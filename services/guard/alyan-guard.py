#!/usr/bin/env python3
"""
Alyan Webpanel — Real-Time 2s Quota, Exact Real-IP & Strict IP-Limit Enforcer (alyan-guard)
Continuously monitors SSH/Dropbear/WS-Proxy (/alyan) & Xray (VLESS/VMess/Trojan):
  1. Correlates Dropbear (-E short-iso journal) & OpenSSH PIDs -> Username -> Exact Real Client IP.
  2. Parses Xray client IPs cleanly via ipaddress (stripping :port, normalizing IPv6 /64 & CDN edges).
  3. Counts real-time SSH & Xray per-user bytes into SQLite every 2s.
  4. Strictly enforces GB quotas, expiry dates, and IP limits (auto-disabling violating SSH & Xray accounts!).
  5. Writes /run/alyan-live.json every 2s (including cached daemon health) for ultra-fast Webpanel sync.
"""
import datetime as dt
import ipaddress
import json
import os
import re
import socket
import sqlite3
import subprocess
import time
import urllib.request
from pathlib import Path

DB_PATH = Path("/var/lib/alyan/alyan.db")
WSD_STATE = Path("/run/alyan-wsd-sessions.json")
HAPROXY_SOCK = Path("/run/haproxy/admin.sock")
LIVE_OUT = Path("/run/alyan-live.json")
XRAY_ACCESS_LOG = Path("/var/log/xray/access.log")

MANAGED_SERVICES = [
    ("haproxy",     "HAProxy Flame Router", "Public 80 / 443 Multiplexer"),
    ("nginx",       "Nginx Router & TLS",   "WS / gRPC / Panel HTTPS"),
    ("dropbear",    "Dropbear SSH",         "Direct Tunnel Ports 109 / 143"),
    ("alyan-wsd",   "Alyan WS-Proxy",       "GET /alyan 101 + Real-IP Bridge"),
    ("xray",        "Xray-Core Engine",     "VMess · VLESS · Trojan · XHTTP"),
    ("alyan-guard", "Alyan Guard",          "GB Quota · Expiry · IP Enforcer"),
    ("alyan-bot",   "Telegram Bot",         "Full User & Server Control"),
    ("alyan-panel", "Alyan Webpanel",       "FastAPI Command Deck"),
]

CF_EDGE_NETS = [
    ipaddress.ip_network(cidr)
    for cidr in (
        "173.245.48.0/20",
        "103.21.244.0/22",
        "103.22.200.0/22",
        "103.31.4.0/22",
        "141.101.64.0/18",
        "108.162.192.0/18",
        "190.93.240.0/20",
        "188.114.96.0/20",
        "197.234.240.0/22",
        "198.41.128.0/17",
        "162.158.0.0/15",
        "104.16.0.0/13",
        "104.24.0.0/14",
        "172.64.0.0/13",
        "131.0.72.0/22",
        "2400:cb00::/32",
        "2606:4700::/32",
        "2803:f800::/32",
        "2405:b500::/32",
        "2405:8100::/32",
        "2a06:98c0::/29",
        "2c0f:f248::/32",
    )
]

HIST = {"cpu": [], "ram": [], "rx": [], "tx": []}
LAST_CPU = None
LAST_NET = None
CACHED_SERVICES: list[dict] = []
CYCLE_TICK = 0

# Persistent tracking caches across 2-second ticks
PID_AUTH_CACHE: dict[int, str] = {}
PORT_TO_USER: dict[str, str] = {}
WSD_PORT_LAST_BYTES: dict[str, int] = {}
PID_LAST_IO_BYTES: dict[int, int] = {}
# uuid -> {device_key: {"ip": str, "ts": float}}
XRAY_ACTIVE_DEVICES: dict[str, dict[str, dict]] = {}

# Consecutive multi-IP violation strikes before auto-disable
SSH_IP_STRIKES: dict[str, int] = {}
XRAY_IP_STRIKES: dict[str, int] = {}

DROPBEAR_AUTH_RE = re.compile(
    r"(?:dropbear\[(\d+)\]|\[(\d+)\]).*?(?:Password|Pubkey) auth succeeded for '([^']+)'",
    re.IGNORECASE,
)
SSHD_AUTH_RE = re.compile(
    r"sshd(?:-session)?\[(\d+)\]:\s+Accepted\s+\S+\s+for\s+(\S+)\s+from",
    re.IGNORECASE,
)
XRAY_EMAIL_RE = re.compile(r"email:\s*([^\s@]+)@alyan", re.IGNORECASE)
XRAY_FROM_RAW_RE = re.compile(r"\bfrom\s+(?:tcp:|udp:)?(\S+)\s+accepted\b", re.IGNORECASE)


def db_conn():
    conn = sqlite3.connect(str(DB_PATH), timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    return conn


def clean_public_ip(raw_token: str) -> str | None:
    """Extract and validate a clean IP address (without :port), ignoring loopback/unspecified."""
    s = (raw_token or "").strip()
    if not s:
        return None
    if s.startswith("["):
        end = s.find("]")
        if end == -1:
            return None
        cand = s[1:end]
    elif s.count(":") == 1:
        cand = s.split(":", 1)[0]
    else:
        cand = s
        try:
            ipaddress.ip_address(cand)
        except ValueError:
            if ":" in cand:
                cand = cand.rsplit(":", 1)[0]
    if cand.lower().startswith("::ffff:"):
        cand = cand[7:]
    try:
        ip_obj = ipaddress.ip_address(cand)
        if ip_obj.is_loopback or ip_obj.is_unspecified or ip_obj.is_link_local:
            return None
        return str(ip_obj)
    except ValueError:
        return None


def device_key_for_ip(ip_str: str) -> str:
    """
    Normalize a client IP to a unique device key:
      - Unwrapped Cloudflare Anycast edge IPs collapse to 'cf-edge' so PoP rotation never fakes 30 IPs.
      - IPv6 SLAAC privacy extensions collapse to their /64 subscriber prefix so 1 mobile phone = 1 device.
      - Standard public IPv4 maps 1:1 to itself.
    """
    try:
        addr = ipaddress.ip_address(ip_str)
        if any(addr in net for net in CF_EDGE_NETS):
            return "cf-edge"
        if isinstance(addr, ipaddress.IPv6Address):
            net64 = ipaddress.IPv6Network((addr, 64), strict=False)
            return f"v6:{net64.network_address}/64"
        return str(addr)
    except ValueError:
        return ip_str


def parse_xray_source_ip(line: str) -> tuple[str | None, bool]:
    """Return (public_ip_or_None, was_loopback) from an Xray access.log 'accepted' line."""
    m = XRAY_FROM_RAW_RE.search(line)
    if not m:
        return None, False
    tok = m.group(1).strip()
    if tok.startswith(("127.0.0.1", "[::1]", "::1")):
        return None, True
    ip_clean = clean_public_ip(tok)
    return ip_clean, False


def read_cpu_pct() -> int:
    global LAST_CPU
    try:
        parts = [int(x) for x in Path("/proc/stat").read_text().splitlines()[0].split()[1:9]]
        idle = parts[3] + parts[4]
        total = sum(parts)
        if LAST_CPU is None:
            LAST_CPU = (idle, total)
            return 6
        d_idle = idle - LAST_CPU[0]
        d_tot = max(1, total - LAST_CPU[1])
        LAST_CPU = (idle, total)
        return max(1, min(99, int(round((1.0 - d_idle / d_tot) * 100))))
    except Exception:
        return 5


def read_ram_pct() -> int:
    try:
        vals = {}
        for ln in Path("/proc/meminfo").read_text().splitlines():
            if ":" in ln:
                k, v = ln.split(":", 1)
                vals[k.strip()] = int(v.strip().split()[0])
        tot = max(1, vals.get("MemTotal", 1))
        avail = vals.get("MemAvailable", vals.get("MemFree", 0))
        return max(1, min(99, int(round(((tot - avail) / tot) * 100))))
    except Exception:
        return 18


def read_net_rates(iface: str):
    global LAST_NET
    now = time.monotonic()
    rx_tot, tx_tot = 0, 0
    try:
        for ln in Path("/proc/net/dev").read_text().splitlines()[2:]:
            if ":" not in ln:
                continue
            name, rest = ln.split(":", 1)
            name = name.strip()
            if name == "lo":
                continue
            cols = rest.split()
            if name == iface or rx_tot == 0:
                rx_tot = int(cols[0])
                tx_tot = int(cols[8])
                if name == iface:
                    break
    except Exception:
        pass
    if LAST_NET is None:
        LAST_NET = (now, rx_tot, tx_tot)
        return 0.0, 0.0, rx_tot, tx_tot
    dt_s = max(0.4, now - LAST_NET[0])
    rx_bps = max(0.0, (rx_tot - LAST_NET[1]) / dt_s)
    tx_bps = max(0.0, (tx_tot - LAST_NET[2]) / dt_s)
    LAST_NET = (now, rx_tot, tx_tot)
    return rx_bps, tx_bps, rx_tot, tx_tot


def fmt_mem(mem_bytes: int) -> str:
    if mem_bytes <= 0 or mem_bytes >= (1 << 60):
        return "—"
    mb = mem_bytes / 1048576.0
    return f"{mb / 1024.0:.1f} GB" if mb >= 1024 else f"{mb:.1f} MB"


def fmt_mono_uptime(enter_usec: int) -> str:
    if enter_usec <= 0:
        return "—"
    try:
        secs = max(0, (int(time.monotonic() * 1_000_000) - enter_usec) // 1_000_000)
        d, rem = divmod(secs, 86400)
        h, rem = divmod(rem, 3600)
        m, _ = divmod(rem, 60)
        if d > 0:
            return f"{d}d {h}h"
        if h > 0:
            return f"{h}h {m}m"
        return f"{max(1, m)}m"
    except Exception:
        return "active"


def collect_services_fast() -> list[dict]:
    unit_ids = [s[0] for s in MANAGED_SERVICES]
    props_by_id: dict[str, dict[str, str]] = {u: {} for u in unit_ids}
    try:
        out = subprocess.check_output(
            [
                "systemctl",
                "show",
                *unit_ids,
                "--property=Id,ActiveState,MemoryCurrent,ActiveEnterTimestampMonotonic",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        for block in out.strip().split("\n\n"):
            kv = {}
            for ln in block.splitlines():
                if "=" in ln:
                    k, v = ln.split("=", 1)
                    kv[k] = v
            uid = kv.get("Id", "").removesuffix(".service")
            if uid in props_by_id:
                props_by_id[uid] = kv
    except Exception:
        pass

    res = []
    for sid, name, desc in MANAGED_SERVICES:
        kv = props_by_id.get(sid, {})
        status = "running" if kv.get("ActiveState") in ("active", "reloading") else "stopped"
        try:
            mem_val = int(kv.get("MemoryCurrent", "0"))
        except ValueError:
            mem_val = 0
        try:
            mono_val = int(kv.get("ActiveEnterTimestampMonotonic", "0"))
        except ValueError:
            mono_val = 0
        res.append(
            {
                "id": sid,
                "name": name,
                "desc": desc,
                "status": status,
                "mem": fmt_mem(mem_val) if status == "running" else "—",
                "uptime": fmt_mono_uptime(mono_val) if status == "running" else "—",
            }
        )
    return res


def refresh_auth_pid_cache(canon_users: dict[str, str]):
    """Scan recent Dropbear & OpenSSH journal entries (-o short-iso keeps PID tags!) to map worker PID -> user."""
    for dead in [p for p in PID_AUTH_CACHE if not Path(f"/proc/{p}").exists()]:
        PID_AUTH_CACHE.pop(dead, None)

    lines: list[str] = []
    try:
        out = subprocess.check_output(
            ["journalctl", "-u", "dropbear", "-u", "ssh", "-u", "sshd", "-n", "400", "--no-pager", "-o", "short-iso"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=2.5,
        )
        lines.extend(out.splitlines())
    except Exception:
        pass

    auth_log = Path("/var/log/auth.log")
    if auth_log.exists():
        try:
            with auth_log.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 32768))
                lines.extend(f.read().decode("utf-8", errors="ignore").splitlines()[-250:])
        except Exception:
            pass

    for ln in lines:
        m_db = DROPBEAR_AUTH_RE.search(ln)
        if m_db:
            pid_s = m_db.group(1) or m_db.group(2)
            if pid_s:
                pid = int(pid_s)
                u_low = m_db.group(3).lower()
                if u_low in canon_users and Path(f"/proc/{pid}").exists():
                    PID_AUTH_CACHE[pid] = canon_users[u_low]
            continue
        m_sh = SSHD_AUTH_RE.search(ln)
        if m_sh:
            pid = int(m_sh.group(1))
            u_low = m_sh.group(2).lower()
            if u_low in canon_users and Path(f"/proc/{pid}").exists():
                PID_AUTH_CACHE[pid] = canon_users[u_low]


def query_haproxy_sessions() -> tuple[dict[str, str], list[str]]:
    """
    Query HAProxy admin socket once per cycle:
      - loopback_map: 127.0.0.1:<ephemeral_port> -> real public client IP (for SSH-SSL :443 -> Dropbear)
      - h2c_ips: active public client IPs on be_nginx_h2c (fallback for gRPC streams if XFF wasn't logged)
    """
    loopback_map: dict[str, str] = {}
    h2c_ips: list[str] = []
    if not HAPROXY_SOCK.exists():
        return loopback_map, h2c_ips
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.45)
            s.connect(str(HAPROXY_SOCK))
            s.sendall(b"show sess all\n")
            chunks = []
            while True:
                buf = s.recv(32768)
                if not buf:
                    break
                chunks.append(buf)
        raw = b"".join(chunks).decode("latin1", errors="ignore")
        for block in re.split(r"(?m)^0x[0-9a-fA-F]+:", raw):
            m_src = re.search(r"(?:src=|addr=)([0-9a-fA-F\.:]+):\d+", block)
            if not m_src:
                continue
            ip = clean_public_ip(m_src.group(1))
            if not ip:
                continue
            if "be=be_nginx_h2c" in block and ip not in h2c_ips:
                h2c_ips.append(ip)
            for m_lp in re.finditer(r"127\.0\.0\.1:(\d+)", block):
                lp = m_lp.group(1)
                if lp not in ("109", "143", "22", "2095", "4443", "8880", "8881", "10023"):
                    loopback_map[lp] = ip
    except Exception:
        pass
    return loopback_map, h2c_ips


def pid_to_username(pid: int, uid_map: dict[int, str], canon_users: dict[str, str]) -> str | None:
    if pid in PID_AUTH_CACHE:
        return PID_AUTH_CACHE[pid]
    try:
        status_txt = Path(f"/proc/{pid}/status").read_text()
        ppid = 0
        for line in status_txt.splitlines():
            if line.startswith("PPid:"):
                ppid = int(line.split()[1])
            elif line.startswith("Uid:"):
                for u in (int(x) for x in line.split()[1:5]):
                    if u in uid_map:
                        PID_AUTH_CACHE[pid] = uid_map[u]
                        return uid_map[u]
        if ppid and ppid in PID_AUTH_CACHE:
            PID_AUTH_CACHE[pid] = PID_AUTH_CACHE[ppid]
            return PID_AUTH_CACHE[ppid]

        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\x00", b" ").decode("latin1", errors="ignore")
        m = re.search(r"sshd(?:-session)?:\s*([A-Za-z0-9_-]+)", cmdline)
        if m and m.group(1).lower() in canon_users:
            resolved = canon_users[m.group(1).lower()]
            PID_AUTH_CACHE[pid] = resolved
            return resolved
    except Exception:
        pass
    return None


def read_pid_io_bytes(pid: int) -> int:
    try:
        rchar, wchar = 0, 0
        for ln in Path(f"/proc/{pid}/io").read_text().splitlines():
            if ln.startswith("rchar:"):
                rchar = int(ln.split()[1])
            elif ln.startswith("wchar:"):
                wchar = int(ln.split()[1])
        return (rchar + wchar) // 2
    except Exception:
        return 0


def scan_ssh_sessions(managed_users: set[str], hap_loop_ips: dict[str, str]) -> tuple[dict[str, list[dict]], dict[str, int]]:
    canon_users = {u.lower(): u for u in managed_users}
    refresh_auth_pid_cache(canon_users)

    uid_map: dict[int, str] = {}
    try:
        for line in Path("/etc/passwd").read_text().splitlines():
            parts = line.split(":")
            if len(parts) >= 4 and parts[0].lower() in canon_users:
                uid_map[int(parts[2])] = canon_users[parts[0].lower()]
    except Exception:
        pass

    wsd_map: dict[str, dict] = {}
    if WSD_STATE.exists():
        try:
            wsd_map = json.loads(WSD_STATE.read_text(encoding="utf-8"))
        except Exception:
            wsd_map = {}

    sessions_by_user: dict[str, list[dict]] = {u: [] for u in managed_users}
    deltas: dict[str, int] = {u: 0 for u in managed_users}
    active_pids: set[int] = set()

    try:
        out = subprocess.check_output(["ss", "-tnp"], text=True, stderr=subprocess.DEVNULL, timeout=2.5)
    except Exception:
        out = ""

    for line in out.splitlines():
        if "ESTAB" not in line:
            continue
        if "dropbear" not in line and "sshd" not in line:
            continue
        cols = line.split()
        if len(cols) < 5:
            continue
        local_ep, peer_ep = cols[3], cols[4]
        lport = local_ep.rsplit(":", 1)[-1]
        if lport not in ("22", "109", "143"):
            continue
        peer_ip, peer_port = peer_ep.rsplit(":", 1)
        peer_ip = peer_ip.strip("[]")
        if peer_ip.startswith("::ffff:"):
            peer_ip = peer_ip[7:]

        pids = [int(x) for x in re.findall(r"pid=(\d+)", line)]
        username = None
        target_pid = None
        for pid in pids:
            u = pid_to_username(pid, uid_map, canon_users)
            if u:
                username = u
                target_pid = pid
                break
        if not username or target_pid is None:
            continue

        active_pids.add(target_pid)
        real_ip = clean_public_ip(peer_ip)

        if peer_ip == "127.0.0.1" and peer_port in wsd_map:
            PORT_TO_USER[peer_port] = username
            real_ip = clean_public_ip(wsd_map[peer_port].get("ip", "")) or "127.0.0.1"
        elif peer_ip == "127.0.0.1" and peer_port in hap_loop_ips:
            real_ip = hap_loop_ips[peer_port]
            cur_io = read_pid_io_bytes(target_pid)
            prev_io = PID_LAST_IO_BYTES.get(target_pid, 0)
            if cur_io > prev_io:
                deltas[username] += (cur_io - prev_io)
            PID_LAST_IO_BYTES[target_pid] = cur_io
        else:
            cur_io = read_pid_io_bytes(target_pid)
            prev_io = PID_LAST_IO_BYTES.get(target_pid, 0)
            if cur_io > prev_io:
                deltas[username] += (cur_io - prev_io)
            PID_LAST_IO_BYTES[target_pid] = cur_io

        if real_ip and real_ip != "127.0.0.1":
            sessions_by_user[username].append(
                {"pid": target_pid, "ip": real_ip, "dev": device_key_for_ip(real_ip)}
            )

    for port, info in wsd_map.items():
        uname = PORT_TO_USER.get(port)
        if not uname or uname not in deltas:
            continue
        cur_b = int(info.get("bytes", 0))
        prev_b = WSD_PORT_LAST_BYTES.get(port, 0)
        if cur_b > prev_b:
            deltas[uname] += (cur_b - prev_b)
        WSD_PORT_LAST_BYTES[port] = cur_b

    for stale_port in list(WSD_PORT_LAST_BYTES.keys()):
        if stale_port not in wsd_map:
            WSD_PORT_LAST_BYTES.pop(stale_port, None)
            PORT_TO_USER.pop(stale_port, None)

    for stale_pid in list(PID_LAST_IO_BYTES.keys()):
        if stale_pid not in active_pids:
            PID_LAST_IO_BYTES.pop(stale_pid, None)

    return sessions_by_user, deltas


def poll_xray_stats_and_ips(
    xray_users: list[sqlite3.Row],
    h2c_ips: list[str],
) -> tuple[dict[str, int], dict[str, list[str]], dict[str, int]]:
    """
    Returns:
      - deltas: uuid -> bytes transferred since last 2s tick
      - ips_by_uuid: uuid -> sorted clean unique client IPs (1 IP per unique device)
      - dev_count_by_uuid: uuid -> count of distinct simultaneously active devices in fresh 14s window
    """
    tag_to_uuid: dict[str, str] = {}
    for r in xray_users:
        tag_to_uuid[f"{r['username'].lower()}.{r['proto'].lower()}"] = r["uuid"]
        tag_to_uuid.setdefault(r["username"].lower(), r["uuid"])

    deltas: dict[str, int] = {}
    if Path("/usr/local/bin/xray").exists():
        try:
            raw = subprocess.check_output(
                ["/usr/local/bin/xray", "api", "statsquery", "--server=127.0.0.1:10085", "-pattern", "user>>>", "-reset"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=3.0,
            )
            data = json.loads(raw) if raw.strip() else {}
            for st in data.get("stat", []):
                parts = st.get("name", "").split(">>>")
                if len(parts) >= 4:
                    tag_low = parts[1].split("@", 1)[0].lower()
                    uid = tag_to_uuid.get(tag_low)
                    if uid:
                        deltas[uid] = deltas.get(uid, 0) + int(st.get("value", 0))
        except Exception:
            pass

    now_ts = time.time()
    now_dt = dt.datetime.now()
    seen_loopback_uids: set[str] = set()
    fresh_window_devs: dict[str, set[str]] = {}

    if XRAY_ACCESS_LOG.exists():
        try:
            with XRAY_ACCESS_LOG.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 65536))
                tail_lines = f.read().decode("utf-8", errors="ignore").splitlines()[-400:]
            for ln in tail_lines:
                if "accepted" not in ln or "email:" not in ln:
                    continue
                m_em = XRAY_EMAIL_RE.search(ln)
                if not m_em:
                    continue
                uid = tag_to_uuid.get(m_em.group(1).lower())
                if not uid:
                    continue
                try:
                    parsed_dt = dt.datetime.strptime(ln[:19], "%Y/%m/%d %H:%M:%S")
                    age = (now_dt - parsed_dt).total_seconds()
                    if age > 16.0 or age < -30.0:
                        continue
                    line_ts = now_ts - max(0.0, age)
                except Exception:
                    continue

                ip_clean, was_loop = parse_xray_source_ip(ln)
                if was_loop:
                    seen_loopback_uids.add(uid)
                    continue
                if not ip_clean:
                    continue

                dev_k = device_key_for_ip(ip_clean)
                dev_map = XRAY_ACTIVE_DEVICES.setdefault(uid, {})
                prev_entry = dev_map.get(dev_k)
                if not prev_entry or line_ts >= prev_entry["ts"]:
                    dev_map[dev_k] = {"ip": ip_clean, "ts": line_ts}
                if (now_ts - line_ts) <= 14.0:
                    fresh_window_devs.setdefault(uid, set()).add(dev_k)
        except Exception:
            pass

    ips_by_uuid: dict[str, list[str]] = {}
    dev_count_by_uuid: dict[str, int] = {}

    for r in xray_users:
        uid = r["uuid"]
        dev_map = XRAY_ACTIVE_DEVICES.setdefault(uid, {})
        active_traffic = deltas.get(uid, 0) > 0

        # If bytes are actively flowing on a long-lived stream without new TCP handshakes,
        # keep ONLY the single most-recent active device alive (never resurrecting old IPs!).
        if active_traffic and dev_map and not fresh_window_devs.get(uid):
            newest_k = max(dev_map.keys(), key=lambda k: dev_map[k]["ts"])
            if now_ts - dev_map[newest_k]["ts"] <= 24.0:
                dev_map[newest_k]["ts"] = now_ts

        # Prune any device idle > 16 seconds
        for stale_k in [k for k, v in dev_map.items() if now_ts - v["ts"] > 16.0]:
            dev_map.pop(stale_k, None)

        # gRPC loopback fallback ONLY from verified HAProxy h2c backend (never random :80/:443 sockets)
        if not dev_map and uid in seen_loopback_uids and h2c_ips:
            first_h2 = h2c_ips[0]
            dev_map[device_key_for_ip(first_h2)] = {"ip": first_h2, "ts": now_ts}

        ips_by_uuid[uid] = sorted({v["ip"] for v in dev_map.values()})
        # For strict IP-limit violation checks, count distinct fresh devices in the 14s window
        dev_count_by_uuid[uid] = len(fresh_window_devs.get(uid, set()))

    return deltas, ips_by_uuid, dev_count_by_uuid


def send_telegram_alert(bot_cfg: dict, message: str):
    if not bot_cfg.get("enabled") or not bot_cfg.get("alerts"):
        return
    token = (bot_cfg.get("token") or "").strip()
    admin_ids = [x.strip() for x in str(bot_cfg.get("admin_id") or "").split(",") if x.strip()]
    if not token or "*" in token or not admin_ids:
        return
    for chat_id in admin_ids:
        try:
            payload = json.dumps({"chat_id": chat_id, "text": f"🔥 *Alyan Guard Alert*\n{message}", "parse_mode": "Markdown"}).encode()
            req = urllib.request.Request(
                f"https://api.telegram.org/bot{token}/sendMessage",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=4).read()
        except Exception:
            pass


def enforce_cycle():
    global CYCLE_TICK, CACHED_SERVICES
    if not DB_PATH.exists():
        return

    CYCLE_TICK += 1
    hap_loop_ips, h2c_ips = query_haproxy_sessions()

    conn = db_conn()
    try:
        settings_rows = {r["key"]: r["value"] for r in conn.execute("SELECT key, value FROM settings").fetchall()}
        iface = settings_rows.get("iface", "eth0")
        bot_cfg = json.loads(settings_rows.get("bot_json", "{}"))

        ssh_rows = conn.execute("SELECT * FROM ssh_users").fetchall()
        xray_rows = conn.execute("SELECT * FROM xray_users").fetchall()

        today = dt.date.today().isoformat()
        managed_ssh = {r["username"] for r in ssh_rows}
        ssh_sessions, ssh_deltas = scan_ssh_sessions(managed_ssh, hap_loop_ips)
        xray_deltas, xray_ips, xray_fresh_devs = poll_xray_stats_and_ips(xray_rows, h2c_ips)

        # ─── 1. Enforce SSH Quotas, Expiry & Strict IP Limit Auto-Disable ───
        for r in ssh_rows:
            uname = r["username"]
            delta_b = int(ssh_deltas.get(uname, 0))
            used = int(r["used_bytes"]) + delta_b
            if delta_b > 0:
                conn.execute("UPDATE ssh_users SET used_bytes = ? WHERE username = ?", (used, uname))

            if r["status"] != "active":
                SSH_IP_STRIKES.pop(uname, None)
                for s in ssh_sessions.get(uname, []):
                    if s.get("pid"):
                        subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                ssh_sessions[uname] = []
                continue

            gb_lim = float(r["gb_limit"] or 0)
            ip_lim = int(r["ip_limit"] or 0)
            conns = ssh_sessions.get(uname, [])
            uniq_devs = sorted({s["dev"] for s in conns if s.get("dev")})
            uniq_ips = sorted({s["ip"] for s in conns if s.get("ip")})

            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"SSH user `{uname}` expired ({r['expiry']})"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"SSH user `{uname}` reached {gb_lim} GB quota"
            elif ip_lim > 0 and len(uniq_devs) > ip_lim:
                SSH_IP_STRIKES[uname] = SSH_IP_STRIKES.get(uname, 0) + 1
                if SSH_IP_STRIKES[uname] >= 2:
                    reason = f"SSH user `{uname}` exceeded IP limit ({len(uniq_ips)}/{ip_lim} IPs) — auto-disabled"
                else:
                    # Immediately terminate excess device sessions on strike 1
                    allowed_devs = set(uniq_devs[:ip_lim])
                    for s in conns:
                        if s["dev"] not in allowed_devs and s.get("pid"):
                            subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                    ssh_sessions[uname] = [s for s in conns if s["dev"] in allowed_devs]
            else:
                SSH_IP_STRIKES.pop(uname, None)

            if reason:
                SSH_IP_STRIKES.pop(uname, None)
                conn.execute("UPDATE ssh_users SET status = 'disabled' WHERE username = ?", (uname,))
                conn.execute(
                    "INSERT INTO audit_log (created_at, actor, action, detail, ip) VALUES (?, 'alyan-guard', 'auto_disable', ?, 'local')",
                    (dt.datetime.now().strftime("%H:%M:%S"), reason),
                )
                subprocess.run(["usermod", "-L", uname], stderr=subprocess.DEVNULL)
                subprocess.run(["pkill", "-KILL", "-u", uname], stderr=subprocess.DEVNULL)
                for s in ssh_sessions.get(uname, []):
                    if s.get("pid"):
                        subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                ssh_sessions[uname] = []
                send_telegram_alert(bot_cfg, reason)

        # ─── 2. Enforce Xray Quotas, Expiry & Strict IP Limit Auto-Disable ───
        xray_resync_needed = False
        for r in xray_rows:
            uname = r["username"]
            uuid = r["uuid"]
            delta_x = int(xray_deltas.get(uuid, 0))
            used = int(r["used_bytes"]) + delta_x
            if delta_x > 0:
                conn.execute("UPDATE xray_users SET used_bytes = ? WHERE uuid = ?", (used, uuid))

            if r["status"] != "active":
                XRAY_IP_STRIKES.pop(uuid, None)
                XRAY_ACTIVE_DEVICES.pop(uuid, None)
                xray_ips[uuid] = []
                continue

            gb_lim = float(r["gb_limit"] or 0)
            ip_lim = int(r["ip_limit"] or 0)
            cur_ips = xray_ips.get(uuid, [])
            fresh_devs = xray_fresh_devs.get(uuid, 0)

            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) expired"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) reached {gb_lim} GB quota"
            elif ip_lim > 0 and fresh_devs > ip_lim and len(cur_ips) > ip_lim:
                XRAY_IP_STRIKES[uuid] = XRAY_IP_STRIKES.get(uuid, 0) + 1
                if XRAY_IP_STRIKES[uuid] >= 3:
                    reason = f"Xray client `{uname}` ({r['proto'].upper()}) exceeded IP limit ({len(cur_ips)}/{ip_lim} IPs) — auto-disabled"
            else:
                XRAY_IP_STRIKES.pop(uuid, None)

            if reason:
                XRAY_IP_STRIKES.pop(uuid, None)
                XRAY_ACTIVE_DEVICES.pop(uuid, None)
                conn.execute("UPDATE xray_users SET status = 'disabled' WHERE uuid = ?", (uuid,))
                conn.execute(
                    "INSERT INTO audit_log (created_at, actor, action, detail, ip) VALUES (?, 'alyan-guard', 'xray_disable', ?, 'local')",
                    (dt.datetime.now().strftime("%H:%M:%S"), reason),
                )
                xray_ips[uuid] = []
                xray_resync_needed = True
                send_telegram_alert(bot_cfg, reason)

        conn.commit()
    finally:
        conn.close()

    if xray_resync_needed and Path("/usr/local/bin/alyan-ctl").exists():
        subprocess.run(["/usr/local/bin/alyan-ctl", "xray-sync"], stderr=subprocess.DEVNULL)

    # ─── 3. Record Rolling Telemetry & Fast Snapshot ─────────────────────────
    cpu_pct = read_cpu_pct()
    ram_pct = read_ram_pct()
    rx_bps, tx_bps, rx_tot, tx_tot = read_net_rates(iface)

    HIST["cpu"] = (HIST["cpu"] + [cpu_pct])[-20:]
    HIST["ram"] = (HIST["ram"] + [ram_pct])[-20:]
    HIST["rx"] = (HIST["rx"] + [round((rx_bps * 8) / 1048576.0, 2)])[-20:]
    HIST["tx"] = (HIST["tx"] + [round((tx_bps * 8) / 1048576.0, 2)])[-20:]

    if not CACHED_SERVICES or (CYCLE_TICK % 2 == 0):
        CACHED_SERVICES = collect_services_fast()

    ssh_live = {}
    for uname, conns in ssh_sessions.items():
        ips = sorted({c["ip"] for c in conns if c.get("ip")})
        ssh_live[uname] = {"online": len(ips) if ips else len(conns), "ips": ips}

    xray_live = {}
    for r in xray_rows:
        uid = r["uuid"]
        ips = xray_ips.get(uid, [])
        xray_live[uid] = {"online": len(ips), "ips": ips}

    snapshot = {
        "updated_at": int(time.time()),
        "cpu_pct": cpu_pct,
        "ram_pct": ram_pct,
        "rx_bps": rx_bps,
        "tx_bps": tx_bps,
        "rx_total": rx_tot,
        "tx_total": tx_tot,
        "hist": HIST,
        "services": CACHED_SERVICES,
        "ssh_live": ssh_live,
        "xray_live": xray_live,
    }
    tmp = LIVE_OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(snapshot), encoding="utf-8")
    os.chmod(tmp, 0o644)
    tmp.replace(LIVE_OUT)


def main():
    while True:
        try:
            enforce_cycle()
        except Exception:
            pass
        time.sleep(2.0)


if __name__ == "__main__":
    main()

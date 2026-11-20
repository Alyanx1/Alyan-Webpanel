#!/usr/bin/env python3
"""
Alyan Webpanel — Real-Time Quota, Exact Real-IP & Option-1 Disconnect Enforcer (alyan-guard)
Continuously monitors SSH/Dropbear/WS-Proxy (/alyan) & Xray (VLESS/VMess/Trojan):
  1. Correlates Dropbear (-E short-iso journal) & OpenSSH PIDs -> Username -> Exact Real Client IP.
  2. Option-1 VLESS/VMess/Trojan Engine:
     - Closes ONLY blocked UDP sockets (`bytes_sent <= 140` after 1.0s) individually so Xray
       never holds 60-second blackholed UDP streams in OnlineMap.
     - NEVER touches active TCP streams (`bytes_sent > 140`) while browsing, buffering YouTube,
       or sitting idle (100% zero Online/Offline blink!).
     - Uses Linux kernel `lastsnd`/`lastrcv` + Nginx close-burst (`recent_burst_cnt >= active_sockets`
       when all remaining sockets have been completely idle for >=1.2s) to detect full VPN
       disconnects in 1-2s even if Cloudflare CDN holds 3-6 old zombie sockets open!
  3. Counts real-time SSH & Xray per-user bytes into SQLite.
  4. Strictly enforces GB quotas, expiry dates, and user limits (auto-disabling violating accounts).
  5. Writes /run/alyan-live.json every 0.5s for ultra-fast Webpanel sync.
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
NGINX_XRAY_LOG = Path("/var/log/nginx/alyan-xray.log")

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
        "141.193.213.0/24",
        "151.101.0.0/16",
        "199.232.0.0/16",
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

PID_AUTH_CACHE: dict[int, str] = {}
PORT_TO_USER: dict[str, str] = {}
WSD_PORT_LAST_BYTES: dict[str, int] = {}
PID_LAST_IO_BYTES: dict[int, int] = {}
XRAY_ACTIVE_DEVICES: dict[str, dict[str, dict]] = {}

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
XRAY_FROM_RAW_RE = re.compile(
    r"(?:\bfrom\s+)?(?:tcp:|udp:)?(\[[0-9a-fA-F:]+\]:[0-9]+|[0-9a-fA-F\.:]+:[0-9]+|[0-9\.]+)\s+accepted\s+(?:tcp|udp):",
    re.IGNORECASE,
)


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


CLOUDFRONT_PREFIXES = (
    "143.204.", "52.84.", "54.192.", "54.230.", "54.239.", "54.240.",
    "13.32.", "13.33.", "13.35.", "13.224.", "13.225.", "13.226.", "13.227.", "13.249.",
    "18.64.", "18.65.", "18.66.", "18.67.", "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.",
    "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.",
    "108.138.", "108.156.", "108.157.", "108.158.", "108.159.", "204.246.", "205.251.",
)
XRAY_LOG_TS_RE = re.compile(r"^(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2})(?:\.(\d+))?")

XRAY_SESSIONS: dict[str, dict[str, dict]] = {}
XRAY_SESSION_SEQ: dict[str, int] = {}
XRAY_ONLINE_ALL_SUPPORTED = False
PREV_PROTO_ONLINE: dict[str, int] = {"vless": 0, "vmess": 0, "trojan": 0}
UDP_KILL_TS_LIST: list[float] = []
LAST_ACCEPT_BY_UID_NET: dict[str, dict[str, float]] = {}
REAL_TCP_CLOSE_MONO: dict[str, list[float]] = {"vless": [], "vmess": [], "trojan": []}


def is_trusted_cdn(ip_str: str) -> bool:
    """Return True if ip_str belongs to a known CDN/reverse-proxy edge network."""
    try:
        addr = ipaddress.ip_address(ip_str)
        if addr.is_loopback or addr.is_private or addr.is_unspecified or addr.is_link_local:
            return True
        if any(addr in net for net in CF_EDGE_NETS):
            return True
        if isinstance(addr, ipaddress.IPv4Address) and str(addr).startswith(CLOUDFRONT_PREFIXES):
            return True
        return False
    except ValueError:
        return False


def ip_family_and_prefixes(ip_str: str) -> tuple[int, str, str]:
    addr = ipaddress.ip_address(ip_str)
    if isinstance(addr, ipaddress.IPv4Address):
        net16 = ipaddress.IPv4Network((addr, 16), strict=False)
        net12 = ipaddress.IPv4Network((addr, 12), strict=False)
        return 4, f"v4:{net16.network_address}/16", f"v4s:{net12.network_address}/12"
    net56 = ipaddress.IPv6Network((addr, 56), strict=False)
    net48 = ipaddress.IPv6Network((addr, 48), strict=False)
    return 6, f"v6:{net56.network_address}/56", f"v6s:{net48.network_address}/48"


def parse_xray_log_ts(line: str) -> float | None:
    """Parse YYYY/MM/DD HH:MM:SS.ffffff timestamp at the beginning of an Xray access.log line."""
    m = XRAY_LOG_TS_RE.match(line.strip())
    if not m:
        return None
    try:
        base_ts = dt.datetime.strptime(m.group(1), "%Y/%m/%d %H:%M:%S").timestamp()
        frac = float(f"0.{m.group(2)}") if m.group(2) else 0.0
        return base_ts + frac
    except Exception:
        return None


def device_key_for_ip(ip_str: str) -> str:
    if is_trusted_cdn(ip_str):
        return "cdn-edge"
    try:
        _, net_k, _ = ip_family_and_prefixes(ip_str)
        return net_k
    except ValueError:
        return ip_str


def read_nginx_ws_close_timestamps(lookback_sec: float = 30.0) -> dict[str, list[float]]:
    """
    Read recent WebSocket close timestamps from `/var/log/nginx/alyan-xray.log`,
    ignoring any close line triggered by our own blocked-UDP socket cleanup (`UDP_KILL_TS_LIST`).
    """
    global UDP_KILL_TS_LIST
    closes: dict[str, list[float]] = {}
    if not NGINX_XRAY_LOG.exists():
        return closes
    now_ts = time.time()
    UDP_KILL_TS_LIST = [kt for kt in UDP_KILL_TS_LIST if (now_ts - kt) <= 30.0]

    try:
        with NGINX_XRAY_LOG.open("rb") as f:
            f.seek(0, os.SEEK_END)
            sz = f.tell()
            f.seek(max(0, sz - 49152))
            lines = f.read().decode("utf-8", errors="ignore").splitlines()[-160:]
        for ln in lines:
            parts = ln.strip().split()
            if len(parts) < 4:
                continue
            try:
                log_ts = float(parts[0])
            except ValueError:
                continue
            if (now_ts - log_ts) > lookback_sec or (now_ts - log_ts) < -5.0:
                continue
            # Ignore Nginx close log entries caused by closing a blocked UDP socket
            if any(abs(log_ts - kt) <= 0.25 for kt in UDP_KILL_TS_LIST):
                continue
            ip_clean = clean_public_ip(parts[1])
            if not ip_clean or is_trusted_cdn(ip_clean):
                continue
            try:
                _, net_k, _ = ip_family_and_prefixes(ip_clean)
            except ValueError:
                continue
            closes.setdefault(net_k, []).append(log_ts)
    except Exception:
        pass
    return closes


def parse_xray_source_ip(line: str) -> tuple[str | None, bool, bool]:
    """Return (public_ip_or_None, was_loopback, is_udp) from an Xray access.log 'accepted' line."""
    low = line.lower()
    is_udp = "accepted udp:" in low
    m = XRAY_FROM_RAW_RE.search(line)
    if not m:
        return None, False, is_udp
    tok = m.group(1).strip()
    if tok.startswith(("127.0.0.1", "[::1]", "::1")):
        return None, True, is_udp
    ip_clean = clean_public_ip(tok)
    return ip_clean, (ip_clean is None), is_udp


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
    dt_s = max(0.35, now - LAST_NET[0])
    rx_bps = max(0.0, (rx_tot - LAST_NET[1]) / dt_s)
    tx_bps = max(0.0, (tx_tot - LAST_NET[2]) / dt_s)
    LAST_NET = (now, rx_tot, tx_tot)
    return rx_bps, tx_bps, rx_tot, tx_tot


def fmt_mem(mem_bytes: int) -> str:
    if mem_bytes <= 0 or mem_bytes >= (1 << 60):
        return "—"
    mb = mem_bytes / 1048576.0
    return f"{mb / 1024.0:.2f} GB" if mb >= 1024 else f"{mb:.2f} MB"


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
        return f"{m}m"
    except Exception:
        return "—"


def collect_services_fast() -> list[dict]:
    units = [f"{u}.service" for u, _, _ in MANAGED_SERVICES]
    props: dict[str, dict[str, str]] = {u: {} for u, _, _ in MANAGED_SERVICES}
    try:
        out = subprocess.check_output(
            [
                "systemctl",
                "show",
                *units,
                "--property=Id,ActiveState,MemoryCurrent,ActiveEnterTimestampMonotonic",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=3.0,
        )
        cur_id = None
        for block in out.strip().split("\n\n"):
            kv = {}
            for ln in block.splitlines():
                if "=" in ln:
                    k, v = ln.split("=", 1)
                    kv[k] = v
            raw_id = kv.get("Id", "")
            if raw_id.endswith(".service"):
                cur_id = raw_id[:-8]
                if cur_id in props:
                    props[cur_id] = kv
    except Exception:
        pass

    result = []
    for unit_id, name, desc in MANAGED_SERVICES:
        kv = props.get(unit_id, {})
        active = kv.get("ActiveState", "") == "active"
        mem_raw = kv.get("MemoryCurrent", "0")
        enter_raw = kv.get("ActiveEnterTimestampMonotonic", "0")
        try:
            mem_b = int(mem_raw) if mem_raw.isdigit() else 0
        except ValueError:
            mem_b = 0
        try:
            enter_u = int(enter_raw) if enter_raw.isdigit() else 0
        except ValueError:
            enter_u = 0
        result.append(
            {
                "id": unit_id,
                "name": name,
                "desc": desc,
                "status": "running" if active else "stopped",
                "mem": fmt_mem(mem_b) if active else "—",
                "uptime": fmt_mono_uptime(enter_u) if active else "—",
            }
        )
    return result


def query_haproxy_sessions() -> tuple[dict[str, str], dict[str, str], list[str], list[str], list[str]]:
    loop_port_to_ip: dict[str, str] = {}
    xray_port_to_ip: dict[str, str] = {}
    ws_ips: list[str] = []
    h2c_ips: list[str] = []
    trojan_ips: list[str] = []

    if not HAPROXY_SOCK.exists():
        return loop_port_to_ip, xray_port_to_ip, ws_ips, h2c_ips, trojan_ips

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1.5)
        s.connect(str(HAPROXY_SOCK))
        s.sendall(b"show sess all\n")
        chunks = []
        while True:
            data = s.recv(65536)
            if not data:
                break
            chunks.append(data)
        s.close()
        raw = b"".join(chunks).decode("utf-8", errors="ignore")

        blocks = re.split(r"(?=^0x[0-9a-fA-F]+:)", raw, flags=re.MULTILINE)
        parsed_blocks: list[tuple[str, str, str, list[str]]] = []
        tls_loop_map: dict[str, str] = {}

        for blk in blocks:
            if not blk.strip():
                continue
            m_src = re.search(r"\b(?:source|src)=([^\s]+)", blk)
            m_be = re.search(r"\b(?:backend|be)=([^\s\(]+)", blk)
            if not m_src or not m_be:
                continue
            src_tok = m_src.group(1).strip()
            be_name = m_be.group(1).strip()
            lports = [
                m.group(1)
                for m in re.finditer(r"127\.0\.0\.1:(\d+)", blk)
                if m.group(1) not in ("109", "143", "22", "2095", "4443", "8880", "8881", "8882", "8883", "8443", "10001", "10002", "10003", "10011", "10012", "10013", "10023", "10031")
            ]
            src_port = src_tok.rsplit(":", 1)[-1] if ":" in src_tok else ""
            c_ip = clean_public_ip(src_tok)
            if be_name == "be_tls_loop" and c_ip:
                for lp in lports:
                    tls_loop_map[lp] = c_ip
            parsed_blocks.append((src_tok, src_port, be_name, lports))

        for src_tok, src_port, be_name, lports in parsed_blocks:
            client_ip = clean_public_ip(src_tok)
            if not client_ip and src_tok.startswith("127.0.0.1:") and src_port in tls_loop_map:
                client_ip = tls_loop_map[src_port]
            if not client_ip:
                continue

            if be_name in ("be_ssh_dropbear", "be_ssh_openssh", "be_dropbear"):
                for lp in lports:
                    loop_port_to_ip[lp] = client_ip
                if not lports:
                    loop_port_to_ip[f" fallback_{client_ip}"] = client_ip
            elif be_name in (
                "be_xray_vless_ws",
                "be_xray_vmess_ws",
                "be_xray_trojan_ws",
                "be_xray_vless_xhttp",
                "be_xray_mux",
                "be_ws_http",
                "be_nginx_ws",
                "be_tls_loop",
            ):
                if client_ip not in ws_ips:
                    ws_ips.append(client_ip)
                if not is_trusted_cdn(client_ip):
                    for lp in lports:
                        xray_port_to_ip[lp] = client_ip
            elif be_name in (
                "be_xray_vless_grpc",
                "be_xray_vmess_grpc",
                "be_xray_trojan_grpc",
                "be_xray_h2c",
                "be_grpc_h2c",
                "be_nginx_h2c",
            ):
                if client_ip not in h2c_ips:
                    h2c_ips.append(client_ip)
                if not is_trusted_cdn(client_ip):
                    for lp in lports:
                        xray_port_to_ip[lp] = client_ip
            elif be_name in ("be_xray_trojan_tcp", "be_trojan_tcp"):
                if client_ip not in trojan_ips:
                    trojan_ips.append(client_ip)
                if not is_trusted_cdn(client_ip):
                    for lp in lports:
                        xray_port_to_ip[lp] = client_ip
    except Exception:
        pass

    return loop_port_to_ip, xray_port_to_ip, ws_ips, h2c_ips, trojan_ips


def refresh_ssh_auth_cache():
    try:
        out = subprocess.check_output(
            [
                "journalctl",
                "-u", "dropbear",
                "-u", "ssh",
                "-u", "sshd",
                "--since", "24 hours ago",
                "-n", "600",
                "--no-pager",
                "-o", "cat",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=2.5,
        )
        for ln in out.splitlines():
            m = DROPBEAR_AUTH_RE.search(ln)
            if m:
                pid_str = m.group(1) or m.group(2)
                if pid_str:
                    PID_AUTH_CACHE[int(pid_str)] = m.group(3)
                continue
            m2 = SSHD_AUTH_RE.search(ln)
            if m2:
                PID_AUTH_CACHE[int(m2.group(1))] = m2.group(2)
    except Exception:
        pass


def resolve_sshd_proc_user(pid: int, managed_users: set[str]) -> str | None:
    for check_pid in (pid,):
        try:
            cmdline = Path(f"/proc/{check_pid}/cmdline").read_bytes().replace(b"\x00", b" ").decode("utf-8", errors="ignore")
            m = re.search(r"sshd(?:-session)?:\s*([a-zA-Z0-9_\-\.]+)", cmdline)
            if m and m.group(1) in managed_users:
                return m.group(1)
        except Exception:
            pass
    try:
        status_txt = Path(f"/proc/{pid}/status").read_text(encoding="utf-8", errors="ignore")
        for ln in status_txt.splitlines():
            if ln.startswith("PPid:"):
                ppid = int(ln.split(":", 1)[1].strip())
                if ppid > 1:
                    if ppid in PID_AUTH_CACHE and PID_AUTH_CACHE[ppid] in managed_users:
                        return PID_AUTH_CACHE[ppid]
                    cmdline = Path(f"/proc/{ppid}/cmdline").read_bytes().replace(b"\x00", b" ").decode("utf-8", errors="ignore")
                    m = re.search(r"sshd(?:-session)?:\s*([a-zA-Z0-9_\-\.]+)", cmdline)
                    if m and m.group(1) in managed_users:
                        return m.group(1)
    except Exception:
        pass
    return None


def read_pid_io_bytes(pid: int) -> int:
    total = 0
    pids_to_scan = [pid]
    try:
        children = Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
        pids_to_scan.extend(int(c) for c in children if c.isdigit())
    except Exception:
        pass
    for p in pids_to_scan:
        try:
            for ln in Path(f"/proc/{p}/io").read_text().splitlines():
                if ln.startswith(("rchar:", "wchar:")):
                    total += int(ln.split(":", 1)[1].strip())
        except Exception:
            pass
    return total


def scan_ssh_sessions(managed_users: set[str], hap_loop_ips: dict[str, str]):
    auth_refreshed = False
    if CYCLE_TICK == 1 or (CYCLE_TICK % 2 == 0):
        refresh_ssh_auth_cache()
        auth_refreshed = True

    wsd_map: dict[str, dict] = {}
    if WSD_STATE.exists():
        try:
            raw_wsd = json.loads(WSD_STATE.read_text(encoding="utf-8"))
            if isinstance(raw_wsd, dict):
                wsd_map = raw_wsd.get("sessions", raw_wsd) if isinstance(raw_wsd.get("sessions"), dict) else raw_wsd
        except Exception:
            wsd_map = {}

    sessions_by_user: dict[str, list[dict]] = {u: [] for u in managed_users}
    deltas: dict[str, int] = {u: 0 for u in managed_users}
    active_pids: set[int] = set()

    try:
        ss_out = subprocess.check_output(["ss", "-tnp"], text=True, stderr=subprocess.DEVNULL, timeout=2.0)
    except Exception:
        ss_out = ""

    seen_pid_port: set[tuple[int, str]] = set()
    for ln in ss_out.splitlines():
        if "ESTAB" not in ln:
            continue
        if "dropbear" not in ln and "sshd" not in ln:
            continue

        cols = ln.split()
        if len(cols) < 5:
            continue
        local_addr, peer_addr = cols[3], cols[4]
        lport = local_addr.rsplit(":", 1)[-1]
        if lport not in ("109", "143", "22"):
            continue

        peer_ip_raw, peer_port = peer_addr.rsplit(":", 1)
        peer_ip = clean_public_ip(peer_ip_raw) or "127.0.0.1"

        pids = [int(m.group(1)) for m in re.finditer(r"pid=(\d+)", ln)]
        if not pids:
            continue

        username = None
        target_pid = pids[0]
        for pid in pids:
            if pid in PID_AUTH_CACHE and PID_AUTH_CACHE[pid] in managed_users:
                username = PID_AUTH_CACHE[pid]
                target_pid = pid
                break
            u_proc = resolve_sshd_proc_user(pid, managed_users)
            if u_proc:
                username = u_proc
                target_pid = pid
                break

        if not username and not auth_refreshed:
            refresh_ssh_auth_cache()
            auth_refreshed = True
            for pid in pids:
                if pid in PID_AUTH_CACHE and PID_AUTH_CACHE[pid] in managed_users:
                    username = PID_AUTH_CACHE[pid]
                    target_pid = pid
                    break

        if not username:
            continue

        key = (target_pid, peer_port)
        if key in seen_pid_port:
            continue
        seen_pid_port.add(key)

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
            if peer_ip == "127.0.0.1" and hap_loop_ips:
                real_ip = next(iter(hap_loop_ips.values()))
            cur_io = read_pid_io_bytes(target_pid)
            prev_io = PID_LAST_IO_BYTES.get(target_pid, 0)
            if cur_io > prev_io:
                deltas[username] += (cur_io - prev_io)
            PID_LAST_IO_BYTES[target_pid] = cur_io

        sessions_by_user[username].append(
            {"pid": target_pid, "ip": real_ip or "127.0.0.1", "dev": str(real_ip or target_pid)}
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


PROTO_PORTS = {
    "vless": (10001, 10011, 10031),
    "vmess": (10002, 10012),
    "trojan": (10003, 10013, 10023),
}
ALL_XRAY_PORTS = (10001, 10002, 10003, 10011, 10012, 10013, 10023, 10031)
XRAY_LAST_ACTIVE_TS: dict[str, float] = {}
XRAY_SOCKET_RX_STATE: dict[str, dict[str, float | int | str]] = {}
UID_TCP_CLOSE_MONO: dict[str, list[float]] = {}
IP_TCP_CLOSE_MONO: dict[str, list[float]] = {}
SS_RX_BYTES_RE = re.compile(r"\bbytes_received:(\d+)")
SS_TX_BYTES_RE = re.compile(r"\bbytes_sent:(\d+)")
SS_LASTSND_RE = re.compile(r"\blastsnd:(\d+)")
SS_LASTRCV_RE = re.compile(r"\blastrcv:(\d+)")


def scan_active_proto_sockets(
    xray_port_to_ip: dict[str, str],
    accept_events: list[dict],
    om_by_uid: dict[str, list[str]],
    om_ip_ts_by_uid: dict[str, dict[str, int]],
    uuid_to_proto: dict[str, str],
    ip_to_uid: dict[str, str],
) -> tuple[
    dict[str, int],
    dict[str, float],
    dict[str, int],
    dict[str, int],
    dict[str, float],
    dict[str, int],
    dict[tuple[str, str], int],
    dict[tuple[str, str], int],
    dict[str, int],
]:
    """
    Direct HAProxy -> Xray Per-User (`uid`) & Per-Session (`(uid, ip)` / `(uid, net_key)`) Socket Scanner:
      1. Inspects all ESTAB sockets on Xray ports (`ss -tin`).
      2. Attributes each socket (`lport:rport`) to its exact `(uid, ip)` via:
         - HAProxy direct socket table (`xray_port_to_ip[rport]`)
         - Xray access.log `accepted tcp:` timestamp correlation (`birth_ts` & `last_io_ts`)
         - Xray `statsonlineiplist` per-IP activity timestamp (`om_ip_ts_by_uid`)
         - Active single-user `statsonlineiplist` (`om_by_uid`) fallback
      3. Classifies sockets by `bytes_sent` (`tx_b`):
         - `tx_b <= 240` after `1.2s`: Blocked UDP stream closed individually (`ss -K`).
         - `tx_b < 600` with `idle >= 1.2s`: Finished one-shot DNS `:53` query (ignored).
         - `tx_b >= 600` (or nascent `tx_b > 140` with `idle < 1.2s`): Active established TCP
           tunnel counted per-protocol, per-`uid`, per-`(uid, ip)`, and per-`(uid, net_key)`.
           NEVER killed by `ss -K` while connected!
    """
    live_counts = {"vless": 0, "vmess": 0, "trojan": 0}
    min_idle_by_proto = {"vless": 9999.0, "vmess": 9999.0, "trojan": 9999.0}
    untagged_by_proto = {"vless": 0, "vmess": 0, "trojan": 0}
    uid_counts: dict[str, int] = {}
    uid_min_idle: dict[str, float] = {}
    uid_ip_counts: dict[tuple[str, str], int] = {}
    uid_net_counts: dict[tuple[str, str], int] = {}

    now_mono = time.monotonic()
    now_ts = time.time()
    seen_keys: set[str] = set()
    used_event_idxs: set[int] = set()

    proto_active_pairs: dict[str, list[tuple[str, str]]] = {"vless": [], "vmess": [], "trojan": []}
    for u_id, ip_list in om_by_uid.items():
        pr = uuid_to_proto.get(u_id, "vless")
        if pr in proto_active_pairs:
            non_cdn = [ip for ip in ip_list if not is_trusted_cdn(ip)]
            use_ips = non_cdn if non_cdn else ip_list
            for ip_v in use_ips:
                proto_active_pairs[pr].append((u_id, ip_v))

    try:
        out = subprocess.check_output(["ss", "-tin"], text=True, stderr=subprocess.DEVNULL, timeout=1.5)
        lines = out.splitlines()
        i = 0
        n = len(lines)
        while i < n:
            ln = lines[i]
            if "ESTAB" not in ln:
                i += 1
                continue
            cols = ln.split()
            if len(cols) < 5:
                i += 1
                continue
            try:
                lport = int(cols[3].rsplit(":", 1)[-1])
                rport = int(cols[4].rsplit(":", 1)[-1])
            except ValueError:
                i += 1
                continue

            info_ln = ""
            if (i + 1) < n and lines[i + 1].startswith((" ", "\t")):
                info_ln = lines[i + 1]
                i += 2
            else:
                i += 1

            matched_proto = None
            for pr, ports in PROTO_PORTS.items():
                if lport in ports:
                    matched_proto = pr
                    break
            if not matched_proto:
                continue

            if lport in ALL_XRAY_PORTS and info_ln:
                sock_key = f"{lport}:{rport}"
                seen_keys.add(sock_key)
                m_rx = SS_RX_BYTES_RE.search(info_ln)
                m_tx = SS_TX_BYTES_RE.search(info_ln)
                m_snd = SS_LASTSND_RE.search(info_ln)
                m_rcv = SS_LASTRCV_RE.search(info_ln)
                rx_b = int(m_rx.group(1)) if m_rx else 0
                tx_b = int(m_tx.group(1)) if m_tx else 0

                kern_idle = 0.0
                if m_snd and m_rcv:
                    kern_idle = min(int(m_snd.group(1)), int(m_rcv.group(1))) / 1000.0
                elif m_snd:
                    kern_idle = int(m_snd.group(1)) / 1000.0
                elif m_rcv:
                    kern_idle = int(m_rcv.group(1)) / 1000.0

                last_io_ts = now_ts - kern_idle
                prev = XRAY_SOCKET_RX_STATE.get(sock_key)
                if prev is None:
                    birth_ts = last_io_ts
                    prev = {
                        "first_seen": now_mono - kern_idle,
                        "last_io_mono": now_mono - kern_idle,
                        "birth_ts": birth_ts,
                        "rx_bytes": rx_b,
                        "tx_bytes": tx_b,
                        "proto": matched_proto,
                        "uid": "",
                        "ip": "",
                    }
                    XRAY_SOCKET_RX_STATE[sock_key] = prev
                    age = kern_idle
                    idle_sec = kern_idle
                else:
                    if rx_b > int(prev["rx_bytes"]) or tx_b > int(prev["tx_bytes"]):
                        prev["rx_bytes"] = rx_b
                        prev["tx_bytes"] = tx_b
                        prev["last_io_mono"] = now_mono

                    age = max(now_mono - float(prev["first_seen"]), kern_idle)
                    idle_sec = max(now_mono - float(prev["last_io_mono"]), kern_idle)

                # 1. Attribute via HAProxy direct socket table
                rport_str = str(rport)
                if rport_str in xray_port_to_ip:
                    hap_ip = xray_port_to_ip[rport_str]
                    prev["ip"] = hap_ip
                    if hap_ip in ip_to_uid:
                        prev["uid"] = ip_to_uid[hap_ip]

                # 2. Attribute via Xray access.log `accepted tcp:` timestamp correlation (birth_ts or last_io_ts)
                if not prev.get("uid") or not prev.get("ip"):
                    b_ts = float(prev.get("birth_ts") or (now_ts - age))
                    best_idx = -1
                    best_diff = 999.0
                    for idx, ev in enumerate(accept_events):
                        if ev["proto"] != matched_proto:
                            continue
                        ev_ts = float(ev["ts"])
                        diff = min(abs(ev_ts - b_ts), abs(ev_ts - last_io_ts))
                        if diff <= 5.0:
                            score = diff if idx not in used_event_idxs else (diff + 2.0)
                            if score < best_diff:
                                best_diff = score
                                best_idx = idx
                    if best_idx >= 0:
                        used_event_idxs.add(best_idx)
                        ev_m = accept_events[best_idx]
                        prev["uid"] = str(ev_m["uid"])
                        prev["ip"] = str(ev_m["ip"])

                # 3. Attribute via Xray statsonlineiplist per-IP activity timestamp (`om_ip_ts_by_uid`)
                if not prev.get("uid") or not prev.get("ip"):
                    best_u = ""
                    best_ip = ""
                    best_om_diff = 6.0
                    for u_id, ip_ts_map in om_ip_ts_by_uid.items():
                        if uuid_to_proto.get(u_id, "vless") != matched_proto:
                            continue
                        for cand_ip, cand_ts in ip_ts_map.items():
                            if cand_ts > 0:
                                d_om = abs(float(cand_ts) - last_io_ts)
                                if d_om < best_om_diff:
                                    best_om_diff = d_om
                                    best_u = u_id
                                    best_ip = cand_ip
                    if best_u and best_ip:
                        prev["uid"] = best_u
                        prev["ip"] = best_ip

                # 4. Fallback if only 1 active pair on this protocol
                if not prev.get("uid") or not prev.get("ip"):
                    pairs = proto_active_pairs.get(matched_proto, [])
                    if len(pairs) == 1:
                        prev["uid"] = pairs[0][0]
                        prev["ip"] = pairs[0][1]
                    elif prev.get("ip") and str(prev["ip"]) in ip_to_uid:
                        prev["uid"] = ip_to_uid[str(prev["ip"])]

                if tx_b <= 240 and age >= 1.2:
                    # Blocked UDP stream (129-byte HTTP 101 or 236-byte WS reject) -> close individually
                    UDP_KILL_TS_LIST.append(now_ts)
                    try:
                        subprocess.run(
                            ["ss", "-K", "sport", "=", f":{lport}", "dport", "=", f":{rport}"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            timeout=0.8,
                        )
                    except Exception:
                        pass
                    XRAY_SOCKET_RX_STATE.pop(sock_key, None)
                else:
                    live_counts[matched_proto] += 1
                    if idle_sec < min_idle_by_proto[matched_proto]:
                        min_idle_by_proto[matched_proto] = idle_sec

                    s_uid = str(prev.get("uid") or "")
                    s_ip = str(prev.get("ip") or "")
                    if s_uid:
                        uid_counts[s_uid] = uid_counts.get(s_uid, 0) + 1
                        if idle_sec < uid_min_idle.get(s_uid, 9999.0):
                            uid_min_idle[s_uid] = idle_sec
                        if s_ip:
                            uid_ip_counts[(s_uid, s_ip)] = uid_ip_counts.get((s_uid, s_ip), 0) + 1
                            if not is_trusted_cdn(s_ip):
                                try:
                                    _, nk, _ = ip_family_and_prefixes(s_ip)
                                    uid_net_counts[(s_uid, nk)] = uid_net_counts.get((s_uid, nk), 0) + 1
                                except ValueError:
                                    pass
                    else:
                        untagged_by_proto[matched_proto] += 1
            else:
                live_counts[matched_proto] += 1
                min_idle_by_proto[matched_proto] = 0.0
    except Exception:
        pass

    for k in list(XRAY_SOCKET_RX_STATE.keys()):
        if k not in seen_keys:
            prev_st = XRAY_SOCKET_RX_STATE.pop(k, None)
            if prev_st and int(prev_st.get("tx_bytes", 0)) >= 600:
                pr_name = str(prev_st.get("proto") or "vless")
                if pr_name in REAL_TCP_CLOSE_MONO:
                    REAL_TCP_CLOSE_MONO[pr_name].append(now_mono)
                st_uid = str(prev_st.get("uid") or "")
                if st_uid:
                    UID_TCP_CLOSE_MONO.setdefault(st_uid, []).append(now_mono)

    real_closed_by_proto: dict[str, int] = {}
    for pr in ("vless", "vmess", "trojan"):
        lst = [t for t in REAL_TCP_CLOSE_MONO.get(pr, []) if (now_mono - t) <= 2.5]
        REAL_TCP_CLOSE_MONO[pr] = lst
        real_closed_by_proto[pr] = len(lst)

    uid_closed: dict[str, int] = {}
    for u_k in list(UID_TCP_CLOSE_MONO.keys()):
        lst = [t for t in UID_TCP_CLOSE_MONO.get(u_k, []) if (now_mono - t) <= 2.5]
        if lst:
            UID_TCP_CLOSE_MONO[u_k] = lst
            uid_closed[u_k] = len(lst)
        else:
            UID_TCP_CLOSE_MONO.pop(u_k, None)

    return (
        live_counts,
        min_idle_by_proto,
        real_closed_by_proto,
        uid_counts,
        uid_min_idle,
        uid_closed,
        uid_ip_counts,
        uid_net_counts,
        untagged_by_proto,
    )


def kill_proto_zombie_sockets(proto: str):
    """When 0 users are online on `proto`, reset close-burst state without killing active TCP tunnels."""
    if proto in REAL_TCP_CLOSE_MONO:
        REAL_TCP_CLOSE_MONO[proto].clear()


def query_xray_online_map(
    xray_users: list[sqlite3.Row],
    tag_to_uuid: dict[str, str],
) -> tuple[dict[str, list[str]], dict[str, dict[str, int]], dict[str, dict[str, int]], bool]:
    """
    Query Xray's `statsonlineiplist` API.
    Returns (om_ips_by_uid, om_last_ts_by_uid_net, om_ip_ts_by_uid, online_map_ok).
    """
    global XRAY_ONLINE_ALL_SUPPORTED
    om_by_uid: dict[str, list[str]] = {}
    om_ts_by_uid_net: dict[str, dict[str, int]] = {}
    om_ip_ts_by_uid: dict[str, dict[str, int]] = {}
    xray_bin = Path("/usr/local/bin/xray")
    if not xray_bin.exists():
        return om_by_uid, om_ts_by_uid_net, om_ip_ts_by_uid, False

    if XRAY_ONLINE_ALL_SUPPORTED:
        proc = subprocess.run(
            [str(xray_bin), "api", "statsonlineiplist", "--server=127.0.0.1:10085", "-all"],
            capture_output=True,
            text=True,
            timeout=2.0,
        )
        if proc.returncode == 0:
            try:
                om_data = json.loads(proc.stdout) if proc.stdout.strip() else {}
                for u_obj in om_data.get("users", []) or []:
                    em_low = (u_obj.get("email") or "").split("@", 1)[0].lower()
                    uid = tag_to_uuid.get(em_low) or tag_to_uuid.get(em_low.split(".", 1)[0])
                    if not uid:
                        continue
                    lst = om_by_uid.setdefault(uid, [])
                    ts_map = om_ts_by_uid_net.setdefault(uid, {})
                    ip_ts_map = om_ip_ts_by_uid.setdefault(uid, {})
                    for ip_ent in u_obj.get("ips", []) or []:
                        ip_c = clean_public_ip(str(ip_ent.get("ip") or ""))
                        if not ip_c:
                            continue
                        if ip_c not in lst:
                            lst.append(ip_c)
                        last_s = int(ip_ent.get("lastSeen") or ip_ent.get("last_seen") or 0)
                        if last_s > 0:
                            ip_ts_map[ip_c] = last_s
                            if not is_trusted_cdn(ip_c):
                                try:
                                    _, net_k, _ = ip_family_and_prefixes(ip_c)
                                    if last_s > ts_map.get(net_k, 0):
                                        ts_map[net_k] = last_s
                                except Exception:
                                    pass
                return om_by_uid, om_ts_by_uid_net, om_ip_ts_by_uid, True
            except Exception:
                pass
        elif "flag provided but not defined" in (proc.stderr or "").lower() or "unknown" in (proc.stderr or "").lower():
            XRAY_ONLINE_ALL_SUPPORTED = False

    if not XRAY_ONLINE_ALL_SUPPORTED:
        any_queried = False
        for r in xray_users:
            if r["status"] != "active":
                continue
            any_queried = True
            email = f"{r['username']}.{r['proto']}@alyan"
            uid = r["uuid"]
            proc = subprocess.run(
                [str(xray_bin), "api", "statsonlineiplist", "--server=127.0.0.1:10085", f"-email={email}"],
                capture_output=True,
                text=True,
                timeout=1.5,
            )
            if proc.returncode == 0 and proc.stdout.strip():
                try:
                    d = json.loads(proc.stdout)
                    ips_map = d.get("ips") or {}
                    lst = om_by_uid.setdefault(uid, [])
                    ts_map = om_ts_by_uid_net.setdefault(uid, {})
                    ip_ts_map = om_ip_ts_by_uid.setdefault(uid, {})
                    if isinstance(ips_map, dict):
                        for raw_ip, raw_ts in ips_map.items():
                            ip_c = clean_public_ip(str(raw_ip))
                            if not ip_c:
                                continue
                            if ip_c not in lst:
                                lst.append(ip_c)
                            ts_val = int(raw_ts) if str(raw_ts).isdigit() else 0
                            ip_ts_map[ip_c] = ts_val
                            if not is_trusted_cdn(ip_c):
                                try:
                                    _, net_k, _ = ip_family_and_prefixes(ip_c)
                                    if ts_val > ts_map.get(net_k, 0):
                                        ts_map[net_k] = ts_val
                                except Exception:
                                    pass
                except Exception:
                    pass
        return om_by_uid, om_ts_by_uid_net, om_ip_ts_by_uid, any_queried

    return om_by_uid, om_ts_by_uid_net, om_ip_ts_by_uid, False


def update_vless_user_sessions(
    uid: str,
    live_om_ips: list[str],
    om_ip_ts: dict[str, int],
    recent_log_ips: list[str],
    proto_hap_ips: list[str],
    online_map_ok: bool,
    active_traffic: bool,
    user_active_sockets: int,
    uid_ip_counts: dict[tuple[str, str], int],
    uid_net_counts: dict[tuple[str, str], int],
    now_ts: float,
) -> tuple[list[str], int]:
    """
    Pure Kernel-Socket + Fresh-Activity Session Engine (S1, S2... S10):
      - Never kills established TCP sockets (`tx_b >= 600`) while connected (0% blink on page/video finish!).
      - Filters out stale Xray `statsonlineiplist` cache entries when `(uid, net_key)` has 0 open kernel sockets
        and `now_ts - raw_ts > 2.5s` (0% blink after disconnect!).
      - Tracks each user (`Alyan` vs `Test`) and each CGNAT `/16` session (`S1..S10`) independently.
    """
    sessions = XRAY_SESSIONS.setdefault(uid, {})

    if active_traffic:
        XRAY_LAST_ACTIVE_TS[uid] = now_ts

    filtered_recent_ips = list(recent_log_ips)
    recent_set_fast = set(filtered_recent_ips)

    # Keep only IPs in live_om_ips that either have active HAProxy connection, kernel socket, or fresh activity (<=2.5s)
    active_om_ips: list[str] = []
    for ip in live_om_ips:
        ip_ts_val = om_ip_ts.get(ip, 0)
        if is_trusted_cdn(ip):
            if active_traffic or (ip_ts_val > 0 and (now_ts - float(ip_ts_val)) <= 2.5):
                active_om_ips.append(ip)
            continue
        try:
            _, net_k, _ = ip_family_and_prefixes(ip)
        except ValueError:
            net_k = ip

        sock_cnt = max(
            uid_ip_counts.get((uid, ip), 0),
            uid_net_counts.get((uid, net_k), 0),
        )
        if sock_cnt == 0 and len(sessions) <= 1 and user_active_sockets > 0:
            sock_cnt = user_active_sockets

        has_alive_socket = (sock_cnt > 0)
        time_since_seen = (now_ts - float(ip_ts_val)) if ip_ts_val > 0 else 999.0
        hap_connected = (ip in proto_hap_ips)
        last_acc_val = LAST_ACCEPT_BY_UID_NET.get(uid, {}).get(net_k, 0.0)
        is_fresh = (
            (active_traffic and time_since_seen <= 2.5)
            or (ip in recent_set_fast)
            or (last_acc_val > 0 and (now_ts - float(last_acc_val)) <= 2.0)
        )
        # IP is truly active if:
        # 1. Open kernel socket for this user/IP & seen within 300s (0% blink during long idle!)
        # 2. Direct HAProxy connection verified & seen within 300s
        # 3. Fresh traffic or new accept event within 2.0s
        # 4. Grace period of <= 2.0s after disconnect before dropping
        if has_alive_socket:
            active_om_ips.append(ip)
        elif hap_connected and (time_since_seen <= 300.0 or time_since_seen == 999.0):
            active_om_ips.append(ip)
        elif is_fresh:
            active_om_ips.append(ip)
        elif time_since_seen <= 1.0:
            active_om_ips.append(ip)

    filtered_om_ips = active_om_ips
    effective_recent_ips = filtered_recent_ips if (not online_map_ok or bool(filtered_om_ips) or user_active_sockets > 0) else []
    real_live_set = {ip for ip in filtered_om_ips if not is_trusted_cdn(ip)}
    raw_real_cands: list[str] = []
    cdn_cands: list[str] = []

    for ip in filtered_om_ips + effective_recent_ips:
        if is_trusted_cdn(ip):
            if ip not in cdn_cands:
                cdn_cands.append(ip)
        else:
            if ip not in raw_real_cands:
                raw_real_cands.append(ip)

    def _ip_sort_key(ip_s: str) -> int:
        try:
            return 0 if ipaddress.ip_address(ip_s).version == 4 else 1
        except ValueError:
            return 2

    real_cands = sorted(raw_real_cands, key=_ip_sort_key)

    if real_cands:
        sessions.pop("S-CDN", None)

        for ip in real_cands:
            try:
                ver, net_key, super_key = ip_family_and_prefixes(ip)
            except ValueError:
                continue

            matched_sess = None

            # Rule 1: Exact IP or same /16 CGNAT pool (or /56-/48 IPv6 prefix)
            for s in sessions.values():
                if (
                    ip in s["ips"]
                    or net_key in s["net_keys"]
                    or (ver == 6 and super_key in s["super_keys"])
                ):
                    matched_sess = s
                    break

            # Rule 2: Dual-Stack (IPv4 + IPv6 on the same phone)
            if matched_sess is None:
                if ver == 6:
                    for s in sessions.values():
                        if s["has_v4"] and (s["v6_super"] is None or s["v6_super"] == super_key):
                            matched_sess = s
                            break
                elif ver == 4:
                    for s in sessions.values():
                        if not s["has_v4"]:
                            matched_sess = s
                            break

            # Rule 3: Same /12 mobile carrier superblock during 3.0s initial connection burst
            if matched_sess is None and ver == 4:
                for s in sessions.values():
                    if super_key in s["super_keys"] and (now_ts - s["created_at"]) <= 3.0:
                        matched_sess = s
                        break

            # Rule 4: Seamless CGNAT IP handover
            if matched_sess is None and online_map_ok:
                recent_set = set(effective_recent_ips)
                for s in sessions.values():
                    if (
                        not s.get("_touched")
                        and not (s["ips"] & real_live_set)
                        and not (s["ips"] & recent_set)
                    ):
                        s["primary_ip"] = ip
                        s["ips"] = {ip}
                        s["net_keys"] = {net_key}
                        s["super_keys"] = {super_key}
                        s["has_v4"] = (ver == 4)
                        s["v6_super"] = super_key if ver == 6 else None
                        s["last_seen"] = now_ts
                        s["_touched"] = True
                        matched_sess = s
                        break

            if matched_sess is not None:
                matched_sess["ips"].add(ip)
                matched_sess["net_keys"].add(net_key)
                matched_sess["super_keys"].add(super_key)
                if ver == 4 and not matched_sess["has_v4"]:
                    matched_sess["has_v4"] = True
                    matched_sess["primary_ip"] = ip
                elif ver == 6 and matched_sess["v6_super"] is None:
                    matched_sess["v6_super"] = super_key
                matched_sess["last_seen"] = now_ts
                matched_sess["_touched"] = True
            else:
                seq = XRAY_SESSION_SEQ.get(uid, 0) + 1
                XRAY_SESSION_SEQ[uid] = seq
                sid = f"S{seq}"
                sessions[sid] = {
                    "session_id": sid,
                    "primary_ip": ip,
                    "ips": {ip},
                    "net_keys": {net_key},
                    "super_keys": {super_key},
                    "has_v4": (ver == 4),
                    "v6_super": super_key if ver == 6 else None,
                    "created_at": now_ts,
                    "last_seen": now_ts,
                    "_touched": True,
                }
    elif not sessions and cdn_cands and (active_traffic or bool(filtered_om_ips)):
        sessions["S-CDN"] = {
            "session_id": "S-CDN",
            "primary_ip": cdn_cands[0],
            "ips": set(cdn_cands),
            "net_keys": {"cdn-edge"},
            "super_keys": {"cdn-edge"},
            "has_v4": True,
            "v6_super": None,
            "created_at": now_ts,
            "last_seen": now_ts,
            "_touched": True,
        }
    elif sessions and cdn_cands and "S-CDN" in sessions and (active_traffic or bool(filtered_om_ips)):
        sessions["S-CDN"]["ips"].update(cdn_cands)
        sessions["S-CDN"]["last_seen"] = now_ts

    live_all_set = set(filtered_om_ips)
    for sid, s in list(sessions.items()):
        s.pop("_touched", None)
        has_open_stream = bool(s["ips"] & live_all_set)

        sess_sockets = max(
            sum(uid_ip_counts.get((uid, ip), 0) for ip in s["ips"]),
            sum(uid_net_counts.get((uid, nk), 0) for nk in s["net_keys"]),
        )
        if len(sessions) == 1 and sess_sockets == 0 and user_active_sockets > 0:
            sess_sockets = user_active_sockets

        if sess_sockets > 0 or has_open_stream or active_traffic:
            s["last_seen"] = now_ts
        else:
            sessions.pop(sid, None)

    if not sessions:
        XRAY_SESSION_SEQ[uid] = 0
        return [], 0

    pinned_ips: list[str] = []
    for s in sessions.values():
        p_ip = s["primary_ip"]
        if p_ip and p_ip not in pinned_ips:
            pinned_ips.append(p_ip)

    return pinned_ips, len(sessions)


def poll_xray_stats_and_ips(
    xray_users: list[sqlite3.Row],
    xray_port_to_ip: dict[str, str],
    ws_ips: list[str],
    h2c_ips: list[str],
    trojan_ips: list[str],
) -> tuple[dict[str, int], dict[str, list[str]], dict[str, int]]:
    tag_to_uuid: dict[str, str] = {}
    uuid_to_proto: dict[str, str] = {}
    for r in xray_users:
        u_low = r["username"].lower()
        p_low = r["proto"].lower()
        uid = r["uuid"]
        tag_to_uuid[f"{u_low}.{p_low}"] = uid
        tag_to_uuid.setdefault(u_low, uid)
        uuid_to_proto[uid] = p_low

    deltas: dict[str, int] = {}
    if Path("/usr/local/bin/xray").exists():
        try:
            raw = subprocess.check_output(
                ["/usr/local/bin/xray", "api", "statsquery", "--server=127.0.0.1:10085", "-pattern", "user>>>", "-reset"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=2.5,
            )
            data = json.loads(raw) if raw.strip() else {}
            for st in data.get("stat", []):
                parts = st.get("name", "").split(">>>")
                if len(parts) >= 4 and parts[2] == "traffic":
                    tag_low = parts[1].split("@", 1)[0].lower()
                    uid = tag_to_uuid.get(tag_low) or tag_to_uuid.get(tag_low.split(".", 1)[0])
                    if uid:
                        val = int(st.get("value", 0))
                        if val > 0:
                            deltas[uid] = deltas.get(uid, 0) + val
        except Exception:
            pass

    now_ts = time.time()
    om_by_uid, _, om_ip_ts_by_uid, online_map_ok = query_xray_online_map(xray_users, tag_to_uuid)
    recent_log_ips_by_uid: dict[str, list[str]] = {}
    accept_events: list[dict] = []
    ip_to_uid: dict[str, str] = {}

    for u_id, ip_lst in om_by_uid.items():
        for ip_v in ip_lst:
            if not is_trusted_cdn(ip_v):
                ip_to_uid[ip_v] = u_id

    if XRAY_ACCESS_LOG.exists():
        try:
            with XRAY_ACCESS_LOG.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 131072))
                raw_lines = f.read().decode("utf-8", errors="ignore").splitlines()
            tail_lines = [l for l in raw_lines if "api-in -> api" not in l][-300:]
            if sz > 2097152 and (CYCLE_TICK == 1 or CYCLE_TICK % 60 == 0):
                try:
                    keep_bytes = "\n".join(tail_lines[-500:]).encode("utf-8") + b"\n"
                    with XRAY_ACCESS_LOG.open("r+b") as wf:
                        wf.seek(0)
                        wf.write(keep_bytes)
                        wf.truncate()
                except Exception:
                    pass
            for ln in tail_lines:
                low_ln = ln.lower()
                if "accepted tcp:" not in low_ln or "email:" not in low_ln:
                    continue
                log_ts = parse_xray_log_ts(ln)
                if log_ts is None or (now_ts - log_ts) > 600.0 or (now_ts - log_ts) < -5.0:
                    continue
                m_em = XRAY_EMAIL_RE.search(ln)
                if not m_em:
                    continue
                em_tag = m_em.group(1).lower()
                uid = tag_to_uuid.get(em_tag) or tag_to_uuid.get(em_tag.split(".", 1)[0])
                if not uid:
                    continue

                ip_clean, _, is_udp = parse_xray_source_ip(ln)
                if ip_clean and not is_udp:
                    u_proto = uuid_to_proto.get(uid, "vless")
                    accept_events.append(
                        {
                            "ts": log_ts,
                            "proto": u_proto,
                            "uid": uid,
                            "ip": ip_clean,
                        }
                    )
                    if not is_trusted_cdn(ip_clean):
                        ip_to_uid[ip_clean] = uid
                        try:
                            _, net_k, _ = ip_family_and_prefixes(ip_clean)
                            u_map = LAST_ACCEPT_BY_UID_NET.setdefault(uid, {})
                            if log_ts > u_map.get(net_k, 0.0):
                                u_map[net_k] = log_ts
                        except ValueError:
                            pass
                        if (now_ts - log_ts) <= 2.0:
                            lst = recent_log_ips_by_uid.setdefault(uid, [])
                            if ip_clean not in lst:
                                lst.append(ip_clean)
        except Exception:
            pass

    (
        proto_socket_counts,
        proto_min_idle,
        proto_real_closed,
        uid_counts,
        uid_min_idle,
        uid_closed,
        uid_ip_counts,
        uid_net_counts,
        untagged_by_proto,
    ) = scan_active_proto_sockets(
        xray_port_to_ip, accept_events, om_by_uid, om_ip_ts_by_uid, uuid_to_proto, ip_to_uid
    )

    ips_by_uuid: dict[str, list[str]] = {}
    dev_count_by_uuid: dict[str, int] = {}
    proto_online_totals = {"vless": 0, "vmess": 0, "trojan": 0}

    for r in xray_users:
        uid = r["uuid"]
        if r["status"] != "active":
            XRAY_SESSIONS.pop(uid, None)
            XRAY_SESSION_SEQ.pop(uid, None)
            ips_by_uuid[uid] = []
            dev_count_by_uuid[uid] = 0
            continue

        proto = r["proto"].lower()
        active_traffic = deltas.get(uid, 0) > 0
        live_om = om_by_uid.get(uid, [])
        u_om_ts = om_ip_ts_by_uid.get(uid, {})
        recent_lg = recent_log_ips_by_uid.get(uid, [])

        u_sock_cnt = uid_counts.get(uid, 0)
        u_cls_rec = uid_closed.get(uid, 0)
        u_min_idle = uid_min_idle.get(uid, 9999.0)


        # Determine active client IPs for this protocol from HAProxy
        if proto in ("vless", "vmess"):
            proto_hap_ips = ws_ips
        elif proto == "grpc":
            proto_hap_ips = h2c_ips
        elif proto == "trojan":
            proto_hap_ips = trojan_ips
        else:
            proto_hap_ips = ws_ips + h2c_ips + trojan_ips

        # Active users count on this protocol from online map
        proto_active_uids = [
            u_r["uuid"] for u_r in xray_users
            if u_r["status"] == "active" and u_r["proto"].lower() == proto and om_by_uid.get(u_r["uuid"])
        ]

        # Untagged sockets are ONLY used as fallback if ONLY ONE user is active on this protocol
        # (strictly prevents cross-user socket leakage in multi-user environments!)
        if (
            u_sock_cnt == 0
            and u_cls_rec == 0
            and live_om
            and len(proto_active_uids) <= 1
            and untagged_by_proto.get(proto, 0) > 0
        ):
            u_sock_cnt = untagged_by_proto[proto]

        if not live_om and not recent_lg and proto == "trojan" and active_traffic and trojan_ips:
            non_cdn_tr = [ip for ip in trojan_ips if not is_trusted_cdn(ip)]
            recent_lg = non_cdn_tr[:1] if non_cdn_tr else trojan_ips[:1]

        u_ips, u_cnt = update_vless_user_sessions(
            uid=uid,
            live_om_ips=live_om,
            om_ip_ts=u_om_ts,
            recent_log_ips=recent_lg,
            proto_hap_ips=proto_hap_ips,
            online_map_ok=online_map_ok,
            active_traffic=active_traffic,
            user_active_sockets=u_sock_cnt,
            uid_ip_counts=uid_ip_counts,
            uid_net_counts=uid_net_counts,
            now_ts=now_ts,
        )
        ips_by_uuid[uid] = u_ips
        dev_count_by_uuid[uid] = u_cnt
        if proto in proto_online_totals:
            proto_online_totals[proto] += u_cnt

    # When the entire protocol transitions from Online (>0) to Offline (0) and all remaining
    # sockets on that protocol have been idle >=1.2s, destroy those leftover Cloudflare zombie
    # sockets via `ss -K` so Xray's internal OnlineMap (`statsonlineiplist`) resets to `{}`!
    for proto, cur_tot in proto_online_totals.items():
        prev_tot = PREV_PROTO_ONLINE.get(proto, 0)
        if (
            cur_tot == 0
            and prev_tot > 0
            and proto_min_idle.get(proto, 9999.0) >= 1.2
        ):
            kill_proto_zombie_sockets(proto)
        PREV_PROTO_ONLINE[proto] = cur_tot

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
    hap_loop_ips, xray_port_to_ip, ws_ips, h2c_ips, trojan_ips = query_haproxy_sessions()

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
        xray_deltas, xray_ips, xray_fresh_devs = poll_xray_stats_and_ips(
            xray_rows, xray_port_to_ip, ws_ips, h2c_ips, trojan_ips
        )

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
            user_lim = int(r["ip_limit"] or 0)
            conns = ssh_sessions.get(uname, [])
            session_count = len(conns)
            uniq_ips = sorted({s["ip"] for s in conns if s.get("ip")})

            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"SSH user `{uname}` expired ({r['expiry']})"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"SSH user `{uname}` reached {gb_lim} GB quota"
            elif user_lim > 0 and session_count > user_lim:
                SSH_IP_STRIKES[uname] = SSH_IP_STRIKES.get(uname, 0) + 1
                if SSH_IP_STRIKES[uname] >= 2:
                    reason = f"SSH user `{uname}` exceeded user limit ({session_count}/{user_lim} Users) — auto-disabled"
                else:
                    excess = conns[user_lim:]
                    for s in excess:
                        if s.get("pid"):
                            subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                    ssh_sessions[uname] = conns[:user_lim]
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
                XRAY_SESSIONS.pop(uuid, None)
                XRAY_SESSION_SEQ.pop(uuid, None)
                xray_ips[uuid] = []
                continue

            gb_lim = float(r["gb_limit"] or 0)
            user_lim = int(r["ip_limit"] or 0)
            cur_ips = xray_ips.get(uuid, [])
            fresh_sess = xray_fresh_devs.get(uuid, 0)

            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) expired"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) reached {gb_lim} GB quota"
            elif user_lim > 0 and fresh_sess > user_lim:
                XRAY_IP_STRIKES[uuid] = XRAY_IP_STRIKES.get(uuid, 0) + 1
                if XRAY_IP_STRIKES[uuid] >= 3:
                    reason = f"Xray client `{uname}` ({r['proto'].upper()}) exceeded user limit ({fresh_sess}/{user_lim} Users) — auto-disabled"
            else:
                XRAY_IP_STRIKES.pop(uuid, None)

            if reason:
                XRAY_IP_STRIKES.pop(uuid, None)
                XRAY_ACTIVE_DEVICES.pop(uuid, None)
                XRAY_SESSIONS.pop(uuid, None)
                XRAY_SESSION_SEQ.pop(uuid, None)
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
        subprocess.run(["/usr/local/bin/alyan-ctl", "--actor", "cli", "xray-sync"], stderr=subprocess.DEVNULL)

    # ─── 3. Record Rolling Telemetry & Fast Snapshot ─────────────────────────
    cpu_pct = read_cpu_pct()
    ram_pct = read_ram_pct()
    rx_bps, tx_bps, rx_tot, tx_tot = read_net_rates(iface)

    HIST["cpu"] = (HIST["cpu"] + [cpu_pct])[-20:]
    HIST["ram"] = (HIST["ram"] + [ram_pct])[-20:]
    HIST["rx"] = (HIST["rx"] + [round((rx_bps * 8) / 1048576.0, 2)])[-20:]
    HIST["tx"] = (HIST["tx"] + [round((tx_bps * 8) / 1048576.0, 2)])[-20:]

    if not CACHED_SERVICES or (CYCLE_TICK % 6 == 0):
        CACHED_SERVICES = collect_services_fast()

    ssh_live = {}
    for uname, conns in ssh_sessions.items():
        ips = sorted({c["ip"] for c in conns if c.get("ip")})
        ssh_live[uname] = {"online": len(conns), "ips": ips}

    xray_live = {}
    for r in xray_rows:
        uid = r["uuid"]
        ips = xray_ips.get(uid, [])
        user_sess_cnt = xray_fresh_devs.get(uid, 0)
        if user_sess_cnt == 0 and ips:
            user_sess_cnt = len(ips)
        xray_live[uid] = {"online": user_sess_cnt, "ips": ips}

    now_int = int(time.time())
    snapshot = {
        "updated_at": now_int,
        "ts": now_int,
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
        time.sleep(0.5)


if __name__ == "__main__":
    main()

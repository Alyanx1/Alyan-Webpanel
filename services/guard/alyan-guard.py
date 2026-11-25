#!/usr/bin/env python3
"""
Alyan Webpanel — Real-Time SSH Quota, Exact Real-IP & Multi-Device Session Enforcer (alyan-guard)
Continuously monitors SSH/Dropbear/WS-Proxy (/alyan):
  1. Correlates Dropbear (-E short-iso journal) & OpenSSH PIDs -> Username -> Exact Real Client IP.
  2. Counts real-time SSH per-user bytes into SQLite.
  3. Strictly enforces GB quotas, expiry dates, and user limits (auto-disabling violating accounts).
  4. Writes /run/alyan-live.json every 0.5s for ultra-fast Webpanel sync.
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

MANAGED_SERVICES = [
    ("haproxy",     "HAProxy Flame Router", "Public 80 / 443 Multiplexer"),
    ("nginx",       "Nginx Router & TLS",   "ACME & Panel HTTPS"),
    ("dropbear",    "Dropbear SSH",         "Direct Tunnel Ports 109 / 143"),
    ("alyan-wsd",   "Alyan WS-Proxy",       "GET /alyan 101 + Real-IP Bridge"),
    ("xray",        "Xray-Core Multi-Engine", "VLESS · VMess · Trojan · XHTTP"),
    ("alyan-guard", "Alyan Guard",          "GB Quota · Expiry · IP Enforcer"),
    ("alyan-bot",   "Telegram Bot",         "Full User & Server Control"),
    ("alyan-panel", "Alyan Webpanel",       "FastAPI Command Deck"),
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

SSH_IP_STRIKES: dict[str, int] = {}

XRAY_BIN = Path("/usr/local/bin/xray")
XRAY_ACCESS_LOG = Path("/var/log/xray/access.log")
XRAY_LAST_OFFSET = 0
XRAY_LOG_INODE: int | None = None
XRAY_LOG_STARTED = False
_MAX_READ_BYTES = 4 * 1024 * 1024
_MAX_LINE = 2048

# email -> {ip: [last_accept, last_seen]}
XRAY_RECENT_IPS: dict[str, dict[str, list[float]]] = {}
XRAY_LAST_BYTES: dict[str, int] = {}
XRAY_IP_STRIKES: dict[str, int] = {}

ONLINE_WINDOW = 6.0       # 6.0s: Snappy ~8s disconnect detection without flapping
ACCEPT_WINDOW = 2.0       # 2.0s: Secondary device active accept window
RETAIN_WINDOW = 600.0     # Retain newest IP up to 10m so idle tunnels recover instantly

XRAY_LINE_RE = re.compile(
    r"(?:from\s+|tcp:|udp:)?\[?(?P<ip>[0-9a-fA-F.:]+)\]?:\d+\s+accepted\s+.*email:\s*(?P<email>\S+)",
    re.IGNORECASE,
)


def _read_new_xray_lines() -> list[str]:
    global XRAY_LAST_OFFSET, XRAY_LOG_STARTED, XRAY_LOG_INODE
    if not XRAY_ACCESS_LOG.exists():
        return []
    try:
        with open(XRAY_ACCESS_LOG, "rb") as fh:
            stat = os.fstat(fh.fileno())
            size, ino = stat.st_size, stat.st_ino
            if not XRAY_LOG_STARTED:
                XRAY_LOG_STARTED = True
                XRAY_LAST_OFFSET = size
                XRAY_LOG_INODE = ino
                return []
            if size < XRAY_LAST_OFFSET or (XRAY_LOG_INODE is not None and ino != XRAY_LOG_INODE):
                XRAY_LAST_OFFSET = 0
            XRAY_LOG_INODE = ino
            fh.seek(XRAY_LAST_OFFSET)
            raw = fh.read(_MAX_READ_BYTES)
            XRAY_LAST_OFFSET = fh.tell()
            skipped = False
            if len(raw) >= _MAX_READ_BYTES:
                fh.seek(0, os.SEEK_END)
                end = fh.tell()
                XRAY_LAST_OFFSET = end
                skipped = True
    except OSError:
        return []

    if raw and not raw.endswith(b"\n"):
        cut = raw.rfind(b"\n")
        remainder = len(raw) if cut == -1 else len(raw) - (cut + 1)
        raw = b"" if cut == -1 else raw[:cut + 1]
        if not skipped:
            XRAY_LAST_OFFSET -= remainder
    return raw.decode("utf-8", "ignore").splitlines()

DROPBEAR_AUTH_RE = re.compile(
    r"(?:dropbear\[(\d+)\]|\[(\d+)\]).*?(?:Password|Pubkey) auth succeeded for '([^']+)'",
    re.IGNORECASE,
)
SSHD_AUTH_RE = re.compile(
    r"sshd(?:-session)?\[(\d+)\]:\s+Accepted\s+\S+\s+for\s+(\S+)\s+from",
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


def query_haproxy_sessions() -> dict[str, str]:
    loop_port_to_ip: dict[str, str] = {}

    if not HAPROXY_SOCK.exists():
        return loop_port_to_ip

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
                if m.group(1) not in ("109", "143", "22", "2095", "4443", "8880", "8884", "8443")
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

            if be_name == "be_tls_loop":
                for lp in lports:
                    tls_loop_map[lp] = client_ip

            if be_name in ("be_ssh_dropbear", "be_ssh_openssh", "be_dropbear"):
                for lp in lports:
                    loop_port_to_ip[lp] = client_ip
                if not lports:
                    loop_port_to_ip[f" fallback_{client_ip}"] = client_ip
    except Exception:
        pass

    return loop_port_to_ip


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
    if CYCLE_TICK == 1 or (CYCLE_TICK % 4 == 0):
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
    hap_loop_ips = query_haproxy_sessions()

    conn = db_conn()
    try:
        settings_rows = {r["key"]: r["value"] for r in conn.execute("SELECT key, value FROM settings").fetchall()}
        iface = settings_rows.get("iface", "eth0")
        bot_cfg = json.loads(settings_rows.get("bot_json", "{}"))

        ssh_rows = conn.execute("SELECT * FROM ssh_users").fetchall()

        today = dt.date.today().isoformat()
        managed_ssh = {r["username"] for r in ssh_rows}
        ssh_sessions, ssh_deltas = scan_ssh_sessions(managed_ssh, hap_loop_ips)

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

        # ─── 2. Scan Xray Live Sessions & Byte Counters (Zeta-Aligned Engine) ───
        xray_rows = conn.execute("SELECT * FROM xray_users").fetchall()
        xray_resync_needed = False
        xray_live: dict[str, dict] = {}

        if xray_rows and XRAY_BIN.exists():
            now_ts = time.time()
            keep_start = now_ts - ONLINE_WINDOW
            retain_start = now_ts - RETAIN_WINDOW

            # 2a. Read newly-appended Xray access.log records (bounded tail)
            lines = _read_new_xray_lines()
            for line in lines:
                if len(line) > _MAX_LINE:
                    continue
                m = XRAY_LINE_RE.search(line)
                if not m:
                    continue
                raw_ip = m.group("ip")
                cip = clean_public_ip(raw_ip)
                if not cip:
                    continue
                email = m.group("email").strip().lower()
                email_ips = XRAY_RECENT_IPS.setdefault(email, {})

                # Mobile/ISP CGNAT pools (e.g. 119.155.x.x /16) rotate public IPv4s across
                # parallel WebSocket connections from the same phone. Collapse global /16
                # siblings to the newest IP so one mobile device never shows as 2+ devices.
                if ":" not in cip:
                    try:
                        if ipaddress.IPv4Address(cip).is_global:
                            prefix16 = ".".join(cip.split(".")[:2]) + "."
                            for old_ip in [k for k in email_ips if k != cip and ":" not in k and k.startswith(prefix16)]:
                                email_ips.pop(old_ip, None)
                    except Exception:
                        pass

                # Record [last_accept, last_seen]
                email_ips[cip] = [now_ts, now_ts]

            # 2b. Cumulative Byte Counters via statsquery & Smart Active-Refresh
            active_emails: set[str] = set()
            if CYCLE_TICK == 1 or (CYCLE_TICK % 2 == 0):
                try:
                    sq_out = subprocess.check_output(
                        [str(XRAY_BIN), "api", "statsquery", "--server=127.0.0.1:10085"],
                        text=True, stderr=subprocess.DEVNULL, timeout=1.5
                    )
                    stats_list = json.loads(sq_out).get("stat", [])
                    user_totals: dict[str, int] = {}
                    for st in stats_list:
                        s_name = st.get("name", "")
                        m_stat = re.match(r"user>>>(.+?)>>>traffic>>>(uplink|downlink)", s_name)
                        if m_stat:
                            em = m_stat.group(1).lower()
                            user_totals[em] = user_totals.get(em, 0) + int(st.get("value", 0))

                    for em, total_b in user_totals.items():
                        prev_b = XRAY_LAST_BYTES.get(em, total_b)
                        delta_x = total_b - prev_b
                        XRAY_LAST_BYTES[em] = total_b
                        if delta_x > 0:
                            active_emails.add(em)
                            if "@" in em:
                                x_user, x_proto = em.split("@", 1)
                                conn.execute(
                                    "UPDATE xray_users SET used_bytes = used_bytes + ? WHERE LOWER(username) = LOWER(?) AND proto = ?",
                                    (delta_x, x_user, x_proto),
                                )
                except Exception:
                    pass

            # 2c. ZetaVPN Refresh: Refresh ONLY newest IP or actively-connecting IPs!
            # Disconnected secondary IPs whose last_accept is older than ACCEPT_WINDOW DO NOT get refreshed!
            accept_thresh = now_ts - ACCEPT_WINDOW
            for email in active_emails:
                ips = XRAY_RECENT_IPS.get(email)
                if not ips:
                    continue
                newest = max(ips, key=lambda i: ips[i][0])
                for ip, ts in ips.items():
                    if ip == newest or ts[0] >= accept_thresh:
                        ts[1] = now_ts  # refresh last_seen (badge) only, NOT last_accept

            # 2d. Prune expired IPs
            for email in list(XRAY_RECENT_IPS.keys()):
                ips = XRAY_RECENT_IPS[email]
                newest_ip = max(ips, key=lambda i: ips[i][0]) if ips else None
                for ip in [
                    ip for ip, ts in ips.items()
                    if (ts[1] < retain_start if ip == newest_ip else ts[1] < keep_start)
                ]:
                    del ips[ip]
                if not ips:
                    del XRAY_RECENT_IPS[email]

            # 2e. Enforce Expiry, Quota & IP Limits with Deterministic Sibling Grouping
            for xr in xray_rows:
                x_uuid = xr["uuid"]
                x_uname = xr["username"]
                x_proto = xr["proto"]
                x_email = f"{x_uname}@{x_proto}".lower()
                x_used = int(xr["used_bytes"])
                x_gb = float(xr["gb_limit"] or 0)
                x_iplim = int(xr["ip_limit"] or 0)

                email_ips = XRAY_RECENT_IPS.get(x_email, {})
                active = {ip: ts[1] for ip, ts in email_ips.items() if ts[1] >= keep_start}

                # Sibling collapse & sorting (Zeta pattern)
                by_prefix: dict[str, tuple[str, float]] = {}
                kept: list[str] = []
                for ip, seen in active.items():
                    if ":" not in ip:
                        try:
                            if ipaddress.IPv4Address(ip).is_global:
                                p16 = ".".join(ip.split(".")[:2]) + "."
                                prev = by_prefix.get(p16)
                                if prev is None or seen >= prev[1]:
                                    by_prefix[p16] = (ip, seen)
                                continue
                        except Exception:
                            pass
                    kept.append(ip)
                kept.extend(ip for ip, _ in by_prefix.values())

                # Dual-stack IPv4/IPv6 pairing on mobile
                v4 = sorted(ip for ip in kept if ":" not in ip)
                v6 = sorted(ip for ip in kept if ":" in ip)
                if len(v4) == 1 and len(v6) == 1:
                    clean_user_ips = v4
                else:
                    clean_user_ips = sorted(kept)

                active_count = len(clean_user_ips)
                is_active = (xr["status"] == "active")

                xray_live[x_uuid] = {
                    "online": active_count if is_active else 0,
                    "ips": clean_user_ips if is_active else [],
                }

                if not is_active:
                    XRAY_IP_STRIKES.pop(x_uuid, None)
                    continue

                x_reason = None
                if xr["expiry"] and xr["expiry"] < today:
                    x_reason = f"Xray client `{x_uname}` ({x_proto.upper()}) expired ({xr['expiry']})"
                elif x_gb > 0 and x_used >= int(x_gb * 1073741824):
                    x_reason = f"Xray client `{x_uname}` ({x_proto.upper()}) reached {x_gb} GB quota"
                elif x_iplim > 0 and active_count > x_iplim:
                    XRAY_IP_STRIKES[x_uuid] = XRAY_IP_STRIKES.get(x_uuid, 0) + 1
                    if XRAY_IP_STRIKES[x_uuid] >= 3:
                        x_reason = f"Xray client `{x_uname}` ({x_proto.upper()}) exceeded user limit ({active_count}/{x_iplim} Users) — auto-disabled"
                else:
                    XRAY_IP_STRIKES.pop(x_uuid, None)

                if x_reason:
                    XRAY_IP_STRIKES.pop(x_uuid, None)
                    conn.execute("UPDATE xray_users SET status = 'disabled' WHERE uuid = ?", (x_uuid,))
                    conn.execute(
                        "INSERT INTO audit_log (created_at, actor, action, detail, ip) VALUES (?, 'alyan-guard', 'xray_disable', ?, 'local')",
                        (dt.datetime.now().strftime("%H:%M:%S"), x_reason),
                    )
                    xray_live[x_uuid] = {"online": 0, "ips": []}
                    XRAY_RECENT_IPS.pop(x_email, None)
                    xray_resync_needed = True
                    send_telegram_alert(bot_cfg, x_reason)

            if xray_resync_needed:
                subprocess.run(["/usr/local/bin/alyan-ctl", "--actor", "cli", "xray-sync"], stderr=subprocess.DEVNULL)

        conn.commit()
    finally:
        conn.close()

    # ─── 2. Record Rolling Telemetry & Fast Snapshot ─────────────────────────
    cpu_pct = read_cpu_pct()
    ram_pct = read_ram_pct()
    rx_bps, tx_bps, rx_tot, tx_tot = read_net_rates(iface)

    HIST["cpu"] = (HIST["cpu"] + [cpu_pct])[-20:]
    HIST["ram"] = (HIST["ram"] + [ram_pct])[-20:]
    HIST["rx"] = (HIST["rx"] + [round((rx_bps * 8) / 1048576.0, 2)])[-20:]
    HIST["tx"] = (HIST["tx"] + [round((tx_bps * 8) / 1048576.0, 2)])[-20:]

    if not CACHED_SERVICES or (CYCLE_TICK % 12 == 0):
        CACHED_SERVICES = collect_services_fast()

    ssh_live = {}
    for uname, conns in ssh_sessions.items():
        ips = sorted({c["ip"] for c in conns if c.get("ip")})
        ssh_live[uname] = {"online": len(conns), "ips": ips}

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

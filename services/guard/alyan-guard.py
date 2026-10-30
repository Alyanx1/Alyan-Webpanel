#!/usr/bin/env python3
"""
Alyan Webpanel — Real-Time 2s Quota, Live-IP & Expiry Enforcer (alyan-guard)
Continuously monitors SSH/Dropbear/WS-Proxy (/alyan) & Xray (VLESS/VMess/Trojan):
  1. Correlates Dropbear (-E journal) & OpenSSH PIDs -> Username -> Real Client IP.
  2. Counts real-time SSH (WS + SSL + Direct) & Xray per-user bytes into SQLite every 2s.
  3. Tracks live Xray client IPs (supporting Nginx X-Forwarded-For & PROXY-v2).
  4. Enforces GB quotas, expiry dates, and multi-IP connection caps.
  5. Writes /run/alyan-live.json every 2s for instant Webpanel updates.
"""
import datetime as dt
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

HIST = {"cpu": [], "ram": [], "rx": [], "tx": []}
LAST_CPU = None
LAST_NET = None

# Persistent tracking caches across 2-second ticks
PID_AUTH_CACHE: dict[int, str] = {}
PORT_TO_USER: dict[str, str] = {}
WSD_PORT_LAST_BYTES: dict[str, int] = {}
PID_LAST_IO_BYTES: dict[int, int] = {}
XRAY_RECENT_IPS: dict[str, dict[str, float]] = {}

DROPBEAR_AUTH_RE = re.compile(
    r"\[(\d+)\].*?(?:Password|Pubkey) auth succeeded for '([^']+)'",
    re.IGNORECASE,
)
SSHD_AUTH_RE = re.compile(
    r"sshd(?:-session)?\[(\d+)\]:\s+Accepted\s+\S+\s+for\s+(\S+)\s+from",
    re.IGNORECASE,
)
XRAY_EMAIL_RE = re.compile(r"email:\s*([^\s@]+)@alyan", re.IGNORECASE)
XRAY_FROM_RE = re.compile(
    r"from\s+(?:tcp:|udp:)?\[?([0-9a-fA-F\.:]+)\]?(?::\d+)?\s+accepted",
    re.IGNORECASE,
)


def db_conn():
    conn = sqlite3.connect(str(DB_PATH), timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    return conn


def read_cpu_pct() -> float:
    global LAST_CPU
    try:
        line = Path("/proc/stat").read_text().splitlines()[0].split()[1:]
        vals = [int(x) for x in line]
        idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
        total = sum(vals)
        if LAST_CPU is None:
            LAST_CPU = (idle, total)
            return 6.0
        d_idle = idle - LAST_CPU[0]
        d_tot = max(1, total - LAST_CPU[1])
        LAST_CPU = (idle, total)
        return round(max(1.0, min(100.0, (1.0 - d_idle / d_tot) * 100.0)), 1)
    except Exception:
        return 6.0


def read_ram_pct() -> float:
    try:
        info = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            k, v = line.split(":", 1)
            info[k.strip()] = int(v.strip().split()[0]) * 1024
        tot = max(1, info.get("MemTotal", 1))
        avail = info.get("MemAvailable", info.get("MemFree", 0))
        return round(((tot - avail) / tot) * 100.0, 1)
    except Exception:
        return 20.0


def read_net_rates(default_iface: str) -> tuple[float, float, int, int]:
    global LAST_NET
    rx_tot, tx_tot = 0, 0
    try:
        for line in Path("/proc/net/dev").read_text().splitlines()[2:]:
            if ":" not in line:
                continue
            iface, rest = line.split(":", 1)
            iface = iface.strip()
            if iface == "lo":
                continue
            cols = [int(x) for x in rest.split()]
            if not default_iface or iface == default_iface:
                rx_tot += cols[0]
                tx_tot += cols[8]
    except Exception:
        pass
    now = time.time()
    if LAST_NET is None:
        LAST_NET = (now, rx_tot, tx_tot)
        return 0.0, 0.0, rx_tot, tx_tot
    dt_s = max(0.4, now - LAST_NET[0])
    rx_bps = max(0.0, (rx_tot - LAST_NET[1]) / dt_s)
    tx_bps = max(0.0, (tx_tot - LAST_NET[2]) / dt_s)
    LAST_NET = (now, rx_tot, tx_tot)
    return rx_bps, tx_bps, rx_tot, tx_tot


def refresh_auth_pid_cache(canon_users: dict[str, str]):
    """Scan recent Dropbear & OpenSSH journal entries to map worker PID -> canonical username."""
    # Prune exited PIDs first
    for dead in [p for p in PID_AUTH_CACHE if not Path(f"/proc/{p}").exists()]:
        PID_AUTH_CACHE.pop(dead, None)

    lines: list[str] = []
    try:
        out = subprocess.check_output(
            ["journalctl", "-u", "dropbear", "-u", "ssh", "-u", "sshd", "-n", "400", "--no-pager", "-o", "cat"],
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
            pid = int(m_db.group(1))
            u_low = m_db.group(2).lower()
            if u_low in canon_users and Path(f"/proc/{pid}").exists():
                PID_AUTH_CACHE[pid] = canon_users[u_low]
            continue
        m_sh = SSHD_AUTH_RE.search(ln)
        if m_sh:
            pid = int(m_sh.group(1))
            u_low = m_sh.group(2).lower()
            if u_low in canon_users and Path(f"/proc/{pid}").exists():
                PID_AUTH_CACHE[pid] = canon_users[u_low]


def query_haproxy_loopback_ips() -> dict[str, str]:
    """Map HAProxy backend 127.0.0.1:<port> -> real public client IP for SSH-SSL :443 tunnels."""
    mapping: dict[str, str] = {}
    if not HAPROXY_SOCK.exists():
        return mapping
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
            ip = m_src.group(1)
            if ip.startswith("::ffff:"):
                ip = ip[7:]
            if ip in ("127.0.0.1", "::1"):
                continue
            for m_lp in re.finditer(r"127\.0\.0\.1:(\d+)", block):
                lp = m_lp.group(1)
                if lp not in ("109", "143", "22", "2095", "4443", "8880", "8881"):
                    mapping[lp] = ip
    except Exception:
        pass
    return mapping


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
    """Read kernel I/O bytes transferred by a per-connection sshd/dropbear worker."""
    try:
        rchar, wchar = 0, 0
        for ln in Path(f"/proc/{pid}/io").read_text().splitlines():
            if ln.startswith("rchar:"):
                rchar = int(ln.split()[1])
            elif ln.startswith("wchar:"):
                wchar = int(ln.split()[1])
        # Bridge process reads from side A and writes to side B -> divide sum by 2
        return (rchar + wchar) // 2
    except Exception:
        return 0


def scan_ssh_sessions(managed_users: set[str]) -> tuple[dict[str, list[dict]], dict[str, int]]:
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

    hap_ips = query_haproxy_loopback_ips()

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
        real_ip = peer_ip

        if peer_ip == "127.0.0.1" and peer_port in wsd_map:
            PORT_TO_USER[peer_port] = username
            real_ip = wsd_map[peer_port].get("ip", "127.0.0.1")
        elif peer_ip == "127.0.0.1" and peer_port in hap_ips:
            real_ip = hap_ips[peer_port]
            cur_io = read_pid_io_bytes(target_pid)
            prev_io = PID_LAST_IO_BYTES.get(target_pid, 0)
            if cur_io > prev_io:
                deltas[username] += (cur_io - prev_io)
            PID_LAST_IO_BYTES[target_pid] = cur_io
        else:
            # Direct SSH / Dropbear on 22, 109, 143 (or local tunnel)
            cur_io = read_pid_io_bytes(target_pid)
            prev_io = PID_LAST_IO_BYTES.get(target_pid, 0)
            if cur_io > prev_io:
                deltas[username] += (cur_io - prev_io)
            PID_LAST_IO_BYTES[target_pid] = cur_io

        sessions_by_user[username].append({"pid": target_pid, "ip": real_ip})

    # Accumulate WS /alyan bytes across both live and recently-closed ports
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


def public_443_80_peers(exclude_ips: set[str]) -> list[str]:
    peers: list[str] = []
    try:
        out = subprocess.check_output(["ss", "-tn", "state", "established"], text=True, stderr=subprocess.DEVNULL, timeout=2.0)
        for ln in out.splitlines()[1:]:
            cols = ln.split()
            if len(cols) < 4:
                continue
            lport = cols[2].rsplit(":", 1)[-1]
            if lport not in ("80", "443"):
                continue
            pip = cols[3].rsplit(":", 1)[0].strip("[]")
            if pip.startswith("::ffff:"):
                pip = pip[7:]
            if pip and pip not in ("127.0.0.1", "::1") and pip not in exclude_ips and pip not in peers:
                peers.append(pip)
    except Exception:
        pass
    return peers


def poll_xray_stats_and_ips(
    xray_users: list[sqlite3.Row],
    ssh_known_ips: set[str],
) -> tuple[dict[str, int], dict[str, list[str]]]:
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
                timeout=3.5,
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
    seen_loopback_recent: set[str] = set()

    if XRAY_ACCESS_LOG.exists():
        try:
            with XRAY_ACCESS_LOG.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 65536))
                tail_lines = f.read().decode("utf-8", errors="ignore").splitlines()[-350:]
            for ln in tail_lines:
                if "accepted" not in ln or "email:" not in ln:
                    continue
                m_em = XRAY_EMAIL_RE.search(ln)
                m_ip = XRAY_FROM_RE.search(ln)
                if not m_em or not m_ip:
                    continue
                uid = tag_to_uuid.get(m_em.group(1).lower())
                if not uid:
                    continue
                line_ts = now_ts
                try:
                    parsed_dt = dt.datetime.strptime(ln[:19], "%Y/%m/%d %H:%M:%S")
                    age = (now_dt - parsed_dt).total_seconds()
                    if age > 35.0 or age < -60.0:
                        continue
                    line_ts = now_ts - max(0.0, age)
                except Exception:
                    pass
                ip = m_ip.group(1).strip("[]")
                if ip.startswith("::ffff:"):
                    ip = ip[7:]
                if ip in ("127.0.0.1", "::1"):
                    seen_loopback_recent.add(uid)
                else:
                    XRAY_RECENT_IPS.setdefault(uid, {})[ip] = max(
                        XRAY_RECENT_IPS.get(uid, {}).get(ip, 0.0), line_ts
                    )
        except Exception:
            pass

    fallback_peers: list[str] | None = None
    ips_by_uuid: dict[str, list[str]] = {}

    for r in xray_users:
        uid = r["uuid"]
        user_map = XRAY_RECENT_IPS.setdefault(uid, {})
        active_traffic = deltas.get(uid, 0) > 0

        # Keep existing IPs alive while bytes are actively moving on a long-lived stream
        if active_traffic and user_map:
            for ip_k in list(user_map.keys()):
                user_map[ip_k] = now_ts

        # Prune idle IPs older than 28s
        for ip_k in [k for k, ts in user_map.items() if now_ts - ts > 28.0]:
            user_map.pop(ip_k, None)

        # Fallback if traffic is actively flowing or loopback was logged without XFF
        if not user_map and (active_traffic or uid in seen_loopback_recent):
            if fallback_peers is None:
                fallback_peers = public_443_80_peers(ssh_known_ips)
            for fp in (fallback_peers[:1] or ["connected"]):
                user_map[fp] = now_ts

        # Enforce Xray multi-IP cap visibility / trim if needed
        ips_by_uuid[uid] = sorted(user_map.keys())

    return deltas, ips_by_uuid


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
    if not DB_PATH.exists():
        return

    conn = db_conn()
    try:
        settings_rows = {r["key"]: r["value"] for r in conn.execute("SELECT key, value FROM settings").fetchall()}
        iface = settings_rows.get("iface", "eth0")
        bot_cfg = json.loads(settings_rows.get("bot_json", "{}"))

        ssh_rows = conn.execute("SELECT * FROM ssh_users").fetchall()
        xray_rows = conn.execute("SELECT * FROM xray_users").fetchall()

        today = dt.date.today().isoformat()
        managed_ssh = {r["username"] for r in ssh_rows}
        ssh_sessions, ssh_deltas = scan_ssh_sessions(managed_ssh)

        ssh_active_ips = {
            s["ip"]
            for conns in ssh_sessions.values()
            for s in conns
            if s.get("ip") and s["ip"] not in ("127.0.0.1", "::1")
        }
        xray_deltas, xray_ips = poll_xray_stats_and_ips(xray_rows, ssh_active_ips)

        # 1. Update SSH quotas, enforce expiry, GB limit, and IP limit
        for r in ssh_rows:
            uname = r["username"]
            delta_b = int(ssh_deltas.get(uname, 0))
            used = int(r["used_bytes"]) + delta_b
            if delta_b > 0:
                conn.execute("UPDATE ssh_users SET used_bytes = ? WHERE username = ?", (used, uname))

            if r["status"] != "active":
                for s in ssh_sessions.get(uname, []):
                    if s.get("pid"):
                        subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                ssh_sessions[uname] = []
                continue

            gb_lim = float(r["gb_limit"] or 0)
            ip_lim = int(r["ip_limit"] or 0)

            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"SSH user `{uname}` expired ({r['expiry']})"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"SSH user `{uname}` reached {gb_lim} GB quota"

            if reason:
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
                continue

            # Enforce multi-IP limit
            conns = ssh_sessions.get(uname, [])
            uniq_ips = []
            for s in conns:
                if s["ip"] not in uniq_ips:
                    uniq_ips.append(s["ip"])
            if ip_lim > 0 and len(uniq_ips) > ip_lim:
                allowed_ips = set(uniq_ips[:ip_lim])
                for s in conns:
                    if s["ip"] not in allowed_ips and s.get("pid"):
                        subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                ssh_sessions[uname] = [s for s in conns if s["ip"] in allowed_ips]

        # 2. Update Xray quotas, enforce expiry & GB limit
        xray_resync_needed = False
        for r in xray_rows:
            uname = r["username"]
            uuid = r["uuid"]
            delta_x = int(xray_deltas.get(uuid, 0))
            used = int(r["used_bytes"]) + delta_x
            if delta_x > 0:
                conn.execute("UPDATE xray_users SET used_bytes = ? WHERE uuid = ?", (used, uuid))

            if r["status"] != "active":
                xray_ips[uuid] = []
                continue

            gb_lim = float(r["gb_limit"] or 0)
            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) expired"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) reached {gb_lim} GB quota"

            if reason:
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

    # 3. Record rolling telemetry & live snapshot
    cpu_pct = read_cpu_pct()
    ram_pct = read_ram_pct()
    rx_bps, tx_bps, rx_tot, tx_tot = read_net_rates(iface)

    HIST["cpu"] = (HIST["cpu"] + [cpu_pct])[-20:]
    HIST["ram"] = (HIST["ram"] + [ram_pct])[-20:]
    HIST["rx"] = (HIST["rx"] + [round((rx_bps * 8) / 1048576.0, 2)])[-20:]
    HIST["tx"] = (HIST["tx"] + [round((tx_bps * 8) / 1048576.0, 2)])[-20:]

    ssh_live = {}
    for uname, conns in ssh_sessions.items():
        ips = sorted({c["ip"] for c in conns if c.get("ip")})
        ssh_live[uname] = {"online": len(conns), "ips": ips}

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
        "ssh_live": ssh_live,
        "xray_live": xray_live,
    }
    tmp = LIVE_OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(snapshot), encoding="utf-8")
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

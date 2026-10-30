#!/usr/bin/env python3
"""
Alyan Webpanel — Autonomous Quota, Multi-IP & Expiry Enforcer (alyan-guard)
Continuously monitors SSH/Dropbear/WS-Proxy & Xray sessions:
  1. Correlates Dropbear/sshd PIDs -> Linux username -> Real Client IP (including /alyan WS).
  2. Accumulates SSH & Xray per-user bandwidth bytes into SQLite (/var/lib/alyan/alyan.db).
  3. Enforces per-user IP connection limits, GB bandwidth quotas, and expiry dates.
  4. Publishes rolling CPU/RAM/Net sparkline & live-online snapshot to /run/alyan-live.json.
"""
import datetime as dt
import json
import os
import re
import sqlite3
import subprocess
import time
import urllib.request
from pathlib import Path

DB_PATH = Path("/var/lib/alyan/alyan.db")
WSD_STATE = Path("/run/alyan-wsd-sessions.json")
LIVE_OUT = Path("/run/alyan-live.json")
XRAY_ACCESS_LOG = Path("/var/log/xray/access.log")

HIST = {"cpu": [], "ram": [], "rx": [], "tx": []}
LAST_CPU = None
LAST_NET = None
SSH_CONN_LAST_BYTES = {}


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
            return 8.0
        d_idle = idle - LAST_CPU[0]
        d_tot = max(1, total - LAST_CPU[1])
        LAST_CPU = (idle, total)
        return round(max(1.0, min(100.0, (1.0 - d_idle / d_tot) * 100.0)), 1)
    except Exception:
        return 8.0


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
    dt_s = max(0.5, now - LAST_NET[0])
    rx_bps = max(0.0, (rx_tot - LAST_NET[1]) / dt_s)
    tx_bps = max(0.0, (tx_tot - LAST_NET[2]) / dt_s)
    LAST_NET = (now, rx_tot, tx_tot)
    return rx_bps, tx_bps, rx_tot, tx_tot


def pid_to_username(pid: int, uid_map: dict[int, str]) -> str | None:
    """Resolve authenticated tunnel username for a Dropbear or sshd session PID."""
    try:
        status_txt = Path(f"/proc/{pid}/status").read_text()
        for line in status_txt.splitlines():
            if line.startswith("Uid:"):
                uids = [int(x) for x in line.split()[1:5]]
                for u in uids:
                    if u in uid_map:
                        return uid_map[u]
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\x00", b" ").decode("latin1", errors="ignore")
        # sshd: username [priv] or sshd: username@notty
        m = re.search(r"sshd:\s*([A-Za-z0-9_-]+)", cmdline)
        if m and m.group(1) in uid_map.values():
            return m.group(1)
        # Dropbear running as root after auth holds child or utmp/environ/journal; check journal/auth or child uid
        for child_task in Path("/proc").iterdir():
            if not child_task.name.isdigit():
                continue
            st_p = child_task / "status"
            if not st_p.exists():
                continue
            st = st_p.read_text()
            if f"PPid:\t{pid}\n" in st:
                for ln in st.splitlines():
                    if ln.startswith("Uid:"):
                        cuids = [int(x) for x in ln.split()[1:5]]
                        for cu in cuids:
                            if cu in uid_map:
                                return uid_map[cu]
    except Exception:
        pass
    return None


def scan_ssh_sessions(managed_users: set[str]) -> tuple[dict[str, list[dict]], dict[str, int]]:
    """
    Returns:
      sessions_by_user: { username: [ {"pid": pid, "ip": real_ip}, ... ] }
      delta_bytes_by_user: { username: bytes_since_last_tick }
    """
    uid_map: dict[int, str] = {}
    try:
        for line in Path("/etc/passwd").read_text().splitlines():
            parts = line.split(":")
            if len(parts) >= 4 and parts[0] in managed_users:
                uid_map[int(parts[2])] = parts[0]
    except Exception:
        pass

    wsd_map = {}
    if WSD_STATE.exists():
        try:
            wsd_map = json.loads(WSD_STATE.read_text(encoding="utf-8"))
        except Exception:
            wsd_map = {}

    sessions_by_user: dict[str, list[dict]] = {u: [] for u in managed_users}
    deltas: dict[str, int] = {u: 0 for u in managed_users}
    seen_ports = set()

    try:
        out = subprocess.check_output(["ss", "-tnp"], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        out = ""

    # Match established sockets to :22, :109, :143
    for line in out.splitlines():
        if "ESTAB" not in line:
            continue
        if "dropbear" not in line and "sshd" not in line:
            continue
        cols = line.split()
        if len(cols) < 6:
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
            u = pid_to_username(pid, uid_map)
            if u:
                username = u
                target_pid = pid
                break
        if not username:
            continue

        real_ip = peer_ip
        if peer_ip == "127.0.0.1" and peer_port in wsd_map:
            info = wsd_map[peer_port]
            real_ip = info.get("ip", "127.0.0.1")
            cur_b = int(info.get("bytes", 0))
            prev_b = SSH_CONN_LAST_BYTES.get(peer_port, 0)
            if cur_b >= prev_b:
                deltas[username] += (cur_b - prev_b)
            SSH_CONN_LAST_BYTES[peer_port] = cur_b
            seen_ports.add(peer_port)

        sessions_by_user[username].append({"pid": target_pid, "ip": real_ip})

    for stale in list(SSH_CONN_LAST_BYTES.keys()):
        if stale not in seen_ports and stale not in wsd_map:
            del SSH_CONN_LAST_BYTES[stale]

    return sessions_by_user, deltas


def poll_xray_stats_and_ips(xray_users: list[sqlite3.Row]) -> tuple[dict[str, int], dict[str, list[str]]]:
    """Query Xray StatsService (resetting counters after read) and tail access.log for recent active IPs."""
    deltas: dict[str, int] = {}
    if Path("/usr/local/bin/xray").exists():
        try:
            raw = subprocess.check_output(
                ["/usr/local/bin/xray", "api", "statsquery", "--server=127.0.0.1:10085", "-pattern", "user>>>", "-reset"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
            data = json.loads(raw) if raw.strip() else {}
            for st in data.get("stat", []):
                # name format: user>>>username@alyan>>>traffic>>>uplink|downlink
                parts = st.get("name", "").split(">>>")
                if len(parts) >= 4:
                    email = parts[1]
                    uname = email.split("@", 1)[0]
                    val = int(st.get("value", 0))
                    deltas[uname] = deltas.get(uname, 0) + val
        except Exception:
            pass

    ips_by_user: dict[str, list[str]] = {r["username"]: [] for r in xray_users}
    if XRAY_ACCESS_LOG.exists():
        try:
            # Read last 24 KB of access log for recent connections (last ~60s)
            with XRAY_ACCESS_LOG.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 24576))
                tail_lines = f.read().decode("utf-8", errors="ignore").splitlines()[-200:]
            cutoff = dt.datetime.now() - dt.timedelta(seconds=75)
            for ln in tail_lines:
                if "email:" not in ln:
                    continue
                m_em = re.search(r"email:\s*([A-Za-z0-9_-]+)@", ln)
                m_ip = re.search(r"from\s+(?:tcp:)?([0-9a-fA-F\.:]+):\d+", ln)
                if not m_em or not m_ip:
                    continue
                # Optional timestamp parse at line start YYYY/MM/DD HH:MM:SS
                try:
                    ts = dt.datetime.strptime(ln[:19], "%Y/%m/%d %H:%M:%S")
                    if ts < cutoff:
                        continue
                except Exception:
                    pass
                uname = m_em.group(1)
                ip = m_ip.group(1)
                if uname in ips_by_user and ip not in ("127.0.0.1", "::1") and ip not in ips_by_user[uname]:
                    ips_by_user[uname].append(ip)
        except Exception:
            pass

    return deltas, ips_by_user


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
        xray_deltas, xray_ips = poll_xray_stats_and_ips(xray_rows)

        # 1. Update SSH quotas, enforce expiry, GB limit, and IP limit
        for r in ssh_rows:
            uname = r["username"]
            used = int(r["used_bytes"]) + int(ssh_deltas.get(uname, 0))
            if ssh_deltas.get(uname, 0) > 0:
                conn.execute("UPDATE ssh_users SET used_bytes = ? WHERE username = ?", (used, uname))

            if r["status"] != "active":
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
            used = int(r["used_bytes"]) + int(xray_deltas.get(uname, 0))
            if xray_deltas.get(uname, 0) > 0:
                conn.execute("UPDATE xray_users SET used_bytes = ? WHERE uuid = ?", (used, uuid))

            if r["status"] != "active":
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
        uname = r["username"]
        ips = xray_ips.get(uname, [])
        xray_live[r["uuid"]] = {"online": len(ips), "ips": ips}

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
        time.sleep(6.0)


if __name__ == "__main__":
    main()

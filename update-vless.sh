#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  ALYAN WEBPANEL — VLESS Session-ID Live Users & Real-IP Update (Standalone)
#  - Keeps main GitHub panel files 100% untouched (safe live VPS test script)
#  - Leaves SSH / Dropbear / Alyan-WSD 100% untouched
#  - Preserves low ping (connIdle: 600, no aggressive WS heartbeat)
#  - Preserves clean 2-decimal GB formatting (e.g. 9.67 GB)
#  - Implements stateful VLESS Session-ID tracking (S1, S2, S3...) per UUID:
#      * Fixes Xray trustedXForwardedFor header unwrapping + statsUserOnline
#      * Unwraps Cloudflare, BunnyCDN (direct & CF-chained), CloudFront & XFF
#      * Binds 1 user's parallel WS streams (Dual-Stack IPv4+IPv6, 4G CGNAT
#        /16 pool, startup burst & cell handoff) into 1 Session ID & 1 IP
#      * Counts 2nd, 3rd... simultaneous users cleanly as Session 2, 3...
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

INSTALL_DIR="/opt/alyan"
REPO_RAW="https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main"
TS="$(date +%s)"

if [[ ! -d "${INSTALL_DIR}" ]]; then
  echo "Error: ${INSTALL_DIR} not found on this server." >&2
  exit 1
fi

echo -e "\033[38;5;208m[1/5]\033[0m Restoring clean SIM Real-IP baseline files into ${INSTALL_DIR}..."
curl -fsSL "${REPO_RAW}/templates/xray-config.json.tpl?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/templates/xray-config.json.tpl"
curl -fsSL "${REPO_RAW}/templates/nginx-router.conf.tpl?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/templates/nginx-router.conf.tpl"
curl -fsSL "${REPO_RAW}/services/guard/alyan-guard.py?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/services/guard/alyan-guard.py"
curl -fsSL "${REPO_RAW}/core/alyan-ctl?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/core/alyan-ctl"
curl -fsSL "${REPO_RAW}/panel/static/app.js?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/panel/static/app.js"

chmod +x "${INSTALL_DIR}/core/alyan-ctl" "${INSTALL_DIR}/services/guard/alyan-guard.py"
ln -sf "${INSTALL_DIR}/core/alyan-ctl" /usr/local/bin/alyan-ctl

echo -e "\033[38;5;208m[2/5]\033[0m Upgrading Xray Real-IP headers & OnlineMap (preserving fast ping)..."
python3 - <<'PYEOF'
import json
from pathlib import Path

# ── 1. Patch xray-config.json.tpl (statsUserOnline + valid header names in trustedXForwardedFor) ──
xray_tpl = Path("/opt/alyan/templates/xray-config.json.tpl")
x_txt = xray_tpl.read_text(encoding="utf-8")

old_policy = '''        "statsUserUplink": true,
        "statsUserDownlink": true,
        "bufferSize": 4096'''

new_policy = '''        "statsUserUplink": true,
        "statsUserDownlink": true,
        "statsUserOnline": true,
        "bufferSize": 4096'''

assert old_policy in x_txt, "Policy block not found in xray-config.json.tpl"
x_txt = x_txt.replace(old_policy, new_policy, 1)
x_txt = x_txt.replace(
    '"trustedXForwardedFor": ["127.0.0.1", "::1"]',
    '"trustedXForwardedFor": ["X-Forwarded-For", "X-Real-IP"]',
)
# Validate template renders valid JSON
test_json = (
    x_txt.replace("{{VLESS_CLIENTS}}", "[]")
    .replace("{{VMESS_CLIENTS}}", "[]")
    .replace("{{TROJAN_CLIENTS}}", "[]")
)
json.loads(test_json)
xray_tpl.write_text(x_txt, encoding="utf-8")
print("✔ xray-config.json.tpl updated (connIdle=600 preserved, statsUserOnline=true, XFF headers fixed).")
PYEOF

echo -e "\033[38;5;208m[3/5]\033[0m Upgrading Nginx CDN Real-IP unwrapping (Cloudflare + BunnyCDN + CloudFront)..."
python3 - <<'PYEOF'
import sqlite3
import subprocess
from pathlib import Path

ng_tpl = Path("/opt/alyan/templates/nginx-router.conf.tpl")
n_txt = ng_tpl.read_text(encoding="utf-8")

old_map_block = '''# CloudFront Viewer Address (AWS CloudFront Real Client IP without :port)
map $http_cloudfront_viewer_address $alyan_cf_viewer_ip {
    default                      "";
    "~^([0-9a-fA-F\\.:]+):\\d+"     $1;
}

# First IP from X-Forwarded-For
map $http_x_forwarded_for $alyan_xff_first {
    default                      "";
    "~^([0-9a-fA-F\\.:]+)"        $1;
}

# Unified CDN Header Priority: CloudFront Viewer Address -> CF-Connecting-IP -> True-Client-IP -> X-Forwarded-For
map $alyan_cf_viewer_ip $alyan_cdn_ip_step1 {
    ""      $http_cf_connecting_ip;
    default $alyan_cf_viewer_ip;
}

map $alyan_cdn_ip_step1 $alyan_cdn_ip_step2 {
    ""      $http_true_client_ip;
    default $alyan_cdn_ip_step1;
}

map $alyan_cdn_ip_step2 $alyan_cdn_resolved_ip {
    ""      $alyan_xff_first;
    default $alyan_cdn_ip_step2;
}

map $alyan_cdn_resolved_ip $alyan_real_ip {
    ""      $proxy_protocol_addr;
    default $alyan_cdn_resolved_ip;
}

log_format alyan_xray '$time_iso8601 $alyan_real_ip $status $request_uri';'''

new_map_block = '''# CloudFront Viewer Address (AWS CloudFront Real Client IP without :port)
map $http_cloudfront_viewer_address $alyan_cf_viewer_ip {
    default                        "";
    "~^\\[([0-9a-fA-F:]+)\\]:\\d+$"  $1;
    "~^([0-9\\.]+):\\d+$"            $1;
    "~^([0-9a-fA-F:]+):\\d+$"       $1;
    "~^([0-9a-fA-F\\.:]+)$"         $1;
}

# BunnyCDN Viewer Address (without :port if present)
map $http_b_cdn_viewer_address $alyan_bcdn_viewer_ip {
    default                                  "";
    "~^\\s*\\[([0-9a-fA-F:]+)\\]"            $1;
    "~^\\s*([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)" $1;
    "~^\\s*([0-9a-fA-F:]+)$"                 $1;
}

# First clean IP from X-Forwarded-For (strips optional :port or brackets)
map $http_x_forwarded_for $alyan_xff_first {
    default                                  "";
    "~^\\s*\\[([0-9a-fA-F:]+)\\]"            $1;
    "~^\\s*([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)" $1;
    "~^\\s*([0-9a-fA-F:]+)"                  $1;
}

# Detect BunnyCDN origin requests (even when chained BunnyCDN -> Cloudflare -> VPS)
map "$http_cdn_pullzone$http_cdn_requestcountrycode" $alyan_bcdn_xff_ip {
    ""      "";
    default $alyan_xff_first;
}

# Unified Real-IP Priority:
#   1. BunnyCDN Viewer / BunnyCDN XFF (prevents 2 BunnyCDN edge PoPs showing when chained via CF)
#   2. CloudFront-Viewer-Address
#   3. CF-Connecting-IP
#   4. True-Client-IP
#   5. X-Forwarded-For (first IP)
#   6. X-Real-IP
#   7. PROXY protocol peer IP
map $alyan_bcdn_viewer_ip $alyan_cdn_step0 {
    ""      $alyan_bcdn_xff_ip;
    default $alyan_bcdn_viewer_ip;
}

map $alyan_cdn_step0 $alyan_cdn_ip_step1 {
    ""      $alyan_cf_viewer_ip;
    default $alyan_cdn_step0;
}

map $alyan_cdn_ip_step1 $alyan_cdn_ip_step2 {
    ""      $http_cf_connecting_ip;
    default $alyan_cdn_ip_step1;
}

map $alyan_cdn_ip_step2 $alyan_cdn_ip_step3 {
    ""      $http_true_client_ip;
    default $alyan_cdn_ip_step2;
}

map $alyan_cdn_ip_step3 $alyan_cdn_ip_step4 {
    ""      $alyan_xff_first;
    default $alyan_cdn_ip_step3;
}

map $alyan_cdn_ip_step4 $alyan_cdn_resolved_ip {
    ""      $http_x_real_ip;
    default $alyan_cdn_ip_step4;
}

map $alyan_cdn_resolved_ip $alyan_real_ip {
    ""      $proxy_protocol_addr;
    default $alyan_cdn_resolved_ip;
}

log_format alyan_xray '$msec $alyan_real_ip $status $request_uri';'''

assert old_map_block in n_txt, "Nginx map block not found in nginx-router.conf.tpl"
n_txt = n_txt.replace(old_map_block, new_map_block, 1)
ng_tpl.write_text(n_txt, encoding="utf-8")

domain = "localhost"
db_path = Path("/var/lib/alyan/alyan.db")
if db_path.exists():
    try:
        conn = sqlite3.connect(str(db_path))
        row = conn.execute("SELECT value FROM settings WHERE key='domain'").fetchone()
        if row and row[0]:
            domain = str(row[0]).strip()
        conn.close()
    except Exception:
        pass

router_out = Path("/etc/nginx/conf.d/alyan-router.conf")
if router_out.parent.exists():
    prev_router = router_out.read_text(encoding="utf-8") if router_out.exists() else None
    router_out.write_text(n_txt.replace("{{DOMAIN}}", domain), encoding="utf-8")
    chk = subprocess.run(["nginx", "-t"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if chk.returncode == 0:
        subprocess.run(["systemctl", "reload", "nginx"], stderr=subprocess.DEVNULL)
        print(f"✔ Nginx router updated & reloaded cleanly for domain={domain}.")
    elif prev_router is not None:
        router_out.write_text(prev_router, encoding="utf-8")
        print("⚠ Kept existing /etc/nginx/conf.d/alyan-router.conf.")
PYEOF

echo -e "\033[38;5;208m[4/5]\033[0m Installing VLESS Session-ID Engine into alyan-guard.py & syncing app.js..."
python3 - <<'PYEOF'
from pathlib import Path

# ── 1. Patch alyan-guard.py with stateful VLESS Session-ID Engine ──
guard_path = Path("/opt/alyan/services/guard/alyan-guard.py")
g_txt = guard_path.read_text(encoding="utf-8")

# 1a. Add missing Cloudflare edge CIDR 141.193.213.0/24 & Fastly edge CIDRs to CF_EDGE_NETS
old_cf = '''        "141.101.64.0/18",'''
new_cf = '''        "141.101.64.0/18",
        "141.193.213.0/24",
        "151.101.0.0/16",
        "199.232.0.0/16",'''
assert old_cf in g_txt, "CF_EDGE_NETS target not found"
g_txt = g_txt.replace(old_cf, new_cf, 1)

# 1b. Add is_trusted_cdn + ip_family_and_prefixes + XRAY_SESSIONS structures
old_dev_fn = '''def device_key_for_ip(ip_str: str) -> str:
    """
    Normalize a client IP to a unique device key:
      - Unwrapped Cloudflare or CloudFront edge IPs collapse to 'cdn-edge' so PoP rotation never fakes 30 IPs.
      - IPv6 SLAAC privacy extensions collapse to their /64 subscriber prefix so 1 mobile phone = 1 device.
      - Standard public IPv4 maps 1:1 to itself.
    """
    try:
        addr = ipaddress.ip_address(ip_str)
        if any(addr in net for net in CF_EDGE_NETS):
            return "cdn-edge"
        # Known AWS CloudFront edge prefixes if any direct edge leaked
        if isinstance(addr, ipaddress.IPv4Address):
            s_ip = str(addr)
            if s_ip.startswith(("143.204.", "52.84.", "54.192.", "54.230.", "54.239.", "54.240.", "13.32.", "13.33.", "13.35.", "13.224.", "13.225.", "13.226.", "13.227.", "13.249.", "18.64.", "18.65.", "18.66.", "18.67.", "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.", "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.", "108.138.", "108.156.", "108.157.", "108.158.", "108.159.", "204.246.", "205.251.")):
                return "cdn-edge"
        if isinstance(addr, ipaddress.IPv6Address):
            net64 = ipaddress.IPv6Network((addr, 64), strict=False)
            return f"v6:{net64.network_address}/64"
        return str(addr)
    except ValueError:
        return ip_str'''

new_dev_fn = '''CLOUDFRONT_PREFIXES = (
    "143.204.", "52.84.", "54.192.", "54.230.", "54.239.", "54.240.",
    "13.32.", "13.33.", "13.35.", "13.224.", "13.225.", "13.226.", "13.227.", "13.249.",
    "18.64.", "18.65.", "18.66.", "18.67.", "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.",
    "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.",
    "108.138.", "108.156.", "108.157.", "108.158.", "108.159.", "204.246.", "205.251.",
)
XRAY_LOG_TS_RE = re.compile(r"^(\\d{4}/\\d{2}/\\d{2}\\s+\\d{2}:\\d{2}:\\d{2})(?:\\.\\d+)?")

# Per-UUID VLESS/Xray Session-ID table:
#   uuid -> { session_id: { "session_id", "primary_ip", "ips", "net_keys", "super_keys",
#                           "has_v4", "v6_super", "created_at", "last_seen" } }
XRAY_SESSIONS: dict[str, dict[str, dict]] = {}
XRAY_SESSION_SEQ: dict[str, int] = {}
XRAY_ONLINE_ALL_SUPPORTED = True


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
    """
    Extract (ip_version, subscriber_net_key, carrier_super_key):
      - IPv4: /16 CGNAT pool key + /12 carrier superblock key
      - IPv6: /56 subscriber prefix + /48 carrier prefix
    """
    addr = ipaddress.ip_address(ip_str)
    if isinstance(addr, ipaddress.IPv4Address):
        net16 = ipaddress.IPv4Network((addr, 16), strict=False)
        net12 = ipaddress.IPv4Network((addr, 12), strict=False)
        return 4, f"v4:{net16.network_address}/16", f"v4s:{net12.network_address}/12"
    net56 = ipaddress.IPv6Network((addr, 56), strict=False)
    net48 = ipaddress.IPv6Network((addr, 48), strict=False)
    return 6, f"v6:{net56.network_address}/56", f"v6s:{net48.network_address}/48"


def parse_xray_log_ts(line: str) -> float | None:
    """Parse YYYY/MM/DD HH:MM:SS timestamp at the beginning of an Xray access.log line."""
    m = XRAY_LOG_TS_RE.match(line.strip())
    if not m:
        return None
    try:
        return dt.datetime.strptime(m.group(1), "%Y/%m/%d %H:%M:%S").timestamp()
    except Exception:
        return None


def device_key_for_ip(ip_str: str) -> str:
    if is_trusted_cdn(ip_str):
        return "cdn-edge"
    try:
        _, net_k, _ = ip_family_and_prefixes(ip_str)
        return net_k
    except ValueError:
        return ip_str'''

assert old_dev_fn in g_txt, "device_key_for_ip block not found in alyan-guard.py"
g_txt = g_txt.replace(old_dev_fn, new_dev_fn, 1)

# 1c. Fix read_recent_nginx_xray_ips so non-numeric timestamps (if any legacy lines exist) are skipped instead of passing forever
old_ng_ts = '''            try:
                log_ts = float(parts[0])
                if (now_ts - log_ts) > max_age_sec:
                    continue
            except ValueError:
                pass'''

new_ng_ts = '''            try:
                log_ts = float(parts[0])
                if (now_ts - log_ts) > max_age_sec or (now_ts - log_ts) < -5.0:
                    continue
            except ValueError:
                continue'''

assert old_ng_ts in g_txt, "read_recent_nginx_xray_ips timestamp block not found"
g_txt = g_txt.replace(old_ng_ts, new_ng_ts, 1)

# 1d. Replace poll_xray_stats_and_ips with the VLESS Session-ID Engine
old_poll = '''def poll_xray_stats_and_ips(
    xray_users: list[sqlite3.Row],
    ws_ips: list[str],
    h2c_ips: list[str],
    trojan_ips: list[str],
) -> tuple[dict[str, int], dict[str, list[str]], dict[str, int]]:
    """
    Returns:
      - deltas: uuid -> bytes transferred since last 2s tick
      - ips_by_uuid: uuid -> sorted clean unique client IPs (1 IP per active connection)
      - dev_count_by_uuid: uuid -> count of distinct active devices
    """
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
    proto_socket_counts = scan_active_proto_sockets()
    nginx_proto_ips = read_recent_nginx_xray_ips(max_age_sec=6.0)
    latest_ip_from_log: dict[str, str] = {}

    if XRAY_ACCESS_LOG.exists():
        try:
            with XRAY_ACCESS_LOG.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 32768))
                tail_lines = f.read().decode("utf-8", errors="ignore").splitlines()[-100:]
            for ln in tail_lines:
                if "accepted" not in ln or "email:" not in ln:
                    continue
                m_em = XRAY_EMAIL_RE.search(ln)
                if not m_em:
                    continue
                uid = tag_to_uuid.get(m_em.group(1).lower())
                if not uid:
                    continue

                proto = uuid_to_proto.get(uid, "vless")
                ip_clean, was_loop = parse_xray_source_ip(ln)
                matched_ip = ip_clean

                if was_loop or not matched_ip:
                    # Connection proxied through Nginx/HAProxy (127.0.0.1 loopback)
                    if proto in nginx_proto_ips and nginx_proto_ips[proto]:
                        matched_ip = nginx_proto_ips[proto][-1]
                    elif proto in ("vless", "vmess") and ws_ips:
                        matched_ip = ws_ips[0]
                    elif proto == "trojan":
                        matched_ip = trojan_ips[0] if trojan_ips else (ws_ips[0] if ws_ips else None)
                    elif h2c_ips:
                        matched_ip = h2c_ips[0]

                if matched_ip:
                    latest_ip_from_log[uid] = matched_ip
        except Exception:
            pass

    ips_by_uuid: dict[str, list[str]] = {}
    dev_count_by_uuid: dict[str, int] = {}

    for r in xray_users:
        uid = r["uuid"]
        proto = r["proto"].lower()
        dev_map = XRAY_ACTIVE_DEVICES.setdefault(uid, {})
        user_traffic = deltas.get(uid, 0)
        active_traffic = user_traffic > 0
        active_sockets = proto_socket_counts.get(proto, 0)

        if active_traffic:
            XRAY_LAST_ACTIVE_TS[uid] = now_ts

        idle_sec = now_ts - XRAY_LAST_ACTIVE_TS.get(uid, 0)

        # ── REAL-TIME DISCONNECT (within 2 seconds) ──
        # Disconnect triggers immediately if no active sockets exist OR if no traffic for > 3.0 seconds
        if active_sockets == 0 or (not active_traffic and idle_sec > 3.0):
            dev_map.clear()
            ips_by_uuid[uid] = []
            dev_count_by_uuid[uid] = 0
            continue

        # If data is actively transferring OR user is within 3.0s active window:
        best_ip = None
        if uid in latest_ip_from_log:
            best_ip = latest_ip_from_log[uid]
        elif proto in nginx_proto_ips and nginx_proto_ips[proto]:
            best_ip = nginx_proto_ips[proto][-1]
        elif proto in ("vless", "vmess") and ws_ips:
            best_ip = ws_ips[0]
        elif proto == "trojan":
            best_ip = trojan_ips[0] if trojan_ips else (ws_ips[0] if ws_ips else None)
        elif h2c_ips:
            best_ip = h2c_ips[0]

        if best_ip:
            dev_k = f"{best_ip}:{len(dev_map)}" if best_ip in dev_map else best_ip
            dev_map[dev_k] = {"ip": best_ip, "ts": now_ts}
            max_devs = max(1, active_sockets)
            if len(dev_map) > max_devs:
                sorted_keys = sorted(dev_map.keys(), key=lambda k: dev_map[k]["ts"], reverse=True)
                for k in sorted_keys[max_devs:]:
                    dev_map.pop(k, None)

        # Short timeout (3.5s) for any lingering device
        for stale_k in [k for k, v in dev_map.items() if (now_ts - v["ts"]) > 3.5]:
            dev_map.pop(stale_k, None)

        ips_by_uuid[uid] = sorted({v["ip"] for v in dev_map.values()})
        dev_count_by_uuid[uid] = max(len(ips_by_uuid[uid]), len(dev_map))

    return deltas, ips_by_uuid, dev_count_by_uuid'''

new_poll = '''def query_xray_online_map(
    xray_users: list[sqlite3.Row],
    tag_to_uuid: dict[str, str],
) -> tuple[dict[str, list[str]], bool]:
    """
    Query Xray's live ref-counted OnlineMap (statsUserOnline).
    An IP exists in OnlineMap ONLY while at least 1 stream for that user's UUID is currently open!
    Supports both `-all` (Xray v25/v26+) and per-user `-email` fallback.
    """
    global XRAY_ONLINE_ALL_SUPPORTED
    om_by_uid: dict[str, list[str]] = {}
    xray_bin = Path("/usr/local/bin/xray")
    if not xray_bin.exists():
        return om_by_uid, False

    if XRAY_ONLINE_ALL_SUPPORTED:
        proc = subprocess.run(
            [str(xray_bin), "api", "statsonlineiplist", "--server=127.0.0.1:10085", "-all"],
            capture_output=True,
            text=True,
            timeout=2.5,
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
                    for ip_ent in u_obj.get("ips", []) or []:
                        ip_c = clean_public_ip(str(ip_ent.get("ip") or ""))
                        if ip_c and ip_c not in lst:
                            lst.append(ip_c)
                return om_by_uid, True
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
                    if isinstance(ips_map, dict):
                        for raw_ip in ips_map.keys():
                            ip_c = clean_public_ip(str(raw_ip))
                            if ip_c and ip_c not in lst:
                                lst.append(ip_c)
                except Exception:
                    pass
        return om_by_uid, any_queried

    return om_by_uid, False


def update_vless_user_sessions(
    uid: str,
    live_om_ips: list[str],
    recent_log_ips: list[str],
    online_map_ok: bool,
    active_traffic: bool,
    active_sockets: int,
    now_ts: float,
) -> tuple[list[str], int]:
    """
    Stateful VLESS Session-ID Engine:
      - Assigns discrete Session IDs (S1, S2, S3...) per connected user on `uid`.
      - Binds 1 mobile phone's parallel WebSocket/gRPC/XHTTP streams into 1 Session ID:
          1) Same /16 IPv4 CGNAT subscriber pool or /56 IPv6 prefix -> same Session ID
          2) Dual-Stack (IPv4 + IPv6 simultaneously on 1 VoLTE SIM) -> merged into 1 Session ID
          3) Same /12 carrier superblock within 3.0s initial connection burst -> same Session ID
          4) Seamless CGNAT IP handover when a session's previous IP closes in OnlineMap -> reuses Session ID
      - Pins `primary_ip` per session so Connected IPs & Live Users stay rock-solid (1, 2, 3...) without flicker.
    """
    sessions = XRAY_SESSIONS.setdefault(uid, {})

    if active_sockets == 0:
        sessions.clear()
        XRAY_SESSION_SEQ[uid] = 0
        return [], 0

    if active_traffic:
        XRAY_LAST_ACTIVE_TS[uid] = now_ts
    idle_sec = now_ts - XRAY_LAST_ACTIVE_TS.get(uid, 0)

    real_live_set = {ip for ip in live_om_ips if not is_trusted_cdn(ip)}
    raw_real_cands: list[str] = []
    cdn_cands: list[str] = []

    for ip in live_om_ips + recent_log_ips:
        if is_trusted_cdn(ip):
            if ip not in cdn_cands:
                cdn_cands.append(ip)
        else:
            if ip not in raw_real_cands:
                raw_real_cands.append(ip)

    # Sort IPv4 before IPv6 so Dual-Stack phones always pin their clean IPv4 as primary_ip
    def _ip_sort_key(ip_s: str) -> int:
        try:
            return 0 if ipaddress.ip_address(ip_s).version == 4 else 1
        except ValueError:
            return 2

    real_cands = sorted(raw_real_cands, key=_ip_sort_key)

    if real_cands:
        # Never allow fallback CDN edge session to coexist alongside real client SIM IPs
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

            # Rule 2: Dual-Stack (IPv4 + IPv6 on the same phone, regardless of which family opened first)
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

            # Rule 4: Seamless CGNAT IP handover (old session's IPs closed in OnlineMap while new IP opened)
            if matched_sess is None and online_map_ok:
                recent_set = set(recent_log_ips)
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
                # Distinct user connected -> assign next Session ID (S1, S2, S3...)
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
    elif not sessions and cdn_cands and (active_traffic or bool(live_om_ips)):
        # Only unwrapped CDN edge IPs visible -> collapse ALL CDN PoPs into 1 single session
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
    elif sessions and cdn_cands and "S-CDN" in sessions and (active_traffic or bool(live_om_ips)):
        sessions["S-CDN"]["ips"].update(cdn_cands)
        sessions["S-CDN"]["last_seen"] = now_ts

    live_all_set = set(live_om_ips)
    for sid, s in list(sessions.items()):
        s.pop("_touched", None)
        has_open_stream = bool(s["ips"] & live_all_set)
        if has_open_stream and (active_traffic or idle_sec <= 45.0):
            s["last_seen"] = now_ts
        elif len(sessions) == 1 and active_traffic:
            s["last_seen"] = now_ts

        # Expire disconnected session cleanly after 4.5s without open stream or traffic
        if (now_ts - s["last_seen"]) > 4.5:
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
    ws_ips: list[str],
    h2c_ips: list[str],
    trojan_ips: list[str],
) -> tuple[dict[str, int], dict[str, list[str]], dict[str, int]]:
    """
    Returns:
      - deltas: uuid -> bytes transferred since last 2s tick
      - ips_by_uuid: uuid -> 1 pinned primary client IP per active Session ID
      - dev_count_by_uuid: uuid -> active Session ID count (1, 2, 3...)
    """
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
                timeout=3.0,
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
    proto_socket_counts = scan_active_proto_sockets()
    om_by_uid, online_map_ok = query_xray_online_map(xray_users, tag_to_uuid)
    nginx_proto_ips = read_recent_nginx_xray_ips(max_age_sec=4.0)
    recent_log_ips_by_uid: dict[str, list[str]] = {}

    if XRAY_ACCESS_LOG.exists():
        try:
            with XRAY_ACCESS_LOG.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 49152))
                tail_lines = f.read().decode("utf-8", errors="ignore").splitlines()[-150:]
            for ln in tail_lines:
                if "accepted" not in ln or "email:" not in ln:
                    continue
                log_ts = parse_xray_log_ts(ln)
                if log_ts is None or (now_ts - log_ts) > 4.0 or (now_ts - log_ts) < -5.0:
                    continue
                m_em = XRAY_EMAIL_RE.search(ln)
                if not m_em:
                    continue
                em_tag = m_em.group(1).lower()
                uid = tag_to_uuid.get(em_tag) or tag_to_uuid.get(em_tag.split(".", 1)[0])
                if not uid:
                    continue

                proto = uuid_to_proto.get(uid, "vless")
                ip_clean, was_loop = parse_xray_source_ip(ln)
                matched_ip = ip_clean

                if (was_loop or not matched_ip) and proto in nginx_proto_ips and nginx_proto_ips[proto]:
                    matched_ip = nginx_proto_ips[proto][-1]

                if matched_ip:
                    lst = recent_log_ips_by_uid.setdefault(uid, [])
                    if matched_ip not in lst:
                        lst.append(matched_ip)
        except Exception:
            pass

    ips_by_uuid: dict[str, list[str]] = {}
    dev_count_by_uuid: dict[str, int] = {}

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
        active_sockets = proto_socket_counts.get(proto, 0)
        live_om = om_by_uid.get(uid, [])
        recent_lg = recent_log_ips_by_uid.get(uid, [])

        # Direct Trojan TCP fallback only if OnlineMap & access.log had no entry yet
        if not live_om and not recent_lg and proto == "trojan" and active_traffic and trojan_ips:
            non_cdn_tr = [ip for ip in trojan_ips if not is_trusted_cdn(ip)]
            recent_lg = non_cdn_tr[:1] if non_cdn_tr else trojan_ips[:1]

        u_ips, u_cnt = update_vless_user_sessions(
            uid=uid,
            live_om_ips=live_om,
            recent_log_ips=recent_lg,
            online_map_ok=online_map_ok,
            active_traffic=active_traffic,
            active_sockets=active_sockets,
            now_ts=now_ts,
        )
        ips_by_uuid[uid] = u_ips
        dev_count_by_uuid[uid] = u_cnt

    return deltas, ips_by_uuid, dev_count_by_uuid'''

assert old_poll in g_txt, "poll_xray_stats_and_ips target block not found in alyan-guard.py"
g_txt = g_txt.replace(old_poll, new_poll, 1)

# 1e. Clean up disabled/snapshot handling in enforce_cycle so session counts & IPs never drift apart
old_snap = '''    xray_live = {}
    for r in xray_rows:
        uid = r["uuid"]
        ips = xray_ips.get(uid, [])
        user_sess_cnt = xray_fresh_devs.get(uid, 0)
        if user_sess_cnt == 0 and ips:
            user_sess_cnt = len(ips)
        if user_sess_cnt == 0 and int(xray_deltas.get(uid, 0)) > 0:
            user_sess_cnt = 1
        xray_live[uid] = {"online": user_sess_cnt, "ips": ips}'''

new_snap = '''    xray_live = {}
    for r in xray_rows:
        uid = r["uuid"]
        ips = xray_ips.get(uid, [])
        user_sess_cnt = xray_fresh_devs.get(uid, 0)
        if user_sess_cnt == 0 and ips:
            user_sess_cnt = len(ips)
        xray_live[uid] = {"online": user_sess_cnt, "ips": ips}'''

assert old_snap in g_txt, "xray_live snapshot block not found in alyan-guard.py"
g_txt = g_txt.replace(old_snap, new_snap, 1)

# Also clear XRAY_SESSIONS when an account is auto-disabled
g_txt = g_txt.replace(
    "XRAY_ACTIVE_DEVICES.pop(uuid, None)",
    "XRAY_ACTIVE_DEVICES.pop(uuid, None)\n                XRAY_SESSIONS.pop(uuid, None)\n                XRAY_SESSION_SEQ.pop(uuid, None)",
)

# Compile-check before saving
compile(g_txt, str(guard_path), "exec")
guard_path.write_text(g_txt, encoding="utf-8")
print("✔ VLESS Session-ID Engine installed and syntax-verified in alyan-guard.py.")

# ── 2. Patch app.js so Connected IPs, Top Live Users & Card Live Users all sync to Session IDs ──
app_js_path = Path("/opt/alyan/panel/static/app.js")
j_txt = app_js_path.read_text(encoding="utf-8")

old_js_top = '''    const getLiveIps = () => items.flatMap(u => (u.status === 'disabled' ? [] : (u.ips || [])).map(ip => ({ user: u.username, proto: u.proto.toUpperCase(), ip })));

    const getXrayLiveUsersTotal = () => items.filter(u => u.proto === STATE.xrayProto).reduce((acc, u) => acc + (u.status === 'disabled' ? 0 : (u.online || (u.ips || []).length || 0)), 0);
    const getXrayLiveUsersList = () => items
      .filter(u => u.status !== 'disabled' && u.proto === STATE.xrayProto && (u.online > 0 || (u.ips && u.ips.length > 0)))
      .map(u => ({
        user: u.username,
        proto: u.proto.toUpperCase(),
        online: u.online || (u.ips || []).length || 0,
        limit: u.ip_limit > 0 ? `${u.ip_limit} Users` : 'Unlimited'
      }));'''

new_js_top = '''    const getLiveIps = () => items
      .filter(u => u.status !== 'disabled' && u.proto === STATE.xrayProto)
      .flatMap(u => (u.ips || []).map((ip, idx) => ({ user: `${u.username} (S${idx + 1})`, proto: u.proto.toUpperCase(), ip })));

    const getXrayLiveUsersTotal = () => items
      .filter(u => u.proto === STATE.xrayProto)
      .reduce((acc, u) => acc + (u.status === 'disabled' ? 0 : (Number(u.online) || (u.ips || []).length || 0)), 0);
    const getXrayLiveUsersList = () => items
      .filter(u => u.status !== 'disabled' && u.proto === STATE.xrayProto && (Number(u.online) > 0 || (u.ips && u.ips.length > 0)))
      .map(u => ({
        user: u.username,
        proto: u.proto.toUpperCase(),
        online: Number(u.online) || (u.ips || []).length || 0,
        limit: u.ip_limit > 0 ? `${u.ip_limit} Users` : 'Unlimited'
      }));'''

assert old_js_top in j_txt, "Top Xray getters not found in app.js"
j_txt = j_txt.replace(old_js_top, new_js_top, 1)

old_js_card = '''        const ipList = isDis ? [] : (u.ips || []);
        const onlineCnt = isDis ? 0 : (ipList.length || u.online || 0);'''

new_js_card = '''        const ipList = isDis ? [] : (u.ips || []);
        const onlineCnt = isDis ? 0 : (Number(u.online) || ipList.length || 0);'''

assert old_js_card in j_txt, "Card onlineCnt line not found in app.js"
j_txt = j_txt.replace(old_js_card, new_js_card, 1)

app_js_path.write_text(j_txt, encoding="utf-8")
print("✔ app.js synced with VLESS Session-ID counts (2-decimal GB formatting preserved).")
PYEOF

echo -e "\033[38;5;208m[5/5]\033[0m Syncing Xray config, clearing stale logs & restarting Xray/Guard/Panel..."
/usr/local/bin/alyan-ctl xray-sync
: > /var/log/xray/access.log 2>/dev/null || true
: > /var/log/nginx/alyan-xray.log 2>/dev/null || true
rm -f /run/alyan-live.json /run/alyan-live.tmp
systemctl restart xray alyan-guard alyan-panel

echo -e "\033[38;5;82m✔ VLESS Session-ID update applied! Refresh browser with Ctrl+F5 and test 1, 2, 3 users.\033[0m"

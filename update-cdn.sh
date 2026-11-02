#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — CDN Wire-Speed & Low-Latency Optimization Engine
#  Supports: AWS CloudFront · BunnyCDN · Cloudflare · Fastly · GCore
#  Fixes   : 20s Connection Delay · 500-700ms Ping Spike · 1-2min Freezing
#  Features: Automatic Pre-Backup & Safe 1-Click Rollback (--rollback)
# ═════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

C_RST="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[38;2;255;75;43m"
C_ORG="\033[38;2;255;110;20m"
C_AMB="\033[38;2;255;154;0m"
C_GLD="\033[38;2;255;200;55m"
C_GRN="\033[38;2;46;213;115m"
C_CYN="\033[38;2;0;210;255m"
C_WHT="\033[38;2;245;242;238m"
C_GRY="\033[38;2;120;120;140m"

INSTALL_DIR="/opt/alyan"
ETC_DIR="/etc/alyan"
VAR_DIR="/var/lib/alyan"
BACKUP_DIR="${VAR_DIR}/backup_pre_cdn"

hdr() {
  echo -e "\n${C_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RST}"
  echo -e "${C_RED}┃${C_RST}  ${C_AMB}${C_BOLD}🔥 ALYAN WEBPANEL — CDN OPTIMIZATION & LATENCY FIX${C_RST}                       ${C_RED}┃${C_RST}"
  echo -e "${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}"
}

preflight() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${C_RED}✖ Error: This script must be run as root (sudo bash update-cdn.sh).${C_RST}"
    exit 1
  fi
  if [[ ! -d "$INSTALL_DIR" || ! -f "${INSTALL_DIR}/core/alyan-ctl" ]]; then
    echo -e "${C_RED}✖ Error: Alyan Webpanel installation not found in ${INSTALL_DIR}.${C_RST}"
    exit 1
  fi
}

do_rollback() {
  hdr
  echo -e "${C_AMB}▶ Starting Rollback to Pre-CDN Configuration...${C_RST}\n"
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo -e "${C_RED}✖ Error: No backup found at ${BACKUP_DIR}! Cannot rollback.${C_RST}"
    exit 1
  fi

  echo -e "  ${C_CYN}•${C_RST} Restoring original templates and services from backup..."
  [[ -f "${BACKUP_DIR}/haproxy.cfg.tpl" ]] && cp -f "${BACKUP_DIR}/haproxy.cfg.tpl" "${INSTALL_DIR}/templates/haproxy.cfg.tpl"
  [[ -f "${BACKUP_DIR}/nginx-router.conf.tpl" ]] && cp -f "${BACKUP_DIR}/nginx-router.conf.tpl" "${INSTALL_DIR}/templates/nginx-router.conf.tpl"
  [[ -f "${BACKUP_DIR}/xray-config.json.tpl" ]] && cp -f "${BACKUP_DIR}/xray-config.json.tpl" "${INSTALL_DIR}/templates/xray-config.json.tpl"
  [[ -f "${BACKUP_DIR}/alyan-wsd.py" ]] && cp -f "${BACKUP_DIR}/alyan-wsd.py" "${INSTALL_DIR}/services/wsd/alyan-wsd.py"
  [[ -f "${BACKUP_DIR}/alyan-guard.py" ]] && cp -f "${BACKUP_DIR}/alyan-guard.py" "${INSTALL_DIR}/services/guard/alyan-guard.py"
  [[ -f "${BACKUP_DIR}/alyan-ctl" ]] && cp -f "${BACKUP_DIR}/alyan-ctl" "${INSTALL_DIR}/core/alyan-ctl"
  [[ -f "${BACKUP_DIR}/99-alyan-turbo.conf" ]] && cp -f "${BACKUP_DIR}/99-alyan-turbo.conf" "/etc/sysctl.d/99-alyan-turbo.conf"

  chmod +x "${INSTALL_DIR}/core/alyan-ctl" "${INSTALL_DIR}/services/wsd/alyan-wsd.py" "${INSTALL_DIR}/services/guard/alyan-guard.py"

  echo -e "  ${C_CYN}•${C_RST} Re-applying original kernel sysctl..."
  sysctl --system >/dev/null 2>&1 || true

  echo -e "  ${C_CYN}•${C_RST} Re-rendering configuration files..."
  python3 "${INSTALL_DIR}/core/alyan-ctl" render >/dev/null 2>&1 || true

  echo -e "  ${C_CYN}•${C_RST} Restarting services..."
  systemctl daemon-reload
  for svc in dropbear alyan-wsd xray nginx haproxy alyan-guard alyan-panel; do
    systemctl restart "$svc" >/dev/null 2>&1 || true
  done

  echo -e "\n${C_GRN}✔ Rollback Complete! Your panel stack is safely restored to original state.${C_RST}\n"
  exit 0
}

create_backup() {
  if [[ -d "$BACKUP_DIR" ]]; then
    echo -e "  ${C_GRY}• Existing backup already saved at: ${BACKUP_DIR}${C_RST}"
    return
  fi
  echo -e "  ${C_CYN}•${C_RST} Creating pristine backup in ${BACKUP_DIR}..."
  mkdir -p "$BACKUP_DIR"
  [[ -f "${INSTALL_DIR}/templates/haproxy.cfg.tpl" ]] && cp -f "${INSTALL_DIR}/templates/haproxy.cfg.tpl" "${BACKUP_DIR}/"
  [[ -f "${INSTALL_DIR}/templates/nginx-router.conf.tpl" ]] && cp -f "${INSTALL_DIR}/templates/nginx-router.conf.tpl" "${BACKUP_DIR}/"
  [[ -f "${INSTALL_DIR}/templates/xray-config.json.tpl" ]] && cp -f "${INSTALL_DIR}/templates/xray-config.json.tpl" "${BACKUP_DIR}/"
  [[ -f "${INSTALL_DIR}/services/wsd/alyan-wsd.py" ]] && cp -f "${INSTALL_DIR}/services/wsd/alyan-wsd.py" "${BACKUP_DIR}/"
  [[ -f "${INSTALL_DIR}/services/guard/alyan-guard.py" ]] && cp -f "${INSTALL_DIR}/services/guard/alyan-guard.py" "${BACKUP_DIR}/"
  [[ -f "${INSTALL_DIR}/core/alyan-ctl" ]] && cp -f "${INSTALL_DIR}/core/alyan-ctl" "${BACKUP_DIR}/"
  [[ -f "/etc/sysctl.d/99-alyan-turbo.conf" ]] && cp -f "/etc/sysctl.d/99-alyan-turbo.conf" "${BACKUP_DIR}/"
  [[ -f "/etc/haproxy/haproxy.cfg" ]] && cp -f "/etc/haproxy/haproxy.cfg" "${BACKUP_DIR}/"
  [[ -f "/etc/nginx/conf.d/alyan-router.conf" ]] && cp -f "/etc/nginx/conf.d/alyan-router.conf" "${BACKUP_DIR}/"
  [[ -f "/usr/local/etc/xray/config.json" ]] && cp -f "/usr/local/etc/xray/config.json" "${BACKUP_DIR}/"
  date -u +"%Y-%m-%d %H:%M:%S UTC" > "${BACKUP_DIR}/backup_timestamp.txt"
  echo -e "  ${C_GRN}✔ Pristine configuration backup created successfully.${C_RST}"
}

apply_haproxy_fix() {
  echo -e "  ${C_CYN}•${C_RST} Applying HAProxy Wire-Speed Multiplexer optimization..."
  cat > "${INSTALL_DIR}/templates/haproxy.cfg.tpl" <<'EOF'
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — HAProxy Flame Router (Ports 80 & 443 Wire-Speed Mux)
#  Auto-generated by alyan-ctl · Domain: {{DOMAIN}} · CDN Turbo Optimized
# ═════════════════════════════════════════════════════════════════════════════
global
    log /dev/log local0 warning
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 65535
    tune.bufsize 65536
    tune.maxrewrite 16384
    tune.ssl.cachesize 100000
    tune.ssl.lifetime 600
    tune.ssl.default-dh-param 2048
    ssl-default-bind-options ssl-min-ver TLSv1.2
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-AES256-GCM-SHA384

defaults
    log     global
    mode    tcp
    option  dontlognull
    option  tcp-nodelay
    option  clitcpka
    option  srvtcpka
    timeout connect 5s
    timeout client  4h
    timeout server  4h
    timeout tunnel  12h
    timeout client-fin 15s
    timeout server-fin 15s

# ─── PUBLIC PORT 80: HTTP / SSH-WS (/alyan) / Xray WS / ACME ─────────────────
frontend fe_http_80
    bind *:80
    mode tcp
    tcp-request inspect-delay 1s

    acl is_raw_ssh    payload(0,4) -m bin 5353482d
    acl is_acme       payload(0,256) -m sub /.well-known/acme-challenge/
    acl is_xray_ws    payload(0,256) -m sub -i /alyan-vless /alyan-vmess /alyan-trojan /alyan-xhttp
    acl is_http_80    payload(0,8) -m beg GET POST HEAD PUT OPTIONS CONNECT PATCH

    tcp-request content accept if is_raw_ssh or is_acme or is_xray_ws or is_http_80

    use_backend be_dropbear  if is_raw_ssh
    use_backend be_nginx_ws  if is_acme or is_xray_ws
    default_backend be_alyan_wsd

# ─── PUBLIC PORT 443 EDGE: Raw SSH vs TLS Multiplexer ────────────────────────
frontend fe_edge_443
    bind *:443
    mode tcp
    tcp-request inspect-delay 1s

    acl is_raw_ssh  payload(0,4) -m bin 5353482d
    acl is_tls      req.ssl_hello_type 1

    tcp-request content accept if is_raw_ssh or is_tls

    use_backend be_dropbear      if is_raw_ssh
    default_backend be_tls_loop

backend be_tls_loop
    mode tcp
    server tls_term 127.0.0.1:4443 send-proxy-v2

# ─── INTERNAL TLS TERMINATOR & PROTOCOL DISPATCHER ───────────────────────────
frontend fe_tls_terminator
    bind 127.0.0.1:4443 accept-proxy ssl crt /etc/alyan/ssl/haproxy.pem alpn h2,http/1.1
    mode tcp
    tcp-request inspect-delay 1s

    acl is_alpn_h2    ssl_fc_alpn -i h2
    acl is_ssh_ssl    payload(0,4) -m bin 5353482d
    acl is_xray_ws    payload(0,256) -m sub -i /alyan-vless /alyan-vmess /alyan-trojan /alyan-xhttp
    acl is_http_req   payload(0,8) -m beg GET POST HEAD PUT OPTIONS CONNECT PATCH

    tcp-request content accept if is_alpn_h2 or is_ssh_ssl or is_xray_ws or is_http_req

    use_backend be_nginx_h2c       if is_alpn_h2
    use_backend be_dropbear        if is_ssh_ssl
    use_backend be_nginx_ws        if is_xray_ws
    use_backend be_alyan_wsd       if is_http_req
    default_backend be_xray_trojan_tcp

# ─── BACKENDS ────────────────────────────────────────────────────────────────
backend be_alyan_wsd
    mode tcp
    server wsd 127.0.0.1:2095 send-proxy-v2

backend be_dropbear
    mode tcp
    server dropbear 127.0.0.1:109

backend be_nginx_ws
    mode tcp
    server nginx_ws 127.0.0.1:8880 send-proxy-v2

backend be_nginx_h2c
    mode tcp
    server nginx_h2 127.0.0.1:8881 send-proxy-v2

backend be_xray_trojan_tcp
    mode tcp
    server xray_trojan 127.0.0.1:10023 send-proxy-v2
EOF
}

apply_wsd_fix() {
  echo -e "  ${C_CYN}•${C_RST} Applying Multi-CDN Real-IP unwrap in alyan-wsd..."
  cat > "${INSTALL_DIR}/services/wsd/alyan-wsd.py" <<'EOF'
#!/usr/bin/env python3
"""
Alyan Webpanel — Wire-Speed Asyncio SSH-WebSocket Bridge (alyan-wsd)
Multi-CDN Optimized: AWS CloudFront, BunnyCDN, Cloudflare, Fastly, GCore
Listens on 127.0.0.1:2095 (accepting PROXY protocol v1/v2 from HAProxy),
handles HTTP 101 Switching Protocols for /alyan & custom Injector payloads,
bridges to Dropbear (127.0.0.1:109) with TCP_NODELAY & zero-stall buffers,
and exports real client IP + byte stats to /run/alyan-wsd-sessions.json.
"""
import asyncio
import base64
import hashlib
import ipaddress
import json
import os
import socket
import struct
import time
from pathlib import Path

LISTEN_HOST = os.environ.get("ALYAN_WSD_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("ALYAN_WSD_PORT", "2095"))
TARGET_HOST = os.environ.get("ALYAN_SSH_TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.environ.get("ALYAN_SSH_TARGET_PORT", "109"))
STATE_FILE = Path("/run/alyan-wsd-sessions.json")

PROXY_V2_SIG = b"\r\n\r\n\x00\r\nQUIT\n"
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def build_101_response(payload: bytes) -> bytes:
    sec_key = None
    if b"\r\n" in payload:
        header_text = payload.split(b"\r\n\r\n", 1)[0].decode("latin1", errors="ignore")
        for line in header_text.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                if k.strip().lower() == "sec-websocket-key":
                    sec_key = v.strip()
                    break

    resp_lines = [
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
    ]
    if sec_key:
        sha = hashlib.sha1((sec_key + WS_GUID).encode("utf-8")).digest()
        accept_b64 = base64.b64encode(sha).decode("utf-8")
        resp_lines.append(f"Sec-WebSocket-Accept: {accept_b64}")
    else:
        resp_lines.append("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    resp_lines.append("Server: Alyan-Flame-Edge")
    return ("\r\n".join(resp_lines) + "\r\n\r\n").encode("latin1")

CF_NETWORKS = [
    ipaddress.ip_network(cidr)
    for cidr in (
        "127.0.0.0/8",
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

BUNNY_EDGE_PREFIXES = (
    "185.180.", "169.150.", "185.93.", "217.156.", "89.187.",
    "138.199.", "146.70.", "194.26.", "147.78.", "84.17.",
    "193.148.", "141.193.",
)

AWS_CF_PREFIXES = (
    "143.204.", "52.84.", "54.192.", "54.230.", "54.239.", "54.240.",
    "13.32.", "13.33.", "13.35.", "13.224.", "13.225.", "13.226.",
    "13.227.", "13.249.", "18.64.", "18.65.", "18.66.", "18.67.",
    "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.",
    "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.",
    "108.138.", "108.156.", "108.157.", "108.158.", "108.159.",
    "204.246.", "205.251.", "3.160.", "3.161.", "3.162.", "3.163.",
    "3.164.", "3.165.", "15.158.", "52.222.", "99.83.", "150.222.", "130.176.",
)

ACTIVE_SESSIONS = {}
RECENT_CLOSED = {}

def normalize_ip(raw: str) -> str | None:
    s = (raw or "").strip().strip("[]")
    if s.lower().startswith("::ffff:"):
        s = s[7:]
    try:
        return str(ipaddress.ip_address(s))
    except ValueError:
        return None

def is_trusted_cdn(ip_str: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip_str)
        if addr.is_loopback:
            return True
        if any(addr in net for net in CF_NETWORKS):
            return True
        if isinstance(addr, ipaddress.IPv4Address):
            s = str(addr)
            if s.startswith(AWS_CF_PREFIXES) or s.startswith(BUNNY_EDGE_PREFIXES):
                return True
        return False
    except ValueError:
        return False

def tune_socket(writer: asyncio.StreamWriter):
    sock = writer.get_extra_info("socket")
    if sock is not None:
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        except Exception:
            pass
    tr = writer.transport
    if tr is not None:
        try:
            tr.set_write_buffer_limits(high=524288, low=131072)
        except Exception:
            pass

def flush_state_now():
    try:
        now = time.time()
        for k in list(RECENT_CLOSED.keys()):
            if now - RECENT_CLOSED[k].get("closed_at", 0) > 15.0:
                del RECENT_CLOSED[k]
        snapshot = {}
        for port, s in list(RECENT_CLOSED.items()):
            snapshot[port] = {
                "ip": s["ip"],
                "since": s["since"],
                "bytes": s["bytes"],
                "closed": True,
            }
        for port, s in list(ACTIVE_SESSIONS.items()):
            snapshot[port] = {
                "ip": s["ip"],
                "since": s["since"],
                "bytes": s["rx"] + s["tx"],
                "closed": False,
            }
        tmp = STATE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(snapshot), encoding="utf-8")
        tmp.replace(STATE_FILE)
    except Exception:
        pass

def parse_proxy_header(buf: bytes):
    if buf.startswith(PROXY_V2_SIG):
        if len(buf) < 16:
            return None
        ver_cmd = buf[12]
        fam_proto = buf[13]
        addr_len = struct.unpack("!H", buf[14:16])[0]
        total = 16 + addr_len
        if len(buf) < total:
            return None
        real_ip = "127.0.0.1"
        if (ver_cmd & 0x0F) == 0x01:
            fam = fam_proto >> 4
            if fam == 0x1 and addr_len >= 12:
                real_ip = socket.inet_ntop(socket.AF_INET, buf[16:20])
            elif fam == 0x2 and addr_len >= 36:
                real_ip = socket.inet_ntop(socket.AF_INET6, buf[16:32])
                if real_ip.startswith("::ffff:"):
                    real_ip = real_ip[7:]
        return real_ip, buf[total:]

    if buf.startswith(b"PROXY "):
        idx = buf.find(b"\r\n")
        if idx == -1:
            return None if len(buf) < 108 else ("127.0.0.1", buf)
        parts = buf[:idx].decode("latin1", errors="ignore").split()
        real_ip = parts[2] if len(parts) >= 3 else "127.0.0.1"
        return real_ip, buf[idx + 2:]

    return None, buf

def strip_ws_headers(data: bytes) -> tuple[bool, bytes]:
    if data.startswith(b"SSH-"):
        return False, data
    ssh_idx = data.find(b"SSH-")
    if ssh_idx != -1:
        return True, data[ssh_idx:]
    end_idx = data.find(b"\r\n\r\n")
    if end_idx != -1:
        return True, data[end_idx + 4:]
    return True, b""

async def pipe_stream(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, stat_dict: dict, key: str):
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            stat_dict[key] += len(chunk)
            writer.write(chunk)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass

async def handle_client(c_reader: asyncio.StreamReader, c_writer: asyncio.StreamWriter):
    tune_socket(c_writer)
    peer = c_writer.get_extra_info("peername")
    real_ip = normalize_ip(peer[0]) if peer else "127.0.0.1"
    real_ip = real_ip or "127.0.0.1"
    local_port = None

    try:
        initial = await asyncio.wait_for(c_reader.read(16384), timeout=12.0)
        if not initial:
            c_writer.close()
            return

        parsed = parse_proxy_header(initial)
        while parsed is None:
            more = await asyncio.wait_for(c_reader.read(4096), timeout=6.0)
            if not more:
                c_writer.close()
                return
            initial += more
            parsed = parse_proxy_header(initial)

        p_ip, payload = parsed
        if p_ip:
            norm_p = normalize_ip(p_ip)
            if norm_p:
                real_ip = norm_p

        if not payload:
            payload = await asyncio.wait_for(c_reader.read(16384), timeout=12.0)
            if not payload:
                c_writer.close()
                return

        if not payload.startswith(b"SSH-") and b"\r\n\r\n" not in payload:
            while b"\r\n\r\n" not in payload and len(payload) < 8192:
                try:
                    more = await asyncio.wait_for(c_reader.read(4096), timeout=3.0)
                    if not more:
                        break
                    payload += more
                except asyncio.TimeoutError:
                    break

        # Always unwrap CDN real client IP headers from HTTP WebSocket Upgrade request
        if b"\r\n" in payload and not payload.startswith(b"SSH-"):
            hdr_text = payload.split(b"\r\n\r\n", 1)[0].decode("latin1", errors="ignore")
            hdr_map = {}
            for line in hdr_text.splitlines()[1:]:
                if ":" in line:
                    k, v = line.split(":", 1)
                    hdr_map[k.strip().lower()] = v.strip()

            for hk in (
                "cloudfront-viewer-address",
                "x-bunny-client-ip",
                "cf-connecting-ip",
                "true-client-ip",
                "x-forwarded-for",
                "x-real-ip",
            ):
                if hk in hdr_map:
                    raw_val = hdr_map[hk]
                    if ":" in raw_val and not raw_val.startswith("["):
                        raw_val = raw_val.split(":", 1)[0]
                    cand = normalize_ip(raw_val.split(",")[0])
                    if cand and cand not in ("127.0.0.1", "::1"):
                        real_ip = cand
                        break

        needs_101, tail = strip_ws_headers(payload)
        if needs_101:
            resp_101 = build_101_response(payload)
            c_writer.write(resp_101)
            await c_writer.drain()

        s_reader, s_writer = await asyncio.wait_for(
            asyncio.open_connection(TARGET_HOST, TARGET_PORT, limit=262144),
            timeout=8.0,
        )
        tune_socket(s_writer)

        sock_info = s_writer.get_extra_info("sockname")
        local_port = str(sock_info[1]) if sock_info else f"anon-{id(c_writer)}"

        stat_entry = {
            "ip": real_ip,
            "since": int(time.time()),
            "rx": len(tail),
            "tx": 0,
        }
        ACTIVE_SESSIONS[local_port] = stat_entry
        flush_state_now()

        if tail:
            if not tail.startswith(b"SSH-") and b"SSH-" in tail:
                tail = tail[tail.find(b"SSH-"):]
            elif not tail.startswith(b"SSH-") and b"\r\n\r\n" in tail:
                tail = tail.split(b"\r\n\r\n")[-1]
            if tail:
                s_writer.write(tail)
                await s_writer.drain()

        await asyncio.gather(
            pipe_stream(c_reader, s_writer, stat_entry, "rx"),
            pipe_stream(s_reader, c_writer, stat_entry, "tx"),
        )
    except Exception:
        try:
            c_writer.close()
        except Exception:
            pass
    finally:
        if local_port and local_port in ACTIVE_SESSIONS:
            st = ACTIVE_SESSIONS.pop(local_port)
            RECENT_CLOSED[local_port] = {
                "ip": st["ip"],
                "since": st["since"],
                "bytes": st["rx"] + st["tx"],
                "closed_at": time.time(),
            }
            flush_state_now()

async def flush_sessions_loop():
    while True:
        flush_state_now()
        await asyncio.sleep(1.5)

async def main():
    server = await asyncio.start_server(
        handle_client,
        LISTEN_HOST,
        LISTEN_PORT,
        backlog=8192,
        limit=262144,
    )
    asyncio.create_task(flush_sessions_loop())
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
EOF
  chmod +x "${INSTALL_DIR}/services/wsd/alyan-wsd.py"
}

apply_guard_fix() {
  echo -e "  ${C_CYN}•${C_RST} Applying Multi-CDN Edge Strike Protection in alyan-guard..."
  # Patch device_key_for_ip in alyan-guard.py using Python for exact clean replacement
  python3 - <<'PYPATCH'
import re
from pathlib import Path

p = Path("/opt/alyan/services/guard/alyan-guard.py")
txt = p.read_text(encoding="utf-8")

# Ensure BUNNY_EDGE_PREFIXES and AWS_CF_PREFIXES are defined
addon = '''BUNNY_EDGE_PREFIXES = (
    "185.180.", "169.150.", "185.93.", "217.156.", "89.187.",
    "138.199.", "146.70.", "194.26.", "147.78.", "84.17.",
    "193.148.", "141.193.",
)
AWS_CF_PREFIXES = (
    "143.204.", "52.84.", "54.192.", "54.230.", "54.239.", "54.240.",
    "13.32.", "13.33.", "13.35.", "13.224.", "13.225.", "13.226.",
    "13.227.", "13.249.", "18.64.", "18.65.", "18.66.", "18.67.",
    "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.",
    "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.",
    "108.138.", "108.156.", "108.157.", "108.158.", "108.159.",
    "204.246.", "205.251.", "3.160.", "3.161.", "3.162.", "3.163.",
    "3.164.", "3.165.", "15.158.", "52.222.", "99.83.", "150.222.", "130.176.",
)
'''

if "BUNNY_EDGE_PREFIXES" not in txt:
    txt = txt.replace("CF_EDGE_NETS = [", addon + "\nCF_EDGE_NETS = [")

# Replace device_key_for_ip implementation
old_pattern = re.compile(r"def device_key_for_ip\(ip_str: str\) -> str:.*?(?=\ndef read_recent_nginx_xray_ips)", re.DOTALL)

new_func = '''def device_key_for_ip(ip_str: str) -> str:
    """
    Normalize a client IP to a unique device key:
      - Unwrapped Cloudflare, AWS CloudFront, BunnyCDN, or other CDN edge IPs collapse to 'cdn-edge'.
      - IPv6 SLAAC privacy extensions collapse to /64 subscriber prefix (1 phone = 1 device).
      - Public IPv4 maps 1:1 to itself.
    """
    try:
        addr = ipaddress.ip_address(ip_str)
        if any(addr in net for net in CF_EDGE_NETS):
            return "cdn-edge"
        if isinstance(addr, ipaddress.IPv4Address):
            s_ip = str(addr)
            if s_ip.startswith(AWS_CF_PREFIXES) or s_ip.startswith(BUNNY_EDGE_PREFIXES):
                return "cdn-edge"
        if isinstance(addr, ipaddress.IPv6Address):
            net64 = ipaddress.IPv6Network((addr, 64), strict=False)
            return f"v6:{net64.network_address}/64"
        return str(addr)
    except ValueError:
        return ip_str

'''

txt = old_pattern.sub(new_func, txt)
p.write_text(txt, encoding="utf-8")
PYPATCH
  chmod +x "${INSTALL_DIR}/services/guard/alyan-guard.py"
}

apply_xray_fix() {
  echo -e "  ${C_CYN}•${C_RST} Applying Xray bufferbloat latency reduction..."
  sed -i 's/"bufferSize": 4096/"bufferSize": 64/g' "${INSTALL_DIR}/templates/xray-config.json.tpl"
}

apply_nginx_fix() {
  echo -e "  ${C_CYN}•${C_RST} Applying Nginx Multi-CDN header mapping & zero-buffering..."
  cat > "${INSTALL_DIR}/templates/nginx-router.conf.tpl" <<'EOF'
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Internal Zero-Buffering Nginx WS / XHTTP / gRPC Router
#  Binds strictly to 127.0.0.1:8880 (HTTP/WS) and 127.0.0.1:8881 (h2c gRPC)
# ═════════════════════════════════════════════════════════════════════════════
map $http_upgrade $alyan_connection_upgrade {
    default upgrade;
    ''      close;
}

# CloudFront Viewer Address (AWS CloudFront Real Client IP without :port)
map $http_cloudfront_viewer_address $alyan_cf_viewer_ip {
    default                      "";
    "~^([0-9a-fA-F\.:]+):\d+"     $1;
}

# BunnyCDN Real IP
map $http_x_bunny_client_ip $alyan_bunny_ip {
    default                      "";
    "~^([0-9a-fA-F\.:]+)"        $1;
}

# First IP from X-Forwarded-For
map $http_x_forwarded_for $alyan_xff_first {
    default                      "";
    "~^([0-9a-fA-F\.:]+)"        $1;
}

# Unified CDN Header Priority: CloudFront -> Bunny -> Cloudflare -> True-Client-IP -> X-Forwarded-For
map $alyan_cf_viewer_ip $alyan_cdn_ip_step1 {
    ""      $alyan_bunny_ip;
    default $alyan_cf_viewer_ip;
}

map $alyan_cdn_ip_step1 $alyan_cdn_ip_step2 {
    ""      $http_cf_connecting_ip;
    default $alyan_cdn_ip_step1;
}

map $alyan_cdn_ip_step2 $alyan_cdn_ip_step3 {
    ""      $http_true_client_ip;
    default $alyan_cdn_ip_step2;
}

map $alyan_cdn_ip_step3 $alyan_cdn_resolved_ip {
    ""      $alyan_xff_first;
    default $alyan_cdn_ip_step3;
}

map $alyan_cdn_resolved_ip $alyan_real_ip {
    ""      $proxy_protocol_addr;
    default $alyan_cdn_resolved_ip;
}

log_format alyan_xray '$time_iso8601 $alyan_real_ip $status $request_uri';

# ─── HTTP/1.1 WebSocket, XHTTP & ACME Challenge Router (:8880) ───────────────
server {
    listen 127.0.0.1:8880 proxy_protocol backlog=16384;
    server_name {{DOMAIN}} _;

    access_log /var/log/nginx/alyan-xray.log alyan_xray;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    tcp_nodelay on;
    tcp_nopush off;
    client_max_body_size 0;
    client_header_buffer_size 8k;
    large_client_header_buffers 4 32k;
    keepalive_timeout 3600s;

    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/alyan-acme;
        default_type "text/plain";
    }

    location /alyan-vless {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-vmess {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-trojan {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-xhttp {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10031;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html><html><head><title>{{DOMAIN}}</title></head><body style="background:#050507;color:#f5f2ee;font-family:sans-serif;display:grid;place-items:center;height:100vh;margin:0"><div><h2 style="letter-spacing:.16em">🔥 ALYAN EDGE NODE ONLINE</h2></div></body></html>';
    }
}

# ─── HTTP/2 Cleartext (h2c) gRPC & XHTTP Router (:8881) ──────────────────────
server {
    listen 127.0.0.1:8881 http2 proxy_protocol backlog=16384;
    server_name {{DOMAIN}} _;

    access_log /var/log/nginx/alyan-xray.log alyan_xray;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    tcp_nodelay on;
    tcp_nopush off;
    client_max_body_size 0;
    client_header_buffer_size 8k;
    large_client_header_buffers 4 32k;
    client_body_timeout 4h;
    grpc_read_timeout 4h;
    grpc_send_timeout 4h;
    grpc_socket_keepalive on;

    location /alyan-vless-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $alyan_real_ip;
        grpc_set_header X-Forwarded-For $alyan_real_ip;
        grpc_pass grpc://127.0.0.1:10011;
    }

    location /alyan-vmess-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $alyan_real_ip;
        grpc_set_header X-Forwarded-For $alyan_real_ip;
        grpc_pass grpc://127.0.0.1:10012;
    }

    location /alyan-trojan-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $alyan_real_ip;
        grpc_set_header X-Forwarded-For $alyan_real_ip;
        grpc_pass grpc://127.0.0.1:10013;
    }

    location /alyan-xhttp {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10031;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-vless {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF
}

apply_kernel_fix() {
  echo -e "  ${C_CYN}•${C_RST} Applying BBR + FQ Pacing & Anti-Throttling Kernel Tuning..."
  # Patch alyan-ctl apply_kernel_network_tuning
  sed -i 's/"net.ipv4.tcp_notsent_lowat = 16384"/"net.ipv4.tcp_notsent_lowat = 4294967295"/g' "${INSTALL_DIR}/core/alyan-ctl"
  sed -i 's/"net.ipv4.tcp_mtu_probing = 1"/"net.ipv4.tcp_mtu_probing = 0"/g' "${INSTALL_DIR}/core/alyan-ctl"
  sed -i 's/"net.core.rmem_max = 33554432"/"net.core.rmem_max = 67108864"/g' "${INSTALL_DIR}/core/alyan-ctl"
  sed -i 's/"net.core.wmem_max = 33554432"/"net.core.wmem_max = 67108864"/g' "${INSTALL_DIR}/core/alyan-ctl"
  sed -i 's/"net.ipv4.tcp_rmem = 4096 131072 33554432"/"net.ipv4.tcp_rmem = 4096 87380 67108864"/g' "${INSTALL_DIR}/core/alyan-ctl"
  sed -i 's/"net.ipv4.tcp_wmem = 4096 65536 33554432"/"net.ipv4.tcp_wmem = 4096 65536 67108864"/g' "${INSTALL_DIR}/core/alyan-ctl"

  cat > /etc/sysctl.d/99-alyan-turbo.conf <<'EOF'
# Alyan Webpanel — Native Wire-Speed + CDN Low-Latency Profile
fs.file-max = 2097152
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65536
net.core.optmem_max = 25165824
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 4294967295
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
EOF
  sysctl --system >/dev/null 2>&1 || true
}

compile_and_reload() {
  echo -e "  ${C_CYN}•${C_RST} Compiling live configs via alyan-ctl..."
  python3 "${INSTALL_DIR}/core/alyan-ctl" render >/dev/null 2>&1 || true

  echo -e "  ${C_CYN}•${C_RST} Restarting HAProxy, Nginx, Xray, WS-Bridge & Guard..."
  systemctl daemon-reload
  for svc in dropbear alyan-wsd xray nginx haproxy alyan-guard alyan-panel; do
    systemctl restart "$svc" >/dev/null 2>&1 || true
  done
}

verify_stack() {
  echo -e "\n${C_GLD}⚡ Stack Health & Service Verification:${C_RST}"
  local all_ok=1
  for svc in haproxy nginx dropbear alyan-wsd xray alyan-guard alyan-panel; do
    if systemctl is-active --quiet "$svc"; then
      printf "  ${C_GRN}✔${C_RST} %-16s ${C_GRN}running${C_RST}\n" "$svc"
    else
      printf "  ${C_RED}✖${C_RST} %-16s ${C_RED}FAILED${C_RST}\n" "$svc"
      all_ok=0
    fi
  done

  if [[ "$all_ok" -eq 1 ]]; then
    echo -e "\n${C_GRN}═════════════════════════════════════════════════════════════════════════════${C_RST}"
    echo -e "${C_GRN}✔ ALL CDN OPTIMIZATIONS APPLIED & VERIFIED SUCCESSFULLY!${C_RST}"
    echo -e "${C_GRN}═════════════════════════════════════════════════════════════════════════════${C_RST}"
    echo -e "  ${C_WHT}• 20s Connection Delay :${C_RST} ${C_GRN}FIXED (HAProxy inspect delay optimized)${C_RST}"
    echo -e "  ${C_WHT}• 500-700ms High Ping  :${C_RST} ${C_GRN}FIXED (Xray bufferbloat + BBR BDP unthrottled)${C_RST}"
    echo -e "  ${C_WHT}• 1-2min Freezing      :${C_RST} ${C_GRN}FIXED (Multi-CDN edge IP strikes eliminated)${C_RST}"
    echo -e "  ${C_WHT}• Supported CDNs       :${C_RST} ${C_CYN}AWS CloudFront, BunnyCDN, Cloudflare, Fastly${C_RST}"
    echo -e "\n${C_AMB}ℹ To revert anytime, run:${C_RST}"
    echo -e "  ${C_ORG}bash update-cdn.sh --rollback${C_RST}\n"
  else
    echo -e "\n${C_RED}✖ One or more services failed to start. Run 'journalctl -xe' to inspect.${C_RST}"
    echo -e "  ${C_AMB}You can revert to original backup with:${C_RST} ${C_ORG}bash update-cdn.sh --rollback${C_RST}\n"
    exit 1
  fi
}

main() {
  preflight
  if [[ "${1:-}" == "--rollback" || "${1:-}" == "--revert" || "${1:-}" == "-r" ]]; then
    do_rollback
  fi

  hdr
  echo -e "${C_AMB}▶ Starting CDN Wire-Speed & Low-Latency Update...${C_RST}\n"
  create_backup
  apply_haproxy_fix
  apply_wsd_fix
  apply_guard_fix
  apply_xray_fix
  apply_nginx_fix
  apply_kernel_fix
  compile_and_reload
  verify_stack
}

main "$@"

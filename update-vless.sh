#!/usr/bin/env bash
{
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — VLESS Per-Session-ID 2s Disconnect + Idle-Online + 1:1 Data
#  1) Per-Session-ID Asyncio Bridge (10091..10094 -> 10001..10031) like SSH wsd
#  2) Stays ONLINE continuously when VLESS is connected & phone sits idle on side
#  3) Goes OFFLINE in 2 seconds per Session ID (2->1 or 1->0) on disconnect
#  4) Exact 1:1 data counting (0 KB Xray buffer, 64 KB socket clamp)
#  Safe Standalone Updater (Does NOT touch SSH / Dropbear / alyan-wsd)
# ═════════════════════════════════════════════════════════════════════════════
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: Please run as root (sudo bash)." >&2
  exit 1
fi

echo "════════════════════════════════════════════════════════════════════"
echo " 🔥 ALYAN VLESS — Session-ID 2s Disconnect + Idle-Online + 1:1 Data"
echo "════════════════════════════════════════════════════════════════════"

# ─── [1/5] Apply Tight Kernel TCP Backpressure & Fast Keepalive ──────────────
echo "[1/5] Locking kernel TCP socket backpressure & fast keepalive probes..."
mkdir -p /etc/sysctl.d
cat <<'EOF_SYSCTL' > /etc/sysctl.d/99-alyan-turbo.conf
# Alyan Webpanel — Wire-Speed + Exact 1:1 Proxy Accounting + Low-Bufferbloat Profile
fs.file-max = 2097152
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65536
net.core.optmem_max = 25165824
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.rmem_max = 524288
net.core.wmem_max = 524288
net.ipv4.tcp_rmem = 4096 65536 262144
net.ipv4.tcp_wmem = 4096 65536 262144
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 5
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_keepalive_time = 15
net.ipv4.tcp_keepalive_intvl = 3
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_retries2 = 5
EOF_SYSCTL

sysctl --system >/dev/null 2>&1 || true
sysctl -w net.core.rmem_default=65536 >/dev/null 2>&1 || true
sysctl -w net.core.wmem_default=65536 >/dev/null 2>&1 || true
sysctl -w net.core.rmem_max=524288 >/dev/null 2>&1 || true
sysctl -w net.core.wmem_max=524288 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_rmem="4096 65536 262144" >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_wmem="4096 65536 262144" >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_fin_timeout=5 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_keepalive_time=15 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_keepalive_intvl=3 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_keepalive_probes=3 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_retries2=5 >/dev/null 2>&1 || true

# Patch alyan-ctl on VPS so future config syncs keep these exact sysctl values
python3 - <<'EOF_PATCH_CTL'
from pathlib import Path
for p_str in ("/opt/alyan/core/alyan-ctl", "/usr/local/bin/alyan-ctl"):
    p = Path(p_str)
    if not p.exists() or p.is_symlink():
        continue
    txt = p.read_text(encoding="utf-8")
    txt = txt.replace('"net.core.rmem_default = 262144"', '"net.core.rmem_default = 65536"')
    txt = txt.replace('"net.core.wmem_default = 262144"', '"net.core.wmem_default = 65536"')
    txt = txt.replace('"net.core.rmem_max = 67108864"', '"net.core.rmem_max = 524288"')
    txt = txt.replace('"net.core.wmem_max = 67108864"', '"net.core.wmem_max = 524288"')
    txt = txt.replace('"net.ipv4.tcp_rmem = 4096 87380 67108864"', '"net.ipv4.tcp_rmem = 4096 65536 262144"')
    txt = txt.replace('"net.ipv4.tcp_wmem = 4096 65536 67108864"', '"net.ipv4.tcp_wmem = 4096 65536 262144"')
    txt = txt.replace('"net.ipv4.tcp_notsent_lowat = 4294967295"', '"net.ipv4.tcp_notsent_lowat = 16384"')
    p.write_text(txt, encoding="utf-8")
EOF_PATCH_CTL

# ─── [2/5] Update Xray Template (heartbeatPeriod: 1, downlinkOnly: 0, bufferSize: 0) ─
echo "[2/5] Updating Xray template (heartbeatPeriod: 1, downlinkOnly: 0, connIdle: 3600, bufferSize: 0)..."
mkdir -p /opt/alyan/templates
cat <<'EOF_XRAY_TPL' > /opt/alyan/templates/xray-config.json.tpl
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "stats": {},
  "api": {
    "tag": "api",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 3600,
        "uplinkOnly": 3600,
        "downlinkOnly": 0,
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "statsUserOnline": true,
        "bufferSize": 0
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "api-in",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    },
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "settings": {
        "clients": {{VLESS_CLIENTS}},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/alyan-vless",
          "heartbeatPeriod": 1
        },
        "sockopt": {
          "tcpNoDelay": true,
          "trustedXForwardedFor": ["X-Forwarded-For", "X-Real-IP"],
          "tcpWindowClamp": 65536
        }
      }
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vmess",
      "settings": {
        "clients": {{VMESS_CLIENTS}}
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/alyan-vmess",
          "heartbeatPeriod": 1
        },
        "sockopt": {
          "tcpNoDelay": true,
          "trustedXForwardedFor": ["X-Forwarded-For", "X-Real-IP"],
          "tcpWindowClamp": 65536
        }
      }
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "trojan",
      "settings": {
        "clients": {{TROJAN_CLIENTS}}
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/alyan-trojan",
          "heartbeatPeriod": 1
        },
        "sockopt": {
          "tcpNoDelay": true,
          "trustedXForwardedFor": ["X-Forwarded-For", "X-Real-IP"],
          "tcpWindowClamp": 65536
        }
      }
    },
    {
      "tag": "vless-grpc",
      "listen": "127.0.0.1",
      "port": 10011,
      "protocol": "vless",
      "settings": {
        "clients": {{VLESS_CLIENTS}},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "alyan-vless-grpc"
        },
        "sockopt": {
          "tcpNoDelay": true,
          "trustedXForwardedFor": ["X-Forwarded-For", "X-Real-IP"],
          "tcpWindowClamp": 65536
        }
      }
    },
    {
      "tag": "vmess-grpc",
      "listen": "127.0.0.1",
      "port": 10012,
      "protocol": "vmess",
      "settings": {
        "clients": {{VMESS_CLIENTS}}
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "alyan-vmess-grpc"
        },
        "sockopt": {
          "tcpNoDelay": true,
          "trustedXForwardedFor": ["X-Forwarded-For", "X-Real-IP"],
          "tcpWindowClamp": 65536
        }
      }
    },
    {
      "tag": "trojan-grpc",
      "listen": "127.0.0.1",
      "port": 10013,
      "protocol": "trojan",
      "settings": {
        "clients": {{TROJAN_CLIENTS}}
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "alyan-trojan-grpc"
        },
        "sockopt": {
          "tcpNoDelay": true,
          "trustedXForwardedFor": ["X-Forwarded-For", "X-Real-IP"],
          "tcpWindowClamp": 65536
        }
      }
    },
    {
      "tag": "trojan-tcp",
      "listen": "127.0.0.1",
      "port": 10023,
      "protocol": "trojan",
      "settings": {
        "clients": {{TROJAN_CLIENTS}}
      },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {
          "acceptProxyProtocol": true
        },
        "sockopt": {
          "tcpNoDelay": true,
          "tcpWindowClamp": 65536
        }
      }
    },
    {
      "tag": "vless-xhttp",
      "listen": "127.0.0.1",
      "port": 10031,
      "protocol": "vless",
      "settings": {
        "clients": {{VLESS_CLIENTS}},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "/alyan-xhttp"
        },
        "sockopt": {
          "tcpNoDelay": true,
          "trustedXForwardedFor": ["X-Forwarded-For", "X-Real-IP"],
          "tcpWindowClamp": 65536
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      },
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "tcpKeepAliveIdle": 15,
          "tcpWindowClamp": 131072
        }
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api-in"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF_XRAY_TPL

# ─── [3/5] Update Nginx & HAProxy Templates (Per-Session-ID Bridge Upstreams) ─
echo "[3/5] Configuring Nginx (:8880/:8881) -> Per-Session-ID Bridge (:10091..10094)..."
cat <<'EOF_NGINX_TPL' > /opt/alyan/templates/nginx-router.conf.tpl
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
    default                        "";
    "~^\[([0-9a-fA-F:]+)\]:\d+$"  $1;
    "~^([0-9\.]+):\d+$"            $1;
    "~^([0-9a-fA-F:]+):\d+$"       $1;
    "~^([0-9a-fA-F\.:]+)$"         $1;
}

# BunnyCDN Viewer Address (without :port if present)
map $http_b_cdn_viewer_address $alyan_bcdn_viewer_ip {
    default                                  "";
    "~^\s*\[([0-9a-fA-F:]+)\]"            $1;
    "~^\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)" $1;
    "~^\s*([0-9a-fA-F:]+)$"                 $1;
}

# First clean IP from X-Forwarded-For (strips optional :port or brackets)
map $http_x_forwarded_for $alyan_xff_first {
    default                                  "";
    "~^\s*\[([0-9a-fA-F:]+)\]"            $1;
    "~^\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)" $1;
    "~^\s*([0-9a-fA-F:]+)"                  $1;
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

log_format alyan_xray '$msec $alyan_real_ip $status $request_uri';

upstream alyan_vless_ws {
    server 127.0.0.1:10091 max_fails=0;
    server 127.0.0.1:10001 backup;
}

upstream alyan_vmess_ws {
    server 127.0.0.1:10092 max_fails=0;
    server 127.0.0.1:10002 backup;
}

upstream alyan_trojan_ws {
    server 127.0.0.1:10093 max_fails=0;
    server 127.0.0.1:10003 backup;
}

upstream alyan_vless_xhttp {
    server 127.0.0.1:10094 max_fails=0;
    server 127.0.0.1:10031 backup;
}

# ─── HTTP/1.1 WebSocket, XHTTP & ACME Challenge Router (:8880) ───────────────
server {
    listen 127.0.0.1:8880 proxy_protocol backlog=16384 rcvbuf=64k sndbuf=64k;
    server_name {{DOMAIN}} _;

    access_log /var/log/nginx/alyan-xray.log alyan_xray;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    tcp_nodelay on;
    tcp_nopush off;
    postpone_output 0;
    client_max_body_size 0;
    keepalive_timeout 3600s;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/alyan-acme;
        default_type "text/plain";
    }

    location /alyan-vless {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://alyan_vless_ws;
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
        proxy_pass http://alyan_vmess_ws;
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
        proxy_pass http://alyan_trojan_ws;
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
        proxy_pass http://alyan_vless_xhttp;
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
    listen 127.0.0.1:8881 http2 proxy_protocol backlog=16384 rcvbuf=64k sndbuf=64k;
    server_name {{DOMAIN}} _;

    access_log /var/log/nginx/alyan-xray.log alyan_xray;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    tcp_nodelay on;
    tcp_nopush off;
    postpone_output 0;
    client_max_body_size 0;
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
        proxy_pass http://alyan_vless_xhttp;
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
        proxy_pass http://alyan_vless_ws;
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
EOF_NGINX_TPL

cat <<'EOF_HAP_TPL' > /opt/alyan/templates/haproxy.cfg.tpl
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — HAProxy Flame Router (Ports 80 & 443 Wire-Speed Mux)
#  Auto-generated by alyan-ctl · Domain: {{DOMAIN}}
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
    tune.bufsize 32768
    tune.maxrewrite 8192
    tune.rcvbuf.client 65536
    tune.sndbuf.client 65536
    tune.rcvbuf.server 65536
    tune.sndbuf.server 65536
    tune.ssl.cachesize 100000
    tune.ssl.lifetime 600
    tune.ssl.default-dh-param 2048
    ssl-default-bind-options ssl-min-ver TLSv1.2
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-AES256-GCM-SHA384

defaults
    log     global
    mode    tcp
    option  dontlognull
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
    tcp-request content accept

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
    tcp-request content accept

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
    tcp-request content accept

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
EOF_HAP_TPL

python3 - <<'EOF_RENDER_ROUTERS'
import sqlite3
import subprocess
from pathlib import Path

domain = "localhost"
for db_candidate in ("/var/lib/alyan/alyan.db", "/etc/alyan/alyan.db"):
    db_path = Path(db_candidate)
    if db_path.exists():
        try:
            conn = sqlite3.connect(str(db_path))
            row = conn.execute("SELECT value FROM settings WHERE key = 'domain'").fetchone()
            if row and row[0]:
                domain = str(row[0]).strip()
                conn.close()
                break
            conn.close()
        except Exception:
            pass

nr_tpl = Path("/opt/alyan/templates/nginx-router.conf.tpl")
nr_out = Path("/etc/nginx/conf.d/alyan-router.conf")
if nr_tpl.exists():
    nr_out.write_text(nr_tpl.read_text(encoding="utf-8").replace("{{DOMAIN}}", domain), encoding="utf-8")
    if subprocess.run(["nginx", "-t"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        fallback_txt = nr_tpl.read_text(encoding="utf-8").replace(" rcvbuf=64k sndbuf=64k", "").replace("{{DOMAIN}}", domain)
        nr_out.write_text(fallback_txt, encoding="utf-8")

hap_tpl = Path("/opt/alyan/templates/haproxy.cfg.tpl")
hap_out = Path("/etc/haproxy/haproxy.cfg")
if hap_tpl.exists():
    prev_hap = hap_out.read_text(encoding="utf-8") if hap_out.exists() else None
    hap_out.write_text(hap_tpl.read_text(encoding="utf-8").replace("{{DOMAIN}}", domain), encoding="utf-8")
    if subprocess.run(["haproxy", "-c", "-f", str(hap_out)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        if prev_hap is not None:
            hap_out.write_text(prev_hap, encoding="utf-8")
EOF_RENDER_ROUTERS

# ─── [4/5] Update alyan-guard.py (Per-Session-ID Bridge + 2s Disconnect) ─────
echo "[4/5] Updating alyan-guard.py with Per-Session-ID Asyncio Bridge & 2s offline engine..."
mkdir -p /opt/alyan/services/guard
cat <<'EOF_ALYAN_GUARD' > /opt/alyan/services/guard/alyan-guard.py
#!/usr/bin/env python3
"""
Alyan Webpanel — Real-Time 1s Quota, Exact Real-IP & Per-Session-ID Enforcer (alyan-guard)
Continuously monitors SSH/Dropbear/WS-Proxy (/alyan) & Xray (VLESS/VMess/Trojan):
  1. Correlates Dropbear (-E short-iso journal) & OpenSSH PIDs -> Username -> Exact Real Client IP.
  2. Runs an in-process Asyncio Loopback Bridge (127.0.0.1:10091..10094 -> 127.0.0.1:10001..10031)
     that tracks every open VLESS/VMess/Trojan WebSocket & XHTTP connection by its exact real client IP
     (just like alyan-wsd.py does for SSH!).
  3. Keeps connected VLESS users online continuously even when the phone sits idle on the side
     (via 1s WebSocket Ping/Pong tracking), while aborting dead sockets (SO_LINGER RST + close)
     and removing disconnected Session IDs (S1, S2...) within 2 seconds flat.
  4. Counts real-time SSH & Xray per-user bytes into SQLite and enforces GB quotas, expiry dates,
     and Session-ID limits.
"""
import asyncio
import datetime as dt
try:
    import fcntl
except ImportError:
    fcntl = None
import ipaddress
import json
import os
import re
import socket
import sqlite3
import struct
import subprocess
import threading
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

# Persistent tracking caches across ticks
PID_AUTH_CACHE: dict[int, str] = {}
PORT_TO_USER: dict[str, str] = {}
WSD_PORT_LAST_BYTES: dict[str, int] = {}
PID_LAST_IO_BYTES: dict[int, int] = {}
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
XRAY_FROM_RAW_RE = re.compile(
    r"(?:\bfrom\s+)?(?:tcp:|udp:)?(\[[0-9a-fA-F:]+\]:[0-9]+|[0-9a-fA-F\.:]+:[0-9]+|[0-9\.]+)\s+accepted\b",
    re.IGNORECASE,
)
NGINX_XRAY_LOG = Path("/var/log/nginx/alyan-xray.log")


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
    "18.64.", "18.65.", "18.67.", "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.",
    "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.",
    "108.138.", "108.156.", "108.157.", "108.158.", "108.159.", "204.246.", "205.251.",
)
XRAY_LOG_TS_RE = re.compile(r"^(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2})(?:\.\d+)?")

# Per-UUID VLESS/Xray Session-ID table:
#   uuid -> { session_id: { "session_id", "primary_ip", "ips", "net_keys", "super_keys",
#                           "has_v4", "v6_super", "created_at", "last_seen" } }
XRAY_SESSIONS: dict[str, dict[str, dict]] = {}
XRAY_SESSION_SEQ: dict[str, int] = {}
XRAY_ONLINE_ALL_SUPPORTED = True


# ═════════════════════════════════════════════════════════════════════════════
#  🔥 PER-SESSION-ID ASYNCIO XRAY LOOPBACK BRIDGE (10091..10094 -> 10001..10031)
#  Mirrors alyan-wsd.py for VLESS/VMess/Trojan:
#    - Extracts exact client IP (X-Real-IP / X-Forwarded-For) per open TCP socket
#    - Tracks real-time client->server rx_bytes (including 1s WebSocket Pongs!)
#    - Immediately aborts (SO_LINGER RST + close) any WS socket that misses 1.6s
#      of WebSocket Pongs so Xray removes the IP from OnlineMap in 0ms on all kernels!
# ═════════════════════════════════════════════════════════════════════════════
BRIDGE_ENDPOINTS = (
    (10091, 10001, "vless", True),
    (10092, 10002, "vmess", True),
    (10093, 10003, "trojan", True),
    (10094, 10031, "vless", False),
)
BRIDGE_CONNS: dict[int, dict] = {}
BRIDGE_SEQ = 0
BRIDGE_WS_PONG_TIMEOUT = 1.65


def _tune_bridge_writer(writer: asyncio.StreamWriter) -> None:
    sock = writer.get_extra_info("socket")
    if sock is not None:
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 65536)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
        except Exception:
            pass
    tr = writer.transport
    if tr is not None:
        try:
            tr.set_write_buffer_limits(high=65536, low=16384)
        except Exception:
            pass


def _extract_bridge_client_ip(header_bytes: bytes) -> str | None:
    try:
        hdr_block = header_bytes.split(b"\r\n\r\n", 1)[0].decode("latin1", errors="ignore")
        hdrs: dict[str, str] = {}
        for ln in hdr_block.splitlines()[1:]:
            if ":" in ln:
                k, v = ln.split(":", 1)
                hdrs[k.strip().lower()] = v.strip()
        for hk in (
            "x-real-ip",
            "x-forwarded-for",
            "cf-connecting-ip",
            "cloudfront-viewer-address",
            "true-client-ip",
            "b-cdn-viewer-address",
        ):
            if hk in hdrs:
                first_tok = hdrs[hk].split(",")[0].strip()
                ip_c = clean_public_ip(first_tok)
                if ip_c:
                    return ip_c
    except Exception:
        pass
    return None


def _close_bridge_conn(conn_info: dict, abort: bool = False) -> None:
    if conn_info.get("closed"):
        return
    conn_info["closed"] = True
    BRIDGE_CONNS.pop(conn_info["id"], None)
    for w_key in ("x_writer", "c_writer"):
        w: asyncio.StreamWriter | None = conn_info.get(w_key)
        if w is None:
            continue
        if abort:
            sock = w.get_extra_info("socket")
            if sock is not None:
                try:
                    sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                except Exception:
                    pass
            tr = w.transport
            if tr is not None:
                try:
                    tr.abort()
                except Exception:
                    pass
        try:
            w.close()
        except Exception:
            pass


async def _pipe_bridge_c2x(
    c_reader: asyncio.StreamReader,
    x_writer: asyncio.StreamWriter,
    conn_info: dict,
) -> None:
    try:
        while not conn_info.get("closed"):
            chunk = await c_reader.read(65536)
            if not chunk:
                break
            conn_info["last_rx_ts"] = time.monotonic()
            conn_info["rx_bytes"] += len(chunk)
            x_writer.write(chunk)
            await x_writer.drain()
    except Exception:
        pass
    finally:
        _close_bridge_conn(conn_info, abort=False)


async def _pipe_bridge_x2c(
    x_reader: asyncio.StreamReader,
    c_writer: asyncio.StreamWriter,
    conn_info: dict,
) -> None:
    try:
        while not conn_info.get("closed"):
            chunk = await x_reader.read(65536)
            if not chunk:
                break
            conn_info["last_tx_ts"] = time.monotonic()
            conn_info["tx_bytes"] += len(chunk)
            c_writer.write(chunk)
            await c_writer.drain()
    except Exception:
        pass
    finally:
        _close_bridge_conn(conn_info, abort=False)


async def _handle_bridge_client(
    c_reader: asyncio.StreamReader,
    c_writer: asyncio.StreamWriter,
    target_port: int,
    proto: str,
    is_ws: bool,
) -> None:
    global BRIDGE_SEQ
    _tune_bridge_writer(c_writer)
    try:
        initial = await asyncio.wait_for(c_reader.read(65536), timeout=8.0)
        if not initial:
            c_writer.close()
            return
        while b"\r\n\r\n" not in initial and len(initial) < 16384:
            try:
                more = await asyncio.wait_for(c_reader.read(4096), timeout=2.0)
                if not more:
                    break
                initial += more
            except asyncio.TimeoutError:
                break

        real_ip = _extract_bridge_client_ip(initial)
        x_reader, x_writer = await asyncio.wait_for(
            asyncio.open_connection("127.0.0.1", target_port),
            timeout=4.0,
        )
        _tune_bridge_writer(x_writer)
    except Exception:
        try:
            c_writer.close()
        except Exception:
            pass
        return

    now_m = time.monotonic()
    BRIDGE_SEQ += 1
    conn_id = BRIDGE_SEQ
    conn_info = {
        "id": conn_id,
        "proto": proto,
        "is_ws": is_ws,
        "ip": real_ip,
        "opened_at": now_m,
        "last_rx_ts": now_m,
        "last_tx_ts": now_m,
        "rx_bytes": len(initial),
        "tx_bytes": 0,
        "c_writer": c_writer,
        "x_writer": x_writer,
        "closed": False,
    }
    BRIDGE_CONNS[conn_id] = conn_info

    try:
        x_writer.write(initial)
        await x_writer.drain()
        await asyncio.gather(
            _pipe_bridge_c2x(c_reader, x_writer, conn_info),
            _pipe_bridge_x2c(x_reader, c_writer, conn_info),
        )
    except Exception:
        pass
    finally:
        _close_bridge_conn(conn_info, abort=False)


async def _bridge_watchdog_loop() -> None:
    while True:
        await asyncio.sleep(0.25)
        now_m = time.monotonic()
        for conn_info in list(BRIDGE_CONNS.values()):
            if conn_info.get("closed"):
                continue
            if conn_info.get("is_ws"):
                if (
                    (now_m - conn_info["opened_at"]) >= BRIDGE_WS_PONG_TIMEOUT
                    and (now_m - conn_info["last_rx_ts"]) >= BRIDGE_WS_PONG_TIMEOUT
                ):
                    _close_bridge_conn(conn_info, abort=True)


async def _run_bridge_servers() -> None:
    servers = []
    for listen_port, target_port, proto, is_ws in BRIDGE_ENDPOINTS:
        try:
            srv = await asyncio.start_server(
                lambda r, w, tp=target_port, pr=proto, ws=is_ws: _handle_bridge_client(r, w, tp, pr, ws),
                host="127.0.0.1",
                port=listen_port,
                backlog=8192,
                reuse_address=True,
            )
            servers.append(srv)
        except Exception:
            pass
    asyncio.create_task(_bridge_watchdog_loop())
    if servers:
        await asyncio.gather(*(s.serve_forever() for s in servers))
    else:
        while True:
            await asyncio.sleep(3600)


def start_xray_bridge_thread() -> None:
    def _runner():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(_run_bridge_servers())

    t = threading.Thread(target=_runner, name="alyan-xray-bridge", daemon=True)
    t.start()


def get_live_bridge_state() -> tuple[dict[str, set[str]], dict[str, int]]:
    """
    Return (live_ips_by_proto, active_conn_count_by_proto) from the in-process
    Asyncio Loopback Bridge. Only includes connections that have received bytes
    (including 1s WebSocket Pongs!) within BRIDGE_WS_PONG_TIMEOUT.
    """
    ips_by_proto: dict[str, set[str]] = {"vless": set(), "vmess": set(), "trojan": set()}
    cnt_by_proto: dict[str, int] = {"vless": 0, "vmess": 0, "trojan": 0}
    now_m = time.monotonic()
    for c in list(BRIDGE_CONNS.values()):
        if c.get("closed"):
            continue
        if c.get("is_ws") and (now_m - c["last_rx_ts"]) >= BRIDGE_WS_PONG_TIMEOUT:
            continue
        pr = c["proto"]
        cnt_by_proto[pr] = cnt_by_proto.get(pr, 0) + 1
        ip = c.get("ip")
        if ip:
            ips_by_proto.setdefault(pr, set()).add(ip)
    return ips_by_proto, cnt_by_proto


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
    return ip_clean, (ip_clean is None)


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
    dt_s = max(0.3, now - LAST_NET[0])
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


def query_haproxy_sessions() -> tuple[dict[str, str], list[str], list[str], list[str]]:
    loopback_map: dict[str, str] = {}
    ws_ips: list[str] = []
    h2c_ips: list[str] = []
    trojan_ips: list[str] = []
    if not HAPROXY_SOCK.exists():
        return loopback_map, ws_ips, h2c_ips, trojan_ips
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
            if ("be=be_nginx_ws" in block or "srv=nginx_ws" in block) and ip not in ws_ips:
                ws_ips.append(ip)
            if ("be=be_nginx_h2c" in block or "srv=nginx_h2" in block) and ip not in h2c_ips:
                h2c_ips.append(ip)
            if ("be=be_xray_trojan_tcp" in block or "srv=xray_trojan" in block) and ip not in trojan_ips:
                trojan_ips.append(ip)
            for m_lp in re.finditer(r"127\.0\.0\.1:(\d+)", block):
                lp = m_lp.group(1)
                if lp not in ("109", "143", "22", "2095", "4443", "8880", "8881", "10023"):
                    loopback_map[lp] = ip
    except Exception:
        pass
    return loopback_map, ws_ips, h2c_ips, trojan_ips


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
    if CYCLE_TICK <= 2 or (CYCLE_TICK % 2 == 0):
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
        out = subprocess.check_output(["ss", "-tnp"], text=True, stderr=subprocess.DEVNULL, timeout=2.0)
    except Exception:
        out = ""

    need_auth_refresh = False
    raw_ssh_rows = []
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
        raw_ssh_rows.append((peer_ip, peer_port, pids))
        for pid in pids:
            if pid not in PID_AUTH_CACHE:
                need_auth_refresh = True

    if need_auth_refresh and (CYCLE_TICK % 2 != 0):
        refresh_auth_pid_cache(canon_users)

    for peer_ip, peer_port, pids in raw_ssh_rows:
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
                {"pid": target_pid, "ip": real_ip, "dev": str(real_ip)}
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


DIRECT_NON_BRIDGE_PORTS = {
    "vless": (10011,),
    "vmess": (10012,),
    "trojan": (10013, 10023),
}


def scan_direct_grpc_trojan_sockets() -> dict[str, int]:
    """Count ESTAB sockets on gRPC (10011/10012/10013) and Trojan-TCP (10023) ports."""
    counts = {"vless": 0, "vmess": 0, "trojan": 0}
    try:
        out = subprocess.check_output(["ss", "-tn"], text=True, stderr=subprocess.DEVNULL, timeout=1.2)
        for ln in out.splitlines():
            if "ESTAB" not in ln:
                continue
            cols = ln.split()
            if len(cols) < 5:
                continue
            try:
                lport = int(cols[3].rsplit(":", 1)[-1])
            except ValueError:
                continue
            for pr, ports in DIRECT_NON_BRIDGE_PORTS.items():
                if lport in ports:
                    counts[pr] += 1
                    break
    except Exception:
        pass
    return counts


def query_xray_online_map(
    xray_users: list[sqlite3.Row],
    tag_to_uuid: dict[str, str],
) -> tuple[dict[str, list[str]], bool]:
    """
    Query Xray's live ref-counted OnlineMap (statsUserOnline).
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
    bridge_live_ips: set[str] | None = None,
    direct_non_bridge_sockets: int = 0,
) -> tuple[list[str], int]:
    """
    Stateful VLESS Per-Session-ID Engine (Continuous Idle-Online + 2s Instant Disconnect):
      - Assigns discrete Session IDs (S1, S2, S3...) per connected user on `uid`.
      - Binds 1 mobile phone's parallel WebSocket/gRPC/XHTTP streams into 1 Session ID:
          1) Same /16 IPv4 CGNAT subscriber pool or /56 IPv6 prefix -> same Session ID
          2) Dual-Stack (IPv4 + IPv6 simultaneously on 1 VoLTE SIM) -> merged into 1 Session ID
          3) Same /12 carrier superblock within 3.0s initial connection burst -> same Session ID
          4) Seamless CGNAT IP handover when a session's previous IP closes -> reuses Session ID
      - Per-Session-ID Liveliness Verification:
        Each Session ID's IP is verified against `bridge_live_ips` (the in-process Asyncio Bridge
        where every connected phone replies to 1s WebSocket Pings). The moment a Session ID
        disconnects, its socket is aborted/removed from `bridge_live_ips`, and that Session ID
        is immediately removed on the 1.0s tick (2->1 or 1->0 in <=2 seconds flat!), even when
        other Session IDs or other VLESS users stay connected!
    """
    sessions = XRAY_SESSIONS.setdefault(uid, {})

    if active_sockets == 0:
        sessions.clear()
        XRAY_SESSION_SEQ[uid] = 0
        return [], 0

    # Filter Xray OnlineMap IPs against live Pong-verified sockets in our Asyncio Bridge
    # (unless a direct non-bridge gRPC/Trojan-TCP socket is active on 10011..10023).
    if bridge_live_ips is not None and direct_non_bridge_sockets == 0:
        verified_om_ips = [ip for ip in live_om_ips if ip in bridge_live_ips]
        verified_recent_ips = [ip for ip in recent_log_ips if ip in bridge_live_ips]
    else:
        verified_om_ips = list(live_om_ips)
        verified_recent_ips = list(recent_log_ips)

    real_live_set = {ip for ip in verified_om_ips if not is_trusted_cdn(ip)}
    raw_real_cands: list[str] = []
    cdn_cands: list[str] = []

    for ip in verified_om_ips + verified_recent_ips:
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

            # Rule 4: Seamless CGNAT IP handover (old session's IPs closed while new IP opened)
            if matched_sess is None and online_map_ok:
                recent_set = set(verified_recent_ips)
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
    elif not sessions and cdn_cands and (active_traffic or bool(verified_om_ips)):
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
    elif sessions and cdn_cands and "S-CDN" in sessions and (active_traffic or bool(verified_om_ips)):
        sessions["S-CDN"]["ips"].update(cdn_cands)
        sessions["S-CDN"]["last_seen"] = now_ts
        sessions["S-CDN"]["_touched"] = True

    live_all_set = set(verified_om_ips) | set(verified_recent_ips)
    for sid, s in list(sessions.items()):
        touched = s.pop("_touched", False)
        has_open_stream = bool(s["ips"] & live_all_set)
        if touched or has_open_stream or (direct_non_bridge_sockets > 0 and len(sessions) == 1 and active_traffic):
            s["last_seen"] = now_ts
        else:
            # Session ID has 0 alive streams -> remove immediately for 2-second instant offline!
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
      - deltas: uuid -> bytes transferred since last tick
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
                timeout=2.0,
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
    bridge_ips_by_proto, bridge_cnt_by_proto = get_live_bridge_state()
    direct_cnt_by_proto = scan_direct_grpc_trojan_sockets()
    om_by_uid, online_map_ok = query_xray_online_map(xray_users, tag_to_uuid)
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
                if log_ts is None or (now_ts - log_ts) > 2.0 or (now_ts - log_ts) < -5.0:
                    continue
                m_em = XRAY_EMAIL_RE.search(ln)
                if not m_em:
                    continue
                em_tag = m_em.group(1).lower()
                uid = tag_to_uuid.get(em_tag) or tag_to_uuid.get(em_tag.split(".", 1)[0])
                if not uid:
                    continue

                ip_clean, _ = parse_xray_source_ip(ln)
                if ip_clean:
                    lst = recent_log_ips_by_uid.setdefault(uid, [])
                    if ip_clean not in lst:
                        lst.append(ip_clean)
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
        b_ips = bridge_ips_by_proto.get(proto, set())
        b_cnt = bridge_cnt_by_proto.get(proto, 0)
        d_cnt = direct_cnt_by_proto.get(proto, 0)
        active_sockets = b_cnt + d_cnt
        live_om = list(om_by_uid.get(uid, []))
        recent_lg = list(recent_log_ips_by_uid.get(uid, []))

        # Fallback if older Xray stripped trustedXForwardedFor (logged 127.0.0.1) while bridge has live IP
        if not live_om and not recent_lg and active_traffic and len(b_ips) == 1:
            live_om = list(b_ips)

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
            bridge_live_ips=b_ips,
            direct_non_bridge_sockets=d_cnt,
        )
        ips_by_uuid[uid] = u_ips
        dev_count_by_uuid[uid] = u_cnt

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
    hap_loop_ips, ws_ips, h2c_ips, trojan_ips = query_haproxy_sessions()

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
        xray_deltas, xray_ips, xray_fresh_devs = poll_xray_stats_and_ips(xray_rows, ws_ips, h2c_ips, trojan_ips)

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
                if SSH_IP_STRIKES[uname] >= 4:
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
            fresh_sess = xray_fresh_devs.get(uuid, 0)

            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) expired"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) reached {gb_lim} GB quota"
            elif user_lim > 0 and fresh_sess > user_lim:
                XRAY_IP_STRIKES[uuid] = XRAY_IP_STRIKES.get(uuid, 0) + 1
                if XRAY_IP_STRIKES[uuid] >= 6:
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
        subprocess.run(["/usr/local/bin/alyan-ctl", "xray-sync"], stderr=subprocess.DEVNULL)

    # ─── 3. Record Rolling Telemetry & Fast Snapshot ─────────────────────────
    cpu_pct = read_cpu_pct()
    ram_pct = read_ram_pct()
    rx_bps, tx_bps, rx_tot, tx_tot = read_net_rates(iface)

    HIST["cpu"] = (HIST["cpu"] + [cpu_pct])[-20:]
    HIST["ram"] = (HIST["ram"] + [ram_pct])[-20:]
    HIST["rx"] = (HIST["rx"] + [round((rx_bps * 8) / 1048576.0, 2)])[-20:]
    HIST["tx"] = (HIST["tx"] + [round((tx_bps * 8) / 1048576.0, 2)])[-20:]

    if not CACHED_SERVICES or (CYCLE_TICK % 4 == 0):
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
    if fcntl is not None:
        lock_f = open("/run/alyan-guard.lock", "w")
        try:
            fcntl.flock(lock_f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return
    start_xray_bridge_thread()
    while True:
        t0 = time.monotonic()
        try:
            enforce_cycle()
        except Exception:
            pass
        elapsed = time.monotonic() - t0
        time.sleep(max(0.15, 1.0 - elapsed))


if __name__ == "__main__":
    main()
EOF_ALYAN_GUARD
chmod +x /opt/alyan/services/guard/alyan-guard.py

# ─── [5/5] Restart Guard Bridge, Sync Xray & Restart Nginx (SSH Untouched) ──
echo "[5/5] Starting Session-ID Bridge, syncing Xray & restarting Nginx (SSH untouched)..."
while iptables -S OUTPUT 2>/dev/null | grep -q " -o lo .* --sport 100"; do
  rule=$(iptables -S OUTPUT | grep " -o lo .* --sport 100" | head -n1 | sed 's/^-A /-D /')
  iptables $rule 2>/dev/null || break
done
systemctl stop alyan-guard >/dev/null 2>&1 || true
pkill -9 -f "alyan-guard.py" >/dev/null 2>&1 || true
systemctl start alyan-guard
sleep 0.5

if [[ -x /usr/local/bin/alyan-ctl ]]; then
  /usr/local/bin/alyan-ctl xray-sync
fi

systemctl restart nginx >/dev/null 2>&1 || systemctl reload nginx >/dev/null 2>&1 || true
systemctl reload haproxy >/dev/null 2>&1 || true

echo "════════════════════════════════════════════════════════════════════"
echo " ✅ VLESS PER-SESSION-ID 2s DISCONNECT + IDLE-ONLINE UPDATE APPLIED!"
echo "    - Session-ID Bridge (10091..10094 -> 10001..10031) active"
echo "    - Stays ONLINE continuously when VLESS is connected & phone is idle"
echo "    - Goes OFFLINE in 2 seconds per Session ID (2->1 or 1->0) on disconnect"
echo "    - Exact 1:1 data counting (0 KB Xray buffer, 16 KB notsent_lowat)"
echo "    - SSH (Dropbear & alyan-wsd) left 100% untouched"
echo "════════════════════════════════════════════════════════════════════"
exit 0
}

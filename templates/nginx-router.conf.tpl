# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Internal Zero-Buffering Nginx WS / XHTTP / gRPC Router
#  Binds strictly to 127.0.0.1:8880 (HTTP/WS) and 127.0.0.1:8881 (h2c gRPC)
# ═════════════════════════════════════════════════════════════════════════════
map $http_upgrade $alyan_connection_upgrade {
    default upgrade;
    ''      close;
}

# Official Cloudflare IPv4 + IPv6 CIDRs: unwrap client IP headers ONLY from trusted CDN edges
geo $proxy_protocol_addr $alyan_is_trusted_cdn {
    default              0;
    127.0.0.1/32         1;
    173.245.48.0/20      1;
    103.21.244.0/22      1;
    103.22.200.0/22      1;
    103.31.4.0/22        1;
    141.101.64.0/18      1;
    108.162.192.0/18     1;
    190.93.240.0/20      1;
    188.114.96.0/20      1;
    197.234.240.0/22     1;
    198.41.128.0/17      1;
    162.158.0.0/15       1;
    104.16.0.0/13        1;
    104.24.0.0/14        1;
    172.64.0.0/13        1;
    131.0.72.0/22        1;
    2400:cb00::/32       1;
    2606:4700::/32       1;
    2803:f800::/32       1;
    2405:b500::/32       1;
    2405:8100::/32       1;
    2a06:98c0::/29       1;
    2c0f:f248::/32       1;
}

map $http_x_forwarded_for $alyan_xff_first {
    default                      "";
    "~^([0-9a-fA-F\.:]+)"        $1;
}

map $http_true_client_ip $alyan_cdn_fallback {
    ""      $alyan_xff_first;
    default $http_true_client_ip;
}

map $http_cf_connecting_ip $alyan_cdn_client_ip {
    ""      $alyan_cdn_fallback;
    default $http_cf_connecting_ip;
}

map "$alyan_is_trusted_cdn:$alyan_cdn_client_ip" $alyan_real_ip {
    "~^1:(.+)$" $1;
    default     $proxy_protocol_addr;
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

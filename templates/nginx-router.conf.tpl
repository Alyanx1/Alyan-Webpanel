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

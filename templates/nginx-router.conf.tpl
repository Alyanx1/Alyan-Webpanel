# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Edge Router & Real-IP Multiplexer (Nginx)
# ═════════════════════════════════════════════════════════════════════════════
map $http_cf_connecting_ip $client_real_ip {
    "" $proxy_protocol_addr;
    default $http_cf_connecting_ip;
}

server {
    listen 127.0.0.1:8880 proxy_protocol backlog=4096;
    listen 127.0.0.1:8884 backlog=4096;
    server_name {{DOMAIN}} _;

    access_log off;
    reset_timedout_and_closed_connections on;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/alyan-acme;
        default_type "text/plain";
    }

    # ─── Xray VLESS WebSocket ────────────────────────────────────────────────
    location /alyan-vless {
        proxy_pass http://127.0.0.1:20001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $client_real_ip;
        proxy_set_header X-Forwarded-For $client_real_ip;
        proxy_set_header CF-Connecting-IP $client_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
        proxy_ignore_client_abort off;
    }

    # ─── Xray VMess WebSocket ────────────────────────────────────────────────
    location /alyan-vmess {
        proxy_pass http://127.0.0.1:20002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $client_real_ip;
        proxy_set_header X-Forwarded-For $client_real_ip;
        proxy_set_header CF-Connecting-IP $client_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
        proxy_ignore_client_abort off;
    }

    # ─── Xray Trojan WebSocket ───────────────────────────────────────────────
    location /alyan-trojan {
        proxy_pass http://127.0.0.1:20003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $client_real_ip;
        proxy_set_header X-Forwarded-For $client_real_ip;
        proxy_set_header CF-Connecting-IP $client_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
        proxy_ignore_client_abort off;
    }

    # ─── Xray VLESS XHTTP ────────────────────────────────────────────────────
    location /alyan-xhttp {
        proxy_pass http://127.0.0.1:20004;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $client_real_ip;
        proxy_set_header X-Forwarded-For $client_real_ip;
        proxy_set_header CF-Connecting-IP $client_real_ip;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # ─── Xray VLESS gRPC ─────────────────────────────────────────────────────
    location /alyan-vless-grpc {
        grpc_pass grpc://127.0.0.1:20005;
        grpc_set_header X-Real-IP $client_real_ip;
        grpc_set_header X-Forwarded-For $client_real_ip;
        grpc_set_header CF-Connecting-IP $client_real_ip;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
    }

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html><html><head><title>{{DOMAIN}}</title></head><body style="background:#050507;color:#f5f2ee;font-family:sans-serif;display:grid;place-items:center;height:100vh;margin:0"><div><h2 style="letter-spacing:.16em">🔥 ALYAN EDGE NODE ONLINE</h2></div></body></html>';
    }
}

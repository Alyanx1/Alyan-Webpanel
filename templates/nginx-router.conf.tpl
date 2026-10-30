# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Internal Nginx WS / XHTTP / gRPC Router
#  Binds strictly to 127.0.0.1:8880 (HTTP/WS) and 127.0.0.1:8881 (h2c gRPC)
# ═════════════════════════════════════════════════════════════════════════════
map $http_upgrade $alyan_connection_upgrade {
    default upgrade;
    ''      close;
}

# ─── HTTP/1.1 WebSocket, XHTTP & ACME Challenge Router (:8880) ───────────────
server {
    listen 127.0.0.1:8880 proxy_protocol;
    server_name {{DOMAIN}} _;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    client_max_body_size 0;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/alyan-acme;
        default_type "text/plain";
    }

    location /alyan-vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $proxy_protocol_addr;
        proxy_set_header X-Forwarded-For $proxy_protocol_addr;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $proxy_protocol_addr;
        proxy_set_header X-Forwarded-For $proxy_protocol_addr;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-trojan {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $proxy_protocol_addr;
        proxy_set_header X-Forwarded-For $proxy_protocol_addr;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-xhttp {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:10031;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $proxy_protocol_addr;
        proxy_set_header X-Forwarded-For $proxy_protocol_addr;
        proxy_read_timeout 86400s;
    }

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html><html><head><title>{{DOMAIN}}</title></head><body style="background:#050507;color:#f5f2ee;font-family:sans-serif;display:grid;place-items:center;height:100vh;margin:0"><div><h2 style="letter-spacing:.16em">🔥 ALYAN EDGE NODE ONLINE</h2></div></body></html>';
    }
}

# ─── HTTP/2 Cleartext (h2c) gRPC & XHTTP Router (:8881) ──────────────────────
server {
    listen 127.0.0.1:8881 http2 proxy_protocol;
    server_name {{DOMAIN}} _;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    client_max_body_size 0;
    client_body_timeout 4h;
    grpc_read_timeout 4h;
    grpc_send_timeout 4h;

    location /alyan-vless-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $proxy_protocol_addr;
        grpc_pass grpc://127.0.0.1:10011;
    }

    location /alyan-vmess-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $proxy_protocol_addr;
        grpc_pass grpc://127.0.0.1:10012;
    }

    location /alyan-trojan-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $proxy_protocol_addr;
        grpc_pass grpc://127.0.0.1:10013;
    }

    location /alyan-xhttp {
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:10031;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $proxy_protocol_addr;
    }
}

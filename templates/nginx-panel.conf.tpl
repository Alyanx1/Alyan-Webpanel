# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Custom Port HTTPS Reverse Proxy
#  Domain: {{DOMAIN}} · Port: {{PANEL_PORT}} -> FastAPI 127.0.0.1:7700
# ═════════════════════════════════════════════════════════════════════════════
server {
    listen 0.0.0.0:{{PANEL_PORT}} ssl http2;
    server_name {{DOMAIN}} _;

    ssl_certificate     /etc/alyan/ssl/fullchain.pem;
    ssl_certificate_key /etc/alyan/ssl/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:AlyanPanelSSL:10m;
    ssl_session_timeout 1d;

    # Redirect plain HTTP sent to HTTPS port automatically cleanly
    error_page 497 https://$host:{{PANEL_PORT}}$request_uri;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    client_max_body_size 16m;

    location / {
        proxy_pass http://127.0.0.1:7700;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 120s;
    }
}

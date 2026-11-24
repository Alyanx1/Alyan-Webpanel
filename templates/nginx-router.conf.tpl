# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — ACME Challenge & Edge Landing Router (Nginx)
# ═════════════════════════════════════════════════════════════════════════════
server {
    listen 127.0.0.1:8880 proxy_protocol backlog=4096;
    listen 127.0.0.1:8884 backlog=4096;
    server_name {{DOMAIN}} _;

    access_log off;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/alyan-acme;
        default_type "text/plain";
    }

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html><html><head><title>{{DOMAIN}}</title></head><body style="background:#050507;color:#f5f2ee;font-family:sans-serif;display:grid;place-items:center;height:100vh;margin:0"><div><h2 style="letter-spacing:.16em">🔥 ALYAN EDGE NODE ONLINE</h2></div></body></html>';
    }
}

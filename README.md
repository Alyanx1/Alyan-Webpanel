# 🔥 Alyan Webpanel

**Alyan Webpanel** is an advanced multi-protocol Linux VPS Tunneling Stack, Flame CLI Dashboard (`menu`), Telegram User-Management Bot, and Dark/Flame FastAPI Web Dashboard built for **Ubuntu 22.04 LTS / 24.04 LTS+** (`x86_64` & `arm64`).

---

## ⚡ Architecture & Port Routing

- **Public Port `80` & `443` (HAProxy + Nginx Multiplexer):**
  - **SSH WebSocket (`/alyan`):** `80` (HTTP WS) & `443` (TLS 1.3 WS) → `alyan-wsd` (`127.0.0.1:2095` with `PROXY-v2` Real-IP) → Dropbear (`127.0.0.1:109`)
  - **SSH Direct & SSL:** `22` (OpenSSH), `109` & `143` (Dropbear Direct), `443` (SSH over TLS)
  - **Xray VLESS:** WS (`/alyan-vless`), gRPC (`alyan-vless-grpc`), XHTTP (`/alyan-xhttp`)
  - **Xray VMess:** WS (`/alyan-vmess` on `80` & `443`)
  - **Xray Trojan:** Native TCP TLS (`443`), WS (`/alyan-trojan`), gRPC (`alyan-trojan-grpc`)
- **Custom HTTPS Port (`https://<domain>:<port>`):**
  - Nginx TLS 1.3 + HTTP/2 reverse proxy → FastAPI Uvicorn (`127.0.0.1:7700`)
- **Enforcement & Stability Daemons:**
  - `alyan-guard.service`: Real-time GB quota, expiry auto-lock, and multi-IP connection enforcer across SSH, Dropbear, WS `/alyan`, and Xray.
  - `alyan-qos.service`: Low-latency **Ping Stability** (`tc` CAKE anti-bufferbloat + automatic `htb/fq_codel` fallback + per-IP bandwidth caps).
  - `alyan-bot.service`: Full remote Telegram Bot with inline keyboards & step-by-step account wizards.

---

## 🚀 Quick Installation (Ubuntu 22.04 / 24.04+)

### Option A — One-Line GitHub Install (After Pushing Repo)
Update `REPO_RAW_URL` at the top of `install.sh` to your GitHub raw URL, then run as `root`:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/install.sh)
```

### Option B — Direct Local Folder Install (Without GitHub)
Upload this `alyan-webpanel` folder to your Ubuntu VPS (e.g. `/root/alyan-webpanel`) and run:

```bash
cd /root/alyan-webpanel
chmod +x install.sh
sudo bash install.sh
```

*(Because `install.sh` automatically detects local bundle files before falling back to GitHub, local installation works out of the box!)*

---

## 🖥 CLI Dashboard

After installation finishes, open the interactive 12-option Flame CLI dashboard anytime by typing:

```bash
menu
```

---

## 📂 Project Structure

```text
alyan-webpanel/
├── install.sh                       # 5-Step Automated Flame Installer
├── core/
│   └── alyan-ctl                    # Privileged Root SQLite & Stack Control CLI
├── cli/
│   └── menu.sh                      # 12-Option Flame Terminal Dashboard (`menu`)
├── bot/
│   └── alyan-bot.py                 # Full User-Management Telegram Bot
├── panel/
│   ├── app.py                       # FastAPI Backend + RBAC + Session/CSRF Auth
│   └── static/
│       ├── index.html               # Alyan Webpanel Shell
│       ├── app.css                  # Dark + Red/Flame Theme & SVG Animations
│       └── app.js                   # Live Fire Sidebar, Flame Launcher & Nano-Fade UI
├── services/
│   ├── wsd/alyan-wsd.py             # GET /alyan 101 WS-to-SSH Proxy (PROXY-v2)
│   ├── guard/alyan-guard.py         # Quota, Expiry & Multi-IP Enforcer Daemon
│   ├── qos/alyan-qos.sh             # Ping Stability (CAKE / fq_codel QoS)
│   └── systemd/*.service            # Systemd Unit Definitions
└── templates/
    ├── haproxy.cfg.tpl              # 80/443 TCP/TLS/ALPN Multiplexer
    ├── nginx-router.conf.tpl        # Internal WS, XHTTP, gRPC & ACME Router
    ├── nginx-panel.conf.tpl         # Custom-Port HTTPS Webpanel Listener
    └── xray-config.json.tpl         # Xray-Core Multi-Protocol Configuration
```

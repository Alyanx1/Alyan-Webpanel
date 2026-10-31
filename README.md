# 🔥 Alyan Webpanel

**Alyan Webpanel** is an advanced multi-protocol Linux VPS Tunneling Stack, Wire-Speed BBR+FQ Network Optimizer, Flame CLI Dashboard (`menu`), Telegram User-Management Bot, and Dark/Flame FastAPI Web Dashboard built for **Ubuntu 22.04 LTS / 24.04 LTS+** (`x86_64` & `arm64`).

---

## 🔄 Live Update Command (Zero Data Loss)

Whenever a new update is pushed to this repository, run this command as `root` on your VPS to pull the latest Engine, Guard, WSD, Templates & Webpanel UI **without losing your users, domain, or SSL certificates**:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/install.sh | tr -d '\r') --update
```

> **Quick VPS Shortcut:** Once updated, you can also simply run `alyan-update` (or `menu` → Option `1`) anytime directly inside your VPS terminal!

---

## 🛠️ Standalone Xray Live Online & Real-IP Hot-Fix (Reversible)

If you only want to update the **Xray (VLESS / VMess / Trojan) Real-IP and Live Online status engine** without reinstalling or replacing the full stack, run this dedicated patch. It automatically creates a pre-fix safety backup:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/update-xray-fix.sh | tr -d '\r')
```

> **Instant Rollback Command:** If you ever want to revert this patch and restore your panel exactly as it was:
> ```bash
> bash <(curl -sSL https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/update-xray-fix.sh | tr -d '\r') --rollback
> ```
> *(Or on your VPS terminal: `bash /opt/alyan/rollback-xray-fix.sh`)*

---

## 🚀 Fresh Installation (Ubuntu 22.04 / 24.04+)

### Option A — One-Line GitHub Install
Run as `root` on a fresh Ubuntu 22.04 / 24.04+ VPS:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/install.sh | tr -d '\r')
```

### Option B — Direct Local Folder Install
Clone or upload this repository to your Ubuntu VPS and run:

```bash
git clone https://github.com/Alyanx1/Alyan-Webpanel.git /root/alyan-webpanel
cd /root/alyan-webpanel
chmod +x install.sh
sudo bash install.sh
```

---

## 🖥 CLI Shortcuts

| Command | Description |
| :--- | :--- |
| `menu` | Open the interactive 12-option Flame CLI Dashboard |
| `alyan-update` | Pull & apply the latest GitHub hot-update (`--update`) with zero data loss |

---

## ⚡ Architecture & Port Routing

- **Public Port `80` & `443` (HAProxy + Nginx Zero-Buffer Multiplexer):**
  - **SSH WebSocket (`/alyan`):** `80` (HTTP WS) & `443` (TLS 1.3 WS) → `alyan-wsd` (`127.0.0.1:2095` with `PROXY-v2` Real-IP & `TCP_NODELAY`) → Dropbear (`127.0.0.1:109`)
  - **SSH Direct & SSL:** `22` (OpenSSH), `109` & `143` (Dropbear Direct), `443` (SSH over TLS)
  - **Xray VLESS:** WS (`/alyan-vless`), gRPC (`alyan-vless-grpc`), XHTTP (`/alyan-xhttp`) with Cloudflare & `X-Forwarded-For` Real-IP unwrapping
  - **Xray VMess:** WS (`/alyan-vmess` on `80` & `443`)
  - **Xray Trojan:** Native TCP TLS (`443`), WS (`/alyan-trojan`), gRPC (`alyan-trojan-grpc`)
- **Custom HTTPS Port (`https://<domain>:<port>`):**
  - Nginx TLS 1.3 + HTTP/2 reverse proxy → FastAPI Uvicorn (`127.0.0.1:7700`) with real-time 2s live telemetry
- **Enforcement & Wire-Speed Engine:**
  - **Kernel BBR + `fq` Packet Pacing (`/etc/sysctl.d/99-alyan-turbo.conf`):** Unthrottled wire-speed throughput, `tcp_slow_start_after_idle=0`, `tcp_notsent_lowat=16384`, and 32 MB socket buffers for stable ping and zero mid-stream speed drops.
  - **`alyan-guard.service`:** Real-time GB quota tracking, expiry auto-lock, accurate subscriber Real-IP detection (`/64` IPv6 prefix grouping), and strict `ip_limit` auto-disable across SSH, Dropbear, WS `/alyan`, and Xray.
  - **`alyan-bot.service`:** Full remote Telegram Bot with inline keyboards & step-by-step account wizards.

---

## 📂 Project Structure

```text
alyan-webpanel/
├── install.sh                       # 5-Step Automated Flame Installer & `--update` Updater
├── core/
│   └── alyan-ctl                    # Privileged Root SQLite, Stack & Wire-Speed Control CLI
├── cli/
│   └── menu.sh                      # 12-Option Flame Terminal Dashboard (`menu`)
├── bot/
│   └── alyan-bot.py                 # Full User-Management Telegram Bot
├── panel/
│   ├── app.py                       # FastAPI Backend + RBAC + Session/CSRF Auth
│   └── static/
│       ├── index.html               # Alyan Webpanel Shell
│       ├── app.css                  # Dark + Red/Flame Theme & SVG Animations
│       └── app.js                   # Live 2s Telemetry, Real-IP Modal & Nano-Fade UI
├── services/
│   ├── wsd/alyan-wsd.py             # GET /alyan 101 WS-to-SSH Proxy (PROXY-v2 + TCP_NODELAY)
│   ├── guard/alyan-guard.py         # Quota, Expiry & Strict Multi-IP Auto-Disable Daemon
│   └── systemd/*.service            # Systemd Unit Definitions
└── templates/
    ├── haproxy.cfg.tpl              # 80/443 High-Concurrency TCP/TLS/ALPN Multiplexer
    ├── nginx-router.conf.tpl        # Zero-Buffer WS, XHTTP, gRPC & Real-IP Router
    ├── nginx-panel.conf.tpl         # Custom-Port HTTPS Webpanel Listener
    └── xray-config.json.tpl         # Xray-Core Multi-Protocol Configuration
```

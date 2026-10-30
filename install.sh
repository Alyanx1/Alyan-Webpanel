#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Automated Flame Tunneling Stack & Web Dashboard Installer
#  Target OS : Ubuntu 22.04 LTS / 24.04 LTS & newer (x86_64 / arm64)
#  Stack     : HAProxy (80/443) + Nginx + Dropbear (109/143) + WS (/alyan) +
#              Xray (VLESS/VMess/Trojan) + CAKE QoS + FastAPI Webpanel + Bot
#  One-Liner : bash <(curl -sSL https://raw.githubusercontent.com/YOUR_USER/alyan-webpanel/main/install.sh)
# ═════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
ALYAN_VERSION="1.0.0"
REPO_SLUG="${ALYAN_REPO_SLUG:-Alyanx1/Alyan-Webpanel}"
REPO_RAW_URL="${ALYAN_REPO_RAW:-https://raw.githubusercontent.com/${REPO_SLUG}/main}"
INSTALL_DIR="/opt/alyan"
ETC_DIR="/etc/alyan"
VAR_DIR="/var/lib/alyan"
LOG_DIR="/var/log/alyan"
LOG_FILE="${LOG_DIR}/install.log"

# ─── Flame ANSI Truecolor Palette ────────────────────────────────────────────
C_RST='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[38;2;255;36;36m'
C_ORG='\033[38;2;255;106;0m'
C_AMB='\033[38;2;255;180;0m'
C_GLD='\033[38;2;255;218;110m'
C_WHT='\033[38;2;245;242;238m'
C_GRY='\033[38;2;130;125;140m'
C_OK='\033[38;2;255;190;30m'
C_ERR='\033[38;2;255;70;70m'

mkdir -p "$LOG_DIR" "$ETC_DIR/ssl" "$VAR_DIR"
: > "$LOG_FILE"

# ─── Visual Helpers ──────────────────────────────────────────────────────────
flame_banner() {
  clear || true
  echo -e "${C_RED}${C_BOLD}"
  cat <<'EOF'
     █████╗ ██╗  ██╗   ██╗ █████╗ ███╗   ██╗
    ██╔══██╗██║  ╚██╗ ██╔╝██╔══██╗████╗  ██║
EOF
  echo -e "${C_ORG}${C_BOLD}"
  cat <<'EOF'
    ███████║██║   ╚████╔╝ ███████║██╔██╗ ██║
    ██╔══██║██║    ╚██╔╝  ██╔══██║██║╚██╗██║
EOF
  echo -e "${C_AMB}${C_BOLD}"
  cat <<'EOF'
    ██║  ██║███████╗██║   ██║  ██║██║ ╚████║
    ╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝
EOF
  echo -e "${C_RST}${C_GLD}   🔥  A L Y A N   W E B P A N E L  ${C_GRY}v${ALYAN_VERSION} · INFERNO COMMAND DECK${C_RST}"
  echo -e "${C_GRY}   ─────────────────────────────────────────────────────────────────${C_RST}"
  echo -e "${C_WHT}   SSH · Dropbear · WS (/alyan) · SSL · HAProxy · Xray · CAKE QoS${C_RST}"
  echo -e "${C_GRY}   ─────────────────────────────────────────────────────────────────${C_RST}\n"
}

section_hdr() {
  local step="$1" title="$2"
  echo -e "\n${C_RED}┏━━${C_ORG}━[${C_AMB}${C_BOLD} STEP ${step} ${C_RST}${C_ORG}]━━${C_WHT}${C_BOLD} ${title}${C_RST}"
}

run_task() {
  local pct="$1" label="$2"
  shift 2
  local frames=('🔥' '⚡' '🌋' '✨')
  local width=26
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar_f bar_e
  bar_f=$(printf '%*s' "$filled" '' | tr ' ' '█')
  bar_e=$(printf '%*s' "$empty" '' | tr ' ' '░')

  ("$@") >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r${C_ORG}┃ ${frames[$((i % 4))]} ${C_RED}%s${C_GRY}%s ${C_AMB}%3d%% ${C_WHT}%-44s${C_RST}" \
      "$bar_f" "$bar_e" "$pct" "$label"
    i=$((i + 1))
    sleep 0.14
  done
  if wait "$pid"; then
    printf "\r${C_ORG}┃ ${C_OK}✔ ${C_RED}%s${C_GRY}%s ${C_AMB}%3d%% ${C_WHT}%-46s${C_RST}\n" \
      "$bar_f" "$bar_e" "$pct" "$label"
  else
    printf "\r${C_ORG}┃ ${C_ERR}✖ ${C_RED}%s${C_GRY}%s ${C_ERR}ERR  ${C_WHT}%-46s${C_RST}\n" \
      "$bar_f" "$bar_e" "$label"
    echo -e "${C_ERR}Task failed! Last 20 lines of ${LOG_FILE}:${C_RST}"
    tail -n 20 "$LOG_FILE" || true
    exit 1
  fi
}

# ─── Pre-Flight Root & OS Check ──────────────────────────────────────────────
preflight_check() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${C_ERR}✖ Please run as root (sudo -i or sudo bash install.sh).${C_RST}"
    exit 1
  fi
  if [[ ! -f /etc/os-release ]]; then
    echo -e "${C_ERR}✖ Unsupported Linux distribution.${C_RST}"
    exit 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"ubuntu"* && "${ID:-}" != "debian" ]]; then
    echo -e "${C_ERR}✖ Alyan Webpanel requires Ubuntu 22.04 / 24.04+ (detected: ${PRETTY_NAME:-unknown}).${C_RST}"
    exit 1
  fi
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) XRAY_ARCH="64" ;;
    aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
    *) echo -e "${C_ERR}✖ Unsupported CPU architecture: ${ARCH}${C_RST}"; exit 1 ;;
  esac
}

# ─── Helper: Fetch File from Local Bundle or Remote GitHub Repo ──────────────
BUNDLE_DIR=""
fetch_asset() {
  local rel="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  local script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -n "$script_dir" && -f "${script_dir}/${rel}" ]]; then
    cp -f "${script_dir}/${rel}" "$dst"
  elif [[ -n "$BUNDLE_DIR" && -f "${BUNDLE_DIR}/${rel}" ]]; then
    cp -f "${BUNDLE_DIR}/${rel}" "$dst"
  elif [[ -n "${ALYAN_GH_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer ${ALYAN_GH_TOKEN}" "${REPO_RAW_URL}/${rel}" -o "$dst" || \
    curl -fsSL -H "Authorization: token ${ALYAN_GH_TOKEN}" "${REPO_RAW_URL}/${rel}" -o "$dst" || \
    curl -fsSL -u "x-access-token:${ALYAN_GH_TOKEN}" "${REPO_RAW_URL}/${rel}" -o "$dst"
  else
    curl -fsSL "${REPO_RAW_URL}/${rel}" -o "$dst"
  fi
  sed -i 's/\r$//' "$dst" 2>/dev/null || true
}

# ═════════════════════════════════════════════════════════════════════════════
#  MAIN INSTALLATION FLOW
# ═════════════════════════════════════════════════════════════════════════════
preflight_check
flame_banner

PUB_IP=$(curl -4fsSL --max-time 6 https://api.ipify.org || curl -4fsSL --max-time 6 https://ifconfig.me || hostname -I | awk '{print $1}')
DEF_IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')
DEF_IFACE="${DEF_IFACE:-eth0}"

echo -e "  ${C_GRY}Node IP   :${C_RST} ${C_WHT}${C_BOLD}${PUB_IP}${C_RST}   ${C_GRY}OS :${C_RST} ${C_WHT}${PRETTY_NAME}${C_RST}   ${C_GRY}NIC :${C_RST} ${C_AMB}${DEF_IFACE}${C_RST}"

# ─── STEP 1: Basic System Packages & Dependencies ────────────────────────────
section_hdr "1/5" "Igniting Base System & Core Dependencies"

run_task 8  "Refreshing APT package repositories" apt-get update -y
run_task 20 "Installing networking, TLS & build utilities" \
  apt-get install -y --no-install-recommends \
  git curl wget jq socat cron ca-certificates gnupg lsb-release unzip tar \
  openssl sqlite3 lsof iproute2 procps bc vnstat dnsutils
run_task 32 "Installing Python 3 runtime & virtual environment" \
  apt-get install -y --no-install-recommends python3 python3-venv python3-pip

# ─── STEP 2: INTERACTIVE PAUSE (Domain & Custom Web Panel Port) ──────────────
section_hdr "2/5" "Interactive Configuration — Domain & Web Panel Port"
echo -e "${C_ORG}┃${C_RST} ${C_GRY}Point your domain's DNS A-record to ${C_AMB}${PUB_IP}${C_GRY} (DNS-only / grey cloud recommended).${C_RST}"

CUSTOM_DOMAIN="${ALYAN_DOMAIN:-}"
while [[ -z "$CUSTOM_DOMAIN" ]]; do
  printf "${C_ORG}┃ ${C_AMB}🔥 Enter your Custom Domain: ${C_WHT}"
  read -r CUSTOM_DOMAIN </dev/tty
  printf "${C_RST}"
  CUSTOM_DOMAIN=$(echo "$CUSTOM_DOMAIN" | tr '[:upper:]' '[:lower:]' | xargs)
  if [[ ! "$CUSTOM_DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$ ]]; then
    echo -e "${C_ORG}┃ ${C_ERR}✖ Invalid domain format. Example: panel.yourdomain.com${C_RST}"
    CUSTOM_DOMAIN=""
    continue
  fi
  RESOLVED_IP=$(dig +short A "$CUSTOM_DOMAIN" @1.1.1.1 | head -n1 || true)
  if [[ -n "$RESOLVED_IP" && "$RESOLVED_IP" != "$PUB_IP" ]]; then
    echo -e "${C_ORG}┃ ${C_AMB}⚠ DNS resolves to ${RESOLVED_IP} (VPS IP is ${PUB_IP}). Self-signed fallback will protect startup if Let's Encrypt waits.${C_RST}"
  elif [[ "$RESOLVED_IP" == "$PUB_IP" ]]; then
    echo -e "${C_ORG}┃ ${C_OK}✔ DNS verified: ${CUSTOM_DOMAIN} → ${PUB_IP}${C_RST}"
  fi
done

PANEL_PORT="${ALYAN_PORT:-}"
RESERVED_PORTS=" 22 53 80 109 143 443 2095 4443 7700 8880 8881 10001 10002 10003 10011 10012 10013 10021 10022 10023 10031 10085 "
while [[ -z "$PANEL_PORT" ]]; do
  printf "${C_ORG}┃ ${C_AMB}🔥 Enter Custom Port for Web Panel [default: 8443]: ${C_WHT}"
  read -r PANEL_PORT </dev/tty
  printf "${C_RST}"
  PANEL_PORT="${PANEL_PORT:-8443}"
  if [[ ! "$PANEL_PORT" =~ ^[0-9]+$ ]] || (( PANEL_PORT < 1024 || PANEL_PORT > 65535 )); then
    echo -e "${C_ORG}┃ ${C_ERR}✖ Port must be a number between 1024 and 65535.${C_RST}"
    PANEL_PORT=""
    continue
  fi
  if [[ "$RESERVED_PORTS" == *" ${PANEL_PORT} "* ]]; then
    echo -e "${C_ORG}┃ ${C_ERR}✖ Port ${PANEL_PORT} is reserved by internal tunneling components. Pick another (e.g. 8443, 9090, 2053).${C_RST}"
    PANEL_PORT=""
    continue
  fi
done
echo -e "${C_ORG}┗━━${C_OK}✔ Locked:${C_RST} Domain=${C_GLD}${CUSTOM_DOMAIN}${C_RST} · Webpanel Port=${C_GLD}${PANEL_PORT}${C_RST}"

# ─── STEP 3: Core Tunneling Stack, SSL, Engine & Web Panel ───────────────────
section_hdr "3/5" "Forging Tunneling Stack (Nginx · HAProxy · Dropbear · Xray · SSL · Webpanel)"

install_daemons_pkg() {
  apt-get install -y --no-install-recommends dropbear nginx haproxy
  systemctl stop nginx haproxy dropbear 2>/dev/null || true
}
run_task 44 "Installing Dropbear SSH, Nginx & HAProxy packages" install_daemons_pkg

deploy_project_files() {
  mkdir -p "$INSTALL_DIR"/{core,cli,bot,panel/static,services/{wsd,guard,qos,systemd},templates}

  # If running from curl pipe (not a local git folder), clone bundle once cleanly
  local local_check=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    local_check="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -z "$local_check" || ! -f "${local_check}/core/alyan-ctl" ]]; then
    BUNDLE_DIR="/tmp/alyan-bundle-src"
    rm -rf "$BUNDLE_DIR"
    if [[ -n "${ALYAN_GH_TOKEN:-}" ]]; then
      git clone --depth 1 "https://x-access-token:${ALYAN_GH_TOKEN}@github.com/${REPO_SLUG}.git" "$BUNDLE_DIR" || \
      git clone --depth 1 "https://github.com/${REPO_SLUG}.git" "$BUNDLE_DIR" || true
    else
      git clone --depth 1 "https://github.com/${REPO_SLUG}.git" "$BUNDLE_DIR" || true
    fi
  fi

  fetch_asset "install.sh"                       "${INSTALL_DIR}/install.sh" || true
  fetch_asset "core/alyan-ctl"                   "${INSTALL_DIR}/core/alyan-ctl"
  fetch_asset "services/wsd/alyan-wsd.py"        "${INSTALL_DIR}/services/wsd/alyan-wsd.py"
  fetch_asset "services/guard/alyan-guard.py"    "${INSTALL_DIR}/services/guard/alyan-guard.py"
  fetch_asset "services/qos/alyan-qos.sh"        "${INSTALL_DIR}/services/qos/alyan-qos.sh"
  fetch_asset "templates/haproxy.cfg.tpl"        "${INSTALL_DIR}/templates/haproxy.cfg.tpl"
  fetch_asset "templates/nginx-router.conf.tpl"  "${INSTALL_DIR}/templates/nginx-router.conf.tpl"
  fetch_asset "templates/nginx-panel.conf.tpl"   "${INSTALL_DIR}/templates/nginx-panel.conf.tpl"
  fetch_asset "templates/xray-config.json.tpl"   "${INSTALL_DIR}/templates/xray-config.json.tpl"
  fetch_asset "cli/menu.sh"                      "${INSTALL_DIR}/cli/menu.sh"
  fetch_asset "panel/app.py"                     "${INSTALL_DIR}/panel/app.py"
  fetch_asset "panel/static/index.html"          "${INSTALL_DIR}/panel/static/index.html"
  fetch_asset "panel/static/app.css"             "${INSTALL_DIR}/panel/static/app.css"
  fetch_asset "panel/static/app.js"              "${INSTALL_DIR}/panel/static/app.js"
  fetch_asset "bot/alyan-bot.py"                 "${INSTALL_DIR}/bot/alyan-bot.py"
  for unit in alyan-wsd alyan-guard alyan-qos alyan-panel alyan-bot; do
    fetch_asset "services/systemd/${unit}.service" "/etc/systemd/system/${unit}.service"
  done
  rm -rf "/tmp/alyan-bundle-src"
  chmod +x "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}/core/alyan-ctl" "${INSTALL_DIR}/cli/menu.sh" "${INSTALL_DIR}/services/qos/alyan-qos.sh" 2>/dev/null || true
  ln -sf "${INSTALL_DIR}/core/alyan-ctl" /usr/local/bin/alyan-ctl
  ln -sf "${INSTALL_DIR}/cli/menu.sh" /usr/local/bin/menu
}
run_task 54 "Deploying Alyan Engine, Templates & Inferno UI" deploy_project_files

install_xray_core() {
  mkdir -p /usr/local/bin /usr/local/share/xray /usr/local/etc/xray /var/log/xray
  local tmp_zip="/tmp/xray.zip"
  curl -fsSL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o "$tmp_zip"
  unzip -qo "$tmp_zip" xray geoip.dat geosite.dat -d /usr/local/bin/
  cp -f /usr/local/bin/geoip.dat /usr/local/bin/geosite.dat /usr/local/share/xray/ 2>/dev/null || true
  chmod +x /usr/local/bin/xray
  rm -f "$tmp_zip"
  cat >/etc/systemd/system/xray.service <<'UNIT'
[Unit]
Description=Alyan Xray-Core Multi-Protocol Engine
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT
}
run_task 66 "Installing Xray-Core (VLESS · VMess · Trojan · XHTTP)" install_xray_core

setup_panel_venv() {
  id -u alyan &>/dev/null || useradd -r -s /usr/sbin/nologin -d /opt/alyan alyan
  chown -R alyan:alyan "${INSTALL_DIR}/panel" "${INSTALL_DIR}/bot"
  cat >/etc/sudoers.d/alyan-panel <<'SUDO'
alyan ALL=(root) NOPASSWD: /usr/local/bin/alyan-ctl, /usr/local/bin/alyan-ctl *
SUDO
  chmod 0440 /etc/sudoers.d/alyan-panel
  python3 -m venv "${INSTALL_DIR}/venv"
  "${INSTALL_DIR}/venv/bin/pip" install --upgrade --quiet pip
  "${INSTALL_DIR}/venv/bin/pip" install --quiet fastapi "uvicorn[standard]" bcrypt python-multipart httpx
}
run_task 78 "Building isolated Python FastAPI environment" setup_panel_venv

issue_ssl_and_render() {
  grep -qxF "/bin/false" /etc/shells || echo "/bin/false" >> /etc/shells
  grep -qxF "/usr/sbin/nologin" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

  # Generate initial self-signed cert first so configs are always valid immediately
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 365 -subj "/CN=${CUSTOM_DOMAIN}" \
    -keyout "${ETC_DIR}/ssl/privkey.pem" \
    -out "${ETC_DIR}/ssl/fullchain.pem"
  cat "${ETC_DIR}/ssl/fullchain.pem" "${ETC_DIR}/ssl/privkey.pem" > "${ETC_DIR}/ssl/haproxy.pem"
  chmod 600 "${ETC_DIR}/ssl/"*.pem

  # Initialize SQLite DB, generate admin password, render Dropbear/Nginx/HAProxy/Xray configs
  /usr/local/bin/alyan-ctl init --domain "$CUSTOM_DOMAIN" --panel-port "$PANEL_PORT" --iface "$DEF_IFACE" --ip "$PUB_IP"

  # Attempt live Let's Encrypt certificate via acme.sh standalone on port 80 before HAProxy binds
  if [[ ! -x "$HOME/.acme.sh/acme.sh" ]]; then
    curl -fsSL https://get.acme.sh | sh -s email="ssl@${CUSTOM_DOMAIN}" || true
  fi
  /usr/local/bin/alyan-ctl ssl-issue --standalone || true
}
run_task 90 "Issuing Let's Encrypt SSL & compiling Flame Router" issue_ssl_and_render

start_all_services() {
  # Enable TCP BBR congestion control
  cat >/etc/sysctl.d/99-alyan-bbr.conf <<'SYS'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYS
  sysctl --system >/dev/null 2>&1 || true

  systemctl daemon-reload
  for svc in dropbear alyan-wsd xray nginx haproxy alyan-guard alyan-qos alyan-panel; do
    systemctl enable "$svc" >/dev/null 2>&1 || true
    systemctl restart "$svc"
  done
}
run_task 98 "Starting HAProxy, Nginx, Dropbear, WS-Proxy, Xray & Panel" start_all_services

# ─── STEP 4: Final Health & Verification Check ───────────────────────────────
section_hdr "4/5" "Final Stack Health & Socket Verification"

SERVICES_CHECK=(haproxy nginx dropbear alyan-wsd xray alyan-guard alyan-panel)
ALL_HEALTHY=1
for svc in "${SERVICES_CHECK[@]}"; do
  if systemctl is-active --quiet "$svc"; then
    printf "  ${C_OK}●${C_RST} %-16s ${C_OK}running${C_RST}\n" "$svc"
  else
    printf "  ${C_ERR}●${C_RST} %-16s ${C_ERR}failed${C_RST}\n" "$svc"
    ALL_HEALTHY=0
  fi
done

for prt in 80 443 109 143 "$PANEL_PORT"; do
  if ss -tln | awk '{print $4}' | grep -qE "(:|\\])${prt}$"; then
    printf "  ${C_AMB}⚡${C_RST} Port %-11s ${C_GLD}listening${C_RST}\n" "$prt"
  else
    printf "  ${C_ERR}✖${C_RST} Port %-11s ${C_ERR}not bound${C_RST}\n" "$prt"
    ALL_HEALTHY=0
  fi
done

# ─── STEP 5: Success Summary & CLI Instruction ───────────────────────────────
ADMIN_PASS=$(/usr/local/bin/alyan-ctl get-initial-pass 2>/dev/null || echo "See /etc/alyan/credentials.txt")

echo -e "\n${C_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RST}"
echo -e "${C_RED}┃${C_RST}  🔥 ${C_AMB}${C_BOLD}ALYAN WEBPANEL INSTALLATION COMPLETE!${C_RST}                           ${C_RED}┃${C_RST}"
echo -e "${C_RED}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_RST}"
printf "${C_RED}┃${C_RST}  ${C_GRY}Web Panel URL  :${C_RST} ${C_GLD}${C_BOLD}https://%s:%s${C_RST}\n" "$CUSTOM_DOMAIN" "$PANEL_PORT"
printf "${C_RED}┃${C_RST}  ${C_GRY}Admin Username :${C_RST} ${C_WHT}${C_BOLD}admin${C_RST}\n"
printf "${C_RED}┃${C_RST}  ${C_GRY}Admin Password :${C_RST} ${C_ORG}${C_BOLD}%s${C_RST}\n" "$ADMIN_PASS"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}SSH Direct     :${C_RST} ${C_WHT}22, 109, 143${C_RST}   ${C_GRY}│  SSH WS / SSL :${C_RST} ${C_WHT}80, 443 (/alyan)${C_RST}"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}WS Payload     :${C_RST} ${C_AMB}GET /alyan HTTP/1.1[crlf]Host: ${CUSTOM_DOMAIN}[crlf]...${C_RST}"
echo -e "${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}"
if (( ALL_HEALTHY == 0 )); then
  echo -e "${C_AMB}⚠ Note: One or more checks reported a warning. Run 'menu' → Option 6 to inspect/fix.${C_RST}"
fi
echo -e "\n👉 ${C_GLD}${C_BOLD}Type 'menu' to access the CLI dashboard.${C_RST}\n"

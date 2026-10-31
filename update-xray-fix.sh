#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Standalone Xray Live Online & Connected IPs Hot-Fix
#  Purpose : Resolves Xray (VLESS / VMess / Trojan) real client IP detection,
#            accurate online status, and live users counter across WebSocket,
#            gRPC and XHTTP without data loss.
#
#  Apply   : bash <(curl -sSL https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/update-xray-fix.sh | tr -d '\r')
#  Rollback: bash <(curl -sSL https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/update-xray-fix.sh | tr -d '\r') --rollback
# ═════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

C_RST='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[38;2;255;36;36m'
C_ORG='\033[38;2;255;106;0m'
C_AMB='\033[38;2;255;180;0m'
C_GLD='\033[38;2;255;218;110m'
C_WHT='\033[38;2;245;242;238m'
C_GRY='\033[38;2;130;125;140m'
C_OK='\033[38;2;255;190;30m'
C_ERR='\033[38;2;255;70;70m'

INSTALL_DIR="/opt/alyan"
BACKUP_DIR="/var/backups/alyan-xray-fix-backup"
REPO_RAW_URL="https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main"

banner() {
  echo -e "\n${C_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RST}"
  echo -e "${C_RED}┃${C_RST}  🔥 ${C_AMB}${C_BOLD}ALYAN WEBPANEL — XRAY LIVE ONLINE & REAL-IP HOT-FIX${C_RST}            ${C_RED}┃${C_RST}"
  echo -e "${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}\n"
}

# ─── ROLLBACK MODE ────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--rollback" || "${1:-}" == "revert" || "${1:-}" == "rollback" ]]; then
  banner
  echo -e "  ${C_AMB}⚡ Starting Rollback to pre-fix state...${C_RST}\n"
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo -e "  ${C_ERR}✖ Backup directory ${BACKUP_DIR} not found. Cannot rollback.${C_RST}\n"
    exit 1
  fi

  if [[ -f "${BACKUP_DIR}/alyan-guard.py" ]]; then
    cp -f "${BACKUP_DIR}/alyan-guard.py" "${INSTALL_DIR}/services/guard/alyan-guard.py"
    echo -e "  ${C_OK}✔ Restored:${C_RST} ${INSTALL_DIR}/services/guard/alyan-guard.py"
  fi
  if [[ -f "${BACKUP_DIR}/nginx-router.conf.tpl" ]]; then
    cp -f "${BACKUP_DIR}/nginx-router.conf.tpl" "${INSTALL_DIR}/templates/nginx-router.conf.tpl"
    echo -e "  ${C_OK}✔ Restored:${C_RST} ${INSTALL_DIR}/templates/nginx-router.conf.tpl"
  fi
  if [[ -f "${BACKUP_DIR}/alyan-router.conf" ]]; then
    cp -f "${BACKUP_DIR}/alyan-router.conf" "/etc/nginx/conf.d/alyan-router.conf"
    echo -e "  ${C_OK}✔ Restored:${C_RST} /etc/nginx/conf.d/alyan-router.conf"
  fi

  systemctl daemon-reload 2>/dev/null || true
  systemctl restart nginx 2>/dev/null || true
  systemctl restart alyan-guard 2>/dev/null || true
  systemctl restart alyan-panel 2>/dev/null || true
  rm -f "${INSTALL_DIR}/rollback-xray-fix.sh"

  echo -e "\n  ${C_OK}✔ Rollback complete! Your panel is now exactly as it was before this update.${C_RST}\n"
  exit 0
fi

# ─── APPLY FIX MODE ───────────────────────────────────────────────────────────
banner
echo -e "  ${C_WHT}This hot-fix enables real-time Xray (VLESS, VMess, Trojan) subscriber Real-IP${C_RST}"
echo -e "  ${C_WHT}correlation, green online badges, and live IP display with zero data loss.${C_RST}\n"

# Step 1: Create Backup
echo -e "  ${C_AMB}[1/4] Creating safety backup in ${BACKUP_DIR}...${C_RST}"
mkdir -p "$BACKUP_DIR"
if [[ -f "${INSTALL_DIR}/services/guard/alyan-guard.py" ]]; then
  cp -f "${INSTALL_DIR}/services/guard/alyan-guard.py" "${BACKUP_DIR}/alyan-guard.py"
fi
if [[ -f "${INSTALL_DIR}/templates/nginx-router.conf.tpl" ]]; then
  cp -f "${INSTALL_DIR}/templates/nginx-router.conf.tpl" "${BACKUP_DIR}/nginx-router.conf.tpl"
fi
if [[ -f "/etc/nginx/conf.d/alyan-router.conf" ]]; then
  cp -f "/etc/nginx/conf.d/alyan-router.conf" "${BACKUP_DIR}/alyan-router.conf"
fi
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${BACKUP_DIR}/backup_timestamp.txt"
echo -e "  ${C_OK}✔ Backup saved.${C_RST}"

# Step 2: Fetch and Install Updated Files
echo -e "  ${C_AMB}[2/4] Deploying updated Guard & Nginx Real-IP correlation engine...${C_RST}"
mkdir -p "${INSTALL_DIR}/services/guard" "${INSTALL_DIR}/templates" /var/log/nginx

# Fetch latest alyan-guard.py and nginx-router.conf.tpl
curl -fsSL "${REPO_RAW_URL}/services/guard/alyan-guard.py?ts=$(date +%s)" -o "${INSTALL_DIR}/services/guard/alyan-guard.py"
sed -i 's/\r$//' "${INSTALL_DIR}/services/guard/alyan-guard.py"
chmod +x "${INSTALL_DIR}/services/guard/alyan-guard.py"

curl -fsSL "${REPO_RAW_URL}/templates/nginx-router.conf.tpl?ts=$(date +%s)" -o "${INSTALL_DIR}/templates/nginx-router.conf.tpl"
sed -i 's/\r$//' "${INSTALL_DIR}/templates/nginx-router.conf.tpl"

# Ensure nginx xray log exists with write permissions
touch /var/log/nginx/alyan-xray.log
chmod 0666 /var/log/nginx/alyan-xray.log 2>/dev/null || true

# Re-render Nginx router config with the new template
if [[ -x "/usr/local/bin/alyan-ctl" ]]; then
  /usr/local/bin/alyan-ctl --actor cli settings --json '{"maint":"fix_ws_ssl_stack"}' >/dev/null 2>&1 || true
fi
echo -e "  ${C_OK}✔ Engine files updated.${C_RST}"

# Step 3: Verify and Restart Services
echo -e "  ${C_AMB}[3/4] Testing configuration and restarting services...${C_RST}"
if command -v python3 &>/dev/null; then
  python3 -m py_compile "${INSTALL_DIR}/services/guard/alyan-guard.py"
fi
nginx -t >/dev/null 2>&1 || true

systemctl daemon-reload 2>/dev/null || true
systemctl restart nginx 2>/dev/null || true
systemctl restart alyan-guard 2>/dev/null || true
systemctl restart alyan-panel 2>/dev/null || true

# Verify health
HEALTH_OK=1
for svc in nginx alyan-guard xray alyan-panel; do
  if systemctl is-active --quiet "$svc"; then
    echo -e "  ${C_OK}●${C_RST} ${svc} is ${C_OK}running${C_RST}"
  else
    echo -e "  ${C_ERR}●${C_RST} ${svc} is ${C_ERR}not running${C_RST}"
    HEALTH_OK=0
  fi
done

# Step 4: Write Local Rollback Helper Script
cat > "${INSTALL_DIR}/rollback-xray-fix.sh" << 'ROLSCRIPT'
#!/usr/bin/env bash
exec bash <(curl -sSL https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/update-xray-fix.sh | tr -d '\r') --rollback
ROLSCRIPT
chmod +x "${INSTALL_DIR}/rollback-xray-fix.sh"

echo -e "\n${C_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RST}"
if (( HEALTH_OK == 1 )); then
  echo -e "${C_RED}┃${C_RST}  ${C_OK}✔ XRAY ONLINE & REAL-IP FIX APPLIED SUCCESSFULLY!${C_RST}                  ${C_RED}┃${C_RST}"
else
  echo -e "${C_RED}┃${C_RST}  ${C_AMB}⚠ Fix applied with warnings. Check service logs.${C_RST}                    ${C_RED}┃${C_RST}"
fi
echo -e "${C_RED}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_RST}"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}Webpanel Tab   :${C_RST} ${C_GLD}Refresh your browser (Ctrl + F5)${C_RST}                    ${C_RED}┃${C_RST}"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}To Revert Fix  :${C_RST} ${C_WHT}bash /opt/alyan/rollback-xray-fix.sh${C_RST}                 ${C_RED}┃${C_RST}"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}Or via Remote  :${C_RST} ${C_AMB}bash <(curl -sSL .../update-xray-fix.sh) --rollback${C_RST}    ${C_RED}┃${C_RST}"
echo -e "${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}\n"

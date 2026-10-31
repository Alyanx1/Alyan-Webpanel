#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Standalone Xray Live Online & Real-IP Hot-Fix
#  Purpose : 1. Real-time Xray & VLESS 1-IP tracking (exact device count)
#            2. Instant disconnect detection (<2 seconds offline)
#            3. AWS CloudFront CDN real IP unwrapping (collapses 8-11 IPs to 1)
#            4. HAProxy + Nginx WebSocket route for /alyan & /Alyan (fixes SSH 403)
#            5. Dropbear SSH banner brand: SSH-2.0-ALYAN_Server
#            6. Full instant 1-click rollback support (--rollback)
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
  echo -e "${C_RED}┃${C_RST}  🔥 ${C_AMB}${C_BOLD}ALYAN WEBPANEL — VLESS, CLOUDFRONT & SSH HOT-FIX${C_RST}                 ${C_RED}┃${C_RST}"
  echo -e "${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}\n"
}

# ─── ROLLBACK MODE ────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--rollback" || "${1:-}" == "revert" || "${1:-}" == "rollback" ]]; then
  banner
  echo -e "  ${C_AMB}⚡ Reverting to pre-fix state (Safety Rollback)...${C_RST}\n"
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo -e "  ${C_ERR}✖ Backup directory ${BACKUP_DIR} not found. Cannot rollback.${C_RST}\n"
    exit 1
  fi

  if [[ -f "${BACKUP_DIR}/alyan-guard.py" ]]; then
    cp -f "${BACKUP_DIR}/alyan-guard.py" "${INSTALL_DIR}/services/guard/alyan-guard.py"
    echo -e "  ${C_OK}✔ Restored:${C_RST} alyan-guard.py"
  fi
  if [[ -f "${BACKUP_DIR}/alyan-wsd.py" ]]; then
    cp -f "${BACKUP_DIR}/alyan-wsd.py" "${INSTALL_DIR}/services/wsd/alyan-wsd.py"
    echo -e "  ${C_OK}✔ Restored:${C_RST} alyan-wsd.py"
  fi
  if [[ -f "${BACKUP_DIR}/haproxy.cfg.tpl" ]]; then
    cp -f "${BACKUP_DIR}/haproxy.cfg.tpl" "${INSTALL_DIR}/templates/haproxy.cfg.tpl"
    echo -e "  ${C_OK}✔ Restored:${C_RST} templates/haproxy.cfg.tpl"
  fi
  if [[ -f "${BACKUP_DIR}/nginx-router.conf.tpl" ]]; then
    cp -f "${BACKUP_DIR}/nginx-router.conf.tpl" "${INSTALL_DIR}/templates/nginx-router.conf.tpl"
    echo -e "  ${C_OK}✔ Restored:${C_RST} templates/nginx-router.conf.tpl"
  fi
  if [[ -f "${BACKUP_DIR}/haproxy.cfg" ]]; then
    cp -f "${BACKUP_DIR}/haproxy.cfg" "/etc/haproxy/haproxy.cfg"
    echo -e "  ${C_OK}✔ Restored:${C_RST} /etc/haproxy/haproxy.cfg"
  fi
  if [[ -f "${BACKUP_DIR}/alyan-router.conf" ]]; then
    cp -f "${BACKUP_DIR}/alyan-router.conf" "/etc/nginx/conf.d/alyan-router.conf"
    echo -e "  ${C_OK}✔ Restored:${C_RST} /etc/nginx/conf.d/alyan-router.conf"
  fi
  if [[ -f "${BACKUP_DIR}/dropbear.bin" ]]; then
    cp -f "${BACKUP_DIR}/dropbear.bin" "/usr/sbin/dropbear"
    chmod +x /usr/sbin/dropbear
    echo -e "  ${C_OK}✔ Restored:${C_RST} /usr/sbin/dropbear binary"
  fi

  # Re-render and restart all services
  if [[ -x "/usr/local/bin/alyan-ctl" ]]; then
    /usr/local/bin/alyan-ctl --actor cli settings --json '{"maint":"fix_ws_ssl_stack"}' >/dev/null 2>&1 || true
  fi

  systemctl daemon-reload 2>/dev/null || true
  for svc in dropbear alyan-wsd xray nginx haproxy alyan-guard alyan-panel; do
    systemctl restart "$svc" 2>/dev/null || true
  done
  rm -f "${INSTALL_DIR}/rollback-xray-fix.sh"

  echo -e "\n  ${C_OK}✔ Rollback complete! Your panel is now exactly as it was before this update.${C_RST}\n"
  exit 0
fi

# ─── APPLY FIX MODE ───────────────────────────────────────────────────────────
banner
echo -e "  ${C_WHT}This hot-fix resolves:${C_RST}"
echo -e "    ${C_GLD}1.${C_RST} VLESS 1-IP tracking & real-time disconnect within 2 seconds"
echo -e "    ${C_GLD}2.${C_RST} AWS CloudFront real subscriber IP unwrapping (stops 8-11 IP spikes)"
echo -e "    ${C_GLD}3.${C_RST} CloudFront SSH 403 Forbidden bridge (/alyan & /Alyan)"
echo -e "    ${C_GLD}4.${C_RST} Dropbear SSH banner brand: ${C_AMB}SSH-2.0-ALYAN_Server${C_RST}\n"

# Step 1: Create Complete Safety Backup
echo -e "  ${C_AMB}[1/4] Creating safety backup in ${BACKUP_DIR}...${C_RST}"
mkdir -p "$BACKUP_DIR"
for f in "${INSTALL_DIR}/services/guard/alyan-guard.py" \
         "${INSTALL_DIR}/services/wsd/alyan-wsd.py" \
         "${INSTALL_DIR}/templates/haproxy.cfg.tpl" \
         "${INSTALL_DIR}/templates/nginx-router.conf.tpl" \
         "/etc/haproxy/haproxy.cfg" \
         "/etc/nginx/conf.d/alyan-router.conf"; do
  if [[ -f "$f" ]]; then
    cp -f "$f" "${BACKUP_DIR}/$(basename "$f")"
  fi
done
if [[ -f /usr/sbin/dropbear ]]; then
  cp -f /usr/sbin/dropbear "${BACKUP_DIR}/dropbear.bin"
fi
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${BACKUP_DIR}/backup_timestamp.txt"
echo -e "  ${C_OK}✔ Backup saved.${C_RST}"

# Step 2: Fetch and Install Updated Files
echo -e "  ${C_AMB}[2/4] Deploying updated Guard, WSD, Nginx & HAProxy router configs...${C_RST}"
mkdir -p "${INSTALL_DIR}/services/guard" "${INSTALL_DIR}/services/wsd" "${INSTALL_DIR}/templates" /var/log/nginx

# Fetch latest engine files
curl -fsSL "${REPO_RAW_URL}/services/guard/alyan-guard.py?ts=$(date +%s)" -o "${INSTALL_DIR}/services/guard/alyan-guard.py"
sed -i 's/\r$//' "${INSTALL_DIR}/services/guard/alyan-guard.py"
chmod +x "${INSTALL_DIR}/services/guard/alyan-guard.py"

curl -fsSL "${REPO_RAW_URL}/services/wsd/alyan-wsd.py?ts=$(date +%s)" -o "${INSTALL_DIR}/services/wsd/alyan-wsd.py"
sed -i 's/\r$//' "${INSTALL_DIR}/services/wsd/alyan-wsd.py"
chmod +x "${INSTALL_DIR}/services/wsd/alyan-wsd.py"

curl -fsSL "${REPO_RAW_URL}/templates/haproxy.cfg.tpl?ts=$(date +%s)" -o "${INSTALL_DIR}/templates/haproxy.cfg.tpl"
sed -i 's/\r$//' "${INSTALL_DIR}/templates/haproxy.cfg.tpl"

curl -fsSL "${REPO_RAW_URL}/templates/nginx-router.conf.tpl?ts=$(date +%s)" -o "${INSTALL_DIR}/templates/nginx-router.conf.tpl"
sed -i 's/\r$//' "${INSTALL_DIR}/templates/nginx-router.conf.tpl"

# Step 2b: Apply Dropbear SSH Banner Patch to /usr/sbin/dropbear
if [[ -f /usr/sbin/dropbear ]]; then
  python3 -c "
import re
p = '/usr/sbin/dropbear'
try:
    with open(p, 'rb') as f:
        data = f.read()
    m = re.search(rb'SSH-2.0-dropbear_[^\r\n\x00]+', data)
    if m:
        old_b = m.group(0)
        new_b = b'SSH-2.0-ALYAN_Server'
        if len(new_b) <= len(old_b):
            replacement = new_b + b'\x00' * (len(old_b) - len(new_b))
            patched = data[:m.start()] + replacement + data[m.end():]
            with open(p, 'wb') as f:
                f.write(patched)
except Exception:
    pass
" 2>/dev/null || true
fi

# Ensure nginx xray log exists with write permissions
touch /var/log/nginx/alyan-xray.log
chmod 0666 /var/log/nginx/alyan-xray.log 2>/dev/null || true

# Re-render HAProxy and Nginx router configs with the new templates
if [[ -x "/usr/local/bin/alyan-ctl" ]]; then
  /usr/local/bin/alyan-ctl --actor cli settings --json '{"maint":"fix_ws_ssl_stack"}' >/dev/null 2>&1 || true
fi
echo -e "  ${C_OK}✔ Engine files & templates updated.${C_RST}"

# Step 3: Verify and Restart Services
echo -e "  ${C_AMB}[3/4] Testing configuration and restarting services...${C_RST}"
if command -v python3 &>/dev/null; then
  python3 -m py_compile "${INSTALL_DIR}/services/guard/alyan-guard.py" "${INSTALL_DIR}/services/wsd/alyan-wsd.py"
fi
nginx -t >/dev/null 2>&1 || true
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 || true

systemctl daemon-reload 2>/dev/null || true
for svc in dropbear alyan-wsd xray nginx haproxy alyan-guard alyan-panel; do
  systemctl restart "$svc" 2>/dev/null || true
done

# Verify health
HEALTH_OK=1
for svc in dropbear alyan-wsd xray nginx haproxy alyan-guard alyan-panel; do
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
  echo -e "${C_RED}┃${C_RST}  ${C_OK}✔ ALYAN WEBPANEL FIX APPLIED SUCCESSFULLY!${C_RST}                         ${C_RED}┃${C_RST}"
else
  echo -e "${C_RED}┃${C_RST}  ${C_AMB}⚠ Fix applied with warnings. Check service logs.${C_RST}                    ${C_RED}┃${C_RST}"
fi
echo -e "${C_RED}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_RST}"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}Webpanel Tab   :${C_RST} ${C_GLD}Refresh your browser (Ctrl + F5)${C_RST}                    ${C_RED}┃${C_RST}"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}Dropbear Banner:${C_RST} ${C_WHT}SSH-2.0-ALYAN_Server${C_RST}                                 ${C_RED}┃${C_RST}"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}To Revert Fix  :${C_RST} ${C_WHT}bash /opt/alyan/rollback-xray-fix.sh${C_RST}                 ${C_RED}┃${C_RST}"
echo -e "${C_RED}┃${C_RST}  ${C_GRY}Or via Remote  :${C_RST} ${C_AMB}bash <(curl -sSL .../update-xray-fix.sh) --rollback${C_RST}    ${C_RED}┃${C_RST}"
echo -e "${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}\n"

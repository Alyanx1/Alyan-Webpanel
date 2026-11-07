#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  ALYAN WEBPANEL — VLESS / Xray Precision Hot-Update (SSH Untouched)
#  - Fixes 2 IPs / 2 Live Users when 1 VLESS device connects
#  - Genuine 2-second real-time Xray backend data counter sync
#  - Instant 2-second VLESS disconnect detection (no lingering online state)
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

INSTALL_DIR="/opt/alyan"
REPO_RAW="https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main"
TS="$(date +%s)"

mkdir -p "${INSTALL_DIR}/templates" "${INSTALL_DIR}/services/guard" "${INSTALL_DIR}/core" "${INSTALL_DIR}/panel/static"

echo -e "\033[38;5;208m[1/4]\033[0m Downloading VLESS / Xray precision update from GitHub..."
curl -fsSL "${REPO_RAW}/templates/xray-config.json.tpl?t=${TS}" -o "${INSTALL_DIR}/templates/xray-config.json.tpl"
curl -fsSL "${REPO_RAW}/services/guard/alyan-guard.py?t=${TS}" -o "${INSTALL_DIR}/services/guard/alyan-guard.py"
curl -fsSL "${REPO_RAW}/core/alyan-ctl?t=${TS}" -o "${INSTALL_DIR}/core/alyan-ctl"
curl -fsSL "${REPO_RAW}/panel/static/app.js?t=${TS}" -o "${INSTALL_DIR}/panel/static/app.js"

for f in \
  "${INSTALL_DIR}/templates/xray-config.json.tpl" \
  "${INSTALL_DIR}/services/guard/alyan-guard.py" \
  "${INSTALL_DIR}/core/alyan-ctl" \
  "${INSTALL_DIR}/panel/static/app.js"; do
  sed -i 's/\r$//' "$f" 2>/dev/null || true
done

chmod +x "${INSTALL_DIR}/core/alyan-ctl" "${INSTALL_DIR}/services/guard/alyan-guard.py"
ln -sf "${INSTALL_DIR}/core/alyan-ctl" /usr/local/bin/alyan-ctl

echo -e "\033[38;5;208m[2/4]\033[0m Clearing stale Xray access logs & live cache..."
: > /var/log/xray/access.log 2>/dev/null || true
: > /var/log/nginx/alyan-xray.log 2>/dev/null || true
rm -f /run/alyan-live.json /run/alyan-live.tmp

echo -e "\033[38;5;208m[3/4]\033[0m Syncing Xray config (Real-IP XFF + statsUserOnline + 2s WS Heartbeat)..."
/usr/local/bin/alyan-ctl xray-sync

echo -e "\033[38;5;208m[4/4]\033[0m Restarting Xray, Alyan Guard & Webpanel (SSH untouched)..."
systemctl restart xray alyan-guard alyan-panel

echo -e "\033[38;5;82m✔ VLESS / Xray update applied successfully!\033[0m"

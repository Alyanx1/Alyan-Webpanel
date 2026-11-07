#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  ALYAN WEBPANEL — VLESS Live Users (1 vs 2 Flicker) Surgical Fix
#  - Restores clean SIM Real-IP baseline files
#  - Fixes dev_map duplicate key bug (f"{best_ip}:{len(dev_map)}") in alyan-guard.py
#  - Syncs top Live Users counter with card LIVE USERS counter in app.js
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

INSTALL_DIR="/opt/alyan"
REPO_RAW="https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main"
TS="$(date +%s)"

echo -e "\033[38;5;208m[1/3]\033[0m Restoring clean SIM Real-IP baseline files..."
curl -fsSL "${REPO_RAW}/templates/xray-config.json.tpl?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/templates/xray-config.json.tpl"
curl -fsSL "${REPO_RAW}/services/guard/alyan-guard.py?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/services/guard/alyan-guard.py"
curl -fsSL "${REPO_RAW}/core/alyan-ctl?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/core/alyan-ctl"
curl -fsSL "${REPO_RAW}/panel/static/app.js?t=${TS}" | tr -d '\r' > "${INSTALL_DIR}/panel/static/app.js"

chmod +x "${INSTALL_DIR}/core/alyan-ctl" "${INSTALL_DIR}/services/guard/alyan-guard.py"
ln -sf "${INSTALL_DIR}/core/alyan-ctl" /usr/local/bin/alyan-ctl

echo -e "\033[38;5;208m[2/3]\033[0m Applying surgical fix for VLESS Live Users 1/2 flicker..."
python3 - <<'PYEOF'
from pathlib import Path

# 1. Fix alyan-guard.py: stop creating fake duplicate key f"{best_ip}:{len(dev_map)}" on every 2s tick
guard_path = Path("/opt/alyan/services/guard/alyan-guard.py")
g_txt = guard_path.read_text(encoding="utf-8")

old_guard = '''        if best_ip:
            dev_k = f"{best_ip}:{len(dev_map)}" if best_ip in dev_map else best_ip
            dev_map[dev_k] = {"ip": best_ip, "ts": now_ts}
            max_devs = max(1, active_sockets)
            if len(dev_map) > max_devs:
                sorted_keys = sorted(dev_map.keys(), key=lambda k: dev_map[k]["ts"], reverse=True)
                for k in sorted_keys[max_devs:]:
                    dev_map.pop(k, None)

        # Short timeout (3.5s) for any lingering device
        for stale_k in [k for k, v in dev_map.items() if (now_ts - v["ts"]) > 3.5]:
            dev_map.pop(stale_k, None)

        ips_by_uuid[uid] = sorted({v["ip"] for v in dev_map.values()})
        dev_count_by_uuid[uid] = max(len(ips_by_uuid[uid]), len(dev_map))'''

new_guard = '''        if best_ip:
            dev_k = device_key_for_ip(best_ip)
            dev_map[dev_k] = {"ip": best_ip, "ts": now_ts}
            max_devs = max(1, active_sockets)
            if len(dev_map) > max_devs:
                sorted_keys = sorted(dev_map.keys(), key=lambda k: dev_map[k]["ts"], reverse=True)
                for k in sorted_keys[max_devs:]:
                    dev_map.pop(k, None)

        # Short timeout (3.5s) for any lingering device
        for stale_k in [k for k, v in dev_map.items() if (now_ts - v["ts"]) > 3.5]:
            dev_map.pop(stale_k, None)

        ips_by_uuid[uid] = sorted({v["ip"] for v in dev_map.values()})
        dev_count_by_uuid[uid] = len(ips_by_uuid[uid])'''

assert old_guard in g_txt, "Target block not found in alyan-guard.py"
guard_path.write_text(g_txt.replace(old_guard, new_guard, 1), encoding="utf-8")

# 2. Fix app.js: make top Live Users button use exact same IP-first formula as the VLESS card
app_js_path = Path("/opt/alyan/panel/static/app.js")
j_txt = app_js_path.read_text(encoding="utf-8")

old_js = '''    const getXrayLiveUsersTotal = () => items.filter(u => u.proto === STATE.xrayProto).reduce((acc, u) => acc + (u.status === 'disabled' ? 0 : (u.online || (u.ips || []).length || 0)), 0);
    const getXrayLiveUsersList = () => items
      .filter(u => u.status !== 'disabled' && u.proto === STATE.xrayProto && (u.online > 0 || (u.ips && u.ips.length > 0)))
      .map(u => ({
        user: u.username,
        proto: u.proto.toUpperCase(),
        online: u.online || (u.ips || []).length || 0,
        limit: u.ip_limit > 0 ? `${u.ip_limit} Users` : 'Unlimited'
      }));'''

new_js = '''    const getXrayLiveUsersTotal = () => items.filter(u => u.proto === STATE.xrayProto).reduce((acc, u) => acc + (u.status === 'disabled' ? 0 : ((u.ips || []).length || u.online || 0)), 0);
    const getXrayLiveUsersList = () => items
      .filter(u => u.status !== 'disabled' && u.proto === STATE.xrayProto && ((u.ips && u.ips.length > 0) || u.online > 0))
      .map(u => ({
        user: u.username,
        proto: u.proto.toUpperCase(),
        online: (u.ips || []).length || u.online || 0,
        limit: u.ip_limit > 0 ? `${u.ip_limit} Users` : 'Unlimited'
      }));'''

assert old_js in j_txt, "Target block not found in app.js"
app_js_path.write_text(j_txt.replace(old_js, new_js, 1), encoding="utf-8")
print("✔ Surgical patch verified and applied.")
PYEOF

echo -e "\033[38;5;208m[3/3]\033[0m Syncing Xray config & restarting services..."
/usr/local/bin/alyan-ctl xray-sync
rm -f /run/alyan-live.json /run/alyan-live.tmp
systemctl restart xray alyan-guard alyan-panel

echo -e "\033[38;5;82m✔ VLESS Live Users fix applied! Main panel repo files untouched.\033[0m"

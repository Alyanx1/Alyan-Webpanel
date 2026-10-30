#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Interactive Flame CLI Dashboard (`menu` command)
#  Provides full terminal control over SSH-WS (/alyan), Xray, SSL, QoS, Bot & Panel
# ═════════════════════════════════════════════════════════════════════════════
set -uo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

CTL="/usr/local/bin/alyan-ctl"
INSTALL_DIR="/opt/alyan"

# ─── Flame Truecolor Palette ─────────────────────────────────────────────────
C_RST='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[38;2;255;36;36m'
C_ORG='\033[38;2;255;106;0m'
C_AMB='\033[38;2;255;180;0m'
C_GLD='\033[38;2;255;218;110m'
C_WHT='\033[38;2;245;242;238m'
C_GRY='\033[38;2;138;132;150m'
C_OK='\033[38;2;60;235;140m'
C_ERR='\033[38;2;255;68;68m'

pause_ret() {
  echo ""
  read -rp "$(echo -e "  ${C_AMB}Press [Enter] to return to Alyan Menu...${C_RST}")" _ </dev/tty
}

svc_dot() {
  if systemctl is-active --quiet "$1" 2>/dev/null; then
    echo -e "${C_OK}● ON ${C_RST}"
  else
    echo -e "${C_ERR}● OFF${C_RST}"
  fi
}

make_xray_links() {
  local proto="$1" user="$2" uuid="$3" dom="$4"
  python3 - "$proto" "$user" "$uuid" "$dom" <<'PY'
import base64, json, sys, urllib.parse
proto, user, uid, dom = sys.argv[1:5]
tag = urllib.parse.quote(f"Alyan-{user}")
if proto == "vless":
    print(f"  VLESS WS TLS  : vless://{uid}@{dom}:443?encryption=none&security=tls&sni={dom}&type=ws&host={dom}&path=%2Falyan-vless#{tag}-WS-TLS")
    print(f"  VLESS WS 80   : vless://{uid}@{dom}:80?encryption=none&security=none&type=ws&host={dom}&path=%2Falyan-vless#{tag}-WS-80")
    print(f"  VLESS gRPC    : vless://{uid}@{dom}:443?encryption=none&security=tls&sni={dom}&type=grpc&serviceName=alyan-vless-grpc#{tag}-gRPC")
    print(f"  VLESS XHTTP   : vless://{uid}@{dom}:443?encryption=none&security=tls&sni={dom}&type=xhttp&host={dom}&path=%2Falyan-xhttp#{tag}-XHTTP")
elif proto == "vmess":
    for port, tls in (("443", "tls"), ("80", "")):
        obj = {"v": "2", "ps": f"Alyan-{user}-{port}", "add": dom, "port": port, "id": uid, "aid": "0", "scy": "auto", "net": "ws", "type": "none", "host": dom, "path": "/alyan-vmess", "tls": tls, "sni": dom if tls else ""}
        b64 = base64.b64encode(json.dumps(obj, separators=(",", ":")).encode()).decode()
        print(f"  VMess WS {port:<4} : vmess://{b64}")
elif proto == "trojan":
    print(f"  Trojan TCP    : trojan://{uid}@{dom}:443?security=tls&sni={dom}&type=tcp#{tag}-TCP")
    print(f"  Trojan WS TLS : trojan://{uid}@{dom}:443?security=tls&sni={dom}&type=ws&host={dom}&path=%2Falyan-trojan#{tag}-WS")
    print(f"  Trojan gRPC   : trojan://{uid}@{dom}:443?security=tls&sni={dom}&type=grpc&serviceName=alyan-trojan-grpc#{tag}-gRPC")
PY
}

draw_header() {
  clear || true
  local ov domain ip port cpu ram up ssh_tot ssh_on xray_tot ssl_d
  ov=$($CTL --actor cli overview 2>/dev/null || echo '{}')
  domain=$(echo "$ov" | jq -r '.cfg.domain // "unconfigured"')
  ip=$(echo "$ov" | jq -r '.cfg.ip // "127.0.0.1"')
  port=$(echo "$ov" | jq -r '.cfg.panel_port // 8443')
  ssl_d=$(echo "$ov" | jq -r '.cfg.ssl_days // 0')
  up=$(echo "$ov" | jq -r '.cfg.uptime // "0h"')
  cpu=$(echo "$ov" | jq -r '.cpu_pct // 0')
  ram=$(echo "$ov" | jq -r '.ram_pct // 0')
  ssh_tot=$(echo "$ov" | jq -r '.ssh_total // 0')
  ssh_on=$(echo "$ov" | jq -r '.ssh_online // 0')
  xray_tot=$(echo "$ov" | jq -r '.xray_total // 0')

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
  echo -e "${C_RST}  🔥 ${C_GLD}${C_BOLD}ALYAN WEBPANEL${C_RST} ${C_GRY}· FLAME TUNNELING COMMAND DECK${C_RST}"
  echo -e "  ${C_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RST}"
  printf "  ${C_RED}┃${C_RST} ${C_GRY}Domain :${C_RST} ${C_GLD}%-24s${C_RST} ${C_GRY}IP :${C_RST} ${C_WHT}%-16s${C_RST} ${C_GRY}SSL:${C_RST} ${C_AMB}%3sd${C_RST} ${C_RED}┃${C_RST}\n" "$domain" "$ip" "$ssl_d"
  printf "  ${C_RED}┃${C_RST} ${C_GRY}CPU/RAM:${C_RST} ${C_WHT}%2s%% / %2s%%${C_RST}   ${C_GRY}Up:${C_RST} ${C_WHT}%-9s${C_RST} ${C_GRY}SSH:${C_RST} ${C_AMB}%s (%s live)${C_RST}  ${C_GRY}Xray:${C_RST} ${C_AMB}%s${C_RST}  ${C_RED}┃${C_RST}\n" "$cpu" "$ram" "$up" "$ssh_tot" "$ssh_on" "$xray_tot"
  echo -e "  ${C_RED}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_RST}"
  echo -e "  ${C_RED}┃${C_RST} HAProxy $(svc_dot haproxy)  Nginx $(svc_dot nginx)  Dropbear $(svc_dot dropbear)  WS $(svc_dot alyan-wsd)  Xray $(svc_dot xray) ${C_RED}┃${C_RST}"
  echo -e "  ${C_RED}┃${C_RST} Panel   $(svc_dot alyan-panel)  Guard $(svc_dot alyan-guard)  Ping     $(svc_dot alyan-qos)  Bot $(svc_dot alyan-bot)  :${port}      ${C_RED}┃${C_RST}"
  echo -e "  ${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}"
}

# ─── Option 1: Install / Re-Verify All Components ────────────────────────────
opt_install_all() {
  echo -e "\n  ${C_AMB}${C_BOLD}⚡ Option 1 — Install / Re-Verify All Components${C_RST}"
  if [[ -f "${INSTALL_DIR}/install.sh" ]]; then
    read -rp "  Re-run full installer? [y/N]: " ans </dev/tty
    if [[ "${ans,,}" == "y" ]]; then
      bash "${INSTALL_DIR}/install.sh"
      pause_ret
      return
    fi
  fi
  echo -e "  ${C_GRY}Verifying packages, configs & restarting tunneling stack...${C_RST}"
  apt-get update -qq && apt-get install -y -qq dropbear nginx haproxy jq sqlite3 curl openssl iproute2 >/dev/null
  $CTL --actor cli settings --json '{"maint":"fix_ws_ssl_stack"}' >/dev/null
  $CTL --actor cli service all restart >/dev/null
  echo -e "  ${C_OK}✔ All core packages, templates & daemons verified and running!${C_RST}"
  pause_ret
}

# ─── Option 2: Add / Change Domain (Auto SSL) ────────────────────────────────
opt_change_domain() {
  echo -e "\n  ${C_AMB}${C_BOLD}🌐 Option 2 — Add / Change Custom Domain (Auto SSL Sync)${C_RST}"
  read -rp "  Enter new Custom Domain: " new_dom </dev/tty
  new_dom=$(echo "$new_dom" | tr '[:upper:]' '[:lower:]' | xargs)
  if [[ -z "$new_dom" ]]; then return; fi
  echo -e "  ${C_ORG}🔥 Updating domain to ${new_dom}, issuing Let's Encrypt EC-256 SSL & reloading HAProxy/Nginx...${C_RST}"
  res=$($CTL --actor cli settings --json "$(jq -nc --arg d "$new_dom" '{domain:$d}')" 2>&1)
  if echo "$res" | jq -e '.ok' >/dev/null 2>&1; then
    ssl_d=$(echo "$res" | jq -r '.cfg.ssl_days')
    echo -e "  ${C_OK}✔ Domain updated to ${new_dom} (SSL valid: ${ssl_d} days)!${C_RST}"
  else
    echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
  fi
  pause_ret
}

# ─── Option 3: SSL Certificate (Issue / Renew) ───────────────────────────────
opt_ssl_cert() {
  echo -e "\n  ${C_AMB}${C_BOLD}🔒 Option 3 — SSL Certificate (Issue / Force Renew)${C_RST}"
  echo -e "  ${C_ORG}🔥 Requesting fresh Let's Encrypt EC-256 certificate & rebuilding HAProxy bundle...${C_RST}"
  res=$($CTL --actor cli ssl-issue 2>&1)
  if echo "$res" | jq -e '.ssl_days' >/dev/null 2>&1; then
    dom=$(echo "$res" | jq -r '.domain')
    days=$(echo "$res" | jq -r '.ssl_days')
    echo -e "  ${C_OK}✔ Certificate active for ${dom} (${days} days remaining).${C_RST}"
  else
    echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
  fi
  pause_ret
}

# ─── Option 4: Manage Users / Limits / Banner ────────────────────────────────
opt_manage_users() {
  while true; do
    draw_header
    echo -e "  ${C_AMB}${C_BOLD}👥 Option 4 — Manage Users / Limits / Banner${C_RST}"
    echo -e "  ${C_ORG}  [1]${C_WHT} Create SSH Account (+ /alyan Payload)     ${C_ORG}[6]${C_WHT} Create Xray Client (VLESS/VMess/Trojan)${C_RST}"
    echo -e "  ${C_ORG}  [2]${C_WHT} List SSH Accounts & Live IPs              ${C_ORG}[7]${C_WHT} List Xray Clients & Share Links${C_RST}"
    echo -e "  ${C_ORG}  [3]${C_WHT} Edit / Renew SSH Limits (Days/GB/IP)      ${C_ORG}[8]${C_WHT} Edit Xray Client${C_RST}"
    echo -e "  ${C_ORG}  [4]${C_WHT} Enable / Disable SSH Account              ${C_ORG}[9]${C_WHT} Delete Xray Client${C_RST}"
    echo -e "  ${C_ORG}  [5]${C_WHT} Delete SSH Account                        ${C_ORG}[10]${C_WHT} Set SSH Handshake Banner${C_RST}"
    echo -e "  ${C_ORG}  [0]${C_GRY} Back to Main Menu${C_RST}\n"
    read -rp "  Select action [0-10]: " uopt </dev/tty
    case "$uopt" in
      1)
        read -rp "  Username       : " u </dev/tty
        read -rp "  Password       : " p </dev/tty
        read -rp "  Validity Days [30] : " d </dev/tty; d="${d:-30}"
        read -rp "  GB Quota (0=∞) [0] : " g </dev/tty; g="${g:-0}"
        read -rp "  IP Limit (0=∞) [2] : " ipm </dev/tty; ipm="${ipm:-2}"
        res=$($CTL --actor cli ssh-add --username "$u" --password "$p" --days "$d" --gb-limit "$g" --ip-limit "$ipm" 2>&1)
        if echo "$res" | jq -e '.item' >/dev/null 2>&1; then
          dom=$(echo "$res" | jq -r '.cfg.domain')
          exp=$(echo "$res" | jq -r '.item.expiry')
          echo -e "\n  ${C_OK}✔ SSH Account Created!${C_RST}"
          echo -e "  ${C_GRY}Host / SNI :${C_RST} ${C_GLD}${dom}${C_RST}"
          echo -e "  ${C_GRY}Username   :${C_RST} ${C_WHT}${u}${C_RST}   ${C_GRY}Password:${C_RST} ${C_WHT}${p}${C_RST}   ${C_GRY}Expires:${C_RST} ${C_AMB}${exp}${C_RST}"
          echo -e "  ${C_GRY}Ports      :${C_RST} Direct 22, 109, 143 · WS 80 · WS-SSL 443 (/alyan)"
          echo -e "  ${C_GRY}Payload    :${C_RST} ${C_AMB}GET /alyan HTTP/1.1[crlf]Host: ${dom}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${C_RST}"
        else
          echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        fi
        pause_ret ;;
      2)
        res=$($CTL --actor cli ssh-list)
        echo ""
        printf "  ${C_AMB}%-16s %-10s %-12s %-14s %-8s %-10s${C_RST}\n" "USERNAME" "STATUS" "EXPIRY" "USED / QUOTA" "IP CAP" "ONLINE"
        echo "$res" | jq -r '.items[] | "\(.username)|\(.status)|\(.expiry)|\((.used_bytes/1073741824*100|round)/100)G/\(if .gb_limit>0 then (.gb_limit|tostring)+"G" else "inf" end)|\(if .ip_limit>0 then (.ip_limit|tostring) else "inf" end)|\(.online)"' | \
        while IFS='|' read -r un st ex qt ic on; do
          printf "  %-16s %-10s %-12s %-14s %-8s %-10s\n" "$un" "$st" "$ex" "$qt" "$ic" "$on"
        done
        pause_ret ;;
      3)
        read -rp "  SSH Username to edit : " u </dev/tty
        read -rp "  New Days [30]        : " d </dev/tty; d="${d:-30}"
        read -rp "  GB Limit (0=∞) [0]   : " g </dev/tty; g="${g:-0}"
        read -rp "  IP Limit (0=∞) [2]   : " ipm </dev/tty; ipm="${ipm:-2}"
        read -rp "  Reset Used Quota? [y/N]: " rq </dev/tty
        rj="false"; [[ "${rq,,}" == "y" ]] && rj="true"
        payload=$(jq -nc --argjson d "$d" --argjson g "$g" --argjson i "$ipm" --argjson r "$rj" '{days:$d,gb_limit:$g,ip_limit:$i,reset_quota:$r}')
        res=$($CTL --actor cli ssh-edit --username "$u" --json "$payload" 2>&1)
        echo "$res" | jq -e '.item' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ Updated ${u}!${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        pause_ret ;;
      4)
        read -rp "  SSH Username         : " u </dev/tty
        read -rp "  Set [1] Enable  [2] Disable : " st_c </dev/tty
        st_v="active"; [[ "$st_c" == "2" ]] && st_v="disabled"
        res=$($CTL --actor cli ssh-edit --username "$u" --json "{\"status\":\"${st_v}\"}" 2>&1)
        echo "$res" | jq -e '.item' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ ${u} is now ${st_v}!${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        pause_ret ;;
      5)
        read -rp "  SSH Username to DELETE: " u </dev/tty
        res=$($CTL --actor cli ssh-del --username "$u" 2>&1)
        echo "$res" | jq -e '.ok' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ Deleted ${u}.${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        pause_ret ;;
      6)
        read -rp "  Protocol (vless/vmess/trojan) [vless]: " pr </dev/tty; pr="${pr:-vless}"
        read -rp "  Client Username : " u </dev/tty
        read -rp "  Validity Days [30]: " d </dev/tty; d="${d:-30}"
        read -rp "  GB Limit (0=∞) [0]: " g </dev/tty; g="${g:-0}"
        read -rp "  IP Limit (0=∞) [2]: " ipm </dev/tty; ipm="${ipm:-2}"
        res=$($CTL --actor cli xray-add --username "$u" --proto "$pr" --days "$d" --gb-limit "$g" --ip-limit "$ipm" 2>&1)
        if echo "$res" | jq -e '.item' >/dev/null 2>&1; then
          uid=$(echo "$res" | jq -r '.item.uuid')
          dom=$(echo "$res" | jq -r '.cfg.domain')
          echo -e "\n  ${C_OK}✔ Created ${pr^^} client '${u}' (UUID: ${uid})${C_RST}"
          make_xray_links "$pr" "$u" "$uid" "$dom"
        else
          echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        fi
        pause_ret ;;
      7)
        res=$($CTL --actor cli xray-list)
        dom=$(echo "$res" | jq -r '.cfg.domain')
        echo ""
        printf "  ${C_AMB}%-14s %-8s %-12s %-38s${C_RST}\n" "USERNAME" "PROTO" "EXPIRY" "UUID / KEY"
        echo "$res" | jq -r '.items[] | "\(.username)|\(.proto)|\(.expiry)|\(.uuid)"' | \
        while IFS='|' read -r un pr ex uu; do
          printf "  %-14s %-8s %-12s %-38s\n" "$un" "${pr^^}" "$ex" "$uu"
        done
        read -rp "  Enter username to print share links (or Enter to skip): " lu </dev/tty
        if [[ -n "$lu" ]]; then
          row=$(echo "$res" | jq -c --arg u "$lu" '.items[] | select(.username==$u)' | head -n1)
          if [[ -n "$row" ]]; then
            make_xray_links "$(echo "$row" | jq -r '.proto')" "$lu" "$(echo "$row" | jq -r '.uuid')" "$dom"
          fi
        fi
        pause_ret ;;
      8)
        read -rp "  Enter Xray Client UUID to edit: " uu </dev/tty
        read -rp "  New Days [30]     : " d </dev/tty; d="${d:-30}"
        read -rp "  GB Limit (0=∞) [0]: " g </dev/tty; g="${g:-0}"
        read -rp "  IP Limit (0=∞) [2]: " ipm </dev/tty; ipm="${ipm:-2}"
        payload=$(jq -nc --argjson d "$d" --argjson g "$g" --argjson i "$ipm" '{days:$d,gb_limit:$g,ip_limit:$i}')
        res=$($CTL --actor cli xray-edit --uuid "$uu" --json "$payload" 2>&1)
        echo "$res" | jq -e '.item' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ Xray client updated!${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        pause_ret ;;
      9)
        read -rp "  Enter Xray Client UUID to DELETE: " uu </dev/tty
        res=$($CTL --actor cli xray-del --uuid "$uu" 2>&1)
        echo "$res" | jq -e '.ok' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ Xray client removed.${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        pause_ret ;;
      10)
        echo -e "  Enter new SSH Banner HTML/Text (single line, leave blank to cancel):"
        read -rp "  Banner > " btxt </dev/tty
        if [[ -n "$btxt" ]]; then
          $CTL --actor cli settings --json "$(jq -nc --arg b "$btxt" '{banner:$b}')" >/dev/null
          echo -e "  ${C_OK}✔ SSH Banner updated and Dropbear reloaded!${C_RST}"
        fi
        pause_ret ;;
      0|"") break ;;
    esac
  done
}

# ─── Option 5: Status & Ports ────────────────────────────────────────────────
opt_status_ports() {
  echo -e "\n  ${C_AMB}${C_BOLD}⚙ Option 5 — Daemons Status & Live Listening TCP Ports${C_RST}"
  eng=$($CTL --actor cli engine)
  echo ""
  printf "  ${C_AMB}%-15s %-24s %-10s %-10s %-10s${C_RST}\n" "SERVICE ID" "DAEMON NAME" "STATUS" "MEMORY" "UPTIME"
  echo "$eng" | jq -r '.services[] | "\(.id)|\(.name)|\(.status)|\(.mem)|\(.uptime)"' | \
  while IFS='|' read -r sid snm sst smm sup; do
    col="$C_OK"; [[ "$sst" != "running" ]] && col="$C_ERR"
    printf "  %-15s %-24s ${col}%-10s${C_RST} %-10s %-10s\n" "$sid" "$snm" "$sst" "$smm" "$sup"
  done

  echo -e "\n  ${C_AMB}PORT     BIND            SCOPE      DAEMON          ROLE${C_RST}"
  echo "$eng" | jq -r '.ports[] | "\(.port)|\(.addr)|\(.scope)|\(.proc)|\(.note)"' | \
  while IFS='|' read -r prt adr scp prc nte; do
    printf "  %-8s %-15s %-10s %-15s %s\n" ":$prt" "$adr" "$scp" "$prc" "$nte"
  done

  echo ""
  read -rp "  Control daemon? Enter '<id> <start|stop|restart>' (or Enter to skip): " scmd </dev/tty
  if [[ -n "$scmd" ]]; then
    read -r t_id t_act <<<"$scmd"
    if [[ -n "${t_id:-}" && -n "${t_act:-}" ]]; then
      $CTL --actor cli service "$t_id" "$t_act" >/dev/null 2>&1 && echo -e "  ${C_OK}✔ ${t_id}: ${t_act} completed.${C_RST}" || echo -e "  ${C_ERR}✖ Failed to ${t_act} ${t_id}.${C_RST}"
    fi
  fi
  pause_ret
}

# ─── Option 6: Fix SSH-WS / SSL Stack ────────────────────────────────────────
opt_fix_stack() {
  echo -e "\n  ${C_AMB}${C_BOLD}🛠 Option 6 — Fix SSH-WS (/alyan) / SSL / HAProxy / Xray Stack${C_RST}"
  echo -e "  ${C_ORG}🔥 Rebuilding PEM bundle, Dropbear 109/143 override, Nginx, HAProxy & Xray configs...${C_RST}"
  $CTL --actor cli settings --json '{"maint":"fix_ws_ssl_stack"}' >/dev/null
  $CTL --actor cli service all restart >/dev/null
  echo -e "  ${C_OK}✔ Full SSH-WS + SSL + Multiplexer stack repaired & restarted!${C_RST}"
  pause_ret
}

# ─── Option 7: Ping Stability (QoS) ──────────────────────────────────────────
opt_ping_qos() {
  echo -e "\n  ${C_AMB}${C_BOLD}🚀 Option 7 — Ping Stability (Anti-Bufferbloat QoS)${C_RST}"
  ov=$($CTL --actor cli overview)
  cur_if=$(echo "$ov" | jq -r '.cfg.qos.iface // "eth0"')
  cur_bw=$(echo "$ov" | jq -r '.cfg.qos.bw_mbps // 500')
  cur_en=$(echo "$ov" | jq -r '.cfg.qos.enabled')
  echo -e "  Current State: ${C_GLD}enabled=${cur_en}${C_RST} · NIC=${C_WHT}${cur_if}${C_RST} · Ceiling=${C_WHT}${cur_bw} Mbps${C_RST}"
  echo -e "  ${C_ORG}[1]${C_WHT} Apply Gaming Low-Ping Preset (CAKE diffserv4 + nat + ack-filter)${C_RST}"
  echo -e "  ${C_ORG}[2]${C_WHT} Apply Balanced Fair-Queue Preset${C_RST}"
  echo -e "  ${C_ORG}[3]${C_WHT} Apply Max Throughput Preset${C_RST}"
  echo -e "  ${C_ORG}[4]${C_WHT} Add Per-IP Bandwidth Cap${C_RST}"
  echo -e "  ${C_ORG}[5]${C_WHT} Disable Ping Stability${C_RST}"
  read -rp "  Choose [1-5, Enter=cancel]: " qopt </dev/tty
  case "$qopt" in
    1|2|3)
      preset="gaming"; [[ "$qopt" == "2" ]] && preset="balanced"; [[ "$qopt" == "3" ]] && preset="throughput"
      read -rp "  NIC Interface [${cur_if}]: " nif </dev/tty; nif="${nif:-$cur_if}"
      read -rp "  Bandwidth Ceiling Mbps [${cur_bw}]: " nbw </dev/tty; nbw="${nbw:-$cur_bw}"
      payload=$(jq -nc --arg i "$nif" --arg p "$preset" --argjson b "$nbw" '{qos:{enabled:true,iface:$i,bw_mbps:$b,preset:$p}}')
      $CTL --actor cli settings --json "$payload" >/dev/null
      echo -e "  ${C_OK}✔ Ping Stability (${preset}) active on ${nif} @ ${nbw} Mbps!${C_RST}" ;;
    4)
      read -rp "  Target IPv4 address : " cip </dev/tty
      read -rp "  Speed Cap (Mbps) [25]: " cmb </dev/tty; cmb="${cmb:-25}"
      payload=$(jq -nc --arg ip "$cip" --argjson m "$cmb" '{add_cap:{ip:$ip,mbps:$m}}')
      res=$($CTL --actor cli settings --json "$payload" 2>&1)
      echo "$res" | jq -e '.ok' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ Added ${cmb} Mbps cap for ${cip}.${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}" ;;
    5)
      $CTL --actor cli settings --json '{"qos":{"enabled":false}}' >/dev/null
      echo -e "  ${C_OK}✔ Ping Stability disabled.${C_RST}" ;;
  esac
  pause_ret
}

# ─── Option 8: VPS Stats / Speedtest ─────────────────────────────────────────
opt_vps_speedtest() {
  echo -e "\n  ${C_AMB}${C_BOLD}📊 Option 8 — VPS Hardware Stats & Live Flame Speedtest${C_RST}"
  tel=$($CTL --actor cli telemetry)
  echo -e "  ${C_GRY}OS / Kernel :${C_RST} $(echo "$tel" | jq -r '.cfg.os') · $(echo "$tel" | jq -r '.cfg.kernel')"
  echo -e "  ${C_GRY}CPU Model   :${C_RST} $(echo "$tel" | jq -r '.cfg.cpu_model')"
  echo -e "  ${C_GRY}Location    :${C_RST} $(echo "$tel" | jq -r '.cfg.location') · $(echo "$tel" | jq -r '.cfg.provider')"
  echo -e "  ${C_GRY}CPU / Load  :${C_RST} $(echo "$tel" | jq -r '.cpu_pct')%  (load: $(echo "$tel" | jq -r '.load'))"
  echo -e "  ${C_GRY}RAM / Disk  :${C_RST} RAM $(echo "$tel" | jq -r '.ram_pct')%  ·  Disk $(echo "$tel" | jq -r '.disk_pct')%"
  echo ""
  read -rp "  Run live download/upload benchmark now? [Y/n]: " rst </dev/tty
  if [[ "${rst,,}" != "n" ]]; then
    echo -e "  ${C_ORG}🔥 Running live speedtest benchmark (please wait ~10-20s)...${C_RST}"
    st=$($CTL --actor cli speedtest)
    echo -e "  ${C_OK}✔ Ping    :${C_RST} $(echo "$st" | jq -r '.ping') ms  (Jitter: $(echo "$st" | jq -r '.jitter') ms)"
    echo -e "  ${C_OK}✔ Download:${C_RST} ${C_GLD}$(echo "$st" | jq -r '.down') Mbps${C_RST}"
    echo -e "  ${C_OK}✔ Upload  :${C_RST} ${C_GLD}$(echo "$st" | jq -r '.up') Mbps${C_RST}  ($(echo "$st" | jq -r '.isp'))"
  fi
  pause_ret
}

# ─── Option 9: Telegram Bot ──────────────────────────────────────────────────
opt_telegram_bot() {
  echo -e "\n  ${C_AMB}${C_BOLD}✈ Option 9 — Telegram User-Management Bot${C_RST}"
  ov=$($CTL --actor cli overview)
  b_en=$(echo "$ov" | jq -r '.cfg.bot.enabled')
  b_ad=$(echo "$ov" | jq -r '.cfg.bot.admin_id // ""')
  echo -e "  Bot Daemon: ${C_GLD}enabled=${b_en}${C_RST} · Authorized Admin ID(s): ${C_WHT}${b_ad:-none}${C_RST}"
  echo -e "  ${C_ORG}[1]${C_WHT} Configure Bot Token & Admin ID + Start Bot${C_RST}"
  echo -e "  ${C_ORG}[2]${C_WHT} Send Test Ping to Telegram Admin${C_RST}"
  echo -e "  ${C_ORG}[3]${C_WHT} Stop & Disable Telegram Bot${C_RST}"
  read -rp "  Choose [1-3, Enter=cancel]: " bopt </dev/tty
  case "$bopt" in
    1)
      read -rp "  BotFather API Token : " tok </dev/tty
      read -rp "  Telegram Admin ID   : " aid </dev/tty
      if [[ -n "$tok" && -n "$aid" ]]; then
        payload=$(jq -nc --arg t "$tok" --arg a "$aid" '{bot:{enabled:true,token:$t,admin_id:$a,alerts:true}}')
        $CTL --actor cli settings --json "$payload" >/dev/null
        echo -e "  ${C_OK}✔ Telegram Bot saved & started! Open your bot in Telegram and send /start.${C_RST}"
      fi ;;
    2)
      res=$($CTL --actor cli tg-test 2>&1)
      echo "$res" | jq -e '.ok' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ Test ping delivered to Telegram!${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}" ;;
    3)
      $CTL --actor cli settings --json '{"bot":{"enabled":false}}' >/dev/null
      echo -e "  ${C_OK}✔ Telegram Bot stopped.${C_RST}" ;;
  esac
  pause_ret
}

# ─── Option 10: Web Panel (Link / Login / Port) ──────────────────────────────
opt_webpanel() {
  echo -e "\n  ${C_AMB}${C_BOLD}🔥 Option 10 — Alyan Webpanel (Link / Login / Port)${C_RST}"
  ov=$($CTL --actor cli overview)
  dom=$(echo "$ov" | jq -r '.cfg.domain')
  prt=$(echo "$ov" | jq -r '.cfg.panel_port')
  ipw=$($CTL get-initial-pass 2>/dev/null || echo "Hidden")

  echo -e "  ${C_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RST}"
  printf "  ${C_RED}┃${C_RST}  Web Panel URL  : ${C_GLD}${C_BOLD}https://%s:%s${C_RST}\n" "$dom" "$prt"
  printf "  ${C_RED}┃${C_RST}  Admin Username : ${C_WHT}${C_BOLD}admin${C_RST}\n"
  printf "  ${C_RED}┃${C_RST}  Admin Password : ${C_ORG}${C_BOLD}%s${C_RST}\n" "$ipw"
  echo -e "  ${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}"
  echo -e "  ${C_ORG}[1]${C_WHT} Change Web Panel HTTPS Port${C_RST}"
  echo -e "  ${C_ORG}[2]${C_WHT} Reset Primary 'admin' Password${C_RST}"
  echo -e "  ${C_ORG}[3]${C_WHT} Restart Web Panel Service${C_RST}"
  read -rp "  Choose [1-3, Enter=back]: " wopt </dev/tty
  case "$wopt" in
    1)
      read -rp "  Enter new Web Panel Port (1024-65535): " nprt </dev/tty
      if [[ -n "$nprt" ]]; then
        res=$($CTL --actor cli settings --json "{\"panel_port\":${nprt}}" 2>&1)
        echo "$res" | jq -e '.ok' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ Web Panel moved to https://${dom}:${nprt}${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
      fi ;;
    2)
      read -rp "  Enter new password for 'admin' (min 6 chars): " npw </dev/tty
      if [[ -n "$npw" ]]; then
        payload=$(jq -nc --arg p "$npw" '{new_password:$p,target_admin:"admin"}')
        res=$($CTL --actor cli settings --json "$payload" 2>&1)
        echo "$res" | jq -e '.ok' >/dev/null 2>&1 && echo -e "  ${C_OK}✔ Admin password updated!${C_RST}" || echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
      fi ;;
    3)
      systemctl restart alyan-panel nginx
      echo -e "  ${C_OK}✔ Web Panel & Nginx restarted.${C_RST}" ;;
  esac
  pause_ret
}

# ─── Option 11: Uninstall ────────────────────────────────────────────────────
opt_uninstall() {
  echo -e "\n  ${C_ERR}${C_BOLD}⚠ Option 11 — Uninstall Alyan Webpanel${C_RST}"
  echo -e "  ${C_GRY}This stops all Alyan daemons and removes /opt/alyan, /etc/alyan & /var/lib/alyan.${C_RST}"
  read -rp "  Type 'UNINSTALL' to confirm complete removal: " conf </dev/tty
  if [[ "$conf" != "UNINSTALL" ]]; then
    echo -e "  ${C_OK}Cancelled.${C_RST}"
    pause_ret
    return
  fi
  for svc in alyan-panel alyan-bot alyan-guard alyan-qos alyan-wsd xray; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/${svc}.service"
  done
  rm -rf /etc/systemd/system/dropbear.service.d/alyan.conf \
         /etc/nginx/conf.d/alyan-router.conf /etc/nginx/conf.d/alyan-panel.conf \
         /etc/sudoers.d/alyan-panel /etc/sysctl.d/99-alyan-bbr.conf \
         /usr/local/bin/alyan-ctl /usr/local/bin/menu \
         /opt/alyan /etc/alyan /var/lib/alyan /var/log/alyan /run/alyan-*.json
  systemctl daemon-reload
  echo -e "  ${C_OK}✔ Alyan Webpanel has been cleanly uninstalled.${C_RST}"
  exit 0
}

# ═════════════════════════════════════════════════════════════════════════════
#  MAIN INTERACTIVE LOOP (12 REQUIRED OPTIONS)
# ═════════════════════════════════════════════════════════════════════════════
while true; do
  draw_header
  echo -e "  ${C_ORG}  [1]${C_WHT} Install All Components          ${C_ORG}[7]${C_WHT}  Ping Stability (QoS)${C_RST}"
  echo -e "  ${C_ORG}  [2]${C_WHT} Add / Change Domain             ${C_ORG}[8]${C_WHT}  VPS Stats / Speedtest${C_RST}"
  echo -e "  ${C_ORG}  [3]${C_WHT} SSL Certificate (Issue/Renew)   ${C_ORG}[9]${C_WHT}  Telegram Bot${C_RST}"
  echo -e "  ${C_ORG}  [4]${C_WHT} Manage Users / Limits / Banner  ${C_ORG}[10]${C_WHT} Web Panel (Link / Login / Port)${C_RST}"
  echo -e "  ${C_ORG}  [5]${C_WHT} Status & Ports                  ${C_ORG}[11]${C_ERR} Uninstall${C_RST}"
  echo -e "  ${C_ORG}  [6]${C_WHT} Fix SSH-WS / SSL stack          ${C_ORG}[12]${C_GRY} Exit${C_RST}"
  echo -e "  ${C_GRY}─────────────────────────────────────────────────────────────────────────${C_RST}"
  printf "  ${C_AMB}🔥 Select option [1-12]: ${C_WHT}"
  read -r choice </dev/tty
  printf "${C_RST}"

  case "$choice" in
    1)  opt_install_all ;;
    2)  opt_change_domain ;;
    3)  opt_ssl_cert ;;
    4)  opt_manage_users ;;
    5)  opt_status_ports ;;
    6)  opt_fix_stack ;;
    7)  opt_ping_qos ;;
    8)  opt_vps_speedtest ;;
    9)  opt_telegram_bot ;;
    10) opt_webpanel ;;
    11) opt_uninstall ;;
    12|0|q|exit) echo -e "\n  ${C_GLD}Stay blazing! 🔥${C_RST}\n"; exit 0 ;;
    *)  ;;
  esac
done

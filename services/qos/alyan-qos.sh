#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Ping Stability Engine (alyan-qos.sh)
#  Eliminates bufferbloat & ping spikes on tunnel interfaces using CAKE / HTB+fq_codel
#  and applies optional per-IP bandwidth caps configured in Settings -> Ping Stability.
# ═════════════════════════════════════════════════════════════════════════════
set -uo pipefail

CONF_FILE="/etc/alyan/qos.json"
ACTION="${1:-apply}"

detect_iface() {
  local ifc=""
  if [[ -f "$CONF_FILE" ]] && command -v jq >/dev/null 2>&1; then
    ifc=$(jq -r '.iface // empty' "$CONF_FILE" 2>/dev/null || true)
  fi
  if [[ -z "$ifc" ]] || ! ip link show "$ifc" >/dev/null 2>&1; then
    ifc=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
  fi
  echo "${ifc:-eth0}"
}

IFACE="$(detect_iface)"

clear_qdisc() {
  tc qdisc del dev "$IFACE" root 2>/dev/null || true
  tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
}

if [[ "$ACTION" == "stop" || "$ACTION" == "clear" ]]; then
  clear_qdisc
  exit 0
fi

ENABLED="true"
BW_MBPS=500
PRESET="gaming"
CAPS_JSON="[]"

if [[ -f "$CONF_FILE" ]] && command -v jq >/dev/null 2>&1; then
  ENABLED=$(jq -r 'if .enabled == false then "false" else "true" end' "$CONF_FILE" 2>/dev/null || echo "true")
  BW_MBPS=$(jq -r '.bw_mbps // 500' "$CONF_FILE" 2>/dev/null || echo "500")
  PRESET=$(jq -r '.preset // "gaming"' "$CONF_FILE" 2>/dev/null || echo "gaming")
  CAPS_JSON=$(jq -c '.caps // []' "$CONF_FILE" 2>/dev/null || echo "[]")
fi

if [[ "$ENABLED" != "true" ]]; then
  clear_qdisc
  exit 0
fi

clear_qdisc

# Optimize socket queue length for low-jitter tunneling
ip link set dev "$IFACE" txqueuelen 1000 2>/dev/null || true

CAP_COUNT=0
if command -v jq >/dev/null 2>&1; then
  CAP_COUNT=$(echo "$CAPS_JSON" | jq 'length' 2>/dev/null || echo 0)
fi

# When per-IP caps exist, build HTB root + CAKE/fq_codel leaf classes so both anti-bufferbloat and IP caps work together
if (( CAP_COUNT > 0 )); then
  tc qdisc add dev "$IFACE" root handle 1: htb default 10
  tc class add dev "$IFACE" parent 1: classid 1:1 htb rate "${BW_MBPS}mbit" ceil "${BW_MBPS}mbit"
  tc class add dev "$IFACE" parent 1:1 classid 1:10 htb rate "$(( BW_MBPS * 75 / 100 ))mbit" ceil "${BW_MBPS}mbit"
  if ! tc qdisc add dev "$IFACE" parent 1:10 handle 10: cake diffserv4 nat wash 2>/dev/null; then
    tc qdisc add dev "$IFACE" parent 1:10 handle 10: fq_codel quantum 300 ecn 2>/dev/null || true
  fi

  idx=20
  while IFS= read -r item; do
    ip_addr=$(echo "$item" | jq -r '.ip // empty')
    mbps=$(echo "$item" | jq -r '.mbps // 25')
    if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$mbps" =~ ^[0-9]+$ ]]; then
      tc class add dev "$IFACE" parent 1:1 classid "1:${idx}" htb rate "${mbps}mbit" ceil "${mbps}mbit"
      tc qdisc add dev "$IFACE" parent "1:${idx}" handle "${idx}:" fq_codel quantum 300 2>/dev/null || true
      tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 u32 match ip dst "${ip_addr}/32" flowid "1:${idx}"
      tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 u32 match ip src "${ip_addr}/32" flowid "1:${idx}"
      idx=$((idx + 1))
    fi
  done < <(echo "$CAPS_JSON" | jq -c '.[]')
  exit 0
fi

# Pure low-latency queue discipline (CAKE preferred, automatic fq_codel fallback)
CAKE_OPTS="diffserv4 nat wash ack-filter rtt 35ms"
case "$PRESET" in
  balanced)   CAKE_OPTS="diffserv3 nat wash rtt 60ms" ;;
  throughput) CAKE_OPTS="besteffort nat rtt 100ms" ;;
esac

modprobe sch_cake 2>/dev/null || true
if ! tc qdisc add dev "$IFACE" root cake bandwidth "${BW_MBPS}mbit" $CAKE_OPTS 2>/dev/null; then
  tc qdisc add dev "$IFACE" root handle 1: htb default 10
  tc class add dev "$IFACE" parent 1: classid 1:10 htb rate "${BW_MBPS}mbit" ceil "${BW_MBPS}mbit"
  tc qdisc add dev "$IFACE" parent 1:10 handle 10: fq_codel quantum 300 target 5ms interval 60ms ecn
fi

exit 0

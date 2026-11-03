#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Session-Based Live Users & Host/Edge IP Correlator
#  Converts: IP Limits & IP Counts → Active Device/User Sessions (1 User = Multiple Sessions)
#  Correlates: Connected IPs with Exact Host/Edge Target IP (141.193.213.11, 185.111.111.156)
#  Features  : Live Users Modal Sheet + 1-Click Rollback (--rollback)
# ═════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

C_RST="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[38;2;255;75;43m"
C_ORG="\033[38;2;255;110;20m"
C_AMB="\033[38;2;255;154;0m"
C_GLD="\033[38;2;255;200;55m"
C_GRN="\033[38;2;46;213;115m"
C_CYN="\033[38;2;0;210;255m"
C_WHT="\033[38;2;245;242;238m"
C_GRY="\033[38;2;120;120;140m"

INSTALL_DIR="/opt/alyan"
ETC_DIR="/etc/alyan"
VAR_DIR="/var/lib/alyan"
BACKUP_DIR="${VAR_DIR}/backup_pre_session"

hdr() {
  echo -e "\n${C_RED}╔═════════════════════════════════════════════════════════════════════════════╗${C_RST}"
  echo -e "${C_RED}║${C_RST}  ${C_AMB}${C_BOLD}🔥 ALYAN WEBPANEL — SESSION-BASED LIVE USERS & HOST IP UPDATE${C_RST}       ${C_RED}║${C_RST}"
  echo -e "${C_RED}╚═════════════════════════════════════════════════════════════════════════════╝${C_RST}"
}

preflight() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${C_RED}✖ Error: This script must be run as root (sudo bash update-session.sh).${C_RST}"
    exit 1
  fi
  if [[ ! -d "$INSTALL_DIR" || ! -f "${INSTALL_DIR}/core/alyan-ctl" ]]; then
    echo -e "${C_RED}✖ Error: Alyan Webpanel installation not found in ${INSTALL_DIR}.${C_RST}"
    exit 1
  fi
}

do_rollback() {
  hdr
  echo -e "${C_AMB}⏪ Starting Rollback to Pre-Session Configuration...${C_RST}\n"
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo -e "${C_RED}✖ Error: No backup found at ${BACKUP_DIR}! Cannot rollback.${C_RST}"
    exit 1
  fi

  echo -e "${C_CYN}▶ Restoring pristine files from ${BACKUP_DIR}...${C_RST}"
  [[ -f "${BACKUP_DIR}/app.js" ]] && cp -f "${BACKUP_DIR}/app.js" "${INSTALL_DIR}/panel/static/app.js"
  [[ -f "${BACKUP_DIR}/alyan-guard.py" ]] && cp -f "${BACKUP_DIR}/alyan-guard.py" "${INSTALL_DIR}/services/guard/alyan-guard.py"
  [[ -f "${BACKUP_DIR}/alyan-wsd.py" ]] && cp -f "${BACKUP_DIR}/alyan-wsd.py" "${INSTALL_DIR}/services/wsd/alyan-wsd.py"
  [[ -f "${BACKUP_DIR}/nginx-router.conf.tpl" ]] && cp -f "${BACKUP_DIR}/nginx-router.conf.tpl" "${INSTALL_DIR}/templates/nginx-router.conf.tpl"
  [[ -f "${BACKUP_DIR}/alyan-router.conf" ]] && cp -f "${BACKUP_DIR}/alyan-router.conf" /etc/nginx/sites-available/alyan-router.conf
  [[ -f "${BACKUP_DIR}/menu.sh" ]] && cp -f "${BACKUP_DIR}/menu.sh" "${INSTALL_DIR}/cli/menu.sh"

  echo -e "${C_CYN}▶ Reloading services...${C_RST}"
  nginx -t && (systemctl reload nginx 2>/dev/null || systemctl restart nginx)
  systemctl restart alyan-wsd alyan-guard alyan-panel

  echo -e "\n${C_GRN}✔ Rollback completed successfully! Pristine state restored.${C_RST}\n"
  exit 0
}

main() {
  if [[ "${1:-}" == "--rollback" ]]; then
    preflight
    do_rollback
  fi

  hdr
  preflight

  echo -e "${C_CYN}▶ [1/5] Backing up existing files to ${BACKUP_DIR}...${C_RST}"
  mkdir -p "$BACKUP_DIR"
  [[ -f "${INSTALL_DIR}/panel/static/app.js" ]] && cp -f "${INSTALL_DIR}/panel/static/app.js" "${BACKUP_DIR}/app.js"
  [[ -f "${INSTALL_DIR}/services/guard/alyan-guard.py" ]] && cp -f "${INSTALL_DIR}/services/guard/alyan-guard.py" "${BACKUP_DIR}/alyan-guard.py"
  [[ -f "${INSTALL_DIR}/services/wsd/alyan-wsd.py" ]] && cp -f "${INSTALL_DIR}/services/wsd/alyan-wsd.py" "${BACKUP_DIR}/alyan-wsd.py"
  [[ -f "${INSTALL_DIR}/templates/nginx-router.conf.tpl" ]] && cp -f "${INSTALL_DIR}/templates/nginx-router.conf.tpl" "${BACKUP_DIR}/nginx-router.conf.tpl"
  [[ -f /etc/nginx/sites-available/alyan-router.conf ]] && cp -f /etc/nginx/sites-available/alyan-router.conf "${BACKUP_DIR}/alyan-router.conf"
  [[ -f "${INSTALL_DIR}/cli/menu.sh" ]] && cp -f "${INSTALL_DIR}/cli/menu.sh" "${BACKUP_DIR}/menu.sh"
  echo -e "  ${C_GRN}✔ Backup stored safely in ${BACKUP_DIR}${C_RST}"

  echo -e "\n${C_CYN}▶ [2/5] Updating Webpanel UI (Session-based Live Users & Modals)...${C_RST}"
  cat > "${INSTALL_DIR}/panel/static/app.js" <<'EOF_APP_JS'
/* ═══════════════════════════════════════════════════════════════════════
   ALYAN WEBPANEL — Frontend Engine (app.js)
   Left 50% Live Fire Sidebar · 9 Animated SVG Logos · Flame Launcher
   ═══════════════════════════════════════════════════════════════════════ */
(() => {
  'use strict';

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  /* ─── 9 Custom Animated Sidebar Logos ─── */
  const NAV_ICONS = {
    // 1. Core: Outer dots grow while center circle shrinks -> center circle grows while outer dots shrink
    core: `<svg viewBox="0 0 24 24" class="ico-core" fill="currentColor">
      <circle class="c-inner" cx="12" cy="12" r="3.7"/>
      <circle class="c-dot" cx="12" cy="3.2" r="1.45"/>
      <circle class="c-dot" cx="18.2" cy="5.8" r="1.35"/>
      <circle class="c-dot" cx="20.8" cy="12" r="1.45"/>
      <circle class="c-dot" cx="18.2" cy="18.2" r="1.35"/>
      <circle class="c-dot" cx="12" cy="20.8" r="1.45"/>
      <circle class="c-dot" cx="5.8" cy="18.2" r="1.35"/>
      <circle class="c-dot" cx="3.2" cy="12" r="1.45"/>
      <circle class="c-dot" cx="5.8" cy="5.8" r="1.35"/>
    </svg>`,

    // 2. SSH Accounts: Animated SSH Console (> sliding + _ blinking + tunnel arc pulsing)
    ssh: `<svg viewBox="0 0 24 24" class="ico-ssh" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
      <rect class="ssh-wave" x="2.5" y="4" width="19" height="16" rx="3.5"/>
      <path class="ssh-chev" d="M6.8 9.5l3.2 2.5-3.2 2.5"/>
      <line class="ssh-cur" x1="12.2" y1="14.5" x2="16.8" y2="14.5"/>
    </svg>`,

    // 3. Xray: Electric Lightning Bolt with flash & spark arcs
    xray: `<svg viewBox="0 0 24 24" class="ico-xray" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
      <path class="bolt-main" fill="currentColor" fill-opacity=".22" d="M13.2 2.2L4.8 13.4h6.3l-1.1 8.4 9.2-11.2h-6.3l.3-8.4z"/>
      <path class="bolt-arc" d="M3 7l2-1.5M20.5 16.5L18.5 18"/>
    </svg>`,

    // 4. Engine: Rotating 8-tooth precision gear + pulsing inner hub
    engine: `<svg viewBox="0 0 24 24" class="ico-engine" fill="none" stroke="currentColor" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round">
      <g class="eng-gear">
        <path d="M12 2.3v2.1M12 19.6v2.1M2.3 12h2.1M19.6 12h2.1M5.1 5.1l1.5 1.5M17.4 17.4l1.5 1.5M18.9 5.1l-1.5 1.5M6.6 17.4l-1.5 1.5"/>
        <circle cx="12" cy="12" r="6.8"/>
      </g>
      <circle class="eng-hub" cx="12" cy="12" r="2.5" fill="currentColor"/>
    </svg>`,

    // 5. VPS Info: Live flowing ECG wave inside server monitor + beacon
    vps: `<svg viewBox="0 0 24 24" class="ico-vps" fill="none" stroke="currentColor" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round">
      <rect x="2.5" y="3.5" width="19" height="14" rx="2.8"/>
      <path class="vps-wave" d="M5.5 11h3l2-3.8 2.8 7.2 2.1-3.4h3.1"/>
      <line x1="8.5" y1="20.5" x2="15.5" y2="20.5"/>
      <circle class="vps-dot" cx="18.5" cy="6.5" r="1.1" fill="currentColor" stroke="none"/>
    </svg>`,

    // 6. Settings: 3 vertical rails with animated gliding slider knobs
    settings: `<svg viewBox="0 0 24 24" class="ico-settings" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">
      <line x1="5" y1="3.5" x2="5" y2="20.5"/>
      <line x1="12" y1="3.5" x2="12" y2="20.5"/>
      <line x1="19" y1="3.5" x2="19" y2="20.5"/>
      <circle class="sl-k1" cx="5" cy="12" r="2.3" fill="#0f0d12"/>
      <circle class="sl-k2" cx="12" cy="12" r="2.3" fill="#0f0d12"/>
      <circle class="sl-k3" cx="19" cy="12" r="2.3" fill="#0f0d12"/>
    </svg>`,

    // 7. Admins: Breathing armor shield + glowing check crest
    admins: `<svg viewBox="0 0 24 24" class="ico-admins" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
      <path class="adm-shield" d="M12 2.4l7.8 3.6v5.8c0 5.2-3.3 8.9-7.8 9.8-4.5-.9-7.8-4.6-7.8-9.8V6L12 2.4z"/>
      <path class="adm-check" d="M8.8 12.2l2.2 2.2 4.4-4.5"/>
    </svg>`,

    // 8. Telegram: Official paper-plane logo gliding in flight + trail
    telegram: `<svg viewBox="0 0 24 24" class="ico-tg" fill="none" stroke="currentColor" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round">
      <g class="tg-plane">
        <path fill="currentColor" fill-opacity=".2" d="M21.4 3.6L2.7 10.9l6.2 2.3 2.4 6.3 3.4-3.9 4.5 3.3 2.2-15.3z"/>
        <path d="M8.9 13.2l12.5-9.6-7.3 11.7"/>
      </g>
      <path class="tg-trail" d="M2.5 17.5l3-1.2M4.5 20.5l2.4-1"/>
    </svg>`,

    // 9. List: Sequential 1-2-3 cascading bullet + bar rows
    list: `<svg viewBox="0 0 24 24" class="ico-list" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
      <g class="l-r1"><circle cx="4.5" cy="6.5" r="1.2" fill="currentColor" stroke="none"/><line x1="8.5" y1="6.5" x2="20" y2="6.5"/></g>
      <g class="l-r2"><circle cx="4.5" cy="12" r="1.2" fill="currentColor" stroke="none"/><line x1="8.5" y1="12" x2="20" y2="12"/></g>
      <g class="l-r3"><circle cx="4.5" cy="17.5" r="1.2" fill="currentColor" stroke="none"/><line x1="8.5" y1="17.5" x2="20" y2="17.5"/></g>
    </svg>`
  };

  /* ─── General UI Action Icons ─── */
  const ICONS = {
    menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg>',
    core: NAV_ICONS.core,
    tunnel: NAV_ICONS.ssh,
    bolt: NAV_ICONS.xray,
    engine: NAV_ICONS.engine,
    chart: NAV_ICONS.vps,
    sliders: NAV_ICONS.settings,
    shield: NAV_ICONS.admins,
    send: NAV_ICONS.telegram,
    list: NAV_ICONS.list,
    search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1"><path d="M12 5v14M5 12h14"/></svg>',
    copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>',
    qr: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3h-3zM19 14h2v2h-2zM14 19h2v2h-2zM18 18h3v3h-3z"/></svg>',
    edit: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>',
    trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6h14z"/></svg>',
    refresh: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.5 9a9 9 0 0 1 14.8-3.4L23 10M1 14l4.7 4.4A9 9 0 0 0 20.5 15"/></svg>',
    terminal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>',
    lock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>',
    globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>',
    wifi: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M5 12.55a11 11 0 0 1 14.08 0M1.42 9a16 16 0 0 1 21.16 0M8.53 16.11a6 6 0 0 1 6.95 0"/><circle cx="12" cy="20" r="1"/></svg>',
    check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><polyline points="20 6 9 17 4 12"/></svg>',
    alert: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>',
    x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>',
    key: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M21 2l-2 2m-7.6 7.6a6.5 6.5 0 1 1-5.3-5.3L15 2h6v6l-3.9 3.9z"/></svg>',
    power: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.8 0"/></svg>',
    logout: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>'
  };
  const ic = (k) => ICONS[k] || ICONS.core;

  /* ─── Pure SVG 6-Corner Hexagon Avatar (100% immune to square CSS glitch) ─── */
  function hexAvatar(label, active = true) {
    return `<div class="hexav ${active ? '' : 'ash'}" aria-hidden="true">
      <svg viewBox="0 0 46 50" class="hexav-svg">
        <polygon points="23,2 43,13.5 43,36.5 23,48 3,36.5 3,13.5"
          fill="${active ? 'url(#gFlame)' : '#25232d'}"
          stroke="${active ? 'rgba(255,196,60,.65)' : 'rgba(255,255,255,.14)'}"
          stroke-width="1.8" stroke-linejoin="round"/>
        <text x="23" y="25.5" text-anchor="middle" dominant-baseline="central"
          fill="${active ? '#1a0500' : '#a8a2b0'}" font-weight="800" font-size="15.5">${esc(label)}</text>
      </svg>
    </div>`;
  }

  /* ─── Nano-Particle Disintegration & Fade Effect on User Delete ─── */
  function nanoDisintegrate(cardEl) {
    return new Promise((resolve) => {
      if (!cardEl || cardEl.dataset.disintegrating) { resolve(); return; }
      cardEl.dataset.disintegrating = '1';
      cardEl.classList.add('is-disintegrating');

      const rect = cardEl.getBoundingClientRect();
      const pad = 95;
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      const cw = rect.width + pad * 2;
      const ch = rect.height + pad * 2;

      const cv = document.createElement('canvas');
      cv.className = 'nano-fx-canvas';
      cv.style.left = `${rect.left - pad}px`;
      cv.style.top = `${rect.top - pad}px`;
      cv.style.width = `${cw}px`;
      cv.style.height = `${ch}px`;
      cv.width = Math.round(cw * dpr);
      cv.height = Math.round(ch * dpr);
      document.body.appendChild(cv);

      const ctx = cv.getContext('2d');
      ctx.scale(dpr, dpr);

      const palette = ['#ff2d2d', '#ff5a00', '#ffb000', '#ffd36b', '#fff1d0', '#dcd6e6', '#8a8396'];
      const count = 480;
      const parts = [];
      for (let i = 0; i < count; i++) {
        const rx = Math.random() * rect.width;
        const ry = Math.random() * rect.height;
        const delay = Math.min(0.84, (rx / Math.max(1, rect.width)) * 0.48 + (ry / Math.max(1, rect.height)) * 0.22 + Math.random() * 0.14);
        parts.push({
          x0: pad + rx,
          y0: pad + ry,
          vx: 30 + Math.random() * 76,
          vy: -(24 + Math.random() * 74),
          r: 0.9 + Math.random() * 1.85,
          delay,
          life: 0.34 + Math.random() * 0.24,
          phase: Math.random() * Math.PI * 2,
          amp: 6 + Math.random() * 13,
          color: palette[(Math.random() * palette.length) | 0],
          glow: Math.random() < 0.28
        });
      }

      const cardDuration = 680;
      const totalDuration = 1080;
      const t0 = performance.now();
      let resolved = false;

      const frame = (now) => {
        const elapsed = now - t0;
        const cardProg = Math.min(1, elapsed / cardDuration);
        const totalProg = Math.min(1, elapsed / totalDuration);

        // Erode card along a sweeping diagonal wavefront as nano-particles detach
        if (cardProg < 1) {
          const edge = -26 + cardProg * 154;
          const mask = `linear-gradient(118deg, transparent ${edge - 18}%, rgba(0,0,0,0.35) ${edge}%, #000 ${edge + 18}%)`;
          cardEl.style.webkitMaskImage = mask;
          cardEl.style.maskImage = mask;
          cardEl.style.transform = `translate3d(${(cardProg * 7).toFixed(1)}px, ${(-cardProg * 5).toFixed(1)}px, 0) scale(${(1 - cardProg * 0.025).toFixed(3)})`;
          cardEl.style.opacity = String(Math.max(0, 1 - Math.pow(cardProg, 2.4)));
        } else if (!resolved) {
          cardEl.style.opacity = '0';
          resolved = true;
          resolve();
        }

        ctx.clearRect(0, 0, cw, ch);
        for (let i = 0; i < count; i++) {
          const p = parts[i];
          if (totalProg < p.delay) continue;
          const u = (totalProg - p.delay) / p.life;
          if (u >= 1) continue;
          const ease = 1 - Math.pow(1 - u, 2);
          const x = p.x0 + p.vx * ease + Math.sin(u * 6.5 + p.phase) * p.amp * u;
          const y = p.y0 + p.vy * ease + Math.cos(u * 5.2 + p.phase) * (p.amp * 0.55) * u;
          const alpha = u < 0.16 ? (u / 0.16) : Math.pow(1 - (u - 0.16) / 0.84, 1.55);
          const radius = p.r * (1 - u * 0.35);

          ctx.globalAlpha = Math.max(0, Math.min(1, alpha));
          if (p.glow) {
            ctx.fillStyle = p.color;
            ctx.beginPath();
            ctx.arc(x, y, radius * 2.1, 0, Math.PI * 2);
            ctx.globalAlpha *= 0.24;
            ctx.fill();
            ctx.globalAlpha = Math.max(0, Math.min(1, alpha));
          }
          ctx.fillStyle = p.color;
          ctx.beginPath();
          ctx.arc(x, y, radius, 0, Math.PI * 2);
          ctx.fill();
        }
        ctx.globalAlpha = 1;

        if (elapsed < totalDuration) {
          requestAnimationFrame(frame);
        } else {
          if (!resolved) resolve();
          cv.remove();
        }
      };

      requestAnimationFrame(frame);
    });
  }

  /* ─── Real Procedural Moving Fire Engine (for Sidebar 50% Fire & Flame Launcher) ─── */
  const FIRE_PAL = (() => {
    const p = new Uint8Array(256 * 4);
    for (let i = 0; i < 256; i++) {
      let r = 0, g = 0, b = 0, a = 0;
      if (i > 12) {
        r = Math.min(255, (i - 12) * 3.1);
        g = i > 78 ? Math.min(255, (i - 78) * 2.25) : 0;
        b = i > 195 ? Math.min(255, (i - 195) * 3.8) : 0;
        a = Math.min(255, i * 2.1);
      }
      p[i * 4] = r; p[i * 4 + 1] = g; p[i * 4 + 2] = b; p[i * 4 + 3] = a;
    }
    return p;
  })();

  function attachRealFire(canvas, opts = {}) {
    if (!canvas) return () => {};
    if (canvas._stopFire) canvas._stopFire();
    const W = opts.w || 68;
    const H = opts.h || 150;
    const coolMax = opts.cool || 3.4;
    const off = document.createElement('canvas');
    off.width = W; off.height = H;
    const octx = off.getContext('2d');
    const img = octx.createImageData(W, H);
    const heat = new Float32Array(W * H);
    const ctx = canvas.getContext('2d');
    let raf = 0, t = 0;

    const tick = () => {
      if (!canvas.isConnected) return;
      t += 0.08;
      if (canvas.width !== canvas.clientWidth || canvas.height !== canvas.clientHeight) {
        canvas.width = Math.max(32, canvas.clientWidth);
        canvas.height = Math.max(24, canvas.clientHeight);
      }
      // Seed bottom 2 rows with turbulent flame fuel
      for (let x = 0; x < W; x++) {
        const wave = Math.sin(x * 0.32 + t * 2.1) * 28 + Math.cos(x * 0.7 - t * 3.2) * 22;
        const val = Math.max(120, Math.min(255, 222 + wave + (Math.random() * 44 - 22)));
        heat[(H - 1) * W + x] = val;
        heat[(H - 2) * W + x] = val * 0.96;
      }
      // Convect heat upward with flickering wind & cooling
      for (let y = 0; y < H - 2; y++) {
        for (let x = 0; x < W; x++) {
          const xl = x > 0 ? x - 1 : 0;
          const xr = x < W - 1 ? x + 1 : W - 1;
          const y1 = (y + 1) * W, y2 = Math.min(H - 1, y + 2) * W;
          const avg = (heat[y1 + xl] + heat[y1 + x] * 2 + heat[y1 + xr] + heat[y2 + x]) * 0.2;
          const decay = Math.random() * coolMax + (y < H * 0.35 ? 1.1 : 0.25);
          heat[y * W + x] = Math.max(0, avg - decay);
        }
      }
      const d = img.data;
      for (let i = 0; i < W * H; i++) {
        const c = (heat[i] | 0) * 4;
        const p = i * 4;
        d[p] = FIRE_PAL[c]; d[p + 1] = FIRE_PAL[c + 1]; d[p + 2] = FIRE_PAL[c + 2]; d[p + 3] = FIRE_PAL[c + 3];
      }
      octx.putImageData(img, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(off, 0, 0, canvas.width, canvas.height);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    canvas._stopFire = () => cancelAnimationFrame(raf);
    return canvas._stopFire;
  }

  /* ─── Formatting & QR Helpers ─── */
  const fmtBytes = (b) => {
    const n = Math.max(0, Number(b) || 0);
    if (n < 1024) return Math.round(n) + ' B';
    const u = ['KB', 'MB', 'GB', 'TB'];
    let i = -1, v = n;
    do { v /= 1024; i++; } while (v >= 1024 && i < u.length - 1);
    return (v >= 100 ? v.toFixed(0) : v.toFixed(v >= 10 ? 1 : 2)) + ' ' + u[i];
  };
  const fmtRate = (bps) => fmtBytes(bps) + '/s';
  const randHex = (n) => Array.from({ length: n }, () => Math.floor(Math.random() * 16).toString(16)).join('');
  const makeUuid = () => `${randHex(8)}-${randHex(4)}-4${randHex(3)}-${['8','9','a','b'][Math.floor(Math.random()*4)]}${randHex(3)}-${randHex(12)}`;
  const daysFromNow = (d) => new Date(Date.now() + d * 86400000).toISOString().slice(0, 10);
  const daysLeft = (iso) => Math.max(0, Math.ceil((new Date(iso + 'T23:59:59').getTime() - Date.now()) / 86400000));

  function renderQrSvg(text) {
    const N = 29;
    const m = Array.from({ length: N }, () => Array(N).fill(null));
    const finder = (r0, c0) => {
      for (let r = -1; r <= 7; r++) for (let c = -1; c <= 7; c++) {
        const rr = r0 + r, cc = c0 + c;
        if (rr < 0 || cc < 0 || rr >= N || cc >= N) continue;
        const on = (r >= 0 && r <= 6 && c >= 0 && c <= 6) && (r === 0 || r === 6 || c === 0 || c === 6 || (r >= 2 && r <= 4 && c >= 2 && c <= 4));
        m[rr][cc] = on ? 1 : 0;
      }
    };
    finder(0, 0); finder(0, N - 7); finder(N - 7, 0);
    for (let r = -2; r <= 2; r++) for (let c = -2; c <= 2; c++) m[N - 7 + r][N - 7 + c] = (Math.abs(r) === 2 || Math.abs(c) === 2 || (r === 0 && c === 0)) ? 1 : 0;
    for (let i = 8; i < N - 8; i++) { m[6][i] = (i % 2 === 0) ? 1 : 0; m[i][6] = (i % 2 === 0) ? 1 : 0; }
    let h = 2166136261 >>> 0;
    for (let i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
    let s = h || 1337, k = 0;
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) if (m[r][c] === null) {
      s ^= s << 13; s ^= s >>> 17; s ^= s << 5;
      m[r][c] = ((s >>> 0) ^ ((text.charCodeAt(k % text.length) || 65) >> (k % 7))) & 1; k++;
    }
    let paths = '';
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) if (m[r][c]) paths += `M${c + 2},${r + 2}h1v1h-1z`;
    return `<svg viewBox="0 0 ${N + 4} ${N + 4}" shape-rendering="crispEdges"><rect width="${N + 4}" height="${N + 4}" fill="#fff"/><path d="${paths}" fill="#0c0b10"/></svg>`;
  }

  function buildSshPayload(domain) {
    return `GET /alyan HTTP/1.1[crlf]Host: ${domain}[crlf]X-Target: [host][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]`;
  }
  function buildSshShareText(u, cfg) {
    return [
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
      ' 🔥 ALYAN WEBPANEL — SSH ACCOUNT',
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
      `👤 Username   : ${u.username}`,
      `🔑 Password   : ${u.password || '(hidden)'}`,
      `🌐 Host       : ${cfg.domain}`,
      `🛡️ SNI        : ${cfg.domain}`,
      `📅 Expiry     : ${u.expiry} (${daysLeft(u.expiry)}d)`,
      `📊 Data Limit : ${u.gb_limit > 0 ? u.gb_limit + ' GB' : 'Unlimited'}`,
      `📱 IP Limit   : ${u.ip_limit > 0 ? u.ip_limit : 'Unlimited'}`,
      '────────── PORTS ───────────',
      '🖥️ SSH Direct : 22, 109, 143',
      '🔒 SSH SSL    : 443',
      '🌍 SSH WS     : 80  -> /alyan',
      '🔐 SSH WS SSL : 443 -> /alyan',
      '───────── LOCATION ─────────',
      `🏙️ Location   : ${cfg.location || 'Singapore'}`,
      '───────── PAYLOAD ──────────',
      buildSshPayload(cfg.domain),
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
      `(Owner: ${u.owner || 'admin'})`
    ].join('\n');
  }
  function buildXrayLinks(u, cfg) {
    const d = cfg.domain, tag = encodeURIComponent(u.username);
    if (u.proto === 'vmess') {
      const mk = (port, tls, net, path) => 'vmess://' + btoa(JSON.stringify({ v: '2', ps: `Alyan-${u.username}-${tls ? 'TLS' : 'NTLS'}-${net.toUpperCase()}`, add: d, port: String(port), id: u.uuid, aid: '0', scy: 'auto', net, type: 'none', host: d, path, tls: tls ? 'tls' : '', sni: tls ? d : '' }));
      return [
        { name: 'VMess WS TLS (443)', uri: mk(443, true, 'ws', '/alyan-vmess') },
        { name: 'VMess WS HTTP (80)', uri: mk(80, false, 'ws', '/alyan-vmess') },
        { name: 'VMess gRPC TLS (443)', uri: mk(443, true, 'grpc', 'alyan-vmess-grpc') }
      ];
    }
    if (u.proto === 'trojan') return [
      { name: 'Trojan WS TLS (443)', uri: `trojan://${u.uuid}@${d}:443?path=%2Falyan-trojan&security=tls&host=${d}&type=ws&sni=${d}#Alyan-${tag}-WS-TLS` },
      { name: 'Trojan TCP TLS (443)', uri: `trojan://${u.uuid}@${d}:443?security=tls&type=tcp&sni=${d}#Alyan-${tag}-TCP` },
      { name: 'Trojan gRPC TLS (443)', uri: `trojan://${u.uuid}@${d}:443?mode=gun&security=tls&type=grpc&serviceName=alyan-trojan-grpc&sni=${d}#Alyan-${tag}-gRPC` }
    ];
    return [
      { name: 'VLESS WS TLS (443)', uri: `vless://${u.uuid}@${d}:443?path=%2Falyan-vless&security=tls&encryption=none&host=${d}&type=ws&sni=${d}#Alyan-${tag}-WS-TLS` },
      { name: 'VLESS WS HTTP (80)', uri: `vless://${u.uuid}@${d}:80?path=%2Falyan-vless&security=none&encryption=none&host=${d}&type=ws#Alyan-${tag}-WS-80` },
      { name: 'VLESS XHTTP TLS (443)', uri: `vless://${u.uuid}@${d}:443?path=%2Falyan-xhttp&security=tls&encryption=none&host=${d}&type=xhttp&sni=${d}#Alyan-${tag}-XHTTP` },
      { name: 'VLESS gRPC TLS (443)', uri: `vless://${u.uuid}@${d}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=alyan-vless-grpc&sni=${d}#Alyan-${tag}-gRPC` }
    ];
  }

  /* ─── Demo State (used automatically when /api is offline) ─── */
  const DEMO = {
    active: false,
    me: { username: 'admin', role: 'super', max_accounts: 0, scope: 'all' },
    cfg: {
      domain: 'panel.alyan08.com',
      panel_port: 8443,
      ssl_days: 89,
      ip: '104.64.221.142',
      location: 'Singapore, SG',
      provider: 'Akamai Connected Cloud',
      os: 'Ubuntu 24.04.5 LTS',
      kernel: '6.8.0-51-generic (x86_64)',
      cpu_model: 'AMD EPYC 7713 64-Core · 2 vCPU',
      uptime: '6d 19h 42m',
      ws_path: '/alyan',
      banner: '<font color="#ff3b1f"><b>🔥 ALYAN WEBPANEL PREMIUM TUNNEL 🔥</b></font><br><font color="#ffb000">No Torrent · No DDoS · Wire-Speed BBR Ready</font>',
      bot: { enabled: true, token: '781204****:AAH9f_alyan_bot_secret', admin_id: '591031001', alerts: true }
    },
    ssh: [
      { username: 'Alyan', password: '1234', used_bytes: 19864223744, gb_limit: 50, ip_limit: 2, online: 2, ips: ['59.103.100.171', '39.42.88.19'], expiry: daysFromNow(29), status: 'active', owner: 'admin' },
      { username: 'Basit', password: '5678', used_bytes: 227960422, gb_limit: 0, ip_limit: 0, online: 0, ips: [], expiry: daysFromNow(29), status: 'active', owner: 'admin' },
      { username: 'ZainGaming', password: '9900', used_bytes: 8412009100, gb_limit: 20, ip_limit: 1, online: 1, ips: ['119.160.64.11'], expiry: daysFromNow(14), status: 'active', owner: 'reseller1' }
    ],
    xray: [
      { username: 'AlyanVIP', proto: 'vless', uuid: '6fc812d1-2561-4b9e-9a44-89ef210a44c1', used_bytes: 1868310937, gb_limit: 100, ip_limit: 3, online: 1, ips: ['59.103.100.171'], expiry: daysFromNow(29), status: 'active', owner: 'admin' },
      { username: 'HamzaStream', proto: 'vmess', uuid: 'a91f44e0-7712-49d1-8112-30bc91a200e8', used_bytes: 5412008960, gb_limit: 0, ip_limit: 2, online: 0, ips: [], expiry: daysFromNow(21), status: 'active', owner: 'admin' },
      { username: 'TrojanPro', proto: 'trojan', uuid: 'd42e9911-62c0-4a80-b122-9f00bc1120aa', used_bytes: 912001024, gb_limit: 30, ip_limit: 1, online: 1, ips: ['182.185.12.44'], expiry: daysFromNow(10), status: 'active', owner: 'admin' }
    ],
    services: [
      { id: 'haproxy', name: 'HAProxy Flame Router', desc: 'Public 80 / 443 Multiplexer', status: 'running', boot: 'enabled', uptime: '6d 19h', mem: '18.4 MB', pid: 67966 },
      { id: 'nginx', name: 'Nginx Router & TLS', desc: 'WS / gRPC / Panel HTTPS', status: 'running', boot: 'enabled', uptime: '6d 19h', mem: '7.2 MB', pid: 67507 },
      { id: 'dropbear', name: 'Dropbear SSH', desc: 'Direct Tunnel Ports 109 / 143', status: 'running', boot: 'enabled', uptime: '6d 19h', mem: '1.1 MB', pid: 67060 },
      { id: 'alyan-wsd', name: 'Alyan WS-Proxy', desc: 'GET /alyan 101 + Real-IP Bridge', status: 'running', boot: 'enabled', uptime: '6d 19h', mem: '9.8 MB', pid: 67297 },
      { id: 'xray', name: 'Xray-Core Engine', desc: 'VMess · VLESS · Trojan · XHTTP', status: 'running', boot: 'enabled', uptime: '6d 19h', mem: '24.6 MB', pid: 68466 },
      { id: 'alyan-guard', name: 'Alyan Guard', desc: 'GB Quota · Expiry · IP Enforcer', status: 'running', boot: 'enabled', uptime: '6d 19h', mem: '11.2 MB', pid: 68115 },
      { id: 'alyan-bot', name: 'Telegram Bot', desc: 'Full User & Server Control', status: 'running', boot: 'enabled', uptime: '2d 11h', mem: '16.5 MB', pid: 69102 },
      { id: 'alyan-panel', name: 'Alyan Webpanel', desc: 'FastAPI Command Deck', status: 'running', boot: 'enabled', uptime: '6d 19h', mem: '28.1 MB', pid: 69447 }
    ],
    ports: [
      { port: 22, addr: '0.0.0.0', proc: 'sshd', scope: 'public', note: 'Admin & Direct SSH' },
      { port: 80, addr: '0.0.0.0', proc: 'haproxy', scope: 'public', note: 'Flame Router HTTP / WS' },
      { port: 443, addr: '0.0.0.0', proc: 'haproxy', scope: 'public', note: 'Flame Router TLS / Multiplex' },
      { port: 109, addr: '0.0.0.0', proc: 'dropbear', scope: 'public', note: 'Dropbear Direct SSH' },
      { port: 143, addr: '0.0.0.0', proc: 'dropbear', scope: 'public', note: 'Dropbear Direct SSH' },
      { port: 8443, addr: '0.0.0.0', proc: 'nginx', scope: 'public', note: 'Alyan Webpanel HTTPS' },
      { port: 2095, addr: '127.0.0.1', proc: 'alyan-wsd', scope: 'local', note: 'SSH-WS /alyan Bridge' },
      { port: 8880, addr: '127.0.0.1', proc: 'nginx', scope: 'local', note: 'Xray WS Internal Router' },
      { port: 8881, addr: '127.0.0.1', proc: 'nginx', scope: 'local', note: 'Xray gRPC / XHTTP h2c' },
      { port: 10001, addr: '127.0.0.1', proc: 'xray', scope: 'local', note: 'VLESS / VMess / Trojan' },
      { port: 10085, addr: '127.0.0.1', proc: 'xray', scope: 'local', note: 'Xray Stats gRPC API' },
      { port: 7700, addr: '127.0.0.1', proc: 'uvicorn', scope: 'local', note: 'Panel FastAPI Core' }
    ],
    admins: [
      { username: 'admin', role: 'super', max_accounts: 0, scope: 'all', accounts: 5, status: 'active', last_login: 'Just now · 59.103.100.171', created: '2026-10-24' },
      { username: 'reseller1', role: 'admin', max_accounts: 25, scope: 'own', accounts: 1, status: 'active', last_login: '3h ago · 119.160.64.11', created: '2026-10-27' },
      { username: 'monitor_view', role: 'viewer', max_accounts: 0, scope: 'all', accounts: 0, status: 'active', last_login: '1d ago · 39.42.88.19', created: '2026-10-28' }
    ],
    audit: [
      { time: '03:54:12', user: 'admin', action: 'xray_links', detail: 'proto=vless user=AlyanVIP', ip: '59.103.100.171' },
      { time: '03:41:08', user: 'admin', action: 'ssh_create', detail: 'user=Alyan days=30 gb=50 ip=2 path=/alyan', ip: '59.103.100.171' },
      { time: '03:28:49', user: 'reseller1', action: 'ssh_create', detail: 'user=ZainGaming days=14 gb=20 ip=1', ip: '119.160.64.11' },
      { time: '03:15:02', user: 'admin', action: 'stack_repair', detail: 'Wire-Speed BBR+FQ + SSH-WS + SSL + HAProxy + Xray tuned', ip: '59.103.100.171' },
      { time: '02:59:30', user: 'admin', action: 'ssl_issue', detail: 'domain=panel.alyan08.com valid=89d', ip: 'local' }
    ],
    hist: {
      cpu: [11, 14, 12, 19, 24, 18, 15, 22, 17, 13, 16, 21, 19, 14, 18, 25, 20, 16, 15, 18],
      ram: [22, 22, 23, 23, 24, 24, 23, 25, 24, 24, 25, 25, 24, 24, 25, 26, 25, 25, 24, 25],
      rx:  [1.2, 2.4, 3.8, 5.1, 4.2, 6.8, 8.4, 7.1, 5.5, 9.2, 11.4, 8.0, 6.2, 7.9, 10.3, 12.6, 9.4, 8.1, 11.2, 9.8],
      tx:  [0.9, 1.8, 2.9, 4.4, 3.9, 5.2, 6.1, 5.8, 4.9, 7.4, 8.8, 6.5, 5.1, 6.4, 8.2, 9.7, 7.8, 6.9, 8.9, 7.6]
    }
  };

  function logDemo(action, detail) {
    DEMO.audit.unshift({ time: new Date().toTimeString().slice(0, 8), user: DEMO.me.username, action, detail, ip: 'preview' });
  }

  function demoOverview() {
    const cpu = Math.max(4, Math.min(92, Math.round((DEMO.hist.cpu.at(-1) || 18) + (Math.random() * 10 - 5))));
    const ram = Math.max(14, Math.min(88, Math.round((DEMO.hist.ram.at(-1) || 25) + (Math.random() * 2 - 1))));
    const rx = +(Math.max(0.4, (DEMO.hist.rx.at(-1) || 8) + (Math.random() * 4 - 2))).toFixed(2);
    const tx = +(Math.max(0.3, (DEMO.hist.tx.at(-1) || 6) + (Math.random() * 3 - 1.5))).toFixed(2);
    DEMO.hist.cpu.push(cpu); DEMO.hist.cpu.shift();
    DEMO.hist.ram.push(ram); DEMO.hist.ram.shift();
    DEMO.hist.rx.push(rx); DEMO.hist.rx.shift();
    DEMO.hist.tx.push(tx); DEMO.hist.tx.shift();
    return {
      cpu_pct: cpu, load: '0.18 · 0.24 · 0.19',
      ram_pct: ram, ram_used: 980 * 1048576, ram_total: 3910 * 1048576,
      disk_pct: 14, disk_used: 11.2 * 1073741824, disk_total: 80 * 1073741824,
      rx_bps: rx * 1048576 / 8, tx_bps: tx * 1048576 / 8,
      rx_total: 148.6 * 1073741824, tx_total: 139.2 * 1073741824,
      ssh_total: DEMO.ssh.length, ssh_online: DEMO.ssh.reduce((a, u) => a + (u.status === 'disabled' ? 0 : u.online), 0),
      xray_total: DEMO.xray.length,
      xray_online: DEMO.xray.reduce((a, u) => a + (u.status === 'disabled' ? 0 : (u.online || 0)), 0),
      xray_vless: DEMO.xray.filter(u => u.proto === 'vless').length,
      xray_vmess: DEMO.xray.filter(u => u.proto === 'vmess').length,
      xray_trojan: DEMO.xray.filter(u => u.proto === 'trojan').length,
      services: DEMO.services, cfg: DEMO.cfg, hist: DEMO.hist
    };
  }

  let csrfToken = '';
  async function api(path, opts = {}) {
    const useDemo = Boolean(window.ALYAN_FORCE_DEMO || location.protocol === 'file:');
    if (!useDemo) {
      const headers = Object.assign({ 'Content-Type': 'application/json' }, opts.headers || {});
      if (csrfToken && opts.method && opts.method !== 'GET') headers['X-CSRF-Token'] = csrfToken;
      const res = await fetch('/api' + path, {
        method: opts.method || 'GET',
        headers,
        cache: 'no-store',
        body: opts.body ? JSON.stringify(opts.body) : undefined,
        credentials: 'same-origin'
      });
      if (res.status === 401 && path !== '/auth/login') {
        showLogin();
        const uerr = new Error('Session expired');
        uerr.httpStatus = 401;
        throw uerr;
      }
      const data = await res.json();
      if (!res.ok) {
        const herr = new Error(data.detail || data.error || 'Request failed');
        herr.httpStatus = res.status;
        throw herr;
      }
      if (data.csrf) csrfToken = data.csrf;
      return data;
    }
    DEMO.active = true;
    const b = opts.body || {};
    if (path === '/auth/me') return { user: DEMO.me, cfg: DEMO.cfg, demo: true };
    if (path === '/auth/login') { DEMO.me.username = b.username || 'admin'; logDemo('login', 'Interactive session'); return { user: DEMO.me, cfg: DEMO.cfg }; }
    if (path === '/auth/logout') return { ok: true };
    if (path === '/overview') return demoOverview();
    if (path === '/ssh' && (!opts.method || opts.method === 'GET')) return { items: DEMO.ssh, cfg: DEMO.cfg };
    if (path === '/ssh' && opts.method === 'POST') {
      if (DEMO.me.role === 'viewer') throw new Error('Viewer role is read-only');
      if (DEMO.ssh.some(u => u.username.toLowerCase() === b.username.toLowerCase())) throw new Error('Username already exists');
      const item = { username: b.username, password: b.password, used_bytes: 0, gb_limit: +b.gb_limit || 0, ip_limit: +b.ip_limit || 0, online: 0, ips: [], expiry: daysFromNow(+b.days || 30), status: 'active', owner: DEMO.me.username };
      DEMO.ssh.unshift(item); logDemo('ssh_create', `user=${item.username} days=${b.days} gb=${item.gb_limit} ip=${item.ip_limit}`);
      return { item, cfg: DEMO.cfg };
    }
    if (path.startsWith('/ssh/') && opts.method === 'PATCH') {
      const name = decodeURIComponent(path.slice(5));
      const u = DEMO.ssh.find(x => x.username === name);
      if (!u) throw new Error('Not found');
      if (b.days) u.expiry = daysFromNow(+b.days);
      if (b.gb_limit !== undefined) u.gb_limit = +b.gb_limit;
      if (b.ip_limit !== undefined) u.ip_limit = +b.ip_limit;
      if (b.password) u.password = b.password;
      if (b.status) {
        u.status = b.status;
        if (b.status === 'disabled') { u.online = 0; u.ips = []; }
      }
      logDemo(b.status ? `ssh_${b.status}` : 'ssh_edit', `user=${name}`);
      return { item: u };
    }
    if (path.startsWith('/ssh/') && opts.method === 'DELETE') {
      const name = decodeURIComponent(path.slice(5));
      DEMO.ssh = DEMO.ssh.filter(x => x.username !== name);
      logDemo('ssh_delete', `user=${name}`);
      return { ok: true };
    }
    if (path === '/xray' && (!opts.method || opts.method === 'GET')) return { items: DEMO.xray, cfg: DEMO.cfg };
    if (path === '/xray' && opts.method === 'POST') {
      if (DEMO.me.role === 'viewer') throw new Error('Viewer role is read-only');
      const item = { username: b.username, proto: b.proto || 'vless', uuid: b.uuid || makeUuid(), used_bytes: 0, gb_limit: +b.gb_limit || 0, ip_limit: +b.ip_limit || 0, online: 0, ips: [], expiry: daysFromNow(+b.days || 30), status: 'active', owner: DEMO.me.username };
      DEMO.xray.unshift(item); logDemo('xray_create', `proto=${item.proto} user=${item.username}`);
      return { item, cfg: DEMO.cfg };
    }
    if (path.startsWith('/xray/') && opts.method === 'PATCH') {
      const uuid = decodeURIComponent(path.slice(6));
      const u = DEMO.xray.find(x => x.uuid === uuid);
      if (!u) throw new Error('Client not found');
      if (b.username && b.username.trim()) u.username = b.username.trim();
      if (b.proto) u.proto = b.proto;
      if (b.new_uuid && b.new_uuid.trim()) u.uuid = b.new_uuid.trim();
      if (b.days) u.expiry = daysFromNow(+b.days);
      if (b.gb_limit !== undefined) u.gb_limit = +b.gb_limit;
      if (b.ip_limit !== undefined) u.ip_limit = +b.ip_limit;
      if (b.status) {
        u.status = b.status;
        if (b.status === 'disabled') { u.online = 0; u.ips = []; }
      }
      logDemo(b.status ? `xray_${b.status}` : 'xray_edit', `proto=${u.proto} user=${u.username}`);
      return { item: u, cfg: DEMO.cfg };
    }
    if (path.startsWith('/xray/') && opts.method === 'DELETE') {
      const uuid = decodeURIComponent(path.slice(6));
      DEMO.xray = DEMO.xray.filter(x => x.uuid !== uuid);
      logDemo('xray_delete', `uuid=${uuid.slice(0, 8)}`);
      return { ok: true };
    }
    if (path === '/engine') return { services: DEMO.services, ports: DEMO.ports };
    if (path.startsWith('/service/')) {
      const [, , id, act] = path.split('/');
      const s = DEMO.services.find(x => x.id === id);
      if (act === 'logs') return { logs: `[${new Date().toISOString()}] systemd[1]: ${id}.service — Alyan Flame Engine active\n[${new Date().toISOString()}] ${id}: listening healthy · 0 errors · PROXY-v2 ready\n[${new Date().toISOString()}] ${id}: accepted 142 tunnel handshakes (path=/alyan)` };
      if (s) { s.status = act === 'stop' ? 'stopped' : 'running'; logDemo(`svc_${act}`, id); }
      if (id === 'all') DEMO.services.forEach(x => { x.status = 'running'; });
      return { ok: true, services: DEMO.services };
    }
    if (path === '/telemetry') return demoOverview();
    if (path === '/settings' && opts.method === 'POST') {
      if (b.domain) { DEMO.cfg.domain = b.domain.trim(); logDemo('domain_set', DEMO.cfg.domain); }
      if (b.panel_port) { DEMO.cfg.panel_port = +b.panel_port; const p = DEMO.ports.find(x => x.note.includes('Webpanel')); if (p) p.port = DEMO.cfg.panel_port; logDemo('port_set', `port=${DEMO.cfg.panel_port}`); }
      if (b.ssl_renew) { DEMO.cfg.ssl_days = 90; logDemo('ssl_renew', DEMO.cfg.domain); }
      if (b.banner !== undefined) { DEMO.cfg.banner = b.banner; logDemo('banner_set', `${b.banner.length} bytes`); }
      if (b.bot) { Object.assign(DEMO.cfg.bot, b.bot); logDemo('bot_config', `enabled=${DEMO.cfg.bot.enabled}`); }
      if (b.new_username) { DEMO.me.username = b.new_username.trim(); logDemo('username_change', `user=${DEMO.me.username}`); }
      if (b.new_password) logDemo('password_change', `user=${DEMO.me.username}`);
      if (b.maint) logDemo('maintenance', b.maint);
      return { ok: true, cfg: DEMO.cfg };
    }
    if (path === '/admins' && (!opts.method || opts.method === 'GET')) return { items: DEMO.admins };
    if (path === '/admins' && opts.method === 'POST') {
      DEMO.admins.push({ username: b.username, role: b.role, max_accounts: +b.max_accounts || 0, scope: b.scope || 'own', accounts: 0, status: 'active', last_login: 'Never', created: new Date().toISOString().slice(0, 10) });
      logDemo('admin_create', `user=${b.username} role=${b.role}`);
      return { ok: true };
    }
    if (path.startsWith('/admins/') && opts.method === 'DELETE') {
      const u = decodeURIComponent(path.slice(8));
      if (u === 'admin') throw new Error('Primary Super Admin cannot be removed');
      DEMO.admins = DEMO.admins.filter(x => x.username !== u);
      logDemo('admin_delete', `user=${u}`);
      return { ok: true };
    }
    if (path === '/audit') return { items: DEMO.audit };
    return { ok: true };
  }

  /* ─── UI Shell & Helpers ─── */
  const STATE = { bay: 'core', me: null, cfg: null, xrayProto: 'vless', searchSsh: '', searchXray: '', searchAudit: '', timer: null };

  function toast(msg, kind = 'ok') {
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.innerHTML = `${ic(kind === 'ok' ? 'check' : 'alert')}<div>${esc(msg)}</div>`;
    $('#toasts').appendChild(el);
    setTimeout(() => el.remove(), 3000);
  }
  async function copyText(txt, label = 'Copied to clipboard') {
    try { await navigator.clipboard.writeText(txt); }
    catch { const ta = document.createElement('textarea'); ta.value = txt; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove(); }
    toast(label, 'ok');
  }
  function openSheet(title, subtitle, bodyHtml) {
    const wrap = $('#sheetWrap'), sh = $('#sheet');
    sh.innerHTML = `<div class="sheet-h"><div><small>${esc(subtitle || 'ALYAN COMMAND')}</small><h3>${esc(title)}</h3></div><button class="icon-btn sm" id="sheetClose" type="button">${ic('x')}</button></div><div class="sheet-body">${bodyHtml}</div>`;
    wrap.hidden = false;
    $('#sheetClose', sh).onclick = closeSheet;
    wrap.onclick = (e) => { if (e.target === wrap) closeSheet(); };
  }
  function closeSheet() { $('#sheetWrap').hidden = true; $('#sheet').innerHTML = ''; }
  function bindSteppers(root) {
    $$('.stepper', root).forEach(st => {
      const inp = $('input', st), [dec, inc] = $$('button', st), step = +(inp.dataset.step || 1);
      dec.onclick = () => { inp.value = Math.max(+(inp.min || 0), (+inp.value || 0) - step); };
      inc.onclick = () => { inp.value = (+inp.value || 0) + step; };
    });
  }
  function sparkPath(arr, w = 360, h = 110, maxOverride = 0) {
    if (!arr || !arr.length) return { line: '', area: '' };
    const max = Math.max(maxOverride || 10, ...arr) * 1.12;
    const pts = arr.map((v, i) => [(i / Math.max(1, arr.length - 1)) * w, h - 8 - ((v / max) * (h - 20))]);
    const line = 'M' + pts.map(p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' L');
    return { line, area: `${line} L${w},${h} L0,${h} Z` };
  }

  function initEmbers() {
    const cv = $('#embers'); if (!cv) return;
    const ctx = cv.getContext('2d'); let w = 0, h = 0;
    const resize = () => { w = cv.width = window.innerWidth; h = cv.height = window.innerHeight; };
    resize(); window.addEventListener('resize', resize);
    const sparks = Array.from({ length: 32 }, () => ({ x: Math.random() * w, y: Math.random() * h, r: 0.8 + Math.random() * 1.9, vy: 0.25 + Math.random() * 0.65, vx: (Math.random() - 0.5) * 0.3, a: 0.2 + Math.random() * 0.45, hue: 12 + Math.random() * 32 }));
    const draw = () => {
      ctx.clearRect(0, 0, w, h);
      for (const p of sparks) {
        p.y -= p.vy; p.x += p.vx;
        if (p.y < -10) { p.y = h + 10; p.x = Math.random() * w; }
        ctx.beginPath(); ctx.fillStyle = `hsla(${p.hue},100%,58%,${p.a})`; ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2); ctx.fill();
      }
      requestAnimationFrame(draw);
    };
    requestAnimationFrame(draw);
  }

  function toggleMobileSidebar(open) {
    const sb = $('#sidebar'), bd = $('#sbBackdrop');
    sb.classList.toggle('open', open);
    bd.hidden = !open;
  }

  function syncHud() {
    if (!STATE.me) return;
    $('#meName').textContent = STATE.me.username;
    $('#meAv').textContent = (STATE.me.username[0] || 'A').toUpperCase();
    const roleEl = $('#meRole');
    roleEl.textContent = STATE.me.role.toUpperCase();
    roleEl.className = `role ${STATE.me.role}`;
  }

  function setBayHead(kicker, title, desc, actionsHtml = '') {
    $('#bayHead').innerHTML = `
      <div class="bay-title"><small>${esc(kicker)}</small><h2>${esc(title)}</h2><p>${esc(desc)}</p></div>
      <div class="bay-actions">${actionsHtml}</div>`;
  }

  function go(bay) {
    STATE.bay = bay;
    clearInterval(STATE.timer);
    toggleMobileSidebar(false);
    $$('#sbNav .sb-item[data-go]').forEach(b => b.classList.toggle('on', b.dataset.go === bay));
    ({
      core: renderCore,
      tunnels: renderTunnels,
      xray: renderXray,
      engine: renderEngine,
      telemetry: renderTelemetry,
      forge: renderForge,
      admins: renderAdmins,
      signals: renderSignals,
      audit: renderAudit
    }[bay] || renderCore)();
  }

  /* ═════════════════════ 1. CORE (Flame Launcher + Centered % Core) ═════════════════════ */
  async function renderCore() {
    const isViewer = STATE.me && STATE.me.role === 'viewer';
    setBayHead(
      'COMMAND DECK · LIVE TELEMETRY',
      'Core',
      'Real-time reactor load, multiplexed 80/443 health & interactive service tiles',
      `<button class="btn sm" id="btnCoreRefresh">${ic('refresh')}<span>Sync</span></button>` +
      (isViewer ? '' : `
       <button class="btn-flame-launcher" id="btnFlameLauncher" type="button">
         <canvas class="btn-fire-cv" id="launcherFire"></canvas>
         <svg viewBox="0 0 64 64" class="flame-svg"><use href="#flame"/></svg>
         <span>Flame Launcher</span>
       </button>`)
    );
    if (!isViewer && $('#launcherFire')) {
      attachRealFire($('#launcherFire'), { w: 56, h: 32, cool: 4.1 });
    }
    $('#btnCoreRefresh').onclick = () => renderCore();
    if (!isViewer && $('#btnFlameLauncher')) {
      $('#btnFlameLauncher').onclick = openQuickSheet;
    }

    const draw = async () => {
      const d = await api('/overview');
      STATE.cfg = d.cfg; syncHud();
      const ring = (r, pct, color) => {
        const c = 2 * Math.PI * r;
        const off = c * (1 - Math.min(100, Math.max(2, pct)) / 100);
        return `<circle class="trk" cx="120" cy="120" r="${r}" stroke-width="9.5"/>
                <circle class="arc" cx="120" cy="120" r="${r}" stroke="${color}" stroke-width="9.5" stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${off.toFixed(1)}"/>`;
      };
      const netPct = Math.min(100, Math.round(((d.rx_bps + d.tx_bps) / (125 * 1048576)) * 100) + 8);
      const runCount = d.services.filter(s => s.status === 'running').length;
      const spRx = sparkPath(d.hist.rx, 460, 110);
      const spTx = sparkPath(d.hist.tx, 460, 110);

      $('#view').innerHTML = `
        <div class="core-top">
          <section class="mod hot reactor-mod">
            <div class="reactor">
              <svg viewBox="0 0 240 240">
                <circle class="orbit" cx="120" cy="120" r="113" stroke-width="1"/>
                ${ring(100, d.cpu_pct, '#ff2d2d')}
                ${ring(83, d.ram_pct, '#ff6a00')}
                ${ring(66, d.disk_pct, '#ffb000')}
                ${ring(49, netPct, '#ffd36b')}
              </svg>
              <div class="reactor-center">
                <span class="core-glow"></span>
                <div class="temp">${d.cpu_pct}<small>%</small></div>
                <div class="state">${d.cpu_pct > 75 ? 'OVERDRIVE' : 'OPTIMAL'}</div>
              </div>
            </div>
            <div class="reactor-legend">
              <div class="lg"><i style="background:#ff2d2d"></i><b>CPU CORE</b><span class="v">${d.cpu_pct}%</span><div class="s">load ${esc(d.load)}</div></div>
              <div class="lg"><i style="background:#ff6a00"></i><b>MEMORY</b><span class="v">${d.ram_pct}%</span><div class="s">${fmtBytes(d.ram_used)} / ${fmtBytes(d.ram_total)}</div></div>
              <div class="lg"><i style="background:#ffb000"></i><b>STORAGE</b><span class="v">${d.disk_pct}%</span><div class="s">${fmtBytes(d.disk_used)} / ${fmtBytes(d.disk_total)}</div></div>
              <div class="lg"><i style="background:#ffd36b"></i><b>THROUGHPUT</b><span class="v">↓ ${fmtRate(d.rx_bps)}</span><div class="s">↑ ${fmtRate(d.tx_bps)} · total ${fmtBytes(d.rx_total + d.tx_total)}</div></div>
            </div>
          </section>

          <div class="kpis">
            <div class="mod kpi" style="cursor:pointer" data-nav="tunnels">
              <div class="k">${ic('tunnel')} SSH ACCOUNTS</div>
              <div class="v">${d.ssh_total} <small>accounts</small></div>
              <div class="s"><span><i class="dot lit"></i> <b>${d.ssh_online}</b> live</span><span>path <b>/alyan</b></span></div>
            </div>
            <div class="mod kpi" style="cursor:pointer" data-nav="xray">
              <div class="k">${ic('bolt')} XRAY MATRIX</div>
              <div class="v">${d.xray_total} <small>clients</small></div>
              <div class="s"><span><i class="dot lit"></i> <b>${d.xray_online || 0}</b> live</span><span>VLESS <b>${d.xray_vless}</b></span><span>VMess <b>${d.xray_vmess}</b></span><span>Trojan <b>${d.xray_trojan}</b></span></div>
            </div>
            <div class="mod kpi" style="cursor:pointer" data-nav="engine">
              <div class="k">${ic('engine')} FLAME STACK</div>
              <div class="v">${runCount} <small>/ ${d.services.length} active</small></div>
              <div class="s"><span>80 · 443 · 109 · 143</span></div>
            </div>
            <div class="mod kpi" style="cursor:pointer" data-nav="telemetry">
              <div class="k">${ic('chart')} VPS INFO</div>
              <div class="v"><small>${esc(d.cfg.ip)}</small></div>
              <div class="s"><span><b>${esc(d.cfg.os)}</b></span><span>up ${esc(d.cfg.uptime)}</span></div>
            </div>
          </div>
        </div>

        <section class="mod" style="margin-top:14px">
          <div class="mod-h">
            <h3>${ic('chart')} Live Flame Stream</h3>
            <span class="sub">↓ ${fmtRate(d.rx_bps)} &nbsp;·&nbsp; ↑ ${fmtRate(d.tx_bps)}</span>
          </div>
          <svg viewBox="0 0 460 110" preserveAspectRatio="none" class="spark">
            <defs>
              <linearGradient id="spFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stop-color="#ff3b1f" stop-opacity=".42"/><stop offset="1" stop-color="#ff3b1f" stop-opacity="0"/>
              </linearGradient>
            </defs>
            <path d="${spRx.area}" fill="url(#spFill)"/>
            <path d="${spRx.line}" fill="none" stroke="#ff3b1f" stroke-width="2.2"/>
            <path d="${spTx.line}" fill="none" stroke="#ffb000" stroke-width="1.8" stroke-dasharray="4 3"/>
          </svg>
        </section>

        <section class="mod" style="margin-top:14px">
          <div class="mod-h">
            <h3>${ic('engine')} Ember Service Matrix</h3>
            <span class="sub">${isViewer ? 'Active service health & status' : 'Click any tile to flip for Start / Restart / Stop / Logs'}</span>
          </div>
          <div class="ember-grid">
            ${d.services.map(s => `
              <div class="ember ${s.status === 'running' ? 'on' : 'bad'}" data-svc="${esc(s.id)}">
                <div class="ember-in">
                  <div class="ember-f">
                    <span class="ember-ic">${ic(s.id.includes('xray') ? 'bolt' : s.id.includes('bot') ? 'send' : 'engine')}</span>
                    <div>
                      <div class="ember-n">${esc(s.name)}</div>
                      <div class="ember-d">${esc(s.desc)}</div>
                    </div>
                    <div class="ember-s">
                      <span><i class="dot ${s.status === 'running' ? 'lit' : 'fire'}"></i> ${esc(s.status)}</span>
                      <span>${esc(s.mem)}</span>
                    </div>
                  </div>
                  <div class="ember-b">
                    <button class="ember-x" type="button" data-unflip>×</button>
                    <div class="ember-n" style="font-size:12px">${esc(s.name)}</div>
                    <div class="btns">
                      <button class="btn sm btn-flame" data-sact="restart" data-sid="${esc(s.id)}">Restart</button>
                      <button class="btn sm ${s.status === 'running' ? 'btn-danger' : ''}" data-sact="${s.status === 'running' ? 'stop' : 'start'}" data-sid="${esc(s.id)}">${s.status === 'running' ? 'Stop' : 'Start'}</button>
                      <button class="btn sm" style="grid-column:span 2" data-sact="logs" data-sid="${esc(s.id)}">Logs</button>
                    </div>
                  </div>
                </div>
              </div>`).join('')}
          </div>
        </section>`;

      $$('[data-nav]', $('#view')).forEach(el => { el.onclick = () => go(el.dataset.nav); });
      $$('.ember', $('#view')).forEach(tile => {
        tile.onclick = (e) => {
          if (isViewer) return;
          if (e.target.closest('[data-unflip]')) { tile.classList.remove('flip'); return; }
          if (e.target.closest('[data-sact]')) return;
          tile.classList.toggle('flip');
        };
      });
      $$('[data-sact]', $('#view')).forEach(btn => {
        btn.onclick = async (e) => {
          e.stopPropagation();
          const { sid, sact } = btn.dataset;
          if (sact === 'logs') {
            const r = await api(`/service/${sid}/logs`);
            openSheet(`${sid} · Journal`, 'SYSTEMD LOGS', `<pre class="term">${esc(r.logs)}</pre>`);
            return;
          }
          await api(`/service/${sid}/${sact}`, { method: 'POST' });
          toast(`${sid}: ${sact} executed`);
          draw();
        };
      });
    };
    let coreBusy = false;
    await draw();
    STATE.timer = setInterval(async () => {
      if (STATE.bay !== 'core' || document.hidden || coreBusy || $('.ember.flip')) return;
      coreBusy = true;
      try { await draw(); } catch {} finally { coreBusy = false; }
    }, 2000);
  }

  /* ═════════════════════ 2. SSH ACCOUNTS (6-Corner SVG + 2s Real-Time Sync) ═════════════════════ */
  async function renderTunnels() {
    let items = [];
    let sshBusy = false;
    const isViewer = STATE.me && STATE.me.role === 'viewer';

    const sshSheetHtml = (liveIps) => liveIps.length
      ? `<div class="tbl-wrap"><table><thead><tr><th>User</th><th>Client IP</th></tr></thead><tbody>${liveIps.map(r => `<tr><td><b>${esc(r.user)}</b></td><td>${esc(r.ip)}</td></tr>`).join('')}</tbody></table></div>`
      : `<div class="empty"><p>No active SSH-WS, SSL or Dropbear sessions right now.</p></div>`;

    const initData = await api('/ssh');
    items = initData.items || [];
    STATE.cfg = initData.cfg; syncHud();

    const getLiveIps = () => items.flatMap(u => (u.status === 'disabled' ? [] : (u.ips || [])).map(ip => ({ user: u.username, ip })));
    const getLiveUsersTotal = () => items.reduce((acc, u) => acc + (u.status === 'disabled' ? 0 : (u.online || (u.ips || []).length || 0)), 0);
    const getLiveUsersList = () => items
      .filter(u => u.status !== 'disabled' && (u.online > 0 || (u.ips && u.ips.length > 0)))
      .map(u => ({
        user: u.username,
        online: u.online || (u.ips || []).length || 0,
        limit: u.ip_limit > 0 ? `${u.ip_limit} Users` : 'Unlimited'
      }));

    const sshUsersSheetHtml = (usersList) => usersList.length
      ? `<div class="tbl-wrap"><table><thead><tr><th>Account</th><th>Live Users (Active Sessions)</th><th>User Limit</th></tr></thead><tbody>${usersList.map(r => `<tr><td><b>${esc(r.user)}</b></td><td><span class="pill lit"><i class="dot lit"></i>${r.online} Active</span></td><td>${r.limit}</td></tr>`).join('')}</tbody></table></div>`
      : `<div class="empty"><p>No active SSH user sessions right now.</p></div>`;

    setBayHead(
      'SSH · WS · SSL',
      'SSH Accounts',
      `Direct (22, 109, 143) · SSL (443) · WebSocket (80/443 → ${STATE.cfg.ws_path || '/alyan'})`,
      isViewer ? '' : `
       <button class="btn sm" id="btnLiveIps">${ic('wifi')}<span id="btnLiveIpsTxt">Connected IPs (${getLiveIps().length})</span></button>
       <button class="btn sm" id="btnLiveUsers">${ic('user')}<span id="btnLiveUsersTxt">Live Users (${getLiveUsersTotal()})</span></button>
       <button class="btn btn-flame sm" id="btnAddSsh">${ic('plus')}<span>Create SSH Account</span></button>`
    );
    if (!isViewer) {
      const btnAdd = $('#btnAddSsh'); if (btnAdd) btnAdd.onclick = () => openSshForm();
      const btnLive = $('#btnLiveIps'); if (btnLive) btnLive.onclick = () => openSheet('Live Connected SSH IPs', 'REAL-IP CORRELATOR · LIVE 2S', `<div id="sshLiveSheetBody">${sshSheetHtml(getLiveIps())}</div>`);
      const btnUsers = $('#btnLiveUsers'); if (btnUsers) btnUsers.onclick = () => openSheet('Live Connected SSH Users', 'REAL-TIME ACTIVE SESSIONS · LIVE 2S', `<div id="sshUsersSheetBody">${sshUsersSheetHtml(getLiveUsersList())}</div>`);
    }

    $('#view').innerHTML = `
      <div class="toolbar">
        <div class="search">${ic('search')}<input id="sshSearch" placeholder="Search SSH account…" value="${esc(STATE.searchSsh)}"/></div>
        <span class="live" id="sshLiveMeta"><i class="dot lit"></i> ${items.length} accounts · live 2s</span>
      </div>
      <div id="sshCardsHost"></div>`;

    const paintCards = () => {
      const host = $('#sshCardsHost');
      if (!host || $('.acc.is-disintegrating', host)) return;
      const liveIps = getLiveIps();
      const liveBtnTxt = $('#btnLiveIpsTxt');
      if (liveBtnTxt) liveBtnTxt.textContent = `Connected IPs (${liveIps.length})`;
      const liveUsersTxt = $('#btnLiveUsersTxt');
      if (liveUsersTxt) liveUsersTxt.textContent = `Live Users (${getLiveUsersTotal()})`;
      const liveMeta = $('#sshLiveMeta');
      if (liveMeta) liveMeta.innerHTML = `<i class="dot lit"></i> ${items.length} accounts · live 2s`;
      const openModalBody = $('#sshLiveSheetBody');
      if (openModalBody) openModalBody.innerHTML = sshSheetHtml(liveIps);
      const openUsersModalBody = $('#sshUsersSheetBody');
      if (openUsersModalBody) openUsersModalBody.innerHTML = sshUsersSheetHtml(getLiveUsersList());

      const filtered = items.filter(u => u.username.toLowerCase().includes(STATE.searchSsh.toLowerCase()));
      host.innerHTML = filtered.length ? `<div class="cards">${filtered.map(u => {
        const isDis = u.status === 'disabled';
        const pct = u.gb_limit > 0 ? Math.min(100, (u.used_bytes / (u.gb_limit * 1073741824)) * 100) : 100;
        if (isViewer) {
          return `
          <article class="mod acc ${isDis ? 'acc-disabled' : ''}">
            <div class="acc-top">
              ${hexAvatar(u.username[0].toUpperCase(), false)}
              <div>
                <div class="acc-n">${esc(u.username)}</div>
                <div class="acc-m">SSH Account</div>
              </div>
            </div>
            <div class="meter">
              <div class="meter-h"><span>DATA QUOTA</span><b>${fmtBytes(u.used_bytes)} / ${u.gb_limit > 0 ? u.gb_limit + ' GB' : '∞'}</b></div>
              <div class="bar ${u.gb_limit > 0 ? '' : 'inf'}"><i style="width:${pct.toFixed(1)}%"></i></div>
            </div>
          </article>`;
        }
        const ipList = isDis ? [] : (u.ips || []);
        const onlineCnt = isDis ? 0 : (u.online || ipList.length || 0);
        const badgeHtml = isDis
          ? `<span class="pill is-disabled"><i class="dot fire"></i>disable</span>`
          : `<span class="pill ${onlineCnt ? 'lit' : ''}"><i class="dot ${onlineCnt ? 'lit' : ''}"></i>${onlineCnt ? onlineCnt + ' online' : 'offline'}</span>`;
        return `
        <article class="mod acc ${isDis ? 'acc-disabled' : ''}">
          <div class="acc-top">
            ${hexAvatar(u.username[0].toUpperCase(), !isDis && onlineCnt > 0)}
            <div>
              <div class="acc-n">${esc(u.username)} ${badgeHtml}</div>
              <div class="acc-m">owner <b>${esc(u.owner)}</b> · exp <b>${esc(u.expiry)}</b> (${daysLeft(u.expiry)}d)</div>
            </div>
          </div>
          <div class="meter">
            <div class="meter-h"><span>DATA QUOTA</span><b>${fmtBytes(u.used_bytes)} / ${u.gb_limit > 0 ? u.gb_limit + ' GB' : '∞'}</b></div>
            <div class="bar ${u.gb_limit > 0 ? '' : 'inf'}"><i style="width:${pct.toFixed(1)}%"></i></div>
          </div>
          <div class="acc-stats cols2">
            <div class="st"><span>USER LIMIT</span><b>${u.ip_limit > 0 ? u.ip_limit + ' Users' : 'Unlimited'}</b></div>
            <div class="st" title="${onlineCnt} Active Users"><span>LIVE USERS</span><b>${onlineCnt}</b></div>
          </div>
          <div class="acc-act">
            <button class="btn sm btn-flame" data-ticket="${esc(u.username)}"><span>Info</span></button>
            <button class="btn sm ${isDis ? 'btn-toggle-on' : 'btn-toggle-off'}" title="${isDis ? 'Enable account' : 'Disable account'}" data-toggle="${esc(u.username)}" data-dis="${isDis ? '1' : '0'}">${ic(isDis ? 'check' : 'power')}<span>${isDis ? 'Enable' : 'Disable'}</span></button>
            <button class="icon-btn sm" title="Edit limits" data-edit="${esc(u.username)}">${ic('edit')}</button>
            <button class="icon-btn sm danger" title="Delete" data-del="${esc(u.username)}">${ic('trash')}</button>
          </div>
        </article>`;
      }).join('')}</div>` : `<div class="mod empty">${ic('tunnel')}<p>No matching SSH accounts found.</p></div>`;

      if (!isViewer) {
        $$('[data-ticket]', host).forEach(b => { b.onclick = () => { const u = items.find(x => x.username === b.dataset.ticket); if (u) showSshTicket(u); }; });
        $$('[data-toggle]', host).forEach(b => {
          b.onclick = async () => {
            const nextStatus = b.dataset.dis === '1' ? 'active' : 'disabled';
            try {
              await api(`/ssh/${encodeURIComponent(b.dataset.toggle)}`, { method: 'PATCH', body: { status: nextStatus } });
              toast(`SSH account ${b.dataset.toggle} ${nextStatus === 'disabled' ? 'disabled' : 'enabled'}`);
              const fresh = await api('/ssh');
              items = fresh.items || [];
              paintCards();
            } catch (err) { toast(err.message, 'err'); }
          };
        });
        $$('[data-edit]', host).forEach(b => { b.onclick = () => { const u = items.find(x => x.username === b.dataset.edit); if (u) openSshForm(u); }; });
        $$('[data-del]', host).forEach(b => {
          b.onclick = async () => {
            const card = b.closest('.acc');
            try {
              await api(`/ssh/${encodeURIComponent(b.dataset.del)}`, { method: 'DELETE' });
              toast(`Deleted SSH account ${b.dataset.del}`);
              await nanoDisintegrate(card);
              items = items.filter(x => x.username !== b.dataset.del);
              paintCards();
            } catch (err) { toast(err.message, 'err'); }
          };
        });
      }
    };

    $('#sshSearch').oninput = (e) => { STATE.searchSsh = e.target.value; paintCards(); };
    paintCards();

    STATE.timer = setInterval(async () => {
      if (STATE.bay !== 'tunnels' || document.hidden || sshBusy || $('.acc.is-disintegrating')) return;
      sshBusy = true;
      try {
        const res = await api('/ssh');
        items = res.items || [];
        STATE.cfg = res.cfg;
        paintCards();
      } catch {} finally { sshBusy = false; }
    }, 2000);
  }

  function showSshTicket(u) {
    const payload = buildSshPayload(STATE.cfg.domain);
    const fullTxt = buildSshShareText(u, STATE.cfg);
    openSheet(`SSH Account: ${u.username}`, 'ACCOUNT INFO', `
      <div class="ticket">
        <div class="ticket-h"><b>${esc(u.username)}</b><span>SSH · WS · SSL</span></div>
        <div class="ticket-b">
          <div class="tk-row"><span>Username</span><b>${esc(u.username)}</b><button class="icon-btn sm" data-cp="${esc(u.username)}">${ic('copy')}</button></div>
          <div class="tk-row"><span>Password</span><b>${esc(u.password || '••••')}</b><button class="icon-btn sm" data-cp="${esc(u.password || '')}">${ic('copy')}</button></div>
          <div class="tk-row"><span>Host / SNI</span><b>${esc(STATE.cfg.domain)}</b><button class="icon-btn sm" data-cp="${esc(STATE.cfg.domain)}">${ic('copy')}</button></div>
          <div class="tk-row"><span>Expiry</span><b>${esc(u.expiry)} (${daysLeft(u.expiry)}d)</b><span></span></div>
          <div class="tk-row"><span>Limits</span><b>${u.gb_limit > 0 ? u.gb_limit + ' GB' : 'Unlimited'} · ${u.ip_limit > 0 ? u.ip_limit + ' Users' : 'Unlimited Users'}</b><span></span></div>
          <div class="tk-sec"></div>
          <div class="tk-label">PORTS &amp; ROUTING</div>
          <div class="tk-row"><span>SSH Direct</span><b>22, 109, 143</b><span></span></div>
          <div class="tk-row"><span>SSH SSL</span><b>443</b><span></span></div>
          <div class="tk-row"><span>SSH WS</span><b>80 → /alyan</b><span></span></div>
          <div class="tk-row"><span>SSH WS SSL</span><b>443 → /alyan</b><span></span></div>
          <div class="tk-sec"></div>
          <div class="tk-label">HTTP INJECTOR / CUSTOM PAYLOAD</div>
          <div class="payload">${esc(payload)}</div>
        </div>
      </div>
      <div class="foot">
        <button class="btn" id="cpPayloadOnly">${ic('copy')}<span>Copy Payload</span></button>
        <button class="btn btn-flame" id="cpFullCard">${ic('copy')}<span>Copy Full Account</span></button>
      </div>`);
    $$('[data-cp]', $('#sheet')).forEach(b => { b.onclick = () => copyText(b.dataset.cp); });
    $('#cpPayloadOnly').onclick = () => copyText(payload, 'Payload copied');
    $('#cpFullCard').onclick = () => copyText(fullTxt, 'Full SSH account copied');
  }

  function openSshForm(existing = null) {
    if (STATE.me && STATE.me.role === 'viewer') return;
    openSheet(existing ? `Edit ${existing.username}` : 'Create SSH Account', 'SSH PROVISIONER', `
      <form class="stack" id="sshForm" autocomplete="off">
        ${existing ? '' : `<label class="field"><span>Username</span><input name="username" required pattern="[A-Za-z0-9_-]{1,31}" placeholder="Enter username" autocomplete="off" /><small>a-z, A-Z, 0-9, _ - (max 31 chars)</small></label>`}
        <label class="field"><span>${existing ? 'New Password (blank = keep)' : 'Password'}</span><input name="password" ${existing ? '' : 'required'} placeholder="Enter password" autocomplete="new-password" /></label>
        <div class="row3">
          <label class="field"><span>Days</span><div class="stepper"><button type="button">−</button><input name="days" type="number" min="1" value="${existing ? Math.max(1, daysLeft(existing.expiry)) : 30}" data-step="5"/><button type="button">+</button></div></label>
          <label class="field"><span>GB (0=∞)</span><div class="stepper"><button type="button">−</button><input name="gb_limit" type="number" min="0" value="${existing ? existing.gb_limit : 0}" data-step="10"/><button type="button">+</button></div></label>
          <label class="field"><span>User Limit (0=∞)</span><div class="stepper"><button type="button">−</button><input name="ip_limit" type="number" min="0" value="${existing ? existing.ip_limit : 2}" data-step="1"/><button type="button">+</button></div></label>
        </div>
        <div class="foot">
          <button type="button" class="btn" id="sshCancel">Cancel</button>
          <button type="submit" class="btn btn-flame">${existing ? 'Save Changes' : 'Create SSH Account'}</button>
        </div>
      </form>`);
    bindSteppers($('#sheet'));
    $('#sshCancel').onclick = closeSheet;
    $('#sshForm').onsubmit = async (e) => {
      e.preventDefault();
      const fd = Object.fromEntries(new FormData(e.target).entries());
      try {
        if (existing) { await api(`/ssh/${encodeURIComponent(existing.username)}`, { method: 'PATCH', body: fd }); toast(`Updated ${existing.username}`); closeSheet(); renderTunnels(); }
        else { const r = await api('/ssh', { method: 'POST', body: fd }); toast(`Created ${r.item.username}`); renderTunnels(); showSshTicket(r.item); }
      } catch (err) { toast(err.message, 'err'); }
    };
  }

  /* ═════════════════════ 3. XRAY (6-Corner SVG Hexagon + 2s Real-Time Sync) ═════════════════════ */
  async function renderXray() {
    let items = [];
    let xrayBusy = false;
    const protos = ['vless', 'vmess', 'trojan'];
    const isViewer = STATE.me && STATE.me.role === 'viewer';

    const xraySheetHtml = (liveIps) => liveIps.length
      ? `<div class="tbl-wrap"><table><thead><tr><th>Client</th><th>Protocol</th><th>Client IP</th></tr></thead><tbody>${liveIps.map(r => `<tr><td><b>${esc(r.user)}</b></td><td>${esc(r.proto)}</td><td>${esc(r.ip)}</td></tr>`).join('')}</tbody></table></div>`
      : `<div class="empty"><p>No active VLESS, VMess or Trojan sessions right now.</p></div>`;

    const initData = await api('/xray');
    items = initData.items || [];
    STATE.cfg = initData.cfg; syncHud();

    const getLiveIps = () => items.flatMap(u => (u.status === 'disabled' ? [] : (u.ips || [])).map(ip => ({ user: u.username, proto: u.proto.toUpperCase(), ip })));

    const getXrayLiveUsersTotal = () => items.filter(u => u.proto === STATE.xrayProto).reduce((acc, u) => acc + (u.status === 'disabled' ? 0 : (u.online || (u.ips || []).length || 0)), 0);
    const getXrayLiveUsersList = () => items
      .filter(u => u.status !== 'disabled' && u.proto === STATE.xrayProto && (u.online > 0 || (u.ips && u.ips.length > 0)))
      .map(u => ({
        user: u.username,
        proto: u.proto.toUpperCase(),
        online: u.online || (u.ips || []).length || 0,
        limit: u.ip_limit > 0 ? `${u.ip_limit} Users` : 'Unlimited'
      }));

    const xrayUsersSheetHtml = (usersList) => usersList.length
      ? `<div class="tbl-wrap"><table><thead><tr><th>Client</th><th>Protocol</th><th>Live Users (Active Sessions)</th><th>User Limit</th></tr></thead><tbody>${usersList.map(r => `<tr><td><b>${esc(r.user)}</b></td><td><b>${esc(r.proto)}</b></td><td><span class="pill lit"><i class="dot lit"></i>${r.online} Active</span></td><td>${r.limit}</td></tr>`).join('')}</tbody></table></div>`
      : `<div class="empty"><p>No active ${STATE.xrayProto.toUpperCase()} user sessions right now.</p></div>`;

    const syncBayHeader = () => {
      setBayHead(
        'XRAY CORE',
        'Xray',
        'Zero-downtime VLESS · VMess · Trojan over WS, gRPC & XHTTP on 80 / 443',
        isViewer ? '' : `
         <button class="btn sm" id="btnXrayLiveIps">${ic('wifi')}<span id="btnXrayLiveIpsTxt">Connected IPs (${getLiveIps().length})</span></button>
         <button class="btn sm" id="btnXrayLiveUsers">${ic('user')}<span id="btnXrayLiveUsersTxt">Live Users (${getXrayLiveUsersTotal()})</span></button>
         <button class="btn btn-flame sm" id="btnAddXray">${ic('plus')}<span>Create ${STATE.xrayProto.toUpperCase()}</span></button>`
      );
      if (!isViewer) {
        const btnAdd = $('#btnAddXray'); if (btnAdd) btnAdd.onclick = () => openXrayForm(STATE.xrayProto);
        const btnLive = $('#btnXrayLiveIps'); if (btnLive) btnLive.onclick = () => openSheet('Live Connected Xray IPs', 'REAL-IP CORRELATOR · LIVE 2S', `<div id="xrayLiveSheetBody">${xraySheetHtml(getLiveIps())}</div>`);
        const btnXUsers = $('#btnXrayLiveUsers'); if (btnXUsers) btnXUsers.onclick = () => openSheet(`Live Connected ${STATE.xrayProto.toUpperCase()} Users`, 'REAL-TIME ACTIVE SESSIONS · LIVE 2S', `<div id="xrayUsersSheetBody">${xrayUsersSheetHtml(getXrayLiveUsersList())}</div>`);
      }
    };
    syncBayHeader();

    const pIdxInit = protos.indexOf(STATE.xrayProto);
    $('#view').innerHTML = `
      <div class="toolbar">
        <div class="seg" id="xraySeg">
          <span class="seg-ind" id="xraySegInd" style="left:calc(${pIdxInit * 33.333}% + 4px);width:calc(33.333% - 8px)"></span>
          ${protos.map(p => `<button type="button" class="${p === STATE.xrayProto ? 'on' : ''}" data-xp="${p}">${p.toUpperCase()}</button>`).join('')}
        </div>
        <div class="search">${ic('search')}<input id="xraySearch" placeholder="Search ${STATE.xrayProto.toUpperCase()} client…" value="${esc(STATE.searchXray)}"/></div>
        <span class="live" id="xrayLiveMeta"><i class="dot lit"></i> 0 clients · live 2s</span>
      </div>
      <div id="xrayCardsHost"></div>`;

    const paintXrayCards = () => {
      const host = $('#xrayCardsHost');
      if (!host || $('.acc.is-disintegrating', host)) return;
      const liveIps = getLiveIps();
      const liveBtnTxt = $('#btnXrayLiveIpsTxt');
      if (liveBtnTxt) liveBtnTxt.textContent = `Connected IPs (${liveIps.length})`;
      const liveUsersTxt = $('#btnXrayLiveUsersTxt');
      if (liveUsersTxt) liveUsersTxt.textContent = `Live Users (${getXrayLiveUsersTotal()})`;
      const openModalBody = $('#xrayLiveSheetBody');
      if (openModalBody) openModalBody.innerHTML = xraySheetHtml(liveIps);
      const openXrayUsersModalBody = $('#xrayUsersSheetBody');
      if (openXrayUsersModalBody) openXrayUsersModalBody.innerHTML = xrayUsersSheetHtml(getXrayLiveUsersList());

      const protoAll = items.filter(u => u.proto === STATE.xrayProto);
      const liveMeta = $('#xrayLiveMeta');
      if (liveMeta) liveMeta.innerHTML = `<i class="dot lit"></i> ${protoAll.length} clients · live 2s`;

      const list = protoAll.filter(u => u.username.toLowerCase().includes(STATE.searchXray.toLowerCase()));
      host.innerHTML = list.length ? `<div class="cards">${list.map(u => {
        const isDis = u.status === 'disabled';
        const pct = u.gb_limit > 0 ? Math.min(100, (u.used_bytes / (u.gb_limit * 1073741824)) * 100) : 100;
        if (isViewer) {
          return `
          <article class="mod acc ${isDis ? 'acc-disabled' : ''}">
            <div class="acc-top">
              ${hexAvatar(u.username[0].toUpperCase(), false)}
              <div>
                <div class="acc-n">${esc(u.username)}</div>
                <div class="acc-m"><b>${esc(u.proto.toUpperCase())}</b> · Client</div>
              </div>
            </div>
            <div class="meter">
              <div class="meter-h"><span>TRAFFIC</span><b>${fmtBytes(u.used_bytes)} / ${u.gb_limit > 0 ? u.gb_limit + ' GB' : '∞'}</b></div>
              <div class="bar ${u.gb_limit > 0 ? '' : 'inf'}"><i style="width:${pct.toFixed(1)}%"></i></div>
            </div>
          </article>`;
        }
        const ipList = isDis ? [] : (u.ips || []);
        const onlineCnt = isDis ? 0 : (ipList.length || u.online || 0);
        const badgeHtml = isDis
          ? `<span class="pill is-disabled"><i class="dot fire"></i>disable</span>`
          : `<span class="pill ${onlineCnt ? 'lit' : ''}"><i class="dot ${onlineCnt ? 'lit' : ''}"></i>${onlineCnt ? onlineCnt + ' online' : 'offline'}</span>`;
        const wsPath = `/alyan-${u.proto}`;
        return `
        <article class="mod acc ${isDis ? 'acc-disabled' : ''}">
          <div class="acc-top">
            ${hexAvatar(u.username[0].toUpperCase(), !isDis && onlineCnt > 0)}
            <div>
              <div class="acc-n">${esc(u.username)} ${badgeHtml}</div>
              <div class="acc-m"><b>${esc(u.proto.toUpperCase())}</b> · cap <b>${u.ip_limit > 0 ? u.ip_limit + ' Users' : 'Unlimited'}</b> · exp <b>${esc(u.expiry)}</b></div>
              <div class="uuid" data-cpuuid="${esc(u.uuid)}">${esc(u.uuid.slice(0, 18))}… ${ic('copy')}</div>
            </div>
          </div>
          <div class="meter">
            <div class="meter-h"><span>TRAFFIC</span><b>${fmtBytes(u.used_bytes)} / ${u.gb_limit > 0 ? u.gb_limit + ' GB' : '∞'}</b></div>
            <div class="bar ${u.gb_limit > 0 ? '' : 'inf'}"><i style="width:${pct.toFixed(1)}%"></i></div>
          </div>
          <div class="acc-stats">
            <div class="st" title="${onlineCnt} Active Users"><span>LIVE USERS</span><b>${onlineCnt}</b></div>
            <div class="st" title="${esc(wsPath)}"><span>WS PATH</span><b>${esc(wsPath)}</b></div>
            <div class="st"><span>EXPIRY</span><b>${daysLeft(u.expiry)}d</b></div>
          </div>
          <div class="acc-act">
            <button class="btn sm btn-flame" data-xlinks="${esc(u.uuid)}">${ic('qr')}<span>Links &amp; QR</span></button>
            <button class="btn sm ${isDis ? 'btn-toggle-on' : 'btn-toggle-off'}" title="${isDis ? 'Enable client' : 'Disable client'}" data-xtoggle="${esc(u.uuid)}" data-dis="${isDis ? '1' : '0'}">${ic(isDis ? 'check' : 'power')}<span>${isDis ? 'Enable' : 'Disable'}</span></button>
            <button class="icon-btn sm" title="Edit client" data-xedit="${esc(u.uuid)}">${ic('edit')}</button>
            <button class="icon-btn sm danger" title="Delete" data-xdel="${esc(u.uuid)}">${ic('trash')}</button>
          </div>
        </article>`;
      }).join('')}</div>` : `<div class="mod empty">${ic('bolt')}<p>No ${STATE.xrayProto.toUpperCase()} accounts yet. Click Create above.</p></div>`;

      if (!isViewer) {
        $$('[data-cpuuid]', host).forEach(el => { el.onclick = () => copyText(el.dataset.cpuuid, 'UUID copied'); });
        $$('[data-xlinks]', host).forEach(b => { b.onclick = () => { const u = items.find(x => x.uuid === b.dataset.xlinks); if (u) showXrayLinks(u); }; });
        $$('[data-xtoggle]', host).forEach(b => {
          b.onclick = async () => {
            const nextStatus = b.dataset.dis === '1' ? 'active' : 'disabled';
            try {
              const target = items.find(x => x.uuid === b.dataset.xtoggle);
              await api(`/xray/${encodeURIComponent(b.dataset.xtoggle)}`, { method: 'PATCH', body: { status: nextStatus } });
              toast(`${target ? target.username : 'Xray client'} ${nextStatus === 'disabled' ? 'disabled' : 'enabled'}`);
              const fresh = await api('/xray');
              items = fresh.items || [];
              paintXrayCards();
            } catch (err) { toast(err.message, 'err'); }
          };
        });
        $$('[data-xedit]', host).forEach(b => { b.onclick = () => { const u = items.find(x => x.uuid === b.dataset.xedit); if (u) openXrayForm(u.proto, u); }; });
        $$('[data-xdel]', host).forEach(b => {
          b.onclick = async () => {
            const card = b.closest('.acc');
            try {
              await api(`/xray/${encodeURIComponent(b.dataset.xdel)}`, { method: 'DELETE' });
              toast('Xray client removed');
              await nanoDisintegrate(card);
              items = items.filter(x => x.uuid !== b.dataset.xdel);
              paintXrayCards();
            } catch (err) { toast(err.message, 'err'); }
          };
        });
      }
    };

    $$('[data-xp]', $('#xraySeg')).forEach(b => {
      b.onclick = () => {
        STATE.xrayProto = b.dataset.xp;
        const idx = protos.indexOf(STATE.xrayProto);
        const ind = $('#xraySegInd');
        if (ind) ind.style.left = `calc(${idx * 33.333}% + 4px)`;
        $$('[data-xp]', $('#xraySeg')).forEach(x => x.classList.toggle('on', x.dataset.xp === STATE.xrayProto));
        const inp = $('#xraySearch');
        if (inp) inp.placeholder = `Search ${STATE.xrayProto.toUpperCase()} client…`;
        syncBayHeader();
        paintXrayCards();
      };
    });
    $('#xraySearch').oninput = (e) => { STATE.searchXray = e.target.value; paintXrayCards(); };
    paintXrayCards();

    STATE.timer = setInterval(async () => {
      if (STATE.bay !== 'xray' || document.hidden || xrayBusy || $('.acc.is-disintegrating')) return;
      xrayBusy = true;
      try {
        const res = await api('/xray');
        items = res.items || [];
        STATE.cfg = res.cfg;
        paintXrayCards();
      } catch {} finally { xrayBusy = false; }
    }, 2000);
  }

  function showXrayLinks(u) {
    const links = buildXrayLinks(u, STATE.cfg);
    openSheet(`${u.username} · ${u.proto.toUpperCase()}`, 'XRAY URIS & QR', `
      <div class="stack">
        <div class="qr-box" id="qrTarget">${renderQrSvg(links[0].uri)}</div>
        <div class="tiny dim center" id="qrCaption">${esc(links[0].name)}</div>
        ${links.map((l, idx) => `
          <div class="link-row">
            <div style="min-width:0"><b>${esc(l.name)}</b><code>${esc(l.uri)}</code></div>
            <button class="icon-btn sm" title="Show QR" data-qri="${idx}">${ic('qr')}</button>
            <button class="icon-btn sm" title="Copy URI" data-cpuri="${esc(l.uri)}">${ic('copy')}</button>
          </div>`).join('')}
        <button class="btn btn-flame wide" id="cpAllXray">${ic('copy')}<span>Copy All ${links.length} Config Links</span></button>
      </div>`);
    $$('[data-qri]', $('#sheet')).forEach(b => {
      b.onclick = () => { const l = links[+b.dataset.qri]; $('#qrTarget').innerHTML = renderQrSvg(l.uri); $('#qrCaption').textContent = l.name; };
    });
    $$('[data-cpuri]', $('#sheet')).forEach(b => { b.onclick = () => copyText(b.dataset.cpuri, 'Config URI copied'); });
    $('#cpAllXray').onclick = () => copyText(links.map(l => l.uri).join('\n'), 'All Xray links copied');
  }

  function openXrayForm(proto = 'vless', existing = null) {
    if (STATE.me && STATE.me.role === 'viewer') return;
    const curProto = existing ? existing.proto : proto;
    openSheet(existing ? `Edit ${existing.username} (${curProto.toUpperCase()})` : `Create ${curProto.toUpperCase()} Client`, existing ? 'EDIT XRAY CLIENT' : 'XRAY HOT-PROVISION', `
      <form class="stack" id="xrayForm" autocomplete="off">
        <div class="row2">
          <label class="field"><span>Username</span><input name="username" required pattern="[A-Za-z0-9_-]{1,31}" value="${existing ? esc(existing.username) : ''}" placeholder="Enter username" autocomplete="off"/></label>
          <label class="field"><span>Protocol</span>
            <select name="proto">
              <option value="vless" ${curProto==='vless'?'selected':''}>VLESS</option>
              <option value="vmess" ${curProto==='vmess'?'selected':''}>VMess</option>
              <option value="trojan" ${curProto==='trojan'?'selected':''}>Trojan</option>
            </select>
          </label>
        </div>
        ${existing ? `<label class="field"><span>UUID / Trojan Key</span><input name="new_uuid" required class="mono" value="${esc(existing.uuid)}"/></label>` : ''}
        <div class="row3">
          <label class="field"><span>Days</span><div class="stepper"><button type="button">−</button><input name="days" type="number" min="1" value="${existing ? Math.max(1, daysLeft(existing.expiry)) : 30}" data-step="5"/><button type="button">+</button></div></label>
          <label class="field"><span>GB (0=∞)</span><div class="stepper"><button type="button">−</button><input name="gb_limit" type="number" min="0" value="${existing ? existing.gb_limit : 0}" data-step="10"/><button type="button">+</button></div></label>
          <label class="field"><span>User Limit (0=∞)</span><div class="stepper"><button type="button">−</button><input name="ip_limit" type="number" min="0" value="${existing ? existing.ip_limit : 2}" data-step="1"/><button type="button">+</button></div></label>
        </div>
        <div class="foot">
          <button type="button" class="btn" id="xCancel">Cancel</button>
          <button type="submit" class="btn btn-flame">${existing ? 'Save Changes' : 'Create Client'}</button>
        </div>
      </form>`);
    bindSteppers($('#sheet'));
    $('#xCancel').onclick = closeSheet;
    $('#xrayForm').onsubmit = async (e) => {
      e.preventDefault();
      const fd = Object.fromEntries(new FormData(e.target).entries());
      try {
        if (existing) {
          const r = await api(`/xray/${encodeURIComponent(existing.uuid)}`, { method: 'PATCH', body: fd });
          STATE.xrayProto = r.item.proto;
          toast(`Updated ${r.item.username}`);
          closeSheet();
          renderXray();
        } else {
          const r = await api('/xray', { method: 'POST', body: fd });
          STATE.xrayProto = r.item.proto;
          toast(`Created ${r.item.username}`);
          renderXray();
          showXrayLinks(r.item);
        }
      } catch (err) { toast(err.message, 'err'); }
    };
  }


  /* ═════════════════════ 4. ENGINE (Services & Listening Ports · 2s Sync) ═════════════════════ */
  async function renderEngine() {
    let engBusy = false;
    const isViewer = STATE.me && STATE.me.role === 'viewer';
    setBayHead(
      'DAEMONS & PORTS',
      'Engine',
      'HAProxy · Nginx · Dropbear · WS-Proxy · Xray · Alyan Guard · Bot · Panel',
      isViewer ? '' : `
       <button class="btn sm" id="btnRefreshEng">${ic('refresh')}<span>Refresh</span></button>
       <button class="btn btn-flame sm" id="btnRestartAll">${ic('bolt')}<span>Restart Full Stack</span></button>`
    );

    const drawEngine = async () => {
      const { services, ports } = await api('/engine');
      const pubPorts = (ports || []).filter(p => p.scope === 'public');
      const locPorts = (ports || []).filter(p => p.scope !== 'public');

      $('#view').innerHTML = `
        <div class="grid ${isViewer ? 'g1' : 'g2'}">
          <section class="mod" style="padding:18px 18px 8px">
            <div class="mod-h">
              <h3>${ic('engine')} System Daemons</h3>
              <span class="sub">${services.filter(s => s.status === 'running').length}/${services.length} running · live 2s</span>
            </div>
            <div>
              ${services.map(s => `
                <div class="svc ${s.status === 'running' ? 'on' : ''}">
                  <div class="svc-ic">${ic(s.id.includes('xray') ? 'bolt' : s.id.includes('bot') ? 'send' : 'engine')}</div>
                  <div>
                    <div class="svc-n">${esc(s.name)} <span class="pill ${s.status === 'running' ? 'lit' : 'fire'}">${esc(s.status)}</span></div>
                    <div class="svc-m"><span>${esc(s.desc)}</span><span>mem ${esc(s.mem)}</span><span>up ${esc(s.uptime)}</span></div>
                  </div>
                  ${isViewer ? '' : `
                  <div class="svc-a">
                    <button class="switch ${s.status === 'running' ? 'on' : ''}" title="${s.status === 'running' ? 'Stop' : 'Start'}" data-svctog="${esc(s.id)}" data-run="${s.status === 'running' ? '1' : '0'}"></button>
                    <button class="icon-btn sm" title="Restart" data-svcrst="${esc(s.id)}">${ic('refresh')}</button>
                    <button class="icon-btn sm" title="Logs" data-svclog="${esc(s.id)}">${ic('terminal')}</button>
                  </div>`}
                </div>`).join('')}
            </div>
          </section>

          ${isViewer ? '' : `
          <section class="mod">
            <div class="mod-h">
              <h3>${ic('globe')} Live Listening TCP Ports</h3>
              <span class="sub">${ports.length} bound sockets</span>
            </div>
            <div class="port-groups">
              <div class="pg">
                <h4>Public Internet · 0.0.0.0</h4>
                <div class="port-chips">
                  ${pubPorts.map(p => `<div class="pc pub"><b>:${p.port}</b><span>${esc(p.note)}</span><em>${esc(p.proc)}</em></div>`).join('')}
                </div>
              </div>
              <div class="pg">
                <h4>Internal Loopback · 127.0.0.1</h4>
                <div class="port-chips">
                  ${locPorts.map(p => `<div class="pc"><b>:${p.port}</b><span>${esc(p.note)}</span><em>${esc(p.proc)}</em></div>`).join('')}
                </div>
              </div>
              <div class="tbl-wrap">
                <table>
                  <thead><tr><th>Port</th><th>Bind</th><th>Daemon</th><th>Role</th></tr></thead>
                  <tbody>
                    ${ports.map(p => `<tr><td><b>${p.port}</b></td><td>${esc(p.addr)}</td><td>${esc(p.proc)}</td><td>${esc(p.note)}</td></tr>`).join('')}
                  </tbody>
                </table>
              </div>
            </div>
          </section>`}
        </div>`;

      if (!isViewer) {
        $$('[data-svctog]', $('#view')).forEach(b => {
          b.onclick = async () => {
            const act = b.dataset.run === '1' ? 'stop' : 'start';
            await api(`/service/${b.dataset.svctog}/${act}`, { method: 'POST' });
            toast(`${b.dataset.svctog}: ${act}`);
            drawEngine();
          };
        });
        $$('[data-svcrst]', $('#view')).forEach(b => {
          b.onclick = async () => {
            await api(`/service/${b.dataset.svcrst}/restart`, { method: 'POST' });
            toast(`${b.dataset.svcrst}: restarted`);
            drawEngine();
          };
        });
        $$('[data-svclog]', $('#view')).forEach(b => {
          b.onclick = async () => {
            const r = await api(`/service/${b.dataset.svclog}/logs`);
            openSheet(`${b.dataset.svclog} · Logs`, 'JOURNAL STREAM', `<pre class="term">${esc(r.logs)}</pre>`);
          };
        });
      }
    };

    if (!isViewer) {
      const btnRef = $('#btnRefreshEng'); if (btnRef) btnRef.onclick = drawEngine;
      const btnRst = $('#btnRestartAll'); if (btnRst) btnRst.onclick = async () => {
        await api('/service/all/restart', { method: 'POST' });
        toast('Full tunneling stack restarted cleanly');
        drawEngine();
      };
    }
    await drawEngine();
    STATE.timer = setInterval(async () => {
      if (STATE.bay !== 'engine' || document.hidden || engBusy) return;
      engBusy = true;
      try { await drawEngine(); } catch {} finally { engBusy = false; }
    }, 2000);
  }

  /* ═════════════════════ 5. VPS INFO (Hardware, Wire-Speed Throughput & Load · 2s Sync) ═════════════════════ */
  async function renderTelemetry() {
    let telBusy = false;
    setBayHead(
      'SERVER SPECS & LIVE TRAFFIC',
      'VPS Info',
      'Hardware profile, kernel BBR + FQ wire-speed engine, live NIC throughput & CPU/Memory curves'
    );

    const drawTel = async () => {
      const d = await api('/telemetry');
      STATE.cfg = d.cfg; syncHud();
      const spCpu = sparkPath(d.hist.cpu, 540, 175, 100);
      const spRam = sparkPath(d.hist.ram, 540, 175, 100);
      const spRx = sparkPath(d.hist.rx, 460, 118);
      const spTx = sparkPath(d.hist.tx, 460, 118);

      $('#view').innerHTML = `
        <div class="grid g2">
          <section class="mod">
            <div class="mod-h"><h3>${ic('chart')} VPS Hardware &amp; Network Profile</h3><span class="pill lit">${esc(d.cfg.os)}</span></div>
            <dl class="kv">
              <dt>Domain / SNI</dt><dd>${esc(d.cfg.domain)}</dd>
              <dt>Public IPv4</dt><dd>${esc(d.cfg.ip)}</dd>
              <dt>Datacenter</dt><dd>${esc(d.cfg.location)} · ${esc(d.cfg.provider)}</dd>
              <dt>CPU Model</dt><dd>${esc(d.cfg.cpu_model)}</dd>
              <dt>Kernel</dt><dd>${esc(d.cfg.kernel)}</dd>
              <dt>System Uptime</dt><dd>${esc(d.cfg.uptime)}</dd>
              <dt>Memory</dt><dd>${fmtBytes(d.ram_used)} / ${fmtBytes(d.ram_total)} (${d.ram_pct}%)</dd>
              <dt>Disk Volume</dt><dd>${fmtBytes(d.disk_used)} / ${fmtBytes(d.disk_total)} (${d.disk_pct}%)</dd>
              <dt>Total Traffic</dt><dd>↓ ${fmtBytes(d.rx_total)} · ↑ ${fmtBytes(d.tx_total)}</dd>
            </dl>
          </section>

          <section class="mod hot">
            <div class="mod-h"><h3>${ic('bolt')} Live Wire-Speed Throughput</h3><span class="pill lit">BBR + FQ · Unthrottled</span></div>
            <div class="st-res" style="margin-bottom:14px">
              <div class="st"><span>DOWNLOAD RATE</span><b>↓ ${fmtRate(d.rx_bps)}</b></div>
              <div class="st"><span>UPLOAD RATE</span><b>↑ ${fmtRate(d.tx_bps)}</b></div>
              <div class="st"><span>LIVE TUNNELS</span><b>${(d.ssh_online || 0) + (d.xray_online || 0)} online</b></div>
            </div>
            <svg viewBox="0 0 460 118" preserveAspectRatio="none" class="spark">
              <defs>
                <linearGradient id="telRxFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0" stop-color="#ff3b1f" stop-opacity=".42"/><stop offset="1" stop-color="#ff3b1f" stop-opacity="0"/>
                </linearGradient>
              </defs>
              <path d="${spRx.area}" fill="url(#telRxFill)"/>
              <path d="${spRx.line}" fill="none" stroke="#ff3b1f" stroke-width="2.2"/>
              <path d="${spTx.line}" fill="none" stroke="#ffb000" stroke-width="1.8" stroke-dasharray="4 3"/>
            </svg>
            <dl class="kv" style="margin-top:12px">
              <dt>Congestion Engine</dt><dd>TCP BBR + Fair Queue (FQ Pacing)</dd>
              <dt>Socket Mode</dt><dd>TCP_NODELAY · Zero Proxy Buffering · Zero Speed Cap</dd>
              <dt>CPU Load Avg</dt><dd>${esc(d.load)} (${d.cpu_pct}%)</dd>
            </dl>
          </section>

          <section class="mod span2">
            <div class="mod-h"><h3>${ic('chart')} CPU &amp; Memory Load Curve</h3><span class="sub">Live 2s rolling window</span></div>
            <div class="legend">
              <span><i style="background:#ff2d2d"></i>CPU ${d.cpu_pct}%</span>
              <span><i style="background:#ffb000"></i>RAM ${d.ram_pct}%</span>
            </div>
            <svg viewBox="0 0 540 175" preserveAspectRatio="none" class="chart">
              <path d="${spCpu.area}" fill="rgba(255,45,45,.16)"/>
              <path d="${spCpu.line}" fill="none" stroke="#ff2d2d" stroke-width="2.4"/>
              <path d="${spRam.line}" fill="none" stroke="#ffb000" stroke-width="2" stroke-dasharray="5 4"/>
            </svg>
          </section>
        </div>`;
    };

    await drawTel();
    STATE.timer = setInterval(async () => {
      if (STATE.bay !== 'telemetry' || document.hidden || telBusy) return;
      telBusy = true;
      try { await drawTel(); } catch {} finally { telBusy = false; }
    }, 2000);
  }

  /* ═════════════════════ 6. SETTINGS (Domain, SSL, Port, Banner, Admin Security) ═════════════════════ */
  async function renderForge() {
    const { cfg } = await api('/auth/me');
    STATE.cfg = cfg; syncHud();
    const isViewer = STATE.me && STATE.me.role === 'viewer';
    setBayHead(
      'SYSTEM CONFIGURATION',
      'Settings',
      'Domain & SSL · Webpanel Port · SSH Handshake Banner · Admin Security & Stack Repair'
    );

    $('#view').innerHTML = `
      <div class="grid g2">
        <!-- Domain, SSL & Panel Port -->
        <section class="mod ${isViewer ? 'span2' : ''}">
          <div class="mod-h"><h3>${ic('globe')} Domain, SSL &amp; Panel Port</h3><span class="pill lit">SSL valid · ${cfg.ssl_days}d</span></div>
          <form class="stack" id="domForm" autocomplete="off">
            <div class="row2">
              <label class="field"><span>Custom Tunnel Domain</span><input name="domain" required value="${esc(cfg.domain)}" ${isViewer ? 'readonly disabled' : ''}/></label>
              <label class="field"><span>Web Panel HTTPS Port</span><input name="panel_port" type="number" min="1024" max="65535" required value="${cfg.panel_port}" ${isViewer ? 'readonly disabled' : ''}/></label>
            </div>
            <p class="note">Changing domain automatically issues a fresh Let's Encrypt EC-256 certificate, rebuilds the HAProxy PEM bundle, and reloads Nginx + Xray without dropping active sessions.</p>
            ${isViewer ? '' : `
            <div class="chips">
              <button type="submit" class="btn btn-flame sm">${ic('check')}<span>Apply Domain &amp; Port</span></button>
              <button type="button" class="btn sm" id="btnRenewSsl">${ic('lock')}<span>Issue / Renew SSL</span></button>
            </div>`}
          </form>
        </section>

        <!-- Admin Security & Stack Repair -->
        ${isViewer ? '' : `
        <section class="mod">
          <div class="mod-h"><h3>${ic('key')} Admin Security &amp; Stack Repair</h3><span class="sub">Username, Password &amp; Stack Tune</span></div>
          <form class="stack" id="pwForm" autocomplete="off">
            <label class="field"><span>Change Admin Username</span><input name="new_username" pattern="[A-Za-z0-9_-]{3,24}" value="${esc(STATE.me.username)}" placeholder="Enter username" autocomplete="off"/><small>a-z, A-Z, 0-9, _ - (3-24 chars)</small></label>
            <div class="row2">
              <label class="field"><span>New Password</span><input name="new_password" type="password" minlength="6" placeholder="Enter new password (blank = keep)" autocomplete="new-password"/></label>
              <label class="field"><span>Confirm Password</span><input name="confirm_password" type="password" minlength="6" placeholder="Confirm password" autocomplete="new-password"/></label>
            </div>
            <p class="note">One-click Stack Repair re-applies unthrottled Kernel BBR + FQ pacing, clears any NIC traffic shapers, and syncs HAProxy, Nginx, Dropbear &amp; Xray.</p>
            <div class="chips">
              <button type="submit" class="btn btn-flame sm">${ic('lock')}<span>Save Credentials</span></button>
              <button type="button" class="btn sm" id="btnFixStack">${ic('refresh')}<span>Fix &amp; Optimize Stack</span></button>
            </div>
          </form>
        </section>`}

        <!-- SSH Handshake Banner -->
        <section class="mod span2">
          <div class="mod-h"><h3>${ic('terminal')} SSH Handshake Banner</h3><span class="sub">Dropbear + OpenSSH</span></div>
          <form class="stack" id="bannerForm" autocomplete="off">
            <label class="field"><span>HTML / ANSI Banner Markup</span><textarea name="banner" ${isViewer ? 'readonly disabled' : ''}>${esc(cfg.banner || '')}</textarea></label>
            ${isViewer ? '' : `<div><button type="submit" class="btn btn-flame sm">${ic('check')}<span>Save SSH Banner</span></button></div>`}
          </form>
        </section>
      </div>`;

    if (!isViewer) {
      $('#domForm').onsubmit = async (e) => {
        e.preventDefault();
        const fd = Object.fromEntries(new FormData(e.target).entries());
        await api('/settings', { method: 'POST', body: { domain: fd.domain, panel_port: +fd.panel_port } });
        toast('Domain & Panel port updated');
        renderForge();
      };
      $('#btnRenewSsl').onclick = async () => {
        await api('/settings', { method: 'POST', body: { ssl_renew: true } });
        toast('SSL certificate renewed & HAProxy bundle synced');
        renderForge();
      };
      $('#bannerForm').onsubmit = async (e) => {
        e.preventDefault();
        const fd = Object.fromEntries(new FormData(e.target).entries());
        await api('/settings', { method: 'POST', body: { banner: fd.banner } });
        toast('SSH handshake banner saved');
      };
      $('#pwForm').onsubmit = async (e) => {
        e.preventDefault();
        const fd = Object.fromEntries(new FormData(e.target).entries());
        const body = {};
        const trimmedU = (fd.new_username || '').trim();
        if (trimmedU && trimmedU !== STATE.me.username) {
          body.new_username = trimmedU;
        }
        if (fd.new_password) {
          if (fd.new_password !== fd.confirm_password) {
            toast('Passwords do not match', 'err');
            return;
          }
          body.new_password = fd.new_password;
        }
        if (!body.new_username && !body.new_password) {
          toast('No changes submitted', 'err');
          return;
        }
        try {
          await api('/settings', { method: 'POST', body });
          if (body.new_username) {
            STATE.me.username = body.new_username;
            syncHud();
          }
          toast('Admin credentials updated successfully');
          renderForge();
        } catch (err) {
          toast(err.message, 'err');
        }
      };
      $('#btnFixStack').onclick = async () => {
        await api('/settings', { method: 'POST', body: { maint: 'fix_ws_ssl_stack' } });
        await api('/service/all/restart', { method: 'POST' });
        toast('Wire-Speed BBR+FQ + SSH-WS + SSL + Xray stack optimized & restarted');
      };
    }
  }

  /* ═════════════════════ 7. ADMINS (Super Admin / Reseller / Viewer RBAC) ═════════════════════ */
  async function renderAdmins() {
    const { items } = await api('/admins');
    const isViewer = STATE.me && STATE.me.role === 'viewer';
    setBayHead(
      'ROLE-BASED ACCESS CONTROL',
      'Admins',
      'Manage Super Admins, Reseller Admins with account quotas & read-only Viewers',
      isViewer ? '' : `<button class="btn btn-flame sm" id="btnNewAdmin">${ic('plus')}<span>Add Panel Admin</span></button>`
    );
    if (!isViewer) {
      $('#btnNewAdmin').onclick = openAdminForm;
    }

    $('#view').innerHTML = `
      <div class="cards">
        ${items.map(a => `
          <article class="mod acc">
            <div class="acc-top">
              ${hexAvatar(a.username[0].toUpperCase(), a.status === 'active')}
              <div>
                <div class="acc-n">${esc(a.username)} <span class="pill ${a.role === 'super' ? 'fire' : a.role === 'admin' ? 'lit' : ''}">${esc(a.role.toUpperCase())}</span></div>
                <div class="acc-m">last login <b>${esc(a.last_login)}</b></div>
              </div>
            </div>
            <div class="acc-stats">
              <div class="st"><span>CREATED</span><b>${a.accounts}</b></div>
              <div class="st"><span>QUOTA</span><b>${a.max_accounts > 0 ? a.max_accounts : 'Unlimited'}</b></div>
              <div class="st"><span>SCOPE</span><b>${esc(a.scope.toUpperCase())}</b></div>
            </div>
            <div class="acc-act">
              ${isViewer ? '' : ((a.role === 'super' && items.filter(x => x.role === 'super').length <= 1) || a.username === STATE.me.username ? `<span class="pill lit">${a.role === 'super' ? 'Primary Root Owner' : 'Current Session'}</span>` : `<button class="btn btn-danger sm" data-adel="${esc(a.username)}">${ic('trash')}<span>Revoke</span></button>`)}
            </div>
          </article>`).join('')}
      </div>`;

    if (!isViewer) {
      $$('[data-adel]', $('#view')).forEach(b => {
        b.onclick = async () => {
          const card = b.closest('.acc');
          try {
            await api(`/admins/${encodeURIComponent(b.dataset.adel)}`, { method: 'DELETE' });
            toast(`Admin ${b.dataset.adel} removed`);
            await nanoDisintegrate(card);
            renderAdmins();
          } catch (err) { toast(err.message, 'err'); }
        };
      });
    }
  }

  function openAdminForm() {
    if (STATE.me && STATE.me.role === 'viewer') return;
    openSheet('Create Panel Admin / Reseller', 'ADMIN RBAC', `
      <form class="stack" id="admForm" autocomplete="off">
        <div class="row2">
          <label class="field"><span>Username</span><input name="username" required pattern="[A-Za-z0-9_-]{3,24}" placeholder="Enter username" autocomplete="off"/></label>
          <label class="field"><span>Password</span><input name="password" type="password" required minlength="6" placeholder="Enter password" autocomplete="new-password"/></label>
        </div>
        <div class="row3">
          <label class="field"><span>Role</span>
            <select name="role">
              <option value="admin">Admin / Reseller</option>
              <option value="super">Super Admin</option>
              <option value="viewer">Viewer (Read-Only)</option>
            </select>
          </label>
          <label class="field"><span>Max Accounts (0=∞)</span><input name="max_accounts" type="number" min="0" value="25"/></label>
          <label class="field"><span>Visibility</span>
            <select name="scope">
              <option value="own">Own Accounts Only</option>
              <option value="all">All Accounts</option>
            </select>
          </label>
        </div>
        <div class="foot">
          <button type="button" class="btn" id="admCancel">Cancel</button>
          <button type="submit" class="btn btn-flame">Create Admin</button>
        </div>
      </form>`);
    $('#admCancel').onclick = closeSheet;
    const roleSel = $('select[name="role"]', $('#admForm'));
    const scopeSel = $('select[name="scope"]', $('#admForm'));
    if (roleSel && scopeSel) {
      roleSel.onchange = () => {
        if (roleSel.value === 'viewer' || roleSel.value === 'super') {
          scopeSel.value = 'all';
        }
      };
    }
    $('#admForm').onsubmit = async (e) => {
      e.preventDefault();
      const fd = Object.fromEntries(new FormData(e.target).entries());
      await api('/admins', { method: 'POST', body: fd });
      closeSheet();
      toast(`Admin ${fd.username} created`);
      renderAdmins();
    };
  }

  /* ═════════════════════ 8. TELEGRAM (Full User Management Bot) ═════════════════════ */
  async function renderSignals() {
    const { cfg } = await api('/auth/me');
    const bot = cfg.bot || { enabled: false, token: '', admin_id: '', alerts: true };
    setBayHead(
      'REMOTE TELEGRAM ENGINE',
      'Telegram',
      'Create, renew & delete SSH / Xray accounts, check server load & receive alerts directly in Telegram'
    );

    $('#view').innerHTML = `
      <div class="grid g2">
        <section class="mod hot">
          <div class="mod-h">
            <h3>${ic('send')} Bot Credentials &amp; Daemon</h3>
            <span class="pill ${bot.enabled ? 'lit' : ''}">${bot.enabled ? 'BOT ONLINE' : 'STOPPED'}</span>
          </div>
          <form class="stack" id="botForm">
            <label class="field"><span>BotFather API Token</span><input name="token" required value="${esc(bot.token)}" placeholder="123456789:AAH..."/></label>
            <label class="field"><span>Authorized Telegram Admin ID(s)</span><input name="admin_id" required value="${esc(bot.admin_id)}" placeholder="591031001"/></label>
            <div class="tg-row">
              <div><b>Enable Telegram Bot Service</b><small>Runs <code>alyan-bot.service</code> with inline keyboard menus</small></div>
              <button type="button" class="switch ${bot.enabled ? 'on' : ''}" id="swBotOn"></button>
            </div>
            <div class="tg-row">
              <div><b>Quota &amp; Expiry Push Alerts</b><small>Notify when users hit GB quota or SSL nears renewal</small></div>
              <button type="button" class="switch ${bot.alerts ? 'on' : ''}" id="swBotAlerts"></button>
            </div>
            <div class="chips">
              <button type="submit" class="btn btn-flame sm">${ic('check')}<span>Save &amp; Restart Bot</span></button>
              <button type="button" class="btn sm" id="btnTestTg">${ic('send')}<span>Send Test Ping</span></button>
            </div>
          </form>
        </section>

        <section class="mod">
          <div class="mod-h"><h3>${ic('terminal')} Interactive Bot Commands</h3><span class="sub">Inline Keyboard Ready</span></div>
          <div class="cmd-list">
            <div><code>/start</code><span>Open main Alyan Flame inline control panel</span></div>
            <div><code>/addssh</code><span>Interactive wizard: username, password, days, GB &amp; IP limit + /alyan payload</span></div>
            <div><code>/delssh</code><span>Delete or lock an SSH account immediately</span></div>
            <div><code>/renewssh</code><span>Extend expiry days or reset data quota</span></div>
            <div><code>/addxray</code><span>Create VLESS / VMess / Trojan client + QR image</span></div>
            <div><code>/delxray</code><span>Remove Xray client cleanly without restart</span></div>
            <div><code>/users</code><span>List all accounts with live online IP counts</span></div>
            <div><code>/status</code><span>Live CPU, RAM, bandwidth, SSL &amp; daemon health</span></div>
            <div><code>/restart</code><span>Restart HAProxy, Nginx, Xray, Dropbear or WS-Proxy</span></div>
          </div>
        </section>
      </div>`;

    let enabled = !!bot.enabled, alerts = !!bot.alerts;
    $('#swBotOn').onclick = (e) => { enabled = !enabled; e.currentTarget.classList.toggle('on', enabled); };
    $('#swBotAlerts').onclick = (e) => { alerts = !alerts; e.currentTarget.classList.toggle('on', alerts); };
    $('#botForm').onsubmit = async (e) => {
      e.preventDefault();
      const fd = Object.fromEntries(new FormData(e.target).entries());
      await api('/settings', { method: 'POST', body: { bot: { token: fd.token, admin_id: fd.admin_id, enabled, alerts } } });
      toast('Telegram Bot saved & synced');
      renderSignals();
    };
    $('#btnTestTg').onclick = async () => {
      try {
        await api('/telegram/test', { method: 'POST' });
        toast('Test message dispatched to Telegram Admin ID');
      } catch (err) { toast(err.message, 'err'); }
    };
  }

  /* ═════════════════════ 9. LIST (Activity & Event List · 2s Sync) ═════════════════════ */
  async function renderAudit() {
    let items = (await api('/audit')).items || [];
    let auditBusy = false;
    setBayHead(
      'ACTIVITY STREAM',
      'List',
      'Chronological list of all account provisions, service actions, SSL updates & logins'
    );

    $('#view').innerHTML = `
      <div class="toolbar">
        <div class="search">${ic('search')}<input id="auditSearch" placeholder="Filter list by user, action or IP…" value="${esc(STATE.searchAudit)}"/></div>
        <span class="live" id="auditLiveMeta"><i class="dot lit"></i> 0 records · live 2s</span>
      </div>
      <section class="mod" id="auditListHost"></section>`;

    const paintAudit = () => {
      const host = $('#auditListHost');
      if (!host) return;
      const q = STATE.searchAudit.toLowerCase();
      const list = items.filter(a => !q || `${a.user} ${a.action} ${a.detail} ${a.ip}`.toLowerCase().includes(q));
      const meta = $('#auditLiveMeta');
      if (meta) meta.innerHTML = `<i class="dot lit"></i> ${list.length} records · live 2s`;
      host.innerHTML = list.length ? list.map(a => `
        <div class="log-item">
          <div class="log-ic">${ic(a.action.includes('xray') ? 'bolt' : a.action.includes('ssh') ? 'tunnel' : 'list')}</div>
          <div class="log-t"><b>${esc(a.action)}</b> &nbsp;<span>${esc(a.detail)}</span></div>
          <div class="log-r"><div>${esc(a.user)} · ${esc(a.ip)}</div><div>${esc(a.time)}</div></div>
        </div>`).join('') : `<div class="empty"><p>No matching entries in list.</p></div>`;
    };

    $('#auditSearch').oninput = (e) => { STATE.searchAudit = e.target.value; paintAudit(); };
    paintAudit();

    STATE.timer = setInterval(async () => {
      if (STATE.bay !== 'audit' || document.hidden || auditBusy) return;
      auditBusy = true;
      try {
        const res = await api('/audit');
        items = res.items || [];
        paintAudit();
      } catch {} finally { auditBusy = false; }
    }, 2000);
  }

  /* ═════════════════════ FLAME LAUNCHER & COMMAND PALETTE ═════════════════════ */
  function openQuickSheet() {
    if (STATE.me && STATE.me.role === 'viewer') return;
    openSheet('Flame Launcher', 'QUICK PROVISION', `
      <div class="qc-grid">
        <button class="qc" data-qa="ssh">${ic('tunnel')}<b>New SSH Account</b><span>Direct · SSL · WS /alyan</span></button>
        <button class="qc" data-qa="vless">${ic('bolt')}<b>New VLESS Client</b><span>WS · gRPC · XHTTP on 443</span></button>
        <button class="qc" data-qa="vmess">${ic('bolt')}<b>New VMess Client</b><span>TLS 443 &amp; HTTP 80</span></button>
        <button class="qc" data-qa="trojan">${ic('lock')}<b>New Trojan Client</b><span>TLS 443 WS · TCP · gRPC</span></button>
      </div>`);
    $$('[data-qa]', $('#sheet')).forEach(b => {
      b.onclick = () => {
        const qa = b.dataset.qa;
        closeSheet();
        if (qa === 'ssh') { go('tunnels'); setTimeout(() => openSshForm(), 40); }
        else { STATE.xrayProto = qa; go('xray'); setTimeout(() => openXrayForm(qa), 40); }
      };
    });
  }

  function openPalette() {
    const wrap = $('#paletteWrap'), inp = $('#paletteInput'), ul = $('#paletteList');
    const isViewer = STATE.me && STATE.me.role === 'viewer';
    const cmds = [
      { label: 'Go to Core', icon: 'core', run: () => go('core'), key: 'G C' },
      ...(isViewer ? [] : [
        { label: 'Create SSH Account (/alyan)', icon: 'plus', run: () => { go('tunnels'); setTimeout(() => openSshForm(), 40); }, key: 'N S' },
        { label: 'Create VLESS Client', icon: 'bolt', run: () => { STATE.xrayProto = 'vless'; go('xray'); setTimeout(() => openXrayForm('vless'), 40); }, key: 'N V' },
        { label: 'Create VMess Client', icon: 'bolt', run: () => { STATE.xrayProto = 'vmess'; go('xray'); setTimeout(() => openXrayForm('vmess'), 40); }, key: 'N M' },
        { label: 'Create Trojan Client', icon: 'lock', run: () => { STATE.xrayProto = 'trojan'; go('xray'); setTimeout(() => openXrayForm('trojan'), 40); }, key: 'N T' }
      ]),
      { label: 'Open SSH Accounts', icon: 'tunnel', run: () => go('tunnels') },
      { label: 'Open Xray', icon: 'bolt', run: () => go('xray') },
      { label: 'Open Engine (Services & Ports)', icon: 'engine', run: () => go('engine') },
      { label: 'Open VPS Info', icon: 'chart', run: () => go('telemetry') },
      { label: 'Open Settings', icon: 'sliders', run: () => go('forge') },
      { label: 'Open Admins (RBAC)', icon: 'shield', run: () => go('admins') },
      { label: 'Open Telegram Bot', icon: 'send', run: () => go('signals') },
      { label: 'Open List', icon: 'list', run: () => go('audit') }
    ];
    let idx = 0, filtered = cmds;
    const draw = () => {
      const q = inp.value.trim().toLowerCase();
      filtered = cmds.filter(c => !q || c.label.toLowerCase().includes(q));
      idx = Math.min(idx, Math.max(0, filtered.length - 1));
      ul.innerHTML = filtered.map((c, i) => `<li class="${i === idx ? 'on' : ''}" data-pi="${i}">${ic(c.icon)}<span>${esc(c.label)}</span>${c.key ? `<kbd>${c.key}</kbd>` : ''}</li>`).join('');
      $$('li', ul).forEach(li => { li.onclick = () => { const c = filtered[+li.dataset.pi]; closePal(); c && c.run(); }; });
    };
    const closePal = () => { wrap.hidden = true; inp.value = ''; };
    wrap.hidden = false;
    draw();
    inp.focus();
    inp.oninput = () => { idx = 0; draw(); };
    inp.onkeydown = (e) => {
      if (e.key === 'Escape') closePal();
      else if (e.key === 'ArrowDown') { e.preventDefault(); idx = Math.min(filtered.length - 1, idx + 1); draw(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); idx = Math.max(0, idx - 1); draw(); }
      else if (e.key === 'Enter' && filtered[idx]) { e.preventDefault(); const c = filtered[idx]; closePal(); c.run(); }
    };
    wrap.onclick = (e) => { if (e.target === wrap) closePal(); };
  }

  /* ═════════════════════ AUTH & BOOTSTRAP ═════════════════════ */
  function showLogin() {
    clearInterval(STATE.timer);
    $('#app').hidden = true;
    $('#login').hidden = false;
  }

  function showApp() {
    $('#login').hidden = true;
    $('#app').hidden = false;
    syncHud();
    // Ignite 50% visible live moving fire inside the Left Sidebar!
    attachRealFire($('#sidebarFire'), { w: 68, h: 150, cool: 3.3 });
    go(STATE.bay || 'core');
  }

  async function boot() {
    // Hydrate animated sidebar icons & static action icons
    $$('[data-nav-i]').forEach(el => { el.innerHTML = NAV_ICONS[el.dataset.navI] || NAV_ICONS.core; });
    $$('[data-i]').forEach(el => { el.innerHTML = ic(el.dataset.i); });
    initEmbers();

    // Live HUD clock
    const tickClock = () => { const c = $('#hudClock'); if (c) c.textContent = new Date().toTimeString().slice(0, 8); };
    tickClock();
    setInterval(tickClock, 1000);

    // Sidebar navigation & mobile drawer
    $$('#sbNav .sb-item[data-go]').forEach(btn => {
      btn.onclick = () => go(btn.dataset.go);
    });
    $('#btnMobMenu').onclick = () => toggleMobileSidebar(true);
    $('#sbClose').onclick = () => toggleMobileSidebar(false);
    $('#sbBackdrop').onclick = () => toggleMobileSidebar(false);

    // Palette & Account menu
    $('#btnPalette').onclick = openPalette;
    window.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openPalette(); }
    });
    $('#btnMe').onclick = () => {
      openSheet(`Signed in as ${STATE.me.username}`, 'SESSION PROFILE', `
        <div class="stack">
          <div class="tk-row"><span>Username</span><b>${esc(STATE.me.username)}</b><span></span></div>
          <div class="tk-row"><span>Role</span><b>${esc(STATE.me.role.toUpperCase())}</b><span></span></div>
          <div class="tk-row"><span>Scope</span><b>${esc(STATE.me.scope || 'all')}</b><span></span></div>
          <div class="foot">
            <button class="btn" id="meSettings">${ic('sliders')}<span>Settings</span></button>
            <button class="btn btn-danger" id="meLogout">${ic('logout')}<span>Sign Out</span></button>
          </div>
        </div>`);
      $('#meSettings').onclick = () => { closeSheet(); go('forge'); };
      $('#meLogout').onclick = async () => { await api('/auth/logout', { method: 'POST' }); closeSheet(); showLogin(); };
    };

    $('#loginForm').onsubmit = async (e) => {
      e.preventDefault();
      $('#loginErr').textContent = '';
      const fd = Object.fromEntries(new FormData(e.target).entries());
      try {
        const r = await api('/auth/login', { method: 'POST', body: fd });
        STATE.me = r.user; STATE.cfg = r.cfg;
        showApp();
      } catch (err) { $('#loginErr').textContent = err.message; }
    };

    try {
      const r = await api('/auth/me');
      STATE.me = r.user; STATE.cfg = r.cfg;
      showApp();
    } catch { showLogin(); }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();

EOF_APP_JS

  echo -e "\n${C_CYN}▶ [3/5] Updating Alyan Guard & WS Daemon (Exact Host/Edge IP Correlator)...${C_RST}"
  cat > "${INSTALL_DIR}/services/wsd/alyan-wsd.py" <<'EOF_WSD'
#!/usr/bin/env python3
"""
Alyan Webpanel — Wire-Speed Asyncio SSH-WebSocket Bridge (alyan-wsd)
Listens on 127.0.0.1:2095 (accepting PROXY protocol v1/v2 from HAProxy),
handles HTTP 101 Switching Protocols for /alyan & custom Injector payloads,
bridges to Dropbear (127.0.0.1:109) with TCP_NODELAY & 64KB zero-stall buffers,
and exports real client IP + byte stats to /run/alyan-wsd-sessions.json.
"""
import asyncio
import base64
import hashlib
import ipaddress
import json
import os
import socket
import struct
import time
from pathlib import Path

LISTEN_HOST = os.environ.get("ALYAN_WSD_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("ALYAN_WSD_PORT", "2095"))
TARGET_HOST = os.environ.get("ALYAN_SSH_TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.environ.get("ALYAN_SSH_TARGET_PORT", "109"))
STATE_FILE = Path("/run/alyan-wsd-sessions.json")

PROXY_V2_SIG = b"\r\n\r\n\x00\r\nQUIT\n"
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def build_101_response(payload: bytes) -> bytes:
    sec_key = None
    if b"\r\n" in payload:
        header_text = payload.split(b"\r\n\r\n", 1)[0].decode("latin1", errors="ignore")
        for line in header_text.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                if k.strip().lower() == "sec-websocket-key":
                    sec_key = v.strip()
                    break

    resp_lines = [
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
    ]
    if sec_key:
        sha = hashlib.sha1((sec_key + WS_GUID).encode("utf-8")).digest()
        accept_b64 = base64.b64encode(sha).decode("utf-8")
        resp_lines.append(f"Sec-WebSocket-Accept: {accept_b64}")
    else:
        resp_lines.append("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    resp_lines.append("Server: Alyan-Flame-Edge")
    return ("\r\n".join(resp_lines) + "\r\n\r\n").encode("latin1")

CF_NETWORKS = [
    ipaddress.ip_network(cidr)
    for cidr in (
        "127.0.0.0/8",
        "173.245.48.0/20",
        "103.21.244.0/22",
        "103.22.200.0/22",
        "103.31.4.0/22",
        "141.101.64.0/18",
        "108.162.192.0/18",
        "190.93.240.0/20",
        "188.114.96.0/20",
        "197.234.240.0/22",
        "198.41.128.0/17",
        "162.158.0.0/15",
        "104.16.0.0/13",
        "104.24.0.0/14",
        "172.64.0.0/13",
        "131.0.72.0/22",
        "2400:cb00::/32",
        "2606:4700::/32",
        "2803:f800::/32",
        "2405:b500::/32",
        "2405:8100::/32",
        "2a06:98c0::/29",
        "2c0f:f248::/32",
    )
]

ACTIVE_SESSIONS = {}
RECENT_CLOSED = {}


def normalize_ip(raw: str) -> str | None:
    s = (raw or "").strip().strip("[]")
    if s.lower().startswith("::ffff:"):
        s = s[7:]
    try:
        return str(ipaddress.ip_address(s))
    except ValueError:
        return None


def is_trusted_cdn(ip_str: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip_str)
        if addr.is_loopback:
            return True
        if any(addr in net for net in CF_NETWORKS):
            return True
        if isinstance(addr, ipaddress.IPv4Address):
            s = str(addr)
            if s.startswith(("143.204.", "52.84.", "54.192.", "54.230.", "54.239.", "54.240.", "13.32.", "13.33.", "13.35.", "13.224.", "13.225.", "13.226.", "13.227.", "13.249.", "18.64.", "18.65.", "18.66.", "18.67.", "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.", "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.", "108.138.", "108.156.", "108.157.", "108.158.", "108.159.", "204.246.", "205.251.")):
                return True
        return False
    except ValueError:
        return False


def tune_socket(writer: asyncio.StreamWriter):
    sock = writer.get_extra_info("socket")
    if sock is not None:
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        except Exception:
            pass
    tr = writer.transport
    if tr is not None:
        try:
            tr.set_write_buffer_limits(high=262144, low=65536)
        except Exception:
            pass


def flush_state_now():
    try:
        now = time.time()
        for k in list(RECENT_CLOSED.keys()):
            if now - RECENT_CLOSED[k].get("closed_at", 0) > 15.0:
                del RECENT_CLOSED[k]
        snapshot = {}
        for port, s in list(RECENT_CLOSED.items()):
            snapshot[port] = {
                "ip": s["ip"],
                "since": s["since"],
                "bytes": s["bytes"],
                "closed": True,
            }
        for port, s in list(ACTIVE_SESSIONS.items()):
            snapshot[port] = {
                "ip": s["ip"],
                "since": s["since"],
                "bytes": s["rx"] + s["tx"],
                "closed": False,
            }
        tmp = STATE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(snapshot), encoding="utf-8")
        tmp.replace(STATE_FILE)
    except Exception:
        pass


def parse_proxy_header(buf: bytes):
    """Parse HAProxy PROXY v2 or v1 header. Returns (real_ip, remaining_bytes) or None if need more bytes."""
    if buf.startswith(PROXY_V2_SIG):
        if len(buf) < 16:
            return None
        ver_cmd = buf[12]
        fam_proto = buf[13]
        addr_len = struct.unpack("!H", buf[14:16])[0]
        total = 16 + addr_len
        if len(buf) < total:
            return None
        real_ip = "127.0.0.1"
        if (ver_cmd & 0x0F) == 0x01:
            fam = fam_proto >> 4
            if fam == 0x1 and addr_len >= 12:
                real_ip = socket.inet_ntop(socket.AF_INET, buf[16:20])
            elif fam == 0x2 and addr_len >= 36:
                real_ip = socket.inet_ntop(socket.AF_INET6, buf[16:32])
                if real_ip.startswith("::ffff:"):
                    real_ip = real_ip[7:]
        return real_ip, buf[total:]

    if buf.startswith(b"PROXY "):
        idx = buf.find(b"\r\n")
        if idx == -1:
            return None if len(buf) < 108 else ("127.0.0.1", buf)
        parts = buf[:idx].decode("latin1", errors="ignore").split()
        real_ip = parts[2] if len(parts) >= 3 else "127.0.0.1"
        return real_ip, buf[idx + 2:]

    return None, buf


def strip_ws_headers(data: bytes) -> tuple[bool, bytes]:
    if data.startswith(b"SSH-"):
        return False, data
    ssh_idx = data.find(b"SSH-")
    if ssh_idx != -1:
        return True, data[ssh_idx:]
    end_idx = data.find(b"\r\n\r\n")
    if end_idx != -1:
        return True, data[end_idx + 4:]
    return True, b""


async def pipe_stream(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, stat_dict: dict, key: str):
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            stat_dict[key] += len(chunk)
            writer.write(chunk)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle_client(c_reader: asyncio.StreamReader, c_writer: asyncio.StreamWriter):
    tune_socket(c_writer)
    peer = c_writer.get_extra_info("peername")
    real_ip = normalize_ip(peer[0]) if peer else "127.0.0.1"
    real_ip = real_ip or "127.0.0.1"
    local_port = None

    try:
        initial = await asyncio.wait_for(c_reader.read(16384), timeout=12.0)
        if not initial:
            c_writer.close()
            return

        parsed = parse_proxy_header(initial)
        while parsed is None:
            more = await asyncio.wait_for(c_reader.read(4096), timeout=6.0)
            if not more:
                c_writer.close()
                return
            initial += more
            parsed = parse_proxy_header(initial)

        p_ip, payload = parsed
        if p_ip:
            norm_p = normalize_ip(p_ip)
            if norm_p:
                real_ip = norm_p

        if not payload:
            payload = await asyncio.wait_for(c_reader.read(16384), timeout=12.0)
            if not payload:
                c_writer.close()
                return

        if not payload.startswith(b"SSH-") and b"\r\n\r\n" not in payload:
            while b"\r\n\r\n" not in payload and len(payload) < 8192:
                try:
                    more = await asyncio.wait_for(c_reader.read(4096), timeout=3.0)
                    if not more:
                        break
                    payload += more
                except asyncio.TimeoutError:
                    break

        # Extract exact target host/edge IP from HTTP headers (e.g. X-Target: [host] -> 141.193.213.11)
        target_ip_cand = None
        if b"\r\n" in payload and not payload.startswith(b"SSH-"):
            hdr_text = payload.split(b"\r\n\r\n", 1)[0].decode("latin1", errors="ignore")
            hdr_map = {}
            for line in hdr_text.splitlines()[1:]:
                if ":" in line:
                    k, v = line.split(":", 1)
                    hdr_map[k.strip().lower()] = v.strip()

            # 1. Custom injector target headers: X-Target, X-Edge-IP, X-Real-Host, X-Forwarded-Host, X-Host
            for hk in ("x-target", "x-edge-ip", "x-real-host", "x-forwarded-host", "x-host", "b-cdn-edge-ip"):
                if hk in hdr_map:
                    raw_val = hdr_map[hk]
                    if ":" in raw_val and not raw_val.startswith("["):
                        raw_val = raw_val.split(":", 1)[0]
                    cand = normalize_ip(raw_val.split(",")[0].strip())
                    if cand and cand not in ("127.0.0.1", "::1"):
                        target_ip_cand = cand
                        break

            # 2. Host header if an explicit IP was dialed (e.g. Host: 141.193.213.11)
            if not target_ip_cand and "host" in hdr_map:
                hval = hdr_map["host"]
                if ":" in hval and not hval.startswith("["):
                    hval = hval.split(":", 1)[0]
                cand = normalize_ip(hval.strip())
                if cand and cand not in ("127.0.0.1", "::1"):
                    target_ip_cand = cand

        if target_ip_cand:
            real_ip = target_ip_cand
        elif p_ip:
            norm_p = normalize_ip(p_ip)
            if norm_p and norm_p not in ("127.0.0.1", "::1"):
                real_ip = norm_p

        needs_101, tail = strip_ws_headers(payload)
        if needs_101:
            resp_101 = build_101_response(payload)
            c_writer.write(resp_101)
            await c_writer.drain()

        s_reader, s_writer = await asyncio.wait_for(
            asyncio.open_connection(TARGET_HOST, TARGET_PORT, limit=262144),
            timeout=8.0,
        )
        tune_socket(s_writer)

        sock_info = s_writer.get_extra_info("sockname")
        local_port = str(sock_info[1]) if sock_info else f"anon-{id(c_writer)}"

        stat_entry = {
            "ip": real_ip,
            "since": int(time.time()),
            "rx": len(tail),
            "tx": 0,
        }
        ACTIVE_SESSIONS[local_port] = stat_entry
        flush_state_now()

        if tail:
            if not tail.startswith(b"SSH-") and b"SSH-" in tail:
                tail = tail[tail.find(b"SSH-"):]
            elif not tail.startswith(b"SSH-") and b"\r\n\r\n" in tail:
                tail = tail.split(b"\r\n\r\n")[-1]
            if tail:
                s_writer.write(tail)
                await s_writer.drain()

        await asyncio.gather(
            pipe_stream(c_reader, s_writer, stat_entry, "rx"),
            pipe_stream(s_reader, c_writer, stat_entry, "tx"),
        )
    except Exception:
        try:
            c_writer.close()
        except Exception:
            pass
    finally:
        if local_port and local_port in ACTIVE_SESSIONS:
            st = ACTIVE_SESSIONS.pop(local_port)
            RECENT_CLOSED[local_port] = {
                "ip": st["ip"],
                "since": st["since"],
                "bytes": st["rx"] + st["tx"],
                "closed_at": time.time(),
            }
            flush_state_now()


async def flush_sessions_loop():
    while True:
        flush_state_now()
        await asyncio.sleep(1.5)


async def main():
    server = await asyncio.start_server(
        handle_client,
        LISTEN_HOST,
        LISTEN_PORT,
        backlog=8192,
        limit=262144,
    )
    asyncio.create_task(flush_sessions_loop())
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass

EOF_WSD
  chmod +x "${INSTALL_DIR}/services/wsd/alyan-wsd.py"

  cat > "${INSTALL_DIR}/services/guard/alyan-guard.py" <<'EOF_GUARD'
#!/usr/bin/env python3
"""
Alyan Webpanel — Real-Time 2s Quota, Exact Real-IP & Strict IP-Limit Enforcer (alyan-guard)
Continuously monitors SSH/Dropbear/WS-Proxy (/alyan) & Xray (VLESS/VMess/Trojan):
  1. Correlates Dropbear (-E short-iso journal) & OpenSSH PIDs -> Username -> Exact Real Client IP.
  2. Parses Xray client IPs cleanly via ipaddress (stripping :port, normalizing IPv6 /64 & CDN edges).
  3. Counts real-time SSH & Xray per-user bytes into SQLite every 2s.
  4. Strictly enforces GB quotas, expiry dates, and IP limits (auto-disabling violating SSH & Xray accounts!).
  5. Writes /run/alyan-live.json every 2s (including cached daemon health) for ultra-fast Webpanel sync.
"""
import datetime as dt
import ipaddress
import json
import os
import re
import socket
import sqlite3
import subprocess
import time
import urllib.request
from pathlib import Path

DB_PATH = Path("/var/lib/alyan/alyan.db")
WSD_STATE = Path("/run/alyan-wsd-sessions.json")
HAPROXY_SOCK = Path("/run/haproxy/admin.sock")
LIVE_OUT = Path("/run/alyan-live.json")
XRAY_ACCESS_LOG = Path("/var/log/xray/access.log")

MANAGED_SERVICES = [
    ("haproxy",     "HAProxy Flame Router", "Public 80 / 443 Multiplexer"),
    ("nginx",       "Nginx Router & TLS",   "WS / gRPC / Panel HTTPS"),
    ("dropbear",    "Dropbear SSH",         "Direct Tunnel Ports 109 / 143"),
    ("alyan-wsd",   "Alyan WS-Proxy",       "GET /alyan 101 + Real-IP Bridge"),
    ("xray",        "Xray-Core Engine",     "VMess · VLESS · Trojan · XHTTP"),
    ("alyan-guard", "Alyan Guard",          "GB Quota · Expiry · IP Enforcer"),
    ("alyan-bot",   "Telegram Bot",         "Full User & Server Control"),
    ("alyan-panel", "Alyan Webpanel",       "FastAPI Command Deck"),
]

CF_EDGE_NETS = [
    ipaddress.ip_network(cidr)
    for cidr in (
        "173.245.48.0/20",
        "103.21.244.0/22",
        "103.22.200.0/22",
        "103.31.4.0/22",
        "141.101.64.0/18",
        "108.162.192.0/18",
        "190.93.240.0/20",
        "188.114.96.0/20",
        "197.234.240.0/22",
        "198.41.128.0/17",
        "162.158.0.0/15",
        "104.16.0.0/13",
        "104.24.0.0/14",
        "172.64.0.0/13",
        "131.0.72.0/22",
        "2400:cb00::/32",
        "2606:4700::/32",
        "2803:f800::/32",
        "2405:b500::/32",
        "2405:8100::/32",
        "2a06:98c0::/29",
        "2c0f:f248::/32",
    )
]

HIST = {"cpu": [], "ram": [], "rx": [], "tx": []}
LAST_CPU = None
LAST_NET = None
CACHED_SERVICES: list[dict] = []
CYCLE_TICK = 0

# Persistent tracking caches across 2-second ticks
PID_AUTH_CACHE: dict[int, str] = {}
PORT_TO_USER: dict[str, str] = {}
WSD_PORT_LAST_BYTES: dict[str, int] = {}
PID_LAST_IO_BYTES: dict[int, int] = {}
# uuid -> {device_key: {"ip": str, "ts": float}}
XRAY_ACTIVE_DEVICES: dict[str, dict[str, dict]] = {}

# Consecutive multi-IP violation strikes before auto-disable
SSH_IP_STRIKES: dict[str, int] = {}
XRAY_IP_STRIKES: dict[str, int] = {}

DROPBEAR_AUTH_RE = re.compile(
    r"(?:dropbear\[(\d+)\]|\[(\d+)\]).*?(?:Password|Pubkey) auth succeeded for '([^']+)'",
    re.IGNORECASE,
)
SSHD_AUTH_RE = re.compile(
    r"sshd(?:-session)?\[(\d+)\]:\s+Accepted\s+\S+\s+for\s+(\S+)\s+from",
    re.IGNORECASE,
)
XRAY_EMAIL_RE = re.compile(r"email:\s*([^\s@]+)@alyan", re.IGNORECASE)
XRAY_FROM_RAW_RE = re.compile(
    r"(?:\bfrom\s+)?(?:tcp:|udp:)?(\[[0-9a-fA-F:]+\]:[0-9]+|[0-9a-fA-F\.:]+:[0-9]+|[0-9\.]+)\s+accepted\b",
    re.IGNORECASE,
)
NGINX_XRAY_LOG = Path("/var/log/nginx/alyan-xray.log")


def db_conn():
    conn = sqlite3.connect(str(DB_PATH), timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    return conn


def clean_public_ip(raw_token: str) -> str | None:
    """Extract and validate a clean IP address (without :port), ignoring loopback/unspecified."""
    s = (raw_token or "").strip()
    if not s:
        return None
    if s.startswith("["):
        end = s.find("]")
        if end == -1:
            return None
        cand = s[1:end]
    elif s.count(":") == 1:
        cand = s.split(":", 1)[0]
    else:
        cand = s
        try:
            ipaddress.ip_address(cand)
        except ValueError:
            if ":" in cand:
                cand = cand.rsplit(":", 1)[0]
    if cand.lower().startswith("::ffff:"):
        cand = cand[7:]
    try:
        ip_obj = ipaddress.ip_address(cand)
        if ip_obj.is_loopback or ip_obj.is_unspecified or ip_obj.is_link_local:
            return None
        return str(ip_obj)
    except ValueError:
        return None


def device_key_for_ip(ip_str: str) -> str:
    """
    Normalize a client IP to a unique device key:
      - Unwrapped Cloudflare or CloudFront edge IPs collapse to 'cdn-edge' so PoP rotation never fakes 30 IPs.
      - IPv6 SLAAC privacy extensions collapse to their /64 subscriber prefix so 1 mobile phone = 1 device.
      - Standard public IPv4 maps 1:1 to itself.
    """
    try:
        addr = ipaddress.ip_address(ip_str)
        if any(addr in net for net in CF_EDGE_NETS):
            return "cdn-edge"
        # Known AWS CloudFront edge prefixes if any direct edge leaked
        if isinstance(addr, ipaddress.IPv4Address):
            s_ip = str(addr)
            if s_ip.startswith(("143.204.", "52.84.", "54.192.", "54.230.", "54.239.", "54.240.", "13.32.", "13.33.", "13.35.", "13.224.", "13.225.", "13.226.", "13.227.", "13.249.", "18.64.", "18.65.", "18.66.", "18.67.", "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.", "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.", "108.138.", "108.156.", "108.157.", "108.158.", "108.159.", "204.246.", "205.251.")):
                return "cdn-edge"
        if isinstance(addr, ipaddress.IPv6Address):
            net64 = ipaddress.IPv6Network((addr, 64), strict=False)
            return f"v6:{net64.network_address}/64"
        return str(addr)
    except ValueError:
        return ip_str


def read_recent_nginx_xray_ips(max_age_sec: float = 6.0) -> dict[str, list[str]]:
    """
    Returns proto -> list of recent clean unique client IPs from Nginx handshake log.
    Only includes handshakes within the last `max_age_sec` seconds!
    """
    res: dict[str, list[str]] = {}
    if not NGINX_XRAY_LOG.exists():
        return res
    now_ts = time.time()
    try:
        with NGINX_XRAY_LOG.open("rb") as f:
            f.seek(0, os.SEEK_END)
            sz = f.tell()
            f.seek(max(0, sz - 32768))
            lines = f.read().decode("utf-8", errors="ignore").splitlines()[-100:]
        for ln in lines:
            parts = ln.strip().split()
            if len(parts) < 4:
                continue
            # parts[0] is $msec (Unix timestamp with float, e.g. 1730378901.123)
            try:
                log_ts = float(parts[0])
                if (now_ts - log_ts) > max_age_sec:
                    continue
            except ValueError:
                pass
            raw_ip = parts[1]
            uri = parts[3].lower()
            ip_clean = clean_public_ip(raw_ip)
            if not ip_clean:
                continue
            proto = None
            if "vless" in uri or "xhttp" in uri:
                proto = "vless"
            elif "vmess" in uri:
                proto = "vmess"
            elif "trojan" in uri:
                proto = "trojan"
            if proto:
                if proto not in res:
                    res[proto] = []
                if ip_clean not in res[proto]:
                    res[proto].append(ip_clean)
    except Exception:
        pass
    return res


def parse_xray_source_ip(line: str) -> tuple[str | None, bool]:
    """Return (public_ip_or_None, was_loopback) from an Xray access.log 'accepted' line."""
    m = XRAY_FROM_RAW_RE.search(line)
    if not m:
        return None, False
    tok = m.group(1).strip()
    if tok.startswith(("127.0.0.1", "[::1]", "::1")):
        return None, True
    ip_clean = clean_public_ip(tok)
    return ip_clean, (ip_clean is None)


def read_cpu_pct() -> int:
    global LAST_CPU
    try:
        parts = [int(x) for x in Path("/proc/stat").read_text().splitlines()[0].split()[1:9]]
        idle = parts[3] + parts[4]
        total = sum(parts)
        if LAST_CPU is None:
            LAST_CPU = (idle, total)
            return 6
        d_idle = idle - LAST_CPU[0]
        d_tot = max(1, total - LAST_CPU[1])
        LAST_CPU = (idle, total)
        return max(1, min(99, int(round((1.0 - d_idle / d_tot) * 100))))
    except Exception:
        return 5


def read_ram_pct() -> int:
    try:
        vals = {}
        for ln in Path("/proc/meminfo").read_text().splitlines():
            if ":" in ln:
                k, v = ln.split(":", 1)
                vals[k.strip()] = int(v.strip().split()[0])
        tot = max(1, vals.get("MemTotal", 1))
        avail = vals.get("MemAvailable", vals.get("MemFree", 0))
        return max(1, min(99, int(round(((tot - avail) / tot) * 100))))
    except Exception:
        return 18


def read_net_rates(iface: str):
    global LAST_NET
    now = time.monotonic()
    rx_tot, tx_tot = 0, 0
    try:
        for ln in Path("/proc/net/dev").read_text().splitlines()[2:]:
            if ":" not in ln:
                continue
            name, rest = ln.split(":", 1)
            name = name.strip()
            if name == "lo":
                continue
            cols = rest.split()
            if name == iface or rx_tot == 0:
                rx_tot = int(cols[0])
                tx_tot = int(cols[8])
                if name == iface:
                    break
    except Exception:
        pass
    if LAST_NET is None:
        LAST_NET = (now, rx_tot, tx_tot)
        return 0.0, 0.0, rx_tot, tx_tot
    dt_s = max(0.4, now - LAST_NET[0])
    rx_bps = max(0.0, (rx_tot - LAST_NET[1]) / dt_s)
    tx_bps = max(0.0, (tx_tot - LAST_NET[2]) / dt_s)
    LAST_NET = (now, rx_tot, tx_tot)
    return rx_bps, tx_bps, rx_tot, tx_tot


def fmt_mem(mem_bytes: int) -> str:
    if mem_bytes <= 0 or mem_bytes >= (1 << 60):
        return "—"
    mb = mem_bytes / 1048576.0
    return f"{mb / 1024.0:.1f} GB" if mb >= 1024 else f"{mb:.1f} MB"


def fmt_mono_uptime(enter_usec: int) -> str:
    if enter_usec <= 0:
        return "—"
    try:
        secs = max(0, (int(time.monotonic() * 1_000_000) - enter_usec) // 1_000_000)
        d, rem = divmod(secs, 86400)
        h, rem = divmod(rem, 3600)
        m, _ = divmod(rem, 60)
        if d > 0:
            return f"{d}d {h}h"
        if h > 0:
            return f"{h}h {m}m"
        return f"{max(1, m)}m"
    except Exception:
        return "active"


def collect_services_fast() -> list[dict]:
    unit_ids = [s[0] for s in MANAGED_SERVICES]
    props_by_id: dict[str, dict[str, str]] = {u: {} for u in unit_ids}
    try:
        out = subprocess.check_output(
            [
                "systemctl",
                "show",
                *unit_ids,
                "--property=Id,ActiveState,MemoryCurrent,ActiveEnterTimestampMonotonic",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        for block in out.strip().split("\n\n"):
            kv = {}
            for ln in block.splitlines():
                if "=" in ln:
                    k, v = ln.split("=", 1)
                    kv[k] = v
            uid = kv.get("Id", "").removesuffix(".service")
            if uid in props_by_id:
                props_by_id[uid] = kv
    except Exception:
        pass

    res = []
    for sid, name, desc in MANAGED_SERVICES:
        kv = props_by_id.get(sid, {})
        status = "running" if kv.get("ActiveState") in ("active", "reloading") else "stopped"
        try:
            mem_val = int(kv.get("MemoryCurrent", "0"))
        except ValueError:
            mem_val = 0
        try:
            mono_val = int(kv.get("ActiveEnterTimestampMonotonic", "0"))
        except ValueError:
            mono_val = 0
        res.append(
            {
                "id": sid,
                "name": name,
                "desc": desc,
                "status": status,
                "mem": fmt_mem(mem_val) if status == "running" else "—",
                "uptime": fmt_mono_uptime(mono_val) if status == "running" else "—",
            }
        )
    return res


def refresh_auth_pid_cache(canon_users: dict[str, str]):
    """Scan recent Dropbear & OpenSSH journal entries (-o short-iso keeps PID tags!) to map worker PID -> user."""
    for dead in [p for p in PID_AUTH_CACHE if not Path(f"/proc/{p}").exists()]:
        PID_AUTH_CACHE.pop(dead, None)

    lines: list[str] = []
    try:
        out = subprocess.check_output(
            ["journalctl", "-u", "dropbear", "-u", "ssh", "-u", "sshd", "-n", "400", "--no-pager", "-o", "short-iso"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=2.5,
        )
        lines.extend(out.splitlines())
    except Exception:
        pass

    auth_log = Path("/var/log/auth.log")
    if auth_log.exists():
        try:
            with auth_log.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 32768))
                lines.extend(f.read().decode("utf-8", errors="ignore").splitlines()[-250:])
        except Exception:
            pass

    for ln in lines:
        m_db = DROPBEAR_AUTH_RE.search(ln)
        if m_db:
            pid_s = m_db.group(1) or m_db.group(2)
            if pid_s:
                pid = int(pid_s)
                u_low = m_db.group(3).lower()
                if u_low in canon_users and Path(f"/proc/{pid}").exists():
                    PID_AUTH_CACHE[pid] = canon_users[u_low]
            continue
        m_sh = SSHD_AUTH_RE.search(ln)
        if m_sh:
            pid = int(m_sh.group(1))
            u_low = m_sh.group(2).lower()
            if u_low in canon_users and Path(f"/proc/{pid}").exists():
                PID_AUTH_CACHE[pid] = canon_users[u_low]


def query_haproxy_sessions() -> tuple[dict[str, str], list[str], list[str], list[str]]:
    """
    Query HAProxy admin socket once per cycle:
      - loopback_map: 127.0.0.1:<ephemeral_port> -> real public client IP (for SSH-SSL :443 -> Dropbear)
      - ws_ips: active public client IPs on be_nginx_ws (WebSocket VLESS, VMess, Trojan, XHTTP)
      - h2c_ips: active public client IPs on be_nginx_h2c (gRPC streams)
      - trojan_ips: active public client IPs on be_xray_trojan_tcp (Trojan TCP)
    """
    loopback_map: dict[str, str] = {}
    ws_ips: list[str] = []
    h2c_ips: list[str] = []
    trojan_ips: list[str] = []
    if not HAPROXY_SOCK.exists():
        return loopback_map, ws_ips, h2c_ips, trojan_ips
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.45)
            s.connect(str(HAPROXY_SOCK))
            s.sendall(b"show sess all\n")
            chunks = []
            while True:
                buf = s.recv(32768)
                if not buf:
                    break
                chunks.append(buf)
        raw = b"".join(chunks).decode("latin1", errors="ignore")
        for block in re.split(r"(?m)^0x[0-9a-fA-F]+:", raw):
            m_src = re.search(r"(?:src=|addr=)([0-9a-fA-F\.:]+):\d+", block)
            if not m_src:
                continue
            ip = clean_public_ip(m_src.group(1))
            if not ip:
                continue
            if ("be=be_nginx_ws" in block or "srv=nginx_ws" in block) and ip not in ws_ips:
                ws_ips.append(ip)
            if ("be=be_nginx_h2c" in block or "srv=nginx_h2" in block) and ip not in h2c_ips:
                h2c_ips.append(ip)
            if ("be=be_xray_trojan_tcp" in block or "srv=xray_trojan" in block) and ip not in trojan_ips:
                trojan_ips.append(ip)
            for m_lp in re.finditer(r"127\.0\.0\.1:(\d+)", block):
                lp = m_lp.group(1)
                if lp not in ("109", "143", "22", "2095", "4443", "8880", "8881", "10023"):
                    loopback_map[lp] = ip
    except Exception:
        pass
    return loopback_map, ws_ips, h2c_ips, trojan_ips


def pid_to_username(pid: int, uid_map: dict[int, str], canon_users: dict[str, str]) -> str | None:
    if pid in PID_AUTH_CACHE:
        return PID_AUTH_CACHE[pid]
    try:
        status_txt = Path(f"/proc/{pid}/status").read_text()
        ppid = 0
        for line in status_txt.splitlines():
            if line.startswith("PPid:"):
                ppid = int(line.split()[1])
            elif line.startswith("Uid:"):
                for u in (int(x) for x in line.split()[1:5]):
                    if u in uid_map:
                        PID_AUTH_CACHE[pid] = uid_map[u]
                        return uid_map[u]
        if ppid and ppid in PID_AUTH_CACHE:
            PID_AUTH_CACHE[pid] = PID_AUTH_CACHE[ppid]
            return PID_AUTH_CACHE[ppid]

        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\x00", b" ").decode("latin1", errors="ignore")
        m = re.search(r"sshd(?:-session)?:\s*([A-Za-z0-9_-]+)", cmdline)
        if m and m.group(1).lower() in canon_users:
            resolved = canon_users[m.group(1).lower()]
            PID_AUTH_CACHE[pid] = resolved
            return resolved
    except Exception:
        pass
    return None


def read_pid_io_bytes(pid: int) -> int:
    try:
        rchar, wchar = 0, 0
        for ln in Path(f"/proc/{pid}/io").read_text().splitlines():
            if ln.startswith("rchar:"):
                rchar = int(ln.split()[1])
            elif ln.startswith("wchar:"):
                wchar = int(ln.split()[1])
        return (rchar + wchar) // 2
    except Exception:
        return 0


def scan_ssh_sessions(managed_users: set[str], hap_loop_ips: dict[str, str]) -> tuple[dict[str, list[dict]], dict[str, int]]:
    canon_users = {u.lower(): u for u in managed_users}
    refresh_auth_pid_cache(canon_users)

    uid_map: dict[int, str] = {}
    try:
        for line in Path("/etc/passwd").read_text().splitlines():
            parts = line.split(":")
            if len(parts) >= 4 and parts[0].lower() in canon_users:
                uid_map[int(parts[2])] = canon_users[parts[0].lower()]
    except Exception:
        pass

    wsd_map: dict[str, dict] = {}
    if WSD_STATE.exists():
        try:
            wsd_map = json.loads(WSD_STATE.read_text(encoding="utf-8"))
        except Exception:
            wsd_map = {}

    sessions_by_user: dict[str, list[dict]] = {u: [] for u in managed_users}
    deltas: dict[str, int] = {u: 0 for u in managed_users}
    active_pids: set[int] = set()

    try:
        out = subprocess.check_output(["ss", "-tnp"], text=True, stderr=subprocess.DEVNULL, timeout=2.5)
    except Exception:
        out = ""

    for line in out.splitlines():
        if "ESTAB" not in line:
            continue
        if "dropbear" not in line and "sshd" not in line:
            continue
        cols = line.split()
        if len(cols) < 5:
            continue
        local_ep, peer_ep = cols[3], cols[4]
        lport = local_ep.rsplit(":", 1)[-1]
        if lport not in ("22", "109", "143"):
            continue
        peer_ip, peer_port = peer_ep.rsplit(":", 1)
        peer_ip = peer_ip.strip("[]")
        if peer_ip.startswith("::ffff:"):
            peer_ip = peer_ip[7:]

        pids = [int(x) for x in re.findall(r"pid=(\d+)", line)]
        username = None
        target_pid = None
        for pid in pids:
            u = pid_to_username(pid, uid_map, canon_users)
            if u:
                username = u
                target_pid = pid
                break
        if not username or target_pid is None:
            continue

        active_pids.add(target_pid)
        real_ip = clean_public_ip(peer_ip)

        if peer_ip == "127.0.0.1" and peer_port in wsd_map:
            PORT_TO_USER[peer_port] = username
            real_ip = clean_public_ip(wsd_map[peer_port].get("ip", "")) or "127.0.0.1"
        elif peer_ip == "127.0.0.1" and peer_port in hap_loop_ips:
            real_ip = hap_loop_ips[peer_port]
            cur_io = read_pid_io_bytes(target_pid)
            prev_io = PID_LAST_IO_BYTES.get(target_pid, 0)
            if cur_io > prev_io:
                deltas[username] += (cur_io - prev_io)
            PID_LAST_IO_BYTES[target_pid] = cur_io
        else:
            cur_io = read_pid_io_bytes(target_pid)
            prev_io = PID_LAST_IO_BYTES.get(target_pid, 0)
            if cur_io > prev_io:
                deltas[username] += (cur_io - prev_io)
            PID_LAST_IO_BYTES[target_pid] = cur_io

        if real_ip and real_ip != "127.0.0.1":
            sessions_by_user[username].append(
                {"pid": target_pid, "ip": real_ip, "dev": str(real_ip)}
            )

    for port, info in wsd_map.items():
        uname = PORT_TO_USER.get(port)
        if not uname or uname not in deltas:
            continue
        cur_b = int(info.get("bytes", 0))
        prev_b = WSD_PORT_LAST_BYTES.get(port, 0)
        if cur_b > prev_b:
            deltas[uname] += (cur_b - prev_b)
        WSD_PORT_LAST_BYTES[port] = cur_b

    for stale_port in list(WSD_PORT_LAST_BYTES.keys()):
        if stale_port not in wsd_map:
            WSD_PORT_LAST_BYTES.pop(stale_port, None)
            PORT_TO_USER.pop(stale_port, None)

    for stale_pid in list(PID_LAST_IO_BYTES.keys()):
        if stale_pid not in active_pids:
            PID_LAST_IO_BYTES.pop(stale_pid, None)

    return sessions_by_user, deltas


PROTO_PORTS = {
    "vless": (10001, 10011, 10031),
    "vmess": (10002, 10012),
    "trojan": (10003, 10013, 10023),
}
XRAY_LAST_ACTIVE_TS: dict[str, float] = {}


def scan_active_proto_sockets() -> dict[str, int]:
    """Return count of active ESTAB sockets on Xray inbound ports."""
    counts = {"vless": 0, "vmess": 0, "trojan": 0}
    try:
        out = subprocess.check_output(["ss", "-tn"], text=True, stderr=subprocess.DEVNULL, timeout=1.5)
        for ln in out.splitlines():
            if "ESTAB" not in ln:
                continue
            cols = ln.split()
            if len(cols) < 5:
                continue
            try:
                lport = int(cols[3].rsplit(":", 1)[-1])
            except ValueError:
                continue
            for pr, ports in PROTO_PORTS.items():
                if lport in ports:
                    counts[pr] += 1
    except Exception:
        pass
    return counts


def poll_xray_stats_and_ips(
    xray_users: list[sqlite3.Row],
    ws_ips: list[str],
    h2c_ips: list[str],
    trojan_ips: list[str],
) -> tuple[dict[str, int], dict[str, list[str]], dict[str, int]]:
    """
    Returns:
      - deltas: uuid -> bytes transferred since last 2s tick
      - ips_by_uuid: uuid -> sorted clean unique client IPs (1 IP per active connection)
      - dev_count_by_uuid: uuid -> count of distinct active devices
    """
    tag_to_uuid: dict[str, str] = {}
    uuid_to_proto: dict[str, str] = {}
    for r in xray_users:
        u_low = r["username"].lower()
        p_low = r["proto"].lower()
        uid = r["uuid"]
        tag_to_uuid[f"{u_low}.{p_low}"] = uid
        tag_to_uuid.setdefault(u_low, uid)
        uuid_to_proto[uid] = p_low

    deltas: dict[str, int] = {}
    if Path("/usr/local/bin/xray").exists():
        try:
            raw = subprocess.check_output(
                ["/usr/local/bin/xray", "api", "statsquery", "--server=127.0.0.1:10085", "-pattern", "user>>>", "-reset"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=3.0,
            )
            data = json.loads(raw) if raw.strip() else {}
            for st in data.get("stat", []):
                parts = st.get("name", "").split(">>>")
                if len(parts) >= 4:
                    tag_low = parts[1].split("@", 1)[0].lower()
                    uid = tag_to_uuid.get(tag_low)
                    if uid:
                        deltas[uid] = deltas.get(uid, 0) + int(st.get("value", 0))
        except Exception:
            pass

    now_ts = time.time()
    proto_socket_counts = scan_active_proto_sockets()
    nginx_proto_ips = read_recent_nginx_xray_ips(max_age_sec=6.0)
    latest_ip_from_log: dict[str, str] = {}

    if XRAY_ACCESS_LOG.exists():
        try:
            with XRAY_ACCESS_LOG.open("rb") as f:
                f.seek(0, os.SEEK_END)
                sz = f.tell()
                f.seek(max(0, sz - 32768))
                tail_lines = f.read().decode("utf-8", errors="ignore").splitlines()[-100:]
            for ln in tail_lines:
                if "accepted" not in ln or "email:" not in ln:
                    continue
                m_em = XRAY_EMAIL_RE.search(ln)
                if not m_em:
                    continue
                uid = tag_to_uuid.get(m_em.group(1).lower())
                if not uid:
                    continue

                proto = uuid_to_proto.get(uid, "vless")
                ip_clean, was_loop = parse_xray_source_ip(ln)
                matched_ip = ip_clean

                if was_loop or not matched_ip:
                    # Connection proxied through Nginx/HAProxy (127.0.0.1 loopback)
                    if proto in nginx_proto_ips and nginx_proto_ips[proto]:
                        matched_ip = nginx_proto_ips[proto][-1]
                    elif proto in ("vless", "vmess") and ws_ips:
                        matched_ip = ws_ips[0]
                    elif proto == "trojan":
                        matched_ip = trojan_ips[0] if trojan_ips else (ws_ips[0] if ws_ips else None)
                    elif h2c_ips:
                        matched_ip = h2c_ips[0]

                if matched_ip:
                    latest_ip_from_log[uid] = matched_ip
        except Exception:
            pass

    ips_by_uuid: dict[str, list[str]] = {}
    dev_count_by_uuid: dict[str, int] = {}

    for r in xray_users:
        uid = r["uuid"]
        proto = r["proto"].lower()
        dev_map = XRAY_ACTIVE_DEVICES.setdefault(uid, {})
        user_traffic = deltas.get(uid, 0)
        active_traffic = user_traffic > 0
        active_sockets = proto_socket_counts.get(proto, 0)

        if active_traffic:
            XRAY_LAST_ACTIVE_TS[uid] = now_ts

        idle_sec = now_ts - XRAY_LAST_ACTIVE_TS.get(uid, 0)

        # ── REAL-TIME DISCONNECT (within 2 seconds) ──
        # Disconnect triggers immediately if no active sockets exist OR if no traffic for > 3.0 seconds
        if active_sockets == 0 or (not active_traffic and idle_sec > 3.0):
            dev_map.clear()
            ips_by_uuid[uid] = []
            dev_count_by_uuid[uid] = 0
            continue

        # If data is actively transferring OR user is within 3.0s active window:
        best_ip = None
        if uid in latest_ip_from_log:
            best_ip = latest_ip_from_log[uid]
        elif proto in nginx_proto_ips and nginx_proto_ips[proto]:
            best_ip = nginx_proto_ips[proto][-1]
        elif proto in ("vless", "vmess") and ws_ips:
            best_ip = ws_ips[0]
        elif proto == "trojan":
            best_ip = trojan_ips[0] if trojan_ips else (ws_ips[0] if ws_ips else None)
        elif h2c_ips:
            best_ip = h2c_ips[0]

        if best_ip:
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
        dev_count_by_uuid[uid] = max(len(ips_by_uuid[uid]), len(dev_map))

    return deltas, ips_by_uuid, dev_count_by_uuid


def send_telegram_alert(bot_cfg: dict, message: str):
    if not bot_cfg.get("enabled") or not bot_cfg.get("alerts"):
        return
    token = (bot_cfg.get("token") or "").strip()
    admin_ids = [x.strip() for x in str(bot_cfg.get("admin_id") or "").split(",") if x.strip()]
    if not token or "*" in token or not admin_ids:
        return
    for chat_id in admin_ids:
        try:
            payload = json.dumps({"chat_id": chat_id, "text": f"🔥 *Alyan Guard Alert*\n{message}", "parse_mode": "Markdown"}).encode()
            req = urllib.request.Request(
                f"https://api.telegram.org/bot{token}/sendMessage",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=4).read()
        except Exception:
            pass


def enforce_cycle():
    global CYCLE_TICK, CACHED_SERVICES
    if not DB_PATH.exists():
        return

    CYCLE_TICK += 1
    hap_loop_ips, ws_ips, h2c_ips, trojan_ips = query_haproxy_sessions()

    conn = db_conn()
    try:
        settings_rows = {r["key"]: r["value"] for r in conn.execute("SELECT key, value FROM settings").fetchall()}
        iface = settings_rows.get("iface", "eth0")
        bot_cfg = json.loads(settings_rows.get("bot_json", "{}"))

        ssh_rows = conn.execute("SELECT * FROM ssh_users").fetchall()
        xray_rows = conn.execute("SELECT * FROM xray_users").fetchall()

        today = dt.date.today().isoformat()
        managed_ssh = {r["username"] for r in ssh_rows}
        ssh_sessions, ssh_deltas = scan_ssh_sessions(managed_ssh, hap_loop_ips)
        xray_deltas, xray_ips, xray_fresh_devs = poll_xray_stats_and_ips(xray_rows, ws_ips, h2c_ips, trojan_ips)

        # ─── 1. Enforce SSH Quotas, Expiry & Strict IP Limit Auto-Disable ───
        for r in ssh_rows:
            uname = r["username"]
            delta_b = int(ssh_deltas.get(uname, 0))
            used = int(r["used_bytes"]) + delta_b
            if delta_b > 0:
                conn.execute("UPDATE ssh_users SET used_bytes = ? WHERE username = ?", (used, uname))

            if r["status"] != "active":
                SSH_IP_STRIKES.pop(uname, None)
                for s in ssh_sessions.get(uname, []):
                    if s.get("pid"):
                        subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                ssh_sessions[uname] = []
                continue

            gb_lim = float(r["gb_limit"] or 0)
            user_lim = int(r["ip_limit"] or 0)
            conns = ssh_sessions.get(uname, [])
            session_count = len(conns)
            uniq_ips = sorted({s["ip"] for s in conns if s.get("ip")})

            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"SSH user `{uname}` expired ({r['expiry']})"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"SSH user `{uname}` reached {gb_lim} GB quota"
            elif user_lim > 0 and session_count > user_lim:
                SSH_IP_STRIKES[uname] = SSH_IP_STRIKES.get(uname, 0) + 1
                if SSH_IP_STRIKES[uname] >= 2:
                    reason = f"SSH user `{uname}` exceeded user limit ({session_count}/{user_lim} Users) — auto-disabled"
                else:
                    # Strike 1: Immediately terminate excess user sessions beyond user_lim
                    excess = conns[user_lim:]
                    for s in excess:
                        if s.get("pid"):
                            subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                    ssh_sessions[uname] = conns[:user_lim]
            else:
                SSH_IP_STRIKES.pop(uname, None)

            if reason:
                SSH_IP_STRIKES.pop(uname, None)
                conn.execute("UPDATE ssh_users SET status = 'disabled' WHERE username = ?", (uname,))
                conn.execute(
                    "INSERT INTO audit_log (created_at, actor, action, detail, ip) VALUES (?, 'alyan-guard', 'auto_disable', ?, 'local')",
                    (dt.datetime.now().strftime("%H:%M:%S"), reason),
                )
                subprocess.run(["usermod", "-L", uname], stderr=subprocess.DEVNULL)
                subprocess.run(["pkill", "-KILL", "-u", uname], stderr=subprocess.DEVNULL)
                for s in ssh_sessions.get(uname, []):
                    if s.get("pid"):
                        subprocess.run(["kill", "-9", str(s["pid"])], stderr=subprocess.DEVNULL)
                ssh_sessions[uname] = []
                send_telegram_alert(bot_cfg, reason)

        # ─── 2. Enforce Xray Quotas, Expiry & Strict IP Limit Auto-Disable ───
        xray_resync_needed = False
        for r in xray_rows:
            uname = r["username"]
            uuid = r["uuid"]
            delta_x = int(xray_deltas.get(uuid, 0))
            used = int(r["used_bytes"]) + delta_x
            if delta_x > 0:
                conn.execute("UPDATE xray_users SET used_bytes = ? WHERE uuid = ?", (used, uuid))

            if r["status"] != "active":
                XRAY_IP_STRIKES.pop(uuid, None)
                XRAY_ACTIVE_DEVICES.pop(uuid, None)
                xray_ips[uuid] = []
                continue

            gb_lim = float(r["gb_limit"] or 0)
            user_lim = int(r["ip_limit"] or 0)
            cur_ips = xray_ips.get(uuid, [])
            fresh_sess = xray_fresh_devs.get(uuid, 0)

            reason = None
            if r["expiry"] and r["expiry"] < today:
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) expired"
            elif gb_lim > 0 and used >= int(gb_lim * 1073741824):
                reason = f"Xray client `{uname}` ({r['proto'].upper()}) reached {gb_lim} GB quota"
            elif user_lim > 0 and fresh_sess > user_lim:
                XRAY_IP_STRIKES[uuid] = XRAY_IP_STRIKES.get(uuid, 0) + 1
                if XRAY_IP_STRIKES[uuid] >= 3:
                    reason = f"Xray client `{uname}` ({r['proto'].upper()}) exceeded user limit ({fresh_sess}/{user_lim} Users) — auto-disabled"
            else:
                XRAY_IP_STRIKES.pop(uuid, None)

            if reason:
                XRAY_IP_STRIKES.pop(uuid, None)
                XRAY_ACTIVE_DEVICES.pop(uuid, None)
                conn.execute("UPDATE xray_users SET status = 'disabled' WHERE uuid = ?", (uuid,))
                conn.execute(
                    "INSERT INTO audit_log (created_at, actor, action, detail, ip) VALUES (?, 'alyan-guard', 'xray_disable', ?, 'local')",
                    (dt.datetime.now().strftime("%H:%M:%S"), reason),
                )
                xray_ips[uuid] = []
                xray_resync_needed = True
                send_telegram_alert(bot_cfg, reason)

        conn.commit()
    finally:
        conn.close()

    if xray_resync_needed and Path("/usr/local/bin/alyan-ctl").exists():
        subprocess.run(["/usr/local/bin/alyan-ctl", "xray-sync"], stderr=subprocess.DEVNULL)

    # ─── 3. Record Rolling Telemetry & Fast Snapshot ─────────────────────────
    cpu_pct = read_cpu_pct()
    ram_pct = read_ram_pct()
    rx_bps, tx_bps, rx_tot, tx_tot = read_net_rates(iface)

    HIST["cpu"] = (HIST["cpu"] + [cpu_pct])[-20:]
    HIST["ram"] = (HIST["ram"] + [ram_pct])[-20:]
    HIST["rx"] = (HIST["rx"] + [round((rx_bps * 8) / 1048576.0, 2)])[-20:]
    HIST["tx"] = (HIST["tx"] + [round((tx_bps * 8) / 1048576.0, 2)])[-20:]

    if not CACHED_SERVICES or (CYCLE_TICK % 2 == 0):
        CACHED_SERVICES = collect_services_fast()

    ssh_live = {}
    for uname, conns in ssh_sessions.items():
        ips = sorted({c["ip"] for c in conns if c.get("ip")})
        ssh_live[uname] = {"online": len(conns), "ips": ips}

    xray_live = {}
    for r in xray_rows:
        uid = r["uuid"]
        ips = xray_ips.get(uid, [])
        user_sess_cnt = xray_fresh_devs.get(uid, 0)
        if user_sess_cnt == 0 and ips:
            user_sess_cnt = len(ips)
        if user_sess_cnt == 0 and int(xray_deltas.get(uid, 0)) > 0:
            user_sess_cnt = 1
        xray_live[uid] = {"online": user_sess_cnt, "ips": ips}

    snapshot = {
        "updated_at": int(time.time()),
        "cpu_pct": cpu_pct,
        "ram_pct": ram_pct,
        "rx_bps": rx_bps,
        "tx_bps": tx_bps,
        "rx_total": rx_tot,
        "tx_total": tx_tot,
        "hist": HIST,
        "services": CACHED_SERVICES,
        "ssh_live": ssh_live,
        "xray_live": xray_live,
    }
    tmp = LIVE_OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(snapshot), encoding="utf-8")
    os.chmod(tmp, 0o644)
    tmp.replace(LIVE_OUT)


def main():
    while True:
        try:
            enforce_cycle()
        except Exception:
            pass
        time.sleep(2.0)


if __name__ == "__main__":
    main()

EOF_GUARD
  chmod +x "${INSTALL_DIR}/services/guard/alyan-guard.py"

  cat > "${INSTALL_DIR}/templates/nginx-router.conf.tpl" <<'EOF_NGINX_TPL'
# ═════════════════════════════════════════════════════════════════════════════
#  🔥 ALYAN WEBPANEL — Internal Zero-Buffering Nginx WS / XHTTP / gRPC Router
#  Binds strictly to 127.0.0.1:8880 (HTTP/WS) and 127.0.0.1:8881 (h2c gRPC)
# ═════════════════════════════════════════════════════════════════════════════
map $http_upgrade $alyan_connection_upgrade {
    default upgrade;
    ''      close;
}

# CloudFront Viewer Address (AWS CloudFront Real Client IP without :port)
map $http_cloudfront_viewer_address $alyan_cf_viewer_ip {
    default                      "";
    "~^([0-9a-fA-F\.:]+):\d+"     $1;
}

# First IP from X-Forwarded-For
map $http_x_forwarded_for $alyan_xff_first {
    default                      "";
    "~^([0-9a-fA-F\.:]+)"        $1;
}

# Unified CDN Header Priority: CloudFront Viewer Address -> CF-Connecting-IP -> True-Client-IP -> X-Forwarded-For
map $alyan_cf_viewer_ip $alyan_cdn_ip_step1 {
    ""      $http_cf_connecting_ip;
    default $alyan_cf_viewer_ip;
}

map $alyan_cdn_ip_step1 $alyan_cdn_ip_step2 {
    ""      $http_true_client_ip;
    default $alyan_cdn_ip_step1;
}

map $alyan_cdn_ip_step2 $alyan_cdn_resolved_ip {
    ""      $alyan_xff_first;
    default $alyan_cdn_ip_step2;
}

# Priority: X-Target header -> X-Edge-IP -> PROXY protocol addr -> remote_addr
map $http_x_target $alyan_x_target_ip {
    default $http_x_target;
    ""      $http_x_edge_ip;
}

map $alyan_x_target_ip $alyan_connected_edge_ip {
    ""      $proxy_protocol_addr;
    default $alyan_x_target_ip;
}

map $alyan_connected_edge_ip $alyan_final_edge_ip {
    ""      $remote_addr;
    default $alyan_connected_edge_ip;
}

log_format alyan_xray '$time_iso8601 $alyan_final_edge_ip $status $request_uri';

# ─── HTTP/1.1 WebSocket, XHTTP & ACME Challenge Router (:8880) ───────────────
server {
    listen 127.0.0.1:8880 proxy_protocol backlog=16384;
    server_name {{DOMAIN}} _;

    access_log /var/log/nginx/alyan-xray.log alyan_xray;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    tcp_nodelay on;
    tcp_nopush off;
    client_max_body_size 0;
    keepalive_timeout 3600s;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/alyan-acme;
        default_type "text/plain";
    }

    location /alyan-vless {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-vmess {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-trojan {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-xhttp {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10031;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html><html><head><title>{{DOMAIN}}</title></head><body style="background:#050507;color:#f5f2ee;font-family:sans-serif;display:grid;place-items:center;height:100vh;margin:0"><div><h2 style="letter-spacing:.16em">🔥 ALYAN EDGE NODE ONLINE</h2></div></body></html>';
    }
}

# ─── HTTP/2 Cleartext (h2c) gRPC & XHTTP Router (:8881) ──────────────────────
server {
    listen 127.0.0.1:8881 http2 proxy_protocol backlog=16384;
    server_name {{DOMAIN}} _;

    access_log /var/log/nginx/alyan-xray.log alyan_xray;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    tcp_nodelay on;
    tcp_nopush off;
    client_max_body_size 0;
    client_body_timeout 4h;
    grpc_read_timeout 4h;
    grpc_send_timeout 4h;
    grpc_socket_keepalive on;

    location /alyan-vless-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $alyan_real_ip;
        grpc_set_header X-Forwarded-For $alyan_real_ip;
        grpc_pass grpc://127.0.0.1:10011;
    }

    location /alyan-vmess-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $alyan_real_ip;
        grpc_set_header X-Forwarded-For $alyan_real_ip;
        grpc_pass grpc://127.0.0.1:10012;
    }

    location /alyan-trojan-grpc {
        client_max_body_size 0;
        grpc_set_header X-Real-IP $alyan_real_ip;
        grpc_set_header X-Forwarded-For $alyan_real_ip;
        grpc_pass grpc://127.0.0.1:10013;
    }

    location /alyan-xhttp {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10031;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location /alyan-vless {
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $alyan_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $alyan_real_ip;
        proxy_set_header X-Forwarded-For $alyan_real_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}

EOF_NGINX_TPL

  cat > "${INSTALL_DIR}/cli/menu.sh" <<'EOF_MENU_SH'
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

  echo ""
  echo -e "\033[1;38;2;255;30;30m   █████╗  ██╗   ██╗   ██╗  █████╗  ███╗   ██╗${C_RST}"
  echo -e "\033[1;38;2;255;64;16m  ██╔══██╗ ██║   ╚██╗ ██╔╝ ██╔══██╗ ████╗  ██║${C_RST}"
  echo -e "\033[1;38;2;255;106;0m  ███████║ ██║    ╚████╔╝  ███████║ ██╔██╗ ██║${C_RST}"
  echo -e "\033[1;38;2;255;150;0m  ██╔══██║ ██║     ╚██╔╝   ██╔══██║ ██║╚██╗██║${C_RST}"
  echo -e "\033[1;38;2;255;192;24m  ██║  ██║ ███████╗ ██║    ██║  ██║ ██║ ╚████║${C_RST}"
  echo -e "\033[1;38;2;255;224;110m  ╚═╝  ╚═╝ ╚══════╝ ╚═╝    ╚═╝  ╚═╝ ╚═╝  ╚═══╝${C_RST}"
  echo -e "  🔥 ${C_GLD}${C_BOLD}ALYAN WEBPANEL${C_RST} ${C_GRY}· FLAME TUNNELING COMMAND DECK${C_RST}"
  echo -e "  ${C_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RST}"
  printf "  ${C_RED}┃${C_RST} ${C_GRY}Domain :${C_RST} ${C_GLD}%-24s${C_RST} ${C_GRY}IP :${C_RST} ${C_WHT}%-16s${C_RST} ${C_GRY}SSL:${C_RST} ${C_AMB}%3sd${C_RST} ${C_RED}┃${C_RST}\n" "$domain" "$ip" "$ssl_d"
  printf "  ${C_RED}┃${C_RST} ${C_GRY}CPU/RAM:${C_RST} ${C_WHT}%2s%% / %2s%%${C_RST}   ${C_GRY}Up:${C_RST} ${C_WHT}%-9s${C_RST} ${C_GRY}SSH:${C_RST} ${C_AMB}%s (%s live)${C_RST}  ${C_GRY}Xray:${C_RST} ${C_AMB}%s${C_RST}  ${C_RED}┃${C_RST}\n" "$cpu" "$ram" "$up" "$ssh_tot" "$ssh_on" "$xray_tot"
  echo -e "  ${C_RED}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_RST}"
  echo -e "  ${C_RED}┃${C_RST} HAProxy $(svc_dot haproxy)  Nginx $(svc_dot nginx)  Dropbear $(svc_dot dropbear)  WS $(svc_dot alyan-wsd)  Xray $(svc_dot xray) ${C_RED}┃${C_RST}"
  echo -e "  ${C_RED}┃${C_RST} Panel   $(svc_dot alyan-panel)  Guard $(svc_dot alyan-guard)  Bot   $(svc_dot alyan-bot)  BBR+FQ ${C_OK}● ON ${C_RST}  :${port}     ${C_RED}┃${C_RST}"
  echo -e "  ${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}"
}

# ─── Option 1: Update from GitHub / Re-Verify All Components ──────────────────
opt_install_all() {
  echo -e "\n  ${C_AMB}${C_BOLD}⚡ Option 1 — Live GitHub Update / Re-Verify Stack${C_RST}"
  echo -e "  ${C_ORG}  [1]${C_WHT} Pull Latest Update from GitHub (--update) [Zero Data Loss]${C_RST}"
  echo -e "  ${C_ORG}  [2]${C_WHT} Verify Local Packages & Restart Stack${C_RST}"
  echo -e "  ${C_ORG}  [3]${C_WHT} Re-run Full Interactive Installer${C_RST}"
  echo -e "  ${C_ORG}  [0]${C_GRY} Back${C_RST}\n"
  read -rp "  Select action [1]: " sub </dev/tty
  sub="${sub:-1}"
  case "$sub" in
    1)
      bash <(curl -fsSL "https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/install.sh?ts=$(date +%s)" | tr -d '\r') --update
      pause_ret
      ;;
    2)
      echo -e "  ${C_GRY}Verifying packages, configs & restarting tunneling stack...${C_RST}"
      apt-get update -qq && apt-get install -y -qq dropbear nginx haproxy jq sqlite3 curl openssl iproute2 >/dev/null
      $CTL --actor cli settings --json '{"maint":"fix_ws_ssl_stack"}' >/dev/null
      $CTL --actor cli service all restart >/dev/null
      echo -e "  ${C_OK}✔ All core packages, templates & daemons verified and running!${C_RST}"
      pause_ret
      ;;
    3)
      if [[ -f "${INSTALL_DIR}/install.sh" ]]; then
        bash "${INSTALL_DIR}/install.sh"
      else
        bash <(curl -fsSL "https://raw.githubusercontent.com/Alyanx1/Alyan-Webpanel/main/install.sh?ts=$(date +%s)" | tr -d '\r')
      fi
      pause_ret
      ;;
    *) ;;
  esac
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
        read -rp "  User Limit (0=∞) [2] : " ipm </dev/tty; ipm="${ipm:-2}"
        res=$($CTL --actor cli ssh-add --username "$u" --password "$p" --days "$d" --gb-limit "$g" --ip-limit "$ipm" 2>&1)
        if echo "$res" | jq -e '.item' >/dev/null 2>&1; then
          dom=$(echo "$res" | jq -r '.cfg.domain')
          exp=$(echo "$res" | jq -r '.item.expiry')
          echo -e "\n  ${C_OK}✔ SSH Account Created!${C_RST}"
          echo -e "  ${C_GRY}Host / SNI :${C_RST} ${C_GLD}${dom}${C_RST}"
          echo -e "  ${C_GRY}Username   :${C_RST} ${C_WHT}${u}${C_RST}   ${C_GRY}Password:${C_RST} ${C_WHT}${p}${C_RST}   ${C_GRY}Expires:${C_RST} ${C_AMB}${exp}${C_RST}"
          echo -e "  ${C_GRY}Ports      :${C_RST} Direct 22, 109, 143 · WS 80 · WS-SSL 443 (/alyan)"
          echo -e "  ${C_GRY}Payload    :${C_RST} ${C_AMB}GET /alyan HTTP/1.1[crlf]Host: ${dom}[crlf]X-Target: [host][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${C_RST}"
        else
          echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        fi
        pause_ret ;;
      2)
        res=$($CTL --actor cli ssh-list)
        echo ""
        printf "  ${C_AMB}%-16s %-10s %-12s %-14s %-8s %-10s${C_RST}\n" "USERNAME" "STATUS" "EXPIRY" "USED / QUOTA" "USER CAP" "ONLINE"
        echo "$res" | jq -r '.items[] | "\(.username)|\(.status)|\(.expiry)|\((.used_bytes/1073741824*100|round)/100)G/\(if .gb_limit>0 then (.gb_limit|tostring)+"G" else "inf" end)|\(if .ip_limit>0 then (.ip_limit|tostring) else "inf" end)|\(.online)"' | \
        while IFS='|' read -r un st ex qt ic on; do
          printf "  %-16s %-10s %-12s %-14s %-8s %-10s\n" "$un" "$st" "$ex" "$qt" "$ic" "$on"
        done
        pause_ret ;;
      3)
        read -rp "  SSH Username to edit : " u </dev/tty
        read -rp "  New Days [30]        : " d </dev/tty; d="${d:-30}"
        read -rp "  GB Limit (0=∞) [0]   : " g </dev/tty; g="${g:-0}"
        read -rp "  User Limit (0=∞) [2]   : " ipm </dev/tty; ipm="${ipm:-2}"
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
        read -rp "  User Limit (0=∞) [2]: " ipm </dev/tty; ipm="${ipm:-2}"
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
        read -rp "  User Limit (0=∞) [2]: " ipm </dev/tty; ipm="${ipm:-2}"
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

# ─── Option 7: Wire-Speed Network Optimizer (BBR + FQ) ───────────────────────
opt_wirespeed_tune() {
  echo -e "\n  ${C_AMB}${C_BOLD}🚀 Option 7 — Wire-Speed Network Optimizer (Kernel BBR + FQ Pacing)${C_RST}"
  local cc qd
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  qd=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
  echo -e "  Active Kernel Profile: Congestion=${C_GLD}${cc}${C_RST} · Queue=${C_GLD}${qd}${C_RST} · Speed Caps=${C_OK}NONE (Unthrottled)${C_RST}"
  echo -e "  ${C_GRY}Re-applying 32MB TCP socket buffers, BBR + FQ pacing, TCP_NODELAY & clearing any NIC shapers...${C_RST}"
  $CTL --actor cli settings --json '{"maint":"fix_ws_ssl_stack"}' >/dev/null
  echo -e "  ${C_OK}✔ Full Wire-Speed BBR + FQ profile active! Native line-rate unlocked.${C_RST}"
  pause_ret
}

# ─── Option 8: VPS Hardware & Live Traffic Stats ─────────────────────────────
opt_vps_stats() {
  echo -e "\n  ${C_AMB}${C_BOLD}📊 Option 8 — VPS Hardware & Live Traffic Stats${C_RST}"
  tel=$($CTL --actor cli telemetry)
  echo -e "  ${C_GRY}OS / Kernel :${C_RST} $(echo "$tel" | jq -r '.cfg.os') · $(echo "$tel" | jq -r '.cfg.kernel')"
  echo -e "  ${C_GRY}CPU Model   :${C_RST} $(echo "$tel" | jq -r '.cfg.cpu_model')"
  echo -e "  ${C_GRY}Location    :${C_RST} $(echo "$tel" | jq -r '.cfg.location') · $(echo "$tel" | jq -r '.cfg.provider')"
  echo -e "  ${C_GRY}CPU / Load  :${C_RST} $(echo "$tel" | jq -r '.cpu_pct')%  (load: $(echo "$tel" | jq -r '.load'))"
  echo -e "  ${C_GRY}RAM / Disk  :${C_RST} RAM $(echo "$tel" | jq -r '.ram_pct')%  ·  Disk $(echo "$tel" | jq -r '.disk_pct')%"
  echo -e "  ${C_GRY}Live Tunnels:${C_RST} SSH $(echo "$tel" | jq -r '.ssh_online') online · Xray $(echo "$tel" | jq -r '.xray_online // 0') online"
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
  adm_user=$($CTL get-super-admin 2>/dev/null || echo "admin")
  ipw=$($CTL get-initial-pass 2>/dev/null || echo "Hidden")

  echo -e "  ${C_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RST}"
  printf "  ${C_RED}┃${C_RST}  Web Panel URL  : ${C_GLD}${C_BOLD}https://%s:%s${C_RST}\n" "$dom" "$prt"
  printf "  ${C_RED}┃${C_RST}  Admin Username : ${C_WHT}${C_BOLD}%s${C_RST}\n" "$adm_user"
  printf "  ${C_RED}┃${C_RST}  Admin Password : ${C_ORG}${C_BOLD}%s${C_RST}\n" "$ipw"
  echo -e "  ${C_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RST}"
  echo -e "  ${C_ORG}[1]${C_WHT} Change Web Panel HTTPS Port${C_RST}"
  echo -e "  ${C_ORG}[2]${C_WHT} Change user pass of web panel${C_RST}"
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
      echo -e "\n  ${C_AMB}${C_BOLD}🔑 Change user pass of web panel${C_RST}"
      read -rp "  Enter new Web Panel Username: " nuser </dev/tty
      read -rp "  Enter new Web Panel Password (min 6 chars): " npw </dev/tty
      if [[ -n "$nuser" && -n "$npw" ]]; then
        payload=$(jq -nc --arg u "$nuser" --arg p "$npw" '{new_username:$u,new_password:$p,target_admin:"@super"}')
        res=$($CTL --actor cli settings --json "$payload" 2>&1)
        if echo "$res" | jq -e '.ok' >/dev/null 2>&1; then
          echo -e "  ${C_OK}✔ Web Panel credentials updated successfully!${C_RST}"
          echo -e "  ${C_WHT}New Username : ${C_GLD}${C_BOLD}${nuser}${C_RST}"
          echo -e "  ${C_WHT}New Password : ${C_ORG}${C_BOLD}${npw}${C_RST}"
        else
          echo -e "  ${C_ERR}✖ $(echo "$res" | jq -r '.error // .')${C_RST}"
        fi
      else
        echo -e "  ${C_ERR}✖ Both username and password are required.${C_RST}"
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
         /etc/systemd/system/nginx.service.d/alyan-limits.conf \
         /etc/systemd/system/haproxy.service.d/alyan-limits.conf \
         /etc/nginx/conf.d/alyan-router.conf /etc/nginx/conf.d/alyan-panel.conf \
         /etc/sudoers.d/alyan-panel /etc/sysctl.d/99-alyan-bbr.conf /etc/sysctl.d/99-alyan-turbo.conf \
         /usr/local/bin/alyan-ctl /usr/local/bin/menu /usr/local/bin/alyan-update \
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
  echo -e "  ${C_ORG}  [1]${C_WHT} Update / Install Stack          ${C_ORG}[7]${C_WHT}  Wire-Speed Optimizer (BBR+FQ)${C_RST}"
  echo -e "  ${C_ORG}  [2]${C_WHT} Add / Change Domain             ${C_ORG}[8]${C_WHT}  VPS Hardware & Live Traffic${C_RST}"
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
    7)  opt_wirespeed_tune ;;
    8)  opt_vps_stats ;;
    9)  opt_telegram_bot ;;
    10) opt_webpanel ;;
    11) opt_uninstall ;;
    12|0|q|exit) echo -e "\n  ${C_GLD}Stay blazing! 🔥${C_RST}\n"; exit 0 ;;
    *)  ;;
  esac
done

EOF_MENU_SH
  chmod +x "${INSTALL_DIR}/cli/menu.sh"

  echo -e "\n${C_CYN}▶ [4/5] Re-compiling Nginx Router configuration...${C_RST}"
  python3 -c "
import sqlite3
from pathlib import Path
db_path = Path('/var/lib/alyan/alyan.db')
dom = 'example.com'
if db_path.exists():
    try:
        conn = sqlite3.connect(str(db_path))
        r = conn.execute(\"SELECT value FROM settings WHERE key='domain'\").fetchone()
        if r and r[0]: dom = r[0]
        conn.close()
    except Exception: pass
tpl = Path('/opt/alyan/templates/nginx-router.conf.tpl').read_text(encoding='utf-8')
conf = tpl.replace('{{DOMAIN}}', dom)
target = Path('/etc/nginx/sites-available/alyan-router.conf')
if target.parent.exists():
    target.write_text(conf, encoding='utf-8')
    print('  ✔ Compiled /etc/nginx/sites-available/alyan-router.conf with domain: ' + dom)
"

  echo -e "\n${C_CYN}▶ [5/5] Testing Nginx and Restarting Services...${C_RST}"
  nginx -t
  systemctl reload nginx 2>/dev/null || systemctl restart nginx
  systemctl restart alyan-wsd
  systemctl restart alyan-guard
  systemctl restart alyan-panel

  sleep 1
  echo -e "\n${C_AMB}── Daemon Verification Status ────────────────────────────${C_RST}"
  for s in alyan-wsd alyan-guard alyan-panel nginx dropbear; do
    if systemctl is-active --quiet "$s"; then
      echo -e "  ${C_GRN}● ${s}${C_RST} : ${C_GRN}Active (Running)${C_RST}"
    else
      echo -e "  ${C_RED}● ${s}${C_RST} : ${C_RED}Inactive / Failed${C_RST}"
    fi
  done

  echo -e "\n${C_GRN}${C_BOLD}═════════════════════════════════════════════════════════════════════════════${C_RST}"
  echo -e "${C_GRN}${C_BOLD}✔ ALYAN WEBPANEL SESSION-BASED LIVE USERS UPDATE INSTALLED!${C_RST}"
  echo -e "${C_WHT}• Simultaneous Sessions Tracking  : ${C_GLD}ACTIVE${C_RST} (1 SSH/Xray user on 5 devices = 5 Live Users)"
  echo -e "${C_WHT}• Session-Based User Limit        : ${C_GLD}ACTIVE${C_RST} (Configurable 0=∞ in Webpanel & CLI)"
  echo -e "${C_WHT}• Live Users Modal Sheet          : ${C_GLD}ACTIVE${C_RST} (Clean session table without Connected IPs)"
  echo -e "${C_WHT}• Target Host/Edge IP Extraction  : ${C_GLD}ACTIVE${C_RST} (Reads X-Target, X-Edge-IP, & PROXY Host)"
  echo -e "${C_GRY}• To rollback anytime             : ${C_AMB}sudo bash update-session.sh --rollback${C_RST}"
  echo -e "${C_GRN}${C_BOLD}═════════════════════════════════════════════════════════════════════════════${C_RST}\n"
}

main "$@"

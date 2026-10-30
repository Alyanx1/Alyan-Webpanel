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
    const n = Number(b) || 0;
    if (n < 1024) return n + ' B';
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
    return `GET /alyan HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]`;
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
    setBayHead(
      'COMMAND DECK · LIVE TELEMETRY',
      'Core',
      'Real-time reactor load, multiplexed 80/443 health & interactive service tiles',
      `<button class="btn sm" id="btnCoreRefresh">${ic('refresh')}<span>Sync</span></button>
       <button class="btn-flame-launcher" id="btnFlameLauncher" type="button">
         <canvas class="btn-fire-cv" id="launcherFire"></canvas>
         <svg viewBox="0 0 64 64" class="flame-svg"><use href="#flame"/></svg>
         <span>Flame Launcher</span>
       </button>`
    );
    attachRealFire($('#launcherFire'), { w: 56, h: 32, cool: 4.1 });
    $('#btnCoreRefresh').onclick = () => renderCore();
    $('#btnFlameLauncher').onclick = openQuickSheet;

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
            <span class="sub">Click any tile to flip for Start / Restart / Stop / Logs</span>
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

    const sshSheetHtml = (liveIps) => liveIps.length
      ? `<div class="tbl-wrap"><table><thead><tr><th>User</th><th>Client IP</th></tr></thead><tbody>${liveIps.map(r => `<tr><td><b>${esc(r.user)}</b></td><td>${esc(r.ip)}</td></tr>`).join('')}</tbody></table></div>`
      : `<div class="empty"><p>No active SSH-WS, SSL or Dropbear sessions right now.</p></div>`;

    const initData = await api('/ssh');
    items = initData.items || [];
    STATE.cfg = initData.cfg; syncHud();

    const getLiveIps = () => items.flatMap(u => (u.status === 'disabled' ? [] : (u.ips || [])).map(ip => ({ user: u.username, ip })));

    setBayHead(
      'SSH · WS · SSL',
      'SSH Accounts',
      `Direct (22, 109, 143) · SSL (443) · WebSocket (80/443 → ${STATE.cfg.ws_path || '/alyan'})`,
      `<button class="btn sm" id="btnLiveIps">${ic('wifi')}<span id="btnLiveIpsTxt">Connected IPs (${getLiveIps().length})</span></button>
       <button class="btn btn-flame sm" id="btnAddSsh">${ic('plus')}<span>Create SSH Account</span></button>`
    );
    $('#btnAddSsh').onclick = () => openSshForm();
    $('#btnLiveIps').onclick = () => openSheet('Live Connected SSH IPs', 'REAL-IP CORRELATOR · LIVE 2S', `<div id="sshLiveSheetBody">${sshSheetHtml(getLiveIps())}</div>`);

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
      const liveMeta = $('#sshLiveMeta');
      if (liveMeta) liveMeta.innerHTML = `<i class="dot lit"></i> ${items.length} accounts · live 2s`;
      const openModalBody = $('#sshLiveSheetBody');
      if (openModalBody) openModalBody.innerHTML = sshSheetHtml(liveIps);

      const filtered = items.filter(u => u.username.toLowerCase().includes(STATE.searchSsh.toLowerCase()));
      host.innerHTML = filtered.length ? `<div class="cards">${filtered.map(u => {
        const isDis = u.status === 'disabled';
        const ipList = isDis ? [] : (u.ips || []);
        const onlineCnt = isDis ? 0 : (u.online || ipList.length || 0);
        const pct = u.gb_limit > 0 ? Math.min(100, (u.used_bytes / (u.gb_limit * 1073741824)) * 100) : 100;
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
            <div class="st"><span>IP LIMIT</span><b>${u.ip_limit > 0 ? u.ip_limit + ' IP' : 'Unlimited'}</b></div>
            <div class="st" title="${esc(ipList.join(', '))}"><span>LIVE IPS</span><b>${ipList.length}</b></div>
          </div>
          <div class="acc-act">
            <button class="btn sm btn-flame" data-ticket="${esc(u.username)}"><span>Info</span></button>
            <button class="btn sm ${isDis ? 'btn-toggle-on' : 'btn-toggle-off'}" title="${isDis ? 'Enable account' : 'Disable account'}" data-toggle="${esc(u.username)}" data-dis="${isDis ? '1' : '0'}">${ic(isDis ? 'check' : 'power')}<span>${isDis ? 'Enable' : 'Disable'}</span></button>
            <button class="icon-btn sm" title="Edit limits" data-edit="${esc(u.username)}">${ic('edit')}</button>
            <button class="icon-btn sm danger" title="Delete" data-del="${esc(u.username)}">${ic('trash')}</button>
          </div>
        </article>`;
      }).join('')}</div>` : `<div class="mod empty">${ic('tunnel')}<p>No matching SSH accounts found.</p></div>`;

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
          <div class="tk-row"><span>Limits</span><b>${u.gb_limit > 0 ? u.gb_limit + ' GB' : 'Unlimited'} · ${u.ip_limit > 0 ? u.ip_limit + ' IP' : 'Unlimited IP'}</b><span></span></div>
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
    openSheet(existing ? `Edit ${existing.username}` : 'Create SSH Account', 'SSH PROVISIONER', `
      <form class="stack" id="sshForm">
        ${existing ? '' : `<label class="field"><span>Username</span><input name="username" required pattern="[A-Za-z0-9_-]{1,31}" placeholder="Alyan" /><small>a-z, A-Z, 0-9, _ - (max 31 chars)</small></label>`}
        <label class="field"><span>${existing ? 'New Password (blank = keep)' : 'Password'}</span><input name="password" ${existing ? '' : 'required'} placeholder="1234" /></label>
        <div class="row3">
          <label class="field"><span>Days</span><div class="stepper"><button type="button">−</button><input name="days" type="number" min="1" value="${existing ? Math.max(1, daysLeft(existing.expiry)) : 30}" data-step="5"/><button type="button">+</button></div></label>
          <label class="field"><span>GB (0=∞)</span><div class="stepper"><button type="button">−</button><input name="gb_limit" type="number" min="0" value="${existing ? existing.gb_limit : 0}" data-step="10"/><button type="button">+</button></div></label>
          <label class="field"><span>IP (0=∞)</span><div class="stepper"><button type="button">−</button><input name="ip_limit" type="number" min="0" value="${existing ? existing.ip_limit : 2}" data-step="1"/><button type="button">+</button></div></label>
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

    const xraySheetHtml = (liveIps) => liveIps.length
      ? `<div class="tbl-wrap"><table><thead><tr><th>Client</th><th>Protocol</th><th>Client IP</th></tr></thead><tbody>${liveIps.map(r => `<tr><td><b>${esc(r.user)}</b></td><td>${esc(r.proto)}</td><td>${esc(r.ip)}</td></tr>`).join('')}</tbody></table></div>`
      : `<div class="empty"><p>No active VLESS, VMess or Trojan sessions right now.</p></div>`;

    const initData = await api('/xray');
    items = initData.items || [];
    STATE.cfg = initData.cfg; syncHud();

    const getLiveIps = () => items.flatMap(u => (u.status === 'disabled' ? [] : (u.ips || [])).map(ip => ({ user: u.username, proto: u.proto.toUpperCase(), ip })));

    const syncBayHeader = () => {
      setBayHead(
        'XRAY CORE',
        'Xray',
        'Zero-downtime VLESS · VMess · Trojan over WS, gRPC & XHTTP on 80 / 443',
        `<button class="btn sm" id="btnXrayLiveIps">${ic('wifi')}<span id="btnXrayLiveIpsTxt">Connected IPs (${getLiveIps().length})</span></button>
         <button class="btn btn-flame sm" id="btnAddXray">${ic('plus')}<span>Create ${STATE.xrayProto.toUpperCase()}</span></button>`
      );
      $('#btnAddXray').onclick = () => openXrayForm(STATE.xrayProto);
      $('#btnXrayLiveIps').onclick = () => openSheet('Live Connected Xray IPs', 'REAL-IP CORRELATOR · LIVE 2S', `<div id="xrayLiveSheetBody">${xraySheetHtml(getLiveIps())}</div>`);
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
      const openModalBody = $('#xrayLiveSheetBody');
      if (openModalBody) openModalBody.innerHTML = xraySheetHtml(liveIps);

      const protoAll = items.filter(u => u.proto === STATE.xrayProto);
      const liveMeta = $('#xrayLiveMeta');
      if (liveMeta) liveMeta.innerHTML = `<i class="dot lit"></i> ${protoAll.length} clients · live 2s`;

      const list = protoAll.filter(u => u.username.toLowerCase().includes(STATE.searchXray.toLowerCase()));
      host.innerHTML = list.length ? `<div class="cards">${list.map(u => {
        const isDis = u.status === 'disabled';
        const ipList = isDis ? [] : (u.ips || []);
        const onlineCnt = isDis ? 0 : (ipList.length || u.online || 0);
        const pct = u.gb_limit > 0 ? Math.min(100, (u.used_bytes / (u.gb_limit * 1073741824)) * 100) : 100;
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
              <div class="acc-m"><b>${esc(u.proto.toUpperCase())}</b> · cap <b>${u.ip_limit > 0 ? u.ip_limit + ' IP' : 'Unlimited'}</b> · exp <b>${esc(u.expiry)}</b></div>
              <div class="uuid" data-cpuuid="${esc(u.uuid)}">${esc(u.uuid.slice(0, 18))}… ${ic('copy')}</div>
            </div>
          </div>
          <div class="meter">
            <div class="meter-h"><span>TRAFFIC</span><b>${fmtBytes(u.used_bytes)} / ${u.gb_limit > 0 ? u.gb_limit + ' GB' : '∞'}</b></div>
            <div class="bar ${u.gb_limit > 0 ? '' : 'inf'}"><i style="width:${pct.toFixed(1)}%"></i></div>
          </div>
          <div class="acc-stats">
            <div class="st" title="${esc(ipList.join(', '))}"><span>LIVE IPS</span><b>${onlineCnt}</b></div>
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
    const curProto = existing ? existing.proto : proto;
    openSheet(existing ? `Edit ${existing.username} (${curProto.toUpperCase()})` : `Create ${curProto.toUpperCase()} Client`, existing ? 'EDIT XRAY CLIENT' : 'XRAY HOT-PROVISION', `
      <form class="stack" id="xrayForm">
        <div class="row2">
          <label class="field"><span>Username</span><input name="username" required pattern="[A-Za-z0-9_-]{1,31}" value="${existing ? esc(existing.username) : ''}" placeholder="Alyan"/></label>
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
          <label class="field"><span>IP (0=∞)</span><div class="stepper"><button type="button">−</button><input name="ip_limit" type="number" min="0" value="${existing ? existing.ip_limit : 2}" data-step="1"/><button type="button">+</button></div></label>
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
    setBayHead(
      'DAEMONS & PORTS',
      'Engine',
      'HAProxy · Nginx · Dropbear · WS-Proxy · Xray · Alyan Guard · Bot · Panel',
      `<button class="btn sm" id="btnRefreshEng">${ic('refresh')}<span>Refresh</span></button>
       <button class="btn btn-flame sm" id="btnRestartAll">${ic('bolt')}<span>Restart Full Stack</span></button>`
    );

    const drawEngine = async () => {
      const { services, ports } = await api('/engine');
      const pubPorts = ports.filter(p => p.scope === 'public');
      const locPorts = ports.filter(p => p.scope !== 'public');

      $('#view').innerHTML = `
        <div class="grid g2">
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
                  <div class="svc-a">
                    <button class="switch ${s.status === 'running' ? 'on' : ''}" title="${s.status === 'running' ? 'Stop' : 'Start'}" data-svctog="${esc(s.id)}" data-run="${s.status === 'running' ? '1' : '0'}"></button>
                    <button class="icon-btn sm" title="Restart" data-svcrst="${esc(s.id)}">${ic('refresh')}</button>
                    <button class="icon-btn sm" title="Logs" data-svclog="${esc(s.id)}">${ic('terminal')}</button>
                  </div>
                </div>`).join('')}
            </div>
          </section>

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
          </section>
        </div>`;

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
    };

    $('#btnRefreshEng').onclick = drawEngine;
    $('#btnRestartAll').onclick = async () => {
      await api('/service/all/restart', { method: 'POST' });
      toast('Full tunneling stack restarted cleanly');
      drawEngine();
    };
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
    setBayHead(
      'SYSTEM CONFIGURATION',
      'Settings',
      'Domain & SSL · Webpanel Port · SSH Handshake Banner · Admin Security & Stack Repair'
    );

    $('#view').innerHTML = `
      <div class="grid g2">
        <!-- Domain, SSL & Panel Port -->
        <section class="mod">
          <div class="mod-h"><h3>${ic('globe')} Domain, SSL &amp; Panel Port</h3><span class="pill lit">SSL valid · ${cfg.ssl_days}d</span></div>
          <form class="stack" id="domForm">
            <div class="row2">
              <label class="field"><span>Custom Tunnel Domain</span><input name="domain" required value="${esc(cfg.domain)}"/></label>
              <label class="field"><span>Web Panel HTTPS Port</span><input name="panel_port" type="number" min="1024" max="65535" required value="${cfg.panel_port}"/></label>
            </div>
            <p class="note">Changing domain automatically issues a fresh Let's Encrypt EC-256 certificate, rebuilds the HAProxy PEM bundle, and reloads Nginx + Xray without dropping active sessions.</p>
            <div class="chips">
              <button type="submit" class="btn btn-flame sm">${ic('check')}<span>Apply Domain &amp; Port</span></button>
              <button type="button" class="btn sm" id="btnRenewSsl">${ic('lock')}<span>Issue / Renew SSL</span></button>
            </div>
          </form>
        </section>

        <!-- Admin Security & Stack Repair -->
        <section class="mod">
          <div class="mod-h"><h3>${ic('key')} Admin Security &amp; Stack Repair</h3><span class="sub">Password &amp; Wire-Speed Tune</span></div>
          <form class="stack" id="pwForm">
            <div class="row2">
              <label class="field"><span>New Admin Password</span><input name="new_password" type="password" required minlength="6" placeholder="••••••••"/></label>
              <label class="field"><span>Confirm Password</span><input name="confirm_password" type="password" required minlength="6" placeholder="••••••••"/></label>
            </div>
            <p class="note">One-click Stack Repair re-applies unthrottled Kernel BBR + FQ pacing, clears any NIC traffic shapers, and syncs HAProxy, Nginx, Dropbear &amp; Xray.</p>
            <div class="chips">
              <button type="submit" class="btn btn-flame sm">${ic('lock')}<span>Update Password</span></button>
              <button type="button" class="btn sm" id="btnFixStack">${ic('refresh')}<span>Fix &amp; Optimize Stack</span></button>
            </div>
          </form>
        </section>

        <!-- SSH Handshake Banner -->
        <section class="mod span2">
          <div class="mod-h"><h3>${ic('terminal')} SSH Handshake Banner</h3><span class="sub">Dropbear + OpenSSH</span></div>
          <form class="stack" id="bannerForm">
            <label class="field"><span>HTML / ANSI Banner Markup</span><textarea name="banner">${esc(cfg.banner || '')}</textarea></label>
            <div><button type="submit" class="btn btn-flame sm">${ic('check')}<span>Save SSH Banner</span></button></div>
          </form>
        </section>
      </div>`;

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
      if (fd.new_password !== fd.confirm_password) { toast('Passwords do not match', 'err'); return; }
      await api('/settings', { method: 'POST', body: { new_password: fd.new_password } });
      e.target.reset();
      toast('Admin password updated');
    };
    $('#btnFixStack').onclick = async () => {
      await api('/settings', { method: 'POST', body: { maint: 'fix_ws_ssl_stack' } });
      await api('/service/all/restart', { method: 'POST' });
      toast('Wire-Speed BBR+FQ + SSH-WS + SSL + Xray stack optimized & restarted');
    };
  }

  /* ═════════════════════ 7. ADMINS (Super Admin / Reseller / Viewer RBAC) ═════════════════════ */
  async function renderAdmins() {
    const { items } = await api('/admins');
    setBayHead(
      'ROLE-BASED ACCESS CONTROL',
      'Admins',
      'Manage Super Admins, Reseller Admins with account quotas & read-only Viewers',
      `<button class="btn btn-flame sm" id="btnNewAdmin">${ic('plus')}<span>Add Panel Admin</span></button>`
    );
    $('#btnNewAdmin').onclick = openAdminForm;

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
              ${a.username === 'admin' ? `<span class="pill lit">Primary Root Owner</span>` : `<button class="btn btn-danger sm" data-adel="${esc(a.username)}">${ic('trash')}<span>Revoke</span></button>`}
            </div>
          </article>`).join('')}
      </div>`;

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

  function openAdminForm() {
    openSheet('Create Panel Admin / Reseller', 'ADMIN RBAC', `
      <form class="stack" id="admForm">
        <div class="row2">
          <label class="field"><span>Username</span><input name="username" required pattern="[A-Za-z0-9_-]{3,24}" placeholder="reseller2"/></label>
          <label class="field"><span>Password</span><input name="password" type="password" required minlength="6" placeholder="••••••••"/></label>
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
    const cmds = [
      { label: 'Go to Core', icon: 'core', run: () => go('core'), key: 'G C' },
      { label: 'Create SSH Account (/alyan)', icon: 'plus', run: () => { go('tunnels'); setTimeout(() => openSshForm(), 40); }, key: 'N S' },
      { label: 'Create VLESS Client', icon: 'bolt', run: () => { STATE.xrayProto = 'vless'; go('xray'); setTimeout(() => openXrayForm('vless'), 40); }, key: 'N V' },
      { label: 'Create VMess Client', icon: 'bolt', run: () => { STATE.xrayProto = 'vmess'; go('xray'); setTimeout(() => openXrayForm('vmess'), 40); }, key: 'N M' },
      { label: 'Create Trojan Client', icon: 'lock', run: () => { STATE.xrayProto = 'trojan'; go('xray'); setTimeout(() => openXrayForm('trojan'), 40); }, key: 'N T' },
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

/* Speil-orb lettvekt (Claude 5.11.2026) – sparer GPU/CPU på SATS-speilet (RK3399, Mali-T860, Fully/WebView).
 * Problem: hvileskjermen (jarvis-hvile-card) tegner ~400 enkeltkall per bilde + 22-90 shadowBlur-prikker på et fullskjerms
 * canvas. På speilet gikk GPU-tråden (Chrome_InProcGpu) i ~60 % av en LITTLE-kjerne, ~1700 GPU-avbrudd/s, hvert bilde tok
 * ~30 ms (78 % «janky») og halve SoC-en var opptatt bare for å vise skjermspareren. Det tok også CPU fra mikrofonen (USB-avbrudd).
 * Løsning: samme bilde med ~20 tegnekall – linjer og noder samlet i styrkegrupper, glød som ferdig sprite i stedet for
 * shadowBlur, og canvas på 0,75x oppløsning (kulen er myk; GPU-en skalerer opp gratis). Jevn 30 fps-rytme (terskel 29 ms).
 * Gjelder bare Android-nettlesere på /jarvis-speil. Veggpanelet (Linux/NUC) er urørt. Feil → faller tilbake til original _start.
 * Tilbake til original: slett denne ressursen (Innstillinger → Dashbord → Ressurser) og last siden på nytt. */
(() => {
  if (!/Android/.test(navigator.userAgent || '')) return;
  const ALVORLIG = /åpen|ulåst|frost|røyk|brann|fryser|lekk|varm|kald|alarm/i; // som i jarvis-hvile-card.js
  const nivaa = (o) => { // 0..1, som i originalen
    if (!o || !o.a) return 0; const b = new Uint8Array(o.a.fftSize); o.a.getByteTimeDomainData(b);
    let s = 0; for (let i = 0; i < b.length; i++) { const v = (b[i] - 128) / 128; s += v * v; } return Math.min(1, Math.sqrt(s / b.length) * 4);
  };
  const micAktiv = () => { const m = window.__jarvisMic; return !!(m && m.st.getAudioTracks().some(t => t.readyState === 'live' && t.enabled)); };

  function hurtigStart(cv) {
    const Q = 0.75; // intern oppløsning relativt til CSS-piksler (originalen: 1,125 = enhetens pikseltetthet)
    const ctx = cv.getContext('2d', { alpha: false });
    const N = 150, P = [];
    for (let i = 0; i < N; i++) {
      const u = Math.random() * 2 - 1, th = Math.random() * Math.PI * 2, r = 0.55 + Math.random() * 0.45;
      P.push({ x: Math.sqrt(1 - u * u) * Math.cos(th) * r, y: u * r, z: Math.sqrt(1 - u * u) * Math.sin(th) * r, f: Math.random() * 6.28, lys: 0 });
    }
    const L = [];
    P.forEach((p, i) => {
      P.map((q, j) => [j, (p.x - q.x) ** 2 + (p.y - q.y) ** 2 + (p.z - q.z) ** 2]).filter(a => a[0] !== i)
        .sort((a, b) => a[1] - b[1]).slice(0, 3).forEach(([j]) => { if (i < j) L.push([i, j]); });
    });
    const pulser = [], ringer = [];
    let sist = 0, glatt = 0, vinkel = 0, nesteBlink = performance.now() + 4000, synt = 0;

    // glød-sprite (erstatter shadowBlur): hvit kjerne + myk fargeglød, lages på nytt bare når fargen skifter
    let spriteNokkel = '', sprite = null;
    const lagSprite = (f) => {
      const key = f.join(',');
      if (key === spriteNokkel) return sprite;
      const s = 64, c = document.createElement('canvas'); c.width = c.height = s;
      const g = c.getContext('2d'), gr = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      gr.addColorStop(0, 'rgba(255,255,255,0.95)'); gr.addColorStop(0.17, 'rgba(255,255,255,0.85)');
      gr.addColorStop(0.24, 'rgba(' + key + ',0.22)'); gr.addColorStop(0.55, 'rgba(' + key + ',0.06)'); gr.addColorStop(1, 'rgba(' + key + ',0)');
      g.fillStyle = gr; g.fillRect(0, 0, s, s);
      spriteNokkel = key; sprite = c; return c;
    };

    const NL = 6, NN = 8; // antall styrkegrupper for linjer / noder
    const lb = Array.from({ length: NL }, () => ({ a: new Float32Array(L.length * 4), n: 0 }));
    const nb = Array.from({ length: NN }, () => ({ a: new Float32Array(N * 3), n: 0 }));

    const tegn = (t) => {
      this._raf = requestAnimationFrame(tegn);
      // 30 fps = hvert 2. skjermbilde (33,3 ms). Terskel 29 i stedet for 33: med 33 falt «to bilder siden sist» (32,9 ms) ofte under
      // grensen, så hvert 5. bilde ble utsatt til 50 ms (målt p90 = 50 ms, 18 % >34 ms) og animasjonen virket ujevn.
      if (t - sist < 29) return; const dt = Math.min(100, t - sist); sist = t;
      const W = Math.round(cv.clientWidth * Q), H = Math.round(cv.clientHeight * Q);
      if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; }
      // tilstand (som originalen)
      const sat = this._satState();
      const lyd = window.__jarvisLyd, lytter = micAktiv() || sat === 'listening', tenker = sat === 'processing', hus = this._husSnakker() || sat === 'responding';
      let amp = 0;
      if (lyd) amp = nivaa(lyd);
      else if (hus) { synt += dt; amp = Math.max(0, Math.sin(synt / 90) * Math.sin(synt / 37 + 1) * 0.9 + (Math.random() - 0.5) * 0.3); }
      else if (lytter) amp = window.__jarvisMic ? nivaa(window.__jarvisMic) * 0.8 : 0.15 + 0.1 * Math.sin(t / 300);
      else if (tenker) amp = 0.25 + 0.2 * Math.random();
      glatt += (amp - glatt) * (amp > glatt ? 0.55 : 0.18);
      const snakker = !!lyd || hus;
      const varsel = this._varsler().some(x => ALVORLIG.test(String(x)));
      const farge = lytter && !snakker ? [60, 255, 200] : tenker ? [140, 150, 255] : snakker ? [150, 230, 255] : varsel ? [255, 140, 60] : [40, 200, 255];
      const rgba = (a) => 'rgba(' + farge[0] + ',' + farge[1] + ',' + farge[2] + ',' + a + ')';
      let blink = 0;
      if (tenker && Math.random() < 0.25) { P[(Math.random() * N) | 0].lys = 1; }
      if (t > nesteBlink && !snakker && !lytter && !tenker) { this._blink = t; nesteBlink = t + 5000 + Math.random() * 9000;
        for (let k = 0; k < 14; k++) pulser.push({ l: L[(Math.random() * L.length) | 0], s: 0, v: 0.03 + Math.random() * 0.03 });
        P[(Math.random() * N) | 0].lys = 1; ringer.push({ r: 0.2, a: 0.35 }); }
      if (this._blink) { const e = (t - this._blink) / 600; blink = e < 1 ? Math.sin(e * Math.PI) : 0; }
      ctx.fillStyle = 'rgba(2,6,13,' + (snakker ? 0.45 : 0.35) + ')'; ctx.fillRect(0, 0, W, H);
      const cx = W * 0.62, cy = H * 0.46, R = Math.min(W, H) * 0.44 * (1 + glatt * 0.08);
      this._kjerne = { x: cx / Q, y: cy / Q, r: (R * 0.35) / Q };
      vinkel += dt / (tenker ? 1400 : lytter ? 3500 : snakker ? 5000 : 9000);
      const a = vinkel, b = Math.sin(t / 13000) * 0.4, ca = Math.cos(a), sa = Math.sin(a), cb = Math.cos(b), sb = Math.sin(b);
      const S = P.map(p => {
        const x = p.x * ca - p.z * sa; let z = p.x * sa + p.z * ca; const y = p.y;
        const y2 = y * cb - z * sb; z = y * sb + z * cb;
        const k = 1.6 / (2.6 - z); return { X: cx + x * R * k, Y: cy + y2 * R * k, z };
      });
      // kjerne (ett fyll)
      const puls = 0.5 + 0.5 * Math.sin(t / (varsel && !snakker ? 350 : 1100));
      const kr = R * (0.5 + glatt * 0.35 + blink * 0.08);
      const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, kr);
      g.addColorStop(0, snakker || lytter ? 'rgba(255,255,255,' + (0.25 + glatt * 0.6) + ')' : rgba(0.28 + 0.2 * puls + 0.4 * blink));
      g.addColorStop(0.35, rgba(0.18 + glatt * 0.4 + 0.2 * blink)); g.addColorStop(1, rgba(0));
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(cx, cy, kr, 0, 6.29); ctx.fill();
      // ringer
      if (snakker && glatt > 0.35 && Math.random() < glatt * 0.5) ringer.push({ r: 0.25, a: 0.5 * glatt });
      ctx.lineWidth = Math.max(1, 1.5 * Q);
      for (let k = ringer.length - 1; k >= 0; k--) {
        const q = ringer[k]; q.r += 0.018; q.a *= 0.955; if (q.a < 0.02) { ringer.splice(k, 1); continue; }
        ctx.strokeStyle = rgba(q.a); ctx.beginPath(); ctx.arc(cx, cy, R * q.r, 0, 6.29); ctx.stroke();
      }
      // linjer: NL styrkegrupper, ett strøk per gruppe (originalen: ett strøk per linje)
      for (let i = 0; i < NL; i++) lb[i].n = 0;
      for (let k = 0; k < L.length; k++) {
        const p = S[L[k][0]], q = S[L[k][1]], dyb = (p.z + q.z + 2) / 4;
        const bk = lb[Math.max(0, Math.min(NL - 1, (dyb * NL) | 0))];
        bk.a[bk.n++] = p.X; bk.a[bk.n++] = p.Y; bk.a[bk.n++] = q.X; bk.a[bk.n++] = q.Y;
      }
      ctx.lineWidth = Q; // = 1 CSS-piksel
      for (let i = 0; i < NL; i++) {
        const bk = lb[i]; if (!bk.n) continue;
        ctx.strokeStyle = rgba(0.05 + 0.22 * ((i + 0.5) / NL) + glatt * 0.25);
        ctx.beginPath(); for (let j = 0; j < bk.n; j += 4) { ctx.moveTo(bk.a[j], bk.a[j + 1]); ctx.lineTo(bk.a[j + 2], bk.a[j + 3]); } ctx.stroke();
      }
      // signaler (glødende prikker): oppdatering som i originalen, tegnes som sprites (samme tekstur → ett GPU-kall)
      const maks = tenker ? 90 : snakker ? 30 + glatt * 60 : lytter ? 45 : varsel ? 40 : 22;
      if (pulser.length < maks && Math.random() < 0.5 + glatt) pulser.push({ l: L[(Math.random() * L.length) | 0], s: 0, v: 0.01 + Math.random() * 0.025 + glatt * 0.03, inn: lytter && !snakker });
      const spr = lagSprite(farge), sz = (22 + glatt * 10) * Q;
      for (let k = pulser.length - 1; k >= 0; k--) {
        const u = pulser[k]; u.s += u.v; if (u.s >= 1) { P[u.l[1]].lys = Math.max(P[u.l[1]].lys, 0.6); pulser.splice(k, 1); continue; }
        const p = S[u.l[0]], q = S[u.l[1]];
        let X = p.X + (q.X - p.X) * u.s, Y = p.Y + (q.Y - p.Y) * u.s;
        if (u.inn) { X += (cx - X) * u.s * 0.6; Y += (cy - Y) * u.s * 0.6; }
        ctx.drawImage(spr, X - sz / 2, Y - sz / 2, sz, sz);
      }
      // noder: NN styrkegrupper, ett fyll per gruppe; de hvite «lys»-nodene for seg
      for (let i = 0; i < NN; i++) nb[i].n = 0;
      const lysNoder = [];
      for (let i = 0; i < N; i++) {
        const s = S[i], p = P[i]; p.lys *= 0.93;
        const dyb = (s.z + 1) / 2, fl = 0.6 + 0.4 * Math.sin(t / 700 + p.f), rad = (1 + 2.6 * dyb + p.lys * 2 + glatt * 1.2) * Q;
        if (p.lys > 0.1) { lysNoder.push([s.X, s.Y, rad, p.lys]); continue; }
        const al = Math.min(1, 0.25 + 0.7 * dyb * fl + glatt * 0.3);
        const bk = nb[Math.max(0, Math.min(NN - 1, (al * NN) | 0))];
        bk.a[bk.n++] = s.X; bk.a[bk.n++] = s.Y; bk.a[bk.n++] = rad;
      }
      for (let i = 0; i < NN; i++) {
        const bk = nb[i]; if (!bk.n) continue;
        ctx.fillStyle = rgba((i + 0.5) / NN);
        ctx.beginPath(); for (let j = 0; j < bk.n; j += 3) { ctx.moveTo(bk.a[j] + bk.a[j + 2], bk.a[j + 1]); ctx.arc(bk.a[j], bk.a[j + 1], bk.a[j + 2], 0, 6.29); } ctx.fill();
      }
      for (const [x, y, r, l] of lysNoder) { ctx.fillStyle = 'rgba(255,255,255,' + l + ')'; ctx.beginPath(); ctx.arc(x, y, r, 0, 6.29); ctx.fill(); }
    };
    this._raf = requestAnimationFrame(tegn);
  }

  const patch = () => {
    const C = customElements.get('jarvis-hvile-card');
    if (!C || C.prototype.__hurtigOrb) return;
    const orig = C.prototype._start;
    C.prototype._start = function (cv) {
      if (!/^\/jarvis-speil(\/|$)/.test(location.pathname)) return orig.call(this, cv); // bare speil-dashbordet
      try { return hurtigStart.call(this, cv); } catch (e) { console.warn('speil-orb-lett: faller tilbake til original', e); return orig.call(this, cv); }
    };
    C.prototype.__hurtigOrb = true;
  };
  if (customElements.get('jarvis-hvile-card')) patch(); else customElements.whenDefined('jarvis-hvile-card').then(patch);
})();

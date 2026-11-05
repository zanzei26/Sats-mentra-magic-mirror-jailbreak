/* Speil: lettere 3D-hus (NeonPlan 3D) – Claude 5.11.2026 – SATS-speilet (RK3399, Mali-T860, Fully/WebView 109).
 * Gjelder kun Android og dashbordet /jarvis-speil, visningen /hus-3d.
 *
 * Problem 1: Three.js (i NeonPlan 3D) tegner hvert gjennomsiktige, tosidige materiale to ganger per bilde
 *   (bakflater, så forflater) og setter material.needsUpdate = true begge gangene. Det tvinger Three til å regne ut
 *   shaderparametre og programnøkkel på nytt for hvert slikt objekt i hvert bilde (getParameters / getProgramCacheKey /
 *   getProgram: ca. 10 % av hovedtråden). Med alle funksjonene på er det ca. 20-33 slike materialer.
 *   Løsning: forceSinglePass = true på Material.prototype (aksessor som alltid gir true). Da tegnes de i ett pass, uten
 *   needsUpdate-støyen. Bildet er likt (sjekket mot skjermbilde fra enheten).
 *
 * Problem 2: hver state-endring fra Home Assistant (ca. 6 i sekundet her: effektmålere, ruter) setter `hass` på
 *   3D-kortet, og NeonPlan kjører hele oppdateringen sin (syncDevices m.m.) i samme oppgave. Det gir hakk på 15-30 ms
 *   midt i en dreiing. Mens man rører skjermen (og 0,6 s etterpå) holdes nyeste `hass` tilbake og leveres når
 *   berøringen er over (senest etter 3 s). I ro går alt rett gjennom som før.
 */
(() => {
  const NS = '__speil3dLett';
  if (window[NS]) return;
  window[NS] = true;
  if (!/Android/i.test(navigator.userAgent)) return;

  const PATH = '/jarvis-speil';
  const VIEW = '/hus-3d';
  const BUSY_MS = 600;   // regnes som "i bruk" så lenge etter siste berøring
  const MAX_MS = 3000;   // holdes aldri tilbake lenger enn dette
  const onPath = () => location.pathname.indexOf(PATH) === 0;

  // --- berøringsklokke -------------------------------------------------------------------------------------------
  let lastTouch = 0;
  const touch = () => { lastTouch = performance.now(); };
  ['pointerdown', 'pointermove', 'pointerup', 'touchstart', 'touchmove', 'wheel'].forEach((ev) =>
    window.addEventListener(ev, touch, { capture: true, passive: true }));

  // --- 2) hass-drosling på 3D-kortet -----------------------------------------------------------------------------
  const S = Symbol('speil3d');
  function throttleHass(C) {
    const P = C.prototype;
    const d = Object.getOwnPropertyDescriptor(P, 'hass');
    if (!d || !d.get || !d.set || d.set.__speil3d) return;
    const set = function (v) {
      const self = this;
      const st = self[S] || (self[S] = { timer: 0, pending: null, since: 0 });
      const now = performance.now();
      if (!(onPath() && now - lastTouch < BUSY_MS)) {   // i ro: rett gjennom
        if (st.timer) { clearTimeout(st.timer); st.timer = 0; }
        st.pending = null; st.since = 0;
        d.set.call(self, v);
        return;
      }
      st.pending = v;
      if (!st.since) st.since = now;
      if (st.timer) return;
      const tick = () => {
        st.timer = 0;
        const n = performance.now();
        if (n - lastTouch < BUSY_MS && n - st.since < MAX_MS) {
          st.timer = setTimeout(tick, Math.max(30, BUSY_MS - (n - lastTouch) + 20));
          return;
        }
        const p = st.pending; st.pending = null; st.since = 0;
        if (p !== null) d.set.call(self, p);
      };
      st.timer = setTimeout(tick, BUSY_MS);
    };
    set.__speil3d = true;
    Object.defineProperty(P, 'hass', { configurable: true, enumerable: d.enumerable, get: d.get, set });
  }
  customElements.whenDefined('neonplan3d-card').then((C) => { try { throttleHass(C); } catch (e) { /* uten drosling */ } });

  // --- 1) ett pass for gjennomsiktige, tosidige materialer --------------------------------------------------------
  const findDeep = (root, sel) => {
    const r = root.querySelector(sel);
    if (r) return r;
    for (const el of root.querySelectorAll('*')) {
      if (el.shadowRoot) { const x = findDeep(el.shadowRoot, sel); if (x) return x; }
    }
    return null;
  };
  let tries = 0;
  const iv = setInterval(() => {
    try {
      if (!onPath() || location.pathname.indexOf(VIEW) < 0) return;
      const host = findDeep(document, 'fp3d-view3d');
      const vw = host && host.viewer;
      if (!vw || !vw.scene) return;
      let m0 = null;
      const mats = new Set();
      vw.scene.traverse((o) => {
        const m = o.material;
        if (!m) return;
        (Array.isArray(m) ? m : [m]).forEach((x) => { mats.add(x); if (!m0) m0 = x; });
      });
      if (!m0) return;
      let P = Object.getPrototypeOf(m0);
      while (P && !Object.prototype.hasOwnProperty.call(P, 'needsUpdate')) P = Object.getPrototypeOf(P);
      if (!P || !('forceSinglePass' in m0)) { if (++tries > 5) clearInterval(iv); return; }
      Object.defineProperty(P, 'forceSinglePass', { configurable: true, enumerable: false, get() { return true; }, set() {} });
      mats.forEach((x) => { if (Object.prototype.hasOwnProperty.call(x, 'forceSinglePass')) delete x.forceSinglePass; });
      clearInterval(iv);
      if (vw.invalidate) vw.invalidate();
    } catch (e) { if (++tries > 5) clearInterval(iv); }
  }, 1500);
})();

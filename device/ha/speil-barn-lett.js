/* Speil: lettere Barn-side (Claude 5.11.2026) – tegning og bakgrunn på SATS-speilet (RK3399, Mali-T860, Fully/WebView).
 * Problem 1 (tegning): jarvis-barn-card tegner HELE tegningen på nytt (clearRect + ett stroke()-kall per linjestykke) for
 *   hver eneste pointermove. Jo mer barnet har tegnet, jo tyngre blir hver bevegelse (O(n) per hendelse), og tegnefeltet er
 *   hele skjermen. På Familie-kortet er feltet lite, derfor merkes det der mye mindre.
 * Problem 2 (bakgrunn): .rot animerer background-position på et 4x stort gradient-bilde i 30 s-løkke, og alle .boble-panelene
 *   har backdrop-filter:blur(4px) over den animerte bakgrunnen. Det betyr full ny rasterering + ny uskarphet av store flater
 *   hvert eneste bilde, hele tiden mens Barn-siden er åpen.
 * Løsning: (1) bare det NYE linjestykket tegnes per pointermove (samme linjer, samme farger – originalens lagring og angre/tøm/
 *   gjenoppretting er uendret), (2) bakgrunnen står stille (pastell-regnbue over hele flaten), og panelene mister blur (litt mer
 *   dekkende hvit). De svevende emojiene beholdes mens barnet bruker siden, men settes på pause etter 20 s uten berøring (se rolig()).
 * Gjelder bare Android-nettlesere på /jarvis-speil. Veggpanelet (Linux/NUC) er urørt. Feil → originalen kjører som før.
 * Tilbake til original: slett denne ressursen og last siden på nytt. */
(() => {
  if (!/Android/.test(navigator.userAgent || '')) return;
  const gyldig = () => /^\/jarvis-speil(\/|$)/.test(location.pathname); // bare speil-dashbordet

  function lettStil(self) {
    const st = document.createElement('style');
    st.textContent = '.rot{animation:none!important;background-size:100% 100%!important;background-position:0 0!important}' +
      '.boble{-webkit-backdrop-filter:none!important;backdrop-filter:none!important;background:#ffffffe8!important}';
    self.shadowRoot.appendChild(st); console.info('speil-barn-lett: stil aktiv');
  }

  // Problem 3 (hvile): de 12 svevende emojiene og den pulserende stjernen animeres hele tiden og holder GPU/kompositoren våken
  //   (60 bilder i sekundet på en ellers stille side). Etter 20 s uten berøring settes animasjonene på pause (emojiene blir stående
  //   der de er); berøring starter dem igjen. Skjermspareren kommer uansett etter to minutter.
  function rolig(self) {
    const st = document.createElement('style');
    st.textContent = '.rot.stille .fly,.rot.stille .stjerne{animation-play-state:paused!important}';
    self.shadowRoot.appendChild(st);
    let tid = null;
    const sett = () => {
      const rot = self.shadowRoot.querySelector('.rot'); if (!rot) return;
      rot.classList.remove('stille'); clearTimeout(tid);
      tid = setTimeout(() => { const r = self.shadowRoot.querySelector('.rot'); if (r) r.classList.add('stille'); }, 20000);
    };
    self.addEventListener('pointerdown', sett, { capture: true, passive: true });
    self.addEventListener('pointermove', sett, { capture: true, passive: true });
    sett(); console.info('speil-barn-lett: ro aktiv');
  }

  function lettTegning(self) {
    const c = self.$('lerret'); if (!c) return;
    const ctx = c.getContext('2d');
    const dpr = () => window.devicePixelRatio || 1;
    const X = p => p[0] * c.width, Y = p => p[1] * c.height;
    // samme punktberegning som originalen (andeler 0–1 av feltet)
    const pkt = e => { const r = c.getBoundingClientRect(); const f = x => Math.round(Math.min(1, Math.max(0, x)) * 10000) / 10000; return [f((e.clientX - r.left) / r.width), f((e.clientY - r.top) / r.height)]; };
    let ned = false, lengde0 = 0;
    // før originalens pointerdown: husk hvor mange streker som fantes, så vi vet at neste strek er den nye
    c.addEventListener('pointerdown', () => { ned = false; try { lengde0 = self._streker.length; } catch (e) { lengde0 = -1; } }, { capture: true });
    // etter originalens pointerdown: den nye streken ligger sist (ikke for stempel)
    c.addEventListener('pointerdown', () => {
      try { const a = self._streker; ned = lengde0 >= 0 && a.length === lengde0 + 1 && a[a.length - 1].type !== 'stempel'; } catch (e) { ned = false; }
    });
    const slutt = () => { ned = false; };
    c.addEventListener('pointerup', slutt); c.addEventListener('pointercancel', slutt);
    // capture-fasen går før originalens lytter på samme element; stopImmediatePropagation hindrer «tegn alt på nytt»
    c.addEventListener('pointermove', e => {
      if (!ned) return;
      const a = self._streker, s = a[a.length - 1];
      if (!s || a.length !== lengde0 + 1 || s.type === 'stempel') return;
      e.stopImmediatePropagation();
      const forrige = s.p[s.p.length - 1], ny = pkt(e); s.p.push(ny);
      // ett linjestykke, nøyaktig som originalens tegnStrek for punkt nr. i
      ctx.lineCap = ctx.lineJoin = 'round'; ctx.lineWidth = s.st * dpr();
      ctx.globalCompositeOperation = s.type === 'visk' ? 'destination-out' : 'source-over';
      ctx.strokeStyle = s.type === 'regnbue' ? `hsl(${(s.h0 + (s.p.length - 1) * 6) % 360},90%,55%)` : s.f;
      ctx.beginPath(); ctx.moveTo(X(forrige), Y(forrige)); ctx.lineTo(X(ny), Y(ny)); ctx.stroke();
      ctx.globalCompositeOperation = 'source-over';
    }, { capture: true });
    console.info('speil-barn-lett: tegning aktiv');
  }

  const patch = () => {
    const B = customElements.get('jarvis-barn-card');
    if (!B || B.prototype.__lett) return;
    B.prototype.__lett = true;
    const oBygg = B.prototype._bygg, oTegn = B.prototype._tegneoppsett;
    B.prototype._bygg = function () { const r = oBygg.apply(this, arguments); if (gyldig()) { try { lettStil(this); rolig(this); } catch (e) { console.warn('speil-barn-lett: stil', e); } } return r; };
    B.prototype._tegneoppsett = function () { const r = oTegn.apply(this, arguments); if (gyldig()) { try { lettTegning(this); } catch (e) { console.warn('speil-barn-lett: tegning', e); } } return r; };
  };
  if (customElements.get('jarvis-barn-card')) patch(); else customElements.whenDefined('jarvis-barn-card').then(patch);
})();

/* Speil-kort: rettelser i jarvis-speil-card (Claude 5.11.2026).
 * 1) Klokke/kalender/vær fryser etter at man har vært på en annen visning.
 *    Feil: disconnectedCallback stopper klokke-, kalender- og vær-tidtakerne, men lar id-ene stå igjen.
 *    connectedCallback starter bare klokka på nytt hvis id-en er tom, så etter Speil → Hus → Speil står klokka stille
 *    (sett 14:22 da klokka var 14:26), og kalender og vær oppdateres aldri mer før siden lastes på nytt.
 *    Rettelse: (nettleseren leser livssyklus-metodene bare ved define(), så de kan ikke byttes ut etterpå) i stedet sjekker
 *    hass-setteren, som HA kaller flere ganger i sekundet, om klokka har stått stille i mer enn 3 s mens kortet er på siden,
 *    og starter da klokke-, kalender- og vær-tidtakerne på nytt (med umiddelbar oppdatering).
 * 2) «Slå av speil» slo ikke av skjermen. Kortet prøver bare Fully sitt JavaScript-grensesnitt (window.fully.turnScreenOff, krever
 *    Fully PLUS + «JavaScript interface»), og faller ellers tilbake til en svart side mens Android-skjermen står på.
 *    Rettelse: når Fully-grensesnittet mangler, kalles HA-scriptet script.speil_skjerm_av. Det sender «input keyevent 223» (SLEEP) over
 *    ADB (androidtv-integrasjonen) så skjermen går av med en gang; er ADB-enheten utilgjengelig brukes Companion-appen: skjermtimeout
 *    10 s, skjermen går av ca. 10 s etter siste berøring, og timeouten settes tilbake til 5 min. Den svarte siden vises umiddelbart.
 *    Berøring på den svarte siden de første 14 s forlenger bare nedtellingen (scriptet kjører mode: restart); berøring etter det,
 *    eller at skjermen kommer på igjen, viser speilet og setter timeouten tilbake (script.speil_skjerm_avbryt).
 * 3) «Kamera»-knappen: en snarvei med til: 'kamera' åpner kamera-appen via HA-scriptet script.speil_kamera (ADB: stopper og starter
 *    appen på nytt i kamerabildet; tidtakeren husker appen, 10 s første gang) i stedet for å navigere til en visning. Tilbake til dashbordet: Tilbake-knappen i oppgavelinja.
 *    Fire knapper + tipsteksten passer ikke på én linje på 1080 px, så knappene får 24 px skrift og mindre fyll (stil lagt til i kortets shadow-DOM).
 * Tilbake til original: slett denne ressursen og last siden på nytt. */
(() => {
  const patch = () => {
    const C = customElements.get('jarvis-speil-card');
    if (!C || C.prototype.__fiks) return;
    const d = Object.getOwnPropertyDescriptor(C.prototype, 'hass');
    if (!d || !d.set) return;
    C.prototype.__fiks = true;
    // husk når klokka sist gikk
    const tikk = C.prototype._tikk;
    C.prototype._tikk = function () { this.__sistTikk = Date.now(); return tikk.apply(this, arguments); };
    const sett = d.set;
    Object.defineProperty(C.prototype, 'hass', {
      configurable: true, enumerable: d.enumerable, get: d.get,
      set(h) {
        try {
          // fire snarveier + tipsteksten passer ikke på en linje på 1080 px: litt mindre knapper (bare når Kamera-snarveien finnes)
          if (!this.__fiksCss && this.shadowRoot && this.c && (this.c.snarveier || []).some(x => x.til === 'kamera')) {
            this.__fiksCss = true;
            const st = document.createElement('style');
            st.textContent = '.fot{gap:12px}.fot .snar{padding:10px 16px;font-size:24px}';
            this.shadowRoot.appendChild(st);
          }
          if (this.r && this.c && !this.c.vakt && this.isConnected && this.__sistTikk && Date.now() - this.__sistTikk > 3000) {
            clearInterval(this._klokkeTimer); clearInterval(this._kalTimer); clearInterval(this._vaerTimer);
            this._klokkeTimer = setInterval(() => this._tikk(), 1000);
            this._kalTimer = setInterval(() => this._hentKalender(), 10 * 60 * 1000);
            this._vaerTimer = setInterval(() => this._hentVaer(), 30 * 60 * 1000);
            this._tikk();
            this._h = h; this._hentKalender(); this._hentVaer();
          }
        } catch (e) { console.warn('speil-kort-fiks:', e); }
        return sett.call(this, h);
      }
    });
    // «Slå av speil»: ekte skjerm av via HA-scriptet når Fully-grensesnittet ikke finnes
    const slaAv = C.prototype._slaAv;
    if (typeof slaAv === 'function') {
      const VINDU = 14000; // ms etter knappetrykket der en berøring bare forlenger nedtellingen
      const kall = (kort, navn) => {
        try { if (kort._h) kort._h.callService('script', navn).catch(e => console.warn('speil-kort-fiks:', navn, e)); }
        catch (e) { console.warn('speil-kort-fiks:', navn, e); }
      };
      const lytt = kort => {
        if (kort.__avLytt || !kort.r) return;
        kort.__avLytt = true;
        // Android slår av skjermen 10 s etter SISTE berøring. En berøring på den svarte siden i nedtellingen skal derfor ikke
        // vise speilet igjen: siden forblir svart og scriptet startes på nytt (mode: restart), så nedtellingen går videre.
        // En berøring etter nedtellingen betyr at skjermen ikke gikk av: vis speilet og sett skjermtimeouten tilbake med en gang.
        kort.r.addEventListener('click', ev => {
          if (!kort._sovnet) return;
          if (Date.now() < (kort.__avTil || 0)) {
            ev.stopImmediatePropagation(); ev.preventDefault();
            kort.__avTil = Date.now() + VINDU; kall(kort, 'speil_skjerm_av');
          } else if (kort.__avBedt) { kort.__avBedt = false; kall(kort, 'speil_skjerm_avbryt'); }
        }, true);
        // Skjermen kommer på igjen (f.eks. command_screen_on): vis speilet i stedet for den svarte siden
        const vis = () => {
          if (document.hidden) { kort.__avTil = 0; return; } // skjermen gikk av: nedtellingen er over
          if (!kort._sovnet || Date.now() < (kort.__avTil || 0)) return;
          if (kort.__avBedt) { kort.__avBedt = false; kall(kort, 'speil_skjerm_avbryt'); }
          kort._vekk();
        };
        document.addEventListener('visibilitychange', vis);
        window.addEventListener('focus', vis);
      };
      C.prototype._slaAv = function () {
        try {
          const harFully = window.fully && typeof window.fully.turnScreenOff === 'function';
          if (!harFully) { lytt(this); this.__avTil = Date.now() + VINDU; this.__avBedt = true; kall(this, 'speil_skjerm_av'); }
        } catch (e) { console.warn('speil-kort-fiks: skjerm av', e); }
        return slaAv.apply(this, arguments);
      };
    }
    // «Kamera»: snarveien med til: 'kamera' kaller HA-scriptet i stedet for å navigere
    const gaa = C.prototype._gaa;
    if (typeof gaa === 'function') {
      C.prototype._gaa = function (til) {
        if (til === 'kamera') {
          try { if (this._h) this._h.callService('script', 'speil_kamera').catch(e => console.warn('speil-kort-fiks: kamera', e)); }
          catch (e) { console.warn('speil-kort-fiks: kamera', e); }
          return;
        }
        return gaa.apply(this, arguments);
      };
    }
  };
  if (customElements.get('jarvis-speil-card')) patch(); else customElements.whenDefined('jarvis-speil-card').then(patch);
})();

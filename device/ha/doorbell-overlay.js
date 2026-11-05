/* Speil-ringeklokke: varsel pa speilet nar noen ringer pa (uten bilde).
 * Gjelder kun dashbordet /jarvis-speil. Utloser: state-endring pa event.gang_chime (selve
 * ringeklokka) eller input_button.speil_ringeklokke (automasjonen trykker den, og den kan
 * trykkes for test). Bruker kun hass.states, sa det fungerer for ikke-admin-brukere
 * (speilet kan ikke abonnere pa egne bus-events). Trykk pa skjermen for a lukke;
 * lukkes av seg selv etter 45 s.
 *
 * Bilde: denne dorklokka (Nest, WebRTC-only) kan ikke gi HA noe bilde av en ringing.
 * Nest-APIet stotter ikke CameraEventImage.GenerateImage uten RTSP, og kamera-entiteten
 * gir bare HAs graa plassholder. Derfor er dette et rent varsel.
 */
(() => {
  const NS = '__speilRingeklokke';
  if (window[NS]) return;
  window[NS] = true;

  const PATH = '/jarvis-speil';
  const WATCH = ['event.gang_chime', 'input_button.speil_ringeklokke'];
  const SHOW_MS = 45000;

  const onPage = () => location.pathname.indexOf(PATH) === 0;
  const getHass = () => {
    const ha = document.querySelector('home-assistant');
    return ha && ha.hass;
  };
  const two = (n) => (n < 10 ? '0' : '') + n;

  let root = null, timeEl = null, hideT = null;

  function build() {
    root = document.createElement('div');
    root.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:2147483647;display:none;' +
      'flex-direction:column;align-items:center;justify-content:center;background:rgba(0,0,0,.95);' +
      'color:#fff;font-family:Roboto,sans-serif;text-align:center;';
    const bell = document.createElement('div');
    bell.textContent = '🔔';
    bell.style.cssText = 'font-size:120px;line-height:1;margin:0 0 24px;';
    const title = document.createElement('div');
    title.textContent = 'Noen ringer på';
    title.style.cssText = 'font-size:48px;font-weight:600;';
    timeEl = document.createElement('div');
    timeEl.style.cssText = 'font-size:28px;opacity:.7;margin-top:12px;';
    const hint = document.createElement('div');
    hint.textContent = 'Trykk for å lukke';
    hint.style.cssText = 'font-size:16px;opacity:.45;margin-top:40px;';
    root.append(bell, title, timeEl, hint);
    root.addEventListener('click', close);
    document.body.appendChild(root);
  }

  function show() {
    if (!onPage()) return;
    if (!root) build();
    const d = new Date();
    timeEl.textContent = 'kl. ' + two(d.getHours()) + ':' + two(d.getMinutes());
    root.style.display = 'flex';
    clearTimeout(hideT);
    hideT = setTimeout(close, SHOW_MS);
  }

  function close() {
    clearTimeout(hideT);
    if (root) root.style.display = 'none';
  }

  // Ringetidspunktet ligger i selve state-verdien (ISO-tid) pa begge entitetene. Vis varselet
  // hvis siste ringing er helt fersk, uavhengig av nar siden ble lastet eller vaknet fra dvale.
  // (Sammenlikning med forrige state virker ikke: siden kan ha lastet mens skjermen sov, og
  // tar da utgangspunkt i staten etter ringingen.)
  const handled = {};
  const FRESH_MS = 40000;
  setInterval(() => {
    const hass = getHass();
    if (!hass) return;
    let fire = false;
    WATCH.forEach((id) => {
      const s = hass.states[id];
      if (!s || handled[id] === s.state) return;
      handled[id] = s.state;
      const t = Date.parse(s.state);
      if (isNaN(t)) return; // unavailable / unknown
      const age = Date.now() - t;
      if (age > -10000 && age < FRESH_MS) fire = true;
    });
    if (fire) show();
  }, 1000);
})();

// Cookiemelding (AVG/ePrivacy), zoals op bingr.online maar in de Tunr-stijl.
// Noodzakelijke opslag (taal, land, favorieten en instellingen van de webspeler, deze keuze) staat altijd aan.
// Met "Accepteren" mag de webspeler anonieme gebruiksstatistieken sturen (zie privacy/#cookies); met "Alleen noodzakelijk"
// niet. De keuze wordt 12 maanden onthouden (localStorage + cookie). Na een keuze staat er een cookieknop linksonder.
// <script src="…/consent.js" data-base="../" data-bottom="96"> : data-base = pad naar de root, data-bottom = afstand onderaan.
(function () {
  var KEY = 'tunr.consent', MAX = 365 * 24 * 3600;
  var me = document.currentScript;
  var base = (me && me.dataset.base) || '';
  var bottom = parseInt((me && me.dataset.bottom) || '16', 10) || 16;
  function read() {
    try { var v = localStorage.getItem(KEY); if (v) return JSON.parse(v); } catch (e) {}
    var m = document.cookie.match(/(?:^|; )tunr_consent=([^;]+)/);
    if (m) { try { return JSON.parse(decodeURIComponent(m[1])); } catch (e) {} }
    return null;
  }
  function save(choice) {
    var v = { choice: choice, at: new Date().toISOString(), v: 1 };
    try { localStorage.setItem(KEY, JSON.stringify(v)); } catch (e) {}
    // de instelling van de webspeler volgt de keuze (daar later ook los aan/uit te zetten)
    try { localStorage.setItem('tunr.shareStats', JSON.stringify(choice === 'all')); } catch (e) {}
    document.cookie = 'tunr_consent=' + encodeURIComponent(JSON.stringify(v)) + '; Max-Age=' + MAX + '; Path=/; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : '');
    try { document.dispatchEvent(new CustomEvent('tunr:consent', { detail: v })); } catch (e) {}
    return v;
  }
  function lang() {
    var l = null;
    try { l = new URLSearchParams(location.search).get('lang') || localStorage.getItem('tunr.lang'); } catch (e) {}
    return (l || navigator.language || 'nl').toLowerCase().indexOf('nl') === 0 ? 'nl' : 'en';
  }
  var TX = {
    nl: { t: 'Cookies en privacy', p: 'Tunr gebruikt alleen opslag die nodig is: om je taal, land, favorieten en deze keuze te onthouden. Met je toestemming stuurt de webspeler ook anonieme gebruiksstatistieken (geen naam, e-mail of IP-adres). Geen advertenties, geen tracking.', a: 'Accepteren', r: 'Alleen noodzakelijk', m: 'Meer in de privacyverklaring', b: 'Cookie-instellingen' },
    en: { t: 'Cookies and privacy', p: 'Tunr only uses storage that’s needed: to remember your language, country, favourites and this choice. With your consent the web player also sends anonymous usage statistics (no name, e-mail or IP address). No ads, no tracking.', a: 'Accept', r: 'Necessary only', m: 'More in the privacy policy', b: 'Cookie settings' }
  };
  function css() {
    if (document.getElementById('tunr-consent-css')) return;
    var st = document.createElement('style'); st.id = 'tunr-consent-css';
    st.textContent =
      '#tunr-consent{position:fixed;left:16px;right:16px;bottom:' + bottom + 'px;z-index:9999;max-width:560px;margin:0 auto;background:#141418f2;backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);border:1px solid #ffffff1f;border-radius:18px;padding:20px 22px 18px;color:#fff;font:15px/1.5 Inter,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;box-shadow:0 24px 70px #000b;animation:tunrcIn .35s ease both}' +
      '#tunr-consent::before{content:"";position:absolute;left:22px;right:22px;top:0;height:3px;border-radius:0 0 3px 3px;background:linear-gradient(90deg,#FF5A1F,#FFB020)}' +
      '#tunr-consent h4{font-size:17px;font-weight:800;margin:2px 0 6px;letter-spacing:-.01em}#tunr-consent p{margin:0;color:#b9b9c4;font-size:14px}#tunr-consent a{color:#FFB020}' +
      '#tunr-consent .b{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}#tunr-consent button{font:inherit;font-weight:800;border:0;border-radius:999px;padding:11px 20px;cursor:pointer}' +
      '#tunr-consent .y{background:linear-gradient(135deg,#FF5A1F,#FFB020);color:#140800}#tunr-consent .y:hover{filter:brightness(1.08)}#tunr-consent .n{background:#ffffff17;color:#fff}#tunr-consent .n:hover{background:#ffffff24}' +
      '#tunr-consent:focus{outline:none}#tunr-consent:focus-visible,#tunr-consent button:focus-visible,#tunr-cookie-btn:focus-visible{outline:3px solid #FFB020;outline-offset:3px}' +
      '#tunr-cookie-btn{position:fixed;left:16px;bottom:' + bottom + 'px;z-index:9998;width:44px;height:44px;border-radius:50%;border:1px solid #ffffff26;background:#141418e6;backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);color:#FFB020;display:grid;place-items:center;cursor:pointer;box-shadow:0 6px 20px #0008;transition:transform .2s,background .2s;padding:0}' +
      '#tunr-cookie-btn:hover{transform:scale(1.08);background:#1d1d22}#tunr-cookie-btn svg{width:24px;height:24px}' +
      '@media (max-width:560px){#tunr-cookie-btn{width:38px;height:38px;left:12px;opacity:.88}#tunr-cookie-btn svg{width:20px;height:20px}}' +
      '@keyframes tunrcIn{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}@media (prefers-reduced-motion:reduce){#tunr-consent{animation:none}}';
    document.head.appendChild(st);
  }
  function banner() {
    if (document.getElementById('tunr-consent')) return;
    css();
    var T = TX[lang()];
    var prev = document.activeElement;
    var d = document.createElement('div'); d.id = 'tunr-consent'; d.setAttribute('role', 'dialog');
    d.setAttribute('aria-labelledby', 'tunr-consent-t'); d.setAttribute('aria-describedby', 'tunr-consent-p'); d.tabIndex = -1;
    d.innerHTML = '<h4 id="tunr-consent-t">' + T.t + '</h4><p id="tunr-consent-p">' + T.p + ' <a href="' + base + 'privacy/#cookies">' + T.m + '</a></p>' +
      '<div class="b"><button type="button" class="y">' + T.a + '</button><button type="button" class="n">' + T.r + '</button></div>';
    function close(choice) {
      save(choice);
      var hadFocus = d.contains(document.activeElement);
      d.remove(); bubble();
      if (hadFocus) {
        var back = prev && prev !== document.body && document.contains(prev) ? prev : document.getElementById('tunr-cookie-btn');
        if (back && back.focus) try { back.focus({ preventScroll: true }); } catch (e) { back.focus(); }
      }
    }
    d.querySelector('.y').onclick = function () { close('all'); };
    d.querySelector('.n').onclick = function () { close('necessary'); };
    (document.body || document.documentElement).appendChild(d);
    try { d.focus({ preventScroll: true }); } catch (e) { d.focus(); }
  }
  function bubble() {
    if (document.getElementById('tunr-cookie-btn')) return;
    css();
    var b = document.createElement('button'); b.id = 'tunr-cookie-btn'; b.type = 'button';
    b.title = TX[lang()].b; b.setAttribute('aria-label', b.title);
    b.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.3A9 9 0 1 1 11.7 3a3 3 0 0 0 3.8 3.8 3 3 0 0 0 3.7 3.7 3 3 0 0 0 1.8 1.8z"/><circle cx="8.5" cy="10.5" r="1" fill="currentColor"/><circle cx="12" cy="15.5" r="1" fill="currentColor"/><circle cx="16" cy="14" r="1" fill="currentColor"/><circle cx="8" cy="15" r=".6" fill="currentColor"/></svg>';
    b.onclick = function () { window.TunrConsent.open(); };
    (document.body || document.documentElement).appendChild(b);
  }
  window.TunrConsent = {
    open: function () { var x = document.getElementById('tunr-consent'); if (x) x.remove(); var b = document.getElementById('tunr-cookie-btn'); if (b) b.remove(); banner(); },
    get: read
  };
  // links "Cookie-instellingen" in de footer
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest && e.target.closest('[data-consent-link]');
    if (a) { e.preventDefault(); window.TunrConsent.open(); }
  });
  // taalwissel op de site: knop en melding in de nieuwe taal
  document.addEventListener('tunr:lang', function () {
    var b = document.getElementById('tunr-cookie-btn'); if (b) { b.title = TX[lang()].b; b.setAttribute('aria-label', b.title); }
    if (document.getElementById('tunr-consent')) window.TunrConsent.open();
  });
  function start() { if (read()) bubble(); else banner(); }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

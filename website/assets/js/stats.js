// Tunr webspeler: anonieme gebruiksping (tunr-beheer/docs/CONTRACT.md, functie `ping`).
// Bij het laden (en bij terugkomen naar de tab) als de laatste geslaagde ping > 12 uur geleden is.
// Alleen als window.TUNR.stats.url is ingevuld en de instelling "Anonieme gebruiksstatistieken" (store 'shareStats',
// standaard aan) aan staat. Install-id: localStorage 'tunr.installId'. Geen persoonsgegevens; fouten worden genegeerd.
// De homepage laadt dit bestand niet (alleen de webspeler).
(function () {
  var T = window.T = window.T || {};
  var INTERVAL = 12 * 60 * 60 * 1000;
  var busy = false;

  function get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }

  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16);
    if (window.crypto && crypto.getRandomValues) crypto.getRandomValues(b);
    else for (var i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  var UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
  function installId() {
    var id = (get('tunr.installId') || '').toLowerCase();
    if (!UUID_RE.test(id)) { id = uuid().toLowerCase(); set('tunr.installId', id); }
    return id;
  }

  // "Chrome 129 (macOS)": browser + hoofdversie + besturingssysteem, zonder verdere details
  function model() {
    var ua = navigator.userAgent || '', d = navigator.userAgentData, name = '', ver = '', os = '';
    if (d && d.brands && d.brands.length) {
      var pick = null;
      d.brands.forEach(function (b) {
        if (/not.?a.?brand|chromium/i.test(b.brand)) return;
        if (!pick || /edge|opera|brave|vivaldi|samsung/i.test(b.brand)) pick = b;
      });
      if (!pick) pick = d.brands.filter(function (b) { return /chromium/i.test(b.brand); })[0];
      if (pick) { name = pick.brand.replace(/^Google\s+/i, '').replace(/^Microsoft\s+/i, ''); ver = pick.version; }
      os = d.platform || '';
    }
    if (!name) {
      var m;
      if ((m = ua.match(/Edg(?:e|A|iOS)?\/(\d+)/))) { name = 'Edge'; ver = m[1]; }
      else if ((m = ua.match(/(?:OPR|Opera)\/(\d+)/))) { name = 'Opera'; ver = m[1]; }
      else if ((m = ua.match(/SamsungBrowser\/(\d+)/))) { name = 'Samsung Internet'; ver = m[1]; }
      else if ((m = ua.match(/(?:Firefox|FxiOS)\/(\d+)/))) { name = 'Firefox'; ver = m[1]; }
      else if ((m = ua.match(/(?:Chrome|CriOS)\/(\d+)/))) { name = 'Chrome'; ver = m[1]; }
      else if ((m = ua.match(/Version\/(\d+)[\d.]*.*Safari/))) { name = 'Safari'; ver = m[1]; }
      else name = 'Browser';
    }
    if (!os) {
      if (/iPhone|iPad|iPod/.test(ua)) os = 'iOS';
      else if (/Macintosh|Mac OS X/.test(ua)) os = navigator.maxTouchPoints > 1 ? 'iPadOS' : 'macOS';
      else if (/Android/.test(ua)) os = 'Android';
      else if (/Windows/.test(ua)) os = 'Windows';
      else if (/CrOS/.test(ua)) os = 'ChromeOS';
      else if (/Linux/.test(ua)) os = 'Linux';
    }
    var s = name + (ver ? ' ' + String(ver).split('.')[0] : '') + (os ? ' (' + os + ')' : '');
    return s.slice(0, 60);
  }

  // build: hoogste buildnummer uit de changelog van de site (zelfde als de footer van de homepage), anders 0
  function build() {
    return fetch('../assets/changelog.json', { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) { return (d && d.builds || []).reduce(function (m, b) { return Math.max(m, +b.build || 0); }, 0); })
      .catch(function () { return 0; });
  }

  // pas na een keuze in de cookiemelding (consent.js): "Accepteren" zet shareStats aan, "Alleen noodzakelijk" uit
  function consented() { return !!(window.TunrConsent && window.TunrConsent.get()); }
  function enabled() { return consented() && !!(T.store && T.store.shareStats); }

  function pingIfDue() {
    var cfg = (window.TUNR && window.TUNR.stats) || {};
    var base = String(cfg.url || '').trim().replace(/\/+$/, '');
    if (!base || !enabled() || busy || !window.fetch) return;
    var last = +get('tunr.statsLastPing') || 0, now = Date.now();
    if (last > 0 && now >= last && now - last < INTERVAL) return;
    busy = true;
    build().then(function (b) {
      var c = (T.store.country || {}).cc || '';
      c = String(c).toUpperCase();
      var body = {
        id: installId(),
        platform: 'web',
        device: 'Browser',
        model: model(),
        os: '',
        version: (window.TUNR && window.TUNR.version) || '1.0.0',
        build: Math.min(Math.max(b | 0, 0), 99999),
        country: /^[A-Z]{2}$/.test(c) ? c : '',
        lang: T.store.lang === 'nl' ? 'nl' : 'en',
        carplay: false
      };
      return fetch(base + '/functions/v1/ping', {
        method: 'POST',
        keepalive: true,
        mode: 'cors',
        credentials: 'omit',
        headers: { 'apikey': String(cfg.key || ''), 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      }).then(function (r) { if (r.status === 200) set('tunr.statsLastPing', String(Date.now())); });
    }).catch(function () { /* genegeerd */ }).then(function () { busy = false; });
  }

  T.stats = { pingIfDue: pingIfDue };
  pingIfDue();
  document.addEventListener('tunr:consent', function () { pingIfDue(); });
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') pingIfDue(); });
})();

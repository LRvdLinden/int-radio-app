// Tunr voor Windows: anonieme gebruiksping (tunr-beheer/docs/CONTRACT.md, functie `ping`).
// Bij het laden (en bij terugkomen naar de tab) als de laatste geslaagde ping > 12 uur geleden is.
// Alleen als window.TUNR.stats.url is ingevuld en de instelling "Anonieme gebruiksstatistieken" (store 'shareStats',
// standaard aan) aan staat. Install-id: localStorage 'tunr.installId'. Geen persoonsgegevens; fouten worden genegeerd.
// platform 'windows', device 'PC', model 'Windows', os '10' of '11' (uit userAgentData, anders leeg).
(function () {
  var T = window.T = window.T || {};
  var INTERVAL = 12 * 60 * 60 * 1000;
  var busy = false;
  // Windows-versie: Chromium geeft platformVersion >= 13 voor Windows 11, 1..10 voor Windows 10
  var winVersion = '';
  try {
    if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
      navigator.userAgentData.getHighEntropyValues(['platformVersion']).then(function (v) {
        var major = parseInt(String(v.platformVersion || '').split('.')[0], 10);
        if (major >= 13) winVersion = '11'; else if (major > 0) winVersion = '10';
      }).catch(function () {});
    }
  } catch (e) {}

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


  // build: hoogste buildnummer uit de changelog van de site (zelfde als de footer van de homepage), anders 0
  function build() {
    // Windows-app: het eigen buildnummer (windows/tunr.properties → build-config.js)
    return Promise.resolve(+(window.TUNR && window.TUNR.build) || 0);
  }

  // Instelling "Anonieme gebruiksstatistieken" (store.shareStats), standaard aan zoals in de andere apps.
  function enabled() { return !!(T.store && T.store.shareStats); }

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
        platform: 'windows',
        device: 'PC',
        model: 'Windows',
        os: winVersion,
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

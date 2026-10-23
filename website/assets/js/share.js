// tunr.online/web/: pagina voor gedeelde links uit de apps (ShareLinks.swift / Share.kt). Geen webspeler (rechten):
// hier speelt niets af. Routes in de hash:
//   #/station/<stationuuid>             gegevens bij Radio Browser (naam, land, genres, logo)
//   #/podcast/<collectionId>            gegevens bij de iTunes Search API (naam, maker, cover)
//   #/episode/<collectionId>/<trackId>  idem, met de titel van de aflevering
// Daarna: kaartje met logo/cover + uitleg en de knop naar de apps. Geen statistieken, geen opslag (behalve de taal via i18n.js).
(function () {
  var card = document.getElementById('shcard');
  if (!card) return;
  var art = document.getElementById('sharticon'), kindEl = document.getElementById('shkind');
  var titleEl = document.getElementById('shtitle'), subEl = document.getElementById('shsub');
  var h1 = document.getElementById('shh'), lead = document.getElementById('shp');
  var RB = ['de1.api.radio-browser.info', 'de2.api.radio-browser.info', 'fi1.api.radio-browser.info'];
  var data = null;

  var TX = {
    nl: { station: 'Radiozender', podcast: 'Podcast', episode: 'Aflevering', title: 'Luister in de app',
          leadItem: 'Deze %s luister je met de gratis app van Tunr, op iPhone, iPad, Mac, Apple TV, Android, Android TV en Windows. Via de website kun je niet meer luisteren.',
          kinds: { station: 'zender', podcast: 'podcast', episode: 'aflevering' } },
    en: { station: 'Radio station', podcast: 'Podcast', episode: 'Episode', title: 'Listen in the app',
          leadItem: 'Listen to this %s in the free Tunr app, on iPhone, iPad, Mac, Apple TV, Android, Android TV and Windows. Listening on the website is no longer available.',
          kinds: { station: 'station', podcast: 'podcast', episode: 'episode' } }
  };
  function lang() { return (window.TunrI18n && TunrI18n.lang) === 'en' ? 'en' : 'nl'; }
  function T() { return TX[lang()]; }
  function clean(s) { return String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); }

  function getJSON(url, ms) {
    var ctl = window.AbortController ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctl) ctl.abort(); }, ms || 8000);
    return fetch(url, ctl ? { signal: ctl.signal } : {}).then(function (r) {
      clearTimeout(timer);
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    });
  }
  // iTunes geeft niet altijd CORS-headers: dan JSONP
  function jsonp(url) {
    return new Promise(function (ok, no) {
      var cb = 'tunrcb' + Math.random().toString(36).slice(2), s = document.createElement('script');
      var timer = setTimeout(function () { done(); no(new Error('timeout')); }, 9000);
      function done() { clearTimeout(timer); try { delete window[cb]; } catch (e) { window[cb] = undefined; } s.remove(); }
      window[cb] = function (d) { done(); ok(d); };
      s.onerror = function () { done(); no(new Error('jsonp')); };
      s.src = url + (url.indexOf('?') < 0 ? '?' : '&') + 'callback=' + cb;
      document.head.appendChild(s);
    });
  }
  function itunes(url) { return getJSON(url, 9000).catch(function () { return jsonp(url); }); }

  function station(id) {
    var i = 0;
    function next() {
      if (i >= RB.length) return Promise.reject(new Error('rb'));
      var host = RB[i++];
      return getJSON('https://' + host + '/json/stations/byuuid?uuids=' + encodeURIComponent(id), 7000).catch(next);
    }
    return next().then(function (list) {
      var s = (list || [])[0];
      if (!s) throw new Error('none');
      var tags = clean(s.tags).split(',').map(clean).filter(Boolean).slice(0, 3).join(', ');
      var place = [clean(s.state), clean(s.country)].filter(Boolean).join(', ');
      return { kind: 'station', title: clean(s.name), sub: [place, tags].filter(Boolean).join(' · '),
               img: clean(s.favicon), cc: clean(s.countrycode).toUpperCase(), id: s.stationuuid, contain: true };
    }).then(function (d) {
      // eerst het app-icoon uit de vaste tabel van tunr.online (zelfde bron als de apps)
      if (!d.cc) return d;
      return getJSON('../assets/data/icons/' + d.cc + '.json', 6000).then(function (t) {
        var u = t && t.u && t.u[d.id];
        if (u) { d.img = u; d.contain = false; }
        return d;
      }).catch(function () { return d; });
    });
  }
  function big(u) { return String(u || '').replace(/\/\d+x\d+(bb|cc)?\.(jpg|jpeg|png|webp)(\?.*)?$/i, '/600x600bb.$2'); }
  function podcast(id, trackId) {
    var url = 'https://itunes.apple.com/lookup?id=' + encodeURIComponent(id) + (trackId ? '&entity=podcastEpisode&limit=200' : '');
    return itunes(url).then(function (d) {
      var res = (d && d.results) || [], p = res[0];
      if (!p) throw new Error('none');
      var out = { kind: 'podcast', title: clean(p.collectionName || p.trackName), sub: clean(p.artistName),
                  img: big(p.artworkUrl600 || p.artworkUrl100), contain: false };
      if (trackId) {
        var e = res.filter(function (x) { return String(x.trackId) === String(trackId); })[0];
        if (e) { out.kind = 'episode'; out.sub = out.title; out.title = clean(e.trackName); out.img = big(e.artworkUrl600 || e.artworkUrl160) || out.img; }
      }
      return out;
    });
  }

  function mono(name) {
    var w = clean(name).replace(/[^\p{L}\p{N} ]/gu, '').split(' ').filter(Boolean);
    return ((w[0] || 'T')[0] + (w[1] ? w[1][0] : (w[0] || '').slice(1, 2))).toUpperCase();
  }
  function render() {
    if (!data) return;
    var t = T();
    kindEl.textContent = t[data.kind];
    titleEl.textContent = data.title;
    subEl.textContent = data.sub || '';
    art.textContent = ''; art.classList.remove('contain');
    var m = mono(data.title);
    if (data.img && /^https:\/\//.test(data.img)) {
      var im = new Image(); im.alt = ''; im.decoding = 'async'; im.referrerPolicy = 'no-referrer';
      im.onload = function () { if (data.contain) art.classList.add('contain'); };
      im.onerror = function () { art.textContent = m; im.remove(); };
      im.src = data.img; art.appendChild(im);
    } else art.textContent = m;
    card.hidden = false;
    h1.removeAttribute('data-i18n'); lead.removeAttribute('data-i18n');
    h1.textContent = t.title;
    lead.textContent = t.leadItem.replace('%s', t.kinds[data.kind]);
    document.title = data.title + ' · Tunr';
  }

  function load() {
    var parts = (location.hash || '').replace(/^#\/?/, '').split('/').map(decodeURIComponent);
    var p;
    if (parts[0] === 'station' && parts[1]) p = station(parts[1]);
    else if (parts[0] === 'podcast' && /^\d+$/.test(parts[1] || '')) p = podcast(parts[1]);
    else if (parts[0] === 'episode' && /^\d+$/.test(parts[1] || '')) p = podcast(parts[1], parts[2]);
    if (!p) return;
    p.then(function (d) { data = d; render(); }).catch(function () { /* algemene tekst blijft staan */ });
  }

  document.addEventListener('tunr:lang', render);
  window.addEventListener('hashchange', function () { data = null; card.hidden = true; load(); });
  load();
})();

// Tunr homepage: de muur van zendertegels in de hero. Eerst gegenereerde tegels (verloop + letters); daarna worden ze
// gevuld met de logo's van populaire zenders uit Radio Browser (eigen land voorop), zodra die echt geladen zijn
// en de live teller (aantal zenders en landen uit Radio Browser, met een vaste terugval).
(function () {
  var PAL = [['#FF5A1F', '#FFB020'], ['#7C3AED', '#DB2777'], ['#0EA5E9', '#22D3EE'], ['#10B981', '#84CC16'],
    ['#F43F5E', '#FB923C'], ['#6366F1', '#06B6D4'], ['#EAB308', '#F97316'], ['#14B8A6', '#3B82F6']];
  var NAMES = ['Radio Azul', 'Nova FM', 'Kosmos', 'Echo 101', 'Jazz Lounge', 'Sunwave', 'Metro Talk', 'Polar 88',
    'Atlas Radio', 'Bossa Café', 'Zen Air', 'Pulse', 'Harbor FM', 'Lumen', 'Orbit 99', 'Classic Gold', 'Vinyl Days',
    'Tango Sur', 'Savanna FM', 'Kyoto Beat', 'Nordlys', 'Fiesta', 'Deep House', 'Rock Arena', 'Nieuws 24', 'Sport Live',
    'Coastline', 'Aurora', 'Velvet', 'Tropica', 'Indie Wave', 'Opera Viva', 'Café Paris', 'Dune', 'Chill Out', 'Retro 80'];
  function hash(s) { var h = 0; for (var i = 0; i < s.length; i++) { h = (h * 31 + s.charCodeAt(i)) | 0; } return Math.abs(h); }
  function mono(n) { var w = n.replace(/[^\p{L}\p{N} ]/gu, '').trim().split(/\s+/); return (w.length > 1 && !/^\d/.test(w[1]) ? w[0][0] + w[1][0] : w[0].slice(0, 2)).toUpperCase(); }
  var EQ = '<span class="eq"><i></i><i></i><i></i><i></i></span>';

  var wall = document.getElementById('wall');
  if (wall) {
    var cols = 11, per = 7, k = 0, html = '';
    for (var c = 0; c < cols; c++) {
      html += '<div class="col">';
      for (var r = 0; r < per; r++) {
        var n = NAMES[(k * 7 + c) % NAMES.length]; k++;
        var p = PAL[hash(n) % PAL.length];
        var bg = 'background:linear-gradient(135deg,' + p[0] + ',' + p[1] + ')';
        if ((c + r) % 5 === 3) {
          html += '<div class="tile card"><span class="a" style="' + bg + '">' + mono(n) + '</span><span class="t"><span></span><span></span></span>' + ((c + r) % 2 ? EQ : '') + '</div>';
        } else {
          html += '<div class="tile" style="' + bg + '"><b>' + mono(n) + '</b>' + ((c * 3 + r) % 4 === 0 ? EQ : '') + '</div>';
        }
      }
      html += '</div>';
    }
    wall.innerHTML = html;
  }

  // ---- echte zenderlogo's in de muur ----
  // Populaire zenders (eigen land voorop, dan wereldwijd) met een https-logo. Een tegel krijgt het logo pas als de
  // afbeelding echt geladen is en groot genoeg is; anders blijft de gegenereerde tegel staan.
  function fillLogos(list) {
    if (!wall || !list || !list.length) return;
    var tiles = Array.prototype.slice.call(wall.querySelectorAll('.tile'));
    // niet elke tegel: ongeveer 2 op de 3, verspreid over de muur
    tiles = tiles.filter(function (_, i) { return i % 3 !== 1; });
    var queue = list.slice(), seen = {};
    function next(tile) {
      var s = queue.shift(); if (!s) return;
      if (seen[s.favicon]) return next(tile);
      seen[s.favicon] = 1;
      var img = new Image();
      img.referrerPolicy = 'no-referrer';
      img.decoding = 'async';
      img.alt = '';
      img.onload = function () {
        if (img.naturalWidth < 64 || img.naturalHeight < 64) return next(tile);   // te klein of een pixel-favicon
        if (tile.classList.contains('card')) {
          var a = tile.querySelector('.a'); a.textContent = ''; a.appendChild(img); a.classList.add('logo');
          var t = tile.querySelector('.t'); t.innerHTML = '<b></b><small></small>';
          t.querySelector('b').textContent = s.name; t.querySelector('small').textContent = s.place;
        } else {
          var b = tile.querySelector('b'); if (b) b.remove();
          tile.insertBefore(img, tile.firstChild); tile.classList.add('logo');
        }
        tile.title = s.name;
      };
      img.onerror = function () { next(tile); };
      img.src = s.favicon;
    }
    tiles.forEach(function (tile, i) { setTimeout(function () { next(tile); }, 120 + i * 35); });
  }
  function cc() {
    var m = /[-_]([A-Za-z]{2})$/.exec(navigator.language || ''); var c = m ? m[1].toUpperCase() : '';
    if (!c) { var l = (window.TunrI18n && TunrI18n.lang) || 'nl'; c = l === 'nl' ? 'NL' : ''; }
    return c;
  }
  function clean(arr) {
    return (arr || []).map(function (x) {
      var f = String(x.favicon || '').trim();
      return { name: String(x.name || '').trim(), favicon: f, place: [x.state, x.country].filter(Boolean).join(', ') };
    }).filter(function (x) { return x.name && /^https:\/\//i.test(x.favicon) && !/\.ico(\?|$)/i.test(x.favicon); });
  }
  function shuffle(a) { for (var i = a.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var t = a[i]; a[i] = a[j]; a[j] = t; } return a; }
  function loadLogos(base) {
    var key = 'tunr.wallLogos.' + (cc() || 'xx');
    try { var c0 = JSON.parse(localStorage.getItem(key) || 'null'); if (c0 && Date.now() - c0.t < 6 * 3600e3) { fillLogos(shuffle(c0.v)); return; } } catch (e) {}
    var q = '/json/stations/search?hidebroken=true&order=clickcount&reverse=true&limit=';
    var local = cc() ? getJSON(base + q + '80&countrycode=' + cc(), 7000).catch(function () { return []; }) : Promise.resolve([]);
    var world = getJSON(base + q + '160', 7000).catch(function () { return []; });
    Promise.all([local, world]).then(function (r) {
      var a = clean(r[0]).slice(0, 40), b = shuffle(clean(r[1])).slice(0, 80);
      var list = shuffle(a.concat(b));
      if (!list.length) return;
      try { localStorage.setItem(key, JSON.stringify({ t: Date.now(), v: list })); } catch (e) {}
      fillLogos(list);
    });
  }

  // ---- live teller ----
  var el = document.getElementById('counter');
  var FALLBACK = ['https://de1.api.radio-browser.info', 'https://de2.api.radio-browser.info', 'https://fi1.api.radio-browser.info'];
  var stats = null;
  function fmt(n) { var l = (window.TunrI18n && TunrI18n.lang) || 'nl'; return Number(n).toLocaleString(l === 'en' ? 'en-GB' : 'nl-NL'); }
  function render() {
    if (!el || !stats) return;
    var en = window.TunrI18n && TunrI18n.lang === 'en';
    // stations ↓ op een rond getal, zodat het niet "verspringt" per server
    var st = Math.floor(stats.stations / 1000) * 1000;
    el.innerHTML = '<span class="live" style="color:#fff;margin-right:8px;font-size:11px">Live</span><b>' + fmt(st) + '+</b> ' + (en ? 'stations' : 'zenders') +
      ' · <b>' + fmt(stats.countries) + '</b> ' + (en ? 'countries' : 'landen') +
      (stats.languages ? ' · <b>' + fmt(stats.languages) + '</b> ' + (en ? 'languages' : 'talen') : '');
  }
  document.addEventListener('tunr:lang', render);
  function getJSON(u, ms) {
    var ctl = 'AbortController' in window ? new AbortController() : null;
    var t = setTimeout(function () { ctl && ctl.abort(); }, ms || 6000);
    return fetch(u, ctl ? { signal: ctl.signal } : {}).then(function (r) { clearTimeout(t); if (!r.ok) throw new Error(r.status); return r.json(); });
  }
  var base = null;
  function tryServers(list) {
    if (!list.length) return Promise.reject(new Error('no server'));
    return getJSON(list[0] + '/json/stats').then(function (r) { base = list[0]; return r; }, function () { return tryServers(list.slice(1)); });
  }
  var cachedStats = null;
  try { cachedStats = JSON.parse(sessionStorage.getItem('tunr.stats') || 'null'); } catch (e) {}
  if (cachedStats && Date.now() - cachedStats.t < 3600e3) { stats = cachedStats.v; render(); }
  getJSON('https://all.api.radio-browser.info/json/servers', 5000)
    .then(function (s) {
      var names = (s || []).map(function (x) { return 'https://' + x.name; }).filter(function (v, i, a) { return a.indexOf(v) === i; });
      names.sort(function () { return Math.random() - 0.5; });
      return tryServers(names.concat(FALLBACK));
    }, function () { return tryServers(FALLBACK); })
    .then(function (s) {
      if (base && wall && !matchMedia('(prefers-reduced-data: reduce)').matches) loadLogos(base);
      if (!s || !s.stations) return;
      stats = { stations: s.stations, countries: s.countries, languages: s.languages };
      try { sessionStorage.setItem('tunr.stats', JSON.stringify({ t: Date.now(), v: stats })); } catch (e) {}
      render();
    })
    .catch(function () { /* terugval blijft staan */ });

  // ---- versie en build in de footer: de HTML heeft al een vaste waarde; hier de nieuwste uit de changelog
  var builds = document.querySelectorAll('[data-build]');
  if (builds.length && window.fetch) {
    fetch('assets/changelog.json', { cache: 'no-cache' }).then(function (r) { return r.ok ? r.json() : null; }).then(function (d) {
      var n = d && d.builds && d.builds.reduce(function (m, b) { return Math.max(m, +b.build || 0); }, 0);
      if (n) builds.forEach(function (el) { var cur = +((el.textContent.match(/build\s*(\d+)/) || [])[1] || 0); if (n > cur) el.textContent = ((window.TUNR && TUNR.version) || '1.0.0') + ' · build ' + n; });
    }).catch(function () {});
  }

  // ---- schermen: de sectie staat standaard verborgen en verschijnt pas als er echt een screenshot laadt;
  //      ontbrekende screenshots verdwijnen per stuk (ook bij taalwissel)
  var shots = document.getElementById('shots'), sec = document.getElementById('schermen');
  if (shots && sec) {
    var imgs = shots.querySelectorAll('img');
    imgs.forEach(function (img) {
      img.addEventListener('error', function () { var f = img.closest('figure'); if (f) f.classList.add('missing'); });
      img.addEventListener('load', function () { var f = img.closest('figure'); if (f) f.classList.remove('missing'); sec.hidden = false; });
    });
    if (imgs[0]) {
      var probe = new Image();
      probe.onload = function () { sec.hidden = false; };
      probe.src = imgs[0].getAttribute('src');
    }
  }
})();

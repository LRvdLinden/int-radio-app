// Tunr homepage: de muur van zendertegels in de hero (gegenereerd, geen echte logo's)
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
  function tryServers(list) {
    if (!list.length) return Promise.reject(new Error('no server'));
    return getJSON(list[0] + '/json/stats').catch(function () { return tryServers(list.slice(1)); });
  }
  try {
    var cached = JSON.parse(sessionStorage.getItem('tunr.stats') || 'null');
    if (cached && Date.now() - cached.t < 3600e3) { stats = cached.v; render(); return; }
  } catch (e) {}
  getJSON('https://all.api.radio-browser.info/json/servers', 5000)
    .then(function (s) {
      var names = (s || []).map(function (x) { return 'https://' + x.name; }).filter(function (v, i, a) { return a.indexOf(v) === i; });
      names.sort(function () { return Math.random() - 0.5; });
      return tryServers(names.concat(FALLBACK));
    }, function () { return tryServers(FALLBACK); })
    .then(function (s) {
      if (!s || !s.stations) return;
      stats = { stations: s.stations, countries: s.countries, languages: s.languages };
      try { sessionStorage.setItem('tunr.stats', JSON.stringify({ t: Date.now(), v: stats })); } catch (e) {}
      render();
    })
    .catch(function () { /* terugval blijft staan */ });

  // ---- schermen: verberg ontbrekende screenshots; geen enkele → rij weg ----
  var shots = document.getElementById('shots');
  if (shots) {
    var imgs = shots.querySelectorAll('img');
    var check = function () {
      var vis = Array.prototype.some.call(shots.querySelectorAll('figure'), function (f) { return !f.hidden; });
      var sec = document.getElementById('schermen'); if (sec) sec.hidden = !vis;
    };
    imgs.forEach(function (img) {
      img.addEventListener('error', function () { var f = img.closest('figure'); if (f) f.hidden = true; check(); });
      img.addEventListener('load', function () { var f = img.closest('figure'); if (f) f.hidden = false; check(); });
    });
    // lazy-plaatjes buiten beeld laden pas later: test er één direct, zodat een lege rij meteen verdwijnt
    var first = imgs[0];
    if (first) {
      var probe = new Image();
      probe.onerror = function () { var sec = document.getElementById('schermen'); if (sec) sec.hidden = true; };
      probe.onload = function () { var sec = document.getElementById('schermen'); if (sec) sec.hidden = false; };
      probe.src = first.getAttribute('src');
    }
  }
})();

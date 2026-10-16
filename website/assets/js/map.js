// Tunr webspeler: Kaart (SPEC §6). Leaflet 1.9.4 + Leaflet.markercluster 1.5.3 van cdnjs, CARTO dark_all-tegels,
// gloeiende CSS-stippen, clusters in huisstijl, landzenders met geo + knop "Wereld" (top 1500), kaartje onderaan met
// de dichtstbijzijnde zenders (vegen), en "Willekeurig". Laadt Leaflet niet → nette melding.
(function () {
  var T = window.T = window.T || {};
  var t = function (k, v) { return T.t(k, v); }, esc = T.esc, I = function (n, c) { return T.icon(n, c); };
  var CDN = 'https://cdnjs.cloudflare.com/ajax/libs/';
  var LEAFLET = { css: CDN + 'leaflet/1.9.4/leaflet.min.css', js: CDN + 'leaflet/1.9.4/leaflet.min.js' };
  var CLUSTER = { css: CDN + 'leaflet.markercluster/1.5.3/MarkerCluster.min.css', js: CDN + 'leaflet.markercluster/1.5.3/leaflet.markercluster.min.js' };
  var libP = null;
  var map = null, layer = null, markers = {}, data = [], mode = 'country', wrap = null, sel = null;

  function css(href) { if (document.querySelector('link[href="' + href + '"]')) return; var l = document.createElement('link'); l.rel = 'stylesheet'; l.href = href; l.crossOrigin = 'anonymous'; document.head.appendChild(l); }
  function js(src) {
    return new Promise(function (res, rej) {
      var s = document.createElement('script'); s.src = src; s.async = false; s.crossOrigin = 'anonymous';
      s.onload = res; s.onerror = function () { s.remove(); rej(new Error('load ' + src)); };
      document.head.appendChild(s);
    });
  }
  function loadLibs() {
    if (window.L && window.L.markerClusterGroup) return Promise.resolve();
    if (libP) return libP;
    css(LEAFLET.css); css(CLUSTER.css);
    var timeout = new Promise(function (_, rej) { setTimeout(function () { rej(new Error('timeout')); }, 15000); });
    libP = Promise.race([js(LEAFLET.js).then(function () { return js(CLUSTER.js); }), timeout]).then(function () {
      if (!window.L) throw new Error('no leaflet');
    }).catch(function (e) { libP = null; throw e; });
    return libP;
  }

  function fail() {
    if (!wrap) return;
    wrap.querySelector('.mapload') && wrap.querySelector('.mapload').remove();
    var mt = wrap.querySelector('.maptop'); if (mt) mt.hidden = true;
    var m = document.createElement('div'); m.className = 'mapmsg';
    m.innerHTML = '<div class="in"><img class="world" src="../assets/img/world-dots.svg" alt=""><b>' + esc(t('map.fail.t')) + '</b><p>' + esc(t('map.fail.p')) + '</p><button class="btn" type="button">' + esc(t('retry')) + '</button></div>';
    m.querySelector('button').onclick = function () { m.remove(); T.views.map(document.getElementById('view')); };
    wrap.appendChild(m);
  }

  function dotIcon(s) {
    var on = T.player.isCurrent(s.id);
    return L.divIcon({ className: 'mdot' + (on ? ' on' : '') + (sel && sel.id === s.id ? ' sel' : ''), html: '<i></i>', iconSize: [22, 22], iconAnchor: [11, 11] });
  }
  function build() {
    if (layer) { map.removeLayer(layer); }
    markers = {};
    layer = L.markerClusterGroup ? L.markerClusterGroup({
      showCoverageOnHover: false, spiderfyOnMaxZoom: true, maxClusterRadius: 48, chunkedLoading: true,
      iconCreateFunction: function (c) {
        var n = c.getChildCount(), sz = n < 20 ? 34 : n < 200 ? 42 : 52;
        return L.divIcon({ html: '<div>' + (n >= 1000 ? Math.round(n / 100) / 10 + 'k' : n) + '</div>', className: 'mclu ' + (n < 20 ? 's' : n < 200 ? 'm' : 'l'), iconSize: [sz, sz] });
      }
    }) : L.layerGroup();
    data.forEach(function (s) {
      var m = L.marker([s.lat, s.lon], { icon: dotIcon(s), title: s.name, keyboard: true, riseOnHover: true });
      m.on('click', function () { pick(s); });
      markers[s.id] = m;
      layer.addLayer(m);
    });
    map.addLayer(layer);
    var cnt = wrap.querySelector('.cnt'); if (cnt) cnt.textContent = data.length ? t('map.count', { n: T.num(data.length) }) : t('map.none');
  }
  function refreshIcons() {
    if (!map) return;
    var cur = T.player.current;
    Object.keys(markers).forEach(function (id) {
      var m = markers[id], el = m._icon;
      var s = data.find(function (x) { return x.id === id; });
      if (el) { el.classList.toggle('on', !!cur && cur.id === id); el.classList.toggle('sel', !!sel && sel.id === id); }
      else if (s) m.setIcon(dotIcon(s));
    });
  }
  function dist(a, b) { var dx = (a.lon - b.lon) * Math.cos((a.lat + b.lat) * Math.PI / 360), dy = a.lat - b.lat; return dx * dx + dy * dy; }

  // kaartje met de gekozen zender + de 7 dichtstbijzijnde (vegen)
  function pick(s, fly) {
    sel = s;
    var near = data.filter(function (x) { return x.id !== s.id; }).sort(function (a, b) { return dist(s, a) - dist(s, b); }).slice(0, 7);
    var arr = [s].concat(near);
    var k = T.ui.reg(arr);
    var old = wrap.querySelector('.mcard'); if (old) old.remove();
    var c = document.createElement('div'); c.className = 'mcard'; c.setAttribute('data-list', k); c.setAttribute('role', 'region'); c.setAttribute('aria-label', s.name);
    c.innerHTML = '<button class="x" type="button" aria-label="' + esc(t('close')) + '">' + I('x') + '</button><div class="strip">' + arr.map(function (x) {
      var active = T.player.isActive(x.id);
      return '<div class="it' + (T.player.isCurrent(x.id) ? ' is-playing' : '') + '" data-sid="' + esc(x.id) + '">' + T.art(x) + '<div class="tx"><b>' + esc(x.name) + '</b><small>' + esc(T.place(x)) + '</small><small>' + esc(T.tagsLine(x, 3)) + '</small>' +
        '<div class="acts"><button class="btn" type="button" data-act="play" data-detail-play="' + esc(x.id) + '">' + I(active ? 'pause' : 'play') + '<span>' + esc(active ? t('pause') : t('play')) + '</span></button><a class="btn ghost" href="#/station/' + encodeURIComponent(x.id) + '">' + esc(t('info')) + '</a></div></div></div>';
    }).join('') + '</div>' + (near.length ? '<div class="near"><span>' + esc(t('map.near')) + ' →</span><span class="pg">' + arr.map(function (x, i) { return '<i class="' + (i ? '' : 'on') + '"></i>'; }).join('') + '</span></div>' : '');
    wrap.appendChild(c);
    var strip = c.querySelector('.strip');
    c.querySelector('.x').onclick = function () { c.remove(); sel = null; refreshIcons(); };
    var lastI = 0;
    strip.addEventListener('scroll', function () {
      var i = Math.round(strip.scrollLeft / strip.clientWidth);
      if (i === lastI) return; lastI = i;
      c.querySelectorAll('.near .pg i').forEach(function (d, j) { d.classList.toggle('on', j === i); });
      var x = arr[i]; if (x) { sel = x; map.panTo([x.lat, x.lon], { animate: true }); refreshIcons(); }
    }, { passive: true });
    if (fly) map.flyTo([s.lat, s.lon], Math.max(map.getZoom(), 9), { duration: 1.6 });
    else map.panTo([s.lat, s.lon], { animate: true });
    refreshIcons();
    T.ui.syncPlaying();
  }

  function load(tk) {
    var c = T.store.country || { cc: 'NL' };
    var ld = wrap.querySelector('.mapload'); if (ld) ld.hidden = false;
    return T.api.geo(mode === 'world' ? '' : c.cc).then(function (arr) {
      if (tk !== T.views._token()) return;
      data = arr;
      if (ld) ld.hidden = true;
      build();
      if (arr.length) {
        var b = L.latLngBounds(arr.map(function (s) { return [s.lat, s.lon]; }));
        if (mode === 'world') map.flyTo([25, 10], 2, { duration: 1 });
        else map.flyToBounds(b.pad(0.08), { maxZoom: 8, duration: 1 });
      }
    }).catch(function () {
      if (ld) ld.hidden = true;
      var cnt = wrap.querySelector('.cnt'); if (cnt) cnt.textContent = t('err.load');
    });
  }

  function random() {
    var b = wrap.querySelector('.dicebtn'); b.classList.remove('rolling'); void b.offsetWidth; b.classList.add('rolling');
    var go = function (pool) {
      if (!pool.length) return;
      var s = pool[Math.floor(Math.random() * pool.length)];
      T.player.play(s, pool);
      pick(s, true);
    };
    // "wereldwijd": altijd uit de wereldlijst, ook als je in landmodus zit
    if (mode === 'world') go(data);
    else T.api.geo('').then(go).catch(function () { go(data); });
  }

  T.views.map = function (el) {
    var tk = T.views._token();
    var c = T.store.country || { cc: 'NL', name: '' };
    el.innerHTML = '';
    var old = document.getElementById('mapwrap');
    if (old) old.remove();
    map = null; layer = null; sel = null;
    wrap = document.createElement('div'); wrap.id = 'mapwrap';
    wrap.innerHTML = '<div id="map" role="application" aria-label="' + esc(t('tab.map')) + '"></div>' +
      '<div class="maptop"><div class="seg" role="group" aria-label="' + esc(t('tab.map')) + '"><button type="button" data-m="country" aria-pressed="' + (mode === 'country') + '">' + T.flag(c.cc) + ' ' + esc(T.countryName(c.cc, c.name)) + '</button><button type="button" data-m="world" aria-pressed="' + (mode === 'world') + '">' + I('globe', 'ic') + esc(t('map.world')) + '</button></div>' +
      '<span class="sp"></span><span class="cnt" aria-live="polite"></span><button class="dicebtn" type="button">' + I('dice') + '<span>' + esc(t('map.random')) + '</span></button></div>' +
      '<div class="mapload">' + I('spinner', 'ic spin') + esc(t('map.loading')) + '</div>';
    document.getElementById('app').appendChild(wrap);
    wrap.querySelector('.seg').addEventListener('click', function (e) {
      var b = e.target.closest('[data-m]'); if (!b || !map) return;
      mode = b.getAttribute('data-m');
      wrap.querySelectorAll('.seg button').forEach(function (x) { x.setAttribute('aria-pressed', x === b); });
      var mc = wrap.querySelector('.mcard'); if (mc) mc.remove(); sel = null;
      load(tk);
    });
    wrap.querySelector('.dicebtn').addEventListener('click', function () { if (map) random(); });
    loadLibs().then(function () {
      if (tk !== T.views._token()) return;
      map = L.map(wrap.querySelector('#map'), { zoomControl: true, worldCopyJump: true, minZoom: 2, maxZoom: 16, zoomSnap: 0.5, attributionControl: true, preferCanvas: false });
      map.zoomControl.setPosition('topright');
      L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        subdomains: 'abcd', maxZoom: 19, detectRetina: false,
        attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> © <a href="https://carto.com/attributions" target="_blank" rel="noopener">CARTO</a>'
      }).addTo(map);
      map.attributionControl.setPrefix(false);
      map.setView([30, 10], 2);
      setTimeout(function () { map && map.invalidateSize(); }, 50);
      load(tk);
    }).catch(function () { if (tk === T.views._token()) fail(); });
  };
  T.views.map.leave = function () {
    var w = document.getElementById('mapwrap'); if (w) w.remove();
    if (map) { try { map.remove(); } catch (e) {} }
    map = null; layer = null; wrap = null; sel = null;
  };
  T.views.map.sync = function () {
    refreshIcons();
    if (wrap && map) {
      wrap.querySelectorAll('.mcard .it').forEach(function (it) { it.classList.toggle('is-playing', T.player.isCurrent(it.getAttribute('data-sid'))); });
    }
  };
  T.views.map.resize = function () { if (map) map.invalidateSize(); };
})();

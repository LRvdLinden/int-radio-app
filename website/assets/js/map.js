// Tunr webspeler: Kaart (SPEC §6). Gloeiende stippen per zender, clusters in huisstijl, landzenders met geo +
// knop "Wereld" (top 1500), kaartje onderaan met de dichtstbijzijnde zenders (vegen), en "Willekeurig".
//
// Twee kaartmotoren met dezelfde bediening:
// - Apple Maps (MapKit JS), donker en gedempt, zodra er een token is. Het token maakt de workflow Website bij elke
//   upload aan (assets/js/mapkit-token.js, niet in git) uit het secret MAPKIT_P8, en werkt alleen op tunr.online.
// - Leaflet 1.9.4 + markercluster met CARTO dark_all-tegels als terugval (geen token, MapKit laadt niet of weigert).
// Laadt geen van beide → nette melding.
(function () {
  var T = window.T = window.T || {};
  var t = function (k, v) { return T.t(k, v); }, esc = T.esc, I = function (n, c) { return T.icon(n, c); };
  var CDN = 'https://cdnjs.cloudflare.com/ajax/libs/';
  var LEAFLET = { css: CDN + 'leaflet/1.9.4/leaflet.min.css', js: CDN + 'leaflet/1.9.4/leaflet.min.js' };
  var CLUSTER = { css: CDN + 'leaflet.markercluster/1.5.3/MarkerCluster.min.css', js: CDN + 'leaflet.markercluster/1.5.3/leaflet.markercluster.min.js' };
  var MAPKIT_JS = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js';
  var leafletP = null, mapkitP = null;
  var engine = null, data = [], mode = 'country', wrap = null, sel = null;

  function css(href) { if (document.querySelector('link[href="' + href + '"]')) return; var l = document.createElement('link'); l.rel = 'stylesheet'; l.href = href; l.crossOrigin = 'anonymous'; document.head.appendChild(l); }
  function js(src, cors) {
    return new Promise(function (res, rej) {
      var s = document.createElement('script'); s.src = src; s.async = false; if (cors !== false) s.crossOrigin = 'anonymous';
      s.onload = res; s.onerror = function () { s.remove(); rej(new Error('load ' + src)); };
      document.head.appendChild(s);
    });
  }
  function withTimeout(p, ms) {
    return Promise.race([p, new Promise(function (_, rej) { setTimeout(function () { rej(new Error('timeout')); }, ms); })]);
  }
  function countLabel(n) { return n >= 1000 ? Math.round(n / 100) / 10 + 'k' : String(n); }
  function sizeClass(n) { return n < 20 ? 's' : n < 200 ? 'm' : 'l'; }
  function dist(a, b) { var dx = (a.lon - b.lon) * Math.cos((a.lat + b.lat) * Math.PI / 360), dy = a.lat - b.lat; return dx * dx + dy * dy; }
  function bounds(arr) {
    var b = { n: -90, s: 90, e: -180, w: 180 };
    arr.forEach(function (x) { b.n = Math.max(b.n, x.lat); b.s = Math.min(b.s, x.lat); b.e = Math.max(b.e, x.lon); b.w = Math.min(b.w, x.lon); });
    return b;
  }

  // ---------- Apple Maps (MapKit JS) ----------
  function mapkitToken() {
    if (window.TUNR_MAPKIT_TOKEN) return Promise.resolve(window.TUNR_MAPKIT_TOKEN);
    // het tokenbestand bestaat alleen op de server (de workflow maakt het); lokaal → geen Apple Maps
    var day = Math.floor(Date.now() / 864e5);
    return js('../assets/js/mapkit-token.js?d=' + day, false).then(function () {
      if (!window.TUNR_MAPKIT_TOKEN) throw new Error('no token');
      return window.TUNR_MAPKIT_TOKEN;
    });
  }
  function loadMapkit() {
    if (mapkitP) return mapkitP;
    mapkitP = withTimeout(mapkitToken().then(function (token) {
      return js(MAPKIT_JS).then(function () {
        if (!window.mapkit) throw new Error('no mapkit');
        return new Promise(function (res, rej) {
          var done = false;
          var ok = function (e) { if (!done && e && e.status === 'Initialized') { done = true; res(); } };
          var bad = function (e) { if (!done) { done = true; rej(new Error('mapkit ' + (e && e.status))); } };
          mapkit.addEventListener('configuration-change', ok);
          mapkit.addEventListener('error', bad);
          mapkit.init({ authorizationCallback: function (cb) { cb(token); }, language: T.store.lang === 'nl' ? 'nl' : 'en' });
        });
      });
    }), 12000).catch(function (e) { mapkitP = null; throw e; });
    return mapkitP;
  }

  function appleEngine(el, onPick) {
    var map = new mapkit.Map(el, {
      colorScheme: mapkit.Map.ColorSchemes.Dark,
      mapType: mapkit.Map.MapTypes.MutedStandard,
      pointOfInterestFilter: mapkit.PointOfInterestFilter.excludingAllCategories,
      showsCompass: mapkit.FeatureVisibility.Hidden,
      showsMapTypeControl: false,
      showsZoomControl: true,
      showsUserLocationControl: false,
      isRotationEnabled: false,
      padding: new mapkit.Padding(70, 16, 16, 16)
    });
    var anns = [], els = {};
    function dotFactory(id) {
      return function () {
        var d = document.createElement('div'); d.className = 'mdot mk'; d.innerHTML = '<i></i>';
        els[id] = d; paint(id); return d;
      };
    }
    function paint(id) {
      var d = els[id]; if (!d) return;
      d.classList.toggle('on', T.player.isCurrent(id));
      d.classList.toggle('sel', !!sel && sel.id === id);
    }
    map.annotationForCluster = function (cluster) {
      var n = cluster.memberAnnotations.length, sz = n < 20 ? 34 : n < 200 ? 42 : 52;
      return new mapkit.Annotation(cluster.coordinate, function () {
        var d = document.createElement('div'); d.className = 'mclu mk ' + sizeClass(n);
        d.style.width = d.style.height = sz + 'px'; d.innerHTML = '<div>' + countLabel(n) + '</div>'; return d;
      }, { calloutEnabled: false, title: '' });
    };
    map.addEventListener('select', function (e) {
      var a = e.annotation; if (!a) return;
      if (a.memberAnnotations && a.memberAnnotations.length) {
        map.showItems(a.memberAnnotations, { animate: true, padding: new mapkit.Padding(90, 50, 160, 50) });
      } else if (a.data && a.data.station) {
        onPick(a.data.station);
      }
      setTimeout(function () { map.selectedAnnotation = null; }, 0);
    });
    function region(lat, lon, latD, lonD) {
      return new mapkit.CoordinateRegion(new mapkit.Coordinate(lat, lon), new mapkit.CoordinateSpan(latD, lonD));
    }
    map.region = region(30, 10, 120, 300);
    return {
      kind: 'apple',
      setData: function (arr) {
        if (anns.length) map.removeAnnotations(anns);
        els = {};
        anns = arr.map(function (s) {
          return new mapkit.Annotation(new mapkit.Coordinate(s.lat, s.lon), dotFactory(s.id), {
            title: s.name, clusteringIdentifier: 'tunr', calloutEnabled: false,
            collisionMode: mapkit.Annotation.CollisionMode.Circle, data: { station: s }
          });
        });
        if (anns.length) map.addAnnotations(anns);
      },
      fit: function (arr) {
        if (!arr.length) return;
        var b = bounds(arr), latD = Math.max(1.2, (b.n - b.s) * 1.25), lonD = Math.max(1.2, (b.e - b.w) * 1.25);
        map.setRegionAnimated(region((b.n + b.s) / 2, (b.e + b.w) / 2, Math.min(latD, 150), Math.min(lonD, 340)), true);
      },
      world: function () { map.setRegionAnimated(region(25, 10, 130, 320), true); },
      panTo: function (s) { map.setCenterAnimated(new mapkit.Coordinate(s.lat, s.lon), true); },
      flyTo: function (s) {
        var span = map.region.span, latD = Math.min(span.latitudeDelta, 2.2), lonD = Math.min(span.longitudeDelta, 2.2);
        map.setRegionAnimated(region(s.lat, s.lon, latD, lonD), true);
      },
      refresh: function () { Object.keys(els).forEach(paint); },
      resize: function () {},
      destroy: function () { try { map.destroy(); } catch (e) {} }
    };
  }

  // ---------- Leaflet (terugval) ----------
  function loadLeaflet() {
    if (window.L && window.L.markerClusterGroup) return Promise.resolve();
    if (leafletP) return leafletP;
    css(LEAFLET.css); css(CLUSTER.css);
    leafletP = withTimeout(js(LEAFLET.js).then(function () { return js(CLUSTER.js); }), 15000).then(function () {
      if (!window.L) throw new Error('no leaflet');
    }).catch(function (e) { leafletP = null; throw e; });
    return leafletP;
  }

  function leafletEngine(el, onPick) {
    var map = L.map(el, { zoomControl: true, worldCopyJump: true, minZoom: 2, maxZoom: 16, zoomSnap: 0.5, attributionControl: true, preferCanvas: false });
    map.zoomControl.setPosition('topright');
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      subdomains: 'abcd', maxZoom: 19, detectRetina: false,
      attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> © <a href="https://carto.com/attributions" target="_blank" rel="noopener">CARTO</a>'
    }).addTo(map);
    map.attributionControl.setPrefix(false);
    map.setView([30, 10], 2);
    setTimeout(function () { map.invalidateSize(); }, 50);
    var layer = null, markers = {};
    function icon(s) {
      var on = T.player.isCurrent(s.id);
      return L.divIcon({ className: 'mdot' + (on ? ' on' : '') + (sel && sel.id === s.id ? ' sel' : ''), html: '<i></i>', iconSize: [22, 22], iconAnchor: [11, 11] });
    }
    return {
      kind: 'leaflet',
      setData: function (arr) {
        if (layer) map.removeLayer(layer);
        markers = {};
        layer = L.markerClusterGroup ? L.markerClusterGroup({
          showCoverageOnHover: false, spiderfyOnMaxZoom: true, maxClusterRadius: 48, chunkedLoading: true,
          iconCreateFunction: function (c) {
            var n = c.getChildCount(), sz = n < 20 ? 34 : n < 200 ? 42 : 52;
            return L.divIcon({ html: '<div>' + countLabel(n) + '</div>', className: 'mclu ' + sizeClass(n), iconSize: [sz, sz] });
          }
        }) : L.layerGroup();
        arr.forEach(function (s) {
          var m = L.marker([s.lat, s.lon], { icon: icon(s), title: s.name, keyboard: true, riseOnHover: true });
          m.on('click', function () { onPick(s); });
          m._tunr = s; markers[s.id] = m; layer.addLayer(m);
        });
        map.addLayer(layer);
      },
      fit: function (arr) {
        if (!arr.length) return;
        var b = L.latLngBounds(arr.map(function (s) { return [s.lat, s.lon]; }));
        map.flyToBounds(b.pad(0.08), { maxZoom: 8, duration: 1 });
      },
      world: function () { map.flyTo([25, 10], 2, { duration: 1 }); },
      panTo: function (s) { map.panTo([s.lat, s.lon], { animate: true }); },
      flyTo: function (s) { map.flyTo([s.lat, s.lon], Math.max(map.getZoom(), 9), { duration: 1.6 }); },
      refresh: function () {
        var cur = T.player.current;
        Object.keys(markers).forEach(function (id) {
          var m = markers[id], el2 = m._icon;
          if (el2) { el2.classList.toggle('on', !!cur && cur.id === id); el2.classList.toggle('sel', !!sel && sel.id === id); }
          else m.setIcon(icon(m._tunr));
        });
      },
      resize: function () { map.invalidateSize(); },
      destroy: function () { try { map.remove(); } catch (e) {} }
    };
  }

  // Eerst Apple Maps; lukt dat niet (geen token, laadt niet, weigert), dan Leaflet
  function startEngine(el, onPick) {
    return loadMapkit().then(function () { return appleEngine(el, onPick); }).catch(function () {
      return loadLeaflet().then(function () { return leafletEngine(el, onPick); });
    });
  }

  // ---------- gedeelde bediening ----------
  function fail() {
    if (!wrap) return;
    wrap.querySelector('.mapload') && wrap.querySelector('.mapload').remove();
    var mt = wrap.querySelector('.maptop'); if (mt) mt.hidden = true;
    var m = document.createElement('div'); m.className = 'mapmsg';
    m.innerHTML = '<div class="in"><img class="world" src="../assets/img/world-dots.svg" alt=""><b>' + esc(t('map.fail.t')) + '</b><p>' + esc(t('map.fail.p')) + '</p><button class="btn" type="button">' + esc(t('retry')) + '</button></div>';
    m.querySelector('button').onclick = function () { m.remove(); T.views.map(document.getElementById('view')); };
    wrap.appendChild(m);
  }

  function setCount() {
    var cnt = wrap && wrap.querySelector('.cnt');
    if (cnt) cnt.textContent = data.length ? t('map.count', { n: T.num(data.length) }) : t('map.none');
  }

  // kaartje met de gekozen zender + de 7 dichtstbijzijnde (vegen)
  function pick(s, fly) {
    if (!engine || !wrap) return;
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
    c.querySelector('.x').onclick = function () { c.remove(); sel = null; engine && engine.refresh(); };
    var lastI = 0;
    strip.addEventListener('scroll', function () {
      var i = Math.round(strip.scrollLeft / strip.clientWidth);
      if (i === lastI) return; lastI = i;
      c.querySelectorAll('.near .pg i').forEach(function (d, j) { d.classList.toggle('on', j === i); });
      var x = arr[i]; if (x && engine) { sel = x; engine.panTo(x); engine.refresh(); }
    }, { passive: true });
    if (fly) engine.flyTo(s); else engine.panTo(s);
    engine.refresh();
    T.ui.syncPlaying();
  }

  function load(tk) {
    var c = T.store.country || { cc: 'NL' };
    var ld = wrap.querySelector('.mapload'); if (ld) ld.hidden = false;
    return T.api.geo(mode === 'world' ? '' : c.cc).then(function (arr) {
      if (tk !== T.views._token() || !engine) return;
      data = arr;
      if (ld) ld.hidden = true;
      engine.setData(arr);
      setCount();
      if (arr.length) { if (mode === 'world') engine.world(); else engine.fit(arr); }
    }).catch(function () {
      if (ld) ld.hidden = true;
      var cnt = wrap && wrap.querySelector('.cnt'); if (cnt) cnt.textContent = t('err.load');
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
    if (engine) { engine.destroy(); engine = null; }
    sel = null;
    wrap = document.createElement('div'); wrap.id = 'mapwrap';
    wrap.innerHTML = '<div id="map" role="application" aria-label="' + esc(t('tab.map')) + '"></div>' +
      '<div class="maptop"><div class="seg" role="group" aria-label="' + esc(t('tab.map')) + '"><button type="button" data-m="country" aria-pressed="' + (mode === 'country') + '">' + T.flag(c.cc) + ' ' + esc(T.countryName(c.cc, c.name)) + '</button><button type="button" data-m="world" aria-pressed="' + (mode === 'world') + '">' + I('globe', 'ic') + esc(t('map.world')) + '</button></div>' +
      '<span class="sp"></span><span class="cnt" aria-live="polite"></span><button class="dicebtn" type="button">' + I('dice') + '<span>' + esc(t('map.random')) + '</span></button></div>' +
      '<div class="mapload">' + I('spinner', 'ic spin') + esc(t('map.loading')) + '</div>';
    document.getElementById('app').appendChild(wrap);
    wrap.querySelector('.seg').addEventListener('click', function (e) {
      var b = e.target.closest('[data-m]'); if (!b || !engine) return;
      mode = b.getAttribute('data-m');
      wrap.querySelectorAll('.seg button').forEach(function (x) { x.setAttribute('aria-pressed', x === b); });
      var mc = wrap.querySelector('.mcard'); if (mc) mc.remove(); sel = null;
      load(tk);
    });
    wrap.querySelector('.dicebtn').addEventListener('click', function () { if (engine) random(); });
    var host = wrap.querySelector('#map');
    startEngine(host, function (s) { pick(s); }).then(function (eng) {
      if (tk !== T.views._token() || !wrap || !host.isConnected) { eng.destroy(); return; }
      engine = eng;
      wrap.classList.toggle('apple', eng.kind === 'apple');
      load(tk);
    }).catch(function () { if (tk === T.views._token()) fail(); });
  };
  T.views.map.leave = function () {
    var w = document.getElementById('mapwrap'); if (w) w.remove();
    if (engine) { engine.destroy(); }
    engine = null; wrap = null; sel = null;
  };
  T.views.map.sync = function () {
    if (!engine || !wrap) return;
    engine.refresh();
    wrap.querySelectorAll('.mcard .it').forEach(function (it) { it.classList.toggle('is-playing', T.player.isCurrent(it.getAttribute('data-sid'))); });
  };
  T.views.map.resize = function () { if (engine) engine.resize(); };
})();

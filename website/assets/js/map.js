// Tunr webspeler: Kaart (SPEC §6). Gloeiende stippen per zender, clusters in huisstijl, landzenders met geo +
// knop "Wereld" (top 1500), kaartje onderaan met de dichtstbijzijnde zenders (vegen), en "Willekeurig".
//
// Twee kaartmotoren met dezelfde bediening:
// - Apple Maps (MapKit JS), donker en gedempt, zodra er een token is. Het token maakt de workflow Website bij elke
//   upload aan (assets/js/mapkit-token.js, niet in git) uit het secret MAPKIT_P8, en werkt alleen op tunr.online.
// - Leaflet 1.9.4 + markercluster met CARTO dark_all-tegels als terugval (geen token, MapKit laadt niet of weigert).
// Laadt geen van beide → nette melding.
// Zoeken op de kaart (SPEC §9): zoekveld bovenaan met suggesties (landen uit Radio Browser + plaatsen via
// mapkit.Search met Apple Maps, anders Nominatim), recente kaartzoekopdrachten en toetsenbordbediening.
(function () {
  var T = window.T = window.T || {};
  var t = function (k, v) { return T.t(k, v); }, esc = T.esc, I = function (n, c) { return T.icon(n, c); };
  var CDN = 'https://cdnjs.cloudflare.com/ajax/libs/';
  var LEAFLET = { css: CDN + 'leaflet/1.9.4/leaflet.min.css', js: CDN + 'leaflet/1.9.4/leaflet.min.js' };
  var CLUSTER = { css: CDN + 'leaflet.markercluster/1.5.3/MarkerCluster.min.css', js: CDN + 'leaflet.markercluster/1.5.3/leaflet.markercluster.min.js' };
  var MAPKIT_JS = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js';
  var leafletP = null, mapkitP = null;
  var engine = null, data = [], mode = 'country', wrap = null, sel = null;
  var viewCC = null;   // tijdelijk getoond land na zoeken (null = eigen land uit Instellingen)
  var place = null;    // gekozen plaats { name, lat, lon, cc } in modus 'place'
  var seq = 0;         // volgnummer van de laatste laadactie: oudere antwoorden negeren

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
      flyToPoint: function (lat, lon, spanKm) {
        var latD = spanKm / 111, lonD = spanKm / (111 * Math.max(0.2, Math.cos(lat * Math.PI / 180)));
        map.setRegionAnimated(region(lat, lon, latD, lonD), true);
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
      flyToPoint: function (lat, lon, spanKm) { map.flyToBounds(L.latLng(lat, lon).toBounds(spanKm * 1000), { duration: 1.4, maxZoom: 14 }); },
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
    if (!cnt) return;
    if (mode === 'place' && place) cnt.textContent = !data.length ? t('map.s.empty', { p: place.name }) : data.length === 1 ? t('map.s.around1', { p: place.name }) : t('map.s.around', { n: T.num(data.length), p: place.name });
    else cnt.textContent = data.length ? t('map.count', { n: T.num(data.length) }) : t('map.none');
  }

  // kaartje met de gekozen zender + de 7 dichtstbijzijnde (vegen)
  function closeCard() { var mc = wrap && wrap.querySelector('.mcard'); if (mc) mc.remove(); sel = null; if (engine) engine.refresh(); }

  // still = kaart niet bewegen (bij zoeken op plaats regelt de zoekfunctie de kaart zelf)
  function pick(s, fly, still) {
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
    if (fly) engine.flyTo(s); else if (!still) engine.panTo(s);
    engine.refresh();
    T.ui.syncPlaying();
  }

  function load(tk) {
    var c = T.store.country || { cc: 'NL' }, my = ++seq;
    var ld = wrap.querySelector('.mapload'); if (ld) ld.hidden = false;
    return T.api.geo(mode === 'world' ? '' : (viewCC || c.cc)).then(function (arr) {
      if (tk !== T.views._token() || !engine || my !== seq) return;
      data = arr;
      if (ld) ld.hidden = true;
      engine.setData(arr);
      setCount();
      if (arr.length) { if (mode === 'world') engine.world(); else engine.fit(arr); }
    }).catch(function () {
      if (my !== seq) return;
      if (ld) ld.hidden = true;
      var cnt = wrap && wrap.querySelector('.cnt'); if (cnt) cnt.textContent = t('err.load');
    });
  }

  // landknop: eigen land, of tijdelijk het land dat je zocht
  function updateSeg() {
    if (!wrap) return;
    var own = T.store.country || { cc: 'NL', name: '' }, cc = viewCC || own.cc;
    var b = wrap.querySelector('.seg [data-m="country"]');
    if (b) { b.innerHTML = T.flag(cc) + ' ' + esc(T.countryName(cc, viewCC ? '' : own.name)); b.classList.toggle('tmp', !!viewCC); }
    wrap.querySelectorAll('.seg button').forEach(function (x) { x.setAttribute('aria-pressed', String(x.getAttribute('data-m') === mode)); });
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

  // ---------- zoeken op de kaart (SPEC §9) ----------
  var NOMINATIM = 'https://nominatim.openstreetmap.org/search';
  var mkSearch = null, mkLang = null, enDN = null;
  function fold(s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, ' ').trim(); }
  function enName(cc) { try { enDN = enDN || new Intl.DisplayNames(['en'], { type: 'region' }); return enDN.of(cc) || ''; } catch (e) { return ''; } }
  function km(a, b) { return Math.sqrt(dist(a, b)) * 111.2; }

  // landen: gelokaliseerde naam, Engelse naam (Intl + Radio Browser) en landcode; max 5
  function matchCountries(list, q) {
    var f = fold(q), up = q.trim().toUpperCase(), out = [];
    if (!f) return out;
    list.forEach(function (c) {
      var names = [fold(T.countryName(c.cc, c.name)), fold(enName(c.cc)), fold(c.name)], sc = -1;
      if (up.length === 2 && c.cc === up) sc = 0;
      else if (names.some(function (n) { return n === f; })) sc = 0;
      else if (names.some(function (n) { return n.indexOf(f) === 0; })) sc = 1;
      else if (names.some(function (n) { return (' ' + n).indexOf(' ' + f) >= 0; })) sc = 2;
      else if (f.length >= 3 && names.some(function (n) { return n.indexOf(f) >= 0; })) sc = 3;
      if (sc >= 0) out.push({ c: c, s: sc });
    });
    return out.sort(function (a, b) { return a.s - b.s || b.c.count - a.c.count; }).slice(0, 5)
      .map(function (x) { return { k: 'c', cc: x.c.cc, name: T.countryName(x.c.cc, x.c.name), count: x.c.count }; });
  }
  // landcode uit een tekst als "Utrecht, Nederland" (Apple-suggesties hebben geen landcode)
  function ccFromText(txt, list) {
    var parts = String(txt || '').split(','), last = fold(parts[parts.length - 1]);
    if (!last) return '';
    var hit = (list || []).filter(function (c) { return fold(T.countryName(c.cc, c.name)) === last || fold(enName(c.cc)) === last || fold(c.name) === last; })[0];
    return hit ? hit.cc : '';
  }

  function nominatim(q) {
    var ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctl) ctl.abort(); }, 8000);
    var url = NOMINATIM + '?q=' + encodeURIComponent(q) + '&format=jsonv2&limit=6&addressdetails=1&accept-language=' + (T.store.lang === 'nl' ? 'nl' : 'en');
    return fetch(url, ctl ? { signal: ctl.signal } : undefined).then(function (r) {
      clearTimeout(timer); if (!r.ok) throw new Error('HTTP ' + r.status); return r.json();
    }, function (e) { clearTimeout(timer); throw e; }).then(function (arr) {
      return (Array.isArray(arr) ? arr : []).filter(function (x) { return x && isFinite(+x.lat) && isFinite(+x.lon); }).map(function (x) {
        var a = x.address || {}, cc = String(a.country_code || '').toUpperCase();
        var name = String(x.name || String(x.display_name || '').split(',')[0]).trim();
        var sub = [a.state || a.region || a.province || a.county, a.country].filter(function (v, i, all) { return v && v !== name && all.indexOf(v) === i; }).join(', ');
        return { k: 'p', name: name, sub: sub, cc: cc, lat: +x.lat, lon: +x.lon, country: (x.addresstype || x.type) === 'country' };
      }).filter(function (p) { return p.name; });
    });
  }

  // Apple Maps: mapkit.Search (MapKit JS 5, Promise-vorm). Suggesties via autocomplete, kiezen via search.
  function mk() {
    var lang = T.store.lang === 'nl' ? 'nl' : 'en';
    if (!mkSearch || mkLang !== lang) {
      mkLang = lang;
      mkSearch = new mapkit.Search({ language: lang, getsUserLocation: false, includePointsOfInterest: false, includeQueries: false, includePhysicalFeatures: false, includeAddresses: true });
    }
    return mkSearch;
  }
  function mkCall(method, q) {
    return new Promise(function (res, rej) {
      var p = mk()[method](q, { language: mkLang, includePointsOfInterest: false, includeQueries: false, includePhysicalFeatures: false, includeAddresses: true });
      if (p && typeof p.then === 'function') p.then(res, rej); else rej(new Error('mapkit search: no promise'));
    });
  }
  function appleSuggest(q, list) {
    return mkCall('autocomplete', q).then(function (r) {
      return ((r && r.results) || []).filter(function (x) { return x && x.displayLines && x.displayLines[0]; }).map(function (x) {
        var sub = x.displayLines.slice(1).join(', '), c = x.coordinate;
        return { k: 'p', name: x.displayLines[0], sub: sub, cc: ccFromText(sub || x.displayLines[0], list), lat: c ? c.latitude : null, lon: c ? c.longitude : null, mk: x };
      });
    });
  }
  // gekozen Apple-suggestie oplossen naar coördinaat + landcode
  function resolvePlace(p) {
    if (!p.mk) return Promise.resolve(p);
    var base = { k: 'p', name: p.name, sub: p.sub, cc: p.cc, lat: p.lat, lon: p.lon };
    return mkCall('search', p.mk).then(function (r) {
      var pl = r && r.places && r.places[0];
      if (pl && pl.coordinate) { base.lat = pl.coordinate.latitude; base.lon = pl.coordinate.longitude; base.cc = String(pl.countryCode || base.cc || '').toUpperCase(); }
      if (base.lat == null) throw new Error('no coordinate');
      return base;
    }).catch(function () {
      if (base.lat != null) return base;
      return nominatim(p.name + (p.sub ? ', ' + p.sub : '')).then(function (a) { if (!a[0]) throw new Error('not found'); base.lat = a[0].lat; base.lon = a[0].lon; base.cc = base.cc || a[0].cc; return base; });
    });
  }
  function geocode(q, list) {
    if (engine && engine.kind === 'apple' && window.mapkit && mapkit.Search) return appleSuggest(q, list).catch(function () { return nominatim(q); });
    return nominatim(q);
  }

  function goCountry(cc) {
    var own = (T.store.country || {}).cc || 'NL';
    viewCC = cc === own ? null : cc; place = null; mode = 'country';
    closeCard(); updateSeg();
    load(T.views._token());
  }

  // plaats: erheen vliegen (±25 km), zenders binnen 50 km → 150 km → het land, dan het kaartje met de dichtstbijzijnde
  function goPlace(p) {
    if (!engine || !wrap) return;
    var tk = T.views._token(), my = ++seq, own = (T.store.country || {}).cc || 'NL';
    place = p; mode = 'place'; viewCC = null;
    closeCard(); updateSeg();
    engine.flyToPoint(p.lat, p.lon, 25);
    var ld = wrap.querySelector('.mapload'); if (ld) ld.hidden = false;
    var cnt = wrap.querySelector('.cnt'); if (cnt) cnt.textContent = '';
    T.api.near(p.lat, p.lon, 50).then(function (a) { return a.length ? a : T.api.near(p.lat, p.lon, 150); }).then(function (a) {
      if (a.length || !p.cc) return { a: a };
      return T.api.geo(p.cc).then(function (b) { return { a: b, country: true }; });
    }).then(function (r) {
      if (tk !== T.views._token() || !engine || my !== seq) return;
      if (ld) ld.hidden = true;
      data = r.a;
      engine.setData(data);
      if (r.country) { mode = 'country'; viewCC = p.cc === own ? null : p.cc; place = null; updateSeg(); }
      setCount();
      if (!data.length) return;
      var byDist = data.slice().sort(function (x, y) { return dist(p, x) - dist(p, y); });
      var nearest = byDist[0];
      if (km(p, nearest) > 12) engine.fit([p].concat(byDist.slice(0, 8)));
      pick(nearest, false, true);
    }).catch(function () {
      if (my !== seq) return;
      if (ld) ld.hidden = true;
      if (cnt) cnt.textContent = t('err.load');
    });
  }

  function searchHTML() {
    return '<div class="msearch" role="search">' + I('search', 'ic mi') +
      '<input id="msq" type="text" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="msug" aria-haspopup="listbox" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" enterkeyhint="search" placeholder="' + esc(t('map.s.ph')) + '" aria-label="' + esc(t('map.s.label')) + '">' +
      '<button class="clr" type="button" aria-label="' + esc(t('map.s.clear')) + '" hidden>' + I('x') + '</button>' +
      '<ul class="msug" id="msug" role="listbox" aria-label="' + esc(t('map.s.ph')) + '" hidden></ul></div>';
  }

  function searchUI() {
    var box = wrap.querySelector('.msearch'), input = box.querySelector('input'), list = box.querySelector('.msug'), clr = box.querySelector('.clr');
    var top = wrap.querySelector('.maptop');
    var items = [], active = -1, timer = null, qSeq = 0, lastQ = null, busy = false, wantEnter = false, countries = [];
    T.api.countries().then(function (c) { countries = c; }).catch(function () {});

    function setOpen(on) {
      list.hidden = !on; input.setAttribute('aria-expanded', on ? 'true' : 'false'); top.classList.toggle('sopen', on);
      if (!on) setActive(-1);
    }
    function setActive(i) {
      active = i;
      list.querySelectorAll('[role="option"]').forEach(function (o) { var on = +o.getAttribute('data-i') === i; o.classList.toggle('on', on); o.setAttribute('aria-selected', on ? 'true' : 'false'); });
      var el = i >= 0 ? document.getElementById('msug-' + i) : null;
      if (el) { input.setAttribute('aria-activedescendant', el.id); el.scrollIntoView({ block: 'nearest' }); } else input.removeAttribute('aria-activedescendant');
    }
    function row(it, i, recent) {
      var ic = it.k === 'c' || it.cc ? '<span class="fl">' + T.flag(it.cc) + '</span>' : '<span class="fl">' + I('pin') + '</span>';
      var name = it.k === 'c' ? T.countryName(it.cc, it.name) : it.name;
      var sub = it.k === 'c' ? (recent || !it.count ? t('map.s.country') : T.stationsN(it.count)) : (it.sub || '');
      return '<li role="option" id="msug-' + i + '" data-i="' + i + '" aria-selected="false" class="' + (it.k === 'c' ? 'c' : 'p') + '">' + ic +
        '<span class="tx"><b>' + esc(name) + '</b>' + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span>' +
        (recent ? I('clock', 'ic rc') : '') + '</li>';
    }
    // groups: [{ title, items, busy }]
    function render(groups, q, recent) {
      items = []; var h = '';
      groups.forEach(function (g, gi) {
        if (!g.items.length && !g.busy) return;
        h += '<li class="gh" role="presentation" id="msug-g' + gi + '">' + esc(g.title) + '</li>';
        g.items.forEach(function (it) { h += row(it, items.length, recent); items.push(it); });
        if (g.busy) h += '<li class="busy" role="presentation">' + I('spinner', 'ic spin') + esc(t('map.s.busy')) + '</li>';
      });
      if (!h && q) h = '<li class="none" role="presentation">' + esc(t('map.s.none', { q: q })) + '</li>';
      list.innerHTML = h;
      active = -1; input.removeAttribute('aria-activedescendant');
      setOpen(!!h && document.activeElement === input);
    }
    function showRecents() {
      lastQ = ''; busy = false; wantEnter = false; qSeq++;
      var r = T.store.mapSearches();
      if (!r.length) { items = []; list.innerHTML = ''; setOpen(false); return; }
      render([{ title: t('map.s.recent'), items: r }], '', true);
    }
    function run(q) {
      var my = ++qSeq; lastQ = q; busy = true;
      return T.api.countries().catch(function () { return countries; }).then(function (cl) {
        if (my !== qSeq) return;
        countries = cl || [];
        var cs = matchCountries(countries, q);
        render([{ title: t('map.s.countries'), items: cs }, { title: t('map.s.places'), items: [], busy: true }], q);
        if (wantEnter && cs.length) { wantEnter = false; choose(cs[0]); return; }
        return geocode(q, countries).catch(function () { return []; }).then(function (ps) {
          if (my !== qSeq) return;
          busy = false;
          var names = cs.map(function (c) { return fold(c.name); }), codes = cs.map(function (c) { return c.cc; });
          ps = ps.filter(function (p) { return !(p.country && codes.indexOf(p.cc) >= 0) && !(names.indexOf(fold(p.name)) >= 0 && !p.sub); }).slice(0, 6);
          render([{ title: t('map.s.countries'), items: cs }, { title: t('map.s.places'), items: ps }], q);
          if (wantEnter) { wantEnter = false; if (items[0]) choose(items[0]); }
        });
      });
    }
    function choose(it) {
      if (!it) return;
      clearTimeout(timer); qSeq++; busy = false; wantEnter = false;
      setOpen(false);
      input.value = it.k === 'c' ? T.countryName(it.cc, it.name) : it.name; lastQ = null;
      clr.hidden = false;
      input.blur();
      if (it.k === 'c') {
        T.store.addMapSearch({ k: 'c', cc: it.cc, name: it.name });
        goCountry(it.cc);
        return;
      }
      resolvePlace(it).then(function (p) {
        if (!wrap || !engine || p.lat == null) return;
        T.store.addMapSearch({ k: 'p', name: p.name, sub: p.sub || '', cc: p.cc || '', lat: p.lat, lon: p.lon });
        goPlace(p);
      }).catch(function () { var cnt = wrap && wrap.querySelector('.cnt'); if (cnt) cnt.textContent = t('err.load'); });
    }
    function clear() {
      clearTimeout(timer); qSeq++; busy = false; wantEnter = false; lastQ = null;
      input.value = ''; clr.hidden = true; items = []; list.innerHTML = ''; setOpen(false);
    }

    input.addEventListener('input', function () {
      var q = input.value.trim();
      clr.hidden = !input.value;
      clearTimeout(timer); wantEnter = false;
      if (!q) { showRecents(); return; }
      if (q.length < 2) { qSeq++; busy = false; lastQ = null; items = []; list.innerHTML = ''; setOpen(false); return; }
      timer = setTimeout(function () { run(q); }, 300);
    });
    input.addEventListener('focus', function () {
      var q = input.value.trim();
      if (!q) showRecents();
      else if (q === lastQ && list.innerHTML) setOpen(true);
    });
    input.addEventListener('blur', function () { setTimeout(function () { if (document.activeElement !== input) setOpen(false); }, 0); });
    input.addEventListener('keydown', function (e) {
      var n = items.length;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        if (!n) return;
        e.preventDefault();
        if (list.hidden) { setOpen(true); setActive(e.key === 'ArrowDown' ? 0 : n - 1); return; }
        setActive(e.key === 'ArrowDown' ? (active + 1) % n : (active <= 0 ? n - 1 : active - 1));
      } else if (e.key === 'Enter') {
        e.preventDefault();
        var q = input.value.trim();
        if (!list.hidden && active >= 0 && items[active]) { choose(items[active]); return; }
        if (!q) { if (items[0] && !list.hidden) choose(items[0]); return; }
        if (q.length < 2) return;
        if (q === lastQ && !busy) { if (items[0]) choose(items[0]); return; }
        if (q === lastQ && busy) { if (items[0]) choose(items[0]); else wantEnter = true; return; }
        clearTimeout(timer); wantEnter = true; run(q);
      } else if (e.key === 'Escape') {
        e.stopPropagation();
        if (input.value || !list.hidden) clear(); else input.blur();
      } else if (e.key === 'Home' || e.key === 'End') {
        if (!list.hidden && active >= 0 && n) { e.preventDefault(); setActive(e.key === 'Home' ? 0 : n - 1); }
      }
    });
    // klikken in de lijst mag de focus niet wegnemen (anders sluit blur de lijst vóór de klik)
    list.addEventListener('mousedown', function (e) { e.preventDefault(); });
    list.addEventListener('click', function (e) {
      var o = e.target.closest('[role="option"]'); if (!o) return;
      choose(items[+o.getAttribute('data-i')]);
    });
    list.addEventListener('mousemove', function (e) {
      var o = e.target.closest('[role="option"]'); if (o && +o.getAttribute('data-i') !== active) setActive(+o.getAttribute('data-i'));
    });
    clr.addEventListener('click', function () { clear(); input.focus(); });
  }

  T.views.map = function (el) {
    var tk = T.views._token();
    var c = T.store.country || { cc: 'NL', name: '' };
    el.innerHTML = '';
    var old = document.getElementById('mapwrap');
    if (old) old.remove();
    if (engine) { engine.destroy(); engine = null; }
    sel = null;
    if (mode === 'place') { mode = 'country'; place = null; } // de buurtzenders zijn weg na opnieuw opbouwen
    wrap = document.createElement('div'); wrap.id = 'mapwrap';
    wrap.innerHTML = '<div id="map" role="application" aria-label="' + esc(t('tab.map')) + '"></div>' +
      '<div class="maptop">' + searchHTML() + '<div class="seg" role="group" aria-label="' + esc(t('tab.map')) + '"><button type="button" data-m="country" aria-pressed="' + (mode === 'country') + '">' + T.flag(c.cc) + ' ' + esc(T.countryName(c.cc, c.name)) + '</button><button type="button" data-m="world" aria-pressed="' + (mode === 'world') + '">' + I('globe', 'ic') + esc(t('map.world')) + '</button></div>' +
      '<span class="sp"></span><span class="cnt" aria-live="polite"></span><button class="dicebtn" type="button">' + I('dice') + '<span>' + esc(t('map.random')) + '</span></button></div>' +
      '<div class="mapload">' + I('spinner', 'ic spin') + esc(t('map.loading')) + '</div>';
    document.getElementById('app').appendChild(wrap);
    updateSeg();
    wrap.querySelector('.seg').addEventListener('click', function (e) {
      var b = e.target.closest('[data-m]'); if (!b || !engine) return;
      mode = b.getAttribute('data-m');
      viewCC = null; place = null; // landknop = terug naar je eigen land
      updateSeg(); closeCard();
      load(tk);
    });
    searchUI();
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
    engine = null; wrap = null; sel = null; viewCC = null; place = null;
    if (mode === 'place') mode = 'country';
  };
  T.views.map.sync = function () {
    if (!engine || !wrap) return;
    engine.refresh();
    wrap.querySelectorAll('.mcard .it').forEach(function (it) { it.classList.toggle('is-playing', T.player.isCurrent(it.getAttribute('data-sid'))); });
  };
  T.views.map.resize = function () { if (engine) engine.resize(); };
})();

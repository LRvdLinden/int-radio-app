// Tunr webspeler: Radio Browser API (docs/SPEC.md §2 en §6).
// - server kiezen uit all.api.radio-browser.info/json/servers (willekeurig, bewaard voor de sessie; bij een fout de volgende),
//   terugval de1/de2/fi1;
// - browsers mogen geen User-Agent zetten: die slaan we hier over;
// - cache in geheugen + localStorage met TTL (landen 7 dagen, zenderlijsten 30 minuten).
(function () {
  var T = window.T = window.T || {};
  var FALLBACK = ['de1.api.radio-browser.info', 'de2.api.radio-browser.info', 'fi1.api.radio-browser.info'];
  var DAY = 864e5, MIN = 6e4;
  var mem = {};
  var servers = null;      // lijst met hosts, de eerste is de huidige
  var serversP = null;

  // ---------- cache ----------
  var CK = 'tunr.c:';
  function cacheGet(key) {
    var m = mem[key];
    if (m && m.e > Date.now()) return m.v;
    try {
      var raw = localStorage.getItem(CK + key);
      if (raw) {
        var o = JSON.parse(raw);
        if (o.e > Date.now()) { mem[key] = o; return o.v; }
        localStorage.removeItem(CK + key);
      }
    } catch (e) {}
    return null;
  }
  function cacheSet(key, v, ttl) {
    var o = { e: Date.now() + ttl, v: v };
    mem[key] = o;
    var s = JSON.stringify(o);
    if (s.length > 400000) return; // grote lijsten (kaart wereldwijd) alleen in het geheugen
    try { localStorage.setItem(CK + key, s); }
    catch (e) { prune(); try { localStorage.setItem(CK + key, s); } catch (e2) {} }
  }
  function prune() {
    try {
      var now = Date.now(), keys = [];
      for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); if (k && k.indexOf(CK) === 0) keys.push(k); }
      keys.forEach(function (k) {
        try { var o = JSON.parse(localStorage.getItem(k)); if (!o || o.e < now + 10 * MIN) localStorage.removeItem(k); } catch (e) { localStorage.removeItem(k); }
      });
    } catch (e) {}
  }
  prune();

  // ---------- netwerk ----------
  function fetchJSON(url, ms) {
    var ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctl) ctl.abort(); }, ms || 12000);
    return fetch(url, ctl ? { signal: ctl.signal } : undefined).then(function (r) {
      clearTimeout(timer);
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    }, function (e) { clearTimeout(timer); throw e; });
  }

  function shuffle(a) { for (var i = a.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var t = a[i]; a[i] = a[j]; a[j] = t; } return a; }

  function getServers() {
    if (servers) return Promise.resolve(servers);
    if (serversP) return serversP;
    var saved = null; try { saved = sessionStorage.getItem('tunr.server'); } catch (e) {}
    serversP = fetchJSON('https://all.api.radio-browser.info/json/servers', 6000).then(function (list) {
      var names = [];
      (list || []).forEach(function (s) { if (s && s.name && names.indexOf(s.name) < 0) names.push(s.name); });
      if (!names.length) throw new Error('empty');
      shuffle(names);
      FALLBACK.forEach(function (f) { if (names.indexOf(f) < 0) names.push(f); });
      return names;
    }).catch(function () { return shuffle(FALLBACK.slice()); }).then(function (names) {
      if (saved && names.indexOf(saved) > 0) { names.splice(names.indexOf(saved), 1); names.unshift(saved); }
      servers = names;
      try { sessionStorage.setItem('tunr.server', names[0]); } catch (e) {}
      return names;
    });
    return serversP;
  }

  // GET op de huidige server; bij een fout de volgende (en die wordt de nieuwe "huidige")
  function get(path) {
    return getServers().then(function (list) {
      var i = 0;
      function attempt() {
        var host = list[i];
        return fetchJSON('https://' + host + path).then(function (data) {
          if (i > 0) { list.splice(i, 1); list.unshift(host); try { sessionStorage.setItem('tunr.server', host); } catch (e) {} }
          return data;
        }, function (err) {
          i++;
          if (i >= list.length) throw err;
          return attempt();
        });
      }
      return attempt();
    });
  }

  function cached(key, ttl, path, map) {
    var hit = cacheGet(key);
    if (hit) return Promise.resolve(hit);
    return get(path).then(function (data) {
      var v = map ? map(data) : data;
      cacheSet(key, v, ttl);
      return v;
    });
  }

  // ---------- zenders ----------
  var known = {}; // uuid → zender (alles wat we ooit zagen; voor detail zonder extra verzoek)
  function norm(s) {
    if (!s || !s.stationuuid) return null;
    var name = String(s.name || '').replace(/\s+/g, ' ').trim();
    if (!name) return null;
    var st = {
      id: s.stationuuid,
      name: name,
      url: String(s.url || '').trim(),
      stream: String(s.url_resolved || s.url || '').trim(),
      homepage: String(s.homepage || '').trim(),
      favicon: String(s.favicon || '').trim(),
      tags: String(s.tags || '').split(',').map(function (t) { return t.trim().toLowerCase(); }).filter(function (t, i, a) { return t && t.length < 32 && a.indexOf(t) === i; }).slice(0, 8),
      country: s.country || '',
      cc: String(s.countrycode || '').toUpperCase(),
      state: String(s.state || '').trim(),
      language: String(s.language || '').split(',')[0].trim(),
      codec: s.codec || '',
      bitrate: +s.bitrate || 0,
      hls: s.hls == 1 || s.hls === true,
      votes: +s.votes || 0,
      clicks: +s.clickcount || 0,
      trend: +s.clicktrend || 0,
      lat: s.geo_lat != null && s.geo_lat !== '' ? +s.geo_lat : null,
      lon: s.geo_long != null && s.geo_long !== '' ? +s.geo_long : null
    };
    if (!st.stream) return null;
    return st;
  }
  function list(data) {
    var seen = {}, out = [];
    (data || []).forEach(function (raw) {
      var s = norm(raw); if (!s) return;
      var k = s.name.toLowerCase() + '|' + s.stream;
      if (seen[k]) return; seen[k] = 1;
      out.push(s);
    });
    return out;
  }
  function remember(arr) { (arr || []).forEach(function (s) { if (s && s.id && !known[s.id]) known[s.id] = s; }); return arr; }
  function stations(key, params) {
    var qs = 'hidebroken=true&' + params;
    return cached('s:' + key, 30 * MIN, '/json/stations/search?' + qs, list).then(remember);
  }
  var enc = encodeURIComponent;

  T.api = {
    server: function () { return servers ? servers[0] : null; },
    known: known,
    remember: remember,
    countries: function () {
      return cached('countries', 7 * DAY, '/json/countries?hidebroken=true&order=name', function (d) {
        return (d || []).filter(function (c) { return c && c.iso_3166_1 && c.stationcount >= 1; })
          .map(function (c) { return { name: c.name, cc: String(c.iso_3166_1).toUpperCase(), count: c.stationcount }; })
          .reduce(function (acc, c) { // dubbele codes samenvoegen
            var e = acc.find(function (x) { return x.cc === c.cc; });
            if (e) { e.count += c.count; if (c.count > e.count / 2) e.name = e.name || c.name; } else acc.push(c);
            return acc;
          }, []);
      });
    },
    popular: function (cc, limit) { return stations('pop:' + cc + ':' + (limit || 60), 'countrycode=' + enc(cc) + '&order=clickcount&reverse=true&limit=' + (limit || 60) + '&offset=0'); },
    trending: function (cc) { return stations('trend:' + cc, 'countrycode=' + enc(cc) + '&order=clicktrend&reverse=true&limit=60&offset=0'); },
    genre: function (cc, tag) { return stations('tag:' + cc + ':' + tag, (cc ? 'countrycode=' + enc(cc) + '&' : '') + 'tag=' + enc(tag) + '&tagExact=true&order=clickcount&reverse=true&limit=60&offset=0'); },
    search: function (q, cc) {
      return get('/json/stations/search?name=' + enc(q) + (cc ? '&countrycode=' + enc(cc) : '') + '&hidebroken=true&order=clickcount&reverse=true&limit=60').then(list).then(remember);
    },
    byUuids: function (ids) {
      if (!ids.length) return Promise.resolve([]);
      return get('/json/stations/byuuid?uuids=' + ids.map(enc).join(',')).then(list).then(function (arr) { arr.forEach(function (s) { known[s.id] = s; }); return arr; });
    },
    station: function (id) {
      if (known[id]) return Promise.resolve(known[id]);
      return T.api.byUuids([id]).then(function (a) { return a[0] || null; });
    },
    states: function (countryName) {
      return cached('states:' + countryName, DAY, '/json/states/' + enc(countryName) + '/?hidebroken=true&order=stationcount&reverse=true', function (d) {
        var seen = {};
        return (d || []).filter(function (r) {
          var n = String(r.name || '').trim(); if (!n || r.stationcount < 1 || seen[n.toLowerCase()]) return false;
          seen[n.toLowerCase()] = 1; return true;
        }).map(function (r) { return { name: String(r.name).trim(), count: r.stationcount }; });
      });
    },
    region: function (cc, state) { return stations('state:' + cc + ':' + state, 'countrycode=' + enc(cc) + '&state=' + enc(state) + '&stateExact=true&order=clickcount&reverse=true&limit=100'); },
    languages: function () {
      return cached('languages', DAY, '/json/languages?hidebroken=true&order=stationcount&reverse=true&limit=60', function (d) {
        return (d || []).filter(function (l) { return l && l.name && l.stationcount > 0; }).map(function (l) { return { name: l.name, code: l.iso_639 || '', count: l.stationcount }; });
      });
    },
    language: function (name) { return stations('lang:' + name, 'language=' + enc(name) + '&languageExact=true&order=clickcount&reverse=true&limit=100'); },
    top100: function () { return stations('top100', 'order=clickcount&reverse=true&limit=100'); },
    geo: function (cc) {
      return stations(cc ? 'geo:' + cc : 'geo:world', (cc ? 'countrycode=' + enc(cc) + '&limit=500' : 'limit=1500') + '&has_geo_info=true&order=clickcount&reverse=true').then(function (a) {
        return a.filter(function (s) { return s.lat != null && s.lon != null && isFinite(s.lat) && isFinite(s.lon) && Math.abs(s.lat) <= 85 && Math.abs(s.lon) <= 180 && !(s.lat === 0 && s.lon === 0); });
      });
    },
    click: function (id) { get('/json/url/' + enc(id)).catch(function () {}); }
  };

  // ================= Podcasts (SPEC §8) =================
  // Bronnen zonder sleutel: Apple-toplijst (rss.applemarketingtools.com), iTunes Search/Lookup en de oude
  // iTunes-RSS per genre. iTunes stuurt niet altijd CORS-headers mee: lukt fetch niet, dan JSONP (&callback=);
  // dat onthouden we voor de sessie zodat we niet elke keer eerst een geblokkeerde fetch doen.
  var HOUR = 36e5;
  var JP = 'tunr.itunesJsonp', RSSG = 'tunr.rssGenreFail';
  function flag(k) { try { return sessionStorage.getItem(k) === '1'; } catch (e) { return false; } }
  function setFlag(k) { try { sessionStorage.setItem(k, '1'); } catch (e) {} }
  var jpN = 0;
  function jsonp(url, ms) {
    return new Promise(function (res, rej) {
      var name = '__tunr_cb' + (++jpN) + '_' + Date.now().toString(36);
      var sc = document.createElement('script'), done = false;
      var timer = setTimeout(function () { finish(new Error('timeout')); }, ms || 12000);
      function finish(err, data) {
        if (done) return; done = true; clearTimeout(timer);
        // een laat antwoord mag niet in een fout eindigen: noop laten staan en later opruimen
        window[name] = function () {};
        setTimeout(function () { try { delete window[name]; } catch (e) { window[name] = undefined; } }, 60000);
        sc.remove();
        if (err) rej(err); else res(data);
      }
      window[name] = function (data) { finish(null, data); };
      sc.onerror = function () { finish(new Error('jsonp')); };
      sc.async = true;
      sc.src = url + (url.indexOf('?') >= 0 ? '&' : '?') + 'callback=' + name;
      document.head.appendChild(sc);
    });
  }
  function itunes(url) {
    if (flag(JP)) return jsonp(url);
    return fetchJSON(url, 10000).catch(function (e) {
      // TypeError = netwerk/CORS; HTTP-fouten (404 enz.) niet opnieuw proberen
      if (!(e instanceof TypeError)) throw e;
      return jsonp(url).then(function (d) { setFlag(JP); return d; });
    });
  }
  function big(u) { return String(u || '').replace(/\/\d+x\d+(bb|cc)?\.(jpg|jpeg|png|webp)(\?.*)?$/i, '/600x600bb.$2'); }
  function clean(s) { return String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); }
  var podKnown = {};
  function rememberP(arr) { (arr || []).forEach(function (p) { if (p && p.id) podKnown[p.id] = Object.assign({}, podKnown[p.id] || {}, p); }); return arr; }
  function fromChart(r) {
    var g = (r.genres || []).filter(function (x) { return x && x.name && x.name !== 'Podcasts'; })[0] || {};
    return { id: String(r.id), name: clean(r.name), artist: clean(r.artistName), art: big(r.artworkUrl100), genre: clean(g.name) };
  }
  function fromItunes(r) {
    var g = clean(r.primaryGenreName);
    return { id: String(r.collectionId || r.trackId), name: clean(r.collectionName || r.trackName), artist: clean(r.artistName),
      art: big(r.artworkUrl600 || r.artworkUrl100 || r.artworkUrl60), genre: g === 'Podcasts' ? '' : g, count: +r.trackCount || 0,
      feedUrl: String(r.feedUrl || ''), date: r.releaseDate || '' };
  }
  function fromRss(e) {
    var img = (e['im:image'] || []).slice(-1)[0];
    var cat = e.category && e.category.attributes;
    return { id: String(e.id && e.id.attributes && e.id.attributes['im:id'] || ''), name: clean(e['im:name'] && e['im:name'].label),
      artist: clean(e['im:artist'] && e['im:artist'].label), art: big(img && img.label), genre: clean(cat && cat.label),
      desc: clean(e.summary && e.summary.label) };
  }
  function normEp(r, p) {
    return { kind: 'episode', id: String(r.trackId), pid: String(r.collectionId || p.id), title: clean(r.trackName) || '—',
      desc: String(r.description || '').slice(0, 8000), short: clean(r.shortDescription || r.description || '').slice(0, 400),
      date: r.releaseDate || '', dur: Math.round((+r.trackTimeMillis || 0) / 1000), url: String(r.episodeUrl || '').trim(),
      art: big(r.artworkUrl600 || r.artworkUrl160 || '') || p.art, pname: p.name, ext: r.episodeFileExtension || '' };
  }
  function podList(d) { return ((d && d.results) || []).filter(function (r) { return r && (r.collectionId || r.trackId) && (r.collectionName || r.trackName); }).map(fromItunes); }
  function ck(cc) { return String(cc || (T.store.country || {}).cc || 'us').toLowerCase(); }

  T.pod = {
    known: podKnown,
    GENRES: [1489, 1303, 1545, 1488, 1324, 1321, 1512, 1487, 1533, 1318, 1305, 1310],
    cc: function () { return ck(); },
    // toplijst per land (50); terugval: us, daarna een zoekopdracht "podcast"
    top: function (cc) {
      cc = ck(cc);
      var key = 'p:top:' + cc, hit = cacheGet(key);
      if (hit) return Promise.resolve(rememberP(hit));
      function chart(c) {
        return fetchJSON('https://rss.applemarketingtools.com/api/v2/' + c + '/podcasts/top/50/podcasts.json', 10000).then(function (d) {
          var r = (d && d.feed && d.feed.results) || [];
          if (!r.length) throw new Error('empty');
          return r.map(fromChart).filter(function (p) { return p.id && p.name; });
        });
      }
      return chart(cc)
        .catch(function (e) { if (cc !== 'us') return chart('us'); throw e; })
        .catch(function () { return itunes('https://itunes.apple.com/search?media=podcast&entity=podcast&term=podcast&country=' + cc + '&limit=50').then(podList); })
        .then(function (list) { if (list.length) cacheSet(key, list, 6 * HOUR); return rememberP(list); });
    },
    // toplijst per genre (oude iTunes-RSS); terugval: zoeken met genreId
    genre: function (cc, gid) {
      cc = ck(cc);
      var key = 'p:g:' + cc + ':' + gid, hit = cacheGet(key);
      if (hit) return Promise.resolve(rememberP(hit));
      var rss = flag(RSSG) ? Promise.reject(new Error('skip')) :
        fetchJSON('https://itunes.apple.com/' + cc + '/rss/toppodcasts/limit=50/genre=' + enc(gid) + '/json', 10000).then(function (d) {
          var e = (d && d.feed && d.feed.entry) || [];
          if (!Array.isArray(e)) e = [e];
          var l = e.map(fromRss).filter(function (p) { return p.id && p.name; });
          if (!l.length) throw new Error('empty');
          return l;
        }, function (err) { if (err instanceof TypeError) setFlag(RSSG); throw err; });
      return rss.catch(function () {
        return itunes('https://itunes.apple.com/search?media=podcast&entity=podcast&term=podcast&genreId=' + enc(gid) + '&country=' + cc + '&limit=50').then(podList);
      }).then(function (list) { if (list.length) cacheSet(key, list, 6 * HOUR); return rememberP(list); });
    },
    search: function (q, cc) {
      cc = ck(cc);
      var key = 'p:s:' + cc + ':' + String(q).toLowerCase(), hit = cacheGet(key);
      if (hit) return Promise.resolve(rememberP(hit));
      return itunes('https://itunes.apple.com/search?media=podcast&entity=podcast&term=' + enc(q) + '&country=' + cc + '&limit=50').then(podList).then(function (l) {
        cacheSet(key, l, 30 * MIN); return rememberP(l);
      });
    },
    // podcast + afleveringen (nieuwste eerst); null als hij niet bestaat
    lookup: function (id, cc) {
      cc = ck(cc); id = String(id);
      var key = 'p:l:' + id, hit = cacheGet(key);
      if (hit) { rememberP([hit.p]); return Promise.resolve(hit); }
      function one(country) {
        return itunes('https://itunes.apple.com/lookup?id=' + enc(id) + '&entity=podcastEpisode&limit=100' + (country ? '&country=' + country : '')).then(function (d) {
          var rs = (d && d.results) || [];
          var pr = rs.filter(function (r) { return r.wrapperType === 'track' || r.kind === 'podcast'; })[0];
          if (!pr) return null;
          var p = fromItunes(pr);
          var k = podKnown[p.id]; if (k && k.desc) p.desc = k.desc;
          var eps = rs.filter(function (r) { return r.wrapperType === 'podcastEpisode' || r.kind === 'podcast-episode'; })
            .map(function (r) { return normEp(r, p); }).filter(function (e) { return e.url; })
            .sort(function (a, b) { return String(b.date).localeCompare(String(a.date)); });
          return { p: p, eps: eps };
        });
      }
      return one(cc).then(function (r) { return r || one(''); }).then(function (r) {
        if (r) { cacheSet(key, r, 30 * MIN); rememberP([r.p]); }
        return r;
      });
    },
    // beschrijving van de podcast (staat niet in de iTunes-gegevens): uit de RSS-feed zelf, als die dat toestaat
    describe: function (p) {
      if (!p) return Promise.resolve('');
      if (p.desc) return Promise.resolve(p.desc);
      var key = 'p:d:' + p.id, hit = cacheGet(key);
      if (hit != null) return Promise.resolve(hit.v || '');
      var u = String(p.feedUrl || '');
      if (!/^https?:\/\//i.test(u) || (location.protocol === 'https:' && /^http:/i.test(u))) return Promise.resolve('');
      var ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
      var timer = setTimeout(function () { if (ctl) ctl.abort(); }, 8000);
      return fetch(u, ctl ? { signal: ctl.signal } : undefined).then(function (r) { clearTimeout(timer); if (!r.ok) throw new Error(r.status); return r.text(); })
        .then(function (xml) {
          var doc = new DOMParser().parseFromString(xml.slice(0, 400000), 'text/xml');
          var ch = doc.querySelector('channel');
          var n = ch && Array.prototype.find.call(ch.children, function (c) { return c.localName === 'summary' || c.localName === 'description'; });
          var d = n ? clean(n.textContent.replace(/<[^>]+>/g, ' ')).slice(0, 2000) : '';
          cacheSet(key, { v: d }, DAY);
          return d;
        }).catch(function () { clearTimeout(timer); cacheSet(key, { v: '' }, DAY); return ''; });
    }
  };
})();

// Tunr webspeler: lokale opslag (localStorage) voor land, regio, taal, instellingen, favorieten, recent en zoekgeschiedenis.
// Favorieten en recent bewaren de volledige zender (JSON), zodat de lijst ook zonder netwerk werkt (SPEC §4).
(function () {
  var T = window.T = window.T || {};
  var P = 'tunr.';
  function read(k, d) { try { var v = localStorage.getItem(P + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } }
  function write(k, v) { try { if (v == null) localStorage.removeItem(P + k); else localStorage.setItem(P + k, JSON.stringify(v)); } catch (e) {} }
  var subs = [];
  function emit(what) { subs.forEach(function (f) { try { f(what); } catch (e) { console.warn(e); } }); }
  function slim(s) { // genoeg om de zender te tonen en af te spelen
    return { id: s.id, name: s.name, url: s.url, stream: s.stream, homepage: s.homepage, favicon: s.favicon, tags: s.tags, country: s.country, cc: s.cc, state: s.state, language: s.language, codec: s.codec, bitrate: s.bitrate, hls: s.hls, votes: s.votes, clicks: s.clicks, lat: s.lat, lon: s.lon };
  }

  T.store = {
    on: function (f) { subs.push(f); },
    // land: { cc, name } (name = Engelse naam uit /json/countries, nodig voor /json/states)
    get country() { return read('country', null); },
    set country(v) { write('country', v); write('region', null); emit('country'); },
    get region() { var r = read('region', null); var c = read('country', null); return r && c && r.cc === c.cc ? r.name : null; },
    set region(name) { var c = read('country', null); write('region', name && c ? { cc: c.cc, name: name } : null); emit('region'); },
    // taal: 'nl' | 'en' (gedeeld met de website: localStorage 'tunr.lang', geen JSON)
    get lang() {
      var v = null; try { v = localStorage.getItem('tunr.lang'); } catch (e) {}
      if (v === 'nl' || v === 'en') return v;
      return String(navigator.language || 'en').toLowerCase().indexOf('nl') === 0 ? 'nl' : 'en';
    },
    get langSetting() { var v = null; try { v = localStorage.getItem('tunr.lang'); } catch (e) {} return v === 'nl' || v === 'en' ? v : 'system'; },
    set lang(v) { try { if (v === 'system') localStorage.removeItem('tunr.lang'); else localStorage.setItem('tunr.lang', v); } catch (e) {} emit('lang'); },
    // build 9: de intromuziek speelt altijd (geen instelling meer)
    get intro() { return true; },
    get volume() { var v = read('volume', 1); return typeof v === 'number' ? Math.min(1, Math.max(0, v)) : 1; },
    set volume(v) { write('volume', v); },

    // favorieten (nieuwste eerst)
    favorites: function () { return read('favorites', []); },
    isFav: function (id) { return read('favorites', []).some(function (s) { return s.id === id; }); },
    toggleFav: function (s) {
      var f = read('favorites', []);
      var i = f.findIndex(function (x) { return x.id === s.id; });
      if (i >= 0) f.splice(i, 1); else f.unshift(slim(s));
      write('favorites', f); emit('favorites');
      return i < 0;
    },
    removeFav: function (id) { write('favorites', read('favorites', []).filter(function (s) { return s.id !== id; })); emit('favorites'); },
    replaceFavs: function (fresh) { // na verversen via /json/stations/byuuid: volgorde behouden
      var f = read('favorites', []), by = {};
      fresh.forEach(function (s) { by[s.id] = s; });
      write('favorites', f.map(function (s) { return by[s.id] ? slim(by[s.id]) : s; }));
    },
    clearFavs: function () { write('favorites', []); emit('favorites'); },

    // recent (max 30)
    recents: function () { return read('recents', []); },
    addRecent: function (s) {
      var r = read('recents', []).filter(function (x) { return x.id !== s.id; });
      r.unshift(slim(s)); write('recents', r.slice(0, 30)); emit('recents');
    },
    clearRecents: function () { write('recents', []); emit('recents'); },

    // zoekgeschiedenis (max 8)
    searches: function () { return read('searches', []); },
    addSearch: function (q) {
      q = String(q || '').trim(); if (q.length < 2) return;
      var r = read('searches', []).filter(function (x) { return x.toLowerCase() !== q.toLowerCase(); });
      r.unshift(q); write('searches', r.slice(0, 8)); emit('searches');
    },
    clearSearches: function () { write('searches', []); emit('searches'); },
    // recente kaartzoekopdrachten (max 5): { k: 'c', cc, name } of { k: 'p', name, sub, cc, lat, lon }
    mapSearches: function () { var r = read('mapSearches', []); return Array.isArray(r) ? r : []; },
    addMapSearch: function (it) {
      if (!it || !it.name) return;
      var key = function (x) { return x.k === 'c' ? 'c:' + x.cc : 'p:' + String(x.name).toLowerCase() + ':' + (+x.lat).toFixed(2) + ':' + (+x.lon).toFixed(2); };
      var r = T.store.mapSearches().filter(function (x) { return x && key(x) !== key(it); });
      r.unshift(it); write('mapSearches', r.slice(0, 5));
    },
    get searchWorld() { return read('searchWorld', false); },
    set searchWorld(v) { write('searchWorld', !!v); },

    // ---------- podcasts (SPEC §8) ----------
    // gevolgde podcasts (nieuwste eerst): id, naam, maker, art, genre, feedUrl
    follows: function () { return read('follows', []); },
    isFollowing: function (id) { id = String(id); return read('follows', []).some(function (p) { return p.id === id; }); },
    toggleFollow: function (p) {
      var f = read('follows', []), id = String(p.id);
      var i = f.findIndex(function (x) { return x.id === id; });
      if (i >= 0) f.splice(i, 1); else f.unshift({ id: id, name: p.name, artist: p.artist || '', art: p.art || '', genre: p.genre || '', feedUrl: p.feedUrl || '' });
      write('follows', f); emit('follows');
      return i < 0;
    },
    // afspeelposities: episodeId → { t, d, done, u, ep } (max 500, oudste eruit); ≥ 95% = beluisterd
    pos: function (id) { return read('pos', {})[String(id)] || null; },
    savePos: function (ep, t, d) {
      if (!ep || !ep.id || !(d > 0)) return;
      var all = read('pos', {});
      var done = t / d >= 0.95;
      all[ep.id] = { t: done ? 0 : Math.max(0, Math.round(t)), d: Math.round(d), done: done, u: Date.now(),
        ep: { kind: 'episode', id: ep.id, pid: ep.pid, title: ep.title, pname: ep.pname, art: ep.art, url: ep.url, date: ep.date, dur: ep.dur || Math.round(d), short: String(ep.short || '').slice(0, 200) } };
      var keys = Object.keys(all);
      if (keys.length > 500) keys.sort(function (a, b) { return (all[a].u || 0) - (all[b].u || 0); }).slice(0, keys.length - 500).forEach(function (k) { delete all[k]; });
      write('pos', all); emit('pos');
    },
    // half beluisterde afleveringen, laatst beluisterd eerst
    continueEps: function () {
      var all = read('pos', {});
      return Object.keys(all).map(function (k) { return all[k]; })
        .filter(function (x) { return x && x.ep && !x.done && x.t >= 5; })
        .sort(function (a, b) { return (b.u || 0) - (a.u || 0); }).slice(0, 30).map(function (x) { return x.ep; });
    },
    get podRate() { var r = read('podRate', 1); return [0.8, 1, 1.25, 1.5, 1.75, 2].indexOf(r) >= 0 ? r : 1; },
    set podRate(v) { write('podRate', v); },
    get searchMode() { return read('searchMode', 'st'); },
    set searchMode(v) { write('searchMode', v === 'pod' ? 'pod' : 'st'); },
    get podSort() { return read('podSort', 'new') === 'old' ? 'old' : 'new'; },
    set podSort(v) { write('podSort', v === 'old' ? 'old' : 'new'); }
  };
})();

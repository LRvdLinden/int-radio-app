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
    get intro() { return read('intro', true); },
    set intro(v) { write('intro', !!v); emit('settings'); },
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
    get searchWorld() { return read('searchWorld', false); },
    set searchWorld(v) { write('searchWorld', !!v); }
  };
})();

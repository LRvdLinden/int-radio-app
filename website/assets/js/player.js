// Tunr webspeler: opstarten (tik om te starten → splash met tune → landkeuze), hash-routing en de
// gedeelde klikafhandeling. Modules: api.js, store.js, strings.js, audio.js, ui.js, views.js, map.js.
(function () {
  var T = window.T;
  var t = T.t;
  var view = document.getElementById('view');
  var current = null; // { name }

  document.documentElement.lang = T.store.lang;

  // ================= start + splash =================
  function applyStatic() {
    document.documentElement.lang = T.store.lang;
    document.querySelectorAll('[data-t]').forEach(function (el) { el.textContent = t(el.getAttribute('data-t')); });
    var g = document.getElementById('gate-go'); if (g) g.setAttribute('aria-label', t('tap.btn'));
    var lg = document.getElementById('gate-logo'); if (lg) lg.outerHTML = '<span id="gate-logo">' + T.TUNR_LOGO() + '</span>';
  }
  applyStatic();

  var seen = false; try { seen = sessionStorage.getItem('tunr.splash') === '1'; } catch (e) {}
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var gate = document.getElementById('gate');

  function boot() {
    T.ui.renderNav();
    window.addEventListener('hashchange', route);
    route();
  }
  function splash(done) {
    var el = document.getElementById('splash');
    var tune = null;
    var timers = [], finished = false;
    function at(ms, f) { timers.push(setTimeout(f, ms)); }
    if (T.store.intro) {
      tune = new Audio();
      var canAac = tune.canPlayType('audio/mp4; codecs="mp4a.40.2"');
      tune.src = '../assets/audio/' + (canAac ? 'tunr_tune.m4a' : 'tunr_tune.mp3');
      tune.volume = 0.85;
      var p = tune.play(); if (p && p.catch) p.catch(function () { /* geen geluid: gewoon door */ });
    }
    if (reduce) { // korte, rustige versie
      el.hidden = false; el.querySelector('.scale').style.opacity = 1;
      el.querySelectorAll('.word span').forEach(function (s) { s.style.opacity = 1; s.style.transform = 'none'; });
      setTimeout(finish, 900);
    } else {
      el.hidden = false;
      run(el);
    }
    function finish() {
      if (finished) return; finished = true;
      timers.forEach(clearTimeout);
      if (tune) { var v = tune.volume, iv = setInterval(function () { v -= 0.1; if (v <= 0) { clearInterval(iv); tune.pause(); } else tune.volume = v; }, 40); }
      el.classList.add('out');
      setTimeout(function () { el.remove(); }, 320);
      done();
    }
    el.addEventListener('click', finish);
    document.addEventListener('keydown', function k(e) { if (!finished && (e.key === 'Enter' || e.key === ' ' || e.key === 'Escape')) { e.preventDefault(); finish(); document.removeEventListener('keydown', k); } });
    el.querySelector('.skip').focus({ preventScroll: true });

    function run(el) {
      var scale = el.querySelector('.scale'), needle = el.querySelector('.needle'), word = el.querySelectorAll('.word span'), waves = el.querySelectorAll('.waves i');
      var A = function (n, k, o) { return n.animate ? n.animate(k, o) : null; };
      // 0–0,4 s: schaal fadet in
      A(scale, [{ opacity: 0, transform: 'scale(1.04)' }, { opacity: 1, transform: 'none' }], { duration: 420, easing: 'ease-out', fill: 'forwards' });
      // 0–1,4 s: naald zoekt met haperingen, 1,45 s: lock op 58%
      A(needle, [
        { left: '2%' }, { left: '22%', offset: .18 }, { left: '19%', offset: .26 }, { left: '44%', offset: .45 }, { left: '41%', offset: .53 },
        { left: '72%', offset: .72 }, { left: '66%', offset: .82 }, { left: '59.5%', offset: .94 }, { left: '58%' }
      ], { duration: 1450, easing: 'cubic-bezier(.4,.1,.3,1)', fill: 'forwards' });
      at(1450, function () {
        A(needle, [{ transform: 'scaleY(1.25)', boxShadow: '0 0 30px #FFB020,0 0 70px #FFB020' }, { transform: 'none' }], { duration: 300, easing: 'ease-out' });
        waves.forEach(function (w, i) { A(w, [{ opacity: .9, transform: 'scale(.3)' }, { opacity: 0, transform: 'scale(3.4)' }], { duration: 1100, delay: i * 160, easing: 'ease-out', fill: 'forwards' }); });
      });
      // 1,6 s: T U N R springen omhoog (90 ms uit elkaar), schaal krimpt tot de balk onder het woordmerk
      at(1600, function () {
        word.forEach(function (s, i) { A(s, [{ opacity: 0, transform: 'translateY(60%)' }, { opacity: 1, transform: 'translateY(-8%)', offset: .7 }, { opacity: 1, transform: 'none' }], { duration: 480, delay: i * 90, easing: 'cubic-bezier(.2,.8,.2,1.2)', fill: 'forwards' }); });
        A(el.querySelector('.ticks:not(.major)'), [{ opacity: 1 }, { opacity: 0 }], { duration: 380, fill: 'forwards' });
        A(el.querySelector('.ticks.major'), [{ opacity: 1 }, { opacity: 0 }], { duration: 380, fill: 'forwards' });
        A(el.querySelector('.nums'), [{ opacity: 1 }, { opacity: 0 }], { duration: 300, fill: 'forwards' });
        A(scale, [{ transform: 'none' }, { transform: 'translateY(-56px) scaleX(.62)' }], { duration: 600, delay: 120, easing: 'cubic-bezier(.3,.7,.2,1)', fill: 'forwards' });
        A(needle, [{ height: '84px', top: '-14px' }, { height: '30px', top: '44px' }], { duration: 600, delay: 120, easing: 'cubic-bezier(.3,.7,.2,1)', fill: 'forwards' });
      });
      at(2100, function () { el.classList.add('shine'); });
      at(3100, finish);
    }
  }

  // ================= routing =================
  // #/discover, #/browse, #/browse/local, #/browse/local/<regio>, #/browse/music, #/browse/news, #/browse/language,
  // #/browse/language/<x>, #/top100, #/map, #/station/<uuid>, #/genre/<tag>, #/list/<popular|trending>, #/search, #/library,
  // #/settings, #/country  (?p=1 = volledige speler open, zodat "terug" hem sluit)
  // podcasts: #/podcasts, #/podcasts/genre/<id>, #/podcast/<id>, #/episode/<podcastId>/<episodeId>
  var TAB_OF = { discover: 'discover', list: 'discover', browse: 'browse', top100: 'browse', genre: 'browse', podcasts: 'browse', podcast: null, episode: null, map: 'map', search: 'search', library: 'library', settings: 'settings', station: null, country: 'settings' };
  function parse() {
    var h = location.hash.replace(/^#\/?/, '');
    var q = ''; var qi = h.indexOf('?'); if (qi >= 0) { q = h.slice(qi + 1); h = h.slice(0, qi); }
    var parts = h.split('/').filter(Boolean);
    return { parts: parts, q: new URLSearchParams(q) };
  }
  function route() {
    var r = parse(), p = r.parts, name = p[0] || '';
    // volledige speler hoort bij de geschiedenis
    if (r.q.get('p') === '1') { if (!T.ui.isFullOpen() && T.player.current) T.ui.openFull(); if (current) return; }
    else if (T.ui.isFullOpen()) { T.ui.closeFull(true); if (current && current.hash === location.hash.split('?')[0]) return; }

    if (!T.store.country && name !== 'country') { location.replace('#/country'); return; }
    if (!name) { location.replace('#/discover'); return; }
    var key = location.hash.split('?')[0] + (name === 'search' || name === 'library' ? '' : '?' + r.q.toString());
    if (current && current.key === key) return;

    if (current && current.name === 'map' && T.views.map.leave) T.views.map.leave();
    T.ui.closeSheet();
    T.views._next();
    T.ui.resetLists();
    T.ui.detailRefresh = null; T.ui.libRender = null; T.ui.podRefresh = null;
    document.body.classList.toggle('solo', name === 'country' && !T.store.country);
    document.body.classList.toggle('on-map', name === 'map');
    document.title = 'Tunr';
    view.onclick = null;

    var fn = null, args = p.slice(1), tab = TAB_OF[name];
    switch (name) {
      case 'discover': fn = T.views.discover; break;
      case 'list': fn = T.views.list; break;
      case 'browse':
        if (p[1] === 'local') { fn = p[2] ? T.views.region : T.views.local; args = p.slice(2); }
        else if (p[1] === 'music') fn = T.views.music;
        else if (p[1] === 'news') fn = T.views.news;
        else if (p[1] === 'language') { fn = p[2] ? T.views.language : T.views.languages; args = p.slice(2); }
        else fn = T.views.browse;
        break;
      case 'top100': fn = T.views.top100; break;
      case 'podcasts':
        if (p[1] === 'genre' && p[2]) { fn = T.views.podGenre; args = p.slice(2); } else fn = T.views.podcasts;
        break;
      case 'podcast': fn = T.views.podcast; tab = T.ui.curTab || 'browse'; break;
      case 'episode': fn = T.views.episode; tab = T.ui.curTab || 'browse'; break;
      case 'genre': fn = T.views.genre; break;
      case 'map': fn = T.views.map; break;
      case 'station': fn = T.views.station; tab = T.ui.curTab; break;
      case 'search': fn = T.views.search; args = [r.q.get('q') || '', r.q.get('m') || '']; break;
      case 'library': fn = T.views.library; args = [r.q.get('seg') || '']; break;
      case 'settings': fn = T.views.settings; break;
      case 'country': fn = T.views.country; break;
      default: location.replace('#/discover'); return;
    }
    current = { name: name, key: key, hash: location.hash.split('?')[0] };
    T.ui.markNav(tab);
    if (name === 'search') fn(view, [], args[0], args[1]);
    else if (name === 'library') fn(view, [], args[0]);
    else fn(view, args);
    if (name !== 'map') window.scrollTo(0, 0);
    // focus naar de nieuwe inhoud voor schermlezers/toetsenbord (niet bij de eerste keer)
    if (route.n++ > 0 && name !== 'search' && name !== 'country') view.focus({ preventScroll: true });
  }
  route.n = 0;
  T.route = route;

  function rerender() { if (current) { var c = current; current = null; route(); } }

  // ================= klikafhandeling (één listener) =================
  // aflevering uit de lijst van de container (podcastpagina, rijen) of uit de opgeslagen posities
  function episodeFrom(el) {
    var host = el.closest('[data-eid]'); if (!host) return null;
    var id = host.getAttribute('data-eid');
    var lc = el.closest('[data-list]');
    var list = lc ? T.ui.list(lc.getAttribute('data-list')) : [];
    var e = list.find(function (x) { return x.id === id; }) || (T.player.current && T.player.current.id === id ? T.player.current : null);
    if (!e) { var ps = T.store.pos(id); e = ps && ps.ep; }
    return e ? { e: e, list: list.length ? list : [e] } : null;
  }
  function stationFrom(el) {
    var host = el.closest('[data-sid]'); if (!host) return null;
    var id = host.getAttribute('data-sid');
    var lc = el.closest('[data-list]');
    var list = lc ? T.ui.list(lc.getAttribute('data-list')) : [];
    var s = list.find(function (x) { return x.id === id; }) || T.api.known[id] || (T.player.current && T.player.current.id === id ? T.player.current : null);
    if (!s) s = T.store.favorites().concat(T.store.recents()).find(function (x) { return x.id === id; });
    return s ? { s: s, list: list } : null;
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest('[data-act]'); if (!a) {
      var sc = e.target.closest('[data-scroll]');
      if (sc) { var row = sc.closest('.sec').querySelector('.scroller'); row.scrollBy({ left: +sc.getAttribute('data-scroll') * row.clientWidth * 0.85, behavior: 'smooth' }); }
      return;
    }
    var act = a.getAttribute('data-act');
    var cur = T.player.current;
    switch (act) {
      case 'play': {
        var x = stationFrom(a); if (!x) return;
        if (T.player.isCurrent(x.s.id) && (T.player.state === 'playing' || T.player.state === 'loading')) T.player.pause();
        else if (T.player.isCurrent(x.s.id) && T.player.state === 'paused') T.player.resume();
        else T.player.play(x.s, x.list.length ? x.list : null);
        break;
      }
      case 'fav': {
        var y = a.closest('#full') || a.closest('#mini') ? (cur ? { s: cur } : null) : stationFrom(a);
        if (y) T.ui.toggleFav(y.s);
        if (T.ui.isFullOpen()) T.ui.renderFull();
        T.ui.renderMini();
        if (T.ui.libRender) T.ui.libRender();
        break;
      }
      case 'eplay': {
        var ex = episodeFrom(a); if (!ex) return;
        if (T.player.isCurrent(ex.e.id) && (T.player.state === 'playing' || T.player.state === 'loading')) T.player.pause();
        else if (T.player.isCurrent(ex.e.id) && T.player.state === 'paused') T.player.resume();
        else T.player.play(ex.e, ex.list);
        break;
      }
      case 'back15': T.player.skip(-15); break;
      case 'fwd30': T.player.skip(30); break;
      case 'speed': T.ui.speedSheet(); break;
      case 'podshare': {
        var hp = location.hash.match(/^#\/podcast\/([^/?]+)/), pk = hp && T.pod.known[decodeURIComponent(hp[1])];
        if (pk) T.ui.share({ kind: 'podcast', id: pk.id, name: pk.name, href: '#/podcast/' + encodeURIComponent(pk.id) });
        break;
      }
      case 'unfav': { var z = stationFrom(a); if (z) { T.store.removeFav(z.s.id); if (T.ui.libRender) T.ui.libRender(); } break; }
      case 'share': { var w = a.closest('#full') ? (cur ? { s: cur } : null) : stationFrom(a); if (w) T.ui.share(w.s); break; }
      case 'toggle': T.player.toggle(); break;
      case 'prev': T.player.prev(); break;
      case 'next': T.player.next(); break;
      case 'retry': T.player.retry(); break;
      case 'sleep': T.ui.sleepSheet(); break;
      case 'openfull': T.ui.openFull(); break;
      case 'closefull': T.ui.closeFull(); break;
      case 'closefull-nav': // naar zenderinfo: speler dicht zonder history.back
        e.preventDefault();
        if (T.ui.isFullOpen()) { T.ui.closeFull(true); }
        location.hash = a.getAttribute('href');
        break;
      case 'mute': {
        if (T.player.volume > 0) { T.player._prevVol = T.player.volume; T.player.setVolume(0); }
        else T.player.setVolume(T.player._prevVol || 1);
        T.ui.renderMini();
        break;
      }
      case 'back':
        // binnen de app genavigeerd → terug in de geschiedenis; direct op een diepe link geland → naar Ontdek
        if (route.n > 1) history.back(); else location.hash = '#/discover';
        break;
    }
  });
  // tijdbalk: tijdens slepen alleen de tijd tonen, bij loslaten spoelen
  function seekLabel(r) {
    var d = T.player.duration, v = +r.value;
    r.style.setProperty('--p', (d ? v / d * 100 : 0) + '%');
    var w = r.closest('#mini, #full'); if (!w) return;
    w.querySelectorAll('[data-tm]').forEach(function (n) { n.textContent = T.clock(v); });
    w.querySelectorAll('[data-tl]').forEach(function (n) { n.textContent = '-' + T.clock(Math.max(0, d - v)); });
  }
  document.addEventListener('change', function (e) {
    var r = e.target.closest('[data-act="seek"]'); if (!r) return;
    r.dataset.drag = ''; T.player.seek(+r.value);
  });
  document.addEventListener('input', function (e) {
    var sk = e.target.closest('[data-act="seek"]');
    if (sk) { sk.dataset.drag = '1'; seekLabel(sk); return; }
    var r = e.target.closest('[data-act="vol"]'); if (!r) return;
    var v = +r.value; T.player.setVolume(v);
    document.querySelectorAll('[data-act="vol"]').forEach(function (x) { if (x !== r) x.value = v; x.style.setProperty('--p', (v * 100) + '%'); });
  });
  // sneltoetsen: spatie = afspelen/pauze, Esc sluit de speler/sheet
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { if (document.getElementById('sheet')) T.ui.closeSheet(); else if (T.ui.isFullOpen()) T.ui.closeFull(); return; }
    var tag = (e.target.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'button' || tag === 'a' || e.target.isContentEditable) return;
    if (e.key === ' ' && T.player.current) { e.preventDefault(); T.player.toggle(); }
    if (T.player.isEpisode && (e.key === 'ArrowLeft' || e.key === 'ArrowRight') && !e.metaKey && !e.ctrlKey) { e.preventDefault(); T.player.skip(e.key === 'ArrowLeft' ? -15 : 30); }
  });
  // vegen omlaag sluit de volledige speler
  (function () {
    var full = document.getElementById('full'), y0 = null;
    full.addEventListener('touchstart', function (e) { if (full.querySelector('.fin').scrollTop <= 0) y0 = e.touches[0].clientY; }, { passive: true });
    full.addEventListener('touchend', function (e) { if (y0 != null && e.changedTouches[0].clientY - y0 > 90) T.ui.closeFull(); y0 = null; });
  })();

  // ================= reageren op speler en opslag =================
  var lastSt = null, lastId = null;
  T.player.on(function (st, s) {
    T.ui.renderMini();
    if (T.ui.isFullOpen()) T.ui.renderFull();
    T.ui.syncPlaying();
    if (T.views.map.sync) T.views.map.sync();
    if (T.ui.detailRefresh) T.ui.detailRefresh();
    if (T.ui.podRefresh && (!s || s.kind === 'episode') && st === 'paused') T.ui.podRefresh();
    if (current && current.name === 'library' && T.ui.libRender && s && s.id !== lastId) T.ui.libRender();
    if (st === 'error' && lastSt !== 'error') T.ui.toast(t('player.err'));
    lastSt = st; lastId = s && s.id;
  });
  setInterval(function () { if (T.player.sleepEnd && T.ui.isFullOpen()) T.ui.renderFull(); }, 30000);
  T.player.onTime(function () { T.ui.tick(); });
  T.store.on(function (what) {
    if (what === 'lang') { applyStatic(); T.ui.renderNav(); T.ui.renderMini(); if (T.ui.isFullOpen()) T.ui.renderFull(); rerender(); }
    if (what === 'country') { T.ui.renderNav(); }
  });
  window.addEventListener('resize', function () { if (T.views.map.resize) T.views.map.resize(); });
  // andere tab wijzigt favorieten/taal
  window.addEventListener('storage', function (e) {
    if (!e.key) return;
    if (e.key === 'tunr.lang') { applyStatic(); T.ui.renderNav(); rerender(); }
    if ((e.key === 'tunr.favorites' || e.key === 'tunr.follows') && T.ui.libRender) T.ui.libRender();
  });
  function startApp() {
  // Na de eerste keer in deze sessie: geen poort en geen splash (geen geluid zonder tik nodig).
  if (seen) { gate.remove(); boot(); }
  else {
    var started = false;
    var start = function () {
      if (started) return; started = true;
      try { sessionStorage.setItem('tunr.splash', '1'); } catch (e) {}
      gate.classList.add('out');
      setTimeout(function () { gate.remove(); }, 400);
      splash(boot);
    };
    document.getElementById('gate-go').addEventListener('click', start);
    gate.addEventListener('click', function (e) { if (e.target === gate || e.target.closest('.in')) start(); });
    document.addEventListener('keydown', function onk(e) { if (!started && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); start(); document.removeEventListener('keydown', onk); } });
    setTimeout(function () { var g = document.getElementById('gate-go'); if (g && !started) g.focus(); }, 50);
    // routing alvast klaarzetten achter de poort, zodat de eerste view meteen kan laden
    T.ui.renderNav();
    window.addEventListener('hashchange', route);
    route();
    boot = function () {};
  }

  }
  startApp();
})();

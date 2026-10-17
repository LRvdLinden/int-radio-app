// Tunr webspeler: schermen. Elke view krijgt (el, params) en tekent zichzelf; T.views.<naam>.
// Ontdek, Bladeren (+ Lokaal/regio's, Muziek, Nieuws & Talk, Sport, Op taal, Top 100), genre, zenderdetail,
// Zoeken, Bibliotheek, Instellingen en Landkeuze.
(function () {
  var T = window.T = window.T || {};
  var t = function (k, v) { return T.t(k, v); }, esc = T.esc, I = function (n, c) { return T.icon(n, c); };
  var V = T.views = {};
  var GENRES = ['pop', 'news', 'rock', 'dance', 'jazz', 'classical', 'hits', 'talk', 'sports', 'oldies', 'hiphop', 'country', 'ambient', 'christian'];
  var MUSIC = ['pop', 'rock', 'dance', 'jazz', 'classical', 'hits', 'oldies', 'hiphop', 'country', 'ambient', 'christian', 'electronic', 'house', 'soul', 'reggae', 'latin', 'metal', 'blues', 'chillout', 'indie'];
  T.GENRES = GENRES;
  var token = 0; // laat late antwoorden van een vorige view vallen
  function live(tk) { return tk === token; }
  V._next = function () { return ++token; };
  V._token = function () { return token; };
  function country() { return T.store.country || { cc: 'NL', name: 'The Netherlands' }; }
  function cname() { var c = country(); return T.countryName(c.cc, c.name); }
  function chipHTML(tag) { var p = T.pal(tag); return '<a class="chip" href="#/genre/' + encodeURIComponent(tag) + '" style="--a:' + p[0] + ';--b:' + p[1] + '"><i></i>' + esc(T.genreLabel(tag)) + '</a>'; }

  // ================= Landkeuze =================
  V.country = function (el) {
    var tk = token;
    var cur = T.store.country;
    var first = !cur;
    el.innerHTML = '<div class="country">' + (first ? T.TUNR_LOGO() : '<header class="top" style="padding:0;margin-bottom:6px"><button class="iconbtn" type="button" data-act="back" aria-label="' + esc(t('back')) + '">' + I('back') + '</button></header>') +
      '<h1 class="ptitle">' + esc(t('country.title')) + '</h1><p class="psub">' + esc(t('country.sub')) + '</p>' +
      '<label class="field"><span class="sr">' + esc(t('country.search')) + '</span>' + I('search', 'lead') + '<input type="search" id="cq" placeholder="' + esc(t('country.search')) + '" autocomplete="off" spellcheck="false"></label>' +
      '<div id="clist">' + T.ui.skList(10) + '</div></div>';
    var input = el.querySelector('#cq');
    var all = [];
    function region() {
      var langs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || ''];
      for (var i = 0; i < langs.length; i++) {
        var m = String(langs[i]).match(/[-_]([A-Za-z]{2})\b/);
        if (m) return m[1].toUpperCase();
      }
      try { var r = new Intl.Locale(navigator.language).maximize().region; if (r) return r; } catch (e) {}
      return null;
    }
    function rowHTML(c) {
      return '<button type="button" data-cc="' + esc(c.cc) + '"' + (cur && cur.cc === c.cc ? ' aria-current="true"' : '') + '><span class="fl" aria-hidden="true">' + T.flag(c.cc) + '</span><span class="lab">' + esc(c.label) + '</span><span class="cnt">' + esc(T.stationsN(c.count)) + '</span></button>';
    }
    function render() {
      var q = input.value.trim().toLocaleLowerCase();
      var norm = function (s) { return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase(); };
      var list = q ? all.filter(function (c) { return norm(c.label).indexOf(norm(q)) >= 0 || norm(c.name).indexOf(norm(q)) >= 0 || c.cc.toLowerCase() === q; }) : all;
      var rc = region(), sug = !q && rc ? all.filter(function (c) { return c.cc === rc; }) : [];
      if (!q && cur && cur.cc !== rc) sug = all.filter(function (c) { return c.cc === cur.cc; }).concat(sug);
      var html = '';
      if (sug.length) html += '<h3>' + esc(t('country.suggested')) + '</h3><div class="rows">' + sug.map(rowHTML).join('') + '</div>';
      html += '<h3>' + esc(t('country.all')) + '</h3>' + (list.length ? '<div class="rows">' + list.map(rowHTML).join('') + '</div>' : '<p class="psub" style="padding:10px 4px">' + esc(t('country.none')) + '</p>');
      el.querySelector('#clist').innerHTML = html;
    }
    function load() {
      el.querySelector('#clist').innerHTML = T.ui.skList(10);
      T.api.countries().then(function (cs) {
        if (!live(tk)) return;
        all = cs.map(function (c) { return { cc: c.cc, name: c.name, count: c.count, label: T.countryName(c.cc, c.name) }; })
          .sort(function (a, b) { return a.label.localeCompare(b.label, T.locale()); });
        render();
      }).catch(function () { if (live(tk)) el.querySelector('#clist').innerHTML = T.ui.error(load); });
    }
    input.addEventListener('input', render);
    el.querySelector('#clist').addEventListener('click', function (e) {
      var b = e.target.closest('[data-cc]'); if (!b) return;
      var c = all.find(function (x) { return x.cc === b.getAttribute('data-cc'); });
      if (!c) return;
      T.store.country = { cc: c.cc, name: c.name };
      document.body.classList.remove('solo');
      T.ui.renderNav();
      location.hash = '#/discover';
    });
    load();
    if (!first || window.innerWidth > 700) setTimeout(function () { input.focus({ preventScroll: true }); }, 50);
  };

  // ================= Ontdek =================
  V.discover = function (el) {
    var tk = token, c = country(), cn = cname();
    var recents = T.store.recents(), favs = T.store.favorites(), region = T.store.region;
    el.innerHTML = '<div class="pg"><header class="top"><span class="mob">' + T.TUNR_LOGO() + '</span><span class="sp"></span>' + T.ui.ccBtn() + T.ui.gearBtn() + '</header>' +
      '<h1 class="greet"><small>' + esc(T.flag(c.cc) + ' ' + cn) + '</small>' + esc(T.ui.greeting()) + '</h1>' +
      '<div id="hero"><div class="sk skhero"></div></div>' +
      (recents.length ? T.ui.row(t('row.continue'), recents, { all: '#/library?seg=recent' }) : '') +
      '<div id="local">' + (region ? T.ui.skRow() : localPick()) + '</div>' +
      '<div id="pop">' + T.ui.skRow() + '</div><div id="trend">' + T.ui.skRow() + '</div>' +
      (T.store.continueEps().length ? T.ui.epRow(t('pod.continue'), T.store.continueEps(), { all: '#/library?seg=podcasts' }) : '') +
      '<div id="pnew"></div><div id="ppop">' + T.ui.skRow() + '</div>' +
      (favs.length ? T.ui.row(t('row.favorites'), favs, { all: '#/library' }) : '') +
      '<section class="sec"><div class="sech"><h2>' + esc(t('row.genres')) + '</h2></div><div class="chips">' + GENRES.map(chipHTML).join('') + '</div></section>' +
      '<div id="g2">' + T.ui.skRow() + '</div></div>';
    function localPick() {
      return '<section class="sec"><div class="sech"><h2>' + esc(t('row.local')) + '</h2></div><a class="pickcard" href="#/browse/local"><span class="pi">' + I('pin') + '</span><span><b>' + esc(t('local.pick')) + '</b><small>' + esc(t('local.pick.sub')) + '</small></span>' + I('chev', 'ic chev') + '</a></section>';
    }
    function fill(id, html) { var n = el.querySelector('#' + id); if (n) n.innerHTML = html; }
    function load() {
      T.api.popular(c.cc).then(function (pop) {
        if (!live(tk)) return;
        if (!pop.length) { fill('hero', ''); fill('pop', T.ui.empty(t('empty'))); return; }
        fill('hero', hero(pop.slice(0, 6)));
        startCarousel(el.querySelector('#hero .hero'));
        fill('pop', T.ui.row(t('row.popular', { c: cn }), pop, { all: '#/list/popular' }));
        // twee genres met de meeste zenders (uit de tags van de populairste zenders)
        var count = {};
        pop.forEach(function (s) { s.tags.forEach(function (tg) { if (GENRES.indexOf(tg) >= 0) count[tg] = (count[tg] || 0) + 1; }); });
        var top = Object.keys(count).sort(function (a, b) { return count[b] - count[a]; }).slice(0, 2);
        if (top.length < 2) ['pop', 'news', 'rock'].forEach(function (g) { if (top.length < 2 && top.indexOf(g) < 0) top.push(g); });
        Promise.all(top.map(function (g) { return T.api.genre(c.cc, g).catch(function () { return []; }); })).then(function (rs) {
          if (!live(tk)) return;
          fill('g2', rs.map(function (r, i) { return T.ui.row(t('row.genre', { g: T.genreLabel(top[i]), c: cn }), r, { all: '#/genre/' + encodeURIComponent(top[i]) }); }).join(''));
          T.ui.syncPlaying();
        });
        T.ui.syncPlaying();
      }).catch(function () { if (live(tk)) { fill('hero', ''); fill('pop', T.ui.error(load)); fill('g2', ''); } });
      T.api.trending(c.cc).then(function (tr) {
        if (!live(tk)) return; fill('trend', T.ui.row(t('row.trending'), tr, { all: '#/list/trending' })); T.ui.syncPlaying();
      }).catch(function () { if (live(tk)) fill('trend', ''); });
      T.pod.top(c.cc).then(function (list) {
        if (!live(tk)) return; fill('ppop', T.ui.podRow(t('pod.popular', { c: cn }), list, { all: '#/podcasts' }));
      }).catch(function () { if (live(tk)) fill('ppop', ''); });
      newEpisodes(tk, function (eps) { if (live(tk)) { fill('pnew', T.ui.epRow(t('pod.new'), eps)); T.ui.syncPlaying(); } });
      if (region) T.api.region(c.cc, region).then(function (r) {
        if (!live(tk)) return;
        fill('local', r.length ? T.ui.row(t('row.local'), r, { sub: region, all: '#/browse/local/' + encodeURIComponent(region) }) : localPick()); T.ui.syncPlaying();
      }).catch(function () { if (live(tk)) fill('local', localPick()); });
    }
    load();
  };
  // laatste aflevering van elke gevolgde podcast, nieuwste eerst
  function newEpisodes(tk, cb) {
    var fs = T.store.follows().slice(0, 20);
    if (!fs.length) return;
    Promise.all(fs.map(function (f) { return T.pod.lookup(f.id).catch(function () { return null; }); })).then(function (rs) {
      if (!live(tk)) return;
      var eps = rs.filter(function (r) { return r && r.eps && r.eps[0]; }).map(function (r) { return r.eps[0]; })
        .sort(function (a, b) { return String(b.date).localeCompare(String(a.date)); });
      if (eps.length) cb(eps);
    });
  }
  function hero(arr) {
    var k = T.ui.reg(arr);
    return '<section class="hero" aria-roledescription="carousel" aria-label="' + esc(t('row.popular', { c: cname() })) + '" data-list="' + k + '"><div class="slides">' +
      arr.map(function (s, i) {
        var p = T.pal(s.name), logo = T.logoUrl(s.favicon);
        return '<div class="slide" data-sid="' + esc(s.id) + '" role="group" aria-roledescription="slide" aria-label="' + (i + 1) + ' / ' + arr.length + '"' + (i ? ' aria-hidden="true"' : '') + '>' +
          '<div class="bgart" style="--a:' + p[0] + ';--b:' + p[1] + '">' + (logo ? '<img src="' + esc(logo) + '" alt="" loading="lazy" referrerpolicy="no-referrer" onerror="this.remove()">' : '') + '</div>' +
          T.art(s) + '<div class="txt"><span class="kick">#' + (i + 1) + ' · ' + esc(t('row.popular', { c: cname() })) + '</span><h3>' + esc(s.name) + '</h3><p>' + esc(T.tagsLine(s, 3) || T.place(s)) + '</p>' +
          '<div class="acts"><button class="btn" type="button" data-act="play"' + (i ? ' tabindex="-1"' : '') + '>' + I('play') + '<span>' + esc(t('listen')) + '</span></button><a class="btn ghost" href="#/station/' + encodeURIComponent(s.id) + '"' + (i ? ' tabindex="-1"' : '') + '>' + I('info') + '<span>' + esc(t('info')) + '</span></a></div></div></div>';
      }).join('') + '</div><div class="dots">' + arr.map(function (s, i) { return '<button type="button" aria-label="' + (i + 1) + '" aria-current="' + (i === 0) + '" data-dot="' + i + '"></button>'; }).join('') + '</div></section>';
  }
  var carT = null;
  function startCarousel(root) {
    clearInterval(carT);
    if (!root) return;
    var slides = root.querySelector('.slides'), n = slides.children.length, i = 0, paused = false;
    function go(j) {
      i = (j + n) % n;
      slides.style.transform = 'translateX(' + (-i * 100) + '%)';
      root.querySelectorAll('[data-dot]').forEach(function (d, k) { d.setAttribute('aria-current', k === i); });
      Array.prototype.forEach.call(slides.children, function (sl, k) {
        sl.setAttribute('aria-hidden', k !== i);
        sl.querySelectorAll('a,button').forEach(function (b) { if (k === i) b.removeAttribute('tabindex'); else b.setAttribute('tabindex', '-1'); });
      });
    }
    root.addEventListener('click', function (e) { var d = e.target.closest('[data-dot]'); if (d) go(+d.getAttribute('data-dot')); });
    root.addEventListener('mouseenter', function () { paused = true; });
    root.addEventListener('mouseleave', function () { paused = false; });
    root.addEventListener('focusin', function () { paused = true; });
    root.addEventListener('focusout', function () { paused = false; });
    // vegen op aanraakschermen
    var x0 = null;
    root.addEventListener('touchstart', function (e) { x0 = e.touches[0].clientX; }, { passive: true });
    root.addEventListener('touchend', function (e) { if (x0 == null) return; var dx = e.changedTouches[0].clientX - x0; if (Math.abs(dx) > 40) go(i + (dx < 0 ? 1 : -1)); x0 = null; });
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) carT = setInterval(function () { if (!paused && document.contains(root) && !document.hidden) go(i + 1); else if (!document.contains(root)) clearInterval(carT); }, 6500);
  }

  // ================= lijsten "Alles" =================
  V.list = function (el, p) {
    var tk = token, c = country(), kind = p[0];
    var title = kind === 'trending' ? t('row.trending') : t('row.popular', { c: cname() });
    el.innerHTML = '<div class="pg">' + T.ui.head(title) + '<div id="res">' + T.ui.skGrid() + '</div></div>';
    function load() {
      (kind === 'trending' ? T.api.trending(c.cc) : T.api.popular(c.cc)).then(function (arr) {
        if (live(tk)) { el.querySelector('#res').innerHTML = arr.length ? T.ui.gridOf(arr) : T.ui.empty(t('empty')); T.ui.syncPlaying(); }
      }).catch(function () { if (live(tk)) el.querySelector('#res').innerHTML = T.ui.error(load); });
    }
    load();
  };

  // ================= genre =================
  V.genre = function (el, p) {
    var tk = token, c = country(), tag = decodeURIComponent(p[0] || 'pop');
    el.innerHTML = '<div class="pg">' + T.ui.head(T.genreLabel(tag)) + '<div id="res">' + T.ui.skGrid() + '</div></div>';
    function load() {
      T.api.genre(c.cc, tag).then(function (arr) {
        if (!live(tk)) return;
        if (arr.length >= 6) { el.querySelector('#res').innerHTML = T.ui.gridOf(arr); T.ui.syncPlaying(); return; }
        // weinig in eigen land → wereldwijd aanvullen
        return T.api.genre('', tag).then(function (w) {
          if (!live(tk)) return;
          var ids = {}; arr.forEach(function (s) { ids[s.id] = 1; });
          var all = arr.concat(w.filter(function (s) { return !ids[s.id]; }));
          el.querySelector('#res').innerHTML = all.length ? (arr.length < 6 ? '<p class="note">' + I('globe') + esc(t('genre.world', { c: cname() })) + '</p>' : '') + T.ui.gridOf(all) : T.ui.empty(t('empty'));
          T.ui.syncPlaying();
        });
      }).catch(function () { if (live(tk)) el.querySelector('#res').innerHTML = T.ui.error(load); });
    }
    load();
  };

  // ================= Bladeren =================
  function tile(href, key, icon, palI, big) {
    var p = T.PALETTE[palI];
    return '<a class="tile' + (big ? ' big' : '') + (big === 'full' ? ' full' : '') + '" href="' + href + '" style="--a:' + p[0] + ';--b:' + p[1] + '"><span class="ti">' + I(icon) + '</span><span class="tsm">' + I(icon) + '</span><b>' + esc(t('browse.' + key)) + '</b><small>' + esc(t('browse.' + key + '.sub')) + '</small></a>';
  }
  V.browse = function (el) {
    var region = T.store.region;
    el.innerHTML = '<div class="pg"><header class="top"><span class="sp"></span>' + T.ui.ccBtn() + '</header>' +
      '<h1 class="ptitle">' + esc(t('tab.browse')) + '</h1>' +
      '<div class="tiles">' +
      tile('#/podcasts', 'pod', 'pod', 1, true) +
      tile(region ? '#/browse/local/' + encodeURIComponent(region) : '#/browse/local', 'local', 'pin', 0, true) +
      tile('#/browse/music', 'music', 'music', 4) + tile('#/browse/news', 'news', 'mic', 5) + tile('#/genre/sports', 'sports', 'ball', 3) +
      tile('#/browse/language', 'lang', 'lang', 2) + tile('#/map', 'map', 'globe', 7, true) + tile('#/top100', 'top', 'trophy', 6, 'full') + '</div>' +
      '<section class="sec"><div class="sech"><h2>' + esc(t('row.genres')) + '</h2></div><div class="chips wrap">' + GENRES.map(chipHTML).join('') + '</div></section></div>';
  };
  V.local = function (el) {
    var tk = token, c = country(), cn = cname(), region = T.store.region;
    el.innerHTML = '<div class="pg">' + T.ui.head(t('browse.local')) + '<p class="psub" style="margin:-4px 0 14px">' + esc(t('local.regions', { c: cn + ' ' + T.flag(c.cc) })) + '</p>' +
      '<label class="field" style="margin-bottom:14px;max-width:560px"><span class="sr">' + esc(t('local.filter')) + '</span>' + I('search', 'lead') + '<input type="search" id="rq" placeholder="' + esc(t('local.filter')) + '" autocomplete="off"></label>' +
      '<div id="res">' + T.ui.skList(8) + '</div></div>';
    var all = [];
    function render() {
      var q = el.querySelector('#rq').value.trim().toLowerCase();
      var list = q ? all.filter(function (r) { return r.name.toLowerCase().indexOf(q) >= 0; }) : all;
      el.querySelector('#res').innerHTML = list.length ? '<div class="rows" style="max-width:720px">' + list.map(function (r) {
        var p = T.pal(r.name);
        return '<a href="#/browse/local/' + encodeURIComponent(r.name) + '"><span class="rico" style="--a:' + p[0] + ';--b:' + p[1] + '">' + I('pin') + '</span><span class="lab">' + esc(r.name) + (region === r.name ? '<small>' + esc(t('local.is')) + '</small>' : '') + '</span><span class="cnt">' + esc(T.stationsN(r.count)) + '</span>' + I('chev', 'chev') + '</a>';
      }).join('') + '</div>' : T.ui.empty(t('local.none'), 'pin');
    }
    function load() {
      T.api.states(c.name).then(function (rs) { if (!live(tk)) return; all = rs; render(); })
        .catch(function () { if (live(tk)) el.querySelector('#res').innerHTML = T.ui.error(load); });
    }
    el.querySelector('#rq').addEventListener('input', render);
    load();
  };
  V.region = function (el, p) {
    var tk = token, c = country(), name = decodeURIComponent(p[0] || '');
    function btn() {
      var mine = T.store.region === name;
      return '<button class="btn sm ' + (mine ? 'ghost' : '') + '" type="button" id="mk"' + (mine ? ' disabled' : '') + '>' + I(mine ? 'pin' : 'pin') + '<span>' + esc(mine ? t('local.is') : t('local.make')) + '</span></button>';
    }
    el.innerHTML = '<div class="pg">' + T.ui.head(name) + '<div style="margin:-2px 0 18px" id="mkw">' + btn() + '</div><div id="res">' + T.ui.skList(8) + '</div></div>';
    el.querySelector('#mkw').addEventListener('click', function (e) {
      if (!e.target.closest('#mk')) return;
      T.store.region = name; el.querySelector('#mkw').innerHTML = btn(); T.ui.toast(t('toast.region', { r: name }));
    });
    // laatst gekozen regio wordt de Lokaal-regio (SPEC §6)
    if (!T.store.region) T.store.region = name;
    function load() {
      T.api.region(c.cc, name).then(function (arr) {
        if (live(tk)) { el.querySelector('#res').innerHTML = arr.length ? T.ui.listOf(arr) : T.ui.empty(t('empty')); T.ui.syncPlaying(); }
      }).catch(function () { if (live(tk)) el.querySelector('#res').innerHTML = T.ui.error(load); });
    }
    load();
  };
  V.music = function (el) {
    el.innerHTML = '<div class="pg">' + T.ui.head(t('browse.music')) + '<div class="tiles">' + MUSIC.map(function (g) {
      var p = T.pal(g);
      return '<a class="tile" href="#/genre/' + encodeURIComponent(g) + '" style="--a:' + p[0] + ';--b:' + p[1] + '"><span class="ti">' + I('music') + '</span><b>' + esc(T.genreLabel(g)) + '</b></a>';
    }).join('') + '</div></div>';
  };
  V.news = function (el) {
    var tk = token, c = country();
    el.innerHTML = '<div class="pg">' + T.ui.head(t('browse.news')) + '<div id="n1">' + T.ui.skRow() + '</div><div id="n2">' + T.ui.skRow() + '</div></div>';
    function load() {
      ['news', 'talk'].forEach(function (g, i) {
        T.api.genre(c.cc, g).then(function (arr) {
          if (!live(tk)) return;
          el.querySelector('#n' + (i + 1)).innerHTML = arr.length ? '<section class="sec"><div class="sech"><h2>' + esc(t('news.' + g)) + '</h2><a class="all" href="#/genre/' + g + '">' + esc(t('all')) + '</a></div>' + T.ui.listOf(arr.slice(0, 12)) + '</section>' : '';
          T.ui.syncPlaying();
        }).catch(function () { if (live(tk)) el.querySelector('#n' + (i + 1)).innerHTML = i ? '' : T.ui.error(load); });
      });
    }
    load();
  };
  V.languages = function (el) {
    var tk = token;
    el.innerHTML = '<div class="pg">' + T.ui.head(t('browse.lang')) + '<div id="res">' + T.ui.skList(10) + '</div></div>';
    function load() {
      T.api.languages().then(function (ls) {
        if (!live(tk)) return;
        el.querySelector('#res').innerHTML = '<div class="rows" style="max-width:720px">' + ls.map(function (l) {
          var p = T.pal(l.name);
          return '<a href="#/browse/language/' + encodeURIComponent(l.name) + '"><span class="rico" style="--a:' + p[0] + ';--b:' + p[1] + '">' + I('lang') + '</span><span class="lab">' + esc(T.languageName(l.name, l.code)) + '</span><span class="cnt">' + esc(T.stationsN(l.count)) + '</span>' + I('chev', 'chev') + '</a>';
        }).join('') + '</div>';
      }).catch(function () { if (live(tk)) el.querySelector('#res').innerHTML = T.ui.error(load); });
    }
    load();
  };
  V.language = function (el, p) {
    var tk = token, name = decodeURIComponent(p[0] || '');
    var label = T.languageName(name, null);
    T.api.languages().then(function (ls) { var l = ls.find(function (x) { return x.name === name; }); if (l && live(tk)) { var h = el.querySelector('.top h1'); if (h) h.textContent = T.languageName(l.name, l.code); } }).catch(function () {});
    el.innerHTML = '<div class="pg">' + T.ui.head(label) + '<div id="res">' + T.ui.skGrid() + '</div></div>';
    function load() {
      T.api.language(name).then(function (arr) {
        if (live(tk)) { el.querySelector('#res').innerHTML = arr.length ? T.ui.gridOf(arr) : T.ui.empty(t('empty')); T.ui.syncPlaying(); }
      }).catch(function () { if (live(tk)) el.querySelector('#res').innerHTML = T.ui.error(load); });
    }
    load();
  };
  V.top100 = function (el) {
    var tk = token;
    el.innerHTML = '<div class="pg">' + T.ui.head(t('browse.top')) + '<div id="res">' + T.ui.skList(10) + '</div></div>';
    function load() {
      T.api.top100().then(function (arr) {
        if (live(tk)) { el.querySelector('#res').innerHTML = T.ui.listOf(arr, { ranked: true }); T.ui.syncPlaying(); }
      }).catch(function () { if (live(tk)) el.querySelector('#res').innerHTML = T.ui.error(load); });
    }
    load();
  };

  // ================= Zenderdetail =================
  V.station = function (el, p) {
    var tk = token, id = decodeURIComponent(p[0] || '');
    el.innerHTML = '<div class="pg">' + T.ui.head('') + '<div id="det"><div class="det"><div class="sk bigart" style="aspect-ratio:1;border-radius:22px"></div><div><div class="sk" style="height:36px;width:60%;border-radius:8px"></div><div class="sk" style="height:16px;width:40%;margin-top:12px;border-radius:6px"></div></div></div></div></div>';
    function load() {
      T.api.station(id).then(function (s) {
        if (!live(tk)) return;
        if (!s) { el.querySelector('#det').innerHTML = T.ui.empty(t('detail.nf'), 'alert'); return; }
        render(s);
      }).catch(function () {
        // offline: misschien staat hij in favorieten/recent
        var s = T.store.favorites().concat(T.store.recents()).find(function (x) { return x.id === id; });
        if (s && live(tk)) render(s); else if (live(tk)) el.querySelector('#det').innerHTML = T.ui.error(load);
      });
    }
    function render(s) {
      var k = T.ui.reg([s]);
      var fav = T.store.isFav(s.id), active = T.player.isActive(s.id);
      var facts = [
        [t('detail.codec'), s.codec || '—'], [t('detail.bitrate'), s.bitrate ? t('kbps', { n: s.bitrate }) : '—'],
        [t('detail.lang'), s.language ? T.languageName(s.language) : '—'], [t('detail.votes'), T.num(s.votes)],
        [t('detail.clicks'), T.num(s.clicks)], [t('detail.hls'), s.hls ? t('yes') : t('no')]
      ];
      document.title = s.name + ' · Tunr';
      el.querySelector('#det').innerHTML = '<div class="det" data-list="' + k + '"><div data-sid="' + esc(s.id) + '" class="' + (T.player.isCurrent(s.id) ? 'is-playing' : '') + '">' + T.art(s, 'bigart') + '</div>' +
        '<div><div class="head" data-sid="' + esc(s.id) + '"><h1>' + esc(s.name) + '</h1><p class="place">' + esc(T.place(s)) + '</p>' +
        '<div class="acts"><button class="btn playbig" type="button" data-act="play" data-detail-play="' + esc(s.id) + '">' + I(active ? 'pause' : 'play') + '<span>' + esc(active ? t('pause') : t('play')) + '</span></button>' +
        '<button class="rbtn" type="button" data-act="fav" data-detail-fav="' + esc(s.id) + '" aria-pressed="' + fav + '" aria-label="' + esc(t('detail.fav')) + '">' + I(fav ? 'heartf' : 'heart') + '</button>' +
        '<button class="rbtn" type="button" data-act="share" aria-label="' + esc(t('detail.share')) + '">' + I('share') + '</button>' +
        (s.homepage && /^https?:/i.test(s.homepage) ? '<a class="rbtn" href="' + esc(s.homepage) + '" target="_blank" rel="noopener noreferrer" aria-label="' + esc(t('detail.website')) + '">' + I('ext') + '</a>' : '') + '</div></div>' +
        '<div id="np" style="margin-top:22px"></div>' +
        (s.tags.length ? '<div class="chips wrap" style="margin-top:22px">' + s.tags.map(chipHTML).join('') + '</div>' : '') +
        '<div class="facts" style="margin-top:22px">' + facts.map(function (f) { return '<div class="fact"><small>' + esc(f[0]) + '</small><b>' + esc(f[1]) + '</b></div>'; }).join('') + '</div></div></div>' +
        '<div id="sim"></div>';
      renderNP(s);
      T.ui.detailRefresh = function () { renderNP(s); };
      if (s.tags[0] && s.cc) T.api.genre(s.cc, s.tags[0]).then(function (arr) {
        if (!live(tk)) return;
        arr = arr.filter(function (x) { return x.id !== s.id; });
        el.querySelector('#sim').innerHTML = T.ui.row(t('detail.similar'), arr, { all: '#/genre/' + encodeURIComponent(s.tags[0]) });
        T.ui.syncPlaying();
      }).catch(function () {});
    }
    function renderNP(s) {
      var n = el.querySelector('#np'); if (!n) return;
      n.innerHTML = T.player.isCurrent(s.id) && T.player.state === 'playing' ? '<div class="npcard is-playing">' + T.art(s, 'sm') + '<div><span class="livepill">' + esc(t('player.live')) + '</span><b style="margin-top:6px">' + esc(t('detail.np')) + '</b><small>' + esc(s.name) + '</small></div><span class="eq" style="margin-left:auto;height:18px"><i></i><i></i><i></i><i></i></span></div>' : '';
    }
    load();
  };

  // ================= Zoeken =================
  V.search = function (el, p, q0, m0) {
    var tk = token, c = country();
    var world = T.store.searchWorld;
    if (m0 === 'pod' || m0 === 'st') T.store.searchMode = m0;
    var mode = T.store.searchMode === 'pod' ? 'pod' : 'st';
    el.innerHTML = '<div class="pg"><header class="top"><h1 class="ptitle" style="margin:0;font-size:clamp(28px,4.4vw,40px)">' + esc(t('tab.search')) + '</h1></header>' +
      '<div class="seg segm" role="group" aria-label="' + esc(t('tab.search')) + '" style="margin:0 0 12px"><button type="button" data-m="st" aria-pressed="' + (mode === 'st') + '">' + I('radio', 'ic') + esc(t('seg.stations')) + '</button><button type="button" data-m="pod" aria-pressed="' + (mode === 'pod') + '">' + I('pod', 'ic') + esc(t('seg.podcasts')) + '</button></div>' +
      '<label class="field" style="max-width:720px"><span class="sr">' + esc(t('tab.search')) + '</span>' + I('search', 'lead') + '<input type="search" id="sq" placeholder="' + esc(mode === 'pod' ? t('pod.ph') : t('search.ph')) + '" autocomplete="off" spellcheck="false" enterkeyhint="search"><button class="clr" type="button" id="sclr" hidden aria-label="' + esc(t('search.clear')) + '">' + I('x') + '</button></label>' +
      '<div style="margin-top:12px" id="wseg"' + (mode === 'pod' ? ' hidden' : '') + '><div class="seg segw" role="group" aria-label="' + esc(t('tab.search')) + '"><button type="button" data-w="0" aria-pressed="' + !world + '">' + T.flag(c.cc) + ' ' + esc(cname()) + '</button><button type="button" data-w="1" aria-pressed="' + world + '">' + I('globe', 'ic') + esc(t('search.world')) + '</button></div></div>' +
      '<div id="sres" style="margin-top:8px"></div></div>';
    var input = el.querySelector('#sq'), res = el.querySelector('#sres'), clr = el.querySelector('#sclr');
    var timer = null, seq = 0;
    function idle() {
      var rec = T.store.searches();
      if (mode === 'pod') {
        res.innerHTML = '<section class="sec"><div class="sech"><h2>' + esc(t('pod.genres')) + '</h2></div>' + podGenreTiles() + '</section>' +
          (rec.length ? recentHTML(rec) : '');
        return;
      }
      res.innerHTML = '<section class="sec"><div class="sech"><h2>' + esc(t('search.genres')) + '</h2></div><div class="chips wrap">' + GENRES.map(chipHTML).join('') + '</div></section>' +
        (rec.length ? recentHTML(rec) : '');
    }
    function recentHTML(rec) {
      return '<section class="sec"><div class="sech"><h2>' + esc(t('search.recent')) + '</h2><button class="all" type="button" id="rclr">' + esc(t('search.clear')) + '</button></div><div class="rows" style="max-width:720px">' +
        rec.map(function (q) { return '<button type="button" data-q="' + esc(q) + '">' + I('clock', 'ic') + '<span class="lab">' + esc(q) + '</span>' + I('chev', 'chev') + '</button>'; }).join('') + '</div></section>';
    }
    function run(q) {
      var my = ++seq;
      res.innerHTML = '<div style="margin-top:16px">' + T.ui.skList(6) + '</div>';
      if (mode === 'pod') {
        T.pod.search(q, c.cc).then(function (arr) {
          if (my !== seq || !live(tk)) return;
          T.store.addSearch(q);
          res.innerHTML = arr.length ? '<section class="sec" style="margin-top:18px"><div class="sech"><h2>' + esc(t('search.results')) + '<small>' + esc(t('pod.results', { n: T.num(arr.length) })) + '</small></h2></div>' + T.ui.podList(arr) + '</section>' : T.ui.empty(t('pod.none', { q: q }), 'pod');
        }).catch(function () { if (my === seq && live(tk)) res.innerHTML = T.ui.error(function () { run(q); }); });
        return;
      }
      T.api.search(q, world ? '' : c.cc).then(function (arr) {
        if (my !== seq || !live(tk)) return;
        T.store.addSearch(q);
        res.innerHTML = arr.length ? '<section class="sec" style="margin-top:18px"><div class="sech"><h2>' + esc(t('search.results')) + '<small>' + esc(T.stationsN(arr.length)) + '</small></h2></div>' + T.ui.listOf(arr) + '</section>' : T.ui.empty(t('search.none', { q: q }), 'search');
        T.ui.syncPlaying();
      }).catch(function () { if (my === seq && live(tk)) res.innerHTML = T.ui.error(function () { run(q); }); });
    }
    function onInput() {
      var q = input.value.trim();
      clr.hidden = !input.value;
      clearTimeout(timer);
      history.replaceState(history.state, '', '#/search' + (q ? '?q=' + encodeURIComponent(q) + (mode === 'pod' ? '&m=pod' : '') : (mode === 'pod' ? '?m=pod' : '')));
      if (q.length < 2) { seq++; idle(); return; }
      timer = setTimeout(function () { run(q); }, 350);
    }
    input.addEventListener('input', onInput);
    input.addEventListener('keydown', function (e) { if (e.key === 'Enter') { clearTimeout(timer); var q = input.value.trim(); if (q.length >= 2) run(q); input.blur(); } });
    clr.addEventListener('click', function () { input.value = ''; onInput(); input.focus(); });
    el.querySelector('.segm').addEventListener('click', function (e) {
      var b = e.target.closest('[data-m]'); if (!b) return;
      mode = b.getAttribute('data-m'); T.store.searchMode = mode;
      el.querySelectorAll('.segm button').forEach(function (x) { x.setAttribute('aria-pressed', x === b); });
      el.querySelector('#wseg').hidden = mode === 'pod';
      input.placeholder = mode === 'pod' ? t('pod.ph') : t('search.ph');
      var q = input.value.trim(); if (q.length >= 2) run(q); else { seq++; idle(); }
    });
    el.querySelector('.segw').addEventListener('click', function (e) {
      var b = e.target.closest('[data-w]'); if (!b) return;
      world = b.getAttribute('data-w') === '1'; T.store.searchWorld = world;
      el.querySelectorAll('.segw button').forEach(function (x) { x.setAttribute('aria-pressed', x === b); });
      var q = input.value.trim(); if (q.length >= 2) run(q);
    });
    res.addEventListener('click', function (e) {
      var r = e.target.closest('[data-q]'); if (r) { input.value = r.getAttribute('data-q'); onInput(); clearTimeout(timer); run(input.value.trim()); return; }
      if (e.target.closest('#rclr')) { T.store.clearSearches(); idle(); }
    });
    if (q0) { input.value = q0; clr.hidden = false; run(q0); } else idle();
    if (window.innerWidth > 700 || !q0) setTimeout(function () { input.focus({ preventScroll: true }); }, 60);
  };

  // ================= Bibliotheek =================
  V.library = function (el, p, q) {
    var seg = q === 'recent' ? 'recent' : q === 'podcasts' ? 'podcasts' : 'fav';
    function render() {
      var favs = T.store.favorites(), rec = T.store.recents();
      var body;
      if (seg === 'fav') {
        body = favs.length ? T.ui.gridOf(favs).replace(/<div class="card/g, '<div class="card lib') : '<div class="msg"><span class="empty-heart"><i></i><i></i><i></i>' + I('heartf') + '</span><b>' + esc(t('lib.fav')) + '</b><span>' + esc(t('lib.empty')) + '</span></div>';
      } else if (seg === 'podcasts') {
        var fol = T.store.follows(), cont = T.store.continueEps();
        body = (cont.length ? T.ui.epRow(t('pod.continue'), cont) : '') +
          (fol.length ? '<section class="sec"><div class="sech"><h2>' + esc(t('seg.podcasts')) + '<small>' + esc(String(fol.length)) + '</small></h2><a class="all" href="#/podcasts">' + esc(t('pod.lib.find')) + '</a></div>' + T.ui.podGrid(fol) + '</section>'
            : '<div class="msg"><span class="mi">' + I('pod') + '</span><b>' + esc(t('seg.podcasts')) + '</b><span>' + esc(t('pod.lib.empty')) + '</span><a class="btn" href="#/podcasts">' + esc(t('pod.lib.find')) + '</a></div>');
      } else {
        body = rec.length ? '<div style="display:flex;justify-content:flex-end;margin-bottom:8px"><button class="btn sm ghost" type="button" id="clrR">' + I('trash') + '<span>' + esc(t('lib.clear')) + '</span></button></div>' + T.ui.listOf(rec) : '<div class="msg"><span class="mi">' + I('clock') + '</span><span>' + esc(t('lib.empty.r')) + '</span></div>';
      }
      el.innerHTML = '<div class="pg"><header class="top"><h1 class="ptitle" style="margin:0;font-size:clamp(28px,4.4vw,40px)">' + esc(t('tab.library')) + '</h1><span class="sp"></span>' + T.ui.gearBtn() + '</header>' +
        '<div class="seg" role="tablist" style="margin:4px 0 22px"><button type="button" role="tab" data-seg="fav" aria-pressed="' + (seg === 'fav') + '" aria-selected="' + (seg === 'fav') + '">' + esc(t('lib.fav')) + (favs.length ? ' · ' + favs.length : '') + '</button><button type="button" role="tab" data-seg="podcasts" aria-pressed="' + (seg === 'podcasts') + '" aria-selected="' + (seg === 'podcasts') + '">' + esc(t('seg.podcasts')) + (T.store.follows().length ? ' · ' + T.store.follows().length : '') + '</button><button type="button" role="tab" data-seg="recent" aria-pressed="' + (seg === 'recent') + '" aria-selected="' + (seg === 'recent') + '">' + esc(t('lib.recent')) + '</button></div>' +
        body + '</div>';
      T.ui.syncPlaying();
    }
    el.onclick = function (e) {
      var b = e.target.closest('[data-seg]');
      if (b) { seg = b.getAttribute('data-seg'); history.replaceState(history.state, '', '#/library' + (seg !== 'fav' ? '?seg=' + seg : '')); render(); return; }
      if (e.target.closest('#clrR')) T.ui.confirm(t('set.confirmR'), t('lib.clear'), function () { T.store.clearRecents(); render(); });
    };
    // verversen van favorieten (namen/logo's/streams kunnen veranderen); stil op de achtergrond
    var favs = T.store.favorites();
    if (favs.length && !V._favRefreshed) {
      V._favRefreshed = true;
      T.api.byUuids(favs.slice(0, 100).map(function (s) { return s.id; })).then(function (fresh) { if (fresh.length) T.store.replaceFavs(fresh); }).catch(function () {});
    }
    T.ui.libRender = render;
    render();
  };

  // ================= Podcasts (SPEC §8) =================
  function podGenreTiles() {
    return '<div class="tiles ptiles">' + T.pod.GENRES.map(function (g, i) {
      var p = T.PALETTE[(i + 1) % T.PALETTE.length];
      return '<a class="tile sm" href="#/podcasts/genre/' + g + '" style="--a:' + p[0] + ';--b:' + p[1] + '"><span class="ti">' + I('pod') + '</span><b>' + esc(T.podGenre(g)) + '</b></a>';
    }).join('') + '</div>';
  }
  V.podcasts = function (el) {
    var tk = token, c = country(), cn = cname();
    el.innerHTML = '<div class="pg"><header class="top"><button class="iconbtn" type="button" data-act="back" aria-label="' + esc(t('back')) + '">' + I('back') + '</button><span class="sp"></span>' + T.ui.ccBtn() + '</header>' +
      '<h1 class="ptitle">' + esc(t('pod.title')) + '</h1>' +
      '<a class="field fake" href="#/search?m=pod" style="max-width:720px;margin-top:12px">' + I('search', 'lead') + '<span>' + esc(t('pod.search')) + '</span></a>' +
      '<div id="pcont"></div>' +
      '<div class="pgrid2"><section class="sec"><div class="sech"><h2>' + esc(t('pod.top', { c: cn })) + '</h2></div><div id="ptop">' + T.ui.skList(10) + '</div></section>' +
      '<section class="sec" id="pgen"><div class="sech"><h2>' + esc(t('pod.genres')) + '</h2></div>' + podGenreTiles() + '</section></div></div>';
    var cont = T.store.continueEps();
    if (cont.length) el.querySelector('#pcont').innerHTML = T.ui.epRow(t('pod.continue'), cont);
    function load() {
      T.pod.top(c.cc).then(function (list) {
        if (!live(tk)) return;
        el.querySelector('#ptop').innerHTML = list.length ? T.ui.podList(list.slice(0, 50), { ranked: true }) : T.ui.empty(t('empty'), 'pod');
      }).catch(function () { if (live(tk)) el.querySelector('#ptop').innerHTML = T.ui.error(load); });
    }
    load();
    // genres: één proefverzoek; lukt de genrebron niet, dan de tegels netjes weglaten
    T.pod.genre(c.cc, T.pod.GENRES[0]).then(function (l) { if (live(tk) && !l.length) hideG(); }).catch(function () { if (live(tk)) hideG(); });
    function hideG() { var g = el.querySelector('#pgen'); if (g) g.hidden = true; }
    T.ui.syncPlaying();
  };
  V.podGenre = function (el, p) {
    var tk = token, c = country(), gid = String(p[0] || '');
    el.innerHTML = '<div class="pg">' + T.ui.head(T.podGenre(gid) || t('pod.title')) + '<div id="res">' + T.ui.skList(10) + '</div></div>';
    function load() {
      T.pod.genre(c.cc, gid).then(function (list) {
        if (!live(tk)) return;
        el.querySelector('#res').innerHTML = list.length ? T.ui.podList(list, { ranked: true }) : T.ui.empty(t('pod.genreFail'), 'pod');
      }).catch(function () { if (live(tk)) el.querySelector('#res').innerHTML = T.ui.empty(t('pod.genreFail'), 'pod'); });
    }
    load();
  };
  // podcastpagina
  V.podcast = function (el, p) {
    var tk = token, id = decodeURIComponent(p[0] || ''), sort = T.store.podSort;
    var k0 = T.pod.known[id];
    el.innerHTML = '<div class="pg">' + T.ui.head('') + '<div id="pd">' + podHead(k0 || { id: id, name: '' }, null, true) + '<div style="margin-top:24px">' + T.ui.skList(6) + '</div></div></div>';
    var data = null;
    function load() {
      T.pod.lookup(id).then(function (r) {
        if (!live(tk)) return;
        if (!r) { el.querySelector('#pd').innerHTML = T.ui.empty(t('pod.nf'), 'alert'); return; }
        data = r; render();
        T.pod.describe(r.p).then(function (d) {
          if (!live(tk) || !d) return; r.p.desc = d;
          var n = el.querySelector('#pdesc'); if (n) { n.innerHTML = descHTML(d); }
        });
      }).catch(function () { if (live(tk)) el.querySelector('#pd').innerHTML = T.ui.error(load); });
    }
    function sorted() { var a = data.eps.slice(); if (sort === 'old') a.reverse(); return a; }
    function render() {
      var pp = data.p;
      document.title = pp.name + ' · Tunr';
      el.querySelector('#pd').innerHTML = podHead(pp, data.eps) +
        '<section class="sec"><div class="sech"><h2>' + esc(t('pod.episodes')) + '<small>' + esc(T.epsN(data.eps.length)) + '</small></h2>' +
        '<div class="seg sm" role="group" aria-label="' + esc(t('pod.episodes')) + '"><button type="button" data-sort="new" aria-pressed="' + (sort === 'new') + '">' + esc(t('pod.sortNew')) + '</button><button type="button" data-sort="old" aria-pressed="' + (sort === 'old') + '">' + esc(t('pod.sortOld')) + '</button></div></div>' +
        (data.eps.length ? T.ui.epList(sorted()) : T.ui.empty(t('pod.noeps'), 'pod')) + '</section>';
      T.ui.syncPlaying();
    }
    el.onclick = function (e) {
      var s = e.target.closest('[data-sort]');
      if (s && data) { sort = s.getAttribute('data-sort'); T.store.podSort = sort; render(); return; }
      if (e.target.closest('[data-act="follow"]') && data) {
        var on = T.store.toggleFollow(data.p);
        T.ui.toast(t(on ? 'pod.toast.follow' : 'pod.toast.unfollow', { n: data.p.name }));
        var b = el.querySelector('[data-act="follow"]'); if (b) b.outerHTML = followBtn(data.p.id);
        return;
      }
      if (e.target.closest('[data-act="latest"]') && data && data.eps[0]) T.player.play(data.eps[0], data.eps);
      var m = e.target.closest('[data-act="dmore"]');
      if (m) { var d = el.querySelector('.pdesc'); var o = d.classList.toggle('open'); m.textContent = t(o ? 'pod.less' : 'pod.more'); }
    };
    T.ui.podRefresh = function () { if (data) render(); };
    load();
  };
  function followBtn(id) {
    var on = T.store.isFollowing(id);
    return '<button class="btn ' + (on ? 'ghost' : 'white') + '" type="button" data-act="follow" aria-pressed="' + on + '">' + I(on ? 'check' : 'plus') + '<span>' + esc(t(on ? 'pod.following' : 'pod.follow')) + '</span></button>';
  }
  function descHTML(d) {
    return '<p class="pdesc">' + esc(d) + '</p>' + (d.length > 220 ? '<button class="linkbtn" type="button" data-act="dmore">' + esc(t('pod.more')) + '</button>' : '');
  }
  function podHead(pp, eps, sk) {
    var meta = [pp.genre, pp.count ? T.epsN(pp.count) : (eps ? T.epsN(eps.length) : '')].filter(Boolean).join(' · ');
    var latest = eps && eps[0];
    return '<div class="det pdet"><div>' + T.podArt(pp, 'bigart') + '</div><div><div class="head">' +
      (sk && !pp.name ? '<div class="sk" style="height:36px;width:60%;border-radius:8px"></div>' : '<h1>' + esc(pp.name) + '</h1>') +
      '<p class="place maker">' + esc(pp.artist || '') + '</p>' + (meta ? '<p class="pmeta">' + esc(meta) + '</p>' : '') +
      (eps ? '<div class="acts">' + (latest ? '<button class="btn playbig" type="button" data-act="latest" data-ep-play="' + esc(latest.id) + '" data-label="' + esc(t('pod.playLatest')) + '">' + I('play') + '<span>' + esc(t('pod.playLatest')) + '</span></button>' : '') + followBtn(pp.id) +
        '<button class="rbtn" type="button" data-act="podshare" aria-label="' + esc(t('detail.share')) + '">' + I('share') + '</button></div>' : '') + '</div>' +
      '<div id="pdesc">' + (pp.desc ? descHTML(pp.desc) : '') + '</div></div></div>';
  }
  // afleveringspagina
  V.episode = function (el, p) {
    var tk = token, pid = decodeURIComponent(p[0] || ''), eid = decodeURIComponent(p[1] || '');
    el.innerHTML = '<div class="pg">' + T.ui.head('') + '<div id="ed">' + T.ui.skList(4) + '</div></div>';
    function load() {
      T.pod.lookup(pid).then(function (r) {
        if (!live(tk)) return;
        var e = r && r.eps.find(function (x) { return x.id === eid; });
        if (!e) { var ps = T.store.pos(eid); e = ps && ps.ep; }
        if (!e) { el.querySelector('#ed').innerHTML = T.ui.empty(t('pod.epnf'), 'alert'); return; }
        render(e, r ? r.eps : [e], r && r.p);
      }).catch(function () {
        var ps = T.store.pos(eid);
        if (ps && ps.ep && live(tk)) render(ps.ep, [ps.ep], null); else if (live(tk)) el.querySelector('#ed').innerHTML = T.ui.error(load);
      });
    }
    function render(e, list, pp) {
      document.title = e.title + ' · Tunr';
      var k = T.ui.reg(list), pr = T.ui.epProg(e), active = T.player.isActive(e.id);
      var text = String(e.desc || e.short || '');
      // beschrijving is soms HTML: alleen tekst, met alinea's
      var tmp = document.createElement('div'); tmp.innerHTML = text.replace(/<(br|\/p|\/div|\/li)\s*\/?>/gi, '\n');
      var plain = (tmp.textContent || '').split(/\n{1,}/).map(function (x) { return x.trim(); }).filter(Boolean);
      el.querySelector('#ed').innerHTML = '<div class="det pdet epdet" data-list="' + k + '"><div data-eid="' + esc(e.id) + '">' + T.podArt({ name: e.pname, art: e.art }, 'bigart') + '</div><div><div class="head" data-eid="' + esc(e.id) + '">' +
        '<a class="kick" href="#/podcast/' + encodeURIComponent(e.pid) + '">' + esc(e.pname || (pp && pp.name) || t('pod.show')) + '</a><h1 class="eph">' + esc(e.title) + '</h1>' +
        '<p class="pmeta">' + esc([T.date(e.date), e.dur ? T.dur(e.dur) : '', pr.done ? t('pod.played') : pr.pct ? t('pod.left', { t: T.dur(pr.left) }) : ''].filter(Boolean).join(' · ')) + '</p>' +
        (pr.pct > 0 && !pr.done ? '<span class="epbar wide"><i style="width:' + pr.pct.toFixed(1) + '%"></i></span>' : '') +
        '<div class="acts"><button class="btn playbig" type="button" data-act="eplay" data-ep-play="' + esc(e.id) + '">' + I(active ? 'pause' : 'play') + '<span>' + esc(active ? t('pause') : t('play')) + '</span></button>' +
        '<a class="btn ghost" href="#/podcast/' + encodeURIComponent(e.pid) + '">' + I('pod') + '<span>' + esc(t('pod.show')) + '</span></a>' +
        '<button class="rbtn" type="button" data-act="epshare" aria-label="' + esc(t('detail.share')) + '">' + I('share') + '</button></div></div>' +
        '<div class="eptext">' + plain.map(function (x) { return '<p>' + esc(x) + '</p>'; }).join('') + '</div></div></div>';
      el.onclick = function (ev) { if (ev.target.closest('[data-act="epshare"]')) T.ui.share(e); };
      T.ui.syncPlaying();
    }
    load();
  };

  // ================= Instellingen =================
  V.settings = function (el) {
    function render() {
      var c = T.store.country, ls = T.store.langSetting, intro = T.store.intro;
      el.innerHTML = '<div class="pg" style="max-width:760px;margin-left:0">' + T.ui.head(t('tab.settings'), { noBack: window.innerWidth >= 900 }) +
        '<section class="sec" style="margin-top:6px"><div class="rows">' +
        '<a href="#/country"><span class="rico">' + I('globe') + '</span><span class="lab">' + esc(t('set.country')) + '</span><span class="val">' + (c ? T.flag(c.cc) + ' ' + esc(T.countryName(c.cc, c.name)) : '') + '</span>' + I('chev', 'chev') + '</a>' +
        '<div class="row"><span class="rico" style="--a:#6366F1;--b:#06B6D4">' + I('lang') + '</span><span class="lab">' + esc(t('set.lang')) + '</span><span class="seg" role="group" aria-label="' + esc(t('set.lang')) + '">' +
        [['system', t('set.system')], ['nl', 'Nederlands'], ['en', 'English']].map(function (o) { return '<button type="button" data-lang="' + o[0] + '" aria-pressed="' + (ls === o[0]) + '">' + esc(o[1]) + '</button>'; }).join('') + '</span></div>' +
        '</div></section>' +
        '<section class="sec"><div class="sech"><h2>' + esc(t('set.data')) + '</h2></div><div class="rows">' +
        '<button type="button" id="cr"><span class="rico" style="--a:#14B8A6;--b:#3B82F6">' + I('clock') + '</span><span class="lab danger">' + esc(t('set.clearR')) + '</span><span class="cnt">' + T.store.recents().length + '</span></button>' +
        '<button type="button" id="cf"><span class="rico" style="--a:#F43F5E;--b:#FB923C">' + I('heart') + '</span><span class="lab danger">' + esc(t('set.clearF')) + '</span><span class="cnt">' + T.store.favorites().length + '</span></button>' +
        '</div></section>' +
        '<section class="sec"><div class="sech"><h2>' + esc(t('set.privacyH')) + '</h2></div><div class="rows">' +
        '<button type="button" id="st" role="switch" aria-checked="' + T.store.shareStats + '"><span class="rico" style="--a:#8B5CF6;--b:#EC4899">' + I('info') + '</span><span class="lab">' + esc(t('set.stats')) + '<small>' + esc(t('set.stats.p')) + '</small></span><span class="switch" aria-hidden="true"></span></button>' +
        '</div></section>' +
        '<section class="sec"><div class="sech"><h2>' + esc(t('set.about')) + '</h2></div><div class="rows">' +
        '<div class="row"><span class="rico">' + I('radio') + '</span><span class="lab">Tunr</span><span class="val">' + esc(t('set.version')) + ' ' + esc(window.TUNR.version) + '</span></div>' +
        '<a href="../"><span class="lab">' + esc(t('set.site')) + '</span>' + I('chev', 'chev') + '</a>' +
        '<a href="../privacy/"><span class="lab">' + esc(t('set.privacy')) + '</span>' + I('chev', 'chev') + '</a>' +
        '<a href="../voorwaarden/"><span class="lab">' + esc(t('set.terms')) + '</span>' + I('chev', 'chev') + '</a>' +
        '<a href="' + esc(window.TUNR.repo) + '" target="_blank" rel="noopener"><span class="lab">' + esc(t('set.source')) + '</span>' + I('ext', 'chev') + '</a>' +
        '<a href="https://www.radio-browser.info" target="_blank" rel="noopener"><span class="rico" style="--a:#10B981;--b:#84CC16">' + I('wave') + '</span><span class="lab">' + esc(t('set.credit')) + '<small>' + esc(t('set.credit.p')) + '</small></span>' + I('ext', 'chev') + '</a>' +
        '</div></section></div>';
    }
    el.onclick = function (e) {
      var l = e.target.closest('[data-lang]');
      if (l) { T.store.lang = l.getAttribute('data-lang'); return; } // store-event tekent alles opnieuw
      if (e.target.closest('#st')) {
        T.store.shareStats = !T.store.shareStats;
        if (T.store.shareStats && T.stats) T.stats.pingIfDue();
        render(); return;
      }
      if (e.target.closest('#cr')) T.ui.confirm(t('set.confirmR'), t('lib.clear'), function () { T.store.clearRecents(); T.ui.toast(t('set.done')); render(); });
      if (e.target.closest('#cf')) T.ui.confirm(t('set.confirmF'), t('lib.clear'), function () { T.store.clearFavs(); T.ui.toast(t('set.done')); render(); });
    };
    render();
  };
})();

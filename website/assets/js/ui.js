// Tunr webspeler: gedeelde UI — iconen, kaarten/rijen/lijsten, navigatie (tabbalk + zijbalk), miniplayer,
// volledige speler, sheets (slaaptimer, bevestigen), toast en delen.
(function () {
  var T = window.T = window.T || {};
  var t = function (k, v) { return T.t(k, v); }, esc = T.esc;

  // ---------- iconen (24×24, currentColor) ----------
  var P = {
    radio: '<path d="M5 9a9.5 9.5 0 0 1 14 0M8 12.2a5.2 5.2 0 0 1 8 0" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/><circle cx="12" cy="16" r="2.2" fill="currentColor"/>',
    grid: '<rect x="3.5" y="3.5" width="7" height="7" rx="2" stroke="currentColor" stroke-width="2" fill="none"/><rect x="13.5" y="3.5" width="7" height="7" rx="2" stroke="currentColor" stroke-width="2" fill="none"/><rect x="3.5" y="13.5" width="7" height="7" rx="2" stroke="currentColor" stroke-width="2" fill="none"/><rect x="13.5" y="13.5" width="7" height="7" rx="2" stroke="currentColor" stroke-width="2" fill="none"/>',
    globe: '<circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2" fill="none"/><path d="M3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9s-1.2 6.4-3.7 9M12 3C9.5 5.6 8.3 8.6 8.3 12s1.2 6.4 3.7 9" stroke="currentColor" stroke-width="2" fill="none"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5" stroke="currentColor" stroke-width="2.2" fill="none"/><path d="m15.5 15.5 5 5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>',
    library: '<path d="M4.5 4v16M9 4v16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="m13.2 4.6 3.6-1 4 15.6-3.6 1z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/>',
    gear: '<path d="M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4z" stroke="currentColor" stroke-width="2" fill="none"/><path d="M19.4 13.5a7.7 7.7 0 0 0 0-3l2-1.6-2-3.4-2.4.9a7.5 7.5 0 0 0-2.6-1.5L14 2.4h-4l-.4 2.5A7.5 7.5 0 0 0 7 6.4l-2.4-.9-2 3.4 2 1.6a7.7 7.7 0 0 0 0 3l-2 1.6 2 3.4 2.4-.9a7.5 7.5 0 0 0 2.6 1.5l.4 2.5h4l.4-2.5a7.5 7.5 0 0 0 2.6-1.5l2.4.9 2-3.4z" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linejoin="round"/>',
    play: '<path d="M8 5.6v12.8c0 .8.9 1.3 1.6.8l10-6.4c.6-.4.6-1.3 0-1.7l-10-6.3C8.9 4.3 8 4.8 8 5.6z" fill="currentColor"/>',
    pause: '<rect x="6.5" y="5" width="4" height="14" rx="1.2" fill="currentColor"/><rect x="13.5" y="5" width="4" height="14" rx="1.2" fill="currentColor"/>',
    prev: '<path d="M6 5.5h2.2v13H6zM19 6.4v11.2c0 .8-.9 1.3-1.6.8L9.6 13a1.2 1.2 0 0 1 0-2l7.8-5.4c.7-.5 1.6 0 1.6.8z" fill="currentColor"/>',
    next: '<path d="M18 5.5h-2.2v13H18zM5 6.4v11.2c0 .8.9 1.3 1.6.8l7.8-5.4a1.2 1.2 0 0 0 0-2L6.6 5.6C5.9 5.1 5 5.6 5 6.4z" fill="currentColor"/>',
    heart: '<path d="M12 20.3s-7.4-4.5-9.1-9.1C1.7 8 3.7 4.8 7 4.8c2 0 3.5 1.1 5 2.9 1.5-1.8 3-2.9 5-2.9 3.3 0 5.3 3.2 4.1 6.4-1.7 4.6-9.1 9.1-9.1 9.1z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/>',
    heartf: '<path d="M12 20.3s-7.4-4.5-9.1-9.1C1.7 8 3.7 4.8 7 4.8c2 0 3.5 1.1 5 2.9 1.5-1.8 3-2.9 5-2.9 3.3 0 5.3 3.2 4.1 6.4-1.7 4.6-9.1 9.1-9.1 9.1z" fill="currentColor"/>',
    share: '<path d="M12 3v12M7.5 7.5 12 3l4.5 4.5" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 12v6.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V12" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/>',
    moon: '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/>',
    info: '<circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2" fill="none"/><path d="M12 11v6" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="7.6" r="1.3" fill="currentColor"/>',
    web: '<circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2" fill="none"/><path d="M3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9s-1.2 6.4-3.7 9M12 3C9.5 5.6 8.3 8.6 8.3 12s1.2 6.4 3.7 9" stroke="currentColor" stroke-width="2" fill="none"/>',
    back: '<path d="M15 5l-7 7 7 7" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    chev: '<path d="M9 5l7 7-7 7" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    down: '<path d="M5 9l7 7 7-7" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    x: '<path d="M6 6l12 12M18 6 6 18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>',
    dice: '<rect x="3" y="3" width="18" height="18" rx="4.5" stroke="currentColor" stroke-width="2" fill="none"/><circle cx="8.3" cy="8.3" r="1.5" fill="currentColor"/><circle cx="15.7" cy="15.7" r="1.5" fill="currentColor"/><circle cx="12" cy="12" r="1.5" fill="currentColor"/><circle cx="15.7" cy="8.3" r="1.5" fill="currentColor"/><circle cx="8.3" cy="15.7" r="1.5" fill="currentColor"/>',
    pin: '<path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/><circle cx="12" cy="10" r="2.4" stroke="currentColor" stroke-width="2" fill="none"/>',
    music: '<path d="M9 18V5.5l11-2V16" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/><circle cx="6.5" cy="18" r="2.5" stroke="currentColor" stroke-width="2" fill="none"/><circle cx="17.5" cy="16" r="2.5" stroke="currentColor" stroke-width="2" fill="none"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3" stroke="currentColor" stroke-width="2" fill="none"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/>',
    ball: '<circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2" fill="none"/><path d="m12 7.2 3.6 2.6-1.4 4.3H9.8L8.4 9.8z" fill="currentColor"/><path d="M12 7.2V3.3M15.6 9.8l3.7-1.2M14.2 14.1l2.3 3.2M9.8 14.1l-2.3 3.2M8.4 9.8 4.7 8.6" stroke="currentColor" stroke-width="1.6"/>',
    lang: '<path d="M4 5h9M8.5 3v2M6 5c.6 3.5 3 6.2 6 7.5M11 5c-.8 4-3.4 7-7 8.5" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="m12.5 21 4-10 4 10M14 17.5h5" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    trophy: '<path d="M7 4h10v5a5 5 0 0 1-10 0z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/><path d="M7 6H4v1.5A3.5 3.5 0 0 0 7.5 11M17 6h3v1.5a3.5 3.5 0 0 1-3.5 3.5M12 14v3.5M8.5 20.5h7M10 17.5h4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/>',
    vol: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/><path d="M15.5 9a4.5 4.5 0 0 1 0 6M18 6.5a8 8 0 0 1 0 11" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/>',
    vol0: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/>',
    spinner: '<path d="M12 3a9 9 0 1 0 9 9" stroke="currentColor" stroke-width="2.6" fill="none" stroke-linecap="round"/>',
    trash: '<path d="M4.5 6.5h15M9.5 6.5V4.5h5v2M6.5 6.5l1 13h9l1-13" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    more: '<circle cx="5.5" cy="12" r="1.8" fill="currentColor"/><circle cx="12" cy="12" r="1.8" fill="currentColor"/><circle cx="18.5" cy="12" r="1.8" fill="currentColor"/>',
    wave: '<path d="M2 12h3l2.5-6 4 12 3.5-9 2.5 6H22" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    clock: '<circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2" fill="none"/><path d="M12 7v5l3.5 2" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/>',
    flame: '<path d="M12 21c-4 0-6.5-2.7-6.5-6.2 0-3.4 2.6-5.6 3.7-8.8.5 1.8 1.6 2.9 2.6 3.5.3-2.6 1.4-4.9 3.4-6.5-.2 3.3 3.3 5.6 3.3 10 0 4.3-2.6 8-6.5 8z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/>',
    alert: '<path d="M12 3.5 2.5 20h19z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/><path d="M12 10v4.5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="17.3" r="1.2" fill="currentColor"/>',
    home: '<path d="M4 10.5 12 4l8 6.5V20h-5.5v-5.5h-5V20H4z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/>',
    ext: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
  };
  T.icon = function (n, cls) { return '<svg class="' + (cls || 'ic') + '" viewBox="0 0 24 24" aria-hidden="true">' + (P[n] || '') + '</svg>'; };
  var I = T.icon;
  var EQ = '<span class="eq"><i></i><i></i><i></i><i></i></span>';
  T.EQ = EQ;

  // ---------- componenten ----------
  // elke zender krijgt data-sid; de klikafhandeling (één listener) speelt af vanuit de lijst van de container.
  var lists = {}; var lid = 0;
  T.ui = T.ui || {};
  T.ui.reg = function (arr) { var k = 'l' + (++lid); lists[k] = arr; return k; };
  T.ui.list = function (k) { return lists[k] || []; };
  T.ui.resetLists = function () { lists = {}; };

  function playingCls(s) { return T.player && T.player.isCurrent(s.id) ? ' is-playing' : ''; }
  T.ui.card = function (s, opts) {
    opts = opts || {};
    return '<div class="card' + playingCls(s) + '" data-sid="' + esc(s.id) + '">' +
      (opts.rank ? '<span class="num' + (opts.rank <= 3 ? ' t3' : '') + '">' + opts.rank + '</span>' : '') +
      '<button class="pbtn" type="button" data-act="play" aria-label="' + esc(t('play') + ': ' + s.name) + '">' + T.art(s) + '</button>' +
      '<a class="meta" href="#/station/' + encodeURIComponent(s.id) + '"><b>' + esc(s.name) + '</b><small>' + esc(opts.sub != null ? opts.sub : (T.tagsLine(s, 2) || T.countryName(s.cc, s.country))) + '</small></a></div>';
  };
  T.ui.li = function (s, opts) {
    opts = opts || {};
    var sub = opts.sub != null ? opts.sub : [T.countryName(s.cc, s.country) + (s.cc ? ' ' + T.flag(s.cc) : ''), T.tagsLine(s, 2)].filter(Boolean).join(' · ');
    return '<div class="li' + playingCls(s) + '" data-sid="' + esc(s.id) + '">' +
      '<button class="main" type="button" data-act="play" aria-label="' + esc(t('play') + ': ' + s.name) + '">' +
      (opts.rank ? '<span class="rk' + (opts.rank <= 3 ? ' t3' : '') + '">' + opts.rank + '</span>' : '') +
      T.art(s, 'sm') + '<span class="tx"><b>' + esc(s.name) + '</b><small>' + esc(sub) + '</small></span>' +
      '<span class="side-eq eq">' + '<i></i><i></i><i></i><i></i>' + '</span>' +
      (s.bitrate && opts.bitrate !== false ? '<span class="br">' + s.bitrate + ' kbps</span>' : '') + '</button>' +
      (opts.remove ? '<button class="more" type="button" data-act="unfav" aria-label="' + esc(t('lib.remove')) + '">' + I('x') + '</button>' : '') +
      '<a class="more" href="#/station/' + encodeURIComponent(s.id) + '" aria-label="' + esc(t('info') + ': ' + s.name) + '">' + I('info') + '</a></div>';
  };
  // horizontale rij met kop
  T.ui.row = function (title, arr, opts) {
    opts = opts || {};
    if (!arr || !arr.length) return '';
    var k = T.ui.reg(arr);
    var id = 'r' + k;
    return '<section class="sec" aria-labelledby="' + id + '"><div class="sech"><h2 id="' + id + '">' + esc(title) + (opts.sub ? '<small>' + esc(opts.sub) + '</small>' : '') + '</h2>' +
      (opts.all ? '<a class="all" href="' + opts.all + '">' + esc(t('all')) + '</a>' : '') +
      '<span class="arr"><button type="button" data-scroll="-1" aria-label="' + esc(t('back')) + '">' + I('back') + '</button><button type="button" data-scroll="1" aria-label="' + esc(t('more')) + '">' + I('chev') + '</button></span></div>' +
      '<div class="scroller" data-list="' + k + '">' + arr.slice(0, opts.max || 30).map(function (s, i) { return T.ui.card(s, { rank: opts.ranked ? i + 1 : 0 }); }).join('') + '</div></section>';
  };
  T.ui.gridOf = function (arr, opts) {
    opts = opts || {};
    var k = T.ui.reg(arr);
    return '<div class="grid" data-list="' + k + '">' + arr.map(function (s, i) { return T.ui.card(s, { rank: opts.ranked ? i + 1 : 0 }); }).join('') + '</div>';
  };
  T.ui.listOf = function (arr, opts) {
    opts = opts || {};
    var k = T.ui.reg(arr);
    return '<div class="list" data-list="' + k + '">' + arr.map(function (s, i) { return T.ui.li(s, { rank: opts.ranked ? i + 1 : 0, remove: opts.remove }); }).join('') + '</div>';
  };
  T.ui.skRow = function (n) {
    var c = ''; for (var i = 0; i < (n || 6); i++) c += '<div class="skcard"><div class="sk"></div><div class="sk l"></div><div class="sk l2"></div></div>';
    return '<section class="sec"><div class="sech"><h2><span class="sk" style="display:block;width:180px;height:20px;border-radius:6px"></span></h2></div><div class="scroller">' + c + '</div></section>';
  };
  T.ui.skGrid = function (n) {
    var c = ''; for (var i = 0; i < (n || 12); i++) c += '<div class="skcard" style="width:auto"><div class="sk"></div><div class="sk l"></div><div class="sk l2"></div></div>';
    return '<div class="grid">' + c + '</div>';
  };
  T.ui.skList = function (n) { var c = ''; for (var i = 0; i < (n || 8); i++) c += '<div class="sk skli"></div>'; return c; };
  T.ui.error = function (retryFn) {
    var id = 'retry' + (++lid);
    setTimeout(function () { var b = document.getElementById(id); if (b) b.onclick = retryFn; }, 0);
    return '<div class="msg" role="alert"><span class="mi">' + I('alert') + '</span><b>' + esc(t('err.load')) + '</b><span>' + esc(t('err.load.p')) + '</span><button class="btn" type="button" id="' + id + '">' + esc(t('retry')) + '</button></div>';
  };
  T.ui.empty = function (text, icon) { return '<div class="msg"><span class="mi">' + I(icon || 'radio') + '</span><span>' + esc(text) + '</span></div>'; };
  // kop met terugknop
  T.ui.head = function (title, opts) {
    opts = opts || {};
    return '<header class="top">' + (opts.noBack ? '' : '<button class="iconbtn" type="button" data-act="back" aria-label="' + esc(t('back')) + '">' + I('back') + '</button>') +
      '<h1>' + esc(title) + '</h1><span class="sp"></span>' + (opts.right || '') + '</header>';
  };
  T.ui.ccBtn = function () {
    var c = T.store.country; if (!c) return '';
    return '<a class="ccbtn" href="#/country" aria-label="' + esc(t('set.country') + ': ' + T.countryName(c.cc, c.name)) + '"><span class="fl">' + T.flag(c.cc) + '</span>' + esc(c.cc) + '</a>';
  };
  T.ui.gearBtn = function () { return '<a class="iconbtn mob" href="#/settings" aria-label="' + esc(t('tab.settings')) + '">' + I('gear') + '</a>'; };

  // ---------- navigatie ----------
  var TABS = [['discover', 'radio'], ['browse', 'grid'], ['map', 'globe'], ['search', 'search'], ['library', 'library']];
  T.ui.renderNav = function () {
    document.getElementById('tabs').innerHTML = TABS.map(function (x) { return '<a href="#/' + x[0] + '" data-tab="' + x[0] + '">' + I(x[1]) + '<span>' + esc(t('tab.' + x[0])) + '</span></a>'; }).join('');
    document.getElementById('side-nav').innerHTML = TABS.map(function (x) { return '<a href="#/' + x[0] + '" data-tab="' + x[0] + '">' + I(x[1]) + '<span>' + esc(t('tab.' + x[0])) + '</span></a>'; }).join('') +
      '<div class="div"></div><a href="#/settings" data-tab="settings">' + I('gear') + '<span>' + esc(t('tab.settings')) + '</span></a>';
    document.getElementById('side-logo').innerHTML = T.TUNR_LOGO();
    var c = T.store.country;
    document.getElementById('side-foot').innerHTML = (c ? '<a class="ccbtn" href="#/country"><span class="fl">' + T.flag(c.cc) + '</span><span class="n">' + esc(T.countryName(c.cc, c.name)) + '</span></a>' : '') +
      '<a class="site" href="../">' + I('home', 'ic') + esc(t('home')) + '</a>';
    document.querySelectorAll('[aria-label="Hoofdmenu"]').forEach(function (el) { el.setAttribute('aria-label', t('nav.label')); });
    T.ui.markNav(T.ui.curTab);
  };
  T.ui.markNav = function (tab) {
    T.ui.curTab = tab;
    document.querySelectorAll('[data-tab]').forEach(function (a) { if (a.getAttribute('data-tab') === tab) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current'); });
  };
  T.TUNR_LOGO = function () { return window.TUNR.logoHTML(''); };

  // ---------- toast ----------
  var toastT;
  T.ui.toast = function (msg) {
    var el = document.getElementById('toast');
    el.textContent = msg; el.classList.add('show');
    clearTimeout(toastT); toastT = setTimeout(function () { el.classList.remove('show'); }, 2400);
  };

  // ---------- sheet ----------
  var lastFocus = null;
  T.ui.sheet = function (html, onMount) {
    T.ui.closeSheet();
    lastFocus = document.activeElement;
    var d = document.createElement('div'); d.id = 'sheet'; d.setAttribute('role', 'dialog'); d.setAttribute('aria-modal', 'true');
    d.innerHTML = '<div class="box">' + html + '</div>';
    d.addEventListener('click', function (e) { if (e.target === d) T.ui.closeSheet(); });
    document.body.appendChild(d);
    if (onMount) onMount(d);
    var f = d.querySelector('button'); if (f) f.focus();
  };
  T.ui.closeSheet = function () { var d = document.getElementById('sheet'); if (d) { d.remove(); if (lastFocus && lastFocus.focus) lastFocus.focus(); } };
  T.ui.confirm = function (q, okLabel, fn) {
    T.ui.sheet('<h3>' + esc(q) + '</h3><div class="row2"><button class="btn ghost" type="button" data-x>' + esc(t('close')) + '</button><button class="btn" type="button" data-ok>' + esc(okLabel) + '</button></div>', function (d) {
      d.querySelector('[data-x]').onclick = T.ui.closeSheet;
      d.querySelector('[data-ok]').onclick = function () { T.ui.closeSheet(); fn(); };
    });
  };
  T.ui.sleepSheet = function () {
    var opts = [0, 15, 30, 45, 60, 90];
    var end = T.player.sleepEnd, left = end ? Math.ceil((end - Date.now()) / 60000) : 0;
    T.ui.sheet('<h3>' + esc(t('player.sleep')) + '</h3>' + (end ? '<p>' + esc(t('sleep.left', { t: left + ' min' })) + '</p>' : '') +
      '<div class="opts">' + opts.map(function (m) { return '<button type="button" data-m="' + m + '" aria-pressed="' + (!end && !m ? 'true' : 'false') + '">' + esc(m ? t('sleep.min', { n: m }) : t('sleep.off')) + '</button>'; }).join('') + '</div>', function (d) {
      d.querySelectorAll('[data-m]').forEach(function (b) {
        b.onclick = function () { var m = +b.getAttribute('data-m'); T.player.setSleep(m); T.ui.closeSheet(); T.ui.toast(m ? t('sleep.set', { n: m }) : t('sleep.cleared')); };
      });
    });
  };

  // ---------- delen ----------
  T.ui.share = function (s) {
    var url = new URL('#/station/' + encodeURIComponent(s.id), location.href.split('#')[0]).href;
    var data = { title: s.name, text: t('share.text', { n: s.name }), url: url };
    if (navigator.share) { navigator.share(data).catch(function () {}); return; }
    var done = function () { T.ui.toast(t('toast.copied')); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, function () { fallbackCopy(url); done(); });
    else { fallbackCopy(url); done(); }
  };
  function fallbackCopy(txt) { var ta = document.createElement('textarea'); ta.value = txt; ta.style.position = 'fixed'; ta.style.opacity = '0'; document.body.appendChild(ta); ta.select(); try { document.execCommand('copy'); } catch (e) {} ta.remove(); }

  T.ui.toggleFav = function (s) {
    var added = T.store.toggleFav(s);
    T.ui.toast(added ? t('toast.fav') : t('toast.unfav'));
    T.ui.syncPlaying();
  };

  // ---------- miniplayer ----------
  var mini = document.getElementById('mini');
  function statusLine(st, s) {
    if (st === 'loading') return '<small>' + I('spinner', 'ic spin') + esc(t('player.loading')) + '</small>';
    if (st === 'error') return '<small class="err">' + esc(t('player.err')) + '</small>';
    if (st === 'blocked') return '<small class="err">' + esc(t('player.blocked')) + '</small>';
    if (st === 'playing') return '<small>' + EQ + esc(T.tagsLine(s, 2) || t('player.playing')) + '</small>';
    return '<small>' + esc(T.tagsLine(s, 2) || t('player.paused')) + '</small>';
  }
  function ppIcon(st) { return st === 'loading' ? I('spinner', 'ic spin') : (st === 'playing' ? I('pause') : I('play')); }
  T.ui.renderMini = function () {
    var s = T.player.current, st = T.player.state;
    if (!s) { mini.hidden = true; document.body.classList.remove('has-mini'); return; }
    mini.hidden = false; document.body.classList.add('has-mini');
    mini.classList.toggle('on', st === 'playing');
    var fav = T.store.isFav(s.id);
    var vol = T.player.volume;
    mini.innerHTML = '<button class="open" type="button" data-act="openfull" aria-label="' + esc(t('player.open')) + '">' + T.art(s, 'sm') +
      '<span class="tx"><b>' + esc(s.name) + '</b>' + statusLine(st, s) + '</span></button>' +
      '<div class="center dsk"><button class="c" type="button" data-act="prev" aria-label="' + esc(t('player.prev')) + '">' + I('prev') + '</button>' +
      '<button class="c pp" type="button" data-act="toggle" aria-label="' + esc(st === 'playing' ? t('pause') : t('play')) + '">' + ppIcon(st) + '</button>' +
      '<button class="c" type="button" data-act="next" aria-label="' + esc(t('player.next')) + '">' + I('next') + '</button></div>' +
      '<div class="right dsk">' + (st === 'playing' ? '<span class="livepill">' + esc(t('player.live')) + '</span>' : '') +
      '<button class="c" type="button" data-act="fav" aria-pressed="' + fav + '" aria-label="' + esc(t('detail.fav')) + '">' + I(fav ? 'heartf' : 'heart') + '</button>' +
      '<button class="c" type="button" data-act="sleep" aria-pressed="' + (!!T.player.sleepEnd) + '" aria-label="' + esc(t('player.sleep')) + '">' + I('moon') + '</button>' +
      '<button class="c" type="button" data-act="mute" aria-label="' + esc(t('player.volume')) + '">' + I(vol > 0 ? 'vol' : 'vol0') + '</button>' +
      '<input type="range" min="0" max="1" step="0.01" value="' + vol + '" data-act="vol" aria-label="' + esc(t('player.volume')) + '" style="--p:' + (vol * 100) + '%"></div>' +
      '<button class="c pp mob-only" type="button" data-act="toggle" aria-label="' + esc(st === 'playing' ? t('pause') : t('play')) + '">' + ppIcon(st) + '</button>' +
      '<button class="c mobnext" type="button" data-act="next" aria-label="' + esc(t('player.next')) + '">' + I('next') + '</button>';
  };

  // ---------- volledige speler ----------
  var full = document.getElementById('full');
  T.ui.openFull = function () {
    if (!T.player.current) return;
    T.ui.renderFull();
    full.classList.add('open'); full.setAttribute('aria-hidden', 'false');
    document.documentElement.style.overflow = 'hidden'; document.body.classList.add('full-open');
    if (!/[?&]p=1/.test(location.hash)) history.pushState({ full: 1 }, '', location.hash.split('?')[0] + '?p=1');
    setTimeout(function () { var b = full.querySelector('[data-act="toggle"]'); if (b) b.focus(); }, 60);
  };
  T.ui.closeFull = function (fromPop) {
    if (!full.classList.contains('open')) return;
    full.classList.remove('open'); full.setAttribute('aria-hidden', 'true');
    document.documentElement.style.overflow = ''; document.body.classList.remove('full-open');
    if (!fromPop && /[?&]p=1/.test(location.hash)) history.back();
    var o = mini.querySelector('.open'); if (o) o.focus();
  };
  T.ui.isFullOpen = function () { return full.classList.contains('open'); };
  T.ui.renderFull = function () {
    var s = T.player.current; if (!s) return;
    var st = T.player.state, p = T.pal(s.name), fav = T.store.isFav(s.id), logo = T.logoUrl(s.favicon);
    var end = T.player.sleepEnd, left = end ? Math.max(1, Math.ceil((end - Date.now()) / 60000)) : 0;
    full.style.setProperty('--a', p[0]); full.style.setProperty('--b', p[1]);
    full.classList.toggle('on', st === 'playing');
    var status = st === 'loading' ? I('spinner', 'ic spin') + esc(t('player.loading'))
      : st === 'playing' ? EQ + esc(t('player.playing')) : st === 'paused' ? esc(t('player.paused')) : '';
    var err = '';
    if (st === 'error') err = '<div class="err" role="alert"><b>' + esc(t('player.err')) + '</b><button class="btn sm white" type="button" data-act="retry">' + esc(t('retry')) + '</button></div>';
    if (st === 'blocked') err = '<div class="err" role="alert"><b>' + esc(t('player.blocked')) + '</b><p>' + esc(t('player.blocked.p')) + '</p><p style="margin-top:8px;color:#fff;font-weight:700">' + esc(t('player.apps')) + '</p></div>';
    var vol = T.player.volume;
    full.innerHTML = '<div class="bd">' + (logo ? '<img src="' + esc(logo) + '" alt="" referrerpolicy="no-referrer" onerror="this.remove()">' : '') + '</div>' +
      '<div class="fin"><div class="fbar"><button class="iconbtn" type="button" data-act="closefull" aria-label="' + esc(t('close')) + '">' + I('down') + '</button>' +
      '<span class="ttl">' + esc(T.countryName(s.cc, s.country)) + ' ' + T.flag(s.cc) + '</span>' +
      '<a class="iconbtn" href="#/station/' + encodeURIComponent(s.id) + '" data-act="closefull-nav" aria-label="' + esc(t('player.info')) + '">' + I('info') + '</a></div>' +
      '<div class="fart"><span class="livepill">' + esc(t('player.live')) + '</span>' + T.art(s, 'lg') + '</div>' +
      '<div class="fmeta"><div class="tx"><h2>' + esc(s.name) + '</h2><p>' + esc([T.tagsLine(s, 3), s.state].filter(Boolean).join(' · ') || T.place(s)) + '</p></div>' +
      '<button class="rbtn" type="button" data-act="fav" aria-pressed="' + fav + '" aria-label="' + esc(t('detail.fav')) + '">' + I(fav ? 'heartf' : 'heart') + '</button></div>' +
      '<div class="line"></div><div class="status">' + status + '</div>' + err +
      '<div class="ctl"><button class="c" type="button" data-act="prev" aria-label="' + esc(t('player.prev')) + '">' + I('prev') + '</button>' +
      '<button class="pp" type="button" data-act="toggle" aria-label="' + esc(st === 'playing' ? t('pause') : t('play')) + '">' + ppIcon(st) + '</button>' +
      '<button class="c" type="button" data-act="next" aria-label="' + esc(t('player.next')) + '">' + I('next') + '</button></div>' +
      '<div class="vol">' + I('vol0') + '<input type="range" min="0" max="1" step="0.01" value="' + vol + '" data-act="vol" aria-label="' + esc(t('player.volume')) + '" style="--p:' + (vol * 100) + '%">' + I('vol') + '</div>' +
      '<div class="more"><button type="button" data-act="share">' + I('share') + esc(t('player.share')) + '</button>' +
      '<button type="button" data-act="sleep" class="' + (end ? 'on' : '') + '">' + I('moon') + esc(t('player.sleep')) + (end ? '<small>' + left + ' min</small>' : '') + '</button>' +
      '<a href="#/station/' + encodeURIComponent(s.id) + '" data-act="closefull-nav" style="display:flex;flex-direction:column;align-items:center;gap:6px;padding:12px 6px;border-radius:14px;background:#ffffff10;border:1px solid #ffffff14;font-size:12.5px;font-weight:700;color:#ffffffd0">' + I('info') + esc(t('player.info')) + '</a></div></div>';
  };

  // speelt-markering bijwerken zonder alles opnieuw te tekenen
  T.ui.syncPlaying = function () {
    var cur = T.player.current;
    document.querySelectorAll('[data-sid]').forEach(function (el) {
      var on = !!cur && el.getAttribute('data-sid') === cur.id;
      el.classList.toggle('is-playing', on);
      if (el.classList.contains('card')) {
        var b = el.querySelector('.pbtn'); if (b) b.setAttribute('aria-label', (on && T.player.state === 'playing' ? t('pause') : t('play')) + ': ' + (el.querySelector('.meta b') || {}).textContent);
      }
    });
    document.querySelectorAll('[data-detail-play]').forEach(function (b) {
      var id = b.getAttribute('data-detail-play'), active = T.player.isActive(id);
      b.innerHTML = (T.player.isCurrent(id) && T.player.state === 'loading' ? I('spinner', 'ic spin') : I(active ? 'pause' : 'play')) + '<span>' + esc(active ? t('pause') : t('play')) + '</span>';
    });
    document.querySelectorAll('[data-detail-fav]').forEach(function (b) {
      var f = T.store.isFav(b.getAttribute('data-detail-fav'));
      b.setAttribute('aria-pressed', f); b.innerHTML = I(f ? 'heartf' : 'heart');
    });
  };

  T.ui.greeting = function () {
    var h = new Date().getHours();
    return t(h >= 5 && h < 12 ? 'greet.morning' : h >= 12 && h < 18 ? 'greet.afternoon' : h >= 18 ? 'greet.evening' : 'greet.night');
  };
})();

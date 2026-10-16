// Tunr changelog-pagina: tekent ../assets/changelog.json (gemaakt door tools/make_changelog.py uit docs/changelog.json)
// met platformlabels, typekoppen (Nieuw / Verbeterd / Opgelost) en een platformfilter. NL/EN volgt i18n.js.
(function () {
  var list = document.getElementById('list'), bar = document.getElementById('fbar');
  var data = null, filter = 'all';
  var PL = {
    ios: ['iPhone', 'apple'], ipados: ['iPad', 'apple'], macos: ['Mac', 'apple'], tvos: ['Apple TV', 'apple'], carplay: ['CarPlay', 'car'],
    android: ['Android', 'and'], androidtv: ['Android TV', 'and'], web: ['Web', 'web']
  };
  var ALL = Object.keys(PL);
  var ICON = {
    apple: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.4 12.6c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.1-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.1-1.2 2.9-2.4.9-1.4 1.3-2.7 1.3-2.8 0 0-2.4-1-2.4-3.9zM14 5.5c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1 .1 2.1-.6 2.8-1.4z"/></svg>',
    and: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4.5 16.5a7.5 7.5 0 0 1 15 0z"/><path d="M7 7.6 5.4 5M17 7.6 18.6 5"/></svg>',
    web: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9s-1.2 6.4-3.7 9M12 3C9.5 5.6 8.3 8.6 8.3 12s1.2 6.4 3.7 9"/></svg>',
    car: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M5 11.5 6.8 6.4A2 2 0 0 1 8.7 5h6.6a2 2 0 0 1 1.9 1.4l1.8 5.1"/><rect x="3" y="11.5" width="18" height="6" rx="1.8"/></svg>'
  };
  function lang() { return (window.TunrI18n && TunrI18n.lang) || 'nl'; }
  function L(nl, en) { return lang() === 'en' ? en : nl; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function date(d) {
    try { return new Date(d + 'T12:00:00').toLocaleDateString(lang() === 'en' ? 'en-GB' : 'nl-NL', { day: 'numeric', month: 'long', year: 'numeric' }); } catch (e) { return d; }
  }
  function badges(pl) {
    var set = {}; pl.forEach(function (p) { set[p] = 1; });
    var hasAll = ALL.every(function (p) { return set[p] || p === 'carplay'; });
    if (hasAll) return '<span class="pi all">' + esc(L('Alle platforms', 'All platforms')) + '</span>';
    return pl.filter(function (p) { return PL[p]; }).map(function (p) { return '<span class="pi ' + PL[p][1] + '">' + ICON[PL[p][1]] + esc(PL[p][0]) + '</span>'; }).join('');
  }
  function renderBar() {
    var used = {};
    (data ? data.builds : []).forEach(function (b) { b.items.forEach(function (i) { i.platforms.forEach(function (p) { used[p] = 1; }); }); });
    var opts = [['all', L('Alles', 'All')]].concat(ALL.filter(function (p) { return used[p]; }).map(function (p) { return [p, PL[p][0]]; }));
    bar.innerHTML = opts.map(function (o) { return '<button type="button" data-f="' + o[0] + '" aria-pressed="' + (filter === o[0]) + '">' + (o[0] !== 'all' ? ICON[PL[o[0]][1]] : '') + esc(o[1]) + '</button>'; }).join('');
  }
  function render() {
    if (!data) return;
    renderBar();
    var builds = data.builds.slice().sort(function (a, b) { return b.build - a.build; });
    var html = '', first = true;
    builds.forEach(function (b) {
      var items = b.items.filter(function (i) { return filter === 'all' || i.platforms.indexOf(filter) >= 0; });
      if (!items.length) return;
      html += '<article class="build" id="build-' + b.build + '"><div class="bh"><h2>Build ' + b.build + '</h2><span class="v">1.0.0</span>' + (first ? '<span class="latest">' + esc(L('Nieuwste', 'Latest')) + '</span>' : '') + '<time datetime="' + esc(b.date) + '">' + esc(date(b.date)) + '</time></div>';
      [['new', L('Nieuw', 'New')], ['improved', L('Verbeterd', 'Improved')], ['fixed', L('Opgelost', 'Fixed')]].forEach(function (k) {
        var g = items.filter(function (i) { return i.type === k[0]; });
        if (!g.length) return;
        html += '<section class="grp ' + k[0] + '"><h3>' + esc(k[1]) + '</h3><ul>' + g.map(function (i) {
          return '<li>' + esc(lang() === 'en' ? i.en : i.nl) + '<div class="pls">' + badges(i.platforms) + '</div></li>';
        }).join('') + '</ul></section>';
      });
      html += '</article>';
      first = false;
    });
    list.innerHTML = html || '<p class="empty">' + esc(L('Geen wijzigingen voor dit platform.', 'No changes for this platform.')) + '</p>';
  }
  bar.addEventListener('click', function (e) { var b = e.target.closest('[data-f]'); if (!b) return; filter = b.getAttribute('data-f'); render(); });
  document.addEventListener('tunr:lang', render);
  fetch('../assets/changelog.json', { cache: 'no-cache' }).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (d) { data = d; render(); if (location.hash) { var el = document.querySelector(location.hash); if (el) el.scrollIntoView(); } })
    .catch(function () { list.innerHTML = '<p class="empty">' + esc(L('De changelog kan nu niet worden geladen.', 'The changelog can\'t be loaded right now.')) + '</p>'; });
})();

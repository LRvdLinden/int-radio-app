// Tunr changelog-pagina (zelfde indeling als de changelog van Bingr): filters Apparaat en Soort, per build een
// uitklapbare kaart "Versie X · Build N" met samenvatting, groepen Nieuw / Verbeterd / Opgelost met apparaatlabels,
// een knop om de link naar de build te kopiëren (#build-N klapt die build open) en rechts "Nieuwste versie per apparaat".
// Gegevens: ../assets/changelog.json (tools/make_changelog.py uit docs/changelog.json). Taal volgt i18n.js (event tunr:lang).
(function () {
  var listEl = document.getElementById('list'), curEl = document.getElementById('cur');
  var fpS = document.getElementById('fp'), ftS = document.getElementById('ft');
  if (!listEl || !fpS || !ftS) return;

  var TX = {
    nl: { all: 'Alles', allApps: 'Alle apps', latest: 'Nieuwste', version: 'Versie', current: 'Nieuwste versie per apparaat',
          copyLink: 'Link kopiëren', copied: 'Gekopieerd', copyTitle: 'Kopieer de link naar build %d',
          new: 'Nieuw', improved: 'Verbeterd', fixed: 'Opgelost', empty: 'Geen wijzigingen voor deze keuze.',
          error: 'De changelog kan nu niet worden geladen.' },
    en: { all: 'All', allApps: 'All apps', latest: 'Latest', version: 'Version', current: 'Latest version per device',
          copyLink: 'Copy link', copied: 'Copied', copyTitle: 'Copy the link to build %d',
          new: 'New', improved: 'Improved', fixed: 'Fixed', empty: 'No changes for this selection.',
          error: "The changelog can't be loaded right now." }
  };
  function lang() { return (window.TunrI18n && TunrI18n.lang) === 'en' ? 'en' : 'nl'; }
  function T() { return TX[lang()]; }

  var S = function (d) { return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>'; };
  var IC = {
    ios: S('<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 5.5h2"/>'),
    ipados: S('<rect x="4.5" y="2.5" width="15" height="19" rx="2"/><circle cx="12" cy="18.5" r=".6" fill="currentColor"/>'),
    macos: S('<rect x="4.5" y="5" width="15" height="10.5" rx="1.5"/><path d="M2 19h20l-1.5-3.5h-17z"/>'),
    tvos: S('<rect x="2.5" y="4" width="19" height="13" rx="2"/><path d="M8.5 20.5h7"/><path d="M9.5 9.5h5M12 9.5v4"/>'),
    carplay: S('<path d="M5 11.5 6.8 6.4A2 2 0 0 1 8.7 5h6.6a2 2 0 0 1 1.9 1.4l1.8 5.1"/><rect x="3" y="11.5" width="18" height="6" rx="1.8"/><path d="M7 20v-2.5M17 20v-2.5"/>'),
    android: S('<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><circle cx="12" cy="5.2" r=".7" fill="currentColor"/>'),
    androidtv: S('<rect x="2.5" y="4" width="19" height="13" rx="2"/><path d="M8.5 20.5h7M12 17v3.5"/>'),
    windows: S('<rect x="3" y="4" width="18" height="12" rx="1.5"/><path d="M8 20h8M12 16v4"/>'),
    web: S('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>'),
    all: S('<rect x="2.5" y="4" width="13" height="9" rx="1.5"/><path d="M6 16h6"/><rect x="16.5" y="8" width="5" height="11" rx="1.3"/>')
  };
  // [sleutel, naam, kleurklasse]
  var P = [['ios', 'iPhone', ''], ['ipados', 'iPad', ''], ['macos', 'Mac', ''], ['tvos', 'Apple TV', ''], ['carplay', 'CarPlay', 'car'],
           ['android', 'Android', 'and'], ['androidtv', 'Android TV', 'and'], ['windows', 'Windows', 'win'], ['web', 'Website', 'web']];
  // "Alle apps" = alle apps (CarPlay en Windows tellen mee als ze erbij staan, maar zijn niet verplicht; zelfde regel als make_changelog.py)
  var APPS = ['ios', 'ipados', 'macos', 'tvos', 'android', 'androidtv', 'web'];

  var q = new URLSearchParams(location.search);
  var fp = q.get('p') || 'all', ft = q.get('t') || 'all';
  var data = null, openSet = null;

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function loc() { return lang() === 'en' ? 'en-GB' : 'nl-NL'; }
  function fmt(d, long) {
    try { return new Date(d + 'T12:00:00').toLocaleDateString(loc(), { day: 'numeric', month: long ? 'long' : 'short', year: 'numeric' }); } catch (e) { return d; }
  }
  function has(list, p) { return list.indexOf(p) >= 0; }
  function plats(pl) {
    var out = [], rest = pl;
    if (APPS.every(function (p) { return has(pl, p); })) {
      out.push('<span class="pi all" title="' + esc(T().allApps) + '">' + IC.all + esc(T().allApps) + '</span>');
      rest = pl.filter(function (p) { return !has(APPS, p); });
    }
    P.forEach(function (x) { if (has(rest, x[0])) out.push('<span class="pi ' + x[2] + '" title="' + esc(x[1]) + '">' + IC[x[0]] + esc(x[1]) + '</span>'); });
    return '<span class="pl">' + out.join('') + '</span>';
  }

  function renderCurrent() {
    if (!curEl) return;
    var rows = P.map(function (x) {
      var e = null;
      for (var i = 0; i < data.length; i++) { if (data[i].items.some(function (it) { return has(it.platforms || [], x[0]); })) { e = data[i]; break; } }
      if (!e) return '';
      return '<a class="cv" href="?p=' + x[0] + '" data-cp="' + x[0] + '">' + IC[x[0]] + '<span class="cn">' + esc(x[1]) + '</span><span class="cb">' +
        esc(e.version || '1.0.0') + ' · <b>Build ' + e.build + '</b><br><span class="cd">' + esc(fmt(e.date)) + '</span></span></a>';
    }).join('');
    curEl.innerHTML = '<h2 id="curTitle">' + esc(T().current) + '</h2><div class="cvs">' + rows + '</div>';
    curEl.querySelectorAll('[data-cp]').forEach(function (a) {
      a.onclick = function (ev) { ev.preventDefault(); fp = a.getAttribute('data-cp'); keep(); render(); listEl.scrollIntoView({ behavior: 'smooth', block: 'start' }); };
    });
  }

  function keep() {
    try {
      var u = new URL(location.href);
      fp === 'all' ? u.searchParams.delete('p') : u.searchParams.set('p', fp);
      ft === 'all' ? u.searchParams.delete('t') : u.searchParams.set('t', ft);
      history.replaceState(null, '', u);
    } catch (e) {}
  }

  var LINK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1.5-1.5"/></svg>';
  function copyText(t) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(t);
    return new Promise(function (ok, no) {
      var a = document.createElement('textarea'); a.value = t; a.style.position = 'fixed'; a.style.opacity = '0';
      document.body.appendChild(a); a.select();
      try { document.execCommand('copy') ? ok() : no(); } catch (e) { no(e); }
      a.remove();
    });
  }

  function render() {
    var t = T();
    fpS.innerHTML = [['all', t.all]].concat(P.map(function (x) { return [x[0], x[1]]; }))
      .map(function (o) { return '<option value="' + o[0] + '"' + (o[0] === fp ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('');
    ftS.innerHTML = [['all', t.all], ['new', t.new], ['improved', t.improved], ['fixed', t.fixed]]
      .map(function (o) { return '<option value="' + o[0] + '"' + (o[0] === ft ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('');
    fpS.onchange = function () { fp = fpS.value; keep(); render(); };
    ftS.onchange = function () { ft = ftS.value; keep(); render(); };

    var firstBuild = null;
    var types = ft === 'all' ? ['new', 'improved', 'fixed'] : [ft];
    var html = data.map(function (e) {
      var items = e.items.filter(function (i) { return fp === 'all' || has(i.platforms || [], fp); });
      var shown = items.filter(function (i) { return has(types, i.type); });
      if (!shown.length) return '';
      var groups = types.map(function (ty) {
        var rows = items.filter(function (i) { return i.type === ty; });
        if (!rows.length) return '';
        return '<div class="grp ' + ty + '"><h3>' + esc(t[ty]) + '</h3><ul>' +
          rows.map(function (i) { return '<li>' + esc(i[lang()] || i.nl) + plats(i.platforms || []) + '</li>'; }).join('') + '</ul></div>';
      }).join('');
      var counts = types.map(function (ty) {
        var n = shown.filter(function (i) { return i.type === ty; }).length;
        return n ? '<span class="tc ' + ty + '">' + esc(t[ty]) + ' <span class="n">' + n + '</span></span>' : '';
      }).join('');
      var allP = [];
      shown.forEach(function (i) { (i.platforms || []).forEach(function (p) { if (!has(allP, p)) allP.push(p); }); });
      if (firstBuild === null) firstBuild = e.build;
      var isOpen = openSet ? openSet.has(e.build) : e.build === firstBuild;
      var top = e.build === data[0].build ? '<span class="latest">' + esc(t.latest) + '</span>' : '';
      var title = t.copyTitle.replace('%d', e.build);
      return '<section class="rel' + (isOpen ? ' open' : '') + '" id="build-' + e.build + '" data-b="' + e.build + '">' +
        '<button type="button" class="cp" data-cp-b="' + e.build + '" title="' + esc(title) + '" aria-label="' + esc(title) + '">' + LINK + '<span class="t">' + esc(t.copyLink) + '</span></button>' +
        '<button type="button" class="rhead" aria-expanded="' + isOpen + '"><span class="rv"><span class="v">' + esc(t.version) + ' ' + esc(e.version || '1.0.0') + '</span>' +
        '<span class="b">Build ' + e.build + '</span><span class="d">' + esc(fmt(e.date, true)) + '</span>' + top + '</span>' +
        '<span class="rsum">' + counts + plats(allP) + '</span></button><div class="rbody">' + groups + '</div></section>';
    }).join('');
    listEl.innerHTML = html || '<p class="empty">' + esc(t.empty) + '</p>';

    listEl.querySelectorAll('.rel .cp').forEach(function (b) {
      b.onclick = function (ev) {
        ev.stopPropagation();
        var n = b.getAttribute('data-cp-b'), url = 'https://tunr.online/changelog/#build-' + n, lab = b.querySelector('.t');
        var done = function () {
          b.classList.add('ok'); lab.textContent = T().copied; b.setAttribute('aria-label', T().copied);
          setTimeout(function () { b.classList.remove('ok'); lab.textContent = T().copyLink; b.setAttribute('aria-label', T().copyTitle.replace('%d', n)); }, 1800);
        };
        copyText(url).then(done, function () { window.prompt(T().copyLink, url); });
        try { history.replaceState(null, '', location.pathname + location.search + '#build-' + n); } catch (e) {}
      };
    });
    listEl.querySelectorAll('.rel .rhead').forEach(function (b) {
      b.onclick = function () {
        var sec = b.parentNode, n = Number(sec.getAttribute('data-b'));
        if (!openSet) { openSet = new Set(); listEl.querySelectorAll('.rel.open').forEach(function (x) { openSet.add(Number(x.getAttribute('data-b'))); }); }
        var o = !sec.classList.contains('open');
        sec.classList.toggle('open', o); b.setAttribute('aria-expanded', o);
        o ? openSet.add(n) : openSet.delete(n);
      };
    });
  }

  // gedeelde link (#build-40): die build openklappen, zichtbaar maken (filters zo nodig terug op Alles) en ernaartoe scrollen
  function goToHash() {
    var m = /^#build-(\d+)$/.exec(location.hash || '');
    if (!m || !data) return false;
    var n = Number(m[1]);
    if (!data.some(function (e) { return e.build === n; })) return false;
    openSet = openSet || new Set(); openSet.add(n);
    render();
    if (!document.getElementById('build-' + n)) { fp = 'all'; ft = 'all'; keep(); render(); }
    var el = document.getElementById('build-' + n);
    if (el) { el.scrollIntoView({ block: 'start' }); el.classList.remove('hl'); void el.offsetWidth; el.classList.add('hl'); }
    return true;
  }

  window.addEventListener('hashchange', goToHash);
  document.addEventListener('tunr:lang', function () { if (data) { renderCurrent(); render(); } });

  fetch('../assets/changelog.json?t=' + Date.now(), { cache: 'no-store' })
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (d) {
      data = (d.builds || d).slice().sort(function (a, b) { return b.build - a.build; });
      if (P.every(function (x) { return x[0] !== fp; })) fp = 'all';
      renderCurrent();
      if (!goToHash()) render();
    })
    .catch(function () { listEl.innerHTML = '<p class="empty">' + esc(T().error) + '</p>'; });
})();

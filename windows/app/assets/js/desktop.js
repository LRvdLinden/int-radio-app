// Tunr voor Windows: koppeling met het venster (Tauri, windows/src-tauri).
// - links naar buiten (http/https/mailto, ook target=_blank) openen in de standaardbrowser, niet in het app-venster;
// - window.open idem;
// - geen contextmenu van de browser behalve in tekstvelden;
// - geen zoom met Ctrl+muiswiel/Ctrl +/- (de app schaalt zelf mee met het venster).
(function () {
  var tauri = window.__TAURI__;
  function openExternal(url) {
    try {
      if (tauri && tauri.opener && tauri.opener.openUrl) return tauri.opener.openUrl(url);
    } catch (e) {}
    window.open(url, '_blank', 'noopener');
  }
  function external(href) { return /^(https?:|mailto:)/i.test(href || '') && href.indexOf(location.origin) !== 0; }

  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.href;
    if (external(href)) { e.preventDefault(); e.stopPropagation(); openExternal(href); }
  }, true);

  if (tauri) {
    var nativeOpen = window.open;
    window.open = function (url) {
      try { var u = new URL(url, location.href).href; if (external(u)) { openExternal(u); return null; } } catch (e) {}
      return nativeOpen.apply(window, arguments);
    };
    document.addEventListener('contextmenu', function (e) {
      var el = e.target;
      if (el && (el.isContentEditable || /^(INPUT|TEXTAREA)$/.test(el.tagName))) return;
      e.preventDefault();
    });
    document.addEventListener('wheel', function (e) { if (e.ctrlKey) e.preventDefault(); }, { passive: false });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === '+' || e.key === '-' || e.key === '=' || e.key === '0')) e.preventDefault();
    });
  }
  window.TUNR.desktop = !!tauri;
  window.TUNR.openExternal = openExternal;
})();

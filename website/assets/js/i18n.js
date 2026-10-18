// Tunr: taal (NL/EN) voor de website. NL staat in de HTML; EN komt uit de woordenlijst hieronder
// plus wat een pagina zelf toevoegt met window.TUNR_I18N = { en: {...} } (vóór dit script).
// - data-i18n="sleutel"             → innerHTML
// - data-i18n-attr="alt:sleutel;aria-label:sleutel2" → attributen
// - data-l="nl" / data-l="en"        → hele blokken per taal (privacy, voorwaarden)
// - data-en="…" / data-nl="…" (niet-meta) → innerHTML in die taal; de tekst in de HTML is de standaardtaal van de
//   pagina (gegenereerde zenderpagina's: NL of EN). Idem data-en-alt / data-nl-alt (ook -title, -aria-label).
// - <meta name="tunr-title-en|tunr-title-nl"> → paginatitel in die taal; meta's met data-en / data-nl idem.
// Keuze: ?lang=en|nl > localStorage 'tunr.lang' (ook gebruikt door de webspeler) > navigator.language.
// Ook: het menu voor smalle schermen, de nav die donker wordt bij scrollen en het jaartal.
(function () {
  var KEY = 'tunr.lang';
  var q = null; try { q = new URLSearchParams(location.search).get('lang'); } catch (e) {}
  var saved = null; try { saved = localStorage.getItem(KEY); } catch (e) {}
  if (q === 'nl' || q === 'en') { try { localStorage.setItem(KEY, q); } catch (e) {} }
  var pick = q || saved || navigator.language || 'nl';
  var lang = String(pick).toLowerCase().indexOf('nl') === 0 ? 'nl' : 'en';

  var EN = {
    'skip': 'Skip to content',
    'nav.label': 'Main menu', 'nav.features': 'Features', 'nav.podcasts': 'Podcasts', 'nav.map': 'World map', 'nav.devices': 'Devices', 'nav.download': 'Download', 'nav.faq': 'FAQ', 'nav.web': 'Listen now', 'nav.stations': 'Stations',
    'nav.menu': 'Menu',
    'foot.tag': 'All the world\'s radio and podcasts. On every screen.',
    'foot.web': 'Web player', 'foot.stations': 'Radio stations by country', 'foot.changelog': 'Changelog', 'foot.privacy': 'Privacy', 'foot.terms': 'Terms', 'foot.cookies': 'Cookie settings', 'foot.info': 'Info', 'foot.more': 'More',
    'foot.disc': 'Tunr doesn\'t host any radio streams or podcasts: every station and episode plays directly from the broadcaster\'s or creator\'s server. Station data: <a href="https://www.radio-browser.info" rel="noopener">Radio Browser</a> (community database); podcast data: Apple\'s public podcast directory. Apple, iPhone, iPad, Mac, Apple TV and CarPlay are trademarks of Apple Inc. Android, Android TV, Android Auto, Google TV and Google Play are trademarks of Google LLC, Fire TV of Amazon.com, Inc.',
    'foot.version': 'version'
  };
  var extra = (window.TUNR_I18N && window.TUNR_I18N.en) || {};
  for (var k in extra) EN[k] = extra[k];

  // canonical: de x-default-URL, plus ?lang= als die nl of en is. Alleen op pagina's met een
  // x-default en zonder eigen canonical.
  (function () {
    var xd = document.querySelector('link[rel="alternate"][hreflang="x-default"]');
    if (!xd || document.querySelector('link[rel="canonical"]')) return;
    var c = document.createElement('link'); c.rel = 'canonical';
    c.href = xd.href + (q === 'nl' || q === 'en' ? '?lang=' + q : '');
    document.head.appendChild(c);
  })();

  var originals = new WeakMap();
  function setHTML(el, key) {
    if (!originals.has(el)) originals.set(el, el.innerHTML);
    var v = lang === 'en' ? EN[key] : null;
    el.innerHTML = v != null ? v : originals.get(el);
  }
  var attrOrig = new WeakMap();
  function setAttrs(el) {
    var spec = el.getAttribute('data-i18n-attr') || '';
    if (!attrOrig.has(el)) attrOrig.set(el, {});
    var o = attrOrig.get(el);
    spec.split(';').forEach(function (pair) {
      var p = pair.split(':'); if (p.length < 2) return;
      var a = p[0].trim(), key = p[1].trim();
      if (!(a in o)) o[a] = el.getAttribute(a);
      var v = lang === 'en' ? EN[key] : null;
      if (v != null) el.setAttribute(a, v); else if (o[a] != null) el.setAttribute(a, o[a]);
    });
  }

  function apply() {
    document.documentElement.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(function (el) { setHTML(el, el.getAttribute('data-i18n')); });
    document.querySelectorAll('[data-i18n-attr]').forEach(setAttrs);
    document.querySelectorAll('[data-l]').forEach(function (el) { el.hidden = el.getAttribute('data-l') !== lang; });
    // gelokaliseerde afbeeldingen: assets/img/nl/... ↔ assets/img/en/...
    document.querySelectorAll('source[data-loc]').forEach(function (so) {
      var next = so.getAttribute('srcset').replace(/\/(nl|en)\//, '/' + lang + '/');
      if (so.getAttribute('srcset') !== next) so.setAttribute('srcset', next);
    });
    document.querySelectorAll('img[data-loc]').forEach(function (img) {
      var src = img.getAttribute('data-src') || img.getAttribute('src');
      var next = src.replace(/\/(nl|en)\//, '/' + lang + '/');
      if (img.getAttribute('src') !== next) {
        var fig = img.closest('figure'); if (fig) fig.hidden = false;
        img.setAttribute('src', next);
      }
    });
    // meta's met een Engelse versie (description, og:…): de NL-tekst staat in de HTML
    document.querySelectorAll('meta[data-en],meta[data-nl]').forEach(function (m) {
      if (m.dataset.orig == null) m.dataset.orig = m.content;
      var v = m.getAttribute('data-' + lang); m.content = v != null ? v : m.dataset.orig;
    });
    // elementen met hun tekst per taal in data-en / data-nl (de HTML bevat de standaardtaal)
    document.querySelectorAll('[data-en]:not(meta),[data-nl]:not(meta)').forEach(function (el) {
      if (!originals.has(el)) originals.set(el, el.innerHTML);
      var v = el.getAttribute('data-' + lang); el.innerHTML = v != null ? v : originals.get(el);
    });
    ['alt', 'title', 'aria-label'].forEach(function (a) {
      document.querySelectorAll('[data-en-' + a + '],[data-nl-' + a + ']').forEach(function (el) {
        var k = 'data-orig-' + a;
        if (!el.hasAttribute(k)) el.setAttribute(k, el.getAttribute(a) || '');
        var v = el.getAttribute('data-' + lang + '-' + a); el.setAttribute(a, v != null ? v : el.getAttribute(k));
      });
    });
    // FAQPage (JSON-LD) gelijk aan de zichtbare vragen in de gekozen taal
    var ld = document.getElementById('ld-faq');
    if (ld) ld.textContent = JSON.stringify({ '@context': 'https://schema.org', '@type': 'FAQPage', '@id': (window.TUNR ? window.TUNR.domain : '') + '/#faq', inLanguage: lang,
      mainEntity: Array.prototype.map.call(document.querySelectorAll('#faq details'), function (d) { return { '@type': 'Question', name: d.querySelector('summary').textContent.trim(), acceptedAnswer: { '@type': 'Answer', text: d.querySelector('.a').textContent.trim() } }; }) });
    var t = document.querySelector('meta[name="tunr-title-' + lang + '"]');
    if (document.documentElement.dataset.titleOrig == null) document.documentElement.dataset.titleOrig = document.title;
    document.title = t ? t.content : document.documentElement.dataset.titleOrig;
    document.querySelectorAll('.lang button').forEach(function (b) {
      var on = b.getAttribute('data-lang') === lang;
      b.classList.toggle('on', on); b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    document.dispatchEvent(new CustomEvent('tunr:lang', { detail: { lang: lang } }));
  }

  function setLang(l) {
    if (l === lang) return;
    lang = l;
    try { localStorage.setItem(KEY, l); } catch (e) {}
    // ?lang= in de adresbalk zou de keuze bij herladen overrulen: bijwerken
    try {
      var u = new URL(location.href);
      if (u.searchParams.has('lang')) { u.searchParams.set('lang', l); history.replaceState(null, '', u.toString()); }
    } catch (e) {}
    apply();
  }

  window.TunrI18n = { get lang() { return lang; }, t: function (key, nl) { return lang === 'en' && EN[key] != null ? EN[key] : nl; }, set: setLang, apply: apply };

  function init() {
    document.querySelectorAll('.lang button').forEach(function (b) {
      b.addEventListener('click', function () { setLang(b.getAttribute('data-lang')); });
    });
    apply();

    // nav donker bij scrollen
    var nav = document.querySelector('nav.top');
    if (nav) {
      var onScroll = function () { nav.classList.toggle('scrolled', window.scrollY > 24 || document.body.classList.contains('sub-page')); };
      onScroll(); window.addEventListener('scroll', onScroll, { passive: true });
      // menu voor smalle schermen
      var tg = nav.querySelector('.navtoggle');
      if (tg) {
        var close = function () { nav.classList.remove('menu-open'); tg.setAttribute('aria-expanded', 'false'); };
        tg.addEventListener('click', function () {
          var open = !nav.classList.contains('menu-open');
          nav.classList.toggle('menu-open', open); tg.setAttribute('aria-expanded', open ? 'true' : 'false');
        });
        nav.querySelectorAll('.links a').forEach(function (a) { a.addEventListener('click', close); });
        document.addEventListener('keydown', function (e) { if (e.key === 'Escape') close(); });
      }
    }
    document.querySelectorAll('[data-year]').forEach(function (el) { el.textContent = new Date().getFullYear() > 2026 ? '2026–' + new Date().getFullYear() : '2026'; });
    if (window.TUNR) {
      document.querySelectorAll('[data-repo]').forEach(function (a) { a.href = window.TUNR.repo + (a.getAttribute('data-repo') || ''); });
      document.querySelectorAll('[data-version]').forEach(function (el) { el.textContent = window.TUNR.version; });
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();

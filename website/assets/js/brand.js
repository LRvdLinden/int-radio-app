// Tunr: de (werk)naam, het domein en de repo staan alleen hier (plus sitemap.xml, robots.txt en de canonical-links).
// Bij een nieuwe naam volstaat zoek-en-vervang op "Tunr".
window.TUNR = {
  name: 'Tunr',
  domain: 'https://tunr.app',
  repo: 'https://github.com/LRvdLinden/int-radio-app',
  version: '1.0.0',
  radioBrowser: 'https://www.radio-browser.info',
  // App-links: leeg tot de apps in de winkels staan ("Binnenkort").
  appStore: '',
  googlePlay: ''
};

// Woordmerk (TunrLogo) als HTML, voor plekken die met JS worden opgebouwd.
// Statische pagina's hebben dezelfde opmaak direct in de HTML.
window.TUNR.logoHTML = function (cls) {
  return '<span class="logo ' + (cls || '') + '" aria-label="' + window.TUNR.name + '"><b>' + window.TUNR.name.toUpperCase() + '</b>' +
    '<svg viewBox="0 0 100 14" preserveAspectRatio="none" aria-hidden="true">' +
    '<defs><linearGradient id="tl-g" x1="0" x2="1"><stop offset="0" stop-color="#FF5A1F"/><stop offset="1" stop-color="#FFB020"/></linearGradient></defs>' +
    '<path d="M4 1.5v4.5M15.5 3.5v2.5M27 1.5v4.5M38.5 3.5v2.5M50 1.5v4.5M61.5 3.5v2.5M73 1.5v4.5M84.5 3.5v2.5M96 1.5v4.5" stroke="#ffffff8c" stroke-width="1.6" stroke-linecap="round" vector-effect="non-scaling-stroke"/>' +
    '<rect x="1" y="8.6" width="98" height="3.4" rx="1.7" fill="url(#tl-g)"/>' +
    '<path d="M58.5 0.5v13" stroke="#FFB020" stroke-width="2.6" stroke-linecap="round" vector-effect="non-scaling-stroke"/></svg></span>';
};

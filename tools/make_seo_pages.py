#!/usr/bin/env python3
"""Landingspagina's voor zoekmachines: /radio/ (landen), /radio/<cc>/ (land) en /radio/<cc>/<slug>/ (zender).

Draait in de workflow Website vlak voor het uploaden; de pagina's staan niet in git (.gitignore: website/radio/),
zodat ze bij elke upload vers zijn. Bron: Radio Browser (één verzoek voor de landen + één per land, met de
User-Agent van Tunr). Alleen feitelijke gegevens uit Radio Browser (naam, plaats, taal, genres, stream), geen
overgenomen beschrijvingen. Logo: eerst de vaste icoontabel website/assets/data/icons/<CC>.json (zoals de apps),
anders het favicon uit Radio Browser, anders een monogram.

Verder, in dezelfde map als de site (--site):
  - sitemap.xml: de bestaande vermeldingen blijven, alles onder /radio/ wordt opnieuw geschreven;
  - index.html: het blok "Populaire zenders" (tussen <!-- BEGIN seo-popular --> en <!-- END seo-popular -->)
    en de FAQPage-JSON-LD (#ld-faq, NL, gelijk aan de zichtbare vragen; i18n.js wisselt hem naar EN).

Is Radio Browser onbereikbaar, dan gebruikt hij de laatste momentopname (--cache, in de workflow bewaard met
actions/cache); zonder momentopname schrijft hij niets en stopt hij zonder fout, zodat de site gewoon uploadt.

Gebruik:
  python3 tools/make_seo_pages.py                       # echt (Radio Browser), schrijft in website/
  python3 tools/make_seo_pages.py --demo --site /tmp/x  # testdata uit tools/fixtures/seo_stations.json
"""
import argparse, datetime, html, json, os, random, re, sys, time, unicodedata, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOMAIN = 'https://tunr.online'
UA = {'User-Agent': 'Tunr/1.0.0 (+https://tunr.online)'}


def _presskit_url():
    """Footer-link PressKit: {stats.url}/functions/v1/presskit (Supabase-URL uit website/assets/js/brand.js)."""
    try:
        with open(os.path.join(ROOT, 'website', 'assets', 'js', 'brand.js'), encoding='utf-8') as fh:
            m = re.search(r"stats:\s*\{\s*url:\s*'(https://[a-z0-9-]+\.supabase\.co)/?'", fh.read())
        if m:
            return m.group(1) + '/functions/v1/presskit'
    except OSError:
        pass
    return DOMAIN + '/presskit/Tunr-PressKit.zip'   # zonder backend: direct (niet geteld)


PRESSKIT_URL = _presskit_url()
NL_COUNTRIES = {'NL', 'BE', 'SR'}          # pagina's met Nederlands als standaardtaal
FORCE = ['NL', 'BE', 'SR']                 # altijd een landpagina, ook buiten de top
POPULAR = [('NL', 10), ('BE', 2), ('GB', 2), ('US', 2), ('DE', 2)]   # homepage: "Populaire zenders"
PAL = [('#FF5A1F', '#FFB020'), ('#7C3AED', '#DB2777'), ('#0EA5E9', '#22D3EE'), ('#10B981', '#84CC16'),
       ('#F43F5E', '#FB923C'), ('#6366F1', '#06B6D4'), ('#EAB308', '#F97316'), ('#14B8A6', '#3B82F6')]
with open(os.path.join(ROOT, 'tools', 'seo_names.json'), encoding='utf-8') as _fh:
    _NAMES = json.load(_fh)
COUNTRY = _NAMES['countries']
LANGS = _NAMES['languages']
# Nederlands: "in het Verenigd Koninkrijk"; Engels: "in the Netherlands"
NL_IN = {'GB': 'het Verenigd Koninkrijk', 'US': 'de Verenigde Staten', 'AE': 'de Verenigde Arabische Emiraten',
         'PH': 'de Filipijnen', 'DO': 'de Dominicaanse Republiek', 'BS': 'de Bahama’s', 'MV': 'de Maldiven',
         'SC': 'de Seychellen', 'KY': 'de Kaaimaneilanden', 'FO': 'de Faeröer', 'VA': 'Vaticaanstad'}
EN_THE = {'NL', 'US', 'GB', 'PH', 'DO', 'AE', 'BS', 'CZ', 'MV', 'SC', 'KY', 'FO', 'CF', 'CD', 'CG', 'GM', 'VA'}


# ---------------------------------------------------------------- hulpjes
def esc(s):
    return html.escape(str(s if s is not None else ''), quote=True)


def cname(cc, lang):
    v = COUNTRY.get(cc)
    return (v[0] if lang == 'nl' else v[1]) if v else cc


def c_in(cc, lang):
    """Landnaam na "in": "het Verenigd Koninkrijk", "the Netherlands"."""
    if lang == 'nl':
        return NL_IN.get(cc, cname(cc, 'nl'))
    n = cname(cc, 'en')
    return ('the ' + n) if cc in EN_THE else n


def fold(s):
    return unicodedata.normalize('NFKD', s or '').encode('ascii', 'ignore').decode('ascii')


def norm_key(name):
    """Zelfde naamsleutel als tools/make_station_icons.py (tabel "n")."""
    f = ''.join(c for c in unicodedata.normalize('NFKD', name or '') if unicodedata.category(c) != 'Mn').lower()
    return ''.join(c for c in f if unicodedata.category(c)[0] == 'L' or unicodedata.category(c) == 'Nd')


def slugify(name):
    s = re.sub(r'[^a-z0-9]+', '-', fold(name).lower()).strip('-')
    return s[:60].strip('-')


def mono(name):
    w = [x for x in re.sub(r'[^\w ]', '', name, flags=re.U).split() if x]
    if not w:
        return '?'
    if len(w) > 1 and w[1].isdigit():
        return (w[0][0] + w[1]) if len(w[1]) <= 2 else w[1][:3]
    return (w[0][0] + w[1][0] if len(w) > 1 else w[0][:2]).upper()


def pal(name):
    h = 0
    for ch in name:
        h = (h * 31 + ord(ch)) & 0xFFFFFFFF
    return PAL[h % len(PAL)]


def flag(cc):
    return ''.join(chr(ord(c) + 127397) for c in cc.upper()) if re.fullmatch(r'[A-Z]{2}', cc or '') else '🌐'


def join_words(items, lang):
    items = list(items)
    if len(items) <= 1:
        return ''.join(items)
    return ', '.join(items[:-1]) + (' en ' if lang == 'nl' else ' and ') + items[-1]


def fit(parts, lo, hi):
    """Zin uit verplichte + optionele delen: (tekst, optioneel). Neemt optionele delen mee zolang de tekst ≤ hi blijft."""
    out = ''
    for text, optional in parts:
        if not optional:
            out += text
        elif len(out + text) <= hi:
            out += text
    if len(out) > hi:
        cut = out[:hi - 1]
        out = cut[:cut.rfind(' ')].rstrip(',;:') + '…'
    return out


def tx(tag, nl, en, dl, attrs=''):
    """Element met de standaardtaal (dl) als inhoud en de andere taal in data-en / data-nl (assets/js/i18n.js)."""
    main, other, ol = (nl, en, 'en') if dl == 'nl' else (en, nl, 'nl')
    alt = f' data-{ol}="{esc(other)}"' if other != main else ''
    return f'<{tag}{attrs}{alt}>{main}</{tag}>'


def ta(attr, nl, en, dl):
    """Attribuut (alt, title, aria-label) in de standaardtaal plus data-<taal>-<attr> voor de andere taal."""
    main, other, ol = (nl, en, 'en') if dl == 'nl' else (en, nl, 'nl')
    s = f' {attr}="{esc(main)}"'
    if other != main:
        s += f' data-{ol}-{attr}="{esc(other)}"'
    return s


def ldjson(obj):
    return '<script type="application/ld+json">' + json.dumps(obj, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/') + '</script>'


def https(u):
    u = (u or '').strip()
    if not re.match(r'^https?://', u, re.I):
        return ''
    return re.sub(r'^http:', 'https:', u, flags=re.I)


# ---------------------------------------------------------------- gegevens
def get(url, timeout=30):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode('utf-8'))


def servers():
    names = []
    try:
        names = ['https://' + s['name'] for s in get('https://all.api.radio-browser.info/json/servers', 15)]
    except Exception:
        pass
    random.shuffle(names)
    return list(dict.fromkeys(names + ['https://de1.api.radio-browser.info', 'https://de2.api.radio-browser.info',
                                       'https://fi1.api.radio-browser.info']))


KEEP = ('stationuuid', 'name', 'tags', 'countrycode', 'state', 'language', 'languagecodes', 'codec', 'bitrate',
        'favicon', 'homepage', 'votes', 'clickcount')


def fetch(n_countries, per):
    """Momentopname uit Radio Browser: {'generated', 'countries': [{cc, count}], 'stations': {cc: [...]}}."""
    for base in servers():
        try:
            t0 = time.time()
            cs = get(f'{base}/json/countries?hidebroken=true&order=stationcount&reverse=true', 30)
            cs = [c for c in cs if re.fullmatch(r'[A-Z]{2}', (c.get('iso_3166_1') or '').upper()) and c.get('stationcount')]
            cs.sort(key=lambda c: -int(c['stationcount']))
            counts = {}
            for c in cs:
                cc = c['iso_3166_1'].upper()
                counts[cc] = counts.get(cc, 0) + int(c['stationcount'])
            pick = [cc for cc, _ in sorted(counts.items(), key=lambda kv: -kv[1])][:n_countries]
            pick += [cc for cc in FORCE if cc not in pick and cc in counts]
            stations = {}
            for cc in pick:
                q = urllib.parse.urlencode(dict(countrycode=cc, hidebroken='true', order='clickcount', reverse='true',
                                                limit=max(per * 4, 200)))
                raw = get(f'{base}/json/stations/search?{q}', 40)
                stations[cc] = [{k: s.get(k) for k in KEEP} for s in raw]
                time.sleep(0.3)
            print(f'Radio Browser ({base}): {len(pick)} landen in {time.time() - t0:.0f} s')
            return {'generated': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                    'countries': [{'cc': cc, 'count': counts[cc]} for cc in pick], 'stations': stations}
        except Exception as e:
            print(f'server mislukt: {base}: {e}')
    return None


_icons = {}


def icon_table(site, cc):
    if cc not in _icons:
        try:
            with open(os.path.join(site, 'assets', 'data', 'icons', cc + '.json'), encoding='utf-8') as fh:
                _icons[cc] = json.load(fh)
        except Exception:
            _icons[cc] = {}
    return _icons[cc]


def clean_tags(tags, cc):
    out = []
    skip = {cname(cc, 'nl').lower(), cname(cc, 'en').lower(), cc.lower(), 'radio', 'fm', 'am', 'online', 'live', 'internet radio', 'webradio'}
    for t in re.split(r'[,;/]', tags or ''):
        t = re.sub(r'\s+', ' ', t).strip().lower()
        if 2 <= len(t) <= 24 and t not in skip and not re.search(r'https?:|www\.|\d{3,}', t) and t not in out:
            out.append(t)
    return out[:5]


def prepare(site, snap, per):
    """Per land de beste `per` zenders: ontdubbeld op naam, met slug, logo, genres, plaats."""
    countries = []
    for c in snap['countries']:
        cc = c['cc'].upper()
        seen, slugs, rows = set(), set(), []
        for s in snap['stations'].get(cc, []):
            name = re.sub(r'\s+', ' ', (s.get('name') or '')).strip(' -_|·')
            if not (2 <= len(name) <= 80) or re.match(r'^https?://', name, re.I) or not s.get('stationuuid'):
                continue
            k = norm_key(name)
            if not k or k in seen:
                continue
            seen.add(k)
            slug = slugify(name) or ('zender-' + s['stationuuid'][:8])
            base, i = slug, 2
            while slug in slugs or slug in ('index',):
                slug = f'{base}-{i}'
                i += 1
            slugs.add(slug)
            tab = icon_table(site, cc)
            logo = (tab.get('u') or {}).get(s['stationuuid']) or (tab.get('n') or {}).get(k) or ''
            logo = https(logo) or https(s.get('favicon'))
            if logo.lower().split('?')[0].endswith('.ico'):
                logo = ''
            state = re.sub(r'\s+', ' ', (s.get('state') or '')).strip()
            if state.lower() in (cname(cc, 'nl').lower(), cname(cc, 'en').lower()) or len(state) > 40:
                state = ''
            codes = [x.strip().lower() for x in (s.get('languagecodes') or '').split(',') if x.strip()][:2]
            langs_nl = [LANGS[x][0] for x in codes if x in LANGS]
            langs_en = [LANGS[x][1] for x in codes if x in LANGS]
            if not langs_en:
                raw = [x.strip() for x in (s.get('language') or '').split(',') if x.strip()][:2]
                langs_en = langs_nl = [x[:1].upper() + x[1:] for x in raw if len(x) <= 20]
            home = https(s.get('homepage')) if re.match(r'^https?://[^/\s]+\.[a-z]{2,}', s.get('homepage') or '', re.I) else ''
            rows.append({'id': s['stationuuid'], 'name': name, 'slug': slug, 'cc': cc, 'logo': logo,
                         'tags': clean_tags(s.get('tags'), cc), 'state': state, 'langs_nl': langs_nl, 'langs_en': langs_en,
                         'codec': (s.get('codec') or '').strip()[:12], 'bitrate': int(s.get('bitrate') or 0),
                         'home': home, 'rank': len(rows) + 1})
            if len(rows) >= per:
                break
        if rows:
            countries.append({'cc': cc, 'count': int(c.get('count') or len(rows)), 'stations': rows})
    return countries


# ---------------------------------------------------------------- opmaak
NAV_LOGO = ('<svg viewBox="0 0 100 14" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="tl-g" x1="0" x2="1">'
            '<stop offset="0" stop-color="#FF5A1F"/><stop offset="1" stop-color="#FFB020"/></linearGradient></defs>'
            '<path d="M4 1.5v4.5M15.5 3.5v2.5M27 1.5v4.5M38.5 3.5v2.5M50 1.5v4.5M61.5 3.5v2.5M73 1.5v4.5M84.5 3.5v2.5M96 1.5v4.5" '
            'stroke="#ffffff8c" stroke-width="1.6" stroke-linecap="round" vector-effect="non-scaling-stroke"/>'
            '<rect x="1" y="8.6" width="98" height="3.4" rx="1.7" fill="url(#tl-g)"/><path d="M58.5 0.5v13" stroke="#FFB020" '
            'stroke-width="2.6" stroke-linecap="round" vector-effect="non-scaling-stroke"/></svg>')
PLAY = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5.6v12.8c0 .8.9 1.3 1.6.8l10-6.4c.6-.4.6-1.3 0-1.7l-10-6.3C8.9 4.3 8 4.8 8 5.6z"/></svg>'
GLOBE = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
         '<circle cx="12" cy="12" r="9.2"/><path d="M2.8 12h18.4M12 2.8c2.6 2.6 3.8 5.6 3.8 9.2s-1.2 6.6-3.8 9.2M12 2.8C9.4 5.4 8.2 8.4 8.2 12s1.2 6.6 3.8 9.2"/></svg>')


def page(path, dl, title, desc, body, ld, og_image=''):
    """Volledige pagina. title/desc = (nl, en); path = '/radio/nl/' enz."""
    url = DOMAIN + path
    t_main, t_other, ol = (title[0], title[1], 'en') if dl == 'nl' else (title[1], title[0], 'nl')
    d_main, d_other = (desc[0], desc[1]) if dl == 'nl' else (desc[1], desc[0])
    loc, loc2 = ('nl_NL', 'en_GB') if dl == 'nl' else ('en_GB', 'nl_NL')
    T = lambda nl, en, attrs='': tx('a' if attrs.startswith(' href') else 'span', nl, en, dl, attrs)
    nav = (f'<nav class="top"{ta("aria-label", "Hoofdmenu", "Main menu", dl)}>'
           '<div class="wrap">'
           f'<a href="/" class="logo" aria-label="Tunr"><b>TUNR</b>{NAV_LOGO}</a>'
           '<div class="links" id="navlinks">'
           + T('Functies', 'Features', ' href="/#features"') + T('Podcasts', 'Podcasts', ' href="/#podcasts"')
           + T('Wereldkaart', 'World map', ' href="/#kaart"') + T('Zenders', 'Stations', ' href="/radio/" aria-current="page"')
           + T('Download', 'Download', ' href="/#download"') + T('FAQ', 'FAQ', ' href="/#faq"') +
           '</div><div class="right">'
           + tx('a', 'Luister nu', 'Listen now', dl, ' class="btn sm navweb" href="/web/"') +
           '<div class="lang" role="group" aria-label="Taal / Language"><button type="button" data-lang="nl">NL</button><button type="button" data-lang="en">EN</button></div>'
           '<button class="navtoggle" type="button" aria-expanded="false" aria-controls="navlinks" aria-label="Menu">'
           '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path class="l1" d="M4 7h16"/><path class="l2" d="M4 12h16"/><path class="l3" d="M4 17h16"/></svg></button>'
           '</div></div></nav>')
    foot = ('<footer class="foot"><div class="wrap"><div class="top">'
            f'<div><a href="/" class="logo" aria-label="Tunr"><b>TUNR</b>{NAV_LOGO}</a>'
            + tx('p', 'Alle radio en podcasts van de wereld. Op elk scherm.', 'All the world\'s radio and podcasts. On every screen.', dl, ' class="tag"') +
            '</div><div class="fcols">'
            '<div class="fcol"><h3>Tunr</h3>' + T('Webspeler', 'Web player', ' href="/web/"') + T('Zenders per land', 'Radio stations by country', ' href="/radio/" aria-current="page"')
            + T('Changelog', 'Changelog', ' href="/changelog/"') + '</div>'
            '<div class="fcol">' + tx('h3', 'Info', 'Info', dl) + T('Privacy', 'Privacy', ' href="/privacy/"') + T('Voorwaarden', 'Terms', ' href="/voorwaarden/"')
            + T('Cookie-instellingen', 'Cookie settings', ' href="#" data-consent-link') + '</div>'
            '<div class="fcol">' + tx('h3', 'Meer', 'More', dl) + '<a href="https://www.radio-browser.info" rel="noopener">Radio Browser</a>'
            f'<a href="{esc(PRESSKIT_URL)}" rel="nofollow" download="Tunr-PressKit.zip">PressKit</a></div>'
            '</div></div>'
            + tx('p', 'Tunr host zelf geen radiostreams: elke zender speelt rechtstreeks vanaf de server van de omroep. Zendergegevens: '
                 '<a href="https://www.radio-browser.info" rel="noopener">Radio Browser</a> (open community-database). Namen en logo\'s van zenders zijn eigendom van de betreffende omroepen.',
                 'Tunr doesn\'t host any radio streams: every station plays directly from the broadcaster\'s server. Station data: '
                 '<a href="https://www.radio-browser.info" rel="noopener">Radio Browser</a> (open community database). Station names and logos belong to their broadcasters.',
                 dl, ' class="disc"') +
            '<p class="copy">© <span data-year>2026</span> Tunr</p></div></footer>')
    head = (f'<!doctype html>\n<html lang="{dl}">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            f'<title>{esc(t_main)}</title>\n<meta name="tunr-title-{ol}" content="{esc(t_other)}">\n'
            f'<meta name="description" content="{esc(d_main)}" data-{ol}="{esc(d_other)}">\n'
            f'<link rel="alternate" hreflang="nl" href="{url}?lang=nl">\n<link rel="alternate" hreflang="en" href="{url}?lang=en">\n'
            f'<link rel="alternate" hreflang="x-default" href="{url}">\n'
            '<meta property="og:type" content="website">\n<meta property="og:site_name" content="Tunr">\n'
            f'<meta property="og:url" content="{url}">\n<meta property="og:title" content="{esc(t_main)}" data-{ol}="{esc(t_other)}">\n'
            f'<meta property="og:description" content="{esc(d_main)}" data-{ol}="{esc(d_other)}">\n'
            f'<meta property="og:locale" content="{loc}">\n<meta property="og:locale:alternate" content="{loc2}">\n'
            f'<meta property="og:image" content="{esc(og_image or DOMAIN + "/assets/img/og-image.png")}">\n'
            '<meta name="twitter:card" content="summary_large_image">\n<meta name="theme-color" content="#0A0A0C">\n'
            '<link rel="icon" href="/favicon.png">\n<link rel="apple-touch-icon" href="/apple-touch-icon.png">\n'
            '<link rel="stylesheet" href="/assets/css/site.css?v=2">\n<link rel="stylesheet" href="/assets/css/radio.css?v=1">\n'
            + ''.join(ldjson(x) + '\n' for x in ld) +
            '</head>\n<body class="sub-page radio-page">\n'
            + tx('a', 'Naar de inhoud', 'Skip to content', dl, ' class="skip" href="#main"') + '\n')
    return (head + nav + '\n<main id="main">\n' + body + '\n</main>\n' + foot + '\n'
            '<script defer src="/assets/js/brand.js?v=3"></script>\n'
            '<script defer src="/assets/js/consent.js?v=1" data-base="/"></script>\n'
            '<script defer src="/assets/js/i18n.js?v=4"></script>\n</body>\n</html>\n')


def art(s, cls, size, dl, eager=False):
    a, b = pal(s['name'])
    img = ''
    if s['logo']:
        load = 'fetchpriority="high"' if eager else 'loading="lazy"'
        img = (f'<img src="{esc(s["logo"])}"{ta("alt", "Logo van " + s["name"], s["name"] + " logo", dl)} width="{size}" height="{size}" '
               f'{load} decoding="async" referrerpolicy="no-referrer" onerror="this.remove()">')
    return f'<span class="art {cls}" style="background:linear-gradient(135deg,{a},{b})"><b aria-hidden="true">{esc(mono(s["name"]))}</b>{img}</span>'


def web_url(s):
    return '/web/#/station/' + urllib.parse.quote(s['id'])


def st_url(s):
    return f'/radio/{s["cc"].lower()}/{s["slug"]}/'


def place(s, lang):
    c = cname(s['cc'], lang)
    return f'{s["state"]}, {c}' if s['state'] else c


def cap(t):
    return t[:1].upper() + t[1:]


def crumbs(items, dl):
    """items = [(nl, en, path|None)]"""
    li = []
    for nl, en, p in items:
        inner = tx('a', esc(nl), esc(en), dl, f' href="{p}"') if p else tx('span', esc(nl), esc(en), dl, ' aria-current="page"')
        li.append(f'<li>{inner}</li>')
    return f'<nav class="crumbs"{ta("aria-label", "Kruimelpad", "Breadcrumb", dl)}><ol>' + ''.join(li) + '</ol></nav>'


def crumbs_ld(items, dl):
    return {'@context': 'https://schema.org', '@type': 'BreadcrumbList', 'itemListElement': [
        {'@type': 'ListItem', 'position': i + 1, 'name': nl if dl == 'nl' else en, **({'item': DOMAIN + p} if p else {})}
        for i, (nl, en, p) in enumerate(items)]}


def sub_line(s, lang):
    parts = []
    if s['state']:
        parts.append(s['state'])
    if s['tags']:
        parts.append(', '.join(s['tags'][:3]))
    return ' · '.join(parts) or cname(s['cc'], lang)


def station_row(s, dl, rank=True):
    nm = esc(s['name'])
    return ('<li class="srow">'
            + (f'<span class="rk">{s["rank"]}</span>' if rank else '')
            + art(s, 'sm', 56, dl) +
            f'<a class="nm" href="{st_url(s)}"><b>{nm}</b>' + tx('small', esc(sub_line(s, 'nl')), esc(sub_line(s, 'en')), dl) + '</a>'
            f'<a class="play" href="{web_url(s)}"{ta("aria-label", "Luister naar " + s["name"] + " in de webspeler", "Listen to " + s["name"] + " in the web player", dl)}>'
            + PLAY + tx('span', 'Luister', 'Listen', dl) + '</a></li>')


def country_chips(countries, cur, dl):
    out = []
    for c in sorted(countries, key=lambda c: cname(c['cc'], dl)):
        cur_attr = ' aria-current="page"' if c['cc'] == cur else ''
        out.append(f'<a href="/radio/{c["cc"].lower()}/"{cur_attr}><span aria-hidden="true">{flag(c["cc"])}</span>'
                   + tx('span', esc(cname(c['cc'], 'nl')), esc(cname(c['cc'], 'en')), dl) + '</a>')
    return '<div class="cchips">' + ''.join(out) + '</div>'


def fmt_n(n, lang):
    return f'{n:,}'.replace(',', '.' if lang == 'nl' else ',')


# ---------------------------------------------------------------- pagina's
def country_page(c, countries):
    cc, sts = c['cc'], c['stations']
    dl = 'nl' if cc in NL_COUNTRIES else 'en'
    n = len(sts)
    cn_nl, cn_en, in_nl, in_en = cname(cc, 'nl'), cname(cc, 'en'), c_in(cc, 'nl'), c_in(cc, 'en')
    path = f'/radio/{cc.lower()}/'

    def title(lang):
        if lang == 'nl':
            for t in (f'Online radio luisteren in {in_nl} – {n} zenders | Tunr', f'Online radio luisteren in {in_nl} | Tunr',
                      f'Radio luisteren in {in_nl} | Tunr', f'Radio {cn_nl} | Tunr'):
                if len(t) <= 60:
                    return t
        for t in (f'Listen to radio online in {in_en} – {n} stations | Tunr', f'Listen to radio online in {in_en} | Tunr',
                  f'Radio stations in {in_en} | Tunr', f'Radio {cn_en} | Tunr'):
            if len(t) <= 60:
                return t
        return f'Radio {cn_en[:40]} | Tunr'
    top3 = [s['name'] for s in sts[:3]]
    d_nl = fit([(f'Online radio luisteren in {in_nl}: ', False), (f'de {n} populairste radiozenders', False),
                (f', zoals {join_words(top3, "nl")}', True), ('. Gratis en live, zonder account', False),
                (', in je browser of de Tunr-app', True), ('.', False)], 140, 158)
    d_en = fit([(f'Listen to radio online in {in_en}: ', False), (f'the {n} most popular radio stations', False),
                (f', including {join_words(top3, "en")}', True), ('. Free and live, no account', False),
                (', in your browser or the Tunr app', True), ('.', False)], 140, 158)
    cr = [('Tunr', 'Tunr', '/'), ('Zenders', 'Stations', '/radio/'), (cn_nl, cn_en, None)]
    rows = ''.join(station_row(s, dl) for s in sts)
    intro_nl = (f'Luister gratis en live naar radiozenders uit {in_nl}, zonder account en zonder iets te installeren. Hieronder staan de {n} '
                f'populairste zenders, gerangschikt op wat luisteraars in de open zenderlijst van Radio Browser het meest kiezen. Tik op een zender '
                'voor meer informatie, of luister meteen in de webspeler van Tunr.')
    intro_en = (f'Listen to radio stations from {in_en} for free and live, with no account and nothing to install. Below are the {n} '
                'most popular stations, ranked by what listeners choose most in the open Radio Browser station directory. Tap a station '
                'for more details, or start listening right away in the Tunr web player.')
    more_nl = (f'In totaal vind je in Tunr zo\'n {fmt_n(c["count"], "nl")} zenders uit {in_nl}: landelijke en regionale omroepen, lokale radio, '
               'nieuws, muziek en sport. Op de <a href="/web/#/map">wereldkaart</a> ontdek je ze per plaats.')
    more_en = (f'Tunr has around {fmt_n(c["count"], "en")} stations from {in_en} in total: national and regional broadcasters, local radio, '
               'news, music and sports. Discover them by location on the <a href="/web/#/map">world radio map</a>.')
    body = (f'<div class="wrap">{crumbs(cr, dl)}'
            '<header class="phead rhead">'
            f'<p class="kicker"><span aria-hidden="true">{flag(cc)}</span> ' + tx('span', 'Radio per land', 'Radio by country', dl) + '</p>'
            + tx('h1', esc(f'Online radio luisteren in {in_nl}'), esc(f'Listen to radio online in {in_en}'), dl, ' class="ttl"')
            + tx('p', esc(intro_nl), esc(intro_en), dl, ' class="sub"') +
            '<div class="acts">'
            f'<a class="btn" href="{web_url(sts[0])}">{PLAY}' + tx('span', esc(f'Luister {sts[0]["name"]}'), esc(f'Listen to {sts[0]["name"]}'), dl) + '</a>'
            f'<a class="btn ghost" href="/web/#/map">{GLOBE}' + tx('span', 'Open de wereldkaart', 'Open the world map', dl) + '</a>'
            '</div></header>'
            '<section aria-labelledby="top-h">'
            + tx('h2', esc(f'Populaire radiozenders in {in_nl}'), esc(f'Popular radio stations in {in_en}'), dl, ' class="h3" id="top-h"')
            + f'<ol class="slist">{rows}</ol></section>'
            '<section class="rmore">' + tx('p', more_nl, more_en, dl, ' class="txt"') + '</section>'
            '<section aria-labelledby="oc-h">' + tx('h2', 'Radio uit andere landen', 'Radio from other countries', dl, ' class="h3" id="oc-h"')
            + country_chips(countries, cc, dl) + '</section></div>')
    ld = [crumbs_ld(cr, dl), {'@context': 'https://schema.org', '@type': 'ItemList',
          'name': f'Online radio luisteren in {in_nl}' if dl == 'nl' else f'Listen to radio online in {in_en}',
          'itemListElement': [{'@type': 'ListItem', 'position': i + 1, 'url': DOMAIN + st_url(s), 'name': s['name']} for i, s in enumerate(sts)]}]
    return path, page(path, dl, (title('nl'), title('en')), (d_nl, d_en), body, ld)


def similar(s, sts, k=6):
    tags = set(s['tags'])
    others = [x for x in sts if x['id'] != s['id']]
    scored = sorted(others, key=lambda x: (-len(tags & set(x['tags'])), x['rank']))
    return scored[:k]


def station_page(s, c, countries):
    cc = s['cc']
    dl = 'nl' if cc in NL_COUNTRIES else 'en'
    name = s['name']
    cn_nl, cn_en = cname(cc, 'nl'), cname(cc, 'en')
    pl_nl, pl_en = place(s, 'nl'), place(s, 'en')
    path = st_url(s)

    def title(lang):
        cands = ([f'{name} online luisteren – gratis live radio | Tunr', f'{name} online luisteren | Tunr', f'{name} live | Tunr']
                 if lang == 'nl' else
                 [f'Listen to {name} online – free live radio | Tunr', f'Listen to {name} online | Tunr', f'{name} live | Tunr'])
        for t in cands:
            if len(t) <= 60:
                return t
        return name[:52].rstrip() + '… | Tunr'
    g = s['tags'][:3]
    d_nl = fit([(f'Luister {name} gratis online', False), (f': live radio uit {pl_nl}', False),
                (f' met {join_words(g, "nl")}', True), ('. Zonder account, in de webspeler', False),
                (' en de Tunr-app voor iPhone, Android en Apple TV', True), (' of de Tunr-app', True), ('.', False),
                (' Ook in de auto.', True)], 140, 158)
    d_en = fit([(f'Listen to {name} online for free', False), (f': live radio from {pl_en}', False),
                (f' with {join_words(g, "en")}', True), ('. No account needed, in the web player', False),
                (' and the Tunr app for iPhone, Android and Apple TV', True), (' or the Tunr app', True), ('.', False),
                (' In the car too.', True)], 140, 158)
    cr = [('Tunr', 'Tunr', '/'), ('Zenders', 'Stations', '/radio/'), (cn_nl, cn_en, f'/radio/{cc.lower()}/'), (name, name, None)]
    nm = esc(name)
    stream = (f'{s["codec"]}' + (f', {s["bitrate"]} kbps' if s['bitrate'] else '')) if s['codec'] else (f'{s["bitrate"]} kbps' if s['bitrate'] else '')
    gl = [cap(t) for t in s['tags']]
    about_nl = f'{nm} is een radiozender uit {esc(pl_nl)}.'
    about_en = f'{nm} is a radio station from {esc(pl_en if not s["state"] else s["state"] + ", " + c_in(cc, "en"))}.'
    if gl:
        about_nl += f' Genres volgens Radio Browser: {esc(join_words(gl, "nl"))}.'
        about_en += f' Genres according to Radio Browser: {esc(join_words(gl, "en"))}.'
    if s['langs_nl']:
        about_nl += f' De uitzendingen zijn in het {esc(join_words(s["langs_nl"], "nl"))}.'
        about_en += f' It broadcasts in {esc(join_words(s["langs_en"], "en"))}.'
    about_nl += (' In Tunr luister je gratis en zonder account naar de livestream' + (f' ({esc(stream)})' if stream else '') +
                 ': in de webspeler, en binnenkort in de apps voor iPhone, iPad, Mac, Apple TV, CarPlay, Android en Android TV.')
    about_en += (' With Tunr you can listen to the live stream' + (f' ({esc(stream)})' if stream else '') +
                 ' for free and without an account: in the web player, and soon in the apps for iPhone, iPad, Mac, Apple TV, CarPlay, Android and Android TV.')
    facts = [(('Land', 'Country'), (f'{flag(cc)} {esc(cn_nl)}', f'{flag(cc)} {esc(cn_en)}'))]
    if s['state']:
        facts.append((('Plaats of regio', 'City or region'), (esc(s['state']), esc(s['state']))))
    if s['langs_nl']:
        facts.append((('Taal', 'Language'), (esc(', '.join(s['langs_nl'])), esc(', '.join(s['langs_en'])))))
    if gl:
        facts.append((('Genres', 'Genres'), (esc(', '.join(gl)), esc(', '.join(gl)))))
    if stream:
        facts.append((('Stream', 'Stream'), (esc(stream), esc(stream))))
    if s['home']:
        host = re.sub(r'^www\.', '', urllib.parse.urlparse(s['home']).netloc)
        link = f'<a href="{esc(s["home"])}" rel="nofollow noopener" target="_blank">{esc(host)}</a>'
        facts.append((('Website', 'Website'), (link, link)))
    dlh = ''.join('<div>' + tx('dt', k[0], k[1], dl) + tx('dd', v[0], v[1], dl) + '</div>' for k, v in facts)
    sim = similar(s, c['stations'])
    sim_html = ''.join(station_row(x, dl, rank=False) for x in sim)
    chips = ''.join(f'<span class="gtag">{esc(t)}</span>' for t in gl[:4])
    sub_nl = f'Live radio uit {esc(pl_nl)}'
    sub_en = f'Live radio from {esc(pl_en)}'
    body = (f'<div class="wrap">{crumbs(cr, dl)}'
            '<header class="shero">' + art(s, 'xl', 160, dl, eager=True) +
            '<div class="shc">'
            f'<p class="kicker"><span class="live">Live</span> ' + tx('span', sub_nl, sub_en, dl) + '</p>'
            + tx('h1', f'{nm} online luisteren', f'Listen to {nm} online', dl, ' class="ttl"')
            + (f'<div class="tags">{chips}</div>' if chips else '') +
            '<div class="acts">'
            f'<a class="btn big" href="{web_url(s)}">{PLAY}' + tx('span', 'Luister live in de webspeler', 'Listen live in the web player', dl) + '</a>'
            + (tx('a', 'Website van de zender', 'Station website', dl, f' class="btn ghost" href="{esc(s["home"])}" rel="nofollow noopener" target="_blank"') if s['home'] else '') +
            '</div></div></header>'
            '<div class="sgrid"><section class="about" aria-labelledby="ab-h">'
            + tx('h2', f'Over {nm}', f'About {nm}', dl, ' class="h3" id="ab-h"')
            + tx('p', about_nl, about_en, dl, ' class="txt"')
            + tx('p', f'Meer radio uit {esc(c_in(cc, "nl"))}? Bekijk de <a href="/radio/{cc.lower()}/">populairste zenders uit {esc(c_in(cc, "nl"))}</a> of ontdek zenders uit de hele wereld op de <a href="/web/#/map">kaart</a>.',
                 f'Want more radio from {esc(c_in(cc, "en"))}? See the <a href="/radio/{cc.lower()}/">most popular stations in {esc(c_in(cc, "en"))}</a> or discover stations from around the world on the <a href="/web/#/map">map</a>.',
                 dl, ' class="txt"') +
            '</section><aside class="facts" aria-labelledby="fa-h">'
            + tx('h2', 'Gegevens', 'Details', dl, ' class="h3" id="fa-h"') + f'<dl>{dlh}</dl>'
            + tx('p', 'Bron: <a href="https://www.radio-browser.info" rel="noopener">Radio Browser</a>. Klopt er iets niet? Verbeter het daar.',
                 'Source: <a href="https://www.radio-browser.info" rel="noopener">Radio Browser</a>. Something wrong? Fix it there.', dl, ' class="src"') +
            '</aside></div>'
            + (('<section aria-labelledby="sim-h">' + tx('h2', 'Vergelijkbare zenders', 'Similar stations', dl, ' class="h3" id="sim-h"')
                + f'<ul class="slist two">{sim_html}</ul>'
                + tx('a', esc(f'Alle populaire zenders uit {c_in(cc, "nl")} →'), esc(f'All popular stations in {c_in(cc, "en")} →'), dl, f' class="more" href="/radio/{cc.lower()}/"')
                + '</section>') if sim else '') +
            '</div>')
    rs = {'@context': 'https://schema.org', '@type': 'RadioStation', '@id': DOMAIN + path + '#station', 'name': name,
          'url': DOMAIN + path, 'address': {'@type': 'PostalAddress', 'addressCountry': cc, **({'addressLocality': s['state']} if s['state'] else {})}}
    if s['logo']:
        rs['logo'] = s['logo']
        rs['image'] = s['logo']
    if s['tags']:
        rs['genre'] = gl
    if s['home']:
        rs['sameAs'] = s['home']
    if s['langs_en']:
        rs['knowsLanguage'] = s['langs_en']
    return path, page(path, dl, (title('nl'), title('en')), (d_nl, d_en), body, [rs, crumbs_ld(cr, dl)])


def index_page(countries):
    dl = 'nl'
    path = '/radio/'
    total = sum(c['count'] for c in countries)
    cards = []
    for c in sorted(countries, key=lambda c: -c['count']):
        cc = c['cc']
        cards.append(f'<li><a href="/radio/{cc.lower()}/"><span class="fl" aria-hidden="true">{flag(cc)}</span><span class="t">'
                     + tx('b', esc(cname(cc, 'nl')), esc(cname(cc, 'en')), dl)
                     + tx('small', f'{fmt_n(c["count"], "nl")} zenders', f'{fmt_n(c["count"], "en")} stations', dl) + '</span></a></li>')
    cr = [('Tunr', 'Tunr', '/'), ('Zenders', 'Stations', None)]
    intro_nl = (f'Online radio luisteren uit de hele wereld: kies een land en ontdek de populairste radiozenders, van landelijke omroepen tot lokale '
                f'radio. Samen goed voor ruim {fmt_n(total, "nl")} zenders uit {len(countries)} landen; in de webspeler en de apps vind je er nog veel meer, uit meer dan 200 landen.')
    intro_en = (f'Listen to radio online from around the world: pick a country and discover its most popular radio stations, from national broadcasters to local '
                f'radio. Together that\'s over {fmt_n(total, "en")} stations from {len(countries)} countries; the web player and the apps have many more, from over 200 countries.')
    pop = next((c for c in countries if c['cc'] == 'NL'), countries[0])
    body = (f'<div class="wrap">{crumbs(cr, dl)}<header class="phead rhead">'
            + tx('h1', 'Radiozenders per land', 'Radio stations by country', dl, ' class="ttl"')
            + tx('p', esc(intro_nl), esc(intro_en), dl, ' class="sub"') +
            f'<div class="acts"><a class="btn" href="/web/">{PLAY}' + tx('span', 'Luister nu in je browser', 'Listen now in your browser', dl) + '</a>'
            f'<a class="btn ghost" href="/web/#/map">{GLOBE}' + tx('span', 'Open de wereldkaart', 'Open the world map', dl) + '</a></div></header>'
            '<section aria-labelledby="cl-h">' + tx('h2', 'Kies een land', 'Choose a country', dl, ' class="h3" id="cl-h"')
            + '<ul class="cgrid">' + ''.join(cards) + '</ul></section>'
            '<section aria-labelledby="pp-h">' + tx('h2', esc(f'Populair in {c_in(pop["cc"], "nl")}'), esc(f'Popular in {c_in(pop["cc"], "en")}'), dl, ' class="h3" id="pp-h"')
            + '<ol class="slist two">' + ''.join(station_row(s, dl) for s in pop['stations'][:12]) + '</ol></section></div>')
    ld = [crumbs_ld(cr, dl), {'@context': 'https://schema.org', '@type': 'ItemList', 'name': 'Radiozenders per land',
          'itemListElement': [{'@type': 'ListItem', 'position': i + 1, 'url': f'{DOMAIN}/radio/{c["cc"].lower()}/', 'name': cname(c['cc'], 'nl')}
                              for i, c in enumerate(sorted(countries, key=lambda c: -c['count']))]}]
    return path, page(path, dl, ('Radiozenders per land – online radio luisteren | Tunr', 'Radio stations by country – listen online | Tunr'),
                      (fit([(f'Online radio luisteren per land: de populairste radiozenders uit {len(countries)} landen, van landelijke omroepen tot lokale radio.', False),
                            (' Gratis en live, zonder account.', True)], 140, 158),
                       fit([(f'Listen to radio online by country: the most popular radio stations from {len(countries)} countries, from national broadcasters to local radio.', False),
                            (' Free and live, no account.', True)], 140, 158)), body, ld)


# ---------------------------------------------------------------- homepage, sitemap
def popular_block(countries):
    by = {c['cc']: c for c in countries}
    items = []
    for cc, k in POPULAR:
        for s in (by.get(cc) or {}).get('stations', [])[:k]:
            items.append(s)
    out = []
    for s in items:
        out.append(f'<li><a href="{st_url(s)[1:]}">' + art(s, '', 44, 'nl') + '<span class="t">'
                   f'<b>{esc(s["name"])}</b>' + tx('small', esc(f'{flag(s["cc"])} {place(s, "nl")}'), esc(f'{flag(s["cc"])} {place(s, "en")}'), 'nl') + '</span></a></li>')
    return ''.join(out)


def update_home(site, countries):
    p = os.path.join(site, 'index.html')
    s = open(p, encoding='utf-8').read()
    if countries:
        s = re.sub(r'(<!-- BEGIN seo-popular[^>]*-->).*?(<!-- END seo-popular -->)',
                   lambda m: m.group(1) + popular_block(countries) + m.group(2), s, count=1, flags=re.S)
    s = refresh_faq_ld(s)
    open(p, 'w', encoding='utf-8').write(s)


def strip_tags(h):
    return html.unescape(re.sub(r'<[^>]+>', '', h)).strip()


def refresh_faq_ld(s):
    """#ld-faq (NL) gelijk aan de zichtbare vragen op de homepage."""
    qa = re.findall(r'<details><summary[^>]*>(.*?)</summary><div class="a"[^>]*>(.*?)</div></details>', s, flags=re.S)
    if not qa:
        return s
    obj = {'@context': 'https://schema.org', '@type': 'FAQPage', '@id': DOMAIN + '/#faq', 'inLanguage': 'nl',
           'mainEntity': [{'@type': 'Question', 'name': strip_tags(q), 'acceptedAnswer': {'@type': 'Answer', 'text': strip_tags(a)}} for q, a in qa]}
    js = json.dumps(obj, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    return re.sub(r'(<script type="application/ld\+json" id="ld-faq">).*?(</script>)', lambda m: m.group(1) + js + m.group(2), s, count=1, flags=re.S)


def url_block(path):
    u = DOMAIN + path
    alts = (f'    <xhtml:link rel="alternate" hreflang="nl" href="{u}?lang=nl"/>\n'
            f'    <xhtml:link rel="alternate" hreflang="en" href="{u}?lang=en"/>\n'
            f'    <xhtml:link rel="alternate" hreflang="x-default" href="{u}"/>\n')
    return ''.join(f'  <url>\n    <loc>{loc}</loc>\n{alts}  </url>\n' for loc in (u, u + '?lang=nl', u + '?lang=en'))


def update_sitemap(site, paths):
    p = os.path.join(site, 'sitemap.xml')
    s = open(p, encoding='utf-8').read()
    s = re.sub(r'\s*<url>\s*<loc>[^<]*/radio/[^<]*</loc>.*?</url>', '', s, flags=re.S)
    s = s.replace('</urlset>', ''.join(url_block(x) for x in paths) + '</urlset>')
    open(p, 'w', encoding='utf-8').write(s)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--site', default=os.path.join(ROOT, 'website'))
    ap.add_argument('--demo', action='store_true', help='testdata uit tools/fixtures/seo_stations.json')
    ap.add_argument('--fixture', default=os.path.join(ROOT, 'tools', 'fixtures', 'seo_stations.json'))
    ap.add_argument('--cache', default=os.environ.get('SEO_CACHE', os.path.join(ROOT, '.seo-cache.json')))
    ap.add_argument('--countries', type=int, default=40)
    ap.add_argument('--per', type=int, default=60)
    a = ap.parse_args()
    t0 = time.time()
    site = os.path.abspath(a.site)

    if a.demo:
        snap = json.load(open(a.fixture, encoding='utf-8'))
    else:
        snap = fetch(a.countries, a.per)
        if snap:
            try:
                json.dump(snap, open(a.cache, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
            except Exception as e:
                print('momentopname niet bewaard:', e)
        elif os.path.exists(a.cache):
            print('::warning::Radio Browser onbereikbaar: landingspagina\'s uit de laatste momentopname')
            snap = json.load(open(a.cache, encoding='utf-8'))
        else:
            print('::warning::Radio Browser onbereikbaar en geen momentopname: geen landingspagina\'s gemaakt')
            update_home(site, [])
            return 0

    countries = prepare(site, snap, a.per)
    if not countries:
        print('::warning::geen zenders: geen landingspagina\'s gemaakt')
        return 0
    out = os.path.join(site, 'radio')
    pages = [index_page(countries)]
    for c in countries:
        pages.append(country_page(c, countries))
        for s in c['stations']:
            pages.append(station_page(s, c, countries))
    # oude pagina's weg (de map is helemaal gegenereerd)
    if os.path.isdir(out):
        import shutil
        shutil.rmtree(out)
    for path, doc in pages:
        d = os.path.join(site, path.strip('/'))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'index.html'), 'w', encoding='utf-8') as fh:
            fh.write(doc)
    update_sitemap(site, [p for p, _ in pages])
    update_home(site, countries)
    n_st = sum(len(c['stations']) for c in countries)
    print(f'{len(pages)} pagina\'s ({len(countries)} landen, {n_st} zenders) in {time.time() - t0:.1f} s → {out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

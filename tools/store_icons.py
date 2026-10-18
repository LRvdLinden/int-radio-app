#!/usr/bin/env python3
"""Precieze app-iconen via de stores (workflow Icons, job site-icons; docs/SPEC.md §1). Gebruikt door
tools/make_site_icons.py, geen eigen hoofdprogramma.

Twee bronnen naast de vage iTunes-zoekfunctie van tools/make_station_icons.py:

1. **Store-links op de website van de zender** (de homepage haalt make_site_icons.py toch al op):
   `<meta name="apple-itunes-app" content="app-id=…">` (smart app banner), links naar `apps.apple.com/…/id…`,
   `<meta name="google-play-app" content="app-id=…">`, links naar `play.google.com/store/apps/details?id=…`,
   `market://details?id=…` en `<link rel="alternate" href="android-app://…">`.
   - App Store-id → `https://itunes.apple.com/lookup?id=<id>` (één verzoek, exact; ≥ 3 s ertussen, max. 600 per
     run) → `artworkUrl512` → `/256x256bb.png`;
   - Play-pakket → `https://play.google.com/store/apps/details?id=<pkg>&hl=en&gl=US` → `og:image`
     (play-lh.googleusercontent.com) → `=s256`.
   Of de app bij een zender hoort, beslist `link_related` per zendernaam (dezelfde match als make_station_icons.py,
   iets ruimer omdat de site zelf naar de app linkt).
2. **Google Play-zoekfunctie** voor populaire zenders zonder App Store- of Play-icoon:
   `https://play.google.com/store/search?q=<naam>&c=apps&hl=<taal>&gl=<land>` → resultaten (pakket, titel, icoon)
   → dezelfde zekere naammatch als make_station_icons.py (`ms.score_app`), daarna de app-pagina (titel +
   ontwikkelaar opnieuw gecontroleerd, `play_accept`) → `og:image`.

Elk icoon wordt gecontroleerd zoals de website-iconen (Pillow: vierkant, ≥ 128 px, niet effen).
Cache `play-cache.json` (branch icons-data, samengevoegd door tools/icons_data_save.sh):
  "ios:<id>" / "gp:<pkg>" / "q:<CC>|<naamsleutel>" → {"u": url of "", "d": datum, "t": titel, …};
missers na 30 dagen en treffers na 120 dagen opnieuw.
"""
import html as htmllib, json, os, re, sys, threading, time, urllib.error, urllib.parse
from datetime import datetime, timedelta
from html.parser import HTMLParser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_station_icons as ms  # noqa: E402

ITUNES_LOOKUP = 'https://itunes.apple.com/lookup'
PLAY = 'https://play.google.com'
PLAY_HOST = 'play-lh.googleusercontent.com'
MISS_DAYS = 30
HIT_DAYS = 120
MAX_LINKS = 3           # app-id's / pakketten per website
MAX_PLAY_PAGE = 3_000_000
PLAY_ACCEPT = 84        # zie play_accept
BUSY = (403, 429, 503)  # HTTP-codes voor "te veel verzoeken"

# taal voor de Play-zoekfunctie per land (titels zijn meestal gelijk; dit maakt de ranglijst lokaler)
HL = {
    'NL': 'nl', 'BE': 'nl', 'DE': 'de', 'AT': 'de', 'CH': 'de', 'FR': 'fr', 'LU': 'fr', 'ES': 'es', 'MX': 'es',
    'AR': 'es', 'CO': 'es', 'CL': 'es', 'PE': 'es', 'VE': 'es', 'EC': 'es', 'IT': 'it', 'PT': 'pt', 'BR': 'pt',
    'PL': 'pl', 'CZ': 'cs', 'SK': 'sk', 'HU': 'hu', 'RO': 'ro', 'BG': 'bg', 'GR': 'el', 'TR': 'tr', 'RU': 'ru',
    'UA': 'uk', 'RS': 'sr', 'HR': 'hr', 'SI': 'sl', 'SE': 'sv', 'NO': 'no', 'DK': 'da', 'FI': 'fi', 'JP': 'ja',
    'KR': 'ko', 'CN': 'zh', 'TW': 'zh-TW', 'ID': 'id', 'TH': 'th', 'VN': 'vi',
}

_PKG = r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+'
_RE_APPLE = re.compile(r'(?:apps|itunes)\.apple\.com/[^"\'\s<>]{0,120}?/id(\d{6,12})', re.I)
_RE_PLAY = re.compile(r'play\.google\.com/store/apps/details\?(?:[^"\'\s<>#]{0,200}?(?:&|&amp;))?id=(' + _PKG + ')',
                      re.I)
_RE_MARKET = re.compile(r'market://details\?(?:[^"\'\s<>#]{0,200}?(?:&|&amp;))?id=(' + _PKG + ')', re.I)
_RE_ANDROID_APP = re.compile(r'android-app://(' + _PKG + ')', re.I)
_RE_APP_ID = re.compile(r'app-id\s*=\s*([A-Za-z0-9_.]+)', re.I)


# ---------------------------------------------------------------- store-links op de website

class _MetaParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ios, self.gp = [], []

    def handle_starttag(self, tag, attrs):
        if tag != 'meta':
            return
        a = {k.lower(): (v or '').strip() for k, v in attrs if k}
        name = (a.get('name') or a.get('property') or '').lower()
        m = _RE_APP_ID.search(a.get('content') or '')
        if not m:
            return
        if name == 'apple-itunes-app' and re.fullmatch(r'\d{6,12}', m.group(1)):
            self.ios.append(m.group(1))
        elif name == 'google-play-app' and re.fullmatch(_PKG, m.group(1)):
            self.gp.append(m.group(1))

    handle_startendtag = handle_starttag


def _ranked(found, limit=MAX_LINKS):
    """Vaakst genoemde eerst, bij gelijk aantal de eerste vermelding; dubbele weg."""
    counts, first = {}, {}
    for i, x in enumerate(found):
        counts[x] = counts.get(x, 0) + 1
        first.setdefault(x, i)
    return sorted(counts, key=lambda x: (-counts[x], first[x]))[:limit]


def store_links(html):
    """{'ios': [app-id's], 'gp': [pakketten]} uit de HTML van een homepage (banner-meta's tellen dubbel)."""
    html = str(html or '')
    p = _MetaParser()
    try:
        p.feed(html)
        p.close()
    except Exception:
        pass
    raw = html.replace('\\/', '/')  # links in ingebedde JSON
    ios = p.ios * 2 + _RE_APPLE.findall(raw)
    gp = p.gp * 2 + _RE_PLAY.findall(raw) + _RE_MARKET.findall(raw) + _RE_ANDROID_APP.findall(raw)
    return {'ios': _ranked(ios), 'gp': _ranked(gp)}


# ---------------------------------------------------------------- URL's normaliseren

def play_icon_url(url):
    """play-lh-icoon als variant van 256 px: een `=w…-h…`/`=s…`-achtervoegsel wordt `=s256`. Anders ''."""
    u = htmllib.unescape(str(url or '').strip())
    if u.startswith('//'):
        u = 'https:' + u
    m = re.fullmatch(r'https?://play-lh\.googleusercontent\.com/([A-Za-z0-9_\-/]+?)(=[A-Za-z0-9_\-]*)?', u)
    if not m:
        return ''
    return f'https://{PLAY_HOST}/{m.group(1)}=s256'


def strip_play_title(t):
    """"Radio 538 - Apps on Google Play" → "Radio 538" (ook andere talen)."""
    t = htmllib.unescape(str(t or '')).strip()
    t = re.sub(r'\s+[-–—|]\s+[^-–—|]*Google Play\s*$', '', t)
    return t.strip()


# ---------------------------------------------------------------- de match

def _fake_app(title, seller='', seller_url='', genre='Music'):
    # ms.score_app wil een genre en artwork; voor Play bestaan die niet zo, de naam beslist
    return {'trackName': title, 'primaryGenreName': genre, 'sellerName': seller, 'sellerUrl': seller_url,
            'artworkUrl512': 'https://is1-ssl.mzstatic.com/x/512x512bb.jpg'}


def title_score(name, title, cc='', homepage='', seller='', seller_url='', genre='Music'):
    return ms.score_app(name, _fake_app(title, seller, seller_url, genre), cc, cc, homepage)


def link_related(name, title, homepage='', cc='', seller='', seller_url='', genre='Music'):
    """Hoort de app (waar de website van de zender naar linkt) bij deze zendernaam? De gewone match (≥ 70), of
    een onderscheidend kernwoord van de zender / de websitenaam zit in de appnaam (de site linkt er zelf naar:
    "Qmusic Non-Stop" op qmusic.nl → app "Qmusic")."""
    if not title or (genre and genre not in ms.GENRES):
        return False
    if title_score(name, title, cc, homepage, seller, seller_url, genre) >= 70:
        return True
    t = ms.norm_key(title)
    words = [w for w in ms.core_tokens(name) if len(w) >= 4 and not ms.is_generic(w)]
    words += [h for h in ms.host_tokens(homepage) if len(h) >= 4 and not ms.is_generic(ms.core(h))]
    return bool(t) and any(w in t for w in words)


def play_accept(name, title, cc='', homepage='', developer=''):
    """Strenge check voor een Play-zoekresultaat (op de app-pagina): exact dezelfde (kern)naam, of de kernnaam in
    de appnaam én de ontwikkelaar hoort bij de website van de zender (fan-apps met de zendernaam vallen af)."""
    return title_score(name, title, cc, homepage, developer) >= PLAY_ACCEPT


# ---------------------------------------------------------------- Play-pagina's lezen

class _PlaySearchParser(HTMLParser):
    """Resultaten van de Play-zoekpagina: per pakket (uit `/store/apps/details?id=`-links) de teksten en
    play-lh-plaatjes binnen die link. Werkt los van de class-namen (die veranderen vaak)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.items, self.order, self.stack = {}, [], []

    def _cur(self):
        return self.stack[-1][1] if self.stack else None

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or '') for k, v in attrs if k}
        if tag == 'a':
            m = re.search(r'/store/apps/details\?(?:[^"#]*?&)?id=(' + _PKG + ')', a.get('href') or '')
            if m:
                pkg = m.group(1)
                if pkg not in self.items:
                    self.items[pkg] = {'pkg': pkg, 'texts': [], 'imgs': []}
                    self.order.append(pkg)
                self.stack.append(('a', pkg))
                if a.get('aria-label'):
                    self.items[pkg]['texts'].append(a['aria-label'].strip())
            else:
                self.stack.append(('a', None))
            return
        pkg = self._cur()
        if pkg and tag == 'img':
            for key in ('src', 'data-src', 'srcset'):
                u = (a.get(key) or '').split()[0] if a.get(key) else ''
                if PLAY_HOST in u:
                    self.items[pkg]['imgs'].append(u)
                    break
            if a.get('alt'):
                self.items[pkg]['texts'].append(a['alt'].strip())

    def handle_endtag(self, tag):
        if tag == 'a' and self.stack:
            self.stack.pop()

    def handle_data(self, data):
        pkg = self._cur()
        t = (data or '').strip()
        if pkg and t:
            self.items[pkg]['texts'].append(t)


def _looks_like_title(t):
    t = t.strip()
    if not t or len(t) > 80:
        return False
    if re.fullmatch(r'[\d.,\s]+(?:star|stars|sterren|★)?', t, re.I) or re.search(r'\bstar(s)?\b.*\d|\d.*\bstar', t, re.I):
        return False
    return t.lower() not in {'install', 'installeren', 'free', 'gratis', 'ad', 'advertentie'}


def parse_play_search(html, limit=10):
    """[{'pkg', 'titles', 'icon'}] in de volgorde van de zoekpagina. Valt terug op kale pakket-links (bijv. alleen
    in de ingebedde AF_initDataCallback-data) als er geen bruikbare <a>-kaarten zijn."""
    html = str(html or '')
    p = _PlaySearchParser()
    try:
        p.feed(html)
        p.close()
    except Exception:
        pass
    out = []
    for pkg in p.order:
        it = p.items[pkg]
        titles = list(dict.fromkeys(t for t in it['texts'] if _looks_like_title(t)))
        out.append({'pkg': pkg, 'titles': titles[:4], 'icon': play_icon_url(it['imgs'][0]) if it['imgs'] else ''})
    if not out:
        raw = html.replace('\\u003d', '=').replace('\\u0026', '&').replace('\\/', '/')
        for pkg in _ranked(re.findall(r'/store/apps/details\?id=(' + _PKG + ')', raw), limit):
            out.append({'pkg': pkg, 'titles': [], 'icon': ''})
    return out[:limit]


class _AppPageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.og_image = self.og_title = self.item_image = self.title = self.developer = ''
        self._in_title = False
        self._dev = None  # (id uit de link, tekst) zolang we in de eerste ontwikkelaarslink zitten

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or '').strip() for k, v in attrs if k}
        prop = (a.get('property') or a.get('name') or '').lower()
        if tag == 'meta':
            if prop == 'og:image' and not self.og_image:
                self.og_image = a.get('content', '')
            elif prop == 'og:title' and not self.og_title:
                self.og_title = a.get('content', '')
            elif a.get('itemprop') == 'image' and not self.item_image:
                self.item_image = a.get('content', '')
        elif tag == 'img' and a.get('itemprop') == 'image' and not self.item_image:
            self.item_image = a.get('src', '')
        elif tag == 'title':
            self._in_title = True
        elif tag == 'a' and not self.developer and self._dev is None:
            m = re.search(r'/store/apps/(?:developer|dev)\?id=([^&"#]+)', a.get('href') or '')
            if m:
                self._dev = [urllib.parse.unquote_plus(m.group(1)), '']

    def handle_endtag(self, tag):
        if tag == 'title':
            self._in_title = False
        elif tag == 'a' and self._dev is not None:
            dev_id, text = self._dev
            # /developer?id= bevat de naam, /dev?id= een getal
            self.developer = text or ('' if dev_id.isdigit() else dev_id)
            self._dev = None if not self.developer else self._dev

    def handle_data(self, data):
        t = (data or '').strip()
        if self._in_title and t and not self.title:
            self.title = t
        if self._dev is not None and t and not self._dev[1]:
            self._dev[1] = t


def parse_play_app(html):
    """{'icon': play-lh-URL van 256 px of '', 'title': appnaam, 'developer': ontwikkelaar} van een app-pagina."""
    p = _AppPageParser()
    try:
        p.feed(str(html or ''))
        p.close()
    except Exception:
        pass
    icon = play_icon_url(p.og_image) or play_icon_url(p.item_image)
    return {'icon': icon, 'title': strip_play_title(p.og_title or p.title), 'developer': p.developer}


# ---------------------------------------------------------------- netwerk (via de Fetcher van make_site_icons)

class Spacer:
    """Minstens `delay` seconden tussen verzoeken (thread-veilig)."""

    def __init__(self, delay):
        self.delay, self.last, self.lock = delay, 0.0, threading.Lock()

    def wait(self, stop=None):
        with self.lock:
            pause = self.last + self.delay - time.time()
            if pause > 0:
                if stop is not None:
                    stop.wait(pause)
                else:
                    time.sleep(pause)
            self.last = time.time()


def lookup_ios(fetcher, spacer, app_id, cc, verify):
    """Cache-item voor een App Store-id: {'u', 't', 'g', 's', 'su'} (u = '' als niet gevonden/ongeldig)."""
    stores = [cc.lower()] if cc else []
    stores.append('')
    for store in dict.fromkeys(stores):
        q = {'id': app_id}
        if store:
            q['country'] = store
        spacer.wait(fetcher.stop)
        _, _, data = fetcher.get(f'{ITUNES_LOOKUP}?{urllib.parse.urlencode(q)}', 500_000, accept='application/json')
        res = (json.loads(data.decode('utf-8', 'replace')).get('results') or [])
        res = [r for r in res if str(r.get('trackId') or app_id) == str(app_id)]
        if not res:
            continue
        r = res[0]
        url = ms.icon_url(r.get('artworkUrl512') or r.get('artworkUrl100'))
        e = {'t': r.get('trackName') or '', 'g': r.get('primaryGenreName') or '', 's': r.get('sellerName') or '',
             'su': r.get('sellerUrl') or ''}
        ok = url and verify(url)
        e['u'] = url if ok else ''
        if not ok:
            e['r'] = 'image'
        return e
    return {'u': '', 'r': 'not-found'}


def fetch_play_app(fetcher, spacer, pkg, cc=''):
    """{'icon', 'title', 'developer'} van een Play-app-pagina (eerst gl=US, daarna het land) of None."""
    for gl in dict.fromkeys(['US'] + ([cc] if cc else [])):
        spacer.wait(fetcher.stop)
        url = f'{PLAY}/store/apps/details?' + urllib.parse.urlencode({'id': pkg, 'hl': 'en', 'gl': gl})
        try:
            _, _, data = fetcher.get(url, 800_000, accept='text/html', truncate=True)
        except urllib.error.HTTPError as e:
            if e.code in BUSY:
                raise  # te veel verzoeken: de aanroeper stopt met Play voor deze run
            continue
        except Exception:
            continue
        info = parse_play_app(data.decode('utf-8', 'replace'))
        if info['icon']:
            return info
    return None


def lookup_play_pkg(fetcher, spacer, pkg, cc, verify):
    info = fetch_play_app(fetcher, spacer, pkg, cc)
    if not info:
        return {'u': '', 'r': 'not-found'}
    ok = verify(info['icon'])
    return {'u': info['icon'] if ok else '', 't': info['title'], 's': info['developer'],
            **({} if ok else {'r': 'image'})}


def search_play(fetcher, spacer, name, cc, homepage, verify, max_pages=2):
    """Cache-item voor een Play-zoekopdracht: {'u', 'p', 't', 's'} of {'u': '', 'r': reden}."""
    q = {'q': ms.search_term(name), 'c': 'apps', 'hl': HL.get(cc, 'en'), 'gl': cc or 'US'}
    spacer.wait(fetcher.stop)
    _, _, data = fetcher.get(f'{PLAY}/store/search?{urllib.parse.urlencode(q)}', MAX_PLAY_PAGE,
                             accept='text/html', truncate=True)
    results = parse_play_search(data.decode('utf-8', 'replace'))
    ranked = []
    for i, r in enumerate(results):
        sc = max([title_score(name, t, cc, homepage) for t in r['titles']] or [0])
        if sc >= 70 or not r['titles']:
            ranked.append((-sc, i, r))
    ranked.sort(key=lambda x: (x[0], x[1]))
    if not ranked:
        return {'u': '', 'r': 'no-match'}
    for _, _, r in ranked[:max_pages]:
        info = fetch_play_app(fetcher, spacer, r['pkg'], cc)
        if not info or not play_accept(name, info['title'], cc, homepage, info['developer']):
            continue
        if verify(info['icon']):
            return {'u': info['icon'], 'p': r['pkg'], 't': info['title'], 's': info['developer']}
    return {'u': '', 'r': 'no-match'}


# ---------------------------------------------------------------- cache

def is_fresh(entry, today):
    try:
        d = datetime.strptime((entry or {}).get('d', ''), '%Y-%m-%d').date()
    except Exception:
        return False
    return today - d < timedelta(days=HIT_DAYS if entry.get('u') else MISS_DAYS)

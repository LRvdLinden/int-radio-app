#!/usr/bin/env python3
"""Zendericonen van de eigen website van de zender (workflow Icons, job site-icons; docs/SPEC.md §1).

Snelle tweede bron naast tools/make_station_icons.py (App Store, ~20 verzoeken per minuut): het icoon dat een
telefoon toont als je de site van de zender op het beginscherm zet. Geen limiet van één dienst, dus veel zenders
per run (standaard top 300 van 80 landen + top 3000 wereldwijd, ~40 minuten).

Per website (host van `homepage`, één keer per host):
1. de homepage ophalen (redirects volgen, eigen browser-User-Agent, max. 1,5 MB, 10 s) en kandidaten zoeken, in
   volgorde: iconen uit het web-app-manifest (`<link rel="manifest">`, vierkant, ≥ 192 px, liefst purpose "any"),
   `apple-touch-icon(-precomposed)` (grootste `sizes`), `<link rel="icon" sizes="192x192|256x256|512x512">`,
   `og:image` (alleen als hij vierkant blijkt); niets gevonden → `/apple-touch-icon.png` en
   `/apple-touch-icon-precomposed.png` in de root;
2. de kandidaat controleren: downloaden (max. 2 MB), PNG/JPEG/WebP (Pillow), (bijna) vierkant (0,85–1,18),
   ≥ 128 px, niet (bijna) effen, geen standaardicoon van een CMS (URL-regels + vingerafdruk; een vingerafdruk die
   bij ≥ 4 sites zonder gemeenschappelijke naam voorkomt is een standaardicoon en wordt overal geweigerd);
3. alleen https: een http-icoon telt alleen als hetzelfde adres via https ook klopt.

Daarna (tools/store_icons.py; tijdsbudget verdeeld 55 % websites / 18 % store-links / 27 % Play-zoeken):
4. store-links op dezelfde homepage (smart app banner, App Store- en Play-links) → exact het App Store-icoon (iTunes
   lookup, ≥ 3 s ertussen, max. 600) of het Google Play-icoon (app-pagina, og:image, ≥ 2 s ertussen);
5. Google Play-zoekfunctie (`--play true|false`) voor de top 100 per land + top 1000 wereldwijd zonder App Store-
   of Play-icoon, met dezelfde zekere naammatch als make_station_icons.py.
Per zender: App Store-app van de website > Play-app van de website > Play-zoekresultaat > website-icoon.

Cache per host (`site-cache.json` op de branch icons-data, met de gevonden store-links): treffers na 120 dagen en
missers na 60 dagen opnieuw (items zonder "sl" = nog zonder store-links bekeken: opnieuw). Store-cache
`play-cache.json` (zie tools/store_icons.py): missers na 30 dagen, treffers na 120 dagen opnieuw.
Uitvoer: dezelfde tabellen als make_station_icons.py (website/assets/data/icons/<CC>.json), samengevoegd via
tools/merge_icon_tables.py: App Store > Google Play > website; er verdwijnt niets.

Gebruik:
    python3 tools/make_site_icons.py [--cache pad] [--play-cache pad] [--budget-min 46] [--play true|false]
                                     [--countries 80] [--per-country 300] [--world 3000] [--workers 32]
                                     [--store-max 600] [--play-max 300] [--existing map] [--out map]
                                     [--offline] [--limit N]
"""
import argparse, io, ipaddress, json, os, re, signal, socket, sys, threading, time, urllib.error, urllib.parse
import urllib.request, warnings
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout, as_completed
from datetime import date, datetime, timedelta
from html.parser import HTMLParser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_station_icons as ms  # noqa: E402
import merge_icon_tables as mt  # noqa: E402
import store_icons as st  # noqa: E402

ROOT = ms.ROOT
OUT_DIR = ms.OUT_DIR
BOT_UA = 'Mozilla/5.0 (compatible; TunrIconBot/1.0; +https://tunr.online)'
TIMEOUT = 10
MAX_HTML = 1_500_000
MAX_MANIFEST = 300_000
MAX_IMG = 2_000_000
MIN_SIDE = 128
RATIO = (0.85, 1.18)
MISS_DAYS = 60
HIT_DAYS = 120
MAX_TRIES = 6           # kandidaten per site
SHARED_HOST = 5         # een host met meer verschillende zendernamen is een platform, geen zendersite
GENERIC_HOSTS = 4       # zelfde vingerafdruk bij zoveel sites zonder gemeenschappelijke naam = standaardicoon

# platforms, sociale media en verzamelsites: hun icoon is niet dat van de zender
SKIP_HOSTS = {
    'facebook.com', 'fb.com', 'fb.me', 'instagram.com', 'twitter.com', 'x.com', 'youtube.com', 'youtu.be',
    'tiktok.com', 'linkedin.com', 't.me', 'telegram.me', 'whatsapp.com', 'wa.me', 'vk.com', 'ok.ru',
    'soundcloud.com', 'mixcloud.com', 'mixlr.com', 'spotify.com', 'apple.com', 'google.com', 'goo.gl', 'bit.ly',
    'linktr.ee', 'tunein.com', 'radio.net', 'radio.de', 'radio.fr', 'radio.at', 'radio.it', 'radio.es',
    'radio.pt', 'radio.dk', 'radio.se', 'radio.pl', 'radio.co', 'radio.garden', 'streema.com',
    'onlineradiobox.com', 'mytuner-radio.com', 'zeno.fm', 'laut.fm', 'shoutcast.com', 'icecast.org',
    'radionomy.com', 'live365.com', 'iheart.com', 'myradiostream.com', 'caster.fm', 'radiojar.com', 'airtime.pro',
    'streamtheworld.com', 'radioking.com', 'radio-browser.info', 'wikipedia.org', 'blogspot.com',
    'wordpress.com', 'wixsite.com', 'weebly.com', 'jimdo.com', 'jimdofree.com', 'webnode.page', 'github.com',
    'radiolisten.de', 'radio-assistant.com', 'listenlive.co', 'fmstream.org', 'surfmusic.de', 'rcast.net',
    'getmeradio.com', 'radios.com.br', 'radio-online.com', 'liveonlineradio.net',
}
# standaardiconen van CMS'en en bouwplatforms (in het pad of op deze hosts)
REJECT_PATH = ('wp-includes/images/w-logo', 'wix', 'squarespace', 'blogger', 'weebly', 'default-favicon',
               '/i/webclip.png', 'shopify-favicon')
REJECT_HOSTS = {'s.w.org', 's0.wp.com', 's1.wp.com', 's2.wp.com', 'www.wix.com', 'wix.com', 'www.blogger.com',
                'blogger.com', 'assets.squarespace.com', 'www.weebly.com'}
# vingerafdrukken (dhash, 16 hex) van bekende standaardiconen; aangevuld met wat elke run zelf als standaard herkent
DEFAULT_HASHES = set()

try:
    from PIL import Image, ImageStat
    Image.MAX_IMAGE_PIXELS = 25_000_000
    warnings.simplefilter('error', Image.DecompressionBombWarning)
except ImportError:  # alleen nodig voor het echte werk (verify); de parsertests draaien zonder
    Image = ImageStat = None


# ---------------------------------------------------------------- HTML en manifest

class HeadParser(HTMLParser):
    """Verzamelt <link>, <meta property="og:image"> en <base href> (de rest van de pagina doet niet mee)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links, self.og, self.base = [], [], ''

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or '').strip() for k, v in attrs if k}
        if tag == 'link' and a.get('href'):
            self.links.append({'rel': set(a.get('rel', '').lower().split()), 'href': a['href'],
                               'sizes': a.get('sizes', ''), 'type': a.get('type', '').lower()})
        elif tag == 'meta' and (a.get('property') or a.get('name') or '').lower() in ('og:image', 'og:image:url',
                                                                                         'og:image:secure_url'):
            if a.get('content'):
                self.og.append(a['content'])
        elif tag == 'base' and a.get('href') and not self.base:
            self.base = a['href']

    handle_startendtag = handle_starttag


def parse_sizes(s):
    """"192x192 512X512 any" → [(192, 192), (512, 512)]."""
    out = []
    for part in str(s or '').lower().split():
        m = re.fullmatch(r'(\d{1,5})x(\d{1,5})', part)
        if m:
            out.append((int(m.group(1)), int(m.group(2))))
    return out


def square_side(sizes):
    """Grootste vierkante maat uit een sizes-lijst (0 = geen vierkante)."""
    return max([w for w, h in sizes if w == h] or [0])


def resolve(base, href):
    href = str(href or '').strip()
    if not href or href.lower().startswith(('data:', 'javascript:', 'blob:')):
        return ''
    try:
        u = urllib.parse.urljoin(base, href)
        p = urllib.parse.urlparse(u)
    except ValueError:
        return ''
    if p.scheme not in ('http', 'https') or not p.hostname:
        return ''
    return urllib.parse.urlunparse(p._replace(fragment=''))


def bad_ext(url):
    path = urllib.parse.urlparse(url).path.lower()
    return path.endswith(('.ico', '.svg', '.svgz'))


def reject_url(url):
    """Standaardiconen van CMS'en en bestandstypen die we niet gebruiken (ico/svg). True = weigeren."""
    try:
        p = urllib.parse.urlparse(url)
    except ValueError:
        return True
    host, path = (p.hostname or '').lower(), p.path.lower()
    if host in REJECT_HOSTS or bad_ext(url) or path.endswith('/favicon.ico'):
        return True
    return any(x in path for x in REJECT_PATH)


def html_candidates(html, page_url):
    """(kandidaten, manifest-URL) uit de HTML. Kandidaat = {url, size, kind}; size 0 = onbekend."""
    p = HeadParser()
    try:
        p.feed(html)
        p.close()
    except Exception:
        pass
    base = resolve(page_url, p.base) or page_url
    manifest, touch, icons, og = '', [], [], []
    for link in p.links:
        url = resolve(base, link['href'])
        if not url:
            continue
        rel = link['rel']
        if 'manifest' in rel and not manifest:
            manifest = url
        elif rel & {'apple-touch-icon', 'apple-touch-icon-precomposed'}:
            sizes = parse_sizes(link['sizes'])
            # zonder sizes is een apple-touch-icon meestal 180 px; met alleen niet-vierkante maten: onbekend
            touch.append({'url': url, 'size': square_side(sizes) if sizes else 180, 'kind': 'apple-touch'})
        elif 'icon' in rel and 'mask-icon' not in rel:
            side = square_side(parse_sizes(link['sizes']))
            if side >= 192 and 'svg' not in link['type']:
                icons.append({'url': url, 'size': side, 'kind': 'icon'})
    for c in p.og:
        url = resolve(base, c)
        if url:
            og.append({'url': url, 'size': 0, 'kind': 'og'})
    touch.sort(key=lambda c: -c['size'])
    icons.sort(key=lambda c: -c['size'])
    return touch + icons + og[:1], manifest


def manifest_candidates(data, manifest_url):
    """Iconen uit een web-app-manifest: vierkant, ≥ 192 px, geen svg; purpose "any" (of leeg) voor alleen
    "maskable"; "monochrome" alleen telt niet. Grootste eerst."""
    try:
        m = json.loads(data) if isinstance(data, (str, bytes)) else data
    except Exception:
        return []
    out = []
    for ic in (m.get('icons') if isinstance(m, dict) else None) or []:
        if not isinstance(ic, dict):
            continue
        url = resolve(manifest_url, ic.get('src'))
        if not url or 'svg' in str(ic.get('type') or '').lower() or bad_ext(url):
            continue
        side = square_side(parse_sizes(ic.get('sizes')))
        if side < 192:
            continue
        purpose = set(str(ic.get('purpose') or 'any').lower().split()) or {'any'}
        if not purpose & {'any', 'maskable'}:
            continue
        out.append({'url': url, 'size': side, 'kind': 'manifest', 'any': 'any' in purpose})
    out.sort(key=lambda c: (not c['any'], -c['size']))
    return out


def order_candidates(manifest_icons, html_icons):
    """Volgorde: manifest, apple-touch-icon, icon met sizes, og:image; dubbele en afgekeurde URL's weg."""
    seen, out = set(), []
    for c in list(manifest_icons) + list(html_icons):
        if c['url'] in seen or reject_url(c['url']):
            continue
        seen.add(c['url'])
        out.append(c)
    return out


def root_candidates(page_url):
    p = urllib.parse.urlparse(page_url)
    root = f'https://{p.hostname}/' if p.hostname else ''
    if not root:
        return []
    return [{'url': root + 'apple-touch-icon.png', 'size': 0, 'kind': 'root'},
            {'url': root + 'apple-touch-icon-precomposed.png', 'size': 0, 'kind': 'root'}]


# ---------------------------------------------------------------- hosts

def site_host(url):
    """Host van een homepage zonder "www." (cachesleutel), of ''."""
    u = str(url or '').strip()
    if not u:
        return ''
    if '://' not in u:
        u = 'http://' + u
    try:
        h = (urllib.parse.urlparse(u).hostname or '').lower().rstrip('.')
    except ValueError:
        return ''
    if not h or '.' not in h:
        return ''
    try:
        ipaddress.ip_address(h)
        return ''  # kale IP-adressen niet
    except ValueError:
        pass
    return h[4:] if h.startswith('www.') else h


def skip_host(host):
    return any(host == s or host.endswith('.' + s) for s in SKIP_HOSTS)


def page_url(homepage):
    u = str(homepage or '').strip()
    return u if '://' in u else 'http://' + u


# ---------------------------------------------------------------- afbeelding controleren

def dhash(im):
    g = im.convert('L').resize((9, 8), Image.LANCZOS)
    px = list(g.tobytes())
    v = sum(1 << i for i in range(64) if px[(i // 8) * 9 + i % 8] > px[(i // 8) * 9 + i % 8 + 1])
    return f'{v:016x}'


def hamming(a, b):
    try:
        return bin(int(a, 16) ^ int(b, 16)).count('1')
    except (TypeError, ValueError):
        return 64


def check_image(data, generic=()):
    """(ok, reden, vingerafdruk) voor de bytes van een kandidaat."""
    if Image is None:
        return False, 'no-pillow', ''
    if not data or len(data) > MAX_IMG:
        return False, 'size', ''
    try:
        im = Image.open(io.BytesIO(data))
        fmt = im.format
        im.load()
    except Exception:
        return False, 'not-image', ''
    if fmt not in ('PNG', 'JPEG', 'WEBP'):
        return False, 'format', ''
    w, h = im.size
    if min(w, h) < MIN_SIDE:
        return False, 'small', ''
    if not RATIO[0] <= w / h <= RATIO[1]:
        return False, 'not-square', ''
    rgba = im.convert('RGBA')
    flat = Image.new('RGBA', rgba.size, (128, 128, 128, 255))
    flat.alpha_composite(rgba)
    flat = flat.convert('RGB').resize((64, 64), Image.LANCZOS)
    if max(ImageStat.Stat(flat).stddev) < 6:
        return False, 'blank', ''
    fp = dhash(flat)
    if any(hamming(fp, g) <= 4 for g in list(DEFAULT_HASHES) + list(generic)):
        return False, 'generic', fp
    return True, '', fp


# ---------------------------------------------------------------- netwerk

class Blocked(Exception):
    pass


_dns, _dns_lock = {}, threading.Lock()


def public_host(host):
    """Alleen hosts die naar openbare adressen wijzen (geen localhost, intern netwerk of metadata-adres)."""
    with _dns_lock:
        if host in _dns:
            return _dns[host]
    try:
        addrs = {ai[4][0] for ai in socket.getaddrinfo(host, None)}
        ok = bool(addrs) and all(ipaddress.ip_address(a.split('%')[0]).is_global for a in addrs)
    except Exception:
        ok = False
    with _dns_lock:
        _dns[host] = ok
    return ok


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        p = urllib.parse.urlparse(newurl)
        if p.scheme not in ('http', 'https') or not p.hostname or not public_host(p.hostname):
            raise Blocked('redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class Fetcher:
    """GET met een eigen User-Agent, maximale grootte en tijd, en hooguit één verzoek tegelijk per host."""

    def __init__(self, timeout=TIMEOUT, stop=None):
        self.timeout = timeout
        self.stop = stop or threading.Event()
        self.locks, self.guard = {}, threading.Lock()
        self.opener = urllib.request.build_opener(SafeRedirect)
        self.calls = 0

    def lock(self, host):
        with self.guard:
            return self.locks.setdefault(host, threading.Lock())

    def get(self, url, limit, accept='*/*', truncate=False):
        """(eind-URL, content-type, bytes). Te groot: fout, of (truncate) alleen het begin."""
        if self.stop.is_set():
            raise Blocked('stop')
        p = urllib.parse.urlparse(url)
        if p.scheme not in ('http', 'https') or not p.hostname or not public_host(p.hostname):
            raise Blocked('host')
        req = urllib.request.Request(url, headers={'User-Agent': BOT_UA, 'Accept': accept,
                                                   'Accept-Language': 'en;q=0.8, *;q=0.5'})
        with self.lock(p.hostname.lower()):
            self.calls += 1
            end = time.time() + self.timeout * 2
            with self.opener.open(req, timeout=self.timeout) as r:
                ctype = (r.headers.get('Content-Type') or '').lower()
                buf = bytearray()
                while len(buf) <= limit:
                    if time.time() > end:
                        raise Blocked('slow')
                    chunk = r.read(65536)
                    if not chunk:
                        break
                    buf += chunk
                if len(buf) > limit:
                    if not truncate:
                        raise Blocked('too-large')
                    buf = buf[:limit]
                return r.geturl(), ctype, bytes(buf)


def verify(fetcher, url, generic=()):
    """(https-URL, vingerafdruk) als de kandidaat een goed icoon is, anders (None, reden)."""
    https = 'https://' + url[len('http://'):] if url.startswith('http://') else url
    if reject_url(https):
        return None, 'rejected-url'
    try:
        final, ctype, data = fetcher.get(https, MAX_IMG, accept='image/png,image/webp,image/jpeg,image/*;q=0.8')
    except Exception as e:
        return None, f'download:{type(e).__name__}'
    if not final.startswith('https://') or reject_url(final):
        return None, 'redirect-url'
    ok, why, fp = check_image(data, generic)
    if not ok:
        return None, why
    return https, fp  # het gevraagde adres (een redirect volgen de apps zelf)


def find_icon(fetcher, homepage, generic=()):
    """{'u': url, 'h': vingerafdruk, 'via': soort} of {'u': '', 'r': reden}; altijd met 'sl': 1 (store-links
    bekeken) en, als de pagina ze heeft, 'ios' (App Store-id's) en 'gp' (Play-pakketten) voor tools/store_icons.py."""
    start = page_url(homepage)
    cands, final, links = [], start, {}
    try:
        final, ctype, data = fetcher.get(start, MAX_HTML, accept='text/html,application/xhtml+xml,*/*;q=0.5',
                                         truncate=True)
        html = data.decode('utf-8', 'replace') if ('html' in ctype or not ctype) else ''
    except Exception as e:
        html, reason = '', f'page:{type(e).__name__}'
    else:
        reason = 'no-candidates'
    if html:
        links = {k: v for k, v in st.store_links(html).items() if v}
        html_icons, manifest = html_candidates(html, final)
        man_icons = []
        if manifest:
            try:
                _, _, mdata = fetcher.get(manifest, MAX_MANIFEST, accept='application/manifest+json,application/json')
                man_icons = manifest_candidates(mdata.decode('utf-8', 'replace'), manifest)
            except Exception:
                pass
        cands = order_candidates(man_icons, html_icons)
    tried = 0
    for c in cands + root_candidates(final if html else start):
        if fetcher.stop.is_set():
            return None
        if c['kind'] == 'root' and tried and cands:
            break  # root alleen als er niets in de pagina stond
        if tried >= MAX_TRIES:
            break
        tried += 1
        url, fp = verify(fetcher, c['url'], generic)
        if url:
            return {'u': url, 'h': fp, 'via': c['kind'], 'sl': 1, **links}
        reason = fp or reason
    return {'u': '', 'r': reason, 'sl': 1, **links}


# ---------------------------------------------------------------- standaardiconen herkennen

def find_generic(items, names_by_host, min_hosts=GENERIC_HOSTS, brand_share=0.6):
    """Vingerafdrukken die bij veel sites voorkomen zonder dat die sites een naam delen (dus geen omroepnetwerk
    zoals Radio Maria): dat is een standaardicoon van een platform. Geeft de set vingerafdrukken."""
    by_hash = {}
    for host, e in items.items():
        if isinstance(e, dict) and e.get('u') and e.get('h'):
            by_hash.setdefault(e['h'], []).append(host)
    out = set()
    for fp, hosts in by_hash.items():
        if len(hosts) < min_hosts:
            continue
        counts = {}
        for host in hosts:
            toks = set(ms.host_tokens('https://' + host))
            for n in names_by_host.get(host, ()):
                toks |= {t for t in ms.core_tokens(n) if len(t) >= 3}
            for t in toks:
                counts[t] = counts.get(t, 0) + 1
        if not counts or max(counts.values()) < brand_share * len(hosts):
            out.add(fp)
    return out


# ---------------------------------------------------------------- cache en uitvoer

def is_fresh(entry, today):
    if not entry.get('sl'):
        return False  # nog zonder store-links bekeken (van voor tools/store_icons.py): opnieuw
    try:
        d = datetime.strptime(entry.get('d', ''), '%Y-%m-%d').date()
    except Exception:
        return False
    return today - d < timedelta(days=HIT_DAYS if entry.get('u') else MISS_DAYS)


def load_cache(path):
    try:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
    except Exception:
        return {}, set()
    if not isinstance(data, dict):
        return {}, set()
    return dict(data.get('items') or {}), set(data.get('generic') or [])


def save_cache(path, items, generic):
    if path:
        mt.save_items(path, items, {'generic': sorted(generic)})


def site_groups(groups):
    """host → {'homepage', 'names', 'keys'}; hosts van platforms en gedeelde hosts (te veel zendernamen) vallen
    af. In volgorde van populariteit (groups is al gesorteerd)."""
    hosts = {}
    for (cc, k), g in groups.items():
        h = site_host(g['homepage'])
        if not h or skip_host(h):
            continue
        e = hosts.setdefault(h, {'homepage': g['homepage'], 'names': [], 'cores': set(), 'keys': []})
        e['names'].append(g['name'])
        e['cores'].add(ms.core(g['name']) or k)
        e['keys'].append((cc, k))
    return {h: e for h, e in hosts.items() if len(e['cores']) <= SHARED_HOST}


def store_icon(cc, k, g, host_entry, pcache):
    """Store-icoon voor één zender (of ''): App Store-app waar zijn website naar linkt > Play-app waar zijn website
    naar linkt > Play-zoekresultaat. Per zendernaam gecontroleerd met st.link_related (de cache bewaart de titel)."""
    hp, name = g['homepage'], g['name']
    he = host_entry or {}
    for app_id in he.get('ios') or []:
        e = pcache.get('ios:' + app_id) or {}
        if e.get('u') and st.link_related(name, e.get('t'), hp, cc, e.get('s') or '', e.get('su') or '',
                                          e.get('g') or 'Music'):
            return e['u']
    for pkg in he.get('gp') or []:
        e = pcache.get('gp:' + pkg) or {}
        if e.get('u') and st.link_related(name, e.get('t'), hp, cc, e.get('s') or ''):
            return e['u']
    return (pcache.get(f'q:{cc}|{k}') or {}).get('u') or ''


def build_tables(groups, items, hosts, pcache=None):
    pcache = pcache or {}
    files = {}
    for (cc, k), g in groups.items():
        h = site_host(g['homepage'])
        e = items.get(h) if h in hosts else None
        url = store_icon(cc, k, g, e, pcache) or (e or {}).get('u') or ''
        if not url.startswith('https://'):
            continue
        f = files.setdefault(cc or '_world', {'u': {}, 'n': {}})
        f['n'][k] = url
        for uuid in g['uuids']:
            f['u'][uuid] = url
    return files


def existing_rank(existing, cc, k, uuids):
    """Beste soort bron (mt.url_rank) die deze zender al in de gepubliceerde tabellen heeft."""
    t = existing.get(cc or '_world') or {}
    urls = [(t.get('n') or {}).get(k)] + [(t.get('u') or {}).get(u) for u in uuids]
    return max([mt.url_rank(u) for u in urls] or [0])


def verify_store_image(fetcher, url):
    """Store-iconen (mzstatic / play-lh): alleen https en een goed plaatje (geen URL-regels voor CMS'en)."""
    if not url.startswith('https://'):
        return False
    try:
        final, _, data = fetcher.get(url, MAX_IMG, accept='image/png,image/webp,image/jpeg,image/*;q=0.8')
    except Exception:
        return False
    return final.startswith('https://') and check_image(data)[0]


def resolve_store_links(fetcher, groups, hosts, items, pcache, existing, deadline, store_max=600,
                        itunes_delay=3.0, play_delay=2.0):
    """Fase 2: App Store-id's (iTunes lookup) en Play-pakketten (app-pagina) van de websites opzoeken, in twee
    threads (één per dienst, elk met eigen tussenpozen). Alleen voor websites met een zender zonder App Store-icoon."""
    today = date.today()
    ios_todo, gp_todo = [], []
    for h, e in hosts.items():
        it = items.get(h) or {}
        if not it.get('ios') and not it.get('gp'):
            continue
        cc = next((c for c, _ in e['keys'] if c), '')
        ranks = [existing_rank(existing, c, k, groups[(c, k)]['uuids']) for c, k in e['keys']]
        if min(ranks) >= 3:
            continue
        for app_id in it.get('ios') or []:
            if not st.is_fresh(pcache.get('ios:' + app_id), today) and app_id not in {x for x, _ in ios_todo}:
                ios_todo.append((app_id, cc))
        # Play alleen als de App Store-links van deze site al zeker niets opleverden (anders volgende run)
        ios_open = any((pcache.get('ios:' + i) or {}).get('u') or not st.is_fresh(pcache.get('ios:' + i), today)
                       for i in it.get('ios') or [])
        if min(ranks) >= 2 or ios_open:
            continue
        for pkg in it.get('gp') or []:
            if not st.is_fresh(pcache.get('gp:' + pkg), today) and pkg not in {x for x, _ in gp_todo}:
                gp_todo.append((pkg, cc))
    print(f'store-links: {len(ios_todo)} App Store-id\'s en {len(gp_todo)} Play-pakketten op te zoeken')
    verify = lambda u: verify_store_image(fetcher, u)
    lock, stats = threading.Lock(), {'ios': 0, 'ios_hits': 0, 'gp': 0, 'gp_hits': 0}
    day = today.isoformat()

    def run(kind, todo, spacer, lookup, cap):
        busy = 0
        for key, cc in todo:
            if fetcher.stop.is_set() or time.time() > deadline or stats[kind] >= cap:
                return
            try:
                res = lookup(fetcher, spacer, key, cc, verify)
            except urllib.error.HTTPError as e:
                if e.code in st.BUSY:
                    busy += 1
                    print(f'  {kind}: HTTP {e.code}, rustiger aan')
                    if busy >= 3:
                        print(f'  {kind}: gestopt voor deze run')
                        return
                    spacer.delay *= 1.5
                    fetcher.stop.wait(30)
                    continue
                res = {'u': '', 'r': f'http:{e.code}'}
            except Exception as e:
                if isinstance(e, Blocked) and str(e) == 'stop':
                    return
                continue  # tijdelijk (netwerk): niet cachen, volgende run opnieuw
            res['d'] = day
            with lock:
                pcache[f'{kind}:{key}'] = res
                stats[kind] += 1
                stats[kind + '_hits'] += bool(res.get('u'))
            if res.get('u'):
                print(f'  + {kind} {key} {res.get("t", "")}')

    threads = [threading.Thread(target=run, args=('ios', ios_todo, st.Spacer(itunes_delay), st.lookup_ios,
                                                  store_max)),
               threading.Thread(target=run, args=('gp', gp_todo, st.Spacer(play_delay), st.lookup_play_pkg,
                                                  store_max))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    print(f'store-links: {stats["ios"]} App Store-lookups ({stats["ios_hits"]} iconen), '
          f'{stats["gp"]} Play-pagina\'s ({stats["gp_hits"]} iconen)')
    return stats


def play_candidates(groups, hosts, items, pcache, existing, per_country=100, world=1000):
    """Fase 3: populaire zenders (top `per_country` per land + top `world` wereldwijd, op clickcount) zonder App
    Store- of Play-icoon (gepubliceerd, of via de store-links van deze run) en zonder verse Play-zoekcache."""
    today = date.today()
    out, per_cc = [], {}
    for i, ((cc, k), g) in enumerate(groups.items()):
        per_cc[cc] = per_cc.get(cc, 0) + 1
        if per_cc[cc] > per_country and i >= world:
            continue
        if st.is_fresh(pcache.get(f'q:{cc}|{k}'), today):
            continue
        c = ms.core(g['name'])
        if ms.is_generic(c) and not (c.isdigit() and len(c) >= 3):
            continue  # "Radio 1", "Jazz Radio": op naam alleen te onzeker in een zoekmachine ("Radio 538" mag)
        if existing_rank(existing, cc, k, g['uuids']) >= 2:
            continue
        h = site_host(g['homepage'])
        if mt.url_rank(store_icon(cc, k, g, items.get(h) if h in hosts else None, pcache)) >= 2:
            continue
        out.append((cc, k, g))
    return out


def search_play_all(fetcher, todo, pcache, deadline, play_max=300, delay=2.0):
    spacer, done, hits, busy = st.Spacer(delay), 0, 0, 0
    verify = lambda u: verify_store_image(fetcher, u)
    day = date.today().isoformat()
    print(f'Play-zoeken: {len(todo)} kandidaten (max. {play_max})')
    for cc, k, g in todo:
        if fetcher.stop.is_set() or time.time() > deadline or done >= play_max:
            break
        try:
            res = st.search_play(fetcher, spacer, g['name'], cc, g['homepage'], verify)
        except urllib.error.HTTPError as e:
            if e.code in st.BUSY:
                busy += 1
                print(f'  Play: HTTP {e.code}')
                if busy >= 2:
                    print('  Play: gestopt voor deze run')
                    break
                spacer.delay *= 2
                fetcher.stop.wait(60)
                continue
            res = {'u': '', 'r': f'http:{e.code}'}
        except Exception:
            continue
        res['d'] = day
        pcache[f'q:{cc}|{k}'] = res
        done += 1
        hits += bool(res.get('u'))
        if res.get('u'):
            print(f'  + play {cc or "--"} {g["name"]} → {res.get("p")}')
    print(f'Play-zoeken: {done} gezocht, {hits} iconen')
    return done, hits


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--cache', default=os.path.join(ROOT, '.site-icons-cache.json'))
    ap.add_argument('--play-cache', default=os.path.join(ROOT, '.play-icons-cache.json'),
                    help='cache van tools/store_icons.py (App Store-id\'s, Play-pakketten, Play-zoekopdrachten)')
    ap.add_argument('--budget-min', type=float, default=46, help='totaal (websites + store-links + Play-zoeken)')
    ap.add_argument('--play', default='true', help='Play-zoekfunctie gebruiken (true/false)')
    ap.add_argument('--countries', type=int, default=80)
    ap.add_argument('--per-country', type=int, default=300)
    ap.add_argument('--world', type=int, default=3000)
    ap.add_argument('--all', action='store_true', help='alle zenders van alle landen (populairste eerst)')
    ap.add_argument('--workers', type=int, default=32)
    ap.add_argument('--store-max', type=int, default=600, help='hooguit zoveel iTunes-lookups (en Play-pagina\'s)')
    ap.add_argument('--play-max', type=int, default=300, help='hooguit zoveel Play-zoekopdrachten')
    ap.add_argument('--play-per-country', type=int, default=100)
    ap.add_argument('--play-world', type=int, default=1000)
    ap.add_argument('--itunes-delay', type=float, default=3.0)
    ap.add_argument('--play-delay', type=float, default=2.0)
    ap.add_argument('--existing', default=OUT_DIR, help='gepubliceerde tabellen (wat er al een store-icoon heeft)')
    ap.add_argument('--limit', type=int, default=0, help='hooguit zoveel sites opzoeken (testen)')
    ap.add_argument('--offline', action='store_true')
    ap.add_argument('--out', default=OUT_DIR)
    a = ap.parse_args(argv)
    play = str(a.play).strip().lower() not in ('false', '0', 'no', 'nee', 'off')

    # tijdsbudget verdelen: websites, store-links (iTunes lookup + Play-pagina's), Play-zoeken
    start = time.time()
    split = (0.55, 0.18, 0.27) if play else (0.75, 0.25, 0.0)
    site_deadline = start + a.budget_min * 60 * split[0]
    items, generic = load_cache(a.cache)
    pcache = mt.load_items(a.play_cache)
    existing = mt.load_dir(a.existing)
    print(f'site-cache: {len(items)} sites ({sum(1 for e in items.values() if e.get("u"))} met icoon); '
          f'play-cache: {len(pcache)} items ({sum(1 for e in pcache.values() if e.get("u"))} met icoon)')
    groups = ms.group(ms.popular_stations(a.countries, a.per_country, a.world, a.all))
    hosts = site_groups(groups)
    print(f'{len(groups)} zendernamen, {len(hosts)} websites')

    stop, stop2 = threading.Event(), threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: (stop.set(), stop2.set()))
    today = date.today().isoformat()
    todo = [h for h in hosts if not is_fresh(items.get(h) or {}, date.today())]
    if a.limit:
        todo = todo[:a.limit]
    print(f'{len(todo)} nog op te zoeken')
    done = hits = 0
    if not a.offline and todo:
        fetcher = Fetcher(stop=stop)
        known = frozenset(generic)
        ex = ThreadPoolExecutor(max_workers=a.workers)
        futs = {ex.submit(find_icon, fetcher, hosts[h]['homepage'], known): h for h in todo}
        try:
            for fut in as_completed(futs, timeout=max(1, site_deadline - time.time())):
                h = futs[fut]
                try:
                    res = fut.result()
                except Exception as e:
                    res = {'u': '', 'r': f'error:{type(e).__name__}'}
                if res is None:  # gestopt
                    continue
                res['d'] = today
                items[h] = res
                done += 1
                hits += bool(res.get('u'))
                if done % 250 == 0:
                    save_cache(a.cache, items, generic)
                    print(f'{done}/{len(todo)} sites, {hits} iconen, {fetcher.calls} verzoeken, '
                          f'{(time.time() - start) / 60:.0f} min')
                if stop.is_set() or time.time() > site_deadline:
                    raise TimeoutError
        except (TimeoutError, FuturesTimeout):
            print('tijd op (websites): de volgende run gaat verder')
        finally:
            stop.set()
            ex.shutdown(wait=True, cancel_futures=True)

    # standaardiconen (zelfde plaatje bij veel losse sites) herkennen en overal weigeren
    names = {h: e['names'] for h, e in hosts.items()}
    new_generic = find_generic(items, names)
    if new_generic - generic:
        print(f'standaardiconen herkend: {len(new_generic - generic)}')
    generic |= new_generic
    for h, e in items.items():
        if e.get('u') and any(hamming(e.get('h'), g) <= 4 for g in generic | DEFAULT_HASHES):
            items[h] = dict(e, u='', r='generic', d=today)  # store-links blijven bewaard
    save_cache(a.cache, items, generic)

    # store-links van de websites (exacte App Store-id / Play-pakket) en de Play-zoekfunctie
    if not a.offline and not stop2.is_set():
        fetcher2 = Fetcher(stop=stop2)
        store_deadline = time.time() + a.budget_min * 60 * split[1] + max(0, site_deadline - time.time())
        resolve_store_links(fetcher2, groups, hosts, items, pcache, existing, store_deadline, a.store_max,
                            a.itunes_delay, a.play_delay)
        mt.save_items(a.play_cache, pcache)
        if play and not stop2.is_set():
            play_deadline = start + a.budget_min * 60
            cands = play_candidates(groups, hosts, items, pcache, existing, a.play_per_country, a.play_world)
            search_play_all(fetcher2, cands, pcache, play_deadline, a.play_max, a.play_delay)
        stop2.set()
    if a.play_cache:
        mt.save_items(a.play_cache, pcache)

    files = build_tables(groups, items, hosts, pcache)
    mt.merge_into_dir(a.out, site=files)
    by = {}
    for f in files.values():
        for url in f['n'].values():
            r = {3: 'App Store', 2: 'Play', 1: 'website'}[mt.url_rank(url)]
            by[r] = by.get(r, 0) + 1
    total = sum(len(f['n']) for f in files.values())
    print(f'klaar: {done} sites opgezocht ({hits} iconen) · {len(files)} bestanden · {total} namen met icoon {by}')


if __name__ == '__main__':
    main()

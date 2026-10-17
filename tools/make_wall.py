#!/usr/bin/env python3
"""Vaste zenderlogo's voor de hero van tunr.online.

Haalt één keer de populairste zenders uit Radio Browser (Nederland voorop, daarna wereldwijd), downloadt hun logo's,
houdt alleen nette, (bijna) vierkante logo's van minstens 96 px over en schrijft ze als WebP naar
website/assets/img/wall/ plus de lijst naar website/assets/js/wall.js. De site laadt daarna alleen die vaste
bestanden: geen live ophalen, geen geflikker. Opnieuw maken: workflow Website met "Hero-logo's vernieuwen".

Voorkeur: het app-icoon uit de vaste tabel website/assets/data/icons/<CC>.json (samengevoegd door
tools/merge_icon_tables.py: App Store-icoon, anders het app-icoon van de eigen website van de zender); staat de
zender er niet in, dan hooguit LIVE_MAX keer zelf iTunes vragen (zelfde match als tools/make_station_icons.py);
daarna het favicon uit Radio Browser.

Gebruik: python3 tools/make_wall.py [aantal]   (standaard 76 = alle tegels behalve die van Tunr)
"""
import io, json, os, random, sys, urllib.request, urllib.parse

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_station_icons as icons  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_IMG = os.path.join(ROOT, 'website', 'assets', 'img', 'wall')
OUT_JS = os.path.join(ROOT, 'website', 'assets', 'js', 'wall.js')
UA = {'User-Agent': 'Tunr/1.0.0 (+https://tunr.online)'}
WANT = int(sys.argv[1]) if len(sys.argv) > 1 else 76
NL_SHARE = 30
SIZE = 192
ICON_DIR = os.path.join(ROOT, 'website', 'assets', 'data', 'icons')
LIVE_MAX = int(os.environ.get('WALL_ITUNES_MAX', '60'))  # live iTunes-verzoeken (≈ 3,2 s per stuk)
_maps, _live = {}, {'n': 0, 'itunes': None}


def icon_map(cc):
    """Vaste tabel met zendericonen (App Store + websites) voor een land (of {} als die er niet is)."""
    cc = cc or '_world'
    if cc not in _maps:
        try:
            with open(os.path.join(ICON_DIR, cc + '.json'), encoding='utf-8') as fh:
                _maps[cc] = json.load(fh)
        except Exception:
            _maps[cc] = {}
    return _maps[cc]


def app_icon(s):
    """URL van het app-icoon van de zender (tabel: App Store of eigen website; anders live iTunes), of ''."""
    cc = (s.get('countrycode') or '').upper()
    m = icon_map(cc)
    url = (m.get('u') or {}).get(s.get('stationuuid') or '') or (m.get('n') or {}).get(icons.norm_key(s.get('name')))
    if url:
        return url
    if _live['n'] >= LIVE_MAX:
        return ''
    _live['n'] += 1
    if _live['itunes'] is None:
        _live['itunes'] = icons.Itunes(3.2)
    try:
        return icons.lookup(_live['itunes'], s.get('name') or '', cc, s.get('homepage') or '', us_fallback=False)
    except Exception as e:
        print('iTunes mislukt:', e)
        _live['n'] = LIVE_MAX  # niet blijven proberen
        return ''


def get(url, timeout=20):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def servers():
    names = []
    try:
        names = ['https://' + s['name'] for s in json.loads(get('https://all.api.radio-browser.info/json/servers'))]
    except Exception:
        pass
    random.shuffle(names)
    return list(dict.fromkeys(names + ['https://de1.api.radio-browser.info', 'https://de2.api.radio-browser.info',
                                       'https://fi1.api.radio-browser.info']))


def stations(base, extra, limit):
    q = urllib.parse.urlencode(dict(hidebroken='true', order='clickcount', reverse='true', limit=limit, **extra))
    return json.loads(get(f'{base}/json/stations/search?{q}', 40))


def key(name):
    return ''.join(ch for ch in name.lower() if ch.isalnum())[:12]


def dhash(im):
    """Kleine vingerafdruk van het plaatje, om bijna dezelfde logo's (zelfde omroep, andere stream) over te slaan."""
    g = im.convert('L').resize((9, 8), Image.LANCZOS)
    px = list(g.getdata())
    return sum(1 << i for i in range(64) if px[(i // 8) * 9 + i % 8] > px[(i // 8) * 9 + i % 8 + 1])


def logo(url):
    """Logo als vierkante WebP-bytes, of None als het niet bruikbaar is."""
    if not url.lower().startswith(('http://', 'https://')) or url.lower().split('?')[0].endswith('.ico'):
        return None
    for u in dict.fromkeys([url.replace('http://', 'https://', 1), url]):
        try:
            data = get(u, 12)
            im = Image.open(io.BytesIO(data))
            im.load()
        except Exception:
            continue
        w, h = im.size
        if min(w, h) < 96 or not (0.8 <= w / h <= 1.25):
            return None
        im = im.convert('RGBA')
        # transparante logo's op het donkere Tunr-vlak, zodat ze de tegel vullen zonder witte rand
        bg = Image.new('RGBA', im.size, (22, 22, 26, 255))
        bg.alpha_composite(im)
        side = min(w, h)
        left, top = (w - side) // 2, (h - side) // 2
        sq = bg.crop((left, top, left + side, top + side)).convert('RGB').resize((SIZE, SIZE), Image.LANCZOS)
        # bijna effen plaatjes (lege of kapotte logo's) overslaan
        if max(hi - lo for lo, hi in sq.getextrema()) < 30:
            return None
        buf = io.BytesIO()
        sq.save(buf, 'WEBP', quality=82, method=6)
        return buf.getvalue(), dhash(sq)
    return None


def main():
    nl = world = []
    for base in servers():
        try:
            nl = stations(base, {'countrycode': 'NL'}, 300)
            world = stations(base, {}, 700)
            break
        except Exception as e:
            print('server mislukt:', base, e)
    if not world:
        sys.exit('Radio Browser niet bereikbaar')

    seen, picked, hashes = set(), [], []

    def take(lst, n):
        got = 0
        for s in lst:
            if got >= n or len(picked) >= WANT:
                break
            name = (s.get('name') or '').strip()
            k = key(name)
            if not name or not k or k in seen:
                continue
            seen.add(k)
            # eerst het (mooiere) app-icoon uit de App Store, dan het favicon uit Radio Browser
            res = None
            ai = app_icon(s)
            if ai:
                res = logo(ai)
            if not res:
                res = logo((s.get('favicon') or '').strip())
            if not res:
                continue
            data, h = res
            if any(bin(h ^ o).count('1') <= 10 for o in hashes):
                continue
            hashes.append(h)
            place = ', '.join(x for x in [(s.get('state') or '').strip(), (s.get('country') or '').strip()] if x)
            picked.append((name, place, data))
            got += 1
            print(f'{len(picked):3d} {name}')

    take(nl, NL_SHARE)
    take(world, WANT)
    if len(picked) < 20:
        sys.exit(f'te weinig logo\'s ({len(picked)})')

    os.makedirs(OUT_IMG, exist_ok=True)
    for f in os.listdir(OUT_IMG):
        if f.endswith('.webp'):
            os.remove(os.path.join(OUT_IMG, f))
    items = []
    for i, (name, place, data) in enumerate(picked, 1):
        fn = f'{i:02d}.webp'
        with open(os.path.join(OUT_IMG, fn), 'wb') as fh:
            fh.write(data)
        items.append({'n': name, 'p': place, 'i': fn})
    with open(OUT_JS, 'w', encoding='utf-8') as fh:
        fh.write('// Gemaakt door tools/make_wall.py: vaste zenderlogo\'s voor de hero (bron: App Store-iconen, iconen van zenderwebsites en Radio Browser).\n')
        fh.write('window.TUNR_WALL = ' + json.dumps(items, ensure_ascii=False, separators=(',', ':')) + ';\n')
    print(f'{len(items)} logo\'s geschreven')


if __name__ == '__main__':
    main()

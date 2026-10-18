#!/usr/bin/env python3
"""Mooie zendericonen: het app-icoon uit de App Store per zender (workflow Icons, docs/SPEC.md §1).

De meeste zenders hebben een iPhone-app met een strak, vierkant icoon. De iTunes Search API (zonder sleutel) is
beperkt (~20 verzoeken per minuut per IP), dus de apps vragen hem niet zelf per zender: dit script maakt in CI een
vaste tabel die de apps en de webspeler van tunr.online halen.

1. populaire zenders uit Radio Browser (eigen User-Agent): de top per land (grootste landen) + de top wereldwijd,
   ontdubbeld op genormaliseerde naam per land;
2. per naam `itunes.apple.com/search?entity=software&country=<cc>` (daarna de Amerikaanse store) en alleen een app
   kiezen als de naam zeker klopt (`match_app`);
3. resultaat (ook "niets gevonden") in een cache (branch icons-data), zodat elke run verdergaat waar de vorige
   stopte; missers na 90 dagen en treffers na 180 dagen opnieuw;
4. uitvoer: website/assets/data/icons/<CC>.json (+ _world.json voor zenders zonder land) =
   {"u": {stationuuid: url}, "n": {naamsleutel: url}}, samengevoegd met wat er al staat via
   tools/merge_icon_tables.py (App Store-icoon gaat voor het Google Play- en website-icoon van
   tools/make_site_icons.py; er verdwijnt niets).

Gebruik:
    python3 tools/make_station_icons.py [--cache pad] [--budget-min 330] [--countries 60] [--per-country 150]
                                        [--world 2000] [--delay 3.2] [--no-us-fallback] [--offline]

`--offline` vraagt niets aan iTunes en schrijft alleen de uitvoer opnieuw uit de cache.
`norm_key` moet overal hetzelfde zijn (Apple IconMap.key, Android IconMap.key, web T.iconKey).
"""
import argparse, json, os, random, re, signal, sys, time, unicodedata, urllib.error, urllib.parse, urllib.request
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import merge_icon_tables  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, 'website', 'assets', 'data', 'icons')
UA = {'User-Agent': 'Tunr/1.0.1 (+https://tunr.online)'}
ITUNES = 'https://itunes.apple.com/search'

GENRES = {'Music', 'Entertainment', 'News', 'Sports', 'Lifestyle', 'Reference', 'Education'}
MISS_DAYS = 90
HIT_DAYS = 180

# woorden die niets over de zender zeggen (weg uit de "kernnaam")
STOP = {
    'radio', 'radios', 'rádio', 'radyo', 'radij', 'radiu', 'fm', 'am', 'dab', 'hd', 'live', 'online', 'stream',
    'streams', 'app', 'apps', 'official', 'officiel', 'oficial', 'offiziell', 'web', 'webradio', 'internet', 'net',
    'player', 'the', 'de', 'het', 'la', 'le', 'el', 'il', 'lo', 'les', 'los', 'las', 'die', 'der', 'das', 'and',
    'en', 'et', 'y', 'und', 'mhz', 'khz', 'station', 'channel', 'tv', 'listen', 'vivo', 'direct', 'direkt',
    'www', 'com', 'org',
}
# kernnamen die te algemeen zijn om op naam alleen te vertrouwen
GENERIC = {
    'news', 'music', 'musica', 'musik', 'jazz', 'rock', 'pop', 'classic', 'classical', 'klassik', 'hits', 'hit',
    'dance', 'love', 'country', 'gold', 'chill', 'lounge', 'top', 'christmas', 'kids', 'talk', 'sport', 'sports',
    'oldies', 'metal', 'blues', 'soul', 'reggae', 'latino', 'latina', 'salsa', 'italia', 'france', 'deutschland',
    'one', 'uno', 'eins', 'two', 'city', 'star', 'max', 'mix', 'nova', 'plus', 'energy', 'world', 'global',
    'international', 'local', 'free', 'best', 'maria', 'christian', 'gospel', 'bible', 'islam', 'quran', 'coran',
    'retro', 'disco', 'house', 'techno', 'party', 'happy', 'smooth', 'easy', 'relax', 'ambient', 'piano',
}
FREQ = re.compile(r'\b\d{2,3}(?:[.,]\d{1,2})\s*(?:fm|mhz)?\b', re.I)


# ---------------------------------------------------------------- normaliseren

def fold(s):
    """NFKD, accenten weg, kleine letters."""
    s = unicodedata.normalize('NFKD', str(s or ''))
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return s.lower()


def norm_key(name):
    """Naamsleutel voor de tabel ("n"): NFKD, accenten weg, kleine letters, alleen letters (L*) en cijfers (Nd).
    Zelfde regel in Swift, Kotlin en JavaScript."""
    return ''.join(c for c in fold(name) if unicodedata.category(c)[0] == 'L' or unicodedata.category(c) == 'Nd')


def tokens(name):
    """Woorden van een naam zonder frequenties, leestekens en accenten."""
    s = FREQ.sub(' ', fold(name))
    out, cur = [], ''
    for c in s:
        cat = unicodedata.category(c)
        if cat[0] == 'L' or cat == 'Nd':
            cur += c
        else:
            if cur:
                out.append(cur)
            cur = ''
    if cur:
        out.append(cur)
    return out


def core_tokens(name):
    return [t for t in tokens(name) if t not in STOP]


def core(name):
    return ''.join(core_tokens(name))


def search_term(name):
    """Zoekterm: de naam zonder slogan na " - " / " | " en zonder frequenties."""
    n = str(name or '').strip()
    for sep in (' - ', ' | ', ' – ', ' — ', ' :: ', ' (', ' ['):
        i = n.find(sep)
        if i >= 3:
            n = n[:i]
    n = FREQ.sub(' ', n)
    return re.sub(r'\s+', ' ', n).strip() or str(name or '').strip()


def host_tokens(url):
    """Woorden uit het domein van een URL ("https://www.radio538.nl/x" → {"radio538"})."""
    u = str(url or '').strip()
    if not u:
        return set()
    if '://' not in u:
        u = 'http://' + u
    try:
        h = urllib.parse.urlparse(u).hostname or ''
    except ValueError:
        return set()
    parts = [p for p in h.lower().split('.') if p and p not in {'www', 'm', 'com', 'org', 'net', 'co', 'apps', 'apple'}]
    if len(parts) > 1:
        parts = parts[:-1]  # landdomein (nl, de, fm) weg
    return {norm_key(p) for p in parts if len(norm_key(p)) >= 3}


def jaccard(a, b):
    a, b = set(a), set(b)
    return len(a & b) / len(a | b) if a and b else 0.0


def is_generic(c):
    return len(c) < 3 or c in GENERIC or c.isdigit()


def icon_url(art):
    """mzstatic-icoon als PNG van 256 px (`/512x512bb.jpg` → `/256x256bb.png`)."""
    art = str(art or '').strip()
    if not art.startswith('https://'):
        return ''
    new = re.sub(r'/\d+x\d+(bb|w|ia)?(-\d+)?\.(jpg|jpeg|png|webp)$', '/256x256bb.png', art, flags=re.I)
    return new if new != art else ''


# ---------------------------------------------------------------- de match

def score_app(station_name, app, store_cc='', station_cc='', homepage=''):
    """Hoe zeker is het dat `app` (iTunes-resultaat) de app van deze zender is? 0 = niet; hoger = zekerder."""
    if (app.get('primaryGenreName') or '') not in GENRES:
        return 0
    if not icon_url(app.get('artworkUrl512') or app.get('artworkUrl100')):
        return 0
    track = app.get('trackName') or ''
    seller = app.get('sellerName') or app.get('artistName') or ''
    s_full, t_full = norm_key(station_name), norm_key(track)
    s_core, t_core = core(station_name), core(track)
    # appnaam zonder slogan ("Radio 538 - Non Stop Hits" → "Radio 538")
    t_head = search_term(track)
    th_full, th_core = norm_key(t_head), core(t_head)
    seller_tok = set(core_tokens(seller)) | {norm_key(seller)}
    site = host_tokens(homepage)
    app_sites = host_tokens(app.get('sellerUrl') or '')
    domain_match = any(a == b or (min(len(a), len(b)) >= 3 and (a in b or b in a)) for a in app_sites for b in site)
    seller_rel = domain_match or bool(site and any(
        t and len(t) >= 3 and any(t in h or h in t for h in site) for t in seller_tok))
    same_store = bool(station_cc) and store_cc.upper() == station_cc.upper()

    if not s_full:
        return 0
    if is_generic(s_core):
        exact = s_full in (t_full, th_full)
        # "Radio 538": een getal van 3+ cijfers is onderscheidend genoeg bij exact dezelfde naam in de eigen store
        if exact and same_store and s_core.isdigit() and len(s_core) >= 3:
            return 90
        # "Radio 1", "Jazz Radio": alleen exact dezelfde naam, in de store van het eigen land, en de uitgever hoort
        # bij de zender (domein of naam van de uitgever in de homepage)
        if exact and same_store and seller_rel:
            return 90
        return 0

    if s_full == t_full or s_full == th_full:
        return 100
    if s_core and (s_core == t_core or s_core == th_core):
        return 95
    score = 0
    # kernnaam van de zender in de appnaam (of andersom, als die niet veel korter is)
    if len(s_core) >= 4 and (s_core in t_full or s_core in th_full):
        score = 80
    elif len(th_core) >= 4 and th_core in s_full and len(th_core) >= 0.6 * len(s_core) and not is_generic(th_core):
        score = 75
    st, at = set(core_tokens(station_name)), set(core_tokens(t_head)) or set(core_tokens(track))
    if len(st | at) >= 2 and jaccard(st, at) >= 0.8:
        score = max(score, 78)
    if score and domain_match:
        score += 10
    elif score and seller_rel:
        score += 4
    if not score and domain_match and jaccard(st, at) >= 0.5:
        score = 70
    return score


def match_app(station_name, results, store_cc='', station_cc='', homepage='', minimum=70):
    """Beste app (iTunes-resultaat) voor deze zender of None. Bij gelijke score wint de volgorde van iTunes."""
    best, best_score = None, 0
    for app in results or []:
        sc = score_app(station_name, app, store_cc, station_cc, homepage)
        if sc > best_score:
            best, best_score = app, sc
    return best if best_score >= minimum else None


# ---------------------------------------------------------------- netwerk

def get(url, timeout=25):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def rb_servers():
    names = []
    try:
        names = ['https://' + s['name'] for s in json.loads(get('https://all.api.radio-browser.info/json/servers'))]
    except Exception:
        pass
    random.shuffle(names)
    return list(dict.fromkeys(names + ['https://de1.api.radio-browser.info', 'https://de2.api.radio-browser.info',
                                       'https://fi1.api.radio-browser.info']))


def rb_get(path, servers):
    last = None
    for base in servers:
        try:
            return json.loads(get(base + path, 60))
        except Exception as e:
            last = e
    raise RuntimeError(f'Radio Browser niet bereikbaar: {last}')


def popular_stations(n_countries, per_country, n_world, all_stations=False):
    servers = rb_servers()
    q = lambda **kw: urllib.parse.urlencode(dict(hidebroken='true', order='clickcount', reverse='true', **kw))
    if all_stations:
        # alle werkende zenders van alle landen, populairste eerst (in blokken van 10.000); runs gaan verder via de cache
        out, offset = [], 0
        while True:
            part = rb_get('/json/stations/search?' + q(limit=10000, offset=offset), servers)
            out += part
            if len(part) < 10000:
                break
            offset += 10000
        print(f'alle zenders: {len(out)}')
        return out
    out = rb_get('/json/stations/search?' + q(limit=n_world), servers) if n_world else []
    countries = rb_get('/json/countries?order=stationcount&reverse=true&hidebroken=true', servers)
    codes = []
    for c in countries:
        cc = (c.get('iso_3166_1') or '').upper()
        if len(cc) == 2 and cc not in codes:
            codes.append(cc)
    for cc in codes[:n_countries]:
        try:
            out += rb_get('/json/stations/search?' + q(countrycode=cc, limit=per_country), servers)
        except Exception as e:
            print('land mislukt:', cc, e)
    return out


class Itunes:
    def __init__(self, delay):
        self.delay = delay
        self.last = 0.0
        self.calls = 0

    def search(self, term, cc):
        q = urllib.parse.urlencode({'term': term, 'entity': 'software', 'country': cc.lower(), 'limit': 8})
        for attempt in range(3):
            wait = self.last + self.delay - time.time()
            if wait > 0:
                time.sleep(wait)
            self.last = time.time()
            self.calls += 1
            try:
                return json.loads(get(f'{ITUNES}?{q}', 20)).get('results') or []
            except urllib.error.HTTPError as e:
                if e.code in (403, 429, 503):
                    # te veel verzoeken: even wachten en rustiger aan
                    self.delay = min(self.delay * 1.25, 8.0)
                    print(f'  iTunes {e.code}: wacht 60 s (vertraging nu {self.delay:.1f} s)')
                    time.sleep(60)
                    continue
                if e.code == 400:  # ongeldige store (land zonder App Store)
                    return None
                raise
            except Exception:
                time.sleep(5)
        raise RuntimeError('iTunes niet bereikbaar')


def lookup(itunes, name, cc, homepage, us_fallback=True):
    """App-icoon-URL voor een zender of '' (niets zekers gevonden)."""
    term = search_term(name)
    stores = [cc] if cc else []
    if us_fallback and cc != 'US':
        stores.append('US')
    for store in stores:
        res = itunes.search(term, store)
        if res is None:
            continue
        app = match_app(name, res, store, cc, homepage)
        if app:
            return icon_url(app.get('artworkUrl512') or app.get('artworkUrl100'))
    return ''


# ---------------------------------------------------------------- cache en uitvoer

def load_cache(path):
    try:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        return data.get('items', {}) if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_cache(path, items):
    if not path:
        return
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump({'v': 1, 'items': items}, fh, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    os.replace(tmp, path)


def is_fresh(entry, today):
    try:
        d = datetime.strptime(entry.get('d', ''), '%Y-%m-%d').date()
    except Exception:
        return False
    return today - d < timedelta(days=HIT_DAYS if entry.get('u') else MISS_DAYS)


def group(stations):
    """(cc, naamsleutel) → {name, homepage, clicks, uuids}; in volgorde van populariteit."""
    groups = {}
    for s in stations:
        name = re.sub(r'\s+', ' ', str(s.get('name') or '')).strip()
        uuid = str(s.get('stationuuid') or '').strip()
        k = norm_key(name)
        if not name or not uuid or not k:
            continue
        cc = str(s.get('countrycode') or '').upper()
        cc = cc if re.fullmatch(r'[A-Z]{2}', cc) else ''
        g = groups.setdefault((cc, k), {'name': name, 'homepage': '', 'clicks': 0, 'uuids': set()})
        g['uuids'].add(uuid)
        clicks = int(s.get('clickcount') or 0)
        if clicks >= g['clicks']:
            g['clicks'] = clicks
            g['name'] = name
            g['homepage'] = str(s.get('homepage') or '').strip() or g['homepage']
    return dict(sorted(groups.items(), key=lambda kv: -kv[1]['clicks']))


def write_output(groups, cache, out_dir=OUT_DIR):
    files = {}
    for (cc, k), g in groups.items():
        e = cache.get(f'{cc}|{k}') or {}
        url = e.get('u') or ''
        if not url:
            continue
        f = files.setdefault(cc or '_world', {'u': {}, 'n': {}})
        f['n'][k] = url
        for uuid in g['uuids']:
            f['u'][uuid] = url
    # ook treffers uit de cache van zenders die nu niet in de lijst staan (naam blijft bruikbaar)
    for ck, e in cache.items():
        if not e.get('u') or '|' not in ck:
            continue
        cc, k = ck.split('|', 1)
        files.setdefault(cc or '_world', {'u': {}, 'n': {}})['n'].setdefault(k, e['u'])
    # samenvoegen met wat er al staat (website-iconen, eerdere runs): één plek voor de voorrang,
    # tools/merge_icon_tables.py; er verdwijnt nooit iets
    merge_icon_tables.merge_into_dir(out_dir, appstore=files)
    return files


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--cache', default=os.path.join(ROOT, '.icons-cache.json'))
    ap.add_argument('--budget-min', type=float, default=330)
    ap.add_argument('--countries', type=int, default=60)
    ap.add_argument('--per-country', type=int, default=150)
    ap.add_argument('--world', type=int, default=2000)
    ap.add_argument('--all', action='store_true', help='alle zenders van alle landen (populairste eerst)')
    ap.add_argument('--delay', type=float, default=3.2)
    ap.add_argument('--no-us-fallback', action='store_true')
    ap.add_argument('--offline', action='store_true')
    ap.add_argument('--out', default=OUT_DIR)
    a = ap.parse_args(argv)

    start = time.time()
    deadline = start + a.budget_min * 60
    cache = load_cache(a.cache)
    print(f'cache: {len(cache)} namen ({sum(1 for e in cache.values() if e.get("u"))} met icoon)')
    groups = group(popular_stations(a.countries, a.per_country, a.world, a.all))
    print(f'{len(groups)} zendernamen')

    stop = {'now': False}
    signal.signal(signal.SIGTERM, lambda *_: stop.update(now=True))
    today = date.today()
    itunes = Itunes(a.delay)
    done = hits = 0
    todo = [(key, g) for key, g in groups.items() if not is_fresh(cache.get(f'{key[0]}|{key[1]}') or {}, today)]
    print(f'{len(todo)} nog op te zoeken')
    if not a.offline:
        for (cc, k), g in todo:
            if stop['now'] or time.time() > deadline:
                print('tijd op: de volgende run gaat verder')
                break
            try:
                url = lookup(itunes, g['name'], cc, g['homepage'], not a.no_us_fallback)
            except Exception as e:
                print('  iTunes mislukt:', g['name'], e)
                continue
            cache[f'{cc}|{k}'] = {'u': url, 'd': today.isoformat()}
            done += 1
            hits += bool(url)
            if url:
                print(f'  + {cc or "--"} {g["name"]}')
            if done % 50 == 0:
                save_cache(a.cache, cache)
                print(f'{done} opgezocht, {hits} iconen, {itunes.calls} verzoeken, {(time.time() - start) / 60:.0f} min')
    save_cache(a.cache, cache)
    files = write_output(groups, cache, a.out)
    total = sum(len(f['n']) for f in files.values())
    print(f'klaar: {done} opgezocht ({hits} iconen) · {len(files)} bestanden · {total} namen met icoon')


if __name__ == '__main__':
    main()

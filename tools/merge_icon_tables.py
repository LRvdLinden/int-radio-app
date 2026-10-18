#!/usr/bin/env python3
"""De zendericoon-tabellen samenvoegen: één plek voor de voorrang tussen de bronnen (workflow Icons, SPEC §1).

Tabel: website/assets/data/icons/<CC>.json (+ _world.json) = {"u": {stationuuid: url}, "n": {naamsleutel: url}}.
Twee jobs schrijven dezelfde vorm:
- tools/make_station_icons.py ("appstore"): het app-icoon uit de App Store via de iTunes-zoekfunctie (mzstatic.com);
- tools/make_site_icons.py ("site"): per zender het beste van: het App Store-icoon van de app waar de website van
  de zender naar linkt (smart app banner / App Store-link, exact via iTunes lookup; mzstatic.com), het Google
  Play-icoon (Play-link op de website of Play-zoekfunctie; play-lh.googleusercontent.com) of het app-icoon van de
  website zelf (manifest / apple-touch-icon).

De soort bron volgt uit de host van de URL (`url_rank`): App Store (mzstatic) > Google Play (play-lh) > website.
Voorrang per sleutel (uuid of naamsleutel), in `merge`: de hoogste soort wint; bij gelijke soort wint de App
Store-zoekjob van deze run, dan de site-job van deze run, dan wat er al stond. Een betere bron vervangt dus een
slechtere voor dezelfde zender, nooit andersom. Er verdwijnt nooit iets uit een bestaande tabel, en er worden geen
bestanden verwijderd.

Gebruik (workflow Icons, job publish):
    python3 tools/merge_icon_tables.py tables --existing DIR [--appstore DIR] [--site DIR] --out DIR [--sources FILE]
    python3 tools/merge_icon_tables.py cache A.json B.json --out C.json   (cache-items: nieuwste datum wint)
"""
import argparse, json, os, sys, urllib.parse


def _host(url):
    try:
        return (urllib.parse.urlparse(str(url or '')).hostname or '').lower()
    except ValueError:
        return ''


def is_appstore_url(url):
    h = _host(url)
    return h == 'mzstatic.com' or h.endswith('.mzstatic.com')


def is_play_url(url):
    return _host(url) == 'play-lh.googleusercontent.com'


def url_rank(url):
    """Soort bron van een icoon-URL: 3 = App Store, 2 = Google Play, 1 = website, 0 = leeg."""
    if not url:
        return 0
    if is_appstore_url(url):
        return 3
    if is_play_url(url):
        return 2
    return 1


# bronlabel (sources.json, alleen debug) per (herkomst, soort)
_LABELS = {
    ('a', 3): 'appstore', ('a', 2): 'appstore', ('a', 1): 'appstore',
    ('s', 3): 'appstore-link', ('s', 2): 'play', ('s', 1): 'site',
    ('e', 3): 'appstore-kept', ('e', 2): 'play-kept', ('e', 1): 'kept',
}


def empty():
    return {'u': {}, 'n': {}}


def load_dir(path):
    """{bestandsnaam zonder .json: tabel} uit een map (ontbrekende map of kapot bestand = leeg)."""
    out = {}
    if not path or not os.path.isdir(path):
        return out
    for fn in sorted(os.listdir(path)):
        if not fn.endswith('.json'):
            continue
        try:
            with open(os.path.join(path, fn), encoding='utf-8') as fh:
                data = json.load(fh)
        except Exception:
            continue
        if isinstance(data, dict):
            out[fn[:-5]] = {'u': dict(data.get('u') or {}), 'n': dict(data.get('n') or {})}
    return out


def merge(existing=None, appstore=None, site=None):
    """Tabellen samenvoegen. Geeft (tabellen, bronnen); bronnen = {bestand: {"u"/"n": {sleutel: bron}}} met bron
    "appstore" (zoekjob), "appstore-link" (exacte App Store-app van de website), "play", "site", of
    "appstore-kept" / "play-kept" / "kept" (stond er al). Alleen voor debug, niet in de openbare tabellen."""
    existing, appstore, site = existing or {}, appstore or {}, site or {}
    tables, sources = {}, {}
    for f in sorted(set(existing) | set(appstore) | set(site)):
        e, a, s = existing.get(f) or empty(), appstore.get(f) or empty(), site.get(f) or empty()
        t, src = empty(), {'u': {}, 'n': {}}
        for sec in ('u', 'n'):
            keys = set(e.get(sec) or {}) | set(a.get(sec) or {}) | set(s.get(sec) or {})
            for k in keys:
                # (url, herkomst) in volgorde van voorkeur bij gelijke soort
                cands = [((a.get(sec) or {}).get(k), 'a'), ((s.get(sec) or {}).get(k), 's'),
                         ((e.get(sec) or {}).get(k), 'e')]
                best, rank, origin = None, 0, ''
                for url, o in cands:
                    r = url_rank(url)
                    if o == 'a' and r:
                        r = 3  # de App Store-job levert alleen App Store-iconen
                    if r > rank:
                        best, rank, origin = url, r, o
                if best:
                    t[sec][k], src[sec][k] = best, _LABELS[(origin, rank)]
        if t['u'] or t['n']:
            tables[f], sources[f] = t, src
    return tables, sources


def write_dir(tables, out_dir):
    """Schrijf de tabellen (gesorteerd, compact). Verwijdert nooit bestanden."""
    os.makedirs(out_dir, exist_ok=True)
    for name, data in tables.items():
        data = {'u': dict(sorted(data['u'].items())), 'n': dict(sorted(data['n'].items()))}
        tmp = os.path.join(out_dir, name + '.json.tmp')
        with open(tmp, 'w', encoding='utf-8') as fh:
            json.dump(data, fh, ensure_ascii=False, separators=(',', ':'))
        os.replace(tmp, os.path.join(out_dir, name + '.json'))


def merge_into_dir(out_dir, appstore=None, site=None):
    """Nieuwe resultaten van één bron in een bestaande tabellenmap zetten (met de voorrang van `merge`)."""
    tables, sources = merge(load_dir(out_dir), appstore, site)
    write_dir(tables, out_dir)
    return tables, sources


# ---------------------------------------------------------------- caches

def load_items(path):
    try:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        return dict(data.get('items') or {}) if isinstance(data, dict) else {}
    except Exception:
        return {}


def merge_caches(a, b):
    """Cache-items samenvoegen: per sleutel de nieuwste datum ("d"); bij gelijke datum wint een treffer, daarna b."""
    out = dict(a or {})
    for k, v in (b or {}).items():
        old = out.get(k)
        if not isinstance(old, dict) or not isinstance(v, dict):
            out[k] = v
            continue
        if (v.get('d') or '', bool(v.get('u'))) >= (old.get('d') or '', bool(old.get('u'))):
            out[k] = v
    return out


def save_items(path, items, extra=None):
    data = {'v': 1, 'items': items}
    data.update(extra or {})
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    os.replace(tmp, path)


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    t = sub.add_parser('tables')
    t.add_argument('--existing', required=True)
    t.add_argument('--appstore')
    t.add_argument('--site')
    t.add_argument('--out', required=True)
    t.add_argument('--sources')
    c = sub.add_parser('cache')
    c.add_argument('files', nargs='+')
    c.add_argument('--out', required=True)
    a = ap.parse_args(argv)

    if a.cmd == 'cache':
        items, extra = {}, {}
        for p in a.files:
            items = merge_caches(items, load_items(p))
            try:
                with open(p, encoding='utf-8') as fh:
                    d = json.load(fh)
                for k, v in d.items():  # extra velden (bijv. "generic" van de site-cache): laatste bestand wint
                    if k not in ('v', 'items'):
                        extra[k] = v
            except Exception:
                pass
        save_items(a.out, items, extra)
        print(f'cache: {len(items)} items -> {a.out}')
        return

    before = load_dir(a.existing)
    tables, sources = merge(before, load_dir(a.appstore), load_dir(a.site))
    write_dir(tables, a.out)
    count = lambda ts: sum(len(x['n']) + len(x['u']) for x in ts.values())
    by = {}
    for f in sources.values():
        for sec in f.values():
            for v in sec.values():
                by[v] = by.get(v, 0) + 1
    print(f'tabellen: {len(tables)} bestanden, {count(before)} -> {count(tables)} sleutels; bronnen: {by}')
    if count(tables) < count(before):  # kan niet (merge verwijdert niets), maar nooit stilletjes minder publiceren
        sys.exit('minder sleutels dan ervoor: gestopt')
    if a.sources:
        with open(a.sources, 'w', encoding='utf-8') as fh:
            json.dump({'v': 1, 'sources': sources}, fh, ensure_ascii=False, separators=(',', ':'), sort_keys=True)


if __name__ == '__main__':
    main()

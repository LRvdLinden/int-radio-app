#!/usr/bin/env python3
"""De zendericoon-tabellen samenvoegen: één plek voor de voorrang tussen de bronnen (workflow Icons, SPEC §1).

Tabel: website/assets/data/icons/<CC>.json (+ _world.json) = {"u": {stationuuid: url}, "n": {naamsleutel: url}}.
Twee bronnen schrijven dezelfde vorm:
- tools/make_station_icons.py: het app-icoon uit de App Store (mzstatic.com), de mooiste bron;
- tools/make_site_icons.py: het app-icoon van de eigen website van de zender (manifest / apple-touch-icon).

Voorrang per sleutel (uuid of naamsleutel), in `merge`:
  1. App Store-icoon van deze run;
  2. App Store-icoon dat al in de tabel stond;
  3. website-icoon van deze run;
  4. wat er al stond.
Er verdwijnt nooit iets uit een bestaande tabel, en er worden geen bestanden verwijderd.

Gebruik (workflow Icons, job publish):
    python3 tools/merge_icon_tables.py tables --existing DIR [--appstore DIR] [--site DIR] --out DIR [--sources FILE]
    python3 tools/merge_icon_tables.py cache A.json B.json --out C.json   (cache-items: nieuwste datum wint)
"""
import argparse, json, os, sys, urllib.parse


def is_appstore_url(url):
    try:
        h = (urllib.parse.urlparse(str(url or '')).hostname or '').lower()
    except ValueError:
        return False
    return h == 'mzstatic.com' or h.endswith('.mzstatic.com')


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
    "appstore", "appstore-kept", "site" of "kept" (alleen voor de cache/debug, niet in de openbare tabellen)."""
    existing, appstore, site = existing or {}, appstore or {}, site or {}
    tables, sources = {}, {}
    for f in sorted(set(existing) | set(appstore) | set(site)):
        e, a, s = existing.get(f) or empty(), appstore.get(f) or empty(), site.get(f) or empty()
        t, src = empty(), {'u': {}, 'n': {}}
        for sec in ('u', 'n'):
            keys = set(e.get(sec) or {}) | set(a.get(sec) or {}) | set(s.get(sec) or {})
            for k in keys:
                av, ev, sv = (a.get(sec) or {}).get(k), (e.get(sec) or {}).get(k), (s.get(sec) or {}).get(k)
                if av:
                    t[sec][k], src[sec][k] = av, 'appstore'
                elif ev and is_appstore_url(ev):
                    t[sec][k], src[sec][k] = ev, 'appstore-kept'
                elif sv:
                    t[sec][k], src[sec][k] = sv, 'site'
                elif ev:
                    t[sec][k], src[sec][k] = ev, 'kept'
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

#!/usr/bin/env python3
"""Echte podcasts voor het podcastvoorbeeld op tunr.online (sectie "Radio en podcasts in één app").

Haalt de top 3 van de Apple Podcasts-toplijst van Nederland op (openbare RSS-feed van Apple, zonder sleutel),
downloadt de covers en schrijft ze vast weg, net als de hero-logo's (tools/make_wall.py):
  website/assets/img/showcase/pod1.webp … pod3.webp   (256 × 256)
  website/assets/js/showcase.js                        window.TUNR_SHOWCASE = {pods: [{n, a, i}]}
home.js vult daarmee het voorbeeld; zonder dit bestand blijven de gekleurde letterblokjes staan.
Opnieuw maken: workflow Website met "Hero-logo's vernieuwen".
"""
import io, json, os, sys, urllib.request
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_IMG = os.path.join(ROOT, 'website', 'assets', 'img', 'showcase')
OUT_JS = os.path.join(ROOT, 'website', 'assets', 'js', 'showcase.js')
UA = {'User-Agent': 'Tunr/1.0.1 (+https://tunr.online)'}
FEED = 'https://rss.applemarketingtools.com/api/v2/nl/podcasts/top/10/podcasts.json'
SEARCH = 'https://itunes.apple.com/search?media=podcast&entity=podcast&country=nl&limit=1&term='
SIZE = 256


def get(url, timeout=25):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()


LEGACY = 'https://itunes.apple.com/nl/rss/toppodcasts/limit=10/json'
LOOKUP = 'https://itunes.apple.com/lookup?country=nl&id='


def top_podcasts():
    """[(naam, maker, cover-URL)] uit de toplijst; eerst de nieuwe RSS-feed, anders de oude iTunes-feed + lookup."""
    try:
        feed = json.loads(get(FEED))
        rows = [(r.get('name'), r.get('artistName'), (r.get('artworkUrl100') or '').replace('100x100bb', '600x600bb'))
                for r in (feed.get('feed') or {}).get('results') or []]
        if rows:
            return rows
    except Exception as e:
        print(f'  toplijst (RSS) niet opgehaald: {e}', file=sys.stderr)
    feed = json.loads(get(LEGACY))
    rows = []
    for en in (feed.get('feed') or {}).get('entry') or []:
        name = ((en.get('im:name') or {}).get('label') or '').strip()
        artist = ((en.get('im:artist') or {}).get('label') or '').strip()
        pid = (((en.get('id') or {}).get('attributes') or {}).get('im:id') or '').strip()
        art = ''
        if pid:
            try:
                res = json.loads(get(LOOKUP + pid)).get('results') or []
                art = (res[0].get('artworkUrl600') if res else '') or ''
            except Exception as e:
                print(f'  lookup {pid} mislukt: {e}', file=sys.stderr)
        if not art:
            imgs = en.get('im:image') or []
            art = (imgs[-1].get('label') if imgs else '') or ''
        rows.append((name, artist, art))
    return rows


def main():
    results = top_podcasts()
    pods = []
    os.makedirs(OUT_IMG, exist_ok=True)
    for name, artist, art in results:
        if len(pods) == 3:
            break
        name, artist = (name or '').strip(), (artist or '').strip()
        if not name or not art:
            continue
        try:
            img = Image.open(io.BytesIO(get(art))).convert('RGB')
        except Exception as e:
            print(f'  cover van {name} niet opgehaald: {e}', file=sys.stderr)
            continue
        if min(img.size) < 200:
            continue
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
        fn = f'pod{len(pods) + 1}.webp'
        img.save(os.path.join(OUT_IMG, fn), quality=86, method=6)
        pods.append({'n': name, 'a': artist, 'i': fn})
        print(f'{fn}: {name} — {artist}')
    if len(pods) < 3:
        sys.exit(f'FOUT: maar {len(pods)} podcasts met cover gevonden')
    with open(OUT_JS, 'w', encoding='utf-8') as f:
        f.write('// Gemaakt door tools/make_showcase.py: echte top-3-podcasts van Nederland (Apple Podcasts-toplijst) '
                'voor het podcastvoorbeeld op de homepage.\n')
        f.write('window.TUNR_SHOWCASE = ' + json.dumps({'pods': pods}, ensure_ascii=False, separators=(',', ':')) + ';\n')
    print('klaar:', OUT_JS)


if __name__ == '__main__':
    main()

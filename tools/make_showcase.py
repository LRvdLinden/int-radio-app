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


def main():
    feed = json.loads(get(FEED))
    results = (feed.get('feed') or {}).get('results') or []
    pods = []
    os.makedirs(OUT_IMG, exist_ok=True)
    for r in results:
        if len(pods) == 3:
            break
        name, artist = (r.get('name') or '').strip(), (r.get('artistName') or '').strip()
        art = r.get('artworkUrl100') or ''
        if not name or not art:
            continue
        art = art.replace('100x100bb', '600x600bb')
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

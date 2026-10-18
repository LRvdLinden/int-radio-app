#!/usr/bin/env python3
"""Offline tests voor tools/make_site_icons.py (website-iconen) en tools/merge_icon_tables.py (voorrang).
Geen netwerk: vaste HTML/manifesten en een nep-Fetcher met plaatjes uit Pillow.

    python3 tools/test_site_icons.py
"""
import io, json, os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_site_icons as si  # noqa: E402
import merge_icon_tables as mt  # noqa: E402

PAGE = 'https://www.radio538.nl/luister/'
HTML = '''<!doctype html><html><head>
<base href="https://www.radio538.nl/">
<link rel="manifest" href="/site.webmanifest">
<link rel="apple-touch-icon" href="img/touch-120.png" sizes="120x120">
<link rel="apple-touch-icon" sizes="180x180" href="img/touch-180.png">
<link rel="apple-touch-icon-precomposed" href="//cdn.radio538.nl/pre.png">
<link rel="icon" type="image/png" sizes="32x32" href="/fav-32.png">
<link rel="icon" type="image/png" sizes="192x192" href="/fav-192.png">
<link rel="icon" type="image/svg+xml" sizes="any" href="/fav.svg">
<link rel="mask-icon" href="/safari.svg" color="#f00">
<meta property="og:image" content="/og.jpg">
</head><body><link rel="icon" href="/late.png" sizes="512x512"></body></html>'''
MANIFEST = {'icons': [
    {'src': 'icons/48.png', 'sizes': '48x48', 'type': 'image/png'},
    {'src': 'icons/mask-512.png', 'sizes': '512x512', 'purpose': 'maskable'},
    {'src': 'icons/192.png', 'sizes': '192x192', 'purpose': 'any'},
    {'src': 'icons/384.png', 'sizes': '384x384'},
    {'src': 'icons/mono.png', 'sizes': '512x512', 'purpose': 'monochrome'},
    {'src': 'icons/logo.svg', 'sizes': 'any', 'type': 'image/svg+xml'},
    {'src': 'icons/wide.png', 'sizes': '512x256'},
]}


def png(w=256, h=256, kind='logo', fmt='PNG'):
    from PIL import Image, ImageDraw
    im = Image.new('RGBA', (w, h), (255, 255, 255, 0) if kind == 'blank' else (220, 30, 40, 255))
    if kind == 'logo':
        d = ImageDraw.Draw(im)
        d.ellipse((w * 0.2, h * 0.2, w * 0.8, h * 0.8), fill=(255, 255, 255, 255))
        d.rectangle((w * 0.45, h * 0.1, w * 0.55, h * 0.9), fill=(20, 20, 20, 255))
    buf = io.BytesIO()
    im.convert('RGB' if fmt == 'JPEG' else 'RGBA').save(buf, fmt)
    return buf.getvalue()


class FakeFetcher:
    """Antwoorden per URL: (content-type, bytes) of een Exception."""

    def __init__(self, routes):
        import threading
        self.routes, self.stop, self.calls, self.seen = routes, threading.Event(), 0, []

    def get(self, url, limit, accept='*/*', truncate=False):
        self.seen.append(url)
        r = self.routes.get(url)
        if r is None:
            raise si.Blocked('404')
        if isinstance(r, Exception):
            raise r
        ctype, data = r
        if isinstance(data, str):
            data = data.encode()
        return url, ctype, data[:limit]


class Parse(unittest.TestCase):
    def test_sizes(self):
        self.assertEqual(si.parse_sizes('192x192 512X512 any'), [(192, 192), (512, 512)])
        self.assertEqual(si.square_side(si.parse_sizes('512x256 180x180')), 180)
        self.assertEqual(si.square_side(si.parse_sizes('any')), 0)
        self.assertEqual(si.parse_sizes(None), [])

    def test_html_candidates(self):
        cands, manifest = si.html_candidates(HTML, PAGE)
        self.assertEqual(manifest, 'https://www.radio538.nl/site.webmanifest')
        urls = [c['url'] for c in cands]
        # apple-touch-icons grootste eerst (zonder sizes = 180), dan icon ≥ 192, dan og:image
        self.assertEqual(urls[0], 'https://www.radio538.nl/img/touch-180.png')
        self.assertIn('https://cdn.radio538.nl/pre.png', urls[:2])  # protocol-relatief opgelost
        self.assertEqual(urls[2], 'https://www.radio538.nl/img/touch-120.png')
        self.assertIn('https://www.radio538.nl/fav-192.png', urls)
        self.assertIn('https://www.radio538.nl/late.png', urls)
        self.assertNotIn('https://www.radio538.nl/fav-32.png', urls)
        self.assertNotIn('https://www.radio538.nl/fav.svg', urls)
        self.assertNotIn('https://www.radio538.nl/safari.svg', urls)
        self.assertEqual(cands[-1], {'url': 'https://www.radio538.nl/og.jpg', 'size': 0, 'kind': 'og'})

    def test_relative_resolution_without_base(self):
        html = '<link rel=apple-touch-icon href="../img/t.png"><link rel="Manifest" href="m.json">'
        cands, manifest = si.html_candidates(html, 'http://example.fm/a/b/index.html')
        self.assertEqual(cands[0]['url'], 'http://example.fm/a/img/t.png')
        self.assertEqual(manifest, 'http://example.fm/a/b/m.json')
        self.assertEqual(si.resolve('https://x.fm/', 'data:image/png;base64,AAA'), '')
        self.assertEqual(si.resolve('https://x.fm/', 'javascript:void(0)'), '')
        self.assertEqual(si.resolve('https://x.fm/p', 'img.png#frag'), 'https://x.fm/img.png')

    def test_manifest_candidates(self):
        c = si.manifest_candidates(json.dumps(MANIFEST), 'https://www.radio538.nl/app/site.webmanifest')
        urls = [x['url'].rsplit('/', 1)[1] for x in c]
        # purpose any/leeg eerst (grootste eerst), alleen-maskable daarna; mono, svg, klein en niet-vierkant weg
        self.assertEqual(urls, ['384.png', '192.png', 'mask-512.png'])
        self.assertTrue(c[0]['url'].startswith('https://www.radio538.nl/app/icons/'))  # relatief t.o.v. manifest
        self.assertEqual(si.manifest_candidates('niet json', 'https://x/'), [])
        self.assertEqual(si.manifest_candidates('{"icons": "x"}', 'https://x/'), [])

    def test_order_and_reject(self):
        man = si.manifest_candidates(json.dumps(MANIFEST), 'https://a.fm/m.json')
        html = [{'url': 'https://a.fm/icons/384.png', 'size': 384, 'kind': 'icon'},
                {'url': 'https://a.fm/wp-includes/images/w-logo-blue.png', 'size': 180, 'kind': 'apple-touch'}]
        out = si.order_candidates(man, html)
        self.assertEqual([c['url'] for c in out].count('https://a.fm/icons/384.png'), 1)
        self.assertEqual(out[0]['kind'], 'manifest')
        self.assertFalse(any('w-logo' in c['url'] for c in out))

    def test_reject_url(self):
        for u in ['https://a.fm/wp-includes/images/w-logo-blue-white-bg.png', 'https://a.fm/favicon.ico',
                  'https://a.fm/x/icon.ICO', 'https://a.fm/logo.svg', 'https://static.a.fm/wix/app.png',
                  'https://a.fm/universal/default-favicon.png', 'https://s0.wp.com/i/webclip.png',
                  'https://www.blogger.com/img/x.png', 'https://a.fm/squarespace/touch.png']:
            self.assertTrue(si.reject_url(u), u)
        for u in ['https://a.fm/apple-touch-icon.png', 'https://cdn.a.fm/img/logo-512.png?v=2']:
            self.assertFalse(si.reject_url(u), u)

    def test_hosts(self):
        self.assertEqual(si.site_host('www.Radio538.nl/luister'), 'radio538.nl')
        self.assertEqual(si.site_host('https://m.qmusic.nl/'), 'm.qmusic.nl')
        self.assertEqual(si.site_host('http://192.168.1.5/'), '')
        self.assertEqual(si.site_host('localhost'), '')
        self.assertTrue(si.skip_host('m.facebook.com'))
        self.assertTrue(si.skip_host('tunein.com'))
        self.assertFalse(si.skip_host('notfacebook.com'))
        self.assertEqual(si.root_candidates('http://www.a.fm/x')[0]['url'], 'https://www.a.fm/apple-touch-icon.png')

    def test_site_groups_shared_host(self):
        groups = {('US', f'k{i}'): {'name': f'Station {i} Radio', 'homepage': f'https://network.com/s/{i}',
                                    'uuids': {f'u{i}'}, 'clicks': 1} for i in range(7)}
        groups[('NL', 'qmusic')] = {'name': 'Qmusic', 'homepage': 'https://qmusic.nl', 'uuids': {'q'}, 'clicks': 9}
        groups[('NL', 'fb')] = {'name': 'FB FM', 'homepage': 'https://facebook.com/fbfm', 'uuids': {'f'}, 'clicks': 9}
        hosts = si.site_groups(groups)
        self.assertEqual(list(hosts), ['qmusic.nl'])


@unittest.skipIf(si.Image is None, 'Pillow ontbreekt')
class Images(unittest.TestCase):
    def test_check_image(self):
        self.assertTrue(si.check_image(png())[0])
        self.assertTrue(si.check_image(png(300, 280, fmt='JPEG'))[0])
        self.assertEqual(si.check_image(png(100, 100))[1], 'small')
        self.assertEqual(si.check_image(png(400, 200))[1], 'not-square')
        self.assertEqual(si.check_image(png(kind='blank'))[1], 'blank')
        self.assertEqual(si.check_image(png(kind='flat'))[1], 'blank')
        self.assertEqual(si.check_image(b'<html>nope</html>')[1], 'not-image')
        self.assertEqual(si.check_image(png(fmt='GIF'))[1], 'format')
        fp = si.check_image(png())[2]
        self.assertEqual(si.check_image(png(), generic={fp})[1], 'generic')

    def test_find_icon_manifest_first_and_https(self):
        f = FakeFetcher({
            'http://radio.fm/': ('text/html; charset=utf-8',
                                 '<link rel=manifest href=/m.json><link rel=apple-touch-icon href=/t.png>'),
            'http://radio.fm/m.json': ('application/json', json.dumps({'icons': [
                {'src': '/i/512.png', 'sizes': '512x512'}, {'src': '/i/192.png', 'sizes': '192x192'}]})),
            # 512 alleen via http geldig → niet gebruiken; 192 ook via https → die
            'https://radio.fm/i/512.png': si.Blocked('tls'),
            'https://radio.fm/i/192.png': ('image/png', png(192, 192)),
            'https://radio.fm/t.png': ('image/png', png(180, 180)),
        })
        res = si.find_icon(f, 'radio.fm/')
        self.assertEqual(res['u'], 'https://radio.fm/i/192.png')
        self.assertEqual(res['via'], 'manifest')
        self.assertNotIn('http://radio.fm/i/512.png', f.seen)  # nooit het http-plaatje

    def test_find_icon_skips_bad_then_root_fallback(self):
        f = FakeFetcher({
            'https://a.fm': ('text/html', '<p>geen iconen</p>'),
            'https://a.fm/apple-touch-icon.png': ('image/png', png(57, 57)),
            'https://a.fm/apple-touch-icon-precomposed.png': ('image/png', png(152, 152)),
        })
        res = si.find_icon(f, 'https://a.fm')
        self.assertEqual(res, {'u': 'https://a.fm/apple-touch-icon-precomposed.png', 'h': res['h'], 'via': 'root',
                               'sl': 1})

    def test_find_icon_miss(self):
        f = FakeFetcher({'https://b.fm': ('text/html', '<link rel="apple-touch-icon" href="/t.png">'),
                         'https://b.fm/t.png': ('image/png', png(kind='blank'))})
        res = si.find_icon(f, 'https://b.fm')
        self.assertEqual(res['u'], '')
        self.assertEqual(res['r'], 'blank')
        self.assertEqual(si.find_icon(FakeFetcher({}), 'https://down.fm')['u'], '')


class Generic(unittest.TestCase):
    def test_find_generic(self):
        items = {f'site{i}.com': {'u': f'https://site{i}.com/t.png', 'h': 'aaaa'} for i in range(5)}
        names = {f'site{i}.com': [n] for i, n in enumerate(['Rock Ola', 'Jazz Kat', 'Pop Zon', 'Folk Uil', 'Lo Fi'])}
        # zelfde netwerk (gedeelde naam "maria") is geen standaardicoon
        items.update({f'radiomaria.{t}': {'u': 'https://x/m.png', 'h': 'bbbb'} for t in ['nl', 'de', 'it', 'pl']})
        names.update({f'radiomaria.{t}': ['Radio Maria ' + t.upper()] for t in ['nl', 'de', 'it', 'pl']})
        self.assertEqual(si.find_generic(items, names), {'aaaa'})

    def test_freshness(self):
        from datetime import date
        today = date(2026, 10, 17)
        self.assertTrue(si.is_fresh({'u': '', 'd': '2026-09-01', 'sl': 1}, today))
        self.assertFalse(si.is_fresh({'u': '', 'd': '2026-08-01', 'sl': 1}, today))
        self.assertTrue(si.is_fresh({'u': 'x', 'd': '2026-07-01', 'sl': 1}, today))
        self.assertFalse(si.is_fresh({'u': 'x', 'd': '2026-06-01', 'sl': 1}, today))
        # van voor de store-links: opnieuw ophalen, ook als hij nog vers is
        self.assertFalse(si.is_fresh({'u': 'x', 'd': '2026-10-01'}, today))


APP = 'https://is1-ssl.mzstatic.com/image/thumb/a/256x256bb.png'
APP_OLD = 'https://is2-ssl.mzstatic.com/image/thumb/old/256x256bb.png'
SITE = 'https://qmusic.nl/apple-touch-icon.png'
SITE_OLD = 'https://qmusic.nl/old-touch.png'


class Merge(unittest.TestCase):
    def test_priority(self):
        existing = {'NL': {'u': {'u1': APP_OLD, 'u2': SITE_OLD, 'u3': SITE_OLD, 'u9': SITE_OLD},
                           'n': {'qmusic': APP_OLD, 'skyradio': SITE_OLD}}}
        appstore = {'NL': {'u': {'u3': APP}, 'n': {}}}
        site = {'NL': {'u': {'u1': SITE, 'u2': SITE, 'u3': SITE}, 'n': {'qmusic': SITE, 'skyradio': SITE}},
                'BE': {'u': {'b1': SITE}, 'n': {}}}
        t, src = mt.merge(existing, appstore, site)
        self.assertEqual(t['NL']['u'], {'u1': APP_OLD, 'u2': SITE, 'u3': APP, 'u9': SITE_OLD})
        self.assertEqual(t['NL']['n'], {'qmusic': APP_OLD, 'skyradio': SITE})
        self.assertEqual(t['BE']['u'], {'b1': SITE})
        self.assertEqual(src['NL']['u'], {'u1': 'appstore-kept', 'u2': 'site', 'u3': 'appstore', 'u9': 'kept'})

    def test_appstore_beats_existing_site(self):
        t, _ = mt.merge({'NL': {'u': {'u1': SITE}, 'n': {}}}, {'NL': {'u': {'u1': APP}, 'n': {}}}, None)
        self.assertEqual(t['NL']['u']['u1'], APP)

    def test_never_drops_and_dir_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            mt.write_dir({'NL': {'u': {'u1': APP}, 'n': {'a': SITE}}, 'DE': {'u': {}, 'n': {'x': SITE}}}, d)
            with open(os.path.join(d, 'notes.txt'), 'w') as fh:
                fh.write('x')
            mt.merge_into_dir(d, site={'NL': {'u': {'u1': SITE, 'u2': SITE}, 'n': {}}})
            got = mt.load_dir(d)
            self.assertEqual(got['NL'], {'u': {'u1': APP, 'u2': SITE}, 'n': {'a': SITE}})
            self.assertEqual(got['DE']['n'], {'x': SITE})
            self.assertTrue(os.path.exists(os.path.join(d, 'notes.txt')))
            # CLI: zelfde vorm, sources apart
            src = os.path.join(d, 'sources.json')
            site_dir = os.path.join(d, 'site')
            mt.write_dir({'FR': {'u': {'f1': SITE}, 'n': {}}}, site_dir)
            mt.main(['tables', '--existing', d, '--site', site_dir, '--out', d, '--sources', src])
            self.assertEqual(mt.load_dir(d)['FR']['u'], {'f1': SITE})
            with open(src) as fh:
                self.assertEqual(json.load(fh)['sources']['FR']['u']['f1'], 'site')

    def test_merge_caches(self):
        a = {'x': {'u': 'A', 'd': '2026-10-01'}, 'y': {'u': '', 'd': '2026-10-05'}, 'z': {'u': 'Z', 'd': '2026-10-01'}}
        b = {'x': {'u': '', 'd': '2026-09-01'}, 'y': {'u': 'B', 'd': '2026-10-05'}, 'w': {'u': 'W', 'd': '2026-10-02'},
             'z': {'u': '', 'd': '2026-10-02'}}
        m = mt.merge_caches(a, b)
        self.assertEqual(m['x']['u'], 'A')   # ouder in b: a blijft
        self.assertEqual(m['y']['u'], 'B')   # zelfde datum: treffer wint
        self.assertEqual(m['z']['u'], '')    # nieuwer in b wint
        self.assertEqual(m['w']['u'], 'W')

    def test_station_writer_keeps_site_icons(self):
        import make_station_icons as ms
        groups = ms.group([{'name': 'Qmusic', 'stationuuid': 'u1', 'countrycode': 'NL', 'clickcount': 5},
                           {'name': 'Sky Radio', 'stationuuid': 'u2', 'countrycode': 'NL', 'clickcount': 4}])
        with tempfile.TemporaryDirectory() as d:
            mt.write_dir({'NL': {'u': {'u2': SITE}, 'n': {'skyradio': SITE}}, 'BE': {'u': {}, 'n': {'x': SITE}}}, d)
            ms.write_output(groups, {'NL|qmusic': {'u': APP, 'd': '2026-10-01'}}, d)
            got = mt.load_dir(d)
            self.assertEqual(got['NL']['u'], {'u1': APP, 'u2': SITE})
            self.assertIn('BE', got)


if __name__ == '__main__':
    unittest.main(verbosity=1)

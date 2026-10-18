#!/usr/bin/env python3
"""Offline tests voor tools/store_icons.py (store-links, Google Play) en de nieuwe voorrang in
tools/merge_icon_tables.py / tools/make_site_icons.py. Geen netwerk: vaste HTML en een nep-Fetcher.

    python3 tools/test_store_icons.py
"""
import json, os, sys, tempfile, threading, unittest, urllib.error, urllib.parse
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_site_icons as si  # noqa: E402
import merge_icon_tables as mt  # noqa: E402
import store_icons as st  # noqa: E402
from test_site_icons import png  # noqa: E402

# ---------------------------------------------------------------- fixtures

HOME = '''<!doctype html><html><head>
<meta name="apple-itunes-app" content="app-id=373589722, app-argument=https://www.radio538.nl/">
<meta name="google-play-app" content="app-id=nl.talpa.radio538">
<link rel="alternate" href="android-app://nl.talpa.radio538/https/www.radio538.nl/">
<link rel="apple-touch-icon" href="/t.png">
</head><body>
<footer>
 <a href="https://apps.apple.com/nl/app/radio-538/id373589722?mt=8"><img src="/badge-ios.svg"></a>
 <a href="https://play.google.com/store/apps/details?hl=nl&amp;id=nl.talpa.radio538"><img src="/badge-gp.svg"></a>
 <a href="https://itunes.apple.com/app/id1234567890">Andere app</a>
 <a href="market://details?id=com.example.other">Andere</a>
</footer>
<script>window.__DATA__={"tunein":"https:\\/\\/play.google.com\\/store\\/apps\\/details?id=tunein.player"}</script>
</body></html>'''

# realistisch fragment van https://play.google.com/store/search?q=Radio+538&c=apps (class-namen veranderen vaak:
# de parser kijkt alleen naar links, plaatjes en tekst)
PLAY_SEARCH = '''<!doctype html><html lang="nl"><head><title>Radio 538 - Apps op Google Play</title></head><body>
<c-wiz><div class="ULeU3b"><div class="Vfr1Fe">
  <a class="Qfxief" href="/store/apps/details?id=nl.talpa.radio538" aria-label="Radio 538">
    <img src="https://play-lh.googleusercontent.com/aB3_xYz-123/rest_ID=s64-rw" class="T75of stzEZd"
         alt="Pictogramafbeelding" srcset="https://play-lh.googleusercontent.com/aB3_xYz-123/rest_ID=s128-rw 2x">
  </a>
  <div class="vWM94c">Radio 538</div><div class="LbQbAe">Talpa Network B.V.</div>
  <a href="/store/apps/details?id=nl.talpa.radio538"><span>Installeren</span></a>
</div></div>
<div role="listitem" class="VfPpkd-EScbFb-JIbuQc">
  <a class="Si6A0c Gy4nib" href="/store/apps/details?id=com.fanapps.radio538nl&amp;referrer=x">
    <div class="j2FCNc"><img src="https://play-lh.googleusercontent.com/FAN123=s64-rw" alt="Pictogramafbeelding">
      <div class="cXFu1"><div class="ubGTjb"><span class="DdYX5">538 Radio App NL Gratis</span></div>
      <div class="ubGTjb"><span class="wMUdtb">FanDev Studio</span></div>
      <div class="ubGTjb"><span class="w2kbF">4,1</span><span class="Q4fJQd">star</span></div></div></div>
  </a>
</div>
<div role="listitem">
  <a class="Si6A0c Gy4nib" href="/store/apps/details?id=nl.radio.online">
    <img src="https://play-lh.googleusercontent.com/AGG999=w240-h480-rw" alt="">
    <span class="DdYX5">Radio NL: Online Radio FM</span><span class="wMUdtb">Radio Apps</span>
  </a>
</div>
</c-wiz>
<script nonce="x">AF_initDataCallback({key: 'ds:4', data:[["nl.talpa.radio538"]]});</script>
</body></html>'''

PLAY_APP = '''<!doctype html><html><head>
<title>Radio 538 - Apps on Google Play</title>
<meta property="og:title" content="Radio 538 - Apps on Google Play">
<meta property="og:image" content="https://play-lh.googleusercontent.com/aB3_xYz-123/rest_ID=w600-h300-pc0xffffff-pd">
<meta itemprop="image" content="https://play-lh.googleusercontent.com/other=s180">
</head><body><h1><span>Radio 538</span></h1>
<div class="Vbfug"><a href="/store/apps/developer?id=Talpa+Network+B.V."><span>Talpa Network B.V.</span></a></div>
</body></html>'''

FAN_APP = PLAY_APP.replace('Radio 538 - Apps', '538 Radio App NL Gratis - Apps').replace(
    'aB3_xYz-123/rest_ID', 'FAN123').replace('Talpa+Network+B.V.', 'FanDev').replace('Talpa Network B.V.', 'FanDev')

ICON = 'https://play-lh.googleusercontent.com/aB3_xYz-123/rest_ID=s256'
MZ = 'https://is1-ssl.mzstatic.com/image/thumb/Purple/v4/x/AppIcon.png/256x256bb.png'
SITE = 'https://radio538.nl/t.png'


class Fetcher:
    """Nep-Fetcher: route = functie(url) → (content-type, bytes) | Exception | None (404)."""

    def __init__(self, route):
        self.route, self.stop, self.seen, self.calls = route, threading.Event(), [], 0

    def get(self, url, limit, accept='*/*', truncate=False):
        self.seen.append(url)
        r = self.route(url)
        if r is None:
            raise si.Blocked('404')
        if isinstance(r, Exception):
            raise r
        ctype, data = r
        return url, ctype, (data.encode() if isinstance(data, str) else data)[:limit]


def q(url):
    return dict(urllib.parse.parse_qsl(urllib.parse.urlparse(url).query))


# ---------------------------------------------------------------- tests

class Links(unittest.TestCase):
    def test_store_links(self):
        links = st.store_links(HOME)
        # banner-meta + link telt het zwaarst; andere apps daarna, max. 3
        self.assertEqual(links['ios'], ['373589722', '1234567890'])
        self.assertEqual(links['gp'][0], 'nl.talpa.radio538')
        self.assertIn('com.example.other', links['gp'])   # market://
        self.assertIn('tunein.player', links['gp'])       # JSON met \/
        self.assertLessEqual(len(links['gp']), 3)

    def test_store_links_variants(self):
        self.assertEqual(st.store_links('<a href="https://apps.apple.com/us/app/npo-radio-2/id1022404283">x</a>'),
                         {'ios': ['1022404283'], 'gp': []})
        self.assertEqual(st.store_links("<a href='market://details?id=nl.npo.radio2&hl=nl'>")['gp'], ['nl.npo.radio2'])
        self.assertEqual(st.store_links('<meta name="apple-itunes-app" content="app-id=nope">'), {'ios': [], 'gp': []})
        self.assertEqual(st.store_links(''), {'ios': [], 'gp': []})
        self.assertEqual(st.store_links(None), {'ios': [], 'gp': []})

    def test_find_icon_keeps_links(self):
        f = Fetcher(lambda u: {'https://radio538.nl': ('text/html', HOME),
                               'https://radio538.nl/t.png': ('image/png', png(180, 180))}.get(u))
        res = si.find_icon(f, 'https://radio538.nl')
        self.assertEqual(res['u'], SITE)
        self.assertEqual(res['ios'][0], '373589722')
        self.assertEqual(res['gp'][0], 'nl.talpa.radio538')
        self.assertEqual(res['sl'], 1)
        miss = si.find_icon(Fetcher(lambda u: ('text/html', '<p>niets</p>') if u == 'https://x.fm' else None),
                            'https://x.fm')
        self.assertEqual((miss['u'], miss['sl'], 'ios' in miss), ('', 1, False))


class Normalize(unittest.TestCase):
    def test_play_icon_url(self):
        for raw in ['https://play-lh.googleusercontent.com/aB3_xYz-123/rest_ID=w600-h300-pc0xffffff-pd',
                    'https://play-lh.googleusercontent.com/aB3_xYz-123/rest_ID=s64-rw',
                    'https://play-lh.googleusercontent.com/aB3_xYz-123/rest_ID',
                    '//play-lh.googleusercontent.com/aB3_xYz-123/rest_ID=w240-h480-rw',
                    'https://play-lh.googleusercontent.com/aB3_xYz-123/rest_ID=s256']:
            self.assertEqual(st.play_icon_url(raw), ICON, raw)
        self.assertEqual(st.play_icon_url('https://lh3.googleusercontent.com/abc=s64'), '')
        self.assertEqual(st.play_icon_url('https://evil.com/play-lh.googleusercontent.com/x'), '')
        self.assertEqual(st.play_icon_url(''), '')

    def test_strip_title(self):
        self.assertEqual(st.strip_play_title('Radio 538 - Apps on Google Play'), 'Radio 538')
        self.assertEqual(st.strip_play_title('NPO Radio 2 – Apps op Google Play'), 'NPO Radio 2')
        self.assertEqual(st.strip_play_title('Qmusic - Hits &amp; nieuws - Apps bei Google Play'), 'Qmusic - Hits & nieuws')


class Parse(unittest.TestCase):
    def test_play_search(self):
        res = st.parse_play_search(PLAY_SEARCH)
        self.assertEqual([r['pkg'] for r in res], ['nl.talpa.radio538', 'com.fanapps.radio538nl', 'nl.radio.online'])
        self.assertEqual(res[0]['titles'][0], 'Radio 538')
        self.assertEqual(res[0]['icon'], ICON)
        self.assertIn('538 Radio App NL Gratis', res[1]['titles'])
        self.assertNotIn('4,1', res[1]['titles'])
        self.assertEqual(res[2]['icon'], 'https://play-lh.googleusercontent.com/AGG999=s256')

    def test_play_search_fallback_json(self):
        html = ('<script>AF_initDataCallback({data:[[null,["\\/store\\/apps\\/details?id\\u003dnl.npo.radio1"]],'
                '"/store/apps/details?id=nl.npo.radio1"]});</script>')
        self.assertEqual(st.parse_play_search(html), [{'pkg': 'nl.npo.radio1', 'titles': [], 'icon': ''}])
        self.assertEqual(st.parse_play_search('<p>geen resultaten</p>'), [])

    def test_play_app(self):
        info = st.parse_play_app(PLAY_APP)
        self.assertEqual(info, {'icon': ICON, 'title': 'Radio 538', 'developer': 'Talpa Network B.V.'})
        bare = st.parse_play_app('<title>X - Apps on Google Play</title><img itemprop="image" '
                                 'src="https://play-lh.googleusercontent.com/II=s180">'
                                 '<a href="/store/apps/dev?id=123456"></a>')
        self.assertEqual(bare, {'icon': 'https://play-lh.googleusercontent.com/II=s256', 'title': 'X',
                                'developer': ''})


class Match(unittest.TestCase):
    def test_link_related(self):
        self.assertTrue(st.link_related('Qmusic Non-Stop', 'Qmusic', 'https://qmusic.nl/', 'NL'))
        self.assertTrue(st.link_related('NPO Klassiek', 'NPO Klassiek', 'https://www.nporadio4.nl', 'NL'))
        self.assertTrue(st.link_related('Radio 538', 'Radio 538', 'https://www.radio538.nl', 'NL'))
        self.assertTrue(st.link_related('538 Non Stop', 'Radio 538', 'https://www.radio538.nl', 'NL'))
        self.assertFalse(st.link_related('Radio 538', 'TuneIn Radio: Music & Sports', 'https://radio538.nl', 'NL'))
        self.assertFalse(st.link_related('Radio 538', 'Radio 538', 'https://radio538.nl', 'NL', genre='Games'))
        self.assertFalse(st.link_related('Jazz Radio', 'Jazz Drums', 'https://jazz.fm', 'FR'))

    def test_play_accept(self):
        self.assertTrue(st.play_accept('Radio 538', 'Radio 538', 'NL', 'https://radio538.nl', 'Talpa Network B.V.'))
        self.assertTrue(st.play_accept('NPO Radio 1', 'NPO Radio 1', 'NL', 'https://nporadio1.nl', 'NPO'))
        self.assertFalse(st.play_accept('Radio 538', '538 Radio App NL Gratis', 'NL', 'https://radio538.nl', 'FanDev'))
        # kernnaam in de titel telt alleen als de ontwikkelaar bij de site hoort
        self.assertFalse(st.play_accept('Qmusic', 'Qmusic Radio Nederland Live', 'NL', 'https://qmusic.nl', 'Fan Apps'))
        self.assertTrue(st.play_accept('Qmusic', 'Qmusic Radio Nederland Live', 'NL', 'https://qmusic.nl', 'Qmusic'))
        self.assertFalse(st.play_accept('Radio 538', 'Radio 538', '', 'https://radio538.nl', 'X'))  # zonder land
        self.assertFalse(st.play_accept('Radio 1', 'Radio 1', 'NO', 'https://radio1.no', 'Random Dev'))


@unittest.skipIf(si.Image is None, 'Pillow ontbreekt')
class Network(unittest.TestCase):
    def route(self, app_page=PLAY_APP):
        def r(url):
            p = urllib.parse.urlparse(url)
            if p.path == '/store/search':
                return ('text/html', PLAY_SEARCH)
            if p.path == '/store/apps/details':
                return ('text/html', app_page if q(url)['id'] == 'nl.talpa.radio538' else FAN_APP)
            if url in (ICON, 'https://play-lh.googleusercontent.com/FAN123=s256'):
                return ('image/png', png(256, 256))
            return None
        return r

    def test_search_play_hit(self):
        f = Fetcher(self.route())
        verify = lambda u: si.verify_store_image(f, u)
        res = st.search_play(f, st.Spacer(0), 'Radio 538', 'NL', 'https://www.radio538.nl', verify)
        self.assertEqual(res, {'u': ICON, 'p': 'nl.talpa.radio538', 't': 'Radio 538', 's': 'Talpa Network B.V.'})
        sq = q(f.seen[0])
        self.assertEqual((sq['q'], sq['c'], sq['hl'], sq['gl']), ('Radio 538', 'apps', 'nl', 'NL'))
        app_q = q(f.seen[1])
        self.assertEqual((app_q['hl'], app_q['gl']), ('en', 'US'))

    def test_search_play_rejects_fan_app(self):
        # alleen de fan-app op de app-pagina: geen icoon
        f = Fetcher(self.route(app_page=FAN_APP))
        res = st.search_play(f, st.Spacer(0), 'Radio 538', 'NL', 'https://www.radio538.nl',
                             lambda u: si.verify_store_image(f, u))
        self.assertEqual(res['u'], '')

    def test_search_play_busy_raises(self):
        err = urllib.error.HTTPError('https://play.google.com/x', 429, 'Too Many', {}, None)
        f = Fetcher(lambda u: err)
        with self.assertRaises(urllib.error.HTTPError):
            st.search_play(f, st.Spacer(0), 'Radio 538', 'NL', '', lambda u: True)

    def test_lookup_ios(self):
        art = 'https://is1-ssl.mzstatic.com/image/thumb/Purple/v4/x/AppIcon.png/512x512bb.jpg'
        body = json.dumps({'resultCount': 1, 'results': [{'trackId': 373589722, 'trackName': 'Radio 538',
                                                          'primaryGenreName': 'Music', 'sellerName': 'Talpa',
                                                          'artworkUrl512': art}]})

        def r(url):
            if url.startswith(st.ITUNES_LOOKUP):
                return ('application/json', body if q(url).get('country') == 'nl' else '{"results":[]}')
            return ('image/png', png(256, 256)) if url == MZ else None
        f = Fetcher(r)
        e = st.lookup_ios(f, st.Spacer(0), '373589722', 'NL', lambda u: si.verify_store_image(f, u))
        self.assertEqual((e['u'], e['t'], e['g']), (MZ, 'Radio 538', 'Music'))
        self.assertEqual(q(f.seen[0]), {'id': '373589722', 'country': 'nl'})
        miss = st.lookup_ios(Fetcher(lambda u: ('application/json', '{"results":[]}')), st.Spacer(0), '1', 'DE',
                             lambda u: True)
        self.assertEqual(miss['u'], '')

    def test_lookup_play_pkg(self):
        f = Fetcher(self.route())
        e = st.lookup_play_pkg(f, st.Spacer(0), 'nl.talpa.radio538', 'NL', lambda u: si.verify_store_image(f, u))
        self.assertEqual((e['u'], e['t'], e['s']), (ICON, 'Radio 538', 'Talpa Network B.V.'))

    def test_verify_store_image(self):
        f = Fetcher(lambda u: ('image/png', png(100, 100)) if 'small' in u else ('image/png', png(512, 512)))
        self.assertTrue(si.verify_store_image(f, ICON))
        self.assertFalse(si.verify_store_image(f, 'https://play-lh.googleusercontent.com/small=s256'))
        self.assertFalse(si.verify_store_image(f, 'http://play-lh.googleusercontent.com/x=s256'))


def groups():
    return {
        ('NL', 'radio538'): {'name': 'Radio 538', 'homepage': 'https://www.radio538.nl', 'uuids': {'u538'}, 'clicks': 9},
        ('NL', '538nonstop'): {'name': '538 Non Stop', 'homepage': 'https://www.radio538.nl', 'uuids': {'u53n'},
                               'clicks': 8},
        ('NL', 'qmusic'): {'name': 'Qmusic', 'homepage': 'https://qmusic.nl', 'uuids': {'uq'}, 'clicks': 7},
        ('NL', 'nporadio1'): {'name': 'NPO Radio 1', 'homepage': 'https://www.nporadio1.nl', 'uuids': {'un1'},
                              'clicks': 6},
        ('NL', 'skyradio'): {'name': 'Sky Radio', 'homepage': 'https://skyradio.nl', 'uuids': {'us'}, 'clicks': 5},
        ('NL', 'radio1'): {'name': 'Radio 1', 'homepage': '', 'uuids': {'ur1'}, 'clicks': 4},
    }


class Tables(unittest.TestCase):
    def test_build_tables_priority(self):
        g = groups()
        hosts = si.site_groups(g)
        items = {
            'radio538.nl': {'u': SITE, 'ios': ['373589722', '999'], 'gp': ['nl.talpa.radio538'], 'sl': 1},
            'qmusic.nl': {'u': 'https://qmusic.nl/t.png', 'gp': ['tunein.player', 'be.qmusic'], 'sl': 1},
            'nporadio1.nl': {'u': 'https://nporadio1.nl/t.png', 'sl': 1},
            'skyradio.nl': {'u': 'https://skyradio.nl/t.png', 'ios': ['555'], 'sl': 1},
        }
        pc = {
            'ios:999': {'u': 'https://is1-ssl.mzstatic.com/other/256x256bb.png', 't': 'Shopping Deals', 'g': 'Shopping'},
            'ios:373589722': {'u': MZ, 't': 'Radio 538', 'g': 'Music'},
            'gp:nl.talpa.radio538': {'u': ICON, 't': 'Radio 538'},
            'gp:tunein.player': {'u': 'https://play-lh.googleusercontent.com/TUNE=s256', 't': 'TuneIn Radio'},
            'gp:be.qmusic': {'u': 'https://play-lh.googleusercontent.com/QM=s256', 't': 'Qmusic'},
            'q:NL|nporadio1': {'u': 'https://play-lh.googleusercontent.com/N1=s256', 'p': 'nl.npo.radio1'},
            'ios:555': {'u': '', 'r': 'not-found'},
        }
        f = si.build_tables(g, items, hosts, pc)['NL']
        self.assertEqual(f['n']['radio538'], MZ)                    # App Store-link (exact id) voor alles
        self.assertEqual(f['n']['538nonstop'], MZ)                  # zelfde site, zelfde app
        self.assertEqual(f['n']['qmusic'], 'https://play-lh.googleusercontent.com/QM=s256')  # TuneIn overgeslagen
        self.assertEqual(f['n']['nporadio1'], 'https://play-lh.googleusercontent.com/N1=s256')  # Play-zoeken
        self.assertEqual(f['n']['skyradio'], 'https://skyradio.nl/t.png')  # geen store: website
        self.assertEqual(f['u']['uq'], 'https://play-lh.googleusercontent.com/QM=s256')
        self.assertNotIn('radio1', f['n'])

    def test_play_candidates(self):
        g = groups()
        hosts = si.site_groups(g)
        items = {'radio538.nl': {'u': SITE, 'gp': ['nl.talpa.radio538'], 'sl': 1}}
        pc = {'gp:nl.talpa.radio538': {'u': ICON, 't': 'Radio 538'},
              f'q:NL|skyradio': {'u': '', 'd': date.today().isoformat()}}
        existing = {'NL': {'u': {'uq': MZ}, 'n': {}}}
        cands = [k for _, k, _ in si.play_candidates(g, hosts, items, pc, existing, per_country=100, world=1000)]
        # 538: Play via site; Qmusic: al App Store; Sky Radio: verse misser; Radio 1: te algemeen
        self.assertEqual(cands, ['nporadio1'])
        few = si.play_candidates(g, hosts, {}, {}, {}, per_country=2, world=1)
        self.assertEqual([k for _, k, _ in few], ['radio538', '538nonstop'])

    def test_freshness(self):
        today = date(2026, 10, 18)
        self.assertTrue(st.is_fresh({'u': '', 'd': '2026-10-01'}, today))
        self.assertFalse(st.is_fresh({'u': '', 'd': '2026-09-10'}, today))
        self.assertTrue(st.is_fresh({'u': 'x', 'd': '2026-07-01'}, today))
        self.assertFalse(st.is_fresh({'u': 'x', 'd': '2026-06-01'}, today))
        self.assertFalse(st.is_fresh(None, today))


PLAY_OLD = 'https://play-lh.googleusercontent.com/OLD=s256'
SITE_OLD = 'https://qmusic.nl/old.png'


class Merge(unittest.TestCase):
    def test_rank(self):
        self.assertEqual([mt.url_rank(u) for u in (MZ, ICON, SITE, '', None)], [3, 2, 1, 0, 0])
        self.assertEqual(mt.url_rank('https://play-lh.googleusercontent.com.evil.nl/x'), 1)

    def test_priority_with_play(self):
        existing = {'NL': {'u': {'a': SITE_OLD, 'b': PLAY_OLD, 'c': MZ, 'd': PLAY_OLD, 'e': SITE_OLD}, 'n': {}}}
        site = {'NL': {'u': {'a': ICON, 'b': SITE, 'c': ICON, 'd': ICON, 'e': MZ, 'f': SITE}, 'n': {}}}
        appstore = {'NL': {'u': {'d': MZ}, 'n': {}}}
        t, src = mt.merge(existing, appstore, site)
        self.assertEqual(t['NL']['u'], {'a': ICON,   # Play vervangt een oud website-icoon
                                        'b': PLAY_OLD,  # website vervangt nooit Play
                                        'c': MZ,        # Play vervangt nooit App Store
                                        'd': MZ,        # App Store-zoekjob wint
                                        'e': MZ,        # exacte App Store-link uit de site-job
                                        'f': SITE})
        self.assertEqual(src['NL']['u'], {'a': 'play', 'b': 'play-kept', 'c': 'appstore-kept', 'd': 'appstore',
                                          'e': 'appstore-link', 'f': 'site'})

    def test_new_play_replaces_old_play_and_cli(self):
        t, src = mt.merge({'NL': {'u': {}, 'n': {'x': PLAY_OLD}}}, None, {'NL': {'u': {}, 'n': {'x': ICON}}})
        self.assertEqual((t['NL']['n']['x'], src['NL']['n']['x']), (ICON, 'play'))
        with tempfile.TemporaryDirectory() as d:
            ex, sd, out = (os.path.join(d, x) for x in ('ex', 'site', 'out'))
            mt.write_dir({'NL': {'u': {'k': SITE_OLD, 'z': MZ}, 'n': {}}}, ex)
            mt.write_dir({'NL': {'u': {'k': ICON, 'z': ICON}, 'n': {}}}, sd)
            srcf = os.path.join(d, 'sources.json')
            mt.main(['tables', '--existing', ex, '--site', sd, '--out', out, '--sources', srcf])
            self.assertEqual(mt.load_dir(out)['NL']['u'], {'k': ICON, 'z': MZ})
            with open(srcf) as fh:
                self.assertEqual(json.load(fh)['sources']['NL']['u'], {'k': 'play', 'z': 'appstore-kept'})

    def test_play_cache_merges_like_other_caches(self):
        a = {'q:NL|x': {'u': '', 'd': '2026-09-01'}, 'gp:p': {'u': ICON, 'd': '2026-10-01', 't': 'P'}}
        b = {'q:NL|x': {'u': ICON, 'd': '2026-10-10', 'p': 'pkg'}, 'gp:p': {'u': '', 'd': '2026-09-01'}}
        m = mt.merge_caches(a, b)
        self.assertEqual((m['q:NL|x']['u'], m['gp:p']['u']), (ICON, ICON))


if __name__ == '__main__':
    unittest.main(verbosity=1)

#!/usr/bin/env python3
"""Offline tests voor de app-icoon-match van tools/make_station_icons.py (geen netwerk; vaste iTunes-antwoorden).

    python3 tools/test_station_icons.py
"""
import os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_station_icons as m  # noqa: E402

ART = 'https://is1-ssl.mzstatic.com/image/thumb/Purple/v4/ab/cd/ef/AppIcon-0-1x_U007emarketing.png/512x512bb.jpg'


def app(track, genre='Music', seller='Some Media BV', url='', art=ART):
    return {'trackName': track, 'primaryGenreName': genre, 'sellerName': seller, 'sellerUrl': url, 'artworkUrl512': art}


class Normalize(unittest.TestCase):
    # zelfde vectoren als Apple IconMap.key, Android IconMap.key en web T.iconKey
    def test_norm_key(self):
        self.assertEqual(m.norm_key('NPO Radio 2'), 'nporadio2')
        self.assertEqual(m.norm_key('Radio Ñandú – 100.7 FM!'), 'radionandu1007fm')
        self.assertEqual(m.norm_key('  Ö3 Hitradio '), 'o3hitradio')
        self.assertEqual(m.norm_key('Русское Радио'), 'русскоерадио')
        self.assertEqual(m.norm_key('ラジオ 1'), 'ラシオ1')  # NFKD splitst de dakuten af
        self.assertEqual(m.norm_key(''), '')

    def test_core(self):
        self.assertEqual(m.core('Radio 538'), '538')
        self.assertEqual(m.core('Sky Radio 101.2 FM'), 'sky')
        self.assertEqual(m.core('BBC Radio 1'), 'bbc1')
        self.assertEqual(m.core('Radio Paradise (Main Mix)'), 'paradisemainmix')

    def test_search_term(self):
        self.assertEqual(m.search_term('Radio 538 - Non Stop Hits'), 'Radio 538')
        self.assertEqual(m.search_term('Sky Radio 101.2 FM'), 'Sky Radio')
        self.assertEqual(m.search_term('Qmusic'), 'Qmusic')

    def test_icon_url(self):
        self.assertTrue(m.icon_url(ART).endswith('/256x256bb.png'))
        self.assertEqual(m.icon_url('https://example.com/logo.svg'), '')
        self.assertEqual(m.icon_url('http://x/512x512bb.jpg'), '')


class Match(unittest.TestCase):
    def test_exact_name(self):
        res = [app('Qmusic Nederland'), app('Qmusic', seller='DPG Media')]
        self.assertEqual(m.match_app('Qmusic', res, 'NL', 'NL')['trackName'], 'Qmusic')

    def test_prefers_exact_over_contains(self):
        res = [app('Sky Radio Hits & More'), app('Sky Radio')]
        self.assertEqual(m.match_app('Sky Radio', res, 'NL', 'NL')['trackName'], 'Sky Radio')

    def test_contains_core(self):
        res = [app('Radio Paradise - Commercial free')]
        self.assertIsNotNone(m.match_app('Radio Paradise', res, 'US', 'US'))

    def test_tagline_in_app_name(self):
        res = [app('NPO Radio 2 - Muziek & nieuws', seller='NPO')]
        self.assertIsNotNone(m.match_app('NPO Radio 2', res, 'NL', 'NL'))

    def test_rejects_games_and_tools(self):
        self.assertIsNone(m.match_app('Qmusic', [app('Qmusic', genre='Games')], 'NL', 'NL'))
        self.assertIsNone(m.match_app('Energy Zürich', [app('Energy Drink Tracker', genre='Health & Fitness')], 'CH', 'CH'))

    def test_rejects_unrelated(self):
        res = [app('TuneIn Radio: Music & Sports'), app('Radio FM: Live Radio Stations')]
        self.assertIsNone(m.match_app('Radio Veronica', res, 'NL', 'NL'))
        self.assertIsNone(m.match_app('Kiss FM Ukraine', [app('KISS FM UK')], 'UA', 'UA'))

    def test_short_app_name_not_inside_long_station(self):
        self.assertIsNone(m.match_app('Antenne Vorarlberg', [app('Antenne Bayern')], 'AT', 'AT'))

    def test_generic_names(self):
        # "Radio 1" of "Jazz Radio": alleen exact, eigen store, en de uitgever hoort bij de zender
        self.assertIsNone(m.match_app('Radio 1', [app('Radio 1')], 'US', 'NO'))
        self.assertIsNone(m.match_app('Radio 1', [app('Radio 1', seller='Random Dev')], 'NO', 'NO', 'https://radio1.no'))
        hit = m.match_app('Radio 1', [app('Radio 1', seller='Radio 1 Norge AS', url='https://www.radio1.no')],
                          'NO', 'NO', 'https://radio1.no/')
        self.assertIsNotNone(hit)
        self.assertIsNotNone(m.match_app('Jazz Radio', [app('Jazz Radio', seller='JAZZ RADIO')], 'FR', 'FR',
                                         'https://www.jazzradio.fr'))
        self.assertIsNone(m.match_app('Jazz Radio', [app('Jazz Radio Smooth', seller='X')], 'FR', 'FR'))

    def test_digit_names(self):
        self.assertIsNotNone(m.match_app('Radio 538', [app('Radio 538', seller='Talpa Network')], 'NL', 'NL'))
        self.assertIsNone(m.match_app('Radio 538', [app('Radio 538', seller='Talpa Network')], 'US', 'NL'))
        self.assertIsNone(m.match_app('Radio 10', [app('Radio 10', seller='Talpa Network')], 'NL', 'NL'))

    def test_token_overlap(self):
        self.assertIsNotNone(m.match_app('Bayern 3', [app('BAYERN 3', seller='Bayerischer Rundfunk')], 'DE', 'DE'))
        self.assertIsNotNone(m.match_app('Antenne Bayern', [app('ANTENNE BAYERN Radio')], 'DE', 'DE'))

    def test_needs_artwork(self):
        self.assertIsNone(m.match_app('Qmusic', [app('Qmusic', art='')], 'NL', 'NL'))


class Output(unittest.TestCase):
    def test_group_and_write(self):
        stations = [
            {'name': 'Qmusic', 'stationuuid': 'u1', 'countrycode': 'NL', 'clickcount': 50},
            {'name': 'QMUSIC ', 'stationuuid': 'u2', 'countrycode': 'nl', 'clickcount': 10},
            {'name': 'World FM', 'stationuuid': 'u3', 'countrycode': '', 'clickcount': 5},
            {'name': 'Nope', 'stationuuid': 'u4', 'countrycode': 'NL', 'clickcount': 1},
        ]
        groups = m.group(stations)
        self.assertEqual(list(groups)[0], ('NL', 'qmusic'))
        self.assertEqual(groups[('NL', 'qmusic')]['uuids'], {'u1', 'u2'})
        cache = {'NL|qmusic': {'u': 'https://a/256x256bb.png', 'd': '2026-10-01'},
                 '|worldfm': {'u': 'https://b/256x256bb.png', 'd': '2026-10-01'},
                 'NL|nope': {'u': '', 'd': '2026-10-01'}}
        with tempfile.TemporaryDirectory() as d:
            files = m.write_output(groups, cache, d)
            self.assertEqual(sorted(os.listdir(d)), ['NL.json', '_world.json'])
            self.assertEqual(files['NL']['u'], {'u1': 'https://a/256x256bb.png', 'u2': 'https://a/256x256bb.png'})
            self.assertEqual(files['NL']['n'], {'qmusic': 'https://a/256x256bb.png'})
            self.assertEqual(files['_world']['u'], {'u3': 'https://b/256x256bb.png'})

    def test_freshness(self):
        from datetime import date
        today = date(2026, 10, 17)
        self.assertTrue(m.is_fresh({'u': '', 'd': '2026-08-01'}, today))
        self.assertFalse(m.is_fresh({'u': '', 'd': '2026-07-01'}, today))
        self.assertTrue(m.is_fresh({'u': 'x', 'd': '2026-05-01'}, today))
        self.assertFalse(m.is_fresh({}, today))


if __name__ == '__main__':
    unittest.main(verbosity=1)

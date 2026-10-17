#!/usr/bin/env python3
"""SEO-rapport voor tunr.online met DataForSEO (workflow *SEO*).

Haalt met de DataForSEO API (secrets DATAFORSEO_LOGIN / DATAFORSEO_PASSWORD) op:
  1. zoekvolume, concurrentie en CPC van kandidaat-zoekwoorden (NL, BE, GB, US);
  2. zoekwoordsuggesties rond de kernwoorden ("radio app", "online radio luisteren", ...);
  3. wie er nu in Google bovenaan staat voor de belangrijkste woorden (SERP top 10);
  4. waar tunr.online zelf al op rankt;
  5. een on-page-controle van de pagina's (titel, description, koppen, laadtijd, fouten).
Schrijft seo/report.md (leesbaar) en seo/report.json (ruw) in de map die als argument wordt gegeven.
Kosten per run zijn klein (enkele tientallen API-taken); zie de limieten hieronder.
"""
import base64, json, os, sys, time, urllib.request, urllib.error

API = 'https://api.dataforseo.com/v3'
LOGIN = os.environ.get('DATAFORSEO_LOGIN', '').strip()
PASSWORD = os.environ.get('DATAFORSEO_PASSWORD', '').strip()
OUT = sys.argv[1] if len(sys.argv) > 1 else 'seo-out'
SITE = 'tunr.online'
PAGES = ['https://tunr.online/', 'https://tunr.online/?lang=en', 'https://tunr.online/changelog/', 'https://tunr.online/privacy/']

# locatiecodes van DataForSEO (Google Ads)
MARKETS = [
    ('NL', 2528, 'nl', [
        'radio app', 'online radio', 'online radio luisteren', 'radio luisteren', 'radio luisteren online gratis',
        'radio app gratis', 'internetradio', 'internet radio app', 'wereldradio', 'buitenlandse radio luisteren',
        'radiozenders', 'radio zenders wereldwijd', 'podcast app', 'podcasts luisteren', 'gratis podcast app',
        'radio apple tv', 'radio carplay', 'radio app iphone', 'radio app android', 'radio android auto',
        'radio mac app', 'tunein alternatief', 'tunein', 'radio garden', 'radio wereldkaart', 'radio browser'
    ]),
    ('BE', 2056, 'nl', ['radio app', 'online radio luisteren', 'radio luisteren', 'podcast app', 'internetradio']),
    ('GB', 2826, 'en', [
        'radio app', 'internet radio app', 'world radio', 'listen to radio online', 'free radio app',
        'radio stations from around the world', 'podcast app', 'radio app apple tv', 'carplay radio app',
        'tunein alternative', 'radio garden', 'world radio map'
    ]),
    ('US', 2840, 'en', [
        'radio app', 'internet radio app', 'world radio', 'listen to radio online', 'free radio app',
        'radio stations from around the world', 'podcast app', 'apple tv radio app', 'carplay radio app',
        'tunein alternative', 'radio garden alternative', 'global radio stations'
    ]),
]
SEEDS = [('NL', 2528, 'nl', ['radio app', 'online radio luisteren', 'podcast app']),
         ('US', 2840, 'en', ['internet radio app', 'world radio'])]
SERP = [('NL', 2528, 'nl', ['radio app', 'online radio luisteren', 'internetradio', 'radio wereldkaart']),
        ('US', 2840, 'en', ['internet radio app', 'world radio app'])]


def call(path, payload):
    auth = base64.b64encode(f'{LOGIN}:{PASSWORD}'.encode()).decode()
    req = urllib.request.Request(API + path, data=json.dumps(payload).encode(), method='POST',
                                 headers={'Authorization': 'Basic ' + auth, 'Content-Type': 'application/json'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                data = json.loads(r.read())
            if data.get('status_code') != 20000:
                raise RuntimeError(f"{path}: {data.get('status_code')} {data.get('status_message')}")
            return data
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt == 2:
                raise
            time.sleep(5 * (attempt + 1))


def results(data):
    out = []
    for t in data.get('tasks') or []:
        if t.get('status_code') != 20000:
            print('  taak mislukt:', t.get('status_code'), t.get('status_message'))
            continue
        out.extend(t.get('result') or [])
    return out


def main():
    if not LOGIN or not PASSWORD:
        sys.exit('DATAFORSEO_LOGIN / DATAFORSEO_PASSWORD ontbreken')
    os.makedirs(OUT, exist_ok=True)
    raw, md = {}, []
    md.append(f'# SEO-rapport {SITE}\n\n_{time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())}, bron: DataForSEO_\n')

    # 1. zoekvolume
    md.append('## 1. Zoekvolume kandidaat-zoekwoorden\n')
    raw['volume'] = {}
    for name, loc, lang, kws in MARKETS:
        try:
            res = results(call('/keywords_data/google_ads/search_volume/live',
                               [{'keywords': kws, 'location_code': loc, 'language_code': lang}]))
        except Exception as e:
            md.append(f'- {name}: fout ({e})\n'); continue
        raw['volume'][name] = res
        rows = sorted(res, key=lambda r: -(r.get('search_volume') or 0))
        md.append(f'### {name}\n\n| zoekwoord | volume/mnd | concurrentie | CPC € |\n|---|---:|---|---:|')
        for r in rows:
            md.append(f"| {r.get('keyword')} | {r.get('search_volume') or 0} | {r.get('competition') or '-'} | {r.get('cpc') or '-'} |")
        md.append('')

    # 2. suggesties
    md.append('## 2. Zoekwoordsuggesties\n')
    raw['suggestions'] = {}
    for name, loc, lang, seeds in SEEDS:
        for seed in seeds:
            try:
                res = results(call('/dataforseo_labs/google/keyword_suggestions/live',
                                   [{'keyword': seed, 'location_code': loc, 'language_code': lang, 'limit': 30,
                                     'order_by': ['keyword_info.search_volume,desc']}]))
            except Exception as e:
                md.append(f'- {name} "{seed}": fout ({e})\n'); continue
            items = (res[0].get('items') if res else None) or []
            raw['suggestions'][f'{name}:{seed}'] = items
            md.append(f'### {name}: "{seed}"\n')
            for it in items[:30]:
                ki = it.get('keyword_info') or {}
                md.append(f"- {it.get('keyword')} ({ki.get('search_volume') or 0}/mnd)")
            md.append('')

    # 3. SERP
    md.append('## 3. Google top 10 nu\n')
    raw['serp'] = {}
    for name, loc, lang, kws in SERP:
        for kw in kws:
            try:
                res = results(call('/serp/google/organic/live/regular',
                                   [{'keyword': kw, 'location_code': loc, 'language_code': lang, 'depth': 20}]))
            except Exception as e:
                md.append(f'- {name} "{kw}": fout ({e})\n'); continue
            items = [i for i in ((res[0].get('items') if res else None) or []) if i.get('type') == 'organic']
            raw['serp'][f'{name}:{kw}'] = items
            pos = next((i.get('rank_absolute') for i in items if SITE in (i.get('domain') or '')), None)
            md.append(f'### {name}: "{kw}" — tunr.online: {pos or "niet in top 20"}\n')
            for i in items[:10]:
                md.append(f"{i.get('rank_absolute')}. {i.get('domain')} — {i.get('title')}")
            md.append('')

    # 4. eigen rankings
    md.append('## 4. Waar tunr.online al op rankt\n')
    raw['ranked'] = {}
    for name, loc, lang in [('NL', 2528, 'nl'), ('US', 2840, 'en')]:
        try:
            res = results(call('/dataforseo_labs/google/ranked_keywords/live',
                               [{'target': SITE, 'location_code': loc, 'language_code': lang, 'limit': 50}]))
            items = (res[0].get('items') if res else None) or []
        except Exception as e:
            md.append(f'- {name}: fout ({e})\n'); continue
        raw['ranked'][name] = items
        md.append(f'### {name}: {len(items)} zoekwoorden\n')
        for it in items[:50]:
            kd = it.get('keyword_data') or {}
            se = ((it.get('ranked_serp_element') or {}).get('serp_item') or {})
            md.append(f"- {kd.get('keyword')}: positie {se.get('rank_absolute')} ({(kd.get('keyword_info') or {}).get('search_volume') or 0}/mnd)")
        md.append('')

    # 5. on-page
    md.append('## 5. On-page-controle\n')
    raw['onpage'] = {}
    for url in PAGES:
        try:
            res = results(call('/on_page/instant_pages', [{'url': url, 'enable_javascript': True, 'load_resources': True}]))
            page = ((res[0].get('items') if res else None) or [{}])[0]
        except Exception as e:
            md.append(f'- {url}: fout ({e})\n'); continue
        raw['onpage'][url] = page
        meta = page.get('meta') or {}
        checks = page.get('checks') or {}
        bad = sorted(k for k, v in checks.items() if v is True and k.startswith(('no_', 'is_', 'has_', 'title_', 'large_', 'high_', 'low_', 'duplicate_', 'deprecated', 'frame', 'lorem', 'seo_friendly')) and k not in ('is_https', 'is_www', 'seo_friendly_url', 'has_html_doctype', 'is_redirect') )
        md.append(f"### {url}\n\n- status: {page.get('status_code')}, onpage-score: {page.get('onpage_score')}\n"
                  f"- titel ({meta.get('title_length')} tekens): {meta.get('title')}\n"
                  f"- description ({meta.get('description_length')} tekens): {meta.get('description')}\n"
                  f"- h1: {(meta.get('htags') or {}).get('h1')}\n"
                  f"- woorden: {(meta.get('content') or {}).get('plain_text_word_count')}, interne links: {meta.get('internal_links_count')}, externe: {meta.get('external_links_count')}\n"
                  f"- laadtijd (ms): {(page.get('page_timing') or {}).get('duration_time')}, grootte: {page.get('size')}\n"
                  f"- aandachtspunten: {', '.join(bad) or 'geen'}\n")

    with open(os.path.join(OUT, 'report.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(md) + '\n')
    with open(os.path.join(OUT, 'report.json'), 'w', encoding='utf-8') as f:
        json.dump(raw, f, ensure_ascii=False, indent=1)
    print('rapport geschreven:', OUT)


if __name__ == '__main__':
    main()

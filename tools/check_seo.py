#!/usr/bin/env python3
"""Snelle SEO-controle van de statische site (en de gegenereerde /radio/-pagina's).

Per HTML-bestand: titel (NL en de andere taal via tunr-title-*) 30–60 tekens, description (beide talen) 110–160
tekens (melding buiten 140–158), geldige JSON-LD, elke <img> met alt. Pagina's met noindex: alleen JSON-LD en alt.

Gebruik: python3 tools/check_seo.py [map]   (standaard website/; exit 1 bij fouten)
"""
import html, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def check(path, rel):
    s = open(path, encoding='utf-8').read()
    errs, warns = [], []
    noindex = bool(re.search(r'<meta name="robots" content="[^"]*noindex', s))
    titles = re.findall(r'<title>(.*?)</title>', s, re.S) + re.findall(r'<meta name="tunr-title-(?:en|nl)" content="([^"]*)"', s)
    descs = []
    m = re.search(r'<meta name="description" content="([^"]*)"([^>]*)>', s)
    if m:
        descs.append(m.group(1))
        descs += re.findall(r'data-(?:en|nl)="([^"]*)"', m.group(2))
    if not noindex:
        if not titles:
            errs.append('geen <title>')
        for t in titles:
            n = len(html.unescape(t))
            if not 30 <= n <= 60:
                errs.append(f'titel {n} tekens: {html.unescape(t)!r}')
        if not descs:
            errs.append('geen description')
        for d in descs:
            n = len(html.unescape(d))
            if not 110 <= n <= 160:
                errs.append(f'description {n} tekens: {html.unescape(d)[:70]!r}…')
            elif not 140 <= n <= 158:
                warns.append(f'description {n} tekens')
    for blob in re.findall(r'<script type="application/ld\+json"[^>]*>(.*?)</script>', s, re.S):
        try:
            json.loads(blob)
        except Exception as e:
            errs.append(f'JSON-LD ongeldig: {e}')
    for img in re.findall(r'<img\b[^>]*>', s):
        if not re.search(r'\salt="', img):
            errs.append('img zonder alt: ' + img[:80])
    return errs, warns


def main():
    base = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'website'))
    n = bad = 0
    for dp, _, files in os.walk(base):
        for f in files:
            if not f.endswith('.html'):
                continue
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, base)
            errs, warns = check(p, rel)
            n += 1
            if errs:
                bad += 1
                print(f'FOUT {rel}:\n  ' + '\n  '.join(errs))
            elif warns and '/radio/' not in '/' + rel:
                print(f'let op {rel}: ' + '; '.join(warns))
    print(f'{n} pagina\'s gecontroleerd, {bad} met fouten')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())

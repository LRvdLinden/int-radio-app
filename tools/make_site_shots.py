#!/usr/bin/env python3
"""Schermafbeeldingen voor tunr.online ("Zo ziet Tunr eruit") uit echte opnames van de Apple-app.

    python3 tools/make_site_shots.py --raw <map>

<map>/<taal>/iphone63-<scène>.png en <map>/<taal>/mac-discover.png (workflow *App Store media* met target = site:
de app in de simulator / op de Mac met `-TunrScreenshot <scène> -TunrScreenshotLang <taal>`).
Uitvoer per taal (nl, en) in website/assets/img/<taal>/: ios_<scène>.jpg + .webp (780 px breed) en
mac_discover.jpg + .webp (1400 px breed). Scènes: zie SCENES (gelijk aan de figuren in website/index.html).
"""
import argparse, pathlib, sys
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCENES = ["discover", "browse", "player", "map", "podcasts", "library"]
LANGS = ["nl", "en"]


def save(img, base, width):
    img = img.convert("RGB")
    h = round(img.height * width / img.width)
    img = img.resize((width, h), Image.LANCZOS)
    base.parent.mkdir(parents=True, exist_ok=True)
    img.save(base.with_suffix(".jpg"), quality=86, optimize=True, progressive=True)
    img.save(base.with_suffix(".webp"), quality=84, method=6)
    return img.size


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", type=pathlib.Path, required=True)
    a = ap.parse_args()
    missing = 0
    for lang in LANGS:
        out = ROOT / "website/assets/img" / lang
        for s in SCENES:
            p = a.raw / lang / f"iphone63-{s}.png"
            if not p.exists():
                print(f"waarschuwing: {p} ontbreekt (oude afbeelding blijft)", file=sys.stderr); missing += 1; continue
            print(f"{lang}/ios_{s}", *save(Image.open(p), out / f"ios_{s}", 780))
        p = a.raw / lang / "mac-discover.png"
        if p.exists():
            print(f"{lang}/mac_discover", *save(Image.open(p), out / "mac_discover", 1400))
        else:
            print(f"waarschuwing: {p} ontbreekt", file=sys.stderr); missing += 1
    print(f"klaar ({missing} ontbrekend)")


if __name__ == "__main__":
    main()

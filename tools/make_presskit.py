#!/usr/bin/env python3
"""Maakt de presskit van Tunr: Tunr-PressKit.zip + presskit.json (download via de footer van tunr.online).

    python3 tools/make_presskit.py --appstore <map appstore/ uit tunr-beheer> [--out website/presskit]
                                   [--previous <oude presskit.json>]

Bronnen:
- de App Store-afbeeldingen uit de repo tunr-beheer (map `appstore/`, gemaakt door de workflow *App Store media*);
  de workflow *Website* haalt die map op met een ondiepe, sparse clone;
- merkbestanden uit deze repo (docs/brand, website/assets/img; zie tools/make_icons.py).

Indeling van de zip (map `Tunr Press Kit/`): README.txt, Brand/, Apple/<apparaat>/, Promo/. Alles staat in LAYOUT
hieronder (bron-glob → map in de zip, per onderdeel): een nieuw platform (bv. Android/) = een extra blok in LAYOUT
plus de naam in PLATFORMS.

presskit.json: {"version": "<YYYY.MM.DD>-<6 tekens sha256 van de inhoud>", "date", "size", "files", "platforms"}.
De zip is reproduceerbaar (vaste tijdstempels, vaste volgorde). De versie verandert alleen als de inhoud verandert:
met --previous (de presskit.json die nu online staat) blijven versie en datum gelijk zolang de inhoudshash gelijk is.
"""
import argparse, datetime as dt, glob, hashlib, json, os, pathlib, sys, zipfile

root = pathlib.Path(__file__).resolve().parent.parent

ZIP_NAME = "Tunr-PressKit.zip"
TOP = "Tunr Press Kit"
ZIP_TIME = (2026, 1, 1, 0, 0, 0)       # vaste tijdstempel in de zip (reproduceerbaar)
SITE = "https://tunr.online"
CONTACT = "info@tunr.online"
COLORS = [("Background", "#0A0A0C"), ("Accent", "#FF5A1F"), ("Accent 2", "#FFB020")]

# (bron, glob, map in de zip, nieuwe naam of None). bron = "appstore" (map uit tunr-beheer) of "repo" (deze repo).
LAYOUT = {
    "Brand": [
        ("appstore", "tunr/en/icon-1024.png", "Brand", "Tunr-app-icon-1024.png"),
        ("repo", "website/assets/img/icon-512.png", "Brand", "Tunr-app-icon-512.png"),
        ("repo", "website/assets/img/icon-rounded.png", "Brand", "Tunr-app-icon-512-rounded.png"),
        ("repo", "docs/brand/wordmark-white.png", "Brand", "Tunr-wordmark-white-transparent.png"),
        ("repo", "docs/brand/wordmark-dark.png", "Brand", "Tunr-wordmark-on-dark.png"),
    ],
    "Apple": [
        ("appstore", "tunr/en/iphone-6.9/*.png", "Apple/iPhone 6.9-inch", None),
        ("appstore", "tunr/en/iphone-6.3/*.png", "Apple/iPhone 6.3-inch", None),
        ("appstore", "tunr/en/ipad-13/*.png", "Apple/iPad 13-inch", None),
        ("appstore", "tunr/en/mac/*.png", "Apple/Mac", None),
        ("appstore", "tunr/en/appletv/*.png", "Apple/Apple TV", None),
        ("appstore", "tunr/en/appletv-brand/*.png", "Apple/Apple TV - Top Shelf & Icons", None),
        ("appstore", "tunr/en/icon-1024.png", "Apple/App Icon", "Tunr-app-icon-1024.png"),
    ],
    "Android": [
        ("playstore", "tunr/en/phone/*.png", "Android/Phone", None),
        ("playstore", "tunr/en/tablet-7/*.png", "Android/Tablet 7-inch", None),
        ("playstore", "tunr/en/tablet-10/*.png", "Android/Tablet 10-inch", None),
        ("playstore", "tunr/en/tv/*.png", "Android/Android TV", None),
        ("playstore", "tunr/en/icon-512.png", "Android/App Icon", "Tunr-play-icon-512.png"),
        ("playstore", "tunr/en/feature-graphic-1024x500.png", "Android/Google Play", None),
        ("playstore", "tunr/en/tv-banner-1280x720.png", "Android/Google Play", None),
    ],
    "Promo": [
        ("appstore", "tunr/en/promo/header-*.png", "Promo", None),
        ("appstore", "tunr/en/promo/search-results-*.png", "Promo", None),
        ("appstore", "tunr/en/promo/promo-*.png", "Promo", None),
        ("repo", "website/assets/img/og-image.png", "Promo", "og-image-1200x630.png"),
    ],
}
# onderdelen die een platform zijn (komen in presskit.json → platforms)
PLATFORMS = ["Apple", "Android"]
PLATFORM_NAMES = {"Apple": "iPhone, iPad, Mac, Apple TV (App Store)",
                  "Android": "Phone, tablet, Android TV (Google Play)"}
# deze platforms moeten bestanden hebben (anders stopt het script); de rest komt mee zodra de map er is
REQUIRED = ["Apple"]


def collect(appstore: pathlib.Path):
    """[(naam in de zip, bronbestand)], gesorteerd; plus waarschuwingen. Stopt als een platform leeg is."""
    # playstore/ staat naast appstore/ in tunr-beheer (Google Play-afbeeldingen, tools/make_playstore_media.py)
    roots = {"appstore": appstore, "playstore": appstore.parent / "playstore", "repo": root}
    out, warn, per_section = {}, [], {}
    for section, rules in LAYOUT.items():
        n = 0
        for src, pattern, folder, rename in rules:
            base = roots[src]
            files = sorted(p for p in glob.glob(str(base / pattern)) if os.path.isfile(p))
            if not files:
                warn.append(f"geen bestanden voor {src}:{pattern}")
                continue
            if rename and len(files) != 1:
                raise SystemExit(f"{pattern}: nieuwe naam {rename} maar {len(files)} bestanden")
            for f in files:
                arc = f"{TOP}/{folder}/{rename or os.path.basename(f)}"
                out[arc] = pathlib.Path(f)
                n += 1
        per_section[section] = n
    for p in REQUIRED:
        if not per_section.get(p):
            raise SystemExit(f"Onderdeel {p} heeft geen bestanden: klopt --appstore ({appstore})?")
    return sorted(out.items()), warn, [p for p in PLATFORMS if per_section.get(p)]


def colors_txt():
    lines = ["Tunr brand colours", ""]
    lines += [f"{name:<11} {hexv}" for name, hexv in COLORS]
    lines += ["", "Accent gradient: #FF5A1F -> #FFB020 (135 degrees).",
              "Use the white wordmark on dark backgrounds (#0A0A0C or darker photos).", ""]
    return "\n".join(lines)


def readme_txt(version, date, platforms, counts):
    plat = "\n".join(f"  - {p}: {PLATFORM_NAMES.get(p, p)}" for p in platforms)
    folders = "\n".join(f"  {k:<44} {v} file{'s' if v != 1 else ''}" for k, v in counts)
    return f"""TUNR PRESS KIT
==============

Tunr is a free radio and podcast app: every radio station in the world, on every screen.

Key facts
  - 50,000+ radio stations from 200+ countries, plus the most popular podcasts
  - Available for iPhone, iPad, Mac, Apple TV, CarPlay, Android, Android TV,
    Android Auto and the web (web player at {SITE}/web/)
  - Free, no account, no ads
  - Search, browse by country or genre, or explore stations on a world map

Website   {SITE}
Contact   {CONTACT}

Contents
{folders}

Platforms in this kit
{plat}

Usage
  The images in this kit may be used for editorial coverage of Tunr (articles,
  reviews, videos). Please don't alter the logo or app icon. Station names and
  logos shown in the screenshots belong to their respective broadcasters.

Press kit version {version} ({date})
"""


def zinfo(name, is_dir=False):
    zi = zipfile.ZipInfo(name + ("/" if is_dir else ""), ZIP_TIME)
    zi.create_system = 3                                   # unix-rechten
    zi.external_attr = ((0o40755 if is_dir else 0o100644) << 16) | (0x10 if is_dir else 0)
    return zi


def content_hash(entries):
    """sha256 over (naam, sha256 van de bytes) per bestand, gesorteerd op naam → eerste 6 tekens."""
    h = hashlib.sha256()
    for name, data in sorted(entries.items()):
        h.update(name.encode() + b"\0" + hashlib.sha256(data).hexdigest().encode() + b"\n")
    return h.hexdigest()[:6]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--appstore", required=True, help="map appstore/ uit een checkout van tunr-beheer")
    ap.add_argument("--out", default=str(root / "website/presskit"), help="uitvoermap (zip + presskit.json)")
    ap.add_argument("--previous", help="presskit.json die nu online staat (versie blijft gelijk bij gelijke inhoud)")
    ap.add_argument("--date", help="datum voor een nieuwe versie (YYYY-MM-DD, standaard vandaag UTC; voor tests)")
    a = ap.parse_args(argv)

    appstore = pathlib.Path(a.appstore).resolve()
    files, warn, platforms = collect(appstore)
    for w in warn:
        print(f"::warning::presskit: {w}", file=sys.stderr)

    entries = {arc: src.read_bytes() for arc, src in files}
    entries[f"{TOP}/Brand/colors.txt"] = colors_txt().encode()
    # telling per map (voor de README), en de hash zonder README (die bevat de versie zelf)
    counts = {}
    for arc in entries:
        folder = arc[len(TOP) + 1:].rsplit("/", 1)[0]
        counts[folder] = counts.get(folder, 0) + 1
    counts_sorted = sorted(counts.items())
    # README-sjabloon zonder versie/datum telt mee, zodat een tekstwijziging ook een nieuwe versie geeft
    template = readme_txt("{version}", "{date}", platforms, counts_sorted).encode()
    digest = content_hash({**entries, f"{TOP}/README.txt": template})

    today = a.date or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    version, date = f"{today.replace('-', '.')}-{digest}", today
    if a.previous:
        try:
            prev = json.loads(pathlib.Path(a.previous).read_text(encoding="utf-8"))
            pv, pd = str(prev.get("version", "")), str(prev.get("date", ""))
            if pv.endswith(f"-{digest}") and len(pd) >= 10:
                version, date = pv, pd[:10]
        except (OSError, ValueError, AttributeError):
            pass
    entries[f"{TOP}/README.txt"] = readme_txt(version, date, platforms, counts_sorted).encode()

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    zpath = out / ZIP_NAME
    tmp = zpath.with_suffix(".zip.tmp")
    names = sorted(entries)
    dirs = sorted({n.rsplit("/", i)[0] for n in names for i in range(1, n.count("/") + 1)})
    with zipfile.ZipFile(tmp, "w") as z:
        for d in dirs:
            z.writestr(zinfo(d, True), b"")
        # README eerst, daarna alles op naam
        for n in sorted(names, key=lambda n: (n != f"{TOP}/README.txt", n)):
            data = entries[n]
            png = n.lower().endswith(".png")         # PNG is al gecomprimeerd: opslaan, tekst: deflate
            z.writestr(zinfo(n), data, compress_type=zipfile.ZIP_STORED if png else zipfile.ZIP_DEFLATED)
    os.replace(tmp, zpath)

    meta = {
        "version": version,
        "date": date,
        "size": zpath.stat().st_size,
        "files": len(names),
        "platforms": platforms,
    }
    (out / "presskit.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print(f"presskit {version}: {len(names)} bestanden, {meta['size'] / 1e6:.1f} MB → {zpath}")
    return meta


if __name__ == "__main__":
    main()

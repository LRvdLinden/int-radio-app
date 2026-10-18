#!/usr/bin/env python3
"""Google Play-afbeeldingen van Tunr (Engels) uit echte schermafbeeldingen van de Android-app.

    python3 tools/make_playstore_media.py --raw <map met ruwe opnames> [--out playstore/tunr/en]
    python3 tools/make_playstore_media.py --demo [--out <map>]     # zonder opnames: proefopmaak

De ruwe opnames maakt de workflow *Play Store media* (.github/workflows/playstore-media.yml): de app start in de
Android-emulator met `--es tunr_screenshot <scène>` (android/.../ui/ScreenshotMode.kt) en wordt gefotografeerd.
Bestandsnamen: `<toestel>-<scène>.png`, toestel = phone | tablet7 | tablet10 | tv.

Uitvoer (PNG zonder alfakanaal, binnen de regels van Google Play: elke zijde 320–3840 px, lange zijde ≤ 2× de korte;
telefoon en tablets 9:16 / 16:9 en ≥ 1080 px, zodat ze ook in aanbevelingen van Google Play mogen):
  <out>/phone/NN-<scène>.png          1080 × 1920   telefoon (verplicht: min. 2, max. 8)
  <out>/tablet-7/NN-<scène>.png       1080 × 1920 of 1920 × 1080   7-inch tablet
  <out>/tablet-10/NN-<scène>.png      1440 × 2560 of 2560 × 1440   10-inch tablet
  <out>/tv/NN-<scène>.png             1920 × 1080   Android TV (verplicht voor tv: min. 1)
  <out>/icon-512.png                  512 × 512     app-icoon (verplicht, 32-bit PNG)
  <out>/feature-graphic-1024x500.png  1024 × 500    feature graphic (verplicht)
  <out>/tv-banner-1280x720.png        1280 × 720    Android TV-banner (verplicht voor tv)
Een verkeerde maat of een alfakanaal (behalve het icoon) = foutmelding (exit 1).
Android Auto: Google Play vraagt voor media-apps in Android Auto geen eigen schermafbeeldingen.
"""
import argparse, pathlib, shutil, sys, tempfile
from PIL import Image, ImageChops, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_appstore_media as am  # noqa: E402  (achtergrond, koppen, schaduw, Apple TV-opmaak: zelfde stijl)
import make_icons as mi  # noqa: E402  (app-icoon, symbool, TV-banner)

ROOT = pathlib.Path(__file__).resolve().parent.parent
PHONE_SCENES = ["discover", "player", "map", "search", "podcasts", "library"]
TV_SCENES = ["discover", "player", "browse", "podcasts", "search"]
# toestel → (map, staand formaat, liggend formaat, soort, scènes)
DEVICES = {
    "phone": ("phone", (1080, 1920), (1920, 1080), "phone", PHONE_SCENES),
    "tablet7": ("tablet-7", (1080, 1920), (1920, 1080), "tablet", PHONE_SCENES),
    "tablet10": ("tablet-10", (1440, 2560), (2560, 1440), "tablet", PHONE_SCENES),
    "tv": ("tv", (1920, 1080), (1920, 1080), "tv", TV_SCENES),
}
CAPTIONS = dict(am.CAPTIONS)
CAPTIONS["player"] = ("Beautifully simple", "Now playing, Android Auto and sleep timer")
CAPTIONS["library"] = ("Your favourites\nalways at hand", "Favourites, recents and followed podcasts")
WIDE = {k: (v[0].replace("\n", " "), v[1]) for k, v in CAPTIONS.items()}
WIDE["player"] = ("Beautifully simple", "Now playing with album art, right on your TV")


def android_frame(shot, kind, target_w):
    """Schermafbeelding in een strakke, afgeronde rand (geen echt toestel); telefoon met een camera-gaatje."""
    shot = shot.convert("RGBA")
    portrait = shot.height >= shot.width
    if kind == "phone":
        bezel, r_screen = int(target_w * 0.03), int(target_w * 0.075)
    else:
        bezel, r_screen = int(target_w * (0.026 if portrait else 0.018)), int(target_w * (0.04 if portrait else 0.025))
    sw = target_w - 2 * bezel
    sh = round(shot.height * sw / shot.width)
    screen = shot.resize((sw, sh), Image.LANCZOS)
    W, H = target_w, sh + 2 * bezel
    r_out = r_screen + bezel
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    body = Image.new("RGBA", (W, H), (0x1B, 0x1B, 0x21, 255))
    frame.paste(body, (0, 0), am.rounded_mask((W, H), r_out))
    d = ImageDraw.Draw(frame)
    lw = max(2, W // 300)
    d.rounded_rectangle([lw // 2, lw // 2, W - 1 - lw // 2, H - 1 - lw // 2], r_out, outline=(255, 255, 255, 46), width=lw)
    frame.paste(screen, (bezel, bezel), ImageChops.multiply(am.rounded_mask((sw, sh), r_screen), screen.getchannel("A")))
    if kind == "phone":
        cr = max(6, int(sw * 0.018))
        cx, cy = bezel + sw // 2, bezel + int(sw * 0.035)
        ImageDraw.Draw(frame).ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(0, 0, 0, 255))
    return frame, r_out


def compose_portrait(shot, kind, size, scene):
    W, H = size
    title, sub = CAPTIONS[scene]
    img = am.background(W, H, (0.5, 0.02))
    u = W / 1080
    top = int(120 * u)
    text_bottom = am.draw_text_block(img, top, title, sub, int(92 * u), int(41 * u), int(W * 0.86), sub_w=int(W * 0.92))
    bar_w, bar_h = int(100 * u), max(5, int(8 * u))
    img.paste(am.gradient_bar(bar_w, bar_h), ((W - bar_w) // 2, int(text_bottom + 22 * u)))
    dev_top = int(text_bottom + 22 * u + bar_h + 56 * u)
    avail_h = H - dev_top - int(80 * u)
    ratio = shot.height / shot.width
    bez = 0.03 if kind == "phone" else 0.026
    fit_w = int(avail_h / (ratio * (1 - 2 * bez) + 2 * bez))
    frame, radius = android_frame(shot, kind, min(int(W * (0.78 if kind == "phone" else 0.84)), fit_w))
    x = (W - frame.width) // 2
    y = dev_top + max(0, (avail_h - frame.height) // 2)
    return am.place_with_shadow(img, frame, x, y, radius)


def compose_landscape(shot, kind, size, scene):
    """Liggende tablet: kop bovenaan, scherm eronder (zoals de Mac-opmaak)."""
    W, H = size
    title, sub = WIDE[scene]
    img = am.background(W, H, (0.5, -0.05))
    u = W / 2560
    text_bottom = am.draw_text_block(img, int(90 * u), title, sub, int(100 * u), int(44 * u), int(W * 0.8))
    dev_top = text_bottom + int(56 * u)
    avail_h, max_w = H - dev_top - int(70 * u), int(W * 0.84)
    ratio = shot.height / shot.width
    frame, radius = android_frame(shot, kind, min(max_w, int(avail_h / (ratio * 0.964 + 0.036))))
    x = (W - frame.width) // 2
    return am.place_with_shadow(img, frame, x, dev_top + max(0, (avail_h - frame.height) // 2), radius)


def compose_tv(shot, size, scene):
    """Android TV: zelfde opmaak als Apple TV (schermvullend + bijschriftband), op 3840 × 2160 getekend en verkleind."""
    title, sub = WIDE[scene]
    old_c, old_tv = am.WIDE_CAPTIONS.get(scene), am.TV_SUBLINES.get(scene)
    am.WIDE_CAPTIONS[scene] = (title, sub)
    am.TV_SUBLINES.pop(scene, None)
    try:
        big = am.compose_tv(shot, (3840, 2160), scene)
    finally:
        am.WIDE_CAPTIONS[scene] = old_c
        if old_tv:
            am.TV_SUBLINES[scene] = old_tv
    return big.resize(size, Image.LANCZOS)


def feature_graphic(raws, size=(1024, 500)):
    """Feature graphic: icoon + TUNR + kop links, rechts telefoons met de app (als er opnames zijn)."""
    W, H = size
    S = 2  # op dubbele maat tekenen
    img = am.background(W * S, H * S, (0.8, 0.4), 1.2)
    d = ImageDraw.Draw(img)
    x = 64 * S
    icon = mi.app_icon(96 * S)
    img.paste(icon.convert("RGB"), (x, 70 * S), am.rounded_mask((96 * S, 96 * S), 22 * S))
    wf = am.font("black", 50 * S)
    d.text((x + 116 * S, 82 * S), "TUNR", font=wf, fill=am.TEXT)
    ww = d.textlength("TUNR", font=wf)
    img.paste(am.gradient_bar(int(ww), 6 * S), (x + 116 * S, 146 * S))
    tf = am.font("black", 46 * S)
    y = 210 * S
    for ln in ("Every radio station", "in the world"):
        d.text((x, y), ln, font=tf, fill=am.TEXT)
        y += 54 * S
    d.text((x, y + 14 * S), "Live radio and podcasts from 200+ countries", font=am.font("semibold", 19 * S), fill=am.SECONDARY)
    shots = [raws.get(("phone", s)) for s in ("player", "discover")]
    shots = [s for s in shots if s]
    for i, p in enumerate(shots[:2]):
        fr, r = android_frame(Image.open(p), "phone", 190 * S)
        fx = W * S - (250 if i == 0 else 440) * S
        fy = (44 if i == 0 else 92) * S
        img = am.place_with_shadow(img, fr, fx, fy, r)
    return img.resize(size, Image.LANCZOS)


def demo_raw(device, scene):
    size = {"phone": (1080, 2400), "tablet7": (1200, 1920), "tablet10": (2560, 1600), "tv": (1920, 1080)}[device]
    dev = {"phone": "iphone69", "tablet7": "iphone69", "tablet10": "mac", "tv": "appletv"}[device]
    return am.demo_raw(dev, scene, size)


def check(path, size, problems, alpha=False):
    im = Image.open(path)
    if im.size != tuple(size):
        problems.append(f"{path}: {im.size[0]}×{im.size[1]}, verwacht {size[0]}×{size[1]}")
    if not alpha and im.mode not in ("RGB", "L"):
        problems.append(f"{path}: modus {im.mode} (alfakanaal niet toegestaan)")
    w, h = im.size
    if not (320 <= min(w, h) and max(w, h) <= 3840 and max(w, h) <= 2 * min(w, h)) and "feature" not in path.name:
        problems.append(f"{path}: {w}×{h} buiten de regels van Google Play")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", type=pathlib.Path, help="map met <toestel>-<scène>.png")
    ap.add_argument("--out", type=pathlib.Path, help="uitvoermap (standaard playstore/tunr/en; bij --demo een tijdelijke map)")
    ap.add_argument("--demo", action="store_true", help="proefopnames voor ontbrekende scènes (niet voor Google Play)")
    ap.add_argument("--only", help="alleen deze toestellen, kommagescheiden (bv. phone,tv)")
    a = ap.parse_args()
    if not a.raw and not a.demo:
        ap.error("--raw of --demo")
    out = a.out or (pathlib.Path(tempfile.mkdtemp(prefix="tunr-play-")) if a.demo else ROOT / "playstore/tunr/en")
    out.mkdir(parents=True, exist_ok=True)
    only = set((a.only or ",".join(DEVICES)).split(","))
    raws, problems, written = {}, [], []
    for dev, (_, _, _, _, scenes) in DEVICES.items():
        for s in scenes:
            p = a.raw / f"{dev}-{s}.png" if a.raw else None
            if p and p.exists():
                raws[(dev, s)] = p

    for dev, (folder, portrait, landscape, kind, scenes) in DEVICES.items():
        if dev not in only:
            continue
        dest = out / folder
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True)
        n = 0
        for s in scenes:
            p = raws.get((dev, s))
            if p:
                shot = Image.open(p)
                shot.load()
            elif a.demo:
                shot = demo_raw(dev, s)
            else:
                print(f"waarschuwing: geen opname {dev}-{s}", file=sys.stderr)
                continue
            if kind == "tv":
                size = landscape
                img = compose_tv(shot, size, s)
            elif shot.height >= shot.width:
                size = portrait
                img = compose_portrait(shot, kind, size, s)
            else:
                size = landscape
                img = compose_landscape(shot, kind, size, s)
            n += 1
            f = dest / f"{n:02d}-{s}.png"
            img.convert("RGB").save(f, optimize=True)
            check(f, size, problems)
            written.append((f, size))
        if dev == "phone" and n < 2:
            problems.append("telefoon: minder dan 2 schermafbeeldingen (Google Play vraagt er min. 2)")
        if dev == "tv" and n < 1:
            print("waarschuwing: tv zonder schermafbeelding (Google Play vraagt er min. 1 voor Android TV)", file=sys.stderr)

    f = out / "icon-512.png"
    mi.app_icon(512).save(f)  # 32-bit PNG, vierkant; Google Play rondt zelf af
    check(f, (512, 512), problems, alpha=True)
    written.append((f, (512, 512)))
    f = out / "feature-graphic-1024x500.png"
    feature_graphic(raws).convert("RGB").save(f, optimize=True)
    check(f, (1024, 500), problems)
    written.append((f, (1024, 500)))
    f = out / "tv-banner-1280x720.png"
    mi.tv_banner(1280, 720).save(f, optimize=True)
    check(f, (1280, 720), problems)
    written.append((f, (1280, 720)))

    for f, (w, h) in written:
        print(f"{f.relative_to(out)}  {w}×{h}")
    if problems:
        print("\n".join("FOUT: " + p for p in problems), file=sys.stderr)
        sys.exit(1)
    print(f"klaar: {len(written)} bestanden in {out}")


if __name__ == "__main__":
    main()

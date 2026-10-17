#!/usr/bin/env python3
"""App Store-afbeeldingen van Tunr (Engels) uit echte schermafbeeldingen van de app.

    python3 tools/make_appstore_media.py --raw <map met ruwe opnames> [--out appstore/en]
    python3 tools/make_appstore_media.py --demo [--out <map>]     # zonder opnames: proefopmaak

De ruwe opnames maakt de workflow *App Store media* (.github/workflows/appstore-media.yml): de app start in de
simulator / op de Mac met `-TunrScreenshot <scène>` (apple/Shared/App/ScreenshotMode.swift) en wordt gefotografeerd.
Bestandsnamen: `<toestel>-<scène>.png`, toestel = iphone69 | iphone63 | ipad13 | mac | appletv.

Uitvoer (PNG, zonder alfakanaal, exact de maten van App Store Connect):
  <out>/iphone-6.9/NN-<scène>.png   1320 × 2868   (iPhone 16 Pro Max)
  <out>/iphone-6.3/NN-<scène>.png   1206 × 2622   (iPhone 16 Pro, verplicht: "iPhone met Dynamic Island")
  <out>/ipad-13/NN-<scène>.png      2064 × 2752
  <out>/mac/NN-<scène>.png          2880 × 1800
  <out>/appletv/NN-<scène>.png      3840 × 2160
  <out>/icon-1024.png               1024 × 1024 (App Store-icoon iOS/macOS)
  <out>/appletv-brand/*.png         Apple TV-icoon (1280×768, 400×240, 800×480) en Top Shelf (gewoon + breed, 1x/2x)
  <out>/promo/promo-1920x1080.png   promotiebanner
  <out>/raw/...                     de originele opnames
Een verkeerde maat of een alfakanaal = foutmelding (exit 1).
"""
import argparse, math, os, pathlib, shutil, sys, tempfile
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "apple/Shared/Assets.xcassets"
BRAND = ASSETS / "App Icon & Top Shelf Image.brandassets"

BG = (0x0A, 0x0A, 0x0C)
SURFACE = (0x16, 0x16, 0x1A)
ACCENT = (0xFF, 0x5A, 0x1F)
ACCENT2 = (0xFF, 0xB0, 0x20)
TEXT = (255, 255, 255)
SECONDARY = (0xA8, 0xA8, 0xB3)

# toestel → (uitvoermap, maat, soort, scènes in volgorde)
DEVICES = {
    "iphone69": ("iphone-6.9", (1320, 2868), "phone", ["discover", "player", "map", "search", "podcasts", "library"]),
    "iphone63": ("iphone-6.3", (1206, 2622), "phone", ["discover", "player", "map", "search", "podcasts", "library"]),
    "ipad13": ("ipad-13", (2064, 2752), "tablet", ["discover", "player", "map", "search", "podcasts", "library"]),
    "mac": ("mac", (2880, 1800), "mac", ["discover", "player", "map", "podcasts", "library"]),
    "appletv": ("appletv", (3840, 2160), "tv", ["discover", "player", "browse", "podcasts", "search"]),
}

CAPTIONS = {
    "discover": ("Every radio station\nin the world", "Tens of thousands of stations from 200+ countries"),
    "browse": ("Find your sound", "Genres, regions and languages"),
    "map": ("Explore the world map", "Tap a dot, start listening"),
    "search": ("Search anything", "Stations, countries and cities"),
    "podcasts": ("All the top podcasts", "Follow shows and resume where you left off"),
    "player": ("Beautifully simple", "Now playing, AirPlay and sleep timer"),
    "library": ("Your favourites\neverywhere", "Synced via iCloud"),
}
# Apple TV en Mac: één regel (breed scherm)
WIDE_CAPTIONS = {k: (v[0].replace("\n", " "), v[1]) for k, v in CAPTIONS.items()}
WIDE_CAPTIONS["player"] = ("Beautifully simple", "Now playing, AirPlay and sleep timer")
TV_SUBLINES = {"player": "Now playing with album art, right on your TV"}

FONT_NAMES = {
    "black": ["InterDisplay-Black.otf", "Inter-Black.otf", "InterDisplay-ExtraBold.otf", "Inter-ExtraBold.otf",
              "DejaVuSans-Bold.ttf"],
    "semibold": ["Inter-SemiBold.otf", "InterDisplay-SemiBold.otf", "Inter-Medium.otf", "DejaVuSans.ttf"],
}
FONT_DIRS = [pathlib.Path(os.environ.get("TUNR_FONT_DIR", ROOT / "apple/build/fonts")), pathlib.Path("/usr/share/fonts"), pathlib.Path.home() / "Library/Fonts",
             pathlib.Path("/Library/Fonts"), pathlib.Path("/opt/homebrew/share/fonts")]
_font_cache = {}


def font(kind, size):
    """Inter (Display) Black / SemiBold; zoekt in $TUNR_FONT_DIR of apple/build/fonts (workflow), systeemfonts, anders DejaVu/standaard."""
    key = (kind, size)
    if key in _font_cache:
        return _font_cache[key]
    path = _font_cache.get(kind)
    if path is None:
        path = ""
        for name in FONT_NAMES[kind]:
            for d in FONT_DIRS:
                if d.is_dir():
                    hit = next(iter(sorted(d.rglob(name))), None)
                    if hit:
                        path = str(hit)
                        break
            if path:
                break
        if not path:
            print(f"waarschuwing: geen font voor {kind}, standaardfont", file=sys.stderr)
        _font_cache[kind] = path
    f = ImageFont.truetype(path, size) if path else ImageFont.load_default(size)
    _font_cache[key] = f
    return f


# ---------------------------------------------------------------- tekenhulpen

def background(w, h, glow_at=(0.5, 0.0), strength=1.0):
    """Donker (#0A0A0C) met een zachte oranje→amber gloed."""
    sw, sh = max(8, w // 16), max(8, h // 16)
    small = Image.new("RGB", (sw, sh), BG)
    px = small.load()
    gx, gy = glow_at
    for y in range(sh):
        for x in range(sw):
            nx, ny = x / sw, y / sh
            # twee gloedvlekken: accent bij glow_at, amber diagonaal verder
            d1 = math.hypot((nx - gx) * w / max(w, h), (ny - gy) * h / max(w, h))
            d2 = math.hypot((nx - (1 - gx * 0.6)) * w / max(w, h), (ny - min(1.0, gy + 0.9)) * h / max(w, h))
            a1 = max(0.0, 1 - d1 / 0.62) ** 2 * 0.42 * strength
            a2 = max(0.0, 1 - d2 / 0.55) ** 2 * 0.16 * strength
            c = [BG[i] + (ACCENT[i] - BG[i]) * a1 + (ACCENT2[i] - BG[i]) * a2 for i in range(3)]
            px[x, y] = tuple(int(max(0, min(255, v))) for v in c)
    img = small.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(max(2, min(w, h) // 200)))
    return img


def gradient_bar(w, h):
    bar = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(bar)
    for x in range(w):
        t = x / max(1, w - 1)
        d.line([(x, 0), (x, h)], fill=tuple(int(ACCENT[i] * (1 - t) + ACCENT2[i] * t) for i in range(3)))
    return bar


def rounded_mask(size, radius, ss=3):
    w, h = size
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * ss - 1, h * ss - 1], radius * ss, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def wrap(text, fnt, max_w, draw):
    """Eigen regeleinden (\\n) respecteren; daarnaast afbreken op breedte."""
    lines = []
    for para in text.split("\n"):
        words, cur = para.split(), ""
        for wd in words:
            t = (cur + " " + wd).strip()
            if draw.textlength(t, font=fnt) <= max_w or not cur:
                cur = t
            else:
                lines.append(cur)
                cur = wd
        lines.append(cur)
    return lines


def draw_text_block(img, top, title, sub, title_size, sub_size, max_w, align="center", x=None, sub_w=None):
    """Kop (Inter Display Black, wit) + subregel (secundair) met een kleine accentstreep; geeft de onderkant terug."""
    d = ImageDraw.Draw(img)
    W = img.width
    tf, sf = font("black", title_size), font("semibold", sub_size)
    # kop zo nodig kleiner tot hij in max. 2 regels past
    while True:
        lines = wrap(title, tf, max_w, d)
        if len(lines) <= 2 or title_size < 40:
            break
        title_size = int(title_size * 0.92)
        tf = font("black", title_size)
    y = top
    lh = int(title_size * 1.08)
    for ln in lines:
        tw = d.textlength(ln, font=tf)
        tx = (W - tw) / 2 if align == "center" else x
        bb = d.textbbox((0, 0), ln, font=tf)
        d.text((tx, y - bb[1] + (lh - (bb[3] - bb[1])) / 2), ln, font=tf, fill=TEXT)
        y += lh
    y += int(sub_size * 0.55)
    for ln in wrap(sub, sf, sub_w or max_w, d):
        tw = d.textlength(ln, font=sf)
        tx = (W - tw) / 2 if align == "center" else x
        d.text((tx, y), ln, font=sf, fill=SECONDARY)
        y += int(sub_size * 1.3)
    return y


def shadow_layer(size, box, radius, blur, color=(0, 0, 0), opacity=170, spread=0):
    sh = Image.new("RGBA", size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(sh).rounded_rectangle([x0 - spread, y0 - spread, x1 + spread, y1 + spread], radius,
                                         fill=color + (opacity,))
    return sh.filter(ImageFilter.GaussianBlur(blur))


def device_frame(shot, kind, target_w):
    """Schermafbeelding in een strakke, afgeronde 'toestel'-rand (geen fotos van Apple-toestellen)."""
    shot = shot.convert("RGBA")
    if kind == "phone":
        bezel, r_screen = int(target_w * 0.028), int(target_w * 0.135)
    elif kind == "tablet":
        bezel, r_screen = int(target_w * 0.026), int(target_w * 0.035)
    else:
        bezel, r_screen = 0, 0
    sw = target_w - 2 * bezel
    sh = round(shot.height * sw / shot.width)
    screen = shot.resize((sw, sh), Image.LANCZOS)
    W, H = target_w, sh + 2 * bezel
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    if bezel:
        r_out = r_screen + bezel
        body = Image.new("RGBA", (W, H), (0x1B, 0x1B, 0x21, 255))
        frame.paste(body, (0, 0), rounded_mask((W, H), r_out))
        # dunne lichte rand + binnenrand
        d = ImageDraw.Draw(frame)
        lw = max(2, W // 300)
        d.rounded_rectangle([lw // 2, lw // 2, W - 1 - lw // 2, H - 1 - lw // 2], r_out, outline=(255, 255, 255, 46), width=lw)
        inner = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(inner).rounded_rectangle([bezel - lw, bezel - lw, W - bezel + lw - 1, H - bezel + lw - 1],
                                                r_screen + lw, fill=(0, 0, 0, 255))
        frame = Image.alpha_composite(frame, inner)
        frame.paste(screen, (bezel, bezel), ImageChops.multiply(rounded_mask((sw, sh), r_screen), screen.getchannel("A")))
        if kind == "phone":
            # Dynamic Island
            iw, ih = int(sw * 0.30), int(sw * 0.085)
            ix, iy = bezel + (sw - iw) // 2, bezel + int(sw * 0.028)
            ImageDraw.Draw(frame).rounded_rectangle([ix, iy, ix + iw, iy + ih], ih // 2, fill=(0, 0, 0, 255))
    else:
        # Mac-venster: de opname heeft zelf al titelbalk en afgeronde hoeken; alleen een zachte rand
        frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        r = int(W * 0.0085)
        frame.paste(screen, (0, 0), ImageChops.multiply(rounded_mask((W, H), r), screen.getchannel("A")))
        lw = max(2, W // 900)
        ImageDraw.Draw(frame).rounded_rectangle([0, 0, W - 1, H - 1], r, outline=(255, 255, 255, 40), width=lw)
        r_screen = r
    return frame, max(r_screen + bezel, 1)


def place_with_shadow(canvas, frame, x, y, radius):
    W, H = canvas.size
    box = (x, y, x + frame.width, y + frame.height)
    base = canvas.convert("RGBA")
    # oranje gloed + donkere slagschaduw
    base = Image.alpha_composite(base, shadow_layer((W, H), box, radius, frame.width // 9, ACCENT, 70, frame.width // 40))
    base = Image.alpha_composite(base, shadow_layer((W, H), (box[0], box[1] + frame.width // 40, box[2], box[3] + frame.width // 40),
                                                    radius, frame.width // 22, (0, 0, 0), 190))
    base.alpha_composite(frame, (int(x), int(y)))
    return base.convert("RGB")


# ---------------------------------------------------------------- opmaak per soort

def compose_portrait(shot, kind, size, scene):
    W, H = size
    title, sub = CAPTIONS[scene]
    img = background(W, H, (0.5, 0.02))
    u = W / 1320
    is_tab = kind == "tablet"
    top = int((150 if not is_tab else 120) * u)
    t_size = int((112 if not is_tab else 92) * u)
    s_size = int((50 if not is_tab else 42) * u)
    text_bottom = draw_text_block(img, top, title, sub, t_size, s_size, int(W * 0.86), sub_w=int(W * 0.92))
    # accentstreep onder de tekst
    bar_w, bar_h = int(120 * u), max(6, int(9 * u))
    img.paste(gradient_bar(bar_w, bar_h), ((W - bar_w) // 2, int(text_bottom + 26 * u)))
    dev_top = int(text_bottom + 26 * u + bar_h + (70 if not is_tab else 60) * u)
    bottom_margin = int((110 if not is_tab else 90) * u)
    avail_h = H - dev_top - bottom_margin
    max_w = int(W * (0.80 if not is_tab else 0.84))
    # breedte zodat het hele toestel past (rand meegerekend)
    bezel_frac = 0.028 if kind == "phone" else 0.026
    ratio = shot.height / shot.width
    fit_w = int(avail_h / (ratio * (1 - 2 * bezel_frac) + 2 * bezel_frac))
    target_w = min(max_w, fit_w)
    frame, radius = device_frame(shot, kind, target_w)
    x = (W - frame.width) // 2
    y = dev_top + max(0, (avail_h - frame.height) // 2)
    return place_with_shadow(img, frame, x, y, radius)


def compose_mac(shot, size, scene):
    W, H = size
    title, sub = WIDE_CAPTIONS[scene]
    img = background(W, H, (0.5, -0.05))
    text_bottom = draw_text_block(img, 120, title, sub, 112, 50, int(W * 0.8))
    dev_top = text_bottom + 70
    avail_h, max_w = H - dev_top - 90, int(W * 0.84)
    ratio = shot.height / shot.width
    target_w = min(max_w, int(avail_h / ratio))
    frame, radius = device_frame(shot, "mac", target_w)
    x = (W - frame.width) // 2
    return place_with_shadow(img, frame, x, dev_top + max(0, (avail_h - frame.height) // 2), radius)


def compose_tv(shot, size, scene):
    """Apple TV: schermvullende opname (vooral de interface) met onderin een bijschriftband."""
    W, H = size
    img = shot.convert("RGB")
    if img.size != (W, H):
        # 16:9 schalen; een afwijkende verhouding bijsnijden vanuit het midden
        r = max(W / img.width, H / img.height)
        img = img.resize((math.ceil(img.width * r), math.ceil(img.height * r)), Image.LANCZOS)
        l, t = (img.width - W) // 2, (img.height - H) // 2
        img = img.crop((l, t, l + W, t + H))
    title, sub = WIDE_CAPTIONS[scene]
    sub = TV_SUBLINES.get(scene, sub)
    band_h = int(H * 0.25)
    # verloop van transparant naar bijna-zwart
    grad = Image.new("L", (1, band_h))
    for y in range(band_h):
        grad.putpixel((0, y), int(246 * min(1.0, (y / band_h) / 0.5) ** 1.3))
    grad = grad.resize((W, band_h))
    dark = Image.new("RGB", (W, band_h), BG)
    img.paste(dark, (0, H - band_h), grad)
    d = ImageDraw.Draw(img)
    x = int(W * 0.045)
    tf, sf = font("black", 118), font("semibold", 56)
    ty = H - int(band_h * 0.50)
    bb = d.textbbox((0, 0), title, font=tf)
    d.text((x, ty - bb[1]), title, font=tf, fill=TEXT)
    tw = d.textlength(title, font=tf)
    sy = ty + (bb[3] - bb[1]) + 26
    d.text((x, sy), sub, font=sf, fill=SECONDARY)
    # accentstreep naast de kop
    img.paste(gradient_bar(12, bb[3] - bb[1] + 70 + 56), (x - 40, ty))
    # TUNR-woordmerk rechts
    wf = font("black", 84)
    wm = "TUNR"
    ww = d.textlength(wm, font=wf)
    wx, wy = W - x - ww, ty + 10
    d.text((wx, wy), wm, font=wf, fill=TEXT)
    img.paste(gradient_bar(int(ww), 10), (int(wx), int(wy + 104)))
    return img


# ---------------------------------------------------------------- iconen, Apple TV-merk, promo

def flatten(img, bg=BG):
    if img.mode in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")
        base = Image.new("RGBA", img.size, bg + (255,))
        base.alpha_composite(img)
        return base.convert("RGB")
    return img.convert("RGB")


def icon_1024():
    src = ASSETS / "AppIcon.appiconset/icon-1024.png"
    if not src.exists():
        raise SystemExit(f"FOUT: {src} ontbreekt (python3 tools/make_icons.py)")
    return flatten(Image.open(src))


def stack(name, scale):
    """Lagen van een tvOS-imagestack (Back onder, Front erop) samengevoegd."""
    base = BRAND / f"{name}.imagestack"
    out = None
    for layer in ("Back", "Front"):
        f = base / f"{layer}.imagestacklayer/Content.imageset/{layer.lower()}@{scale}x.png"
        if not f.exists():
            raise SystemExit(f"FOUT: {f} ontbreekt in de Apple TV-merkafbeeldingen")
        im = Image.open(f).convert("RGBA")
        out = im if out is None else Image.alpha_composite(out, im.resize(out.size, Image.LANCZOS))
    return flatten(out)


def appletv_brand():
    """{bestandsnaam: (afbeelding, verwachte maat)}"""
    items = {
        "app-icon-app-store-1280x768.png": (stack("App Icon - App Store", 1), (1280, 768)),
        "app-icon-400x240.png": (stack("App Icon", 1), (400, 240)),
        "app-icon-800x480.png": (stack("App Icon", 2), (800, 480)),
    }
    for folder, stem, sizes in (("Top Shelf Image", "top-shelf", ((1920, 720), (3840, 1440))),
                                ("Top Shelf Image Wide", "top-shelf-wide", ((2320, 720), (4640, 1440)))):
        for scale, sz in zip((1, 2), sizes):
            f = BRAND / f"{folder}.imageset/topshelf@{scale}x.png"
            if not f.exists():
                raise SystemExit(f"FOUT: {f} ontbreekt")
            items[f"{stem}-{sz[0]}x{sz[1]}.png"] = (flatten(Image.open(f)), sz)
    return items


def promo(raws, size=(1920, 1080)):
    """Promotiebanner: kop links, rechts iPad + iPhone (Ontdek/Speler) als die er zijn."""
    W, H = size
    img = background(W, H, (0.78, 0.35), 1.15)
    d = ImageDraw.Draw(img)
    icon = icon_1024().resize((150, 150), Image.LANCZOS)
    x = 120
    img.paste(icon, (x, 170), rounded_mask((150, 150), 34))
    wf = font("black", 76)
    d.text((x + 185, 192), "TUNR", font=wf, fill=TEXT)
    ww = d.textlength("TUNR", font=wf)
    img.paste(gradient_bar(int(ww), 8), (x + 185, 290))
    tf = font("black", 84)
    y = 420
    for ln in ("Every radio station", "in the world"):
        d.text((x, y), ln, font=tf, fill=TEXT)
        y += 96
    sf = font("semibold", 34)
    d.text((x, y + 24), "Live radio and podcasts from 200+ countries", font=sf, fill=SECONDARY)
    d.text((x, y + 72), "iPhone · iPad · Mac · Apple TV · CarPlay", font=sf, fill=SECONDARY)
    tab = raws.get(("ipad13", "discover"))
    ph = raws.get(("iphone69", "player")) or raws.get(("iphone63", "player")) or raws.get(("iphone69", "discover"))
    if tab:
        fr, r = device_frame(Image.open(tab), "tablet", 600)
        img = place_with_shadow(img, fr, W - 690, 170, r)
    if ph:
        fr, r = device_frame(Image.open(ph), "phone", 300)
        img = place_with_shadow(img, fr, W - 860 if tab else W - 520, 360 if tab else 170, r)
    return img


# ---------------------------------------------------------------- demo-opnames (alleen proefopmaak)

def demo_raw(device, scene, size):
    """Proefopname: liefst een echte schermafbeelding van de webspeler (docs/screenshots), anders een schets."""
    W, H = size
    shots = ROOT / "docs/screenshots"
    pick = {"discover": "web_discover", "browse": "web_browse", "map": "web_map", "search": "web_search",
            "player": "web_full", "library": "web_library", "podcasts": "web_browse"}[scene]
    wide = device in ("mac", "appletv")
    cand = shots / (f"{pick}_1440.jpg" if wide else f"{pick}_390.jpg")
    if wide and not cand.exists():
        cand = shots / ("web_map_world_1440.jpg" if scene == "map" else "web_discover_1440.jpg")
    img = Image.new("RGB", (W, H), BG)
    if cand.exists():
        src = Image.open(cand).convert("RGB")
        r = W / src.width
        src = src.resize((W, max(1, round(src.height * r))), Image.LANCZOS).crop((0, 0, W, H))
        img.paste(src, (0, 0))
    else:
        d = ImageDraw.Draw(img)
        for i in range(6):
            y = int(H * (0.12 + i * 0.14))
            d.rounded_rectangle([W * 0.05, y, W * 0.95, y + H * 0.11], int(W * 0.03), fill=SURFACE)
    d = ImageDraw.Draw(img)
    d.text((W * 0.04, H * 0.965), f"DEMO {device}/{scene}", font=font("semibold", max(14, W // 40)), fill=(255, 90, 31))
    return img


DEMO_SIZES = {"iphone69": (1320, 2868), "iphone63": (1206, 2622), "ipad13": (2064, 2752),
              "mac": (2880, 1856), "appletv": (3840, 2160)}


# ---------------------------------------------------------------- hoofdprogramma

def check(path, size, problems):
    im = Image.open(path)
    if im.size != tuple(size):
        problems.append(f"{path}: {im.size[0]}×{im.size[1]}, verwacht {size[0]}×{size[1]}")
    if im.mode not in ("RGB", "L"):
        problems.append(f"{path}: modus {im.mode} (alfakanaal niet toegestaan)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", type=pathlib.Path, help="map met <toestel>-<scène>.png")
    ap.add_argument("--out", type=pathlib.Path, help="uitvoermap (standaard appstore/en; bij --demo een tijdelijke map)")
    ap.add_argument("--demo", action="store_true", help="proefopnames maken voor ontbrekende scènes (niet voor de App Store)")
    ap.add_argument("--only", help="alleen deze toestellen, kommagescheiden (bv. iphone69,mac)")
    ap.add_argument("--strict", action="store_true", help="fout als er scènes ontbreken")
    a = ap.parse_args()

    out = a.out or (pathlib.Path(tempfile.mkdtemp(prefix="tunr-appstore-demo-")) if a.demo else ROOT / "appstore/en")
    raw_dir = a.raw or (out / "raw")
    if a.demo:
        raw_dir = out / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    devices = [x for x in DEVICES if not a.only or x in a.only.split(",")]

    raws, missing = {}, []
    for dev in devices:
        for scene in DEVICES[dev][3]:
            p = raw_dir / f"{dev}-{scene}.png"
            if not p.exists() and a.demo:
                demo_raw(dev, scene, DEMO_SIZES[dev]).save(p)
            if p.exists():
                raws[(dev, scene)] = p
            else:
                missing.append(f"{dev}-{scene}")

    out.mkdir(parents=True, exist_ok=True)
    if a.raw and out / "raw" != raw_dir:
        # originele opnames meenemen naar <out>/raw
        (out / "raw").mkdir(exist_ok=True)
        for p in raws.values():
            shutil.copy2(p, out / "raw" / p.name)

    problems, written = [], []
    for dev in devices:
        folder, size, kind, scenes = DEVICES[dev]
        dest = out / folder
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True)
        n = 0
        for scene in scenes:
            p = raws.get((dev, scene))
            if not p:
                continue
            shot = Image.open(p)
            shot.load()
            if kind in ("phone", "tablet"):
                img = compose_portrait(shot, kind, size, scene)
            elif kind == "mac":
                img = compose_mac(shot, size, scene)
            else:
                img = compose_tv(shot, size, scene)
            n += 1
            f = dest / f"{n:02d}-{scene}.png"
            img.convert("RGB").save(f, optimize=True)
            check(f, size, problems)
            written.append((f, size))

    f = out / "icon-1024.png"
    icon_1024().save(f)
    check(f, (1024, 1024), problems)
    written.append((f, (1024, 1024)))

    bdir = out / "appletv-brand"
    bdir.mkdir(exist_ok=True)
    for name, (im, sz) in appletv_brand().items():
        f = bdir / name
        im.save(f, optimize=True)
        check(f, sz, problems)
        written.append((f, sz))

    pdir = out / "promo"
    pdir.mkdir(exist_ok=True)
    f = pdir / "promo-1920x1080.png"
    promo(raws).save(f, optimize=True)
    check(f, (1920, 1080), problems)
    written.append((f, (1920, 1080)))

    for f, sz in written:
        print(f"{f.relative_to(out)}  {sz[0]}×{sz[1]}")
    print(f"uitvoer: {out}")
    if missing:
        print("ontbrekende opnames: " + ", ".join(missing), file=sys.stderr)
    if problems:
        print("FOUT:\n  " + "\n  ".join(problems), file=sys.stderr)
        sys.exit(1)
    if missing and a.strict:
        sys.exit(1)


if __name__ == "__main__":
    main()

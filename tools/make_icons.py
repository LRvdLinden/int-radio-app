#!/usr/bin/env python3
"""Maakt alle iconen en merkafbeeldingen van Tunr vanuit één tekening.

    python3 tools/make_icons.py

Het icoon: oranje→amber verloop (accent → accent2), wit symbool = zendmast-golven rond een punt,
met eronder de frequentieschaal met naald (zelfde motief als het woordmerk en de splash).

Uitvoer:
- apple/Shared/Assets.xcassets   AppIcon (iOS 1024 + macOS), App Icon & Top Shelf Image (tvOS), AccentColor
- android/app/src/main/res       adaptief icoon (voorgrond + verloop-achtergrond), mipmaps, tv_banner
- website/                       favicon, apple-touch-icon, PWA-iconen, og-image
- docs/brand/                    icon.png, wordmark.png (README), wordmark-white.png + wordmark-dark.png (presskit)
"""
import json, math, pathlib
from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = pathlib.Path(__file__).resolve().parent.parent
ACCENT = (0xFF, 0x5A, 0x1F)
ACCENT2 = (0xFF, 0xB0, 0x20)
BG = (0x0A, 0x0A, 0x0C)
FONT = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
SS = 4  # supersampling


def gradient(w, h, c1=ACCENT, c2=ACCENT2, angle=135):
    """Lineair verloop c1 (linksboven) → c2 (rechtsonder), met een zachte lichte vlek linksboven."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    a = math.radians(angle)
    dx, dy = math.cos(a - math.pi / 2), math.sin(a - math.pi / 2)
    dx, dy = 0.7071, 0.7071
    for y in range(h):
        for x in range(w):
            t = ((x / w) * dx + (y / h) * dy) / (dx + dy)
            r = math.hypot(x / w - 0.2, y / h - 0.15)
            glow = max(0.0, 1 - r / 0.75) * 0.12
            px[x, y] = tuple(int(min(255, (c1[i] * (1 - t) + c2[i] * t) + 255 * glow)) for i in range(3))
    return img


def fast_gradient(w, h):
    # snellere variant via kleine afbeelding + schalen
    small = gradient(max(2, w // 8), max(2, h // 8))
    return small.resize((w, h), Image.BICUBIC)


def symbol(size, color=(255, 255, 255, 255), needle=(10, 10, 12, 230), scale_bar=True):
    """Wit symbool op transparant, in een vierkant van `size` px."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = S / 1024
    cx, cy = 512 * u, (430 if scale_bar else 512) * u
    # punt
    r = 74 * u
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    # golven: twee bogen links en rechts met ronde uiteinden
    for radius, width in ((185, 58), (300, 58)):
        rr = radius * u; w = int(width * u)
        for start, end in ((-42, 42), (138, 222)):
            d.arc([cx - rr, cy - rr, cx + rr, cy + rr], start=start, end=end, fill=color, width=w)
            for ang in (start, end):
                a = math.radians(ang)
                mid = rr - w / 2
                ex, ey = cx + mid * math.cos(a), cy + mid * math.sin(a)
                d.ellipse([ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2], fill=color)
    if scale_bar:
        y = 790 * u
        x0, x1 = 222 * u, 802 * u
        h = 16 * u
        d.rounded_rectangle([x0, y - h / 2, x1, y + h / 2], radius=h / 2, fill=color)
        for i in range(9):
            x = x0 + (x1 - x0) * (i + 0.5) / 9
            th = (48 if i % 2 == 0 else 28) * u
            tw = 12 * u
            d.rounded_rectangle([x - tw / 2, y - h / 2 - th - 6 * u, x + tw / 2, y - h / 2 - 6 * u], radius=tw / 2, fill=color)
        # naald (donker), iets rechts van het midden
        nx = 600 * u; nw = 20 * u
        d.rounded_rectangle([nx - nw / 2, y - 92 * u, nx + nw / 2, y + 46 * u], radius=nw / 2, fill=needle)
    return img.resize((size, size), Image.LANCZOS)


def app_icon(size, rounded=False, circle=False):
    bg = fast_gradient(size, size).convert("RGBA")
    sym = symbol(size)
    bg.alpha_composite(sym)
    if rounded or circle:
        mask = Image.new("L", (size * SS, size * SS), 0)
        md = ImageDraw.Draw(mask)
        if circle:
            md.ellipse([0, 0, size * SS - 1, size * SS - 1], fill=255)
        else:
            md.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=size * SS * 0.2237, fill=255)
        mask = mask.resize((size, size), Image.LANCZOS)
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.paste(bg, (0, 0), mask)
        return out
    return bg


def wordmark(height, with_scale=True, color=(255, 255, 255, 255), white_bar=False):
    """TUNR + frequentieschaal (verloop) met naald, op transparant."""
    fs = int(height * 0.72 * SS)
    font = ImageFont.truetype(FONT, fs)
    text = "TUNR"
    tmp = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    bbox = tmp.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    W = int(tw + fs * 0.1); H = int(height * SS)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text(((W - tw) / 2 - bbox[0], -bbox[1] + fs * 0.02), text, font=font, fill=color)
    if with_scale:
        y = th + fs * 0.26
        bar_h = max(SS * 2, fs * 0.075)
        x0, x1 = fs * 0.06, W - fs * 0.06
        bar = (Image.new("RGBA", (max(2, int(x1 - x0)), max(2, int(bar_h))), (255, 255, 255, 255)) if white_bar
               else fast_gradient(max(2, int(x1 - x0)), max(2, int(bar_h))).convert("RGBA"))
        m = Image.new("L", bar.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, bar.size[0] - 1, bar.size[1] - 1], radius=bar.size[1] / 2, fill=255)
        img.paste(bar, (int(x0), int(y - bar_h / 2)), m)
        for i in range(9):
            x = x0 + (x1 - x0) * (i + 0.5) / 9
            th2 = fs * (0.09 if i % 2 == 0 else 0.055)
            tw2 = fs * 0.022
            d.rounded_rectangle([x - tw2 / 2, y - bar_h / 2 - th2 - fs * 0.02, x + tw2 / 2, y - bar_h / 2 - fs * 0.02],
                                radius=tw2 / 2, fill=(255, 255, 255, 150))
        nx = x0 + (x1 - x0) * 0.6; nw = fs * 0.035
        d.rounded_rectangle([nx - nw / 2, y - fs * 0.15, nx + nw / 2, y + fs * 0.09], radius=nw / 2, fill=(BG + (235,)) if white_bar else (ACCENT2 + (255,)))
    img = img.resize((max(1, W // SS), max(1, H // SS)), Image.LANCZOS)
    return img


def save(img, path):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def write_json(path, data):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


INFO = {"author": "xcode", "version": 1}


def accent_color(catalog):
    write_json(catalog / "AccentColor.colorset/Contents.json", {
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": f"{ACCENT[0] / 255:.3f}", "green": f"{ACCENT[1] / 255:.3f}", "blue": f"{ACCENT[2] / 255:.3f}", "alpha": "1.000"}}}],
        "info": INFO})
    write_json(catalog / "Contents.json", {"info": INFO})


def mac_icon(size):
    """macOS-stijl: afgeronde tegel op 824/1024 met marge en zachte schaduw."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = int(size * 824 / 1024)
    tile = app_icon(inner, rounded=True)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    ImageDraw.Draw(shadow).rounded_rectangle([off, off + size * 0.012, off + inner, off + inner + size * 0.012],
                                            radius=inner * 0.2237, fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(max(1, size * 0.01))))
    canvas.alpha_composite(tile, (off, off))
    return canvas


def apple():
    # één asset-catalogus voor het multiplatform-target (iPhone, iPad, Mac, Apple TV)
    cat = root / "apple/Shared/Assets.xcassets"
    accent_color(cat)
    images = [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]
    save(app_icon(1024).convert("RGB"), cat / "AppIcon.appiconset/icon-1024.png")  # App Store: geen transparantie
    for pt in (16, 32, 128, 256, 512):
        for sc in (1, 2):
            fn = f"mac-{pt}@{sc}x.png"
            save(mac_icon(pt * sc), cat / "AppIcon.appiconset" / fn)
            images.append({"filename": fn, "idiom": "mac", "scale": f"{sc}x", "size": f"{pt}x{pt}"})
    write_json(cat / "AppIcon.appiconset/Contents.json", {"images": images, "info": INFO})
    # logo in de app (o.a. Over-scherm)
    save(app_icon(512, rounded=True), cat / "TunrIcon.imageset/icon.png")
    write_json(cat / "TunrIcon.imageset/Contents.json", {"images": [{"filename": "icon.png", "idiom": "universal"}], "info": INFO})
    # CarPlay-icoon in lijsten zonder logo
    save(symbol(180, scale_bar=False), cat / "TunrSymbol.imageset/symbol.png")
    write_json(cat / "TunrSymbol.imageset/Contents.json", {"images": [{"filename": "symbol.png", "idiom": "universal"}], "info": INFO})

    brand = cat / "App Icon & Top Shelf Image.brandassets"
    write_json(brand / "Contents.json", {"assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
    ], "info": INFO})

    def tv_layers(w, h):
        back = fast_gradient(w, h)
        front = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        s = int(h * 0.86)
        front.alpha_composite(symbol(s), ((w - s) // 2, (h - s) // 2 + int(h * 0.03)))
        return back, front

    for stack, scales in (("App Icon - App Store.imagestack", {"1x": (1280, 768)}),
                          ("App Icon.imagestack", {"1x": (400, 240), "2x": (800, 480)})):
        write_json(brand / stack / "Contents.json", {"layers": [{"filename": "Front.imagestacklayer"},
                                                                 {"filename": "Back.imagestacklayer"}], "info": INFO})
        for layer in ("Front", "Back"):
            write_json(brand / stack / f"{layer}.imagestacklayer/Contents.json", {"info": INFO})
            write_json(brand / stack / f"{layer}.imagestacklayer/Content.imageset/Contents.json", {
                "images": [{"filename": f"{layer.lower()}@{sc}.png", "idiom": "tv", "scale": sc} for sc in scales],
                "info": INFO})
        for sc, (w, h) in scales.items():
            back, front = tv_layers(w, h)
            save(back, brand / stack / f"Back.imagestacklayer/Content.imageset/back@{sc}.png")
            save(front, brand / stack / f"Front.imagestacklayer/Content.imageset/front@{sc}.png")

    for name, (w, h) in (("Top Shelf Image.imageset", (1920, 720)), ("Top Shelf Image Wide.imageset", (2320, 720))):
        write_json(brand / name / "Contents.json", {"images": [
            {"filename": "topshelf@1x.png", "idiom": "tv", "scale": "1x"},
            {"filename": "topshelf@2x.png", "idiom": "tv", "scale": "2x"}], "info": INFO})
        for sc, f in (("1x", 1), ("2x", 2)):
            save(top_shelf(w * f, h * f), brand / name / f"topshelf@{sc}.png")


def top_shelf(w, h):
    img = Image.new("RGBA", (w, h), BG + (255,))
    # zachte gloed in accentkleur
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([w * 0.25, h * 0.1, w * 0.75, h * 1.2], fill=ACCENT + (110,))
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.18))
    img.alpha_composite(glow)
    # golfringen
    rings = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    cx, cy = w / 2, h * 0.5
    for i, r in enumerate((h * 0.42, h * 0.62, h * 0.82, h * 1.02)):
        rd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 34 - i * 6), width=max(2, h // 240))
    img.alpha_composite(rings)
    wm = wordmark(int(h * 0.36))
    img.alpha_composite(wm, ((w - wm.size[0]) // 2, int(h * 0.5 - wm.size[1] * 0.55)))
    return img.convert("RGB")


def android():
    res = root / "android/app/src/main/res"
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, f in dens.items():
        s = int(48 * f)
        save(app_icon(s, rounded=True), res / f"mipmap-{name}/ic_launcher.png")
        save(app_icon(s, circle=True), res / f"mipmap-{name}/ic_launcher_round.png")
        fg = int(108 * f)
        layer = Image.new("RGBA", (fg, fg), (0, 0, 0, 0))
        sym = symbol(int(fg * 0.62))
        layer.alpha_composite(sym, ((fg - sym.size[0]) // 2, (fg - sym.size[1]) // 2))
        save(layer, res / f"mipmap-{name}/ic_launcher_foreground.png")
    adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_gradient" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""
    for nm in ("ic_launcher", "ic_launcher_round"):
        p = res / f"mipmap-anydpi-v26/{nm}.xml"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(adaptive)
    (res / "drawable").mkdir(parents=True, exist_ok=True)
    (res / "drawable/ic_launcher_gradient.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<!-- achtergrond van het adaptieve icoon: accent -> accent2 (zie docs/SPEC.md) -->
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient android:angle="315" android:startColor="#FF5A1F" android:endColor="#FFB020" />
</shape>
""")
    # Android TV-banner (320x180, drawable-xhdpi)
    w, h = 320, 180
    b = fast_gradient(w, h).convert("RGBA")
    sym = symbol(int(h * 0.62), scale_bar=False)
    b.alpha_composite(sym, (int(w * 0.08), (h - sym.size[1]) // 2))
    wm = wordmark(int(h * 0.36), white_bar=True)
    b.alpha_composite(wm, (int(w * 0.08) + sym.size[0] + int(w * 0.03), (h - wm.size[1]) // 2 + 4))
    save(b.convert("RGB"), res / "drawable-xhdpi/tv_banner.png")
    # splash-scherm van Android 12+ gebruikt het icoon; los symbool voor in de app
    save(symbol(288), res / "drawable-nodpi/tunr_symbol.png")


def web():
    site = root / "website"
    save(app_icon(64, rounded=True), site / "favicon.png")
    save(app_icon(180).convert("RGB"), site / "apple-touch-icon.png")
    save(app_icon(192), site / "assets/img/icon-192.png")
    save(app_icon(512), site / "assets/img/icon-512.png")
    save(app_icon(512, rounded=True), site / "assets/img/icon-rounded.png")
    # og-image
    w, h = 1200, 630
    og = Image.new("RGBA", (w, h), BG + (255,))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([w * 0.2, h * 0.15, w * 0.8, h * 1.25], fill=ACCENT + (120,))
    og.alpha_composite(glow.filter(ImageFilter.GaussianBlur(110)))
    rings = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    for i, r in enumerate((180, 280, 380, 480)):
        rd.ellipse([w / 2 - r, h * 0.42 - r, w / 2 + r, h * 0.42 + r], outline=(255, 255, 255, 36 - i * 7), width=3)
    og.alpha_composite(rings)
    d = ImageDraw.Draw(og)
    wm = wordmark(200)
    og.alpha_composite(wm, ((w - wm.size[0]) // 2, int(h * 0.42 - wm.size[1] * 0.55)))
    font = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-SemiBold.otf", 34)
    tag = "Every radio station in the world. On every screen."
    tb = d.textbbox((0, 0), tag, font=font)
    d.text(((w - (tb[2] - tb[0])) / 2, h * 0.8), tag, font=font, fill=(230, 230, 236, 255))
    save(og.convert("RGB"), site / "assets/img/og-image.png")
    save(wordmark(120), site / "assets/img/wordmark.png")


def docs():
    save(app_icon(256, rounded=True), root / "docs/brand/icon.png")
    wm = wordmark(140)
    pad = Image.new("RGBA", (wm.size[0] + 80, wm.size[1] + 60), BG + (255,))
    pad.alpha_composite(wm, (40, 30))
    save(pad, root / "docs/brand/wordmark.png")
    presskit_brand()


def presskit_brand():
    """Woordmerk in hoge resolutie voor de presskit (tools/make_presskit.py): wit op transparant en op donker."""
    wm = wordmark(480)
    wm = wm.crop(wm.getbbox())  # strak om het woordmerk (geen lege rand onder de schaal)
    save(wm, root / "docs/brand/wordmark-white.png")
    pad = Image.new("RGBA", (wm.size[0] + 320, wm.size[1] + 280), BG + (255,))
    pad.alpha_composite(wm, (160, 140))
    save(pad.convert("RGB"), root / "docs/brand/wordmark-dark.png")


if __name__ == "__main__":
    apple(); android(); web(); docs()
    print("ok")

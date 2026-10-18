#!/usr/bin/env python3
"""App Store Connect promo-afbeeldingen (Header en Search Results) voor Tunr, Engels.

Formaten (App Store Connect, product page / in-app events / search):
  Header:          5244 × 2950, 3840 × 1646
  Search Results:  5244 × 2950, 3840 × 2560, 1920 × 1280
Bronnen: app-icoon (appstore/en/icon-1024.png of apple/Shared/Assets.xcassets), echte iPhone-schermafbeeldingen
(appstore/en/raw/iphone69-*.png) en de vaste zenderlogo's van de hero (website/assets/img/wall/*.webp).
Gebruik: python3 tools/make_appstore_promo.py --media <map met appstore/en> --out <uitvoermap>
Alle PNG's zonder alfakanaal (eis van Apple). Belangrijke inhoud blijft in het midden (veilige zone).
"""
import argparse, glob, math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = (10, 10, 12)
ORANGE = (255, 90, 31)
AMBER = (255, 176, 32)
FONT_DIR = '/usr/share/fonts/opentype/inter'


def font(weight, size):
    for name in (f'Inter-{weight}.otf', f'InterDisplay-{weight}.otf', 'Inter-Bold.otf'):
        p = os.path.join(FONT_DIR, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', size)


def rounded(im, r):
    m = Image.new('L', im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, im.width - 1, im.height - 1), r, fill=255)
    out = Image.new('RGBA', im.size)
    out.paste(im.convert('RGBA'), (0, 0), m)
    return out


def gradient_h(w, h, c1, c2):
    g = Image.new('RGB', (w, 1))
    for x in range(w):
        t = x / max(1, w - 1)
        g.putpixel((x, 0), tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    return g.resize((w, h))


def glow(w, h, cx, cy, r, color, alpha):
    layer = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(r * 0.55))


def logo_wall(w, h, tile, logos, opacity):
    """Gekantelde muur van zenderlogo's zoals de hero van tunr.online, gedimd."""
    big = int(math.hypot(w, h)) + tile * 2
    wall = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    gap = int(tile * 0.18)
    rnd = random.Random(7)
    i = 0
    for col, x in enumerate(range(0, big, tile + gap)):
        off = (col % 3) * tile // 3
        for y in range(-tile + off, big, tile + gap):
            lg = logos[i % len(logos)]; i += 1
            t = rounded(lg.resize((tile, tile), Image.LANCZOS), int(tile * 0.22))
            wall.alpha_composite(t, (x, y))
    rnd.shuffle(logos)
    wall = wall.rotate(-12, resample=Image.BICUBIC)
    cx, cy = wall.width // 2, wall.height // 2
    wall = wall.crop((cx - w // 2, cy - h // 2, cx - w // 2 + w, cy - h // 2 + h))
    a = wall.getchannel('A').point(lambda v: int(v * opacity))
    wall.putalpha(a)
    return wall


def phone(shot, height):
    """iPhone-achtig kader om een echte schermafbeelding."""
    s = shot.convert('RGB')
    w = int(height * s.width / s.height)
    s = s.resize((w, height), Image.LANCZOS)
    bezel = int(height * 0.022)
    frame = Image.new('RGBA', (w + bezel * 2, height + bezel * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    R = int(height * 0.075)
    d.rounded_rectangle((0, 0, frame.width - 1, frame.height - 1), R + bezel, fill=(28, 28, 32, 255))
    d.rounded_rectangle((2, 2, frame.width - 3, frame.height - 3), R + bezel - 2, outline=(70, 70, 78, 255), width=3)
    frame.alpha_composite(rounded(s, R), (bezel, bezel))
    return frame


def shadowed(layer, blur, opacity=150):
    sh = Image.new('RGBA', (layer.width + blur * 4, layer.height + blur * 4), (0, 0, 0, 0))
    a = layer.getchannel('A').point(lambda v: min(opacity, v))
    sh.paste((0, 0, 0, 255), (blur * 2, blur * 2 + blur // 2), a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    sh.alpha_composite(layer, (blur * 2, blur * 2))
    return sh


def wordmark(height):
    """"TUNR" met de frequentieschaal en naald eronder (zoals het logo)."""
    f = font('Black', height)
    tw = int(f.getlength('TUNR'))
    th = int(height * 1.42)
    im = Image.new('RGBA', (tw + 4, th), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.text((0, -int(height * 0.12)), 'TUNR', font=f, fill=(255, 255, 255, 255))
    bar_y = int(height * 1.08)
    bar_h = max(6, int(height * 0.09))
    bar = gradient_h(tw, bar_h, ORANGE, AMBER)
    m = Image.new('L', (tw, bar_h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, tw - 1, bar_h - 1), bar_h // 2, fill=255)
    im.paste(bar, (0, bar_y), m)
    for k in range(9):
        x = int(tw * (0.04 + k * 0.115))
        tall = k % 2 == 0
        d.line((x, bar_y - int(height * (0.16 if tall else 0.09)), x, bar_y - int(height * 0.03)),
               fill=(255, 255, 255, 140), width=max(2, height // 40))
    nx = int(tw * 0.585)
    d.line((nx, bar_y - int(height * 0.22), nx, bar_y + bar_h + int(height * 0.08)), fill=AMBER + (255,), width=max(3, height // 22))
    return im


def text_block(w_max, headline_px, lines_head, sub, sub_px):
    fh = font('Black', headline_px)
    fs = font('Medium', sub_px)
    lh = int(headline_px * 1.08)
    heights = len(lines_head) * lh + int(sub_px * 0.9) + int(sub_px * 1.4)
    im = Image.new('RGBA', (w_max, heights + sub_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    y = 0
    for i, line in enumerate(lines_head):
        if i == len(lines_head) - 1:
            # laatste regel in het oranje verloop
            tw = int(fh.getlength(line))
            m = Image.new('L', (tw + 10, lh + headline_px // 3), 0)
            ImageDraw.Draw(m).text((0, -int(headline_px * 0.1)), line, font=fh, fill=255)
            g = gradient_h(m.width, m.height, ORANGE, AMBER)
            im.paste(g, (0, y), m)
        else:
            d.text((0, y - int(headline_px * 0.1)), line, font=fh, fill=(255, 255, 255, 255))
        y += lh
    y += int(sub_px * 0.9)
    d.text((0, y), sub, font=fs, fill=(196, 196, 206, 255))
    return im


def compose(W, H, kind, icon, shots, logos):
    canvas = Image.new('RGBA', (W, H), BG + (255,))
    s = min(W / 3840, H / 2160) if kind == 'header' else min(W / 3840, H / 2560)
    canvas.alpha_composite(logo_wall(W, H, int(260 * s * (1.25 if kind == 'header' else 1.0)), logos, 0.20))
    # donkere vignet links (leesbaarheid) en gloed
    vig = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vig)
    for i in range(60):
        t = i / 60
        vd.rectangle((0, 0, int(W * (0.62 - 0.3 * t)), H), fill=BG + (int(12 * (1 - t) ** 0.6 + 3),))
    canvas.alpha_composite(vig.filter(ImageFilter.GaussianBlur(int(80 * s))))
    canvas.alpha_composite(glow(W, H, int(W * 0.70), int(H * 0.42), int(900 * s), ORANGE, 120))
    canvas.alpha_composite(glow(W, H, int(W * 0.18), int(H * 0.85), int(700 * s), AMBER, 50))

    wide = W / H > 2.0
    # telefoons rechts (2 of 3), echte schermafbeeldingen
    ph = int(H * (0.80 if wide else 0.64))
    phones = [phone(sh, ph) for sh in shots[:3]]
    if wide and len(phones) >= 3:
        order = [(phones[1], -8, 0.62, 0.10), (phones[2], 8, 0.84, 0.10), (phones[0], 0, 0.73, 0.06)]
    else:
        order = [(phones[1], -7, 0.62 if wide else 0.70, 0.22 if not wide else 0.10),
                 (phones[0], 4, 0.80 if wide else 0.865, 0.17 if not wide else 0.07)]
    for p, ang, cxr, top in order:
        rp = shadowed(p, int(40 * s)).rotate(ang, resample=Image.BICUBIC, expand=True)
        x = int(W * cxr - rp.width / 2)
        y = int(H * top) - int(80 * s)
        canvas.alpha_composite(rp, (x, y))

    # links: icoon + woordmerk + kop
    left = int(W * (0.075 if wide else 0.07))
    ic_px = int(330 * s * (1.1 if wide else 1.0))
    ic = rounded(icon.convert('RGB').resize((ic_px, ic_px), Image.LANCZOS), int(ic_px * 0.225))
    wm = wordmark(int(150 * s * (1.1 if wide else 1.0)))
    head_px = int((230 if wide else 165) * s)
    sub_px = int((86 if wide else 66) * s)
    tb = text_block(int(W * 0.5), head_px, ['Every radio station', 'in the world.', 'On every screen.'],
                    'Radio & podcasts from 200+ countries', sub_px)
    total_h = ic_px + int(70 * s) + tb.height
    y0 = (H - total_h) // 2 + int(20 * s)
    canvas.alpha_composite(shadowed(ic, int(30 * s), 120), (left - int(60 * s), y0 - int(60 * s)))
    canvas.alpha_composite(wm, (left + ic_px + int(60 * s), y0 + (ic_px - wm.height) // 2 + int(10 * s)))
    canvas.alpha_composite(tb, (left, y0 + ic_px + int(80 * s)))
    return canvas.convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--media', required=True, help='map met appstore/en (icon-1024.png en raw/)')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    en = os.path.join(a.media, 'appstore', 'en')
    icon = Image.open(os.path.join(en, 'icon-1024.png'))
    shots = [Image.open(os.path.join(en, 'raw', f'iphone69-{n}.png')) for n in ('discover', 'player', 'library')]
    logos = [Image.open(f).convert('RGB') for f in sorted(glob.glob(os.path.join(ROOT, 'website/assets/img/wall/*.webp')))]
    os.makedirs(a.out, exist_ok=True)
    jobs = [('header', 5244, 2950), ('header', 3840, 1646),
            ('search-results', 5244, 2950), ('search-results', 3840, 2560), ('search-results', 1920, 1280)]
    for kind, w, h in jobs:
        im = compose(w, h, 'header' if kind == 'header' else 'search', icon, shots, logos)
        assert im.size == (w, h) and im.mode == 'RGB'
        p = os.path.join(a.out, f'{kind}-{w}x{h}.png')
        im.save(p, optimize=True)
        print(p, im.size)


if __name__ == '__main__':
    main()

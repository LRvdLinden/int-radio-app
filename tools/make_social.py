#!/usr/bin/env python3
"""Social-media-banners voor Tunr (NL + EN) uit de echte app-screenshots van tunr.online (website/assets/img/<taal>/).

    python3 tools/make_social.py [datum]   → social/tunr-<datum>/<nl|en>/<kanaal>-<formaat>.png + posts.md

HTML/CSS per formaat, gerenderd met Playwright/Chromium (deviceScaleFactor 1). Huisstijl: donker #0A0A0C, oranje
verloop #FF5A1F → #FFB020, Inter Display Black voor koppen. Geen logo's van derden behalve wat de echte app toont.
"""
import base64, datetime, pathlib, sys
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMG = ROOT / "website/assets/img"
DATE = sys.argv[1] if len(sys.argv) > 1 else datetime.date.today().isoformat()
OUT = ROOT / f"social/tunr-{DATE}"

def data_uri(p):
    p = pathlib.Path(p)
    mime = {".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".svg": "image/svg+xml"}[p.suffix]
    return f"data:{mime};base64," + base64.b64encode(p.read_bytes()).decode()

T = {
    "nl": dict(badge="Gratis · zonder account · zonder reclame",
               h1="Alle radio van de wereld.", h2="Op elk scherm.",
               sub="Tienduizenden zenders uit 200+ landen en de populairste podcasts.",
               devices="iPhone · iPad · Mac · Apple TV · Apple Watch · Android · Windows",
               cta="tunr.online", beta="Nu als beta"),
    "en": dict(badge="Free · no account · no ads",
               h1="Every radio station in the world.", h2="On every screen.",
               sub="Tens of thousands of stations from 200+ countries and the most popular podcasts.",
               devices="iPhone · iPad · Mac · Apple TV · Apple Watch · Android · Windows",
               cta="tunr.online", beta="Now in beta"),
}

CSS = """
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:%(w)dpx;height:%(h)dpx;overflow:hidden;background:#0A0A0C;color:#fff;font-family:Inter,sans-serif}
.bg{position:absolute;inset:0;background:
  radial-gradient(60%% 70%% at %(gx)s %(gy)s,rgba(255,90,31,.42),rgba(255,90,31,0) 70%%),
  radial-gradient(45%% 55%% at %(g2x)s %(g2y)s,rgba(255,176,32,.20),rgba(255,176,32,0) 70%%),#0A0A0C}
.dots{position:absolute;inset:0;background:url(%(dots)s) center/%(dotsize)s no-repeat;opacity:.16}
.brand{display:flex;align-items:center;gap:%(bgap)dpx}
.brand img{width:%(icon)dpx;height:%(icon)dpx;border-radius:22%%;box-shadow:0 10px 30px rgba(0,0,0,.45)}
.word{font-family:'Inter Display';font-weight:900;font-size:%(word)dpx;letter-spacing:.06em;line-height:1}
.word .bar{display:block;height:%(barh)dpx;margin-top:%(barm)dpx;border-radius:9px;background:linear-gradient(90deg,#FF5A1F,#FFB020)}
.badge{display:inline-block;font-weight:700;font-size:%(small)dpx;color:#FFB020;letter-spacing:.01em}
h1{font-family:'Inter Display';font-weight:900;font-size:%(h1)dpx;line-height:1.02;letter-spacing:-.02em}
h1 em{font-style:normal;background:linear-gradient(90deg,#FF5A1F,#FFB020);-webkit-background-clip:text;background-clip:text;color:transparent}
.sub{font-size:%(sub)dpx;line-height:1.35;color:#C9C9D2;font-weight:500}
.dev{font-size:%(small)dpx;color:#A8A8B3;font-weight:600}
.cta{display:inline-flex;align-items:center;gap:%(cgap)dpx;padding:%(cpy)dpx %(cpx)dpx;border-radius:999px;
  background:linear-gradient(90deg,#FF5A1F,#FFB020);color:#fff;font-weight:800;font-size:%(cta)dpx;box-shadow:0 12px 34px rgba(255,90,31,.35)}
.cta small{font-weight:700;font-size:.72em;opacity:.95;background:rgba(0,0,0,.18);padding:.18em .55em;border-radius:999px}
.phone{position:absolute;border-radius:%(pr)dpx;padding:%(pb)dpx;background:linear-gradient(145deg,#3a3a42,#16161b);
  box-shadow:0 30px 80px rgba(0,0,0,.6),0 0 0 2px rgba(255,255,255,.06)}
.phone img{display:block;width:100%%;border-radius:%(pir)dpx}
"""

def page(w, h, body, **k):
    v = dict(w=w, h=h, gx="78%", gy="55%", g2x="15%", g2y="10%", dots=data_uri(IMG / "world-dots.svg"), dotsize="120%",
             bgap=18, icon=72, word=56, barh=7, barm=8, small=26, h1=84, sub=32, cgap=14, cpy=18, cpx=30, cta=32,
             pr=58, pb=12, pir=48)
    v.update(k)
    return f"<!doctype html><html><head><meta charset=utf-8><style>{CSS % v}</style></head><body><div class=bg></div><div class=dots></div>{body}</body></html>"

def brand(t):
    return (f'<div class=brand><img src="{data_uri(IMG / "icon-rounded.png")}" alt="">'
            f'<div class=word>TUNR<span class=bar></span></div></div>')

def phone(src, left, top, width, rot=0, z=1):
    return (f'<div class=phone style="left:{left}px;top:{top}px;width:{width}px;transform:rotate({rot}deg);z-index:{z}">'
            f'<img src="{data_uri(src)}" alt=""></div>')

def cta(t, size=None):
    s = f' style="font-size:{size}px"' if size else ""
    return f'<span class=cta{s}>{t["cta"]} <small>{t["beta"]}</small></span>'

def shot(lang, name):
    return IMG / lang / f"ios_{name}.jpg"

FORMATS = []

def fmt(name, w, h):
    def deco(fn):
        FORMATS.append((name, w, h, fn)); return fn
    return deco

@fmt("instagram-facebook-post", 1080, 1080)
def post_square(t, lang):
    body = (f'<div style="position:absolute;left:72px;top:76px;width:560px;display:flex;flex-direction:column;gap:26px">'
            f'{brand(t)}<span class=badge>{t["badge"]}</span>'
            f'<h1>{t["h1"]}<br><em>{t["h2"]}</em></h1><p class=sub>{t["sub"]}</p>'
            f'<div style="margin-top:8px">{cta(t)}</div><p class=dev>{t["devices"]}</p></div>'
            + phone(shot(lang, "player"), 640, 150, 372, rot=4))
    return page(1080, 1080, body, h1=70 if lang == "en" else 74, sub=28, small=18, dotsize="140%")

@fmt("instagram-facebook-post", 1080, 1350)
def post_portrait(t, lang):
    body = (f'<div style="position:absolute;left:72px;right:72px;top:68px;display:flex;flex-direction:column;gap:22px;z-index:5">'
            f'{brand(t)}<h1>{t["h1"]}<br><em>{t["h2"]}</em></h1><p class=sub style="max-width:880px">{t["sub"]}</p>'
            f'<div style="display:flex;align-items:center;gap:22px">{cta(t)}<span class=dev>{t["badge"]}</span></div></div>'
            + phone(shot(lang, "discover"), 130, 760, 380, rot=-6)
            + phone(shot(lang, "player"), 560, 720, 400, rot=5, z=2))
    return page(1080, 1350, body, h1=72 if lang == "en" else 80, sub=30, small=22, gy="85%", gx="60%")

@fmt("story-reels", 1080, 1920)
def story(t, lang):
    # veilige zone: 250 px boven en onder vrij; de telefoons lopen onderaan het beeld uit (decoratief)
    body = (f'<div style="position:absolute;left:80px;right:80px;top:260px;display:flex;flex-direction:column;align-items:center;text-align:center;gap:26px;z-index:5">'
            f'{brand(t)}<h1>{t["h1"]}<br><em>{t["h2"]}</em></h1><p class=sub style="max-width:880px">{t["sub"]}</p>'
            f'{cta(t, 40)}<p class=dev>{t["devices"]}</p></div>'
            + phone(shot(lang, "map"), 110, 1150, 400, rot=-6)
            + phone(shot(lang, "player"), 560, 1110, 420, rot=5, z=2))
    return page(1080, 1920, body, h1=88 if lang == "en" else 96, sub=34, small=25, gy="80%", gx="50%", dotsize="170%")

@fmt("facebook-cover", 1640, 624)
def fb_cover(t, lang):
    # belangrijke inhoud in het midden (mobiel snijdt de zijkanten af)
    body = (f'<div style="position:absolute;left:250px;top:120px;width:720px;display:flex;flex-direction:column;gap:22px">'
            f'{brand(t)}<h1>{t["h1"]}<br><em>{t["h2"]}</em></h1><p class=dev>{t["devices"]}</p>'
            f'<div>{cta(t, 28)}</div></div>'
            + phone(shot(lang, "discover"), 1010, 80, 230, rot=-5)
            + phone(shot(lang, "player"), 1190, 50, 245, rot=4, z=2))
    return page(1640, 624, body, h1=58 if lang == "en" else 62, small=21, word=46, icon=60, dotsize="110%", gx="70%")

@fmt("linkedin-cover", 1584, 396)
def li_cover(t, lang):
    # profielfoto/paginalogo valt linksonder: inhoud rechts van het midden
    body = (f'<div style="position:absolute;left:520px;top:62px;width:700px;display:flex;flex-direction:column;gap:16px">'
            f'{brand(t)}<h1>{t["h1"]}<br><em>{t["h2"]}</em></h1><div>{cta(t, 24)}</div></div>'
            + phone(shot(lang, "player"), 1290, 36, 190, rot=5))
    return page(1584, 396, body, h1=44 if lang == "en" else 46, word=38, icon=50, bgap=14, barh=5, cpy=12, cpx=22,
                dotsize="100%", gx="85%", gy="50%", pr=34, pb=8, pir=28)

POSTS = {
    "nl": """# Tunr — posts (NL)

## Instagram / Facebook (post en story)
Alle radio van de wereld, op elk scherm 📻 Met Tunr luister je gratis naar tienduizenden zenders uit meer dan 200 landen en de populairste podcasts, op iPhone, iPad, Mac, Apple TV, Apple Watch, Android en Windows. Geen account, geen reclame. Probeer de beta via tunr.online.

#radio #internetradio #podcasts #app #tunr #radioluisteren

## Facebook-cover / LinkedIn-cover
Geen posttekst nodig. Beschrijving bij de cover: Tunr: alle radio van de wereld, op elk scherm. Gratis op tunr.online.

## Alt-teksten
- instagram-facebook-post-1080x1080.png: Tunr-banner met de kop "Alle radio van de wereld. Op elk scherm." en een iPhone met de speler van Tunr die een zender live afspeelt. Onderaan tunr.online, nu als beta.
- instagram-facebook-post-1080x1350.png: Tunr-banner met dezelfde kop en twee iPhones: het scherm Ontdek met populaire zenders en de speler. Onderaan tunr.online en "Gratis, zonder account, zonder reclame".
- story-reels-1080x1920.png: Staande Tunr-banner met de kop, twee iPhones met de wereldkaart en de speler, en onderaan tunr.online en de apparaten waarop Tunr werkt.
- facebook-cover-1640x624.png: Brede Tunr-banner met logo, kop "Alle radio van de wereld. Op elk scherm.", de lijst met apparaten en twee iPhones met de app.
- linkedin-cover-1584x396.png: Smalle Tunr-banner met logo, kop en tunr.online, met rechts een iPhone met de speler.
""",
    "en": """# Tunr — posts (EN)

## Instagram / Facebook (post and story)
Every radio station in the world, on every screen 📻 With Tunr you can listen for free to tens of thousands of stations from more than 200 countries and the most popular podcasts, on iPhone, iPad, Mac, Apple TV, Apple Watch, Android and Windows. No account, no ads. Try the beta at tunr.online.

#radio #internetradio #podcasts #app #tunr #onlineradio

## Facebook cover / LinkedIn cover
No post text needed. Cover description: Tunr: every radio station in the world, on every screen. Free at tunr.online.

## Alt texts
- instagram-facebook-post-1080x1080.png: Tunr banner with the headline "Every radio station in the world. On every screen." and an iPhone showing the Tunr player playing a station live. At the bottom tunr.online, now in beta.
- instagram-facebook-post-1080x1350.png: Tunr banner with the same headline and two iPhones: the Discover screen with popular stations and the player. At the bottom tunr.online and "Free, no account, no ads".
- story-reels-1080x1920.png: Vertical Tunr banner with the headline, two iPhones showing the world map and the player, and at the bottom tunr.online and the devices Tunr runs on.
- facebook-cover-1640x624.png: Wide Tunr banner with the logo, the headline "Every radio station in the world. On every screen.", the list of devices and two iPhones with the app.
- linkedin-cover-1584x396.png: Narrow Tunr banner with the logo, headline and tunr.online, with an iPhone showing the player on the right.
""",
}

def main():
    with sync_playwright() as pw:
        b = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium") if pathlib.Path("/opt/pw-browsers/chromium").exists() else pw.chromium.launch()
        for lang, t in T.items():
            d = OUT / lang; d.mkdir(parents=True, exist_ok=True)
            for name, w, h, fn in FORMATS:
                p = b.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
                p.set_content(fn(t, lang)); p.wait_for_timeout(300)
                p.screenshot(path=str(d / f"{name}-{w}x{h}.png")); p.close()
                print(lang, name, w, h)
            (d / "posts.md").write_text(POSTS[lang])
        b.close()

if __name__ == "__main__":
    main()

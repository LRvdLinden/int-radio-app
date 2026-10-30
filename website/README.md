# tunr.online

De website van **Tunr**, de gratis app voor radio en podcasts uit de hele wereld, voor iPhone, iPad, Mac, Apple TV, CarPlay, Android, Android TV / Google TV / Fire TV, Android Auto en de browser. De site is er in het Nederlands en het Engels.

- Alle apps (Apple, Android) en deze site staan in één repo: [LRvdLinden/int-radio-app](https://github.com/LRvdLinden/int-radio-app)
- Wat er nieuw is per build: [tunr.online/changelog](https://tunr.online/changelog/)
- Functionele spec en huisstijl: `docs/SPEC.md`

## /web: Tunr in je browser

Op [tunr.online/web](https://tunr.online/web/) luister je zonder iets te installeren, in Chrome, Safari, Edge of Firefox, op je computer, iPad of telefoon. Geen account nodig.

- **Zelfde schermen als de apps**: Ontdek, Bladeren, Kaart, Zoeken en Bibliotheek, met een miniplayer en een speler op volledig scherm.
- **Radio**: zenders uit [Radio Browser](https://www.radio-browser.info) (open community-database, zonder sleutel): populair, trending, lokaal (provincie of staat), op genre, op taal, de Top 100 wereldwijd en een wereldkaart (Leaflet + CARTO-tegels).
- **Podcasts**: toplijst per land (Apple-toplijsten), genres, zoeken (iTunes Search API), podcastpagina met Volgen en afleveringen, afleveringspagina. Speler met tijdbalk, 15 s terug / 30 s vooruit, snelheid 0,8×–2× en slaaptimer tot het einde van de aflevering. Lukt `fetch` naar iTunes niet door CORS, dan gebruikt de speler JSONP.
- **Alles lokaal**: land, favorieten, recent, gevolgde podcasts en luisterposities staan in `localStorage` van je eigen browser.
- **Media Session**: bediening op het vergrendelscherm en met mediatoetsen; bij afleveringen ook spoelen.
- **Sneltoetsen**: spatie (afspelen/pauze), ← → (15 s terug / 30 s vooruit bij een aflevering), Esc (speler of venster sluiten).
- Zenders en afleveringen die alleen via http streamen, blokkeert de browser op een https-pagina; de speler zegt dan dat ze alleen in de app werken.
- `web/` is de verborgen webspeler: geen links ernaartoe op de site, niet in de changelog, `noindex`, niet in de sitemap.

## Functies van de site

- **Home** ([tunr.online](https://tunr.online)): uitleg over Tunr, screenshots per apparaat (WebP met JPG als terugval, per taal in `assets/img/nl` en `assets/img/en`), podcasts, de wereldkaart, downloads (nog *Coming Soon*) en veelgestelde vragen.
- **Changelog** ([/changelog](https://tunr.online/changelog/)): wat er nieuw is per build, uitklapbaar en te filteren per platform. Leest `assets/changelog.json`, gemaakt door `python3 tools/make_changelog.py` uit `docs/changelog.json`.
- **Privacy** ([/privacy](https://tunr.online/privacy/)) en **Voorwaarden** ([/voorwaarden](https://tunr.online/voorwaarden/)).
- **404** (`404.html`, alle paden absoluut) voor onbekende adressen.
- De footer toont de versie en de nieuwste build (`<span data-build>`): een vaste waarde in de HTML, en `assets/js/home.js` zet daar het hoogste buildnummer uit de changelog neer als dat hoger is.
- Overal Nederlands en Engels: volgt de taal van je browser, of kies zelf (NL/EN rechtsboven; `?lang=nl` en `?lang=en` gaan voor). Teksten: NL in de HTML, EN in `window.TUNR_I18N` per pagina en in `assets/js/i18n.js`.

## SEO

Per pagina hreflang-links voor `?lang=nl`, `?lang=en` en x-default; de canonical zet `assets/js/i18n.js` (de x-default-URL plus `?lang=`). `sitemap.xml` heeft per pagina dezelfde drie URL's, `robots.txt` verwijst ernaar.

## Naam en domein

"Tunr" is een werknaam. De naam, het domein en de repo staan in `assets/js/brand.js`, plus `sitemap.xml`, `robots.txt` en de hreflang-links; zoek-en-vervang op `Tunr` en `tunr.online` volstaat.

## Publiceren

De workflow *Website* (`.github/workflows/website.yml`) zet `website/` via FTPS op de webserver bij elke push naar `main` die `website/` raakt, of met de hand. Secrets: `FTP_SERVER`, `FTP_USERNAME`, `FTP_PASSWORD` (optioneel `FTP_DIR`). Zonder secrets slaat hij de upload over.

Lokaal bekijken:

```sh
cd website && python3 -m http.server 8000
# http://localhost:8000/ en http://localhost:8000/web/
```

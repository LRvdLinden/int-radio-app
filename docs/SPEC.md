# Tunr — functionele spec en huisstijl

Eén product op alle schermen: **iPhone, iPad, Mac, Apple TV, CarPlay, Android (telefoon/tablet), Android TV, Android Auto, Windows**. (De webspeler is om rechtenredenen offline; de website speelt niets af.) Alle platforms hebben dezelfde functies, schermen, volgorde en teksten (NL + EN; standaard de taal van het toestel, Engels als terugval).

---


> Logoweergave (build 22): grote logo's (kleinste zijde ≥ 0,75 × tegel of ≥ 160 px) vullen de tegel; kleine logo's staan gecentreerd, aspect-fit, max. 2× hun eigen pixelgrootte en max. 62% van de tegel, op een effen achtergrond uit het logo (gemiddelde randkleur als de rand dekkend is, anders wit of #16161A). Verloop + letters alleen zonder logo.

## 1. Huisstijl

| Token | Waarde | Gebruik |
|---|---|---|
| `bg` | `#0A0A0C` | achtergrond |
| `surface` | `#16161A` | kaarten, lijsten |
| `elevated` | `#202026` | sheets, focus-achtergrond |
| `stroke` | `#FFFFFF14` | 1px randen |
| `text` | `#FFFFFF` | primaire tekst |
| `secondary` | `#A8A8B3` | secundaire tekst |
| `accent` | `#FF5A1F` | "On Air"-oranje: knoppen, actieve tab, voortgang, equalizer |
| `accent2` | `#FFB020` | amber: verloop met accent (`accent → accent2`, 135°) |
| `live` | `#FF3B30` | LIVE-bolletje |

- Altijd donker (geen licht thema).
- Lettertype: systeem (SF Pro / Roboto / system-ui). Koppen **heavy/black**, afgerond (SF Rounded; op Android `FontWeight.Black`).
- Afronding: kaarten 14 px (tv 20), knoppen 12, chips volledig rond.
- **Wordmark**: `TUNR` in heavy rounded, wit, met eronder een **frequentieschaal**: een dunne balk in het accentverloop met 9 korte maatstreepjes en een klein **naaldje** (accent2) iets rechts van het midden. Component heet overal `TunrLogo`.
- Zendercover ("StationArt"): vierkant. Achtergrond = verloop van twee kleuren afgeleid van een hash van de zendernaam (palet hieronder), daarop het logo (zie Logo-bronnen hieronder) gecentreerd op 62% met 8% binnenmarge op een witte, afgeronde tegel als het logo transparant/klein is; geen logo of laden mislukt → **monogram** (eerste 1–2 letters, heavy rounded, wit). Paletten (begin, eind):
  `#FF5A1F→#FFB020`, `#7C3AED→#DB2777`, `#0EA5E9→#22D3EE`, `#10B981→#84CC16`, `#F43F5E→#FB923C`, `#6366F1→#06B6D4`, `#EAB308→#F97316`, `#14B8A6→#3B82F6`.
- Equalizer-animatie (4 staafjes, accent) bij de zender die nu speelt — in kaarten, lijsten, miniplayer.
- **Logo-bronnen** (zo veel mogelijk mooie, echte zendericonen; ook als de zender in Radio Browser een favicon heeft), in volgorde; één helper per platform (Apple `LogoSources`/`IconMap`/`LogoResolver` in `PlatformSupport.swift`, Android `data/LogoSources.kt` + `data/IconMap.kt`, web `T.logoCandidates(s)`/`T.iconFor(s)` in `strings.js`):
  1. **App-icoon** uit de vaste tabel van tunr.online: `https://tunr.online/assets/data/icons/<CC>.json` (land van de zender, `countrycode`; zonder land `_world.json`) = `{"u": {stationuuid: url}, "n": {naamsleutel: url}}`, url altijd https. Bronnen (workflow *Icons*), samengevoegd door `tools/merge_icon_tables.py` (voorrang op host van de URL): bij voorkeur het **App Store-icoon** (mzstatic-PNG van 256 px; via de iTunes-zoekfunctie in `tools/make_station_icons.py`, of exact via de App Store-link op de website van de zender), anders het **Google Play-icoon** (`play-lh.googleusercontent.com/…=s256`; via de Play-link op de website van de zender of de Play-zoekfunctie, `tools/store_icons.py`), anders het **app-icoon van de eigen website van de zender** (`tools/make_site_icons.py`: grootste vierkante icoon ≥ 192 px uit het web-app-manifest, anders `apple-touch-icon`, `<link rel=icon sizes=…>` ≥ 192 of een vierkante `og:image`, anders `/apple-touch-icon.png` in de root; gecontroleerd: PNG/JPEG/WebP, verhouding 0,85–1,18, ≥ 128 px, niet effen, geen standaardicoon van een CMS of platform). Een App Store-icoon wordt nooit door een Play- of website-icoon vervangen, een Play-icoon nooit door een website-icoon, en er verdwijnt niets uit de tabel. Opzoeken op uuid, anders op naamsleutel. Naamsleutel overal gelijk (`norm_key` in `tools/make_station_icons.py`): NFKD, combinerende tekens (Mn) weg, kleine letters, alleen letters (L*) en decimale cijfers (Nd). De tabel wordt per land pas geladen als een zender uit dat land getoond wordt (één verzoek tegelijk), en bewaard in het geheugen + 7 dagen op schijf (Apple `Caches/icons`, Android `cacheDir/icons`, web `localStorage` `tunr.icons:<CC>`); 404 = leeg land (alleen deze sessie; web 1 dag); mislukt = 10 minuten niet opnieuw (oude kopie gebruiken als die er is). De apps/webspeler vragen iTunes hiervoor nooit zelf (limiet ~20 per minuut per IP);
  2. domein van `homepage` via Google: `https://www.google.com/s2/favicons?domain=<host>&sz=256`, alleen als het resultaat **minstens 96 px** breed is (dan is het meestal het apple-touch-icon van de site);
  3. `favicon` uit Radio Browser (http → eerst https; Apple/Android proberen daarna het originele http-adres), vanaf **48 px**;
  4. `https://icons.duckduckgo.com/ip3/<host>.ico`, vanaf 48 px;
  5. anders het monogram. Een klein favicon of app-icoon (< 48 px) wordt alleen gebruikt als niets anders werkt; van de diensten (2, 4) nooit.
  Het logo vult de hele tegel (Apple `.fill`, Android `ContentScale.Crop`, web `object-fit: cover`), want app-iconen zijn vierkant. Mislukte URL's en het gevonden logo per zender worden in het geheugen onthouden (afbeeldingen zelf in de bestaande beeldcache: Apple URLCache, Android Coil-schijfcache), zodat er bij scrollen niet steeds opnieuw geprobeerd wordt. Apple en Android wachten met kiezen tot de tabel van het land er is (of mislukte), zodat het App Store-icoon voorgaat; de webspeler wacht bij het laden van een zenderlijst max. 1,5 s op de tabel en maakt covers die al getekend waren opnieuw zodra de tabel binnenkomt. Geldt ook voor CarPlay, widgets en Live Activity (verkleinde logo's), Now Playing, de mediasessie en Android Auto (Android Auto laadt eerst de tabellen van de getoonde lijst). Eigen User-Agent niet naar de favicondiensten; web met `referrerpolicy="no-referrer"`. Vermeld in de privacyverklaring (tunr.online, mzstatic.com, play-lh.googleusercontent.com, websites van zenders, Google, DuckDuckGo).
  **De tabel maken** (workflow *Icons*, wekelijks + met de hand): `tools/make_station_icons.py` haalt populaire zenders uit Radio Browser (top 150 van de 60 landen met de meeste zenders + top 2000 wereldwijd, op clickcount, ontdubbeld op naamsleutel per land) en zoekt per naam `https://itunes.apple.com/search?term=<naam>&entity=software&country=<cc>&limit=8` (daarna de store `us`), ~3,2 s tussen verzoeken, tijdsbudget 330 min. Een app telt alleen bij een zekere match (`match_app`, getest in `tools/test_station_icons.py`): genre Music/Entertainment/News/Sports/Lifestyle/Reference/Education; exact dezelfde naam of kernnaam (zonder radio/fm/live/online/stream/app, frequenties, leestekens, accenten) wint; anders kernnaam in de appnaam (of andersom als die niet veel korter is) of ≥ 0,8 Jaccard op de kernwoorden, met bonus als het domein van de uitgever bij de homepage past; algemene namen ("Radio 1", "Jazz Radio") alleen exact, in de store van het eigen land en als de uitgever bij de zender hoort; "Radio 538"-achtige namen (3+ cijfers) exact in de eigen store. Icoon: `artworkUrl512` met `/512x512bb.jpg` → `/256x256bb.png`. Cache (naam+land → icoon of "niets" + datum) op de branch `icons-data`: elke run gaat verder waar de vorige stopte; missers na 90 dagen en treffers na 180 dagen opnieuw. De workflow commit `website/assets/data/icons/` naar main (`[skip ci]`) en start daarna de workflow *Website*. Daarnaast (eigen job `site-icons`, parallel, ~40 min, invoer `source` = `all`/`appstore`/`site`) haalt `tools/make_site_icons.py` voor de top 300 van 80 landen + top 3000 wereldwijd per website-host het app-icoon van de site (32 threads, max. 1 verzoek tegelijk per host, 10 s, HTML max. 1,5 MB, icoon max. 2 MB, User-Agent `Mozilla/5.0 (compatible; TunrIconBot/1.0; +https://tunr.online)`; platforms/sociale media/verzamelsites en hosts met meer dan 5 zendernamen overgeslagen; alleen https, http alleen als het https-adres ook klopt; een vingerafdruk die bij ≥ 4 sites zonder gemeenschappelijke naam voorkomt geldt als standaardicoon). Cache per host `site-cache.json` op `icons-data` (treffers na 120, missers na 60 dagen opnieuw; met de gevonden store-links). In dezelfde job daarna `tools/store_icons.py` (tijdsbudget `site_budget`, standaard 46 min, verdeeld 55 % websites / 18 % store-links / 27 % Play-zoeken): **store-links** op de homepage van de zender (`<meta name="apple-itunes-app" content="app-id=…">`, links naar `apps.apple.com/…/id…`, `<meta name="google-play-app">`, `play.google.com/store/apps/details?id=…`, `market://details?id=…`, `<link rel="alternate" href="android-app://…">`) → App Store-id via `https://itunes.apple.com/lookup?id=<id>&country=<cc>` (≥ 3 s ertussen, max. 600 per run) → `artworkUrl512` → `/256x256bb.png`; Play-pakket via `https://play.google.com/store/apps/details?id=<pkg>&hl=en&gl=US` → `og:image` (play-lh, achtervoegsel `=w…-h…`/`=s…` → `=s256`; ≥ 2 s ertussen). Per zender alleen als de appnaam bij de zender past (gewone match, of een onderscheidend kernwoord van de zender/het domein zit in de appnaam). Daarna (invoer `play`, standaard aan) de **Google Play-zoekfunctie** `https://play.google.com/store/search?q=<naam>&c=apps&hl=<taal>&gl=<land>` voor de top 100 per land + top 1000 wereldwijd zonder App Store- of Play-icoon (algemene namen zoals "Radio 1" niet; max. 300 per run, ≥ 2 s): resultaten uit de links `/store/apps/details?id=` met titel en icoon (los van class-namen), dezelfde match als `match_app`, dan op de app-pagina streng: exact dezelfde (kern)naam, of kernnaam in de appnaam én de ontwikkelaar hoort bij de website (fan-apps vallen af). Bij HTTP 403/429/503 stopt Play voor die run. Elk store-icoon wordt gecontroleerd (Pillow, vierkant, ≥ 128 px, niet effen). Per zender: App Store-link > Play-link > Play-zoeken > website-icoon. Cache `play-cache.json` op `icons-data` (`ios:<id>`, `gp:<pkg>`, `q:<CC>|<naamsleutel>`; missers na 30, treffers na 120 dagen opnieuw). De job `publish` voegt alles samen met `tools/merge_icon_tables.py` vanaf de nieuwste main (App Store > Google Play > website, niets verdwijnt) en bewaart de gekozen bron per sleutel in `sources.json` op `icons-data` (niet in de openbare tabellen). `tools/make_wall.py` (hero) gebruikt dezelfde samengevoegde tabel/match en neemt het app-icoon vóór het favicon.
- tvOS / Android TV: focus = 1.08× schalen + schaduw + witte 3px rand; nooit grijze systeemvlakken.
- **Apple TV (focus engine)**: elk bedienbaar element is een `Button` met een tv-stijl (`TVLiftStyle`, `TVRowButtonStyle` voor lijstrijen, `AccentButtonStyle`/`SecondaryButtonStyle`); geen tik-gebaren of `Menu`'s (keuzes via `confirmationDialog`, bv. slaaptimer en snelheid); horizontale rijen met `.focusSection()` en `.scrollClipDisabled()`. Landkeuze (eerste start, Ontdek en Instellingen) schermvullend (`fullScreenCover`): raster van landrijen met zoeken (`.searchable`), het huidige land gemarkeerd en met focus; Menu sluit. Regio's en talen: eigen lijsten met focusvlak (huidige regio krijgt de focus). Instellingen: systeemrijen, ook Versie/links focusbaar zodat je tot onderaan kunt scrollen. Speler: afspelen/pauze krijgt de focus, Play/Pause-knop van de afstandsbediening werkt, Menu sluit. Rasterpagina's: Alles afspelen/Maak mijn regio als knoppen boven het raster (geen werkbalk). Kaart: niet bedienbaar met de afstandsbediening (geen focus op stippen); kiezen via de lijst links.

## 2. Databron: Radio Browser

Open community-database, geen sleutel nodig.

- **Servers**: `GET https://all.api.radio-browser.info/json/servers` → `[{"name":"de1.api.radio-browser.info", ...}]`. Kies willekeurig, bewaar de keuze voor de sessie, bij een fout de volgende. Terugval-lijst: `de1`, `de2`, `fi1` (`https://<x>.api.radio-browser.info`).
- **User-Agent** altijd: `Tunr/1.0.0 (nl.lrvdlinden.tunr; <platform>)`.
- Endpoints (alle `GET`, JSON):
  - Landen: `/json/countries?hidebroken=true&order=name` → `[{name, iso_3166_1, stationcount}]`. Filter `stationcount >= 1` en lege codes eruit. Toon de **gelokaliseerde** landnaam (Locale / Intl.DisplayNames) en de vlag als emoji uit de ISO-code.
  - Zenders per land, populair: `/json/stations/search?countrycode=NL&hidebroken=true&order=clickcount&reverse=true&limit=60&offset=0`
  - Trending: zelfde met `order=clicktrend`
  - Per genre in land: zelfde met `&tag=<tag>&tagExact=true`
  - Zoeken: `/json/stations/search?name=<q>&countrycode=NL&hidebroken=true&order=clickcount&reverse=true&limit=60` (zonder `countrycode` = wereldwijd)
  - Genres in land: neem de `tags` van de top-500 zenders en tel; of vaste lijst (zie §4).
  - Zenders op uuid: `/json/stations/byuuid?uuids=a,b,c` (favorieten verversen)
  - Klik tellen bij afspelen: `/json/url/<stationuuid>` (fire-and-forget)
- Zender-velden die we gebruiken: `stationuuid, name, url, url_resolved, homepage, favicon, tags, country, countrycode, state, language, codec, bitrate, hls, votes, clickcount, clicktrend, lastcheckok, geo_lat, geo_long`.
- Stream-URL: `url_resolved`, anders `url`. Namen trimmen; dubbele zenders (zelfde naam + zelfde `url_resolved`) samenvoegen.
- Caching: landenlijst 7 dagen, zenderlijsten 30 min (geheugen + schijf).

**Albumhoes bij "nu speelt"**: als de stream ICY-metadata geeft (`StreamTitle='Artiest - Titel'`), splits op ` - ` en zoek `https://itunes.apple.com/search?term=<artiest titel>&entity=song&limit=1` → `artworkUrl100` vervangen door `600x600bb`. Cache per titel. Geen resultaat → zenderlogo.

## 3. Flow

1. **Splash** (±3,4 s, met tune, overslaanbaar met tik/OK):
   - zwart scherm; in het midden een horizontale **frequentieschaal** (maatstreepjes, getallen 88–108) die infadet;
   - een **naald** zoekt van links naar rechts met wat haperingen (0–1,4 s) terwijl de tune "ruis + afstemmen" laat horen;
   - op 1,45 s **klik/lock**: naald staat stil, er gaan 3 **cirkelgolven** uit (accent, uitdijend, vervagend);
   - de letters **T U N R** springen één voor één omhoog (90 ms uit elkaar, tegelijk met de 4 tonen), de schaal krimpt tot de balk onder het woordmerk;
   - glanzende veeg over de letters (2,1 s), fade-out (3,1–3,4 s).
   - Tune: `tunr_tune.m4a` (gemaakt met `tools/make_tune.py`), speelt met `.playback` + `mixWithOthers`. Speelt altijd (niet uit te zetten, sinds build 9).
2. **Landkeuze** (verplicht bij eerste start, daarna via Instellingen of het landknopje rechtsboven op Home):
   - titel "Kies je land" / "Choose your country", subtitel "Je kunt dit later altijd wijzigen";
   - zoekveld; bovenaan **"Voorgesteld"** met het land van het toestel; daarna **"Alle landen"** alfabetisch;
   - rij: vlag (groot), landnaam, aantal zenders ("1.234 zenders");
   - tv: raster van landkaarten (vlag groot + naam + aantal), zoeken via de tv-zoekbalk;
   - kiezen → opslaan → naar Home met een korte overgang.
3. **Hoofdscherm** met tabs **Ontdek · Zoeken · Favorieten · Instellingen** (iPhone/Android telefoon: onderaan; iPad: zijbalk/tabs; tv: bovenaan (tvOS) / links (Android TV)). Altijd een **miniplayer** boven de tabbalk zodra er iets speelt (tv: geen miniplayer, wel een "Nu aan het spelen"-kaart bovenaan Ontdek).

## 4. Schermen

### Ontdek (Home)
- Kop: `TunrLogo` links, rechts een **landknop** (vlag + landcode) → Landkeuze.
- **Hero-carrousel**: top 6 populairste zenders; grote kaart met vervaagde cover-achtergrond, StationArt, naam, genres, knop **Luister** (play) en **Info**.
- Rijen (horizontaal scrollen, "Alles"-knop → rasterpagina):
  1. Verder luisteren (recent, alleen als er iets is)
  2. Populair in {land}
  3. Trending
  4. Jouw favorieten (alleen als er iets is)
  5. Genre-chips (horizontaal): Pop, Nieuws, Rock, Dance, Jazz, Klassiek, Hits, Talk, Sport, Oldies, Hiphop, Country, Ambient, Christelijk → tags `pop, news, rock, dance, jazz, classical, hits, talk, sports, oldies, hiphop, country, ambient, christian`. Een chip opent de **genrepagina** (raster).
  6. Twee genre-rijen voor het land: de 2 genres met de meeste zenders.
- Laden: skeletten; fout: melding met **Opnieuw**.

### Zenderdetail
- Groot: StationArt (iPhone 260 pt, iPad/tv groter), daaronder naam (heavy), regel "Stad/provincie · Land {vlag}".
- Knoppen: **Afspelen/Pauze** (groot, accent), **Favoriet** (hart), **Delen** (deelt naam + homepage of stream), **Website** (als `homepage`).
- **Nu speelt**-kaart (als deze zender speelt): hoes + "Artiest — Titel", LIVE-bolletje.
- Genre-chips (tikbaar → genrepagina).
- Info-raster: Codec, Bitrate ("128 kbps"), Taal, Stemmen, Luisteraars (clickcount), HLS ja/nee.
- **Vergelijkbare zenders**: zelfde eerste genre in hetzelfde land (zonder deze zender), rij.
- tvOS/Android TV: links grote art, rechts info + knoppen; rij vergelijkbaar onderaan.

### Speler
- **Miniplayer**: art 44 pt, naam, "Nu speelt"-tekst of genres, play/pauze, (telefoon) volgende. Tik → volledig scherm.
- **Volledig scherm** (sheet, sleepbaar omlaag): achtergrond = vervaagde art; grote art (hoes van het nummer als bekend, anders zender); titel/artiest of zendernaam; LIVE-bolletje + equalizer; knoppen **vorige zender · play/pauze · volgende zender** (binnen de lijst van waaruit gestart is); **favoriet**, **AirPlay** (iOS) / **Cast-knop** weglaten op Android, **slaaptimer** (15/30/45/60/90 min, uit), **delen**; volume-slider (iOS: MPVolumeView).
- Achtergrondaudio, vergrendelscherm en Bedieningspaneel / mediamelding met art, titel en vorige/volgende/play/pauze. Onderbrekingen (telefoon, andere app) correct afhandelen; koptelefoon eruit → pauze.
- Bij fout/ruis: "Deze zender is nu niet bereikbaar" met **Opnieuw** en automatisch één keer opnieuw proberen met `url` als `url_resolved` faalde.
- Bij afspelen: `/json/url/<uuid>` aanroepen en de zender bovenaan "Recent" zetten (max 30).

### Zoeken
- Zoekveld (debounce 350 ms), schakelaar **{land} / Wereldwijd**.
- Leeg: "Populaire genres" (de chips) + "Recent gezocht" (max 8, wisbaar).
- Resultaten: lijst (art 56, naam, land/genres, bitrate) met equalizer als die speelt.

### Favorieten
- Raster (telefoon 2–3 kolommen, iPad 4–6, tv 6), lang indrukken/contextmenu → verwijderen; bewerken/sorteren (iOS EditButton, Android slepen mag later).
- Leeg: illustratie (hart in golven) + "Tik op het hartje bij een zender om hem hier te bewaren".
- Opslag: lokaal (iOS: UserDefaults + iCloud KV-store `NSUbiquitousKeyValueStore` zodat iPhone/iPad/Apple TV delen; Android: DataStore/SharedPreferences; web: localStorage). Bewaar de volledige zender (JSON) zodat de lijst offline werkt.

### Instellingen
- **Land** (vlag + naam, → Landkeuze)
- **Taal**: Systeem, Nederlands, English
- (Intromuziek is geen instelling: de tune speelt altijd)
- **Taal, slaaptimer en automatisch verder spelen** gaan op Apple via iCloud mee tussen je apparaten
- **Slaaptimer standaard** (uit/15/30/60)
- **Automatisch verder spelen bij opstarten** (laatste zender, standaard uit)
- **Recent wissen**, **Favorieten wissen** (met bevestiging)
- **Privacy → Anonieme gebruiksstatistieken** (standaard aan, per apparaat, niet via iCloud), met uitleg eronder: geen persoonsgegevens, alleen type apparaat, app-versie, gekozen land/taal en een willekeurig installatienummer. Aan = max. 1× per 12 uur een ping bij starten/terugkomen (contract: `tunr-beheer/docs/CONTRACT.md`); uit = niets. De website pingt niet.
- **Over**: versie + build, link naar de website, privacy, voorwaarden, "Zendergegevens: Radio Browser (community)" met link `https://www.radio-browser.info`.

## 5. Platform-details

**Apple** (`apple/`): SwiftUI, iOS 17+, tvOS 17+, Swift 5.9, XcodeGen. Targets `Tunr` (iOS, device family 1,2) en `TunrTV` (tvOS). Gedeelde code in `apple/Shared`. AVPlayer (HLS en Icecast/Shoutcast mp3/aac werken), ICY-titels via `AVPlayerItemMetadataOutput`. `UIBackgroundModes: [audio]`, `NSAllowsArbitraryLoads: true` (veel zenders zijn http). Lokalisatie in `Localizable.strings` (en, nl). Bundle `nl.lrvdlinden.tunr`, team `EU3UY476T6`.

**Android** (`android/`): Kotlin, Compose (Material 3, eigen donker thema met bovenstaande tokens), Media3 ExoPlayer + `MediaSessionService` (melding + vergrendelscherm), HLS-module, OkHttp-datasource, Coil voor afbeeldingen, kotlinx-serialization. minSdk 24, target/compile 35. Eén APK; Android TV via `LEANBACK_LAUNCHER`, `android:banner`, `touchscreen required=false`; als het toestel een tv is (UiModeManager) de tv-indeling met D-pad-focus. `usesCleartextTraffic=true`. ICY-titel via `Player.Listener.onMediaMetadataChanged` (`title`/`station`). Strings in `values/` (en) en `values-nl/`.

**Windows** (`windows/`): desktop-app met dezelfde flow als de vroegere webspeler, maar zonder tikpoort (splash met tune bij elke start), zijbalk op brede vensters, Leaflet-kaart met CARTO-tegels, mediatoetsen via de Media Session API, links naar buiten in de standaardbrowser, gedeelde links via `https://tunr.online/web/`. Gegevens (favorieten, land, instellingen) lokaal in WebView2.

**Web**: geen webspeler (offline om rechtenredenen). `website/web/` toont alleen gedeelde links uit de apps (zender/podcast/aflevering) met een knop naar de apps en speelt niets af.

---

## 6. Uitbreiding (geïnspireerd op TuneIn) — HEEFT VOORRANG op §3–§4 waar het verschilt

### Tabs (nieuw)
**Ontdek · Bladeren · Kaart · Zoeken · Bibliotheek** (iPhone/Android telefoon: 5 tabs onderaan; iPad/tv/web: zijbalk of bovenbalk).
- **Instellingen** is geen tab meer: tandwiel-knop rechtsboven op Ontdek en Bibliotheek (tv: laatste item in de tab/zijbalk mag wel "Instellingen" zijn).
- **Bibliotheek** = segmenten **Favorieten · Recent** (Favorieten-scherm uit §4 + volledige Recent-lijst met "Wissen").
- SF Symbols / Material-iconen: `dot.radiowaves.left.and.right` / Radio, `square.grid.2x2` / GridView, `globe.europe.africa` / Public, `magnifyingglass` / Search, `books.vertical` / LibraryMusic.

### Ontdek (aanvullingen)
- Kop: begroeting naar tijdstip ("Goedemorgen", "Goedemiddag", "Goedenavond", "Goedenacht") boven de rijen.
- Nieuwe rij **"Lokaal"** direct na Verder luisteren: zenders uit de provincie/staat die de gebruiker kiest (zie Bladeren → Lokaal); zolang niets gekozen is een kaart "Kies je regio" die naar die lijst gaat.

### Bladeren (nieuw tabblad, raster van grote gekleurde tegels zoals TuneIn)
Tegels (verloop uit het StationArt-palet, groot icoon, titel):
1. **Lokaal** → lijst van regio's in het land: `GET /json/states/{landnaam-Engels}/?hidebroken=true&order=stationcount&reverse=true` (velden `name, country, stationcount`; landnaam = het `name`-veld uit /json/countries). Kies regio → zenderlijst `/json/stations/search?countrycode=NL&state=<regio>&stateExact=true&hidebroken=true&order=clickcount&reverse=true`. Laatst gekozen regio wordt de "Lokaal"-regio voor Ontdek (ook te kiezen met een "Maak dit mijn regio"-knop).
2. **Muziek** → genres (alle muziekchips) als tegels → genrepagina.
3. **Nieuws & Talk** → zenders met tag `news` + `talk` (twee secties).
4. **Sport** → tag `sports`.
5. **Op taal** → `GET /json/languages?hidebroken=true&order=stationcount&reverse=true&limit=60` → lijst met talen (gelokaliseerd waar mogelijk) → zenders `/json/stations/search?language=<taal>&languageExact=true&...` (wereldwijd, niet beperkt tot land).
6. **Wereldkaart** → springt naar het Kaart-tabblad.
7. **Top 100 wereldwijd** → `/json/stations/search?hidebroken=true&order=clickcount&reverse=true&limit=100` (zonder land), genummerd 1–100.

### Kaart (nieuw tabblad — de "wow"-functie, zoals TuneIn Explorer / Radio Garden)
- Donkere interactieve wereldkaart met zenders als **gloeiende stippen** (accent, zachte gloed); de zender die speelt pulseert. Inzoomen/pannen; clustering met aantal in een rondje bij uitgezoomd.
- Data: zenders met geo-informatie: `/json/stations/search?countrycode=NL&has_geo_info=true&hidebroken=true&order=clickcount&reverse=true&limit=500` voor het gekozen land (de kaart opent gecentreerd op dat land), plus een knop **"Wereld"** die de top 1500 wereldwijd laadt (`has_geo_info=true`, zonder land). Zenders zonder geo verschijnen niet op de kaart.
- Tik op een stip/cluster → onderaan een **kaartje** met StationArt, naam, plaats, genres en grote **Afspelen**-knop + "Info". Horizontaal swipen in het kaartje = de dichtstbijzijnde zenders.
- Knop **"Willekeurig"** (dobbelsteen): vliegt naar een willekeurige zender wereldwijd en speelt hem af (Radio Garden-gevoel).
- Kaartmateriaal (geen API-sleutels):
  - Apple: **MapKit** (SwiftUI `Map`, iOS 17/tvOS 17) met `.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))` in donker; eigen annotaties. tvOS: Map met focus op stippen via een lijst ernaast (D-pad: links een lijst met de zenders in beeld, selecteren centreert de kaart).
  - Android: **osmdroid** (`org.osmdroid:osmdroid-android:6.1.20`) met CARTO-tegels "dark_all" (`https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png`, attributie "© OpenStreetMap-bijdragers © CARTO" zichtbaar), eigen User-Agent; Android TV: lijst links + kaart rechts, D-pad zoals tvOS.
  - Web: **Leaflet** (cdnjs) + dezelfde CARTO dark-tegels + attributie, markers als CSS-stippen, Leaflet.markercluster (cdnjs).

### Speler (aanvullingen)
- Onder de knoppen een rij **"Meer van deze zender"**-acties: Delen, Slaaptimer, **Zenderinfo**.
- Boven de art een **LIVE**-pil.
- Android: **Android Auto** ondersteunen via Media3 `MediaLibraryService` met een bladerboom: Favorieten, Recent, Populair in {land}, Genres (zie platform-details); CarPlay later (vereist Apple-toestemming).

## 7. Apple: één multiplatform-target + Mac + CarPlay — HEEFT VOORRANG op §5 (Apple)

- **Eén Xcode-project, één app-target `Tunr`** met `supportedDestinations: [iOS, tvOS, macOS]` (XcodeGen ≥ 2.40). Geen aparte TV-target meer. Platformverschillen met `#if os(iOS)` / `os(tvOS)` / `os(macOS)`. Deployment: iOS 17, tvOS 17, macOS 14.
- Eén asset-catalogus `apple/Shared/Assets.xcassets` met `AppIcon` (iOS 1024 + macOS-maten), `App Icon & Top Shelf Image` (tvOS) en `AccentColor`. Icoonnaam per SDK: `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletv*]`.
- Info.plist en entitlements per SDK via `INFOPLIST_FILE[sdk=…]` / `CODE_SIGN_ENTITLEMENTS[sdk=…]`.
- **Mac**: `NavigationSplitView` met zijbalk (Ontdek, Bladeren, Kaart, Zoeken, Bibliotheek, Instellingen via ⌘,-`Settings`-scene), miniplayer onderaan het venster, menu **Afspelen** (Spatie = afspelen/pauze, ⌘→/⌘← = volgende/vorige zender, ⌘L = favoriet), Now Playing in het Bedieningscentrum via MPNowPlayingInfoCenter, venster min. 900×600. Sandbox met netwerk-client.
- **CarPlay** (audio-app): `CPTemplateApplicationSceneDelegate` in een eigen scene (`UIApplicationSceneManifest` → `CPTemplateApplicationSceneSessionRoleApplication`). Root = `CPTabBarTemplate` met tabs **Favorieten**, **Recent**, **Populair** ({land}) en **Genres** (lijst → zenders) als `CPListTemplate`'s met zenderlogo's; kiezen speelt af en toont `CPNowPlayingTemplate.shared` (knoppen: favoriet, volgende/vorige zender via remote commands). Alleen code onder `#if os(iOS)` + `canImport(CarPlay)`. De entitlement komt pas mee als Apple hem toekent (zie CLAUDE.md), dus de app moet bouwen en draaien zonder.

---

## 8. Podcasts (alle apps) — nieuw

Naast radio kun je in Tunr podcasts zoeken, volgen en afluisteren. Geen account, geen sleutels.

### Bronnen (sleutelloos)
- **Toplijst per land**: `GET https://rss.applemarketingtools.com/api/v2/{cc}/podcasts/top/50/podcasts.json` (cc = landcode in kleine letters, bv. `nl`) → `feed.results[] {id, name, artistName, artworkUrl100, genres[]}`. Valt terug op `us` als het land geen lijst heeft.
- **Zoeken**: `GET https://itunes.apple.com/search?media=podcast&entity=podcast&term=<q>&country=<cc>&limit=50` → `results[] {collectionId, collectionName, artistName, artworkUrl600, primaryGenreName, trackCount, feedUrl, releaseDate}`.
- **Podcast + afleveringen**: `GET https://itunes.apple.com/lookup?id=<collectionId>&entity=podcastEpisode&limit=100&country=<cc>` → eerste resultaat = de podcast (`wrapperType: "track"`, `kind: "podcast"`), de rest = afleveringen (`wrapperType: "podcastEpisode"`) met `trackId, trackName, description/shortDescription, releaseDate, trackTimeMillis, episodeUrl, artworkUrl600, episodeFileExtension`.
- **Genres** (tegels): zoeken met `&genreId=` via de toplijst per genre: `https://itunes.apple.com/{cc}/rss/toppodcasts/limit=50/genre=<id>/json` (oud formaat, `feed.entry[]`: `im:name.label`, `im:artist.label`, `im:image[2].label`, `id.attributes["im:id"]`). Genres: Nieuws 1489, Comedy 1303, Sport 1545, True crime 1488, Maatschappij & cultuur 1324, Zakelijk 1321, Gezondheid 1512, Geschiedenis 1487, Wetenschap 1533, Technologie 1318, Kinderen & gezin 1305, Muziek 1310.
- Artwork: vervang `100x100bb`/`600x600bb` door `600x600bb`.
- **Web**: als `fetch` door CORS faalt, gebruik voor `itunes.apple.com` de JSONP-variant (`&callback=cb`); de toplijst-JSON van rss.applemarketingtools.com via fetch (valt die weg, dan de oude iTunes-RSS met JSONP niet mogelijk → toon "Populair" uit een zoekopdracht `term=podcast`).
- Cache: toplijsten 6 uur, afleveringen 30 min.

### Plek in de app
- **Bladeren**: nieuwe grote tegel **Podcasts** (bovenaan, naast Lokaal) → podcastoverzicht.
- **Ontdek**: rij **Populaire podcasts in {land}** (na Trending) en, als je favoriete podcasts hebt, **Nieuwe afleveringen** (laatste aflevering van elke favoriete podcast, nieuwste eerst) en **Verder luisteren** voor half beluisterde afleveringen.
- **Podcastoverzicht** (vanuit Bladeren): toplijst van je land (genummerd 1–50), genre-tegels, zoeken.
- **Zoeken**: segment **Zenders · Podcasts** bovenaan; bij Podcasts zoekt het in iTunes.
- **Bibliotheek**: segmenten **Favorieten · Podcasts · Recent**. Podcasts = **Favoriete podcasts** (raster, hartje op de kaart) + gedownloade/half beluisterde afleveringen bovenaan als "Verder luisteren".
- **Favoriet** (zoals bij zenders): een podcast zet je met het **hartje** in je favorieten: knop **Favoriet / In favorieten** (EN *Favourite / In favourites*; Android EN *Favorite / In favorites*), `heart`/`heart.fill` in de accentkleur. Plekken: podcastpagina (in de knoppenrij; op tv krijgt hij bij openen de focus), speler voor afleveringen (de podcast van de aflevering; iPhone/Android-telefoon naast de titel/rechtsboven, elders in de actierij), contextmenu (lang indrukken) op podcastkaarten en -rijen en op afleveringen. Opslag = de bestaande lijst gevolgde podcasts (Apple ook iCloud KV), dus niets verandert voor wie al podcasts volgde.
- **Podcastpagina**: grote art, titel, maker, genre, aantal afleveringen, **Speel nieuwste**, **Favoriet**, beschrijving (uitklapbaar), lijst afleveringen (datum, duur, titel, korte omschrijving, voortgangsbalkje als je al luisterde, ✓ als beluisterd) met sorteren Nieuwste/Oudste.
- **Afleveringspagina** (tik op aflevering): titel, podcast, datum, duur, volledige omschrijving, Afspelen.

### Speler voor afleveringen (zelfde speler, andere modus)
- Geen LIVE-pil maar een **tijdbalk** (sleepbaar) met verstreken/resterende tijd; knoppen **15 s terug · afspelen/pauze · 30 s vooruit**; **snelheid** (0,8×, 1×, 1,25×, 1,5×, 1,75×, 2×); slaaptimer incl. "Einde van aflevering"; volgende/vorige = volgende/vorige aflevering in de lijst.
- **Positie onthouden** per aflevering (elke 10 s en bij pauze), hervatten waar je was; ≥ 95% = beluisterd.
- Vergrendelscherm / Bedieningspaneel / mediamelding met scrubben (`changePlaybackPositionCommand`, skipForward 30 / skipBackward 15; Android Media3 seekBack/seekForward).
- Mini-player toont titel van de aflevering en een dunne voortgangslijn.
- CarPlay en Android Auto: extra tab/map **Podcasts** met gevolgde podcasts → afleveringen.
- tvOS en Android TV: podcasts in Bladeren en Bibliotheek; speler met tijdbalk (op tvOS met swipe/klik-links/rechts = 15/30 s).

### Opslag
- Favoriete (gevolgde) podcasts (id, naam, maker, art, feedUrl) en afspeelposities (episodeId → seconden, duur, beluisterd) lokaal; Apple ook via iCloud KV (zoals favorieten). Max 500 posities (oudste eruit).

---

## 9. Zoeken op de kaart (alle apps) — nieuw

Bovenaan de Kaart een **zoekveld** "Zoek een land of plaats" (EN "Search a country or place"), naast de knoppen {land} · Wereld · Willekeurig (telefoon: zoekveld op een eigen regel erboven).

- **Suggesties tijdens het typen** (debounce 300 ms, vanaf 2 tekens), in twee groepen:
  1. **Landen**: uit de landenlijst van Radio Browser (al in cache), match op de gelokaliseerde én de Engelse naam en op de landcode; vlag + naam + "1.234 zenders". Max 5.
  2. **Plaatsen**: geocoder van het platform (zie onder): naam + regio/land met vlag. Max 6.
- **Kies je een land** → de kaart toont de zenders van dát land (zelfde query als de landmodus, `countrycode=XX&has_geo_info=true`, limit 500) en past de kaart erop aan; de landknop in de balk toont dan dat land (tijdelijk, het gekozen land in Instellingen verandert niet). Terug naar je eigen land met de landknop.
- **Kies je een plaats** → de kaart vliegt erheen (zoom ±25 km), laadt de zenders in de buurt: `GET /json/stations/search?geo_lat=<lat>&geo_long=<lon>&geo_distance=50000&has_geo_info=true&hidebroken=true&order=clickcount&reverse=true&limit=300`. Leeg → straal 150 km; nog leeg → de zenders van het land van die plaats. Daarna opent het kaartje onderaan met de dichtstbijzijnde zender + 7 in de buurt (zelfde kaartje als bij tikken op een stip).
- Enter zonder suggestie kiezen = eerste suggestie. Escape/× = veld leeg en suggesties dicht. Lege resultaten: "Niets gevonden voor “…”".
- Recente kaartzoekopdrachten (max 5) als suggesties zolang het veld leeg is en focus heeft.

**Geocoders (geen extra sleutels):**
- **Apple** (iOS, iPadOS, macOS, tvOS): `MKLocalSearchCompleter` met `resultTypes = .address` voor suggesties en `MKLocalSearch` om een gekozen suggestie op te lossen naar coördinaat + `placemark.countryCode`. tvOS: SwiftUI `.searchable` met dezelfde suggesties als lijst.
- **Android**: `android.location.Geocoder.getFromLocationName(q, 6)` op een achtergrondthread (API 33+: de callback-variant); niet beschikbaar of leeg → **Nominatim** `https://nominatim.openstreetmap.org/search?q=<q>&format=jsonv2&limit=6&addressdetails=1&accept-language=<taal>` met de User-Agent van de app, max 1 aanvraag per seconde (debounce regelt dat).
- **Web**: met Apple Maps (`mapkit.Search`/`autocomplete` + `search`) als die geladen is; met de Leaflet-terugval **Nominatim** (zelfde URL; de browser stuurt de Referer, geen eigen User-Agent mogelijk).

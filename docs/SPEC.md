# Tunr — functionele spec en huisstijl

Eén product op zes schermen: **iPhone, iPad, Apple TV, Android (telefoon/tablet), Android TV** en de **webspeler**. Alle platforms hebben dezelfde functies, schermen, volgorde en teksten (NL + EN; standaard de taal van het toestel, Engels als terugval).

---

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
- Zendercover ("StationArt"): vierkant. Achtergrond = verloop van twee kleuren afgeleid van een hash van de zendernaam (palet hieronder), daarop het logo (`favicon`) gecentreerd op 62% met 8% binnenmarge op een witte, afgeronde tegel als het logo transparant/klein is; geen logo of laden mislukt → **monogram** (eerste 1–2 letters, heavy rounded, wit). Paletten (begin, eind):
  `#FF5A1F→#FFB020`, `#7C3AED→#DB2777`, `#0EA5E9→#22D3EE`, `#10B981→#84CC16`, `#F43F5E→#FB923C`, `#6366F1→#06B6D4`, `#EAB308→#F97316`, `#14B8A6→#3B82F6`.
- Equalizer-animatie (4 staafjes, accent) bij de zender die nu speelt — in kaarten, lijsten, miniplayer.
- tvOS / Android TV: focus = 1.08× schalen + schaduw + witte 3px rand; nooit grijze systeemvlakken.

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
   - Tune: `tunr_tune.m4a` (gemaakt met `tools/make_tune.py`), speelt met `.playback` + `mixWithOthers`. Uit te zetten in Instellingen → Intromuziek.
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
- **Intromuziek** aan/uit
- **Slaaptimer standaard** (uit/15/30/60)
- **Automatisch verder spelen bij opstarten** (laatste zender, standaard uit)
- **Recent wissen**, **Favorieten wissen** (met bevestiging)
- **Over**: versie + build, link naar de website, privacy, voorwaarden, "Zendergegevens: Radio Browser (community)" met link `https://www.radio-browser.info`.

## 5. Platform-details

**Apple** (`apple/`): SwiftUI, iOS 17+, tvOS 17+, Swift 5.9, XcodeGen. Targets `Tunr` (iOS, device family 1,2) en `TunrTV` (tvOS). Gedeelde code in `apple/Shared`. AVPlayer (HLS en Icecast/Shoutcast mp3/aac werken), ICY-titels via `AVPlayerItemMetadataOutput`. `UIBackgroundModes: [audio]`, `NSAllowsArbitraryLoads: true` (veel zenders zijn http). Lokalisatie in `Localizable.strings` (en, nl). Bundle `nl.lrvdlinden.tunr`, team `EU3UY476T6`.

**Android** (`android/`): Kotlin, Compose (Material 3, eigen donker thema met bovenstaande tokens), Media3 ExoPlayer + `MediaSessionService` (melding + vergrendelscherm), HLS-module, OkHttp-datasource, Coil voor afbeeldingen, kotlinx-serialization. minSdk 24, target/compile 35. Eén APK; Android TV via `LEANBACK_LAUNCHER`, `android:banner`, `touchscreen required=false`; als het toestel een tv is (UiModeManager) de tv-indeling met D-pad-focus. `usesCleartextTraffic=true`. ICY-titel via `Player.Listener.onMediaMetadataChanged` (`title`/`station`). Strings in `values/` (en) en `values-nl/`.

**Web** (`website/web/`): zelfde flow (splash licht, met tune als de bezoeker op "Start" tikt — browsers blokkeren autoplay), `<audio>` + hls.js (cdnjs) voor HLS, Media Session API, favorieten in localStorage.

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

# Tunr voor Windows

Desktop-app voor Windows 10 en 11 (64-bit), gemaakt met [Tauri 2](https://tauri.app): een klein Rust-programma
(`src-tauri/`) dat een venster opent met de speler in HTML/JS (`app/`). De speler is dezelfde als de vroegere
webspeler van tunr.online (die is om rechtenredenen offline); hij draait nu alleen nog in deze app.

## Bouwen

De workflow *Windows* bouwt bij elke push naar `windows/**` de installer `Tunr-<versie>-build<N>-Setup.exe` en zet
hem in Beheer (tab Downloads, onderdeel Windows). Buildnummer: `windows/tunr.properties`.

Zelf op een Windows-pc (met [Rust](https://rustup.rs) en Node 22):

```
cd windows\src-tauri
npx @tauri-apps/cli@2.12.4 dev        # starten
npx @tauri-apps/cli@2.12.4 build      # installer in target\release\bundle\nsis\
```

`app/assets/js/build-config.js` (niet in git) zet het buildnummer en de CARTO-sleutel; zonder dat bestand draait de
app ook (build 0, kaart met watermerk).

## Verschillen met de vroegere webspeler

- geen tikpoort: WebView2 start met `--autoplay-policy=no-user-gesture-required`, dus de tune speelt direct;
- kaart altijd Leaflet + CARTO (een MapKit JS-token geldt alleen voor tunr.online);
- links naar buiten (website, privacy, zenderwebsites) openen in de standaardbrowser (`desktop.js`);
- delen geeft een link naar `https://tunr.online/web/#/…` (pagina voor gedeelde links);
- gebruiksping met platform `windows`, standaard aan (instelling in Instellingen).

## Vlaggen

Windows heeft geen vlag-emoji's. Daarom gebruikt de app het lettertype *Twemoji Country Flags*
(`app/assets/fonts/`, uit het npm-pakket `country-flag-emoji-polyfill` 0.1.10; code MIT, vlaggen uit
[Twemoji](https://github.com/twitter/twemoji) onder CC-BY 4.0), alleen voor de vlagtekens.

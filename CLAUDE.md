# Tunr: werkafspraken

Tunr is een wereldwijde radio-app (werknaam) voor **iPhone, iPad, Mac, Apple TV, CarPlay, Android, Android TV / Android Auto** en een **website met webspeler**. Alles staat in deze ene repo.

## Mappen

| Map | Inhoud |
|---|---|
| `apple/` | SwiftUI-app: **één Xcode-project met één multiplatform-target `Tunr`** (iPhone, iPad, Mac, Apple TV) + CarPlay-scene. `apple/Tunr.xcodeproj` staat in de repo (door de workflow *Apple* gemaakt uit `apple/project.yml` met XcodeGen): klonen en openen |
| `android/` | Kotlin + Jetpack Compose + Media3; één APK voor telefoon, tablet en Android TV / Google TV / Fire TV |
| `website/` | Statische site (NL/EN) met de webspeler op `/web/`, wordt via FTP gepubliceerd |
| `docs/` | `SPEC.md` (functionele spec en huisstijl), `changelog.json`, mockups en screenshots |
| `tools/` | Scripts: tune, iconen, screenshots, changelog |

## Afspraken

- Versie blijft **1.0.0**; alleen het buildnummer gaat omhoog, en alleen voor de platforms die echt veranderen.
  - Apple: `CURRENT_PROJECT_VERSION` in `apple/project.yml`.
  - Android (+ Android TV): `TUNR_BUILD` in `android/gradle.properties`.
  - Website: geen buildnummer in een bestand; telt mee via de changelog (`web`).
- Wijzig het Xcode-project via `apple/project.yml` (niet in Xcode zelf): de workflow maakt `Tunr.xcodeproj` opnieuw en commit hem.
- CarPlay: code en scene zitten erin; de entitlement `com.apple.developer.carplay-audio` staat in `apple/Tunr-CarPlay.entitlements` en wordt pas gebruikt (`TUNR_CARPLAY = YES` in `project.yml`) zodra Apple hem heeft toegekend (aanvragen via developer.apple.com/contact/carplay).
- Bundle-/application-id: `nl.lrvdlinden.tunr`. Apple Team ID: `EU3UY476T6` (automatisch ondertekenen).
- Bij elke build:
  - een item in `docs/changelog.json` (per punt `type` = `new`/`improved`/`fixed`, `platforms` uit `ios`, `ipados`, `macos`, `tvos`, `carplay`, `android`, `androidtv`, `web`, en tekst in `nl` en `en`);
  - `python3 tools/make_changelog.py` (maakt `CHANGELOG.md` en `website/assets/changelog.json`);
  - README en screenshots bijwerken als schermen veranderen (`python3 tools/make_screenshots.py`).
- Buildpakketten (Xcode-zip, APK) nooit openbaar in de repo of als release: de repo is openbaar.
- Geen geheime sleutels in de repo. De app gebruikt alleen openbare, sleutelloze bronnen:
  - zenders: **Radio Browser** (community-database, `api.radio-browser.info`), altijd met een eigen User-Agent `Tunr/1.0.0`;
  - albumhoezen bij "nu speelt": **iTunes Search API** (zonder sleutel).
- Website-FTP: secrets `FTP_SERVER`, `FTP_USERNAME`, `FTP_PASSWORD` (optioneel `FTP_DIR`). Zonder secrets slaat de workflow de upload over.
- De naam "Tunr" is een werknaam en staat op één plek per platform (`apple/Shared/App/Brand.swift`, `android/.../Brand.kt`, `website/assets/js/brand.js`) plus teksten; zoek-en-vervang op `Tunr` volstaat bij een nieuwe naam.

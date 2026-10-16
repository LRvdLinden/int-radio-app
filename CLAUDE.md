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
- CarPlay: code en scene zitten erin; de entitlement `com.apple.developer.carplay-audio` staat in `apple/Config/Tunr-CarPlay.entitlements` en wordt pas gebruikt zodra Apple hem heeft toegekend: zet dan in `apple/project.yml` `TUNR_IOS_ENTITLEMENTS: Config/Tunr-CarPlay.entitlements` (staat als commentaar klaar) (aanvragen via developer.apple.com/contact/carplay).
- Bundle-/application-id: `nl.lrvdlinden.tunr`. Apple Team ID: `EU3UY476T6` (automatisch ondertekenen).
- Bij elke build:
  - een item in `docs/changelog.json` (per punt `type` = `new`/`improved`/`fixed`, `platforms` uit `ios`, `ipados`, `macos`, `tvos`, `carplay`, `android`, `androidtv`, `web`, en tekst in `nl` en `en`);
  - `python3 tools/make_changelog.py` (maakt `CHANGELOG.md` en `website/assets/changelog.json`);
  - README en screenshots bijwerken als schermen veranderen (`python3 tools/make_screenshots.py`).
- **Xcode-zip bij elke Apple-build**: het complete Xcode-project als `versions/apple/<versie>/build-<N>/Tunr-<versie>-build<N>-Xcode.zip` (uitpakken → map `Tunr` → `Tunr.xcodeproj` openen) in de repo én als GitHub-release `apple-v<versie>-build<N>`. De workflow *Apple* doet dat automatisch zodra iOS, tvOS en macOS slagen (alleen als die build nog niet bestaat). Lever de zip daarnaast ook in de chat.
- **APK bij elke Android-build**: `versions/android/<versie>/build-<N>/Tunr-<versie>-build<N>.apk` in de repo én als GitHub-release `android-v<versie>-build<N>` (downloaden vanaf GitHub). De workflow *Android* doet dat automatisch. Ondertekenen met de release-sleutel uit de secrets `TUNR_KEYSTORE_BASE64`, `TUNR_KEYSTORE_PASSWORD`, `TUNR_KEY_ALIAS`; zonder secrets met `android/ci-debug.keystore`.
- Geen geheime sleutels in de repo. De app gebruikt alleen openbare, sleutelloze bronnen:
  - zenders: **Radio Browser** (community-database, `api.radio-browser.info`), altijd met een eigen User-Agent `Tunr/1.0.0`;
  - albumhoezen bij "nu speelt": **iTunes Search API** (zonder sleutel).
- Website-FTP: secrets `FTP_SERVER`, `FTP_USERNAME`, `FTP_PASSWORD` (optioneel `FTP_DIR`). Zonder secrets slaat de workflow de upload over.
- De naam "Tunr" is een werknaam en staat op één plek per platform (`apple/Shared/App/Brand.swift`, `android/.../Brand.kt`, `website/assets/js/brand.js`) plus teksten; zoek-en-vervang op `Tunr` volstaat bij een nieuwe naam.

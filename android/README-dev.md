# Tunr voor Android: ontwikkelen

Eén APK voor telefoon, tablet, Android TV / Google TV / Fire TV en Android Auto.

## Openen

1. Open de map `android/` (niet de hele repo) in **Android Studio** (Ladybug of nieuwer, JDK 17).
2. Laat Gradle synchroniseren (Gradle 8.11.1 via de wrapper, AGP 8.7.3, Kotlin 2.1.0).
3. Kies de configuratie `app` en een toestel of emulator (telefoon, tablet of Android TV).

Vanaf de opdrachtregel:

```bash
cd android
./gradlew :app:assembleDebug      # app/build/outputs/apk/debug/app-debug.apk
./gradlew :app:assembleRelease    # met eigen sleutel als die is ingesteld, anders de debug-sleutel
```

## Versie en build

- Versie blijft `1.0.0` (`TUNR_VERSION`), alleen `TUNR_BUILD` in `gradle.properties` gaat omhoog.
- Bij elke build een item in `docs/changelog.json` (zie `CLAUDE.md`).

## Release-sleutel (optioneel)

In `android/local.properties` (staat in `.gitignore`) of als omgevingsvariabelen:

```
TUNR_KEYSTORE=/pad/naar/tunr.jks
TUNR_KEYSTORE_PASSWORD=...
TUNR_KEY_ALIAS=tunr
TUNR_KEY_PASSWORD=...
```

APK's en sleutels nooit in de repo of als openbare release: de repo is openbaar.

## Structuur (`app/src/main/java/nl/lrvdlinden/tunr`)

| Map / bestand | Inhoud |
|---|---|
| `Brand.kt` | Naam, User-Agent, website. Eén plek voor de werknaam "Tunr". |
| `data/` | Radio Browser-client (servers, cache), modellen, iTunes-albumhoezen, bibliotheek (favorieten, recent, instellingen) |
| `player/` | `PlaybackService` (Media3 `MediaLibraryService`: melding, vergrendelscherm, Android Auto) en `RadioController` |
| `ui/` | Thema, componenten en schermen (Compose). Tv-indeling met D-pad-focus als het toestel een tv is. |

## Testen

- **Android TV**: emulator met een TV-image; de app staat in de leanback-launcher met de banner.
- **Android Auto**: Desktop Head Unit (DHU) uit de SDK Manager; zet in de Android Auto-app de ontwikkelaarsopties aan en "Onbekende bronnen".
- **Kaart**: tegels van CARTO (`basemaps.cartocdn.com`), attributie staat altijd zichtbaar.

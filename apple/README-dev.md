# Tunr voor Apple: ontwikkelen

Eén Xcode-project met **één multiplatform-target `Tunr`** voor iPhone, iPad, Mac (native macOS, geen Catalyst) en Apple TV, plus een CarPlay-scene in de iOS-build.

## Openen

1. Clone de repo.
2. Open `apple/Tunr.xcodeproj`. Dit project staat in de repo en wordt bij elke push door de workflow *Apple* opnieuw gemaakt uit `apple/project.yml`.
3. Kies bovenin het schema **Tunr** en als bestemming een iPhone, iPad, *My Mac* of Apple TV, en druk op Run.

Ondertekenen gaat automatisch met team `EU3UY476T6`.

## Projectinstellingen wijzigen

Wijzig niets in Xcode zelf: dat wordt bij de volgende generatie overschreven. Pas `apple/project.yml` aan en draai:

```sh
brew install xcodegen   # eenmalig
cd apple
xcodegen generate
```

- Versie blijft `1.0.0` (`MARKETING_VERSION`); alleen `CURRENT_PROJECT_VERSION` gaat omhoog.
- Info.plist per platform: `Config/Info-iOS.plist`, `Config/Info-tvOS.plist`, `Config/Info-macOS.plist` (gekozen via `INFOPLIST_FILE[sdk=…]`).
- Entitlements per platform: `Config/Tunr-iOS.entitlements`, `Config/Tunr-tvOS.entitlements`, `Config/Tunr-macOS.entitlements` (sandbox + netwerk-client). Alle drie gebruiken dezelfde iCloud key-value-store, zodat favorieten en recent tussen apparaten gedeeld worden.

## Mappen

| Map | Inhoud |
|---|---|
| `Shared/App` | `TunrApp` (@main, Mac-menu *Afspelen*, Settings-scene), `AppState`, navigatie, `Brand` (naam, user-agent, links) |
| `Shared/API` | Radio Browser-client (serverkeuze, cache, tolerant decoderen) en de iTunes-albumhoes |
| `Shared/Models` | `Station`, `Country`, `RegionState`, `LanguageInfo`, `Genre` |
| `Shared/Storage` | `Library`: favorieten, recent, zoekgeschiedenis, land en regio (UserDefaults + iCloud) |
| `Shared/Player` | `RadioPlayer`: AVPlayer, ICY-titels, Now Playing, bediening op afstand, slaaptimer |
| `Shared/UI` | Huisstijl (`Theme`), componenten en schermen |
| `Shared/CarPlay` | `CarPlaySceneDelegate` (alleen iOS) |
| `Shared/Resources` | `Localizable.strings` (en, nl) en `tunr_tune.m4a` |
| `Shared/Assets.xcassets` | Iconen (gemaakt met `tools/make_icons.py`, niet met de hand wijzigen) |

Platformverschillen staan in de code onder `#if os(iOS)`, `os(tvOS)` en `os(macOS)`.

## Teksten

Alle teksten gaan via `L("sleutel")` en staan in `Shared/Resources/en.lproj/Localizable.strings` en `nl.lproj/Localizable.strings`. Voeg een nieuwe sleutel altijd in **beide** bestanden toe. De taal is in de app te kiezen (Instellingen → Taal); standaard volgt de app de systeemtaal, met Engels als terugval.

## CarPlay

De code en de scene (`CPTemplateApplicationSceneSessionRoleApplication` in `Config/Info-iOS.plist`) zitten erin. Op een echt toestel werkt CarPlay pas met de entitlement `com.apple.developer.carplay-audio`. Die vraag je aan via developer.apple.com/contact/carplay. Zonder de entitlement bouwt en draait de app gewoon; alleen verschijnt hij niet in CarPlay.

Zodra Apple de entitlement heeft toegekend, zet je in `project.yml` bij de target-instellingen:

```yaml
TUNR_CARPLAY: "YES"
TUNR_IOS_ENTITLEMENTS: Config/Tunr-CarPlay.entitlements
```

Draai daarna `xcodegen generate`. Testen kan ook zonder entitlement, in de simulator via *I/O → External Displays → CarPlay*.

## Controle-build (zoals de CI)

```sh
cd apple
xcodebuild build -project Tunr.xcodeproj -scheme Tunr -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Tunr.xcodeproj -scheme Tunr -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Tunr.xcodeproj -scheme Tunr -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
```

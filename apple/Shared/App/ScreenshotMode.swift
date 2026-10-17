import SwiftUI
#if os(macOS)
import AppKit
#endif

/// App Store-schermafbeeldingen (workflow *App Store media*, `.github/workflows/appstore-media.yml`).
/// Start met `-TunrScreenshot <scène>` (bv. `xcrun simctl launch … nl.lrvdlinden.tunr -TunrScreenshot player`).
/// Dan: geen intro/tune, Engels, land Nederland zonder landkeuze, geen gebruiksping, geen Live Activity,
/// niets naar iCloud of UserDefaults (favorieten alleen in het geheugen) en meteen de gevraagde scène.
/// Zonder dat argument doet dit niets (ook veilig in een release-build).
enum ScreenshotMode {
    enum Scene: String, CaseIterable {
        case discover, browse, map, search, podcasts, player, library
    }

    /// De gevraagde scène, of nil (gewone start)
    static let scene: Scene? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-TunrScreenshot") else { return nil }
        let value = i + 1 < args.count ? args[i + 1].lowercased() : ""
        return Scene(rawValue: value) ?? .discover
    }()

    static var isActive: Bool { scene != nil }

    static let countryCode = "NL"
    static let countryName = "The Netherlands"
    /// Zoekterm voor de scène `search`
    static let searchQuery = "jazz"
    /// Zender voor de scène `player` (eerste treffer in NL; anders de populairste zender)
    static let playerStation = "Qmusic"
    /// Aantal favorieten (alleen in het geheugen)
    static let favoriteCount = 6

    /// Startzoekterm voor Zoeken
    static var initialSearch: String { scene == .search ? searchQuery : "" }

    /// Tabblad waarop de app opent
    static var tab: AppTab {
        switch scene {
        case .browse, .podcasts: return .browse
        case .map: return .map
        case .search: return .search
        case .library: return .library
        default: return .discover
        }
    }

    /// Bestemmingen die bij het openen al op de navigatiestapel van een tabblad staan
    static func initialRoutes(for tab: AppTab) -> [Route] {
        if scene == .podcasts, tab == .browse { return [.podcasts] }
        return []
    }

    /// Kaart: Europa (met Nederland) in beeld
    static var mapRegionIsEurope: Bool { scene == .map }

    /// Gegevens ophalen en de scène klaarzetten (live van Radio Browser; ~5–10 s)
    @MainActor static func prepare(app: AppState) {
        guard let scene else { return }
        Library.shared.applyScreenshotCountry(code: countryCode, name: countryName)
        if scene == .map { app.mapWantsWorld = true }
        #if os(macOS)
        sizeMainWindow()
        #endif
        Task { @MainActor in
            let api = RadioBrowser.shared
            let popular = (try? await api.popular(country: countryCode, limit: 60)) ?? []
            // favorieten (alleen in het geheugen): populaire zenders met een logo
            let withLogo = popular.filter { !$0.favicon.isEmpty }
            let favs = Array((withLogo.count >= favoriteCount ? withLogo : popular).prefix(favoriteCount))
            Library.shared.setScreenshotFavorites(favs)

            if scene == .player {
                let found = (try? await api.search(name: playerStation, country: countryCode)) ?? []
                let pick = found.first(where: { $0.name.localizedCaseInsensitiveContains(playerStation) && $0.streamURL != nil })
                    ?? popular.first(where: { $0.streamURL != nil })
                if let s = pick {
                    RadioPlayer.shared.play(s, queue: popular.isEmpty ? [s] : popular)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    app.showPlayer = true
                }
            }
        }
    }

    #if os(macOS)
    /// Hoofdvenster op 1440 × 900 punten (2880 × 1800 op een Retina-scherm), midden op het scherm
    @MainActor private static func sizeMainWindow() {
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let w = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.contentView != nil }) else { continue }
                w.setContentSize(NSSize(width: 1440, height: 900))
                w.center()
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                selfCaptureIfAsked(w)
                return
            }
        }
    }

    /// Zonder schermopname-toestemming (CI): de app tekent zijn eigen venster op 2× in een PNG.
    /// Alleen als `TUNR_SCREENSHOT_OUT` (pad) is gezet; wacht `TUNR_SCREENSHOT_DELAY` seconden (standaard 14).
    @MainActor private static func selfCaptureIfAsked(_ window: NSWindow) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["TUNR_SCREENSHOT_OUT"], !path.isEmpty else { return }
        let delay = Double(env["TUNR_SCREENSHOT_DELAY"] ?? "") ?? 14
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let view = window.contentView?.superview ?? window.contentView else { return }
            let rect = view.bounds
            let scale: CGFloat = 2
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * scale),
                                             pixelsHigh: Int(rect.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = rect.size
            view.cacheDisplay(in: rect, to: rep)
            // het blad (speler) is een eigen venster boven het hoofdvenster: dat erbij tekenen
            if let sheet = window.attachedSheet, let sv = sheet.contentView?.superview ?? sheet.contentView,
               let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                // blad midden bovenaan het venster (zoals macOS het toont)
                let sr = sv.bounds
                if let srep = sv.bitmapImageRepForCachingDisplay(in: sr) {
                    sv.cacheDisplay(in: sr, to: srep)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = ctx
                    NSColor.black.withAlphaComponent(0.25).setFill()
                    rect.fill(using: .sourceOver)
                    let titlebar = rect.height - window.contentLayoutRect.height
                    let origin = NSPoint(x: (rect.width - sr.width) / 2, y: max(0, rect.height - sr.height - titlebar))
                    _ = srep.draw(in: NSRect(origin: origin, size: sr.size))
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
    #endif
}

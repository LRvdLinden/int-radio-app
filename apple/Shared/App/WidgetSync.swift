#if os(iOS) || os(macOS)
import Foundation
import Combine
import WidgetKit
import ImageIO
import UniformTypeIdentifiers

/// Houdt de widgets bij (alleen de app, niet de extensie): schrijft bij elke wijziging van de speler, de
/// favorieten of recent een snapshot naar de App Group (WidgetBridge), maakt verkleinde logo's en laat WidgetKit
/// de widgets opnieuw tekenen (hooguit eens per 1,5 s).
@MainActor
final class WidgetSync {
    static let shared = WidgetSync()

    private var bag = Set<AnyCancellable>()
    private var started = false
    private var lastSnapshot: WidgetSnapshot?
    private var reloadTask: Task<Void, Never>?
    private var lastReload = Date.distantPast
    private var logoTask: Task<Void, Never>?
    /// Logo's die deze sessie niet te laden waren (niet steeds opnieuw proberen)
    private var failedLogos = Set<String>()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        TunrIntentHandler.ensureAppHandler()
        let p = RadioPlayer.shared
        Publishers.CombineLatest4(p.$station, p.$state, p.$nowPlaying, p.$episode)
            .map { _ in () }
            .merge(with: Library.shared.changed)
            .merge(with: Localizer.shared.$language.map { _ in () })
            // @Published meldt vóór de wijziging: even wachten, dan staat alles goed (en wordt het samengevoegd)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.update() } }
            .store(in: &bag)
        update()
        handlePendingCommand()
    }

    /// Snapshot opnieuw opbouwen en (als er iets veranderd is) bewaren en de widgets bijwerken
    func update() {
        let p = RadioPlayer.shared
        let lib = Library.shared
        var snap = WidgetBridge.load()

        if let s = p.station, p.episode == nil {
            let parts = ArtworkLookup.split(p.nowPlaying)
            snap.nowPlaying = WidgetNowPlaying(station: Self.widgetStation(s), isPlaying: p.isPlaying,
                                              title: parts?.title ?? p.nowPlaying, artist: parts?.artist ?? "")
        } else if var np = snap.nowPlaying {
            // gestopt of een aflevering: de laatste zender blijft staan, gepauzeerd
            np.isPlaying = false
            np.title = ""
            np.artist = ""
            snap.nowPlaying = np
        } else if let last = lib.recents.first {
            snap.nowPlaying = WidgetNowPlaying(station: Self.widgetStation(last), isPlaying: false, title: "", artist: "")
        }
        snap.favorites = lib.favorites.prefix(WidgetBridge.maxStations).map(Self.widgetStation)
        snap.recents = lib.recents.prefix(WidgetBridge.maxStations).map(Self.widgetStation)
        snap.language = Localizer.shared.language

        guard snap != lastSnapshot else { return }
        lastSnapshot = snap
        WidgetBridge.save(snap)
        scheduleReload()
        refreshLogos(for: snap)
    }

    /// Opdracht die een widget achterliet terwijl de app niet draaide (terugval, zie TunrIntents.swift)
    func handlePendingCommand() {
        guard let command = WidgetBridge.takePendingCommand() else { return }
        TunrIntentHandler.ensureAppHandler()
        guard let handler = TunrIntentHandler.shared else { return }
        Task {
            switch command {
            case "toggle": await handler.togglePlayback()
            case "play": await handler.setPlaying(true)
            case "pause": await handler.setPlaying(false)
            case "stop": await handler.stopPlayback()
            default:
                if command.hasPrefix("play:") {
                    await handler.playStation(id: String(command.dropFirst(5)))
                }
            }
        }
    }

    static func widgetStation(_ s: Station) -> WidgetStation {
        WidgetStation(id: s.id, name: s.displayName, country: s.country, countryCode: s.countryCode,
                      logoURL: s.logoURL?.absoluteString)
    }

    // MARK: Opnieuw tekenen (gesmoord)

    private func scheduleReload() {
        guard reloadTask == nil else { return }   // er staat er al een klaar; die neemt de nieuwste stand mee
        let wait = max(0, 1.5 - Date().timeIntervalSince(lastReload))
        reloadTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard let self else { return }
            self.reloadTask = nil
            self.lastReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
            #if os(iOS)
            if #available(iOS 18.0, *) {
                ControlCenter.shared.reloadControls(ofKind: WidgetKind.control)
            }
            #endif
        }
    }

    // MARK: Logo's

    private func refreshLogos(for snap: WidgetSnapshot) {
        var wanted: [WidgetStation] = []
        var seen = Set<String>()
        let all = (snap.nowPlaying.map { [$0.station] } ?? []) + snap.favorites + snap.recents
        for s in all where !seen.contains(s.id) {
            seen.insert(s.id)
            wanted.append(s)
        }
        let missing = wanted.filter { s in
            s.logoURL != nil && !failedLogos.contains(s.id) && !WidgetBridge.hasLogo(for: s.id)
        }
        let keep = seen
        logoTask?.cancel()
        logoTask = Task { [weak self] in
            var added: [String] = []
            for s in missing {
                if Task.isCancelled { return }
                guard let raw = s.logoURL, let url = URL(string: raw) else { continue }
                if let png = await WidgetLogoMaker.makePNG(from: url) {
                    WidgetBridge.writeLogo(png, for: s.id)
                    added.append(s.id)
                } else {
                    self?.failedLogos.insert(s.id)
                }
            }
            if Task.isCancelled { return }
            WidgetBridge.removeLogos(except: keep)
            guard let self, !added.isEmpty else { return }
            self.scheduleReload()
            #if os(iOS) && canImport(ActivityKit)
            LiveActivityController.shared.logosChanged(added)
            #endif
        }
    }
}

/// Download + verkleinen naar max. ~120 px (PNG) met ImageIO; werkt op iOS en macOS.
enum WidgetLogoMaker {
    static func makePNG(from url: URL, maxPixel: Int = 120) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return downscale(data, maxPixel: maxPixel)
    }

    static func downscale(_ data: Data, maxPixel: Int) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }
        // .ico e.d. bevatten meerdere formaten: het grootste nemen
        var best = 0
        var bestWidth = 0
        for i in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let w = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
            if w > bestWidth {
                bestWidth = w
                best = i
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, best, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

// MARK: - Intents in de app

/// Voert de App Intents van de widgets, het Bedieningspaneel en de Live Activity uit met de speler van de app.
@MainActor
final class AppIntentHandler: TunrIntentHandling {
    func playStation(id: String) async {
        let player = RadioPlayer.shared
        let lib = Library.shared
        if let s = player.station, s.id == id, player.episode == nil {
            if !player.isPlaying { player.resume() }
            return
        }
        if let s = lib.favorites.first(where: { $0.id == id }) {
            player.play(s, queue: lib.favorites)
            return
        }
        if let s = lib.recents.first(where: { $0.id == id }) {
            player.play(s, queue: lib.recents)
            return
        }
        // niet (meer) in de bibliotheek: opzoeken bij Radio Browser
        if let s = try? await RadioBrowser.shared.byUUIDs([id]).first {
            player.play(s, queue: [s])
        }
    }

    func togglePlayback() async {
        let player = RadioPlayer.shared
        if player.hasMedia {
            player.toggle()
            return
        }
        // niets geladen (app net op de achtergrond gestart): de zender uit de widget, anders de laatste
        if let id = WidgetBridge.load().nowPlaying?.station.id {
            await playStation(id: id)
        } else {
            player.playLastStation()
        }
    }

    func setPlaying(_ playing: Bool) async {
        let player = RadioPlayer.shared
        if playing {
            if player.hasMedia {
                if !player.isPlaying { player.resume() }
            } else {
                await togglePlayback()
            }
        } else if player.isPlaying {
            player.pause()
        }
    }

    func stopPlayback() async {
        RadioPlayer.shared.stop()
    }
}

extension TunrIntentHandler {
    /// De app-implementatie registreren (ook als het systeem de app alleen voor een intent start)
    static func ensureAppHandler() {
        if shared == nil { shared = AppIntentHandler() }
    }
}

// MARK: - Deep links (tunr://)

/// `tunr://station/<stationuuid>` = afspelen en de speler tonen, `tunr://player` = speler tonen, `tunr://open` = app
enum TunrDeepLink {
    @MainActor static func handle(_ url: URL, app: AppState) {
        guard url.scheme?.lowercased() == "tunr" else { return }
        switch url.host?.lowercased() {
        case "station":
            let id = url.pathComponents.first(where: { $0 != "/" }) ?? ""
            guard !id.isEmpty else { return }
            TunrIntentHandler.ensureAppHandler()
            Task {
                await TunrIntentHandler.shared?.playStation(id: id)
                app.showPlayer = RadioPlayer.shared.hasMedia
            }
        case "player":
            if RadioPlayer.shared.hasMedia { app.showPlayer = true }
        default:
            break
        }
    }
}
#endif

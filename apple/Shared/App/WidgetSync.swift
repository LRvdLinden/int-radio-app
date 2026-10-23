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
    /// zender-id → zender, voor de logo-bronnen (App Store-icoon, Google, favicon, DuckDuckGo; zie LogoSources)
    private var logoStations: [String: Station] = [:]
    /// Albumhoes die nu geladen wordt (URL), zodat dezelfde niet twee keer tegelijk wordt opgehaald
    private var coverLoading: URL?

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
            .merge(with: p.$artworkURL.map { _ in () })
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
                                              title: parts?.title ?? p.nowPlaying, artist: parts?.artist ?? "",
                                              coverFile: currentCoverFile())
        } else if var np = snap.nowPlaying {
            // gestopt of een aflevering: de laatste zender blijft staan, gepauzeerd
            np.isPlaying = false
            np.title = ""
            np.artist = ""
            np.coverFile = nil
            snap.nowPlaying = np
        } else if let last = lib.recents.first {
            snap.nowPlaying = WidgetNowPlaying(station: Self.widgetStation(last), isPlaying: false, title: "", artist: "")
        }
        snap.favorites = lib.favorites.prefix(WidgetBridge.maxStations).map(Self.widgetStation)
        snap.recents = lib.recents.prefix(WidgetBridge.maxStations).map(Self.widgetStation)
        for st in [p.station].compactMap({ $0 }) + lib.favorites.prefix(WidgetBridge.maxStations)
            + lib.recents.prefix(WidgetBridge.maxStations) {
            logoStations[st.id] = st
        }
        snap.language = Localizer.shared.language

        guard snap != lastSnapshot else { return }
        lastSnapshot = snap
        WidgetBridge.save(snap)
        scheduleReload()
        refreshLogos(for: snap)
    }

    // MARK: Albumhoes

    /// Bestandsnaam van de hoes van het huidige nummer als die al in de App Group staat; anders nil en (één keer)
    /// ophalen. Daarna worden widgets en Live Activity opnieuw bijgewerkt.
    func currentCoverFile() -> String? {
        let p = RadioPlayer.shared
        guard p.episode == nil, !p.nowPlaying.isEmpty, let url = p.artworkURL else { return nil }
        let name = WidgetBridge.coverFileName(for: url.absoluteString)
        if WidgetBridge.hasFile(name) { return name }
        guard coverLoading != url else { return nil }
        coverLoading = url
        Task { [weak self] in
            let png = await WidgetLogoMaker.makeCoverPNG(from: url)
            guard let self else { return }
            self.coverLoading = nil
            guard let png, RadioPlayer.shared.artworkURL == url else { return }
            WidgetBridge.writeCover(png, fileName: name)
            self.update()
            #if os(iOS) && canImport(ActivityKit)
            LiveActivityController.shared.sync()
            #endif
        }
        return nil
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
        let stations = logoStations
        let plain: (WidgetStation) -> [URL] = { s in s.logoURL.flatMap { URL(string: $0) }.map { [$0] } ?? [] }
        let missing = wanted.filter { s in
            let possible = stations[s.id].map { LogoSources.mayHaveLogo($0) } ?? !plain(s).isEmpty
            return possible && !failedLogos.contains(s.id) && !WidgetBridge.hasLogo(for: s.id)
        }
        let keep = seen
        logoTask?.cancel()
        logoTask = Task { [weak self] in
            var added: [String] = []
            for s in missing {
                if Task.isCancelled { return }
                let urls: [URL]
                if let st = stations[s.id] {
                    urls = await LogoSources.resolveCandidates(for: st)
                } else {
                    urls = plain(s)
                }
                if let png = await WidgetLogoMaker.makePNG(fromCandidates: urls) {
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

/// Download + vierkant logo van ~120 px (PNG) met ImageIO; werkt op iOS en macOS. Zelfde regels als StationArt
/// (SPEC §1): groot logo vult het vierkant, klein logo gecentreerd (hooguit 2× zijn eigen maat, hooguit 62%) op een
/// effen achtergrond die uit het logo zelf komt (`LogoLook`), nooit opgerekt.
enum WidgetLogoMaker {
    static func makePNG(from url: URL, maxPixel: Int = 120) async -> Data? {
        guard let data = await download(url) else { return nil }
        return render(data, side: maxPixel)
    }

    /// Eerste bron van minstens `LogoSources.goodPixels` (96 px); anders het grootste kleinere logo dat mag
    /// (`LogoSources.acceptableSmall`: Google nooit onder 96, DuckDuckGo niet onder 48).
    static func makePNG(fromCandidates urls: [URL], maxPixel: Int = 120) async -> Data? {
        var best: (data: Data, pixels: Int)?
        for url in urls {
            if Task.isCancelled { return nil }
            guard let data = await download(url) else { continue }
            let size = largestSize(data)
            let pixels = max(size.width, size.height)
            if CGFloat(pixels) >= LogoSources.goodPixels {
                if let png = render(data, side: maxPixel) { return png }
            } else if LogoSources.acceptableSmall(url, pixels: CGFloat(pixels)), pixels > (best?.pixels ?? 0) {
                best = (data, pixels)
            }
        }
        return best.flatMap { render($0.data, side: maxPixel) }
    }

    private static func download(_ url: URL) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 12)
        if !LogoSources.isFallbackService(url) {
            req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return data
    }

    /// Albumhoes: vierkant (midden uitgesneden), `side` px, PNG. Geen LogoLook: een hoes vult altijd de tegel.
    static func makeCoverPNG(from url: URL, side: Int = 240) async -> Data? {
        guard let data = await download(url),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let edge = min(image.width, image.height)
        guard edge > 0, let crop = image.cropping(to: CGRect(x: (image.width - edge) / 2, y: (image.height - edge) / 2,
                                                             width: edge, height: edge)),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let square = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, square, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Breedste afbeelding in de data (pixels; 0 = geen afbeelding)
    static func largestWidth(_ data: Data) -> Int {
        largestSize(data).width
    }

    /// Maat van de breedste afbeelding in de data (pixels; 0 = geen afbeelding)
    static func largestSize(_ data: Data) -> (width: Int, height: Int) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return (0, 0) }
        var widest = (width: 0, height: 0)
        for i in 0..<CGImageSourceGetCount(src) {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let w = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let h = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
            if w > widest.width { widest = (w, h) }
        }
        return widest
    }

    /// Vierkante PNG van `side` px: het logo (grootste formaat in de data, max. 512 px) volgens `LogoLook`
    static func render(_ data: Data, side: Int) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }
        // .ico e.d. bevatten meerdere formaten: het grootste nemen
        var best = 0
        var bestWidth = 0
        var bestHeight = 0
        for i in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let w = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
            if w > bestWidth {
                bestWidth = w
                bestHeight = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
                best = i
            }
        }
        // grote afbeeldingen eerst verkleinen (geheugen); kleine blijven op hun eigen maat
        let longest = max(bestWidth, bestHeight)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(512, longest > 0 ? longest : 512)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, best, options as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(src, best, nil) else { return nil }
        // maat van het origineel (niet van de verkleinde kopie) bepaalt groot/klein
        let props = CGImageSourceCopyPropertiesAtIndex(src, best, nil) as? [CFString: Any]
        let ow = (props?[kCGImagePropertyPixelWidth] as? Int) ?? image.width
        let oh = (props?[kCGImagePropertyPixelHeight] as? Int) ?? image.height
        let look = LogoLook.analyze(image, pixelSize: CGSize(width: ow, height: oh))
        guard let square = look.compose(image, side: side) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, square, nil)
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

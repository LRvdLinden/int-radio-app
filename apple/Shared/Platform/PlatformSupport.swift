import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// Kleine vertalingen tussen UIKit (iPhone, iPad, Apple TV) en AppKit (Mac).

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

/// Soort apparaat. Wordt één keer bij het starten op de hoofdthread bepaald (`configure()` in TunrApp.init),
/// zodat het overal (ook buiten de main actor) gelezen kan worden.
enum DeviceKind {
    private(set) static var isPhone = false
    private(set) static var isPad = false

    @MainActor static func configure() {
        #if os(iOS)
        isPhone = UIDevice.current.userInterfaceIdiom == .phone
        isPad = UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    static var isTV: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}

/// Lichte trilling bij tikken (alleen iPhone/iPad)
enum Haptics {
    @MainActor static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    @MainActor static func soft() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    @MainActor static func rigid() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }

    @MainActor static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

/// Afbeeldingen voor Now Playing / CarPlay (logo of hoes), met een eenvoudige geheugencache.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, PlatformImage>()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 12
        return URLSession(configuration: c)
    }()

    func cached(_ url: URL) -> PlatformImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> PlatformImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        var req = URLRequest(url: url)
        // eigen User-Agent niet naar de favicondiensten van Google/DuckDuckGo
        if !LogoSources.isFallbackService(url) {
            req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
        }
        guard let (data, _) = try? await session.data(for: req), let img = PlatformImage(data: data) else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}

// MARK: - Zenderlogo's met terugval

/// Waar een zenderlogo vandaan kan komen, in volgorde (SPEC §1, zelfde als Android en de webspeler):
/// 1. het app-icoon uit de App Store, uit de vaste tabel van tunr.online (`IconMap`);
/// 2. Google-favicondienst op het domein van de homepage (`sz=256`), alleen vanaf `minServicePixels` (96 px:
///    dan is het meestal het apple-touch-icon van de site);
/// 3. `favicon` uit Radio Browser (http → eerst https, daarna het origineel);
/// 4. DuckDuckGo-favicondienst (`ip3/<host>.ico`), vanaf `minPixels`;
/// 5. (geen URL) het monogram/verloop van StationArt.
/// Een te klein favicon of app-icoon wordt alleen gebruikt als niets anders werkt; van de diensten nooit.
enum LogoSources {
    static let minPixels: CGFloat = 48
    /// Google: kleiner dan dit is een gewoon favicon (of de globe van 16 px), niet het mooie icoon van de site
    static let minServicePixels: CGFloat = 96

    /// Alle bronnen in volgorde, met het App Store-icoon alleen als de tabel van het land al geladen is.
    /// Voor laden: `resolveCandidates(for:)` (haalt de tabel zo nodig eerst op).
    static func candidates(for s: Station) -> [URL] {
        build(s, appIcon: IconMap.shared.cachedURL(for: s))
    }

    /// Zelfde als `candidates(for:)`, maar wacht eerst op de icoontabel van het land van de zender
    static func resolveCandidates(for s: Station) async -> [URL] {
        let icon = await IconMap.shared.url(for: s)
        return build(s, appIcon: icon)
    }

    /// Kan deze zender een logo hebben? (zo niet: meteen het monogram, zonder te laden)
    static func mayHaveLogo(_ s: Station) -> Bool {
        !candidates(for: s).isEmpty || !IconMap.shared.knownAbsent(s)
    }

    private static func build(_ s: Station, appIcon: URL?) -> [URL] {
        var out: [URL] = []
        if let appIcon { out.append(appIcon) }
        let host = host(fromHomepage: s.homepage)
        if let host, let g = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=256") { out.append(g) }
        let fav = s.favicon.trimmingCharacters(in: .whitespacesAndNewlines)
        if fav.lowercased().hasPrefix("http://") {
            if let https = URL(string: "https://" + String(fav.dropFirst(7))) { out.append(https) }
            if let http = URL(string: fav) { out.append(http) }
        } else if fav.lowercased().hasPrefix("https://"), let u = URL(string: fav) {
            out.append(u)
        }
        if let host, let d = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") { out.append(d) }
        var seen = Set<URL>()
        return out.filter { seen.insert($0).inserted }
    }

    /// Domein van de homepage ("https://www.npo.nl/radio2" → "www.npo.nl"); nil als er geen bruikbaar domein is
    static func host(fromHomepage homepage: String) -> String? {
        var h = homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }
        if !h.contains("://") { h = "http://" + h }
        guard let host = URL(string: h)?.host?.lowercased(), host.contains("."),
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return host
    }

    /// Google- of DuckDuckGo-favicondienst (dan geldt de minimummaat strikt, en geen eigen User-Agent)
    static func isFallbackService(_ url: URL) -> Bool {
        let h = url.host?.lowercased() ?? ""
        return h == "www.google.com" || h == "icons.duckduckgo.com"
    }

    /// Minimale breedte in pixels voor deze bron (Google 96, de rest 48)
    static func requiredPixels(for url: URL) -> CGFloat {
        url.host?.lowercased() == "www.google.com" ? minServicePixels : minPixels
    }

    /// Breedte in pixels (iPhone/iPad/tv: UIImage, Mac: grootste representatie)
    static func pixelWidth(_ img: PlatformImage) -> CGFloat {
        #if os(macOS)
        let px = img.representations.map(\.pixelsWide).max() ?? 0
        return px > 0 ? CGFloat(px) : img.size.width
        #else
        return img.size.width * img.scale
        #endif
    }
}

/// App Store-iconen per land: `https://tunr.online/assets/data/icons/<CC>.json` (zenders zonder land: `_world.json`),
/// gemaakt door tools/make_station_icons.py (workflow Icons). Inhoud: `{"u": {stationuuid: url}, "n": {naamsleutel: url}}`.
/// Wordt per land pas opgehaald als het nodig is, en bewaard in het geheugen en in Caches/icons (7 dagen geldig;
/// zonder netwerk wordt een oudere kopie gebruikt).
final class IconMap: @unchecked Sendable {
    static let shared = IconMap()
    static let ttl: TimeInterval = 7 * 24 * 3600
    static let base = "https://tunr.online/assets/data/icons/"

    private typealias Table = [String: [String: String]]
    private let lock = NSLock()
    private var tables: [String: Table] = [:]
    /// na een mislukte download pas na dit tijdstip opnieuw proberen
    private var retryAfter: [String: Date] = [:]
    private var loading: [String: Task<Void, Never>] = [:]

    /// Naamsleutel, gelijk aan `norm_key` in tools/make_station_icons.py (en Android/web): NFKD, accenten weg,
    /// kleine letters, alleen letters en decimale cijfers
    static func key(_ name: String) -> String {
        let folded = String(String.UnicodeScalarView(
            name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }
        )).lowercased()
        let kept = folded.unicodeScalars.filter { sc in
            switch sc.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
                return true
            default:
                return false
            }
        }
        return String(String.UnicodeScalarView(kept))
    }

    /// Bestandsnaam van de tabel voor deze zender ("NL" of "_world")
    static func file(for s: Station) -> String {
        let cc = s.countryCode.trimmingCharacters(in: .whitespaces).uppercased()
        let ok = cc.count == 2 && cc.unicodeScalars.allSatisfy { $0.value >= 65 && $0.value <= 90 }
        return ok ? cc : "_world"
    }

    /// Icoon-URL als de tabel van het land al geladen is (zonder netwerk)
    func cachedURL(for s: Station) -> URL? {
        let file = Self.file(for: s)
        guard let t = lock.withLock({ tables[file] }) else { return nil }
        let raw = t["u"]?[s.id] ?? t["n"]?[Self.key(s.name)]
        guard let raw, raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }

    /// Weten we zeker dat er geen App Store-icoon is? (tabel geladen zonder deze zender, of laden net mislukt)
    func knownAbsent(_ s: Station) -> Bool {
        let file = Self.file(for: s)
        let state: (loaded: Bool, waiting: Bool) = lock.withLock {
            (tables[file] != nil, (retryAfter[file] ?? .distantPast) > Date())
        }
        if state.loaded { return cachedURL(for: s) == nil }
        return state.waiting
    }

    /// Icoon-URL voor de zender (haalt de tabel van het land zo nodig eerst op)
    func url(for s: Station) async -> URL? {
        await ensureLoaded(Self.file(for: s))
        return cachedURL(for: s)
    }

    func ensureLoaded(_ file: String) async {
        let task: Task<Void, Never>? = lock.withLock {
            if tables[file] != nil || (retryAfter[file] ?? .distantPast) > Date() { return nil }
            if let t = loading[file] { return t }
            let t = Task.detached(priority: .utility) { await IconMap.shared.fetch(file) }
            loading[file] = t
            return t
        }
        if let task { await task.value }
    }

    private static var diskDir: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func decode(_ data: Data) -> Table? {
        try? JSONDecoder().decode(Table.self, from: data)
    }

    private func fetch(_ file: String) async {
        let disk = Self.diskDir?.appendingPathComponent(file + ".json")
        var table: Table?
        var fresh = false
        if let disk, let data = try? Data(contentsOf: disk), let t = Self.decode(data) {
            table = t
            let mod = (try? FileManager.default.attributesOfItem(atPath: disk.path)[.modificationDate]) as? Date
            fresh = Date().timeIntervalSince(mod ?? .distantPast) < Self.ttl
        }
        if !fresh, let url = URL(string: Self.base + file + ".json") {
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await URLSession.shared.data(for: req),
               let http = response as? HTTPURLResponse {
                if http.statusCode == 200, let t = Self.decode(data) {
                    table = t
                    if let disk { try? data.write(to: disk, options: .atomic) }
                } else if http.statusCode == 404 {
                    // geen tabel voor dit land (nog geen iconen gevonden): leeg, alleen deze sessie
                    table = [:]
                }
            }
        }
        lock.withLock {
            if let table { tables[file] = table } else { retryAfter[file] = Date().addingTimeInterval(600) }
            loading[file] = nil
        }
    }
}

/// Zoekt per zender het eerste logo dat werkt (zie `LogoSources`) en onthoudt dat in het geheugen, net als welke
/// URL's mislukten, zodat er bij scrollen niet steeds opnieuw geprobeerd wordt. De afbeeldingen zelf staan in de
/// cache van ImageLoader (geheugen + URLCache op schijf).
final class LogoResolver: @unchecked Sendable {
    static let shared = LogoResolver()

    private let lock = NSLock()
    /// zender-id → URL die werkt
    private var resolved: [String: URL] = [:]
    /// zenders waarvoor niets werkt (alleen het monogram)
    private var noLogo = Set<String>()
    /// URL's die niet laadden of te klein waren
    private var failed = Set<URL>()

    /// Al gevonden logo (zonder netwerk), voor de eerste weergave
    func cachedImage(for s: Station) -> PlatformImage? {
        guard let url = lock.withLock({ resolved[s.id] }) else { return nil }
        return ImageLoader.shared.cached(url)
    }

    /// Weten we al dat deze zender geen logo heeft?
    func knownMissing(_ s: Station) -> Bool {
        lock.withLock { noLogo.contains(s.id) }
    }

    /// De URL die voor deze zender werkt (laadt zo nodig de kandidaten na elkaar)
    func url(for s: Station) async -> URL? {
        guard await image(for: s) != nil else { return nil }
        return lock.withLock { resolved[s.id] }
    }

    /// Het logo van de zender, of nil (dan het monogram)
    func image(for s: Station) async -> PlatformImage? {
        if let url = lock.withLock({ resolved[s.id] }), let img = ImageLoader.shared.cached(url) { return img }
        if lock.withLock({ noLogo.contains(s.id) }) { return nil }
        let candidates = await LogoSources.resolveCandidates(for: s)
        // een te klein favicon/app-icoon is beter dan niets, maar alleen als de rest ook niets heeft
        var tiny: (URL, PlatformImage)?
        for url in candidates {
            if Task.isCancelled { return nil }
            let service = LogoSources.isFallbackService(url)
            if lock.withLock({ failed.contains(url) }) {
                if !service, tiny == nil, let img = ImageLoader.shared.cached(url) { tiny = (url, img) }
                continue
            }
            guard let img = await ImageLoader.shared.load(url) else {
                if Task.isCancelled { return nil }
                lock.withLock { _ = failed.insert(url) }
                continue
            }
            if LogoSources.pixelWidth(img) >= LogoSources.requiredPixels(for: url) {
                lock.withLock { resolved[s.id] = url }
                return img
            }
            lock.withLock { _ = failed.insert(url) }
            if !service, tiny == nil { tiny = (url, img) }
        }
        if Task.isCancelled { return nil }
        if let tiny {
            lock.withLock { resolved[s.id] = tiny.0 }
            return tiny.1
        }
        lock.withLock { _ = noLogo.insert(s.id) }
        return nil
    }
}

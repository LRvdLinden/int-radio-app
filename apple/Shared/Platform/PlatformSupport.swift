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

/// Waar een zenderlogo vandaan kan komen, in volgorde:
/// 1. `favicon` uit Radio Browser (http → eerst https, daarna het origineel);
/// 2. Google-favicondienst op het domein van de homepage (`sz=256`);
/// 3. DuckDuckGo-favicondienst (`ip3/<host>.ico`);
/// 4. (geen URL) het monogram/verloop van StationArt.
/// Resultaten van de diensten kleiner dan `minPixels` breed tellen als mislukt (Google geeft dan een globe van 16 px).
enum LogoSources {
    static let minPixels: CGFloat = 48

    static func candidates(for s: Station) -> [URL] {
        var out: [URL] = []
        let fav = s.favicon.trimmingCharacters(in: .whitespacesAndNewlines)
        if fav.lowercased().hasPrefix("http://") {
            if let https = URL(string: "https://" + String(fav.dropFirst(7))) { out.append(https) }
            if let http = URL(string: fav) { out.append(http) }
        } else if fav.lowercased().hasPrefix("https://"), let u = URL(string: fav) {
            out.append(u)
        }
        if let host = host(fromHomepage: s.homepage) {
            if let g = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=256") { out.append(g) }
            if let d = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") { out.append(d) }
        }
        return out
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

    /// Google- of DuckDuckGo-favicondienst (dan geldt de minimummaat strikt)
    static func isFallbackService(_ url: URL) -> Bool {
        let h = url.host?.lowercased() ?? ""
        return h == "www.google.com" || h == "icons.duckduckgo.com"
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
        let candidates = LogoSources.candidates(for: s)
        // een te klein favicon is beter dan niets, maar alleen als de diensten ook niets hebben
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
            if LogoSources.pixelWidth(img) >= LogoSources.minPixels {
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

import SwiftUI
import ImageIO
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
        guard let (data, _) = try? await session.data(for: req), let img = Self.decode(data) else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }

    /// .ico e.d. bevatten meerdere formaten: neem het grootste (UIImage pakt anders het eerste, vaak 16 px)
    static func decode(_ data: Data) -> PlatformImage? {
        if let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 1 {
            var best = 0
            var bestWidth = 0
            for i in 0..<CGImageSourceGetCount(src) {
                let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
                let w = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
                if w > bestWidth { bestWidth = w; best = i }
            }
            if let cg = CGImageSourceCreateImageAtIndex(src, best, nil) { return PlatformImage.fromCG(cg) }
        }
        return PlatformImage(data: data)
    }
}

// MARK: - Logo-weergave (maat en achtergrond)

/// Maat en achtergrondkleur van een zenderlogo (SPEC §1). Eén keer per afbeelding berekend en per URL onthouden
/// (`LogoResolver`). Groot logo → vult de tegel (aspect fill); klein logo → gecentreerd, aspect fit, hooguit 2× de
/// eigen pixelmaat en hooguit 62% van de tegel, op een effen achtergrond die bij het logo past.
struct LogoLook: Sendable {
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat
    /// achtergrond (sRGB, 0…1)
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var minSide: CGFloat { min(pixelWidth, pixelHeight) }
    var maxSide: CGFloat { max(pixelWidth, pixelHeight) }
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// Groot genoeg om de hele tegel te vullen? (`tilePixels` = zijde van de tegel in pixels)
    func isLarge(tilePixels: CGFloat) -> Bool {
        minSide >= 0.75 * tilePixels || minSide >= 160
    }

    /// Zijde (pixels) van het vak waarin een klein logo aspect fit getekend wordt
    func smallBox(tilePixels: CGFloat) -> CGFloat {
        max(1, min(2 * maxSide, 0.62 * tilePixels))
    }

    /// Bepaalt de achtergrond uit de randpixels: dekkend → hun gemiddelde kleur (het logo loopt over in zijn eigen
    /// achtergrond); transparant → wit bij een donker/gekleurd logo, Tunr-surface #16161A bij een licht/wit logo.
    static func analyze(_ image: CGImage, pixelSize: CGSize) -> LogoLook {
        let n = 24
        let surface: (CGFloat, CGFloat, CGFloat) = (0x16 / 255.0, 0x16 / 255.0, 0x1A / 255.0)
        var rgb: (CGFloat, CGFloat, CGFloat) = (1, 1, 1)
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let drawn: Bool = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        if drawn {
            // rand: dekkende pixels tellen en middelen
            var edgeTotal = 0, edgeOpaque = 0
            var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0
            // hele logo: lichte pixels tellen
            var solid = 0, light = 0
            for y in 0..<n {
                for x in 0..<n {
                    let i = (y * n + x) * 4
                    let a = CGFloat(px[i + 3]) / 255
                    let r = a > 0 ? min(1, CGFloat(px[i]) / 255 / a) : 0
                    let g = a > 0 ? min(1, CGFloat(px[i + 1]) / 255 / a) : 0
                    let b = a > 0 ? min(1, CGFloat(px[i + 2]) / 255 / a) : 0
                    if x == 0 || y == 0 || x == n - 1 || y == n - 1 {
                        edgeTotal += 1
                        if a >= 0.9 { edgeOpaque += 1; er += r; eg += g; eb += b }
                    }
                    if a >= 0.5 {
                        solid += 1
                        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                        let sat = max(r, g, b) - min(r, g, b)
                        if lum > 0.78 && sat < 0.2 { light += 1 }
                    }
                }
            }
            if edgeTotal > 0, Double(edgeOpaque) >= 0.75 * Double(edgeTotal) {
                let c = CGFloat(edgeOpaque)
                rgb = (er / c, eg / c, eb / c)
            } else if solid > 0, Double(light) > 0.6 * Double(solid) {
                rgb = surface
            }
        }
        return LogoLook(pixelWidth: pixelSize.width, pixelHeight: pixelSize.height, red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// Vierkante afbeelding van `side` pixels met het logo volgens dezelfde regels als de tegel in de app
    /// (CarPlay, Now Playing, widgets en Live Activity).
    func compose(_ image: CGImage, side: Int) -> CGImage? {
        guard side > 0 else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(side)
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        ctx.setFillColor(cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        let w = CGFloat(max(1, image.width)), h = CGFloat(max(1, image.height))
        let rect: CGRect
        if isLarge(tilePixels: s) {
            let k = max(s / w, s / h)
            rect = CGRect(x: (s - w * k) / 2, y: (s - h * k) / 2, width: w * k, height: h * k)
        } else {
            let box = smallBox(tilePixels: s)
            let k = min(box / w, box / h)
            rect = CGRect(x: (s - w * k) / 2, y: (s - h * k) / 2, width: w * k, height: h * k)
        }
        ctx.draw(image, in: rect.integral)
        return ctx.makeImage()
    }
}

/// Zenderlogo met zijn berekende weergave
struct LogoArt {
    let image: PlatformImage
    let look: LogoLook
}

extension PlatformImage {
    /// CGImage in de volle pixelmaat (Mac: grootste representatie)
    var fullCGImage: CGImage? {
        #if os(macOS)
        let size = LogoSources.pixelSize(self)
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return cgImage
        #endif
    }

    /// Afbeelding uit een CGImage (schaal 1)
    static func fromCG(_ cg: CGImage) -> PlatformImage {
        #if os(macOS)
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #else
        return UIImage(cgImage: cg)
        #endif
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
/// De eerste bron van minstens `goodPixels` (96 px) wint. Kleinere logo's worden onthouden en alleen gebruikt als
/// niets beters werkt (het grootste); Google onder 96 px en DuckDuckGo onder 48 px nooit (`acceptableSmall`).
enum LogoSources {
    static let minPixels: CGFloat = 48
    /// Google: kleiner dan dit is een gewoon favicon (of de globe van 16 px), niet het mooie icoon van de site
    static let minServicePixels: CGFloat = 96
    /// Vanaf deze maat (grootste zijde, pixels) is een logo goed genoeg om te stoppen met zoeken
    static let goodPixels: CGFloat = 96

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

    /// Mag een logo van deze maat (grootste zijde, pixels) als terugval gebruikt worden? Google nooit onder 96 px
    /// (dan is het een gewoon favicon of de globe), DuckDuckGo niet onder 48 px, de rest altijd.
    static func acceptableSmall(_ url: URL, pixels: CGFloat) -> Bool {
        guard pixels > 0 else { return false }
        switch url.host?.lowercased() ?? "" {
        case "www.google.com": return pixels >= minServicePixels
        case "icons.duckduckgo.com": return pixels >= minPixels
        default: return true
        }
    }

    /// Breedte in pixels (iPhone/iPad/tv: UIImage, Mac: grootste representatie)
    static func pixelWidth(_ img: PlatformImage) -> CGFloat {
        pixelSize(img).width
    }

    /// Maat in pixels (iPhone/iPad/tv: UIImage, Mac: grootste representatie)
    static func pixelSize(_ img: PlatformImage) -> CGSize {
        #if os(macOS)
        var best = CGSize.zero
        for rep in img.representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
            if CGFloat(rep.pixelsWide) > best.width { best = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
        }
        return best.width > 0 ? best : img.size
        #else
        return CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
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

/// Zoekt per zender het eerste goede logo (zie `LogoSources`) en onthoudt dat in het geheugen, zodat er bij scrollen
/// niet steeds opnieuw geprobeerd wordt; ook welke URL's mislukten en de weergave (`LogoLook`) per URL. De afbeeldingen
/// zelf staan in de cache van ImageLoader (geheugen + URLCache op schijf).
final class LogoResolver: @unchecked Sendable {
    static let shared = LogoResolver()

    private let lock = NSLock()
    /// zender-id → URL die gekozen is
    private var resolved: [String: URL] = [:]
    /// zenders waarvoor niets werkt (alleen het monogram)
    private var noLogo = Set<String>()
    /// URL's die niet laadden
    private var failed = Set<URL>()
    /// URL → maat en achtergrond van het logo
    private var looks: [URL: LogoLook] = [:]

    /// Al gevonden logo (zonder netwerk), voor de eerste weergave
    func cachedImage(for s: Station) -> PlatformImage? {
        cachedArt(for: s)?.image
    }

    /// Al gevonden logo met zijn weergave (zonder netwerk)
    func cachedArt(for s: Station) -> LogoArt? {
        guard let url = lock.withLock({ resolved[s.id] }), let img = ImageLoader.shared.cached(url) else { return nil }
        return art(img, url: url)
    }

    /// Weten we al dat deze zender geen logo heeft?
    func knownMissing(_ s: Station) -> Bool {
        lock.withLock { noLogo.contains(s.id) }
    }

    /// De URL die voor deze zender werkt (laadt zo nodig de kandidaten na elkaar)
    func url(for s: Station) async -> URL? {
        guard await art(for: s) != nil else { return nil }
        return lock.withLock { resolved[s.id] }
    }

    /// Het logo van de zender, of nil (dan het monogram)
    func image(for s: Station) async -> PlatformImage? {
        await art(for: s)?.image
    }

    /// Vierkant beeld van `pixels` px met het logo op zijn eigen achtergrond (CarPlay, Now Playing), of nil
    func composedImage(for s: Station, pixels: Int) async -> PlatformImage? {
        guard let a = await art(for: s), let cg = a.image.fullCGImage,
              let out = a.look.compose(cg, side: pixels) else { return nil }
        return PlatformImage.fromCG(out)
    }

    /// Weergave van een afbeelding (eenmalig berekend per URL)
    private func art(_ img: PlatformImage, url: URL) -> LogoArt {
        if let look = lock.withLock({ looks[url] }) { return LogoArt(image: img, look: look) }
        let size = LogoSources.pixelSize(img)
        let look: LogoLook
        if let cg = img.fullCGImage {
            look = LogoLook.analyze(cg, pixelSize: size)
        } else {
            look = LogoLook(pixelWidth: size.width, pixelHeight: size.height, red: 1, green: 1, blue: 1)
        }
        lock.withLock { looks[url] = look }
        return LogoArt(image: img, look: look)
    }

    /// Het logo van de zender met zijn weergave, of nil (dan het monogram)
    func art(for s: Station) async -> LogoArt? {
        if let url = lock.withLock({ resolved[s.id] }) {
            // al gekozen: alleen opnieuw laden als de afbeelding uit de geheugencache is
            if let img = await ImageLoader.shared.load(url) { return art(img, url: url) }
            if Task.isCancelled { return nil }
            lock.withLock { _ = resolved.removeValue(forKey: s.id) }
        }
        if lock.withLock({ noLogo.contains(s.id) }) { return nil }
        let candidates = await LogoSources.resolveCandidates(for: s)
        // een klein logo is beter dan niets, maar alleen als de rest ook niets beters heeft (dan het grootste)
        var best: (url: URL, image: PlatformImage, pixels: CGFloat)?
        for url in candidates {
            if Task.isCancelled { return nil }
            if lock.withLock({ failed.contains(url) }) { continue }
            guard let img = await ImageLoader.shared.load(url) else {
                if Task.isCancelled { return nil }
                lock.withLock { _ = failed.insert(url) }
                continue
            }
            let size = LogoSources.pixelSize(img)
            let pixels = max(size.width, size.height)
            if pixels >= LogoSources.goodPixels {
                lock.withLock { resolved[s.id] = url }
                return art(img, url: url)
            }
            if LogoSources.acceptableSmall(url, pixels: pixels), pixels > (best?.pixels ?? 0) {
                best = (url, img, pixels)
            }
        }
        if Task.isCancelled { return nil }
        if let best {
            lock.withLock { resolved[s.id] = best.url }
            return art(best.image, url: best.url)
        }
        lock.withLock { _ = noLogo.insert(s.id) }
        return nil
    }
}

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Opslagsleutels van de anonieme statistieken. Bewust lokaal (UserDefaults) en NIET in iCloud:
/// SettingsSync en Library spiegelen alleen hun eigen, vaste lijst sleutels.
enum StatsKey {
    /// Willekeurige UUID per installatie
    static let installID = "stats.installId"
    /// Tijdstip (seconden sinds 1970) van de laatste geslaagde ping
    static let lastPing = "stats.lastPing"
    /// Ooit een CarPlay-scene verbonden (gezet in CarPlaySceneDelegate)
    static let carplayUsed = "stats.carplayUsed"
}

/// Anonieme gebruiksping (tunr-beheer/docs/CONTRACT.md, functie `ping`).
/// Bij het starten en bij terugkomen naar de voorgrond, als de laatste geslaagde ping > 12 uur geleden is.
/// Alleen als `Brand.statsURL` is ingevuld en de instelling "Anonieme gebruiksstatistieken" aan staat.
/// Geen persoonsgegevens: type apparaat, model-id, OS- en app-versie, gekozen land en taal, willekeurig
/// installatienummer. Fouten worden genegeerd.
@MainActor
final class StatsPing {
    static let shared = StatsPing()

    private static let interval: TimeInterval = 12 * 60 * 60
    private let defaults = UserDefaults.standard
    private var inFlight = false

    private init() {}

    /// Staat de instelling aan? (standaard aan)
    var isEnabled: Bool { defaults.object(forKey: SettingsKey.shareStats) as? Bool ?? true }

    func pingIfDue() {
        let base = Brand.statsURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, isEnabled, !inFlight else { return }
        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: StatsKey.lastPing)
        if last > 0, now - last < Self.interval, now >= last { return }

        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: trimmed + "/functions/v1/ping"),
              let body = try? JSONSerialization.data(withJSONObject: payload()) else { return }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(Brand.statsKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        inFlight = true
        Task {
            let ok = await Self.send(request)
            self.inFlight = false
            if ok { self.defaults.set(Date().timeIntervalSince1970, forKey: StatsKey.lastPing) }
        }
    }

    // MARK: Gegevens

    private var installID: String {
        if let id = defaults.string(forKey: StatsKey.installID), UUID(uuidString: id) != nil { return id.lowercased() }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: StatsKey.installID)
        return id
    }

    private func payload() -> [String: Any] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? Brand.version
        let build = Int(info?["CFBundleVersion"] as? String ?? "") ?? 0
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText = os.patchVersion > 0
            ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            : "\(os.majorVersion).\(os.minorVersion)"
        let code = (Library.shared.countryCode ?? "").uppercased()
        let country = code.count == 2 && code.allSatisfy({ $0.isASCII && $0.isLetter }) ? code : ""
        let (platform, device) = Self.platformAndDevice()
        return [
            "id": installID,
            "platform": platform,
            "device": device,
            "model": String(Self.modelIdentifier().prefix(60)),
            "os": osText,
            "version": version,
            "build": min(max(build, 0), 99999),
            "country": country,
            "lang": Localizer.shared.language == "nl" ? "nl" : "en",
            "carplay": defaults.bool(forKey: StatsKey.carplayUsed),
        ]
    }

    private static func platformAndDevice() -> (String, String) {
        #if os(tvOS)
        return ("tvos", "Apple TV")
        #elseif os(macOS)
        return ("macos", "Mac")
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? ("ipados", "iPad") : ("ios", "iPhone")
        #endif
    }

    /// Model-id van het toestel: "iPhone16,2", "AppleTV14,1", op de Mac "Mac14,2" (sysctl hw.model).
    private static func modelIdentifier() -> String {
        #if os(macOS)
        var size = 0
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 {
                let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                return String(decoding: bytes, as: UTF8.self)
            }
        }
        return ""
        #else
        // simulator: het nagebootste toestel
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        #endif
    }

    // MARK: Versturen

    private nonisolated static func send(_ request: URLRequest) async -> Bool {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

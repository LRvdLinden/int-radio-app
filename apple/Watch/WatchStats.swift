import Foundation
import WatchKit

/// Anonieme gebruiksping van de Watch-app (tunr-beheer/docs/CONTRACT.md, functie `ping`): platform `watchos`,
/// max. 1× per 12 uur bij openen, alleen als "Anonieme gebruiksstatistieken" aan staat (standaard aan, per apparaat).
/// Geen persoonsgegevens: model-id, watchOS- en app-versie, land (uit de iPhone-app), taal, willekeurig nummer.
@MainActor
enum WatchStats {
    private static let interval: TimeInterval = 12 * 60 * 60
    private static var inFlight = false

    static func pingIfDue() {
        let d = UserDefaults.standard
        let base = Brand.statsURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, WatchStore.shared.shareStats, !inFlight else { return }
        let now = Date().timeIntervalSince1970
        let last = d.double(forKey: "stats.lastPing")
        if last > 0, now - last < interval, now >= last { return }
        var id = d.string(forKey: "stats.installId") ?? ""
        if UUID(uuidString: id) == nil { id = UUID().uuidString; d.set(id, forKey: "stats.installId") }
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let cc = WatchStore.shared.countryCode
        let payload: [String: Any] = [
            "id": id.lowercased(),
            "platform": "watchos",
            "device": "Apple Watch",
            "model": String(model().prefix(60)),
            "os": "\(os.majorVersion).\(os.minorVersion)",
            "version": info?["CFBundleShortVersionString"] as? String ?? Brand.version,
            "build": min(max(Int(info?["CFBundleVersion"] as? String ?? "") ?? 0, 0), 99999),
            "country": cc.count == 2 ? cc : "",
            "lang": (Locale.preferredLanguages.first ?? "en").hasPrefix("nl") ? "nl" : "en",
            "carplay": false,
        ]
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: trimmed + "/functions/v1/ping"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue(Brand.statsKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        inFlight = true
        Task {
            let ok = ((try? await URLSession.shared.data(for: req))?.1 as? HTTPURLResponse)?.statusCode == 200
            inFlight = false
            if ok { d.set(Date().timeIntervalSince1970, forKey: "stats.lastPing") }
        }
    }

    private static func model() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}

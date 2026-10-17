#if os(iOS) || os(macOS)
import Foundation
import CoreGraphics
import ImageIO

// Gedeeld tussen de app en de widget-extensie (TunrWidgets): alles wat de widgets, het Bedieningspaneel en de
// Live Activity van de app moeten weten, via de App Group. Geen afhankelijkheden van de speler of de UI van de app.

/// Soorten (kinds) van de widgets en de Bedieningspaneel-knop
enum WidgetKind {
    static let nowPlaying = "nl.lrvdlinden.tunr.widget.nowplaying"
    static let favorites = "nl.lrvdlinden.tunr.widget.favorites"
    static let control = "nl.lrvdlinden.tunr.control.playback"
}

/// Compacte zender voor de widgets (geen stream-URL nodig: afspelen gaat via de app)
struct WidgetStation: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var country: String
    var countryCode: String
    /// Origineel logo (internet); de widget gebruikt de verkleinde kopie in de App Group
    var logoURL: String?

    var displayName: String { name.isEmpty ? "Radio" : name }

    /// Eén of twee letters voor de terugval-tegel ("NPO Radio 2" → "NR")
    var monogram: String {
        let words = displayName.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0) }
        let text = letters.joined().uppercased()
        return text.isEmpty ? "R" : text
    }
}

/// Wat er nu speelt (of het laatst speelde: dan `isPlaying == false`)
struct WidgetNowPlaying: Codable, Hashable {
    var station: WidgetStation
    var isPlaying: Bool
    /// Titel van het nummer (leeg als de zender niets meldt)
    var title: String
    /// Artiest (leeg als onbekend)
    var artist: String

    /// "Artiest – Titel", of alleen de titel
    var trackLine: String {
        if !artist.isEmpty, !title.isEmpty { return artist + " – " + title }
        return title
    }
}

/// Alles wat de widgets tonen
struct WidgetSnapshot: Codable, Hashable {
    var nowPlaying: WidgetNowPlaying?
    /// Bovenste favorieten (max. 8)
    var favorites: [WidgetStation] = []
    /// Laatst beluisterd (max. 8)
    var recents: [WidgetStation] = []
    /// Taal van de app ("nl"/"en"; leeg = systeem)
    var language: String = ""
}

/// Opslag in de App Group: JSON in UserDefaults(suiteName:) plus verkleinde logo's (PNG, ~120 px) als bestanden,
/// omdat widgets niet betrouwbaar afbeeldingen van internet kunnen laden.
enum WidgetBridge {
    #if os(macOS)
    /// Mac: App Group met team-prefix (werkt op alle macOS-versies zonder extra profiel)
    static let appGroup = "EU3UY476T6.nl.lrvdlinden.tunr"
    #else
    static let appGroup = "group.nl.lrvdlinden.tunr"
    #endif

    static let maxStations = 8

    private static let snapshotKey = "widget.snapshot"
    private static let languageKey = "widget.language"
    private static let pendingKey = "widget.pendingCommand"
    private static let logoFolder = "WidgetLogos"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    // MARK: Gegevens

    static func load() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snap
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let d = defaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) { d.set(data, forKey: snapshotKey) }
        d.set(snapshot.language, forKey: languageKey)
    }

    /// Taal van de app ("nl", "en" of leeg = systeem); goedkoop te lezen (zonder de hele snapshot)
    static var language: String { defaults?.string(forKey: languageKey) ?? "" }

    // MARK: Opdracht voor de app (terugval als een intent toch in de extensie draait)

    /// "toggle", "stop" of "play:<stationuuid>"
    static func setPendingCommand(_ command: String) {
        defaults?.set(command, forKey: pendingKey)
    }

    static func takePendingCommand() -> String? {
        guard let d = defaults, let c = d.string(forKey: pendingKey), !c.isEmpty else { return nil }
        d.removeObject(forKey: pendingKey)
        return c
    }

    // MARK: Logo's

    static var logosDirectory: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let dir = base.appendingPathComponent(logoFolder, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Vaste bestandsnaam per zender ("logo-<uuid>.png")
    static func logoFileName(for stationID: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let safe = String(stationID.filter { allowed.contains($0) }.prefix(64))
        return "logo-" + (safe.isEmpty ? "unknown" : safe) + ".png"
    }

    static func logoFileURL(for stationID: String) -> URL? {
        logosDirectory?.appendingPathComponent(logoFileName(for: stationID))
    }

    static func logoFileURL(fileName: String) -> URL? {
        logosDirectory?.appendingPathComponent(fileName)
    }

    static func hasLogo(for stationID: String) -> Bool {
        guard let url = logoFileURL(for: stationID) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func writeLogo(_ png: Data, for stationID: String) {
        guard let url = logoFileURL(for: stationID) else { return }
        try? png.write(to: url, options: .atomic)
    }

    /// Logo's van zenders die niet meer in de widgets staan opruimen
    static func removeLogos(except stationIDs: Set<String>) {
        guard let dir = logosDirectory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let keep = Set(stationIDs.map { logoFileName(for: $0) })
        for f in files where f.hasPrefix("logo-") && !keep.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    /// Het verkleinde logo als CGImage (werkt op iOS en macOS, zonder UIKit/AppKit)
    static func logoImage(for stationID: String) -> CGImage? {
        guard let url = logoFileURL(for: stationID) else { return nil }
        return image(at: url)
    }

    static func logoImage(fileName: String) -> CGImage? {
        guard let url = logoFileURL(fileName: fileName) else { return nil }
        return image(at: url)
    }

    private static func image(at url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
#endif

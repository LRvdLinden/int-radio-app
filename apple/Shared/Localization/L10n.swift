import Foundation
import SwiftUI
import Combine

/// Vertalingen uit `Localizable.strings` (en, nl) met een taalkeuze in de app zelf (Instellingen → Taal),
/// los van de systeemtaal. Gebruik: `L("tab.discover")`, `L("stations.count", 1234)`.
final class Localizer: ObservableObject {
    static let shared = Localizer()

    /// Opslagsleutel van de taalkeuze: "" = systeem, "nl", "en"
    static let key = "settings.language"
    static let supported = ["en", "nl"]

    /// "" = volg het systeem
    @Published var override: String {
        didSet {
            UserDefaults.standard.set(override, forKey: Self.key)
            apply()
        }
    }
    /// De actieve taal ("nl" of "en")
    @Published private(set) var language: String

    private let lock = NSLock()
    private var bundle: Bundle

    private init() {
        let o = UserDefaults.standard.string(forKey: Self.key) ?? ""
        let lang = Self.resolve(o)
        override = o
        language = lang
        bundle = Self.bundle(for: lang)
    }

    private func apply() {
        let lang = Self.resolve(override)
        let b = Self.bundle(for: lang)
        lock.lock(); bundle = b; lock.unlock()
        language = lang
    }

    static func resolve(_ override: String) -> String {
        if supported.contains(override) { return override }
        for pref in Locale.preferredLanguages {
            let base = String(pref.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
            if supported.contains(base) { return base }
        }
        return "en"
    }

    private static func bundle(for lang: String) -> Bundle {
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) { return b }
        return Bundle.main
    }

    func text(_ key: String) -> String {
        lock.lock(); let b = bundle; lock.unlock()
        let value = b.localizedString(forKey: key, value: nil, table: nil)
        if value != key { return value }
        // terugval: Engels
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let en = Bundle(path: path) {
            return en.localizedString(forKey: key, value: key, table: nil)
        }
        return key
    }

    var locale: Locale { Locale(identifier: language == "nl" ? "nl_NL" : "en_US") }
}

/// Vertaal een sleutel naar de actieve taal.
func L(_ key: String) -> String { Localizer.shared.text(key) }

/// Vertaal met opmaak-argumenten (`%@`, `%d`, `%ld`).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.text(key), locale: Localizer.shared.locale, arguments: args)
}

/// Getal met duizendtallen in de taal van de app ("1.234")
func formattedNumber(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Localizer.shared.locale
    return f.string(from: NSNumber(value: n)) ?? String(n)
}

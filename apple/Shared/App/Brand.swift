import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// De (werk)naam en vaste gegevens van de app staan alleen hier.
/// Bij een nieuwe naam volstaat zoek-en-vervang op "Tunr" (plus de teksten in Localizable.strings).
enum Brand {
    static let name = "Tunr"
    static let bundleID = "nl.lrvdlinden.tunr"
    static let version = "1.0.0"

    /// Website (tunr.online), privacy en voorwaarden (website/privacy en website/voorwaarden)
    static let website = URL(string: "https://tunr.online")!
    static let domain = URL(string: "https://tunr.online")!
    static let privacy = URL(string: "https://tunr.online/privacy/")!
    static let terms = URL(string: "https://tunr.online/voorwaarden/")!
    static let radioBrowser = URL(string: "https://www.radio-browser.info")!

    /// Anonieme gebruiksstatistieken (BeheerTunr, zie tunr-beheer/docs/CONTRACT.md): Supabase-URL
    /// (`https://<project-ref>.supabase.co`) en publishable key (`sb_publishable_…`). Openbaar, mag in de repo.
    /// Zolang de URL leeg is, stuurt de app geen ping.
    static let statsURL = "https://vbhkewgyujzgbukkbtml.supabase.co"
    static let statsKey = "sb_publishable_0Fp86h5uCovv00KReb3Pvg_lTH7TwU6"

    /// "iOS", "iPadOS", "tvOS" of "macOS"; wordt bij het starten ingevuld (zie `configurePlatform`).
    static var platformName: String = {
        #if os(tvOS)
        return "tvOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }()

    /// User-Agent voor Radio Browser (verplicht een eigen naam): `Tunr/1.0.0 (nl.lrvdlinden.tunr; iOS)`
    static var userAgent: String { "\(name)/\(version) (\(bundleID); \(platformName))" }

    /// Versie + build zoals in Instellingen → Over ("1.0.0 (12)")
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? version
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// iPad als "iPadOS" melden; moet op de hoofdthread (UIDevice).
    @MainActor static func configurePlatform() {
        #if os(iOS)
        platformName = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
    }
}

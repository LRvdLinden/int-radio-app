import SwiftUI
import Combine

/// Tabbladen (SPEC §6). `settings` alleen als tabblad op Apple TV.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case discover, browse, map, search, library, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return L("tab.discover")
        case .browse: return L("tab.browse")
        case .map: return L("tab.map")
        case .search: return L("tab.search")
        case .library: return L("tab.library")
        case .settings: return L("tab.settings")
        }
    }

    var symbol: String {
        switch self {
        case .discover: return "dot.radiowaves.left.and.right"
        case .browse: return "square.grid.2x2"
        case .map: return "globe.europe.africa"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        case .settings: return "gearshape"
        }
    }

    /// De vijf hoofdtabbladen (zonder Instellingen)
    static var main: [AppTab] { [.discover, .browse, .map, .search, .library] }
}

/// Toestand van de app: fase (intro → landkeuze → hoofdscherm), gekozen tabblad en open bladen.
@MainActor
final class AppState: ObservableObject {
    enum Stage: Equatable { case splash, countryPicker, main }

    @Published var stage: Stage = .splash
    @Published var tab: AppTab = .discover
    @Published var showPlayer = false
    @Published var showCountryPicker = false
    @Published var showSettings = false
    /// Kaart: eenmalig verzoek (bijv. vanuit Bladeren → Wereldkaart) om de wereld te laden
    @Published var mapWantsWorld = false

    private var bag = Set<AnyCancellable>()

    init() {
        // App Store-schermafbeeldingen: meteen het hoofdscherm met de gevraagde scène (niets onthouden)
        if ScreenshotMode.isActive {
            stage = .main
            tab = ScreenshotMode.tab
            ScreenshotMode.prepare(app: self)
            return
        }
        // tabblad onthouden tussen starts
        if let raw = UserDefaults.standard.string(forKey: "ui.tab"), let t = AppTab(rawValue: raw) { tab = t }
        $tab.dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "ui.tab") }
            .store(in: &bag)
    }

    /// Na de intro: landkeuze bij de eerste start, anders het hoofdscherm
    func finishSplash() {
        withAnimation(.easeInOut(duration: 0.45)) {
            stage = Library.shared.countryCode == nil ? .countryPicker : .main
        }
        if stage == .main { RadioPlayer.shared.resumeLastIfWanted() }
    }

    func countryChosen() {
        showCountryPicker = false
        if stage != .main {
            withAnimation(.easeInOut(duration: 0.5)) { stage = .main }
        }
    }

    /// Instellingen openen (tv: tabblad; iPhone/iPad: blad; Mac: eigen venster via SettingsLink)
    func openSettings() {
        #if os(tvOS)
        tab = .settings
        #else
        showSettings = true
        #endif
    }
}

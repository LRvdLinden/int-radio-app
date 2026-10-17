import SwiftUI
import Combine

@main
struct TunrApp: App {
    @StateObject private var app = AppState()
    @StateObject private var localizer = Localizer.shared
    // Gedeelde objecten die alleen worden doorgegeven: de schermen volgen ze zelf
    private let library = Library.shared
    private let player = RadioPlayer.shared
    @Environment(\.scenePhase) private var phase

    init() {
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        DeviceKind.configure()
        Brand.configurePlatform()
        // build 9: taal, slaaptimer en automatisch verder spelen via iCloud
        SettingsSync.shared.start()
        // anonieme gebruiksping (max. 1× per 12 uur; uit te zetten in Instellingen)
        StatsPing.shared.pingIfDue()
        #if os(iOS) || os(macOS)
        // widgets, Bedieningspaneel en App Intents (App Group, zie WidgetSync.swift)
        TunrIntentHandler.ensureAppHandler()
        WidgetSync.shared.start()
        #endif
        #if os(iOS) && canImport(ActivityKit)
        // Live Activity "Nu speelt" (Dynamic Island, vergrendelscherm)
        LiveActivityController.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // taal wisselen → alles opnieuw opbouwen
                .id(localizer.language)
                .environmentObject(app)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(localizer)
                .environment(\.locale, localizer.locale)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                #if os(iOS) || os(macOS)
                // widgets: tunr://station/<id>, tunr://player
                .onOpenURL { url in TunrDeepLink.handle(url, app: app) }
                #endif
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        .commands { PlaybackCommands(player: player, library: library) }
        #endif
        .onChange(of: phase) { _, p in
            if p == .active {
                Task { await library.refreshFavorites() }
                StatsPing.shared.pingIfDue()
                #if os(iOS) || os(macOS)
                WidgetSync.shared.handlePendingCommand()
                #endif
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(localizer)
                .environment(\.locale, localizer.locale)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .frame(width: 560, height: 640)
        }
        #endif
    }
}

#if os(macOS)
/// Menu "Afspelen": Spatie = afspelen/pauze, ⌘→/⌘← = volgende/vorige zender, ⌘L = favoriet.
/// Aflevering: ⌘→/⌘← = 30 s vooruit / 15 s terug, ⇧⌘→/⇧⌘← = volgende/vorige aflevering, plus snelheid.
struct PlaybackCommands: Commands {
    @ObservedObject var player: RadioPlayer
    @ObservedObject var library: Library

    var body: some Commands {
        CommandMenu(L("menu.playback")) {
            Button(player.state == .playing ? L("player.pause") : L("player.play")) { player.toggle() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!player.hasMedia)
            Divider()
            if player.isEpisode {
                Button(L("player.forward30")) { player.skip(RadioPlayer.skipForward) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button(L("player.back15")) { player.skip(-RadioPlayer.skipBack) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button(L("player.nextEpisode")) { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                    .disabled(!player.hasNext)
                Button(L("player.previousEpisode")) { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                    .disabled(!player.hasPrevious)
                Divider()
                Menu(L("player.speed")) {
                    ForEach(RadioPlayer.rates, id: \.self) { r in
                        Button((r == player.rate ? "✓ " : "") + PodcastFormat.rate(r)) { player.setRate(r) }
                    }
                }
            } else {
                Button(L("player.next")) { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!player.hasNext)
                Button(L("player.previous")) { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(!player.hasNext)
                Divider()
                Button(isFavorite ? L("action.unfavorite") : L("action.favorite")) { player.toggleFavoriteCurrent() }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(player.station == nil)
            }
            Divider()
            Menu(L("player.sleepTimer")) {
                if player.isEpisode {
                    Button(L("sleep.endOfEpisode")) { player.setSleepAtEpisodeEnd() }
                }
                ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                    Button(L("sleep.minutes", m)) { player.setSleepTimer(minutes: m) }
                }
                Button(L("sleep.off")) { player.setSleepTimer(minutes: 0) }
            }
            .disabled(!player.hasMedia)
        }
    }

    private var isFavorite: Bool {
        guard let s = player.station else { return false }
        return library.isFavorite(s)
    }
}
#endif

/// Intro → landkeuze (eerste start) → hoofdscherm
struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch app.stage {
            case .splash:
                SplashView { app.finishSplash() }
                    .transition(.opacity)
            case .countryPicker:
                CountryPickerView(isFirstRun: true)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            case .main:
                MainView()
                    .transition(.opacity)
            }
        }
    }
}

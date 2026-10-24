import SwiftUI

/// Tunr op de Apple Watch: Nu speelt (iPhone of Watch), favorieten en recent, ontdekken (populair in je land,
/// zoeken) en instellingen. Pagina's verticaal met de Digital Crown.
@main
struct TunrWatchApp: App {
    @StateObject private var store = WatchStore.shared
    @StateObject private var player = WatchPlayer.shared
    @StateObject private var phone = PhoneLink.shared
    @Environment(\.scenePhase) private var phase

    init() {
        PhoneLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { NowPlayingPage() }
                NavigationStack { LibraryPage() }
                NavigationStack { DiscoverPage() }
                NavigationStack { SettingsPage() }
            }
            .tabViewStyle(.verticalPage)
            .tint(WTheme.accent)
            .environmentObject(store)
            .environmentObject(player)
            .environmentObject(phone)
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                WatchStats.pingIfDue()
                PhoneLink.shared.refresh()
            }
        }
    }
}

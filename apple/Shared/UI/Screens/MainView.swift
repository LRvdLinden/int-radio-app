import SwiftUI

/// Hoofdscherm.
/// - iPhone: TabView met 5 tabbladen, miniplayer boven de tabbalk.
/// - iPad en Mac: NavigationSplitView met zijbalk, miniplayer onderaan.
/// - Apple TV: TabView bovenaan met 6 tabbladen (incl. Instellingen), geen miniplayer.
struct MainView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        layout
            .modifier(PlayerPresentation())
            .sheet(isPresented: $app.showCountryPicker) {
                CountryPickerView()
            }
            #if os(iOS)
            .sheet(isPresented: $app.showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("action.done")) { app.showSettings = false }
                            }
                        }
                }
            }
            #endif
    }

    @ViewBuilder private var layout: some View {
        #if os(tvOS)
        TVTabs()
        #elseif os(macOS)
        SidebarLayout()
        #else
        if DeviceKind.isPad {
            SidebarLayout()
        } else {
            PhoneTabs()
        }
        #endif
    }
}

/// Inhoud per tabblad (elk met een eigen navigatiestapel)
struct TabContent: View {
    let tab: AppTab

    var body: some View {
        switch tab {
        case .discover: NavStack { DiscoverView() }
        case .browse: NavStack { BrowseView() }
        case .map: NavStack { MapExplorerView() }
        case .search: NavStack { SearchView() }
        case .library: NavStack { LibraryView() }
        case .settings: NavStack { SettingsView() }
        }
    }
}

#if os(iOS)
/// iPhone: 5 tabbladen onderaan, miniplayer erboven
struct PhoneTabs: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        TabView(selection: $app.tab) {
            ForEach(AppTab.main) { tab in
                TabContent(tab: tab)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        // ruimte zodat de miniplayer geen inhoud afdekt
                        if player.station != nil { Color.clear.frame(height: 68) }
                    }
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .toolbarBackground(Theme.bg.opacity(0.94), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .bottom) {
            MiniPlayer()
                .padding(.bottom, 49)   // hoogte van de tabbalk (boven het thuisbalkje)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: player.station?.id)
        }
    }
}
#endif

#if !os(tvOS)
/// iPad en Mac: zijbalk + detail, miniplayer onderaan
struct SidebarLayout: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: RadioPlayer
    @State private var columns: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } detail: {
            TabContent(tab: app.tab == .settings ? .discover : app.tab)
                .id(app.tab)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if player.station != nil {
                        MiniPlayer()
                            .padding(.top, 4)
                            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: player.station?.id)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        List(selection: Binding<AppTab?>(get: { app.tab }, set: { if let t = $0 { app.tab = t } })) {
            Section {
                ForEach(AppTab.main) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                        .tag(tab)
                }
            } header: {
                TunrLogo(size: 20)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(Brand.name)
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        #else
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button { app.showSettings = true } label: {
                    Label(L("tab.settings"), systemImage: "gearshape")
                }
            }
        }
        #endif
    }
}
#endif

#if os(tvOS)
/// Apple TV: tabbladen bovenaan, Instellingen als laatste tabblad
struct TVTabs: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.tab) {
            ForEach(AppTab.allCases) { tab in
                TabContent(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
    }
}
#endif

/// Volledige speler: iPhone/iPad/tv schermvullend (sleepbaar omlaag op iOS), Mac als blad
struct PlayerPresentation: ViewModifier {
    @EnvironmentObject private var app: AppState

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(isPresented: $app.showPlayer) {
            PlayerView()
                .frame(minWidth: 820, idealWidth: 960, minHeight: 600, idealHeight: 700)
        }
        #elseif os(tvOS)
        content.fullScreenCover(isPresented: $app.showPlayer) { PlayerView() }
        #else
        content.sheet(isPresented: $app.showPlayer) {
            PlayerView()
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
                .presentationBackground(Theme.bg)
        }
        #endif
    }
}

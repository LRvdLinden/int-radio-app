import SwiftUI

/// Bibliotheek: segmenten Favorieten · Podcasts · Recent
struct LibraryView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case favorites, podcasts, recent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .favorites: return L("library.favorites")
            case .podcasts: return L("library.podcasts")
            case .recent: return L("library.recent")
            }
        }
    }

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: RadioPlayer
    @AppStorage("ui.librarySegment") private var segment: Segment = .favorites
    @State private var confirmClear = false
    @Environment(\.navigate) private var navigate
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 18)]
        #else
        return [GridItem(.adaptive(minimum: DeviceKind.isPhone ? 105 : 150, maximum: 200), spacing: 14)]
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: tvScaled(14)) {
            header
            Picker(L("tab.library"), selection: $segment) {
                ForEach(Segment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: tvScaled(520))
            .padding(.horizontal, Theme.edge)
            #if os(macOS)
            .labelsHidden()
            #endif

            Group {
                switch segment {
                case .favorites: favorites
                case .podcasts: podcasts
                case .recent: recents
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.2), value: segment)
        }
        .padding(.top, tvScaled(12))
        .screenBackground()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.editMode, $editMode)
        #elseif os(macOS)
        .navigationTitle(L("tab.library"))
        #endif
        .confirmationDialog(segment == .favorites ? L("settings.clearFavoritesConfirm") : L("settings.clearRecentConfirm"),
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("action.clear"), role: .destructive) {
                withAnimation {
                    if segment == .favorites { library.clearFavorites() } else { library.clearRecents() }
                }
            }
            Button(L("action.cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: tvScaled(10)) {
            #if !os(macOS)
            Text(L("tab.library"))
                .font(Theme.screenTitle)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            #endif
            Spacer()
            #if os(iOS)
            if segment == .favorites, library.favorites.count > 1 {
                Button(editMode.isEditing ? L("action.done") : L("action.edit")) {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
            #endif
            if segment == .recent, !library.recents.isEmpty {
                Button(L("action.clear")) { confirmClear = true }
                    .font(.system(size: tvScaled(15), weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .plainTVButton()
            }
            #if os(iOS)
            Button { app.openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 34)
            }
            .buttonStyle(SecondaryButtonStyle(cornerRadius: 17))
            .accessibilityLabel(L("tab.settings"))
            #elseif os(macOS)
            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(SecondaryButtonStyle(cornerRadius: 15))
            .accessibilityLabel(L("tab.settings"))
            #endif
        }
        .padding(.horizontal, Theme.edge)
    }

    // MARK: Favorieten

    @ViewBuilder private var favorites: some View {
        if library.favorites.isEmpty {
            EmptyStateView(symbol: "heart.fill", title: L("library.emptyFavorites"), message: L("library.emptyFavoritesHint"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEditing {
            #if os(iOS)
            // bewerken/sorteren (EditButton-gedrag)
            List {
                ForEach(library.favorites) { s in
                    StationRow(station: s).listRowBackground(Theme.surface)
                }
                .onMove { library.moveFavorites(from: $0, to: $1) }
                .onDelete { idx in
                    let doomed = idx.map { library.favorites[$0] }
                    for s in doomed { library.removeFavorite(s) }
                }
            }
            .hiddenListBackground()
            #endif
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: tvScaled(20)) {
                    ForEach(library.favorites) { s in
                        Button {
                            Haptics.tap()
                            player.play(s, queue: library.favorites)
                        } label: {
                            StationCard(station: s, width: nil)
                        }
                        .cardButton()
                        .contextMenu {
                            StationContextMenu(station: s, queue: library.favorites,
                                               onRemove: { withAnimation { library.removeFavorite(s) } },
                                               removeTitle: L("library.removeFavorite"))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Theme.edge)
                .padding(.vertical, tvScaled(10))
                #if os(tvOS)
                .padding(.vertical, 20)
                #endif
            }
        }
    }

    private var isEditing: Bool {
        #if os(iOS)
        return editMode.isEditing
        #else
        return false
        #endif
    }

    // MARK: Podcasts

    /// Verder luisteren (half beluisterde afleveringen) bovenaan, daaronder de gevolgde podcasts als raster
    @ViewBuilder private var podcasts: some View {
        let continuing = library.continueListening
        if library.followedPodcasts.isEmpty && continuing.isEmpty {
            VStack(spacing: tvScaled(14)) {
                EmptyStateView(symbol: "mic.fill", title: L("library.emptyPodcasts"), message: L("library.emptyPodcastsHint"))
                Button { navigate(.podcasts) } label: {
                    Label(L("library.discoverPodcasts"), systemImage: "sparkles")
                        .font(.system(size: tvScaled(14), weight: .bold))
                        .padding(.horizontal, tvScaled(16)).padding(.vertical, tvScaled(9))
                }
                .buttonStyle(AccentButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                    if !continuing.isEmpty {
                        EpisodeShelf(title: L("row.continueEpisodes"), episodes: continuing)
                    }
                    if !library.followedPodcasts.isEmpty {
                        VStack(alignment: .leading, spacing: tvScaled(10)) {
                            SectionHeader(title: L("podcasts.following"),
                                          actionTitle: L("library.discoverPodcasts"),
                                          action: { navigate(.podcasts) })
                            LazyVGrid(columns: columns, alignment: .leading, spacing: tvScaled(20)) {
                                ForEach(library.followedPodcasts) { p in
                                    PodcastCardButton(podcast: p, width: nil)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, Theme.edge)
                            #if os(tvOS)
                            .padding(.vertical, 20)
                            .focusSection()
                            #endif
                        }
                    }
                }
                .padding(.vertical, tvScaled(10))
            }
        }
    }

    // MARK: Recent

    @ViewBuilder private var recents: some View {
        if library.recents.isEmpty {
            EmptyStateView(symbol: "clock.fill", title: L("library.emptyRecent"), message: L("library.emptyRecentHint"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(library.recents) { s in
                        StationRowButton(station: s, queue: library.recents,
                                         onRemove: { withAnimation { library.removeRecent(s) } },
                                         removeTitle: L("library.removeRecent"))
                            .padding(.horizontal, Theme.edge)
                        Divider().overlay(Theme.stroke).padding(.leading, Theme.edge + Theme.rowArt + tvScaled(12))
                    }
                }
                .padding(.vertical, tvScaled(6))
            }
        }
    }
}

import SwiftUI

/// Bibliotheek: segmenten Favorieten · Recent
struct LibraryView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case favorites, recent
        var id: String { rawValue }
        var title: String { self == .favorites ? L("library.favorites") : L("library.recent") }
    }

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: RadioPlayer
    @AppStorage("ui.librarySegment") private var segment: Segment = .favorites
    @State private var confirmClear = false
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
            .frame(maxWidth: tvScaled(420))
            .padding(.horizontal, Theme.edge)
            #if os(macOS)
            .labelsHidden()
            #endif

            Group {
                switch segment {
                case .favorites: favorites
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
                    for i in idx { library.removeFavorite(library.favorites[i]) }
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

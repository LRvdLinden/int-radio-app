import SwiftUI

/// Rasterpagina met zenders ("Alles", genrepagina, regio, taal, Top 100 genummerd)
struct StationGridView: View {
    let source: StationSource

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: RadioPlayer
    @State private var state: LoadState<[Station]> = .idle
    @State private var filter = ""

    private var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 18)]
        #else
        return [GridItem(.adaptive(minimum: DeviceKind.isPhone ? 105 : 150, maximum: 200), spacing: 14)]
        #endif
    }

    private var stations: [Station] {
        let list: [Station]
        switch source {
        case .favorites: list = library.favorites
        case .recents: list = library.recents
        default: list = state.value ?? []
        }
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.tags.localizedCaseInsensitiveContains(q) }
    }

    /// Regionaam als dit een regiolijst is
    private var regionName: String? {
        if case .region(_, let name) = source { return name }
        return nil
    }

    private var canMakeRegion: Bool {
        guard let name = regionName else { return false }
        return library.currentRegion?.name != name
    }

    private var isMyRegion: Bool {
        guard let name = regionName else { return false }
        return library.currentRegion?.name == name
    }

    var body: some View {
        content
            .screenBackground()
            .navigationTitle(source.title)
            .inlineTitle()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if canMakeRegion {
                        Button {
                            if let name = regionName { library.setLocalRegion(name) }
                            Haptics.success()
                        } label: {
                            Label(L("local.makeMine"), systemImage: "location.fill")
                        }
                    }
                    if !stations.isEmpty {
                        Button {
                            if let first = stations.first { player.play(first, queue: stations) }
                        } label: {
                            Label(L("action.playAll"), systemImage: "play.fill")
                        }
                    }
                }
            }
            .task(id: source) { await load() }
    }

    @ViewBuilder private var content: some View {
        if !source.isLocal, state.isFailed {
            ErrorRetryView { Task { await load(force: true) } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !source.isLocal, state.isLoading, state.value == nil {
            ScrollView {
                LazyVGrid(columns: columns, spacing: tvScaled(18)) {
                    ForEach(0..<18, id: \.self) { _ in CardSkeleton(width: nil) }
                }
                .padding(Theme.edge)
            }
        } else if stations.isEmpty && filter.isEmpty {
            EmptyStateView(symbol: "radio", title: L("empty.noStations"), message: L("empty.noStationsHint"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: tvScaled(14)) {
                    if isMyRegion {
                        Label(L("local.isMine"), systemImage: "location.fill")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, Theme.edge)
                    }
                    if source.isRanked {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(stations.enumerated()), id: \.element.id) { i, s in
                                StationRowButton(station: s, queue: stations, rank: i + 1)
                                    .padding(.horizontal, Theme.edge)
                                Divider().overlay(Theme.stroke).padding(.leading, Theme.edge + Theme.rowArt + tvScaled(54))
                            }
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: tvScaled(20)) {
                            ForEach(stations) { s in
                                StationCardButton(station: s, queue: stations, width: nil)
                            }
                        }
                        .padding(.horizontal, Theme.edge)
                    }
                }
                .padding(.vertical, tvScaled(12))
                #if os(tvOS)
                .padding(.vertical, 20)
                #endif
            }
            #if !os(tvOS)
            .searchable(text: $filter, prompt: L("search.filter"))
            #endif
        }
    }

    private func load(force: Bool = false) async {
        guard !source.isLocal else { return }
        if state.value == nil || force { state = .loading }
        do {
            let list = try await source.fetch()
            withAnimation(.easeOut(duration: 0.25)) { state = .loaded(list) }
        } catch {
            if state.value == nil { state = .failed }
        }
    }
}

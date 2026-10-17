import SwiftUI

/// Podcastoverzicht (Bladeren → Podcasts): zoekveld, genre-tegels en de genummerde top 50 van het land.
struct PodcastsHomeView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate
    @State private var top: LoadState<[Podcast]> = .idle
    @State private var query = ""

    private var country: String { library.countryCode ?? "NL" }
    private var countryName: String { Country.localizedName(code: country, fallback: library.countryName) }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if trimmed.count >= 2 {
                    PodcastSearchResults(query: trimmed, country: country)
                } else {
                    if !library.followedPodcasts.isEmpty {
                        PodcastShelf(title: L("podcasts.following"), podcasts: library.followedPodcasts)
                    }
                    genres
                    topList
                }
            }
            .padding(.vertical, tvScaled(12))
        }
        .scrollDismissesKeyboardIfAvailable()
        .screenBackground()
        .navigationTitle(L("podcasts.title"))
        .inlineTitle()
        .searchable(text: $query, prompt: L("search.promptPodcasts"))
        .onSubmit(of: .search) { library.addSearch(trimmed) }
        .task(id: country) { await load() }
    }

    // MARK: Genres

    private var genres: some View {
        VStack(alignment: .leading, spacing: tvScaled(10)) {
            SectionHeader(title: L("row.genres"))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.itemSpacing) {
                    ForEach(Array(PodcastGenre.all.enumerated()), id: \.element.id) { i, g in
                        Button { navigate(.podcastGenre(g)) } label: {
                            BrowseTile(title: g.title, symbol: g.symbol, paletteIndex: i)
                                .frame(width: tvScaled(DeviceKind.isPhone ? 150 : 180))
                        }
                        .cardButton()
                    }
                }
                .padding(.horizontal, Theme.edge)
                #if os(tvOS)
                .padding(.vertical, 30)
                #endif
            }
            .scrollClipDisabled()
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    // MARK: Top 50

    @ViewBuilder private var topList: some View {
        VStack(alignment: .leading, spacing: tvScaled(6)) {
            SectionHeader(title: L("podcasts.topIn", countryName))
            switch top {
            case .idle, .loading:
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { _ in RowSkeleton().padding(.horizontal, Theme.edge) }
                }
            case .failed:
                ErrorRetryView(title: L("podcasts.errorTitle")) { Task { await load(force: true) } }
                    .frame(maxWidth: .infinity)
            case .loaded(let list):
                if list.isEmpty {
                    EmptyStateView(symbol: "mic", title: L("podcasts.none"), message: L("podcasts.noneHint"))
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                            PodcastRowButton(podcast: p, rank: i + 1)
                                .padding(.horizontal, Theme.edge)
                            Divider().overlay(Theme.stroke).padding(.leading, Theme.edge + Theme.rowArt + tvScaled(54))
                        }
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            }
        }
    }

    private func load(force: Bool = false) async {
        if top.value == nil || force { top = .loading }
        do {
            let list = try await PodcastAPI.shared.topPodcasts(country: country)
            withAnimation(.easeOut(duration: 0.25)) { top = .loaded(list) }
        } catch {
            if top.value == nil { top = .failed }
        }
    }
}

/// Zoekresultaten voor podcasts (debounce 350 ms); gebruikt door Zoeken en het podcastoverzicht
struct PodcastSearchResults: View {
    let query: String
    let country: String

    @EnvironmentObject private var library: Library
    @State private var results: LoadState<[Podcast]> = .idle
    @State private var lastQuery = ""

    var body: some View {
        Group {
            switch results {
            case .idle, .loading:
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in RowSkeleton().padding(.horizontal, Theme.edge) }
                }
            case .failed:
                ErrorRetryView(title: L("podcasts.errorTitle")) { Task { await search() } }
                    .frame(maxWidth: .infinity)
            case .loaded(let list):
                if list.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: L("search.noResults"), message: L("search.noPodcastsHint"))
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(L("search.podcastCount", list.count))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, Theme.edge)
                            .padding(.bottom, tvScaled(6))
                        ForEach(list) { p in
                            PodcastRowButton(podcast: p, onOpen: { library.addSearch(query) })
                                .padding(.horizontal, Theme.edge)
                            Divider().overlay(Theme.stroke).padding(.leading, Theme.edge + Theme.rowArt + tvScaled(12))
                        }
                    }
                }
            }
        }
        .task(id: query + "|" + country) { await search() }
    }

    private func search() async {
        let q = query
        guard q.count >= 2 else {
            results = .idle
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        if results.value == nil || lastQuery != q { results = .loading }
        do {
            let list = try await PodcastAPI.shared.search(q, country: country)
            guard !Task.isCancelled else { return }
            lastQuery = q
            withAnimation(.easeOut(duration: 0.2)) { results = .loaded(list) }
        } catch {
            guard !Task.isCancelled else { return }
            results = .failed
        }
    }
}

/// Toplijst van één podcastgenre (raster, genummerd)
struct PodcastGenreView: View {
    let genre: PodcastGenre

    @EnvironmentObject private var library: Library
    @State private var state: LoadState<[Podcast]> = .idle

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
        Group {
            switch state {
            case .idle, .loading:
                ScrollView {
                    LazyVGrid(columns: columns, spacing: tvScaled(18)) {
                        ForEach(0..<18, id: \.self) { _ in CardSkeleton(width: nil) }
                    }
                    .padding(Theme.edge)
                }
            case .failed:
                ErrorRetryView(title: L("podcasts.errorTitle")) { Task { await load() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let list):
                if list.isEmpty {
                    EmptyStateView(symbol: "mic", title: L("podcasts.none"), message: L("podcasts.noneHint"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: tvScaled(20)) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                                PodcastCardButton(podcast: p, width: nil, rank: i + 1)
                            }
                        }
                        .padding(.horizontal, Theme.edge)
                        .padding(.vertical, tvScaled(12))
                        #if os(tvOS)
                        .padding(.vertical, 20)
                        #endif
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle(genre.title)
        .inlineTitle()
        .task(id: genre.id) { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let list = try await PodcastAPI.shared.topPodcasts(genre: genre.id, country: library.countryCode ?? "NL")
            withAnimation(.easeOut(duration: 0.25)) { state = .loaded(list) }
        } catch {
            if state.value == nil { state = .failed }
        }
    }
}

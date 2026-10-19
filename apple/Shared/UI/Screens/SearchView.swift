import SwiftUI

/// Zoeken: segment Zenders · Podcasts, zoekveld (debounce 350 ms), bij zenders schakelaar {land} / Wereldwijd.
/// Leeg: populaire genres (of podcastgenres) + recent gezocht (max 8, wisbaar). Resultaten: lijst.
struct SearchView: View {
    @EnvironmentObject private var library: Library
    // App Store-schermafbeeldingen: met een zoekterm, wereldwijd
    @State private var query = ScreenshotMode.initialSearch
    @State private var worldwide = ScreenshotMode.scene == .search
    @State private var results: LoadState<[Station]> = .idle
    @State private var lastQuery = ""
    @AppStorage("ui.searchKind") private var kind: SearchKind = .stations
    @Environment(\.navigate) private var navigate

    private var country: String { library.countryCode ?? "NL" }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: tvScaled(18)) {
                #if os(iOS)
                Text(L("tab.search"))
                    .font(Theme.screenTitle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.edge)
                    .accessibilityAddTraits(.isHeader)
                #endif

                #if os(tvOS)
                NowPlayingCard()   // terug naar de speler (tv heeft geen miniplayer)
                #endif

                kindPicker
                    .padding(.horizontal, Theme.edge)

                if kind == .stations {
                    scopePicker
                        .padding(.horizontal, Theme.edge)
                }

                if trimmed.count < 2 {
                    emptyContent
                } else if kind == .podcasts {
                    PodcastSearchResults(query: trimmed, country: country)
                } else {
                    resultsContent
                }
            }
            .padding(.vertical, tvScaled(12))
        }
        .scrollDismissesKeyboardIfAvailable()
        .screenBackground()
        .searchable(text: $query, prompt: kind == .stations ? L("search.prompt") : L("search.promptPodcasts"))
        .onSubmit(of: .search) { library.addSearch(trimmed) }
        #if os(macOS)
        .navigationTitle(L("tab.search"))
        #endif
        .task(id: trimmed + (worldwide ? "|w" : "|" + country) + "|" + kind.rawValue) {
            guard kind == .stations else { return }
            await search()
        }
    }

    private var kindPicker: some View {
        Picker(L("search.kind"), selection: $kind) {
            ForEach(SearchKind.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: tvScaled(460))
        #if os(macOS)
        .labelsHidden()
        #endif
    }

    private var scopePicker: some View {
        Picker(L("search.scope"), selection: $worldwide) {
            Text(Country.flag(for: country) + " " + Country.localizedName(code: country, fallback: country)).tag(false)
            Text("🌍 " + L("search.worldwide")).tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: tvScaled(460))
        #if os(macOS)
        .labelsHidden()
        #endif
    }

    // MARK: Leeg

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            VStack(alignment: .leading, spacing: tvScaled(10)) {
                SectionHeader(title: L("search.popularGenres"))
                if kind == .stations {
                    GenreChips(horizontal: false)
                        .padding(.horizontal, Theme.edge)
                } else {
                    FlowLayout(spacing: tvScaled(8)) {
                        ForEach(PodcastGenre.all) { g in
                            GenreChip(title: g.title, symbol: g.symbol) { navigate(.podcastGenre(g)) }
                        }
                    }
                    .padding(.horizontal, Theme.edge)
                }
            }
            if !library.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: tvScaled(6)) {
                    SectionHeader(title: L("search.recent"), actionTitle: L("action.clear")) {
                        withAnimation { library.clearSearches() }
                    }
                    VStack(spacing: 0) {
                        ForEach(library.recentSearches, id: \.self) { q in
                            Button { query = q } label: {
                                HStack(spacing: tvScaled(12)) {
                                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.secondary)
                                    Text(q).font(Theme.body).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "arrow.up.left").font(.system(size: tvScaled(12))).foregroundStyle(Theme.secondary)
                                }
                                .padding(.vertical, tvScaled(10))
                                .padding(.horizontal, Theme.edge)
                                .contentShape(Rectangle())
                                #if os(tvOS)
                                .background(RowFocusBackground())
                                #endif
                            }
                            .plainTVButton()
                        }
                    }
                }
            }
        }
    }

    // MARK: Resultaten

    @ViewBuilder private var resultsContent: some View {
        switch results {
        case .idle, .loading:
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in RowSkeleton().padding(.horizontal, Theme.edge) }
            }
        case .failed:
            ErrorRetryView { Task { await search() } }
                .frame(maxWidth: .infinity)
        case .loaded(let list):
            if list.isEmpty {
                VStack(spacing: tvScaled(12)) {
                    EmptyStateView(symbol: "magnifyingglass", title: L("search.noResults"),
                                   message: worldwide ? L("search.noResultsHint") : L("search.tryWorldwide"))
                    if !worldwide {
                        Button { worldwide = true } label: {
                            Label(L("search.worldwide"), systemImage: "globe")
                                .font(.system(size: tvScaled(14), weight: .bold))
                                .padding(.horizontal, tvScaled(16)).padding(.vertical, tvScaled(9))
                        }
                        .buttonStyle(AccentButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(L("search.resultCount", list.count))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, Theme.edge)
                        .padding(.bottom, tvScaled(6))
                    ForEach(list) { s in
                        StationRowButton(station: s, queue: list, onPlay: { library.addSearch(trimmed) })
                            .padding(.horizontal, Theme.edge)
                        Divider().overlay(Theme.stroke).padding(.leading, Theme.edge + Theme.rowArt + tvScaled(12))
                    }
                }
            }
        }
    }

    private func search() async {
        let q = trimmed
        guard q.count >= 2 else {
            results = .idle
            return
        }
        // debounce 350 ms (de .task wordt bij elke toetsaanslag opnieuw gestart en geannuleerd)
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        if results.value == nil || lastQuery != q { results = .loading }
        do {
            let list = try await RadioBrowser.shared.search(name: q, country: worldwide ? nil : country)
            guard !Task.isCancelled else { return }
            lastQuery = q
            withAnimation(.easeOut(duration: 0.2)) { results = .loaded(list) }
        } catch {
            guard !Task.isCancelled else { return }
            results = .failed
        }
    }
}

extension View {
    /// Toetsenbord wegschuiven bij scrollen (iPhone/iPad)
    @ViewBuilder func scrollDismissesKeyboardIfAvailable() -> some View {
        #if os(iOS)
        self.scrollDismissesKeyboard(.immediately)
        #else
        self
        #endif
    }
}

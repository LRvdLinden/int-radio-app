import SwiftUI

/// Bladeren: raster van grote gekleurde tegels (zoals TuneIn)
struct BrowseView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate

    private struct Tile: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let palette: Int
        var subtitle: String? = nil
        let action: () -> Void
    }

    private var tiles: [Tile] {
        let nav = navigate
        let app = self.app
        let region = library.currentRegion?.name
        return [
            Tile(id: "local", title: L("browse.local"), symbol: "location.fill", palette: 5, subtitle: region) { nav(.regions) },
            Tile(id: "music", title: L("browse.music"), symbol: "music.note.list", palette: 1) { nav(.music) },
            Tile(id: "news", title: L("browse.newsTalk"), symbol: "newspaper.fill", palette: 2) { nav(.newsTalk) },
            Tile(id: "sports", title: L("browse.sports"), symbol: "sportscourt.fill", palette: 3) { nav(.sports) },
            Tile(id: "language", title: L("browse.language"), symbol: "character.bubble.fill", palette: 7) { nav(.languages) },
            Tile(id: "map", title: L("browse.worldMap"), symbol: "globe.europe.africa.fill", palette: 6) {
                app.mapWantsWorld = true
                app.tab = .map
            },
            Tile(id: "top100", title: L("browse.top100"), symbol: "trophy.fill", palette: 0) { nav(.list(.top100)) },
        ]
    }

    private var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
        #else
        return [GridItem(.adaptive(minimum: DeviceKind.isPhone ? 150 : 220), spacing: 14)]
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                #if !os(macOS)
                Text(L("tab.browse"))
                    .font(Theme.screenTitle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.edge)
                    .accessibilityAddTraits(.isHeader)
                #endif

                LazyVGrid(columns: columns, spacing: tvScaled(14)) {
                    ForEach(tiles) { t in
                        Button(action: t.action) {
                            BrowseTile(title: t.title, symbol: t.symbol, paletteIndex: t.palette, subtitle: t.subtitle)
                        }
                        .cardButton()
                    }
                }
                .padding(.horizontal, Theme.edge)
                #if os(tvOS)
                .focusSection()
                #endif

                VStack(alignment: .leading, spacing: tvScaled(10)) {
                    SectionHeader(title: L("row.genres"))
                    GenreChips(horizontal: false)
                        .padding(.horizontal, Theme.edge)
                }
            }
            .padding(.vertical, tvScaled(12))
        }
        .screenBackground()
        #if os(macOS)
        .navigationTitle(L("tab.browse"))
        #elseif os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

/// Bladeren → Muziek: alle muziekgenres als tegels
struct MusicGenresView: View {
    @Environment(\.navigate) private var navigate

    private var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
        #else
        return [GridItem(.adaptive(minimum: DeviceKind.isPhone ? 150 : 200), spacing: 14)]
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: tvScaled(14)) {
                ForEach(Array(Genre.music.enumerated()), id: \.element.id) { i, g in
                    Button {
                        navigate(.list(.genre(tag: g.tag, country: Library.shared.countryCode)))
                    } label: {
                        BrowseTile(title: g.title, symbol: g.symbol, paletteIndex: i)
                    }
                    .cardButton()
                }
            }
            .padding(Theme.edge)
        }
        .screenBackground()
        .navigationTitle(L("browse.music"))
        .inlineTitle()
    }
}

/// Bladeren → Nieuws & Talk: twee secties (news, talk)
struct NewsTalkView: View {
    @EnvironmentObject private var library: Library
    @State private var news: LoadState<[Station]> = .idle
    @State private var talk: LoadState<[Station]> = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                StationShelf(title: L("genre.news"), stations: news.value ?? [],
                             source: .genre(tag: "news", country: library.countryCode),
                             loading: news.isLoading, failed: news.isFailed, onRetry: reload)
                StationShelf(title: L("genre.talk"), stations: talk.value ?? [],
                             source: .genre(tag: "talk", country: library.countryCode),
                             loading: talk.isLoading, failed: talk.isFailed, onRetry: reload)
                if news.value?.isEmpty == true && talk.value?.isEmpty == true {
                    EmptyStateView(symbol: "newspaper", title: L("empty.noStations"), message: L("empty.noStationsHint"))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, tvScaled(12))
        }
        .screenBackground()
        .navigationTitle(L("browse.newsTalk"))
        .inlineTitle()
        .task { if news.value == nil { await load() } }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        let c = library.countryCode
        news = .loading
        talk = .loading
        async let n = try? RadioBrowser.shared.byTag("news", country: c)
        async let t = try? RadioBrowser.shared.byTag("talk", country: c)
        let (nl, tl) = await (n, t)
        withAnimation {
            news = loadState(nl)
            talk = loadState(tl)
        }
    }
}

/// Bladeren → Lokaal: regio's (provincies/staten) in het land
struct LocalRegionsView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate
    @State private var state: LoadState<[RegionState]> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                List { ForEach(0..<12, id: \.self) { _ in RowSkeleton().listRowBackground(Color.clear) } }
                    .hiddenListBackground()
            case .failed:
                ErrorRetryView { Task { await load() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let regions):
                if regions.isEmpty {
                    EmptyStateView(symbol: "location.slash", title: L("local.none"), message: L("local.noneHint"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(regions) { r in regionRow(r) }
                        } footer: {
                            Text(L("local.footer")).foregroundStyle(Theme.secondary)
                        }
                    }
                    .hiddenListBackground()
                }
            }
        }
        .screenBackground()
        .navigationTitle(L("browse.local"))
        .inlineTitle()
        .task(id: library.countryCode) { await load() }
    }

    private func regionRow(_ r: RegionState) -> some View {
        Button {
            library.setLocalRegion(r.name)
            navigate(.list(.region(country: library.countryCode ?? "", name: r.name)))
        } label: {
            HStack(spacing: tvScaled(14)) {
                Image(systemName: library.currentRegion?.name == r.name ? "location.fill" : "mappin.circle")
                    .font(.system(size: tvScaled(20)))
                    .foregroundStyle(library.currentRegion?.name == r.name ? Theme.accent : Theme.secondary)
                    .frame(width: tvScaled(28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(.system(size: tvScaled(16), weight: .semibold)).foregroundStyle(.white)
                    Text(L("stations.count", formattedNumber(r.stationCount)))
                        .font(.system(size: tvScaled(13))).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: tvScaled(12), weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .padding(.vertical, tvScaled(4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
    }

    private func load() async {
        guard !library.countryName.isEmpty else {
            state = .loaded([])
            return
        }
        if state.value == nil { state = .loading }
        do {
            let list = try await RadioBrowser.shared.states(countryName: library.countryName)
            withAnimation { state = .loaded(list) }
        } catch {
            state = .failed
        }
    }
}

/// Bladeren → Op taal (wereldwijd)
struct LanguagesView: View {
    @Environment(\.navigate) private var navigate
    @State private var state: LoadState<[LanguageInfo]> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                List { ForEach(0..<12, id: \.self) { _ in RowSkeleton().listRowBackground(Color.clear) } }
                    .hiddenListBackground()
            case .failed:
                ErrorRetryView { Task { await load() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let langs):
                List(langs) { lang in
                    Button {
                        navigate(.list(.language(name: lang.name, title: lang.displayName)))
                    } label: {
                        HStack {
                            Text(lang.displayName).font(.system(size: tvScaled(16), weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Text(formattedNumber(lang.stationCount))
                                .font(.system(size: tvScaled(13), weight: .medium)).foregroundStyle(Theme.secondary)
                                .monospacedDigit()
                            Image(systemName: "chevron.right").font(.system(size: tvScaled(12), weight: .semibold)).foregroundStyle(Theme.secondary)
                        }
                        .padding(.vertical, tvScaled(4))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                    .accessibilityLabel(lang.displayName + ", " + L("stations.count", formattedNumber(lang.stationCount)))
                }
                .hiddenListBackground()
            }
        }
        .screenBackground()
        .navigationTitle(L("browse.language"))
        .inlineTitle()
        .task { if state.value == nil { await load() } }
    }

    private func load() async {
        state = .loading
        do {
            let list = try await RadioBrowser.shared.languages()
            withAnimation { state = .loaded(list) }
        } catch {
            state = .failed
        }
    }
}

import SwiftUI

/// Een genre-rij op Ontdek
struct GenreRow: Identifiable {
    let tag: String
    let stations: [Station]
    var id: String { tag }
}

/// Data voor Ontdek (per land)
@MainActor
final class DiscoverModel: ObservableObject {
    @Published var popular: LoadState<[Station]> = .idle
    @Published var trending: LoadState<[Station]> = .idle
    @Published var local: LoadState<[Station]> = .idle
    @Published var genreRows: [GenreRow] = []
    /// Populaire podcasts in het land (SPEC §8)
    @Published var podcasts: LoadState<[Podcast]> = .idle
    /// Laatste aflevering van elke gevolgde podcast
    @Published var newEpisodes: [Episode] = []
    @Published var newEpisodesLoading = false
    private(set) var loadedFor: String?
    private var episodesFor: String?

    func load(country: String, region: String?, force: Bool = false) async {
        let key = country + "|" + (region ?? "")
        guard force || loadedFor != key else { return }
        loadedFor = key
        if popular.value == nil || force { popular = .loading }
        if trending.value == nil || force { trending = .loading }

        async let p = RadioBrowser.shared.popular(country: country)
        async let t = RadioBrowser.shared.trending(country: country)
        let pop = try? await p
        let trend = try? await t
        withAnimation(.easeOut(duration: 0.3)) {
            popular = loadState(pop)
            trending = loadState(trend)
        }
        if pop == nil { loadedFor = nil }

        await loadLocal(country: country, region: region)
        await loadPodcasts(country: country, force: force)

        if let tags = try? await RadioBrowser.shared.topGenres(country: country) {
            var rows: [GenreRow] = []
            for tag in tags {
                if let list = try? await RadioBrowser.shared.byTag(tag, country: country), !list.isEmpty {
                    rows.append(GenreRow(tag: tag, stations: list))
                }
            }
            withAnimation(.easeOut(duration: 0.3)) { genreRows = rows }
        }
    }

    func loadPodcasts(country: String, force: Bool = false) async {
        if podcasts.value == nil || force { podcasts = .loading }
        let list = try? await PodcastAPI.shared.topPodcasts(country: country)
        withAnimation(.easeOut(duration: 0.3)) { podcasts = loadState(list) }
    }

    /// Nieuwe afleveringen van gevolgde podcasts (opnieuw als de lijst gevolgde podcasts verandert)
    func loadNewEpisodes(country: String, followed: [String], force: Bool = false) async {
        let key = country + "|" + followed.joined(separator: ",")
        guard force || episodesFor != key else { return }
        episodesFor = key
        guard !followed.isEmpty else {
            newEpisodes = []
            return
        }
        newEpisodesLoading = newEpisodes.isEmpty
        let list = await Library.shared.newEpisodes(country: country)
        withAnimation(.easeOut(duration: 0.3)) {
            newEpisodes = list
            newEpisodesLoading = false
        }
    }

    func loadLocal(country: String, region: String?) async {
        guard let region else {
            local = .idle
            return
        }
        local = .loading
        if let list = try? await RadioBrowser.shared.stations(country: country, state: region) {
            withAnimation(.easeOut(duration: 0.3)) { local = .loaded(list) }
        } else {
            local = .failed
        }
    }
}

/// Ontdek (Home): begroeting, landknop, hero-carrousel en rijen
struct DiscoverView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: RadioPlayer
    @Environment(\.navigate) private var navigate
    @StateObject private var model = DiscoverModel()

    private var country: String { library.countryCode ?? "NL" }
    private var countryName: String { Country.localizedName(code: country, fallback: library.countryName) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.rowSpacing) {
                header

                #if os(tvOS)
                NowPlayingCard()
                #endif

                hero

                if !library.recents.isEmpty {
                    StationShelf(title: L("row.continue"), stations: library.recents, source: .recents)
                }

                localRow

                StationShelf(title: L("row.popularIn", countryName),
                             stations: model.popular.value ?? [],
                             source: .popular(country: country),
                             loading: model.popular.isLoading,
                             failed: model.popular.isFailed,
                             onRetry: reload)

                StationShelf(title: L("row.trending"),
                             stations: model.trending.value ?? [],
                             source: .trending(country: country),
                             loading: model.trending.isLoading,
                             failed: model.trending.isFailed,
                             onRetry: reload)

                // Podcasts (SPEC §8)
                PodcastShelf(title: L("row.popularPodcastsIn", countryName),
                             podcasts: model.podcasts.value ?? [],
                             loading: model.podcasts.isLoading,
                             ranked: true,
                             onAll: { navigate(.podcasts) })

                if !library.followedPodcasts.isEmpty {
                    EpisodeShelf(title: L("row.newEpisodes"), episodes: model.newEpisodes,
                                 loading: model.newEpisodesLoading)
                }

                if !library.continueListening.isEmpty {
                    EpisodeShelf(title: L("row.continueEpisodes"), episodes: library.continueListening)
                }

                if !library.favorites.isEmpty {
                    StationShelf(title: L("row.favorites"), stations: library.favorites, source: .favorites)
                }

                VStack(alignment: .leading, spacing: tvScaled(10)) {
                    SectionHeader(title: L("row.genres"))
                    GenreChips()
                }

                ForEach(model.genreRows) { row in
                    StationShelf(title: L("row.genreIn", Genre.forTag(row.tag).title, countryName),
                                 stations: row.stations,
                                 source: .genre(tag: row.tag, country: country))
                }

                if model.popular.isFailed && model.trending.isFailed {
                    ErrorRetryView(onRetry: reload).frame(maxWidth: .infinity)
                }

                Text(L("about.source"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, tvScaled(20))
            }
            .padding(.vertical, tvScaled(12))
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        #if !os(tvOS)
        .refreshable {
            await model.load(country: country, region: library.currentRegion?.name, force: true)
            await model.loadNewEpisodes(country: country, followed: library.followedPodcasts.map(\.id), force: true)
        }
        #endif
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #elseif os(macOS)
        .navigationTitle(L("tab.discover"))
        #endif
        .task(id: country + "|" + (library.currentRegion?.name ?? "")) {
            await model.load(country: country, region: library.currentRegion?.name)
        }
        .task(id: country + "|" + library.followedPodcasts.map(\.id).joined(separator: ",")) {
            await model.loadNewEpisodes(country: country, followed: library.followedPodcasts.map(\.id))
        }
    }

    private func reload() {
        Task { await model.load(country: country, region: library.currentRegion?.name, force: true) }
    }

    // MARK: Kop

    private var header: some View {
        VStack(alignment: .leading, spacing: tvScaled(10)) {
            HStack(alignment: .center, spacing: tvScaled(12)) {
                TunrLogo(size: tvScaled(24))
                Spacer()
                Button { app.showCountryPicker = true } label: {
                    HStack(spacing: tvScaled(6)) {
                        Text(Country.flag(for: country)).font(.system(size: tvScaled(18)))
                        Text(country).font(.system(size: tvScaled(14), weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, tvScaled(12))
                    .padding(.vertical, tvScaled(7))
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: tvScaled(20)))
                .accessibilityLabel(L("a11y.changeCountry", countryName))

                #if !os(tvOS) && !os(macOS)
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
            Text(Self.greeting())
                .font(Theme.screenTitle)
                .foregroundStyle(.white)
                .padding(.top, tvScaled(6))
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Theme.edge)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    static func greeting(date: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 6..<12: return L("greeting.morning")
        case 12..<18: return L("greeting.afternoon")
        case 18..<24: return L("greeting.evening")
        default: return L("greeting.night")
        }
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        switch model.popular {
        case .idle, .loading:
            HeroSkeleton()
        case .failed:
            EmptyView()
        case .loaded(let list):
            HeroCarousel(stations: Array(list.prefix(6)), queue: list)
        }
    }

    // MARK: Lokaal

    @ViewBuilder private var localRow: some View {
        if let region = library.currentRegion {
            StationShelf(title: L("row.local", region.name),
                         stations: model.local.value ?? [],
                         source: .region(country: country, name: region.name),
                         loading: model.local.isLoading,
                         failed: model.local.isFailed,
                         onRetry: { Task { await model.loadLocal(country: country, region: region.name) } })
        } else {
            VStack(alignment: .leading, spacing: tvScaled(10)) {
                SectionHeader(title: L("row.localTitle"))
                Button { navigate(.regions) } label: {
                    HStack(spacing: tvScaled(14)) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: tvScaled(34)))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: tvScaled(3)) {
                            Text(L("local.choose")).font(.rounded(17)).foregroundStyle(.white)
                            Text(L("local.chooseHint")).font(Theme.caption).foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(tvScaled(16))
                    .background(Theme.paletteGradient(5), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .focusRing()
                }
                .cardButton()
                .padding(.horizontal, Theme.edge)
            }
        }
    }
}

// MARK: - Hero-carrousel

/// Top 6: grote kaart met vervaagde cover-achtergrond, art, naam, genres, Luister en Info
struct HeroCarousel: View {
    let stations: [Station]
    let queue: [Station]

    @State private var index = 0

    var body: some View {
        #if os(tvOS) || os(macOS)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.itemSpacing) {
                ForEach(stations) { s in
                    HeroCard(station: s, queue: queue)
                        .frame(width: heroWidth)
                }
            }
            .padding(.horizontal, Theme.edge)
            #if os(tvOS)
            .padding(.vertical, 24)
            #endif
        }
        .scrollClipDisabled()
        #if os(tvOS)
        .focusSection()
        #endif
        #else
        VStack(spacing: 10) {
            TabView(selection: $index) {
                ForEach(Array(stations.enumerated()), id: \.element.id) { i, s in
                    HeroCard(station: s, queue: queue)
                        .padding(.horizontal, Theme.edge)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Theme.heroHeight)

            HStack(spacing: 6) {
                ForEach(0..<stations.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Theme.accent : Color.white.opacity(0.25))
                        .frame(width: i == index ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: index)
                }
            }
            .accessibilityHidden(true)
        }
        .task(id: stations.map(\.id)) {
            // automatisch doorschuiven
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled, stations.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.5)) { index = (index + 1) % stations.count }
            }
        }
        #endif
    }

    private var heroWidth: CGFloat {
        #if os(tvOS)
        return 1100
        #else
        return 620
        #endif
    }
}

struct HeroCard: View {
    let station: Station
    let queue: [Station]

    @EnvironmentObject private var player: RadioPlayer
    @Environment(\.navigate) private var navigate

    private var isCurrent: Bool { player.station?.id == station.id }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BlurredArt(station: station)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)

            HStack(alignment: .bottom, spacing: tvScaled(16)) {
                StationArt(station: station)
                    .frame(width: artSize, height: artSize)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: tvScaled(6)) {
                    HStack(spacing: tvScaled(6)) {
                        LivePill(compact: true)
                        if isCurrent { EqualizerBars(animating: player.state == .playing, height: tvScaled(12)) }
                    }
                    Text(station.displayName)
                        .font(.rounded(DeviceKind.isPhone ? 22 : 26, .black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if !station.genreLine.isEmpty {
                        Text(station.genreLine)
                            .font(.system(size: tvScaled(13), weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    HStack(spacing: tvScaled(10)) {
                        Button {
                            Haptics.tap()
                            if isCurrent { player.toggle() } else { player.play(station, queue: queue) }
                        } label: {
                            Label(isCurrent && player.isPlaying ? L("player.pause") : L("action.listen"),
                                  systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: tvScaled(14), weight: .bold))
                                .padding(.horizontal, tvScaled(16))
                                .padding(.vertical, tvScaled(9))
                        }
                        .buttonStyle(AccentButtonStyle())
                        Button { navigate(.station(station)) } label: {
                            Label(L("action.info"), systemImage: "info.circle")
                                .font(.system(size: tvScaled(14), weight: .bold))
                                .padding(.horizontal, tvScaled(14))
                                .padding(.vertical, tvScaled(9))
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.top, tvScaled(4))
                }
                Spacer(minLength: 0)
            }
            .padding(tvScaled(18))
        }
        .frame(height: Theme.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius + 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius + 6, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .contextMenu { StationContextMenu(station: station, queue: queue) }
    }

    private var artSize: CGFloat {
        #if os(tvOS)
        return 280
        #elseif os(macOS)
        return 170
        #else
        return DeviceKind.isPhone ? 118 : 170
        #endif
    }
}

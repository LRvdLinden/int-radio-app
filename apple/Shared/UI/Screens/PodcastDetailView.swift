import SwiftUI

/// Podcastpagina: grote art, titel, maker, genre, aantal afleveringen, Favoriet (hartje), uitklapbare beschrijving,
/// Speel nieuwste en de afleveringenlijst (datum, duur, voortgang, ✓) met sorteren Nieuwste/Oudste.
/// iPad/Mac/tv: twee kolommen (art + knoppen links, afleveringen rechts).
struct PodcastDetailView: View {
    let podcast: Podcast

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library
    @State private var info: Podcast?
    @State private var episodes: LoadState<[Episode]> = .idle
    @State private var about = ""
    @State private var expanded = false
    #if os(tvOS)
    @State private var showFullText = false
    #endif
    @AppStorage("ui.episodeSort") private var sort: EpisodeSort = .newest
    #if os(tvOS)
    /// Apple TV: het hartje krijgt bij openen als eerste de focus
    @FocusState private var focus: PodcastDetailFocus?
    #endif

    private var shown: Podcast { info.map { $0.merged(with: podcast) } ?? podcast }
    private var wide: Bool { !DeviceKind.isPhone }
    private var country: String { library.countryCode ?? "NL" }

    private var sortedEpisodes: [Episode] {
        let list = episodes.value ?? []
        return sort == .newest ? list : Array(list.reversed())
    }

    var body: some View {
        Group {
            if wide {
                wideLayout
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: tvScaled(18)) {
                        VStack(spacing: 16) {
                            art.frame(width: artSize).frame(maxWidth: .infinity)
                            titleBlock.frame(maxWidth: .infinity)
                            buttons.frame(maxWidth: .infinity)
                        }
                        descriptionBlock
                        episodeList
                    }
                    .padding(.horizontal, Theme.edge)
                    .padding(.vertical, tvScaled(16))
                }
            }
        }
        .background {
            ZStack {
                Theme.bg
                BlurredPodcastArt(url: shown.artworkURL, name: shown.displayName)
                    .opacity(0.35)
                    .frame(height: 420)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
        .navigationTitle(wide ? shown.displayName : "")
        .inlineTitle()
        #if os(tvOS)
        .defaultFocus($focus, .favorite)
        #endif
        .task(id: podcast.id) { await load() }
    }

    // MARK: Indeling breed

    @ViewBuilder private var wideLayout: some View {
        HStack(alignment: .top, spacing: tvScaled(32)) {
            ScrollView {
                VStack(alignment: .leading, spacing: tvScaled(18)) {
                    art.frame(width: artSize)
                    titleBlock
                    buttons
                    descriptionBlock
                }
                .frame(width: artSize, alignment: .leading)
                .padding(.vertical, tvScaled(16))
                #if os(tvOS)
                .padding(.vertical, 20)
                #endif
            }
            .scrollIndicators(.hidden)
            #if os(tvOS)
            .focusSection()
            #endif
            ScrollView {
                episodeList
                    .padding(.vertical, tvScaled(16))
                    #if os(tvOS)
                    .padding(.vertical, 20)
                    #endif
            }
            .frame(maxWidth: .infinity)
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .padding(.horizontal, Theme.edge)
    }

    private var artSize: CGFloat {
        #if os(tvOS)
        return 480
        #elseif os(macOS)
        return 280
        #else
        return DeviceKind.isPhone ? 240 : 320
        #endif
    }

    private var art: some View {
        PodcastArt(podcast: shown, cornerRadius: Theme.cardRadius + 4)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }

    private var titleBlock: some View {
        VStack(alignment: wide ? .leading : .center, spacing: tvScaled(6)) {
            Text(shown.displayName)
                .font(.rounded(26, .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(wide ? .leading : .center)
                .accessibilityAddTraits(.isHeader)
            if !shown.artist.isEmpty {
                Text(shown.artist)
                    .font(Theme.body)
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(wide ? .leading : .center)
            }
            Text(metaLine)
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !shown.genre.isEmpty { parts.append(shown.genre) }
        let count = max(shown.trackCount, episodes.value?.count ?? 0)
        if count > 0 { parts.append(L("podcast.episodeCount", count)) }
        return parts.joined(separator: " · ")
    }

    private var buttons: some View {
        HStack(spacing: tvScaled(10)) {
            Button {
                Haptics.tap()
                playLatest()
            } label: {
                Label(latestLabel, systemImage: isPlayingHere ? "pause.fill" : "play.fill")
                    .font(.system(size: tvScaled(15), weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, tvScaled(20))
                    .padding(.vertical, tvScaled(12))
            }
            .buttonStyle(AccentButtonStyle())
            .disabled((episodes.value ?? []).isEmpty)

            // Favoriet (hartje, zoals bij zenders); zelfde opslag als "volgen" (followedPodcasts + iCloud)
            Button {
                Haptics.success()
                withAnimation(.spring(response: 0.3)) { library.toggleFollow(shown) }
            } label: {
                FavoriteButtonLabel(isFavorite: library.isFollowing(shown))
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(library.isFollowing(shown) ? L("action.unfavorite") : L("action.favorite"))
            .accessibilityValue(library.isFollowing(shown) ? L("podcast.following") : "")
            #if os(tvOS)
            .focused($focus, equals: .favorite)
            #endif

            #if !os(tvOS)
            Group {
                ShareLink(item: ShareLinks.podcast(shown.id), subject: Text(shown.displayName), message: Text(L("share.podcast", shown.displayName, Brand.name))) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: tvScaled(16), weight: .semibold))
                        .frame(width: tvScaled(44), height: tvScaled(42))
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(L("action.share"))
            }
            #endif
        }
    }

    /// Speelt er nu een aflevering van deze podcast?
    private var isPlayingHere: Bool {
        player.episode?.podcastId == podcast.id && player.isPlaying
    }

    private var latestLabel: String {
        if isPlayingHere { return L("player.pause") }
        if player.episode?.podcastId == podcast.id { return L("player.play") }
        return L("podcast.playLatest")
    }

    private func playLatest() {
        if player.episode?.podcastId == podcast.id {
            player.toggle()
            return
        }
        let list = episodes.value ?? []
        guard let first = list.first else { return }
        player.play(episode: first, queue: list)
    }

    // MARK: Beschrijving

    @ViewBuilder private var descriptionBlock: some View {
        if !about.isEmpty {
            VStack(alignment: .leading, spacing: tvScaled(6)) {
                Text(about)
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondary)
                    #if os(tvOS)
                    .lineLimit(4)   // volledige tekst via "Meer" (schermvullend, scrollbaar)
                    #else
                    .lineLimit(expanded ? nil : 4)
                    #endif
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if about.count > 180 {
                    Button {
                        #if os(tvOS)
                        showFullText = true
                        #else
                        withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                        #endif
                    } label: {
                        Text(expanded ? L("podcast.less") : L("podcast.more"))
                            .font(.system(size: tvScaled(14), weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            #if os(tvOS)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            #endif
                    }
                    .textTVButton()
                    #if os(tvOS)
                    .fullScreenCover(isPresented: $showFullText) { TVLongTextSheet(title: podcast.name, text: about) }
                    #endif
                }
            }
        }
    }

    // MARK: Afleveringen

    @ViewBuilder private var episodeList: some View {
        VStack(alignment: .leading, spacing: tvScaled(8)) {
            HStack {
                Text(L("podcast.episodes"))
                    .font(Theme.rowTitle)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker(L("podcast.sort"), selection: $sort) {
                    ForEach(EpisodeSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: tvScaled(240))
                #if os(macOS)
                .labelsHidden()
                #endif
            }
            switch episodes {
            case .idle, .loading:
                ForEach(0..<6, id: \.self) { _ in RowSkeleton() }
            case .failed:
                ErrorRetryView(title: L("podcasts.errorTitle")) { Task { await load() } }
                    .frame(maxWidth: .infinity)
            case .loaded(let list):
                if list.isEmpty {
                    EmptyStateView(symbol: "mic.slash", title: L("podcast.noEpisodes"), message: L("podcast.noEpisodesHint"))
                        .frame(maxWidth: .infinity)
                } else {
                    let ordered = sortedEpisodes
                    LazyVStack(spacing: 0) {
                        ForEach(ordered) { e in
                            EpisodeRowButton(episode: e, queue: ordered, showArt: false)
                            Divider().overlay(Theme.stroke)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        if episodes.value == nil { episodes = .loading }
        do {
            let result = try await PodcastAPI.shared.lookup(podcast.id, country: country)
            if let p = result.podcast {
                info = p
                library.updateFollowed(p.merged(with: podcast))
            }
            withAnimation(.easeOut(duration: 0.25)) { episodes = .loaded(result.episodes) }
            let feed = (result.podcast?.feedURL ?? "").isEmpty ? podcast.feedURL : (result.podcast?.feedURL ?? "")
            if about.isEmpty, !feed.isEmpty {
                let text = await PodcastAPI.shared.feedDescription(feed)
                withAnimation { about = text }
            }
        } catch {
            if episodes.value == nil { episodes = .failed }
        }
    }
}

#if os(tvOS)
enum PodcastDetailFocus: Hashable { case favorite }
#endif

/// Hartje + "Favoriet" / "In favorieten" (accentkleur als hij favoriet is)
struct FavoriteButtonLabel: View {
    let isFavorite: Bool

    var body: some View {
        Label(isFavorite ? L("podcast.following") : L("podcast.follow"),
              systemImage: isFavorite ? "heart.fill" : "heart")
            .font(.system(size: tvScaled(15), weight: .bold))
            .lineLimit(1)
            .tvAwareForeground(isFavorite ? Theme.accent : .white)
            .padding(.horizontal, tvScaled(18))
            .padding(.vertical, tvScaled(12))
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Afleveringspagina: titel, podcast, datum, duur, volledige omschrijving en Afspelen
struct EpisodeDetailView: View {
    let episode: Episode

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate

    private var isCurrent: Bool { player.episode?.id == episode.id }
    private var wide: Bool { !DeviceKind.isPhone }
    #if os(tvOS)
    @State private var showFullText = false
    #endif

    var body: some View {
        ScrollView {
            Group {
                if wide {
                    HStack(alignment: .top, spacing: tvScaled(32)) {
                        PodcastArt(episode: episode, cornerRadius: Theme.cardRadius + 4)
                            .frame(width: artSize)
                            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                        VStack(alignment: .leading, spacing: tvScaled(16)) { content }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        PodcastArt(episode: episode, cornerRadius: Theme.cardRadius + 4)
                            .frame(width: artSize)
                            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                            .frame(maxWidth: .infinity)
                        content
                    }
                }
            }
            .padding(.horizontal, Theme.edge)
            .padding(.vertical, tvScaled(16))
        }
        .background {
            ZStack {
                Theme.bg
                BlurredPodcastArt(url: episode.artworkURL, name: episode.podcastName)
                    .opacity(0.3)
                    .frame(height: 420)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
        .navigationTitle(wide ? episode.displayTitle : "")
        .inlineTitle()
    }

    private var artSize: CGFloat {
        #if os(tvOS)
        return 420
        #elseif os(macOS)
        return 240
        #else
        return DeviceKind.isPhone ? 200 : 280
        #endif
    }

    @ViewBuilder private var content: some View {
        let status = EpisodeStatus(episode, library: library)
        Button { navigate(.podcast(episode.podcastStub)) } label: {
            HStack(spacing: tvScaled(4)) {
                Text(episode.podcastName)
                Image(systemName: "chevron.right").font(.system(size: tvScaled(11), weight: .bold))
            }
            .font(.system(size: tvScaled(15), weight: .semibold))
            .foregroundStyle(Theme.accent)
            #if os(tvOS)
            .padding(.horizontal, 18).padding(.vertical, 8)
            #endif
        }
        .textTVButton()

        Text(episode.displayTitle)
            .font(.rounded(24, .black))
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)

        Text([PodcastFormat.date(episode.date), PodcastFormat.duration(episode.duration)].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(Theme.caption)
            .foregroundStyle(Theme.secondary)

        if status.started {
            HStack(spacing: tvScaled(8)) {
                ProgressLine(fraction: status.fraction).frame(maxWidth: tvScaled(200))
                if let p = library.position(for: episode.id), p.duration > 0 {
                    Text(L("episode.left", PodcastFormat.duration(max(0, p.duration - p.seconds))))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
        } else if status.finished {
            Label(L("episode.played"), systemImage: "checkmark.circle.fill")
                .font(Theme.caption)
                .foregroundStyle(Theme.accent)
        }

        HStack(spacing: tvScaled(10)) {
            Button {
                Haptics.tap()
                if isCurrent { player.toggle() } else { player.play(episode: episode, queue: [episode]) }
            } label: {
                Label(playTitle(status), systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: tvScaled(16), weight: .bold))
                    .padding(.horizontal, tvScaled(26))
                    .padding(.vertical, tvScaled(12))
            }
            .buttonStyle(AccentButtonStyle())

            Button {
                Haptics.success()
                withAnimation { library.markFinished(episode, !status.finished) }
            } label: {
                Image(systemName: status.finished ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: tvScaled(17), weight: .semibold))
                    .tvAwareForeground(status.finished ? Theme.accent : .white)
                    .frame(width: tvScaled(46), height: tvScaled(44))
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(status.finished ? L("episode.markUnplayed") : L("episode.markPlayed"))

            #if !os(tvOS)
            Group {
                ShareLink(item: ShareLinks.episode(podcastID: episode.podcastId, episodeID: episode.id), subject: Text(episode.displayTitle), message: Text(L("share.podcast", episode.displayTitle, Brand.name))) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: tvScaled(17), weight: .semibold))
                        .frame(width: tvScaled(46), height: tvScaled(44))
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(L("action.share"))
            }
            #endif
        }

        if !episode.summary.isEmpty {
            #if os(tvOS)
            // tv: 5 regels, de rest via "Meer" (schermvullend, elke alinea focusbaar zodat je tot het einde scrolt)
            Text(episode.summary)
                .font(Theme.body)
                .foregroundStyle(Theme.secondary)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if episode.summary.count > 220 {
                Button { showFullText = true } label: {
                    Text(L("podcast.more"))
                        .font(.system(size: tvScaled(14), weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                }
                .textTVButton()
                .fullScreenCover(isPresented: $showFullText) {
                    TVLongTextSheet(title: episode.displayTitle, text: episode.summary)
                }
            }
            #else
            Text(episode.summary)
                .font(Theme.body)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            #endif
        }
    }

    private func playTitle(_ status: EpisodeStatus) -> String {
        if isCurrent { return player.isPlaying ? L("player.pause") : L("player.play") }
        return status.started ? L("episode.resume") : L("player.play")
    }
}

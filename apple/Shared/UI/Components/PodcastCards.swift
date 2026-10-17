import SwiftUI

// MARK: - Podcastcover

/// Vierkante podcastcover in dezelfde stijl als StationArt: verloop uit de naam-hash, de art vult de hele tegel
/// (geen extra witte tegel eromheen), monogram als er geen art is of het laden mislukt.
struct PodcastArt: View {
    let url: URL?
    let name: String
    var cornerRadius: CGFloat = Theme.cardRadius

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let colors = Theme.palette(for: name)
            ZStack {
                LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url {
                    RemoteImage(url: url, contentMode: .fill) { monogram(side) }
                } else {
                    monogram(side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func monogram(_ side: CGFloat) -> some View {
        Text(PodcastFormat.initials(name.isEmpty ? "Podcast" : name))
            .font(.system(size: side * 0.36, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.2), radius: 4)
            .padding(side * 0.08)
    }
}

extension PodcastArt {
    init(podcast: Podcast, cornerRadius: CGFloat = Theme.cardRadius) {
        self.init(url: podcast.artworkURL, name: podcast.displayName, cornerRadius: cornerRadius)
    }

    init(episode: Episode, cornerRadius: CGFloat = Theme.cardRadius) {
        self.init(url: episode.artworkURL, name: episode.podcastName, cornerRadius: cornerRadius)
    }
}

/// Vervaagde achtergrond van een podcastcover (speler, podcastpagina)
struct BlurredPodcastArt: View {
    let url: URL?
    let name: String

    var body: some View {
        PodcastArt(url: url, name: name, cornerRadius: 0)
            .scaleEffect(1.6)
            .blur(radius: 60)
            .saturation(1.4)
            .overlay(Color.black.opacity(0.45))
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Podcastkaart

/// Vierkante podcastkaart: art, titel, maker (optioneel een rangnummer)
struct PodcastCard: View {
    let podcast: Podcast
    var width: CGFloat? = Theme.cardWidth
    var rank: Int? = nil

    @EnvironmentObject private var library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: tvScaled(7)) {
            PodcastArt(podcast: podcast)
                .overlay(alignment: .topLeading) {
                    if let rank {
                        Text("\(rank)")
                            .font(.rounded(15, .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, tvScaled(8)).padding(.vertical, tvScaled(3))
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .padding(tvScaled(8))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if library.isFollowing(podcast) {
                        // favoriet (zelfde opslag als volgen)
                        Image(systemName: "heart.fill")
                            .font(.system(size: tvScaled(11), weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: tvScaled(24), height: tvScaled(24))
                            .background(Theme.accent, in: Circle())
                            .padding(tvScaled(8))
                    }
                }
                .focusRing()
            Text(podcast.displayName)
                .font(.system(size: tvScaled(14), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(podcast.artist.isEmpty ? podcast.genre : podcast.artist)
                .font(.system(size: tvScaled(12), weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(podcast.displayName + (podcast.artist.isEmpty ? "" : ", " + podcast.artist))
    }
}

/// Knop rond een podcastkaart: tik = podcastpagina, contextmenu met Favoriet
struct PodcastCardButton: View {
    let podcast: Podcast
    var width: CGFloat? = Theme.cardWidth
    var rank: Int? = nil

    @Environment(\.navigate) private var navigate

    var body: some View {
        Button {
            Haptics.tap()
            navigate(.podcast(podcast))
        } label: {
            PodcastCard(podcast: podcast, width: width, rank: rank)
        }
        .cardButton()
        .contextMenu { PodcastContextMenu(podcast: podcast) }
        .accessibilityHint(L("a11y.openPodcast"))
    }
}

struct PodcastContextMenu: View {
    let podcast: Podcast
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button { navigate(.podcast(podcast)) } label: {
            Label(L("podcast.open"), systemImage: "info.circle")
        }
        // Favoriet (hartje, zoals bij zenders); opslag = gevolgde podcasts
        Button { library.toggleFollow(podcast) } label: {
            if library.isFollowing(podcast) {
                Label(L("podcast.unfollow"), systemImage: "heart.slash")
            } else {
                Label(L("action.favorite"), systemImage: "heart")
            }
        }
    }
}

/// Rij voor podcastlijsten (genummerde toplijst, zoekresultaten)
struct PodcastRow: View {
    let podcast: Podcast
    var rank: Int? = nil

    @EnvironmentObject private var library: Library

    var body: some View {
        HStack(spacing: tvScaled(12)) {
            if let rank {
                Text("\(rank)")
                    .font(.rounded(15, .black))
                    .foregroundStyle(rank <= 3 ? Theme.accent : Theme.secondary)
                    .frame(width: tvScaled(30))
                    .monospacedDigit()
            }
            PodcastArt(podcast: podcast, cornerRadius: tvScaled(10))
                .frame(width: Theme.rowArt, height: Theme.rowArt)
            VStack(alignment: .leading, spacing: tvScaled(3)) {
                HStack(spacing: tvScaled(6)) {
                    Text(podcast.displayName)
                        .font(.system(size: tvScaled(16), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if library.isFollowing(podcast) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: tvScaled(10)))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                Text(podcast.detailLine)
                    .font(.system(size: tvScaled(13), weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: tvScaled(8))
            Image(systemName: "chevron.right")
                .font(.system(size: tvScaled(12), weight: .semibold))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, tvScaled(6))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(podcast.displayName + ", " + podcast.detailLine)
    }
}

struct PodcastRowButton: View {
    let podcast: Podcast
    var rank: Int? = nil
    /// Extra actie na tikken (bv. zoekopdracht onthouden)
    var onOpen: (() -> Void)? = nil
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button {
            Haptics.tap()
            onOpen?()
            navigate(.podcast(podcast))
        } label: {
            PodcastRow(podcast: podcast, rank: rank)
                #if os(tvOS)
                .padding(.horizontal, 16)
                .background(RowFocusBackground())
                #endif
        }
        #if os(tvOS)
        .buttonStyle(TVLiftStyle(scale: 1.03, border: false))
        #else
        .buttonStyle(PressableStyle())
        #endif
        .contextMenu { PodcastContextMenu(podcast: podcast) }
    }
}

/// Horizontale rij met podcastkaarten
struct PodcastShelf: View {
    let title: String
    let podcasts: [Podcast]
    var loading = false
    var failed = false
    var ranked = false
    var onRetry: (() -> Void)? = nil
    var onAll: (() -> Void)? = nil

    var body: some View {
        if loading || failed || !podcasts.isEmpty {
            VStack(alignment: .leading, spacing: tvScaled(10)) {
                SectionHeader(title: title,
                              actionTitle: onAll != nil && !podcasts.isEmpty ? L("action.all") : nil,
                              action: onAll)
                if failed && podcasts.isEmpty {
                    InlineError(onRetry: onRetry)
                        .padding(.horizontal, Theme.edge)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Theme.itemSpacing) {
                            if loading && podcasts.isEmpty {
                                ForEach(0..<8, id: \.self) { _ in CardSkeleton() }
                            } else {
                                ForEach(Array(podcasts.prefix(30).enumerated()), id: \.element.id) { i, p in
                                    PodcastCardButton(podcast: p, rank: ranked ? i + 1 : nil)
                                }
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
        }
    }
}

// MARK: - Aflevering

/// Dunne voortgangsbalk (positie in een aflevering)
struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = tvScaled(3)
    var track: Color = Color.white.opacity(0.15)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(Theme.gradient)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Status van een aflevering voor deze gebruiker
struct EpisodeStatus {
    let fraction: Double
    let finished: Bool
    let started: Bool

    @MainActor init(_ e: Episode, library: Library) {
        let p = library.position(for: e.id)
        finished = p?.finished ?? false
        fraction = p?.fraction ?? 0
        started = !finished && (p?.seconds ?? 0) >= 15
    }
}

/// Rij voor de afleveringenlijst: datum · duur, titel, korte omschrijving, voortgang of ✓
struct EpisodeRow: View {
    let episode: Episode
    var showPodcast = false
    var showArt = true

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library

    private var isCurrent: Bool { player.episode?.id == episode.id }

    var body: some View {
        let status = EpisodeStatus(episode, library: library)
        HStack(alignment: .top, spacing: tvScaled(12)) {
            if showArt {
                PodcastArt(episode: episode, cornerRadius: tvScaled(10))
                    .frame(width: Theme.rowArt, height: Theme.rowArt)
            }
            VStack(alignment: .leading, spacing: tvScaled(4)) {
                HStack(spacing: tvScaled(6)) {
                    Text(metaLine)
                        .font(.system(size: tvScaled(11), weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    if status.finished {
                        Label(L("episode.played"), systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: tvScaled(12)))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(episode.displayTitle)
                    .font(.system(size: tvScaled(15), weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent ? Theme.accent : (status.finished ? Theme.secondary : .white))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !episode.shortSummary.isEmpty {
                    Text(episode.shortSummary)
                        .font(.system(size: tvScaled(13), weight: .regular))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if status.started {
                    ProgressLine(fraction: status.fraction)
                        .frame(maxWidth: tvScaled(160))
                        .padding(.top, tvScaled(2))
                }
            }
            Spacer(minLength: tvScaled(6))
            if isCurrent {
                EqualizerBars(animating: player.state == .playing, height: tvScaled(16))
                    .padding(.top, tvScaled(4))
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: tvScaled(26)))
                    .foregroundStyle(Theme.gradient)
                    .padding(.top, tvScaled(2))
            }
        }
        .padding(.vertical, tvScaled(8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(episode.displayTitle + ", " + metaLine)
        .accessibilityValue(isCurrent ? L("a11y.nowPlaying") : (status.finished ? L("episode.played") : ""))
    }

    private var metaLine: String {
        var parts: [String] = []
        if showPodcast { parts.append(episode.podcastName) }
        let d = PodcastFormat.date(episode.date)
        if !d.isEmpty { parts.append(d) }
        let dur = PodcastFormat.duration(episode.duration)
        if !dur.isEmpty { parts.append(dur) }
        return parts.joined(separator: " · ")
    }
}

/// Knop rond een EpisodeRow: tik = afspelen (in de lijst); contextmenu met Info, Beluisterd e.d.
struct EpisodeRowButton: View {
    let episode: Episode
    var queue: [Episode] = []
    var showPodcast = false
    var showArt = true

    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        Button {
            Haptics.tap()
            player.play(episode: episode, queue: queue)
        } label: {
            EpisodeRow(episode: episode, showPodcast: showPodcast, showArt: showArt)
                #if os(tvOS)
                .padding(.horizontal, 16)
                .background(RowFocusBackground())
                #endif
        }
        #if os(tvOS)
        .buttonStyle(TVLiftStyle(scale: 1.02, border: false))
        #else
        .buttonStyle(PressableStyle())
        #endif
        .contextMenu { EpisodeContextMenu(episode: episode, queue: queue) }
        .accessibilityHint(L("a11y.playEpisodeHint"))
    }
}

struct EpisodeContextMenu: View {
    let episode: Episode
    var queue: [Episode] = []

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button { player.play(episode: episode, queue: queue) } label: {
            Label(L("action.play"), systemImage: "play.fill")
        }
        Button { navigate(.episode(episode)) } label: {
            Label(L("episode.details"), systemImage: "info.circle")
        }
        Button { navigate(.podcast(episode.podcastStub)) } label: {
            Label(L("episode.goToPodcast"), systemImage: "square.stack")
        }
        Button { library.toggleFollow(episode.podcastStub) } label: {
            if library.isFollowing(podcastId: episode.podcastId) {
                Label(L("podcast.unfavoritePodcast"), systemImage: "heart.slash")
            } else {
                Label(L("podcast.favoritePodcast"), systemImage: "heart")
            }
        }
        if library.position(for: episode.id)?.finished == true {
            Button { library.markFinished(episode, false) } label: {
                Label(L("episode.markUnplayed"), systemImage: "circle")
            }
        } else {
            Button { library.markFinished(episode) } label: {
                Label(L("episode.markPlayed"), systemImage: "checkmark.circle")
            }
        }
    }
}

/// Kaart voor afleveringen in een horizontale rij (Nieuwe afleveringen, Verder luisteren)
struct EpisodeCard: View {
    let episode: Episode
    var width: CGFloat? = Theme.cardWidth

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library

    private var isCurrent: Bool { player.episode?.id == episode.id }

    var body: some View {
        let status = EpisodeStatus(episode, library: library)
        VStack(alignment: .leading, spacing: tvScaled(7)) {
            PodcastArt(episode: episode)
                .overlay(alignment: .bottom) {
                    if status.started {
                        ProgressLine(fraction: status.fraction, height: tvScaled(4), track: Color.black.opacity(0.45))
                            .padding(tvScaled(8))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isCurrent {
                        EqualizerBars(animating: player.state == .playing, color: .white, height: tvScaled(14))
                            .padding(tvScaled(7))
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: tvScaled(8), style: .continuous))
                            .padding(tvScaled(8))
                    }
                }
                .focusRing()
            Text(episode.displayTitle)
                .font(.system(size: tvScaled(14), weight: .bold, design: .rounded))
                .foregroundStyle(isCurrent ? Theme.accent : .white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text([episode.podcastName, PodcastFormat.date(episode.date)].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: tvScaled(12), weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(episode.displayTitle + ", " + episode.podcastName)
    }
}

/// Horizontale rij met afleveringen; tik = afspelen
struct EpisodeShelf: View {
    let title: String
    let episodes: [Episode]
    var loading = false

    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        if loading || !episodes.isEmpty {
            VStack(alignment: .leading, spacing: tvScaled(10)) {
                SectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.itemSpacing) {
                        if loading && episodes.isEmpty {
                            ForEach(0..<6, id: \.self) { _ in CardSkeleton() }
                        } else {
                            ForEach(episodes.prefix(30)) { e in
                                Button {
                                    Haptics.tap()
                                    player.play(episode: e, queue: episodes)
                                } label: {
                                    EpisodeCard(episode: e)
                                }
                                .cardButton()
                                .contextMenu { EpisodeContextMenu(episode: e, queue: episodes) }
                                .accessibilityHint(L("a11y.playEpisodeHint"))
                            }
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
    }
}

// MARK: - Segment Zenders · Podcasts

/// Wat doorzocht wordt op Zoeken
enum SearchKind: String, CaseIterable, Identifiable {
    case stations, podcasts
    var id: String { rawValue }
    var title: String { self == .stations ? L("search.kindStations") : L("search.kindPodcasts") }
}

import SwiftUI

/// Zenderdetail: grote art, naam, plaats, knoppen (Afspelen, Favoriet, Delen, Website), Nu speelt-kaart,
/// genre-chips, info-raster en vergelijkbare zenders. iPad/Mac/tv: twee kolommen.
struct StationDetailView: View {
    let station: Station

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate
    @Environment(\.openURL) private var openURL
    @State private var similar: LoadState<[Station]> = .idle

    private var isCurrent: Bool { player.station?.id == station.id }
    private var wide: Bool { !DeviceKind.isPhone }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if wide {
                    HStack(alignment: .top, spacing: tvScaled(32)) {
                        art.frame(width: artSize)
                        VStack(alignment: .leading, spacing: tvScaled(18)) {
                            titleBlock
                            buttons
                            nowPlayingCard
                            chips
                            infoGrid
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Theme.edge)
                    #if os(tvOS)
                    .focusSection()
                    #endif
                } else {
                    VStack(spacing: 18) {
                        art.frame(width: artSize).frame(maxWidth: .infinity)
                        titleBlock.frame(maxWidth: .infinity)
                        buttons.frame(maxWidth: .infinity)
                        nowPlayingCard
                        chips
                        infoGrid
                    }
                    .padding(.horizontal, Theme.edge)
                }

                StationShelf(title: L("detail.similar"),
                             stations: similar.value ?? [],
                             loading: similar.isLoading && similar.value == nil,
                             failed: false)
            }
            .padding(.vertical, tvScaled(16))
        }
        .background {
            ZStack {
                Theme.bg
                BlurredArt(station: station)
                    .opacity(0.35)
                    .frame(height: 420)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
        .navigationTitle(wide ? station.displayName : "")
        .inlineTitle()
        .task(id: station.id) { await loadSimilar() }
    }

    private var artSize: CGFloat {
        #if os(tvOS)
        return 520
        #elseif os(macOS)
        return 280
        #else
        return DeviceKind.isPhone ? 260 : 340
        #endif
    }

    private var art: some View {
        StationArt(station: station, cornerRadius: Theme.cardRadius + 4, overrideURL: isCurrent ? player.artworkURL : nil)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .overlay(alignment: .bottomTrailing) {
                if isCurrent {
                    EqualizerBars(animating: player.state == .playing, color: .white, height: tvScaled(18))
                        .padding(tvScaled(10))
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: tvScaled(10), style: .continuous))
                        .padding(tvScaled(12))
                }
            }
    }

    private var titleBlock: some View {
        VStack(alignment: wide ? .leading : .center, spacing: tvScaled(6)) {
            Text(station.displayName)
                .font(.rounded(28, .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(wide ? .leading : .center)
                .accessibilityAddTraits(.isHeader)
            if !station.placeLine.isEmpty {
                Text(station.placeLine)
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: tvScaled(10)) {
            Button {
                Haptics.tap()
                if isCurrent { player.toggle() } else { player.play(station, queue: [station] + (similar.value ?? [])) }
            } label: {
                Label(isCurrent && player.isPlaying ? L("player.pause") : L("player.play"),
                      systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: tvScaled(16), weight: .bold))
                    .padding(.horizontal, tvScaled(26))
                    .padding(.vertical, tvScaled(12))
            }
            .buttonStyle(AccentButtonStyle())

            iconButton(library.isFavorite(station) ? "heart.fill" : "heart",
                       label: library.isFavorite(station) ? L("action.unfavorite") : L("action.favorite"),
                       tint: library.isFavorite(station) ? Theme.accent : .white) {
                Haptics.success()
                withAnimation(.spring(response: 0.3)) { library.toggleFavorite(station) }
            }

            #if !os(tvOS)
            ShareLink(item: shareURL, subject: Text(station.displayName), message: Text(shareText)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: tvScaled(17), weight: .semibold))
                    .frame(width: tvScaled(46), height: tvScaled(44))
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(L("action.share"))

            if let home = station.homepageURL {
                iconButton("safari", label: L("detail.website"), tint: .white) { openURL(home) }
            }
            #endif
        }
    }

    private var shareURL: URL { station.homepageURL ?? station.streamURL ?? Brand.website }
    private var shareText: String { L("share.text", station.displayName, Brand.name) }

    private func iconButton(_ symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: tvScaled(17), weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: tvScaled(46), height: tvScaled(44))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder private var nowPlayingCard: some View {
        if isCurrent {
            HStack(spacing: tvScaled(12)) {
                StationArt(station: station, cornerRadius: tvScaled(8), overrideURL: player.artworkURL)
                    .frame(width: tvScaled(52), height: tvScaled(52))
                VStack(alignment: .leading, spacing: tvScaled(3)) {
                    HStack(spacing: tvScaled(6)) {
                        LivePill(compact: true)
                        Text(L("player.nowPlaying")).font(Theme.caption).foregroundStyle(Theme.secondary)
                    }
                    Text(nowPlayingText)
                        .font(.system(size: tvScaled(15), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(tvScaled(12))
            .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var nowPlayingText: String {
        if let p = ArtworkLookup.split(player.nowPlaying) { return p.artist + " — " + p.title }
        return player.nowPlaying.isEmpty ? L("player.liveRadio") : player.nowPlaying
    }

    @ViewBuilder private var chips: some View {
        if !station.tagList.isEmpty {
            FlowLayout(spacing: tvScaled(8)) {
                ForEach(station.tagList, id: \.self) { tag in
                    GenreChip(title: Genre.forTag(tag).title) {
                        navigate(.list(.genre(tag: tag, country: station.countryCode.isEmpty ? nil : station.countryCode)))
                    }
                }
            }
        }
    }

    private var infoGrid: some View {
        let items: [(String, String)] = [
            (L("info.codec"), station.codec.isEmpty ? "—" : station.codec.uppercased()),
            (L("info.bitrate"), station.bitrateText.isEmpty ? "—" : station.bitrateText),
            (L("info.language"), station.language.isEmpty ? "—" : station.language.capitalized),
            (L("info.votes"), formattedNumber(station.votes)),
            (L("info.listeners"), formattedNumber(station.clickCount)),
            (L("info.hls"), station.hls ? L("common.yes") : L("common.no")),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: tvScaled(140)), spacing: tvScaled(10))], spacing: tvScaled(10)) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: tvScaled(4)) {
                    Text(item.0.uppercased())
                        .font(.system(size: tvScaled(10), weight: .heavy, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(Theme.secondary)
                    Text(item.1)
                        .font(.system(size: tvScaled(15), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(tvScaled(12))
                .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: tvScaled(12), style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func loadSimilar() async {
        guard let tag = station.tagList.first else {
            similar = .loaded([])
            return
        }
        similar = .loading
        let country = station.countryCode.isEmpty ? nil : station.countryCode
        let list = (try? await RadioBrowser.shared.byTag(tag, country: country, limit: 30)) ?? []
        withAnimation { similar = .loaded(list.filter { $0.id != station.id }) }
    }
}

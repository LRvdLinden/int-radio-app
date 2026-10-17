import SwiftUI

/// Speler in aflevering-modus (SPEC §8): geen LIVE-pil maar een tijdbalk (sleepbaar op iPhone/iPad/Mac) met
/// verstreken/resterende tijd, knoppen vorige · 15 s terug · afspelen/pauze · 30 s vooruit · volgende,
/// favoriet (de podcast), snelheid, slaaptimer (incl. "Einde van aflevering"), delen en afleveringsinfo.
/// tvOS: tijdbalk focusbaar; links/rechts op de afstandsbediening = −15/+30 s; snelheid/slaaptimer als keuzelijst.
struct EpisodePlayerContent: View {
    let episode: Episode

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library
    @State private var showInfo = false
    #if os(tvOS)
    /// Apple TV: snelheid en slaaptimer als keuzelijst (een Menu werkt op tv niet prettig met de focus)
    @State private var showSpeed = false
    @State private var showSleep = false
    @FocusState private var focus: PlayerFocus?
    #endif

    private var isFavorite: Bool { library.isFollowing(podcastId: episode.podcastId) }

    var body: some View {
        content
            #if os(tvOS)
            .confirmationDialog(L("player.speed"), isPresented: $showSpeed, titleVisibility: .visible) {
                ForEach(RadioPlayer.rates, id: \.self) { r in
                    Button((r == player.rate ? "✓ " : "") + PodcastFormat.rate(r)) { player.setRate(r) }
                }
                Button(L("action.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L("player.sleepTimer"), isPresented: $showSleep, titleVisibility: .visible) {
                Button(L("sleep.endOfEpisode")) { player.setSleepAtEpisodeEnd() }
                ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                    Button(L("sleep.minutes", m)) { player.setSleepTimer(minutes: m) }
                }
                Button(L("sleep.off"), role: player.sleepActive ? .destructive : nil) { player.setSleepTimer(minutes: 0) }
                Button(L("action.cancel"), role: .cancel) {}
            }
            #endif
            .sheet(isPresented: $showInfo) {
                NavStack {
                    EpisodeDetailView(episode: episode)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("action.done")) { showInfo = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 560)
                #endif
            }
    }

    @ViewBuilder private var content: some View {
        #if os(tvOS)
        HStack(spacing: 80) {
            artwork.frame(width: 600)
            VStack(alignment: .leading, spacing: 36) {
                titles(alignment: .leading)
                EpisodeTimeBar(progress: player.progress)
                transport
                actions(includeFavorite: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
        .padding(80)
        // afspelen/pauze krijgt als eerste de focus (niet de tijdbalk)
        .defaultFocus($focus, .play)
        #else
        GeometryReader { geo in
            let wide = geo.size.width > 700 && geo.size.width > geo.size.height
            if wide {
                VStack(spacing: 0) {
                    PlayerTopBar()
                    Spacer(minLength: 0)
                    HStack(spacing: 48) {
                        artwork.frame(width: min(geo.size.height * 0.55, 440))
                        VStack(alignment: .leading, spacing: 22) {
                            titles(alignment: .leading)
                            EpisodeTimeBar(progress: player.progress)
                            transport
                            PlayerVolumeRow()
                            actions(includeFavorite: true)
                        }
                        .frame(maxWidth: 480)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 18) {
                    PlayerTopBar()
                    Spacer(minLength: 0)
                    artwork.frame(maxWidth: min(geo.size.width - 64, 360))
                    Spacer(minLength: 0)
                    // smal (iPhone): het hartje naast de titel, zodat de actierij past
                    HStack(alignment: .center, spacing: 8) {
                        Color.clear.frame(width: 40, height: 40)
                        titles(alignment: .center)
                        favoriteIconButton
                    }
                    EpisodeTimeBar(progress: player.progress)
                    transport
                    PlayerVolumeRow()
                    actions(includeFavorite: false)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
        }
        #endif
    }

    private var artwork: some View {
        PodcastArt(episode: episode, cornerRadius: Theme.cardRadius + 6)
            .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
            .scaleEffect(player.state == .playing ? 1 : 0.92)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.state)
            .id(episode.id)
            .transition(.opacity)
    }

    private func titles(alignment: HorizontalAlignment) -> some View {
        let textAlign: TextAlignment = alignment == .center ? .center : .leading
        return VStack(alignment: alignment, spacing: tvScaled(6)) {
            Text(episode.displayTitle)
                .font(.rounded(22, .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(textAlign)
            Text([episode.podcastName, PodcastFormat.date(episode.date)].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: tvScaled(15), weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .multilineTextAlignment(textAlign)
            if player.state == .failed {
                VStack(alignment: alignment, spacing: tvScaled(8)) {
                    Label(L("player.episodeFailed"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: tvScaled(14), weight: .semibold))
                        .foregroundStyle(Theme.live)
                    Button { player.retry() } label: {
                        Label(L("action.retry"), systemImage: "arrow.clockwise")
                            .font(.system(size: tvScaled(14), weight: .bold))
                            .padding(.horizontal, tvScaled(16)).padding(.vertical, tvScaled(8))
                    }
                    .buttonStyle(AccentButtonStyle())
                }
                .padding(.top, tvScaled(6))
            } else if player.sleepAtEpisodeEnd {
                Label(L("sleep.endOfEpisodeActive"), systemImage: "moon.zzz.fill")
                    .font(.system(size: tvScaled(12), weight: .semibold))
                    .foregroundStyle(Theme.accent2)
                    .padding(.top, tvScaled(2))
            } else if let end = player.sleepEnd {
                Label(L("sleep.until", end.formatted(date: .omitted, time: .shortened)), systemImage: "moon.zzz.fill")
                    .font(.system(size: tvScaled(12), weight: .semibold))
                    .foregroundStyle(Theme.accent2)
                    .padding(.top, tvScaled(2))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private var transport: some View {
        HStack(spacing: tvScaled(DeviceKind.isPhone ? 18 : 26)) {
            Button { Haptics.tap(); player.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: tvScaled(20), weight: .semibold))
                    .frame(width: tvScaled(44), height: tvScaled(56))
            }
            .buttonStyle(TransportButtonStyle())
            .disabled(!player.hasPrevious)
            .accessibilityLabel(L("player.previousEpisode"))

            Button { Haptics.tap(); player.skip(-RadioPlayer.skipBack) } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: tvScaled(28), weight: .semibold))
                    .frame(width: tvScaled(56), height: tvScaled(56))
            }
            .buttonStyle(TransportButtonStyle())
            .accessibilityLabel(L("player.back15"))

            Button { Haptics.rigid(); player.toggle() } label: {
                ZStack {
                    if player.state == .loading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: tvScaled(32), weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                            .offset(x: player.state == .playing ? 0 : tvScaled(2))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: tvScaled(78), height: tvScaled(78))
                .background(Theme.gradient, in: Circle())
                .shadow(color: Theme.accent.opacity(0.5), radius: 18, y: 6)
            }
            .buttonStyle(TransportButtonStyle(scale: 1.1))
            .accessibilityLabel(player.state == .playing ? L("player.pause") : L("player.play"))
            #if os(iOS)
            .keyboardShortcut(.space, modifiers: [])
            #elseif os(tvOS)
            .focused($focus, equals: .play)
            #endif

            Button { Haptics.tap(); player.skip(RadioPlayer.skipForward) } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: tvScaled(28), weight: .semibold))
                    .frame(width: tvScaled(56), height: tvScaled(56))
            }
            .buttonStyle(TransportButtonStyle())
            .accessibilityLabel(L("player.forward30"))

            Button { Haptics.tap(); player.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: tvScaled(20), weight: .semibold))
                    .frame(width: tvScaled(44), height: tvScaled(56))
            }
            .buttonStyle(TransportButtonStyle())
            .disabled(!player.hasNext)
            .accessibilityLabel(L("player.nextEpisode"))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    private func toggleFavorite() {
        Haptics.success()
        withAnimation(.spring(response: 0.3)) { library.toggleFollow(episode.podcastStub) }
    }

    /// Alleen het hartje (smalle speler, naast de titel)
    private var favoriteIconButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.accent : .white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.12), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(isFavorite ? L("podcast.unfavoritePodcast") : L("podcast.favoritePodcast"))
    }

    private func actions(includeFavorite: Bool) -> some View {
        HStack(spacing: tvScaled(12)) {
            if includeFavorite {
                // Favoriet: de podcast van deze aflevering (zelfde opslag als volgen); tv: eerste knop van de rij
                Button(action: toggleFavorite) {
                    ActionLabel(symbol: isFavorite ? "heart.fill" : "heart",
                                title: isFavorite ? L("podcast.following") : L("podcast.follow"),
                                tint: isFavorite ? Theme.accent : .white)
                }
                #if os(tvOS)
                .buttonStyle(TVLiftStyle(scale: 1.1, border: false))
                #else
                .buttonStyle(PressableStyle())
                #endif
                .accessibilityLabel(isFavorite ? L("podcast.unfavoritePodcast") : L("podcast.favoritePodcast"))
            }

            #if os(tvOS)
            Button { showSpeed = true } label: {
                ActionLabel(symbol: "speedometer", title: L("player.speed"),
                            tint: player.rate == 1 ? .white : Theme.accent2, text: PodcastFormat.rate(player.rate))
            }
            .buttonStyle(TVLiftStyle(scale: 1.1, border: false))
            .accessibilityLabel(L("player.speed") + ", " + PodcastFormat.rate(player.rate))

            Button { showSleep = true } label: {
                ActionLabel(symbol: player.sleepActive ? "moon.zzz.fill" : "moon.zzz",
                            title: L("player.sleepTimer"),
                            tint: player.sleepActive ? Theme.accent2 : .white)
            }
            .buttonStyle(TVLiftStyle(scale: 1.1, border: false))
            #else
            Menu {
                ForEach(RadioPlayer.rates, id: \.self) { r in
                    Button {
                        player.setRate(r)
                    } label: {
                        if r == player.rate {
                            Label(PodcastFormat.rate(r), systemImage: "checkmark")
                        } else {
                            Text(PodcastFormat.rate(r))
                        }
                    }
                }
            } label: {
                ActionLabel(symbol: "speedometer", title: L("player.speed"),
                            tint: player.rate == 1 ? .white : Theme.accent2, text: PodcastFormat.rate(player.rate))
            }
            #if os(macOS)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            #endif
            .accessibilityLabel(L("player.speed") + ", " + PodcastFormat.rate(player.rate))

            Menu {
                Button(L("sleep.endOfEpisode")) { player.setSleepAtEpisodeEnd() }
                ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                    Button(L("sleep.minutes", m)) { player.setSleepTimer(minutes: m) }
                }
                Button(L("sleep.off"), role: player.sleepActive ? .destructive : nil) { player.setSleepTimer(minutes: 0) }
            } label: {
                ActionLabel(symbol: player.sleepActive ? "moon.zzz.fill" : "moon.zzz",
                            title: L("player.sleepTimer"),
                            tint: player.sleepActive ? Theme.accent2 : .white)
            }
            #if os(macOS)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            #endif
            #endif

            #if !os(tvOS)
            Group {
                ShareLink(item: ShareLinks.episode(podcastID: episode.podcastId, episodeID: episode.id), subject: Text(episode.displayTitle),
                          message: Text(L("share.podcast", episode.displayTitle, Brand.name))) {
                    ActionLabel(symbol: "square.and.arrow.up", title: L("action.share"), tint: .white)
                }
                .buttonStyle(PressableStyle())
            }
            #endif

            Button { showInfo = true } label: {
                ActionLabel(symbol: "info.circle", title: L("player.episodeInfo"), tint: .white)
            }
            #if os(tvOS)
            .buttonStyle(TVLiftStyle(scale: 1.1, border: false))
            #else
            .buttonStyle(PressableStyle())
            #endif
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tijdbalk

/// Tijdbalk met verstreken en resterende tijd. iPhone/iPad/Mac: sleepbaar (Slider). Apple TV: Slider bestaat
/// niet, dus een balk die focus kan krijgen; links/rechts op de afstandsbediening = −15/+30 s.
struct EpisodeTimeBar: View {
    @ObservedObject var progress: PlaybackProgress
    @EnvironmentObject private var player: RadioPlayer

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    #if os(tvOS)
    @FocusState private var focused: Bool
    #endif

    private var shownTime: Double { scrubbing ? scrubValue : progress.currentTime }
    private var remaining: Double { max(0, progress.duration - shownTime) }

    var body: some View {
        VStack(spacing: tvScaled(6)) {
            bar
            HStack {
                Text(PodcastFormat.clock(shownTime))
                Spacer()
                Text(progress.duration > 0 ? "−" + PodcastFormat.clock(remaining) : "--:--")
            }
            .font(.system(size: tvScaled(12), weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.secondary)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("player.position"))
        .accessibilityValue(L("player.positionValue", PodcastFormat.clock(shownTime), PodcastFormat.clock(progress.duration)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.skip(RadioPlayer.skipForward)
            case .decrement: player.skip(-RadioPlayer.skipBack)
            @unknown default: break
            }
        }
    }

    @ViewBuilder private var bar: some View {
        #if os(tvOS)
        ProgressLine(fraction: progress.duration > 0 ? progress.currentTime / progress.duration : 0,
                     height: focused ? 14 : 8, track: Color.white.opacity(0.2))
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(focused ? Color.white.opacity(0.12) : Color.clear, in: Capsule())
            .overlay(alignment: .center) {
                if focused {
                    HStack {
                        Label("15", systemImage: "chevron.left")
                        Spacer()
                        Label("30", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
                    }
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(y: 36)
                }
            }
            .focusable()
            .focused($focused)
            .onMoveCommand { direction in
                switch direction {
                case .left: player.skip(-RadioPlayer.skipBack)
                case .right: player.skip(RadioPlayer.skipForward)
                default: break
                }
            }
            .animation(.easeOut(duration: 0.15), value: focused)
        #else
        Slider(value: Binding(get: { shownTime },
                              set: { scrubValue = $0 }),
               in: 0...max(1, progress.duration),
               onEditingChanged: { editing in
                   if editing {
                       scrubValue = progress.currentTime
                       scrubbing = true
                   } else {
                       player.seek(to: scrubValue)
                       scrubbing = false
                   }
               })
            .tint(Theme.accent)
            .disabled(progress.duration <= 0)
        #endif
    }
}

#if os(tvOS)
/// Label met het icoon rechts ("30 >")
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}
#endif

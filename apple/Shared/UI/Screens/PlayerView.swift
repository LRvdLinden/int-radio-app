import SwiftUI
import AVKit
import MediaPlayer

/// Volledige speler: vervaagde art als achtergrond, LIVE-pil, grote art (hoes of zender), titel,
/// vorige · play/pauze · volgende, favoriet, AirPlay (iOS/Mac), volume (iOS), en een rij
/// "Meer van deze zender": Delen (niet op tv), Slaaptimer, Zenderinfo.
struct PlayerView: View {
    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showInfo = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let s = player.station {
                BlurredArt(station: s, overrideURL: player.artworkURL)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.6), value: player.artworkURL)
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                content(s)
            } else {
                EmptyStateView(symbol: "radio", title: L("player.nothing"), message: L("player.nothingHint"))
            }
        }
        .sheet(isPresented: $showInfo) {
            if let s = player.station {
                NavStack {
                    StationDetailView(station: s)
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
        #if os(tvOS)
        .onPlayPauseCommand { player.toggle() }
        #endif
        #if os(tvOS) || os(macOS)
        .onExitCommand { dismiss() }
        #endif
    }

    @ViewBuilder private func content(_ s: Station) -> some View {
        #if os(tvOS)
        HStack(spacing: 80) {
            artwork(s).frame(width: 640)
            VStack(alignment: .leading, spacing: 36) {
                titles(s, alignment: .leading)
                transport(s)
                actions(s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
        .padding(80)
        #else
        GeometryReader { geo in
            let wide = geo.size.width > 700 && geo.size.width > geo.size.height
            if wide {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    HStack(spacing: 48) {
                        artwork(s).frame(width: min(geo.size.height * 0.6, 460))
                        VStack(alignment: .leading, spacing: 26) {
                            titles(s, alignment: .leading)
                            transport(s)
                            volumeRow
                            actions(s)
                        }
                        .frame(maxWidth: 460)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 22) {
                    topBar
                    Spacer(minLength: 0)
                    artwork(s).frame(maxWidth: min(geo.size.width - 64, 380))
                    Spacer(minLength: 0)
                    titles(s, alignment: .center)
                    transport(s)
                    volumeRow
                    actions(s)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
        }
        #endif
    }

    #if !os(tvOS)
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(L("action.close"))
            Spacer()
            TunrLogo(size: 15)
            Spacer()
            RoutePicker()
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.12), in: Circle())
                .accessibilityLabel(L("player.airplay"))
        }
    }
    #endif

    private func artwork(_ s: Station) -> some View {
        VStack(spacing: tvScaled(14)) {
            LivePill()
            StationArt(station: s, cornerRadius: Theme.cardRadius + 6, overrideURL: player.artworkURL)
                .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
                .scaleEffect(player.state == .playing ? 1 : 0.92)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.state)
                .id(player.artworkURL?.absoluteString ?? s.id)
                .transition(.opacity)
        }
    }

    private func titles(_ s: Station, alignment: HorizontalAlignment) -> some View {
        let parts = ArtworkLookup.split(player.nowPlaying)
        let textAlign: TextAlignment = alignment == .center ? .center : .leading
        return VStack(alignment: alignment, spacing: tvScaled(6)) {
            HStack(spacing: tvScaled(8)) {
                if player.state == .playing { EqualizerBars(animating: true, height: tvScaled(14)) }
                Text(parts?.title ?? s.displayName)
                    .font(.rounded(24, .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(textAlign)
            }
            Text(secondLine(s))
                .font(.system(size: tvScaled(15), weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .multilineTextAlignment(textAlign)
            if player.state == .failed {
                VStack(alignment: alignment, spacing: tvScaled(8)) {
                    Label(L("player.unreachable"), systemImage: "exclamationmark.triangle.fill")
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
            } else if let end = player.sleepEnd {
                Label(L("sleep.until", end.formatted(date: .omitted, time: .shortened)), systemImage: "moon.zzz.fill")
                    .font(.system(size: tvScaled(12), weight: .semibold))
                    .foregroundStyle(Theme.accent2)
                    .padding(.top, tvScaled(2))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .animation(.easeInOut(duration: 0.25), value: player.nowPlaying)
    }

    /// Artiest · zender, of genres/plaats als er geen nummer bekend is
    private func secondLine(_ s: Station) -> String {
        if let p = ArtworkLookup.split(player.nowPlaying) { return p.artist + " · " + s.displayName }
        return s.genreLine.isEmpty ? s.placeLine : s.genreLine
    }

    private func transport(_ s: Station) -> some View {
        HStack(spacing: tvScaled(34)) {
            Button { Haptics.tap(); player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: tvScaled(26), weight: .semibold))
                    .frame(width: tvScaled(56), height: tvScaled(56))
            }
            .buttonStyle(TransportButtonStyle())
            .disabled(!player.hasNext)
            .accessibilityLabel(L("player.previous"))

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
            #endif

            Button { Haptics.tap(); player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: tvScaled(26), weight: .semibold))
                    .frame(width: tvScaled(56), height: tvScaled(56))
            }
            .buttonStyle(TransportButtonStyle())
            .disabled(!player.hasNext)
            .accessibilityLabel(L("player.next"))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var volumeRow: some View {
        #if os(iOS)
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            SystemVolumeSlider().frame(height: 34)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .contain)
        #elseif os(macOS)
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Slider(value: Binding(get: { Double(player.volume) }, set: { player.volume = Float($0) }), in: 0...1)
                .tint(Theme.accent)
                .accessibilityLabel(L("player.volume"))
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            RoutePicker().frame(width: 28, height: 28).accessibilityLabel(L("player.airplay"))
        }
        #else
        EmptyView()
        #endif
    }

    private func actions(_ s: Station) -> some View {
        HStack(spacing: tvScaled(12)) {
            actionButton(library.isFavorite(s) ? "heart.fill" : "heart",
                         title: L("player.favorite"),
                         tint: library.isFavorite(s) ? Theme.accent : .white) {
                Haptics.success()
                withAnimation(.spring(response: 0.3)) { player.toggleFavoriteCurrent() }
            }

            #if !os(tvOS)
            ShareLink(item: s.homepageURL ?? s.streamURL ?? Brand.website,
                      subject: Text(s.displayName),
                      message: Text(L("share.text", s.displayName, Brand.name))) {
                ActionLabel(symbol: "square.and.arrow.up", title: L("action.share"), tint: .white)
            }
            .buttonStyle(PressableStyle())
            #endif

            Menu {
                ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                    Button(L("sleep.minutes", m)) { player.setSleepTimer(minutes: m) }
                }
                Button(L("sleep.off"), role: player.sleepEnd == nil ? nil : .destructive) { player.setSleepTimer(minutes: 0) }
            } label: {
                ActionLabel(symbol: player.sleepEnd == nil ? "moon.zzz" : "moon.zzz.fill",
                            title: L("player.sleepTimer"),
                            tint: player.sleepEnd == nil ? .white : Theme.accent2)
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            #endif

            actionButton("info.circle", title: L("player.stationInfo"), tint: .white) { showInfo = true }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButton(_ symbol: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ActionLabel(symbol: symbol, title: title, tint: tint)
        }
        #if os(tvOS)
        .buttonStyle(TVLiftStyle(scale: 1.1, border: false))
        #else
        .buttonStyle(PressableStyle())
        #endif
    }
}

/// Icoon + bijschrift voor de actierij
private struct ActionLabel: View {
    let symbol: String
    let title: String
    let tint: Color
    @Environment(\.tvFocused) private var focused

    var body: some View {
        VStack(spacing: tvScaled(6)) {
            Image(systemName: symbol)
                .font(.system(size: tvScaled(19), weight: .semibold))
                .foregroundStyle(focused ? Color.black : tint)
                .frame(width: tvScaled(50), height: tvScaled(50))
                .background(focused ? Color.white : Color.white.opacity(0.12), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.system(size: tvScaled(11), weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: tvScaled(70))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// Transportknoppen: indrukken; tv: lift zonder grijs vlak
private struct TransportButtonStyle: ButtonStyle {
    var scale: CGFloat = 1.15
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, scale: scale)
    }
    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        private var isFocused: Bool {
            #if os(tvOS)
            return focused
            #else
            return false
            #endif
        }
        var body: some View {
            configuration.label
                .opacity(enabled ? 1 : 0.35)
                .scaleEffect(configuration.isPressed ? 0.9 : (isFocused ? scale : 1))
                .shadow(color: .white.opacity(isFocused ? 0.35 : 0), radius: 14)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
        }
    }
}

// MARK: - AirPlay en volume

#if os(iOS)
/// AirPlay-knop (AVRoutePickerView)
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(red: 1, green: 0.353, blue: 0.122, alpha: 1)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Systeemvolume (MPVolumeView zonder routeknop)
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.tintColor = UIColor(red: 1, green: 0.353, blue: 0.122, alpha: 1)
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#elseif os(macOS)
/// AirPlay-knop (AVRoutePickerView) op de Mac
struct RoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.isRoutePickerButtonBordered = false
        return v
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif

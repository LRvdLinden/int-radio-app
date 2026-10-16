import SwiftUI

/// Miniplayer boven de tabbalk (iPhone) of onderaan het venster (iPad, Mac).
/// Art 44 pt, naam, nu-speelt of genres, play/pauze, (telefoon) volgende. Tik → volledige speler.
struct MiniPlayer: View {
    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library

    var body: some View {
        if let s = player.station {
            HStack(spacing: 12) {
                Button {
                    app.showPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        StationArt(station: s, cornerRadius: 9, overrideURL: player.artworkURL)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(s.displayName)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if player.state == .playing {
                                    EqualizerBars(animating: true, height: 11)
                                }
                            }
                            Text(statusText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(player.state == .failed ? Theme.live : Theme.secondary)
                                .lineLimit(1)
                                .id(statusText)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .animation(.easeOut(duration: 0.25), value: statusText)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("a11y.openPlayer") + ", " + s.displayName)

                #if os(macOS)
                Button {
                    library.toggleFavorite(s)
                } label: {
                    Image(systemName: library.isFavorite(s) ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(library.isFavorite(s) ? Theme.accent : .white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(library.isFavorite(s) ? L("action.unfavorite") : L("action.favorite"))

                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 15, weight: .semibold)).frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(!player.hasNext)
                .accessibilityLabel(L("player.previous"))
                #endif

                Button {
                    Haptics.tap()
                    player.toggle()
                } label: {
                    ZStack {
                        if player.state == .loading {
                            ProgressView().smallControl().tint(.white)
                        } else {
                            Image(systemName: player.state == .playing ? "pause.fill" : (player.state == .failed ? "arrow.clockwise" : "play.fill"))
                                .font(.system(size: 18, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.gradient, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(player.state == .playing ? L("player.pause") : L("player.play"))

                if !DeviceKind.isPad {
                    Button {
                        Haptics.tap()
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(player.hasNext ? .white : Theme.secondary)
                            .frame(width: 36, height: 40)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!player.hasNext)
                    .accessibilityLabel(L("player.next"))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.elevated.opacity(0.75))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: DeviceKind.isPhone ? CGFloat.infinity : 720)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var statusText: String {
        switch player.state {
        case .loading: return L("player.connecting")
        case .failed: return L("player.unreachable")
        default: return player.subtitle.isEmpty ? L("player.liveRadio") : player.subtitle
        }
    }
}

/// tvOS: "Nu aan het spelen"-kaart bovenaan Ontdek
struct NowPlayingCard: View {
    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var app: AppState

    var body: some View {
        if let s = player.station {
            Button {
                app.showPlayer = true
            } label: {
                HStack(spacing: tvScaled(16)) {
                    StationArt(station: s, cornerRadius: tvScaled(12), overrideURL: player.artworkURL)
                        .frame(width: tvScaled(80), height: tvScaled(80))
                    VStack(alignment: .leading, spacing: tvScaled(4)) {
                        HStack(spacing: tvScaled(8)) {
                            Text(L("player.nowPlaying").uppercased())
                                .font(.system(size: tvScaled(11), weight: .heavy, design: .rounded))
                                .kerning(1.2)
                                .foregroundStyle(Theme.accent)
                            EqualizerBars(animating: player.state == .playing, height: tvScaled(11))
                        }
                        Text(s.displayName).font(.rounded(20)).foregroundStyle(.white).lineLimit(1)
                        Text(player.subtitle.isEmpty ? L("player.liveRadio") : player.subtitle)
                            .font(.system(size: tvScaled(13), weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: player.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: tvScaled(36)))
                        .foregroundStyle(Theme.gradient)
                }
                .padding(tvScaled(14))
                .background {
                    ZStack {
                        BlurredArt(station: s, overrideURL: player.artworkURL)
                        Theme.surface.opacity(0.55)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .focusRing()
            }
            .cardButton()
            .padding(.horizontal, Theme.edge)
            .accessibilityLabel(L("player.nowPlaying") + ": " + s.displayName)
        }
    }
}

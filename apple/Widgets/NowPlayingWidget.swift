import WidgetKit
import SwiftUI
import AppIntents

/// Widget "Nu speelt": logo, zender, nummer en een afspeel-/pauzeknop.
/// Beginscherm (klein, middel), vergrendelscherm (rond, rechthoekig, regel), CarPlay op iOS 26 (klein) en de Mac.
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nowPlaying, provider: TunrProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetText.t("widget.nowPlaying.name"))
        .description(WidgetText.t("widget.nowPlaying.description"))
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        return [.systemSmall, .systemMedium]
        #endif
    }
}

struct NowPlayingWidgetView: View {
    let entry: TunrEntry
    @Environment(\.widgetFamily) private var family

    private var np: WidgetNowPlaying? { entry.snapshot.nowPlaying }

    var body: some View {
        content
            .widgetURL(np.map { stationURL($0.station.id) } ?? URL(string: "tunr://open"))
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
        switch family {
        case .accessoryCircular:
            circular.containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            inline.containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            medium.containerBackground(for: .widget) { WidgetTheme.background }
        default:
            small.containerBackground(for: .widget) { WidgetTheme.background }
        }
        #else
        switch family {
        case .systemMedium:
            medium.containerBackground(for: .widget) { WidgetTheme.background }
        default:
            small.containerBackground(for: .widget) { WidgetTheme.background }
        }
        #endif
    }

    // MARK: Beginscherm

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                if let np {
                    StationLogoView(station: np.station, size: 54, coverFile: np.isPlaying ? np.coverFile : nil)
                } else {
                    TunrMark(size: 22, showName: false)
                }
                Spacer(minLength: 4)
                playButton(size: 34)
            }
            Spacer(minLength: 6)
            if let np {
                statusLine(np)
                Text(np.station.displayName)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
                Text(trackOrCountry(np))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetTheme.secondary)
                    .lineLimit(2)
            } else {
                emptyText
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            if let np {
                StationLogoView(station: np.station, size: 112, cornerRadius: 20, coverFile: np.isPlaying ? np.coverFile : nil)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(WidgetTheme.elevated)
                    TunrMark(size: 30, showName: false)
                }
                .frame(width: 112, height: 112)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    TunrMark(size: 12)
                    Spacer(minLength: 4)
                }
                Spacer(minLength: 2)
                if let np {
                    statusLine(np)
                    Text(np.station.displayName)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(trackOrCountry(np))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WidgetTheme.secondary)
                        .lineLimit(2)
                } else {
                    emptyText
                }
                Spacer(minLength: 2)
                HStack {
                    Spacer()
                    playButton(size: 38)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func statusLine(_ np: WidgetNowPlaying) -> some View {
        HStack(spacing: 5) {
            EqualizerBars(isPlaying: np.isPlaying, height: 10, color: np.isPlaying ? WidgetTheme.accent : WidgetTheme.secondary)
            Text(np.isPlaying ? WidgetText.t("widget.live") : WidgetText.t("widget.paused"))
                .font(.system(size: 10, weight: .heavy))
                .kerning(0.6)
                .foregroundStyle(np.isPlaying ? WidgetTheme.accent : WidgetTheme.secondary)
        }
    }

    private var emptyText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WidgetText.t("widget.nothing"))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(WidgetText.t("widget.openApp"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetTheme.secondary)
                .lineLimit(2)
        }
    }

    private func trackOrCountry(_ np: WidgetNowPlaying) -> String {
        if np.isPlaying, !np.trackLine.isEmpty { return np.trackLine }
        return np.station.country
    }

    /// Ronde oranje knop: afspelen/pauze (TogglePlaybackIntent, draait in de app)
    private func playButton(size: CGFloat) -> some View {
        let playing = np?.isPlaying ?? false
        return Button(intent: TogglePlaybackIntent()) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(WidgetTheme.gradient, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? WidgetText.t("widget.pause") : WidgetText.t("widget.play"))
    }

    // MARK: Vergrendelscherm

    #if os(iOS)
    private var circular: some View {
        let playing = np?.isPlaying ?? false
        return Button(intent: TogglePlaybackIntent()) {
            VStack(spacing: 1) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(np.map { String($0.station.displayName.prefix(6)) } ?? "Tunr")
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel(playing ? WidgetText.t("widget.pause") : WidgetText.t("widget.play"))
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: (np?.isPlaying ?? false) ? "waveform" : "radio")
                        .font(.system(size: 11, weight: .bold))
                    Text(np?.station.displayName ?? "Tunr")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
                .widgetAccentable()
                if let np {
                    Text(np.isPlaying && !np.trackLine.isEmpty ? np.trackLine
                         : (np.isPlaying ? WidgetText.t("widget.live") : WidgetText.t("widget.paused")))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                } else {
                    Text(WidgetText.t("widget.openApp"))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if np != nil {
                Button(intent: TogglePlaybackIntent()) {
                    Image(systemName: (np?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        let text: String
        if let np {
            text = np.isPlaying && !np.trackLine.isEmpty ? np.station.displayName + " · " + np.trackLine : np.station.displayName
        } else {
            text = "Tunr"
        }
        return Label(text, systemImage: (np?.isPlaying ?? false) ? "waveform" : "radio")
    }
    #endif
}

#if DEBUG
struct NowPlayingWidget_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingWidgetView(entry: TunrEntry(date: Date(), snapshot: .sample))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
        NowPlayingWidgetView(entry: TunrEntry(date: Date(), snapshot: .sample))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
#endif

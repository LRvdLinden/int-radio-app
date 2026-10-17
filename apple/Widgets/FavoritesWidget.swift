import WidgetKit
import SwiftUI
import AppIntents

/// Widget "Favorieten": raster met favoriete zenders (anders de laatst beluisterde); tik = afspelen in de app.
struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.favorites, provider: TunrProvider()) { entry in
            FavoritesWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.background }
        }
        .configurationDisplayName(WidgetText.t("widget.favorites.name"))
        .description(WidgetText.t("widget.favorites.description"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct FavoritesWidgetView: View {
    let entry: TunrEntry
    @Environment(\.widgetFamily) private var family

    private var stations: [WidgetStation] {
        let favs = entry.snapshot.favorites
        let list = favs.isEmpty ? entry.snapshot.recents : favs
        return Array(list.prefix(family == .systemLarge ? 8 : 4))
    }

    private var playingID: String? {
        guard let np = entry.snapshot.nowPlaying, np.isPlaying else { return nil }
        return np.station.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            HStack {
                TunrMark(size: 13)
                Spacer()
                Text(WidgetText.t("widget.favorites.name"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetTheme.secondary)
            }
            if stations.isEmpty {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(WidgetText.t("widget.favorites.empty"))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(WidgetText.t("widget.favorites.emptyHint"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetTheme.secondary)
                }
                Spacer(minLength: 0)
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "tunr://open"))
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        let size: CGFloat = family == .systemLarge ? 64 : 54
        return LazyVGrid(columns: columns, alignment: .leading, spacing: family == .systemLarge ? 14 : 8) {
            ForEach(stations) { s in
                Button(intent: PlayStationIntent(stationID: s.id)) {
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottomTrailing) {
                            StationLogoView(station: s, size: size)
                            if playingID == s.id {
                                EqualizerBars(isPlaying: true, height: 10, color: .white)
                                    .padding(4)
                                    .background(WidgetTheme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .padding(3)
                            }
                        }
                        Text(s.displayName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .frame(maxWidth: size + 8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WidgetText.t("widget.play") + ": " + s.displayName)
            }
        }
    }
}

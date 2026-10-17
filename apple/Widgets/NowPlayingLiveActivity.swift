#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Live Activity "Nu speelt": vergrendelscherm en Dynamic Island (compact, minimaal, uitgeklapt), met
/// afspelen/pauze en stop. De app start en werkt hem bij (LiveActivityController).
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            LiveLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(widgetHex: 0x121216))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "tunr://player"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StationLogoView(station: station(context.attributes), size: 52, fileName: context.attributes.logoFile)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveButtons(isPlaying: context.state.isPlaying, size: 36)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.stationName)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(subtitle(context.attributes, context.state))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WidgetTheme.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        EqualizerBars(isPlaying: context.state.isPlaying, height: 10,
                                      color: context.state.isPlaying ? WidgetTheme.accent : WidgetTheme.secondary)
                        Text(context.state.isPlaying ? WidgetText.t("widget.live") : WidgetText.t("widget.paused"))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(context.state.isPlaying ? WidgetTheme.accent : WidgetTheme.secondary)
                        Spacer()
                        TunrMark(size: 11)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                StationLogoView(station: station(context.attributes), size: 24, cornerRadius: 6, fileName: context.attributes.logoFile)
            } compactTrailing: {
                EqualizerBars(isPlaying: context.state.isPlaying, height: 14,
                              color: context.state.isPlaying ? WidgetTheme.accent : WidgetTheme.secondary)
            } minimal: {
                StationLogoView(station: station(context.attributes), size: 22, cornerRadius: 11, fileName: context.attributes.logoFile)
            }
            .widgetURL(URL(string: "tunr://player"))
            .keylineTint(WidgetTheme.accent)
        }
    }
}

private func station(_ a: NowPlayingAttributes) -> WidgetStation {
    WidgetStation(id: a.stationID, name: a.stationName, country: a.country, countryCode: "", logoURL: nil)
}

private func subtitle(_ a: NowPlayingAttributes, _ s: NowPlayingAttributes.ContentState) -> String {
    if s.isPlaying, !s.trackLine.isEmpty { return s.trackLine }
    return a.country
}

/// Vergrendelscherm (en Apple Watch / CarPlay waar het systeem deze weergave gebruikt)
struct LiveLockScreenView: View {
    let attributes: NowPlayingAttributes
    let state: NowPlayingAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            StationLogoView(station: station(attributes), size: 56, cornerRadius: 14, fileName: attributes.logoFile)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    EqualizerBars(isPlaying: state.isPlaying, height: 10,
                                  color: state.isPlaying ? WidgetTheme.accent : WidgetTheme.secondary)
                    Text(state.isPlaying ? WidgetText.t("widget.live") : WidgetText.t("widget.paused"))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(state.isPlaying ? WidgetTheme.accent : WidgetTheme.secondary)
                    Spacer(minLength: 4)
                    TunrMark(size: 11)
                }
                Text(attributes.stationName)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle(attributes, state))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WidgetTheme.secondary)
                    .lineLimit(1)
            }
            LiveButtons(isPlaying: state.isPlaying, size: 38)
        }
        .padding(14)
    }
}

/// Afspelen/pauze + stop (LiveActivityIntent: draait in de app)
struct LiveButtons: View {
    let isPlaying: Bool
    let size: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: LiveTogglePlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(WidgetTheme.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? WidgetText.t("widget.pause") : WidgetText.t("widget.play"))
            Button(intent: LiveStopPlaybackIntent()) {
                Image(systemName: "stop.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WidgetText.t("widget.stop"))
        }
    }
}
#endif

#if os(iOS)
import WidgetKit
import SwiftUI
import AppIntents

/// Knop in het Bedieningspaneel, op het vergrendelscherm en voor de Actieknop (iOS 18): Tunr afspelen of pauzeren.
@available(iOSApplicationExtension 18.0, *)
struct PlaybackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.control, provider: Provider()) { isPlaying in
            ControlWidgetToggle(LocalizedStringKey("control.title"), isOn: isPlaying, action: SetPlaybackIntent()) { on in
                Label(on ? LocalizedStringKey("control.playing") : LocalizedStringKey("control.paused"),
                      systemImage: on ? "pause.fill" : "play.fill")
            }
        }
        .displayName("control.title")
        .description("control.description")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            WidgetBridge.load().nowPlaying?.isPlaying ?? false
        }
    }
}
#endif

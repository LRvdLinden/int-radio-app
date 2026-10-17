#if os(iOS) || os(macOS)
import Foundation
import AppIntents

// App Intents voor de widgets, het Bedieningspaneel en de Live Activity. Dit bestand zit in de app én in de
// extensie. Omdat de intents AudioPlaybackIntent / LiveActivityIntent zijn, voert het systeem ze uit in het
// proces van de app (op de achtergrond, zonder de app te openen); daar gaan ze via `TunrIntentHandler.shared`
// naar de speler. Draait een intent toch in de extensie (`WIDGET_EXTENSION`), dan blijft er een opdracht in de
// App Group staan die de app bij de volgende start uitvoert.

/// Wat de app met de intents doet (geïmplementeerd in de app: AppIntentHandler in WidgetSync.swift)
@MainActor
protocol TunrIntentHandling: AnyObject {
    /// Zender met deze stationuuid afspelen
    func playStation(id: String) async
    /// Afspelen/pauze (niets geladen: de laatste zender)
    func togglePlayback() async
    /// Afspelen (`true`) of pauze (`false`)
    func setPlaying(_ playing: Bool) async
    /// Stoppen (Live Activity verdwijnt)
    func stopPlayback() async
}

/// Haak die de app bij het starten vult
@MainActor
enum TunrIntentHandler {
    static var shared: TunrIntentHandling?
}

/// Voert een intent uit in de app, of laat in de extensie een opdracht achter
enum TunrIntentRunner {
    @MainActor static func play(stationID: String) async {
        #if WIDGET_EXTENSION
        WidgetBridge.setPendingCommand("play:" + stationID)
        #else
        TunrIntentHandler.ensureAppHandler()
        await TunrIntentHandler.shared?.playStation(id: stationID)
        #endif
    }

    @MainActor static func toggle() async {
        #if WIDGET_EXTENSION
        WidgetBridge.setPendingCommand("toggle")
        #else
        TunrIntentHandler.ensureAppHandler()
        await TunrIntentHandler.shared?.togglePlayback()
        #endif
    }

    @MainActor static func setPlaying(_ playing: Bool) async {
        #if WIDGET_EXTENSION
        WidgetBridge.setPendingCommand(playing ? "play" : "pause")
        #else
        TunrIntentHandler.ensureAppHandler()
        await TunrIntentHandler.shared?.setPlaying(playing)
        #endif
    }

    @MainActor static func stop() async {
        #if WIDGET_EXTENSION
        WidgetBridge.setPendingCommand("stop")
        #else
        TunrIntentHandler.ensureAppHandler()
        await TunrIntentHandler.shared?.stopPlayback()
        #endif
    }
}

// MARK: - Widgets (beginscherm, vergrendelscherm)

/// Tik op een zender in een widget: die zender afspelen
struct PlayStationIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play Station"
    static var description: IntentDescription = IntentDescription("Plays a radio station in Tunr.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Station ID")
    var stationID: String

    init() {}

    init(stationID: String) {
        self.stationID = stationID
    }

    func perform() async throws -> some IntentResult {
        await TunrIntentRunner.play(stationID: stationID)
        return .result()
    }
}

/// Afspelen/pauze (widgets)
struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause Tunr"
    static var description: IntentDescription = IntentDescription("Plays or pauses the radio in Tunr.")

    init() {}

    func perform() async throws -> some IntentResult {
        await TunrIntentRunner.toggle()
        return .result()
    }
}

#if os(iOS)
// MARK: - Live Activity (knoppen in de Dynamic Island en op het vergrendelscherm)

/// Afspelen/pauze vanuit de Live Activity
struct LiveTogglePlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play or Pause Tunr"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await TunrIntentRunner.toggle()
        return .result()
    }
}

/// Stoppen vanuit de Live Activity
struct LiveStopPlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Tunr"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await TunrIntentRunner.stop()
        return .result()
    }
}

// MARK: - Bedieningspaneel (iOS 18)

/// Knop in het Bedieningspaneel / op het vergrendelscherm / de Actieknop: afspelen of pauze
@available(iOS 18.0, *)
struct SetPlaybackIntent: SetValueIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause Tunr"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Playing")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        await TunrIntentRunner.setPlaying(value)
        return .result()
    }
}
#endif
#endif

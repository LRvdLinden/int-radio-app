#if os(iOS) && canImport(ActivityKit)
import Foundation
import ActivityKit

/// Live Activity "Nu speelt" (Dynamic Island, vergrendelscherm, CarPlay op iOS 26, Apple Watch Smart Stack).
/// Gedeeld: de app start/werkt bij/stopt hem (LiveActivityController), de extensie tekent hem.
struct NowPlayingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Titel van het nummer (leeg als de zender niets meldt)
        var title: String
        /// Artiest (leeg als onbekend)
        var artist: String
        var isPlaying: Bool
        /// Begin van het luisteren naar deze zender
        var startedAt: Date

        var trackLine: String {
            if !artist.isEmpty, !title.isEmpty { return artist + " – " + title }
            return title
        }
    }

    var stationID: String
    var stationName: String
    var country: String
    /// Bestandsnaam van het verkleinde logo in de App Group (zie WidgetBridge)
    var logoFile: String
}
#endif

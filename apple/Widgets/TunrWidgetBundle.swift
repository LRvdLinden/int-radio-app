import WidgetKit
import SwiftUI

/// Alle widgets van Tunr: "Nu speelt" en "Favorieten" (beginscherm, vergrendelscherm, Mac, CarPlay op iOS 26),
/// de Live Activity (Dynamic Island, vergrendelscherm) en de knop in het Bedieningspaneel (iOS 18).
@main
struct TunrWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        FavoritesWidget()
        #if os(iOS)
        NowPlayingLiveActivity()
        if #available(iOSApplicationExtension 18.0, *) {
            PlaybackControl()
        }
        #endif
    }
}

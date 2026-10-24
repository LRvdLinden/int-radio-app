import Foundation
import Combine

/// Waar de Watch afspeelt: op de iPhone (afstandsbediening) of op de Watch zelf (met AirPods/koptelefoon)
enum PlaybackTarget: String, CaseIterable, Identifiable {
    case phone, watch
    var id: String { rawValue }
}

/// Favorieten, recent en gekozen land op de Watch. Bron 1: de iPhone-app via WatchConnectivity (applicationContext,
/// meteen en ook zonder iCloud); bron 2: iCloud (dezelfde sleutels als Library in de iPhone-app: lib.favorites,
/// lib.recents, lib.country). Lokaal bewaard, zodat de lijsten ook zonder iPhone in de buurt werken.
@MainActor
final class WatchStore: ObservableObject {
    static let shared = WatchStore()

    @Published private(set) var favorites: [WStation] = []
    @Published private(set) var recents: [WStation] = []
    @Published private(set) var countryCode: String = ""
    /// Zenders die op de Watch zelf speelden (nieuwste eerst, max. 20)
    @Published private(set) var watchRecents: [WStation] = []

    @Published var target: PlaybackTarget {
        didSet { defaults.set(target.rawValue, forKey: K.target) }
    }
    @Published var shareStats: Bool {
        didSet { defaults.set(shareStats, forKey: K.shareStats) }
    }

    private enum K {
        static let favorites = "lib.favorites"
        static let favoritesStamp = "lib.favorites.stamp"
        static let recents = "lib.recents"
        static let country = "lib.country"
        static let watchRecents = "watch.recents"
        static let target = "watch.target"
        static let shareStats = "settings.shareStats"
    }

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    private init() {
        target = PlaybackTarget(rawValue: defaults.string(forKey: "watch.target") ?? "") ?? .phone
        shareStats = defaults.object(forKey: "settings.shareStats") as? Bool ?? true
        favorites = WJSON.stations(defaults.data(forKey: K.favorites))
        recents = WJSON.stations(defaults.data(forKey: K.recents))
        watchRecents = WJSON.stations(defaults.data(forKey: K.watchRecents))
        countryCode = defaults.string(forKey: K.country) ?? ""
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.loadFromCloud() }
        }
        _ = cloud.synchronize()
        loadFromCloud()
    }

    /// iCloud: alleen gebruiken als de iPhone (nog) niets stuurde of iCloud nieuwer is
    private func loadFromCloud() {
        let favs = WJSON.stations(cloud.data(forKey: K.favorites))
        if !favs.isEmpty, cloud.double(forKey: K.favoritesStamp) >= defaults.double(forKey: K.favoritesStamp) {
            setFavorites(favs, stamp: cloud.double(forKey: K.favoritesStamp))
        }
        let rec = WJSON.stations(cloud.data(forKey: K.recents))
        if recents.isEmpty, !rec.isEmpty { setRecents(rec) }
        if let cc = cloud.string(forKey: K.country), !cc.isEmpty, countryCode.isEmpty { setCountry(cc) }
    }

    /// Gegevens van de iPhone (WatchConnectivity)
    func apply(phoneContext ctx: [String: Any]) {
        if let d = ctx["favorites"] as? Data {
            setFavorites(WJSON.stations(d), stamp: ctx["favoritesStamp"] as? Double ?? Date().timeIntervalSince1970)
        }
        if let d = ctx["recents"] as? Data { setRecents(WJSON.stations(d)) }
        if let cc = ctx["country"] as? String, !cc.isEmpty { setCountry(cc) }
    }

    private func setFavorites(_ list: [WStation], stamp: Double) {
        guard list != favorites || stamp != defaults.double(forKey: K.favoritesStamp) else { return }
        favorites = list
        defaults.set(WJSON.data(list), forKey: K.favorites)
        defaults.set(stamp, forKey: K.favoritesStamp)
    }

    private func setRecents(_ list: [WStation]) {
        guard list != recents else { return }
        recents = list
        defaults.set(WJSON.data(list), forKey: K.recents)
    }

    private func setCountry(_ cc: String) {
        let c = cc.uppercased()
        guard c != countryCode else { return }
        countryCode = c
        defaults.set(c, forKey: K.country)
    }

    func isFavorite(_ s: WStation) -> Bool { favorites.contains(s) }

    /// Favoriet aan/uit: via de iPhone als die bereikbaar is (die bewaart en synchroniseert), anders hier en in iCloud
    func toggleFavorite(_ s: WStation) {
        var list = favorites
        if let i = list.firstIndex(of: s) { list.remove(at: i) } else { list.insert(s, at: 0) }
        let stamp = Date().timeIntervalSince1970
        setFavorites(list, stamp: stamp)
        if PhoneLink.shared.isReachable {
            PhoneLink.shared.send(["cmd": "favorite", "station": WJSON.data(s) ?? Data()])
        } else if let data = WJSON.data(list) {
            cloud.set(data, forKey: K.favorites)
            cloud.set(stamp, forKey: K.favoritesStamp)
        }
    }

    func noteWatchPlay(_ s: WStation) {
        var list = watchRecents.filter { $0 != s }
        list.insert(s, at: 0)
        watchRecents = Array(list.prefix(20))
        defaults.set(WJSON.data(watchRecents), forKey: K.watchRecents)
    }

    /// Recent: die van de iPhone, aangevuld met wat op de Watch speelde
    var allRecents: [WStation] {
        var seen = Set<String>()
        return (watchRecents + recents).filter { seen.insert($0.id).inserted }.prefix(25).map { $0 }
    }
}

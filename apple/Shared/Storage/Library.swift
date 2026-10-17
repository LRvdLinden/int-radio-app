import Foundation
import Combine
import SwiftUI

/// Sleutels van de instellingen (ook bruikbaar met @AppStorage)
enum SettingsKey {
    static let language = Localizer.key                     // "", "nl", "en"
    static let defaultSleep = "settings.defaultSleepMinutes" // Int: 0 = uit, 15, 30, 60
    static let autoplayLast = "settings.autoplayLast"        // Bool, standaard uit
}

/// Bibliotheek van de gebruiker: favorieten, recent, recente zoekopdrachten, gekozen land en lokale regio.
/// Opslag als JSON in UserDefaults, gespiegeld naar iCloud (NSUbiquitousKeyValueStore) zodat iPhone, iPad,
/// Mac en Apple TV dezelfde favorieten hebben. Volledige zenders worden bewaard, dus het werkt ook offline.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    static let maxRecents = 30
    static let maxSearches = 8
    static let maxPositions = 500
    static let maxRecentEpisodes = 40
    static let maxMapSearches = 5

    @Published private(set) var favorites: [Station] = []
    @Published private(set) var recents: [Station] = []
    @Published private(set) var recentSearches: [String] = []
    /// Recente kaartzoekopdrachten (landen en plaatsen, max 5, nieuwste eerst)
    @Published private(set) var recentMapSearches: [MapSearchItem] = []
    /// Gekozen land (ISO-code), nil = nog niet gekozen (landkeuze tonen)
    @Published private(set) var countryCode: String?
    /// Engelse landnaam (voor /json/states)
    @Published private(set) var countryName: String = ""
    @Published private(set) var localRegion: LocalRegion?
    /// Gevolgde podcasts (nieuwste eerst)
    @Published private(set) var followedPodcasts: [Podcast] = []
    /// Afspeelposities per aflevering (episodeId → positie)
    @Published private(set) var episodePositions: [String: EpisodePosition] = [:]
    /// Laatst beluisterde afleveringen (compact, voor "Verder luisteren")
    @Published private(set) var recentEpisodes: [Episode] = []

    private enum K {
        static let favorites = "lib.favorites"
        static let recents = "lib.recents"
        static let searches = "lib.searches"
        static let country = "lib.country"
        static let countryName = "lib.countryName"
        static let region = "lib.region"
        static let favoritesStamp = "lib.favorites.stamp"
        static let podcasts = "lib.podcasts"
        static let podcastsStamp = "lib.podcasts.stamp"
        static let positions = "lib.episodePositions"
        static let episodes = "lib.recentEpisodes"
        static let mapSearches = "lib.mapSearches"
        static let all = [favorites, recents, searches, country, countryName, region, podcasts, positions, episodes, mapSearches]
    }

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    private init() {
        loadLocal()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            Task { @MainActor in self?.mergeFromCloud(keys: keys) }
        }
        _ = cloud.synchronize()
        mergeFromCloud(keys: K.all)
    }

    // MARK: - Laden / bewaren

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func loadLocal() {
        favorites = decode([Station].self, defaults.data(forKey: K.favorites)) ?? []
        recents = decode([Station].self, defaults.data(forKey: K.recents)) ?? []
        recentSearches = defaults.stringArray(forKey: K.searches) ?? []
        recentMapSearches = decode([MapSearchItem].self, defaults.data(forKey: K.mapSearches)) ?? []
        countryCode = defaults.string(forKey: K.country)
        countryName = defaults.string(forKey: K.countryName) ?? ""
        localRegion = decode(LocalRegion.self, defaults.data(forKey: K.region))
        followedPodcasts = decode([Podcast].self, defaults.data(forKey: K.podcasts)) ?? []
        episodePositions = decode([String: EpisodePosition].self, defaults.data(forKey: K.positions)) ?? [:]
        recentEpisodes = decode([Episode].self, defaults.data(forKey: K.episodes)) ?? []
    }

    private func save(_ key: String, _ data: Data?) {
        defaults.set(data, forKey: key)
        if let data { cloud.set(data, forKey: key) } else { cloud.removeObject(forKey: key) }
    }

    private func saveFavorites() {
        save(K.favorites, try? JSONEncoder().encode(favorites))
        let stamp = Date().timeIntervalSince1970
        defaults.set(stamp, forKey: K.favoritesStamp)
        cloud.set(stamp, forKey: K.favoritesStamp)
        changed.send()
    }

    private func saveRecents() {
        save(K.recents, try? JSONEncoder().encode(recents))
        changed.send()
    }

    /// Voor CarPlay e.d.: vuurt bij elke wijziging van favorieten of recent
    let changed = PassthroughSubject<Void, Never>()

    /// Wijzigingen van een ander toestel samenvoegen
    private func mergeFromCloud(keys: [String]) {
        for key in keys {
            switch key {
            case K.favorites:
                guard let remote = decode([Station].self, cloud.data(forKey: K.favorites)) else { continue }
                let remoteStamp = cloud.double(forKey: K.favoritesStamp)
                let localStamp = defaults.double(forKey: K.favoritesStamp)
                if remoteStamp >= localStamp {
                    // de nieuwste lijst wint (dan kloppen ook verwijderingen en volgorde)
                    favorites = remote
                } else {
                    // lokaal is nieuwer: aanvullen met zenders die alleen in iCloud staan
                    let ids = Set(favorites.map(\.id))
                    favorites += remote.filter { !ids.contains($0.id) }
                }
                defaults.set(try? JSONEncoder().encode(favorites), forKey: K.favorites)
                defaults.set(max(remoteStamp, localStamp), forKey: K.favoritesStamp)
                changed.send()
            case K.recents:
                guard let remote = decode([Station].self, cloud.data(forKey: K.recents)) else { continue }
                // samenvoegen: lokaal eerst, dan de rest uit iCloud
                var merged = recents
                let ids = Set(recents.map(\.id))
                merged += remote.filter { !ids.contains($0.id) }
                recents = Array(merged.prefix(Self.maxRecents))
                defaults.set(try? JSONEncoder().encode(recents), forKey: K.recents)
                changed.send()
            case K.searches:
                if let remote = cloud.array(forKey: K.searches) as? [String] {
                    var merged = recentSearches
                    for s in remote where !merged.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) { merged.append(s) }
                    recentSearches = Array(merged.prefix(Self.maxSearches))
                    defaults.set(recentSearches, forKey: K.searches)
                }
            case K.mapSearches:
                guard let remote = decode([MapSearchItem].self, cloud.data(forKey: K.mapSearches)) else { continue }
                // samenvoegen: lokaal eerst, dan de rest uit iCloud
                var merged = recentMapSearches
                let ids = Set(recentMapSearches.map(\.id))
                merged += remote.filter { !ids.contains($0.id) }
                recentMapSearches = Array(merged.prefix(Self.maxMapSearches))
                defaults.set(try? JSONEncoder().encode(recentMapSearches), forKey: K.mapSearches)
            case K.country:
                // alleen overnemen als hier nog niets gekozen is (een ander toestel kan in een ander land staan)
                if countryCode == nil, let code = cloud.string(forKey: K.country), !code.isEmpty {
                    countryCode = code
                    countryName = cloud.string(forKey: K.countryName) ?? ""
                    defaults.set(code, forKey: K.country)
                    defaults.set(countryName, forKey: K.countryName)
                }
            case K.region:
                if localRegion == nil, let r = decode(LocalRegion.self, cloud.data(forKey: K.region)), r.countryCode == countryCode {
                    localRegion = r
                    defaults.set(cloud.data(forKey: K.region), forKey: K.region)
                }
            case K.podcasts:
                guard let remote = decode([Podcast].self, cloud.data(forKey: K.podcasts)) else { continue }
                let remoteStamp = cloud.double(forKey: K.podcastsStamp)
                let localStamp = defaults.double(forKey: K.podcastsStamp)
                if remoteStamp >= localStamp {
                    followedPodcasts = remote
                } else {
                    let ids = Set(followedPodcasts.map(\.id))
                    followedPodcasts += remote.filter { !ids.contains($0.id) }
                }
                defaults.set(try? JSONEncoder().encode(followedPodcasts), forKey: K.podcasts)
                defaults.set(max(remoteStamp, localStamp), forKey: K.podcastsStamp)
                changed.send()
            case K.positions:
                guard let remote = decode([String: EpisodePosition].self, cloud.data(forKey: K.positions)) else { continue }
                // per aflevering wint de nieuwste positie
                var merged = episodePositions
                for (id, p) in remote where (merged[id]?.updated ?? .distantPast) < p.updated { merged[id] = p }
                episodePositions = Self.capped(merged)
                defaults.set(try? JSONEncoder().encode(episodePositions), forKey: K.positions)
            case K.episodes:
                guard let remote = decode([Episode].self, cloud.data(forKey: K.episodes)) else { continue }
                var merged = recentEpisodes
                let ids = Set(recentEpisodes.map(\.id))
                merged += remote.filter { !ids.contains($0.id) }
                recentEpisodes = Array(merged.prefix(Self.maxRecentEpisodes))
                defaults.set(try? JSONEncoder().encode(recentEpisodes), forKey: K.episodes)
            default:
                break
            }
        }
    }

    // MARK: - Favorieten

    func isFavorite(_ s: Station) -> Bool { favorites.contains { $0.id == s.id } }

    func toggleFavorite(_ s: Station) {
        if isFavorite(s) { removeFavorite(s) } else { addFavorite(s) }
    }

    func addFavorite(_ s: Station) {
        guard !isFavorite(s) else { return }
        favorites.insert(s, at: 0)
        saveFavorites()
    }

    func removeFavorite(_ s: Station) {
        favorites.removeAll { $0.id == s.id }
        saveFavorites()
    }

    func moveFavorites(from: IndexSet, to: Int) {
        favorites.move(fromOffsets: from, toOffset: to)
        saveFavorites()
    }

    func clearFavorites() {
        favorites = []
        saveFavorites()
    }

    /// Opgeslagen favorieten bijwerken met verse gegevens (logo, stream-URL) uit Radio Browser
    func refreshFavorites() async {
        let ids = favorites.map(\.id)
        guard !ids.isEmpty, let fresh = try? await RadioBrowser.shared.byUUIDs(ids) else { return }
        let byID = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var updated = favorites
        var dirty = false
        for i in updated.indices {
            if let f = byID[updated[i].id], f.streamURL != nil,
               f.urlResolved != updated[i].urlResolved || f.favicon != updated[i].favicon || f.name != updated[i].name {
                updated[i] = f
                dirty = true
            }
        }
        if dirty {
            favorites = updated
            save(K.favorites, try? JSONEncoder().encode(favorites))
            changed.send()
        }
    }

    // MARK: - Recent

    func pushRecent(_ s: Station) {
        var list = recents.filter { $0.id != s.id }
        list.insert(s, at: 0)
        recents = Array(list.prefix(Self.maxRecents))
        saveRecents()
    }

    func removeRecent(_ s: Station) {
        recents.removeAll { $0.id == s.id }
        saveRecents()
    }

    func clearRecents() {
        recents = []
        saveRecents()
    }

    // MARK: - Recent gezocht

    func addSearch(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return }
        var list = recentSearches.filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        list.insert(t, at: 0)
        recentSearches = Array(list.prefix(Self.maxSearches))
        defaults.set(recentSearches, forKey: K.searches)
        cloud.set(recentSearches, forKey: K.searches)
    }

    func clearSearches() {
        recentSearches = []
        defaults.set(recentSearches, forKey: K.searches)
        cloud.set(recentSearches, forKey: K.searches)
    }

    // MARK: - Recent gezocht op de kaart

    func addMapSearch(_ item: MapSearchItem) {
        var list = recentMapSearches.filter { $0.id != item.id }
        list.insert(item, at: 0)
        recentMapSearches = Array(list.prefix(Self.maxMapSearches))
        save(K.mapSearches, try? JSONEncoder().encode(recentMapSearches))
    }

    func clearMapSearches() {
        recentMapSearches = []
        save(K.mapSearches, try? JSONEncoder().encode(recentMapSearches))
    }

    // MARK: - Land en regio

    func setCountry(_ c: Country) {
        let changedCountry = countryCode != c.code
        countryCode = c.code
        countryName = c.name
        defaults.set(c.code, forKey: K.country)
        defaults.set(c.name, forKey: K.countryName)
        cloud.set(c.code, forKey: K.country)
        cloud.set(c.name, forKey: K.countryName)
        if changedCountry, localRegion?.countryCode != c.code {
            localRegion = nil
            save(K.region, nil)
        }
        changed.send()
    }

    func setLocalRegion(_ name: String) {
        guard let code = countryCode else { return }
        let r = LocalRegion(countryCode: code, name: name)
        localRegion = r
        save(K.region, try? JSONEncoder().encode(r))
    }

    /// Lokale regio die bij het huidige land hoort
    var currentRegion: LocalRegion? {
        guard let r = localRegion, r.countryCode == countryCode else { return nil }
        return r
    }

    var country: Country? {
        guard let code = countryCode else { return nil }
        return Country(name: countryName, code: code, stationCount: 0)
    }
}

// MARK: - Podcasts

extension Library {
    // MARK: Volgen

    func isFollowing(_ p: Podcast) -> Bool { followedPodcasts.contains { $0.id == p.id } }
    func isFollowing(podcastId: String) -> Bool { followedPodcasts.contains { $0.id == podcastId } }

    func toggleFollow(_ p: Podcast) {
        if isFollowing(p) { unfollow(p) } else { follow(p) }
    }

    func follow(_ p: Podcast) {
        guard !isFollowing(p) else { return }
        followedPodcasts.insert(p, at: 0)
        saveFollowed()
    }

    func unfollow(_ p: Podcast) {
        followedPodcasts.removeAll { $0.id == p.id }
        saveFollowed()
    }

    /// Gegevens van een gevolgde podcast bijwerken (art, aantal afleveringen) na het laden van de pagina
    func updateFollowed(_ p: Podcast) {
        guard let i = followedPodcasts.firstIndex(where: { $0.id == p.id }) else { return }
        let fresh = p.merged(with: followedPodcasts[i])
        guard fresh.name != followedPodcasts[i].name || fresh.artworkURL != followedPodcasts[i].artworkURL
                || fresh.trackCount != followedPodcasts[i].trackCount || fresh.feedURL != followedPodcasts[i].feedURL else { return }
        followedPodcasts[i] = fresh
        saveFollowed()
    }

    private func saveFollowed() {
        save(K.podcasts, try? JSONEncoder().encode(followedPodcasts))
        let stamp = Date().timeIntervalSince1970
        defaults.set(stamp, forKey: K.podcastsStamp)
        cloud.set(stamp, forKey: K.podcastsStamp)
        changed.send()
    }

    // MARK: Afspeelposities

    func position(for episodeId: String) -> EpisodePosition? { episodePositions[episodeId] }

    /// Positie bewaren; `finished` wordt ook gezet bij ≥ 95%
    /// `syncCloud == false` (tijdens het afspelen, elke 10 s) = alleen lokaal; bij pauze/stop ook naar iCloud.
    func savePosition(_ e: Episode, seconds: Double, duration: Double, finished: Bool = false, syncCloud: Bool = true) {
        guard seconds.isFinite, duration.isFinite else { return }
        let dur = duration > 0 ? duration : e.duration
        let done = finished || (dur > 0 && seconds / dur >= 0.95)
        episodePositions[e.id] = EpisodePosition(seconds: done ? 0 : max(0, seconds), duration: dur,
                                                 finished: done, updated: Date())
        episodePositions = Self.capped(episodePositions)
        let data = try? JSONEncoder().encode(episodePositions)
        if syncCloud { save(K.positions, data) } else { defaults.set(data, forKey: K.positions) }
    }

    func markFinished(_ e: Episode, _ finished: Bool = true) {
        let dur = episodePositions[e.id]?.duration ?? e.duration
        episodePositions[e.id] = EpisodePosition(seconds: 0, duration: dur, finished: finished, updated: Date())
        save(K.positions, try? JSONEncoder().encode(episodePositions))
    }

    /// Max. 500 posities: de oudste eruit
    fileprivate static func capped(_ dict: [String: EpisodePosition]) -> [String: EpisodePosition] {
        guard dict.count > maxPositions else { return dict }
        let keep = dict.sorted { $0.value.updated > $1.value.updated }.prefix(maxPositions)
        return Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    // MARK: Laatst beluisterd

    func pushRecentEpisode(_ e: Episode) {
        var list = recentEpisodes.filter { $0.id != e.id }
        list.insert(e.compact, at: 0)
        recentEpisodes = Array(list.prefix(Self.maxRecentEpisodes))
        save(K.episodes, try? JSONEncoder().encode(recentEpisodes))
        changed.send()
    }

    func removeRecentEpisode(_ e: Episode) {
        recentEpisodes.removeAll { $0.id == e.id }
        save(K.episodes, try? JSONEncoder().encode(recentEpisodes))
    }

    /// Half beluisterde afleveringen (meest recent eerst)
    var continueListening: [Episode] {
        recentEpisodes
            .compactMap { e -> (Episode, Date)? in
                guard let p = episodePositions[e.id], !p.finished, p.seconds >= 15 else { return nil }
                return (e, p.updated)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// Laatste aflevering van elke gevolgde podcast, nieuwste eerst
    func newEpisodes(country: String) async -> [Episode] {
        let podcasts = Array(followedPodcasts.prefix(30))
        guard !podcasts.isEmpty else { return [] }
        let api = PodcastAPI.shared
        let found: [Episode] = await withTaskGroup(of: Episode?.self) { group in
            for p in podcasts {
                let id = p.id
                group.addTask { await api.latestEpisode(id, country: country) }
            }
            var out: [Episode] = []
            for await e in group { if let e { out.append(e) } }
            return out
        }
        return found.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

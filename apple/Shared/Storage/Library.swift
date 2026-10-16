import Foundation
import Combine
import SwiftUI

/// Sleutels van de instellingen (ook bruikbaar met @AppStorage)
enum SettingsKey {
    static let introMusic = "settings.introMusic"           // Bool, standaard aan
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

    @Published private(set) var favorites: [Station] = []
    @Published private(set) var recents: [Station] = []
    @Published private(set) var recentSearches: [String] = []
    /// Gekozen land (ISO-code), nil = nog niet gekozen (landkeuze tonen)
    @Published private(set) var countryCode: String?
    /// Engelse landnaam (voor /json/states)
    @Published private(set) var countryName: String = ""
    @Published private(set) var localRegion: LocalRegion?

    private enum K {
        static let favorites = "lib.favorites"
        static let recents = "lib.recents"
        static let searches = "lib.searches"
        static let country = "lib.country"
        static let countryName = "lib.countryName"
        static let region = "lib.region"
        static let favoritesStamp = "lib.favorites.stamp"
        static let all = [favorites, recents, searches, country, countryName, region]
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
        countryCode = defaults.string(forKey: K.country)
        countryName = defaults.string(forKey: K.countryName) ?? ""
        localRegion = decode(LocalRegion.self, defaults.data(forKey: K.region))
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

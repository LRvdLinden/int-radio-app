import Foundation
import Combine

/// Build 9: instellingen gaan via iCloud mee tussen iPhone, iPad, Mac en Apple TV (zelfde Apple ID),
/// net als favorieten en podcasts. Het gaat om de taal, de standaard-slaaptimer en automatisch verder spelen.
/// (De intromuziek is geen instelling meer: die speelt altijd.)
///
/// Werkwijze: de instellingen blijven gewoon in UserDefaults staan (dus @AppStorage blijft werken).
/// - lokaal gewijzigd → naar iCloud (NSUbiquitousKeyValueStore);
/// - in iCloud gewijzigd door een ander apparaat → lokaal overnemen (taal direct toepassen);
/// - bij het starten wint wat in iCloud staat; staat er nog niets, dan gaan de lokale waarden erheen.
@MainActor
final class SettingsSync {
    static let shared = SettingsSync()

    private let keys = [SettingsKey.language, SettingsKey.defaultSleep, SettingsKey.autoplayLast]
    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private var applyingRemote = false
    private var started = false
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        _ = cloud.synchronize()
        // bij het starten: iCloud wint; ontbreekt een sleutel daar, dan de lokale waarde erheen
        for key in keys {
            if let remote = cloud.object(forKey: key) {
                applyRemote(key, remote)
            } else if let local = defaults.object(forKey: key) {
                cloud.set(local, forKey: key)
            }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            Task { @MainActor in self?.cloudChanged(changed) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.localChanged() }
        })
    }

    private func cloudChanged(_ changed: [String]) {
        for key in changed where keys.contains(key) {
            if let remote = cloud.object(forKey: key) { applyRemote(key, remote) }
        }
    }

    private func localChanged() {
        guard !applyingRemote else { return }
        for key in keys {
            let local = defaults.object(forKey: key)
            if !same(local, cloud.object(forKey: key)) {
                if let local { cloud.set(local, forKey: key) } else { cloud.removeObject(forKey: key) }
            }
        }
    }

    private func applyRemote(_ key: String, _ value: Any) {
        guard !same(defaults.object(forKey: key), value) else { return }
        applyingRemote = true
        if key == SettingsKey.language, let lang = value as? String {
            // via de Localizer, zodat de app meteen van taal wisselt (die bewaart het zelf in UserDefaults)
            Localizer.shared.override = lang
        } else {
            defaults.set(value, forKey: key)
        }
        applyingRemote = false
    }

    private func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x as String, y as String): return x == y
        case let (x as NSNumber, y as NSNumber): return x == y
        default: return false
        }
    }
}

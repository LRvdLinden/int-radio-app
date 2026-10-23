#if os(iOS) && canImport(ActivityKit)
import Foundation
import Combine
import ActivityKit

/// Live Activity "Nu speelt" (alleen iPhone): start zodra een zender gaat spelen, werkt bij bij een nieuw nummer
/// of afspelen/pauze, en stopt bij stoppen. Uit te zetten in Instellingen ("Live Activity bij afspelen",
/// per apparaat). De weergave staat in de extensie (Widgets/NowPlayingLiveActivity.swift).
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var bag = Set<AnyCancellable>()
    private var started = false
    private var activity: Activity<NowPlayingAttributes>?
    private var lastContent: NowPlayingAttributes.ContentState?
    private var startedAt = Date()

    private init() {}

    /// Staat de instelling aan? (standaard aan)
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.liveActivity) as? Bool ?? true
    }

    func start() {
        guard !started else { return }
        started = true
        endStaleActivities()
        let p = RadioPlayer.shared
        Publishers.CombineLatest4(p.$station, p.$state, p.$nowPlaying, p.$episode)
            .map { _ in () }
            .merge(with: p.$artworkURL.map { _ in () })
            // @Published meldt vóór de wijziging: even wachten, dan staat alles goed
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.sync() } }
            .store(in: &bag)
    }

    /// Live Activity in lijn brengen met de speler (ook na het wijzigen van de instelling)
    func sync() {
        let p = RadioPlayer.shared
        guard Self.isEnabled, p.episode == nil, let s = p.station, p.state != .idle else {
            endAll()
            return
        }
        let parts = ArtworkLookup.split(p.nowPlaying)
        let isPlaying = p.isPlaying
        // albumhoes alleen als hij al in de App Group staat (WidgetSync haalt hem op en roept daarna sync() aan)
        let cover: String? = {
            guard isPlaying, !p.nowPlaying.isEmpty, let u = p.artworkURL else { return nil }
            let name = WidgetBridge.coverFileName(for: u.absoluteString)
            return WidgetBridge.hasFile(name) ? name : nil
        }()

        if let a = activity, a.attributes.stationID == s.id, a.activityState == .active {
            let content = NowPlayingAttributes.ContentState(title: parts?.title ?? p.nowPlaying, artist: parts?.artist ?? "",
                                                            isPlaying: isPlaying, startedAt: startedAt, coverFile: cover)
            guard content != lastContent else { return }
            lastContent = content
            Task { await a.update(ActivityContent(state: content, staleDate: nil)) }
            return
        }

        // andere zender (of nog geen activity): de oude weg, een nieuwe alleen als er echt iets speelt
        endAll()
        guard isPlaying, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        startedAt = Date()
        let content = NowPlayingAttributes.ContentState(title: parts?.title ?? p.nowPlaying, artist: parts?.artist ?? "",
                                                        isPlaying: isPlaying, startedAt: startedAt, coverFile: cover)
        let attributes = NowPlayingAttributes(stationID: s.id, stationName: s.displayName, country: s.country,
                                              logoFile: WidgetBridge.logoFileName(for: s.id))
        do {
            activity = try Activity.request(attributes: attributes,
                                            content: ActivityContent(state: content, staleDate: nil),
                                            pushType: nil)
            lastContent = content
        } catch {
            activity = nil
            lastContent = nil
        }
    }

    /// Een logo is net in de App Group gezet: de activity opnieuw laten tekenen
    func logosChanged(_ stationIDs: [String]) {
        guard let a = activity, stationIDs.contains(a.attributes.stationID), let content = lastContent else { return }
        Task { await a.update(ActivityContent(state: content, staleDate: nil)) }
    }

    private func endAll() {
        let current = activity
        activity = nil
        lastContent = nil
        for a in Activity<NowPlayingAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        if let current, !Activity<NowPlayingAttributes>.activities.contains(where: { $0.id == current.id }) {
            Task { await current.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Bij het starten: activities van een vorige sessie (app gestopt/gecrasht) opruimen
    private func endStaleActivities() {
        for a in Activity<NowPlayingAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
#endif

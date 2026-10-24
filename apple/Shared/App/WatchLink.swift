#if os(iOS) && canImport(WatchConnectivity)
import Foundation
import Combine
import WatchConnectivity

/// Verbinding met de Apple Watch-app (Watch/PhoneLink.swift). De iPhone stuurt via de applicationContext wat er
/// speelt (zender, stream-titel, afspelen, albumhoes) plus favorieten, recent en het gekozen land; de Watch stuurt
/// opdrachten: play (zender + lijst), toggle, stop, next, prev, favorite, state. Elk antwoord is de nieuwe stand.
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    private var bag = Set<AnyCancellable>()
    private var started = false
    private var lastContext: [String: Any] = [:]

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func start() {
        guard !started, let s = session else { return }
        started = true
        s.delegate = self
        s.activate()
        let p = RadioPlayer.shared
        Publishers.CombineLatest4(p.$station, p.$state, p.$nowPlaying, p.$artworkURL)
            .map { _ in () }
            .merge(with: Library.shared.changed)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.pushContext() } }
            .store(in: &bag)
    }

    /// Stand voor de Watch (ook als antwoord op een opdracht)
    private func state(full: Bool) -> [String: Any] {
        let p = RadioPlayer.shared
        var ctx: [String: Any] = ["playing": p.episode == nil && p.isPlaying]
        if p.episode == nil, let s = p.station, let data = try? JSONEncoder().encode(s) {
            ctx["station"] = data
            ctx["title"] = p.nowPlaying
            if let art = p.artworkURL?.absoluteString { ctx["art"] = art }
        }
        if full {
            let lib = Library.shared
            if let f = try? JSONEncoder().encode(Array(lib.favorites.prefix(50))) { ctx["favorites"] = f }
            if let r = try? JSONEncoder().encode(Array(lib.recents.prefix(20))) { ctx["recents"] = r }
            ctx["country"] = lib.countryCode ?? ""
        }
        return ctx
    }

    private func pushContext() {
        guard let s = session, s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let ctx = state(full: true)
        // alleen bij een echte wijziging (de applicationContext is beperkt in grootte en frequentie)
        guard !NSDictionary(dictionary: ctx).isEqual(to: lastContext) else { return }
        lastContext = ctx
        try? s.updateApplicationContext(ctx)
    }

    fileprivate func handle(_ msg: [String: Any]) async -> [String: Any] {
        let p = RadioPlayer.shared
        let lib = Library.shared
        switch msg["cmd"] as? String ?? "" {
        case "play":
            if let d = msg["station"] as? Data, let s = try? JSONDecoder().decode(Station.self, from: d) {
                let queue = (msg["queue"] as? Data).flatMap { try? JSONDecoder().decode([Station].self, from: $0) }
                p.play(s, queue: queue ?? [s])
            }
        case "toggle":
            if p.hasMedia { p.toggle() } else { _ = p.playLastStation() }
        case "stop": p.stop()
        case "next": p.next()
        case "prev": p.previous()
        case "favorite":
            if let d = msg["station"] as? Data, let s = try? JSONDecoder().decode(Station.self, from: d) {
                lib.toggleFavorite(s)
            }
        default: break
        }
        // even wachten, zodat de speler de nieuwe stand heeft
        try? await Task.sleep(nanoseconds: 300_000_000)
        return state(full: msg["cmd"] as? String == "state" || msg["cmd"] as? String == "favorite")
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in WatchLink.shared.pushContext() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()   // andere Watch gekoppeld
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in WatchLink.shared.pushContext() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let box = ReplyBox(replyHandler)
        Task { @MainActor in
            let reply = await WatchLink.shared.handle(message)
            box.reply(reply)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in _ = await WatchLink.shared.handle(message) }
    }
}

/// Het antwoord van WatchConnectivity over de grens van de main actor brengen
private final class ReplyBox: @unchecked Sendable {
    let reply: ([String: Any]) -> Void
    init(_ reply: @escaping ([String: Any]) -> Void) { self.reply = reply }
}
#endif

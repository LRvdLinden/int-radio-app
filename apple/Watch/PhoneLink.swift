import Foundation
import WatchConnectivity

/// Wat er op de iPhone speelt (uit de applicationContext of een antwoord van de iPhone-app)
struct PhoneNowPlaying: Equatable {
    var station: WStation
    var streamTitle: String
    var isPlaying: Bool
    var artwork: URL?
}

/// Verbinding met de iPhone-app (WatchConnectivity). Opdrachten: play (zender), toggle, stop, next, prev,
/// favorite, state. De iPhone stuurt via de applicationContext wat er speelt plus favorieten, recent en land
/// (iPhone-kant: Shared/App/WatchLink.swift).
@MainActor
final class PhoneLink: NSObject, ObservableObject {
    static let shared = PhoneLink()

    @Published private(set) var nowPlaying: PhoneNowPlaying?
    @Published private(set) var isReachable = false

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func start() {
        guard let s = session else { return }
        s.delegate = self
        s.activate()
    }

    /// Opdracht naar de iPhone; het antwoord (de nieuwe stand) wordt meteen verwerkt
    func send(_ message: [String: Any]) {
        guard let s = session, s.activationState == .activated else { return }
        s.sendMessage(message, replyHandler: { reply in
            Task { @MainActor in PhoneLink.shared.apply(reply) }
        }, errorHandler: { _ in })
    }

    func play(_ station: WStation, queue: [WStation]) {
        var msg: [String: Any] = ["cmd": "play", "station": WJSON.data(station) ?? Data()]
        if let q = WJSON.data(Array(queue.prefix(40))) { msg["queue"] = q }
        // meteen tonen; de iPhone bevestigt met de echte stand
        nowPlaying = PhoneNowPlaying(station: station, streamTitle: "", isPlaying: true, artwork: nil)
        send(msg)
    }

    func command(_ cmd: String) {
        if cmd == "toggle", var np = nowPlaying { np.isPlaying.toggle(); nowPlaying = np }
        if cmd == "stop", var np = nowPlaying { np.isPlaying = false; nowPlaying = np }
        send(["cmd": cmd])
    }

    func refresh() { send(["cmd": "state"]) }

    fileprivate func apply(_ ctx: [String: Any]) {
        WatchStore.shared.apply(phoneContext: ctx)
        guard ctx["playing"] != nil || ctx["station"] != nil else { return }
        if let s = WJSON.station(ctx["station"] as? Data) {
            nowPlaying = PhoneNowPlaying(station: s,
                                         streamTitle: ctx["title"] as? String ?? "",
                                         isPlaying: ctx["playing"] as? Bool ?? false,
                                         artwork: (ctx["art"] as? String).flatMap { URL(string: $0) })
        } else {
            nowPlaying = nil
        }
    }

    fileprivate func updateReachability() {
        isReachable = session?.isReachable ?? false
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let ctx = session.receivedApplicationContext
        Task { @MainActor in
            PhoneLink.shared.updateReachability()
            if !ctx.isEmpty { PhoneLink.shared.apply(ctx) }
            PhoneLink.shared.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in PhoneLink.shared.apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in PhoneLink.shared.apply(message) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            PhoneLink.shared.updateReachability()
            if session.isReachable { PhoneLink.shared.refresh() }
        }
    }
}

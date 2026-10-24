import Foundation
import AVFoundation
import MediaPlayer
import Combine

/// Afspelen op de Watch zelf. watchOS speelt lange audio alleen via Bluetooth (AirPods, koptelefoon, speaker):
/// de sessie met `.longFormAudio` toont zo nodig zelf de keuze van het audioapparaat. Nu speelt op de Watch
/// (en op de iPhone als die meekijkt) via MPNowPlayingInfoCenter, met de stream-titel als "Titel - Artiest".
@MainActor
final class WatchPlayer: NSObject, ObservableObject {
    static let shared = WatchPlayer()

    enum State: Equatable { case idle, loading, playing, paused, failed }

    @Published private(set) var station: WStation?
    @Published private(set) var state: State = .idle
    @Published private(set) var streamTitle = ""
    @Published var volume: Double = 0.8 {
        didSet { player.volume = Float(min(max(volume, 0), 1)) }
    }

    private let player = AVPlayer()
    private var queue: [WStation] = []
    private var usedFallback = false
    private var bag = Set<AnyCancellable>()
    private var itemBag = Set<AnyCancellable>()
    private var watchdog: Task<Void, Never>?

    var hasMedia: Bool { station != nil && state != .idle }
    var isPlaying: Bool { state == .playing || state == .loading }

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = Float(volume)
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in Task { @MainActor in self?.timeControlChanged(status) } }
            .store(in: &bag)
        setupRemote()
    }

    func play(_ s: WStation, queue list: [WStation]) {
        queue = list.contains(s) ? list : [s] + list
        if station == s, state == .paused || state == .failed { resume(); return }
        if station == s, isPlaying { return }
        station = s
        streamTitle = ""
        usedFallback = false
        state = .loading
        updateNowPlaying()
        WatchStore.shared.noteWatchPlay(s)
        Task { await WatchRadioBrowser.shared.click(s.id) }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        } catch {
            state = .failed
            return
        }
        activateAndStart(s)
    }

    /// Audiosessie aanzetten (kiest zo nodig een Bluetooth-apparaat) en dan de stream starten
    private func activateAndStart(_ s: WStation) {
        AVAudioSession.sharedInstance().activate(options: []) { ok, _ in
            Task { @MainActor in
                let p = WatchPlayer.shared
                guard p.station == s else { return }
                if ok { p.start(url: s.streamURL) } else { p.state = .failed; p.updateNowPlaying() }
            }
        }
    }

    private func start(url: URL?) {
        guard let url else { state = .failed; return }
        itemBag.removeAll()
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": Brand.userAgent]])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .failed { Task { @MainActor in self?.handleFailure() } }
            }
            .store(in: &itemBag)
        state = .loading
        player.replaceCurrentItem(with: item)
        player.play()
        armWatchdog()
    }

    private func handleFailure() {
        guard let s = station, state != .paused else { return }
        if !usedFallback, let fb = s.fallbackURL {
            usedFallback = true
            start(url: fb)
            return
        }
        watchdog?.cancel()
        player.pause()
        state = .failed
        updateNowPlaying()
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self, self.state == .loading else { return }
            self.handleFailure()
        }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        guard station != nil, state != .paused, state != .failed, state != .idle else { return }
        switch status {
        case .playing:
            state = .playing
            watchdog?.cancel()
            updateNowPlaying()
        case .waitingToPlayAtSpecifiedRate:
            if state != .loading { state = .loading; armWatchdog() }
        default:
            break
        }
    }

    func pause() {
        guard hasMedia else { return }
        player.pause()
        watchdog?.cancel()
        state = .paused
        updateNowPlaying()
    }

    /// Live radio: opnieuw verbinden (anders loopt de buffer achter)
    func resume() {
        guard let s = station else { return }
        usedFallback = false
        state = .loading
        updateNowPlaying()
        activateAndStart(s)
    }

    func toggle() { isPlaying ? pause() : resume() }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        watchdog?.cancel()
        station = nil
        streamTitle = ""
        state = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func step(_ delta: Int) {
        guard let s = station, queue.count > 1, let i = queue.firstIndex(of: s) else { return }
        let next = queue[(i + delta + queue.count) % queue.count]
        play(next, queue: queue)
    }

    // MARK: Nu speelt

    private func updateNowPlaying() {
        guard let s = station else { return }
        let line = WTrack.line(streamTitle)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.displayName,
            MPMediaItemPropertyArtist: line.isEmpty ? (s.genreLine.isEmpty ? Brand.name : s.genreLine) : line,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in Task { @MainActor in WatchPlayer.shared.resume() }; return .success }
        c.pauseCommand.addTarget { _ in Task { @MainActor in WatchPlayer.shared.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in WatchPlayer.shared.toggle() }; return .success }
        c.nextTrackCommand.addTarget { _ in Task { @MainActor in WatchPlayer.shared.step(1) }; return .success }
        c.previousTrackCommand.addTarget { _ in Task { @MainActor in WatchPlayer.shared.step(-1) }; return .success }
    }

    fileprivate func handleStreamTitle(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = (t == station?.name || t == "-") ? "" : t
        guard cleaned != streamTitle else { return }
        streamTitle = cleaned
        updateNowPlaying()
    }
}

extension WatchPlayer: AVPlayerItemMetadataOutputPushDelegate {
    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        var title: String?
        var artist: String?
        for group in groups {
            for item in group.items {
                guard let value = item.stringValue, !value.isEmpty else { continue }
                if item.identifier == .icyMetadataStreamTitle {
                    title = value
                } else if item.commonKey == .commonKeyTitle, title == nil {
                    title = value
                } else if item.commonKey == .commonKeyArtist {
                    artist = value
                }
            }
        }
        guard var t = title else { return }
        if let artist, !t.contains(" - ") { t = artist + " - " + t }
        let final = t
        Task { @MainActor in WatchPlayer.shared.handleStreamTitle(final) }
    }
}

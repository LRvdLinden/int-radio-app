import Foundation
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI

/// Afspeeltoestand
enum PlaybackState: Equatable {
    case idle, loading, playing, paused, failed
}

/// De radiospeler (één voor de hele app, ook CarPlay en het vergrendelscherm).
/// AVPlayer speelt HLS en Icecast/Shoutcast (mp3/aac); ICY-titels komen via AVPlayerItemMetadataOutput.
@MainActor
final class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()

    @Published private(set) var station: Station?
    @Published private(set) var state: PlaybackState = .idle
    /// Lijst waaruit gestart is (voor vorige/volgende zender)
    @Published private(set) var queue: [Station] = []
    /// "Artiest - Titel" uit de stream (leeg als de zender niets meldt)
    @Published private(set) var nowPlaying: String = ""
    /// Hoes van het nummer (iTunes), anders nil → zenderlogo
    @Published private(set) var artworkURL: URL?
    /// Einde van de slaaptimer
    @Published private(set) var sleepEnd: Date?
    @Published var volume: Float = 1 {
        didSet { player.volume = volume }
    }

    private let player = AVPlayer()
    private var bag = Set<AnyCancellable>()
    private var itemBag = Set<AnyCancellable>()
    private var metadataReceiver: MetadataReceiver?
    private var usedFallback = false
    private var watchdog: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var nowPlayingImage: PlatformImage?
    private var observers: [NSObjectProtocol] = []

    var isPlaying: Bool { state == .playing || state == .loading }
    var hasNext: Bool { queue.count > 1 }

    /// Tekst onder de zendernaam: nu-speelt-titel, anders genres
    var subtitle: String {
        if !nowPlaying.isEmpty { return nowPlaying }
        return station?.genreLine ?? ""
    }

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        #if os(iOS) || os(tvOS)
        player.allowsExternalPlayback = true
        #endif
        observePlayer()
        configureSession()
        configureRemoteCommands()
    }

    // MARK: - Afspelen

    /// Speel een zender; `queue` = de lijst waaruit gekozen is (voor vorige/volgende).
    func play(_ s: Station, queue newQueue: [Station]? = nil) {
        if let newQueue, !newQueue.isEmpty {
            queue = newQueue.contains(s) ? newQueue : [s] + newQueue
        } else if !queue.contains(s) {
            queue = [s]
        }
        if station?.id == s.id, state == .playing { return }
        if station?.id == s.id, state == .paused {
            resume()
            return
        }
        station = s
        nowPlaying = ""
        artworkURL = nil
        nowPlayingImage = nil
        usedFallback = false
        start(url: s.streamURL)
        Library.shared.pushRecent(s)
        RadioBrowser.shared.click(s.id)
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: "player.last")
        loadStationImage()
        applyDefaultSleepTimerIfNeeded()
    }

    private func start(url: URL?) {
        guard let url else {
            state = .failed
            return
        }
        activateSession()
        itemBag.removeAll()
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": Brand.userAgent]])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        let receiver = MetadataReceiver { [weak self] title in
            Task { @MainActor in self?.handleStreamTitle(title) }
        }
        output.setDelegate(receiver, queue: DispatchQueue.main)
        item.add(output)
        metadataReceiver = receiver

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor in self?.itemStatusChanged(status) }
            }
            .store(in: &itemBag)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.handleFailure() } }
            .store(in: &itemBag)
        NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.armWatchdog() } }
            .store(in: &itemBag)

        state = .loading
        player.replaceCurrentItem(with: item)
        player.play()
        armWatchdog()
        updateNowPlaying()
    }

    func pause() {
        guard station != nil else { return }
        player.pause()
        state = .paused
        watchdog?.cancel()
        updateNowPlaying()
    }

    func resume() {
        guard let s = station else { return }
        // live radio: na een pauze opnieuw verbinden (anders loopt de stream achter of is hij verlopen)
        usedFallback = false
        start(url: s.streamURL)
    }

    func toggle() {
        switch state {
        case .playing, .loading: pause()
        case .paused, .failed, .idle: resume()
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        watchdog?.cancel()
        state = .idle
        station = nil
        nowPlaying = ""
        artworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    func retry() {
        guard let s = station else { return }
        usedFallback = false
        start(url: s.streamURL)
    }

    func next() { step(1) }
    func previous() { step(-1) }

    private func step(_ delta: Int) {
        guard let s = station, queue.count > 1 else { return }
        let i = queue.firstIndex(of: s) ?? 0
        let n = (i + delta + queue.count) % queue.count
        play(queue[n], queue: queue)
    }

    func toggleFavoriteCurrent() {
        guard let s = station else { return }
        Library.shared.toggleFavorite(s)
        updateRemoteFavorite()
    }

    /// Laatste zender opnieuw laden (Instellingen → automatisch verder spelen)
    func resumeLastIfWanted() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.autoplayLast), station == nil,
              let data = UserDefaults.standard.data(forKey: "player.last"),
              let s = try? JSONDecoder().decode(Station.self, from: data) else { return }
        play(s, queue: Library.shared.favorites.contains(s) ? Library.shared.favorites : [s])
    }

    // MARK: - Status

    private func observePlayer() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor in self?.timeControlChanged(status) }
            }
            .store(in: &bag)
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        guard station != nil, state != .paused, state != .failed else { return }
        switch status {
        case .playing:
            state = .playing
            watchdog?.cancel()
            updateNowPlaying()
        case .waitingToPlayAtSpecifiedRate:
            if state != .loading { state = .loading }
            armWatchdog()
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status) {
        if status == .failed { handleFailure() }
    }

    /// Fout: één keer opnieuw met `url` als `url_resolved` faalde, anders "niet bereikbaar"
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

    /// Bewaker: hangt het laden of bufferen te lang, dan als fout behandelen
    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.state == .loading else { return }
                self.handleFailure()
            }
        }
    }

    // MARK: - Nu speelt

    private func handleStreamTitle(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // sommige zenders sturen hun eigen naam of lege titels: dan niets tonen
        let cleaned = (t == station?.name || t == "-" ) ? "" : t
        guard cleaned != nowPlaying else { return }
        nowPlaying = cleaned
        artworkTask?.cancel()
        artworkURL = nil
        updateNowPlaying()
        guard !cleaned.isEmpty else {
            loadStationImage()
            return
        }
        artworkTask = Task { [weak self] in
            let url = await ArtworkLookup.shared.artwork(for: cleaned)
            guard !Task.isCancelled else { return }
            var img: PlatformImage?
            if let url { img = await ImageLoader.shared.load(url) }
            await MainActor.run {
                guard let self, self.nowPlaying == cleaned else { return }
                self.artworkURL = url
                if let img { self.nowPlayingImage = img; self.updateNowPlaying() } else { self.loadStationImage() }
            }
        }
    }

    private func loadStationImage() {
        guard let s = station, let url = s.logoURL else { return }
        Task { [weak self] in
            let img = await ImageLoader.shared.load(url)
            await MainActor.run {
                guard let self, self.station?.id == s.id, self.artworkURL == nil, let img else { return }
                self.nowPlayingImage = img
                self.updateNowPlaying()
            }
        }
    }

    // MARK: - Slaaptimer

    /// `minutes == 0` = uit
    func setSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        guard minutes > 0 else {
            sleepEnd = nil
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepEnd = end
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.sleepEnd = nil
                self.pause()
            }
        }
    }

    private func applyDefaultSleepTimerIfNeeded() {
        let m = UserDefaults.standard.integer(forKey: SettingsKey.defaultSleep)
        if m > 0, sleepEnd == nil { setSleepTimer(minutes: m) }
    }

    // MARK: - Audiosessie (iPhone, iPad, Apple TV)

    private func configureSession() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let optRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optRaw) }
        })
        #endif
        #if os(iOS)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            Task { @MainActor in
                // koptelefoon eruit → pauze
                if AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable { self?.pause() }
            }
        })
        #endif
    }

    private func activateSession() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        // de intro-tune zet .mixWithOthers; voor de radio weer gewoon .playback
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try? session.setActive(true)
        #endif
    }

    #if os(iOS) || os(tvOS)
    private func handleInterruption(typeRaw: UInt, optionsRaw: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            if state == .playing || state == .loading {
                player.pause()
                state = .paused
                wasInterrupted = true
                updateNowPlaying()
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if wasInterrupted, options.contains(.shouldResume) { resume() }
            wasInterrupted = false
        @unknown default:
            break
        }
    }
    #endif
    private var wasInterrupted = false

    // MARK: - Vergrendelscherm / Bedieningspaneel / CarPlay

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        c.pauseCommand.isEnabled = true
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.isEnabled = true
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        c.stopCommand.isEnabled = true
        c.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.nextTrackCommand.isEnabled = true
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        c.previousTrackCommand.isEnabled = true
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        // live radio: niet spoelen
        c.changePlaybackPositionCommand.isEnabled = false
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
        #if os(iOS)
        // favoriet (o.a. de hartjesknop in CarPlay en op het vergrendelscherm)
        c.likeCommand.isEnabled = true
        c.likeCommand.localizedTitle = L("player.favorite")
        c.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggleFavoriteCurrent() }
            return .success
        }
        #endif
    }

    private func updateRemoteFavorite() {
        #if os(iOS)
        if let s = station { MPRemoteCommandCenter.shared().likeCommand.isActive = Library.shared.isFavorite(s) }
        #endif
    }

    private func updateNowPlaying() {
        guard let s = station else { return }
        let parts = ArtworkLookup.split(nowPlaying)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: parts?.title ?? s.displayName,
            MPMediaItemPropertyArtist: parts?.artist ?? (s.genreLine.isEmpty ? Brand.name : s.genreLine),
            MPMediaItemPropertyAlbumTitle: s.displayName,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        if let img = nowPlayingImage {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(img)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = state == .playing ? .playing : (state == .paused ? .paused : .interrupted)
        #endif
        let c = MPRemoteCommandCenter.shared()
        c.nextTrackCommand.isEnabled = queue.count > 1
        c.previousTrackCommand.isEnabled = queue.count > 1
        updateRemoteFavorite()
    }

    /// Buiten de main actor, zodat de handler (die het systeem op een willekeurige thread aanroept) niet aan de
    /// hoofdthread vastzit.
    nonisolated private static func makeArtwork(_ image: PlatformImage) -> MPMediaItemArtwork {
        let size = image.size
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }
}

/// Ontvangt de ICY-/ID3-metadata van de stream en geeft de titel ("Artiest - Titel") door.
final class MetadataReceiver: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let onTitle: (String) -> Void

    init(onTitle: @escaping (String) -> Void) {
        self.onTitle = onTitle
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
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
        onTitle(t)
    }
}

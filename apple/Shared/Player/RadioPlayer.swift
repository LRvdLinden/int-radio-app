import Foundation
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI

/// Afspeeltoestand
enum PlaybackState: Equatable {
    case idle, loading, playing, paused, failed
}

/// Tijd van de aflevering die speelt. Los object, zodat alleen de tijdbalk en de voortgangslijn elke halve
/// seconde opnieuw tekenen (en niet elk scherm dat de speler volgt). Wordt alleen op de hoofdthread gewijzigd.
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    /// 0…1
    var fraction: Double { duration > 0 ? min(1, max(0, currentTime / duration)) : 0 }
    var remaining: Double { max(0, duration - currentTime) }
}

/// De speler (één voor de hele app, ook CarPlay en het vergrendelscherm).
/// - Radio: AVPlayer speelt HLS en Icecast/Shoutcast (mp3/aac); ICY-titels komen via AVPlayerItemMetadataOutput.
/// - Podcast (SPEC §8): dezelfde AVPlayer in "aflevering"-modus met spoelen, ±15/30 s, snelheid, hervatten
///   op de bewaarde positie en vorige/volgende aflevering in de lijst waaruit gestart is.
@MainActor
final class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()

    /// Snelheden voor afleveringen
    nonisolated static let rates: [Float] = [0.8, 1, 1.25, 1.5, 1.75, 2]
    nonisolated static let skipBack: Double = 15
    nonisolated static let skipForward: Double = 30

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

    // MARK: Aflevering-modus
    /// De aflevering die speelt (nil = radio of niets)
    @Published private(set) var episode: Episode?
    /// Lijst waaruit de aflevering gestart is (vorige/volgende aflevering)
    @Published private(set) var episodeQueue: [Episode] = []
    /// Afspeelsnelheid voor afleveringen (onthouden)
    @Published private(set) var rate: Float = 1
    /// Slaaptimer "Einde van aflevering"
    @Published private(set) var sleepAtEpisodeEnd = false
    /// Verstreken tijd en duur (eigen object, zie PlaybackProgress)
    let progress = PlaybackProgress()

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
    private var timeObserver: Any?
    /// Positie waar naartoe gespoeld wordt zodra het item klaar is
    private var pendingSeek: Double?
    private var lastPositionSave = Date.distantPast

    var isPlaying: Bool { state == .playing || state == .loading }
    /// Speelt er een aflevering (en geen radio)?
    var isEpisode: Bool { episode != nil }
    /// Is er iets geladen (zender of aflevering)?
    var hasMedia: Bool { station != nil || episode != nil }

    /// Radio: meer dan één zender in de lijst. Aflevering: er is een volgende aflevering.
    var hasNext: Bool {
        if let e = episode {
            guard let i = episodeQueue.firstIndex(of: e) else { return false }
            return i + 1 < episodeQueue.count
        }
        return queue.count > 1
    }

    var hasPrevious: Bool {
        if let e = episode {
            guard let i = episodeQueue.firstIndex(of: e) else { return false }
            return i > 0
        }
        return queue.count > 1
    }

    /// Tekst onder de zendernaam: nu-speelt-titel, anders genres (aflevering: de podcast)
    var subtitle: String {
        if let e = episode { return e.podcastName }
        if !nowPlaying.isEmpty { return nowPlaying }
        return station?.genreLine ?? ""
    }

    /// Titel voor de miniplayer e.d.
    var title: String {
        if let e = episode { return e.displayTitle }
        return station?.displayName ?? ""
    }

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        #if os(iOS) || os(tvOS)
        player.allowsExternalPlayback = true
        #endif
        let saved = UserDefaults.standard.float(forKey: "player.rate")
        if Self.rates.contains(saved) { rate = saved }
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
        leaveEpisodeMode()
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
        pendingSeek = nil
        player.defaultRate = 1
        player.replaceCurrentItem(with: item)
        player.play()
        armWatchdog()
        updateNowPlaying()
    }

    func pause() {
        guard hasMedia else { return }
        player.pause()
        state = .paused
        watchdog?.cancel()
        if episode != nil { saveEpisodePosition() }
        updateNowPlaying()
    }

    func resume() {
        if let e = episode {
            resumeEpisode(e)
            return
        }
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
        if episode != nil { saveEpisodePosition() }
        player.pause()
        player.replaceCurrentItem(with: nil)
        watchdog?.cancel()
        state = .idle
        station = nil
        episode = nil
        episodeQueue = []
        sleepAtEpisodeEnd = false
        pendingSeek = nil
        progress.currentTime = 0
        progress.duration = 0
        nowPlaying = ""
        artworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    func retry() {
        if let e = episode {
            startEpisode(e, at: progress.currentTime)
            return
        }
        guard let s = station else { return }
        usedFallback = false
        start(url: s.streamURL)
    }

    func next() { step(1) }
    func previous() { step(-1) }

    private func step(_ delta: Int) {
        if let e = episode {
            guard let i = episodeQueue.firstIndex(of: e) else { return }
            let n = i + delta
            guard episodeQueue.indices.contains(n) else { return }
            play(episode: episodeQueue[n], queue: episodeQueue)
            return
        }
        guard let s = station, queue.count > 1 else { return }
        let i = queue.firstIndex(of: s) ?? 0
        let n = (i + delta + queue.count) % queue.count
        play(queue[n], queue: queue)
    }

    func toggleFavoriteCurrent() {
        guard episode == nil, let s = station else { return }
        Library.shared.toggleFavorite(s)
        updateRemoteFavorite()
    }

    /// Laatste zender opnieuw laden (Instellingen → automatisch verder spelen)
    func resumeLastIfWanted() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.autoplayLast) else { return }
        playLastStation()
    }

    /// Laatst gespeelde zender opnieuw afspelen als er nu niets geladen is (ook vanuit een widget of het
    /// Bedieningspaneel). `false` = er was geen laatste zender (of er speelt al iets).
    @discardableResult
    func playLastStation() -> Bool {
        guard station == nil, episode == nil,
              let data = UserDefaults.standard.data(forKey: "player.last"),
              let s = try? JSONDecoder().decode(Station.self, from: data) else { return false }
        play(s, queue: Library.shared.favorites.contains(s) ? Library.shared.favorites : [s])
        return true
    }

    // MARK: - Status

    private func observePlayer() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor in self?.timeControlChanged(status) }
            }
            .store(in: &bag)
        // tijd van de aflevering (elke halve seconde; bij radio genegeerd)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        guard hasMedia, state != .paused, state != .failed else { return }
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
        if status == .readyToPlay, episode != nil { itemReady() }
    }

    /// Fout: één keer opnieuw met `url` als `url_resolved` faalde, anders "niet bereikbaar"
    private func handleFailure() {
        if episode != nil {
            guard state != .paused else { return }
            watchdog?.cancel()
            player.pause()
            state = .failed
            updateNowPlaying()
            return
        }
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
        // afleveringen (grote bestanden, spoelen) krijgen wat meer tijd
        let seconds: UInt64 = episode == nil ? 15 : 30
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self, self.state == .loading else { return }
            self.handleFailure()
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
            var loaded: PlatformImage?
            if let url {
                loaded = await ImageLoader.shared.load(url)
            }
            let img = loaded
            guard let self, self.nowPlaying == cleaned else { return }
            self.artworkURL = url
            if let img {
                self.nowPlayingImage = img
                self.updateNowPlaying()
            } else {
                self.loadStationImage()
            }
        }
    }

    private func loadStationImage() {
        guard let s = station, LogoSources.mayHaveLogo(s) else { return }
        Task { [weak self] in
            // logo met terugval (App Store-icoon → Google → favicon → DuckDuckGo), zie LogoSources
            let img = await LogoResolver.shared.image(for: s)
            guard let self, self.station?.id == s.id, self.artworkURL == nil, let img else { return }
            self.nowPlayingImage = img
            self.updateNowPlaying()
        }
    }

    // MARK: - Slaaptimer

    /// `minutes == 0` = uit
    func setSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        sleepAtEpisodeEnd = false
        guard minutes > 0 else {
            sleepEnd = nil
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepEnd = end
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.sleepEnd = nil
            self.pause()
        }
    }

    /// Slaaptimer "Einde van aflevering" (alleen in aflevering-modus)
    func setSleepAtEpisodeEnd() {
        guard episode != nil else { return }
        sleepTask?.cancel()
        sleepEnd = nil
        sleepAtEpisodeEnd = true
    }

    /// Staat er een slaaptimer aan (tijd of einde van aflevering)?
    var sleepActive: Bool { sleepEnd != nil || sleepAtEpisodeEnd }

    private func applyDefaultSleepTimerIfNeeded() {
        let m = UserDefaults.standard.integer(forKey: SettingsKey.defaultSleep)
        if m > 0, sleepEnd == nil, !sleepAtEpisodeEnd { setSleepTimer(minutes: m) }
    }

    // MARK: - Audiosessie (iPhone, iPad, Apple TV)

    private func configureSession() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
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
        try? session.setCategory(.playback, mode: .default, options: [])
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
                if episode != nil { saveEpisodePosition() }
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
        // spoelen alleen bij afleveringen (live radio: niet); aan/uit in updateRemoteCommands()
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self?.seek(to: t) }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: 30)]
        c.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            Task { @MainActor in self?.skip(interval) }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        c.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.skip(-interval) }
            return .success
        }
        c.changePlaybackRateCommand.supportedPlaybackRates = [0.8, 1, 1.25, 1.5, 1.75, 2].map { NSNumber(value: $0) }
        c.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let r = e.playbackRate
            Task { @MainActor in self?.setRate(r) }
            return .success
        }
        c.changePlaybackPositionCommand.isEnabled = false
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
        c.changePlaybackRateCommand.isEnabled = false
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

    /// Radio: vorige/volgende zender, geen spoelen. Aflevering: spoelen, ±15/30 s, snelheid; vorige/volgende uit
    /// (anders tonen het vergrendelscherm en CarPlay geen skip-knoppen).
    private func updateRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        let ep = episode != nil
        c.changePlaybackPositionCommand.isEnabled = ep
        c.skipForwardCommand.isEnabled = ep
        c.skipBackwardCommand.isEnabled = ep
        c.changePlaybackRateCommand.isEnabled = ep
        c.nextTrackCommand.isEnabled = !ep && queue.count > 1
        c.previousTrackCommand.isEnabled = !ep && queue.count > 1
        #if os(iOS)
        c.likeCommand.isEnabled = !ep
        #endif
    }

    private func updateNowPlaying() {
        if let e = episode {
            updateEpisodeNowPlaying(e)
            return
        }
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
        updateRemoteCommands()
        updateRemoteFavorite()
    }

    private func updateEpisodeNowPlaying(_ e: Episode) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: e.displayTitle,
            MPMediaItemPropertyArtist: e.podcastName,
            MPMediaItemPropertyAlbumTitle: e.podcastName,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if progress.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = progress.duration }
        if let i = episodeQueue.firstIndex(of: e) {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = i
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = episodeQueue.count
        }
        if let img = nowPlayingImage {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(img)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = state == .playing ? .playing : (state == .paused ? .paused : .interrupted)
        #endif
        updateRemoteCommands()
    }

    /// Buiten de main actor, zodat de handler (die het systeem op een willekeurige thread aanroept) niet aan de
    /// hoofdthread vastzit.
    nonisolated private static func makeArtwork(_ image: PlatformImage) -> MPMediaItemArtwork {
        let size = image.size
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }
}

// MARK: - Afleveringen (podcasts)

extension RadioPlayer {
    /// Speel een aflevering; `queue` = de lijst waaruit gekozen is (vorige/volgende aflevering).
    /// Hervat op de bewaarde positie (een beluisterde aflevering begint opnieuw).
    func play(episode e: Episode, queue list: [Episode]? = nil) {
        if let list, !list.isEmpty {
            episodeQueue = list.contains(e) ? list : [e] + list
        } else if !episodeQueue.contains(e) {
            episodeQueue = [e]
        }
        if episode?.id == e.id {
            if state == .playing || state == .loading { return }
            resumeEpisode(e)
            return
        }
        if episode != nil { saveEpisodePosition() }
        if station != nil {
            // radio verlaten
            station = nil
            nowPlaying = ""
            artworkTask?.cancel()
        }
        episode = e
        artworkURL = e.artworkURL
        nowPlayingImage = nil
        let saved = Library.shared.position(for: e.id)
        let start = (saved?.finished ?? true) ? 0 : (saved?.seconds ?? 0)
        progress.duration = saved?.duration ?? e.duration
        if progress.duration <= 0 { progress.duration = e.duration }
        progress.currentTime = start
        Library.shared.pushRecentEpisode(e)
        startEpisode(e, at: start)
        loadEpisodeImage(e)
        applyDefaultSleepTimerIfNeeded()
    }

    /// Hervatten na pauze (of opnieuw laden na een fout / aan het einde)
    fileprivate func resumeEpisode(_ e: Episode) {
        let atEnd = progress.duration > 0 && progress.currentTime >= progress.duration - 1
        if player.currentItem == nil || state == .failed || state == .idle {
            startEpisode(e, at: atEnd ? 0 : progress.currentTime)
            return
        }
        if atEnd { seek(to: 0) }
        activateSession()
        player.defaultRate = rate
        state = .loading
        player.play()
        player.rate = rate
        armWatchdog()
        updateNowPlaying()
    }

    fileprivate func startEpisode(_ e: Episode, at seconds: Double) {
        guard let url = e.audioURL else {
            state = .failed
            updateNowPlaying()
            return
        }
        activateSession()
        itemBag.removeAll()
        metadataReceiver = nil
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": Brand.userAgent]])
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor in self?.itemStatusChanged(status) }
            }
            .store(in: &itemBag)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.episodeEnded() } }
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
        pendingSeek = seconds > 1 ? seconds : nil
        lastPositionSave = Date()
        player.defaultRate = rate
        player.replaceCurrentItem(with: item)
        // zonder hervatpositie meteen starten; anders eerst spoelen zodra het item klaar is (itemReady)
        if pendingSeek == nil {
            player.play()
            player.rate = rate
        }
        armWatchdog()
        updateNowPlaying()
    }

    /// Item klaar: duur overnemen en naar de hervatpositie spoelen
    fileprivate func itemReady() {
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { progress.duration = d }
        guard let target = pendingSeek else { return }
        pendingSeek = nil
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.episode != nil, self.state == .loading else { return }
                self.player.play()
                self.player.rate = self.rate
                self.updateNowPlaying()
            }
        }
    }

    fileprivate func tick(_ time: CMTime) {
        guard episode != nil else { return }
        let t = time.seconds
        // tijdens het wachten op de hervatpositie niet terugspringen naar 0
        if t.isFinite, pendingSeek == nil { progress.currentTime = t }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0, abs(d - progress.duration) > 0.5 {
            progress.duration = d
            updateNowPlaying()
        }
        if state == .playing, Date().timeIntervalSince(lastPositionSave) >= 10 {
            saveEpisodePosition(syncCloud: false)
        }
    }

    /// Positie van de huidige aflevering bewaren (elke 10 s lokaal; bij pauze/stop/wissel ook iCloud)
    fileprivate func saveEpisodePosition(syncCloud: Bool = true) {
        guard let e = episode else { return }
        lastPositionSave = Date()
        let t = pendingSeek ?? progress.currentTime
        Library.shared.savePosition(e, seconds: t, duration: progress.duration, syncCloud: syncCloud)
    }

    fileprivate func episodeEnded() {
        guard let e = episode else { return }
        Library.shared.markFinished(e)
        watchdog?.cancel()
        progress.currentTime = progress.duration
        state = .paused
        if sleepAtEpisodeEnd {
            // slaaptimer "Einde van aflevering": stoppen
            sleepAtEpisodeEnd = false
            updateNowPlaying()
            return
        }
        // anders door naar de volgende (nog niet beluisterde) aflevering in de lijst
        if let i = episodeQueue.firstIndex(of: e), i + 1 < episodeQueue.count {
            let next = episodeQueue[i + 1]
            if Library.shared.position(for: next.id)?.finished != true {
                play(episode: next, queue: episodeQueue)
                return
            }
        }
        updateNowPlaying()
    }

    /// Radio of iets anders gaat spelen: positie bewaren en de aflevering loslaten
    fileprivate func leaveEpisodeMode() {
        guard episode != nil else { return }
        saveEpisodePosition()
        episode = nil
        episodeQueue = []
        sleepAtEpisodeEnd = false
        pendingSeek = nil
        progress.currentTime = 0
        progress.duration = 0
    }

    // MARK: Spoelen en snelheid

    func seek(to seconds: Double) {
        guard episode != nil, seconds.isFinite else { return }
        let d = progress.duration
        let target = max(0, d > 0 ? min(seconds, max(0, d - 0.5)) : seconds)
        progress.currentTime = target
        if player.currentItem?.status != .readyToPlay {
            pendingSeek = target
            updateNowPlaying()
            return
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlaying() }
        }
        updateNowPlaying()
    }

    /// ± seconden (−15 / +30)
    func skip(_ delta: Double) {
        guard episode != nil else { return }
        seek(to: progress.currentTime + delta)
    }

    func setRate(_ r: Float) {
        let value = Self.rates.min(by: { abs($0 - r) < abs($1 - r) }) ?? 1
        rate = value
        UserDefaults.standard.set(value, forKey: "player.rate")
        guard episode != nil else { return }
        player.defaultRate = value
        if state == .playing || state == .loading { player.rate = value }
        updateNowPlaying()
    }

    /// Volgende snelheid in het rijtje (knop op tv/CarPlay)
    func cycleRate() {
        let i = Self.rates.firstIndex(of: rate) ?? 1
        setRate(Self.rates[(i + 1) % Self.rates.count])
    }

    fileprivate func loadEpisodeImage(_ e: Episode) {
        guard let url = e.artworkURL else { return }
        Task { [weak self] in
            let img = await ImageLoader.shared.load(url)
            guard let self, self.episode?.id == e.id, let img else { return }
            self.nowPlayingImage = img
            self.updateNowPlaying()
        }
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

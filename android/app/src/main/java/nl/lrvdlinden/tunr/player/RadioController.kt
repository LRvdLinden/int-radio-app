@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package nl.lrvdlinden.tunr.player

import android.content.ComponentName
import android.content.Context
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import nl.lrvdlinden.tunr.AppScope
import nl.lrvdlinden.tunr.data.Episode
import nl.lrvdlinden.tunr.data.EpisodeCache
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.NowPlaying
import nl.lrvdlinden.tunr.data.Station

/**
 * De speler zoals de schermen hem zien: verbindt met [PlaybackService] via een MediaController en zet alles in
 * StateFlows (zender, speelt, buffert, fout, nu speelt, albumhoes, slaaptimer).
 */
object RadioController {

    private var future: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    private var pending: (() -> Unit)? = null

    private val _station = MutableStateFlow<Station?>(null)
    val station: StateFlow<Station?> = _station.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _buffering = MutableStateFlow(false)
    val buffering: StateFlow<Boolean> = _buffering.asStateFlow()

    /** Zender niet bereikbaar (na de automatische tweede poging) */
    private val _error = MutableStateFlow(false)
    val error: StateFlow<Boolean> = _error.asStateFlow()

    private val _nowPlaying = MutableStateFlow<NowPlaying?>(null)
    val nowPlaying: StateFlow<NowPlaying?> = _nowPlaying.asStateFlow()

    /** Albumhoes van het nummer (iTunes) of null → zenderlogo */
    private val _artwork = MutableStateFlow<String?>(null)
    val artwork: StateFlow<String?> = _artwork.asStateFlow()

    /** Lijst van waaruit gestart is (voor vorige/volgende) */
    private val _queue = MutableStateFlow<List<Station>>(emptyList())
    val queue: StateFlow<List<Station>> = _queue.asStateFlow()

    /** Einde van de slaaptimer (epoch ms) of null */
    private val _sleepUntil = MutableStateFlow<Long?>(null)
    val sleepUntil: StateFlow<Long?> = _sleepUntil.asStateFlow()
    private var sleepJob: Job? = null

    private var autoplayChecked = false

    // MARK: podcastmodus (SPEC §8)

    /** Aflevering die nu speelt (dan is [station] null) */
    private val _episode = MutableStateFlow<Episode?>(null)
    val episode: StateFlow<Episode?> = _episode.asStateFlow()

    /** Lijst afleveringen van waaruit gestart is (vorige/volgende) */
    private val _episodeQueue = MutableStateFlow<List<Episode>>(emptyList())
    val episodeQueue: StateFlow<List<Episode>> = _episodeQueue.asStateFlow()

    /** Positie en duur in ms (alleen bij afleveringen; elke 500 ms bijgewerkt tijdens afspelen) */
    private val _position = MutableStateFlow(0L)
    val position: StateFlow<Long> = _position.asStateFlow()
    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()
    private var pollJob: Job? = null

    /** Afspeelsnelheid (0,8–2,0), bewaard in de bibliotheek */
    val speed: StateFlow<Float> get() = Library.playbackSpeed

    /** Slaaptimer "Einde van aflevering" */
    private val _sleepEndOfEpisode = MutableStateFlow(false)
    val sleepEndOfEpisode: StateFlow<Boolean> = _sleepEndOfEpisode.asStateFlow()

    /** Speelt er iets (zender of aflevering)? */
    val hasMedia: Boolean get() = _station.value != null || _episode.value != null

    fun connect(context: Context) {
        if (future != null) return
        val app = context.applicationContext
        val token = SessionToken(app, ComponentName(app, PlaybackService::class.java))
        val f = MediaController.Builder(app, token).buildAsync()
        future = f
        f.addListener({
            val c = runCatching { f.get() }.getOrNull() ?: run { future = null; return@addListener }
            controller = c
            c.addListener(listener)
            syncFrom(c)
            pending?.invoke()
            pending = null
        }, ContextCompat.getMainExecutor(app))
    }

    private fun withController(block: (MediaController) -> Unit) {
        val c = controller
        if (c != null) block(c) else pending = { controller?.let(block) }
    }

    // MARK: bediening

    /** Speel [station] af; [queue] is de lijst waarin hij stond (vorige/volgende blijven daarbinnen). */
    fun play(station: Station, queue: List<Station> = listOf(station)) {
        val list = queue.filter { it.streamUrl.isNotEmpty() }.distinctBy { it.uuid }
        val finalList = if (list.any { it.uuid == station.uuid }) list else listOf(station) + list
        val index = finalList.indexOfFirst { it.uuid == station.uuid }.coerceAtLeast(0)
        StationCache.putAll(finalList)
        _episode.value = null
        _episodeQueue.value = emptyList()
        _sleepEndOfEpisode.value = false
        stopPolling()
        _station.value = station
        _queue.value = finalList
        _error.value = false
        _nowPlaying.value = null
        _artwork.value = null
        _buffering.value = true
        withController { c ->
            c.setMediaItems(finalList.map { it.toMediaItem() }, index, 0L)
            c.prepare()
            c.play()
        }
        // Standaard slaaptimer uit Instellingen
        val def = Library.settings.value.defaultSleepMinutes
        if (def > 0 && _sleepUntil.value == null) setSleepTimer(def)
    }

    fun togglePlay() = withController { c ->
        if (c.isPlaying || c.playWhenReady && c.playbackState == Player.STATE_BUFFERING) c.pause()
        else {
            if (c.playbackState == Player.STATE_IDLE) c.prepare()
            if (c.playbackState == Player.STATE_ENDED) c.seekTo(0L) // aflevering was afgelopen: opnieuw
            c.play()
        }
    }

    fun pause() = withController { it.pause() }

    /** Opnieuw proberen na een fout */
    fun retry() {
        _episode.value?.let { playEpisode(it, _episodeQueue.value); return }
        val s = _station.value ?: return
        play(s, _queue.value)
    }

    fun next() = withController { if (it.mediaItemCount > 1) it.seekToNext() }
    fun previous() = withController { if (it.mediaItemCount > 1) it.seekToPrevious() }

    val canSkip: Boolean get() = if (_episode.value != null) _episodeQueue.value.size > 1 else _queue.value.size > 1

    fun stop() = withController {
        it.stop()
        it.clearMediaItems()
        _station.value = null
        _queue.value = emptyList()
        _episode.value = null
        _episodeQueue.value = emptyList()
        _sleepEndOfEpisode.value = false
        stopPolling()
    }

    // MARK: afleveringen

    /**
     * Speel [episode] af via dezelfde Media3-sessie; [list] = de lijst waarin hij stond (vorige/volgende blijven
     * daarbinnen). Hervat op de bewaarde positie als de aflevering half beluisterd is.
     */
    fun playEpisode(episode: Episode, list: List<Episode> = listOf(episode)) {
        val clean = list.filter { it.url.isNotEmpty() }.distinctBy { it.id }
        val finalList = if (clean.any { it.id == episode.id }) clean else listOf(episode) + clean
        val index = finalList.indexOfFirst { it.id == episode.id }.coerceAtLeast(0)
        EpisodeCache.putAll(finalList)
        val saved = Library.progressOf(episode.id)
        val start = if (saved != null && saved.inProgress) saved.positionMs else 0L
        _station.value = null
        _queue.value = emptyList()
        _nowPlaying.value = null
        _artwork.value = null
        _episode.value = episode
        _episodeQueue.value = finalList
        _error.value = false
        _buffering.value = true
        _position.value = start
        _duration.value = episode.durationMs
        withController { c ->
            c.setMediaItems(finalList.map { it.toMediaItem() }, index, start)
            c.setPlaybackSpeed(Library.playbackSpeed.value)
            c.prepare()
            c.play()
        }
        val def = Library.settings.value.defaultSleepMinutes
        if (def > 0 && _sleepUntil.value == null && !_sleepEndOfEpisode.value) setSleepTimer(def)
    }

    fun seekTo(ms: Long) {
        val d = _duration.value
        val target = if (d > 0) ms.coerceIn(0L, d) else ms.coerceAtLeast(0L)
        _position.value = target
        withController { it.seekTo(target) }
    }

    /** 15 s terug */
    fun skipBack() = withController {
        it.seekBack()
        _position.value = it.currentPosition
    }

    /** 30 s vooruit */
    fun skipForward() = withController {
        it.seekForward()
        _position.value = it.currentPosition
    }

    fun setSpeed(value: Float) {
        Library.setPlaybackSpeed(value)
        if (_episode.value != null) withController { it.setPlaybackSpeed(Library.playbackSpeed.value) }
    }

    private fun startPolling() {
        if (pollJob?.isActive == true) return
        pollJob = AppScope.launch {
            while (true) {
                val c = controller
                if (c == null || !c.isPlaying || _episode.value == null) break
                _position.value = c.currentPosition.coerceAtLeast(0L)
                c.duration.takeIf { it > 0 }?.let { _duration.value = it }
                delay(500)
            }
            pollJob = null
        }
    }

    private fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    // MARK: slaaptimer

    /** [minutes] 0 = uit */
    fun setSleepTimer(minutes: Int) {
        sleepJob?.cancel()
        _sleepEndOfEpisode.value = false
        if (minutes <= 0) { _sleepUntil.value = null; return }
        val until = System.currentTimeMillis() + minutes * 60_000L
        _sleepUntil.value = until
        sleepJob = AppScope.launch {
            while (System.currentTimeMillis() < until) delay(1_000)
            pause()
            _sleepUntil.value = null
        }
    }

    /** Slaaptimer: pauzeren aan het einde van de huidige aflevering */
    fun setSleepAtEndOfEpisode() {
        sleepJob?.cancel()
        _sleepUntil.value = null
        _sleepEndOfEpisode.value = _episode.value != null
    }

    // MARK: automatisch verder spelen

    /** Bij opstarten: laatste zender als dat in Instellingen aan staat (één keer per proces). */
    fun autoplayLastIfWanted() {
        if (autoplayChecked) return
        autoplayChecked = true
        if (!Library.settings.value.autoplayLast) return
        if (_station.value != null) return
        val last = Library.lastStation ?: return
        play(last, Library.recents.value.ifEmpty { listOf(last) })
    }

    // MARK: toestand uit de speler

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            syncFrom(player)
        }

        override fun onPlayerError(error: PlaybackException) {
            // De dienst probeert zelf één keer `url`; blijft het mis, dan de melding tonen
            AppScope.launch {
                delay(2_500)
                val c = controller ?: return@launch
                if (c.playerError != null) {
                    _error.value = true
                    _buffering.value = false
                }
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            // "Einde van aflevering": de vorige liep vanzelf af → stoppen (aan het begin van de volgende)
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO && _sleepEndOfEpisode.value) {
                _sleepEndOfEpisode.value = false
                controller?.pause()
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_ENDED) _sleepEndOfEpisode.value = false
        }

        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
            // ICY-titel en albumhoes zet de dienst in de extras van het MediaItem
            readNowPlaying(controller?.currentMediaItem?.mediaMetadata ?: mediaMetadata)
        }
    }

    private fun syncFrom(p: Player) {
        _isPlaying.value = p.isPlaying
        _buffering.value = p.playWhenReady && p.playbackState == Player.STATE_BUFFERING
        if (p.isPlaying) _error.value = false
        val item: MediaItem? = p.currentMediaItem
        if (item == null) return
        // Aflevering: podcastmodus (positie/duur, wachtrij van afleveringen)
        val epId = episodeIdOf(item.mediaId)
        if (epId != null) {
            val ep = EpisodeCache[epId]
            if (ep != null && ep.id != _episode.value?.id) {
                _episode.value = ep
                _station.value = null
                _queue.value = emptyList()
                _nowPlaying.value = null
                _artwork.value = null
                _error.value = false
            }
            if (_episodeQueue.value.none { it.id == epId }) {
                _episodeQueue.value = (0 until p.mediaItemCount).mapNotNull { EpisodeCache[episodeIdOf(p.getMediaItemAt(it).mediaId)] }
            }
            _position.value = p.currentPosition.coerceAtLeast(0L)
            val d = p.duration
            if (d > 0) _duration.value = d else if (ep != null && ep.durationMs > 0) _duration.value = ep.durationMs
            if (p.isPlaying) startPolling() else stopPolling()
            return
        }
        if (_episode.value != null) {
            _episode.value = null
            _episodeQueue.value = emptyList()
            stopPolling()
        }
        val s = StationCache[item.mediaId]
        if (s != null && s.uuid != _station.value?.uuid) {
            _station.value = s
            _nowPlaying.value = null
            _artwork.value = null
            _error.value = false
        }
        // Na het opstarten speelt de dienst al (bijv. vanuit Android Auto): wachtrij overnemen
        if (_queue.value.isEmpty() || _queue.value.none { it.uuid == item.mediaId }) {
            val ids = (0 until p.mediaItemCount).map { p.getMediaItemAt(it).mediaId }
            _queue.value = ids.mapNotNull { StationCache[it] }
        }
        readNowPlaying(item.mediaMetadata)
    }

    private fun readNowPlaying(m: MediaMetadata) {
        val ex = m.extras ?: run { _nowPlaying.value = null; _artwork.value = null; return }
        val title = ex.getString(Extras.NP_TITLE)
        _nowPlaying.value = title?.let { NowPlaying(ex.getString(Extras.NP_ARTIST), it) }
        _artwork.value = ex.getString(Extras.NP_ART)
    }
}

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
            c.play()
        }
    }

    fun pause() = withController { it.pause() }

    /** Opnieuw proberen na een fout */
    fun retry() {
        val s = _station.value ?: return
        play(s, _queue.value)
    }

    fun next() = withController { if (it.mediaItemCount > 1) it.seekToNext() }
    fun previous() = withController { if (it.mediaItemCount > 1) it.seekToPrevious() }

    val canSkip: Boolean get() = _queue.value.size > 1

    fun stop() = withController {
        it.stop()
        it.clearMediaItems()
        _station.value = null
        _queue.value = emptyList()
    }

    // MARK: slaaptimer

    /** [minutes] 0 = uit */
    fun setSleepTimer(minutes: Int) {
        sleepJob?.cancel()
        if (minutes <= 0) { _sleepUntil.value = null; return }
        val until = System.currentTimeMillis() + minutes * 60_000L
        _sleepUntil.value = until
        sleepJob = AppScope.launch {
            while (System.currentTimeMillis() < until) delay(1_000)
            pause()
            _sleepUntil.value = null
        }
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

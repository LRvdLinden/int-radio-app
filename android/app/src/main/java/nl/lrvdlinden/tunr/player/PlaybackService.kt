@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package nl.lrvdlinden.tunr.player

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Metadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.metadata.icy.IcyInfo
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import nl.lrvdlinden.tunr.Brand
import nl.lrvdlinden.tunr.LocaleHelper
import nl.lrvdlinden.tunr.MainActivity
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.LogoSources
import nl.lrvdlinden.tunr.data.Artwork
import nl.lrvdlinden.tunr.data.Episode
import nl.lrvdlinden.tunr.data.EpisodeCache
import nl.lrvdlinden.tunr.data.GENRE_TAGS
import nl.lrvdlinden.tunr.data.Http
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.NowPlaying
import nl.lrvdlinden.tunr.data.Podcast
import nl.lrvdlinden.tunr.data.PodcastApi
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.data.Stats
import nl.lrvdlinden.tunr.data.localizedCountryName

/**
 * Afspelen op de achtergrond: ExoPlayer + MediaLibrarySession (mediamelding, vergrendelscherm, koptelefoonknoppen,
 * Android Auto). Telt klikken en houdt "Recent" bij voor alles wat hier speelt (ook vanuit de auto).
 */
class PlaybackService : MediaLibraryService() {

    private var session: MediaLibrarySession? = null
    private lateinit var exo: ExoPlayer
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** Per uuid: al eens opnieuw geprobeerd met `url` */
    private val retried = HashSet<String>()
    private var lastIcy: String? = null
    private var lastCounted: String? = null

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(LocaleHelper.wrap(base))
    }

    override fun onCreate() {
        super.onCreate()
        Library.init(this)
        RadioBrowser.init(this)
        PodcastApi.init(this)

        val http = OkHttpDataSource.Factory(Http.client)
            .setUserAgent(Brand.userAgent)
            .setDefaultRequestProperties(mapOf("Icy-MetaData" to "1"))
        exo = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(this).setDataSourceFactory(http))
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                /* handleAudioFocus = */ true
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            // Podcasts: 15 s terug / 30 s vooruit (melding, vergrendelscherm, koptelefoon, Android Auto)
            .setSeekBackIncrementMs(SEEK_BACK_MS)
            .setSeekForwardIncrementMs(SEEK_FORWARD_MS)
            .build()
        exo.addListener(listener)

        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        session = MediaLibrarySession.Builder(this, RadioPlayer(exo), LibraryCallback())
            .setSessionActivity(open)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        // App weggeveegd en er speelt niets: dienst stoppen. Speelt er wel iets, dan doorgaan (zoals Spotify/TuneIn).
        val p = session?.player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        saveEpisodeProgress()
        scope.cancel()
        session?.run {
            player.release()
            release()
        }
        session = null
        super.onDestroy()
    }

    // MARK: speler-gebeurtenissen

    private val listener = object : Player.Listener {
        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            // Aflevering: de vorige bewaren (of als beluisterd markeren als hij vanzelf afliep), dan hervatten
            onEpisodeTransition(mediaItem, reason)
            // Ook een metadata-update (replaceMediaItem) kan hier komen: alleen bij een echt andere zender tellen
            val id = mediaItem?.mediaId
            if (id == null || id == lastCounted) return
            lastCounted = id
            lastIcy = null
            val station = StationCache[id] ?: return
            // Klik tellen + bovenaan "Recent" (max 30)
            Library.addRecent(station)
            scope.launch(Dispatchers.IO) { RadioBrowser.click(station.uuid) }
        }

        override fun onMetadata(metadata: Metadata) {
            for (i in 0 until metadata.length()) {
                val entry = metadata.get(i)
                if (entry is IcyInfo) onIcyTitle(entry.title)
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            // Gestopt (wachtrij leeg): de volgende keer dezelfde zender weer tellen
            if (playbackState == Player.STATE_IDLE && exo.mediaItemCount == 0) lastCounted = null
            // Laatste aflevering van de lijst afgelopen: beluisterd
            if (playbackState == Player.STATE_ENDED) {
                currentEpisode()?.let { Library.markFinished(it, true) }
                lastEpisode = null
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (isPlaying) startProgressTicker() else {
                progressJob?.cancel()
                saveEpisodeProgress() // bij pauze
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            // url_resolved faalde: één keer opnieuw met `url`
            val index = exo.currentMediaItemIndex
            val item = exo.currentMediaItem ?: return
            if (isEpisodeId(item.mediaId)) return
            val alt = item.mediaMetadata.extras?.getString(Extras.ALT_URL)
            if (alt.isNullOrEmpty() || !retried.add(item.mediaId)) return
            val replacement = item.buildUpon()
                .setUri(alt)
                .setMimeType(if (alt.contains(".m3u8", true)) androidx.media3.common.MimeTypes.APPLICATION_M3U8 else null)
                .build()
            exo.replaceMediaItem(index, replacement)
            exo.prepare()
            exo.play()
        }
    }

    // MARK: afleveringen: positie onthouden en hervatten (SPEC §8)

    private var progressJob: Job? = null
    /** Laatst bekende aflevering + positie (bij een overgang wijst currentPosition al naar het volgende item) */
    private var lastEpisode: Episode? = null
    private var lastEpisodePos: Long = 0L
    private var lastEpisodeDur: Long = 0L

    private fun currentEpisode(): Episode? = episodeIdOf(exo.currentMediaItem?.mediaId)?.let { EpisodeCache[it] }

    /** Elke seconde de positie bijhouden, elke 10 s bewaren */
    private fun startProgressTicker() {
        progressJob?.cancel()
        progressJob = scope.launch {
            var ticks = 0
            while (isActive) {
                val ep = currentEpisode()
                if (ep != null) {
                    lastEpisode = ep
                    lastEpisodePos = exo.currentPosition
                    lastEpisodeDur = exo.duration.takeIf { it > 0 } ?: ep.durationMs
                    if (++ticks % 10 == 0) Library.saveProgress(ep, lastEpisodePos, lastEpisodeDur)
                }
                delay(1_000)
            }
        }
    }

    private fun saveEpisodeProgress() {
        val ep = currentEpisode() ?: return
        val dur = exo.duration.takeIf { it > 0 } ?: ep.durationMs
        Library.saveProgress(ep, exo.currentPosition, dur)
        lastEpisode = ep; lastEpisodePos = exo.currentPosition; lastEpisodeDur = dur
    }

    private var seekButtonsShown = false

    /** Mediamelding: bij afleveringen knoppen 15 s terug / 30 s vooruit; bij radio niet */
    private fun updateSeekButtons(episode: Boolean) {
        if (episode == seekButtonsShown) return
        seekButtonsShown = episode
        val layout: List<CommandButton> = if (!episode) emptyList() else listOf(
            CommandButton.Builder()
                .setDisplayName(getString(R.string.skip_back_15))
                .setIconResId(R.drawable.ic_seek_back)
                .setPlayerCommand(Player.COMMAND_SEEK_BACK)
                .build(),
            CommandButton.Builder()
                .setDisplayName(getString(R.string.skip_forward_30))
                .setIconResId(R.drawable.ic_seek_forward)
                .setPlayerCommand(Player.COMMAND_SEEK_FORWARD)
                .build(),
        )
        session?.setCustomLayout(ImmutableList.copyOf(layout))
    }

    private fun onEpisodeTransition(item: MediaItem?, reason: Int) {
        val prev = lastEpisode
        val newId = episodeIdOf(item?.mediaId)
        if (prev != null && prev.id != newId) {
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO) Library.markFinished(prev, true)
            else Library.saveProgress(prev, lastEpisodePos, lastEpisodeDur)
        }
        updateSeekButtons(newId != null)
        // Snelheid: afleveringen met de gekozen snelheid, radio altijd 1×
        val speed = if (newId != null) Library.playbackSpeed.value else 1f
        if (exo.playbackParameters.speed != speed) exo.setPlaybackSpeed(speed)
        if (newId == null) { lastEpisode = null; return }
        val ep = EpisodeCache[newId]
        if (ep == null) { lastEpisode = null; return }
        if (prev?.id == newId) return // metadata-update van hetzelfde item
        lastEpisode = ep
        lastEpisodePos = 0L
        lastEpisodeDur = ep.durationMs
        // Hervatten waar je was (half beluisterd); beluisterde afleveringen beginnen opnieuw
        val saved = Library.progressOf(ep.id)
        if (saved != null && saved.inProgress && exo.currentPosition < 2_000) {
            exo.seekTo(saved.positionMs)
            lastEpisodePos = saved.positionMs
        }
    }

    /** ICY "StreamTitle": titel/artiest in de melding zetten en een albumhoes zoeken (iTunes). */
    private fun onIcyTitle(raw: String?) {
        if (raw == lastIcy) return
        lastIcy = raw
        val item = exo.currentMediaItem ?: return
        if (isEpisodeId(item.mediaId)) return // afleveringen houden hun eigen titel
        val station = StationCache[item.mediaId]
        val name = station?.displayName ?: item.mediaMetadata.station?.toString() ?: ""
        val np = NowPlaying.parse(raw)?.takeIf { !it.line.equals(name, ignoreCase = true) }
        updateNowPlaying(item.mediaId, station, np, null)
        if (np != null) scope.launch {
            val art = Artwork.lookup(np)
            if (art != null && lastIcy == raw) updateNowPlaying(item.mediaId, station, np, art)
        }
    }

    private fun updateNowPlaying(mediaId: String, station: Station?, np: NowPlaying?, art: String?) {
        val index = exo.currentMediaItemIndex
        val item = exo.currentMediaItem ?: return
        if (item.mediaId != mediaId) return
        val old = item.mediaMetadata
        val extras = Bundle(old.extras ?: Bundle()).apply {
            remove(Extras.NP_ARTIST); remove(Extras.NP_TITLE); remove(Extras.NP_ART)
            if (np != null) {
                np.artist?.let { putString(Extras.NP_ARTIST, it) }
                putString(Extras.NP_TITLE, np.title)
            }
            art?.let { putString(Extras.NP_ART, it) }
        }
        val name = station?.displayName ?: old.station?.toString() ?: old.title?.toString() ?: ""
        val stationArt = station?.let { LogoSources.best(it) }
        val meta = old.buildUpon()
            // ExoPlayer legt de ruwe ICY-titel er toch over (title); daarom de zendernaam als artiest-regel
            .setTitle(np?.line ?: name)
            .setArtist(if (np != null) name else (station?.genresLine?.ifEmpty { null } ?: old.artist))
            .setArtworkUri((art ?: stationArt)?.let { Uri.parse(it) })
            .setExtras(extras)
            .build()
        // Zelfde stream-URI: ExoPlayer werkt alleen de metadata bij, zonder het afspelen te onderbreken
        exo.replaceMediaItem(index, item.buildUpon().setMediaMetadata(meta).build())
    }

    // MARK: Android Auto / mediabrowsers

    private inner class LibraryCallback : MediaLibrarySession.Callback {

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: MediaLibraryService.LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> {
            // voor de anonieme statistieken: "ooit Android Auto gebruikt"
            if (browser.packageName == Stats.ANDROID_AUTO_PACKAGE) Stats.markAndroidAutoUsed(this@PlaybackService)
            return Futures.immediateFuture(LibraryResult.ofItem(folderItem(ROOT, getString(R.string.app_name), MediaMetadata.MEDIA_TYPE_FOLDER_MIXED), params))
        }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val ep = episodeIdOf(mediaId)?.let { EpisodeCache[it] }
            if (ep != null) return Futures.immediateFuture(LibraryResult.ofItem(ep.toMediaItem(), null))
            val s = StationCache[mediaId]
            return Futures.immediateFuture(
                if (s != null) LibraryResult.ofItem(s.toMediaItem(), null)
                else LibraryResult.ofError<MediaItem>(LibraryResult.RESULT_ERROR_BAD_VALUE)
            )
        }

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: MediaLibraryService.LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            val future = SettableFuture.create<LibraryResult<ImmutableList<MediaItem>>>()
            scope.launch {
                val items: List<MediaItem> = runCatching { children(parentId) }.getOrDefault(emptyList())
                future.set(LibraryResult.ofItemList(ImmutableList.copyOf(items), params))
            }
            return future
        }

        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> {
            val future = SettableFuture.create<MutableList<MediaItem>>()
            scope.launch {
                val missing = mediaItems.map { it.mediaId }
                    .filter { it.isNotEmpty() && !isEpisodeId(it) && !it.contains(':') && StationCache[it] == null }
                if (missing.isNotEmpty()) runCatching { StationCache.putAll(RadioBrowser.byUuids(missing)) }
                val resolved = mediaItems.mapNotNull { resolve(it) }.toMutableList()
                future.set(resolved)
            }
            return future
        }

        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            // Eén zender gekozen in Android Auto: de hele lijst waar hij in stond wordt de wachtrij (vorige/volgende)
            val single = mediaItems.singleOrNull()
            val fromOtherApp = controller.packageName != packageName
            val epList = single?.let { lastEpisodeLists[it.mediaId] }
            val list = single?.let { lastLists[it.mediaId] }
            val items: MutableList<MediaItem>
            val start: Int
            if (single != null && epList != null && fromOtherApp) {
                // Aflevering in Android Auto: de afleveringen van die podcast worden de wachtrij
                items = epList.map { it.toMediaItem() }.toMutableList()
                start = epList.indexOfFirst { EPISODE_PREFIX + it.id == single.mediaId }.coerceAtLeast(0)
            } else if (single != null && list != null && fromOtherApp) {
                items = list.map { it.toMediaItem() }.toMutableList()
                start = list.indexOfFirst { it.uuid == single.mediaId }.coerceAtLeast(0)
            } else {
                items = mediaItems
                start = startIndex
            }
            val future = SettableFuture.create<MediaSession.MediaItemsWithStartPosition>()
            val added = onAddMediaItems(mediaSession, controller, items)
            added.addListener({
                val resolved = runCatching { added.get() }.getOrDefault(mutableListOf())
                val idx = if (resolved.isEmpty()) C.INDEX_UNSET else start.coerceIn(0, resolved.size - 1)
                // Aflevering vanuit de app met een bewaarde positie: daar beginnen; radio altijd live (TIME_UNSET)
                val startItemIsEpisode = idx >= 0 && isEpisodeId(resolved.getOrNull(idx)?.mediaId)
                val pos = if (startItemIsEpisode && items === mediaItems && startPositionMs > 0) startPositionMs else C.TIME_UNSET
                future.set(MediaSession.MediaItemsWithStartPosition(resolved, idx, pos))
            }, { it.run() })
            return future
        }
    }

    /** Laatst getoonde lijst per zender (voor de wachtrij in Android Auto) */
    private val lastLists = HashMap<String, List<Station>>()
    /** Idem per aflevering (mediaId "ep:<id>") */
    private val lastEpisodeLists = HashMap<String, List<Episode>>()

    /** MediaItem uit een controller → met stream-URI (controllers sturen de URI niet mee, alleen mediaId/requestMetadata). */
    private fun resolve(item: MediaItem): MediaItem? {
        episodeIdOf(item.mediaId)?.let { id -> EpisodeCache[id]?.let { return it.toMediaItem() } }
        StationCache[item.mediaId]?.let { return it.toMediaItem() }
        val uri = item.requestMetadata.mediaUri ?: item.localConfiguration?.uri ?: return null
        return item.buildUpon().setUri(uri).build()
    }

    private suspend fun children(parentId: String): List<MediaItem> {
        val cc = Library.country.value?.code ?: LocaleHelper.deviceCountry().ifEmpty { "NL" }
        val stations: List<Station> = when {
            parentId == ROOT -> {
                val land = localizedCountryName(cc, cc)
                return listOf(
                    folderItem(FAVORITES, getString(R.string.tab_favorites)),
                    folderItem(RECENTS, getString(R.string.recent)),
                    folderItem(POPULAR, getString(R.string.popular_in, land)),
                    folderItem(GENRES, getString(R.string.genres), MediaMetadata.MEDIA_TYPE_FOLDER_GENRES),
                    folderItem(PODCASTS, getString(R.string.podcasts), MediaMetadata.MEDIA_TYPE_FOLDER_PODCASTS),
                )
            }
            parentId == PODCASTS -> return Library.followedPodcasts.value.map { podcastFolder(it) }
            parentId.startsWith(PODCAST_PREFIX) -> {
                val id = parentId.removePrefix(PODCAST_PREFIX)
                val episodes = PodcastApi.lookup(id, cc)?.second.orEmpty().take(50)
                episodes.forEach { lastEpisodeLists[EPISODE_PREFIX + it.id] = episodes }
                return episodes.map { it.toMediaItem() }
            }
            parentId == GENRES -> return GENRE_TAGS.map { tag ->
                folderItem(GENRE_PREFIX + tag, getString(genreLabel(tag)), MediaMetadata.MEDIA_TYPE_GENRE)
            }
            parentId == FAVORITES -> Library.favorites.value
            parentId == RECENTS -> Library.recents.value
            parentId == POPULAR -> RadioBrowser.popular(cc, 40)
            parentId.startsWith(GENRE_PREFIX) -> RadioBrowser.byTag(parentId.removePrefix(GENRE_PREFIX), cc, 40)
            else -> emptyList()
        }
        stations.forEach { lastLists[it.uuid] = stations }
        return stations.map { it.toMediaItem() }
    }

    /** Gevolgde podcast als map (met art) in de bladerboom */
    private fun podcastFolder(p: Podcast): MediaItem =
        MediaItem.Builder()
            .setMediaId(PODCAST_PREFIX + p.id)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(p.displayName)
                    .setArtist(p.artist)
                    .setSubtitle(p.artist)
                    .setArtworkUri(p.artwork.takeIf { it.startsWith("http") }?.let { Uri.parse(it) })
                    .setIsBrowsable(true)
                    .setIsPlayable(false)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_PODCAST)
                    .build()
            )
            .build()

    companion object {
        const val ROOT = "root"
        const val FAVORITES = "favorites"
        const val RECENTS = "recents"
        const val POPULAR = "popular"
        const val GENRES = "genres"
        const val GENRE_PREFIX = "genre:"
        const val PODCASTS = "podcasts"
        const val PODCAST_PREFIX = "pod:"
        const val SEEK_BACK_MS = 15_000L
        const val SEEK_FORWARD_MS = 30_000L

        /** Tekst-sleutel voor een genre-tag */
        fun genreLabel(tag: String): Int = when (tag) {
            "pop" -> R.string.genre_pop
            "news" -> R.string.genre_news
            "rock" -> R.string.genre_rock
            "dance" -> R.string.genre_dance
            "jazz" -> R.string.genre_jazz
            "classical" -> R.string.genre_classical
            "hits" -> R.string.genre_hits
            "talk" -> R.string.genre_talk
            "sports" -> R.string.genre_sports
            "oldies" -> R.string.genre_oldies
            "hiphop" -> R.string.genre_hiphop
            "country" -> R.string.genre_country
            "ambient" -> R.string.genre_ambient
            "christian" -> R.string.genre_christian
            else -> R.string.genre_other
        }
    }
}

/**
 * Radio-gedrag voor vorige/volgende: altijd naar de vorige/volgende zender (nooit "terug naar het begin" van een
 * livestream), met doorlopen van het eind naar het begin. Geldt voor de app, de melding en Android Auto.
 */
private class RadioPlayer(player: Player) : ForwardingPlayer(player) {
    override fun seekToNext() = step(+1)
    override fun seekToPrevious() = step(-1)
    override fun seekToNextMediaItem() = step(+1)
    override fun seekToPreviousMediaItem() = step(-1)

    private fun step(dir: Int) {
        val n = mediaItemCount
        // Afleveringen: vorige/volgende in de lijst, zonder rond te lopen; vorige op de eerste = naar het begin
        if (isEpisodeId(currentMediaItem?.mediaId)) {
            val target = currentMediaItemIndex + dir
            if (target < 0 || n <= 1) { seekTo(0L); return }
            if (target >= n) return
            seekToDefaultPosition(target)
            if (!playWhenReady) play()
            return
        }
        if (n <= 1) return
        val next = ((currentMediaItemIndex + dir) % n + n) % n
        seekToDefaultPosition(next)
        if (!playWhenReady) play()
    }

    override fun getAvailableCommands(): Player.Commands {
        val base = super.getAvailableCommands()
        if (mediaItemCount <= 1) return base
        return base.buildUpon()
            .addAll(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
            .build()
    }

    override fun isCommandAvailable(command: Int): Boolean = availableCommands.contains(command)
}

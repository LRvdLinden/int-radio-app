package nl.lrvdlinden.tunr.data

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer

/** Instellingen (SPEC §4 Instellingen). */
@Serializable
data class Settings(
    /** "system", "nl" of "en" */
    val language: String = SYSTEM,
    val introMusic: Boolean = true,
    /** Standaard slaaptimer in minuten (0 = uit) */
    val defaultSleepMinutes: Int = 0,
    val autoplayLast: Boolean = false,
) {
    companion object { const val SYSTEM = "system" }
}

/** Gekozen land (code + Engelse naam voor /json/states) */
@Serializable
data class SelectedCountry(val code: String, val name: String)

/**
 * Bibliotheek: favorieten, recent (30), recente zoekopdrachten (8), land, lokale regio en instellingen.
 * Lokaal in SharedPreferences als JSON (volledige zender, zodat de lijsten offline werken).
 */
object Library {
    const val PREFS = "tunr_library"
    const val KEY_SETTINGS = "settings"
    private const val KEY_FAVORITES = "favorites"
    private const val KEY_RECENTS = "recents"
    private const val KEY_SEARCHES = "recent_searches"
    private const val KEY_COUNTRY = "country"
    private const val KEY_REGION = "local_region"
    private const val KEY_LAST = "last_station"
    private const val KEY_PODCASTS = "followed_podcasts"
    private const val KEY_PROGRESS = "episode_progress"
    private const val KEY_SPEED = "playback_speed"

    private const val MAX_RECENTS = 30
    private const val MAX_SEARCHES = 8
    /** Max. bewaarde afspeelposities (oudste eruit, SPEC §8) */
    private const val MAX_PROGRESS = 500

    private lateinit var prefs: SharedPreferences
    private val json get() = Http.json
    private val stationList = ListSerializer(Station.serializer())
    private val podcastList = ListSerializer(Podcast.serializer())
    private val progressList = ListSerializer(EpisodeProgress.serializer())

    private val _favorites = MutableStateFlow<List<Station>>(emptyList())
    val favorites: StateFlow<List<Station>> = _favorites.asStateFlow()

    private val _recents = MutableStateFlow<List<Station>>(emptyList())
    val recents: StateFlow<List<Station>> = _recents.asStateFlow()

    private val _searches = MutableStateFlow<List<String>>(emptyList())
    val recentSearches: StateFlow<List<String>> = _searches.asStateFlow()

    private val _country = MutableStateFlow<SelectedCountry?>(null)
    val country: StateFlow<SelectedCountry?> = _country.asStateFlow()

    private val _region = MutableStateFlow<String?>(null)
    val localRegion: StateFlow<String?> = _region.asStateFlow()

    private val _settings = MutableStateFlow(Settings())
    val settings: StateFlow<Settings> = _settings.asStateFlow()

    /** Gevolgde podcasts (nieuwste volg-actie eerst) */
    private val _podcasts = MutableStateFlow<List<Podcast>>(emptyList())
    val followedPodcasts: StateFlow<List<Podcast>> = _podcasts.asStateFlow()

    /** Afspeelposities per aflevering-id */
    private val _progress = MutableStateFlow<Map<String, EpisodeProgress>>(emptyMap())
    val progress: StateFlow<Map<String, EpisodeProgress>> = _progress.asStateFlow()

    /** Afspeelsnelheid voor afleveringen (0,8–2,0) */
    private val _speed = MutableStateFlow(1f)
    val playbackSpeed: StateFlow<Float> = _speed.asStateFlow()

    private var initialized = false

    fun init(context: Context) {
        if (initialized) return
        initialized = true
        prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        _favorites.value = read(KEY_FAVORITES, stationList) ?: emptyList()
        _recents.value = read(KEY_RECENTS, stationList) ?: emptyList()
        _searches.value = read(KEY_SEARCHES, ListSerializer(String.serializer())) ?: emptyList()
        _country.value = read(KEY_COUNTRY, SelectedCountry.serializer())
        _region.value = prefs.getString(KEY_REGION, null)
        _settings.value = read(KEY_SETTINGS, Settings.serializer()) ?: Settings()
        _podcasts.value = read(KEY_PODCASTS, podcastList) ?: emptyList()
        _progress.value = (read(KEY_PROGRESS, progressList) ?: emptyList()).associateBy { it.episodeId }
        _speed.value = prefs.getFloat(KEY_SPEED, 1f).coerceIn(0.8f, 2f)
    }

    private fun <T> read(key: String, ser: kotlinx.serialization.KSerializer<T>): T? {
        val raw = prefs.getString(key, null) ?: return null
        return runCatching { json.decodeFromString(ser, raw) }.getOrNull()
    }

    private fun <T> write(key: String, ser: kotlinx.serialization.KSerializer<T>, value: T) {
        prefs.edit().putString(key, json.encodeToString(ser, value)).apply()
    }

    // MARK: favorieten

    fun isFavorite(uuid: String): Boolean = _favorites.value.any { it.uuid == uuid }

    fun toggleFavorite(s: Station) {
        val list = _favorites.value
        _favorites.value = if (list.any { it.uuid == s.uuid }) list.filterNot { it.uuid == s.uuid } else listOf(s) + list
        write(KEY_FAVORITES, stationList, _favorites.value)
    }

    fun removeFavorite(uuid: String) {
        _favorites.value = _favorites.value.filterNot { it.uuid == uuid }
        write(KEY_FAVORITES, stationList, _favorites.value)
    }

    fun clearFavorites() {
        _favorites.value = emptyList()
        write(KEY_FAVORITES, stationList, emptyList())
    }

    /** Favorieten bijwerken met verse gegevens (logo, stream), volgorde blijft */
    fun refreshFavorites(fresh: List<Station>) {
        if (fresh.isEmpty()) return
        val byId = fresh.associateBy { it.uuid }
        _favorites.value = _favorites.value.map { byId[it.uuid] ?: it }
        write(KEY_FAVORITES, stationList, _favorites.value)
    }

    // MARK: recent

    fun addRecent(s: Station) {
        _recents.value = (listOf(s) + _recents.value.filterNot { it.uuid == s.uuid }).take(MAX_RECENTS)
        write(KEY_RECENTS, stationList, _recents.value)
        prefs.edit().putString(KEY_LAST, json.encodeToString(Station.serializer(), s)).apply()
    }

    fun removeRecent(uuid: String) {
        _recents.value = _recents.value.filterNot { it.uuid == uuid }
        write(KEY_RECENTS, stationList, _recents.value)
    }

    fun clearRecents() {
        _recents.value = emptyList()
        write(KEY_RECENTS, stationList, emptyList())
    }

    val lastStation: Station? get() = read(KEY_LAST, Station.serializer())

    // MARK: zoeken

    fun addSearch(q: String) {
        val t = q.trim()
        if (t.length < 2) return
        _searches.value = (listOf(t) + _searches.value.filterNot { it.equals(t, ignoreCase = true) }).take(MAX_SEARCHES)
        write(KEY_SEARCHES, ListSerializer(String.serializer()), _searches.value)
    }

    fun clearSearches() {
        _searches.value = emptyList()
        write(KEY_SEARCHES, ListSerializer(String.serializer()), emptyList())
    }

    // MARK: land en regio

    fun setCountry(c: Country) {
        val sel = SelectedCountry(c.code.uppercase(), c.name)
        if (_country.value?.code != sel.code) {
            // ander land: de lokale regio hoort bij het oude land
            _region.value = null
            prefs.edit().remove(KEY_REGION).apply()
        }
        _country.value = sel
        write(KEY_COUNTRY, SelectedCountry.serializer(), sel)
    }

    fun setLocalRegion(name: String?) {
        _region.value = name
        prefs.edit().apply { if (name == null) remove(KEY_REGION) else putString(KEY_REGION, name) }.apply()
    }

    // MARK: instellingen

    fun updateSettings(transform: (Settings) -> Settings) {
        _settings.value = transform(_settings.value)
        // commit: de taal moet al op schijf staan als de activity zich direct daarna opnieuw maakt
        prefs.edit().putString(KEY_SETTINGS, json.encodeToString(Settings.serializer(), _settings.value)).commit()
    }

    // MARK: podcasts (SPEC §8)

    fun isFollowing(podcastId: String): Boolean = _podcasts.value.any { it.id == podcastId }

    fun toggleFollow(p: Podcast) {
        val list = _podcasts.value
        _podcasts.value = if (list.any { it.id == p.id }) list.filterNot { it.id == p.id } else listOf(p) + list
        write(KEY_PODCASTS, podcastList, _podcasts.value)
    }

    /** Gevolgde podcast bijwerken met verse gegevens (art, aantal, feed), volgorde blijft */
    fun refreshFollowed(p: Podcast) {
        val list = _podcasts.value
        if (list.none { it.id == p.id }) return
        _podcasts.value = list.map { if (it.id == p.id) p else it }
        write(KEY_PODCASTS, podcastList, _podcasts.value)
    }

    fun progressOf(episodeId: String): EpisodeProgress? = _progress.value[episodeId]

    /**
     * Positie bewaren (elke 10 s en bij pauze). ≥ 95% = beluisterd. Max [MAX_PROGRESS] posities: de oudste gaan eruit.
     */
    fun saveProgress(episode: Episode, positionMs: Long, durationMs: Long) {
        if (episode.id.isEmpty()) return
        val dur = if (durationMs > 0) durationMs else episode.durationMs
        val finished = dur > 0 && positionMs >= dur * 0.95
        // omschrijving inkorten: de lijst blijft klein in SharedPreferences
        val slim = episode.copy(description = "", shortDescription = episode.summary.take(300))
        val entry = EpisodeProgress(
            episodeId = episode.id,
            positionMs = if (finished) 0L else positionMs.coerceAtLeast(0L),
            durationMs = dur,
            finished = finished,
            updatedAt = System.currentTimeMillis(),
            episode = slim,
        )
        putProgress(entry)
    }

    fun markFinished(episode: Episode, finished: Boolean) {
        val old = _progress.value[episode.id]
        val slim = episode.copy(description = "", shortDescription = episode.summary.take(300))
        putProgress(
            EpisodeProgress(episode.id, 0L, old?.durationMs ?: episode.durationMs, finished, System.currentTimeMillis(), slim)
        )
    }

    private fun putProgress(entry: EpisodeProgress) {
        val map = LinkedHashMap(_progress.value)
        map[entry.episodeId] = entry
        val trimmed = if (map.size > MAX_PROGRESS) {
            map.values.sortedByDescending { it.updatedAt }.take(MAX_PROGRESS).associateBy { it.episodeId }
        } else map
        _progress.value = trimmed
        write(KEY_PROGRESS, progressList, trimmed.values.toList())
    }

    /** Half beluisterde afleveringen, laatst beluisterd eerst ("Verder luisteren") */
    fun continueListening(map: Map<String, EpisodeProgress> = _progress.value, limit: Int = 20): List<Episode> =
        map.values.filter { it.inProgress && it.episode != null }
            .sortedByDescending { it.updatedAt }
            .take(limit)
            .mapNotNull { it.episode }

    /** Laatste aflevering van elke gevolgde podcast, nieuwste eerst ("Nieuwe afleveringen") */
    suspend fun newEpisodes(cc: String, podcasts: List<Podcast> = _podcasts.value): List<Episode> =
        kotlinx.coroutines.coroutineScope {
            podcasts.take(30).map { p -> async { PodcastApi.latestEpisode(p, cc) } }.awaitAll()
        }.filterNotNull().sortedByDescending { it.releaseDate }

    fun setPlaybackSpeed(speed: Float) {
        _speed.value = speed.coerceIn(0.8f, 2f)
        prefs.edit().putFloat(KEY_SPEED, _speed.value).apply()
    }
}

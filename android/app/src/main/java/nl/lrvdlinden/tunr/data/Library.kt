package nl.lrvdlinden.tunr.data

import android.content.Context
import android.content.SharedPreferences
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

    private const val MAX_RECENTS = 30
    private const val MAX_SEARCHES = 8

    private lateinit var prefs: SharedPreferences
    private val json get() = Http.json
    private val stationList = ListSerializer(Station.serializer())

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
}

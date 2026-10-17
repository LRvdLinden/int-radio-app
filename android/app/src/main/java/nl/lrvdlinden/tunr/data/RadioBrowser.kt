package nl.lrvdlinden.tunr.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import nl.lrvdlinden.tunr.Brand
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/** Gedeelde HTTP-client met onze User-Agent op elk verzoek. */
object Http {
    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
            .addInterceptor { chain ->
                chain.proceed(chain.request().newBuilder().header("User-Agent", Brand.userAgent).build())
            }
            .build()
    }

    /** Tolerant: onbekende velden, null in niet-null velden (→ standaard) en rommelige JSON. */
    val json = Json { ignoreUnknownKeys = true; coerceInputValues = true; isLenient = true }

    fun getString(url: HttpUrl): String {
        val req = Request.Builder().url(url).header("Accept", "application/json").build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("HTTP ${resp.code}")
            return resp.body?.string() ?: throw IOException("Lege respons")
        }
    }
}

/**
 * Radio Browser (community-database, geen sleutel). Kiest een willekeurige server uit de lijst en houdt die voor de
 * sessie; bij een fout de volgende. Antwoorden in geheugen + op schijf (landen 7 dagen, lijsten 30 minuten).
 */
object RadioBrowser {
    private const val DISCOVERY = "https://all.api.radio-browser.info/json/servers"
    private val FALLBACK = listOf("de1.api.radio-browser.info", "de2.api.radio-browser.info", "fi1.api.radio-browser.info")

    const val TTL_COUNTRIES = 7L * 24 * 60 * 60 * 1000
    const val TTL_LIST = 30L * 60 * 1000
    const val TTL_SHORT = 5L * 60 * 1000

    private const val PAGE = 60

    private var cacheDir: File? = null
    private val memory = ConcurrentHashMap<String, Pair<Long, String>>()
    private val serverLock = Mutex()
    private var servers: List<String> = emptyList()
    private var current = 0

    fun init(context: Context) {
        cacheDir = File(context.cacheDir, "radiobrowser").apply { mkdirs() }
    }

    // MARK: servers

    private suspend fun serverList(): List<String> = serverLock.withLock {
        if (servers.isNotEmpty()) return servers
        val found = runCatching {
            val body = Http.getString(DISCOVERY.toHttpUrl())
            Http.json.decodeFromString(ListSerializer(ServerInfo.serializer()), body)
                .map { it.name.trim() }.filter { it.isNotEmpty() }.distinct()
        }.getOrDefault(emptyList())
        servers = (found.ifEmpty { FALLBACK }).shuffled()
        current = 0
        servers
    }

    /** Doet het verzoek op de huidige server; bij een fout de volgende (max 3 pogingen). */
    private suspend fun fetch(path: String, params: List<Pair<String, String>>): String = withContext(Dispatchers.IO) {
        val list = serverList()
        var lastError: Exception = IOException("Geen server")
        val attempts = minOf(3, maxOf(list.size, 1))
        repeat(attempts) {
            val host = list[(current) % list.size]
            try {
                val b = HttpUrl.Builder().scheme("https").host(host)
                path.trim('/').split('/').filter { it.isNotEmpty() }.forEach { b.addPathSegment(it) }
                params.forEach { (k, v) -> b.addQueryParameter(k, v) }
                return@withContext Http.getString(b.build())
            } catch (e: Exception) {
                lastError = e
                current = (current + 1) % list.size
            }
        }
        throw lastError
    }

    // MARK: cache

    private fun cacheKey(path: String, params: List<Pair<String, String>>): String {
        val raw = path + "?" + params.joinToString("&") { "${it.first}=${it.second}" }
        val md = MessageDigest.getInstance("SHA-1").digest(raw.toByteArray())
        return md.joinToString("") { "%02x".format(it) }
    }

    private suspend fun cached(path: String, params: List<Pair<String, String>>, ttl: Long, force: Boolean = false): String {
        val key = cacheKey(path, params)
        val now = System.currentTimeMillis()
        if (!force) {
            memory[key]?.let { (t, body) -> if (now - t < ttl) return body }
            val disk = withContext(Dispatchers.IO) {
                cacheDir?.let { File(it, "$key.json") }?.takeIf { it.exists() && now - it.lastModified() < ttl }
                    ?.let { runCatching { it.readText() }.getOrNull() }
            }
            if (disk != null) { memory[key] = now to disk; return disk }
        }
        return try {
            val body = fetch(path, params)
            memory[key] = now to body
            withContext(Dispatchers.IO) { runCatching { cacheDir?.let { File(it, "$key.json").writeText(body) } } }
            body
        } catch (e: Exception) {
            // Offline: dan maar een verlopen kopie (beter dan niets)
            val stale = memory[key]?.second ?: withContext(Dispatchers.IO) {
                cacheDir?.let { File(it, "$key.json") }?.takeIf { it.exists() }?.let { runCatching { it.readText() }.getOrNull() }
            }
            stale ?: throw e
        }
    }

    private suspend fun <T> list(
        path: String, params: List<Pair<String, String>>, ttl: Long, ser: KSerializer<T>, force: Boolean = false,
    ): List<T> {
        val body = cached(path, params, ttl, force)
        return withContext(Dispatchers.Default) { Http.json.decodeFromString(ListSerializer(ser), body) }
    }

    private suspend fun stations(params: List<Pair<String, String>>, ttl: Long = TTL_LIST, force: Boolean = false): List<Station> =
        list("json/stations/search", params, ttl, Station.serializer(), force).cleaned()

    private fun base(order: String = "clickcount", limit: Int = PAGE, offset: Int = 0) = listOf(
        "hidebroken" to "true", "order" to order, "reverse" to "true", "limit" to "$limit", "offset" to "$offset",
    )

    /** Maakt de geheugen- en schijfcache leeg (niet de landenlijst nodig, maar eenvoudig: alles). */
    fun clearCache() {
        memory.clear()
        cacheDir?.listFiles()?.forEach { it.delete() }
    }

    // MARK: endpoints

    /** Alle landen met minstens één zender, gesorteerd op gelokaliseerde naam */
    suspend fun countries(): List<Country> =
        list("json/countries", listOf("hidebroken" to "true", "order" to "name"), TTL_COUNTRIES, Country.serializer())
            .filter { it.stationCount >= 1 && it.code.trim().length == 2 }
            .distinctBy { it.code.uppercase() }
            .sortedWith(compareBy(java.text.Collator.getInstance()) { it.localizedName })

    suspend fun popular(cc: String, limit: Int = PAGE, force: Boolean = false) =
        stations(listOf("countrycode" to cc) + base("clickcount", limit), force = force)

    suspend fun trending(cc: String, limit: Int = PAGE, force: Boolean = false) =
        stations(listOf("countrycode" to cc) + base("clicktrend", limit), force = force)

    /** Zenders met een genre; [cc] null = wereldwijd */
    suspend fun byTag(tag: String, cc: String?, limit: Int = PAGE) =
        stations(listOfNotNull(cc?.let { "countrycode" to it }) + listOf("tag" to tag, "tagExact" to "true") + base("clickcount", limit))

    /** Zoeken op naam; [cc] null = wereldwijd. Korte cache (zoekopdrachten veranderen snel). */
    suspend fun search(query: String, cc: String?, limit: Int = PAGE) =
        stations(listOfNotNull(cc?.let { "countrycode" to it }) + listOf("name" to query.trim()) + base("clickcount", limit), ttl = TTL_SHORT)

    /** Zenders op uuid (favorieten verversen) */
    suspend fun byUuids(uuids: List<String>): List<Station> {
        if (uuids.isEmpty()) return emptyList()
        return uuids.chunked(50).flatMap { chunk ->
            list("json/stations/byuuid", listOf("uuids" to chunk.joinToString(",")), TTL_SHORT, Station.serializer())
        }.distinctBy { it.uuid }
    }

    /** Klik tellen bij afspelen (fire-and-forget, geen cache) */
    suspend fun click(uuid: String) {
        if (uuid.isEmpty()) return
        runCatching { fetch("json/url/$uuid", emptyList()) }
    }

    /** Provincies/staten van een land; [countryName] = het Engelse `name` uit /json/countries */
    suspend fun states(countryName: String): List<RegionState> =
        list("json/states/$countryName", listOf("hidebroken" to "true", "order" to "stationcount", "reverse" to "true"),
            TTL_COUNTRIES, RegionState.serializer())
            .filter { it.name.isNotBlank() && it.stationCount > 0 }
            .distinctBy { it.name.trim().lowercase() }

    suspend fun byState(cc: String, state: String, limit: Int = 100) =
        stations(listOf("countrycode" to cc, "state" to state, "stateExact" to "true") + base("clickcount", limit))

    suspend fun languages(): List<LanguageInfo> =
        list("json/languages", listOf("hidebroken" to "true", "order" to "stationcount", "reverse" to "true", "limit" to "60"),
            TTL_COUNTRIES, LanguageInfo.serializer()).filter { it.name.isNotBlank() && it.stationCount > 0 }

    /** Zenders in een taal (wereldwijd) */
    suspend fun byLanguage(language: String, limit: Int = PAGE) =
        stations(listOf("language" to language, "languageExact" to "true") + base("clickcount", limit))

    /** Top 100 wereldwijd */
    suspend fun top100() = stations(base("clickcount", 100))

    /** Zenders met geo-info voor de kaart: land (500) of wereld (1500) */
    suspend fun geoStations(cc: String?): List<Station> {
        val limit = if (cc == null) 1500 else 500
        return stations(listOfNotNull(cc?.let { "countrycode" to it }) + listOf("has_geo_info" to "true") + base("clickcount", limit))
            .filter { it.hasGeo }
    }

    /** Zenders binnen [distanceMeters] van een punt (zoeken op de kaart, SPEC §9), top 300 op populariteit */
    suspend fun nearStations(lat: Double, lon: Double, distanceMeters: Int): List<Station> {
        val params = listOf(
            "geo_lat" to String.format(java.util.Locale.US, "%.4f", lat),
            "geo_long" to String.format(java.util.Locale.US, "%.4f", lon),
            "geo_distance" to "$distanceMeters",
            "has_geo_info" to "true",
        ) + base("clickcount", 300)
        return stations(params).filter { it.hasGeo }
    }

    /** Willekeurige zender wereldwijd (met geo, zodat de kaart erheen kan vliegen) */
    suspend fun randomStation(): Station? {
        val params = listOf("has_geo_info" to "true", "hidebroken" to "true", "order" to "random", "limit" to "20")
        val body = fetch("json/stations/search", params)
        val list = withContext(Dispatchers.Default) {
            Http.json.decodeFromString(ListSerializer(Station.serializer()), body)
        }.cleaned().filter { it.hasGeo && it.lastCheckOk == 1 }
        return list.maxByOrNull { it.clickCount } ?: list.firstOrNull()
    }

    /** De genres met de meeste zenders in een land (uit de tags van de top 500), alleen uit de vaste chiplijst */
    suspend fun topGenres(cc: String, count: Int = 2): List<String> {
        val top = stations(listOf("countrycode" to cc) + base("clickcount", 500), ttl = TTL_COUNTRIES / 7)
        val counts = HashMap<String, Int>()
        top.forEach { s ->
            s.tags.split(',').map { it.trim().lowercase() }.distinct().forEach { t ->
                if (t in GENRE_TAGS) counts[t] = (counts[t] ?: 0) + 1
            }
        }
        val ranked = counts.entries.sortedByDescending { it.value }.map { it.key }
        return (ranked + listOf("pop", "news")).distinct().take(count)
    }
}

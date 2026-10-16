package nl.lrvdlinden.tunr.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * Podcasts (SPEC §8), sleutelloos via Apple:
 * - toplijst per land: rss.applemarketingtools.com (v2 JSON), terugval `us`;
 * - toplijst per genre: oude iTunes-RSS als JSON (`feed.entry[]`);
 * - zoeken: itunes.apple.com/search (media=podcast);
 * - podcast + afleveringen: itunes.apple.com/lookup (entity=podcastEpisode, limit 100).
 * Antwoorden in geheugen + op schijf (toplijsten 6 uur, afleveringen 30 min). JSON tolerant via JsonElement.
 */
object PodcastApi {
    const val TTL_CHARTS = 6L * 60 * 60 * 1000
    const val TTL_EPISODES = 30L * 60 * 1000
    const val TTL_SEARCH = 10L * 60 * 1000

    private var cacheDir: File? = null
    private val memory = ConcurrentHashMap<String, Pair<Long, String>>()

    fun init(context: Context) {
        if (cacheDir == null) cacheDir = File(context.cacheDir, "podcasts").apply { mkdirs() }
    }

    // MARK: cache

    private fun key(url: HttpUrl): String =
        MessageDigest.getInstance("SHA-1").digest(url.toString().toByteArray()).joinToString("") { "%02x".format(it) }

    private suspend fun cached(url: HttpUrl, ttl: Long, force: Boolean = false): String = withContext<String>(Dispatchers.IO) {
        val k = key(url)
        val now = System.currentTimeMillis()
        val file = cacheDir?.let { File(it, "$k.json") }
        if (!force) {
            memory[k]?.let { (t, body) -> if (now - t < ttl) return@withContext body }
            val disk = file?.takeIf { it.exists() && now - it.lastModified() < ttl }?.let { runCatching { it.readText() }.getOrNull() }
            if (disk != null) { memory[k] = now to disk; return@withContext disk }
        }
        try {
            val body = Http.getString(url)
            memory[k] = now to body
            runCatching { file?.writeText(body) }
            body
        } catch (e: Exception) {
            // Offline: een verlopen kopie is beter dan niets
            memory[k]?.second ?: file?.takeIf { it.exists() }?.let { runCatching { it.readText() }.getOrNull() } ?: throw e
        }
    }

    private fun parse(body: String): JsonElement = Http.json.parseToJsonElement(body)

    fun clearCache() {
        memory.clear()
        cacheDir?.listFiles()?.forEach { it.delete() }
    }

    // MARK: endpoints

    /** Top 50 podcasts van een land (valt terug op `us`) */
    suspend fun topPodcasts(cc: String, force: Boolean = false): List<Podcast> {
        val code = cc.trim().lowercase(Locale.ROOT).ifEmpty { "us" }
        if (code == "us") return chart("us", force)
        val list = runCatching { chart(code, force) }.getOrDefault(emptyList())
        return list.ifEmpty { chart("us", force) }
    }

    private suspend fun chart(cc: String, force: Boolean): List<Podcast> {
        val url = "https://rss.applemarketingtools.com/api/v2/$cc/podcasts/top/50/podcasts.json".toHttpUrl()
        val body = cached(url, TTL_CHARTS, force)
        return withContext<List<Podcast>>(Dispatchers.Default) {
            val results = parse(body).obj("feed")?.arr("results") ?: return@withContext emptyList()
            results.mapNotNull { el ->
                val o = el as? JsonObject ?: return@mapNotNull null
                val id = o.str("id") ?: return@mapNotNull null
                val genre = o.arr("genres")?.firstOrNull { (it as? JsonObject)?.str("name")?.equals("Podcasts", true) == false }
                    ?.let { (it as JsonObject).str("name") }.orEmpty()
                Podcast(
                    id = id,
                    name = o.str("name").orEmpty(),
                    artist = o.str("artistName").orEmpty(),
                    artwork = art600(o.str("artworkUrl100")),
                    genre = genre,
                )
            }.distinctBy { it.id }
        }
    }

    /** Top 50 per genre (oude iTunes-RSS), terugval `us` */
    suspend fun topByGenre(cc: String, genreId: Int): List<Podcast> {
        val code = cc.trim().lowercase(Locale.ROOT).ifEmpty { "us" }
        if (code == "us") return genreChart("us", genreId)
        val list = runCatching { genreChart(code, genreId) }.getOrDefault(emptyList())
        return list.ifEmpty { genreChart("us", genreId) }
    }

    private suspend fun genreChart(cc: String, genreId: Int): List<Podcast> {
        val url = "https://itunes.apple.com/$cc/rss/toppodcasts/limit=50/genre=$genreId/json".toHttpUrl()
        val body = cached(url, TTL_CHARTS)
        return withContext<List<Podcast>>(Dispatchers.Default) {
            val feed = parse(body).obj("feed") ?: return@withContext emptyList()
            // `entry` is een lijst, of één object als er maar één podcast is
            val entries: List<JsonElement> = when (val e = feed["entry"]) {
                is JsonArray -> e
                is JsonObject -> listOf(e)
                else -> emptyList()
            }
            entries.mapNotNull { el ->
                val o = el as? JsonObject ?: return@mapNotNull null
                val id = o.obj("id")?.obj("attributes")?.str("im:id") ?: return@mapNotNull null
                val images = o.arr("im:image").orEmpty()
                val image = (images.getOrNull(2) ?: images.lastOrNull()) as? JsonObject
                Podcast(
                    id = id,
                    name = o.obj("im:name")?.str("label").orEmpty(),
                    artist = o.obj("im:artist")?.str("label").orEmpty(),
                    artwork = art600(image?.str("label")),
                    genre = o.obj("category")?.obj("attributes")?.str("label").orEmpty(),
                )
            }.distinctBy { it.id }
        }
    }

    /** Zoeken in iTunes (media=podcast) */
    suspend fun search(term: String, cc: String): List<Podcast> {
        val q = term.trim()
        if (q.length < 2) return emptyList()
        val url = "https://itunes.apple.com/search".toHttpUrl().newBuilder()
            .addQueryParameter("media", "podcast")
            .addQueryParameter("entity", "podcast")
            .addQueryParameter("term", q)
            .addQueryParameter("country", cc.trim().lowercase(Locale.ROOT).ifEmpty { "us" })
            .addQueryParameter("limit", "50")
            .build()
        val body = cached(url, TTL_SEARCH)
        return withContext<List<Podcast>>(Dispatchers.Default) {
            parse(body).arr("results").orEmpty().mapNotNull { (it as? JsonObject)?.toPodcast() }.distinctBy { it.id }
        }
    }

    /** Podcast + afleveringen (nieuwste eerst). Null als iTunes de podcast niet kent. */
    suspend fun lookup(podcastId: String, cc: String, force: Boolean = false): Pair<Podcast, List<Episode>>? {
        if (podcastId.isBlank()) return null
        val url = "https://itunes.apple.com/lookup".toHttpUrl().newBuilder()
            .addQueryParameter("id", podcastId)
            .addQueryParameter("entity", "podcastEpisode")
            .addQueryParameter("limit", "100")
            .addQueryParameter("country", cc.trim().lowercase(Locale.ROOT).ifEmpty { "us" })
            .build()
        val body = cached(url, TTL_EPISODES, force)
        return withContext<Pair<Podcast, List<Episode>>?>(Dispatchers.Default) {
            val results = parse(body).arr("results").orEmpty().mapNotNull { it as? JsonObject }
            val head = results.firstOrNull { it.str("wrapperType") != "podcastEpisode" } ?: return@withContext null
            val podcast = head.toPodcast() ?: return@withContext null
            val episodes = results.filter { it.str("wrapperType") == "podcastEpisode" }
                .mapNotNull { it.toEpisode(podcast) }
                .distinctBy { it.id }
                .sortedByDescending { it.releaseDate }
            podcast to episodes
        }.also { result -> result?.second?.let { EpisodeCache.putAll(it) } }
    }

    private val descriptions = ConcurrentHashMap<String, String>()

    /**
     * Beschrijving van de podcast uit de RSS-feed (iTunes Lookup geeft die niet): `<itunes:summary>` of `<description>`
     * van het kanaal, vóór het eerste `<item>`. Leest hooguit 256 kB. Null als het niet lukt.
     */
    suspend fun feedDescription(feedUrl: String): String? {
        val url = feedUrl.trim()
        if (!url.startsWith("http")) return null
        descriptions[url]?.let { return it.ifEmpty { null } }
        val found = withContext<String?>(Dispatchers.IO) {
            runCatching {
                val req = okhttp3.Request.Builder().url(url).header("Accept", "application/rss+xml, application/xml, text/xml").build()
                Http.client.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) return@use null
                    val source = resp.body?.source() ?: return@use null
                    source.request(256L * 1024)
                    val head = source.buffer.snapshot().utf8().let { val i = it.indexOf("<item"); if (i > 0) it.substring(0, i) else it }
                    val tags = listOf("itunes:summary", "description", "itunes:subtitle")
                    tags.firstNotNullOfOrNull { tag ->
                        Regex("<$tag[^>]*>([\\s\\S]*?)</$tag>", RegexOption.IGNORE_CASE).find(head)?.groupValues?.get(1)
                            ?.replace("<![CDATA[", "")?.replace("]]>", "")?.let { plainText(it) }?.takeIf { it.isNotBlank() }
                    }
                }
            }.getOrNull()
        }
        descriptions[url] = found.orEmpty()
        return found
    }

    /** Nieuwste aflevering van een podcast (Ontdek → Nieuwe afleveringen) */
    suspend fun latestEpisode(podcast: Podcast, cc: String): Episode? =
        runCatching { lookup(podcast.id, cc)?.second?.firstOrNull() }.getOrNull()

    // MARK: JSON → modellen

    private fun JsonObject.toPodcast(): Podcast? {
        val id = str("collectionId") ?: str("trackId") ?: return null
        return Podcast(
            id = id,
            name = str("collectionName") ?: str("trackName").orEmpty(),
            artist = str("artistName").orEmpty(),
            artwork = art600(str("artworkUrl600") ?: str("artworkUrl100") ?: str("artworkUrl60")),
            feedUrl = str("feedUrl").orEmpty(),
            genre = str("primaryGenreName").orEmpty().takeIf { !it.equals("Podcasts", true) }.orEmpty(),
            trackCount = str("trackCount")?.toIntOrNull() ?: 0,
            releaseDate = str("releaseDate").orEmpty(),
        )
    }

    private fun JsonObject.toEpisode(p: Podcast): Episode? {
        val id = str("trackId") ?: return null
        val url = str("episodeUrl") ?: str("previewUrl") ?: return null
        if (!url.startsWith("http")) return null
        return Episode(
            id = id,
            podcastId = p.id,
            podcastName = p.displayName,
            podcastArtwork = p.artwork,
            title = str("trackName").orEmpty(),
            description = str("description").orEmpty(),
            shortDescription = str("shortDescription").orEmpty(),
            releaseDate = str("releaseDate").orEmpty(),
            durationMs = str("trackTimeMillis")?.toDoubleOrNull()?.toLong() ?: 0L,
            url = url,
            artwork = art600(str("artworkUrl600") ?: str("artworkUrl160")),
            fileExtension = str("episodeFileExtension").orEmpty(),
        )
    }
}

/** Afleveringen die de app ooit heeft gezien, op id (de dienst vertaalt een mediaId "ep:<id>" zo terug). */
object EpisodeCache {
    private val map = ConcurrentHashMap<String, Episode>()
    fun put(e: Episode) { if (e.id.isNotEmpty()) map[e.id] = e }
    fun putAll(list: List<Episode>) = list.forEach { put(it) }
    operator fun get(id: String?): Episode? = id?.let { map[it] }
}

// MARK: JSON-hulpjes (tolerant: alles wat ontbreekt of een ander type heeft → null)

internal fun JsonElement?.obj(key: String): JsonObject? = ((this as? JsonObject)?.get(key)) as? JsonObject
internal fun JsonElement?.arr(key: String): JsonArray? = ((this as? JsonObject)?.get(key)) as? JsonArray
internal fun JsonElement?.str(key: String): String? =
    (((this as? JsonObject)?.get(key)) as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() && it != "null" }

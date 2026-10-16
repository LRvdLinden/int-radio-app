package nl.lrvdlinden.tunr.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.util.concurrent.ConcurrentHashMap

/** Wat er nu speelt, uit de ICY-titel ("Artiest - Titel"). */
data class NowPlaying(val artist: String?, val title: String) {
    /** "Artiest — Titel" of alleen de titel */
    val line: String get() = if (artist.isNullOrBlank()) title else "$artist — $title"

    companion object {
        /** Maakt van een ruwe StreamTitle iets bruikbaars; null als het leeg of reclame-achtig is. */
        fun parse(raw: String?): NowPlaying? {
            val t = raw?.trim()?.trim('\'', '"')?.trim().orEmpty()
            if (t.isEmpty() || t == "-" || t.length < 2) return null
            val i = t.indexOf(" - ")
            return if (i > 0) {
                val artist = t.substring(0, i).trim()
                val title = t.substring(i + 3).trim()
                if (title.isEmpty()) NowPlaying(null, artist) else NowPlaying(artist, title)
            } else NowPlaying(null, t)
        }
    }
}

/** Albumhoes via de iTunes Search API (zonder sleutel). Cache per titel; geen resultaat → null (zenderlogo). */
object Artwork {
    @Serializable private data class Result(val artworkUrl100: String? = null)
    @Serializable private data class Response(val resultCount: Int = 0, val results: List<Result> = emptyList())

    private val cache = ConcurrentHashMap<String, String>()
    private const val NONE = ""

    suspend fun lookup(np: NowPlaying): String? {
        if (np.artist.isNullOrBlank()) return null // alleen een titel: vaak de zendernaam of reclame
        val term = "${np.artist} ${np.title}".trim()
        val key = term.lowercase()
        cache[key]?.let { return it.ifEmpty { null } }
        val found = withContext(Dispatchers.IO) {
            runCatching {
                val url = "https://itunes.apple.com/search".toHttpUrl().newBuilder()
                    .addQueryParameter("term", term)
                    .addQueryParameter("entity", "song")
                    .addQueryParameter("limit", "1")
                    .build()
                val body = Http.getString(url)
                Http.json.decodeFromString(Response.serializer(), body).results.firstOrNull()?.artworkUrl100
                    ?.replace("100x100bb", "600x600bb")
            }.getOrNull()
        }
        cache[key] = found ?: NONE
        return found
    }
}

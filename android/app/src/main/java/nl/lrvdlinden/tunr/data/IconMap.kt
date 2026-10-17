package nl.lrvdlinden.tunr.data

import android.content.Context
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import okhttp3.Request
import java.io.File
import java.text.Normalizer
import java.util.concurrent.ConcurrentHashMap

/**
 * App Store-iconen per land: `https://tunr.online/assets/data/icons/<CC>.json` (zenders zonder land: `_world.json`),
 * gemaakt door tools/make_station_icons.py (workflow Icons). Inhoud: `{"u": {stationuuid: url}, "n": {naamsleutel: url}}`.
 * Per land pas opgehaald als het nodig is, bewaard in het geheugen en in cacheDir/icons (7 dagen geldig; zonder
 * netwerk een oudere kopie). [version] telt op als een tabel klaar is (of mislukte), zodat zendercovers opnieuw kiezen.
 */
object IconMap {
    private const val BASE = "https://tunr.online/assets/data/icons/"
    private const val TTL = 7L * 24 * 60 * 60 * 1000
    private const val RETRY = 10L * 60 * 1000

    private val tables = ConcurrentHashMap<String, Map<String, Map<String, String>>>()
    private val retryAfter = ConcurrentHashMap<String, Long>()
    private val loading = ConcurrentHashMap<String, Deferred<Unit>>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var dir: File? = null

    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version.asStateFlow()

    private val serializer = MapSerializer(String.serializer(), MapSerializer(String.serializer(), String.serializer()))

    fun init(context: Context) {
        dir = File(context.cacheDir, "icons").apply { mkdirs() }
    }

    /**
     * Naamsleutel, gelijk aan `norm_key` in tools/make_station_icons.py (en Apple/web): NFKD, accenten weg,
     * kleine letters, alleen letters en decimale cijfers.
     */
    fun key(name: String): String {
        val folded = Normalizer.normalize(name, Normalizer.Form.NFKD)
            .filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }
            .lowercase()
        val sb = StringBuilder()
        var i = 0
        while (i < folded.length) {
            val cp = folded.codePointAt(i)
            if (Character.isLetter(cp) || Character.getType(cp) == Character.DECIMAL_DIGIT_NUMBER.toInt()) sb.appendCodePoint(cp)
            i += Character.charCount(cp)
        }
        return sb.toString()
    }

    /** Bestandsnaam van de tabel voor deze zender ("NL" of "_world") */
    fun file(s: Station): String {
        val cc = s.countryCode.trim().uppercase()
        return if (cc.length == 2 && cc.all { it in 'A'..'Z' }) cc else "_world"
    }

    /** Icoon-URL als de tabel van het land al geladen is (zonder netwerk) */
    fun cached(s: Station): String? {
        val t = tables[file(s)] ?: return null
        val url = t["u"]?.get(s.uuid) ?: t["n"]?.get(key(s.name))
        return url?.takeIf { it.startsWith("https://") }
    }

    /** Weten we zeker dat er geen App Store-icoon is? (tabel geladen zonder deze zender, of laden net mislukt) */
    fun knownAbsent(s: Station): Boolean {
        val f = file(s)
        if (tables.containsKey(f)) return cached(s) == null
        return (retryAfter[f] ?: 0L) > System.currentTimeMillis()
    }

    /** Tabel van het land op de achtergrond ophalen (geen effect als hij er al is) */
    fun prefetch(s: Station) {
        val f = file(s)
        if (ready(f)) return
        scope.launch { ensure(f) }
    }

    /** Wacht tot de tabellen voor deze zenders er zijn (of mislukten) */
    suspend fun ensureFor(stations: List<Station>) {
        stations.map { file(it) }.distinct().forEach { ensure(it) }
    }

    /** Is de tabel voor deze zender geladen (of net mislukt)? Dan kan er gekozen worden. */
    fun isReady(s: Station): Boolean = ready(file(s))

    private fun ready(f: String) = tables.containsKey(f) || (retryAfter[f] ?: 0L) > System.currentTimeMillis()

    /** Tabel laden (één keer tegelijk per land; loopt door in [scope] ook als de aanroeper stopt) */
    suspend fun ensure(f: String) {
        if (ready(f)) return
        loading.computeIfAbsent(f) {
            scope.async {
                try {
                    val t = runCatching { load(f) }.getOrNull()
                    if (t != null) {
                        tables[f] = t
                    } else {
                        retryAfter[f] = System.currentTimeMillis() + RETRY
                    }
                    _version.value = _version.value + 1
                } finally {
                    loading.remove(f)
                }
                Unit
            }
        }.await()
    }

    private fun decode(text: String): Map<String, Map<String, String>>? =
        runCatching { Http.json.decodeFromString(serializer, text) }.getOrNull()

    private fun load(f: String): Map<String, Map<String, String>>? {
        val disk = dir?.let { File(it, "$f.json") }
        var table: Map<String, Map<String, String>>? = null
        var fresh = false
        if (disk != null && disk.exists()) {
            table = runCatching { decode(disk.readText()) }.getOrNull()
            fresh = table != null && System.currentTimeMillis() - disk.lastModified() < TTL
        }
        if (fresh) return table
        val req = Request.Builder().url("$BASE$f.json").header("Accept", "application/json").build()
        val result: Pair<Int, String?>? = runCatching {
            Http.client.newCall(req).execute().use { resp -> Pair(resp.code, if (resp.isSuccessful) resp.body?.string() else null) }
        }.getOrNull()
        if (result != null) {
            val (code, text) = result
            val net = if (code in 200..299 && text != null) decode(text) else null
            if (net != null) {
                table = net
                runCatching { disk?.writeText(text.orEmpty()) }
            } else if (code == 404) {
                // geen tabel voor dit land (nog geen iconen gevonden): leeg, alleen deze sessie
                table = emptyMap()
            }
        }
        return table
    }
}

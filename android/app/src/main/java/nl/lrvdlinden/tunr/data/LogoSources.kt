package nl.lrvdlinden.tunr.data

import java.net.URI
import java.net.URLEncoder
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

/**
 * Waar een zenderlogo vandaan kan komen, in volgorde (SPEC §1, zelfde als Apple en de webspeler):
 * 1. het app-icoon uit de App Store, uit de vaste tabel van tunr.online ([IconMap]);
 * 2. Google-favicondienst op het domein van de homepage (`sz=256`), alleen vanaf [MIN_SERVICE_PX] (96 px: dan is
 *    het meestal het apple-touch-icon van de site);
 * 3. `favicon` uit Radio Browser (http → eerst https, daarna het origineel);
 * 4. DuckDuckGo-favicondienst (`ip3/<host>.ico`), vanaf [MIN_PX];
 * 5. (geen URL) het monogram/verloop van StationArt.
 * De eerste bron van minstens [GOOD_PX] (96 px) wint; kleinere logo's ([markTiny]) alleen als laatste redmiddel (het
 * grootste), Google onder 96 px en DuckDuckGo onder 48 px nooit ([acceptableSmall]). Mislukte URL's en het
 * gevonden logo per zender onthouden we in het geheugen (de afbeeldingen zelf staan in de schijfcache van Coil),
 * zodat er bij scrollen niet steeds opnieuw geprobeerd wordt.
 */
object LogoSources {
    const val MIN_PX = 48
    /** Google: kleiner dan dit is een gewoon favicon (of de globe van 16 px), niet het mooie icoon van de site */
    const val MIN_SERVICE_PX = 96
    /** Vanaf deze maat (grootste zijde, pixels) is een logo goed genoeg om te stoppen met zoeken */
    const val GOOD_PX = 96

    private val failed: MutableSet<String> = Collections.newSetFromMap(ConcurrentHashMap())
    /** te kleine logo's → hun maat (grootste zijde, pixels) */
    private val tiny = ConcurrentHashMap<String, Int>()
    private val resolved = ConcurrentHashMap<String, String>()

    /**
     * Alle bronnen in volgorde (ook de al mislukte; filter zelf met [isFailed]). Het App Store-icoon staat er alleen
     * in als de tabel van het land al geladen is (zie [IconMap.prefetch] / [IconMap.ensureFor]).
     */
    fun candidates(s: Station): List<String> {
        val out = mutableListOf<String>()
        IconMap.cached(s)?.let { out += it }
        val h = host(s.homepage)
        if (h != null) out += "https://www.google.com/s2/favicons?domain=" + URLEncoder.encode(h, "UTF-8") + "&sz=256"
        val fav = s.favicon.trim()
        when {
            fav.startsWith("http://", ignoreCase = true) -> {
                out += "https://" + fav.substring(7)
                out += fav
            }
            fav.startsWith("https://", ignoreCase = true) -> out += fav
        }
        if (h != null) out += "https://icons.duckduckgo.com/ip3/$h.ico"
        return out.distinct()
    }

    /** Kan deze zender een logo hebben? (zo niet: meteen het monogram) */
    fun mayHaveLogo(s: Station): Boolean = candidates(s).isNotEmpty() || !IconMap.knownAbsent(s)

    /** Domein van de homepage ("https://www.npo.nl/radio2" → "www.npo.nl"), of null */
    fun host(homepage: String): String? {
        var h = homepage.trim()
        if (h.isEmpty()) return null
        if (!h.contains("://")) h = "http://$h"
        val host = runCatching { URI(h).host }.getOrNull()?.lowercase() ?: return null
        return host.takeIf { it.matches(Regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$")) }
    }

    /** Google- of DuckDuckGo-favicondienst (dan geldt de minimummaat strikt) */
    fun isService(url: String): Boolean =
        url.startsWith("https://www.google.com/s2/favicons") || url.startsWith("https://icons.duckduckgo.com/ip3/")

    /** Minimale breedte in pixels voor deze bron (Google 96, de rest 48) */
    fun minPx(url: String): Int = if (url.startsWith("https://www.google.com/s2/favicons")) MIN_SERVICE_PX else MIN_PX

    fun isFailed(url: String) = url in failed
    fun markFailed(url: String) { failed += url }
    fun isTiny(url: String) = tiny.containsKey(url)
    fun markTiny(url: String, px: Int) { tiny[url] = px }

    /** Mag een logo van deze maat (grootste zijde) als terugval? Google nooit onder 96, DuckDuckGo niet onder 48 */
    fun acceptableSmall(url: String, px: Int): Boolean = when {
        px <= 0 -> false
        url.startsWith("https://www.google.com/s2/favicons") -> px >= MIN_SERVICE_PX
        url.startsWith("https://icons.duckduckgo.com/ip3/") -> px >= MIN_PX
        else -> true
    }

    /** Grootste bekende kleine logo van deze zender dat als terugval mag (of null) */
    fun bestTiny(s: Station): String? =
        candidates(s).filter { !isFailed(it) && tiny.containsKey(it) }.maxByOrNull { tiny[it] ?: 0 }

    /** Het logo dat voor deze zender werkte (of null) */
    fun resolved(uuid: String): String? = resolved[uuid]
    fun markResolved(uuid: String, url: String) { if (uuid.isNotEmpty()) resolved[uuid] = url }

    /** Beste gok voor plekken die zelf laden (mediasessie, Android Auto): gevonden logo, anders de eerste bron */
    fun best(s: Station): String? {
        resolved(s.uuid)?.let { return it }
        val all = candidates(s)
        return all.firstOrNull { !isFailed(it) && !isTiny(it) } ?: bestTiny(s) ?: all.firstOrNull { !isFailed(it) }
    }
}

package nl.lrvdlinden.tunr.data

import java.net.URI
import java.net.URLEncoder
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

/**
 * Waar een zenderlogo vandaan kan komen, in volgorde (SPEC §1, zelfde als Apple en de webspeler):
 * 1. `favicon` uit Radio Browser (http → eerst https, daarna het origineel);
 * 2. Google-favicondienst op het domein van de homepage (`sz=256`);
 * 3. DuckDuckGo-favicondienst (`ip3/<host>.ico`);
 * 4. (geen URL) het monogram/verloop van StationArt.
 * Resultaten van de diensten kleiner dan [MIN_PX] breed tellen als mislukt (Google geeft dan een globe van 16 px);
 * een klein favicon alleen als laatste redmiddel. Mislukte URL's en het gevonden logo per zender onthouden we in het
 * geheugen (de afbeeldingen zelf staan in de schijfcache van Coil), zodat er bij scrollen niet steeds opnieuw
 * geprobeerd wordt.
 */
object LogoSources {
    const val MIN_PX = 48

    private val failed: MutableSet<String> = Collections.newSetFromMap(ConcurrentHashMap())
    private val tiny: MutableSet<String> = Collections.newSetFromMap(ConcurrentHashMap())
    private val resolved = ConcurrentHashMap<String, String>()

    /** Alle bronnen in volgorde (ook de al mislukte; filter zelf met [isFailed]) */
    fun candidates(s: Station): List<String> {
        val out = mutableListOf<String>()
        val fav = s.favicon.trim()
        when {
            fav.startsWith("http://", ignoreCase = true) -> {
                out += "https://" + fav.substring(7)
                out += fav
            }
            fav.startsWith("https://", ignoreCase = true) -> out += fav
        }
        host(s.homepage)?.let { h ->
            out += "https://www.google.com/s2/favicons?domain=" + URLEncoder.encode(h, "UTF-8") + "&sz=256"
            out += "https://icons.duckduckgo.com/ip3/$h.ico"
        }
        return out
    }

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

    fun isFailed(url: String) = url in failed
    fun markFailed(url: String) { failed += url }
    fun isTiny(url: String) = url in tiny
    fun markTiny(url: String) { tiny += url }

    /** Het logo dat voor deze zender werkte (of null) */
    fun resolved(uuid: String): String? = resolved[uuid]
    fun markResolved(uuid: String, url: String) { if (uuid.isNotEmpty()) resolved[uuid] = url }

    /** Beste gok voor plekken die zelf laden (mediasessie, Android Auto): gevonden logo, anders de eerste bron */
    fun best(s: Station): String? =
        resolved(s.uuid) ?: candidates(s).firstOrNull { !isFailed(it) && !isTiny(it) } ?: candidates(s).firstOrNull { !isFailed(it) }
}

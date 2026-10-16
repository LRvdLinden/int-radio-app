package nl.lrvdlinden.tunr.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Locale

/** Zender uit Radio Browser (alleen de velden die we gebruiken, zie SPEC §2). */
@Serializable
data class Station(
    @SerialName("stationuuid") val uuid: String = "",
    val name: String = "",
    val url: String = "",
    @SerialName("url_resolved") val urlResolved: String = "",
    val homepage: String = "",
    val favicon: String = "",
    val tags: String = "",
    val country: String = "",
    @SerialName("countrycode") val countryCode: String = "",
    val state: String = "",
    val language: String = "",
    val codec: String = "",
    val bitrate: Int = 0,
    val hls: Int = 0,
    val votes: Int = 0,
    @SerialName("clickcount") val clickCount: Int = 0,
    @SerialName("clicktrend") val clickTrend: Int = 0,
    @SerialName("lastcheckok") val lastCheckOk: Int = 1,
    @SerialName("geo_lat") val geoLat: Double? = null,
    @SerialName("geo_long") val geoLong: Double? = null,
) {
    /** Getrimde naam (zonder rare spaties) */
    val displayName: String get() = name.trim().replace(Regex("\\s+"), " ").ifEmpty { "Radio" }

    /** Stream: url_resolved, anders url */
    val streamUrl: String get() = urlResolved.trim().ifEmpty { url.trim() }

    /** Genres als lijst (max 6, zonder lege of hele lange tags) */
    val tagList: List<String>
        get() = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() && it.length <= 24 }.distinct().take(6)

    val firstTag: String? get() = tagList.firstOrNull()

    /** "pop · rock · hits" */
    val genresLine: String get() = tagList.take(3).joinToString(" · ")

    val flag: String get() = flagEmoji(countryCode)

    val hasGeo: Boolean
        get() = geoLat != null && geoLong != null && !(geoLat == 0.0 && geoLong == 0.0) &&
            geoLat in -85.0..85.0 && geoLong in -180.0..180.0

    val isHls: Boolean get() = hls == 1 || streamUrl.contains(".m3u8", ignoreCase = true)

    /** "Provincie · Land 🇳🇱" */
    fun placeLine(): String {
        val land = localizedCountryName(countryCode, country)
        val parts = listOfNotNull(state.trim().takeIf { it.isNotEmpty() }, land.takeIf { it.isNotEmpty() })
        val text = parts.joinToString(" · ")
        return if (flag.isNotEmpty()) "$text $flag".trim() else text
    }
}

/** Land uit /json/countries */
@Serializable
data class Country(
    val name: String = "",
    @SerialName("iso_3166_1") val code: String = "",
    @SerialName("stationcount") val stationCount: Int = 0,
) {
    val flag: String get() = flagEmoji(code)
    val localizedName: String get() = localizedCountryName(code, name)
}

/** Provincie/staat uit /json/states */
@Serializable
data class RegionState(
    val name: String = "",
    val country: String = "",
    @SerialName("stationcount") val stationCount: Int = 0,
)

/** Taal uit /json/languages */
@Serializable
data class LanguageInfo(
    val name: String = "",
    @SerialName("iso_639") val iso: String? = null,
    @SerialName("stationcount") val stationCount: Int = 0,
) {
    /** Naam in de taal van de app als we de ISO-code kennen, anders de naam uit Radio Browser met hoofdletter */
    val localizedName: String
        get() {
            val code = iso?.trim().orEmpty()
            if (code.length in 2..3) {
                val n = Locale(code).getDisplayLanguage(Locale.getDefault())
                if (n.isNotBlank() && !n.equals(code, ignoreCase = true)) return n.replaceFirstChar { it.titlecase(Locale.getDefault()) }
            }
            return name.replaceFirstChar { it.titlecase(Locale.getDefault()) }
        }
}

/** Antwoord van /json/url/<uuid> (we gebruiken het alleen om te tellen) */
@Serializable
data class ClickResult(val ok: Boolean = false, val url: String = "")

/** Server uit https://all.api.radio-browser.info/json/servers */
@Serializable
data class ServerInfo(val name: String = "")

/** Vlag-emoji uit een ISO-landcode ("NL" → 🇳🇱). */
fun flagEmoji(code: String): String {
    val c = code.trim().uppercase()
    if (c.length != 2 || !c.all { it in 'A'..'Z' }) return ""
    val first = Character.codePointAt(c, 0) - 0x41 + 0x1F1E6
    val second = Character.codePointAt(c, 1) - 0x41 + 0x1F1E6
    return String(Character.toChars(first)) + String(Character.toChars(second))
}

/** Landnaam in de taal van de app ("NL" → "Nederland" / "Netherlands"). */
fun localizedCountryName(code: String, fallback: String = ""): String {
    val c = code.trim().uppercase()
    if (c.length == 2) {
        val n = Locale("", c).getDisplayCountry(Locale.getDefault())
        if (n.isNotBlank() && n != c) return n
    }
    return fallback.trim()
}

/** Dubbele zenders (zelfde naam + zelfde stream) samenvoegen, kapotte eruit (SPEC §2). */
fun List<Station>.cleaned(): List<Station> {
    val seen = HashSet<String>()
    val ids = HashSet<String>()
    // ook op uuid ontdubbelen: lazy lijsten gebruiken de uuid als sleutel
    return filter { s ->
        s.uuid.isNotEmpty() && s.streamUrl.isNotEmpty() && ids.add(s.uuid) &&
            seen.add(s.displayName.lowercase() + "|" + s.streamUrl.lowercase())
    }
}

/** Genres voor de chips (SPEC §4): tag → tekst-sleutel (zie GenreChips) */
val GENRE_TAGS = listOf(
    "pop", "news", "rock", "dance", "jazz", "classical", "hits", "talk",
    "sports", "oldies", "hiphop", "country", "ambient", "christian",
)

/** Muziekgenres (Bladeren → Muziek): de chips zonder nieuws, talk en sport */
val MUSIC_TAGS = GENRE_TAGS.filter { it != "news" && it != "talk" && it != "sports" }

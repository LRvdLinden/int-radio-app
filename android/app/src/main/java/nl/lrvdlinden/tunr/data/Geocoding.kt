package nl.lrvdlinden.tunr.data

import android.content.Context
import android.location.Address
import android.location.Geocoder
import android.os.Build
import androidx.annotation.RequiresApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.HttpUrl
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.resume

/** Een plaats uit de geocoder (SPEC §9): naam, regio/land, coördinaat en landcode */
@Serializable
data class MapPlace(
    val name: String,
    val detail: String = "",
    val lat: Double,
    val lon: Double,
    val countryCode: String = "",
) {
    val flag: String get() = flagEmoji(countryCode)
}

@Serializable
private data class NominatimAddress(
    @SerialName("country_code") val countryCode: String = "",
    val country: String = "",
    val state: String = "",
    val county: String = "",
    val city: String = "",
    val town: String = "",
    val village: String = "",
    val municipality: String = "",
)

@Serializable
private data class NominatimItem(
    val name: String = "",
    @SerialName("display_name") val displayName: String = "",
    val lat: String = "",
    val lon: String = "",
    val address: NominatimAddress? = null,
)

/**
 * Plaatsen zoeken (SPEC §9): eerst de Geocoder van het toestel (API 33+: callback-variant), anders of bij niets/fout
 * Nominatim (OpenStreetMap) met de User-Agent van de app (via [Http.client]), max. 1 aanvraag per seconde.
 */
object Geocoding {
    private const val MAX = 6
    private val memory = ConcurrentHashMap<String, List<MapPlace>>()
    private val nominatimLock = Mutex()
    private var lastNominatim = 0L

    suspend fun search(context: Context, query: String): List<MapPlace> {
        val q = query.trim()
        if (q.length < 2) return emptyList()
        val lang = Locale.getDefault().language.ifEmpty { "en" }
        val key = "$lang|${q.lowercase(Locale.ROOT)}"
        memory[key]?.let { return it }
        val fromDevice = runCatching { deviceGeocoder(context.applicationContext, q) }.getOrDefault(emptyList())
        val result = fromDevice.ifEmpty { nominatim(q, lang) }
        if (result.isNotEmpty()) memory[key] = result
        return result
    }

    // MARK: Geocoder van het toestel

    private suspend fun deviceGeocoder(context: Context, q: String): List<MapPlace> {
        if (!Geocoder.isPresent()) return emptyList()
        val geocoder = Geocoder(context, Locale.getDefault())
        val addresses: List<Address> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            withTimeoutOrNull(6_000L) { geocodeAsync(geocoder, q) } ?: emptyList()
        } else {
            withContext(Dispatchers.IO) {
                @Suppress("DEPRECATION")
                geocoder.getFromLocationName(q, MAX)?.toList() ?: emptyList()
            }
        }
        return addresses.mapNotNull { it.toPlace() }.distinctBy { "${it.name}|${it.detail}" }.take(MAX)
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private suspend fun geocodeAsync(geocoder: Geocoder, q: String): List<Address> =
        suspendCancellableCoroutine { cont ->
            geocoder.getFromLocationName(q, MAX, object : Geocoder.GeocodeListener {
                override fun onGeocode(addresses: MutableList<Address>) {
                    if (cont.isActive) cont.resume(addresses.toList())
                }

                override fun onError(errorMessage: String?) {
                    if (cont.isActive) cont.resume(emptyList())
                }
            })
        }

    private fun Address.toPlace(): MapPlace? {
        if (!hasLatitude() || !hasLongitude()) return null
        val name = listOf(locality, subAdminArea, featureName, adminArea, countryName)
            .firstOrNull { !it.isNullOrBlank() }?.trim() ?: return null
        val detail = listOfNotNull(adminArea, countryName)
            .map { it.trim() }.filter { it.isNotEmpty() && !it.equals(name, ignoreCase = true) }
            .distinct().joinToString(", ")
        return MapPlace(name, detail, latitude, longitude, countryCode?.uppercase(Locale.ROOT).orEmpty())
    }

    // MARK: Nominatim

    private suspend fun nominatim(q: String, lang: String): List<MapPlace> = nominatimLock.withLock {
        // Gebruiksregels van Nominatim: hooguit één aanvraag per seconde
        val wait = 1_000L - (System.currentTimeMillis() - lastNominatim)
        if (wait > 0) delay(wait)
        lastNominatim = System.currentTimeMillis()
        runCatching {
            val url = HttpUrl.Builder().scheme("https").host("nominatim.openstreetmap.org").addPathSegment("search")
                .addQueryParameter("q", q)
                .addQueryParameter("format", "jsonv2")
                .addQueryParameter("limit", "$MAX")
                .addQueryParameter("addressdetails", "1")
                .addQueryParameter("accept-language", lang)
                .build()
            val body = withContext(Dispatchers.IO) { Http.getString(url) }
            val items = withContext(Dispatchers.Default) {
                Http.json.decodeFromString(ListSerializer(NominatimItem.serializer()), body)
            }
            items.mapNotNull { it.toPlace() }.distinctBy { "${it.name}|${it.detail}" }.take(MAX)
        }.getOrDefault(emptyList())
    }

    private fun NominatimItem.toPlace(): MapPlace? {
        val la = lat.toDoubleOrNull() ?: return null
        val lo = lon.toDoubleOrNull() ?: return null
        val a = address
        val name = listOf(name, a?.city, a?.town, a?.village, a?.municipality, displayName.substringBefore(','))
            .firstOrNull { !it.isNullOrBlank() }?.trim() ?: return null
        val detail = listOfNotNull(a?.state, a?.country)
            .map { it.trim() }.filter { it.isNotEmpty() && !it.equals(name, ignoreCase = true) }
            .distinct().joinToString(", ")
            .ifEmpty { displayName.substringAfter(',', "").trim() }
        return MapPlace(name, detail, la, lo, a?.countryCode?.uppercase(Locale.ROOT).orEmpty())
    }
}

package nl.lrvdlinden.tunr.data

import android.content.Context
import android.os.Build
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import nl.lrvdlinden.tunr.Brand
import nl.lrvdlinden.tunr.BuildConfig
import nl.lrvdlinden.tunr.Device
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Anonieme gebruiksping (tunr-beheer/docs/CONTRACT.md, functie `ping`).
 * Bij het starten en bij terugkomen naar de voorgrond (MainActivity.onResume), als de laatste geslaagde ping
 * > 12 uur geleden is. Alleen als [Brand.STATS_URL] is ingevuld en de instelling "Anonieme
 * gebruiksstatistieken" ([Settings.shareStats], standaard aan) aan staat. Geen persoonsgegevens; fouten
 * worden genegeerd.
 */
object Stats {
    private const val PREFS = "tunr_stats"
    private const val KEY_INSTALL_ID = "install_id"
    private const val KEY_LAST_PING = "last_ping"
    private const val KEY_AUTO_USED = "android_auto_used"
    private const val INTERVAL_MS = 12L * 60 * 60 * 1000

    /** Package van Android Auto (controller die de mediabibliotheek opvraagt) */
    const val ANDROID_AUTO_PACKAGE = "com.google.android.projection.gearhead"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val inFlight = AtomicBoolean(false)
    private val jsonType = "application/json".toMediaType()

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Vanuit PlaybackService: Android Auto heeft verbinding gemaakt ("ooit gebruikt"). */
    fun markAndroidAutoUsed(context: Context) {
        val p = prefs(context)
        if (!p.getBoolean(KEY_AUTO_USED, false)) p.edit().putBoolean(KEY_AUTO_USED, true).apply()
    }

    fun pingIfDue(context: Context) {
        val base = Brand.STATS_URL.trim().trimEnd('/')
        if (base.isEmpty() || !Library.settings.value.shareStats) return
        val p = prefs(context)
        val now = System.currentTimeMillis()
        val last = p.getLong(KEY_LAST_PING, 0L)
        if (last > 0 && now >= last && now - last < INTERVAL_MS) return
        if (!inFlight.compareAndSet(false, true)) return

        val body = payload(context).toString()
        scope.launch {
            try {
                val req = Request.Builder()
                    .url("$base/functions/v1/ping")
                    .header("apikey", Brand.STATS_KEY)
                    .post(body.toRequestBody(jsonType))
                    .build()
                Http.client.newCall(req).execute().use { resp ->
                    if (resp.code == 200) p.edit().putLong(KEY_LAST_PING, System.currentTimeMillis()).apply()
                }
            } catch (_: Exception) {
                // genegeerd
            } finally {
                inFlight.set(false)
            }
        }
    }

    private fun installId(context: Context): String {
        val p = prefs(context)
        val existing = p.getString(KEY_INSTALL_ID, null)
        if (existing != null && runCatching { UUID.fromString(existing) }.isSuccess) return existing
        val id = UUID.randomUUID().toString()
        p.edit().putString(KEY_INSTALL_ID, id).apply()
        return id
    }

    private fun payload(context: Context) = buildJsonObject {
        val code = Library.country.value?.code?.uppercase(Locale.ROOT).orEmpty()
        val tag = Library.settings.value.language
        val lang = when {
            tag == "nl" || tag == "en" -> tag
            Locale.getDefault().language == "nl" -> "nl"
            else -> "en"
        }
        put("id", installId(context))
        put("platform", if (Device.isTV) "androidtv" else "android")
        put("device", deviceType(context))
        put("model", Build.MODEL.orEmpty().take(60))
        put("os", Build.VERSION.RELEASE.orEmpty().take(20))
        put("version", BuildConfig.VERSION_NAME)
        put("build", BuildConfig.VERSION_CODE.coerceIn(0, 99999))
        put("country", if (Regex("^[A-Z]{2}$").matches(code)) code else "")
        put("lang", lang)
        put("carplay", prefs(context).getBoolean(KEY_AUTO_USED, false))
    }

    /** "Android-telefoon", "Android-tablet", "Android TV", "Google TV" of "Fire TV" (vaste waarden uit het contract). */
    private fun deviceType(context: Context): String {
        if (Device.isTV) {
            val pm = context.packageManager
            return when {
                Build.MANUFACTURER.equals("Amazon", ignoreCase = true) || pm.hasSystemFeature("amazon.hardware.fire_tv") -> "Fire TV"
                pm.hasSystemFeature("com.google.android.tv") -> "Google TV"
                else -> "Android TV"
            }
        }
        return if (context.resources.configuration.smallestScreenWidthDp >= 600) "Android-tablet" else "Android-telefoon"
    }
}

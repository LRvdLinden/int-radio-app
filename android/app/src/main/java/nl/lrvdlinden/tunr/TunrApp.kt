package nl.lrvdlinden.tunr

import android.app.Application
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.serialization.json.Json
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.Settings
import java.util.Locale
import kotlin.coroutines.CoroutineContext

/** Start van het proces (ook als alleen Android Auto of de mediamelding de dienst start). */
class TunrApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Device.init(this)
        RadioBrowser.init(this)
        Library.init(this)
    }
}

/** Is dit een tv (Android TV / Google TV / Fire TV)? Dan de tv-indeling met D-pad-focus. */
object Device {
    var isTV: Boolean = false
        private set

    fun init(context: Context) {
        val ui = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val pm = context.packageManager
        isTV = ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature("amazon.hardware.fire_tv")
    }
}

/** Scope voor korte klussen die niet aan een scherm hangen (klik tellen, albumhoes zoeken, slaaptimer). */
object AppScope : CoroutineScope {
    override val coroutineContext: CoroutineContext = SupervisorJob() + Dispatchers.Main.immediate
}

/**
 * Taal van de app: Systeem, Nederlands of English (Instellingen → Taal).
 * MainActivity wikkelt zijn Context hierin (attachBaseContext) en maakt zich opnieuw bij een wijziging.
 */
object LocaleHelper {
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    fun languageTag(context: Context): String {
        val raw = context.getSharedPreferences(Library.PREFS, Context.MODE_PRIVATE).getString(Library.KEY_SETTINGS, null)
            ?: return Settings.SYSTEM
        return runCatching { json.decodeFromString(Settings.serializer(), raw).language }.getOrDefault(Settings.SYSTEM)
    }

    /** Context met de gekozen taal (of ongewijzigd bij "Systeem"). */
    fun wrap(base: Context): Context {
        val tag = languageTag(base)
        if (tag == Settings.SYSTEM || tag.isBlank()) return base
        val config = Configuration(base.resources.configuration)
        config.setLocale(Locale(tag))
        return base.createConfigurationContext(config)
    }

    /** Land van het toestel (niet beïnvloed door de taalkeuze in de app). */
    fun deviceCountry(): String {
        val sys = android.content.res.Resources.getSystem().configuration.locales
        return if (sys.size() > 0) sys[0].country.uppercase() else Locale.getDefault().country.uppercase()
    }
}

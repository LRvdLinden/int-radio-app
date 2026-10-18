package nl.lrvdlinden.tunr

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import nl.lrvdlinden.tunr.data.Stats
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.AppState
import nl.lrvdlinden.tunr.ui.ScreenshotMode
import nl.lrvdlinden.tunr.ui.TunrRoot
import nl.lrvdlinden.tunr.ui.TunrTheme

class MainActivity : ComponentActivity() {

    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* mediamelding: mag ook zonder */ }

    /** Taal uit Instellingen toepassen vóór er iets getekend wordt. */
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleHelper.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        // Nieuwe start (niet na een taalwissel / recreate): weer met de splash beginnen
        if (savedInstanceState == null) {
            ScreenshotMode.readIntent(intent)
            AppState.resetForLaunch()
            ScreenshotMode.prepare()  // alleen met de extra tunr_screenshot (Play Store-afbeeldingen)
        }
        // Schermafbeeldingen: navigatie-/taakbalk weg (geen app-iconen van het toestel in beeld)
        if (ScreenshotMode.isActive) {
            androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
                systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(androidx.core.view.WindowInsetsCompat.Type.navigationBars())
            }
        }
        RadioController.connect(applicationContext)
        AppState.onReachedMain = { askNotificationPermission() }

        setContent {
            TunrTheme {
                TunrRoot()
            }
        }
    }

    /** Bij starten en terugkomen naar de voorgrond: anonieme ping (max. 1× per 12 uur, zie Stats). */
    override fun onResume() {
        super.onResume()
        if (!ScreenshotMode.isActive) Stats.pingIfDue(applicationContext)
    }

    /** Android 13+: toestemming voor de mediamelding (één keer vragen, niet op tv). */
    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33 || Device.isTV || ScreenshotMode.isActive) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        val prefs = getSharedPreferences("tunr_flags", MODE_PRIVATE)
        if (prefs.getBoolean("asked_notifications", false)) return
        prefs.edit().putBoolean("asked_notifications", true).apply()
        notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}

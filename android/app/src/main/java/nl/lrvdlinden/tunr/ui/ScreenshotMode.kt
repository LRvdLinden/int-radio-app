package nl.lrvdlinden.tunr.ui

import android.content.Intent
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import nl.lrvdlinden.tunr.AppScope
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.player.RadioController

/**
 * Play Store-schermafbeeldingen (workflow *Play Store media*, `.github/workflows/playstore-media.yml`).
 * Start met `adb shell am start -n nl.lrvdlinden.tunr/.MainActivity --es tunr_screenshot <scène>`.
 * Dan: geen splash/tune, land Nederland zonder landkeuze, geen gebruiksping, geen vraag om meldingen,
 * favorieten en land alleen in het geheugen, en meteen de gevraagde scène. De taal volgt het toestel (in CI Engels).
 * Zonder die extra doet dit niets (ook veilig in een release-build). Zelfde scènes als de Apple-app (ScreenshotMode.swift).
 */
object ScreenshotMode {
    enum class Scene { DISCOVER, BROWSE, MAP, SEARCH, PODCASTS, PLAYER, LIBRARY }

    const val EXTRA = "tunr_screenshot"
    const val COUNTRY_CODE = "NL"
    const val COUNTRY_NAME = "The Netherlands"
    private const val SEARCH_QUERY = "jazz"
    private const val PLAYER_STATION = "Qmusic"
    private const val FAVORITE_COUNT = 6

    /** De gevraagde scène, of null (gewone start) */
    var scene: Scene? = null
        private set

    val isActive: Boolean get() = scene != null

    /** Startzoekterm voor Zoeken */
    val initialSearch: String get() = if (scene == Scene.SEARCH) SEARCH_QUERY else ""

    fun readIntent(intent: Intent?) {
        val v = intent?.getStringExtra(EXTRA) ?: return
        scene = Scene.entries.firstOrNull { it.name.equals(v.trim(), ignoreCase = true) } ?: Scene.DISCOVER
    }

    /** Scène klaarzetten (na Library.init en AppState.resetForLaunch); gegevens komen live van Radio Browser. */
    fun prepare() {
        val s = scene ?: return
        Library.applyScreenshotCountry(COUNTRY_CODE, COUNTRY_NAME)
        AppState.stage = AppState.Stage.MAIN
        AppState.tab = when (s) {
            Scene.BROWSE, Scene.PODCASTS -> Tab.BROWSE
            Scene.MAP -> Tab.MAP
            Scene.SEARCH -> Tab.SEARCH
            Scene.LIBRARY -> Tab.LIBRARY
            else -> Tab.DISCOVER
        }
        if (s == Scene.PODCASTS) Nav.push(Route.PodcastsHome)
        AppScope.launch {
            val popular = runCatching { RadioBrowser.popular(COUNTRY_CODE, 60) }.getOrDefault(emptyList())
            val withLogo = popular.filter { it.favicon.isNotBlank() }
            Library.setScreenshotFavorites((if (withLogo.size >= FAVORITE_COUNT) withLogo else popular).take(FAVORITE_COUNT))
            if (s == Scene.PLAYER) {
                val found = runCatching { RadioBrowser.search(PLAYER_STATION, COUNTRY_CODE) }.getOrDefault(emptyList())
                val pick = found.firstOrNull { it.name.contains(PLAYER_STATION, ignoreCase = true) && it.streamUrl.isNotBlank() }
                    ?: popular.firstOrNull { it.streamUrl.isNotBlank() }
                if (pick != null) {
                    RadioController.play(pick, popular.ifEmpty { listOf(pick) })
                    delay(800)
                    AppState.showPlayer = true
                }
            }
        }
    }
}

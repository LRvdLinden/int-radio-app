package nl.lrvdlinden.tunr.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.focus.FocusRequester
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import nl.lrvdlinden.tunr.AppScope
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.data.Episode
import nl.lrvdlinden.tunr.data.Podcast
import nl.lrvdlinden.tunr.data.Station

/** Tabs (SPEC §6): Ontdek · Bladeren · Kaart · Zoeken · Bibliotheek (+ Instellingen op tv) */
enum class Tab { DISCOVER, BROWSE, MAP, SEARCH, LIBRARY, SETTINGS }

/** Toestand van de app die meerdere schermen delen (Compose-state, alleen op de main thread). */
object AppState {
    enum class Stage { SPLASH, COUNTRY, MAIN }

    var stage by mutableStateOf(Stage.SPLASH)
    var tab by mutableStateOf(Tab.DISCOVER)
    /** Volledige speler open */
    var showPlayer by mutableStateOf(false)
    /** Tv: de zijbalk heeft de focus (dan pakt een nieuw tabblad de focus niet af) */
    var railFocused by mutableStateOf(false)
    /** Kaart: zender om naartoe te vliegen (bijv. vanuit "Wereldkaart" of zenderdetail) */
    var mapFocus by mutableStateOf<Station?>(null)

    /** Wordt aangeroepen als het hoofdscherm voor het eerst verschijnt (toestemming voor meldingen) */
    var onReachedMain: (() -> Unit)? = null

    fun resetForLaunch() {
        stage = Stage.SPLASH
        tab = Tab.DISCOVER
        showPlayer = false
        Nav.clear()
    }
}

/** Een scherm boven het hoofdscherm. */
sealed class Route {
    data object CountryPicker : Route()
    data object Settings : Route()
    data class StationDetail(val station: Station) : Route()
    data class Grid(val source: GridSource) : Route()
    data object Regions : Route()
    data object Music : Route()
    data object NewsTalk : Route()
    data object Languages : Route()
    /** Podcasts (SPEC §8): overzicht, genre-toplijst, podcastpagina, afleveringspagina */
    data object PodcastsHome : Route()
    data class PodcastGenre(val genreId: Int) : Route()
    data class PodcastDetail(val podcast: Podcast) : Route()
    data class EpisodeDetail(val episode: Episode, val queue: List<Episode> = listOf(episode)) : Route()
}

/** Waar een rasterpagina zijn zenders vandaan haalt. */
sealed class GridSource {
    data class Popular(val cc: String) : GridSource()
    data class Trending(val cc: String) : GridSource()
    data class Tag(val tag: String, val cc: String?) : GridSource()
    data class Region(val cc: String, val state: String) : GridSource()
    data class Language(val name: String, val label: String) : GridSource()
    data object Top100 : GridSource()
    data object Favorites : GridSource()
    data object Recents : GridSource()
}

/**
 * Eigen schermstapel (geen Navigation-bibliotheek): [Nav.push] legt een scherm erover, terug sluit het bovenste.
 * Op tv komt de focus na het sluiten terug op het element dat het scherm opende ([FocusMemory]).
 */
object Nav {
    data class Entry(val id: Long, val route: Route)

    val stack = mutableStateListOf<Entry>()
    private var counter = 0L
    private val returnFocus = HashMap<Long, FocusRequester>()

    fun push(route: Route) {
        // Dezelfde zender twee keer achter elkaar openen (bijv. via "vergelijkbaar") is zinloos
        if (stack.lastOrNull()?.route == route) return
        counter += 1
        FocusMemory.current?.let { returnFocus[counter] = it }
        stack.add(Entry(counter, route))
    }

    fun station(s: Station) = push(Route.StationDetail(s))
    fun grid(source: GridSource) = push(Route.Grid(source))
    fun podcast(p: Podcast) = push(Route.PodcastDetail(p))
    fun episode(e: Episode, queue: List<Episode> = listOf(e)) = push(Route.EpisodeDetail(e, queue))

    fun pop(): Boolean {
        val top = stack.lastOrNull() ?: return false
        close(top.id)
        return true
    }

    fun close(id: Long) {
        val wasTop = stack.lastOrNull()?.id == id
        val back = returnFocus.remove(id)
        stack.removeAll { it.id == id }
        if (wasTop && back != null) FocusMemory.restore(back)
    }

    fun clear() { stack.clear(); returnFocus.clear() }
}

/** Onthoudt op tv welk element de focus had, om die na het sluiten van een scherm terug te zetten. */
object FocusMemory {
    var current: FocusRequester? = null
        private set

    fun changed(r: FocusRequester, focused: Boolean) {
        if (focused) current = r else if (current === r) current = null
    }

    fun restore(r: FocusRequester) {
        if (!Device.isTV) return
        AppScope.launch {
            repeat(10) {
                delay(80)
                if (current === r) return@launch
                runCatching { r.requestFocus() }
            }
        }
    }
}

/** Op tv meteen de focus op dit element (een paar pogingen: lazy lijsten komen iets later). */
@Composable
fun rememberInitialFocus(enabled: Boolean = Device.isTV, key: Any? = Unit): FocusRequester {
    val r = remember { FocusRequester() }
    LaunchedEffect(key, enabled) {
        if (!enabled) return@LaunchedEffect
        repeat(10) {
            if (AppState.railFocused && Nav.stack.isEmpty()) return@LaunchedEffect
            delay(90)
            if (runCatching { r.requestFocus() }.isSuccess) return@LaunchedEffect
        }
    }
    return r
}

/** Resultaat van een laadactie */
sealed interface Load<out T> {
    data object Loading : Load<Nothing>
    data class Ok<T>(val value: T) : Load<T>
    data class Failed(val error: Throwable) : Load<Nothing>
}

class LoadState<T>(val state: Load<T>, val retry: () -> Unit) {
    val value: T? get() = (state as? Load.Ok<T>)?.value
    val loading: Boolean get() = state is Load.Loading
    val failed: Boolean get() = state is Load.Failed
}

/** Laadt iets (opnieuw bij andere [keys]); [LoadState.retry] probeert het nog eens. */
@Composable
fun <T> rememberLoad(vararg keys: Any?, block: suspend () -> T): LoadState<T> {
    var attempt by remember { mutableIntStateOf(0) }
    var state by remember(*keys) { mutableStateOf<Load<T>>(Load.Loading) }
    val current by rememberUpdatedState(block)
    LaunchedEffect(*keys, attempt) {
        if (state !is Load.Ok<*> || attempt > 0) state = Load.Loading
        state = try {
            Load.Ok(current())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Load.Failed(e)
        }
    }
    return LoadState(state) { attempt++ }
}

package nl.lrvdlinden.tunr.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.input.pointer.pointerInput
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.screens.CountryPickerScreen
import nl.lrvdlinden.tunr.ui.screens.EpisodeDetailScreen
import nl.lrvdlinden.tunr.ui.screens.PodcastDetailScreen
import nl.lrvdlinden.tunr.ui.screens.PodcastGenreScreen
import nl.lrvdlinden.tunr.ui.screens.PodcastsHomeScreen
import nl.lrvdlinden.tunr.ui.screens.LanguagesScreen
import nl.lrvdlinden.tunr.ui.screens.MainScreen
import nl.lrvdlinden.tunr.ui.screens.MusicScreen
import nl.lrvdlinden.tunr.ui.screens.NewsTalkScreen
import nl.lrvdlinden.tunr.ui.screens.PlayerScreen
import nl.lrvdlinden.tunr.ui.screens.RegionsScreen
import nl.lrvdlinden.tunr.ui.screens.SettingsScreen
import nl.lrvdlinden.tunr.ui.screens.SplashScreen
import nl.lrvdlinden.tunr.ui.screens.StationDetailScreen
import nl.lrvdlinden.tunr.ui.screens.StationGridScreen

/** Splash → (eerste keer) landkeuze → hoofdscherm; schermen en speler liggen erbovenop. */
@Composable
fun TunrRoot() {
    Box(Modifier.fillMaxSize().background(T.bg)) {
        val covered = Nav.stack.isNotEmpty() || AppState.showPlayer
        Box(Modifier.fillMaxSize().blockFocus(covered)) {
            Crossfade(targetState = AppState.stage, animationSpec = tween(450), label = "stage") { stage ->
                when (stage) {
                    AppState.Stage.SPLASH -> SplashScreen(onFinished = {
                        AppState.stage = if (Library.country.value == null) AppState.Stage.COUNTRY else AppState.Stage.MAIN
                    })
                    AppState.Stage.COUNTRY -> CountryPickerScreen(firstRun = true, onPicked = { AppState.stage = AppState.Stage.MAIN })
                    AppState.Stage.MAIN -> MainScreen()
                }
            }
        }

        // Schermstapel boven het hoofdscherm
        val entries = Nav.stack.toList()
        entries.forEachIndexed { i, entry ->
            key(entry.id) {
                val top = i == entries.lastIndex
                AnimatedLayer(Modifier.blockFocus(!top || AppState.showPlayer)) {
                    RouteContent(entry.route, onClose = { Nav.close(entry.id) })
                }
            }
        }

        // Volledige speler (sheet)
        AnimatedVisibility(
            visible = AppState.showPlayer,
            enter = slideInVertically(tween(320)) { it } + fadeIn(tween(200)),
            exit = slideOutVertically(tween(260)) { it } + fadeOut(tween(200)),
        ) {
            FullLayer { PlayerScreen(onClose = { AppState.showPlayer = false }) }
        }

        BackHandler(enabled = AppState.showPlayer) { AppState.showPlayer = false }
        BackHandler(enabled = !AppState.showPlayer && Nav.stack.isNotEmpty()) { Nav.pop() }
        // Hoofdscherm: terug gaat eerst naar Ontdek, pas daarna uit de app
        BackHandler(enabled = !AppState.showPlayer && Nav.stack.isEmpty() && AppState.stage == AppState.Stage.MAIN &&
            AppState.tab != Tab.DISCOVER) { AppState.tab = Tab.DISCOVER }
    }

    LaunchedEffect(AppState.stage) {
        if (AppState.stage == AppState.Stage.MAIN) {
            AppState.onReachedMain?.invoke()
            RadioController.autoplayLastIfWanted()
        }
    }
    // Speler sluiten als er niets meer is om te tonen
    val station by RadioController.station.collectAsState()
    val episode by RadioController.episode.collectAsState()
    val nothing = station == null && episode == null
    LaunchedEffect(nothing) { if (nothing) AppState.showPlayer = false }
}

@Composable
private fun RouteContent(route: Route, onClose: () -> Unit) {
    when (route) {
        Route.CountryPicker -> CountryPickerScreen(firstRun = false, onPicked = onClose, onClose = onClose)
        Route.Settings -> SettingsScreen(onClose = onClose)
        is Route.StationDetail -> StationDetailScreen(route.station, onClose = onClose)
        is Route.Grid -> StationGridScreen(route.source, onClose = onClose)
        Route.Regions -> RegionsScreen(onClose = onClose)
        Route.Music -> MusicScreen(onClose = onClose)
        Route.NewsTalk -> NewsTalkScreen(onClose = onClose)
        Route.Languages -> LanguagesScreen(onClose = onClose)
        Route.PodcastsHome -> PodcastsHomeScreen(onClose = onClose)
        is Route.PodcastGenre -> PodcastGenreScreen(route.genreId, onClose = onClose)
        is Route.PodcastDetail -> PodcastDetailScreen(route.podcast, onClose = onClose)
        is Route.EpisodeDetail -> EpisodeDetailScreen(route.episode, route.queue, onClose = onClose)
    }
}

/** Scherm dat van rechts inschuift (telefoon) of infadet (tv) */
@Composable
private fun AnimatedLayer(modifier: Modifier, content: @Composable BoxScope.() -> Unit) {
    val state = androidx.compose.runtime.remember {
        androidx.compose.animation.core.MutableTransitionState(false).apply { targetState = true }
    }
    AnimatedVisibility(
        visibleState = state,
        enter = if (Dims.tv) fadeIn(tween(220)) else slideInHorizontally(tween(280)) { it / 3 } + fadeIn(tween(220)),
        exit = if (Dims.tv) fadeOut(tween(160)) else slideOutHorizontally(tween(220)) { it / 3 } + fadeOut(tween(160)),
    ) {
        FullLayer(modifier, content)
    }
}

/** Volledig scherm, ondoorzichtig, en tikken gaan niet door naar wat eronder ligt. */
@Composable
fun FullLayer(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier
            .fillMaxSize()
            .background(T.bg)
            .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } },
        content = content
    )
}

/** D-pad: focus kan niet in deze groep komen zolang [blocked] (er ligt iets overheen). */
@OptIn(ExperimentalComposeUiApi::class)
fun Modifier.blockFocus(blocked: Boolean): Modifier =
    this.focusProperties { if (blocked) enter = { FocusRequester.Cancel } }.focusGroup()

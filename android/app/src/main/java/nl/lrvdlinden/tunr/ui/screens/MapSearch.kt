package nl.lrvdlinden.tunr.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Country
import nl.lrvdlinden.tunr.data.Geocoding
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.MapPlace
import nl.lrvdlinden.tunr.data.MapRecent
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.flagEmoji
import nl.lrvdlinden.tunr.ui.AppState
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.stationCount
import nl.lrvdlinden.tunr.ui.tvClickable
import java.text.Normalizer
import java.util.Locale

/** Suggestie in het zoekveld op de kaart (SPEC §9) */
sealed interface MapSuggestion {
    data class CountryItem(val country: Country) : MapSuggestion
    data class PlaceItem(val place: MapPlace) : MapSuggestion
    data class RecentItem(val recent: MapRecent) : MapSuggestion
}

/** Toestand van het zoekveld op de kaart: tekst, suggesties en of de lijst open is */
@Stable
class MapSearchState {
    var query by mutableStateOf("")
    var open by mutableStateOf(false)
    var countries by mutableStateOf<List<Country>>(emptyList())
    var places by mutableStateOf<List<MapPlace>>(emptyList())
    var searching by mutableStateOf(false)
    /** Zoekterm waarvoor de suggesties compleet zijn (landen én plaatsen) */
    var resultsFor by mutableStateOf<String?>(null)
    /** Enter gedrukt voordat de suggesties er waren: kies de eerste zodra ze binnen zijn */
    var submitPending by mutableStateOf(false)

    val first: MapSuggestion?
        get() = countries.firstOrNull()?.let { MapSuggestion.CountryItem(it) }
            ?: places.firstOrNull()?.let { MapSuggestion.PlaceItem(it) }

    /** Veld leeg en suggesties dicht */
    fun clear() {
        query = ""
        countries = emptyList()
        places = emptyList()
        searching = false
        resultsFor = null
        submitPending = false
        open = false
    }

    fun submit(onChoose: (MapSuggestion) -> Unit) {
        val q = query.trim()
        if (q.length < 2) return
        if (resultsFor == q && !searching) {
            val f = first ?: return
            clear()
            onChoose(f)
        } else submitPending = true
    }
}

/** Zoektoestand met debounce (300 ms, vanaf 2 tekens): landen uit de cache van Radio Browser, plaatsen via [Geocoding] */
@Composable
fun rememberMapSearchState(onChoose: (MapSuggestion) -> Unit): MapSearchState {
    val context = LocalContext.current
    val state = remember { MapSearchState() }
    val choose by rememberUpdatedState(onChoose)
    val allCountries by produceState<List<Country>>(emptyList()) {
        value = try { RadioBrowser.countries() } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
    }
    LaunchedEffect(state.query, allCountries) {
        val q = state.query.trim()
        if (q.length < 2) {
            state.countries = emptyList(); state.places = emptyList(); state.searching = false; state.resultsFor = null
            return@LaunchedEffect
        }
        delay(300)
        state.countries = matchCountries(allCountries, q)
        state.places = emptyList()
        state.searching = true
        val found = try {
            Geocoding.search(context, q)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
        state.places = found
        state.searching = false
        state.resultsFor = q
        if (state.submitPending) {
            state.submitPending = false
            val f = state.first
            if (f != null) { state.clear(); choose(f) }
        }
    }
    return state
}

private fun normalize(s: String): String =
    Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT).trim()

/** Landen die passen op de gelokaliseerde of Engelse naam of de landcode; beste match eerst, max 5 */
private fun matchCountries(all: List<Country>, query: String): List<Country> {
    val q = normalize(query)
    if (q.isEmpty()) return emptyList()
    return all.mapNotNull { c ->
        val code = c.code.trim().lowercase(Locale.ROOT)
        val local = normalize(c.localizedName)
        val english = normalize(c.name)
        val englishLocale = normalize(Locale("", c.code.trim().uppercase(Locale.ROOT)).getDisplayCountry(Locale.ENGLISH))
        val names = listOf(local, english, englishLocale).filter { it.isNotEmpty() }
        val score = when {
            q.length == 2 && code == q -> 0
            local.startsWith(q) -> 1
            names.any { it.startsWith(q) } -> 2
            names.any { n -> n.split(' ', '-', '(').any { it.startsWith(q) } } -> 3
            q.length >= 3 && names.any { it.contains(q) } -> 4
            else -> return@mapNotNull null
        }
        c to score
    }.sortedWith(compareBy<Pair<Country, Int>> { it.second }.thenByDescending { it.first.stationCount })
        .take(5).map { it.first }
}

/** Het zoekveld zelf (Enter = eerste suggestie, Escape/× = leeg en dicht) */
@Composable
fun MapSearchField(
    state: MapSearchState,
    onChoose: (MapSuggestion) -> Unit,
    modifier: Modifier = Modifier,
    focusRequester: FocusRequester? = null,
) {
    val focusManager = LocalFocusManager.current
    BackHandler(enabled = state.open && Nav.stack.isEmpty() && !AppState.showPlayer) { state.clear(); focusManager.clearFocus() }
    SearchField(
        value = state.query,
        onChange = { state.query = it; state.open = true },
        placeholder = stringResource(R.string.map_search_placeholder),
        modifier = modifier.onPreviewKeyEvent { e ->
            if (e.key == Key.Escape && e.type == KeyEventType.KeyUp) {
                state.clear(); focusManager.clearFocus(); true
            } else false
        },
        focusRequester = focusRequester,
        onSubmit = { state.submit(onChoose) },
        onFocusChange = { focused ->
            if (focused) state.open = true
            else if (!Device.isTV && state.query.isBlank()) state.open = false
        },
        onClear = { state.clear(); focusManager.clearFocus() },
    )
}

/** Of de suggestielijst zichtbaar moet zijn */
@Composable
fun mapSearchPanelVisible(state: MapSearchState): Boolean {
    val recents by Library.mapSearches.collectAsState()
    return state.open && (state.query.trim().length >= 2 || recents.isNotEmpty())
}

/** Suggesties in twee groepen (Landen, Plaatsen), of recente kaartzoekopdrachten als het veld leeg is */
@Composable
fun MapSearchPanel(
    state: MapSearchState,
    onChoose: (MapSuggestion) -> Unit,
    modifier: Modifier = Modifier,
    maxHeight: Dp = 340.dp,
) {
    val recents by Library.mapSearches.collectAsState()
    val q = state.query.trim()
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(T.elevated.copy(alpha = 0.97f))
            .heightIn(max = maxHeight)
            .verticalScroll(rememberScrollState())
            .padding(vertical = 6.dp)
    ) {
        if (q.length < 2) {
            Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 6.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                GroupHeader(stringResource(R.string.recent_searches), Modifier.weight(1f))
                Text(
                    stringResource(R.string.clear), color = T.accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.tvClickable(RoundedCornerShape(8.dp), scale = 1.04f) { Library.clearMapSearches() }
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                )
            }
            recents.forEach { r ->
                SuggestionRow(
                    flag = flagEmoji(r.countryCode), icon = Icons.Rounded.History, title = r.label,
                    subtitle = r.place?.detail?.takeIf { it.isNotEmpty() },
                ) { onChoose(MapSuggestion.RecentItem(r)) }
            }
        } else {
            MapSearchResults(state, q, onChoose)
        }
    }
}

@Composable
private fun MapSearchResults(state: MapSearchState, q: String, onChoose: (MapSuggestion) -> Unit) {
    Column {
        if (state.countries.isNotEmpty()) {
            GroupHeader(stringResource(R.string.map_search_countries), Modifier.padding(start = 14.dp, top = 4.dp))
            state.countries.forEach { c ->
                SuggestionRow(flag = c.flag, icon = Icons.Rounded.Public, title = c.localizedName, subtitle = stationCount(c.stationCount)) {
                    onChoose(MapSuggestion.CountryItem(c))
                }
            }
        }
        if (state.places.isNotEmpty()) {
            GroupHeader(stringResource(R.string.map_search_places), Modifier.padding(start = 14.dp, top = 6.dp))
            state.places.forEach { p ->
                SuggestionRow(flag = p.flag, icon = Icons.Rounded.Place, title = p.name, subtitle = p.detail.takeIf { it.isNotEmpty() }) {
                    onChoose(MapSuggestion.PlaceItem(p))
                }
            }
        }
        when {
            state.searching || state.resultsFor != q -> Row(
                Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically
            ) {
                CircularProgressIndicator(Modifier.size(14.dp), color = T.accent, strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.map_search_searching), color = T.secondary, fontSize = 13.sp)
            }
            state.countries.isEmpty() && state.places.isEmpty() -> Text(
                stringResource(R.string.map_search_none, q), color = T.secondary, fontSize = 14.sp,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)
            )
        }
    }
}

@Composable
private fun GroupHeader(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(Locale.getDefault()), color = T.secondary, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        letterSpacing = 0.8.sp, modifier = modifier.padding(vertical = 4.dp))
}

@Composable
private fun SuggestionRow(flag: String, icon: ImageVector, title: String, subtitle: String?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp)
            .tvClickable(RoundedCornerShape(10.dp), scale = 1.02f, onClick = onClick)
            .padding(horizontal = 10.dp, vertical = if (Device.isTV) 10.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Start,
    ) {
        Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
            if (flag.isNotEmpty()) Text(flag, fontSize = 20.sp)
            else Icon(icon, null, tint = T.secondary, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, color = T.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

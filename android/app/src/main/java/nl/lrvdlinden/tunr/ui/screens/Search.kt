package nl.lrvdlinden.tunr.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.GENRE_TAGS
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.PODCAST_GENRE_IDS
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.data.localizedCountryName
import nl.lrvdlinden.tunr.player.PlaybackService
import nl.lrvdlinden.tunr.ui.Chip
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.ErrorRetry
import nl.lrvdlinden.tunr.ui.GridSource
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.Route
import nl.lrvdlinden.tunr.ui.SegmentedControl
import nl.lrvdlinden.tunr.ui.podcastGenreIcon
import nl.lrvdlinden.tunr.ui.podcastGenreLabel
import nl.lrvdlinden.tunr.ui.SkeletonList
import nl.lrvdlinden.tunr.ui.StationRow
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.bottomContentPadding
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.tvClickable

/** Zoekveld in de huisstijl (ook gebruikt door de landkeuze) */
@Composable
fun SearchField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    focusRequester: FocusRequester? = null,
    onSubmit: () -> Unit = {},
    onFocusChange: (Boolean) -> Unit = {},
    onClear: (() -> Unit)? = null,
) {
    var focused by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier
            .fillMaxWidth()
            .background(T.surface, shape)
            .border(if (focused) 2.dp else 1.dp, if (focused) Color.White else T.stroke, shape)
            .padding(horizontal = 12.dp, vertical = if (Device.isTV) 14.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Rounded.Search, null, tint = T.secondary, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, color = T.secondary, fontSize = 16.sp, maxLines = 1)
            BasicTextField(
                value = value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = TextStyle(color = T.text, fontSize = 16.sp),
                cursorBrush = SolidColor(T.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSubmit(); focusManager.clearFocus() }),
                modifier = Modifier.fillMaxWidth()
                    .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
                    .onFocusChanged { focused = it.isFocused; onFocusChange(it.isFocused) }
            )
        }
        if (value.isNotEmpty()) {
            Icon(Icons.Rounded.Close, stringResource(R.string.clear), tint = T.secondary,
                modifier = Modifier.size(22.dp).tvClickable(RoundedCornerShape(11.dp)) { if (onClear != null) onClear() else onChange("") })
        }
    }
}

/** Zoeken (SPEC §4): debounce 350 ms, {land} / Wereldwijd, populaire genres + recent gezocht als het veld leeg is */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SearchScreen() {
    val cc = currentCountryCode()
    var query by rememberSaveable { mutableStateOf("") }
    var worldwide by rememberSaveable { mutableStateOf(false) }
    /** 0 = Zenders, 1 = Podcasts (SPEC §8) */
    var segment by rememberSaveable { mutableStateOf(0) }
    var results by remember { mutableStateOf<List<Station>?>(null) }
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }
    val recentSearches by Library.recentSearches.collectAsState()
    val fieldFocus = rememberInitialFocus()

    LaunchedEffect(query, worldwide, cc, attempt, segment) {
        val q = query.trim()
        failed = false
        if (q.length < 2 || segment != 0) { results = null; return@LaunchedEffect }
        delay(350)
        results = null
        try {
            results = RadioBrowser.search(q, if (worldwide) null else cc)
            Library.addSearch(q)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            failed = true
        }
    }

    Column(Modifier.fillMaxSize().background(T.bg).statusBarsPadding()) {
        Text(stringResource(R.string.tab_search), style = heading(if (Device.isTV) 34.sp else 28.sp),
            modifier = Modifier.padding(start = Dims.edge, end = Dims.edge, top = 16.dp))
        SegmentedControl(
            listOf(stringResource(R.string.stations), stringResource(R.string.podcasts)), segment,
            Modifier.padding(start = Dims.edge, end = Dims.edge, top = 12.dp).widthIn(max = 420.dp).fillMaxWidth()
        ) { segment = it }
        SearchField(query, { query = it },
            stringResource(if (segment == 0) R.string.search_placeholder else R.string.search_podcasts_placeholder),
            Modifier.padding(horizontal = Dims.edge, vertical = 12.dp).widthIn(max = 720.dp), focusRequester = fieldFocus)
        if (segment == 0) {
            Row(Modifier.padding(horizontal = Dims.edge), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip(localizedCountryName(cc, cc), selected = !worldwide) { worldwide = false }
                Chip(stringResource(R.string.worldwide), selected = worldwide) { worldwide = true }
            }
            Spacer(Modifier.height(8.dp))
        }

        val q = query.trim()
        when {
            segment == 1 && q.length >= 2 -> PodcastSearchResults(q, cc)
            segment == 1 -> LazyColumn(contentPadding = PaddingValues(bottom = bottomContentPadding)) {
                item {
                    Text(stringResource(R.string.podcast_genres), style = heading(Dims.titleSize),
                        modifier = Modifier.padding(start = Dims.edge, end = Dims.edge, top = 8.dp, bottom = 10.dp))
                    FlowRow(Modifier.padding(horizontal = Dims.edge), horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        PODCAST_GENRE_IDS.forEach { id ->
                            Chip(stringResource(podcastGenreLabel(id)), icon = podcastGenreIcon(id)) { Nav.push(Route.PodcastGenre(id)) }
                        }
                    }
                }
                if (recentSearches.isNotEmpty()) {
                    item {
                        Text(stringResource(R.string.recent_searches), style = heading(Dims.titleSize),
                            modifier = Modifier.padding(start = Dims.edge, end = Dims.edge, top = 24.dp, bottom = 4.dp))
                    }
                    itemsIndexed(recentSearches, key = { _, s -> "pr$s" }) { _, s ->
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = Dims.edge - 8.dp)
                                .tvClickable(RoundedCornerShape(10.dp), scale = 1.02f) { query = s }
                                .padding(horizontal = 8.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Rounded.History, null, tint = T.secondary, modifier = Modifier.size(20.dp))
                            Spacer(Modifier.width(12.dp))
                            Text(s, color = T.text, fontSize = 16.sp)
                        }
                    }
                }
            }
            q.length < 2 -> LazyColumn(contentPadding = PaddingValues(bottom = bottomContentPadding)) {
                item {
                    Text(stringResource(R.string.popular_genres), style = heading(Dims.titleSize),
                        modifier = Modifier.padding(start = Dims.edge, end = Dims.edge, top = 16.dp, bottom = 10.dp))
                    FlowRow(Modifier.padding(horizontal = Dims.edge), horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        GENRE_TAGS.forEach { tag ->
                            Chip(stringResource(PlaybackService.genreLabel(tag))) {
                                Nav.grid(GridSource.Tag(tag, if (worldwide) null else cc))
                            }
                        }
                    }
                }
                if (recentSearches.isNotEmpty()) {
                    item {
                        Row(Modifier.fillMaxWidth().padding(start = Dims.edge, end = Dims.edge, top = 24.dp, bottom = 4.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.recent_searches), style = heading(Dims.titleSize), modifier = Modifier.weight(1f))
                            Text(stringResource(R.string.clear), color = T.accent, fontWeight = FontWeight.Bold,
                                modifier = Modifier.tvClickable(RoundedCornerShape(50)) { Library.clearSearches() }
                                    .padding(horizontal = 10.dp, vertical = 6.dp))
                        }
                    }
                    itemsIndexed(recentSearches, key = { _, s -> "r$s" }) { _, s ->
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = Dims.edge - 8.dp)
                                .tvClickable(RoundedCornerShape(10.dp), scale = 1.02f) { query = s }
                                .padding(horizontal = 8.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Rounded.History, null, tint = T.secondary, modifier = Modifier.size(20.dp))
                            Spacer(Modifier.width(12.dp))
                            Text(s, color = T.text, fontSize = 16.sp)
                        }
                    }
                }
            }
            failed -> ErrorRetry(onRetry = { attempt++ })
            results == null -> SkeletonList()
            results!!.isEmpty() -> Text(stringResource(R.string.no_results), color = T.secondary, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(32.dp))
            else -> {
                val list = results!!
                LazyColumn(contentPadding = PaddingValues(start = Dims.edge - 8.dp, end = Dims.edge - 8.dp, bottom = bottomContentPadding)) {
                    itemsIndexed(list, key = { _, s -> s.uuid }) { _, s -> StationRow(s, list) }
                }
            }
        }
    }
}

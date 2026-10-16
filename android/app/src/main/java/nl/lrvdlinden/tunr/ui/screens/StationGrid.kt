package nl.lrvdlinden.tunr.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.data.localizedCountryName
import nl.lrvdlinden.tunr.player.PlaybackService
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.ErrorRetry
import nl.lrvdlinden.tunr.ui.GridSource
import nl.lrvdlinden.tunr.ui.PillButton
import nl.lrvdlinden.tunr.ui.SkeletonRow
import nl.lrvdlinden.tunr.ui.StationCard
import nl.lrvdlinden.tunr.ui.StationRow
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.TopBar
import nl.lrvdlinden.tunr.ui.bottomContentPadding
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.rememberLoad
import nl.lrvdlinden.tunr.ui.stationCount

/** Rasterpagina ("Alles", genre, regio, taal, Top 100 genummerd als lijst) */
@Composable
fun StationGridScreen(source: GridSource, onClose: () -> Unit) {
    val favorites by Library.favorites.collectAsState()
    val recents by Library.recents.collectAsState()
    val region by Library.localRegion.collectAsState()

    val load = rememberLoad(source) {
        when (source) {
            is GridSource.Popular -> RadioBrowser.popular(source.cc, 100)
            is GridSource.Trending -> RadioBrowser.trending(source.cc, 100)
            is GridSource.Tag -> RadioBrowser.byTag(source.tag, source.cc, 100)
            is GridSource.Region -> RadioBrowser.byState(source.cc, source.state, 100)
            is GridSource.Language -> RadioBrowser.byLanguage(source.name, 100)
            GridSource.Top100 -> RadioBrowser.top100()
            GridSource.Favorites, GridSource.Recents -> emptyList()
        }
    }
    val stations: List<Station>? = when (source) {
        GridSource.Favorites -> favorites
        GridSource.Recents -> recents
        else -> load.value
    }
    val title = when (source) {
        is GridSource.Popular -> stringResource(R.string.popular_in, localizedCountryName(source.cc, source.cc))
        is GridSource.Trending -> stringResource(R.string.trending)
        is GridSource.Tag -> stringResource(PlaybackService.genreLabel(source.tag)) +
            (if (source.cc == null) " · " + stringResource(R.string.worldwide) else "")
        is GridSource.Region -> source.state
        is GridSource.Language -> source.label
        GridSource.Top100 -> stringResource(R.string.browse_top100)
        GridSource.Favorites -> stringResource(R.string.your_favorites)
        GridSource.Recents -> stringResource(R.string.continue_listening)
    }
    val numbered = source == GridSource.Top100
    val first = rememberInitialFocus(key = stations?.isNotEmpty() == true)

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        TopBar(title, onBack = onClose)
        val list = stations
        when {
            list == null && load.failed -> ErrorRetry(onRetry = load.retry, focusRequester = first)
            list == null -> Column { repeat(3) { SkeletonRow(); Spacer(Modifier.padding(8.dp)) } }
            list.isEmpty() -> Text(stringResource(R.string.no_stations), color = T.secondary, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(32.dp))
            numbered -> LazyColumn(contentPadding = PaddingValues(start = Dims.edge - 8.dp, end = Dims.edge - 8.dp, bottom = bottomContentPadding)) {
                itemsIndexed(list, key = { _, s -> s.uuid }) { i, s ->
                    StationRow(s, list, number = i + 1, focusRequester = if (i == 0) first else null)
                }
            }
            else -> {
                val min: Dp = if (Device.isTV) 150.dp else if (isWide()) 150.dp else 104.dp
                LazyVerticalGrid(
                    columns = if (Device.isTV) GridCells.Fixed(6) else GridCells.Adaptive(min),
                    contentPadding = PaddingValues(start = Dims.edge, end = Dims.edge, top = 4.dp, bottom = bottomContentPadding),
                    horizontalArrangement = Arrangement.spacedBy(Dims.rowGap),
                    verticalArrangement = Arrangement.spacedBy(if (Device.isTV) 24.dp else 16.dp),
                ) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 4.dp)) {
                            PillButton(stringResource(R.string.play), Icons.Rounded.PlayArrow, small = true) {
                                RadioController.play(list.first(), list)
                            }
                            PillButton(stringResource(R.string.shuffle), Icons.Rounded.Shuffle, primary = false, small = true) {
                                val shuffled = list.shuffled(); RadioController.play(shuffled.first(), shuffled)
                            }
                            if (source is GridSource.Region) {
                                val mine = region == source.state
                                PillButton(
                                    stringResource(if (mine) R.string.my_region else R.string.make_my_region),
                                    if (mine) Icons.Rounded.Check else Icons.Rounded.Place, primary = false, small = true
                                ) { Library.setLocalRegion(source.state) }
                            }
                            Spacer(Modifier.width(4.dp))
                            Text(stationCount(list.size), color = T.secondary, modifier = Modifier.padding(top = 8.dp))
                        }
                    }
                    itemsIndexed(list, key = { _, s -> s.uuid }) { i, s ->
                        StationCard(s, list, width = Dp.Unspecified, focusRequester = if (i == 0) first else null)
                    }
                }
            }
        }
    }
}

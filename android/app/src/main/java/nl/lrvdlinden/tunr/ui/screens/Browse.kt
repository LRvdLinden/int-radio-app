package nl.lrvdlinden.tunr.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Church
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Nightlight
import androidx.compose.material.icons.rounded.Piano
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.SportsSoccer
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Translate
import androidx.compose.material.icons.rounded.Whatshot
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.Audiotrack
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.LocaleHelper
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.MUSIC_TAGS
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.localizedCountryName
import nl.lrvdlinden.tunr.player.PlaybackService
import nl.lrvdlinden.tunr.ui.AppState
import nl.lrvdlinden.tunr.ui.BrowseTile
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.ErrorRetry
import nl.lrvdlinden.tunr.ui.GridSource
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.Route
import nl.lrvdlinden.tunr.ui.SkeletonList
import nl.lrvdlinden.tunr.ui.StationRowSection
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.Tab
import nl.lrvdlinden.tunr.ui.TopBar
import nl.lrvdlinden.tunr.ui.bottomContentPadding
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.rememberLoad
import nl.lrvdlinden.tunr.ui.stationCount
import nl.lrvdlinden.tunr.ui.tvClickable

/** Huidige landcode (gekozen land, anders dat van het toestel) */
@Composable
fun currentCountryCode(): String {
    val country by Library.country.collectAsState()
    return country?.code ?: LocaleHelper.deviceCountry().ifEmpty { "NL" }
}

private data class Tile(val title: Int, val icon: ImageVector, val palette: Int, val action: () -> Unit)

/** Bladeren (SPEC §6): grote gekleurde tegels zoals TuneIn */
@Composable
fun BrowseScreen() {
    val region by Library.localRegion.collectAsState()
    val tiles = listOf(
        Tile(R.string.browse_local, Icons.Rounded.Place, 0) { Nav.push(Route.Regions) },
        Tile(R.string.browse_music, Icons.Rounded.MusicNote, 1) { Nav.push(Route.Music) },
        Tile(R.string.browse_news_talk, Icons.Rounded.Newspaper, 2) { Nav.push(Route.NewsTalk) },
        Tile(R.string.browse_sports, Icons.Rounded.SportsSoccer, 3) { Nav.grid(GridSource.Tag("sports", null)) },
        Tile(R.string.browse_language, Icons.Rounded.Translate, 4) { Nav.push(Route.Languages) },
        Tile(R.string.browse_world_map, Icons.Rounded.Public, 5) { AppState.tab = Tab.MAP },
        Tile(R.string.browse_top100, Icons.Rounded.EmojiEvents, 6) { Nav.grid(GridSource.Top100) },
    )
    val first = rememberInitialFocus()
    LazyVerticalGrid(
        columns = if (Device.isTV) GridCells.Fixed(4) else GridCells.Adaptive(160.dp),
        modifier = Modifier.fillMaxSize().background(T.bg),
        contentPadding = PaddingValues(start = Dims.edge, end = Dims.edge, bottom = bottomContentPadding),
        horizontalArrangement = Arrangement.spacedBy(Dims.rowGap),
        verticalArrangement = Arrangement.spacedBy(Dims.rowGap),
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Text(stringResource(R.string.tab_browse), style = heading(if (Device.isTV) 34.sp else 28.sp),
                modifier = Modifier.statusBarsPadding().padding(top = 16.dp, bottom = 4.dp))
        }
        itemsIndexed(tiles) { i, t ->
            BrowseTile(
                stringResource(t.title), t.icon, t.palette,
                Modifier.aspectRatio(1.35f),
                subtitle = if (t.title == R.string.browse_local) region else null,
                focusRequester = if (i == 0) first else null,
                onClick = t.action
            )
        }
    }
}

/** Lokaal → regio's van het land → zenders */
@Composable
fun RegionsScreen(onClose: () -> Unit) {
    val country by Library.country.collectAsState()
    val cc = currentCountryCode()
    val countryName = country?.name
    val region by Library.localRegion.collectAsState()
    val load = rememberLoad(cc, countryName) {
        val name = countryName ?: RadioBrowser.countries().firstOrNull { it.code.equals(cc, true) }?.name ?: cc
        RadioBrowser.states(name)
    }
    val first = rememberInitialFocus(key = load.value != null)
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        TopBar(stringResource(R.string.regions_in, localizedCountryName(cc, cc)), onBack = onClose)
        when {
            load.loading -> SkeletonList()
            load.failed -> ErrorRetry(onRetry = load.retry, focusRequester = first)
            load.value.isNullOrEmpty() -> Text(stringResource(R.string.no_regions), color = T.secondary,
                modifier = Modifier.padding(Dims.edge))
            else -> LazyColumn(contentPadding = PaddingValues(bottom = bottomContentPadding)) {
                itemsIndexed(load.value!!, key = { _, r -> r.name }) { i, r ->
                    ListRow(
                        title = r.name, subtitle = stationCount(r.stationCount),
                        icon = Icons.Rounded.Place, paletteIndex = i,
                        checked = r.name == region,
                        focus = if (i == 0) first else null,
                    ) {
                        Library.setLocalRegion(r.name) // laatst gekozen regio = de "Lokaal"-regio
                        Nav.grid(GridSource.Region(cc, r.name))
                    }
                }
            }
        }
    }
}

/** Muziek → genres als tegels */
@Composable
fun MusicScreen(onClose: () -> Unit) {
    val cc = currentCountryCode()
    val first = rememberInitialFocus()
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        TopBar(stringResource(R.string.browse_music), onBack = onClose)
        LazyVerticalGrid(
            columns = if (Device.isTV) GridCells.Fixed(5) else GridCells.Adaptive(150.dp),
            contentPadding = PaddingValues(start = Dims.edge, end = Dims.edge, top = 8.dp, bottom = bottomContentPadding),
            horizontalArrangement = Arrangement.spacedBy(Dims.rowGap),
            verticalArrangement = Arrangement.spacedBy(Dims.rowGap),
        ) {
            itemsIndexed(MUSIC_TAGS) { i, tag ->
                BrowseTile(stringResource(PlaybackService.genreLabel(tag)), genreIcon(tag), i, Modifier.aspectRatio(1.5f),
                    focusRequester = if (i == 0) first else null) { Nav.grid(GridSource.Tag(tag, cc)) }
            }
        }
    }
}

/** Nieuws & Talk: twee secties */
@Composable
fun NewsTalkScreen(onClose: () -> Unit) {
    val cc = currentCountryCode()
    val news = rememberLoad(cc) { RadioBrowser.byTag("news", cc) }
    val talk = rememberLoad(cc) { RadioBrowser.byTag("talk", cc) }
    val first = rememberInitialFocus(key = news.value != null)
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        TopBar(stringResource(R.string.browse_news_talk), onBack = onClose)
        LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = bottomContentPadding), verticalArrangement = Arrangement.spacedBy(Dims.sectionGap)) {
            item { StationRowSection(stringResource(R.string.genre_news), news, onSeeAll = { Nav.grid(GridSource.Tag("news", cc)) }, firstFocus = first) }
            item { StationRowSection(stringResource(R.string.genre_talk), talk, onSeeAll = { Nav.grid(GridSource.Tag("talk", cc)) }) }
            item { StationRowSection(stringResource(R.string.news_worldwide), rememberLoad("newsw") { RadioBrowser.byTag("news", null) },
                onSeeAll = { Nav.grid(GridSource.Tag("news", null)) }) }
        }
    }
}

/** Op taal → talen → zenders (wereldwijd) */
@Composable
fun LanguagesScreen(onClose: () -> Unit) {
    val load = rememberLoad(Unit) { RadioBrowser.languages() }
    val first = rememberInitialFocus(key = load.value != null)
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        TopBar(stringResource(R.string.browse_language), onBack = onClose)
        when {
            load.loading -> SkeletonList()
            load.failed -> ErrorRetry(onRetry = load.retry, focusRequester = first)
            else -> LazyColumn(contentPadding = PaddingValues(bottom = bottomContentPadding)) {
                itemsIndexed(load.value.orEmpty(), key = { _, l -> l.name }) { i, l ->
                    val label = l.localizedName
                    ListRow(label, stationCount(l.stationCount), Icons.Rounded.Translate, i, focus = if (i == 0) first else null) {
                        Nav.grid(GridSource.Language(l.name, label))
                    }
                }
            }
        }
    }
}

/** Rij met gekleurd rondje, titel, ondertitel en pijltje */
@Composable
fun ListRow(
    title: String,
    subtitle: String?,
    icon: ImageVector,
    paletteIndex: Int,
    checked: Boolean = false,
    focus: androidx.compose.ui.focus.FocusRequester? = null,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Dims.edge - 8.dp)
            .tvClickable(RoundedCornerShape(12.dp), scale = 1.02f, focusRequester = focus, onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(T.paletteBrush(paletteIndex)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = T.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, color = T.secondary, fontSize = 13.sp)
        }
        if (checked) Icon(Icons.Rounded.Check, null, tint = T.accent)
        else Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = T.secondary)
    }
}

fun genreIcon(tag: String): ImageVector = when (tag) {
    "pop" -> Icons.Rounded.Star
    "news" -> Icons.Rounded.Newspaper
    "rock" -> Icons.Rounded.Album
    "dance" -> Icons.Rounded.GraphicEq
    "jazz" -> Icons.Rounded.Audiotrack
    "classical" -> Icons.Rounded.Piano
    "hits" -> Icons.Rounded.Whatshot
    "talk" -> Icons.Rounded.Forum
    "sports" -> Icons.Rounded.SportsSoccer
    "oldies" -> Icons.Rounded.History
    "hiphop" -> Icons.Rounded.Mic
    "country" -> Icons.AutoMirrored.Rounded.QueueMusic
    "ambient" -> Icons.Rounded.Nightlight
    "christian" -> Icons.Rounded.Church
    else -> Icons.Rounded.Headphones
}

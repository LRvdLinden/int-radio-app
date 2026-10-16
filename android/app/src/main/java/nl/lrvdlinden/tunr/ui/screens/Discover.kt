package nl.lrvdlinden.tunr.ui.screens

import android.os.Build
import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerDefaults
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.LocaleHelper
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.GENRE_TAGS
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.PodcastApi
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.data.flagEmoji
import nl.lrvdlinden.tunr.data.localizedCountryName
import nl.lrvdlinden.tunr.player.PlaybackService
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.AppState
import nl.lrvdlinden.tunr.ui.CircleIconButton
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.EqualizerBars
import nl.lrvdlinden.tunr.ui.EpisodeRowSection
import nl.lrvdlinden.tunr.ui.ErrorRetry
import nl.lrvdlinden.tunr.ui.GenreChips
import nl.lrvdlinden.tunr.ui.GridSource
import nl.lrvdlinden.tunr.ui.LivePill
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.PillButton
import nl.lrvdlinden.tunr.ui.PodcastArt
import nl.lrvdlinden.tunr.ui.PodcastRowSection
import nl.lrvdlinden.tunr.ui.ProgressLine
import nl.lrvdlinden.tunr.ui.Route
import nl.lrvdlinden.tunr.ui.SectionHeader
import nl.lrvdlinden.tunr.ui.Skeleton
import nl.lrvdlinden.tunr.ui.StationArt
import nl.lrvdlinden.tunr.ui.StationRowSection
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.TunrLogo
import nl.lrvdlinden.tunr.ui.bottomContentPadding
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.rememberLoad
import nl.lrvdlinden.tunr.ui.tvClickable
import java.util.Calendar

/** Ontdek (SPEC §4 + §6): begroeting, hero top 6, rijen, genre-chips en twee genre-rijen. */
@Composable
fun DiscoverScreen() {
    val country by Library.country.collectAsState()
    val cc = country?.code ?: LocaleHelper.deviceCountry().ifEmpty { "NL" }
    val land = localizedCountryName(cc, country?.name ?: cc)
    val region by Library.localRegion.collectAsState()
    val recents by Library.recents.collectAsState()
    val favorites by Library.favorites.collectAsState()
    val current by RadioController.station.collectAsState()
    val currentEpisode by RadioController.episode.collectAsState()

    val popular = rememberLoad(cc) { RadioBrowser.popular(cc) }
    val trending = rememberLoad(cc) { RadioBrowser.trending(cc) }
    val local = rememberLoad(cc, region) { region?.let { RadioBrowser.byState(cc, it, 40) } ?: emptyList() }
    val genres = rememberLoad(cc) { RadioBrowser.topGenres(cc, 2) }

    // Podcasts (SPEC §8)
    val topPodcasts = rememberLoad(cc) { PodcastApi.topPodcasts(cc) }
    val followed by Library.followedPodcasts.collectAsState()
    val progress by Library.progress.collectAsState()
    val followedIds = followed.joinToString(",") { it.id }
    val newEpisodes = rememberLoad(cc, followedIds) { if (followed.isEmpty()) emptyList() else Library.newEpisodes(cc, followed) }
    val continueEpisodes = remember(progress) { Library.continueListening(progress) }

    // Favorieten op de achtergrond verversen (logo/stream kunnen veranderd zijn)
    LaunchedEffect(Unit) {
        val ids = Library.favorites.value.map { it.uuid }
        if (ids.isNotEmpty()) runCatching { Library.refreshFavorites(RadioBrowser.byUuids(ids)) }
    }

    val firstFocus = rememberInitialFocus(key = popular.value != null)

    LazyColumn(
        Modifier.fillMaxSize().background(T.bg),
        contentPadding = PaddingValues(bottom = bottomContentPadding),
        verticalArrangement = Arrangement.spacedBy(Dims.sectionGap)
    ) {
        item(key = "header") {
            Column(Modifier.statusBarsPadding()) {
                Header(cc)
                Text(greeting(), style = heading(if (Device.isTV) 34.sp else 28.sp),
                    modifier = Modifier.padding(horizontal = Dims.edge).padding(top = 4.dp))
            }
        }
        if (Device.isTV && current != null) {
            item(key = "nowplaying") { TvNowPlayingCard(current!!) }
        }
        if (Device.isTV && currentEpisode != null) {
            item(key = "nowplaying-episode") { TvEpisodeNowPlayingCard(currentEpisode!!) }
        }
        item(key = "hero") {
            val list = popular.value?.take(6)
            when {
                list != null && list.isNotEmpty() -> Hero(list, popular.value!!, firstFocus = if ((current == null && currentEpisode == null) || !Device.isTV) firstFocus else null)
                popular.failed -> ErrorRetry(onRetry = { popular.retry(); trending.retry() }, focusRequester = firstFocus)
                else -> Skeleton(Modifier.padding(horizontal = Dims.edge).fillMaxWidth().height(if (Device.isTV) 260.dp else 210.dp), Dims.cardRadius)
            }
        }
        if (recents.isNotEmpty()) item(key = "recent") {
            StationRowSection(stringResource(R.string.continue_listening), null, recents.take(15),
                onSeeAll = { Nav.grid(GridSource.Recents) })
        }
        item(key = "local") {
            if (region == null) PickRegionCard()
            else StationRowSection(stringResource(R.string.local_in, region!!), local,
                onSeeAll = { Nav.grid(GridSource.Region(cc, region!!)) })
        }
        item(key = "popular") {
            StationRowSection(stringResource(R.string.popular_in, land), popular, onSeeAll = { Nav.grid(GridSource.Popular(cc)) })
        }
        item(key = "trending") {
            StationRowSection(stringResource(R.string.trending), trending, onSeeAll = { Nav.grid(GridSource.Trending(cc)) })
        }
        item(key = "podcasts") {
            PodcastRowSection(stringResource(R.string.popular_podcasts_in, land), topPodcasts,
                onSeeAll = { Nav.push(Route.PodcastsHome) }, numbered = true)
        }
        if (followed.isNotEmpty()) item(key = "new-episodes") {
            EpisodeRowSection(stringResource(R.string.new_episodes), newEpisodes)
        }
        if (continueEpisodes.isNotEmpty()) item(key = "continue-episodes") {
            EpisodeRowSection(stringResource(R.string.continue_listening_podcasts), null, continueEpisodes)
        }
        if (favorites.isNotEmpty()) item(key = "favorites") {
            StationRowSection(stringResource(R.string.your_favorites), null, favorites.take(20),
                onSeeAll = { Nav.grid(GridSource.Favorites) })
        }
        item(key = "chips") {
            Column {
                SectionHeader(stringResource(R.string.genres))
                Spacer(Modifier.height(6.dp))
                GenreChips(GENRE_TAGS) { Nav.grid(GridSource.Tag(it, cc)) }
            }
        }
        genres.value?.forEach { tag ->
            item(key = "genre-$tag") { GenreRow(tag, cc) }
        }
    }
}

@Composable
private fun GenreRow(tag: String, cc: String) {
    val load = rememberLoad(tag, cc) { RadioBrowser.byTag(tag, cc, 30) }
    StationRowSection(stringResource(PlaybackService.genreLabel(tag)), load, onSeeAll = { Nav.grid(GridSource.Tag(tag, cc)) })
}

@Composable
private fun Header(cc: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Dims.edge, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TunrLogo(if (Device.isTV) 26.sp else 22.sp)
        Spacer(Modifier.weight(1f))
        // Landknop: vlag + code → landkeuze
        Row(
            Modifier.tvClickable(CircleShape) { Nav.push(Route.CountryPicker) }
                .background(T.surface).padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(flagEmoji(cc), fontSize = 18.sp)
            Spacer(Modifier.width(6.dp))
            Text(cc, color = T.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
        }
        if (!Device.isTV) {
            Spacer(Modifier.width(8.dp))
            CircleIconButton(Icons.Rounded.Settings, stringResource(R.string.settings), size = 40.dp, background = T.surface) {
                Nav.push(Route.Settings)
            }
        }
    }
}

@Composable
fun greeting(): String {
    val h = remember { Calendar.getInstance().get(Calendar.HOUR_OF_DAY) }
    return stringResource(
        when (h) {
            in 6..11 -> R.string.greeting_morning
            in 12..17 -> R.string.greeting_afternoon
            in 18..23 -> R.string.greeting_evening
            else -> R.string.greeting_night
        }
    )
}

/** Hero-carrousel: grote kaart met vervaagde cover, art, naam, genres, Luister + Info */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Hero(top: List<Station>, queue: List<Station>, firstFocus: androidx.compose.ui.focus.FocusRequester?) {
    if (Device.isTV || isWide()) {
        // Tv/tablet: rij grote kaarten (D-pad-vriendelijker dan een pager)
        LazyRow(
            contentPadding = PaddingValues(horizontal = Dims.edge, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(Dims.rowGap)
        ) {
            itemsIndexed(top, key = { _, s -> s.uuid }) { i, s ->
                HeroCard(s, queue, Modifier.width(if (Device.isTV) 460.dp else 420.dp), if (i == 0) firstFocus else null)
            }
        }
        return
    }
    val pager = rememberPagerState { top.size }
    // Automatisch doorschuiven
    LaunchedEffect(pager, top.size) {
        while (true) {
            delay(6_000)
            if (!pager.isScrollInProgress && top.size > 1) pager.animateScrollToPage((pager.currentPage + 1) % top.size)
        }
    }
    Column {
        HorizontalPager(
            state = pager,
            contentPadding = PaddingValues(horizontal = Dims.edge),
            pageSpacing = 12.dp,
            flingBehavior = PagerDefaults.flingBehavior(pager),
        ) { page -> HeroCard(top[page], queue, Modifier.fillMaxWidth(), if (page == 0) firstFocus else null) }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            repeat(top.size) { i ->
                Box(
                    Modifier.padding(horizontal = 3.dp).size(width = if (i == pager.currentPage) 18.dp else 6.dp, height = 6.dp)
                        .clip(CircleShape).background(if (i == pager.currentPage) T.accent else Color.White.copy(alpha = 0.25f))
                )
            }
        }
    }
}

@Composable
private fun HeroCard(s: Station, queue: List<Station>, modifier: Modifier, focus: androidx.compose.ui.focus.FocusRequester?) {
    val current by RadioController.station.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val isCurrent = current?.uuid == s.uuid
    val shape = RoundedCornerShape(Dims.cardRadius)
    Box(
        modifier
            .height(if (Device.isTV) 240.dp else 210.dp)
            .clip(shape)
            .background(T.paletteBrush(s.displayName))
    ) {
        // Vervaagde cover als achtergrond (blur vanaf Android 12, anders een donker verloop)
        if (Build.VERSION.SDK_INT >= 31) {
            StationArt(s, Modifier.fillMaxSize().graphicsLayer { scaleX = 1.6f; scaleY = 1.6f }.blur(40.dp), radius = 0.dp)
        }
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.75f), Color.Black.copy(alpha = 0.25f)))))
        Row(Modifier.fillMaxSize().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            StationArt(s, Modifier.size(if (Device.isTV) 180.dp else 150.dp), radius = 14.dp)
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    LivePill()
                    if (isCurrent && playing) { Spacer(Modifier.width(8.dp)); EqualizerBars() }
                }
                Spacer(Modifier.height(8.dp))
                Text(s.displayName, style = heading(if (Device.isTV) 26.sp else 22.sp), maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(s.genresLine.ifEmpty { s.placeLine() }, color = Color.White.copy(alpha = 0.8f), fontSize = 13.sp,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PillButton(
                        stringResource(if (isCurrent && playing) R.string.pause else R.string.listen),
                        if (isCurrent && playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                        small = !Device.isTV, focusRequester = focus
                    ) { if (isCurrent) RadioController.togglePlay() else RadioController.play(s, queue) }
                    PillButton(stringResource(R.string.info), Icons.Rounded.Info, primary = false, small = !Device.isTV) { Nav.station(s) }
                }
            }
        }
    }
}

/** "Kies je regio" zolang er geen lokale regio is */
@Composable
private fun PickRegionCard() {
    Column {
        SectionHeader(stringResource(R.string.local))
        Spacer(Modifier.height(10.dp))
        Row(
            Modifier.padding(horizontal = Dims.edge).fillMaxWidth()
                .tvClickable(RoundedCornerShape(Dims.cardRadius), scale = 1.03f) { Nav.push(Route.Regions) }
                .background(T.surface).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(Modifier.size(48.dp).clip(CircleShape).background(T.accentBrush), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Place, null, tint = Color.White)
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.pick_region), color = T.text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.pick_region_hint), color = T.secondary, fontSize = 13.sp)
            }
        }
    }
}

/** Tv: "Nu aan het spelen"-kaart bovenaan Ontdek (er is geen miniplayer) */
@Composable
private fun TvNowPlayingCard(s: Station) {
    val playing by RadioController.isPlaying.collectAsState()
    val np by RadioController.nowPlaying.collectAsState()
    val art by RadioController.artwork.collectAsState()
    Row(
        Modifier.padding(horizontal = Dims.edge).fillMaxWidth()
            .tvClickable(RoundedCornerShape(Dims.cardRadius), scale = 1.02f, focusRequester = rememberInitialFocus(key = s.uuid)) {
                AppState.showPlayer = true
            }
            .background(T.elevated).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StationArt(s, Modifier.size(96.dp), radius = 14.dp, overrideUrl = art)
        Spacer(Modifier.width(18.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.now_playing_tv).uppercase(), color = T.accent, fontSize = 13.sp,
                    fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                Spacer(Modifier.width(10.dp))
                EqualizerBars(playing = playing)
            }
            Text(s.displayName, style = heading(24.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(np?.line ?: s.genresLine.ifEmpty { s.placeLine() }, color = T.secondary, fontSize = 15.sp, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
        }
        Box(Modifier.size(56.dp).clip(CircleShape).background(T.accent).aspectRatio(1f), contentAlignment = Alignment.Center) {
            Icon(if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(30.dp))
        }
    }
}

/** Tv: "Nu aan het spelen"-kaart voor een aflevering (titel, podcast, voortgang) */
@Composable
private fun TvEpisodeNowPlayingCard(e: nl.lrvdlinden.tunr.data.Episode) {
    val playing by RadioController.isPlaying.collectAsState()
    val position by RadioController.position.collectAsState()
    val duration by RadioController.duration.collectAsState()
    Row(
        Modifier.padding(horizontal = Dims.edge).fillMaxWidth()
            .tvClickable(RoundedCornerShape(Dims.cardRadius), scale = 1.02f, focusRequester = rememberInitialFocus(key = e.id)) {
                AppState.showPlayer = true
            }
            .background(T.elevated).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        PodcastArt(e.art, e.podcastName, Modifier.size(96.dp), radius = 14.dp)
        Spacer(Modifier.width(18.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.now_playing_tv).uppercase(), color = T.accent, fontSize = 13.sp,
                    fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                Spacer(Modifier.width(10.dp))
                EqualizerBars(playing = playing)
            }
            Text(e.displayTitle, style = heading(24.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(e.podcastName, color = T.secondary, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(8.dp))
            ProgressLine(if (duration > 0) position.toFloat() / duration else 0f, Modifier.fillMaxWidth(0.6f))
        }
        Box(Modifier.size(56.dp).clip(CircleShape).background(T.accent), contentAlignment = Alignment.Center) {
            Icon(if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(30.dp))
        }
    }
}

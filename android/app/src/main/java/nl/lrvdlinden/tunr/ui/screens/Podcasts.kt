package nl.lrvdlinden.tunr.ui.screens

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Podcasts
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Episode
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.PODCAST_GENRE_IDS
import nl.lrvdlinden.tunr.data.Podcast
import nl.lrvdlinden.tunr.data.PodcastApi
import nl.lrvdlinden.tunr.data.localizedCountryName
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.BrowseTile
import nl.lrvdlinden.tunr.ui.Chip
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.EmptyState
import nl.lrvdlinden.tunr.ui.EpisodeRow
import nl.lrvdlinden.tunr.ui.ErrorRetry
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.PillButton
import nl.lrvdlinden.tunr.ui.PodcastArt
import nl.lrvdlinden.tunr.ui.PodcastCard
import nl.lrvdlinden.tunr.ui.PodcastRow
import nl.lrvdlinden.tunr.ui.ProgressLine
import nl.lrvdlinden.tunr.ui.Route
import nl.lrvdlinden.tunr.ui.SectionHeader
import nl.lrvdlinden.tunr.ui.SkeletonList
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.TopBar
import nl.lrvdlinden.tunr.ui.bottomContentPadding
import nl.lrvdlinden.tunr.ui.episodeCount
import nl.lrvdlinden.tunr.ui.formatDurationShort
import nl.lrvdlinden.tunr.ui.formatEpisodeDate
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.podcastGenreIcon
import nl.lrvdlinden.tunr.ui.podcastGenreLabel
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.rememberLoad
import nl.lrvdlinden.tunr.ui.tvClickable

// MARK: podcastoverzicht

/** Podcastoverzicht (vanuit Bladeren, SPEC §8): zoeken, genre-tegels, toplijst van je land (1–50) */
@Composable
fun PodcastsHomeScreen(onClose: () -> Unit) {
    val cc = currentCountryCode()
    val land = localizedCountryName(cc, cc)
    var query by rememberSaveable { mutableStateOf("") }
    val top = rememberLoad(cc) { PodcastApi.topPodcasts(cc) }
    val first = rememberInitialFocus()

    Column(Modifier.fillMaxSize().background(T.bg).statusBarsPadding()) {
        TopBar(stringResource(R.string.podcasts), onBack = onClose)
        SearchField(query, { query = it }, stringResource(R.string.search_podcasts_placeholder),
            Modifier.padding(horizontal = Dims.edge, vertical = 8.dp).widthIn(max = 720.dp), focusRequester = first)
        if (query.trim().length >= 2) {
            PodcastSearchResults(query, cc)
            return@Column
        }
        LazyColumn(
            contentPadding = PaddingValues(top = 8.dp, bottom = bottomContentPadding),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            item(key = "genres-title") {
                SectionHeader(stringResource(R.string.podcast_genres))
                Spacer(Modifier.height(10.dp))
            }
            item(key = "genres") {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = Dims.edge, vertical = if (Device.isTV) 10.dp else 0.dp),
                    horizontalArrangement = Arrangement.spacedBy(Dims.rowGap)
                ) {
                    itemsIndexed(PODCAST_GENRE_IDS, key = { _, id -> id }) { i, id ->
                        BrowseTile(stringResource(podcastGenreLabel(id)), podcastGenreIcon(id), i,
                            Modifier.width(if (Device.isTV) 200.dp else 160.dp).aspectRatio(1.5f)) {
                            Nav.push(Route.PodcastGenre(id))
                        }
                    }
                }
            }
            item(key = "top-title") {
                Spacer(Modifier.height(Dims.sectionGap))
                SectionHeader(stringResource(R.string.top_podcasts_in, land))
                Spacer(Modifier.height(6.dp))
            }
            podcastList(top.value, top.failed, top.retry, numbered = true)
        }
    }
}

/** Genummerde lijst podcasts als items van een LazyColumn (laden/fout inbegrepen) */
private fun LazyListScope.podcastList(
    list: List<Podcast>?,
    failed: Boolean,
    retry: () -> Unit,
    numbered: Boolean,
    firstFocus: FocusRequester? = null,
) {
    when {
        list == null && failed -> item { ErrorRetry(message = stringResource(R.string.error_loading_podcasts), onRetry = retry, compact = true) }
        list == null -> item { SkeletonList() }
        list.isEmpty() -> item {
            Text(stringResource(R.string.no_podcasts), color = T.secondary, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(32.dp))
        }
        else -> itemsIndexed(list, key = { _, p -> "p" + p.id }) { i, p ->
            PodcastRow(p, Modifier.padding(horizontal = Dims.edge - 8.dp), number = if (numbered) i + 1 else null,
                focusRequester = if (i == 0) firstFocus else null)
        }
    }
}

/** Toplijst van één genre */
@Composable
fun PodcastGenreScreen(genreId: Int, onClose: () -> Unit) {
    val cc = currentCountryCode()
    val load = rememberLoad(cc, genreId) { PodcastApi.topByGenre(cc, genreId) }
    val first = rememberInitialFocus(key = load.value != null)
    Column(Modifier.fillMaxSize().background(T.bg).statusBarsPadding()) {
        TopBar(stringResource(podcastGenreLabel(genreId)), onBack = onClose)
        if (load.failed && load.value == null) {
            ErrorRetry(message = stringResource(R.string.error_loading_podcasts), onRetry = load.retry, focusRequester = first)
            return@Column
        }
        LazyColumn(contentPadding = PaddingValues(top = 4.dp, bottom = bottomContentPadding)) {
            podcastList(load.value, load.failed, load.retry, numbered = true, firstFocus = first)
        }
    }
}

/** Zoekresultaten podcasts (iTunes, debounce 350 ms); gebruikt door Zoeken en het podcastoverzicht */
@Composable
fun PodcastSearchResults(query: String, cc: String) {
    var results by remember { mutableStateOf<List<Podcast>?>(null) }
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }
    LaunchedEffect(query, cc, attempt) {
        val q = query.trim()
        failed = false
        if (q.length < 2) { results = null; return@LaunchedEffect }
        delay(350)
        results = null
        try {
            results = PodcastApi.search(q, cc)
            Library.addSearch(q)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            failed = true
        }
    }
    when {
        failed -> ErrorRetry(message = stringResource(R.string.error_loading_podcasts), onRetry = { attempt++ })
        results == null -> SkeletonList()
        results!!.isEmpty() -> Text(stringResource(R.string.no_results), color = T.secondary, textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(32.dp))
        else -> {
            val list = results!!
            LazyColumn(contentPadding = PaddingValues(start = Dims.edge - 8.dp, end = Dims.edge - 8.dp, bottom = bottomContentPadding)) {
                itemsIndexed(list, key = { _, p -> p.id }) { _, p -> PodcastRow(p) }
            }
        }
    }
}

// MARK: podcastpagina

/**
 * Podcastpagina (SPEC §8): grote art, titel, maker, genre, aantal afleveringen, Volgen/Volgend, uitklapbare
 * beschrijving, Speel nieuwste, afleveringen (Nieuwste/Oudste). Tablet/tv: twee kolommen.
 */
@Composable
fun PodcastDetailScreen(podcast: Podcast, onClose: () -> Unit) {
    val cc = currentCountryCode()
    val load = rememberLoad(podcast.id, cc) { PodcastApi.lookup(podcast.id, cc) }
    val full: Podcast = load.value?.first?.let { fresh ->
        // gegevens uit de toplijst aanvullen met die uit Lookup
        fresh.copy(
            name = fresh.name.ifEmpty { podcast.name },
            artist = fresh.artist.ifEmpty { podcast.artist },
            artwork = fresh.artwork.ifEmpty { podcast.artwork },
            genre = fresh.genre.ifEmpty { podcast.genre },
        )
    } ?: podcast
    val episodes: List<Episode>? = load.value?.second
    var newestFirst by rememberSaveable { mutableStateOf(true) }
    val sorted = remember(episodes, newestFirst) { episodes?.let { if (newestFirst) it else it.reversed() } }
    val description = rememberLoad(full.feedUrl) { PodcastApi.feedDescription(full.feedUrl) }
    val playFocus = rememberInitialFocus(key = podcast.id)
    val wide = isWide()

    // Gevolgde podcast bijwerken (art, aantal afleveringen, feed)
    LaunchedEffect(load.value) { load.value?.first?.let { if (Library.isFollowing(it.id)) Library.refreshFollowed(full) } }

    val header: @Composable () -> Unit = {
        PodcastHeader(full, episodes, description.value, wide, playFocus)
    }

    if (wide) {
        Row(Modifier.fillMaxSize().background(T.bg).statusBarsPadding()) {
            Column(Modifier.weight(0.42f).fillMaxHeight()) {
                TopBar("", onBack = onClose)
                LazyColumn(contentPadding = PaddingValues(start = Dims.edge, end = 16.dp, bottom = bottomContentPadding)) {
                    item { header() }
                }
            }
            Column(Modifier.weight(0.58f).fillMaxHeight()) {
                Spacer(Modifier.height(if (Device.isTV) 24.dp else 56.dp))
                EpisodesHeader(episodes?.size, newestFirst) { newestFirst = it }
                LazyColumn(contentPadding = PaddingValues(start = 8.dp, end = Dims.edge - 8.dp, bottom = bottomContentPadding)) {
                    episodeItems(sorted, load.failed, load.retry)
                }
            }
        }
    } else {
        LazyColumn(
            Modifier.fillMaxSize().background(T.bg),
            contentPadding = PaddingValues(bottom = bottomContentPadding)
        ) {
            item { Box(Modifier.statusBarsPadding()) { TopBar("", onBack = onClose) } }
            item { Box(Modifier.padding(horizontal = Dims.edge)) { header() } }
            item {
                Spacer(Modifier.height(Dims.sectionGap))
                EpisodesHeader(episodes?.size, newestFirst) { newestFirst = it }
            }
            episodeItems(sorted, load.failed, load.retry, horizontalPadding = true)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PodcastHeader(p: Podcast, episodes: List<Episode>?, description: String?, wide: Boolean, playFocus: FocusRequester) {
    val followed by Library.followedPodcasts.collectAsState()
    val following = followed.any { it.id == p.id }
    val currentEp by RadioController.episode.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val newest = episodes?.firstOrNull()
    val isNewestPlaying = newest != null && currentEp?.id == newest.id && playing
    val hAlign = if (wide) Alignment.Start else Alignment.CenterHorizontally
    val tAlign = if (wide) TextAlign.Start else TextAlign.Center

    Column(Modifier.fillMaxWidth(), horizontalAlignment = hAlign) {
        PodcastArt(p.artwork, p.displayName, Modifier.size(if (Device.isTV) 260.dp else if (wide) 240.dp else 220.dp), radius = 20.dp)
        Spacer(Modifier.height(18.dp))
        Text(p.displayName, style = heading(if (Device.isTV) 32.sp else 26.sp), textAlign = tAlign, maxLines = 3, overflow = TextOverflow.Ellipsis)
        if (p.artist.isNotBlank()) {
            Spacer(Modifier.height(4.dp))
            Text(p.artist, color = T.accent, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, textAlign = tAlign, maxLines = 2)
        }
        val count = if (p.trackCount > 0) p.trackCount else episodes?.size ?: 0
        val meta = listOfNotNull(p.genre.takeIf { it.isNotBlank() }, if (count > 0) episodeCount(count) else null).joinToString(" · ")
        if (meta.isNotEmpty()) {
            Spacer(Modifier.height(4.dp))
            Text(meta, color = T.secondary, fontSize = 14.sp, textAlign = tAlign)
        }
        Spacer(Modifier.height(16.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp, if (wide) Alignment.Start else Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            PillButton(
                stringResource(if (isNewestPlaying) R.string.pause else R.string.play_latest),
                if (isNewestPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
            ) {
                if (newest == null) return@PillButton
                if (currentEp?.id == newest.id) RadioController.togglePlay() else RadioController.playEpisode(newest, episodes.orEmpty())
            }
            // Favoriet (hartje, zoals bij zenders); zelfde opslag als "volgen". TV: krijgt als eerste de focus.
            PillButton(
                stringResource(if (following) R.string.following else R.string.follow),
                if (following) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                primary = false,
                focusRequester = playFocus,
                iconTint = if (following) T.accent else Color.White,
            ) { Library.toggleFollow(p) }
        }
        if (!description.isNullOrBlank()) {
            Spacer(Modifier.height(16.dp))
            ExpandableText(description, wide)
        }
    }
}

/** Beschrijving: 3 regels, tik = alles */
@Composable
private fun ExpandableText(text: String, alignStart: Boolean) {
    var expanded by rememberSaveable(text) { mutableStateOf(false) }
    Column(
        Modifier.widthIn(max = 640.dp).fillMaxWidth()
            .tvClickable(RoundedCornerShape(12.dp), scale = 1.02f) { expanded = !expanded }
            .padding(8.dp)
            .animateContentSize(),
        horizontalAlignment = if (alignStart) Alignment.Start else Alignment.CenterHorizontally
    ) {
        Text(text, color = T.secondary, fontSize = 14.sp, lineHeight = 20.sp, maxLines = if (expanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis, textAlign = if (alignStart) TextAlign.Start else TextAlign.Center)
        Text(stringResource(if (expanded) R.string.show_less else R.string.show_more), color = T.accent,
            fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 4.dp))
    }
}

/** "12 afleveringen" + sorteren Nieuwste/Oudste */
@Composable
private fun EpisodesHeader(count: Int?, newestFirst: Boolean, onSort: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = Dims.edge), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.episodes), style = heading(Dims.titleSize))
            if (count != null && count > 0) Text(episodeCount(count), color = T.secondary, fontSize = 13.sp)
        }
        Chip(stringResource(R.string.sort_newest), selected = newestFirst) { onSort(true) }
        Spacer(Modifier.width(8.dp))
        Chip(stringResource(R.string.sort_oldest), selected = !newestFirst) { onSort(false) }
    }
    Spacer(Modifier.height(8.dp))
}

private fun LazyListScope.episodeItems(
    list: List<Episode>?,
    failed: Boolean,
    retry: () -> Unit,
    horizontalPadding: Boolean = false,
) {
    val pad = if (horizontalPadding) Modifier.padding(horizontal = Dims.edge - 8.dp) else Modifier
    when {
        list == null && failed -> item { ErrorRetry(message = stringResource(R.string.error_loading_podcasts), onRetry = retry, compact = true) }
        list == null -> item { SkeletonList(6) }
        list.isEmpty() -> item {
            Text(stringResource(R.string.no_episodes), color = T.secondary, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(32.dp))
        }
        else -> itemsIndexed(list, key = { _, e -> e.id }) { _, e -> EpisodeRow(e, list, pad) }
    }
}

// MARK: afleveringspagina

/** Afleveringspagina (SPEC §8): titel, podcast, datum, duur, volledige omschrijving, Afspelen */
@Composable
fun EpisodeDetailScreen(episode: Episode, queue: List<Episode>, onClose: () -> Unit) {
    val current by RadioController.episode.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val progress by Library.progress.collectAsState()
    val p = progress[episode.id]
    val isCurrent = current?.id == episode.id
    val playFocus = rememberInitialFocus(key = episode.id)
    val wide = isWide()

    LazyColumn(Modifier.fillMaxSize().background(T.bg), contentPadding = PaddingValues(bottom = bottomContentPadding)) {
        item { Box(Modifier.statusBarsPadding()) { TopBar("", onBack = onClose) } }
        item {
            val info: @Composable () -> Unit = {
                Column(horizontalAlignment = if (wide) Alignment.Start else Alignment.CenterHorizontally) {
                    Text(
                        episode.podcastName, color = T.accent, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.tvClickable(RoundedCornerShape(8.dp), scale = 1.03f) { Nav.podcast(episode.podcast()) }
                            .padding(horizontal = 4.dp, vertical = 2.dp)
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(episode.displayTitle, style = heading(if (Device.isTV) 30.sp else 24.sp),
                        textAlign = if (wide) TextAlign.Start else TextAlign.Center)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        listOf(formatEpisodeDate(episode.releaseDate), formatDurationShort(episode.durationMs))
                            .filter { it.isNotBlank() }.joinToString(" · "),
                        color = T.secondary, fontSize = 14.sp
                    )
                    if (p != null && p.inProgress) {
                        Spacer(Modifier.height(10.dp))
                        ProgressLine(p.fraction, Modifier.width(200.dp))
                    }
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        PillButton(
                            stringResource(
                                when {
                                    isCurrent && playing -> R.string.pause
                                    p != null && p.inProgress -> R.string.resume
                                    else -> R.string.play
                                }
                            ),
                            if (isCurrent && playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                            focusRequester = playFocus
                        ) { if (isCurrent) RadioController.togglePlay() else RadioController.playEpisode(episode, queue) }
                        val finished = p?.finished == true
                        PillButton(
                            stringResource(if (finished) R.string.mark_unplayed else R.string.mark_played),
                            if (finished) Icons.Rounded.RadioButtonUnchecked else Icons.Rounded.CheckCircle,
                            primary = false
                        ) { Library.markFinished(episode, !finished) }
                    }
                }
            }
            if (wide) {
                Row(Modifier.padding(horizontal = Dims.edge), verticalAlignment = Alignment.Top) {
                    PodcastArt(episode.art, episode.podcastName, Modifier.size(if (Device.isTV) 260.dp else 240.dp), radius = Dims.cardRadius)
                    Spacer(Modifier.width(32.dp))
                    Box(Modifier.weight(1f)) { info() }
                }
            } else {
                Column(Modifier.fillMaxWidth().padding(horizontal = Dims.edge), horizontalAlignment = Alignment.CenterHorizontally) {
                    PodcastArt(episode.art, episode.podcastName, Modifier.size(220.dp), radius = 20.dp)
                    Spacer(Modifier.height(18.dp))
                    info()
                }
            }
        }
        val text = episode.fullDescription
        if (text.isNotEmpty()) item {
            Column(Modifier.padding(horizontal = Dims.edge).padding(top = Dims.sectionGap).widthIn(max = 760.dp)) {
                Text(stringResource(R.string.about_episode), style = heading(Dims.titleSize))
                Spacer(Modifier.height(8.dp))
                Text(
                    text, color = T.text.copy(alpha = 0.85f), fontSize = 15.sp, lineHeight = 22.sp,
                    // tv: focusbaar zodat je met de D-pad door lange teksten kunt scrollen
                    modifier = if (Device.isTV) Modifier.clip(RoundedCornerShape(12.dp))
                        .tvClickable(RoundedCornerShape(12.dp), scale = 1.0f) {}.padding(8.dp) else Modifier
                )
            }
        }
    }
}

// MARK: bibliotheek → podcasts

/** Bibliotheek, segment Podcasts: Verder luisteren bovenaan + gevolgde podcasts als raster */
@Composable
fun LibraryPodcasts(firstFocus: FocusRequester? = null) {
    val followed by Library.followedPodcasts.collectAsState()
    val progress by Library.progress.collectAsState()
    val cont = remember(progress) { Library.continueListening(progress) }
    if (followed.isEmpty() && cont.isEmpty()) {
        EmptyState(Icons.Rounded.Podcasts, stringResource(R.string.no_podcasts_title), stringResource(R.string.no_podcasts_message))
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            PillButton(stringResource(R.string.discover_podcasts), focusRequester = firstFocus) { Nav.push(Route.PodcastsHome) }
        }
        return
    }
    val min = if (isWide()) 150.dp else 104.dp
    LazyVerticalGrid(
        columns = if (Device.isTV) GridCells.Fixed(6) else GridCells.Adaptive(min),
        contentPadding = PaddingValues(start = Dims.edge, end = Dims.edge, top = 4.dp, bottom = bottomContentPadding),
        horizontalArrangement = Arrangement.spacedBy(Dims.rowGap),
        verticalArrangement = Arrangement.spacedBy(if (Device.isTV) 24.dp else 16.dp),
    ) {
        if (cont.isNotEmpty()) {
            item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                Column(Modifier.padding(bottom = 8.dp)) {
                    Text(stringResource(R.string.continue_listening), style = heading(Dims.titleSize))
                    Spacer(Modifier.height(4.dp))
                    cont.take(5).forEach { e -> EpisodeRow(e, cont) }
                }
            }
        }
        if (followed.isNotEmpty()) {
            item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.followed_podcasts), style = heading(Dims.titleSize), modifier = Modifier.weight(1f))
                    Text(stringResource(R.string.discover_podcasts), color = T.accent, fontWeight = FontWeight.Bold, fontSize = 14.sp,
                        modifier = Modifier.tvClickable(RoundedCornerShape(50)) { Nav.push(Route.PodcastsHome) }
                            .padding(horizontal = 10.dp, vertical = 6.dp))
                }
            }
            itemsIndexed(followed, key = { _, p -> p.id }) { i, p ->
                PodcastCard(p, width = androidx.compose.ui.unit.Dp.Unspecified,
                    focusRequester = if (i == 0 && cont.isEmpty()) firstFocus else null)
            }
        }
    }
}

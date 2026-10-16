package nl.lrvdlinden.tunr.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChildCare
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.FitnessCenter
import androidx.compose.material.icons.rounded.Gavel
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Mood
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.People
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.SportsSoccer
import androidx.compose.material.icons.rounded.Work
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.compose.AsyncImagePainter
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Episode
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.Podcast
import nl.lrvdlinden.tunr.player.RadioController
import java.text.DateFormat
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

// MARK: art

/**
 * Vierkante podcastcover in de StationArt-stijl: de afbeelding vult de hele tegel; tijdens laden, zonder art of
 * als laden mislukt: verloop uit het palet (hash van de naam) met monogram.
 */
@Composable
fun PodcastArt(url: String?, name: String, modifier: Modifier = Modifier, radius: Dp = 14.dp) {
    val (c1, c2) = T.palette(name)
    val src = url?.trim()?.takeIf { it.startsWith("http") }
    var failed by remember(src) { mutableStateOf(false) }
    var loaded by remember(src) { mutableStateOf(false) }
    Box(
        modifier.aspectRatio(1f).clip(RoundedCornerShape(radius)).background(Brush.linearGradient(listOf(c1, c2))),
        contentAlignment = Alignment.Center
    ) {
        if (src == null || failed) {
            ArtMonogram(name)
        } else {
            if (!loaded) ArtMonogram(name)
            AsyncImage(
                model = src, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                onState = {
                    if (it is AsyncImagePainter.State.Success) loaded = true
                    if (it is AsyncImagePainter.State.Error) failed = true
                }
            )
        }
    }
}

@Composable
private fun ArtMonogram(name: String) {
    val letters = name.split(' ', '-', '.', '_').filter { it.isNotBlank() && it[0].isLetterOrDigit() }
        .take(2).joinToString("") { it.first().uppercase() }.ifEmpty { name.take(1).uppercase() }
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val px = with(LocalDensity.current) { (maxWidth * 0.36f).toSp() }
        Text(letters, style = heading(px), maxLines = 1)
    }
}

/** Dunne voortgangslijn (accentverloop op een donkere baan) */
@Composable
fun ProgressLine(fraction: Float, modifier: Modifier = Modifier, height: Dp = 3.dp, track: Color = Color.White.copy(alpha = 0.18f)) {
    Box(modifier.height(height).clip(CircleShape).background(track)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(fraction.coerceIn(0f, 1f)).clip(CircleShape).background(T.accentHorizontal))
    }
}

// MARK: podcastkaarten

/** Kaart in een horizontale rij of raster: art + naam + maker; optioneel genummerd */
@Composable
fun PodcastCard(
    podcast: Podcast,
    modifier: Modifier = Modifier,
    width: Dp = Dims.cardWidth,
    number: Int? = null,
    focusRequester: FocusRequester? = null,
    onClick: () -> Unit = { Nav.podcast(podcast) },
) {
    val shape = RoundedCornerShape(Dims.cardRadius)
    Column(if (width == Dp.Unspecified) modifier.fillMaxWidth() else modifier.width(width)) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).tvClickable(shape, focusRequester = focusRequester, onClick = onClick)) {
            PodcastArt(podcast.artwork, podcast.displayName, Modifier.fillMaxSize(), radius = Dims.cardRadius)
            if (number != null) {
                Text(
                    "$number", style = heading(if (Device.isTV) 18.sp else 16.sp),
                    modifier = Modifier.align(Alignment.TopStart).padding(8.dp).clip(RoundedCornerShape(8.dp))
                        .background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 7.dp, vertical = 2.dp)
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(podcast.displayName, color = T.text, fontSize = Dims.bodySize, fontWeight = FontWeight.Bold,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(podcast.artist.ifEmpty { podcast.genre }, color = T.secondary, fontSize = Dims.smallSize,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Rij in een lijst: (nummer), art 56, naam, maker · genre, pijltje */
@Composable
fun PodcastRow(
    podcast: Podcast,
    modifier: Modifier = Modifier,
    number: Int? = null,
    focusRequester: FocusRequester? = null,
    onClick: () -> Unit = { Nav.podcast(podcast) },
) {
    val followed by Library.followedPodcasts.collectAsState()
    val following = followed.any { it.id == podcast.id }
    Row(
        modifier.fillMaxWidth()
            .tvClickable(RoundedCornerShape(12.dp), scale = 1.03f, focusRequester = focusRequester, onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (number != null) {
            Text("$number", style = heading(16.sp, T.secondary), modifier = Modifier.width(34.dp), textAlign = TextAlign.Center)
        }
        PodcastArt(podcast.artwork, podcast.displayName, Modifier.size(if (Device.isTV) 64.dp else 56.dp), radius = 10.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(podcast.displayName, color = T.text, fontSize = 16.sp, fontWeight = FontWeight.Bold,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            val sub = listOf(podcast.artist, podcast.genre).filter { it.isNotBlank() }.distinct().joinToString(" · ")
            Text(sub, color = T.secondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (following) {
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Rounded.CheckCircle, stringResource(R.string.following), tint = T.accent, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(4.dp))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = T.secondary)
    }
}

/** Horizontale rij podcasts met kop; laden = skeletten, fout = opnieuw */
@Composable
fun PodcastRowSection(
    title: String,
    load: LoadState<List<Podcast>>?,
    podcasts: List<Podcast>? = load?.value,
    onSeeAll: (() -> Unit)? = null,
    numbered: Boolean = false,
    firstFocus: FocusRequester? = null,
) {
    val list = podcasts
    if (load == null && list.isNullOrEmpty()) return
    if (load?.value != null && list.isNullOrEmpty()) return
    Column(Modifier.fillMaxWidth()) {
        SectionHeader(title, onSeeAll = if (!list.isNullOrEmpty()) onSeeAll else null)
        Spacer(Modifier.height(10.dp))
        when {
            !list.isNullOrEmpty() -> LazyRow(
                contentPadding = PaddingValues(horizontal = Dims.edge, vertical = if (Device.isTV) 10.dp else 0.dp),
                horizontalArrangement = Arrangement.spacedBy(Dims.rowGap)
            ) {
                itemsIndexed(list, key = { _, p -> p.id }) { i, p ->
                    PodcastCard(p, number = if (numbered) i + 1 else null, focusRequester = if (i == 0) firstFocus else null)
                }
            }
            load != null && load.failed -> ErrorRetry(message = stringResource(R.string.error_loading_podcasts), onRetry = load.retry, compact = true)
            else -> SkeletonRow()
        }
    }
}

// MARK: afleveringen

/** Kaart voor Ontdek/Bibliotheek: art met voortgang, titel (2 regels), podcast. Tik = afspelen, lang = details. */
@Composable
fun EpisodeCard(
    episode: Episode,
    queue: List<Episode>,
    modifier: Modifier = Modifier,
    width: Dp = Dims.cardWidth,
    focusRequester: FocusRequester? = null,
) {
    val current by RadioController.episode.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val progress by Library.progress.collectAsState()
    val p = progress[episode.id]
    val isCurrent = current?.id == episode.id
    val shape = RoundedCornerShape(Dims.cardRadius)
    Column(modifier.width(width)) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(1f)
                .tvClickable(shape, focusRequester = focusRequester, onLongClick = { Nav.episode(episode, queue) }) {
                    if (isCurrent) RadioController.togglePlay() else RadioController.playEpisode(episode, queue)
                }
        ) {
            PodcastArt(episode.art, episode.podcastName, Modifier.fillMaxSize(), radius = Dims.cardRadius)
            Box(
                Modifier.align(Alignment.BottomEnd).padding(8.dp).size(34.dp).clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.6f)),
                contentAlignment = Alignment.Center
            ) {
                if (isCurrent && playing) EqualizerBars(playing = true)
                else Icon(Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(20.dp))
            }
            if (p != null && p.inProgress) {
                ProgressLine(p.fraction, Modifier.align(Alignment.BottomStart).padding(start = 10.dp, end = 52.dp, bottom = 14.dp).fillMaxWidth())
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(episode.displayTitle, color = if (isCurrent) T.accent else T.text, fontSize = Dims.bodySize,
            fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(
            listOf(episode.podcastName, formatEpisodeDate(episode.releaseDate)).filter { it.isNotBlank() }.joinToString(" · "),
            color = T.secondary, fontSize = Dims.smallSize, maxLines = 1, overflow = TextOverflow.Ellipsis
        )
    }
}

/** Horizontale rij afleveringen met kop */
@Composable
fun EpisodeRowSection(title: String, load: LoadState<List<Episode>>?, episodes: List<Episode>? = load?.value) {
    val list = episodes
    if (load == null && list.isNullOrEmpty()) return
    if (load?.value != null && list.isNullOrEmpty()) return
    Column(Modifier.fillMaxWidth()) {
        SectionHeader(title)
        Spacer(Modifier.height(10.dp))
        when {
            !list.isNullOrEmpty() -> LazyRow(
                contentPadding = PaddingValues(horizontal = Dims.edge, vertical = if (Device.isTV) 10.dp else 0.dp),
                horizontalArrangement = Arrangement.spacedBy(Dims.rowGap)
            ) {
                itemsIndexed(list, key = { _, e -> e.id }) { _, e -> EpisodeCard(e, list, width = if (Device.isTV) 180.dp else 150.dp) }
            }
            load != null && load.failed -> ErrorRetry(message = stringResource(R.string.error_loading_podcasts), onRetry = load.retry, compact = true)
            else -> SkeletonRow()
        }
    }
}

/**
 * Aflevering in de lijst van een podcast: datum · duur, titel, korte omschrijving, voortgangsbalkje, ✓ als beluisterd,
 * afspeelknop. Tik op de rij = afleveringspagina.
 */
@Composable
fun EpisodeRow(
    episode: Episode,
    queue: List<Episode>,
    modifier: Modifier = Modifier,
    focusRequester: FocusRequester? = null,
) {
    val current by RadioController.episode.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val progress by Library.progress.collectAsState()
    val p = progress[episode.id]
    val isCurrent = current?.id == episode.id
    Row(
        modifier.fillMaxWidth()
            .tvClickable(RoundedCornerShape(12.dp), scale = 1.02f, focusRequester = focusRequester) { Nav.episode(episode, queue) }
            .padding(horizontal = 8.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (p?.finished == true) {
                    Icon(Icons.Rounded.CheckCircle, stringResource(R.string.played), tint = T.accent, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(4.dp))
                }
                Text(
                    listOf(formatEpisodeDate(episode.releaseDate), formatDurationShort(episode.durationMs))
                        .filter { it.isNotBlank() }.joinToString(" · "),
                    color = T.secondary, fontSize = 12.sp, maxLines = 1
                )
            }
            Spacer(Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isCurrent && playing) { EqualizerBars(); Spacer(Modifier.width(8.dp)) }
                Text(episode.displayTitle, color = if (isCurrent) T.accent else T.text, fontSize = 16.sp,
                    fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            val summary = episode.summary
            if (summary.isNotEmpty()) {
                Spacer(Modifier.height(2.dp))
                Text(summary, color = T.secondary, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            if (p != null && p.inProgress) {
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ProgressLine(p.fraction, Modifier.widthIn(max = 160.dp).fillMaxWidth(0.5f))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.time_left, formatDurationShort((p.durationMs - p.positionMs).coerceAtLeast(0L))),
                        color = T.secondary, fontSize = 12.sp, maxLines = 1)
                }
            }
        }
        Spacer(Modifier.width(10.dp))
        CircleIconButton(
            if (isCurrent && playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
            stringResource(if (isCurrent && playing) R.string.pause else R.string.play),
            size = 44.dp, background = T.surface
        ) { if (isCurrent) RadioController.togglePlay() else RadioController.playEpisode(episode, queue) }
    }
}

// MARK: miniplayer (aflevering)

/** Miniplayer bij een aflevering: art, titel van de aflevering, podcast, play/pauze, 30 s vooruit, dunne voortgangslijn */
@Composable
fun EpisodeMiniPlayer(episode: Episode, modifier: Modifier = Modifier) {
    val playing by RadioController.isPlaying.collectAsState()
    val buffering by RadioController.buffering.collectAsState()
    val error by RadioController.error.collectAsState()
    val position by RadioController.position.collectAsState()
    val duration by RadioController.duration.collectAsState()
    val fraction = if (duration > 0) position.toFloat() / duration else 0f
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(T.elevated)
            .tvClickable(RoundedCornerShape(14.dp), scale = 1.0f) { AppState.showPlayer = true }
    ) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            PodcastArt(episode.art, episode.podcastName, Modifier.size(44.dp), radius = 8.dp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(episode.displayTitle, color = T.text, fontSize = 15.sp, fontWeight = FontWeight.Bold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    if (error) stringResource(R.string.episode_unreachable) else episode.podcastName,
                    color = if (error) T.live else T.secondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                if (buffering && !error) CircularProgressIndicator(Modifier.size(40.dp), color = T.accent, strokeWidth = 2.dp)
                CircleIconButton(
                    when { error -> Icons.Rounded.Refresh; playing || buffering -> Icons.Rounded.Pause; else -> Icons.Rounded.PlayArrow },
                    stringResource(if (playing) R.string.pause else R.string.play),
                    size = 40.dp, background = Color.Transparent
                ) { if (error) RadioController.retry() else RadioController.togglePlay() }
            }
            SkipIconButton(forward = true, size = 40.dp) { RadioController.skipForward() }
        }
        ProgressLine(fraction, Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 6.dp), height = 2.dp)
    }
}

/** Ronde knop "15 s terug" / "30 s vooruit": rond pijltje met het aantal seconden erin */
@Composable
fun SkipIconButton(
    forward: Boolean,
    modifier: Modifier = Modifier,
    size: Dp = 56.dp,
    focusRequester: FocusRequester? = null,
    onClick: () -> Unit,
) {
    val label = stringResource(if (forward) R.string.skip_forward_30 else R.string.skip_back_15)
    Box(
        modifier
            .size(size)
            .tvClickable(CircleShape, scale = 1.1f, focusRequester = focusRequester, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            Icons.Rounded.Replay, null, tint = Color.White,
            modifier = Modifier.size(size * 0.62f).graphicsLayer { if (forward) scaleX = -1f }
        )
        Text(
            if (forward) "30" else "15", color = Color.White, fontWeight = FontWeight.Black,
            fontSize = (size.value * 0.19f).sp, modifier = Modifier.padding(top = (size.value * 0.06f).dp)
        )
    }
}

// MARK: gesegmenteerde keuze

/** Eenvoudige gesegmenteerde keuze in de huisstijl (geen experimentele Material-API) */
@Composable
fun SegmentedControl(
    labels: List<String>,
    selected: Int,
    modifier: Modifier = Modifier,
    firstFocus: FocusRequester? = null,
    onSelect: (Int) -> Unit,
) {
    Row(
        modifier.clip(RoundedCornerShape(12.dp)).background(T.surface).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        labels.forEachIndexed { i, label ->
            val sel = selected == i
            Box(
                Modifier.weight(1f)
                    .tvClickable(RoundedCornerShape(9.dp), scale = 1.03f, focusRequester = if (i == 0) firstFocus else null) { onSelect(i) }
                    .background(if (sel) T.accent else Color.Transparent)
                    .padding(vertical = 9.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(label, color = if (sel) Color.White else T.secondary, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1)
            }
        }
    }
}

// MARK: genres

/** Tekst-sleutel voor een iTunes-podcastgenre (SPEC §8) */
fun podcastGenreLabel(id: Int): Int = when (id) {
    1489 -> R.string.pgenre_news
    1303 -> R.string.pgenre_comedy
    1545 -> R.string.pgenre_sports
    1488 -> R.string.pgenre_true_crime
    1324 -> R.string.pgenre_society
    1321 -> R.string.pgenre_business
    1512 -> R.string.pgenre_health
    1487 -> R.string.pgenre_history
    1533 -> R.string.pgenre_science
    1318 -> R.string.pgenre_technology
    1305 -> R.string.pgenre_kids
    1310 -> R.string.pgenre_music
    else -> R.string.genre_other
}

fun podcastGenreIcon(id: Int): ImageVector = when (id) {
    1489 -> Icons.Rounded.Newspaper
    1303 -> Icons.Rounded.Mood
    1545 -> Icons.Rounded.SportsSoccer
    1488 -> Icons.Rounded.Gavel
    1324 -> Icons.Rounded.People
    1321 -> Icons.Rounded.Work
    1512 -> Icons.Rounded.FitnessCenter
    1487 -> Icons.Rounded.History
    1533 -> Icons.Rounded.School
    1318 -> Icons.Rounded.Computer
    1305 -> Icons.Rounded.ChildCare
    1310 -> Icons.Rounded.MusicNote
    else -> Icons.Rounded.Headphones
}

// MARK: opmaak

/** "1:02:03" of "2:03" */
fun formatClock(ms: Long): String {
    val total = (ms.coerceAtLeast(0L) / 1000)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

/** "1 u 5 min" / "42 min" (leeg als onbekend) */
@Composable
fun formatDurationShort(ms: Long): String {
    if (ms <= 0) return ""
    val totalMin = ((ms + 30_000) / 60_000).coerceAtLeast(1)
    val h = totalMin / 60
    val m = totalMin % 60
    return if (h > 0) stringResource(R.string.hours_minutes, h.toInt(), m.toInt()) else stringResource(R.string.minutes_n, m.toInt())
}

/** ISO-datum uit iTunes → "1 mei 2024" in de taal van de app (leeg als onbekend) */
fun formatEpisodeDate(iso: String): String {
    val d = parseIsoDate(iso) ?: return ""
    return DateFormat.getDateInstance(DateFormat.MEDIUM, Locale.getDefault()).format(d)
}

fun parseIsoDate(iso: String): Date? {
    val t = iso.trim()
    if (t.length < 10) return null
    val patterns = listOf("yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd")
    for (p in patterns) {
        val f = SimpleDateFormat(p, Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("UTC"); isLenient = true }
        val src = if (p == "yyyy-MM-dd") t.take(10) else t
        runCatching { f.parse(src) }.getOrNull()?.let { return it }
    }
    return null
}

/** "1,25×" in de taal van de app */
fun speedLabel(v: Float): String =
    NumberFormat.getNumberInstance(Locale.getDefault()).apply { maximumFractionDigits = 2; minimumFractionDigits = 0 }.format(v) + "×"

/** Aantal afleveringen met de juiste meervoudsvorm */
@Composable
fun episodeCount(n: Int): String =
    pluralStringResource(R.plurals.episode_count, n, NumberFormat.getIntegerInstance().format(n))

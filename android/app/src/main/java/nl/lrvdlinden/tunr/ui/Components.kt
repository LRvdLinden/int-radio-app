package nl.lrvdlinden.tunr.ui

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
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
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.compose.AsyncImagePainter
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.player.PlaybackService
import nl.lrvdlinden.tunr.player.RadioController

// MARK: logo

/**
 * Wordmark (SPEC §1): "TUNR" heavy, wit, met eronder een frequentieschaal in het accentverloop met 9 maatstreepjes
 * en een naaldje (accent2) iets rechts van het midden.
 */
@Composable
fun TunrLogo(size: TextUnit = 24.sp, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    val widthDp = with(density) { (size.toPx() * 2.75f).toDp() }
    Column(modifier.semantics { contentDescription = "Tunr" }, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("TUNR", style = heading(size), letterSpacing = (size.value * 0.06f).sp, maxLines = 1)
        FrequencyBar(Modifier.width(widthDp).height(with(density) { (size.toPx() * 0.42f).toDp() }))
    }
}

/** De balk onder het woordmerk: verloop, 9 streepjes, naald */
@Composable
fun FrequencyBar(modifier: Modifier = Modifier, needleAt: Float = 0.58f) {
    Canvas(modifier) {
        val barH = size.height * 0.28f
        val y = size.height - barH
        drawRoundRect(
            brush = Brush.horizontalGradient(listOf(T.accent, T.accent2)),
            topLeft = Offset(0f, y), size = Size(size.width, barH), cornerRadius = CornerRadius(barH / 2, barH / 2)
        )
        val tickW = (size.width * 0.012f).coerceAtLeast(1f)
        for (i in 0 until 9) {
            val x = size.width * (0.1f + 0.8f * i / 8f)
            val h = if (i % 2 == 0) size.height * 0.55f else size.height * 0.4f
            drawLine(Color.White.copy(alpha = 0.55f), Offset(x, y - h * 0.15f), Offset(x, y - h), tickW, StrokeCap.Round)
        }
        val nx = size.width * needleAt
        drawLine(T.accent2, Offset(nx, 0f), Offset(nx, size.height), tickW * 2.2f, StrokeCap.Round)
    }
}

// MARK: zendercover

/**
 * Vierkante zendercover: verloop uit het palet (hash van de naam), daarop het logo op een witte afgeronde tegel
 * (62%); geen logo of mislukt → monogram.
 */
@Composable
fun StationArt(
    station: Station?,
    modifier: Modifier = Modifier,
    radius: Dp = 14.dp,
    overrideUrl: String? = null,
) {
    val name = station?.displayName ?: "Tunr"
    val (c1, c2) = T.palette(name)
    var failed by remember(station?.uuid, overrideUrl) { mutableStateOf(false) }
    val logo = overrideUrl ?: station?.favicon?.trim()?.takeIf { it.startsWith("http") }
    Box(
        modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(radius))
            .background(Brush.linearGradient(listOf(c1, c2))),
        contentAlignment = Alignment.Center
    ) {
        if (logo == null || failed) {
            Monogram(name)
        } else if (overrideUrl != null) {
            // albumhoes: vult het hele vlak
            AsyncImage(
                model = overrideUrl, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                onState = { if (it is AsyncImagePainter.State.Error) failed = true }
            )
        } else {
            Box(
                Modifier.fillMaxSize(0.62f).clip(RoundedCornerShape(radius * 0.7f)).background(Color.White),
                contentAlignment = Alignment.Center
            ) {
                AsyncImage(
                    model = logo, contentDescription = null, contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize().padding(8.dp * 0.9f).aspectRatio(1f),
                    onState = { if (it is AsyncImagePainter.State.Error) failed = true }
                )
            }
        }
    }
}

@Composable
private fun BoxScope.Monogram(name: String) {
    val letters = name.split(' ', '-', '.', '_').filter { it.isNotBlank() && it[0].isLetterOrDigit() }
        .take(2).joinToString("") { it.first().uppercase() }.ifEmpty { name.take(1).uppercase() }
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
        val px = with(LocalDensity.current) { (maxWidth * 0.36f).toSp() }
        Text(letters, style = heading(px), maxLines = 1)
    }
}

// MARK: equalizer en LIVE

/** 4 staafjes in de accentkleur die bewegen als er iets speelt */
@Composable
fun EqualizerBars(modifier: Modifier = Modifier, playing: Boolean = true, color: Color = T.accent, barCount: Int = 4) {
    val t = rememberInfiniteTransition(label = "eq")
    val phases = listOf(0, 180, 90, 270, 45)
    val anims = (0 until barCount).map { i ->
        t.animateFloat(
            initialValue = 0.25f, targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(420 + i * 70, delayMillis = phases[i % phases.size], easing = FastOutSlowInEasing), RepeatMode.Reverse),
            label = "eq$i"
        )
    }
    Canvas(modifier.size(16.dp, 14.dp)) {
        val gap = size.width * 0.12f
        val w = (size.width - gap * (barCount - 1)) / barCount
        for (i in 0 until barCount) {
            val f = if (playing) anims[i].value else 0.25f + 0.1f * (i % 2)
            val h = size.height * f
            drawRoundRect(color, Offset(i * (w + gap), size.height - h), Size(w, h), CornerRadius(w / 2, w / 2))
        }
    }
}

/** Rood bolletje + "LIVE" */
@Composable
fun LivePill(modifier: Modifier = Modifier) {
    val t = rememberInfiniteTransition(label = "live")
    val a by t.animateFloat(1f, 0.35f, infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Reverse), label = "dot")
    Row(
        modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.12f)).padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(7.dp).graphicsLayer { alpha = a }.clip(CircleShape).background(T.live))
        Spacer(Modifier.width(6.dp))
        Text(stringResource(R.string.live), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
    }
}

// MARK: kaarten en rijen

/** Contextmenu (lang indrukken): zenderinfo, favoriet, plus eventueel extra acties (verwijderen uit Recent) */
@Composable
fun StationMenu(
    station: Station,
    expanded: Boolean,
    onDismiss: () -> Unit,
    extra: List<Pair<String, () -> Unit>> = emptyList(),
) {
    val favorites by Library.favorites.collectAsState()
    val fav = favorites.any { it.uuid == station.uuid }
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss, containerColor = T.elevated) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.station_info), color = T.text) },
            leadingIcon = { Icon(Icons.Rounded.Info, null, tint = T.text) },
            onClick = { onDismiss(); Nav.station(station) }
        )
        DropdownMenuItem(
            text = { Text(stringResource(if (fav) R.string.remove_favorite else R.string.add_favorite), color = T.text) },
            leadingIcon = { Icon(if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null, tint = T.accent) },
            onClick = { onDismiss(); Library.toggleFavorite(station) }
        )
        extra.forEach { (label, action) ->
            DropdownMenuItem(
                text = { Text(label, color = T.text) },
                leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = T.text) },
                onClick = { onDismiss(); action() }
            )
        }
    }
}

/** Kaart in een horizontale rij: art + naam + genres; equalizer als hij speelt */
@Composable
fun StationCard(
    station: Station,
    queue: List<Station>,
    modifier: Modifier = Modifier,
    width: Dp = Dims.cardWidth,
    number: Int? = null,
    focusRequester: FocusRequester? = null,
    onLongClick: (() -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val current by RadioController.station.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val isCurrent = current?.uuid == station.uuid
    val shape = RoundedCornerShape(Dims.cardRadius)
    var menu by remember { mutableStateOf(false) }
    Column(if (width == Dp.Unspecified) modifier.fillMaxWidth() else modifier.width(width)) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .tvClickable(shape, focusRequester = focusRequester, onLongClick = onLongClick ?: { menu = true }) {
                    onClick?.invoke() ?: RadioController.play(station, queue)
                }
        ) {
            StationMenu(station, menu, onDismiss = { menu = false })
            StationArt(station, Modifier.fillMaxSize(), radius = Dims.cardRadius)
            if (isCurrent) {
                Box(
                    Modifier.align(Alignment.BottomEnd).padding(8.dp).clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.6f)).padding(6.dp)
                ) { EqualizerBars(playing = playing) }
            }
            if (number != null) {
                Text(
                    "$number", style = heading(if (Device.isTV) 18.sp else 16.sp),
                    modifier = Modifier.align(Alignment.TopStart).padding(8.dp).clip(RoundedCornerShape(8.dp))
                        .background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 7.dp, vertical = 2.dp)
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            station.displayName, color = if (isCurrent) T.accent else T.text, fontSize = Dims.bodySize,
            fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis
        )
        Text(
            station.genresLine.ifEmpty { station.placeLine() }, color = T.secondary, fontSize = Dims.smallSize,
            maxLines = 1, overflow = TextOverflow.Ellipsis
        )
    }
}

/** Rij in een lijst: art 56, naam, land/genres, bitrate; equalizer als hij speelt */
@Composable
fun StationRow(
    station: Station,
    queue: List<Station>,
    modifier: Modifier = Modifier,
    number: Int? = null,
    focusRequester: FocusRequester? = null,
    trailing: (@Composable () -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val current by RadioController.station.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val isCurrent = current?.uuid == station.uuid
    var menu by remember { mutableStateOf(false) }
    Row(
        modifier
            .fillMaxWidth()
            .tvClickable(RoundedCornerShape(12.dp), scale = 1.03f, focusRequester = focusRequester,
                onLongClick = onLongClick ?: { menu = true }) {
                onClick?.invoke() ?: RadioController.play(station, queue)
            }
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box { StationMenu(station, menu, onDismiss = { menu = false }) }
        if (number != null) {
            Text("$number", style = heading(16.sp, T.secondary), modifier = Modifier.width(34.dp), textAlign = TextAlign.Center)
        }
        StationArt(station, Modifier.size(if (Device.isTV) 64.dp else 56.dp), radius = 10.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isCurrent) { EqualizerBars(playing = playing); Spacer(Modifier.width(8.dp)) }
                Text(
                    station.displayName, color = if (isCurrent) T.accent else T.text, fontSize = 16.sp,
                    fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
            val sub = listOf(station.placeLine(), station.genresLine).filter { it.isNotBlank() }.joinToString(" · ")
            Text(sub, color = T.secondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (station.bitrate > 0) {
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.kbps, station.bitrate), color = T.secondary, fontSize = 12.sp)
        }
        trailing?.let { Spacer(Modifier.width(4.dp)); it() }
    }
}

/** Kop van een sectie met optioneel "Alles" */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, onSeeAll: (() -> Unit)? = null) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = Dims.edge),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, style = heading(Dims.titleSize), modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (onSeeAll != null) {
            Row(
                Modifier.tvClickable(CircleShape, onClick = onSeeAll).padding(horizontal = 10.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(stringResource(R.string.see_all), color = T.accent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = T.accent, modifier = Modifier.size(18.dp))
            }
        }
    }
}

/** Horizontale rij zenders met kop; laden = skeletten, fout = opnieuw */
@Composable
fun StationRowSection(
    title: String,
    load: LoadState<List<Station>>?,
    stations: List<Station>? = load?.value,
    onSeeAll: (() -> Unit)? = null,
    numbered: Boolean = false,
    firstFocus: FocusRequester? = null,
) {
    val list = stations
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
                itemsIndexed(list, key = { _, s -> s.uuid }) { i, s ->
                    StationCard(s, list, number = if (numbered) i + 1 else null,
                        focusRequester = if (i == 0) firstFocus else null)
                }
            }
            load != null && load.failed -> ErrorRetry(onRetry = load.retry, compact = true)
            else -> SkeletonRow()
        }
    }
}

/** Genre-chips (SPEC §4) */
@Composable
fun GenreChips(tags: List<String>, modifier: Modifier = Modifier, onClick: (String) -> Unit) {
    LazyRow(
        modifier,
        contentPadding = PaddingValues(horizontal = Dims.edge, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        itemsIndexed(tags, key = { _, t -> t }) { _, tag ->
            Chip(stringResource(PlaybackService.genreLabel(tag))) { onClick(tag) }
        }
    }
}

@Composable
fun Chip(text: String, selected: Boolean = false, icon: ImageVector? = null, onClick: () -> Unit) {
    Row(
        Modifier
            .tvClickable(CircleShape, scale = 1.06f, onClick = onClick)
            .then(if (selected) Modifier.background(T.accentBrush) else Modifier.background(T.surface).border(1.dp, T.stroke, CircleShape))
            .padding(horizontal = if (Device.isTV) 18.dp else 14.dp, vertical = if (Device.isTV) 10.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)) }
        Text(text, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** Grote gekleurde tegel (Bladeren) */
@Composable
fun BrowseTile(
    title: String,
    icon: ImageVector,
    paletteIndex: Int,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    focusRequester: FocusRequester? = null,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(Dims.cardRadius)
    Box(
        modifier
            .tvClickable(shape, scale = 1.05f, focusRequester = focusRequester, onClick = onClick)
            .background(T.paletteBrush(paletteIndex))
            .padding(16.dp)
    ) {
        Icon(
            icon, null, tint = Color.White.copy(alpha = 0.28f),
            modifier = Modifier.align(Alignment.BottomEnd).size(if (Device.isTV) 72.dp else 64.dp)
                .graphicsLayer { rotationZ = -12f; translationX = 18f; translationY = 14f }
        )
        Column(Modifier.align(Alignment.TopStart)) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.height(10.dp))
            Text(title, style = heading(if (Device.isTV) 20.sp else 18.sp), maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 1)
        }
    }
}

// MARK: laden en fouten

/** Glanzend skelet */
@Composable
fun Skeleton(modifier: Modifier = Modifier, radius: Dp = 14.dp) {
    val t = rememberInfiniteTransition(label = "skeleton")
    val x by t.animateFloat(-1f, 2f, infiniteRepeatable(tween(1300, easing = LinearEasing)), label = "shimmer")
    Box(
        modifier.clip(RoundedCornerShape(radius)).background(T.surface)
    ) {
        androidx.compose.foundation.layout.BoxWithConstraints(Modifier.matchParentSize()) {
            val w = constraints.maxWidth.toFloat().coerceAtLeast(1f)
            Box(
                Modifier.matchParentSize().background(
                    Brush.linearGradient(
                        listOf(Color.Transparent, Color.White.copy(alpha = 0.07f), Color.Transparent),
                        start = Offset(w * x - w * 0.5f, 0f), end = Offset(w * x + w * 0.5f, 0f)
                    )
                )
            )
        }
    }
}

@Composable
fun SkeletonRow() {
    Row(Modifier.padding(horizontal = Dims.edge), horizontalArrangement = Arrangement.spacedBy(Dims.rowGap)) {
        repeat(if (Device.isTV) 7 else 4) {
            Column(Modifier.width(Dims.cardWidth)) {
                Skeleton(Modifier.fillMaxWidth().aspectRatio(1f), Dims.cardRadius)
                Spacer(Modifier.height(8.dp))
                Skeleton(Modifier.fillMaxWidth(0.8f).height(12.dp), 6.dp)
                Spacer(Modifier.height(6.dp))
                Skeleton(Modifier.fillMaxWidth(0.5f).height(10.dp), 5.dp)
            }
        }
    }
}

@Composable
fun SkeletonList(count: Int = 8) {
    Column(Modifier.padding(horizontal = Dims.edge), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        repeat(count) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Skeleton(Modifier.size(56.dp), 10.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Skeleton(Modifier.fillMaxWidth(0.6f).height(13.dp), 6.dp)
                    Spacer(Modifier.height(6.dp))
                    Skeleton(Modifier.fillMaxWidth(0.4f).height(10.dp), 5.dp)
                }
            }
        }
    }
}

/** Foutmelding met "Opnieuw" */
@Composable
fun ErrorRetry(
    modifier: Modifier = Modifier,
    message: String = stringResource(R.string.error_loading),
    compact: Boolean = false,
    focusRequester: FocusRequester? = null,
    onRetry: () -> Unit,
) {
    if (compact) {
        Row(
            modifier.fillMaxWidth().padding(horizontal = Dims.edge).clip(RoundedCornerShape(14.dp)).background(T.surface).padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Rounded.WifiOff, null, tint = T.secondary, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
            Text(message, color = T.secondary, fontSize = 14.sp, modifier = Modifier.weight(1f))
            PillButton(stringResource(R.string.retry), Icons.Rounded.Refresh, small = true, focusRequester = focusRequester, onClick = onRetry)
        }
    } else {
        Column(
            modifier.fillMaxWidth().padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(Icons.Rounded.WifiOff, null, tint = T.secondary, modifier = Modifier.size(40.dp))
            Spacer(Modifier.height(12.dp))
            Text(message, color = T.secondary, fontSize = 15.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp))
            PillButton(stringResource(R.string.retry), Icons.Rounded.Refresh, focusRequester = focusRequester, onClick = onRetry)
        }
    }
}

/** Lege toestand met icoon en tekst */
@Composable
fun EmptyState(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(contentAlignment = Alignment.Center) {
            // "hart in golven": concentrische ringen achter het icoon
            Canvas(Modifier.size(120.dp)) {
                for (i in 1..3) drawCircle(T.accent.copy(alpha = 0.22f / i), radius = size.minDimension / 2 * (0.4f + i * 0.2f),
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2.dp.toPx()))
            }
            Icon(icon, null, tint = T.accent, modifier = Modifier.size(44.dp))
        }
        Spacer(Modifier.height(12.dp))
        Text(title, style = heading(18.sp), textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(message, color = T.secondary, fontSize = 14.sp, textAlign = TextAlign.Center)
    }
}

// MARK: knoppen

/** Afgeronde knop: accent (primair) of glas (secundair) */
@Composable
fun PillButton(
    text: String,
    icon: ImageVector? = null,
    modifier: Modifier = Modifier,
    primary: Boolean = true,
    small: Boolean = false,
    focusRequester: FocusRequester? = null,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(Dims.buttonRadius)
    Row(
        modifier
            .tvClickable(shape, scale = 1.06f, focusRequester = focusRequester, onClick = onClick)
            .then(if (primary) Modifier.background(T.accent) else Modifier.background(Color.White.copy(alpha = 0.12f)))
            .padding(horizontal = if (small) 12.dp else 18.dp, vertical = if (small) 7.dp else 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center
    ) {
        if (icon != null) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(if (small) 16.dp else 20.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(text, color = Color.White, fontWeight = FontWeight.Bold, fontSize = if (small) 13.sp else 15.sp, maxLines = 1)
    }
}

/** Ronde icoonknop (glas) */
@Composable
fun CircleIconButton(
    icon: ImageVector,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    size: Dp = 44.dp,
    tint: Color = Color.White,
    background: Color = Color.White.copy(alpha = 0.1f),
    focusRequester: FocusRequester? = null,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(size)
            .tvClickable(CircleShape, scale = 1.1f, focusRequester = focusRequester, onClick = onClick)
            .background(background)
            .semantics { if (contentDescription != null) this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(size * 0.5f))
    }
}

/** Terugknop bovenaan een scherm + titel */
@Composable
fun TopBar(title: String, onBack: () -> Unit, modifier: Modifier = Modifier, actions: @Composable () -> Unit = {}) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = Dims.edge - 6.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (!Device.isTV) {
            CircleIconButton(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.back), size = 40.dp,
                background = Color.Transparent, onClick = onBack)
            Spacer(Modifier.width(4.dp))
        }
        Text(title, style = heading(if (Device.isTV) 28.sp else 22.sp), modifier = Modifier.weight(1f),
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        actions()
    }
}

// MARK: miniplayer

/** Miniplayer boven de tabbalk (telefoon/tablet): art 44, naam, nu speelt / genres, play/pauze, volgende */
@Composable
fun MiniPlayer(modifier: Modifier = Modifier) {
    val station by RadioController.station.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val buffering by RadioController.buffering.collectAsState()
    val error by RadioController.error.collectAsState()
    val np by RadioController.nowPlaying.collectAsState()
    val queue by RadioController.queue.collectAsState()
    val s = station ?: return
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(T.elevated)
            .tvClickable(RoundedCornerShape(14.dp), scale = 1.0f) { AppState.showPlayer = true }
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StationArt(s, Modifier.size(44.dp), radius = 8.dp)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(s.displayName, color = T.text, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (playing) { EqualizerBars(Modifier.size(12.dp, 10.dp)); Spacer(Modifier.width(6.dp)) }
                Text(
                    when {
                        error -> stringResource(R.string.station_unreachable)
                        np != null -> np!!.line
                        else -> s.genresLine.ifEmpty { s.placeLine() }
                    },
                    color = if (error) T.live else T.secondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
        Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
            if (buffering && !error) CircularProgressIndicator(Modifier.size(40.dp), color = T.accent, strokeWidth = 2.dp)
            CircleIconButton(
                when { error -> Icons.Rounded.Refresh; playing || buffering -> Icons.Rounded.Pause; else -> Icons.Rounded.PlayArrow },
                stringResource(if (playing) R.string.pause else R.string.play),
                size = 40.dp, background = Color.Transparent
            ) { if (error) RadioController.retry() else RadioController.togglePlay() }
        }
        if (queue.size > 1) {
            CircleIconButton(Icons.Rounded.SkipNext, stringResource(R.string.next_station), size = 40.dp,
                background = Color.Transparent) { RadioController.next() }
        }
    }
}

/** Aantal zenders ("1.234 zenders") met de juiste meervoudsvorm */
@Composable
fun stationCount(n: Int): String =
    pluralStringResource(R.plurals.station_count, n, java.text.NumberFormat.getIntegerInstance().format(n))

/** Opvulling onder lijsten zodat de miniplayer/tabbalk niets bedekt */
val bottomContentPadding: Dp get() = if (Device.isTV) 48.dp else 24.dp

/** Volle breedte gradient-overlay onderaan */
@Composable
fun BoxScope.BottomFade(height: Dp = 120.dp, color: Color = T.bg) {
    Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(height)
        .background(Brush.verticalGradient(listOf(Color.Transparent, color))))
}

package nl.lrvdlinden.tunr.ui.screens

import android.os.Build
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Episode
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.CircleIconButton
import nl.lrvdlinden.tunr.ui.EqualizerBars
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.PodcastArt
import nl.lrvdlinden.tunr.ui.SkipIconButton
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.formatClock
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.speedLabel
import nl.lrvdlinden.tunr.ui.tvFocus

/** Snelheden voor afleveringen (SPEC §8) */
private val SPEEDS = listOf(0.8f, 1f, 1.25f, 1.5f, 1.75f, 2f)

/**
 * Speler in podcastmodus (SPEC §8): geen LIVE-pil maar een tijdbalk met verstreken/resterende tijd,
 * vorige · 15 s terug · afspelen/pauze · 30 s vooruit · volgende, snelheid, slaaptimer (incl. einde van aflevering).
 * Tv: de tijdbalk is focusbaar; D-pad links/rechts = 15 s terug / 30 s vooruit.
 */
@Composable
fun EpisodePlayerScreen(episode: Episode, onClose: () -> Unit) {
    val playing by RadioController.isPlaying.collectAsState()
    val buffering by RadioController.buffering.collectAsState()
    val error by RadioController.error.collectAsState()
    val queue by RadioController.episodeQueue.collectAsState()
    val index = queue.indexOfFirst { it.id == episode.id }
    val hasPrevious = index > 0
    val hasNext = index >= 0 && index < queue.lastIndex
    var showSleep by remember { mutableStateOf(false) }
    var drag by remember { mutableFloatStateOf(0f) }
    val dragAnim by animateFloatAsState(drag, label = "drag")
    val playFocus = rememberInitialFocus(key = episode.id)
    val wide = isWide()

    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer { translationY = dragAnim.coerceAtLeast(0f) }
            .background(T.bg)
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragEnd = { if (drag > 220f) onClose() else drag = 0f },
                    onDragCancel = { drag = 0f },
                ) { _, dy -> drag = (drag + dy).coerceAtLeast(0f) }
            }
    ) {
        EpisodeBackdrop(episode)

        val art: @Composable (Dp) -> Unit = { size ->
            Box(Modifier.size(size), contentAlignment = Alignment.Center) {
                PodcastArt(episode.art, episode.podcastName, Modifier.fillMaxSize(), radius = 22.dp)
            }
        }

        val info: @Composable () -> Unit = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (playing) { EqualizerBars(); Spacer(Modifier.width(8.dp)) }
                    Text(
                        episode.displayTitle, style = heading(if (Device.isTV) 28.sp else 22.sp), textAlign = TextAlign.Center,
                        maxLines = 2, overflow = TextOverflow.Ellipsis
                    )
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    if (error) stringResource(R.string.episode_unreachable) else episode.podcastName,
                    color = if (error) T.live else Color.White.copy(alpha = 0.75f), fontSize = 16.sp,
                    textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(18.dp))

                TimeBar(Modifier.widthIn(max = 560.dp).fillMaxWidth())

                Spacer(Modifier.height(14.dp))
                // vorige · 15 terug · play/pauze · 30 vooruit · volgende
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (Device.isTV) 18.dp else 8.dp)) {
                    CircleIconButton(Icons.Rounded.SkipPrevious, stringResource(R.string.previous_episode), size = 48.dp,
                        tint = if (hasPrevious) Color.White else Color.White.copy(alpha = 0.35f), background = Color.Transparent) {
                        RadioController.previous()
                    }
                    SkipIconButton(forward = false, size = 56.dp) { RadioController.skipBack() }
                    Box(contentAlignment = Alignment.Center) {
                        if (buffering && !error) CircularProgressIndicator(Modifier.size(86.dp), color = Color.White, strokeWidth = 2.dp)
                        CircleIconButton(
                            when { error -> Icons.Rounded.Refresh; playing || buffering -> Icons.Rounded.Pause; else -> Icons.Rounded.PlayArrow },
                            stringResource(if (playing) R.string.pause else R.string.play),
                            size = 76.dp, background = T.accent, focusRequester = playFocus
                        ) { if (error) RadioController.retry() else RadioController.togglePlay() }
                    }
                    SkipIconButton(forward = true, size = 56.dp) { RadioController.skipForward() }
                    CircleIconButton(Icons.Rounded.SkipNext, stringResource(R.string.next_episode), size = 48.dp,
                        tint = if (hasNext) Color.White else Color.White.copy(alpha = 0.35f), background = Color.Transparent) {
                        if (hasNext) RadioController.next()
                    }
                }

                Spacer(Modifier.height(22.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SpeedButton()
                    ActionButton(Icons.Rounded.Bedtime, sleepLabel()) { showSleep = true }
                    ActionButton(Icons.Rounded.Info, stringResource(R.string.podcast_info)) {
                        onClose(); Nav.podcast(episode.podcast())
                    }
                }

                if (!Device.isTV) {
                    Spacer(Modifier.height(22.dp))
                    VolumeSlider(Modifier.widthIn(max = 420.dp).fillMaxWidth())
                }
            }
        }

        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (!Device.isTV) CircleIconButton(Icons.Rounded.KeyboardArrowDown, stringResource(R.string.close), background = Color.Transparent, onClick = onClose)
                Spacer(Modifier.weight(1f))
                Text(stringResource(R.string.now_playing).uppercase(), color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp,
                    fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
                Spacer(Modifier.weight(1f))
                if (!Device.isTV) Spacer(Modifier.size(44.dp))
            }
            if (wide) {
                Row(Modifier.fillMaxSize().padding(horizontal = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { art(if (Device.isTV) 340.dp else 320.dp) }
                    Spacer(Modifier.width(48.dp))
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { info() }
                }
            } else {
                Column(
                    Modifier.fillMaxSize().padding(horizontal = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.SpaceEvenly
                ) {
                    art(280.dp)
                    info()
                }
            }
        }
    }

    if (showSleep) SleepTimerDialog(onDismiss = { showSleep = false })
}

/** Vervaagde art als achtergrond (blur vanaf Android 12, anders verloop) */
@Composable
private fun EpisodeBackdrop(e: Episode) {
    Box(Modifier.fillMaxSize()) {
        if (Build.VERSION.SDK_INT >= 31) {
            PodcastArt(
                e.art, e.podcastName,
                Modifier.fillMaxHeight().aspectRatio(1f, matchHeightConstraintsFirst = true).align(Alignment.Center)
                    .graphicsLayer { scaleX = 1.4f; scaleY = 1.4f }.blur(60.dp),
                radius = 0.dp
            )
        } else {
            Box(Modifier.fillMaxSize().background(T.paletteBrush(e.podcastName)))
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Black.copy(alpha = 0.6f), T.bg))))
    }
}

/**
 * Tijdbalk: telefoon/tablet een sleepbare Slider; tv een focusbare balk (D-pad links/rechts = −15/+30 s,
 * OK = afspelen/pauze). Eronder verstreken en resterende tijd.
 */
@Composable
private fun TimeBar(modifier: Modifier = Modifier) {
    val position by RadioController.position.collectAsState()
    val duration by RadioController.duration.collectAsState()
    var dragging by remember { mutableStateOf<Float?>(null) }
    val fraction = if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f
    val shown = dragging ?: fraction
    val shownMs = if (duration > 0) (shown * duration).toLong() else position

    Column(modifier) {
        if (Device.isTV) {
            var focused by remember { mutableStateOf(false) }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(28.dp)
                    .onPreviewKeyEvent { ev ->
                        if (ev.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                        when (ev.key) {
                            Key.DirectionLeft -> { RadioController.skipBack(); true }
                            Key.DirectionRight -> { RadioController.skipForward(); true }
                            Key.DirectionCenter, Key.Enter -> { RadioController.togglePlay(); true }
                            else -> false
                        }
                    }
                    .tvFocus(RoundedCornerShape(14.dp), scale = 1.02f)
                    .onFocusChanged { focused = it.isFocused }
                    .focusable()
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (focused) Color.White.copy(alpha = 0.12f) else Color.Transparent)
                    .padding(horizontal = 10.dp),
                contentAlignment = Alignment.CenterStart
            ) {
                Box(Modifier.fillMaxWidth().height(if (focused) 8.dp else 5.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.25f))) {
                    Box(Modifier.fillMaxHeight().fillMaxWidth(shown).clip(CircleShape).background(T.accentHorizontal))
                }
            }
            if (focused) {
                Text(stringResource(R.string.tv_seek_hint), color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp,
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 4.dp))
            }
        } else {
            Slider(
                value = shown,
                onValueChange = { dragging = it },
                onValueChangeFinished = {
                    val d = dragging
                    if (d != null && duration > 0) RadioController.seekTo((d * duration).toLong())
                    dragging = null
                },
                enabled = duration > 0,
                modifier = Modifier.fillMaxWidth(),
                colors = SliderDefaults.colors(
                    thumbColor = Color.White, activeTrackColor = T.accent, inactiveTrackColor = Color.White.copy(alpha = 0.25f),
                    disabledThumbColor = Color.White.copy(alpha = 0.5f), disabledInactiveTrackColor = Color.White.copy(alpha = 0.2f)
                )
            )
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
            Text(formatClock(shownMs), color = Color.White.copy(alpha = 0.75f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text(
                if (duration > 0) "−" + formatClock((duration - shownMs).coerceAtLeast(0L)) else "",
                color = Color.White.copy(alpha = 0.75f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold
            )
        }
    }
}

/** Snelheid: knop met menu 0,8× – 2× */
@Composable
private fun SpeedButton() {
    val speed by RadioController.speed.collectAsState()
    var open by remember { mutableStateOf(false) }
    Box {
        ActionButton(Icons.Rounded.Speed, speedLabel(speed)) { open = true }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = T.elevated) {
            SPEEDS.forEach { v ->
                DropdownMenuItem(
                    text = {
                        Text(speedLabel(v), color = if (v == speed) T.accent else T.text,
                            fontWeight = if (v == speed) FontWeight.Bold else FontWeight.Normal)
                    },
                    onClick = { open = false; RadioController.setSpeed(v) }
                )
            }
        }
    }
}

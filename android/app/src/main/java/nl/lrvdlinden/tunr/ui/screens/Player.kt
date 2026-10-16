package nl.lrvdlinden.tunr.ui.screens

import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.automirrored.rounded.VolumeDown
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.CircleIconButton
import nl.lrvdlinden.tunr.ui.EqualizerBars
import nl.lrvdlinden.tunr.ui.LivePill
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.StationArt
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.tvClickable

/**
 * Volledige speler (SPEC §4 + §6): vervaagde art als achtergrond, LIVE-pil boven de art, titel/artiest of zendernaam,
 * vorige · play/pauze · volgende, favoriet, acties Delen/Slaaptimer/Zenderinfo, volume (telefoon). Omlaag slepen sluit.
 */
@Composable
fun PlayerScreen(onClose: () -> Unit) {
    val station by RadioController.station.collectAsState()
    val s = station ?: return
    val playing by RadioController.isPlaying.collectAsState()
    val buffering by RadioController.buffering.collectAsState()
    val error by RadioController.error.collectAsState()
    val np by RadioController.nowPlaying.collectAsState()
    val art by RadioController.artwork.collectAsState()
    val queue by RadioController.queue.collectAsState()
    val favorites by Library.favorites.collectAsState()
    val fav = favorites.any { it.uuid == s.uuid }
    val context = LocalContext.current
    var showSleep by remember { mutableStateOf(false) }
    var drag by remember { mutableFloatStateOf(0f) }
    val dragAnim by animateFloatAsState(drag, label = "drag")
    val playFocus = rememberInitialFocus(key = s.uuid)
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
        Backdrop(s, art)

        val content: @Composable (Dp) -> Unit = { artSize ->
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                LivePill()
                Spacer(Modifier.height(14.dp))
                Box(Modifier.size(artSize), contentAlignment = Alignment.Center) {
                    StationArt(s, Modifier.fillMaxSize(), radius = 22.dp, overrideUrl = art)
                }
            }
        }

        val info: @Composable () -> Unit = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (playing) { EqualizerBars(); Spacer(Modifier.width(8.dp)) }
                    Text(
                        if (np != null) np!!.title else s.displayName,
                        style = heading(if (Device.isTV) 32.sp else 24.sp), textAlign = TextAlign.Center,
                        maxLines = 2, overflow = TextOverflow.Ellipsis
                    )
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    when {
                        error -> stringResource(R.string.station_unreachable)
                        np != null -> listOfNotNull(np!!.artist, s.displayName).joinToString(" · ")
                        else -> s.genresLine.ifEmpty { s.placeLine() }
                    },
                    color = if (error) T.live else Color.White.copy(alpha = 0.75f), fontSize = 16.sp,
                    textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(24.dp))

                // vorige · play/pauze · volgende
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                    CircleIconButton(Icons.Rounded.SkipPrevious, stringResource(R.string.previous_station), size = 56.dp,
                        tint = if (queue.size > 1) Color.White else Color.White.copy(alpha = 0.35f), background = Color.Transparent) {
                        RadioController.previous()
                    }
                    Box(contentAlignment = Alignment.Center) {
                        if (buffering && !error) CircularProgressIndicator(Modifier.size(86.dp), color = Color.White, strokeWidth = 2.dp)
                        CircleIconButton(
                            when { error -> Icons.Rounded.Refresh; playing || buffering -> Icons.Rounded.Pause; else -> Icons.Rounded.PlayArrow },
                            stringResource(if (playing) R.string.pause else R.string.play),
                            size = 76.dp, background = T.accent, focusRequester = playFocus
                        ) { if (error) RadioController.retry() else RadioController.togglePlay() }
                    }
                    CircleIconButton(Icons.Rounded.SkipNext, stringResource(R.string.next_station), size = 56.dp,
                        tint = if (queue.size > 1) Color.White else Color.White.copy(alpha = 0.35f), background = Color.Transparent) {
                        RadioController.next()
                    }
                }

                if (error) {
                    Spacer(Modifier.height(10.dp))
                    Text(stringResource(R.string.retry), color = T.accent, fontWeight = FontWeight.Bold,
                        modifier = Modifier.tvClickable(CircleShape) { RadioController.retry() }.padding(horizontal = 12.dp, vertical = 6.dp))
                }

                Spacer(Modifier.height(22.dp))
                // Meer van deze zender
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ActionButton(if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                        stringResource(if (fav) R.string.favorite else R.string.add_favorite), tint = if (fav) T.accent else Color.White) {
                        Library.toggleFavorite(s)
                    }
                    if (!Device.isTV) ActionButton(Icons.Rounded.Share, stringResource(R.string.share)) { shareStation(context, s) }
                    ActionButton(Icons.Rounded.Bedtime, sleepLabel()) { showSleep = true }
                    ActionButton(Icons.Rounded.Info, stringResource(R.string.station_info)) { onClose(); Nav.station(s) }
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
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { content(if (Device.isTV) 340.dp else 320.dp) }
                    Spacer(Modifier.width(48.dp))
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { info() }
                }
            } else {
                Column(
                    Modifier.fillMaxSize().padding(horizontal = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.SpaceEvenly
                ) {
                    content(300.dp)
                    info()
                }
            }
        }
    }

    if (showSleep) SleepTimerDialog(onDismiss = { showSleep = false })
}

@Composable
private fun Backdrop(s: Station, art: String?) {
    Box(Modifier.fillMaxSize()) {
        if (Build.VERSION.SDK_INT >= 31) {
            StationArt(s, Modifier.fillMaxHeight().aspectRatio(1f, matchHeightConstraintsFirst = true).align(Alignment.Center)
                .graphicsLayer { scaleX = 1.4f; scaleY = 1.4f }.blur(60.dp), radius = 0.dp, overrideUrl = art)
        } else {
            Box(Modifier.fillMaxSize().background(T.paletteBrush(s.displayName)))
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Black.copy(alpha = 0.6f), T.bg))))
    }
}

@Composable
private fun ActionButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tint: Color = Color.White, onClick: () -> Unit) {
    Column(
        Modifier.width(if (Device.isTV) 104.dp else 78.dp).tvClickable(RoundedCornerShape(14.dp), scale = 1.06f, onClick = onClick)
            .background(Color.White.copy(alpha = 0.08f)).padding(vertical = 10.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(22.dp))
        Spacer(Modifier.height(4.dp))
        Text(label, color = Color.White, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

/** "Slaaptimer" of de resterende tijd ("23:45") */
@Composable
private fun sleepLabel(): String {
    val until by RadioController.sleepUntil.collectAsState()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(until) {
        while (until != null) { now = System.currentTimeMillis(); delay(1_000) }
    }
    val u = until ?: return stringResource(R.string.sleep_timer)
    val left = ((u - now) / 1000).coerceAtLeast(0)
    return "%d:%02d".format(left / 60, left % 60)
}

/** Slaaptimer: 15/30/45/60/90 min of uit */
@Composable
fun SleepTimerDialog(onDismiss: () -> Unit) {
    val until by RadioController.sleepUntil.collectAsState()
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = T.elevated,
        title = { Text(stringResource(R.string.sleep_timer), style = heading(20.sp)) },
        text = {
            Column {
                val first = rememberInitialFocus()
                listOf(15, 30, 45, 60, 90).forEachIndexed { i, m ->
                    Text(
                        stringResource(R.string.minutes_n, m), color = T.text, fontSize = 16.sp,
                        modifier = Modifier.fillMaxWidth()
                            .tvClickable(RoundedCornerShape(10.dp), scale = 1.02f, focusRequester = if (i == 0) first else null) {
                                RadioController.setSleepTimer(m); onDismiss()
                            }
                            .padding(horizontal = 8.dp, vertical = 12.dp)
                    )
                }
                if (until != null) {
                    Text(
                        stringResource(R.string.sleep_off), color = T.accent, fontSize = 16.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier.fillMaxWidth()
                            .tvClickable(RoundedCornerShape(10.dp), scale = 1.02f) { RadioController.setSleepTimer(0); onDismiss() }
                            .padding(horizontal = 8.dp, vertical = 12.dp)
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = T.secondary) } },
    )
}

/** Volume van het mediakanaal (AudioManager), volgt ook de volumeknoppen */
@Composable
private fun VolumeSlider(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val audio = remember { context.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val max = remember { audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1) }
    var value by remember { mutableFloatStateOf(audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / max) }
    DisposableEffect(Unit) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                value = audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / max
            }
        }
        context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.AutoMirrored.Rounded.VolumeDown, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp))
        Slider(
            value = value,
            onValueChange = {
                value = it
                runCatching { audio.setStreamVolume(AudioManager.STREAM_MUSIC, (it * max).toInt(), 0) }
            },
            modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
            colors = SliderDefaults.colors(
                thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(alpha = 0.25f)
            )
        )
        Icon(Icons.AutoMirrored.Rounded.VolumeUp, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp))
    }
}

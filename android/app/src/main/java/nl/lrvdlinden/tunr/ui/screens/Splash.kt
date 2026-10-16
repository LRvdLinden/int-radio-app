package nl.lrvdlinden.tunr.ui.screens

import android.media.AudioAttributes
import android.media.MediaPlayer
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.heading
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Splash (SPEC §3.1, ±3,4 s): frequentieschaal 88–108 fadet in, de naald zoekt met haperingen (0–1,4 s), op 1,45 s
 * klik/lock met 3 cirkelgolven, de letters T U N R springen één voor één omhoog (90 ms uit elkaar) terwijl de schaal
 * krimpt tot de balk onder het woordmerk, glanzende veeg (2,1 s) en fade-out (3,1–3,4 s).
 * Overslaan met tikken, OK (D-pad) of terug. Tune als Instellingen → Intromuziek aan staat.
 */
@Composable
fun SplashScreen(onFinished: () -> Unit) {
    val context = LocalContext.current
    val finish by rememberUpdatedState(onFinished)
    var done by remember { mutableStateOf(false) }
    val clock = remember { Animatable(0f) }
    val focus = remember { FocusRequester() }

    fun skip() {
        if (done) return
        done = true
        finish()
    }

    // Tune (mengt met andere audio: MediaPlayer vraagt zelf geen audiofocus)
    DisposableEffect(Unit) {
        val player: MediaPlayer? = if (Library.settings.value.introMusic) runCatching {
            MediaPlayer.create(
                context, R.raw.tunr_tune,
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build(),
                0
            )?.apply { setVolume(0.8f, 0.8f); start() }
        }.getOrNull() else null
        onDispose { runCatching { player?.stop(); player?.release() } }
    }

    LaunchedEffect(Unit) {
        runCatching { focus.requestFocus() }
        clock.animateTo(TOTAL, tween((TOTAL * 1000).roundToInt(), easing = LinearEasing))
        skip()
    }

    BackHandler { skip() }

    val t = clock.value
    val fadeOut = 1f - ((t - 3.1f) / 0.3f).coerceIn(0f, 1f)

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(focus)
            .focusable()
            .onKeyEvent {
                if (it.type == KeyEventType.KeyUp && (it.key == Key.DirectionCenter || it.key == Key.Enter ||
                        it.key == Key.NumPadEnter || it.key == Key.Spacebar)) { skip(); true } else false
            }
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { skip() }
            .graphicsLayer { alpha = fadeOut },
        contentAlignment = Alignment.Center
    ) {
        val density = LocalDensity.current
        val scaleW = min(maxWidth * 0.82f, 560.dp)
        val wordSize = if (maxWidth > 700.dp) 84.sp else 64.sp
        val wordPx = with(density) { wordSize.toPx() }
        val logoW = with(density) { (wordPx * 2.75f).toDp() }
        val measurer = rememberTextMeasurer()
        val labelStyle = TextStyle(color = T.secondary, fontSize = 11.sp)

        // Fasen
        val scaleIn = (t / 0.35f).coerceIn(0f, 1f)
        val needle = needlePosition(t)
        val locked = t >= LOCK
        val shrink = easeInOut(((t - 1.6f) / 0.5f).coerceIn(0f, 1f))

        Canvas(Modifier.fillMaxSize()) {
            val cx = size.width / 2
            val cy = size.height / 2
            val fullW = scaleW.toPx()
            val endW = logoW.toPx()
            val w = fullW + (endW - fullW) * shrink
            val left = cx - w / 2
            // eindpositie van de balk: net onder het woordmerk
            val endY = cy + wordPx * 0.55f
            val y = cy + (endY - cy) * shrink
            val alphaIn = scaleIn

            // basislijn → balk in het accentverloop
            val barH = (2.dp.toPx() + (wordPx * 0.12f - 2.dp.toPx()) * shrink)
            drawRoundRect(
                brush = Brush.horizontalGradient(listOf(T.accent, T.accent2), startX = left, endX = left + w),
                topLeft = Offset(left, y - barH / 2), size = Size(w, barH),
                cornerRadius = CornerRadius(barH / 2, barH / 2), alpha = alphaIn * (0.55f + 0.45f * shrink)
            )

            // maatstreepjes 88–108 + getallen; worden er 9 bij het krimpen
            val tickAlpha = alphaIn * (1f - shrink)
            if (tickAlpha > 0.01f) {
                for (mhz in 88..108) {
                    val f = (mhz - 88) / 20f
                    val x = left + w * f
                    val major = mhz % 4 == 0
                    val h = if (major) 18.dp.toPx() else 9.dp.toPx()
                    drawLine(Color.White.copy(alpha = if (major) 0.8f else 0.4f), Offset(x, y - barH / 2 - 3.dp.toPx()),
                        Offset(x, y - barH / 2 - 3.dp.toPx() - h), 1.5.dp.toPx(), StrokeCap.Round, alpha = tickAlpha)
                    if (major) {
                        val layout = measurer.measure("$mhz", labelStyle)
                        drawText(layout, topLeft = Offset(x - layout.size.width / 2f, y + 10.dp.toPx()), alpha = tickAlpha)
                    }
                }
            }
            if (shrink > 0.01f) {
                for (i in 0 until 9) {
                    val x = left + w * (0.1f + 0.8f * i / 8f)
                    val h = wordPx * (if (i % 2 == 0) 0.2f else 0.14f)
                    drawLine(Color.White.copy(alpha = 0.55f), Offset(x, y - barH / 2), Offset(x, y - barH / 2 - h),
                        2.dp.toPx(), StrokeCap.Round, alpha = shrink)
                }
            }

            // naald: zoekt, lockt, gaat mee naar 58% van de balk
            val nf = if (locked) LOCK_POS + (0.58f - LOCK_POS) * shrink else needle
            val nx = left + w * nf
            val nTop = y - barH / 2 - (34.dp.toPx() * (1f - shrink) + wordPx * 0.3f * shrink)
            val nBottom = y + barH / 2 + 6.dp.toPx() * (1f - shrink)
            drawLine(T.accent2, Offset(nx, nTop), Offset(nx, nBottom), (2.5.dp.toPx() + 1.5.dp.toPx() * shrink), StrokeCap.Round, alpha = alphaIn)
            if (!locked) drawCircle(T.accent2.copy(alpha = 0.35f), 10.dp.toPx(), Offset(nx, y), alpha = alphaIn)

            // 3 cirkelgolven vanaf de lock
            if (locked) {
                for (i in 0 until 3) {
                    val p = ((t - LOCK - i * 0.12f) / 0.9f).coerceIn(0f, 1f)
                    if (p in 0.001f..0.999f) {
                        drawCircle(T.accent, radius = 12.dp.toPx() + p * fullW * 0.45f, center = Offset(nx, y),
                            alpha = (1f - p) * 0.7f, style = Stroke(width = (3.dp.toPx() * (1f - p)).coerceAtLeast(0.5f)))
                    }
                }
            }
        }

        // Woordmerk: letters springen één voor één omhoog, met glanzende veeg
        Row(
            Modifier
                .offset { IntOffset(0, (-wordPx * 0.12f).roundToInt()) }
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    val sp = ((t - 2.1f) / 0.55f).coerceIn(0f, 1f)
                    if (sp > 0f && sp < 1f) {
                        val x = -size.width * 0.4f + size.width * 1.8f * sp
                        drawRect(
                            Brush.linearGradient(
                                listOf(Color.Transparent, Color.White.copy(alpha = 0.85f), Color.Transparent),
                                start = Offset(x - size.width * 0.25f, 0f), end = Offset(x + size.width * 0.25f, size.height)
                            ),
                            blendMode = BlendMode.SrcAtop
                        )
                    }
                }
        ) {
            "TUNR".forEachIndexed { i, ch ->
                val start = LOCK + 0.05f + i * 0.09f
                val p = ((t - start) / 0.32f).coerceIn(0f, 1f)
                val jump = if (p <= 0f) 0f else backOut(p)
                androidx.compose.material3.Text(
                    ch.toString(),
                    style = heading(wordSize),
                    modifier = Modifier.graphicsLayer {
                        alpha = (p * 2.5f).coerceIn(0f, 1f)
                        translationY = (1f - jump) * wordPx * 0.6f
                        scaleX = 0.85f + 0.15f * jump; scaleY = 0.85f + 0.15f * jump
                    }
                )
            }
        }
    }
}

private const val TOTAL = 3.4f
private const val LOCK = 1.45f
private const val LOCK_POS = 0.62f

/** Naald zoekt van links naar rechts met haperingen (0–1,4 s), daarna vast op [LOCK_POS] */
private fun needlePosition(t: Float): Float {
    if (t >= LOCK) return LOCK_POS
    val p = (t / 1.4f).coerceIn(0f, 1f)
    // Gaat te ver door, twijfelt, en komt dan op de zender uit
    val sweep = when {
        p < 0.55f -> easeInOut(p / 0.55f) * 0.82f
        p < 0.75f -> 0.82f - easeInOut((p - 0.55f) / 0.2f) * 0.3f
        else -> 0.52f + easeInOut((p - 0.75f) / 0.25f) * (LOCK_POS - 0.52f)
    }
    val jitter = (sin(p * 38f * PI.toFloat()) * 0.008f + sin(p * 13f * PI.toFloat()) * 0.006f) * (1f - p)
    return (0.05f + sweep * 0.95f + jitter).coerceIn(0.02f, 0.98f)
}

private fun easeInOut(x: Float): Float = if (x < 0.5f) 2 * x * x else 1 - (-2 * x + 2).let { it * it } / 2

/** Even voorbij schieten en terugveren */
private fun backOut(x: Float): Float {
    val c1 = 1.70158f
    val c3 = c1 + 1
    val y = x - 1
    return 1 + c3 * y * y * y + c1 * y * y
}

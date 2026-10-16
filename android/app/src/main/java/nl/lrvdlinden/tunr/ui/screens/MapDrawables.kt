package nl.lrvdlinden.tunr.ui.screens

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import kotlin.math.min

private const val ACCENT = 0xFFFF5A1F.toInt()
private const val ACCENT2 = 0xFFFFB020.toInt()

/** Gloeiende stip voor één zender (accent met zachte gloed). [pulse] 0..1 laat de gloed uitdijen (zender die speelt). */
class GlowDotDrawable(private val sizePx: Int, private val core: Int = ACCENT, private val playing: Boolean = false) : Drawable() {
    var pulse: Float = 0f
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG)
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = core }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt(); style = Paint.Style.STROKE }

    override fun draw(canvas: Canvas) {
        val b = bounds
        val cx = b.exactCenterX()
        val cy = b.exactCenterY()
        val r = min(b.width(), b.height()) / 2f
        val glowR = if (playing) r * (0.65f + 0.35f * pulse) else r
        glow.shader = RadialGradient(cx, cy, glowR.coerceAtLeast(1f),
            intArrayOf(withAlpha(core, if (playing) (200 * (1f - 0.6f * pulse)).toInt() else 150), withAlpha(core, 40), withAlpha(core, 0)),
            floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP)
        canvas.drawCircle(cx, cy, glowR, glow)
        val coreR = r * (if (playing) 0.3f else 0.22f)
        canvas.drawCircle(cx, cy, coreR, dot)
        if (playing) {
            ring.strokeWidth = r * 0.07f
            canvas.drawCircle(cx, cy, coreR, ring)
        }
    }

    override fun getIntrinsicWidth() = sizePx
    override fun getIntrinsicHeight() = sizePx
    override fun setAlpha(alpha: Int) { dot.alpha = alpha }
    override fun setColorFilter(colorFilter: ColorFilter?) { dot.colorFilter = colorFilter }
    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

/** Cluster: rondje in het accentverloop met gloed en het aantal zenders */
class ClusterDrawable(private val count: Int, private val density: Float) : Drawable() {
    private val sizePx = ((when {
        count < 10 -> 34
        count < 100 -> 42
        else -> 50
    }) * density).toInt()
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG)
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFFFFF.toInt()
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    override fun draw(canvas: Canvas) {
        val b = bounds
        val cx = b.exactCenterX()
        val cy = b.exactCenterY()
        val r = min(b.width(), b.height()) / 2f
        glow.shader = RadialGradient(cx, cy, r, intArrayOf(withAlpha(ACCENT, 120), withAlpha(ACCENT, 0)), null, Shader.TileMode.CLAMP)
        canvas.drawCircle(cx, cy, r, glow)
        val inner = r * 0.68f
        fill.shader = android.graphics.LinearGradient(cx - inner, cy - inner, cx + inner, cy + inner, ACCENT, ACCENT2, Shader.TileMode.CLAMP)
        canvas.drawCircle(cx, cy, inner, fill)
        text.textSize = inner * (if (count >= 1000) 0.62f else 0.8f)
        val label = if (count >= 1000) "${count / 1000}k" else count.toString()
        canvas.drawText(label, cx, cy - (text.descent() + text.ascent()) / 2, text)
    }

    override fun getIntrinsicWidth() = sizePx
    override fun getIntrinsicHeight() = sizePx
    override fun setAlpha(alpha: Int) { fill.alpha = alpha }
    override fun setColorFilter(colorFilter: ColorFilter?) { fill.colorFilter = colorFilter }
    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

private fun withAlpha(color: Int, alpha: Int): Int = (color and 0x00FFFFFF) or (alpha.coerceIn(0, 255) shl 24)

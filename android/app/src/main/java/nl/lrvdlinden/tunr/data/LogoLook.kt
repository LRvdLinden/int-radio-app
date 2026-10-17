package nl.lrvdlinden.tunr.data

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Maat en achtergrondkleur van een zenderlogo (SPEC §1, zelfde regels als Apple `LogoLook` en de webspeler).
 * Groot logo → vult de tegel (crop); klein logo → gecentreerd, fit, hooguit 2× de eigen pixelmaat en hooguit 62%
 * van de tegel, op een effen achtergrond die bij het logo past. Eén keer per afbeelding berekend en per URL onthouden.
 */
data class LogoLook(val pixelWidth: Int, val pixelHeight: Int, val background: Int) {
    val minSide: Int get() = min(pixelWidth, pixelHeight)
    val maxSide: Int get() = max(pixelWidth, pixelHeight)

    /** Groot genoeg om de hele tegel te vullen? (`tilePx` = zijde van de tegel in pixels) */
    fun isLarge(tilePx: Float): Boolean = minSide >= 0.75f * tilePx || minSide >= 160

    /** Zijde (pixels) van het vak waarin een klein logo (fit) getekend wordt */
    fun smallBox(tilePx: Float): Float = max(1f, min(2f * maxSide, 0.62f * tilePx))

    companion object {
        /** Tunr-surface #16161A (achter lichte/witte transparante logo's) */
        const val SURFACE = 0xFF16161A.toInt()
        const val WHITE = 0xFFFFFFFF.toInt()

        private val cache = ConcurrentHashMap<String, LogoLook>()

        fun cached(url: String): LogoLook? = cache[url]

        /** Weergave van dit logo, eenmalig berekend per URL */
        fun of(url: String, bitmap: Bitmap): LogoLook =
            cache[url] ?: analyze(bitmap).also { cache[url] = it }

        /** Software-kopie als het een hardware-bitmap is (die kun je niet uitlezen of op een Canvas tekenen) */
        fun software(bitmap: Bitmap): Bitmap =
            if (Build.VERSION.SDK_INT >= 26 && bitmap.config == Bitmap.Config.HARDWARE) {
                bitmap.copy(Bitmap.Config.ARGB_8888, false) ?: bitmap
            } else bitmap

        /**
         * Achtergrond uit de randpixels: dekkend → hun gemiddelde kleur (het logo loopt over in zijn eigen
         * achtergrond); transparant → wit bij een donker/gekleurd logo, surface bij een licht/wit logo.
         */
        fun analyze(bitmap: Bitmap): LogoLook {
            val w = bitmap.width
            val h = bitmap.height
            var bg = WHITE
            runCatching {
                val n = 24
                val small = Bitmap.createScaledBitmap(software(bitmap), n, n, true)
                val px = IntArray(n * n)
                small.getPixels(px, 0, n, 0, 0, n, n)
                var edgeTotal = 0
                var edgeOpaque = 0
                var er = 0f; var eg = 0f; var eb = 0f
                var solid = 0
                var light = 0
                for (y in 0 until n) for (x in 0 until n) {
                    val c = px[y * n + x]
                    val a = (c ushr 24 and 0xFF) / 255f
                    val r = (c shr 16 and 0xFF) / 255f
                    val g = (c shr 8 and 0xFF) / 255f
                    val b = (c and 0xFF) / 255f
                    if (x == 0 || y == 0 || x == n - 1 || y == n - 1) {
                        edgeTotal++
                        if (a >= 0.9f) { edgeOpaque++; er += r; eg += g; eb += b }
                    }
                    if (a >= 0.5f) {
                        solid++
                        val lum = 0.2126f * r + 0.7152f * g + 0.0722f * b
                        val sat = maxOf(r, g, b) - minOf(r, g, b)
                        if (lum > 0.78f && sat < 0.2f) light++
                    }
                }
                bg = when {
                    edgeTotal > 0 && edgeOpaque >= 0.75f * edgeTotal -> {
                        val k = edgeOpaque.toFloat()
                        (0xFF shl 24) or ((er / k * 255).roundToInt().coerceIn(0, 255) shl 16) or
                            ((eg / k * 255).roundToInt().coerceIn(0, 255) shl 8) or
                            (eb / k * 255).roundToInt().coerceIn(0, 255)
                    }
                    solid > 0 && light > 0.6f * solid -> SURFACE
                    else -> WHITE
                }
            }
            return LogoLook(w, h, bg)
        }
    }

    /**
     * Vierkante bitmap van `side` pixels met het logo volgens dezelfde regels als de tegel in de app
     * (mediasessie: melding, vergrendelscherm, Android Auto).
     */
    fun compose(bitmap: Bitmap, side: Int): Bitmap {
        val src = software(bitmap)
        val out = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(background)
        val s = side.toFloat()
        val w = max(1, src.width).toFloat()
        val h = max(1, src.height).toFloat()
        val k = if (isLarge(s)) max(s / w, s / h) else smallBox(s).let { box -> min(box / w, box / h) }
        val dw = w * k
        val dh = h * k
        val dst = RectF((s - dw) / 2f, (s - dh) / 2f, (s + dw) / 2f, (s + dh) / 2f)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG or Paint.DITHER_FLAG)
        canvas.drawBitmap(src, Rect(0, 0, src.width, src.height), dst, paint)
        return out
    }
}

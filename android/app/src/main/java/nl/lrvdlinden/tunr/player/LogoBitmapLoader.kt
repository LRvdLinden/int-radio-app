@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package nl.lrvdlinden.tunr.player

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.media3.common.util.BitmapLoader
import androidx.media3.datasource.DataSourceBitmapLoader
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import nl.lrvdlinden.tunr.data.LogoLook

/**
 * Afbeeldingen voor de mediasessie (melding, vergrendelscherm, Android Auto "nu speelt"): zelfde regels als
 * StationArt (SPEC §1, [LogoLook]). Een klein logo wordt gecentreerd op zijn eigen effen achtergrond in een vierkant
 * van [SIDE] px gezet in plaats van opgerekt; grote afbeeldingen (albumhoes, App Store-icoon) vullen het vierkant.
 * Onthoudt de laatste URI, zodat het bijwerken van de metadata (ICY-titel) niet steeds opnieuw laadt.
 */
class LogoBitmapLoader(context: Context) : BitmapLoader {
    private val delegate = DataSourceBitmapLoader(context.applicationContext)
    private var lastUri: Uri? = null
    private var lastFuture: ListenableFuture<Bitmap>? = null

    override fun supportsMimeType(mimeType: String): Boolean = delegate.supportsMimeType(mimeType)

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> = square(delegate.decodeBitmap(data), null)

    @Synchronized
    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        val last = lastFuture
        if (last != null && uri == lastUri) {
            val broken = last.isDone && runCatching { last.get() }.isFailure
            if (!broken) return last
        }
        val f = square(delegate.loadBitmap(uri), uri.toString())
        lastUri = uri
        lastFuture = f
        return f
    }

    private fun square(future: ListenableFuture<Bitmap>, key: String?): ListenableFuture<Bitmap> =
        Futures.transform(
            future,
            com.google.common.base.Function<Bitmap, Bitmap> { b ->
                runCatching {
                    val look = if (key != null) LogoLook.of(key, b) else LogoLook.analyze(b)
                    look.compose(b, SIDE)
                }.getOrDefault(b)
            },
            MoreExecutors.directExecutor()
        )

    companion object {
        const val SIDE = 512
    }
}

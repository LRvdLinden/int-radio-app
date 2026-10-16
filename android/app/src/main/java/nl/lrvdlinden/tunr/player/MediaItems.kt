package nl.lrvdlinden.tunr.player

import android.net.Uri
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import nl.lrvdlinden.tunr.data.Station
import java.util.concurrent.ConcurrentHashMap

/**
 * Zenders die de app of Android Auto ooit als MediaItem heeft gezien, op uuid. Dienst en app draaien in hetzelfde
 * proces, dus beide kunnen een mediaId weer naar een volledige zender vertalen.
 */
object StationCache {
    private val map = ConcurrentHashMap<String, Station>()
    fun put(s: Station) { if (s.uuid.isNotEmpty()) map[s.uuid] = s }
    fun putAll(list: List<Station>) = list.forEach { put(it) }
    operator fun get(uuid: String?): Station? = uuid?.let { map[it] }
}

/** Sleutels in MediaMetadata.extras */
object Extras {
    const val ALT_URL = "tunr.alt_url"
    const val NP_ARTIST = "tunr.np_artist"
    const val NP_TITLE = "tunr.np_title"
    const val NP_ART = "tunr.np_art"
    const val STATION_ART = "tunr.station_art"
    const val GENRES = "tunr.genres"
}

/** Zender → afspeelbaar MediaItem (ook voor de bladerboom van Android Auto). */
fun Station.toMediaItem(): MediaItem {
    StationCache.put(this)
    val extras = Bundle().apply {
        val alt = url.trim()
        if (alt.isNotEmpty() && alt != streamUrl) putString(Extras.ALT_URL, alt)
        putString(Extras.STATION_ART, favicon)
        putString(Extras.GENRES, genresLine)
    }
    val meta = MediaMetadata.Builder()
        .setTitle(displayName)
        .setDisplayTitle(displayName)
        .setArtist(genresLine.ifEmpty { placeLine() })
        .setSubtitle(placeLine())
        .setStation(displayName)
        .setArtworkUri(favicon.trim().takeIf { it.startsWith("http") }?.let { Uri.parse(it) })
        .setIsPlayable(true)
        .setIsBrowsable(false)
        .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
        .setExtras(extras)
        .build()
    val uri = streamUrl
    return MediaItem.Builder()
        .setMediaId(uuid)
        .setUri(uri)
        .apply { if (isHls) setMimeType(MimeTypes.APPLICATION_M3U8) }
        .setRequestMetadata(MediaItem.RequestMetadata.Builder().setMediaUri(Uri.parse(uri)).build())
        .setMediaMetadata(meta)
        .build()
}

/** Map in de bladerboom (Android Auto) */
fun folderItem(id: String, title: String, mediaType: Int = MediaMetadata.MEDIA_TYPE_FOLDER_RADIO_STATIONS): MediaItem =
    MediaItem.Builder()
        .setMediaId(id)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(title)
                .setIsBrowsable(true)
                .setIsPlayable(false)
                .setMediaType(mediaType)
                .build()
        )
        .build()

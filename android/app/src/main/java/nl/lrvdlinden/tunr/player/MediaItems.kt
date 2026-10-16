@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package nl.lrvdlinden.tunr.player

import android.net.Uri
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import nl.lrvdlinden.tunr.data.Episode
import nl.lrvdlinden.tunr.data.EpisodeCache
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
    const val DURATION_MS = "tunr.duration_ms"
    const val PODCAST_ID = "tunr.podcast_id"
}

/** mediaId-voorvoegsel voor podcastafleveringen ("ep:<trackId>"); zenders gebruiken hun uuid */
const val EPISODE_PREFIX = "ep:"

fun isEpisodeId(mediaId: String?): Boolean = mediaId?.startsWith(EPISODE_PREFIX) == true
fun episodeIdOf(mediaId: String?): String? = mediaId?.takeIf { it.startsWith(EPISODE_PREFIX) }?.removePrefix(EPISODE_PREFIX)

/** Aflevering → afspeelbaar MediaItem (mediaId "ep:<id>", titel, artiest = podcast, art, duur in extras). */
fun Episode.toMediaItem(): MediaItem {
    EpisodeCache.put(this)
    val extras = Bundle().apply {
        putLong(Extras.DURATION_MS, durationMs)
        putString(Extras.PODCAST_ID, podcastId)
    }
    val artUri = art.trim().takeIf { it.startsWith("http") }?.let { Uri.parse(it) }
    val meta = MediaMetadata.Builder()
        .setTitle(displayTitle)
        .setDisplayTitle(displayTitle)
        .setArtist(podcastName)
        .setAlbumTitle(podcastName)
        .setSubtitle(podcastName)
        .setArtworkUri(artUri)
        .setIsPlayable(true)
        .setIsBrowsable(false)
        .setMediaType(MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE)
        .setExtras(extras)
        .build()
    return MediaItem.Builder()
        .setMediaId(EPISODE_PREFIX + id)
        .setUri(url)
        .apply { if (url.contains(".m3u8", ignoreCase = true)) setMimeType(MimeTypes.APPLICATION_M3U8) }
        .setRequestMetadata(MediaItem.RequestMetadata.Builder().setMediaUri(Uri.parse(url)).build())
        .setMediaMetadata(meta)
        .build()
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

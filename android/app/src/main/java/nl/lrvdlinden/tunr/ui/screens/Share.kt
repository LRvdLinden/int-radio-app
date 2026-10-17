package nl.lrvdlinden.tunr.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import nl.lrvdlinden.tunr.Brand
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Station

/** Vaste links naar de webspeler op tunr.online (zelfde routes als website/assets/js/ui.js → T.ui.share). */
object ShareLinks {
    private fun web(route: String) = Brand.WEBSITE + "/web/#/" + route
    private fun enc(s: String): String = Uri.encode(s)
    fun station(uuid: String) = web("station/" + enc(uuid))
    fun podcast(id: String) = web("podcast/" + enc(id))
    fun episode(podcastId: String, episodeId: String) = web("episode/" + enc(podcastId) + "/" + enc(episodeId))
}

/** Deelt naam + vaste link naar de zender op tunr.online via het systeemmenu */
fun shareStation(context: Context, s: Station) {
    val link = ShareLinks.station(s.uuid)
    val text = context.getString(R.string.share_text, s.displayName, link)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, s.displayName)
        putExtra(Intent.EXTRA_TEXT, text)
    }
    runCatching {
        context.startActivity(Intent.createChooser(intent, context.getString(R.string.share)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** Deelt een aflevering met een vaste link naar tunr.online */
fun shareEpisode(context: Context, e: nl.lrvdlinden.tunr.data.Episode) {
    val link = ShareLinks.episode(e.podcastId, e.id)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, e.displayTitle)
        putExtra(Intent.EXTRA_TEXT, e.displayTitle + (if (e.podcastName.isNotEmpty()) " · " + e.podcastName else "") + "\n" + link)
    }
    runCatching {
        context.startActivity(Intent.createChooser(intent, context.getString(R.string.share)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** Opent een link in de browser (op tv vaak geen browser: dan gebeurt er niets) */
fun openUrl(context: Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

package nl.lrvdlinden.tunr.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Station

/** Deelt naam + homepage (of stream) via het systeemmenu */
fun shareStation(context: Context, s: Station) {
    val link = s.homepage.trim().takeIf { it.startsWith("http") } ?: s.streamUrl
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

/** Opent een link in de browser (op tv vaak geen browser: dan gebeurt er niets) */
fun openUrl(context: Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

package nl.lrvdlinden.tunr.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.AppState
import nl.lrvdlinden.tunr.ui.Chip
import nl.lrvdlinden.tunr.ui.CircleIconButton
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.EqualizerBars
import nl.lrvdlinden.tunr.ui.GridSource
import nl.lrvdlinden.tunr.ui.LivePill
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.PillButton
import nl.lrvdlinden.tunr.ui.StationArt
import nl.lrvdlinden.tunr.ui.StationRowSection
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.Tab
import nl.lrvdlinden.tunr.ui.TopBar
import nl.lrvdlinden.tunr.ui.bottomContentPadding
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.rememberLoad
import java.text.NumberFormat

/** Zenderdetail (SPEC §4): art, naam, plaats, knoppen, nu speelt, genres, info-raster, vergelijkbare zenders. */
@Composable
fun StationDetailScreen(station: Station, onClose: () -> Unit) {
    val wide = isWide()
    val similar = rememberLoad(station.uuid) {
        val tag = station.firstTag
        if (tag == null) emptyList()
        else RadioBrowser.byTag(tag, station.countryCode.ifEmpty { null }, 30).filter { it.uuid != station.uuid }
    }
    val playFocus = rememberInitialFocus(key = station.uuid)

    LazyColumn(
        Modifier.fillMaxSize().background(T.bg),
        contentPadding = PaddingValues(bottom = bottomContentPadding),
        verticalArrangement = Arrangement.spacedBy(Dims.sectionGap)
    ) {
        item { Box(Modifier.statusBarsPadding()) { TopBar("", onBack = onClose) } }
        item {
            if (wide) {
                Row(Modifier.padding(horizontal = Dims.edge), verticalAlignment = Alignment.Top) {
                    StationArt(station, Modifier.size(if (Device.isTV) 300.dp else 280.dp), radius = Dims.cardRadius)
                    Spacer(Modifier.width(32.dp))
                    Column(Modifier.weight(1f)) { DetailInfo(station, playFocus, alignStart = true) }
                }
            } else {
                Column(Modifier.fillMaxWidth().padding(horizontal = Dims.edge), horizontalAlignment = Alignment.CenterHorizontally) {
                    StationArt(station, Modifier.size(260.dp), radius = 20.dp)
                    Spacer(Modifier.height(20.dp))
                    DetailInfo(station, playFocus, alignStart = false)
                }
            }
        }
        item {
            StationRowSection(stringResource(R.string.similar_stations), similar,
                onSeeAll = station.firstTag?.let { t -> { Nav.grid(GridSource.Tag(t, station.countryCode.ifEmpty { null })) } })
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DetailInfo(s: Station, playFocus: androidx.compose.ui.focus.FocusRequester, alignStart: Boolean) {
    val context = LocalContext.current
    val current by RadioController.station.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val np by RadioController.nowPlaying.collectAsState()
    val art by RadioController.artwork.collectAsState()
    val favorites by Library.favorites.collectAsState()
    val fav = favorites.any { it.uuid == s.uuid }
    val isCurrent = current?.uuid == s.uuid
    val align = if (alignStart) TextAlign.Start else TextAlign.Center
    val hAlign = if (alignStart) Alignment.Start else Alignment.CenterHorizontally

    Column(Modifier.fillMaxWidth(), horizontalAlignment = hAlign) {
        Text(s.displayName, style = heading(if (Device.isTV) 34.sp else 28.sp), textAlign = align, maxLines = 3, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        Text(s.placeLine(), color = T.secondary, fontSize = 15.sp, textAlign = align)
        Spacer(Modifier.height(18.dp))

        FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp, if (alignStart) Alignment.Start else Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            PillButton(
                stringResource(if (isCurrent && playing) R.string.pause else R.string.play),
                if (isCurrent && playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                focusRequester = playFocus
            ) { if (isCurrent) RadioController.togglePlay() else RadioController.play(s, listOf(s)) }
            CircleIconButton(if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                stringResource(if (fav) R.string.remove_favorite else R.string.add_favorite),
                tint = if (fav) T.accent else androidx.compose.ui.graphics.Color.White) { Library.toggleFavorite(s) }
            if (!Device.isTV) CircleIconButton(Icons.Rounded.Share, stringResource(R.string.share)) { shareStation(context, s) }
            if (!Device.isTV && s.homepage.startsWith("http")) {
                CircleIconButton(Icons.Rounded.Language, stringResource(R.string.website)) { openUrl(context, s.homepage) }
            }
            if (s.hasGeo) CircleIconButton(Icons.Rounded.Public, stringResource(R.string.show_on_map)) {
                AppState.mapFocus = s; AppState.tab = Tab.MAP; Nav.clear()
            }
        }

        // Nu speelt
        if (isCurrent && np != null) {
            Spacer(Modifier.height(18.dp))
            Row(
                Modifier.widthIn(max = 520.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.surface).padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                StationArt(s, Modifier.size(52.dp), radius = 8.dp, overrideUrl = art)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LivePill(); Spacer(Modifier.width(8.dp)); EqualizerBars(playing = playing)
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(np!!.line, color = T.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }

        // Genres
        if (s.tagList.isNotEmpty()) {
            Spacer(Modifier.height(18.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp, if (alignStart) Alignment.Start else Alignment.CenterHorizontally),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                s.tagList.forEach { t -> Chip(t) { Nav.grid(GridSource.Tag(t, s.countryCode.ifEmpty { null })) } }
            }
        }

        // Info-raster
        Spacer(Modifier.height(18.dp))
        val nf = NumberFormat.getIntegerInstance()
        val rows = listOf(
            stringResource(R.string.info_codec) to s.codec.ifBlank { "—" },
            stringResource(R.string.info_bitrate) to (if (s.bitrate > 0) stringResource(R.string.kbps, s.bitrate) else "—"),
            stringResource(R.string.info_language) to s.language.split(',').firstOrNull()?.trim()?.replaceFirstChar { it.uppercase() }.orEmpty().ifBlank { "—" },
            stringResource(R.string.info_votes) to nf.format(s.votes),
            stringResource(R.string.info_listeners) to nf.format(s.clickCount),
            stringResource(R.string.info_hls) to stringResource(if (s.isHls) R.string.yes else R.string.no),
        )
        Column(Modifier.widthIn(max = 520.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.surface)) {
            rows.chunked(2).forEachIndexed { i, pair ->
                if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(T.stroke))
                Row(Modifier.fillMaxWidth()) {
                    pair.forEach { (k, v) ->
                        Column(Modifier.weight(1f).padding(14.dp)) {
                            Text(k, color = T.secondary, fontSize = 12.sp)
                            Text(v, color = T.text, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

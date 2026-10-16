package nl.lrvdlinden.tunr.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.ui.CircleIconButton
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.EmptyState
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.Route
import nl.lrvdlinden.tunr.ui.StationCard
import nl.lrvdlinden.tunr.ui.StationMenu
import nl.lrvdlinden.tunr.ui.StationRow
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.bottomContentPadding
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.tvClickable

/** Bibliotheek (SPEC §6): segmenten Favorieten · Recent; lang indrukken = verwijderen */
@Composable
fun LibraryScreen() {
    var segment by rememberSaveable { mutableStateOf(0) }
    val favorites by Library.favorites.collectAsState()
    val recents by Library.recents.collectAsState()
    var confirmClear by rememberSaveable { mutableStateOf(false) }
    val first = rememberInitialFocus()

    Column(Modifier.fillMaxSize().background(T.bg).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = Dims.edge, end = Dims.edge, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.tab_library), style = heading(if (Device.isTV) 34.sp else 28.sp), modifier = Modifier.weight(1f))
            if (!Device.isTV) CircleIconButton(Icons.Rounded.Settings, stringResource(R.string.settings), size = 40.dp, background = T.surface) {
                Nav.push(Route.Settings)
            }
        }
        // Gesegmenteerde keuze
        Row(
            Modifier.padding(horizontal = Dims.edge, vertical = 12.dp).widthIn(max = 420.dp).fillMaxWidth()
                .clip(RoundedCornerShape(12.dp)).background(T.surface).padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            listOf(R.string.tab_favorites, R.string.recent).forEachIndexed { i, label ->
                val sel = segment == i
                Box(
                    Modifier.weight(1f)
                        .tvClickable(RoundedCornerShape(9.dp), scale = 1.03f, focusRequester = if (i == 0) first else null) { segment = i }
                        .background(if (sel) T.accent else Color.Transparent)
                        .padding(vertical = 9.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(stringResource(label), color = if (sel) Color.White else T.secondary, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
            }
        }

        if (segment == 0) {
            if (favorites.isEmpty()) {
                EmptyState(Icons.Rounded.FavoriteBorder, stringResource(R.string.no_favorites_title), stringResource(R.string.no_favorites_message))
            } else {
                val min: Dp = if (isWide()) 150.dp else 104.dp
                LazyVerticalGrid(
                    columns = if (Device.isTV) GridCells.Fixed(6) else GridCells.Adaptive(min),
                    contentPadding = PaddingValues(start = Dims.edge, end = Dims.edge, top = 4.dp, bottom = bottomContentPadding),
                    horizontalArrangement = Arrangement.spacedBy(Dims.rowGap),
                    verticalArrangement = Arrangement.spacedBy(if (Device.isTV) 24.dp else 16.dp),
                ) {
                    itemsIndexed(favorites, key = { _, s -> s.uuid }) { _, s ->
                        // lang indrukken → menu met "Verwijderen uit favorieten"
                        StationCard(s, favorites, width = Dp.Unspecified)
                    }
                }
            }
        } else {
            if (recents.isEmpty()) {
                EmptyState(Icons.Rounded.History, stringResource(R.string.no_recents_title), stringResource(R.string.no_recents_message))
            } else {
                Row(Modifier.fillMaxWidth().padding(horizontal = Dims.edge), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.long_press_hint), color = T.secondary, fontSize = 13.sp, modifier = Modifier.weight(1f))
                    Text(stringResource(R.string.clear), color = T.accent, fontWeight = FontWeight.Bold,
                        modifier = Modifier.tvClickable(CircleShape) { confirmClear = true }.padding(horizontal = 10.dp, vertical = 6.dp))
                }
                LazyColumn(contentPadding = PaddingValues(start = Dims.edge - 8.dp, end = Dims.edge - 8.dp, top = 4.dp, bottom = bottomContentPadding)) {
                    itemsIndexed(recents, key = { _, s -> s.uuid }) { _, s -> RecentRow(s, recents) }
                }
            }
        }
    }

    if (confirmClear) ConfirmDialog(
        title = stringResource(R.string.clear_recents),
        message = stringResource(R.string.clear_recents_confirm),
        onConfirm = { Library.clearRecents(); confirmClear = false },
        onDismiss = { confirmClear = false }
    )
}

@Composable
private fun RecentRow(s: Station, list: List<Station>) {
    var menu by rememberSaveable(s.uuid) { mutableStateOf(false) }
    Box {
        StationRow(s, list, onLongClick = { menu = true })
        StationMenu(s, menu, onDismiss = { menu = false },
            extra = listOf(stringResource(R.string.remove_from_recent) to { Library.removeRecent(s.uuid) }))
    }
}

/** Bevestigen (wissen) */
@Composable
fun ConfirmDialog(title: String, message: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val focus = rememberInitialFocus()
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = T.elevated,
        title = { Text(title, style = heading(20.sp)) },
        text = { Text(message, color = T.secondary, textAlign = TextAlign.Start) },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(stringResource(R.string.clear), color = T.live, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, modifier = Modifier.focusRequester(focus)) {
                Text(stringResource(R.string.cancel), color = T.text)
            }
        },
    )
}

package nl.lrvdlinden.tunr.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.LocaleHelper
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Country
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.ErrorRetry
import nl.lrvdlinden.tunr.ui.SkeletonList
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.TopBar
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.rememberLoad
import nl.lrvdlinden.tunr.ui.stationCount
import nl.lrvdlinden.tunr.ui.tvClickable
import java.text.Normalizer

/** Landkeuze (SPEC §3.2): zoekveld, "Voorgesteld" (land van het toestel), "Alle landen". Tv: raster van landkaarten. */
@Composable
fun CountryPickerScreen(firstRun: Boolean, onPicked: () -> Unit, onClose: (() -> Unit)? = null) {
    val load = rememberLoad(Unit) { RadioBrowser.countries() }
    var query by rememberSaveable { mutableStateOf("") }
    val selected by Library.country.collectAsState()
    val deviceCc = remember { LocaleHelper.deviceCountry() }

    fun pick(c: Country) {
        Library.setCountry(c)
        onPicked()
    }

    val all = load.value.orEmpty()
    val filtered = remember(all, query) {
        val q = fold(query)
        if (q.isEmpty()) all else all.filter { fold(it.localizedName).contains(q) || fold(it.name).contains(q) || it.code.equals(q, true) }
    }
    val suggested = remember(all, query) { if (query.isBlank()) all.filter { it.code.equals(deviceCc, true) } else emptyList() }
    val firstFocus = rememberInitialFocus(key = all.isNotEmpty())

    Column(Modifier.fillMaxSize().background(T.bg).statusBarsPadding()) {
        if (!firstRun && onClose != null) {
            TopBar(stringResource(R.string.choose_country), onBack = onClose)
        } else {
            Column(Modifier.fillMaxWidth().padding(horizontal = Dims.edge, vertical = 16.dp)) {
                Text(stringResource(R.string.choose_country), style = heading(if (Device.isTV) 36.sp else 30.sp))
                Spacer(Modifier.height(4.dp))
                Text(stringResource(R.string.choose_country_subtitle), color = T.secondary, fontSize = 15.sp)
            }
        }
        if (!firstRun) {
            Text(stringResource(R.string.choose_country_subtitle), color = T.secondary, fontSize = 14.sp,
                modifier = Modifier.padding(horizontal = Dims.edge))
        }
        SearchField(query, { query = it }, stringResource(R.string.search_country),
            Modifier.padding(horizontal = Dims.edge, vertical = 12.dp).widthIn(max = 640.dp))

        when {
            load.loading && all.isEmpty() -> SkeletonList(10)
            load.failed && all.isEmpty() -> ErrorRetry(onRetry = load.retry, focusRequester = firstFocus)
            Device.isTV -> CountryGrid(suggested, filtered, selected?.code, firstFocus, ::pick)
            else -> LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 32.dp),
            ) {
                if (suggested.isNotEmpty()) {
                    item { GroupLabel(stringResource(R.string.suggested)) }
                    items(suggested, key = { "s" + it.code }) { CountryRow(it, it.code == selected?.code, null) { pick(it) } }
                }
                item { GroupLabel(stringResource(R.string.all_countries)) }
                items(filtered, key = { it.code }) { c -> CountryRow(c, c.code == selected?.code, null) { pick(c) } }
                if (filtered.isEmpty()) item {
                    Text(stringResource(R.string.no_results), color = T.secondary, textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(32.dp))
                }
            }
        }
    }
}

@Composable
private fun GroupLabel(text: String) {
    Text(text.uppercase(), color = T.secondary, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp,
        modifier = Modifier.padding(start = Dims.edge, end = Dims.edge, top = 16.dp, bottom = 6.dp))
}

@Composable
private fun CountryRow(c: Country, selected: Boolean, focus: FocusRequester?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Dims.edge - 8.dp)
            .tvClickable(RoundedCornerShape(12.dp), scale = 1.02f, focusRequester = focus, onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(c.flag, fontSize = 30.sp)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(c.localizedName, color = T.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(stationCount(c.stationCount), color = T.secondary, fontSize = 13.sp)
        }
        if (selected) Icon(Icons.Rounded.Check, null, tint = T.accent)
    }
}

/** Tv: raster van landkaarten (vlag groot + naam + aantal) */
@Composable
private fun CountryGrid(
    suggested: List<Country>, all: List<Country>, selectedCode: String?, firstFocus: FocusRequester, onPick: (Country) -> Unit,
) {
    val list = suggested + all.filter { a -> suggested.none { it.code == a.code } }
    LazyVerticalGrid(
        columns = GridCells.Adaptive(170.dp),
        contentPadding = PaddingValues(horizontal = Dims.edge, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxSize().navigationBarsPadding()
    ) {
        if (list.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
            Text(stringResource(R.string.no_results), color = T.secondary, textAlign = TextAlign.Center, modifier = Modifier.padding(32.dp))
        }
        items(list, key = { it.code }) { c ->
            val first = c == list.firstOrNull()
            Column(
                Modifier
                    .tvClickable(RoundedCornerShape(Dims.cardRadius), focusRequester = if (first) firstFocus else null) { onPick(c) }
                    .background(if (c.code == selectedCode) T.elevated else T.surface)
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(c.flag, fontSize = 44.sp)
                Spacer(Modifier.height(6.dp))
                Text(c.localizedName, color = T.text, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                Text(stationCount(c.stationCount), color = T.secondary, fontSize = 12.sp)
                if (c.code == selectedCode) Box(Modifier.padding(top = 4.dp)) { Icon(Icons.Rounded.Check, null, tint = T.accent, modifier = Modifier.size(18.dp)) }
            }
        }
    }
}

/** Zonder accenten en hoofdletters, voor zoeken */
fun fold(s: String): String =
    Normalizer.normalize(s.trim().lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")

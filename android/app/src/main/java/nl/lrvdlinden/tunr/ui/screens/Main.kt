package nl.lrvdlinden.tunr.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Radio
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.AppState
import nl.lrvdlinden.tunr.ui.EqualizerBars
import nl.lrvdlinden.tunr.ui.MiniPlayer
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.Tab
import nl.lrvdlinden.tunr.ui.TunrLogo
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.tvClickable

private data class TabItem(val tab: Tab, val label: Int, val icon: ImageVector)

private val TABS = listOf(
    TabItem(Tab.DISCOVER, R.string.tab_discover, Icons.Rounded.Radio),
    TabItem(Tab.BROWSE, R.string.tab_browse, Icons.Rounded.GridView),
    TabItem(Tab.MAP, R.string.tab_map, Icons.Rounded.Public),
    TabItem(Tab.SEARCH, R.string.tab_search, Icons.Rounded.Search),
    TabItem(Tab.LIBRARY, R.string.tab_library, Icons.Rounded.LibraryMusic),
)

/**
 * Hoofdscherm (SPEC §6): telefoon 5 tabs onderaan met miniplayer erboven; tablet een NavigationRail;
 * tv een eigen zijbalk links met de 5 tabs + Instellingen en geen miniplayer.
 */
@Composable
fun MainScreen() {
    val holder = rememberSaveableStateHolder()
    val content: @Composable (Tab) -> Unit = { tab ->
        holder.SaveableStateProvider(tab.name) {
            when (tab) {
                Tab.DISCOVER -> DiscoverScreen()
                Tab.BROWSE -> BrowseScreen()
                Tab.MAP -> MapScreen()
                Tab.SEARCH -> SearchScreen()
                Tab.LIBRARY -> LibraryScreen()
                Tab.SETTINGS -> SettingsScreen(onClose = null)
            }
        }
    }
    when {
        Device.isTV -> TvMain(content)
        isWide() -> TabletMain(content)
        else -> PhoneMain(content)
    }
}

@Composable
private fun PhoneMain(content: @Composable (Tab) -> Unit) {
    val station by RadioController.station.collectAsState()
    Column(Modifier.fillMaxSize().background(T.bg)) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            Crossfade(AppState.tab, animationSpec = tween(180), label = "tab") { content(it) }
        }
        AnimatedVisibility(station != null, enter = expandVertically(), exit = shrinkVertically()) { MiniPlayer() }
        NavigationBar(containerColor = T.surface, tonalElevation = 0.dp) {
            TABS.forEach { item ->
                NavigationBarItem(
                    selected = AppState.tab == item.tab,
                    onClick = { AppState.tab = item.tab },
                    icon = { Icon(item.icon, null) },
                    label = { Text(stringResource(item.label), fontSize = 11.sp, maxLines = 1) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = T.accent, selectedTextColor = T.accent,
                        unselectedIconColor = T.secondary, unselectedTextColor = T.secondary,
                        indicatorColor = T.accent.copy(alpha = 0.14f),
                    )
                )
            }
        }
    }
}

@Composable
private fun TabletMain(content: @Composable (Tab) -> Unit) {
    val station by RadioController.station.collectAsState()
    Row(Modifier.fillMaxSize().background(T.bg)) {
        NavigationRail(containerColor = T.surface, header = {
            Spacer(Modifier.height(12.dp)); TunrLogo(18.sp); Spacer(Modifier.height(12.dp))
        }) {
            Spacer(Modifier.weight(1f))
            TABS.forEach { item ->
                NavigationRailItem(
                    selected = AppState.tab == item.tab,
                    onClick = { AppState.tab = item.tab },
                    icon = { Icon(item.icon, null) },
                    label = { Text(stringResource(item.label), fontSize = 12.sp, maxLines = 1) },
                    colors = NavigationRailItemDefaults.colors(
                        selectedIconColor = T.accent, selectedTextColor = T.accent,
                        unselectedIconColor = T.secondary, unselectedTextColor = T.secondary,
                        indicatorColor = T.accent.copy(alpha = 0.14f),
                    )
                )
            }
            Spacer(Modifier.weight(1f))
        }
        Column(Modifier.weight(1f).fillMaxHeight()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                Crossfade(AppState.tab, animationSpec = tween(180), label = "tab") { content(it) }
            }
            AnimatedVisibility(station != null, enter = expandVertically(), exit = shrinkVertically()) {
                Box(Modifier.navigationBarsPadding()) { MiniPlayer() }
            }
        }
    }
}

/** Tv: zijbalk links. Focus op een item kiest dat tabblad (zoals de Google TV-launcher). */
@Composable
private fun TvMain(content: @Composable (Tab) -> Unit) {
    val items = TABS + TabItem(Tab.SETTINGS, R.string.settings, Icons.Rounded.Settings)
    var railFocused by remember { mutableStateOf(false) }
    val station by RadioController.station.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    Row(Modifier.fillMaxSize().background(T.bg)) {
        Column(
            Modifier
                .fillMaxHeight()
                .width(if (railFocused) 220.dp else 84.dp)
                .background(if (railFocused) T.surface else Color.Transparent)
                .onFocusChanged { railFocused = it.hasFocus; AppState.railFocused = it.hasFocus }
                .padding(vertical = 24.dp, horizontal = 12.dp)
                .selectableGroup(),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(Modifier.fillMaxWidth().height(56.dp), contentAlignment = if (railFocused) Alignment.CenterStart else Alignment.Center) {
                TunrLogo(if (railFocused) 22.sp else 14.sp, Modifier.padding(start = if (railFocused) 12.dp else 0.dp))
            }
            Spacer(Modifier.height(12.dp))
            items.forEach { item ->
                if (item.tab == Tab.SETTINGS) Spacer(Modifier.weight(1f))
                TvRailItem(item, selected = AppState.tab == item.tab, expanded = railFocused,
                    playingHere = item.tab == Tab.DISCOVER && station != null && playing)
            }
        }
        Box(Modifier.weight(1f).fillMaxHeight()) {
            Crossfade(AppState.tab, animationSpec = tween(160), label = "tab") { content(it) }
        }
    }
}

@Composable
private fun TvRailItem(item: TabItem, selected: Boolean, expanded: Boolean, playingHere: Boolean) {
    var focused by remember { mutableStateOf(false) }
    val req = remember { FocusRequester() }
    val shape = RoundedCornerShape(12.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .focusRequester(req)
            .onFocusChanged {
                focused = it.isFocused
                if (it.isFocused && AppState.tab != item.tab) AppState.tab = item.tab
            }
            .tvClickable(shape, scale = 1.04f) { AppState.tab = item.tab }
            .background(
                when {
                    focused -> Color.White
                    selected -> T.accent.copy(alpha = 0.18f)
                    else -> Color.Transparent
                }
            )
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val tint = when { focused -> Color.Black; selected -> T.accent; else -> T.secondary }
        Icon(item.icon, stringResource(item.label), tint = tint, modifier = Modifier.size(26.dp))
        if (expanded) {
            Spacer(Modifier.width(14.dp))
            Text(stringResource(item.label), color = tint, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                modifier = Modifier.weight(1f))
            if (playingHere) EqualizerBars(color = if (focused) Color.Black else T.accent)
        }
    }
}

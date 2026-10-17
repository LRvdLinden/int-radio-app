package nl.lrvdlinden.tunr.ui.screens

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Casino
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import nl.lrvdlinden.tunr.Brand
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.MapPlace
import nl.lrvdlinden.tunr.data.MapRecent
import nl.lrvdlinden.tunr.data.RadioBrowser
import nl.lrvdlinden.tunr.data.flagEmoji
import nl.lrvdlinden.tunr.data.localizedCountryName
import nl.lrvdlinden.tunr.data.Station
import nl.lrvdlinden.tunr.player.RadioController
import nl.lrvdlinden.tunr.ui.AppState
import nl.lrvdlinden.tunr.ui.Chip
import nl.lrvdlinden.tunr.ui.CircleIconButton
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.EqualizerBars
import nl.lrvdlinden.tunr.ui.ErrorRetry
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.PillButton
import nl.lrvdlinden.tunr.ui.StationArt
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.isWide
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.rememberLoad
import nl.lrvdlinden.tunr.ui.stationCount
import nl.lrvdlinden.tunr.ui.tvClickable
import org.osmdroid.config.Configuration
import org.osmdroid.events.DelayedMapListener
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import java.io.File
import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.tan

/** CARTO "dark_all" (OpenStreetMap-gegevens), geen sleutel nodig. Attributie staat altijd in beeld. */
private val CartoDark = XYTileSource(
    "CartoDark", 0, 19, 256, ".png",
    arrayOf(
        "https://a.basemaps.cartocdn.com/dark_all/",
        "https://b.basemaps.cartocdn.com/dark_all/",
        "https://c.basemaps.cartocdn.com/dark_all/",
    )
)

/** Laatste camera, zodat de kaart na een tabwissel op dezelfde plek terugkomt */
private object MapMemory {
    var center: GeoPoint? = null
    var zoom: Double = 0.0
    var forCountry: String? = null
    var world: Boolean = false
    /** Bron waarvoor de camera al passend is gemaakt (zie [sourceKey]) */
    var key: String? = null
    /** Tijdelijk gekozen land via zoeken (SPEC §9); het land in Instellingen verandert niet */
    var override: String? = null
    /** Gekozen plaats via zoeken */
    var place: MapPlace? = null
}

/** Welke zenders de kaart toont: wereld, rond een plaats of een land */
private fun sourceKey(world: Boolean, place: MapPlace?, cc: String): String = when {
    world -> "world"
    place != null -> "near:${place.lat},${place.lon}"
    else -> "cc:$cc"
}

/** Zenders voor de bron; rond een plaats 50 km, dan 150 km, dan het land van die plaats (SPEC §9) */
private suspend fun loadMapStations(world: Boolean, place: MapPlace?, cc: String): List<Station> = when {
    world -> RadioBrowser.geoStations(null)
    place != null -> RadioBrowser.nearStations(place.lat, place.lon, 50_000)
        .ifEmpty { RadioBrowser.nearStations(place.lat, place.lon, 150_000) }
        .ifEmpty { place.countryCode.takeIf { it.length == 2 }?.let { RadioBrowser.geoStations(it) } ?: emptyList() }
    else -> RadioBrowser.geoStations(cc)
}

private fun configureOsmdroid(context: Context) {
    val cfg = Configuration.getInstance()
    cfg.load(context, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
    cfg.userAgentValue = Brand.userAgent
    val base = File(context.cacheDir, "osmdroid")
    cfg.osmdroidBasePath = base
    cfg.osmdroidTileCache = File(base, "tiles")
}

/** Een stip of een cluster op de kaart */
private data class Cluster(val lat: Double, val lon: Double, val stations: List<Station>)

/**
 * Kaart (SPEC §6): donkere wereldkaart met gloeiende stippen, clustering, kaartje onderaan, "Wereld" en "Willekeurig".
 * Tv: lijst met zenders links (focus = kaart centreren, OK = afspelen), kaart rechts.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MapScreen() {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val scope = rememberCoroutineScope()
    val cc = currentCountryCode()
    val restore = MapMemory.forCountry == cc
    var world by remember { mutableStateOf(MapMemory.world && restore) }
    /** Tijdelijk land en gekozen plaats (zoeken op de kaart, SPEC §9) */
    var overrideCc by remember { mutableStateOf(if (restore) MapMemory.override else null) }
    var place by remember { mutableStateOf(if (restore) MapMemory.place else null) }
    val shownCc = overrideCc ?: cc
    val source = sourceKey(world, place, shownCc)
    val load = rememberLoad(source) { loadMapStations(world, place, shownCc) }
    val extra = remember { mutableStateListOf<Station>() }
    val stations: List<Station> = remember(load.value, extra.size) {
        val base = load.value.orEmpty()
        base + extra.filter { e -> base.none { it.uuid == e.uuid } }
    }
    var selected by remember { mutableStateOf<Station?>(null) }
    var viewport by remember { mutableIntStateOf(0) }
    var randomBusy by remember { mutableStateOf(false) }
    val playing by RadioController.station.collectAsState()
    val isPlaying by RadioController.isPlaying.collectAsState()

    val map = remember {
        configureOsmdroid(context.applicationContext)
        MapView(context).apply {
            setTileSource(CartoDark)
            setMultiTouchControls(true)
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            setMinZoomLevel(2.0)
            setMaxZoomLevel(18.0)
            setVerticalMapRepetitionEnabled(false)
            setHorizontalMapRepetitionEnabled(true)
            setScrollableAreaLimitLatitude(MapView.getTileSystem().maxLatitude, MapView.getTileSystem().minLatitude, 0)
            overlayManager.tilesOverlay.setLoadingBackgroundColor(android.graphics.Color.parseColor("#0A0A0C"))
            overlayManager.tilesOverlay.setLoadingLineColor(android.graphics.Color.parseColor("#16161A"))
            setBackgroundColor(android.graphics.Color.parseColor("#0A0A0C"))
            setTilesScaledToDpi(true)
            // Op tv bedient de lijst de kaart; de kaart zelf pakt geen D-pad-focus
            isFocusable = !Device.isTV
            MapMemory.center?.let { c -> controller.setZoom(MapMemory.zoom); controller.setCenter(c) }
                ?: run { controller.setZoom(3.0); controller.setCenter(GeoPoint(35.0, 10.0)) }
            addMapListener(DelayedMapListener(object : MapListener {
                override fun onScroll(event: ScrollEvent?): Boolean { viewport++; return false }
                override fun onZoom(event: ZoomEvent?): Boolean { viewport++; return false }
            }, 120))
        }
    }

    // Levenscyclus van de MapView
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, map) {
        val obs = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_RESUME -> map.onResume()
                Lifecycle.Event.ON_PAUSE -> map.onPause()
                else -> {}
            }
        }
        lifecycle.addObserver(obs)
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) map.onResume()
        onDispose {
            lifecycle.removeObserver(obs)
            MapMemory.center = GeoPoint(map.mapCenter.latitude, map.mapCenter.longitude)
            MapMemory.zoom = map.zoomLevelDouble
            MapMemory.world = world
            MapMemory.forCountry = cc
            MapMemory.override = overrideCc
            MapMemory.place = place
            map.onPause()
            map.onDetach()
        }
    }

    /** Zoeken: dichtstbijzijnde zender bij de plaats kiezen (kaartje onderaan opent) */
    fun openNearest(p: MapPlace, list: List<Station>) {
        val first = nearestTo(p.lat, p.lon, list, 1).firstOrNull() ?: return
        selected = first
        // Niets in de buurt (terugval op het land): naar die zender vliegen
        if (distanceKm(p.lat, p.lon, first.geoLat!!, first.geoLong!!) > 150.0) {
            map.controller.animateTo(GeoPoint(first.geoLat!!, first.geoLong!!), 9.0, 1000L)
        }
    }

    // Eerste keer (of ander land / Wereld / plaats): kaart passend maken op de zenders
    LaunchedEffect(load.value, source) {
        val list = load.value ?: return@LaunchedEffect
        if (MapMemory.key == source && MapMemory.center != null) return@LaunchedEffect
        MapMemory.key = source
        MapMemory.forCountry = cc; MapMemory.world = world
        val p = place
        when {
            p != null -> openNearest(p, list)
            world || list.size < 2 -> map.controller.animateTo(GeoPoint(30.0, 10.0), 2.6, 900L)
            else -> fitTo(map, list)
        }
        MapMemory.center = GeoPoint(map.mapCenter.latitude, map.mapCenter.longitude)
    }

    // Vanuit zenderdetail of "Wereldkaart": naar een zender vliegen
    LaunchedEffect(AppState.mapFocus) {
        val s = AppState.mapFocus ?: return@LaunchedEffect
        AppState.mapFocus = null
        if (stations.none { it.uuid == s.uuid }) extra.add(s)
        selected = s
        map.controller.animateTo(GeoPoint(s.geoLat!!, s.geoLong!!), 10.0, 1200L)
    }

    // Markers opnieuw opbouwen bij een andere uitsnede, data, selectie of zender die speelt
    var pulseDrawable by remember { mutableStateOf<GlowDotDrawable?>(null) }
    LaunchedEffect(viewport, stations, selected?.uuid, playing?.uuid) {
        val clusters = cluster(stations, map, density)
        map.overlays.removeAll { it is Marker }
        var pulse: GlowDotDrawable? = null
        clusters.forEach { c ->
            val m = Marker(map)
            m.setPosition(GeoPoint(c.lat, c.lon))
            m.setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            m.setInfoWindow(null as org.osmdroid.views.overlay.infowindow.MarkerInfoWindow?)
            if (c.stations.size == 1) {
                val s = c.stations[0]
                val isPlayingHere = s.uuid == playing?.uuid
                val isSel = s.uuid == selected?.uuid
                val d = GlowDotDrawable(((if (isPlayingHere || isSel) 40 else 26) * density).toInt(),
                    core = if (isSel && !isPlayingHere) 0xFFFFB020.toInt() else 0xFFFF5A1F.toInt(), playing = isPlayingHere)
                if (isPlayingHere) pulse = d
                m.setIcon(d)
                m.setTitle(s.displayName)
                m.setOnMarkerClickListener { _, _ -> selected = s; true }
            } else {
                m.setIcon(ClusterDrawable(c.stations.size, density))
                m.setOnMarkerClickListener { _, mv ->
                    if (mv.zoomLevelDouble >= 13.5 || c.stations.all { it.geoLat == c.stations[0].geoLat && it.geoLong == c.stations[0].geoLong }) {
                        selected = c.stations.maxByOrNull { it.clickCount }
                    } else {
                        mv.controller.animateTo(GeoPoint(c.lat, c.lon), (mv.zoomLevelDouble + 2.5).coerceAtMost(16.0), 600L)
                    }
                    true
                }
            }
            map.overlays.add(m)
        }
        pulseDrawable = pulse
        map.invalidate()
    }

    // De zender die speelt pulseert
    LaunchedEffect(pulseDrawable, isPlaying) {
        val d = pulseDrawable ?: return@LaunchedEffect
        val start = System.currentTimeMillis()
        while (true) {
            val t = ((System.currentTimeMillis() - start) % 1400L) / 1400f
            d.pulse = if (isPlaying) t else 0f
            map.postInvalidate()
            delay(if (isPlaying) 40 else 500)
        }
    }

    fun random() {
        if (randomBusy) return
        randomBusy = true
        scope.launch {
            val s = runCatching { RadioBrowser.randomStation() }.getOrNull()
            randomBusy = false
            if (s != null) {
                if (stations.none { it.uuid == s.uuid }) extra.add(s)
                selected = s
                map.controller.animateTo(GeoPoint(s.geoLat!!, s.geoLong!!), 9.0, 1800L)
                RadioController.play(s, listOf(s) + nearest(s, stations, 12))
            }
        }
    }

    /** Terug naar je eigen land (landknop), of opnieuw passend maken als dat al getoond wordt */
    fun showOwnCountry() {
        val same = !world && place == null && overrideCc == null
        world = false; place = null; overrideCc = null; selected = null
        if (same) load.value?.let { if (it.size >= 2) fitTo(map, it) }
    }

    fun chooseCountry(code: String, label: String) {
        val c = code.trim().uppercase()
        if (c.length != 2) return
        Library.addMapSearch(MapRecent(label, c))
        val newOverride = c.takeIf { it != cc }
        val same = !world && place == null && overrideCc == newOverride
        world = false; place = null; overrideCc = newOverride; selected = null
        if (same) load.value?.let { if (it.size >= 2) fitTo(map, it) }
    }

    fun choosePlace(p: MapPlace) {
        Library.addMapSearch(MapRecent(p.name, p.countryCode, p))
        val same = !world && place == p
        world = false; overrideCc = null; selected = null; place = p
        map.controller.animateTo(GeoPoint(p.lat, p.lon), 11.0, 1400L)
        if (same) load.value?.let { openNearest(p, it) }
    }

    fun handleSuggestion(sug: MapSuggestion) {
        when (sug) {
            is MapSuggestion.CountryItem -> chooseCountry(sug.country.code, sug.country.localizedName)
            is MapSuggestion.PlaceItem -> choosePlace(sug.place)
            is MapSuggestion.RecentItem -> sug.recent.place?.let { choosePlace(it) }
                ?: chooseCountry(sug.recent.countryCode, sug.recent.label)
        }
    }

    // Enter / eerste suggestie: de zoektoestand maakt zichzelf daarna leeg
    val search = rememberMapSearchState { handleSuggestion(it) }
    val focusManager = LocalFocusManager.current
    val chooseAndClose: (MapSuggestion) -> Unit = { handleSuggestion(it); search.clear(); focusManager.clearFocus() }
    val panelVisible = mapSearchPanelVisible(search)

    val controls: @Composable () -> Unit = {
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically
        ) {
            val p = place
            Chip(
                if (p != null) p.name else "${flagEmoji(shownCc)} ${localizedCountryName(shownCc, shownCc)}".trim(),
                selected = !world, icon = if (p != null) Icons.Rounded.Place else null,
            ) { showOwnCountry() }
            Chip(stringResource(R.string.map_world), selected = world, icon = Icons.Rounded.Public) {
                world = !world; place = null; overrideCc = null; selected = null
            }
            Row(
                Modifier.tvClickable(CircleShape, scale = 1.06f) { random() }.background(T.surface).padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (randomBusy) CircularProgressIndicator(Modifier.size(16.dp), color = T.accent, strokeWidth = 2.dp)
                else Icon(Icons.Rounded.Casino, null, tint = Color.White, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.map_random), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
            if (load.loading) CircularProgressIndicator(Modifier.size(18.dp), color = T.accent, strokeWidth = 2.dp)
        }
    }

    if (Device.isTV) {
        Row(Modifier.fillMaxSize().background(T.bg)) {
            val tvSearch: @Composable () -> Unit = {
                MapSearchField(search, onChoose = { handleSuggestion(it) })
                if (panelVisible) {
                    Spacer(Modifier.height(6.dp))
                    MapSearchPanel(search, chooseAndClose, maxHeight = 300.dp)
                }
            }
            TvStationList(stations, load.failed, load.retry, tvSearch, controls) { s, focusOnly ->
                selected = s
                map.controller.animateTo(GeoPoint(s.geoLat!!, s.geoLong!!), map.zoomLevelDouble.coerceAtLeast(9.0), 700L)
                if (!focusOnly) RadioController.play(s, listOf(s) + nearest(s, stations, 12))
            }
            Box(Modifier.weight(1f).fillMaxHeight().padding(top = 24.dp, end = 24.dp, bottom = 24.dp).clip(RoundedCornerShape(20.dp))) {
                AndroidView(factory = { map }, modifier = Modifier.fillMaxSize())
                Attribution(Modifier.align(Alignment.BottomEnd))
                selected?.let { s ->
                    Box(Modifier.align(Alignment.BottomStart).padding(16.dp).widthIn(max = 480.dp)) { TvSelectedCard(s) }
                }
            }
        }
    } else {
        Box(Modifier.fillMaxSize().background(T.bg)) {
            AndroidView(factory = { map }, modifier = Modifier.fillMaxSize())
            Column(Modifier.statusBarsPadding().padding(horizontal = Dims.edge, vertical = 10.dp)) {
                if (isWide()) {
                    // Tablet: zoekveld in de bovenbalk, naast de knoppen
                    Row(verticalAlignment = Alignment.Top) {
                        Text(stringResource(R.string.tab_map), style = heading(26.sp), modifier = Modifier.padding(top = 6.dp))
                        Spacer(Modifier.width(16.dp))
                        Column(Modifier.weight(1f, fill = false).widthIn(min = 200.dp, max = 420.dp)) {
                            MapSearchField(search, onChoose = { handleSuggestion(it) })
                            if (panelVisible) {
                                Spacer(Modifier.height(6.dp))
                                MapSearchPanel(search, chooseAndClose, maxHeight = 420.dp)
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        Box(Modifier.padding(top = 4.dp)) { controls() }
                    }
                } else {
                    // Telefoon: zoekveld op een eigen regel boven de knoppen
                    Text(stringResource(R.string.tab_map), style = heading(26.sp))
                    Spacer(Modifier.height(8.dp))
                    MapSearchField(search, onChoose = { handleSuggestion(it) })
                    if (panelVisible) {
                        Spacer(Modifier.height(6.dp))
                        MapSearchPanel(search, chooseAndClose, maxHeight = 340.dp)
                    }
                    Spacer(Modifier.height(8.dp))
                    controls()
                }
                if (load.failed && stations.isEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    ErrorRetry(compact = true, onRetry = load.retry)
                }
            }
            if (selected == null) Attribution(Modifier.align(Alignment.BottomEnd))
            else Attribution(Modifier.align(Alignment.TopEnd).statusBarsPadding())
            AnimatedVisibility(
                visible = selected != null,
                modifier = Modifier.align(Alignment.BottomCenter),
                enter = slideInVertically { it } + fadeIn(),
                exit = slideOutVertically { it } + fadeOut(),
            ) {
                val s = selected
                if (s != null) {
                    // Na zoeken op een plaats: de dichtstbijzijnde zender + 7 in de buurt (SPEC §9)
                    val nearCount = if (place != null) 7 else 12
                    val near = remember(s.uuid, stations, nearCount) { listOf(s) + nearest(s, stations, nearCount) }
                    NearbyPager(near, onDismiss = { selected = null }) { focus ->
                        map.controller.animateTo(GeoPoint(focus.geoLat!!, focus.geoLong!!), map.zoomLevelDouble, 500L)
                    }
                }
            }
        }
    }
}

/** Kaartje onderaan: swipen = de dichtstbijzijnde zenders */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NearbyPager(list: List<Station>, onDismiss: () -> Unit, onPage: (Station) -> Unit) {
    val pager = rememberPagerState { list.size }
    LaunchedEffect(pager, list) {
        snapshotFlow { pager.settledPage }.distinctUntilChanged().collect { p ->
            if (p > 0) list.getOrNull(p)?.let(onPage)
        }
    }
    HorizontalPager(
        state = pager,
        contentPadding = PaddingValues(start = 16.dp, end = 40.dp, bottom = 22.dp),
        pageSpacing = 10.dp,
        modifier = Modifier.fillMaxWidth()
    ) { page ->
        MapStationCard(list[page], list, onDismiss = onDismiss)
    }
}

@Composable
private fun MapStationCard(s: Station, queue: List<Station>, onDismiss: () -> Unit) {
    val current by RadioController.station.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    val isCurrent = current?.uuid == s.uuid
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(T.elevated).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StationArt(s, Modifier.size(76.dp), radius = 12.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isCurrent && playing) { EqualizerBars(); Spacer(Modifier.width(6.dp)) }
                Text(s.displayName, color = T.text, fontWeight = FontWeight.Black, fontSize = 16.sp, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                CircleIconButton(Icons.Rounded.Close, stringResource(R.string.close), size = 28.dp, background = Color.Transparent, onClick = onDismiss)
            }
            Text(s.placeLine(), color = T.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (s.genresLine.isNotEmpty()) Text(s.genresLine, color = T.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PillButton(
                    stringResource(if (isCurrent && playing) R.string.pause else R.string.play),
                    if (isCurrent && playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, small = true
                ) { if (isCurrent) RadioController.togglePlay() else RadioController.play(s, queue) }
                PillButton(stringResource(R.string.info), Icons.Rounded.Info, primary = false, small = true) { Nav.station(s) }
            }
        }
    }
}

@Composable
private fun TvSelectedCard(s: Station) {
    val current by RadioController.station.collectAsState()
    val playing by RadioController.isPlaying.collectAsState()
    Row(
        Modifier.clip(RoundedCornerShape(18.dp)).background(T.elevated.copy(alpha = 0.95f)).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StationArt(s, Modifier.size(84.dp), radius = 12.dp)
        Spacer(Modifier.width(14.dp))
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (current?.uuid == s.uuid && playing) { EqualizerBars(); Spacer(Modifier.width(8.dp)) }
                Text(s.displayName, style = heading(20.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(s.placeLine(), color = T.secondary, fontSize = 14.sp, maxLines = 1)
            if (s.genresLine.isNotEmpty()) Text(s.genresLine, color = T.secondary, fontSize = 13.sp, maxLines = 1)
        }
    }
}

/** Tv: lijst met zenders op de kaart; focus centreert de kaart, OK speelt af */
@Composable
private fun TvStationList(
    stations: List<Station>,
    failed: Boolean,
    retry: () -> Unit,
    search: @Composable () -> Unit,
    controls: @Composable () -> Unit,
    onSelect: (Station, focusOnly: Boolean) -> Unit,
) {
    val list = remember(stations) { stations.sortedByDescending { it.clickCount }.take(300) }
    val first = rememberInitialFocus(key = list.isNotEmpty())
    Column(Modifier.width(360.dp).fillMaxHeight().padding(start = 24.dp, top = 24.dp, end = 12.dp)) {
        Text(stringResource(R.string.tab_map), style = heading(30.sp))
        Spacer(Modifier.height(10.dp))
        search()
        Spacer(Modifier.height(10.dp))
        controls()
        Spacer(Modifier.height(10.dp))
        Text(stationCount(list.size), color = T.secondary, fontSize = 13.sp)
        Spacer(Modifier.height(6.dp))
        if (failed && list.isEmpty()) ErrorRetry(compact = true, onRetry = retry, focusRequester = first)
        LazyColumn(contentPadding = PaddingValues(vertical = 8.dp, horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            itemsIndexed(list, key = { _, s -> s.uuid }) { i, s ->
                Row(
                    Modifier.fillMaxWidth()
                        .onFocusChanged { if (it.isFocused) onSelect(s, true) }
                        .tvClickable(RoundedCornerShape(12.dp), scale = 1.03f, focusRequester = if (i == 0) first else null) { onSelect(s, false) }
                        .padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    StationArt(s, Modifier.size(48.dp), radius = 8.dp)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(s.displayName, color = T.text, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(s.placeLine(), color = T.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun Attribution(modifier: Modifier = Modifier) {
    Text(
        stringResource(R.string.map_attribution), color = Color.White.copy(alpha = 0.75f), fontSize = 10.sp,
        modifier = modifier.padding(6.dp).clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = 0.55f))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    )
}

// MARK: hulpfuncties

/** Kaart passend op de zenders, zonder uitschieters (overzeese gebieden): 5e–95e percentiel */
private fun fitTo(map: MapView, list: List<Station>) {
    val lats = list.mapNotNull { it.geoLat }.sorted()
    val lons = list.mapNotNull { it.geoLong }.sorted()
    if (lats.isEmpty()) return
    fun pct(l: List<Double>, p: Double) = l[((l.size - 1) * p).toInt().coerceIn(0, l.size - 1)]
    var n = pct(lats, 0.95); var s = pct(lats, 0.05); var e = pct(lons, 0.95); var w = pct(lons, 0.05)
    if (n - s < 0.5) { n += 0.5; s -= 0.5 }
    if (e - w < 0.5) { e += 0.5; w -= 0.5 }
    val box = BoundingBox(n.coerceAtMost(84.0), e.coerceAtMost(179.0), s.coerceAtLeast(-84.0), w.coerceAtLeast(-179.0))
    val fit = { runCatching { map.zoomToBoundingBox(box, true, 80) } ; Unit }
    if (map.isLayoutOccurred) fit() else map.addOnFirstLayoutListener { _, _, _, _, _ -> fit() }
}

/** Raster-clustering in Web-Mercator-pixels van het huidige zoomniveau; alleen wat (bijna) in beeld is */
private fun cluster(stations: List<Station>, map: MapView, density: Float): List<Cluster> {
    if (stations.isEmpty()) return emptyList()
    val zoom = map.zoomLevelDouble
    val world = 256.0 * 2.0.pow(zoom)
    val cell = 56.0 * density
    val box = map.boundingBox
    val latPad = (box.latNorth - box.latSouth) * 0.25
    val lonPad = (box.lonEast - box.lonWest).let { if (it <= 0) 360.0 else it } * 0.25
    val visible = stations.filter { s ->
        val lat = s.geoLat!!; val lon = s.geoLong!!
        lat <= box.latNorth + latPad && lat >= box.latSouth - latPad &&
            (box.lonEast - box.lonWest >= 300 || box.lonWest > box.lonEast ||
                (lon <= box.lonEast + lonPad && lon >= box.lonWest - lonPad))
    }
    if (zoom >= 14.5) return visible.map { Cluster(it.geoLat!!, it.geoLong!!, listOf(it)) }
    val bins = LinkedHashMap<Long, MutableList<Station>>()
    visible.forEach { s ->
        val lat = s.geoLat!!.coerceIn(-85.0, 85.0)
        val x = (s.geoLong!! + 180.0) / 360.0 * world
        val rad = lat * PI / 180.0
        val y = (1.0 - ln(tan(rad) + 1.0 / cos(rad)) / PI) / 2.0 * world
        val key = (floor(x / cell).toLong() shl 32) or (floor(y / cell).toLong() and 0xFFFFFFFFL)
        bins.getOrPut(key) { mutableListOf() }.add(s)
    }
    return bins.values.map { list ->
        Cluster(list.map { it.geoLat!! }.average(), list.map { it.geoLong!! }.average(), list)
    }
}

/** De [n] zenders het dichtst bij een punt (benadering, prima voor sorteren) */
private fun nearestTo(lat: Double, lon: Double, all: List<Station>, n: Int): List<Station> {
    val k = cos(lat * PI / 180.0)
    return all.asSequence().filter { it.hasGeo }
        .map { it to ((it.geoLat!! - lat).pow(2) + ((it.geoLong!! - lon) * k).pow(2)) }
        .sortedBy { it.second }.take(n).map { it.first }.toList()
}

/** Afstand in km (haversine) */
private fun distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
    val r = PI / 180.0
    val dLat = (lat2 - lat1) * r
    val dLon = (lon2 - lon1) * r
    val a = sin(dLat / 2).pow(2) + cos(lat1 * r) * cos(lat2 * r) * sin(dLon / 2).pow(2)
    return 2 * 6371.0 * asin(sqrt(a.coerceIn(0.0, 1.0)))
}

/** De [n] dichtstbijzijnde zenders (benadering, prima voor sorteren) */
private fun nearest(s: Station, all: List<Station>, n: Int): List<Station> {
    val lat = s.geoLat ?: return emptyList()
    val lon = s.geoLong ?: return emptyList()
    val k = cos(lat * PI / 180.0)
    return all.asSequence().filter { it.uuid != s.uuid && it.hasGeo }
        .map { it to ((it.geoLat!! - lat).pow(2) + ((it.geoLong!! - lon) * k).pow(2)) }
        .sortedBy { it.second }.take(n).map { it.first }.toList()
}

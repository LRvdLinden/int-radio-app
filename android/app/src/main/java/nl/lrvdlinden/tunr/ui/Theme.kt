package nl.lrvdlinden.tunr.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.Device

/** Huisstijl (docs/SPEC.md §1). Altijd donker. */
object T {
    val bg = Color(0xFF0A0A0C)
    val surface = Color(0xFF16161A)
    val elevated = Color(0xFF202026)
    val stroke = Color(0x14FFFFFF)
    val text = Color.White
    val secondary = Color(0xFFA8A8B3)
    val accent = Color(0xFFFF5A1F)
    val accent2 = Color(0xFFFFB020)
    val live = Color(0xFFFF3B30)

    /** accent → accent2, 135° (linksboven → rechtsonder) */
    val accentBrush: Brush get() = Brush.linearGradient(listOf(accent, accent2))
    val accentHorizontal: Brush get() = Brush.horizontalGradient(listOf(accent, accent2))

    /** Paletten voor StationArt en tegels (begin, eind) */
    val palettes: List<Pair<Color, Color>> = listOf(
        Color(0xFFFF5A1F) to Color(0xFFFFB020),
        Color(0xFF7C3AED) to Color(0xFFDB2777),
        Color(0xFF0EA5E9) to Color(0xFF22D3EE),
        Color(0xFF10B981) to Color(0xFF84CC16),
        Color(0xFFF43F5E) to Color(0xFFFB923C),
        Color(0xFF6366F1) to Color(0xFF06B6D4),
        Color(0xFFEAB308) to Color(0xFFF97316),
        Color(0xFF14B8A6) to Color(0xFF3B82F6),
    )

    /** Vast palet per naam (hash), zodat een zender overal dezelfde kleuren heeft */
    fun palette(name: String): Pair<Color, Color> {
        var h = 0
        for (c in name.trim().lowercase()) h = (h * 31 + c.code) and 0x7FFFFFFF
        return palettes[h % palettes.size]
    }

    fun paletteBrush(name: String): Brush = palette(name).let { Brush.linearGradient(listOf(it.first, it.second)) }
    fun paletteBrush(index: Int): Brush = palettes[((index % palettes.size) + palettes.size) % palettes.size]
        .let { Brush.linearGradient(listOf(it.first, it.second)) }
}

/** Maten: op tv alles iets groter en ruimer (D-pad, 3 meter afstand). */
object Dims {
    val tv: Boolean get() = Device.isTV
    val edge: Dp get() = if (tv) 40.dp else 16.dp
    val cardRadius: Dp get() = if (tv) 20.dp else 14.dp
    val buttonRadius: Dp = 12.dp
    val cardWidth: Dp get() = if (tv) 132.dp else 128.dp
    val rowGap: Dp get() = if (tv) 18.dp else 12.dp
    val sectionGap: Dp get() = if (tv) 28.dp else 24.dp
    val titleSize: TextUnit get() = if (tv) 22.sp else 20.sp
    val bodySize: TextUnit get() = if (tv) 15.sp else 15.sp
    val smallSize: TextUnit get() = if (tv) 13.sp else 13.sp
}

/** Breed scherm (tablet/vouwtelefoon) of tv: twee kolommen, zijbalk. */
@Composable
fun isWide(): Boolean = Device.isTV || LocalConfiguration.current.screenWidthDp >= 600

@Composable
fun TunrTheme(content: @Composable () -> Unit) {
    val base = Typography()
    val heavy = FontWeight.Black
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = T.accent, onPrimary = Color.White,
            secondary = T.accent2, onSecondary = Color.Black,
            background = T.bg, onBackground = T.text,
            surface = T.surface, onSurface = T.text,
            surfaceVariant = T.elevated, onSurfaceVariant = T.secondary,
            surfaceContainer = T.surface, surfaceContainerHigh = T.elevated, surfaceContainerHighest = T.elevated,
            outline = T.stroke, outlineVariant = T.stroke,
            error = T.live,
        ),
        typography = base.copy(
            headlineLarge = base.headlineLarge.copy(fontWeight = heavy),
            headlineMedium = base.headlineMedium.copy(fontWeight = heavy),
            headlineSmall = base.headlineSmall.copy(fontWeight = heavy),
            titleLarge = base.titleLarge.copy(fontWeight = heavy),
        ),
        content = content
    )
}

/** Kopstijl: heavy/black, licht samengeknepen (afgerond gevoel van SF Rounded) */
fun heading(size: TextUnit, color: Color = T.text) =
    TextStyle(fontSize = size, fontWeight = FontWeight.Black, color = color, letterSpacing = (-0.2).sp)

/**
 * Focusstijl op tv (SPEC §1): 1.08× schalen, witte rand van 3 dp en schaduw. Nooit grijze systeemvlakken.
 * Gebruik dit vóór een klikbare modifier (zoals [tvClickable] doet).
 */
fun Modifier.tvFocus(shape: Shape = RoundedCornerShape(14.dp), scale: Float = 1.08f): Modifier = composed {
    var focused by remember { mutableStateOf(false) }
    val s by animateFloatAsState(if (focused) scale else 1f, spring(dampingRatio = 0.75f, stiffness = 520f), label = "tvFocus")
    this
        .onFocusChanged { focused = it.isFocused || it.hasFocus }
        .graphicsLayer { scaleX = s; scaleY = s }
        .then(
            if (focused) Modifier.shadow(18.dp, shape, clip = false, ambientColor = Color.Black, spotColor = Color.Black)
                .border(3.dp, Color.White, shape)
            else Modifier
        )
}

/**
 * Klikbaar + focusbaar voor touch én D-pad: op telefoon een ripple, op tv de focusstijl van [tvFocus] zonder ripple.
 * Onthoudt op tv het gefocuste element zodat de focus na het sluiten van een scherm terugkomt ([FocusMemory]).
 */
@OptIn(ExperimentalFoundationApi::class)
fun Modifier.tvClickable(
    shape: Shape = RoundedCornerShape(14.dp),
    scale: Float = 1.08f,
    focusRequester: FocusRequester? = null,
    role: Role? = Role.Button,
    enabled: Boolean = true,
    onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit,
): Modifier = composed {
    var focused by remember { mutableStateOf(false) }
    val memory = remember { FocusRequester() }
    val s by animateFloatAsState(if (focused) scale else 1f, spring(dampingRatio = 0.75f, stiffness = 520f), label = "tvClick")
    val tv = Device.isTV
    this
        .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
        .focusRequester(memory)
        .onFocusChanged {
            focused = it.isFocused
            FocusMemory.changed(memory, it.isFocused)
        }
        .graphicsLayer { scaleX = s; scaleY = s }
        .then(
            if (focused && tv) Modifier.shadow(18.dp, shape, clip = false).border(3.dp, Color.White, shape)
            else if (focused) Modifier.border(2.dp, Color.White.copy(alpha = 0.8f), shape)
            else Modifier
        )
        .clip(shape)
        .combinedClickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = if (tv) null else LocalIndication.current,
            enabled = enabled,
            role = role,
            onLongClick = onLongClick,
            onClick = onClick,
        )
}

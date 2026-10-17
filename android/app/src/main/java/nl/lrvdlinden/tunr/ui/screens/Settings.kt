package nl.lrvdlinden.tunr.ui.screens

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.lrvdlinden.tunr.Brand
import nl.lrvdlinden.tunr.BuildConfig
import nl.lrvdlinden.tunr.Device
import nl.lrvdlinden.tunr.LocaleHelper
import nl.lrvdlinden.tunr.R
import nl.lrvdlinden.tunr.data.Library
import nl.lrvdlinden.tunr.data.Settings
import nl.lrvdlinden.tunr.data.Stats
import nl.lrvdlinden.tunr.data.flagEmoji
import nl.lrvdlinden.tunr.data.localizedCountryName
import nl.lrvdlinden.tunr.ui.Dims
import nl.lrvdlinden.tunr.ui.Nav
import nl.lrvdlinden.tunr.ui.Route
import nl.lrvdlinden.tunr.ui.T
import nl.lrvdlinden.tunr.ui.TopBar
import nl.lrvdlinden.tunr.ui.TunrLogo
import nl.lrvdlinden.tunr.ui.bottomContentPadding
import nl.lrvdlinden.tunr.ui.heading
import nl.lrvdlinden.tunr.ui.rememberInitialFocus
import nl.lrvdlinden.tunr.ui.tvClickable

/** Instellingen (SPEC §4). [onClose] null = als tabblad op tv (geen terugknop). */
@Composable
fun SettingsScreen(onClose: (() -> Unit)?) {
    val context = LocalContext.current
    val settings by Library.settings.collectAsState()
    val country by Library.country.collectAsState()
    var dialog by rememberSaveable { mutableStateOf<String?>(null) }
    val first = rememberInitialFocus()
    val cc = country?.code ?: LocaleHelper.deviceCountry()

    Column(Modifier.fillMaxSize().background(T.bg).statusBarsPadding()) {
        if (onClose != null) TopBar(stringResource(R.string.settings), onBack = onClose)
        else Text(stringResource(R.string.settings), style = heading(34.sp), modifier = Modifier.padding(start = Dims.edge, top = 24.dp, bottom = 8.dp))

        LazyColumn(
            Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(start = Dims.edge, end = Dims.edge, bottom = bottomContentPadding)
        ) {
            item {
                Group(stringResource(R.string.settings_general)) {
                    SettingRow(stringResource(R.string.country), "${flagEmoji(cc)} ${localizedCountryName(cc, country?.name ?: cc)}",
                        focus = first) { Nav.push(Route.CountryPicker) }
                    SettingRow(stringResource(R.string.language), languageLabel(settings.language)) { dialog = "language" }
                    SettingRow(stringResource(R.string.default_sleep_timer), sleepLabel(settings.defaultSleepMinutes)) { dialog = "sleep" }
                    SwitchRow(stringResource(R.string.autoplay_last), settings.autoplayLast) { v -> Library.updateSettings { it.copy(autoplayLast = v) } }
                }
            }
            item {
                Group(stringResource(R.string.settings_library)) {
                    SettingRow(stringResource(R.string.clear_recents), null, destructive = true) { dialog = "recents" }
                    SettingRow(stringResource(R.string.clear_favorites), null, destructive = true) { dialog = "favorites" }
                }
            }
            item {
                Column {
                    Group(stringResource(R.string.settings_privacy)) {
                        SwitchRow(stringResource(R.string.share_stats), settings.shareStats) { v ->
                            Library.updateSettings { it.copy(shareStats = v) }
                            if (v) Stats.pingIfDue(context)
                        }
                    }
                    Text(stringResource(R.string.share_stats_footer), color = T.secondary, fontSize = 12.sp, lineHeight = 16.sp,
                        modifier = Modifier.widthIn(max = 720.dp).padding(start = 4.dp, end = 4.dp, top = 8.dp))
                }
            }
            item {
                Group(stringResource(R.string.about)) {
                    SettingRow(stringResource(R.string.version), stringResource(R.string.version_value, BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE), chevron = false) {}
                    if (!Device.isTV) {
                        SettingRow(stringResource(R.string.website), null) { openUrl(context, Brand.WEBSITE) }
                        SettingRow(stringResource(R.string.privacy), null) { openUrl(context, Brand.PRIVACY) }
                        SettingRow(stringResource(R.string.terms), null) { openUrl(context, Brand.TERMS) }
                    }
                    SettingRow(stringResource(R.string.station_data_credit), if (Device.isTV) "radio-browser.info" else null,
                        chevron = !Device.isTV) { if (!Device.isTV) openUrl(context, Brand.RADIO_BROWSER) }
                }
            }
            item {
                Column(Modifier.fillMaxWidth().padding(top = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    TunrLogo(20.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(stringResource(R.string.made_with), color = T.secondary, fontSize = 12.sp)
                }
            }
        }
    }

    when (dialog) {
        "language" -> ChoiceDialog(
            title = stringResource(R.string.language),
            options = listOf(Settings.SYSTEM to stringResource(R.string.language_system), "nl" to "Nederlands", "en" to "English"),
            selected = settings.language,
            onDismiss = { dialog = null }
        ) { tag ->
            dialog = null
            if (tag != settings.language) {
                Library.updateSettings { it.copy(language = tag) }
                context.findActivity()?.recreate()
            }
        }
        "sleep" -> ChoiceDialog(
            title = stringResource(R.string.default_sleep_timer),
            options = listOf(0, 15, 30, 60).map { it.toString() to sleepLabelPlain(it) },
            selected = settings.defaultSleepMinutes.toString(),
            onDismiss = { dialog = null }
        ) { v -> dialog = null; Library.updateSettings { it.copy(defaultSleepMinutes = v.toInt()) } }
        "recents" -> ConfirmDialog(stringResource(R.string.clear_recents), stringResource(R.string.clear_recents_confirm),
            onConfirm = { Library.clearRecents(); dialog = null }, onDismiss = { dialog = null })
        "favorites" -> ConfirmDialog(stringResource(R.string.clear_favorites), stringResource(R.string.clear_favorites_confirm),
            onConfirm = { Library.clearFavorites(); dialog = null }, onDismiss = { dialog = null })
    }
}

@Composable
private fun languageLabel(tag: String): String = when (tag) {
    "nl" -> "Nederlands"
    "en" -> "English"
    else -> stringResource(R.string.language_system)
}

@Composable
private fun sleepLabel(min: Int): String = sleepLabelPlain(min)

@Composable
private fun sleepLabelPlain(min: Int): String =
    if (min <= 0) stringResource(R.string.off) else stringResource(R.string.minutes_n, min)

@Composable
private fun Group(title: String, content: @Composable () -> Unit) {
    Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().padding(top = 20.dp)) {
        Text(title.uppercase(), color = T.secondary, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp,
            modifier = Modifier.padding(start = 4.dp, bottom = 8.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.surface)) { content() }
    }
}

@Composable
private fun SettingRow(
    title: String,
    value: String?,
    destructive: Boolean = false,
    chevron: Boolean = true,
    focus: androidx.compose.ui.focus.FocusRequester? = null,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .tvClickable(RoundedCornerShape(12.dp), scale = 1.02f, focusRequester = focus, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 15.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, color = if (destructive) T.live else T.text, fontSize = 16.sp, modifier = Modifier.weight(1f),
            maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (value != null) {
            Spacer(Modifier.width(8.dp))
            Text(value, color = T.secondary, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 220.dp))
        }
        if (chevron && !destructive) Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = T.secondary)
    }
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .tvClickable(RoundedCornerShape(12.dp), scale = 1.02f, role = androidx.compose.ui.semantics.Role.Switch) { onChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, color = T.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Switch(
            checked = checked, onCheckedChange = null,
            colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = T.accent,
                uncheckedThumbColor = T.secondary, uncheckedTrackColor = T.elevated, uncheckedBorderColor = T.stroke)
        )
    }
}

@Composable
private fun ChoiceDialog(
    title: String,
    options: List<Pair<String, String>>,
    selected: String,
    onDismiss: () -> Unit,
    onPick: (String) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = T.elevated,
        title = { Text(title, style = heading(20.sp)) },
        text = {
            Column {
                val first = rememberInitialFocus()
                options.forEachIndexed { i, (key, label) ->
                    Row(
                        Modifier.fillMaxWidth()
                            .tvClickable(RoundedCornerShape(10.dp), scale = 1.02f, focusRequester = if (i == 0) first else null) { onPick(key) }
                            .padding(horizontal = 8.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(label, color = T.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                        if (key == selected) Icon(Icons.Rounded.Check, null, tint = T.accent)
                        else Box(Modifier.size(24.dp))
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = T.secondary) } },
    )
}

/** De Activity achter een (gewikkelde) Context */
tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

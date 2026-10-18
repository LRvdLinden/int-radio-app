#!/usr/bin/env bash
# Opnames voor Google Play in een draaiende Android-emulator (workflow *Play Store media*).
#   tools/playstore_capture.sh <toestel> <apk> <rawmap> "<scènes>" [wachttijd]
# Start de app per scène met de extra tunr_screenshot (android/.../ui/ScreenshotMode.kt) en bewaart
# <rawmap>/<toestel>-<scène>.png. Statusbalk in demomodus (09:41, volle batterij, wifi).
set -u
DEV=$1 APK=$2 RAW=$3 SCENES=$4 WAIT=${5:-15}
PKG=nl.lrvdlinden.tunr
ACT=$PKG/.MainActivity
mkdir -p "$RAW"
adb wait-for-device
# wachten tot het systeem echt klaar is
for _ in $(seq 1 90); do [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break; sleep 2; done
adb shell settings put global window_animation_scale 0 || true
adb shell settings put global transition_animation_scale 0 || true
adb shell settings put global animator_duration_scale 0 || true
adb shell cmd uimode night yes || true
# geen "… reageert niet"-meldingen in beeld (trage emulator)
adb shell settings put global hide_error_dialogs 1 || true
adb shell settings put global anr_show_background 0 || true
# taal: de emulator staat standaard op Engels (Verenigde Staten), zoals de App Store-afbeeldingen
# statusbalk: demomodus
adb shell settings put global sysui_demo_allowed 1 || true
demo() { adb shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null 2>&1 || true; }
demo enter
demo clock -e hhmm 0941
demo battery -e level 100 -e plugged false
demo network -e wifi show -e level 4
demo network -e mobile hide
demo notifications -e visible false

adb install -r -g "$APK" || { echo "::error::$DEV: installeren mislukt"; exit 1; }
adb shell wm size; adb shell wm density
# opwarmen: caches (landen, iconentabel, logo's) vullen
adb shell am start -W -n "$ACT" --es tunr_screenshot discover >/dev/null || true
sleep 30
for s in $SCENES; do
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$ACT" --es tunr_screenshot "$s" >/dev/null || echo "::warning::$DEV-$s: starten mislukt"
  sleep "$WAIT"
  [ "$s" = "player" ] && sleep 8   # stream + nu-speelt-titel + albumhoes
  [ "$s" = "map" ] && sleep 8      # kaarttegels
  # eventuele systeemmelding sluiten en de app weer naar voren
  if adb shell dumpsys window | grep -qiE "Application Not Responding|isn.t responding"; then
    echo "::warning::$DEV-$s: ANR-melding, opnieuw"
    adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
    adb shell input keyevent KEYCODE_BACK; sleep 2
    adb shell am start -W -n "$ACT" --es tunr_screenshot "$s" >/dev/null || true
    sleep "$WAIT"
  fi
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
  adb exec-out screencap -p > "$RAW/$DEV-$s.png" || echo "::warning::$DEV-$s: geen opname"
  python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(sys.argv[1].split('/')[-1],*struct.unpack('>II',d[16:24]))" "$RAW/$DEV-$s.png" 2>/dev/null \
    || echo "::warning::$DEV-$s: opname ongeldig"
done
adb shell am force-stop "$PKG" || true
ls -la "$RAW"

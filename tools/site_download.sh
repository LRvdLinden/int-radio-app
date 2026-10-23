#!/usr/bin/env bash
# Zet een beta-buildpakket openbaar op tunr.online (map downloads/) en werkt downloads/latest.json bij.
#
#   tools/site_download.sh <windows|android> <bestand> <versie> <build>
#
# windows → downloads/Tunr-Setup.exe, android → downloads/Tunr.apk (altijd de nieuwste; vaste naam zodat de knoppen op
# de homepage niet hoeven te veranderen). latest.json: {"windows": {file, version, build, size, sha256, date}, ...}.
# Omgeving: FTP_SERVER, FTP_USERNAME, FTP_PASSWORD (de secrets van de workflow Website), optioneel FTP_DIR.
# FTPS met certificaatcontrole via tools/ftps.sh uit tunr-beheer (zelfde aanpak als beheer_upload.sh).
# Het log is openbaar: geen mappen, servernamen of serverantwoorden.
set -euo pipefail
KIND="${1:?windows|android}"; FILE="${2:?bestand}"; VERSION="${3:?versie}"; BUILD="${4:?build}"
case "$KIND" in
  windows) NAME="Tunr-Setup.exe" ;;
  android) NAME="Tunr.apk" ;;
  *) echo "::error::Onbekend soort: $KIND"; exit 2 ;;
esac
[ -s "$FILE" ] || { echo "::error::Bestand ontbreekt."; exit 2; }
[[ "$BUILD" =~ ^[0-9]{1,7}$ ]] || { echo "::error::Ongeldig buildnummer."; exit 2; }
command -v lftp >/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq lftp >/dev/null; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export FTPS_TMP="$WORK/ftps"; mkdir -p "$FTPS_TMP"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/LRvdLinden/tunr-beheer/main/tools/ftps.sh" -o "$WORK/ftps.sh"
# de website-login komt uit in de webmap van tunr.online; die is hier juist het doel (FTP_DIR, standaard ".")
export FTP_DIR="${FTP_DIR:-.}"
# shellcheck source=/dev/null
source "$WORK/ftps.sh"
ftps_connect
B="$FTPS_TARGET/downloads"

SIZE=$(wc -c < "$FILE" | tr -d ' ')
SHA=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$FILE")
ftps_try "get \"$B/latest.json\" -o \"$WORK/latest.json\"" >/dev/null 2>&1 || true
python3 - "$WORK/latest.json" "$KIND" "$NAME" "$VERSION" "$BUILD" "$SIZE" "$SHA" <<'PY'
import json, sys, datetime, os
p, kind, name, version, build, size, sha = sys.argv[1:]
try: d = json.load(open(p)) if os.path.getsize(p) else {}
except Exception: d = {}
if not isinstance(d, dict): d = {}
d[kind] = {"file": name, "version": version, "build": int(build), "size": int(size), "sha256": sha,
           "date": datetime.date.today().isoformat()}
json.dump(d, open(p, "w"), indent=2, sort_keys=True)
PY
ftps_run "mkdir -p -f \"$B\"; put \"$FILE\" -o \"$B/$NAME.part\"; rm -f \"$B/$NAME\"; mv \"$B/$NAME.part\" \"$B/$NAME\"; chmod 644 \"$B/$NAME\"; put \"$WORK/latest.json\" -o \"$B/latest.json\"; chmod 644 \"$B/latest.json\"" >/dev/null 2>&1 \
  || { echo "::error::Upload naar tunr.online/downloads mislukt."; exit 1; }
echo "::notice::$NAME ($VERSION, build $BUILD) staat op tunr.online/downloads/."

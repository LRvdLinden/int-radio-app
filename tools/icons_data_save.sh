#!/usr/bin/env bash
# Bestanden op de branch icons-data bijwerken zonder iets van een andere run kwijt te raken (workflow Icons).
#
#   GH_TOKEN=... tools/icons_data_save.sh "<bericht>" cache.json=/pad/a.json site-cache.json=/pad/b.json ...
#
# Haalt de nieuwste icons-data op, voegt *cache.json samen met tools/merge_icon_tables.py (per item de nieuwste
# datum; niets verdwijnt), kopieert andere bestanden, en zet het resultaat terug als één commit (zonder
# geschiedenis, zodat de branch klein blijft) met --force-with-lease: als iemand anders er net tussen pushte,
# opnieuw vanaf zijn versie. Ontbrekende of lege bronbestanden worden overgeslagen.
set -euo pipefail
msg="$1"; shift
tools="$(cd "$(dirname "$0")" && pwd)"
url="${ICONS_DATA_REMOTE:-https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git}"
work="$(mktemp -d)"
for i in 1 2 3 4 5 6; do
  rm -rf "$work/d"; mkdir -p "$work/d"; cd "$work/d"
  git init -q
  git remote add origin "$url"
  lease="refs/heads/icons-data:"   # leeg = de branch mag nog niet bestaan
  if git fetch -q --depth 1 origin icons-data 2>/dev/null; then
    lease="refs/heads/icons-data:$(git rev-parse FETCH_HEAD)"
    git checkout -q FETCH_HEAD -- . 2>/dev/null || true
  fi
  git checkout -q --orphan icons-data-new
  changed=0
  for pair in "$@"; do
    name="${pair%%=*}"; src="${pair#*=}"
    [ -s "$src" ] || continue
    case "$name" in
      *cache.json)
        if [ -s "$name" ]; then
          python3 "$tools/merge_icon_tables.py" cache "$name" "$src" --out "$name.new" >/dev/null
          mv "$name.new" "$name"
        else
          cp "$src" "$name"
        fi ;;
      *) cp "$src" "$name" ;;
    esac
    changed=1
  done
  [ "$changed" = 1 ] || { echo "icons-data: niets te bewaren"; exit 0; }
  git add -A .
  git -c user.name=github-actions -c user.email=actions@github.com commit -q -m "$msg [skip ci]"
  if git push -q --force-with-lease="$lease" origin HEAD:refs/heads/icons-data 2>/dev/null; then
    echo "icons-data bijgewerkt ($(ls | tr '\n' ' '))"; exit 0
  fi
  echo "icons-data veranderde tussendoor: opnieuw ($i)"
  sleep $((i * 5))
done
echo "::error::icons-data niet bijgewerkt"; exit 1

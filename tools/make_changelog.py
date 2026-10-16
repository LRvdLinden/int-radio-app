#!/usr/bin/env python3
"""Maakt CHANGELOG.md (Nederlands, met Engelse regel eronder) en website/assets/changelog.json
uit docs/changelog.json.

    python3 tools/make_changelog.py
"""
import json, pathlib, shutil

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "docs/changelog.json"
data = json.loads(src.read_text())

NAMES = {"ios": "iPhone", "ipados": "iPad", "macos": "Mac", "tvos": "Apple TV", "carplay": "CarPlay",
         "android": "Android", "androidtv": "Android TV", "web": "Website"}
ALL = set(NAMES)
TYPES = {"new": "Nieuw", "improved": "Verbeterd", "fixed": "Opgelost"}

lines = ["# Changelog", "",
         "Alle wijzigingen per build. Versie blijft 1.0.0; elk platform heeft zijn eigen buildnummer.", "",
         "Ook online: de pagina *changelog* op de website.", ""]
for b in sorted(data["builds"], key=lambda x: -x["build"]):
    lines += [f"## Build {b['build']}", f"_{b['date']}_", ""]
    for kind in ("new", "improved", "fixed"):
        items = [i for i in b["items"] if i["type"] == kind]
        if not items:
            continue
        lines.append(f"**{TYPES[kind]}**")
        lines.append("")
        for i in items:
            plats = set(i["platforms"])
            label = "Alle apps" if plats >= ALL else ", ".join(NAMES[p] for p in i["platforms"])
            lines.append(f"- {i['nl']} _({label})_  ")
            lines.append(f"  <sub>{i['en']}</sub>")
        lines.append("")

(root / "CHANGELOG.md").write_text("\n".join(lines).rstrip() + "\n")
dst = root / "website/assets/changelog.json"
dst.parent.mkdir(parents=True, exist_ok=True)
shutil.copy(src, dst)
print("CHANGELOG.md +", dst.relative_to(root))

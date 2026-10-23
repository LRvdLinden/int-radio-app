#!/usr/bin/env python3
"""Zet de versie van Tunr (zonder buildnummer) op alle plekken tegelijk.

    python3 tools/set_version.py 1.0.1

Daarna in dezelfde commit: buildnummer(s) omhoog en een item in docs/changelog.json met "version": "<versie>"
(zie CLAUDE.md). Plekken: Apple (MARKETING_VERSION, Brand.version), Android (TUNR_VERSION), website
(brand.js, footers), User-Agent van de tools en de documentatie.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RULES = [  # (bestand of glob, patroon, vervanging met {v})
    ("apple/project.yml", r'MARKETING_VERSION: "[\d.]+"', 'MARKETING_VERSION: "{v}"'),
    ("apple/Shared/App/Brand.swift", r'static let version = "[\d.]+"', 'static let version = "{v}"'),
    ("android/gradle.properties", r'TUNR_VERSION=[\d.]+', 'TUNR_VERSION={v}'),
    ("android/app/build.gradle.kts", r'\?: "[\d.]+"', '?: "{v}"'),
    ("website/assets/js/brand.js", r"version: '[\d.]+'", "version: '{v}'"),
    ("windows/app/assets/js/brand.js", r"version: '[\d.]+'", "version: '{v}'"),
    ("windows/src-tauri/tauri.conf.json", r'"version": "[\d.]+"', '"version": "{v}"'),
    ("windows/src-tauri/Cargo.toml", r'(?m)^version = "[\d.]+"', 'version = "{v}"'),
    ("website/assets/js/home.js", r"\|\| '[\d.]+'\) \+ ' · build", "|| '{v}') + ' · build"),
    ("website/**/*.html", r'<span data-build>[\d.]+ ·', '<span data-build>{v} ·'),
    ("tools/*.py", r"Tunr/[\d.]+ \(\+https://tunr\.online\)", "Tunr/{v} (+https://tunr.online)"),
    ("docs/SPEC.md", r"Tunr/[\d.]+ \(nl\.lrvdlinden", "Tunr/{v} (nl.lrvdlinden"),
    ("CLAUDE.md", r"User-Agent `Tunr/[\d.]+`", "User-Agent `Tunr/{v}`"),
    ("CLAUDE.md", r"Huidige versie: \*\*[\d.]+\*\*", "Huidige versie: **{v}**"),
]


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        sys.exit("gebruik: python3 tools/set_version.py 1.0.1")
    v = sys.argv[1]
    changed = 0
    for pattern, rx, repl in RULES:
        files = sorted(ROOT.glob(pattern)) if "*" in pattern else [ROOT / pattern]
        hits = 0
        for f in files:
            if not f.exists() or "website/radio/" in f.as_posix():
                continue
            s = f.read_text(encoding="utf-8")
            n_s, n = re.subn(rx, repl.format(v=v), s)
            hits += n
            if n_s != s:
                f.write_text(n_s, encoding="utf-8"); changed += 1
                print(f"  {f.relative_to(ROOT)}: {n}×")
        if not hits:
            sys.exit(f"FOUT: niets gevonden voor {pattern} ({rx})")
    print(f"versie {v}: {changed} bestanden bijgewerkt")


if __name__ == "__main__":
    main()

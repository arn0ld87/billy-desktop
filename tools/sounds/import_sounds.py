#!/usr/bin/env python3
"""Macht aus heruntergeladenen Geräuschen (z. B. CC0 von freesound.org) Billys Sounds.

Erwartet im Eingabeordner Audiodateien mit diesen Namen (beliebige Endung, die ffmpeg lesen kann):
  bark, happy, pant, whine, snore, sniff, yawn, drop   – optional mit Nummer: bark_1.wav, bark_2.mp3 …

Pro Datei: Stille vorn/hinten abschneiden, auf höchstens MAX_SECONDS kürzen, Lautheit angleichen
(damit Bellen nicht lauter ist als Schnüffeln), sanft ausblenden, als AAC (.m4a) speichern.
Eine CREDITS.md im Eingabeordner wird mitkopiert (Quellen und Lizenzen).

Aufruf:
  python3 tools/sounds/import_sounds.py sounds --out Resources/Sounds     # mitgeliefert (make sounds-bundle)
  python3 tools/sounds/import_sounds.py ~/Downloads/Billy-Ton              # nur auf diesem Mac (make sounds)
Braucht ffmpeg (brew install ffmpeg).
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

EVENTS = ["bark", "happy", "pant", "whine", "snore", "sniff", "yawn", "drop"]
# Längere Geräusche wie Schnarchen dürfen etwas länger sein.
MAX_SECONDS = {"snore": 4.0, "pant": 3.0, "yawn": 3.0}
DEFAULT_MAX = 2.0
LOUDNESS = {"sniff": -24, "drop": -24, "snore": -26}   # LUFS; leise Geräusche bleiben leiser
DEFAULT_LOUDNESS = -20
DEFAULT_OUT = Path.home() / "Library" / "Application Support" / "Billy Desktop" / "Sounds"
FILE_RE = re.compile(r"^(?P<event>[a-z]+)(?:[_-](?P<index>\d+))?\.[a-z0-9]+$", re.I)


def collect(src: Path) -> dict[str, list[Path]]:
    found: dict[str, list[tuple[int, Path]]] = {}
    for path in sorted(src.iterdir()):
        m = FILE_RE.match(path.name)
        if not m or m["event"].lower() not in EVENTS or path.suffix.lower() == ".md":
            continue
        found.setdefault(m["event"].lower(), []).append((int(m["index"] or 0), path))
    return {event: [p for _, p in sorted(items)] for event, items in found.items()}


def convert(src: Path, dst: Path, event: str) -> None:
    seconds = MAX_SECONDS.get(event, DEFAULT_MAX)
    trim = "silenceremove=start_periods=1:start_threshold=-45dB"
    filters = ",".join([
        trim, "areverse", trim, "areverse",                 # Stille vorn und hinten weg
        f"atrim=0:{seconds}",
        f"afade=t=out:st={max(0.0, seconds - 0.15)}:d=0.15",
        f"loudnorm=I={LOUDNESS.get(event, DEFAULT_LOUDNESS)}:TP=-2:LRA=11",
    ])
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(src), "-af", filters, "-ac", "1", "-ar", "44100",
         "-c:a", "aac", "-b:a", "96k", str(dst)],
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="Ordner mit den heruntergeladenen Geräuschen")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"Zielordner (Standard: {DEFAULT_OUT})")
    args = parser.parse_args()

    if shutil.which("ffmpeg") is None:
        print("Fehler: ffmpeg fehlt – bitte `brew install ffmpeg`.", file=sys.stderr)
        return 1
    src = args.source.expanduser()
    events = collect(src)
    if not events:
        print(f"Fehler: keine passenden Dateien in {src} (Namen wie bark.wav, snore_1.mp3 …).", file=sys.stderr)
        return 1

    out = args.out.expanduser()
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.m4a"):
        old.unlink()
    count = 0
    for event in EVENTS:
        for i, path in enumerate(events.get(event, [])):
            dst = out / f"{event}_{i:02d}.m4a"
            print(f"{path.name} → {dst.name}")
            convert(path, dst, event)
            count += 1
    credits = src / "CREDITS.md"
    if credits.exists():
        shutil.copy(credits, out / "CREDITS.md")
    else:
        print("Hinweis: keine CREDITS.md gefunden – bitte Quellen und Lizenzen notieren.")
    missing = [e for e in EVENTS if e not in events]
    if missing:
        print(f"Noch ohne Geräusch (Billy bleibt dort still): {', '.join(missing)}")
    print(f"\n✔ {count} Geräusche → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

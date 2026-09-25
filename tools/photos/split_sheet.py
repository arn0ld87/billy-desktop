#!/usr/bin/env python3
"""Zerlegt ein Übersichtsbild mit mehreren Billy-Posen (z. B. aus ChatGPT) in Einzelbilder.

Jeder Hund wird per KI-Freistellung (rembg) gefunden, in Lesereihenfolge (Zeilen von oben,
dann von links) sortiert und unter den angegebenen Namen als freigestelltes PNG gespeichert.
Beschriftungen wie „walk_1.png“ im Bild werden ignoriert.

Aufruf:
  python3 tools/photos/split_sheet.py uebersicht.jpg ~/Pictures/Billy-Fotos \\
      --names walk_1,walk_2,walk_3,walk_4,carry,sit,happy,bark,lie,sleep,sniff
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_photos import rembg_cutout  # noqa: E402


def find_dogs(alpha: np.ndarray, min_share: float = 0.01):
    solid = alpha > 100
    solid = ndimage.binary_closing(solid, iterations=3)
    labels, n = ndimage.label(solid)
    boxes = []
    total = alpha.shape[0] * alpha.shape[1]
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        area = int((labels[sl] == i).sum())
        if area >= total * min_share:
            boxes.append((sl, i, area))
    return labels, boxes


def reading_order(boxes):
    items = [(sl[0].start, sl[0].stop, sl[1].start, b) for b in boxes for sl in [b[0]]]
    items.sort(key=lambda t: (t[0] + t[1]) / 2)
    rows, current = [], []
    for it in items:
        cy = (it[0] + it[1]) / 2
        if current and cy > max(c[1] for c in current):  # unterhalb aller bisherigen Zeilenelemente
            rows.append(current)
            current = []
        current.append(it)
    if current:
        rows.append(current)
    return [it[3] for row in rows for it in sorted(row, key=lambda t: t[2])]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("sheet", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--names", required=True, help="Kommagetrennte Posen-Namen in Lesereihenfolge")
    args = parser.parse_args()

    names = [n.strip() for n in args.names.split(",") if n.strip()]
    img = Image.open(args.sheet)
    rgba = np.array(img.convert("RGBA")).astype(np.float32)
    if np.median(np.concatenate([rgba[0, :, 3], rgba[-1, :, 3], rgba[:, 0, 3], rgba[:, -1, 3]])) < 10:
        cut = rgba                      # schon transparent – Maske direkt übernehmen
    else:
        cut = rembg_cutout(img)
    if cut is None:
        print("Bitte zuerst installieren: pip install 'rembg[cpu]'", file=sys.stderr)
        return 1
    labels, boxes = find_dogs(cut[..., 3])
    ordered = reading_order(boxes)
    if len(ordered) != len(names):
        print(f"Achtung: {len(ordered)} Hunde gefunden, aber {len(names)} Namen angegeben.", file=sys.stderr)

    out = args.out.expanduser()
    out.mkdir(parents=True, exist_ok=True)
    for idx, (sl, label, _) in enumerate(ordered):
        name = names[idx] if idx < len(names) else f"extra_{idx + 1}"
        y0, y1 = max(0, sl[0].start - 8), min(cut.shape[0], sl[0].stop + 8)
        x0, x1 = max(0, sl[1].start - 8), min(cut.shape[1], sl[1].stop + 8)
        crop = cut[y0:y1, x0:x1].copy()
        crop[..., 3] *= ndimage.binary_dilation(labels[y0:y1, x0:x1] == label, iterations=4)
        Image.fromarray(np.clip(crop, 0, 255).astype(np.uint8), "RGBA").save(out / f"{name}.png")
        print(f"✔ {name}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())

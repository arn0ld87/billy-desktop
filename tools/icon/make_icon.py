#!/usr/bin/env python3
"""Erzeugt das App-Icon (AppIcon.iconset) aus einem Foto von Billy.

Aufruf: python3 tools/icon/make_icon.py <foto.jpg> <x> <y> <kantenlaenge>
Der quadratische Ausschnitt (x, y, Kantenlänge) wird aufgehellt und in eine
macOS-typische abgerundete Kachel gesetzt. Ergebnis: Resources/AppIcon.iconset
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Resources" / "AppIcon.iconset"


def squircle_mask(size, radius_ratio=0.225):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * radius_ratio), fill=255)
    return m


def main():
    src, x, y, side = sys.argv[1], *map(int, sys.argv[2:5])
    photo = Image.open(src).convert("RGB").crop((x, y, x + side, y + side))
    photo = ImageEnhance.Brightness(photo).enhance(1.35)
    photo = ImageEnhance.Contrast(photo).enhance(1.08)
    photo = ImageEnhance.Color(photo).enhance(1.1)

    canvas = 1024
    tile = 824                      # Apple-Raster: 100 px Rand
    icon = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (100, 112), squircle_mask(tile))
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    face = photo.resize((tile, tile), Image.LANCZOS).convert("RGBA")
    icon.paste(face, (100, 100), squircle_mask(tile))

    OUT.mkdir(parents=True, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            icon.resize((px, px), Image.LANCZOS).save(OUT / name)
    icon.save(ROOT / "Resources" / "AppIcon-1024.png")


if __name__ == "__main__":
    main()

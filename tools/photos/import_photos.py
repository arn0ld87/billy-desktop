#!/usr/bin/env python3
"""Macht aus ChatGPT-Bildern von Billy fertige Sprites für die App.

Erwartet im Eingabeordner PNG/JPG/WEBP-Dateien mit diesen Namen (nur stand ist Pflicht):
  stand, walk_1 … walk_n (oder walk), carry, sit, happy, bark, lie, sleep, sniff

Pro Bild: Hintergrund entfernen (Transparenz oder Greenscreen #00FF00), Krümel entfernen,
zuschneiden, einheitlich skalieren, auf die Bodenlinie setzen, Anker (Nase/Maul/Kopf)
berechnen. Ergebnis: sprites.json + PNGs im Zielordner (Standard: Foto-Ordner der App).

Aufruf:
  python3 tools/photos/import_photos.py ~/Pictures/Billy-Fotos
  python3 tools/photos/import_photos.py ~/Pictures/Billy-Fotos --out /tmp/test --flip sit.png
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

W, H = 320, 240          # Frame in Pixeln (@2x → 160×120 pt, wie die Zeichnung)
GROUND = 224             # Bodenlinie in Pixeln von oben
DEFAULT_OUT = Path.home() / "Library" / "Application Support" / "Billy Desktop" / "Sprites"

POSES = ["stand", "walk", "carry", "sit", "happy", "bark", "lie", "sleep", "sniff"]
# Zielbox (Breite, Höhe) in Pixeln je Posen-Typ – das Bild wird proportional hineingepasst.
BOX = {
    "stand": (250, 200), "walk": (250, 200), "carry": (250, 200), "sniff": (250, 190),
    "sit": (200, 205), "happy": (200, 205), "bark": (200, 205),
    "lie": (290, 130), "sleep": (290, 120),
}
FILE_RE = re.compile(r"^(?P<pose>[a-z]+)(?:[_-](?P<index>\d+))?\.(png|jpe?g|webp)$", re.I)


_REMBG_SESSION = None


def rembg_cutout(img: Image.Image):
    """KI-Freistellung (rembg/ISNet), falls installiert – klappt auch bei weißem Hund auf Weiß."""
    global _REMBG_SESSION
    try:
        from rembg import new_session, remove
    except ImportError:
        return None
    if _REMBG_SESSION is None:
        _REMBG_SESSION = new_session("isnet-general-use")
    rgb = img.convert("RGB")
    mask = np.array(remove(rgb, session=_REMBG_SESSION, only_mask=True)).astype(np.float32)
    rgba = np.dstack([np.array(rgb).astype(np.float32), mask])   # Farben vom Original, Maske von der KI
    return solidify(rgba)


def solidify(rgba: np.ndarray) -> np.ndarray:
    """Weißes Fell vor weißem Hintergrund wird teils halbtransparent: Inneres voll deckend machen,
    nur ein schmaler Rand bleibt weich."""
    alpha = rgba[..., 3]
    solid = ndimage.binary_fill_holes(ndimage.binary_closing(alpha > 60, iterations=2))
    core = ndimage.binary_erosion(solid, iterations=3)
    rgba[..., 3] = np.where(core, 255, np.where(solid, np.maximum(alpha, 160), alpha * 0.6))
    return rgba


def remove_background(img: Image.Image) -> np.ndarray:
    """Liefert RGBA-Array mit freigestelltem Hund."""
    rgba = np.array(img.convert("RGBA")).astype(np.float32)
    alpha = rgba[..., 3]
    border = np.concatenate([alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]])
    if np.median(border) < 10:
        return rgba  # schon transparent

    rgb = rgba[..., :3]
    edge = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(edge, axis=0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    if bg[1] > bg[0] + 60 and bg[1] > bg[2] + 60:
        # Greenscreen: Grün-Überschuss bestimmt die Transparenz, danach Grünstich entfernen.
        excess = g - np.maximum(r, b)
        a = np.clip((90 - excess) / 60, 0, 1) * 255
        spill = np.clip(excess, 0, None)
        rgba[..., 1] = g - spill * 0.9
    elif (cut := rembg_cutout(img)) is not None:
        return cut
    else:
        # Einfarbiger Hintergrund ohne rembg: von den Rändern aus flutfüllen.
        dist = np.sqrt(((rgb - bg) ** 2).sum(axis=-1))
        similar = dist < 38
        labels, _ = ndimage.label(similar)
        edge_labels = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
        background = np.isin(labels, list(edge_labels))
        a = np.where(background, 0, 255).astype(np.float32)
        a = ndimage.gaussian_filter(a, 0.8)
        if (bg > 225).all():
            print("  Hinweis: weißer Hintergrund bei weißem Hund – besser `pip install rembg` oder Greenscreen #00FF00.")
    rgba[..., 3] = a
    return rgba


def keep_largest(rgba: np.ndarray) -> np.ndarray:
    solid = rgba[..., 3] > 128
    labels, n = ndimage.label(solid)
    if n > 1:
        sizes = ndimage.sum(solid, labels, range(1, n + 1))
        keep = labels == (int(np.argmax(sizes)) + 1)
        keep = ndimage.binary_dilation(keep, iterations=3)
        rgba[..., 3] *= keep
    return rgba


def trim(rgba: np.ndarray) -> Image.Image:
    ys, xs = np.nonzero(rgba[..., 3] > 20)
    if len(xs) == 0:
        raise ValueError("Kein Hund gefunden (alles transparent).")
    crop = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return Image.fromarray(np.clip(crop, 0, 255).astype(np.uint8), "RGBA")


def fit_scale(dog: Image.Image, pose: str) -> float:
    bw, bh = BOX[pose]
    return min(bw / dog.width, bh / dog.height, (W - 8) / dog.width, (GROUND - 4) / dog.height)


def body_center_x(dog: Image.Image) -> float:
    """Mitte des Rumpfs (obere 55 %) – ruhiger als die Bildmitte, wenn die Beine schwingen."""
    a = np.array(dog)[..., 3] > 128
    top = a[: max(1, int(a.shape[0] * 0.55))]
    xs = np.nonzero(top)[1]
    return float(xs.mean()) if len(xs) else dog.width / 2


def place(dog: Image.Image, scale: float) -> Image.Image:
    size = (max(1, round(dog.width * scale)), max(1, round(dog.height * scale)))
    dog = dog.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # weicher Bodenschatten
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cx = W // 2
    ImageDraw.Draw(shadow).ellipse((cx - dog.width * 0.42, GROUND - 7, cx + dog.width * 0.42, GROUND + 7), fill=(0, 0, 0, 40))
    frame.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(3)))
    x = round(cx - body_center_x(dog))
    x = min(max(x, 2), W - dog.width - 2) if dog.width < W - 4 else (W - dog.width) // 2
    frame.alpha_composite(dog, (x, GROUND - dog.height))
    return frame


def anchors(frame: Image.Image) -> dict:
    """Nase = vorderster Punkt, Maul knapp dahinter, Kopf = höchster Punkt im vorderen Drittel."""
    a = np.array(frame)[..., 3] > 128
    ys, xs = np.nonzero(a)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w, h = x1 - x0, y1 - y0
    front = xs >= x1 - max(3, int(w * 0.03))
    nose = (x1, float(np.mean(ys[front])))
    mouth = (x1 - w * 0.08, nose[1] + h * 0.04)
    band = xs >= x1 - w * 0.33
    head_top = float(ys[band].min())
    head = (x1 - w * 0.18, head_top + h * 0.08)
    to_pt = lambda p: [round(float(p[0]) / 2, 1), round(float(p[1]) / 2, 1)]
    return {"nose": to_pt(nose), "mouth": to_pt(mouth), "head": to_pt(head)}


def collect(src: Path) -> dict[str, list[Path]]:
    found: dict[str, list[tuple[int, Path]]] = {}
    for path in sorted(src.iterdir()):
        m = FILE_RE.match(path.name)
        if not m or m["pose"].lower() not in POSES:
            continue
        found.setdefault(m["pose"].lower(), []).append((int(m["index"] or 0), path))
    return {pose: [p for _, p in sorted(items)] for pose, items in found.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="Ordner mit den ChatGPT-Bildern")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"Zielordner (Standard: {DEFAULT_OUT})")
    parser.add_argument("--flip", action="append", default=[], help="Dateiname, der gespiegelt werden soll (Kopf zeigt nach links)")
    args = parser.parse_args()

    poses = collect(args.source.expanduser())
    if "stand" not in poses:
        print(f"Fehler: {args.source}/stand.png fehlt (Pflicht).", file=sys.stderr)
        return 1
    out = args.out.expanduser()
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()

    meta = {"frameSize": [W // 2, H // 2], "scale": 2, "groundY": GROUND / 2, "animations": {}}
    for pose in POSES:
        dogs = []
        for path in poses.get(pose, []):
            print(f"{path.name} → {pose}")
            img = Image.open(path)
            if path.name in args.flip:
                img = img.transpose(Image.FLIP_LEFT_RIGHT)
            dogs.append(trim(keep_largest(remove_background(img))))
        if not dogs:
            continue
        # eine gemeinsame Skalierung pro Pose, damit Billy zwischen Laufbildern nicht pumpt
        scale = float(np.median([fit_scale(d, pose) for d in dogs]))
        for i, dog in enumerate(dogs):
            frame = place(dog, min(scale, fit_scale(dog, pose) * 1.08))
            name = f"{pose}_{i:02d}.png"
            frame.save(out / name, optimize=True)
            meta["animations"].setdefault(pose, []).append({"file": name, "anchors": anchors(frame)})
    (out / "sprites.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"\n✔ {sum(len(v) for v in meta['animations'].values())} Bilder → {out}")
    print("In der App: Menüleiste 🐾 → Aussehen → Echte Fotos")
    return 0


if __name__ == "__main__":
    sys.exit(main())

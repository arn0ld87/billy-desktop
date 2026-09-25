#!/usr/bin/env python3
"""Rendert Billys Sprite-Frames (Seitenansicht, Blick nach rechts).

Billy wird als Skelett (Hüfte, Körperwinkel, Beingelenke, Hals, Kopf, Rute)
beschrieben und als Sticker mit Kontur gerendert. Ausgabe:

  Resources/Sprites/<animation>_<nn>.png   (320x240 px, @2x)
  Resources/Sprites/sprites.json           (Frames + Anker)

Aufruf:  python3 tools/sprites/generate_sprites.py
"""
from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass, field, replace
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

W, H = 320, 240          # Ausgabegröße in Pixeln (@2x -> 160x120 pt)
S = 4                    # Supersampling-Faktor
GROUND = 224             # Bodenlinie (Pixel, von oben)
OUTLINE = 2.6            # Konturbreite in Ausgabepixeln

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "Resources" / "Sprites"

# Farben nach Billys Fotos: weiß mit hellbraunen Platten, rosa Nase, Bernsteinaugen
C_OUT = (74, 56, 44, 255)
C_LINE = (180, 160, 146, 255)
C_WHITE = (252, 249, 244, 255)
C_SHADE = (226, 217, 205, 255)
C_TAN = (212, 142, 86, 255)
C_TAN_DARK = (184, 116, 66, 255)
C_EAR_IN = (238, 186, 170, 255)
C_NOSE = (196, 128, 116, 255)
C_EYE = (216, 160, 62, 255)
C_PUPIL = (40, 28, 20, 255)
C_MOUTH = (122, 48, 50, 255)
C_TONGUE = (232, 120, 128, 255)


# --------------------------------------------------------------------------- Geometrie

def rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def down(a):
    """Richtungsvektor: Winkel 0 = senkrecht nach unten, positiv = nach vorn (rechts)."""
    return (math.sin(a), math.cos(a))


def ellipse_poly(c, rx, ry, ang=0.0, n=72):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        p = rot((rx * math.cos(t), ry * math.sin(t)), ang)
        pts.append(add(c, p))
    return pts


def capsule_polys(p1, p2, r1, r2):
    """Konischer Zylinder mit runden Enden als Liste von Polygonen."""
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    ln = math.hypot(dx, dy) or 1e-6
    nx, ny = -dy / ln, dx / ln
    quad = [
        (p1[0] + nx * r1, p1[1] + ny * r1),
        (p2[0] + nx * r2, p2[1] + ny * r2),
        (p2[0] - nx * r2, p2[1] - ny * r2),
        (p1[0] - nx * r1, p1[1] - ny * r1),
    ]
    return [ellipse_poly(p1, r1, r1), ellipse_poly(p2, r2, r2), quad]


class Mask:
    """Binärmaske im Supersampling-Raster."""

    def __init__(self):
        self.img = Image.new("L", (W * S, H * S), 0)
        self.draw = ImageDraw.Draw(self.img)

    def poly(self, pts):
        self.draw.polygon([(x * S, y * S) for x, y in pts], fill=255)
        return self

    def polys(self, polys):
        for p in polys:
            self.poly(p)
        return self

    def arr(self):
        return np.array(self.img) > 127


def outline_of(mask, width=OUTLINE):
    dist = ndimage.distance_transform_edt(~mask)
    return dist <= width * S


def ring_of(mask, width):
    """Innenkante einer Maske (für weiche Trennlinien)."""
    inner = ndimage.distance_transform_edt(mask)
    return mask & (inner <= width * S)


class Canvas:
    def __init__(self):
        self.px = np.zeros((H * S, W * S, 4), dtype=np.float32)

    def paint(self, mask, color, alpha=1.0):
        col = np.array(color, dtype=np.float32) / 255.0
        a = col[3] * alpha
        m = mask.astype(np.float32) * a
        for ch in range(3):
            self.px[..., ch] = self.px[..., ch] * (1 - m) + col[ch] * m
        self.px[..., 3] = self.px[..., 3] * (1 - m) + m

    def sticker(self, mask, fill, outline=True):
        if outline:
            self.paint(outline_of(mask), C_OUT)
        self.paint(mask, fill)

    def image(self):
        rgba = np.clip(self.px * 255.0, 0, 255).astype(np.uint8)
        big = Image.fromarray(rgba, "RGBA").convert("RGBa")
        return big.resize((W, H), Image.BOX).convert("RGBA")


def ear_poly(hp, base, tilt, k):
    """Großes, breites Stehohr mit abgerundeter Spitze (Billys Fledermausohren)."""
    shape = [(-13, 2), (-17, -14), (-16, -30), (-11, -42), (-5, -47), (0, -45),
             (6, -34), (11, -18), (12, -4), (9, 2)]
    return [hp(add(base, rot((x * k, y * k), tilt))) for x, y in shape]


# --------------------------------------------------------------------------- Pose

@dataclass
class Leg:
    angles: tuple            # Segmentwinkel (0 = nach unten, + = nach vorn)
    lengths: tuple
    radii: tuple             # Radius am Gelenk je Segment + Endradius


@dataclass
class Pose:
    hip: tuple = (112.0, 133.0)
    body: float = 0.0          # Körperwinkel, negativ = Vorderteil hoch
    neck: float = -0.9         # absolute Halsrichtung (Winkel zur +x-Achse)
    head: float = 0.0          # Kopfneigung, positiv = Schnauze nach unten
    jaw: float = 0.0           # Maulöffnung (rad)
    tongue: bool = False
    eyes_closed: bool = False
    ear_tilt: float = 0.0      # Ohrwinkel (Zucken)
    tail: float = -2.85        # Startwinkel der Rute (absolut, zur +x-Achse)
    tail_curl: float = 0.16    # Krümmung pro Segment
    front_near: Leg = None
    front_far: Leg = None
    hind_near: Leg = None
    hind_far: Leg = None
    ground_snap: bool = True
    breathe: float = 0.0       # 0..1 Brustkorb
    lift: float = 0.0          # Sprunghöhe über dem Boden (nach dem Aufsetzen)
    far_ear_tilt: float | None = None
    belly: bool = False        # liegt: Brust statt Pfoten auf den Boden setzen
    extra: dict = field(default_factory=dict)


FRONT_LEN = (38, 40)
FRONT_RAD = (10, 7, 6.5)
HIND_LEN = (32, 34, 26)
HIND_RAD = (13, 8, 6.5, 6)


def front(a1, a2):
    return Leg((a1, a2), FRONT_LEN, FRONT_RAD)


def hind(a1, a2, a3):
    return Leg((a1, a2, a3), HIND_LEN, HIND_RAD)


STAND_FRONT = front(0.02, 0.0)
STAND_HIND = hind(0.45, -0.52, 0.12)


# --------------------------------------------------------------------------- Rendering

def body_pt(pose, local):
    return add(pose.hip, rot(local, pose.body))


def leg_points(joint, leg: Leg):
    pts = [joint]
    p = joint
    for a, ln in zip(leg.angles, leg.lengths):
        d = down(a)
        p = (p[0] + d[0] * ln, p[1] + d[1] * ln)
        pts.append(p)
    return pts


def leg_polys(joint, leg: Leg):
    pts = leg_points(joint, leg)
    polys = []
    for i in range(len(pts) - 1):
        polys += capsule_polys(pts[i], pts[i + 1], leg.radii[i], leg.radii[i + 1])
    paw = pts[-1]
    polys.append(ellipse_poly((paw[0] + 5, paw[1] + 1), 9, 5.5))
    return polys, pts


def paw_bottom(joint, leg):
    return leg_points(joint, leg)[-1][1] + 6.5


def joints(pose):
    return {
        "shoulder": body_pt(pose, (92, 6)),
        "hip": body_pt(pose, (0, 0)),
        "neck": body_pt(pose, (100, -22)),
        "tail": body_pt(pose, (-26, -24)),
    }


def snap_to_ground(pose):
    j = joints(pose)
    lows = [
        paw_bottom(j["shoulder"], pose.front_near),
        paw_bottom(j["shoulder"], pose.front_far),
        paw_bottom(j["hip"], pose.hind_near),
        paw_bottom(j["hip"], pose.hind_far),
    ]
    dy = GROUND - max(lows)
    return replace(pose, hip=(pose.hip[0], pose.hip[1] + dy))


def head_frame(pose):
    j = joints(pose)
    center = add(j["neck"], (44 * math.cos(pose.neck), 44 * math.sin(pose.neck)))
    return center, pose.head


def head_pt(pose, local):
    c, a = head_frame(pose)
    return add(c, rot(local, a))


def resolve(pose: Pose) -> Pose:
    """Setzt die Pose auf den Boden (Pfoten oder Bauch) und wendet den Sprung an."""
    if pose.belly:
        chest_bottom = body_pt(pose, (92, 20 + pose.breathe))[1]
        pose = replace(pose, hip=(pose.hip[0], pose.hip[1] + GROUND - 2 - chest_bottom))
    elif pose.ground_snap:
        pose = snap_to_ground(pose)
    return replace(pose, hip=(pose.hip[0], pose.hip[1] - pose.lift), ground_snap=False, belly=False, lift=0.0)


def render(pose: Pose):
    lift = pose.lift
    pose = resolve(pose)
    cv = Canvas()
    j = joints(pose)
    far_offset = (7, -3)  # entfernte Beine leicht versetzt

    # Schatten
    sx = (j["hip"][0] + j["shoulder"][0]) / 2
    k = max(0.55, 1 - lift / 40)
    shadow = Mask().poly(ellipse_poly((sx, GROUND - 1), 92 * k, 9 * k)).arr()
    cv.paint(shadow, (0, 0, 0, 255), alpha=0.14 * k)

    # Entfernte Beine
    for joint, leg in ((j["hip"], pose.hind_far), (j["shoulder"], pose.front_far)):
        polys, _ = leg_polys(add(joint, far_offset), leg)
        cv.sticker(Mask().polys(polys).arr(), C_SHADE)

    # Rute
    tail = Mask()
    p = j["tail"]
    ang = pose.tail
    r = 6.2
    for i in range(9):
        q = add(p, (9 * math.cos(ang), 9 * math.sin(ang)))
        r2 = max(2.4, r - 0.45)
        tail.polys(capsule_polys(p, q, r, r2))
        p, r = q, r2
        ang += pose.tail_curl
    cv.sticker(tail.arr(), C_WHITE)

    # Kopfgeometrie
    hc, ha = head_frame(pose)

    def hp(local):
        return add(hc, rot(local, ha))

    tilt = pose.ear_tilt
    far_tilt = pose.far_ear_tilt if pose.far_ear_tilt is not None else tilt - 0.12
    cv.sticker(Mask().poly(ear_poly(hp, (0, -12), far_tilt, 1.0)).arr(), C_TAN_DARK)

    # Hauptkörper: Rumpf, Hals, Kopf, nahe Beine
    br = pose.breathe
    torso = Mask()
    torso.poly(ellipse_poly(body_pt(pose, (-2, -14)), 30, 28, pose.body))
    torso.poly(ellipse_poly(body_pt(pose, (48, -16)), 58, 23 + br, pose.body))
    torso.poly(ellipse_poly(body_pt(pose, (92, -10)), 28, 30 + br, pose.body))
    torso_m = torso.arr()

    neck_m = Mask().polys(capsule_polys(j["neck"], hc, 18, 13)).arr()

    jaw_ang = pose.jaw
    skull = Mask().poly(ellipse_poly(hc, 24, 19.5, ha))
    skull.polys(capsule_polys(hp((6, 3)), hp((44, 7)), 13, 6.5))
    jaw_pivot = (8, 11)
    jaw_tip = add(jaw_pivot, rot((30, 3), jaw_ang))
    jaw = Mask().polys(capsule_polys(hp(jaw_pivot), hp(jaw_tip), 8, 4.5))
    head_m = skull.arr() | jaw.arr()

    near_front_polys, nf_pts = leg_polys(j["shoulder"], pose.front_near)
    near_hind_polys, nh_pts = leg_polys(j["hip"], pose.hind_near)
    nf_m = Mask().polys(near_front_polys).arr()
    nh_m = Mask().polys(near_hind_polys).arr()

    main = torso_m | neck_m | head_m | nf_m | nh_m
    cv.paint(outline_of(main), C_OUT)
    cv.paint(main, C_WHITE)

    # Maulinneres, wenn geöffnet
    if jaw_ang > 0.05:
        mouth = Mask().poly([hp((6, 9)), hp((42, 10)), hp(jaw_tip), hp((10, 14))]).arr()
        cv.paint(mouth & ~jaw.arr(), C_MOUTH)
        cv.paint(jaw.arr(), C_WHITE)
        cv.paint(ring_of(jaw.arr(), 1.2), C_LINE)
        if pose.tongue:
            tongue = Mask().poly(ellipse_poly(hp(add(jaw_tip, (-7, 3))), 8, 5, ha + jaw_ang + 0.5)).arr()
            cv.paint(outline_of(tongue, 1.4) & ~jaw.arr(), C_OUT)
            cv.paint(tongue, C_TONGUE)

    # Fellplatten (hellbraun), auf den Rumpf begrenzt
    saddle = Mask()
    saddle.poly(ellipse_poly(body_pt(pose, (30, -32)), 44, 15, pose.body - 0.05))
    saddle.poly(ellipse_poly(body_pt(pose, (-6, -20)), 23, 19, pose.body))
    cv.paint(saddle.arr() & torso_m & ~nh_m, C_TAN)
    cv.paint(Mask().poly(ellipse_poly(body_pt(pose, (-6, -20)), 23, 19, pose.body)).arr() & nh_m, C_TAN)

    # Kopfzeichnung: brauner Oberkopf, Augenfleck, weiße Blesse
    head_tan = Mask()
    head_tan.poly(ellipse_poly(hp((-8, -6)), 18, 15, ha))
    head_tan.poly(ellipse_poly(hp((13, -4)), 10, 8, ha))
    cv.paint(head_tan.arr() & skull.arr(), C_TAN)
    blaze = Mask().polys(capsule_polys(hp((4, -18)), hp((30, -4)), 3.5, 5)).arr()
    cv.paint(blaze & skull.arr(), C_WHITE)
    freckles = Mask()
    for fx, fy in ((26, 2), (31, 5), (29, -1), (35, 3)):
        freckles.poly(ellipse_poly(hp((fx, fy)), 1.1, 1.1))
    cv.paint(freckles.arr(), C_TAN_DARK, alpha=0.7)

    # Weiche Trennlinien zwischen überlappenden Teilen
    for part, width in ((head_m, 1.3),):
        others = main & ~part
        edge = ring_of(part, width) & ndimage.binary_dilation(others, iterations=int(1.5 * S))
        cv.paint(edge, C_LINE)

    # Nahes Ohr
    cv.sticker(Mask().poly(ear_poly(hp, (-8, -12), tilt, 1.0)).arr(), C_TAN)
    cv.paint(Mask().poly(ear_poly(hp, (-8, -14), tilt, 0.62)).arr(), C_EAR_IN)

    # Auge
    eye_c = hp((14, -3))
    if pose.eyes_closed:
        lid = Mask().polys(capsule_polys(hp((8, -2)), hp((20, -1)), 1.4, 1.4)).arr()
        cv.paint(lid, C_OUT)
    else:
        cv.paint(Mask().poly(ellipse_poly(eye_c, 6.2, 5.6, ha)).arr(), C_OUT)
        cv.paint(Mask().poly(ellipse_poly(eye_c, 5.0, 4.5, ha)).arr(), C_EYE)
        cv.paint(Mask().poly(ellipse_poly(hp((15.5, -3)), 2.9, 3.2, ha)).arr(), C_PUPIL)
        cv.paint(Mask().poly(ellipse_poly(hp((17, -4.8)), 1.3, 1.3)).arr(), (255, 255, 255, 255))

    # Nase
    cv.paint(Mask().poly(ellipse_poly(hp((45, 5)), 6.5, 5.2, ha)).arr(), C_OUT)
    cv.paint(Mask().poly(ellipse_poly(hp((45, 5)), 5.3, 4.1, ha)).arr(), C_NOSE)
    cv.paint(Mask().poly(ellipse_poly(hp((46.5, 3.5)), 1.6, 1.0, ha)).arr(), (255, 230, 225, 255), alpha=0.8)

    anchors = {
        "mouth": hp(add(jaw_pivot, rot((24, -1), jaw_ang / 2))),
        "nose": hp((50, 5)),
        "head": hp((0, -30)),
    }
    return cv.image(), anchors


# --------------------------------------------------------------------------- Animationen

TAU = 2 * math.pi


def ease(t):
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_leg(a: Leg, b: Leg, t):
    return Leg(tuple(lerp(x, y, t) for x, y in zip(a.angles, b.angles)), a.lengths, a.radii)


def lerp_pose(a: Pose, b: Pose, t: float) -> Pose:
    """Überblendet zwei (bereits aufgesetzte) Posen."""
    a, b = resolve(a), resolve(b)
    return Pose(
        hip=(lerp(a.hip[0], b.hip[0], t), lerp(a.hip[1], b.hip[1], t)),
        body=lerp(a.body, b.body, t), neck=lerp(a.neck, b.neck, t), head=lerp(a.head, b.head, t),
        jaw=lerp(a.jaw, b.jaw, t), tongue=b.tongue if t >= 0.5 else a.tongue,
        eyes_closed=b.eyes_closed if t >= 0.5 else a.eyes_closed,
        ear_tilt=lerp(a.ear_tilt, b.ear_tilt, t),
        tail=lerp(a.tail, b.tail, t), tail_curl=lerp(a.tail_curl, b.tail_curl, t),
        front_near=lerp_leg(a.front_near, b.front_near, t), front_far=lerp_leg(a.front_far, b.front_far, t),
        hind_near=lerp_leg(a.hind_near, b.hind_near, t), hind_far=lerp_leg(a.hind_far, b.hind_far, t),
        breathe=lerp(a.breathe, b.breathe, t), ground_snap=False,
    )


def blink(i, at):
    return i in at


# ---- Grundposen -------------------------------------------------------------

def walk_leg_angles(p, amp):
    """Schrittzyklus: 60 % Standphase, 40 % Schwungphase mit Anheben."""
    stance = 0.6
    if p < stance:
        return amp * (1 - 2 * p / stance), 0.0
    q = (p - stance) / (1 - stance)
    return -amp + 2 * amp * q, math.sin(math.pi * q)


def walk_pose(t, amp=0.38, carry=False):
    offsets = {"hind_near": 0.0, "front_near": 0.25, "hind_far": 0.5, "front_far": 0.75}
    legs = {}
    for name, off in offsets.items():
        a, lift = walk_leg_angles((t + off) % 1.0, amp)
        if name.startswith("front"):
            legs[name] = front(a * 0.85, a * 0.85 - lift * 1.1)
        else:
            legs[name] = hind(0.45 + a * 0.8, -0.52 + a * 0.45 + lift * 0.35, 0.12 + a * 0.6 - lift * 0.9)
    bob = math.sin(2 * TAU * t)
    return Pose(
        body=0.02 * bob,
        neck=-0.85 + 0.05 * bob,
        head=(-0.04 if carry else 0.08) + 0.03 * math.sin(2 * TAU * t + 0.6),
        jaw=0.22 if carry else 0.0,
        tail=-2.75 + 0.22 * math.sin(TAU * t),
        tail_curl=0.14,
        ear_tilt=-0.1 - 0.12 * math.sin(2 * TAU * t - 0.9),   # Ohren wippen nach
        **legs,
    )


def stand_pose(wag=0.0, eyes_closed=False, ear=0.0, breathe=0.0, **kw):
    base = dict(
        neck=-0.95, head=0.02, tail=-2.2 + 0.45 * wag, tail_curl=0.22, ear_tilt=ear,
        eyes_closed=eyes_closed, breathe=breathe,
        front_near=STAND_FRONT, front_far=front(-0.05, -0.02),
        hind_near=STAND_HIND, hind_far=hind(0.38, -0.55, 0.1),
    )
    base.update(kw)
    return Pose(**base)


SIT_HIND = hind(1.25, -1.62, 1.5)


def sit_pose(wag=0.0, jaw=0.0, tongue=False, head=-0.02, neck=-1.3, eyes_closed=False, ear=0.0, breathe=0.0, **kw):
    base = dict(
        hip=(128, 200), body=-0.8, neck=neck, head=head, jaw=jaw, tongue=tongue,
        tail=-3.2 + 0.3 * wag, tail_curl=-0.06, eyes_closed=eyes_closed, ear_tilt=ear, breathe=breathe,
        front_near=front(0.06, 0.0), front_far=front(0.0, -0.02),
        hind_near=SIT_HIND, hind_far=hind(1.2, -1.6, 1.5),
    )
    base.update(kw)
    return Pose(**base)


LIE_FRONT = front(1.0, 1.57)
LIE_HIND = hind(1.35, -1.5, 1.55)


def lie_pose(breathe=0.0, sleep=False, eyes_closed=False, tail=3.0, ear=0.0):
    return Pose(
        hip=(110, 202), body=0.0, neck=0.05 if sleep else -0.7, head=0.18 if sleep else 0.05,
        eyes_closed=sleep or eyes_closed, ear_tilt=(-0.25 if sleep else ear),
        tail=2.9 if sleep else tail, tail_curl=-0.06 if sleep else -0.04, breathe=breathe, belly=True,
        front_near=LIE_FRONT, front_far=front(1.05, 1.57),
        hind_near=LIE_HIND, hind_far=hind(1.3, -1.5, 1.55),
    )


def sniff_pose(t, jaw=0.0):
    wob = math.sin(TAU * t)
    return stand_pose(
        wag=0.4 * math.sin(2 * TAU * t), neck=0.55 + 0.08 * wob, head=1.05 + 0.1 * math.sin(2 * TAU * t),
        jaw=jaw, ear=0.1 * wob, front_near=front(0.08, 0.02), tail=-2.3 + 0.25 * wob,
    )


def bow_pose(jaw=0.0, eyes_closed=False, head=0.1):
    """Vorderkörper tief, Po hoch – Strecken wie ein Windhund."""
    return Pose(
        body=0.34, neck=-0.3, head=head, jaw=jaw, eyes_closed=eyes_closed, tail=-1.9, tail_curl=0.2,
        front_near=front(1.15, 1.5), front_far=front(1.05, 1.45),
        hind_near=hind(0.25, -0.45, 0.1), hind_far=hind(0.2, -0.5, 0.08),
    )


# ---- Galopp (Podenco = Windhund) --------------------------------------------

GALLOP = [
    dict(fn=(0.95, 1.25), ff=(0.8, 1.1), hn=(-0.7, -1.0, -0.7), hf=(-0.55, -0.9, -0.6), body=0.0, lift=9, neck=-0.55),
    dict(fn=(0.35, 0.3), ff=(0.6, 0.7), hn=(-0.2, -0.9, -0.3), hf=(-0.4, -1.0, -0.5), body=0.04, lift=0, neck=-0.5),
    dict(fn=(-0.45, -0.7), ff=(-0.1, -0.2), hn=(0.6, -0.6, 0.3), hf=(0.4, -0.7, 0.0), body=0.02, lift=0, neck=-0.6),
    dict(fn=(-0.9, -1.6), ff=(-0.75, -1.4), hn=(1.25, -0.5, 0.9), hf=(1.1, -0.6, 0.7), body=-0.06, lift=7, neck=-0.7),
    dict(fn=(-0.2, -1.2), ff=(-0.4, -1.3), hn=(0.9, -0.3, 0.25), hf=(1.0, -0.4, 0.4), body=-0.04, lift=0, neck=-0.65),
    dict(fn=(0.4, -0.3), ff=(0.2, -0.6), hn=(0.1, -0.8, -0.2), hf=(0.4, -0.6, 0.0), body=-0.02, lift=0, neck=-0.6),
]


def gallop_pose(t):
    x = t * len(GALLOP)
    i = int(x) % len(GALLOP)
    f = x - int(x)
    a, b = GALLOP[i], GALLOP[(i + 1) % len(GALLOP)]
    mix = lambda k: tuple(lerp(u, v, f) for u, v in zip(a[k], b[k]))
    return Pose(
        body=lerp(a["body"], b["body"], f), neck=lerp(a["neck"], b["neck"], f), head=0.12,
        lift=lerp(a["lift"], b["lift"], f), ear_tilt=-0.6, far_ear_tilt=-0.7,
        tail=-3.05 + 0.12 * math.sin(TAU * t), tail_curl=0.05,
        front_near=front(*mix("fn")), front_far=front(*mix("ff")),
        hind_near=hind(*mix("hn")), hind_far=hind(*mix("hf")),
    )


# ---- Sequenzen --------------------------------------------------------------

def seq(n, fn):
    return [fn(i / n, i) for i in range(n)]


def transition(a: Pose, b: Pose, n=6):
    return [lerp_pose(a, b, ease((i + 1) / n)) for i in range(n)]


def keyframes(poses, per=3):
    out = []
    for a, b in zip(poses, poses[1:]):
        out += [lerp_pose(a, b, ease(i / per)) for i in range(per)]
    return out + [poses[-1]]


STAND = stand_pose()
SIT = sit_pose()
LIE = lie_pose()
SNIFF = sniff_pose(0.0)
CARRY = walk_pose(0.0, carry=True)

ANIMATIONS = {
    # Laufen & Tragen: 12 Bilder, Kopf und Ohren wippen mit
    "walk": seq(12, lambda t, i: walk_pose(t)),
    "carry": seq(12, lambda t, i: walk_pose(t, carry=True)),
    # Galopp für Zoomies
    "run": seq(8, lambda t, i: gallop_pose(t)),
    # Ruhen mit Atmen, Blinzeln, Ohrzucken, Rutenwedeln
    "stand": seq(16, lambda t, i: stand_pose(
        wag=math.sin(2 * TAU * t), breathe=0.8 * math.sin(TAU * t),
        eyes_closed=blink(i, (11,)), ear=0.25 if i in (5, 6) else 0.0)),
    "sit": seq(16, lambda t, i: sit_pose(
        wag=0.6 * math.sin(2 * TAU * t), breathe=0.8 * math.sin(TAU * t),
        eyes_closed=blink(i, (9,)), ear=-0.2 if i in (3, 4) else 0.0)),
    "happy": seq(8, lambda t, i: sit_pose(
        wag=1.6 * math.sin(2 * TAU * t), jaw=0.35, tongue=True, head=-0.1 + 0.05 * math.sin(2 * TAU * t))),
    "hop": seq(8, lambda t, i: stand_pose(
        wag=1.8 * math.sin(2 * TAU * t), jaw=0.3, tongue=True, head=-0.08,
        lift=14 * max(0.0, math.sin(TAU * t)), ear=-0.3 * math.sin(TAU * t),
        front_near=front(0.02 + 0.5 * max(0.0, math.sin(TAU * t)), -0.6 * max(0.0, math.sin(TAU * t))),
        front_far=front(0.3 * max(0.0, math.sin(TAU * t)), -0.5 * max(0.0, math.sin(TAU * t))))),
    "bark": [sit_pose(jaw=j, head=h, neck=-1.4, ear=e) for j, h, e in
             ((0.05, -0.2, 0.0), (0.5, -0.3, -0.15), (0.6, -0.34, -0.2), (0.1, -0.22, 0.0))],
    "lie": seq(8, lambda t, i: lie_pose(breathe=1.2 * math.sin(TAU * t), eyes_closed=blink(i, (6,)),
                                         tail=3.0 + 0.08 * math.sin(TAU * t))),
    "sleep": seq(8, lambda t, i: lie_pose(breathe=1.6 * math.sin(TAU * t), sleep=True)),
    "sniff": seq(8, lambda t, i: sniff_pose(t)),
    # Kopf schief legen, wenn Billy zuhört
    "tilt": seq(8, lambda t, i: stand_pose(
        head=-0.28 * math.sin(math.pi * min(1.0, t * 1.4)), neck=-1.05,
        ear=-0.35 * math.sin(math.pi * min(1.0, t * 1.4)),
        far_ear_tilt=0.2 * math.sin(math.pi * min(1.0, t * 1.4)), wag=0.3 * math.sin(2 * TAU * t))),
    # Strecken und Gähnen nach dem Aufwachen
    "stretch": keyframes([STAND, bow_pose(), bow_pose(jaw=0.75, eyes_closed=True, head=-0.15),
                          bow_pose(), STAND], per=3),
    # Übergänge zwischen Haltungen
    "sitDown": transition(STAND, SIT),
    "standUp": transition(SIT, STAND),
    "lieDown": transition(SIT, LIE),
    "getUp": transition(LIE, SIT),
    # Datei aufnehmen und ablegen
    "pick": keyframes([replace(SNIFF, jaw=0.0), replace(SNIFF, jaw=0.45), replace(SNIFF, jaw=0.22), CARRY], per=2),
    "place": keyframes([CARRY, replace(SNIFF, jaw=0.22), replace(SNIFF, jaw=0.55), STAND], per=2),
    # hängt beim Hochheben mit der Maus
    "dangle": seq(4, lambda t, i: Pose(
        hip=(112, 124), lift=34, body=0.08, neck=-1.0, head=-0.05, ground_snap=False, ear_tilt=-0.35,
        jaw=0.25, tongue=True, tail=1.75 + 0.2 * math.sin(TAU * t), tail_curl=0.05,
        front_near=front(0.12 * math.sin(TAU * t), 0.05), front_far=front(-0.1 * math.sin(TAU * t), 0.0),
        hind_near=hind(0.15 - 0.12 * math.sin(TAU * t), -0.1, 0.05), hind_far=hind(0.1 + 0.1 * math.sin(TAU * t), -0.1, 0.0))),
}


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("*.png"):
        old.unlink()
    meta = {"frameSize": [W // 2, H // 2], "scale": 2, "groundY": GROUND / 2, "animations": {}}
    only = set(sys.argv[1:])
    for name, poses in ANIMATIONS.items():
        if only and name not in only:
            continue
        frames = []
        for i, pose in enumerate(poses):
            img, anchors = render(pose)
            fname = f"{name}_{i:02d}.png"
            img.save(OUT_DIR / fname, optimize=True)
            frames.append({
                "file": fname,
                "anchors": {k: [round(v[0] / 2, 1), round(v[1] / 2, 1)] for k, v in anchors.items()},
            })
        meta["animations"][name] = frames
        print(f"{name}: {len(frames)} Frames", flush=True)
    if not only:
        (OUT_DIR / "sprites.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()

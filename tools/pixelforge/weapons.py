"""Weapon shapes, used twice over.

The same vector-ish description draws both the tiny copy that rides a
character's hand in the sprite sheet and the 32x32 inventory icon, so a
weapon you picked up always looks like the one on screen.

All shapes are authored pointing UP with the grip at the canvas centre; the
rig rotates about that centre, which keeps the grip glued to the hand.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

from .core import Canvas, Ramp, RGBA, mix, shade, with_alpha
from . import palette as P


@dataclass
class WeaponStyle:
    metal: Ramp
    wood: Ramp
    accent: Ramp
    glow: RGBA | None = None


DEFAULT = WeaponStyle(P.R_STEEL, P.R_WOOD, P.R_GOLD)


def _haft(c: Canvas, x: float, y0: float, y1: float, style: WeaponStyle, w: float = 1.6) -> None:
    c.capsule((x, y0), (x, y1), w, w, style.wood.dark)
    c.capsule((x - 0.5, y0), (x - 0.5, y1), w * 0.55, w * 0.55, style.wood.core)


def _grip_wrap(c: Canvas, x: float, y0: float, y1: float, style: WeaponStyle | None = None) -> None:
    """Leather-wrapped grip; the material never varies, so style is optional."""
    c.capsule((x, y0), (x, y1), 1.7, 1.7, P.R_LEATHER.dark)
    for y in range(int(y0), int(y1) + 1, 2):
        c.hline(int(x - 1), int(x + 1), y, P.R_LEATHER.core)


def _blade(c: Canvas, x: float, base_y: float, tip_y: float, half_w: float, style: WeaponStyle) -> None:
    """Straight double-edged blade with a lit left edge and a fuller line."""
    c.polygon(
        [
            (x - half_w, base_y),
            (x + half_w, base_y),
            (x + half_w * 0.55, tip_y + 3),
            (x, tip_y),
            (x - half_w * 0.55, tip_y + 3),
        ],
        style.metal.dark,
    )
    c.polygon(
        [
            (x - half_w + 0.8, base_y - 1),
            (x + 0.2, base_y - 1),
            (x + 0.2, tip_y + 3),
            (x - half_w * 0.5 + 0.6, tip_y + 4),
        ],
        style.metal.core,
    )
    c.vline(int(x - half_w + 1), int(tip_y + 4), int(base_y - 2), style.metal.hi)


def _crescent(
    c: Canvas, cx: float, cy: float, radius: float, span: float, start: float,
    thickness: float, ramp: Ramp,
) -> None:
    steps = max(10, int(radius * 3))
    for i in range(steps + 1):
        a = math.radians(start + span * i / steps)
        taper = 1.0 - (i / steps) ** 2 * 0.75
        c.circle(cx + math.cos(a) * radius, cy + math.sin(a) * radius, thickness * taper, ramp.dark)
    for i in range(steps + 1):
        a = math.radians(start + span * i / steps)
        taper = 1.0 - (i / steps) ** 2 * 0.75
        c.circle(
            cx + math.cos(a) * (radius - 0.6) - 0.3,
            cy + math.sin(a) * (radius - 0.6) - 0.3,
            thickness * taper * 0.5,
            ramp.core,
        )


def _muzzle_flare(c: Canvas, x: float, y: float, col: RGBA) -> None:
    """A hot pixel at the bore — small on purpose, so it never inflates the
    icon's bounding box and shrinks the weapon."""
    c.blend(int(x), int(y + 1), with_alpha(col, 200))
    c.blend(int(x - 1), int(y + 1), with_alpha(col, 110))


# ---------------------------------------------------------------------------
# Individual shapes. cx/cy is the grip; the weapon reaches upward.
# ---------------------------------------------------------------------------
def _scythe(c, cx, cy, st, k):
    _haft(c, cx, cy + 9 * k, cy - 12 * k, st, 1.5 * k)
    _crescent(c, cx + 1 * k, cy - 12 * k, 9 * k, 155, -175, 1.9 * k, st.metal)
    c.circle(cx, cy - 11 * k, 1.8 * k, st.accent.core)


def _cleaver(c, cx, cy, st, k, big=False):
    w = (5.5 if big else 4.0) * k
    _grip_wrap(c, cx, cy + 6 * k, cy - 1 * k)
    c.polygon(
        [
            (cx - w * 0.5, cy - 2 * k),
            (cx + w, cy - 3 * k),
            (cx + w * 0.9, cy - 13 * k),
            (cx - w * 0.6, cy - 15 * k),
        ],
        st.metal.dark,
    )
    c.polygon(
        [
            (cx - w * 0.4, cy - 3 * k),
            (cx + w * 0.2, cy - 3.5 * k),
            (cx + w * 0.15, cy - 12.5 * k),
            (cx - w * 0.5, cy - 14 * k),
        ],
        st.metal.core,
    )
    c.line((cx + w * 0.85, cy - 4 * k), (cx + w * 0.8, cy - 12.5 * k), st.metal.hi)
    c.circle(cx + w * 0.6, cy - 14 * k, 1.2 * k, st.accent.core)


def _sword(c, cx, cy, st, k):
    _grip_wrap(c, cx, cy + 6 * k, cy + 1 * k)
    c.rect(int(cx - 4 * k), int(cy), int(8 * k), max(1, int(1.6 * k)), st.accent.dark)
    c.rect(int(cx - 3.5 * k), int(cy - 0.5), int(7 * k), 1, st.accent.core)
    _blade(c, cx, cy - 1 * k, cy - 17 * k, 2.2 * k, st)
    c.circle(cx, cy + 7 * k, 1.6 * k, st.accent.core)
    if st.glow:
        for i in range(6):
            c.blend(int(cx + 2 * k), int(cy - 4 * k - i * 2 * k), with_alpha(st.glow, 130 - i * 15))


def _dagger(c, cx, cy, st, k, wavy=False):
    _grip_wrap(c, cx, cy + 5 * k, cy + 1 * k)
    c.rect(int(cx - 2.5 * k), int(cy), int(5 * k), 1, st.accent.core)
    if wavy:
        prev = (cx, cy - 1 * k)
        for i in range(1, 9):
            t = i / 8
            nx = cx + math.sin(t * math.pi * 2.2) * 1.8 * k
            ny = cy - 1 * k - t * 11 * k
            c.capsule(prev, (nx, ny), 1.7 * k, 1.2 * k, st.metal.dark)
            c.capsule((prev[0] - 0.5, prev[1]), (nx - 0.5, ny), 0.9 * k, 0.6 * k, st.metal.core)
            prev = (nx, ny)
    else:
        _blade(c, cx, cy - 1 * k, cy - 12 * k, 1.7 * k, st)


def _twin_daggers(c, cx, cy, st, k):
    for flip, off in ((1, -3.0 * k), (1, 3.0 * k)):
        _blade(c, cx + off, cy + 2 * k, cy - 10 * k, 1.4 * k, st)
        c.rect(int(cx + off - 2 * k), int(cy + 2 * k), int(4 * k), 1, st.accent.core)
    _grip_wrap(c, cx, cy + 6 * k, cy + 3 * k)


def _pistol(c, cx, cy, st, k, long=False, revolver=False):
    barrel = (11 if long else 7) * k
    _grip_wrap(c, cx, cy + 5 * k, cy + 1 * k)
    c.polygon(
        [(cx - 2 * k, cy + 2 * k), (cx + 2.5 * k, cy + 2 * k), (cx + 2 * k, cy - 2 * k), (cx - 2 * k, cy - 2 * k)],
        st.metal.dark,
    )
    c.capsule((cx, cy - 2 * k), (cx, cy - barrel), 1.5 * k, 1.2 * k, st.metal.dark)
    c.capsule((cx - 0.5, cy - 2 * k), (cx - 0.5, cy - barrel), 0.8 * k, 0.6 * k, st.metal.core)
    if revolver:
        c.circle(cx, cy - 1.5 * k, 2.2 * k, st.metal.core)
        c.circle(cx, cy - 1.5 * k, 1.0 * k, st.metal.dark)
        for i in range(5):
            a = i / 5 * math.tau
            c.set(int(cx + math.cos(a) * 1.6 * k), int(cy - 1.5 * k + math.sin(a) * 1.6 * k), P.VOID)
    else:
        c.polygon([(cx + 2 * k, cy - 1 * k), (cx + 4 * k, cy - 3 * k), (cx + 2 * k, cy - 3.5 * k)], st.accent.core)
    _muzzle_flare(c, cx, cy - barrel - 1, st.glow or P.AMBER)


def _long_gun(c, cx, cy, st, k, flared=False, stake=False):
    _grip_wrap(c, cx, cy + 6 * k, cy + 2 * k)
    c.polygon(
        [(cx - 2 * k, cy + 8 * k), (cx + 2 * k, cy + 6 * k), (cx + 2 * k, cy - 1 * k), (cx - 2.5 * k, cy + 1 * k)],
        st.wood.dark,
    )
    c.polygon(
        [(cx - 1 * k, cy + 7 * k), (cx + 1 * k, cy + 6 * k), (cx + 1 * k, cy), (cx - 1.5 * k, cy + 1 * k)],
        st.wood.core,
    )
    tip = cy - 15 * k
    c.capsule((cx, cy - 1 * k), (cx, tip), 1.8 * k, 1.5 * k, st.metal.dark)
    c.capsule((cx - 0.6, cy - 1 * k), (cx - 0.6, tip), 0.9 * k, 0.7 * k, st.metal.core)
    if flared:
        c.polygon([(cx - 4 * k, tip - 1), (cx + 4 * k, tip - 1), (cx + 1.6 * k, tip + 4 * k), (cx - 1.6 * k, tip + 4 * k)], st.metal.dark)
        c.polygon([(cx - 3 * k, tip), (cx + 1 * k, tip), (cx + 0.8 * k, tip + 3 * k), (cx - 1.2 * k, tip + 3 * k)], st.metal.core)
    if stake:
        c.polygon([(cx - 1.4 * k, tip + 5 * k), (cx + 1.4 * k, tip + 5 * k), (cx, tip - 4 * k)], P.R_WOOD.light)
    c.rect(int(cx - 2.5 * k), int(cy + 1 * k), int(5 * k), max(1, int(1.4 * k)), st.accent.dark)
    # Lock plate + hammer + fore-sight: without these a musket is a grey tube.
    c.circle(cx + 2 * k, cy + 1.5 * k, 1.4 * k, st.accent.core)
    c.polygon([(cx + 1.5 * k, cy), (cx + 4 * k, cy - 2.5 * k), (cx + 2 * k, cy - 3 * k)], st.metal.core)
    c.rect(int(cx - 1), int(tip + 2 * k), 2, max(1, int(1.5 * k)), st.metal.hi)
    for band in range(2):
        c.hline(int(cx - 2 * k), int(cx + 2 * k), int(cy - 5 * k - band * 4 * k), st.accent.dark)
    _muzzle_flare(c, cx, tip - 1, st.glow or P.AMBER)


def _bow(c, cx, cy, st, k, crossbow=False):
    if crossbow:
        c.capsule((cx, cy + 5 * k), (cx, cy - 9 * k), 1.5 * k, 1.2 * k, st.wood.dark)
        for flip in (-1, 1):
            c.capsule((cx, cy - 6 * k), (cx + flip * 8 * k, cy - 4 * k), 1.4 * k, 0.8 * k, st.wood.core)
        c.line((cx - 8 * k, cy - 4 * k), (cx + 8 * k, cy - 4 * k), P.BONE)
        c.polygon([(cx - 1.2 * k, cy - 9 * k), (cx + 1.2 * k, cy - 9 * k), (cx, cy - 14 * k)], st.metal.core)
        _grip_wrap(c, cx, cy + 5 * k, cy + 2 * k)
    else:
        steps = 20
        arc = 150.0
        bx = cx - 3 * k
        for i in range(steps + 1):
            a = math.radians(-arc / 2 - 90 + arc * i / steps)
            taper = 1.0 - abs(i / steps - 0.5) * 0.5
            c.circle(bx - math.sin(a) * 9 * k, cy + math.cos(a) * 12 * k, 1.6 * k * taper, st.wood.dark)
        for i in range(steps + 1):
            a = math.radians(-arc / 2 - 90 + arc * i / steps)
            c.circle(bx - math.sin(a) * 9 * k - 0.5, cy + math.cos(a) * 12 * k - 0.5, 0.8 * k, st.wood.core)
        top = (bx - math.sin(math.radians(-arc / 2 - 90)) * 9 * k, cy + math.cos(math.radians(-arc / 2 - 90)) * 12 * k)
        bot = (bx - math.sin(math.radians(arc / 2 - 90)) * 9 * k, cy + math.cos(math.radians(arc / 2 - 90)) * 12 * k)
        c.line(top, bot, P.BONE)
        # Nocked arrow, so the icon reads as "bow" and not "bracket".
        c.capsule((bx + 1 * k, cy), (bx + 11 * k, cy), 0.9 * k, 0.6 * k, st.wood.core)
        c.polygon([(bx + 11 * k, cy - 1.6 * k), (bx + 15 * k, cy), (bx + 11 * k, cy + 1.6 * k)], st.accent.core)


def _staff(c, cx, cy, st, k):
    _haft(c, cx, cy + 10 * k, cy - 10 * k, st, 1.5 * k)
    glow = st.glow or P.SPECTRAL
    c.ellipse_blend(cx, cy - 13 * k, 5 * k, 5 * k, with_alpha(glow, 60))
    c.circle(cx, cy - 13 * k, 2.8 * k, shade(glow, -0.4))
    c.circle(cx - 0.5, cy - 13.5 * k, 1.8 * k, glow)
    c.set(int(cx - 1), int(cy - 14 * k), (255, 255, 255, 255))
    for flip in (-1, 1):
        c.capsule((cx + flip * 1.5 * k, cy - 10 * k), (cx + flip * 4 * k, cy - 15 * k), 1.2 * k, 0.5, P.R_BONE.dark)


def _book(c, cx, cy, st, k):
    c.polygon([(cx - 6 * k, cy - 5 * k), (cx + 6 * k, cy - 5 * k), (cx + 6 * k, cy + 4 * k), (cx - 6 * k, cy + 4 * k)], P.R_LEATHER.dark)
    c.polygon([(cx - 5 * k, cy - 4 * k), (cx + 5 * k, cy - 4 * k), (cx + 5 * k, cy + 3 * k), (cx - 5 * k, cy + 3 * k)], P.R_LEATHER.core)
    c.vline(int(cx), int(cy - 5 * k), int(cy + 4 * k), P.R_LEATHER.dark)
    c.rect(int(cx - 4.5 * k), int(cy - 3 * k), int(4 * k), int(5 * k), P.PARCHMENT)
    c.rect(int(cx + 0.5 * k), int(cy - 3 * k), int(4 * k), int(5 * k), P.BONE)
    glow = st.glow or P.SPECTRAL
    for i in range(4):
        c.blend(int(cx - 1 + i), int(cy - 7 * k - i), with_alpha(glow, 170 - i * 30))
    c.circle(cx, cy - 5.5 * k, 1.2 * k, glow)


def _bell(c, cx, cy, st, k):
    _haft(c, cx, cy + 8 * k, cy - 6 * k, st, 1.2 * k)
    c.polygon([(cx - 5 * k, cy - 1 * k), (cx + 5 * k, cy - 1 * k), (cx + 3 * k, cy - 9 * k), (cx - 3 * k, cy - 9 * k)], st.metal.dark)
    c.polygon([(cx - 3.5 * k, cy - 2 * k), (cx + 0.5 * k, cy - 2 * k), (cx + 0.5 * k, cy - 8 * k), (cx - 2 * k, cy - 8 * k)], st.metal.core)
    c.hline(int(cx - 5 * k), int(cx + 5 * k), int(cy), st.accent.core)
    c.circle(cx, cy + 1.5 * k, 1.4 * k, st.accent.dark)
    for i in range(3):
        c.blend(int(cx + 6 * k + i), int(cy - 5 * k - i), with_alpha(P.CANDLE, 150 - i * 40))


def _lantern(c, cx, cy, st, k):
    c.capsule((cx, cy + 4 * k), (cx, cy - 2 * k), 1.0 * k, 1.0 * k, st.metal.dark)
    c.polygon([(cx - 4 * k, cy - 2 * k), (cx + 4 * k, cy - 2 * k), (cx + 3 * k, cy - 11 * k), (cx - 3 * k, cy - 11 * k)], st.metal.dark)
    glow = st.glow or P.MOONLIGHT
    c.polygon([(cx - 2.6 * k, cy - 3 * k), (cx + 2.6 * k, cy - 3 * k), (cx + 2 * k, cy - 10 * k), (cx - 2 * k, cy - 10 * k)], shade(glow, -0.35))
    c.ellipse(cx, cy - 6.5 * k, 1.6 * k, 2.4 * k, glow)
    c.ellipse_blend(cx, cy - 6.5 * k, 5 * k, 5 * k, with_alpha(glow, 34))
    c.hline(int(cx - 4 * k), int(cx + 4 * k), int(cy - 11 * k), st.metal.core)
    for flip in (-1, 1):
        c.capsule((cx + flip * 3 * k, cy - 11 * k), (cx, cy - 15 * k), 0.9 * k, 0.9 * k, st.metal.core)


def _flask(c, cx, cy, st, k, fire=False):
    liquid = P.EMBER if fire else P.MOONLIGHT
    c.polygon([(cx - 4 * k, cy + 3 * k), (cx + 4 * k, cy + 3 * k), (cx + 3 * k, cy - 4 * k), (cx - 3 * k, cy - 4 * k)], shade(P.SMOKE, -0.5))
    c.polygon([(cx - 3 * k, cy + 2 * k), (cx + 3 * k, cy + 2 * k), (cx + 2.4 * k, cy - 1 * k), (cx - 2.4 * k, cy - 1 * k)], shade(liquid, -0.3))
    c.polygon([(cx - 2.4 * k, cy + 1 * k), (cx + 1 * k, cy + 1 * k), (cx + 1 * k, cy - 0.5 * k), (cx - 2.4 * k, cy - 0.5 * k)], liquid)
    c.rect(int(cx - 1.5 * k), int(cy - 7 * k), int(3 * k), int(3 * k), shade(P.SMOKE, -0.4))
    c.rect(int(cx - 2 * k), int(cy - 9 * k), int(4 * k), int(2 * k), P.R_WOOD.core)
    c.set(int(cx - 2 * k), int(cy), P.PARCHMENT)
    if fire:
        for i in range(4):
            c.blend(int(cx + (i % 2) - 1), int(cy - 11 * k - i), with_alpha(P.EMBER, 180 - i * 35))
    c.ellipse_blend(cx, cy, 4.5 * k, 4.5 * k, with_alpha(liquid, 26))


def _whip(c, cx, cy, st, k):
    _grip_wrap(c, cx, cy + 6 * k, cy + 1 * k)
    prev = (cx, cy)
    for i in range(1, 13):
        t = i / 12
        nx = cx + math.sin(t * math.pi * 1.8) * 6.5 * k * t
        ny = cy - t * 15 * k
        col = st.metal.dark if i % 2 else st.metal.core
        c.circle(nx, ny, max(0.6, 1.6 * k * (1 - t * 0.6)), col)
        prev = (nx, ny)
    c.polygon([(prev[0] - 1.4 * k, prev[1]), (prev[0] + 1.4 * k, prev[1]), (prev[0], prev[1] - 3.5 * k)], P.R_BONE.core)


def _trap(c, cx, cy, st, k):
    # Base plate and spring.
    c.ellipse(cx, cy + 3 * k, 7 * k, 2.2 * k, st.metal.dark)
    c.ellipse(cx, cy + 2.4 * k, 5 * k, 1.4 * k, st.metal.core)
    c.circle(cx - 7 * k, cy + 3 * k, 1.8 * k, st.metal.core)
    c.circle(cx + 7 * k, cy + 3 * k, 1.8 * k, st.metal.core)
    # Two open jaws, teeth splayed outward.
    for flip in (-1, 1):
        jaw = [
            (cx + flip * 1.0 * k, cy + 2 * k),
            (cx + flip * 6.5 * k, cy - 3 * k),
            (cx + flip * 7.5 * k, cy - 1.5 * k),
            (cx + flip * 2.0 * k, cy + 3.5 * k),
        ]
        c.polygon(jaw, st.metal.dark)
        c.line(jaw[0], jaw[1], st.metal.core)
        for i in range(4):
            f = 0.2 + i * 0.22
            tx = cx + flip * (1.0 + 5.5 * f) * k
            ty = cy + 2 * k - 5 * k * f
            c.polygon(
                [(tx - 0.9 * k, ty), (tx + 0.9 * k, ty), (tx + flip * 1.6 * k, ty - 3.4 * k)],
                st.metal.light,
            )


def _claws(c, cx, cy, st, k):
    # Gauntlet first, then three blades with a gap of empty pixels between
    # them — touching claws merge into an unreadable blob at icon size.
    c.polygon(
        [(cx - 4 * k, cy + 6 * k), (cx + 4 * k, cy + 6 * k), (cx + 3.5 * k, cy + 1 * k), (cx - 3.5 * k, cy + 1 * k)],
        P.R_LEATHER.dark,
    )
    c.polygon(
        [(cx - 3 * k, cy + 5 * k), (cx + 1 * k, cy + 5 * k), (cx + 1 * k, cy + 2 * k), (cx - 3 * k, cy + 2 * k)],
        P.R_LEATHER.core,
    )
    for i in range(3):
        bx = cx - 4.2 * k + i * 4.2 * k
        tip = (bx + 3.0 * k, cy - 10 * k + i * 1.2 * k)
        mid = (bx + 0.8 * k, cy - 4 * k + i * 0.6 * k)
        c.capsule((bx, cy + 1.5 * k), mid, 1.7 * k, 1.2 * k, st.metal.dark)
        c.capsule(mid, tip, 1.2 * k, 0.4, st.metal.dark)
        c.capsule((bx - 0.5, cy + 1.5 * k), (mid[0] - 0.5, mid[1]), 0.9 * k, 0.6 * k, st.metal.core)
        c.capsule((mid[0] - 0.4, mid[1]), (tip[0] - 0.4, tip[1]), 0.6 * k, 0.3, st.metal.light)
    if st.glow:
        for i in range(3):
            bx = cx - 4.2 * k + i * 4.2 * k
            c.blend(int(bx + 2.6 * k), int(cy - 9 * k + i * 1.2 * k), with_alpha(st.glow, 190))


def _whistle(c, cx, cy, st, k):
    c.polygon([(cx - 2 * k, cy + 4 * k), (cx + 2 * k, cy + 4 * k), (cx + 1.4 * k, cy - 6 * k), (cx - 1.4 * k, cy - 6 * k)], P.R_BONE.dark)
    c.polygon([(cx - 1 * k, cy + 3 * k), (cx + 0.5 * k, cy + 3 * k), (cx + 0.5 * k, cy - 5 * k), (cx - 1 * k, cy - 5 * k)], P.R_BONE.core)
    c.circle(cx, cy - 6.5 * k, 1.6 * k, P.R_BONE.light)
    glow = st.glow or P.SPECTRAL
    for i in range(4):
        r = 3 + i * 2
        c.ring(cx, cy - 9 * k, r * k, with_alpha(glow, 120 - i * 25))


def _orb(c, cx, cy, st, k):
    glow = st.glow or P.VIOLET
    c.ellipse_blend(cx, cy - 4 * k, 6 * k, 6 * k, with_alpha(glow, 42))
    c.circle(cx, cy - 4 * k, 4 * k, shade(glow, -0.45))
    c.circle(cx - 0.7 * k, cy - 4.8 * k, 2.6 * k, glow)
    c.circle(cx - 1.4 * k, cy - 5.6 * k, 1.1 * k, (255, 255, 255, 255))
    for i in range(4):
        a = i / 4 * math.tau
        c.set(int(cx + math.cos(a) * 6.5 * k), int(cy - 4 * k + math.sin(a) * 6.5 * k), glow)


_SHAPES = {
    "scythe": _scythe,
    "cleaver": lambda c, x, y, s, k: _cleaver(c, x, y, s, k, False),
    "big_cleaver": lambda c, x, y, s, k: _cleaver(c, x, y, s, k, True),
    "sword": _sword,
    "dagger": lambda c, x, y, s, k: _dagger(c, x, y, s, k, False),
    "kris": lambda c, x, y, s, k: _dagger(c, x, y, s, k, True),
    "twin_daggers": _twin_daggers,
    "pistol": lambda c, x, y, s, k: _pistol(c, x, y, s, k, False, False),
    "revolver": lambda c, x, y, s, k: _pistol(c, x, y, s, k, False, True),
    "rifle": lambda c, x, y, s, k: _long_gun(c, x, y, s, k, False, False),
    "blunderbuss": lambda c, x, y, s, k: _long_gun(c, x, y, s, k, True, False),
    "stake_launcher": lambda c, x, y, s, k: _long_gun(c, x, y, s, k, False, True),
    "bow": lambda c, x, y, s, k: _bow(c, x, y, s, k, False),
    "crossbow": lambda c, x, y, s, k: _bow(c, x, y, s, k, True),
    "staff": _staff,
    "book": _book,
    "bell": _bell,
    "lantern": _lantern,
    "flask": lambda c, x, y, s, k: _flask(c, x, y, s, k, False),
    "firebomb": lambda c, x, y, s, k: _flask(c, x, y, s, k, True),
    "whip": _whip,
    "trap": _trap,
    "claws": _claws,
    "whistle": _whistle,
    "orb": _orb,
    "none": lambda c, x, y, s, k: None,
}


def held(kind: str, style: WeaponStyle = DEFAULT, scale: float = 0.75, cell: int = 36) -> Canvas:
    """Small in-hand copy. Grip sits at the canvas centre so the rig can
    rotate it about the hand."""
    c = Canvas(cell, cell)
    fn = _SHAPES.get(kind)
    if fn is None:
        return c
    fn(c, cell / 2, cell / 2, style, scale)
    c.outline_pass(P.VOID)
    return c


def mount(kind: str, style: WeaponStyle = DEFAULT, scale: float = 0.85, cell: int = 44) -> Canvas:
    """The copy the player actually carries in the arena, pointing RIGHT.

    Shapes are authored pointing up with the grip on the canvas centre, so a
    single -90 degree turn both aims the weapon along +x and leaves the grip
    exactly on the centre pixel. That matters: the Godot sprite is `centered`
    and rotates about its origin, so the grip stays welded to the hand no
    matter which way the weapon is aimed.
    """
    from PIL import Image as _Image

    c = Canvas(cell, cell)
    fn = _SHAPES.get(kind)
    if fn is None:
        return c
    fn(c, cell / 2, cell / 2, style, scale)
    c.outline_pass(P.VOID)
    c.rim_light(P.PARCHMENT, -1, -1, 40)
    return Canvas.wrap(c.img.rotate(-90, resample=_Image.NEAREST, expand=False))


# Per-shape icon tilt. Long guns read better nearly level; round things
# (books, orbs, traps) look wrong tilted at all.
_ICON_TILT = {
    "rifle": -20, "blunderbuss": -20, "stake_launcher": -20,
    "pistol": -25, "revolver": -25, "crossbow": -15,
    "book": 0, "orb": 0, "trap": 0, "flask": -8, "firebomb": -8,
    "lantern": 0, "bell": -12, "whistle": 0, "claws": 0, "bow": 0,
}


def icon(kind: str, style: WeaponStyle = DEFAULT, cell: int = 32) -> Canvas:
    """Inventory icon: the same shape, tilted and framed to fill a square.

    Drawn small enough that it never needs downscaling — resampling pixel art
    is what makes icon sets look muddy.
    """
    from PIL import Image as _Image

    pad = cell * 2
    big = Canvas(pad, pad)
    fn = _SHAPES.get(kind)
    if fn is None:
        return Canvas(cell, cell)
    fn(big, pad / 2, pad / 2 + 3, style, 0.92)
    big.outline_pass(P.VOID)
    big.rim_light(P.PARCHMENT, -1, -1, 45)

    tilt = _ICON_TILT.get(kind, -38)
    src = Canvas.wrap(big.img.rotate(tilt, resample=_Image.NEAREST, expand=False)) if tilt else big

    out = Canvas(cell, cell)
    box = src.bounds()
    if box:
        cropped = src.img.crop(box)
        max_side = cell - 2
        if cropped.width > max_side or cropped.height > max_side:
            ratio = min(max_side / cropped.width, max_side / cropped.height)
            cropped = cropped.resize(
                (max(1, int(cropped.width * ratio)), max(1, int(cropped.height * ratio))),
                _Image.NEAREST,
            )
        out.img.alpha_composite(
            cropped, ((cell - cropped.width) // 2, (cell - cropped.height) // 2)
        )
        out.px = out.img.load()
    return out


# Weapon id -> (shape, style). Drives both icons and the .tres icon textures.
CATALOG: dict[str, tuple[str, WeaponStyle]] = {
    "rusty_scythe": ("scythe", WeaponStyle(P.R_RUST, P.R_WOOD, P.R_IRON)),
    "war_cleaver": ("big_cleaver", WeaponStyle(P.R_STEEL, P.R_WOOD, P.R_GOLD)),
    "bone_cleaver": ("cleaver", WeaponStyle(P.R_BONE, P.R_LEATHER, P.R_RUST)),
    "spellblade_of_ash": ("sword", WeaponStyle(P.R_IRON, P.R_LEATHER, P.R_GOLD, P.EMBER)),
    "silver_kris_dagger": ("kris", WeaponStyle(P.R_SILVER, P.R_LEATHER, P.R_GOLD, P.MOONLIGHT)),
    "twin_stiletto_blades": ("twin_daggers", WeaponStyle(P.R_SILVER, P.R_LEATHER, P.R_IRON)),
    "vampiric_claws": ("claws", WeaponStyle(P.R_SILVER, P.R_LEATHER, P.R_RUST, P.CRIMSON)),
    "cursed_chain_whip": ("whip", WeaponStyle(P.R_IRON, P.R_LEATHER, P.R_RUST, P.ARCANE)),
    "flintlock_pistol": ("pistol", WeaponStyle(P.R_STEEL, P.R_WOOD, P.R_GOLD, P.AMBER)),
    "hexed_revolver": ("revolver", WeaponStyle(P.R_IRON, P.R_LEATHER, P.R_ARCANE, P.VIOLET)),
    "silver_revolver": ("revolver", WeaponStyle(P.R_SILVER, P.R_WOOD, P.R_GOLD, P.MOONLIGHT)),
    "cathedral_rifle": ("rifle", WeaponStyle(P.R_STEEL, P.R_WOOD, P.R_GOLD, P.CANDLE)),
    "sawnoff_blunderbuss": ("blunderbuss", WeaponStyle(P.R_IRON, P.R_WOOD, P.R_RUST, P.EMBER)),
    "silver_stake_launcher": ("stake_launcher", WeaponStyle(P.R_SILVER, P.R_WOOD, P.R_GOLD, P.MOONLIGHT)),
    "bone_bow": ("bow", WeaponStyle(P.R_BONE, P.R_BONE, P.R_RUST)),
    "hunting_crossbow": ("crossbow", WeaponStyle(P.R_STEEL, P.R_WOOD, P.R_GOLD)),
    "wraith_staff": ("staff", WeaponStyle(P.R_IRON, P.R_WOOD, P.R_SPECTRAL, P.SPECTRAL)),
    "grimoire_of_bones": ("book", WeaponStyle(P.R_BONE, P.R_LEATHER, P.R_GOLD, P.SPECTRAL)),
    "bell_of_judgement": ("bell", WeaponStyle(P.R_GOLD, P.R_WOOD, P.R_SILVER, P.CANDLE)),
    "frost_lantern": ("lantern", WeaponStyle(P.R_SILVER, P.R_WOOD, P.R_STEEL, P.MOONLIGHT)),
    "holy_water_flask": ("flask", WeaponStyle(P.R_SILVER, P.R_WOOD, P.R_GOLD, P.MOONLIGHT)),
    "alchemists_firebomb": ("firebomb", WeaponStyle(P.R_RUST, P.R_WOOD, P.R_GOLD, P.EMBER)),
    "iron_bear_trap": ("trap", WeaponStyle(P.R_IRON, P.R_WOOD, P.R_RUST)),
    "spectral_hound_whistle": ("whistle", WeaponStyle(P.R_BONE, P.R_LEATHER, P.R_SPECTRAL, P.SPECTRAL)),
    "familiar_bolt": ("orb", WeaponStyle(P.R_ARCANE, P.R_WOOD, P.R_SILVER, P.VIOLET)),
}

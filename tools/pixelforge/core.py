"""Pixel drawing primitives for Nightbane.

Everything here is aliasing-free on purpose: shapes snap to the pixel grid,
colours come from fixed ramps, and nothing is ever blended with a soft edge.
That is what separates pixel art from a downscaled painting.
"""
from __future__ import annotations

import math
from typing import Iterable, Sequence

from PIL import Image

RGBA = tuple[int, int, int, int]
CLEAR: RGBA = (0, 0, 0, 0)


# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
def rgb(hex_code: str, alpha: int = 255) -> RGBA:
    """'#1a0f14' or '1a0f14' -> (26, 15, 20, alpha)."""
    h = hex_code.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def shade(color: RGBA, amount: float) -> RGBA:
    """Darken (amount < 0) or lighten (amount > 0) by a fraction of headroom."""
    r, g, b, a = color
    if amount >= 0.0:
        return (
            int(r + (255 - r) * amount),
            int(g + (255 - g) * amount),
            int(b + (255 - b) * amount),
            a,
        )
    f = 1.0 + amount
    return (int(r * f), int(g * f), int(b * f), a)


def mix(a: RGBA, b: RGBA, t: float) -> RGBA:
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))  # type: ignore[return-value]


def with_alpha(color: RGBA, alpha: int) -> RGBA:
    return (color[0], color[1], color[2], max(0, min(255, alpha)))


class Ramp:
    """A 5-step shading ramp: shadow -> core -> light -> highlight, plus outline.

    Pixel art reads best when every material uses the same small number of
    steps, so every surface in the game is drawn through one of these.
    """

    __slots__ = ("outline", "dark", "core", "light", "hi")

    def __init__(self, base: str | RGBA, *, outline: str | RGBA | None = None):
        core = rgb(base) if isinstance(base, str) else base
        self.core = core
        self.dark = shade(core, -0.38)
        self.light = shade(core, 0.24)
        self.hi = shade(core, 0.52)
        if outline is None:
            self.outline = shade(core, -0.72)
        else:
            self.outline = rgb(outline) if isinstance(outline, str) else outline

    def step(self, index: int) -> RGBA:
        return (self.outline, self.dark, self.core, self.light, self.hi)[
            max(0, min(4, index))
        ]

    def tinted(self, color: RGBA, t: float) -> "Ramp":
        out = Ramp(mix(self.core, color, t))
        out.outline = mix(self.outline, color, t * 0.5)
        return out


# ---------------------------------------------------------------------------
# Canvas
# ---------------------------------------------------------------------------
class Canvas:
    """A small RGBA raster with hard-edged drawing operations."""

    def __init__(self, width: int, height: int, fill: RGBA = CLEAR):
        self.w = width
        self.h = height
        self.img = Image.new("RGBA", (width, height), fill)
        self.px = self.img.load()

    # -- construction ------------------------------------------------------
    @classmethod
    def wrap(cls, image: Image.Image) -> "Canvas":
        c = cls.__new__(cls)
        c.img = image.convert("RGBA")
        c.w, c.h = c.img.size
        c.px = c.img.load()
        return c

    def clone(self) -> "Canvas":
        return Canvas.wrap(self.img.copy())

    # -- pixels ------------------------------------------------------------
    def get(self, x: int, y: int) -> RGBA:
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[x, y]
        return CLEAR

    def set(self, x: int, y: int, color: RGBA) -> None:
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h and color[3] > 0:
            self.px[x, y] = color

    def blend(self, x: int, y: int, color: RGBA) -> None:
        """Source-over a single pixel (used for glows and soft rim light)."""
        x, y = int(x), int(y)
        if not (0 <= x < self.w and 0 <= y < self.h) or color[3] <= 0:
            return
        sr, sg, sb, sa = color
        if sa >= 255:
            self.px[x, y] = color
            return
        dr, dg, db, da = self.px[x, y]
        a = sa / 255.0
        out_a = sa + int(da * (1 - a))
        self.px[x, y] = (
            int(sr * a + dr * (1 - a)),
            int(sg * a + dg * (1 - a)),
            int(sb * a + db * (1 - a)),
            min(255, out_a),
        )

    # -- shapes ------------------------------------------------------------
    def rect(self, x: int, y: int, w: int, h: int, color: RGBA) -> None:
        for py in range(int(y), int(y + h)):
            for px in range(int(x), int(x + w)):
                self.set(px, py, color)

    def rect_outline(self, x: int, y: int, w: int, h: int, color: RGBA) -> None:
        x, y, w, h = int(x), int(y), int(w), int(h)
        for px in range(x, x + w):
            self.set(px, y, color)
            self.set(px, y + h - 1, color)
        for py in range(y, y + h):
            self.set(x, py, color)
            self.set(x + w - 1, py, color)

    def hline(self, x0: int, x1: int, y: int, color: RGBA) -> None:
        if x0 > x1:
            x0, x1 = x1, x0
        for x in range(int(x0), int(x1) + 1):
            self.set(x, y, color)

    def vline(self, x: int, y0: int, y1: int, color: RGBA) -> None:
        if y0 > y1:
            y0, y1 = y1, y0
        for y in range(int(y0), int(y1) + 1):
            self.set(x, y, color)

    def line(self, p0: Sequence[float], p1: Sequence[float], color: RGBA, width: int = 1) -> None:
        x0, y0 = int(round(p0[0])), int(round(p0[1]))
        x1, y1 = int(round(p1[0])), int(round(p1[1]))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        lo = -(width // 2)
        hi = lo + width
        while True:
            for oy in range(lo, hi):
                for ox in range(lo, hi):
                    self.set(x0 + ox, y0 + oy, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, color: RGBA) -> None:
        if rx <= 0 or ry <= 0:
            return
        for y in range(int(math.floor(cy - ry)), int(math.ceil(cy + ry)) + 1):
            dy = (y - cy) / ry
            if abs(dy) > 1.0:
                continue
            half = rx * math.sqrt(max(0.0, 1.0 - dy * dy))
            self.hline(int(round(cx - half)), int(round(cx + half)), y, color)

    def circle(self, cx: float, cy: float, r: float, color: RGBA) -> None:
        self.ellipse(cx, cy, r, r, color)

    def ring(self, cx: float, cy: float, r: float, color: RGBA, thickness: int = 1) -> None:
        steps = max(8, int(r * 8))
        for i in range(steps):
            a = i / steps * math.tau
            for t in range(thickness):
                self.set(round(cx + math.cos(a) * (r - t)), round(cy + math.sin(a) * (r - t)), color)

    def polygon(self, points: Sequence[Sequence[float]], color: RGBA) -> None:
        """Scanline fill; integer edges keep the result crisp."""
        if len(points) < 3:
            return
        ys = [p[1] for p in points]
        y_min, y_max = int(math.floor(min(ys))), int(math.ceil(max(ys)))
        n = len(points)
        for y in range(y_min, y_max + 1):
            sy = y + 0.5
            xs: list[float] = []
            for i in range(n):
                ax, ay = points[i]
                bx, by = points[(i + 1) % n]
                if (ay <= sy < by) or (by <= sy < ay):
                    xs.append(ax + (sy - ay) / (by - ay) * (bx - ax))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                self.hline(int(math.floor(xs[i] + 0.5)), int(math.ceil(xs[i + 1] - 0.5)), y, color)

    def capsule(
        self,
        p0: Sequence[float],
        p1: Sequence[float],
        r0: float,
        r1: float,
        color: RGBA,
    ) -> None:
        """Tapered limb segment — the workhorse for arms, legs and tails."""
        x0, y0 = p0
        x1, y1 = p1
        dist = math.hypot(x1 - x0, y1 - y0)
        steps = max(2, int(dist) + 1)
        for i in range(steps + 1):
            t = i / steps
            self.circle(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r0 + (r1 - r0) * t, color)

    # -- compositing -------------------------------------------------------
    def paste(self, other: "Canvas", x: int = 0, y: int = 0) -> None:
        self.img.alpha_composite(other.img, (int(x), int(y)))
        self.px = self.img.load()

    def paste_rotated(
        self, other: "Canvas", cx: float, cy: float, degrees: float, flip_h: bool = False
    ) -> None:
        """Nearest-neighbour rotation about the sprite's own centre.

        Chunky rotation artefacts are the accepted look for swung weapons in
        pixel art; smoothing them would fight the rest of the style.
        """
        src = other.img.transpose(Image.FLIP_LEFT_RIGHT) if flip_h else other.img
        if degrees:
            src = src.rotate(degrees, resample=Image.NEAREST, expand=True)
        self.img.alpha_composite(src, (int(cx - src.width / 2), int(cy - src.height / 2)))
        self.px = self.img.load()

    # -- post effects ------------------------------------------------------
    def outline_pass(self, color: RGBA, diagonal: bool = False) -> None:
        """Wrap every opaque cluster in a 1px border. Applied last, so the
        silhouette stays readable against any arena floor."""
        neighbours = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            neighbours += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        additions = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[x, y][3] != 0:
                    continue
                for dx, dy in neighbours:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and self.px[nx, ny][3] > 128:
                        additions.append((x, y))
                        break
        for x, y in additions:
            self.px[x, y] = color

    def rim_light(self, color: RGBA, dx: int = -1, dy: int = -1, strength: int = 150) -> None:
        """One-pixel lit edge on the side facing the light."""
        hits = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[x, y][3] < 200:
                    continue
                nx, ny = x + dx, y + dy
                if not (0 <= nx < self.w and 0 <= ny < self.h) or self.px[nx, ny][3] < 40:
                    hits.append((x, y))
        for x, y in hits:
            self.blend(x, y, with_alpha(color, strength))

    def drop_shadow(self, cx: float, cy: float, rx: float, ry: float, alpha: int = 90) -> None:
        under = Canvas(self.w, self.h)
        under.ellipse(cx, cy, rx, ry, (0, 0, 0, alpha))
        under.img.alpha_composite(self.img)
        self.img = under.img
        self.px = self.img.load()

    def glow(self, cx: float, cy: float, r: float, color: RGBA, layers: int = 3) -> None:
        for i in range(layers, 0, -1):
            t = i / layers
            self.ellipse_blend(cx, cy, r * t, r * t, with_alpha(color, int(color[3] * (1 - t) * 0.8) + 20))

    def ellipse_blend(self, cx: float, cy: float, rx: float, ry: float, color: RGBA) -> None:
        for y in range(int(cy - ry), int(cy + ry) + 1):
            dy = (y - cy) / ry if ry else 0
            if abs(dy) > 1.0:
                continue
            half = rx * math.sqrt(max(0.0, 1.0 - dy * dy))
            for x in range(int(cx - half), int(cx + half) + 1):
                self.blend(x, y, color)

    def dither(self, x: int, y: int, w: int, h: int, color: RGBA, density: int = 2) -> None:
        """Ordered checker dithering — the classic way to fake an extra tone."""
        for py in range(y, y + h):
            for px in range(x, x + w):
                if (px + py) % density == 0:
                    self.set(px, py, color)

    def recolor(self, mapping: dict[RGBA, RGBA]) -> None:
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[x, y]
                if c in mapping:
                    self.px[x, y] = mapping[c]

    def flash(self, color: RGBA, amount: float) -> None:
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[x, y]
                if c[3] > 0:
                    self.px[x, y] = mix(c, color, amount)

    def fade(self, alpha_scale: float) -> None:
        for y in range(self.h):
            for x in range(self.w):
                r, g, b, a = self.px[x, y]
                if a:
                    self.px[x, y] = (r, g, b, int(a * alpha_scale))

    def offset(self, dx: int, dy: int) -> "Canvas":
        out = Canvas(self.w, self.h)
        out.paste(self, dx, dy)
        return out

    def scaled(self, factor: int) -> "Canvas":
        return Canvas.wrap(
            self.img.resize((self.w * factor, self.h * factor), Image.NEAREST)
        )

    def bounds(self) -> tuple[int, int, int, int] | None:
        return self.img.getbbox()

    def save(self, path) -> None:
        self.img.save(path)


# ---------------------------------------------------------------------------
# Sheet assembly
# ---------------------------------------------------------------------------
def build_sheet(frames: Sequence[Canvas], columns: int, cell: int) -> Canvas:
    rows = max(1, math.ceil(len(frames) / columns))
    sheet = Canvas(columns * cell, rows * cell)
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i % columns) * cell, (i // columns) * cell)
    return sheet


def ease_in_out(t: float) -> float:
    return t * t * (3 - 2 * t)


def ease_out(t: float) -> float:
    return 1 - (1 - t) ** 2


def ease_in(t: float) -> float:
    return t * t


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def wave(t: float, phase: float = 0.0) -> float:
    """Unit sine over a 0..1 cycle."""
    return math.sin((t + phase) * math.tau)

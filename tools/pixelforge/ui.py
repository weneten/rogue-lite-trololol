"""UI chrome: nine-slice panels, buttons, bars and HUD icons.

Every piece is authored at 1:1 pixel scale with a 5px slice margin, so Godot
stretches only the flat middle and the carved border stays sharp at any size.
"""
from __future__ import annotations

import math
from pathlib import Path

from .core import Canvas, RGBA, mix, shade, with_alpha
from . import palette as P

SLICE = 5
UNIT = 16          # nine-slice source size: 5 + 6 + 5


# ---------------------------------------------------------------------------
# Nine-slice frames
# ---------------------------------------------------------------------------
def _frame(
    fill: RGBA,
    border: RGBA,
    *,
    outer: RGBA = P.VOID,
    highlight: RGBA | None = None,
    shadow: RGBA | None = None,
    studs: RGBA | None = None,
    inner_line: RGBA | None = None,
    size: int = UNIT,
) -> Canvas:
    c = Canvas(size, size)
    c.rect(0, 0, size, size, fill)

    # Carved edge: black outside, coloured bevel inside, lit top / dark bottom.
    c.rect_outline(0, 0, size, size, outer)
    c.rect_outline(1, 1, size - 2, size - 2, border)
    if highlight:
        c.hline(2, size - 3, 2, highlight)
        c.vline(2, 2, size - 3, highlight)
    if shadow:
        c.hline(2, size - 3, size - 3, shadow)
        c.vline(size - 3, 2, size - 3, shadow)
    if inner_line:
        c.rect_outline(3, 3, size - 6, size - 6, inner_line)
    if studs:
        for sx, sy in ((2, 2), (size - 3, 2), (2, size - 3), (size - 3, size - 3)):
            c.set(sx, sy, studs)
    return c


def panels() -> dict[str, Canvas]:
    base = P.UI_PANEL
    return {
        "panel": _frame(
            base, P.UI_BORDER,
            highlight=P.UI_PANEL_HI, shadow=shade(base, -0.4), studs=P.UI_BORDER_HI,
        ),
        "panel_dark": _frame(
            P.UI_BG, shade(P.UI_BORDER, -0.3),
            highlight=shade(P.UI_BG, 0.18), shadow=P.VOID,
        ),
        "panel_inset": _frame(
            shade(P.UI_BG, -0.25), shade(P.UI_BORDER, -0.45),
            highlight=P.VOID, shadow=P.UI_PANEL_HI,
        ),
        "panel_ornate": _frame(
            base, P.UI_GOLD,
            highlight=P.UI_PANEL_HI, shadow=shade(base, -0.45),
            studs=P.CANDLE, inner_line=shade(P.UI_GOLD, -0.55),
        ),
        "panel_blood": _frame(
            shade(P.BLOOD_DARK, -0.35), P.BLOOD,
            highlight=P.CRIMSON, shadow=P.VOID, studs=P.EMBER,
        ),
        "tooltip": _frame(
            shade(P.UI_BG, -0.1), P.UI_BORDER_HI,
            highlight=P.UI_PANEL_HI, shadow=P.VOID,
        ),
    }


def buttons() -> dict[str, Canvas]:
    """Four states with real value separation — hover lifts, pressed sinks."""
    normal = _frame(
        P.UI_PANEL_HI, P.UI_BORDER,
        highlight=shade(P.UI_PANEL_HI, 0.28), shadow=shade(P.UI_PANEL, -0.45),
        studs=P.UI_BORDER_HI,
    )
    hover = _frame(
        mix(P.UI_PANEL_HI, P.BLOOD, 0.35), P.CRIMSON,
        highlight=P.EMBER, shadow=shade(P.BLOOD_DARK, -0.3), studs=P.ROSE,
    )
    pressed = _frame(
        shade(P.UI_PANEL, -0.25), P.BLOOD,
        highlight=P.VOID, shadow=P.CRIMSON, studs=P.BLOOD,
    )
    disabled = _frame(
        shade(P.UI_PANEL, -0.35), shade(P.UI_BORDER, -0.5),
        highlight=shade(P.UI_PANEL, -0.1), shadow=P.VOID,
    )
    focus = Canvas(UNIT, UNIT)
    focus.rect_outline(0, 0, UNIT, UNIT, P.AMBER)
    focus.rect_outline(1, 1, UNIT - 2, UNIT - 2, with_alpha(P.AMBER, 60))
    return {
        "button_normal": normal,
        "button_hover": hover,
        "button_pressed": pressed,
        "button_disabled": disabled,
        "button_focus": focus,
    }


def bars() -> dict[str, Canvas]:
    """Bar pieces are 8px tall; the fills carry a lit top edge so they read as
    liquid in a trough rather than a flat rectangle."""
    out: dict[str, Canvas] = {}

    bg = Canvas(UNIT, 8)
    bg.rect(0, 0, UNIT, 8, shade(P.UI_BG, -0.3))
    bg.rect_outline(0, 0, UNIT, 8, P.VOID)
    bg.hline(1, UNIT - 2, 1, shade(P.UI_BG, -0.55))
    bg.hline(1, UNIT - 2, 6, shade(P.UI_PANEL, 0.05))
    out["bar_bg"] = bg

    for name, col in (
        ("health", P.CRIMSON),
        ("xp", P.SPECTRAL),
        ("boss", P.BLOOD),
        ("shield", P.MOONLIGHT),
        ("cast", P.ARCANE),
    ):
        fill = Canvas(UNIT, 8)
        fill.rect(0, 0, UNIT, 8, shade(col, -0.35))
        fill.hline(0, UNIT - 1, 1, col)
        fill.hline(0, UNIT - 1, 2, shade(col, 0.35))
        fill.hline(0, UNIT - 1, 3, col)
        fill.hline(0, UNIT - 1, 6, shade(col, -0.55))
        out[f"bar_{name}"] = fill
    return out


def widgets() -> dict[str, Canvas]:
    out: dict[str, Canvas] = {}

    grabber = Canvas(8, 12)
    grabber.rect(0, 0, 8, 12, P.UI_PANEL_HI)
    grabber.rect_outline(0, 0, 8, 12, P.VOID)
    grabber.rect_outline(1, 1, 6, 10, P.UI_BORDER_HI)
    grabber.hline(2, 5, 5, P.AMBER)
    out["slider_grabber"] = grabber

    hi = grabber.clone()
    hi.rect_outline(1, 1, 6, 10, P.EMBER)
    hi.hline(2, 5, 5, P.CANDLE)
    out["slider_grabber_hover"] = hi

    for name, on in (("check_off", False), ("check_on", True)):
        box = Canvas(14, 14)
        box.rect(0, 0, 14, 14, shade(P.UI_BG, -0.2))
        box.rect_outline(0, 0, 14, 14, P.VOID)
        box.rect_outline(1, 1, 12, 12, P.UI_BORDER)
        if on:
            # Chunky check, drawn as two strokes so it stays crisp.
            box.line((3, 7), (6, 10), P.EMBER, 2)
            box.line((6, 10), (11, 3), P.EMBER, 2)
        out[name] = box

    for name, on in (("radio_off", False), ("radio_on", True)):
        r = Canvas(14, 14)
        r.circle(7, 7, 6, shade(P.UI_BG, -0.2))
        r.ring(7, 7, 6, P.VOID)
        r.ring(7, 7, 5, P.UI_BORDER)
        if on:
            r.circle(7, 7, 2.6, P.EMBER)
        out[name] = r

    scroll = Canvas(8, UNIT)
    scroll.rect(0, 0, 8, UNIT, shade(P.UI_BG, -0.35))
    scroll.vline(0, 0, UNIT - 1, P.VOID)
    scroll.vline(7, 0, UNIT - 1, P.VOID)
    out["scroll_bg"] = scroll

    thumb = Canvas(8, UNIT)
    thumb.rect(0, 0, 8, UNIT, P.UI_PANEL_HI)
    thumb.rect_outline(0, 0, 8, UNIT, P.VOID)
    thumb.vline(1, 1, UNIT - 2, P.UI_BORDER_HI)
    out["scroll_thumb"] = thumb

    # A hairline, not a slab: the middle row is what Godot stretches, so it
    # has to stay transparent or the separator fills its whole box.
    # A hairline, not a slab. Godot stretches the middle slice to whatever
    # height the separator gets, so that row must stay transparent.
    sep = Canvas(UNIT, 3)
    sep.hline(0, UNIT - 1, 0, P.UI_BORDER)
    out["separator"] = sep
    return out


# ---------------------------------------------------------------------------
# HUD / stat icons — 16x16, one silhouette idea each
# ---------------------------------------------------------------------------
def _icon(draw) -> Canvas:
    c = Canvas(16, 16)
    draw(c)
    c.outline_pass(P.VOID)
    return c


def _heart(c: Canvas) -> None:
    for dx in (-3, 3):
        c.circle(8 + dx, 6, 3.2, P.BLOOD)
    c.polygon([(3, 7), (13, 7), (8, 14)], P.BLOOD)
    for dx in (-3, 3):
        c.circle(8 + dx - 1, 5, 2.0, P.CRIMSON)
    c.polygon([(5, 7), (11, 7), (8, 12)], P.CRIMSON)
    c.circle(5, 4, 1.2, P.ROSE)


def _coin(c: Canvas) -> None:
    c.circle(8, 8, 6, P.GOLD_DARK)
    c.circle(8, 8, 5, P.GOLD)
    c.circle(7, 7, 3, P.AMBER)
    c.circle(6, 6, 1.2, P.CANDLE)
    c.vline(8, 5, 11, P.GOLD_DARK)


def _gem(c: Canvas) -> None:
    c.polygon([(8, 1), (14, 7), (8, 15), (2, 7)], shade(P.SPECTRAL, -0.4))
    c.polygon([(8, 3), (12, 7), (8, 13), (4, 7)], P.SPECTRAL)
    c.polygon([(8, 3), (8, 13), (4, 7)], shade(P.SPECTRAL, 0.3))
    c.set(6, 6, (255, 255, 255, 255))


def _skull(c: Canvas) -> None:
    c.ellipse(8, 7, 5, 4.6, P.BONE)
    c.rect(5, 10, 6, 4, P.BONE)
    c.rect(4, 4, 2, 2, P.VOID)
    c.rect(10, 4, 2, 2, P.VOID)
    c.ellipse(5, 7, 1.6, 1.8, P.VOID)
    c.ellipse(11, 7, 1.6, 1.8, P.VOID)
    c.set(8, 10, P.VOID)
    for x in (6, 8, 10):
        c.vline(x, 11, 13, P.VOID)


def _clock(c: Canvas) -> None:
    c.circle(8, 8, 6, P.STONE)
    c.circle(8, 8, 5, P.UI_BG)
    c.ring(8, 8, 5, P.SMOKE)
    c.line((8, 8), (8, 4), P.AMBER)
    c.line((8, 8), (11, 9), P.AMBER)
    c.set(8, 8, P.CANDLE)


def _sword(c: Canvas) -> None:
    c.polygon([(9, 1), (12, 4), (6, 11), (4, 9)], P.R_SILVER.core)
    c.polygon([(9, 2), (10, 4), (6, 9), (5, 9)], P.R_SILVER.hi)
    c.line((3, 10), (6, 13), P.GOLD, 2)
    c.line((2, 13), (4, 15), P.R_LEATHER.core, 2)


def _boot(c: Canvas) -> None:
    c.polygon([(5, 2), (9, 2), (9, 10), (13, 10), (13, 14), (4, 14)], P.R_LEATHER.core)
    c.polygon([(6, 3), (8, 3), (8, 10), (11, 10), (11, 12), (5, 12)], P.R_LEATHER.light)
    c.hline(4, 13, 14, P.INK)
    for k in range(3):
        c.set(6, 5 + k * 2, P.GOLD)


def _shield(c: Canvas) -> None:
    c.polygon([(3, 2), (13, 2), (13, 8), (8, 14), (3, 8)], P.R_STEEL.core)
    c.polygon([(5, 4), (11, 4), (11, 8), (8, 11), (5, 8)], P.R_STEEL.hi)
    c.polygon([(8, 4), (11, 4), (11, 8), (8, 11)], P.R_STEEL.dark)
    c.set(8, 6, P.GOLD)


def _crit(c: Canvas) -> None:
    for i in range(8):
        a = i / 8 * math.tau
        c.line((8, 8), (8 + math.cos(a) * 7, 8 + math.sin(a) * 7), P.AMBER if i % 2 else P.EMBER)
    c.circle(8, 8, 2.6, P.CANDLE)


def _lock(c: Canvas) -> None:
    c.ring(8, 6, 4, P.STONE, 2)
    c.rect(3, 7, 10, 8, P.R_IRON.core)
    c.rect(4, 8, 8, 6, P.R_IRON.light)
    c.rect_outline(3, 7, 10, 8, P.INK)
    c.circle(8, 11, 1.4, P.INK)


def _potion(c: Canvas) -> None:
    c.polygon([(5, 6), (11, 6), (12, 14), (4, 14)], shade(P.SMOKE, -0.45))
    c.polygon([(5, 9), (11, 9), (11, 13), (5, 13)], P.ROT)
    c.rect(6, 2, 4, 4, P.STONE)
    c.rect(5, 1, 6, 2, P.R_WOOD.core)
    c.set(6, 10, P.TOXIC)


def _wave(c: Canvas) -> None:
    for row, y in enumerate((4, 9)):
        for k in range(3):
            x = 3 + k * 5 + row * 2
            c.polygon([(x, y), (x + 3, y), (x + 1, y + 4)], P.CRIMSON if row == 0 else P.BLOOD)


def _star(c: Canvas) -> None:
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 7 if i % 2 == 0 else 3
        pts.append((8 + math.cos(a) * r, 8 + math.sin(a) * r))
    c.polygon(pts, P.AMBER)
    c.polygon([(p[0] - 0.8, p[1] - 0.8) for p in pts[:6]], P.CANDLE)


def _moon(c: Canvas) -> None:
    c.circle(8, 8, 7, P.BLOOD)
    c.circle(8, 8, 6, P.CRIMSON)
    c.circle(11, 6, 4.5, shade(P.BLOOD_DARK, -0.3))
    c.circle(5, 9, 1.2, P.EMBER)


ICONS = {
    "icon_health": _heart,
    "icon_coin": _coin,
    "icon_xp": _gem,
    "icon_skull": _skull,
    "icon_time": _clock,
    "icon_damage": _sword,
    "icon_speed": _boot,
    "icon_armor": _shield,
    "icon_crit": _crit,
    "icon_lock": _lock,
    "icon_potion": _potion,
    "icon_wave": _wave,
    "icon_star": _star,
    "icon_moon": _moon,
}


# ---------------------------------------------------------------------------
# Rarity frames for item cards
# ---------------------------------------------------------------------------
def rarity_frames() -> dict[str, Canvas]:
    out = {}
    for tier, col in P.RARITY.items():
        out[f"frame_rarity_{tier}"] = _frame(
            mix(P.UI_PANEL, col, 0.12), col,
            highlight=shade(col, 0.4), shadow=shade(col, -0.6), studs=shade(col, 0.55),
        )
    return out


# ---------------------------------------------------------------------------
# Backdrops
# ---------------------------------------------------------------------------
def menu_backdrop(width: int = 320, height: int = 180) -> Canvas:
    """A low-res parallax plate for menus: blood moon, spires, fog banks.

    Rendered at 320x180 and stretched 4x by the UI, which keeps the pixel
    grid intact at 1280x720.
    """
    c = Canvas(width, height)
    # Sky gradient, banded on purpose.
    import random

    rng = random.Random(0xB10D)
    for y in range(height):
        t = y / height
        c.hline(0, width - 1, y, mix(P.rgb("140718"), P.rgb("3a1020"), t ** 0.8))

    # Sparse stars, thinning out toward the horizon haze.
    for _ in range(70):
        sx = rng.randrange(width)
        sy = rng.randrange(int(height * 0.62))
        if rng.random() > (1.0 - sy / (height * 0.62)) * 0.9 + 0.1:
            continue
        c.blend(sx, sy, with_alpha(P.PARCHMENT, rng.choice((60, 90, 140, 200))))

    # Blood moon.
    mx, my, mr = width * 0.72, height * 0.28, 26
    c.ellipse_blend(mx, my, mr * 2.6, mr * 2.6, with_alpha(P.BLOOD, 26))
    c.ellipse_blend(mx, my, mr * 1.6, mr * 1.6, with_alpha(P.CRIMSON, 30))
    c.circle(mx, my, mr, P.rgb("7a1420"))
    c.circle(mx, my, mr - 1, P.rgb("9e2028"))
    for cx, cy, cr in ((mx - 9, my - 6, 5), (mx + 7, my + 4, 7), (mx - 3, my + 11, 4)):
        c.circle(cx, cy, cr, P.rgb("87181f"))
    c.circle(mx - 12, my - 12, 6, P.rgb("b8323a"))

    # Distant spires, two depths.
    for depth, (base_y, tone, count) in enumerate(
        ((height * 0.78, P.rgb("2a1220"), 9), (height * 0.9, P.rgb("140a12"), 7))
    ):
        x = -10
        while x < width + 10:
            w = rng.randint(14, 30)
            h = rng.randint(24, 62) * (1.0 if depth else 0.8)
            top = base_y - h
            c.polygon([(x, base_y), (x + w, base_y), (x + w, top + 8), (x + w / 2, top), (x, top + 8)], tone)
            # Windows: a few lit slits so the skyline feels inhabited.
            if depth == 0 and rng.random() < 0.7:
                for k in range(rng.randint(1, 3)):
                    wx = x + rng.randint(3, max(4, w - 4))
                    wy = top + 12 + k * 7
                    if wy < base_y - 3:
                        c.set(int(wx), int(wy), P.AMBER)
                        c.set(int(wx), int(wy) + 1, P.GOLD_DARK)
            x += w + rng.randint(-6, 4)

    # Ground fog.
    for i in range(5):
        y = height * 0.82 + i * 3
        c.ellipse_blend(width * (0.2 + i * 0.16), y, 70 - i * 6, 6, with_alpha(P.rgb("50304a"), 26))

    # Foreground: an irregular ridge of headstones and iron railings. Even
    # spacing here reads as a comb, so every tooth gets its own width.
    ridge_y = int(height * 0.9)
    c.rect(0, ridge_y, width, height - ridge_y, P.rgb("0a050c"))
    x = -4
    while x < width + 4:
        w = rng.randint(4, 11)
        h = rng.randint(3, 11)
        if rng.random() < 0.25:
            # A leaning cross among the stones.
            c.vline(int(x + w / 2), ridge_y - h - 4, ridge_y, P.rgb("0a050c"))
            c.hline(int(x + w / 2) - 2, int(x + w / 2) + 2, ridge_y - h - 1, P.rgb("0a050c"))
        else:
            c.polygon(
                [(x, ridge_y + 2), (x, ridge_y - h), (x + w / 2, ridge_y - h - 2),
                 (x + w, ridge_y - h), (x + w, ridge_y + 2)],
                P.rgb("0a050c"),
            )
        x += w + rng.randint(0, 3)
    return c


def vignette(width: int = 64, height: int = 36) -> Canvas:
    """Radial darkening plate, stretched over the arena."""
    c = Canvas(width, height)
    cx, cy = width / 2, height / 2
    max_r = math.hypot(cx, cy)
    for y in range(height):
        for x in range(width):
            d = math.hypot(x - cx, y - cy) / max_r
            a = int(max(0.0, (d - 0.45) / 0.55) ** 1.6 * 190)
            if a > 0:
                c.set(x, y, (6, 2, 8, a))
    return c


# ---------------------------------------------------------------------------
def export(root: Path) -> None:
    out = root / "Assets" / "UI"
    out.mkdir(parents=True, exist_ok=True)

    pieces: dict[str, Canvas] = {}
    pieces.update(panels())
    pieces.update(buttons())
    pieces.update(bars())
    pieces.update(widgets())
    pieces.update(rarity_frames())
    for name, fn in ICONS.items():
        pieces[name] = _icon(fn)

    for name, canvas in pieces.items():
        canvas.save(out / f"{name}.png")

    menu_backdrop().save(out / "menu_backdrop.png")
    vignette().save(out / "vignette.png")

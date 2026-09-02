"""The Bleeding Wheel: the Jester's slot machine, drawn as UI chrome.

Three pieces, all authored at 1:1 and shown at 2x in SlotMachineUI:

    slot_cabinet   the machine itself — crest, three reel windows, coin tray
    slot_lever     five frames of the arm, resting to fully pulled
    slot_blood     droplets and splats thrown off the pull

The cabinet is a fixed sprite rather than a nine-slice: a slot machine has a
shape, and stretching one would put its reel windows wherever the layout felt
like. SlotMachineUI positions everything against the constants below, so the
art and the layout cannot drift apart.
"""
from __future__ import annotations

import math
from pathlib import Path

from .core import Canvas, RGBA, mix, shade, with_alpha
from . import palette as P

# Cabinet geometry, in source pixels. SlotMachineUI mirrors these (times its
# display scale) to place the reels; change one and change the other.
CAB_W = 100
CAB_H = 88
WINDOW_Y = 24
WINDOW_H = 28
WINDOW_W = 22
WINDOW_X = (8, 38, 68)
# Where the lever's pivot sits on the cabinet.
MOUNT = (95, 34)

LEVER_W = 52
LEVER_H = 64
LEVER_PIVOT = (8, 56)
LEVER_FRAMES = 5

BLOOD_CELL = 12
BLOOD_FRAMES = 4

# Lacquered blood-red enamel over iron, with gold trim: the cabinet has to read
# as a fairground machine that has been in a crypt for a century.
ENAMEL = P.rgb("6b1220")
ENAMEL_HI = P.rgb("9c2030")
ENAMEL_LO = P.rgb("3a0a12")
IRON = P.rgb("2a2230")
GOLD = P.UI_GOLD
GOLD_LO = P.rgb("6b4a12")


def _bevel(c: Canvas, x: int, y: int, w: int, h: int, fill: RGBA, hi: RGBA, lo: RGBA) -> None:
    """Flat panel with a lit top-left and a dark bottom-right."""
    c.rect(x, y, w, h, fill)
    c.hline(x, x + w - 1, y, hi)
    c.vline(x, y, y + h - 1, hi)
    c.hline(x, x + w - 1, y + h - 1, lo)
    c.vline(x + w - 1, y, y + h - 1, lo)


def _drip(c: Canvas, x: int, y: int, length: int, color: RGBA) -> None:
    """A bead of blood running down from a lip. Two pixels wide, then one."""
    c.vline(x, y, y + length - 2, color)
    c.vline(x + 1, y, y + max(0, length // 2), color)
    c.set(x, y + length - 1, shade(color, 0.25))


def cabinet() -> Canvas:
    c = Canvas(CAB_W, CAB_H)

    # Body and outline.
    c.rect(2, 6, CAB_W - 6, CAB_H - 8, IRON)
    _bevel(c, 3, 7, CAB_W - 8, CAB_H - 10, ENAMEL, ENAMEL_HI, ENAMEL_LO)

    # Crest: an arch with a skull in it. The one silhouette that says this is
    # not just another HUD panel.
    for i in range(14):
        span = int(math.sqrt(max(0.0, 1.0 - (i / 14.0) ** 2)) * 30)
        c.hline(46 - span, 46 + span, 6 - 0 + i - 8 + 8, ENAMEL if i > 1 else ENAMEL_LO)
    c.ellipse(46, 8, 30, 9, ENAMEL)
    c.ellipse(46, 8, 28, 7, ENAMEL_HI)
    c.ellipse(46, 9, 26, 6, ENAMEL)

    skull_x, skull_y = 46, 9
    c.ellipse(skull_x, skull_y, 6, 5, P.BONE)
    c.ellipse(skull_x, skull_y - 1, 5, 4, P.PARCHMENT)
    c.rect(skull_x - 3, skull_y + 3, 6, 3, P.BONE)
    for ex in (-2, 2):
        c.rect(skull_x + ex - 1, skull_y - 1, 2, 2, P.VOID)
        c.set(skull_x + ex, skull_y - 1, P.CRIMSON)
    c.set(skull_x, skull_y + 1, P.VOID)
    for k in range(3):
        c.vline(skull_x - 2 + k * 2, skull_y + 3, skull_y + 5, P.VOID)

    # Gold band under the crest.
    c.hline(6, CAB_W - 7, 18, GOLD)
    c.hline(6, CAB_W - 7, 19, GOLD_LO)

    # Reel bay: one recessed plate holding three windows.
    _bevel(c, 5, WINDOW_Y - 3, CAB_W - 12, WINDOW_H + 8, IRON, P.VOID, P.UI_PANEL_HI)
    for wx in WINDOW_X:
        c.rect(wx - 1, WINDOW_Y - 1, WINDOW_W + 2, WINDOW_H + 2, P.VOID)
        c.rect(wx, WINDOW_Y, WINDOW_W, WINDOW_H, P.rgb("0d0a12"))
        # Glass: a lit top edge and a faint red bloom at the bottom, so the
        # window reads as covered rather than as a hole.
        c.hline(wx, wx + WINDOW_W - 1, WINDOW_Y, P.rgb("2a2438"))
        # Blended, not set: an alpha-40 pixel written straight into the buffer
        # would come out pale rather than as a faint glow over the dark glass.
        for k in range(3):
            for gx in range(wx, wx + WINDOW_W):
                c.blend(gx, WINDOW_Y + WINDOW_H - 1 - k, with_alpha(P.BLOOD, 44 - k * 12))
        c.rect_outline(wx - 1, WINDOW_Y - 1, WINDOW_W + 2, WINDOW_H + 2, GOLD_LO)

    # Lower fascia: a coin slot, and the tray the winnings never come out of.
    _bevel(c, 5, 58, CAB_W - 12, 12, ENAMEL_LO, ENAMEL, P.VOID)
    c.rect(40, 62, 14, 3, P.VOID)
    c.hline(40, 53, 62, GOLD_LO)
    _bevel(c, 12, 72, CAB_W - 26, 10, IRON, P.UI_PANEL_HI, P.VOID)
    c.rect(16, 75, CAB_W - 34, 5, P.rgb("0d0a12"))
    for dx in (22, 36, 54, 70):
        c.blend(dx, 78, with_alpha(P.BLOOD, 150))

    # Blood run out from under the gold band, over the bay's dividers and down
    # the fascia. Drawn last so it sits on top of the metal, the way it would.
    for dx, length in ((6, 26), (33, 34), (63, 20), (92, 30)):
        _drip(c, dx, 20, length, P.BLOOD)
    for dx, length in ((16, 7), (75, 5)):
        _drip(c, dx, 58, length, P.BLOOD_DARK)

    # Lever mount: a gold boss on the right flank.
    c.ellipse(MOUNT[0] - 2, MOUNT[1], 4, 4, GOLD_LO)
    c.ellipse(MOUNT[0] - 2, MOUNT[1] - 1, 3, 3, GOLD)

    c.outline_pass(P.VOID)
    return c


def lever_frames() -> list[Canvas]:
    """The arm, resting (frame 0) to fully pulled (frame 4).

    Rotation is baked into frames rather than done at runtime: a rotated pixel
    sprite fringes at every angle, and five frames is the whole animation.
    """
    frames: list[Canvas] = []
    # Degrees from vertical, positive swinging down and forward.
    for angle in (-8.0, 18.0, 46.0, 70.0, 84.0):
        c = Canvas(LEVER_W, LEVER_H)
        px, py = LEVER_PIVOT
        a = math.radians(angle)
        length = 40.0
        tip = (px + math.sin(a) * length, py - math.cos(a) * length)

        # Shaft: steel, with a lit side so the pull has some weight to it.
        c.capsule((px, py), tip, 2.6, 2.0, P.rgb("6b7382"))
        c.capsule((px + 0.6, py), (tip[0] + 0.6, tip[1] + 0.4), 1.4, 0.9, P.rgb("9aa3b4"))

        # Knob: a blood-red ball, brighter as the arm comes down and the
        # machine wakes up.
        heat = frames.__len__() / float(LEVER_FRAMES - 1)
        knob = mix(P.CRIMSON, P.EMBER, heat * 0.7)
        c.ellipse(tip[0], tip[1], 4.2, 4.2, shade(knob, -0.45))
        c.ellipse(tip[0], tip[1], 3.4, 3.4, knob)
        c.ellipse(tip[0] - 1.1, tip[1] - 1.2, 1.5, 1.4, mix(knob, P.ROSE, 0.6))

        # Mount collar over the shaft root.
        c.ellipse(px, py, 4.0, 3.6, GOLD_LO)
        c.ellipse(px, py - 0.6, 3.0, 2.6, GOLD)
        c.set(round(px), round(py), shade(GOLD_LO, -0.4))

        c.outline_pass(P.VOID)
        frames.append(c)

    return frames


def blood_frames() -> list[Canvas]:
    """Two droplets and two splats, in that order of size.

    Deliberately small: the pull throws a few beads, it does not paint the
    screen. SlotMachineUI flings the droplets and leaves one splat behind.
    """
    frames: list[Canvas] = []
    cell = BLOOD_CELL
    mid = cell / 2.0

    for radius in (1.6, 2.6):
        c = Canvas(cell, cell)
        c.ellipse(mid, mid, radius, radius * 1.25, P.BLOOD_DARK)
        c.ellipse(mid, mid - 0.3, radius * 0.7, radius * 0.9, P.BLOOD)
        c.set(round(mid - radius * 0.4), round(mid - radius * 0.6), P.CRIMSON)
        frames.append(c)

    for scale, spokes in ((0.75, 4), (1.0, 6)):
        c = Canvas(cell, cell)
        c.ellipse(mid, mid, 2.4 * scale, 1.9 * scale, P.BLOOD_DARK)
        c.ellipse(mid, mid - 0.3, 1.6 * scale, 1.2 * scale, P.BLOOD)
        for k in range(spokes):
            ang = math.tau * (k / float(spokes)) + 0.4
            dist = (2.6 + (k % 2) * 1.4) * scale
            x = round(mid + math.cos(ang) * dist)
            y = round(mid + math.sin(ang) * dist * 0.8)
            c.set(x, y, P.BLOOD)
            if k % 2 == 0:
                c.blend(x, y - 1, with_alpha(P.BLOOD_DARK, 170))
        frames.append(c)

    return frames


def _sheet(frames: list[Canvas], cell_w: int, cell_h: int) -> Canvas:
    sheet = Canvas(cell_w * len(frames), cell_h)
    for i, frame in enumerate(frames):
        sheet.paste(frame, i * cell_w, 0)
    return sheet


# ---------------------------------------------------------------------------
def export(root: Path) -> None:
    out = root / "Assets" / "UI"
    out.mkdir(parents=True, exist_ok=True)

    cabinet().save(out / "slot_cabinet.png")
    _sheet(lever_frames(), LEVER_W, LEVER_H).save(out / "slot_lever.png")
    _sheet(blood_frames(), BLOOD_CELL, BLOOD_CELL).save(out / "slot_blood.png")

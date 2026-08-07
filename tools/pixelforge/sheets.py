"""Renders each cast entry into a Godot-ready sprite sheet + atlas JSON.

Layout is a fixed 6-column grid, one animation per row, which is exactly what
SpriteSheetCache expects:

    row 0  idle   4 frames   loop
    row 1  run    6 frames   loop
    row 2  attack 6 frames   one-shot   (enemies and bosses only)
    row 3  hurt   2 frames   one-shot
    row 4  death  5 frames   one-shot
    row 5  dash   4 frames   one-shot

Hunters have no attack row — see `anims_for`. Rows and frame indices are
written into the atlas JSON, so a sheet with one row fewer needs no change
anywhere on the Godot side.
"""
from __future__ import annotations

import json
from pathlib import Path

from .cast import Entry
from .core import Canvas, build_sheet
from .rig import build_pose, draw_figure
from . import weapons
from . import palette as P

COLUMNS = 6

# name, frame count, fps, loops
ANIMS = [
    ("idle", 4, 6, True),
    ("run", 6, 12, True),
    ("attack", 6, 14, False),
    ("hurt", 2, 12, False),
    ("death", 5, 9, False),
    ("dash", 4, 16, False),
]

# The combat code asks for these by name depending on weapon class; they all
# resolve to the same swing so nothing ever falls back to idle.
ATTACK_ALIASES = [
    "attack_slash", "attack_whip", "attack_orbs", "shield_bash",
    "chain_swing", "attack_spin", "attack_nova", "attack_cross",
]


def anims_for(entry: Entry) -> list[tuple]:
    """Which rows this entry's sheet gets.

    Hunters get no attack row. A Hunter fires six weapons at once at whatever
    is nearest, so an attack animation on the body was firing several times a
    second and the character spent the whole wave twitching. The swing lives
    on the weapon instead (Scripts/Combat/WeaponVisual.gd), which is both what
    the player is actually watching and the only thing that knows whether the
    weapon is a scythe or a revolver.

    Enemies and bosses attack with their bodies, so they keep theirs.
    """
    if entry.group == "characters":
        return [a for a in ANIMS if a[0] != "attack"]
    return ANIMS


def _feet_y(cell: int) -> float:
    return cell - 6.0


def render_frames(entry: Entry) -> list[Canvas]:
    cell = entry.cell
    cx = cell * 0.46
    fy = _feet_y(cell)
    weapon_scale = 0.62 * entry.spec.stature
    held = (
        weapons.held(entry.spec.weapon, entry.weapon_style, weapon_scale, cell=max(28, int(cell * 0.62)))
        if entry.spec.weapon != "none"
        else None
    )

    frames: list[Canvas] = []
    for name, count, _fps, loops in anims_for(entry):
        row: list[Canvas] = []
        for i in range(count):
            # Looping anims sample [0,1); one-shots reach the final pose.
            t = i / count if loops else (i / (count - 1) if count > 1 else 0.0)
            pose = build_pose(entry.spec, name, t, center_x=cx, feet_y=fy, swing=entry.swing)
            frame = Canvas(cell, cell)
            flash = 0.38 if (name == "hurt" and i == 0) else 0.0
            draw_figure(frame, entry.spec, pose, t=t, weapon_canvas=held, flash=flash)
            if name == "dash":
                _add_dash_streaks(frame, pose, i, count)
            row.append(frame)
        # Pad each row out to the column count so indices stay predictable.
        row += [Canvas(cell, cell) for _ in range(COLUMNS - count)]
        frames.extend(row)
    return frames


def _add_dash_streaks(frame: Canvas, pose, index: int, count: int) -> None:
    from .core import with_alpha

    fade = 1.0 - index / count
    for k in range(3):
        alpha = int(70 * fade / (k + 1))
        if alpha <= 4:
            continue
        x = pose.hip[0] - 5 - k * 4
        frame.ellipse_blend(x, pose.hip[1] - 4, 2.0, 9.0, with_alpha(P.MOONLIGHT, alpha))


def build_meta(entry: Entry) -> dict:
    cell = entry.cell
    anims = anims_for(entry)
    animations: dict[str, dict] = {}
    for row, (name, count, fps, loops) in enumerate(anims):
        indices = [row * COLUMNS + i for i in range(count)]
        animations[name] = {
            "row": row,
            "from": indices[0],
            "to": indices[-1],
            "frames": indices,
            "frameCount": count,
            "fps": fps,
            "loop": loops,
        }
    if "attack" in animations:
        for alias in ATTACK_ALIASES:
            animations[alias] = dict(animations["attack"])

    return {
        "image": f"{entry.ident}.png",
        "frameWidth": cell,
        "frameHeight": cell,
        "columns": COLUMNS,
        "rows": len(anims),
        "facing": "right",
        "pixelArt": True,
        "origin": {"x": round(cell * 0.46, 1), "y": _feet_y(cell)},
        "animations": animations,
    }


def build_portrait(entry: Entry, size: int = 96) -> Canvas:
    """A bust for the character-select panel: the idle pose, framed to the
    chest, on transparency so the panel art shows behind it."""
    spec = entry.spec
    big_cell = 96
    cx = big_cell * 0.46
    fy = _feet_y(big_cell)
    scale_up = 1.55 if entry.cell == 64 else 1.0
    original = spec.stature
    spec.stature = original * scale_up
    pose = build_pose(spec, "idle", 0.15, center_x=cx, feet_y=fy, swing=entry.swing)
    tall = Canvas(big_cell, big_cell)
    held = (
        weapons.held(spec.weapon, entry.weapon_style, 0.62 * spec.stature, cell=int(big_cell * 0.62))
        if spec.weapon != "none"
        else None
    )
    draw_figure(tall, spec, pose, t=0.15, weapon_canvas=held)
    spec.stature = original

    out = Canvas(size, size)
    # Frame on the head and shoulders rather than the whole figure.
    head_y = pose.head[1] - pose.head_r * 3.0
    out.paste(tall, int((size - big_cell) / 2 + (size * 0.5 - pose.head[0])), int(-head_y + 8))
    return out


def export(entry: Entry, root: Path) -> None:
    out_dir = root / "Assets" / "sprites" / entry.group / entry.ident
    out_dir.mkdir(parents=True, exist_ok=True)

    frames = render_frames(entry)
    sheet = build_sheet(frames, COLUMNS, entry.cell)
    sheet.save(out_dir / f"{entry.ident}.png")

    meta = build_meta(entry)
    (out_dir / f"{entry.ident}.json").write_text(json.dumps(meta, indent=2) + "\n")

    build_portrait(entry).save(out_dir / f"{entry.ident}_portrait.png")

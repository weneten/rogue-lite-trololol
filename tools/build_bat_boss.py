#!/usr/bin/env python3
"""Build The Belfry Tyrant's sprite sheet from the supplied bat artwork.

    python3 tools/build_bat_boss.py "<BatBoss.png>"

Writes over assets/sprites/bosses/belfry_tyrant/, on purpose: the .tres, the
.import and the uid all point there already, so replacing the art in place is
the whole swap.

The source is a labelled reference sheet laid out in two columns, which is what
makes it different from the other build scripts here:

* It is drawn on a near-black backdrop. strip_background's default tolerance of
  34 counts the bat's own shadowed wings as backdrop and floods holes through
  the middle of the figure, so this passes a much tighter one. Anything above
  about 10 starts eating wing.
* Rows do not span the sheet. IDLE sits beside SCREAM, WALK beside the take-off
  wind-up, and only ATTACK (DIVE) runs the full width. A y-band alone would
  therefore scoop up two unrelated animations, so each region states its x range
  as well.
* The captions are plain light text rather than badges, and two of them
  (FLY, ATTACK) sit low enough to touch the figures underneath. They are erased
  by stated rectangle before anything is measured.

Frame counts per region are stated rather than guessed: the bats overlap wing to
wing, so the column profile has no clean valley between them, and the wide dive
poses would otherwise be read as two bats each.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image  # noqa: E402

from spritecut import (  # noqa: E402
    _drop_grey_shadow,
    _runs,
    _tighten,
    build_sheet,
    strip_background,
)

ROOT = Path(__file__).resolve().parents[1]
NAME = "belfry_tyrant"
CELL = 128
FEET_MARGIN = 4

# The backdrop is (10, 11, 16) and very flat; the darkest wing is comfortably
# above this. See the module docstring for why the default is far too loose.
BG_TOLERANCE = 8

# Caption text, erased before slicing. FLY/ABHEBEN/ATTACK overlap their own
# figure band, so this cannot simply be a strip off the top of each band.
LABELS = [
    (14, 20, 70, 44),      # IDLE
    (793, 20, 1098, 44),   # SCREAM / SCHREI ANIMATION
    (14, 246, 76, 270),    # WALK
    (793, 246, 1190, 270), # FLUCHT / GLEICH ABHEBEN (WIND-UP)
    (14, 458, 60, 489),    # FLY
    (793, 458, 1018, 489), # ABHEBEN / TAKE OFF
    (14, 656, 175, 681),   # ATTACK (DIVE)
    (14, 838, 75, 860),    # HURT
    (768, 838, 842, 860),  # DEATH
]

# name, y0, y1, x0, x1, frame count. Order fixes the frame indices the layout
# below refers to.
REGIONS = [
    ("idle",    45,  222,    0,  772, 4),
    ("scream",  45,  222,  772, 1536, 4),
    ("walk",   268,  425,    0,  774, 6),
    ("crouch", 268,  425,  774, 1536, 4),
    ("fly",    450,  632,    0,  780, 5),
    ("takeoff",450,  632,  780, 1536, 4),
    ("dive",   650,  815,    0, 1536, 9),
    ("hurt",   858,  992,    0,  756, 5),
    ("death",  858,  992,  756, 1536, 5),
]

BLOOD = (150, 24, 30)
VOID = (86, 60, 120)

ATTACK_ALIASES = [
    "attack_slash", "attack_whip", "attack_orbs", "shield_bash",
    "chain_swing", "attack_spin", "attack_nova", "attack_cross",
]


def _erase_labels(px) -> None:
    for x0, y0, x1, y1 in LABELS:
        for y in range(y0, y1):
            for x in range(x0, x1):
                px[x, y] = (0, 0, 0, 0)


def _valley_cuts(profile: list[int], run: tuple[int, int], pieces: int) -> list[tuple[int, int]]:
    """Cut one run into `pieces` at its emptiest columns.

    spritecut's _split_wide looks for a valley near each even division point,
    inside a narrow window. That assumes the frames are about the same width,
    and on this sheet they are not — a bat mid-stride with its wings folded is
    two thirds the width of one with them spread, so by the third frame the even
    division has drifted past the real gap and the window no longer contains it.
    Picking the emptiest columns outright does not care how the widths are
    distributed; the only thing enforced is that two cuts cannot sit on top of
    each other. Depth decides, and distance from the even division breaks ties.
    """
    start, end = run
    if pieces <= 1:
        return [run]

    span = end - start
    guard = max(8, int(span / pieces * 0.55))
    candidates = list(range(start + guard, end - guard))

    cuts: list[int] = []
    for k in range(1, pieces):
        if not candidates:
            break

        ideal = start + span * k / pieces
        best = min(candidates, key=lambda x: (profile[x], abs(x - ideal)))
        cuts.append(best)
        candidates = [x for x in candidates if abs(x - best) >= guard]

    cuts.sort()
    bounds = [start] + cuts + [end]
    return [(bounds[i], bounds[i + 1]) for i in range(len(bounds) - 1)]


def _split_to_count(profile: list[int], runs: list[tuple[int, int]], want: int) -> list[tuple[int, int]]:
    """Cut `runs` into exactly `want` frames, sharing them out by width.

    spritecut's own loop splits the widest run in half over and over, which is
    right when the overflow is one pair of touching figures. Here a single run
    can hold five overlapping bats while its neighbour holds one, and repeated
    halving gives that run four pieces instead of five. Handing each run a share
    proportional to its width puts roughly the right number of cuts in each.
    """
    if not runs:
        return []

    widths = [b - a for a, b in runs]
    unit = sum(widths) / want
    pieces = [max(1, round(w / unit)) for w in widths]

    # Rounding rarely lands on `want` exactly. Move one piece at a time to or
    # from whichever run is currently most / least crowded.
    guard = 0
    while sum(pieces) != want and guard < 64:
        guard += 1
        if sum(pieces) > want:
            index = min((i for i in range(len(pieces)) if pieces[i] > 1),
                        key=lambda i: widths[i] / pieces[i], default=None)
            if index is None:
                break

            pieces[index] -= 1
        else:
            index = max(range(len(pieces)), key=lambda i: widths[i] / pieces[i])
            pieces[index] += 1

    out: list[tuple[int, int]] = []
    for run, count in zip(runs, pieces):
        out.extend(_valley_cuts(profile, run, count))

    return out


def slice_bat(path: Path) -> tuple[Image.Image, list[dict], dict[str, tuple[int, int]]]:
    image = strip_background(Image.open(path), BG_TOLERANCE)
    px = image.load()
    _erase_labels(px)

    frames: list[dict] = []
    spans: dict[str, tuple[int, int]] = {}
    for name, y0, y1, x0, x1, want in REGIONS:
        profile = [sum(1 for y in range(y0, y1) if px[x, y][3] > 24) if x0 <= x < x1 else 0
                   for x in range(image.width)]
        runs = _split_to_count(profile, [r for r in _runs(profile, 16)], want)

        start = len(frames)
        for rx0, rx1 in runs:
            box = _tighten(px, (rx0, y0, rx1, y1))
            if box is None:
                continue

            box = _drop_grey_shadow(px, box)
            frames.append({"box": box, "w": box[2] - box[0], "h": box[3] - box[1]})

        spans[name] = (start, len(frames))
        if len(frames) - start != want:
            print(f"[bat] {name}: found {len(frames) - start}, expected {want}")

    return image, frames, spans


def layout(spans: dict[str, tuple[int, int]]) -> list[dict]:
    def row(region: str) -> list[tuple[str, int]]:
        start, end = spans[region]
        return [("b", i) for i in range(start, end)]

    return [
        {"name": "idle", "fps": 6, "loop": True, "frames": row("idle")},
        {"name": "run", "fps": 12, "loop": True, "frames": row("walk")},
        # He shells from the air between dives; this is the hover, not the dive.
        {"name": "fly", "fps": 12, "loop": True, "frames": row("fly")},
        # The scream IS the sonic wave, so it is his attack row outright.
        {"name": "attack", "fps": 12, "loop": False, "aliases": ATTACK_ALIASES,
         "frames": row("scream")},
        # Gathering himself before he leaves the ground. Played over the
        # ascend_dive wind-up, which had no animation of its own before.
        {"name": "crouch", "fps": 12, "loop": False, "frames": row("crouch")},
        {"name": "takeoff", "fps": 14, "loop": False, "frames": row("takeoff")},
        # "dash" as well, because that is the name the boss used for both halves
        # of the manoeuvre before this sheet gave it two.
        {"name": "dive", "fps": 16, "loop": False, "aliases": ["dash"],
         "frames": row("dive")},
        {"name": "hurt", "fps": 12, "loop": False, "frames": row("hurt")},
        {"name": "death", "fps": 9, "loop": False, "frames": row("death")},
    ]


def portrait(image: Image.Image, frames: list[dict], index: int, size: int = 96) -> Image.Image:
    """Head-and-shoulders bust for the boss bar / codex."""
    frame = frames[index]
    crop = image.crop(frame["box"])
    head = crop.crop((0, 0, crop.width, max(1, int(crop.height * 0.62))))
    scale = min(size / head.width, size / head.height)
    head = head.resize((max(1, round(head.width * scale)), max(1, round(head.height * scale))),
                       Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(head, ((size - head.width) // 2, (size - head.height) // 2))
    return out


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(1)

    print("slicing source artwork...")
    image, frames, spans = slice_bat(Path(sys.argv[1]))
    print(f"  {len(frames)} frames, tallest {max(f['h'] for f in frames)}px, "
          f"widest {max(f['w'] for f in frames)}px")

    rows = layout(spans)
    columns = max(len(entry["frames"]) for entry in rows)

    out_dir = ROOT / "assets" / "sprites" / "bosses" / NAME
    out_dir.mkdir(parents=True, exist_ok=True)

    sheet, meta = build_sheet({"b": (image, frames)}, rows, CELL, columns, FEET_MARGIN)
    meta["image"] = f"{NAME}.png"
    sheet.save(out_dir / f"{NAME}.png")
    (out_dir / f"{NAME}.json").write_text(json.dumps(meta, indent=2) + "\n")

    portrait(image, frames, spans["idle"][0]).save(out_dir / f"{NAME}_portrait.png")
    print(f"  {NAME}: {sheet.width}x{sheet.height}, {len(meta['animations'])} anims")


if __name__ == "__main__":
    main()

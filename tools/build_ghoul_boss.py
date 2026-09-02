#!/usr/bin/env python3
"""Build The Tolling Ghoul's sprite sheet from the supplied artwork.

    python3 tools/build_ghoul_boss.py "<GhoulBoss.png>"

The source is a labelled reference sheet — five rows of poses with a caption
badge in front of each one — rather than a grid, so the figures are found
first and this file says what each one is for.

Two things the generic slicer in spritecut.py cannot work out on its own:

* The caption badges ("IDLE", "WALK", …) are solid blobs sitting in the same
  band as the figures, and the column splitter counts them as characters. They
  are flood-filled away before slicing, seeded from the leftmost pixel of each
  band, which is always a badge on this sheet.
* Attack and spin share one band. The painted ground shadows bridge the gap
  between them, so the row profile never reaches zero and the automatic band
  finder merges the two. The bands are therefore stated outright.
* strip_background floods in from the borders, which cannot reach the backdrop
  showing between a leg and a robe hem. Those pockets survive as white blobs
  sitting on the character, so they are cleared in a second pass.

Three frames are also cropped narrower than the artwork drew them. build_sheet
centres every frame in its cell and scales them all by one shared factor, so a
frame carrying a wide flourish — the slam's dust plume, the dropped bell beside
the corpse — would both shrink the whole character and shove its body off to
one side of the cell. The slam's impact is drawn in-engine by BossGroundQuake
anyway, which is the version that has to line up with the hitbox.
"""
from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image  # noqa: E402

from spritecut import (  # noqa: E402
    _drop_grey_shadow,
    _runs,
    _split_wide,
    _tighten,
    build_sheet,
    strip_background,
)

ROOT = Path(__file__).resolve().parents[1]
NAME = "tolling_ghoul"
CELL = 160
COLUMNS = 5
FEET_MARGIN = 4

# (y0, y1, how many figures). Read off the artwork; the attack/spin split at
# 657 is where the two rows' shadows stop overlapping.
BANDS = [
    (9, 224, 4),    # 0-3    idle
    (233, 413, 5),  # 4-8    walk
    (430, 657, 5),  # 9-13   overhead slam
    (657, 830, 5),  # 14-18  spin
    (842, 1012, 5), # 19-23  death
]

# frame index -> replacement right edge. See the module docstring.
CROP_RIGHT = {
    12: 1015,  # slam: keep the ghoul, drop the dust plume
    14: 330,   # spin wind-up: drop the next frame's stray swirl
    23: 1300,  # corpse: drop the bell that rolled away
}

PALE = (255, 242, 236)
ROT = (104, 62, 126)

# Deliberately no "attack_spin": the whirlwind has a row of its own, and
# aliasing it onto the slam would make the two attacks look identical.
ATTACK_ALIASES = [
    "attack_slash", "attack_whip", "attack_orbs", "shield_bash",
    "chain_swing", "attack_nova", "attack_cross",
]


def _erase_badge(px, width: int, height: int, y0: int, y1: int) -> None:
    """Flood the caption badge out of one band.

    Seeded from the first opaque pixel in the band's left margin, which on this
    sheet is always the badge — the figures start well clear of it.
    """
    seed = None
    for y in range(y0, min(y0 + 60, y1)):
        for x in range(0, 60):
            if px[x, y][3] > 24:
                seed = (x, y)
                break
        if seed:
            break

    if seed is None:
        return

    queue = deque([seed])
    seen = set()
    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or not (0 <= x < width and y0 <= y < y1):
            continue

        seen.add((x, y))
        if px[x, y][3] <= 24:
            continue

        px[x, y] = (0, 0, 0, 0)
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))


# Backdrop left over inside the silhouette is near-white and neutral. The
# ghoul's own brightest pixels — bone highlights, the sheen on the bell — sit
# below this, and the ones that do not are single specks rather than pockets.
ENCLOSED_MIN_CHANNEL = 238
ENCLOSED_MAX_SPREAD = 14
ENCLOSED_MIN_BLOB = 24


def _strip_enclosed_background(px, width: int, height: int) -> int:
    """Clear backdrop pockets the border flood could not reach.

    Only blobs are cleared, never lone pixels: a specular highlight on the bell
    can be as pale as the paper behind it, but it is never a puddle of it.
    """
    def is_paper(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return (a > 24 and min(r, g, b) >= ENCLOSED_MIN_CHANNEL
                and max(r, g, b) - min(r, g, b) <= ENCLOSED_MAX_SPREAD)

    seen = bytearray(width * height)
    cleared = 0
    for sy in range(height):
        for sx in range(width):
            if seen[sy * width + sx] or not is_paper(sx, sy):
                continue

            blob = []
            queue = deque([(sx, sy)])
            seen[sy * width + sx] = 1
            while queue:
                x, y = queue.popleft()
                blob.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if not (0 <= nx < width and 0 <= ny < height):
                        continue

                    index = ny * width + nx
                    if seen[index] or not is_paper(nx, ny):
                        continue

                    seen[index] = 1
                    queue.append((nx, ny))

            if len(blob) < ENCLOSED_MIN_BLOB:
                continue

            for x, y in blob:
                px[x, y] = (0, 0, 0, 0)

            cleared += len(blob)

    return cleared


def slice_ghoul(path: Path) -> tuple[Image.Image, list[dict]]:
    image = strip_background(Image.open(path))
    width, height = image.size
    px = image.load()

    print(f"  cleared {_strip_enclosed_background(px, width, height)} enclosed backdrop px")
    for y0, y1, _ in BANDS:
        _erase_badge(px, width, height, y0, y1)

    frames: list[dict] = []
    for y0, y1, want in BANDS:
        column_profile = [sum(1 for y in range(y0, y1) if px[x, y][3] > 24) for x in range(width)]
        runs = list(_runs(column_profile, 12))

        # Neighbouring figures overlap, so split the widest run until the band
        # holds the number of poses the artwork actually contains.
        guard = 0
        while len(runs) < want and guard < 24:
            guard += 1
            widest = max(range(len(runs)), key=lambda k: runs[k][1] - runs[k][0])
            run = runs.pop(widest)
            runs[widest:widest] = _split_wide(column_profile, run, 2)

        if len(runs) != want:
            print(f"[ghoul] band {y0}-{y1}: found {len(runs)}, expected {want}")

        for x0, x1 in runs:
            box = _tighten(px, (x0, y0, x1, y1))
            if box is None:
                continue

            box = _drop_grey_shadow(px, box)
            crop_to = CROP_RIGHT.get(len(frames))
            if crop_to is not None:
                box = (box[0], box[1], min(box[2], crop_to), box[3])

            frames.append({"box": box, "w": box[2] - box[0], "h": box[3] - box[1]})

    return image, frames


def layout() -> list[dict]:
    """0-3 idle, 4-8 walk, 9-13 slam, 14-18 spin, 19-23 death."""
    return [
        {"name": "idle", "fps": 6, "loop": True,
         "frames": [("g", 0), ("g", 1), ("g", 2), ("g", 3)]},
        {"name": "run", "fps": 11, "loop": True,
         "frames": [("g", 4), ("g", 5), ("g", 6), ("g", 7), ("g", 8)]},
        # Bell up over the head, down through the floor, and the recovery.
        {"name": "attack", "fps": 13, "loop": False, "aliases": ATTACK_ALIASES,
         "frames": [("g", 9), ("g", 10), ("g", 11), ("g", 12), ("g", 13)]},
        # A cycle, not a swing: the whirlwind re-triggers this for as long as
        # it runs, so it has to come back round to where it started.
        {"name": "attack_spin", "fps": 16, "loop": False,
         "frames": [("g", 15), ("g", 16), ("g", 17), ("g", 16)]},
        # No hurt pose was drawn. The stagger that opens the death row reads as
        # one when it is flashed pale and never allowed to continue.
        {"name": "hurt", "fps": 12, "loop": False,
         "frames": [("g", 19), ("g", 0)],
         "tint": [(PALE, 0.35), (ROT, 0.2)]},
        {"name": "death", "fps": 8, "loop": False,
         "frames": [("g", 19), ("g", 20), ("g", 21), ("g", 22), ("g", 23)],
         "tint": [None, None, (ROT, 0.15), (ROT, 0.3), (ROT, 0.4)],
         "alpha": [1.0, 1.0, 0.95, 0.9, 0.85]},
        # The leap that ends the toll combo: bell up, and down on landing.
        {"name": "dash", "fps": 16, "loop": False,
         "frames": [("g", 10), ("g", 11), ("g", 12), ("g", 13)]},
    ]


def portrait(image: Image.Image, frames: list[dict], index: int, size: int = 96) -> Image.Image:
    """Head-and-shoulders bust for the boss bar / codex."""
    frame = frames[index]
    crop = image.crop(frame["box"])
    head = crop.crop((0, 0, crop.width, max(1, int(crop.height * 0.52))))
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

    source = Path(sys.argv[1])
    print("slicing source artwork...")
    image, frames = slice_ghoul(source)
    print(f"  {len(frames)} frames, tallest {max(f['h'] for f in frames)}px, "
          f"widest {max(f['w'] for f in frames)}px")

    out_dir = ROOT / "Assets" / "sprites" / "bosses" / NAME
    out_dir.mkdir(parents=True, exist_ok=True)

    sheet, meta = build_sheet({"g": (image, frames)}, layout(), CELL, COLUMNS, FEET_MARGIN)
    meta["image"] = f"{NAME}.png"
    sheet.save(out_dir / f"{NAME}.png")
    (out_dir / f"{NAME}.json").write_text(json.dumps(meta, indent=2) + "\n")

    portrait(image, frames, 0).save(out_dir / f"{NAME}_portrait.png")
    print(f"  {NAME}: {sheet.width}x{sheet.height}, {len(meta['animations'])} anims")


if __name__ == "__main__":
    main()

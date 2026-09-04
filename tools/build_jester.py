#!/usr/bin/env python3
"""Build the Jester's sprite sheet from the supplied Dark Jester artwork.

    python3 tools/build_jester.py "<DarkJester.png>"

The source is a 3072x3072 reference sheet: four direction blocks (front, back,
left, right), each holding idle / walk / run / hit / death, wrapped in title
text, row labels and a legend table. Only the RIGHT block is used — the game
draws every Hunter facing right and mirrors for left — so the block is cut out
by hand-measured bounds rather than by tools/spritecut.py's band finder, which
would happily read the headline text as a row of characters.

Two things about the artwork are worth knowing:

* Its rows disagree about how big the Jester is. The idle row is drawn some
  16% smaller than the run row below it, so the character would grow the
  moment you pressed a key. IDLE_SCALE pulls that row back into line.
* Every row sits on a painted ground line. It is attached to the feet, so the
  shadow trim in spritecut cannot see it as a detached blob; the row bounds
  below stop short of it, and what still slips through — the scrap of it the
  flood cannot reach, walled in between two legs — is scrubbed per frame.

Bounds are measured against the supplied image and are stable as long as that
image does not change.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image  # noqa: E402

from spritecut import _runs, _tighten, build_sheet, strip_background  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CELL = 64
COLUMNS = 5
# 64 - 6 puts the feet on y=58, where every other Hunter's sheet has them.
FEET_MARGIN = 6

# The RIGHT block, in source pixels. x starts past the row labels; each row
# ends above its painted ground line.
BLOCK_X = 360
ROWS = {
    "idle": (2058, 2199),
    "walk": (2204, 2368),   # 0-3 walk, 4-8 run
    "floor": (2398, 2563),  # 0-2 hit, 3-7 death
}

# The idle row is drawn smaller than the rest of the block. Matched on the
# standing figure's height, then eased off a little: the idle pose is also
# chunkier, and scaling it all the way gives it a head the run row never has.
IDLE_SCALE = 1.12

# How deep under a standing figure the ground line and the backdrop trapped
# above it reach, in source pixels.
GROUND_LINE = 34


def scrub_ground(px, box: tuple[int, int, int, int]) -> None:
    """Erase the ground line the flood could not reach.

    Only the bottom sliver of a frame, and only pixels that are both bright and
    grey: the ground line is painted backdrop, while the Jester's own whites —
    the face paint, the eyes — sit well above this, and his blood is saturated.

    A figure on its feet is cut to GROUND_LINE, deep enough to reach the pocket
    of backdrop walled in between two legs. A corpse — wider than it is tall —
    gets a tenth of its own height instead: it lies along the line, and its
    painted face would be inside a deeper cut.
    """
    x0, y0, x1, y1 = box
    standing = (y1 - y0) > (x1 - x0)
    depth = GROUND_LINE if standing else max(3, round((y1 - y0) * 0.1))
    for y in range(max(y0, y1 - depth), y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a and min(r, g, b) > 150 and max(r, g, b) - min(r, g, b) < 40:
                px[x, y] = (0, 0, 0, 0)


def cut_rows(image: Image.Image) -> dict[str, list[dict]]:
    """Every figure of the RIGHT block, per row, left to right."""
    px = image.load()
    width, _ = image.size
    out: dict[str, list[dict]] = {}
    for name, (y0, y1) in ROWS.items():
        column_profile = [
            sum(1 for y in range(y0, y1) if px[x, y][3] > 24)
            for x in range(width)
        ]
        for x in range(BLOCK_X):
            column_profile[x] = 0

        frames = []
        for x0, x1 in _runs(column_profile, 18):
            box = _tighten(px, (x0, y0, x1, y1))
            if box is None:
                continue

            # Scrubbing can free the bottom rows, so measure the frame after it:
            # the feet, not the ground line, are what every cell is pinned by.
            scrub_ground(px, box)
            box = _tighten(px, box)
            if box is None:
                continue

            frames.append({"box": box, "w": box[2] - box[0], "h": box[3] - box[1]})

        out[name] = frames

    return out


def layout(rows: dict[str, list[dict]]) -> list[dict]:
    """What each figure is for.

    The sheet's own labels promise eight walk and eight run frames; what it
    actually drew is four walking poses and five running ones, so the run row
    is the five real strides rather than a padded eight.
    """
    idle = [("idle", i) for i in range(4)]
    run = [("walk", i) for i in range(4, 9)]
    return [
        {"name": "idle", "fps": 7, "loop": True, "scale": IDLE_SCALE, "frames": idle},
        {"name": "run", "fps": 13, "loop": True, "frames": run},
        {"name": "hurt", "fps": 15, "loop": False,
         "frames": [("floor", 0), ("floor", 1), ("floor", 2)]},
        {"name": "death", "fps": 10, "loop": False,
         "frames": [("floor", i) for i in range(3, 8)]},
        # No dodge was drawn. The deepest walk lean starts it, the run's own
        # extended strides carry it. Five frames at 18fps keeps the roll the
        # same length it was, and the roll's length is the i-frame window.
        {"name": "dash", "fps": 18, "loop": False,
         "frames": [("walk", 3), ("walk", 4), ("walk", 6), ("walk", 7), ("walk", 8)]},
    ]


def portrait(image: Image.Image, frame: dict, size: int = 96) -> Image.Image:
    """Head-and-shoulders bust, kept beside the sheet like every other cast member."""
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

    source = strip_background(Image.open(Path(sys.argv[1])))
    rows = cut_rows(source)
    for name, frames in rows.items():
        print(f"  {name}: {len(frames)} figures")

    sources = {name: (source, frames) for name, frames in rows.items()}
    sheet, meta = build_sheet(sources, layout(rows), CELL, COLUMNS, FEET_MARGIN)
    meta["image"] = "jester.png"

    out_dir = ROOT / "Assets" / "sprites" / "characters" / "jester"
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet.save(out_dir / "jester.png")
    (out_dir / "jester.json").write_text(json.dumps(meta, indent=2) + "\n")
    portrait(source, rows["idle"][0]).save(out_dir / "jester_portrait.png")
    print(f"  jester: {sheet.width}x{sheet.height}, {len(meta['animations'])} anims")


if __name__ == "__main__":
    main()

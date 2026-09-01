#!/usr/bin/env python3
"""Cut a hand-supplied sprite sheet into the uniform grid Godot expects.

Sheets that come out of an image generator are not grids: the figures sit
wherever they landed, at different sizes, on a near-white background, usually
with a painted shadow underneath. SpriteSheetCache needs fixed cells and a
fixed origin, so this finds each figure and re-lays them out.

    python3 tools/spritecut.py detect "sheet.png"

`detect` reports what it found in reading order, so a manifest can be written
against stable indices before anything is exported. `slice_sheet` and
`build_sheet` are the API the per-character build scripts use.

Two decisions worth knowing about:

* Background removal floods in from the borders rather than thresholding on
  brightness. These characters have white hair, and a threshold eats it.
* Figures are separated by projection, not by connected components. Capes and
  flames overlap between neighbours, so components merge whole rows into one
  blob; a column profile still shows a clean valley between two characters.
"""
from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image

# How far a pixel may sit from the corner colour and still count as backdrop.
BG_TOLERANCE = 34
# Vertical run of empty rows that ends a band of figures. Kept short because
# painted ground shadows sit in the gap between two rows of figures and break
# it into pieces; the per-frame shadow trim cleans them up afterwards.
BAND_GAP = 14
# Horizontal run of empty columns that ends a figure.
COLUMN_GAP = 18
# A run wider than this multiple of the median is two figures that touch.
SPLIT_RATIO = 1.55
# Below this mean saturation, a detached blob under the feet is a painted grey
# shadow rather than part of the character. Blood splatter stays.
SHADOW_SATURATION = 0.20


def _is_background(pixel, reference) -> bool:
    return (
        abs(pixel[0] - reference[0]) <= BG_TOLERANCE
        and abs(pixel[1] - reference[1]) <= BG_TOLERANCE
        and abs(pixel[2] - reference[2]) <= BG_TOLERANCE
    )


def strip_background(image: Image.Image) -> Image.Image:
    """Flood the backdrop away from every border pixel, leaving alpha 0."""
    image = image.convert("RGBA")
    width, height = image.size
    px = image.load()
    reference = px[0, 0]

    seen = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if not (0 <= x < width and 0 <= y < height):
            continue

        index = y * width + x
        if seen[index]:
            continue

        seen[index] = 1
        if not _is_background(px[x, y], reference):
            continue

        px[x, y] = (0, 0, 0, 0)
        queue.append((x + 1, y))
        queue.append((x - 1, y))
        queue.append((x, y + 1))
        queue.append((x, y - 1))

    return image


def _runs(profile: list[int], min_gap: int) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    start = None
    gap = 0
    for index, value in enumerate(profile):
        if value > 0:
            if start is None:
                start = index
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                out.append((start, index - gap + 1))
                start = None
                gap = 0

    if start is not None:
        out.append((start, len(profile)))

    return out


def _split_wide(profile: list[int], run: tuple[int, int], pieces: int) -> list[tuple[int, int]]:
    """Cut an over-wide run at its deepest valleys.

    Two characters whose capes touch have no empty column between them, but the
    profile still dips hard where one ends and the next begins.
    """
    start, end = run
    width = end - start
    step = width / pieces
    cuts = []
    for k in range(1, pieces):
        centre = start + int(step * k)
        window = max(6, int(step * 0.22))
        low = min(range(centre - window, centre + window + 1),
                  key=lambda x: profile[x] if 0 <= x < len(profile) else 10 ** 9)
        cuts.append(low)

    bounds = [start] + cuts + [end]
    return [(bounds[i], bounds[i + 1]) for i in range(len(bounds) - 1)]


def _tighten(px, box: tuple[int, int, int, int]) -> tuple[int, int, int, int] | None:
    """Shrink a box to the pixels actually inside it."""
    x0, y0, x1, y1 = box
    min_x, min_y, max_x, max_y = x1, y1, x0, y0
    for y in range(y0, y1):
        for x in range(x0, x1):
            if px[x, y][3] > 24:
                min_x, max_x = min(min_x, x), max(max_x, x)
                min_y, max_y = min(min_y, y), max(max_y, y)

    if max_x < min_x:
        return None

    return (min_x, min_y, max_x + 1, max_y + 1)


def _drop_grey_shadow(px, box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """Trim a detached, desaturated blob off the bottom of a frame."""
    x0, y0, x1, y1 = box
    rows = [any(px[x, y][3] > 24 for x in range(x0, x1)) for y in range(y0, y1)]

    # Largest empty run in the lower half is the gap above the shadow.
    best = None
    start = None
    for index, filled in enumerate(rows):
        if not filled:
            if start is None:
                start = index
        elif start is not None:
            if index - start >= 3 and start > len(rows) * 0.55:
                if best is None or index - start > best[1] - best[0]:
                    best = (start, index)
            start = None

    if best is None:
        return box

    tail_y0 = y0 + best[1]
    saturation_sum = 0.0
    count = 0
    for y in range(tail_y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a <= 24:
                continue

            high, low = max(r, g, b), min(r, g, b)
            saturation_sum += 0.0 if high == 0 else (high - low) / high
            count += 1

    if count == 0 or saturation_sum / count >= SHADOW_SATURATION:
        return box

    return (x0, y0, x1, y0 + best[0])


def slice_sheet(path: Path, expected: dict[int, int] | None = None) -> list[dict]:
    """Every figure on the sheet, in reading order.

    `expected` maps a band index to how many figures it should hold, which is
    how an over-wide run gets split at the right count.
    """
    image = strip_background(Image.open(path))
    width, height = image.size
    px = image.load()

    row_profile = [sum(1 for x in range(width) if px[x, y][3] > 24) for y in range(height)]
    bands = _runs(row_profile, BAND_GAP)

    frames: list[dict] = []
    for band_index, (y0, y1) in enumerate(bands):
        column_profile = [sum(1 for y in range(y0, y1) if px[x, y][3] > 24) for x in range(width)]
        runs = _runs(column_profile, COLUMN_GAP)
        widths = sorted(r[1] - r[0] for r in runs)
        median = widths[len(widths) // 2] if widths else 1

        want = expected.get(band_index) if expected else None
        if want is None:
            # Guess from the median: anything much wider than its neighbours is
            # two characters whose capes touch.
            exploded: list[tuple[int, int]] = []
            for run in runs:
                span = run[1] - run[0]
                pieces = max(1, round(span / median)) if span > median * SPLIT_RATIO else 1
                exploded.extend(_split_wide(column_profile, run, pieces) if pieces > 1 else [run])
        else:
            # A known count beats the guess. One frame can legitimately be far
            # wider than the rest — a cast surrounded by a ring of blood — and
            # the median rule cuts that one in half.
            exploded = list(runs)
            guard = 0
            while len(exploded) < want and guard < 24:
                guard += 1
                widest = max(range(len(exploded)), key=lambda k: exploded[k][1] - exploded[k][0])
                run = exploded.pop(widest)
                exploded[widest:widest] = _split_wide(column_profile, run, 2)

            if len(exploded) != want:
                print(f"[spritecut] band {band_index}: found {len(exploded)}, expected {want}")

        for column_index, (x0, x1) in enumerate(exploded):
            box = _tighten(px, (x0, y0, x1, y1))
            if box is None:
                continue

            box = _drop_grey_shadow(px, box)
            frames.append({
                "index": len(frames),
                "band": band_index,
                "column": column_index,
                "box": box,
                "w": box[2] - box[0],
                "h": box[3] - box[1],
            })

    return frames


def build_sheet(sources: dict[str, tuple[Image.Image, list[dict]]], layout: list[dict],
                cell: int, columns: int, feet_margin: int = 4) -> tuple[Image.Image, dict]:
    """Lay chosen frames out on a uniform grid, one animation per row.

    Every frame is scaled by ONE factor shared across all sources, so the sizes
    the artist drew survive: a powered-up second phase drawn bigger stays
    bigger. Each frame is then pinned by its feet to the same line in its cell,
    which is what makes the character stop bobbing between animations.

    A layout entry names its frames as (source, index) pairs, and may carry
    per-frame `alpha`, `offset` and `tint` lists — that is how the death and
    hurt rows are built out of poses the sheet never actually contained.
    """
    used: list[dict] = []
    for entry in layout:
        for source_key, frame_index in entry["frames"]:
            used.append(sources[source_key][1][frame_index])

    tallest = max((f["h"] for f in used), default=1)
    widest = max((f["w"] for f in used), default=1)
    scale = min((cell - feet_margin * 2) / tallest, cell / widest)

    sheet = Image.new("RGBA", (columns * cell, len(layout) * cell), (0, 0, 0, 0))
    animations: dict[str, dict] = {}

    for row, entry in enumerate(layout):
        indices = []
        for column, (source_key, frame_index) in enumerate(entry["frames"]):
            image, frames = sources[source_key]
            frame = frames[frame_index]
            crop = image.crop(frame["box"])
            crop = crop.resize(
                (max(1, round(crop.width * scale)), max(1, round(crop.height * scale))),
                Image.LANCZOS,
            )
            crop = _sharpen_alpha(crop)

            tint = entry.get("tint", [])
            if column < len(tint) and tint[column] is not None:
                crop = _tint(crop, *tint[column])

            alpha = entry.get("alpha", [])
            if column < len(alpha):
                crop = _fade(crop, alpha[column])

            dx, dy = entry.get("offset", [])[column] if column < len(entry.get("offset", [])) else (0, 0)
            x = column * cell + (cell - crop.width) // 2 + dx
            y = row * cell + (cell - feet_margin - crop.height) + dy
            sheet.alpha_composite(crop, (x, y))
            indices.append(row * columns + column)

        animations[entry["name"]] = {
            "row": row,
            "from": indices[0],
            "to": indices[-1],
            "frames": indices,
            "frameCount": len(indices),
            "fps": entry.get("fps", 10),
            "loop": entry.get("loop", False),
        }
        for alias in entry.get("aliases", []):
            animations[alias] = dict(animations[entry["name"]])

    meta = {
        "frameWidth": cell,
        "frameHeight": cell,
        "columns": columns,
        "rows": len(layout),
        "facing": "right",
        "pixelArt": True,
        "origin": {"x": cell * 0.5, "y": float(cell - feet_margin)},
        "animations": animations,
    }
    return sheet, meta


def _tint(image: Image.Image, colour: tuple[int, int, int], amount: float) -> Image.Image:
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue

            px[x, y] = (
                round(r + (colour[0] - r) * amount),
                round(g + (colour[1] - g) * amount),
                round(b + (colour[2] - b) * amount),
                a,
            )

    return image


def _fade(image: Image.Image, alpha_scale: float) -> Image.Image:
    if alpha_scale >= 1.0:
        return image

    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (r, g, b, round(a * alpha_scale))

    return image


def _sharpen_alpha(image: Image.Image, threshold: int = 90) -> Image.Image:
    """Harden the alpha edge a resample softened, so cells do not halo."""
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue

            px[x, y] = (r, g, b, 0 if a < threshold else (255 if a > 210 else a))

    return image


def main() -> None:
    if len(sys.argv) < 3 or sys.argv[1] != "detect":
        print(__doc__)
        raise SystemExit(1)

    path = Path(sys.argv[2])
    frames = slice_sheet(path)
    print(f"{path.name}: {len(frames)} frames")
    for frame in frames:
        x0, y0, x1, y1 = frame["box"]
        print(f"  [{frame['index']:2d}] band {frame['band']} col {frame['column']}  "
              f"box=({x0},{y0},{x1},{y1})  {frame['w']}x{frame['h']}")


if __name__ == "__main__":
    main()

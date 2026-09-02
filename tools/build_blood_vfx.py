#!/usr/bin/env python3
"""Build the Crimson Voivode's blood VFX sheets.

    python3 tools/build_blood_vfx.py pool "<BloodPoolTopDown.png>"
    python3 tools/build_blood_vfx.py aura "<BloodAura.png>"

Both sources are contact sheets of one effect over time, and both get the same
treatment, which is what they share this file for:

* The frames are found by row band and column run rather than cut on a rigid
  grid. Both sheets look like clean grids and neither quite is — frames drift
  a few pixels across the cell boundaries, and on the aura sheet the two lower
  rows touch outright.
* Every frame is anchored on the EFFECT, not on the frame. Droplets fly up and
  fall back, so a frame's bounding box grows and shrinks by a third over the
  animation; centring on that box makes the blood slosh sideways and bob while
  it is supposed to be lying on the floor. The anchor is the centre of the
  thing that has to hold still.
* One scale for the whole sheet, chosen so the effect's radius lands on a
  documented fraction of the cell. Both effects are hit-tested against their own
  radius in GDScript, and the point of using artwork at all is that the blood
  you see is the shape that hits you.

The aura additionally prints its per-frame growth curve. BloodPulseAura.gd
carries that table so the damage front travels with the drawn front rather than
with a linear guess at it.
"""
from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image  # noqa: E402

from build_bat_boss import _split_to_count  # noqa: E402
from spritecut import _runs, strip_background  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------
def _bands(px, width: int, height: int, gap: int = 10) -> list[tuple[int, int]]:
    rows = [sum(1 for x in range(width) if px[x, y][3] > 24) for y in range(height)]
    return [r for r in _runs(rows, gap)]


def _frames(px, width: int, height: int, per_band: int | None = None) -> list[tuple[int, int, int, int]]:
    out: list[tuple[int, int, int, int]] = []
    for y0, y1 in _bands(px, width, height):
        profile = [sum(1 for y in range(y0, y1) if px[x, y][3] > 24) for x in range(width)]
        runs = [r for r in _runs(profile, 12)]
        if per_band is not None:
            runs = _split_to_count(profile, runs, per_band)

        for x0, x1 in runs:
            out.append((x0, y0, x1, y1))

    return out


def _largest_blob(px, box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """Bounding box of the biggest connected shape — the pool, never a droplet."""
    x0, y0, x1, y1 = box
    seen: set[tuple[int, int]] = set()
    best: list[tuple[int, int]] = []
    for sy in range(y0, y1):
        for sx in range(x0, x1):
            if (sx, sy) in seen or px[sx, sy][3] <= 24:
                continue

            queue = deque([(sx, sy)])
            seen.add((sx, sy))
            blob: list[tuple[int, int]] = []
            while queue:
                x, y = queue.popleft()
                blob.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if x0 <= nx < x1 and y0 <= ny < y1 and (nx, ny) not in seen \
                            and px[nx, ny][3] > 24:
                        seen.add((nx, ny))
                        queue.append((nx, ny))

            if len(blob) > len(best):
                best = blob

    xs = [p[0] for p in best]
    ys = [p[1] for p in best]
    return min(xs), min(ys), max(xs), max(ys)


def _disc(px, box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """Bounding box of the wide rows only — the ring on the ground.

    The aura's crown of spray reaches far higher than the ground it covers, and
    the droplets above it higher still. Only rows that are actually wide belong
    to the footprint the hit test cares about.
    """
    x0, y0, x1, y1 = box
    rows = []
    for y in range(y0, y1):
        xs = [x for x in range(x0, x1) if px[x, y][3] > 24]
        if xs and (xs[-1] - xs[0]) > (x1 - x0) * 0.45:
            rows.append((y, xs[0], xs[-1]))

    if not rows:
        return _largest_blob(px, box)

    return (min(r[1] for r in rows), rows[0][0],
            max(r[2] for r in rows), rows[-1][0])


def _compose(name: str, image: Image.Image, boxes: list, anchors: list,
             cell: int, columns: int, radius_src: float, radius_ratio: float,
             fps: int, loop: bool, anim_name: str, margin: int = 6) -> dict:
    """Lay the frames out, each with its anchor pinned to the same cell point."""
    up = max(ay - b[1] for (_, ay), b in zip(anchors, boxes)) + margin
    down = max(b[3] - ay for (_, ay), b in zip(anchors, boxes)) + margin
    half_x = max(max(ax - b[0], b[2] - ax) for (ax, _), b in zip(anchors, boxes)) + margin

    scale = (cell * radius_ratio) / radius_src
    if half_x * 2.0 * scale > cell or (up + down) * scale > cell:
        scale = min(cell / (half_x * 2.0), cell / (up + down))
        print(f"  ! cell too small for the ratio, falling back to {scale:.4f} "
              f"(radius becomes {radius_src * scale / cell:.3f} of the cell)")

    centre_x = cell / 2.0
    centre_y = (cell - (up + down) * scale) / 2.0 + up * scale
    print(f"  scale {scale:.4f} -> radius {radius_src * scale:.1f}px, "
          f"anchor at ({centre_x:.0f}, {centre_y:.0f}) in a {cell}px cell")

    rows = (len(boxes) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell, rows * cell), (0, 0, 0, 0))
    for index, (box, (ax, ay)) in enumerate(zip(boxes, anchors)):
        crop = image.crop(box)
        crop = crop.resize(
            (max(1, round(crop.width * scale)), max(1, round(crop.height * scale))),
            Image.LANCZOS)
        x = (index % columns) * cell + round(centre_x - (ax - box[0]) * scale)
        y = (index // columns) * cell + round(centre_y - (ay - box[1]) * scale)
        sheet.alpha_composite(crop, (x, y))

    meta = {
        "image": f"{name}.png",
        "frameWidth": cell,
        "frameHeight": cell,
        "columns": columns,
        "rows": rows,
        "facing": "right",
        "pixelArt": True,
        # The anchor, so SpriteSheetCache offsets the sprite to sit the effect on
        # the node's own position rather than hanging off it.
        "origin": {"x": centre_x, "y": centre_y},
        "animations": {
            anim_name: {
                "row": 0,
                "from": 0,
                "to": len(boxes) - 1,
                "frames": list(range(len(boxes))),
                "frameCount": len(boxes),
                "fps": fps,
                "loop": loop,
            }
        },
    }
    # SpriteSheetCache guarantees an "idle" row exists; naming it outright keeps
    # anything generic that reaches for one pointed at the real animation.
    if anim_name != "idle":
        meta["animations"]["idle"] = dict(meta["animations"][anim_name])

    out_dir = ROOT / "Assets" / "sprites" / "vfx" / name
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet.save(out_dir / f"{name}.png")
    (out_dir / f"{name}.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"  {name}: {sheet.width}x{sheet.height}, {len(boxes)} frames at {fps} fps")
    return meta


# ---------------------------------------------------------------------------
# Pool: a lid of blood that lies on the floor and boils. Loops forever.
# ---------------------------------------------------------------------------
POOL_CELL = 128
POOL_COLUMNS = 6
POOL_RADIUS_RATIO = 0.4
POOL_FPS = 12


def build_pool(source: Path) -> None:
    image = strip_background(Image.open(source))
    px = image.load()
    boxes = _frames(px, image.width, image.height)
    pools = [_largest_blob(px, b) for b in boxes]
    print(f"  {len(boxes)} frames")

    anchors = [((p[0] + p[2]) / 2.0, (p[1] + p[3]) / 2.0) for p in pools]
    radius = max(p[2] - p[0] + 1 for p in pools) / 2.0
    print(f"  pool radius {radius:.0f}px")
    _compose("blood_pool", image, boxes, anchors, POOL_CELL, POOL_COLUMNS,
             radius, POOL_RADIUS_RATIO, POOL_FPS, True, "pool")


# ---------------------------------------------------------------------------
# Aura: one pulse, played once, from a ripple to a crown of spray and out.
# ---------------------------------------------------------------------------
AURA_CELL = 160
AURA_COLUMNS = 4
AURA_PER_BAND = 4
AURA_RADIUS_RATIO = 0.45
AURA_FPS = 14


def build_aura(source: Path) -> None:
    image = strip_background(Image.open(source))
    px = image.load()
    boxes = _frames(px, image.width, image.height, AURA_PER_BAND)
    discs = [_disc(px, b) for b in boxes]
    print(f"  {len(boxes)} frames")

    anchors = [((d[0] + d[2]) / 2.0, (d[1] + d[3]) / 2.0) for d in discs]
    half_widths = [(d[2] - d[0]) / 2.0 for d in discs]
    half_heights = [(d[3] - d[1]) / 2.0 for d in discs]
    radius = max(half_widths)

    # Non-decreasing: a damage front that retreats is not a front. The artwork
    # dips a percent or two once the crown peaks, which is the spray settling
    # rather than the ring coming back in.
    growth: list[float] = []
    peak = 0.0
    for w in half_widths:
        peak = max(peak, w / radius)
        growth.append(round(peak, 3))

    # The ground ellipse is flatter than the crown that grows out of it; the
    # early frames, before the spray rises, are the honest read on the footprint.
    aspect = sum(half_heights[i] / half_widths[i] for i in range(3)) / 3.0

    print(f"  ring radius {radius:.0f}px, ground aspect {aspect:.3f}")
    print(f"  PULSE_GROWTH := {growth}")
    print(f"  PULSE_ASPECT := {aspect:.2f}")
    _compose("blood_aura", image, boxes, anchors, AURA_CELL, AURA_COLUMNS,
             radius, AURA_RADIUS_RATIO, AURA_FPS, False, "pulse")


def main() -> None:
    if len(sys.argv) < 3 or sys.argv[1] not in ("pool", "aura"):
        print(__doc__)
        raise SystemExit(1)

    print(f"slicing {sys.argv[1]} artwork...")
    (build_pool if sys.argv[1] == "pool" else build_aura)(Path(sys.argv[2]))


if __name__ == "__main__":
    main()

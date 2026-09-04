#!/usr/bin/env python3
"""Build the hooded lich sheet from the supplied artwork.

    python3 tools/build_dark_mage.py "<DarkMage.png>"

Two things wear this rig, and deliberately the same one: the dark mage wardens
DarkMages plants behind a Hunter who has outrun the night, and The Witchfire
Magus that turns up on wave 30 and sends them. They are the same figure at two
sizes — 0.75 for a warden, 1.9 for the boss — which is why the sheet lives under
enemies/ rather than in either one's own folder, and why re-exporting the
artwork moves both.

The source is a labelled reference sheet: four rows of poses on a pale backdrop,
each row captioned in its left margin and ruled off from the next by a solid
black line across the whole sheet. Neither the captions nor the rules are art,
and the generic slicer in spritecut.py would count both as figures, so this file
takes them out first:

* The rules are found rather than measured — a run of rows covered nearly wall
  to wall and only a few pixels thick is not a figure — and they are then used
  for the one thing they are good for: they mark exactly where one row of poses
  ends and the next begins, which is a better answer than a hardcoded pixel
  table (see build_ghoul_boss.py, which had no such luxury).
* The captions are small marks alone in the left margin. Anything in the
  leftmost LABEL_ZONE of the sheet that is a fraction of its band's height gets
  cleared; a figure fails the height test and a figure's ground shadow reaches
  well past the margin, so neither is touched.

Bands, in the order the artwork labels them:

  Walk   5  the cycle. There is no separate idle pose, so idle is built from it
  Cast   6  witchfire gathering in the off hand over four frames, then the
            summoning circle (no figure in it), then the release
  Hit    4  the stagger
  Death  6  down on one knee, collapsing, and three frames going out as flame

Frames 9 and 10 — the circle, and the release with its skull halfway across the
sheet — are sliced but appear in no animation. build_sheet scales every frame by
one factor shared across the sheet, so either of them would shrink the character
to fit itself into a cell. Neither is needed as art: the circle is drawn
in-engine by FlameEruption and the projectile by BossHomingBolt, which are the
versions that have to line up with the hitboxes. They stay in the slice so that
dropping them does not renumber everything after them.

Nothing here reads the artwork's dimensions, so a re-export at a different size
still slices. If a row comes out with the wrong count the run says so on stdout,
and BAND_COUNTS is the one place to correct it.
"""
from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image  # noqa: E402

from spritecut import (  # noqa: E402
    COLUMN_GAP,
    _drop_grey_shadow,
    _runs,
    _tighten,
    build_sheet,
    strip_background,
)

ROOT = Path(__file__).resolve().parents[1]
NAME = "dark_mage"
CELL = 160
COLUMNS = 6
FEET_MARGIN = 4

# Band index -> how many figures the artwork actually drew in it.
BAND_COUNTS = {0: 5, 1: 6, 2: 4, 3: 6}

# A separator rule: opaque across at least this share of the sheet, and no
# taller than this. The drawn rules measure 100% to the pixel, so the bar is set
# high on purpose — at 0.75 the death row qualified, because its flame bases and
# their shadows run shoulder to shoulder across 79% of the sheet. That cost four
# rows of artwork to a rule that was never there.
RULE_COVERAGE = 0.92
RULE_MAX_HEIGHT = 16
# Once a rule is found, its soft edges are swallowed down to this coverage.
RULE_EDGE_COVERAGE = 0.4

# Captions live in this share of the sheet width, and stand no taller than this
# share of their band. The first figure starts past the one and fills the other.
LABEL_ZONE = 0.08
LABEL_MAX_HEIGHT = 0.2

WITCHFIRE = (150, 92, 214)

# Every id the shared code may ask for by name. Neither the warden nor the boss
# ever swings anything, so they all land on the one cast row.
ATTACK_ALIASES = [
    "attack", "attack_slash", "attack_whip", "attack_orbs", "attack_nova",
    "shield_bash", "chain_swing", "attack_cross",
]


def _coverage(px, width: int, y: int) -> float:
    return sum(1 for x in range(width) if px[x, y][3] > 24) / float(width)


def _clear_rules(px, width: int, height: int) -> list[tuple[int, int]]:
    """Erase the separator lines. Returns the bands they leave behind."""
    covered = [_coverage(px, width, y) >= RULE_COVERAGE for y in range(height)]

    rules: list[tuple[int, int]] = []
    start = None
    for y, is_rule in enumerate(covered + [False]):
        if is_rule and start is None:
            start = y
        elif not is_rule and start is not None:
            if y - start <= RULE_MAX_HEIGHT:
                rules.append((start, y))
            start = None

    # A drawn rule has soft edges: the row above and below it are half covered,
    # which is under RULE_COVERAGE but still a visible grey line, and it ends up
    # glued to the top of whichever band comes next. Grow each rule outward
    # while the coverage stays anywhere near a line.
    grown: list[tuple[int, int]] = []
    for y0, y1 in rules:
        while y0 > 0 and _coverage(px, width, y0 - 1) >= RULE_EDGE_COVERAGE:
            y0 -= 1
        while y1 < height and _coverage(px, width, y1) >= RULE_EDGE_COVERAGE:
            y1 += 1
        grown.append((y0, y1))

    rules = grown
    for y0, y1 in rules:
        for y in range(y0, y1):
            for x in range(width):
                px[x, y] = (0, 0, 0, 0)

    # The regions the rules cut the sheet into, tightened onto their content.
    edges = [0] + [y for rule in rules for y in rule] + [height]
    bands: list[tuple[int, int]] = []
    for i in range(0, len(edges) - 1, 2):
        top, bottom = edges[i], edges[i + 1]
        rows = [y for y in range(top, bottom)
                if any(px[x, y][3] > 24 for x in range(width))]
        if rows:
            bands.append((rows[0], rows[-1] + 1))

    return bands


def _clear_label(px, width: int, band: tuple[int, int]) -> int:
    """Erase the caption from one band. Returns how many pixels went."""
    y0, y1 = band
    zone = int(width * LABEL_ZONE)
    max_height = (y1 - y0) * LABEL_MAX_HEIGHT
    cleared = 0
    seen: set[tuple[int, int]] = set()

    for sy in range(y0, y1):
        for sx in range(zone):
            if (sx, sy) in seen or px[sx, sy][3] <= 24:
                continue

            blob: list[tuple[int, int]] = []
            queue = deque([(sx, sy)])
            seen.add((sx, sy))
            while queue:
                x, y = queue.popleft()
                blob.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if not (0 <= nx < width and y0 <= ny < y1):
                        continue
                    if (nx, ny) in seen or px[nx, ny][3] <= 24:
                        continue

                    seen.add((nx, ny))
                    queue.append((nx, ny))

            right = max(x for x, _ in blob)
            top = min(y for _, y in blob)
            bottom = max(y for _, y in blob)
            if right >= zone or bottom - top > max_height:
                continue

            for x, y in blob:
                px[x, y] = (0, 0, 0, 0)

            cleared += len(blob)

    return cleared


def _smooth(profile: list[int], window: int = 5) -> list[float]:
    half = window // 2
    out: list[float] = []
    for i in range(len(profile)):
        lo, hi = max(0, i - half), min(len(profile), i + half + 1)
        out.append(sum(profile[lo:hi]) / float(hi - lo))
    return out


def _cut_positions(profile: list[int], x0: int, x1: int, count: int) -> list[int]:
    """The count-1 columns to cut a band of touching figures at.

    spritecut._split_wide assumes the pieces are evenly spaced and looks for a
    valley near each even division. On this artwork they are not: every mage
    holds its staff out to one side, the staff reaches into the next pose, and
    the whole Walk row comes back as one unbroken run 1192px wide. Cutting it in
    five equal parts lands each seam 10-16px off, which is exactly enough to
    saw a staff head off one frame and leave it floating in the next.

    So the seams are looked for instead of assumed: the thinnest columns in the
    band are where one pose ends, wherever they happen to fall. An empty column
    is the best seam there is and sorts first; failing that, the narrowest
    bridge does. Cuts are kept apart by a fraction of the average pose width so
    two of them cannot both land in the same gap.
    """
    if count <= 1 or x1 - x0 < 2:
        return []

    smooth = _smooth(profile)
    span = x1 - x0
    min_separation = span / float(count) * 0.55

    candidates: list[tuple[float, int]] = []
    gap_start = None
    for x in range(x0, x1 + 1):
        empty = x < x1 and profile[x] == 0
        if empty and gap_start is None:
            gap_start = x
        elif not empty and gap_start is not None:
            candidates.append((0.0, (gap_start + x) // 2))
            gap_start = None

    for x in range(x0 + 1, x1 - 1):
        if profile[x] == 0:
            continue
        if smooth[x] <= smooth[x - 1] and smooth[x] <= smooth[x + 1]:
            candidates.append((smooth[x], x))

    candidates.sort()
    chosen: list[int] = []
    for _, x in candidates:
        if x - x0 < min_separation or x1 - x < min_separation:
            continue
        if any(abs(x - c) < min_separation for c in chosen):
            continue

        chosen.append(x)
        if len(chosen) == count - 1:
            break

    return sorted(chosen)


def slice_labelled(path: Path) -> tuple[Image.Image, list[dict]]:
    image = strip_background(Image.open(path))
    width, height = image.size
    px = image.load()

    bands = _clear_rules(px, width, height)
    print(f"  {len(bands)} bands between rules")
    if len(bands) != len(BAND_COUNTS):
        print(f"[dark_mage] expected {len(BAND_COUNTS)} bands, found {len(bands)} — "
              f"check RULE_COVERAGE against the artwork")

    for band in bands:
        cleared = _clear_label(px, width, band)
        if cleared:
            print(f"  band {band[0]}-{band[1]}: cleared {cleared} caption px")

    frames: list[dict] = []
    for index, (y0, y1) in enumerate(bands):
        column_profile = [sum(1 for y in range(y0, y1) if px[x, y][3] > 24)
                          for x in range(width)]
        runs = list(_runs(column_profile, COLUMN_GAP))

        # A caption that survived the clear (or a stray mark beside one) is a
        # short run at the far left. Every real figure fills its band.
        if runs:
            tallest = max(max(column_profile[a:b], default=0) for a, b in runs)
            first_peak = max(column_profile[runs[0][0]:runs[0][1]], default=0)
            if first_peak < tallest * 0.3:
                print(f"  band {index}: dropped a short leading run (caption)")
                runs.pop(0)

        if not runs:
            continue

        # One span end to end, cut at the seams the profile actually shows. The
        # runs above are only used for where the content starts and stops: their
        # own boundaries are unreliable here because the poses touch.
        want = BAND_COUNTS.get(index, len(runs))
        left, right = runs[0][0], runs[-1][1]
        cuts = _cut_positions(column_profile, left, right, want)
        edges = [left] + cuts + [right]
        runs = [(edges[i], edges[i + 1]) for i in range(len(edges) - 1)]
        if len(runs) != want:
            print(f"[dark_mage] band {index}: found {len(runs)}, expected {want}")

        for x0, x1 in runs:
            box = _tighten(px, (x0, y0, x1, y1))
            if box is None:
                continue

            box = _drop_grey_shadow(px, box)
            frames.append({"box": box, "w": box[2] - box[0], "h": box[3] - box[1]})

    return image, frames


def layout() -> list[dict]:
    """0-4 walk, 5-10 cast, 11-14 hit, 15-20 death."""
    return [
        # The artwork labels this row Walk, and every frame in it has a leg
        # forward. Standing still on any of them is a lich caught mid-stride, so
        # idle is the two poses nearest a neutral stance, held slowly — the
        # contact frames at either end of the cycle.
        {"name": "idle", "fps": 3, "loop": True,
         "frames": [("m", 0), ("m", 4)]},
        {"name": "run", "fps": 9, "loop": True,
         "frames": [("m", 0), ("m", 1), ("m", 2), ("m", 3), ("m", 4)]},
        # The gather, and the frame it is released on. The circle and the fired
        # skull are engine-side, so the pose stops at the throw.
        {"name": "cast", "fps": 12, "loop": False, "aliases": ATTACK_ALIASES,
         "frames": [("m", 5), ("m", 6), ("m", 7), ("m", 8), ("m", 7)]},
        # A drawn stagger at last, rather than the death row's opening frame
        # flashed pale and cut short. No tint either: the pale key existed to
        # sell a borrowed pose as a hit, and over art that is already a hit it
        # only bleaches the first frame.
        {"name": "hurt", "fps": 12, "loop": False,
         "frames": [("m", 11), ("m", 12), ("m", 13), ("m", 14)]},
        {"name": "death", "fps": 8, "loop": False,
         "frames": [("m", 15), ("m", 16), ("m", 17), ("m", 18), ("m", 19), ("m", 20)],
         "tint": [None, None, (WITCHFIRE, 0.15), (WITCHFIRE, 0.3),
                  (WITCHFIRE, 0.4), (WITCHFIRE, 0.5)],
         "alpha": [1.0, 1.0, 0.95, 0.9, 0.8, 0.7]},
    ]


def portrait(image: Image.Image, frames: list[dict], index: int, size: int = 96) -> Image.Image:
    """Head-and-shoulders bust for the boss bar / codex."""
    frame = frames[index]
    crop = image.crop(frame["box"])
    head = crop.crop((0, 0, crop.width, max(1, int(crop.height * 0.5))))
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
    image, frames = slice_labelled(source)
    print(f"  {len(frames)} frames, tallest {max(f['h'] for f in frames)}px, "
          f"widest {max(f['w'] for f in frames)}px")

    expected = sum(BAND_COUNTS.values())
    if len(frames) != expected:
        print(f"[dark_mage] expected {expected} frames, got {len(frames)} — "
              f"check BAND_COUNTS against the artwork before trusting the sheet")

    out_dir = ROOT / "Assets" / "sprites" / "enemies" / NAME
    out_dir.mkdir(parents=True, exist_ok=True)

    sheet, meta = build_sheet({"m": (image, frames)}, layout(), CELL, COLUMNS, FEET_MARGIN)
    meta["image"] = f"{NAME}.png"
    sheet.save(out_dir / f"{NAME}.png")
    (out_dir / f"{NAME}.json").write_text(json.dumps(meta, indent=2) + "\n")

    portrait(image, frames, 0).save(out_dir / f"{NAME}_portrait.png")
    print(f"  {NAME}: {sheet.width}x{sheet.height}, {len(meta['animations'])} anims")


if __name__ == "__main__":
    main()

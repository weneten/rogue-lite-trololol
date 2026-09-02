#!/usr/bin/env python3
"""Build The Blood Moon Alpha's sprite sheet from the supplied werewolf artwork.

    python3 tools/build_wolf_boss.py "<WolfBoss.png>"

Writes over Assets/sprites/bosses/blood_moon_alpha/, on purpose: the .tres, the
.import and the uid all point there already, so replacing the art in place is
the whole swap.

The source is a directional sheet — six labelled rows, and each row holds the
same animation three times over: facing the camera, in profile, and from
behind. EnemySpriteAnimator has no notion of facing beyond flipping horizontally,
so only one of those three can be used, and the choice is not free:

* The front group is the only one drawn for all six rows. The profile group has
  no hurt frames at all and exactly one usable attack pose, and the back group
  would have the boss fighting with his back turned. So the standing animations
  are all front.
* The profile group earns its place in one animation. Its run is the wolf
  dropping to all fours and sprinting, which is precisely what the Alpha does
  when he pounces — and `dash` is a one-shot played while the leap carries him,
  the one moment his body genuinely leads. resolve_facing_x already turns him to
  face the landing, so the profile art points the right way on its own.

Two frames in the source resist slicing and are simply not used: the walk row's
profile pair touch and come out as one 280px blob, and the attack row's profile
slash detaches into a floating set of claws. Neither is in the layout, and
build_sheet scales from the frames a layout actually names, so leaving them
alone costs nothing.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image  # noqa: E402

from build_bat_boss import _split_to_count  # noqa: E402
from spritecut import _drop_grey_shadow, _runs, _tighten, build_sheet, strip_background  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
NAME = "blood_moon_alpha"
CELL = 128
FEET_MARGIN = 4

# The backdrop is a near-black navy. The wolf is charcoal grey and its shadowed
# fur is nearly as dark, so the default tolerance of 34 floods straight through
# it — the same trap the bat sheet set. Ten is comfortably clear of the pelt.
BG_TOLERANCE = 10

# y0, y1, how many figures. Three groups of three per row (front, profile,
# back), except hurt, which was only drawn twice over, and death, which ends in
# a five-frame corpse.
BANDS = [
    (17, 177, 9),    # 0-8    idle
    (192, 352, 9),   # 9-17   walk
    (366, 520, 9),   # 18-26  run
    (533, 683, 9),   # 27-35  attack
    (703, 848, 6),   # 36-41  hurt
    (864, 1000, 8),  # 42-49  death
]

# The row captions are light text sitting above the first figure of each band,
# well clear of it, so one rectangle per band takes them out.
LABEL_X = (14, 152)
LABEL_HEIGHT = 27

PALE = (255, 240, 235)

ATTACK_ALIASES = [
    "attack_slash", "attack_whip", "attack_orbs", "shield_bash",
    "chain_swing", "attack_spin", "attack_nova", "attack_cross",
]


def slice_wolf(path: Path) -> tuple[Image.Image, list[dict]]:
    image = strip_background(Image.open(path), BG_TOLERANCE)
    px = image.load()

    for y0, _, _ in BANDS:
        for y in range(y0, min(y0 + LABEL_HEIGHT, image.height)):
            for x in range(*LABEL_X):
                px[x, y] = (0, 0, 0, 0)

    frames: list[dict] = []
    for y0, y1, want in BANDS:
        profile = [sum(1 for y in range(y0, y1) if px[x, y][3] > 24) for x in range(image.width)]
        runs = _split_to_count(profile, [r for r in _runs(profile, 14)], want)
        start = len(frames)
        for x0, x1 in runs:
            box = _tighten(px, (x0, y0, x1, y1))
            if box is None:
                continue

            box = _drop_grey_shadow(px, box)
            frames.append({"box": box, "w": box[2] - box[0], "h": box[3] - box[1]})

        if len(frames) - start != want:
            print(f"[wolf] band {y0}-{y1}: found {len(frames) - start}, expected {want}")

    return image, frames


def layout() -> list[dict]:
    """Front group unless noted; see the module docstring for why."""
    return [
        {"name": "idle", "fps": 6, "loop": True,
         "frames": [("w", 0), ("w", 1), ("w", 2)]},
        {"name": "run", "fps": 10, "loop": True,
         "frames": [("w", 18), ("w", 19), ("w", 20)]},
        # 29 carries the drawn slash arc, so it is the frame the hit lands on.
        {"name": "attack", "fps": 12, "loop": False, "aliases": ATTACK_ALIASES,
         "frames": [("w", 27), ("w", 28), ("w", 29), ("w", 32)]},
        {"name": "hurt", "fps": 12, "loop": False,
         "frames": [("w", 36), ("w", 37)],
         # Lighter than the ghoul's flash: this pelt is charcoal, and the same
         # 0.35 that read as a flinch on pale skin washed the wolf out to a
         # silhouette.
         "tint": [(PALE, 0.22), None]},
        # Staggers, falls, and settles: three on his feet and five on the floor.
        {"name": "death", "fps": 9, "loop": False,
         "frames": [("w", 42), ("w", 43), ("w", 44), ("w", 45),
                    ("w", 46), ("w", 47), ("w", 48), ("w", 49)]},
        # The profile sprint — the pounce, and the only place the side group is
        # both complete and the right thing to be looking at.
        {"name": "dash", "fps": 14, "loop": False,
         "frames": [("w", 21), ("w", 22), ("w", 23), ("w", 22)]},
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

    print("slicing source artwork...")
    image, frames = slice_wolf(Path(sys.argv[1]))
    rows = layout()
    used = sorted({i for entry in rows for _, i in entry["frames"]})
    print(f"  {len(frames)} frames sliced, {len(used)} used")
    print(f"  tallest used {max(frames[i]['h'] for i in used)}px, "
          f"widest used {max(frames[i]['w'] for i in used)}px")

    columns = max(len(entry["frames"]) for entry in rows)
    out_dir = ROOT / "Assets" / "sprites" / "bosses" / NAME
    out_dir.mkdir(parents=True, exist_ok=True)

    sheet, meta = build_sheet({"w": (image, frames)}, rows, CELL, columns, FEET_MARGIN)
    meta["image"] = f"{NAME}.png"
    sheet.save(out_dir / f"{NAME}.png")
    (out_dir / f"{NAME}.json").write_text(json.dumps(meta, indent=2) + "\n")

    portrait(image, frames, 0).save(out_dir / f"{NAME}_portrait.png")
    print(f"  {NAME}: {sheet.width}x{sheet.height}, {len(meta['animations'])} anims")


if __name__ == "__main__":
    main()

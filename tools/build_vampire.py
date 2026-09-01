#!/usr/bin/env python3
"""Build the Crimson Voivode's two sprite sheets from the supplied artwork.

    python3 tools/build_vampire.py "<phase1.png>" "<phase2.png>"

The source sheets are hand/AI art, not grids, so tools/spritecut.py finds the
figures and this file says what each one is for. Frame indices below come from
`python3 tools/spritecut.py detect <sheet>` and are stable as long as the
source images do not change.

Both phases share one scale factor, so the phase-2 vampire — drawn larger and
wreathed in blood-fire — really is bigger on screen than the phase-1 one.

The sources carry no hurt or death poses, so those rows are assembled here out
of existing poses plus per-frame tint, fade and offset: a vampire coming apart
should sink and thin out into red mist, which is a compositing job rather than
something the artwork needed to contain.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image  # noqa: E402

from spritecut import build_sheet, slice_sheet, strip_background  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CELL = 128
COLUMNS = 6
FEET_MARGIN = 4

# How many figures each band of each source holds. Counted off the artwork;
# without it the slicer halves the wide blood-ring cast frame.
PHASE1_BANDS = {0: 5, 1: 7, 2: 6}
PHASE2_BANDS = {0: 7, 1: 7}

CRIMSON = (150, 20, 30)
WHITE = (255, 240, 240)

ATTACK_ALIASES = [
    "attack_slash", "attack_whip", "attack_orbs", "shield_bash",
    "chain_swing", "attack_spin", "attack_nova", "attack_cross",
]


def phase1_layout() -> list[dict]:
    """p1 frames: 0-3 idle, 4 blood-ring cast, 5-10 fly, 11 stand, 12-17 ignite."""
    return [
        {"name": "idle", "fps": 7, "loop": True,
         "frames": [("p1", 0), ("p1", 1), ("p1", 2), ("p1", 3)]},
        {"name": "run", "fps": 12, "loop": True,
         "frames": [("p1", 5), ("p1", 6), ("p1", 7), ("p1", 8), ("p1", 9), ("p1", 10)]},
        # The ignition sequence doubles as his cast: arms open, blood rises.
        {"name": "attack", "fps": 12, "loop": False, "aliases": ATTACK_ALIASES,
         "frames": [("p1", 12), ("p1", 13), ("p1", 14), ("p1", 15), ("p1", 16), ("p1", 17)]},
        {"name": "hurt", "fps": 12, "loop": False,
         "frames": [("p1", 11), ("p1", 0)],
         "tint": [(WHITE, 0.5), (CRIMSON, 0.25)]},
        {"name": "death", "fps": 8, "loop": False,
         "frames": [("p1", 11), ("p1", 0), ("p1", 0), ("p1", 0), ("p1", 0)],
         "tint": [(CRIMSON, 0.15), (CRIMSON, 0.3), (CRIMSON, 0.45), (CRIMSON, 0.6), (CRIMSON, 0.75)],
         "alpha": [1.0, 0.85, 0.6, 0.35, 0.12],
         "offset": [(0, 0), (0, 3), (0, 8), (0, 15), (0, 22)]},
        # Used for the shadow step and any other one-shot the boss asks for.
        {"name": "dash", "fps": 16, "loop": False,
         "frames": [("p1", 5), ("p1", 7), ("p1", 9), ("p1", 10)]},
    ]


def phase2_layout() -> list[dict]:
    """p2 frames: 0-6 hovering ablaze, 7-9 lunging, 10 turning, 11-13 back."""
    return [
        {"name": "idle", "fps": 8, "loop": True,
         "frames": [("p2", 0), ("p2", 1), ("p2", 2), ("p2", 3), ("p2", 4), ("p2", 5)]},
        {"name": "run", "fps": 10, "loop": True,
         "frames": [("p2", 7), ("p2", 8), ("p2", 9)]},
        # No cast pose was drawn for phase two, but the last ignition frames
        # are already fully ablaze, so they read as this phase, not the last.
        {"name": "attack", "fps": 12, "loop": False, "aliases": ATTACK_ALIASES,
         "frames": [("p1", 14), ("p1", 15), ("p1", 16), ("p1", 17), ("p2", 6), ("p2", 4)]},
        {"name": "hurt", "fps": 12, "loop": False,
         "frames": [("p2", 0), ("p2", 1)],
         "tint": [(WHITE, 0.5), (CRIMSON, 0.25)]},
        {"name": "death", "fps": 8, "loop": False,
         "frames": [("p2", 6), ("p2", 0), ("p2", 0), ("p2", 0), ("p2", 0)],
         "tint": [(CRIMSON, 0.15), (CRIMSON, 0.3), (CRIMSON, 0.5), (CRIMSON, 0.65), (CRIMSON, 0.8)],
         "alpha": [1.0, 0.85, 0.6, 0.32, 0.1],
         "offset": [(0, 0), (0, 4), (0, 10), (0, 18), (0, 26)]},
        # Turning away and gone: exactly the shadow step this phase gains.
        {"name": "dash", "fps": 14, "loop": False,
         "frames": [("p2", 10), ("p2", 11), ("p2", 12), ("p2", 13)]},
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


def export(name: str, sources: dict, layout: list[dict], portrait_source: str,
           portrait_index: int) -> None:
    out_dir = ROOT / "Assets" / "sprites" / "bosses" / name
    out_dir.mkdir(parents=True, exist_ok=True)

    sheet, meta = build_sheet(sources, layout, CELL, COLUMNS, FEET_MARGIN)
    meta["image"] = f"{name}.png"
    sheet.save(out_dir / f"{name}.png")
    (out_dir / f"{name}.json").write_text(json.dumps(meta, indent=2) + "\n")

    image, frames = sources[portrait_source]
    portrait(image, frames, portrait_index).save(out_dir / f"{name}_portrait.png")
    print(f"  {name}: {sheet.width}x{sheet.height}, {len(meta['animations'])} anims")


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        raise SystemExit(1)

    phase1_path, phase2_path = Path(sys.argv[1]), Path(sys.argv[2])
    print("slicing source artwork...")
    sources = {
        "p1": (strip_background(Image.open(phase1_path)),
               slice_sheet(phase1_path, PHASE1_BANDS)),
        "p2": (strip_background(Image.open(phase2_path)),
               slice_sheet(phase2_path, PHASE2_BANDS)),
    }
    print(f"  p1: {len(sources['p1'][1])} frames, p2: {len(sources['p2'][1])} frames")

    export("crimson_voivode", sources, phase1_layout(), "p1", 0)
    export("crimson_voivode_ascendant", sources, phase2_layout(), "p2", 0)


if __name__ == "__main__":
    main()

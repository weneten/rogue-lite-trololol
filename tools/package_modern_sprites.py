#!/usr/bin/env python3
"""Package modern 2D bases + optional video frames into Godot sprite sheets.

- Chroma-keys magenta / hot-pink backgrounds to transparency
- Builds uniform cell sheets (default 128x128)
- Writes atlas JSON compatible with SpriteSheetCache
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "Assets" / "sprites" / "_work"
CELL = 128
# Magenta key with tolerance
KEY = (255, 0, 170)
TOL = 55


def chroma_key(im: Image.Image, key=KEY, tol=TOL) -> Image.Image:
    """Remove flat magenta backdrop. Samples corners for actual bg; soft edges.
    Leaves intentional pink rim-light on the subject (darker / lower saturation).
    """
    import math

    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    corners = [px[2, 2], px[w - 3, 2], px[2, h - 3], px[w - 3, h - 3]]
    bg = [c[:3] for c in corners if c[0] > 170 and c[2] > 110 and c[1] < 160]
    if bg:
        kr = sum(c[0] for c in bg) // len(bg)
        kg = sum(c[1] for c in bg) // len(bg)
        kb = sum(c[2] for c in bg) // len(bg)
    else:
        kr, kg, kb = key
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            dist = math.sqrt((r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2)
            # flat bg: bright magenta, green not dominant, not a dark silhouette pixel
            is_bgish = r > 170 and b > 110 and g < 160 and (r + b) > g * 2.0
            if is_bgish and dist < tol:
                if dist < tol * 0.5:
                    px[x, y] = (0, 0, 0, 0)
                else:
                    alpha = int(255 * (dist - tol * 0.5) / (tol * 0.5))
                    px[x, y] = (r, g, b, min(a, max(0, alpha)))
    return im


def content_bbox(im: Image.Image, alpha_min: int = 16):
    a = im.split()[-1]
    return a.getbbox()


def fit_to_cell(im: Image.Image, cell: int = CELL, pad: float = 0.08) -> Image.Image:
    im = chroma_key(im)
    bb = content_bbox(im)
    if not bb:
        return Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    cropped = im.crop(bb)
    max_side = int(cell * (1.0 - 2 * pad))
    w, h = cropped.size
    scale = min(max_side / w, max_side / h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    cropped = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    # feet near bottom for consistent ground line
    x = (cell - nw) // 2
    y = cell - nh - int(cell * pad * 0.6)
    out.paste(cropped, (x, y), cropped)
    return out


def extract_video_frames(video: Path, out_dir: Path, fps: int = 10) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    pattern = str(out_dir / "f%03d.png")
    for p in out_dir.glob("f*.png"):
        p.unlink()
    cmd = [
        "ffmpeg", "-y", "-i", str(video),
        "-vf", f"fps={fps}",
        pattern,
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    return sorted(out_dir.glob("f*.png"))


def pick_loop_frames(paths: list[Path], count: int) -> list[Path]:
    if not paths:
        return []
    if len(paths) <= count:
        return paths
    # skip first frame (often identical to still), sample evenly across middle period
    start = max(1, len(paths) // 10)
    end = len(paths) - max(1, len(paths) // 12)
    window = paths[start:end] or paths
    if len(window) <= count:
        return window
    idxs = [round(i * (len(window) - 1) / (count - 1)) for i in range(count)]
    return [window[i] for i in idxs]


def build_sheet(
    anim_frames: dict[str, list[Image.Image]],
    out_png: Path,
    out_json: Path,
    cell: int = CELL,
    columns: int | None = None,
) -> None:
    anims_meta = {}
    rows = []
    max_cols = max((len(v) for v in anim_frames.values()), default=1)
    if columns is None:
        columns = max(6, max_cols)

    flat_index = 0
    row_i = 0
    for name, frames in anim_frames.items():
        # pad row to columns
        row_imgs = list(frames)
        while len(row_imgs) < columns:
            row_imgs.append(Image.new("RGBA", (cell, cell), (0, 0, 0, 0)))
        rows.append(row_imgs[:columns])
        n = len(frames)
        indices = list(range(flat_index, flat_index + n))
        # fps defaults by name
        if name == "idle":
            fps, loop = 6, True
        elif name in ("run", "walk"):
            fps, loop = 12, True
        elif name == "hurt":
            fps, loop = 10, False
        elif name == "death":
            fps, loop = 8, False
        else:
            fps, loop = 12, False
        anims_meta[name] = {
            "row": row_i,
            "from": indices[0] if indices else flat_index,
            "to": indices[-1] if indices else flat_index,
            "frames": indices,
            "frameCount": n,
            "fps": fps,
            "loop": loop,
        }
        flat_index += columns
        row_i += 1

    sheet_h = cell * len(rows)
    sheet_w = cell * columns
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    for ri, row in enumerate(rows):
        for ci, fr in enumerate(row):
            sheet.paste(fr, (ci * cell, ri * cell), fr)

    out_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_png)
    meta = {
        "image": out_png.name,
        "frameWidth": cell,
        "frameHeight": cell,
        "columns": columns,
        "rows": len(rows),
        "facing": "right",
        "origin": {"x": cell // 2, "y": cell - 6},
        "animations": anims_meta,
    }
    out_json.write_text(json.dumps(meta, indent=2) + "\n")
    print(f"wrote {out_png} ({sheet_w}x{sheet_h}) + {out_json}")


def _load_pose(dest_dir: Path, name: str, cell: int) -> Image.Image | None:
    for ext in (".jpg", ".png", ".jpeg", ".webp"):
        p = dest_dir / f"{name}{ext}"
        if p.exists():
            return fit_to_cell(Image.open(p), cell)
    return None


def _blend(a: Image.Image, b: Image.Image, t: float) -> Image.Image:
    """Alpha-aware crossfade between two same-size frames."""
    return Image.blend(a.convert("RGBA"), b.convert("RGBA"), max(0.0, min(1.0, t)))


def _nudge(im: Image.Image, dx: int = 0, dy: int = 0) -> Image.Image:
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (dx, dy), im)
    return out


def package_static_base(base_path: Path, dest_dir: Path, entity_id: str, cell: int = CELL):
    """Build sheet from base + optional run_pose/attack_pose keyframes."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    base = fit_to_cell(Image.open(base_path), cell)
    run_pose = _load_pose(dest_dir, "run_pose", cell)
    atk_pose = _load_pose(dest_dir, "attack_pose", cell)

    idle = [_nudge(base, 0, 0), _nudge(base, 0, -1), _nudge(base, 0, -2), _nudge(base, 0, -1)]

    if run_pose is not None:
        # idle -> run_pose -> mirrored-offset cycle for a readable run
        run = [
            base,
            _blend(base, run_pose, 0.45),
            run_pose,
            _blend(base, run_pose, 0.7),
            _nudge(run_pose, 0, -1),
            _blend(run_pose, base, 0.55),
        ]
    else:
        run = [_nudge(base, ox, -abs(i % 3)) for i, ox in enumerate([0, 2, 0, -2, 0, 2])]

    if atk_pose is not None:
        attack = [
            base,
            _blend(base, atk_pose, 0.35),
            _blend(base, atk_pose, 0.7),
            atk_pose,
            _blend(atk_pose, base, 0.4),
            base,
        ]
    else:
        attack = [_nudge(base, ox, 0) for ox in (-2, 4, 8, 4, 0, -1)]

    hurt = [_nudge(base, -2, 0), _nudge(base, 3, 2)]
    death = [
        base,
        _nudge(base, 0, 3),
        _nudge(base, 0, 8),
        Image.new("RGBA", base.size, (0, 0, 0, 0)),
    ]

    anims = {
        "idle": idle,
        "run": run,
        "attack": attack,
        "hurt": hurt,
        "death": death,
        "attack_slash": attack,
        "shield_bash": attack,
        "attack_whip": attack,
        "attack_orbs": attack,
        "attack_nova": attack,
        "dash": [
            base,
            _nudge(base, 6, 0),
            _nudge(base, 12, -1),
            _nudge(base, 8, 0),
            base,
        ],
    }

    build_sheet(
        anims,
        dest_dir / f"{entity_id}.png",
        dest_dir / f"{entity_id}.json",
        cell=cell,
        columns=6,
    )
    base.save(dest_dir / f"{entity_id}_portrait.png")


def package_from_videos(
    base_path: Path,
    video_map: dict[str, Path],
    dest_dir: Path,
    entity_id: str,
    cell: int = CELL,
    frames_per_anim: dict[str, int] | None = None,
):
    frames_per_anim = frames_per_anim or {
        "idle": 4,
        "run": 6,
        "attack": 6,
        "hurt": 2,
        "death": 4,
    }
    dest_dir.mkdir(parents=True, exist_ok=True)
    work = WORK / entity_id
    work.mkdir(parents=True, exist_ok=True)

    anims: dict[str, list[Image.Image]] = {}
    base_cell = fit_to_cell(Image.open(base_path), cell)

    for name, count in frames_per_anim.items():
        if name in video_map and video_map[name].exists():
            vdir = work / f"vid_{name}"
            paths = extract_video_frames(video_map[name], vdir, fps=10)
            picked = pick_loop_frames(paths, count)
            anims[name] = [fit_to_cell(Image.open(p), cell) for p in picked]
        else:
            # fallback: subtle nudge of base
            anims[name] = [base_cell] * count

    # aliases
    if "attack" in anims:
        for alias in ("attack_slash", "shield_bash", "attack_whip", "attack_orbs", "attack_nova"):
            anims[alias] = anims["attack"]

    build_sheet(anims, dest_dir / f"{entity_id}.png", dest_dir / f"{entity_id}.json", cell=cell, columns=6)
    base_cell.save(dest_dir / f"{entity_id}_portrait.png")


def package_weapon_icon(path: Path, dest: Path, size: int = 128):
    im = fit_to_cell(Image.open(path), size, pad=0.12)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest)
    print(f"weapon {dest}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all-static", action="store_true", help="Package all bases as static sheets")
    ap.add_argument("--entity", type=str, help="Single entity id under characters/enemies/bosses")
    ap.add_argument("--kind", choices=["characters", "enemies", "bosses"], default="characters")
    ap.add_argument("--weapons", action="store_true")
    args = ap.parse_args()

    if args.weapons:
        wdir = ROOT / "Assets" / "sprites" / "weapons"
        for p in sorted(wdir.glob("*_base.*")):
            package_weapon_icon(p, wdir / f"{p.stem.replace('_base', '')}.png")
        return

    targets = []
    if args.entity:
        targets.append((args.kind, args.entity))
    elif args.all_static:
        for kind in ("characters", "enemies", "bosses"):
            d = ROOT / "Assets" / "sprites" / kind
            for p in sorted(d.glob("*_base.*")):
                eid = p.stem.replace("_base", "")
                targets.append((kind, eid))

    for kind, eid in targets:
        base = ROOT / "Assets" / "sprites" / kind / f"{eid}_base.jpg"
        if not base.exists():
            base = ROOT / "Assets" / "sprites" / kind / f"{eid}_base.png"
        if not base.exists():
            print(f"skip missing {base}", file=sys.stderr)
            continue
        dest = ROOT / "Assets" / "sprites" / kind / eid
        package_static_base(base, dest, eid)
        print(f"ok {kind}/{eid}")


if __name__ == "__main__":
    main()

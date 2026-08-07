#!/usr/bin/env python3
"""Regenerate Nightbane's music beds.

    python3 tools/build_music.py              # everything
    python3 tools/build_music.py boss shop    # just those tracks

Writes 32 kHz stereo WAVs into Assets/Audio/music. Godot compresses them to
IMA-ADPCM on import (see the .import files), and AudioManager loops them.

Requires numpy. Everything is seeded, so a rebuild is byte-identical unless
the generators change.
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from soundforge.core import SR, master, write_wav  # noqa: E402
from soundforge.tracks import MASTER_THRESHOLD, TRACKS  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Assets" / "Audio" / "music"


def build(name: str) -> None:
    started = time.time()
    buf = master(TRACKS[name](), threshold=MASTER_THRESHOLD.get(name, 0.4))
    write_wav(OUT / f"{name}.wav", buf)
    print(f"  {name}.wav  {buf.shape[0] / SR:5.1f}s  "
          f"{buf.shape[0] * 4 / 1024 / 1024:4.1f} MB  ({time.time() - started:.1f}s)")


def main(argv: list[str]) -> int:
    wanted = argv or list(TRACKS)
    unknown = [n for n in wanted if n not in TRACKS]
    if unknown:
        print(f"unknown track(s): {', '.join(unknown)}")
        print(f"available: {', '.join(TRACKS)}")
        return 1

    started = time.time()
    print("music:")
    for name in wanted:
        build(name)
    print(f"done in {time.time() - started:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

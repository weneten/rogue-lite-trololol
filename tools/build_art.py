#!/usr/bin/env python3
"""Regenerate every piece of Nightbane's art from source.

    python3 tools/build_art.py            # everything
    python3 tools/build_art.py sprites ui # just those groups

Groups:
    sprites  character / enemy / boss sheets + portraits + atlas JSON
    weapons  32x32 inventory icons + the mounted copies carried in the arena
    items    32x32 shop relic icons
    cosmetics  loadout aura and charm chrome worn by the Hunter
    ui       panels, buttons, bars, icons, backdrop, vignette
    slots    the Jester's slot machine cabinet, lever and blood
    font     bitmap font atlases + .fnt descriptors
    theme    the Godot Theme resource
    arena    floor / wall tiles and props

Requires Pillow. Everything is deterministic, so a rebuild produces
byte-identical output unless the generators change.
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pixelforge import arena, cast, cosmetics, font, items, sheets, slots, theme, ui, weapons  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def build_sprites() -> None:
    for entry in cast.ALL:
        sheets.export(entry, ROOT)
        print(f"  {entry.group}/{entry.ident}")


def build_weapons() -> None:
    out = ROOT / "Assets" / "sprites" / "weapons"
    mounts = out / "mounted"
    out.mkdir(parents=True, exist_ok=True)
    mounts.mkdir(parents=True, exist_ok=True)
    for name, (kind, style) in weapons.CATALOG.items():
        weapons.icon(kind, style, 32).save(out / f"{name}.png")
        # The arena-facing copy, so the weapon on your character is the same
        # object as the one in the shop card.
        weapons.mount(kind, style).save(mounts / f"{name}.png")
    print(f"  {len(weapons.CATALOG)} icons + mounted copies")


def build_items() -> None:
    items.export(ROOT)
    print(f"  {len(items.ICONS)} relic icons")


def build_cosmetics() -> None:
    cosmetics.export(ROOT)
    print("  loadout aura, charm backing")


def build_ui() -> None:
    ui.export(ROOT)
    print("  panels, buttons, bars, icons, backdrop, vignette")


def build_font() -> None:
    sizes = font.export(ROOT)
    print(f"  atlases at cap heights {sizes}")


def build_theme() -> None:
    print(f"  {theme.export(ROOT).relative_to(ROOT)}")


def build_slots() -> None:
    slots.export(ROOT)
    print("  slot cabinet, lever frames, blood")


def build_arena() -> None:
    arena.export(ROOT)
    print("  floor tiles, wall tiles, props")


GROUPS = {
    "sprites": build_sprites,
    "weapons": build_weapons,
    "items": build_items,
    "cosmetics": build_cosmetics,
    "ui": build_ui,
    "slots": build_slots,
    "font": build_font,
    "theme": build_theme,
    "arena": build_arena,
}

# The theme references the font atlases and UI textures, so it goes last.
ORDER = ["font", "ui", "slots", "arena", "weapons", "items", "cosmetics", "sprites", "theme"]


def main(argv: list[str]) -> int:
    requested = argv[1:] or ORDER
    unknown = [name for name in requested if name not in GROUPS]
    if unknown:
        print(f"unknown group(s): {', '.join(unknown)}", file=sys.stderr)
        print(f"available: {', '.join(ORDER)}", file=sys.stderr)
        return 2

    for name in ORDER:
        if name not in requested:
            continue
        start = time.time()
        print(f"{name}:")
        GROUPS[name]()
        print(f"  done in {time.time() - start:.1f}s")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

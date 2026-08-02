"""Arena tiles and props.

The floor is a strip of 16x16 variants that ArenaVisuals stamps at random;
props are a second strip of loose objects. Both stay on the same palette as
the cast so nothing in the arena looks pasted in from a different game.
"""
from __future__ import annotations

import random
from pathlib import Path

from .core import Canvas, RGBA, mix, shade, with_alpha
from . import palette as P

TILE = 16
PROP = 32

FLOOR_TILES = 8
PROP_COUNT = 8


def _stone_tile(c: Canvas, ox: int, rng: random.Random, base: RGBA, joint: RGBA) -> None:
    """Irregular flagstones — a plain checker reads as a chessboard, not ground."""
    c.rect(ox, 0, TILE, TILE, base)
    for _ in range(26):
        x = ox + rng.randrange(TILE)
        y = rng.randrange(TILE)
        c.set(x, y, shade(base, rng.choice((-0.1, -0.05, 0.05, 0.09))))

    # Two or three slabs per tile, seams broken so the grid does not line up.
    split_y = rng.choice((5, 6, 7, 9, 10))
    split_x = rng.randrange(4, 12)
    c.hline(ox, ox + TILE - 1, split_y, joint)
    c.vline(ox + split_x, 0, split_y - 1, joint)
    c.vline(ox + (split_x + 7) % TILE, split_y + 1, TILE - 1, joint)

    # Lit top edge on each slab.
    c.hline(ox, ox + TILE - 1, split_y + 1, shade(base, 0.1))
    c.hline(ox, ox + TILE - 1, 0, joint)


def floor_strip(seed: int = 7) -> Canvas:
    rng = random.Random(seed)
    c = Canvas(TILE * FLOOR_TILES, TILE)
    base = P.rgb("3b3540")
    joint = P.rgb("241f28")

    for i in range(FLOOR_TILES):
        ox = i * TILE
        tone = mix(base, P.rgb("463f4a") if i % 2 else P.rgb("332e38"), 0.5)
        _stone_tile(c, ox, rng, tone, joint)

        if i == 2 or i == 5:
            # Moss creeping out of the joints.
            for _ in range(rng.randint(8, 16)):
                c.set(ox + rng.randrange(TILE), rng.randrange(TILE),
                      shade(P.ROT_DARK, rng.choice((0.0, 0.15))))
        if i == 3:
            # A crack.
            x, y = ox + 3, 1
            for _ in range(11):
                c.set(x, y, joint)
                x += rng.choice((0, 1, 1))
                y += rng.choice((1, 1, 2))
                if x >= ox + TILE or y >= TILE:
                    break
        if i == 6:
            # Old blood stain, long dried.
            c.ellipse(ox + 8, 9, 4, 3, with_alpha(P.BLOOD_DARK, 90))
            c.ellipse(ox + 6, 8, 2, 1.5, with_alpha(P.BLOOD_DARK, 120))
        if i == 7:
            for _ in range(3):
                bx, by = ox + rng.randrange(2, 13), rng.randrange(2, 13)
                c.hline(bx, bx + 2, by, P.BONE)
                c.set(bx - 1, by, P.BONE)
    return c


def _headstone(c: Canvas, x: int) -> None:
    stone = P.rgb("6a6470")
    c.ellipse(x + 16, 26, 10, 3, (0, 0, 0, 90))
    c.polygon([(x + 10, 26), (x + 10, 12), (x + 16, 8), (x + 22, 12), (x + 22, 26)], shade(stone, -0.35))
    c.polygon([(x + 12, 25), (x + 12, 13), (x + 16, 10), (x + 19, 13), (x + 19, 25)], stone)
    c.polygon([(x + 12, 24), (x + 12, 13), (x + 15, 11)], shade(stone, 0.22))
    c.vline(x + 16, 15, 21, shade(stone, -0.5))
    c.hline(x + 14, x + 18, 17, shade(stone, -0.5))


def _cross(c: Canvas, x: int) -> None:
    wood = P.R_WOOD
    c.ellipse(x + 16, 27, 8, 3, (0, 0, 0, 90))
    c.rect(x + 14, 6, 4, 21, wood.dark)
    c.rect(x + 15, 7, 2, 19, wood.core)
    c.rect(x + 8, 11, 16, 4, wood.dark)
    c.rect(x + 9, 12, 14, 2, wood.core)
    c.set(x + 15, 8, wood.light)


def _dead_tree(c: Canvas, x: int) -> None:
    bark = P.rgb("2e2620")
    c.ellipse(x + 16, 29, 9, 3, (0, 0, 0, 100))
    c.capsule((x + 16, 29), (x + 15, 12), 3.0, 1.6, bark)
    c.capsule((x + 15, 18), (x + 8, 10), 1.4, 0.5, bark)
    c.capsule((x + 15, 15), (x + 23, 7), 1.4, 0.5, bark)
    c.capsule((x + 15, 13), (x + 13, 3), 1.2, 0.5, bark)
    c.capsule((x + 10, 13), (x + 6, 8), 0.9, 0.4, bark)
    c.capsule((x + 21, 10), (x + 26, 6), 0.9, 0.4, bark)
    c.vline(x + 14, 14, 28, shade(bark, 0.2))


def _brazier(c: Canvas, x: int) -> None:
    iron = P.R_IRON
    c.ellipse(x + 16, 29, 8, 3, (0, 0, 0, 100))
    c.polygon([(x + 12, 30), (x + 20, 30), (x + 17, 22), (x + 15, 22)], iron.dark)
    c.polygon([(x + 10, 22), (x + 22, 22), (x + 20, 16), (x + 12, 16)], iron.dark)
    c.polygon([(x + 12, 21), (x + 18, 21), (x + 17, 17), (x + 13, 17)], iron.core)
    # Flame. The glow is what makes the arena feel lit rather than flat.
    c.ellipse_blend(x + 16, 13, 9, 9, with_alpha(P.EMBER, 40))
    c.polygon([(x + 13, 17), (x + 19, 17), (x + 16, 6)], P.EMBER)
    c.polygon([(x + 14, 16), (x + 18, 16), (x + 16, 9)], P.AMBER)
    c.polygon([(x + 15, 15), (x + 17, 15), (x + 16, 11)], P.CANDLE)


def _bones(c: Canvas, x: int) -> None:
    for bx, by, length in ((6, 22, 11), (14, 25, 8), (18, 19, 6)):
        c.capsule((x + bx, by), (x + bx + length, by - 2), 1.4, 1.4, P.R_BONE.dark)
        c.capsule((x + bx, by - 0.5), (x + bx + length, by - 2.5), 0.7, 0.7, P.R_BONE.core)
        c.circle(x + bx, by, 1.8, P.R_BONE.core)
        c.circle(x + bx + length, by - 2, 1.8, P.R_BONE.core)


def _rubble(c: Canvas, x: int) -> None:
    stone = P.rgb("57505e")
    for cx, cy, r in ((10, 24, 3.5), (16, 26, 4.5), (21, 23, 2.8), (14, 21, 2.2)):
        c.circle(x + cx, cy, r, shade(stone, -0.35))
        c.circle(x + cx - 1, cy - 1, r * 0.6, stone)


def _candles(c: Canvas, x: int) -> None:
    for cx, h in ((11, 6), (16, 9), (21, 5)):
        base_y = 26
        c.rect(x + cx - 1, base_y - h, 3, h, P.PARCHMENT)
        c.rect(x + cx - 1, base_y - h, 1, h, shade(P.PARCHMENT, -0.25))
        c.ellipse_blend(x + cx, base_y - h - 3, 5, 5, with_alpha(P.CANDLE, 45))
        c.polygon([(x + cx - 1, base_y - h - 1), (x + cx + 1, base_y - h - 1), (x + cx, base_y - h - 5)], P.AMBER)
        c.set(x + cx, base_y - h - 3, P.CANDLE)


def _gate(c: Canvas, x: int) -> None:
    iron = P.R_IRON
    for bx in range(x + 6, x + 27, 5):
        c.rect(bx, 8, 2, 20, iron.dark)
        c.rect(bx, 8, 1, 20, iron.core)
        c.polygon([(bx - 1, 8), (bx + 3, 8), (bx + 1, 4)], iron.core)
    c.rect(x + 5, 12, 22, 2, iron.dark)
    c.rect(x + 5, 22, 22, 2, iron.dark)


_PROPS = [_headstone, _cross, _dead_tree, _brazier, _bones, _rubble, _candles, _gate]

PICKUP = 16
PICKUP_FRAMES = 4


def pickup_strip() -> Canvas:
    """The drop every enemy leaves: a soul shard veined with gold.

    One pickup carries both the experience and the coin, so the player has a
    single thing to chase instead of two overlapping ones. Four frames of
    bob-and-glint keep it visible against a dark, busy floor.
    """
    c = Canvas(PICKUP * PICKUP_FRAMES, PICKUP)
    for i in range(PICKUP_FRAMES):
        ox = i * PICKUP
        lift = (0, -1, -2, -1)[i]
        cy = 9 + lift

        # Halo, so a small pickup still reads on a dark flagstone floor.
        c.ellipse_blend(ox + 8, cy, 6.5, 6.5, with_alpha(P.SPECTRAL, 30))
        c.ellipse(ox + 8, 13, 4, 1.5, (0, 0, 0, 80))

        crystal = [(ox + 8, cy - 5), (ox + 12, cy - 1), (ox + 8, cy + 5), (ox + 4, cy - 1)]
        c.polygon(crystal, shade(P.SPECTRAL, -0.45))
        c.polygon([(ox + 8, cy - 4), (ox + 11, cy - 1), (ox + 8, cy + 4), (ox + 5, cy - 1)], P.SPECTRAL)
        # Lit left facet.
        c.polygon([(ox + 8, cy - 4), (ox + 8, cy + 4), (ox + 5, cy - 1)], shade(P.SPECTRAL, 0.3))

        # Gold vein — the coin half of the reward, readable at a glance.
        c.line((ox + 7, cy - 3), (ox + 9, cy + 2), P.AMBER)
        c.set(ox + 9, cy + 2, P.CANDLE)

        # Glint travels around the crystal across the cycle.
        glint = ((6, -3), (7, -4), (9, -2), (6, 0))[i]
        c.set(ox + glint[0], cy + glint[1], (255, 255, 255, 255))

    c.outline_pass(P.VOID)
    return c


def prop_strip() -> Canvas:
    c = Canvas(PROP * PROP_COUNT, PROP)
    for i, fn in enumerate(_PROPS):
        fn(c, i * PROP)
    c.outline_pass(P.VOID)
    return c


def wall_strip() -> Canvas:
    """Three 16x16 wall tiles: face, capstone, and a mossy variant."""
    rng = random.Random(31)
    c = Canvas(TILE * 3, TILE)
    base = P.rgb("2b2632")
    for i in range(3):
        ox = i * TILE
        c.rect(ox, 0, TILE, TILE, base)
        for row in range(0, TILE, 5):
            offset = 0 if (row // 5) % 2 == 0 else 4
            c.hline(ox, ox + TILE - 1, row, shade(base, -0.4))
            for bx in range(offset, TILE, 8):
                c.vline(ox + bx, row, min(TILE - 1, row + 4), shade(base, -0.4))
            c.hline(ox, ox + TILE - 1, row + 1, shade(base, 0.14))
        for _ in range(18):
            c.set(ox + rng.randrange(TILE), rng.randrange(TILE), shade(base, rng.choice((-0.12, 0.1))))
        if i == 1:
            c.rect(ox, 0, TILE, 4, shade(base, 0.22))
            c.hline(ox, ox + TILE - 1, 4, P.VOID)
        if i == 2:
            for _ in range(14):
                c.set(ox + rng.randrange(TILE), rng.randrange(6, TILE), P.ROT_DARK)
    return c


def export(root: Path) -> None:
    out = root / "Assets" / "sprites" / "arena"
    out.mkdir(parents=True, exist_ok=True)
    floor_strip().save(out / "floor_tiles.png")
    wall_strip().save(out / "wall_tiles.png")
    prop_strip().save(out / "props.png")
    pickup_strip().save(out / "pickup.png")

"""Shop relic icons.

One 32x32 icon per passive item. Icons live on the same palette and the same
outline/rim-light treatment as the weapon icons, so a shop row mixing weapons
and relics reads as one set rather than two.

Each icon is drawn at final size — no downscaling anywhere, because resampling
is what turns a crisp icon set muddy. The silhouette does the work: a boot, a
bottle and a pendant have to be tellable apart in black at 32 pixels before any
colour is considered.
"""
from __future__ import annotations

from pathlib import Path

from .core import Canvas, Ramp, RGBA, shade, with_alpha
from . import palette as P

CELL = 32


# ---------------------------------------------------------------- primitives

def _cord(c: Canvas, cy: int, drop: int, color: RGBA = None) -> None:
    """The neck cord every pendant hangs from."""
    col = color or P.R_LEATHER.dark
    c.line((10, cy), (16, cy + drop), col)
    c.line((22, cy), (16, cy + drop), col)


def _bottle(c: Canvas, cx: int, top: int, bottom: int, half: float,
            glass: Ramp, fluid: RGBA, cork: bool = True) -> None:
    """Stoppered flask: neck, shoulders, body, and a lit fluid line."""
    neck_y = top + 5
    c.rect(int(cx - 2), top + 2, 4, 5, glass.dark)
    c.rect(int(cx - 1), top + 2, 2, 5, glass.core)
    if cork:
        c.rect(int(cx - 3), top - 1, 6, 4, P.R_WOOD.dark)
        c.rect(int(cx - 2), top, 4, 2, P.R_WOOD.core)

    body = [
        (cx - 2, neck_y), (cx + 2, neck_y),
        (cx + half, neck_y + 4), (cx + half, bottom - 2),
        (cx + half - 2, bottom), (cx - half + 2, bottom),
        (cx - half, bottom - 2), (cx - half, neck_y + 4),
    ]
    c.polygon(body, glass.dark)

    # Fluid fills the lower two thirds and gets its own meniscus highlight.
    level = neck_y + 6
    c.polygon(
        [(cx - half + 1, level), (cx + half - 1, level),
         (cx + half - 1, bottom - 2), (cx + half - 3, bottom - 1),
         (cx - half + 3, bottom - 1), (cx - half + 1, bottom - 2)],
        fluid,
    )
    c.hline(int(cx - half + 1), int(cx + half - 1), level, shade(fluid, 0.3))
    c.vline(int(cx - half + 1), neck_y + 4, bottom - 3, with_alpha(P.PARCHMENT, 70))


def _gem(c: Canvas, cx: int, cy: int, r: float, color: RGBA) -> None:
    """Faceted stone — a lit left face and a white glint, nothing more."""
    c.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], shade(color, -0.4))
    c.polygon([(cx, cy - r + 1), (cx + r - 1, cy), (cx, cy + r - 1), (cx - r + 1, cy)], color)
    c.polygon([(cx, cy - r + 1), (cx, cy + r - 1), (cx - r + 1, cy)], shade(color, 0.28))
    c.set(int(cx - 1), int(cy - 1), P.PARCHMENT)


def _ring_band(c: Canvas, cx: int, cy: int, r: float, metal: Ramp) -> None:
    c.ring(cx, cy, r, metal.dark, 2)
    c.ring(cx, cy, r - 0.5, metal.core, 1)
    c.set(int(cx - r + 1), int(cy - 1), metal.hi)


def _cloth_folds(c: Canvas, pts, ramp: Ramp) -> None:
    c.polygon(pts, ramp.dark)
    inner = [(x + (1 if x < 16 else -1), y) for x, y in pts]
    c.polygon(inner, ramp.core)


# -------------------------------------------------------------------- relics

def _hunters_tonic(c: Canvas) -> None:
    _bottle(c, 16, 5, 27, 6, P.R_STEEL, P.CRIMSON)
    c.rect(11, 17, 10, 4, with_alpha(P.PARCHMENT, 200))
    c.hline(13, 18, 19, P.R_LEATHER.dark)


def _grave_runner_boots(c: Canvas) -> None:
    leather = P.R_LEATHER
    for ox, lift in ((3, 2), (15, 0)):
        c.polygon([(ox + 2, 10 + lift), (ox + 8, 10 + lift), (ox + 8, 20 + lift),
                   (ox + 13, 20 + lift), (ox + 13, 25 + lift), (ox + 2, 25 + lift)], leather.dark)
        c.polygon([(ox + 3, 11 + lift), (ox + 7, 11 + lift), (ox + 7, 21 + lift),
                   (ox + 12, 21 + lift), (ox + 12, 24 + lift), (ox + 3, 24 + lift)], leather.core)
        c.hline(ox + 3, ox + 12, 24 + lift, P.R_IRON.core)      # sole
        c.hline(ox + 3, ox + 7, 14 + lift, P.R_GOLD.core)       # buckle
        c.set(ox + 5, 14 + lift, P.R_GOLD.hi)
        c.vline(ox + 3, 12 + lift, 20 + lift, leather.light)


def _vial_of_vigor(c: Canvas) -> None:
    _bottle(c, 16, 6, 27, 7, P.R_SILVER, P.BLOOD)
    # A heart suspended in the fluid: the health read, not just a red liquid.
    c.circle(14, 19, 2.4, P.CRIMSON)
    c.circle(18, 19, 2.4, P.CRIMSON)
    c.polygon([(11, 20), (21, 20), (16, 25)], P.CRIMSON)
    c.set(14, 18, P.ROSE)


def _whetstone_of_saints(c: Canvas) -> None:
    stone = Ramp(P.rgb("8b8496"), outline=P.INK)
    # The blade being honed, so the icon says "sharper" rather than "rock".
    c.polygon([(4, 6), (7, 4), (26, 15), (24, 18)], P.R_STEEL.dark)
    c.polygon([(5, 6), (7, 5), (24, 15), (23, 17)], P.R_STEEL.core)
    c.line((6, 6), (24, 16), P.R_STEEL.hi)

    c.polygon([(6, 22), (24, 13), (28, 18), (10, 27)], stone.dark)
    c.polygon([(8, 22), (23, 15), (26, 18), (11, 25)], stone.core)
    c.line((9, 21), (23, 16), stone.hi)
    for x, y in ((13, 21), (17, 19), (20, 18)):
        c.set(x, y, stone.light)
    # Sparks off the contact point.
    for sx, sy, col in ((25, 12, P.CANDLE), (28, 10, P.AMBER), (27, 14, P.CANDLE), (30, 13, P.AMBER)):
        c.set(sx, sy, col)


def _crow_feather_charm(c: Canvas) -> None:
    _cord(c, 3, 3)
    quill = P.R_CLOTH_NAVY
    # Vane first as a solid leaf, then the shaft over it and barb splits cut
    # in — building it up from lines never read as a feather at this size.
    c.polygon([(17, 5), (23, 14), (21, 24), (16, 29), (11, 22), (11, 12)], quill.dark)
    c.polygon([(17, 7), (21, 15), (19, 23), (16, 27), (13, 21), (13, 13)], quill.core)
    c.polygon([(17, 7), (16, 27), (13, 21), (13, 13)], quill.light)
    for i in range(7):
        y = 10 + i * 2
        c.line((16, y), (11 + i * 0.4, y + 3), quill.outline)
        c.line((17, y), (22 - i * 0.4, y + 3), quill.outline)
    c.line((17, 5), (16, 29), P.R_BONE.core)
    c.set(15, 10, P.MOONLIGHT)
    c.set(14, 16, P.MOONLIGHT)


def _widows_lens(c: Canvas) -> None:
    metal = P.R_GOLD
    c.circle(14, 14, 8, metal.dark)
    c.circle(14, 14, 6.2, P.rgb("2a3550"))
    c.circle(13, 13, 3.2, P.rgb("46608c"))
    c.set(12, 12, P.MOONLIGHT)
    c.ring(14, 14, 8, metal.core, 1)
    # Handle.
    c.capsule((19, 20), (27, 28), 2.0, 1.4, metal.dark)
    c.capsule((19, 20), (26, 27), 1.0, 0.6, metal.core)
    # Crosshair etched on the glass — this is the crit item.
    c.hline(9, 19, 14, with_alpha(P.CRIMSON, 190))
    c.vline(14, 9, 19, with_alpha(P.CRIMSON, 190))


def _leech_sigil(c: Canvas) -> None:
    _cord(c, 4, 5)
    metal = P.R_IRON
    c.circle(16, 18, 8, metal.dark)
    c.circle(16, 18, 6.5, metal.core)
    c.ring(16, 18, 8, metal.outline, 1)
    # A drop of blood caught in the sigil's mouth.
    c.polygon([(16, 12), (20, 19), (16, 24), (12, 19)], P.BLOOD_DARK)
    c.polygon([(16, 14), (19, 19), (16, 22), (13, 19)], P.BLOOD)
    c.set(15, 17, P.CRIMSON)


def _rusted_cuirass(c: Canvas) -> None:
    plate = P.R_RUST
    # Flared pauldrons and a neck notch: without them a breastplate silhouette
    # is indistinguishable from a barrel.
    c.polygon([(2, 11), (9, 6), (12, 10), (5, 15)], plate.dark)
    c.polygon([(30, 11), (23, 6), (20, 10), (27, 15)], plate.dark)
    c.polygon([(3, 11), (9, 8), (11, 10), (5, 13)], plate.core)
    c.polygon([(29, 11), (23, 8), (21, 10), (27, 13)], plate.core)

    c.polygon([(9, 6), (13, 6), (16, 10), (19, 6), (23, 6),
               (25, 14), (21, 27), (11, 27), (7, 14)], plate.dark)
    c.polygon([(11, 8), (13, 8), (16, 12), (19, 8), (21, 8),
               (23, 14), (20, 25), (12, 25), (9, 14)], plate.core)
    c.vline(16, 13, 25, plate.outline)
    for y in (16, 20, 23):
        c.hline(10, 22, y, shade(plate.core, -0.3))
    c.vline(11, 10, 23, plate.light)
    for x, y in ((11, 11), (21, 11), (11, 22), (21, 22)):
        c.set(x, y, P.R_IRON.hi)


def _gravedirt_pendant(c: Canvas) -> None:
    _cord(c, 4, 6)
    c.circle(16, 19, 7, P.R_BONE.dark)
    c.circle(16, 19, 5.6, P.rgb("3b3226"))
    # Loose grave dirt inside the locket.
    for x, y in ((14, 18), (17, 17), (15, 21), (18, 20), (16, 19), (13, 20)):
        c.set(x, y, P.rgb("6a5a40"))
    c.ring(16, 19, 7, P.R_GOLD.core, 1)
    c.set(13, 15, P.R_GOLD.hi)


def _embalmers_salve(c: Canvas) -> None:
    jar = Ramp(P.rgb("6f7d6a"), outline=P.INK)
    c.rect(9, 12, 14, 14, jar.dark)
    c.rect(11, 13, 10, 12, jar.core)
    c.rect(8, 8, 16, 5, P.R_BONE.dark)
    c.rect(9, 9, 14, 3, P.R_BONE.core)
    c.vline(11, 14, 24, jar.light)
    # Wax cross on the label — the healing read.
    c.rect(13, 16, 6, 6, P.PARCHMENT)
    c.hline(14, 17, 19, P.CRIMSON)
    c.vline(15, 17, 21, P.CRIMSON)


def _silver_censer(c: Canvas) -> None:
    metal = P.R_SILVER
    c.line((16, 2), (16, 9), metal.dark)
    c.circle(16, 3, 1.6, metal.core)
    c.polygon([(9, 12), (23, 12), (20, 24), (12, 24)], metal.dark)
    c.polygon([(11, 13), (21, 13), (19, 23), (13, 23)], metal.core)
    c.polygon([(10, 9), (22, 9), (20, 12), (12, 12)], metal.light)
    for y in (16, 19):
        c.hline(12, 20, y, metal.outline)
    # Holy smoke.
    for i, (x, y) in enumerate(((14, 8), (17, 6), (15, 4), (18, 3))):
        c.set(x, y, with_alpha(P.CANDLE, 190 - i * 30))


def _runed_thimble(c: Canvas) -> None:
    metal = Ramp(P.rgb("6a5a86"), outline=P.rgb("1a1028"))
    # Domed top and a flared rim, or it is just a purple brick.
    c.ellipse(16, 11, 6, 4, metal.dark)
    c.polygon([(10, 11), (22, 11), (21, 23), (11, 23)], metal.dark)
    c.ellipse(16, 24, 7, 3, metal.dark)
    c.ellipse(16, 11, 4.5, 2.8, metal.core)
    c.polygon([(12, 12), (20, 12), (19, 22), (13, 22)], metal.core)
    c.ellipse(16, 23, 5.5, 2, metal.core)
    c.ellipse(14, 10, 2, 1.2, metal.hi)

    # Dimples, then the runes glowing on top of them.
    for y in range(13, 22, 3):
        for x in range(13, 21, 3):
            c.set(x, y, metal.outline)
    for x, y in ((13, 14), (17, 16), (14, 19), (19, 13), (18, 20)):
        c.set(x, y, P.VIOLET)
        c.blend(x, y - 1, with_alpha(P.VIOLET, 110))


def _scholars_spectacles(c: Canvas) -> None:
    metal = P.R_GOLD
    for cx in (9, 23):
        c.ring(cx, 16, 6, metal.dark, 2)
        c.circle(cx, 16, 4.5, with_alpha(P.MOONLIGHT, 120))
        c.ring(cx, 16, 6, metal.core, 1)
        c.set(cx - 2, 14, P.PARCHMENT)
    c.hline(15, 17, 16, metal.core)
    c.line((3, 14), (0, 12), metal.dark)
    c.line((29, 14), (31, 12), metal.dark)


def _coin_purse(c: Canvas) -> None:
    cloth = P.R_CLOTH_NAVY
    # Coins go down first and to the side, so the purse body cannot bury them.
    for cx, cy in ((25, 8), (28, 13), (22, 4)):
        c.circle(cx, cy, 3.0, P.R_GOLD.dark)
        c.circle(cx, cy, 2.0, P.R_GOLD.core)
        c.set(cx - 1, cy - 1, P.CANDLE)

    c.ellipse(14, 22, 10, 8, cloth.dark)
    c.ellipse(13, 21, 8, 6, cloth.core)
    c.ellipse(11, 19, 4, 3, cloth.light)
    c.polygon([(9, 15), (19, 15), (18, 11), (10, 11)], cloth.dark)
    c.polygon([(10, 15), (18, 15), (17, 12), (11, 12)], cloth.core)
    c.hline(9, 19, 14, P.R_GOLD.core)      # drawstring
    c.set(19, 13, P.R_GOLD.hi)


def _shroud_of_mist(c: Canvas) -> None:
    ghost = Ramp(P.rgb("4a6f7a"), outline=P.rgb("101c22"))
    # An empty hooded cloak — the hollow cowl is what sells "you aren't there".
    _cloth_folds(c, [(16, 3), (23, 8), (26, 20), (24, 27), (20, 23),
                     (16, 28), (12, 23), (8, 27), (6, 20), (9, 8)], ghost)
    c.polygon([(16, 6), (21, 10), (21, 17), (16, 20), (11, 17), (11, 10)], P.rgb("0d1418"))
    c.polygon([(16, 8), (19, 11), (19, 16), (16, 18), (13, 16), (13, 11)], P.rgb("060a0c"))
    for y in (12, 15):
        c.hline(9, 23, y, with_alpha(P.SPECTRAL, 60))
    c.line((9, 9), (7, 21), ghost.light)
    c.line((23, 9), (25, 21), ghost.light)
    # Two cold points where a face would be.
    c.set(14, 13, P.SPECTRAL)
    c.set(18, 13, P.SPECTRAL)


def _iron_maiden_pin(c: Canvas) -> None:
    metal = P.R_IRON
    c.polygon([(16, 3), (20, 14), (16, 29), (12, 14)], metal.dark)
    c.polygon([(16, 5), (18, 14), (16, 26), (14, 14)], metal.core)
    c.vline(16, 6, 25, metal.light)
    c.circle(16, 12, 3.2, P.R_RUST.dark)
    c.circle(16, 12, 2.2, P.R_RUST.core)
    _gem(c, 16, 12, 1.6, P.CRIMSON)


def _plague_doctors_mask(c: Canvas) -> None:
    leather = P.R_LEATHER
    c.polygon([(9, 8), (23, 8), (24, 16), (18, 20), (14, 20), (8, 16)], leather.dark)
    c.polygon([(11, 10), (21, 10), (22, 16), (17, 19), (15, 19), (10, 16)], leather.core)
    # Beak.
    c.polygon([(14, 17), (18, 17), (17, 29), (15, 29)], leather.dark)
    c.polygon([(15, 18), (17, 18), (16, 27)], leather.light)
    for cx in (13, 19):
        c.circle(cx, 13, 2.8, P.R_GOLD.dark)
        c.circle(cx, 13, 1.8, P.rgb("2a3550"))
        c.set(cx - 1, 12, P.MOONLIGHT)


def _quicksilver_flask(c: Canvas) -> None:
    _bottle(c, 16, 5, 27, 7, P.R_SILVER, P.MOONLIGHT, cork=False)
    c.rect(13, 3, 6, 4, P.R_SILVER.core)
    # Motion streaks — the speed read.
    for y, x0 in ((13, 3), (18, 2), (23, 4)):
        c.hline(x0, x0 + 4, y, with_alpha(P.MOONLIGHT, 150))


def _martyrs_heart(c: Canvas) -> None:
    c.circle(11, 13, 6, P.BLOOD_DARK)
    c.circle(21, 13, 6, P.BLOOD_DARK)
    c.polygon([(4, 15), (28, 15), (16, 30)], P.BLOOD_DARK)
    c.circle(11, 13, 4.6, P.BLOOD)
    c.circle(21, 13, 4.6, P.BLOOD)
    c.polygon([(6, 15), (26, 15), (16, 28)], P.BLOOD)
    c.circle(10, 12, 2.4, P.CRIMSON)
    c.set(9, 11, P.ROSE)
    # Thorn crown wound round it.
    for x in range(5, 28, 4):
        c.set(x, 16, P.R_WOOD.dark)
        c.set(x + 1, 15, P.R_WOOD.core)


def _bloodmoon_amulet(c: Canvas) -> None:
    _cord(c, 3, 5)
    c.circle(16, 18, 9, P.R_GOLD.dark)
    c.circle(16, 18, 7.4, P.BLOOD_DARK)
    c.circle(16, 18, 6, P.CRIMSON)
    # Eclipse bite out of the moon.
    c.circle(20, 15, 5, P.BLOOD_DARK)
    c.ring(16, 18, 9, P.R_GOLD.core, 1)
    c.set(12, 16, P.ROSE)


def _duelists_glove(c: Canvas) -> None:
    leather = Ramp(P.rgb("6a4e37"), outline=P.rgb("1c1109"))
    # Separate fingers drawn as their own capsules, then the palm, then the
    # cuff — one blocky outline just reads as a brick.
    for fx, top in ((11, 4), (14, 2), (17, 3), (20, 6)):
        c.capsule((fx, top), (fx, 14), 1.6, 1.6, leather.dark)
        c.capsule((fx - 0.4, top + 1), (fx - 0.4, 13), 0.8, 0.8, leather.core)
    c.capsule((23, 11), (21, 16), 1.8, 1.8, leather.dark)   # thumb

    c.polygon([(9, 12), (23, 12), (23, 21), (9, 21)], leather.dark)
    c.polygon([(10, 13), (22, 13), (22, 20), (10, 20)], leather.core)
    c.hline(10, 21, 16, shade(leather.core, -0.3))
    c.vline(10, 13, 20, leather.light)

    # Steel cuff with the duelling stone set into it.
    c.rect(8, 21, 16, 6, P.R_SILVER.dark)
    c.rect(9, 22, 14, 4, P.R_SILVER.core)
    c.hline(9, 22, 22, P.R_SILVER.hi)
    _gem(c, 16, 24, 2.2, P.MOONLIGHT)


def _reapers_hourglass(c: Canvas) -> None:
    wood = P.R_WOOD
    c.rect(7, 4, 18, 3, wood.dark)
    c.rect(7, 25, 18, 3, wood.dark)
    c.rect(8, 5, 16, 1, wood.core)
    c.rect(8, 26, 16, 1, wood.core)
    c.polygon([(10, 7), (22, 7), (17, 16), (22, 25), (10, 25), (15, 16)], P.R_SILVER.dark)
    c.polygon([(12, 8), (20, 8), (16, 16), (20, 24), (12, 24)], P.rgb("221a2a"))
    # Sand: nearly all fallen, which is the whole joke of the item.
    c.polygon([(13, 21), (19, 21), (19, 23), (13, 23)], P.AMBER)
    c.polygon([(14, 9), (18, 9), (16, 13)], P.AMBER)
    c.vline(16, 13, 21, P.CANDLE)


def _crown_of_thorns(c: Canvas) -> None:
    wood = Ramp(P.rgb("47301f"), outline=P.rgb("160d06"))
    # Drawn as rings rather than a filled ellipse minus a hole: Canvas.set
    # ignores fully transparent writes, so there is no way to punch one out.
    for t in range(3):
        c.ring(16, 18 - t * 0.4, 11 - t, wood.dark if t else wood.core, 1)
    c.ring(16, 17, 10, wood.core, 1)
    c.ring(16, 16.5, 9.5, wood.light, 1)
    # Thorns, and a bead of blood on the longest one.
    for x, y, dx, dy in ((6, 15, -3, -4), (11, 12, -2, -5), (16, 11, 0, -6),
                         (21, 12, 2, -5), (26, 15, 3, -4), (9, 22, -3, 4), (23, 22, 3, 4)):
        c.line((x, y), (x + dx, y + dy), wood.dark)
        c.set(x + dx, y + dy, wood.light)
    c.set(16, 5, P.CRIMSON)
    c.set(16, 6, P.BLOOD)


def _ossuary_key(c: Canvas) -> None:
    metal = P.R_GOLD
    c.ring(10, 9, 5, metal.dark, 2)
    c.ring(10, 9, 4.5, metal.core, 1)
    c.capsule((12, 13), (24, 25), 2.0, 2.0, metal.dark)
    c.capsule((12, 13), (23, 24), 1.0, 1.0, metal.core)
    # Wards.
    c.line((21, 20), (26, 19), metal.dark)
    c.line((23, 23), (28, 22), metal.dark)
    c.set(8, 7, metal.hi)
    # A little skull cast into the bow.
    c.circle(10, 9, 2.2, P.R_BONE.core)
    c.set(9, 9, P.INK)
    c.set(11, 9, P.INK)


# id -> drawing routine. The keys are the PassiveItemData ids, so a missing
# icon is a KeyError at build time rather than a blank square in the shop.
ICONS = {
    "hunters_tonic": _hunters_tonic,
    "grave_runner_boots": _grave_runner_boots,
    "vial_of_vigor": _vial_of_vigor,
    "whetstone_of_saints": _whetstone_of_saints,
    "crow_feather_charm": _crow_feather_charm,
    "widows_lens": _widows_lens,
    "leech_sigil": _leech_sigil,
    "rusted_cuirass": _rusted_cuirass,
    "gravedirt_pendant": _gravedirt_pendant,
    "embalmers_salve": _embalmers_salve,
    "silver_censer": _silver_censer,
    "runed_thimble": _runed_thimble,
    "scholars_spectacles": _scholars_spectacles,
    "coin_purse_of_the_drowned": _coin_purse,
    "shroud_of_mist": _shroud_of_mist,
    "iron_maiden_pin": _iron_maiden_pin,
    "plague_doctors_mask": _plague_doctors_mask,
    "quicksilver_flask": _quicksilver_flask,
    "martyrs_heart": _martyrs_heart,
    "bloodmoon_amulet": _bloodmoon_amulet,
    "duelists_glove": _duelists_glove,
    "reapers_hourglass": _reapers_hourglass,
    "crown_of_thorns": _crown_of_thorns,
    "ossuary_key": _ossuary_key,
}


def icon(ident: str) -> Canvas:
    c = Canvas(CELL, CELL)
    ICONS[ident](c)
    c.outline_pass(P.VOID)
    c.rim_light(P.PARCHMENT, -1, -1, 40)
    return c


def export(root: Path) -> None:
    out = root / "Assets" / "sprites" / "items"
    out.mkdir(parents=True, exist_ok=True)
    for ident in ICONS:
        icon(ident).save(out / f"{ident}.png")

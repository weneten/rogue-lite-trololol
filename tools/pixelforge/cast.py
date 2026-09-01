"""Who's in the game.

One entry per hunter, enemy and boss. Silhouette first: every entry differs
in headgear, cape and stature so you can tell them apart at 44 pixels tall
before you notice a single colour.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .core import Ramp
from .rig import BodySpec
from .weapons import WeaponStyle
from . import palette as P


@dataclass
class Entry:
    ident: str
    group: str              # characters | enemies | bosses
    spec: BodySpec
    weapon_style: WeaponStyle
    swing: str = "slash"    # which attack arc to use
    cell: int = 64
    title: str = ""


def _c(ident, title, spec, wstyle, swing="slash") -> Entry:
    return Entry(ident, "characters", spec, wstyle, swing, 64, title)


def _e(ident, title, spec, wstyle, swing="slash", cell=64) -> Entry:
    return Entry(ident, "enemies", spec, wstyle, swing, cell, title)


def _b(ident, title, spec, wstyle, swing="smash") -> Entry:
    return Entry(ident, "bosses", spec, wstyle, swing, 96, title)


# ---------------------------------------------------------------------------
# Hunters
#
# Every hunter is drawn empty-handed (weapon="none"). The only weapons a
# Hunter shows in the arena are the ones the player actually owns, drawn by
# Scripts/Combat/WeaponVisual.gd from the shop art. A weapon baked into the
# sheet as well meant a starting Hunter was holding a scythe they did not own
# while their real weapon rode beside them — two weapons, one of them a lie.
#
# weapon_style is still set per hunter: it tints the attack arcs and stays
# ready if a sheet ever wants a held prop again.
# ---------------------------------------------------------------------------
CHARACTERS = [
    _c(
        "the_reaper", "The Reaper",
        BodySpec(
            cloth=P.R_CLOTH_BLACK, armor=P.R_IRON, skin=P.R_FLESH_PALE, accent=P.R_RUST,
            head="hood", cape="tatters", weapon="none", stature=1.05, build=0.9,
            eye=P.EMBER, belt=True,
        ),
        WeaponStyle(P.R_RUST, P.R_WOOD, P.R_IRON), "slash",
    ),
    _c(
        "bloodstained_crusader", "Bloodstained Crusader",
        BodySpec(
            cloth=P.R_CLOTH_CRIMSON, armor=P.R_STEEL, skin=P.R_FLESH, accent=P.R_GOLD,
            head="helm", cape="cloak", weapon="none", stature=1.1, build=1.25,
            eye=P.CANDLE, shoulder_pads=True,
        ),
        WeaponStyle(P.R_STEEL, P.R_LEATHER, P.R_GOLD, P.CANDLE), "smash",
    ),
    _c(
        "witch_hunter", "Witch Hunter",
        BodySpec(
            cloth=P.R_LEATHER, armor=P.R_IRON, skin=P.R_FLESH, accent=P.R_GOLD,
            head="hat", cape="coat", weapon="none", stature=1.0, build=0.95,
            eye=P.AMBER,
        ),
        WeaponStyle(P.R_STEEL, P.R_WOOD, P.R_GOLD, P.AMBER), "shoot",
    ),
    _c(
        "silver_priest", "Silver Priest",
        BodySpec(
            cloth=Ramp(P.rgb("d8d2c4"), outline=P.rgb("4a4438")), armor=P.R_SILVER,
            skin=P.R_FLESH_PALE, accent=P.R_GOLD,
            head="mitre", cape="cloak", weapon="none", stature=1.05, build=1.0,
            eye=P.CANDLE, tall_collar=True, aura=P.CANDLE,
        ),
        WeaponStyle(P.R_GOLD, P.R_WOOD, P.R_SILVER, P.CANDLE), "cast",
    ),
    _c(
        "moonlit_duelist", "Moonlit Duelist",
        BodySpec(
            cloth=P.R_CLOTH_NAVY, armor=P.R_SILVER, skin=P.R_FLESH_PALE, accent=P.R_SILVER,
            head="bare", cape="coat", weapon="none", stature=1.02, build=0.85,
            eye=P.MOONLIGHT, tall_collar=True,
        ),
        WeaponStyle(P.R_SILVER, P.R_LEATHER, P.R_GOLD, P.MOONLIGHT), "thrust",
    ),
    _c(
        "pyromancer", "Pyromancer",
        BodySpec(
            cloth=Ramp(P.rgb("7a3520"), outline=P.rgb("240d07")), armor=P.R_RUST,
            skin=P.R_FLESH, accent=P.R_GOLD,
            head="hood", cape="cloak", weapon="none", stature=0.98, build=0.95,
            eye=P.EMBER, aura=P.EMBER,
        ),
        WeaponStyle(P.R_RUST, P.R_WOOD, P.R_GOLD, P.EMBER), "cast",
    ),
    _c(
        "alchemist", "Alchemist",
        BodySpec(
            cloth=Ramp(P.rgb("3d4a35"), outline=P.rgb("121a10")), armor=P.R_IRON,
            skin=P.R_FLESH, accent=P.R_GOLD,
            head="mask", cape="coat", weapon="none", stature=0.98, build=0.9,
            eye=P.TOXIC, aura=P.BILE,
        ),
        WeaponStyle(P.R_SILVER, P.R_WOOD, P.R_GOLD, P.TOXIC), "cast",
    ),
    _c(
        "grave_warden", "Grave Warden",
        BodySpec(
            cloth=Ramp(P.rgb("2f3630"), outline=P.rgb("0d100e")), armor=P.R_IRON,
            skin=P.R_FLESH_DEAD, accent=P.R_RUST,
            head="helm", cape="cloak", weapon="none", stature=1.15, build=1.35,
            eye=P.SPECTRAL, shoulder_pads=True,
        ),
        WeaponStyle(P.R_IRON, P.R_WOOD, P.R_RUST), "smash",
    ),
    _c(
        "cursed_noble", "Cursed Noble",
        BodySpec(
            cloth=Ramp(P.rgb("2a1030"), outline=P.rgb("0d0512")), armor=P.R_GOLD,
            skin=P.R_FLESH_PALE, accent=P.R_GOLD,
            head="crown", cape="cloak", weapon="none", stature=1.05, build=0.9,
            eye=P.CRIMSON, tall_collar=True, aura=P.ARCANE,
        ),
        WeaponStyle(P.R_IRON, P.R_LEATHER, P.R_ARCANE, P.VIOLET), "shoot",
    ),
    _c(
        "bloodletter", "Bloodletter",
        BodySpec(
            cloth=Ramp(P.rgb("4a1420"), outline=P.rgb("180509")), armor=P.R_RUST,
            skin=P.R_FLESH_PALE, accent=P.R_RUST,
            head="bare", cape="tatters", weapon="none", stature=1.0, build=0.95,
            eye=P.CRIMSON, aura=P.BLOOD,
        ),
        WeaponStyle(P.R_BONE, P.R_LEATHER, P.R_RUST, P.CRIMSON), "slash",
    ),
]

# ---------------------------------------------------------------------------
# Enemies
# ---------------------------------------------------------------------------
ENEMIES = [
    _e(
        "ghoul", "Ghoul",
        BodySpec(
            cloth=Ramp(P.rgb("585a4a"), outline=P.rgb("15170f")), armor=P.R_IRON,
            skin=P.R_FLESH_ROT, accent=P.R_RUST,
            head="bare", cape="tatters", weapon="none", stature=0.92, build=1.0,
            hunch=0.55, eye=P.TOXIC, belt=False,
        ),
        WeaponStyle(P.R_BONE, P.R_WOOD, P.R_RUST), "slash",
    ),
    _e(
        "skeletal_archer", "Skeletal Archer",
        BodySpec(
            cloth=Ramp(P.rgb("6e6754"), outline=P.rgb("1c1a12")), armor=P.R_BONE,
            skin=P.R_BONE, accent=P.R_RUST,
            head="skull", cape="tatters", weapon="bow", stature=0.98, build=0.7,
            eye=P.EMBER, belt=False,
        ),
        WeaponStyle(P.R_BONE, P.R_BONE, P.R_RUST), "shoot",
    ),
    _e(
        "wraith", "Wraith",
        BodySpec(
            cloth=Ramp(P.rgb("2c3a52"), outline=P.rgb("0a0f18")), armor=P.R_STEEL,
            skin=P.R_SPECTRAL, accent=P.R_SPECTRAL,
            head="hood", cape="shroud", weapon="none", stature=1.05, build=0.8,
            hover=True, eye=P.SPECTRAL, aura=P.SPECTRAL, belt=False,
        ),
        WeaponStyle(P.R_SPECTRAL, P.R_WOOD, P.R_SILVER, P.SPECTRAL), "cast",
    ),
    _e(
        "bloated_corpse", "Bloated Corpse",
        BodySpec(
            cloth=Ramp(P.rgb("6b7346"), outline=P.rgb("1a1d0e")), armor=P.R_ROT,
            skin=P.R_ROT, accent=P.R_ROT,
            head="bare", cape="none", weapon="none", stature=1.12, build=1.9,
            hunch=0.35, eye=P.BILE, aura=P.ROT, belt=False,
        ),
        WeaponStyle(P.R_ROT, P.R_WOOD, P.R_RUST), "smash",
    ),
    _e(
        # The Blood Moon Alpha's pack. Same beast rig as the boss at two
        # thirds the height, so a summoned add reads as "one of his".
        "dire_wolf", "Dire Wolf",
        BodySpec(
            cloth=Ramp(P.rgb("434653"), outline=P.rgb("0f1017")),
            armor=P.R_BONE,
            skin=Ramp(P.rgb("4d505d"), outline=P.rgb("111219")),
            accent=P.R_BONE,
            head="wolf", cape="mane", weapon="none", stature=0.82, build=1.1,
            hunch=0.85, eye=P.AMBER, belt=False,
            digitigrade=True, fur=0.85, claws=True, tail=True,
        ),
        WeaponStyle(P.R_BONE, P.R_LEATHER, P.R_RUST, P.AMBER), "slash",
    ),
    _e(
        "plague_rat", "Plague Rat",
        BodySpec(
            cloth=Ramp(P.rgb("4a3d33"), outline=P.rgb("140f0b")), armor=P.R_IRON,
            skin=Ramp(P.rgb("6b5847"), outline=P.rgb("1c1610")), accent=P.R_ROT,
            head="rat", cape="none", weapon="none", stature=0.55, build=1.3,
            hunch=1.0, eye=P.TOXIC, tail=True, belt=False,
        ),
        WeaponStyle(P.R_BONE, P.R_WOOD, P.R_ROT), "slash",
    ),
]

# ---------------------------------------------------------------------------
# Bosses
# ---------------------------------------------------------------------------
BOSSES = [
    _b(
        # Wave 10. The only beast rig in the cast: digitigrade legs, a muzzle
        # and a ragged fur outline, so it does not read as one more tall man
        # in a coat next to the Count and the Colossus.
        "blood_moon_alpha", "The Blood Moon Alpha",
        BodySpec(
            cloth=Ramp(P.rgb("57525f"), outline=P.rgb("120f1a")),
            armor=P.R_BONE,
            skin=Ramp(P.rgb("635c6c"), outline=P.rgb("15121e")),
            accent=P.R_BONE,
            head="wolf", cape="mane", weapon="none", stature=1.5, build=1.25,
            hunch=0.35, eye=P.AMBER, aura=P.BLOOD, belt=False,
            digitigrade=True, fur=1.0, claws=True, tail=True,
        ),
        WeaponStyle(P.R_BONE, P.R_LEATHER, P.R_RUST, P.AMBER), "slash",
    ),
    _b(
        # Wave 15. A real bat, not a man in a cape: the Count next door wears
        # wings, this one is built around them.
        "belfry_tyrant", "The Belfry Tyrant",
        BodySpec(
            # Grey-green hide, purple membrane, red lamps: the wings have to be
            # a different material from the body or the whole thing flattens.
            cloth=Ramp(P.rgb("3f453f"), outline=P.rgb("101310")),
            armor=P.R_BONE,
            skin=Ramp(P.rgb("4a504a"), outline=P.rgb("12160f")),
            accent=P.R_GOLD,
            wing=Ramp(P.rgb("50405e"), outline=P.rgb("160f1e")),
            head="bat", cape="none", weapon="none", stature=1.45, build=1.15,
            hunch=0.5, crouch=0.85, eye=P.CRIMSON, aura=P.BLOOD, belt=False,
            claws=True, digitigrade=True, wingspan=21.0, wing_holes=3,
            amulet=True,
        ),
        WeaponStyle(P.R_BONE, P.R_LEATHER, P.R_SILVER, P.CRIMSON), "cast",
    ),
    _b(
        "bat_winged_count", "The Bat-Winged Count",
        BodySpec(
            cloth=Ramp(P.rgb("240a18"), outline=P.rgb("0a0208")), armor=P.R_GOLD,
            skin=P.R_FLESH_PALE, accent=P.R_GOLD,
            head="bare", cape="wings", weapon="claws", stature=1.55, build=1.05,
            eye=P.CRIMSON, tall_collar=True, aura=P.BLOOD,
        ),
        WeaponStyle(P.R_BONE, P.R_LEATHER, P.R_GOLD, P.CRIMSON), "slash",
    ),
    _b(
        "gravekeeper_colossus", "Gravekeeper Colossus",
        BodySpec(
            cloth=Ramp(P.rgb("2a2b26"), outline=P.rgb("0b0c0a")), armor=P.R_IRON,
            skin=P.R_FLESH_DEAD, accent=P.R_RUST,
            head="helm", cape="none", weapon="big_cleaver", stature=1.7, build=1.55,
            hunch=0.3, eye=P.EMBER, shoulder_pads=True, extra_arms=True,
        ),
        WeaponStyle(P.R_IRON, P.R_WOOD, P.R_RUST), "smash",
    ),
    _b(
        "hollow_cardinal", "The Hollow Cardinal",
        BodySpec(
            cloth=Ramp(P.rgb("5a1220"), outline=P.rgb("1a0509")), armor=P.R_GOLD,
            skin=P.R_BONE, accent=P.R_GOLD,
            head="mitre", cape="shroud", weapon="staff", stature=1.6, build=1.1,
            eye=P.CANDLE, tall_collar=True, aura=P.CANDLE, horns=True,
        ),
        WeaponStyle(P.R_GOLD, P.R_WOOD, P.R_SILVER, P.CANDLE), "cast",
    ),
]

ALL: list[Entry] = CHARACTERS + ENEMIES + BOSSES
BY_ID = {e.ident: e for e in ALL}

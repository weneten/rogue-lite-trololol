"""The Nightbane palette.

One shared 32-ish colour family keeps ten hunters, five enemies, three bosses,
twenty-five weapon icons and the whole UI looking like they came from the same
hand. Everything else in the toolkit pulls from here.
"""
from __future__ import annotations

from .core import Ramp, mix, rgb, shade

# -- neutrals ---------------------------------------------------------------
VOID = rgb("0b0710")
INK = rgb("140d18")
COAL = rgb("1e1622")
IRON = rgb("2e2635")
STONE = rgb("463c50")
ASH = rgb("6b5f76")
SMOKE = rgb("9a8ea6")
BONE = rgb("d9cfc0")
PARCHMENT = rgb("f0e6d2")

# -- blood moon -------------------------------------------------------------
BLOOD_DARK = rgb("4a0d18")
BLOOD = rgb("8e1526")
CRIMSON = rgb("c62233")
EMBER = rgb("ff5a46")
ROSE = rgb("ff9a8c")

# -- gold / candlelight -----------------------------------------------------
GOLD_DARK = rgb("6b4a12")
GOLD = rgb("c99a2e")
AMBER = rgb("f0c04a")
CANDLE = rgb("ffe9a8")

# -- cold / arcane ----------------------------------------------------------
NIGHT = rgb("18203a")
STEEL_BLUE = rgb("3c5578")
SPECTRAL = rgb("5fd4c8")
MOONLIGHT = rgb("a8d8f0")
ARCANE = rgb("8a5ad4")
VIOLET = rgb("b98cf5")

# -- rot / plague -----------------------------------------------------------
ROT_DARK = rgb("2c3a1e")
ROT = rgb("58703a")
BILE = rgb("8fae4c")
TOXIC = rgb("c2e05a")

# -- flesh ------------------------------------------------------------------
FLESH_PALE = rgb("c9a48c")
FLESH = rgb("a87a60")
FLESH_DEAD = rgb("8d9186")
FLESH_ROT = rgb("7f8a63")

# -- shared ramps -----------------------------------------------------------
R_CLOTH_BLACK = Ramp(IRON, outline=VOID)
R_CLOTH_CRIMSON = Ramp(BLOOD, outline=rgb("2a060d"))
R_CLOTH_NAVY = Ramp(NIGHT, outline=rgb("090c18"))
R_CLOTH_BONE = Ramp(rgb("b3a894"), outline=rgb("3a3428"))
R_LEATHER = Ramp(rgb("4a3527"), outline=rgb("1a1109"))
R_IRON = Ramp(STONE, outline=INK)
R_STEEL = Ramp(rgb("7f8a9c"), outline=rgb("1a1e28"))
R_SILVER = Ramp(rgb("b6c2d4"), outline=rgb("2a3040"))
R_GOLD = Ramp(GOLD, outline=rgb("2e1f06"))
R_BONE = Ramp(BONE, outline=rgb("3d3629"))
R_WOOD = Ramp(rgb("5a4128"), outline=rgb("1e1408"))
R_RUST = Ramp(rgb("8a5a3c"), outline=rgb("2a1710"))
R_FLESH = Ramp(FLESH, outline=rgb("35211a"))
R_FLESH_PALE = Ramp(FLESH_PALE, outline=rgb("46291f"))
R_FLESH_DEAD = Ramp(FLESH_DEAD, outline=rgb("2c322c"))
R_FLESH_ROT = Ramp(FLESH_ROT, outline=rgb("232a1a"))
R_ROT = Ramp(ROT, outline=rgb("141c0e"))
R_ARCANE = Ramp(ARCANE, outline=rgb("21123d"))
R_SPECTRAL = Ramp(SPECTRAL, outline=rgb("0f3b38"))

# -- UI ---------------------------------------------------------------------
UI_BG = rgb("120c16")
UI_PANEL = rgb("1c1524")
UI_PANEL_HI = rgb("2a2033")
UI_BORDER = rgb("574360")
UI_BORDER_HI = rgb("8a6f96")
UI_TEXT = rgb("e6dccc")
UI_TEXT_DIM = rgb("8e8394")
UI_ACCENT = CRIMSON
UI_ACCENT_HI = EMBER
UI_GOLD = AMBER

# Rarity keys used by the shop, level-up cards and weapon frames.
RARITY = {
    0: rgb("7d7288"),   # common — worn iron
    1: rgb("4f9e6a"),   # uncommon — verdigris
    2: rgb("3f7fc4"),   # rare — cold moonlight
    3: rgb("a05ad4"),   # epic — arcane
    4: rgb("e0a032"),   # legendary — candle gold
}

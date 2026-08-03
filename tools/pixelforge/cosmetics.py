"""Loadout cosmetics worn by the Hunter.

Two pieces, both deliberately chosen to need no registration against the rig:
the character sheets bob and swing through six animations, so anything that has
to sit exactly on a shoulder drifts off it within two frames. A ground aura and
free-floating charms track the body instead of the skeleton, which means they
work on all ten Hunters without a single per-character offset.
"""
from __future__ import annotations

from pathlib import Path

from .core import Canvas, with_alpha
from . import palette as P

AURA_W, AURA_H = 64, 32
CHARM = 16


def aura() -> Canvas:
    """Soft ground disc under the Hunter, tinted at runtime by relic category.

    Drawn white so a single texture can serve every category through modulate
    — five near-identical PNGs would only be five things to keep in sync.
    """
    c = Canvas(AURA_W, AURA_H)
    cx, cy = AURA_W / 2, AURA_H / 2
    rings = 9
    for i in range(rings, 0, -1):
        t = i / rings
        # Peaks high enough that the runtime modulate (which drops it to about
        # half) still reads on a dark flagstone floor.
        alpha = int(165 * (1.0 - t) ** 1.6) + 6
        c.ellipse(cx, cy, (AURA_W / 2 - 1) * t, (AURA_H / 2 - 1) * t, (255, 255, 255, alpha))
    # A brighter rim so the disc has an edge instead of dissolving into the floor.
    c.ellipse(cx, cy, AURA_W / 2 - 1, AURA_H / 2 - 1, (255, 255, 255, 0))
    for i in range(2):
        c.ring(cx, cy, AURA_W / 2 - 2 - i, (255, 255, 255, 90 - i * 35))
    return c


def charm_backing() -> Canvas:
    """The disc a relic icon rides on while orbiting the Hunter.

    Without it a 32x32 icon shrunk to charm size reads as visual noise against
    a busy floor; the dark disc gives every charm the same silhouette.
    """
    c = Canvas(CHARM, CHARM)
    c.circle(CHARM / 2, CHARM / 2, 7, with_alpha(P.VOID, 190))
    c.circle(CHARM / 2, CHARM / 2, 6, with_alpha(P.UI_PANEL, 220))
    c.ring(CHARM / 2, CHARM / 2, 7, P.UI_BORDER)
    c.ring(CHARM / 2, CHARM / 2, 6, with_alpha(P.UI_BORDER_HI, 120))
    return c


def export(root: Path) -> None:
    out = root / "Assets" / "sprites" / "cosmetics"
    out.mkdir(parents=True, exist_ok=True)
    aura().save(out / "aura.png")
    charm_backing().save(out / "charm_backing.png")

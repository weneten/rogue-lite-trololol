"""The Witchfire Magus's purple fire.

One sheet, three rows, each of which is a different job the fight already has
somebody doing with `draw_rect` and a triangle:

    curtain  a wall of fire standing on the floor, tileable left to right.
             FlameArena's border and FlameWall's leading face.
    ground   burning floor, tileable in both directions. The ground a sweep has
             already crossed and the rings of a pyre eruption.
    plume    one column of fire with a hot foot, not tiled. A meteor impact, an
             eruption's centre, anything that is a single fire rather than a
             field of it.

# The angle

Nightbane is drawn from a high three-quarter view: the cast stands upright with
their feet at the bottom of the cell, and things lying on the floor — blood
pools, telegraph decals — are flattened into ellipses. Fire has to answer both
halves of that at once, and the answer is the same one the shadow under a
character uses.

Every flame here therefore has two parts. Its footprint is an ellipse squashed
to `FOOT_SQUASH` of its width, because it is lying on the ground plane the
Hunter walks on. Its tongues rise toward the top of the screen, but only
`RISE` of the height a side-on view would give them, because at this angle a
metre of height is worth less screen than a metre of floor. Fire drawn without
the first part hovers; fire drawn without the second is a purple puddle.

The one thing that is not compressed is the hot line where the fire meets the
floor. That line is the contact point, and it is what makes the effect sit on
the ground rather than in front of it.

# Why the noise is periodic

A wall of fire is drawn by repeating one tile along an edge, and it loops
forever. Ordinary noise can do neither: the tile shows its seam and the loop
shows its cut. `_Turbulence` is a value-noise lattice that wraps in x, y and
time, so a period of it returns to exactly where it started — the tile matches
itself, and frame 8 is frame 0 again with no cross-fade to hide a join.

That is also why every lattice period below divides the cell size. Change the
cell and the periods have to follow, or the seams come back.
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

from .core import Canvas, RGBA, build_sheet, ease_in_out, with_alpha
from . import palette as P

CELL = 64
COLUMNS = 8
FRAMES = 8

# Lattice cell sizes in pixels, coarse and fine. CELL divided by either must be
# a whole number of lattice periods or the tile stops matching itself — see
# _check_periods, which refuses to build a sheet that would seam.
COARSE = 8.0
FINE = 4.0

# How far each octave climbs per frame, in pixels. Both are chosen so that over
# FRAMES frames the total climb is a whole number of lattice periods: the noise
# then arrives back where it started and frame 8 is frame 0 exactly. Anything
# else gives a fire that jumps once a second, which is worse than one that does
# not move at all. The two differ so the shimmer runs over the body rather than
# the whole flame sliding as one sheet.
SCROLL_COARSE = 8.0
SCROLL_FINE = 16.0

# Where the ground plane crosses the cell. Flame above, scorched floor and
# embers below, and the sheet's origin sits on it — so a curtain drawn at a
# wall line puts its fire on the right side of that line without the caller
# working out an offset.
FLOOR_Y = 46

# How far the tallest tongue may reach above the floor line, in pixels. Chosen
# against FlameArena.BORDER (46) so that at scale 1 one texel is one world
# pixel and the curtain fills the band the arena actually burns. Typical
# tongues come to about half of it — see the cooling term in _heat.
FLAME_H = 52

# How much of a side-on flame's height survives the camera angle, and how flat
# a circle on the floor becomes. Both are the same tilt expressed twice — keep
# them in step or the fire and its own footprint disagree about where the
# camera is.
RISE = 0.85
FOOT_SQUASH = 0.42

# The heat a pixel gets from the noise, and what climbing costs it. Fire is
# built by subtraction here rather than by multiplication: heat = noise * FUEL
# - height * COOLING. A product fades every column together and gives a flame
# with a soft, even edge — a haze. A difference lets a column the noise happens
# to favour climb the whole way while its neighbour dies at a third of the
# height, which is what a tongue is.
#
# FUEL and the ramp below share one scale, so a pixel's heat is readable as
# "which colour" rather than as a number normalised somewhere else that drifts
# out of step with the thresholds.
FUEL = 0.85
# Below FUEL, so the luckiest columns reach the top of their range and stop
# there rather than being cut off mid-tongue.
COOLING = 0.62

# Noise alone gives detached blobs hanging over the floor — popcorn, not fire.
# BODY is the sheet of flame they grow out of: a heat floor that is high at the
# ground and gone by the time anything is licking. Fire is a solid thing near
# its fuel and a scatter of tongues at its top, and this is the "solid" half.
BODY = 0.45
BODY_FALL = 1.8

# A plume is one fire rather than a stretch of one, and it has to read from
# across a room as a column going up. It therefore cools more slowly than a
# curtain — a wall's tongues are read against the wall beside them, a plume's
# only against its own height — and narrows harder, so what climbs is a
# tapering column and not a heap.
PLUME_COOLING = 0.30
PLUME_TAPER = 0.45

# Half the plume's width where it leaves the floor. Deliberately less than half
# its height: at anything wider the body term fills the bottom of the cell and
# the result is a mound of fire with a wisp on top, which is what a bonfire
# looks like from the side and not what a column of witchfire coming out of the
# floor looks like from anywhere.
PLUME_HALF = 10.5

# Value noise clusters around its own mean, and a flame drawn straight from it
# is all mid-tone. Pushing contrast about the middle separates the tongues from
# the gaps. Gently: past about 1.5 the noise clamps at both ends and the fire
# goes back to being flat, just flat at white instead of at mid-violet.
CONTRAST = 1.35

# -- colour -----------------------------------------------------------------
# Six steps from the outside in. Witchfire is the arcane family the Magus is
# already drawn in (palette.ARCANE / VIOLET), pushed to a near-white centre:
# fire is the one thing in this game allowed to be brighter than candlelight.
EMBER_EDGE = P.rgb("21123d")
DEEP = P.rgb("3c1a6e")
MID = P.ARCANE
CORE = P.VIOLET
HOT = P.rgb("e6c9ff")
WHITE = P.rgb("fbf0ff")

# The floor under a fire, and the light it throws on it.
SCORCH = P.rgb("120a18", 214)
SCORCH_EDGE = P.rgb("1d1226", 150)
GLOW = P.rgb("6a2fae", 120)

# Heat thresholds, outside in; anything hotter than the last one is WHITE. The
# gaps are uneven on purpose. The outer bands are thin so the flame keeps a
# crisp edge, the middle ones are wide because that is where fire actually
# lives, and the last threshold sits above what an average pixel can reach so
# white stays a fleck in the hottest part of the base rather than a bar across
# it. A wall lit evenly at the top of its ramp reads as a fluorescent tube.
STEPS: list[tuple[float, RGBA]] = [
    (0.30, EMBER_EDGE),
    (0.47, DEEP),
    (0.66, MID),
    (0.86, CORE),
    (1.08, HOT),
]

# Below this there is no fire at all. Between it and the first step the flame is
# dithered rather than drawn solid — the classic way to get a seventh tone out
# of a six-colour ramp, and the reason the edges shimmer instead of crawling.
CUTOFF = 0.16


class _Turbulence:
    """Value noise on a lattice that wraps in x, y and time. See module head."""

    __slots__ = ("nx", "ny", "nt", "g")

    def __init__(self, rng: random.Random, nx: int, ny: int, nt: int):
        self.nx, self.ny, self.nt = nx, ny, nt
        self.g = [rng.random() for _ in range(nx * ny * nt)]

    def _at(self, x: int, y: int, t: int) -> float:
        return self.g[((t % self.nt) * self.ny + (y % self.ny)) * self.nx + (x % self.nx)]

    def sample(self, x: float, y: float, t: float) -> float:
        x0, y0, t0 = math.floor(x), math.floor(y), math.floor(t)
        fx, fy, ft = ease_in_out(x - x0), ease_in_out(y - y0), ease_in_out(t - t0)

        out = 0.0
        for dt in (0, 1):
            wt = ft if dt else 1.0 - ft
            for dy in (0, 1):
                wy = fy if dy else 1.0 - fy
                for dx in (0, 1):
                    wx = fx if dx else 1.0 - fx
                    out += self._at(x0 + dx, y0 + dy, t0 + dt) * wx * wy * wt

        return out


def _paint(c: Canvas, x: int, y: int, heat: float) -> None:
    """One pixel of fire, quantised to the ramp. Nothing is ever blended."""
    if heat <= CUTOFF:
        return

    if heat < STEPS[0][0]:
        # Stippled outer edge. Checkered rather than half-alpha so the flame
        # keeps a hard silhouette at every zoom.
        if (x + y) % 2 == 0:
            c.set(x, y, EMBER_EDGE)
        return

    for limit, color in STEPS:
        if heat < limit:
            c.set(x, y, color)
            return

    c.set(x, y, WHITE)


def _fbm(turb: _Turbulence, fine: _Turbulence, x: float, y: float, t: float,
         scroll: float) -> float:
    """Two octaves, both scrolling upward at the rate their own period loops.

    The coarse one is the shape of the flame; the fine one is the shimmer on
    it. They scroll at different speeds, which is what stops the whole wall
    moving as one sheet of wallpaper.
    """
    coarse = turb.sample(x / COARSE, (y - scroll * SCROLL_COARSE) / COARSE, t)
    detail = fine.sample(x / FINE, (y - scroll * SCROLL_FINE) / FINE, t * 2.0)
    n = coarse * 0.72 + detail * 0.28
    n = 0.5 + (n - 0.5) * CONTRAST
    return min(1.0, max(0.0, n))


def _foot(c: Canvas, cx: float, half_width: float, strength: float) -> None:
    """The contact between a fire and the floor it stands on.

    Scorch, then the light the fire throws on it, then the hot line itself. In
    that order, because the line has to survive both.
    """
    depth = max(3.0, half_width * FOOT_SQUASH)
    # Dithered rather than filled: a solid ellipse under a flame reads as a
    # plate the fire has been stood on. Scorch has to look like the floor got
    # darker, which means the floor has to show through it.
    ring = Canvas(c.w, c.h)
    ring.ellipse(cx, FLOOR_Y, half_width, depth, SCORCH_EDGE)
    ring.ellipse(cx, FLOOR_Y, half_width * 0.74, depth * 0.74, SCORCH)
    for y in range(c.h):
        for x in range(c.w):
            if ring.get(x, y)[3] and (x + y) % 2 == 0:
                c.set(x, y, ring.get(x, y))

    c.ellipse_blend(cx, FLOOR_Y - 1, half_width * 0.62, depth * 0.58,
                    with_alpha(GLOW, int(110 * strength)))


# ---------------------------------------------------------------------------
# Rows
# ---------------------------------------------------------------------------
def _curtain_frame(turb: _Turbulence, fine: _Turbulence, index: int) -> Canvas:
    c = Canvas(CELL, CELL)
    t = index / FRAMES * turb.nt
    scroll = index

    # Scorched ground under the whole tile, so a wall of these has a footprint
    # rather than appearing to hover. Tiles with the fire, so it is drawn as a
    # band and not as one ellipse per tongue.
    for y in range(FLOOR_Y - 2, min(CELL, FLOOR_Y + 12)):
        fade = 1.0 - (y - FLOOR_Y + 2) / 14.0
        for x in range(CELL):
            if fade > 0.55 or (x + y) % 2 == 0:
                c.set(x, y, SCORCH if fade > 0.3 else SCORCH_EDGE)

    for y in range(0, FLOOR_Y):
        # 0 at the floor, 1 at the top of the tallest tongue's reach.
        up = (FLOOR_Y - y) / (FLAME_H * RISE)
        if up > 1.0:
            continue

        # Held back over the bottom few pixels. Fire is coolest exactly where it
        # touches its fuel, and without the dip the hottest colour in the ramp
        # runs the full width of the tile in a straight line — a fluorescent
        # tube with flames on top of it.
        body = BODY * (1.0 - up) ** BODY_FALL * (0.70 + 0.30 * min(1.0, up / 0.16))
        for x in range(CELL):
            n = _fbm(turb, fine, x, y, t, scroll)
            # How hard this stretch of wall is burning, sampled per column from
            # the coarse lattice alone so it varies over tens of pixels rather
            # than per pixel. Without it BODY is the same number all the way
            # along and the base of the wall is a drawn line; with it the wall
            # roars in places and sags in others, which is the read the old
            # procedural version got from one lick per tongue.
            # Sampled off one fixed plane of the lattice and animated by t
            # alone. Giving it a scroll of its own was what broke the loop: any
            # drift here has to land on a whole period after FRAMES frames too,
            # and the time axis already wraps by construction.
            draught = 0.55 + 0.85 * turb.sample(x / COARSE, 0.0, t)
            # BODY is also what keeps the contact line unbroken: near the floor
            # every column stays lit whatever the fine noise is doing, or the
            # wall develops gaps a player could believe they can walk through.
            _paint(c, x, y, n * FUEL - up * COOLING + body * draught)

    return c


def _ground_frame(turb: _Turbulence, fine: _Turbulence, index: int) -> Canvas:
    c = Canvas(CELL, CELL)
    t = index / FRAMES * turb.nt

    # Scorch under the whole tile, dithered and half transparent. Laid over a
    # large stretch of arena this has to darken the floor without replacing it:
    # a solid black tile reads as a hole in the level, not as burnt ground.
    for y in range(CELL):
        for x in range(CELL):
            if (x + y) % 2 == 0:
                c.set(x, y, SCORCH)

    for y in range(CELL):
        for x in range(CELL):
            # No height term and no body — this fire is seen from directly
            # above, so there is no up for it to cool along and no near edge to
            # be solid at. Instead the noise is stretched about a high
            # threshold: what clears it burns hot, what does not is dark
            # ground, and the between is thin. Patches with floor showing
            # around them, which is what makes a burning field readable.
            n = _fbm(turb, fine, x, y, t, index)
            _paint(c, x, y, (n - 0.46) * 1.30)

    return c


def _plume_frame(turb: _Turbulence, fine: _Turbulence, index: int) -> Canvas:
    c = Canvas(CELL, CELL)
    t = index / FRAMES * turb.nt
    cx = CELL / 2.0

    _foot(c, cx, PLUME_HALF + 3.0, 0.8 + 0.2 * math.sin(index / FRAMES * math.tau))

    for y in range(0, FLOOR_Y):
        up = (FLOOR_Y - y) / (FLAME_H * RISE)
        if up > 1.0:
            continue

        # Narrows as it climbs, and leans very slightly, because a column of
        # fire that is exactly symmetrical about its own axis reads as a lamp.
        half = PLUME_HALF * (1.0 - up * PLUME_TAPER)
        lean = 2.6 * up * math.sin(index / FRAMES * math.tau + 0.6)
        for x in range(CELL):
            across = abs(x + 0.5 - (cx + lean)) / half
            n = _fbm(turb, fine, x, y, t, index)
            # Same terms as the curtain, with the distance from the axis as a
            # second thing to climb. The plume's edge is therefore ragged for
            # the same reason its tip is, instead of being an envelope the fire
            # has been poured into. Its body is a column rather than a sheet,
            # so BODY falls off across the plume as well as up it.
            # Thins toward the tip so the top of the plume is tongues rather
            # than a filled cone, and dips at the very bottom for the same
            # reason the curtain's does.
            body = (BODY * (1.0 - up) ** 1.4
                    * max(0.0, 1.0 - across * across)
                    * (0.72 + 0.28 * min(1.0, up / 0.20)))
            heat = n * FUEL - up * PLUME_COOLING - across * across * 0.55 + body
            _paint(c, x, y, heat)

    return c


ROWS = [
    ("curtain", _curtain_frame, 12, True),
    ("ground", _ground_frame, 10, True),
    ("plume", _plume_frame, 12, True),
]


def _check_periods() -> None:
    """The two things that make this sheet usable, asserted rather than hoped.

    A tile seams, or an animation jumps, the moment one of these stops holding,
    and neither failure is obvious in a still frame — you see it in the game, on
    a wall two hundred pixels long, as a repeating scar. Cheap to check here.
    """
    for size, cells in ((COARSE, CELL // int(COARSE)), (FINE, CELL // int(FINE))):
        span = CELL / size
        if span % cells:
            raise ValueError(
                f"tile seams: {CELL}px is {span} lattice steps, period {cells}")

    for scroll, size, cells in (
        (SCROLL_COARSE, COARSE, CELL // int(COARSE)),
        (SCROLL_FINE, FINE, CELL // int(FINE)),
    ):
        climb = FRAMES * scroll / size
        if climb % cells:
            raise ValueError(
                f"loop jumps: {FRAMES} frames climb {climb} steps, period {cells}")


def render_frames(seed: int = 1917) -> list[Canvas]:
    _check_periods()

    frames: list[Canvas] = []
    for row, (_name, render, _fps, _loop) in enumerate(ROWS):
        # A lattice per row, so the three effects do not flicker in unison.
        rng = random.Random(seed + row * 101)
        turb = _Turbulence(rng, CELL // int(COARSE), CELL // int(COARSE), 4)
        fine = _Turbulence(rng, CELL // int(FINE), CELL // int(FINE), 4)
        row_frames = [render(turb, fine, i) for i in range(FRAMES)]
        row_frames += [Canvas(CELL, CELL) for _ in range(COLUMNS - FRAMES)]
        frames.extend(row_frames)

    return frames


def build_meta() -> dict:
    animations: dict[str, dict] = {}
    for row, (name, _render, fps, loop) in enumerate(ROWS):
        indices = [row * COLUMNS + i for i in range(FRAMES)]
        animations[name] = {
            "row": row,
            "from": indices[0],
            "to": indices[-1],
            "frames": indices,
            "frameCount": FRAMES,
            "fps": fps,
            "loop": loop,
        }

    # idle is what SpriteSheetCache falls back to when a caller names nothing.
    animations["idle"] = dict(animations["curtain"])

    return {
        "image": "witchfire.png",
        "frameWidth": CELL,
        "frameHeight": CELL,
        "columns": COLUMNS,
        "rows": len(ROWS),
        "facing": "right",
        "pixelArt": True,
        # The floor line, not the middle of the cell: a curtain or a plume
        # placed at a point stands ON that point. The ground row is a tile and
        # is laid by rect rather than anchored, so it does not care.
        "origin": {"x": CELL / 2.0, "y": float(FLOOR_Y)},
        "animations": animations,
        # How far flame actually reaches above the floor line, after the camera
        # angle takes its share — not FLAME_H, which is the height before the
        # tilt. GDScript scales the artwork by this to fill a hazard deeper than
        # the cell (FlameWall's slab is as deep as its attack pattern says), and
        # scaling by the pre-tilt number leaves the last tenth of the burning
        # slab looking like floor.
        "flameHeight": round(FLAME_H * RISE, 1),
        "floorY": FLOOR_Y,
        "tileable": {"curtain": "x", "ground": "xy", "plume": "none"},
    }


def export(root: Path) -> Path:
    out_dir = root / "Assets" / "sprites" / "vfx" / "witchfire"
    out_dir.mkdir(parents=True, exist_ok=True)

    build_sheet(render_frames(), COLUMNS, CELL).save(out_dir / "witchfire.png")
    (out_dir / "witchfire.json").write_text(json.dumps(build_meta(), indent=2) + "\n")
    return out_dir

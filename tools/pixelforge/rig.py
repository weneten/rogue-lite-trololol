"""A poseable humanoid drawn in pixels.

Every hunter, enemy and boss in the game is the same rig with a different
spec: proportions, ramps, headgear, cape and held weapon. Keeping one rig is
what makes ten characters read as one cast instead of ten clip-art imports.

Frames face right; the game mirrors with flip_h.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

from .core import (
    CLEAR,
    RGBA,
    Canvas,
    Ramp,
    ease_in_out,
    ease_out,
    lerp,
    mix,
    shade,
    with_alpha,
)
from . import palette as P

Vec2 = tuple[float, float]


# ---------------------------------------------------------------------------
# Spec
# ---------------------------------------------------------------------------
@dataclass
class BodySpec:
    """Everything that makes one character look unlike the others."""

    cloth: Ramp = field(default_factory=lambda: P.R_CLOTH_BLACK)
    armor: Ramp = field(default_factory=lambda: P.R_IRON)
    skin: Ramp = field(default_factory=lambda: P.R_FLESH)
    accent: Ramp = field(default_factory=lambda: P.R_GOLD)

    head: str = "hood"      # hood hat helm skull bare crown mask mitre veil rat
    cape: str = "cloak"     # none cloak tatters wings shroud coat
    weapon: str = "scythe"  # see weapons.held()
    build: float = 1.0      # limb thickness
    stature: float = 1.0    # overall height
    hunch: float = 0.0      # forward spine curve (0..1)
    hover: bool = False     # wraith-likes drift instead of stepping
    eye: RGBA = P.EMBER
    aura: RGBA | None = None
    shoulder_pads: bool = False
    belt: bool = True
    tall_collar: bool = False
    extra_arms: bool = False
    horns: bool = False
    tail: bool = False


# ---------------------------------------------------------------------------
# Pose
# ---------------------------------------------------------------------------
@dataclass
class Pose:
    hip: Vec2
    chest: Vec2
    neck: Vec2
    head: Vec2
    head_r: float
    shoulder_b: Vec2
    elbow_b: Vec2
    hand_b: Vec2
    shoulder_f: Vec2
    elbow_f: Vec2
    hand_f: Vec2
    hip_b: Vec2
    knee_b: Vec2
    foot_b: Vec2
    hip_f: Vec2
    knee_f: Vec2
    foot_f: Vec2
    weapon_angle: float = 0.0
    cape_sway: float = 0.0
    tilt: float = 0.0
    ground_y: float = 0.0
    alpha: float = 1.0
    airborne: bool = False


def _joint(origin: Vec2, angle_deg: float, length: float) -> Vec2:
    """Angle 0 points straight down; positive swings forward (screen right)."""
    a = math.radians(angle_deg)
    return (origin[0] + math.sin(a) * length, origin[1] + math.cos(a) * length)


def _arm(shoulder: Vec2, upper_deg: float, fore_deg: float, s: float) -> tuple[Vec2, Vec2]:
    elbow = _joint(shoulder, upper_deg, 8.0 * s)
    hand = _joint(elbow, upper_deg + fore_deg, 7.5 * s)
    return elbow, hand


def _leg(hip: Vec2, thigh_deg: float, shin_deg: float, s: float) -> tuple[Vec2, Vec2]:
    knee = _joint(hip, thigh_deg, 9.0 * s)
    foot = _joint(knee, thigh_deg + shin_deg, 9.0 * s)
    return knee, foot


# Weapon-arm angle curves, one entry per attack frame. Sharp acceleration
# between frames 1 and 3 is what sells the impact.
_SWING = {
    "slash": [-55, -95, -30, 55, 85, 45],
    "thrust": [-25, -60, -10, 45, 30, 5],
    "cast": [-30, -70, -80, -60, -30, -5],
    "shoot": [-15, -35, -8, -8, -14, -10],
    "smash": [-70, -110, -40, 70, 95, 60],
}


def build_pose(
    spec: BodySpec,
    anim: str,
    t: float,
    *,
    center_x: float,
    feet_y: float,
    swing: str = "slash",
) -> Pose:
    s = spec.stature
    cx = center_x
    bob = 0.0
    lean = spec.hunch * 10.0
    tilt = 0.0
    alpha = 1.0
    airborne = False
    ground_y = feet_y
    thigh_b = thigh_f = shin_b = shin_f = 0.0
    arm_b_u, arm_b_f = 18.0, 20.0
    arm_f_u, arm_f_f = -12.0, 18.0
    weapon_angle = -20.0
    cape_sway = 0.0
    drop = 0.0

    if anim == "idle":
        breath = math.sin(t * math.tau)
        bob = -0.5 - breath * 0.9
        arm_b_u = 16 + breath * 4
        arm_f_u = -14 + breath * 4
        arm_f_f = 34
        weapon_angle = -38 + breath * 5
        cape_sway = breath * 1.6
        thigh_b, thigh_f = -4.0, 4.0
        shin_b, shin_f = 4.0, -2.0
        if spec.hover:
            bob = -2.0 - breath * 2.5
            thigh_b, thigh_f = -12.0, 10.0
            shin_b, shin_f = 14.0, 16.0
            airborne = True

    elif anim == "run":
        ph = t * math.tau
        swing_amt = 34.0
        thigh_f = math.sin(ph) * swing_amt
        thigh_b = math.sin(ph + math.pi) * swing_amt
        # Knees only bend on the recovery half of the stride.
        shin_f = max(0.0, -math.sin(ph - 0.6)) * 46.0
        shin_b = max(0.0, -math.sin(ph + math.pi - 0.6)) * 46.0
        bob = -abs(math.sin(ph * 2.0)) * 2.2 - 0.5
        lean += 9.0
        arm_b_u = 18 + math.sin(ph) * 30
        arm_f_u = -14 + math.sin(ph + math.pi) * 26
        arm_b_f = 26
        arm_f_f = 30
        weapon_angle = -28 + math.sin(ph + math.pi) * 18
        cape_sway = 3.0 + math.sin(ph) * 2.2
        if spec.hover:
            thigh_f, thigh_b = 18.0, -14.0
            shin_f, shin_b = 20.0, 24.0
            bob = -3.0 - abs(math.sin(ph)) * 2.0
            airborne = True

    elif anim == "attack":
        curve = _SWING.get(swing, _SWING["slash"])
        idx = t * (len(curve) - 1)
        i0 = int(math.floor(idx))
        i1 = min(len(curve) - 1, i0 + 1)
        f = idx - i0
        arm_f_u = lerp(curve[i0], curve[i1], f)
        weapon_angle = arm_f_u - 35.0
        # Body counter-rotates into the swing.
        lean += -6.0 if t < 0.35 else 12.0 * ease_out(min(1.0, (t - 0.35) / 0.4))
        bob = -1.0 if t < 0.35 else -2.0
        arm_b_u = 24 - arm_f_u * 0.25
        arm_f_f = 22 if t < 0.4 else 8
        thigh_f = 16 if t > 0.35 else 6
        thigh_b = -14 if t > 0.35 else -6
        shin_f, shin_b = 4, 10
        cape_sway = -4.0 if t < 0.35 else 5.0

    elif anim == "hurt":
        k = ease_out(t)
        lean += -18.0 * (1.0 - k * 0.4)
        bob = -1.5
        tilt = -8.0 * (1.0 - k * 0.5)
        arm_b_u = 42
        arm_f_u = -38
        weapon_angle = -60
        thigh_b, thigh_f = -16.0, 12.0
        shin_b, shin_f = 18.0, 4.0
        cape_sway = -5.0

    elif anim == "death":
        k = ease_in_out(min(1.0, t * 1.15))
        tilt = -80.0 * k
        drop = 12.0 * k
        lean += -25.0 * k
        arm_b_u = lerp(40, 95, k)
        arm_f_u = lerp(-40, -95, k)
        weapon_angle = lerp(-70, -140, k)
        thigh_b = lerp(-18, -55, k)
        thigh_f = lerp(14, 48, k)
        shin_b = lerp(20, 55, k)
        shin_f = lerp(8, 40, k)
        alpha = 1.0 if t < 0.6 else lerp(1.0, 0.25, (t - 0.6) / 0.4)
        cape_sway = -8.0 * k

    elif anim == "dash":
        k = ease_out(t)
        lean += 26.0 * math.sin(min(1.0, t * 1.4) * math.pi)
        bob = -3.5 * math.sin(min(1.0, t * 1.3) * math.pi)
        thigh_f = lerp(45, 10, k)
        thigh_b = lerp(-40, -6, k)
        shin_f = lerp(30, 8, k)
        shin_b = lerp(50, 14, k)
        arm_b_u = lerp(60, 20, k)
        arm_f_u = lerp(-50, -14, k)
        weapon_angle = lerp(-70, -25, k)
        cape_sway = 8.0 - k * 4.0
        airborne = True

    feet = feet_y + drop
    ground_y = feet_y
    hip_y = feet - 18.0 * s + bob
    lean_off = math.tan(math.radians(lean)) * 12.0 * s
    hip = (cx, hip_y)
    chest = (cx + lean_off * 0.75, hip_y - 12.0 * s)
    neck = (cx + lean_off, hip_y - 16.0 * s)
    head_r = 5.4 * s
    head = (cx + lean_off * 1.25 + math.sin(math.radians(tilt)) * 6.0,
            hip_y - 20.5 * s + math.cos(math.radians(tilt)) * 0.0 + abs(tilt) * 0.06)

    sh_dx = 6.6 * s
    shoulder_b = (chest[0] - sh_dx * 0.5, chest[1] + 1.0)
    shoulder_f = (chest[0] + sh_dx * 0.5, chest[1] + 1.5)
    elbow_b, hand_b = _arm(shoulder_b, arm_b_u, arm_b_f, s)
    elbow_f, hand_f = _arm(shoulder_f, arm_f_u, arm_f_f, s)

    hip_b = (hip[0] - 3.0 * s, hip[1])
    hip_f = (hip[0] + 3.0 * s, hip[1])
    knee_b, foot_b = _leg(hip_b, thigh_b, shin_b, s)
    knee_f, foot_f = _leg(hip_f, thigh_f, shin_f, s)

    if not airborne and anim not in ("death",):
        # Pin whichever foot is lower to the ground so runs don't skate.
        lowest = max(foot_b[1], foot_f[1])
        correction = feet - lowest
        if correction < 0:
            correction = 0.0
        foot_b = (foot_b[0], foot_b[1] + correction * 0.6)
        foot_f = (foot_f[0], foot_f[1] + correction * 0.6)

    return Pose(
        hip=hip, chest=chest, neck=neck, head=head, head_r=head_r,
        shoulder_b=shoulder_b, elbow_b=elbow_b, hand_b=hand_b,
        shoulder_f=shoulder_f, elbow_f=elbow_f, hand_f=hand_f,
        hip_b=hip_b, knee_b=knee_b, foot_b=foot_b,
        hip_f=hip_f, knee_f=knee_f, foot_f=foot_f,
        weapon_angle=weapon_angle + tilt, cape_sway=cape_sway, tilt=tilt,
        ground_y=ground_y, alpha=alpha, airborne=airborne,
    )


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
def _limb(c: Canvas, a: Vec2, b: Vec2, r0: float, r1: float, ramp: Ramp) -> None:
    """Shadowed capsule, base tone on top of it, lit sliver up-left.

    Three tones is the minimum that still reads as a round limb; two makes
    dark cloth collapse into a flat blob.
    """
    c.capsule(a, b, r0, r1, ramp.dark)
    c.capsule((a[0] - 0.3, a[1] - 0.4), (b[0] - 0.3, b[1] - 0.4), r0 * 0.82, r1 * 0.82, ramp.core)
    if r0 > 1.6:
        c.capsule((a[0] - 0.9, a[1] - 1.0), (b[0] - 0.9, b[1] - 1.0), r0 * 0.42, r1 * 0.42, ramp.light)


def _boot(c: Canvas, foot: Vec2, s: float, ramp: Ramp) -> None:
    c.ellipse(foot[0] + 1.0 * s, foot[1], 3.2 * s, 1.9 * s, ramp.dark)
    c.ellipse(foot[0] + 0.8 * s, foot[1] - 0.7, 2.6 * s, 1.2 * s, ramp.core)
    c.hline(round(foot[0] - 1.4 * s), round(foot[0] + 1.6 * s), round(foot[1] - 1.4 * s), ramp.light)


def _draw_cape(c: Canvas, pose: Pose, spec: BodySpec, s: float) -> None:
    kind = spec.cape
    if kind == "none":
        return
    ramp = spec.cloth
    sway = pose.cape_sway
    top = (pose.neck[0] - 1.5 * s, pose.neck[1] + 1.0)
    bottom_y = pose.ground_y - 3.0 * s

    if kind in ("cloak", "shroud", "coat"):
        width = 7.0 * s if kind != "shroud" else 9.0 * s
        hem = bottom_y if kind != "coat" else pose.hip[1] + 9.0 * s
        pts = [
            (top[0] + 2.0 * s, top[1]),
            (top[0] - 3.0 * s, top[1] + 3.0 * s),
            (top[0] - 4.5 * s - sway, hem - 6.0 * s),
            (top[0] - width - sway * 1.6, hem),
            (top[0] + width * 0.4 - sway * 0.6, hem + 1.0),
            (top[0] + 3.2 * s, pose.hip[1] + 2.0 * s),
        ]
        c.polygon(pts, ramp.dark)
        inner = [(x + 1.2, y - 0.6) for x, y in pts]
        c.polygon(inner, ramp.core)
        # Vertical folds — three darker seams give the cloth volume.
        for i in range(3):
            fx = top[0] - (1.5 + i * 2.0) * s - sway * (0.4 + i * 0.35)
            c.line((fx + 1.0, top[1] + 4.0 * s), (fx - sway * 0.8, hem - 1.0), shade(ramp.dark, -0.35))

    elif kind == "tatters":
        base_y = pose.hip[1] + 4.0 * s
        for i in range(6):
            fx = top[0] - 5.5 * s + i * 2.0 * s
            length = (7.0 + (i % 3) * 3.5) * s
            tip = (fx - sway * (1.0 + i * 0.2), base_y + length)
            c.capsule((fx, top[1] + 3.0 * s), tip, 1.8 * s, 0.5, ramp.dark)
        c.polygon(
            [
                (top[0] + 2.0 * s, top[1]),
                (top[0] - 5.0 * s, top[1] + 2.5 * s),
                (top[0] - 5.5 * s - sway, base_y),
                (top[0] + 3.0 * s, base_y - 1.0 * s),
            ],
            ramp.dark,
        )

    elif kind == "wings":
        # Two swept membranes: a leading arm bone up-and-back, then a
        # scalloped trailing edge falling back toward the hip.
        span = 15.0 * s
        for layer_i, (depth, tone) in enumerate(
            ((1.15, shade(ramp.dark, -0.35)), (1.0, ramp.dark))
        ):
            root = (pose.chest[0] - 1.0 * s + layer_i * 1.5, pose.chest[1] - 1.0 * s)
            peak = (root[0] - span * 0.5 * depth, root[1] - 8.0 * s * depth)
            tip = (root[0] - span * 1.25 * depth - sway * 0.6, root[1] - 1.0 * s * depth)
            hipward = (root[0] - 3.0 * s, root[1] + 12.0 * s)
            c.polygon([root, peak, tip, hipward], tone)
            # Finger struts fanning from the shoulder to the trailing edge.
            for k in range(1, 4):
                f = k / 4.0
                fx = lerp(tip[0], hipward[0], f)
                fy = lerp(tip[1], hipward[1], f)
                c.line(root, (fx, fy), shade(tone, -0.3))
            # Scallops between the struts read as bat membrane, not a cape.
            for k in range(4):
                f = k / 4.0
                sx = lerp(tip[0], hipward[0], f) + 1.5
                sy = lerp(tip[1], hipward[1], f) + 2.0
                c.circle(sx, sy, 1.6 * s, CLEAR)
            c.capsule(root, peak, 1.6 * s, 1.1 * s, shade(tone, 0.25))
            c.capsule(peak, tip, 1.1 * s, 0.6 * s, shade(tone, 0.25))


def _draw_torso(c: Canvas, pose: Pose, spec: BodySpec, s: float) -> None:
    cloth = spec.cloth
    hip, chest = pose.hip, pose.chest
    w_top = 5.6 * s * spec.build
    w_bot = 4.2 * s * spec.build

    c.capsule(chest, hip, w_top, w_bot, cloth.dark)
    c.capsule((chest[0] - 0.5, chest[1] - 0.4), (hip[0] - 0.5, hip[1]), w_top * 0.82, w_bot * 0.82, cloth.core)
    c.capsule((chest[0] - 1.4, chest[1] - 0.6), (hip[0] - 1.6, hip[1] - 1.0), w_top * 0.34, w_bot * 0.3, cloth.light)

    if spec.cape in ("cloak", "shroud", "coat", "tatters"):
        # Robe skirt over the legs.
        hem = pose.ground_y - 5.0 * s if spec.cape != "coat" else hip[1] + 8.0 * s
        skirt = [
            (hip[0] - w_bot - 0.5, hip[1] - 1.0),
            (hip[0] + w_bot + 0.5, hip[1] - 1.0),
            (hip[0] + w_bot + 2.6 * s - pose.cape_sway * 0.4, hem),
            (hip[0] - w_bot - 2.8 * s - pose.cape_sway * 0.8, hem),
        ]
        c.polygon(skirt, cloth.dark)
        c.polygon([(x + 0.6, y - 0.6) for x, y in skirt[:3]] + [skirt[3]], cloth.core)
        c.line((skirt[0][0] + 1.0, skirt[0][1]), (skirt[3][0] + 2.0, skirt[3][1] - 1), cloth.light)
        c.line((hip[0] - 1.0, hip[1] + 1.0), (hip[0] - 2.0 - pose.cape_sway * 0.4, hem - 1), shade(cloth.dark, -0.3))
        c.line((hip[0] + 2.0, hip[1] + 1.0), (hip[0] + 2.6, hem - 1), shade(cloth.dark, -0.3))

    if spec.belt:
        c.capsule((hip[0] - w_bot, hip[1] - 1.0), (hip[0] + w_bot, hip[1] - 1.0), 1.4 * s, 1.4 * s, spec.accent.dark)
        c.set(round(hip[0] + 0.5), round(hip[1] - 1.5), spec.accent.light)

    if spec.shoulder_pads:
        for sh in (pose.shoulder_b, pose.shoulder_f):
            pad_w = min(3.4 * s * spec.build, 4.6 * s)
            c.ellipse(sh[0] - 0.5, sh[1] - 0.5, pad_w, pad_w * 0.72, spec.armor.dark)
            c.ellipse(sh[0] - 1.0, sh[1] - 1.2, pad_w * 0.7, pad_w * 0.46, spec.armor.core)
            c.set(round(sh[0] - 1.5), round(sh[1] - 2.0), spec.armor.hi)

    if spec.tall_collar:
        c.polygon(
            [
                (pose.neck[0] - 4.5 * s, pose.neck[1] + 2.0),
                (pose.neck[0] - 5.5 * s, pose.neck[1] - 6.0 * s),
                (pose.neck[0] - 1.0 * s, pose.neck[1] - 1.0),
                (pose.neck[0] + 4.0 * s, pose.neck[1] - 6.0 * s),
                (pose.neck[0] + 3.5 * s, pose.neck[1] + 2.0),
            ],
            spec.accent.dark if spec.accent else cloth.dark,
        )


def _draw_head(c: Canvas, pose: Pose, spec: BodySpec, s: float) -> None:
    hx, hy = pose.head
    r = pose.head_r
    kind = spec.head
    skin = spec.skin

    if kind in ("hood", "shroud", "veil"):
        # Cowl: face is a void with two burning points. Cheapest, strongest
        # gothic read there is.
        cowl = [
            (hx - r - 0.8, hy + r + 1.0),
            (hx - r - 1.2, hy - r * 0.4),
            (hx - r * 0.3, hy - r - 1.8),
            (hx + r * 0.9, hy - r * 0.6),
            (hx + r * 1.0, hy + r * 0.9),
        ]
        c.polygon(cowl, spec.cloth.dark)
        c.polygon([(x + 0.6, y + 0.4) for x, y in cowl], spec.cloth.core)
        c.line((hx - r * 0.9, hy - r - 1.0), (hx - r - 0.8, hy - r * 0.1), spec.cloth.light)
        c.ellipse(hx + r * 0.25, hy + r * 0.1, r * 0.8, r * 0.72, P.VOID)
        c.set(round(hx + r * 0.55), round(hy), spec.eye)
        c.set(round(hx + r * 0.55), round(hy - 1), with_alpha(spec.eye, 170))
        c.set(round(hx - r * 0.1), round(hy + 0.5), spec.eye)
        c.line((hx - r - 1.0, hy - r * 0.2), (hx - r * 0.2, hy - r - 1.6), spec.cloth.core)
        return

    # Skull / flesh base.
    base = P.R_BONE if kind == "skull" else skin
    c.ellipse(hx, hy, r, r * 1.06, base.dark)
    c.ellipse(hx - 0.6, hy - 0.6, r * 0.78, r * 0.82, base.core)
    c.ellipse(hx - 1.2, hy - 1.4, r * 0.4, r * 0.34, base.light)
    # Jaw.
    c.ellipse(hx + r * 0.35, hy + r * 0.55, r * 0.6, r * 0.45, base.dark)

    eye_y = round(hy - 0.2)
    c.set(round(hx + r * 0.5), eye_y, spec.eye)
    c.set(round(hx - r * 0.25), eye_y, spec.eye)
    if kind == "skull":
        c.set(round(hx + r * 0.5), eye_y + 1, shade(spec.eye, -0.5))
        c.set(round(hx - r * 0.25), eye_y + 1, shade(spec.eye, -0.5))
        c.set(round(hx + r * 0.2), round(hy + r * 0.45), P.VOID)
        for k in range(3):
            c.set(round(hx + r * 0.1 + k * 1.2), round(hy + r * 0.9), P.VOID)

    if kind == "hat":
        # Wide-brim tricorne, the witch-hunter silhouette.
        c.polygon(
            [
                (hx - r * 2.3, hy - r * 0.35),
                (hx + r * 2.0, hy - r * 0.35),
                (hx + r * 1.4, hy - r * 0.95),
                (hx - r * 1.6, hy - r * 0.95),
            ],
            spec.cloth.dark,
        )
        c.polygon(
            [
                (hx - r * 1.1, hy - r * 0.95),
                (hx + r * 1.0, hy - r * 0.95),
                (hx + r * 0.6, hy - r * 2.3),
                (hx - r * 0.7, hy - r * 2.3),
            ],
            spec.cloth.core,
        )
        c.hline(round(hx - r * 1.1), round(hx + r), round(hy - r * 1.3), spec.accent.core)
    elif kind == "helm":
        c.ellipse(hx, hy - 0.5, r * 1.15, r * 1.1, spec.armor.dark)
        c.ellipse(hx - 0.8, hy - 1.4, r * 0.8, r * 0.6, spec.armor.core)
        c.rect(round(hx - r * 0.4), eye_y - 1, round(r * 1.8), 2, P.VOID)
        c.set(round(hx + r * 0.5), eye_y, spec.eye)
        c.set(round(hx - r * 0.1), eye_y, spec.eye)
        c.vline(round(hx + r * 0.15), round(hy - r * 1.4), round(hy + r * 0.8), spec.armor.hi)
    elif kind == "crown":
        for k in range(4):
            px = hx - r * 1.0 + k * r * 0.7
            c.vline(round(px), round(hy - r * 1.1), round(hy - r * 2.0 - (k % 2)), spec.accent.core)
        c.hline(round(hx - r * 1.1), round(hx + r * 1.1), round(hy - r * 1.05), spec.accent.dark)
        c.set(round(hx), round(hy - r * 1.05), P.CRIMSON)
    elif kind == "mitre":
        c.polygon(
            [
                (hx - r * 1.1, hy - r * 0.7),
                (hx + r * 1.0, hy - r * 0.7),
                (hx + r * 0.2, hy - r * 3.0),
                (hx - r * 0.4, hy - r * 3.0),
            ],
            spec.cloth.core,
        )
        c.line((hx - r * 0.3, hy - r * 0.7), (hx - r * 0.1, hy - r * 2.9), spec.accent.core)
    elif kind == "mask":
        # Plague beak.
        c.polygon(
            [
                (hx + r * 0.2, hy - r * 0.5),
                (hx + r * 2.4, hy + r * 0.4),
                (hx + r * 0.2, hy + r * 0.8),
            ],
            P.R_LEATHER.core,
        )
        c.ellipse(hx, hy - 0.3, r * 1.0, r * 0.95, P.R_LEATHER.dark)
        c.set(round(hx + r * 0.35), eye_y, spec.eye)
        c.set(round(hx - r * 0.35), eye_y, spec.eye)
    elif kind == "rat":
        c.polygon([(hx + r * 0.3, hy), (hx + r * 2.2, hy + r * 0.5), (hx + r * 0.3, hy + r * 0.9)], base.dark)
        c.ellipse(hx - r * 0.5, hy - r * 1.1, r * 0.5, r * 0.6, base.dark)
        c.ellipse(hx + r * 0.4, hy - r * 1.2, r * 0.45, r * 0.55, base.dark)

    if spec.horns:
        for flip in (-1, 1):
            base_pt = (hx + flip * r * 0.75, hy - r * 0.6)
            mid = (base_pt[0] + flip * r * 0.5, base_pt[1] - r * 0.45)
            tip = (mid[0] - r * 0.25, mid[1] - r * 0.4)
            c.capsule(base_pt, mid, r * 0.22, r * 0.16, P.R_BONE.dark)
            c.capsule(mid, tip, r * 0.16, 0.5, P.R_BONE.core)


def _draw_aura(c: Canvas, pose: Pose, spec: BodySpec, s: float, t: float) -> None:
    if spec.aura is None:
        return
    col = spec.aura
    pulse = 0.6 + 0.4 * math.sin(t * math.tau)
    c.ellipse_blend(pose.chest[0], pose.chest[1] + 2, 9 * s, 12 * s, with_alpha(col, int(26 * pulse)))
    for k in range(5):
        a = (t + k / 5.0) * math.tau
        px = pose.chest[0] + math.cos(a) * 8.5 * s
        py = pose.chest[1] + math.sin(a * 1.3) * 8.0 * s - k * 0.6
        c.blend(round(px), round(py), with_alpha(col, 150))


def draw_figure(
    canvas: Canvas,
    spec: BodySpec,
    pose: Pose,
    *,
    t: float = 0.0,
    weapon_canvas: Canvas | None = None,
    flash: float = 0.0,
) -> None:
    """Composite one frame of the rig onto `canvas`."""
    s = spec.stature
    layer = Canvas(canvas.w, canvas.h)

    # Contact shadow first, on the ground plane rather than under the hips.
    shadow_w = 7.0 * s * (0.6 if pose.airborne else 1.0)
    layer.ellipse(pose.hip[0], pose.ground_y + 1, shadow_w, 2.4 * s, (0, 0, 0, 90))

    _draw_cape(layer, pose, spec, s)

    back = spec.cloth.tinted(P.VOID, 0.35)
    _limb(layer, pose.hip_b, pose.knee_b, 2.5 * s * spec.build, 2.1 * s, back)
    _limb(layer, pose.knee_b, pose.foot_b, 2.1 * s, 1.7 * s, back)
    _boot(layer, pose.foot_b, s, back)
    _limb(layer, pose.shoulder_b, pose.elbow_b, 2.2 * s * spec.build, 1.9 * s, back)
    _limb(layer, pose.elbow_b, pose.hand_b, 1.9 * s, 1.5 * s, back)

    _draw_torso(layer, pose, spec, s)

    _limb(layer, pose.hip_f, pose.knee_f, 2.7 * s * spec.build, 2.2 * s, spec.cloth)
    _limb(layer, pose.knee_f, pose.foot_f, 2.2 * s, 1.8 * s, spec.cloth)
    _boot(layer, pose.foot_f, s, P.R_LEATHER)

    if spec.tail:
        tail_a = (pose.hip[0] - 3.0 * s, pose.hip[1])
        tail_b = (tail_a[0] - 9.0 * s, tail_a[1] + 3.0 * s + pose.cape_sway)
        layer.capsule(tail_a, tail_b, 1.8 * s, 0.5, spec.skin.dark)

    _draw_head(layer, pose, spec, s)

    _limb(layer, pose.shoulder_f, pose.elbow_f, 2.4 * s * spec.build, 2.0 * s, spec.cloth)
    _limb(layer, pose.elbow_f, pose.hand_f, 2.0 * s, 1.6 * s, spec.skin)
    layer.circle(pose.hand_f[0], pose.hand_f[1], 1.7 * s, spec.skin.dark)

    # Weapon last: it is held in the near hand, so nothing may occlude it.
    # Grip sits at the weapon canvas centre, which is the rotation pivot too.
    if weapon_canvas is not None:
        layer.paste_rotated(weapon_canvas, pose.hand_f[0], pose.hand_f[1], -pose.weapon_angle)

    if spec.extra_arms:
        mid = ((pose.shoulder_b[0] + pose.hip[0]) / 2, (pose.shoulder_b[1] + pose.hip[1]) / 2)
        e2, h2 = _arm(mid, 55 + pose.cape_sway * 2, 30, s * 0.8)
        _limb(layer, mid, e2, 1.8 * s, 1.5 * s, back)
        _limb(layer, e2, h2, 1.5 * s, 1.2 * s, back)

    _draw_aura(layer, pose, spec, s, t)

    layer.outline_pass(spec.cloth.outline)
    layer.rim_light(P.MOONLIGHT, -1, -1, 105)

    if flash > 0.0:
        layer.flash((255, 255, 255, 255), flash)
    if pose.alpha < 1.0:
        layer.fade(pose.alpha)

    canvas.paste(layer, 0, 0)

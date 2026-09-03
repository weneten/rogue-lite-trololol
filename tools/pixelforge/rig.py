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
    ease_in,
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

    head: str = "hood"      # hood hat helm skull bare crown mask mitre veil rat jester
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
    # Beast options. A werewolf is not a hairy man: the reversed middle leg
    # joint and the ragged outline are what make the silhouette read as an
    # animal at 40 pixels tall, long before anyone sees the muzzle.
    digitigrade: bool = False   # hip -> knee -> hock -> paw
    fur: float = 0.0            # 0 smooth, 1 shaggy: spine ridge + joint tufts
    claws: bool = False         # hooked talons on hands and paws
    # Membrane wings that actually beat, one behind the body and one in front.
    # Distinct from cape="wings", which is a static pair of vampire drapes.
    # Value is the span in pixels before stature scaling; 0 disables.
    wingspan: float = 0.0
    # Membrane colour. Falls back to `cloth`, which is what a creature whose
    # wings are the same hide as its back wants; a bat with purple wings on a
    # grey body needs the two separated.
    wing: Ramp | None = None
    # Torn membrane. Holes are what stop a big flat wing reading as a cape.
    wing_holes: int = 0
    # 0 upright, 1 down on all fours: the spine goes horizontal, the hips drop
    # and the haunches fold. A gargoyle crouch, not a standing man with wings.
    crouch: float = 0.0
    # Skull charm hung at the throat.
    amulet: bool = False
    # A surcoat worn over the torso, in its own colour, with an emblem on the
    # chest. A knight in one flat cloth ramp is a monk; the panel and the
    # charge on it are the whole order.
    tabard: Ramp | None = None
    emblem: str = "none"    # none | cross
    # Heater shield strapped to the far arm. Drawn with the back limb, so it
    # sits behind the torso and reads as depth rather than as a plate glued to
    # the front of the sprite.
    shield: bool = False


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
    # Digitigrade rigs only; None on the humanoids.
    ankle_b: Vec2 | None = None
    ankle_f: Vec2 | None = None
    # Wing rigs only. flap runs -1 (raised) to +1 (driven down); flare scales
    # the span, so a screech throws them wide and a dive tucks them in.
    wing_flap: float = 0.0
    wing_flare: float = 1.0
    # 0 shut, 1 gaping. Only the beast heads use it.
    mouth_open: float = 0.0
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


def _leg_digi(hip: Vec2, thigh_deg: float, shin_deg: float, s: float) -> tuple[Vec2, Vec2, Vec2]:
    """Beast leg: femur forward, hock kicking back, long paw forward again.

    Total reach is kept at ~18*s, the same as the humanoid leg, so the shared
    hip height and the foot-pin correction in `build_pose` still hold.
    """
    knee = _joint(hip, thigh_deg + 24.0, 8.0 * s)
    ankle = _joint(knee, thigh_deg + shin_deg * 0.6 - 38.0, 8.0 * s)
    toe = _joint(ankle, thigh_deg * 0.4 + shin_deg * 0.3 + 34.0, 5.0 * s)
    return knee, ankle, toe


# Weapon-arm angle curves, one entry per attack frame. Sharp acceleration
# between frames 1 and 3 is what sells the impact.
_SWING = {
    "slash": [-35, -60, -10, 40, 55, 20],
    "thrust": [-20, -50, -8, 38, 25, 5],
    "cast": [-30, -70, -80, -60, -30, -5],
    "shoot": [-15, -35, -8, -8, -14, -10],
    "smash": [-55, -85, -25, 55, 75, 40],
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
    wing_flap = 0.0
    wing_flare = 1.0
    mouth_open = 0.0
    # Lateral weight shift, shoulder-line rotation and how far the head
    # leads the spine. Small numbers, but they are the difference between
    # a rig moving and a body moving. `sway` moves the upper body over the
    # hips, NOT the whole figure — sliding the character sideways takes the
    # planted feet with it, which in the character-select panel (a still
    # sprite at 3x zoom) read as the Hunter shuffling on the spot.
    sway = 0.0
    twist = 0.0
    head_lead = 0.0
    # Ribcage lift. Breathing raises the chest, not the pelvis; driving it
    # off `bob` lifted the hips and took the feet off the floor with them.
    chest_rise = 0.0
    # How hard the support foot is held to the ground line, 0..1. 1 pins it
    # exactly; below 1 the figure keeps some of its own vertical travel, which
    # is what gives a run its flight phase. 0 disables the pin entirely.
    foot_plant = 1.0

    if anim == "idle":
        # Three waves, not one. Every joint used to ride the same sine, which
        # is a pulse rather than a body: lungs, spine and cloth all reached
        # their extreme on the same frame and the figure read as a breathing
        # statue. Each layer now trails the one driving it, so the pose is
        # never symmetrical and the loop has no visible seam.
        breath = math.sin(t * math.tau)
        settle = math.sin((t - 0.14) * math.tau)   # spine follows the lungs
        drift = math.sin((t - 0.28) * math.tau)    # limbs and cloth trail both
        # The pelvis barely moves; the ribcage does the breathing. Lifting the
        # hips instead pulled both feet off the floor for half the loop, and
        # then sank them through it for the other half.
        bob = -0.3 - breath * 0.35
        chest_rise = 0.55 + breath * 0.85
        # Weight rocks between the feet. A hand's width of travel is enough at
        # this size and it is what stops the stance reading as bolted down.
        sway = drift * 0.7
        twist = drift * 2.4
        head_lead = settle * 0.6
        arm_b_u = 16 + drift * 5
        # Slightly behind the hip line so the near sleeve rides the coat
        # instead of poking out in front of it.
        arm_f_u = -8 + drift * 3
        # Enough bend to show an elbow. Upper arm and forearm nearly collinear
        # drew the whole limb as a single unbroken bar.
        arm_b_f = 26 + settle * 4
        arm_f_f = 23 + settle * 4
        weapon_angle = -74 + drift * 5
        cape_sway = drift * 2.1
        # A degree of stance change either way. The foot pin turns it into a
        # small vertical settle that is driven by the legs rather than painted
        # on over them.
        thigh_b, thigh_f = -4.0 + drift * 1.2, 4.0 + drift * 1.2
        shin_b, shin_f = 4.0, -2.0
        wing_flap = math.sin(t * math.tau) * 0.85
        if spec.hover:
            bob = -2.0 - breath * 2.5
            sway = drift * 1.2
            thigh_b, thigh_f = -12.0, 10.0
            shin_b, shin_f = 14.0, 16.0
            airborne = True
        if spec.wingspan > 0.0:
            # A hovering bat is held up by the beat, so the body rides the
            # downstroke rather than breathing on the spot.
            bob = -2.5 - wing_flap * 2.2

    elif anim == "run":
        ph = t * math.tau
        swing_amt = 30.0
        thigh_f = math.sin(ph) * swing_amt
        thigh_b = math.sin(ph + math.pi) * swing_amt
        # Knees only bend on the recovery half of the stride.
        # Deep enough that the swing foot visibly clears the floor. Now that
        # the pin moves the body instead of the boots, the knee bend is the
        # only thing lifting that foot, so it has to do the whole job.
        shin_f = max(0.0, -math.sin(ph - 0.6)) * 44.0
        shin_b = max(0.0, -math.sin(ph + math.pi - 0.6)) * 44.0
        # Weight curve, one per footfall. The legs are most spread at ph 90
        # and 270 — those are the contacts, and the body is lowest there; the
        # legs cross at ph 0 and 180 and the body is highest. Both previous
        # curves had this wrong: `-abs(sin(2*ph))` dipped four times per
        # stride, and the cos form after it was a half-cycle out of phase, so
        # the body rose into each footfall instead of settling onto it.
        bob = -(1.0 + math.cos((ph - 0.3) * 2.0)) * 0.5 * 3.0 - 0.4
        # Planted through the contact, half-free at the pass so the figure
        # keeps some lift between steps rather than skating along the floor.
        foot_plant = 0.5 + 0.5 * abs(math.sin(ph))
        lean += 9.0 + math.sin(ph * 2.0) * 1.6
        # Shoulders counter-rotate against the hips — the thing that separates
        # a run from a pair of scissoring legs under a rigid torso.
        twist = -math.sin(ph) * 4.2
        head_lead = math.sin(ph * 2.0) * 0.7
        arm_b_u = 18 + math.sin(ph) * 34
        arm_f_u = -16 + math.sin(ph + math.pi) * 24
        # The elbow closes on the forward swing and opens on the back swing.
        arm_b_f = 26 + max(0.0, math.sin(ph)) * 16
        arm_f_f = 24 + max(0.0, math.sin(ph + math.pi)) * 14
        # Held close over the back/shoulder rather than swinging wide with
        # the arm: a long weapon (scythe, cleaver) tracking the full arm
        # swing reads as a streamer trailing off the silhouette.
        weapon_angle = -72 + math.sin(ph + math.pi) * 5
        # Cloth lags the body by an eighth of a stride. The oscillation stays
        # well under the base: a running figure's cloak trails behind for the
        # whole stride, and an amplitude that reached zero made it hang dead
        # straight for three frames out of eight.
        cape_sway = 3.4 + math.sin(ph - 0.35) * 1.4
        wing_flap = math.sin(ph)
        wing_flare = 1.05
        if spec.wingspan > 0.0:
            bob = -3.0 - wing_flap * 2.6
        if spec.hover:
            thigh_f, thigh_b = 18.0, -14.0
            shin_f, shin_b = 20.0, 24.0
            bob = -3.0 - abs(math.sin(ph)) * 2.0
            twist = 0.0
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
        # Wind up away from the target, then drive through it. Torso rotation
        # is where a swing gets its weight; the arm alone is a wave.
        twist = lerp(-5.0, 7.0, ease_out(min(1.0, max(0.0, (t - 0.25)) / 0.5)))
        head_lead = twist * 0.25
        sway = -1.0 if t < 0.35 else 1.6
        arm_b_u = 24 - arm_f_u * 0.25
        arm_f_f = 22 if t < 0.4 else 16
        thigh_f = 16 if t > 0.35 else 6
        thigh_b = -14 if t > 0.35 else -6
        shin_f, shin_b = 4, 10
        cape_sway = -4.0 if t < 0.35 else 5.0
        # Rear back, then throw the wings open on the release: the flare is
        # the wind-up tell, and it is what makes a screech read as an attack
        # rather than as one more hover frame.
        wing_flap = lerp(-0.95, 0.45, ease_out(t))
        wing_flare = 1.0 + 0.42 * math.sin(min(1.0, t * 1.15) * math.pi)
        # Snaps open early and holds: a scream is a sustained note, not a bite.
        mouth_open = ease_out(min(1.0, t * 2.2))

    elif anim == "hurt":
        # `snap` is the hit itself: 1 on the impact frame, 0 once recovered.
        # Driving everything off it means the third frame is already most of
        # the way back to idle, so the flinch reads as a recoil-and-recover
        # rather than as a pose the character is left standing in.
        snap = 1.0 - ease_out(t)
        lean += -4.0 - 22.0 * snap
        bob = -1.5 - snap * 1.5
        tilt = -11.0 * snap
        sway = -1.7 * snap
        twist = -4.5 * snap
        head_lead = -1.3 * snap
        arm_b_u = lerp(24.0, 46.0, snap)
        arm_f_u = lerp(-16.0, -44.0, snap)
        weapon_angle = -60
        thigh_b = lerp(-8.0, -20.0, snap)
        thigh_f = lerp(6.0, 15.0, snap)
        shin_b = lerp(10.0, 20.0, snap)
        shin_f = lerp(2.0, 6.0, snap)
        cape_sway = -6.5 * snap
        wing_flap = lerp(-0.1, -0.4, snap)
        wing_flare = lerp(1.0, 0.72, snap)
        mouth_open = 0.45 * snap

    elif anim == "death":
        # Two stages rather than one ramp. A body that starts sinking on
        # frame one has no moment of being hit; it just deflates. So: a
        # short stagger backwards, then the knees go and it comes down,
        # then it settles and thins out.
        stagger = ease_out(min(1.0, t / 0.26))
        k = ease_in_out(max(0.0, (t - 0.2)) / 0.8)
        tilt = -7.0 * stagger - 24.0 * k
        # The hips sink toward planted feet rather than the whole body sliding
        # down the cell: `drop` moves the feet too, and at any useful amount it
        # pushed the legs clean off the bottom of the 64px frame.
        drop = 3.0 * k
        bob = -1.2 * stagger + 10.0 * k
        # No pin: the whole point is that the body goes down through its own
        # stance. Holding the feet to the ground line would stand it back up.
        foot_plant = 0.0
        lean += -6.0 * stagger - 16.0 * k
        sway = -1.8 * stagger - 1.0 * k
        twist = -3.0 * stagger
        head_lead = -1.0 * stagger + 1.4 * k
        # Arms fold toward the body rather than flying out behind it, and the
        # weapon rotates down to hang from the hand. Both were widening the
        # silhouette exactly as it should have been getting smaller.
        arm_b_u = lerp(40, 62, k)
        arm_f_u = lerp(-40, -6, k)
        weapon_angle = lerp(-70, -18, k)
        thigh_b = lerp(-18, -22, k)
        thigh_f = lerp(14, 18, k)
        shin_b = lerp(20, 26, k)
        shin_f = lerp(8, 14, k)
        # Holds opaque through the fall and only thins out once it is down —
        # a body that starts fading while it is still on its feet reads as a
        # teleport rather than a death.
        alpha = 1.0 if t < 0.68 else lerp(1.0, 0.2, (t - 0.68) / 0.32)
        cape_sway = -3.0 * stagger - 7.0 * k
        # Wings fold as it comes down. A corpse with the span still spread
        # reads as a kite, not a body.
        wing_flap = lerp(-0.2, 0.85, k)
        wing_flare = lerp(1.0, 0.4, k)
        mouth_open = 0.5 * stagger * (1.0 - k)

    elif anim == "dash":
        # Coil, drive, land. The old curve started at full extension, so the
        # dash had no push-off — the character was already travelling on
        # frame one and simply slowed down.
        drive = ease_out(min(1.0, t / 0.34))
        settle = ease_in(max(0.0, (t - 0.56)) / 0.44)
        # Deep crouch, then thrown forward, then upright again on the landing.
        lean += lerp(6.0, 30.0, drive) - 22.0 * settle
        bob = lerp(2.0, -5.0, drive) + 5.0 * settle
        sway = lerp(-1.5, 1.5, drive) - 0.8 * settle
        twist = lerp(3.0, -3.5, drive)
        head_lead = lerp(-0.8, 1.4, drive) - 1.0 * settle
        thigh_f = lerp(26.0, 8.0, drive) + 10.0 * settle
        thigh_b = lerp(-6.0, -26.0, drive) + 14.0 * settle
        shin_f = lerp(24.0, 4.0, drive) + 8.0 * settle
        shin_b = lerp(6.0, 22.0, drive) - 8.0 * settle
        arm_b_u = lerp(58.0, 14.0, drive) + 14.0 * settle
        arm_f_u = lerp(-20.0, -52.0, drive) + 22.0 * settle
        arm_b_f = 22.0
        arm_f_f = lerp(30.0, 14.0, drive)
        weapon_angle = lerp(-70, -25, drive)
        cape_sway = lerp(2.0, 9.0, drive) - 3.0 * settle
        # Feet are only off the ground between the push-off and the landing.
        airborne = drive > 0.35 and settle < 0.5
        # The dive: swept back and tucked, driving down.
        wing_flap = lerp(0.55, 0.95, drive)
        wing_flare = lerp(0.62, 0.48, drive)
        # Coming down mouth-first.
        mouth_open = lerp(0.3, 0.85, drive)

    if spec.shield:
        # A shield arm is braced across the body, not swinging free. Left on
        # the normal arm curve the board swung clear of the sprite on every
        # stride and read as a second object flying alongside the character.
        arm_b_u = lerp(arm_b_u, 12.0, 0.76)
        arm_b_f = lerp(arm_b_f, 34.0, 0.76)

    crouch = max(0.0, min(1.0, spec.crouch))
    feet = feet_y + drop
    ground_y = feet_y
    hip_y = feet - lerp(18.0, 10.0, crouch) * s + bob
    lean_off = math.tan(math.radians(lean)) * 12.0 * s
    # Crouching trades spine height for spine reach: the chest and head move
    # forward instead of up, which is the whole difference between a beast on
    # all fours and a person leaning over.
    spine_up = lerp(12.0, 5.0, crouch) * s
    spine_out = 10.5 * crouch * s
    hip = (cx, hip_y)
    # `sway` and `chest_rise` ride the spine the same way `lean` does: nothing
    # below the hips knows about either, so the stance stays where the legs
    # put it.
    chest = (cx + lean_off * 0.75 + spine_out + sway * 0.75, hip_y - spine_up - chest_rise)
    neck = (cx + lean_off + spine_out * 1.3 + sway,
            hip_y - lerp(16.0, 7.0, crouch) * s - chest_rise * 1.1)
    head_r = 3.9 * s * (1.0 + 0.42 * crouch)
    head = (cx + lean_off * 1.25 + spine_out * 1.75 + math.sin(math.radians(tilt)) * 6.0
            + head_lead + sway * 1.25,
            hip_y - lerp(21.5, 9.5, crouch) * s + abs(tilt) * 0.06 - chest_rise * 1.15)

    if crouch > 0.0:
        # Forelimbs come down to meet the ground the body is now over.
        arm_b_u = lerp(arm_b_u, 24.0, crouch * 0.75)
        arm_f_u = lerp(arm_f_u, 32.0, crouch * 0.55)
        arm_b_f = lerp(arm_b_f, 28.0, crouch * 0.6)
        arm_f_f = lerp(arm_f_f, 26.0, crouch * 0.6)

    # Shoulder spacing has to track the torso, which is `5.6 * s * build` wide
    # at the chest. A flat 5.8 put the near shoulder at 2.9*s — well inside
    # that — so the arm hung down the middle of the chest. 8.4 overshot the
    # other way: the near limb sat entirely in front of the silhouette and
    # read as a slab glued to the coat. 6.4 keeps the joint on the chest edge
    # so the sleeve overlays the torso instead of hanging off it.
    sh_dx = 6.4 * s * spec.build
    # `twist` rotates the shoulder line in plan view: the near shoulder swings
    # further than the far one and both drop slightly as they come forward,
    # which is as much three-quarter turn as a side-on rig can show.
    shoulder_b = (chest[0] - sh_dx * 0.5 - twist * 0.35, chest[1] + 1.0 - twist * 0.12)
    shoulder_f = (chest[0] + sh_dx * 0.5 + twist * 0.65, chest[1] + 1.5 + twist * 0.12)
    elbow_b, hand_b = _arm(shoulder_b, arm_b_u, arm_b_f, s)
    elbow_f, hand_f = _arm(shoulder_f, arm_f_u, arm_f_f, s)

    hip_b = (hip[0] - 3.0 * s, hip[1])
    hip_f = (hip[0] + 3.0 * s, hip[1])
    ankle_b = ankle_f = None
    # Segments shrink with the crouch. The hip is lower but the leg is the same
    # length, so without this the feet punch straight through the cell floor.
    leg_s = s * lerp(1.0, 0.62, crouch)
    if spec.digitigrade:
        knee_b, ankle_b, foot_b = _leg_digi(hip_b, thigh_b, shin_b, leg_s)
        knee_f, ankle_f, foot_f = _leg_digi(hip_f, thigh_f, shin_f, leg_s)
    else:
        knee_b, foot_b = _leg(hip_b, thigh_b, shin_b, leg_s)
        knee_f, foot_f = _leg(hip_f, thigh_f, shin_f, leg_s)

    if not airborne and foot_plant > 0.0:
        # Plant the support foot by moving the FIGURE, not the foot.
        #
        # The rig is built hip-downward, so the feet land wherever the leg
        # angles put them: a straight-legged stance reaches ~18*s, a stance
        # spread 30 degrees only ~15.6*s. Something has to close that gap or
        # the character walks two and a half pixels above the floor.
        #
        # The old code closed it by pushing the feet down and leaving the
        # knees where they were, which was wrong twice over. The shins
        # stretched by up to five pixels on a forty-pixel character; and
        # because it moved BOTH feet by the same amount, neither foot ever
        # lifted or planted — the legs scissored while the boots stayed glued
        # together at one height. A shuffle on stilts.
        #
        # Translating the whole figure instead keeps every limb its true
        # length, sits the support foot exactly on the ground line, and leaves
        # the swing foot the clearance the leg angles actually gave it. The
        # shift runs both ways, so a stance that would sink through the floor
        # is lifted out of it as readily as a floating one is set down.
        shift = (feet - max(foot_b[1], foot_f[1])) * foot_plant
        if abs(shift) > 0.001:
            hip = (hip[0], hip[1] + shift)
            chest = (chest[0], chest[1] + shift)
            neck = (neck[0], neck[1] + shift)
            head = (head[0], head[1] + shift)
            shoulder_b = (shoulder_b[0], shoulder_b[1] + shift)
            elbow_b = (elbow_b[0], elbow_b[1] + shift)
            hand_b = (hand_b[0], hand_b[1] + shift)
            shoulder_f = (shoulder_f[0], shoulder_f[1] + shift)
            elbow_f = (elbow_f[0], elbow_f[1] + shift)
            hand_f = (hand_f[0], hand_f[1] + shift)
            hip_b = (hip_b[0], hip_b[1] + shift)
            knee_b = (knee_b[0], knee_b[1] + shift)
            foot_b = (foot_b[0], foot_b[1] + shift)
            hip_f = (hip_f[0], hip_f[1] + shift)
            knee_f = (knee_f[0], knee_f[1] + shift)
            foot_f = (foot_f[0], foot_f[1] + shift)
            if ankle_b is not None:
                ankle_b = (ankle_b[0], ankle_b[1] + shift)
                ankle_f = (ankle_f[0], ankle_f[1] + shift)

    return Pose(
        hip=hip, chest=chest, neck=neck, head=head, head_r=head_r,
        shoulder_b=shoulder_b, elbow_b=elbow_b, hand_b=hand_b,
        shoulder_f=shoulder_f, elbow_f=elbow_f, hand_f=hand_f,
        hip_b=hip_b, knee_b=knee_b, foot_b=foot_b,
        hip_f=hip_f, knee_f=knee_f, foot_f=foot_f,
        ankle_b=ankle_b, ankle_f=ankle_f,
        wing_flap=wing_flap, wing_flare=wing_flare, mouth_open=mouth_open,
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


def _paw(c: Canvas, ankle: Vec2, toe: Vec2, s: float, ramp: Ramp, claw: RGBA | None) -> None:
    """Metatarsus plus a splayed pad. Wider and flatter than a boot, which is
    most of what stops the hind leg reading as a shin in a stocking."""
    c.capsule(ankle, toe, 1.9 * s, 1.5 * s, ramp.dark)
    c.ellipse(toe[0] + 1.3 * s, toe[1], 3.6 * s, 1.8 * s, ramp.dark)
    c.ellipse(toe[0] + 1.1 * s, toe[1] - 0.8, 2.7 * s, 1.0 * s, ramp.core)
    if claw is not None:
        for k in range(3):
            cy = toe[1] - 0.8 + k * 1.1
            c.line((toe[0] + 3.2 * s, cy), (toe[0] + 5.0 * s, cy + 0.7), claw)


def _draw_claws(c: Canvas, elbow: Vec2, hand: Vec2, s: float, tone: RGBA) -> None:
    """Three hooks fanned along the forearm axis, so they swing with the arm
    instead of pointing at a fixed corner of the cell."""
    dx, dy = hand[0] - elbow[0], hand[1] - elbow[1]
    d = math.hypot(dx, dy) or 1.0
    base = math.atan2(dy / d, dx / d)
    for k in range(3):
        a = base + math.radians(-26 + k * 26)
        tip = (hand[0] + math.cos(a) * 3.6 * s, hand[1] + math.sin(a) * 3.6 * s)
        c.capsule(hand, tip, 0.9 * s, 0.4, tone)


def _fur_fringe(c: Canvas, pose: Pose, spec: BodySpec, s: float) -> None:
    """Shaggy spikes down the spine and off every joint.

    Fur at this size is a silhouette problem, not a texture problem — a
    smooth outline reads as armour no matter what colour it is painted.
    """
    if spec.fur <= 0.0:
        return

    amt = spec.fur
    ramp = spec.cloth
    spine = shade(ramp.dark, -0.28)

    for k in range(6):
        f = k / 5.0
        bx = lerp(pose.neck[0], pose.hip[0], f) - (3.4 + f * 1.4) * s
        by = lerp(pose.neck[1], pose.hip[1], f)
        tip = (
            bx - (2.8 + (k % 2) * 2.0) * s * amt - pose.cape_sway * 0.35,
            by - (1.8 - f * 3.0) * s * amt,
        )
        c.capsule((bx + 1.0, by), tip, 1.5 * s, 0.5, spine)

    for joint_pt, far in (
        (pose.elbow_b, True), (pose.knee_b, True),
        (pose.elbow_f, False), (pose.knee_f, False),
    ):
        tone = shade(ramp.dark, -0.32) if far else ramp.dark
        c.capsule(
            joint_pt,
            (joint_pt[0] - 4.2 * s * amt, joint_pt[1] + 2.2 * s),
            1.7 * s, 0.5, tone,
        )


def _draw_leg(
    c: Canvas, spec: BodySpec, s: float,
    hip: Vec2, knee: Vec2, ankle: Vec2 | None, foot: Vec2,
    ramp: Ramp, foot_ramp: Ramp,
    r_hip: float, r_knee: float, r_foot: float,
) -> None:
    """One leg, humanoid or digitigrade. Radii are passed in rather than
    derived, so the beast branch cannot quietly restyle the whole cast."""
    _limb(c, hip, knee, r_hip, r_knee, ramp)
    if ankle is None:
        _limb(c, knee, foot, r_knee, r_foot, ramp)
        _boot(c, foot, s, foot_ramp)
        return

    _limb(c, knee, ankle, r_knee, r_foot, ramp)
    _paw(c, ankle, foot, s, foot_ramp, P.R_BONE.light if spec.claws else None)


# Membrane wing in a local frame that points back-and-out from the shoulder,
# then rotated by the flap. Building it flat and rotating once is what keeps
# the finger struts and the scalloped trailing edge consistent through the
# whole beat — posing each strut separately makes the membrane tear open on
# the extremes.
# The arm bone climbs before it reaches out, so the wrist sits above the
# shoulder and the membrane hangs from an arch. A wing that only goes outward
# reads as a cape no matter how it is shaded.
_WING_ELBOW = (-0.34, -0.58)
_WING_WRIST = (-0.94, -0.82)
# Where the finger tips land, in the same span units. They fan down and back
# from the wrist; the last one anchors the membrane to the hip.
_WING_TIPS = ((-1.16, -0.14), (-1.00, 0.36), (-0.70, 0.68), (-0.30, 0.82))
# Tears in the membrane, as (u, v) centres and a radius in span units.
_WING_HOLES = ((-0.86, 0.06, 0.10), (-0.58, 0.34, 0.075), (-0.95, -0.42, 0.065))


def _draw_bat_wing(c: Canvas, pose: Pose, spec: BodySpec, s: float, near: bool) -> None:
    span = spec.wingspan * s * pose.wing_flare
    if span <= 0.0:
        return

    membrane = spec.wing if spec.wing is not None else spec.cloth

    # The two wings sweep opposite ways — the far one back, the near one
    # forward over the camera side. Both pointing the same way was the whole
    # reason the first pass read as a cloak instead of a wingspan.
    if near:
        span *= 0.84
        # A beat behind, so the pair never freezes into one symmetrical shape.
        flap = pose.wing_flap * 0.86
        # Rooted behind the shoulder: swept forward from the shoulder itself it
        # reached across the muzzle and swallowed the whole face.
        root = (pose.shoulder_f[0] - 2.6 * s, pose.shoulder_f[1] + 0.5)
        tone = membrane.tinted(P.SMOKE, 0.16)
        mirror = -1.0
    else:
        flap = pose.wing_flap
        root = (pose.shoulder_b[0] - 1.0 * s, pose.shoulder_b[1] - 0.5)
        tone = membrane.tinted(P.VOID, 0.42)
        mirror = 1.0

    # Screen y grows downward, so a raised wing needs the positive angle. The
    # frame is already arched, so the beat rides on top of it rather than
    # sweeping the wing from overhead to underfoot.
    angle = math.radians(lerp(26.0, -22.0, (flap + 1.0) * 0.5)) * mirror
    cos_a, sin_a = math.cos(angle), math.sin(angle)

    def place(u: float, v: float) -> Vec2:
        x, y = u * span * mirror, v * span
        return (root[0] + x * cos_a - y * sin_a, root[1] + x * sin_a + y * cos_a)

    elbow = place(*_WING_ELBOW)
    wrist = place(*_WING_WRIST)
    tips = [place(*tip) for tip in _WING_TIPS]

    # Membrane: leading edge out to the wrist, then the trailing edge home,
    # notched between the fingers so the outline reads as skin over bone.
    outline = [root, elbow, wrist]
    for i, tip in enumerate(tips):
        outline.append(tip)
        if i < len(tips) - 1:
            mid_u = (_WING_TIPS[i][0] + _WING_TIPS[i + 1][0]) * 0.5
            mid_v = (_WING_TIPS[i][1] + _WING_TIPS[i + 1][1]) * 0.5
            outline.append(place(mid_u * 0.78, mid_v * 0.78))

    c.polygon(outline, tone.dark)
    # Inner sheen, pulled toward the arm so the membrane looks stretched.
    inner = [(lerp(p[0], elbow[0], 0.16), lerp(p[1], elbow[1], 0.16) - 0.5) for p in outline]
    c.polygon(inner, tone.core)

    # Tears. Punched after the fills and before the struts, so a strut can
    # still cross a hole the way a finger bone crosses a rip.
    for i in range(min(spec.wing_holes, len(_WING_HOLES))):
        hu, hv, hr = _WING_HOLES[i]
        centre = place(hu, hv)
        c.circle(centre[0], centre[1], max(1.0, hr * span), CLEAR)

    strut = shade(tone.dark, -0.34)
    for tip in tips:
        c.line(wrist, tip, strut)

    c.line(root, tips[-1], strut)
    c.capsule(root, elbow, 2.0 * s, 1.5 * s, tone.light)
    c.capsule(elbow, wrist, 1.5 * s, 0.7 * s, tone.light)
    # Thumb hook at the wrist — the claw every bat wing has, and the detail
    # that stops the shape reading as a cape corner. Small and dull: at bone
    # white it was a pale bar hanging off each wing tip.
    hook = place(_WING_WRIST[0] - 0.04, _WING_WRIST[1] - 0.11)
    c.capsule(wrist, hook, 0.7 * s, 0.4, shade(P.R_BONE.dark, -0.15))


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

    elif kind == "mane":
        # A ruff over the shoulders instead of cloth. The wolf has no cape, so
        # the fur has to carry the whole upper silhouette by itself.
        base = shade(ramp.dark, -0.14)
        root = (pose.chest[0] - 0.5 * s, pose.chest[1] + 1.0 * s)
        for k in range(9):
            a = math.radians(-188 + k * 27)
            length = (7.8 + (k % 3) * 2.8) * s
            tip = (
                root[0] + math.cos(a) * length - sway * 0.4,
                root[1] + math.sin(a) * length * 0.8,
            )
            c.capsule(root, tip, 2.2 * s, 0.5, base)
        c.ellipse(root[0] - 0.4 * s, root[1] - 0.5, 5.6 * s, 4.2 * s, ramp.dark)
        c.ellipse(root[0] - 1.4 * s, root[1] - 1.8, 3.2 * s, 2.2 * s, ramp.core)

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
        # The hem is carried by the legs inside it, so it parts around the
        # leading foot and drags behind the trailing one. Without this a robed
        # hunter runs as a rigid bell with two boots appearing under it, and
        # for the half of the stride where the near leg is tucked up in
        # recovery there is nothing left moving at all.
        lead = (pose.foot_f[0] - hip[0]) * 0.45
        trail = (pose.foot_b[0] - hip[0]) * 0.45
        skirt = [
            (hip[0] - w_bot - 0.5, hip[1] - 1.0),
            (hip[0] + w_bot + 0.5, hip[1] - 1.0),
            (hip[0] + w_bot + 2.6 * s - pose.cape_sway * 0.4 + lead, hem),
            (hip[0] - w_bot - 2.8 * s - pose.cape_sway * 0.8 + trail, hem),
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
        # Seated inboard of the joint. The pads used to be centred on the
        # shoulders themselves, which was fine while those sat close together;
        # once shoulder spacing started tracking the torso width the pair drew
        # as two separate balls floating off either side of the neck.
        pad_w = min(3.0 * s * spec.build, 4.2 * s)
        for sh in (pose.shoulder_b, pose.shoulder_f):
            px = lerp(chest[0], sh[0], 0.62)
            c.ellipse(px - 0.5, sh[1] - 0.5, pad_w, pad_w * 0.72, spec.armor.dark)
            c.ellipse(px - 1.0, sh[1] - 1.2, pad_w * 0.7, pad_w * 0.46, spec.armor.core)
            c.set(round(px - 1.5), round(sh[1] - 2.0), spec.armor.hi)

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


def _draw_tabard(c: Canvas, pose: Pose, spec: BodySpec, s: float) -> None:
    """A surcoat panel down the front of the torso, with a charge on it.

    Drawn after the near leg on purpose: a surcoat hangs over the thigh, and
    the first pass put it under the leg where two thirds of it — the whole
    lower half, cross included — was covered by the trouser.

    Narrower than the torso, also on purpose: the cloth of the body has to
    stay visible either side, or the panel stops reading as a garment worn
    over armour and becomes the character's only colour.
    """
    ramp = spec.tabard
    if ramp is None:
        return

    hip, chest = pose.hip, pose.chest
    top_w = 3.4 * s * spec.build
    bot_w = 3.0 * s * spec.build
    hem = hip[1] + 8.0 * s
    # Hangs off the body rather than being painted on it, so it drags with
    # the same sway the cape does.
    drag = pose.cape_sway * 0.35
    panel = [
        (chest[0] - top_w, chest[1] + 0.5 * s),
        (chest[0] + top_w * 0.85, chest[1] + 0.5 * s),
        (hip[0] + bot_w * 0.9 - drag, hem),
        (hip[0] - bot_w - drag * 1.4, hem),
    ]
    c.polygon(panel, ramp.dark)
    c.polygon([(x + 0.7, y + 0.6) for x, y in panel[:2]]
              + [(panel[2][0] - 0.5, panel[2][1] - 1.2), (panel[3][0] + 1.2, panel[3][1] - 1.2)],
              ramp.core)
    # Shadowed far edge, lit near edge.
    c.line((panel[0][0] + 0.4, panel[0][1] + 1.0), (panel[3][0] + 1.4, panel[3][1] - 1.0),
           shade(ramp.dark, -0.3))
    c.line((panel[1][0] - 1.0, panel[1][1] + 1.0), (panel[2][0] - 1.2, panel[2][1] - 1.5),
           ramp.light)

    if spec.emblem == "cross":
        # Two bars, three or four pixels of arm at hunter scale. Any bigger and
        # the chest is all charge; any smaller and it is a smudge.
        # Pushed to the far side of the panel: on the spine the near sleeve
        # swings across it and the charge disappears for half of every cycle.
        cxp = chest[0] - 1.7 * s
        cyp = chest[1] + 4.0 * s
        arm = max(1.0, 1.4 * s)
        c.vline(round(cxp), round(cyp - arm * 1.4), round(cyp + arm * 1.7), spec.accent.dark)
        c.hline(round(cxp - arm), round(cxp + arm), round(cyp), spec.accent.dark)
        c.set(round(cxp), round(cyp), spec.accent.core)
        c.set(round(cxp), round(cyp - arm), spec.accent.core)


def _draw_shield(c: Canvas, pose: Pose, spec: BodySpec, s: float) -> None:
    """A heater shield centred on the far hand.

    Two things it must not do, both of which the first pass did. It must sit
    *on* the hand rather than beside it — offset along the forearm axis, the
    board floated away from the fist as soon as the arm swung. And it is on
    the far arm, so it is shaded down toward the back-limb tone; drawn in
    plain armour white beside a bone surcoat it was the brightest thing on
    the sprite and read as a flag.
    """
    if not spec.shield:
        return

    face = spec.armor.tinted(P.VOID, 0.30)
    fx, fy = pose.hand_b
    # A shield is carried a little in front of and above the fist, and it
    # tilts with the forearm rather than tracking it end to end.
    dx, dy = fx - pose.elbow_b[0], fy - pose.elbow_b[1]
    d = math.hypot(dx, dy) or 1.0
    tilt = (dx / d) * 1.6 * s
    cxp, cyp = fx + 3.0 * s, fy - 1.2 * s

    w = 3.6 * s
    h = 5.4 * s
    # Flat top, straight sides, point at the bottom — the heater outline.
    pts = [
        (cxp - w + tilt, cyp - h * 0.62),
        (cxp + w + tilt, cyp - h * 0.62),
        (cxp + w * 0.92, cyp + h * 0.1),
        (cxp + w * 0.1, cyp + h * 0.72),
        (cxp - w * 0.92, cyp + h * 0.1),
    ]
    c.polygon(pts, face.dark)
    c.polygon([(x + 0.8, y + 0.7) for x, y in pts[:2]] + [pts[2], pts[3], pts[4]], face.core)
    # Rim and boss. Two details, and they are what stop it reading as a plank.
    c.line(pts[0], pts[1], face.light)
    c.circle(cxp, cyp - h * 0.05, 1.1 * s, shade(spec.accent.dark, -0.25))


def _draw_head(c: Canvas, pose: Pose, spec: BodySpec, s: float) -> None:
    hx, hy = pose.head
    r = pose.head_r
    kind = spec.head
    skin = spec.skin

    # Neck: a two-pixel column between collar and skull. Without it the head
    # sits straight on the chest and the whole figure reads as a snowman.
    c.capsule((pose.neck[0], pose.neck[1] + 1.0), (hx, hy + r * 0.7), 1.5 * s, 1.3 * s, skin.dark)

    if kind in ("hood", "shroud", "veil"):
        # Cowl: face is a void with two burning points. Cheapest, strongest
        # gothic read there is.
        cowl = [
            (hx - r - 1.0, hy + r + 1.5),
            (hx - r - 1.0, hy - r * 0.5),
            (hx - r * 0.5, hy - r * 1.9),
            (hx + r * 0.6, hy - r * 1.4),
            (hx + r * 1.0, hy + r * 0.6),
            (hx + r * 0.6, hy + r + 1.5),
        ]
        c.polygon(cowl, spec.cloth.dark)
        c.polygon([(x + 0.6, y + 0.5) for x, y in cowl], spec.cloth.core)
        c.line((hx - r * 0.6, hy - r * 1.7), (hx - r - 0.8, hy - r * 0.2), spec.cloth.light)
        c.ellipse(hx + r * 0.1, hy + r * 0.15, r * 0.72, r * 0.78, P.VOID)
        c.set(round(hx + r * 0.4), round(hy), spec.eye)
        c.set(round(hx - r * 0.25), round(hy), spec.eye)
        return

    if kind == "bat":
        # Ears: big, but sat on the crown and close together. Taller and
        # further back they stopped reading as ears and became a pair of horns
        # floating over the neck.
        for dx, lean_ear, tall in ((0.34, 0.12, 1.0), (-0.34, -0.14, 0.86)):
            bx = hx + r * dx
            by = hy - r * 0.72
            tip = (bx + r * lean_ear, by - r * 1.95 * tall)
            c.polygon([
                (bx - r * 0.48, by + r * 0.2),
                (bx + r * 0.48, by + r * 0.1),
                tip,
            ], skin.dark)
            c.polygon([
                (bx - r * 0.2, by + r * 0.02),
                (bx + r * 0.24, by - r * 0.04),
                (lerp(tip[0], bx, 0.28), lerp(tip[1], by, 0.28)),
            ], shade(skin.core, 0.14))

        c.ellipse(hx, hy, r * 1.05, r * 1.0, skin.dark)
        c.ellipse(hx - 0.6, hy - 0.7, r * 0.8, r * 0.7, skin.core)

        # Snub muzzle with a nose leaf.
        c.ellipse(hx + r * 0.95, hy + r * 0.45, r * 0.72, r * 0.5, skin.dark)
        c.ellipse(hx + r * 0.9, hy + r * 0.3, r * 0.42, r * 0.28, skin.core)
        c.vline(round(hx + r * 1.15), round(hy + r * 0.05), round(hy + r * 0.45), P.VOID)

        gape = pose.mouth_open
        if gape > 0.05:
            # A wedge hinged at the cheek, dropping away from the muzzle. The
            # throat behind it is what sells the volume.
            jaw = r * (0.55 + 1.15 * gape)
            hinge = (hx + r * 0.35, hy + r * 0.55)
            c.polygon([
                hinge,
                (hx + r * 1.5, hy + r * 0.5),
                (hx + r * 1.1, hinge[1] + jaw),
                (hx + r * 0.2, hinge[1] + jaw * 0.72),
            ], P.VOID)
            c.polygon([
                (hinge[0] + r * 0.2, hinge[1] + jaw * 0.22),
                (hx + r * 1.15, hinge[1] + jaw * 0.28),
                (hx + r * 0.85, hinge[1] + jaw * 0.6),
                (hx + r * 0.35, hinge[1] + jaw * 0.52),
            ], shade(P.CRIMSON, -0.55))
            # Upper fangs down from the lip, lower fangs up from the jaw.
            for k in range(2):
                tx = round(hx + r * (0.55 + k * 0.55))
                c.vline(tx, round(hinge[1]), round(hinge[1] + r * 0.42), P.BONE)
                c.vline(tx - 1, round(hinge[1] + jaw * 0.78), round(hinge[1] + jaw * 0.78 + r * 0.34), P.BONE)
        else:
            for k in range(2):
                tx = round(hx + r * (0.75 + k * 0.5))
                ty = round(hy + r * 0.8)
                c.vline(tx, ty, ty + 1, P.BONE)

        # Two lamps, small and clearly apart. At the old size they merged into
        # one red bar across the face.
        c.line((hx - r * 0.2, hy - r * 0.34), (hx + r * 1.0, hy - r * 0.22),
               shade(skin.dark, -0.45))
        for ex in (r * 0.86, r * 0.24):
            c.ellipse(hx + ex, hy, r * 0.22, r * 0.24, shade(spec.eye, -0.6))
            c.set(round(hx + ex), round(hy), spec.eye)
            c.blend(round(hx + ex), round(hy - 1), with_alpha(spec.eye, 130))
        return

    if kind == "wolf":
        ruff = shade(skin.dark, -0.22)
        # Collar of fur first, so the skull sits inside it.
        for k in range(7):
            a = math.radians(-152 + k * 34)
            c.capsule(
                (hx - r * 0.4, hy + r * 0.5),
                (hx - r * 0.4 + math.cos(a) * r * 2.4, hy + r * 0.5 + math.sin(a) * r * 2.4),
                1.8 * s, 0.5, ruff,
            )

        # Ears: swept back, unequal height so the head reads three-quarter.
        for dx, tall in ((0.2, 1.0), (-0.5, 0.82)):
            bx = hx + r * dx
            by = hy - r * 0.7
            c.polygon(
                [
                    (bx - r * 0.5, by + r * 0.25),
                    (bx + r * 0.45, by + r * 0.1),
                    (bx - r * 0.3, by - r * 1.55 * tall),
                ],
                skin.dark,
            )
            c.set(round(bx - r * 0.1), round(by - r * 0.45 * tall), P.VOID)

        # Cranium.
        c.ellipse(hx, hy, r * 1.05, r * 0.95, skin.dark)
        c.ellipse(hx - 0.7, hy - 0.8, r * 0.78, r * 0.64, skin.core)

        # Muzzle: a wedge forward and slightly down. This is the whole animal.
        tip_x = hx + r * 2.5
        tip_y = hy + r * 0.5
        c.polygon(
            [
                (hx + r * 0.1, hy - r * 0.45),
                (tip_x, tip_y - r * 0.4),
                (tip_x, tip_y + r * 0.3),
                (hx + r * 0.1, hy + r * 1.0),
            ],
            skin.dark,
        )
        c.polygon(
            [
                (hx + r * 0.3, hy - r * 0.15),
                (tip_x - r * 0.3, tip_y - r * 0.25),
                (tip_x - r * 0.3, tip_y + r * 0.02),
                (hx + r * 0.3, hy + r * 0.5),
            ],
            skin.core,
        )
        c.set(round(tip_x - 1), round(tip_y - r * 0.15), P.VOID)

        # Bared teeth along the jaw line — cheap, and it does all the menace.
        for k in range(2):
            tx = round(tip_x - r * 0.55 - k * r * 0.7)
            ty = round(hy + r * 0.62 + k * 0.2)
            c.vline(tx, ty, ty + 1, P.BONE)

        # Brow ridge, then two lamps under it.
        c.line((hx - r * 0.35, hy - r * 0.4), (hx + r * 0.95, hy - r * 0.2),
               shade(skin.dark, -0.5))
        for ex, ey in ((r * 0.8, r * 0.02), (r * 0.15, r * 0.08)):
            c.set(round(hx + ex), round(hy + ey), spec.eye)
            c.blend(round(hx + ex), round(hy + ey - 1), with_alpha(spec.eye, 100))
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
        # Nasal bar, crown to jaw. Any higher and the highlight reads as a
        # spike growing out of the helmet.
        c.vline(round(hx + r * 0.15), round(hy - r * 1.0), round(hy + r * 0.8), spec.armor.hi)
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
    elif kind == "jester":
        # Belled cap: a dome and three drooping lobes, one forward, one back,
        # one standing up. Nothing else in the cast has anything above the
        # skull that hangs, so the silhouette reads as the Jester long before
        # the motley colours do.
        c.ellipse(hx, hy - r * 0.35, r * 0.95, r * 0.8, spec.cloth.dark)
        c.ellipse(hx - 0.5, hy - r * 0.55, r * 0.7, r * 0.5, spec.cloth.core)
        # Each lobe leaves the skull, rises, then falls away from it. Drawn as
        # two capsules rather than one so the horn actually droops instead of
        # sticking out like a spike.
        for mid, tip in (
            ((hx + r * 1.6, hy - r * 1.5), (hx + r * 2.5, hy + r * 0.3)),
            ((hx - r * 1.7, hy - r * 1.5), (hx - r * 2.6, hy + r * 0.2)),
            ((hx - r * 0.2, hy - r * 2.2), (hx - r * 1.0, hy - r * 3.0)),
        ):
            c.capsule((hx, hy - r * 0.8), mid, r * 0.34, r * 0.2, spec.cloth.core)
            c.capsule(mid, tip, r * 0.2, r * 0.1, spec.cloth.dark)
            # The bell on the end: a bright core with a dim pixel under it. Two
            # pixels, and they catch the eye every time he moves.
            c.set(round(tip[0]), round(tip[1]), spec.accent.core)
            c.set(round(tip[0]), round(tip[1]) + 1, spec.accent.dark)
        c.hline(round(hx - r * 0.95), round(hx + r * 0.95), round(hy + r * 0.15), spec.accent.dark)
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


def _draw_amulet(c: Canvas, pose: Pose, spec: BodySpec, s: float) -> None:
    """A small bone skull slung at the throat, on a thin chain."""
    if not spec.amulet:
        return

    hang = (pose.neck[0] + 1.2 * s, pose.neck[1] + 3.4 * s)
    chain = spec.accent.core if spec.accent is not None else P.R_GOLD.core
    c.line((pose.neck[0] - 2.4 * s, pose.neck[1] + 0.5), (hang[0], hang[1] - 1.4 * s), chain)
    c.line((pose.neck[0] + 3.0 * s, pose.neck[1] + 0.5), (hang[0], hang[1] - 1.4 * s), chain)

    r = 1.9 * s
    c.ellipse(hang[0], hang[1], r, r * 0.95, P.R_BONE.dark)
    c.ellipse(hang[0] - 0.4, hang[1] - 0.4, r * 0.72, r * 0.66, P.R_BONE.core)
    c.set(round(hang[0] - r * 0.42), round(hang[1] - r * 0.1), P.VOID)
    c.set(round(hang[0] + r * 0.42), round(hang[1] - r * 0.1), P.VOID)
    c.hline(round(hang[0] - r * 0.4), round(hang[0] + r * 0.4), round(hang[1] + r * 0.6), P.VOID)


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

    # Contact shadow first, on the ground plane rather than under the hips, and
    # tied to how high the hips actually are. A shadow that tightens on the
    # bounce is what sells weight; a fixed ellipse makes any bob read as the
    # sprite sliding up and down a wall.
    lift = (pose.ground_y - pose.hip[1]) - 18.0 * s
    shadow_scale = max(0.55, min(1.15, 1.0 - lift * 0.09))
    if pose.airborne:
        shadow_scale *= 0.7
    layer.ellipse(pose.hip[0], pose.ground_y + 1, 7.0 * s * shadow_scale,
                  2.4 * s * shadow_scale, (0, 0, 0, 90))

    # Far wing under everything, near wing over the body: one behind and one
    # in front is what gives a flat side-view bat any depth at all.
    if spec.wingspan > 0.0:
        _draw_bat_wing(layer, pose, spec, s, near=False)

    _draw_cape(layer, pose, spec, s)

    # Four separate tones, and the reason is legibility rather than realism.
    # Everything used to be drawn in spec.cloth, so the legs, the sleeves and
    # the coat were one undifferentiated blob — which meant every pose change
    # in the rig was invisible and the whole cast read as a shuffling mass.
    # Depth now maps to value: far limbs darkest, trousers below the coat,
    # near sleeve lifted off it.
    back = spec.cloth.tinted(P.VOID, 0.42)
    trouser = spec.cloth.tinted(P.VOID, 0.26)
    # 0.62 put the far leg within a couple of values of the robe it stands
    # behind, so for half of every stride the only leg reaching was invisible
    # and the run looked like a limp. Still clearly the darker of the two.
    back_trouser = spec.cloth.tinted(P.VOID, 0.48)
    # 0.16 left the near sleeve within a couple of values of the coat behind
    # it. In a side view that limb lies over the torso for its whole length,
    # so it needs to be visibly lighter as well as outlined.
    sleeve = spec.cloth.tinted(P.SMOKE, 0.22)

    _draw_leg(layer, spec, s, pose.hip_b, pose.knee_b, pose.ankle_b, pose.foot_b,
              back_trouser, back, 2.5 * s * spec.build, 2.1 * s, 1.7 * s)
    _limb(layer, pose.shoulder_b, pose.elbow_b, 1.9 * s * spec.build, 1.6 * s, back)
    _limb(layer, pose.elbow_b, pose.hand_b, 1.6 * s, 1.35 * s, back)
    if spec.claws:
        layer.circle(pose.hand_b[0], pose.hand_b[1], 1.5 * s, back.dark)
        _draw_claws(layer, pose.elbow_b, pose.hand_b, s, shade(P.R_BONE.dark, -0.3))

    _draw_torso(layer, pose, spec, s)

    _draw_leg(layer, spec, s, pose.hip_f, pose.knee_f, pose.ankle_f, pose.foot_f,
              trouser, trouser if spec.digitigrade else P.R_LEATHER,
              2.7 * s * spec.build, 2.2 * s, 1.8 * s)

    # Over the near thigh, which is what a surcoat does.
    _draw_tabard(layer, pose, spec, s)
    # Then the shield over that, but still under the near arm — which is what
    # keeps it reading as carried on the far side rather than pinned to the
    # chest. Drawn behind the torso it disappeared completely once the
    # shoulders moved out to the edge of the body.
    _draw_shield(layer, pose, spec, s)

    if spec.tail:
        tail_a = (pose.hip[0] - 3.0 * s, pose.hip[1])
        tail_b = (tail_a[0] - 9.0 * s, tail_a[1] + 3.0 * s + pose.cape_sway)
        if spec.fur > 0.0:
            # A brush, not a rope: two overlapping capsules plus a fanned tip.
            mid = (tail_a[0] - 5.0 * s, tail_a[1] - 1.0 * s + pose.cape_sway * 0.4)
            tip = (tail_a[0] - 11.0 * s, tail_a[1] + 2.0 * s + pose.cape_sway)
            layer.capsule(tail_a, mid, 2.6 * s, 2.4 * s, shade(spec.cloth.dark, -0.2))
            layer.capsule(mid, tip, 2.4 * s, 1.0 * s, shade(spec.cloth.dark, -0.2))
            for k in range(3):
                layer.capsule(mid, (tip[0] - 1.0 * s, tip[1] - 2.5 * s + k * 2.4 * s),
                              1.4 * s, 0.5, shade(spec.cloth.dark, -0.35))
        else:
            layer.capsule(tail_a, tail_b, 1.8 * s, 0.5, spec.skin.dark)

    _fur_fringe(layer, pose, spec, s)

    if spec.wingspan > 0.0:
        _draw_bat_wing(layer, pose, spec, s, near=True)

    _draw_head(layer, pose, spec, s)
    _draw_amulet(layer, pose, spec, s)

    # Sleeve down to the wrist, then a small gloved hand. A full forearm in
    # skin tone reads as a pale smear across a dark torso.
    #
    # The near arm is laid over the torso, so it is drawn on a hard edge of its
    # own first. Without it the sleeve dissolved into the coat and the only
    # part of the limb anyone could see was the hand, apparently floating
    # unattached at hip height.
    # An arm is about a third of the torso's width, not two thirds: at the old
    # radii the near sleeve was almost as wide as the chest it hung over.
    edge = spec.cloth.outline
    up_r, fore_r, wrist_r = 1.7 * s * spec.build, 1.45 * s, 1.2 * s
    hand_r = 1.3 * s
    layer.capsule(pose.shoulder_f, pose.elbow_f, up_r + 0.6, fore_r + 0.6, edge)
    layer.capsule(pose.elbow_f, pose.hand_f, fore_r + 0.6, wrist_r + 0.6, edge)
    layer.circle(pose.hand_f[0], pose.hand_f[1], hand_r + 0.6, edge)
    _limb(layer, pose.shoulder_f, pose.elbow_f, up_r, fore_r, sleeve)
    _limb(layer, pose.elbow_f, pose.hand_f, fore_r, wrist_r, sleeve)
    layer.circle(pose.hand_f[0], pose.hand_f[1], hand_r, spec.skin.dark)
    layer.circle(pose.hand_f[0] - 0.4, pose.hand_f[1] - 0.5, 0.8 * s, spec.skin.core)
    if spec.claws:
        _draw_claws(layer, pose.elbow_f, pose.hand_f, s, P.R_BONE.dark)

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
    # Gentle: at full strength this drew a bright thread down the back edge of
    # every coat, which reads as a stray hair rather than as moonlight.
    layer.rim_light(P.MOONLIGHT, -1, -1, 62)

    if flash > 0.0:
        layer.flash((255, 255, 255, 255), flash)
    if pose.alpha < 1.0:
        layer.fade(pose.alpha)

    canvas.paste(layer, 0, 0)

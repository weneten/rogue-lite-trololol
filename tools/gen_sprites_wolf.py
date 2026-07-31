"""
Nightbane - Blutwolf: Pixel-Art Sprite-Generator (gleicher Stil wie der Jaeger).

Erzeugt aus dem Blutwolf-Konzept-Art einen spielbaren 2D-Charakter als
Sprite-Sheet (64x64 pro Frame, Blickrichtung rechts, horizontal spiegeln
fuer links). Nutzt dieselben Pixel-Primitive wie tools/gen_sprites.py
(Rim-Light + Outline-Postprocessing), aber einen eigenen, wuchtigeren
Koerperbau und eigene Animationen.

Ausgabe:  assets/sprites/blutwolf/blutwolf.png
          assets/sprites/blutwolf/blutwolf.json
          assets/sprites/blutwolf/strips/<anim>.png
          assets/sprites/blutwolf/preview.html

Aufruf:   python tools/gen_sprites_wolf.py
"""

import json
import math
import os

from PIL import Image

import gen_sprites as gs   # gemeinsame Pixel-Primitive + Preview-Template

new_layer, pset, thick_line = gs.new_layer, gs.pset, gs.thick_line
poly, rect, disc, ring = gs.poly, gs.rect, gs.disc, gs.ring
bezier, arc_pts = gs.bezier, gs.arc_pts
rim_light, outline_layer, tint = gs.rim_light, gs.outline_layer, gs.tint

W, H, CX, GY, OUT = gs.W, gs.H, gs.CX, gs.GY, gs.OUT

# --------------------------------------------------------------------------
# Palette (aus dem Konzept-Art: verfluchtes Fell, Rost, Blutmond, Knochen)
# --------------------------------------------------------------------------
FUR_D  = (18, 17, 20, 255)      # Fell dunkel (Schatten)
FUR_M  = (34, 33, 38, 255)      # Fell mittel
FUR_L  = (54, 53, 60, 255)      # Fell Kante / Grannenhaare
SCAR   = (58, 50, 52, 255)      # vernarbte Haut zwischen dem Fell
ARM_D  = (36, 30, 24, 255)      # zerrissene Ruestung dunkel
ARM_M  = (60, 48, 36, 255)      # zerrissene Ruestung mittel
RST_D  = (52, 40, 30, 255)      # verwittertes Metall / Dornen dunkel
RST_M  = (92, 68, 44, 255)      # verwittertes Metall / Dornen mittel
RST_L  = (132, 100, 60, 255)    # Metallkante
CLAW_D = (150, 146, 138, 255)   # Kralle dunkel
CLAW_L = (216, 210, 196, 255)   # Kralle hell / Spitze
RED_D, RED_M, RED_L = gs.RED_D, gs.RED_M, gs.RED_L
BONE = gs.BONE

OUTDIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "assets", "sprites", "blutwolf")

FUR_TEETH = [0, 2, 4, 1, 3, 0, 2, 4, 1, 3, 0, 2]


def tattered_hem(x0, x1, y, teeth, step=2):
    pts = []
    n = max(2, int((x1 - x0) // step))
    for i in range(n + 1):
        x = x1 - (x1 - x0) * i / n
        pts.append((x, y + teeth[i % len(teeth)]))
    return pts


# --------------------------------------------------------------------------
# Pose - digitigrade Beine, lange Arme, gebeugter Ruecken
# --------------------------------------------------------------------------
def pose(**kw):
    p = dict(
        dy=0, lean=2, crouch=0,
        hip_y=38,
        # Bein: Hueft -> Knie (nach vorn geknickt) -> Sprunggelenk -> Pfote
        knee_b=(-6, 6), ankle_b=(-3, 14), foot_b=(-8, 20),
        knee_f=(6, 6), ankle_f=(9, 14), foot_f=(4, 20),
        arm_b=((-10, 2), (-16, 8)),
        arm_f=((10, 0), (17, 4)),
        sway=0, chest_flare=0,
        head_dx=5, head_dy=-8, head_tilt=0, jaw=0,
        ear_b=0,
        eye=1.0, aura=0.0,
    )
    p.update(kw)
    return p


# --------------------------------------------------------------------------
# Koerperteile
# --------------------------------------------------------------------------
def draw_leg(layer, hip, knee, ankle, foot, back):
    col = FUR_D if back else FUR_M
    thick_line(layer, hip, knee, col, 4)
    thick_line(layer, knee, ankle, col, 3)
    thick_line(layer, ankle, foot, FUR_D if back else FUR_M, 2)
    # Pfote mit Krallen
    fx, fy = foot
    d = 1 if fx >= ankle[0] else -1
    for i, o in enumerate((-2, 0, 2)):
        cx, cy = fx + o, fy
        thick_line(layer, (cx, cy - 1), (cx + d * 3, cy + 1), CLAW_D, 1)
        pset(layer.load(), cx + d * 3, cy + 1, CLAW_L)


def draw_tail(layer, hip, sway):
    base = (hip[0] - 6, hip[1] - 2)
    tip = (base[0] - 10 - sway, base[1] + 8 - sway * 0.4)
    mid = (base[0] - 6 - sway * 0.6, base[1] + 2)
    pts = bezier(base, mid, tip, 6)
    for i, (x, y) in enumerate(pts):
        w = 3 if i < 3 else 2
        thick_line(layer, (x, y), (x, y), FUR_D, w)
    pset(layer.load(), *[int(v) for v in tip], FUR_L)


def draw_torso(layer, p, sh_y, hip_y):
    lean = p["lean"]
    flare = p["chest_flare"]
    # breiter, nach vorn gebeugter Brustkorb
    poly(layer, [(CX - 10 + lean, sh_y - 2), (CX + 9 + flare + lean, sh_y),
                 (CX + 8 + flare, hip_y), (CX - 8, hip_y + 1)], FUR_M)
    poly(layer, [(CX - 10 + lean, sh_y - 2), (CX - 3 + lean, sh_y - 1),
                 (CX - 4, hip_y), (CX - 8, hip_y + 1)], FUR_D)
    # vernarbte Brust (Detail: Narben & Verfluchung)
    thick_line(layer, (CX - 2 + lean, sh_y + 2), (CX + 3, hip_y - 6), SCAR, 1)
    thick_line(layer, (CX + 1 + lean, sh_y + 1), (CX + 5, hip_y - 8), SCAR, 1)
    # zerrissene Ruestungsplatten mit Dornen (Details: zerrissene Ruestung)
    rect(layer, CX - 6, hip_y - 9, CX + 7 + flare, hip_y - 5, ARM_M)
    rect(layer, CX - 6, hip_y - 9, CX + 7 + flare, hip_y - 8, ARM_D)
    for dx in (-4, 0, 4, 8):
        x = CX + dx + flare * 0.3
        thick_line(layer, (x, hip_y - 9), (x, hip_y - 12), RST_M, 1)
        pset(layer.load(), int(x), hip_y - 12, RST_L)
    # Wolfsamulett auf der Brust (Detail: Wolfsamulett) - klein und dezent
    ax, ay = CX - 1 + lean, sh_y + 5
    ring(layer, ax, ay, 2, RST_L, 1)
    pset(layer.load(), ax, ay, RST_D)
    # Guertel + kurze haengende Kette mit Schaedel-Anhaenger
    rect(layer, CX - 8, hip_y - 1, CX + 8, hip_y + 1, ARM_D)
    chain_pts = bezier((CX - 5, hip_y + 1), (CX - 7, hip_y + 4), (CX - 5, hip_y + 7), 5)
    for i, (x, y) in enumerate(chain_pts):
        pset(layer.load(), x, y, RST_M if i % 2 else RST_D)
    disc(layer, CX - 5, hip_y + 8, 1, BONE)


def draw_arm(layer, sh, elbow, hand, back, claw_spread=1.0):
    col = FUR_D if back else FUR_M
    thick_line(layer, sh, elbow, col, 4)
    thick_line(layer, elbow, hand, col, 3)
    # Schulterdornen
    thick_line(layer, (sh[0], sh[1] - 1), (sh[0] - 1, sh[1] - 4), RST_M, 1)
    # Klauenhand - drei Krallen die vom Handgelenk auffaechern
    hx, hy = hand
    ang = math.degrees(math.atan2(hand[1] - elbow[1], hand[0] - elbow[0]))
    for i, off in enumerate((-22, 0, 22)):
        a = math.radians(ang + off * claw_spread)
        tx = hx + math.cos(a) * 6
        ty = hy + math.sin(a) * 6
        thick_line(layer, (hx, hy), (tx, ty), CLAW_D, 1)
        pset(layer.load(), int(tx), int(ty), CLAW_L)


def draw_head(layer, p, sh_y):
    hx = CX + p["head_dx"]
    hy = sh_y + p["head_dy"]
    tilt = p["head_tilt"]
    # Nacken - verbindet Kopf und Schultern, damit nichts frei schwebt
    poly(layer, [(CX - 3 + p["lean"], sh_y - 1), (hx - 4, hy + 4),
                 (hx + 1, hy + 5), (CX + 4 + p["lean"], sh_y - 1)], FUR_D)
    # Schaedel + Schnauze (nach vorn gebeugt)
    poly(layer, [(hx - 5, hy - 3 + tilt), (hx + 2, hy - 5 + tilt), (hx + 8, hy - 2),
                 (hx + 10 + p["jaw"], hy + 2), (hx + 4, hy + 4), (hx - 5, hy + 3)], FUR_M)
    # Unterkiefer / Maul
    poly(layer, [(hx + 3, hy + 1), (hx + 10 + p["jaw"], hy + 2),
                 (hx + 8 + p["jaw"] * 0.6, hy + 5 + p["jaw"]), (hx + 3, hy + 4)], FUR_D)
    if p["jaw"] > 1:
        pset(layer.load(), hx + 6, hy + 3, CLAW_L)   # Reisszahn blitzt auf
    # Ohren
    eb = p["ear_b"]
    poly(layer, [(hx - 4, hy - 3 + tilt), (hx - 6, hy - 9 + eb), (hx - 1, hy - 4)], FUR_D)
    poly(layer, [(hx + 1, hy - 5 + tilt), (hx + 2, hy - 10 + eb), (hx + 5, hy - 4)], FUR_D)
    # Nackenmaehne
    poly(layer, [(hx - 6, hy - 2), (hx - 9, hy + 4), (hx - 4, hy + 6),
                 (hx - 4, hy - 1)], FUR_D)
    for fx, fy in ((hx - 8, hy + 1), (hx - 7, hy + 4), (hx - 5, hy - 2)):
        pset(layer.load(), fx, fy, FUR_L)
    # Glut-Augen - wichtigster Lesepunkt
    if p["eye"] > 0:
        px = layer.load()
        ec = RED_L if p["eye"] >= 1 else RED_M
        pset(px, hx - 1, hy - 2 + tilt, ec)
        pset(px, hx + 2, hy - 3 + tilt, ec)


def draw_wolf(p):
    back = new_layer()
    body = new_layer()
    front = new_layer()

    dy = p["dy"] + p["crouch"]
    hip_y = p["hip_y"] + dy
    sh_y = hip_y - 16 + p["crouch"] * 0.3
    hip = (CX, hip_y)
    sh_b = (CX - 8 + p["lean"], sh_y + 3)
    sh_f = (CX + 7 + p["lean"], sh_y + 1)

    knee_b = (CX + p["knee_b"][0], hip_y + p["knee_b"][1])
    ankle_b = (CX + p["ankle_b"][0], hip_y + p["ankle_b"][1])
    foot_b = (CX + p["foot_b"][0], hip_y + p["foot_b"][1])
    knee_f = (CX + p["knee_f"][0], hip_y + p["knee_f"][1])
    ankle_f = (CX + p["ankle_f"][0], hip_y + p["ankle_f"][1])
    foot_f = (CX + p["foot_f"][0], hip_y + p["foot_f"][1])

    el_b = (sh_b[0] + p["arm_b"][0][0], sh_b[1] + p["arm_b"][0][1])
    hd_b = (sh_b[0] + p["arm_b"][1][0], sh_b[1] + p["arm_b"][1][1])
    el_f = (sh_f[0] + p["arm_f"][0][0], sh_f[1] + p["arm_f"][0][1])
    hd_f = (sh_f[0] + p["arm_f"][1][0], sh_f[1] + p["arm_f"][1][1])

    draw_tail(back, hip, p["sway"])
    draw_leg(back, hip, knee_b, ankle_b, foot_b, True)
    draw_arm(back, sh_b, el_b, hd_b, True)

    draw_leg(body, hip, knee_f, ankle_f, foot_f, False)
    draw_torso(body, p, sh_y, hip_y)
    draw_head(body, p, sh_y)

    draw_arm(front, sh_f, el_f, hd_f, False)

    body.alpha_composite(front)
    back.alpha_composite(body)
    return back, hd_f, hd_b, hip_y


def compose(p, fx_back=None, fx_front=None, ghosts=()):
    frame = new_layer()
    fig, hd_f, hd_b, hip_y = draw_wolf(p)

    for dx, dy, col, alpha in ghosts:
        g = tint(fig, col, alpha)
        frame.alpha_composite(g.transform((W, H), Image.AFFINE, (1, 0, -dx, 0, 1, -dy)))

    if fx_back:
        frame.alpha_composite(fx_back(p, hd_f, hd_b, hip_y))

    rim_light(fig)
    frame.alpha_composite(outline_layer(fig))

    if fx_front:
        frame.alpha_composite(fx_front(p, hd_f, hd_b, hip_y))
    return frame


# --------------------------------------------------------------------------
# Effekte
# --------------------------------------------------------------------------
def fx_moon_bg(scale, alpha=255):
    def f(p, hd_f, hd_b, hip_y):
        l = new_layer()
        r = 10 * scale
        c = l.load()
        disc(l, CX + 2, 14, r, (52, 8, 12, 255))
        disc(l, CX + 2, 14, max(1, r - 3), (100, 16, 18, 255))
        if alpha < 255:
            l.putalpha(l.getchannel("A").point(lambda v: v * alpha // 255))
        return l
    return f


def fx_ground_pulse(phase):
    def f(p, hd_f, hd_b, hip_y):
        l = new_layer()
        r = 6 + 20 * min(1.0, phase * 1.3)
        col = RED_M if phase < 0.75 else RED_D
        ring(l, CX, GY - 2, r, col, 1, ry=max(2, r * 0.32))
        ring(l, CX, GY - 2, max(2, r - 4), RED_D, 1, ry=max(1, (r - 4) * 0.32))
        for i in range(6):
            a = math.radians(phase * 300 + i * 60)
            pset(l.load(), CX + math.cos(a) * r, GY - 2 + math.sin(a) * r * 0.32, RED_L)
        return l
    return f


def fx_howl(phase):
    """Schockringe breiten sich konzentrisch um die Schnauze aus."""
    def f(p, hd_f, hd_b, hip_y):
        l = new_layer()
        sh_y = hip_y - 16
        cx = CX + p["head_dx"] + 6
        cy = sh_y + p["head_dy"] + 1
        for i, r0 in enumerate((2, 5, 8)):
            r = r0 + phase * 7
            ring(l, cx, cy, r, RED_M if i else RED_L, 1, ry=max(1, r * 0.8))
        return l
    return f


def fx_whirl_claws(phase):
    def f(p, hd_f, hd_b, hip_y):
        l = new_layer()
        cy = hip_y - 6
        r = 14 + 4 * math.sin(phase * math.pi)
        for k in range(2):
            a0 = phase * 720 + k * 180
            trail = arc_pts(CX, cy, r, a0 - 60, a0, 9, 0.75)
            for i, (x, y) in enumerate(trail):
                pset(l.load(), x, y, CLAW_L if i > 5 else CLAW_D)
        return l
    return f


def fx_rage_aura(phase):
    def f(p, hd_f, hd_b, hip_y):
        l = new_layer()
        px = l.load()
        for i in range(int(6 + phase * 6)):
            a = math.radians(i * 47 + phase * 60)
            r = 12 + (i % 3) * 4
            x = CX + math.cos(a) * r
            y = hip_y - 8 + math.sin(a) * r * 0.9
            pset(px, x, y, RED_M if i % 2 else RED_D)
        return l
    return f


# --------------------------------------------------------------------------
# Animationen
# --------------------------------------------------------------------------
def anim_idle():
    frames = []
    for b in (0, -1, 0, 1):
        p = pose(dy=b, lean=2, jaw=0, ear_b=b, eye=1.0 if b != 1 else 0.7)
        frames.append(compose(p))
    return frames, 6, True


def anim_run():
    frames = []
    cyc = [
        (0, (10, 20, 6), (-9, 22, -6)), (-2, (6, 16, 2), (-4, 22, -2)),
        (0, (0, 22, -2), (2, 20, 2)), (0, (-6, 22, -6), (8, 20, 6)),
        (-2, (-9, 16, -2), (6, 16, 2)), (0, (-9, 21, -6), (10, 20, 6)),
    ]
    for dy, (ffx, ffy, fax), (bfx, bfy, bax) in cyc:
        p = pose(dy=dy, lean=6, crouch=1,
                 foot_f=(ffx, ffy), ankle_f=(fax, 14), knee_f=(fax // 2 + 2, 8),
                 foot_b=(bfx, bfy), ankle_b=(bax, 14), knee_b=(bax // 2 - 2, 8),
                 arm_f=((11, -1), (18, 3)), arm_b=((-9, 3), (-15, 9)),
                 sway=3, head_dy=-7)
        frames.append(compose(p))
    return frames, 12, True


def anim_dash():
    """Bestiensprung: Ducken -> Sprung mit ausgefahrenen Krallen -> Landung."""
    frames = []
    frames.append(compose(pose(dy=5, crouch=3, lean=8, head_dy=-6,
                               knee_f=(4, 4), foot_f=(2, 16), knee_b=(-4, 4),
                               foot_b=(-2, 16), arm_f=((8, -2), (13, 0)))))
    for i, lean in enumerate((10, 12, 9)):
        streaks = [(30 + k * 4, 4 + i, 18 - i * 2, RED_D if k % 2 else FUR_L)
                   for k in range(4)]
        p = pose(dy=0, lean=lean, crouch=-2, head_dy=-8,
                 knee_f=(10, 3), foot_f=(16, 12), knee_b=(-2, 8),
                 foot_b=(-6, 18), arm_f=((14, -4), (21, -8)),
                 arm_b=((-8, 4), (-13, 10)), sway=6)
        ghosts = [(-6 - i * 3, 0, RED_D, 90), (-12 - i * 4, 0, (20, 6, 10), 55)]
        l = new_layer()
        for y, x0, x1, c in streaks:
            thick_line(l, (x0, y), (x1, y), c, 1)
        frames.append(compose(p, fx_back=lambda p, a, b, c, l=l: l, ghosts=ghosts))
    frames.append(compose(pose(dy=3, lean=5, crouch=1, head_dy=-6,
                               knee_f=(6, 6), foot_f=(6, 20), knee_b=(-6, 6),
                               foot_b=(-8, 20), arm_f=((10, 2), (16, 6))),
                          ghosts=[(-6, 0, RED_D, 45)]))
    return frames, 16, False


def anim_attack_slash():
    """Klauen-Schlag: Ausholen -> zwei Krallenhiebe."""
    frames = []
    frames.append(compose(pose(lean=-2, arm_f=((-4, -12), (-9, -17)), head_dy=-9)))
    for i, ang in enumerate((-40, 10, 60)):
        p = pose(lean=6 + i, arm_f=((14, -2 + i * 4), (22, 4 + i * 6)),
                 arm_b=((-8, 2), (-13, 8)), head_dy=-7, jaw=2)
        l = new_layer()
        hx, hy = CX + 22 + p["lean"], p["hip_y"] + p["dy"] + 4 + i * 6
        for k in range(3):
            trail = arc_pts(hx - 12, hy - 4, 13 + k * 3, ang - 55, ang, 7, 0.8)
            for x, y in trail:
                thick_line(l, (x, y), (x, y), CLAW_L if k == 2 else CLAW_D, 1)
        frames.append(compose(p, fx_front=lambda p, a, b, c, l=l: l))
    frames.append(compose(pose(lean=3, arm_f=((10, 4), (16, 8)))))
    return frames, 14, False


def anim_attack_spin():
    """Wirbelnde Klingen: Flaechenangriff, Koerper dreht sich um die eigene Achse."""
    frames = []
    for i, ph in enumerate((0.05, 0.25, 0.5, 0.75, 1.0)):
        p = pose(dy=-1 if i in (1, 2, 3) else 0, lean=0, crouch=1,
                 arm_f=((13, -2), (20, 2)), arm_b=((-13, -2), (-20, 2)),
                 head_dy=-8, jaw=2, eye=1.0)
        frames.append(compose(p, fx_front=fx_whirl_claws(ph)))
    return frames, 14, False


def anim_rage():
    """Raserei: Buff-Pose, Aura verdichtet sich."""
    frames = []
    for i, ph in enumerate((0.1, 0.4, 0.7, 1.0)):
        p = pose(dy=-1 if i > 1 else 0, lean=3 + i, chest_flare=i,
                 arm_f=((9, -4 - i), (14, -8 - i * 2)),
                 arm_b=((-9, -2), (-14, -4)), head_dy=-9 - i, jaw=i, eye=1.0)
        frames.append(compose(p, fx_back=fx_rage_aura(ph)))
    return frames, 10, False


def anim_howl():
    """Blutmond Heulen: Kopf in den Nacken, Schockwelle laeuft nach aussen."""
    frames = []
    for i, ph in enumerate((0.0, 0.3, 0.6, 1.0)):
        p = pose(dy=1 if i == 0 else 0, lean=-2, head_dy=-10 - i * 2,
                 head_tilt=-2 - i, jaw=3 if i > 0 else 0,
                 arm_f=((6, 4), (9, 8)), arm_b=((-6, 4), (-9, 8)), eye=1.0)
        frames.append(compose(p, fx_back=fx_moon_bg(0.6 + ph * 0.3),
                              fx_front=fx_howl(ph)))
    return frames, 8, False


def anim_hurt():
    frames = []
    for lean, dy in ((-6, 2), (-3, 0)):
        p = pose(dy=dy, lean=lean, head_dy=-6, jaw=0,
                 arm_f=((4, 2), (5, -2)), eye=1.0)
        f = compose(p)
        fl = new_layer()
        for x, y in ((26, 24), (34, 22), (30, 30), (37, 28)):
            pset(fl.load(), x, y, RED_L)
        f.alpha_composite(fl)
        frames.append(f)
    return frames, 10, False


def anim_death():
    frames = []
    specs = [(2, -2, 0.7, 255), (7, 0, 0.4, 255), (13, 2, 0.15, 230), (18, 4, 0.0, 180)]
    for i, (dy, lean, eye, alpha) in enumerate(specs):
        p = pose(dy=dy, lean=lean, crouch=i, head_dy=-6 + i * 2, head_tilt=i,
                 knee_f=(6, 4), foot_f=(6, 18 - dy), knee_b=(-6, 4),
                 foot_b=(-6, 18 - dy), arm_f=((8, 6), (12, 10 - i)),
                 arm_b=((-8, 6), (-12, 10 - i)), eye=eye)
        f = compose(p)
        if alpha < 255:
            f.putalpha(f.getchannel("A").point(lambda v: v * alpha // 255))
        frames.append(f)
    return frames, 8, False


def anim_ultimate():
    """Vollmond: volle Verwandlung, Blutmond waechst hinter dem Wolf."""
    frames = []
    for i, ph in enumerate((0.1, 0.3, 0.5, 0.7, 0.85, 1.0)):
        p = pose(dy=-1 if i > 2 else 0, lean=2 + int(2 * ph), chest_flare=int(3 * ph),
                 arm_f=((9 + int(4 * ph), -4 - int(6 * ph)),
                        (14 + int(6 * ph), -9 - int(9 * ph))),
                 arm_b=((-9, 0), (-14, 2)), head_dy=-9 - int(3 * ph),
                 jaw=int(3 * ph), eye=1.0)
        frames.append(compose(p, fx_back=fx_moon_bg(0.8 + ph * 1.1),
                              fx_front=fx_ground_pulse(ph)))
    return frames, 10, False


ANIMS = [
    ("idle", anim_idle),
    ("run", anim_run),
    ("dash", anim_dash),
    ("attack_slash", anim_attack_slash),
    ("attack_spin", anim_attack_spin),
    ("rage", anim_rage),
    ("howl", anim_howl),
    ("hurt", anim_hurt),
    ("death", anim_death),
    ("ultimate", anim_ultimate),
]


def main():
    os.makedirs(os.path.join(OUTDIR, "strips"), exist_ok=True)
    built = [(name, *fn()) for name, fn in ANIMS]
    cols = max(len(f) for _, f, _, _ in built)
    rows = len(built)

    sheet = Image.new("RGBA", (cols * W, rows * H), (0, 0, 0, 0))
    meta = {"image": "blutwolf.png", "frameWidth": W, "frameHeight": H,
            "columns": cols, "rows": rows, "facing": "right",
            "origin": {"x": CX, "y": GY}, "animations": {}}

    for r, (name, frames, fps, loop) in enumerate(built):
        strip = Image.new("RGBA", (len(frames) * W, H), (0, 0, 0, 0))
        for c, f in enumerate(frames):
            sheet.alpha_composite(f, (c * W, r * H))
            strip.alpha_composite(f, (c * W, 0))
        strip.save(os.path.join(OUTDIR, "strips", f"{name}.png"))
        meta["animations"][name] = {
            "row": r, "from": r * cols, "to": r * cols + len(frames) - 1,
            "frames": [r * cols + i for i in range(len(frames))],
            "frameCount": len(frames), "fps": fps, "loop": loop,
        }

    sheet.save(os.path.join(OUTDIR, "blutwolf.png"))
    Image.open(os.path.join(OUTDIR, "blutwolf.png")).resize(
        (sheet.width * 4, sheet.height * 4), Image.NEAREST).save(
        os.path.join(OUTDIR, "blutwolf@4x.png"))
    with open(os.path.join(OUTDIR, "blutwolf.json"), "w") as fh:
        json.dump(meta, fh, indent=2)

    import base64
    with open(os.path.join(OUTDIR, "blutwolf.png"), "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()
    html = (gs.PREVIEW.replace("Nightbane - Sprite Preview", "Blutwolf - Sprite Preview")
                       .replace("Nightbane &mdash; Jaeger", "Nightbane &mdash; Blutwolf")
                       .replace("__B64__", b64).replace("__META__", json.dumps(meta)))
    with open(os.path.join(OUTDIR, "preview.html"), "w", encoding="utf-8") as fh:
        fh.write(html)

    print(f"sheet {sheet.width}x{sheet.height}  ({rows} Animationen, {cols} Spalten)")
    for name, frames, fps, loop in built:
        print(f"  {name:<14} {len(frames)} Frames @ {fps} fps  loop={loop}")


if __name__ == "__main__":
    main()

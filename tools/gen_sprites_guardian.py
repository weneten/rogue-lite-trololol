"""
Nightbane - Blutwaechter: Pixel-Art Sprite-Generator (gleicher Stil wie
Jaeger, Blutwolf und Schattenhexerin).

Erzeugt aus dem Blutwaechter-Konzept-Art einen spielbaren 2D-Charakter als
Sprite-Sheet (64x64 pro Frame, Blickrichtung rechts, horizontal spiegeln
fuer links). Nutzt dieselben Pixel-Primitive wie tools/gen_sprites.py
(Rim-Light + Outline-Postprocessing), aber einen eigenen, massiven
Ritter-Koerperbau (Plattenruestung, Kreuz-Wappenrock, Schild, Morgenstern-
Kette, ewige Laterne) und eigene Animationen.

Ausgabe:  assets/sprites/blutwaechter/blutwaechter.png
          assets/sprites/blutwaechter/blutwaechter.json
          assets/sprites/blutwaechter/strips/<anim>.png
          assets/sprites/blutwaechter/preview.html

Aufruf:   python tools/gen_sprites_guardian.py
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
LEA_D, LEA_M, LEA_L = gs.LEA_D, gs.LEA_M, gs.LEA_L

# --------------------------------------------------------------------------
# Palette (aus dem Konzept-Art: beschlagener Stahl, rostige Ketten, Blut,
# heiliges Licht)
# --------------------------------------------------------------------------
STL_D  = (48, 50, 56, 255)      # Stahl dunkel (Schatten)
STL_M  = (92, 96, 106, 255)     # Stahl mittel
STL_L  = (152, 158, 170, 255)   # Stahl Glanzkante
RUST_D = (58, 44, 32, 255)      # rostige Kette dunkel
RUST_M = (100, 74, 48, 255)     # rostige Kette mittel
CLO_D  = (58, 16, 18, 255)      # zerfetzter Wappenrock dunkel
CLO_M  = (98, 24, 26, 255)      # zerfetzter Wappenrock mittel
BLOOD  = (70, 10, 12, 255)      # getrocknetes Blut
GOLD_D = (120, 96, 40, 255)     # heiliges Licht dunkel (Kreuz/Laterne)
GOLD_M = (206, 168, 74, 255)    # heiliges Licht mittel
GOLD_L = (250, 224, 150, 255)   # heiliges Licht hell / Glut
BONE   = gs.BONE

OUTDIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "assets", "sprites", "blutwaechter")

CLOTH_TEETH = [0, 3, 1, 4, 0, 2, 4, 1]


def tattered_hem(x0, x1, y, teeth, step=2):
    pts = []
    n = max(2, int((x1 - x0) // step))
    for i in range(n + 1):
        x = x1 - (x1 - x0) * i / n
        pts.append((x, y + teeth[i % len(teeth)]))
    return pts


# --------------------------------------------------------------------------
# Pose
# --------------------------------------------------------------------------
def pose(**kw):
    p = dict(
        dy=0, lean=1, hip_y=37,
        knee_b=(-4, 8), foot_b=(-7, 22),
        knee_f=(4, 8), foot_f=(7, 22),
        arm_shield=((-6, 3), (-9, 8)),   # Schild-Arm (hinten)
        arm_flail=((6, 2), (10, 9)),     # Waffen-Arm (vorn)
        shield_up=0.0, cloth_sway=0,
        helm_tilt=0, head_dx=1, head_dy=0,
        eye=1.0, cross_glow=0.4,
    )
    p.update(kw)
    return p


# --------------------------------------------------------------------------
# Koerperteile
# --------------------------------------------------------------------------
def draw_leg(layer, hip, knee, foot, back):
    col = STL_D if back else STL_M
    thick_line(layer, hip, knee, col, 4)
    thick_line(layer, knee, foot, col, 3)
    bx, by = foot
    rect(layer, bx - 3, by - 2, bx + 4, by + 2, STL_D if back else (54, 56, 62, 255))
    if not back:
        rect(layer, bx - 2, by - 1, bx + 3, by - 1, STL_L)
    rect(layer, bx - 3, by + 1, bx + 4, by + 2, OUT)
    # Knieschutz
    pset(layer.load(), knee[0], knee[1] - 1, STL_L if not back else STL_D)


def draw_torso(layer, p, sh_y, hip_y):
    lean = p["lean"]
    # Brustpanzer
    poly(layer, [(CX - 7 + lean, sh_y - 1), (CX + 7 + lean, sh_y - 1),
                 (CX + 6, hip_y), (CX - 6, hip_y)], STL_M)
    poly(layer, [(CX - 7 + lean, sh_y - 1), (CX - 1 + lean, sh_y),
                 (CX - 2, hip_y), (CX - 6, hip_y)], STL_D)
    thick_line(layer, (CX + 6 + lean, sh_y), (CX + 5, hip_y - 1), STL_L, 1)
    # Kreuz auf der Brustplatte (Detail: Brustplatte)
    cx, cy = CX + lean, sh_y + 5
    g = p["cross_glow"]
    ccol = GOLD_L if g > 0.7 else (GOLD_M if g > 0.3 else GOLD_D)
    rect(layer, cx, cy - 4, cx, cy + 4, ccol)
    rect(layer, cx - 3, cy - 1, cx + 3, cy - 1, ccol)
    # zerfetzter Wappenrock (Detail: zerfetzter Stoff)
    bot = hip_y + 10
    left, right = CX - 5 - p["cloth_sway"], CX + 5
    pts = [(CX - 4, hip_y), (CX + 4, hip_y)]
    pts += tattered_hem(left, right, bot, CLOTH_TEETH)
    poly(layer, pts, CLO_M)
    poly(layer, [(CX - 4, hip_y), (CX - 1, hip_y), (CX - 2, bot), (left, bot - 2)], CLO_D)
    pset(layer.load(), CX - 3, bot - 4, BLOOD)
    # Guertel + haengende ewige Laterne (Detail: ewige Laterne)
    rect(layer, CX - 6, hip_y - 2, CX + 6, hip_y, RUST_D)
    lx, ly = CX - 7, hip_y + 4
    rect(layer, lx - 1, ly, lx + 1, ly + 3, RUST_M)
    rect(layer, lx - 1, ly + 3, lx + 1, ly + 3, STL_D)
    pset(layer.load(), lx, ly + 1, GOLD_L if p["eye"] > 0.5 else GOLD_M)


def draw_arm(layer, sh, elbow, hand, col_d, col_m):
    thick_line(layer, sh, elbow, col_d, 4)
    thick_line(layer, elbow, hand, col_m, 3)
    # Schulterpanzer (Pauldron) mit Dorn
    disc(layer, sh[0], sh[1], 3, col_m)
    d = 1 if hand[0] >= sh[0] else -1
    thick_line(layer, (sh[0], sh[1] - 3), (sh[0] + d, sh[1] - 6), STL_L, 1)


def draw_head(layer, p, sh_y):
    hx = CX + p["head_dx"] + p["lean"]
    hy = sh_y - 5 + p["head_dy"]
    tilt = p["helm_tilt"]
    # Helm (Detail: Helm des Waechters) - geschlossen, kleine Hoerner
    poly(layer, [(hx - 4, hy + 3), (hx - 4, hy - 3 + tilt), (hx - 1, hy - 6 + tilt),
                 (hx + 3, hy - 6 + tilt), (hx + 5, hy - 2), (hx + 5, hy + 3),
                 (hx + 2, hy + 4), (hx - 2, hy + 4)], STL_M)
    poly(layer, [(hx - 4, hy - 3 + tilt), (hx - 1, hy - 6 + tilt), (hx - 2, hy - 1),
                 (hx - 4, hy + 1)], STL_D)
    thick_line(layer, (hx - 1, hy - 6 + tilt), (hx + 3, hy - 6 + tilt), STL_L, 1)
    # kleine Hoerner
    thick_line(layer, (hx - 2, hy - 6 + tilt), (hx - 3, hy - 9 + tilt), STL_L, 1)
    thick_line(layer, (hx + 2, hy - 6 + tilt), (hx + 3, hy - 9 + tilt), STL_L, 1)
    # Visier-Schlitz - gluehende Augen dahinter
    rect(layer, hx - 3, hy, hx + 4, hy + 1, (10, 9, 12, 255))
    if p["eye"] > 0:
        px = layer.load()
        ec = GOLD_L if p["eye"] >= 1 else GOLD_M
        pset(px, hx - 1, hy, ec)
        pset(px, hx + 2, hy, ec)


def draw_shield(layer, hand, raise_amt=0.0):
    """Kite-Schild mit Kreuz - Detail: Schild der Busse."""
    x, y = hand[0] - 2, hand[1] - int(raise_amt * 6)
    poly(layer, [(x - 4, y - 7), (x + 4, y - 7), (x + 5, y - 1),
                 (x, y + 8), (x - 5, y - 1)], STL_M)
    poly(layer, [(x - 4, y - 7), (x - 1, y - 6), (x - 2, y + 6), (x - 5, y - 1)], STL_D)
    thick_line(layer, (x + 4, y - 7), (x + 5, y - 1), STL_L, 1)
    # Kreuz-Emblem
    thick_line(layer, (x, y - 5), (x, y + 3), GOLD_M, 1)
    thick_line(layer, (x - 2, y - 2), (x + 2, y - 2), GOLD_M, 1)


def draw_flail(layer, hand, ang_deg, chain_len=10, ball_r=3, glow=0.0):
    """Morgenstern - Kette + Stachelkugel (Waffen-Detail)."""
    a = math.radians(ang_deg)
    ball = (hand[0] + math.cos(a) * chain_len, hand[1] + math.sin(a) * chain_len)
    chain = bezier(hand, ((hand[0] + ball[0]) / 2, (hand[1] + ball[1]) / 2 - 2), ball, 8)
    for i, (x, y) in enumerate(chain):
        pset(layer.load(), x, y, RUST_M if i % 2 else RUST_D)
    disc(layer, ball[0], ball[1], ball_r, STL_D)
    disc(layer, ball[0], ball[1], max(1, ball_r - 1), STL_M)
    for i in range(6):
        sa = math.radians(i * 60 + ang_deg * 0.3)
        tx = ball[0] + math.cos(sa) * (ball_r + 2)
        ty = ball[1] + math.sin(sa) * (ball_r + 2)
        pset(layer.load(), tx, ty, STL_L)
    if glow > 0:
        pset(layer.load(), int(ball[0]), int(ball[1]), GOLD_L)
    return ball


def draw_guardian(p):
    back = new_layer()
    body = new_layer()
    front = new_layer()

    dy = p["dy"]
    hip_y = p["hip_y"] + dy
    sh_y = hip_y - 13
    hip = (CX, hip_y)
    sh_b = (CX - 5 + p["lean"], sh_y + 2)
    sh_f = (CX + 5 + p["lean"], sh_y + 2)

    knee_b = (CX + p["knee_b"][0], hip_y + p["knee_b"][1])
    foot_b = (CX + p["foot_b"][0], hip_y + p["foot_b"][1])
    knee_f = (CX + p["knee_f"][0], hip_y + p["knee_f"][1])
    foot_f = (CX + p["foot_f"][0], hip_y + p["foot_f"][1])

    el_s = (sh_b[0] + p["arm_shield"][0][0], sh_b[1] + p["arm_shield"][0][1])
    hd_s = (sh_b[0] + p["arm_shield"][1][0], sh_b[1] + p["arm_shield"][1][1])
    el_w = (sh_f[0] + p["arm_flail"][0][0], sh_f[1] + p["arm_flail"][0][1])
    hd_w = (sh_f[0] + p["arm_flail"][1][0], sh_f[1] + p["arm_flail"][1][1])

    draw_leg(back, hip, knee_b, foot_b, True)
    draw_arm(back, sh_b, el_s, hd_s, STL_D, STL_M)
    draw_shield(back, hd_s, p["shield_up"])

    draw_leg(body, hip, knee_f, foot_f, False)
    draw_torso(body, p, sh_y, hip_y)
    draw_head(body, p, sh_y)

    draw_arm(front, sh_f, el_w, hd_w, STL_M, (108, 112, 122, 255))

    body.alpha_composite(front)
    back.alpha_composite(body)
    return back, hd_w, hd_s, hip_y


def compose(p, fx_back=None, fx_front=None, ghosts=()):
    frame = new_layer()
    fig, hd_w, hd_s, hip_y = draw_guardian(p)

    for dx, dy, col, alpha in ghosts:
        g = tint(fig, col, alpha)
        frame.alpha_composite(g.transform((W, H), Image.AFFINE, (1, 0, -dx, 0, 1, -dy)))

    if fx_back:
        frame.alpha_composite(fx_back(p, hd_w, hd_s, hip_y))

    rim_light(fig)
    frame.alpha_composite(outline_layer(fig))

    if fx_front:
        frame.alpha_composite(fx_front(p, hd_w, hd_s, hip_y))
    return frame


# --------------------------------------------------------------------------
# Effekte
# --------------------------------------------------------------------------
def fx_flail_rest(p, hd_w, hd_s, hip_y):
    l = new_layer()
    draw_flail(l, hd_w, 100)
    return l


def fx_flail_swing(phase):
    """Kettenschlag: die Kugel umkreist den Waechter einmal komplett."""
    def f(p, hd_w, hd_s, hip_y):
        l = new_layer()
        ang = -90 + 320 * phase
        ball = draw_flail(l, hd_w, ang, chain_len=13, glow=0.5)
        trail = arc_pts(hd_w[0], hd_w[1], 13, ang - 70, ang, 10, 0.9)
        for i, (x, y) in enumerate(trail):
            pset(l.load(), x, y, STL_D if i < 5 else STL_M)
        return l
    return f


def fx_shield_bash(phase):
    """Schild bleibt an seinem Platz links vom Koerper, damit sein Kreuz nicht
    mit dem Brust-Kreuz kollidiert - der Ausfallschritt (lean) und ein fester
    Einschlagpunkt vor dem Koerper verkaufen den Stoss."""
    def f(p, hd_w, hd_s, hip_y):
        l = new_layer()
        draw_shield(l, hd_s, 0.3)
        if phase > 0.5:
            strike = (CX + 20, hip_y - 9)
            for i in range(5):
                a = math.radians(i * 72)
                x = strike[0] + math.cos(a) * 4
                y = strike[1] + math.sin(a) * 4
                pset(l.load(), x, y, GOLD_L if i % 2 else STL_L)
            for dy2 in (-3, 0, 3):
                thick_line(l, (strike[0] - 5, strike[1] + dy2),
                          (strike[0], strike[1] + dy2), STL_L, 1)
        return l
    return f


def fx_bastion(phase):
    """Heilige Bastion: goldene Kuppel waechst um den Waechter."""
    def f(p, hd_w, hd_s, hip_y):
        l = new_layer()
        r = 6 + 22 * min(1.0, phase * 1.2)
        ring(l, CX, hip_y - 10, r, GOLD_M, 1, ry=r * 0.9)
        for i in range(5):
            a = 180 + i * -45 * phase
            x = CX + math.cos(math.radians(a)) * r
            y = hip_y - 10 + math.sin(math.radians(a)) * r * 0.9
            if math.sin(math.radians(a)) <= 0.1:
                pset(l.load(), x, y, GOLD_L)
        ring(l, CX, GY - 2, r * 0.5, GOLD_D, 1, ry=max(2, r * 0.16))
        return l
    return f


def fx_fist_glint(p, hd_w, hd_s, hip_y):
    """Gepanzerte Faust hebt sich sichtbar neben den Helm - kleiner Glanzpunkt
    schafft Kontrast, da Arm und Helm sonst im selben Stahlton verschmelzen."""
    l = new_layer()
    pset(l.load(), hd_w[0], hd_w[1] - 1, STL_L)
    pset(l.load(), hd_w[0] + 1, hd_w[1], GOLD_M)
    return l


def fx_taunt(phase):
    """Buesseruf: Lichtsaeule schiesst nach oben, Ruf-Ring am Boden."""
    def f(p, hd_w, hd_s, hip_y):
        l = new_layer()
        top = hip_y - 14 - 18 * min(1.0, phase * 1.4)
        thick_line(l, (CX, hip_y - 14), (CX, top), GOLD_M, 2)
        thick_line(l, (CX, hip_y - 14), (CX, top), GOLD_L, 1)
        r = 4 + 16 * phase
        ring(l, CX, GY - 2, r, GOLD_D, 1, ry=max(2, r * 0.32))
        return l
    return f


def fx_ground_impact(phase):
    def f(p, hd_w, hd_s, hip_y):
        l = new_layer()
        if phase <= 0:
            return l
        r = 4 + 22 * phase
        col = GOLD_M if phase < 0.7 else GOLD_D
        ring(l, CX, GY - 1, r, col, 1, ry=max(2, r * 0.3))
        for i in range(6):
            a = math.radians(i * 60)
            x = CX + math.cos(a) * r
            y = GY - 1 + math.sin(a) * r * 0.3
            thick_line(l, (CX, GY - 1), (x, y), GOLD_D, 1)
        return l
    return f


def fx_unbreakable(phase):
    def f(p, hd_w, hd_s, hip_y):
        l = new_layer()
        r = 10 + 10 * phase
        for i in range(int(6 + phase * 10)):
            a = math.radians(i * 37 + phase * 90)
            x = CX + math.cos(a) * r
            y = hip_y - 8 + math.sin(a) * r * 0.85
            pset(l.load(), x, y, GOLD_L if i % 2 else GOLD_M)
        return l
    return f


# --------------------------------------------------------------------------
# Animationen
# --------------------------------------------------------------------------
def anim_idle():
    frames = []
    for i, b in enumerate((0, -1, 0, 1)):
        p = pose(dy=b, shield_up=0.3, eye=1.0 if i != 2 else 0.7,
                 cross_glow=0.4 + 0.1 * (i % 2))
        frames.append(compose(p, fx_front=fx_flail_rest))
    return frames, 6, True


def anim_run():
    frames = []
    cyc = [
        (0, (9, 19), (-8, 22)), (-1, (6, 15), (-4, 21)),
        (0, (2, 21), (2, 19)), (0, (-4, 22), (8, 19)),
        (-1, (-6, 15), (6, 15)), (0, (-8, 21), (9, 20)),
    ]
    for dy, (ffx, ffy), (bfx, bfy) in cyc:
        p = pose(dy=dy, lean=3, foot_f=(ffx, ffy), knee_f=(ffx // 2 + 2, 9),
                 foot_b=(bfx, bfy), knee_b=(bfx // 2 - 1, 9),
                 cloth_sway=2, shield_up=0.2, head_dx=2)
        frames.append(compose(p, fx_front=fx_flail_rest))
    return frames, 10, True


def anim_shield_bash():
    """Schildstoss: kurzer Ausfallschritt, Schild voraus, Rueckstoss-Impact."""
    frames = []
    frames.append(compose(pose(lean=-2, shield_up=0.5)))
    for i, ph in enumerate((0.3, 0.6, 1.0)):
        p = pose(lean=5 + i * 2, shield_up=0.6,
                 knee_f=(6, 7), foot_f=(11, 20), knee_b=(-3, 9), foot_b=(-6, 22))
        frames.append(compose(p, fx_front=fx_shield_bash(ph)))
    frames.append(compose(pose(lean=2, shield_up=0.3), fx_front=fx_flail_rest))
    return frames, 12, False


def anim_chain_swing():
    """Kettenschlag: die Kugel schwingt einmal komplett um den Koerper."""
    frames = []
    for i, ph in enumerate((0.0, 0.2, 0.4, 0.6, 0.8, 1.0)):
        p = pose(lean=1, shield_up=0.2, helm_tilt=0 if i % 2 == 0 else 1,
                 head_dx=2)
        frames.append(compose(p, fx_front=fx_flail_swing(ph)))
    return frames, 16, False


def anim_bastion():
    """Heilige Bastion: Schild verankert, goldene Schutzkuppel waechst."""
    frames = []
    for i, ph in enumerate((0.1, 0.35, 0.6, 0.85, 1.0)):
        p = pose(dy=0, shield_up=0.8, cross_glow=0.5 + ph * 0.5, eye=1.0)
        frames.append(compose(p, fx_back=fx_bastion(ph), fx_front=fx_flail_rest))
    return frames, 10, False


def anim_taunt():
    """Buesseruf: Faust/Waffe hoch, Lichtsaeule ruft die Aggro."""
    frames = []
    for i, ph in enumerate((0.0, 0.35, 0.7, 1.0)):
        p = pose(dy=-1 if i > 0 else 0, arm_flail=((9, -3), (14, -10)),
                 shield_up=0.2, cross_glow=0.6 + ph * 0.4, eye=1.0)
        frames.append(compose(p, fx_back=fx_taunt(ph), fx_front=fx_fist_glint))
    return frames, 8, False


def anim_guardian_leap():
    """Rache des Waechters: hochspringen, in der Luft halten, einschlagen."""
    frames = []
    frames.append(compose(pose(dy=4, lean=3, shield_up=0.3,
                               knee_f=(5, 5), foot_f=(8, 15), knee_b=(-5, 6),
                               foot_b=(-8, 17))))
    frames.append(compose(pose(dy=-10, lean=2, shield_up=0.1,
                               knee_f=(6, 10), foot_f=(9, 16), knee_b=(-6, 10),
                               foot_b=(-9, 15), arm_flail=((5, -4), (9, -9)))))
    frames.append(compose(pose(dy=-14, lean=0, shield_up=0.1,
                               knee_f=(4, 12), foot_f=(6, 18), knee_b=(-4, 12),
                               foot_b=(-6, 18), arm_flail=((6, -6), (10, -12)))))
    frames.append(compose(pose(dy=2, lean=1, shield_up=0.4,
                               knee_f=(5, 6), foot_f=(8, 20), knee_b=(-5, 6),
                               foot_b=(-8, 21), arm_flail=((7, 1), (11, 6))),
                          fx_front=fx_ground_impact(1.0)))
    frames.append(compose(pose(dy=0, shield_up=0.3), fx_front=fx_flail_rest))
    return frames, 14, False


def anim_hurt():
    frames = []
    for lean, dy in ((-4, 1), (-2, 0)):
        p = pose(dy=dy, lean=lean, shield_up=0.5, eye=1.0)
        f = compose(p)
        fl = new_layer()
        for x, y in ((26, 24), (34, 22), (30, 30)):
            pset(fl.load(), x, y, STL_L)
        f.alpha_composite(fl)
        frames.append(f)
    return frames, 10, False


def anim_death():
    frames = []
    specs = [(2, -2, 0.7, 255), (7, 0, 0.4, 255), (13, 2, 0.15, 225), (18, 4, 0.0, 175)]
    for dy, lean, eye, alpha in specs:
        p = pose(dy=dy, lean=lean, shield_up=0.1,
                 knee_f=(6, 5), foot_f=(8, GY - 37 - dy), knee_b=(-6, 5),
                 foot_b=(-8, GY - 37 - dy), arm_flail=((6, 6), (9, 10)), eye=eye,
                 cross_glow=max(0.1, 0.4 - dy * 0.02))
        f = compose(p)
        if alpha < 255:
            f.putalpha(f.getchannel("A").point(lambda v: v * alpha // 255))
        frames.append(f)
    return frames, 8, False


def anim_ultimate():
    """Unzerbrechlich: er huellt sich in heiliges Licht, wird unaufhaltsam."""
    frames = []
    for i, ph in enumerate((0.1, 0.3, 0.5, 0.7, 0.85, 1.0)):
        p = pose(dy=-1 if i > 2 else 0, shield_up=0.5 + ph * 0.3,
                 cross_glow=0.5 + ph * 0.5, eye=1.0)
        frames.append(compose(p, fx_back=fx_unbreakable(ph), fx_front=fx_flail_rest))
    return frames, 10, False


ANIMS = [
    ("idle", anim_idle),
    ("run", anim_run),
    ("shield_bash", anim_shield_bash),
    ("chain_swing", anim_chain_swing),
    ("bastion", anim_bastion),
    ("taunt", anim_taunt),
    ("guardian_leap", anim_guardian_leap),
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
    meta = {"image": "blutwaechter.png", "frameWidth": W, "frameHeight": H,
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

    sheet.save(os.path.join(OUTDIR, "blutwaechter.png"))
    Image.open(os.path.join(OUTDIR, "blutwaechter.png")).resize(
        (sheet.width * 4, sheet.height * 4), Image.NEAREST).save(
        os.path.join(OUTDIR, "blutwaechter@4x.png"))
    with open(os.path.join(OUTDIR, "blutwaechter.json"), "w") as fh:
        json.dump(meta, fh, indent=2)

    import base64
    with open(os.path.join(OUTDIR, "blutwaechter.png"), "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()
    html = (gs.PREVIEW.replace("Nightbane - Sprite Preview", "Blutwaechter - Sprite Preview")
                       .replace("Nightbane &mdash; Jaeger", "Nightbane &mdash; Blutwaechter")
                       .replace("__B64__", b64).replace("__META__", json.dumps(meta)))
    with open(os.path.join(OUTDIR, "preview.html"), "w", encoding="utf-8") as fh:
        fh.write(html)

    print(f"sheet {sheet.width}x{sheet.height}  ({rows} Animationen, {cols} Spalten)")
    for name, frames, fps, loop in built:
        print(f"  {name:<14} {len(frames)} Frames @ {fps} fps  loop={loop}")


if __name__ == "__main__":
    main()

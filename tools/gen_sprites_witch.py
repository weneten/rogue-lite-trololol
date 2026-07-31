"""
Nightbane - Schattenhexerin: Pixel-Art Sprite-Generator (gleicher Stil wie
Jaeger und Blutwolf).

Erzeugt aus dem Schattenhexerin-Konzept-Art einen spielbaren 2D-Charakter
als Sprite-Sheet (64x64 pro Frame, Blickrichtung rechts, horizontal
spiegeln fuer links). Nutzt dieselben Pixel-Primitive wie
tools/gen_sprites.py (Rim-Light + Outline-Postprocessing), aber einen
eigenen Koerperbau (bodenlanger zerrissener Robe, Ritualmaske, Schattenstab)
und eigene Animationen.

Ausgabe:  assets/sprites/schattenhexerin/schattenhexerin.png
          assets/sprites/schattenhexerin/schattenhexerin.json
          assets/sprites/schattenhexerin/strips/<anim>.png
          assets/sprites/schattenhexerin/preview.html

Aufruf:   python tools/gen_sprites_witch.py
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
MET_D, MET_M, MET_L, BONE = gs.MET_D, gs.MET_M, gs.MET_L, gs.BONE

# --------------------------------------------------------------------------
# Palette (aus dem Konzept-Art: zerrissener Stoff, Knochen, Seelenenergie)
# --------------------------------------------------------------------------
ROBE_D = (13, 11, 18, 255)      # Robe dunkel (Schatten)
ROBE_M = (24, 21, 32, 255)      # Robe mittel
ROBE_L = (38, 33, 50, 255)      # Robe Kante
MASK_D = (96, 88, 94, 255)      # Ritualmaske Schatten
MASK_L = (154, 144, 148, 255)   # Ritualmaske Licht
PUR_D  = (52, 18, 82, 255)      # Seelenenergie dunkel
PUR_M  = (112, 44, 168, 255)    # Seelenenergie mittel
PUR_L  = (206, 132, 246, 255)   # Seelenenergie hell / Glut
RIT_D  = (44, 34, 30, 255)      # Blut & Ritual dunkel
RIT_M  = (86, 24, 30, 255)      # Blut & Ritual mittel

OUTDIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "assets", "sprites", "schattenhexerin")

ROBE_TEETH = [0, 4, 1, 5, 2, 0, 4, 1, 5, 2, 0, 4, 2]


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
        dy=0, lean=0, hip_y=42,
        hem_sway=0, hem_tear=0, hover=0,
        arm_b=((-7, 2), (-9, 10)),      # Stab-Arm (hinten)
        arm_f=((6, 0), (10, -3)),       # freie Hand (vorn, casting)
        hood_tilt=0, head_dx=1, head_dy=0,
        eye=1.0, staff_glow=1.0,
    )
    p.update(kw)
    return p


# --------------------------------------------------------------------------
# Koerperteile
# --------------------------------------------------------------------------
def draw_robe(layer, p, sh_y):
    """Bodenlange, zerrissene Robe - verdeckt die Beine komplett."""
    sway = p["hem_sway"]
    lean = p["lean"]
    top_l, top_r = CX - 8 + lean, CX + 8 + lean
    bot = GY - p["hover"]
    left = CX - 11 - sway
    right = CX + 10 + sway * 0.4
    pts = [(top_l, sh_y - 1), (top_r, sh_y - 1),
           (right, bot - 20), (right + 1, bot - 6)]
    pts += tattered_hem(left, right, bot, ROBE_TEETH)
    pts += [(left - 1, bot - 6), (left, bot - 20)]
    poly(layer, pts, ROBE_M)
    # Schattenseite
    poly(layer, [(top_l, sh_y - 1), (CX - 1 + lean, sh_y),
                 (CX - 3, bot - 4), (left, bot - 8), (left, bot - 20)], ROBE_D)
    # Saumkante (Zerfetzter Stoff)
    thick_line(layer, (right, bot - 20), (right + 1, bot - 6), ROBE_L, 1)
    # Faltenwurf
    for i, fx in enumerate((-4, 1, 6)):
        x = CX + fx + lean - sway * (0.5 - i * 0.15)
        thick_line(layer, (x, sh_y + 6), (x - 1, bot - 10 - i * 2), ROBE_D, 1)


def draw_torso_details(layer, p, sh_y):
    """Okkulte Symbole + Talismane auf der Brust (Details im Konzept)."""
    lean = p["lean"]
    cx = CX + lean
    # Okkultes Symbol - schwaches Glimmen
    thick_line(layer, (cx - 2, sh_y + 3), (cx + 2, sh_y + 7), PUR_D, 1)
    thick_line(layer, (cx + 2, sh_y + 3), (cx - 2, sh_y + 7), PUR_D, 1)
    pset(layer.load(), cx, sh_y + 5, PUR_M)
    # Talisman-Kette mit kleinem Schaedel-Anhaenger - klein und dezent
    chain = bezier((cx - 4, sh_y + 2), (cx - 5, sh_y + 6), (cx - 4, sh_y + 9), 4)
    for i, (x, y) in enumerate(chain):
        pset(layer.load(), x, y, MET_D if i % 2 else MET_M)
    disc(layer, cx - 4, sh_y + 10, 1, BONE)


def draw_arm(layer, sh, elbow, hand, back, col=ROBE_M):
    thick_line(layer, sh, elbow, ROBE_D if back else col, 3)
    thick_line(layer, elbow, hand, ROBE_D if back else col, 2)
    disc(layer, hand[0], hand[1], 1, (68, 60, 74, 255))


def draw_hood_mask(layer, p, sh_y):
    hx = CX + p["head_dx"] + p["lean"]
    hy = sh_y - 6 + p["head_dy"]
    tilt = p["hood_tilt"]
    # Kapuze - spitz zulaufend, verdeckt den Schaedel
    poly(layer, [(hx - 6, hy + 5), (hx - 6, hy - 2), (hx - 2, hy - 8 + tilt),
                 (hx + 3, hy - 9 + tilt), (hx + 7, hy - 3), (hx + 6, hy + 5),
                 (hx + 2, hy + 2), (hx - 2, hy + 2)], ROBE_D)
    thick_line(layer, (hx - 2, hy - 8 + tilt), (hx + 3, hy - 9 + tilt), ROBE_L, 1)
    # Ritualmaske - blassse, ausdruckslose Flaeche mit Glitzeraugen
    poly(layer, [(hx - 2, hy - 1), (hx + 2, hy - 2), (hx + 3, hy + 1),
                 (hx + 1, hy + 3), (hx - 2, hy + 2)], MASK_D)
    pset(layer.load(), hx, hy, MASK_L)
    # Augen - Seelenenergie glimmt durch die Maske
    if p["eye"] > 0:
        px = layer.load()
        ec = PUR_L if p["eye"] >= 1 else PUR_M
        pset(px, hx - 1, hy, ec)
        pset(px, hx, hy, ec)
        pset(px, hx + 1, hy - 1, ec)
        pset(px, hx + 2, hy - 1, ec)


def draw_staff(layer, hand, tilt=-70, glow=1.0, length=17):
    """Schattenstab - Halbmond mit schwebendem Seelen-Orb."""
    a = math.radians(tilt)
    tip = (hand[0] + math.cos(a) * length, hand[1] + math.sin(a) * length)
    thick_line(layer, hand, tip, MET_D, 2)
    thick_line(layer, (hand[0] + (tip[0] - hand[0]) * 0.3,
                       hand[1] + (tip[1] - hand[1]) * 0.3), tip, MET_M, 1)
    # Halbmond-Krone
    for x, y in arc_pts(tip[0], tip[1] - 2, 4, -160, 40, 8, 1.0):
        pset(layer.load(), x, y, MET_M)
    # Seelen-Orb
    if glow > 0:
        r = 2 + glow
        disc(layer, tip[0], tip[1] - 4, r, PUR_D)
        disc(layer, tip[0], tip[1] - 4, max(1, r - 1), PUR_M)
        pset(layer.load(), int(tip[0]), int(tip[1] - 4), PUR_L)
    return tip


def draw_skull_orb(layer, x, y, r=2, col=PUR_M):
    disc(layer, x, y, r, PUR_D)
    pset(layer.load(), int(x), int(y), col)


def draw_witch(p):
    back = new_layer()
    body = new_layer()
    front = new_layer()

    dy = p["dy"]
    hip_y = p["hip_y"] + dy
    sh_y = hip_y - 20
    sh_b = (CX - 6 + p["lean"], sh_y + 2)
    sh_f = (CX + 6 + p["lean"], sh_y + 2)

    el_b = (sh_b[0] + p["arm_b"][0][0], sh_b[1] + p["arm_b"][0][1])
    hd_b = (sh_b[0] + p["arm_b"][1][0], sh_b[1] + p["arm_b"][1][1])
    el_f = (sh_f[0] + p["arm_f"][0][0], sh_f[1] + p["arm_f"][0][1])
    hd_f = (sh_f[0] + p["arm_f"][1][0], sh_f[1] + p["arm_f"][1][1])

    draw_arm(back, sh_b, el_b, hd_b, True)
    staff_tip = draw_staff(back, hd_b, tilt=-95, glow=p["staff_glow"])

    draw_robe(body, p, sh_y)
    draw_torso_details(body, p, sh_y)
    draw_hood_mask(body, p, sh_y)

    draw_arm(front, sh_f, el_f, hd_f, False)

    body.alpha_composite(front)
    back.alpha_composite(body)
    return back, hd_f, hd_b, staff_tip, hip_y


def compose(p, fx_back=None, fx_front=None, ghosts=()):
    frame = new_layer()
    fig, hd_f, hd_b, staff_tip, hip_y = draw_witch(p)

    for dx, dy, col, alpha in ghosts:
        g = tint(fig, col, alpha)
        frame.alpha_composite(g.transform((W, H), Image.AFFINE, (1, 0, -dx, 0, 1, -dy)))

    if fx_back:
        frame.alpha_composite(fx_back(p, hd_f, hd_b, staff_tip, hip_y))

    rim_light(fig)
    frame.alpha_composite(outline_layer(fig))

    if fx_front:
        frame.alpha_composite(fx_front(p, hd_f, hd_b, staff_tip, hip_y))
    return frame


# --------------------------------------------------------------------------
# Effekte
# --------------------------------------------------------------------------
def fx_idle_wisps(phase):
    def f(p, hd_f, hd_b, staff_tip, hip_y):
        l = new_layer()
        for i in range(2):
            a = phase * 360 + i * 180
            x = staff_tip[0] + math.cos(math.radians(a)) * 3
            y = staff_tip[1] - 4 + math.sin(math.radians(a)) * 2
            pset(l.load(), x, y, PUR_L)
        return l
    return f


def fx_drain(phase):
    """Seelensaug: kleine Skull-Seelen wandern zur Hand, Heilglimmen am Koerper."""
    def f(p, hd_f, hd_b, staff_tip, hip_y):
        l = new_layer()
        for i, base in enumerate((0.0, 0.33, 0.66)):
            t = (phase + base) % 1.0
            x = hd_f[0] + (CX - hd_f[0]) * (1 - t) + (i - 1) * 4
            y = hd_f[1] + 6 - t * 4
            draw_skull_orb(l, x, y, r=1, col=PUR_M)
        if phase > 0.5:
            ring(l, CX, hip_y - 12, 6 + (phase - 0.5) * 6, PUR_D, 1)
        return l
    return f


def fx_orb_throw(phase):
    def f(p, hd_f, hd_b, staff_tip, hip_y):
        l = new_layer()
        x0, y0 = hd_f
        tx, ty = CX + 26, hip_y - 16
        x = x0 + (tx - x0) * phase
        y = y0 + (ty - y0) * phase - math.sin(phase * math.pi) * 6
        trail = bezier((x0, y0), ((x0 + x) / 2, (y0 + y) / 2 - 4), (x, y), 6)
        for i, (tx2, ty2) in enumerate(trail):
            pset(l.load(), tx2, ty2, PUR_D if i < 3 else PUR_M)
        draw_skull_orb(l, x, y, r=2 if phase < 0.85 else 3,
                       col=PUR_L if phase > 0.8 else PUR_M)
        if phase > 0.85:
            ring(l, x, y, (phase - 0.85) * 30, PUR_M, 1)
        return l
    return f


def fx_nova(phase):
    def f(p, hd_f, hd_b, staff_tip, hip_y):
        l = new_layer()
        r = 4 + 26 * min(1.0, phase * 1.2)
        col = PUR_M if phase < 0.7 else PUR_D
        ring(l, CX, hip_y - 8, r, col, 1, ry=max(2, r * 0.55))
        ring(l, CX, hip_y - 8, max(2, r - 5), PUR_D, 1, ry=max(1, (r - 5) * 0.55))
        for i in range(8):
            a = math.radians(phase * 200 + i * 45)
            pset(l.load(), CX + math.cos(a) * r, hip_y - 8 + math.sin(a) * r * 0.55, PUR_L)
        return l
    return f


def fx_stakes(phase):
    def f(p, hd_f, hd_b, staff_tip, hip_y):
        l = new_layer()
        for i, ox in enumerate((-16, -6, 8, 18)):
            t = max(0.0, min(1.0, (phase - i * 0.15) * 2.2))
            if t <= 0:
                continue
            h = 18 * t
            x = CX + ox
            thick_line(l, (x, GY), (x, GY - h), PUR_D, 2)
            thick_line(l, (x, GY - h), (x - 1, GY - h + 3), PUR_M, 1)
            if t > 0.6:
                pset(l.load(), x, GY - h, PUR_L)
        return l
    return f


def fx_sacrifice(phase):
    def f(p, hd_f, hd_b, staff_tip, hip_y):
        l = new_layer()
        r = 8 + 18 * min(1.0, phase * 1.2)
        cy = hip_y - 10 - r * 0.3
        disc(l, CX, cy, r * 0.5, (30, 10, 46, 255))
        ring(l, CX, cy, r * 0.55, PUR_D, 1)
        if phase > 0.4:
            ring(l, CX, cy, r * 0.3, PUR_M, 1)
            eye_y = cy - r * 0.15
            pset(l.load(), CX - 2, eye_y, PUR_L)
            pset(l.load(), CX + 2, eye_y, PUR_L)
        if phase > 0.6:
            for i in range(6):
                a = math.radians(phase * 300 + i * 60)
                pset(l.load(), CX + math.cos(a) * r * 0.6,
                     hip_y - 6 + math.sin(a) * r * 0.2, PUR_L)
        return l
    return f


# --------------------------------------------------------------------------
# Animationen
# --------------------------------------------------------------------------
def anim_idle():
    frames = []
    for i, (b, sway) in enumerate(((0, 0), (-1, 1), (0, 1), (1, 0))):
        p = pose(dy=b, hem_sway=sway, hover=1 - b,
                 arm_f=((5, -1 - b), (8, -3 - b)), eye=1.0 if i != 2 else 0.75)
        frames.append(compose(p, fx_front=fx_idle_wisps(i / 4)))
    return frames, 6, True


def anim_run():
    """Schweben/Gleiten - Robe peitscht nach hinten, kein sichtbarer Schritt."""
    frames = []
    sways = (4, 7, 10, 8, 5, 2)
    for i, sway in enumerate(sways):
        p = pose(dy=-1 if i % 2 else 0, lean=5, hem_sway=sway, hover=2,
                 arm_f=((8, -2 - i % 2), (13, -6 - i % 2)),
                 arm_b=((-8, -1), (-12, 1)), head_dx=3)
        l = new_layer()
        for k, y in enumerate((30, 36, 42)):
            x1 = CX - 6 - sway * 0.6
            thick_line(l, (x1, y), (x1 - 4 - k, y), ROBE_L, 1)
        frames.append(compose(p, fx_back=lambda p, a, b, c, d, l=l: l))
    return frames, 12, True


def anim_dash():
    """Schattenschritt: kurzes Aufloesen in Rauch, Neuerscheinen mit Versatz."""
    frames = []
    frames.append(compose(pose(hem_sway=-2, lean=-2)))
    for i in range(3):
        p = pose(lean=6 + i * 2, hem_sway=8 + i * 2, hover=3,
                 arm_f=((8, -3), (13, -6)))
        ghosts = [(-8 - i * 4, 0, PUR_M, 90 - i * 15), (-16 - i * 5, 0, PUR_D, 55)]
        frames.append(compose(p, ghosts=ghosts))
    frames.append(compose(pose(lean=2, hem_sway=2), ghosts=[(-6, 0, PUR_D, 45)]))
    return frames, 16, False


def anim_attack_orbs():
    """Schattensphaeren: Ausholen -> Wurf -> Einschlag."""
    frames = []
    frames.append(compose(pose(lean=-2, arm_f=((3, -6), (2, -11)))))
    for i, ph in enumerate((0.2, 0.5, 0.75, 1.0)):
        p = pose(lean=2 + i, arm_f=((8 + i, -4 + i), (14 + i, -8 + i)))
        frames.append(compose(p, fx_front=fx_orb_throw(ph)))
    return frames, 14, False


def anim_attack_nova():
    """Dunkler Nova: Stab in den Boden, Schockwelle radial nach aussen."""
    frames = []
    for i, ph in enumerate((0.05, 0.3, 0.55, 0.8, 1.0)):
        p = pose(dy=-1 if i in (1, 2) else 0, lean=0,
                 arm_f=((0, 4), (0, 8)), arm_b=((-3, 6), (-2, 12)),
                 hem_sway=int(4 * ph), staff_glow=1.5, eye=1.0)
        frames.append(compose(p, fx_back=fx_nova(ph)))
    return frames, 14, False


def anim_soul_drain():
    """Seelensaug: Hand ausgestreckt, kleine Seelen wandern heran."""
    frames = []
    for i, ph in enumerate((0.0, 0.3, 0.6, 0.9)):
        p = pose(lean=-1, arm_f=((10, -2), (16, -4)), eye=1.0)
        frames.append(compose(p, fx_front=fx_drain(ph)))
    return frames, 8, False


def anim_stakes():
    """Seelenpfaehle: Stab hebt sich, Schattenpfaehle durchbohren den Boden."""
    frames = []
    for i, ph in enumerate((0.05, 0.3, 0.55, 0.8)):
        p = pose(dy=-1 if i > 0 else 0, arm_b=((-7, -2), (-9, -8)),
                 staff_glow=1.5 + ph)
        frames.append(compose(p, fx_front=fx_stakes(ph)))
    return frames, 10, False


def anim_hurt():
    frames = []
    for lean, dy in ((-5, 1), (-2, 0)):
        p = pose(dy=dy, lean=lean, hem_sway=-3,
                 arm_f=((3, 2), (4, -1)), eye=1.0)
        f = compose(p)
        fl = new_layer()
        for x, y in ((26, 26), (34, 24), (30, 32)):
            pset(fl.load(), x, y, PUR_L)
        f.alpha_composite(fl)
        frames.append(f)
    return frames, 10, False


def anim_death():
    frames = []
    specs = [(1, -2, 0.7, 255), (5, -1, 0.4, 255), (10, 1, 0.15, 220), (15, 3, 0.0, 170)]
    for dy, lean, eye, alpha in specs:
        p = pose(dy=dy, lean=lean, hover=-dy * 0.4, hem_sway=-4,
                 arm_f=((5, 4), (8, 8)), arm_b=((-5, 4), (-7, 8)), eye=eye)
        f = compose(p)
        if alpha < 255:
            f.putalpha(f.getchannel("A").point(lambda v: v * alpha // 255))
        frames.append(f)
    return frames, 8, False


def anim_ultimate():
    """Seelenopfer: Sie sinkt in sich zusammen, ein grosser Geist erhebt sich."""
    frames = []
    for i, ph in enumerate((0.1, 0.3, 0.5, 0.7, 0.85, 1.0)):
        p = pose(dy=int(2 * ph), lean=-1, hem_sway=int(3 * ph), hover=-int(2 * ph),
                 arm_f=((4, 3), (6, 7)), arm_b=((-4, 3), (-6, 7)),
                 eye=max(0.3, 1.0 - ph * 0.5), staff_glow=1.0 + ph)
        frames.append(compose(p, fx_back=fx_sacrifice(ph)))
    return frames, 10, False


ANIMS = [
    ("idle", anim_idle),
    ("run", anim_run),
    ("dash", anim_dash),
    ("attack_orbs", anim_attack_orbs),
    ("attack_nova", anim_attack_nova),
    ("soul_drain", anim_soul_drain),
    ("stakes", anim_stakes),
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
    meta = {"image": "schattenhexerin.png", "frameWidth": W, "frameHeight": H,
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

    sheet.save(os.path.join(OUTDIR, "schattenhexerin.png"))
    Image.open(os.path.join(OUTDIR, "schattenhexerin.png")).resize(
        (sheet.width * 4, sheet.height * 4), Image.NEAREST).save(
        os.path.join(OUTDIR, "schattenhexerin@4x.png"))
    with open(os.path.join(OUTDIR, "schattenhexerin.json"), "w") as fh:
        json.dump(meta, fh, indent=2)

    import base64
    with open(os.path.join(OUTDIR, "schattenhexerin.png"), "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()
    html = (gs.PREVIEW.replace("Nightbane - Sprite Preview", "Schattenhexerin - Sprite Preview")
                       .replace("Nightbane &mdash; Jaeger", "Nightbane &mdash; Schattenhexerin")
                       .replace("__B64__", b64).replace("__META__", json.dumps(meta)))
    with open(os.path.join(OUTDIR, "preview.html"), "w", encoding="utf-8") as fh:
        fh.write(html)

    print(f"sheet {sheet.width}x{sheet.height}  ({rows} Animationen, {cols} Spalten)")
    for name, frames, fps, loop in built:
        print(f"  {name:<14} {len(frames)} Frames @ {fps} fps  loop={loop}")


if __name__ == "__main__":
    main()

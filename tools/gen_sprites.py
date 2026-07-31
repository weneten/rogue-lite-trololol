"""
Nightbane - Jaeger: Pixel-Art Sprite-Generator.

Erzeugt aus dem Konzept-Art einen spielbaren 2D-Charakter als Sprite-Sheet
(64x64 pro Frame, Blickrichtung rechts, horizontal spiegeln fuer links).

Ausgabe:  assets/sprites/nightbane_hunter.png
          assets/sprites/nightbane_hunter.json   (Atlas + Animationen)
          assets/sprites/strips/<anim>.png       (einzelne Streifen)

Aufruf:   python tools/gen_sprites.py
"""

import json
import math
import os

from PIL import Image, ImageDraw

# --------------------------------------------------------------------------
# Palette (aus dem Konzept-Art: Schwarz/Anthrazit, Leder, Blutrot, Knochen)
# --------------------------------------------------------------------------
OUT    = (8, 7, 10, 255)        # Outline
CLK_D  = (22, 21, 26, 255)      # Umhang dunkel
CLK_M  = (36, 35, 42, 255)      # Umhang mittel
CLK_L  = (56, 55, 66, 255)      # Umhang Kante
LEA_D  = (28, 22, 20, 255)      # Leder dunkel
LEA_M  = (50, 39, 34, 255)      # Leder mittel
LEA_L  = (74, 59, 48, 255)      # Leder Kante
MET_D  = (44, 46, 52, 255)      # Metall dunkel
MET_M  = (92, 96, 104, 255)     # Metall mittel
MET_L  = (140, 146, 156, 255)   # Metall Glanz
SKIN   = (146, 118, 96, 255)    # Haut
SKIN_D = (96, 76, 62, 255)      # Haut Schatten
RED_D  = (104, 14, 18, 255)     # Blutrot dunkel
RED_M  = (178, 28, 30, 255)     # Blutrot
RED_L  = (240, 84, 64, 255)     # Blutrot hell / Glut
BONE   = (206, 196, 178, 255)   # Knochen / Beige
RIM    = (72, 74, 88, 255)      # Rim-Light oben

W = H = 64          # Framegroesse
CX = 30             # Koerpermitte
GY = 58             # Bodenlinie

OUTDIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "assets", "sprites")


# --------------------------------------------------------------------------
# Zeichen-Helfer (alles hart gepixelt, kein Antialiasing)
# --------------------------------------------------------------------------
def new_layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def pset(px, x, y, c):
    x, y = int(x), int(y)
    if 0 <= x < W and 0 <= y < H:
        px[x, y] = c


def thick_line(layer, p0, p1, col, width=1):
    """Bresenham mit quadratischem Pinsel - liefert saubere Pixelkanten."""
    px = layer.load()
    x0, y0 = int(round(p0[0])), int(round(p0[1]))
    x1, y1 = int(round(p1[0])), int(round(p1[1]))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    r0 = -(width // 2)
    r1 = r0 + width
    while True:
        for oy in range(r0, r1):
            for ox in range(r0, r1):
                pset(px, x0 + ox, y0 + oy, col)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def poly(layer, pts, col):
    d = ImageDraw.Draw(layer)
    d.polygon([(int(round(x)), int(round(y))) for x, y in pts], fill=col)


def rect(layer, x0, y0, x1, y1, col):
    d = ImageDraw.Draw(layer)
    d.rectangle([int(x0), int(y0), int(x1), int(y1)], fill=col)


def disc(layer, cx, cy, r, col):
    d = ImageDraw.Draw(layer)
    d.ellipse([int(cx - r), int(cy - r), int(cx + r), int(cy + r)], fill=col)


def ring(layer, cx, cy, r, col, width=1, ry=None):
    ry = r if ry is None else ry
    d = ImageDraw.Draw(layer)
    d.ellipse([int(cx - r), int(cy - ry), int(cx + r), int(cy + ry)],
              outline=col, width=width)


def bezier(p0, p1, p2, steps):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def arc_pts(cx, cy, r, a0, a1, steps, squash=1.0):
    out = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        out.append((cx + math.cos(a) * r, cy + math.sin(a) * r * squash))
    return out


def rim_light(layer):
    """Helle Oberkante -> Silhouette bleibt auf dunklem Hintergrund lesbar."""
    src = layer.copy()
    spx, dpx = src.load(), layer.load()
    for y in range(1, H):
        for x in range(W):
            if spx[x, y][3] and spx[x, y - 1][3] == 0:
                c = spx[x, y]
                if c[0] + c[1] + c[2] < 260:      # nur dunkle Flaechen aufhellen
                    dpx[x, y] = (min(c[0] + 26, RIM[0]), min(c[1] + 26, RIM[1]),
                                 min(c[2] + 30, RIM[2]), 255)


def outline_layer(layer, col=OUT):
    """Ein Pixel Kontur aussen herum."""
    src = layer.copy()
    spx = src.load()
    dst = layer.copy()
    dpx = dst.load()
    for y in range(H):
        for x in range(W):
            if spx[x, y][3]:
                continue
            for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + ox, y + oy
                if 0 <= nx < W and 0 <= ny < H and spx[nx, ny][3]:
                    dpx[x, y] = col
                    break
    return dst


def tint(layer, col, alpha):
    """Silhouette einfaerben (Nachbilder / Blutmond)."""
    out = new_layer()
    spx, opx = layer.load(), out.load()
    for y in range(H):
        for x in range(W):
            if spx[x, y][3]:
                opx[x, y] = (col[0], col[1], col[2], alpha)
    return out


# --------------------------------------------------------------------------
# Pose
# --------------------------------------------------------------------------
def pose(**kw):
    p = dict(
        dy=0,               # ganzer Koerper hoch/runter
        lean=0,             # Oberkoerper-Neigung (px an der Schulter)
        hip_y=36,
        knee_b=(-3, 8), foot_b=(-6, 22),
        knee_f=(3, 8), foot_f=(6, 22),
        arm_b=((-5, 5), (-6, 10)),      # (Ellbogen, Hand) relativ zur Schulter
        arm_f=((5, 5), (8, 9)),
        coat_sway=0, coat_flare=0,
        cloak_sway=0, cloak_lift=0,
        hat_tilt=0, head_dx=1, head_dy=0,
        eye=1.0,
        weapon="whip_rest",
    )
    p.update(kw)
    return p


# --------------------------------------------------------------------------
# Koerperteile
# --------------------------------------------------------------------------
# Tatter-Muster fuer die Saeume (fix, damit es zwischen Frames nicht flackert)
COAT_TEETH = [0, 3, 1, 4, 0, 2, 4, 1, 3, 0, 2, 4]
CLOAK_TEETH = [2, 5, 1, 4, 6, 2, 5, 3, 6, 1, 4, 2, 5]


def tattered_hem(x0, x1, y, teeth, step=2):
    """Zackiger Saum von rechts nach links (fuer Polygon-Unterkante)."""
    pts = []
    n = max(2, int((x1 - x0) // step))
    for i in range(n + 1):
        x = x1 - (x1 - x0) * i / n
        pts.append((x, y + teeth[i % len(teeth)]))
    return pts


def draw_cloak(layer, p, sh_y, hip_y):
    """Grosser zerrissener Umhang hinter dem Koerper."""
    sway = p["cloak_sway"]
    lift = p["cloak_lift"]
    top_x = CX - 3 + p["lean"]
    bot_y = hip_y + 12 - lift
    left = CX - 8 - sway
    pts = [(top_x + 4, sh_y - 3), (top_x - 4, sh_y - 2),
           (left + 2, hip_y - 6 - lift * 0.6), (left, bot_y - 4)]
    pts += tattered_hem(left, CX + 2 - sway * 0.3, bot_y, CLOAK_TEETH)
    pts += [(CX + 4, hip_y - 4), (top_x + 5, sh_y + 2)]
    poly(layer, pts, CLK_D)
    # Falten
    for i, fx in enumerate((-6, -2, 2)):
        x = CX + fx - sway * (0.7 - i * 0.15)
        thick_line(layer, (x, hip_y - 8 - lift * 0.5), (x - 1, bot_y - 3), CLK_M)


def draw_leg(layer, hip, knee, foot, back):
    col = LEA_D if back else LEA_M
    thick_line(layer, hip, knee, col, 3)
    thick_line(layer, knee, foot, col, 3)
    # Stiefel (vorne heller, damit die Schrittstellung lesbar bleibt)
    bx, by = foot
    rect(layer, bx - 2, by - 4, bx + 3, by, LEA_D if back else LEA_M)
    if not back:
        rect(layer, bx - 2, by - 4, bx + 2, by - 4, LEA_L)     # Schafthoehe
        rect(layer, bx - 1, by - 3, bx + 2, by - 3, LEA_L)     # Schnalle
    rect(layer, bx - 2, by - 1, bx + 3, by, OUT)


def draw_torso(layer, p, sh_y, hip_y):
    lean = p["lean"]
    poly(layer, [(CX - 6 + lean, sh_y), (CX + 6 + lean, sh_y),
                 (CX + 5, hip_y + 1), (CX - 5, hip_y + 1)], CLK_M)
    # Brustriemen (Ausruestung: Traenke, Knoblauch, Weihkreuze)
    thick_line(layer, (CX - 5 + lean, sh_y + 2), (CX + 5, hip_y - 4), LEA_M, 2)
    for t in (0.3, 0.6):
        x = CX - 5 + lean + (10 - lean) * t
        y = sh_y + 2 + (hip_y - 6 - sh_y) * t
        rect(layer, x, y, x + 1, y + 2, BONE)
    # Guertel
    rect(layer, CX - 5, hip_y - 2, CX + 5, hip_y, LEA_D)
    rect(layer, CX + 1, hip_y - 2, CX + 2, hip_y - 1, MET_M)


def draw_coat(layer, p, hip_y):
    """Vorderer Mantelschoss mit zerfetztem Saum."""
    sway = p["coat_sway"]
    flare = p["coat_flare"]
    bot = hip_y + 9
    left = CX - 6 - flare + sway
    right = CX + 5 + flare + sway * 0.5
    pts = [(CX - 5, hip_y - 3), (CX + 5, hip_y - 3), (right, bot - 5)]
    pts += tattered_hem(left, right, bot, COAT_TEETH)
    poly(layer, pts, CLK_M)
    # Schattenseite + Kante
    poly(layer, [(CX - 5, hip_y - 3), (CX - 1, hip_y - 3),
                 (CX - 2, bot), (left, bot - 1), (left + 1, hip_y - 1)], CLK_D)
    thick_line(layer, (right - 1, hip_y - 2), (right, bot - 5), CLK_L)


def draw_arm(layer, sh, elbow, hand, back):
    col = CLK_D if back else CLK_M
    thick_line(layer, sh, elbow, col, 3)
    thick_line(layer, elbow, hand, LEA_D if back else LEA_M, 2)
    # Armband / Schnalle
    thick_line(layer, (elbow[0], elbow[1] + 1), (elbow[0] + 1, elbow[1] + 1), MET_M)
    disc(layer, hand[0], hand[1], 1, LEA_D if back else (58, 46, 40, 255))


def draw_head(layer, p, sh_y):
    hx = CX + p["head_dx"] + p["lean"]
    hy = sh_y - 5 + p["head_dy"]
    tilt = p["hat_tilt"]
    # Kragen (hochgestellt, verdeckt das halbe Gesicht)
    poly(layer, [(hx - 7, sh_y + 3), (hx - 5, sh_y - 5), (hx - 1, sh_y - 3),
                 (hx + 4, sh_y - 4), (hx + 6, sh_y + 2), (hx, sh_y + 4)], CLK_D)
    thick_line(layer, (hx - 5, sh_y - 5), (hx - 1, sh_y - 3), CLK_M)
    # Kopf - fast komplett im Schatten, nur das Kinn bekommt Licht
    rect(layer, hx - 2, hy - 3, hx + 3, hy + 2, (46, 36, 32, 255))
    rect(layer, hx + 1, hy + 1, hx + 3, hy + 2, SKIN_D)     # Kinnpartie
    pset(layer.load(), hx + 2, hy + 1, SKIN)
    rect(layer, hx - 3, hy - 3, hx + 3, hy, (18, 14, 16, 255))   # Krempenschatten
    # Hut: breite Krempe + Krone
    by = hy - 5 + tilt
    poly(layer, [(hx - 11, by + 1 - tilt), (hx - 4, by - 2), (hx + 4, by - 2),
                 (hx + 9, by + 1 + tilt), (hx + 4, by + 2), (hx - 5, by + 2)], CLK_D)
    thick_line(layer, (hx - 10, by + 1 - tilt), (hx - 4, by - 1), CLK_M)
    poly(layer, [(hx - 4, by - 1), (hx - 3, by - 7), (hx + 3, by - 7),
                 (hx + 4, by - 1)], CLK_D)
    thick_line(layer, (hx - 3, by - 7), (hx + 3, by - 7), CLK_M)
    rect(layer, hx - 4, by - 3, hx + 4, by - 2, (16, 15, 19, 255))   # Hutband
    # Augen zuletzt - die Glut muss ueber der Krempe liegen und lesbar bleiben
    if p["eye"] > 0:
        px = layer.load()
        ec = RED_L if p["eye"] >= 1 else RED_M
        ey = by + 4
        pset(px, hx + 1, ey, ec)
        pset(px, hx + 3, ey, ec)
        pset(px, hx + 2, ey, RED_D)


# --------------------------------------------------------------------------
# Waffen (Peitsche-Sichel, geweihtes Kreuz, Trank)
# --------------------------------------------------------------------------
def draw_sickle(layer, tip, ang, size=5):
    """Sichelklinge - Halbmond, Spitze zeigt in Richtung ang."""
    a0, a1 = ang - 100, ang + 100
    pts = arc_pts(tip[0], tip[1], size, a0, a1, 12)
    for i, (x, y) in enumerate(pts):
        c = MET_L if i in (0, len(pts) - 1) else MET_M
        thick_line(layer, (x, y), (x, y), c, 2)
    inner = arc_pts(tip[0], tip[1], size - 2, a0 + 12, a1 - 12, 10)
    for x, y in inner:
        thick_line(layer, (x, y), (x, y), MET_D, 1)
    thick_line(layer, pts[0], pts[1], MET_L, 1)


def draw_chain(layer, p0, p1, p2, segs=10, glow=False):
    pts = bezier(p0, p1, p2, segs)
    px = layer.load()
    for i, (x, y) in enumerate(pts):
        c = MET_M if i % 2 == 0 else MET_D
        pset(px, x, y, c)
        if i % 3 == 0:
            pset(px, x, y - 1, MET_L)
        if glow and i % 2:
            pset(px, x + 1, y, RED_D)
    return pts


def draw_cross(layer, cx, cy, scale=1, glow=True):
    """Geweihtes Kreuz - brennt das Boese."""
    s = scale
    rect(layer, cx - 1, cy - 5 * s, cx + 1, cy + 5 * s, MET_M)
    rect(layer, cx - 4 * s, cy - 2, cx + 4 * s, cy, MET_M)
    rect(layer, cx, cy - 5 * s, cx, cy + 5 * s, MET_L)
    rect(layer, cx - 4 * s, cy - 2, cx + 4 * s, cy - 2, MET_L)
    if glow:
        px = layer.load()
        pset(px, cx, cy - 6 * s, RED_L)
        pset(px, cx - 5 * s, cy - 1, RED_D)
        pset(px, cx + 5 * s, cy - 1, RED_D)


def draw_flask(layer, x, y, tilted=False):
    rect(layer, x - 2, y - 1, x + 2, y + 3, (40, 34, 40, 255))
    rect(layer, x - 1, y - 1, x + 1, y + 3, RED_M)
    rect(layer, x - 1, y - 3, x + 1, y - 2, MET_D)
    if tilted:
        pset(layer.load(), x, y + 4, RED_L)


# --------------------------------------------------------------------------
# Figur zusammenbauen
# --------------------------------------------------------------------------
def draw_hunter(p):
    """Zeichnet die Figur (ohne Effekte) und gibt Layer + Handposition zurueck."""
    back = new_layer()      # hinter dem Koerper
    body = new_layer()
    front = new_layer()     # vor dem Koerper

    dy = p["dy"]
    hip_y = p["hip_y"] + dy
    sh_y = hip_y - 12
    hip = (CX, hip_y)
    sh_b = (CX - 3 + p["lean"], sh_y + 2)
    sh_f = (CX + 3 + p["lean"], sh_y + 2)

    knee_b = (CX + p["knee_b"][0], hip_y + p["knee_b"][1])
    foot_b = (CX + p["foot_b"][0], hip_y + p["foot_b"][1])
    knee_f = (CX + p["knee_f"][0], hip_y + p["knee_f"][1])
    foot_f = (CX + p["foot_f"][0], hip_y + p["foot_f"][1])

    el_b = (sh_b[0] + p["arm_b"][0][0], sh_b[1] + p["arm_b"][0][1])
    hd_b = (sh_b[0] + p["arm_b"][1][0], sh_b[1] + p["arm_b"][1][1])
    el_f = (sh_f[0] + p["arm_f"][0][0], sh_f[1] + p["arm_f"][0][1])
    hd_f = (sh_f[0] + p["arm_f"][1][0], sh_f[1] + p["arm_f"][1][1])

    draw_cloak(back, p, sh_y, hip_y)
    draw_leg(back, hip, knee_b, foot_b, True)
    draw_arm(back, sh_b, el_b, hd_b, True)

    draw_leg(body, hip, knee_f, foot_f, False)
    draw_torso(body, p, sh_y, hip_y)
    draw_coat(body, p, hip_y)
    draw_head(body, p, sh_y)

    draw_arm(front, sh_f, el_f, hd_f, False)

    body.alpha_composite(front)
    back.alpha_composite(body)
    return back, hd_f, hd_b, (hip_y, sh_y)


def compose(p, fx_back=None, fx_front=None, ghosts=()):
    """Ein fertiger Frame: Effekte hinten, Figur (Rim+Outline), Effekte vorn."""
    frame = new_layer()
    fig, hd_f, hd_b, (hip_y, sh_y) = draw_hunter(p)

    for dx, dy, col, alpha in ghosts:
        g = tint(fig, col, alpha)
        frame.alpha_composite(g, (0, 0)) if (dx, dy) == (0, 0) else \
            frame.alpha_composite(g.transform(
                (W, H), Image.AFFINE, (1, 0, -dx, 0, 1, -dy)))

    if fx_back:
        frame.alpha_composite(fx_back(p, hd_f, hd_b))

    rim_light(fig)
    frame.alpha_composite(outline_layer(fig))

    if fx_front:
        frame.alpha_composite(fx_front(p, hd_f, hd_b))
    return frame


# --------------------------------------------------------------------------
# Effekt-Layer pro Animation
# --------------------------------------------------------------------------
def fx_whip_rest(p, hd_f, hd_b):
    l = new_layer()
    pts = draw_chain(l, hd_f, (hd_f[0] + 5, hd_f[1] + 8), (hd_f[0] + 3, GY - 2), 8)
    draw_sickle(l, pts[-1], -60, 4)
    return l


def fx_whip_windup(p, hd_f, hd_b):
    """Ausholen: Sichel haengt hinter dem Jaeger, Kette laeuft tief nach hinten."""
    l = new_layer()
    tip = (CX - 13, GY - 14)
    pts = draw_chain(l, hd_f, (hd_f[0] - 8, hd_f[1] + 6), tip, 9)
    draw_sickle(l, pts[-1], 150, 5)
    for x, y in arc_pts(hd_f[0] - 2, hd_f[1], 11, 150, 200, 6, 0.9):
        pset(l.load(), x, y, RED_D)
    return l


def fx_whip_swing(phase):
    """phase 0..1 entlang des Peitschenbogens."""
    def f(p, hd_f, hd_b):
        l = new_layer()
        a = -200 + 250 * phase
        r = 15 + 6 * math.sin(math.pi * phase)
        cx, cy = hd_f[0] - 1, hd_f[1] - 2
        tip = (cx + math.cos(math.radians(a)) * r,
               cy + math.sin(math.radians(a)) * r * 0.85)
        # Nachzieh-Bogen (Blut-Trail), zum Schlagende hin kuerzer
        span = 70 * (1.0 - 0.6 * max(0.0, phase - 0.7) / 0.3)
        trail = arc_pts(cx, cy, r, a - span, a, 10, 0.85)
        for i, (x, y) in enumerate(trail):
            c = RED_D if i < 5 else RED_M
            thick_line(l, (x, y), (x, y), c, 1)
        trail2 = arc_pts(cx, cy, r - 2, a - span * 0.6, a - 5, 8, 0.85)
        for x, y in trail2:
            thick_line(l, (x, y), (x, y), RED_L, 1)
        draw_chain(l, hd_f, ((hd_f[0] + tip[0]) / 2 + 2, (hd_f[1] + tip[1]) / 2 - 3),
                   tip, 9, glow=True)
        draw_sickle(l, tip, a + 90, 5)
        return l
    return f


def fx_cross_spin(phase, arm=True):
    """Kreuz-Wirbel: Klinge kreist um den Jaeger, Schockwelle laeuft am Boden."""
    def f(p, hd_f, hd_b):
        l = new_layer()
        gy = GY - 3 + p["dy"]
        r = 5 + 19 * min(1.0, phase * 1.4)
        col = RED_M if phase < 0.75 else RED_D
        if phase > 0.05:
            ring(l, CX, gy, r, col, 1, ry=max(2, r * 0.34))
            ring(l, CX, gy, max(2, r - 4), RED_D, 1, ry=max(1, (r - 4) * 0.34))
            for i in range(6):
                a = math.radians(phase * 360 + i * 60)
                pset(l.load(), CX + math.cos(a) * r, gy + math.sin(a) * r * 0.34, RED_L)
        if arm:
            # Das Kreuz kreist auf Brusthoehe und bleibt an der Hand angebunden
            a = math.radians(-90 + phase * 360)
            cxp = CX + 1 + math.cos(a) * 11
            cyp = p["hip_y"] + p["dy"] - 8 + math.sin(a) * 4
            thick_line(l, hd_f, (cxp, cyp), LEA_M, 1)
            draw_cross(l, int(cxp), int(cyp), 1)
        return l
    return f


def fx_dash(streaks, dust):
    def f(p, hd_f, hd_b):
        l = new_layer()
        for y, x0, x1, c in streaks:
            thick_line(l, (x0, y + p["dy"]), (x1, y + p["dy"]), c, 1)
        for x, y, c in dust:
            pset(l.load(), x, GY - y, c)
        return l
    return f


def fx_potion(phase):
    """Trank wird ueber dem Kopf angesetzt (siehe Konzept: TRANK NUTZEN)."""
    def f(p, hd_f, hd_b):
        l = new_layer()
        draw_flask(l, hd_f[0], hd_f[1] - 1, tilted=phase > 0.4)
        if phase > 0.55:
            px = l.load()
            for i in range(5):
                pset(px, hd_f[0] - 1 + (i % 2), hd_f[1] + 3 + i, RED_L if i % 2 else RED_M)
            r = 9 + int(phase * 5)
            ring(l, CX + 1, GY - 3 + p["dy"], r, RED_D, 1, ry=max(2, r * 0.34))
        return l
    return f


def fx_moon(phase):
    """Ultimate - Blutmond."""
    def f(p, hd_f, hd_b):
        l = new_layer()
        r = 10 + 14 * min(1.0, phase * 1.3)
        disc(l, CX + 1, 24, r, (52, 8, 12, 255))
        disc(l, CX + 1, 24, max(1, r - 3), (96, 14, 16, 255))
        if phase > 0.5:
            disc(l, CX + 1, 24, max(1, r - 7), (150, 22, 24, 255))
        ring(l, CX + 1, 24, r, RED_M, 1)
        # Fledermaeuse
        px = l.load()
        for i, (bx, by) in enumerate(((10, 14), (48, 20), (18, 28), (44, 34))):
            if phase * 4 > i:
                o = int(math.sin(phase * 8 + i) * 1.5)
                pset(px, bx, by + o, OUT)
                pset(px, bx - 1, by - 1 + o, OUT)
                pset(px, bx + 1, by - 1 + o, OUT)
        return l
    return f


def fx_moon_front(phase):
    def f(p, hd_f, hd_b):
        l = new_layer()
        if phase > 0.45:
            pts = draw_chain(l, hd_f, (hd_f[0] + 8, hd_f[1] - 8),
                             (hd_f[0] + 12, hd_f[1] - 14), 8, glow=True)
            draw_sickle(l, pts[-1], -30, 5)
            for x, y in arc_pts(CX, GY - 2, 12 + phase * 6, 200, 340, 12, 0.35):
                pset(l.load(), x, y, RED_M)
        return l
    return f


# --------------------------------------------------------------------------
# Animationen
# --------------------------------------------------------------------------
def anim_idle():
    frames = []
    for i, (b, sway) in enumerate(((0, 0), (-1, 1), (0, 1), (1, 0))):
        p = pose(dy=b, coat_sway=sway, cloak_sway=sway,
                 arm_f=((5, 5 - b), (8, 9 - b)), eye=1.0 if i != 2 else 0.7,
                 knee_b=(-4, 8), foot_b=(-7, 22), knee_f=(3, 8), foot_f=(5, 22))
        frames.append(compose(p, fx_front=fx_whip_rest))
    return frames, 6, True


def anim_run():
    frames = []
    cyc = [  # (dy, front foot, back foot, lean)
        (0, (9, 20), (-8, 22), 2), (-1, (7, 16), (-4, 22), 2),
        (0, (3, 22), (2, 20), 3), (0, (-4, 22), (8, 20), 2),
        (-1, (-6, 22), (6, 16), 2), (0, (-8, 22), (9, 21), 3),
    ]
    for i, (dy, ff, bf, lean) in enumerate(cyc):
        p = pose(dy=dy, lean=lean,
                 foot_f=ff, knee_f=(ff[0] // 2 + 2, 9),
                 foot_b=bf, knee_b=(bf[0] // 2 - 1, 9),
                 coat_sway=3, cloak_sway=4 + (i % 2), coat_flare=1,
                 arm_f=((5, 4), (7, 8)), arm_b=((-6, 4), (-8, 7)),
                 head_dx=2)
        frames.append(compose(p, fx_front=fx_whip_rest))
    return frames, 12, True


def anim_dash():
    frames = []
    # 0 Ansatz / Ducken
    frames.append(compose(pose(dy=3, lean=4, hip_y=36, coat_sway=-2, cloak_sway=-3,
                               knee_f=(4, 7), foot_f=(7, 19), knee_b=(-4, 7),
                               foot_b=(-7, 19), arm_f=((4, 6), (6, 10))),
                          fx_front=fx_whip_rest))
    # 1-3 Schub mit Nachbildern
    for i, (dy, lean) in enumerate(((1, 7), (0, 8), (1, 6))):
        streaks = [(28 + k * 5, 2 + i, 16 - i * 2, RED_D if k % 2 else CLK_L)
                   for k in range(4)]
        dust = [(12 + i * 3, 1, CLK_L), (16 + i * 3, 2, CLK_M), (9 + i * 2, 0, RED_D)]
        p = pose(dy=dy, lean=lean, coat_sway=6, cloak_sway=9, cloak_lift=5,
                 coat_flare=2, knee_f=(5, 6), foot_f=(9, 18),
                 knee_b=(-5, 9), foot_b=(-9, 20),
                 arm_f=((6, 3), (9, 6)), arm_b=((-7, 5), (-10, 8)),
                 head_dx=3, hat_tilt=-1)
        ghosts = [(-5 - i * 2, 0, RED_D, 90), (-10 - i * 3, 0, (20, 6, 10), 60)]
        frames.append(compose(p, fx_back=fx_dash(streaks, dust), ghosts=ghosts))
    # 4 Landung / Ausklang
    frames.append(compose(pose(dy=2, lean=3, coat_sway=3, cloak_sway=4,
                               knee_f=(4, 8), foot_f=(8, 20), knee_b=(-4, 8),
                               foot_b=(-6, 21), arm_f=((5, 5), (8, 9))),
                          fx_front=fx_whip_rest,
                          ghosts=[(-6, 0, RED_D, 45)]))
    return frames, 16, False


def anim_attack_whip():
    frames = []
    # Ausholen
    frames.append(compose(pose(dy=1, lean=-3, coat_sway=-3, cloak_sway=-4,
                               arm_f=((-2, 2), (-5, -2)), head_dx=0, hat_tilt=1),
                          fx_back=fx_whip_windup))
    # Schlagbogen
    for i, ph in enumerate((0.28, 0.5, 0.72)):
        p = pose(dy=0, lean=2 + i, coat_sway=2 + i, cloak_sway=3 + i, coat_flare=1,
                 arm_f=((4 + i, 1), (7 + i, 0)), arm_b=((-5, 4), (-7, 7)),
                 knee_f=(4, 8), foot_f=(8, 21), knee_b=(-4, 8), foot_b=(-7, 22),
                 head_dx=2)
        frames.append(compose(p, fx_front=fx_whip_swing(ph)))
    # Ausklang
    frames.append(compose(pose(dy=0, lean=3, coat_sway=3, cloak_sway=3,
                               arm_f=((6, 4), (9, 7))),
                          fx_front=fx_whip_swing(0.92)))
    frames.append(compose(pose(dy=1, lean=1, coat_sway=1, cloak_sway=1,
                               arm_f=((5, 5), (8, 9))),
                          fx_front=fx_whip_rest))
    return frames, 14, False


def anim_attack_cross():
    frames = []
    frames.append(compose(pose(dy=1, lean=-2, coat_sway=-2, cloak_sway=-3,
                               arm_f=((2, -2), (4, -6))),
                          fx_front=fx_cross_spin(0.0)))
    for i, ph in enumerate((0.2, 0.45, 0.7, 0.9)):
        p = pose(dy=-1 if i in (1, 2) else 0, lean=0,
                 coat_sway=0, coat_flare=2 + i % 2, cloak_sway=0, cloak_lift=3,
                 knee_f=(4, 8), foot_f=(6, 22), knee_b=(-4, 8), foot_b=(-6, 22),
                 arm_f=((5, -1), (8, -4)), arm_b=((-5, -1), (-8, -4)),
                 head_dx=1, eye=1.0)
        frames.append(compose(p, fx_back=fx_cross_spin(ph, arm=False),
                              fx_front=fx_cross_spin(ph)))
    frames.append(compose(pose(dy=1, arm_f=((5, 5), (8, 9))), fx_front=fx_whip_rest))
    return frames, 14, False


def anim_potion():
    frames = []
    for i, (ph, ay) in enumerate(((0.0, 2), (0.35, -4), (0.65, -7), (0.95, -4))):
        p = pose(dy=1 if i == 0 else 0, lean=-1,
                 arm_f=((2, ay), (3, ay - 5)), head_dy=-1 if i > 1 else 0,
                 hat_tilt=1 if i > 1 else 0, eye=0.7)
        frames.append(compose(p, fx_front=fx_potion(ph)))
    return frames, 8, False


def anim_hurt():
    frames = []
    for i, (lean, dy) in enumerate(((-4, 1), (-2, 0))):
        p = pose(dy=dy, lean=lean, coat_sway=-3, cloak_sway=-4, hat_tilt=1,
                 arm_f=((3, 2), (4, -2)), eye=1.0, head_dx=-1)
        f = compose(p, fx_front=fx_whip_rest)
        # Treffer-Blitz
        fl = new_layer()
        px = fl.load()
        for x, y in ((26, 26), (33, 24), (29, 31), (36, 30), (24, 33)):
            pset(px, x, y, RED_L if i == 0 else RED_M)
        f.alpha_composite(fl)
        frames.append(f)
    return frames, 10, False


def anim_death():
    """Auf die Knie -> Zusammensacken. Fuesse bleiben auf der Bodenlinie."""
    frames = []
    #     dy  lean  eye  alpha
    specs = [(2, -4, 0.7, 255), (7, -3, 0.4, 255),
             (13, -2, 0.2, 235), (17, 0, 0.0, 190)]
    for i, (dy, lean, eye, alpha) in enumerate(specs):
        base = 36 + dy
        p = pose(dy=dy, lean=lean, hip_y=36, coat_sway=-3, cloak_sway=-5,
                 knee_f=(6, 5), foot_f=(4, GY - base), knee_b=(-6, 5),
                 foot_b=(-6, GY - base), arm_f=((5, 5), (8, GY - base - 2)),
                 arm_b=((-5, 5), (-8, GY - base - 2)),
                 hat_tilt=1 + i // 2, eye=eye, head_dy=1 + i // 2, head_dx=0)
        f = compose(p)
        fl = new_layer()
        for x, y in ((21, GY - 1), (25, GY), (35, GY - 1), (40, GY), (28, GY)):
            pset(fl.load(), x, y, RED_D)
        f.alpha_composite(fl)
        if alpha < 255:
            f.putalpha(f.getchannel("A").point(lambda v: v * alpha // 255))
        frames.append(f)
    return frames, 8, False


def anim_ultimate():
    frames = []
    for i, ph in enumerate((0.1, 0.3, 0.5, 0.7, 0.85, 1.0)):
        p = pose(dy=-1 if i > 2 else 0, lean=1,
                 coat_sway=int(3 * ph), coat_flare=int(3 * ph),
                 cloak_sway=int(5 * ph), cloak_lift=int(6 * ph),
                 arm_f=((5, -3 - int(4 * ph)), (8, -6 - int(6 * ph))),
                 arm_b=((-5, 2), (-7, 4)), hat_tilt=-1 if ph > 0.5 else 0,
                 head_dy=-1 if ph > 0.6 else 0, eye=1.0)
        frames.append(compose(p, fx_back=fx_moon(ph), fx_front=fx_moon_front(ph)))
    return frames, 10, False


ANIMS = [
    ("idle", anim_idle),
    ("run", anim_run),
    ("dash", anim_dash),
    ("attack_whip", anim_attack_whip),
    ("attack_cross", anim_attack_cross),
    ("potion", anim_potion),
    ("hurt", anim_hurt),
    ("death", anim_death),
    ("ultimate", anim_ultimate),
]


# --------------------------------------------------------------------------
PREVIEW = """<!doctype html><meta charset="utf-8"><title>Nightbane - Sprite Preview</title>
<style>
 body{background:#141216;color:#c9c4bd;font:14px/1.5 system-ui,sans-serif;margin:0;padding:24px}
 h1{font:600 20px/1 system-ui;color:#e8e2d8;margin:0 0 4px}
 p.sub{color:#7d7788;margin:0 0 20px}
 .grid{display:flex;flex-wrap:wrap;gap:14px}
 .card{background:#1d1a20;border:1px solid #2b2730;border-radius:8px;padding:10px;width:180px}
 .name{font:600 12px/1 monospace;color:#d8534a;letter-spacing:.05em}
 .meta{font:11px/1 monospace;color:#6c6672;margin-top:4px}
 .view{margin:8px 0;background:linear-gradient(#221f27,#17151b);border-radius:4px;
   image-rendering:pixelated;background-repeat:no-repeat;overflow:hidden}
 button{background:#2b2730;color:#c9c4bd;border:1px solid #3a3542;border-radius:4px;
   padding:4px 8px;font:11px monospace;cursor:pointer}
</style>
<h1>Nightbane &mdash; Jaeger</h1>
<p class="sub">64&times;64 pro Frame, Blickrichtung rechts. Klick = einmal abspielen.</p>
<div class="grid" id="g"></div>
<script>
const SHEET="data:image/png;base64,__B64__";
const META=__META__;
const S=2.5, FW=META.frameWidth, FH=META.frameHeight, COLS=META.columns;
const g=document.getElementById("g");
for(const [name,a] of Object.entries(META.animations)){
  const card=document.createElement("div"); card.className="card";
  card.innerHTML=`<div class="name">${name}</div>
    <div class="view"></div>
    <div class="meta">${a.frameCount} f @ ${a.fps} fps${a.loop?" loop":""}</div>`;
  const v=card.querySelector(".view");
  v.style.backgroundImage=`url(${SHEET})`;
  v.style.backgroundSize=`${COLS*FW*S}px auto`;
  v.style.width=`${FW*S}px`; v.style.height=`${FH*S}px`;
  let i=0,timer=null;
  const show=()=>{const c=a.frames[i]%COLS, r=a.row;
    v.style.backgroundPosition=`${-c*FW*S}px ${-r*FH*S}px`;};
  const play=()=>{clearInterval(timer); i=0; show();
    timer=setInterval(()=>{i++;
      if(i>=a.frameCount){ if(a.loop){i=0;} else {i=a.frameCount-1; clearInterval(timer);} }
      show();},1000/a.fps);};
  card.onclick=play; g.appendChild(card); play();
}
</script>"""


def write_preview(sheet_path, meta):
    import base64
    with open(sheet_path, "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()
    html = PREVIEW.replace("__B64__", b64).replace("__META__", json.dumps(meta))
    with open(os.path.join(OUTDIR, "preview.html"), "w", encoding="utf-8") as fh:
        fh.write(html)


def main():
    os.makedirs(os.path.join(OUTDIR, "strips"), exist_ok=True)
    built = [(name, *fn()) for name, fn in ANIMS]
    cols = max(len(f) for _, f, _, _ in built)
    rows = len(built)

    sheet = Image.new("RGBA", (cols * W, rows * H), (0, 0, 0, 0))
    meta = {"image": "nightbane_hunter.png", "frameWidth": W, "frameHeight": H,
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

    sheet.save(os.path.join(OUTDIR, "nightbane_hunter.png"))
    Image.open(os.path.join(OUTDIR, "nightbane_hunter.png")).resize(
        (sheet.width * 4, sheet.height * 4), Image.NEAREST).save(
        os.path.join(OUTDIR, "nightbane_hunter@4x.png"))
    with open(os.path.join(OUTDIR, "nightbane_hunter.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
    write_preview(os.path.join(OUTDIR, "nightbane_hunter.png"), meta)

    print(f"sheet {sheet.width}x{sheet.height}  ({rows} Animationen, {cols} Spalten)")
    for name, frames, fps, loop in built:
        print(f"  {name:<14} {len(frames)} Frames @ {fps} fps  loop={loop}")


if __name__ == "__main__":
    main()

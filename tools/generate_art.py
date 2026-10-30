"""Generates Gunarok's placeholder stage and UI art (original, team-owned).

Run from the project root:  python tools/generate_art.py
Needs Pillow. Everything is drawn from simple shapes, so no outside
images are used (GDD Section 10.2).
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
STAGES = ROOT / "assets" / "sprites" / "stages"
UI = ROOT / "assets" / "sprites" / "ui"
W, H = 1600, 720
SS = 2  # supersampling factor
FLOOR_Y = 620


def canvas(w=W, h=H, color=(0, 0, 0, 0)):
    img = Image.new("RGBA", (w * SS, h * SS), color)
    return img, ImageDraw.Draw(img)


def s(v):
    """Scale a coordinate or a tuple of coordinates by the supersampling factor."""
    if isinstance(v, (list, tuple)):
        return type(v)(s(x) for x in v)
    return v * SS


def finish(img, path, w=W, h=H):
    img = img.resize((w, h), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print("wrote", path.relative_to(ROOT))


def gradient(draw, top, bottom, y0, y1, x0=0, x1=W):
    for y in range(s(y0), s(y1)):
        t = (y - s(y0)) / max(1, s(y1) - s(y0))
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        draw.line([(s(x0), y), (s(x1), y)], fill=c)


def layer_of(img):
    """Translucent shapes must be drawn on their own layer and composited,
    because ImageDraw replaces pixels instead of blending them."""
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    return lay, ImageDraw.Draw(lay)


def lerp_color(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# --------------------------------------------------------------------------
# Stage 1: Ancient Arena (M1, M2)
# --------------------------------------------------------------------------
def ancient_arena():
    rnd = random.Random(1)
    img, d = canvas()
    gradient(d, (58, 38, 92), (250, 168, 92), 0, 330)
    gradient(d, (250, 168, 92), (255, 205, 140), 330, 470)
    d.ellipse(s((1120, 150, 1260, 290)), fill=(255, 226, 160, 255))

    # Colosseum stands: three tiers of arches with a crowd on top of each
    tiers = [(180, 270, (150, 118, 88)), (270, 360, (165, 132, 98)), (360, 445, (178, 145, 108))]
    for top, bottom, col in tiers:
        d.rectangle(s((0, top, W, bottom)), fill=col + (255,))
        d.line(s([(0, top), (W, top)]), fill=(110, 84, 60, 255), width=s(4))
        for x in range(10, W, 70):
            aw = 40
            d.rectangle(s((x, top + 26, x + aw, bottom - 4)), fill=(60, 40, 34, 255))
            d.ellipse(s((x, top + 10, x + aw, top + 44)), fill=(60, 40, 34, 255))
        # crowd silhouettes
        for x in range(0, W, 13):
            hx = x + rnd.randint(-3, 3)
            hy = top - rnd.randint(8, 16)
            shade = rnd.choice([(70, 40, 70), (85, 52, 78), (60, 36, 60)])
            d.ellipse(s((hx - 9, hy + 6, hx + 9, top + 4)), fill=shade + (255,))
            d.ellipse(s((hx - 5, hy - 6, hx + 5, hy + 5)), fill=shade + (255,))
            if rnd.random() < 0.12:
                d.line(s([(hx + 4, hy), (hx + 10, hy - 16)]), fill=shade + (255,), width=s(3))

    # Arena back wall made of stone blocks
    d.rectangle(s((0, 445, W, FLOOR_Y)), fill=(206, 176, 138, 255))
    for row, y in enumerate(range(445, FLOOR_Y, 30)):
        d.line(s([(0, y), (W, y)]), fill=(160, 130, 98, 255), width=s(2))
        off = 0 if row % 2 == 0 else 40
        for x in range(off, W, 80):
            d.line(s([(x, y), (x, min(y + 30, FLOOR_Y))]), fill=(160, 130, 98, 255), width=s(2))

    # Banners from many eras (GDD 7.2): different colors and simple emblems
    banners = [
        ((170, 30, 30), (240, 200, 90), "lambda"),
        ((110, 30, 90), (240, 200, 90), "wings"),
        ((30, 30, 34), (235, 205, 60), "raven"),
        ((240, 238, 228), (200, 30, 40), "disc"),
        ((200, 40, 40), (250, 210, 60), "sun"),
        ((40, 70, 140), (235, 235, 245), "cross"),
        ((40, 90, 60), (230, 220, 180), "diamond"),
    ]
    xs = [150, 360, 570, 800, 1030, 1240, 1450]
    for (bg, fg, emblem), x in zip(banners, xs):
        top, bottom, w2 = 452, 590, 34
        d.rectangle(s((x - w2 - 6, top - 6, x + w2 + 6, top + 2)), fill=(90, 60, 30, 255))
        d.polygon(s([(x - w2, top), (x + w2, top), (x + w2, bottom), (x, bottom - 26), (x - w2, bottom)]), fill=bg + (255,))
        cy = top + 52
        if emblem == "lambda":
            d.line(s([(x - 16, cy + 22), (x, cy - 20), (x + 16, cy + 22)]), fill=fg + (255,), width=s(6))
        elif emblem == "wings":
            d.polygon(s([(x, cy - 6), (x - 26, cy - 22), (x - 14, cy + 6), (x, cy + 18), (x + 14, cy + 6), (x + 26, cy - 22)]), fill=fg + (255,))
        elif emblem == "raven":
            d.ellipse(s((x - 14, cy - 10, x + 10, cy + 12)), fill=fg + (255,))
            d.polygon(s([(x + 8, cy - 4), (x + 22, cy), (x + 8, cy + 4)]), fill=fg + (255,))
            d.polygon(s([(x - 12, cy), (x - 28, cy - 18), (x - 6, cy - 6)]), fill=fg + (255,))
        elif emblem == "disc":
            d.ellipse(s((x - 20, cy - 20, x + 20, cy + 20)), outline=fg + (255,), width=s(5))
            d.polygon(s([(x, cy - 11), (x + 10, cy + 7), (x - 10, cy + 7)]), fill=fg + (255,))
        elif emblem == "sun":
            for k in range(12):
                a = k * math.tau / 12
                d.line(s([(x, cy), (x + math.cos(a) * 26, cy + math.sin(a) * 26)]), fill=fg + (255,), width=s(3))
            d.ellipse(s((x - 12, cy - 12, x + 12, cy + 12)), fill=fg + (255,))
        elif emblem == "cross":
            for k in range(3):
                yy = cy - 18 + k * 18
                d.line(s([(x - 20, yy), (x, yy + 14), (x + 20, yy)]), fill=fg + (255,), width=s(5))
        elif emblem == "diamond":
            d.polygon(s([(x, cy - 22), (x + 16, cy), (x, cy + 22), (x - 16, cy)]), fill=fg + (255,))

    # Shields hung on the wall between banners
    shields = [(255, "round_bronze"), (465, "scutum"), (685, "round_painted"), (915, "round_hide"), (1135, "round_bronze"), (1345, "scutum")]
    for x, kind in shields:
        cy = 520
        if kind == "round_bronze":
            d.ellipse(s((x - 26, cy - 26, x + 26, cy + 26)), fill=(176, 126, 50, 255), outline=(110, 70, 26, 255), width=s(4))
            d.line(s([(x - 12, cy + 14), (x, cy - 14), (x + 12, cy + 14)]), fill=(120, 30, 20, 255), width=s(4))
        elif kind == "scutum":
            d.rounded_rectangle(s((x - 20, cy - 32, x + 20, cy + 32)), radius=s(6), fill=(160, 32, 32, 255), outline=(220, 180, 70, 255), width=s(3))
            d.ellipse(s((x - 7, cy - 7, x + 7, cy + 7)), fill=(220, 180, 70, 255))
        elif kind == "round_painted":
            d.ellipse(s((x - 26, cy - 26, x + 26, cy + 26)), fill=(220, 210, 180, 255), outline=(70, 50, 30, 255), width=s(4))
            for k in range(4):
                a = k * math.tau / 4
                d.pieslice(s((x - 24, cy - 24, x + 24, cy + 24)), math.degrees(a), math.degrees(a) + 45, fill=(40, 70, 130, 255))
            d.ellipse(s((x - 7, cy - 7, x + 7, cy + 7)), fill=(120, 120, 130, 255))
        elif kind == "round_hide":
            d.ellipse(s((x - 24, cy - 24, x + 24, cy + 24)), fill=(205, 175, 130, 255), outline=(110, 80, 50, 255), width=s(4))
            d.line(s([(x - 16, cy), (x + 16, cy)]), fill=(150, 60, 40, 255), width=s(3))
            d.line(s([(x, cy - 16), (x, cy + 16)]), fill=(150, 60, 40, 255), width=s(3))

    # Sand floor
    gradient(d, (222, 190, 140), (196, 160, 110), FLOOR_Y, H)
    d.line(s([(0, FLOOR_Y), (W, FLOOR_Y)]), fill=(150, 116, 80, 255), width=s(4))
    for _ in range(1400):
        x, y = rnd.randint(0, W), rnd.randint(FLOOR_Y + 4, H)
        c = rnd.choice([(180, 146, 100), (236, 206, 160), (170, 136, 92)])
        d.ellipse(s((x, y, x + 2, y + 2)), fill=c + (255,))

    # Boundary pillars mark the arena walls (GDD 5.4)
    for x0 in (0, W - 60):
        d.rectangle(s((x0, 120, x0 + 60, H)), fill=(214, 196, 166, 255), outline=(130, 104, 74, 255), width=s(4))
        for fx in range(x0 + 10, x0 + 60, 12):
            d.line(s([(fx, 150), (fx, FLOOR_Y + 60)]), fill=(170, 150, 120, 255), width=s(3))
        d.rectangle(s((x0 - 8, 100, x0 + 68, 130)), fill=(196, 176, 146, 255), outline=(130, 104, 74, 255), width=s(4))
    finish(img, STAGES / "stage_1_ancient_arena.png")


# --------------------------------------------------------------------------
# Stage 2: Battlefield (M3 to M5). Sky is its own sprite so it can darken.
# --------------------------------------------------------------------------
def battlefield():
    rnd = random.Random(2)
    sky, d = canvas()
    gradient(d, (88, 92, 112), (214, 140, 92), 0, 470)
    gradient(d, (214, 140, 92), (226, 160, 110), 470, H)
    d.ellipse(s((300, 210, 400, 310)), fill=(255, 214, 160, 255))
    lay, ld = layer_of(sky)
    for _ in range(26):
        x, y, r = rnd.randint(0, W), rnd.randint(30, 380), rnd.randint(30, 80)
        ld.ellipse(s((x - r * 2, y - r * 0.6, x + r * 2, y + r * 0.6)), fill=(96, 86, 92, 90))
    lay = lay.filter(ImageFilter.GaussianBlur(s(10)))
    sky.alpha_composite(lay)
    finish(sky, STAGES / "stage_2_battlefield_sky.png")

    img, d = canvas()
    # distant hills
    pts = [(0, H)] + [(x, 410 + 40 * math.sin(x / 170.0) + 18 * math.sin(x / 53.0)) for x in range(0, W + 1, 20)] + [(W, H)]
    d.polygon(s(pts), fill=(84, 70, 70, 255))
    pts = [(0, H)] + [(x, 470 + 30 * math.sin(x / 120.0 + 2) + 10 * math.sin(x / 37.0)) for x in range(0, W + 1, 20)] + [(W, H)]
    d.polygon(s(pts), fill=(70, 56, 50, 255))
    # smoke columns
    lay, ld = layer_of(img)
    for x in (230, 760, 1290):
        for k in range(10):
            r = 22 + k * 7
            y = 470 - k * 34
            ld.ellipse(s((x - r + k * 6, y - r, x + r + k * 6, y + r)), fill=(58, 52, 54, 150 - k * 12))
    lay = lay.filter(ImageFilter.GaussianBlur(s(5)))
    img.alpha_composite(lay)
    # scorched ground
    d.rectangle(s((0, 540, W, H)), fill=(78, 60, 48, 255))
    gradient(d, (92, 72, 56), (60, 46, 38), 540, FLOOR_Y)
    gradient(d, (64, 48, 40), (44, 34, 30), FLOOR_Y, H)
    d.line(s([(0, FLOOR_Y), (W, FLOOR_Y)]), fill=(30, 22, 20, 255), width=s(4))
    for _ in range(18):
        x, y = rnd.randint(80, W - 80), rnd.randint(560, 610)
        d.ellipse(s((x - 46, y - 8, x + 46, y + 10)), fill=(46, 34, 30, 255))
    for _ in range(260):
        x, y = rnd.randint(0, W), rnd.randint(FLOOR_Y + 6, H)
        d.ellipse(s((x, y, x + 3, y + 3)), fill=rnd.choice([(255, 140, 40, 255), (200, 80, 30, 255), (110, 90, 80, 255)]))

    # Weapons of fallen challengers stuck in the dirt (GDD 7.2)
    def spear(x, y, ang):
        dx, dy = math.cos(ang), math.sin(ang)
        d.line(s([(x, y), (x + dx * 150, y + dy * 150)]), fill=(110, 74, 40, 255), width=s(6))
        tip = (x + dx * 150, y + dy * 150)
        px, py = -dy, dx
        d.polygon(s([(tip[0] + dx * 28, tip[1] + dy * 28), (tip[0] + px * 8, tip[1] + py * 8), (tip[0] - px * 8, tip[1] - py * 8)]), fill=(180, 180, 186, 255))

    def katana(x, y, ang):
        dx, dy = math.cos(ang), math.sin(ang)
        d.line(s([(x, y), (x + dx * 120, y + dy * 120)]), fill=(214, 216, 224, 255), width=s(5))
        hx, hy = x + dx * 120, y + dy * 120
        d.ellipse(s((hx - 8, hy - 8, hx + 8, hy + 8)), fill=(60, 50, 40, 255))
        d.line(s([(hx, hy), (hx + dx * 44, hy + dy * 44)]), fill=(40, 30, 60, 255), width=s(7))

    def rifle(x, y, ang):
        dx, dy = math.cos(ang), math.sin(ang)
        d.line(s([(x, y), (x + dx * 150, y + dy * 150)]), fill=(36, 36, 40, 255), width=s(5))
        d.line(s([(x + dx * 60, y + dy * 60), (x + dx * 130, y + dy * 130)]), fill=(110, 70, 40, 255), width=s(9))
        px, py = -dy, dx
        d.polygon(s([(x + dx * 130 + px * 4, y + dy * 130 + py * 4), (x + dx * 175 + px * 12, y + dy * 175 + py * 12),
                     (x + dx * 182 - px * 2, y + dy * 182 - py * 2), (x + dx * 130 - px * 4, y + dy * 130 - py * 4)]), fill=(110, 70, 40, 255))

    spear(330, 600, -1.2)
    katana(560, 606, -1.9)
    rifle(1050, 602, -1.35)
    spear(1380, 598, -2.0)
    katana(140, 604, -1.4)
    # broken shields half buried
    for x, col in ((820, (150, 40, 40)), (1210, (176, 126, 50))):
        d.pieslice(s((x - 34, 570, x + 34, 638)), 180, 360, fill=col + (255,), outline=(40, 30, 26, 255), width=s(4))
        d.line(s([(x - 6, 572), (x + 8, 600)]), fill=(40, 30, 26, 255), width=s(3))
    # torn banners on poles
    for x, col in ((700, (130, 30, 30)), (1500, (40, 60, 110)), (980, (200, 180, 60))):
        d.line(s([(x, 600), (x, 380)]), fill=(80, 56, 36, 255), width=s(6))
        d.polygon(s([(x, 384), (x + 70, 392), (x + 52, 420), (x + 74, 446), (x, 440)]), fill=col + (255,))
    # Boundary palisades (GDD 5.4)
    for x0, direction in ((0, 1), (W - 64, -1)):
        for k in range(4):
            lx = x0 + k * 16
            d.rectangle(s((lx, 200, lx + 14, H)), fill=(100, 70, 44, 255), outline=(50, 34, 22, 255), width=s(2))
            d.polygon(s([(lx, 200), (lx + 7, 170), (lx + 14, 200)]), fill=(100, 70, 44, 255), outline=(50, 34, 22, 255))
        d.rectangle(s((x0, 330, x0 + 64, 344)), fill=(70, 48, 30, 255))
        d.rectangle(s((x0, 520, x0 + 64, 534)), fill=(70, 48, 30, 255))
    finish(img, STAGES / "stage_2_battlefield.png")


# --------------------------------------------------------------------------
# Stage 3: Mythic Summit (M6, Zeus)
# --------------------------------------------------------------------------
def column(d, x, top, bottom, width, color=(238, 234, 226), shade=(196, 190, 182)):
    d.rectangle(s((x, top, x + width, bottom)), fill=color + (255,))
    for fx in range(int(x + 6), int(x + width - 4), 10):
        d.line(s([(fx, top + 20), (fx, bottom - 10)]), fill=shade + (255,), width=s(3))
    d.rectangle(s((x - 10, top - 22, x + width + 10, top)), fill=color + (255,), outline=shade + (255,), width=s(3))
    d.rectangle(s((x - 10, bottom - 4, x + width + 10, bottom + 14)), fill=color + (255,), outline=shade + (255,), width=s(3))


def statue(d, cx, base_y, height, holding):
    marble, shade = (232, 228, 220, 255), (186, 180, 172, 255)
    head_r = height * 0.06
    body_top = base_y - height + head_r * 2.6
    d.rectangle(s((cx - 70, base_y, cx + 70, base_y + 40)), fill=marble, outline=shade, width=s(3))
    d.polygon(s([(cx - height * 0.16, body_top + 30), (cx + height * 0.16, body_top + 30), (cx + height * 0.22, base_y), (cx - height * 0.22, base_y)]), fill=marble, outline=shade)
    for k in range(5):
        fx = cx - height * 0.14 + k * height * 0.07
        d.line(s([(fx, body_top + 60), (fx + (k - 2) * 6, base_y - 6)]), fill=shade, width=s(3))
    d.ellipse(s((cx - head_r, body_top - head_r * 2.2, cx + head_r, body_top - head_r * 0.2)), fill=marble, outline=shade, width=s(2))
    d.polygon(s([(cx - head_r * 0.9, body_top - head_r * 0.9), (cx + head_r * 0.9, body_top - head_r * 0.9), (cx, body_top + head_r * 1.4)]), fill=marble, outline=shade)
    arm_x = cx + height * 0.2
    d.line(s([(cx + height * 0.12, body_top + 40), (arm_x, body_top + 10)]), fill=marble, width=s(int(height * 0.05)))
    if holding == "trident":
        d.line(s([(arm_x, body_top - 120), (arm_x, base_y - 10)]), fill=shade, width=s(6))
        for off in (-18, 0, 18):
            d.line(s([(arm_x + off, body_top - 150), (arm_x + off, body_top - 110)]), fill=shade, width=s(5))
        d.line(s([(arm_x - 18, body_top - 110), (arm_x + 18, body_top - 110)]), fill=shade, width=s(5))
    elif holding == "spear":
        d.line(s([(arm_x, body_top - 140), (arm_x, base_y - 10)]), fill=shade, width=s(6))
        d.polygon(s([(arm_x, body_top - 176), (arm_x - 10, body_top - 140), (arm_x + 10, body_top - 140)]), fill=shade)


def mythic_summit():
    rnd = random.Random(3)
    img, d = canvas()
    gradient(d, (34, 26, 84), (150, 110, 190), 0, 300)
    gradient(d, (150, 110, 190), (255, 206, 150), 300, 560)
    gradient(d, (255, 206, 150), (255, 230, 200), 560, H)
    for _ in range(60):
        x, y = rnd.randint(0, W), rnd.randint(0, 220)
        d.ellipse(s((x, y, x + 3, y + 3)), fill=(255, 255, 240, 255))
    # distant lightning
    for x0 in (300, 1250):
        pts, x, y = [], x0, 40
        while y < 330:
            pts.append((x, y))
            x += rnd.randint(-30, 30)
            y += rnd.randint(25, 45)
        d.line(s(pts), fill=(255, 250, 200, 230), width=s(5))
        d.line(s(pts), fill=(255, 255, 255, 255), width=s(2))
    # far clouds and temple
    lay, ld = layer_of(img)
    for _ in range(40):
        x, y, r = rnd.randint(-50, W + 50), rnd.randint(470, 600), rnd.randint(40, 90)
        ld.ellipse(s((x - r * 1.6, y - r * 0.6, x + r * 1.6, y + r * 0.6)), fill=(255, 238, 230, 200))
    lay = lay.filter(ImageFilter.GaussianBlur(s(4)))
    img.alpha_composite(lay)
    d.polygon(s([(560, 300), (800, 220), (1040, 300)]), fill=(240, 232, 214, 255), outline=(200, 186, 160, 255))
    for k in range(7):
        column(d, 586 + k * 64, 310, 520, 32, (244, 238, 224), (206, 196, 176))
    d.rectangle(s((560, 520, 1040, 548)), fill=(240, 232, 214, 255))
    lay, ld = layer_of(img)
    ld.ellipse(s((720, 340, 880, 500)), fill=(255, 220, 120, 150))
    lay = lay.filter(ImageFilter.GaussianBlur(s(14)))
    img.alpha_composite(lay)
    # Statues of gods, much taller than the fighters (GDD 7.2)
    statue(d, 250, 560, 470, "trident")
    statue(d, 1350, 560, 470, "spear")
    # Marble floor platform with clouds beneath
    d.rectangle(s((0, FLOOR_Y, W, 662)), fill=(244, 240, 234, 255))
    for _ in range(36):
        x = rnd.randint(0, W)
        pts = [(x, FLOOR_Y + 4)]
        for k in range(5):
            pts.append((pts[-1][0] + rnd.randint(10, 40), pts[-1][1] + rnd.randint(-4, 8)))
        d.line(s(pts), fill=(200, 196, 204, 255), width=s(2))
    d.line(s([(0, FLOOR_Y), (W, FLOOR_Y)]), fill=(200, 170, 90, 255), width=s(5))
    d.rectangle(s((0, 656, W, 664)), fill=(210, 180, 100, 255))
    for _ in range(70):
        x, y, r = rnd.randint(-40, W + 40), rnd.randint(668, 740), rnd.randint(30, 70)
        d.ellipse(s((x - r * 1.5, y - r * 0.7, x + r * 1.5, y + r * 0.7)), fill=(255, 246, 244, 255))
    # Boundary columns (GDD 5.4)
    column(d, 4, 60, FLOOR_Y, 64)
    column(d, W - 68, 60, FLOOR_Y, 64)
    finish(img, STAGES / "stage_3_mythic_summit.png")


# --------------------------------------------------------------------------
# Menu background and HUD bar textures
# --------------------------------------------------------------------------
def menu_background():
    rnd = random.Random(4)
    w, h = 1280, 720
    img, d = canvas(w, h)
    gradient(d, (12, 10, 30), (70, 34, 60), 0, 460, 0, w)
    gradient(d, (70, 34, 60), (150, 70, 50), 460, h, 0, w)
    lay, ld = layer_of(img)
    for _ in range(30):
        x, y, r = rnd.randint(0, w), rnd.randint(40, 380), rnd.randint(60, 140)
        ld.ellipse(s((x - r * 2, y - r * 0.6, x + r * 2, y + r * 0.6)), fill=(46, 34, 70, 130))
    # A giant faint god figure in the clouds
    ld.ellipse(s((560, 70, 720, 230)), fill=(110, 96, 150, 120))
    ld.polygon(s([(470, 720), (560, 230), (720, 230), (810, 720)]), fill=(96, 84, 140, 110))
    lay = lay.filter(ImageFilter.GaussianBlur(s(8)))
    img.alpha_composite(lay)
    d = ImageDraw.Draw(img)
    # lightning
    pts, x, y = [], 900, 0
    while y < 520:
        pts.append((x, y))
        x += rnd.randint(-45, 35)
        y += rnd.randint(30, 60)
    d.line(s(pts), fill=(255, 240, 160, 255), width=s(9))
    d.line(s(pts), fill=(255, 255, 255, 255), width=s(3))
    # silhouettes of warriors on a ridge
    d.polygon(s([(0, 720), (0, 600), (300, 570), (640, 590), (980, 565), (1280, 600), (1280, 720)]), fill=(14, 10, 18, 255))
    for k, x in enumerate(range(150, 1200, 135)):
        y = 585
        d.ellipse(s((x - 12, y - 132, x + 12, y - 108)), fill=(14, 10, 18, 255))
        d.polygon(s([(x - 22, y - 106), (x + 22, y - 106), (x + 16, y - 40), (x - 16, y - 40)]), fill=(14, 10, 18, 255))
        d.line(s([(x - 8, y - 40), (x - 14, y)]), fill=(14, 10, 18, 255), width=s(12))
        d.line(s([(x + 8, y - 40), (x + 14, y)]), fill=(14, 10, 18, 255), width=s(12))
        if k % 2 == 0:
            d.line(s([(x + 20, y - 100), (x + 46, y - 190)]), fill=(14, 10, 18, 255), width=s(5))
    finish(img, UI / "menu_background.png", w, h)


def bar_textures():
    under = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(under)
    d.rounded_rectangle((0, 0, 31, 15), radius=4, fill=(18, 16, 22, 230), outline=(235, 225, 200, 255), width=2)
    UI.mkdir(parents=True, exist_ok=True)
    under.save(UI / "bar_under.png")
    fill = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(fill)
    for y in range(16):
        v = int(255 - abs(y - 5) * 9)
        d.line([(2, y), (29, y)], fill=(v, v, v, 255))
    d.rectangle((0, 0, 1, 15), fill=(0, 0, 0, 0))
    d.rectangle((30, 0, 31, 15), fill=(0, 0, 0, 0))
    fill.putpixel((2, 0), (0, 0, 0, 0))
    fill.save(UI / "bar_fill.png")
    print("wrote bar textures")


if __name__ == "__main__":
    ancient_arena()
    battlefield()
    mythic_summit()
    menu_background()
    bar_textures()

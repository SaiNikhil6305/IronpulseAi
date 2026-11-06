"""Render IronPulse muscle-group demo videos (720x1280, 30 fps).

Photos: free-exercise-db (https://github.com/yuhonas/free-exercise-db), public domain (Unlicense).
Body map: original artwork drawn here.

Usage: python3 render.py <photo_dir> <out_dir> [--preview]
"""
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS, DUR = 720, 1280, 30, 9.0
BG = (10, 10, 11)
CARD = (22, 23, 26)
BORDER = (42, 44, 49)
ORANGE = (255, 106, 19)
AMBER = (255, 176, 32)
TEXT = (255, 255, 255)
MUTED = (154, 156, 163)
BODY = (46, 48, 54)
MUSCLE = (66, 69, 77)
EDGE = (92, 96, 106)

FD = "/usr/share/fonts/opentype/inter/"


def font(weight, size):
    return ImageFont.truetype(FD + {"b": "Inter-Bold.otf", "x": "Inter-ExtraBold.otf", "m": "Inter-Medium.otf",
                                    "r": "Inter-Regular.otf", "s": "Inter-SemiBold.otf"}[weight], size)


# ---------------------------------------------------------------- body map geometry (180 x 400 box)
def mirror(pts):
    return [(180 - x, y) for x, y in pts]


SIL = {  # body silhouette parts drawn for one side and mirrored
    "uarm": [(40, 76), (56, 80), (54, 150), (36, 152), (28, 112)],
    "farm": [(36, 150), (54, 150), (49, 214), (37, 214), (27, 180)],
    "thigh": [(60, 206), (91, 214), (89, 302), (66, 304), (56, 252)],
    "shin": [(66, 300), (89, 300), (86, 376), (72, 376), (63, 338)],
    "foot": [(70, 372), (88, 372), (91, 392), (62, 392)],
}
TORSO = [(60, 62), (120, 62), (142, 78), (133, 150), (125, 200), (119, 218), (61, 218), (55, 200), (47, 150), (38, 78)]
NECK = [(80, 46), (100, 46), (104, 66), (76, 66)]

FRONT = {
    "traps": [[(81, 56), (62, 70), (84, 70)]],
    "delts": [[(40, 74), (60, 68), (62, 90), (47, 106), (34, 94)]],
    "chest": [[(61, 74), (89, 77), (89, 112), (73, 117), (56, 104), (55, 88)]],
    "biceps": [[(40, 106), (53, 98), (53, 141), (43, 147), (35, 128)]],
    "forearms": [[(37, 153), (52, 153), (48, 202), (38, 202), (30, 177)]],
    "abs": [[(78, 119), (88, 120), (88, 134), (78, 134)], [(78, 137), (88, 137), (88, 153), (78, 153)],
            [(79, 156), (88, 156), (88, 175), (79, 175)], [(80, 178), (88, 178), (88, 204), (81, 202)]],
    "obliques": [[(60, 119), (75, 121), (75, 176), (65, 186), (58, 150)]],
    "quads": [[(63, 222), (89, 227), (87, 290), (73, 297), (60, 262)]],
    "calves": [[(66, 310), (80, 306), (78, 352), (69, 352)]],
}
BACK = {
    "traps": [[(90, 52), (68, 70), (81, 86), (90, 124), (99, 86), (112, 70)]],
    "delts": [[(40, 74), (60, 68), (62, 90), (47, 106), (34, 94)]],
    "lats": [[(60, 92), (81, 98), (87, 152), (71, 162), (58, 130)]],
    "triceps": [[(37, 102), (53, 98), (53, 142), (43, 147), (33, 124)]],
    "forearms": [[(37, 153), (52, 153), (48, 202), (38, 202), (30, 177)]],
    "lowerback": [[(80, 150), (88, 146), (88, 196), (80, 196)]],
    "glutes": [[(61, 200), (89, 205), (89, 242), (70, 246), (59, 228)]],
    "hamstrings": [[(64, 248), (89, 248), (87, 297), (73, 299), (61, 272)]],
    "calves": [[(65, 304), (87, 304), (85, 352), (72, 354), (63, 330)]],
}
CENTRAL = {"traps"}  # back traps polygon already spans both sides


def figure(draw, ox, oy, s, muscles, colors):
    """Draw one figure; colors maps muscle key -> fill colour."""
    P = lambda pts: [(ox + x * s, oy + y * s) for x, y in pts]
    for part in [TORSO, NECK]:
        draw.polygon(P(part), fill=BODY)
    for pts in SIL.values():
        draw.polygon(P(pts), fill=BODY)
        draw.polygon(P(mirror(pts)), fill=BODY)
    draw.ellipse(P([(71, 6), (109, 52)]), fill=BODY)
    for key, polys in muscles.items():
        c = colors.get(key, MUSCLE)
        for pts in polys:
            draw.polygon(P(pts), fill=c, outline=EDGE if c == MUSCLE else None)
            if not (muscles is BACK and key in CENTRAL):
                draw.polygon(P(mirror(pts)), fill=c, outline=EDGE if c == MUSCLE else None)


GAP = 30


def body_layer(target, secondary, color_target, color_sec, scale):
    """RGBA layer with both figures, drawn 3x and downsampled for smooth edges."""
    out = (int(180 * scale * 2 + GAP * scale), int(400 * scale))
    scale *= 3
    w, h = int(180 * scale * 2 + GAP * scale), int(400 * scale)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cols = {}
    for k in secondary:
        cols[k] = color_sec
    if target:
        cols[target] = color_target
    figure(d, 0, 0, scale, FRONT, cols)
    figure(d, int(180 * scale + GAP * scale), 0, scale, BACK, cols)
    return img.resize(out, Image.LANCZOS)


def mask_layer(keys, color, scale):
    """Only the given muscles, for glows."""
    out = (int(180 * scale * 2 + GAP * scale), int(400 * scale))
    scale *= 3
    w, h = int(180 * scale * 2 + GAP * scale), int(400 * scale)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for view, ox in ((FRONT, 0), (BACK, int((180 + GAP) * scale))):
        for k in keys:
            for pts in view.get(k, []):
                P = [(ox + x * scale, y * scale) for x, y in pts]
                d.polygon(P, fill=color)
                if not (view is BACK and k in CENTRAL):
                    d.polygon([(ox + (180 - x) * scale, y * scale) for x, y in pts], fill=color)
    return img.resize(out, Image.LANCZOS)


# ---------------------------------------------------------------- content
VIDEOS = [
    ("chest", "CHEST", "Barbell Bench Press", "Barbell_Bench_Press_-_Medium_Grip",
     ("chest", "Chest", "Pectoralis major"),
     [("delts", "Front shoulders", "Anterior deltoid"), ("triceps", "Triceps", "Triceps brachii")]),
    ("back", "BACK", "Wide-Grip Lat Pulldown", "Wide-Grip_Lat_Pulldown",
     ("lats", "Lats", "Latissimus dorsi"),
     [("biceps", "Biceps", "Biceps brachii"), ("traps", "Mid back", "Rhomboids & lower trapezius"),
      ("delts", "Rear shoulders", "Posterior deltoid")]),
    ("shoulders", "SHOULDERS", "Dumbbell Shoulder Press", "Dumbbell_Shoulder_Press",
     ("delts", "Shoulders", "Anterior & lateral deltoid"),
     [("triceps", "Triceps", "Triceps brachii"), ("traps", "Upper traps", "Upper trapezius")]),
    ("biceps", "BICEPS", "Dumbbell Bicep Curl", "Dumbbell_Bicep_Curl",
     ("biceps", "Biceps", "Biceps brachii & brachialis"),
     [("forearms", "Forearms", "Brachioradialis")]),
    ("triceps", "TRICEPS", "Cable Triceps Pushdown", "Triceps_Pushdown",
     ("triceps", "Triceps", "Triceps brachii (all 3 heads)"),
     [("forearms", "Forearms", "Wrist stabilisers"), ("abs", "Core", "Rectus abdominis (bracing)")]),
    ("quads", "LEGS · QUADS", "Barbell Back Squat", "Barbell_Squat",
     ("quads", "Quadriceps", "Rectus femoris & vasti"),
     [("glutes", "Glutes", "Gluteus maximus"), ("hamstrings", "Hamstrings", "Biceps femoris"),
      ("lowerback", "Lower back", "Erector spinae"), ("calves", "Calves", "Gastrocnemius & soleus")]),
    ("hamstrings", "LEGS · HAMSTRINGS", "Romanian Deadlift", "Romanian_Deadlift",
     ("hamstrings", "Hamstrings", "Biceps femoris, semitendinosus"),
     [("glutes", "Glutes", "Gluteus maximus"), ("lowerback", "Lower back", "Erector spinae"),
      ("forearms", "Grip", "Forearm flexors")]),
    ("glutes", "GLUTES", "Barbell Hip Thrust", "Barbell_Hip_Thrust",
     ("glutes", "Glutes", "Gluteus maximus & medius"),
     [("hamstrings", "Hamstrings", "Biceps femoris"), ("quads", "Quadriceps", "Rectus femoris & vasti")]),
    ("calves", "CALVES", "Standing Calf Raise", "Standing_Calf_Raises",
     ("calves", "Calves", "Gastrocnemius"),
     [("calves", "Deep calf", "Soleus")]),
    ("abs", "ABS & CORE", "Cable Crunch", "Cable_Crunch",
     ("abs", "Abs", "Rectus abdominis"),
     [("obliques", "Obliques", "External & internal obliques")]),
    ("traps", "TRAPS", "Barbell Shrug", "Barbell_Shrug",
     ("traps", "Traps", "Upper trapezius"),
     [("forearms", "Grip", "Forearm flexors"), ("traps", "Neck", "Levator scapulae")]),
    ("forearms", "FOREARMS", "Barbell Wrist Curl", "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench",
     ("forearms", "Forearms", "Wrist flexors"),
     [("forearms", "Inner forearm", "Palmaris longus")]),
]


PY = 176   # photo top
CY = 712   # body-map card top
GREEN = (46, 204, 113)
RED = (255, 77, 79)

# key -> (what is measured, gauge max deg, best (lo, hi), best label, best why, avoid (lo, hi), avoid label, avoid why)
ANGLES = {
    "chest": ("Elbow angle from torso", 90, (35, 55), "45°", "Strongest press, less shoulder stress",
              (78, 90), "90°", "Flared elbows: shoulder impingement risk"),
    "back": ("Torso lean back", 90, (10, 30), "≈20°", "Pull bar to upper chest; lats do the work",
             (50, 90), ">45°", "Swinging: momentum replaces the lats"),
    "shoulders": ("Elbows forward (scapular plane)", 90, (20, 40), "≈30°", "Natural shoulder path, more room in joint",
                  (0, 6), "0°", "Elbows straight out: impingement risk"),
    "biceps": ("Upper-arm swing", 90, (0, 8), "0°", "Elbows pinned: full tension on biceps",
               (30, 90), ">30°", "Swinging: shoulders and back take over"),
    "triceps": ("Elbow flare from body", 90, (0, 12), "0–10°", "Elbows tucked: triceps stay loaded",
                (45, 90), ">45°", "Flared: chest and shoulders take over"),
    "quads": ("Knee bend at the bottom", 140, (95, 125), "≥90°", "Thighs at/below parallel: more muscle growth",
              (0, 50), "<45°", "Quarter squat: much less muscle worked"),
    "hamstrings": ("Hip hinge from upright", 90, (50, 80), "60–80°", "Flat back, soft knees ≈20°: big stretch",
                   (85, 90), "Round back", "Spine rounding under load: back injury risk"),
    "glutes": ("Knee angle at the top", 180, (82, 98), "≈90°", "Shins vertical: glutes at full contraction",
               (130, 180), ">130°", "Feet too far out: hamstrings take over"),
    "calves": ("Knee bend", 90, (0, 6), "0°", "Straight knees target the gastrocnemius",
               (60, 90), "90°", "Bent knees shift work to the soleus"),
    "abs": ("Spinal curl (ribs to hips)", 90, (30, 50), "≈40°", "Curl the spine, hips stay still",
            (70, 90), "Hip fold", "Folding at hips: hip flexors take over"),
    "traps": ("Shoulder path", 90, (0, 6), "0° straight up", "Lift straight up, pause at the top",
              (30, 90), "Rolling", "Rolling shoulders: no extra benefit, joint stress"),
    "forearms": ("Wrist range of motion", 140, (110, 140), "≈130° full", "Lower fully, curl fully: most growth",
                 (0, 45), "<45°", "Partial reps: far less stimulus"),
}


def angle_panel(key):
    m = ANGLES[key]
    what, mx, (blo, bhi), blab, bwhy, (alo, ahi), alab, awhy = m
    S = 2
    pw_, ph_ = W - 32, 150
    img = Image.new("RGBA", (pw_ * S, ph_ * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, pw_ * S - 1, ph_ * S - 1], 18 * S, fill=(8, 8, 10, 215), outline=(70, 72, 80, 255), width=S)
    d.text((16 * S, 12 * S), "BEST ANGLE", font=font("x", 14 * S), fill=GREEN)
    d.text((16 * S + d.textlength("BEST ANGLE  ", font=font("x", 14 * S)), 12 * S), what.upper(), font=font("s", 12 * S),
           fill=MUTED)
    # gauge: semicircle, 0 at left, max at right
    cx, cy, r, wdt = 84 * S, 124 * S, 60 * S, 13 * S
    box = [cx - r, cy - r, cx + r, cy + r]
    a = lambda v: 180 + 180 * v / mx
    d.arc(box, 180, 360, fill=(60, 62, 70), width=wdt)
    d.arc(box, a(alo), a(ahi), fill=RED, width=wdt)
    d.arc(box, a(blo), a(bhi), fill=GREEN, width=wdt)
    mid = (blo + bhi) / 2
    ang = math.radians(a(mid))
    d.line([(cx, cy), (cx + (r - 18 * S) * math.cos(ang), cy + (r - 18 * S) * math.sin(ang))], fill=TEXT, width=4 * S)
    d.ellipse([cx - 6 * S, cy - 6 * S, cx + 6 * S, cy + 6 * S], fill=TEXT)
    d.text((cx - r - 4 * S, cy + 4 * S), "0°", font=font("m", 11 * S), fill=MUTED)
    d.text((cx + r - 18 * S, cy + 4 * S), f"{mx}°", font=font("m", 11 * S), fill=MUTED)
    # texts
    x = 172 * S
    tw = (pw_ - 184) * S

    def block(y, color, mark, lab, why):
        d.ellipse([x, y + 3 * S, x + 20 * S, y + 23 * S], fill=color)
        k = 5 * S
        mx_, my_ = x + 10 * S, y + 13 * S
        if mark == "ok":
            d.line([(mx_ - k, my_), (mx_ - k / 3, my_ + k * 0.7), (mx_ + k, my_ - k * 0.7)], fill=(0, 0, 0), width=3 * S)
        else:
            d.line([(mx_ - k * .8, my_ - k * .8), (mx_ + k * .8, my_ + k * .8)], fill=(0, 0, 0), width=3 * S)
            d.line([(mx_ - k * .8, my_ + k * .8), (mx_ + k * .8, my_ - k * .8)], fill=(0, 0, 0), width=3 * S)
        d.text((x + 28 * S, y), lab, font=font("x", 20 * S), fill=color)
        yy = y + 27 * S
        lw = d.textlength(lab + "  ", font=font("x", 20 * S))
        lines = wrap(why, font("m", 14 * S), tw - 28 * S - lw, d)
        for i, line in enumerate(lines[:2]):
            d.text((x + 28 * S + lw, y + 4 * S + i * 18 * S - (8 * S if len(lines) > 1 else 0)), line,
                   font=font("m", 14 * S), fill=(220, 222, 228))

    block(42 * S, GREEN, "ok", blab, bwhy)
    block(96 * S, RED, "no", alab, awhy)
    return img.resize((pw_, ph_), Image.LANCZOS)


def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], r, fill=255)
    img.putalpha(m)
    return img


def ease(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def static_frame(v):
    key, group, name, photo, target, sec = v
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # header
    d.text((28, 34), "IRON", font=font("x", 34), fill=TEXT)
    d.text((28 + d.textlength("IRON", font=font("x", 34)), 34), "PULSE", font=font("x", 34), fill=ORANGE)
    tag = f"{group} DAY" if "·" not in group else group
    tw = d.textlength(tag, font=font("b", 18))
    d.rounded_rectangle([W - 28 - tw - 28, 36, W - 28, 74], 19, fill=(51, 25, 10), outline=ORANGE)
    d.text((W - 28 - tw - 14, 45), tag, font=font("b", 18), fill=ORANGE)
    d.text((28, 96), name, font=font("x", 40), fill=TEXT)
    d.text((28, 142), "Exercise demonstration", font=font("m", 18), fill=MUTED)
    # body map card
    d.rounded_rectangle([16, CY, W - 16, H - 52], 22, fill=CARD, outline=BORDER)
    d.text((100, CY + 18), "FRONT", font=font("b", 14), fill=MUTED)
    d.text((302, CY + 18), "BACK", font=font("b", 14), fill=MUTED)
    # legend / labels column
    x0 = 480
    d.text((x0, CY + 20), "TARGET MUSCLE", font=font("b", 15), fill=ORANGE)
    ts = 30
    while ts > 18 and d.textlength(target[1], font=font("x", ts)) > W - 36 - x0:
        ts -= 1
    d.text((x0, CY + 44 + (30 - ts) // 2), target[1], font=font("x", ts), fill=TEXT)
    y = CY + 82
    for line in wrap(target[2], font("m", 18), W - 40 - x0, d):
        d.text((x0, y), line, font=font("m", 18), fill=MUTED)
        y += 24
    y += 22
    d.text((x0, y), "ALSO INVOLVED", font=font("b", 15), fill=AMBER)
    y += 28
    for _, lab, anat in sec:
        d.ellipse([x0, y + 7, x0 + 12, y + 19], fill=AMBER)
        d.text((x0 + 22, y), lab, font=font("s", 20), fill=TEXT)
        y += 26
        for line in wrap(anat, font("r", 16), W - 62 - x0, d):
            d.text((x0 + 22, y), line, font=font("r", 16), fill=MUTED)
            y += 21
        y += 12
    d.text((28, H - 40), "Photos: free-exercise-db (public domain) · Angles: biomechanics guidance, not medical advice", font=font("r", 14), fill=(90, 92, 99))
    return img


def wrap(text, f, width, d):
    words, lines, cur = text.split(), [], ""
    for w_ in words:
        t = (cur + " " + w_).strip()
        if d.textlength(t, font=f) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w_
    lines.append(cur)
    return lines


def render(v, photo_dir, out_dir, preview=False):
    key, group, name, photo, target, sec = v
    base = static_frame(v)
    scale = 1.1
    sec_keys = [k for k, _, _ in sec if k != target[0]]
    body = body_layer(target[0], sec_keys, ORANGE, AMBER, scale)
    glow_src = mask_layer([target[0]], ORANGE + (255,), scale)
    pad = 30
    glow = Image.new("RGBA", (glow_src.width + 2 * pad, glow_src.height + 2 * pad), (0, 0, 0, 0))
    glow.paste(glow_src, (pad, pad))
    glow = glow.filter(ImageFilter.GaussianBlur(12))
    core = mask_layer([target[0]], (255, 190, 140, 255), scale)
    bx, by = 30, CY + (H - 52 - CY - int(400 * scale)) // 2 + 14
    # photos sized to card
    pw, ph = W - 32, 360
    photos = [Image.open(os.path.join(photo_dir, f"{photo}_{i}.jpg")).convert("RGB") for i in (0, 1)]

    def photo_at(i, zoom):
        p = photos[i]
        zw = int(pw * zoom)
        zh = int(zw * p.height / p.width)
        p = p.resize((zw, zh), Image.LANCZOS)
        l, t = (zw - pw) // 2, int((zh - ph) * 0.4)
        return p.crop((l, t, l + pw, t + ph))

    angle_panel_img = angle_panel(key)
    n = int(DUR * FPS)
    tmp = os.path.join(out_dir, f"{key}.tmp.mp4")
    final = os.path.join(out_dir, f"{key}.mp4")
    frames = [0, 45, 100] if preview else range(n)
    proc = None
    if not preview:
        proc = subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                                 "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "veryfast", "-crf", "25",
                                 "-pix_fmt", "yuv420p", "-movflags", "+faststart", tmp], stdin=subprocess.PIPE)
    cycle = 2.4  # start hold, fade, finish hold, fade
    for f in frames:
        t = f / FPS
        img = base.copy()
        # photo: crossfade start <-> finish, slow push-in
        ph_t = t % cycle
        if ph_t < 0.8:
            mix = 0.0
        elif ph_t < 1.2:
            mix = (ph_t - 0.8) / 0.4
        elif ph_t < 2.0:
            mix = 1.0
        else:
            mix = 1 - (ph_t - 2.0) / 0.4
        mix = 0.5 - 0.5 * math.cos(math.pi * mix)
        zoom = 1.0 + 0.04 * (t / DUR)
        p = Image.blend(photo_at(0, zoom), photo_at(1, zoom), mix)
        p = rounded(p.convert("RGBA"), 20)
        intro = ease(t / 0.6)
        img.paste(p, (16, PY + int(30 * (1 - intro))), p)
        d = ImageDraw.Draw(img)
        chip = "START" if mix < 0.5 else "FINISH"
        d.rounded_rectangle([32, PY + 16, 32 + 96, PY + 46], 15, fill=(0, 0, 0))
        d.text((32 + 48 - d.textlength(chip, font=font("b", 15)) / 2, PY + 23), chip, font=font("b", 15), fill=TEXT)
        ap = angle_panel_img
        a_in = ease((t - 0.5) / 0.6)
        if a_in > 0:
            ap2 = ap.copy()
            ap2.putalpha(ap2.getchannel("A").point(lambda v_: int(v_ * a_in)))
            img.paste(ap2, (16, PY + ph + 12 + int(20 * (1 - a_in))), ap2)
        wm = "IRONPULSE"
        d.text((W - 32 - d.textlength(wm, font=font("x", 18)), PY + ph - 34), wm, font=font("x", 18), fill=(255, 255, 255))
        # body map with pulsing target
        img.paste(body, (bx, by), body)
        pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(2 * math.pi * t / 1.2))
        g = glow.copy()
        g.putalpha(g.getchannel("A").point(lambda a: int(a * pulse * min(1, t / 0.8))))
        img.paste(g, (bx - pad, by - pad), g)
        c = core.copy()
        c.putalpha(c.getchannel("A").point(lambda a: int(a * 0.35 * pulse)))
        img.paste(c, (bx, by), c)
        if preview:
            img.save(os.path.join(out_dir, f"preview_{key}_{f}.png"))
        else:
            proc.stdin.write(img.tobytes())
    if proc:
        proc.stdin.close()
        if proc.wait() == 0:
            os.replace(tmp, final)
            return final
        raise RuntimeError("ffmpeg failed for " + key)


if __name__ == "__main__":
    from videos_data import V
    VIDEOS = [(k, g, n, ph, t, sec) for k, (g, n, ph, t, sec, _) in V.items()]
    ANGLES.clear()
    ANGLES.update({k: v[5] for k, v in V.items()})
    photo_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    only = [a for a in sys.argv[3:] if not a.startswith("--")]
    for v in VIDEOS:
        if only and v[0] not in only:
            continue
        print(render(v, photo_dir, out_dir, preview="--preview" in sys.argv), flush=True)

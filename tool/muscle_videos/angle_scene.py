"""Angle-comparison scene (rows of the same body at different angles), IronPulse style.

Usage: python3 angle_scene.py <out.mp4> [--preview dir]
"""
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

from render import BG, FPS, H, MUTED, TEXT, W, font

GREEN, ORANGE, RED = (46, 204, 113), (255, 140, 40), (255, 77, 79)
SKIN, EDGE = (196, 200, 210), (150, 154, 166)
DUR = 8.0
ROW_H = 336
TOP = 150

# (angle from torso, colour, label, sub-label, bad?)
ROWS = [
    (90, RED, "INJURY RISK", "Elbows flared 90°: shoulder impingement", True),
    (45, GREEN, "CHEST", "Elbows 45°: strongest, shoulder-friendly", False),
    (20, ORANGE, "TRICEPS", "Elbows tucked 20°: shifts work to triceps", False),
]


def ease(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def arm_points(sx, sy, ang, side, L1=100, L2=78):
    """Upper arm from shoulder at `ang` degrees from torso (0 = down), forearm bent upward like a press."""
    a = math.radians(ang)
    ex, ey = sx + side * L1 * math.sin(a), sy + L1 * math.cos(a)
    hx, hy = ex + side * 6, ey - L2  # forearm vertical (pressing position)
    return (ex, ey), (hx, hy)


def draw_row(img, y0, ang_target, color, label, sub, bad, t, S=2):
    w, h = W * S, ROW_H * S
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, sy = 440 * S, 132 * S
    ang = 8 + (ang_target - 8) * ease(t)
    shoulder_w = 64 * S
    # torso (back view)
    d.polygon([(cx - 70 * S, sy - 8 * S), (cx + 70 * S, sy - 8 * S), (cx + 74 * S, sy + 40 * S), (cx + 58 * S, sy + 100 * S),
               (cx + 46 * S, sy + 150 * S), (cx - 46 * S, sy + 150 * S), (cx - 58 * S, sy + 100 * S), (cx - 74 * S, sy + 40 * S)],
              fill=SKIN)
    d.ellipse([cx - 30 * S, sy - 92 * S, cx + 30 * S, sy - 22 * S], fill=SKIN)
    d.polygon([(cx - 16 * S, sy - 30 * S), (cx + 16 * S, sy - 30 * S), (cx + 22 * S, sy), (cx - 22 * S, sy)], fill=SKIN)
    d.line([(cx, sy), (cx, sy + 146 * S)], fill=EDGE, width=2 * S)  # spine
    pts = {}
    for side in (-1, 1):
        sx = cx + side * shoulder_w
        (ex, ey), (hx, hy) = arm_points(sx / S, sy / S, ang, side)
        ex, ey, hx, hy = ex * S, ey * S, hx * S, hy * S
        d.line([(sx, sy), (ex, ey)], fill=SKIN, width=34 * S)
        d.line([(ex, ey), (hx, hy)], fill=SKIN, width=28 * S)
        d.ellipse([sx - 26 * S, sy - 22 * S, sx + 26 * S, sy + 26 * S], fill=SKIN)  # deltoid
        d.ellipse([ex - 16 * S, ey - 16 * S, ex + 16 * S, ey + 16 * S], fill=SKIN)
        d.ellipse([hx - 16 * S, hy - 22 * S, hx + 16 * S, hy + 8 * S], fill=SKIN)  # hand
        pts[side] = (sx, sy, ex, ey)
    # muscle highlight
    hl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    if label == "CHEST":
        for side in (-1, 1):
            hd.chord([cx + min(0, side) * 64 * S + side * 2 * S, sy - 6 * S, cx + max(0, side) * 64 * S + side * 2 * S, sy + 66 * S],
                     0, 360, fill=color + (255,))
    for side in (-1, 1):
        sx, sy_, ex, ey = pts[side]
        if label == "TRICEPS":
            hd.line([(sx, sy_), (ex, ey)], fill=color + (255,), width=26 * S)
        if bad:
            hd.ellipse([sx - 24 * S, sy_ - 20 * S, sx + 24 * S, sy_ + 24 * S], fill=color + (255,))
    pulse = 0.6 + 0.4 * math.sin(2 * math.pi * t / 1.2)
    glow = hl.filter(ImageFilter.GaussianBlur(14 * S))
    glow.putalpha(glow.getchannel("A").point(lambda a: int(min(255, a * 1.6) * pulse)))
    core = hl.copy()
    core.putalpha(core.getchannel("A").point(lambda a: int(a * 0.85)))
    layer.alpha_composite(glow)
    layer.alpha_composite(core)
    # angle guide: line along shoulders and arms + arc
    gd = ImageDraw.Draw(layer)
    l, r_ = pts[-1], pts[1]
    gd.line([(l[2], l[3]), (l[0], l[1]), (r_[0], r_[1]), (r_[2], r_[3])], fill=color, width=4 * S, joint="curve")
    sx, sy_, ex, ey = pts[1]
    rad = 54 * S
    gd.arc([sx - rad, sy_ - rad, sx + rad, sy_ + rad], 90 - ang, 90, fill=color, width=4 * S)
    gd.text((sx + 60 * S, sy_ + 70 * S), f"{round(ang)}°", font=font("x", 26 * S), fill=color)
    layer = layer.resize((W, ROW_H), Image.LANCZOS)
    img.alpha_composite(layer, (0, y0))
    # badge card on the left
    d2 = ImageDraw.Draw(img)
    bx, by = 34, y0 + 70
    d2.rounded_rectangle([bx, by, bx + 150, by + 170], 18, fill=(20, 21, 24, 255), outline=color, width=3)
    d2.text((bx + 75, by + 40), f"{ang_target}°", font=font("x", 40), fill=color, anchor="mm")
    if bad:
        d2.ellipse([bx + 51, by + 74, bx + 99, by + 122], fill=color)
        d2.line([(bx + 63, by + 86), (bx + 87, by + 110)], fill=(0, 0, 0), width=6)
        d2.line([(bx + 63, by + 110), (bx + 87, by + 86)], fill=(0, 0, 0), width=6)
    else:
        d2.ellipse([bx + 51, by + 74, bx + 99, by + 122], fill=color)
        d2.line([(bx + 63, by + 98), (bx + 72, by + 108), (bx + 89, by + 88)], fill=(0, 0, 0), width=6, joint="curve")
    d2.text((bx + 75, by + 145), label, font=font("x", 18), fill=TEXT, anchor="mm")
    d2.text((W // 2 + 80, y0 + ROW_H - 22), sub, font=font("m", 17), fill=MUTED, anchor="mm")


def frame(t):
    img = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(img)
    d.text((28, 34), "IRON", font=font("x", 34), fill=TEXT)
    d.text((28 + d.textlength("IRON", font=font("x", 34)), 34), "PULSE", font=font("x", 34), fill=(255, 106, 19))
    d.text((28, 92), "Bench Press · Elbow angle", font=font("x", 32), fill=TEXT)
    for i, (ang, col, lab, sub, bad) in enumerate(ROWS):
        y0 = TOP + i * (ROW_H + 8)
        d.rounded_rectangle([16, y0, W - 16, y0 + ROW_H], 22, fill=(22, 23, 26, 255), outline=(42, 44, 49, 255))
        draw_row(img, y0, ang, col, lab, sub, bad, t - 0.35 * i)
    d.text((28, H - 40), "Biomechanics guidance, not medical advice", font=font("r", 14), fill=(90, 92, 99))
    return img.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1]
    if "--preview" in sys.argv:
        pdir = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(pdir, exist_ok=True)
        for t in (0.4, 3.0):
            frame(t).save(os.path.join(pdir, f"angle_{t}.png"))
        sys.exit()
    tmp = out[:-4] + ".tmp.mp4"
    p = subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
                          "-i", "-", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", tmp],
                         stdin=subprocess.PIPE)
    for f in range(int(DUR * FPS)):
        p.stdin.write(frame(f / FPS).tobytes())
    p.stdin.close()
    if p.wait() == 0:
        os.replace(tmp, out)
        print(out)

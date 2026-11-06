"""Generate IronPulse launcher icons (original artwork: orange pulse line on black).

Run: python3 tool/make_icons.py   (requires Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ORANGE = (255, 106, 19, 255)
BLACK = (10, 10, 11, 255)


def draw(size: int, rounded: bool = True, padding: float = 0.0) -> Image.Image:
    s = size * 4  # supersample for smooth edges
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=BLACK)
    else:
        d.rectangle([0, 0, s, s], fill=BLACK)
    p = s * (0.16 + padding)
    w = s - 2 * p
    mid = s / 2
    pts = [(p, mid), (p + w * 0.26, mid), (p + w * 0.38, mid - w * 0.30), (p + w * 0.56, mid + w * 0.30),
           (p + w * 0.68, mid), (p + w, mid)]
    d.line(pts, fill=ORANGE, width=int(s * 0.085), joint="curve")
    r = s * 0.0425
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=ORANGE)
    return img.resize((size, size), Image.LANCZOS)


android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for name, px in android.items():
    out = ROOT / f"android/app/src/main/res/mipmap-{name}/ic_launcher.png"
    draw(px).save(out)

ios_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
if ios_dir.exists():
    import json

    contents = json.loads((ios_dir / "Contents.json").read_text())
    for img in contents["images"]:
        fn = img.get("filename")
        if not fn:
            continue
        base = float(img["size"].split("x")[0])
        scale = int(img["scale"].replace("x", ""))
        icon = draw(int(base * scale), rounded=False).convert("RGB")  # App Store icons must be opaque
        icon.save(ios_dir / fn)

draw(512).save(ROOT / "assets/images/app_icon.png")
print("icons written")

"""The launcher icon's sand a shade lighter (pass 61, Garry: "Change the App Icon. Let's just make the sand slightly
lighter. But otherwise keep the same proportions and logic.").

Reads the v0.46 painting `tools/dl/app_icon/icon_src_v046.png` (the hat on the dunes, kept as it was) and writes
`tools/dl/app_icon/icon_src.png`: the same picture, pixel for pixel in place, with only the sand lifted. The hat (every
pixel darker than HAT_V and every pale sheen inside it: its leather, its band and its ink outline, grown by HAT_GROW px and
feathered) is left exactly as painted, and so is its cast shadow on the sand (pixels darker than SHADOW_V near the hat,
kept whole SHADOW_RAMP below it and partly in between, fading out by SHADOW_REACH px, so no contour shows); the rest
goes through a gamma of GAMMA per channel, which lifts the mid tones of the sand more than its highlights (nothing clips
to white) and the blue channel most (a touch paler, like the game's own sand in pass 61). Then it rebuilds the launcher
icons from the new source exactly as `gen_art.app_icon` does (game/icon.png 1024, icon_192.png, icon_fg_432.png,
icon_bg_432.png) and, with --splash, the boot splash that carries the icon (tools/make_splash.py).

  python tools/icon_sand.py [--gamma 0.8] [--splash] [--compare out.png]
      --compare: the old and new icon side by side at 192 px and 48 px (and the full size), to look at
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(REPO, "tools", "dl", "app_icon")
SRC = os.path.join(DIR, "icon_src_v046.png")
OUT = os.path.join(DIR, "icon_src.png")
GAMMA = 0.8
HAT_V = 0.5          # the hat's leather and outline are darker than this (the sand's darkest troughs are above 0.55)
HAT_GROW = 3         # px the hat's mask is grown, so the outline's soft edge is kept too
FEATHER = 1.5        # px blur on the masks' edges
SHADOW_V = 0.74      # the hat's shadow on the sand is darker than this ...
SHADOW_REACH = 60    # ... and lies within this many px of the hat
SHADOW_RAMP = 0.1    # the shadow is kept whole this far below SHADOW_V, partly between


def masks(rgb: np.ndarray) -> np.ndarray:
    """Weight 0..1 of each pixel's sand lift: 0 on the hat and its shadow, 1 on the open sand. The shadow's weight ramps
    with its darkness (over SHADOW_RAMP below SHADOW_V, read off a slightly blurred value so the sand's grain does not
    speckle it) and fades out with the distance from the hat, so no contour shows where the kept shadow meets the
    lifted sand."""
    v = rgb.max(axis=2)
    hat = Image.fromarray(((v < HAT_V) * 255).astype(np.uint8), "L")
    # the hat's own highlights (a pale sheen on the crown) are holes in that mask: everything the sand round it cannot
    # reach from the picture's corner is the hat
    filled = hat.copy()
    ImageDraw.floodfill(filled, (0, 0), 128)
    hat = Image.fromarray(np.where(np.asarray(filled) == 128, 0, 255).astype(np.uint8), "L")
    hat = hat.filter(ImageFilter.MaxFilter(2 * HAT_GROW + 1)).filter(ImageFilter.GaussianBlur(FEATHER))
    hat_a = np.asarray(hat).astype(np.float32) / 255.0
    near = Image.fromarray(((v < HAT_V) * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(2 * (SHADOW_REACH // 2) + 1))
    near_a = np.asarray(near.filter(ImageFilter.GaussianBlur(SHADOW_REACH * 0.25))).astype(np.float32) / 255.0
    near_a = np.clip(near_a * 2.0, 0.0, 1.0)
    vb = np.asarray(Image.fromarray((v * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255.0
    dark = np.clip((SHADOW_V - vb) / SHADOW_RAMP, 0.0, 1.0)
    keep = np.maximum(hat_a, dark * near_a)
    return 1.0 - keep


def lighten(src_path: str, out_path: str, gamma: float) -> None:
    im = Image.open(src_path).convert("RGBA")
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb = a[..., :3]
    w = masks(rgb)[..., None]
    lit = np.power(rgb, gamma)
    a[..., :3] = rgb + (lit - rgb) * w
    Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(out_path)
    print("icon_sand: %s -> %s (gamma %.2f, %.0f %% of the picture lifted)" % (os.path.basename(src_path), os.path.basename(out_path), gamma, 100.0 * float((w > 0.5).mean())))


def build_icons() -> None:
    # gen_art.app_icon: the painted source to icon.png, icon_192.png and the adaptive pair
    sys.path.insert(0, os.path.join(REPO, "tools"))
    argv = sys.argv
    sys.argv = [argv[0]]
    import gen_art
    sys.argv = argv
    gen_art.app_icon()


def compare(path: str) -> None:
    old = Image.open(SRC).convert("RGBA")
    new = Image.open(OUT).convert("RGBA")
    pad = 24
    w = 512 * 2 + 192 * 2 + 48 * 2 + pad * 7
    sheet = Image.new("RGBA", (w, 512 + pad * 2), (40, 34, 30, 255))
    x = pad
    for size in (512, 192, 48):
        for im in (old, new):
            sheet.alpha_composite(im.resize((size, size), Image.LANCZOS), (x, pad))
            x += size + pad
    sheet.save(path)
    print("icon_sand: compare sheet (old, new at 512, 192, 48) -> %s" % path)


if __name__ == "__main__":
    gamma = GAMMA
    for i, arg in enumerate(sys.argv):
        if arg == "--gamma" and i + 1 < len(sys.argv):
            gamma = float(sys.argv[i + 1])
    if not os.path.exists(SRC):
        sys.exit("icon_sand: %s is missing (copy the v0.46 icon_src.png there first)" % SRC)
    lighten(SRC, OUT, gamma)
    build_icons()
    if "--splash" in sys.argv:
        subprocess.run([sys.executable, os.path.join(REPO, "tools", "make_splash.py")], check=True)
    for i, arg in enumerate(sys.argv):
        if arg == "--compare" and i + 1 < len(sys.argv):
            compare(sys.argv[i + 1])

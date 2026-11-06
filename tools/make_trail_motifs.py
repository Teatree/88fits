"""Pass 129 (lane TRAIL-UI): the Trail backdrop's section motifs, the faint tiled signs behind the track.

One white silhouette per motif name of docs/trail_schema.md (`cactus`, `star`, `skull`, `horseshoe`, `moon`, `flame`,
`dust`), 128 px, transparent, drawn with the loading wallpaper's own pen (tools/make_loading_wallpaper.py: the first
four are its shapes, the other three are drawn here) -> game/art/ui/trail/motifs/<name>.png. The screen
(game/ui/TrailScreen.gd) tints and tiles them. Then `bash tools/godot.sh --headless --path game --import`.

    python tools/make_trail_motifs.py [--sheet out.png]
"""
import argparse
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_loading_wallpaper as mlw  # noqa: E402

OUT = os.path.join(HERE, "..", "game", "art", "ui", "trail", "motifs")
SIDE = 128


def v_moon():
    p = mlw.Pen()
    p.circ(124, 128, 96)
    p.circ(164, 108, 82, 0)
    for x, y, r in ((196, 70, 9), (214, 132, 6), (176, 176, 5)):
        p.poly(mlw.star_pts(x, y, r * 2.2, r * 0.9, 4))
    return p


def v_flame():
    p = mlw.Pen()
    outer = mlw.spline([(128, 16), (158, 62), (196, 104), (206, 156), (184, 208), (128, 238), (72, 208), (50, 156),
                        (62, 112), (92, 96), (100, 60)])
    p.poly(outer)
    inner = mlw.spline([(128, 118), (150, 150), (158, 186), (128, 214), (98, 186), (104, 152)])
    p.poly(inner, 0)
    return p


def v_dust():
    """A dust devil: three curled gusts."""
    p = mlw.Pen()
    for cy, rx, w, a0, a1 in ((70, 86, 20, 200, 520), (132, 62, 17, 190, 500), (190, 38, 14, 180, 480)):
        pts = []
        n = 48
        for i in range(n + 1):
            t = i / n
            a = math.radians(a0 + (a1 - a0) * t)
            k = 1.0 - 0.55 * t
            pts.append((128 + rx * k * math.cos(a), cy + rx * 0.42 * k * math.sin(a)))
        p.line(pts, w)
    return p


MOTIFS = {"cactus": mlw.v_cactus, "star": mlw.v_star, "skull": mlw.v_skull, "horseshoe": mlw.v_horseshoe,
          "moon": v_moon, "flame": v_flame, "dust": v_dust}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", help="also write every motif side by side on slate, to look at")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    made = []
    for name, f in MOTIFS.items():
        mask = mlw.fit(f().mask(), side=SIDE, margin=0.06)
        im = Image.new("RGBA", (SIDE, SIDE), (255, 255, 255, 0))
        im.putalpha(mask)
        path = os.path.join(OUT, name + ".png")
        im.save(path)
        made.append((name, im))
        print("wrote", os.path.normpath(path))
    if args.sheet:
        sheet = Image.new("RGBA", (SIDE * len(made) + 16 * (len(made) + 1), SIDE + 32), (39, 49, 74, 255))
        for i, (_, im) in enumerate(made):
            sheet.alpha_composite(im, (16 + i * (SIDE + 16), 16))
        sheet.save(args.sheet)
        print("sheet", args.sheet)


if __name__ == "__main__":
    main()

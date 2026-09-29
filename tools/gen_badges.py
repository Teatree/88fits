"""The badges that float over special creatures (pass 33.3): a crown over every Elite, a skull over a boss, a gear over the
specials (the harpooner, the rocketeer). One Flux render each in the item icons' style (bold object, thick outline),
keyed, fitted to a 128 px cell with a heavier dark outline and a soft halo in the badge's own colour, so it reads over
the sand, the crowd and the effects at the size it is drawn on a phone (about 60 px).

  python tools/gen_badges.py [--force] [--dev] [--only crown,skull]

Output: game/art/ui/badges/<badge>.png; raw renders in tools/dl/ai_raw_props/ (cached, --force re-renders)."""
import io
import os
import sys
import time

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(REPO, "game", "art", "ui", "badges")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_props")
FORCE = "--force" in sys.argv
DEV = "--dev" in sys.argv
ONLY = None
for a in sys.argv:
    if a.startswith("--only="):
        ONLY = a.split("=", 1)[1].split(",")
CELL = 128

# badge -> (subject, halo colour, seed)
BADGES = {
    "crown": ("a golden royal crown with five tall points, each point tipped with a small round pearl, the band set with a red ruby in "
              "the middle and two blue sapphires, shiny polished gold, seen from the front", (255, 214, 110), 71),
    "skull": ("a menacing white skull seen straight from the front, big deep black eye sockets with a small red glow deep inside, a "
              "wide jaw with square teeth, a crack across the brow, bold simple shape", (255, 70, 70), 72),
    "gear": ("a single chunky steel cogwheel gear seen straight from the front, eight big square teeth round the rim, a round hole "
             "in the middle, bluish steel with a bright brass ring round the hole", (130, 215, 255), 73),
}


def _render(key, prompt, seed):
    os.makedirs(RAW, exist_ok=True)
    raw = os.path.join(RAW, "%s_%d.png" % (key, seed))
    if os.path.exists(raw) and not FORCE:
        return Image.open(raw).convert("RGB")
    t0 = time.time()
    if DEV:
        imgs, _ = comfy.run(comfy.flux2_dev(prompt, seed, 1024, 1024, steps=8, guidance=4.0, turbo=True, prefix="88fits/" + key))
    else:
        imgs, _ = comfy.run(comfy.klein(prompt, seed, 1024, 1024, refs=[], prefix="88fits/" + key))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  render %-14s seed %-4d %5.0fs" % (key, seed, time.time() - t0))
    if DEV:
        ga.log("  " + comfy.release_models())
    return img


def _halo(img, color, blur):
    """A soft glow of `color` round the badge's silhouette, under it."""
    a = img.split()[3]
    grown = a.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", img.size, color + (0,))
    layer.putalpha(grown.point(lambda v: int(v * 0.6)))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(layer)
    out.alpha_composite(img)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind, (subject, halo, seed) in BADGES.items():
        if ONLY and kind not in ONLY:
            continue
        prompt = subject + ". " + ga.ICON_STYLE + ". " + ga.BG_GREEN + "."
        img = _render("badge_" + kind, prompt, seed)
        # fitted a little inside the cell so the halo has room, then a heavy dark outline and the glow
        cell_img, _ = ga.finish(img, CELL, 0.8, False, None, 0.035, None, (24, 14, 20, 255))
        out = _halo(cell_img, halo, 4)
        path = os.path.join(OUT, kind + ".png")
        out.save(path)
        ga.log("gen_badges: wrote " + path)


if __name__ == "__main__":
    main()

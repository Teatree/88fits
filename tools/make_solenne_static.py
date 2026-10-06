"""Solenne's static pictures from Garry's turnaround (pass 54): no painting model involved.

`_REFERENCES/2d/Sun-Headed Catsuit Character Turnaround.png` holds the front view (left) and the back view (right) of the
sun-headed woman on transparency. Garry: "cut it in half width-wise and use the left side as her icon in the static Main Menu".
This writes:
  game/art/ui/wanted/hero_solenne.png            the title's painted-menu cut-out (660 x 888, gen_title_heroes.fit's rules)
  game/content/characters/solenne/solenne_icon.png   her round 256 px badge (the sun head), gen_art.portrait_badge's look
  tools/dl/ai_raw_anime/solenne_front.png / _back.png (+ .json)   the two stills gen_art would otherwise paint, laid on the
                                                   blue screen heroes are keyed from, so gen_art paints only the side and
                                                   three-quarter views, the hurt stills, the dead painting and the clips
  tools/dl/review/solenne_static.png             a review sheet
    python tools/make_solenne_static.py [--no-raw]   (--no-raw keeps the painted stills if gen_art already made better ones)
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_art as ga  # noqa: E402
import gen_title_heroes as gth  # noqa: E402

REPO = os.path.dirname(HERE)
SRC = os.path.join(REPO, "_REFERENCES", "2d", "Sun-Headed Catsuit Character Turnaround.png")
BLUE = (0, 0, 255)


def halves(im):
    """The two figures: split at the widest clear column gap between them."""
    a = im.getchannel("A")
    import numpy as np
    arr = np.asarray(a)
    cols = np.where(arr.max(axis=0) > 20)[0]
    inside = [x for x in range(cols.min(), cols.max()) if arr[:, x].max() <= 20]
    mid = (inside[0] + inside[-1]) // 2 if inside else im.width // 2
    left = im.crop((0, 0, mid, im.height))
    right = im.crop((mid, 0, im.width, im.height))
    return left, right


def on_screen(fig_rgba, fill=0.84, size=1024):
    """A keyed figure laid on the blue screen the way Klein paints a hero: `fill` of the canvas tall, feet near the bottom."""
    bbox = fig_rgba.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    fig = fig_rgba.crop(bbox)
    k = min(size * fill / fig.height, size * 0.8 / fig.width)
    fig = fig.resize((max(1, round(fig.width * k)), max(1, round(fig.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), BLUE + (255,))
    out.alpha_composite(fig, ((size - fig.width) // 2, int(size * 0.94) - fig.height))
    return out.convert("RGB")


def main():
    im = Image.open(SRC).convert("RGBA")
    front, back = halves(im)
    # the title cut-out: the front figure fitted to the title's box
    title = gth.fit(front)
    os.makedirs(gth.SLOT_DIR, exist_ok=True)
    title.save(os.path.join(gth.SLOT_DIR, "hero_solenne.png"))
    # the badge: the top of the figure (the sun head and the collar), on the screen, through the same badge routine
    bbox = front.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    head = front.crop((bbox[0], bbox[1], bbox[2], bbox[1] + int((bbox[3] - bbox[1]) * 0.34)))
    head_on = Image.new("RGBA", (head.width + 80, head.height + 80), BLUE + (255,))
    head_on.alpha_composite(head, (40, 40))
    badge = ga.portrait_badge(head_on.convert("RGB"))
    folder = os.path.join(REPO, "game", "content", "characters", "solenne")
    os.makedirs(folder, exist_ok=True)
    badge.save(os.path.join(folder, "solenne_icon.png"))
    outs = [title, badge]
    if "--no-raw" not in sys.argv:
        os.makedirs(ga.RAW, exist_ok=True)
        for key, fig in (("solenne_front", front), ("solenne_back", back)):
            raw = on_screen(fig)
            raw.save(os.path.join(ga.RAW, key + ".png"))
            json.dump({"seed": 0, "prompt": "cut from Garry's turnaround picture (pass 54, tools/make_solenne_static.py)",
                       "refs": [os.path.basename(SRC)], "qa": {"problems": [], "source": "reference"}, "attempt": 0},
                      open(os.path.join(ga.RAW, key + ".json"), "w", encoding="utf-8"), indent=1)
            outs.append(raw.convert("RGBA").resize((512, 512)))
    sheet = Image.new("RGBA", (sum(o.width for o in outs) + 20 * (len(outs) + 1), max(o.height for o in outs) + 40), (40, 40, 48, 255))
    x = 20
    for o in outs:
        sheet.alpha_composite(o, (x, 20))
        x += o.width + 20
    rev = os.path.join(REPO, "tools", "dl", "review")
    os.makedirs(rev, exist_ok=True)
    sheet.save(os.path.join(rev, "solenne_static.png"))
    print("solenne static: title %dx%d, badge %dx%d, raw stills %s; review tools/dl/review/solenne_static.png" % (
        title.width, title.height, badge.width, badge.height, "written" if "--no-raw" not in sys.argv else "kept"))


if __name__ == "__main__":
    main()

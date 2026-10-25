"""Pass 106 (lane DRUM): the War Drum's moment picture and its icon, cut from the drum's own painting (no new painting).

The structure's painting was made on a blue screen (tools/dl/ai_raw_props/st_war_drum_45.png, 1024 px); keyed
(artkit.key_background), cropped to the drum and written as:
  game/art/ui/drum/war_drum_big.png   the drum the time-stop moment shows in the middle of the screen (ui/DrumMoment.gd)
  game/content/structures/war_drum/war_drum_icon.png   its icon (the HUD's timed plate, the collection), 256 px, the
                                      drum's body without the stand, on transparency (it was a grey placeholder)
and prints the drum head's circle as fractions of the big picture (centre x, centre y, radius over the width): the
numbers the War Drum's `params.moment.head` carries, where the slaps' rings start.

    python tools/make_drum_moment.py [--preview <png>]
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import artkit  # noqa: E402

REPO = os.path.join(HERE, "..")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_props", "st_war_drum_45.png")
BIG = os.path.join(REPO, "game", "art", "ui", "drum", "war_drum_big.png")
ICON = os.path.join(REPO, "game", "content", "structures", "war_drum", "war_drum_icon.png")
BIG_H = 900
ICON_PX = 256


## The drum head's skin (inside its patterned ring) in the big picture, as fractions (centre x, centre y of the height,
## radius of the width), measured by eye on the keyed painting (a pale-pixel fit was thrown by the skin's shading).
HEAD = (0.524, 0.399, 0.266)


def head_circle(rgba):
    """The drum head's circle (cx, cy, r) in pixels of the big picture."""
    return HEAD[0] * rgba.width, HEAD[1] * rgba.height, HEAD[2] * rgba.width


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    img = Image.open(RAW).convert("RGB")
    keyed = artkit.key_background(img, cut_shadow=True)
    keyed = artkit.crop_alpha(keyed, pad=8)
    s = BIG_H / keyed.height
    big = keyed.resize((int(round(keyed.width * s)), BIG_H), Image.LANCZOS)
    os.makedirs(os.path.dirname(BIG), exist_ok=True)
    big.save(BIG)
    cx, cy, r = head_circle(big)
    print("big %dx%d  head centre (%.3f, %.3f) r %.3f of the width" % (big.width, big.height, cx / big.width, cy / big.height, r / big.width))
    # the icon: the drum's body (the stand cut off under the head's rim), fitted to a square
    body_bottom = int(min(big.height, cy + r * 1.35))
    body = artkit.crop_alpha(big.crop((0, 0, big.width, body_bottom)), pad=4)
    side = int(max(body.width, body.height) / 0.9)
    icon = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    icon.paste(body, ((side - body.width) // 2, (side - body.height) // 2), body)
    icon = icon.resize((ICON_PX, ICON_PX), Image.LANCZOS)
    icon = artkit.add_outline(icon, 3)
    icon.save(ICON)
    print("icon", ICON)
    if a.preview:
        sheet = Image.new("RGBA", (big.width + ICON_PX + 40, big.height), (60, 40, 40, 255))
        sheet.paste(big, (0, 0), big)
        sheet.paste(icon, (big.width + 20, 20), icon)
        from PIL import ImageDraw
        d = ImageDraw.Draw(sheet)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(0, 255, 0, 255), width=3)
        sheet.save(a.preview)


if __name__ == "__main__":
    main()

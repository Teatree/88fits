"""Measures how tall each creature's figure stands in its sprite cell and writes it into the creature's JSON as `head`
(pass 33.3): the fraction of the cell's height from its bottom edge (where the feet stand) to the top of the figure,
taken over the front idle and run frames. The game hangs a creature's badge (a crown over an Elite, a skull over a
boss, a gear over the specials) just above that line; a wide, low creature has its crown on its back, not in the air.

  python tools/measure_heads.py [id ...]      then run import_json.gd so the .tres files carry it
"""
import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CONTENT = os.path.join(REPO, "game", "content")


def head_of(strip_path, cell, cols, count):
    img = np.asarray(Image.open(strip_path).convert("RGBA"))
    best = 0.0
    for k in range(count):
        x, y = (k % cols) * cell, (k // cols) * cell
        a = img[y:y + cell, x:x + cell, 3] > 127
        rows = np.nonzero(a.max(axis=1))[0]
        if len(rows):
            best = max(best, (cell - rows.min()) / float(cell))
    return round(best, 3)


def main():
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    for t in ("enemies", "bosses"):
        base = os.path.join(CONTENT, t)
        for id_ in sorted(os.listdir(base)):
            folder = os.path.join(base, id_)
            jpath = os.path.join(folder, id_ + ".json")
            if not os.path.isfile(jpath) or (only and id_ not in only):
                continue
            d = json.load(open(jpath, encoding="utf-8"))
            sprite = os.path.join(folder, d.get("sprite", id_ + "_sprite.png"))
            anims = d.get("anims", {})
            if not os.path.isfile(sprite) or not anims:
                continue
            cell = int(d.get("frame_px", 128))
            cols = int(d.get("strip_cols", 0)) or (Image.open(sprite).width // cell)
            count = int(anims.get("idle", 0)) + int(anims.get("run", 0))
            h = head_of(sprite, cell, cols, max(count, 1))
            if h <= 0.0:
                continue
            d["head"] = h
            json.dump(d, open(jpath, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
            print("%-20s head %.3f" % (id_, h))


if __name__ == "__main__":
    main()

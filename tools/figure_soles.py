"""Pass 127: where each hero look's painted soles end, frame by frame, in its idle cycles -> game/art/ui/figure_soles.json
(core/systems/FigureSoles.gd reads it, ui/TitleScreen.gd's HeroFigure keeps his soles on the shadow's line with it).

  python tools/figure_soles.py [--check]      # writes the table; --check prints what would change and exits 1 if anything would

ship.sh runs it before the import, so a new look has its row in the next build. A sole is the last row with paint (alpha over
ALPHA_MIN) + 1, over the frame's height."""
import glob
import json
import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GAME, "art", "ui", "figure_soles.json")
ALPHA_MIN = 40
IDLES = ("idle_f", "idle_fd", "idle")


def order():
    src = open(os.path.join(GAME, "ui", "TitleStage.gd"), encoding="utf8").read()
    return eval(re.search(r"const ORDER[^=]*=\s*(\[[^\]]*\])", src, re.S).group(1))


def rows_of(path, anims, cols, frame_px, keys):
    im = np.array(Image.open(path).convert("RGBA"))[:, :, 3]
    k = 0
    out = {}
    for a in keys:
        n = int(anims.get(a, 0))
        if n and a in IDLES:
            soles = []
            for f in range(k, k + n):
                cell = im[(f // cols) * frame_px:(f // cols + 1) * frame_px, (f % cols) * frame_px:(f % cols + 1) * frame_px]
                rows = np.where(cell.max(axis=1) > ALPHA_MIN)[0]
                soles.append(round(float(rows[-1] + 1) / frame_px, 4) if rows.size else 1.0)
            out[a] = soles
        k += n
    return out


def build():
    keys = order()
    table = {}
    for jp in sorted(glob.glob(os.path.join(GAME, "content", "characters", "*", "*.json"))):
        hero = os.path.basename(os.path.dirname(jp))
        if os.path.basename(jp) != hero + ".json":
            continue
        d = json.load(open(jp, encoding="utf8"))
        looks = [(d.get("sprite") or hero + "_sprite.png", d.get("anims") or {}, d.get("strip_cols") or 0, d.get("frame_px") or 256)]
        for v in (d.get("variants") or {}).values():
            if isinstance(v, dict):
                looks.append((v.get("sprite") or looks[0][0], v.get("anims") or looks[0][1], v.get("strip_cols") or looks[0][2], v.get("frame_px") or looks[0][3]))
        for sprite, anims, cols, frame_px in looks:
            path = os.path.join(os.path.dirname(jp), sprite)
            res = "res://content/characters/%s/%s" % (hero, sprite)
            if res in table or not cols or not os.path.exists(path):
                continue
            rows = rows_of(path, anims, int(cols), int(frame_px), keys)
            if rows:
                table[res] = rows
    return table


def main():
    table = build()
    text = json.dumps(table, indent=0, sort_keys=True) + "\n"
    old = open(OUT, encoding="utf8").read() if os.path.exists(OUT) else ""
    if "--check" in sys.argv:
        print("figure_soles: %d strips, %s" % (len(table), "up to date" if old == text else "STALE"))
        return 0 if old == text else 1
    if old != text:
        with open(OUT, "w", encoding="utf8", newline="\n") as f:
            f.write(text)
    print("figure_soles: %d strips" % len(table))
    return 0


if __name__ == "__main__":
    sys.exit(main())

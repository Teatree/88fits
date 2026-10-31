"""Pass 116 (lane MAP): the three barrels cut straight from Garry's board
(_REFERENCES/2d/Barrel Variant Terrain Comparison Board.png, top row), keyed off the sand by a flood from the crop's edge
that stops at the barrels' dark ink line, cleaned (largest island, holes filled, a soft 1 px edge) and saved as
game/art/sprites/barrels/barrel_<kind>.png (bottom-centred on a square-ish canvas, the foot on the last rows).
python tools/cut_barrels.py [--preview out.png]"""
import sys
from collections import deque
from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "_REFERENCES/2d/Barrel Variant Terrain Comparison Board.png"
OUT = ROOT / "game/art/sprites/barrels"
# (kind, crop box on the board) - each holds one whole barrel and sand round it
CROPS = {"exp": (190, 95, 430, 405), "coins": (640, 85, 905, 405), "powerup": (1140, 85, 1395, 405)}
DARK = 95  # luminance at or under this is the ink line the flood stops at


def cut(img: Image.Image):
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    lum = a @ np.array([0.3, 0.59, 0.11], np.float32)
    bg = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        q.append((0, x)); q.append((h - 1, x))
    for y in range(h):
        q.append((y, 0)); q.append((y, w - 1))
    while q:
        y, x = q.popleft()
        if y < 0 or x < 0 or y >= h or x >= w or bg[y, x] or lum[y, x] <= DARK:
            continue
        bg[y, x] = True
        q.extend(((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)))
    fg = ~bg
    # the largest island only (pebbles and their dark specks out)
    lab = np.zeros((h, w), np.int32)
    best, best_n, n_lab = 0, 0, 0
    for sy in range(h):
        for sx in range(w):
            if fg[sy, sx] and lab[sy, sx] == 0:
                n_lab += 1
                cnt = 0
                st = [(sy, sx)]
                lab[sy, sx] = n_lab
                while st:
                    y, x = st.pop()
                    cnt += 1
                    for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                        if 0 <= yy < h and 0 <= xx < w and fg[yy, xx] and lab[yy, xx] == 0:
                            lab[yy, xx] = n_lab
                            st.append((yy, xx))
                if cnt > best_n:
                    best, best_n = n_lab, cnt
    mask = lab == best
    # the dark shadow touching the foot is ink-dark only at its core: drop rows of mask pixels that are sand-hued and
    # dim (the cast shadow), keeping the ink (near-black) and the barrel's own colours
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    shadowish = (lum > 60) & (r > g) & (g > b * 1.15) & ((r - b) > 40) & (lum < 150) & False
    mask &= ~shadowish
    # close small bites the flood took where the gold rim has no ink line (MaxFilter then MinFilter), then fill holes
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.MinFilter(11))
    m = m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out = img.convert("RGBA")
    out.putalpha(m)
    bb = m.point(lambda v: 255 if v > 20 else 0).getbbox()
    return out.crop(bb)


def main():
    board = Image.open(SRC)
    OUT.mkdir(parents=True, exist_ok=True)
    cuts = {}
    for kind, box in CROPS.items():
        c = cut(board.crop(box))
        side = max(c.width, c.height) + 8
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(c, ((side - c.width) // 2, side - c.height - 2), c)
        canvas.save(OUT / f"barrel_{kind}.png")
        cuts[kind] = canvas
        print(kind, c.size, "->", OUT / f"barrel_{kind}.png")
    if "--preview" in sys.argv:
        p = sys.argv[sys.argv.index("--preview") + 1]
        W = sum(c.width for c in cuts.values()) + 40
        H = max(c.height for c in cuts.values()) + 20
        for bgc, y0 in (((60, 200, 60), 0), ((230, 200, 140), 1)):
            pass
        sheet = Image.new("RGB", (W, H * 2), (60, 200, 60))
        sheet.paste((230, 200, 140), (0, H, W, H * 2))
        x = 10
        for c in cuts.values():
            sheet.paste(c, (x, 10), c); sheet.paste(c, (x, H + 10), c); x += c.width + 10
        sheet.save(p)


if __name__ == "__main__":
    main()

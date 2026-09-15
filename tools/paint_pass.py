"""Painted-look post-process for every generated sprite strip and icon (design bible section 15, stage 2/3).

For each game/content/**/<id>_sprite.png and <id>_icon.png:
  1. vertical shading inside the silhouette (top lighter, bottom darker) plus a soft top-left highlight,
  2. a few random "brush dabs" of slightly shifted colour inside the silhouette,
  3. a thick dark outline by dilating the alpha mask,
  4. a faint drop shadow offset down-right (icons only).
Frame cells are processed independently so shading stays per frame. Idempotent when run with --clean
first (it regenerates from the flat versions kept in *_flat.png).
Run: python tools/paint_pass.py
"""
import glob, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "content")
OUTLINE = np.array([0.13, 0.08, 0.10], np.float32)
rng = np.random.default_rng(7)


def dilate(mask, w):
    out = mask.copy()
    for dy in range(-w, w + 1):
        for dx in range(-w, w + 1):
            if dx * dx + dy * dy > w * w + 1:
                continue
            out |= np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
    return out


def paint_cell(cell, is_icon):
    h, w, _ = cell.shape
    rgb = cell[..., :3].astype(np.float32) / 255.0
    a = cell[..., 3].astype(np.float32) / 255.0
    mask = a > 0.5
    if not mask.any():
        return cell
    ys, xs = np.nonzero(mask)
    y0, y1 = ys.min(), ys.max()
    x0, x1 = xs.min(), xs.max()
    # 1. vertical shade within the silhouette's own bounds
    grad = np.linspace(1.16, 0.78, max(y1 - y0 + 1, 2), dtype=np.float32)
    shade = np.ones((h, w), np.float32)
    shade[y0:y1 + 1, :] = grad[:, None]
    hx, hy = x0 + (x1 - x0) * 0.35, y0 + (y1 - y0) * 0.3
    yy, xx = np.mgrid[0:h, 0:w]
    hl = np.clip(1.0 - np.sqrt((xx - hx) ** 2 + (yy - hy) ** 2) / (0.35 * max(x1 - x0, y1 - y0) + 1), 0, 1)
    rgb = rgb * (shade * (1.0 + 0.14 * hl))[..., None]
    # 2. brush dabs
    for _ in range(18 if not is_icon else 10):
        cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
        r = rng.uniform(0.04, 0.10) * max(x1 - x0, y1 - y0)
        dab = np.clip(1.0 - np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / max(r, 1), 0, 1) ** 1.5
        tint = rng.uniform(0.9, 1.1)
        rgb = rgb * (1.0 - dab * 0.35)[..., None] + (rgb * tint) * (dab * 0.35)[..., None]
    rgb = np.clip(rgb, 0, 1)
    # 3. outline by dilation
    ow = max(2, int(round(min(h, w) / 56)))
    ring = dilate(mask, ow) & ~mask
    out_rgb = rgb.copy()
    out_a = a.copy()
    out_rgb[ring] = OUTLINE
    out_a[ring] = 1.0
    # 4. drop shadow for icons
    if is_icon:
        sh = np.roll(np.roll(mask | ring, 5, axis=0), 5, axis=1) & ~(mask | ring)
        out_rgb[sh] = np.array([0.08, 0.05, 0.06], np.float32)
        out_a[sh] = 0.45
    out = np.concatenate([np.clip(out_rgb * 255, 0, 255), np.clip(out_a * 255, 0, 255)[..., None]], axis=2).astype(np.uint8)
    return out


def process(path, is_icon):
    # AI-painted items carry an <id>_ai.json marker; they are already painted and outlined.
    base = os.path.basename(path)
    item_id = base.replace("_sprite.png", "").replace("_icon.png", "")
    if os.path.exists(os.path.join(os.path.dirname(path), item_id + "_ai.json")):
        return
    flat = path.replace(".png", "_flat.png")
    if os.path.exists(flat):
        src = Image.open(flat).convert("RGBA")
    else:
        src = Image.open(path).convert("RGBA")
        src.save(flat)
    arr = np.asarray(src).copy()
    h, w, _ = arr.shape
    cell = h  # square frames in a horizontal strip
    n = max(1, w // cell)
    for k in range(n):
        arr[:, k * cell:(k + 1) * cell] = paint_cell(arr[:, k * cell:(k + 1) * cell], is_icon)
    Image.fromarray(arr, "RGBA").save(path)


def main():
    n = 0
    for path in glob.glob(os.path.join(ROOT, "**", "*_sprite.png"), recursive=True):
        process(path, False)
        n += 1
    for path in glob.glob(os.path.join(ROOT, "**", "*_icon.png"), recursive=True):
        process(path, True)
        n += 1
    print("paint_pass: painted %d images" % n)


if __name__ == "__main__":
    main()

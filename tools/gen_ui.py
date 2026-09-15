"""AI-painted UI skin for 88fits, through the same ComfyUI server as the sprites (Flux.2 Klein).

The idea: ask the model for one *sheet* of UI parts in the game's style on a flat magenta screen, key the screen
out, cut the sheet into its parts, and save each part as a PNG plus a 9-slice recipe. Godot then draws buttons and
panels with a StyleBoxTexture (texture margins = the 9-slice recipe), so the painted parts stretch to any size.

    python tools/gen_ui.py                 # render every sheet, key, cut, write game/ui/skin/
    python tools/gen_ui.py --seed=7        # another take
    python tools/gen_ui.py --only=buttons  # one sheet
    python tools/gen_ui.py --fake          # no server: synthetic sheets, exercises the keying/cutting only

Wiring a part into the game (by hand, once the parts look right; nothing here touches UiKit):
    var sb := StyleBoxTexture.new()
    sb.texture = load("res://ui/skin/button_gold.png")
    sb.texture_margin_left = 40   # from skin.json, "margin" = the un-stretched corner size in px
    ... right/top/bottom likewise
    button.add_theme_stylebox_override("normal", sb)

Reads tools/comfy.py (server address, Klein builder) and tools/artkit.py (keying, components).
"""
import argparse
import io
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "ui", "skin")
RAW = os.path.join(ROOT, "tools", "dl", "ui_raw")
MAGENTA = (255, 0, 255)

STYLE = ("clean mobile game UI kit in the style of Survivor.io and Archero, glossy rounded shapes with a soft "
         "bevel and a darker bottom edge, thick dark navy outline, flat vector, high contrast, "
         "no text, no letters, no logos, isolated parts spaced far apart on a flat solid magenta background, "
         "nothing overlaps, straight-on view, 2D")

# Each sheet is one render; `parts` names the components left-to-right, top-to-bottom, biggest first is not
# assumed: components are sorted by their bounding box (rows, then columns).
SHEETS = {
    "buttons": {
        "prompt": "a set of six wide rounded rectangle game buttons in a 2 by 3 grid, gold yellow, sky blue, "
                  "green, red, purple, dark navy, each with a glossy highlight and a darker bottom edge, " + STYLE,
        "parts": ["button_gold", "button_blue", "button_green", "button_red", "button_purple", "button_navy"],
        "margin": 0.38,   # fraction of the part height kept un-stretched at each corner
    },
    "panels": {
        "prompt": "two large empty rounded rectangle game panels, dark navy with a lighter blue rim and a subtle "
                  "inner glow, one tall one wide, " + STYLE,
        "parts": ["panel_tall", "panel_wide"],
        "margin": 0.2,
    },
    "frames": {
        "prompt": "four square item slot frames in a row, gold, purple, blue, grey, each an empty rounded square "
                  "with a thick rim and a dark inset, then four round slot frames in the same colours below, " + STYLE,
        "parts": ["slot_gold", "slot_purple", "slot_blue", "slot_grey", "ring_gold", "ring_purple", "ring_blue", "ring_grey"],
        "margin": 0.3,
    },
    "bars": {
        "prompt": "three long progress bars stacked vertically: a purple XP bar with a dark trough, a red boss "
                  "health bar, a green player health bar, each with a glossy top highlight and rounded ends, " + STYLE,
        "parts": ["bar_xp", "bar_boss", "bar_hp"],
        "margin": 0.45,
    },
}


def render(name, prompt, seed):
    """One Klein render at 1024 x 1024 on a magenta screen; returns an RGB PIL image."""
    import comfy
    os.makedirs(RAW, exist_ok=True)
    g = comfy.klein(prompt + ", solid magenta background #FF00FF", seed, 1024, 1024, [], 4, 1.0, "ui_" + name,
                    negative="text, letters, watermark, photo, 3d render, gradient background, overlapping parts")
    pngs, secs = comfy.run(g)
    img = Image.open(io.BytesIO(pngs[0])).convert("RGB")
    img.save(os.path.join(RAW, "%s_%d.png" % (name, seed)))
    print("  rendered %s in %.0fs" % (name, secs))
    return img


def fake_sheet(name):
    """Synthetic sheet so the keying and cutting can be exercised without the server."""
    img = Image.new("RGB", (1024, 1024), MAGENTA)
    d = ImageDraw.Draw(img)
    n = len(SHEETS[name]["parts"])
    cols = 2 if n in (2, 4, 6) else 4 if n == 8 else 1
    rows = (n + cols - 1) // cols
    cw, ch = 1024 // cols, 1024 // rows
    colours = [(255, 181, 46), (76, 201, 255), (90, 214, 106), (255, 95, 107), (139, 108, 255), (43, 54, 90), (120, 120, 130), (200, 200, 200)]
    for i in range(n):
        r, c = divmod(i, cols)
        x0, y0 = c * cw + 60, r * ch + 60
        x1, y1 = (c + 1) * cw - 60, (r + 1) * ch - 60
        rad = min(x1 - x0, y1 - y0) // 4
        d.rounded_rectangle((x0, y0, x1, y1), rad, fill=colours[i % len(colours)], outline=(20, 26, 43), width=8)
    return img


def key_magenta(img):
    """Magenta screen to alpha with a little despill; artkit's keyer samples the background from the top edge."""
    return artkit.key_background(img, despill=0.05, despill_mix=0.3)


def components(rgba, min_area=1500):
    """Bounding boxes of the opaque blobs, sorted in reading order (row bands, then x)."""
    import numpy as np
    a = np.array(rgba)[:, :, 3] > 24
    h, w = a.shape
    seen = np.zeros_like(a, dtype=bool)
    boxes = []
    for y in range(h):
        row = a[y]
        for x in np.nonzero(row & ~seen[y])[0]:
            # flood fill (iterative) from (x, y)
            stack = [(y, x)]
            seen[y, x] = True
            ys, xs = [], []
            while stack:
                cy, cx = stack.pop()
                ys.append(cy)
                xs.append(cx)
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and a[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(ys) >= min_area:
                boxes.append((min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    # reading order: group into row bands by vertical overlap
    boxes.sort(key=lambda b: b[1])
    bands = []
    for b in boxes:
        for band in bands:
            if b[1] < band["bottom"] - 10:
                band["boxes"].append(b)
                band["bottom"] = max(band["bottom"], b[3])
                break
        else:
            bands.append({"boxes": [b], "bottom": b[3]})
    ordered = []
    for band in bands:
        ordered += sorted(band["boxes"], key=lambda b: b[0])
    return ordered


def cut(rgba, sheet, name, seed):
    """Save each part and its 9-slice margin; returns the recipe rows."""
    parts = sheet["parts"]
    boxes = components(rgba)
    if len(boxes) != len(parts):
        print("  %s: expected %d parts, found %d blobs (seed %d); saving what was found as %s_partN" % (name, len(parts), len(boxes), seed, name))
        parts = ["%s_part%d" % (name, i) for i in range(len(boxes))]
    rows = []
    for pname, box in zip(parts, boxes):
        part = rgba.crop(box)
        part.save(os.path.join(OUT, pname + ".png"))
        m = int(min(part.size) * sheet["margin"])
        rows.append({"name": pname, "file": pname + ".png", "size": list(part.size), "margin": m, "sheet": name, "seed": seed})
        print("  %-14s %4d x %4d  margin %d" % (pname, part.size[0], part.size[1], m))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--only", default="")
    ap.add_argument("--fake", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    recipe = []
    for name, sheet in SHEETS.items():
        if a.only and a.only != name:
            continue
        print("sheet", name)
        img = fake_sheet(name) if a.fake else render(name, sheet["prompt"], a.seed)
        rgba = key_magenta(img)
        rgba.save(os.path.join(OUT, "_sheet_%s.png" % name))
        recipe += cut(rgba, sheet, name, a.seed)
    with open(os.path.join(OUT, "skin.json"), "w", encoding="utf-8") as f:
        json.dump({"parts": recipe, "note": "9-slice: StyleBoxTexture with texture_margin_* = margin"}, f, indent=2)
    print("wrote", len(recipe), "parts to", OUT)


if __name__ == "__main__":
    main()

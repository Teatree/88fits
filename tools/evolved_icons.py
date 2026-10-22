#!/usr/bin/env python3
"""Pass 95 (lane PASSIVES): the Evolved icon of every passive item (Garry: "use the same icon art with a white outline
around the 'hero' of the image, and that displayed over a black background").

    python tools/evolved_icons.py [--only cake,beer] [--px 6] [--force] [--sheet tools/dl/p95/PASSIVES/evolved_review.png]

For each passive item (content/passives/<id>, `line` false, no `evolves_from`) with <id>_icon.png (256 px RGBA, the
subject on a transparent ground): the subject's alpha, binarised, grown by `px` (2.5% of the icon: 6 px) and softened
a touch, painted white, the icon laid over it -> <id>_icon_evolved.png, still on a transparent ground: the black is the
Evolved plate itself (W.EVOLVED_FILL, the ink plate ringed in brass that every evolution wears), so the icon sits on
it with the plate's own rounded corners. The game shows it on the item's Evolved rung (PassiveDef.icon_at); the
Collection keeps the base icon. The review sheet shows every item twice: its base icon on its rarity's plate and the
Evolved icon on the dark plate, as the cards draw them. Then `--import` (and tools/lossy_imports.py, --import again)
and tools/import_json.gd for the items, so the .tres carries the texture.
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASSIVES = os.path.join(REPO, "game", "content", "passives")
ICON_PX = 256
OUTLINE_FRAC = 0.025          # of the icon's side: 6 px on 256
ALPHA_CUT = 48                # where the painted subject ends (the keyer's soft halo is below it)
# W.gd's plate colours (pass 47b, 53) and the evolved plate (INK) with its brass ring
PLATE = {"common": "#d2cfc7", "uncommon": "#8cc97a", "rare": "#6b9fd8", "epic": "#a585c8", "legendary": "#e0a060"}
INK, BRASS, PAPER = "#241b14", "#c9932f", "#f3e6c8"


def items(only=None):
    """[(id, dir, json)] of every passive item (not a line, not an evolved form), sorted."""
    out = []
    for d in sorted(os.listdir(PASSIVES)):
        f = os.path.join(PASSIVES, d, d + ".json")
        if not os.path.isfile(f):
            continue
        with open(f, "r", encoding="utf-8") as fh:
            j = json.load(fh)
        # pass 100 (lane SMALL): a one-shot item (`single`) has no Evolved rung, so no Evolved icon
        if j.get("line") or j.get("evolves_from") or j.get("single"):
            continue
        if only and d not in only:
            continue
        out.append((d, os.path.join(PASSIVES, d), j))
    return out


def evolved_icon(icon, px=None):
    """The Evolved icon of an RGBA icon: a white outline `px` wide round its subject, the icon over it."""
    icon = icon.convert("RGBA")
    if px is None:
        px = max(1, int(round(icon.width * OUTLINE_FRAC)))
    a = icon.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
    grown = a.filter(ImageFilter.MaxFilter(2 * px + 1))
    # a soft edge: the stair-steps of the dilation blurred a touch, the inside kept solid
    soft = grown.filter(ImageFilter.GaussianBlur(0.9))
    line = Image.new("RGBA", icon.size, (255, 255, 255, 255))
    line.putalpha(soft)
    line.alpha_composite(icon)
    return line


def plate(fill, px, ring=None, radius=None):
    """A card plate as WPlate draws it: a rounded square in `fill` with an ink border, a brass ring inside for an evolved one."""
    radius = radius or int(px * 0.08)
    im = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    dr.rounded_rectangle((0, 0, px - 1, px - 1), radius=radius, fill=fill, outline=INK, width=max(2, px // 36))
    if ring:
        w = max(2, int(round(px * 0.04)))
        b = max(2, px // 36)
        dr.rounded_rectangle((b, b, px - 1 - b, px - 1 - b), radius=max(1, radius - b), outline=ring, width=w)
    return im


def on_plate(icon, fill, px, ring=None, frac=0.68):
    p = plate(fill, px, ring)
    side = int(px * frac)
    ic = icon.resize((side, side), Image.LANCZOS)
    p.alpha_composite(ic, ((px - side) // 2, (px - side) // 2))
    return p


def review_sheet(rows, path, cell=150):
    """rows: [(id, rarity, base_icon, evolved_icon)]; two plates a row cell, 4 items a row, the id under them."""
    cols = 4
    pad, label_h = 14, 22
    w_cell = cell * 2 + pad * 3
    h_cell = cell + label_h + pad
    n_rows = (len(rows) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * w_cell, n_rows * h_cell + pad), (62, 54, 48, 255))
    dr = ImageDraw.Draw(sheet)
    for i, (pid, rarity, base, evo) in enumerate(rows):
        x0 = (i % cols) * w_cell + pad
        y0 = (i // cols) * h_cell + pad
        sheet.alpha_composite(on_plate(base, PLATE.get(rarity, PLATE["common"]), cell), (x0, y0))
        sheet.alpha_composite(on_plate(evo, INK, cell, ring=BRASS), (x0 + cell + pad, y0))
        dr.text((x0, y0 + cell + 4), "%s (%s -> Evolved)" % (pid, rarity), fill=PAPER)
    sheet.save(path)
    return path


def main(argv=None):
    ap = argparse.ArgumentParser(description="the Evolved icons of the passive items (pass 95)")
    ap.add_argument("--only", default="", help="item ids, comma-separated (default: every passive item)")
    ap.add_argument("--px", type=int, default=0, help="the outline's width in pixels (default 2.5%% of the icon: 6)")
    ap.add_argument("--force", action="store_true", help="write an Evolved icon that exists already")
    ap.add_argument("--sheet", default=os.path.join(REPO, "tools", "dl", "p95", "PASSIVES", "evolved_review.png"), help="the review sheet (\"\" for none)")
    args = ap.parse_args(argv)
    only = [s for s in args.only.split(",") if s] or None
    rows, made, kept, missing = [], [], [], []
    for pid, d, j in items(only):
        src = os.path.join(d, str(j.get("icon", pid + "_icon.png")))
        dst = os.path.join(d, pid + "_icon_evolved.png")
        if not os.path.isfile(src):
            missing.append(pid)
            continue
        base = Image.open(src).convert("RGBA")
        if os.path.isfile(dst) and not args.force:
            evo = Image.open(dst).convert("RGBA")
            kept.append(pid)
        else:
            evo = evolved_icon(base, args.px or None)
            evo.save(dst)
            made.append(pid)
        rows.append((pid, str(j.get("rarity", "common")), base, evo))
    if args.sheet and rows:
        os.makedirs(os.path.dirname(args.sheet), exist_ok=True)
        review_sheet(rows, args.sheet)
    print("evolved_icons: %d made, %d kept (--force repaints), %d without a base icon%s%s" % (
        len(made), len(kept), len(missing), (": " + ", ".join(missing)) if missing else "", ("; sheet " + args.sheet) if args.sheet and rows else ""))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())

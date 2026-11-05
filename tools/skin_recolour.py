"""Pass 126 (lane SKINS; Garry: "Make a skin for every hero"): a hero skin as a recolour of a finished look: the same
passes over its whole strip, its round badge and its title cut-out, so the look stays a whole. No model runs. The passes
live in the look's recipe, so a later run makes the same files:

    "DRI-C": {"recipe": {"method": "recolour", "recolour": {"from": "DRI-A", "passes": [
        {"mode": "lift", "ranges": [[15, 50]], "to": 40, "set_sat": 0.22, "v_lo": 0.42, "v_hi": 0.92, "min_sat": 0.25,
         "min_val": 0.12, "src_hi": 0.6, "max_val": 0.62}
    ]}}}

    python tools/skin_recolour.py --id drifter --code DRI-C              # strip, badge, title; writes the look's entry
    python tools/skin_recolour.py --id drifter --code DRI-C --preview    # only tools/dl/p126/SKINS/review/<id>_<letter>_rec.png
    python tools/skin_recolour.py --id drifter --code DRI-B --polish     # a walked look's strip: its recipe's `polish` passes, in place

A pass is artkit's: `mode` "hue" (remap_hues: ranges, to, sat, min_sat, max_sat), "tint" (tint_range: ranges, to, set_sat,
value, min_sat, max_sat, min_val) or "lift" (lift_range: ranges, to, set_sat | sat, v_lo, v_hi, gamma, min_sat, max_sat,
min_val, src_hi, soft, hue_soft, to_dark, mass, grow, mass_sat, keep_edge). Gates any pass may carry: `max_val` leaves
pixels brighter than it as they were (a coat's browns, not the face's); `only` limits a pass to "strip", "icon" or "title" (a
badge and a cut-out are paintings of their own and can need other numbers); `rects` / `keep_rects` limit it to, or spare,
places in the picture (fractions [x0, y0, x1, y1]: the face in a badge, the hands in a cut-out). The look's entry takes the source's
anims, strip_cols and fps; the files are <id>_sprite_<letter>.png, <id>_icon_<letter>.png, hero_<id>_<letter>.png.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import artkit  # noqa: E402

CHARS = os.path.join(REPO, "game", "content", "characters")
TITLES = os.path.join(REPO, "game", "art", "ui", "wanted")
ORDER = ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd",
         "hit_f", "hit_s", "hit_bd", "hit_fd"]


def letter(code):
    return code.split("-")[-1].lower()


def _one(im, p):
    """One pass on an RGBA picture, its gate applied."""
    mode = str(p.get("mode", "hue"))
    r = p.get("ranges", [[0, 360]])
    if mode == "lift":
        out = artkit.lift_range(im, r, float(p["to"]), p.get("set_sat"), float(p.get("sat", 1.0)), float(p.get("v_lo", 0.5)), float(p.get("v_hi", 1.0)),
                                float(p.get("gamma", 1.0)), float(p.get("min_sat", 0.0)), float(p.get("max_sat", 1.01)), float(p.get("min_val", 0.0)),
                                float(p.get("src_hi", 1.0)), float(p.get("soft", 0.04)), float(p.get("hue_soft", 0.0)), p.get("to_dark"),
                                int(p.get("mass", 0)), p.get("grow"), p.get("mass_sat"), int(p.get("keep_edge", 0)))
    elif mode == "tint":
        out = artkit.tint_range(im, r, float(p["to"]), float(p.get("set_sat", 0.55)), float(p.get("value", 0.6)), float(p.get("min_sat", 0.06)),
                                float(p.get("max_sat", 0.55)), float(p.get("min_val", 0.3)))
    else:
        out = artkit.remap_hues(im, r, float(p["to"]), float(p.get("sat", 1.0)), float(p.get("min_sat", 0.2)), float(p.get("max_sat", 1.01)))
    if p.get("max_val") is None and not p.get("rects") and not p.get("keep_rects"):
        return out
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    b = np.asarray(out.convert("RGBA")).astype(np.float32)
    keep = np.zeros(a.shape[:2], dtype=np.float32)
    # the gate: brighter than max_val stays as it was, blended over a small band so no seam shows
    if p.get("max_val") is not None:
        v = a[..., :3].max(axis=2) / 255.0
        mv = float(p["max_val"])
        keep = np.clip((v - (mv - 0.03)) / 0.06, 0.0, 1.0)
    # the places: only inside `rects` / never inside `keep_rects`, fractions of the picture [x0, y0, x1, y1], feathered
    h, w = a.shape[:2]

    def _mask(rects):
        m = Image.new("L", (w, h), 0)
        dr = ImageDraw.Draw(m)
        for r in rects:
            dr.rectangle([r[0] * w, r[1] * h, r[2] * w, r[3] * h], fill=255)
        return np.asarray(m.filter(ImageFilter.GaussianBlur(max(w, h) * 0.006))).astype(np.float32) / 255.0

    if p.get("rects"):
        keep = np.maximum(keep, 1.0 - _mask(p["rects"]))
    if p.get("keep_rects"):
        keep = np.maximum(keep, _mask(p["keep_rects"]))
    k3 = keep[..., None]
    return Image.fromarray(np.clip(a * k3 + b * (1.0 - k3), 0, 255).astype(np.uint8), "RGBA")


def apply_passes(im, passes, what):
    out = im
    for p in passes:
        if p.get("only") and str(p["only"]) != what:
            continue
        out = _one(out, p)
    return out


def source_files(d, hid, code):
    """(strip, icon, title) names of look `code` (the hero's own for a base look without files of its own)."""
    e = (d.get("variants") or {}).get(code) or {}
    strip = e.get("sprite") or d.get("sprite") or hid + "_sprite.png"
    icon = e.get("icon") or d.get("icon") or hid + "_icon.png"
    title = e.get("title") or "hero_%s.png" % hid
    return strip, icon, title


def frame_sheet(strip, anims, cols, cell=256):
    """A look at a recoloured strip: every view's idle and two run frames, the hit, the death, the cheer on sand."""
    idx, k = {}, 0
    for a in ORDER:
        n = int(anims.get(a, 0) or 0)
        if n:
            idx[a] = k
        k += n
    want = []
    for a, offs in (("idle_f", [0]), ("run_f", [6, 18]), ("hit_f", [0]), ("idle_fd", [0]), ("run_fd", [6]), ("idle_s", [0]), ("run_s", [6]), ("hit_s", [0]),
                    ("idle_bd", [0]), ("run_bd", [6]), ("idle", [0]), ("run", [6, 18]), ("hit", [0]), ("die", [1, 3]), ("cheer", [0])):
        if a in idx:
            want += [idx[a] + o for o in offs]
    n_col = 9
    out = Image.new("RGB", (cell * n_col, cell * ((len(want) + n_col - 1) // n_col)), (150, 125, 90))
    for j, i in enumerate(want):
        x, y = (i % cols) * cell, (i // cols) * cell
        f = strip.crop((x, y, x + cell, y + cell))
        out.paste(f, ((j % n_col) * cell, (j // n_col) * cell), f)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--id", required=True)
    ap.add_argument("--code", required=True)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--polish", action="store_true", help="the look's own walked strip, its recipe's `polish` passes, in place")
    a = ap.parse_args()
    folder = os.path.join(CHARS, a.id)
    jp = os.path.join(folder, a.id + ".json")
    d = json.load(open(jp, encoding="utf-8"))
    e = (d.get("variants") or {}).get(a.code)
    if not isinstance(e, dict):
        raise SystemExit("skin_recolour: %s has no look %s" % (a.id, a.code))
    if a.polish:
        # a painted look's last step: the hues the video model smeared on (a black coat gone olive, yellow rims on grey trousers);
        # run it again after every gen_art walk of the look, which writes the strip afresh
        sp = os.path.join(folder, str(e["sprite"]))
        apply_passes(Image.open(sp).convert("RGBA"), (e.get("recipe") or {}).get("polish") or [], "strip").save(sp)
        print("skin_recolour: polished " + str(e["sprite"]))
        return
    rec = (e.get("recipe") or {}).get("recolour") or {}
    src_code = str(rec.get("from") or d.get("variant") or "")
    passes = rec.get("passes") or []
    if not passes:
        raise SystemExit("skin_recolour: %s %s has no recolour passes in its recipe" % (a.id, a.code))
    src_e = (d.get("variants") or {}).get(src_code) or {}
    strip_n, icon_n, title_n = source_files(d, a.id, src_code)
    anims = src_e.get("anims") or d.get("anims") or {}
    cols = int(src_e.get("strip_cols") or d.get("strip_cols") or 62)
    fps = src_e.get("fps") or d.get("fps") or {}
    let = letter(a.code)
    strip = apply_passes(Image.open(os.path.join(folder, strip_n)).convert("RGBA"), passes, "strip")
    icon = apply_passes(Image.open(os.path.join(folder, icon_n)).convert("RGBA"), passes, "icon")
    title = None
    tp = os.path.join(TITLES, title_n)
    if os.path.isfile(tp):
        title = apply_passes(Image.open(tp).convert("RGBA"), passes, "title")
    if a.preview:
        rd = os.path.join(REPO, "tools", "dl", "p126", "SKINS", "review")
        os.makedirs(rd, exist_ok=True)
        sh = frame_sheet(strip, anims, cols)
        ih = sh.height
        extra = 256 + (int(title.width * ih / title.height) if title else 0)
        out = Image.new("RGB", (sh.width + extra, ih), (150, 125, 90))
        out.paste(sh, (0, 0))
        out.paste(icon.resize((256, 256), Image.LANCZOS), (sh.width, 0), icon.resize((256, 256), Image.LANCZOS))
        if title:
            t2 = title.resize((extra - 256, ih), Image.LANCZOS)
            out.paste(t2, (sh.width + 256, 0), t2)
        p = os.path.join(rd, "%s_%s_rec.png" % (a.id, let))
        out.save(p)
        print("skin_recolour: preview " + p)
        return
    names = {"sprite": "%s_sprite_%s.png" % (a.id, let), "icon": "%s_icon_%s.png" % (a.id, let)}
    strip.save(os.path.join(folder, names["sprite"]))
    icon.save(os.path.join(folder, names["icon"]))
    if title:
        names["title"] = "hero_%s_%s.png" % (a.id, let)
        title.save(os.path.join(TITLES, names["title"]))
    cur = json.load(open(jp, encoding="utf-8"))
    entry = cur.setdefault("variants", {}).setdefault(a.code, {})
    entry.update(names)
    entry.update({"anims": anims, "strip_cols": cols, "fps": fps})
    json.dump(cur, open(jp, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    print("skin_recolour: %s %s -> %s" % (a.id, a.code, ", ".join(names.values())))


if __name__ == "__main__":
    main()

"""Pass 130 (Garry: "What I wanted is just the same thing but under a different seed and potentially with fixes ... five
variations, just using a different seed but ultimately trying to recreate the same thing. You can add smallish variations
to them but they have to be really small ... five variations of all the existing art assets. When you look at something
like Joshua Tree, you seem to be grouping all 4 into 1, I want variations for each please."): five re-draws of EVERY
scenery painting in the game (each kind's own painting and each of its variants on its own), candidates only. Nothing
here writes into game/ except --install.

How a re-draw is made: Flux.2 Klein with the style anchor and the painting itself (on its screen colour) as references,
asked for the same object again; the seed is the only thing that changes between the five. FIXES holds the one-line
repair a painting needs (dead_shrub_b: "it's not clear where it begins and where it ends"). The finish is the game's own
(gen_prop_variants.finish), then the candidate's saturation and brightness are matched to the painting it re-draws (the
reference is already muted once, so a second mute would grey it).

  python tools/gen_env_reseed.py --only dead_shrub_b [--seeds 5] [--force]   # one painting: ONE PROCESS A PAINTING
  python tools/gen_env_reseed.py --list                                       # every painting it covers
  python tools/gen_env_reseed.py --sheets                                     # the contact sheets again, nothing painted
  python tools/gen_env_reseed.py --install joshua_tree_c=3 ... [--dry-run]    # LATER: candidate k replaces the painting
      # (the old one kept in tools/dl/p130/ENV/replaced/); then python tools/prop_shadows.py --only <ids> and --import

Files (tools/dl/p130/ENV, git-ignored): raw/<id>_s<k>.png, cands/<id>_s<k>.png, sheets/sheet_<n>.png, renders.log
"""
import argparse
import io
import json
import os
import shutil
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ENV = os.path.join(REPO, "tools", "dl", "p130", "ENV")
RAWS = os.path.join(ENV, "raw")
CANDS = os.path.join(ENV, "cands")
SHEETS = os.path.join(ENV, "sheets")
PROPS = os.path.join(REPO, "game", "art", "sprites", "props")
SAND = (214, 188, 145)
SEED0 = 41000

# the one-line repair a painting gets on top of "the same thing again"
FIXES = {
    "dead_shrub_b": "ONE single dead shrub shaped like a dome on one short woody stem: every twig joined to that stem, the lowest twigs "
                    "ending above the floor line, a tidy rounded readable outline, clear where the shrub begins and where it ends, no "
                    "loose twigs, no sticks lying on the floor, no debris",
}

# a painting whose re-draws wandered when the painter was only shown it (a lost sand patch, another tree): the painting is
# also the start of the re-draw (img2img at this denoise), which holds the composition
INIT = {"skull_small": 0.8, "bones": 0.8, "joshua_tree_b": 0.8, "joshua_tree_d": 0.8}

_mods = None


def painter():
    global _mods
    if _mods is None:
        keep = sys.argv
        sys.argv = [keep[0]]
        sys.path.insert(0, HERE)
        import gen_prop_variants as gpv
        import gen_props as gp
        import gen_art as ga
        import comfy
        sys.argv = keep
        _mods = (gpv, gp, ga, comfy)
    return _mods


def paintings():
    """[(id, subject, cell, screen)] for every scenery painting the game can lay (no structure, nothing hidden)."""
    gpv, gp, _, _ = painter()
    manifest = json.load(open(os.path.join(PROPS, "props.json"), encoding="utf-8"))
    env = {r["id"]: r for r in json.load(open(os.path.join(HERE, "env_variations.json"), encoding="utf-8"))["rows"]}
    out = []
    for id_, row in manifest.items():
        if id_.startswith("st_") or row.get("hidden"):
            continue
        base = row.get("variant_of") or id_
        if id_ in gp.PROPS:
            subject, screen = gp.PROPS[id_][0], gp.PROPS[id_][5]
        elif id_ in gpv.VARIANTS:
            subject, screen = gpv.VARIANTS[id_][2], gpv.VARIANTS[id_][7]
        elif id_ in env:
            subject = env[id_]["subject"]
            screen = gp.PROPS[base][5] if base in gp.PROPS else gpv.VARIANTS[base][7]
        else:
            continue
        out.append((id_, subject, int(row["cell"]), screen))
    return out


def _lab(rgb):
    """Linear-ish opponent space (Ruderman's l-alpha-beta without the log): cheap, and enough for a mean / spread match."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return np.stack([(r + g + b) / 3.0, (r - g), (r + g - 2.0 * b) / 2.0], -1)


def _rgb(lab):
    l, a, b2 = lab[..., 0], lab[..., 1], lab[..., 2]
    b = l - 2.0 * b2 / 3.0
    r = (3.0 * l - b + a) / 2.0
    g = r - a
    return np.stack([r, g, b], -1)


def match_tone(cand, like):
    """The candidate's colours brought to the painting it re-draws: each opponent channel's mean and spread over the opaque
    pixels matched to the painting's (the spread's gain clamped: a nudge, never a repaint). The reference was muted once
    already and every seed drifts a little warmer or paler; this keeps a re-draw in its painting's own colours."""
    c = np.asarray(cand.convert("RGBA")).astype(float) / 255.0
    l = np.asarray(like.convert("RGBA")).astype(float) / 255.0
    cm, lm = c[..., 3] > 0.5, l[..., 3] > 0.5
    if cm.sum() < 16 or lm.sum() < 16:
        return cand
    cl, ll = _lab(c[..., :3]), _lab(l[..., :3])
    out = cl.copy()
    for ch in range(3):
        mu_c, sd_c = cl[..., ch][cm].mean(), cl[..., ch][cm].std()
        mu_l, sd_l = ll[..., ch][lm].mean(), ll[..., ch][lm].std()
        k = min(max(sd_l / max(sd_c, 1e-4), 0.7), 1.4)
        out[..., ch] = (cl[..., ch] - mu_c) * k + mu_l
    c[..., :3] = np.clip(_rgb(out), 0.0, 1.0)
    return Image.fromarray((c * 255.0 + 0.5).astype("uint8"), "RGBA")


def paint(id_, subject, cell, screen, seeds, force):
    gpv, gp, ga, comfy = painter()
    for d in (RAWS, CANDS):
        os.makedirs(d, exist_ok=True)
    like = Image.open(os.path.join(PROPS, id_ + ".png")).convert("RGBA")
    blue = screen == "blue"
    shown = ga.on_screen(like.resize((1024, 1024), Image.LANCZOS), blue)
    bg = ga.BG_BLUE if blue else ga.BG_GREEN
    fix = FIXES.get(id_, "")
    prompt = ("Using exactly the same art style, line art, cel shading, palette, lighting from the upper left and level of detail as the "
              "reference images, draw the object of the last reference image again, as the same artist would draw the same thing a second "
              "time: " + subject + ". The same kind of object, the same overall shape and proportions, the same size in the frame, the same "
              "colours and tones, the same number of main parts; only tiny natural differences in the small details. A clean closed silhouette, "
              "the same thin dark brown line art as the reference (no thick black border), every part joined to the rest, its base resting "
              "on the floor line. "
              + (fix + ". " if fix else "") +
              "Seen from the front at eye level, the whole object visible, no ground patch, no cast shadow, nothing else in the frame. "
              + ga.STYLE + ". " + bg + ".")
    if hasattr(gp, "NO_FACE") and gp.NO_FACE not in prompt:
        prompt += gp.NO_FACE
    refs = None
    n = 0
    if id_.startswith("cart_toppled"):
        return paint_cart(id_, subject, cell, screen, seeds, force, like)
    recipe = id_ in FIXES and id_ in gpv.VARIANTS and gpv.VARIANTS[id_][1]
    if recipe:
        # a painting that needs a repair is not shown to the painter (it would copy the fault): its own first recipe again
        # (the kind's raw render as the reference, its subject) with the repair's words, under new seeds
        prompt = ("Using exactly the same art style, rendering, line art, cel shading, palette, lighting from the upper left and level of "
                  "detail as the reference images, draw a new desert prop for the same game: " + subject + ". " + fix + ". Seen from the "
                  "front at eye level, the whole object visible, its base resting on the floor line, no ground patch, no cast shadow, "
                  "nothing else in the frame. " + ga.STYLE + ". " + bg + ". Do not copy the reference objects exactly: this is a "
                  "different plant or rock of the same family.")
    for k in range(seeds):
        raw = os.path.join(RAWS, "%s_s%d.png" % (id_, k))
        out = os.path.join(CANDS, "%s_s%d.png" % (id_, k))
        if os.path.exists(out) and not force:
            continue
        if not os.path.exists(raw) or force:
            if refs is None:
                last = Image.open(os.path.join(gpv.RAW, gpv.VARIANTS[id_][1])).convert("RGB") if recipe else shown
                refs = list(ga.ensure_anchor_uploaded()) + [comfy.upload_pil(last, "p130_" + id_ + "_ref.png")]
            seed = SEED0 + (abs(hash_id(id_)) % 5000) * 7 + k * 977
            t0 = time.time()
            if id_ in INIT and not recipe:
                imgs, _ = comfy.run(comfy.klein(prompt, seed, 1024, 1024, refs=refs, prefix="88fits/reseed_" + id_, init=refs[-1], denoise=INIT[id_]))
            else:
                imgs, _ = comfy.run(comfy.klein(prompt, seed, 1024, 1024, refs=refs, prefix="88fits/reseed_" + id_))
            Image.open(io.BytesIO(imgs[0])).convert("RGB").save(raw)
            n += 1
            with open(os.path.join(ENV, "renders.log"), "a", encoding="utf-8", newline="\n") as f:
                f.write("%s %s s%d seed %d %.0fs\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), id_, k, seed, time.time() - t0))
        grade = gpv.FROM_RENDER.get("cart_toppled", {}).get("grade") if id_.startswith("cart_toppled") else None
        cand = gpv.finish(Image.open(raw).convert("RGB"), cell, grade)
        match_tone(cand, like).save(out)
    return n


def paint_cart(id_, subject, cell, screen, seeds, force, like):
    """The cart and its wreck states: their own first recipe again (gen_prop_variants.render: painted over the Blender
    render at the cart's denoise, so every plank and wheel stays where the model has it), under new seeds."""
    gpv, gp, ga, comfy = painter()
    env = {r["id"]: r for r in json.load(open(os.path.join(HERE, "env_variations.json"), encoding="utf-8"))["rows"]}
    fr = dict(gpv.FROM_RENDER["cart_toppled"])
    if env.get(id_, {}).get("render"):
        fr["ref"] = env[id_]["render"]
    gpv.FROM_RENDER[id_] = fr
    gpv.RAW = os.path.join(RAWS, "cart")
    gpv.FORCE = force
    seed0 = SEED0 + (abs(hash_id(id_)) % 5000) * 7
    vrow = ("cart_toppled", None, subject, 0.0, 0.0, cell, seed0, screen)
    n = 0
    for k in range(seeds):
        out = os.path.join(CANDS, "%s_s%d.png" % (id_, k))
        if os.path.exists(out) and not force:
            continue
        t0 = time.time()
        img = gpv.render(id_, vrow, k)
        n += 1
        with open(os.path.join(ENV, "renders.log"), "a", encoding="utf-8", newline="\n") as f:
            f.write("%s %s s%d seed %d %.0fs (cart recipe)\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), id_, k, seed0 + k * 977, time.time() - t0))
        img.save(os.path.join(RAWS, "%s_s%d.png" % (id_, k)))
        match_tone(gpv.finish(img, cell, fr.get("grade")), like).save(out)
    return n


def hash_id(s):
    h = 0
    for ch in s:
        h = (h * 131 + ord(ch)) % 1000003
    return h


def font(size):
    for name in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def sheets(rows, seeds, per=6, tile=170):
    """Contact sheets: one row a painting (the game's own first, then its candidates), `per` paintings a sheet."""
    os.makedirs(SHEETS, exist_ok=True)
    out = []
    f = font(15)
    have = [r for r in rows if os.path.exists(os.path.join(CANDS, "%s_s0.png" % r[0]))]
    for n in range(0, len(have), per):
        part = have[n:n + per]
        w = 150 + (seeds + 1) * (tile + 8)
        sh = Image.new("RGBA", (w, len(part) * (tile + 8) + 8), SAND + (255,))
        dr = ImageDraw.Draw(sh)
        for j, (id_, _, _, _) in enumerate(part):
            y = 8 + j * (tile + 8)
            dr.text((6, y + 6), id_, fill=(40, 20, 10, 255), font=f)
            tiles = [("in game", os.path.join(PROPS, id_ + ".png"))] + [("s%d" % k, os.path.join(CANDS, "%s_s%d.png" % (id_, k))) for k in range(seeds)]
            for i, (name, path) in enumerate(tiles):
                x = 150 + i * (tile + 8)
                if os.path.exists(path):
                    sh.alpha_composite(Image.open(path).convert("RGBA").resize((tile, tile), Image.LANCZOS), (x, y))
                dr.text((x + 3, y + tile - 16), name, fill=(40, 20, 10, 255), font=f)
        p = os.path.join(SHEETS, "sheet_%02d.png" % (n // per))
        sh.convert("RGB").save(p)
        out.append(p)
    return out


def install(picks, dry):
    rows = {r[0]: r for r in paintings()}
    keep = os.path.join(ENV, "replaced")
    os.makedirs(keep, exist_ok=True)
    for p in picks:
        id_, k = p.split("=")
        src = os.path.join(CANDS, "%s_s%s.png" % (id_, k))
        if id_ not in rows or not os.path.exists(src):
            raise SystemExit("install: no candidate %s" % src)
        print("install: %s s%s -> game/art/sprites/props/%s.png%s" % (id_, k, id_, "  (dry run)" if dry else ""))
        if dry:
            continue
        dst = os.path.join(PROPS, id_ + ".png")
        if not os.path.exists(os.path.join(keep, id_ + ".png")):
            shutil.copyfile(dst, os.path.join(keep, id_ + ".png"))
        shutil.copyfile(src, dst)
    if not dry:
        print("install: now python tools/prop_shadows.py (the replaced paintings' shadows) and the Godot --import")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--seeds", type=int, default=5)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--sheets", action="store_true")
    ap.add_argument("--install", nargs="*")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    rows = paintings()
    if a.list:
        for r in rows:
            print(r[0])
        return
    if a.install is not None:
        install(a.install, a.dry_run)
        return
    if a.sheets:
        for p in sheets(rows, a.seeds):
            print(p)
        return
    only = [x for x in a.only.split(",") if x]
    if not only:
        raise SystemExit("name the painting(s): --only <id>[,<id>] (one process a painting: the ComfyUI lock changes hands)")
    for r in rows:
        if r[0] in only:
            n = paint(r[0], r[1], r[2], r[3], a.seeds, a.force)
            print("reseed: %s %d renders" % (r[0], n))


if __name__ == "__main__":
    main()

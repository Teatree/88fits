"""Creature art variants walked on a 3D model's control video (pass 46): tools/gen_ant.py's method for any creature, its
recipe read from the creature JSON (variants[code].recipe). The Dune Scorpion's four options are the first users.

For a variant:
  1. the drivers (a Blender script's depth videos ctl_NN.png and clay.png per view, e.g. tools/blender_scorpion.py ->
     tools/dl/drivers/scorpion_walk) must exist; the recipe names the folder ("drivers")
  2. the side view is painted first from its clay (candidates k0..k<n>, picked by eye with --use-side=kN); --dev paints them
     on Flux.2 dev at full steps, the best model we have; the recipe may add a look reference ("look_ref", a picture)
  3. every other view is painted on Klein from the side painting and its own clay, the way it faces spelled out, so the
     five views are one creature
  4. Wan 2.2 Fun Control walks each view along its depth video (animate.cycle_control), each walk resized to its depth
     video's width (model_scale: Wan keeps the painting's scale, and the paintings differ)
  5. the death: with "death_drivers" (a front-view control video of the model dying, tools/blender_scorpion.py mode=death)
     Wan 2.2 Fun Control walks the front painting along it (animate.oneshot_control, 8 frames at the walk's scale); without
     one the front painting is edited dead and Wan 2.2 first-last-frame animates the fall (gen_art.death_cycle)
  6. everything is fitted to one scale and packed as a strip (8 directions unless the recipe says "directions": 2):
     <id>_sprite_<letter>.png, <id>_icon_<letter>.png (kept when the entry says icon_picked: an icon picked from
     candidates in the Level Editor), the counts written into variants[code]

    python tools/gen_ctl.py --id=dune_scorpion --variant=SC-A [--dev] [--seeds=3]      (side candidates, then stops)
    python tools/gen_ctl.py --id=dune_scorpion --variant=SC-A --use-side=k1 [--stage=paint]
    python tools/gen_ctl.py --id=dune_scorpion --variant=SC-B --view-cands=fd,back [--seeds=3]   (a view painted again, then stops)
    python tools/gen_ctl.py --id=dune_scorpion --variant=SC-B --use-view=fd:c1,back:c0 [--stage=paint]

Recipe keys: drivers, prompt (the look), noun ("a scorpion"), detail (anatomy), blockout (how the clay looks), words
{front, fd, bd, back} (the camera per view), keep (something every view must carry), look_ref (a picture under the repo),
motion (the walk's words), death_drivers (a folder under tools/dl/drivers), death_motion (its words), death_keep (which
8 of the death clip's frames to keep, picked by eye; re-picking needs no render), remap_hues (artkit.remap_hues on every
frame, a colour one view drifted into), dead (the dead
painting's words when there is no death driver), fps, directions, screen ("green"/"blue"), outline_frac, outline_color,
side_seeds.
Pass 70 (lane LE): the side and view candidates' seeds are the job's own (tools/cand_seeds.py: the Level Editor job id and
its attempt move them, candidate k a prime past a million from k-1); the plain views keep their seeds.
"""
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ARGS = sys.argv[1:]
sys.argv = ["gen_art.py", "--no-import"] + (["--skip-qa"] if "--skip-qa" in ARGS else [])
sys.path.insert(0, HERE)
import gen_art as g  # noqa: E402
import animate  # noqa: E402
import cand_seeds  # noqa: E402
import artkit  # noqa: E402
import comfy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

VIEWS = ["front", "fd", "side", "bd", "back"]
SP = os.path.join(REPO, "tools", "dl", "review")


def opt(name, default=""):
    for a in ARGS:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


def log(*a):
    print(*a, flush=True)


def sheet(keys, name):
    ims = [Image.open(os.path.join(g.RAW, k + ".png")).convert("RGB") for k in keys]
    W = 400
    out = Image.new("RGB", (W * len(ims), W + 28), (30, 30, 36))
    dr = ImageDraw.Draw(out)
    for i, (k, im) in enumerate(zip(keys, ims)):
        out.paste(im.resize((W, W), Image.LANCZOS), (i * W, 28))
        dr.text((i * W + 6, 6), k, fill=(255, 230, 140))
    os.makedirs(SP, exist_ok=True)
    out.save(os.path.join(SP, name))
    return os.path.join(SP, name)


def _width(img, depth=False):
    a = (np.asarray(img.convert("L")) > 12) if depth else (np.asarray(img.convert("RGBA"))[..., 3] > 127)
    xs = np.nonzero(a.max(axis=0))[0]
    return float(xs.max() - xs.min() + 1) if len(xs) else 0.0


def model_scale(frames, ctl_dir, first=12):
    """How much to resize a walk so it has its model's size: Wan follows the painting's scale, and Klein paints some views
    bigger than their clay (pass 46: the scorpion's front walk came out 23% wider than its depth video, the back as wide),
    so a creature would grow and shrink as it turned. The median frame width is matched to the depth video's (frames
    first.. of the clip, the stride cycle_control keeps)."""
    ws = sorted(_width(f) for f in frames)
    cs = sorted(_width(Image.open(os.path.join(ctl_dir, "ctl_%02d.png" % k)), True) for k in range(first, first + len(frames))
                if os.path.exists(os.path.join(ctl_dir, "ctl_%02d.png" % k)))
    if not ws or not cs or ws[len(ws) // 2] <= 0:
        return 1.0
    k = cs[len(cs) // 2] / ws[len(ws) // 2]
    return 1.0 if abs(k - 1.0) < 0.04 else k


def drop_islands(img, frac=0.08, gap=6):
    """A frame's detached bits cleared: alpha blobs smaller than `frac` of the largest that lie more than `gap` pixels
    from it (pass 46: SC-C's back walk had a sting floating above the claws in two frames; a leg the keyer cut loose
    stays, being next to the body)."""
    from scipy import ndimage
    a = np.asarray(img.convert("RGBA")).copy()
    mask = a[..., 3] > 40
    labels, n = ndimage.label(mask)
    if n <= 1:
        return img
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    main = int(np.argmax(sizes)) + 1
    near = ndimage.binary_dilation(labels == main, iterations=gap)
    gone = 0
    for i, sz in enumerate(sizes, start=1):
        if i != main and sz < sizes.max() * frac and not (near & (labels == i)).any():
            a[labels == i, 3] = 0
            gone += 1
    return Image.fromarray(a, "RGBA") if gone else img


def resized(frames, k):
    if k == 1.0:
        return frames
    return [f.resize((max(1, round(f.width * k)), max(1, round(f.height * k))), Image.LANCZOS) for f in frames]


def no_green(img):
    """A creature with no green in it: any green in a frame is the screen's spill, held down to the red channel."""
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 0
    r, gch = a[..., 0].astype(np.int16), a[..., 1].astype(np.int16)
    a[..., 1] = np.where(m & (gch > r), r, gch).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def paint(cid, code, recipe, drv, seed, bg):
    """The five views; returns {view: RGB}, or None while the side view waits to be picked."""
    key = cid + "_" + code.lower().replace("-", "")
    noun = recipe.get("noun", "a creature")
    blockout = recipe.get("blockout", "a smooth plain clay 3D model of the same creature")
    detail = recipe.get("detail", "")
    side_key = key + "_side"
    chosen = opt("use-side")
    anatomy = recipe.get("anatomy", "exactly one body, exactly one tail")
    if chosen:
        for ext in (".png", ".json"):
            shutil.copy(os.path.join(g.RAW, "%s_%s%s" % (side_key, chosen, ext)), os.path.join(g.RAW, side_key + ext))
    look = []
    if recipe.get("look_ref"):
        look = [comfy.upload_pil(Image.open(os.path.join(REPO, recipe["look_ref"])).convert("RGB"), key + "_look.png")]
    if not os.path.exists(os.path.join(g.RAW, side_key + ".png")):
        refs = g.ensure_anchor_uploaded()
        clay = comfy.upload_pil(Image.open(os.path.join(drv, "side", "clay.png")).convert("RGB"), key + "_clay_side.png")
        n = int(opt("seeds", str(recipe.get("side_seeds", 3))))
        # pass 70: the job's own seeds (a re-run's attempt and the job id move them)
        side_seeds = cand_seeds.seeds(seed + g.LOOK_SEED_STEP * (cand_seeds.job_attempt() - 1), n, cand_seeds.job_tag())
        keys = []
        for k in range(n):
            ck = "%s_k%d" % (side_key, k)
            looks = (" The third reference image shows what this creature looks like: copy its armour, colours and markings, "
                     "but not its pose or camera angle.") if look else ""
            p = ("The first reference image shows the art style only; do not copy its subjects. The second reference image is a "
                 "smooth plain 3D model of " + noun + " (" + blockout + "): use it only for the anatomy, the pose, the camera angle "
                 "and where every leg and every other part is." + looks + " Redraw it as a finished, detailed anime game creature "
                 "illustration of " + recipe["prompt"] + (", with " + detail if detail else "") + ", in side profile facing right, "
                 + anatomy + ". It must not look like a plain 3D model. " + g.STYLE + ". " + bg + ".")
            raw = os.path.join(g.RAW, ck + ".png")
            if not os.path.exists(raw):
                s = side_seeds[k]
                # the painter and its quality come from gen_art.MODEL (--dev, --model=, --steps=, or the editor's ART_* env)
                imgs, secs = g.paint(p, s, 1024, 1024, list(refs) + [clay] + look, "88fits/" + ck, full=True)
                import io
                Image.open(io.BytesIO(imgs[0])).convert("RGB").save(raw)
                json.dump({"seed": s, "prompt": p, "refs": list(refs) + [clay] + look, "qa": {"problems": []}, "attempt": 0},
                          open(raw[:-4] + ".json", "w", encoding="utf-8"), indent=1)
                log("  side %s seed %d %.0fs" % (ck, s, secs))
            keys.append(ck)
        path = sheet(keys, side_key + "_cands.png")
        log("  side candidates painted: look at %s, then rerun with --use-side=kN" % path)
        return None
    side = Image.open(os.path.join(g.RAW, side_key + ".png")).convert("RGB")
    out = {"side": side}
    keep = (" It keeps " + recipe["keep"] + ", seen from this angle.") if recipe.get("keep") else ""
    words = recipe.get("words", {})
    side_ref = comfy.upload_pil(side, side_key + ".png")
    # a view that came out wrong is painted again as candidates (--view-cands=fd,back) and picked (--use-view=fd:c1,back:c0)
    cands = [v for v in opt("view-cands").split(",") if v]
    for pair in [u for u in opt("use-view").split(",") if ":" in u]:
        view, ck = pair.split(":", 1)
        for ext in (".png", ".json"):
            shutil.copy(os.path.join(g.RAW, "%s_%s_%s%s" % (key, view, ck, ext)), os.path.join(g.RAW, "%s_%s%s" % (key, view, ext)))
    for k, view in enumerate(["front", "fd", "bd", "back"]):
        clay = comfy.upload_pil(Image.open(os.path.join(drv, view, "clay.png")).convert("RGB"), "%s_clay_%s.png" % (key, view))
        p = ("The first reference image is a finished painting of " + noun + " character in side view. The second reference image is a "
             "smooth plain 3D model of the same creature, " + words.get(view, "seen from another angle") + ". Redraw the 3D model as the "
             "same creature as the first image, the same colours, armour, markings and art style, in exactly the pose and camera angle "
             "of the 3D model, with " + anatomy + " and the same number of legs and claws as the 3D model." + keep +
             " It must not look like a plain 3D model. " + g.STYLE + ". " + bg + ".")
        if view in cands:
            ks = ["%s_%s_c%d" % (key, view, c) for c in range(int(opt("seeds", "3")))]
            # pass 70: the job's own seeds, CAND_STEP past the plain view's own
            vseeds = cand_seeds.seeds(seed + 11 + k + cand_seeds.CAND_STEP + g.LOOK_SEED_STEP * (cand_seeds.job_attempt() - 1), len(ks), cand_seeds.job_tag())
            for c, ck in enumerate(ks):
                g.render(ck, p, [side_ref, clay], {"subject": noun, "view": None, "subjects_max": 1}, vseeds[c], tries=1)
            log("  %s candidates: %s" % (view, sheet(ks, "%s_%s_cands.png" % (key, view))))
            continue
        img, _ = g.render("%s_%s" % (key, view), p, [side_ref, clay], {"subject": noun, "view": None, "subjects_max": 1}, seed + 11 + k, tries=1)
        out[view] = img
    if cands:
        log("  pick with --use-view=VIEW:cN[,VIEW:cN]")
        return None
    log("  views sheet: " + sheet([key + "_" + v for v in VIEWS], key + "_views.png"))
    return out


def main():
    cid = opt("id")
    code = opt("variant")
    folder = None
    for kind in ("enemies", "bosses"):
        f = os.path.join(REPO, "game", "content", kind, cid)
        if os.path.isdir(f):
            folder = f
    if folder is None:
        raise SystemExit("gen_ctl: no creature folder for %s" % cid)
    d = json.load(open(os.path.join(folder, cid + ".json"), encoding="utf-8"))
    entry = (d.get("variants") or {}).get(code)
    if not isinstance(entry, dict) or "recipe" not in entry:
        raise SystemExit("gen_ctl: no recipe for %s in %s.json" % (code, cid))
    recipe = entry["recipe"]
    drv = os.path.join(REPO, "tools", "dl", "drivers", recipe["drivers"])
    if not os.path.exists(os.path.join(drv, "back", "ctl_24.png")):
        raise SystemExit("gen_ctl: render the drivers first (%s)" % drv)
    bg = g.BG_BLUE if recipe.get("screen", d.get("screen", "green")) == "blue" else g.BG_GREEN
    seed = g.seed_for(cid + code)
    views = paint(cid, code, recipe, drv, seed, bg)
    if views is None or opt("stage") == "paint":
        return
    key = cid + "_" + code.lower().replace("-", "")
    cell = int(d.get("frame_px", 128))
    oc = str(recipe.get("outline_color", d.get("outline_color", "#0E080C"))).lstrip("#")
    CO = (int(oc[0:2], 16), int(oc[2:4], 16), int(oc[4:6], 16), 255)
    CF = float(recipe.get("outline_frac", d.get("outline_frac", 0.024)))
    anatomy_short = recipe.get("anatomy", "exactly one tail")
    motion = ("A 2D anime game creature sprite, " + recipe["prompt"].split(",")[0] + ", " + recipe.get("motion", "walking in place") +
              " exactly as the control video shows, the same creature, colours and markings as the reference in every frame, "
              + anatomy_short + ", crisp clean line art, cel shading. The camera is completely locked off and static. The background stays a flat "
              "solid bright " + ("blue" if bg == g.BG_BLUE else "green") + " color with nothing in it, no ground, no shadow.")
    two = int(recipe.get("directions", 8)) == 2
    walks = {}
    sizes = {}
    for view in (["front", "back"] if two else VIEWS):
        # "walk_seeds" {view: n} rolls one view's walk again with another seed (pass 49: BB-B's three-quarter front painted
        # its long horn as a see-through grey ghost); move that view's ai_anim folder away first
        wseed = seed + 20 + VIEWS.index(view) + 1000 * int((recipe.get("walk_seeds") or {}).get(view, 0))
        frames, _ = animate.cycle_control(views[view], key + "_ctl_" + view, os.path.join(drv, view), wseed, prompt=motion,
                                          negative_extra=str(recipe.get("anim_negative", d.get("anim_negative", ""))))
        k = model_scale(frames, os.path.join(drv, view))
        sizes[view] = k
        walks[view] = [drop_islands(f) for f in resized(frames, k)]
    log("  model scale per view: " + ", ".join("%s %.2f" % (v, k) for v, k in sizes.items()))
    # one scale for every view: the widest and tallest walk frames of all the walks fitted into the cell

    def extent(f, axis):
        idx = np.nonzero(np.asarray(f)[..., 3].max(axis=axis) > 127)[0]
        return float(idx.max() - idx.min() + 1) if len(idx) else 0.0
    tall = max(extent(f, 1) for fr in walks.values() for f in fr)
    wide = max(extent(f, 0) for fr in walks.values() for f in fr)
    px = max(1, int(round(cell * CF)))
    scale = min((cell * 0.8) / tall, (cell - 2 * px - 6) / wide)
    cells = {v: artkit.place_clip_frames(fr, cell, scale, px, CO) for v, fr in walks.items()}
    base = cells["front"][0]
    back_cell = cells["back"][0]
    views8 = {} if two else {"_s": (cells["side"][0], cells["side"]), "_bd": (cells["bd"][0], cells["bd"]), "_fd": (cells["fd"][0], cells["fd"])}
    frames = artkit.enemy_frames(base, cell, cells["front"], back_cell, cells["back"], views8)
    # the death: walked along the model's own death (the recipe's "death_drivers", a front-view control video) when there
    # is one, at the walk's scale; else the front painting edited dead and a first-last-frame fall between them
    front = views["front"]
    ddrv = recipe.get("death_drivers")
    ddir = os.path.join(REPO, "tools", "dl", "drivers", ddrv, "front") if ddrv else ""
    ddriven = bool(ddir and os.path.exists(os.path.join(ddir, "ctl_24.png")))
    if ddriven:
        dmotion = ("A 2D anime game creature sprite, " + recipe["prompt"].split(",")[0] + ", dying exactly as the control video shows: "
                   + recipe.get("death_motion", "it rears up in a spasm, rolls over onto its back and lies dead with its legs curled up in the "
                                "air, the pale underside of its body showing") + ". The same creature, colours and markings as the reference in "
                   "every frame, " + anatomy_short + ", crisp clean line art, cel shading. The camera is completely locked off and static. The "
                   "background stays a flat solid bright " + ("blue" if bg == g.BG_BLUE else "green") + " color with nothing in it, no ground, no shadow.")
        # "death_keep": which 8 of the clip's 25 frames to keep (Wan smears some of the roll; picked by eye from
        # tools/dl/ai_anim/<key>_death/full_NN.png and re-picked without a render)
        dkeep = tuple(int(v) for v in recipe.get("death_keep", (1, 4, 7, 10, 13, 16, 20, 24)))
        dclip, _ = animate.oneshot_control(front, key + "_death", ddir, seed + 30, prompt=dmotion,
                                           negative_extra=str(recipe.get("anim_negative", d.get("anim_negative", ""))), keep=dkeep)
        # the death starts from the front painting, so it takes the front walk's size correction
        frames["die"] = artkit.place_clip_frames([drop_islands(f) for f in resized(dclip, sizes.get("front", 1.0))], cell, scale, px, CO)
        fall = True
    else:
        front_ref = comfy.upload_pil(front, key + "_front.png")
        dead_words = recipe.get("dead", "lying dead on its back, its legs curled up limp in the air")
        dead_prompt = ("This exact creature " + dead_words + ", seen from the front and a little above so the whole body is visible. Keep the "
                       "same colors, proportions and art style. No ground, no sand. " + bg + ".")
        dead, _ = g.render(key + "_dead", dead_prompt, [front_ref], {"subject": noun_or(recipe), "view": None, "subjects_max": 1}, seed + 9)
        fall = g.death_cycle(front, dead, key + "_fall", seed + 9, cell, base, 8, CF, CO, recipe["prompt"].split(",")[0][:120], "")
        if fall:
            frames["die"] = fall
        else:
            dead_cell = g.finish(dead, cell, 0.7, True, None, CF, None, CO)[0]
            frames["die"] = [artkit.transform(base, lean_deg=-14, sy=0.97), artkit.fall(base, 38), artkit.fall(base, 66), dead_cell, dead_cell]
    if recipe.get("no_green", True):
        for k in list(frames.keys()):
            frames[k] = [no_green(f) for f in frames[k]]
    # "remap_hues" {ranges, to, sat, min_sat, max_sat}: a hue some views took that the others do not have, pulled to one (pass 46:
    # SC-C's three-quarter back came out purple-blue and its side blue-black beside charcoal front and back views)
    rh = recipe.get("remap_hues")
    if isinstance(rh, dict):
        for k in list(frames.keys()):
            frames[k] = [artkit.remap_hues(f, rh.get("ranges", []), rh.get("to", 230), rh.get("sat", 0.55), rh.get("min_sat", 0.16), rh.get("max_sat", 1.01)) for f in frames[k]]
    strip, counts, cols = artkit.pack_strip(frames, artkit.ENEMY_ORDER, cell)
    letter = code.split("-")[-1].lower()
    fname = cid + "_sprite_" + letter + ".png"
    strip.save(os.path.join(folder, fname))
    iname = cid + "_icon_" + letter + ".png"
    if keeps_picked_icon(entry, os.path.join(folder, iname)):
        log("  the look's icon was picked from candidates: kept (%s)" % iname)
    else:
        icon, _ = g.finish(front, 256, 0.9, False, None, 0.009)
        icon.save(os.path.join(folder, iname))
    head = round(max(g.figure_top(f) for f in frames.get("idle", []) + frames.get("run", [])), 3)
    patch = {"sprite": fname, "icon": iname, "anims": counts, "strip_cols": cols, "head": head,
             "fps": {"run": int(recipe.get("fps", 20)), "die": 12 if fall else 8}}
    # pass 66: under a Level Editor job (ASSET_JOB_SIDECAR) the entry goes into the sidecar for the server to merge in
    # place; a command line writes the JSON as before
    if g.WRITE_JSON:
        cur = json.load(open(os.path.join(folder, cid + ".json"), encoding="utf-8"))
        ent = cur.setdefault("variants", {}).setdefault(code, {})
        ent.update(patch)
        json.dump(cur, open(os.path.join(folder, cid + ".json"), "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    else:
        clip_kind = {v: "control" for v in walks}
        clip_kind["die"] = "control" if ddriven else ("flf" if fall else "procedural")
        g.emit_sidecar(folder, cid, code, patch, {"pipeline": "gen_ctl", "scale": sizes, "fall": bool(fall), "recipe_ran": recipe,
                                                  "clip_kind": clip_kind, "qa_online": g.QA_ONLINE})
    log("gen_ctl: %s %s packed, %d frames, %s" % (cid, code, sum(counts.values()), fname))


def noun_or(recipe):
    return recipe.get("noun", "a creature")


def keeps_picked_icon(entry, icon_path):
    """pass 68 (review): a look whose icon was picked from candidates (the Level Editor marks its entry `icon_picked`)
    keeps that file: the run does not paint the front-still crop over it (gen_art's rule); its entry still names it."""
    return bool(isinstance(entry, dict) and entry.get("icon_picked") and os.path.isfile(icon_path))


if __name__ == "__main__":
    main()

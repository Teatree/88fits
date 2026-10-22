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
side_seeds, ctl_soft / death_soft (pass 92: {radius, body, views}: the depth's body softened so a painted face survives).
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
import frames_store  # noqa: E402  (pass 95, lane VACE: the frames store told after strip.save)
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


def fit_to_ctl(ref, ctl_dir, first=12, n=12, share=1.0):
    """pass 93 (recipe "fit_ref": true, or a list of views): the painting's figure moved and scaled onto the depth video's
    figure before Wan walks it. Klein paints some views bigger than their clay (SP-E's front 1.4 times as wide): Wan then
    walks the painting at its own size along a smaller depth figure, and the painted legs outside the depth's stay on as
    faded grey ghost legs beside the walking ones. The painting's keyed box is fitted to the depth's box over the stride
    (the median width matched, centres and bottoms aligned) on the painting's own screen colour. `share` < 1 goes only that
    part of the way (0.5: half the size change), so a painting whose look lies outside the clay keeps some of it."""
    rgb = ref.convert("RGB")
    a = np.asarray(artkit.key_background(rgb))[..., 3] > 127
    ys, xs = np.nonzero(a)
    if len(xs) < 50:
        return ref
    W, H = rgb.size
    boxes = []
    for k in range(first, first + n):
        p = os.path.join(ctl_dir, "ctl_%02d.png" % k)
        if os.path.exists(p):
            im = Image.open(p).convert("L")
            m = np.asarray(im) > 12
            yy, xx = np.nonzero(m)
            if len(xx):
                boxes.append((xx.min() / im.width, yy.min() / im.height, (xx.max() + 1) / im.width, (yy.max() + 1) / im.height))
    if not boxes:
        return ref
    cw = float(np.median([b[2] - b[0] for b in boxes]))
    cx = float(np.median([(b[0] + b[2]) / 2.0 for b in boxes]))
    cb = float(np.median([b[3] for b in boxes]))
    pw = (xs.max() + 1 - xs.min()) / W
    s = 1.0 + (cw / max(pw, 1e-6) - 1.0) * float(share)
    if abs(s - 1.0) < 0.04:
        return ref
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    fig = artkit.key_background(rgb).crop(box)
    fig = fig.resize((max(1, round(fig.width * s)), max(1, round(fig.height * s))), Image.LANCZOS)
    corner = np.asarray(rgb)[:8, :8].reshape(-1, 3).mean(axis=0)
    out = Image.new("RGBA", (W, H), tuple(int(c) for c in corner) + (255,))
    x = int(round(cx * W - fig.width / 2.0))
    y = int(round(cb * H - fig.height))
    out.paste(fig, (x, y), fig)
    log("  fit_ref: the painting x%.2f onto the depth figure" % s)
    return out.convert("RGB")


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


def no_green(img, mode=True):
    """A creature with no green in it: any green in a frame is the screen's spill, held down to the red channel.
    mode "rb" (pass 93, recipe "no_green": "rb"): held down to the larger of red and blue instead, so a light blue
    creature keeps its colour (SP-F's sky blue has more green than red: the red clamp turned it royal blue)."""
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 0
    r, gch = a[..., 0].astype(np.int16), a[..., 1].astype(np.int16)
    cap = np.maximum(r, a[..., 2].astype(np.int16)) if mode == "rb" else r
    a[..., 1] = np.where(m & (gch > cap), cap, gch).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def repaint_mode(recipe):
    """pass 94 (lane REAL): recipe "paint_mode": "repaint": every view is the model's own clay repainted (the clay the
    first and main reference, no style anchor, "keep the model's silhouette, pose and camera exactly"), for a look as
    close to the 3D model as it can get; the other views take the side painting as their second reference (colours and
    finish). Default "redraw": the pass 46 wording (style anchor, the clay for anatomy and pose only)."""
    return str(recipe.get("paint_mode", "redraw")) == "repaint"


def clay_for(recipe, drv, view, size=1024):
    """The clay a view is painted from (pass 94): clay.png, or look.png with "clay_src": "look" (the model in its own
    colours: grey for an untextured model, no brown to leak into a light look); with "clay_fill" f (0..1) cropped square
    round the figure so it fills f of the frame, and scaled to `size`, so the painter sees the model bigger. Returns
    (RGB, box in the 640 driver frame or None)."""
    # pass 99 (lane SPIDER): "clay_drivers" (a driver name, or {view: name}) names the driver a view was painted from
    # and is put back on, when the walk moved to another (spider_walk_v5 dropped the fins: the old paintings keep the
    # crop of the clay they were painted on, so the cached placement and the walk's reference stay the same)
    cd = recipe.get("clay_drivers")
    cname = (cd.get(view) if isinstance(cd, dict) else cd) if cd else None
    if cname:
        drv = os.path.join(REPO, "tools", "dl", "drivers", str(cname))
    d = os.path.join(drv, view)
    src = os.path.join(d, "look.png") if recipe.get("clay_src") == "look" and os.path.exists(os.path.join(d, "look.png")) else os.path.join(d, "clay.png")
    im = Image.open(src).convert("RGB")
    fill = float(recipe.get("clay_fill") or 0)
    if fill <= 0 or fill > 1:
        return im, None
    a = np.asarray(artkit.key_background(im))[..., 3] > 127
    ys, xs = np.nonzero(a)
    if len(xs) < 50:
        return im, None
    side = max(xs.max() + 1 - xs.min(), ys.max() + 1 - ys.min()) / fill
    cx, cy = (xs.min() + xs.max() + 1) / 2.0, (ys.min() + ys.max() + 1) / 2.0
    box = (int(round(cx - side / 2)), int(round(cy - side / 2)), int(round(cx + side / 2)), int(round(cy + side / 2)))
    corner = tuple(int(c) for c in np.asarray(im)[:8, :8].reshape(-1, 3).mean(axis=0))
    pad = Image.new("RGB", (box[2] - box[0], box[3] - box[1]), corner)
    pad.paste(im, (-box[0], -box[1]))
    return pad.resize((size, size), Image.LANCZOS), box


def uncrop(painting, box, size=640):
    """A painting of a clay_fill crop put back where the crop came from in the driver's frame (the inverse of clay_for),
    on the painting's own screen colour, so Wan walks it where the depth video's figure is."""
    if not box:
        return painting
    rgb = painting.convert("RGB")
    corner = tuple(int(c) for c in np.asarray(rgb)[:8, :8].reshape(-1, 3).mean(axis=0))
    out = Image.new("RGB", (size, size), corner)
    out.paste(rgb.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS), (box[0], box[1]))
    return out


def tinted_clay(clay, recipe, bg, side=None):
    """pass 94: the start picture of an img2img paint (recipe "init": {"denoise": 0.8, "tint": "#C4A8E2" | "auto"}): the
    clay keyed, its shading coloured like the look ("auto": the side painting's median figure colour) on the pure screen."""
    ini = recipe.get("init") if isinstance(recipe.get("init"), dict) else {}
    t = str(ini.get("tint", "#C4A8E2"))
    if t == "auto" and side is not None:
        a = np.asarray(artkit.key_background(side.convert("RGB")))
        m = a[..., 3] > 200
        rgb = np.median(a[..., :3][m], axis=0) if m.any() else np.array([196, 168, 226])
    else:
        t = t.lstrip("#") if t != "auto" else "C4A8E2"
        rgb = np.array([int(t[0:2], 16), int(t[2:4], 16), int(t[4:6], 16)], np.float32)
    k = artkit.key_background(clay.convert("RGB"))
    a = np.asarray(k).astype(np.float32)
    lum = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) / 255.0
    # "shade_blur" px: only the shading inside the figure blurred (the clay's facets gone), its outline kept sharp: Flux.2
    # dev lets go of a blurred start picture altogether, and holds on to a sharp outline
    sb = float(ini.get("shade_blur", 0) or 0)
    if sb > 0:
        from scipy import ndimage
        w = a[..., 3] / 255.0
        lum = ndimage.gaussian_filter(lum * w, sb) / np.maximum(ndimage.gaussian_filter(w, sb), 1e-3)
    # "posterize" n: the shading in n flat bands, like cel shading (clean shapes with edges a painter can hold on to)
    pz = int(ini.get("posterize", 0) or 0)
    if pz > 1:
        lo, hi = float(np.percentile(lum[a[..., 3] > 127], 5)) if (a[..., 3] > 127).any() else 0.0, float(lum.max())
        q = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 0.999)
        lum = lo + (np.floor(q * pz) + 0.5) / pz * (hi - lo)
    col = np.clip(lum[..., None] * float(ini.get("gain", 1.25)) * np.asarray(rgb, np.float32)[None, None, :], 0, 255)
    al = a[..., 3:4] / 255.0
    scr = np.array((0, 0, 255) if bg == g.BG_BLUE else (0, 255, 0), np.float32)
    out = Image.fromarray((col * al + scr[None, None, :] * (1 - al)).astype(np.uint8), "RGB")
    # "blur" px: the clay's flat polygons and fins softened, so the painter keeps the shapes but not the facets
    if float(ini.get("blur", 0) or 0) > 0:
        from PIL import ImageFilter
        out = out.filter(ImageFilter.GaussianBlur(float(ini["blur"])))
    return out


def init_denoise(recipe):
    ini = recipe.get("init")
    return float(ini.get("denoise", 0.8)) if isinstance(ini, dict) else 1.0


def repaint_anchor(recipe):
    """pass 94: a repaint look keeps the house style when its recipe says "anchor": true (Garry: "the realistic version that
    is still in our style"): the style anchor goes in as the last reference, style only."""
    return bool(recipe.get("anchor"))


def repaint_prompt(recipe, view, bg, with_side):
    """The repaint wording (pass 94): the clay first, its shapes kept exactly, the look's words, the recipe's own style
    ("style") or the house style line; with "anchor" the style anchor is the last reference (repaint_anchor)."""
    noun = recipe.get("noun", "a creature")
    words = dict(recipe.get("words", {}))
    vw = words.get(view) or ("in side profile facing right" if view == "side" else "seen from another angle")
    detail = recipe.get("detail", "")
    anatomy = recipe.get("anatomy", "exactly one body, exactly one tail")
    style = recipe.get("style") or g.STYLE
    second = (" The second reference image is the finished painting of the same creature seen from the side: copy its colours, "
              "markings, hair and finish exactly, but not its pose or camera angle.") if with_side else ""
    anchor = repaint_anchor(recipe)
    art = (" The " + ("third" if with_side else "second") + " reference image shows the art style only; do not copy its subjects.") if anchor else ""
    what = ("Repaint this exact 3D model as a finished, detailed anime game creature illustration of " if anchor else "Repaint this exact model as ")
    surface = ("It must not look like a plain 3D model. " if anchor else
               "Only the surface changes: the flat polygons become the creature's real body. ")
    # pass 99 (lane SPIDER): "view_words" {view: words}: the look's words for that view's painting only (SP-G's pale
    # three-quarter views painted again with "stronger violet ..." without touching the shared prompt)
    extra = str((recipe.get("view_words") or {}).get(view, "") or "")
    return ("The first reference image is a rough 3D model of " + noun + " (" + recipe.get("blockout", "a plain clay 3D model") + "), "
            + vw + "." + second + art + " " + what + recipe["prompt"] + (", " + extra if extra else "") + (", with " + detail if detail else "") +
            ". Keep the model's silhouette, its pose and the camera angle exactly: " + anatomy + "; every leg stays where it is, at "
            "the same angle and length, bending at the same joints, the body and head the same size and in the same place; nothing "
            "is added that the model does not have. " + surface + style + ". " + bg + ".")


def refine(img, key, recipe, refs, seed, bg, prompt=""):
    """pass 94: "refine" {"rounds": n, "denoise": 0.6, "steps": 28, "model": "klein" | "dev", "words": ...}: the painting
    painted over again n times from itself (img2img at `denoise`) with the view's own prompt and references (the clay,
    the side painting, the style anchor), so its shapes stay and the clay's facets and smears can go. Flux.2 dev (model
    "dev") restarts the server before each round. Each round cached as RAW/<key>_r<k>.png."""
    rf = recipe.get("refine")
    if not isinstance(rf, dict) or int(rf.get("rounds", 0) or 0) <= 0:
        return img
    words = rf.get("words") or prompt or ("Clean up this painting of " + recipe.get("noun", "a creature") + ": keep exactly the same "
                                          "creature, pose, colours and camera; sharpen the details, remove smears and any extra or broken "
                                          "legs; " + recipe.get("anatomy", "") + ". " + (recipe.get("style") or g.STYLE) + ". " + bg + ".")
    dev = str(rf.get("model", "klein")) == "dev"
    for k in range(int(rf["rounds"])):
        raw = os.path.join(g.RAW, "%s_r%d.png" % (key, k + 1))
        if os.path.exists(raw):
            img = Image.open(raw).convert("RGB")
            continue
        cur = comfy.upload_pil(img, "%s_r%d_in.png" % (key, k))
        steps = int(rf.get("steps", 40 if dev else 28))
        den = float(rf.get("denoise", 0.6))
        if dev:
            imgs, secs = comfy.run_dev(comfy.flux2_dev(words, seed + 101 * (k + 1), 1024, 1024, refs=list(refs), steps=steps, guidance=4.0,
                                                       turbo=False, prefix="88fits/" + key + "_r%d" % (k + 1), init=cur, denoise=den))
            log("  " + comfy.release_models())
        else:
            imgs, secs = comfy.run(comfy.klein(words, seed + 101 * (k + 1), 1024, 1024, refs=list(refs), steps=steps,
                                               prefix="88fits/" + key + "_r%d" % (k + 1), init=cur, denoise=den))
        import io
        img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
        img.save(raw)
        log("  refine %s round %d (%s, %d steps, denoise %.2f) %.0fs" % (key, k + 1, "dev" if dev else "klein", steps, den, secs))
    return img


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
    rp = repaint_mode(recipe)
    if not os.path.exists(os.path.join(g.RAW, side_key + ".png")):
        refs = [] if rp else g.ensure_anchor_uploaded()
        tail = g.ensure_anchor_uploaded() if rp and repaint_anchor(recipe) else []
        clay_img = clay_for(recipe, drv, "side")[0] if rp else Image.open(os.path.join(drv, "side", "clay.png")).convert("RGB")
        clay = comfy.upload_pil(clay_img, key + "_clay_side.png")
        init = comfy.upload_pil(tinted_clay(clay_img, recipe, bg), key + "_init_side.png") if rp and init_denoise(recipe) < 1 else None
        n = int(opt("seeds", str(recipe.get("side_seeds", 3))))
        # pass 70: the job's own seeds (a re-run's attempt and the job id move them); pass 72: from the job's First seed
        # (--first-seed, 0 = the look's own seed: cand_seeds.start)
        side_seeds = cand_seeds.seeds(cand_seeds.start(seed, opt("first-seed", "0")) + g.LOOK_SEED_STEP * (cand_seeds.job_attempt() - 1), n, cand_seeds.job_tag())
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
            if rp:
                p = repaint_prompt(recipe, "side", bg, False)
            raw = os.path.join(g.RAW, ck + ".png")
            if not os.path.exists(raw):
                s = side_seeds[k]
                # the painter and its quality come from gen_art.MODEL (--dev, --model=, --steps=, or the editor's ART_* env)
                imgs, secs = g.paint(p, s, 1024, 1024, list(refs) + [clay] + look + list(tail), "88fits/" + ck, full=True,
                                     init=init, denoise=init_denoise(recipe) if init else 1.0)
                import io
                Image.open(io.BytesIO(imgs[0])).convert("RGB").save(raw)
                json.dump({"seed": s, "prompt": p, "refs": list(refs) + [clay] + look + list(tail), "qa": {"problems": []}, "attempt": 0,
                           "painter": g.painter_info(True), "init": init, "denoise": init_denoise(recipe) if init else 1.0},
                          open(raw[:-4] + ".json", "w", encoding="utf-8"), indent=1)
                log("  side %s seed %d %.0fs" % (ck, s, secs))
            keys.append(ck)
        path = sheet(keys, side_key + "_cands.png")
        log("  side candidates painted: look at %s, then rerun with --use-side=kN" % path)
        return None
    side = Image.open(os.path.join(g.RAW, side_key + ".png")).convert("RGB")
    if rp:
        side = refine(side, side_key, recipe, [comfy.upload_pil(clay_for(recipe, drv, "side")[0], key + "_clay_side.png")] +
                      (list(g.ensure_anchor_uploaded()) if repaint_anchor(recipe) else []), seed + 7, bg, repaint_prompt(recipe, "side", bg, False))
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
        # pass 92: the view's old walk (and, for the front, the death walked from the front painting) is set aside so the
        # new painting is walked; a cache from before pass 92 has no painting hash for animate.cache_fits to refuse it
        for sub in ([key + "_ctl_" + view] + ([key + "_death"] if view == "front" else [])):
            d0 = os.path.join(animate.ANIM, sub)
            if os.path.isdir(d0):
                d1 = d0 + "_old"
                if os.path.isdir(d1):
                    shutil.rmtree(d1, ignore_errors=True)
                os.replace(d0, d1)
                log("  %s: the old walk set aside (%s_old)" % (view, sub))
    for k, view in enumerate(["front", "fd", "bd", "back"]):
        clay_img = clay_for(recipe, drv, view)[0] if rp else Image.open(os.path.join(drv, view, "clay.png")).convert("RGB")
        clay = comfy.upload_pil(clay_img, "%s_clay_%s.png" % (key, view))
        vinit = comfy.upload_pil(tinted_clay(clay_img, recipe, bg, side), "%s_init_%s.png" % (key, view)) if rp and init_denoise(recipe) < 1 else None
        vden = init_denoise(recipe) if vinit else 1.0
        p = ("The first reference image is a finished painting of " + noun + " character in side view. The second reference image is a "
             "smooth plain 3D model of the same creature, " + words.get(view, "seen from another angle") + ". Redraw the 3D model as the "
             "same creature as the first image, the same colours, armour, markings and art style, in exactly the pose and camera angle "
             "of the 3D model, with " + anatomy + " and the same number of legs and claws as the 3D model." + keep +
             " It must not look like a plain 3D model. " + g.STYLE + ". " + bg + ".")
        vrefs = [side_ref, clay]
        if rp:
            p = repaint_prompt(recipe, view, bg, True)
            vrefs = [clay, side_ref] + (list(g.ensure_anchor_uploaded()) if repaint_anchor(recipe) else [])
        if view in cands:
            ks = ["%s_%s_c%d" % (key, view, c) for c in range(int(opt("seeds", "3")))]
            # pass 70: the job's own seeds, CAND_STEP past the plain view's own
            vseeds = cand_seeds.seeds(cand_seeds.start(seed, opt("first-seed", "0")) + 11 + k + cand_seeds.CAND_STEP + g.LOOK_SEED_STEP * (cand_seeds.job_attempt() - 1), len(ks), cand_seeds.job_tag())
            for c, ck in enumerate(ks):
                g.render(ck, p, vrefs, {"subject": noun, "view": None, "subjects_max": 1}, vseeds[c], tries=1, init=vinit, denoise=vden)
            log("  %s candidates: %s" % (view, sheet(ks, "%s_%s_cands.png" % (key, view))))
            continue
        img, _ = g.render("%s_%s" % (key, view), p, vrefs, {"subject": noun, "view": None, "subjects_max": 1}, seed + 11 + k, tries=1,
                          init=vinit, denoise=vden)
        out[view] = refine(img, "%s_%s" % (key, view), recipe, vrefs, seed + 11 + k, bg, p) if rp else img
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
    if os.environ.get("GEN_CTL_FOLDER") and os.path.isdir(os.environ["GEN_CTL_FOLDER"]):
        # pass 96 (lane LOOP): a dry run's copy of the creature folder (tools/asset_job.py _dry_folder, as gen_art's dry
        # run has had since pass 71): the strip, the icon and the marker land in the copy, never in game/content
        folder = os.environ["GEN_CTL_FOLDER"]
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
    # pass 94: the look's recorded painter {model, steps, guidance, turbo} (gen_art.apply_painter; a job's own settings win)
    g.apply_painter(recipe.get("painter"))
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
    # pass 94: a repainted look without the style anchor (a realistic look) is not told "anime ... cel shading"
    if repaint_mode(recipe) and not repaint_anchor(recipe):
        kind_words, finish_words = "A realistic game creature, ", ", the same realistic detail, fine hairs and soft light as the reference"
    else:
        kind_words, finish_words = "A 2D anime game creature sprite, ", ", crisp clean line art, cel shading"
    motion = (kind_words + recipe["prompt"].split(",")[0] + ", " + recipe.get("motion", "walking in place") +
              " exactly as the control video shows, the same creature, colours and markings as the reference in every frame, "
              + anatomy_short + finish_words + ". The camera is completely locked off and static. The background stays a flat "
              "solid bright " + ("blue" if bg == g.BG_BLUE else "green") + " color with nothing in it, no ground, no shadow.")
    two = int(recipe.get("directions", 8)) == 2
    walks = {}
    sizes = {}
    for view in (["front", "back"] if two else VIEWS):
        # "walk_seeds" {view: n} rolls one view's walk again with another seed (pass 49: BB-B's three-quarter front painted
        # its long horn as a see-through grey ghost); since pass 92 the walk cache follows the seed and the painting
        # (animate.cache_fits), so that view's ai_anim folder no longer has to be moved away first
        wseed = seed + 20 + VIEWS.index(view) + 1000 * int((recipe.get("walk_seeds") or {}).get(view, 0))
        # pass 92: "ctl_soft" {radius, body, views}: the body's depth softened so a painted face survives the walk
        # pass 99 (lane SPIDER): "view_drivers" {view: name}: that view walks on another driver than "drivers"
        vdrv = os.path.join(REPO, "tools", "dl", "drivers", str((recipe.get("view_drivers") or {}).get(view) or recipe["drivers"]))
        cdir = soft_dir(recipe, os.path.join(vdrv, view), view)
        # pass 93: "fit_ref" true (or a list of views): the painting fitted onto the depth figure first (fit_to_ctl)
        fr = recipe.get("fit_ref")
        # (a number 0..1 fits that share of the way: fit_to_ctl's share)
        share = 1.0 if (fr is True or (isinstance(fr, list) and view in fr)) else (float(fr) if isinstance(fr, (int, float)) and not isinstance(fr, bool) else 0.0)
        # pass 94: a clay_fill painting goes back where its crop came from in the driver's frame first
        src = uncrop(views[view], clay_for(recipe, drv, view)[1]) if repaint_mode(recipe) else views[view]
        ref = fit_to_ctl(src, os.path.join(vdrv, view), share=share) if share > 0 else src
        frames, _ = animate.cycle_control(ref, key + "_ctl_" + view, cdir, wseed, prompt=motion,
                                          negative_extra=str(recipe.get("anim_negative", d.get("anim_negative", ""))), wan=recipe.get("wan"))
        k = model_scale(frames, os.path.join(vdrv, view))
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
        dmotion = (kind_words + recipe["prompt"].split(",")[0] + ", dying exactly as the control video shows: "
                   + recipe.get("death_motion", "it rears up in a spasm, rolls over onto its back and lies dead with its legs curled up in the "
                                "air, the pale underside of its body showing") + ". The same creature, colours and markings as the reference in "
                   "every frame, " + anatomy_short + finish_words + ". The camera is completely locked off and static. The "
                   "background stays a flat solid bright " + ("blue" if bg == g.BG_BLUE else "green") + " color with nothing in it, no ground, no shadow.")
        # "death_keep": which 8 of the clip's 25 frames to keep (Wan smears some of the roll; picked by eye from
        # tools/dl/ai_anim/<key>_death/full_NN.png and re-picked without a render)
        dkeep = tuple(int(v) for v in recipe.get("death_keep", (1, 4, 7, 10, 13, 16, 20, 24)))
        dfront = uncrop(front, clay_for(recipe, drv, "front")[1]) if repaint_mode(recipe) else front
        dclip, _ = animate.oneshot_control(dfront, key + "_death", soft_dir(recipe, ddir, "front", "death_soft"), seed + 30, prompt=dmotion,
                                           negative_extra=str(recipe.get("anim_negative", d.get("anim_negative", ""))), keep=dkeep, wan=recipe.get("wan"))
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
            frames[k] = [no_green(f, recipe.get("no_green", True)) for f in frames[k]]
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
    frames_store.hook_after_save(folder, cid, code, counts, cols, fname, log)   # pass 95: the frames store follows the strip (pinned slots warned)
    iname = cid + "_icon_" + letter + ".png"
    # pass 76: a pick has a file of its own since the Level Editor's icon guard (<id>_icon_<x>_<tag>_c<k>.png)
    if isinstance(entry, dict) and entry.get("icon_picked") and entry.get("icon") and os.path.isfile(os.path.join(folder, os.path.basename(str(entry["icon"])))):
        iname = os.path.basename(str(entry["icon"]))
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


def soft_dir(recipe, ctl_dir, view, key="ctl_soft"):
    """The control video a view walks along: the driver's own, or its softened copy when the recipe's `ctl_soft` (or, for
    the death, `death_soft`) names this view: {"radius": 14, "body": true, "views": ["front", "fd"]} (no views: all)."""
    cs = recipe.get(key)
    if not isinstance(cs, dict) or not float(cs.get("radius", 0) or 0):
        return ctl_dir
    vs = cs.get("views")
    if vs and view not in vs:
        return ctl_dir
    return animate.soften_ctl(ctl_dir, float(cs["radius"]), bool(cs.get("body", True)), int(cs.get("open", 9)))


def noun_or(recipe):
    return recipe.get("noun", "a creature")


def keeps_picked_icon(entry, icon_path):
    """pass 68 (review): a look whose icon was picked from candidates (the Level Editor marks its entry `icon_picked`)
    keeps that file: the run does not paint the front-still crop over it (gen_art's rule); its entry still names it."""
    return bool(isinstance(entry, dict) and entry.get("icon_picked") and os.path.isfile(icon_path))


if __name__ == "__main__":
    main()

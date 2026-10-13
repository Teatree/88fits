"""The Puppet trial (hero_puppet, 2026-10-13): a hero's painting turned into a rigged, animated 3D figure, whose renders
then guide the video model instead of a flat Mixamo stick figure. Plan: https://claude.ai/artifact/5B4qnyf76VsjEPSXnsX4Kf

    python tools/puppet.py may                                  # every stage still missing, in order
    python tools/puppet.py may --stage apose|shape|rig|anim|guides|looks|compare [--force]
    python tools/puppet.py may --pick front=2                   # the arms-out front picked by eye (then side and back)
    python tools/puppet.py may --pick side=1 back=0
    python tools/puppet.py may --pick shape=1                   # the Hunyuan3D try kept
    python tools/puppet.py may --from-blend                     # Garry fixed the rig in may_puppet.blend: anim export,
                                                                #   guides, looks and compare again from his file
    python tools/puppet.py may --from-fbx <file>                # a Mixamo-rigged FBX (mixamo.com) instead of our rig

Every stage writes under tools/dl/puppet/<hero>/ and is resumable (a stage whose outputs exist is skipped unless
--force or --stage names it):
  apose    Klein edits of the look's front still (MAY-G's), the arms held 40-45 degrees out from the body, several seeds
           -> apose/front_cN.png + apose/front_sheet.png; a pick -> apose_front.png; then the side (facing right) and the
           back in the same pose, edited from the pick and the look's own side/back stills -> apose_side.png,
           apose_back.png. The arms must be clear of the body: a hanging arm fuses into the torso in 3D and cannot be rigged.
  shape    Hunyuan3D 2 multi-view (tencent/Hunyuan3D-2mv, models/checkpoints/hunyuan3d-dit-v2-mv.safetensors on the AI
           server) through ComfyUI's built-in nodes; ComfyUI restarted before and after (the server's RAM); the views
           keyed onto white, 85 % of the square (the model's own border 0.15); the side still is Hunyuan's "right" view
           (the figure faces screen-right), its mirror the "left" -> shape/try_N.glb; the pick -> shape_raw.glb, cleaned
           in Blender (tools/puppet_blender.py mode=clean: the largest piece, voxel remesh, decimated, feet at the
           origin, her game height in metres, facing -Y) -> shape.glb.
  rig      tools/puppet_blender.py mode=rig: joints from the mesh (A-pose slices) and the painting, Mixamo bone names
           (mixamorig:Hips ...), automatic weights (bone heat; the fallback is our own distance weights), the beret
           and hair on the head -> may_puppet.blend (mesh "May", armature "May_Rig").
  anim     tools/puppet_blender.py mode=anim: tools/dl/mixamo/running.fbx retargeted by bone directions (her A-pose
           rest against Mixamo's T-pose), the hips' bob scaled to her legs, feet on the ground, in place; an idle
           (breathing, arms down; there is no Mixamo idle on disk); vertex colours projected from the arms-out
           paintings -> may_puppet.glb (animations "run", "idle"), may_puppet_preview.png; then the GLB and the preview to
           E:/My Drive/88fits builds/puppets/ and GLB_READY.json (the lead tells Garry).
  guides   OpenPose drivers from HER bones in tools/pose_driver.py's five views, framing and folder layout, a joint
           hidden behind her own mesh dropped (ray cast from the camera) -> tools/dl/drivers/<hero>_puppet_run; depth
           videos from the GLB (tools/blender_depth_drivers.py, 24 poses x 2 strides + 1) -> <hero>_puppet_run_depth.
  looks    through the running Level Editor's HTTP API: <P> (hero_pose5, the base look's stills reused, pose_drivers =
           the puppet run in every view, no run_scale) and <Q> (gen_art's ctl_drivers: Wan 2.2 Fun Control on the
           depth guides, the same stills); the base look's badge and cut-out installed on both; both fresh.
  compare  contact sheets base vs P vs Q per view (run, idle), the head's size in the run against the idle per view,
           hands in the back run, the straps in the bd views, the shoulders' tilt -> compare/, a verdict.
Timings, picks and failures: stages.json beside the outputs; tools/dl/puppet/status_PUPPET.md is the lane's log.

Pass 71 (lane PLE: the Puppet method in the Level Editor, method `hero_puppet`) made it any hero's:
    --look CODE              the look whose stills are the source (default: the one he is played in)
    --ref front=paint side=still:<key> back=<picture>|none
                             the 3D reference per view: "paint" (arms-out candidates, the default), a still of any look
                             (tools/dl/ai_raw_anime/<key>.png), an uploaded picture (a repo path), or "none" (side/back
                             left out of the shape)
    --screen green|blue      the painting screen (default: the look's recipe, else the hero's, else blue; Jezyk is green)
    --painter klein|dev [--steps N] [--no-turbo] [--seed N] [--seeds N] [--words-front/--words-side/--words-back "..."]
    --reroll front|views|shape   the candidates of that pick moved aside (old/<stamp>/) and painted again (--seed N)
    --reset-from STAGE       that stage's outputs and the later ones moved aside (old/<stamp>/): it runs again
    --clip running.fbx [--idle <fbx>]   the moving clip (tools/dl/mixamo/) and the idle (default: procedural)
    --frame soles|ankles     the OpenPose guides framed by the soles (default; the boots stay in the canvas) or the ankles
    --face nose|head         the face angle: the ears from the measured nose (default: a side view stays in profile) or
                             on the head bone's axis (the trial's first guide, which turned May's side run to the camera)
    --lane comfy|local       the Level Editor's job lanes: stops with "puppet: NEXT lane X" where the work changes lane;
                             a pick stops with "puppet: PICK front|views|shape"; the end of --until with "puppet: DONE"
    --dry-run [--out-root D] nothing reaches ComfyUI or Blender: every prompt, graph and command is recorded in
                             <D>/dry_run.json, the picks are c0, stand-in files under <D>/<hero>/ and <D>/drivers/
The guides are versioned: <hero>_puppet_<clip> (running.fbx = run), a new folder _2, _3 ... whenever the framing, the
clip or the GLB changed (the looks that walked on the old guides keep them); each guide folder holds its silhouette.json.
"""
import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

BLENDER = os.path.join(os.environ.get("LOCALAPPDATA", r"C:\Users\Garry\AppData\Local"), "Programs", "blender-5.2.0-windows-x64", "blender.exe")
CONTENT = os.path.join(REPO, "game", "content", "characters")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_anime")
DRIVERS = os.path.join(REPO, "tools", "dl", "drivers")
# the guides as they are on disk: a dry run reads them here (which exist, which match) and writes its stand-ins to DRIVERS
DRIVERS_REAL = DRIVERS
MIXAMO = os.path.join(REPO, "tools", "dl", "mixamo")
PUPPETS = os.path.join(REPO, "tools", "dl", "puppet")
DRIVE = r"E:/My Drive/88fits builds/puppets"
LE = os.environ.get("LEVEL_EDITOR", "")
HY_CKPT = "hunyuan3d-dit-v2-mv.safetensors"
STAGES = ["apose", "shape", "rig", "anim", "guides", "looks", "compare"]
VIEWS3 = ("front", "side", "back")
# the game draws a hero's 256 px cell 1.9 m tall (Player._setup_sprite: sprite.setup(..., 1.9, ...))
CELL_M = 1.9
# pass 71: the mesh's object name in the .blend (the armature is <NAME>_Rig), set from the hero id in main()
NAME = ["May"]
# pass 71: the dry run (--dry-run): nothing reaches ComfyUI or Blender, every call is recorded
DRY = {"on": False, "path": "", "notes": [], "t0": 0.0}


def log(*a):
    print("[puppet %s]" % time.strftime("%H:%M:%S"), *a, flush=True)


def dry_note(kind, **kw):
    """One record of what a dry run would have sent (written at once: a dry run that fails keeps what it reached)."""
    kw["kind"] = kind
    kw["t"] = round(time.time() - DRY["t0"], 2)
    DRY["notes"].append(kw)
    with open(DRY["path"], "w", encoding="utf-8", newline="\n") as f:
        json.dump({"dry_run": True, "tool": "puppet", "prompts": DRY["notes"]}, f, indent=1, ensure_ascii=False)


def name_of(hero):
    """The mesh's object name in the .blend: the hero id in letters ("may" -> "May", "buck" -> "Buck")."""
    s = re.sub(r"[^A-Za-z0-9]", "", hero.title())
    return s or "Hero"


class Ctx:
    def __init__(self, hero, look=None, out_root=None):
        self.hero = hero
        self.out = os.path.join(out_root or PUPPETS, hero)
        os.makedirs(self.out, exist_ok=True)
        self.jpath = os.path.join(CONTENT, hero, hero + ".json")
        self.d = json.load(open(self.jpath, encoding="utf-8"))
        self.look = look or str(self.d.get("variant") or self.d.get("variant_base") or "")
        self.entry = (self.d.get("variants") or {}).get(self.look) or {}
        self.recipe = self.entry.get("recipe") or {}
        self.slug = str(self.recipe.get("stills") or "")
        self.state_p = os.path.join(self.out, "stages.json")
        self.state = json.load(open(self.state_p, encoding="utf-8")) if os.path.exists(self.state_p) else {}
        self.screen = str(self.recipe.get("screen") or self.d.get("screen") or "blue").lower()

    def still(self, view):
        """The look's painting of a view (tools/dl/ai_raw_anime/<id>_<slug>_<view>; a still_keys view names its own)."""
        sk = self.recipe.get("still_keys") if isinstance(self.recipe.get("still_keys"), dict) else {}
        if sk.get(view):
            return os.path.join(RAW, str(sk[view]) + ".png")
        return os.path.join(RAW, "%s%s_%s.png" % (self.hero, "_" + self.slug if self.slug else "", view))

    def who(self):
        """The character in words, for the arms-out edits: the look's or the hero's `appearance`, else its art_prompt
        without the pose clause (the part after the first ';')."""
        a = str(self.recipe.get("appearance") or self.d.get("appearance") or "").strip()
        if not a:
            a = str(self.recipe.get("art_prompt") or self.d.get("art_prompt") or "").split(";")[0].strip()
        return a.rstrip(". ")

    def p(self, *parts):
        return os.path.join(self.out, *parts)

    def save(self):
        with open(self.state_p, "w", encoding="utf-8", newline="\n") as f:
            json.dump(self.state, f, indent=1)

    def mark(self, stage, **kw):
        rec = self.state.setdefault(stage, {})
        rec.update(kw)
        self.save()


def keyed(img, ctx):
    """A still on its screen -> RGBA, with the hero's own key settings (gen_art.process's)."""
    import artkit
    d = dict(ctx.d)
    d.update(ctx.recipe)
    artkit.KEY_SAT = float(d.get("key_sat", 0.35))
    artkit.KEY_MIN_V = float(d.get("key_min_value", 0.2))
    artkit.KEY_CUT_SHADOW = bool(d.get("key_cut_shadow", True))
    artkit.KEY_CLAMP_SCREEN = bool(d.get("key_clamp_screen", False))
    return artkit.key_background(img)


# ---------------------------------------------------------------- apose

BLUE = ("isolated on a flat solid bright blue (#0000FF) background that fills the entire frame, floating in empty space with no "
        "ground plane, no cast shadow, no text, no watermark")
# pass 71: the screen the arms-out paintings are made on (the hero's own: Jezyk's blue skin goes on green)
SCREENS = {"blue": BLUE, "green": BLUE.replace("bright blue (#0000FF)", "bright green (#00FF00)")}
# "arms held straight out, 45 degrees down from the shoulders" came back as a near T-pose (25 degrees below the
# horizontal, tools/dl/puppet/may/apose/wide/); this wording gives the 45-degree A-pose. Pass 71: the words are any hero's
# (the trial's named May's beret and straps); {screen} is the screen colour, {who} the character in words (the front
# only: the side and the back follow the picked front and the look's own still; a back_hint describes the standing pose,
# arms down, and is left out). Each view's words can be replaced whole (--words-front / --words-side / --words-back).
APOSE_FRONT = ("Edit the reference image: the exact same character with the same head, face, outfit, colours, proportions and art "
               "style, full body seen straight from the front, standing straight and facing the viewer in a relaxed A-pose for a 3D model "
               "turnaround sheet: both arms hang down and out to the sides at 45 degrees from the body, so the hands are at the height of "
               "the hips but a forearm's length out to the side of them, the elbows straight, the hands open with the palms facing the "
               "legs, clear {screen} background between each arm and the torso all the way from the armpit to the hand; the legs straight "
               "and a little apart with a gap between them, the feet fully visible. Nothing in the hands. {who}")
APOSE_SEED = 2026101377
# the A-pose's arms reach out sideways, toward and away from a side camera, so in profile the near arm hangs straight down
# over the side of the torso with the hand at hip height (not held forward)
APOSE_SIDE = ("The first reference image shows a character standing in an A-pose, the arms held out to the sides. The second reference "
              "image shows how the same character looks from the side. Draw the same character seen from the side in a strict profile, "
              "facing to the right of the frame, standing straight: the arms reach out sideways toward and away from the viewer, so from "
              "the side the near arm hangs straight down over the side of the torso with the hand at the height of the hips, nothing held "
              "forward, the far arm hidden behind the body, the legs straight. Keep the outfit, colours, proportions and art style of "
              "the references, the same height as the first image. ")
APOSE_BACK = ("The first reference image shows a character standing in an A-pose, the arms held out to the sides. The second reference "
              "image shows how the same character looks from behind. Draw the same character in exactly the same A-pose seen directly "
              "from behind: the back of the head, no face visible, both arms held straight out away from the body and angled 45 degrees "
              "down from the shoulders, a wide gap between each arm and the torso, the legs straight and a little apart. Keep the outfit "
              "(what its back shows), the colours, the proportions and the art style of the references. ")
APOSE_WORDS = {"front": APOSE_FRONT, "side": APOSE_SIDE, "back": APOSE_BACK}
SEED_STEP = 7919


def apose_words(ctx, view, args):
    """The edit's words for one view: the view's own words when given (--words-<view>), else the template filled in."""
    own = str(getattr(args, "words_" + view, "") or "").strip()
    if own:
        return own.rstrip(" ") + " "
    who = ctx.who()
    return APOSE_WORDS[view].format(screen=screen_of(ctx, args), who=("The character: %s. " % who) if who else "")


def screen_of(ctx, args):
    s = str(getattr(args, "screen", "") or "").lower()
    return s if s in SCREENS else (ctx.screen if ctx.screen in SCREENS else "blue")


def ref_of(args, view):
    """The 3D reference of a view (--ref view=src): "paint" (arms-out candidates; the default), "none" (side or back left
    out of the shape), "still:<key>" (a painting of any look, tools/dl/ai_raw_anime/<key>.png) or a picture's path."""
    for pair in getattr(args, "ref", None) or []:
        v, _, src = str(pair).partition("=")
        if v.strip() == view and src.strip():
            return src.strip()
    return "paint"


def ref_path(src):
    """The file of a --ref value that is a picture: a still key or a path (repo-relative or absolute)."""
    if src.startswith("still:"):
        key = src[6:]
        return os.path.join(RAW, key if key.endswith(".png") else key + ".png")
    return src if os.path.isabs(src) else os.path.join(REPO, src)


def _paint_cands(ctx, name, prompt, refs, seeds, base_seed, args):
    """Arms-out candidates of one view (<name>_c<k>.png under apose/), Klein (4 steps) or Flux.2 dev (--painter dev),
    each with its JSON (seed, prompt, refs, painter, seconds); a candidate on disk is kept (the cache)."""
    from PIL import Image
    d = ctx.p("apose")
    os.makedirs(d, exist_ok=True)
    names = []
    words = prompt + SCREENS[screen_of(ctx, args)] + "."
    painter = getattr(args, "painter", "klein") or "klein"
    for k in range(seeds):
        f = os.path.join(d, "%s_c%d.png" % (name, k))
        if not os.path.exists(f):
            s = base_seed + k * 1000003
            if DRY["on"]:
                dry_note("paint", view=name, candidate=k, painter=painter, steps=int(getattr(args, "steps", 0) or 0), seed=s, prompt=words, refs=refs)
                src = refs[-1] if refs and os.path.isfile(str(refs[-1])) else None
                (Image.open(src).convert("RGB") if src else Image.new("RGB", (1024, 1024), (0, 255, 0))).save(f)
                secs = 0.0
            else:
                import comfy
                if painter == "dev":
                    steps = int(getattr(args, "steps", 0) or 0) or 8
                    g = comfy.flux2_dev(words, s, 1024, 1024, refs=refs, steps=steps, turbo=not getattr(args, "no_turbo", False),
                                        prefix="88fits/puppet_%s_%s" % (ctx.hero, name))
                    imgs, secs = comfy.run_dev(g)
                else:
                    steps = int(getattr(args, "steps", 0) or 0) or 4
                    imgs, secs = comfy.run(comfy.klein(words, s, 1024, 1024, refs=refs, steps=steps, prefix="88fits/puppet_%s_%s" % (ctx.hero, name)))
                Image.open(io.BytesIO(imgs[0])).convert("RGB").save(f)
            json.dump({"seed": s, "prompt": words, "refs": [str(r) for r in refs], "painter": painter, "seconds": round(secs, 1)},
                      open(f[:-4] + ".json", "w", encoding="utf-8"), indent=1)
            # the jobs parser reads this line (RE_ICON's shape): the candidate's stage ticks on the job card
            log("  %s c%d seed %d %.0fs" % (name, k, s, secs))
        names.append(f)
    _sheet(names, os.path.join(d, name + "_sheet.png"))
    return names


def _sheet(paths, out, w=360, labels=None):
    from PIL import Image, ImageDraw
    ims = [Image.open(p).convert("RGB") for p in paths]
    sheet = Image.new("RGB", (w * len(ims), w + 24), (30, 30, 36))
    dr = ImageDraw.Draw(sheet)
    for i, im in enumerate(ims):
        sheet.paste(im.resize((w, w)), (i * w, 24))
        dr.text((i * w + 6, 5), labels[i] if labels else os.path.basename(paths[i]), fill=(255, 230, 140))
    sheet.save(out)
    return out


def arms_clearance(path, ctx):
    """How clear the arms are of the body on an arms-out front: per row between the shoulders and the hips, the figure's
    runs of opaque pixels; rows with three or more runs (arm, torso, arm) as a share of that band. 1 = arms free all
    the way down, 0 = arms against the body."""
    import numpy as np
    from PIL import Image
    a = np.asarray(keyed(Image.open(path).convert("RGB"), ctx))[..., 3] > 127
    ys = np.nonzero(a.any(axis=1))[0]
    if not len(ys):
        return 0.0, 0.0
    top, bot = ys.min(), ys.max()
    H = bot - top
    band = range(int(top + H * 0.22), int(top + H * 0.48))
    free = 0
    for y in band:
        xs = np.nonzero(a[y])[0]
        runs = np.split(xs, np.nonzero(np.diff(xs) > 3)[0] + 1) if len(xs) else []
        if len([r for r in runs if len(r) > 2]) >= 3:
            free += 1
    width = (np.ptp(np.nonzero(a.any(axis=0))[0]) + 1) / max(1, H)
    return round(free / max(1, len(band)), 3), round(float(width), 3)


def _upload(img, name):
    if DRY["on"]:
        dry_note("upload", name=name, size=list(img.size))
        return name
    import comfy
    return comfy.upload_pil(img, name)


def _cands_exist(ctx, name, n):
    return all(os.path.exists(ctx.p("apose", "%s_c%d.png" % (name, k))) for k in range(n))


def side_back_seeds(args):
    return max(3, int(args.seeds) // 2)


def stage_apose(ctx, args):
    """The arms-out paintings the 3D shape is made from. Per view (--ref): a picture given is copied as it is; "paint"
    paints candidates (the front an edit of the look's front still; the side and the back edits of the picked front and
    the look's own side / back still) and stops for the pick ("pick:front", then "pick:views"); "none" leaves a side or
    back out of the shape."""
    # pass 72: the job's First seed (--first-seed, 0 = APOSE_SEED: cand_seeds' start), candidate k CAND_STEP from k-1
    first = int(getattr(args, "first_seed", 0) or 0)
    seed0 = (first or APOSE_SEED) + int(getattr(args, "seed", 0) or 0) * SEED_STEP
    for view in VIEWS3:
        src = ref_of(args, view)
        dst = ctx.p("apose_%s.png" % view)
        if src in ("paint", "none") or os.path.exists(dst):
            continue
        p = ref_path(src)
        if not os.path.isfile(p):
            raise RuntimeError("the %s reference %s is not on disk (%s)" % (view, src, p))
        _open_rgb(p).save(dst)
        ctx.state.setdefault("apose", {}).setdefault("sources", {})[view] = src
        ctx.save()
        log("%s: the given picture %s -> apose_%s.png (no painting)" % (view, src, view))
    if not os.path.exists(ctx.p("apose_front.png")):
        if ref_of(args, "front") == "none":
            raise RuntimeError("the front cannot be left out: the shape is made from it")
        if not _cands_exist(ctx, "front", args.seeds):
            t0 = time.time()
            front_ref = _upload(_open_rgb(ctx.still("front")), "puppet_%s_front_ref.png" % ctx.hero) if not DRY["on"] else ctx.still("front")
            paths = _paint_cands(ctx, "front", apose_words(ctx, "front", args), [front_ref], args.seeds, seed0, args)
            scores = {os.path.basename(p): arms_clearance(p, ctx) for p in paths} if not DRY["on"] else {}
            ctx.mark("apose", front_cands=scores, front_seconds=round(time.time() - t0, 1), painter=args.painter, screen=screen_of(ctx, args))
            log("arms-out fronts painted: %s (arms clear, width/height): %s" % (ctx.p("apose", "front_sheet.png"), scores))
        log("pick one by eye: python tools/puppet.py %s --pick front=N" % ctx.hero)
        return "pick:front"
    need = [v for v in ("side", "back") if ref_of(args, v) == "paint" and not os.path.exists(ctx.p("apose_%s.png" % v))]
    if need:
        n = side_back_seeds(args)
        if not all(_cands_exist(ctx, v, n) for v in need):
            t0 = time.time()
            pick_ref = _upload(_open_rgb(ctx.p("apose_front.png")), "puppet_%s_apose_front.png" % ctx.hero) if not DRY["on"] else ctx.p("apose_front.png")
            for v, off in (("side", 17), ("back", 31)):
                if v not in need:
                    continue
                refs = [pick_ref]
                if os.path.exists(ctx.still(v)):
                    refs.append(_upload(_open_rgb(ctx.still(v)), "puppet_%s_%s_ref.png" % (ctx.hero, v)) if not DRY["on"] else ctx.still(v))
                _paint_cands(ctx, v, apose_words(ctx, v, args), refs, n, seed0 + off, args)
            ctx.mark("apose", views_seconds=round(time.time() - t0, 1))
        log("%s candidates: %s; pick: --pick %s" % (" and ".join(need), ", ".join(ctx.p("apose", v + "_sheet.png") for v in need),
                                                    " ".join("%s=N" % v for v in need)))
        return "pick:views"
    return True


def _open_rgb(path):
    from PIL import Image
    return Image.open(path).convert("RGB")


def do_pick(ctx, pairs):
    """`front=2`, `side=1`, `back=0`, `shape=1` (also "side=1,back=0" in one item, as the Level Editor sends a pick)."""
    for item in pairs:
        for pair in str(item).split(","):
            if "=" not in pair:
                continue
            view, k = [x.strip() for x in pair.split("=", 1)]
            k = k.lstrip("c")
            if view in ("front", "side", "back"):
                src = ctx.p("apose", "%s_c%s.png" % (view, k))
                shutil.copy(src, ctx.p("apose_%s.png" % view))
                ctx.state.setdefault("apose", {}).setdefault("picks", {})[view] = int(k)
                log("picked %s c%s -> apose_%s.png" % (view, k, view))
            elif view == "shape":
                src = ctx.p("shape", "try_%s.glb" % k)
                shutil.copy(src, ctx.p("shape_raw.glb"))
                ctx.state.setdefault("shape", {})["pick"] = int(k)
                log("picked shape try %s -> shape_raw.glb" % k)
    ctx.save()


def _aside(ctx, paths, stamp, why):
    """Files or folders under the hero's puppet folder moved into old/<stamp>/ (kept, out of the way)."""
    moved = []
    for p in paths:
        if not os.path.exists(p):
            continue
        rel = os.path.relpath(p, ctx.out)
        dst = os.path.join(ctx.out, "old", stamp, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.move(p, dst)
        moved.append(rel.replace("\\", "/"))
    if moved:
        log("%s: moved aside to old/%s/: %s" % (why, stamp, ", ".join(moved)))
    return moved


def do_reroll(ctx, what, stamp):
    """--reroll front|views|shape: that pick's candidates moved aside so they are painted again (with --seed's shift)."""
    import glob
    if what == "front":
        paths = glob.glob(ctx.p("apose", "front_c*")) + [ctx.p("apose", "front_sheet.png")]
    elif what == "views":
        paths = glob.glob(ctx.p("apose", "side_c*")) + glob.glob(ctx.p("apose", "back_c*")) + [ctx.p("apose", "side_sheet.png"), ctx.p("apose", "back_sheet.png")]
    else:
        paths = glob.glob(ctx.p("shape", "try_*"))
        ctx.state.setdefault("shape", {}).pop("tries", None)
        ctx.state["shape"].pop("pick", None)
    _aside(ctx, paths, stamp, "re-roll of the %s candidates" % what)
    ctx.save()


def stage_outputs(ctx, stage):
    """What a stage leaves under the hero's folder (--reset-from moves these aside). The guide folders under
    tools/dl/drivers are never moved: looks walk on them; new guides get a new version once the GLB changed."""
    h = ctx.hero
    return {"apose": [ctx.p("apose_front.png"), ctx.p("apose_side.png"), ctx.p("apose_back.png"), ctx.p("apose"), ctx.p("paint")],
            "shape": [ctx.p("shape"), ctx.p("shape_raw.glb"), ctx.p("shape.glb")] + [ctx.p(f) for f in os.listdir(ctx.out) if f.startswith("shape_preview")],
            "rig": [blend_path(ctx), blend_path(ctx) + "1", ctx.p("rig")],
            "anim": [ctx.p("%s_puppet.glb" % h), ctx.p("%s_puppet_preview.png" % h), ctx.p("renders"), ctx.p("GLB_READY.json")],
            "guides": [ctx.p("silhouette.json")]}.get(stage, [])


def do_reset(ctx, stage, stamp):
    """--reset-from STAGE: that stage's outputs and every later stage's moved into old/<stamp>/, their records too."""
    order = ["apose", "shape", "rig", "anim", "guides"]
    if stage not in order:
        return []
    moved = []
    for s in order[order.index(stage):]:
        moved += _aside(ctx, stage_outputs(ctx, s), stamp, "reset from %s" % stage)
        old = ctx.state.pop(s, None)
        if old is not None:
            ctx.state.setdefault("_old", {})["%s_%s" % (s, stamp)] = old
    ctx.save()
    return moved


# ---------------------------------------------------------------- shape (Hunyuan3D 2mv on the AI server)

def _hy_view(img_rgb, ctx, mirror=False, size=1024, fill=0.85):
    """A painting keyed and laid on white, its longer side `fill` of the square (Hunyuan's border_ratio 0.15)."""
    import artkit
    from PIL import Image, ImageOps
    k = artkit.crop_alpha(keyed(img_rgb, ctx), pad=0)
    if mirror:
        k = ImageOps.mirror(k)
    s = size * fill / max(k.width, k.height)
    k = k.resize((max(1, round(k.width * s)), max(1, round(k.height * s))), Image.LANCZOS)
    canvas = Image.new("RGB", (size, size), (255, 255, 255))
    canvas.paste(k, ((size - k.width) // 2, (size - k.height) // 2), k)
    return canvas


def hunyuan_graph(views, seed, steps=30, cfg=5.0, octree=380, chunks=20000, prefix="88fits/puppet/shape"):
    import comfy
    g = comfy.Graph()
    ck = g.add("ImageOnlyCheckpointLoader", "Hunyuan3D 2mv", ckpt_name=HY_CKPT)
    enc = {}
    for view, name in views.items():
        li = g.add("LoadImage", view + " view", image=name)
        enc[view] = (g.add("CLIPVisionEncode", clip_vision=(ck, 1), image=(li, 0), crop="center"), 0)
    cond = g.add("Hunyuan3Dv2ConditioningMultiView", **enc)
    lat = g.add("EmptyLatentHunyuan3Dv2", resolution=3072, batch_size=1)
    ks = g.add("KSampler", model=(ck, 0), seed=seed, steps=steps, cfg=cfg, sampler_name="euler", scheduler="normal", denoise=1.0,
               positive=(cond, 0), negative=(cond, 1), latent_image=(lat, 0))
    vox = g.add("VAEDecodeHunyuan3D", samples=(ks, 0), vae=(ck, 2), num_chunks=chunks, octree_resolution=octree)
    mesh = g.add("VoxelToMesh", voxel=(vox, 0), algorithm="surface net", threshold=0.6)
    g.add("SaveGLB", mesh=(mesh, 0), filename_prefix=prefix)
    return g


def run_3d(graph, timeout=3600):
    """comfy.run for a SaveGLB graph: returns ([glb bytes], seconds)."""
    import uuid
    import comfy
    if DRY["on"]:
        facts = {}
        for n in graph.api().values():
            ct, inp = n.get("class_type"), n.get("inputs", {})
            if ct == "LoadImage":
                facts.setdefault("views", []).append(inp.get("image"))
            elif ct == "KSampler":
                facts.update(seed=inp.get("seed"), steps=inp.get("steps"), cfg=inp.get("cfg"))
            elif ct == "VAEDecodeHunyuan3D":
                facts["octree"] = inp.get("octree_resolution")
            elif ct == "ImageOnlyCheckpointLoader":
                facts["checkpoint"] = inp.get("ckpt_name")
        dry_note("comfy.run_3d", **facts)
        return [b"glTF dry-run stand-in"], 0.0
    comfy.save_job_workflow(graph)
    r = comfy.post("/prompt", {"prompt": graph.api(), "client_id": "88fits-" + uuid.uuid4().hex[:8]})
    if r.get("error") or r.get("node_errors"):
        raise RuntimeError("ComfyUI rejected the graph: " + json.dumps({"error": r.get("error"), "node_errors": r.get("node_errors")})[:1500])
    pid = r["prompt_id"]
    t0 = time.time()
    while True:
        time.sleep(2.0)
        comfy._beat()
        h = comfy.get("/history/" + pid)
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError("ComfyUI error: " + json.dumps(st.get("messages"))[:2500])
            out = []
            for o in h[pid].get("outputs", {}).values():
                for key in ("3d", "glbs", "meshes"):
                    for f in o.get(key, []) or []:
                        url = comfy.SERVER + "/view?filename=%s&subfolder=%s&type=%s" % (
                            urllib.parse.quote(f["filename"]), urllib.parse.quote(f.get("subfolder", "")), f.get("type", "output"))
                        out.append(urllib.request.urlopen(url, timeout=300).read())
            if not out:
                raise RuntimeError("ComfyUI produced no 3D file: %s" % json.dumps(h[pid].get("outputs"))[:800])
            return out, time.time() - t0
        if time.time() - t0 > timeout:
            try:
                comfy.post("/interrupt", {})
            except Exception:
                pass
            raise RuntimeError("ComfyUI timeout after %ds" % timeout)


def stage_shape(ctx, args):
    """Hunyuan3D-2mv tries (ComfyUI's own nodes, the server restarted before and after), each rendered in clay for the
    pick ("pick:shape"); the pick cleaned in Blender (one piece, game height, feet at 0) -> shape.glb."""
    d = ctx.p("shape")
    os.makedirs(d, exist_ok=True)
    redo = args.force_stage == "shape"
    shift = int(getattr(args, "seed", 0) or 0) * 104729
    if not os.path.exists(ctx.p("shape_raw.glb")) or redo:
        need = [k for k in range(args.tries) if redo or not os.path.exists(os.path.join(d, "try_%d.glb" % k))]
        tries = list(ctx.state.get("shape", {}).get("tries", []))
        if need:
            views = {"front": _hy_view(_open_rgb(ctx.p("apose_front.png")), ctx)}
            if os.path.exists(ctx.p("apose_back.png")):
                views["back"] = _hy_view(_open_rgb(ctx.p("apose_back.png")), ctx)
            if os.path.exists(ctx.p("apose_side.png")) and not args.front_only:
                # the side still faces screen-right: Hunyuan's "right" view; its mirror is the "left" (the model's examples:
                # left.png faces screen-left)
                views["right"] = _hy_view(_open_rgb(ctx.p("apose_side.png")), ctx)
                views["left"] = _hy_view(_open_rgb(ctx.p("apose_side.png")), ctx, mirror=True)
            for v, im in views.items():
                im.save(os.path.join(d, "in_%s.png" % v))
            _sheet([os.path.join(d, "in_%s.png" % v) for v in views], os.path.join(d, "inputs_sheet.png"), 300)
            if DRY["on"]:
                names = {v: "puppet_%s_hy_%s.png" % (ctx.hero, v) for v in views}
                dry_note("restart_server", why="before Hunyuan3D (the server's RAM)")
            else:
                import comfy
                names = {v: comfy.upload_pil(im, "puppet_%s_hy_%s.png" % (ctx.hero, v)) for v, im in views.items()}
                log("restarting ComfyUI before Hunyuan3D (the server's RAM)")
                comfy.wait_idle()
                log("  " + comfy.restart_server())
            t_all = time.time()
            for k in need:
                f = os.path.join(d, "try_%d.glb" % k)
                seed = 12345 + k * 7919 + shift
                try:
                    glbs, secs = run_3d(hunyuan_graph(names, seed, steps=args.hy_steps, octree=args.octree, prefix="88fits/puppet/%s_shape_%d" % (ctx.hero, k)))
                except Exception as e:
                    log("  Hunyuan3D try %d FAILED: %s" % (k, e))
                    tries.append({"try": k, "seed": seed, "error": str(e)[:2000]})
                    ctx.mark("shape", tries=tries)
                    if k == need[0]:
                        if not DRY["on"]:
                            import comfy
                            comfy.restart_server()
                            comfy.release_lock()
                        raise
                    break
                open(f, "wb").write(glbs[0])
                tries = [t for t in tries if t.get("try") != k] + [{"try": k, "seed": seed, "seconds": round(secs, 1), "bytes": len(glbs[0])}]
                # the jobs parser reads this line: the try's stage ticks on the job card
                log("  Hunyuan3D try %d seed %d %.0fs %d bytes" % (k, seed, secs, len(glbs[0])))
                ctx.mark("shape", tries=tries)
            if DRY["on"]:
                dry_note("restart_server", why="after Hunyuan3D")
            else:
                import comfy
                log("restarting ComfyUI after Hunyuan3D")
                log("  " + comfy.restart_server())
                comfy.release_lock()
            ctx.mark("shape", tries=tries, seconds=round(time.time() - t_all, 1), views=list(views))
        # every try rendered in clay for the pick
        for k in range(args.tries):
            f = os.path.join(d, "try_%d.glb" % k)
            if os.path.exists(f) and (redo or not os.path.exists(os.path.join(d, "try_%d.png" % k))):
                blender("clean", src=f, preview=os.path.join(d, "try_%d.png" % k), height=game_height(ctx), only_preview=1)
        if "pick" not in ctx.state.get("shape", {}):
            log("shape tries rendered: %s/try_N.png; pick: --pick shape=N" % d)
            return "pick:shape"
    if not os.path.exists(ctx.p("shape.glb")) or redo:
        t0 = time.time()
        blender("clean", src=ctx.p("shape_raw.glb"), out=ctx.p("shape.glb"), preview=ctx.p("shape_preview.png"), height=game_height(ctx),
                faces=args.faces)
        ctx.mark("shape", clean_seconds=round(time.time() - t0, 1))
    return True


def game_height(ctx):
    """Her standing height in metres as the game draws her: the look's back idle cell's figure over the 1.9 m cell."""
    import numpy as np
    from PIL import Image
    e = ctx.entry
    anims = e.get("anims") or ctx.d.get("anims")
    cols = int(e.get("strip_cols") or ctx.d.get("strip_cols"))
    fp = int(ctx.d.get("frame_px", 256))
    strip = Image.open(os.path.join(CONTENT, ctx.hero, e.get("sprite") or ctx.d.get("sprite"))).convert("RGBA")
    a = np.asarray(strip.crop((0, 0, fp, fp)))[..., 3] > 127   # idle frame 0 (the back view) is the strip's first cell
    ys = np.nonzero(a.any(axis=1))[0]
    return round(float(ys.ptp() + 1) / fp * CELL_M, 3)


# ---------------------------------------------------------------- rig

def stage_rig(ctx, args):
    if os.path.exists(blend_path(ctx)) and args.force_stage != "rig":
        return True
    t0 = time.time()
    os.makedirs(ctx.p("rig"), exist_ok=True)
    blender("rig", src=ctx.p("shape.glb"), out=blend_path(ctx), overlay=ctx.p("rig"))
    jp = ctx.p("rig", "joints.json")
    j = json.load(open(jp, encoding="utf-8")) if os.path.exists(jp) else {}
    ctx.mark("rig", seconds=round(time.time() - t0, 1), notes=j.get("notes"))
    return True


def blend_path(ctx):
    return ctx.p("%s_puppet.blend" % ctx.hero)


# ---------------------------------------------------------------- anim

def paint_inputs(ctx):
    """The arms-out paintings keyed (the hero's key settings), the screen round the figure filled with the nearest figure
    colour (so a colour sampled a pixel off the edge is still hers), as RGBA PNGs with the figure's box: what
    puppet_blender colours the mesh from. The side still faces screen-right (her right side); its mirror is her left."""
    import numpy as np
    from PIL import Image, ImageOps
    from scipy import ndimage
    d = ctx.p("paint")
    os.makedirs(d, exist_ok=True)
    meta = {}
    for view, src, mirror in (("front", "apose_front.png", False), ("back", "apose_back.png", False),
                              ("right", "apose_side.png", False), ("left", "apose_side.png", True)):
        if not os.path.exists(ctx.p(src)):
            continue
        k = keyed(_open_rgb(ctx.p(src)), ctx)
        if mirror:
            k = ImageOps.mirror(k)
        a = np.asarray(k).astype(np.float32)
        alpha = a[..., 3] > 127
        # the fill's colours from well inside the figure: the keyed rim is a blend with the screen (teal once the blue is
        # clamped), and a colour sampled a pixel off the edge must not be that
        core = ndimage.binary_erosion(a[..., 3] > 250, iterations=4)
        idx = ndimage.distance_transform_edt(~core, return_distances=False, return_indices=True)
        rgb = a[..., :3][idx[0], idx[1]]
        out = np.concatenate([rgb, a[..., 3:4]], axis=2).astype(np.uint8)
        f = view + ".png"
        Image.fromarray(out, "RGBA").save(os.path.join(d, f))
        ys, xs = np.nonzero(alpha)
        meta[view] = {"file": f, "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]}
    json.dump(meta, open(os.path.join(d, "paint.json"), "w", encoding="utf-8"), indent=1)
    return d


def preview_sheet(ctx, rd, out):
    """may_puppet_preview.png: the turntable in her colours (idle frame 0), then six frames of the run from the side,
    the front and the back."""
    from PIL import Image, ImageDraw
    info = json.load(open(os.path.join(rd, "renders.json"), encoding="utf-8"))
    tt = [Image.open(os.path.join(rd, f)).convert("RGB") for f in info["turntable"]]
    run = [Image.open(os.path.join(rd, f)).convert("RGB") for f in info["run"]]
    cell = 300
    cols = 6
    rows_run = (len(run) + cols - 1) // cols
    W = cell * cols
    sheet = Image.new("RGB", (W, 34 + cell + 30 + rows_run * cell), (24, 25, 30))
    dr = ImageDraw.Draw(sheet)
    dr.text((8, 8), "%s puppet: turntable (front, fd, side, bd, back) in the idle's first frame, then the run (side, front, back)" % ctx.hero, fill=(255, 230, 140))
    tw = W // len(tt)
    for i, im in enumerate(tt):
        sheet.paste(im.resize((min(tw, cell), min(tw, cell))), (i * tw + (tw - min(tw, cell)) // 2, 34))
    y0 = 34 + cell + 30
    dr.text((8, y0 - 22), "run frames %s of %d" % (info["run_frames"], info["run_n"]), fill=(200, 200, 210))
    for i, im in enumerate(run):
        sheet.paste(im.resize((cell, cell)), ((i % cols) * cell, y0 + (i // cols) * cell))
    sheet.save(out)
    return out


def clip_path(name):
    """A clip named as the form names it (a file in tools/dl/mixamo/, or a repo path, or an absolute one)."""
    if not name:
        return ""
    if os.path.isabs(name):
        return name
    if os.path.exists(os.path.join(MIXAMO, name)):
        return os.path.join(MIXAMO, name)
    return os.path.join(REPO, name)


def rel(p):
    try:
        return os.path.relpath(p, REPO).replace("\\", "/")
    except ValueError:
        return str(p).replace("\\", "/")


def stage_anim(ctx, args):
    """The moving clip (--clip, default running.fbx) retargeted onto the rig as "run", the idle (--idle: a Mixamo clip
    retargeted, else the procedural breathing idle), the colours from the arms-out paintings, the GLB and its preview.
    Made again when the clip or the idle asked for differs from the one the GLB has (the old GLB moved aside)."""
    glb = ctx.p("%s_puppet.glb" % ctx.hero)
    clip = clip_path(getattr(args, "clip", "") or "running.fbx")
    idle = clip_path(getattr(args, "idle", "") or "")
    want = {"clip": rel(clip), "idle": rel(idle) if idle else "procedural"}
    have = ctx.state.get("anim", {})
    same = (have.get("clip") or "tools/dl/mixamo/running.fbx") == want["clip"] and (have.get("idle") or "procedural") == want["idle"]
    if os.path.exists(glb) and same and args.force_stage != "anim" and not (args.from_blend or args.from_fbx):
        return True
    if not os.path.isfile(clip) and not DRY["on"]:
        raise RuntimeError("the clip %s is not on disk" % clip)
    if os.path.exists(glb) and not same:
        _aside(ctx, [glb, ctx.p("%s_puppet_preview.png" % ctx.hero)], time.strftime("%Y%m%d-%H%M%S"),
               "a new clip (%s, idle %s; the GLB had %s, idle %s)" % (want["clip"], want["idle"], have.get("clip") or "running.fbx", have.get("idle") or "procedural"))
    t0 = time.time()
    rd = ctx.p("renders")
    src = args.from_fbx or blend_path(ctx)
    blender("anim", src=src, clip=clip, idle=idle or None, paint=paint_inputs(ctx) if not DRY["on"] else ctx.p("paint"), out=glb, renders=rd,
            save=blend_path(ctx))
    prev = ctx.p("%s_puppet_preview.png" % ctx.hero)
    if DRY["on"]:
        if os.path.exists(prev):
            os.remove(prev)
        open(prev, "wb").close()
    else:
        preview_sheet(ctx, rd, prev)
    ctx.mark("anim", seconds=round(time.time() - t0, 1), glb=glb, preview=prev, source=src, clip=want["clip"], idle=want["idle"])
    if not DRY["on"] and not getattr(args, "no_drive", False):
        hand_off(ctx, glb, prev)
    return True


def hand_off(ctx, glb, prev):
    """The GLB and its preview to Drive, and GLB_READY.json for the lead (who tells Garry). Never waits."""
    copies = {}
    try:
        os.makedirs(DRIVE, exist_ok=True)
        for f in (glb, prev):
            dst = DRIVE + "/" + os.path.basename(f)
            shutil.copy2(f, dst)
            copies[os.path.basename(f)] = dst
    except OSError as e:
        log("Drive copy failed: %s" % e)
    rec = {"glb": glb.replace("\\", "/"), "preview": prev.replace("\\", "/"), "drive_copy": copies.get(os.path.basename(glb), ""),
           "drive_preview": copies.get(os.path.basename(prev), ""), "time": time.strftime("%Y-%m-%d %H:%M:%S"),
           "animations": ["run", "idle"], "blend": blend_path(ctx).replace("\\", "/")}
    with open(ctx.p("GLB_READY.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(rec, f, indent=1)
    log("GLB ready: %s (Drive: %s)" % (glb, rec["drive_copy"] or "not copied"))


# ---------------------------------------------------------------- guides

def clip_slug(args):
    """The guides' clip part: running.fbx = run (the trial's may_puppet_run), else the clip file's stem."""
    stem = os.path.splitext(os.path.basename(getattr(args, "clip", "") or "running.fbx"))[0].lower()
    return "run" if stem == "running" else (re.sub(r"[^a-z0-9]+", "_", stem).strip("_") or "clip")


def _guides_match(name, ctx, args):
    """Whether tools/dl/drivers/<name> holds this puppet's guides as asked: the same framing (a meta without one was
    framed by the ankles: the trial's), the same clip, made after the GLB, the OpenPose and the depth sets whole."""
    d = os.path.join(DRIVERS_REAL, name)
    mp = os.path.join(d, "meta.json")
    if not os.path.isfile(mp):
        return False
    try:
        m = json.load(open(mp, encoding="utf-8"))
    except (OSError, ValueError):
        return False
    glb = ctx.p("%s_puppet.glb" % ctx.hero)
    if m.get("frame", "ankles") != getattr(args, "frame", "soles"):
        return False
    if m.get("face", "nose") != getattr(args, "face", "nose"):   # a meta without one: the trial's v3 guides (the nose)
        return False
    if (m.get("clip") or "tools/dl/mixamo/running.fbx") != rel(clip_path(getattr(args, "clip", "") or "running.fbx")):
        return False
    if os.path.exists(glb) and os.path.getmtime(glb) > os.path.getmtime(mp) + 1:
        return False
    sil_ok = os.path.exists(os.path.join(d, "silhouette.json")) or (name == "%s_puppet_run" % ctx.hero and os.path.exists(ctx.p("silhouette.json")))
    return (os.path.exists(os.path.join(d, "front", "driver_24.png")) and os.path.exists(os.path.join(DRIVERS_REAL, name + "_depth", "back", "ctl_48.png"))
            and sil_ok)


def guides_name(ctx, args):
    """(name, ready): <hero>_puppet_<clip>, or the first free _2, _3 ... when an older folder holds guides made
    otherwise (another framing, clip or GLB): a look keeps walking on the guides it was made with."""
    base = "%s_puppet_%s" % (ctx.hero, clip_slug(args))
    redo = args.force_stage == "guides" or args.from_blend or bool(args.from_fbx)
    for k in range(1, 100):
        name = base if k == 1 else "%s_%d" % (base, k)
        taken = [os.path.exists(os.path.join(root, name)) or os.path.exists(os.path.join(root, name + "_depth")) for root in {DRIVERS, DRIVERS_REAL}]
        if not any(taken):
            return name, False
        if not redo and _guides_match(name, ctx, args):
            return name, True
    raise RuntimeError("no free guide folder name under %s" % base)


def guides_silhouette(ctx, name):
    """The silhouette of a guide folder: <folder>/silhouette.json (pass 71), else the trial's tools/dl/puppet/<hero>/."""
    p = os.path.join(DRIVERS_REAL, name, "silhouette.json")
    return p if os.path.exists(p) else os.path.join(PUPPETS, ctx.hero, "silhouette.json")


def stage_guides(ctx, args):
    """OpenPose guides from the puppet's own bones (framed by the soles unless --frame ankles), depth videos from its
    GLB, and its silhouette (each view's run against its idle) -> tools/dl/drivers/<name>/ and <name>_depth/; the names
    go into stages.json "guides" (the Level Editor's job writes them into the look's recipe)."""
    name, ready = guides_name(ctx, args)
    pose_dir = os.path.join(DRIVERS, name)
    depth_dir = os.path.join(DRIVERS, name + "_depth")
    sil = os.path.join(pose_dir, "silhouette.json")
    t0 = time.time()
    clip = rel(clip_path(getattr(args, "clip", "") or "running.fbx"))
    if ready:
        log("guides %s are this puppet's as asked (framing %s, clip %s): kept" % (name, args.frame, clip_slug(args)))
        sil = guides_silhouette(ctx, name)
    else:
        blender("guides", src=blend_path(ctx), out=pose_dir, frames=24, pitch=25, frame=args.frame, face=args.face, clip=clip,
                glb=rel(ctx.p("%s_puppet.glb" % ctx.hero)))
        if DRY["on"]:
            dry_note("pose_driver draw", folder=rel(pose_dir))
        else:
            r = subprocess.run([sys.executable, os.path.join(HERE, "pose_driver.py"), "draw", pose_dir], capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError("pose_driver draw failed: %s" % (r.stderr or r.stdout)[-1500:])
        log("OpenPose guides drawn: %s/all_sheet.png" % pose_dir)
    t1 = time.time()
    if not ready:
        argv = [BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "blender_depth_drivers.py"), "--",
                "src=" + ctx.p("%s_puppet.glb" % ctx.hero), "out=" + depth_dir, "action=run", "mode=cycle", "frames=24", "cycles=2",
                "depth=tight", "forward=-Y", "inplace=0", "pitch=25"]
        log("blender_depth_drivers " + " ".join(argv[5:]))
        if DRY["on"]:
            dry_note("blender", script="blender_depth_drivers.py", argv=argv[5:])
            os.makedirs(os.path.join(depth_dir, "back"), exist_ok=True)
        else:
            r = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=3600)
            for ln in (r.stdout or "").splitlines():
                if ln.startswith("blender_depth_drivers") or "Error" in ln:
                    print("   ", ln, flush=True)
            if r.returncode != 0 or not os.path.exists(os.path.join(depth_dir, "back", "ctl_48.png")):
                raise RuntimeError("depth drivers failed: %s" % " | ".join(((r.stdout or "") + (r.stderr or "")).splitlines()[-30:]))
            depth_sheet(depth_dir)
        blender("silhouette", src=blend_path(ctx), out=sil, frames=24, pitch=25)
        if os.path.exists(sil) and not DRY["on"]:
            shutil.copy2(sil, ctx.p("silhouette.json"))   # the latest puppet's, where the trial kept it (compare reads it)
    occ = None
    try:
        occ = json.load(open(os.path.join(pose_dir, "meta.json"), encoding="utf-8")).get("occlusion")
    except (OSError, ValueError):
        pass
    ctx.mark("guides", pose_dir=pose_dir, depth_dir=depth_dir, pose_name=name, depth_name=name + "_depth", silhouette=rel(sil),
             frame=args.frame, face=args.face, clip=clip, reused=bool(ready), pose_seconds=round(t1 - t0, 1), depth_seconds=round(time.time() - t1, 1),
             occlusion=occ)
    # the jobs parser reads this line: the names the look's recipe takes
    print("puppet: GUIDES %s %s %s" % (name, name + "_depth", rel(sil)), flush=True)
    return True


def depth_sheet(depth_dir):
    """all_sheet.png for a depth guide folder: clay and every 4th depth frame per view."""
    from PIL import Image
    rows = []
    for v in ("front", "fd", "side", "bd", "back"):
        d = os.path.join(depth_dir, v)
        ims = [Image.open(os.path.join(d, "clay.png")).convert("RGB")] + [Image.open(os.path.join(d, "ctl_%02d.png" % k)).convert("RGB") for k in range(24, 49, 4)]
        rows.append(ims)
    c = 120
    sheet = Image.new("RGB", (c * len(rows[0]), c * len(rows)), (20, 20, 24))
    for r, ims in enumerate(rows):
        for i, im in enumerate(ims):
            sheet.paste(im.resize((c, c)), (i * c, r * c))
    sheet.save(os.path.join(depth_dir, "all_sheet.png"))


# ---------------------------------------------------------------- looks (through the Level Editor's HTTP API)

VIEWS5 = ["front", "fd", "side", "bd", "back"]
_LE_STARTED = []


def le_base():
    """The running Level Editor's address: LEVEL_EDITOR, else the port in the jobs lock's note (the editor that runs the
    queue); if none runs, one is started (--no-browser) and stopped at the end of the looks stage."""
    import re
    if LE:
        return LE.rstrip("/")
    try:
        owner = json.load(open(os.path.join(REPO, "tools", "dl", "locks", "jobs.lock", "owner.json"), encoding="utf-8"))
        m = re.search(r"port (\d+)", owner.get("note", ""))
        if m:
            base = "http://127.0.0.1:%s" % m.group(1)
            urllib.request.urlopen(base + "/api/status", timeout=10).read()
            return base
    except Exception:
        pass
    log("no Level Editor runs the queue: starting one on 8787 (stopped at the end of this stage)")
    p = subprocess.Popen([sys.executable, os.path.join(HERE, "level_editor", "server.py"), "--port", "8787", "--no-browser"], cwd=REPO,
                         stdout=open(os.path.join(REPO, "tools", "dl", "puppet", "le_server.log"), "w"), stderr=subprocess.STDOUT)
    _LE_STARTED.append(p)
    for _ in range(60):
        time.sleep(1)
        try:
            urllib.request.urlopen("http://127.0.0.1:8787/api/status", timeout=5).read()
            return "http://127.0.0.1:8787"
        except Exception:
            continue
    raise RuntimeError("the Level Editor did not start")


def api(base, method, path, body=None, timeout=120):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=timeout))
    except urllib.error.HTTPError as e:
        txt = e.read().decode("utf-8", "replace")
        try:
            return dict(json.loads(txt), http=e.code)
        except ValueError:
            return {"ok": False, "http": e.code, "error": txt[:800]}


def look_codes(ctx):
    prefix = ctx.look.rsplit("-", 1)[0]
    return prefix + "-P", prefix + "-Q"


def look_recipes(ctx):
    """P: the base look's recipe (its stills, seeds and words: nothing is painted again), every view's pose driver the
    puppet's OpenPose, NO run_scale (whether the puppet keeps her size by itself is the test). Q: the same, every view
    walked on the puppet's depth guide (gen_art's ctl_drivers)."""
    base = json.loads(json.dumps(ctx.recipe))
    for k in ("run_scale",):
        base.pop(k, None)
    base["stills"] = ctx.slug
    p = dict(base)
    pg = ctx.state.get("guides", {}).get("pose_name") or "%s_puppet_run" % ctx.hero
    p["pose_drivers"] = {v: pg for v in VIEWS5}
    q = dict(p)
    # the depth video carries no face: the front walks on the OpenPose guide (Fun Control painted a crosshatched face,
    # then long hair, from the front), the other views on the depth guide; words for the face and the hair (the first
    # bd painted her bob as skin)
    q["ctl_drivers"] = {v: ctx.state.get("guides", {}).get("depth_name") or pg + "_depth" for v in ("fd", "side", "bd", "back")}
    q["anim_hint"] = (str(ctx.d.get("anim_hint", "")) + ", her short straight black bob haircut and black beret, black hair all round the back "
                      "of her head; where her face shows it is a clean simple anime face: two dark eyes, a small smile, a small black "
                      "star on her cheek, pale skin").lstrip(", ")
    q["anim_negative"] = (str(ctx.d.get("anim_negative", "")) + ", crosshatching, hatching lines, a grid or mesh pattern, a veil over the face, "
                          "a distorted face, skin-coloured hair, a bald head, the back of the head without hair").lstrip(", ")
    return p, q


def base_job_spec(ctx, base):
    """The base look's own last look job (its seed and painter settings), so the new looks' clips roll the same seeds."""
    d = api(base, "GET", "/api/jobs")
    best = None
    for j in d.get("jobs", []):
        t = j.get("target") or {}
        if j.get("kind") == "look" and t.get("id") == ctx.hero and t.get("code") == ctx.look:
            best = j
    return (best or {}).get("spec") or {}


def wait_jobs(base, ids, limit_s, what):
    """Poll the jobs until every one is finished (done, failed, cancelled, unmerged, interrupted) or `limit_s` passes."""
    t0 = time.time()
    last = {}
    while True:
        states = {}
        for jid in ids:
            r = api(base, "GET", "/api/job/" + jid)
            j = r.get("job", r)
            states[jid] = j.get("state")
            pr = j.get("progress") or {}
            msg = "%s %s %s/%s %s" % (jid, j.get("state"), pr.get("done"), pr.get("total"), pr.get("stage") or "")
            if last.get(jid) != msg:
                log("  " + msg)
                last[jid] = msg
        if all(s in ("done", "failed", "cancelled", "unmerged", "interrupted") for s in states.values()):
            return states
        if time.time() - t0 > limit_s:
            log("  %s: still not finished after %d s; leaving them queued" % (what, limit_s))
            return states
        time.sleep(30)


def install_base_pictures(ctx, base, code):
    """The base look's badge and title cut-out installed on a new look (the cheapest way to give it the pictures the
    editor asks for): the install jobs the base look got, re-run with variant=<code>."""
    d = api(base, "GET", "/api/jobs")
    picks = {}
    for j in d.get("jobs", []):
        t = j.get("target") or {}
        if j.get("kind") == "install" and t.get("id") == ctx.hero and t.get("code") == ctx.look and j.get("state") == "done":
            src = (j.get("spec") or {}).get("source_job")
            srcj = api(base, "GET", "/api/job/" + src).get("job", {})
            picks[srcj.get("kind")] = (src, (j.get("spec") or {}).get("choice"))
    out = []
    for kind in ("hero_badge", "hero_title"):
        if kind not in picks:
            log("  no %s install of %s to copy" % (kind, ctx.look))
            continue
        src, choice = picks[kind]
        r = api(base, "POST", "/api/jobs/%s/install" % src, {"choice": choice, "options": {"variant": code}})
        jid = (r.get("job") or {}).get("id") if isinstance(r.get("job"), dict) else r.get("id")
        log("  %s %s #%s -> %s: %s" % (kind, src, choice, code, jid or r))
        if jid:
            out.append(jid)
    return out


def base_pictures_in_place(ctx, code):
    """The base look's badge and title cut-out named in a new look's entry (a line each, the file's layout kept): the
    landing already names the base's icon; the title is added when the entry has none."""
    e0 = (ctx.d.get("variants") or {}).get(ctx.look) or {}
    title = e0.get("title")
    raw = open(ctx.jpath, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    lines = raw.decode("utf-8").splitlines()
    d = json.loads(raw.decode("utf-8"))
    e = (d.get("variants") or {}).get(code) or {}
    if not title or e.get("title"):
        return
    out, cur, done = [], None, False
    for ln in lines:
        t = ln.strip()
        if t.startswith('"') and t.endswith("{") and t.count('"') == 2:
            cur = t.split('"')[1]
        out.append(ln)
        if cur == code and not done and t.startswith('"icon":') and t.endswith(","):
            out.append(ln[: len(ln) - len(ln.lstrip())] + '"title": %s,' % json.dumps(title))
            done = True
    if not done:
        log("  %s: no icon line to put the title after; left as it is" % code)
        return
    text = nl.join(out) + nl
    json.loads(text)
    with open(ctx.jpath, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    log("  %s: the base look's cut-out %s named in its entry" % (code, title))


def stage_looks(ctx, args):
    base = le_base()
    try:
        return _stage_looks(ctx, args, base)
    finally:
        for p in _LE_STARTED:
            p.terminate()
        _LE_STARTED.clear()


def _stage_looks(ctx, args, base):
    rec = ctx.state.setdefault("looks", {})
    code_p, code_q = look_codes(ctx)
    rp, rq = look_recipes(ctx)
    spec0 = base_job_spec(ctx, base)
    common = {"method": "hero_pose5", "skip_qa": bool(spec0.get("skip_qa", True)), "seed": int(spec0.get("seed") or 0),
              "model": spec0.get("model", "klein"), "steps": int(spec0.get("steps") or 0), "guidance": float(spec0.get("guidance") or 0),
              "turbo": spec0.get("turbo", True)}
    notes = {code_p: "the Puppet trial: %s's stills, every view's walk on OpenPose from her own rigged 3D puppet (%s_puppet_run, joints her "
                     "body hides dropped), no run_scale" % (ctx.look, ctx.hero),
             code_q: "the Puppet trial: %s's stills; fd, side, bd and back walked by Wan 2.2 Fun Control on the puppet's depth "
                     "video (%s_puppet_run_depth), the front on the puppet's OpenPose guide (the depth video has no face), no "
                     "run_scale" % (ctx.look, ctx.hero)}
    jobs = rec.setdefault("jobs", {})
    t0 = time.time()
    for code, recipe in ((code_p, rp), (code_q, rq)):
        if args.only_look and code != args.only_look:
            continue
        d = json.load(open(ctx.jpath, encoding="utf-8"))
        if code not in (d.get("variants") or {}):
            r = api(base, "POST", "/api/content/hero/%s/look" % ctx.hero, {"code": code, "note": notes[code], "recipe": recipe})
            if not r.get("ok"):
                raise RuntimeError("add_look %s: %s" % (code, r))
            log("look %s added (stub)" % code)
        old = jobs.get(code)
        rerun = args.force_stage == "looks" or args.from_blend or bool(args.from_fbx)
        if old and not rerun:
            st = api(base, "GET", "/api/job/" + old).get("job", {}).get("state")
            if st not in ("failed", "cancelled", "interrupted"):
                continue
        spec = dict(common, recipe=recipe, note=notes[code])
        if old and rerun:
            # a rig fixed by hand (--from-blend) or Mixamo's (--from-fbx): new guides, so the walks are made again from the
            # same stills (the cached clips moved aside by the editor's re-roll)
            spec["reroll"] = {"mode": "clips"}
        r = api(base, "POST", "/api/jobs", {"kind": "look", "target": {"kind": "hero", "id": ctx.hero, "code": code}, "spec": spec,
                                            "title": "%s %s (Puppet trial: %s)" % (ctx.d.get("name", ctx.hero), code,
                                                                                  "OpenPose from her rig" if code == code_p else "Fun Control on her depth")})
        jid = (r.get("job") or {}).get("id") if isinstance(r.get("job"), dict) else r.get("id")
        if not jid:
            raise RuntimeError("enqueue %s: %s" % (code, r))
        jobs[code] = jid
        log("look job %s queued for %s" % (jid, code))
        ctx.save()
    states = wait_jobs(base, [jobs[c] for c in (code_p, code_q) if c in jobs], args.look_wait, "the look jobs")
    rec["states"] = states
    rec["seconds"] = round(time.time() - t0, 1)
    ctx.save()
    inst = rec.setdefault("installs", {})
    for code in (code_p, code_q):
        jid = jobs.get(code)
        if jid and states.get(jid) == "done" and code not in inst:
            if args.install_pickers:
                # an editor from pass 70 on installs a candidate into any look (options.variant); an older one installs
                # into the job's own look (2026-10-13: the base look's badge rewritten, the title failed)
                inst[code] = install_base_pictures(ctx, base, code)
            else:
                inst[code] = []
                base_pictures_in_place(ctx, code)
            ctx.save()
    pending = [j for v in inst.values() for j in v]
    if pending:
        rec["install_states"] = wait_jobs(base, pending, 1800, "the installs")
    # the imports the landings queued (godot lane), so the strips are in the game before compare/ship
    d = api(base, "GET", "/api/jobs")
    imps = [j["id"] for j in d.get("jobs", []) if j.get("kind") == "import" and j.get("state") in ("queued", "running")
            and ctx.hero in json.dumps(j.get("target") or {}) + json.dumps((j.get("spec") or {}).get("targets") or [])]
    if imps:
        rec["import_states"] = wait_jobs(base, imps, 1800, "the imports")
    ctx.save()
    ok = all(states.get(jobs.get(c)) == "done" for c in (code_p, code_q) if c in jobs)
    return ok


# ---------------------------------------------------------------- compare

SFX = {"back": "", "bd": "_bd", "side": "_s", "fd": "_fd", "front": "_f"}


def look_cells(ctx, code):
    """{anim: [RGBA cells]} of a look's strip as the game cuts it (the JSON's anims in order, strip_cols per row)."""
    from PIL import Image
    d = json.load(open(ctx.jpath, encoding="utf-8"))
    e = (d.get("variants") or {}).get(code) or {}
    if code == d.get("variant_base") and not e.get("sprite"):
        e = d
    anims = e.get("anims") or d.get("anims")
    cols = int(e.get("strip_cols") or d.get("strip_cols"))
    fp = int(e.get("frame_px") or d.get("frame_px", 256))
    strip = Image.open(os.path.join(CONTENT, ctx.hero, e.get("sprite") or d.get("sprite"))).convert("RGBA")
    out, k = {}, 0
    for a, n in anims.items():
        cells = []
        for i in range(int(n)):
            g = k + i
            x0, y0 = (g % cols) * fp, (g // cols) * fp
            cells.append(strip.crop((x0, y0, x0 + fp, y0 + fp)))
        out[a] = cells
        k += int(n)
    return out


def _alpha(c):
    import numpy as np
    return np.asarray(c)[..., 3] > 127


def head_width(a, top, rows):
    """The widest contiguous run of one row within `rows` rows from `top` (lane ART's head_width.py)."""
    import numpy as np
    w = 0
    for y in range(top, min(a.shape[0], top + rows)):
        xs = np.nonzero(a[y])[0]
        if len(xs):
            runs = np.split(xs, np.nonzero(np.diff(xs) > 2)[0] + 1)
            w = max(w, max(len(r) for r in runs))
    return w


def glove_mask(c):
    """Her magenta gloves (and scarf): hue 290-350 degrees, saturated, not dark."""
    import numpy as np
    a = np.asarray(c.convert("RGBA")).astype(np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = a[..., :3].max(axis=2), a[..., :3].min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    hue = np.zeros_like(mx)
    d = np.maximum(mx - mn, 1e-6)
    m = mx == r
    hue[m] = ((g - b) / d)[m] % 6
    m = mx == b
    hue[m] = ((r - g) / d)[m] + 4
    hue = hue * 60.0
    return (a[..., 3] > 0.5) & (sat > 0.45) & (mx > 0.35) & (hue > 290) & (hue < 352)


def measure_view(cells, view):
    """Size of the run against the idle in one view: head width (median run / idle frame 0), figure height (median and
    largest run / idle), head top (run's highest / idle's); for the back view the gloves over her back (torso band)."""
    import numpy as np
    s = SFX[view]
    idle = _alpha(cells["idle" + s][0])
    ys = np.nonzero(idle.any(axis=1))[0]
    top, H = int(ys.min()), int(ys.ptp())
    rows = max(4, int(H * 0.10))
    wi = head_width(idle, top, rows)
    hw, hh = [], []
    for c in cells["run" + s]:
        a = _alpha(c)
        yr = np.nonzero(a.any(axis=1))[0]
        hw.append(head_width(a, int(yr.min()), rows) / max(1, wi))
        hh.append(float(yr.ptp()) / max(1, H))
    out = {"head_width": round(float(np.median(hw)), 3), "head_width_range": [round(min(hw), 3), round(max(hw), 3)],
           "height_median": round(float(np.median(hh)), 3), "height_max": round(max(hh), 3)}
    if view in ("back", "bd"):
        # gloves over her back: magenta inside the torso band (the idle's torso: 22-55 % down from the head top, the
        # middle 60 % of the idle's width at shoulder height), per run frame, positioned on each frame's own centre
        xs_sh = np.nonzero(idle[top + int(H * 0.25)])[0]
        tw = (xs_sh.max() - xs_sh.min()) if len(xs_sh) else H * 0.25
        n_on, n_any, area = 0, 0, []
        for c in cells["run" + s]:
            a = _alpha(c)
            yr = np.nonzero(a.any(axis=1))[0]
            t0 = int(yr.min())
            band = a[t0 + int(H * 0.22): t0 + int(H * 0.55)]
            cols_ = np.nonzero(band.any(axis=0))[0]
            cx = float(np.median(np.nonzero(band)[1])) if band.any() else c.width / 2
            gm = glove_mask(c)
            # the scarf sits above the band; the band starts under it
            gb = gm[t0 + int(H * 0.22): t0 + int(H * 0.55), max(0, int(cx - tw * 0.3)): int(cx + tw * 0.3)]
            on = int(gb.sum())
            area.append(on)
            n_on += on > 25
            n_any += int(gm[t0 + int(H * 0.2):].sum()) > 25
        out["gloves_on_back_frames"] = n_on
        out["gloves_visible_frames"] = n_any
        out["gloves_on_back_px_mean"] = round(float(np.mean(area)), 1)
        out["frames"] = len(cells["run" + s])
    return out


def puppet_hands_over_back(ctx, view):
    """Per pose of the puppet's run (24): whether a wrist her body does not hide lies over her torso in this view (inside
    the shoulders-hips quadrilateral of the OpenPose guide): the 3D truth of "a glove over her back"."""
    pg = ctx.state.get("guides", {}).get("pose_name") or "%s_puppet_run" % ctx.hero
    m = json.load(open(os.path.join(DRIVERS, pg, view, "poses.json"), encoding="utf-8"))

    def inside(pt, poly):
        x, y = pt
        n, ok = len(poly), False
        for i in range(n):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n]
            if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / ((y2 - y1) or 1e-9) + x1:
                ok = not ok
        return ok
    out = []
    for f in m["frames"][:24]:
        b = f["body"]
        quad = [b[2][:2], b[5][:2], b[11][:2], b[8][:2]]
        over = any(b[i][2] and inside(b[i][:2], quad) for i in (4, 7))
        out.append(bool(over))
    return out


def compare_sheet(ctx, looks, cells, view, out, every=2):
    from PIL import Image, ImageDraw
    s = SFX[view]
    c = 128
    n = len(cells[looks[0]]["run" + s][::every])
    W = 70 + c * (2 + n)
    sheet = Image.new("RGB", (W, 24 + c * len(looks)), (178, 160, 124))
    dr = ImageDraw.Draw(sheet)
    dr.text((6, 5), "%s %s: idle 0, idle 2, then every %s run frame (of %d)" % (ctx.hero, view, "2nd" if every == 2 else "", len(cells[looks[0]]["run" + s])), fill=(20, 20, 20))
    for r, code in enumerate(looks):
        y = 24 + r * c
        dr.text((6, y + c // 2 - 6), code, fill=(20, 20, 20))
        frames = [cells[code]["idle" + s][0], cells[code]["idle" + s][2]] + cells[code]["run" + s][::every]
        for i, f in enumerate(frames):
            t = f.resize((c, c), Image.LANCZOS)
            sheet.paste(t, (70 + i * c, y), t)
    sheet.save(out)
    return out


def compare_gif(cells, looks, view, out, fps=36):
    from PIL import Image
    s = SFX[view]
    c = 256
    run = [cells[code]["run" + s] for code in looks]
    n = min(len(r) for r in run)
    frames = []
    for k in range(n):
        fr = Image.new("RGBA", (c * len(looks), c), (178, 160, 124, 255))
        for i, r in enumerate(run):
            fr.paste(r[k], (i * c, 0), r[k])
        frames.append(fr.convert("RGB").convert("P", palette=Image.ADAPTIVE, colors=128))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0)


def heads_sheet(ctx, looks, cells, out):
    """The head and shoulders of every look's run (frame 6) against its idle, per view, at 2x: size at a glance."""
    from PIL import Image, ImageDraw
    import numpy as np
    c = 128
    sheet = Image.new("RGB", (60 + c * 2 * len(VIEWS5), 24 + c * len(looks)), (178, 160, 124))
    dr = ImageDraw.Draw(sheet)
    dr.text((6, 5), "heads at one pixel scale (crop of the top 128 px of the 256 cell, x1): per view idle | run frame 6", fill=(20, 20, 20))
    for r, code in enumerate(looks):
        dr.text((6, 24 + r * c + c // 2), code, fill=(20, 20, 20))
        for i, v in enumerate(VIEWS5):
            s = SFX[v]
            for j, f in enumerate((cells[code]["idle" + s][0], cells[code]["run" + s][6])):
                a = _alpha(f)
                ys = np.nonzero(a.any(axis=1))[0]
                t = max(0, int(ys.min()) - 8)
                crop = f.crop((64, t, 192, t + 128))
                sheet.paste(crop, (60 + (2 * i + j) * c, 24 + r * c), crop)
    sheet.save(out)


def rescale_cell(c, f):
    """A strip cell with its figure scaled by f about its feet (bottom centre of the figure's box)."""
    import numpy as np
    from PIL import Image
    a = np.asarray(c)[..., 3] > 0
    ys, xs = np.nonzero(a)
    if len(xs) == 0 or abs(f - 1.0) < 1e-3:
        return c
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    fig = c.crop(box)
    w, h = max(1, round(fig.width * f)), max(1, round(fig.height * f))
    fig = fig.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", c.size, (0, 0, 0, 0))
    cx = (box[0] + box[2]) / 2.0
    x0 = int(round(cx - w / 2.0))
    y0 = box[3] - h
    out.alpha_composite(fig, (max(0, min(c.width - w, x0)), max(0, y0)))
    return out


def silhouette(ctx):
    p = ctx.p("silhouette.json")
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}


def stage_compare(ctx, args):
    base_code = ctx.look
    code_p, code_q = look_codes(ctx)
    d = json.load(open(ctx.jpath, encoding="utf-8"))
    # pass 71: and every look made with the Puppet method (recipe.method hero_puppet), or the codes --compare-looks names
    extra = list(getattr(args, "compare_looks", None) or [])
    if not extra:
        extra = [c for c, e in (d.get("variants") or {}).items() if isinstance(e, dict) and ((e.get("recipe") or {}).get("method") == "hero_puppet")]
    looks = [base_code] + [c for c in [code_p, code_q] + extra if ((d.get("variants") or {}).get(c) or {}).get("sprite")]
    looks = [c for i, c in enumerate(looks) if c not in looks[:i]]
    if len(looks) < 2:
        log("no puppet look has a strip yet")
        return False
    out = ctx.p("compare")
    os.makedirs(out, exist_ok=True)
    cells = {c: look_cells(ctx, c) for c in looks}
    res = {}
    for v in VIEWS5:
        compare_sheet(ctx, looks, cells, v, os.path.join(out, "%s_run.png" % v))
        compare_gif(cells, looks, v, os.path.join(out, "%s_run.gif" % v))
        for c in looks:
            res.setdefault(c, {})[v] = measure_view(cells[c], v)
    heads_sheet(ctx, looks, cells, os.path.join(out, "heads.png"))
    truth = {v: sum(puppet_hands_over_back(ctx, v)) for v in ("back", "bd")}
    # the puppet's own size: the 3D figure says how tall her run stands against her idle in every view
    # (silhouette.json, the guides' cameras); each look's run scaled so its median height has that ratio (one factor a
    # view, no hand-tuned run_scale), and the heads measured again
    sil = silhouette(ctx)
    fits = {}
    for code in looks:
        if not sil:
            break
        alt = dict(cells[code])
        for v in VIEWS5:
            want = sil[v]["ratio_median"]
            f = want / max(1e-6, res[code][v]["height_median"])
            alt["run" + SFX[v]] = [rescale_cell(c, f) for c in cells[code]["run" + SFX[v]]]
            m = measure_view(alt, v)
            fits.setdefault(code, {})[v] = {"factor": round(f, 3), "puppet_ratio": want, "head_width": m["head_width"], "height_median": m["height_median"]}
        cells[code + "fit"] = alt
    if fits:
        fl = [c + "fit" for c in looks]
        for v in VIEWS5:
            compare_sheet(ctx, fl, cells, v, os.path.join(out, "%s_run_puppetfit.png" % v))
        heads_sheet(ctx, fl, cells, os.path.join(out, "heads_puppetfit.png"))
    # the idle is the same painting in every look (the stills are the base look's): one sheet shows it
    from PIL import Image
    idle = Image.new("RGB", (256 * 5, 256), (178, 160, 124))
    for i, v in enumerate(VIEWS5):
        f = cells[base_code]["idle" + SFX[v]][0]
        idle.paste(f, (i * 256, 0), f)
    idle.save(os.path.join(out, "idle_all_looks.png"))
    json.dump({"looks": looks, "measures": res, "puppet_fit": fits}, open(os.path.join(out, "measures.json"), "w", encoding="utf-8", newline="\n"), indent=1)
    lines = ["%-6s %-6s head %5s (range %s)  height med %5s max %5s%s" % (
        c, v, m["head_width"], m["head_width_range"], m["height_median"], m["height_max"],
        ("  gloves on back %d/%d frames (visible %d), %s px" % (m["gloves_on_back_frames"], m["frames"], m["gloves_visible_frames"], m["gloves_on_back_px_mean"])) if "frames" in m else "")
        for v in VIEWS5 for c in looks for m in [res[c][v]]]
    for v in ("back", "bd"):
        lines.append("puppet %-6s a visible wrist over her torso in %d of 24 poses (the 3D truth for 'a glove over her back')" % (v, truth[v]))
    for c, per in fits.items():
        for v, m in per.items():
            lines.append("%-6s %-6s scaled x%.3f to the puppet's own run/idle height (%.3f): head %5s, height med %5s" % (c, v, m["factor"], m["puppet_ratio"], m["head_width"], m["height_median"]))
    open(os.path.join(out, "measures.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    for ln in lines:
        log(ln)
    ctx.mark("compare", looks=looks, measures=res, puppet_fit=fits)
    return True


# ---------------------------------------------------------------- Blender

def blender(mode, timeout=3600, **kw):
    kw.setdefault("name", NAME[0])
    argv = [BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "puppet_blender.py"), "--", "mode=" + mode]
    argv += ["%s=%s" % (k, v) for k, v in kw.items() if v is not None]
    log("blender " + " ".join(argv[5:]))
    t0 = time.time()
    if DRY["on"]:
        dry_note("blender", script="puppet_blender.py", mode=mode, argv=argv[5:])
        _dry_outputs(mode, kw)
        return 0.0
    r = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    lines = [ln for ln in (r.stdout or "").splitlines() if ln.startswith("puppet_blender") or "Error" in ln or "Traceback" in ln]
    for ln in lines[-60:]:
        print("   ", ln, flush=True)
    if r.returncode != 0 or any(ln.startswith("puppet_blender: FAILED") for ln in lines):
        tail = "\n".join((r.stdout or "").splitlines()[-40:] + (r.stderr or "").splitlines()[-20:])
        raise RuntimeError("blender %s failed (%d):\n%s" % (mode, r.returncode, tail))
    return time.time() - t0


def _dry_outputs(mode, kw):
    """The files a Blender mode would write, as empty stand-ins (a dry run's later stages find them)."""
    for k in ("out", "save", "preview"):
        p = kw.get(k)
        if not p:
            continue
        if mode == "guides" and k == "out":
            for v in ("front", "fd", "side", "bd", "back"):
                os.makedirs(os.path.join(p, v), exist_ok=True)
            json.dump({"kind": "pose", "frame": kw.get("frame"), "face": kw.get("face"), "clip": kw.get("clip"), "dry_run": True}, open(os.path.join(p, "meta.json"), "w", encoding="utf-8"))
            continue
        os.makedirs(os.path.dirname(os.path.abspath(p)), exist_ok=True)
        if os.path.exists(p):
            os.remove(p)
        if mode == "silhouette":
            json.dump({v: {"ratio_median": 1.0, "dry_run": True} for v in ("front", "fd", "side", "bd", "back")}, open(p, "w", encoding="utf-8"))
        else:
            open(p, "wb").close()
    for k in ("overlay", "renders"):
        if kw.get(k):
            os.makedirs(kw[k], exist_ok=True)


# ---------------------------------------------------------------- lanes (the Level Editor's job runs the stages lane by lane)

def stage_lane(ctx, s, args):
    """The lane the work left in a stage needs: "comfy" (a painting or the Hunyuan3D shape), "local" (Blender, files), or
    None when the stage has nothing left to do. A stage that only waits for a pick runs on either lane."""
    if s == "apose":
        if not os.path.exists(ctx.p("apose_front.png")):
            if ref_of(args, "front") == "paint" and not _cands_exist(ctx, "front", args.seeds):
                return "comfy"
            return "local"
        need = [v for v in ("side", "back") if ref_of(args, v) not in ("none",) and not os.path.exists(ctx.p("apose_%s.png" % v))]
        if not need:
            return None
        paint = [v for v in need if ref_of(args, v) == "paint" and not _cands_exist(ctx, v, side_back_seeds(args))]
        return "comfy" if paint else "local"
    if s == "shape":
        redo = args.force_stage == "shape"
        if os.path.exists(ctx.p("shape.glb")) and not redo:
            return None
        if (not os.path.exists(ctx.p("shape_raw.glb")) or redo) and not all(os.path.exists(ctx.p("shape", "try_%d.glb" % k)) for k in range(args.tries)):
            return "comfy"
        return "local"
    if s == "rig":
        return None if os.path.exists(blend_path(ctx)) and args.force_stage != "rig" else "local"
    if s in ("anim", "guides", "compare"):
        return "local"
    return None


# ---------------------------------------------------------------- main

RUNNERS = {}


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="the Puppet method: a hero's painting -> a rigged 3D figure -> guides for the video model")
    ap.add_argument("hero")
    ap.add_argument("--stage", choices=STAGES, help="run this stage (again) only")
    ap.add_argument("--force", action="store_true", help="with --stage: redo it even when its outputs exist")
    ap.add_argument("--pick", nargs="*", default=[], help="front=N side=N back=N shape=N (or side=1,back=0)")
    ap.add_argument("--look", default="", help="the look whose stills are the source (default: the hero's played look)")
    ap.add_argument("--seeds", type=int, default=4, help="arms-out front candidates (the side and the back: half, at least 3)")
    ap.add_argument("--tries", type=int, default=2, help="Hunyuan3D tries (seeds)")
    ap.add_argument("--hy-steps", type=int, default=30)
    ap.add_argument("--octree", type=int, default=380)
    ap.add_argument("--faces", type=int, default=60000, help="the cleaned mesh's triangle budget")
    ap.add_argument("--front-only", action="store_true", help="Hunyuan3D on the front (and back) only")
    ap.add_argument("--from-blend", action="store_true", help="start from <hero>_puppet.blend (a rig fixed by hand): anim export, guides, looks, compare")
    ap.add_argument("--from-fbx", default="", help="a Mixamo-rigged FBX instead of our rig")
    ap.add_argument("--until", choices=STAGES, help="stop after this stage")
    ap.add_argument("--only-look", default="", help="looks: queue this code only (MAY-P or MAY-Q)")
    ap.add_argument("--look-wait", type=int, default=4 * 3600, help="looks: how long to wait for the look jobs (s)")
    ap.add_argument("--install-pickers", action="store_true", help="looks: install the base look's badge and cut-out through the editor's "
                    "install jobs (needs a Level Editor from pass 70 on); default: name them in the new looks' entries")
    # pass 71 (lane PLE): the Puppet method for any hero, from the Level Editor
    ap.add_argument("--ref", nargs="*", default=[], help="the 3D reference per view: front=paint|still:<key>|<picture> side=... back=...|none")
    ap.add_argument("--screen", default="", help="green | blue: the arms-out paintings' screen (default: the look's, else the hero's, else blue)")
    ap.add_argument("--painter", choices=["klein", "dev"], default="klein", help="the arms-out paintings' painter")
    ap.add_argument("--steps", type=int, default=0, help="the painter's passes (0 = its default: Klein 4, dev 8 with Turbo)")
    ap.add_argument("--no-turbo", action="store_true", help="dev: the full-quality steps (20+) without the Turbo LoRA")
    ap.add_argument("--seed", type=int, default=0, help="shift every arms-out and Hunyuan3D seed (a re-roll)")
    ap.add_argument("--first-seed", type=int, default=0, help="the arms-out candidates' first seed (0 = the tool's own); candidate k "
                    "paints on it + k x 1,000,003 (pass 72, the Level Editor's First seed)")
    ap.add_argument("--words-front", default="", help="the front edit's words in place of the template")
    ap.add_argument("--words-side", default="", help="the side edit's words in place of the template")
    ap.add_argument("--words-back", default="", help="the back edit's words in place of the template")
    ap.add_argument("--reroll", choices=["front", "views", "shape"], help="move that pick's candidates aside (painted again)")
    ap.add_argument("--reset-from", choices=["apose", "shape", "rig", "anim", "guides"], help="move that stage's outputs and the later ones aside")
    ap.add_argument("--clip", default="running.fbx", help="the moving clip (tools/dl/mixamo/<file>, or a path)")
    ap.add_argument("--idle", default="", help="an idle clip (tools/dl/mixamo/<file>); empty = the procedural breathing idle")
    ap.add_argument("--frame", choices=["soles", "ankles"], default="soles", help="the OpenPose guides framed by the soles (default) or the ankles")
    ap.add_argument("--face", choices=["nose", "head"], default="nose", help="the face angle of the stick figures: the ears from the measured "
                    "nose (default: a side view stays in profile) or on the head bone's axis (the trial's first guide)")
    ap.add_argument("--lane", choices=["", "comfy", "local"], default="", help="the Level Editor's lane: stop where the work needs the other one")
    ap.add_argument("--no-drive", action="store_true", help="no copy of the GLB to Google Drive")
    ap.add_argument("--compare-looks", nargs="*", default=[], help="compare: these looks beside the base, P and Q (default: every hero_puppet look)")
    ap.add_argument("--dry-run", action="store_true", help="record every prompt, graph and command; nothing reaches ComfyUI or Blender")
    ap.add_argument("--out-root", default="", help="the folder holding <hero>/ (default tools/dl/puppet; a dry run: where its stand-ins go)")
    return ap.parse_args(argv)


def _dry_mirror(real_dir, dry_dir):
    """A dry run's copy of the hero's puppet folder: files under 3 MB copied (stages.json, the paintings), bigger ones (the
    GLBs, the .blend) as empty files with the real modification time (a stage only asks whether they exist and how old
    they are); old/ is left out. Nothing is linked: a dry run's writes never reach the real files."""
    n = 0
    for base, dirs, files in os.walk(real_dir):
        dirs[:] = [x for x in dirs if x not in ("old",)]
        rel_dir = os.path.relpath(base, real_dir)
        for f in files:
            src = os.path.join(base, f)
            dst = os.path.join(dry_dir, rel_dir, f)
            if os.path.exists(dst):
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            st = os.stat(src)
            if st.st_size < 3 * 1024 * 1024:
                shutil.copy2(src, dst)
            else:
                open(dst, "wb").close()
                os.utime(dst, (st.st_atime, st.st_mtime))
            n += 1
    return n


def main(argv=None):
    global DRIVERS
    args = parse_args(argv)
    if args.dry_run:
        root = os.path.abspath(args.out_root or os.path.join(PUPPETS, "_dry"))
        os.makedirs(root, exist_ok=True)
        DRY.update(on=True, path=os.path.join(root, "dry_run.json"), notes=[], t0=time.time())
        DRIVERS = os.path.join(root, "drivers")    # the guides' stand-ins too: tools/dl/drivers is never written
        os.makedirs(DRIVERS, exist_ok=True)
        args.out_root = root
        args.no_drive = True
        dry_note("start", argv=list(argv if argv is not None else sys.argv[1:]))
        real = os.path.join(PUPPETS, args.hero)
        if os.path.isdir(real) and os.path.abspath(real) != os.path.abspath(os.path.join(root, args.hero)):
            dry_note("mirror", of=rel(real), files=_dry_mirror(real, os.path.join(root, args.hero)))
    NAME[0] = name_of(args.hero)
    ctx = Ctx(args.hero, args.look or None, args.out_root or None)
    args.force_stage = args.stage if args.force else None
    stamp = time.strftime("%Y%m%d-%H%M%S")
    if args.reset_from:
        do_reset(ctx, args.reset_from, stamp)
    if args.reroll:
        do_reroll(ctx, args.reroll, stamp)
    if args.pick:
        do_pick(ctx, args.pick)
    stages = [args.stage] if args.stage else STAGES
    if args.from_blend or args.from_fbx:
        stages = [s for s in stages if s in ("anim", "guides", "looks", "compare")]
    if args.until:
        stages = stages[:stages.index(args.until) + 1] if args.until in stages else stages
    log("hero %s (look %s, stills %s, screen %s, painter %s), stages %s%s" % (args.hero, ctx.look, ctx.slug or "(the hero's own)", screen_of(ctx, args),
                                                                           args.painter, ", ".join(stages), " [DRY RUN]" if DRY["on"] else ""))
    for s in stages:
        fn = RUNNERS.get(s) or globals().get("stage_" + s)
        if fn is None:
            log("stage %s is not built yet" % s)
            return 2
        need = stage_lane(ctx, s, args)
        if args.lane and need and need != args.lane and not DRY["on"]:
            # the Level Editor's job: this stage's work needs the other lane (a painting on comfy, Blender on local)
            print("puppet: NEXT lane %s (stage %s)" % (need, s), flush=True)
            return 0
        t0 = time.time()
        log("== stage %s" % s)
        print("puppet: STAGE %s start" % s, flush=True)
        for attempt in range(8):
            ok = fn(ctx, args)
            if DRY["on"] and isinstance(ok, str) and ok.startswith("pick:"):
                # a dry run picks the first candidate of every pick and goes on
                what = ok[5:]
                pairs = {"front": ["front=0"], "views": [v + "=0" for v in ("side", "back") if ref_of(args, v) == "paint"], "shape": ["shape=0"]}[what]
                dry_note("pick", what=what, pairs=pairs)
                do_pick(ctx, pairs)
                continue
            break
        if isinstance(ok, str) and ok.startswith("pick:"):
            ctx.mark(s, last_run=time.strftime("%Y-%m-%d %H:%M:%S"), last_seconds=round(time.time() - t0, 1), done=False, waiting=ok[5:])
            print("puppet: PICK %s" % ok[5:], flush=True)
            log("stage %s waits for your pick (%s); rerun with --pick when chosen" % (s, ok[5:]))
            return 0
        ctx.mark(s, last_run=time.strftime("%Y-%m-%d %H:%M:%S"), last_seconds=round(time.time() - t0, 1), done=bool(ok), waiting=None)
        if not ok:
            log("stage %s stopped (failed); rerun when ready" % s)
            return 1
        print("puppet: STAGE %s done %.0fs" % (s, time.time() - t0), flush=True)
    if args.until:
        print("puppet: DONE %s" % args.until, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

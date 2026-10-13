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
"""
import argparse
import io
import json
import os
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
DRIVE = r"E:/My Drive/88fits builds/puppets"
LE = os.environ.get("LEVEL_EDITOR", "")
HY_CKPT = "hunyuan3d-dit-v2-mv.safetensors"
STAGES = ["apose", "shape", "rig", "anim", "guides", "looks", "compare"]
# the game draws a hero's 256 px cell 1.9 m tall (Player._setup_sprite: sprite.setup(..., 1.9, ...))
CELL_M = 1.9


def log(*a):
    print("[puppet %s]" % time.strftime("%H:%M:%S"), *a, flush=True)


class Ctx:
    def __init__(self, hero, look=None):
        self.hero = hero
        self.out = os.path.join(REPO, "tools", "dl", "puppet", hero)
        os.makedirs(self.out, exist_ok=True)
        self.jpath = os.path.join(CONTENT, hero, hero + ".json")
        self.d = json.load(open(self.jpath, encoding="utf-8"))
        self.look = look or str(self.d.get("variant") or self.d.get("variant_base") or "")
        self.entry = (self.d.get("variants") or {}).get(self.look) or {}
        self.recipe = self.entry.get("recipe") or {}
        self.slug = str(self.recipe.get("stills") or "")
        self.state_p = os.path.join(self.out, "stages.json")
        self.state = json.load(open(self.state_p, encoding="utf-8")) if os.path.exists(self.state_p) else {}

    def still(self, view):
        """The look's painting of a view (tools/dl/ai_raw_anime/<id>_<slug>_<view>.png)."""
        return os.path.join(RAW, "%s%s_%s.png" % (self.hero, "_" + self.slug if self.slug else "", view))

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
# "arms held straight out, 45 degrees down from the shoulders" came back as a near T-pose (25 degrees below the
# horizontal, tools/dl/puppet/may/apose/wide/); this wording gives the 45-degree A-pose
APOSE_FRONT = ("Edit the reference image: the exact same woman with the same face, hair, beret, outfit, colours, proportions and art "
               "style, full body seen straight from the front, standing straight and facing the viewer in a relaxed A-pose for a 3D model "
               "turnaround sheet: both arms hang down and out to the sides at 45 degrees from her body, so her hands are at the height of "
               "her hips but a forearm's length out to the side of them, the elbows straight, the hands open with the palms facing her "
               "legs, clear blue background between each arm and her torso all the way from the armpit to the hand; her legs straight and "
               "a little apart with a gap between them, the feet fully visible. Nothing in her hands. ")
APOSE_SEED = 2026101377
# the A-pose's arms reach out sideways, toward and away from a side camera, so in profile the near arm hangs straight down
# over the side of the torso with the hand at hip height (not held forward)
APOSE_SIDE = ("The first reference image shows a woman standing in an A-pose, her arms held out to the sides. The second reference image "
              "shows how the same woman looks from the side. Draw the same woman seen from the side in a strict profile, facing to the "
              "right of the frame, standing straight: her arms reach out sideways toward and away from the viewer, so from the side the "
              "near arm hangs straight down over the side of her torso with the gloved hand at the height of her hips, nothing held "
              "forward, the far arm hidden behind the body, the legs straight. Keep the outfit, colours, proportions and art style of "
              "the references, the same height as the first image. ")
APOSE_BACK = ("The first reference image shows a woman standing in an A-pose, her arms held out to the sides. The second reference image "
              "shows how the same woman looks from behind. Draw the same woman in exactly the same A-pose seen directly from behind: "
              "the back of her head and beret, no face visible, both arms held straight out away from her body and angled 45 degrees "
              "down from the shoulders, a wide gap between each arm and her torso, the legs straight and a little apart. Keep the "
              "outfit (the overalls' back panel and the two suspender straps over her shoulders), the colours, the proportions and the "
              "art style of the references. ")


def _klein_cands(ctx, name, prompt, refs, seeds, base_seed):
    import comfy
    from PIL import Image
    d = ctx.p("apose")
    os.makedirs(d, exist_ok=True)
    names = []
    for k in range(seeds):
        f = os.path.join(d, "%s_c%d.png" % (name, k))
        if not os.path.exists(f):
            s = base_seed + k * 1000003
            imgs, secs = comfy.run(comfy.klein(prompt + BLUE + ".", s, 1024, 1024, refs=refs, prefix="88fits/puppet_%s_%s" % (ctx.hero, name)))
            Image.open(io.BytesIO(imgs[0])).convert("RGB").save(f)
            json.dump({"seed": s, "prompt": prompt + BLUE + ".", "refs": refs, "seconds": round(secs, 1)},
                      open(f[:-4] + ".json", "w", encoding="utf-8"), indent=1)
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
    top, bot = ys.min(), ys.max()
    H = bot - top
    band = range(int(top + H * 0.22), int(top + H * 0.48))
    free = 0
    for y in band:
        xs = np.nonzero(a[y])[0]
        runs = np.split(xs, np.nonzero(np.diff(xs) > 3)[0] + 1) if len(xs) else []
        if len([r for r in runs if len(r) > 2]) >= 3:
            free += 1
    width = (np.nonzero(a.any(axis=0))[0].ptp() + 1) / max(1, H)
    return round(free / max(1, len(band)), 3), round(float(width), 3)


def stage_apose(ctx, args):
    import comfy
    picks = ctx.state.get("apose", {}).get("picks", {})
    front_ref = comfy.upload_pil(_open_rgb(ctx.still("front")), "puppet_%s_front_ref.png" % ctx.hero)
    seed0 = APOSE_SEED
    if not os.path.exists(ctx.p("apose_front.png")):
        t0 = time.time()
        paths = _klein_cands(ctx, "front", APOSE_FRONT, [front_ref], args.seeds, seed0)
        scores = {os.path.basename(p): arms_clearance(p, ctx) for p in paths}
        ctx.mark("apose", front_cands=scores, front_seconds=round(time.time() - t0, 1))
        log("arms-out fronts painted: %s (arms clear, width/height): %s" % (ctx.p("apose", "front_sheet.png"), scores))
        log("pick one by eye: python tools/puppet.py %s --pick front=N" % ctx.hero)
        comfy.release_lock()
        return False
    if not (os.path.exists(ctx.p("apose_side.png")) and os.path.exists(ctx.p("apose_back.png"))):
        t0 = time.time()
        pick_ref = comfy.upload_pil(_open_rgb(ctx.p("apose_front.png")), "puppet_%s_apose_front.png" % ctx.hero)
        side_ref = comfy.upload_pil(_open_rgb(ctx.still("side")), "puppet_%s_side_ref.png" % ctx.hero)
        back_ref = comfy.upload_pil(_open_rgb(ctx.still("back")), "puppet_%s_back_ref.png" % ctx.hero)
        n = max(3, args.seeds // 2)
        if not os.path.exists(ctx.p("apose_side.png")):
            _klein_cands(ctx, "side", APOSE_SIDE, [pick_ref, side_ref], n, seed0 + 17)
        if not os.path.exists(ctx.p("apose_back.png")):
            _klein_cands(ctx, "back", APOSE_BACK, [pick_ref, back_ref], n, seed0 + 31)
        ctx.mark("apose", views_seconds=round(time.time() - t0, 1))
        log("side and back candidates: %s, %s; pick: --pick side=N back=N" % (ctx.p("apose", "side_sheet.png"), ctx.p("apose", "back_sheet.png")))
        comfy.release_lock()
        return False
    comfy.release_lock()
    return True


def _open_rgb(path):
    from PIL import Image
    return Image.open(path).convert("RGB")


def do_pick(ctx, pairs):
    for pair in pairs:
        view, k = pair.split("=", 1)
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
    import comfy
    d = ctx.p("shape")
    os.makedirs(d, exist_ok=True)
    redo = args.force_stage == "shape"
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
            names = {v: comfy.upload_pil(im, "puppet_%s_hy_%s.png" % (ctx.hero, v)) for v, im in views.items()}
            log("restarting ComfyUI before Hunyuan3D (the server's RAM)")
            comfy.wait_idle()
            log("  " + comfy.restart_server())
            t_all = time.time()
            for k in need:
                f = os.path.join(d, "try_%d.glb" % k)
                seed = 12345 + k * 7919
                try:
                    glbs, secs = run_3d(hunyuan_graph(names, seed, steps=args.hy_steps, octree=args.octree, prefix="88fits/puppet/%s_shape_%d" % (ctx.hero, k)))
                except Exception as e:
                    log("  Hunyuan3D try %d FAILED: %s" % (k, e))
                    tries.append({"try": k, "seed": seed, "error": str(e)[:2000]})
                    ctx.mark("shape", tries=tries)
                    if k == need[0]:
                        comfy.restart_server()
                        comfy.release_lock()
                        raise
                    break
                open(f, "wb").write(glbs[0])
                tries = [t for t in tries if t.get("try") != k] + [{"try": k, "seed": seed, "seconds": round(secs, 1), "bytes": len(glbs[0])}]
                log("  Hunyuan3D try %d seed %d %.0fs %d bytes" % (k, seed, secs, len(glbs[0])))
                ctx.mark("shape", tries=tries)
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
            return False
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
    j = json.load(open(ctx.p("rig", "joints.json"), encoding="utf-8"))
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


def stage_anim(ctx, args):
    glb = ctx.p("%s_puppet.glb" % ctx.hero)
    if os.path.exists(glb) and args.force_stage != "anim" and not (args.from_blend or args.from_fbx):
        return True
    t0 = time.time()
    rd = ctx.p("renders")
    src = args.from_fbx or blend_path(ctx)
    blender("anim", src=src, clip=os.path.join(REPO, "tools", "dl", "mixamo", "running.fbx"), paint=paint_inputs(ctx), out=glb, renders=rd,
            save=blend_path(ctx))
    prev = preview_sheet(ctx, rd, ctx.p("%s_puppet_preview.png" % ctx.hero))
    ctx.mark("anim", seconds=round(time.time() - t0, 1), glb=glb, preview=prev, source=src)
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

def stage_guides(ctx, args):
    pose_dir = os.path.join(DRIVERS, "%s_puppet_run" % ctx.hero)
    depth_dir = os.path.join(DRIVERS, "%s_puppet_run_depth" % ctx.hero)
    redo = args.force_stage == "guides" or args.from_blend or bool(args.from_fbx)
    t0 = time.time()
    if redo or not os.path.exists(os.path.join(pose_dir, "front", "driver_24.png")):
        blender("guides", src=blend_path(ctx), out=pose_dir, frames=24, pitch=25)
        r = subprocess.run([sys.executable, os.path.join(HERE, "pose_driver.py"), "draw", pose_dir], capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("pose_driver draw failed: %s" % (r.stderr or r.stdout)[-1500:])
        log("OpenPose guides drawn: %s/all_sheet.png" % pose_dir)
    t1 = time.time()
    if redo or not os.path.exists(os.path.join(depth_dir, "back", "ctl_48.png")):
        argv = [BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "blender_depth_drivers.py"), "--",
                "src=" + ctx.p("%s_puppet.glb" % ctx.hero), "out=" + depth_dir, "action=run", "mode=cycle", "frames=24", "cycles=2",
                "depth=tight", "forward=-Y", "inplace=0", "pitch=25"]
        log("blender_depth_drivers " + " ".join(argv[5:]))
        r = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=3600)
        for ln in (r.stdout or "").splitlines():
            if ln.startswith("blender_depth_drivers") or "Error" in ln:
                print("   ", ln, flush=True)
        if r.returncode != 0 or not os.path.exists(os.path.join(depth_dir, "back", "ctl_48.png")):
            raise RuntimeError("depth drivers failed: %s" % " | ".join(((r.stdout or "") + (r.stderr or "")).splitlines()[-30:]))
        depth_sheet(depth_dir)
    if redo or not os.path.exists(ctx.p("silhouette.json")):
        blender("silhouette", src=blend_path(ctx), out=ctx.p("silhouette.json"), frames=24, pitch=25)
    ctx.mark("guides", pose_dir=pose_dir, depth_dir=depth_dir, pose_seconds=round(t1 - t0, 1), depth_seconds=round(time.time() - t1, 1),
             occlusion=json.load(open(os.path.join(pose_dir, "meta.json"), encoding="utf-8")).get("occlusion"))
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
    p["pose_drivers"] = {v: "%s_puppet_run" % ctx.hero for v in VIEWS5}
    q = dict(p)
    # the depth video carries no face: the front walks on the OpenPose guide (Fun Control painted a crosshatched face,
    # then long hair, from the front), the other views on the depth guide; words for the face and the hair (the first
    # bd painted her bob as skin)
    q["ctl_drivers"] = {v: "%s_puppet_run_depth" % ctx.hero for v in ("fd", "side", "bd", "back")}
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
    m = json.load(open(os.path.join(DRIVERS, "%s_puppet_run" % ctx.hero, view, "poses.json"), encoding="utf-8"))

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
    looks = [base_code] + [c for c in (code_p, code_q) if ((d.get("variants") or {}).get(c) or {}).get("sprite")]
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
    argv = [BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "puppet_blender.py"), "--", "mode=" + mode]
    argv += ["%s=%s" % (k, v) for k, v in kw.items() if v is not None]
    log("blender " + " ".join(argv[5:]))
    t0 = time.time()
    r = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    lines = [ln for ln in (r.stdout or "").splitlines() if ln.startswith("puppet_blender") or "Error" in ln or "Traceback" in ln]
    for ln in lines[-60:]:
        print("   ", ln, flush=True)
    if r.returncode != 0 or any(ln.startswith("puppet_blender: FAILED") for ln in lines):
        tail = "\n".join((r.stdout or "").splitlines()[-40:] + (r.stderr or "").splitlines()[-20:])
        raise RuntimeError("blender %s failed (%d):\n%s" % (mode, r.returncode, tail))
    return time.time() - t0


# ---------------------------------------------------------------- main

RUNNERS = {}


def main():
    ap = argparse.ArgumentParser(description="the Puppet trial: a hero's painting -> a rigged 3D figure -> guides for the video model")
    ap.add_argument("hero")
    ap.add_argument("--stage", choices=STAGES, help="run this stage (again) only")
    ap.add_argument("--force", action="store_true", help="with --stage: redo it even when its outputs exist")
    ap.add_argument("--pick", nargs="*", default=[], help="front=N side=N back=N shape=N")
    ap.add_argument("--look", default="", help="the look whose stills are the source (default: the hero's played look)")
    ap.add_argument("--seeds", type=int, default=4, help="arms-out front candidates")
    ap.add_argument("--tries", type=int, default=2, help="Hunyuan3D tries (seeds)")
    ap.add_argument("--hy-steps", type=int, default=30)
    ap.add_argument("--octree", type=int, default=380)
    ap.add_argument("--faces", type=int, default=60000, help="the cleaned mesh's triangle budget")
    ap.add_argument("--front-only", action="store_true", help="Hunyuan3D on the front (and back) only")
    ap.add_argument("--from-blend", action="store_true", help="start from may_puppet.blend (Garry's rig fix): anim export, guides, looks, compare")
    ap.add_argument("--from-fbx", default="", help="a Mixamo-rigged FBX instead of our rig")
    ap.add_argument("--until", choices=STAGES, help="stop after this stage")
    ap.add_argument("--only-look", default="", help="looks: queue this code only (MAY-P or MAY-Q)")
    ap.add_argument("--look-wait", type=int, default=4 * 3600, help="looks: how long to wait for the look jobs (s)")
    ap.add_argument("--install-pickers", action="store_true", help="looks: install the base look's badge and cut-out through the editor's "
                    "install jobs (needs a Level Editor from pass 70 on); default: name them in the new looks' entries")
    args = ap.parse_args()
    ctx = Ctx(args.hero, args.look or None)
    args.force_stage = args.stage if args.force else None
    if args.pick:
        do_pick(ctx, args.pick)
    stages = [args.stage] if args.stage else STAGES
    if args.from_blend or args.from_fbx:
        stages = [s for s in stages if s in ("anim", "guides", "looks", "compare")]
    for s in stages:
        fn = RUNNERS.get(s) or globals().get("stage_" + s)
        if fn is None:
            log("stage %s is not built yet" % s)
            return 2
        t0 = time.time()
        log("== stage %s" % s)
        ok = fn(ctx, args)
        ctx.mark(s, last_run=time.strftime("%Y-%m-%d %H:%M:%S"), last_seconds=round(time.time() - t0, 1), done=bool(ok))
        if not ok:
            log("stage %s stopped (waiting for a pick or failed); rerun when ready" % s)
            return 1
        if args.until == s:
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())

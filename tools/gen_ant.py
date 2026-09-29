"""The fire ant's art variants (pass 34): a 3D ant walked in Blender drives Wan 2.2 Fun Control, so a creature with no
Mixamo skeleton still walks on a real gait, in eight directions.

For each variant (fire_ant.json variants[code].recipe: prompt, body proportions, fps):
  1. tools/blender_ant.py renders the ant's tripod walk in the five game views (front, fd, side, bd, back) as depth
     videos, and frame 0 as coloured clay (tools/dl/drivers/ant_<code>/)
  2. Flux.2 Klein repaints the side clay as the variant's ant (style anchor + clay as references, the blockout only for
     the pose), then every other view from its clay with the side painting as the reference, so the five are one ant
  3. Wan 2.2 Fun Control animates each view's painting along that view's depth video (animate.cycle_control)
  4. the front painting is edited dead on its back and Wan 2.2 first-last-frame animates the fall (gen_art.death_cycle)
  5. everything is fitted to one scale and packed as an eight-direction strip, fire_ant_sprite_<letter>.png, its
     counts written into variants[code]

    python tools/gen_ant.py --variant=ANT-A                       (paints side candidates k0..k3 and stops, to be looked at)
    python tools/gen_ant.py --variant=ANT-A --use-side=k2 [--stage=paint]   (takes k2; paint stops after the five paintings)
"""
import json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ARGS = sys.argv[1:]
sys.argv = ["gen_art.py", "--no-import"] + (["--skip-qa"] if "--skip-qa" in ARGS else [])
sys.path.insert(0, HERE)
import gen_art as g  # noqa: E402
import animate  # noqa: E402
import artkit  # noqa: E402
import comfy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

VIEWS = ["front", "fd", "side", "bd", "back"]
CID = "fire_ant"
FOLDER = os.path.join(REPO, "game", "content", "enemies", CID)
BLENDER = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "blender-5.2.0-windows-x64", "blender.exe")
SP = os.environ.get("ANT_REVIEW", os.path.join(REPO, "tools", "dl", "review"))


def opt(name, default=""):
    for a in ARGS:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


def log(*a):
    print(*a, flush=True)


def drivers(code, recipe):
    out = os.path.join(REPO, "tools", "dl", "drivers", "ant_" + code.lower().replace("-", ""))
    if os.path.exists(os.path.join(out, "back", "ctl_24.png")):
        return out
    body = recipe.get("body", {})
    cmd = [BLENDER, "-b", "--python", os.path.join(HERE, "blender_ant.py"), "--", "out=" + out, "frames=12", "cycles=2"]
    cmd += ["%s=%s" % (k, v) for k, v in body.items()]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log("  drivers", out)
    return out


DETAIL = ("real insect anatomy drawn as a stylised creature: hard chitin plates with crisp specular highlights, a big head with large glossy "
          "compound eyes and strong serrated mandibles, elbowed antennae made of small segments, legs that taper to thin segments with small "
          "spikes and hooked claws at the tips, a banded shiny gaster")
WORDS = {
    "front": "walking straight towards the viewer, seen from the front and a little above: its head, big eyes and mandibles are at the bottom of "
             "the picture, nearest the viewer, and its thorax and round gaster stretch away up the picture behind the head, foreshortened",
    "fd": "walking towards the lower right corner of the picture, seen three-quarters from the front and a little above: the head at the lower "
          "right, nearest the viewer, the gaster at the upper left, farther away",
    "bd": "walking away towards the upper right corner of the picture, seen three-quarters from behind and a little above: the round gaster at "
          "the lower left, nearest the viewer, the head at the upper right, farther away",
    "back": "walking straight away from the viewer, seen from behind and a little above: its round gaster is at the bottom of the picture, "
            "nearest the viewer, and its thorax and head stretch away up the picture, with the antennae at the top",
}


def paint(code, recipe, drv, seed, bg):
    """The five views; returns {view: RGB}, or None while the side view waits to be picked. The side view comes first,
    painted from its clay with the style anchor (candidates k0..k3; --use-side=kN takes one): a front view painted from
    the blockout came out top-down with the head at the far end. Every other view is then painted from the side
    painting and its own clay, the way it faces spelled out."""
    key = "fire_ant_" + code.lower().replace("-", "")
    refs = g.ensure_anchor_uploaded()
    subject = recipe["prompt"]
    side_key = key + "_side"
    chosen = opt("use-side")
    if chosen:
        for ext in (".png", ".json"):
            shutil.copy(os.path.join(g.RAW, "%s_%s%s" % (side_key, chosen, ext)), os.path.join(g.RAW, side_key + ext))
    if not os.path.exists(os.path.join(g.RAW, side_key + ".png")):
        clay = comfy.upload_pil(Image.open(os.path.join(drv, "side", "clay.png")).convert("RGB"), key + "_clay_side.png")
        keys = []
        for k in range(4):
            ck = "%s_k%d" % (side_key, k)
            g.FORCE_KEYS.append(ck)
            p = ("The first reference image shows the art style only; do not copy its subjects. The second reference image is a rough 3D blockout "
                 "of an ant made of plain spheres and sticks: use it only for the pose, the camera angle and where the six legs are. Redraw it as "
                 "a finished, detailed anime game creature illustration of " + subject + ", with " + DETAIL + ", in side profile facing right. It "
                 "must not look like spheres and sticks. " + g.STYLE + ". " + bg + ".")
            g.render(ck, p, refs + [clay], {"subject": "an ant", "view": None, "subjects_max": 1}, seed + 1000 * k, tries=1)
            keys.append(ck)
        sheet(keys, key + "_side_cands.png")
        log("  side candidates painted: look at %s, then rerun with --use-side=kN" % os.path.join(SP, key + "_side_cands.png"))
        return None
    side = Image.open(os.path.join(g.RAW, side_key + ".png")).convert("RGB")
    out = {"side": side}
    # what every view must carry that the blockout does not show (ANT-C's flame at the tip of its gaster)
    keep = (" It keeps " + recipe["keep"] + ", seen from this angle.") if recipe.get("keep") else ""
    side_ref = comfy.upload_pil(side, side_key + ".png")
    for k, view in enumerate(["front", "fd", "bd", "back"]):
        clay = comfy.upload_pil(Image.open(os.path.join(drv, view, "clay.png")).convert("RGB"), "%s_clay_%s.png" % (key, view))
        p = ("The first reference image is a finished painting of an ant character in side view. The second reference image is a rough 3D "
             "blockout of the same ant made of plain spheres and sticks, " + WORDS[view] + ". Redraw the blockout as the same ant character as the "
             "first image, the same colours, plates, eyes, mandibles, spiky legs and art style, in exactly the pose and camera angle of the "
             "blockout, with exactly six legs and two antennae." + keep + " It must not look like spheres and sticks. " + g.STYLE + ". " + bg + ".")
        img, _ = g.render("%s_%s" % (key, view), p, [side_ref, clay], {"subject": "an ant", "view": None, "subjects_max": 1}, seed + 11 + k, tries=2)
        out[view] = img
    sheet([key + "_" + v for v in VIEWS], key + "_views.png")
    return out


def no_green(img):
    """The ants have no green in them (reds, oranges, yellows, black, white), so any green in a frame is the screen's
    spill on the thin far legs: the green channel is held to the red one, which leaves every yellow and orange as it is."""
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 0
    r, gch = a[..., 0].astype(np.int16), a[..., 1].astype(np.int16)
    a[..., 1] = np.where(m & (gch > r), r, gch).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


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


def main():
    code = opt("variant")
    d = json.load(open(os.path.join(FOLDER, CID + ".json"), encoding="utf-8"))
    entry = (d.get("variants") or {}).get(code)
    if not isinstance(entry, dict) or "recipe" not in entry:
        raise SystemExit("gen_ant: no recipe for %s in fire_ant.json" % code)
    recipe = entry["recipe"]
    bg = g.BG_GREEN
    seed = g.seed_for(CID + code)
    drv = drivers(code, recipe)
    views = paint(code, recipe, drv, seed, bg)
    if views is None or opt("stage") == "paint":
        return
    key = "fire_ant_" + code.lower().replace("-", "")
    cell = int(d.get("frame_px", 128))
    CO, CF = (14, 8, 12, 255), 0.024
    motion = ("A 2D anime game creature sprite, " + recipe["prompt"].split(",")[0] + ", scuttling in place on its six legs exactly as the control "
              "video shows, the same creature, colours and markings as the reference in every frame, crisp clean line art, cel shading. The "
              "camera is completely locked off and static. The background stays a flat solid bright green color with nothing in it, no ground, no shadow.")
    # "directions": 2 walks only the front and back, like every other creature (pass 35: ANT-A); 5 views give the 8-way strip
    two = int(recipe.get("directions", 8)) == 2
    walks = {}
    for view in (["front", "back"] if two else VIEWS):
        frames, _ = animate.cycle_control(views[view], key + "_ctl_" + view, os.path.join(drv, view), seed + 20 + VIEWS.index(view), prompt=motion,
                                          negative_extra=str(d.get("anim_negative", "")))
        walks[view] = frames
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
    # the death: the front painting edited dead, and the fall between them
    front = views["front"]
    front_ref = comfy.upload_pil(front, key + "_front.png")
    dead_prompt = ("This exact ant lying dead on its back on the ground, its six legs curled up in the air, antennae limp, seen from the front "
                   "and a little above so the whole body is visible. Keep the same colors, proportions and art style. " + bg + ".")
    dead, _ = g.render(key + "_dead", dead_prompt, [front_ref], {"subject": "an ant lying on its back", "view": None, "subjects_max": 1}, seed + 9)
    fall = g.death_cycle(front, dead, key + "_fall", seed + 9, cell, base, 8, CF, CO, recipe["prompt"].split(",")[0][:120], "")
    if fall:
        frames["die"] = fall
    else:
        dead_cell = g.finish(dead, cell, 0.7, True, None, CF, None, CO)[0]
        frames["die"] = [artkit.transform(base, lean_deg=-14, sy=0.97), artkit.fall(base, 38), artkit.fall(base, 66), dead_cell, dead_cell]
    for k in list(frames.keys()):
        frames[k] = [no_green(f) for f in frames[k]]
    strip, counts, cols = artkit.pack_strip(frames, artkit.ENEMY_ORDER, cell)
    fname = CID + "_sprite_" + code.split("-")[-1].lower() + ".png"
    strip.save(os.path.join(FOLDER, fname))
    icon, _ = g.finish(front, 256, 0.9, False, None, 0.009)
    icon.save(os.path.join(FOLDER, CID + "_icon_" + code.split("-")[-1].lower() + ".png"))
    head = round(max(g.figure_top(f) for f in frames.get("idle", []) + frames.get("run", [])), 3)
    cur = json.load(open(os.path.join(FOLDER, CID + ".json"), encoding="utf-8"))
    ent = cur.setdefault("variants", {}).setdefault(code, {})
    ent.update({"sprite": fname, "icon": CID + "_icon_" + code.split("-")[-1].lower() + ".png", "anims": counts, "strip_cols": cols, "head": head,
                "fps": {"run": int(recipe.get("fps", 20)), "die": 12 if fall else 8}})
    json.dump(cur, open(os.path.join(FOLDER, CID + ".json"), "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    log("gen_ant: %s packed, %d frames, %s" % (code, sum(counts.values()), fname))


if __name__ == "__main__":
    main()

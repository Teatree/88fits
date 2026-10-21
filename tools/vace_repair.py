"""Frame repair with VACE (pass 95, lane VACE): a few frames of a look's animation painted anew, the rest kept.

Garry's third approach: regenerate a short stretch of a clip pinned at both ends, keeping the good frames and
following the driver. Wan 2.2 Fun VACE (tools/comfy.wan_fun_vace) gets the whole animation as a clip: every frame the
Level Editor's frames store holds for it (tools/frames_store.py: the effective version of each slot, its clip frame
when the cache had it, else the strip cell put back on the clip's canvas), the frames to redo masked out and replaced
by their guide (the driver's depth or pose frame the clip was walked on, fitted onto the kept frames' figure; mid grey
when the look has no driver), and the view's painting as the reference. The repainted frames come back keyed like the
pipeline keys a clip and land in the store as new versions of their slots (source "vace", labelled <CODE>-<n>). This
process never writes staged.json (pass 95 resume, AN-08: one writer): each version says `stage_wanted` and the Level
Editor's landing (jobs._post -> frames_io.stage_versions) stages it unless the slot is pinned or a hand choice was
staged meanwhile; a hand run stages with `python tools/frames_store.py stage ...` or in the Frames view. Nothing in
the game changes until Export. An animation with neither a clip cache nor a driver (a procedural idle, an attack, a
hit) is refused unless `free_fill` is sent on purpose: VACE would have nothing to follow (AN-01's rule per method).

    python tools/vace_repair.py --kind enemy --id desert_spider --code SP-B --anim run --view side --slots 3,4,5,9
        [--prompt "..."] [--seed N] [--window auto|single|double] [--size 640] [--no-stage] [--dry-run] [--out DIR]
    python tools/vace_repair.py --job tools/dl/jobs/<id>/repair.json      (the Level Editor's job: the same keys)

The window: a loop of up to 12 frames goes in twice plus the first frame again (25 frames: the model sees the whole
cycle twice, the redone frames are taken from the second pass; a frame to redo is masked in both passes so the model
never copies the bad one); a longer loop once plus its first frame (a 24-frame hero run: 25); a one-shot (a death,
an attack) as it is, the last frame repeated up to the next 4k+1. A single frame has no stretch to repair: use a
repaint. Output: the new versions, a before / guide / after sheet (repair_<stamp>.png) and result.json for the job card.
"""
import argparse
import io
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402
import artkit  # noqa: E402
import frames_store as fs  # noqa: E402

DEFAULT_NEG = ("camera movement, camera pan, zoom, dolly, the character walks across the frame, background scenery, ground, floor, "
               "shadow, blurry, low quality, deformed, extra limbs, missing limbs, text, watermark, static image, frozen, "
               "a second creature, duplicate body, morphing, melting")


def log(*a):
    print(*a, flush=True)


def parse_slots(text, n):
    out = []
    for part in re.split(r"[\s,;]+", str(text or "")):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    out = sorted(set(k for k in out if 0 <= k < n))
    return out


def window_plan(n, loop, mode="auto"):
    """[(slot, redo_allowed, take)] per window frame: which slot each frame shows, whether a redo of that slot is
    masked here, and whether the output of this frame is the slot's new picture."""
    if mode == "auto":
        mode = "double" if (loop and n <= 12) else "single"
    frames = []
    if loop and mode == "double":
        frames = [(k, True, False) for k in range(n)] + [(k, True, True) for k in range(n)] + [(0, False, False)]
    elif loop:
        frames = [(k, True, True) for k in range(n)] + [(0, False, False)]
    else:
        frames = [(k, True, True) for k in range(n)]
    while (len(frames) - 1) % 4:
        frames.append((frames[-1][0], False, False))   # the last frame held: a one-shot's rest pose
    return frames, mode


def inverse_fit(cell, fit, S):
    """A strip cell put back on the clip's canvas (the inverse of Group.to_cell's placement, outline and all)."""
    s = float(fit["s"])
    big = cell.resize((max(1, int(round(cell.width / s))), max(1, int(round(cell.height / s)))), Image.LANCZOS)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    x, y = int(round(-fit["ox"] / s)), int(round(-fit["oy"] / s))
    piece = big
    px, py = x, y
    if x < 0 or y < 0:
        piece = big.crop((max(0, -x), max(0, -y), big.width, big.height))
        px, py = max(0, x), max(0, y)
    if px < S and py < S:
        piece = piece.crop((0, 0, min(piece.width, S - px), min(piece.height, S - py)))
        canvas.alpha_composite(piece, (px, py))
    return canvas


def on_screen(rgba, screen):
    bg = Image.new("RGBA", rgba.size, tuple(screen) + (255,))
    bg.alpha_composite(rgba)
    return bg.convert("RGB")


def screen_colour(group, ref_img):
    if ref_img is not None:
        arr = np.asarray(ref_img.convert("RGB"))
        edge = np.concatenate([arr[:8, :, :].reshape(-1, 3), arr[:, :8, :].reshape(-1, 3)])
        c = np.median(edge, axis=0)
        return tuple(int(v) for v in c)
    return (0, 0, 255) if group.meta.get("screen") == "blue" else (0, 255, 0)


def align_driver(group, kept, drv, S):
    """The affine (s, ox, oy) that puts the driver's frames onto the kept frames' figure: medians of the figure boxes
    of the kept frames against their driver frames (the painting walked at its own size, not the depth's: gen_ctl's
    model_scale and fit_ref make the two differ)."""
    ss, oxs, oys = [], [], []
    for slot, canvas in kept:
        rb = fs.bbox(canvas)
        p = os.path.join(REPO, drv["dir"], drv["pattern"] % drv["index"][slot])
        if not rb or not os.path.isfile(p):
            continue
        d = Image.open(p).convert("L")
        m = np.asarray(d) > 12
        ys, xs = np.nonzero(m)
        if len(xs) < 8:
            continue
        db = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
        dh, dw = db[3] - db[1], db[2] - db[0]
        rh, rw = rb[3] - rb[1], rb[2] - rb[0]
        if dh <= 0 or dw <= 0:
            continue
        s = (rh / dh + rw / dw) / 2.0
        ss.append(s)
        oxs.append((rb[0] + rb[2]) / 2.0 - (db[0] + db[2]) / 2.0 * s)
        oys.append(rb[3] - db[3] * s)   # the feet on the same floor
    if not ss:
        return {"s": 1.0, "ox": 0.0, "oy": 0.0, "pairs": 0}
    return {"s": float(np.median(ss)), "ox": float(np.median(oxs)), "oy": float(np.median(oys)), "pairs": len(ss)}


def warp_driver(img, aff, S):
    """A driver frame (on black) scaled and moved by the affine onto an S x S black canvas."""
    s = float(aff["s"])
    rgb = img.convert("RGB")
    big = rgb.resize((max(1, int(round(rgb.width * s))), max(1, int(round(rgb.height * s)))), Image.BILINEAR)
    canvas = Image.new("RGB", (S, S), (0, 0, 0))
    x, y = int(round(aff["ox"])), int(round(aff["oy"]))
    piece = big
    if x < 0 or y < 0:
        piece = big.crop((max(0, -x), max(0, -y), big.width, big.height))
        x, y = max(0, x), max(0, y)
    if x < S and y < S:
        canvas.paste(piece.crop((0, 0, min(piece.width, S - x), min(piece.height, S - y))), (x, y))
    return canvas


def key_settings(look):
    """gen_art's keying knobs from the look's recipe / JSON, so the new frames key like the clip's did."""
    d = look.d
    artkit.KEY_SAT = float(d.get("key_sat", 0.35))
    artkit.KEY_MIN_V = float(d.get("key_min_value", 0.2))
    artkit.KEY_CUT_SHADOW = bool(d.get("key_cut_shadow", True))
    artkit.KEY_CLAMP_SCREEN = bool(d.get("key_clamp_screen", False))


def sheet(rows, labels, redo, cell=180, out_path=None):
    """Rows of frames (RGBA or RGB) side by side, the redone columns marked."""
    n = max(len(r) for r in rows)
    W, H = cell, cell + 18
    img = Image.new("RGB", (n * W, len(rows) * H + 18), (40, 40, 48))
    dr = ImageDraw.Draw(img)
    for k in range(n):
        dr.text((k * W + 6, 3), "slot %d%s" % (k, "  REDONE" if k in redo else ""), fill=(255, 120, 120) if k in redo else (200, 200, 210))
    for r, (row, lab) in enumerate(zip(rows, labels)):
        y0 = 18 + r * H
        dr.text((4, y0 + 2), lab, fill=(255, 230, 140))
        for k, f in enumerate(row):
            if f is None:
                continue
            t = f.convert("RGBA").copy()
            t.thumbnail((cell - 6, cell - 6))
            bg = Image.new("RGBA", (cell, cell), (100, 100, 110, 255) if k not in redo else (120, 90, 90, 255))
            bg.alpha_composite(t, ((cell - t.width) // 2, (cell - t.height) // 2))
            img.paste(bg.convert("RGB"), (k * W, y0 + 18))
    if out_path:
        img.save(out_path)
    return img


def repair(kind, cid, code, base, view, slots, prompt=None, seed=None, window="auto", size=None, stage=True, dry=False, out_dir=None,
           job=None, negative=None, steps=None, cfg=None, lora=None, shift=None, strength=1.0, guide="driver", free_fill=False):
    t_all = time.time()
    look = fs.Look(kind, cid, code)
    g = fs.Group(look, base, view)
    if not g.exists():
        fs.register_look(kind, cid, code)
        g = fs.Group(look, base, view)
    if not g.exists():
        raise SystemExit("vace_repair: %s %s has no %s %s group (no strip?)" % (cid, code, base, view))
    if not g.meta.get("clip") and not g.meta.get("driver") and not free_fill:
        raise SystemExit("vace_repair: %s %s %s/%s is procedural (no clip cache, no driver): VACE has nothing to follow; "
                         "repaint the still and re-run the look, or send free_fill on purpose for a free fill from the neighbours" % (cid, code, base, view))
    if not out_dir:
        fs.prune_repairs()   # the sheets older than RETENTION["repair_days"] under tools/dl/frames/_repairs
    n = g.n
    redo = parse_slots(slots, n) if isinstance(slots, str) else sorted(set(int(k) for k in slots if 0 <= int(k) < n))
    if not redo:
        raise SystemExit("vace_repair: no slots to redo in 0..%d" % (n - 1))
    if n < 2:
        raise SystemExit("vace_repair: %s %s has one frame: there is no stretch to repair, repaint it instead" % (base, view))
    loop = fs.loops(base)
    plan, mode = window_plan(n, loop, window)
    S = int(size or g.canvas_size() or fs.CANVAS)
    S = max(256, S // 16 * 16)
    out_dir = out_dir or os.path.join(REPO, "tools", "dl", "frames", "_repairs")
    os.makedirs(out_dir, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    key_settings(look)
    # the reference painting and the screen
    ref_img = None
    if g.meta.get("ref_still") and os.path.isfile(os.path.join(REPO, g.meta["ref_still"])):
        ref_img = Image.open(os.path.join(REPO, g.meta["ref_still"])).convert("RGB")
    screen = screen_colour(g, ref_img)
    fit = g.fit()
    # every slot on the canvas (RGBA), the effective version
    canvases = {}
    eff = {}
    for k in range(n):
        v, how = g.effective(k)
        eff[k] = v
        if v is None:
            raise SystemExit("vace_repair: slot %d has no version" % k)
        raw = g.raw_of(k, v)
        if raw is not None:
            if raw.size != (S, S):
                raw = raw.resize((S, S), Image.LANCZOS)
            canvases[k] = raw
        else:
            canvases[k] = inverse_fit(g.cell_of(k, v), fit, S)
    kept_slots = [k for k in range(n) if k not in redo]
    if not kept_slots:
        raise SystemExit("vace_repair: every frame is to be redone: that is a new clip, not a repair (re-roll the look instead)")
    if ref_img is None:
        # no painting in the cache: the kept frame with the most figure stands in as the identity
        best = max(kept_slots, key=lambda k: float((np.asarray(canvases[k])[..., 3] > 127).sum()))
        ref_img = on_screen(canvases[best], screen)
        ref_src = "slot %d" % best
    else:
        ref_src = g.meta["ref_still"]
    ref_img = ref_img.resize((S, S), Image.LANCZOS)
    # the guides: the driver's frames fitted onto the kept figure, or mid grey
    drv = g.meta.get("driver")
    aff = None
    guides = {}
    guided = bool(drv) and str(guide or "driver") != "free"   # "free": no guide, the frames filled from their neighbours
    if guided:
        aff = align_driver(g, [(k, canvases[k]) for k in kept_slots], drv, S)
        for k in redo:
            p = os.path.join(REPO, drv["dir"], drv["pattern"] % drv["index"][k])
            if os.path.isfile(p):
                guides[k] = warp_driver(Image.open(p), aff, S)
    grey = Image.new("RGB", (S, S), (128, 128, 128))
    white = Image.new("RGB", (S, S), (255, 255, 255))
    black = Image.new("RGB", (S, S), (0, 0, 0))
    frames, masks, takes = [], [], {}
    for j, (slot, redo_ok, take) in enumerate(plan):
        if slot in redo and redo_ok:
            frames.append(guides.get(slot, grey))
            masks.append(white)
            if take:
                takes[slot] = j
        else:
            frames.append(on_screen(canvases[slot], screen))
            masks.append(black)
    for slot in redo:
        if slot not in takes:
            # a redo slot whose taking frame is the padding (never for a loop; a one-shot's last slot is taken from its own frame)
            takes[slot] = next(j for j, (s2, _, _) in enumerate(plan) if s2 == slot)
    words = prompt or (g.meta.get("clip") or {}).get("prompt") or ""
    if not words:
        noun = look.d.get("noun") or look.d.get("anim_hint") or str(look.d.get("art_prompt", "")).split(",")[0][:120] or "the same creature"
        words = ("A 2D anime game creature sprite, %s, %s in place exactly as the control video shows, the same creature, colours and markings as the "
                 "reference in every frame, crisp clean line art, cel shading. The camera is completely locked off and static. The background stays a flat "
                 "solid bright %s color with nothing in it, no ground, no shadow." % (noun, "walking" if base == "run" else "moving", "blue" if screen[2] > screen[1] else "green"))
    wan = (g.meta.get("clip") or {}).get("wan") or {}
    settings = {"steps": int(steps or wan.get("steps") or 4), "cfg": float(cfg if cfg is not None else wan.get("cfg", 1.0)),
                "lora": bool(wan.get("lora", True) if lora is None else lora), "shift": float(shift or wan.get("shift") or 5.0), "size": S, "strength": float(strength)}
    seed = int(seed if seed is not None else ((g.meta.get("clip") or {}).get("seed") or 0) + 31 + sum(redo))
    neg = negative or DEFAULT_NEG
    drv_rec = {"name": drv["name"], "ctl_sig": (g.meta.get("clip") or {}).get("ctl_sig")} if drv else None
    info = {"kind": kind, "id": cid, "code": code, "base": base, "view": view, "key": g.key, "slots": redo, "window": mode, "frames": len(plan),
            "seed": seed, "prompt": words, "negative": neg, "reference": ref_src, "driver": (drv or {}).get("name"), "driver_rec": drv_rec, "driver_fit": aff, "screen": list(screen),
            "canvas": S, "wan": settings, "job": job, "stamp": stamp, "guide": "driver" if guided else "free", "free_fill": bool(free_fill),
            "plan": [{"slot": s, "redo": (s in redo and r), "take": t} for s, r, t in plan]}
    # the sheet of what goes in (before, the guides), kept even on a dry run
    before = [g.cell_of(k, eff[k]) for k in range(n)]
    guide_row = [guides.get(k, grey if k in redo else None) if k in redo else None for k in range(n)]
    if dry:
        sheet([before, guide_row], ["before (the effective frames)", "guide (the driver fitted on; grey = free)"], set(redo), out_path=os.path.join(out_dir, "repair_%s_dry.png" % stamp))
        with open(os.path.join(out_dir, "dry_run_%s.json" % stamp), "w", encoding="utf-8", newline="\n") as f:
            json.dump(info, f, indent=1, ensure_ascii=False)
        log("vace_repair: dry run: %d window frames, %d to redo (%s), seed %d; nothing sent" % (len(plan), len(redo), mode, seed))
        return dict(info, dry_run=True, versions=[], sheet=os.path.join(out_dir, "repair_%s_dry.png" % stamp))
    import comfy
    log("vace_repair: %s %s %s/%s: redo %s in a %s window of %d frames, seed %d, %s" % (cid, code, base, view, redo, mode, len(plan), seed,
                                                                                    ("driver " + drv["name"]) if guided else "no guide (a free fill from the neighbours)"))
    vram0 = None
    try:
        vram0 = comfy.get("/system_stats", timeout=10)["devices"][0].get("vram_free")
    except Exception:
        pass
    tag = "%s_%s_%s_%s_%s" % (cid, fs.code_part(code), base, view, stamp[-6:])
    ref_name = comfy.upload_pil(ref_img, tag + "_ref.png")
    ctl_names = [comfy.upload_pil(f, "%s_f%02d.png" % (tag, j)) for j, f in enumerate(frames)]
    mask_names = [comfy.upload_pil(m, "%s_m%02d.png" % (tag, j)) for j, m in enumerate(masks)]
    graph = comfy.wan_fun_vace(words, ref_name, ctl_names, mask_names, seed, S, S, negative=neg, prefix="88fits/vace_" + tag, shift=settings["shift"],
                               steps=settings["steps"], cfg=settings["cfg"], lora=settings["lora"], strength=settings["strength"])
    t0 = time.time()
    pngs, secs = comfy.run(graph, timeout=3600)
    raw = [Image.open(io.BytesIO(b)).convert("RGB") for b in pngs]
    log("vace_repair: %d frames back in %.0f s" % (len(raw), secs))
    if len(raw) < len(plan):
        raise SystemExit("vace_repair: ComfyUI returned %d frames for a window of %d" % (len(raw), len(plan)))
    vram1 = None
    try:
        vram1 = comfy.get("/system_stats", timeout=10)["devices"][0].get("vram_free")
    except Exception:
        pass
    # the redone frames keyed like a clip (the wider despill of a video frame), as new versions; NOT staged here (one
    # writer of staged.json: the Level Editor's landing stages what `stage_wanted` says, a hand run stages by hand)
    versions = []
    after = list(before)
    sel = g.selected()
    for slot in redo:
        j = takes[slot]
        keyed = artkit.key_background(raw[j], 0.16, 0.7)
        empty = float((np.asarray(keyed)[..., 3] > 127).mean())
        v = g.add_version(slot, keyed, "raw", "vace", by="ai", seed=seed, prompt=words, model="wan2.2_fun_vace_14B", workflow="wan_fun_vace",
                          job=job, window={"mode": mode, "frames": len(plan), "taken": j}, control=("driver:" + drv["name"]) if guided else "free",
                          reference=ref_src, kept=[k for k in range(n) if k not in redo], wan=settings, canvas=[S, S], driver=drv_rec, free_fill=bool(free_fill) or None)
        pinned = bool((sel.get(str(slot)) or {}).get("pinned"))
        wanted = bool(stage and not pinned and empty >= fs.FLAG_RULES["empty"])
        after[slot] = g.cell_of(slot, v)
        versions.append({"slot": slot, "id": v["id"], "label": v["label"], "staged": False, "stage_wanted": wanted, "pinned": pinned,
                         "empty": empty < fs.FLAG_RULES["empty"], "n": v["n"], "shrunk": g.last_shrink})
        log("  slot %2d -> %s%s%s%s" % (slot, v["label"], " (to stage at the landing)" if wanted else (" (pinned: not to be staged)" if pinned else ""),
                                       " EMPTY" if empty < fs.FLAG_RULES["empty"] else "", (" shrunk to %d%% to fit the cell" % int(round(g.last_shrink * 100))) if g.last_shrink else ""))
    if not job:
        log("vace_repair: nothing is staged by this process; stage a version with: python tools/frames_store.py stage %s %s %s %s %s <slot> <version id>, or in the Frames view" % (kind, cid, code, base, view))
    sheet_path = os.path.join(out_dir, "repair_%s.png" % stamp)
    sheet([before, guide_row, after], ["before (the effective frames)", "guide (the driver fitted on; grey = free)", "after (the new versions, to stage)"], set(redo), out_path=sheet_path)
    # the whole window as it came back, for the eye
    full = Image.new("RGB", (len(raw) * 160, 160), (40, 40, 48))
    for j, f in enumerate(raw):
        full.paste(f.resize((160, 160), Image.LANCZOS), (j * 160, 0))
    full.save(os.path.join(out_dir, "window_%s.jpg" % stamp), quality=85)
    info.update(seconds=round(secs, 1), total_seconds=round(time.time() - t_all, 1), vram_free_before=vram0, vram_free_after=vram1, versions=versions,
                sheet=sheet_path, window_picture=os.path.join(out_dir, "window_%s.jpg" % stamp), flags=g.flags())
    with open(os.path.join(out_dir, "repair_%s.json" % stamp), "w", encoding="utf-8", newline="\n") as f:
        json.dump(info, f, indent=1, ensure_ascii=False)
    side = os.environ.get("ASSET_JOB_SIDECAR", "")
    if side:
        rel = lambda p: os.path.relpath(p, REPO).replace("\\", "/")  # noqa: E731
        rec = {"id": cid, "folder": look.folder, "variant": code, "entry": {}, "top": {},
               "info": {"pipeline": "vace_repair", "repair": {k: v for k, v in info.items() if k not in ("plan",)},
                        "outputs": [{"label": "before / guide / after", "type": "sheet", "file": rel(sheet_path)},
                                    {"label": "the window as it came back", "type": "sheet", "file": rel(info["window_picture"])}]}}
        os.makedirs(os.path.dirname(side) or ".", exist_ok=True)
        with open(side, "w", encoding="utf-8", newline="\n") as f:
            json.dump(rec, f, indent=1, ensure_ascii=False)
    log("vace_repair: done in %.0f s (the render %.0f s): %s" % (time.time() - t_all, secs, sheet_path))
    return info


def main(argv=None):
    ap = argparse.ArgumentParser(description="repair frames of a look's animation with Wan 2.2 Fun VACE")
    ap.add_argument("--job", help="a Level Editor job's repair.json (its keys are the flags below)")
    ap.add_argument("--kind")
    ap.add_argument("--id")
    ap.add_argument("--code")
    ap.add_argument("--anim", help="the animation (run, idle, die, attack, ...)")
    ap.add_argument("--view", help="front, fd, side, bd, back")
    ap.add_argument("--slots", help="the frames to redo: 3,4,5 or 3-5,9")
    ap.add_argument("--prompt", default=None)
    ap.add_argument("--negative", default=None)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--window", default="auto", choices=("auto", "single", "double"))
    ap.add_argument("--size", type=int, default=None)
    ap.add_argument("--steps", type=int, default=None)
    ap.add_argument("--cfg", type=float, default=None)
    ap.add_argument("--shift", type=float, default=None)
    ap.add_argument("--strength", type=float, default=1.0)
    ap.add_argument("--guide", default="driver", choices=("driver", "free"), help="driver: the redone frames follow the driver's frames; free: filled from their neighbours")
    ap.add_argument("--free-fill", action="store_true", help="paint a procedural animation (no clip, no driver) anyway, as a free fill from the neighbours")
    ap.add_argument("--no-stage", action="store_true", help="mark the versions as not to be staged at the landing (this process never stages: one writer)")
    ap.add_argument("--dry-run", action="store_true", help="build the inputs and the sheet; send nothing")
    ap.add_argument("--out", default=None, help="where the sheet and result go (default tools/dl/frames/_repairs)")
    a = ap.parse_args(argv)
    kw = {}
    if a.job:
        with open(a.job, "r", encoding="utf-8") as f:
            j = json.load(f)
        kw = dict(kind=j.get("kind"), cid=j.get("id"), code=j.get("code"), base=j.get("anim"), view=j.get("view"), slots=j.get("slots"),
                  prompt=j.get("prompt") or None, seed=j.get("seed"), window=j.get("window") or "auto", size=j.get("size"), stage=not j.get("no_stage"),
                  dry=bool(j.get("dry_run")), out_dir=j.get("out") or os.path.dirname(os.path.abspath(a.job)), job=j.get("job") or os.environ.get("ASSET_JOB_ID"),
                  negative=j.get("negative") or None, steps=j.get("steps"), cfg=j.get("cfg"), shift=j.get("shift"), strength=float(j.get("strength") or 1.0),
                  guide=str(j.get("guide") or "driver"), free_fill=bool(j.get("free_fill")))
    else:
        if not (a.kind and a.id and a.code and a.anim and a.view and a.slots):
            ap.error("--kind, --id, --code, --anim, --view and --slots are needed (or --job)")
        kw = dict(kind=a.kind, cid=a.id, code=a.code, base=a.anim, view=a.view, slots=a.slots, prompt=a.prompt, seed=a.seed, window=a.window, size=a.size,
                  stage=not a.no_stage, dry=a.dry_run, out_dir=a.out, job=os.environ.get("ASSET_JOB_ID"), negative=a.negative, steps=a.steps, cfg=a.cfg,
                  shift=a.shift, strength=a.strength, guide=a.guide, free_fill=a.free_fill)
    if kw.get("seed") is not None:
        kw["seed"] = int(kw["seed"])
    repair(**kw)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

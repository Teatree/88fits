"""The VACE repair benchmark (pass 96, lane GATES, gate G1): which repair profile is the most reliable per method class,
measured, not eyed. Every run is one vace_repair.repair() of existing cached frames (nothing is re-walked, no new
painting) on a COPY of the frames store (tools/dl/p96/GATES/bench/store: Garry's tools/dl/frames is never written), judged
by deterministic checks on the staged composition, scored = checks passed / checks, costed in render seconds, VRAM and
upload volume. The winner per class (the best mean score over its seeds, ties to the cheaper) is written into the class's
`repair` rule in tools/level_editor/methods.json as `profile` + `escalation` (vace_repair.profile_for reads it); a class
whose best score is under PASS_MIN keeps `vace: conditional` and its escalation starts at `reroll_view`.

    python tools/vace_bench.py plan                       the matrix (27 runs) and what each costs so far
    python tools/vace_bench.py run [--only ctl,pose,free,cell,mask] [--limit N] [--dry-run]
                                                          every run not done yet, each in its own process (the comfy lock is
                                                          released between runs so the Level Editor's queue can interleave)
    python tools/vace_bench.py one <run id>               one run (what `run` spawns)
    python tools/vace_bench.py score                      the table (bench/summary.md + summary.json) and the chosen profiles
    python tools/vace_bench.py write-profiles [--dry-run] methods.json: `profile` + `escalation` on every method's repair rule
    python tools/vace_bench.py checks <kind> <id> <code> <anim> <view> <slots>   the checks on the real store's staged state (no GPU)

The classes and their looks (the clip caches and drivers exist for all of them; the brief's picks):
  ctl   Desert Spider SP-B run/side (the demo's slots 3, 4, 5, 9 and seeds 24110, 7): window single 13 / double 25 x
        strength 1.0 / 0.7 x the 4-step lightx2v LoRAs (cfg 1) / 20 steps without (cfg 3.5)
  pose  Goblin GOB-D run/front (a Wan Animate walk on the OpenPose driver bigguy_goblin, `_pose_f`): single / double
  free  Buckshot Dwarf BD-A run/front (creature_free2, `_walk_f`, no driver: a free fill): single / double
  cell  Red Goblin RG-A run/front (a recipe-less base: cells only, no clip, no still): single / double, free fill
  mask  SP-B run/side slot 5 with a rectangle over its front legs (the partial-frame proof for UI-08's regions)

The checks per redone slot (E4): no `empty`, `jump`, `footprint` flag, no `silhouette` flag where a driver exists (the flags of
frames_store.Group.flags on the composition with the new versions staged), the seam flag unchanged when slot 0 or n-1 is
redone, the figure's alpha area within 0.72-1.35 of the group's median, and the colour distance to the view's still (a
6x6x6 RGB histogram of the figure, half the L1) no more than COLOUR_TOL x the kept frames' median distance. The hue-only
histogram E4 names was tried first and did not separate the demo's good repairs (3, 4) from its bad ones (5, 9): see
balancing_GATES.md. Lone (no redone neighbour) and span slots are scored apart.
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import artkit  # noqa: E402
import frames_store as fs  # noqa: E402
import vace_repair as VR  # noqa: E402

OUT = os.path.join(REPO, "tools", "dl", "p96", "GATES", "bench")
STORE = os.path.join(OUT, "store")
PASS_MIN = 0.6           # a class whose best mean score is under this keeps vace: conditional and escalates to reroll_view at once
COLOUR_TOL = 1.25        # a redone frame's colour distance to the still may be this times the kept frames' median
AREA_RANGE = (0.72, 1.35)
TIE = 0.02               # two profiles within this score are a tie: the cheaper wins
PY = sys.executable

LOOKS = {
    "ctl": {"kind": "enemy", "cid": "desert_spider", "code": "SP-B", "base": "run", "view": "side", "slots": [3, 4, 5, 9]},
    "pose": {"kind": "enemy", "cid": "goblin", "code": "GOB-D", "base": "run", "view": "front", "slots": [3, 4, 5, 9]},
    "free": {"kind": "enemy", "cid": "buckshot_dwarf", "code": "BD-A", "base": "run", "view": "front", "slots": [3, 4, 5, 9]},
    "cell": {"kind": "enemy", "cid": "red_goblin", "code": "RG-A", "base": "run", "view": "front", "slots": [3, 4, 5, 9], "free_fill": True, "guide": "free"},
}
SEEDS = [24110, 7]
SAMPLERS = {"lora4": {"steps": 4, "cfg": 1.0, "lora": True}, "steps20": {"steps": 20, "cfg": 3.5, "lora": False}}
# the 21 methods by class (vace_repair.METHOD_CLASSES; the rest are cell)
CLASS_OF_METHOD = dict(VR.METHOD_CLASSES)


def log(*a):
    print(*a, flush=True)


def _load(p, default=None):
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _save(p, obj):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
    os.replace(tmp, p)


# ---------------------------------------------------------------- the matrix

def plan():
    """[{id, cls, window, strength, sampler, seed, ...}] in the order they run: the cheap ctl runs, the other classes, the mask,
    the 20-step runs last (five times the sampling)."""
    runs = []

    def add(cls, window, strength, sampler, seed, **extra):
        rid = "%s_%s_s%s_%s_seed%d" % (cls, window, ("%.1f" % strength).replace(".", ""), sampler, seed)
        if extra.get("mask"):
            rid = "mask_%s_%s_seed%d" % (window, sampler, seed)
        runs.append(dict(id=rid, cls=cls, window=window, strength=strength, sampler=sampler, seed=seed, **extra))

    for window in ("single", "double"):
        for strength in (1.0, 0.7):
            for seed in SEEDS:
                add("ctl", window, strength, "lora4", seed)
    for cls in ("pose", "free"):
        for window in ("single", "double"):
            for seed in SEEDS:
                add(cls, window, 1.0, "lora4", seed)
    for window in ("single", "double"):
        add("cell", window, 1.0, "lora4", SEEDS[0])
    add("ctl", "double", 1.0, "lora4", SEEDS[0], mask=True, slots=[5])
    for window in ("single", "double"):
        for strength in (1.0, 0.7):
            for seed in SEEDS:
                add("ctl", window, strength, "steps20", seed)
    return runs


def run_dir(rid):
    return os.path.join(OUT, "runs", rid)


def result_of(rid):
    return _load(os.path.join(run_dir(rid), "result.json"))


# ---------------------------------------------------------------- the store copy and the checks

def group_of(cls, store=None):
    L = LOOKS[cls]
    store = store or STORE
    look = fs.Look(L["kind"], L["cid"], L["code"])
    g = fs.Group(look, L["base"], L["view"], store)
    if not g.exists():
        res = fs.register_look(L["kind"], L["cid"], L["code"], store=store)
        if not res.get("ok"):
            raise SystemExit("vace_bench: cannot register %s %s: %s" % (L["cid"], L["code"], res.get("error")))
        g = fs.Group(look, L["base"], L["view"], store)
    return look, g


def colour_hist(img, bins=6):
    """A 6x6x6 RGB histogram of the figure's pixels (alpha over 127), normalised; zeros for an empty picture."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    m = a[..., 3] > 0.5
    rgb = a[..., :3][m]
    if len(rgb) == 0:
        return np.zeros((bins, bins, bins), dtype=np.float64)
    h, _ = np.histogramdd(rgb, bins=(bins, bins, bins), range=((0, 1),) * 3)
    return h / max(h.sum(), 1e-9)


def colour_dist(h1, h2):
    return float(0.5 * np.abs(h1 - h2).sum())


def alpha_area(img):
    return int((np.asarray(img.convert("RGBA"))[..., 3] > 127).sum())


def still_figure(g):
    """The view's painting keyed (as the clip's reference), or None when the cache has none."""
    p = g.meta.get("ref_still")
    if not p or not os.path.isfile(os.path.join(fs.REPO, p)):
        return None
    VR.key_settings(g.look)
    return artkit.key_background(Image.open(os.path.join(fs.REPO, p)).convert("RGB"), 0.16, 0.7)


def frame_picture(g, slot, v):
    """The picture the colour check reads: the raw canvas when the version has one, else the cell."""
    raw = g.raw_of(slot, v)
    return raw if raw is not None else g.cell_of(slot, v)


def baseline(g, cls):
    """The group before any run: the flags, every slot's colour distance to the still (or to the fullest frame when there is
    no still) and alpha area. Cached under the bench folder."""
    p = os.path.join(OUT, "baseline_%s.json" % cls)
    b = _load(p)
    if b and b.get("n") == g.n:
        return b
    ref = still_figure(g)
    pics = {}
    for k in range(g.n):
        v, _ = g.effective(k)
        pics[k] = frame_picture(g, k, v)
    ref_src = g.meta.get("ref_still") or ""
    if ref is None:
        best = max(pics, key=lambda k: alpha_area(pics[k]))
        ref, ref_src = pics[best], "slot %d" % best
    H = colour_hist(ref)
    cells = g.effective_cells()
    b = {"n": g.n, "cls": cls, "ref": ref_src, "flags": g.flags(),
         "colour": {str(k): round(colour_dist(colour_hist(pics[k]), H), 4) for k in range(g.n)},
         "area": {str(k): alpha_area(cells[k]) for k in range(g.n)}}
    _save(p, b)
    return b


def classify_slots(redo, n, loop=True):
    """{slot: "lone" | "span"}: lone = no redone neighbour."""
    out = {}
    s = set(redo)
    for k in redo:
        p, q = (k - 1) % n if loop else k - 1, (k + 1) % n if loop else k + 1
        out[k] = "span" if (p in s or q in s) else "lone"
    return out


def checks(g, info, base, stage=True):
    """The checks on the composition with the run's versions staged (then unstaged again). Returns the per-slot results,
    the score and the lone / span split."""
    n = g.n
    redo = [int(s) for s in info["slots"]]
    versions = {int(v["slot"]): v["id"] for v in info.get("versions") or []}
    if stage:
        for slot, vid in versions.items():
            g.stage(slot, vid, why="bench")
    try:
        flags = g.flags()
        cells = g.effective_cells()
        areas = [alpha_area(c) for c in cells]
        med_area = float(np.median(areas)) if areas else 0.0
        ref = still_figure(g)
        if ref is None:
            kept = [k for k in range(n) if k not in redo]
            best = max(kept, key=lambda k: areas[k])
            v, _ = g.effective(best)
            ref = frame_picture(g, best, v)
        H = colour_hist(ref)
        kept_d = [float(base["colour"][str(k)]) for k in range(n) if k not in redo]
        kept_med = float(np.median(kept_d)) if kept_d else 0.0
        drv = g.meta.get("driver")
        # a flag that fires on most installed frames of the look is noise, not a check (the pose class: a stick figure's IoU
        # against a body is always small); such a flag is left out of this group's checks and said so
        noisy = [name for name in ("silhouette", "footprint", "jump") if sum(1 for k in range(n) if name in (base["flags"].get(str(k)) or {})) > n // 2]
        kinds = classify_slots(redo, n, fs.loops(g.base))
        per = {}
        for slot in redo:
            v, _ = g.effective(slot)
            f = flags.get(str(slot)) or {}
            d = colour_dist(colour_hist(frame_picture(g, slot, v)), H)
            ratio = areas[slot] / med_area if med_area > 0 else 0.0
            c = {"empty": "empty" not in f, "jump": "jump" not in f, "footprint": "footprint" not in f,
                 "area": AREA_RANGE[0] <= ratio <= AREA_RANGE[1],
                 "colour": d <= COLOUR_TOL * kept_med if kept_med > 0 else d <= 0.5}
            if drv:
                c["silhouette"] = "silhouette" not in f
            for name in noisy:
                c.pop(name, None)
            if slot in (0, n - 1) and fs.loops(g.base):
                before = "seam" in (base["flags"].get(str(n - 1)) or {})
                after = "seam" in (flags.get(str(n - 1)) or {})
                c["seam"] = (after == before) or (before and not after)
            per[str(slot)] = {"kind": kinds[slot], "checks": c, "passed": sum(1 for x in c.values() if x), "of": len(c),
                              "flags": {k2: {x: y for x, y in v2.items() if x != "rule"} for k2, v2 in f.items()},
                              "colour": round(d, 4), "colour_kept_median": round(kept_med, 4), "area_ratio": round(ratio, 3),
                              "version": versions.get(slot), "staged": bool(versions.get(slot))}
    finally:
        if stage:
            for slot in versions:
                g.unstage(slot)
    passed = sum(x["passed"] for x in per.values())
    of = sum(x["of"] for x in per.values())

    def part(kind):
        xs = [x for x in per.values() if x["kind"] == kind]
        p, o = sum(x["passed"] for x in xs), sum(x["of"] for x in xs)
        return {"passed": p, "of": o, "score": round(p / o, 3) if o else None}

    clean = sum(1 for x in per.values() if x["passed"] == x["of"])
    return {"per_slot": per, "passed": passed, "of": of, "score": round(passed / of, 3) if of else None,
            "clean": clean, "slots": len(per), "clean_rate": round(clean / len(per), 3) if per else None, "skipped": noisy,
            "lone": part("lone"), "span": part("span"), "flags_before": {str(s): list((base["flags"].get(str(s)) or {}).keys()) for s in redo}}


# ---------------------------------------------------------------- one run

def one(rid, dry=False):
    runs = {r["id"]: r for r in plan()}
    if rid not in runs:
        raise SystemExit("vace_bench: no run %s" % rid)
    r = runs[rid]
    L = LOOKS[r["cls"]]
    look, g = group_of(r["cls"])
    base = baseline(g, r["cls"])
    d = run_dir(rid)
    os.makedirs(d, exist_ok=True)
    slots = r.get("slots") or L["slots"]
    sp = SAMPLERS[r["sampler"]]
    kw = dict(kind=L["kind"], cid=L["cid"], code=L["code"], base=L["base"], view=L["view"], slots=slots, seed=r["seed"], window=r["window"],
              strength=r["strength"], steps=sp["steps"], cfg=sp["cfg"], lora=sp["lora"], stage=False, dry=dry, out_dir=d, store=STORE,
              guide=L.get("guide", "driver"), free_fill=bool(L.get("free_fill")))
    if r.get("mask"):
        # a rectangle over the front legs of the slot: the lower-left 45% x 55% of its figure box, in canvas fractions
        v, _ = g.effective(slots[0])
        pic = frame_picture(g, slots[0], v)
        S = pic.width
        bb = fs.bbox(pic) or (0, 0, S, S)
        w, h = bb[2] - bb[0], bb[3] - bb[1]
        rect = [bb[0] / S, (bb[1] + 0.45 * h) / S, (bb[0] + 0.45 * w) / S, bb[3] / S]
        kw["mask"] = {slots[0]: rect}
    log("vace_bench: %s: %s %s %s/%s slots %s window %s strength %s %s seed %d%s" % (rid, L["cid"], L["code"], L["base"], L["view"], slots, r["window"], r["strength"],
                                                                                   r["sampler"], r["seed"], " MASK %s" % kw.get("mask") if r.get("mask") else ""))
    rec = {"id": rid, "run": r, "look": L, "slots": slots, "started": time.strftime("%Y-%m-%dT%H:%M:%S")}
    t0 = time.time()
    try:
        info = VR.repair(**kw)
    except BaseException as e:   # SystemExit from the tool too
        rec.update(error="%s: %s" % (type(e).__name__, e), seconds=round(time.time() - t0, 1))
        _save(os.path.join(d, "result.json"), rec)
        log("vace_bench: %s FAILED: %s" % (rid, rec["error"]))
        return rec
    rec["info"] = {k: v for k, v in info.items() if k not in ("plan", "flags")}
    if dry or info.get("dry_run"):
        rec.update(dry_run=True)
        _save(os.path.join(d, "result.json"), rec)
        return rec
    rec["checks"] = checks(g, info, base)
    rec["cost"] = {"render_s": info.get("seconds"), "total_s": info.get("total_seconds"), "upload_s": info.get("upload_seconds"),
                   "upload_mb": round((info.get("upload_bytes") or 0) / 1e6, 2), "frames": info.get("frames"), "frames_back": info.get("frames_back"),
                   "vram_free_before_gb": round((info.get("vram_free_before") or 0) / 1e9, 2) if info.get("vram_free_before") else None,
                   "vram_free_after_gb": round((info.get("vram_free_after") or 0) / 1e9, 2) if info.get("vram_free_after") else None}
    rec["score"] = rec["checks"]["score"]
    rec["ended"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    _save(os.path.join(d, "result.json"), rec)
    log("vace_bench: %s: score %s (%d/%d; lone %s, span %s), render %.0f s, total %.0f s, upload %.1f MB" % (
        rid, rec["score"], rec["checks"]["passed"], rec["checks"]["of"], rec["checks"]["lone"]["score"], rec["checks"]["span"]["score"],
        info.get("seconds") or 0, info.get("total_seconds") or 0, rec["cost"]["upload_mb"]))
    return rec


def run_all(only=None, limit=None, dry=False):
    todo = [r for r in plan() if (not only or r["cls"] in only or (r.get("mask") and "mask" in only))]
    done = 0
    for r in todo:
        res = result_of(r["id"])
        if res and (res.get("score") is not None or (dry and res.get("dry_run"))):
            continue
        if limit is not None and done >= limit:
            break
        done += 1
        log("vace_bench: run %d: %s" % (done, r["id"]))
        d = run_dir(r["id"])
        os.makedirs(d, exist_ok=True)
        cmd = [PY, os.path.abspath(__file__), "one", r["id"]] + (["--dry-run"] if dry else [])
        with open(os.path.join(d, "log.txt"), "a", encoding="utf-8") as logf:
            rc = subprocess.call(cmd, cwd=REPO, stdout=logf, stderr=subprocess.STDOUT)
        res = result_of(r["id"]) or {}
        log("vace_bench: %s -> rc %s, score %s, error %s" % (r["id"], rc, res.get("score"), (res.get("error") or "")[:160]))
    log("vace_bench: %d run(s) this time; %d of %d done" % (done, sum(1 for r in todo if (result_of(r["id"]) or {}).get("score") is not None), len(todo)))


# ---------------------------------------------------------------- the table and the profiles

def profile_key(r):
    return "%s/%s/strength %.1f/%s" % (r["cls"], r["window"], r["strength"], r["sampler"])


def score_all():
    rows = {}
    for r in plan():
        res = result_of(r["id"])
        key = ("mask" if r.get("mask") else r["cls"], r["window"], r["strength"], r["sampler"])
        row = rows.setdefault(key, {"cls": key[0], "window": r["window"], "strength": r["strength"], "sampler": r["sampler"], "runs": [], "scores": [],
                                    "lone": [], "span": [], "clean": [], "render_s": [], "total_s": [], "upload_mb": [], "vram_gb": [], "errors": 0, "planned": 0})
        row["planned"] += 1
        if not res:
            continue
        if res.get("error") or res.get("score") is None:
            row["errors"] += 1
            row["runs"].append({"id": r["id"], "seed": r["seed"], "error": (res.get("error") or "no score")[:200]})
            continue
        c, cost = res["checks"], res.get("cost") or {}
        row["runs"].append({"id": r["id"], "seed": r["seed"], "score": res["score"], "lone": c["lone"]["score"], "span": c["span"]["score"],
                            "render_s": cost.get("render_s"), "sheet": (res.get("info") or {}).get("sheet")})
        row["scores"].append(res["score"])
        if c.get("clean_rate") is not None:
            row["clean"].append(c["clean_rate"])
        if c["lone"]["score"] is not None:
            row["lone"].append(c["lone"]["score"])
        if c["span"]["score"] is not None:
            row["span"].append(c["span"]["score"])
        for k in ("render_s", "total_s", "upload_mb"):
            if cost.get(k) is not None:
                row[k].append(cost[k])
        if cost.get("vram_free_before_gb") is not None and cost.get("vram_free_after_gb") is not None:
            row["vram_gb"].append(round(cost["vram_free_before_gb"] - cost["vram_free_after_gb"], 2))
    table = []
    for key, row in rows.items():
        mean = lambda xs: round(float(np.mean(xs)), 3) if xs else None  # noqa: E731
        table.append(dict(cls=row["cls"], window=row["window"], strength=row["strength"], sampler=row["sampler"], n=len(row["scores"]), planned=row["planned"],
                          errors=row["errors"], score=mean(row["scores"]), score_min=(min(row["scores"]) if row["scores"] else None), clean=mean(row["clean"]), lone=mean(row["lone"]), span=mean(row["span"]),
                          render_s=mean(row["render_s"]), total_s=mean(row["total_s"]), upload_mb=mean(row["upload_mb"]), vram_gb=mean(row["vram_gb"]), runs=row["runs"]))
    chosen = choose(table)
    out = {"made": time.strftime("%Y-%m-%dT%H:%M:%S"), "pass_min": PASS_MIN, "colour_tol": COLOUR_TOL, "area_range": list(AREA_RANGE), "tie": TIE,
           "table": table, "chosen": chosen}
    _save(os.path.join(OUT, "summary.json"), out)
    md = markdown(out)
    with open(os.path.join(OUT, "summary.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(md)
    print(md)
    return out


def choose(table):
    """Per class: the profile with the best mean score, ties (within TIE) to the cheaper render; the escalation rungs are the
    plan's fixed ladder single -> double -> reroll_view for a reliable class; a class under PASS_MIN escalates to
    reroll_view at once and stays conditional. `other_window_score` says how the other window did."""
    out = {}
    for cls in ("ctl", "pose", "free", "cell"):
        rows = [t for t in table if t["cls"] == cls and t["score"] is not None]
        if not rows:
            out[cls] = {"profile": None, "escalation": ["reroll_view"], "reliable": False, "why": "no finished run"}
            continue
        rows.sort(key=lambda t: (-(t["score"] or 0), t["render_s"] or 1e9))
        best = rows[0]
        for t in rows[1:]:
            if best["score"] - t["score"] <= TIE and (t["render_s"] or 1e9) < (best["render_s"] or 1e9):
                best = t
        reliable = (best["score"] or 0) >= PASS_MIN
        sp = SAMPLERS[best["sampler"]]
        prof = {"window": best["window"], "frames": 13 if best["window"] == "single" else 25, "strength": best["strength"], "steps": sp["steps"], "cfg": sp["cfg"], "lora": sp["lora"]}
        other = "double" if best["window"] == "single" else "single"
        other_rows = [t for t in rows if t["window"] == other and t["strength"] == best["strength"] and t["sampler"] == best["sampler"]]
        other_best = max((t["score"] for t in other_rows), default=None)
        # the ladder's order is the plan's fixed one (INTERFACES, F5 G1: single -> double -> reroll_view); the profile's window
        # says where a hand run or an "auto" job starts; a class that is not reliable escalates to a re-roll at once
        esc = list(VR.DEFAULT_ESCALATION) if reliable else ["reroll_view"]
        out[cls] = {"profile": prof, "escalation": esc, "reliable": reliable, "score": best["score"], "render_s": best["render_s"],
                    "other_window_score": other_best, "why": ("best mean score %s at %s s" % (best["score"], best["render_s"])) if reliable else
                    ("best mean score %s is under %s: VACE stays conditional, escalate to a re-roll" % (best["score"], PASS_MIN))}
    return out


def markdown(out):
    lines = ["# VACE repair benchmark (pass 96, lane GATES, G1): %s" % out["made"], "",
             "Score = checks passed / checks on the redone slots (empty, jump, footprint, area %s-%s of the median, colour <= %.2f x the kept median, silhouette where a driver exists, the seam when slot 0 or n-1 is redone); mean over the seeds; clean slots = the share of redone slots passing every check; lone = a redone slot with no redone neighbour, span = the rest. Ties within %.2f go to the cheaper render." % (
                 out["area_range"][0], out["area_range"][1], out["colour_tol"], out["tie"]), "",
             "| class | window | strength | sampler | runs | score (mean) | min | clean slots | lone | span | render s | total s | upload MB | VRAM GB used |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for t in out["table"]:
        lines.append("| %s | %s | %.1f | %s | %d/%d%s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            t["cls"], t["window"], t["strength"], t["sampler"], t["n"], t["planned"], (" (%d failed)" % t["errors"]) if t["errors"] else "",
            t["score"], t["score_min"], t.get("clean"), t["lone"], t["span"], t["render_s"], t["total_s"], t["upload_mb"], t["vram_gb"]))
    lines += ["", "## Chosen per class", ""]
    for cls, c in out["chosen"].items():
        lines.append("- **%s**: %s; profile %s; escalation %s" % (cls, c["why"], json.dumps(c["profile"]), " -> ".join(c["escalation"])))
    lines += ["", "## Runs", ""]
    for t in out["table"]:
        for r in t["runs"]:
            if r.get("error"):
                lines.append("- %s: FAILED %s" % (r["id"], r["error"]))
            else:
                lines.append("- %s: score %s (lone %s, span %s), render %s s, sheet %s" % (r["id"], r["score"], r["lone"], r["span"], r["render_s"], r.get("sheet")))
    return "\n".join(lines) + "\n"


def write_profiles(dry=False, summary=None, path=None):
    """methods.json: every method's `repair` line gains `profile` and `escalation` (its class's chosen ones), in place, one line
    each, the file's other lines untouched. A class under PASS_MIN sets `vace` to conditional where it said yes."""
    path = path or VR.METHODS_JSON
    summary = summary or _load(os.path.join(OUT, "summary.json"))
    if not summary or not summary.get("chosen"):
        raise SystemExit("vace_bench: no summary.json yet: run `score` first")
    chosen = summary["chosen"]
    with open(path, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(nl)
    doc = json.loads(text)
    ids = [str(m.get("id")) for m in doc.get("methods") or [] if isinstance(m, dict)]
    changed = []
    mid_i = 0
    out_lines = []
    cur = None
    method_indent = None   # a method's own keys sit at one depth; a nested "id" (an example record) is deeper and never names a method
    for line in lines:
        s = line.strip()
        indent = line[: len(line) - len(line.lstrip())]
        if s.startswith('"repair":') and method_indent is None:
            method_indent = indent
        if s.startswith('"id":') and (method_indent is None or indent == method_indent):
            try:
                cur = json.loads("{" + s.rstrip(",") + "}")["id"]
            except ValueError:
                cur = None
        if s.startswith('"repair":') and cur is not None and indent == method_indent:
            body = s[len('"repair":'):].strip()
            trailing = ","
            if body.endswith(","):
                body = body[:-1].rstrip()
            else:
                trailing = ""
            rule = json.loads(body)
            cls = CLASS_OF_METHOD.get(cur, "cell")
            c = chosen.get(cls) or {}
            if c.get("profile"):
                rule["profile"] = c["profile"]
            rule["escalation"] = c.get("escalation") or ["reroll_view"]
            if not c.get("reliable") and rule.get("vace") == "yes":
                rule["vace"] = "conditional"
            new = indent + '"repair": ' + json.dumps(rule, ensure_ascii=False) + trailing
            if new != line:
                changed.append(cur)
            out_lines.append(new)
            continue
        out_lines.append(line)
    new_text = nl.join(out_lines)
    json.loads(new_text)   # still valid
    if dry:
        print("would change %d rule(s): %s" % (len(changed), ", ".join(changed)))
        return changed
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(new_text)
    print("methods.json: %d repair rule(s) updated: %s" % (len(changed), ", ".join(changed)))
    return changed


def checks_cli(kind, cid, code, base, view, slots):
    """The checks on the REAL store's staged state of a group (no GPU; nothing written): what the loop would read."""
    look = fs.Look(kind, cid, code)
    g = fs.Group(look, base, view)
    if not g.exists():
        raise SystemExit("no group %s %s %s/%s in the store" % (cid, code, base, view))
    cls = VR.class_of(g.meta.get("method"), g.meta)
    base_rec = baseline(g, "%s_%s_%s_%s_%s" % (kind, cid, fs.code_part(code), base, view))
    redo = VR.parse_slots(slots, g.n)
    info = {"slots": redo, "versions": [{"slot": k, "id": g.effective(k)[0]["id"]} for k in redo]}
    res = checks(g, info, base_rec, stage=False)
    print(json.dumps({"class": cls, "score": res["score"], "passed": res["passed"], "of": res["of"], "lone": res["lone"], "span": res["span"],
                      "per_slot": {k: {"kind": v["kind"], "checks": v["checks"], "colour": v["colour"], "area_ratio": v["area_ratio"]} for k, v in res["per_slot"].items()}}, indent=1))
    return res


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    cmd = argv[0] if argv else "plan"
    dry = "--dry-run" in argv
    if cmd == "plan":
        for k, r in enumerate(plan()):
            res = result_of(r["id"]) or {}
            print("%2d %-40s %s" % (k + 1, r["id"], ("score %s, render %s s" % (res.get("score"), (res.get("cost") or {}).get("render_s"))) if res.get("score") is not None
                                    else ("FAILED " + res["error"][:80]) if res.get("error") else ""))
    elif cmd == "run":
        only = None
        limit = None
        if "--only" in argv:
            only = argv[argv.index("--only") + 1].split(",")
        if "--limit" in argv:
            limit = int(argv[argv.index("--limit") + 1])
        run_all(only, limit, dry)
    elif cmd == "one":
        one(argv[1], dry)
    elif cmd == "score":
        score_all()
    elif cmd == "write-profiles":
        write_profiles(dry)
    elif cmd == "checks":
        checks_cli(*argv[1:7])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

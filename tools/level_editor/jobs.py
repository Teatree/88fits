"""The Level Editor's jobs queue (pass 66): the local AI's work as a list Garry can watch, edit, reorder, cancel and add to.

Three lanes, one job each at a time, as daemon threads inside the editor server:
    comfy   the art (gen_art / gen_ctl / gen_edit_stills / gen_icon_cands / gen_title_heroes / gen_badge_cands) through
            `python -u tools/asset_job.py <job_dir>`, under the repo-wide ComfyUI lock (tools/locks.py, comfy.lock)
    godot   register / import / launch, under the Godot lock with the PC save kept aside
    local   Blender (drivers, 3D probes and renders), the pose_* tools, recolour_strip, installs of picked candidates

The queue lives in tools/dl/jobs/queue.json (atomic writes, a monotonic `rev` the page polls with); each job has its
folder tools/dl/jobs/<id>/ with job.json (what asset_job.py runs), log.txt, result.json (the tool's sidecar, see
gen_art.emit_sidecar) and candidate pictures. Nothing here imports server.py: the server hands `init()` a hooks dict
(content_path, merge_look, merge_top, set_recipe, redump_merge, look_records) and every content write goes through it.

    queued ──worker (oldest of its lane; a picked continuation goes first)──► running
    running ──exit 0, no stop marker──► post phase (merge through the hooks, an import job) ──► done
    running ──exit 0 + a stop marker ("side candidates painted" | "pick with --use-view" | "then --pick N")──► waiting
             ──pick──► queued (phase + 1, same id, at the front of its lane)
    running ──exit ≠ 0──► failed      running ──cancel (taskkill /T /F; a comfy job also gets /interrupt + /queue clear)──► cancelled
    queued ──edit / move / cancel      running ──the server stopped──► interrupted (recover() at the next start)
    done | failed | cancelled | interrupted ──requeue (attempt + 1, optional re-roll)──► queued
    any state but running ──edit──► the command re-derived (a waiting job goes back to queued, phase 1)

Nothing starts at import: `init(hooks, root)` loads the queue and recovers, `start_workers()` starts the three threads
(only server.main() calls it; the selftest pins threading.active_count()).
"""
import collections
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
import locks  # noqa: E402

_LIST = list   # the API below is named list(); the builtin stays reachable as _LIST

GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")
DL = os.path.join(ROOT, "tools", "dl")
JOBS_DIR = os.path.join(DL, "jobs")
QUEUE_FILE = os.path.join(JOBS_DIR, "queue.json")
RAW = os.path.join(DL, "ai_raw_anime")
ANIM = os.path.join(DL, "ai_anim")
REVIEW = os.path.join(DL, "review")
DRIVERS = os.path.join(DL, "drivers")
UPLOADS = os.path.join(DL, "uploads")
TITLE_OUT = os.path.join(DL, "title_heroes")
METHODS_FILE = os.path.join(HERE, "methods.json")
PY = sys.executable
GODOT = locks.GODOT
LAUNCH_FILE = os.path.join(locks.SAVE_DIR, "debug_launch.json")   # a module variable: the selftest points it at a temp dir
COMFY_SERVER = os.environ.get("COMFY_SERVER", "http://192.168.137.54:8188")
LMSTUDIO_MODELS = "http://127.0.0.1:1234/v1/models"
STALL_SECONDS = 20 * 60          # silence this long marks a job stalled (never killed: a dev restart can take minutes)
CACHE_CHECK_SECONDS = 5.0
SAVE_THROTTLE = 2.0
LOG_TAIL_FULL = 80
LOG_TAIL_SHORT = 12
STATES = ("queued", "running", "waiting", "done", "failed", "interrupted", "cancelled")
LANES = ("comfy", "godot", "local")
KIND_FOLDERS = {"enemy": "enemies", "boss": "bosses", "hero": "characters", "weapon": "weapons", "evolution": "evolutions",
                "passive": "passives", "mutation": "mutations"}
LOOK_METHODS = ("hero_pose5", "hero_fit", "creature_free2", "creature_pose2", "creature_free8", "creature_ctl", "creature_proc",
                "front_from_picture", "recolour")
CTL_VIEWS = ("front", "fd", "side", "bd", "back")
HERO_VIEWS = ("front", "back", "side", "fd", "bd")
# median seconds per method when methods.json has no timing (the synthesis §7; "~" always on the page)
BUILTIN_MEDIAN = {"hero_pose5": 570, "hero_fit": 276, "creature_free2": 450, "creature_pose2": 240, "creature_free8": 960,
                  "creature_ctl": 660, "creature_ctl_side": 60, "creature_ctl_side_dev": 840, "creature_proc": 90,
                  "front_from_picture": 20, "recolour": 5, "item_icon": 20, "icon_cands": 20, "icon_cands_dev": 270,
                  "hero_badge": 20, "hero_title": 25, "driver_pose": 60, "driver_depth": 300, "ref_probe": 10,
                  "ref_render": 60, "register": 120, "import": 90, "launch": 0, "install": 5}

# ---------------------------------------------------------------- the kinds and their fields

def _f(type_, default=None, required=False, help_="", options=None, group=None):
    d = {"type": type_, "default": default, "required": required, "help": help_}
    if group:
        d["group"] = group
    if options:
        d["options"] = _LIST(options)
    return d


_LOOK_FIELDS = {
    "method": _f("enum", None, True, "how the look is made (tools/level_editor/methods.json describes each)", LOOK_METHODS),
    "recipe": _f("json", {}, False, "variants[CODE].recipe: the art keys this look overrides (gen_art / gen_ctl read it from the JSON)"),
    "refs": _f("list", [], False, "2D references [{path, role: identity|style|pose, follow: loosely|closely|copy, use: [look]}]"),
    "drivers": _f("json", {}, False, "{pose: <driver folder>, depth: <driver folder>} (tools/dl/drivers/)"),
    "skip_qa": _f("bool", False, False, "--skip-qa: no vision check (LM Studio); the geometry checks still run"),
    "dev": _f("bool", False, False, "--dev: Flux.2 dev for the stills (gen_ctl's side candidates): 4-5 min each with a server restart"),
    "seed": _f("int", 0, False, "--seed=N: every seed moves by N x 7919 (a fresh roll of the stills named in `keys`)"),
    "seeds": _f("int", 3, False, "candidates at a human stop (gen_ctl's side view; front_from_picture's fronts)"),
    "keys": _f("list", [], False, "--keys: still cache keys painted again (tools/dl/ai_raw_anime/<key>.png)"),
    "no_video": _f("bool", False, False, "--no-video: no Wan clips at all, procedural frames (creature_proc)"),
    "stills": _f("str", "", False, "front_from_picture: the slug the picked front is cached under (<id>_<slug>_front)"),
    "ref": _f("str", "", False, "front_from_picture: the picture (a path under the repo, e.g. tools/dl/uploads/2d/x.png)"),
    "prompt": _f("str", "", False, "front_from_picture: the creature in words"),
    "keep": _f("str", "", False, "front_from_picture: what the redraw must keep (\"small yellow eyes\")"),
    "screen": _f("enum", "", False, "the screen colour the stills are painted on", ("", "green", "blue")),
    "no_style_ref": _f("bool", False, False, "front_from_picture: leave the style anchor out (the picture alone sets the look)"),
    "stage": _f("str", "", False, "creature_ctl: --stage=paint stops after the five views"),
    "use_side": _f("str", "", False, "creature_ctl: the side candidate picked (k0..); set by Pick"),
    "view_cands": _f("str", "", False, "creature_ctl: views to paint again as candidates (fd,back)"),
    "use_view": _f("str", "", False, "creature_ctl: the view candidates picked (fd:c1,back:c0); set by Pick"),
    "pick": _f("str", "", False, "front_from_picture: the candidate picked (0..); set by Pick"),
    "recolour": _f("json", {}, False, "recolour: {from: CODE, ranges: [[60,130]], to: 355, sat: 1.0, mode: hue|tint, set_sat, value, min_sat, max_sat, min_val}"),
    "note": _f("str", "", False, "the look's note (shown on its card)"),
}

# the painter and its quality (Garry: "choose which Model ... the number of passes"): one group on every job that paints
# stills; jobs.py hands them to the tools as ART_* environment variables (gen_art.MODEL / gen_art.paint)
MODEL_FIELDS = {
    "model": _f("enum", "klein", False, "the painter: Flux.2 Klein (4 steps, ~20 s a still) or Flux.2 dev (the better painter, 4-5 min a still with a server restart each)", ("klein", "dev"), group="model"),
    "steps": _f("int", 0, False, "the passes (sampling steps): 0 = the model's own default (Klein 4; dev 8 with Turbo, 28 without); more = slower and usually cleaner", group="model"),
    "guidance": _f("float", 0.0, False, "dev only: how hard the words are followed (0 = the default 4.0)", group="model"),
    "turbo": _f("bool", True, False, "dev only: the Turbo LoRA (8 quick steps); off = the full 28-step quality, what the candidate methods use", group="model"),
}


def _with_model(fields):
    out = dict(fields)
    out.update(MODEL_FIELDS)
    return out


SPECS = {
    "look": {"lane": "comfy", "fields": _with_model(_LOOK_FIELDS),
             "help": "one art look of an enemy, boss or hero (target.code); `recolour` runs on the local lane"},
    "item_icon": {"lane": "comfy", "fields": _with_model({
        "skip_qa": _f("bool", False, False, "--skip-qa"), "dev": _f("bool", False, False, "--dev"),
        "seed": _f("int", 0, False, "--seed=N")}), "help": "one Klein roll of the item's art_prompt into <id>_icon.png (the old icon is kept aside)"},
    "icon_cands": {"lane": "comfy", "fields": _with_model({
        "subject": _f("str", "", True, "what to paint (gen_icon_cands JOBS[key].subject)"),
        "ref": _f("str", "", False, "a reference render laid on the screen colour (tools/dl/<x>_ref.png or an upload)"),
        "screen": _f("enum", "green", False, "the screen colour", ("green", "blue")),
        "style": _f("str", "", False, "words in place of gen_art's ICON_STYLE"),
        "file": _f("str", "", False, "the icon file the pick installs (<id>_icon.png, or a look's <id>_icon_<x>.png)"),
        "key": _f("str", "", False, "the candidates' key (default: the target id)"),
        "seeds": _f("int", 4, False, "how many candidates"), "dev": _f("bool", False, False, "--dev: Flux.2 dev at 28 steps, a restart each")}),
        "help": "icon candidates for an item, or for an enemy/boss look (file = its <id>_icon_<x>.png); Install picks one"},
    "hero_badge": {"lane": "comfy", "fields": _with_model({
        "seeds": _f("int", 4, False, "how many portraits"), "prompt": _f("str", "", False, "the portrait words (default: the hero's portrait_prompt)"),
        "first_seed": _f("int", 0, False, "added to every seed"), "head_width": _f("float", 0.0, False, "badge: the head's span as a share of the badge (0 = the default zoom)"),
        "top_pad": _f("float", 0.03, False, "badge: the gap above the head"), "skip_qa": _f("bool", False, False, "--skip-qa")}),
        "help": "round badge candidates from the hero's front still; Install writes <id>_icon.png and the JSON's badge"},
    "hero_title": {"lane": "comfy", "fields": _with_model({
        "seeds": _f("int", 4, False, "how many cut-outs"), "first_seed": _f("int", 11, False, "the first seed (+101 each)")}),
        "help": "title cut-out candidates (title_pose / title_holds / title_camera / title_extra_ref from the hero JSON); Install writes art/ui/wanted/hero_<id>.png"},
    "driver_pose": {"lane": "local", "fields": {
        "src": _f("str", "", True, "the FBX or GLB (tools/dl/uploads/3d/<slug>/<file> or tools/dl/mixamo/<file>)"),
        "name": _f("str", "", True, "the driver folder name under tools/dl/drivers/"),
        "frames": _f("int", 24, False, "24 for a run, 12 for a walk; a one-shot wants 4k+1 (9, 25)"),
        "loop": _f("bool", True, False, "a loop (the last frame repeats the first) or a one-shot"),
        "pitch": _f("int", 25, False, "the camera's pitch"), "start": _f("str", "", False, "slice: start seconds"), "end": _f("str", "", False, "slice: end seconds"),
        "arms": _f("str", "", False, "zombie | hold_r"), "body": _f("str", "", False, "retarget proportions top_nose:..,torso:.."),
        "fwd": _f("str", "", False, "body: square the views to the hips and shoulders"), "rig": _f("str", "", False, "mixamo (default) | sm"),
        "rigmap": _f("str", "", False, "a {model_bone: mixamo_name} JSON for another humanoid rig")},
        "help": "an OpenPose driver from a rigged clip (Blender), then its sheets (pose_driver.py draw)"},
    "driver_depth": {"lane": "local", "fields": {
        "src": _f("str", "", True, "the rigged model"), "name": _f("str", "", True, "the driver folder name"), "action": _f("str", "", False, "the clip to play"),
        "mode": _f("enum", "cycle", False, "cycle (a walk) | oneshot (a death)", ("cycle", "oneshot")), "frames": _f("int", 12, False, ""),
        "cycles": _f("int", 2, False, ""), "total": _f("int", 25, False, "oneshot frames"), "start": _f("str", "", False, ""), "end": _f("str", "", False, ""),
        "depth": _f("enum", "tight", False, "", ("tight", "wide")), "amp": _f("float", 1.0, False, "legs swing this much wider"),
        "amp_bones": _f("str", "", False, "regex of the bones amp applies to"), "pitch": _f("int", 25, False, ""), "views": _f("str", "", False, "front,fd,side,bd,back"),
        "forward": _f("str", "", False, "-Y"), "screen": _f("str", "", False, "0,1,0"), "albedo": _f("str", "", False, ""), "inplace": _f("bool", True, False, "")},
        "help": "depth control videos for gen_ctl from a model's own clip (tools/blender_depth_drivers.py, lane B)"},
    "ref_probe": {"lane": "local", "fields": {"src": _f("str", "", True, "the 3D file")}, "help": "what a 3D file can do: probe.json beside it"},
    "ref_render": {"lane": "local", "fields": {
        "src": _f("str", "", True, "the 3D file"), "mode": _f("enum", "views", False, "", ("icon", "views", "all")), "forward": _f("str", "", False, ""),
        "action": _f("str", "", False, ""), "at": _f("str", "", False, "seconds"), "frame": _f("str", "", False, ""), "pitch": _f("int", 25, False, ""),
        "icon_yaw": _f("int", 35, False, ""), "icon_pitch": _f("int", 20, False, ""), "size": _f("int", 1024, False, ""), "screen": _f("str", "", False, ""),
        "albedo": _f("str", "", False, ""), "scale": _f("str", "auto", False, "")}, "help": "icon and look renders of a 3D file (tools/blender_ref.py, lane B)"},
    "register": {"lane": "godot", "fields": {"targets": _f("list", [], True, "content folders type/id (enemies/goblin)")},
                 "help": "a new folder: placeholders, --import, lossy, --import, import_json"},
    "import": {"lane": "godot", "fields": {"targets": _f("list", [], True, "content folders type/id"), "placeholders": _f("bool", False, False, "draw placeholders first")},
               "help": "--import, lossy_imports, --import, import_json only=...; consecutive queued imports merge"},
    "launch": {"lane": "godot", "fields": {
        "character": _f("str", "", False, "the hero"), "look": _f("str", "", False, "the hero's look code (shown, not kept)"),
        "spawn_enemy": _f("str", "", False, "a creature to spawn"), "variant": _f("str", "", False, "its look code"),
        "count": _f("int", 3, False, "how many"), "map": _f("str", "red_canyon", False, "")},
        "help": "Test in game: the debug arena in a window (user://debug_launch.json; the Godot lock is held while it is open)"},
    "install": {"lane": "local", "fields": {
        "source_job": _f("str", "", True, "the finished icon_cands / hero_badge / hero_title job"), "choice": _f("str", "", True, "which candidate"),
        "head_width": _f("float", 0.0, False, "badge"), "top_pad": _f("float", 0.03, False, "badge")},
        "help": "a picked candidate written into the game (then an import job)"},
}

# ---------------------------------------------------------------- state

_lock = threading.RLock()
_state = {"rev": 0, "jobs": []}
_hooks = None
_root = ROOT
_workers = []
_stop = threading.Event()
_live = {}                       # job id -> Live
_lane_current = {l: None for l in LANES}
_qa_cache = {"t": 0.0, "v": None}
_log = lambda m: print(m, flush=True)   # noqa: E731


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def _hook(name):
    if _hooks is None:
        return None
    if isinstance(_hooks, dict):
        return _hooks.get(name)
    return getattr(_hooks, name, None)


def _rel(path):
    try:
        return os.path.relpath(path, _root).replace("\\", "/")
    except ValueError:
        return path.replace("\\", "/")


class Live:
    """A running job's process-side state (never persisted)."""

    def __init__(self, job):
        self.job = job
        self.proc = None
        self.cancelled = False
        self.tail = collections.deque(maxlen=LOG_TAIL_FULL)
        self.marker = None
        self.logf = None
        self.key_to_stage = {}
        self.last_save = 0.0
        self.lock = None


# ---------------------------------------------------------------- persistence

def _load():
    global _state
    try:
        with open(QUEUE_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
        if isinstance(d, dict) and isinstance(d.get("jobs"), _LIST):
            _state = {"rev": int(d.get("rev", 0)), "jobs": [j for j in d["jobs"] if isinstance(j, dict) and j.get("id")]}
            return True
    except (OSError, ValueError):
        pass
    _state = {"rev": 0, "jobs": []}
    return False


def _save():
    with _lock:
        if _readonly is not None:   # a read-only editor never writes the queue
            return _state["rev"]
        _state["rev"] += 1
        os.makedirs(JOBS_DIR, exist_ok=True)
        tmp = QUEUE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            json.dump(_state, f, indent=1, ensure_ascii=False)
        os.replace(tmp, QUEUE_FILE)
        return _state["rev"]


def _find(job_id):
    for j in _state["jobs"]:
        if j["id"] == job_id:
            return j
    return None


def _job_dir(job_id):
    return os.path.join(JOBS_DIR, job_id)


def _new_id():
    return "j%s-%s" % (time.strftime("%Y%m%d-%H%M%S"), uuid.uuid4().hex[:4])


# ---------------------------------------------------------------- content helpers (read-only)

def content_path(kind, cid):
    """(type folder, json path) through the server's hook when there is one, else the folder table."""
    h = _hook("content_path")
    if h:
        try:
            tf, jp = h(kind, cid)
            if jp:
                return tf, jp
        except Exception:
            pass
    tf = KIND_FOLDERS.get(kind)
    if not tf:
        return None, None
    return tf, os.path.join(CONTENT, tf, cid, cid + ".json")


def content_doc(kind, cid):
    tf, jp = content_path(kind, cid)
    if not jp or not os.path.isfile(jp):
        return None
    try:
        with open(jp, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _content_folder(kind, cid):
    tf, jp = content_path(kind, cid)
    return os.path.dirname(jp) if jp else None


def _methods():
    try:
        with open(METHODS_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
        out = {}
        for m in d.get("methods", []):
            if isinstance(m, dict) and m.get("id"):
                out[m["id"]] = m
        return out
    except (OSError, ValueError):
        return {}


def blender_path():
    env = os.environ.get("BLENDER")
    if env and os.path.isfile(env):
        return env
    for pat in (os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "blender-*", "blender.exe"),
                "C:/Program Files/Blender Foundation/Blender */blender.exe"):
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[-1]
    return None


def qa_online(max_age=30.0):
    """Whether LM Studio (the vision QA) answers at 127.0.0.1:1234; cached for `max_age` seconds."""
    now = time.time()
    if now - _qa_cache["t"] < max_age:
        return _qa_cache["v"]
    try:
        urllib.request.urlopen(LMSTUDIO_MODELS, timeout=1.5).read(64)
        v = True
    except Exception:
        v = False
    _qa_cache.update(t=now, v=v)
    return v


# ---------------------------------------------------------------- keys, stages, titles

def _code_part(code):
    return code.lower().replace("-", "") if code else ""


def _letter(code):
    return code.split("-")[-1].lower() if code else ""


def cache_keys(method, spec, target, doc=None):
    """The still and clip cache keys a look job reads or makes (gen_art.py's sk/ak/ck, gen_ctl's key), for re-roll offers."""
    cid, code = target.get("id", ""), target.get("code", "")
    recipe = (spec or {}).get("recipe") or {}
    doc = doc or {}
    stills, clips = [], []
    if method in ("creature_free2", "creature_pose2", "creature_free8", "creature_proc"):
        st = recipe.get("stills", doc.get("stills"))
        sk = cid + ("_" + str(st) if st else "")
        ak = cid + ("_" + _code_part(code) if code else "")
        stills = [sk + "_front", sk + "_back", sk + "_dead"]
        if method == "creature_free8" or int(recipe.get("directions", doc.get("directions", 2))) == 8:
            stills += [sk + "_side", sk + "_bd", sk + "_fd"]
            clips += [ak + "_walk_side", ak + "_walk_bd", ak + "_walk_fd"]
        if method == "creature_pose2" or (recipe.get("pose", doc.get("pose")) and method != "creature_proc"):
            clips = [ak + "_pose_f", ak + "_pose_b"] + clips
        elif method != "creature_proc" and str(recipe.get("walk", doc.get("walk", ""))) != "hop":
            clips = [ak + "_walk_f", ak + "_walk_b"] + clips
        death = str(recipe.get("death", doc.get("death", "")))
        if death == "clip":
            clips.append(ak + "_fall")
        elif death.startswith("pose:"):
            clips.append(ak + "_death")
    elif method in ("hero_pose5", "hero_fit"):
        skeys = recipe.get("still_keys") if isinstance(recipe.get("still_keys"), dict) else (doc.get("still_keys") if isinstance(doc.get("still_keys"), dict) else {})
        ck = cid + ("_" + _code_part(code) if code else "")
        for v in HERO_VIEWS:
            stills.append(str(skeys.get(v, cid + "_" + v)))
        stills.append(str(skeys.get("cheer", cid + "_cheer")))
        for v in HERO_VIEWS:
            stills.append(str(skeys.get("hurt_" + v, cid + "_hurt_" + v)))
        stills.append(str(skeys.get("dead", cid + "_dead")))
        if not code:
            stills.append(cid + "_portrait")
        clips = [ck + "_pose_run_" + v for v in ("back", "front", "side", "bd", "fd")]
    elif method == "creature_ctl":
        key = cid + "_" + _code_part(code)
        n = int((spec or {}).get("seeds") or recipe.get("side_seeds", 3) or 3)
        stills = [key + "_side"] + ["%s_side_k%d" % (key, k) for k in range(n)] + [key + "_" + v for v in ("front", "fd", "bd", "back")]
        two = int(recipe.get("directions", 8)) == 2
        clips = [key + "_ctl_" + v for v in (("front", "back") if two else CTL_VIEWS)]
        if recipe.get("death_drivers"):
            clips.append(key + "_death")
        else:
            stills.append(key + "_dead")
            clips.append(key + "_fall")
    elif method == "front_from_picture":
        slug = str((spec or {}).get("stills") or "")
        n = int((spec or {}).get("seeds") or 4)
        stills = ["%s_%s_front_c%d" % (cid, slug, k) for k in range(n)]
    return {"stills": stills, "clips": clips}


def expected_stages(method, spec, target, doc=None, phase=1):
    """[{name, key, type}] in the order the tool reaches them; `total` for the bar. gen_ctl phase 1 is the side
    candidates (unless the side is already cached), phase 2 the views, the walks, the death and the pack."""
    cid, code = target.get("id", ""), target.get("code", "")
    recipe = (spec or {}).get("recipe") or {}
    doc = doc or {}
    keys = cache_keys(method, spec, target, doc)
    st = []

    def add(name, key, type_):
        st.append({"name": name, "key": key, "type": type_})

    if method in ("creature_free2", "creature_pose2", "creature_free8", "creature_proc"):
        stills, clips = keys["stills"], keys["clips"]
        add("front", stills[0], "still")
        add("back", stills[1], "still")
        for k in clips:
            if k.endswith("_walk_f") or k.endswith("_pose_f"):
                add("pose_f" if k.endswith("_pose_f") else "walk_f", k, "clip")
            elif k.endswith("_walk_b") or k.endswith("_pose_b"):
                add("pose_b" if k.endswith("_pose_b") else "walk_b", k, "clip")
        for s in stills[3:]:
            add(s.rsplit("_", 1)[-1], s, "still")
        for k in clips:
            for v in ("side", "bd", "fd"):
                if k.endswith("_walk_" + v):
                    add("walk_" + v, k, "clip")
        add("dead", stills[2], "still")
        for k in clips:
            if k.endswith("_fall"):
                add("fall", k, "clip")
            elif k.endswith("_death"):
                add("death", k, "clip")
        add("pack", "", "pack")
    elif method == "hero_pose5":
        stills, clips = keys["stills"], keys["clips"]
        names = _LIST(HERO_VIEWS) + ["cheer"] + ["hurt_" + v for v in HERO_VIEWS] + ["dead"]
        for n, k in zip(names[:6], stills[:6]):
            add(n, k, "still")
        for n, k in zip(("back", "front", "side", "bd", "fd"), clips):
            add("pose_run_" + n, k, "clip")
        for n, k in zip(names[6:], stills[6:12]):
            add(n, k, "still")
        if not code and len(stills) > 12:
            add("portrait", stills[12], "still")
        add("pack", "", "pack")
    elif method == "hero_fit":
        for n, k in zip(("back", "front", "side", "bd", "fd"), keys["clips"]):
            add("pose_run_" + n, k, "clip")
        add("pack", "", "pack")
    elif method == "creature_ctl":
        key = cid + "_" + _code_part(code)
        side_cached = os.path.isfile(os.path.join(RAW, key + "_side.png"))
        if phase <= 1 and not side_cached and not (spec or {}).get("use_side"):
            for k in keys["stills"]:
                if "_side_k" in k:
                    add(k.rsplit("_", 1)[-1] and "side_" + k.rsplit("_", 1)[-1], k, "still")
            add("side candidates", "", "stop")
        else:
            for v in ("front", "fd", "bd", "back"):
                add(v, key + "_" + v, "still")
            for k in keys["clips"]:
                if "_ctl_" in k:
                    add("ctl_" + k.rsplit("_", 1)[-1], k, "clip")
            if key + "_dead" in keys["stills"]:
                add("dead", key + "_dead", "still")
            for k in keys["clips"]:
                if k.endswith("_death"):
                    add("death", k, "clip")
                elif k.endswith("_fall"):
                    add("fall", k, "clip")
            add("pack", "", "pack")
    elif method == "front_from_picture":
        if phase <= 1 and not (spec or {}).get("pick"):
            for k in keys["stills"]:
                add("front_" + k.rsplit("_", 1)[-1], k, "still")
            add("candidates", "", "stop")
        else:
            add("install", "", "pack")
    elif method == "recolour":
        add("strip", "", "pack")
        add("icon", "", "pack")
    return st


def _eta(job):
    """Median seconds from methods.json's timings (else the built-in table), scaled by the stages still pending."""
    kind, method = job["kind"], job.get("method") or job["kind"]
    spec = job.get("spec") or {}
    key = method
    if method == "creature_ctl" and job.get("phase", 1) <= 1 and not spec.get("use_side"):
        key = "creature_ctl_side_dev" if spec.get("dev") else "creature_ctl_side"
    if kind == "icon_cands" and spec.get("dev"):
        key = "icon_cands_dev"
    med = None
    m = _methods().get(method)
    if m and isinstance(m.get("time"), dict) and m["time"].get("median_s"):
        med = float(m["time"]["median_s"])
    if med is None:
        med = float(BUILTIN_MEDIAN.get(key, BUILTIN_MEDIAN.get(method, 60)))
    if kind in ("icon_cands", "hero_badge", "hero_title", "front_from_picture") or method == "front_from_picture":
        med *= max(1, int(spec.get("seeds") or 1))
    stages = (job.get("progress") or {}).get("stages") or []
    if stages:
        pending = sum(1 for s in stages if s.get("state") not in ("done", "skipped"))
        return int(round(med * pending / max(1, len(stages))))
    return int(round(med))


def _title(job):
    t = job.get("target") or {}
    doc = content_doc(t.get("kind", ""), t.get("id", "")) if t.get("id") else None
    name = (doc or {}).get("name") or t.get("id") or job["kind"]
    code = t.get("code", "")
    method = job.get("method") or ""
    if job["kind"] == "look":
        return "%s %s · %s" % (name, code, method)
    if job["kind"] in ("register", "import"):
        return "%s %s" % (job["kind"], ", ".join((job.get("spec") or {}).get("targets") or []))
    if job["kind"] == "launch":
        s = job.get("spec") or {}
        return "Test in game: " + ", ".join(x for x in (s.get("character"), s.get("spawn_enemy"), s.get("variant"), s.get("look")) if x)
    if job["kind"] in ("driver_pose", "driver_depth"):
        return "%s %s" % (job["kind"], (job.get("spec") or {}).get("name", ""))
    if job["kind"] in ("ref_probe", "ref_render"):
        return "%s %s" % (job["kind"], os.path.basename((job.get("spec") or {}).get("src", "")))
    return "%s%s · %s" % (name, (" " + code) if code else "", job["kind"])


# ---------------------------------------------------------------- validation

def _coerce(name, f, v):
    t = f["type"]
    if v is None:
        return f.get("default")
    try:
        if t == "int":
            return int(v)
        if t == "float":
            return float(v)
        if t == "bool":
            if isinstance(v, str):
                return v.strip().lower() in ("1", "true", "yes", "on")
            return bool(v)
        if t == "enum":
            v = str(v)
            if f.get("options") and v not in f["options"]:
                raise ValueError("%s: %r is not one of %s" % (name, v, ", ".join(repr(o) for o in f["options"])))
            return v
        if t == "json":
            if isinstance(v, str):
                v = json.loads(v) if v.strip() else {}
            if not isinstance(v, dict):
                raise ValueError("%s: a JSON object is wanted" % name)
            return v
        if t == "list":
            if isinstance(v, str):
                v = [x.strip() for x in v.split(",") if x.strip()]
            if not isinstance(v, _LIST):
                raise ValueError("%s: a list is wanted" % name)
            return v
        return str(v)
    except ValueError:
        raise
    except Exception as e:
        raise ValueError("%s: %s" % (name, e))


def validate_spec(kind, spec):
    """The spec coerced to SPECS[kind]'s types with its defaults filled in; ValueError(text) when it does not fit."""
    if kind not in SPECS:
        raise ValueError("unknown job kind %r (one of %s)" % (kind, ", ".join(SPECS)))
    spec = dict(spec or {})
    out = {}
    fields = SPECS[kind]["fields"]
    for name, f in fields.items():
        v = spec.get(name)
        if f.get("required") and (v is None or v == "" or v == []):
            raise ValueError("%s needs %s: %s" % (kind, name, f.get("help", "")))
        out[name] = _coerce(name, f, v)
    for name, v in spec.items():
        if name not in fields:
            out[name] = v   # a key the page knows and this module does not: kept, never dropped
    if kind == "look":
        if out["method"] in ("front_from_picture",) and not out.get("pick") and not (out.get("ref") and out.get("prompt") and out.get("stills")):
            raise ValueError("front_from_picture needs ref, prompt and stills (the slug the pick is cached under)")
        if out["method"] == "recolour" and not (out.get("recolour") or {}).get("from"):
            raise ValueError("recolour needs recolour.from: the look to recolour")
    return out


def _check_target(kind, target):
    target = dict(target or {})
    for k in ("kind", "id", "code"):
        target.setdefault(k, "")
    if kind in ("look", "item_icon", "icon_cands", "hero_badge", "hero_title"):
        if not target.get("id"):
            raise ValueError("%s needs a target id" % kind)
        if target.get("kind") and target["kind"] not in KIND_FOLDERS:
            raise ValueError("unknown target kind %r" % target["kind"])
        if kind == "look" and not target.get("code"):
            raise ValueError("a look job needs a target code (the look's CODE, e.g. GOB-E)")
        if kind in ("hero_badge", "hero_title") and target.get("kind", "hero") != "hero":
            raise ValueError("%s is for a hero" % kind)
    return target


# ---------------------------------------------------------------- the plan: what runs

def _asset_env(job):
    env = {"ASSET_JOB_SIDECAR": os.path.join(_job_dir(job["id"]), "result.json"), "ASSET_JOB_ID": job["id"],
           "ASSET_JOB_NAME": _user_folder(job),   # the folder its workflows take in the ComfyUI page's Workflows sidebar
           "LOCK_HELD_COMFY": "1", "COMFY_LOCK_HELD": "1", "PYTHONIOENCODING": "utf-8"}
    spec = job.get("spec") or {}
    model = "dev" if (spec.get("dev") or spec.get("model") == "dev") else "klein"
    env["ART_MODEL"] = model
    if int(spec.get("steps") or 0):
        env["ART_STEPS"] = str(int(spec["steps"]))
    if float(spec.get("guidance") or 0):
        env["ART_GUIDANCE"] = str(float(spec["guidance"]))
    if "turbo" in spec and spec.get("turbo") is not None:
        env["ART_TURBO"] = "1" if spec.get("turbo") else "0"
    return env


def _q(a):
    a = str(a)
    return '"%s"' % a.replace('"', '\\"') if (" " in a or a == "") else a


def _model_argv(spec):
    """The painter flags gen_art reads (also in the ART_* env): --dev, --steps=, --guidance=, --no-turbo."""
    out = []
    if spec.get("dev") or spec.get("model") == "dev":
        out.append("--dev")
    if int(spec.get("steps") or 0):
        out.append("--steps=%d" % int(spec["steps"]))
    if float(spec.get("guidance") or 0):
        out.append("--guidance=%s" % spec["guidance"])
    if spec.get("turbo") is False:
        out.append("--no-turbo")
    return out


def _equiv_py(script, argv):
    return "python tools/%s.py %s" % (script, " ".join(_q(a) for a in argv))


def _runner_from_methods(method, fmt, spec):
    """methods.json's `runner.argv` for a method with its placeholders filled (lane B's convention: `{name}` from the
    target/spec, a trailing `?` marks an item left out when its value is empty, a bare `--flag?` is on when the spec's
    flag is). None when the method has no runner or a required placeholder cannot be filled (the built-in command then)."""
    m = _methods().get(method)
    r = (m or {}).get("runner")
    if not isinstance(r, dict) or not r.get("tool") or not isinstance(r.get("argv"), _LIST):
        return None
    out = []
    for a in r["argv"]:
        a = str(a)
        optional = a.endswith("?")
        if optional:
            a = a[:-1]
        names = re.findall(r"\{([^}]+)\}", a)
        if not names:
            if optional:
                flag = a.lstrip("-").replace("-", "_")
                if spec.get(flag):
                    out.append(a)
            else:
                out.append(a)
            continue
        vals, ok = {}, True
        for n in names:
            v = fmt.get(n, spec.get(n)) if n not in fmt else fmt[n]
            if isinstance(v, _LIST):
                v = ",".join(str(x) for x in v)
            if v is None or v == "" or v is False or (optional and v == 0):
                ok = False
                break
            vals[n] = str(v)
        if not ok:
            if optional:
                continue
            return None
        for n, v in vals.items():
            a = a.replace("{" + n + "}", v)
        out.append(a)
    return {"tool": r["tool"], "call": r.get("call", "process"), "argv": out}


def _plan(job):
    """Everything the worker needs: {mode: asset|steps|launch, lock, tool, call, argv, env, equiv, type, folder, id, steps, launch}."""
    kind, spec, t = job["kind"], job.get("spec") or {}, job.get("target") or {}
    method = job.get("method") or ""
    cid, code = t.get("id", ""), t.get("code", "")
    tf, jp = content_path(t.get("kind", ""), cid) if cid else (None, None)
    folder = os.path.dirname(jp) if jp else ""
    asset_dir = _job_dir(job["id"])
    env = _asset_env(job)
    p = {"mode": "asset", "lock": "comfy", "tool": "", "call": "", "argv": [], "env": env, "equiv": "", "type": tf or "",
         "folder": _rel(folder) if folder else "", "id": cid, "steps": [], "launch": None}
    if kind == "look":
        if method in ("hero_pose5", "hero_fit", "creature_free2", "creature_pose2", "creature_free8", "creature_proc"):
            argv = ["--no-import", "--only", cid, "--variant=" + code]
            if spec.get("skip_qa"):
                argv.append("--skip-qa")
            argv += _model_argv(spec)
            if spec.get("no_video") or method == "creature_proc" and spec.get("no_video") is None:
                if spec.get("no_video"):
                    argv.append("--no-video")
            if int(spec.get("seed") or 0):
                argv.append("--seed=%d" % int(spec["seed"]))
            if spec.get("keys"):
                argv.append("--keys=" + ",".join(spec["keys"]))
            r = _runner_from_methods(method, {"id": cid, "code": code, "folder": p["folder"], "type": tf or "", "seed": int(spec.get("seed") or 0),
                                              "keys": _LIST(spec.get("keys") or [])}, spec)
            if r and r["tool"] == "gen_art" and r.get("call", "process") == "process":
                # the catalogue's order, plus any set flag the catalogue's runner does not list (--keys, --seed, --dev...)
                argv = r["argv"] + [a for a in argv if a not in r["argv"]]
            p.update(tool="gen_art", call="process", argv=argv, equiv=_equiv_py("gen_art", argv))
        elif method == "creature_ctl":
            argv = ["--id=" + cid, "--variant=" + code]
            if spec.get("use_side"):
                argv.append("--use-side=" + str(spec["use_side"]))
            if spec.get("view_cands") and not spec.get("use_view"):
                argv.append("--view-cands=" + str(spec["view_cands"]))
            if spec.get("use_view"):
                argv.append("--use-view=" + str(spec["use_view"]))
            argv += _model_argv(spec)
            if spec.get("seeds") and int(spec["seeds"]) != 3:
                argv.append("--seeds=%d" % int(spec["seeds"]))
            if spec.get("skip_qa"):
                argv.append("--skip-qa")
            if spec.get("stage"):
                argv.append("--stage=" + str(spec["stage"]))
            p.update(tool="gen_ctl", call="main", argv=argv, equiv=_equiv_py("gen_ctl", argv))
        elif method == "front_from_picture":
            slug = str(spec.get("stills") or "")
            if spec.get("pick") not in (None, ""):
                argv = ["--id", cid, "--stills", slug, "--pick", str(spec["pick"])]
            else:
                argv = ["--id", cid, "--stills", slug, "--ref", str(spec.get("ref", "")), "--prompt", str(spec.get("prompt", "")),
                        "--seeds", str(int(spec.get("seeds") or 4))]
                if spec.get("screen") == "blue":
                    argv += ["--screen", "blue"]
                if spec.get("keep"):
                    argv += ["--keep", str(spec["keep"])]
                if spec.get("no_style_ref"):
                    argv.append("--no-style-ref")
                if spec.get("skip_qa"):
                    argv.append("--skip-qa")
            p.update(tool="gen_edit_stills", call="main", argv=argv, equiv=_equiv_py("gen_edit_stills", argv))
        elif method == "recolour":
            rc = spec.get("recolour") or {}
            src_code = str(rc.get("from", ""))
            steps = []
            for suffix in ("sprite", "icon"):
                src = os.path.join(folder, "%s_%s_%s.png" % (cid, suffix, _letter(src_code)))
                dst = os.path.join(folder, "%s_%s_%s.png" % (cid, suffix, _letter(code)))
                a = [PY, os.path.join(TOOLS, "recolour_strip.py"), "--src", _rel(src), "--dst", _rel(dst)]
                if rc.get("ranges"):
                    a += ["--ranges"] + ["%s-%s" % (r[0], r[1]) for r in rc["ranges"] if isinstance(r, (_LIST, tuple)) and len(r) == 2]
                if rc.get("to") is not None:
                    a += ["--to", str(rc["to"])]
                if rc.get("mode"):
                    a += ["--mode", str(rc["mode"])]
                for k, flag in (("sat", "--sat"), ("set_sat", "--set-sat"), ("value", "--value"), ("min_sat", "--min-sat"),
                                ("max_sat", "--max-sat"), ("min_val", "--min-val")):
                    if rc.get(k) is not None:
                        a += [flag, str(rc[k])]
                if suffix == "sprite":
                    a += ["--preview", _rel(os.path.join(REVIEW, "%s_%s_recolour.png" % (cid, _letter(code))))]
                steps.append(a)
            p.update(mode="steps", lock=None, steps=steps, equiv=" && ".join("python " + " ".join(_q(x) for x in s[1:]) for s in steps))
    elif kind == "item_icon":
        argv = ["--no-import", "--only", cid]
        if spec.get("skip_qa"):
            argv.append("--skip-qa")
        argv += _model_argv(spec)
        if int(spec.get("seed") or 0):
            argv.append("--seed=%d" % int(spec["seed"]))
        r = _runner_from_methods("item_icon", {"id": cid, "code": "", "folder": p["folder"], "type": tf or "", "seed": int(spec.get("seed") or 0)}, spec)
        if r and r["tool"] == "gen_art":
            argv = r["argv"] + [a for a in argv if a not in r["argv"]]
        p.update(tool="gen_art", call="process", argv=argv, equiv=_equiv_py("gen_art", argv))
    elif kind == "icon_cands":
        key = str(spec.get("key") or cid)
        icon_job = {"kind": tf or "", "id": cid, "subject": str(spec.get("subject", "")), "set": "_le_" + job["id"]}
        for k in ("ref", "screen", "style", "file"):
            if spec.get(k):
                icon_job[k] = spec[k]
        if icon_job.get("screen") == "green":
            icon_job.pop("screen", None)
        p.update(tool="gen_icon_cands", call="paint", argv=["--only", key, "--seeds", str(int(spec.get("seeds") or 4))] + (["--dev"] if spec.get("dev") else []),
                 key=key, icon_job=icon_job, seeds=int(spec.get("seeds") or 4), dev=bool(spec.get("dev")))
        p["equiv"] = "python tools/gen_icon_cands.py --only %s --seeds %d%s   (JOBS[%r] = %s)" % (
            key, p["seeds"], " --dev" if p["dev"] else "", key, json.dumps(icon_job, ensure_ascii=False))
    elif kind == "hero_badge":
        argv = ["--id", cid, "--seeds", str(int(spec.get("seeds") or 4))]
        if spec.get("prompt"):
            argv += ["--prompt", str(spec["prompt"])]
        if int(spec.get("first_seed") or 0):
            argv += ["--first-seed", str(int(spec["first_seed"]))]
        if float(spec.get("head_width") or 0) > 0:
            argv += ["--head-width", str(spec["head_width"])]
        if spec.get("top_pad") not in (None, "", 0.03):
            argv += ["--top-pad", str(spec["top_pad"])]
        if spec.get("skip_qa"):
            argv.append("--skip-qa")
        p.update(tool="gen_badge_cands", call="main", argv=argv, equiv=_equiv_py("gen_badge_cands", argv))
    elif kind == "hero_title":
        seeds, first = int(spec.get("seeds") or 4), int(spec.get("first_seed") if spec.get("first_seed") is not None else 11)
        p.update(tool="gen_title_heroes", call="paint", argv=["--only", cid, "--seeds=%d" % seeds, "--first-seed=%d" % first],
                 hid=cid, seeds=seeds, first=first)
        p["equiv"] = _equiv_py("gen_title_heroes", p["argv"])
    elif kind in ("driver_pose", "driver_depth", "ref_probe", "ref_render"):
        p.update(mode="steps", lock=None)
        bl = blender_path() or "$BLENDER"
        src = str(spec.get("src", ""))
        if kind == "driver_pose":
            out = os.path.join(DRIVERS, str(spec.get("name", "")))
            kv = [("glb" if src.lower().endswith((".glb", ".gltf")) else "fbx") + "=" + src, "out=" + _rel(out), "frames=%d" % int(spec.get("frames") or 24)]
            if not spec.get("loop", True):
                kv.append("loop=0")
            for k in ("pitch", "start", "end", "arms", "body", "fwd", "rig", "rigmap"):
                v = spec.get(k)
                if v not in (None, "", 25) or (k == "pitch" and v not in (None, "", 25)):
                    if k == "pitch" and int(v) == 25:
                        continue
                    kv.append("%s=%s" % (k, v))
            steps = [[bl, "-b", "--python", os.path.join(TOOLS, "pose_driver.py"), "--"] + kv,
                     [PY, os.path.join(TOOLS, "pose_driver.py"), "draw", _rel(out)]]
            p["steps"] = steps
            p["equiv"] = '"$BLENDER" -b --python tools/pose_driver.py -- %s && python tools/pose_driver.py draw %s' % (" ".join(kv), _rel(out))
        elif kind == "driver_depth":
            out = os.path.join(DRIVERS, str(spec.get("name", "")))
            kv = ["src=" + src, "out=" + _rel(out), "mode=" + str(spec.get("mode") or "cycle")]
            if spec.get("action"):
                kv.append("action=" + str(spec["action"]))
            for k, dflt in (("frames", 12), ("cycles", 2), ("total", 25), ("start", ""), ("end", ""), ("depth", "tight"), ("amp", 1.0),
                            ("amp_bones", ""), ("pitch", 25), ("views", ""), ("forward", ""), ("screen", ""), ("albedo", "")):
                v = spec.get(k)
                if v not in (None, "") and v != dflt:
                    kv.append("%s=%s" % (k, v))
            if spec.get("inplace") is False:
                kv.append("inplace=0")
            p["steps"] = [[bl, "-b", "--python", os.path.join(TOOLS, "blender_depth_drivers.py"), "--"] + kv]
            p["equiv"] = '"$BLENDER" -b --python tools/blender_depth_drivers.py -- ' + " ".join(kv)
        else:
            slug_dir = os.path.dirname(src) if os.path.dirname(src) else os.path.join(UPLOADS, "3d", os.path.splitext(os.path.basename(src))[0])
            if not os.path.isabs(slug_dir):
                # a repo-relative src (tools/dl/uploads/3d/<slug>/<file>): resolve against the repo, not the process's
                # working directory (the selftest runs from tools/level_editor and doubled the path)
                slug_dir = os.path.join(_root, slug_dir)
            mode = "probe" if kind == "ref_probe" else str(spec.get("mode") or "views")
            kv = ["src=" + src, "out=" + _rel(slug_dir), "mode=" + mode]
            if kind == "ref_render":
                for k, dflt in (("forward", ""), ("action", ""), ("at", ""), ("frame", ""), ("pitch", 25), ("icon_yaw", 35), ("icon_pitch", 20),
                                ("size", 1024), ("screen", ""), ("albedo", ""), ("scale", "auto")):
                    v = spec.get(k)
                    if v not in (None, "") and v != dflt:
                        kv.append("%s=%s" % (k, v))
            p["steps"] = [[bl, "-b", "--python", os.path.join(TOOLS, "blender_ref.py"), "--"] + kv]
            p["equiv"] = '"$BLENDER" -b --python tools/blender_ref.py -- ' + " ".join(kv)
    elif kind in ("register", "import"):
        targets = [str(x).strip().strip("/") for x in (spec.get("targets") or []) if str(x).strip()]
        only = ",".join(targets)
        g = [GODOT, "--headless", "--path", GAME]
        steps = []
        if kind == "register" or spec.get("placeholders"):
            steps.append(g + ["--script", "res://tools/gen_placeholders.gd", "--", "only=" + only])
        steps += [g + ["--import"], [PY, os.path.join(TOOLS, "lossy_imports.py")], g + ["--import"],
                  g + ["--script", "res://tools/import_json.gd", "--", "only=" + only]]
        p.update(mode="steps", lock="godot", steps=steps, keep_save=True)
        p["equiv"] = " && ".join(("bash tools/godot.sh " + " ".join(_q(x) for x in s[1:])) if s[0] == GODOT else ("python " + _rel(s[1])) for s in steps)
    elif kind == "launch":
        launch = {"map": str(spec.get("map") or "red_canyon"), "arena": True, "spawn": False, "count": int(spec.get("count") or 3)}
        for k in ("character", "look", "spawn_enemy", "variant"):
            if spec.get(k):
                launch[k] = str(spec[k])
        cmd = [GODOT, "--path", GAME, "res://game/Game.tscn"]
        p.update(mode="launch", lock="godot", steps=[cmd], launch=launch, equiv="bash tools/godot.sh --path game res://game/Game.tscn   (user://debug_launch.json = %s)" % json.dumps(launch))
    elif kind == "install":
        src = _find(str(spec.get("source_job", "")))
        choice = str(spec.get("choice", ""))
        if src is None:
            p.update(mode="steps", lock=None, steps=[], equiv="", error="the source job %r is gone" % spec.get("source_job"))
        elif src["kind"] == "icon_cands":
            sp = src.get("plan") or {}
            p.update(tool="gen_icon_cands", call="pick", lock=None, argv=["--pick", "%s=%s" % (sp.get("key", cid), choice)], key=sp.get("key", cid),
                     icon_job=sp.get("icon_job") or {}, choice=choice, id=src["target"].get("id", ""), type=sp.get("type", ""))
            p["equiv"] = "python tools/gen_icon_cands.py --pick %s=%s   (JOBS[%r] = %s)" % (p["key"], choice, p["key"], json.dumps(p["icon_job"], ensure_ascii=False))
        elif src["kind"] == "hero_badge":
            hid = src["target"].get("id", "")
            argv = ["--id", hid, "--pick", choice]
            if float(spec.get("head_width") or 0) > 0:
                argv += ["--head-width", str(spec["head_width"])]
            if spec.get("top_pad") not in (None, "", 0.03):
                argv += ["--top-pad", str(spec["top_pad"])]
            p.update(tool="gen_badge_cands", call="main", lock=None, argv=argv, equiv=_equiv_py("gen_badge_cands", argv), id=hid, type="characters")
        elif src["kind"] == "hero_title":
            hid = src["target"].get("id", "")
            p.update(tool="gen_title_heroes", call="pick", lock=None, argv=["--pick", "%s=%s" % (hid, choice)], hid=hid, choice=choice, id=hid, type="characters",
                     equiv="python tools/gen_title_heroes.py --pick %s=%s" % (hid, choice))
        else:
            p.update(mode="steps", lock=None, steps=[], error="nothing to install from a %s job" % src["kind"])
    return p


def _derive(job):
    """cmd, equiv, lane, eta, cache_keys, the stage list and the job folder's job.json, from kind + method + target + spec."""
    kind, spec, t = job["kind"], job.get("spec") or {}, job.get("target") or {}
    method = job.get("method") or (spec.get("method") if kind == "look" else kind)
    job["method"] = method
    job["lane"] = "local" if (kind == "look" and method == "recolour") else SPECS[kind]["lane"]
    doc = content_doc(t.get("kind", ""), t.get("id", "")) if t.get("id") else None
    plan = _plan(job)
    job["plan"] = plan
    if plan["mode"] == "asset":
        job["cmd"] = [PY, "-u", os.path.join(TOOLS, "asset_job.py"), _rel(_job_dir(job["id"]))]
    else:
        job["cmd"] = plan["steps"][0] if plan["steps"] else []
    job["equiv"] = plan.get("equiv", "")
    job["cache_keys"] = cache_keys(method, spec, t, doc) if kind == "look" else (
        {"stills": [t.get("id", "") + "_icon2"], "clips": []} if kind == "item_icon" else
        {"stills": ["%s_portrait_c%d" % (t.get("id", ""), k) for k in range(int(spec.get("seeds") or 4))], "clips": []} if kind == "hero_badge" else
        {"stills": [], "clips": []})
    stages = expected_stages(method, spec, t, doc, job.get("phase", 1)) if kind == "look" else []
    if kind == "item_icon":
        stages = [{"name": "icon", "key": t.get("id", "") + "_icon2", "type": "still"}, {"name": "finish", "key": "", "type": "pack"}]
    elif kind in ("icon_cands", "hero_badge", "hero_title"):
        n = int(spec.get("seeds") or 4)
        stages = [{"name": "c%d" % k, "key": "", "type": "still"} for k in range(n)] + [{"name": "review", "key": "", "type": "pack"}]
        if kind == "hero_badge":
            for k, s in enumerate(stages[:n]):
                s["key"] = "%s_portrait_c%d" % (t.get("id", ""), k)
    elif plan["mode"] == "steps":
        stages = [{"name": _step_name(s), "key": "", "type": "step"} for s in plan["steps"]]
    elif plan["mode"] == "launch":
        stages = [{"name": "the game window", "key": "", "type": "step"}]
    prog = job.setdefault("progress", {})
    done_before = {s["name"]: s for s in prog.get("stages", []) if s.get("state") == "done"}
    for s in stages:
        s["state"] = "pending"
        s["secs"] = None
    prog.update(done=0, total=len(stages), stage="", stages=stages, stalled=False)
    prog.setdefault("last_output", None)
    job["eta_s"] = _eta(job)
    if not job.get("title"):
        job["title"] = _title(job)
    job["log_file"] = _rel(os.path.join(_job_dir(job["id"]), "log.txt"))
    _write_job_json(job)
    return job


def _step_name(argv):
    if not argv:
        return "step"
    a = [str(x) for x in argv]
    if a[0] == GODOT:
        if "--import" in a:
            return "godot --import"
        for x in a:
            if x.startswith("res://"):
                return os.path.basename(x)
        return "godot"
    if a[0] == PY and len(a) > 1:
        return os.path.basename(a[1]) + (" " + a[2] if len(a) > 2 and not a[2].startswith("-") else "")
    return os.path.basename(a[0]) + (" " + os.path.basename(a[3]) if len(a) > 3 else "")


def _write_job_json(job):
    d = _job_dir(job["id"])
    os.makedirs(d, exist_ok=True)
    plan = job.get("plan") or {}
    payload = {"id": job["id"], "kind": job["kind"], "method": job.get("method"), "target": job.get("target"), "spec": job.get("spec"),
               "phase": job.get("phase", 1), "attempt": job.get("attempt", 1), "title": job.get("title", "")}
    payload.update({k: v for k, v in plan.items() if k not in ("launch",) or v is not None})
    payload["equiv"] = job.get("equiv", "")
    with open(os.path.join(d, "job.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(payload, f, indent=1, ensure_ascii=False)


# ---------------------------------------------------------------- public API

_queue_lock = None    # the `jobs` lock this process holds while it runs the queue (claim_queue)
_readonly = None      # the holder's record when another editor runs it: this process shows the queue, changes nothing
_disk_sig = None      # (mtime, size) of queue.json at the last read-only load


def claim_queue(who="level_editor"):
    """Become the one process that runs the job queue: the `jobs` lock (tools/dl/locks/jobs.lock), held while the
    server lives. A second Level Editor started while the first runs finds it held by a live process and runs
    READ-ONLY: it shows the queue as the file changes and refuses every change, and it neither recovers nor runs jobs.
    (2026-10-11: two level_editor.cmd windows shared one queue.json, each with its own picture of it, each writing the
    whole file; and recover() in a second server kills the first one's running job.) None when claimed, else the record."""
    global _queue_lock, _readonly
    if _queue_lock is not None:
        return None
    lk = locks.acquire("jobs", who=who, note="the Level Editor that runs the job queue", wait=False, log=lambda m: None)
    if lk is None:
        _readonly = locks.status("jobs") or {"who": "another Level Editor"}
        return _readonly
    _queue_lock, _readonly = lk, None
    return None


def is_readonly():
    return _readonly is not None


def _writable():
    """Every change to the queue starts here: a read-only editor refuses with the holder named."""
    if _readonly is None:
        return
    o = _readonly
    since = time.strftime("%H:%M", time.localtime(float(o.get("since") or 0))) if o.get("since") else "?"
    raise ValueError("another Level Editor runs the job queue (%s, pid %s, since %s): queue it from that page, or close it and "
                     "restart this one; this page only shows the queue" % (o.get("who") or "another Level Editor", o.get("pid") or "?", since))


def _sync_from_disk():
    """Read-only: the queue as the other editor last wrote it, loaded again whenever queue.json changed."""
    global _disk_sig
    if _readonly is None:
        return
    try:
        st = os.stat(QUEUE_FILE)
        sig = (st.st_mtime, st.st_size)
    except OSError:
        return
    if sig != _disk_sig:
        _disk_sig = sig
        _load()


def init(hooks, root=None, claim=True):
    """server.main(): the hooks dict, the queue loaded, the queue claimed (or this process read-only), recover() run by
    the claimant. Starts no thread. `claim=False` (a tool, a test) neither claims nor recovers."""
    global _hooks, _root
    _hooks = hooks
    if root:
        _root = root
    _load()
    if claim:
        if claim_queue() is None:
            recover()
    return _state["rev"]


def start_workers():
    """The three lane threads (daemon). Only server.main() calls this; a second call is a no-op; a read-only editor
    (another one holds the queue) starts none."""
    if _workers:
        return _workers
    if _readonly is not None:
        return []
    _stop.clear()
    for lane in LANES:
        th = threading.Thread(target=_worker, args=(lane,), name="jobs-" + lane, daemon=True)
        th.start()
        _workers.append(th)
    return _workers


def stop(timeout=3.0):
    global _queue_lock
    _stop.set()
    for th in _LIST(_workers):
        th.join(timeout)
    _workers.clear()
    if _queue_lock is not None:
        try:
            _queue_lock.release()
        except Exception:
            pass
        _queue_lock = None


def list(since_rev=None):   # noqa: A001 (the contract's name)
    with _lock:
        _sync_from_disk()
        if since_rev is not None and int(since_rev) == _state["rev"]:
            return {"rev": _state["rev"], "unchanged": True}
        return {"rev": _state["rev"], "jobs": [_public(j, LOG_TAIL_SHORT) for j in _state["jobs"]]}


def get(job_id):
    with _lock:
        _sync_from_disk()
        j = _find(job_id)
        return _public(j, LOG_TAIL_FULL, full=True) if j else None


def _public(job, tail_n, full=False):
    out = {k: v for k, v in job.items() if k not in ("plan",)}
    out["plan"] = {k: v for k, v in (job.get("plan") or {}).items() if k != "env"}
    live = _live.get(job["id"])
    if live is not None:
        out["log_tail"] = [x for x in live.tail][-tail_n:]
    elif full or job.get("state") in ("running", "waiting", "failed", "interrupted"):
        out["log_tail"] = _tail_from_file(job, tail_n)
    else:
        out["log_tail"] = []
    return out


def _tail_from_file(job, n):
    p = os.path.join(_job_dir(job["id"]), "log.txt")
    try:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
        return lines[-n:]
    except OSError:
        return []


CREATURE_STILL_METHODS = ("creature_free2", "creature_pose2", "creature_free8", "creature_proc")
# the art words a new look inherits from its creature when its recipe leaves them out, so the prompt is in the look's
# own recipe where Garry can read and change it (lead, after the Armadillo's ARM-A came out identical to ARM-0)
INHERITED_WORDS = ("art_prompt", "motion", "dead_hint", "back_hint", "anim_negative", "view_hints", "screen")


def _painter_of(spec):
    """The painter a look job runs with (MODEL_FIELDS -> the ART_* env), as its recipe records it under `painter`: the
    model, the passes (0 = that model's own default) and, for Flux.2 dev, the guidance and whether Turbo is on. The
    look grid and the recipe editor show it ("painted with ..."); Duplicate and Re-roll prefill the job form from it;
    gen_art reads it on a hand run that names no painter (Garry: "'Looks' should contain a lot of these settings")."""
    model = "dev" if (spec.get("dev") or spec.get("model") == "dev") else "klein"
    out = {"model": model, "steps": int(spec.get("steps") or 0)}
    if model == "dev":
        out["guidance"] = float(spec.get("guidance") or 0)
        out["turbo"] = True if spec.get("turbo") is None else bool(spec.get("turbo"))
    return out


def _seed_recipe(target, spec):
    """What every look job writes into its recipe before it runs. Every painting method records its `painter`
    (_painter_of; a recolour paints nothing). A creature look painted by gen_art also gets its own `stills` slug when
    the key is absent (else the stills are CACHED under the creature's own keys and every look comes out as the base;
    an explicit "" keeps the creature's own paintings: Duplicate's "reuse the paintings") and a copy of the base's art
    words when it names none."""
    if not target.get("code") or spec.get("method") == "recolour":
        return
    recipe = spec.get("recipe")
    if not isinstance(recipe, dict):
        recipe = {}
        spec["recipe"] = recipe
    recipe["painter"] = _painter_of(spec)
    if spec.get("method") not in CREATURE_STILL_METHODS:
        return
    if "stills" not in recipe or recipe.get("stills") is None:
        recipe["stills"] = _letter(target["code"])
    base = content_doc(target.get("kind"), target.get("id")) or {}
    for k in INHERITED_WORDS:
        if not recipe.get(k) and base.get(k) not in (None, "", {}):
            recipe[k] = base[k]


def enqueue(kind, target, spec, title=None):
    _writable()
    spec = validate_spec(kind, spec)
    target = _check_target(kind, target)
    if kind == "look":
        _seed_recipe(target, spec)
    job = {"id": _new_id(), "kind": kind, "method": spec.get("method") if kind == "look" else kind, "lane": SPECS[kind]["lane"],
           "state": "queued", "title": title or "", "target": target, "spec": spec, "phase": 1, "attempt": 1, "created": _now(),
           "started": None, "ended": None, "pid": None, "cmd": [], "equiv": "",
           "progress": {"done": 0, "total": 0, "stage": "", "stages": [], "last_output": None, "stalled": False},
           "eta_s": 0, "log_file": "", "outputs": [], "choices": [], "cache_keys": {}, "error": "", "qa_online": None,
           "written": None, "lock_waits": {}, "front": False}
    with _lock:
        _derive(job)
        if kind == "look" and spec.get("recipe") is not None and _hook("set_recipe"):
            try:
                _hook("set_recipe")(target["kind"], target["id"], target["code"], spec.get("recipe") or {}, spec.get("note") or None)
            except Exception as e:
                job["error"] = "the recipe could not be written: %s" % e
        _state["jobs"].append(job)
        _save()
        return _public(job, LOG_TAIL_SHORT)


def edit(job_id, spec=None, title=None):
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise ValueError("no job %s" % job_id)
        if job["state"] == "running":
            raise ValueError("job %s is running: cancel it first" % job_id)
        if spec is not None:
            merged = dict(job.get("spec") or {})
            merged.update(spec)
            job["spec"] = validate_spec(job["kind"], merged)
            if job["kind"] == "look":
                _seed_recipe(job.get("target") or {}, job["spec"])
            if job["kind"] == "look":
                job["method"] = job["spec"].get("method")
        if title is not None:
            job["title"] = str(title)
        if job["state"] == "waiting":
            job["state"], job["phase"] = "queued", 1
            job["choices"] = []
            for k in ("use_side", "use_view", "pick"):
                if k in job["spec"]:
                    job["spec"][k] = ""
        job["front"] = False
        _derive(job)
        if job["kind"] == "look" and spec is not None and "recipe" in spec and _hook("set_recipe"):
            t = job["target"]
            try:
                _hook("set_recipe")(t["kind"], t["id"], t["code"], job["spec"].get("recipe") or {}, job["spec"].get("note") or None)
            except Exception as e:
                job["error"] = "the recipe could not be written: %s" % e
        _save()
        return _public(job, LOG_TAIL_SHORT)


def cancel(job_id):
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise ValueError("no job %s" % job_id)
        if job["state"] in ("queued", "waiting"):
            job["state"], job["ended"] = "cancelled", _now()
            _save()
            return _public(job, LOG_TAIL_SHORT)
        if job["state"] != "running":
            return _public(job, LOG_TAIL_SHORT)
        live = _live.get(job_id)
        pid = job.get("pid")
    if live is not None:
        live.cancelled = True
    if pid:
        _kill_tree(pid)
    if job.get("lane") == "comfy" and pid:
        _comfy_interrupt()
    with _lock:
        if live is None:   # no worker (a recovered record): finish it here
            job["state"], job["ended"] = "cancelled", _now()
            _save()
        if job.get("kind") == "launch":
            job["progress"]["stage"] = "the game window was closed"
            _save()
        return _public(job, LOG_TAIL_SHORT)


def requeue(job_id, reroll=None):
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise ValueError("no job %s" % job_id)
        if job["state"] in ("running", "queued"):
            raise ValueError("job %s is %s" % (job_id, job["state"]))
        spec = job.setdefault("spec", {})
        rr = reroll or {}
        stamp = time.strftime("%Y%m%d-%H%M%S")
        moved = []
        gen_art_tool = (job.get("plan") or {}).get("tool") in ("gen_art", "") and job.get("method") != "creature_ctl"
        for key in rr.get("stills") or []:
            for ext in (".png", ".json"):
                src = os.path.join(RAW, key + ext)
                if os.path.isfile(src):
                    shutil.copy2(src, os.path.join(RAW, "%s_old%s%s" % (key, stamp, ext)))
                    if not gen_art_tool:
                        os.remove(src)   # gen_ctl cannot be told --keys: the painting is moved away so it paints again
                    moved.append(_rel(os.path.join(RAW, "%s_old%s%s" % (key, stamp, ext))))
            if gen_art_tool:
                keys = [k for k in (spec.get("keys") or []) if k]
                if key not in keys:
                    keys.append(key)
                spec["keys"] = keys
        for key in rr.get("clips") or []:
            src = os.path.join(ANIM, key)
            if os.path.isdir(src):
                dst = "%s_old%s" % (src, stamp)
                shutil.move(src, dst)
                moved.append(_rel(dst))
        if rr.get("seed") is not None:
            spec["seed"] = int(rr["seed"])
        if rr.get("clips") and job["kind"] == "look":
            recipe = dict(spec.get("recipe") or {})
            if job.get("method") == "creature_ctl":
                ws = dict(recipe.get("walk_seeds") or {})
                for key in rr["clips"]:
                    if "_ctl_" in key:
                        v = key.rsplit("_", 1)[-1]
                        ws[v] = int(ws.get(v, 0)) + 1
                recipe["walk_seeds"] = ws
            else:
                recipe["anim_seed"] = int(recipe.get("anim_seed", 0)) + 1
            spec["recipe"] = recipe
            if _hook("set_recipe"):
                t = job["target"]
                try:
                    _hook("set_recipe")(t["kind"], t["id"], t["code"], recipe, spec.get("note") or None)
                except Exception as e:
                    job["error"] = "the recipe could not be written: %s" % e
        job["attempt"] = int(job.get("attempt", 1)) + 1
        job["state"], job["phase"] = "queued", 1
        for k in ("started", "ended", "pid"):
            job[k] = None
        job["error"] = job.get("error", "") if "could not be written" in job.get("error", "") else ""
        job["outputs"], job["choices"], job["written"], job["lock_waits"] = [], [], None, {}
        job["front"] = False
        if moved:
            job["reroll"] = {"moved": moved, "stamp": stamp}
        if job["method"] == "creature_ctl":
            # a side already picked stays picked (the cache holds <key>_side.png); the views start again from there
            pass
        _derive(job)
        _save()
        return _public(job, LOG_TAIL_SHORT)


def pick(job_id, choice):
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise ValueError("no job %s" % job_id)
        if job["state"] != "waiting":
            raise ValueError("job %s is not waiting for a pick" % job_id)
        spec = job.setdefault("spec", {})
        choice = str(choice)
        marker = (job.get("waiting_for") or "")
        if job["method"] == "creature_ctl":
            if marker == "view" or ":" in choice:
                spec["use_view"] = choice
                spec["view_cands"] = ""
            else:
                spec["use_side"] = choice if choice.startswith("k") else "k" + choice
        elif job["method"] == "front_from_picture":
            spec["pick"] = choice.lstrip("c")
        else:
            spec["choice"] = choice
        job["picked"] = choice
        job["phase"] = int(job.get("phase", 1)) + 1
        job["state"], job["front"] = "queued", True
        job["choices"] = []
        job["ended"], job["pid"] = None, None
        _derive(job)
        _save()
        return _public(job, LOG_TAIL_SHORT)


def install(job_id, choice, options=None):
    _writable()
    with _lock:
        src = _find(job_id)
        if src is None:
            raise ValueError("no job %s" % job_id)
        if src["kind"] not in ("icon_cands", "hero_badge", "hero_title"):
            raise ValueError("nothing to install from a %s job" % src["kind"])
        if src["state"] != "done":
            raise ValueError("job %s is %s: its candidates are not ready" % (job_id, src["state"]))
    spec = {"source_job": job_id, "choice": str(choice)}
    for k in ("head_width", "top_pad"):
        if options and options.get(k) is not None:
            spec[k] = options[k]
    return enqueue("install", dict(src.get("target") or {}), spec, title="install %s · %s #%s" % (src.get("title", ""), src["kind"], choice))


def move(job_id, delta):
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise ValueError("no job %s" % job_id)
        if job["state"] != "queued":
            raise ValueError("only a queued job moves")
        jobs = _state["jobs"]
        peers = [j for j in jobs if j["state"] == "queued" and j.get("lane") == job.get("lane")]
        i = peers.index(job)
        k = max(0, min(len(peers) - 1, i + int(delta)))
        if k != i:
            a, b = jobs.index(job), jobs.index(peers[k])
            jobs[a], jobs[b] = jobs[b], jobs[a]
        _save()
        return _public(job, LOG_TAIL_SHORT)


def delete(job_id):
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            return False
        if job["state"] == "running":
            raise ValueError("job %s is running: cancel it first" % job_id)
        _state["jobs"].remove(job)
        _save()
    shutil.rmtree(_job_dir(job_id), ignore_errors=True)
    return True


def merge(job_id, redump=False):
    """Garry's "Merge again" / "Re-dump this file (changes its layout)" on a finished job whose landing could not be
    written line by line (`written.layout` "unmerged"; lane V's card): the post phase's merge run again through the
    hooks, or, with `redump`, through hooks.redump_merge, the explicit whole-file re-dump (never silent). Returns the
    public record; None when there is no such job."""
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            return None
        if job["state"] == "running":
            raise ValueError("job %s is running" % job_id)
        kind, t = job["kind"], dict(job.get("target") or {})
        res = _result(job) or {}
    if redump:
        entry = res.get("entry") or {}
        if kind != "look" or not entry:
            raise ValueError("nothing to re-dump: the job has no look entry in result.json")
        h = _hook("redump_merge")
        if not h:
            raise ValueError("no redump hook in this server")
        e = dict(entry)
        e["fresh"] = True
        r = h(t["kind"], t["id"], t["code"], e) or {}
        written = _written(t, r, ["variants"])
        error = "" if r.get("ok") else str(r.get("error") or "the file could not be re-dumped")
    else:
        written, error = _post(job)
    with _lock:
        if written is not None:
            job["written"] = written
        job["error"] = error or ""
        job["outputs"] = _harvest(job)
        _save()
        out = _public(job, 80)
    if written and written.get("layout") != "unmerged" and not error:
        _after_done(job)
    return out


def status():
    with _lock:
        _sync_from_disk()
        counts = {s: sum(1 for j in _state["jobs"] if j["state"] == s) for s in ("queued", "running", "waiting")}
        lanes = dict(_lane_current)
    ro = None
    if _readonly is not None:
        ro = {k: _readonly.get(k) for k in ("who", "pid", "since", "host") if k in _readonly}
    return {"queued": counts["queued"], "running": counts["running"], "waiting": counts["waiting"], "lanes": lanes,
            "locks": locks.status_all(), "blender": blender_path(), "qa_online": _qa_cache["v"], "rev": _state["rev"],
            "workers": len(_workers), "readonly": ro}


def reclaim_stale_locks():
    """Locks whose owner.json names a dead pid are reclaimed (locks.py's rule); one without owner.json is left alone."""
    out = []
    for name in locks.NAMES:
        try:
            if locks._reclaim_if_stale(name, _log):
                out.append(name)
        except Exception:
            pass
    return out


def recover():
    """At the server's start: a job that was running when the server stopped is interrupted (its process tree killed if
    still alive), a leftover launch file is deleted, a pending PC-save keep is restored, stale locks are reclaimed."""
    changed = []
    with _lock:
        for job in _state["jobs"]:
            if job["state"] == "running":
                pid = job.get("pid")
                if pid and locks.pid_alive(pid):
                    _kill_tree(pid)
                job["state"], job["ended"] = "interrupted", _now()
                job["error"] = job.get("error") or "the editor server stopped while this ran"
                job["pid"] = None
                changed.append(job["id"])
                if job["kind"] == "launch" and os.path.isfile(LAUNCH_FILE):
                    try:
                        os.remove(LAUNCH_FILE)
                    except OSError:
                        pass
        for l in LANES:
            _lane_current[l] = None
        if changed:
            _save()
    try:
        if os.path.isfile(locks.RESTORE_PENDING):
            locks.restore_save()
    except Exception:
        pass
    reclaim_stale_locks()
    return changed


# ---------------------------------------------------------------- workers

def _worker(lane):
    while not _stop.is_set():
        job = _take_next(lane)
        if job is None:
            _stop.wait(1.0)
            continue
        try:
            _run(job)
        except Exception as e:  # never let a lane die
            import traceback
            traceback.print_exc()
            with _lock:
                if job["state"] == "running":
                    _finish(job, "failed", error="%s: %s" % (type(e).__name__, e))
        finally:
            with _lock:
                _lane_current[lane] = None


def _take_next(lane):
    with _lock:
        cands = [j for j in _state["jobs"] if j["state"] == "queued" and j.get("lane") == lane]
        if not cands:
            return None
        front = [j for j in cands if j.get("front")]
        job = (front or cands)[0]
        if job["kind"] == "import":
            # consecutive queued imports become one with the union of their targets (critique 18)
            others = [j for j in cands if j is not job and j["kind"] == "import"]
            if others:
                targets = [str(x) for x in (job["spec"].get("targets") or [])]
                for o in others:
                    for t in o["spec"].get("targets") or []:
                        if str(t) not in targets:
                            targets.append(str(t))
                    o["state"], o["ended"], o["merged_into"] = "done", _now(), job["id"]
                    o["title"] = (o.get("title") or "import") + " (merged into %s)" % job["id"]
                job["spec"]["targets"] = targets
                _derive(job)
        job["state"], job["started"], job["front"] = "running", _now(), False
        job["ended"], job["error"] = None, "" if "could not be written" not in job.get("error", "") else job["error"]
        job["progress"]["stalled"] = False
        _lane_current[lane] = job["id"]
        _save()
        return job


def _finish(job, state, error="", save=True):
    job["state"], job["ended"] = state, _now()
    if error:
        job["error"] = error
    job["pid"] = None
    job["lock_waits"] = {}
    if state == "done":
        for s in job["progress"].get("stages", []):
            if s.get("state") == "pending":
                s["state"] = "done"
        job["progress"]["done"] = len(job["progress"].get("stages", []))
        job["progress"]["stage"] = "done"
    elif state in ("failed", "cancelled", "interrupted") and job.get("kind") != "launch":
        # what a stopped job made before it stopped (its workflows above all: the graph that failed is the one to open)
        try:
            job["outputs"] = _harvest(job)
        except Exception:
            pass
    if save:
        _save()


def _acquire(job, live, name):
    """The lane's lock, saying who holds it meanwhile (lock_waits); None when the job was cancelled while waiting."""
    said = None
    while not _stop.is_set():
        if live.cancelled:
            return None
        lk = locks.acquire(name, who="level_editor", job=job["id"], wait=False, log=_log)
        if lk is not None:
            with _lock:
                job["lock_waits"] = {}
                job["progress"]["stage"] = ""
            return lk
        s = locks.status(name) or {}
        who = "%s%s since %s" % (s.get("who", "?"), (" / " + s["job"]) if s.get("job") else "", time.strftime("%H:%M", time.localtime(s.get("since", time.time()))))
        with _lock:
            job["lock_waits"] = {name: who}
            job["progress"]["stage"] = "waiting for the %s lock (%s)" % (name, who)
            if who != said:
                said = who
                _save()
        _stop.wait(2.0)
    return None


def _run(job):
    live = Live(job)
    _live[job["id"]] = live
    plan = job.get("plan") or _plan(job)
    d = _job_dir(job["id"])
    os.makedirs(d, exist_ok=True)
    live.logf = open(os.path.join(d, "log.txt"), "a", encoding="utf-8", newline="\n")
    try:
        live.logf.write("--- %s attempt %d phase %d: %s\n" % (_now(), job.get("attempt", 1), job.get("phase", 1), job.get("equiv", "")))
        live.logf.flush()
        if plan.get("error"):
            with _lock:
                _finish(job, "failed", error=plan["error"])
            return
        if plan["mode"] == "steps" and job["kind"] in ("driver_pose", "driver_depth", "ref_probe", "ref_render"):
            msg = _blender_ready(job["kind"], plan)
            if msg:
                live.logf.write(msg + "\n")
                with _lock:
                    _finish(job, "failed", error=msg)
                return
        lk = None
        if plan.get("lock"):
            lk = _acquire(job, live, plan["lock"])
            if lk is None:
                with _lock:
                    _finish(job, "cancelled")
                return
            live.lock = lk
        try:
            if job["lane"] == "comfy":
                with _lock:
                    job["qa_online"] = qa_online()
            if plan["mode"] == "launch":
                rc = _run_launch(job, plan, live)
            elif plan["mode"] == "steps":
                rc = _run_steps(job, plan, live)
            else:
                rc = _spawn(job, live, job["cmd"], _asset_env(job))
            _after_exit(job, rc, live)
        finally:
            if lk is not None:
                lk.release()
    finally:
        try:
            live.logf.close()
        except Exception:
            pass
        _live.pop(job["id"], None)
        with _lock:
            _save()


def _blender_ready(kind, plan):
    bl = blender_path()
    if not bl:
        return "Blender not found: set BLENDER or install it under %LOCALAPPDATA%/Programs/blender-*/ (the page's status line shows the path)"
    script = {"driver_pose": "pose_driver.py", "driver_depth": "blender_depth_drivers.py", "ref_probe": "blender_ref.py", "ref_render": "blender_ref.py"}[kind]
    if not os.path.isfile(os.path.join(TOOLS, script)):
        if kind == "driver_depth":
            return "ask Claude for a depth driver: tools/blender_depth_drivers.py is not in this checkout yet"
        return "ask Claude: tools/%s is not in this checkout yet" % script
    return ""


def _spawn(job, live, cmd, env_extra=None, cwd=None):
    """Run one command, its output to log.txt and the progress parser; returns the exit code (-1 when it could not start)."""
    env = dict(os.environ)
    env.update(env_extra or {})
    env.setdefault("PYTHONIOENCODING", "utf-8")
    flags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    live.logf.write("$ %s\n" % " ".join(_q(x) for x in cmd))
    live.logf.flush()
    try:
        proc = subprocess.Popen([str(x) for x in cmd], cwd=cwd or _root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                encoding="utf-8", errors="replace", env=env, creationflags=flags)
    except OSError as e:
        live.logf.write("could not start: %s\n" % e)
        live.tail.append("could not start: %s" % e)
        return -1
    live.proc = proc
    with _lock:
        job["pid"] = proc.pid
        job["progress"]["last_output"] = _now()
        _save()
    live.key_to_stage = _stage_index(job)
    last_line_t = time.time()
    reader = threading.Thread(target=_read, args=(job, live, proc), daemon=True)
    reader.start()
    last_cache = 0.0
    last_beat = time.time()
    flows_seen = None
    while proc.poll() is None:
        now = time.time()
        if now - last_cache >= CACHE_CHECK_SECONDS:
            last_cache = now
            _check_caches(job, live)
            # the card shows every workflow (and every still and clip) as it lands, not only at the end: a harvest
            # whenever the job's workflows folder changes (pass 66 follow-up: "running a Mummy job I don't see a link")
            sig = _workflows_sig(job)
            if sig != flows_seen:
                flows_seen = sig
                with _lock:
                    job["outputs"] = _harvest(job)
                    live.last_save = live.last_save or time.time()
        if live.lock is not None and now - last_beat >= 30.0:
            last_beat = now
            live.lock.beat()
        lo = job["progress"].get("last_output")
        try:
            lo_t = time.mktime(time.strptime(lo, "%Y-%m-%dT%H:%M:%S")) if lo else last_line_t
        except ValueError:
            lo_t = last_line_t
        stalled = (now - lo_t) > STALL_SECONDS
        if stalled != job["progress"].get("stalled"):
            with _lock:
                job["progress"]["stalled"] = stalled
                _save()
        if live.last_save and now - live.last_save >= SAVE_THROTTLE:
            with _lock:
                live.last_save = 0.0
                _save()
        time.sleep(0.5)
    reader.join(5.0)
    return proc.returncode


def _read(job, live, proc):
    try:
        for line in proc.stdout:
            line = line.rstrip("\r\n")
            _on_line(job, live, line)
    except Exception:
        pass


def _on_line(job, live, line):
    try:
        live.logf.write(line + "\n")
        live.logf.flush()
    except Exception:
        pass
    live.tail.append(line)
    with _lock:
        job["progress"]["last_output"] = _now()
        parse_line(job, line, live.key_to_stage)
        m = stop_marker(line)
        if m:
            live.marker = m
        if not live.last_save:
            live.last_save = time.time()


# ---------------------------------------------------------------- progress

RE_RENDER = re.compile(r"^\s+render\s+(\S+)\s+seed\s+(\d+)\s+([\d.]+)s\s+(ok|retry: .+)$")
RE_CLIP = re.compile(r"^\s+(pose|clip|ctl|flf|shot)\s+(\S+)\s+seed\s+(\d+)\s+([\d.]+)s\s+(.+)$")
RE_SIDE = re.compile(r"^\s+side\s+(\S+)\s+seed\s+(\d+)\s+([\d.]+)s")
RE_ICON = re.compile(r"^\s+(\S+) c(\d+) seed (\d+) ([\d.]+)s")
RE_TITLE = re.compile(r"^\s+(\S+) #(\d+) seed (\d+)\s+([\d.]+)s")
RE_BADGE = re.compile(r"^\s+badge (\S+) c(\d+) seed (\d+)")
RE_PACKED = re.compile(r"gen_ctl: (\S+) (\S+) packed, (\d+) frames")
RE_ITEM = re.compile(r"^\[\s*\d+/\s*\d+\]\s+\S+\s+(\S+)\s+(ok|FAIL)")
RE_NO_DRIVERS = re.compile(r"\(no drivers in .* falling back")
RE_FAILED = re.compile(r"\((video|pose|fall) (cycle|clip) failed")
RE_QA_FAILED = re.compile(r"\(vision QA failed")
RE_KEPT = re.compile(r"kept the best of \d+ for (\S+):")
RE_ROLL = re.compile(r"rolling again")
RE_SIDE_DONE = re.compile(r"side candidates painted")
RE_VIEW_PICK = re.compile(r"pick with --use-view")
RE_EDIT_PICK = re.compile(r"look at (\S+), then --pick N")
RE_REVIEW = re.compile(r"^review (\S+)")
RE_BADGE_DONE = re.compile(r"badge candidates painted")
RE_TITLE_REVIEW = re.compile(r"^\s+review: (\S+)")
RE_SIDECAR = re.compile(r"sidecar written: (\S+)")
RE_VIEWS_SHEET = re.compile(r"views sheet:")


def stop_marker(line):
    """The human stops and the done-with-candidates lines: side | view | pick | review | badge | title; else None."""
    if RE_SIDE_DONE.search(line):
        return "side"
    if RE_VIEW_PICK.search(line):
        return "view"
    if RE_EDIT_PICK.search(line):
        return "pick"
    if RE_REVIEW.match(line):
        return "review"
    if RE_BADGE_DONE.search(line):
        return "badge"
    if RE_TITLE_REVIEW.match(line):
        return "title"
    return None


def _stage_index(job):
    """cache key (and its aliases) -> stage, for the parser."""
    idx = {}
    for s in job["progress"].get("stages", []):
        k = s.get("key")
        if not k:
            continue
        idx[k] = s
        # a view's re-rolled candidates and a hero's free-clip fallback count for the stage they replace
        if "_pose_run_" in k:
            view = k.rsplit("_", 1)[-1]
            suffix = {"back": "_b", "front": "_f", "side": "_s", "bd": "_bd", "fd": "_fd"}.get(view, "")
            idx[k.replace("_pose_run_" + view, "_run" + suffix)] = s
        if s.get("type") == "still" and job.get("method") == "creature_ctl" and "_side_k" not in k:
            for c in range(8):
                idx["%s_c%d" % (k, c)] = s
    return idx


def _mark(stage, state, secs=None, note=None):
    if stage is None:
        return
    if state == "done" or stage.get("state") != "done":
        stage["state"] = state
    if secs is not None:
        stage["secs"] = (stage.get("secs") or 0) + float(secs)
    if note:
        stage["note"] = note


def parse_line(job, line, key_to_stage=None):
    """One log line into the job's progress (stages, done, stage name, the silent fallbacks). Returns what it saw."""
    prog = job["progress"]
    stages = prog.get("stages", [])
    idx = key_to_stage if key_to_stage is not None else _stage_index(job)
    seen = None
    m = RE_RENDER.match(line)
    if m:
        key, secs, verdict = m.group(1), float(m.group(3)), m.group(4)
        st = idx.get(key)
        seen = ("render", key)
        _mark(st, "done" if verdict == "ok" else "running", secs, None if verdict == "ok" else verdict)
        prog["stage"] = (st or {}).get("name") or key
    else:
        m = RE_CLIP.match(line)
        if m:
            kind, key, secs, rest = m.group(1), m.group(2), float(m.group(4)), m.group(5)
            st = idx.get(key)
            seen = (kind, key)
            ok = not rest.startswith("retry")
            _mark(st, "done" if ok else "running", secs, None if ok else rest)
            if st is not None and ok:
                st["clip_kind"] = {"pose": "pose", "clip": "free", "ctl": "control", "flf": "flf", "shot": "control"}.get(kind, kind)
            prog["stage"] = (st or {}).get("name") or key
        else:
            m = RE_SIDE.match(line)
            if m:
                key, secs = m.group(1), float(m.group(3))
                st = idx.get(key)
                seen = ("side", key)
                _mark(st, "done", secs)
                prog["stage"] = (st or {}).get("name") or key
            else:
                m = RE_ICON.match(line) or RE_BADGE.match(line)
                if m and job["kind"] in ("icon_cands", "hero_badge"):
                    c = int(m.group(2))
                    st = stages[c] if c < len(stages) else None
                    seen = ("cand", c)
                    _mark(st, "done", float(m.group(4)) if m.re is RE_ICON else None)
                    prog["stage"] = "c%d" % c
                else:
                    m = RE_TITLE.match(line)
                    if m and job["kind"] == "hero_title":
                        c = int(m.group(2))
                        st = stages[c] if c < len(stages) else None
                        seen = ("cand", c)
                        _mark(st, "done", float(m.group(4)))
                        prog["stage"] = "c%d" % c
    if RE_PACKED.search(line) or RE_ITEM.match(line):
        for s in stages:
            if s.get("type") == "pack":
                _mark(s, "done")
        prog["stage"] = "packed"
        seen = seen or ("pack", "")
    if RE_NO_DRIVERS.search(line) or RE_FAILED.search(line):
        prog.setdefault("fallbacks", []).append(line.strip())
        seen = seen or ("fallback", line.strip())
    if RE_QA_FAILED.search(line):
        job["qa_online"] = False
        seen = seen or ("qa_offline", "")
    m = RE_KEPT.search(line)
    if m:
        # every try failed the checks and the best was kept: that still is finished all the same
        st = idx.get(m.group(1))
        _mark(st, "done", None, "kept the best: " + line.strip().split(":", 1)[-1].strip(" )"))
        prog["stage"] = (st or {}).get("name") or m.group(1)
    if m or RE_ROLL.search(line):
        prog.setdefault("notes", []).append(line.strip())
    if RE_VIEWS_SHEET.search(line):
        for s in stages:
            if s.get("type") == "still" and s.get("state") == "pending" and s.get("name") in ("front", "fd", "bd", "back"):
                _mark(s, "done")
    m = RE_SIDECAR.search(line)
    if m:
        job["sidecar"] = m.group(1)
    marker = stop_marker(line)
    if marker in ("review", "badge", "title", "side", "view", "pick"):
        for s in stages:
            if s.get("type") in ("pack", "stop") or (s.get("type") == "still" and marker in ("review", "badge", "title", "side", "pick")):
                _mark(s, "done")
        prog["stage"] = {"side": "side candidates painted", "view": "view candidates painted", "pick": "candidates painted",
                         "review": "review sheet", "badge": "badge candidates", "title": "title candidates"}[marker]
        seen = seen or ("marker", marker)
    prog["done"] = sum(1 for s in stages if s.get("state") == "done")
    prog["total"] = len(stages)
    return seen


def parse_log(job, text):
    """A whole log through the parser (the selftest); returns the markers seen in order."""
    markers = []
    idx = _stage_index(job)
    for line in text.splitlines():
        parse_line(job, line, idx)
        m = stop_marker(line)
        if m:
            markers.append(m)
    return markers


def _check_caches(job, live):
    """A stage whose cache files sit on disk is done, whatever the log said (a cached still prints nothing)."""
    changed = False
    with _lock:
        for s in job["progress"].get("stages", []):
            if s.get("state") == "done" or not s.get("key"):
                continue
            if s["type"] == "still" and os.path.isfile(os.path.join(RAW, s["key"] + ".json")) and os.path.isfile(os.path.join(RAW, s["key"] + ".png")):
                s["state"], changed = "done", True
                s.setdefault("note", "cached")
            elif s["type"] == "clip" and os.path.isfile(os.path.join(ANIM, s["key"], "cycle.json")):
                s["state"], changed = "done", True
                s.setdefault("note", "cached")
        if changed:
            job["progress"]["done"] = sum(1 for s in job["progress"]["stages"] if s.get("state") == "done")
            job["eta_s"] = _eta(job)
            live.last_save = live.last_save or time.time()


# ---------------------------------------------------------------- after the process

def _after_exit(job, rc, live):
    with _lock:
        if live.cancelled:
            _finish(job, "cancelled", error="")
            return
        if rc != 0:
            tail = [x for x in live.tail if x.strip()]
            err = ""
            for x in reversed(tail):   # the exception's own line first, then a tool's message, then the runner's
                if re.match(r"^\w*(Error|Exception|Exit)\b", x) or x.startswith(("gen_art:", "gen_ctl:", "gen_edit_stills:", "gen_badge_cands:", "SCRIPT ERROR")):
                    err = x.strip()
                    break
            if not err:
                for x in reversed(tail):
                    if x.startswith("asset_job:") or "error" in x.lower():
                        err = x.strip()
                        break
            _finish(job, "failed", error=err or (tail[-1].strip() if tail else "exit code %s" % rc))
            return
        marker = live.marker
        if marker in ("side", "view", "pick"):
            job["waiting_for"] = marker
            job["choices"] = _choices(job, marker)
            job["outputs"] = _harvest(job)
            job["state"], job["ended"], job["pid"] = "waiting", _now(), None
            job["progress"]["stage"] = {"side": "pick a side view", "view": "pick the views", "pick": "pick a front"}[marker]
            _save()
            return
    # the post phase: merge through the hooks (outside the lock: the server's merge takes its own)
    written, error = _post(job)
    with _lock:
        if written is not None:
            job["written"] = written
        job["outputs"] = _harvest(job)
        if job["kind"] in ("icon_cands", "hero_badge", "hero_title"):
            job["choices"] = _choices(job, {"icon_cands": "review", "hero_badge": "badge", "hero_title": "title"}[job["kind"]])
        _finish(job, "done", error=error or "", save=False)
        if job["kind"] == "launch":
            job["progress"]["stage"] = "the window closed"
        _save()
    _after_done(job)


def _result(job):
    p = os.path.join(_job_dir(job["id"]), "result.json")
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _post(job):
    """The merge into the content JSON through the server's hooks; returns (written, error)."""
    kind, method, t = job["kind"], job.get("method"), job.get("target") or {}
    res = _result(job) or {}
    info = res.get("info") or {}
    try:
        if kind == "look" and method in ("hero_pose5", "hero_fit", "creature_free2", "creature_pose2", "creature_free8", "creature_proc", "creature_ctl"):
            entry = res.get("entry") or {}
            if not entry:
                return None, "the tool wrote no result.json entry (nothing merged)"
            h = _hook("merge_look")
            if not h:
                return {"file": "", "keys": ["variants"], "backup": "", "layout": "unmerged"}, "no merge hook: the entry sits in result.json"
            e = dict(entry)
            e["fresh"] = True
            r = h(t["kind"], t["id"], t["code"], e, info) or {}
            return _written(t, r, ["variants"]), ("" if r.get("ok") else str(r.get("error") or "the entry could not be merged"))
        if kind == "look" and method == "front_from_picture" and job.get("phase", 1) >= 2:
            h = _hook("set_recipe")
            recipe = dict((job.get("spec") or {}).get("recipe") or {})
            recipe["stills"] = str((job.get("spec") or {}).get("stills") or "")
            if h:
                r = h(t["kind"], t["id"], t["code"], recipe, (job.get("spec") or {}).get("note") or None) or {}
                return _written(t, r, ["variants"]), ("" if r.get("ok", True) else str(r.get("error", "")))
            return None, ""
        if kind == "look" and method == "recolour":
            h, lr = _hook("merge_look"), _hook("look_records")
            src_code = str(((job.get("spec") or {}).get("recolour") or {}).get("from", ""))
            entry = {"sprite": "%s_sprite_%s.png" % (t["id"], _letter(t["code"])), "icon": "%s_icon_%s.png" % (t["id"], _letter(t["code"])), "fresh": True}
            if lr:
                for rec in lr(t["kind"], t["id"]) or []:
                    if rec.get("code") == src_code:
                        for k in ("anims", "strip_cols", "fps", "head", "front_faces", "back_faces", "frame_px"):
                            if rec.get(k) not in (None, "", 0, {}):
                                entry[k] = rec[k]
            if not h:
                return {"file": "", "keys": ["variants"], "backup": "", "layout": "unmerged"}, "no merge hook"
            r = h(t["kind"], t["id"], t["code"], entry, {"pipeline": "recolour_strip", "from": src_code}) or {}
            return _written(t, r, ["variants"]), ("" if r.get("ok") else str(r.get("error") or ""))
        if kind == "item_icon" or (kind == "install" and (res.get("top") or {}).get("badge")):
            top = res.get("top") or {}
            if not top:
                return None, ""
            h = _hook("merge_top")
            if not h:
                return {"file": "", "keys": sorted(top), "backup": "", "layout": "unmerged"}, "no merge hook: the keys sit in result.json"
            tk = "hero" if kind == "install" else t.get("kind", "")
            r = h(tk, t["id"], top) or {}
            return _written(t, r, sorted(top)), ("" if r.get("ok") else str(r.get("error") or ""))
    except Exception as e:
        return {"file": "", "keys": [], "backup": "", "layout": "unmerged"}, "merge failed: %s: %s" % (type(e).__name__, e)
    return None, ""


def _written(t, r, keys):
    tf, jp = content_path(t.get("kind", ""), t.get("id", ""))
    return {"file": _rel(jp) if jp else "", "keys": keys, "backup": r.get("backup", ""), "layout": r.get("layout", "unmerged" if not r.get("ok") else "block")}


def _after_done(job):
    """What follows a landing: an import job for new PNGs."""
    kind, t = job["kind"], job.get("target") or {}
    if kind in ("look", "item_icon", "install") and t.get("id"):
        if kind == "look" and job.get("method") == "front_from_picture":
            return
        tf, jp = content_path(t.get("kind", ""), t["id"])
        if tf:
            try:
                enqueue("import", {"kind": t.get("kind", ""), "id": t["id"], "code": ""}, {"targets": ["%s/%s" % (tf, t["id"])]},
                        title="import %s/%s (after %s)" % (tf, t["id"], job["id"]))
            except ValueError:
                pass


# ---------------------------------------------------------------- harvest

def _url_dl(path):
    return "/dl/" + _rel(path).split("tools/dl/", 1)[-1] if "tools/dl/" in _rel(path) else "/dl/" + _rel(path)


def _still_output(key, label=None):
    png, meta = os.path.join(RAW, key + ".png"), os.path.join(RAW, key + ".json")
    if not os.path.isfile(png):
        return None
    out = {"label": label or key, "type": "still", "url": "/dl/ai_raw_anime/%s.png" % key, "cache_key": key}
    try:
        with open(meta, "r", encoding="utf-8") as f:
            m = json.load(f)
        out["seed"] = m.get("seed")
        out["qa"] = {"problems": (m.get("qa") or {}).get("problems", [])}
        if (m.get("qa") or {}).get("error"):
            out["qa"]["offline"] = True
    except (OSError, ValueError):
        pass
    return out


def _clip_output(key, label=None, fps=None):
    cj = os.path.join(ANIM, key, "cycle.json")
    if not os.path.isfile(cj):
        return None
    out = {"label": label or key, "type": "clip", "url": "/dl/ai_anim/%s/" % key, "cache_key": key,
           "sheet": "/dl/ai_anim/%s/cycle_sheet.png" % key}
    try:
        with open(cj, "r", encoding="utf-8") as f:
            m = json.load(f)
        out["frames"] = m.get("n_out") or m.get("frames")
        out["seed"] = m.get("seed")
        out["seconds"] = m.get("seconds")
        out["clip_kind"] = "pose" if m.get("pose") else "control" if m.get("control") or m.get("oneshot") else "flf" if m.get("flf") else "free"
    except (OSError, ValueError):
        pass
    frames = sorted(glob.glob(os.path.join(ANIM, key, "out_*.png")))
    out["frame_files"] = [os.path.basename(p) for p in frames]
    if fps:
        out["fps"] = fps
    return out


def _harvest(job):
    kind, method, t = job["kind"], job.get("method"), job.get("target") or {}
    spec = job.get("spec") or {}
    outs = []
    ck = job.get("cache_keys") or {}
    res = _result(job) or {}
    info = res.get("info") or {}
    kinds = info.get("clip_kind") or {}
    if kind in ("look", "item_icon", "hero_badge"):
        for k in ck.get("stills", []):
            o = _still_output(k)
            if o:
                outs.append(o)
        fps = ((res.get("entry") or {}).get("fps") or {})
        for k in ck.get("clips", []):
            o = _clip_output(k, fps=fps.get("die") if k.endswith(("_fall", "_death")) else fps.get("run"))
            if o:
                v = k.rsplit("_", 1)[-1]
                if v in kinds:
                    o["clip_kind"] = kinds[v]
                outs.append(o)
    if kind == "look" and method == "creature_ctl":
        key = t["id"] + "_" + _code_part(t.get("code", ""))
        for name in (key + "_side_cands.png", key + "_views.png"):
            p = os.path.join(REVIEW, name)
            if os.path.isfile(p):
                outs.append({"label": name, "type": "sheet", "url": "/dl/review/" + name})
        for v in CTL_VIEWS:
            p = os.path.join(REVIEW, "%s_%s_cands.png" % (key, v))
            if os.path.isfile(p):
                outs.append({"label": "%s candidates" % v, "type": "sheet", "url": "/dl/review/" + os.path.basename(p)})
    if kind == "look" and method == "front_from_picture":
        name = "%s_%s_front_cands.png" % (t["id"], spec.get("stills", ""))
        if os.path.isfile(os.path.join(REVIEW, name)):
            outs.append({"label": "front candidates", "type": "sheet", "url": "/dl/review/" + name})
        installed = _still_output("%s_%s_front" % (t["id"], spec.get("stills", "")), "the picked front")
        if installed:
            outs.append(installed)
    if kind == "look" and method not in ("front_from_picture",) and t.get("code"):
        folder = _content_folder(t.get("kind", ""), t["id"])
        if folder:
            letter = _letter(t["code"])
            sp = os.path.join(folder, "%s_sprite_%s.png" % (t["id"], letter))
            if os.path.isfile(sp):
                outs.append({"label": "strip", "type": "strip", "url": "/sprite/%s/%s/%s?v=%d" % (t.get("kind", ""), t["id"], t["code"], int(os.path.getmtime(sp))),
                             "file": _rel(sp), "mtime": int(os.path.getmtime(sp))})
            ic = os.path.join(folder, "%s_icon_%s.png" % (t["id"], letter))
            if os.path.isfile(ic):
                outs.append({"label": "icon", "type": "icon", "url": "/icon/%s/%s/%s?v=%d" % (t.get("kind", ""), t["id"], t["code"], int(os.path.getmtime(ic))), "file": _rel(ic)})
            ai = os.path.join(folder, "%s_%s_ai.json" % (t["id"], letter))
            if os.path.isfile(ai):
                outs.append({"label": "marker", "type": "json", "file": _rel(ai)})
    if kind == "item_icon" and t.get("id"):
        folder = _content_folder(t.get("kind", ""), t["id"])
        doc = content_doc(t.get("kind", ""), t["id"]) or {}
        ic = os.path.join(folder or "", doc.get("icon", t["id"] + "_icon.png"))
        if folder and os.path.isfile(ic):
            outs.append({"label": "icon", "type": "icon", "url": "/icon/%s/%s?v=%d" % (t.get("kind", ""), t["id"], int(os.path.getmtime(ic))), "file": _rel(ic)})
        if info.get("icon_backup"):
            outs.append({"label": "the old icon", "type": "backup", "file": _rel(info["icon_backup"])})
    if kind == "icon_cands":
        key = (job.get("plan") or {}).get("key", t.get("id", ""))
        folder = os.path.join(DL, "icons_le_" + job["id"])
        for p in sorted(glob.glob(os.path.join(folder, "%s_c*.png" % key))):
            outs.append({"label": os.path.basename(p)[:-4], "type": "candidate", "url": "/dl/icons_le_%s/%s" % (job["id"], os.path.basename(p))})
        rv = os.path.join(folder, "review_%s.png" % key)
        if os.path.isfile(rv):
            outs.append({"label": "review sheet", "type": "sheet", "url": "/dl/icons_le_%s/review_%s.png" % (job["id"], key)})
    if kind == "hero_badge":
        rv = os.path.join(REVIEW, "%s_badge_cands.png" % t.get("id", ""))
        if os.path.isfile(rv):
            outs.append({"label": "badge candidates", "type": "sheet", "url": "/dl/review/" + os.path.basename(rv)})
    if kind == "hero_title":
        hid = t.get("id", "")
        for p in sorted(glob.glob(os.path.join(TITLE_OUT, "%s_[0-9]*.png" % hid))):
            if p.endswith("_raw.png"):
                continue
            outs.append({"label": os.path.basename(p)[:-4], "type": "candidate", "url": "/dl/title_heroes/" + os.path.basename(p)})
        rv = os.path.join(TITLE_OUT, "review_%s.png" % hid)
        if os.path.isfile(rv):
            outs.append({"label": "review sheet", "type": "sheet", "url": "/dl/title_heroes/review_%s.png" % hid})
    if kind in ("driver_pose", "driver_depth"):
        name = str(spec.get("name", ""))
        d = os.path.join(DRIVERS, name)
        for n in ("all_sheet.png",) + tuple("%s_sheet.png" % v for v in CTL_VIEWS):
            if os.path.isfile(os.path.join(d, n)):
                outs.append({"label": n, "type": "sheet", "url": "/dl/drivers/%s/%s" % (name, n)})
        for v in CTL_VIEWS:
            for n in ("clay.png", "look.png"):
                if os.path.isfile(os.path.join(d, v, n)):
                    outs.append({"label": "%s %s" % (v, n), "type": "still", "url": "/dl/drivers/%s/%s/%s" % (name, v, n)})
        if os.path.isfile(os.path.join(d, "meta.json")):
            outs.append({"label": "meta.json", "type": "json", "url": "/dl/drivers/%s/meta.json" % name})
    if kind in ("ref_probe", "ref_render"):
        src = str(spec.get("src", ""))
        d = os.path.dirname(src) if os.path.dirname(src) else os.path.join(UPLOADS, "3d", os.path.splitext(os.path.basename(src))[0])
        d = d if os.path.isabs(d) else os.path.join(_root, d)
        for n in ("probe.json", "icon_ref.png", "thumbs.png"):
            if os.path.isfile(os.path.join(d, n)):
                outs.append({"label": n, "type": "json" if n.endswith(".json") else "still", "url": _url_dl(os.path.join(d, n))})
        for v in CTL_VIEWS:
            for n in ("clay.png", "look.png"):
                if os.path.isfile(os.path.join(d, v, n)):
                    outs.append({"label": "%s %s" % (v, n), "type": "still", "url": _url_dl(os.path.join(d, v, n))})
    if kind == "install" and res:
        outs.append({"label": "installed", "type": "json", "detail": {k: res.get(k) for k in ("tool", "call", "top") if res.get(k) is not None}})
    # the ComfyUI workflows the job ran (comfy.save_job_workflow): one file per graph; the copy in the page's Workflows
    # sidebar (`<stem>_userdata.json` marker, written by the run or by push_workflows) gives the "open in ComfyUI" link
    wd = os.path.join(_job_dir(job["id"]), "workflows")
    if os.path.isdir(wd):
        for f in sorted(os.listdir(wd)):
            if f.endswith("_workflow.json"):
                stem = f[:-len("_workflow.json")]
                o = {"label": stem, "type": "workflow", "url": _url_dl(os.path.join(wd, f)),
                     "api_url": _url_dl(os.path.join(wd, stem + "_api.json"))}
                mk = os.path.join(wd, stem + "_userdata.json")
                if os.path.isfile(mk):
                    try:
                        with open(mk, "r", encoding="utf-8") as fh:
                            upath = str(json.load(fh).get("path") or "")
                        if upath:
                            o["userdata"] = upath
                            o["open_url"] = _comfy_open_url(upath)
                    except Exception:
                        pass
                outs.append(o)
    return outs


def _choices(job, marker):
    t = job.get("target") or {}
    spec = job.get("spec") or {}
    out = []
    if marker == "side":
        key = t["id"] + "_" + _code_part(t.get("code", ""))
        for p in sorted(glob.glob(os.path.join(RAW, key + "_side_k*.png"))):
            k = os.path.basename(p)[:-4].rsplit("_", 1)[-1]
            out.append({"id": k, "label": k, "url": "/dl/ai_raw_anime/" + os.path.basename(p)})
        sheet = os.path.join(REVIEW, key + "_side_cands.png")
        if os.path.isfile(sheet):
            out.append({"id": "", "label": "sheet", "url": "/dl/review/" + os.path.basename(sheet), "sheet": True})
    elif marker == "view":
        key = t["id"] + "_" + _code_part(t.get("code", ""))
        for v in [x for x in str(spec.get("view_cands", "")).split(",") if x]:
            for p in sorted(glob.glob(os.path.join(RAW, "%s_%s_c*.png" % (key, v)))):
                c = os.path.basename(p)[:-4].rsplit("_", 1)[-1]
                out.append({"id": "%s:%s" % (v, c), "label": "%s %s" % (v, c), "view": v, "url": "/dl/ai_raw_anime/" + os.path.basename(p)})
    elif marker == "pick":
        key = "%s_%s_front" % (t["id"], spec.get("stills", ""))
        for p in sorted(glob.glob(os.path.join(RAW, key + "_c*.png"))):
            c = os.path.basename(p)[:-4].rsplit("_c", 1)[-1]
            out.append({"id": c, "label": "c" + c, "url": "/dl/ai_raw_anime/" + os.path.basename(p)})
    elif marker == "review":
        key = (job.get("plan") or {}).get("key", t.get("id", ""))
        for p in sorted(glob.glob(os.path.join(DL, "icons_le_" + job["id"], "%s_c*.png" % key))):
            c = os.path.basename(p)[:-4].rsplit("_c", 1)[-1]
            out.append({"id": c, "label": "c" + c, "url": "/dl/icons_le_%s/%s" % (job["id"], os.path.basename(p))})
    elif marker == "badge":
        for p in sorted(glob.glob(os.path.join(RAW, "%s_portrait_c*.png" % t.get("id", "")))):
            c = os.path.basename(p)[:-4].rsplit("_c", 1)[-1]
            out.append({"id": c, "label": "c" + c, "url": "/dl/ai_raw_anime/" + os.path.basename(p)})
    elif marker == "title":
        hid = t.get("id", "")
        for p in sorted(glob.glob(os.path.join(TITLE_OUT, "%s_[0-9]*.png" % hid))):
            if p.endswith("_raw.png"):
                continue
            n = os.path.basename(p)[:-4].rsplit("_", 1)[-1]
            out.append({"id": n, "label": "#" + n, "url": "/dl/title_heroes/" + os.path.basename(p)})
    return out


# ---------------------------------------------------------------- steps and the launch

def _run_steps(job, plan, live):
    keep = bool(plan.get("keep_save"))
    if keep:
        locks.keep_save()
    try:
        rc = 0
        for i, step in enumerate(plan.get("steps") or []):
            with _lock:
                st = job["progress"]["stages"][i] if i < len(job["progress"]["stages"]) else None
                if st:
                    st["state"] = "running"
                job["progress"]["stage"] = (st or {}).get("name", "step %d" % (i + 1))
                _save()
            t0 = time.time()
            rc = _spawn(job, live, step)
            with _lock:
                if st:
                    st["state"] = "done" if rc == 0 else "failed"
                    st["secs"] = round(time.time() - t0, 1)
                job["progress"]["done"] = sum(1 for s in job["progress"]["stages"] if s.get("state") == "done")
            if rc != 0 or live.cancelled:
                break
        return rc
    finally:
        if keep:
            locks.restore_save()


def _run_launch(job, plan, live):
    locks.keep_save()
    try:
        os.makedirs(os.path.dirname(LAUNCH_FILE), exist_ok=True)
        with open(LAUNCH_FILE, "w", encoding="utf-8", newline="\n") as f:
            json.dump(plan.get("launch") or {}, f)
        live.logf.write("wrote %s: %s\n" % (LAUNCH_FILE, json.dumps(plan.get("launch") or {})))
        with _lock:
            job["progress"]["stage"] = "the game window is open"
            job["progress"]["stages"][0]["state"] = "running"
            _save()
        rc = _spawn(job, live, plan["steps"][0])
        if os.path.isfile(LAUNCH_FILE):
            # the game never read it (it died early, or it was not Game.tscn): never leave it for Garry's next Play
            try:
                os.remove(LAUNCH_FILE)
                live.logf.write("the launch file was still there: removed\n")
            except OSError:
                pass
        with _lock:
            job["progress"]["stages"][0]["state"] = "done"
            job["progress"]["done"] = 1
        return rc
    finally:
        locks.restore_save()


# ---------------------------------------------------------------- killing

def _kill_tree(pid):
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True, timeout=30)
        else:
            os.kill(pid, 9)
        return True
    except Exception:
        return False


def _user_folder(job):
    """The folder a job's workflows take in the ComfyUI page's Workflows sidebar (workflows/88fits/<folder>/): a look's
    `<id>_<CODE>`, else `<id>_<kind>` (goblin_GOB-E, drifter_hero_badge, spear_item_icon)."""
    t = job.get("target") or {}
    base = str(t.get("id") or job.get("kind") or "job")
    tail = str(t.get("code") or "") if job.get("kind") == "look" else str(job.get("kind") or "")
    name = "%s_%s" % (base, tail) if tail else base
    out = "".join(c if (c.isalnum() or c in "-_.") else "_" for c in name).strip("._")
    return out[:80] or "job"


def _workflows_sig(job):
    """What the job's workflows folder holds (the names), to notice a new graph or a new sidebar marker cheaply."""
    wd = os.path.join(_job_dir(job["id"]), "workflows")
    try:
        return tuple(sorted(f for f in os.listdir(wd) if f.endswith(("_workflow.json", "_userdata.json"))))
    except OSError:
        return ()


def _comfy_open_url(path):
    """The link that opens the ComfyUI page on a saved workflow (the 88fits_open extension reads ?open=)."""
    return COMFY_SERVER.rstrip("/") + "/?open=" + urllib.parse.quote(path, safe="")


def _comfy_put_userdata(path, obj, timeout=30):
    """Save a workflow into the ComfyUI page's user data (its Workflows sidebar): POST /api/userdata/<path>."""
    url = COMFY_SERVER.rstrip("/") + "/api/userdata/" + urllib.parse.quote(path, safe="") + "?overwrite=true&full_info=true"
    req = urllib.request.Request(url, data=json.dumps(obj).encode("utf-8"), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))


_ext_state = {"at": 0.0, "installed": None}


def comfy_extension_state(max_age=60.0):
    """Whether the ComfyUI page lists the 88fits_open extension (the one that makes the "open in ComfyUI" links work):
    {installed: True | False | None (no answer), checked: iso}. Asked at most once a minute (the page polls status)."""
    now = time.time()
    if now - _ext_state["at"] >= max_age:
        st = None
        try:
            files = json.load(urllib.request.urlopen(COMFY_SERVER.rstrip("/") + "/api/extensions", timeout=3))
            st = any("/88fits_open/" in str(f) for f in files)
        except Exception:
            st = None
        _ext_state.update({"at": now, "installed": st, "checked": _now()})
    return {"installed": _ext_state["installed"], "checked": _ext_state.get("checked"), "server": COMFY_SERVER}


def push_workflows(job_id):
    """Save a job's workflow files into the ComfyUI page's Workflows sidebar: the ones its run did not push itself (jobs
    from before the push existed, or a server that was down at the time). Network outside the lock; then the job's
    outputs carry the open links. Returns the public job with `pushed` and `push_errors`."""
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise KeyError(job_id)
        folder = _user_folder(job)
    wd = os.path.join(_job_dir(job_id), "workflows")
    pushed, errors = [], []
    if os.path.isdir(wd):
        for f in sorted(os.listdir(wd)):
            if not f.endswith("_workflow.json"):
                continue
            stem = f[:-len("_workflow.json")]
            mk = os.path.join(wd, stem + "_userdata.json")
            if os.path.isfile(mk):
                continue
            upath = "workflows/88fits/%s/%s.json" % (folder, stem)
            try:
                with open(os.path.join(wd, f), "r", encoding="utf-8") as fh:
                    wf = json.load(fh)
                rec = _comfy_put_userdata(upath, wf)
                with open(mk, "w", encoding="utf-8", newline="\n") as fh:
                    json.dump({"path": upath, "open": _comfy_open_url(upath), "server": rec}, fh, indent=1)
                pushed.append(upath)
            except Exception as e:
                errors.append("%s: %s" % (stem, e))
    with _lock:
        job["outputs"] = _harvest(job)
        _save()
        out = _public(job, LOG_TAIL_SHORT)
    out["pushed"], out["push_errors"] = pushed, errors
    return out


_templates_pushed = {}


def push_templates(folder=None):
    """The method templates (tools/comfy_workflows/*.json, `python tools/comfy.py --export`) saved into the sidebar under
    workflows/88fits/templates/ (each once per server start and file change); returns [{name, path, open_url, error?}]."""
    folder = folder or os.path.join(TOOLS, "comfy_workflows")
    out = []
    if not os.path.isdir(folder):
        return out
    for f in sorted(os.listdir(folder)):
        if not f.endswith(".json"):
            continue
        full = os.path.join(folder, f)
        upath = "workflows/88fits/templates/%s" % f
        rec = {"name": f, "path": upath, "open_url": _comfy_open_url(upath)}
        try:
            mtime = os.path.getmtime(full)
            if _templates_pushed.get(f) != mtime:
                with open(full, "r", encoding="utf-8") as fh:
                    _comfy_put_userdata(upath, json.load(fh))
                _templates_pushed[f] = mtime
        except Exception as e:
            rec["error"] = str(e)
        out.append(rec)
    return out


def _comfy_interrupt():
    """After a cancelled comfy job: stop what the server is doing and clear its queue (ours alone: we hold the lock)."""
    for path, body in (("/interrupt", {}), ("/queue", {"clear": True})):
        try:
            req = urllib.request.Request(COMFY_SERVER + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=5).read()
        except Exception:
            pass

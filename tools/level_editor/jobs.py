"""The Level Editor's jobs queue (pass 66): the local AI's work as a list Garry can watch, edit, reorder, cancel and add to.

Three lanes, one job each at a time, as daemon threads inside the editor server:
    comfy   the art (gen_art / gen_ctl / gen_edit_stills / gen_icon_cands / gen_title_heroes / gen_badge_cands) through
            `python -u tools/asset_job.py <job_dir>`, under the repo-wide ComfyUI lock (tools/locks.py, comfy.lock)
    godot   register / import / launch, under the Godot lock with the PC save kept aside
    local   Blender (drivers, 3D probes and renders), the pose_* tools, recolour_strip, installs of picked candidates

The queue lives in tools/dl/jobs/queue.json (atomic writes, a monotonic `rev` the page polls with); each job has its
folder tools/dl/jobs/<id>/ with job.json (what asset_job.py runs), log.txt, result.json (the tool's sidecar, see
gen_art.emit_sidecar) and candidate pictures. Nothing here imports server.py: the server hands `init()` a hooks dict
(content_path, merge_look, merge_top, set_recipe, set_look_files, redump_merge, look_records) and every content write
goes through it.

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
import ast
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
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
import locks  # noqa: E402
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import vocab as _VOCAB  # noqa: E402  (pass 70: the stills slug rule, STILLS_RE / stills_problem)

_LIST = list   # the API below is named list(); the builtin stays reachable as _LIST

GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")
DL = os.path.join(ROOT, "tools", "dl")
# pass 71 (lane PLE): LE_JOBS_DIR points a test editor (--no-jobs, its own port) at a queue of its own; unset = the real one
JOBS_DIR = os.environ.get("LE_JOBS_DIR") or os.path.join(DL, "jobs")
QUEUE_FILE = os.path.join(JOBS_DIR, "queue.json")
RAW = os.path.join(DL, "ai_raw_anime")
ANIM = os.path.join(DL, "ai_anim")
REVIEW = os.path.join(DL, "review")
DRIVERS = os.path.join(DL, "drivers")
UPLOADS = os.path.join(DL, "uploads")
TITLE_OUT = os.path.join(DL, "title_heroes")
WANTED = os.path.join(GAME, "art", "ui", "wanted")   # the title cut-outs (hero_<id>.png, a look's hero_<id>_<x>.png)
METHODS_FILE = os.path.join(HERE, "methods.json")
PY = sys.executable
GODOT = locks.GODOT
LAUNCH_FILE = os.path.join(locks.SAVE_DIR, "debug_launch.json")   # a module variable: the selftest points it at a temp dir
import ai_hosts  # noqa: E402  (pass 97, lane SAFE: tools/ai_hosts.json; COMFY_SERVER still wins; the old literals when absent)
COMFY_SERVER = os.environ.get("COMFY_SERVER", ai_hosts.get("comfy", "http://192.168.137.54:8188"))
LMSTUDIO_MODELS = ai_hosts.get("lmstudio", "http://127.0.0.1:1234").rstrip("/") + "/v1/models"
STALL_SECONDS = 20 * 60          # silence this long marks a job stalled (never killed: a dev restart can take minutes)
# pass 70 (lane LE): a step that runs Godot (register / import: --import, import_json, gen_placeholders) is killed after
# this many seconds, the Godot lock freed, the job failed with the reason and offered for Re-queue. A `godot --import`
# once sat 12 minutes at no CPU after "Editor layout ready" holding the lock for every lane (j20261013-031045-ad0e). The
# job's spec `step_timeout` (seconds) wins; LE_GODOT_STEP_TIMEOUT sets the default; 0 = never. Test in game never times
# out (the game window is Garry's).
GODOT_STEP_TIMEOUT = int(os.environ.get("LE_GODOT_STEP_TIMEOUT", "600") or 0)
CACHE_CHECK_SECONDS = 5.0
SAVE_THROTTLE = 2.0
LOG_TAIL_FULL = 80
LOG_TAIL_SHORT = 12
STATES = ("queued", "running", "waiting", "done", "failed", "interrupted", "cancelled")
LANES = ("comfy", "godot", "local", "sim")   # pass 77 (lane SIMUI): the run sim's own lane, so a sim never holds up the others
KIND_FOLDERS = {"enemy": "enemies", "boss": "bosses", "hero": "characters", "weapon": "weapons", "evolution": "evolutions",
                "passive": "passives", "mutation": "mutations"}
LOOK_METHODS = ("hero_pose5", "hero_fit", "creature_free2", "creature_pose2", "creature_free8", "creature_ctl", "creature_proc",
                "front_from_picture", "recolour", "hero_puppet", "creature_pictures")
CTL_VIEWS = ("front", "fd", "side", "bd", "back")
HERO_VIEWS = ("front", "back", "side", "fd", "bd")
# median seconds per method when methods.json has no timing (the synthesis §7; "~" always on the page)
BUILTIN_MEDIAN = {"frames_repair": 240, "frames_export": 15,   # pass 95 (lane VACE): a VACE repair of one animation, an export
                  "evaluate": 30,   # pass 96 (lane LOOP): the evaluator on a look (tier 0 + the local eye on the flagged frames)
                  "hero_pose5": 570, "hero_fit": 276, "creature_free2": 450, "creature_pose2": 240, "creature_free8": 960,
                  "creature_ctl": 660, "creature_ctl_side": 60, "creature_ctl_side_dev": 840, "creature_proc": 90, "creature_pictures": 15,
                  "front_from_picture": 20, "recolour": 5, "item_icon": 20, "icon_cands": 20, "icon_cands_dev": 270,
                  "hero_badge": 20, "hero_title": 25, "driver_pose": 60, "driver_depth": 300, "driver_tweak": 5, "ref_probe": 10,
                  "ref_render": 60, "ref_limbs": 20, "register": 120, "import": 90, "launch": 0, "install": 5, "hero_puppet": 1200}

# ---------------------------------------------------------------- the kinds and their fields

def _f(type_, default=None, required=False, help_="", options=None, group=None):
    d = {"type": type_, "default": default, "required": required, "help": help_}
    if group:
        d["group"] = group
    if options:
        d["options"] = _LIST(options)
    return d


# pass 72 (Garry: "first seed" on every asset that has candidates): the two fields every candidate kind carries, with
# the same words (jobs.js shows them together as Candidates and First seed; tools/cand_seeds.start reads the first)
CANDIDATES_HELP = "how many candidates to paint and pick from, each on a seed of its own"
FIRST_SEED_HELP = ("where this job's seeds start: candidate k paints on the first seed + k x 1,000,003, the whole set moved by "
                   "this job's id and by every re-run, so no two jobs paint the same pictures (tools/cand_seeds.py); 0 = the "
                   "tool's own start, from the asset's id; another number = a fresh set from the same words")


_LOOK_FIELDS = {
    "method": _f("enum", None, True, "how the look is made (tools/level_editor/methods.json describes each)", LOOK_METHODS),
    "recipe": _f("json", {}, False, "variants[CODE].recipe: the art keys this look overrides (gen_art / gen_ctl read it from the JSON)"),
    "refs": _f("list", [], False, "2D references [{path, role: identity|style|pose, follow: loosely|closely|copy, use: [look]}]"),
    "drivers": _f("json", {}, False, "{pose: <driver folder>, depth: <driver folder>} (tools/dl/drivers/)"),
    "skip_qa": _f("bool", False, False, "--skip-qa: no vision check (LM Studio); the geometry checks still run"),
    "dev": _f("bool", False, False, "--dev: Flux.2 dev for the stills (gen_ctl's side candidates): 4-5 min each with a server restart"),
    "seed": _f("int", 0, False, "--seed=N: every seed moves by N x 7919 (a fresh roll of the stills named in `keys`)"),
    "seeds": _f("int", 3, False, CANDIDATES_HELP + " (gen_ctl's side view and view candidates; front_from_picture's fronts)"),
    "first_seed": _f("int", 0, False, FIRST_SEED_HELP),
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
    # pass 71 (lane PLE): the Puppet method's own settings (puppet_spec: source, stills, refs, painter, steps, turbo, seeds,
    # seed, words, screen, tries, faces, reuse, fbx, clip, idle, frame, depth_views, run_fit, fringe; picks and the one-shot
    # reset_from / reroll set by the card)
    "puppet": _f("json", {}, False, "hero_puppet: {source, stills: reuse|repaint, refs: {front, side, back}: paint|still:<key>|<picture>|none, "
                                    "painter: klein|dev, steps, seeds, words: {view: text}, tries, reuse: auto|fresh|blend|fbx, fbx, clip, idle, "
                                    "frame: soles|ankles, depth_views, run_fit, fringe}"),
    # pass 68 (D3): the job form's re-roll radios, applied once at enqueue (the cache moved aside, the recipe's seeds moved)
    "reroll": _f("json", {}, False, "{mode: stills | seeds | clips | view, view}: stills = the look's stills painted again (a look that "
                                    "shared the creature's or hero's paintings gets its own); seeds = stills and clips; clips = the "
                                    "clips again from the same stills; view = creature_ctl's view candidates (view: fd,back)"),
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
    # pass 68 (D6): every word and the reference picture of the three candidate kinds is a job field the server fills
    # from the target when it is left empty (candidate_defaults; GET /api/jobs/defaults shows them before Queue)
    "icon_cands": {"lane": "comfy", "fields": _with_model({
        "subject": _f("str", "", False, "what to paint; empty = the creature's description (appearance, else its art_prompt without "
                                         "the pose) or the item's art_prompt"),
        "ref": _f("str", "", False, "the reference picture laid on the screen colour (a repo path such as tools/dl/uploads/2d/x.png, a "
                                     "tools/dl path or an absolute one); empty = the creature look's own front still, an item's 3D render"),
        "screen": _f("enum", "", False, "the screen colour; empty = the target's own (its `screen`, else as gen_art picks it)", ("", "green", "blue")),
        "style": _f("str", "", False, "words in place of gen_art's ICON_STYLE"),
        "file": _f("str", "", False, "the icon file the pick installs (<id>_icon.png, or a look's <id>_icon_<x>.png; empty = from the target)"),
        "key": _f("str", "", False, "the candidates' key (default: the target id)"),
        "seeds": _f("int", 4, False, CANDIDATES_HELP), "first_seed": _f("int", 0, False, FIRST_SEED_HELP),
        "dev": _f("bool", False, False, "--dev: Flux.2 dev (8 Turbo steps unless turbo is off, then 28), a restart each")}),
        "help": "icon candidates for an item, or for an enemy/boss look (file = its <id>_icon_<x>.png); Install picks one. A hero's "
                "icon is the round badge: hero_badge"},
    "hero_badge": {"lane": "comfy", "fields": _with_model({
        "seeds": _f("int", 4, False, CANDIDATES_HELP),
        "character": _f("str", "", False, "who: the hero's description (appearance, else art_prompt without the pose); empty = filled"),
        "prompt": _f("str", "", False, "the action of the portrait (default: the hero's portrait_prompt)"),
        "ref": _f("str", "", False, "the identity picture (default: the look's own front still, else the hero's)"),
        "variant": _f("str", "", False, "the look code the badge is for (its pick writes <id>_icon_<x>.png into that look); empty = the hero's own"),
        "first_seed": _f("int", 0, False, FIRST_SEED_HELP), "head_width": _f("float", 0.0, False, "badge: the head's span as a share of the badge (0 = the default zoom)"),
        "top_pad": _f("float", 0.03, False, "badge: the gap above the head"), "skip_qa": _f("bool", False, False, "--skip-qa")}),
        "help": "round badge candidates from the hero's (or the look's) front still; Install writes <id>_icon.png and the JSON's badge, "
                "or a look's <id>_icon_<x>.png and variants[CODE].icon"},
    "hero_title": {"lane": "comfy", "fields": _with_model({
        "seeds": _f("int", 4, False, CANDIDATES_HELP), "first_seed": _f("int", 0, False, FIRST_SEED_HELP),
        "character": _f("str", "", False, "who: the hero's description (appearance, else art_prompt without the pose)"),
        "pose": _f("str", "", False, "the pose of the splash (title_pose, else the tool's table, else a confident full-body stance)"),
        "holds": _f("str", "", False, "the one thing held (title_holds)"),
        "camera": _f("str", "", False, "the shot (title_camera)"),
        "ref": _f("str", "", False, "the identity picture (default: the look's own front still, else the hero's)"),
        "extra_ref": _f("str", "", False, "a second picture copied exactly, e.g. a render of the held object (title_extra_ref.file)"),
        "extra_words": _f("str", "", False, "the words about the second picture (title_extra_ref.words)"),
        "variant": _f("str", "", False, "the look code the cut-out is for (its pick writes art/ui/wanted/hero_<id>_<x>.png); empty = the hero's own")}),
        "help": "title cut-out candidates; Install writes art/ui/wanted/hero_<id>.png, or a look's hero_<id>_<x>.png and variants[CODE].title"},
    "driver_pose": {"lane": "local", "fields": {
        "src": _f("str", "", True, "the FBX or GLB (tools/dl/uploads/3d/<slug>/<file> or tools/dl/mixamo/<file>)"),
        "name": _f("str", "", True, "the driver folder name under tools/dl/drivers/"),
        "frames": _f("int", 24, False, "24 for a run, 12 for a walk; a one-shot wants 4k+1 (9, 25)"),
        "loop": _f("bool", True, False, "a loop (the last frame repeats the first) or a one-shot"),
        "pitch": _f("int", 25, False, "the camera's pitch"), "start": _f("str", "", False, "slice: start seconds"), "end": _f("str", "", False, "slice: end seconds"),
        "arms": _f("str", "", False, "zombie | hold_r | back (pass 69: both arms swept straight back, the dash)"), "body": _f("str", "", False, "retarget proportions top_nose:..,torso:.."),
        "fwd": _f("str", "", False, "body: square the views to the hips and shoulders"), "rig": _f("str", "", False, "mixamo (default) | sm"),
        "rigmap": _f("str", "", False, "a {model_bone: mixamo_name} JSON for another humanoid rig"),
        # pass 69 (lane ART's pose_driver options and tools/pose_shoulders.py; lane LE put them in the form)
        "amp": _f("float", 1.0, False, "the limbs swing this many times as far round their average (1.35 = a sprint)"),
        "amp_bones": _f("str", "", False, "regex of the bones amp applies to (default (Arm|ForeArm|UpLeg|Leg)$)"),
        "lean": _f("float", 0.0, False, "the spine bent forward this many degrees (12 a sprint, 14 the dash)"),
        "shoulders": _f("str", "", False, "level the shoulders with the neck: each shoulder's height off the neck x this (0.3); written to <name>_lvl; empty = off"),
        "shoulder_views": _f("str", "back,bd", False, "the views pose_shoulders levels (back,bd; side,fd for the side runs)"),
        "tuck": _f("str", "", False, "side view: the far upper arm at most this many degrees back from straight down (25); empty = off")},
        "help": "an OpenPose driver from a rigged clip (Blender), then its sheets (pose_driver.py draw); with shoulders, a levelled copy <name>_lvl (pose_shoulders.py)"},
    # pass 70 (lane LE): a copy of a library driver with one change, so Garry can fix one view of a look himself (May's
    # and Jezyk's fixes): tools/pose_scale.py, pose_spread.py, pose_occlude.py, pose_shoulders.py
    "driver_tweak": {"lane": "local", "fields": {
        "src": _f("str", "", True, "the driver to start from (a folder under tools/dl/drivers)"),
        "name": _f("str", "", True, "the new driver's folder name under tools/dl/drivers/ (a free one)"),
        "op": _f("enum", "scale", False, "scale | spread | occlude | shoulders", ("scale", "spread", "occlude", "shoulders")),
        "scale": _f("float", 0.85, False, "op scale: every keypoint moves toward the clip's middle by this (0.85: a wide figure stays inside the clip; the sprite's size is the look's run_scale, not this)"),
        "views": _f("str", "back,bd", False, "op scale and shoulders: the views changed"),
        "spread": _f("float", 0.06, False, "op spread: how far past the torso a back wrist goes"),
        "level": _f("float", 0.3, False, "op shoulders: each shoulder's height off the neck times this"),
        "tuck": _f("str", "", False, "op shoulders, side view: the far upper arm at most this many degrees back from down (25)")},
        "help": "a copy of a pose driver with one change in chosen views (pose_scale / pose_spread / pose_occlude / pose_shoulders), drawn again"},
    "driver_depth": {"lane": "local", "fields": {
        "src": _f("str", "", True, "the rigged model"), "name": _f("str", "", True, "the driver folder name"), "action": _f("str", "", False, "the clip to play"),
        "mode": _f("enum", "cycle", False, "cycle (the clip as a walk) | oneshot (the clip as a death) | gait (a walk made for a legged model, no clip needed) | flip_curl (a death made: it rolls onto its back, legs curled)", ("cycle", "oneshot", "gait", "flip_curl")), "frames": _f("int", 12, False, ""),
        "cycles": _f("int", 2, False, ""), "total": _f("int", 25, False, "oneshot frames"), "start": _f("str", "", False, ""), "end": _f("str", "", False, ""),
        "depth": _f("enum", "tight", False, "", ("tight", "wide")), "amp": _f("float", 1.0, False, "legs swing this much wider"),
        "amp_bones": _f("str", "", False, "regex of the bones amp applies to"), "pitch": _f("int", 25, False, ""), "views": _f("str", "", False, "front,fd,side,bd,back"),
        "forward": _f("str", "", False, "-Y"), "screen": _f("str", "", False, "0,1,0"), "albedo": _f("str", "", False, ""), "inplace": _f("bool", True, False, ""),
        # pass 94 (lane REAL): a low-poly model's cones and fins rounded in the renders (the spider's crystal knees)
        "smooth": _f("int", 0, False, "subdivision levels the renders get (2 for a low-poly model: its cones and fins rounded, the depth range and the leg tips still from the raw mesh); 0 = off"),
        "skin": _f("enum", "", False, "gait / flip_curl: capsule = the legs' own mesh replaced by tapered capsules along the bone chain, head to head (a low-poly model's cone legs stood up as spikes at every joint); empty = the mesh as it is", ("", "capsule")),
        "skin_radius": _f("float", 0.06, False, "skin capsule: the leg's radius at the hip as a share of its length, tapering to a point at the foot"),
        # pass 92 (lane SPIDER): the made motions (tools/blender_gait.py); empty = the tool's default
        "legs": _f("str", "", False, "gait / flip_curl: a regex over the leg bones' names (empty: leg, thigh, calf, shin, foot, toe, tarsus, femur, tibia)"),
        "base": _f("str", "", False, "gait / flip_curl: seconds into the named clip whose pose is the stance (empty: the rest pose)"),
        "body_scale": _f("float", 1.0, False, "gait / flip_curl: the body this much bigger, the legs keeping their size (a cartoon look's big abdomen: Wan follows the depth's shapes, so the clay carries the look's proportions)"),
        "head_scale": _f("float", 1.0, False, "gait / flip_curl: the head this much bigger (a big cartoon face needs room in the depth)"),
        "leg_scale": _f("float", 1.0, False, "gait / flip_curl: every leg this much longer or shorter (0.65: stubby cartoon legs)"),
        "scale_bones": _f("str", "", False, "gait / flip_curl: name:factor,... any other bone this much bigger"),
        "head_pitch": _f("float", 0.0, False, "gait / flip_curl: degrees the head is raised so a cartoon face looks at the front view (SP-D: 35)"),
        "gait": _f("enum", "alternate", False, "gait: alternate (two sets half a stride apart: a spider's L1 R2 L3 R4, an insect's tripod) | wave (a ripple from the back)", ("alternate", "wave")),
        "swing": _f("float", 14.0, False, "gait: degrees each leg turns fore and aft over the stride"),
        "lift": _f("float", 18.0, False, "gait: degrees a leg rises while it steps forward"),
        "flex": _f("float", 14.0, False, "gait: degrees the second joint bends while the leg is up"),
        "duty": _f("float", 0.55, False, "gait: the share of the stride a leg is on the ground"),
        "bob": _f("float", 0.04, False, "gait: the body dips this share of its height twice a stride"),
        "sway": _f("float", 2.5, False, "gait: degrees the body turns side to side"),
        # pass 93 (lane LEGS): step=track, every foot along the body's length (the spider's legs had swept sideways)
        "step": _f("enum", "swing", False, "gait: swing (each leg turns rigidly round its hip: a leg pointing forward or back sweeps its foot across the body) | track (every foot slides straight back on the ground and steps forward through the air, reached by bending hip and knee: the spider's v2 walk)", ("swing", "track")),
        "stride": _f("float", 0.22, False, "gait: step track: how far each foot travels fore and aft, a share of the creature's length"),
        "raise": _f("float", 0.12, False, "gait: step track: how high a foot rises mid-step, a share of the creature's length (the spider: 0.15)"),
        "crouch": _f("float", 0.1, False, "gait: step track: the feet's tracks pulled in towards the hips by this share of the reach, so straight legs have bend to give (the spider: 0.15)"),
        "knee": _f("enum", "up", False, "gait: step track: up (the knee above the hip-to-foot line: spiders, insects) | down", ("up", "down")),
        "seconds": _f("float", 1.2, False, "flip_curl: how long the clip is (its total frames spread over it)"),
        "roll_axis": _f("enum", "side", False, "flip_curl: side (rolls over sideways, a spider) | front (flips end over end)", ("side", "front")),
        "roll": _f("float", 180.0, False, "flip_curl: degrees it turns over (170: tipped a little to one side)"),
        "roll_dir": _f("float", 1.0, False, "flip_curl: 1 or -1, which way it rolls"),
        "roll_start": _f("float", 0.08, False, "flip_curl: seconds before the roll starts"),
        "roll_time": _f("float", 0.4, False, "flip_curl: seconds the roll takes"),
        "curl": _f("float", 70.0, False, "flip_curl: degrees each knee folds in towards the belly"),
        "curl_root": _f("float", 40.0, False, "flip_curl: degrees each hip swings the leg towards the belly"),
        "curl_start": _f("float", 0.05, False, "flip_curl: seconds when the curl starts"),
        "curl_end": _f("float", 0.75, False, "flip_curl: seconds when the legs are fully curled"),
        "bounce": _f("float", 0.12, False, "flip_curl: the share of its height it bounces when it lands"),
        "twitch": _f("float", 6.0, False, "flip_curl: degrees the curled legs twitch before it lies still (0: none)"),
        "spasm_deg": _f("float", 22.0, False, "flip_curl: degrees the legs fling up at the hit"),
        "hold": _f("float", 0.85, False, "flip_curl: the share of the clip after which the dead pose is held")},
        "help": "depth control videos for gen_ctl from a model's own clip, or a walk / death made for a legged model (tools/blender_depth_drivers.py, tools/blender_gait.py)"},
    "ref_probe": {"lane": "local", "fields": {"src": _f("str", "", True, "the 3D file")}, "help": "what a 3D file can do: probe.json beside it"},
    # pass 92 (lane SPIDER): a model with the wrong number of legs fixed (tools/blender_limb_clone.py), written as a new upload
    "ref_limbs": {"lane": "local", "fields": {
        "src": _f("str", "", True, "the rigged 3D file"),
        "name": _f("str", "", True, "the new model's name: it is written to tools/dl/uploads/3d/<name>/<name>.glb and probed"),
        "rest": _f("str", "frame:0", False, "frame:<n>: the clip's pose at frame n becomes the rest pose first (a Sketchfab GLB rests far from its stance; the clips are dropped); empty: keep the rest pose"),
        "clone": _f("str", "", False, "chain:new:yaw[:shift];... copies a leg chain (bones whose names start with chain) as new, turned yaw degrees round its hip, slid shift of its reach along forward (negative: back)"),
        "turn": _f("str", "", False, "chain:yaw[:shift];... turns an existing chain the same way"),
        "forward": _f("str", "", False, "the way the model faces (-Y, +Y, -X, +X): the slide's direction")},
        "help": "a leg chain copied or turned on a rigged model (tools/blender_limb_clone.py: the spider's six legs made eight), then probed"},
    "ref_render": {"lane": "local", "fields": {
        "src": _f("str", "", True, "the 3D file"), "mode": _f("enum", "views", False, "", ("icon", "views", "all")), "forward": _f("str", "", False, ""),
        "action": _f("str", "", False, ""), "at": _f("str", "", False, "seconds"), "frame": _f("str", "", False, ""), "pitch": _f("int", 25, False, ""),
        "icon_yaw": _f("int", 35, False, ""), "icon_pitch": _f("int", 20, False, ""), "size": _f("int", 1024, False, ""), "screen": _f("str", "", False, ""),
        "albedo": _f("str", "", False, ""), "scale": _f("str", "auto", False, "")}, "help": "icon and look renders of a 3D file (tools/blender_ref.py, lane B)"},
    "register": {"lane": "godot", "fields": {"targets": _f("list", [], True, "content folders type/id (enemies/goblin)"),
                                             "step_timeout": _f("int", 0, False, "seconds a Godot step may run before it is killed (0 = the default, 600)")},
                 "help": "a new folder: placeholders, --import, lossy, --import, import_json"},
    "import": {"lane": "godot", "fields": {"targets": _f("list", [], True, "content folders type/id"), "placeholders": _f("bool", False, False, "draw placeholders first"),
                                           "step_timeout": _f("int", 0, False, "seconds a Godot step may run before it is killed (0 = the default, 600)")},
               "help": "--import, lossy_imports, --import, import_json only=...; consecutive queued imports merge"},
    "launch": {"lane": "godot", "fields": {
        "character": _f("str", "", False, "the hero"), "look": _f("str", "", False, "the hero's look code (shown, not kept)"),
        "spawn_enemy": _f("str", "", False, "a creature to spawn"), "variant": _f("str", "", False, "its look code"),
        "count": _f("int", 3, False, "how many"), "map": _f("str", "red_canyon", False, "")},
        "help": "Test in game: the debug arena in a window (user://debug_launch.json; the Godot lock is held while it is open)"},
    # (pass 70: register and import take `step_timeout`, seconds a Godot step may run; see GODOT_STEP_TIMEOUT)
    "install": {"lane": "local", "fields": {
        "source_job": _f("str", "", True, "the finished icon_cands / hero_badge / hero_title job"), "choice": _f("str", "", True, "which candidate"),
        "head_width": _f("float", 0.0, False, "badge"), "top_pad": _f("float", 0.03, False, "badge")},
        "help": "a picked candidate written into the game (then an import job)"},
    # pass 77 (lane SIMUI): the Sim tab's run sim (tools/sim_batch.py): no ComfyUI, no Godot lock (its own sim lock, on a
    # snapshot of game/ with its own user folder), its own lane; started only by the Sim tab's Run sim button
    # pass 95 (lane VACE): the Frames view's jobs (tools/level_editor/frames_io.py queues them): a repair of chosen frames
    # of one animation x view with Wan 2.2 Fun VACE (tools/vace_repair.py, the comfy lane), and the export of a look's
    # strip from the frames store's choices (tools/frames_store.py export; the entry merged, then an import job)
    "frames_repair": {"lane": "comfy", "fields": {
        "kind": _f("str", "", True, "enemy | boss | hero"), "id": _f("str", "", True, "the asset"), "code": _f("str", "", True, "the look"),
        "anim": _f("str", "", True, "the animation (run, idle, die, attack)"), "view": _f("str", "", True, "front | fd | side | bd | back"),
        "slots": _f("list", [], True, "the frames to paint anew (0-based slots of the animation)"),
        "prompt": _f("str", "", False, "the words (empty: the clip's own)"), "seed": _f("int", 0, False, "0 = the clip's seed moved by the slots"),
        "window": _f("enum", "auto", False, "auto | single | double: how much of the animation goes in (auto: a short loop twice)", ("auto", "single", "double")),
        "guide": _f("enum", "driver", False, "driver: the redone frames follow the driver's frames fitted onto the kept figure; free: filled from their neighbours", ("driver", "free")),
        "free_fill": _f("bool", False, False, "paint a procedural animation (no clip cache, no driver) anyway, as a free fill from the neighbours (the method's repair rule in methods.json says VACE is pointless there)"),
        "size": _f("int", 0, False, "the canvas (0 = the clip's, 640)"), "note": _f("str", "", False, "")},
        "help": "chosen frames of one animation painted anew with Wan 2.2 Fun VACE, the rest kept; the new frames land in the frames store and are staged at the landing (one writer of staged.json)"},
    "frames_export": {"lane": "local", "fields": {
        "kind": _f("str", "", True, ""), "id": _f("str", "", True, ""), "code": _f("str", "", True, ""), "note": _f("str", "", False, "")},
        "help": "the look's strip packed again from the frames store's staged and selected versions (the old strip backed up), its entry merged, then an import"},
    # pass 96 (lane LOOP, AI-07 / AI-03): the loop's evaluator on a look (tools/vision_eval.py): tier 0 deterministic on every
    # frame of its groups, tier 1 the local eye on the flagged frames plus one sampled clean frame a group, tier 2 the cloud eye
    # on one contact sheet when the request's cloud_dollars allow it; writes <job>/findings.json (the local lane, no lock)
    "evaluate": {"lane": "local", "fields": {
        "kind": _f("str", "", True, "enemy | boss | hero"), "id": _f("str", "", True, "the asset"), "code": _f("str", "", True, "the look"),
        "groups": _f("list", [], False, "the animation x view groups to evaluate (run/side, die/front, ...; empty = every group of the look)"),
        "tiers": _f("list", [0, 1], False, "0 deterministic flags + geometry, 1 the local vision model on the flagged frames + one clean frame a group, 2 Gemini (pass 98: through Antigravity, free, first; the local model then only checks what a failed Gemini call left) or a paid cloud eye on contact sheets"),
        "request": _f("str", "", False, "the request this evaluation belongs to (empty = a plain job)"),
        "cloud_dollars": _f("float", 0.0, False, "the request's ceiling for a PAID tier 2 (0 = a paid eye is off; Gemini through Antigravity costs nothing and runs at 0, capped by tiers[2].daily_calls)"),
        "backend": _f("str", "", False, "openai_chat | anthropic | gemini | fake (empty = the tier table's)"), "model": _f("str", "", False, "the model id (empty = the tier table's)"),
        "note": _f("str", "", False, "")},
        "help": "every frame of the look flagged (empty, footprint, jump, seam, silhouette; the stills' geometry), the flagged ones shown to the local vision model; findings.json + a sheet beside the job"},
    "sim": {"lane": "sim", "fields": {
        "hero": _f("str", "drifter", False, "the hero every run plays"),
        "players": _f("int", 10, False, "how many runs are played and averaged (1-100)"),
        "workers": _f("int", 0, False, "how many runs play at once: 0 = as many as the runs, at most the PC's logical processors - 2"),
        "limit": _f("int", 1500, False, "play seconds each run stops at (1500 = 25:00; boss fights and portal waits count)"),
        "board": _f("float", 1.5, False, "the Upgrade board preset: 0 none, 1.5 a quarter, 3 half, 6 full (talents wins when given)"),
        "talents": _f("json", {}, False, "the Upgrade board talent by talent: {talent: picks}, one letter a rank, its form (A the first, "
                                         "B the second), e.g. {\"grit\": \"AAB\"}; empty = the board preset"),
        "board_label": _f("str", "", False, "the board's name in the sim's header (\"my save\"; empty = the preset's, or custom)"),
        "death": _f("enum", "end", False, "end: the first death ends the run; ad: revive once with an ad, then end; keep: every death "
                                          "counted, the hero stood up again, played to the stop", ("end", "ad", "keep")),
        "fast": _f("bool", True, False, "the runner's sim mode (the purely visual work skipped, every rule kept) when it has one"),
        "seed": _f("int", 1, False, "run k plays seed + k - 1"),
        "map": _f("str", "red_canyon", False, "the map (its saved file)"),
        "stage": _f("int", 1, False, "pass 87: the stage every run plays, 1-based (each stage is its own run)"),
        "fps": _f("int", 60, False, "--fixed-fps: 60 = a weapon can fire every frame as on the phone"),
        "note": _f("str", "", False, "a few words to find this sim in the history"),
        "bot": _f("json", {}, False, "pass 80: the bot's options {preset, key: value} (tools/sim_batch.py BOT_KEYS); empty = the runner's default (Explorer)"),
        "synthetic": _f("bool", False, False, "tests only: made-up players, no Godot")},
        "help": "N headless runs of the real game driven by a bot, averaged per second of play (the Sim tab)"},
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
        self.timed_out = ""   # pass 70: the reason a step was killed for running over its time limit


# ---------------------------------------------------------------- persistence

def _read_queue(path):
    """The queue file parsed, or None (missing, not JSON, or held mid-replace by its writer: a few quick tries)."""
    for i in range(6):
        try:
            with open(path, "r", encoding="utf-8") as f:
                d = json.load(f)
            if isinstance(d, dict) and isinstance(d.get("jobs"), _LIST):
                return {"rev": int(d.get("rev", 0)), "jobs": [j for j in d["jobs"] if isinstance(j, dict) and j.get("id")]}
            return None
        except (OSError, ValueError):
            time.sleep(0.02)
    return None


def _load():
    global _state
    d = _read_queue(QUEUE_FILE)
    if d is not None:
        _state = d
        return True
    _state = {"rev": 0, "jobs": []}
    return False


def _save():
    with _lock:
        if _readonly is not None:   # a read-only editor never writes the queue
            return _state["rev"]
        if not _inited:
            raise RuntimeError("jobs.init() has not run in this process: the queue is not written (a script importing jobs.py)")
        if not _queue_file_ok():   # pass 97 (lane PROGRESS): a test that re-pointed JOBS_DIR alone wrote its fake queue over the real one
            _log("jobs: %s is not inside JOBS_DIR %s: the queue is not written" % (QUEUE_FILE, JOBS_DIR))
            return _state["rev"]
        _state["rev"] += 1
        os.makedirs(JOBS_DIR, exist_ok=True)
        tmp = QUEUE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            json.dump(_state, f, indent=1, ensure_ascii=False)
        # Windows refuses the replace while another process (a read-only editor's poll) holds the file open for a
        # millisecond: try again a few times; after that the queue stays in memory until the next save
        for i in range(40):
            try:
                os.replace(tmp, QUEUE_FILE)
                break
            except PermissionError:
                if i == 39:
                    _log("jobs: queue.json is held open by another process; the queue stays in memory until the next save")
                    break
                time.sleep(0.05)
        return _state["rev"]


def _queue_file_ok():
    """pass 97 (lane PROGRESS): QUEUE_FILE is JOBS_DIR's own queue.json (selftest_VACE95 pointed JOBS_DIR at a temp folder
    and left QUEUE_FILE on the real one: every full selftest run wrote its two-job fake over Garry's queue)."""
    try:
        return os.path.normcase(os.path.abspath(os.path.dirname(QUEUE_FILE))) == os.path.normcase(os.path.abspath(JOBS_DIR))
    except Exception:   # noqa: BLE001
        return False


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


def _badge_tag(job):
    """pass 68 (D7): the tag a badge job's candidates are keyed by (<id>_portrait_<tag>_c<k>): the last four letters and
    digits of its id (gen_badge_cands.cand_tag of --tag / ASSET_JOB_ID), so a new job never gets an old job's pictures
    back from the cache (a requeue moves its own aside: requeue)."""
    s = re.sub(r"[^A-Za-z0-9]", "", str((job or {}).get("id") or ""))
    return s[-4:] if s else "x"


def _badge_keys(job, n=None):
    t = job.get("target") or {}
    n = int((job.get("spec") or {}).get("seeds") or 4) if n is None else n
    return ["%s_portrait_%s_c%d" % (t.get("id", ""), _badge_tag(job), k) for k in range(n)]


def _icon_set(job):
    """The folder an icon_cands job paints into (tools/dl/icons<set>/): the job's own. A later attempt (--attempt N, from
    job.json) has gen_icon_cands move the earlier candidates into <folder>/attempt<N-1>/ and paint new ones on new seeds
    (pass 68, lane G), so the folder's root holds this attempt's only."""
    return "_le_" + job["id"]


def _icon_folder(job):
    sset = str(((job.get("plan") or {}).get("icon_job") or {}).get("set") or ("_le_" + job["id"]))
    return os.path.join(DL, "icons" + sset)


def _title_stem(job):
    """pass 68 (D7): the stem of a title job's candidates under tools/dl/title_heroes/ (gen_title_heroes.cand_stem):
    <id> for the hero's own cut-out (the base strip's code is the hero's own, as the tool treats it), <id>_<x> for a
    look's (its `variant`), then the job's tag (_badge_tag; pass 68 review: a second title job for the same hero or look
    paints files of its own instead of overwriting the first's, and each job's Install picks its own)."""
    t = job.get("target") or {}
    v = str((job.get("spec") or {}).get("variant") or "").strip()
    if v and _look_state(dict(t, kind=t.get("kind") or "hero", code=v))["is_base"]:
        v = ""
    return t.get("id", "") + ("_" + _letter(v) if v else "") + "_" + _badge_tag(job)


def cache_keys(method, spec, target, doc=None):
    """The still and clip cache keys a look job reads or makes (gen_art.py's sk/ak/ck, gen_ctl's key), for re-roll offers."""
    cid, code = target.get("id", ""), target.get("code", "")
    recipe = (spec or {}).get("recipe") or {}
    doc = doc or {}
    stills, clips = [], []
    if method in ("creature_free2", "creature_pose2", "creature_free8", "creature_proc", "creature_pictures"):
        st = recipe.get("stills", doc.get("stills"))
        sk = cid + ("_" + str(st) if st else "")
        ak = cid + ("_" + _code_part(code) if code else "")
        stills = [sk + "_front", sk + "_back", sk + "_dead"]
        if method == "creature_free8" or int(recipe.get("directions", doc.get("directions", 2))) == 8:
            stills += [sk + "_side", sk + "_bd", sk + "_fd"]
            clips += [ak + "_walk_side", ak + "_walk_bd", ak + "_walk_fd"]
        procedural = method in ("creature_proc", "creature_pictures")   # pass 91: no clips for either
        if method == "creature_pose2" or (recipe.get("pose", doc.get("pose")) and not procedural):
            clips = [ak + "_pose_f", ak + "_pose_b"] + clips
        elif not procedural and str(recipe.get("walk", doc.get("walk", ""))) != "hop":
            clips = [ak + "_walk_f", ak + "_walk_b"] + clips
        death = str(recipe.get("death", doc.get("death", "")))
        if death == "clip":
            clips.append(ak + "_fall")
        elif death.startswith("pose:"):
            clips.append(ak + "_death")
    elif method in ("hero_pose5", "hero_fit", "hero_puppet"):
        skeys = recipe.get("still_keys") if isinstance(recipe.get("still_keys"), dict) else (doc.get("still_keys") if isinstance(doc.get("still_keys"), dict) else {})
        ck = cid + ("_" + _code_part(code) if code else "")
        # pass 68 (D1): a look with its own `stills` slug paints <id>_<slug>_<view> (gen_art's hero branch); still_keys
        # still wins per view; no slug = the hero's own paintings
        st = recipe.get("stills", doc.get("stills"))
        hk = cid + ("_" + str(st) if st else "")
        for v in HERO_VIEWS:
            stills.append(str(skeys.get(v, hk + "_" + v)))
        stills.append(str(skeys.get("cheer", hk + "_cheer")))
        for v in HERO_VIEWS:
            stills.append(str(skeys.get("hurt_" + v, hk + "_hurt_" + v)))
        stills.append(str(skeys.get("dead", hk + "_dead")))
        if not code:
            stills.append(cid + "_portrait")
        clips = [ck + "_pose_run_" + v for v in ("back", "front", "side", "bd", "fd")]
        if method == "hero_puppet":
            # pass 71: a view walked on the puppet's depth guide is cached as gen_art's ctl_cycle names it
            ctl = recipe.get("ctl_drivers") if isinstance(recipe.get("ctl_drivers"), dict) else None
            dv = [v for v in ctl if ctl.get(v)] if ctl is not None else puppet_spec(spec, target)["depth_views"]
            clips = [ck + ("_ctl_run_" if v in dv else "_pose_run_") + v for v in ("back", "front", "side", "bd", "fd")]
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

    if method in ("creature_free2", "creature_pose2", "creature_free8", "creature_proc", "creature_pictures"):
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
        if str(recipe.get("death", doc.get("death", ""))) != "shatter":   # pass 91: a shatter paints no dead still
            add("dead", stills[2], "still")
        for k in clips:
            if k.endswith("_fall"):
                add("fall", k, "clip")
            elif k.endswith("_death"):
                add("death", k, "clip")
        add("pack", "", "pack")
    elif method in ("hero_pose5", "hero_puppet"):
        stills, clips = keys["stills"], keys["clips"]
        if method == "hero_puppet":
            st += puppet_stage_defs(spec, target)   # pass 71: the puppet's stages, then the walks as hero_pose5's
        names = _LIST(HERO_VIEWS) + ["cheer"] + ["hurt_" + v for v in HERO_VIEWS] + ["dead"]
        for n, k in zip(names[:6], stills[:6]):
            add(n, k, "still")
        for n, k in zip(("back", "front", "side", "bd", "fd"), clips):
            add(("ctl_run_" if "_ctl_run_" in k else "pose_run_") + n, k, "clip")
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
    if kind == "sim":
        return sim_eta(job)   # pass 77 (lane SIMUI): from the measured speed of the last sims
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
    med = _measured_eta(job, key, med)   # pass 97 (lane PROGRESS, OPS-02): the measured median at >= 5 samples; job["eta_source"] says which
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
    if job["kind"] == "sim":
        return sim_title(job)   # pass 77 (lane SIMUI)
    if job["kind"] in ("register", "import"):
        return "%s %s" % (job["kind"], ", ".join((job.get("spec") or {}).get("targets") or []))
    if job["kind"] == "launch":
        s = job.get("spec") or {}
        return "Test in game: " + ", ".join(x for x in (s.get("character"), s.get("spawn_enemy"), s.get("variant"), s.get("look")) if x)
    if job["kind"] in ("driver_pose", "driver_depth", "driver_tweak"):
        return "%s %s" % (job["kind"], (job.get("spec") or {}).get("name", ""))
    if job["kind"] in ("ref_probe", "ref_render", "ref_limbs"):
        return "%s %s" % (job["kind"], os.path.basename((job.get("spec") or {}).get("src", "")))
    return "%s%s · %s" % (name, (" " + code) if code else "", job["kind"])


# ---------------------------------------------------------------- validation

def _coerce(name, f, v):
    t = f["type"]
    if v is None:
        # pass 71 (lane PLE): a copy: a spec without a recipe got THE default dict, and _seed_recipe then wrote one look's
        # stills and seeds into every later spec without one
        d = f.get("default")
        return json.loads(json.dumps(d)) if isinstance(d, (dict, _LIST)) else d
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
        # pass 70 (the Bandit check): Stills is the look's slug, never the picture (that goes in Reference)
        for where, v in (("stills", out.get("stills")), ("recipe.stills", (out.get("recipe") or {}).get("stills") if isinstance(out.get("recipe"), dict) else None)):
            prob = _VOCAB.stills_problem(v if v != "" else None)
            if prob:
                raise ValueError("%s: %s" % (where, prob))
        if out["method"] in ("front_from_picture",) and not out.get("pick") and not (out.get("ref") and out.get("prompt") and out.get("stills")):
            raise ValueError("front_from_picture needs ref, prompt and stills (the slug the pick is cached under)")
        rrc = (out.get("recipe") or {}).get("recolour") if isinstance(out.get("recipe"), dict) else None
        if out["method"] == "recolour" and not (out.get("recolour") or {}).get("from") and isinstance(rrc, dict) and rrc.get("from"):
            # the job form writes the recolour block as recipe fields (methods.json recolour.*): the plan reads spec.recolour
            out["recolour"] = dict(rrc)
        if out["method"] == "recolour" and not (out.get("recolour") or {}).get("from"):
            raise ValueError("recolour needs recolour.from: the look to recolour")
    if kind == "sim":
        out = sim_check(out)   # pass 77 (lane SIMUI): the settings' ranges (tools/sim_batch.clean_settings)
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
        if kind == "icon_cands" and target.get("kind") == "hero":
            # pass 68: icon_cands' pick wrote a square icon over the hero's round badge
            raise ValueError("a hero's icon is the round badge: queue hero_badge")
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
    if job.get("method") == "hero_puppet" and job.get("lane") == "local":
        # pass 71: the local lane holds no ComfyUI lock: puppet.py (and anything it calls) takes it itself if it must
        env.pop("LOCK_HELD_COMFY", None)
        env.pop("COMFY_LOCK_HELD", None)
    if job.get("kind") == "install":
        src = _find(str(spec.get("source_job", ""))) or _archived_raw(str(spec.get("source_job", "")))   # pass 97 (lane PROGRESS): an archived source too
        if src is not None and src.get("kind") in ("hero_badge", "hero_title"):
            # pass 68 (D7): the badge candidates (and, since the review, the title cut-outs) are keyed by the job that
            # painted them (tag = ASSET_JOB_ID's last 4): the pick runs under that job's id so the tool finds them by the
            # same rule
            env["ASSET_JOB_ID"] = src["id"]
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
    if kind == "look" and method == "hero_puppet" and job.get("puppet_next") != "walks":
        # pass 71: one puppet.py phase on the job's lane (tools/asset_job.py imports puppet and calls main with argv)
        lane = job.get("lane") if job.get("lane") in ("comfy", "local") else puppet_lane(job)
        argv = puppet_argv(job, lane)
        # the walks that follow (gen_art on the look), for a dry run of the whole job (asset_job --dry-run)
        wargv = ["--no-import", "--only", cid, "--variant=" + code] + (["--skip-qa"] if spec.get("skip_qa") else []) + _model_argv(spec)
        if int(spec.get("seed") or 0):
            wargv.append("--seed=%d" % int(spec["seed"]))
        p.update(tool="puppet", call="main", argv=argv, lock="comfy" if lane == "comfy" else None, lane=lane,
                 equiv=_equiv_py("puppet", argv), walks={"argv": wargv, "type": tf or "characters", "folder": p["folder"], "id": cid})
        prob = puppet_problem(spec, t)
        if prob:
            p["error"] = prob
    elif kind == "look":
        if method in ("hero_pose5", "hero_fit", "creature_free2", "creature_pose2", "creature_free8", "creature_proc", "creature_pictures", "hero_puppet"):
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
            r = _runner_from_methods("hero_pose5" if method == "hero_puppet" else method, {"id": cid, "code": code, "folder": p["folder"], "type": tf or "", "seed": int(spec.get("seed") or 0),
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
            if int(spec.get("first_seed") or 0):
                argv.append("--first-seed=%d" % int(spec["first_seed"]))   # pass 72: the side / view candidates' first seed
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
                if int(spec.get("first_seed") or 0):
                    argv += ["--first-seed", str(int(spec["first_seed"]))]   # pass 72
                if spec.get("skip_qa"):
                    argv.append("--skip-qa")
            p.update(tool="gen_edit_stills", call="main", argv=argv, equiv=_equiv_py("gen_edit_stills", argv))
        elif method == "recolour":
            rc = spec.get("recolour") or {}
            src_code = str(rc.get("from", ""))
            steps = []
            picked = bool(_look_state(t)["entry"].get("icon_picked"))
            for suffix in ("sprite", "icon"):
                src = os.path.join(folder, "%s_%s_%s.png" % (cid, suffix, _letter(src_code)))
                dst = os.path.join(folder, "%s_%s_%s.png" % (cid, suffix, _letter(code)))
                if suffix == "icon" and picked and os.path.isfile(dst):
                    # pass 68 (review): the look's icon was picked from candidates (icon_picked): kept, as gen_art and
                    # gen_ctl keep it
                    continue
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
        icon_job = {"kind": tf or "", "id": cid, "subject": str(spec.get("subject", "")).strip(), "set": _icon_set(job)}
        for k in ("ref", "screen", "style", "file"):
            v = str(spec.get(k) or "").strip()
            if v:
                icon_job[k] = v
        if icon_job.get("screen") == "green":
            icon_job.pop("screen", None)
        attempt = int(job.get("attempt", 1) or 1)
        first = int(spec.get("first_seed") or 0)
        more = (["--dev"] if spec.get("dev") else []) + (["--attempt", str(attempt)] if attempt > 1 else []) + (["--first-seed", str(first)] if first else [])
        p.update(tool="gen_icon_cands", call="paint", argv=["--only", key, "--seeds", str(int(spec.get("seeds") or 4))] + more,
                 key=key, icon_job=icon_job, seeds=int(spec.get("seeds") or 4), dev=bool(spec.get("dev")), first_seed=first)
        p["equiv"] = "python tools/gen_icon_cands.py --only %s --seeds %d%s   (JOBS[%r] = %s)" % (
            key, p["seeds"], "".join(" " + a for a in more), key, json.dumps(icon_job, ensure_ascii=False))
    elif kind == "hero_badge":
        # pass 68 (D7): every word and the reference go to the tool explicitly (the server filled the empty ones); a field
        # holding only a space is left out
        argv = ["--id", cid, "--seeds", str(int(spec.get("seeds") or 4))]
        if int(spec.get("first_seed") or 0):
            argv += ["--first-seed", str(int(spec["first_seed"]))]
        for k, flag in (("character", "--character"), ("prompt", "--prompt"), ("ref", "--ref"), ("variant", "--variant")):
            v = str(spec.get(k) or "").strip()
            if v:
                argv += [flag, v]
        if float(spec.get("head_width") or 0) > 0:
            argv += ["--head-width", str(spec["head_width"])]
        if spec.get("top_pad") not in (None, "", 0.03):
            argv += ["--top-pad", str(spec["top_pad"])]
        if spec.get("skip_qa"):
            argv.append("--skip-qa")
        # the candidates' tag (the tool takes the last four letters and digits) and a re-run's attempt (new seeds), named
        # so the equiv line is the command that was run
        argv += ["--tag", str(job["id"])]
        if int(job.get("attempt", 1) or 1) > 1:
            argv += ["--attempt", str(int(job["attempt"]))]
        p.update(tool="gen_badge_cands", call="main", argv=argv, equiv=_equiv_py("gen_badge_cands", argv),
                 tag=_badge_tag(job), variant=str(spec.get("variant") or "").strip())
    elif kind == "hero_title":
        # pass 72: 0 (the form's default) = the tool's own start, 11 (cand_seeds.start)
        seeds, first = int(spec.get("seeds") or 4), int(spec.get("first_seed") or 0) or 11
        argv = ["--only", cid, "--seeds=%d" % seeds, "--first-seed=%d" % first]
        # pass 68 (D7): asset_job calls paint(hid, seeds, first, **kwargs) with the same names as the flags
        kw = {}
        for k, flag in (("character", "--character"), ("pose", "--pose"), ("holds", "--holds"), ("camera", "--camera"), ("ref", "--ref"),
                        ("extra_ref", "--extra-ref"), ("extra_words", "--extra-words"), ("variant", "--variant")):
            v = str(spec.get(k) or "").strip()
            if v:
                argv += [flag, v]
                kw[k] = v
        # pass 68 review: the cut-outs are keyed by the job (<stem>_<tag>_<n>.png, the tag as the badges'), named so the
        # equiv line is the command that was run
        argv += ["--tag", str(job["id"])]
        if int(job.get("attempt", 1) or 1) > 1:
            argv += ["--attempt", str(int(job["attempt"]))]   # a re-run's new seeds (asset_job passes attempt= from job.json)
        p.update(tool="gen_title_heroes", call="paint", argv=argv, hid=cid, seeds=seeds, first=first, kwargs=kw, tag=_badge_tag(job))
        p.update(kw)
        p["equiv"] = _equiv_py("gen_title_heroes", p["argv"])
    elif kind == "driver_tweak":
        # pass 70: one change to a copy of a library driver (no Blender, no ComfyUI)
        p.update(mode="steps", lock=None)
        src_name = re.sub(r"[^A-Za-z0-9_.-]", "", str(spec.get("src", "")))
        name = re.sub(r"[^A-Za-z0-9_.-]", "", str(spec.get("name", "")))
        src_dir, dst_dir = os.path.join(DRIVERS, src_name), os.path.join(DRIVERS, name)
        op = str(spec.get("op") or "scale")
        views = ",".join(v for v in re.split(r"[\s,]+", str(spec.get("views") or "back,bd")) if v in ("front", "fd", "side", "bd", "back")) or "back,bd"
        if not src_name or not name or src_name == name:
            p.update(steps=[], equiv="", error="driver_tweak needs a source driver and a new, different name")
        elif os.path.exists(dst_dir):
            p.update(steps=[], equiv="", error="tools/dl/drivers/%s exists already: give the tweaked driver a free name" % name)
        else:
            if op == "scale":
                args = ["scale=%g" % float(spec.get("scale") or 0.85), "views=" + views]
                tool = "pose_scale.py"
            elif op == "spread":
                args, tool = ["spread=%g" % float(spec.get("spread") or 0.06)], "pose_spread.py"
            elif op == "occlude":
                args, tool = [], "pose_occlude.py"
            else:
                args, tool = ["level=%g" % float(spec.get("level") if spec.get("level") not in (None, "") else 0.3), "views=" + views], "pose_shoulders.py"
                if str(spec.get("tuck") or "").strip():
                    args.append("tuck=%g" % float(str(spec["tuck"]).strip()))
            p["steps"] = [[PY, os.path.join(TOOLS, tool), _rel(src_dir), _rel(dst_dir)] + args]
            p["equiv"] = "python tools/%s %s %s %s" % (tool, _rel(src_dir), _rel(dst_dir), " ".join(args))
    elif kind in ("driver_pose", "driver_depth", "ref_probe", "ref_render", "ref_limbs"):
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
            # pass 69 (lane ART's options): a sprint's wider swing and lean (amp, amp_bones, lean)
            if spec.get("amp") not in (None, "") and abs(float(spec["amp"]) - 1.0) > 1e-6:
                kv.append("amp=%g" % float(spec["amp"]))
                if str(spec.get("amp_bones") or "").strip():
                    kv.append("amp_bones=%s" % str(spec["amp_bones"]).strip())
            if spec.get("lean") not in (None, "") and abs(float(spec["lean"])) > 1e-6:
                kv.append("lean=%g" % float(spec["lean"]))
            steps = [[bl, "-b", "--python", os.path.join(TOOLS, "pose_driver.py"), "--"] + kv,
                     [PY, os.path.join(TOOLS, "pose_driver.py"), "draw", _rel(out)]]
            equiv = '"$BLENDER" -b --python tools/pose_driver.py -- %s && python tools/pose_driver.py draw %s' % (" ".join(kv), _rel(out))
            # pass 69: the shoulders levelled with the neck into <name>_lvl (tools/pose_shoulders.py: Fadeaway's sagging
            # back run, the side runs' raised shoulder)
            if str(spec.get("shoulders") or "").strip():
                sk = ["level=%s" % str(spec["shoulders"]).strip(), "views=%s" % (str(spec.get("shoulder_views") or "back,bd").strip() or "back,bd")]
                if str(spec.get("tuck") or "").strip():
                    sk.append("tuck=%s" % str(spec["tuck"]).strip())
                steps.append([PY, os.path.join(TOOLS, "pose_shoulders.py"), _rel(out), _rel(out) + "_lvl"] + sk)
                equiv += " && python tools/pose_shoulders.py %s %s_lvl %s" % (_rel(out), _rel(out), " ".join(sk))
            p["steps"] = steps
            p["equiv"] = equiv
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
            kv += made_motion_args(spec)
            if int(spec.get("smooth") or 0) > 0:
                kv.append("smooth=%d" % int(spec["smooth"]))
            if str(spec.get("skin") or "") == "capsule":
                kv.append("skin=capsule")
                if spec.get("skin_radius") not in (None, "") and abs(float(spec["skin_radius"]) - 0.06) > 1e-9:
                    kv.append("skin_radius=%g" % float(spec["skin_radius"]))
            if spec.get("inplace") is False:
                kv.append("inplace=0")
            # pass 93 (lane LEGS): a made motion writes where every foot goes (tips.json); a made walk is then checked
            # (tools/gait_check.py: gait_check.png, the foot paths per view, and which way each foot steps)
            made = str(spec.get("mode") or "cycle") in ("gait", "flip_curl")
            if made:
                kv.append("tips=1")
            p["steps"] = [[bl, "-b", "--python", os.path.join(TOOLS, "blender_depth_drivers.py"), "--"] + kv]
            p["equiv"] = '"$BLENDER" -b --python tools/blender_depth_drivers.py -- ' + " ".join(kv)
            if str(spec.get("mode") or "cycle") == "gait":
                p["steps"].append([PY, os.path.join(TOOLS, "gait_check.py"), _rel(out)])
                p["equiv"] += " && python tools/gait_check.py " + _rel(out)
        elif kind == "ref_limbs":
            # pass 92 (lane SPIDER): the fixed model as a new upload of its own, then its probe beside it
            name = re.sub(r"[^a-z0-9_]+", "_", str(spec.get("name", "")).lower()).strip("_")
            d = os.path.join(UPLOADS, "3d", name)
            out = os.path.join(d, name + ".glb")
            kv = ["src=" + src, "out=" + _rel(out), "shot=" + _rel(os.path.join(d, "top.png"))]
            for k in ("rest", "clone", "turn", "forward"):
                if str(spec.get(k) or "").strip():
                    kv.append("%s=%s" % (k, str(spec[k]).strip()))
            pk = ["src=" + _rel(out), "out=" + _rel(d), "mode=probe"] + (["forward=" + str(spec["forward"]).strip()] if str(spec.get("forward") or "").strip() else [])
            if not name:
                p.update(steps=[], equiv="", error="ref_limbs needs a name for the new model")
            elif os.path.exists(out):
                p.update(steps=[], equiv="", error="tools/dl/uploads/3d/%s exists already: choose another name" % name)
            else:
                p["steps"] = [[bl, "-b", "--python", os.path.join(TOOLS, "blender_limb_clone.py"), "--"] + kv,
                              [bl, "-b", "--python", os.path.join(TOOLS, "blender_ref.py"), "--"] + pk]
                p["equiv"] = ('"$BLENDER" -b --python tools/blender_limb_clone.py -- ' + " ".join('"%s"' % a if ";" in a else a for a in kv)
                              + ' && "$BLENDER" -b --python tools/blender_ref.py -- ' + " ".join(pk))
        else:
            slug_dir = os.path.dirname(src) if os.path.dirname(src) else os.path.join(UPLOADS, "3d", os.path.splitext(os.path.basename(src))[0])
            if not os.path.isabs(slug_dir):
                # a repo-relative src (tools/dl/uploads/3d/<slug>/<file>): resolve against the repo, not the process's
                # working directory (the selftest runs from tools/level_editor and doubled the path)
                slug_dir = os.path.join(_root, slug_dir)
            slug_dir = loose_slug_dir(slug_dir, src)
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
    elif kind in ("frames_repair", "frames_export"):
        p.update(_frames_plan(job, asset_dir))   # pass 95 (lane VACE): the Frames view's repair and export
    elif kind == "evaluate":
        p.update(_evaluate_plan(job, asset_dir))   # pass 96 (lane LOOP): the loop's evaluator on a look
    elif kind == "sim":
        p.update(sim_plan(job))   # pass 77 (lane SIMUI): one tools/sim_batch.py process, its own sim lock
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
        src = _find(str(spec.get("source_job", ""))) or _archived_raw(str(spec.get("source_job", "")))   # pass 97 (lane PROGRESS): an archived source too
        choice = str(spec.get("choice", ""))
        if src is None:
            p.update(mode="steps", lock=None, steps=[], equiv="", error="the source job %r is gone" % spec.get("source_job"))
        elif src["kind"] == "icon_cands":
            sp = src.get("plan") or {}
            icon_job = dict(sp.get("icon_job") or {})
            if "variant" in spec:
                # pass 70: installed into the look the picker names ("" = the creature's own icon)
                if spec["variant"] and not _look_state(dict(t, code=spec["variant"]))["is_base"]:
                    icon_job["variant"] = spec["variant"]
                else:
                    icon_job.pop("variant", None)
            if spec.get("icon_file"):
                # pass 76 (lane ICON): the install's own new file; keep_old: never written over a different picture
                icon_job["file"] = spec["icon_file"]
                icon_job["keep_old"] = True
            p.update(tool="gen_icon_cands", call="pick", lock=None, argv=["--pick", "%s=%s" % (sp.get("key", cid), choice)], key=sp.get("key", cid),
                     icon_job=icon_job, choice=choice, id=src["target"].get("id", ""), type=sp.get("type", ""))
            p["equiv"] = "python tools/gen_icon_cands.py --pick %s=%s   (JOBS[%r] = %s)" % (p["key"], choice, p["key"], json.dumps(p["icon_job"], ensure_ascii=False))
        elif src["kind"] == "hero_badge":
            hid = src["target"].get("id", "")
            variant = str((src.get("spec") or {}).get("variant") or "").strip()
            if "variant" in spec:
                variant = "" if _look_state(dict(t, code=spec["variant"]))["is_base"] else str(spec["variant"] or "")   # pass 70: the picker's look
            argv = ["--id", hid, "--pick", choice]
            if variant:
                argv += ["--variant", variant]   # pass 68 (D7, D8): <id>_icon_<x>.png and the sidecar's entry {icon}
            if float(spec.get("head_width") or 0) > 0:
                argv += ["--head-width", str(spec["head_width"])]
            if spec.get("top_pad") not in (None, "", 0.03):
                argv += ["--top-pad", str(spec["top_pad"])]
            # the candidates are keyed by the job that painted them (<id>_portrait_<tag>_c<k>): the pick names that job
            # (--tag; its ASSET_JOB_ID is that job's too, _asset_env)
            argv += ["--tag", str(src["id"])]
            if spec.get("icon_file"):
                argv += ["--icon-file", str(spec["icon_file"])]   # pass 76 (lane ICON): its own new file, nothing overwritten
            p.update(tool="gen_badge_cands", call="main", lock=None, argv=argv, equiv=_equiv_py("gen_badge_cands", argv), id=hid, type="characters",
                     variant=variant, source_job=src["id"], tag=_badge_tag(src))
        elif src["kind"] == "hero_title":
            hid = src["target"].get("id", "")
            variant = str((src.get("spec") or {}).get("variant") or "").strip()
            pick_as = choice
            if "variant" in spec:
                # pass 70: the picker's look; the candidate is named by its file (its stem is the source job's look's)
                variant = "" if _look_state(dict(t, code=spec["variant"]))["is_base"] else str(spec["variant"] or "")
                url = next((str(c.get("url", "")) for c in (src.get("choices") or []) if str(c.get("id")) == choice), "")
                if url:
                    pick_as = os.path.basename(url.split("?")[0])
            argv = ["--pick", "%s=%s" % (hid, pick_as)] + (["--variant", variant] if variant else [])
            # pass 68 review: the cut-outs are keyed by the job that painted them (<stem>_<tag>_<n>.png): the pick names
            # that job (--tag; its ASSET_JOB_ID is that job's too, _asset_env), so it installs that job's own picture
            argv += ["--tag", str(src["id"])]
            p.update(tool="gen_title_heroes", call="pick", lock=None, argv=argv, hid=hid, choice=choice, id=hid, type="characters",
                     variant=variant, equiv=_equiv_py("gen_title_heroes", argv), source_job=src["id"], tag=_badge_tag(src))
        else:
            p.update(mode="steps", lock=None, steps=[], error="nothing to install from a %s job" % src["kind"])
    return p


def _frames_plan(job, asset_dir):
    """pass 95 (lane VACE): a frames_repair runs tools/vace_repair.py on the job's repair.json under the comfy lock
    (the step told the lock is held, as an asset job is: env_steps), a frames_export runs tools/frames_store.py export
    on the local lane; both write the job's result.json (the repair's sheet for the card, the export's entry for the
    merge), the export's entry landing through merge_look like a look's."""
    kind, spec = job["kind"], job.get("spec") or {}
    os.makedirs(asset_dir, exist_ok=True)
    env = {"ASSET_JOB_SIDECAR": os.path.join(asset_dir, "result.json"), "ASSET_JOB_ID": job["id"], "ASSET_JOB_NAME": _user_folder(job),
           "PYTHONIOENCODING": "utf-8", "PYTHONUNBUFFERED": "1"}
    if kind == "frames_repair":
        rj = os.path.join(asset_dir, "repair.json")
        rec = {k: spec.get(k) for k in ("kind", "id", "code", "anim", "view", "slots", "prompt", "seed", "window", "size", "note", "guide", "free_fill")}
        rec["job"] = job["id"]
        with open(rj, "w", encoding="utf-8", newline="\n") as f:
            json.dump(rec, f, indent=1, ensure_ascii=False)
        env.update({"LOCK_HELD_COMFY": "1", "COMFY_LOCK_HELD": "1"})
        step = [PY, os.path.join(TOOLS, "vace_repair.py"), "--job", _rel(rj)]
        return {"mode": "steps", "lock": "comfy", "steps": [step], "env_steps": env,
                "equiv": "python tools/vace_repair.py --kind %s --id %s --code %s --anim %s --view %s --slots %s" % (
                    spec.get("kind"), spec.get("id"), spec.get("code"), spec.get("anim"), spec.get("view"), ",".join(str(s) for s in (spec.get("slots") or [])))}
    step = [PY, os.path.join(TOOLS, "frames_store.py"), "export", str(spec.get("kind", "")), str(spec.get("id", "")), str(spec.get("code", ""))]
    return {"mode": "steps", "lock": None, "steps": [step], "env_steps": env,
            "equiv": "python tools/frames_store.py export %s %s %s" % (spec.get("kind"), spec.get("id"), spec.get("code"))}


def _evaluate_plan(job, asset_dir):
    """pass 96 (lane LOOP, AI-07 / AI-03): an `evaluate` job runs tools/vision_eval.py --job on the job's evaluate.json on
    the local lane with no lock (the local eye is LM Studio on this PC; a cloud call is bounded by the ledger's ceilings
    inside the tool): it writes <job>/findings.json + findings_sheet.png and the sidecar result.json the card reads."""
    spec = job.get("spec") or {}
    os.makedirs(asset_dir, exist_ok=True)
    ej = os.path.join(asset_dir, "evaluate.json")
    rec = {k: spec.get(k) for k in ("kind", "id", "code", "groups", "tiers", "request", "cloud_dollars", "backend", "model", "note")}
    for k in ("scope", "slots", "cloud_backend", "calls_left", "fresh"):   # pass 98 (lane GEMINI): only when the spec has them
        if spec.get(k) not in (None, "", [], {}):
            rec[k] = spec[k]
    rec["job"] = job["id"]
    with open(ej, "w", encoding="utf-8", newline="\n") as f:
        json.dump(rec, f, indent=1, ensure_ascii=False)
    env = {"ASSET_JOB_SIDECAR": os.path.join(asset_dir, "result.json"), "ASSET_JOB_ID": job["id"], "PYTHONIOENCODING": "utf-8", "PYTHONUNBUFFERED": "1"}
    if spec.get("request"):
        env["ASSET_JOB_REQUEST"] = str(spec["request"])   # the ledger's request id
    step = [PY, os.path.join(TOOLS, "vision_eval.py"), "--job", _rel(ej)]
    equiv = "python tools/vision_eval.py --kind %s --id %s --code %s --tiers %s" % (spec.get("kind"), spec.get("id"), spec.get("code"),
                                                                                     ",".join(str(t) for t in (spec.get("tiers") or [0, 1])))
    if spec.get("groups"):
        equiv += " --groups " + ",".join(str(g) for g in spec["groups"])
    return {"mode": "steps", "lock": None, "steps": [step], "env_steps": env, "equiv": equiv}


def _evaluate_post(job, res):
    """pass 96 (lane LOOP): an evaluate job merges nothing; its findings' path goes on the job and its one line into the
    notes (the card shows it; REQ's step function reads <job>/findings.json). Returns (written, error) like _post."""
    info = (res or {}).get("info") or {}
    if not info.get("findings"):
        return {"file": "", "keys": [], "backup": "", "layout": "findings"}, "the evaluator wrote no findings (nothing landed)"
    try:   # pass 98 (lane GEMINI): the models' findings written per frame into the frames store (qa.eyes), the eye's line
        import eyes_io
        ew = eyes_io.on_findings(job, info)
        if ew.get("written") or ew.get("line") or ew.get("gemini_error"):
            with _lock:   # pass 98 review: the job record is dumped by _save under the lock
                job["eyes"] = ew
        if ew.get("gemini_error"):   # Garry: a Gemini failure checked by the local model instead is an error the log keeps
            _ev_emit("evaluator", "fallback", job=job.get("id"), rid=job.get("request") or (job.get("spec") or {}).get("request"),
                     look={"kind": (job.get("spec") or {}).get("kind"), "id": (job.get("spec") or {}).get("id"), "code": (job.get("spec") or {}).get("code")},
                     gemini_error=ew.get("gemini_error"), eye=ew.get("eye"), frames=ew.get("fallback_frames"))
    except Exception as e:   # noqa: BLE001  (a landing must not fail on the store)
        with _lock:
            job["eyes"] = {"written": 0, "error": "%s: %s" % (type(e).__name__, e)}
    with _lock:
        job["findings"] = info["findings"]
        if info.get("summary"):
            notes = job.setdefault("progress", {}).setdefault("notes", [])
            if info["summary"] not in notes:
                notes.append(str(info["summary"]))
    _ev_emit("evaluator", "verdict", job=job.get("id"), rid=job.get("request") or (job.get("spec") or {}).get("request"),   # pass 97 (lane PROGRESS, WF-02)
             look={"kind": (job.get("spec") or {}).get("kind"), "id": (job.get("spec") or {}).get("id"), "code": (job.get("spec") or {}).get("code")},
             gates=info.get("gates"), summary=info.get("summary"), dollars=info.get("dollars"), model_calls=info.get("model_calls"), findings=info["findings"])
    return {"file": "", "keys": [], "backup": "", "layout": "findings", "findings": info["findings"], "gates": info.get("gates"), "summary": info.get("summary")}, ""


def _evaluate_outputs(job, res):
    """pass 96 (lane LOOP): the card's outputs of an evaluate job: its sheets (info.outputs, the frames jobs' reader) and
    the findings record with its gates and summary."""
    info = (res or {}).get("info") or {}
    outs = _frames_outputs(job, res)
    if info.get("findings"):
        f = str(info["findings"])
        rec = {"label": "findings", "type": "json", "file": f,
               "detail": {"findings": f, "gates": info.get("gates"), "summary": info.get("summary"), "dollars": info.get("dollars"),
                          "model_calls": info.get("model_calls"), "tier2": info.get("tier2")}}
        if "tools/dl/" in f:
            rec["url"] = _url_dl(os.path.join(_root, f))
        outs.append(rec)
    return outs


def _derive(job):
    """cmd, equiv, lane, eta, cache_keys, the stage list and the job folder's job.json, from kind + method + target + spec."""
    kind, spec, t = job["kind"], job.get("spec") or {}, job.get("target") or {}
    method = job.get("method") or (spec.get("method") if kind == "look" else kind)
    job["method"] = method
    job["lane"] = "local" if (kind == "look" and method == "recolour") else puppet_lane(job) if (kind == "look" and method == "hero_puppet") else SPECS[kind]["lane"]
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
        {"stills": _badge_keys(job), "clips": []} if kind == "hero_badge" else
        {"stills": [], "clips": []})
    stages = expected_stages(method, spec, t, doc, job.get("phase", 1)) if kind == "look" else []
    if kind == "item_icon":
        stages = [{"name": "icon", "key": t.get("id", "") + "_icon2", "type": "still"}, {"name": "finish", "key": "", "type": "pack"}]
    elif kind in ("icon_cands", "hero_badge", "hero_title"):
        n = int(spec.get("seeds") or 4)
        stages = [{"name": "c%d" % k, "key": "", "type": "still"} for k in range(n)] + [{"name": "review", "key": "", "type": "pack"}]
        if kind == "hero_badge":
            for s, key in zip(stages[:n], _badge_keys(job, n)):
                s["key"] = key
    elif kind == "sim":
        stages = sim_stages(spec)   # pass 77 (lane SIMUI): the snapshot, one stage a run, the charts
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
    if method == "hero_puppet":
        puppet_mark(job)   # pass 71: a puppet stage whose files are on disk is done (a hero's puppet reused)
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
_inited = False       # init() ran: before that nothing writes queue.json (a script that imports jobs.py)


def _epoch(x):
    """A time as seconds: a float, or an ISO text as _now() writes it; None when neither."""
    if x in (None, ""):
        return None
    try:
        return float(x)
    except (TypeError, ValueError):
        pass
    try:
        return time.mktime(time.strptime(str(x)[:19], "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        return None


def _holder_is_editor(holder):
    """Whether the `jobs` lock's holder is a Level Editor that answers: the port in its note asked for /api/status
    (1.5 s). No owner record, a dead pid, or a port that does not answer as a Level Editor = a phantom (an editor
    closed by its window never ran stop(); Windows reuses pids), and the lock is ours to take."""
    if not holder or not holder.get("owner_file") or holder.get("alive") is False:
        return False
    m = re.search(r"port (\d+)", str(holder.get("note") or ""))
    if not m:
        return bool(holder.get("alive"))   # an older record without a port: a live pid is trusted
    try:
        with urllib.request.urlopen("http://127.0.0.1:%s/api/status" % m.group(1), timeout=1.5) as r:
            d = json.load(r)
        return bool(isinstance(d, dict) and d.get("ok") and "jobs_available" in d)
    except Exception:
        return False


def claim_queue(who="level_editor", port=None):
    """Become the one process that runs the job queue: the `jobs` lock (tools/dl/locks/jobs.lock), held while the
    server lives, its note naming the port. A second Level Editor started while the first runs finds it held by a
    live editor and runs READ-ONLY: it shows the queue as the file changes and refuses every change, and it neither
    recovers nor runs jobs. (2026-10-11: two level_editor.cmd windows shared one queue.json, each with its own
    picture of it, each writing the whole file; and recover() in a second server kills the first one's running job.)
    A lock left by an editor that is gone (no owner record, a dead or reused pid, a port that does not answer) is
    released and taken. None when claimed, else the holder's record."""
    global _queue_lock, _readonly
    if _queue_lock is not None:
        return None
    note = "the Level Editor that runs the job queue" + (" (port %d)" % int(port) if port else "")
    for attempt in range(2):
        lk = locks.acquire("jobs", who=who, note=note, wait=False, log=lambda m: None)
        if lk is not None:
            _queue_lock, _readonly = lk, None
            return None
        holder = locks.status("jobs") or {}
        if attempt == 0 and not _holder_is_editor(holder):
            locks.force_release("jobs")
            continue
        _readonly = holder or {"who": "another Level Editor"}
        return _readonly
    return _readonly


def _release_claim():
    global _queue_lock
    if _queue_lock is not None:
        try:
            _queue_lock.release()
        except Exception:
            pass
        _queue_lock = None


def _foreign_runner():
    """A running job that belongs to a live editor other than this process (one from before the queue lock, or one
    whose claim this process just took over): its record, else None. A job's `server_pid` says which server took it;
    an older record has none, so the lane lock's owner says, else the job's own live process. Such a job is never
    killed: this process goes read-only instead of running recover()."""
    for job in _state["jobs"]:
        if job.get("state") != "running":
            continue
        sp = job.get("server_pid")
        if sp:
            if int(sp) != os.getpid() and locks.pid_alive(int(sp)):
                return {"who": "another Level Editor (it runs %s)" % job["id"], "pid": int(sp), "since": _epoch(job.get("started")), "job": job["id"]}
            continue   # its editor is gone: recover() deals with the orphan
        plan = job.get("plan") or {}
        name = plan.get("lock") or (job.get("lane") if job.get("lane") in ("comfy", "godot") else None)
        if name:
            st = locks.status(name) or {}
            if st.get("owner_file") and st.get("alive") and st.get("job") == job["id"] and int(st.get("pid") or 0) != os.getpid():
                return {"who": "an older Level Editor (no queue lock yet; it runs %s)" % job["id"], "pid": int(st.get("pid") or 0), "since": st.get("since"), "job": job["id"]}
        pid = job.get("pid")
        if pid and locks.pid_alive(int(pid)):
            return {"who": "an older Level Editor (its job %s still runs)" % job["id"], "pid": int(pid), "since": _epoch(job.get("started")), "job": job["id"]}
    return None


def is_readonly():
    return _readonly is not None


def _writable():
    """Every change to the queue starts here: a read-only editor refuses with the holder named."""
    if _readonly is None:
        return
    o = _readonly
    t = _epoch(o.get("since"))
    since = time.strftime("%H:%M", time.localtime(t)) if t else "?"
    if o.get("view_only"):
        raise ValueError("this editor was started with --no-jobs: it shows the queue and changes nothing; use the editor that runs it")
    raise ValueError("another Level Editor runs the job queue (%s, pid %s, since %s): queue it from that page, or close it and "
                     "restart this one; this page only shows the queue" % (o.get("who") or "another Level Editor", o.get("pid") or "?", since))


def _sync_from_disk():
    """Read-only: the queue as the other editor last wrote it, loaded again whenever queue.json changed (the old
    picture stays when a read fails: the writer's replace may be in flight)."""
    global _disk_sig, _state
    if _readonly is None:
        return
    try:
        st = os.stat(QUEUE_FILE)
        sig = (st.st_mtime, st.st_size)
    except OSError:
        return
    if sig != _disk_sig:
        d = _read_queue(QUEUE_FILE)
        if d is not None:
            _state, _disk_sig = d, sig


def init(hooks, root=None, claim=True, port=None, view_only=False):
    """server.main(): the hooks dict, the queue loaded, the queue claimed (or this process read-only), recover() run by
    the claimant when no other editor's job is running. Starts no thread. `claim=False` (a tool, a test) neither claims
    nor recovers; `view_only` (--no-jobs) shows the queue and refuses every change."""
    global _hooks, _root, _inited, _readonly
    _hooks = hooks
    if root:
        _root = root
    _load()
    _inited = True
    if view_only:
        _readonly = {"who": "this editor, started with --no-jobs", "pid": os.getpid(), "since": time.time(), "view_only": True}
        return _state["rev"]
    if claim and claim_queue(port=port) is None:
        foreign = _foreign_runner()
        if foreign:
            # an editor from before the queue lock (or one whose phantom lock was just released) still runs a job:
            # do not take the queue from under it, and never kill its job
            _release_claim()
            _readonly = foreign
        else:
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
        return _public(j, LOG_TAIL_FULL, full=True) if j else _archived_public(job_id)   # pass 97 (lane PROGRESS): an archived id too


def _public(job, tail_n, full=False):
    out = {k: v for k, v in job.items() if k not in ("plan",)}
    out["plan"] = {k: v for k, v in (job.get("plan") or {}).items() if k != "env"}
    # pass 68 review: a queued candidate job the worker skips while its look paints the reference first (_waits_for_look);
    # the Jobs tab numbers these after the runnable ones of their lane
    out["held"] = bool(job.get("state") == "queued" and (_waits_for_look(job) or _frames_export_waits(job)))
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
        return [x for x in lines if not RE_COMFY_STEP.match(x)][-n:]   # pass 97 (lane PROGRESS): without ComfyUI's step lines
    except OSError:
        return []


# ---------------------------------------------------------------- pass 97 (lane LIVE, UI-02): the delta poll
# GET /api/jobs?since=<rev>&delta=1 answers what changed since <rev> instead of the whole list. Every record's served view
# (the record, `held` for a queued job, the log tail of a running one) is hashed at the first delta call after the
# queue's rev moved; a record whose hash changed gets `rev` = that rev, an id gone gets a tombstone, the id order is
# kept. Nothing here writes a record, queue.json, list() or _public: the non-delta answer stays exactly as it was (the
# per-record rev lives in this process's memory and is served on the delta's records only). Measured against a hash in
# _save on a 468-job queue: tools/dl/p97/LIVE/measure_delta.py, the numbers in status_LIVE.md.

_delta = {"rev": None, "floor": None, "state": None, "sig": {}, "at": {}, "tomb": {}, "order": None, "order_at": 0}


def _delta_view_sig(job):
    """One record's served view as a hash (process-local, never persisted): the record itself, `held` for a queued job
    (it follows other jobs and the disk), the log tail of a running job (it moves without the record)."""
    held = bool(job.get("state") == "queued" and (_waits_for_look(job) or _frames_export_waits(job)))
    tail = None
    if job.get("state") == "running":
        live = _live.get(job.get("id"))
        tail = tuple([x for x in live.tail][-LOG_TAIL_SHORT:]) if live is not None else tuple(_tail_from_file(job, LOG_TAIL_SHORT))
    try:
        text = json.dumps(job, ensure_ascii=False, default=str)
    except (TypeError, ValueError):
        text = repr(job)
    return hash((text, held, tail))


def _delta_scan():
    """Bring the per-record revs up to the queue's rev (under _lock): once per rev, whoever polls first pays it."""
    d = _delta
    rev = _state["rev"]
    if d["rev"] == rev and d["state"] is _state:
        return
    if d["state"] is not _state and d["rev"] is not None and rev < d["rev"]:
        # a queue loaded again with a lower rev (a test's fresh world, another file): the bookkeeping starts over
        d.update(rev=None, floor=None, sig={}, at={}, tomb={}, order=None, order_at=0)
    seen = []
    for j in _state["jobs"]:
        jid = j.get("id")
        seen.append(jid)
        s = _delta_view_sig(j)
        if d["sig"].get(jid) != s:
            d["sig"][jid] = s
            d["at"][jid] = rev
    have = set(seen)
    for jid in [k for k in d["sig"] if k not in have]:
        d["sig"].pop(jid, None)
        d["at"].pop(jid, None)
        d["tomb"][jid] = rev
    for jid in [k for k in d["tomb"] if k in have]:
        d["tomb"].pop(jid, None)
    if seen != d["order"]:
        if d["order"] is not None:
            d["order_at"] = rev
        d["order"] = seen
    if d["floor"] is None:
        d["floor"] = rev
    d["rev"], d["state"] = rev, _state


def list_delta(since_rev=None):
    """pass 97: {rev, changed: [served records, each with its `rev`], removed: [ids], delta: True}; + `order` (every id in
    the queue's order) when an id was added, removed or moved since `since_rev`; + `full: True` (everything, the page
    replaces its list) when `since_rev` is 0, older than this process's bookkeeping or ahead of the queue; + `unchanged:
    True` (nothing) when it is the queue's rev. list() stays the contract for every other caller."""
    with _lock:
        _sync_from_disk()
        _delta_scan()
        d = _delta
        rev = _state["rev"]
        try:
            since = int(since_rev) if since_rev is not None else 0
        except (TypeError, ValueError):
            since = 0
        out = {"rev": rev, "delta": True}
        if since > 0 and since == rev:
            out.update(changed=[], removed=[], unchanged=True)
            return out
        full = since <= 0 or since < (d["floor"] or 0) or since > rev
        jobs = _state["jobs"] if full else [j for j in _state["jobs"] if d["at"].get(j.get("id"), rev) > since]
        changed = []
        for j in jobs:
            p = _public(j, LOG_TAIL_SHORT)
            p["rev"] = d["at"].get(j.get("id"), rev)
            changed.append(p)
        out["changed"] = changed
        out["removed"] = [] if full else sorted(k for k, r in d["tomb"].items() if r > since)
        if full:
            out["full"] = True
        if full or d["order_at"] > since:
            out["order"] = [j.get("id") for j in _state["jobs"]]
        return out


CREATURE_STILL_METHODS =("creature_free2", "creature_pose2", "creature_free8", "creature_proc", "creature_pictures")
# pass 68 (D1, D2): the look methods whose stills gen_art keys by the recipe's `stills` slug (<id>_<slug>_<view>); hero_fit
# never gets one (it re-walks the hero's own paintings by design)
STILL_METHODS = CREATURE_STILL_METHODS + ("hero_pose5", "hero_puppet")
# the art words a new look inherits from its creature when its recipe leaves them out, so the prompt is in the look's
# own recipe where Garry can read and change it (lead, after the Armadillo's ARM-A came out identical to ARM-0)
INHERITED_WORDS = ("art_prompt", "motion", "dead_hint", "back_hint", "anim_negative", "view_hints", "screen")
# pass 68 (D3): the job form's re-roll radios ("none" or "" = nothing)
REROLL_MODES = ("stills", "seeds", "clips", "view", "clip", "stage")


def clip_view(key):
    """The view a look's clip cache key walks (pass 70, the one-view re-roll): a hero's <ck>_pose_run_<view>, gen_ctl's
    <key>_ctl_<view>, a creature's _walk_f / _pose_f (front), _walk_b / _pose_b (back), _walk_side / _bd / _fd; None for a
    death or a fall."""
    k = str(key)
    for mark in ("_pose_run_", "_ctl_run_", "_ctl_"):
        if mark in k:
            return k.rsplit(mark, 1)[-1]
    for suffix, view in (("_walk_f", "front"), ("_pose_f", "front"), ("_walk_b", "back"), ("_pose_b", "back"), ("_walk_side", "side"),
                         ("_walk_bd", "bd"), ("_walk_fd", "fd")):
        if k.endswith(suffix):
            return view
    return None
# pass 68 (D6): the jobs whose words and reference the server fills from the target (candidate_defaults)
CANDIDATE_KINDS = ("icon_cands", "hero_badge", "hero_title")


def _seed_offset(code):
    """A new look's own seed offset (pass 68, D2): 1 + crc32(code) % 9973; gen_art adds 104729 x it to seed_for(id), so two
    new looks with the same words never paint the same pictures (DM-E and DM-F did, at seed 12902)."""
    return 1 + zlib.crc32(str(code).encode("utf-8")) % 9973


def implied_method(kind, recipe, doc=None):
    """The method a look was made with: its recipe's `method`, else what its keys imply (the page's Assets.methodOf, the
    same rules): a hero is hero_fit with still_keys and pose_drivers, else hero_pose5; a creature with drivers is
    creature_ctl, a hop walk creature_proc, a pose creature_pose2, eight directions creature_free8, else creature_free2."""
    rec = recipe if isinstance(recipe, dict) else {}
    doc = doc if isinstance(doc, dict) else {}
    if rec.get("method"):
        return str(rec["method"])
    if kind == "hero":
        return ("hero_fit" if rec.get("still_keys") else "hero_pose5") if (rec.get("pose_drivers") or doc.get("pose_drivers")) else "hero_pose5"
    if rec.get("drivers"):
        return "creature_ctl"
    if (rec.get("walk") or doc.get("walk")) == "hop":
        return "creature_proc"
    if rec.get("pose") or doc.get("pose"):
        return "creature_pose2"
    try:
        if int(rec.get("directions") or doc.get("directions") or 0) == 8:
            return "creature_free8"
    except (TypeError, ValueError):
        pass
    return "creature_free2"


def _look_state(target, doc=None):
    """What the content JSON says of a look target: {doc, entry, recipe, base_code, is_base, is_new}. A NEW look is a code
    that is not the base strip's (`variant_base`) and whose entry has no `sprite` yet (a stub, a draft, or no entry)."""
    if doc is None:
        doc = content_doc(target.get("kind", ""), target.get("id", "")) if target.get("id") else None
    doc = doc if isinstance(doc, dict) else {}
    code = str(target.get("code") or "")
    base_code = str(doc.get("variant_base") or "")
    vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    entry = vs.get(code) if isinstance(vs.get(code), dict) else {}
    recipe = entry.get("recipe") if isinstance(entry.get("recipe"), dict) else {}
    is_base = bool(code) and code == base_code
    return {"doc": doc, "entry": entry, "recipe": recipe, "base_code": base_code, "is_base": is_base,
            "is_new": bool(code) and not is_base and not entry.get("sprite")}


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
    """What every look job writes into its recipe before it runs (pass 68, D2).
    - The job's `method` (front_from_picture records none: it paints a front for the look job that follows it).
    - The `painter` of every painting method (_painter_of; a recolour paints nothing).
    - A look whose stills gen_art paints (STILL_METHODS, heroes' hero_pose5 too):
      a NEW look (not the base strip's code, no `sprite` in its entry yet) gets its own `stills` slug (its letter) when the
      key is absent or None, and its own `seed_offset` when absent, so its paintings are its own and two new looks with
      the same words differ;
      an EXISTING look (a sprite, or the base) gets `stills: ""` when the key is absent: the paintings it was made from,
      never a letter (a re-roll from its card must not repaint them by accident), and no seed_offset (0).
      An explicit "" is kept: the creature's or hero's own paintings (Duplicate's "reuse the paintings").
    - A creature look copies the base's art words it names none of, so its prompt is in its own recipe."""
    if not target.get("code"):
        return
    method = spec.get("method")
    recipe = spec.get("recipe")
    if not isinstance(recipe, dict):
        recipe = {}
        spec["recipe"] = recipe
    if method == "front_from_picture":
        if recipe.get("method") == "front_from_picture":
            recipe.pop("method")
    elif method:
        # the method that runs is the one recorded (the recipe's own named another when the form changed it)
        recipe["method"] = method
    if method == "recolour":
        return
    recipe["painter"] = _painter_of(spec)
    if method == "hero_puppet":
        _seed_puppet_recipe(target, spec, recipe)
    if method not in STILL_METHODS:
        return
    st = _look_state(target)
    if st["is_new"]:
        if recipe.get("stills") is None:
            recipe["stills"] = _letter(target["code"])
        if recipe.get("seed_offset") is None:
            recipe["seed_offset"] = _seed_offset(target["code"])
    elif recipe.get("stills") is None:
        recipe["stills"] = ""
    if method in CREATURE_STILL_METHODS:
        base = st["doc"]
        for k in INHERITED_WORDS:
            if not recipe.get(k) and base.get(k) not in (None, "", {}):
                recipe[k] = base[k]


# ---------------------------------------------------------------- re-rolls (pass 68, D3)

def _move_stills_aside(keys, stamp, remove=False):
    """Each still's PNG and JSON copied to <key>_old<stamp> (the paintings stay recoverable); `remove` deletes the
    original too (a tool that cannot be told --keys paints it again only when it is gone). Returns the copies' paths."""
    moved = []
    for key in keys:
        for ext in (".png", ".json"):
            src = os.path.join(RAW, key + ext)
            if os.path.isfile(src):
                dst = os.path.join(RAW, "%s_old%s%s" % (key, stamp, ext))
                shutil.copy2(src, dst)
                if remove:
                    os.remove(src)
                moved.append(_rel(dst))
    return moved


def _move_clips_aside(keys, stamp):
    """Each clip's cache folder moved to <key>_old<stamp> (the clip cache is by key only). Returns the new paths."""
    moved = []
    for key in keys:
        src = os.path.join(ANIM, key)
        if os.path.isdir(src):
            dst = "%s_old%s" % (src, stamp)
            shutil.move(src, dst)
            moved.append(_rel(dst))
    return moved


def _unspent_keys(keys, started):
    """The forced still keys (spec.keys) an attempt that started at `started` has not painted yet: a key whose PNG is not
    older than the start was painted by that attempt. Every key when the attempt never started (pass 68 review)."""
    t0 = _epoch(started)
    keys = [str(k) for k in (keys or []) if k]
    if t0 is None:
        return keys
    out = []
    for k in keys:
        p = os.path.join(RAW, k + ".png")
        if not (os.path.isfile(p) and os.path.getmtime(p) >= t0):
            out.append(k)
    return out


def _slug_users(doc, code, slug):
    """The other looks of the file whose recipe names the same `stills` slug ("top" for the creature's own `stills`)."""
    out = []
    vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    for c, e in vs.items():
        if c == code or not isinstance(e, dict):
            continue
        r = e.get("recipe") if isinstance(e.get("recipe"), dict) else {}
        if r.get("stills") is not None and str(r.get("stills")) == slug:
            out.append(c)
    if doc.get("stills") is not None and str(doc.get("stills")) == slug:
        out.append("top")
    return out


def _own_slug(doc, code):
    """A slug of the look's own: its letter, or the letter and a number when another look's recipe names the letter."""
    base = _letter(code)
    slug, n = base, 1
    while _slug_users(doc, code, slug):
        n += 1
        slug = "%s%d" % (base, n)
    return slug


def _fork_shared_stills(job, r_stills):
    """pass 68: a job card's still re-roll (requeue) on a look whose paintings are shared (stills "" = the creature's or
    hero's own, or a slug another look names) must not repaint the shared files (every other look, the badge and title
    tools read them): the look gets a slug of its own and its own seed_offset, the shared paintings it keeps are copied
    under its new keys (their dates kept: the honest painter calls them reused), and only the asked ones are painted,
    under the new keys. Returns (the keys to paint again, {forked, from, copied} or None when nothing was shared)."""
    t = job.get("target") or {}
    spec = job.get("spec") or {}
    method = job.get("method")
    if job.get("kind") != "look" or method not in STILL_METHODS or not r_stills or not t.get("code"):
        return r_stills, None
    st = _look_state(t)
    if st["is_base"]:
        return r_stills, None   # the base strip's paintings are its own
    recipe = spec.get("recipe") if isinstance(spec.get("recipe"), dict) else {}
    slug = str(recipe.get("stills") or "")
    if slug and not _slug_users(st["doc"], t["code"], slug):
        return r_stills, None
    old_keys = cache_keys(method, spec, t, st["doc"])["stills"]
    if not any(k in old_keys for k in r_stills):
        return r_stills, None
    recipe = dict(recipe)
    recipe["stills"] = _own_slug(st["doc"], t["code"])
    if recipe.get("seed_offset") is None:
        recipe["seed_offset"] = _seed_offset(t["code"])
    spec["recipe"] = recipe
    new_keys = cache_keys(method, spec, t, st["doc"])["stills"]
    forced, copied = [], []
    for old, new in zip(old_keys, new_keys):
        if old in r_stills:
            forced.append(new)   # a still_keys view keeps its named painting's key (old == new)
            continue
        if old == new:
            continue
        for ext in (".png", ".json"):
            src, dst = os.path.join(RAW, old + ext), os.path.join(RAW, new + ext)
            if os.path.isfile(src) and not os.path.isfile(dst):
                shutil.copy2(src, dst)
                if ext == ".png":
                    copied.append(new)
    forced += [k for k in r_stills if k not in old_keys]
    # a key an older re-roll forced under the shared names is not this look's any more
    spec["keys"] = [k for k in (spec.get("keys") or []) if k and (k not in old_keys or k in new_keys)]
    return forced, {"forked": recipe["stills"], "from": slug, "copied": copied}


def _apply_reroll(target, spec):
    """The job form's re-roll (spec.reroll = {mode, view}), applied once at enqueue (pass 68, D3); `applied` marks it so an
    edit does not apply it again. The recipe changes are written with the recipe (set_recipe at enqueue); the cache is
    moved aside with requeue's helpers (a still copied to <key>_old<stamp>, a clip folder moved).
      stills  a look that shares its paintings (stills "" or a slug another look names) gets a slug of its own and its own
              seed_offset: its stills are painted fresh under new keys and the shared ones are never touched; a look with
              its own slug: seed_offset + 1 and its stills painted again (--keys); its clips are moved aside too and
              walked again from the new stills (the lead, pass 68: kept clips would be the old walks of the old stills)
      seeds   stills, and the clips moved aside with anim_seed + 1
      clips   the clips moved aside, anim_seed + 1 (creature_ctl: walk_seeds + 1 per view), the stills kept
      view    creature_ctl's view candidates (--view-cands)
      clip    pass 70: one view's walk (reroll.view: front, fd, side, bd, back): only that clip moved aside and walked again
              (on the driver the recipe names for that view now; anim_seed + 1, creature_ctl's walk_seeds[view] + 1), the
              stills and the other views kept
    Returns {mode, moved, stamp, keys} or None; ValueError when the mode does not fit the method."""
    rr = spec.get("reroll")
    if not isinstance(rr, dict):
        return None
    mode = str(rr.get("mode") or "")
    if mode in ("", "none") or rr.get("applied"):
        return None
    if mode not in REROLL_MODES:
        raise ValueError("reroll.mode %r is not one of %s" % (mode, ", ".join(REROLL_MODES)))
    method = spec.get("method")
    code = str(target.get("code") or "")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    if method in ("front_from_picture", "recolour"):
        raise ValueError("%s paints no stills or clips of its own: there is nothing to re-roll (queue it again)" % method)
    if mode == "stage":
        # pass 71: a hero_puppet look made again from one puppet stage (puppet.py --reset-from moves that stage's outputs
        # and the later ones aside when the job runs)
        if method != "hero_puppet":
            raise ValueError("the stage re-roll is the Puppet method's (hero_puppet)")
        stage = str(rr.get("stage") or rr.get("view") or "")
        if stage not in PUPPET_STAGES:
            raise ValueError("the stage re-roll needs reroll.stage: one of %s" % ", ".join(PUPPET_STAGES))
        pp = spec.get("puppet") if isinstance(spec.get("puppet"), dict) else {}
        pp["reset_from"] = stage
        spec["puppet"] = pp
        rr["applied"] = stamp
        return {"mode": mode, "moved": [], "stamp": stamp, "keys": [], "stage": stage}
    if mode == "view":
        if method != "creature_ctl":
            raise ValueError("the view re-roll is creature_ctl's view candidates (gen_ctl --view-cands)")
        views = [v.strip() for v in str(rr.get("view") or "").split(",") if v.strip()]
        if not views or any(v not in CTL_VIEWS for v in views):
            raise ValueError("the view re-roll needs reroll.view: one or more of %s" % ", ".join(CTL_VIEWS))
        spec["view_cands"] = ",".join(views)
        spec["use_view"] = ""
        rr["applied"] = stamp
        return {"mode": mode, "moved": [], "stamp": stamp, "keys": [], "view": spec["view_cands"]}
    if mode == "clip":
        views = [v.strip() for v in str(rr.get("view") or "").split(",") if v.strip()]
        if not views or any(v not in CTL_VIEWS for v in views):
            raise ValueError("the one-view walk needs reroll.view: one or more of %s" % ", ".join(CTL_VIEWS))
        if method in ("creature_proc", "creature_pictures"):
            raise ValueError(method + " has no clips (its frames are procedural): re-roll the stills")
        clips = [k for k in cache_keys(method, spec, target, _look_state(target)["doc"])["clips"] if clip_view(k) in views]
        if not clips:
            raise ValueError("%s walks no %s view (a two-direction look walks front and back only)" % (code or "this look", "/".join(views)))
        recipe = spec.get("recipe")
        if not isinstance(recipe, dict):
            recipe = {}
            spec["recipe"] = recipe
        if method == "creature_ctl":
            ws = dict(recipe.get("walk_seeds") or {})
            for key in clips:
                ws[clip_view(key)] = int(ws.get(clip_view(key), 0)) + 1
            recipe["walk_seeds"] = ws
        else:
            recipe["anim_seed"] = int(recipe.get("anim_seed", 0) or 0) + 1
        moved = _move_clips_aside(clips, stamp)
        rr["applied"] = stamp
        return {"mode": mode, "moved": moved, "stamp": stamp, "keys": [], "view": ",".join(views)}
    if method == "hero_fit" and mode in ("stills", "seeds"):
        raise ValueError("hero_fit walks the hero's own paintings (every look's): re-roll its clips, or paint the look's own stills with hero_pose5")
    if method == "creature_ctl" and mode in ("stills", "seeds"):
        raise ValueError("creature_ctl paints its stills from the picked side with its code's own seeds: re-roll a view or the clips "
                         "(new side candidates: queue a new look)")
    if method in ("creature_proc", "creature_pictures") and mode == "clips":
        raise ValueError(method + " has no clips (its frames are procedural): re-roll the stills")
    recipe = spec.get("recipe")
    if not isinstance(recipe, dict):
        recipe = {}
        spec["recipe"] = recipe
    st = _look_state(target)
    doc, cid = st["doc"], str(target.get("id") or "")
    moved, forced = [], []
    if mode in ("stills", "seeds") and method in STILL_METHODS:
        slug = str(recipe.get("stills") or "")
        shared = not slug or bool(_slug_users(doc, code, slug))
        if shared:
            recipe["stills"] = _own_slug(doc, code)
            if recipe.get("seed_offset") is None:
                recipe["seed_offset"] = _seed_offset(code)
        else:
            recipe["seed_offset"] = int(recipe.get("seed_offset") or 0) + 1
        prefix = cid + "_" + str(recipe["stills"]) + "_"
        # only the slug's own keys: a hero recipe's still_keys name paintings other looks share, never repainted here
        keys = [k for k in cache_keys(method, spec, target, doc)["stills"] if k.startswith(prefix)]
        if shared:
            keys = [k for k in keys if os.path.isfile(os.path.join(RAW, k + ".png"))]   # leftovers under the new slug
        moved += _move_stills_aside(keys, stamp)
        sk = [k for k in (spec.get("keys") or []) if k]
        for k in keys:
            if k not in sk:
                sk.append(k)
        spec["keys"] = sk
        forced = keys
    if mode == "stills":
        # the walks follow the stills they are walked from (new stills, the same clip seed: new clips)
        moved += _move_clips_aside(cache_keys(method, spec, target, doc)["clips"], stamp)
    if mode in ("seeds", "clips"):
        clips = cache_keys(method, spec, target, doc)["clips"]
        if method == "creature_ctl":
            clips = [k for k in clips if "_ctl_" in k]   # its death has a seed of its own: moving it would paint the same
            ws = dict(recipe.get("walk_seeds") or {})
            for key in clips:
                v = key.rsplit("_", 1)[-1]
                ws[v] = int(ws.get(v, 0)) + 1
            recipe["walk_seeds"] = ws
        else:
            recipe["anim_seed"] = int(recipe.get("anim_seed", 0) or 0) + 1
        moved += _move_clips_aside(clips, stamp)
    rr["applied"] = stamp
    return {"mode": mode, "moved": moved, "stamp": stamp, "keys": forced}


# ---------------------------------------------------------------- candidate defaults (pass 68, D6)

# a clause of an art_prompt that describes the still's pose rather than the character (appearance_of)
_POSE_STRONG = re.compile(r"\b(standing|facing|relaxed|pose[sd]?|posing)\b", re.I)
_POSE_LIMBS = re.compile(r"\b(arms?|hands?)\b", re.I)
_POSE_LIMB_WAYS = re.compile(r"\b(sides?|empty|raised|crossed|hips?|hanging|nothing|down|folded|outstretched|spread)\b", re.I)


def _is_pose_clause(text):
    t = str(text or "")
    return bool(_POSE_STRONG.search(t) or (_POSE_LIMBS.search(t) and _POSE_LIMB_WAYS.search(t)))


def appearance_of(text):
    """The character in an art_prompt without the trailing clause about the still's pose ("; standing straight, both arms
    relaxed at her sides", ", standing straight with his hands relaxed at his sides", ", empty hands"): a last ;-clause,
    then each last ,-clause, that names standing, facing, relaxed or a pose (or arms/hands with how they hang), is cut.
    A badge, a title or an icon has its own action, which the still's pose contradicts."""
    s = str(text or "").strip()
    if not s:
        return ""
    if ";" in s:
        head, tail = s.rsplit(";", 1)
        if head.strip() and _is_pose_clause(tail):
            s = head.strip()
    while "," in s:
        head, tail = s.rsplit(",", 1)
        if head.strip() and _is_pose_clause(tail):
            s = head.strip()
        else:
            break
    return s.rstrip(" ,;.")


_title_cache = {"mtime": None, "tables": {}}


def _title_tables():
    """gen_title_heroes.py's own tables (POSES, HOLDS, CAMERA, FACING, EXTRA_REFS), read as literals from its source (the
    tool imports gen_art and comfy, which must not load in the editor); {} when they cannot be read."""
    path = os.path.join(TOOLS, "gen_title_heroes.py")
    try:
        mt = os.path.getmtime(path)
    except OSError:
        return {}
    if _title_cache["mtime"] == mt:
        return _title_cache["tables"]
    out = {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            tree = ast.parse(f.read())
        for node in tree.body:
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) \
                    and node.targets[0].id in ("POSES", "HOLDS", "CAMERA", "FACING", "EXTRA_REFS"):
                try:
                    v = ast.literal_eval(node.value)
                except ValueError:
                    continue
                if isinstance(v, dict):
                    out[node.targets[0].id] = v
    except (OSError, SyntaxError, ValueError):
        out = {}
    _title_cache.update(mtime=mt, tables=out)
    return out


def _resolve_pic(path):
    """A picture path as a job field names it (repo-relative such as tools/dl/uploads/2d/x.png, tools/dl-relative such as
    basketball_ref.png, or absolute) -> the file on disk, or None."""
    p = str(path or "").strip()
    if not p:
        return None
    norm = p.replace("\\", "/")
    for prefix, base in (("tools/dl/ai_raw_anime/", RAW), ("tools/dl/", DL)):
        if norm.startswith(prefix):
            cand = os.path.join(base, *norm[len(prefix):].split("/"))
            if os.path.isfile(cand):
                return cand
    cands = [p] if os.path.isabs(p) else [os.path.join(_root, *norm.split("/")), os.path.join(DL, *norm.split("/"))]
    for c in cands:
        if os.path.isfile(c):
            return c
    return None


def _pic_url(path):
    """The page's /dl/ link of a picture under tools/dl, else None."""
    norm = str(path or "").strip().replace("\\", "/")
    if norm.startswith("tools/dl/"):
        return "/dl/" + norm[len("tools/dl/"):]
    full = _resolve_pic(norm)
    if full:
        r = _rel(full)
        if r.startswith("tools/dl/"):
            return "/dl/" + r[len("tools/dl/"):]
    return None


def _base_recipe(doc):
    """(code, recipe) of the base strip's own entry (`variant_base`): a base look the editor made carries the recipe its
    stills were painted from (bull_beetle's BB-C, lesser_scorpion's LS-B, werewolf's WW-A); recipe {} when it has none."""
    doc = doc if isinstance(doc, dict) else {}
    bc = str(doc.get("variant_base") or "")
    vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    e = vs.get(bc) if bc else None
    r = e.get("recipe") if isinstance(e, dict) else None
    return bc, (r if isinstance(r, dict) else {})


def _front_key(tkind, cid, code, doc):
    """(key, source) of a target's identity picture: a look's own front still (cache_keys of its method and recipe; a new
    look's slug as _seed_recipe will give it), else the base's: the base look's own front when its entry has a recipe and
    that still is on disk (pass 68 review: BB-C's bull_beetle_bbc_front, not the old bull_beetle_front), else a hero's
    still_keys.front or <id>_front, a creature's <id>[_<stills>]_front. (None, "") for an item."""
    st = _look_state({"kind": tkind, "id": cid, "code": code}, doc)
    if code and not st["is_base"]:
        recipe = dict(st["recipe"])
        method = implied_method(tkind, recipe, doc)
        if st["is_new"] and method in STILL_METHODS and recipe.get("stills") is None:
            recipe["stills"] = _letter(code)
        keys = cache_keys(method, {"recipe": recipe}, {"kind": tkind, "id": cid, "code": code}, doc).get("stills") or []
        front = next((k for k in keys if k.endswith("_front")), None)
        if front:
            return front, "the look's front still (%s)" % front
    bc, brec = _base_recipe(doc)
    if brec and tkind in ("hero", "enemy", "boss"):
        keys = cache_keys(implied_method(tkind, brec, doc), {"recipe": brec}, {"kind": tkind, "id": cid, "code": bc}, doc).get("stills") or []
        front = next((k for k in keys if k.endswith("_front")), None)
        if front and os.path.isfile(os.path.join(RAW, front + ".png")):
            return front, "the base look's front still (%s)" % front
    if tkind == "hero":
        sk = doc.get("still_keys") if isinstance(doc.get("still_keys"), dict) else {}
        key = str(sk.get("front", cid + "_front"))
        return key, "the hero's front still (%s)" % key
    if tkind in ("enemy", "boss"):
        stl = doc.get("stills")
        key = cid + ("_" + str(stl) if stl else "") + "_front"
        return key, "the creature's front still (%s)" % key
    return None, ""


def _item_render(cid):
    """An item's 3D render, the reference its icon may copy: tools/dl/<id>_ref.png (the Blender scripts' icon renders), else
    ref_render's tools/dl/uploads/3d/<id>/icon_ref.png; None when neither is there."""
    for rel in ("%s_ref.png" % cid, "uploads/3d/%s/icon_ref.png" % cid):
        if os.path.isfile(os.path.join(DL, *rel.split("/"))):
            return "tools/dl/" + rel
    return None


def _character_of(doc, recipe):
    """(words, source): the look's own appearance, else its own art_prompt when it differs from the base's (a look copies
    the base's), else the base's appearance, else the base's art_prompt; an art_prompt goes through appearance_of."""
    rec = recipe if isinstance(recipe, dict) else {}
    base_ap = str(doc.get("art_prompt") or "").strip()
    if str(rec.get("appearance") or "").strip():
        return str(rec["appearance"]).strip(), "the look's appearance"
    own = str(rec.get("art_prompt") or "").strip()
    if own and own != base_ap:
        a = appearance_of(own)
        return a, "the look's art_prompt" + (" (its pose clause cut)" if a != own.rstrip(" ,;.") else "")
    if str(doc.get("appearance") or "").strip():
        return str(doc["appearance"]).strip(), "appearance"
    if base_ap:
        a = appearance_of(base_ap)
        return a, "art_prompt" + (" (its pose clause cut)" if a != base_ap.rstrip(" ,;.") else "")
    return "", ""


def _screen_of(doc, recipe):
    """(screen, source) for an icon: the look's or the item's `screen`, else gen_art.bg_for's rule (a green-ish
    placeholder colour paints on blue), else green."""
    for d, where in ((recipe if isinstance(recipe, dict) else {}, "the look's screen"), (doc, "screen")):
        named = str(d.get("screen") or "").lower()
        if named in ("green", "blue"):
            return named, where
    ph = doc.get("placeholder") if isinstance(doc.get("placeholder"), dict) else {}
    import colorsys
    for key in ("color", "hat", "outline"):
        col = str(ph.get(key, "")).lstrip("#")
        if len(col) != 6:
            continue
        try:
            r, g, b = int(col[0:2], 16) / 255, int(col[2:4], 16) / 255, int(col[4:6], 16) / 255
        except ValueError:
            continue
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if s > 0.25 and 0.2 < h < 0.48:
            return "blue", "the placeholder colour is green-ish (gen_art paints it on blue)"
    return "green", "the default screen"


def candidate_defaults(kind, target):
    """What the server fills into an icon_cands, hero_badge or hero_title job's empty fields (pass 68, D6), and where each
    came from: {"kind", "target", "fields": {...}, "sources": {field: "where it came from"}, "ref_url": "/dl/..." or None,
    "ref_exists": bool}. Served by GET /api/jobs/defaults so the form shows them as values Garry edits; applied at enqueue
    and edit to every empty field (_seed_candidates).
      character  (badge, title; a creature's icon subject) the appearance, else the art_prompt with its pose clause cut
      ref        the target look's own front still (tools/dl/ai_raw_anime/<front key>.png), else the base's; an item's
                 3D render when it has one
      hero_badge prompt (portrait_prompt), variant (the look code; "" for the hero's own)
      hero_title pose (title_pose, else the tool's table, else a confident full-body stance), holds, camera, extra_ref,
                 extra_words (title_*, else the tool's tables), variant
      icon_cands subject (a creature's character words; an item's art_prompt), screen, file (<id>_icon_<x>.png for a
                 look, else the base icon)"""
    if kind not in CANDIDATE_KINDS:
        raise ValueError("defaults are for %s (got %r)" % (", ".join(CANDIDATE_KINDS), kind))
    t = dict(target or {})
    tkind, cid, code = str(t.get("kind") or ""), str(t.get("id") or ""), str(t.get("code") or "")
    if not cid:
        raise ValueError("%s defaults need a target id" % kind)
    if kind in ("hero_badge", "hero_title") and tkind not in ("", "hero"):
        raise ValueError("%s is for a hero" % kind)
    if kind == "icon_cands" and tkind == "hero":
        raise ValueError("a hero's icon is the round badge: queue hero_badge")
    if not tkind and kind in ("hero_badge", "hero_title"):
        tkind = "hero"
    doc = content_doc(tkind, cid)
    if doc is None:
        raise ValueError("no %s %s" % (tkind or "item", cid))
    st = _look_state({"kind": tkind, "id": cid, "code": code}, doc)
    is_look = bool(code) and not st["is_base"]
    # the base look's own recipe when its entry has one (pass 68 review): its words and screen, as its front still
    recipe = st["recipe"] if is_look else _base_recipe(doc)[1]
    creature = tkind in ("enemy", "boss")
    fields, sources = {}, {}

    def put(name, value, source):
        fields[name] = "" if value is None else value
        sources[name] = source

    def word(key):
        """A hero key from the look's recipe, else the hero JSON's: (value, source)."""
        if is_look and str(recipe.get(key) or "").strip():
            return str(recipe[key]).strip(), "the look's " + key
        if str(doc.get(key) or "").strip():
            return str(doc[key]).strip(), key
        return "", ""

    ref_key, ref_src = (None, "")
    if kind in ("hero_badge", "hero_title") or creature:
        ref_key, ref_src = _front_key(tkind, cid, code if is_look else "", doc)
    ref = "tools/dl/ai_raw_anime/%s.png" % ref_key if ref_key else None
    if kind == "icon_cands" and not creature:
        ref = _item_render(cid)
        ref_src = "the item's 3D render" if ref else ""
    if kind in ("hero_badge", "hero_title") or creature:
        who, src = _character_of(doc, recipe)
        if kind == "icon_cands":
            put("subject", who, src)
        else:
            put("character", who, src)
    else:
        put("subject", str(doc.get("art_prompt") or "").strip(), "art_prompt" if doc.get("art_prompt") else "")
    put("ref", ref or "", ref_src)
    variant = code if is_look else ""
    if kind == "hero_badge":
        pp, src = word("portrait_prompt")
        put("prompt", pp or "smiling at the viewer", src or "the tool's default")
        put("variant", variant, "the look" if variant else "the hero's own badge")
    elif kind == "hero_title":
        tabs = _title_tables()
        pose, src = word("title_pose")
        if not pose and cid in (tabs.get("POSES") or {}):
            pose, src = str(tabs["POSES"][cid]), "gen_title_heroes POSES"
        put("pose", pose or "standing confidently in a heroic pose, full body", src or "the default pose")
        holds, src = word("title_holds")
        if not holds and cid in (tabs.get("HOLDS") or {}):
            holds, src = str(tabs["HOLDS"][cid]), "gen_title_heroes HOLDS"
        put("holds", holds or "no weapon", src or "the tool's default")
        cam, src = word("title_camera")
        for tab in ("CAMERA", "FACING"):
            if not cam and cid in (tabs.get(tab) or {}):
                cam, src = str(tabs[tab][cid]), "gen_title_heroes " + tab
        put("camera", cam or "facing the viewer, seen from the front at eye level", src or "the tool's default")
        xr = recipe.get("title_extra_ref") if is_look and isinstance(recipe.get("title_extra_ref"), dict) else doc.get("title_extra_ref")
        xfile, xwords, xsrc = "", "", ""
        if isinstance(xr, dict) and xr.get("file"):
            xfile, xwords, xsrc = str(xr["file"]), str(xr.get("words") or ""), "title_extra_ref"
        elif cid in (tabs.get("EXTRA_REFS") or {}):
            pair = tabs["EXTRA_REFS"][cid]
            if isinstance(pair, (tuple, _LIST)) and len(pair) == 2:
                xfile, xwords, xsrc = str(pair[0]), str(pair[1]), "gen_title_heroes EXTRA_REFS"
        put("extra_ref", xfile, xsrc)
        put("extra_words", xwords, xsrc)
        put("variant", variant, "the look" if variant else "the hero's own cut-out")
    else:
        scr, src = _screen_of(doc, recipe)
        put("screen", scr, src)
        if is_look:
            put("file", "%s_icon_%s.png" % (cid, _letter(code)), "the look's own icon file")
        else:
            put("file", os.path.basename(str(doc.get("icon") or (cid + "_icon.png"))), "the icon the game reads")
    full = _resolve_pic(fields.get("ref"))
    return {"kind": kind, "target": {"kind": tkind, "id": cid, "code": code}, "fields": fields, "sources": sources,
            "ref_url": _pic_url(fields.get("ref")) if fields.get("ref") else None, "ref_exists": bool(full)}


def _seed_candidates(kind, target, spec):
    """D6 at enqueue and edit: every empty field of an icon_cands / hero_badge / hero_title spec gets candidate_defaults'
    value; spec.defaults_from says where each filled one came from (the job card shows it). A field holding only a space
    is not empty: the plan leaves it out (the way to send no words)."""
    if kind not in CANDIDATE_KINDS:
        return {}
    try:
        d = candidate_defaults(kind, target)
    except ValueError:
        return {}
    filled = {}
    for k, v in d["fields"].items():
        if spec.get(k) in (None, "") and v not in (None, ""):
            spec[k] = v
            filled[k] = d["sources"].get(k, "")
    prev = spec.get("defaults_from") if isinstance(spec.get("defaults_from"), dict) else {}
    # a field whose value is no longer the default (Garry typed or picked his own on an edit) is no longer "filled in"
    kept = {k: s for k, s in prev.items() if spec.get(k) in (None, "") or spec.get(k) == d["fields"].get(k)}
    if filled or kept != prev:
        spec["defaults_from"] = dict(kept, **filled)
    return filled


def _planned_stills(cid):
    """The still keys the queued, running and waiting look jobs of an id will paint (a candidate job's reference may be
    a new look's front, painted first: the comfy lane runs in order)."""
    out = set()
    for j in _state["jobs"]:
        if j.get("kind") == "look" and j.get("state") in ("queued", "running", "waiting") and (j.get("target") or {}).get("id") == cid:
            out.update((j.get("cache_keys") or {}).get("stills") or [])
    return out


def _check_candidate_spec(kind, target, spec):
    """After the defaults: an icon job needs words, and every picture it names must be on disk or a still a queued look
    job of the same id paints first (MAM-C's typed reference had lost its space and was never there)."""
    if kind == "icon_cands" and not str(spec.get("subject") or "").strip():
        raise ValueError("icon_cands needs subject: what to paint (the target has no art_prompt or appearance to fill it from)")
    planned = None
    for k in ("ref", "extra_ref"):
        p = str(spec.get(k) or "").strip()
        if not p or _resolve_pic(p):
            continue
        norm = p.replace("\\", "/")
        key = norm[len("tools/dl/ai_raw_anime/"):-4] if norm.startswith("tools/dl/ai_raw_anime/") and norm.endswith(".png") else None
        if planned is None:
            planned = _planned_stills(str(target.get("id") or ""))
        if key and key in planned:
            continue
        raise ValueError("%s: the picture %s is not on disk (repo paths such as tools/dl/uploads/2d/<file>, tools/dl paths and "
                         "absolute ones are read; check the name)" % (k, p))


def enqueue(kind, target, spec, title=None, request=None):
    """`request` (pass 96, lane REQ): the art request this job belongs to, stamped on the record as `request`; a job
    without one runs exactly as before (nothing in this module reads it except the request hook)."""
    _writable()
    spec = validate_spec(kind, spec)
    target = _check_target(kind, target)
    if kind == "look" and spec.get("method") == "hero_puppet":
        prob = puppet_problem(spec, target)   # pass 71
        if prob:
            raise ValueError(prob)
    rr = None
    if kind == "look":
        _seed_recipe(target, spec)
        rr = _apply_reroll(target, spec)
    elif kind in CANDIDATE_KINDS:
        _seed_candidates(kind, target, spec)
        _check_candidate_spec(kind, target, spec)
    job = {"id": _new_id(), "kind": kind, "method": spec.get("method") if kind == "look" else kind, "lane": SPECS[kind]["lane"],
           "state": "queued", "title": title or "", "target": target, "spec": spec, "phase": 1, "attempt": 1, "created": _now(),
           "started": None, "ended": None, "pid": None, "cmd": [], "equiv": "",
           "progress": {"done": 0, "total": 0, "stage": "", "stages": [], "last_output": None, "stalled": False},
           "eta_s": 0, "log_file": "", "outputs": [], "choices": [], "cache_keys": {}, "error": "", "qa_online": None,
           "written": None, "lock_waits": {}, "front": False}
    if rr:
        job["reroll"] = rr
    if request or spec.get("request"):
        job["request"] = str(request or spec.get("request"))   # pass 96 (lane REQ): the art request this job is part of (the kwarg, or the spec's own key: an evaluate job)
    with _lock:
        _derive(job)
        if kind == "look" and spec.get("recipe") is not None and _hook("set_recipe"):
            try:
                _hook("set_recipe")(target["kind"], target["id"], target["code"], spec.get("recipe") or {}, spec.get("note") or None)
            except Exception as e:
                job["error"] = "the recipe could not be written: %s" % e
        _state["jobs"].append(job)
        _ev_job(job, "queued", title=job.get("title"), spec=job.get("spec"))   # pass 97 (lane PROGRESS, WF-02)
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
        rr = None
        recipe_before = json.dumps((job.get("spec") or {}).get("recipe"), sort_keys=True)
        if spec is not None:
            # a deep copy: a refused edit leaves the job as it was (the checks below may raise)
            merged = json.loads(json.dumps(job.get("spec") or {}))
            stored, inc = merged.get("reroll"), spec.get("reroll")
            if (isinstance(stored, dict) and stored.get("applied") and isinstance(inc, dict) and not inc.get("applied")
                    and str(inc.get("mode") or "") == str(stored.get("mode") or "")
                    and (str(inc.get("mode") or "") != "view" or str(inc.get("view") or "") == str(stored.get("view") or ""))):
                # pass 68 review: the page's Save changes sends the whole form, its re-roll without the stamp: the same
                # mode (and view) is the re-roll already applied at Queue, never applied again (seed_offset + 1 again,
                # the stills it painted moved aside); a different mode or view is a new re-roll, applied once
                spec = dict(spec, reroll=dict(inc, applied=stored["applied"]))
            merged.update(spec)
            new = validate_spec(job["kind"], merged)
            t = job.get("target") or {}
            if job["kind"] == "look":
                _seed_recipe(t, new)
                rr = _apply_reroll(t, new)   # raises before it moves anything
            elif job["kind"] in CANDIDATE_KINDS:
                _seed_candidates(job["kind"], t, new)
                _check_candidate_spec(job["kind"], t, new)
            job["spec"] = new
            if rr:
                job["reroll"] = rr
            if job["kind"] == "look":
                job["method"] = job["spec"].get("method")
        if title is not None:
            job["title"] = str(title)
        if job.get("method") == "hero_puppet":
            job["puppet_next"], job["puppet_lane"] = None, None   # pass 71: the phases start again from the disk
        if job["state"] == "waiting":
            job["state"], job["phase"] = "queued", 1
            job["choices"] = []
            for k in ("use_side", "use_view", "pick"):
                if k in job["spec"]:
                    job["spec"][k] = ""
        job["front"] = False
        _derive(job)
        recipe_changed = json.dumps((job.get("spec") or {}).get("recipe"), sort_keys=True) != recipe_before
        if job["kind"] == "look" and spec is not None and ("recipe" in spec or recipe_changed) and _hook("set_recipe"):
            t = job["target"]
            try:
                _hook("set_recipe")(t["kind"], t["id"], t["code"], job["spec"].get("recipe") or {}, job["spec"].get("note") or None)
            except Exception as e:
                job["error"] = "the recipe could not be written: %s" % e
        _ev_job(job, "edited", spec=spec, title=title)   # pass 97 (lane PROGRESS, WF-02)
        _save()
        return _public(job, LOG_TAIL_SHORT)


def cancel(job_id):
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise ValueError("no job %s" % job_id)
        _ev_job(job, "cancel")   # pass 97 (lane PROGRESS, WF-02): asked; `finished` says how it ended
        if job["state"] in ("queued", "waiting"):
            job["state"], job["ended"] = "cancelled", _now()
            _save()
            _request_after(job)   # pass 96 (lane REQ): a request's job cancelled by hand: its record learns
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
        _comfy_interrupt(job.get("comfy_prompt"))   # pass 96 (WF-06c): this job's own prompt, never the whole queue
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
        job = _find(job_id) or _unarchive(job_id)   # pass 97 (lane PROGRESS): an archived job comes back into the queue
        if job is None:
            raise ValueError("no job %s" % job_id)
        if job["state"] in ("running", "queued"):
            raise ValueError("job %s is %s" % (job_id, job["state"]))
        spec = job.setdefault("spec", {})
        if job["kind"] == "look":
            # pass 70 (the Bandit check): a job queued before the check with a picture's path in Stills is refused again
            # with the words (Edit the job: Stills a short name, the picture in Reference)
            prob = _VOCAB.stills_problem(spec.get("stills") or None)
            if prob:
                raise ValueError("stills: %s: Edit the job first" % prob)
            # pass 70: the look's recipe as its JSON holds it now: a driver or a hint changed in the recipe editor since
            # the job ran is what the re-run reads (the job's own copy was written back over it, so a one-view re-roll
            # walked on the old driver)
            t0 = job.get("target") or {}
            if t0.get("code") and job.get("method") != "front_from_picture":
                cur = _look_state(t0)["recipe"]
                if cur and cur != spec.get("recipe"):
                    spec["recipe"] = json.loads(json.dumps(cur))
        rr = reroll or {}
        if job.get("method") == "hero_puppet":
            puppet_requeue(job, rr)   # pass 71
        stamp = time.strftime("%Y%m%d-%H%M%S")
        moved = []
        gen_art_tool = (job.get("plan") or {}).get("tool") in ("gen_art", "") and job.get("method") != "creature_ctl"
        r_stills = [k for k in (rr.get("stills") or []) if k]
        if job["kind"] == "look" and not r_stills and spec.get("keys"):
            # pass 68 review: a stopped job (failed, cancelled, interrupted) keeps its forced keys; the ones its attempt
            # already repainted (a PNG not older than the attempt's start) are spent, so a plain Re-queue continues from
            # the cache as the card says instead of painting them all again
            spec["keys"] = _unspent_keys(spec["keys"], job.get("attempt_started"))
        # pass 68: a look that shares its paintings forks them first (the shared files are never repainted from a look)
        r_stills, fork = _fork_shared_stills(job, r_stills)
        # gen_ctl and the candidate tools cannot be told --keys: their paintings are moved away so they paint again
        moved += _move_stills_aside(r_stills, stamp, remove=not gen_art_tool)
        if gen_art_tool and r_stills:
            keys = [k for k in (spec.get("keys") or []) if k]
            for key in r_stills:
                if key not in keys:
                    keys.append(key)
            spec["keys"] = keys
        moved += _move_clips_aside([k for k in (rr.get("clips") or []) if k], stamp)
        if job["kind"] == "hero_badge":
            # pass 68: a badge job's candidates are cached by their keys (<id>_portrait_<tag>_c<k>): a re-run would hand
            # the same pictures back whatever its seeds, so its own are moved aside and the next attempt paints new ones
            moved += _move_stills_aside([k for k in _badge_keys(job) if k not in r_stills], stamp, remove=True)
        if rr.get("seed") is not None:
            spec["seed"] = int(rr["seed"])
        if (rr.get("clips") or fork) and job["kind"] == "look":
            recipe = dict(spec.get("recipe") or {})
            if not rr.get("clips"):
                pass
            elif job.get("method") == "creature_ctl":
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
        if moved or fork:
            job["reroll"] = {"moved": moved, "stamp": stamp}
            if fork:
                job["reroll"]["fork"] = fork
        if job["method"] == "creature_ctl":
            # a side already picked stays picked (the cache holds <key>_side.png); the views start again from there
            pass
        _derive(job)
        _ev_job(job, "requeued", reroll=reroll or None, moved=len(moved))   # pass 97 (lane PROGRESS, WF-02)
        _save()
        return _public(job, LOG_TAIL_SHORT)


# pass 97 (lane SAFE, OPS-03): "N jobs interrupted by the restart: Re-queue all". recover() is the only place a job turns
# `interrupted`, at this editor's start, stamping `ended`; the jobs it stamped are the ones ended at or after this
# module's import (STARTED_AT; a test sets it). Nothing here runs on its own: only POST /api/jobs/requeue_interrupted.
STARTED_AT = time.time()


def interrupted_ids(scope="restart"):
    """The ids of the interrupted jobs, queue order: scope "restart" = the ones the restart interrupted (ended at or
    after STARTED_AT), "all" = every interrupted job in the queue."""
    with _lock:
        _sync_from_disk()
        out = []
        for j in _state["jobs"]:
            if j.get("state") != "interrupted":
                continue
            if scope != "all":
                t = _epoch(j.get("ended"))
                if t is None or t < STARTED_AT - 1.0:   # _now() keeps whole seconds
                    continue
            out.append(j["id"])
        return out


def requeue_interrupted(ids=None, scope="restart"):
    """Re-queue all (Garry's one click, never automatic): requeue() on every interrupted job of `scope` (or of `ids`
    among them), exactly as its own Re-queue button does. A `launch` job (Test in game: the game window) is skipped,
    since a re-run would open the game again; a job requeue() refuses is listed with its words.
    -> {requeued: [ids], skipped: [{id, why}], refused: [{id, error}]}"""
    _writable()
    todo = interrupted_ids("all" if scope == "all" else "restart")
    out = {"requeued": [], "skipped": [], "refused": []}
    if ids is not None:
        want = [str(i) for i in ids]
        out["skipped"] += [{"id": i, "why": "not interrupted%s" % ("" if scope == "all" else " by the restart")}
                           for i in want if i not in todo]
        todo = [i for i in todo if i in want]
    for jid in todo:
        with _lock:
            j = _find(jid)
            kind = j.get("kind") if j else None
        if j is None:
            out["skipped"].append({"id": jid, "why": "gone"})
            continue
        if kind == "launch":
            out["skipped"].append({"id": jid, "why": "a test in game is started by its own Re-queue"})
            continue
        try:
            requeue(jid)
            out["requeued"].append(jid)
        except Exception as e:   # noqa: BLE001  (one refusal never stops the others)
            out["refused"].append({"id": jid, "error": str(e) if isinstance(e, ValueError) else "%s: %s" % (type(e).__name__, e)})
    return out


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
        elif job["method"] == "hero_puppet":
            # pass 71: "front=2", "side=1,back=0", "shape=1"; applied by the next puppet phase (--pick), kept in spec.puppet.picks
            if not re.match(r"^(front|side|back|shape)=c?\d+(,(front|side|back|shape)=c?\d+)*$", choice):
                raise ValueError("a puppet pick is front=N, side=N,back=N or shape=N (got %r)" % choice)
            pp = spec.get("puppet") if isinstance(spec.get("puppet"), dict) else {}
            picks = dict(pp.get("picks") or {})
            for pair in choice.split(","):
                v, k = pair.split("=", 1)
                picks[v] = int(k.lstrip("c"))
            pp["picks"] = picks
            spec["puppet"] = pp
            job["puppet_pick"] = choice
            job["puppet_lane"] = None
        else:
            spec["choice"] = choice
        job["picked"] = choice
        job["phase"] = int(job.get("phase", 1)) + 1
        job["state"], job["front"] = "queued", True
        job["choices"] = []
        job["ended"], job["pid"] = None, None
        _derive(job)
        _ev_job(job, "picked", choice=choice, waiting_for=marker)   # pass 97 (lane PROGRESS, WF-02)
        _save()
        return _public(job, LOG_TAIL_SHORT)


def choice_id(src, choice):
    """pass 76 (lane ICON): the candidate a pick names, as its id: the Jobs tab and an item's icon candidates send the
    label ("c2", "#1"), the look picker the id ("2"); the pick tools read the id (gen_icon_cands looked for <key>_cc2.png)."""
    c = str(choice if choice is not None else "")
    ids = [str(x.get("id")) for x in (src.get("choices") or []) if isinstance(x, dict)]
    if c in ids:
        return c
    hit = next((str(x.get("id")) for x in (src.get("choices") or []) if isinstance(x, dict) and str(x.get("label")) == c), None)
    return hit if hit is not None else c


def install(job_id, choice, options=None):
    _writable()
    with _lock:
        src = _find(job_id) or _archived_raw(job_id)   # pass 97 (lane PROGRESS): an archived candidate job's pictures too
        if src is None:
            raise ValueError("no job %s" % job_id)
        if src["kind"] not in ("icon_cands", "hero_badge", "hero_title"):
            raise ValueError("nothing to install from a %s job" % src["kind"])
        if src["state"] != "done":
            raise ValueError("job %s is %s: its candidates are not ready" % (job_id, src["state"]))
        choice = choice_id(src, choice)
    spec = {"source_job": job_id, "choice": str(choice)}
    for k in ("head_width", "top_pad"):
        if options and options.get(k) is not None:
            spec[k] = options[k]
    # pass 76 (lane ICON): the server's install guard names the install's own new file (never an existing one), the look
    # it is for ("" = the base: the top-level icon) and why; the pick writes that file and lands through set_look_files
    if options and options.get("icon_file"):
        spec["icon_file"] = os.path.basename(str(options["icon_file"]))
        spec["icon_code"] = str(options.get("icon_code") or "")
        spec["why"] = str(options.get("why") or "")
    target = dict(src.get("target") or {})
    more = ""
    if options and options.get("variant") is not None:
        # pass 70: a candidate of any finished job installed into any look of the same asset (the look's picker): the
        # target look's own icon / cut-out ("" = the asset's own, the base look's top-level files)
        code = str(options.get("variant") or "").strip()
        if code and not re.match(r"^[A-Za-z0-9_-]+$", code):
            raise ValueError("bad look code %r" % code)
        t2 = dict(target, code=code)
        st = _look_state(t2)
        if code and not st["is_base"] and not st["entry"]:
            raise ValueError("%s has no look %s" % (target.get("id", "?"), code))
        target, spec["variant"] = t2, code
        more = " → %s" % (code or "its own")
    return enqueue("install", target, spec, title="install %s · %s #%s%s" % (src.get("title", ""), src["kind"], choice, more))


def move(job_id, delta):
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise ValueError("no job %s" % job_id)
        if job["state"] != "queued":
            raise ValueError("only a queued job moves")
        jobs = _state["jobs"]
        # pass 68 review: the order the worker takes them (_take_next): a picked continuation (front) first, then the list
        # order, a held job (_waits_for_look) skipped until its reference is painted; a job moves among its own group only
        # (front / runnable / held), so a swap always changes what the worker does next
        held = _waits_for_look(job)
        peers = [j for j in jobs if j["state"] == "queued" and j.get("lane") == job.get("lane")
                 and bool(j.get("front")) == bool(job.get("front")) and _waits_for_look(j) == held]
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
    _ev_job(job, "merged", written=written, error=error or "", redump=bool(redump))   # pass 97 (lane PROGRESS, WF-02)
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
        ro = {k: _readonly.get(k) for k in ("who", "pid", "host", "job", "view_only") if k in _readonly}
        ro["since"] = _epoch(_readonly.get("since"))
    return {"queued": counts["queued"], "running": counts["running"], "waiting": counts["waiting"], "lanes": lanes,
            "locks": locks.status_all(), "blender": blender_path(), "qa_online": _qa_cache["v"], "rev": _state["rev"],
            "workers": len(_workers), "readonly": ro, "archived": _archived_count()}   # pass 97 (lane PROGRESS): jobs in archive/


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
                _ev_job(job, "interrupted", why=job["error"])   # pass 97 (lane PROGRESS, WF-02)
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
        job = None
        try:
            job = _take_next(lane)   # inside the try: a failing save must never end the lane
            if job is None:
                _stop.wait(1.0)
                continue
            _run(job)
        except Exception as e:  # never let a lane die
            import traceback
            traceback.print_exc()
            if job is None:
                _stop.wait(1.0)
            else:
                with _lock:
                    if job["state"] == "running":
                        _finish(job, "failed", error="%s: %s" % (type(e).__name__, e))
                _request_after(job)   # pass 96 (lane REQ): a request's job that died in the worker
        finally:
            if job is not None:
                with _lock:
                    _lane_current[lane] = None


CANDIDATE_KINDS = ("icon_cands", "hero_badge", "hero_title")


def _waits_for_look(job):
    """A candidate job whose reference picture is not on disk yet while a look job of the same target (same id and code)
    is queued, running or waiting for a pick: the look paints that picture first (pass 68, the lead: creature_ctl waits
    for a pick while the comfy lane moves on, and a new look's candidates would otherwise paint before its front exists)."""
    if job.get("kind") not in CANDIDATE_KINDS:
        return False
    ref = str((job.get("spec") or {}).get("ref") or "")
    if not ref:
        return False
    if os.path.isfile(ref) or _resolve_pic(ref):   # the resolver the candidate checks use (tools/dl/ai_raw_anime/ -> RAW)
        return False
    t = job.get("target") or {}
    for o in _state["jobs"]:
        ot = o.get("target") or {}
        if (o is not job and o.get("kind") == "look" and o.get("state") in ("queued", "running", "waiting")
                and ot.get("id") == t.get("id") and str(ot.get("code") or "") == str(t.get("code") or "")):
            return True
    return False


def _frames_export_waits(job):
    """pass 95 resume (AN-08, E5): a queued frames_export waits while a frames_repair of the same look is queued, running or
    waiting, so the export packs the repair's result (staged at its landing) and never a half-landed store."""
    if job.get("kind") != "frames_export":
        return False
    t = job.get("target") or {}
    for o in _state["jobs"]:
        ot = o.get("target") or {}
        if (o is not job and o.get("kind") == "frames_repair" and o.get("state") in ("queued", "running", "waiting")
                and ot.get("id") == t.get("id") and str(ot.get("code") or "") == str(t.get("code") or "")):
            return True
    return False


def _take_next(lane):
    with _lock:
        cands = [j for j in _state["jobs"] if j["state"] == "queued" and j.get("lane") == lane and not _waits_for_look(j) and not _frames_export_waits(j)]
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
                    for x in o["spec"].get("after_export") or []:   # pass 95 resume: the exports an import follows, carried into the merged one
                        if x not in (job["spec"].get("after_export") or []):
                            job["spec"].setdefault("after_export", []).append(x)
                    o["state"], o["ended"], o["merged_into"] = "done", _now(), job["id"]
                    o["title"] = (o.get("title") or "import") + " (merged into %s)" % job["id"]
                job["spec"]["targets"] = targets
                _derive(job)
        job["state"], job["started"], job["front"] = "running", _now(), False
        if int(job.get("phase", 1) or 1) <= 1 or not job.get("attempt_started"):
            # the attempt's first start (a picked continuation's phase 2 keeps it): the stills older than this were reused (D4)
            job["attempt_started"] = job["started"]
        job["ended"], job["error"] = None, "" if "could not be written" not in job.get("error", "") else job["error"]
        job["progress"]["stalled"] = False
        job["server_pid"] = os.getpid()   # which editor runs it (a later editor's start must not kill it)
        _on_attempt_start(job)   # pass 97 (lane PROGRESS): no stale substage, the attempt's lock wait, the `started` event
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
        if job.get("kind") == "look" and (job.get("spec") or {}).get("keys"):
            # a forced repaint (a re-roll's --keys) is spent once it painted: a later plain Re-queue reuses the new stills.
            # No _derive here (pass 68 review): it set every stage back to pending; the card keeps its progress and the
            # command it ran, and requeue / edit derive the plan again before the next run
            job["spec"]["keys"] = []
    elif state in ("failed", "cancelled", "interrupted") and job.get("kind") != "launch":
        # what a stopped job made before it stopped (its workflows above all: the graph that failed is the one to open)
        try:
            job["outputs"] = _harvest(job)
        except Exception:
            pass
    _on_finish(job, state)   # pass 97 (lane PROGRESS): the substage goes; the `finished` event
    if save:
        _save()


def _acquire(job, live, name):
    """The lane's lock, saying who holds it meanwhile (lock_waits); None when the job was cancelled while waiting."""
    said = None
    t_wait0 = time.time()   # pass 97 (lane PROGRESS): the wait is kept per attempt (lock_wait_s)
    while not _stop.is_set():
        if live.cancelled:
            return None
        lk = locks.acquire(name, who="level_editor", job=job["id"], wait=False, log=_log)
        if lk is not None:
            with _lock:
                job["lock_waits"] = {}
                job["progress"]["stage"] = ""
                _add_lock_wait(job, name, time.time() - t_wait0)
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
        if plan["mode"] == "steps" and job["kind"] in ("driver_pose", "driver_depth", "ref_probe", "ref_render", "ref_limbs"):
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
            _snapshot_icons(job)   # pass 76 (lane ICON): the asset's icons into backups/<id>/ before anything paints
            if job["lane"] == "comfy":
                with _lock:
                    job["qa_online"] = qa_online()
            if plan["mode"] == "launch":
                rc = _run_launch(job, plan, live)
            elif plan["mode"] == "sim":
                rc = _spawn(job, live, plan["steps"][0])   # pass 77 (lane SIMUI): sim_parse moves its stages
            elif plan["mode"] == "steps":
                rc = _run_steps(job, plan, live)
            else:
                rc = _spawn(job, live, job["cmd"], _asset_env(job))
            _after_exit(job, rc, live)
            _request_after(job)   # pass 96 (lane REQ): a request's job ended (any way): its step function runs
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


# pass 92 (lane SPIDER): the made motions' keys (tools/blender_gait.py) with the tool's own defaults: a key is passed only
# when the job changes it and only to the mode that reads it, so the command line stays the short one Garry would type
SCALE_KEYS = (("body_scale", 1.0), ("head_scale", 1.0), ("leg_scale", 1.0), ("scale_bones", ""), ("head_pitch", 0.0))
GAIT_KEYS = SCALE_KEYS + (("legs", ""), ("base", ""), ("gait", "alternate"), ("swing", 14.0), ("lift", 18.0), ("flex", 14.0), ("duty", 0.55),
             ("bob", 0.04), ("sway", 2.5),
             # pass 93 (lane LEGS): step=track and its settings
             ("step", "swing"), ("stride", 0.22), ("raise", 0.12), ("crouch", 0.1), ("knee", "up"))
DEATH_KEYS = SCALE_KEYS + (("legs", ""), ("base", ""), ("seconds", 1.2), ("roll_axis", "side"), ("roll", 180.0), ("roll_dir", 1.0), ("roll_start", 0.08),
              ("roll_time", 0.4), ("curl", 70.0), ("curl_root", 40.0), ("curl_start", 0.05), ("curl_end", 0.75), ("bounce", 0.12),
              ("twitch", 6.0), ("spasm_deg", 22.0), ("hold", 0.85))


def loose_slug_dir(slug_dir, src):
    """pass 92 (lane SPIDER): a model lying in uploads/3d itself (dropped there by hand) writes its probe and renders into
    uploads/3d/<slug>/, the folder the editor's list reads (server.loose_models), not into uploads/3d where every loose
    model would share one probe.json."""
    if os.path.normcase(os.path.normpath(slug_dir)) != os.path.normcase(os.path.normpath(os.path.join(UPLOADS, "3d"))):
        return slug_dir
    stem = os.path.splitext(os.path.basename(src))[0].lower()
    slug = re.sub(r"[^a-z0-9]+", "_", stem).strip("_") or "upload"
    d = os.path.join(UPLOADS, "3d", slug)
    if os.path.isdir(d) and any(f.lower().endswith((".fbx", ".glb", ".gltf", ".obj", ".dae", ".blend")) for f in os.listdir(d)):
        d += "_loose"
    return d


def made_motion_args(spec):
    """The key=value words a driver_depth job adds for mode gait or flip_curl (none for cycle / oneshot)."""
    mode = str(spec.get("mode") or "cycle")
    keys = GAIT_KEYS if mode == "gait" else DEATH_KEYS if mode == "flip_curl" else ()
    out = []
    for k, dflt in keys:
        v = spec.get(k)
        if v in (None, ""):
            continue
        if isinstance(dflt, float):
            try:
                if abs(float(v) - dflt) < 1e-9:
                    continue
            except (TypeError, ValueError):
                pass
        elif str(v) == str(dflt):
            continue
        out.append("%s=%s" % (k, v))
    return out


def _blender_ready(kind, plan):
    bl = blender_path()
    if not bl:
        return "Blender not found: set BLENDER or install it under %LOCALAPPDATA%/Programs/blender-*/ (the page's status line shows the path)"
    script = {"driver_pose": "pose_driver.py", "driver_depth": "blender_depth_drivers.py", "ref_probe": "blender_ref.py", "ref_render": "blender_ref.py",
              "ref_limbs": "blender_limb_clone.py"}[kind]
    if not os.path.isfile(os.path.join(TOOLS, script)):
        if kind == "driver_depth":
            return "ask Claude for a depth driver: tools/blender_depth_drivers.py is not in this checkout yet"
        return "ask Claude: tools/%s is not in this checkout yet" % script
    return ""


def step_timeout(job, cmd):
    """pass 70: the seconds a step may run before it is killed (0 = no limit): a Godot step of a register or import job
    gets the job's `step_timeout`, else GODOT_STEP_TIMEOUT; every other step none."""
    if job.get("kind") not in ("register", "import") or not cmd or str(cmd[0]) != str(GODOT):
        return 0
    try:
        v = int(float((job.get("spec") or {}).get("step_timeout") or 0))
    except (TypeError, ValueError):
        v = 0
    return v if v > 0 else max(0, GODOT_STEP_TIMEOUT)


def _spawn(job, live, cmd, env_extra=None, cwd=None, timeout=0):
    """Run one command, its output to log.txt and the progress parser; returns the exit code (-1 when it could not start).
    `timeout` (pass 70): seconds after which the process tree is killed and live.timed_out says why (0 = none)."""
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
    t_start = time.time()
    while proc.poll() is None:
        now = time.time()
        if timeout and now - t_start > timeout and not live.timed_out:
            # pass 70: a hung step (a godot --import at no CPU) is killed so the Godot lock is freed for everyone
            live.timed_out = ("the step ran over its %d s limit and was killed (%s): Re-queue to run it again; the job's "
                              "step_timeout sets the limit" % (int(timeout), os.path.basename(str(cmd[0]))))
            try:
                live.logf.write(live.timed_out + "\n")
                live.logf.flush()
            except Exception:
                pass
            live.tail.append(live.timed_out)
            _kill_tree(proc.pid)
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
    if not RE_COMFY_STEP.match(line):   # pass 97 (lane PROGRESS): ComfyUI's step lines go to log.txt and the substage, not the card's tail
        live.tail.append(line)
    with _lock:
        job["progress"]["last_output"] = _now()
        seen = parse_line(job, line, live.key_to_stage)
        if _render_ok(seen, line):
            # pass 96 (lane PAGE, UI-02): a `render <key> seed N 12.3s ok` line lists the still on the card at once, not at
            # the next 5 s cache check (_harvest is idempotent: it is rebuilt from disk every time)
            try:
                job["outputs"] = _harvest(job)
            except Exception as e:   # pass 96 (lead): never let a harvest error stop the reader thread (the log would freeze)
                _log("harvest on the render line: %s: %s" % (type(e).__name__, e))
            live.last_save = live.last_save or time.time()
        m = stop_marker(line)
        if m:
            live.marker = m
        if not live.last_save:
            live.last_save = time.time()


def _render_ok(seen, line):
    """pass 96: whether a parsed line was a finished render (`render <key> seed N 12.3s ok`): the still is on disk now."""
    return bool(seen) and isinstance(seen, tuple) and seen[0] == "render" and str(line).rstrip().endswith(" ok")


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
RE_COMFY_PROMPT = re.compile(r"^comfy: prompt (\S+)")   # pass 96 (WF-06c): comfy.run's prompt id, so a cancel deletes that one
RE_VIEWS_SHEET = re.compile(r"views sheet:")


def stop_marker(line):
    """The human stops and the done-with-candidates lines: side | view | pick | review | badge | title; pass 71: puppet.py's
    puppet:pick:<what> | puppet:lane:<lane> | puppet:done; else None."""
    if line.startswith("puppet: "):
        return puppet_marker(line)
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
    stage_before = prog.get("stage")   # pass 97 (lane PROGRESS): a stage that moves clears the ComfyUI substage
    if job.get("kind") == "sim":
        return sim_parse(job, line)   # pass 77 (lane SIMUI): tools/sim_batch.py's "sim: ..." lines
    if job.get("method") == "hero_puppet" and (line.startswith("puppet: ") or line.startswith("[puppet ")):
        seen = puppet_parse(job, line)   # pass 71: the puppet's stages
        prog["done"] = sum(1 for s in stages if s.get("state") == "done")
        prog["total"] = len(stages)
        return seen
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
    m = RE_COMFY_PROMPT.match(line)
    if m:
        job["comfy_prompt"] = m.group(1)   # pass 96 (WF-06c): the newest prompt the job queued on ComfyUI
    marker = stop_marker(line)
    if marker in ("review", "badge", "title", "side", "view", "pick"):
        for s in stages:
            if s.get("type") in ("pack", "stop") or (s.get("type") == "still" and marker in ("review", "badge", "title", "side", "pick")):
                _mark(s, "done")
        prog["stage"] = {"side": "side candidates painted", "view": "view candidates painted", "pick": "candidates painted",
                         "review": "review sheet", "badge": "badge candidates", "title": "title candidates"}[marker]
        seen = seen or ("marker", marker)
    _comfy_progress(job, line, stage_before)   # pass 97 (lane PROGRESS, WF-07): progress.substage / progress.comfy_error
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
        if job.get("method") == "hero_puppet":
            changed = puppet_mark(job) or changed   # pass 71
        for s in job["progress"].get("stages", []):
            if s.get("state") == "done" or not s.get("key") or s.get("type") == "puppet":
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
        if live.timed_out:
            # pass 70: killed for its time limit; the worker's finally frees the lock, the card offers Re-queue
            _finish(job, "failed", error=live.timed_out)
            _rollback_after_import(job)   # pass 95 resume: an import that followed a Frames export undoes the export
            return
        if rc != 0:
            # the exception's own line first, then a tool's message, then the runner's; pass 97 (lane PROGRESS, OPS-02): on
            # ANSI-stripped lines, never an ANSI code alone (error_line)
            _finish(job, "failed", error=error_line(live.tail, rc))
            _rollback_after_import(job)   # pass 95 resume: an import that followed a Frames export undoes the export
            return
        marker = live.marker
        puppet_phase = job.get("method") == "hero_puppet" and job.get("puppet_next") != "walks"
        if marker in ("side", "view", "pick") and not puppet_phase:
            job["waiting_for"] = marker
            job["choices"] = _choices(job, marker)
            job["outputs"] = _harvest(job)
            job["state"], job["ended"], job["pid"] = "waiting", _now(), None
            job["progress"]["stage"] = {"side": "pick a side view", "view": "pick the views", "pick": "pick a front"}[marker]
            _save()
            return
    if puppet_phase:
        # pass 71: a puppet phase: a pick, the other lane, or the walks (puppet_after takes the lock itself)
        puppet_after(job, live)
        return
    # the post phase: merge through the hooks (outside the lock: the server's merge takes its own)
    written, error = _post(job)
    _ev_job(job, "landed", written=written, error=error or "")   # pass 97 (lane PROGRESS, WF-02): what the landing wrote
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


def _frames_repair_post(job, res):
    """pass 95 resume (AN-08, one writer of staged.json): the repair subprocess only adds versions; at the landing each
    version that asked to be staged is staged unless the slot is pinned or a hand choice was staged meanwhile (then it
    stays unstaged and the card says so). Returns (written, error) like _post."""
    t = job.get("target") or {}
    rep = ((res or {}).get("info") or {}).get("repair") or {}
    versions = rep.get("versions") or []
    if not versions:
        return {"file": "", "keys": [], "backup": "", "layout": "staged", "staged": [], "skipped": []}, ("" if rep else "the repair wrote no result.json (nothing landed)")
    try:
        import frames_io as FRIO
        r = FRIO.stage_versions(t.get("kind"), t.get("id"), t.get("code"), rep.get("base"), rep.get("view"), versions)
    except Exception as e:   # noqa: BLE001
        return {"file": "", "keys": [], "backup": "", "layout": "staged", "staged": [], "skipped": [{"slot": v.get("slot"), "id": v.get("id"), "why": "not staged: %s" % e} for v in versions]}, \
            "the versions landed but could not be staged: %s: %s (stage them in the Frames view)" % (type(e).__name__, e)
    return {"file": "", "keys": [], "backup": "", "layout": "staged", "staged": r.get("staged") or [], "skipped": r.get("skipped") or []}, ""


def _frames_rollback(job, info, why, restore_entry=False):
    """pass 95 resume (AN-09): a Frames export undone when its merge or the import after it failed: the strip put back
    from the export's backup and the exported choices staged again (frames_store.rollback_export); with restore_entry
    (the merge had gone through) the old entry is merged back through the hook, without `fresh`."""
    t = job.get("target") or {}
    out = {"ok": False, "why": why}
    try:
        import frames_io as FRIO
        r = FRIO.rollback(t.get("kind"), t.get("id"), t.get("code"), info.get("backup"), info.get("changed"), job=job["id"], why=why) or {}
        out.update(r)
        old = info.get("old_entry") or {}
        h = _hook("merge_look")
        if restore_entry and r.get("ok") and old and h:
            m = h(t["kind"], t["id"], t["code"], dict(old), {"pipeline": "frames_rollback", "why": why}) or {}
            out["entry_restored"], out["entry_error"] = bool(m.get("ok")), (m.get("error") or "")
    except Exception as e:   # noqa: BLE001
        out["error"] = "%s: %s" % (type(e).__name__, e)
    _log("jobs: Frames export %s rolled back (%s): %s" % (job["id"], why, json.dumps({k: out.get(k) for k in ("ok", "restored_from", "staged_again", "entry_restored", "error")})))
    return out


def _rollback_after_import(job):
    """pass 95 resume (AN-09): an import that followed a frames_export (spec.after_export) failed: the export is undone
    (the strip, the choices, the entry) and its card says so. Never raises (a rollback must not end the lane)."""
    try:
        if job.get("kind") != "import":
            return
        for jid in (job.get("spec") or {}).get("after_export") or []:
            ex = _find(jid)
            if not ex or ex.get("rolled_back"):
                continue
            info = (_result(ex) or {}).get("info") or {}
            if not info.get("backup"):
                continue
            ex["rolled_back"] = _frames_rollback(ex, info, "the import after it failed (%s)" % (job.get("error") or "")[:160], restore_entry=True)
            ex["error"] = ((ex.get("error") or "") + " | rolled back: the import failed; your frames are staged again").strip(" |")
    except Exception as e:   # noqa: BLE001
        _log("jobs: the rollback after import %s failed: %s: %s" % (job.get("id"), type(e).__name__, e))
    try:
        _save()
    except Exception as e:   # noqa: BLE001  (a script importing jobs.py without init: the queue stays in memory)
        _log("jobs: the queue was not saved after the rollback: %s" % e)


def _post(job):
    """The merge into the content JSON through the server's hooks; returns (written, error)."""
    kind, method, t = job["kind"], job.get("method"), job.get("target") or {}
    res = _result(job) or {}
    info = res.get("info") or {}
    try:
        if kind == "evaluate":   # pass 96 (lane LOOP): the findings on the job, nothing merged
            return _evaluate_post(job, res)
        if kind == "frames_repair":   # pass 95 resume (lane VACE): the repair's versions staged here, one writer of staged.json
            return _frames_repair_post(job, res)
        if (kind == "look" and method in ("hero_pose5", "hero_fit", "creature_free2", "creature_pose2", "creature_free8", "creature_proc", "creature_pictures", "creature_ctl", "hero_puppet")) \
                or kind == "frames_export":   # pass 95 (lane VACE): an export's entry lands like a look's
            entry = res.get("entry") or {}
            if not entry:
                return None, "the tool wrote no result.json entry (nothing merged)"
            h = _hook("merge_look")
            if not h:
                return {"file": "", "keys": ["variants"], "backup": "", "layout": "unmerged"}, "no merge hook: the entry sits in result.json"
            e = dict(entry)
            if kind != "frames_export":
                e["fresh"] = True   # pass 95 resume: an export is Garry's own choice of frames, never a NEW look
            r = h(t["kind"], t["id"], t["code"], e, info) or {}
            written = _written(t, r, ["variants"])
            if isinstance(r.get("frames"), dict):
                written["frames"] = _frames_landed_note(r["frames"])   # pass 96 (lane PAGE): "re-applied N pinned frames" / the pins that no longer fit
            if kind == "frames_export" and not r.get("ok"):
                # pass 95 resume (AN-09): the strip is already new while the entry is old: put the strip back, stage the choices again
                written["rollback"] = _frames_rollback(job, info, "the entry could not be merged: %s" % (r.get("error") or "?"))
                return written, "%s | rolled back: the strip was put back from its backup and your frames are staged again" % (r.get("error") or "the entry could not be merged")
            if r.get("ok"):
                try:
                    honest = _note_reused_stills(job)
                    if honest:
                        written["painter"] = honest
                except Exception as ex:   # the strip landed: a painter note that fails must not fail the job
                    written["painter"] = {"error": "%s: %s" % (type(ex).__name__, ex)}
            return written, ("" if r.get("ok") else str(r.get("error") or "the entry could not be merged"))
        if kind == "look" and method == "front_from_picture" and job.get("phase", 1) >= 2:
            # pass 70 (the pick race, lane ART): the pick writes only the key it owns, `stills` (the slug its picked
            # front is cached under), into the look's recipe as the JSON holds it NOW. It used to write the job's own
            # copy of the recipe ({stills, painter}) over the whole recipe, so a look job queued before the pick landed
            # lost its words (BD-A's first walk ran on the base dwarf's words).
            update = {"stills": str((job.get("spec") or {}).get("stills") or "")}
            hm = _hook("merge_recipe")
            if hm:
                r = hm(t["kind"], t["id"], t["code"], update) or {}
                return _written(t, r, ["variants"]), ("" if r.get("ok", True) else str(r.get("error", "")))
            h = _hook("set_recipe")
            if h:
                recipe = json.loads(json.dumps(_look_state(t)["recipe"] or {}))
                recipe.update(update)
                r = h(t["kind"], t["id"], t["code"], recipe, None) or {}
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
        if kind == "install" and (job.get("spec") or {}).get("icon_file"):
            return _post_install_icon(job, res)   # pass 76 (lane ICON)
        if kind == "install" and _install_code(job, res):
            return _post_install_look(job, res, _install_code(job, res))
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


def _frames_landed_note(sync):
    """pass 96 (lane PAGE, AN-09 Q4): what the frames store did at a landing, for the card: the pinned frames it queued a
    re-apply export for ("re-applied N pinned frames", the job), and the pins that no longer fit (reported, kept)."""
    out = {}
    rp = sync.get("reapply") if isinstance(sync.get("reapply"), dict) else None
    if rp:
        out["reapply"] = {"pinned": rp.get("pinned"), "job": rp.get("job"), "names": rp.get("names") or [], "error": rp.get("error") or ""}
        out["note"] = "%s%s" % (rp.get("note") or "re-applied %s pinned frames" % rp.get("pinned"), (" (export job %s)" % rp["job"]) if rp.get("job") else (": " + rp["error"] if rp.get("error") else ""))
    if sync.get("misfit"):
        out["misfit"] = sync["misfit"]
        out["misfit_text"] = sync.get("misfit_text") or ""
        out["note"] = (out.get("note", "") + "; " if out.get("note") else "") + (sync.get("misfit_text") or "some pinned frames could not be re-applied")
    if sync.get("error"):
        out["error"] = sync["error"]
    return out


def _note_reused_stills(job):
    """pass 68 (D4), the honest painter: at a look's landing, its stills whose PNG is older than the attempt's start were
    reused from the cache, not painted by this job's painter (MAM-C said Flux.2 dev at 32 steps; every still was MAM-B's
    Klein painting). The entry's recipe is read again from the file (Garry may have edited it while the job ran) and its
    `painter` written as the painter that ran (_painter_of the job's spec) plus, when stills were reused, `stills`:
    "reused" (all) or "N of M painted" and `reused`: [keys]; nothing more when every still was painted. Returns
    {painted, total, reused} or None (nothing to say: no stills, no start time, no hook)."""
    t = job.get("target") or {}
    started = _epoch(job.get("attempt_started") or job.get("started"))
    h = _hook("set_recipe")
    if started is None or not h or not t.get("code"):
        return None
    keys = [k for k in (job.get("cache_keys") or {}).get("stills", []) if "_side_k" not in k and os.path.isfile(os.path.join(RAW, k + ".png"))]
    if not keys:
        return None
    reused = [k for k in keys if os.path.getmtime(os.path.join(RAW, k + ".png")) < started]
    st = _look_state(t)
    if not st["entry"]:
        return None
    recipe = json.loads(json.dumps(st["recipe"]))
    old = recipe.get("painter") if isinstance(recipe.get("painter"), dict) else None
    want = _painter_of(job.get("spec") or {})
    if reused:
        want["stills"] = "reused" if len(reused) == len(keys) else "%d of %d painted" % (len(keys) - len(reused), len(keys))
        want["reused"] = reused
    out = {"painted": len(keys) - len(reused), "total": len(keys), "reused": reused}
    if old == want:
        return out
    recipe["painter"] = want
    h(t.get("kind", ""), t["id"], t["code"], recipe, None)
    return out


def _install_look_code(job):
    """The look code a candidate pick installs into (pass 68, D8): the target's code when it is a look of the file (not
    the base strip's own code), else ""."""
    t = job.get("target") or {}
    code = str(t.get("code") or "")
    if not code or not t.get("id"):
        return ""
    st = _look_state(t)
    return "" if st["is_base"] else code


def _install_code(job, res):
    """The look a pick lands in: the sidecar's `variant` when its entry names the file the tool wrote for it, else
    _install_look_code. (Since the pass 68 review the hero tools never name the base strip's code: a base pick is the
    hero's own <id>_icon.png + badge or hero_<id>.png, as candidate_defaults and the page assume.)"""
    ent = res.get("entry") if isinstance(res.get("entry"), dict) else {}
    if str(res.get("variant") or "").strip() and (ent.get("icon") or ent.get("title")):
        return str(res["variant"]).strip()
    return _install_look_code(job)


def _post_install_look(job, res, code=None):
    """pass 68 (D8): a candidate picked for a look lands in that look's entry: variants[CODE].icon (a badge or an icon)
    or variants[CODE].title (a title cut-out, a file under art/ui/wanted/), through the server's line-preserving writer
    with a backup, without the `fresh` mark (the strip is not touched). The file comes from the tool's sidecar entry,
    else from the names the tools write (an icon job's `file`, <id>_icon_<x>.png, hero_<id>_<x>.png) when on disk."""
    t = job.get("target") or {}
    code = str(code or t.get("code") or "")
    src = _find(str((job.get("spec") or {}).get("source_job", ""))) or _archived_raw(str((job.get("spec") or {}).get("source_job", ""))) or {}   # pass 97 (lane PROGRESS)
    entry = res.get("entry") if isinstance(res.get("entry"), dict) else {}
    files = {k: os.path.basename(str(entry[k])) for k in ("icon", "title") if entry.get(k)}
    if not files:
        folder = _content_folder(t.get("kind", ""), t.get("id", "")) or ""
        letter = _letter(code)
        if src.get("kind") == "icon_cands":
            name = os.path.basename(str(((src.get("plan") or {}).get("icon_job") or {}).get("file") or ""))
            if name and os.path.isfile(os.path.join(folder, name)):
                files = {"icon": name}
        elif src.get("kind") == "hero_badge":
            name = "%s_icon_%s.png" % (t.get("id", ""), letter)
            if os.path.isfile(os.path.join(folder, name)):
                files = {"icon": name}
        elif src.get("kind") == "hero_title":
            name = "hero_%s_%s.png" % (t.get("id", ""), letter)
            if os.path.isfile(os.path.join(WANTED, name)):
                files = {"title": name}
    if not files:
        return None, "the pick named no file for %s (nothing merged into its entry)" % code
    h = _hook("set_look_files")
    if not h:
        return {"file": "", "keys": ["variants"], "backup": "", "layout": "unmerged"}, "no set_look_files hook: %s sits on disk, not in the entry" % files
    r = h(t.get("kind", ""), t["id"], code, files) or {}
    w = _written(t, r, ["variants"])
    w["entry_keys"] = sorted(files)
    return w, ("" if r.get("ok") else str(r.get("error") or "the look's entry could not be written"))


def _post_install_icon(job, res):
    """pass 76 (lane ICON): an install the server's guard named a file for (spec.icon_file, never an existing file) lands
    through set_look_files for its look (spec.icon_code; "" = the base: the top-level icon), which keeps the look's
    icon_history and a copy of the icon it replaces under tools/level_editor/backups/<id>/; a hero base's badge block
    follows (merge_top). The file is the one the tool says it wrote (its sidecar entry, or info.icon_file)."""
    t = job.get("target") or {}
    spec = job.get("spec") or {}
    folder = _content_folder(t.get("kind", ""), t.get("id", "")) or ""
    ent = res.get("entry") if isinstance(res.get("entry"), dict) else {}
    info = res.get("info") if isinstance(res.get("info"), dict) else {}
    name = os.path.basename(str(ent.get("icon") or info.get("icon_file") or spec.get("icon_file") or ""))
    if not name or not os.path.isfile(os.path.join(folder, name)):
        return None, "the install wrote no icon file (looked for %s in %s)" % (name or "?", _rel(folder) if folder else "?")
    h = _hook("set_look_files")
    if not h:
        return {"file": "", "keys": ["icon"], "backup": "", "layout": "unmerged"}, "no set_look_files hook: %s sits on disk, not in the JSON" % name
    code = str(spec.get("icon_code") or "")
    r = h(t.get("kind", ""), t["id"], code, {"icon": name}, {"why": str(spec.get("why") or "install")}) or {}
    w = _written(t, r, ["variants"] if code else ["icon", "icon_history"])
    w["entry_keys"] = ["icon"]
    w["icon_file"] = name
    err = "" if r.get("ok") else str(r.get("error") or "the icon could not be written")
    top = res.get("top") or {}
    if top.get("badge") and _hook("merge_top"):
        r2 = _hook("merge_top")("hero", t["id"], {"badge": top["badge"]}) or {}
        if not r2.get("ok"):
            err = err or str(r2.get("error") or "the badge block could not be written")
        elif r2.get("keys"):
            w["keys"] = w["keys"] + [k for k in r2["keys"] if k not in w["keys"]]
    return w, err


def _snapshot_icons(job):
    """pass 76 (lane ICON): before a look, an item icon or an install job runs, every icon of its asset is copied into
    tools/level_editor/backups/<id>/ (the server's snapshot_icons hook; a picture already there is not copied again), so a
    repaint never loses one. Never fails the job."""
    if job.get("kind") not in ("look", "item_icon", "install"):
        return
    t = job.get("target") or {}
    h = _hook("snapshot_icons")
    if not h or not t.get("id"):
        return
    try:
        h(t.get("kind", "") or ("hero" if job.get("kind") == "install" else ""), t["id"])
    except Exception as e:
        _log("jobs: the icon snapshot of %s failed: %s: %s" % (t.get("id"), type(e).__name__, e))


def _after_done(job):
    """What follows a landing: an import job for new PNGs."""
    kind, t = job["kind"], job.get("target") or {}
    if kind in ("look", "item_icon", "install", "frames_export") and t.get("id"):   # pass 95: an export's strip needs the import too
        if kind == "look" and job.get("method") == "front_from_picture":
            return
        tf, jp = content_path(t.get("kind", ""), t["id"])
        if tf:
            try:
                spec = {"targets": ["%s/%s" % (tf, t["id"])]}
                if kind == "frames_export":
                    spec["after_export"] = [job["id"]]   # pass 95 resume: a failed import undoes this export (_rollback_after_import)
                enqueue("import", {"kind": t.get("kind", ""), "id": t["id"], "code": ""}, spec,
                        title="import %s/%s (after %s)" % (tf, t["id"], job["id"]), request=job.get("request"))   # pass 96: the import follows its request
            except ValueError:
                pass


# ---------------------------------------------------------------- pass 96 (lane REQ): the art requests' hook
# A job that carries `request` (enqueue(..., request=rid) or set_request) belongs to an art request
# (tools/level_editor/requests.py: the record above the request's jobs and the frame of the Auto-iterate loop). When
# such a job ends in any way (_run after _after_exit, a hand cancel, a worker crash) the request's step function runs
# and decides what to queue next. A job without `request` never reaches this: it runs exactly as before this pass.

def requests_module():
    """tools/level_editor/requests.py as one shared module object. The file is named by the plan; the PyPI library
    of that name may be in sys.modules first (a third party imported it): then ours is loaded from its file under the
    alias `le_requests`, so every caller (this hook, requests_io.py, the selftests) still shares one object."""
    m = sys.modules.get("requests")
    if m is not None and hasattr(m, "on_job_end"):
        return m
    if m is None:
        import importlib
        try:
            m2 = importlib.import_module("requests")
        except ImportError:
            m2 = None
        if m2 is not None and hasattr(m2, "on_job_end"):
            return m2
    m3 = sys.modules.get("le_requests")
    if m3 is None:
        import importlib.util
        spec = importlib.util.spec_from_file_location("le_requests", os.path.join(HERE, "requests.py"))
        m3 = importlib.util.module_from_spec(spec)
        sys.modules["le_requests"] = m3
        spec.loader.exec_module(m3)
    return m3


def set_request(job_id, rid):
    """A job stamped as part of an art request after the fact (an export queued through frames_io, a job LOOP's
    dispatcher queued through the plain enqueue). Returns the job's public record; ValueError without the job."""
    _writable()
    with _lock:
        job = _find(job_id)
        if job is None:
            raise ValueError("no job %s" % job_id)
        job["request"] = str(rid)
        _save()
        return _public(job, LOG_TAIL_SHORT)


def _request_after(job):
    """The request's step function after one of its jobs ended; nothing for a plain job; never raises (a broken
    request must not end a lane). An import that other imports were merged into (_take_next's coalescing) ends for
    their requests too: each is told with its own rid."""
    if not job:
        return
    rids = [job["request"]] if job.get("request") else []
    with _lock:
        for o in _state["jobs"]:
            if o.get("merged_into") == job.get("id") and o.get("request") and o["request"] not in rids:
                rids.append(o["request"])
    for rid in rids:
        try:
            requests_module().on_job_end(dict(job, request=rid))
        except Exception as e:   # noqa: BLE001
            _log("jobs: request %s: the step after %s failed: %s: %s" % (rid, job.get("id"), type(e).__name__, e))


# ---------------------------------------------------------------- harvest

def _url_dl(path):
    return "/dl/" + _rel(path).split("tools/dl/", 1)[-1] if "tools/dl/" in _rel(path) else "/dl/" + _rel(path)


def _still_output(key, label=None, since=None):
    png, meta = os.path.join(RAW, key + ".png"), os.path.join(RAW, key + ".json")
    if not os.path.isfile(png):
        return None
    out = {"label": label or key, "type": "still", "url": "/dl/ai_raw_anime/%s.png" % key, "cache_key": key}
    if since is not None and os.path.getmtime(png) < since:
        out["reused"] = True   # pass 68 (D4): older than the attempt: the cache's painting, not this job's
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


def _frames_outputs(job, res):
    """pass 95 (lane VACE): what a frames job's result.json names (info.outputs: sheets under tools/dl, the strip) as the
    card's outputs; a repair also says which versions it made and what was staged."""
    outs = []
    info = (res or {}).get("info") or {}
    for o in info.get("outputs") or []:
        f = str(o.get("file") or "")
        p = os.path.join(_root, f) if f and not os.path.isabs(f) else f
        if not p or not os.path.isfile(p):
            continue
        rec = {"label": str(o.get("label") or os.path.basename(p)), "type": str(o.get("type") or "sheet"), "file": _rel(p)}
        if o.get("type") == "strip":
            t = job.get("target") or {}
            rec["url"] = "/sprite/%s/%s/%s?v=%d" % (t.get("kind", ""), t.get("id", ""), t.get("code", ""), int(os.path.getmtime(p)))
        elif "tools/dl/" in _rel(p):
            rec["url"] = _url_dl(p) + "?v=%d" % int(os.path.getmtime(p))
        outs.append(rec)
    rep = info.get("repair") or {}
    if rep.get("versions"):
        outs.append({"label": "versions", "type": "json", "detail": {"versions": rep["versions"], "seconds": rep.get("seconds"), "window": rep.get("window"), "seed": rep.get("seed")}})
    if info.get("changed") is not None and job["kind"] == "frames_export":
        outs.append({"label": "frames changed", "type": "json", "detail": {"changed": info.get("changed"), "backup": info.get("backup")}})
    return outs


def _harvest(job):
    kind, method, t = job["kind"], job.get("method"), job.get("target") or {}
    spec = job.get("spec") or {}
    outs = []
    ck = job.get("cache_keys") or {}
    res = _result(job) or {}
    info = res.get("info") or {}
    kinds = info.get("clip_kind") or {}
    since = _epoch(job.get("attempt_started") or job.get("started")) if kind == "look" else None
    if kind in ("look", "item_icon", "hero_badge"):
        for k in ck.get("stills", []):
            o = _still_output(k, since=since)
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
        folder = _icon_folder(job)
        for c in _icon_choices(job):
            outs.append({"label": "%s_c%s" % (key, c["id"]), "type": "candidate", "url": c["url"]})
        rv = os.path.join(folder, "review_%s.png" % key)
        if os.path.isfile(rv):
            outs.append({"label": "review sheet", "type": "sheet", "url": "/dl/%s/review_%s.png" % (os.path.basename(folder), key)})
    if kind == "hero_badge":
        for name in ("%s_%s_badge_cands.png" % (t.get("id", ""), _badge_tag(job)), "%s_badge_cands.png" % t.get("id", "")):
            if os.path.isfile(os.path.join(REVIEW, name)):
                outs.append({"label": "badge candidates", "type": "sheet", "url": "/dl/review/" + name})
                break
    if kind == "hero_title":
        stem = _title_stem(job)
        for c in _title_choices(job):
            outs.append({"label": "%s_%s" % (stem, c["id"]), "type": "candidate", "url": c["url"]})
        if os.path.isfile(os.path.join(TITLE_OUT, "review_%s.png" % stem)):
            outs.append({"label": "review sheet", "type": "sheet", "url": "/dl/title_heroes/review_%s.png" % stem})
    if kind in ("driver_pose", "driver_depth", "driver_tweak"):
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
    if kind in ("ref_probe", "ref_render", "ref_limbs"):
        src = str(spec.get("src", ""))
        d = os.path.dirname(src) if os.path.dirname(src) else os.path.join(UPLOADS, "3d", os.path.splitext(os.path.basename(src))[0])
        d = d if os.path.isabs(d) else os.path.join(_root, d)
        d = loose_slug_dir(d, src)   # pass 92: a loose model's probe lives in uploads/3d/<slug>/
        if kind == "ref_limbs":
            d = os.path.join(UPLOADS, "3d", re.sub(r"[^a-z0-9_]+", "_", str(spec.get("name", "")).lower()).strip("_"))
            if os.path.isfile(os.path.join(d, "top.png")):
                outs.append({"label": "top.png (the legs from above)", "type": "still", "url": _url_dl(os.path.join(d, "top.png"))})
        for n in ("probe.json", "icon_ref.png", "thumbs.png"):
            if os.path.isfile(os.path.join(d, n)):
                outs.append({"label": n, "type": "json" if n.endswith(".json") else "still", "url": _url_dl(os.path.join(d, n))})
        for v in CTL_VIEWS:
            for n in ("clay.png", "look.png"):
                if os.path.isfile(os.path.join(d, v, n)):
                    outs.append({"label": "%s %s" % (v, n), "type": "still", "url": _url_dl(os.path.join(d, v, n))})
    if kind == "look" and method == "hero_puppet":
        outs = puppet_outputs(job) + outs   # pass 71: the arms-out sheets, the shape, the rig, the preview, the GLB, the guides
    if kind == "install" and res:
        outs.append({"label": "installed", "type": "json", "detail": {k: res.get(k) for k in ("tool", "call", "top") if res.get(k) is not None}})
    if kind in ("frames_repair", "frames_export"):
        outs += _frames_outputs(job, res)   # pass 95 (lane VACE): the repair's sheets, the exported strip
    if kind == "evaluate":
        outs += _evaluate_outputs(job, res)   # pass 96 (lane LOOP): the findings sheet and record
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
        out = _icon_choices(job)
    elif marker == "badge":
        out = _badge_choices(job)
    elif marker == "title":
        out = _title_choices(job)
    return out


# pass 68: a candidate job's choices are its own files only: k (or n) in range(seeds) under its own keys, never a stale
# _old<stamp> copy, a _view or a _raw file, or a picture an earlier job of the same hero left

def _seeds_of(job):
    return max(0, int((job.get("spec") or {}).get("seeds") or 4))


def _icon_choices(job):
    key = (job.get("plan") or {}).get("key", (job.get("target") or {}).get("id", ""))
    folder = _icon_folder(job)
    out = []
    for k in range(_seeds_of(job)):
        name = "%s_c%d.png" % (key, k)
        if os.path.isfile(os.path.join(folder, name)):
            out.append({"id": str(k), "label": "c%d" % k, "url": "/dl/%s/%s" % (os.path.basename(folder), name)})
    return out


def _badge_choices(job):
    """The job's own portraits (<id>_portrait_<tag>_c<k>); a tool that keys them the pre-68 way (<id>_portrait_c<k>) is
    read when none of the tagged ones is there."""
    hid = (job.get("target") or {}).get("id", "")
    n = _seeds_of(job)
    for keys in (_badge_keys(job, n), ["%s_portrait_c%d" % (hid, k) for k in range(n)]):
        out = [{"id": str(k), "label": "c%d" % k, "url": "/dl/ai_raw_anime/%s.png" % key}
               for k, key in enumerate(keys) if os.path.isfile(os.path.join(RAW, key + ".png"))]
        if out:
            return out
    return []


def _title_choices(job):
    stem = _title_stem(job)
    out = []
    for n in range(_seeds_of(job)):
        name = "%s_%d.png" % (stem, n)
        if os.path.isfile(os.path.join(TITLE_OUT, name)):
            out.append({"id": str(n), "label": "#%d" % n, "url": "/dl/title_heroes/" + name})
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
            rc = _spawn(job, live, step, env_extra=plan.get("env_steps"), timeout=step_timeout(job, step))   # pass 95: a step's own env (the frames jobs)
            if live.timed_out and rc == 0:
                rc = -9   # killed for its time limit: never a success
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
    `<id>_<CODE>/<job id>`, else `<id>_<kind>/<job id>` (goblin_GOB-E/j2026…, drifter_hero_badge/j2026…)."""
    t = job.get("target") or {}
    base = str(t.get("id") or job.get("kind") or "job")
    tail = str(t.get("code") or "") if job.get("kind") == "look" else str(job.get("kind") or "")
    name = "%s_%s" % (base, tail) if tail else base
    out = "".join(c if (c.isalnum() or c in "-_.") else "_" for c in name).strip("._")
    # a sub-folder per job: a re-roll of the same code is another job and must not overwrite the earlier copies
    return "%s/%s" % (out[:80] or "job", str(job.get("id") or "job"))


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


def _comfy_put_userdata(path, obj, timeout=10):
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
            except urllib.error.HTTPError as e:   # the server answered: this file was refused, the next may not be
                errors.append("%s: the ComfyUI server answered HTTP %s" % (stem, e.code))
            except OSError as e:   # the server did not answer (URLError is an OSError): the rest would wait as long
                errors.append("%s: the ComfyUI server did not answer (%s); the rest not tried" % (stem, e))
                break
            except Exception as e:
                errors.append("%s: %s" % (stem, e))
    with _lock:
        job["outputs"] = _harvest(job)
        _save()
        out = _public(job, LOG_TAIL_SHORT)
    if errors and not pushed:
        raise RuntimeError("nothing was sent to ComfyUI: " + "; ".join(errors))
    out["pushed"], out["push_errors"] = pushed, errors
    return out


_templates_pushed = {}


def push_templates(folder=None):
    """The method templates (tools/comfy_workflows/*.json, `python tools/comfy.py --export`) saved into the sidebar under
    workflows/88fits/templates/ (each once per server start and file change); returns [{name, path, open_url, error?}]."""
    folder = folder or os.path.join(TOOLS, "comfy_workflows")
    out = []
    down = ""
    if not os.path.isdir(folder):
        return out
    for f in sorted(os.listdir(folder)):
        if not f.endswith(".json"):
            continue
        full = os.path.join(folder, f)
        upath = "workflows/88fits/templates/%s" % f
        rec = {"name": f, "path": upath, "open_url": _comfy_open_url(upath)}
        if down:
            rec["error"] = down
        else:
            try:
                mtime = os.path.getmtime(full)
                if _templates_pushed.get(f) != mtime:
                    with open(full, "r", encoding="utf-8") as fh:
                        _comfy_put_userdata(upath, json.load(fh))
                    _templates_pushed[f] = mtime
            except urllib.error.HTTPError as e:
                rec["error"] = "the ComfyUI server answered HTTP %s" % e.code
            except OSError as e:   # the server did not answer: the rest would each wait the timeout
                down = rec["error"] = "the ComfyUI server did not answer (%s)" % e
            except Exception as e:
                rec["error"] = str(e)
        out.append(rec)
    return out


def _comfy_post(path, body, timeout=5):
    req = urllib.request.Request(COMFY_SERVER + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=timeout).read()


def _comfy_running_ids(timeout=5):
    """The prompt ids ComfyUI is running now (GET /queue: queue_running rows are [number, prompt_id, ...])."""
    try:
        with urllib.request.urlopen(COMFY_SERVER + "/queue", timeout=timeout) as r:
            q = json.load(r)
        out = []
        for row in (q.get("queue_running") or []):
            if isinstance(row, (_LIST, tuple)) and len(row) > 1:
                out.append(str(row[1]))
            elif isinstance(row, dict) and row.get("prompt_id"):
                out.append(str(row["prompt_id"]))
        return out
    except Exception:
        return None   # pass 96 (lead): "could not ask" is not "nothing runs": the caller interrupts anyway


def _comfy_interrupt(prompt_id=None):
    """After a cancelled comfy job (pass 96, WF-06c; lane REAL's lesson: a `clear` of the whole queue cost a hand run its
    12-minute prompt): only THIS job's prompt is touched. With its id (comfy.run prints `comfy: prompt <id>`,
    parse_line keeps it): POST /queue {delete: [id]} takes it out of the pending queue, and /interrupt is sent only
    while that id is the one running. Without an id (an older tool, a job that never reached /prompt): /interrupt
    alone, never `clear`. Returns what was sent (the selftest's fake ComfyUI records it too)."""
    sent = []
    if prompt_id:
        try:
            _comfy_post("/queue", {"delete": [str(prompt_id)]})
            sent.append(("/queue", {"delete": [str(prompt_id)]}))
        except Exception:
            pass
        running = _comfy_running_ids()
        if running is None or str(prompt_id) in running:
            try:
                _comfy_post("/interrupt", {})
                sent.append(("/interrupt", {}))
            except Exception:
                pass
        return sent
    try:
        _comfy_post("/interrupt", {})
        sent.append(("/interrupt", {}))
    except Exception:
        pass
    return sent


# ---------------------------------------------------------------- pass 71 (lane PLE): the Puppet method, hero_puppet
# Garry (2026-10-13): "add that in to LevelEditor with the considerations that I asked you about earlier": choose which 2D
# reference feeds the 3D model (or have one painted locally), preview the animated 3D model, the Puppet method in the job
# form like the others. A hero_puppet look job runs tools/puppet.py's stages (through tools/asset_job.py, tool "puppet")
# lane by lane: the comfy lane for the arms-out paintings and the Hunyuan3D shape, the local lane for Blender (clean, rig,
# the clips and colours, the guides); puppet.py stops where the work changes lane ("puppet: NEXT lane X"), at a pick
# ("puppet: PICK front|views|shape") and after the guides ("puppet: DONE guides"); the job then re-queues itself on the
# other lane (front of it), waits for the pick, or writes the guides into the look's recipe (pose_drivers, ctl_drivers,
# run_fit) and walks the look with gen_art on the comfy lane like hero_pose5, merged the same way.

PUPPET_DIR = os.path.join(DL, "puppet")
PUPPET_MIXAMO = os.path.join(DL, "mixamo")   # the Mixamo clips the form offers (--clip, --idle)
PUPPET_VIEWS = ("front", "side", "back")
PUPPET_STAGES = ("apose", "shape", "rig", "anim", "guides")
PUPPET_DEPTH_VIEWS = ("fd", "side", "bd", "back")   # the trial's best mix: depth for these, the puppet's OpenPose for the front
PUPPET_REUSE = ("auto", "fresh", "blend", "fbx")
# pass 71 follow-up: the settings a puppet look's recipe records under `puppet` (the form's choices; the job's own
# picks, one-shot reset / re-roll and seed shift are not settings)
PUPPET_SETTINGS = ("source", "stills", "refs", "painter", "steps", "turbo", "seeds", "first_seed", "words", "screen", "tries", "faces", "reuse", "fbx",
                   "clip", "idle", "frame", "face", "depth_views", "run_fit", "fringe")
RE_PUPPET_STAGE = re.compile(r"^puppet: STAGE (\w+) (start|done)(?: (\d+)s)?")
RE_PUPPET_GUIDES = re.compile(r"^puppet: GUIDES (\S+) (\S+) (\S+)")
RE_PUPPET_CAND = re.compile(r"^\[puppet [\d:]+\]\s+(front|side|back) c(\d+) seed (\d+) ([\d.]+)s")
RE_PUPPET_TRY = re.compile(r"^\[puppet [\d:]+\]\s+Hunyuan3D try (\d+) seed (\d+) ([\d.]+)s")


def puppet_dir(hero):
    return os.path.join(PUPPET_DIR, str(hero))


def puppet_spec(spec, target=None):
    """A hero_puppet job's own settings (spec.puppet) with their defaults (the form's, docs/assets_schema.md):
      source     the look whose stills the arms-out paintings are edited from (default: the one he is played in)
      stills     reuse | repaint: the walks on the source look's stills, or stills of the look's own (its letter)
      refs       {front, side, back}: paint | still:<key> | <picture path> | none (side/back): the 3D reference per view
      painter    klein | dev, steps (0 = the painter's default), turbo, seeds (fronts; side/back half, at least 3), seed,
                 first_seed (pass 72: the arms-out candidates' first seed, 0 = puppet.py's own)
      words      {front, side, back}: the edit's words in place of the template ("" = the template)
      tries      Hunyuan3D tries; faces: the cleaned mesh's triangle budget
      reuse      auto (what the hero's puppet already has is kept) | fresh (a new puppet: the old one moved aside) |
                 blend (from <hero>_puppet.blend, a rig fixed by hand) | fbx (a Mixamo-rigged FBX: `fbx`)
      clip, idle the moving clip and the idle (tools/dl/mixamo/<file>; idle "" = procedural)
      frame      soles | ankles: how the OpenPose guides are framed
      face       nose | head: the stick figures' face angle (the ears from the measured nose: a side view stays in
                 profile; head: on the head bone's axis, the trial's first guide)
      depth_views the views walked on the depth guide (Wan Fun Control); the others on the puppet's OpenPose (a list, or
                 a comma text as the typed recipe writes it)
      run_fit    true: each view's walk sized by the puppet's own run/idle height (silhouette.json)
      fringe     true (pass 71 follow-up: the default): gen_art's fringe_remap on the walks
    Pass 71 follow-up (Garry: every one a setting, seen in the look's recipe afterwards): the look's recipe records them
    under `puppet` (PUPPET_SETTINGS; written at Queue and Edit); a spec's own value wins over the recipe's, and a
    re-queue drops the spec's so the recipe as the JSON holds it (edited in Recipe (typed)) is what runs."""
    rec = ((spec or {}).get("recipe") or {}).get("puppet") if isinstance((spec or {}).get("recipe"), dict) else None
    pp = dict(rec) if isinstance(rec, dict) else {}
    if isinstance((spec or {}).get("puppet"), dict):
        pp.update(spec["puppet"])
    dvs = pp.get("depth_views")
    if isinstance(dvs, str):
        dvs = [x.strip() for x in dvs.replace(";", ",").split(",") if x.strip()]
    refs = pp.get("refs") if isinstance(pp.get("refs"), dict) else {}
    words = pp.get("words") if isinstance(pp.get("words"), dict) else {}
    out = {
        "source": str(pp.get("source") or ""),
        "stills": "repaint" if str(pp.get("stills") or "") == "repaint" else "reuse",
        "refs": {v: (str(refs.get(v) or "paint").strip() or "paint") for v in PUPPET_VIEWS},
        "painter": "dev" if str(pp.get("painter") or "") == "dev" else "klein",
        "steps": int(pp.get("steps") or 0),
        "turbo": pp.get("turbo") is not False,
        "seeds": max(1, int(pp.get("seeds") or 4)),
        "seed": int(pp.get("seed") or 0),
        # pass 72: the arms-out candidates' First seed (0 = puppet.py's own start)
        "first_seed": int(pp.get("first_seed") or 0),
        "words": {v: str(words.get(v) or "").strip() for v in PUPPET_VIEWS},
        "screen": str(pp.get("screen") or "").lower() if str(pp.get("screen") or "").lower() in ("blue", "green") else "",
        "tries": max(1, int(pp.get("tries") or 2)),
        "faces": max(5000, int(pp.get("faces") or 60000)),
        "reuse": str(pp.get("reuse") or "auto") if str(pp.get("reuse") or "auto") in PUPPET_REUSE else "auto",
        "fbx": str(pp.get("fbx") or ""),
        "clip": str(pp.get("clip") or "running.fbx"),
        "idle": str(pp.get("idle") or ""),
        "frame": "ankles" if str(pp.get("frame") or "") == "ankles" else "soles",
        "face": "head" if str(pp.get("face") or "") == "head" else "nose",
        "depth_views": [v for v in (dvs if isinstance(dvs, _LIST) else PUPPET_DEPTH_VIEWS) if v in CTL_VIEWS],
        "run_fit": pp.get("run_fit") is not False,
        "fringe": pp.get("fringe") is not False,
        "picks": dict(pp.get("picks") or {}) if isinstance(pp.get("picks"), dict) else {},
        "reset_from": str(pp.get("reset_from") or "") if str(pp.get("reset_from") or "") in PUPPET_STAGES else "",
        "reroll": str(pp.get("reroll") or "") if str(pp.get("reroll") or "") in ("front", "views", "shape") else "",
    }
    if out["refs"]["front"] == "none":
        out["refs"]["front"] = "paint"   # the shape is made from the front
    return out


def puppet_problem(spec, target):
    """Why a hero_puppet job cannot run as specified ("" when it can): a hero only, a picture that is not on disk, an
    FBX for reuse fbx, a clip that is not on disk."""
    if (target or {}).get("kind", "hero") != "hero":
        return "the Puppet method is for a hero (a humanoid the Mixamo clips fit)"
    pp = puppet_spec(spec, target)
    for v, src in pp["refs"].items():
        if src in ("paint", "none"):
            continue
        p = os.path.join(RAW, src[6:] + ("" if src.endswith(".png") else ".png")) if src.startswith("still:") else (src if os.path.isabs(src) else os.path.join(_root, src))
        if not os.path.isfile(p):
            return "the %s reference %s is not on disk" % (v, src)
    if pp["reuse"] == "fbx" and not (pp["fbx"] and os.path.isfile(pp["fbx"] if os.path.isabs(pp["fbx"]) else os.path.join(_root, pp["fbx"]))):
        return "reuse fbx needs the Mixamo-rigged FBX (puppet.fbx)"
    if pp["reuse"] == "blend" and not os.path.isfile(os.path.join(puppet_dir(target.get("id", "")), "%s_puppet.blend" % target.get("id", ""))):
        return "reuse blend: there is no tools/dl/puppet/%s/%s_puppet.blend yet" % (target.get("id", ""), target.get("id", ""))
    for k in ("clip", "idle"):
        n = pp[k]
        if n and not os.path.isfile(os.path.join(PUPPET_MIXAMO, n)) and not os.path.isfile(n if os.path.isabs(n) else os.path.join(_root, n)):
            return "the %s %s is not in tools/dl/mixamo" % (k, n)
    return ""


def _puppet_has(hero, name):
    return os.path.exists(os.path.join(puppet_dir(hero), name))


def puppet_lane(job):
    """The lane a hero_puppet job's next puppet phase starts on: the walks run on comfy; a phase that has a painting or
    the shape to make starts on comfy, anything else (Blender, a pick to apply before Blender) on local. A wrong guess
    costs one hop: puppet.py says where the work is ("NEXT lane")."""
    if job.get("puppet_next") == "walks":
        return "comfy"
    if job.get("puppet_lane") in ("comfy", "local"):
        return job["puppet_lane"]
    t = job.get("target") or {}
    hero = t.get("id", "")
    pp = puppet_spec(job.get("spec") or {}, t)
    pick = str(job.get("puppet_pick") or "")
    if pp["reuse"] in ("blend", "fbx"):
        return "local"
    if pp["reuse"] == "fresh" and not job.get("puppet_fresh_done"):
        return "comfy"   # a new puppet: its paintings and its shape are made again
    if pp["reset_from"] in ("apose", "shape") or pp["reroll"]:
        return "comfy"
    if "shape=" in pick:
        return "local"
    if "front=" in pick:
        return "comfy"
    views_pick = "side=" in pick or "back=" in pick
    if not views_pick and not _puppet_has(hero, "apose_front.png"):
        return "comfy" if pp["refs"]["front"] == "paint" else "local"
    if not views_pick:
        for v in ("side", "back"):
            if pp["refs"][v] == "paint" and not _puppet_has(hero, "apose_%s.png" % v):
                return "comfy"
    if not _puppet_has(hero, "shape.glb") and not _puppet_has(hero, "shape_raw.glb"):
        if all(_puppet_has(hero, os.path.join("shape", "try_%d.glb" % k)) for k in range(pp["tries"])):
            return "local"
        return "comfy"
    return "local"


def puppet_argv(job, lane):
    """puppet.py's command line for the job's next phase on `lane` (tools/asset_job.py runs puppet.main with it)."""
    t = job.get("target") or {}
    pp = puppet_spec(job.get("spec") or {}, t)
    argv = [t.get("id", ""), "--lane", lane, "--until", "guides"]
    if pp["source"]:
        argv += ["--look", pp["source"]]
    argv += ["--ref"] + ["%s=%s" % (v, pp["refs"][v]) for v in PUPPET_VIEWS]
    if pp["screen"]:
        argv += ["--screen", pp["screen"]]
    argv += ["--painter", pp["painter"], "--seeds", str(pp["seeds"])]
    if pp["steps"]:
        argv += ["--steps", str(pp["steps"])]
    if pp["painter"] == "dev" and not pp["turbo"]:
        argv.append("--no-turbo")
    if pp["seed"]:
        argv += ["--seed", str(pp["seed"])]
    if pp["first_seed"]:
        argv += ["--first-seed", str(pp["first_seed"])]
    for v in PUPPET_VIEWS:
        if pp["words"][v]:
            argv += ["--words-" + v, pp["words"][v]]
    argv += ["--tries", str(pp["tries"]), "--faces", str(pp["faces"]), "--clip", pp["clip"], "--frame", pp["frame"], "--face", pp["face"]]
    if pp["idle"]:
        argv += ["--idle", pp["idle"]]
    if pp["reuse"] == "blend":
        argv.append("--from-blend")
    elif pp["reuse"] == "fbx":
        argv += ["--from-fbx", pp["fbx"]]
    if pp["reset_from"]:
        argv += ["--reset-from", pp["reset_from"]]
    elif pp["reuse"] == "fresh" and not job.get("puppet_fresh_done"):
        argv += ["--reset-from", "apose"]   # a new puppet: the old one moved aside once, by the first phase
    if pp["reroll"]:
        argv += ["--reroll", pp["reroll"]]
    if job.get("puppet_pick"):
        argv += ["--pick", str(job["puppet_pick"])]
    return argv


def puppet_stage_defs(spec, target):
    """The puppet's stages on the job card: {name, key, type: "puppet", files} (a stage is done when its files are on
    disk; the guides once the look's recipe names them)."""
    hero = (target or {}).get("id", "")
    pp = puppet_spec(spec, target)
    d = puppet_dir(hero)
    recipe = (spec or {}).get("recipe") if isinstance((spec or {}).get("recipe"), dict) else {}
    views = [v for v in ("side", "back") if pp["refs"][v] != "none"]
    pose = str((recipe.get("pose_drivers") or {}).get("front") or "") if isinstance(recipe.get("pose_drivers"), dict) else ""
    out = [{"name": "arms-out front", "key": "puppet_apose_front", "type": "puppet", "files": [os.path.join(d, "apose_front.png")]}]
    if views:
        out.append({"name": "arms-out " + " + ".join(views), "key": "puppet_apose_views", "type": "puppet",
                    "files": [os.path.join(d, "apose_%s.png" % v) for v in views]})
    out += [{"name": "3D shape", "key": "puppet_shape", "type": "puppet", "files": [os.path.join(d, "shape.glb")]},
            {"name": "rig", "key": "puppet_rig", "type": "puppet", "files": [os.path.join(d, "%s_puppet.blend" % hero)]},
            {"name": "clips + colours (GLB)", "key": "puppet_anim", "type": "puppet", "files": [os.path.join(d, "%s_puppet.glb" % hero)]},
            {"name": "guides", "key": "puppet_guides", "type": "puppet",
             "files": [os.path.join(DRIVERS, pose, "meta.json")] if pose and "_puppet_" in pose else []}]
    return out


def puppet_mark(job):
    """Every puppet stage whose files are on disk marked done (a reused stage says "cached")."""
    changed = False
    for s in (job.get("progress") or {}).get("stages", []):
        if s.get("type") != "puppet" or s.get("state") == "done":
            continue
        files = s.get("files") or []
        if files and all(os.path.exists(f) for f in files):
            s["state"], changed = "done", True
            s.setdefault("note", "on disk")
    if changed:
        prog = job["progress"]
        prog["done"] = sum(1 for s in prog["stages"] if s.get("state") == "done")
    return changed


def puppet_parse(job, line):
    """A puppet.py log line into the job's progress: the stage that started or finished, a candidate or a try painted,
    the guides' names. Returns what it saw or None."""
    prog = job["progress"]
    st = {s.get("key"): s for s in prog.get("stages", [])}
    m = RE_PUPPET_STAGE.match(line)
    if m:
        name, what = m.group(1), m.group(2)
        keys = ["puppet_apose_front", "puppet_apose_views"] if name == "apose" else ["puppet_" + name]
        for k in keys:
            s = st.get(k)
            if s and s.get("state") != "done":
                if what == "start":
                    s["state"] = "running"
                break   # the first stage of the group not done yet is the one that runs
        prog["stage"] = {"apose": "the arms-out paintings", "shape": "the 3D shape (Hunyuan3D)", "rig": "the rig (Blender)",
                         "anim": "the clips and colours (Blender)", "guides": "the guides (OpenPose, depth, silhouette)"}.get(name, name) + ("" if what == "start" else " done")
        if what == "done" and m.group(3):
            s = st.get("puppet_" + name) if name != "apose" else None
            if s:
                s["secs"] = float(m.group(3))
        return ("puppet_stage", name, what)
    m = RE_PUPPET_GUIDES.match(line)
    if m:
        job["puppet_guides"] = {"pose": m.group(1), "depth": m.group(2), "silhouette": m.group(3)}
        s = st.get("puppet_guides")
        if s:
            s["state"] = "done"
        return ("puppet_guides", m.group(1))
    m = RE_PUPPET_CAND.match(line)
    if m:
        view = m.group(1)
        s = st.get("puppet_apose_front" if view == "front" else "puppet_apose_views")
        if s:
            s["state"] = "running"
            s["note"] = "%s c%s painted" % (view, m.group(2))
            s["secs"] = (s.get("secs") or 0) + float(m.group(4))
        prog["stage"] = "arms-out %s c%s" % (view, m.group(2))
        return ("puppet_cand", view)
    m = RE_PUPPET_TRY.match(line)
    if m:
        s = st.get("puppet_shape")
        if s:
            s["state"] = "running"
            s["note"] = "try %s made" % m.group(1)
            s["secs"] = (s.get("secs") or 0) + float(m.group(3))
        prog["stage"] = "Hunyuan3D try %s" % m.group(1)
        return ("puppet_try", m.group(1))
    return None


def puppet_marker(line):
    """puppet.py's stop lines as the jobs' markers: puppet:pick:<what>, puppet:lane:<lane>, puppet:done; else None."""
    if line.startswith("puppet: PICK "):
        return "puppet:pick:" + line.split()[2]
    if line.startswith("puppet: NEXT lane "):
        return "puppet:lane:" + line.split()[3]
    if line.startswith("puppet: DONE"):
        return "puppet:done"
    return None


def _puppet_url(hero, rel_name, stamp=True):
    p = os.path.join(puppet_dir(hero), rel_name)
    u = "/dl/puppet/%s/%s" % (hero, rel_name.replace("\\", "/"))
    if stamp and os.path.isfile(p):
        u += "?v=%d" % int(os.path.getmtime(p))
    return u


def puppet_choices(job, what):
    """The candidates of a puppet pick: front (apose/front_c<k>), views (side_c<k>, back_c<k>, one pick per group), shape
    (shape/try_<k>.png, the clay render of each Hunyuan3D try). Each choice's key is what puppet.py's --pick takes."""
    t = job.get("target") or {}
    hero = t.get("id", "")
    pp = puppet_spec(job.get("spec") or {}, t)
    d = puppet_dir(hero)
    out = []
    if what == "front":
        for k in range(pp["seeds"]):
            if os.path.isfile(os.path.join(d, "apose", "front_c%d.png" % k)):
                out.append({"id": "front=%d" % k, "key": "front=%d" % k, "label": "front c%d" % k, "url": _puppet_url(hero, "apose/front_c%d.png" % k)})
    elif what == "views":
        n = max(3, pp["seeds"] // 2)
        for v in ("side", "back"):
            if pp["refs"][v] != "paint" or os.path.isfile(os.path.join(d, "apose_%s.png" % v)):
                continue
            for k in range(n):
                if os.path.isfile(os.path.join(d, "apose", "%s_c%d.png" % (v, k))):
                    out.append({"id": "%s=%d" % (v, k), "key": "%s=%d" % (v, k), "label": "%s c%d" % (v, k), "group": v,
                                "url": _puppet_url(hero, "apose/%s_c%d.png" % (v, k))})
    elif what == "shape":
        for k in range(pp["tries"]):
            if os.path.isfile(os.path.join(d, "shape", "try_%d.png" % k)):
                out.append({"id": "shape=%d" % k, "key": "shape=%d" % k, "label": "try %d" % k, "url": _puppet_url(hero, "shape/try_%d.png" % k)})
        if os.path.isfile(os.path.join(d, "shape", "inputs_sheet.png")):
            out.append({"id": "", "label": "the views it was made from", "url": _puppet_url(hero, "shape/inputs_sheet.png"), "sheet": _puppet_url(hero, "shape/inputs_sheet.png")})
    return out


def puppet_outputs(job):
    """What the puppet made, for the job card: the arms-out sheets and picks, the shape, the rig, the preview, the GLB
    (type glb: the page's 3D viewer plays its clips) and the guides' sheets."""
    t = job.get("target") or {}
    hero = t.get("id", "")
    d = puppet_dir(hero)
    outs = []
    for name, label, typ in (("apose/front_sheet.png", "arms-out front candidates", "sheet"), ("apose_front.png", "the arms-out front", "still"),
                             ("apose/side_sheet.png", "side candidates", "sheet"), ("apose_side.png", "the arms-out side", "still"),
                             ("apose/back_sheet.png", "back candidates", "sheet"), ("apose_back.png", "the arms-out back", "still"),
                             ("shape/inputs_sheet.png", "Hunyuan3D's views", "sheet"), ("shape_preview.png", "the shape (clay)", "sheet"),
                             ("rig/rig_front.png", "the rig (x-ray)", "still"), ("rig/bendtest.png", "bend test", "sheet"),
                             ("%s_puppet_preview.png" % hero, "the puppet: turntable and run", "sheet")):
        if os.path.isfile(os.path.join(d, name)):
            outs.append({"label": label, "type": typ, "url": _puppet_url(hero, name)})
    glb = os.path.join(d, "%s_puppet.glb" % hero)
    if os.path.isfile(glb):
        # first on the card: the 3D puppet, turned and played in the page
        outs.insert(0, {"label": "the 3D puppet (run, idle)", "type": "glb", "url": _puppet_url(hero, "%s_puppet.glb" % hero),
                        "blend": _rel(os.path.join(d, "%s_puppet.blend" % hero)), "file": _rel(glb)})
    g = job.get("puppet_guides") or {}
    for key in ("pose", "depth"):
        nm = str(g.get(key) or "")
        if nm and os.path.isfile(os.path.join(DRIVERS, nm, "all_sheet.png")):
            outs.append({"label": "%s guides %s" % ("OpenPose" if key == "pose" else "depth", nm), "type": "sheet", "url": "/dl/drivers/%s/all_sheet.png" % nm})
    return outs


def puppet_recipe_update(job):
    """After the guides: the look's recipe walks on them. Every view's pose_drivers names the puppet's OpenPose guides
    (the fallback of a depth view too), ctl_drivers the depth guides for the depth views, run_fit the silhouette (unless
    off). Merged into the look's recipe as the JSON holds it (hooks.merge_recipe) and into the job's spec."""
    t = job.get("target") or {}
    spec = job.setdefault("spec", {})
    pp = puppet_spec(spec, t)
    g = dict(job.get("puppet_guides") or {})
    if not g.get("pose"):
        try:
            with open(os.path.join(puppet_dir(t.get("id", "")), "stages.json"), "r", encoding="utf-8") as f:
                rec = (json.load(f).get("guides") or {})
            g = {"pose": rec.get("pose_name"), "depth": rec.get("depth_name"), "silhouette": rec.get("silhouette")}
        except (OSError, ValueError):
            g = {}
    if not g.get("pose"):
        return None, "the puppet's guides are not named (no GUIDES line, no stages.json record)"
    update = {"pose_drivers": {v: g["pose"] for v in CTL_VIEWS},
              "ctl_drivers": ({v: g["depth"] for v in pp["depth_views"]} if pp["depth_views"] and g.get("depth") else None),
              "run_fit": g.get("silhouette") if pp["run_fit"] and g.get("silhouette") else None}
    update["fringe_remap"] = True if pp["fringe"] else None
    recipe = dict(spec.get("recipe") or {})
    for k, v in update.items():
        if v is None:
            recipe.pop(k, None)
        else:
            recipe[k] = v
    spec["recipe"] = recipe
    h = _hook("merge_recipe")
    if h and t.get("code"):
        try:
            r = h(t.get("kind", "hero"), t["id"], t["code"], update) or {}
            if not r.get("ok", True):
                return update, str(r.get("error") or "the recipe could not be written")
        except Exception as e:
            return update, "the recipe could not be written: %s" % e
    return update, ""


def puppet_after(job, live):
    """A puppet phase ended with exit 0: wait for a pick, hop to the other lane, or go on to the walks (the guides
    written into the look's recipe first, outside the jobs lock: the server's writer takes its own)."""
    m = live.marker or ""
    if not (m.startswith("puppet:pick:") or m.startswith("puppet:lane:")):
        update, err = puppet_recipe_update(job)
        if err:
            with _lock:
                _finish(job, "failed", error=err)
            return
    with _lock:
        pp = job["spec"].setdefault("puppet", {}) if isinstance(job["spec"].get("puppet"), dict) else job["spec"].setdefault("puppet", {})
        for k in ("reset_from", "reroll"):
            pp.pop(k, None)   # applied once, by the phase that just ran
        if puppet_spec(job["spec"], job.get("target"))["reuse"] == "fresh":
            job["puppet_fresh_done"] = True   # the old puppet was moved aside by that phase: never again for this job
        job["puppet_pick"] = None
        if m.startswith("puppet:pick:"):
            what = m.split(":")[2]
            job["waiting_for"] = "puppet_" + what
            job["choices"] = puppet_choices(job, what)
            job["outputs"] = _harvest(job)
            job["state"], job["ended"], job["pid"] = "waiting", _now(), None
            job["progress"]["stage"] = {"front": "pick the arms-out front", "views": "pick the arms-out side and back",
                                        "shape": "pick the 3D shape"}.get(what, "pick")
            _save()
            return
        if m.startswith("puppet:lane:"):
            job["puppet_lane"] = m.split(":")[2]
        else:
            job["puppet_next"] = "walks"
            job["puppet_lane"] = None
        job["phase"] = int(job.get("phase", 1)) + 1
        job["state"], job["front"] = "queued", True
        job["ended"], job["pid"] = None, None
        job["outputs"] = _harvest(job)
        _derive(job)
        _save()


def puppet_requeue(job, rr):
    """requeue's part for a hero_puppet job: {stage: X} = run again from that puppet stage (its outputs and the later
    ones moved aside by puppet.py --reset-from), {candidates: true} (a waiting pick's "Re-roll N more") = that pick's
    candidates painted again on new seeds; then the job starts at the puppet again (the walks after it)."""
    spec = job.setdefault("spec", {})
    pp = spec.setdefault("puppet", {}) if isinstance(spec.get("puppet"), dict) else spec.setdefault("puppet", {})
    # the settings as the look's recipe holds them now (Recipe (typed) may have changed them since the job ran)
    if isinstance((spec.get("recipe") or {}).get("puppet"), dict):
        for k in PUPPET_SETTINGS:
            pp.pop(k, None)
    stage = str((rr or {}).get("stage") or "")
    if stage:
        if stage not in PUPPET_STAGES:
            raise ValueError("a puppet re-run starts at one of %s" % ", ".join(PUPPET_STAGES))
        pp["reset_from"] = stage
    wf = str(job.get("waiting_for") or "")
    if (rr or {}).get("candidates") or (job.get("state") == "waiting" and wf.startswith("puppet_") and (rr or {}).get("seed") is not None):
        what = wf[len("puppet_"):] if wf.startswith("puppet_") else ""
        if what in ("front", "views", "shape"):
            pp["reroll"] = what
            pp["seed"] = int(pp.get("seed") or 0) + 1
    if stage or pp.get("reroll") or job.get("puppet_next") != "walks" or (rr or {}).get("puppet"):
        job["puppet_next"] = None
    job["puppet_lane"] = None
    job["puppet_pick"] = None
    job["waiting_for"] = None


def _seed_puppet_recipe(target, spec, recipe):
    """A hero_puppet look's recipe before it runs (pass 71): the source look's recipe (its stills slug, seed_offset,
    anim_seed, words, keys; never its run_scale, drivers, painter, method or `from`) for every key the recipe names none
    of, so the walks roll the source's seeds on its stills, as the trial's MAY-P did; "repaint" leaves `stills` out (the
    look's own letter, painted by gen_art with the Model settings) and drops the source's seed_offset."""
    pp = puppet_spec(spec, target)
    st = _look_state(target)
    doc = st["doc"]
    src_code = pp["source"] or str(doc.get("variant") or doc.get("variant_base") or "")
    vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    src = vs.get(src_code) if isinstance(vs.get(src_code), dict) else {}
    srec = src.get("recipe") if isinstance(src.get("recipe"), dict) else {}
    skip = {"run_scale", "pose_drivers", "ctl_drivers", "painter", "method", "from", "run_fit", "fringe_remap", "puppet"}
    if pp["stills"] == "repaint":
        skip |= {"stills", "seed_offset", "still_keys"}
    for k, v in srec.items():
        if k in skip or k in recipe:
            continue
        recipe[k] = json.loads(json.dumps(v))
    if pp["stills"] == "reuse" and recipe.get("stills") is None:
        recipe["stills"] = str(srec.get("stills") or "")
    if pp["fringe"]:
        recipe["fringe_remap"] = True
    else:
        recipe.pop("fringe_remap", None)
    spec["puppet"] = dict(spec.get("puppet") or {}, source=src_code)
    # pass 71 follow-up: every setting recorded in the look's recipe (Recipe (typed) shows them; a re-queue reads them)
    pp = puppet_spec(spec, target)
    recipe["puppet"] = {k: pp[k] for k in PUPPET_SETTINGS}


# ---------------------------------------------------------------- pass 77 (lane SIMUI): the run sim
#
# The Sim tab's Run sim queues one job of kind "sim" on its own lane ("sim"): one `python -u tools/sim_batch.py ...`
# process (mode "sim": _spawn, no lock here: the driver takes tools/dl/locks/sim.lock itself and never the Godot lock).
# Its output folder is tools/dl/sim/runs/<job id>[_a<attempt>] (the plan's sim_out), where the Sim tab reads
# progress.json and result.json; its "sim: ..." lines move the card's stages (the snapshot, one stage a run, the charts).

RE_SIM_RUN = re.compile(r"^sim: run (\d+)/(\d+) (started|done|failed)\b(.*)$")
RE_SIM_AT = re.compile(r"^sim: run (\d+) at (\d+:\d\d(?::\d\d)?)")
RE_SIM_WAIT = re.compile(r"^sim: waiting for the sim lock(.*)$")
RE_SIM_STEP = re.compile(r"^sim: (sync|import|import_json): (.*)$")


def _sim_mod():
    import sim_batch   # tools/sim_batch.py (TOOLS is on sys.path)
    return sim_batch


def sim_dir():
    """The sims' folder (tools/dl/sim): it follows DL, so a test's temporary DL holds its own sims and history."""
    return os.path.join(DL, "sim")


def sim_out_dir(job):
    """tools/dl/sim/runs/<job id>, a re-queue's attempt N in <job id>_aN (each attempt a sim of its own in the history)."""
    att = int(job.get("attempt", 1) or 1)
    return os.path.join(sim_dir(), "runs", str(job["id"]) + ("" if att <= 1 else "_a%d" % att))


def sim_check(spec):
    """The spec's settings checked and coerced by sim_batch.clean_settings (ValueError with every problem)."""
    s, probs = _sim_mod().clean_settings(spec)
    if probs:
        raise ValueError("sim: " + "; ".join(probs))
    out = dict(spec)
    out.update(s)
    return out


def sim_plan(job):
    spec = job.get("spec") or {}
    sb = _sim_mod()
    s, _ = sb.clean_settings(spec)
    out = sim_out_dir(job)
    tail = ["--hero", s["hero"], "--players", str(s["players"]), "--workers", str(s["workers"]), "--limit", str(s["limit"]),
            "--board", "%g" % max(0.0, s["board"]), "--talents", sb.talents_arg(s.get("talents") or {}), "--death", s["death"],
            "--seed", str(s["seed"]), "--map", s["map"], "--stage", str(int(s.get("stage", 1) or 1)), "--fps", str(s["fps"]), "--job", str(job["id"])]
    if s.get("board_label"):
        tail += ["--board-label", s["board_label"]]
    if not s.get("fast", True):
        tail.append("--no-fast")
    if s.get("note"):
        tail += ["--note", s["note"]]
    if s.get("bot"):
        tail += ["--bot", sb.bot_arg(s["bot"])]   # pass 80 (lane BOT): the bot's options
    if spec.get("synthetic"):
        tail.append("--synthetic")
        if spec.get("synthetic_speed"):
            tail += ["--synthetic-speed", "%g" % float(spec["synthetic_speed"])]
    argv = [PY, "-u", os.path.join(TOOLS, "sim_batch.py"), "--out", out, "--sim-dir", sim_dir()] + tail
    equiv = "python tools/sim_batch.py --out %s %s" % (_rel(out), " ".join(_q(a) for a in tail))
    return {"mode": "sim", "lock": None, "steps": [argv], "keep_save": False, "equiv": equiv, "sim_out": _rel(out),
            "sim_id": os.path.basename(out)}


def sim_stages(spec):
    s, _ = _sim_mod().clean_settings(spec)
    return ([{"name": "snapshot", "key": "", "type": "step"}]
            + [{"name": "run %d" % k, "key": "", "type": "run"} for k in range(1, int(s["players"]) + 1)]
            + [{"name": "charts", "key": "", "type": "pack"}])


def sim_eta(job):
    """The whole sim's estimate (sim_batch.eta_seconds: the snapshot, the runs in rounds at the measured speed)."""
    sb = _sim_mod()
    try:
        s, _ = sb.clean_settings(job.get("spec") or {})
        speed = sb.load_speed(os.path.join(sim_dir(), "speed.json"), fast=bool(s.get("fast", True)))   # the chosen mode's records
    except Exception:
        speed = None
    return int(sb.eta_seconds(job.get("spec") or {}, speed))


def sim_title(job):
    sb = _sim_mod()
    s, _ = sb.clean_settings(job.get("spec") or {}, legacy=True)
    name = (content_doc("hero", s["hero"]) or {}).get("name") or s["hero"]
    death = {"gold": "gold revives", "end": "no revive", "ad": "one ad revive", "keep": "every death counted"}.get(s["death"], s["death"])
    return "Sim · %s × %d to %s · board %s · %s" % (name, s["players"], sb.fmt_t(s["limit"]), sb.board_text(s.get("talents"), s.get("board_label")), death)


def sim_parse(job, line):
    """One line of tools/sim_batch.py into the card: the snapshot done at the first run's start, a run's stage running /
    done / failed, the running runs' clocks in the stage text, the charts done at "sim: done"."""
    prog = job["progress"]
    stages = prog.get("stages", [])
    by = {s.get("name"): s for s in stages}
    clocks = prog.setdefault("sim_clocks", {})
    seen = None
    step = ""
    m = RE_SIM_RUN.match(line)
    if m:
        k, what, rest = int(m.group(1)), m.group(3), m.group(4).strip(" :")
        snap = by.get("snapshot")
        if snap is not None and snap.get("state") != "done":
            _mark(snap, "done")
        st = by.get("run %d" % k)
        if what == "started":
            if st is not None and st.get("state") != "done":
                st["state"] = "running"
            clocks[str(k)] = "0:00"
        else:
            clocks.pop(str(k), None)
            if st is not None:
                _mark(st, "done" if what == "done" else "failed", note=rest[:90] or None)
        seen = ("run", k, what)
    else:
        m = RE_SIM_AT.match(line)
        if m:
            clocks[m.group(1)] = m.group(2)
            seen = ("at", int(m.group(1)), m.group(2))
        else:
            m = RE_SIM_WAIT.match(line)
            if m:
                step = "waiting for the sim lock" + m.group(1)
                seen = ("wait", "")
            else:
                m = RE_SIM_STEP.match(line)
                if m:
                    step = {"sync": "copying the game to the snapshot", "import": "the snapshot imports",
                            "import_json": "the snapshot imports the saved JSON"}[m.group(1)] + ": " + m.group(2)[:90]
                    seen = ("step", m.group(1))
                    if by.get("snapshot") is not None and by["snapshot"].get("state") == "pending":
                        by["snapshot"]["state"] = "running"
    if line.startswith("sim: done:"):
        if by.get("charts") is not None:
            _mark(by["charts"], "done")
        clocks.clear()
        seen = seen or ("done", "")
    elif line.startswith("sim: error:"):
        prog["sim_error"] = line[len("sim: error:"):].strip()[:200]
        seen = seen or ("error", "")
    runs = [s for s in stages if s.get("type") == "run"]
    done_runs = sum(1 for s in runs if s.get("state") in ("done", "failed"))
    if step:
        prog["stage"] = step
    elif seen and seen[0] in ("run", "at", "done"):
        live = sorted(clocks.items(), key=lambda kv: int(kv[0]))
        bits = ["%d of %d runs done" % (done_runs, len(runs))] + ["run %s at %s" % (k, c) for k, c in live[:6]]
        if len(live) > 6:
            bits.append("+%d more" % (len(live) - 6))
        prog["stage"] = " · ".join(bits) if not line.startswith("sim: done:") else "done: %d of %d runs" % (done_runs, len(runs))
    prog["done"] = sum(1 for s in stages if s.get("state") == "done")
    prog["total"] = len(stages)
    return seen


# ---------------------------------------------------------------- pass 97 (lane PROGRESS): progress, events, archive, ops
# WF-07: comfy.run's progress thread prints `comfy: <prompt> <node> <value>/<max>` and `comfy: <prompt> error <text>`
# (tools/comfy.py ProgressWatch); parse_line turns them into progress.substage / progress.comfy_error (_comfy_progress).
# WF-02: the events log (tools/level_editor/events.py, on only in the server process): one line at each choke point
# calls _ev_job / _ev_emit. The archive: finished records whose `ended` is older than ARCHIVE_DAYS move to
# JOBS_DIR/archive/queue_<YYYY-MM>.json (their folders untouched; get() still finds them; list() shows the live queue).
# OPS-02: the error-line rule (error_line), the per-attempt lock wait (lock_wait_s), the measured medians the ETA uses
# at >= MEASURED_MIN_SAMPLES (eta_source says which number the card shows).

RE_COMFY_STEP = re.compile(r"^comfy: (?!prompt )(\S+) (.+) (\d+)/(\d+)\s*$")
RE_COMFY_ERROR = re.compile(r"^comfy: (?!prompt )(\S+) error (.+)$")
ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b[@-Z\\-_]")
ARCHIVE_DAYS = 30
ARCHIVE_STATES = ("done", "failed", "cancelled")
MEASURED_MIN_SAMPLES = 5
MEASURED_TTL = 30.0
SEEDED_KINDS = ("icon_cands", "hero_badge", "hero_title", "front_from_picture")


def _ev():
    """tools/level_editor/events.py as one module object (None when it cannot be imported: nothing is logged). A
    third-party `events` in sys.modules first: ours is loaded from its file under the alias `le_events`."""
    m = sys.modules.get("events")
    if m is not None and hasattr(m, "job_event"):
        return m
    m = sys.modules.get("le_events")
    if m is not None:
        return m
    try:
        if m is None and sys.modules.get("events") is None:
            import events as m2
            if hasattr(m2, "job_event"):
                return m2
        import importlib.util
        spec = importlib.util.spec_from_file_location("le_events", os.path.join(HERE, "events.py"))
        m3 = importlib.util.module_from_spec(spec)
        sys.modules["le_events"] = m3
        spec.loader.exec_module(m3)
        return m3
    except Exception:   # noqa: BLE001
        return None


def _ev_job(job, event, **fields):
    """One job event (never raises; nothing when the log is off)."""
    try:
        m = _ev()
        if m is not None:
            m.job_event(job, event, **fields)
    except Exception:   # noqa: BLE001
        pass


def _ev_emit(kind, event, **fields):
    try:
        m = _ev()
        if m is not None:
            m.emit(kind, event, **fields)
    except Exception:   # noqa: BLE001
        pass


# ---- WF-07: the substage

def _running_view(job):
    """The view of the job's first unfinished still or clip stage (the one rendering now), or ""."""
    for s in (job.get("progress") or {}).get("stages") or []:
        if s.get("type") in ("still", "clip", "side") and s.get("state") not in ("done", "skipped"):
            words = re.split(r"[\s_/]+", str(s.get("name") or "") + " " + str(s.get("key") or ""))
            for v in ("front", "back", "side", "fd", "bd"):
                if v in words:
                    return v
            return ""
    return ""


def _comfy_progress(job, line, stage_before):
    """parse_line's tail: a `comfy: <prompt> <node> <v>/<max>` line -> progress.substage {node, value, max, at, since,
    prompt, view?}; `comfy: <prompt> error <text>` -> progress.comfy_error (+ comfy_error_prompt); a newer `comfy: prompt`
    clears the error (a retry queued a new prompt); a stage that moved clears the substage."""
    prog = job.setdefault("progress", {})
    m = RE_COMFY_ERROR.match(line)
    if m:
        prog["comfy_error"] = strip_ansi(m.group(2)).strip()[:300]
        prog["comfy_error_prompt"] = m.group(1)
        return
    m = RE_COMFY_STEP.match(line)
    if m:
        pid, node = m.group(1), m.group(2).strip()
        sub = prog.get("substage") if isinstance(prog.get("substage"), dict) else None
        now = _now()
        since = sub.get("since") if sub and sub.get("node") == node and sub.get("prompt") == pid and sub.get("since") else now
        new = {"node": node, "value": int(m.group(3)), "max": int(m.group(4)), "at": now, "since": since, "prompt": pid}
        view = _running_view(job)
        if view:
            new["view"] = view
        prog["substage"] = new
        return
    m = RE_COMFY_PROMPT.match(line)
    if m and prog.get("comfy_error_prompt") and prog.get("comfy_error_prompt") != m.group(1):
        prog.pop("comfy_error", None)
        prog.pop("comfy_error_prompt", None)
    if prog.get("stage") != stage_before and "substage" in prog:
        prog.pop("substage", None)


def _on_attempt_start(job):
    """_take_next: a run starts (an attempt, or a picked continuation): no stale substage or ComfyUI error; the lock
    wait starts again when the attempt is new; the `started` event."""
    prog = job.setdefault("progress", {})
    prog.pop("substage", None)
    prog.pop("comfy_error", None)
    prog.pop("comfy_error_prompt", None)
    att = int(job.get("attempt", 1) or 1)
    if job.get("lock_wait_attempt") != att:
        job["lock_wait_s"] = {}
        job["lock_wait_attempt"] = att
    _ev_job(job, "started", lane=job.get("lane"))


def _on_finish(job, state):
    """_finish: the substage goes (nothing renders any more; a ComfyUI error stays on the card); the `finished` event."""
    (job.get("progress") or {}).pop("substage", None)
    _ev_job(job, "finished", error=(job.get("error") or "")[:300], ended=job.get("ended"))


def _add_lock_wait(job, name, secs):
    """_acquire: the seconds this attempt waited for a lock, kept (lock_waits itself is cleared when the lock is taken)."""
    try:
        secs = float(secs)
    except (TypeError, ValueError):
        return
    if secs < 0.05:
        return
    att = int(job.get("attempt", 1) or 1)
    if job.get("lock_wait_attempt") != att:
        job["lock_wait_s"] = {}
        job["lock_wait_attempt"] = att
    w = job.setdefault("lock_wait_s", {})
    w[name] = round(float(w.get(name, 0.0)) + secs, 1)
    tot = job.setdefault("lock_wait_total_s", {})
    tot[name] = round(float(tot.get(name, 0.0)) + secs, 1)
    if secs >= 1.0:
        _ev_job(job, "lock_waited", lock=name, seconds=round(secs, 1))


# ---- OPS-02: the error line

def strip_ansi(text):
    return ANSI_RE.sub("", str(text or ""))


def error_line(tail, rc=None):
    """A failed job's `error`: the rule before pass 97 on ANSI-stripped lines with the blank ones left out (an ANSI reset
    `\\x1b[0m` alone was the error of four failed imports): newest first, the exception's own line (`<Name>Error: ...`,
    `...Exception`, `Exit...`) or a tool's message (gen_art:, gen_ctl:, gen_edit_stills:, gen_badge_cands:, SCRIPT ERROR);
    else a line with `asset_job:`, "error" (any case) or FAILED; else the last non-empty line; else "exit code <rc>"."""
    lines = []
    for x in tail or []:
        s = strip_ansi(x).rstrip("\r\n")
        if s.strip():
            lines.append(s)
    for x in reversed(lines):
        if re.match(r"^\w*(Error|Exception|Exit)\b", x) or x.startswith(("gen_art:", "gen_ctl:", "gen_edit_stills:", "gen_badge_cands:", "SCRIPT ERROR")):
            return x.strip()
    for x in reversed(lines):
        if x.startswith("asset_job:") or "error" in x.lower() or "FAILED" in x:
            return x.strip()
    if lines:
        # nothing telling: how the step ended and the last thing it said (a Godot crash at its teardown printed only
        # "[ DONE ] loading_editor_layout" and an ANSI reset)
        return ("%s after: %s" % (exit_text(rc), lines[-1].strip()))[:400]
    return exit_text(rc) if rc is not None else "exit code None"


# Windows NTSTATUS codes a crashed process exits with (as the unsigned and the signed number)
NTSTATUS = {0xC0000005: "an access violation (a crash)", 0xC00000FD: "a stack overflow (a crash)", 0xC0000409: "a stack buffer overrun (a crash)",
            0xC000013A: "Ctrl+C / the console closed", 0xC0000374: "a heap corruption (a crash)"}


def exit_text(rc):
    """"exit code 1", "exit code 0xC0000005: an access violation (a crash)", or "the step failed" (rc unknown)."""
    if rc is None:
        return "the step failed"
    try:
        u = int(rc) & 0xFFFFFFFF
    except (TypeError, ValueError):
        return "exit code %s" % rc
    if u in NTSTATUS:
        return "exit code 0x%08X: %s" % (u, NTSTATUS[u])
    return "exit code %s" % rc


def error_is_noise(err):
    """An `error` that says nothing once its ANSI codes are gone (the records before pass 97; the Ops view re-derives it)."""
    return bool(err) and not strip_ansi(err).strip()


def last_attempt_tail(job_id, n=LOG_TAIL_FULL):
    """The last `n` lines of a job's log.txt after its last attempt header (read-only)."""
    p = os.path.join(_job_dir(job_id), "log.txt")
    try:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return []
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].startswith("--- ") and " attempt " in lines[i]:
            lines = lines[i + 1:]
            break
    return lines[-n:]


# ---- OPS-02: measured medians (the ETA, the Ops fold)

def eta_key(job):
    """The key _eta looks up for a job (its method, creature_ctl's side phase, a dev icon set)."""
    kind, method = job.get("kind"), job.get("method") or job.get("kind")
    spec = job.get("spec") or {}
    key = method
    if method == "creature_ctl" and int(job.get("phase", 1) or 1) <= 1 and not spec.get("use_side"):
        key = "creature_ctl_side_dev" if spec.get("dev") else "creature_ctl_side"
    if kind == "icon_cands" and spec.get("dev"):
        key = "icon_cands_dev"
    return key


def attempt_seconds(job):
    """Seconds the record's last run took (ended - started; a candidate set's per seed, as _eta counts it), or None."""
    a, b = _epoch(job.get("started")), _epoch(job.get("ended"))
    if a is None or b is None or b < a:
        return None
    secs = b - a
    spec = job.get("spec") or {}
    if job.get("kind") in SEEDED_KINDS or job.get("method") == "front_from_picture":
        secs /= max(1, int(spec.get("seeds") or 1))
    return secs


def attempt_rendered(job):
    """False when the run painted nothing (every still and clip stage came from the cache), else True."""
    stages = [s for s in (job.get("progress") or {}).get("stages") or [] if s.get("type") in ("still", "clip", "side")]
    if not stages:
        return True
    return any(float(s.get("secs") or 0) > 0 for s in stages)


def _median_p90(xs):
    xs = sorted(xs)
    if not xs:
        return None
    n = len(xs)
    med = xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2.0
    p90 = xs[max(0, min(n - 1, -(-9 * n // 10) - 1))]   # the nearest rank: ceil(0.9 n)
    return {"median": round(med, 1), "p90": round(p90, 1), "n": n}


def measured_medians(records=None):
    """{key: {"rendered": {median, p90, n}, "cached": {...}}} over finished runs (done, or waiting after a phase) of at
    least one second."""
    samples = {}
    for j in (records if records is not None else _state["jobs"]):
        if j.get("state") not in ("done", "waiting") or j.get("merged_into"):
            continue
        secs = attempt_seconds(j)
        if secs is None or secs < 1.0:
            continue
        samples.setdefault(eta_key(j), {"rendered": [], "cached": []})["rendered" if attempt_rendered(j) else "cached"].append(secs)
    out = {}
    for k, v in samples.items():
        out[k] = {"rendered": _median_p90(v["rendered"]), "cached": _median_p90(v["cached"])}
    return out


_measured = {"t": 0.0, "rev": None, "n": None, "table": {}}


def _measured_table():
    """measured_medians() of this queue, kept MEASURED_TTL seconds (the ETA asks every 5 s per running job)."""
    now = time.time()
    st = _state
    age = now - _measured["t"]
    moved = _measured["rev"] != st.get("rev") or _measured["n"] != len(st["jobs"])
    if age > MEASURED_TTL or (moved and age > 5.0):
        try:
            _measured["table"] = measured_medians(st["jobs"])
        except Exception:   # noqa: BLE001
            _measured["table"] = {}
        _measured.update(t=now, rev=st.get("rev"), n=len(st["jobs"]))
    return _measured["table"]


def _measured_eta(job, key, med):
    """_eta's base number: the measured rendered median of this key at >= MEASURED_MIN_SAMPLES, else what _eta had
    (methods.json's median, else BUILTIN_MEDIAN); job["eta_source"] says which."""
    try:
        row = (_measured_table().get(key) or {}).get("rendered") or {}
        if int(row.get("n") or 0) >= MEASURED_MIN_SAMPLES and float(row.get("median") or 0) >= 1.0:
            job["eta_source"] = "measured"
            job["eta_samples"] = int(row["n"])
            return float(row["median"])
        m = _methods().get(job.get("method") or job.get("kind"))
        job["eta_source"] = "methods" if (m and isinstance(m.get("time"), dict) and m["time"].get("median_s")) else "builtin"
        job.pop("eta_samples", None)
    except Exception:   # noqa: BLE001
        pass
    return med


# ---- WF-02: the archive

_arch_cache = {}   # path -> ((mtime_ns, size), record)


def archive_dir():
    return os.path.join(JOBS_DIR, "archive")


def _archive_files():
    d = archive_dir()
    try:
        names = sorted(n for n in os.listdir(d) if n.startswith("queue_") and n.endswith(".json"))
    except OSError:
        return []
    return [os.path.join(d, n) for n in names]


def _archive_load(p, fresh=False):
    """An archive file {v, month, jobs: [...]} (cached by mtime and size), or None."""
    try:
        st = os.stat(p)
        sig = (st.st_mtime_ns, st.st_size)
    except OSError:
        return None
    hit = _arch_cache.get(p)
    if hit and hit[0] == sig and not fresh:
        return hit[1]
    try:
        with open(p, "r", encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(d, dict) or not isinstance(d.get("jobs"), _LIST):
        return None
    _arch_cache[p] = (sig, d)
    return d


def _write_json_atomic(p, obj):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
    for i in range(40):
        try:
            os.replace(tmp, p)
            return True
        except PermissionError:
            if i == 39:
                raise
            time.sleep(0.05)
    return False


def _archive_month(job):
    e = str(job.get("ended") or "")
    return e[:7] if re.match(r"^\d{4}-\d{2}", e) else "unknown"


def archive_finished(days=ARCHIVE_DAYS, now=None):
    """Finished records (done, failed, cancelled) whose `ended` is older than `days` move from queue.json to
    archive/queue_<YYYY-MM>.json (the month they ended). The records are copied as they are (never rewritten), each month
    written and read back before the queue lets them go; their folders stay. A record a live job still points at (an
    import's after_export, a merged import's target) waits. Only the editor that runs the queue does this."""
    if _readonly is not None or not _inited:
        return {"ok": False, "archived": 0, "skipped": "read-only" if _readonly is not None else "jobs.init() has not run"}
    if not _queue_file_ok():
        return {"ok": False, "archived": 0, "skipped": "QUEUE_FILE is not in JOBS_DIR"}
    cutoff = (now if now is not None else time.time()) - float(days) * 86400.0
    with _lock:
        refs = set()
        for j in _state["jobs"]:
            if j.get("state") not in ARCHIVE_STATES:
                refs.update(str(x) for x in ((j.get("spec") or {}).get("after_export") or []))
            if j.get("merged_into"):
                refs.add(str(j["merged_into"]))
        old = []
        for j in _state["jobs"]:
            t = _epoch(j.get("ended"))
            if j.get("state") in ARCHIVE_STATES and t is not None and t < cutoff and j["id"] not in refs and j["id"] not in _live:
                old.append(j)
        if not old:
            return {"ok": True, "archived": 0, "months": [], "kept": len(_state["jobs"])}
        by_month = collections.OrderedDict()
        for j in old:
            by_month.setdefault(_archive_month(j), []).append(j)
        months = []
        try:
            for month, recs in by_month.items():
                p = os.path.join(archive_dir(), "queue_%s.json" % month)
                cur = _archive_load(p, fresh=True) or {"v": 1, "month": month,
                                                       "about": "finished jobs moved out of tools/dl/jobs/queue.json (pass 97, jobs.archive_finished); their folders are untouched",
                                                       "jobs": []}
                at = {r.get("id"): i for i, r in enumerate(cur["jobs"]) if isinstance(r, dict)}
                for r in recs:
                    rc = json.loads(json.dumps(r, ensure_ascii=False))
                    if r["id"] in at:
                        cur["jobs"][at[r["id"]]] = rc
                    else:
                        cur["jobs"].append(rc)
                cur["updated"] = _now()
                _write_json_atomic(p, cur)
                back = _archive_load(p, fresh=True) or {}
                have = {r.get("id") for r in back.get("jobs") or [] if isinstance(r, dict)}
                if not all(r["id"] in have for r in recs):
                    raise RuntimeError("%s did not read back with every record" % p)
                months.append({"month": month, "n": len(recs), "file": _rel(p)})
        except Exception as e:   # noqa: BLE001  (nothing leaves the queue unless its month is safely written)
            _log("jobs: the archive was not written (%s: %s): the queue keeps every record" % (type(e).__name__, e))
            return {"ok": False, "archived": 0, "error": "%s: %s" % (type(e).__name__, e)}
        gone = {j["id"] for j in old}
        _state["jobs"][:] = [j for j in _state["jobs"] if j["id"] not in gone]
        _save()
        kept = len(_state["jobs"])
    _ev_emit("server", "archive", n=len(gone), months=months, days=days)
    return {"ok": True, "archived": len(gone), "months": months, "kept": kept}


def archive_tick(days=ARCHIVE_DAYS):
    """The server's start and its daily tick: the archive, and the events log rolled when it grew past its size."""
    out = {"archive": None, "events_rolled": None}
    try:
        out["archive"] = archive_finished(days)
    except Exception as e:   # noqa: BLE001
        out["archive"] = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
    try:
        m = _ev()
        if m is not None:
            out["events_rolled"] = m.roll_if_big()
    except Exception:   # noqa: BLE001
        pass
    return out


def archived_summary():
    """{total, months: [{month, n, file}]} of the archive (newest month first)."""
    months = []
    for p in reversed(_archive_files()):
        d = _archive_load(p) or {}
        months.append({"month": d.get("month") or os.path.basename(p)[6:-5], "n": len(d.get("jobs") or []), "file": _rel(p)})
    return {"total": sum(m["n"] for m in months), "months": months}


def archived_records(month=None):
    """The archived records (raw) of one month, or of every month (oldest first)."""
    out = []
    for p in _archive_files():
        d = _archive_load(p) or {}
        if month and (d.get("month") or os.path.basename(p)[6:-5]) != month:
            continue
        for r in d.get("jobs") or []:
            if isinstance(r, dict) and r.get("id"):
                out.append((p, r))
    return out


def archived_month(month):
    """GET /api/jobs/archived?month=YYYY-MM: the month's records as the page reads a job (no log tails)."""
    out = []
    for p, r in archived_records(month):
        pub = {k: v for k, v in r.items() if k != "plan"}
        pub["plan"] = {k: v for k, v in (r.get("plan") or {}).items() if k != "env"}
        pub["held"], pub["log_tail"], pub["archived"] = False, [], os.path.basename(p)
        out.append(pub)
    return out


def _archived_public(job_id):
    """get()'s fallback: an archived record as get() serves a job (its log tail from its folder), `archived` naming the
    file; None when no archive holds it."""
    for p in reversed(_archive_files()):
        d = _archive_load(p) or {}
        for r in d.get("jobs") or []:
            if isinstance(r, dict) and r.get("id") == job_id:
                pub = _public(r, LOG_TAIL_FULL, full=True)
                pub["archived"] = os.path.basename(p)
                return pub
    return None


def _archived_count():
    try:
        return archived_summary()["total"]
    except Exception:   # noqa: BLE001
        return 0


def _archived_raw(job_id):
    """An archived record as it was written (read-only: install reads a candidate job's choices), or None."""
    for p in reversed(_archive_files()):
        d = _archive_load(p) or {}
        for r in d.get("jobs") or []:
            if isinstance(r, dict) and r.get("id") == job_id:
                return json.loads(json.dumps(r, ensure_ascii=False))
    return None


def _unarchive(job_id):
    """requeue()'s fallback (under _lock): an archived record put back at the end of the queue (a copy; the archive keeps
    its own until the next archive replaces it by id), or None. The page never shows an archived job, so only an API call
    (Claude, a request's fold) gets here."""
    if _readonly is not None:
        return None
    rec = _archived_raw(job_id)
    if rec is None:
        return None
    rec.pop("archived", None)
    _state["jobs"].append(rec)
    _ev_job(rec, "unarchived")
    return rec

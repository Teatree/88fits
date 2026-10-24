#!/usr/bin/env python3
"""The Level Editor's local server (pass 53; pass 66: the asset editors' content model, routes and vocabularies).

    python tools/level_editor/server.py [--port 8787] [--no-browser]

Serves this folder (index.html, the scripts, the styles) on 127.0.0.1 and a JSON API over the content folders. The
routes are listed in docs/level_editor.md ("The API (for scripts)"); in short:

    the map (pass 53):      GET /api/maps, GET|POST /api/map/<id>, GET /api/enemies|elites|pickups|schema|status|turnover/<map>
    a creature's look:      POST /api/enemy/<id>/variant {"code"} (pass 54), POST /api/enemy/<id>/blood {"color"} (pass 58)
    pictures:               GET /icon/<kind>/<id>[/<code>], /sprite/<kind>/<id>[/<code>], /art/wanted/hero_<id>.png,
                            /dl/<rel> (tools/dl, chosen roots), /examples/<name>.png, /sound/<id>
    the asset editors (66): GET /api/vocab, /api/methods, /api/heroes, /api/items, /api/templates/<kind>,
                            /api/content/<kind>/<id>[/next_codes], /api/drivers, /api/refs
                            POST /api/content/<kind> (create from a template), /api/content/<kind>/<id>/save|variant|
                            retire|availability|delete|make_path|look, /api/content/<kind>/<id>/look/<code>,
                            /api/upload, /api/test_launch
    the jobs (66, jobs.py): GET /api/jobs[?since=rev], /api/job/<id>, /api/jobs/specs, /api/jobs/defaults?kind=&target=
                            (68); POST /api/jobs, /api/jobs/<id>[/cancel|requeue|pick|install|move|delete]; pass 97:
                            GET /api/jobs?since=rev&delta=1 -> {rev, changed, removed, delta[, order, full, unchanged]}
                            POST /api/jobs/requeue_interrupted {ids?, all?} -> {requeued, skipped, refused} (97, SAFE)
    the guard (97, SAFE):   every POST (and the one GET that writes, /api/frames/<kind>/<id>/<code>) needs a loopback Host
                            and no foreign Origin (403); a JSON route's body needs Content-Type: application/json (415)
    the run sim (77):       GET /api/sim/settings|status|history|result/<id>; POST /api/sim/settings|run|unlock,
                            /api/sim/<id>/keep|delete|cancel (sim_io.py; the sims are tools/sim_batch.py jobs of kind "sim")
    the icon guard (76):    GET /api/content/<kind>/<id>/icons, /iconfile/<kind>/<id>/<ref>; POST /api/content/<kind>/<id>/icon
                            {op: revert|use, code, ref, confirm} (also the look ops revert_icon / use_icon); an icon install
                            into the look in play or the base is a 409 confirm_needed until it is sent with confirm: true

Garry (the user) is not a programmer, so the server stays plain: the standard library only, nothing installed, nothing
fetched from the internet. What it writes: the map JSON it was asked to save; one content JSON at a time, edited line
by line in place (content_io.py: a key's own span is rewritten, every other byte stays, a layout it cannot keep is
refused rather than re-dumped); a brand-new content folder from a template; one unlock quest; the created-ids ledger
under tools/dl/jobs; uploads under tools/dl/uploads. Every content write leaves a backup under
tools/level_editor/backups/ (removed looks and deleted folders go to backups/deleted/<id>/<stamp>/). The JSON -> .tres
import after a write is CLAUDE.md's command, run under the repo-wide Godot lock (tools/locks.py) with the PC save kept
aside:
    Godot --headless --path game --script res://tools/import_json.gd -- only=<type>/<id>
The AI jobs (looks, icons, drivers, imports, the test launch) live in jobs.py (lane J); this file hands it the hooks it
writes content through and never starts a worker at import (selftest.py imports this module).
"""
import argparse
import glob
import json
import math
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")
GODOT = os.path.join(ROOT, "Godot_v4.7.2-stable_win64", "Godot_v4.7.2-stable_win64.exe")
BACKUPS = os.path.join(HERE, "backups")
SCHEMA = os.path.join(ROOT, "docs", "waves_schema.md")
ASSETS_SCHEMA = os.path.join(ROOT, "docs", "assets_schema.md")
METHODS = os.path.join(HERE, "methods.json")
EXAMPLES = os.path.join(HERE, "examples")
DL = os.path.join(ROOT, "tools", "dl")
UPLOADS = os.path.join(DL, "uploads")
DRIVERS = os.path.join(DL, "drivers")
LEDGER = os.path.join(DL, "jobs", "created.json")
WANTED_ART = os.path.join(GAME, "art", "ui", "wanted")
KEEP_BACKUPS = 30
IMPORT_TIMEOUT = 120
# how long a Save waits for the Godot lock before it queues an `import` job instead (seconds)
LOCK_WAIT = 120
# pass 103 (lane LE; Garry: "Stage 2 save is not working, it's just saying `Saving and importing...` and nothing is
# happening"): the map's Save waits this long, not LOCK_WAIT: two silent minutes read as a hang. The page then says who
# holds the lock and follows the queued import job until it has run.
SAVE_LOCK_WAIT = 8
ID_RE = re.compile(r"^[a-z0-9_]+$")
CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")
HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
FILENAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
# what a creature with no `blood` bleeds (EnemyDef.blood's default, Color(0.78, 0.05, 0.05), pass 58)
BLOOD_DEFAULT = "#c70d0d"
STATIC_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".md": "text/markdown; charset=utf-8",
    ".json": "application/json; charset=utf-8",
}
FILE_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif",
              ".json": "application/json; charset=utf-8", ".txt": "text/plain; charset=utf-8", ".wav": "audio/wav",
              ".ogg": "audio/ogg", ".mp3": "audio/mpeg", ".glb": "model/gltf-binary"}
# the folders the API reads, by the kind the page names (pass 66 added the heroes and the items)
KIND_FOLDERS = {"enemy": "enemies", "boss": "bosses", "elite": "elites", "pickup": "pickups", "hero": "characters",
                "weapon": "weapons", "evolution": "evolutions", "passive": "passives", "mutation": "mutations",
                "quest": "quests", "perk": "perks"}
# the kinds the asset editors create, save and delete (pass 69: a hero's perks, edited from the Heroes tab)
EDIT_KINDS = ("enemy", "boss", "hero", "weapon", "evolution", "passive", "mutation", "perk")
# the kinds that carry art looks (`variants`)
LOOK_KINDS = ("enemy", "boss", "hero")
# pass 73 (lane CARDS): the kinds whose looks are icons alone (the line items' fortune cards: A the old icon, B-E the four
# card framings): `variants {CODE: {icon, note, recipe?, shelved?}}` + `variant` + `variant_base`, no strips. Pass 76 (lane
# LOOKS): a weapon family's looks too (game/core/data/ItemLooks.gd): a weapon, an evolution or a mutation carries
# `variants {CODE: {name, flavour, text, icon, visual, params, noun, nouns, note, shelved, fresh}}` + `variant_base` ("A"),
# and the WEAPON's `variant` is the code its whole family plays (FAMILY_LOOK_KINDS)
ITEM_LOOK_KINDS = ("passive", "weapon", "evolution", "mutation")
FAMILY_LOOK_KINDS = ("weapon", "evolution", "mutation")
# every content type the game scans (JsonContent.TYPES): a new id must be free under all of them
ALL_TYPES = ["weapons", "evolutions", "passives", "mutations", "perks", "enemies", "bosses", "elites", "characters",
             "talents", "quests", "maps", "pickups", "structures", "boss_attacks"]
# the keys of a boss attack the estimate times its script by (pass 57)
SCRIPT_KEYS = ("name", "windup", "duration", "count", "enemy", "interval", "warn", "spawn")
# INTERFACES §0.1 (BALANCING §13): a new weapon starts hidden with its three template mutations and its evolution
NEW_WEAPON_STARTS_HIDDEN = True
# pass44_test.gd's quest-locked band of the base items (pass 69 re-pinned its floor to 0.28: the Salt, the Frisbee and
# five passive items came unlocked; selftest_L69 reads the bounds from the test file)
BAND_LO, BAND_HI = 0.28, 0.56
# tools/dl roots the page may read through /dl/<rel> (plus any root whose name starts with "icons")
DL_ROOTS = ("jobs", "drivers", "ai_raw_anime", "ai_anim", "review", "title_heroes", "uploads", "puppet", "frames")   # pass 95: the frames store
DL_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".json", ".txt", ".glb")
# pass 71 (lane PLE): the Puppet method's files (tools/dl/puppet/<hero>/: the arms-out paintings, the shape, the rig's
# x-rays, <hero>_puppet.glb with its clips) and the page's 3D viewer, vendored (tools/level_editor/vendor/: Google's
# <model-viewer>, a pinned release, so the page works offline)
PUPPET_DIR = os.path.join(DL, "puppet")
MIXAMO_DIR = os.path.join(DL, "mixamo")
VENDOR = os.path.join(HERE, "vendor")
VENDOR_TYPES = {".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".txt": "text/plain; charset=utf-8",
                ".md": "text/markdown; charset=utf-8", ".json": "application/json; charset=utf-8"}
UPLOAD_MAX = 200 * 1024 * 1024
UPLOAD_EXTS = {"2d": (".png", ".jpg", ".jpeg", ".webp", ".gif"), "3d": (".fbx", ".glb", ".gltf", ".obj", ".dae", ".blend", ".zip")}

sys.path.insert(0, os.path.join(ROOT, "tools"))
import ai_hosts  # noqa: E402  (pass 97, lane SAFE: tools/ai_hosts.json; the old literal when the file has none)
QA_URL = ai_hosts.get("lmstudio", "http://127.0.0.1:1234").rstrip("/") + "/v1/models"
import locks  # noqa: E402  (tools/locks.py: the repo-wide Godot and ComfyUI locks, the PC save kept aside)
import content_io as cio  # noqa: E402
import vocab as VOCAB  # noqa: E402
import boss_attacks_io as BAIO  # noqa: E402  (pass 72, lane BOSS: the custom boss attacks' routes)
import sim_io as SIMIO  # noqa: E402  (pass 77, lane SIMUI: the Sim tab's routes, /api/sim/...)
import drivers_io as DRVIO  # noqa: E402  (pass 93, lane PREVIEW: the driver library, /api/drivers[/<name>], /api/painted_death)
import frames_io as FRIO  # noqa: E402  (pass 95, lane VACE: the frames store's routes, /api/frames/...)
import requests_io as REQIO  # noqa: E402  (pass 96, lane REQ: the art requests, /api/requests..., /api/job/<id>/summary)
import events as EV  # noqa: E402  (pass 97, lane PROGRESS: the events log tools/dl/jobs/events.jsonl; on only in main())
import ops_io as OPSIO  # noqa: E402  (pass 97, lane PROGRESS: /api/ops, /api/events, /api/jobs/archived, server.log)
import eyes_io as EYESIO  # noqa: E402  (pass 98, lane GEMINI: /api/eyes, Check with Gemini, the frames' eyes)

_write_lock = threading.Lock()
# a test hook: a module-like object standing in for jobs.py (selftest_S.py); None = import jobs.py when it is there
JOBS = None
_jobs_error = [""]

# the keys the editors edit per kind: a Save removes a key only when it is one of these (an unknown key such as a
# `pose_fit` note or an `_ai` marker is never removed by a form that does not know it)
_COMMON_OWNED = {"id", "name", "flavour", "rarity", "element", "weight", "hidden", "from_stage", "icon", "placeholder",
                 "art_prompt", "note", "doc"}
_CREATURE_OWNED = _COMMON_OWNED | {
    "archetype", "brain", "hp", "damage", "speed", "size", "radius", "knockback", "knockback_resist", "damage_reduction", "contact_cd", "blood",
    "shadow", "head", "front_faces", "back_faces", "badge", "pack_size", "cap_share", "max_alive", "xp_mult", "can_be_elite",
    "can_be_grabbed", "pickup_chance_mult", "pickup_weights", "drops", "variance", "sfx", "ranged", "charge", "kamikaze",
    "artillery", "caster", "support", "ambush", "death_burst", "boss", "elite", "retired", "sprite", "anims", "fps",
    "frame_px", "strip_cols", "variant", "variant_base", "variants", "directions", "view_hints", "motion", "anim_negative",
    "dead_hint", "outline_frac", "outline_color", "remap_hues", "screen", "back_hint", "back_prompt", "pose", "pose_front",
    "gait", "stand", "walk", "hop_height", "death", "death_frames", "anim_seed", "run_fps", "cell_fill", "clip_fill", "grade",
    "key_sat", "key_min_value", "key_cut_shadow", "key_clamp_screen",
    "appearance"}   # pass 68 (D6): the character's words without a pose (a candidate job's `character` / icon subject)
_WEAPON_OWNED = _COMMON_OWNED | {"behavior", "targeting", "base", "levels", "max_level", "tags", "evolves_with", "evolves_into",
                                 "is_evolution", "evolved_from", "sfx", "params", "visual", "hero"}
EDITOR_OWNED = {
    "enemy": _CREATURE_OWNED, "boss": _CREATURE_OWNED,
    "hero": _COMMON_OWNED | {"trait", "trait_per_level", "order", "trait_name", "trait_text", "pronoun", "level_heal",
                             "favourite_weapon", "start_weapon", "favourite_bonus", "favourite_passive", "favourite_passive_bonus",
                             "specials", "momentum", "unlock_quest", "availability", "price", "currency_type", "frame_px",
                             "strip_cols", "fps", "anims", "sprite", "variant", "variant_base", "variants", "motion", "anim_hint",
                             "anim_negative", "anim_seed", "pose_drivers", "pose_motion", "pose_driven", "pose_hint", "back_hint",
                             "side_hint", "hurt_hint", "portrait_prompt", "still_keys", "run_fps", "screen", "key_sat",
                             "key_min_value", "key_cut_shadow", "key_clamp_screen", "grade", "remap_hues", "badge", "title_pose",
                             "title_holds", "title_camera", "title_extra_ref", "appearance"},
    "weapon": _WEAPON_OWNED, "evolution": _WEAPON_OWNED,
    "passive": _COMMON_OWNED | {"line", "levels", "repeat_last_level", "max_level", "pairs_with", "trade", "evolves_into",
                                "evolves_from", "text", "single"},
    "mutation": _COMMON_OWNED | {"weapon", "kind", "hero", "text", "vfx", "effects", "params", "behavior", "visual"},
    # pass 69: a perk (PerkDef: hero, text, effects, special, params)
    "perk": _COMMON_OWNED | {"hero", "text", "effects", "special", "params"},
}
# art keys a new folder does not take from its template (unless `copy_art`)
_ART_KEYS_RESET = ("sprite", "icon", "anims", "strip_cols", "fps", "head", "variant", "variant_base", "variants", "retired",
                   "hidden", "note", "badge", "still_keys")


# ---------------------------------------------------------------- content reading

def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def rel(path):
    """A path as the page shows it: relative to the repo with forward slashes, or absolute when it lies on another drive."""
    try:
        return os.path.relpath(path, ROOT).replace("\\", "/")
    except ValueError:
        return os.path.abspath(path).replace("\\", "/")


def mtime_of(path):
    try:
        return round(os.path.getmtime(path), 3)
    except OSError:
        return None


def content_folders(kind):
    """(id, folder, json path) for every content folder of `kind` that holds its <id>.json."""
    base = os.path.join(CONTENT, KIND_FOLDERS[kind])
    out = []
    if not os.path.isdir(base):
        return out
    for sub in sorted(os.listdir(base)):
        folder = os.path.join(base, sub)
        path = os.path.join(folder, sub + ".json")
        if os.path.isdir(folder) and os.path.isfile(path):
            out.append((sub, folder, path))
    return out


def content_path(kind, cid):
    """(type folder, json path) of `cid` under its kind's folder, or (None, None)."""
    if kind not in KIND_FOLDERS or not isinstance(cid, str) or not ID_RE.match(cid):
        return None, None
    path = os.path.join(CONTENT, KIND_FOLDERS[kind], cid, cid + ".json")
    if os.path.isfile(path):
        return KIND_FOLDERS[kind], path
    return None, None


def id_exists_anywhere(cid):
    """The content type folder that already holds a folder named `cid`, or None."""
    for t in ALL_TYPES:
        if os.path.isdir(os.path.join(CONTENT, t, cid)):
            return t
    if os.path.isdir(os.path.join(CONTENT, "sounds", cid)):
        return "sounds"
    return None


def list_maps():
    base = os.path.join(CONTENT, "maps")
    out = []
    if not os.path.isdir(base):
        return out
    for sub in sorted(os.listdir(base)):
        path = os.path.join(base, sub, sub + ".json")
        if os.path.isfile(path):
            try:
                d = load_json(path)
            except (OSError, ValueError):
                continue
            out.append({"id": sub, "name": str(d.get("name", sub)),
                        "file": rel(path)})
    return out


def map_path(map_id):
    return os.path.join(CONTENT, "maps", map_id, map_id + ".json")


def resolve_file(folder, name):
    """A content file named in a JSON: res:// under game/, else beside the JSON; None when it is not on disk."""
    if name.startswith("res://"):
        full = os.path.join(GAME, name[len("res://"):].replace("/", os.sep))
    else:
        full = os.path.join(folder, os.path.basename(name))
    return full if os.path.isfile(full) else None


def playable_codes(folder, d):
    """The art variant codes the game can play for this creature or hero JSON (JsonContent): the base strip's code
    (`variant_base`) and every other entry with a `sprite` whose file is on disk."""
    out = set()
    base_code = str(d.get("variant_base", ""))
    if base_code:
        out.add(base_code)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    for code, entry in vs.items():
        if str(code) == base_code or not isinstance(entry, dict) or not entry.get("sprite"):
            continue
        if resolve_file(folder, str(entry["sprite"])):
            out.add(str(code))
    return out


def item_playable_codes(folder, d, kind="passive"):
    """pass 73 (lane CARDS): the looks an item JSON can play (JsonContent._passive_variants): the base look's code
    (`variant_base`, its icon the top-level one) and every other entry with an `icon` whose file is on disk. Pass 76 (lane
    LOOKS): a weapon family member's (FAMILY_LOOK_KINDS) by family_playable_codes."""
    if kind in FAMILY_LOOK_KINDS:
        return family_playable_codes(folder, d)
    out = set()
    base_code = str(d.get("variant_base", ""))
    if base_code:
        out.add(base_code)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    for code, entry in vs.items():
        if str(code) == base_code or not isinstance(entry, dict) or not entry.get("icon"):
            continue
        if resolve_file(folder, str(entry["icon"])):
            out.add(str(code))
    return out


def item_looks(kind, cid, folder, d, play=None):
    """pass 73 (lane CARDS): one record per look of an item (the cards' A-E): {code, note, icon (the page's URL),
    icon_file, exists (its picture is on disk: the game can play it), base, default (the look the game plays), shelved,
    recipe (the words it was painted from), painted}; the base look first, then the others by code. Pass 76 (lane LOOKS):
    a weapon family member's records also carry name (the look's, else the item's), fresh, own (it has an entry for the
    code) and visual_file; its base is "A" when it names none; `play` is the code its family plays (family_member_play:
    a member wears its weapon's look, its base when it cannot), None = its own `variant` (a card, a weapon)."""
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    fam = kind in FAMILY_LOOK_KINDS
    base_code = family_base_code(d) if fam else str(d.get("variant_base", ""))
    playable = item_playable_codes(folder, d, kind)
    want = str(d.get("variant", base_code)) if play is None else str(play)
    play = want if want in playable else base_code
    top_icon = str(d.get("icon") or (cid + "_icon.png"))
    codes = sorted(set(vs.keys()) | ({base_code} if base_code else set()), key=lambda c: (c != base_code, c))
    out = []
    for code in codes:
        entry = vs.get(code) if isinstance(vs.get(code), dict) else {}
        is_base = code == base_code
        file_ = str(entry.get("icon") or (top_icon if is_base or fam else ""))
        recipe = entry.get("recipe") if isinstance(entry.get("recipe"), dict) else None
        rec = {"code": code, "note": str(entry.get("note", "")), "icon": "/icon/%s/%s/%s" % (kind, cid, code),
               "icon_file": file_, "exists": code in playable, "base": is_base, "default": code == play,
               "shelved": bool(entry.get("shelved", False)), "recipe": recipe,
               "painted": entry.get("painted") if isinstance(entry.get("painted"), dict) else None}
        if fam:
            rec.update({"name": str(entry.get("name") or d.get("name") or cid), "fresh": bool(entry.get("fresh", False)),
                        "own": isinstance(vs.get(code), dict), "visual_file": str(entry.get("visual", ""))})
        out.append(rec)
    return out


def item_look_state(kind, cid, folder, d, play=None):
    """{variant, variant_base, play, icon_play, looks} of an item for the page (pass 73, lane CARDS); pass 76 (lane
    LOOKS): a weapon family member's also `name_play` (the name it goes by in the look it wears); `play` as item_looks'."""
    looks = item_looks(kind, cid, folder, d, play)
    play = next((x["code"] for x in looks if x["default"]), "")
    out = {"variant": str(d.get("variant", "")), "variant_base": str(d.get("variant_base", "")), "play": play,
           "icon_play": "/icon/%s/%s/%s" % (kind, cid, play) if play else "/icon/%s/%s" % (kind, cid), "looks": looks}
    if kind in FAMILY_LOOK_KINDS:
        cur = next((x for x in looks if x["default"]), None)
        out["name_play"] = cur["name"] if cur else str(d.get("name", cid))
    return out


def set_item_looks_all(kind, code, ids=None):
    """POST /api/item_looks/set_all (pass 73, lane CARDS; Garry: "set every card to look X"): every line card (`line`
    true; or the ids given) that can play `code` gets its top-level `variant` set to it, one line each (a backup each,
    every other byte as it was); a card without that look painted keeps its own. One import of the changed folders."""
    # pass 76 (lane LOOKS): the cards only (a weapon family plays its weapon's look: write_variant_kind on the weapon)
    if kind != "passive":
        return {"ok": False, "error": "only the cards (passive) are set all at once; a weapon family plays its weapon's variant"}
    if not isinstance(code, str) or not CODE_RE.match(code):
        return {"ok": False, "error": "the body needs a look code: {\"code\": \"B\"}"}
    changed, kept, skipped = [], [], []
    for cid, folder, path, d in _load_kind(kind):
        if ids is not None and cid not in ids:
            continue
        if ids is None and not d.get("line"):
            continue
        if not isinstance(d.get("variants"), dict) or not d.get("variants"):
            skipped.append({"id": cid, "why": "no looks"})
            continue
        vs = d["variants"]
        if code not in item_playable_codes(folder, d) or (isinstance(vs.get(code), dict) and vs[code].get("shelved")):
            skipped.append({"id": cid, "why": "look %s not painted" % code if code not in item_playable_codes(folder, d) else "look %s shelved" % code})
            continue
        if str(d.get("variant", "")) == code:
            kept.append(cid)
            continue
        with _write_lock:
            src = cio.read_text(path)
            text = cio.set_top_block(src, "variant", code, [("before", "variants"), ("end", None)])
            if text is None:
                skipped.append({"id": cid, "why": "layout: not one top-level key per line"})
                continue
            backup(cid, path)
            cio.write_atomic(path, text)
        changed.append(cid)
    import_ok, output = (True, "nothing changed: no import")
    if changed:
        import_ok, output = run_import(",".join("%s/%s" % (KIND_FOLDERS[kind], c) for c in changed))
    return {"ok": True, "code": code, "changed": changed, "kept": kept, "skipped": skipped, "import_ok": import_ok, "output": output}


# ---------------------------------------------------------------- pass 76 (lane LOOKS): a weapon family's looks

# Garry, pass 76: the Grenade as a Dynamite Stick "as a Look (with several candidates), so I can switch back to the
# grenade if I ever change my mind", the Molotov "in several different versions". A weapon, an evolution or a mutation
# carries `variants` + `variant_base` (game/core/data/ItemLooks.gd); the WEAPON's `variant` is the look its whole family
# plays (Registry.played_item_look; a phone's Save.item_looks over it), and every member wears its entry for that code or
# its base. The Items tab's weapon editor shows the family's looks (family_looks) and plays one (write_variant_kind on
# the weapon); a member's editor says which look its family plays.

def family_base_code(d):
    """A weapon family member's base look: its `variant_base`, "A" when it has looks and names none (ItemLooks.read);
    "" without looks."""
    b = str(d.get("variant_base") or "")
    return b or ("A" if isinstance(d.get("variants"), dict) and d["variants"] else "")


def family_playable_codes(folder, d):
    """The looks a weapon family member's JSON can wear (ItemLooks.read): its base, and every entry whose files (`icon`,
    `visual`) are all on disk; an entry naming no file (words or params alone) plays too."""
    out = set()
    base = family_base_code(d)
    if base:
        out.add(base)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    for code, entry in vs.items():
        if not isinstance(entry, dict):
            continue
        if all(resolve_file(folder, str(entry[k])) for k in ("icon", "visual") if entry.get(k)):
            out.add(str(code))
    return out


def weapon_play_code(folder, wd):
    """The look a weapon's family plays by its JSON (no phone's choice here): its `variant` when it can play it, else its
    base; "" for a weapon without looks."""
    base = family_base_code(wd)
    want = str(wd.get("variant") or base)
    return want if want in family_playable_codes(folder, wd) else base


def family_weapon_id(kind, cid, d):
    """The weapon whose family a member belongs to (Registry.item_family_root): a weapon's own id, an evolution's
    `evolved_from` (else the weapon that evolves into it), a mutation's `weapon` (or that evolution's weapon); "" for none."""
    if kind == "weapon":
        return cid
    if kind == "evolution":
        src = str(d.get("evolved_from") or "")
        if src and content_path("weapon", src)[1]:
            return src
        for wcid, wfolder, wpath, wd in _load_kind("weapon"):
            if str(wd.get("evolves_into", "")) == cid:
                return wcid
        return ""
    if kind == "mutation":
        w = str(d.get("weapon") or "")
        if w and content_path("weapon", w)[1]:
            return w
        epath = content_path("evolution", w)[1] if w else None
        if epath:
            try:
                return family_weapon_id("evolution", w, load_json(epath))
            except (OSError, ValueError):
                return ""
    return ""


def family_member_play(kind, cid, d):
    """The look an evolution or a mutation wears in the game: its weapon's (weapon_play_code); None for a weapon (its own
    `variant` says it) and for a member of no weapon on disk."""
    if kind not in ("evolution", "mutation"):
        return None
    wid = family_weapon_id(kind, cid, d)
    wpath = content_path("weapon", wid)[1] if wid else None
    if not wpath:
        return None
    try:
        return weapon_play_code(os.path.dirname(wpath), load_json(wpath))
    except (OSError, ValueError):
        return None


def family_records_wear(w, members):
    """The Items list's records of a weapon family as the game wears it (list_items): every member's play, icon_play,
    name_play and looks' `default` follow the weapon's played look (a member without that look wears its base), each
    member names its `family`; the weapon's record gains `family_looks`, per look of the weapon: {code, note, shelved,
    fresh, exists, default, base, name, icon, members: [{kind, id, role, name, icon, own, hidden}]} (a member's own
    icon and name in that look, else its base's)."""
    code = str(w.get("play") or "")
    for m in members:
        m["family"] = w["id"]
        looks = m.get("looks") or []
        ok = [x["code"] for x in looks if x.get("exists")]
        mine = code if code and code in ok else next((x["code"] for x in looks if x.get("base")), "")
        for x in looks:
            x["default"] = x["code"] == mine
        m["play"] = mine
        m["icon_play"] = "/icon/%s/%s/%s" % (m["kind"], m["id"], mine) if mine else "/icon/%s/%s" % (m["kind"], m["id"])
        cur = next((x for x in looks if x["code"] == mine), None)
        m["name_play"] = cur.get("name", m["name"]) if cur else m["name"]
    out = []
    for lk in w.get("looks") or []:
        c = lk["code"]
        mem = []
        for m in members:
            ml = next((x for x in m.get("looks") or [] if x["code"] == c), None)
            own = bool(ml and ml.get("own") and ml.get("exists"))
            mem.append({"kind": m["kind"], "id": m["id"], "role": m.get("mutation_kind") or m["kind"],
                        "name": ml.get("name", m["name"]) if own else m["name"],
                        "icon": "/icon/%s/%s/%s" % (m["kind"], m["id"], c) if own else "/icon/%s/%s" % (m["kind"], m["id"]),
                        "own": own, "hidden": bool(m.get("hidden"))})
        out.append({"code": c, "note": lk["note"], "shelved": lk["shelved"], "fresh": lk.get("fresh", False),
                    "exists": lk["exists"], "default": lk["default"], "base": lk["base"], "name": lk.get("name", w["name"]),
                    "icon": lk["icon"], "members": mem})
    w["family_looks"] = out


def _num(v, default):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else default


def _imported_flag(folder, png_name, json_path, cid):
    """Whether the game would see this strip (critique 26): the PNG's .import exists AND the .tres is newer than both the
    JSON and the PNG. None when the PNG itself is not there."""
    png = resolve_file(folder, png_name) if png_name else None
    if not png:
        return None, None
    png_mtime = os.path.getmtime(png)
    if not os.path.isfile(png + ".import"):
        return False, int(png_mtime)
    tres = os.path.join(folder, cid + ".tres")
    if not os.path.isfile(tres):
        return False, int(png_mtime)
    tm = os.path.getmtime(tres)
    return bool(tm >= os.path.getmtime(json_path) - 0.001 and tm >= png_mtime - 0.001), int(png_mtime)


def look_records(kind, cid, folder, d, json_path=None):
    """One record per look of a creature or hero JSON (INTERFACES §6): the base strip's code (from `variant_base`, with
    or without its own entry) and every `variants` entry, with what the game reads per look (its own values, else the
    top-level ones as JsonContent falls back; a non-base entry's `strip_cols` defaults to 0), the page-only flags and
    the import state."""
    json_path = json_path or os.path.join(folder, cid + ".json")
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    base_code = str(d.get("variant_base", ""))
    playable = playable_codes(folder, d)
    want = str(d.get("variant", base_code))
    play = want if want in playable else base_code
    top_sprite = str(d.get("sprite", cid + "_sprite.png"))
    top_anims = d.get("anims") if isinstance(d.get("anims"), dict) else (VOCAB.CHAR_ANIMS_DEFAULT if kind == "hero" else VOCAB.ENEMY_ANIMS_DEFAULT)
    top_fps = d.get("fps") if isinstance(d.get("fps"), dict) else {}
    top_cols = int(_num(d.get("strip_cols"), 0))
    top_px = int(_num(d.get("frame_px"), 256 if kind == "hero" else 128))
    top_head = _num(d.get("head"), 0.86)
    out = []

    def record(code, entry, is_base):
        entry = entry if isinstance(entry, dict) else {}
        sprite_name = top_sprite if is_base else str(entry.get("sprite", ""))
        imported, sprite_mtime = _imported_flag(folder, sprite_name, json_path, cid)
        recipe = entry.get("recipe") if isinstance(entry.get("recipe"), dict) else None
        rec = {"code": code, "note": str(entry.get("note", "")),
               "icon": "/icon/%s/%s/%s" % (kind, cid, code), "sprite": "/sprite/%s/%s/%s" % (kind, cid, code),
               "ready": True if is_base else code in playable, "base": is_base, "default": code == play,
               "anims": top_anims if is_base or not isinstance(entry.get("anims"), dict) else entry["anims"],
               "fps": top_fps if is_base or not isinstance(entry.get("fps"), dict) else entry["fps"],
               "strip_cols": top_cols if is_base else int(_num(entry.get("strip_cols"), 0)),
               "frame_px": top_px if is_base else int(_num(entry.get("frame_px"), top_px)),
               "head": top_head if is_base else _num(entry.get("head"), top_head),
               "front_faces": str(entry.get("front_faces", d.get("front_faces", "right"))),
               "back_faces": str(entry.get("back_faces", d.get("back_faces", "right"))),
               "shadow": entry.get("shadow") if isinstance(entry.get("shadow"), dict) else (d.get("shadow") if isinstance(d.get("shadow"), dict) else {}),
               "shelved": bool(entry.get("shelved", False)), "fresh": bool(entry.get("fresh", False)),
               "imported": imported, "sprite_mtime": sprite_mtime,
               "sprite_file": sprite_name, "icon_file": str(entry.get("icon", "")) if entry.get("icon") else "",
               "has_recipe": recipe is not None, "recipe": recipe}
        if kind == "hero":
            # pass 68 (D8): a look's own title cut-out (art/ui/wanted/<file>), picked from its hero_title candidates
            rec["title_file"] = str(entry.get("title", "")) if entry.get("title") else ""
        return rec

    if base_code and base_code not in vs:
        # the top-level strip is a look of its own even when the JSON gives it no entry (JsonContent adds it)
        r = record(base_code, {"note": "the top-level strip"}, True)
        out.append(r)
    for code, entry in vs.items():
        out.append(record(str(code), entry, str(code) == base_code))
    return out


def creature_record(kind, cid, folder, d, json_path=None):
    """What the palette, the selects and the override placeholders need from one creature's JSON."""
    boss = d.get("boss") if isinstance(d.get("boss"), dict) else None
    boss_out = None
    if boss is not None:
        names = []
        for a in boss.get("attacks", []) or []:
            if isinstance(a, dict) and a.get("name"):
                names.append(str(a["name"]))
            elif isinstance(a, str):
                names.append(a)
        boss_out = {"attacks": names}
        for k in ("cooldown_between", "hp_mult_per_stage"):
            if k in boss:
                boss_out[k] = boss[k]
        # pass 57: the script's timing and what it brings, for the "Spawned so far" estimate (a boss's spawn_ring adds
        # its minions to the fight: the Tumbleweed King's 12 a ring)
        boss_out["script"] = [{k: a[k] for k in SCRIPT_KEYS if k in a} for a in boss.get("attacks", []) or [] if isinstance(a, dict)]
    json_path = json_path or os.path.join(folder, cid + ".json")
    looks = look_records(kind, cid, folder, d, json_path)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    base_code = str(d.get("variant_base", ""))
    playable = playable_codes(folder, d)
    # pass 54: the icon the game shows is the in-play variant's (JsonContent.build swaps it in after _common), so the
    # page gets that one as `icon_play` beside the top-level `icon`; nine creatures differ (the skeleton plays SK-A).
    # `play` is the code the game really plays: the JSON's `variant` when it can, else the base strip's
    want = str(d.get("variant", base_code))
    play = want if want in playable else base_code
    icon_play = "/icon/%s/%s/%s" % (kind, cid, play) if play and play in vs else "/icon/%s/%s" % (kind, cid)
    sprite_play = "/sprite/%s/%s/%s" % (kind, cid, play) if play and play in vs else "/sprite/%s/%s" % (kind, cid)
    variance = d.get("variance") if isinstance(d.get("variance"), dict) else {}
    blood = d.get("blood")
    frame_px = d.get("frame_px", 128)
    blocks = sorted(b for b in VOCAB.BLOCKS if isinstance(d.get(b), dict) and d.get(b))
    return {
        "id": cid,
        "name": str(d.get("name", cid)),
        "kind": kind,
        "archetype": str(d.get("archetype", "")),
        "brain": str(d.get("brain", "")),
        "hp": d.get("hp", 0),
        "damage": d.get("damage", 0),
        "speed": d.get("speed", 0),
        "size": d.get("size", 1),
        "radius": d.get("radius", 0.5),
        "pack_size": d.get("pack_size", 1),
        "cap_share": d.get("cap_share", 1.0),
        "max_alive": d.get("max_alive", 0),
        "xp_mult": d.get("xp_mult", 1.0),
        "damage_reduction": d.get("damage_reduction", 0.0),
        # pass 67: the share of the hero's shoves it shrugs off (EnemyDef.knockback_resist, 0..1; 0 when the JSON has
        # none; the Hammer Giant 0.67)
        "knockback_resist": d.get("knockback_resist", 0.0),
        # pass 53: EnemyDef.contact_cd (seconds between bites), 0.6 when the JSON has none
        "contact_cd": d.get("contact_cd", 0.6),
        "drops": d.get("drops", {}),
        "ranged": d.get("ranged"),
        "charge": d.get("charge"),
        "kamikaze": d.get("kamikaze"),
        "artillery": d.get("artillery"),
        "boss": boss_out,
        "elite": d.get("elite"),
        # pass 54: the variance block (tints, the coloured specials) is what a row's Elite overrides merge over, and
        # `knockback` is the bite's shove on the hero (null = the game's default from the damage; the page computes it)
        "variance": variance,
        "knockback": d.get("knockback") if isinstance(d.get("knockback"), (int, float)) and not isinstance(d.get("knockback"), bool) else None,
        "can_be_elite": bool(d.get("can_be_elite", True)),
        "hidden": bool(d.get("hidden", False)),
        "retired": bool(d.get("retired", False)),
        "doc": str(d.get("doc", "")),
        "flavour": str(d.get("flavour", "")),
        "variant": str(d.get("variant", "")),
        "variant_base": base_code,
        "play": play,
        "variants": looks,
        "icon": "/icon/%s/%s" % (kind, cid),
        "icon_play": icon_play,
        # pass 58: the look in play's strip and its cell (frame 0 is the standing idle frame the colour preview tints),
        # and the death splash's colour as the JSON spells it (null: none, the game bleeds BLOOD_DEFAULT)
        "sprite_play": sprite_play,
        "frame_px": int(frame_px) if isinstance(frame_px, (int, float)) and not isinstance(frame_px, bool) and frame_px > 0 else 128,
        "blood": blood if isinstance(blood, str) and HEX_RE.match(blood) else None,
        # pass 66: the asset editor's list pane (the same look records as `variants`, plus the strip's own numbers)
        "looks": looks,
        "sprite": "/sprite/%s/%s" % (kind, cid),
        "anims": d.get("anims") if isinstance(d.get("anims"), dict) else {},
        "fps": d.get("fps") if isinstance(d.get("fps"), dict) else {},
        "strip_cols": int(_num(d.get("strip_cols"), 0)),
        "head": _num(d.get("head"), 0.86),
        "badge": str(d.get("badge", "")),
        "front_faces": str(d.get("front_faces", "right")),
        "back_faces": str(d.get("back_faces", "right")),
        "sfx": d.get("sfx") if isinstance(d.get("sfx"), dict) else {},
        "blocks": blocks,
        "combo": "%s|%s" % (str(d.get("brain", "chase")), "+".join(blocks)),
        "can_be_grabbed": bool(d.get("can_be_grabbed", True)),
        "directions": int(_num(d.get("directions"), 2)),
        "file": rel(json_path),
        "mtime": mtime_of(json_path),
    }


def list_creatures():
    out = []
    ledger = ledger_load()["ids"]
    for kind in ("enemy", "boss"):
        for cid, folder, path in content_folders(kind):
            # the debug arena's dummies are hidden tools, never a wave's creature
            if cid.startswith("training_dummy"):
                continue
            try:
                d = load_json(path)
            except (OSError, ValueError) as e:
                print("skipping %s: %s" % (path, e))
                continue
            rec = creature_record(kind, cid, folder, d, path)
            rec["deletable"] = cid in ledger
            out.append(rec)
    return out


def combos_seen():
    """The brain + block combinations creatures in play use (not retired, not hidden, not a dummy): "brain|a+b"."""
    out = set()
    for kind in ("enemy", "boss"):
        for cid, folder, path in content_folders(kind):
            if cid.startswith("training_dummy"):
                continue
            try:
                d = load_json(path)
            except (OSError, ValueError):
                continue
            if d.get("retired") or d.get("hidden"):
                continue
            blocks = sorted(b for b in VOCAB.BLOCKS if isinstance(d.get(b), dict) and d.get(b))
            out.add("%s|%s" % (str(d.get("brain", "chase")), "+".join(blocks)))
    return out


def list_elites():
    out = []
    for cid, folder, path in content_folders("elite"):
        try:
            d = load_json(path)
        except (OSError, ValueError):
            continue
        out.append({"id": cid, "name": str(d.get("name", cid)), "outline": str(d.get("outline", "")),
                    "icon": "/icon/elite/%s" % cid})
    return out


def list_pickups():
    out = []
    for cid, folder, path in content_folders("pickup"):
        try:
            d = load_json(path)
        except (OSError, ValueError):
            continue
        params = d.get("params") if isinstance(d.get("params"), dict) else {}
        out.append({"id": cid, "name": str(d.get("name", cid)), "small": bool(params.get("small", False)),
                    "weight": d.get("weight", 0), "color": str(d.get("color", "")), "icon": "/icon/pickup/%s" % cid})
    return out


def _load_kind(kind):
    """[(id, folder, path, json)] of a kind, skipping unreadable files."""
    out = []
    for cid, folder, path in content_folders(kind):
        try:
            d = load_json(path)
        except (OSError, ValueError) as e:
            print("skipping %s: %s" % (path, e))
            continue
        out.append((cid, folder, path, d))
    return out


def quests_by_unlock():
    """{(unlocks.type, unlocks.id): quest record} over content/quests."""
    out = {}
    for cid, folder, path, d in _load_kind("quest"):
        u = d.get("unlocks") if isinstance(d.get("unlocks"), dict) else {}
        rec = {"id": cid, "name": str(d.get("name", cid)), "condition": d.get("condition") if isinstance(d.get("condition"), dict) else {},
               "unlocks": u, "quest_text": str(d.get("quest_text", "")), "file": rel(path), "icon": "/icon/quest/%s" % cid}
        if u.get("type") and u.get("id"):
            out[(str(u["type"]), str(u["id"]))] = rec
        out[("quest", cid)] = rec
    return out


def item_availability(kind, cid, d, quests):
    """Derived (INTERFACES §3): hidden -> "hidden"; a quest with unlocks.id == id -> "locked" (+ the quest id); else
    "available". Lines are quests of type "passive"."""
    if d.get("hidden"):
        return "hidden", None
    qtype = "weapon" if kind in ("weapon", "evolution") else "passive"
    q = quests.get((qtype, cid))
    if q and kind in ("weapon", "passive"):
        return "locked", q["id"]
    return "available", None


def icon_play_url(kind, cid, folder, d):
    """pass 70: the icon of the look the asset is played in (the JSON's `variant` when the game can play it, else the
    base), with its file's time so a newly installed badge shows at once. The Heroes list showed the base icon only, so
    May (played MAY-G, her base icon a placeholder) showed none."""
    base = str(d.get("variant_base", ""))
    want = str(d.get("variant", base))
    play = want if want and want in playable_codes(folder, d) else base
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    code = play if play and play in vs else ""
    full = icon_path(kind, cid, code)
    v = int(os.path.getmtime(full)) if full and os.path.isfile(full) else 0
    return "/icon/%s/%s%s?v=%d" % (kind, cid, ("/" + code) if code else "", v)


def title_play_url(cid, folder, d):
    """pass 70: the title cut-out of the look the hero is played in (its entry's `title`, else hero_<id>.png), None when
    neither is on disk (the game's CharacterDef.title_path: the look worn's own, else the hero's)."""
    base = str(d.get("variant_base", ""))
    want = str(d.get("variant", base))
    play = want if want and want in playable_codes(folder, d) else base
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    e = vs.get(play) if isinstance(vs.get(play), dict) else {}
    for name in ([os.path.basename(str(e["title"]))] if e.get("title") else []) + ["hero_%s.png" % cid]:
        full = os.path.join(WANTED_ART, name)
        if FILENAME_RE.match(name) and os.path.isfile(full):
            return "/art/wanted/%s?v=%d" % (name, int(os.path.getmtime(full)))
    return None


def hero_record(cid, folder, d, path, perks=None, mutations=None, weapons=None, quest=None, perk_records=None):
    hidden = bool(d.get("hidden", False))
    avail = str(d.get("availability", "hidden" if hidden else "available"))
    # pass 69 (lane UI's JsonContent rule): a purchase hero is never hidden in play; "hidden" alone hides
    hidden_in_play = avail == "hidden" or (hidden and avail != "purchase")
    title = os.path.join(WANTED_ART, "hero_%s.png" % cid)
    rec = {"id": cid, "kind": "hero", "name": str(d.get("name", cid)), "flavour": str(d.get("flavour", "")),
           "order": d.get("order", 100), "pronoun": str(d.get("pronoun", "they")), "hidden": hidden,
           "availability": avail, "price": int(_num(d.get("price"), 0)), "currency_type": str(d.get("currency_type", "gold")),
           "trait": d.get("trait", []), "trait_per_level": d.get("trait_per_level", []), "trait_name": str(d.get("trait_name", "")),
           "trait_text": str(d.get("trait_text", "")), "level_heal": _num(d.get("level_heal"), 0.0),
           "favourite_weapon": str(d.get("favourite_weapon", "")), "favourite_bonus": d.get("favourite_bonus", {}),
           "favourite_passive": str(d.get("favourite_passive", "")), "favourite_passive_bonus": d.get("favourite_passive_bonus", {}),
           "start_weapon": str(d.get("start_weapon", "")), "specials": d.get("specials", []), "momentum": d.get("momentum", {}),
           "frame_px": int(_num(d.get("frame_px"), 256)), "strip_cols": int(_num(d.get("strip_cols"), 0)),
           "fps": d.get("fps") if isinstance(d.get("fps"), dict) else {},
           "anims": d.get("anims") if isinstance(d.get("anims"), dict) else VOCAB.CHAR_ANIMS_DEFAULT,
           "sprite": "/sprite/hero/%s" % cid, "icon": "/icon/hero/%s" % cid, "icon_play": icon_play_url("hero", cid, folder, d),
           "title_play": title_play_url(cid, folder, d),
           "title": "/art/wanted/hero_%s.png" % cid if os.path.isfile(title) else None,
           "variant": str(d.get("variant", "")), "variant_base": str(d.get("variant_base", "")),
           "looks": look_records("hero", cid, folder, d, path),
           "perks": [p for p in (perks or [])], "hero_mutations": [m for m in (mutations or [])], "weapons": [w for w in (weapons or [])],
           "file": rel(path), "mtime": mtime_of(path),
           # pass 69: in play as the game reads it, his unlock quest (unlocks {type character, id}) and his perks' records
           "hidden_in_play": hidden_in_play, "quest": quest, "perk_records": [p for p in (perk_records or [])]}
    return rec


def perk_record(cid, d, path):
    """Pass 69: a perk as the Heroes tab lists it."""
    return {"id": cid, "kind": "perk", "name": str(d.get("name", cid)), "hero": str(d.get("hero", "")),
            "special": str(d.get("special", "")), "text": str(d.get("text", "")), "hidden": bool(d.get("hidden", False)),
            "rarity": str(d.get("rarity", "rare")), "weight": d.get("weight", 6), "icon": "/icon/perk/%s" % cid,
            "file": rel(path), "mtime": mtime_of(path)}


def list_heroes():
    perks, muts, weps, precs = {}, {}, {}, {}
    quests = quests_by_unlock()
    for cid, folder, path, d in _load_kind("perk"):
        if d.get("hero"):
            perks.setdefault(str(d["hero"]), []).append(cid)
            precs.setdefault(str(d["hero"]), []).append(perk_record(cid, d, path))
    for cid, folder, path, d in _load_kind("mutation"):
        if d.get("hero"):
            muts.setdefault(str(d["hero"]), []).append(cid)
    for cid, folder, path, d in _load_kind("weapon"):
        if d.get("hero"):
            weps.setdefault(str(d["hero"]), []).append(cid)
    out = []
    ledger = ledger_load()["ids"]
    for cid, folder, path, d in _load_kind("hero"):
        rec = hero_record(cid, folder, d, path, perks.get(cid, []), muts.get(cid, []), weps.get(cid, []),
                          quests.get(("character", cid)), precs.get(cid, []))
        rec["deletable"] = cid in ledger
        out.append(rec)
    out.sort(key=lambda r: (r["hidden_in_play"], r["order"] if isinstance(r["order"], (int, float)) else 100, r["id"]))
    return out


def item_record(kind, cid, folder, d, path, quests):
    avail, locked_by = item_availability(kind, cid, d, quests)
    rec = {"id": cid, "kind": kind, "name": str(d.get("name", cid)), "flavour": str(d.get("flavour", "")),
           "rarity": str(d.get("rarity", "common")), "weight": d.get("weight", 10), "hidden": bool(d.get("hidden", False)),
           "from_stage": int(_num(d.get("from_stage"), 0)), "element": str(d.get("element", "")),
           "icon": "/icon/%s/%s" % (kind, cid), "availability": avail, "locked_by": locked_by,
           "file": rel(path), "mtime": mtime_of(path)}
    if kind in ("weapon", "evolution"):
        rec.update({"behavior": str(d.get("behavior", "ProjectileEmitter")), "targeting": str(d.get("targeting", "nearest")),
                    "hero": str(d.get("hero", "")), "tags": d.get("tags", []), "max_level": d.get("max_level", 8),
                    "levels": d.get("levels", []), "base": d.get("base", {}), "evolves_into": str(d.get("evolves_into", "")),
                    "evolves_with": str(d.get("evolves_with", "")), "evolved_from": str(d.get("evolved_from", "")),
                    "is_evolution": bool(d.get("is_evolution", kind == "evolution")), "sfx": d.get("sfx", {}),
                    "visual": str(d.get("visual", "")),
                    "visual_exists": os.path.isfile(os.path.join(folder, str(d.get("visual", cid + "_visual.tscn")))),
                    # pass 69: a mutation's typed params show what its weapon already sets (the effective value and its source)
                    "params": d.get("params", {}) if isinstance(d.get("params"), dict) else {}})
        # pass 76 (lane LOOKS): its looks in its weapon family (list_items makes a member follow its weapon's)
        rec.update(item_look_state(kind, cid, folder, d))
    elif kind == "passive":
        rec.update({"line": bool(d.get("line", False)), "max_level": d.get("max_level", 8), "levels": d.get("levels", []),
                    "repeat_last_level": bool(d.get("repeat_last_level", True)), "evolves_into": str(d.get("evolves_into", "")),
                    "evolves_from": str(d.get("evolves_from", "")), "text": str(d.get("text", "")),
                    "pairs_with": str(d.get("pairs_with", "")), "trade": str(d.get("trade", "")),
                    "single": bool(d.get("single", False))})
        # pass 73 (lane CARDS): its looks (the cards' A-E) and the one the game plays
        rec.update(item_look_state(kind, cid, folder, d))
    elif kind == "mutation":
        rec.update({"weapon": str(d.get("weapon", "")), "mutation_kind": str(d.get("kind", "motion")), "hero": str(d.get("hero", "")),
                    "text": str(d.get("text", "")), "vfx": str(d.get("vfx", "")), "effects": d.get("effects", []),
                    "params": d.get("params", {}), "behavior": str(d.get("behavior", "")), "visual": str(d.get("visual", ""))})
        # pass 76 (lane LOOKS): its looks in its weapon family (list_items makes it follow its weapon's)
        rec.update(item_look_state(kind, cid, folder, d))
    return rec


def list_items():
    """GET /api/items: weapons grouped with their evolution and path mutations, lines with their evolved form, passive
    items, quests; the quest-locked band (pass44_test.gd:48-79: non-hidden base weapons + base passives, BAND_LO-BAND_HI)."""
    quests = quests_by_unlock()
    ledger = ledger_load()["ids"]
    weapons = [item_record("weapon", cid, folder, d, path, quests) for cid, folder, path, d in _load_kind("weapon")]
    evolutions = [item_record("evolution", cid, folder, d, path, quests) for cid, folder, path, d in _load_kind("evolution")]
    mutations = [item_record("mutation", cid, folder, d, path, quests) for cid, folder, path, d in _load_kind("mutation")]
    passives = [item_record("passive", cid, folder, d, path, quests) for cid, folder, path, d in _load_kind("passive")]
    for rec in weapons + evolutions + mutations + passives:
        rec["deletable"] = rec["id"] in ledger
    evo_by_id = {e["id"]: e for e in evolutions}
    used_evo, used_mut, used_pas = set(), set(), set()
    order = {k: i for i, k in enumerate(VOCAB.MUTATION_KINDS)}
    for w in weapons:
        own = [m for m in mutations if m["weapon"] == w["id"]]
        own.sort(key=lambda m: (order.get(m["mutation_kind"], 9), m["id"]))
        w["mutations"] = own
        used_mut.update(m["id"] for m in own)
        evo = evo_by_id.get(w["evolves_into"]) if w["evolves_into"] else None
        if evo is None:
            evo = next((e for e in evolutions if e["evolved_from"] == w["id"]), None)
        w["evolution"] = evo
        if evo:
            used_evo.add(evo["id"])
        # the path the game offers: the non-hidden, non-hero mutations by kind (Registry.mutations_of)
        path_kinds = [m["mutation_kind"] for m in own if not m["hidden"] and not m["hero"]]
        w["path"] = path_kinds
        w["path_missing"] = weapon_path_missing_from(w, own, evo)
        # pass 76 (lane LOOKS): the family wears the weapon's look; the weapon's record carries the family's looks
        family_records_wear(w, ([evo] if evo else []) + own)
    pas_by_id = {p["id"]: p for p in passives}
    lines, items = [], []
    for p in passives:
        if p["evolves_from"]:
            continue
        if p["line"]:
            ev = pas_by_id.get(p["evolves_into"]) if p["evolves_into"] else None
            if ev is None:
                ev = next((q for q in passives if q["evolves_from"] == p["id"]), None)
            p["evolved"] = ev
            if ev:
                used_pas.add(ev["id"])
            lines.append(p)
        else:
            items.append(p)
    orphans = {"mutations": [m for m in mutations if m["id"] not in used_mut],
               "evolutions": [e for e in evolutions if e["id"] not in used_evo],
               "passives": [p for p in passives if p["evolves_from"] and p["id"] not in used_pas]}
    base = [w for w in weapons if not w["hidden"]] + [p for p in passives if not p["evolves_from"] and not p["hidden"]]
    locked = [x for x in base if x["availability"] == "locked"]
    band = {"locked": len(locked), "base": len(base), "share": round(len(locked) / len(base), 4) if base else 0.0,
            "lo": BAND_LO, "hi": BAND_HI}
    qlist = sorted({q["id"]: q for q in quests.values()}.values(), key=lambda q: q["id"])
    return {"ok": True, "weapons": weapons, "lines": lines, "passives": items, "quests": qlist, "band": band, "orphans": orphans}


def weapon_path_missing_from(w, own, evo):
    """What keeps a weapon from turning available (INTERFACES §0.1): one non-hidden path mutation per kind, each with
    `text` and at least one effect or param, and an evolution with a name. [] when nothing is missing."""
    out = []
    for kind in VOCAB.PATH_KINDS:
        cands = [m for m in own if m["mutation_kind"] == kind and not m["hero"]]
        live = [m for m in cands if not m["hidden"]]
        if not cands:
            out.append("no %s mutation" % kind)
            continue
        if not live:
            out.append("%s: the %s mutation is hidden" % (cands[0]["id"], kind))
        for m in cands:
            if not m["text"]:
                out.append("%s: no text" % m["id"])
            if not m["effects"] and not m["params"]:
                out.append("%s: no effect and no param" % m["id"])
        if len(live) > 1:
            out.append("more than one open %s mutation: %s" % (kind, ", ".join(m["id"] for m in live)))
    if evo is None:
        out.append("no evolution (evolves_into %s)" % (w["evolves_into"] or "is empty"))
    elif not evo["name"]:
        out.append("%s: the evolution has no name yet" % evo["id"])
    return out


def weapon_path_missing(weapon_id):
    items = list_items()
    w = next((x for x in items["weapons"] if x["id"] == weapon_id), None)
    return w["path_missing"] if w else ["no weapon %s" % weapon_id]


def list_templates(kind):
    """[{id, name}] of a kind, the retired left out (a template is something to copy, not a shelved creature)."""
    out = []
    kinds = [kind] if kind in KIND_FOLDERS else []
    for k in kinds:
        for cid, folder, path, d in _load_kind(k):
            if d.get("retired") or cid.startswith("training_dummy"):
                continue
            out.append({"id": cid, "kind": k, "name": str(d.get("name", cid)), "hidden": bool(d.get("hidden", False)),
                        "icon": "/icon/%s/%s" % (k, cid)})
    return out


def icon_path(kind, cid, code):
    """The PNG of a content item's icon, or of one of its art variants: the variant entry's `icon` file when it has one,
    else the JSON's top-level `icon`, else <id>_icon.png (the game's own order, JsonContent.build; pass 54 added the middle
    step, a variant without its own icon showed the default painting instead of the creature's named one)."""
    if kind not in KIND_FOLDERS or not ID_RE.match(cid):
        return None
    folder = os.path.join(CONTENT, KIND_FOLDERS[kind], cid)
    path = os.path.join(folder, cid + ".json")
    if not os.path.isfile(path):
        return None
    name = cid + "_icon.png"
    try:
        d = load_json(path)
    except (OSError, ValueError):
        d = {}
    if d.get("icon"):
        name = str(d["icon"])
    if code:
        entry = (d.get("variants") or {}).get(code) if isinstance(d.get("variants"), dict) else None
        if isinstance(entry, dict) and entry.get("icon"):
            # a variant's own painting; when its file is not on disk yet the creature's icon stands in (the game's rule)
            own = resolve_file(folder, str(entry["icon"]))
            if own:
                return own
    return resolve_file(folder, name)


def sprite_path(kind, cid, code):
    """The animation strip PNG of a creature's or hero's look (pass 58, the colour range's preview; pass 66 heroes): the
    variant entry's `sprite` when its file is on disk, else the JSON's top-level `sprite`, else <id>_sprite.png
    (JsonContent's order; a base strip's own code is the top-level strip). Cells are `frame_px` square, frame 0 the
    standing idle frame."""
    if kind not in LOOK_KINDS or not ID_RE.match(cid):
        return None
    folder = os.path.join(CONTENT, KIND_FOLDERS[kind], cid)
    path = os.path.join(folder, cid + ".json")
    if not os.path.isfile(path):
        return None
    try:
        d = load_json(path)
    except (OSError, ValueError):
        return None
    if code:
        entry = (d.get("variants") or {}).get(code) if isinstance(d.get("variants"), dict) else None
        if isinstance(entry, dict) and entry.get("sprite"):
            own = resolve_file(folder, str(entry["sprite"]))
            if own:
                return own
    return resolve_file(folder, str(d.get("sprite", cid + "_sprite.png")))


# ---------------------------------------------------------------- writing a map

restore_numbers = cio.restore_numbers


def ordered_like(old, new):
    """`new`'s keys in the order the file on disk has them, new keys after; one level down for `timeline_data` too, so a
    one-number change is a one-line diff."""
    if not isinstance(old, dict) or not isinstance(new, dict):
        return new
    out = {}
    for k in old:
        if k in new:
            out[k] = ordered_like(old[k], new[k]) if k == "timeline_data" else new[k]
    for k in new:
        if k not in out:
            out[k] = new[k]
    return out


def backup(map_id, path):
    os.makedirs(BACKUPS, exist_ok=True)
    ignore = os.path.join(BACKUPS, ".gitignore")
    if not os.path.exists(ignore):
        # the backups never go in the repository (the JSON itself is what Garry commits)
        with open(ignore, "w", encoding="utf-8", newline="\n") as f:
            f.write("*\n")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(BACKUPS, "%s-%s.json" % (map_id, stamp))
    n = 0
    while os.path.exists(dest):
        n += 1
        dest = os.path.join(BACKUPS, "%s-%s-%d.json" % (map_id, stamp, n))
    with open(path, "rb") as src, open(dest, "wb") as dst:
        dst.write(src.read())
    mine = sorted(f for f in os.listdir(BACKUPS) if f.startswith(map_id + "-") and f.endswith(".json"))
    for f in mine[:-KEEP_BACKUPS]:
        try:
            os.remove(os.path.join(BACKUPS, f))
        except OSError:
            pass
    return rel(dest)


def run_import(target, who="level_editor save"):
    """JSON -> .tres for one or more content folders (`maps/red_canyon`, `enemies/skeleton,quests/unlock_x`), under the
    repo-wide Godot lock with the PC save kept aside (tools/locks.py); (ok, output tail). ok is None when the lock was
    busy for LOCK_WAIT seconds: then an `import` job is queued when jobs.py is here, and the tail says so."""
    info = run_import_info(target, who, LOCK_WAIT)
    return info["ok"], info["output"]


def _queued_import(targets):
    """Pass 103 (lane LE): a queued (not yet started) import job that already covers every one of `targets`, or None: a
    second Save while the lock is held joins it (the job reads the JSON when it runs) instead of piling up another."""
    m = jobs_module()
    if m is None or not hasattr(m, "list"):
        return None
    try:
        jl = m.list() or {}
    except Exception:
        return None
    for j in jl.get("jobs") or []:
        if j.get("kind") == "import" and j.get("state") == "queued":
            have = [str(x) for x in ((j.get("spec") or {}).get("targets") or [])]
            if all(str(t) in have for t in targets):
                return j
    return None


def run_import_info(target, who="level_editor save", wait=None):
    """Pass 103 (lane LE): run_import with what the page needs to follow a queued import: {ok (True | False | None:
    the lock was busy for `wait` seconds), output (the tail), job (the queued import job's id, or None), joined (the
    job was already queued for these targets), lock ({who, age_s} of the holder when it was busy)}."""
    out = {"ok": False, "output": "", "job": None, "joined": False, "lock": None}
    if not os.path.isfile(GODOT):
        out["output"] = ("Godot binary not found at %s: the JSON is saved, but the game plays the .tres. Run the import "
                       "yourself: Godot --headless --path game --script res://tools/import_json.gd -- only=%s"
                       % (GODOT, target))
        return out
    args = ["--headless", "--path", GAME, "--script", "res://tools/import_json.gd", "--", "only=%s" % target]
    lk = locks.acquire("godot", who, note="import_json only=%s" % target, timeout=LOCK_WAIT if wait is None else wait, log=lambda m: None)
    if lk is None:
        s = locks.status("godot") or {}
        holder = "%s%s" % (s.get("who", "?"), (" / " + s["job"]) if s.get("job") else "")
        targets = target.split(",")
        have = _queued_import(targets)
        if have is not None:
            job = {"job": have}
            out["joined"] = True
            more = "the import job %s already queued for it will import it" % have["id"]
        else:
            job = _enqueue("import", {"kind": "content", "id": target}, {"targets": targets}, "import %s" % target)
            more = ("an import job was queued instead (%s)" % job["job"]["id"]) if job.get("job") else \
                ("no import job could be queued: %s" % job.get("error", "the jobs module is not here yet"))
        out.update(ok=None, job=(job.get("job") or {}).get("id"), lock={"who": holder, "age_s": int(s.get("age_s", 0))},
                   output="the Godot lock has been held by %s for %d s: %s" % (holder, int(s.get("age_s", 0)), more))
        return out
    try:
        locks.keep_save()
        try:
            p = subprocess.run([GODOT] + args, capture_output=True, text=True, timeout=IMPORT_TIMEOUT, cwd=ROOT,
                               encoding="utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            out["output"] = "the import did not finish in %d s" % IMPORT_TIMEOUT
            return out
        except OSError as e:
            out["output"] = "could not run the import: %s" % e
            return out
        finally:
            locks.restore_save()
    finally:
        lk.release()
    text = (p.stdout or "") + (p.stderr or "")
    lines = [l for l in text.replace("\r", "").split("\n") if l.strip()]
    out["output"] = "\n".join(lines[-12:])
    out["ok"] = p.returncode == 0 and "SCRIPT ERROR" not in text and "import_json: wrote" in text
    return out


def write_map(map_id, data):
    path = map_path(map_id)
    if not os.path.isfile(path):
        return {"ok": False, "error": "no map %s on disk (the editor never creates maps)" % map_id}
    if not isinstance(data, dict) or not isinstance(data.get("timeline_data"), dict):
        return {"ok": False, "error": "the body must be the whole map JSON with a timeline_data block"}
    if str(data.get("id", map_id)) != map_id:
        return {"ok": False, "error": "the body's id does not match the map"}
    with _write_lock:
        with open(path, "r", encoding="utf-8") as f:
            old = json.load(f)
        # pass 67: a top-level key the page never saw (`weapon_grade`, added to the file while the page was open) rides
        # along: the page edits timeline_data, every other key of the file is kept as it was
        for k in old:
            if k not in data:
                data[k] = old[k]
        merged = ordered_like(old, restore_numbers(old, data))
        text = json.dumps(merged, indent=2, ensure_ascii=False) + "\n"
        backup_rel = backup(map_id, path)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        os.replace(tmp, path)
    # pass 103 (lane LE): a short wait for the Godot lock, then the queued import job and its holder go back to the page
    imp = run_import_info("maps/%s" % map_id, wait=SAVE_LOCK_WAIT)
    return {"ok": True, "wrote": rel(path), "backup": backup_rel,
            "import_ok": imp["ok"], "output": imp["output"], "import_job": imp["job"], "import_joined": imp["joined"],
            "lock": imp["lock"]}


# ---------------------------------------------------------------- a creature's default look (pass 54), the blood (pass 58)

def creature_file(cid):
    """(kind, json path) of the creature `cid` under content/enemies or content/bosses, or (None, None)."""
    if not ID_RE.match(cid) or cid.startswith("training_dummy"):
        return None, None
    for kind in ("enemy", "boss"):
        path = os.path.join(CONTENT, KIND_FOLDERS[kind], cid, cid + ".json")
        if os.path.isfile(path):
            return kind, path
    return None, None


set_top_key = cio.set_top_key
_redump = cio.redump
_write_creature = cio.write_atomic


def write_variant(cid, code):
    """The pass 54 route: a creature's default look (see write_variant_kind)."""
    kind, path = creature_file(cid)
    if path is None:
        return {"ok": False, "error": "no creature %s under content/enemies or content/bosses" % cid}
    return write_variant_kind(kind, cid, code)


def write_variant_kind(kind, cid, code):
    """Set the JSON's top-level `variant` to `code` (one of the looks the game can play: the base strip or an entry of
    `variants` whose strip is on disk): a backup like a map's, then that one line written (in place, or a new line just
    before `variants`), every other byte as it was (pass 58: the old re-dump turned the three files with a CRLF only on
    their last line into CRLF throughout; pass 66: a file that cannot be edited line by line is refused, never
    re-dumped), then the JSON -> .tres import of that one folder. Creatures (pass 54) and heroes (pass 66); items with
    looks (pass 73, the cards: a look plays once its icon is on disk); pass 76 (lane LOOKS): a weapon, for its whole
    family (an evolution or a mutation is refused: it wears its weapon's look)."""
    if kind not in LOOK_KINDS and kind not in ITEM_LOOK_KINDS:
        return {"ok": False, "error": "only enemies, bosses, heroes, cards and weapons have looks"}
    _, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid)}
    if kind in ("evolution", "mutation"):
        try:
            wid = family_weapon_id(kind, cid, load_json(path))
        except (OSError, ValueError):
            wid = ""
        return {"ok": False, "error": "%s wears its weapon family's look: play the look on the weapon %s (one look for "
                                      "the whole family)" % (cid, wid or "it belongs to")}
    if not isinstance(code, str) or not CODE_RE.match(code):
        return {"ok": False, "error": "the body needs a variant code: {\"code\": \"SK-B\"}"}
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        playable = item_playable_codes(os.path.dirname(path), d, kind) if kind in ITEM_LOOK_KINDS else playable_codes(os.path.dirname(path), d)
        if code not in playable:
            vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
            known = ", ".join(sorted(playable)) or "none"
            what = "icon or visual is not on disk" if kind in FAMILY_LOOK_KINDS else ("icon" if kind in ITEM_LOOK_KINDS else "strip") + " is not painted"
            why = ("its %s yet" % what) if code in vs else "it has no such variant"
            return {"ok": False, "error": "%s cannot play %s: %s (it can play: %s)" % (cid, code, why, known)}
        before = str(d.get("variant", ""))
        text = cio.set_top_block(src, "variant", code, [("before", "variants"), ("end", None)])
        if text is None:
            return {"ok": False, "error": "layout: %s is not laid out one top-level key per line, so the editor will not "
                                          "rewrite it (edit `variant` by hand, or ask for a re-dump)" % rel(path)}
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
    import_ok, output = run_import("%s/%s" % (KIND_FOLDERS[kind], cid))
    return {"ok": True, "id": cid, "kind": kind, "variant": code, "was": before,
            "wrote": rel(path), "backup": backup_rel,
            "import_ok": import_ok, "output": output}


def write_blood(cid, color):
    """Set the creature JSON's top-level `blood` (pass 58, R4: the colour of its death splash, EnemyDef.blood) to `color`
    ("#rrggbb", written in capitals as the creature files spell their colours: lane FX's blood, the variance tints): the
    same way as the default look (a backup, that one line in place or a new line after `size`, where lane FX put every
    creature's, else after `knockback` or `damage`, else at the end; every other byte as it was), then the import of that
    one creature. The colour it already has (any case) writes nothing and imports nothing."""
    kind, path = creature_file(cid)
    if path is None:
        return {"ok": False, "error": "no creature %s under content/enemies or content/bosses" % cid}
    if not isinstance(color, str) or not HEX_RE.match(color.strip()):
        return {"ok": False, "error": "the body needs a colour as #rrggbb: {\"color\": \"#8A1428\"} (got %s)" % json.dumps(color)}
    value = color.strip().upper()
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        was = d.get("blood")
        if isinstance(was, str) and was.strip().upper() == value:
            return {"ok": True, "id": cid, "kind": kind, "blood": was, "was": was, "unchanged": True,
                    "wrote": "", "backup": "", "import_ok": True, "output": "the colour was already %s: nothing written" % was}
        text = cio.set_top_block(src, "blood", value, [("after", "size"), ("after", "knockback"), ("after", "damage"), ("end", None)])
        if text is None:
            return {"ok": False, "error": "layout: %s is not laid out one top-level key per line, so the editor will not "
                                          "rewrite it (edit `blood` by hand, or ask for a re-dump)" % rel(path)}
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
    import_ok, output = run_import("%s/%s" % (KIND_FOLDERS[kind], cid))
    return {"ok": True, "id": cid, "kind": kind, "blood": value, "was": was if isinstance(was, str) else None,
            "wrote": rel(path), "backup": backup_rel, "import_ok": import_ok, "output": output}


# ---------------------------------------------------------------- pass 66: the content model's operations

def _layout_error(path, what="the file"):
    return ("layout: %s is not laid out one top-level key per line (or the key's lines cannot be edited on their own), so "
            "the editor will not rewrite %s; fix the layout by hand, or ask for a re-dump" % (rel(path), what))


def ledger_load():
    try:
        d = load_json(LEDGER)
        return d if isinstance(d, dict) and isinstance(d.get("ids"), dict) else {"ids": {}}
    except (OSError, ValueError):
        return {"ids": {}}


def ledger_write(d):
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    cio.write_atomic(LEDGER, json.dumps(d, indent=1, ensure_ascii=False) + "\n")


def ledger_add(cid, kind, template):
    d = ledger_load()
    d["ids"][cid] = {"kind": kind, "created": time.strftime("%Y-%m-%d %H:%M:%S"), "template": template}
    ledger_write(d)


def ledger_remove(cid):
    d = ledger_load()
    if cid in d["ids"]:
        del d["ids"][cid]
        ledger_write(d)


def deleted_dir(cid):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(BACKUPS, "deleted", cid, stamp)
    n = 0
    while os.path.exists(dest):
        n += 1
        dest = os.path.join(BACKUPS, "deleted", cid, "%s-%d" % (stamp, n))
    os.makedirs(dest)
    return dest


def map_references(cid, code=None):
    """Where the maps name creature `cid` (rows, events, specials, skins, the boss, bosses' spawn_ring): ["red_canyon:
    roster r1", ...]. With `code`, only the places that pin that art variant."""
    out = []
    base = os.path.join(CONTENT, "maps")
    if not os.path.isdir(base):
        return out
    for sub in sorted(os.listdir(base)):
        path = os.path.join(base, sub, sub + ".json")
        if not os.path.isfile(path):
            continue
        try:
            d = load_json(path)
        except (OSError, ValueError):
            continue
        tl = d.get("timeline_data") if isinstance(d.get("timeline_data"), dict) else {}
        if code is None:
            if str(d.get("boss", "")) == cid:
                out.append("%s: the boss" % sub)
            for role, skin in (d.get("skins") or {}).items() if isinstance(d.get("skins"), dict) else []:
                if str(skin) == cid:
                    out.append("%s: skin %s" % (sub, role))
        for r in tl.get("roster", []) if isinstance(tl.get("roster"), list) else []:
            if isinstance(r, dict) and str(r.get("enemy", "")) == cid and (code is None or str(r.get("variant", "")) == code):
                out.append("%s: roster %s" % (sub, r.get("id", "?")))
        for i, e in enumerate(tl.get("events", []) if isinstance(tl.get("events"), list) else []):
            if not isinstance(e, dict):
                continue
            ens = e.get("enemy")
            names = ens if isinstance(ens, list) else [ens]
            if cid in [str(x) for x in names if x is not None] and (code is None or str(e.get("variant", "")) == code):
                out.append("%s: event %d (%s)" % (sub, i + 1, e.get("type", "?")))
            for a in e.get("alts", []) if isinstance(e.get("alts"), list) else []:
                if isinstance(a, dict) and str(a.get("enemy", "")) == cid and (code is None or str(a.get("variant", "")) == code):
                    out.append("%s: event %d alternative" % (sub, i + 1))
        for w in tl.get("waves", []) if isinstance(tl.get("waves"), list) else []:
            if not isinstance(w, dict):
                continue
            if str(w.get("enemy", "")) == cid and (code is None or str(w.get("variant", "")) == code):
                out.append("%s: wave %s" % (sub, w.get("name", w.get("id", "?"))))
            for a in w.get("alts", []) if isinstance(w.get("alts"), list) else []:
                if isinstance(a, dict) and str(a.get("enemy", "")) == cid and (code is None or str(a.get("variant", "")) == code):
                    out.append("%s: wave %s alternative" % (sub, w.get("name", w.get("id", "?"))))
        sp = tl.get("specials") if isinstance(tl.get("specials"), dict) else {}
        for p in sp.get("pool", []) if isinstance(sp.get("pool"), list) else []:
            if isinstance(p, dict) and str(p.get("enemy", "")) == cid and (code is None or str(p.get("variant", "")) == code):
                out.append("%s: specials pool" % sub)
    if code is None:
        for kind in ("boss", "enemy"):
            for bid, folder, path, d in _load_kind(kind):
                boss = d.get("boss") if isinstance(d.get("boss"), dict) else {}
                for a in boss.get("attacks", []) if isinstance(boss.get("attacks"), list) else []:
                    if isinstance(a, dict) and a.get("name") == "spawn_ring" and str(a.get("enemy", "")) == cid:
                        out.append("%s: spawn_ring" % bid)
    return out


def references_to(kind, cid):
    """Everything that names this id: {maps, quests, weapons, evolutions, mutations, characters, perks, passives}."""
    out = {"maps": [], "quests": [], "weapons": [], "evolutions": [], "mutations": [], "characters": [], "perks": [], "passives": []}
    if kind in ("enemy", "boss"):
        out["maps"] = map_references(cid)
    for qid, folder, path, d in _load_kind("quest"):
        u = d.get("unlocks") if isinstance(d.get("unlocks"), dict) else {}
        c = d.get("condition") if isinstance(d.get("condition"), dict) else {}
        # pass 100 (lane QUESTS): the build quests name an item (`id`) or a hero (`hero`)
        if str(u.get("id", "")) == cid or cid in (str(c.get("enemy", "")), str(c.get("weapon", "")), str(c.get("id", "")), str(c.get("hero", ""))):
            out["quests"].append(qid)
    for wid, folder, path, d in _load_kind("weapon"):
        if str(d.get("evolves_into", "")) == cid or str(d.get("hero", "")) == cid:
            out["weapons"].append(wid)
    for eid, folder, path, d in _load_kind("evolution"):
        if str(d.get("evolved_from", "")) == cid or str(d.get("hero", "")) == cid:
            out["evolutions"].append(eid)
    for mid, folder, path, d in _load_kind("mutation"):
        if str(d.get("weapon", "")) == cid or str(d.get("hero", "")) == cid:
            out["mutations"].append(mid)
    for hid, folder, path, d in _load_kind("hero"):
        if cid in (str(d.get("favourite_weapon", "")), str(d.get("start_weapon", "")), str(d.get("favourite_passive", ""))):
            out["characters"].append(hid)
    for pid, folder, path, d in _load_kind("perk"):
        if str(d.get("hero", "")) == cid:
            out["perks"].append(pid)
    for pid, folder, path, d in _load_kind("passive"):
        if cid in (str(d.get("evolves_into", "")), str(d.get("evolves_from", ""))):
            out["passives"].append(pid)
    return out


def code_prefix(kind, cid, d):
    """INTERFACES §3: the most common prefix of the existing `variants` keys -> `variant_base`'s -> the initials of the
    id's words (dune_scorpion -> DS; a one-word id takes its first three letters, goblin -> GOB)."""
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    counts = {}
    for code in vs:
        if "-" in str(code):
            p = str(code).rsplit("-", 1)[0]
            counts[p] = counts.get(p, 0) + 1
    if counts:
        return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
    base = str(d.get("variant_base", ""))
    if "-" in base:
        return base.rsplit("-", 1)[0]
    words = [w for w in cid.split("_") if w]
    if len(words) > 1:
        return "".join(w[0] for w in words).upper()
    return cid[:3].upper()


def _suffixes():
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for a in letters:
        yield a
    for a in letters:
        for b in letters:
            yield a + b


def _cached_names(cid):
    """The lower-cased names under tools/dl/ai_raw_anime and tools/dl/ai_anim that start with `<id>_` (next_codes)."""
    out = []
    for sub in ("ai_raw_anime", "ai_anim"):
        try:
            names = os.listdir(os.path.join(DL, sub))
        except OSError:
            names = []
        out.append([x.lower() for x in names if x.lower().startswith(cid.lower() + "_")])
    return out


def next_codes(kind, cid, n=1):
    """{ok, codes, base_created, prefix}: the next free codes (a suffix whose strip or icon PNG exists, or a stub entry,
    counts as used; a hero without variants keeps A for its base strip); base_created says the first look op will create
    `variant_base` and the base entry because the file has no variants yet.
    Pass 68 (review): a suffix whose paintings or clips are still cached counts as used too (tools/dl/ai_raw_anime
    `<id>_<letter>_*` or `<id>_<codepart>_*`, tools/dl/ai_anim `<id>_<codepart>_*`). Remove moves only a look's strip,
    icon, marker and cut-out; gen_art and the clip cycles reuse a cached key whatever the seed, so a new look (+ New look…
    or a Duplicate's draft) handed the removed look's code would land its pictures again (DM-F brought back DM-E's clone)."""
    tfolder, path = content_path(kind, cid)
    if path is None or kind not in LOOK_KINDS:
        return {"ok": False, "error": "no %s %s" % (kind, cid)}
    d = load_json(path)
    folder = os.path.dirname(path)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    prefix = code_prefix(kind, cid, d)
    used = set()
    for code in vs:
        used.add(str(code).rsplit("-", 1)[-1].upper())
    base = str(d.get("variant_base", ""))
    if base:
        used.add(base.rsplit("-", 1)[-1].upper())
    no_variants = not vs
    if no_variants and kind == "hero":
        used.add("A")
    raw_names, anim_names = _cached_names(cid)
    out = []
    for s in _suffixes():
        if len(out) >= max(1, min(int(n), 50)):
            break
        if s in used:
            continue
        low = s.lower()
        if os.path.isfile(os.path.join(folder, "%s_sprite_%s.png" % (cid, low))) or os.path.isfile(os.path.join(folder, "%s_icon_%s.png" % (cid, low))):
            continue
        slug, cp = ("%s_%s_" % (cid, low)).lower(), ("%s_%s_" % (cid, (prefix + s).replace("-", ""))).lower()
        if any(x.startswith((slug, cp)) for x in raw_names) or any(x.startswith(cp) for x in anim_names):
            continue
        out.append("%s-%s" % (prefix, s))
    return {"ok": True, "codes": out, "base_created": no_variants, "prefix": prefix}


def _ensure_variants(src, kind, cid, d):
    """`src` with a `variants` block, `variant_base` and the base entry present (the first look of a file that had none:
    creatures `<PREFIX>-0`, heroes `<PREFIX>-A`); (text, base_code) or (None, error)."""
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else None
    text = src
    base = str(d.get("variant_base", ""))
    if vs:
        return text, base
    if not base:
        base = "%s-%s" % (code_prefix(kind, cid, d), "A" if kind == "hero" else "0")
        text = cio.set_top_block(text, "variant_base", base, [("before", "variant"), ("before", "variants"), ("end", None)])
        if text is None:
            return None, "variant_base"
    if vs is None:
        text = cio.set_top_block(text, "variants", {}, [("after", "variant"), ("after", "variant_base"), ("end", None)])
        if text is None:
            return None, "variants"
    text = cio.set_variant_entry(text, base, {"note": "the top-level strip, before the Level Editor's looks"})
    if text is None:
        return None, "the base entry"
    return text, base


def read_content(kind, cid):
    """GET /api/content/<kind>/<id>."""
    tfolder, path = content_path(kind, cid)
    if path is None or kind not in EDIT_KINDS:
        return {"ok": False, "error": "no %s %s" % (kind, cid), "status": 404}
    src = cio.read_text(path)
    try:
        d = json.loads(src)
    except ValueError as e:
        return {"ok": False, "error": "%s is not valid JSON: %s" % (rel(path), e), "status": 500}
    folder = os.path.dirname(path)
    quests = quests_by_unlock()
    avail, locked_by = (None, None)
    if kind == "hero":
        avail = str(d.get("availability", "hidden" if d.get("hidden") else "available"))
    elif kind in ("weapon", "evolution", "passive", "mutation"):
        avail, locked_by = item_availability(kind, cid, d, quests)
    ledger = ledger_load()["ids"]
    out = {"ok": True, "kind": kind, "id": cid, "file": rel(path), "mtime": mtime_of(path), "text": src, "json": d,
           "layout": cio.layout(src), "editable": cio.top_spans(src) is not None,
           "looks": look_records(kind, cid, folder, d, path) if kind in LOOK_KINDS else (
               item_looks(kind, cid, folder, d, family_member_play(kind, cid, d)) if kind in ITEM_LOOK_KINDS else []),
           "refs": references_to(kind, cid), "availability": avail, "locked_by": locked_by,
           # pass 69: a hero's quest is the one that unlocks {type character, id} (his requirement)
           "quest": quests.get(("character" if kind == "hero" else "weapon" if kind in ("weapon", "evolution") else "passive", cid)),
           "files": sorted(f for f in os.listdir(folder) if os.path.isfile(os.path.join(folder, f))),
           "deletable": cid in ledger, "ledger": ledger.get(cid),
           "combos_seen": sorted(combos_seen()) if kind in ("enemy", "boss") else []}
    if kind == "weapon":
        out["path_missing"] = weapon_path_missing(cid)
    return out


def write_content(kind, cid, new_obj, base_mtime=None):
    """POST /api/content/<kind>/<id>/save: the whole document back. The file is edited key by key in place: a changed key's
    span rewritten (the file's floats put back where the page sent whole numbers), a removed key's lines gone (only keys
    the editor owns are ever removed), a new key after the key before it in the document, else at the end. One backup,
    one atomic write, then the import (outside the write lock, under the Godot lock)."""
    if kind not in EDIT_KINDS:
        return {"ok": False, "error": "unknown kind %s" % kind, "status": 400}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid), "status": 404}
    if not isinstance(new_obj, dict) or str(new_obj.get("id", cid)) != cid:
        return {"ok": False, "error": "the body's json must be the whole %s with id %s" % (kind, cid), "status": 400}
    with _write_lock:
        cur = mtime_of(path)
        if base_mtime is not None and isinstance(base_mtime, (int, float)) and abs(float(base_mtime) - cur) > 0.0015:
            return {"ok": False, "error": "changed on disk", "mtime": cur, "status": 409}
        src = cio.read_text(path)
        old = json.loads(src)
        if kind in LOOK_KINDS:
            # pass 70 (the Bandit check): a look's Stills that is not a slug is refused when the save brings it (a bad
            # value already on disk is left for the page's rule to point at)
            had = set(VOCAB.bad_stills(old))
            new_bad = [b for b in VOCAB.bad_stills(new_obj) if b not in had]
            if new_bad:
                return {"ok": False, "error": "%s: %s" % new_bad[0], "status": 400, "path": new_bad[0][0]}
        owned = EDITOR_OWNED[kind]
        changed = [k for k in new_obj if k not in old or restore_numbers(old[k], new_obj[k]) != old[k]]
        removed = [k for k in old if k not in new_obj and k in owned]
        if not changed and not removed:
            return {"ok": True, "changed": [], "removed": [], "unchanged": True, "backup": "", "import_ok": True,
                    "output": "nothing changed: nothing written", "mtime": cur}
        text = src
        for k in removed:
            text = cio.del_top_block(text, k)
            if text is None:
                return {"ok": False, "error": _layout_error(path, "key %s" % k), "status": 400}
        keys_new = list(new_obj.keys())
        for k in [k for k in old if k in changed]:
            text = cio.set_top_block(text, k, restore_numbers(old[k], new_obj[k]))
            if text is None:
                return {"ok": False, "error": _layout_error(path, "key %s" % k), "status": 400}
        present = [k for k in old if k not in removed]
        for k in [k for k in keys_new if k not in old]:
            places = []
            i = keys_new.index(k)
            for prev in reversed(keys_new[:i]):
                if prev in present:
                    places.append(("after", prev))
                    break
            places.append(("end", None))
            text = cio.set_top_block(text, k, new_obj[k], places)
            if text is None:
                return {"ok": False, "error": _layout_error(path, "new key %s" % k), "status": 400}
            present.append(k)
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
        new_mtime = mtime_of(path)
    EV.emit("content", "write", kind_of=kind, id=cid, changed=changed, removed=removed, backup=backup_rel, file=rel(path))   # pass 97 (lane PROGRESS, WF-02)
    import_ok, output = run_import("%s/%s" % (tfolder, cid))
    return {"ok": True, "changed": changed, "removed": removed, "backup": backup_rel, "import_ok": import_ok,
            "output": output, "mtime": new_mtime, "wrote": rel(path)}


def _reset_from_template(kind, t, new_id, name, flavour, doc, copy_art):
    """The new object from the template's parsed object in its key order, with the identity reset and the art keys
    dropped unless `copy_art`."""
    obj = {}
    for k, v in t.items():
        if k == "id":
            obj[k] = new_id
        elif k == "name":
            obj[k] = name
        elif k == "flavour":
            obj[k] = flavour
        elif k == "doc":
            obj[k] = doc
        elif k in _ART_KEYS_RESET and not copy_art:
            continue
        elif k in ("hidden", "retired", "note") and copy_art:
            continue
        else:
            obj[k] = json.loads(json.dumps(v))
    if "name" not in obj:
        obj["name"] = name
    if "flavour" not in obj:
        obj["flavour"] = flavour
    return obj


def _insert_after(obj, after, key, value):
    """`obj` with `key: value` placed right after `after` (or at the end)."""
    out = {}
    done = False
    for k, v in obj.items():
        if k == key:
            continue
        out[k] = v
        if k == after:
            out[key] = value
            done = True
    if not done:
        out[key] = value
    return out


def default_knockback(damage):
    """EnemyDef.default_knockback: clamp(3.4 * sqrt(damage / 4), 2.5, 7.0)."""
    try:
        v = 3.4 * math.sqrt(max(0.0, float(damage)) / 4.0)
    except (TypeError, ValueError):
        v = 2.5
    return round(min(7.0, max(2.5, v)), 2)


def _copy_art_files(kind, t_id, t_folder, new_id, folder, obj):
    """Copy the template's strip and icon PNGs renamed to the new id, rewrite the names in the object (top-level
    `sprite`/`icon` and every variant entry's), no .import files (the register job imports fresh)."""
    copied = []
    for f in os.listdir(t_folder):
        if not f.lower().endswith(".png") or not f.startswith(t_id + "_"):
            continue
        if "_sprite" not in f and "_icon" not in f:
            continue
        dest = new_id + f[len(t_id):]
        shutil.copyfile(os.path.join(t_folder, f), os.path.join(folder, dest))
        copied.append(dest)

    def rename(name):
        name = str(name)
        if name.startswith(t_id + "_"):
            return new_id + name[len(t_id):]
        return name
    for k in ("sprite", "icon"):
        if k in obj:
            obj[k] = rename(obj[k])
    if isinstance(obj.get("variants"), dict):
        for code, entry in obj["variants"].items():
            if isinstance(entry, dict):
                for k in ("sprite", "icon"):
                    if k in entry:
                        entry[k] = rename(entry[k])
    return copied


def _mutation_template(weapon, wid, kind, name=None):
    ph = weapon.get("placeholder") if isinstance(weapon.get("placeholder"), dict) else {}
    return {"id": "%s_%s" % (wid, kind), "name": name or "%s %s" % (str(weapon.get("name", wid)), kind.capitalize()),
            "flavour": "", "rarity": "rare", "weight": 8, "hidden": True, "weapon": wid, "kind": kind, "element": "",
            "hero": "", "text": "", "vfx": "", "effects": [], "params": {}, "art_prompt": "",
            "placeholder": {"color": str(ph.get("color", "#888888")), "glyph": "star"}}


def _evolution_template(weapon, wid, eid, name=None):
    ph = weapon.get("placeholder") if isinstance(weapon.get("placeholder"), dict) else {}
    out = {"id": eid, "name": name or "", "flavour": "", "rarity": "rare",
           "hidden": True, "is_evolution": True, "evolved_from": wid, "max_level": 1}
    if weapon.get("hero"):
        out["hero"] = str(weapon["hero"])
    out["behavior"] = str(weapon.get("behavior", "ProjectileEmitter"))
    out["targeting"] = str(weapon.get("targeting", "nearest"))
    for k in ("base", "params", "sfx"):
        out[k] = json.loads(json.dumps(weapon.get(k, {})))
    out["levels"] = [[]]
    out["placeholder"] = {"color": str(ph.get("color", "#888888")), "glyph": str(ph.get("glyph", "star")), "gold": True}
    out["art_prompt"] = ""
    return out


def _make_path_files(weapon, wid, names=None):
    """Create the three template mutations and the template evolution of weapon `wid` (INTERFACES §0.1); returns
    (created type/id list, evolution id) or raises ValueError when an id exists."""
    names = names if isinstance(names, dict) else {}
    eid = str(weapon.get("evolves_into", "")) or "%s_evolved" % wid
    if content_path("evolution", eid)[1] is not None:
        raise ValueError("the evolution %s exists already" % eid)
    ids = [("mutation", "%s_%s" % (wid, k)) for k in VOCAB.PATH_KINDS] + [("evolution", eid)]
    for kind, cid in ids:
        t = id_exists_anywhere(cid)
        if t:
            raise ValueError("the id %s exists already under content/%s" % (cid, t))
    created = []
    for k in VOCAB.PATH_KINDS:
        obj = _mutation_template(weapon, wid, k, names.get(k))
        folder = os.path.join(CONTENT, "mutations", obj["id"])
        os.makedirs(folder)
        cio.write_atomic(os.path.join(folder, obj["id"] + ".json"), cio.dump_new(obj))
        ledger_add(obj["id"], "mutation", wid)
        created.append("mutations/%s" % obj["id"])
    obj = _evolution_template(weapon, wid, eid, names.get("evolution") or names.get("evolved"))
    folder = os.path.join(CONTENT, "evolutions", eid)
    os.makedirs(folder)
    cio.write_atomic(os.path.join(folder, eid + ".json"), cio.dump_new(obj))
    ledger_add(eid, "evolution", wid)
    created.append("evolutions/%s" % eid)
    return created, eid


def create_content(kind, new_id, template_id, name="", flavour="", doc="", copy_art=False, fields=None):
    """POST /api/content/<kind>: a new folder from a template (its parsed object in its key order, identity reset, art
    keys dropped unless copy_art, the kind's defaults of the synthesis §2 / INTERFACES §0.1), the ledger entry, then a
    `register` job (placeholders, imports) through jobs.py."""
    if kind not in EDIT_KINDS:
        return {"ok": False, "error": "unknown kind %s (one of %s)" % (kind, ", ".join(EDIT_KINDS)), "status": 400}
    if not isinstance(new_id, str) or not ID_RE.match(new_id):
        return {"ok": False, "error": "the id must be lower-case letters, digits and underscores (got %s)" % json.dumps(new_id), "status": 400}
    if new_id.startswith("training_dummy"):
        return {"ok": False, "error": "ids starting with training_dummy are the arena's", "status": 400}
    if not isinstance(name, str) or not name.strip():
        return {"ok": False, "error": "a name is needed", "status": 400}
    if kind in ("enemy", "boss") and (not isinstance(doc, str) or not doc.strip()):
        return {"ok": False, "error": "a creature needs a one-line doc (the Collection's text; a test requires it)", "status": 400}
    with _write_lock:
        t_type = id_exists_anywhere(new_id)
        if t_type:
            return {"ok": False, "error": "the id %s exists already under content/%s" % (new_id, t_type), "status": 409}
        t_kind = kind
        tfolder, tpath = content_path(kind, template_id or "")
        if tpath is None and kind in ("enemy", "boss"):
            # a creature may start from a boss or an enemy alike
            t_kind = "boss" if kind == "enemy" else "enemy"
            tfolder, tpath = content_path(t_kind, template_id or "")
        if tpath is None:
            return {"ok": False, "error": "no template %s of kind %s" % (template_id, kind), "status": 404}
        t = load_json(tpath)
        obj = _reset_from_template(kind, t, new_id, name.strip(), flavour if isinstance(flavour, str) else "",
                                   doc.strip() if isinstance(doc, str) else "", copy_art)
        if isinstance(fields, dict):
            for k, v in fields.items():
                if k != "id" and isinstance(k, str):
                    obj[k] = v
        if kind in ("enemy", "boss"):
            if "doc" not in obj:
                obj["doc"] = doc.strip()
            obj = _insert_after(obj, "damage", "knockback", default_knockback(obj.get("damage", 5.0)))
            if kind == "boss" and str(obj.get("archetype", "")) != "boss":
                obj["archetype"] = "boss"
            if not copy_art:
                obj.pop("strip_cols", None)
        elif kind == "hero":
            orders = [int(d["order"]) for _, _, _, d in _load_kind("hero") if isinstance(d.get("order"), (int, float)) and not isinstance(d.get("order"), bool)]
            obj["order"] = (max(orders) + 1) if orders else 100
            obj = _insert_after(obj, "pronoun" if "pronoun" in obj else "order", "hidden", True)
            obj = _insert_after(obj, "hidden", "availability", "hidden")
            obj = _insert_after(obj, "availability", "price", 0)
            obj = _insert_after(obj, "price", "currency_type", "gold")
        elif kind == "weapon":
            obj = _insert_after(obj, "weight" if "weight" in obj else "rarity", "hidden", bool(NEW_WEAPON_STARTS_HIDDEN))
            if not obj.get("hidden"):
                obj.pop("hidden", None)
            obj["evolves_into"] = "%s_evolved" % new_id
            obj["evolves_with"] = ""
        elif kind in ("evolution", "mutation"):
            obj = _insert_after(obj, "weight" if "weight" in obj else "rarity", "hidden", True)
        elif kind == "passive":
            obj.pop("hidden", None)
            for k in ("evolves_into", "evolves_from"):
                if k in obj:
                    obj[k] = ""
        folder = os.path.join(CONTENT, KIND_FOLDERS[kind], new_id)
        os.makedirs(folder)
        copied = _copy_art_files(kind, template_id, os.path.dirname(tpath), new_id, folder, obj) if copy_art else []
        path = os.path.join(folder, new_id + ".json")
        cio.write_atomic(path, cio.dump_new(obj))
        ledger_add(new_id, kind, template_id)
        created = ["%s/%s" % (KIND_FOLDERS[kind], new_id)]
        if kind == "weapon":
            try:
                more, _ = _make_path_files(obj, new_id)
                created += more
            except ValueError as e:
                return {"ok": True, "id": new_id, "kind": kind, "file": rel(path), "created": created, "copied": copied,
                        "job": None, "job_error": "the path templates were not created: %s" % e}
    job = _enqueue("register", {"kind": kind, "id": new_id}, {"targets": created}, "register %s" % new_id)
    return {"ok": True, "id": new_id, "kind": kind, "file": rel(path), "created": created, "copied": copied,
            "job": job.get("job"), "job_error": job.get("error")}


def make_path(wid, names=None):
    """POST /api/content/weapon/<id>/make_path: the three template mutations and the template evolution of an existing
    weapon, `evolves_into` set when it was empty, one `register` job; refused when any id exists."""
    tfolder, path = content_path("weapon", wid)
    if path is None:
        return {"ok": False, "error": "no weapon %s" % wid, "status": 404}
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        try:
            created, eid = _make_path_files(d, wid, names)
        except ValueError as e:
            return {"ok": False, "error": str(e), "status": 409}
        text = src
        if str(d.get("evolves_into", "")) != eid:
            text = cio.set_top_block(src, "evolves_into", eid, [("after", "evolves_with"), ("after", "levels"), ("end", None)])
            if text is None:
                return {"ok": False, "error": _layout_error(path, "evolves_into"), "created": created, "status": 400}
            backup(wid, path)
            cio.write_atomic(path, text)
        created.append("weapons/%s" % wid)
    job = _enqueue("register", {"kind": "weapon", "id": wid}, {"targets": created}, "register %s's path" % wid)
    return {"ok": True, "created": created, "evolution": eid, "job": job.get("job"), "job_error": job.get("error")}


def set_retired(kind, cid, retired):
    """POST /api/content/<kind>/<id>/retire {retired}: enemies and bosses; retiring one a map names is refused (409)."""
    if kind not in ("enemy", "boss"):
        return {"ok": False, "error": "only creatures retire (items hide, heroes have availability)", "status": 400}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid), "status": 404}
    retired = bool(retired)
    if retired:
        refs = map_references(cid)
        if refs:
            return {"ok": False, "error": "a map still names %s" % cid, "refs": refs, "status": 409}
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        if bool(d.get("retired", False)) == retired:
            return {"ok": True, "retired": retired, "unchanged": True, "import_ok": True, "output": "nothing changed"}
        if retired:
            text = cio.set_top_block(src, "retired", True, [("after", "hidden"), ("after", "doc"), ("after", "flavour"), ("end", None)])
        else:
            text = cio.del_top_block(src, "retired") if "retired" in d else src
        if text is None:
            return {"ok": False, "error": _layout_error(path, "retired"), "status": 400}
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
    import_ok, output = run_import("%s/%s" % (tfolder, cid))
    return {"ok": True, "retired": retired, "backup": backup_rel, "import_ok": import_ok, "output": output}


def _quest_object(kind, cid, d, quest):
    """A new unlock quest in unlock_adrenaline.json's shape."""
    quest = quest if isinstance(quest, dict) else {}
    cond = quest.get("condition") if isinstance(quest.get("condition"), dict) and quest["condition"].get("type") else dict(VOCAB.QUEST_TEMPLATE_CONDITION)
    ph = d.get("placeholder") if isinstance(d.get("placeholder"), dict) else {}
    utype = "character" if kind == "hero" else "weapon" if kind in ("weapon", "evolution") else "passive"   # pass 69: heroes
    out = {"id": "unlock_%s" % cid, "name": str(quest.get("name") or d.get("name", cid)), "condition": cond,
           "unlocks": {"type": utype, "id": cid}}
    if quest.get("quest_text"):
        out["quest_text"] = str(quest["quest_text"])
    out["art_prompt"] = str(quest.get("art_prompt") or d.get("art_prompt", ""))
    out["placeholder"] = {"color": str(ph.get("color", "#C9A227")), "glyph": "star"}
    return out


def _hero_quest_op(cid, d, quest):
    """Pass 69: a hero's requirement, the quest whose unlocks is {type character, id} (lane UI's unlock_<hero>, Registry
    .quest_for). `quest` a dict {condition, quest_text?, name?}: the existing quest is edited in place (only the keys that
    changed), else content/quests/unlock_<id>/ is made in unlock_buck.json's shape (ledger, imported); None: the existing
    quest moves to backups/deleted (no requirement: a free hero is owned at once, a purchase hero on sale at once).
    Called under _write_lock. Returns {ok, wrote, imports, quest, moved} or an error record."""
    have = quests_by_unlock().get(("character", cid))
    out = {"ok": True, "wrote": [], "imports": [], "quest": have["id"] if have else None, "moved": None}
    if quest is None:
        if have:
            qfolder = os.path.join(CONTENT, "quests", have["id"])
            dest = deleted_dir(have["id"])
            shutil.move(qfolder, os.path.join(dest, have["id"]))
            ledger_remove(have["id"])
            out.update(moved=rel(dest), quest=None)
            out["wrote"].append("quest %s removed" % have["id"])
        return out
    if have:
        qpath = os.path.join(CONTENT, "quests", have["id"], have["id"] + ".json")
        qsrc = cio.read_text(qpath)
        qold = json.loads(qsrc)
        qtext = qsrc
        for key, value, places in (("condition", quest.get("condition"), [("after", "name"), ("end", None)]),
                                   ("quest_text", quest.get("quest_text"), [("after", "unlocks"), ("end", None)]),
                                   ("name", quest.get("name"), [("after", "id"), ("end", None)])):
            if value is None or (value == "" and key != "quest_text") or qold.get(key) == value:
                continue
            if key == "quest_text" and value == "":
                qtext = cio.del_top_block(qtext, key) if key in qold else qtext
            else:
                qtext = cio.set_top_block(qtext, key, value, places)
            if qtext is None:
                return {"ok": False, "error": _layout_error(qpath, key), "status": 400}
        if qtext != qsrc:
            backup(have["id"], qpath)
            cio.write_atomic(qpath, qtext)
            out["wrote"].append("quest %s" % have["id"])
            out["imports"].append("quests/%s" % have["id"])
        return out
    qobj = _quest_object("hero", cid, d, quest)
    # the quest's icon words in the shape of lane UI's (a jar with something of his inside), never his whole art prompt
    qobj["art_prompt"] = str(quest.get("art_prompt") or "a glass jar with a small figure of %s inside" % str(d.get("name", cid)))
    qid = qobj["id"]
    if id_exists_anywhere(qid):
        return {"ok": False, "error": "the quest id %s exists already but does not unlock the hero %s" % (qid, cid), "status": 409}
    qfolder = os.path.join(CONTENT, "quests", qid)
    os.makedirs(qfolder)
    cio.write_atomic(os.path.join(qfolder, qid + ".json"), cio.dump_new(qobj))
    ledger_add(qid, "quest", cid)
    out["wrote"].append("quest %s" % qid)
    out["imports"].append("quests/%s" % qid)
    out["quest"] = qid
    return out


def set_availability(kind, cid, body):
    """POST /api/content/<kind>/<id>/availability. Hero: {availability: hidden|available|purchase, price, currency_type,
    quest?} written, `hidden` kept in step (pass 69: hidden = availability == hidden; a purchase hero is on the title);
    `quest` (pass 69) a {condition, quest_text, name} writes his requirement content/quests/unlock_<id> (unlocks
    {type character}), null removes it, absent leaves it (_hero_quest_op). Item: {availability: hidden|available|locked,
    quest?: {condition, quest_text, name}}: hidden sets `hidden: true`; available removes `hidden` and the unlock quest
    (moved to backups/deleted); locked makes or edits content/quests/unlock_<id>. A weapon turns available or locked
    only when its path is complete (INTERFACES §0.1; `missing` lists what is not)."""
    if kind not in EDIT_KINDS or kind in ("enemy", "boss"):
        return {"ok": False, "error": "availability is for heroes and items (creatures retire)", "status": 400}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid), "status": 404}
    body = body if isinstance(body, dict) else {}
    avail = str(body.get("availability", ""))
    wrote, imports, quest_out, moved = [], ["%s/%s" % (tfolder, cid)], None, None
    if kind == "hero":
        if avail not in VOCAB.AVAILABILITY:
            return {"ok": False, "error": "availability must be one of %s" % ", ".join(VOCAB.AVAILABILITY), "status": 400}
        price = body.get("price", None)
        if price is not None and (not isinstance(price, (int, float)) or isinstance(price, bool) or price < 0):
            return {"ok": False, "error": "price must be a whole number >= 0", "status": 400}
        cur = body.get("currency_type", None)
        if cur is not None and cur not in VOCAB.CURRENCIES:
            return {"ok": False, "error": "currency_type must be one of %s" % ", ".join(VOCAB.CURRENCIES), "status": 400}
        if "quest" in body and body["quest"] is not None and not (isinstance(body["quest"], dict) and isinstance(body["quest"].get("condition"), dict)
                                                                   and str(body["quest"]["condition"].get("type", "")) in VOCAB.QUEST_TYPES):
            return {"ok": False, "error": "the requirement needs a condition whose type is one of %s" % ", ".join(sorted(VOCAB.QUEST_TYPES)), "status": 400}
        with _write_lock:
            src = cio.read_text(path)
            d = json.loads(src)
            text = src
            # pass 69 (lane UI's JsonContent rule): only "hidden" hides; a purchase hero is on the title (locked or on sale)
            steps = [("hidden", avail == "hidden", [("after", "pronoun"), ("after", "order"), ("after", "flavour"), ("after", "name"), ("end", None)]),
                     ("availability", avail, [("after", "hidden"), ("end", None)]),
                     ("price", int(price) if price is not None else int(_num(d.get("price"), 0)), [("after", "availability"), ("end", None)]),
                     ("currency_type", str(cur or d.get("currency_type", "gold")), [("after", "price"), ("end", None)])]
            for key, value, places in steps:
                if d.get(key) == value and key in d:
                    continue
                text = cio.set_top_block(text, key, value, places)
                if text is None:
                    return {"ok": False, "error": _layout_error(path, key), "status": 400}
                wrote.append(key)
            # pass 69: his requirement (body.quest: a dict writes content/quests/unlock_<id>, None removes it, absent keeps it)
            if "quest" in body:
                res = _hero_quest_op(cid, d, body["quest"])
                if not res.get("ok"):
                    return res
                wrote += res["wrote"]
                imports += res["imports"]
                quest_out, moved = res["quest"], res["moved"]
            if not wrote:
                return {"ok": True, "unchanged": True, "wrote": [], "import_ok": True, "output": "nothing changed",
                        "availability": avail, "quest": quest_out}
            backup_rel = ""
            if text != src:
                backup_rel = backup(cid, path)
                cio.write_atomic(path, text)
    else:
        if avail not in ("hidden", "available", "locked") or (avail == "locked" and kind not in ("weapon", "passive")):
            return {"ok": False, "error": "an item's availability is hidden, available or (weapons and passives) locked", "status": 400}
        if kind == "weapon" and avail != "hidden":
            missing = weapon_path_missing(cid)
            if missing:
                return {"ok": False, "error": "the weapon cannot turn %s yet: its path is not complete" % avail,
                        "missing": missing, "status": 409}
        qtype = "weapon" if kind in ("weapon", "evolution") else "passive"
        with _write_lock:
            src = cio.read_text(path)
            d = json.loads(src)
            text = src
            if avail == "hidden":
                if not d.get("hidden"):
                    text = cio.set_top_block(text, "hidden", True, [("after", "weight"), ("after", "rarity"), ("after", "flavour"), ("after", "name"), ("end", None)])
                    wrote.append("hidden")
            elif "hidden" in d:
                text = cio.del_top_block(text, "hidden")
                wrote.append("hidden")
            if text is None:
                return {"ok": False, "error": _layout_error(path, "hidden"), "status": 400}
            quests = quests_by_unlock()
            have = quests.get((qtype, cid))
            if avail == "locked":
                q = body.get("quest") if isinstance(body.get("quest"), dict) else {}
                if have:
                    qpath = os.path.join(CONTENT, "quests", have["id"], have["id"] + ".json")
                    qsrc = cio.read_text(qpath)
                    qtext = qsrc
                    for key, value, places in (("condition", q.get("condition"), [("after", "name"), ("end", None)]),
                                               ("quest_text", q.get("quest_text"), [("after", "unlocks"), ("end", None)]),
                                               ("name", q.get("name"), [("after", "id"), ("end", None)])):
                        if value is None or value == "" or json.loads(qsrc).get(key) == value:
                            continue
                        qtext = cio.set_top_block(qtext, key, value, places)
                        if qtext is None:
                            return {"ok": False, "error": _layout_error(qpath, key), "status": 400}
                    if qtext != qsrc:
                        backup(have["id"], qpath)
                        cio.write_atomic(qpath, qtext)
                        wrote.append("quest %s" % have["id"])
                    quest_out = have["id"]
                else:
                    qobj = _quest_object(kind, cid, d, q)
                    qid = qobj["id"]
                    if id_exists_anywhere(qid):
                        return {"ok": False, "error": "the quest id %s exists already but does not unlock %s" % (qid, cid), "status": 409}
                    qfolder = os.path.join(CONTENT, "quests", qid)
                    os.makedirs(qfolder)
                    cio.write_atomic(os.path.join(qfolder, qid + ".json"), cio.dump_new(qobj))
                    ledger_add(qid, "quest", cid)
                    wrote.append("quest %s" % qid)
                    quest_out = qid
                imports.append("quests/%s" % quest_out)
            elif have:
                qfolder = os.path.join(CONTENT, "quests", have["id"])
                dest = deleted_dir(have["id"])
                shutil.move(qfolder, os.path.join(dest, have["id"]))
                ledger_remove(have["id"])
                moved = rel(dest)
                wrote.append("quest %s removed" % have["id"])
            if not wrote:
                return {"ok": True, "unchanged": True, "wrote": [], "import_ok": True, "output": "nothing changed",
                        "availability": avail, "quest": have["id"] if have else None}
            if text != src:
                backup_rel = backup(cid, path)
                cio.write_atomic(path, text)
            else:
                backup_rel = ""
    import_ok, output = run_import(",".join(imports))
    out = {"ok": True, "wrote": wrote, "backup": backup_rel, "import_ok": import_ok, "output": output, "availability": avail}
    if kind != "hero" or "quest" in body:
        out["quest"] = quest_out
        out["moved_to"] = moved
    return out


def delete_content(kind, cid, cascade=False):
    """POST /api/content/<kind>/<id>/delete: only ids in the created-ids ledger, and only when nothing names them (409
    `{refs}`); with `cascade`, a weapon's own ledger-held templates (its mutations, its evolution, its unlock quest) go
    with it. The folder moves to backups/deleted/<id>/<stamp>/."""
    if kind not in EDIT_KINDS:
        return {"ok": False, "error": "unknown kind %s" % kind, "status": 400}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid), "status": 404}
    ledger = ledger_load()["ids"]
    if cid not in ledger:
        return {"ok": False, "error": "%s was not created by the Level Editor (only ids in tools/dl/jobs/created.json can be deleted here; "
                                      "remove the folder by hand if you mean it)" % cid, "status": 403}
    with _write_lock:
        refs = references_to(kind, cid)
        extra = []
        if cascade and kind == "weapon":
            for k in ("mutations", "evolutions", "quests"):
                keep = []
                for rid in refs[k]:
                    if rid in ledger:
                        extra.append((k[:-1], rid))
                    else:
                        keep.append(rid)
                refs[k] = keep
        blocking = {k: v for k, v in refs.items() if v}
        if blocking:
            return {"ok": False, "error": "something still names %s" % cid, "refs": blocking, "status": 409}
        dest = deleted_dir(cid)
        moved = []
        for k, rid in extra:
            rfolder = os.path.join(CONTENT, KIND_FOLDERS[k], rid)
            if os.path.isdir(rfolder):
                shutil.move(rfolder, os.path.join(dest, rid))
                ledger_remove(rid)
                moved.append(rid)
        shutil.move(os.path.dirname(path), os.path.join(dest, cid))
        ledger_remove(cid)
        moved.append(cid)
    return {"ok": True, "moved_to": rel(dest), "deleted": moved}


def add_look(kind, cid, code=None, note="", recipe=None):
    """POST /api/content/<kind>/<id>/look {code?, note, recipe}: a stub entry (no sprite: Godot skips it until a painting
    lands) so a job has somewhere to land; the first look of a file without variants creates `variant_base` and the base
    entry first. No import (nothing changes in play) and no job: pass 68's Duplicate makes a DRAFT this way (the source's
    recipe with `from`, its method and painter; Generate… queues the job later)."""
    if kind not in LOOK_KINDS:
        return {"ok": False, "error": "only enemies, bosses and heroes have looks", "status": 400}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid), "status": 404}
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        if code is None or code == "":
            nc = next_codes(kind, cid, 1)
            code = nc["codes"][0]
        if not isinstance(code, str) or not CODE_RE.match(code):
            return {"ok": False, "error": "a look code is letters, digits, - and _ (got %s)" % json.dumps(code), "status": 400}
        vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
        if code in vs or code == str(d.get("variant_base", "")):
            return {"ok": False, "error": "%s has a look %s already" % (cid, code), "status": 409}
        text, base = _ensure_variants(src, kind, cid, d)
        if text is None:
            return {"ok": False, "error": _layout_error(path, base), "status": 400}
        entry = {"note": str(note or "")}
        if isinstance(recipe, dict) and recipe:
            recipe = dict(recipe)
            prob = VOCAB.stills_problem(recipe.get("stills") or None)
            if prob and not recipe.get("from"):
                return {"ok": False, "error": "recipe.stills: " + prob, "status": 400}
            if recipe.get("from"):
                # pass 68 (D5): a Duplicate is a draft of its source (`from`): it copies the words and the painter, never
                # the source's stills slug or seed offset, or its first paint would be the source's pictures again (the
                # job form's "reuse <from>'s paintings" sets the slug when Generate is pressed)
                recipe.pop("stills", None)
                recipe.pop("seed_offset", None)
            entry["recipe"] = recipe
        text = cio.set_variant_entry(text, code, entry)
        if text is None:
            return {"ok": False, "error": _layout_error(path, "variants"), "status": 400}
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
        d2 = json.loads(text)
    return {"ok": True, "code": code, "base": base, "backup": backup_rel,
            "looks": look_records(kind, cid, os.path.dirname(path), d2, path), "import_ok": None, "output": "no import needed"}


def _entry_files(folder, cid, d, code):
    """The PNGs a variant entry owns (its sprite and icon beside the JSON, when no other entry and not the top level
    names them), their .import files and the `<id>_<suffix>_ai.json` marker."""
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    entry = vs.get(code) if isinstance(vs.get(code), dict) else {}
    others = set()
    for c, e in vs.items():
        if c != code and isinstance(e, dict):
            for k in ("sprite", "icon"):
                if e.get(k):
                    others.add(os.path.basename(str(e[k])))
    others.add(os.path.basename(str(d.get("sprite", cid + "_sprite.png"))))
    others.add(os.path.basename(str(d.get("icon", cid + "_icon.png"))))
    out = []
    for k in ("sprite", "icon"):
        name = os.path.basename(str(entry.get(k, "")))
        if not name or name in others:
            continue
        full = os.path.join(folder, name)
        for f in (full, full + ".import"):
            if os.path.isfile(f):
                out.append(f)
    suffix = code.rsplit("-", 1)[-1].lower()
    marker = os.path.join(folder, "%s_%s_ai.json" % (cid, suffix))
    if os.path.isfile(marker):
        out.append(marker)
    # pass 68 (D8): a hero look's own title cut-out (art/ui/wanted/), unless another entry names it or it is the hero's own
    title = os.path.basename(str(entry.get("title", "")))
    others_t = {os.path.basename(str(e.get("title"))) for c, e in vs.items() if c != code and isinstance(e, dict) and e.get("title")}
    if title and FILENAME_RE.match(title) and title != "hero_%s.png" % cid and title not in others_t:
        full = os.path.join(WANTED_ART, title)
        for f in (full, full + ".import"):
            if os.path.isfile(f):
                out.append(f)
    return out


# ---------------------------------------------------------------- pass 70: removing the base look

# the top-level keys that are a look's art: the base look's are these (JsonContent reads them for the base strip), any
# other look's sit in its entry; frame_px is a hero's (a creature's cell is the top level's for every look)
BASE_ART_KEYS = ("sprite", "icon", "anims", "strip_cols", "fps", "frame_px", "head")


def base_art_top(kind, d, entry):
    """{key: value or cio.REMOVE}: the top-level art keys that make `entry`'s look the base strip, as the game reads a look:
    its own sprite / icon / anims / fps / head / frame_px where it has them, else what it already inherited from the top
    level (kept); strip_cols its own, else 0 (a look's default, JsonContent: int(v.get("strip_cols", 0)))."""
    out = {}
    for k in BASE_ART_KEYS:
        if k == "frame_px" and kind != "hero":
            continue
        if k in entry:
            if d.get(k) != entry[k]:
                out[k] = entry[k]
        elif k == "strip_cols":
            if int(_num(d.get("strip_cols"), 0)) != 0:
                out[k] = cio.REMOVE
    return out


def inherited_pins(kind, d, top_change, skip):
    """{code: {key: value}}: what the other looks inherited from the top level and must keep when the top level's art
    keys change (`top_change`, base_art_top's): a look with its own strip and no anims / fps / head (a creature's) /
    frame_px (a hero's) of its own played the top level's, so the old value (the game's default when the top level had
    none) is written into its entry and it plays exactly as before."""
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    defaults = {"anims": VOCAB.CHAR_ANIMS_DEFAULT if kind == "hero" else VOCAB.ENEMY_ANIMS_DEFAULT, "fps": {},
                "head": 0.86, "frame_px": 256 if kind == "hero" else 128}
    keys = [k for k in ("anims", "fps", "head", "frame_px") if k in top_change and not (k == "head" and kind == "hero")
            and not (k == "frame_px" and kind != "hero")]
    out = {}
    for code, e in vs.items():
        if code in skip or not isinstance(e, dict) or not e.get("sprite"):
            continue
        pin = {k: (d[k] if k in d else defaults[k]) for k in keys if k not in e}
        if pin:
            out[code] = pin
    return out


def base_choices(kind, cid, d, folder, old_base):
    """The looks that may become the base when `old_base` goes: an entry with its own strip on disk (not a stub, not the
    base itself); the played look first."""
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    playable = playable_codes(folder, d)
    want = str(d.get("variant", old_base))
    out = [c for c in vs if c != old_base and c in playable and isinstance(vs[c], dict) and vs[c].get("sprite")]
    out.sort(key=lambda c: (c != want, c))
    return out


def remove_base(kind, cid, old_base, new_base=None):
    """POST /api/content/<kind>/<id>/look/<base> {op: remove, new_base}: the base look (`variant_base`) removed (Garry,
    pass 70: "For May, can you remove MAY-A I can't remove it"). `new_base` (default: the look in play) must be a look
    with its own strip on disk. The top-level art keys become the new base's (BASE_ART_KEYS: its sprite, icon, anims,
    strip_cols, fps, a hero's frame_px, head; no file is renamed: the top level names its files), `variant_base` names it,
    the old base's entry goes, and the old base's files nothing names any more (the old top-level strip and icon, their
    .import files, the <id>_ai.json marker of its base runs) move to backups/deleted/<id>/<stamp>/ with base_<CODE>.json
    (what the old base was). The new base keeps its entry whole (recipe, note, title, icon_picked): its jobs still run on
    its own recipe and land in its own files, and merge_look mirrors them to the top level. Refused: the look in play
    (make another the default first), a map row pinning the old base, a new base that is the old one, unknown, a stub or
    a draft; no new_base is a 409 with the choices (the page asks, the look in play first). One backup, one write, an
    import."""
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid), "status": 404}
    folder = os.path.dirname(path)
    moved = []
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
        base = str(d.get("variant_base", ""))
        play = str(d.get("variant", base))
        if old_base != base:
            return {"ok": False, "error": "%s is not %s's base look (that is %s)" % (old_base, cid, base or "none"), "status": 409}
        choices = base_choices(kind, cid, d, folder, old_base)
        if old_base == play:
            return {"ok": False, "error": "%s is the look in play: make another the default first" % old_base, "status": 409,
                    "choices": choices}
        if not choices:
            return {"ok": False, "error": "%s has no other look with a strip of its own to become the base" % cid, "status": 409,
                    "choices": choices}
        if not new_base:
            # the page asks (default: the look in play); the API wants it said
            return {"ok": False, "error": "%s is the base look: say which look becomes the base (new_base: %s; the look in play is %s)"
                    % (old_base, ", ".join(choices), play), "status": 409, "choices": choices, "suggest": choices[0]}
        new_base = str(new_base)
        if new_base not in choices:
            why = "it is the base already" if new_base == old_base else "a look with a strip of its own on disk is needed (not a stub or a draft)"
            return {"ok": False, "error": "%s cannot become the base: %s" % (new_base, why), "status": 400, "choices": choices}
        refs = map_references(cid, old_base)
        if refs:
            return {"ok": False, "error": "a map pins the look %s" % old_base, "refs": refs, "status": 409}
        entry = vs[new_base]
        old_top = {k: d.get(k) for k in BASE_ART_KEYS}
        old_sprite = os.path.basename(str(d.get("sprite", cid + "_sprite.png")))
        old_icon = os.path.basename(str(d.get("icon", cid + "_icon.png")))
        text = src
        if old_base in vs:
            text = cio.del_variant_entry(text, old_base)
            if text is None:
                return {"ok": False, "error": _layout_error(path, "variants"), "status": 400}
        places = [("before", "variants"), ("end", None)]
        change = base_art_top(kind, d, entry)
        # the other looks keep what they inherited from the old top level (their anims, fps, cell)
        pins = inherited_pins(kind, d, change, (old_base, new_base))
        for c, pin in pins.items():
            text = cio.set_variant_entry(text, c, pin)
            if text is None:
                return {"ok": False, "error": _layout_error(path, "variants"), "status": 400}
        for k, v in change.items():
            if v is cio.REMOVE:
                text = cio.del_top_block(text, k)
            else:
                text = cio.set_top_block(text, k, v, places)
            if text is None:
                return {"ok": False, "error": _layout_error(path, k), "status": 400}
        text = cio.set_top_block(text, "variant_base", new_base, places)
        if text is None:
            return {"ok": False, "error": _layout_error(path, "variant_base"), "status": 400}
        d2 = json.loads(text)
        # the old base's files that nothing names any more
        named = {os.path.basename(str(d2.get("sprite", cid + "_sprite.png"))), os.path.basename(str(d2.get("icon", cid + "_icon.png")))}
        for c, e in (d2.get("variants") or {}).items():
            if isinstance(e, dict):
                for k in ("sprite", "icon"):
                    if e.get(k):
                        named.add(os.path.basename(str(e[k])))
        files = []
        for name in (old_sprite, old_icon):
            if name and name not in named and FILENAME_RE.match(name):
                for f in (os.path.join(folder, name), os.path.join(folder, name) + ".import"):
                    if os.path.isfile(f) and f not in files:
                        files.append(f)
        marker = os.path.join(folder, "%s_ai.json" % cid)
        if os.path.isfile(marker):
            files.append(marker)
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
        dest = deleted_dir(cid)
        for f in files:
            shutil.move(f, os.path.join(dest, os.path.basename(f)))
            moved.append(rel(os.path.join(dest, os.path.basename(f))))
        # what the old base was, beside its files, so it can be put back by hand
        with open(os.path.join(dest, "base_%s.json" % old_base), "w", encoding="utf-8", newline="\n") as fh:
            json.dump({"code": old_base, "entry": vs.get(old_base), "top": old_top, "new_base": new_base}, fh, indent=1)
        moved.append(rel(os.path.join(dest, "base_%s.json" % old_base)))
    import_ok, output = run_import("%s/%s" % (tfolder, cid))
    return {"ok": True, "op": "remove", "codes": [old_base], "new_base": new_base, "backup": backup_rel,
            "looks": look_records(kind, cid, folder, d2, path), "import_ok": import_ok, "output": output, "moved": moved,
            "top": {k: d2.get(k) for k in BASE_ART_KEYS if k in d2}, "pinned": pins}


def look_op(kind, cid, codes, op, body=None):
    """POST /api/content/<kind>/<id>/look/<code> {op, ...} and the bulk form {op, codes: [...]}: approve (drops `fresh`),
    shelve (`shelved: true`; refused for the code in play), unshelve, remove (refused for the code in play, the base
    strip's code, or a code a map pins; the entry's own PNGs + .import files and its _ai marker move to
    backups/deleted/<id>/<stamp>/), note {note}, recipe {recipe}, default (the look in play). One backup, one write; an
    import for what the game reads (shelve, unshelve, remove, default)."""
    body = body if isinstance(body, dict) else {}
    if op in ("revert_icon", "use_icon"):
        # pass 76 (lane ICON): "Revert icon" and the gallery's "Use for this look", on any asset with an icon (icon_op)
        c = codes[0] if isinstance(codes, list) and codes else (codes if isinstance(codes, str) else "")
        return icon_op(kind, cid, str(c or ""), op, body)
    if kind not in LOOK_KINDS:
        return {"ok": False, "error": "only enemies, bosses and heroes have looks", "status": 400}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid), "status": 404}
    if op not in ("approve", "shelve", "unshelve", "remove", "note", "recipe", "default"):
        return {"ok": False, "error": "unknown look op %s" % op, "status": 400}
    codes = [c for c in (codes if isinstance(codes, list) else [codes]) if isinstance(c, str) and CODE_RE.match(c)]
    if not codes:
        return {"ok": False, "error": "no look code", "status": 400}
    if op == "remove":
        # pass 70: the base look goes on its own, with the look that becomes the base (body.new_base; default: in play)
        try:
            base_now = str(load_json(path).get("variant_base", ""))
        except (OSError, ValueError, TypeError):
            base_now = ""
        if base_now and base_now in codes:
            if len(codes) > 1:
                return {"ok": False, "error": "%s is the base look: remove it on its own (the editor asks which look becomes the base)" % base_now,
                        "status": 409}
            return remove_base(kind, cid, base_now, body.get("new_base"))
    if op == "default":
        res = write_variant_kind(kind, cid, codes[0])
        if res.get("ok"):
            EV.look_events(kind, cid, codes[:1], "default", backup=res.get("backup"))   # pass 97 (lane PROGRESS, WF-02)
            d = load_json(path)
            res["looks"] = look_records(kind, cid, os.path.dirname(path), d, path)
        else:
            res["status"] = 400
        return res
    folder = os.path.dirname(path)
    moved = []
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
        play = str(d.get("variant", d.get("variant_base", "")))
        base = str(d.get("variant_base", ""))
        text = src
        for code in codes:
            if code not in vs:
                return {"ok": False, "error": "%s has no look %s" % (cid, code), "status": 404}
            if op == "approve":
                text = cio.set_variant_entry(text, code, {"fresh": cio.REMOVE})
            elif op == "shelve":
                if code == play:
                    return {"ok": False, "error": "%s is the look in play: make another the default first" % code, "status": 409}
                text = cio.set_variant_entry(text, code, {"shelved": True})
            elif op == "unshelve":
                text = cio.set_variant_entry(text, code, {"shelved": cio.REMOVE})
            elif op == "note":
                text = cio.set_variant_entry(text, code, {"note": str(body.get("note", ""))})
            elif op == "recipe":
                r = body.get("recipe")
                if r is not None and not isinstance(r, dict):
                    return {"ok": False, "error": "recipe must be an object or null", "status": 400}
                # pass 70 (the Bandit check): the recipe's Stills is the look's slug, never a picture's path
                prob = VOCAB.stills_problem((r or {}).get("stills") or None)
                if prob:
                    return {"ok": False, "error": "recipe.stills: " + prob, "status": 400}
                text = cio.set_variant_entry(text, code, {"recipe": r if r else cio.REMOVE})
            elif op == "remove":
                if code == play:
                    return {"ok": False, "error": "%s is the look in play: make another the default first" % code, "status": 409}
                refs = map_references(cid, code)
                if refs:
                    return {"ok": False, "error": "a map pins the look %s" % code, "refs": refs, "status": 409}
                text = cio.del_variant_entry(text, code)
            if text is None:
                return {"ok": False, "error": _layout_error(path, "variants"), "status": 400}
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
        if op == "remove":
            dest = None
            for code in codes:
                files = _entry_files(folder, cid, d, code)
                if files and dest is None:
                    dest = deleted_dir(cid)
                for f in files:
                    shutil.move(f, os.path.join(dest, os.path.basename(f)))
                    moved.append(rel(os.path.join(dest, os.path.basename(f))))
        d2 = json.loads(text)
    import_ok, output, job = (None, "no import needed", None)
    EV.look_events(kind, cid, codes, op, backup=backup_rel, moved=moved or None,   # pass 97 (lane PROGRESS, WF-02)
                   note=str(body.get("note", "")) if op == "note" else None, recipe=body.get("recipe") if op == "recipe" else None)
    if op in ("shelve", "unshelve", "remove"):
        import_ok, output = run_import("%s/%s" % (tfolder, cid))
    else:
        # approve / note / recipe change nothing the game reads, but they make the JSON newer than the .tres, which the
        # page shows as "not imported": an import job (coalesced, off the request) brings the .tres level again (lead)
        try:
            target = "%s/%s" % (tfolder, cid)
            job = _enqueue("import", {"kind": "content", "id": target}, {"targets": [target]}, "import %s" % target)
            output = "import queued"
        except Exception as e:  # no jobs module, or a bad spec: the next Save or finished job imports
            output = "import not queued: %s" % e
    return {"ok": True, "op": op, "codes": codes, "backup": backup_rel, "looks": look_records(kind, cid, folder, d2, path),
            "import_ok": import_ok, "output": output, "moved": moved, "job": job}


# ---------------------------------------------------------------- pass 76 (lane ICON): the icon guard

# Garry, pass 76: "I made a variant of an Icon and can't find the old one. Make a fix in LevelEditor to make sure that
# this doesn't happen." (A badge painted for Solenne's base was installed into SOL-B, the look in play, and the hero's
# own badge left every screen.) From here every change of an icon goes through set_look_icon:
#   - nothing is overwritten: an installed candidate lands in a file of its own (fresh_icon_name);
#   - the key that names an icon keeps its past beside it: `icon_history` (a look's in its entry, the base's at the top
#     level next to `icon`), each step with a copy of the picture it replaced under backups/<id>/ (keep_icon_copy);
#   - the look in play and the base (every look without an icon of its own shows the base's) change only with
#     `confirm: true` (the page asks first: now -> new, the file names, "the look the game plays");
#   - "Revert icon" (revert_icon) steps back one change; "Use for this look" (use_icon) puts any picture of
#     icon_gallery's on a look: the folder's icons, backups/<id>/, removed looks' files (backups/deleted/<id>/) and the
#     older tools' copies (tools/dl/backup/icons*/).

WEAPON_FAMILY_KINDS = FAMILY_LOOK_KINDS   # lane LOOKS' weapon families (a weapon, its evolution, its mutations)
ICON_HISTORY_MAX = 40
LEGACY_ICON_BACKUPS = os.path.join(DL, "backup")


def _icon_name_re(cid):
    """The icon files of an asset: <id>_icon.png, <id>_icon_<x>.png, <id>_icon_<x>_<tag>_c2.png, <id>_icon_<stamp>.png."""
    return re.compile(r"^%s_icon(?:[_.-][A-Za-z0-9._-]*)?\.png$" % re.escape(cid))


def _abs_path(p):
    """A path rel() wrote (repo-relative with forward slashes, or absolute on another drive) as an absolute one."""
    p = str(p or "")
    if not p:
        return ""
    return p if os.path.isabs(p) else os.path.join(ROOT, p.replace("/", os.sep))


def _file_digest(path):
    import hashlib
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def _same_bytes(a, b):
    try:
        return os.path.getsize(a) == os.path.getsize(b) and _file_digest(a) == _file_digest(b)
    except OSError:
        return False


def _load_or_empty(path):
    try:
        d = load_json(path) if path else {}
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _backups_root():
    """backups/ with its .gitignore (nothing under it goes in the repository), as backup() makes it."""
    os.makedirs(BACKUPS, exist_ok=True)
    ignore = os.path.join(BACKUPS, ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8", newline="\n") as f:
            f.write("*\n")


def icon_backup_dir(cid):
    """tools/level_editor/backups/<id>/: the copies of an asset's icons (pass 76), beside its JSON backups."""
    return os.path.join(BACKUPS, cid)


def keep_icon_copy(cid, full):
    """A copy of the picture `full` under backups/<id>/ as <stem>_<stamp>.png, unless a copy with the same bytes is there
    already. The rel path of the copy (made now or found); "" when `full` is not a file."""
    if not full or not os.path.isfile(full):
        return ""
    _backups_root()
    folder = icon_backup_dir(cid)
    os.makedirs(folder, exist_ok=True)
    size, digest = os.path.getsize(full), None
    for name in sorted(os.listdir(folder)):
        p = os.path.join(folder, name)
        if name.lower().endswith(".png") and os.path.isfile(p) and os.path.getsize(p) == size:
            digest = digest or _file_digest(full)
            if _file_digest(p) == digest:
                return rel(p)
    stem = os.path.splitext(os.path.basename(full))[0]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(folder, "%s_%s.png" % (stem, stamp))
    n = 1
    while os.path.exists(dest):
        n += 1
        dest = os.path.join(folder, "%s_%s-%d.png" % (stem, stamp, n))
    shutil.copy2(full, dest)
    return rel(dest)


def _named_icons(cid, d):
    """The icon file names a JSON names: its top-level `icon` (or <id>_icon.png) and every look entry's `icon`."""
    out = [os.path.basename(str(d.get("icon") or cid + "_icon.png"))]
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    for e in vs.values():
        if isinstance(e, dict) and e.get("icon"):
            out.append(os.path.basename(str(e["icon"])))
    return [n for n in dict.fromkeys(out) if FILENAME_RE.match(n)]


def _folder_icon_names(cid, folder, d):
    """The icon PNGs in an asset's folder: every <id>_icon*.png and any other file its JSON names as an icon, sorted."""
    pat = _icon_name_re(cid)
    names = set(n for n in _named_icons(cid, d) if os.path.isfile(os.path.join(folder, n)))
    try:
        for n in os.listdir(folder):
            if pat.match(n) and os.path.isfile(os.path.join(folder, n)):
                names.add(n)
    except OSError:
        pass
    return sorted(names)


def snapshot_icons(kind, cid):
    """Every icon of an asset (_folder_icon_names) copied into backups/<id>/ unless those bytes are there already: run
    before a job that may paint over one (a look's re-roll repaints its own icon, an item icon roll its <id>_icon.png).
    The rel paths of the copies (made now or found)."""
    tfolder, path = content_path(kind, cid)
    if path is None:
        return []
    folder = os.path.dirname(path)
    out = []
    for name in _folder_icon_names(cid, folder, _load_or_empty(path)):
        r = keep_icon_copy(cid, os.path.join(folder, name))
        if r:
            out.append(r)
    return out


def fresh_icon_name(folder, cid, code="", tag=""):
    """A file name no file in `folder` has, for a new icon (a pick never overwrites): <id>_icon[_<letter>][_<tag>].png,
    then _2, _3... A look's letter is its code's last part (SOL-B -> b); the base's icon has none."""
    letter = str(code).split("-")[-1].lower() if code else ""
    tag = re.sub(r"[^A-Za-z0-9_-]", "", str(tag or ""))
    stem = "%s_icon%s%s" % (cid, "_" + letter if letter else "", "_" + tag if tag else "")
    name, n = stem + ".png", 1
    while os.path.exists(os.path.join(folder, name)) or os.path.exists(os.path.join(folder, name + ".import")):
        n += 1
        name = "%s_%d.png" % (stem, n)
    return name


def _base_code(kind, d):
    """The base look's code: `variant_base`; a weapon family member's family_base_code (lane LOOKS: "A" when it has looks
    and names none)."""
    if kind in WEAPON_FAMILY_KINDS:
        return family_base_code(d)
    return str(d.get("variant_base") or "")


def icon_played_code(kind, cid, folder, d):
    """The look whose icon the game shows for an asset: the JSON's `variant` when it can play it, else the base ("" for an
    asset without looks). A weapon family (lane LOOKS' helpers): the weapon's weapon_play_code, a member wears its
    weapon's look when it can (family_member_play), else its base."""
    base = _base_code(kind, d)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    if not vs:
        return base
    want = str(d.get("variant") or base)
    if kind in LOOK_KINDS:
        ok = playable_codes(folder, d)
    elif kind in WEAPON_FAMILY_KINDS:
        if kind == "weapon":
            return weapon_play_code(folder, d)
        want = family_member_play(kind, cid, d) or base
        ok = family_playable_codes(folder, d)
    else:
        ok = item_playable_codes(folder, d)
    return want if want in ok else base


def look_icon_info(kind, cid, folder, d, code):
    """A look's icon now: {code (the base's own code for the base), base, played, play, shown (the file the game shows for
    it), own (the look names its own; the base: the JSON names its icon), picked, history, exists, url, what (badge for a
    hero, else icon), shared_by (the base: the looks without an icon of their own, which show its icon), revertable}. The
    game's order (JsonContent): a look's own icon when its file is there, else the top-level `icon` (or <id>_icon.png); the
    base reads the top level (a card, or a hero base with a strip of its own, reads its entry's icon first)."""
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    base = _base_code(kind, d)
    is_base = not code or code == base
    code = base if is_base else str(code)
    top = os.path.basename(str(d.get("icon") or cid + "_icon.png"))
    e = vs.get(code) if isinstance(vs.get(code), dict) else {}
    own_name = os.path.basename(str(e.get("icon") or ""))
    own_ok = bool(own_name) and resolve_file(folder, own_name) is not None
    if is_base:
        entry_first = own_ok and kind not in ("enemy", "boss") and (kind != "hero" or bool(e.get("sprite")))
        shown, own, hist, picked = (own_name if entry_first else top), (entry_first or bool(d.get("icon"))), d.get("icon_history"), False
    else:
        shown, own, hist, picked = (own_name if own_ok else top), own_ok, e.get("icon_history"), bool(e.get("icon_picked"))
    hist = [h for h in hist if isinstance(h, dict)] if isinstance(hist, list) else []
    played = icon_played_code(kind, cid, folder, d)
    shared = []
    if is_base:
        for c, x in vs.items():
            if c == code or not isinstance(x, dict):
                continue
            n = os.path.basename(str(x.get("icon") or ""))
            if n and resolve_file(folder, n):
                continue
            if (kind in LOOK_KINDS and x.get("sprite")) or kind in WEAPON_FAMILY_KINDS:
                shared.append(str(c))
    full = resolve_file(folder, shown)
    return {"code": code, "base": is_base, "played": code == played, "play": played, "shown": shown, "own": own,
            "picked": picked, "history": hist, "exists": full is not None,
            "url": ("/iconfile/%s/%s/folder/%s?v=%d" % (kind, cid, shown, int(os.path.getmtime(full)))) if full else "",
            "what": "badge" if kind == "hero" else "icon", "shared_by": sorted(shared),
            "revertable": bool(hist) or (not is_base and own_ok and picked)}


def _now_text():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def _icon_refusal(kind, cid, d, info, new_name, new_url, label, verb="change"):
    """The 409 the page turns into its question: the look in play or the base changes its icon only with confirm: true.
    The body carries what the question shows: now -> new (files and pictures), played, base, the looks that share it."""
    name = str(d.get("name") or cid)
    what = info["what"]
    who = info["code"] or name
    bits = []
    if not info["code"]:
        bits.append("it is %s's own %s (it has no other looks): the game shows it wherever it shows %s" % (name, what, name))
    else:
        if info["played"]:
            bits.append("%s is the look the game plays" % who)
        if info["base"]:
            sb = info["shared_by"]
            bits.append("%s is the base look: its %s is %s's own%s" % (who, what, name, (", and %s show%s it too (no %s of %s own)" % (
                ", ".join(sb), "s" if len(sb) == 1 else "", what, "its" if len(sb) == 1 else "their")) if sb else ""))
            if info["play"] in sb:
                bits.append("%s, the look the game plays, is one of them" % info["play"])
    return {"ok": False, "status": 409, "confirm_needed": True, "kind": kind, "id": cid, "name": name, "what": what,
            "look": info["code"], "base": info["base"], "played": info["played"], "play": info["play"], "shared_by": info["shared_by"],
            "verb": verb, "now": {"file": info["shown"], "url": info["url"], "own": info["own"]},
            "next": {"file": new_name, "url": new_url, "label": label},
            "error": "%s's %s for %s would change: now %s, new %s. %s. Nothing is overwritten (%s stays on disk); send "
                     "confirm: true to go on" % (name, what, who, info["shown"], new_name or "?", "; ".join(bits), info["shown"])}


def set_look_icon(kind, cid, code, file, why="", confirm=None, need_file=True):
    """THE one place an icon changes (pass 76, lane ICON): the look's icon set to `file`, a plain PNG name in the asset's
    folder (`need_file`: it must be on disk; a job's landing names the file its tool just wrote). A look (any code but the
    base's): its entry's `icon` and `icon_picked` (its re-rolls keep it). The base (code "" or `variant_base`): the
    top-level `icon`, and the base entry's when that entry names one of its own. First the picture the look showed is
    copied into backups/<id>/ (keep_icon_copy) and a step {icon (what the key said, "" = nothing of its own), shown,
    backup, to, at, why[, picked | entry_icon]} goes onto the `icon_history` beside the key (the last ICON_HISTORY_MAX
    kept). One JSON backup, one write, no import (the caller's). `confirm` None: no question (a job landing: its install
    was confirmed when queued); else the look in play and the base need confirm True, or the 409 the page asks with
    (_icon_refusal). Heroes, creatures and items (cards; weapon families) alike."""
    if kind not in EDIT_KINDS:
        return {"ok": False, "status": 400, "error": "%s has no icon the editor sets" % kind}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "status": 404, "error": "no %s %s" % (kind, cid)}
    folder = os.path.dirname(path)
    name = str(file or "")
    if not name or not FILENAME_RE.match(name) or name.startswith(".") or not name.lower().endswith(".png"):
        return {"ok": False, "status": 400, "error": "an icon is a PNG file name beside the JSON (got %r)" % (file,)}
    if need_file and not os.path.isfile(os.path.join(folder, name)):
        return {"ok": False, "status": 404, "error": "%s is not in %s" % (name, rel(folder))}
    code = str(code or "")
    if code and not CODE_RE.match(code):
        return {"ok": False, "status": 400, "error": "bad look code %r" % code}
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
        base = _base_code(kind, d)
        is_base = not code or code == base
        if not is_base and code not in vs:
            return {"ok": False, "status": 404, "error": "%s has no look %s" % (cid, code)}
        info = look_icon_info(kind, cid, folder, d, code)
        e = vs.get(code) if isinstance(vs.get(code), dict) else {}
        be = vs.get(base) if base and isinstance(vs.get(base), dict) else {}
        if is_base:
            same = os.path.basename(str(d.get("icon") or cid + "_icon.png")) == name and (not be.get("icon") or be.get("icon") == name)
        else:
            same = e.get("icon") == name and e.get("icon_picked") is True
        if same:
            return {"ok": True, "unchanged": True, "kind": kind, "id": cid, "code": info["code"], "base": is_base, "file": name,
                    "was": name, "backup": "", "icon_backup": "", "layout": "entry", "icon": info, "entry": e or None}
        if confirm is not None and confirm is not True and (info["played"] or info["base"]):
            return _icon_refusal(kind, cid, d, info, name, "/iconfile/%s/%s/folder/%s" % (kind, cid, name), name)
        shown_full = resolve_file(folder, info["shown"])
        copy = keep_icon_copy(cid, shown_full) if shown_full else ""
        if is_base:
            step = {"icon": os.path.basename(str(d["icon"])) if d.get("icon") else ""}
            if base and isinstance(vs.get(base), dict) and vs[base].get("icon"):
                step["entry_icon"] = os.path.basename(str(vs[base]["icon"]))
        else:
            step = {"icon": os.path.basename(str(e["icon"])) if e.get("icon") else "", "picked": bool(e.get("icon_picked"))}
        step.update({"shown": info["shown"], "backup": copy, "to": name, "at": _now_text(), "why": str(why or "")})
        history = (info["history"] + [step])[-ICON_HISTORY_MAX:]
        if is_base:
            text = cio.set_top_block(src, "icon", name, [("before", "variants"), ("end", None)])
            if text is not None:
                text = cio.set_top_block(text, "icon_history", history, [("after", "icon"), ("before", "variants"), ("end", None)])
            if text is not None and step.get("entry_icon"):
                text = cio.set_variant_entry(text, base, {"icon": name})
        else:
            text = cio.set_variant_entry(src, code, {"icon": name, "icon_picked": True, "icon_history": history})
        if text is None:
            return {"ok": False, "status": 400, "error": _layout_error(path, "the icon keys")}
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
        d2 = json.loads(text)
    EV.emit("icon", "set", look=EV.look_of(kind, cid, info["code"]), file=name, was=info["shown"], base=is_base, why=str(why or ""),   # pass 97 (lane PROGRESS, WF-02)
            icon_backup=copy, backup=backup_rel)
    return {"ok": True, "kind": kind, "id": cid, "code": info["code"], "base": is_base, "file": name, "was": info["shown"],
            "icon_backup": copy, "backup": backup_rel, "layout": "entry", "history": len(history),
            "entry": None if is_base else (d2.get("variants") or {}).get(code), "icon": look_icon_info(kind, cid, folder, d2, code)}


def _picture_in_folder(cid, folder, name, copy_rel, dry=False):
    """(file, put_back) for a picture a history step names: `name` when it is in the folder with the bytes of its copy
    (or there is no copy to compare), else the copy put back into the folder under its own name (a fresh one when that is
    taken); ("", False) when neither is there. `dry`: the name it would get, nothing copied."""
    full = os.path.join(folder, name) if name else ""
    copy = _abs_path(copy_rel)
    have_copy = bool(copy) and os.path.isfile(copy)
    if full and os.path.isfile(full) and (not have_copy or _same_bytes(full, copy)):
        return name, False
    if not have_copy:
        return "", False
    for n in _folder_icon_names(cid, folder, {}):
        if _same_bytes(os.path.join(folder, n), copy):
            return n, False
    want = os.path.basename(copy)
    if os.path.exists(os.path.join(folder, want)) or os.path.exists(os.path.join(folder, want + ".import")):
        stem, k = os.path.splitext(want)[0], 1
        while True:
            k += 1
            want = "%s-%d.png" % (stem, k)
            if not os.path.exists(os.path.join(folder, want)) and not os.path.exists(os.path.join(folder, want + ".import")):
                break
    if not dry:
        shutil.copy2(copy, os.path.join(folder, want))
    return want, True


def _icon_import(kind, cid, new_png):
    """After an icon op: a PNG new to the folder needs Godot's --import before import_json can name it (an `import` job:
    --import, lossy_imports, --import, import_json); one already imported only the JSON -> .tres import."""
    target = "%s/%s" % (KIND_FOLDERS[kind], cid)
    if new_png:
        r = _enqueue("import", {"kind": "content", "id": target}, {"targets": [target]}, "import %s (an icon put back)" % target)
        return None, ("import queued (the PNG first)" if r.get("job") else "import not queued: %s" % r.get("error")), r.get("job")
    ok, out = run_import(target)
    return ok, out, None


def revert_icon(kind, cid, code, confirm=None):
    """"Revert icon" (pass 76, a look op): the look's (or the base's) icon one change back. The last `icon_history` step is
    undone: the key gets back what it said (the picture put back from the step's copy when its file was painted over
    since; a look's icon_picked as it was; a step from when the look had no icon of its own drops its `icon`; the base's
    default <id>_icon.png when the top level named none, or the copy when that file changed since), and the step goes.
    With no history, a look whose own icon was picked (before pass 76: Solenne's SOL-B) loses that icon and shows the
    base's again; anything else has nothing to revert. The look in play and the base need confirm, like set_look_icon;
    the question is asked before anything is copied. One JSON backup, one write, then the import."""
    if kind not in EDIT_KINDS:
        return {"ok": False, "status": 400, "error": "%s has no icon the editor sets" % kind}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "status": 404, "error": "no %s %s" % (kind, cid)}
    code = str(code or "")
    if code and not CODE_RE.match(code):
        return {"ok": False, "status": 400, "error": "bad look code %r" % code}
    folder = os.path.dirname(path)
    put_back = False
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
        base = _base_code(kind, d)
        is_base = not code or code == base
        if not is_base and code not in vs:
            return {"ok": False, "status": 404, "error": "%s has no look %s" % (cid, code)}
        info = look_icon_info(kind, cid, folder, d, code)
        hist = info["history"]
        step = hist[-1] if hist else None
        # what the key gets back: (name, copy to put back) -- name "" = the key goes
        if step is not None:
            prev = os.path.basename(str(step.get("icon") or ""))
            copy_rel = str(step.get("backup") or "")
            if prev:
                name, needs = _picture_in_folder(cid, folder, prev, copy_rel, dry=True)
                if not name:
                    return {"ok": False, "status": 409, "error": "%s is gone and its copy (%s) too: use the gallery" % (prev, copy_rel or "none")}
            elif is_base:
                dflt = cid + "_icon.png"
                name, needs = (_picture_in_folder(cid, folder, dflt, copy_rel, dry=True) if step.get("shown") == dflt else (dflt, False))
                name = "" if name == dflt and not needs else name
            else:
                name, needs = "", False
        elif not is_base and info["own"] and info["picked"]:
            name, needs, copy_rel = "", False, ""
        else:
            return {"ok": False, "status": 409, "error": "nothing to revert: %s's %s for %s has no earlier one recorded%s" % (
                cid, info["what"], info["code"] or "it", "" if is_base else " and was not picked (use the gallery to put another on it)")}
        if is_base:
            after = name or cid + "_icon.png"
        else:
            after = name or os.path.basename(str(d.get("icon") or cid + "_icon.png"))
        if confirm is not None and confirm is not True and (info["played"] or info["base"]):
            url = ("/iconfile/%s/%s/folder/%s" % (kind, cid, after)) if not needs else ("/iconfile/%s/%s/%s" % (kind, cid, _gallery_ref(cid, _abs_path(copy_rel))))
            if not is_base and not name:
                label = "the base's %s: %s has none of its own again" % (info["what"], info["code"])
            else:
                label = "as it was before %s" % str((step or {}).get("at") or "the last change")[:16]
            return _icon_refusal(kind, cid, d, info, after, url, label, verb="revert")
        if needs:
            name, put_back = _picture_in_folder(cid, folder, name, copy_rel)
        rest = hist[:-1]
        if is_base:
            text = cio.set_top_block(src, "icon", name, [("before", "variants"), ("end", None)]) if name else (cio.del_top_block(src, "icon") if "icon" in d else src)
            if text is not None:
                text = cio.set_top_block(text, "icon_history", rest, [("after", "icon"), ("before", "variants"), ("end", None)]) if rest else (
                    cio.del_top_block(text, "icon_history") if "icon_history" in d else text)
            if text is not None and step is not None and "entry_icon" in step and isinstance(vs.get(base), dict):
                # the base entry named its own icon too (a base made from a look, pass 70): it gets its own back
                ei = os.path.basename(str(step.get("entry_icon") or ""))
                keep = ei if ei and os.path.isfile(os.path.join(folder, ei)) else name
                text = cio.set_variant_entry(text, base, {"icon": keep if keep else cio.REMOVE})
        else:
            prev_picked = bool(step.get("picked")) if step is not None else False
            update = {"icon": name if name else cio.REMOVE, "icon_picked": True if (name and prev_picked) else cio.REMOVE,
                      "icon_history": rest if rest else cio.REMOVE}
            text = cio.set_variant_entry(src, code, update)
        if text is None:
            return {"ok": False, "status": 400, "error": _layout_error(path, "the icon keys")}
        backup_rel = backup(cid, path)
        cio.write_atomic(path, text)
        d2 = json.loads(text)
    import_ok, output, job = _icon_import(kind, cid, put_back)
    now = look_icon_info(kind, cid, folder, d2, code)
    return {"ok": True, "op": "revert_icon", "kind": kind, "id": cid, "code": info["code"], "base": is_base, "was": info["shown"],
            "file": now["shown"], "put_back": put_back, "backup": backup_rel, "icon": now, "import_ok": import_ok, "output": output, "job": job}


def _gallery_ref(cid, full):
    """The gallery ref of a file under backups/<id>/ (backup/<f>), else of a folder file (folder/<f>)."""
    if full and os.path.dirname(os.path.abspath(full)) == os.path.abspath(icon_backup_dir(cid)):
        return "backup/" + os.path.basename(full)
    return "folder/" + os.path.basename(full or "")


def icon_ref_path(kind, cid, ref):
    """The file an icon_gallery ref names, or None: folder/<f> (the asset's folder: an <id>_icon*.png or a file its JSON
    names), backup/<f> (backups/<id>/), deleted/<stamp>/<f> (a removed look's, backups/deleted/<id>/<stamp>/) or
    legacy/<icons dir>/<f> (the older tools' copies, tools/dl/backup/icons*/): every part a plain name, a PNG."""
    tfolder, path = content_path(kind, cid)
    if path is None or not isinstance(ref, str):
        return None
    parts = ref.split("/")
    if any(not p or p.startswith(".") or not FILENAME_RE.match(p) for p in parts) or not parts[-1].lower().endswith(".png"):
        return None
    pat = _icon_name_re(cid)
    if parts[0] == "folder" and len(parts) == 2:
        if not (pat.match(parts[1]) or parts[1] in _named_icons(cid, _load_or_empty(path))):
            return None
        full = os.path.join(os.path.dirname(path), parts[1])
    elif parts[0] == "backup" and len(parts) == 2:
        full = os.path.join(icon_backup_dir(cid), parts[1])
    elif parts[0] == "deleted" and len(parts) == 3 and pat.match(parts[2]):
        full = os.path.join(BACKUPS, "deleted", cid, parts[1], parts[2])
    elif parts[0] == "legacy" and len(parts) == 3 and parts[1].startswith("icons") and pat.match(parts[2]):
        full = os.path.join(LEGACY_ICON_BACKUPS, parts[1], parts[2])
    else:
        return None
    return full if os.path.isfile(full) else None


def use_icon(kind, cid, code, ref, confirm=None):
    """"Use for this look" (pass 76, the gallery): the picture an icon_gallery ref names put on a look (code "" = the base):
    a folder file as it is; any other (a backup, a removed look's, an older tool's copy) put back into the folder first,
    under its own name or a fresh one (a folder file with the same bytes is used instead). Then set_look_icon (why "use
    <ref>"). The look in play and the base need confirm (asked before anything is copied); then the import."""
    if kind not in EDIT_KINDS:
        return {"ok": False, "status": 400, "error": "%s has no icon the editor sets" % kind}
    full = icon_ref_path(kind, cid, ref)
    if full is None:
        return {"ok": False, "status": 404, "error": "no icon %s of %s %s" % (ref, kind, cid)}
    tfolder, path = content_path(kind, cid)
    folder = os.path.dirname(path)
    code = str(code or "")
    d = _load_or_empty(path)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    if code and code != _base_code(kind, d) and code not in vs:
        return {"ok": False, "status": 404, "error": "%s has no look %s" % (cid, code)}
    info = look_icon_info(kind, cid, folder, d, code)
    where = ref.split("/", 1)[0]
    name = os.path.basename(full)
    same = ""
    if where != "folder":
        same = next((n for n in _folder_icon_names(cid, folder, d) if _same_bytes(os.path.join(folder, n), full)), "")
        name = same or name
    if confirm is not True and (info["played"] or info["base"]) and not (info["shown"] == name and (info["own"] or info["base"])):
        label = {"folder": "in %s's folder" % str(d.get("name") or cid), "backup": "a backup copy (put back into the folder)",
                 "deleted": "a removed look's file (put back into the folder)", "legacy": "an older tool's copy (put back into the folder)"}.get(where, ref)
        if where != "folder" and same:
            label = "in %s's folder (the same picture as this %s copy)" % (str(d.get("name") or cid), where)
        return _icon_refusal(kind, cid, d, info, name, "/iconfile/%s/%s/%s" % (kind, cid, ref), label, verb="use another")
    put_back = False
    if where != "folder" and not same:
        if os.path.exists(os.path.join(folder, name)) or os.path.exists(os.path.join(folder, name + ".import")):
            name = fresh_icon_name(folder, cid, "", os.path.splitext(name)[0][len(cid) + 6:] or "r")
        shutil.copy2(full, os.path.join(folder, name))
        put_back = True
    res = set_look_icon(kind, cid, code, name, "use %s" % ref, confirm=None)
    if not res.get("ok"):
        return res
    if res.get("unchanged") and not put_back:
        res.update(import_ok=None, output="no change: %s already shows %s" % (info["code"] or cid, name), job=None)
        return res
    import_ok, output, job = _icon_import(kind, cid, put_back)
    res.update(op="use_icon", put_back=put_back, import_ok=import_ok, output=output, job=job)
    return res


def icon_gallery(kind, cid):
    """GET /api/content/<kind>/<id>/icons (pass 76): every icon picture of an asset on disk, one tile per picture (copies
    with the same bytes are one tile, listed under `copies`): the folder's (_folder_icon_names), backups/<id>/ (the
    guard's copies), backups/deleted/<id>/<stamp>/ (removed looks') and the older tools' copies under
    tools/dl/backup/icons*/; each tile with the looks that show it (`used_by`); and every look's icon now
    (look_icon_info: the base first)."""
    if kind not in EDIT_KINDS:
        return {"ok": False, "status": 400, "error": "%s has no icons" % kind}
    tfolder, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "status": 404, "error": "no %s %s" % (kind, cid)}
    folder = os.path.dirname(path)
    d = _load_or_empty(path)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    base = _base_code(kind, d)
    codes = [base] + sorted((c for c in vs if c != base), key=lambda c: str(c))
    looks = [look_icon_info(kind, cid, folder, d, c) for c in codes]
    shown_by = {}
    for x in looks:
        shown_by.setdefault(x["shown"], []).append(x["code"])
    pat = _icon_name_re(cid)
    cands = [("folder/" + n, os.path.join(folder, n), "folder") for n in _folder_icon_names(cid, folder, d)]
    bdir = icon_backup_dir(cid)
    if os.path.isdir(bdir):
        cands += [("backup/" + n, os.path.join(bdir, n), "backup") for n in sorted(os.listdir(bdir))
                  if n.lower().endswith(".png") and FILENAME_RE.match(n) and os.path.isfile(os.path.join(bdir, n))]
    ddir = os.path.join(BACKUPS, "deleted", cid)
    if os.path.isdir(ddir):
        for stamp in sorted(os.listdir(ddir), reverse=True):
            sd = os.path.join(ddir, stamp)
            if os.path.isdir(sd) and FILENAME_RE.match(stamp):
                cands += [("deleted/%s/%s" % (stamp, n), os.path.join(sd, n), "deleted") for n in sorted(os.listdir(sd)) if pat.match(n)]
    if os.path.isdir(LEGACY_ICON_BACKUPS):
        for sub in sorted(os.listdir(LEGACY_ICON_BACKUPS)):
            sd = os.path.join(LEGACY_ICON_BACKUPS, sub)
            if sub.startswith("icons") and FILENAME_RE.match(sub) and os.path.isdir(sd):
                cands += [("legacy/%s/%s" % (sub, n), os.path.join(sd, n), "legacy") for n in sorted(os.listdir(sd)) if pat.match(n)]
    tiles, order = {}, []
    for ref, full, where in cands:
        try:
            st = os.stat(full)
            dg = _file_digest(full)
        except OSError:
            continue
        item = {"ref": ref, "where": where, "file": os.path.basename(full), "mtime": int(st.st_mtime), "size": st.st_size,
                "when": time.strftime("%Y-%m-%d %H:%M", time.localtime(st.st_mtime))}
        t = tiles.get(dg)
        if t is None:
            t = dict(item, digest=dg[:12], url="/iconfile/%s/%s/%s?v=%d" % (kind, cid, ref, int(st.st_mtime)), copies=[], used_by=[])
            tiles[dg] = t
            order.append(dg)
        else:
            t["copies"].append(item)
        if where == "folder":
            for c in shown_by.get(item["file"], []):
                if c not in t["used_by"]:
                    t["used_by"].append(c)
    return {"ok": True, "kind": kind, "id": cid, "name": str(d.get("name") or cid), "base": base,
            "play": icon_played_code(kind, cid, folder, d), "looks": looks, "files": [tiles[k] for k in order],
            "folder": rel(folder), "backups": rel(bdir)}


def icon_op(kind, cid, code, op, body=None):
    """POST /api/content/<kind>/<id>/icon {op: revert | use, code ("" = the base), ref (use), confirm} and the look ops
    revert_icon / use_icon {ref, confirm} (pass 76)."""
    body = body if isinstance(body, dict) else {}
    confirm = True if body.get("confirm") is True else False
    if op in ("revert", "revert_icon"):
        return revert_icon(kind, cid, code, confirm)
    if op in ("use", "use_icon"):
        return use_icon(kind, cid, code, str(body.get("ref") or ""), confirm)
    return {"ok": False, "status": 400, "error": "unknown icon op %s (revert or use)" % op}


def install_guard(job_id, body):
    """POST /api/jobs/<id>/install, an icon candidate (icon_cands, hero_badge) going on a look (pass 76): (status, body) of
    the refusal when it must wait (the look in play or the base without `confirm: true`: the page asks now -> new), else
    (None, the options jobs.install gets): the install's own new file (`icon_file`: the job form's named file when it is
    free, else fresh_icon_name; nothing is overwritten), the look (`icon_code`, "" = the base) and why. Anything else (a
    title cut-out, an unknown or unfinished job): (None, the options as sent)."""
    body = body if isinstance(body, dict) else {}
    sent = body.get("options") if isinstance(body.get("options"), dict) else (body.get("badge") if isinstance(body.get("badge"), dict) else None)
    options = dict(sent or {})
    st, got = jobs_call("get", job_id)
    src = got.get("job") if st == 200 and isinstance(got, dict) else None
    if not isinstance(src, dict) or src.get("kind") not in ("icon_cands", "hero_badge") or src.get("state") != "done":
        return None, sent
    t = src.get("target") or {}
    kind, cid = str(t.get("kind") or ("hero" if src["kind"] == "hero_badge" else "")), str(t.get("id") or "")
    tfolder, path = content_path(kind, cid)
    if path is None or kind not in EDIT_KINDS:
        return None, sent
    folder = os.path.dirname(path)
    d = _load_or_empty(path)
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    if "variant" in options:
        code = str(options.get("variant") or "").strip()
    elif src["kind"] == "hero_badge" and str((src.get("spec") or {}).get("variant") or "").strip():
        code = str(src["spec"]["variant"]).strip()
    else:
        code = str(t.get("code") or "")
    if code and code != _base_code(kind, d) and code not in vs:
        return None, sent
    info = look_icon_info(kind, cid, folder, d, code)
    choice = str(body.get("choice") if body.get("choice") is not None else "").strip()
    tag = re.sub(r"[^A-Za-z0-9]", "", str(src.get("id") or ""))[-4:]
    choices = [c for c in (src.get("choices") or []) if isinstance(c, dict)]
    # the Jobs tab and an item's candidates send the label ("c2"), the look picker the id ("2"): jobs.choice_id's rule
    ch = next((c for c in choices if str(c.get("id")) == choice), None) or next((c for c in choices if str(c.get("label")) == choice), None)
    choice = str(ch.get("id")) if ch else choice
    label = "%s of #%s" % ((ch or {}).get("label") or ("c" + choice), tag)
    named = os.path.basename(str(((src.get("plan") or {}).get("icon_job") or {}).get("file") or ""))
    if named and FILENAME_RE.match(named) and named.lower().endswith(".png") and not os.path.exists(os.path.join(folder, named)):
        new_name = named
    else:
        new_name = fresh_icon_name(folder, cid, "" if info["base"] else info["code"], "%s_c%s" % (tag, choice) if choice.isdigit() else tag)
    if (info["played"] or info["base"]) and body.get("confirm") is not True:
        ref = _icon_refusal(kind, cid, d, info, new_name, (ch or {}).get("url", ""), label, verb="install a new")
        ref["next"]["candidate"] = True
        ref["job"] = src.get("id")
        ref["choice"] = choice
        EV.emit("icon", "install_asks", job=src.get("id"), look=EV.look_of(kind, cid, info["code"]), choice=choice, file=new_name)   # pass 97 (lane PROGRESS)
        return ref.pop("status"), ref
    options.update(icon_file=new_name, icon_code="" if info["base"] else info["code"], why="install %s" % label)
    EV.emit("icon", "install_guard", job=src.get("id"), look=EV.look_of(kind, cid, info["code"]), choice=choice, file=new_name,   # pass 97 (lane PROGRESS)
            confirmed=body.get("confirm") is True)
    return None, options


# ---------------------------------------------------------------- the hooks jobs.py writes content through

class Hooks:
    """What jobs.py (lane J) calls to land a job's result in a content JSON (INTERFACES §4). One object; its methods are
    also reachable as items (`hooks["merge_look"]`), so either style works. jobs.py never imports server.py."""

    def __getitem__(self, name):
        return getattr(self, name)

    def get(self, name, default=None):
        return getattr(self, name, default)

    def content_path(self, kind, cid):
        return content_path(kind, cid)

    def snapshot_icons(self, kind, cid):
        """pass 76 (lane ICON): the asset's icons copied into backups/<id>/ before a job that may paint over one runs."""
        return snapshot_icons(kind, cid)

    def look_records(self, kind, cid):
        tfolder, path = content_path(kind, cid)
        if path is None or kind not in LOOK_KINDS:
            return []
        d = load_json(path)
        return look_records(kind, cid, os.path.dirname(path), d, path)

    def merge_look(self, kind, cid, code, entry, info=None):
        """The sidecar's `entry` ({sprite, icon, anims, strip_cols, fps, head}) merged over the existing entry (its note,
        recipe, shelved kept), `fresh: true`; a hero look takes `frame_px` from its recipe. The write: the whole-block
        rewrite when it changes only this entry's lines (the file is in dump style: layout "block"), else the entry
        surgery ("entry"), else nothing is written ("unmerged": ok false; the job ends done with that layout and the card
        offers Merge again / Re-dump)."""
        if kind not in LOOK_KINDS or not isinstance(entry, dict):
            return {"ok": False, "layout": "unmerged", "error": "merge_look: kind %s or entry %r" % (kind, type(entry).__name__)}
        tfolder, path = content_path(kind, cid)
        if path is None:
            return {"ok": False, "layout": "unmerged", "error": "no %s %s" % (kind, cid)}
        if not isinstance(code, str) or not CODE_RE.match(code):
            return {"ok": False, "layout": "unmerged", "error": "bad code %r" % (code,)}
        with _write_lock:
            src = cio.read_text(path)
            d = json.loads(src)
            text, base = _ensure_variants(src, kind, cid, d)
            if text is None:
                return {"ok": False, "layout": "unmerged", "error": _layout_error(path, base)}
            d = json.loads(text)
            vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
            existing = vs.get(code) if isinstance(vs.get(code), dict) else {}
            update = dict(entry)
            # pass 76 (lane ICON): a look whose icon was picked keeps it when a re-roll lands (the tools name their front
            # crop <id>_icon_<x>.png; a pick has had a file of its own since pass 76)
            if "icon" in update and existing.get("icon_picked") and existing.get("icon") and update["icon"] != existing["icon"] \
                    and resolve_file(os.path.dirname(path), str(existing["icon"])):
                update.pop("icon")
            if kind == "hero" and "frame_px" not in update and isinstance(existing.get("recipe"), dict) and existing["recipe"].get("frame_px"):
                update["frame_px"] = existing["recipe"]["frame_px"]
            if str((info or {}).get("pipeline") or "") not in ("frames_export", "frames_rollback"):
                update["fresh"] = True   # pass 95 resume (AN-09): a Frames export is Garry's own choice of frames, never a NEW look
            merged = cio.merge_entry(existing, update)
            t_entry = cio.set_variant_entry(text, code, update)
            new_vs = dict(vs)
            new_vs[code] = merged
            t_block = cio.set_top_block(text, "variants", new_vs)
            if t_entry is not None:
                layout = "block" if t_block == t_entry else "entry"
                out = t_entry
            elif t_block is not None and cio.diff_within_entry(text, t_block, code):
                layout, out = "block", t_block
            else:
                return {"ok": False, "layout": "unmerged", "file": rel(path), "keys": ["variants"],
                        "error": "neither the block write nor the entry write keeps %s's layout; Merge again after fixing the "
                                 "layout by hand, or Re-dump this file" % rel(path)}
            # pass 70: the base look's art is the top level's (JsonContent reads it for the base strip): a job landing on
            # a base whose entry names its own strip (a base made by removing the old one) mirrors it there
            keys = ["variants"]
            if code == str(d.get("variant_base", "")) and merged.get("sprite"):
                for k, v in base_art_top(kind, json.loads(out), merged).items():
                    t2 = cio.del_top_block(out, k) if v is cio.REMOVE else cio.set_top_block(out, k, v, [("before", "variants"), ("end", None)])
                    if t2 is None:
                        return {"ok": False, "layout": "unmerged", "file": rel(path), "keys": keys,
                                "error": "the base look %s's %s could not be mirrored to the top level: %s" % (code, k, _layout_error(path, k))}
                    out = t2
                    keys.append(k)
            backup_rel = backup(cid, path)
            cio.write_atomic(path, out)
            d2 = json.loads(out)
        # pass 95 (lane VACE): the landed strip's frames into the frames store (new cells become versions, selected
        # unless a human pinned the slot); never fails the landing
        frames_sync = FRIO.on_look_landed(kind, cid, code) if merged.get("sprite") else None
        return {"ok": True, "layout": layout, "file": rel(path), "keys": keys, "backup": backup_rel, "code": code,
                "base": base, "entry": d2["variants"][code], "frames": frames_sync}

    def merge_top(self, kind, cid, top):
        """A base run's top-level keys (anims, strip_cols, fps, head; art_prompt only when absent; a hero badge install's
        `badge`; an item icon roll's `art_prompt`), each written in place or added beside its neighbours; one backup."""
        if kind not in EDIT_KINDS or not isinstance(top, dict):
            return {"ok": False, "layout": "unmerged", "error": "merge_top: kind %s" % kind}
        tfolder, path = content_path(kind, cid)
        if path is None:
            return {"ok": False, "layout": "unmerged", "error": "no %s %s" % (kind, cid)}
        places = {"anims": [("after", "frame_px"), ("after", "drops"), ("before", "fps"), ("before", "variants"), ("end", None)],
                  "strip_cols": [("after", "anims"), ("after", "frame_px"), ("before", "variants"), ("end", None)],
                  "fps": [("after", "strip_cols"), ("after", "anims"), ("before", "variants"), ("end", None)],
                  "head": [("after", "fps"), ("after", "strip_cols"), ("before", "variants"), ("end", None)],
                  "art_prompt": [("after", "placeholder"), ("after", "flavour"), ("end", None)]}
        with _write_lock:
            src = cio.read_text(path)
            d = json.loads(src)
            text = src
            keys = []
            for k, v in top.items():
                if k == "art_prompt" and d.get("art_prompt"):
                    continue
                if k in d and d[k] == v:
                    continue
                text = cio.set_top_block(text, k, v, places.get(k, [("end", None)]))
                if text is None:
                    return {"ok": False, "layout": "unmerged", "error": _layout_error(path, k), "file": rel(path), "keys": keys}
                keys.append(k)
            if not keys:
                return {"ok": True, "layout": "block", "file": rel(path), "keys": [], "backup": "", "unchanged": True}
            backup_rel = backup(cid, path)
            cio.write_atomic(path, text)
        return {"ok": True, "layout": "block", "file": rel(path), "keys": keys, "backup": backup_rel}

    def set_recipe(self, kind, cid, code, recipe, note=None):
        """A look job's recipe (and note) written into its entry; the entry (and the variants block) created when missing."""
        if kind not in LOOK_KINDS:
            return {"ok": False, "error": "only enemies, bosses and heroes have looks"}
        tfolder, path = content_path(kind, cid)
        if path is None:
            return {"ok": False, "error": "no %s %s" % (kind, cid)}
        if not isinstance(code, str) or not CODE_RE.match(code):
            return {"ok": False, "error": "bad code %r" % (code,)}
        with _write_lock:
            src = cio.read_text(path)
            d = json.loads(src)
            text, base = _ensure_variants(src, kind, cid, d)
            if text is None:
                return {"ok": False, "error": _layout_error(path, base)}
            update = {"recipe": recipe if isinstance(recipe, dict) and recipe else cio.REMOVE}
            if note is not None:
                update["note"] = str(note)
            text = cio.set_variant_entry(text, code, update)
            if text is None:
                return {"ok": False, "error": _layout_error(path, "variants")}
            if text == src:
                return {"ok": True, "unchanged": True, "file": rel(path), "code": code}
            backup_rel = backup(cid, path)
            cio.write_atomic(path, text)
        return {"ok": True, "file": rel(path), "keys": ["variants"], "backup": backup_rel, "code": code}

    def merge_recipe(self, kind, cid, code, update):
        """pass 70 (the pick race): only `update`'s keys merged into the look's recipe as the file holds it now (a key
        whose value is None is removed), under the write lock, one backup; nothing written when nothing changes. A
        front-from-a-picture pick names its slug this way, so a recipe written meanwhile (a look job queued before the
        pick landed) keeps its words. The look's entry must exist."""
        if kind not in LOOK_KINDS:
            return {"ok": False, "error": "only enemies, bosses and heroes have looks"}
        tfolder, path = content_path(kind, cid)
        if path is None:
            return {"ok": False, "error": "no %s %s" % (kind, cid)}
        if not isinstance(code, str) or not CODE_RE.match(code) or not isinstance(update, dict):
            return {"ok": False, "error": "bad code %r or update" % (code,)}
        prob = VOCAB.stills_problem(update.get("stills") or None) if "stills" in update else None
        if prob:
            return {"ok": False, "error": "recipe.stills: " + prob}
        with _write_lock:
            src = cio.read_text(path)
            d = json.loads(src)
            vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
            if not isinstance(vs.get(code), dict):
                return {"ok": False, "error": "%s has no look %s" % (cid, code)}
            cur = vs[code].get("recipe") if isinstance(vs[code].get("recipe"), dict) else {}
            merged = dict(cur)
            for k, v in update.items():
                if v is None:
                    merged.pop(k, None)
                else:
                    merged[k] = v
            if merged == cur:
                return {"ok": True, "unchanged": True, "file": rel(path), "code": code, "keys": []}
            text = cio.set_variant_entry(src, code, {"recipe": merged if merged else cio.REMOVE})
            if text is None:
                return {"ok": False, "error": _layout_error(path, "variants")}
            backup_rel = backup(cid, path)
            cio.write_atomic(path, text)
        return {"ok": True, "file": rel(path), "keys": ["variants"], "backup": backup_rel, "code": code, "recipe": merged}

    def set_look_files(self, kind, cid, code, files, meta=None):
        """pass 68 (D8): a candidate picked for a look lands in its entry: {"icon": "<id>_icon_<x>.png"} (a badge or an
        icon beside the JSON) and/or {"title": "hero_<id>_<x>.png"} (a hero's title cut-out under art/ui/wanted/). The
        entry is edited in place (content_io's entry writer), with a backup; no `fresh` (the strip is not touched) and no
        import here (the job queues one). The look must exist: a pick never creates an entry. Pass 73 (lane CARDS): a
        card's look (ITEM_LOOK_KINDS) takes its icon the same way. Pass 76 (lane ICON): the icon goes through
        set_look_icon, the one place an icon changes (the look's icon_history, a copy of the icon it replaces under
        backups/<id>/; code "" or the base's own: the top-level icon, for any asset); `meta` {why} is the step's reason."""
        if isinstance(files, dict) and "icon" in files and set(files) <= {"icon", "title"}:
            why = str(meta.get("why") or "") if isinstance(meta, dict) else ""
            r = set_look_icon(kind, cid, code if isinstance(code, str) else "", str(files.get("icon") or ""), why, confirm=None, need_file=False)
            r.pop("status", None)
            r["layout"] = r.get("layout", "entry") if r.get("ok") else "unmerged"
            r["keys"] = ["icon", "icon_history"] if r.get("base") else ["variants"]
            if not r.get("ok") or "title" not in files:
                return r
            files = {"title": files["title"]}
        if kind not in LOOK_KINDS and not (kind in ITEM_LOOK_KINDS and set(files or {}) <= {"icon"}):
            return {"ok": False, "layout": "unmerged", "error": "only enemies, bosses, heroes and cards have looks"}
        tfolder, path = content_path(kind, cid)
        if path is None:
            return {"ok": False, "layout": "unmerged", "error": "no %s %s" % (kind, cid)}
        if not isinstance(code, str) or not CODE_RE.match(code):
            return {"ok": False, "layout": "unmerged", "error": "bad code %r" % (code,)}
        if not isinstance(files, dict) or not files or any(k not in ("icon", "title") for k in files):
            return {"ok": False, "layout": "unmerged", "error": "set_look_files takes {icon?, title?}: %r" % (files,)}
        update = {}
        for k, v in files.items():
            name = str(v or "")
            if not FILENAME_RE.match(name) or name.startswith("."):
                return {"ok": False, "layout": "unmerged", "error": "%s must be a plain file name (got %r)" % (k, name)}
            if k == "title" and kind != "hero":
                return {"ok": False, "layout": "unmerged", "error": "a title cut-out is a hero's"}
            update[k] = name
        if "icon" in update:
            # the lead, pass 68: a picked icon is kept by the look's later runs (gen_art paints a creature look's icon
            # from its front still on every run and would paint over the pick)
            update["icon_picked"] = True
        with _write_lock:
            src = cio.read_text(path)
            d = json.loads(src)
            vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
            if code not in vs:
                return {"ok": False, "layout": "unmerged", "error": "%s has no look %s (removed while the job ran?)" % (cid, code)}
            if all(isinstance(vs[code], dict) and vs[code].get(k) == v for k, v in update.items()):
                return {"ok": True, "layout": "entry", "file": rel(path), "keys": ["variants"], "backup": "", "code": code,
                        "unchanged": True, "entry": vs[code]}
            text = cio.set_variant_entry(src, code, update)
            if text is None:
                return {"ok": False, "layout": "unmerged", "file": rel(path), "keys": ["variants"], "error": _layout_error(path, "variants")}
            # pass 70: a base whose entry names its own strip shows its icon from the top level (merge_look's mirror)
            if code == str(d.get("variant_base", "")) and vs[code].get("sprite") and "icon" in update and d.get("icon") != update["icon"]:
                t2 = cio.set_top_block(text, "icon", update["icon"], [("before", "variants"), ("end", None)])
                if t2 is None:
                    return {"ok": False, "layout": "unmerged", "file": rel(path), "keys": ["variants", "icon"], "error": _layout_error(path, "icon")}
                text = t2
            backup_rel = backup(cid, path)
            cio.write_atomic(path, text)
            d2 = json.loads(text)
        return {"ok": True, "layout": "entry", "file": rel(path), "keys": ["variants"], "backup": backup_rel, "code": code,
                "entry": d2["variants"][code]}

    def redump_merge(self, kind, cid, code, entry):
        """Garry's explicit "Re-dump this file (changes its layout)": the entry merged, the whole file dumped again with
        its indent unit, line ending and final newline. Never called on its own."""
        if kind not in LOOK_KINDS or not isinstance(entry, dict):
            return {"ok": False, "layout": "unmerged", "error": "redump_merge: kind %s" % kind}
        tfolder, path = content_path(kind, cid)
        if path is None:
            return {"ok": False, "layout": "unmerged", "error": "no %s %s" % (kind, cid)}
        with _write_lock:
            src = cio.read_text(path)
            d = json.loads(src)
            vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
            if not vs:
                base = str(d.get("variant_base", "")) or "%s-%s" % (code_prefix(kind, cid, d), "A" if kind == "hero" else "0")
                d["variant_base"] = base
                vs = {base: {"note": "the top-level strip, before the Level Editor's looks"}}
            existing = vs.get(code) if isinstance(vs.get(code), dict) else {}
            vs[code] = cio.merge_entry(existing, dict(entry, fresh=True))
            d["variants"] = vs
            backup_rel = backup(cid, path)
            cio.write_atomic(path, cio.redump(src, d))
        return {"ok": True, "layout": "redumped", "file": rel(path), "keys": ["variants"], "backup": backup_rel, "code": code}


HOOKS = Hooks()


# ---------------------------------------------------------------- jobs.py (lane J), lazily

def jobs_module():
    """jobs.py when it is here (or the test stand-in `JOBS`); None otherwise, with the import error kept for the reply."""
    if JOBS is not None:
        return JOBS
    try:
        import jobs as m  # noqa: F401
        return m
    except ImportError:
        _jobs_error[0] = "the jobs module is not here yet"
        return None
    except Exception as e:  # a half-written jobs.py must not kill the editor
        _jobs_error[0] = "jobs.py could not be imported: %s: %s" % (type(e).__name__, e)
        return None


def _enqueue(kind, target, spec, title=None):
    """{job} or {job: None, error}: never raises (a create or a save must not fail because the queue is not there)."""
    m = jobs_module()
    if m is None:
        return {"job": None, "error": _jobs_error[0] or "the jobs module is not here yet"}
    try:
        return {"job": m.enqueue(kind, target, spec, title)}
    except Exception as e:
        return {"job": None, "error": "%s: %s" % (type(e).__name__, e)}


def jobs_call(name, *args, **kw):
    """(status, body) of one jobs.py call: a bad body is a 400, an unknown job a 404, a state the call does not allow a 409."""
    m = jobs_module()
    if m is None:
        return 503, {"ok": False, "error": _jobs_error[0] or "the jobs module is not here yet"}
    fn = getattr(m, name, None)
    if fn is None:
        return 501, {"ok": False, "error": "jobs.%s is not implemented" % name}
    try:
        result = fn(*args, **kw)
    except ValueError as e:
        return 400, {"ok": False, "error": str(e)}
    except (KeyError, LookupError) as e:
        return 404, {"ok": False, "error": "no such job: %s" % e}
    except Exception as e:
        return 409, {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
    if name in ("enqueue", "edit", "cancel", "requeue", "pick", "install", "move", "get", "merge", "push_workflows"):
        if result is None:
            return 404, {"ok": False, "error": "no such job"}
        return 200, {"ok": True, "job": result}
    if isinstance(result, dict):
        out = dict(result)
        out.setdefault("ok", True)
        return 200, out
    return 200, {"ok": True, "result": result}


# ---------------------------------------------------------------- status

_qa_cache = [0.0, None]


def qa_online(max_age=15.0):
    """Whether LM Studio (the vision QA) answers on 127.0.0.1:1234; cached; a connection refused is immediate."""
    now = time.time()
    if now - _qa_cache[0] < max_age:
        return _qa_cache[1]
    import urllib.request
    try:
        with urllib.request.urlopen(QA_URL, timeout=0.8) as r:
            ok = 200 <= r.status < 300
    except Exception:
        ok = False
    _qa_cache[0], _qa_cache[1] = now, ok
    return ok


def blender_path():
    """env BLENDER, else %LOCALAPPDATA%/Programs/blender-*/blender.exe, else C:/Program Files/Blender Foundation/Blender */blender.exe."""
    env = os.environ.get("BLENDER", "")
    if env and os.path.isfile(env):
        return env.replace("\\", "/")
    cands = []
    local = os.environ.get("LOCALAPPDATA", "")
    if local:
        cands += glob.glob(os.path.join(local, "Programs", "blender-*", "blender.exe"))
    cands += glob.glob("C:/Program Files/Blender Foundation/Blender */blender.exe")
    cands = sorted(cands)
    return cands[-1].replace("\\", "/") if cands else None


def _still_url(key):
    p = os.path.join(DL, "ai_raw_anime", key + ".png")
    return ("/dl/ai_raw_anime/%s.png?v=%d" % (key, int(os.path.getmtime(p)))) if os.path.isfile(p) else None


def _played_screen(doc, vs, played):
    """The screen of the look he is played in (its recipe's), else the hero's own; None when neither names one."""
    e = vs.get(played) if isinstance(vs.get(played), dict) else {}
    r = e.get("recipe") if isinstance(e.get("recipe"), dict) else {}
    return str(r.get("screen") or doc.get("screen") or "") or None


def puppet_record(hid):
    """GET /api/puppet/<hero> (pass 71, lane PLE): the hero's puppet (tools/dl/puppet/<hero>/): the GLB (+ its clips as
    stages.json recorded them), the preview, the .blend, which stages are on disk, the guides made from it (tools/dl/
    drivers/<hero>_puppet_*: framing, clip, silhouette); and what the job form offers: every look's stills (the 3D
    reference picker: any look's front, side and back), the look he is played in, the Mixamo clips on disk, the screen."""
    tf, path = content_path("hero", hid)
    if path is None:
        return {"ok": False, "error": "no hero %s" % hid}
    try:
        doc = load_json(path)
    except (OSError, ValueError) as e:
        return {"ok": False, "error": "%s.json: %s" % (hid, e)}
    d = os.path.join(PUPPET_DIR, hid)

    def url(name):
        f = os.path.join(d, name)
        return ("/dl/puppet/%s/%s?v=%d" % (hid, name.replace(os.sep, "/"), int(os.path.getmtime(f)))) if os.path.isfile(f) else None
    state = {}
    try:
        state = load_json(os.path.join(d, "stages.json"))
    except (OSError, ValueError):
        state = {}
    glb = os.path.join(d, "%s_puppet.glb" % hid)
    files = {k: url(n) for k, n in (("apose_front", "apose_front.png"), ("apose_side", "apose_side.png"), ("apose_back", "apose_back.png"),
                                     ("shape_preview", "shape_preview_front.png" if os.path.isfile(os.path.join(d, "shape_preview_front.png")) else "shape_preview.png"),
                                     ("rig_front", os.path.join("rig", "rig_front.png")),
                                     ("bendtest", os.path.join("rig", "bendtest.png")), ("preview", "%s_puppet_preview.png" % hid),
                                     ("front_sheet", os.path.join("apose", "front_sheet.png")))}
    stages = {"apose": os.path.isfile(os.path.join(d, "apose_front.png")), "shape": os.path.isfile(os.path.join(d, "shape.glb")),
              "rig": os.path.isfile(os.path.join(d, "%s_puppet.blend" % hid)), "anim": os.path.isfile(glb)}
    guides = []
    if os.path.isdir(DRIVERS):
        for name in sorted(os.listdir(DRIVERS)):
            if not name.startswith(hid + "_puppet_") or "_depth" in name or "_old" in name or "_v1_" in name:
                continue
            mp = os.path.join(DRIVERS, name, "meta.json")
            if not os.path.isfile(mp):
                continue
            try:
                m = load_json(mp)
            except (OSError, ValueError):
                m = {}
            sil = os.path.join(DRIVERS, name, "silhouette.json")
            if not os.path.isfile(sil) and name == hid + "_puppet_run" and os.path.isfile(os.path.join(d, "silhouette.json")):
                sil = os.path.join(d, "silhouette.json")
            ratios = {}
            try:
                ratios = {v: (r or {}).get("ratio_median") for v, r in load_json(sil).items()} if os.path.isfile(sil) else {}
            except (OSError, ValueError, AttributeError):
                ratios = {}
            guides.append({"name": name, "frame": m.get("frame", "ankles"), "clip": m.get("clip") or "tools/dl/mixamo/running.fbx",
                           "depth": name + "_depth" if os.path.isdir(os.path.join(DRIVERS, name + "_depth")) else None,
                           "silhouette": rel(sil) if os.path.isfile(sil) else None, "ratios": ratios,
                           "sheet": "/dl/drivers/%s/all_sheet.png" % name if os.path.isfile(os.path.join(DRIVERS, name, "all_sheet.png")) else None,
                           "mtime": mtime_of(mp)})
    vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    played = str(doc.get("variant") or doc.get("variant_base") or "")
    looks = []
    for code, e in vs.items():
        if not isinstance(e, dict):
            continue
        r = e.get("recipe") if isinstance(e.get("recipe"), dict) else {}
        slug = str(r.get("stills") or "")
        sk = r.get("still_keys") if isinstance(r.get("still_keys"), dict) else {}
        stills = {}
        for v in ("front", "side", "back", "fd", "bd"):
            key = str(sk.get(v) or "%s%s_%s" % (hid, "_" + slug if slug else "", v))
            u = _still_url(key)
            if u:
                stills[v] = {"key": key, "url": u}
        looks.append({"code": code, "slug": slug, "stills": stills, "played": code == played, "shelved": bool(e.get("shelved")),
                      "has_strip": bool(e.get("sprite")) or code == doc.get("variant_base"), "method": r.get("method") or ""})
    if not any(lk["code"] == played for lk in looks):
        # the hero's own paintings (<id>_<view>): a hero without looks, or a base strip the variants do not list
        own = {v: {"key": "%s_%s" % (hid, v), "url": _still_url("%s_%s" % (hid, v))} for v in ("front", "side", "back", "fd", "bd")}
        own = {v: x for v, x in own.items() if x["url"]}
        if own:
            looks.insert(0, {"code": played, "slug": "", "stills": own, "played": True, "shelved": False, "has_strip": True, "method": "", "own": True})
    clips = sorted(f for f in os.listdir(MIXAMO_DIR) if f.lower().endswith(".fbx")) if os.path.isdir(MIXAMO_DIR) else []
    anim = state.get("anim") if isinstance(state.get("anim"), dict) else {}
    return {"ok": True, "hero": hid, "name": doc.get("name") or hid, "dir": rel(d), "exists": os.path.isdir(d),
            "glb": url("%s_puppet.glb" % hid), "glb_file": rel(glb) if os.path.isfile(glb) else None,
            "glb_mtime": mtime_of(glb), "blend": rel(os.path.join(d, "%s_puppet.blend" % hid)) if stages["rig"] else None,
            "clip": anim.get("clip") or ("tools/dl/mixamo/running.fbx" if stages["anim"] else None), "idle": anim.get("idle") or ("procedural" if stages["anim"] else None),
            "files": files, "stages": stages, "guides": guides, "looks": looks, "played": played, "clips": clips,
            "screen": _played_screen(doc, vs, played),
            "picks": (state.get("apose") or {}).get("picks"),
            "rig_howto": rel(os.path.join(DL, "puppet", "may", "RIG_HOWTO.md")) if os.path.isfile(os.path.join(DL, "puppet", "may", "RIG_HOWTO.md")) else None}


def status_record():
    m = jobs_module()
    jobs = None
    if m is not None:
        try:
            jobs = m.status()
        except Exception as e:
            jobs = {"error": "%s: %s" % (type(e).__name__, e)}
    lk = locks.status_all()
    qa = jobs.get("qa_online") if isinstance(jobs, dict) and jobs.get("qa_online") is not None else qa_online()
    return _safe_status({"ok": True, "root": ROOT, "godot": os.path.isfile(GODOT), "backups": BACKUPS, "content": CONTENT,
            "blender": blender_path(), "qa_online": qa, "locks": lk, "comfy": lk.get("comfy"), "godot_lock": lk.get("godot"),
            "jobs": jobs, "jobs_available": m is not None, "jobs_error": _jobs_error[0] if m is None else "",
            "methods": os.path.isfile(METHODS), "new_weapon_starts_hidden": NEW_WEAPON_STARTS_HIDDEN,
            # whether the ComfyUI page has the 88fits_open extension (the "open in ComfyUI" links need it)
            "comfy_open_ext": (m.comfy_extension_state() if m is not None and hasattr(m, "comfy_extension_state") else None)}, m)


# ---------------------------------------------------------------- drivers, refs, methods

def list_drivers():
    """Pass 93 (lane PREVIEW): drivers_io.list_drivers (every folder with frames, meta.json or not; real frame counts,
    stills, used_by, the folder path; the keys the pass 66 listing had are kept)."""
    return DRVIO.list_drivers(DRIVERS, CONTENT)


def _slug(name):
    stem = os.path.splitext(name)[0].lower()
    stem = re.sub(r"[^a-z0-9]+", "_", stem).strip("_")
    return stem or "upload"


def list_refs():
    """tools/dl/uploads: {"2d": [{name, url, size, mtime}], "3d": [{slug, file, size, mtime, probe, renders}]}."""
    out = {"2d": [], "3d": []}
    d2 = os.path.join(UPLOADS, "2d")
    if os.path.isdir(d2):
        for f in sorted(os.listdir(d2)):
            full = os.path.join(d2, f)
            if os.path.isfile(full) and f.lower().endswith(UPLOAD_EXTS["2d"]):
                out["2d"].append({"name": f, "url": "/dl/uploads/2d/%s" % f, "path": rel(full), "size": os.path.getsize(full),
                                  "mtime": int(os.path.getmtime(full))})
    d3 = os.path.join(UPLOADS, "3d")
    # pass 92 (lane SPIDER): a model dropped into uploads/3d by hand (spider._low_poly.glb, the raptor, the ant) has no
    # folder of its own and was never listed; it is listed now under its slug, its probe and renders in uploads/3d/<slug>/
    loose = loose_models(d3)
    if os.path.isdir(d3):
        for slug in sorted(os.listdir(d3)):
            folder = os.path.join(d3, slug)
            if not os.path.isdir(folder):
                continue
            files = [f for f in os.listdir(folder) if os.path.isfile(os.path.join(folder, f))]
            model = next((f for f in sorted(files) if f.lower().endswith(UPLOAD_EXTS["3d"])), None)
            if model is None and slug in loose:
                continue   # the probe folder of a loose model: listed with it below
            probe = None
            if os.path.isfile(os.path.join(folder, "probe.json")):
                try:
                    probe = load_json(os.path.join(folder, "probe.json"))
                except (OSError, ValueError):
                    probe = {"error": "probe.json is not valid JSON"}
            renders = ["/dl/uploads/3d/%s/%s" % (slug, f) for f in sorted(files) if f.lower().endswith((".png", ".jpg", ".webp"))]
            out["3d"].append({"slug": slug, "file": model, "path": rel(os.path.join(folder, model)) if model else None,
                              "size": os.path.getsize(os.path.join(folder, model)) if model else 0,
                              "mtime": int(os.path.getmtime(folder)), "probe": probe, "renders": renders})
        for slug, name in sorted(loose.items()):
            full = os.path.join(d3, name)
            folder = os.path.join(d3, slug)
            probe = None
            if os.path.isfile(os.path.join(folder, "probe.json")):
                try:
                    probe = load_json(os.path.join(folder, "probe.json"))
                except (OSError, ValueError):
                    probe = {"error": "probe.json is not valid JSON"}
            files = sorted(os.listdir(folder)) if os.path.isdir(folder) else []
            renders = ["/dl/uploads/3d/%s/%s" % (slug, f) for f in files if f.lower().endswith((".png", ".jpg", ".webp"))]
            out["3d"].append({"slug": slug, "file": name, "path": rel(full), "size": os.path.getsize(full),
                              "mtime": int(os.path.getmtime(full)), "probe": probe, "renders": renders, "loose": True})
    return out


def loose_models(d3):
    """{slug: file name} of the model files lying in uploads/3d itself (not in a folder of their own). A slug a folder
    with its own model already has gets a _loose suffix."""
    out = {}
    if not os.path.isdir(d3):
        return out
    for name in sorted(os.listdir(d3)):
        full = os.path.join(d3, name)
        if not os.path.isfile(full) or not name.lower().endswith(UPLOAD_EXTS["3d"]) or name.lower().endswith(".zip"):
            continue
        slug = _slug(name)
        folder = os.path.join(d3, slug)
        if os.path.isdir(folder) and any(f.lower().endswith(UPLOAD_EXTS["3d"]) for f in os.listdir(folder)):
            slug += "_loose"
        out[slug] = name
    return out


def methods_table():
    """tools/level_editor/methods.json (lane B), or {methods: []} so the page still loads without it."""
    if not os.path.isfile(METHODS):
        return {"ok": True, "methods": [], "missing": True}
    try:
        d = load_json(METHODS)
    except (OSError, ValueError) as e:
        return {"ok": True, "methods": [], "error": "methods.json: %s" % e}
    if isinstance(d, dict):
        d.setdefault("ok", True)
        d.setdefault("methods", [])
        return d
    return {"ok": True, "methods": d if isinstance(d, list) else []}


def dl_path(relpath):
    """The file under tools/dl a /dl/<rel> request may read, or None: a known root, an allowed extension, normpath
    inside tools/dl. A directory is returned as a directory (the route lists it)."""
    parts = [p for p in relpath.replace("\\", "/").split("/") if p]
    if not parts:
        return None
    root = parts[0]
    # pass 68: a top-level 3D render (tools/dl/<x>_ref.png, the Blender scripts' icon references) is a candidate job's
    # reference picture, shown as the form's thumbnail
    ref_render = len(parts) == 1 and root.lower().endswith("_ref.png")
    if root not in DL_ROOTS and not root.startswith("icons") and not ref_render:
        return None
    if root == "uploads":
        # the uploads folder is its own global (the selftest points it elsewhere)
        base = os.path.normpath(UPLOADS)
        full = os.path.normpath(os.path.join(UPLOADS, *parts[1:]))
    else:
        base = os.path.normpath(DL)
        full = os.path.normpath(os.path.join(DL, *parts))
    if not (full == base or full.startswith(base + os.sep)):
        return None
    if os.path.isdir(full):
        return full
    if not os.path.isfile(full) or os.path.splitext(full)[1].lower() not in DL_EXTS:
        return None
    return full


def sound_path(sid):
    """content/sounds/<file> of a sound id in soundmap.json."""
    if not re.match(r"^[a-z0-9_]+$", sid or ""):
        return None
    try:
        sounds = load_json(os.path.join(CONTENT, "sounds", "soundmap.json")).get("sounds", {})
    except (OSError, ValueError, AttributeError):
        return None
    row = sounds.get(sid) if isinstance(sounds, dict) else next((r for r in sounds if isinstance(r, dict) and r.get("id") == sid), None)
    if not isinstance(row, dict) or not row.get("file"):
        return None
    full = os.path.normpath(os.path.join(CONTENT, "sounds", str(row["file"]).replace("/", os.sep)))
    base = os.path.normpath(os.path.join(CONTENT, "sounds"))
    if not full.startswith(base + os.sep) or not os.path.isfile(full):
        return None
    return full


# ---------------------------------------------------------------- the kill rate from Garry's run records (pass 57)

ANALYTICS_RUNS = os.path.join(ROOT, "analytics", "runs")
# what the "Spawned so far" lane assumes with no record to learn from: 6 % of the crowd killed a second (an average
# creature lives about 17 s), a 60 s boss fight and a 30 s portal wait
TURNOVER_FALLBACK = {"turnover": 0.06, "boss_seconds": 60.0, "portal_seconds": 30.0}
# a minute of the run clock joins the curve when the pooled records hold this many seconds of it
CURVE_MIN_SECONDS = 30
# a stage gets its own number when the pooled records hold this many seconds of it (else the stage before's)
STAGE_MIN_SECONDS = 60
# only the latest runs speak for the game as it is now (the file names are the runs' start times, so they sort in time)
FIT_MAX_RUNS = 12
_run_cache = {}  # path -> (mtime, size, summary or None)


def run_summary(path):
    """What the kill-rate fit needs from one run record (analytics/SCHEMA.md), or None when it cannot be used: the header
    (map, hero, version, result, length, headless), per second of the normal phase the run clock, the stage, the kills
    and the creatures alive (alive_by, which leaves out the dying), the boss fights' lengths (boss_start to boss_end, in
    play seconds) and the portal waits' (boss_end to the portal). A record whose clock runs ahead of its play time (a tool
    that jumped the clock) is not a run as played. Cached by modification time and size."""
    try:
        st = os.stat(path)
    except OSError:
        return None
    hit = _run_cache.get(path)
    if hit and hit[0] == st.st_mtime and hit[1] == st.st_size:
        return hit[2]
    out = None
    try:
        d = load_json(path)
    except (OSError, ValueError):
        d = None
    if isinstance(d, dict) and isinstance(d.get("samples"), list):
        rows = []
        jumped = False
        for r in d["samples"]:
            if not isinstance(r, dict):
                continue
            t, clock = float(r.get("t", 0) or 0), float(r.get("clock", 0) or 0)
            if clock > t + 3.0:
                jumped = True
                break
            if int(r.get("phase", 0) or 0) != 0:
                continue
            living = r.get("alive_by")
            if not isinstance(living, dict):
                continue
            killed = r.get("killed") if isinstance(r.get("killed"), dict) else {}
            rows.append((clock, int(r.get("stage", 1) or 1), float(sum(killed.values())), float(sum(living.values()))))
        fights, waits = [], []
        start = end = None
        for e in d.get("events", []) if isinstance(d.get("events"), list) else []:
            if not isinstance(e, dict):
                continue
            kind, t = e.get("kind"), float(e.get("t", 0) or 0)
            if kind == "boss_start":
                start, end = t, None
            elif kind == "boss_end" and start is not None:
                fights.append(t - start)
                start, end = None, t
            elif kind == "portal" and end is not None:
                waits.append(t - end)
                end = None
        if not jumped:
            out = {"file": os.path.basename(path), "map": str(d.get("map", "")), "hero": str(d.get("hero", "")),
                   "version": str(d.get("version", "")), "result": str(d.get("result", "")),
                   "length": float(d.get("length", 0) or 0), "headless": bool(d.get("headless", False)),
                   "rows": rows, "fights": fights, "waits": waits}
    _run_cache[path] = (st.st_mtime, st.st_size, out)
    return out


def fit_turnover(map_id, include_headless=False, runs_dir=None):
    """The "Spawned so far" lane's assumptions from the run records under analytics/runs (the local recorder's files,
    pass 45): the share of the living crowd the hero kills a second (kills over creatures alive, normal phase only,
    pooled over the latest FIT_MAX_RUNS runs of the map), as one number, per stage (a stage with under
    STAGE_MIN_SECONDS of records takes the stage before's) and minute by minute of the run clock (the curve the lane
    plays: a hero kills slowly while his build is young), the mean boss fight and the mean portal wait. Only Garry's own
    runs count unless `include_headless`: a headless record is a tool's bot. A run counts with a minute or more of the
    normal phase, played as it came (no jumped clock). With nothing to learn from, the fallback numbers and
    `source: "fallback"`."""
    base = runs_dir or ANALYTICS_RUNS
    used, fights, waits = [], [], []
    by_min, by_stage = {}, {}
    k_all = a_all = 0.0
    # pass 74: tool runs (headless or started with --script) are kept apart in analytics/runs/tools/
    dirs = [base] + ([os.path.join(base, "tools")] if include_headless else [])
    entries = sorted((n, os.path.join(d, n)) for d in dirs if os.path.isdir(d) for n in os.listdir(d))
    picked = []
    for name, path in reversed(entries):
        if len(picked) >= FIT_MAX_RUNS:
            break
        if not name.endswith(".json") or name.startswith("index"):
            continue
        s = run_summary(path)
        if not s or s["map"] != map_id or (s["headless"] and not include_headless) or len(s["rows"]) < 60:
            continue
        picked.append(s)
    for s in reversed(picked):
        k_run = a_run = 0.0
        for clock, stage, k, a in s["rows"]:
            m = int(clock // 60)
            b = by_min.setdefault(m, [0.0, 0.0, 0])
            b[0] += k
            b[1] += a
            b[2] += 1
            g = by_stage.setdefault(stage, [0.0, 0.0, 0])
            g[0] += k
            g[1] += a
            g[2] += 1
            k_run += k
            a_run += a
        k_all += k_run
        a_all += a_run
        fights += s["fights"]
        waits += s["waits"]
        used.append({"file": s["file"], "hero": s["hero"], "version": s["version"], "result": s["result"],
                     "length": round(s["length"], 1), "seconds": len(s["rows"]),
                     "turnover": round(k_run / a_run, 4) if a_run > 0 else None})
    fb = dict(TURNOVER_FALLBACK)
    if not used or a_all <= 0:
        return {"ok": True, "map": map_id, "source": "fallback", "runs": [], "turnover": fb["turnover"],
                "by_stage": [], "curve": [], "boss_seconds": fb["boss_seconds"], "portal_seconds": fb["portal_seconds"],
                "fights": 0, "waits": 0, "fallback": fb}
    flat = k_all / a_all
    stages = []
    prev = flat
    for st in range(1, (max(by_stage) if by_stage else 1) + 1):
        g = by_stage.get(st)
        if g and g[2] >= STAGE_MIN_SECONDS and g[1] > 0:
            prev = g[0] / g[1]
        stages.append(round(prev, 4))
    curve = [[m * 60 + 30, round(b[0] / b[1], 4)] for m, b in sorted(by_min.items()) if b[2] >= CURVE_MIN_SECONDS and b[1] > 0]
    return {"ok": True, "map": map_id, "source": "records", "runs": used, "turnover": round(flat, 4), "by_stage": stages,
            "curve": curve,
            "boss_seconds": round(sum(fights) / len(fights), 1) if fights else fb["boss_seconds"],
            "portal_seconds": round(sum(waits) / len(waits), 1) if waits else fb["portal_seconds"],
            "fights": len(fights), "waits": len(waits), "fallback": fb}


# ---------------------------------------------------------------- the handler

# GETs that are polled or fetched by the dozen say nothing in the console (pass 66)
QUIET_PREFIXES = ("/api/jobs", "/api/job/", "/api/status", "/dl/", "/icon/", "/sprite/", "/art/", "/examples/", "/sound/", "/api/sim/", "/api/requests")   # pass 96: the request folds are polled too
QUIET_PREFIXES += ("/api/events", "/api/ops", "/api/eyes")   # pass 97 (lane PROGRESS): the look card's history and the Ops fold are polled too


class Handler(BaseHTTPRequestHandler):
    server_version = "88fits-level-editor/1.0"

    def log_message(self, fmt, *args):
        # one quiet line per API call; the page's files, the pictures and the polls say nothing
        if self.path.startswith("/api/") and not (self.command == "GET" and self.path.startswith(QUIET_PREFIXES)):
            sys.stdout.write("%s %s\n" % (self.command, self.path))
            sys.stdout.flush()

    def _send(self, code, body, ctype="application/json; charset=utf-8", cache="no-store"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)

    def _error(self, code, msg, **extra):
        body = {"ok": False, "error": msg}
        body.update(extra)
        self._send(code, body)

    def _result(self, result):
        """A content op's dict: its `status` (default 200 when ok, 400 when not) decides the HTTP code."""
        status = result.pop("status", None) if isinstance(result, dict) else None
        if status is None:
            status = 200 if result.get("ok") else 400
        self._send(status, result)

    def _file(self, full, ctype=None, cache="max-age=60"):
        ext = os.path.splitext(full)[1].lower()
        ctype = ctype or FILE_TYPES.get(ext, "application/octet-stream")
        with open(full, "rb") as f:
            data = f.read()
        self._send(200, data, ctype, cache)

    def do_GET(self):
        raw = self.path.split("?", 1)
        path = unquote(raw[0])
        query = parse_qs(raw[1]) if len(raw) > 1 else {}
        parts = [p for p in path.split("/") if p]
        if _state_changing_get(parts):   # pass 97 (lane SAFE, WF-08): the one GET that writes gets the Host and Origin check
            refused = _request_guard(self, body_check=False)
            if refused:
                return _guard_refuse(self, refused)
        try:
            if parts[:1] == ["api"]:
                return self._api_get(parts[1:], query)
            if parts[:1] == ["icon"]:
                return self._icon(parts[1:])
            if parts[:1] == ["iconfile"]:
                return self._iconfile(parts[1:])   # pass 76 (lane ICON): a picture of the icon gallery
            if parts[:1] == ["sprite"]:
                return self._sprite(parts[1:])
            if parts[:2] == ["art", "wanted"] and len(parts) == 3:
                return self._wanted(parts[2])
            if parts[:1] == ["dl"]:
                return self._dl(parts[1:])
            if parts[:1] == ["examples"] and len(parts) == 2:
                return self._example(parts[1])
            if parts[:1] == ["workflows"] and len(parts) == 2:
                return self._workflow(parts[1])
            if parts[:1] == ["sound"] and len(parts) == 2:
                return self._sound(parts[1])
            if parts[:1] == ["vendor"] and len(parts) == 2:
                return self._vendor(parts[1])
            return self._static(parts)
        except Exception as e:  # a bug should show in the page, not kill the server
            import traceback
            traceback.print_exc()
            self._error(500, "%s: %s" % (type(e).__name__, e))

    def _api_get(self, parts, query):
        if parts == ["maps"]:
            return self._send(200, list_maps())
        if len(parts) == 2 and parts[0] == "map":
            if not ID_RE.match(parts[1]) or not os.path.isfile(map_path(parts[1])):
                return self._error(404, "no map %s" % parts[1])
            with open(map_path(parts[1]), "r", encoding="utf-8") as f:
                return self._send(200, f.read())
        if parts == ["enemies"]:
            return self._send(200, list_creatures())
        if parts == ["elites"]:
            return self._send(200, list_elites())
        if parts == ["pickups"]:
            return self._send(200, list_pickups())
        if parts == ["schema"]:
            if not os.path.isfile(SCHEMA):
                return self._send(200, "(docs/waves_schema.md is missing)", "text/plain; charset=utf-8")
            with open(SCHEMA, "r", encoding="utf-8") as f:
                return self._send(200, f.read(), "text/markdown; charset=utf-8")
        if parts == ["schema", "assets"]:
            if not os.path.isfile(ASSETS_SCHEMA):
                return self._send(200, "(docs/assets_schema.md is missing)", "text/plain; charset=utf-8")
            with open(ASSETS_SCHEMA, "r", encoding="utf-8") as f:
                return self._send(200, f.read(), "text/markdown; charset=utf-8")
        if parts == ["workflows"]:
            d = os.path.join(ROOT, "tools", "comfy_workflows")
            return self._send(200, {"ok": True, "files": sorted(f for f in os.listdir(d) if f.endswith(".json")) if os.path.isdir(d) else []})
        if parts == ["status"]:
            return self._send(200, status_record())
        if len(parts) in (2, 3) and parts[0] == "turnover" and (len(parts) == 2 or parts[2] == "all"):
            # pass 57: the "Spawned so far" lane's kill rate and boss fight from the run records (/all: tools' runs too)
            if not ID_RE.match(parts[1]):
                return self._error(404, "bad map id")
            return self._send(200, fit_turnover(parts[1], include_headless=len(parts) == 3))
        # ---- pass 66
        if parts == ["vocab"]:
            return self._send(200, VOCAB.table(CONTENT, GAME, combos_seen()))
        if parts == ["methods"]:
            return self._send(200, methods_table())
        if parts == ["heroes"]:
            return self._send(200, list_heroes())
        if parts == ["items"]:
            return self._send(200, list_items())
        if parts == ["drivers"]:
            return self._send(200, list_drivers())
        if (len(parts) == 2 and parts[0] == "drivers") or (len(parts) == 3 and parts[0] == "painted_death"):
            # pass 93 (lane PREVIEW): one driver with every frame and still; a creature_ctl look's painted death
            return DRVIO.api_get(self, sys.modules[__name__], parts, query)
        if parts[:1] == ["frames"]:
            # pass 95 (lane VACE): the Frames view (frames_io.py: a look's groups, one group's slots and versions, other looks')
            return FRIO.api_get(self, sys.modules[__name__], parts[1:], query)
        if parts[:1] == ["eyes"]:
            # pass 98 (lane GEMINI): the Gemini eye's health and today's calls, what the eyes say of a look (eyes_io.py)
            return EYESIO.api_get(self, sys.modules[__name__], parts, query)
        if parts[:1] == ["requests"] or (len(parts) == 3 and parts[0] == "job" and parts[2] == "summary"):
            # pass 96 (lane REQ): the art requests' folds and a job's summary (requests_io.py)
            return REQIO.api_get(self, sys.modules[__name__], parts, query)
        if len(parts) == 2 and parts[0] == "puppet":
            # pass 71 (lane PLE): what the Puppet method has of a hero and what its form offers
            if not ID_RE.match(parts[1]):
                return self._error(404, "bad id")
            res = puppet_record(parts[1])
            return self._send(200 if res.get("ok") else 404, res)
        if parts == ["refs"]:
            return self._send(200, list_refs())
        if parts[:1] == ["sim"]:
            # pass 77 (lane SIMUI): the Sim tab (sim_io.py: settings, status, history, result/<id>)
            return SIMIO.api_get(self, sys.modules[__name__], parts[1:], query)
        if parts[:1] == ["boss_attacks"]:
            # pass 72 (lane BOSS): the custom boss attacks (boss_attacks_io.py)
            return BAIO.api_get(self, sys.modules[__name__], parts[1:], query)
        if len(parts) == 2 and parts[0] == "templates":
            if parts[1] not in EDIT_KINDS:
                return self._error(404, "unknown kind %s" % parts[1])
            return self._send(200, list_templates(parts[1]))
        if len(parts) in (3, 4) and parts[0] == "content":
            kind, cid = parts[1], parts[2]
            if kind not in EDIT_KINDS:
                return self._error(404, "unknown kind %s" % kind)
            if not ID_RE.match(cid):
                return self._error(404, "bad id")
            if len(parts) == 3:
                return self._result(read_content(kind, cid))
            if parts[3] == "icons":
                # pass 76 (lane ICON): every icon picture on disk and every look's icon now (the gallery, Revert icon)
                return self._result(icon_gallery(kind, cid))
            if parts[3] == "next_codes":
                n = query.get("n", ["1"])[0]
                try:
                    n = int(n)
                except ValueError:
                    n = 1
                res = next_codes(kind, cid, n)
                return self._send(200 if res.get("ok") else 404, res)
            return self._error(404, "unknown API path")
        if parts in (["ops"], ["events"], ["jobs", "archived"]):
            # pass 97 (lane PROGRESS): the Ops roll-up, the events log, the archived jobs (ops_io.py)
            return OPSIO.api_get(self, sys.modules[__name__], parts, query)
        if parts == ["jobs", "specs"]:
            m = jobs_module()
            if m is None:
                return self._send(503, {"ok": False, "error": _jobs_error[0] or "the jobs module is not here yet", "specs": {}})
            return self._send(200, {"ok": True, "specs": getattr(m, "SPECS", {})})
        if parts == ["jobs", "defaults"]:
            # pass 68 (D6): what the server fills into a candidate job's empty fields, and where each came from, so the
            # form shows them as values: ?kind=icon_cands|hero_badge|hero_title&target=<kind>/<id>[/<code>]
            kind = (query.get("kind") or [""])[0]
            bits = [b for b in (query.get("target") or [""])[0].split("/") if b]
            if len(bits) not in (2, 3) or bits[0] not in KIND_FOLDERS or not ID_RE.match(bits[1]) or (len(bits) == 3 and not CODE_RE.match(bits[2])):
                return self._error(400, "target is <kind>/<id>[/<code>] (got %s)" % "/".join(bits))
            st, body = jobs_call("candidate_defaults", kind, {"kind": bits[0], "id": bits[1], "code": bits[2] if len(bits) == 3 else ""})
            return self._send(st, body)
        if parts == ["jobs"]:
            since = query.get("since", [None])[0]
            try:
                since = int(since) if since is not None else None
            except ValueError:
                since = None
            if (query.get("delta") or [""])[0] in ("1", "true"):
                # pass 97 (lane LIVE, UI-02): {rev, changed, removed, delta} for the page; without delta=1 today's answer
                st, body = jobs_call("list_delta", since)
                return self._send(st, body)
            st, body = jobs_call("list", since)
            return self._send(st, body)
        if len(parts) == 2 and parts[0] == "job":
            st, body = jobs_call("get", parts[1])
            return self._send(st, body)
        return self._error(404, "unknown API path")

    def _iconfile(self, parts):
        """/iconfile/<kind>/<id>/<ref> (pass 76): one picture of the icon gallery (icon_ref_path checks the ref)."""
        if len(parts) < 4 or parts[0] not in KIND_FOLDERS or not ID_RE.match(parts[1]):
            return self._error(404, "icon gallery paths are /iconfile/<kind>/<id>/<folder|backup|deleted|legacy>/...")
        full = icon_ref_path(parts[0], parts[1], "/".join(parts[2:]))
        if not full:
            return self._error(404, "no such icon")
        self._file(full, "image/png")

    def _icon(self, parts):
        if len(parts) not in (2, 3):
            return self._error(404, "icon paths are /icon/<kind>/<id>[/<code>]")
        code = parts[2] if len(parts) == 3 else ""
        if code and not CODE_RE.match(code):
            return self._error(404, "bad variant code")
        full = icon_path(parts[0], parts[1], code)
        if not full:
            return self._error(404, "no icon")
        self._file(full, "image/png")

    def _sprite(self, parts):
        """A creature's or hero's animation strip (pass 58, pass 66): /sprite/<kind>/<id>[/<code>], kind enemy|boss|hero."""
        if len(parts) not in (2, 3):
            return self._error(404, "sprite paths are /sprite/<kind>/<id>[/<code>]")
        code = parts[2] if len(parts) == 3 else ""
        if code and not CODE_RE.match(code):
            return self._error(404, "bad variant code")
        full = sprite_path(parts[0], parts[1], code)
        if not full:
            return self._error(404, "no strip")
        self._file(full, "image/png")

    def _wanted(self, name):
        """/art/wanted/hero_<id>.png: a hero's title cut-out (game/art/ui/wanted/)."""
        m = re.match(r"^hero_([a-z0-9_]+)\.png$", name)
        if not m:
            return self._error(404, "only /art/wanted/hero_<id>.png")
        full = os.path.join(WANTED_ART, name)
        if not os.path.isfile(full):
            return self._error(404, "no title cut-out for %s" % m.group(1))
        self._file(full, "image/png")

    def _dl(self, parts):
        """/dl/<rel>: a file under tools/dl's allowed roots (png jpg webp gif json txt), or a directory listing as JSON."""
        full = dl_path("/".join(parts))
        if full is None:
            return self._error(404, "not found")
        if os.path.isdir(full):
            names = sorted(f for f in os.listdir(full) if not f.startswith("."))
            files = [{"name": f, "dir": os.path.isdir(os.path.join(full, f)),
                      "size": os.path.getsize(os.path.join(full, f)) if os.path.isfile(os.path.join(full, f)) else 0}
                     for f in names]
            return self._send(200, {"ok": True, "path": "/dl/" + "/".join(parts), "files": files})
        self._file(full)

    def _example(self, name):
        if not FILENAME_RE.match(name) or not name.lower().endswith(".png"):
            return self._error(404, "not found")
        full = os.path.join(EXAMPLES, name)
        if not os.path.isfile(full):
            return self._error(404, "no example %s" % name)
        self._file(full, "image/png")

    def _workflow(self, name):
        """A ComfyUI workflow template (tools/comfy_workflows/*.json, written by `python tools/comfy.py --export`)."""
        if not FILENAME_RE.match(name) or not name.lower().endswith(".json"):
            return self._error(404, "not found")
        full = os.path.join(ROOT, "tools", "comfy_workflows", name)
        if not os.path.isfile(full):
            return self._error(404, "no workflow %s" % name)
        self._file(full, "application/json; charset=utf-8")

    def _vendor(self, name):
        """/vendor/<file>: a third-party script the page loads (pass 71: model-viewer), from tools/level_editor/vendor/."""
        ext = os.path.splitext(name)[1].lower()
        if not FILENAME_RE.match(name) or ext not in VENDOR_TYPES:
            return self._error(404, "not found")
        full = os.path.join(VENDOR, name)
        if not os.path.isfile(full):
            return self._error(404, "no vendor file %s" % name)
        self._file(full, VENDOR_TYPES[ext], cache="max-age=86400")

    def _sound(self, sid):
        full = sound_path(sid)
        if full is None:
            return self._error(404, "no sound %s" % sid)
        self._file(full)

    def _static(self, parts):
        name = parts[-1] if parts else "index.html"
        if len(parts) > 1 or "/" in name or "\\" in name or name.startswith("."):
            return self._error(404, "not found")
        ext = os.path.splitext(name)[1].lower()
        if ext not in STATIC_TYPES:
            return self._error(404, "not found")
        full = os.path.join(HERE, name)
        if not os.path.isfile(full):
            return self._error(404, "not found")
        with open(full, "rb") as f:
            data = f.read()
        self._send(200, data, STATIC_TYPES[ext])

    def _body(self):
        """The request's JSON body, or (None, error text)."""
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > 50 * 1024 * 1024:
            return None, "no body"
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8")), None
        except ValueError as e:
            return None, "the body is not JSON: %s" % e

    def _upload(self):
        """POST /api/upload: the raw file in the body, headers X-Kind (2d|3d) and X-Filename; streamed to <dest>.tmp in
        1 MiB pieces (critique 24); no Content-Length is a 411, over 200 MB a 413. A 3D file gets a folder of its own and
        a `ref_probe` job."""
        kind = (self.headers.get("X-Kind") or "").strip().lower()
        name = (self.headers.get("X-Filename") or "").strip()
        length = self.headers.get("Content-Length")
        if length is None:
            self.close_connection = True
            return self._error(411, "the upload needs a Content-Length")
        try:
            length = int(length)
        except ValueError:
            self.close_connection = True
            return self._error(400, "bad Content-Length")
        if length <= 0:
            return self._error(400, "an empty upload")
        if length > UPLOAD_MAX:
            self.close_connection = True
            return self._error(413, "the upload is over %d MB" % (UPLOAD_MAX // (1024 * 1024)))
        if kind not in UPLOAD_EXTS:
            self.close_connection = True
            return self._error(400, "X-Kind must be 2d or 3d")
        if not FILENAME_RE.match(name) or name.startswith(".") or not name.lower().endswith(UPLOAD_EXTS[kind]):
            self.close_connection = True
            return self._error(400, "X-Filename must be letters, digits, dots, dashes and underscores with one of %s"
                               % ", ".join(UPLOAD_EXTS[kind]))
        if kind == "2d":
            folder = os.path.join(UPLOADS, "2d")
            slug = _slug(name)
        else:
            slug = _slug(name)
            folder = os.path.join(UPLOADS, "3d", slug)
            n = 1
            while os.path.isdir(folder):
                n += 1
                folder = os.path.join(UPLOADS, "3d", "%s_%d" % (slug, n))
            slug = os.path.basename(folder)
        os.makedirs(folder, exist_ok=True)
        dest = os.path.join(folder, name)
        if kind == "2d":
            stem, ext = os.path.splitext(name)
            n = 1
            while os.path.exists(dest):
                n += 1
                dest = os.path.join(folder, "%s_%d%s" % (stem, n, ext))
        tmp = dest + ".tmp"
        remaining = length
        with open(tmp, "wb") as f:
            while remaining > 0:
                chunk = self.rfile.read(min(remaining, 1024 * 1024))
                if not chunk:
                    break
                f.write(chunk)
                remaining -= len(chunk)
        if remaining > 0:
            try:
                os.remove(tmp)
            except OSError:
                pass
            self.close_connection = True
            return self._error(400, "the upload ended early (%d bytes short)" % remaining)
        os.replace(tmp, dest)
        out = {"ok": True, "kind": kind, "name": os.path.basename(dest), "path": rel(dest), "slug": slug, "size": length,
               "url": "/dl/uploads/2d/%s" % os.path.basename(dest) if kind == "2d" else None, "job": None}
        if kind == "3d":
            job = _enqueue("ref_probe", {"kind": "ref", "id": slug}, {"src": rel(dest)},
                           "probe %s" % os.path.basename(dest))
            out["job"], out["job_error"] = job.get("job"), job.get("error")
        self._send(200, out)

    def do_POST(self):
        refused = _request_guard(self)   # pass 97 (lane SAFE, WF-08): a foreign Host or Origin 403, a non-JSON body 415
        if refused:
            return _guard_refuse(self, refused)
        path = unquote(self.path.split("?", 1)[0])
        parts = [p for p in path.split("/") if p]
        try:
            if parts == ["api", "upload"]:
                return self._upload()
            if len(parts) == 3 and parts[:2] == ["api", "map"]:
                map_id = parts[2]
                if not ID_RE.match(map_id):
                    return self._error(400, "bad map id")
                data, err = self._body()
                if err:
                    return self._error(400, err)
                result = write_map(map_id, data)
                return self._send(200 if result.get("ok") else 400, result)
            if len(parts) == 4 and parts[:2] == ["api", "enemy"] and parts[3] == "variant":
                cid = parts[2]
                if not ID_RE.match(cid):
                    return self._error(400, "bad creature id")
                data, err = self._body()
                if err:
                    return self._error(400, err)
                code = data.get("code") if isinstance(data, dict) else None
                result = write_variant(cid, code)
                return self._send(200 if result.get("ok") else 400, result)
            if len(parts) == 4 and parts[:2] == ["api", "enemy"] and parts[3] == "blood":
                # pass 58: the death splash's colour from the Creatures tab
                cid = parts[2]
                if not ID_RE.match(cid):
                    return self._error(400, "bad creature id")
                data, err = self._body()
                if err:
                    return self._error(400, err)
                color = data.get("color") if isinstance(data, dict) else None
                result = write_blood(cid, color)
                return self._send(200 if result.get("ok") else 400, result)
            if parts == ["api", "item_looks", "set_all"]:
                # pass 73 (lane CARDS): "set every card to look X" (the Items tab's Cards bar)
                data, err = self._body()
                if err:
                    return self._error(400, err)
                data = data if isinstance(data, dict) else {}
                ids = data.get("ids") if isinstance(data.get("ids"), list) else None
                res = set_item_looks_all(str(data.get("kind") or "passive"), data.get("code"), ids)
                return self._send(200 if res.get("ok") else 400, res)
            # ---- pass 66: the content model
            if parts[:2] == ["api", "content"] and len(parts) >= 3:
                return self._post_content(parts[2:])
            if parts == ["api", "workflows", "push"]:
                # the job form's template workflows into the ComfyUI page's Workflows sidebar (88fits/templates/)
                m = jobs_module()
                if m is None or not hasattr(m, "push_templates"):
                    return self._send(503, {"ok": False, "error": _jobs_error[0] or "the jobs module is not here"})
                return self._send(200, {"ok": True, "files": m.push_templates(), "extension": m.comfy_extension_state()})
            if parts == ["api", "test_launch"]:
                data, err = self._body()
                if err:
                    return self._error(400, err)
                return self._test_launch(data if isinstance(data, dict) else {})
            if len(parts) == 4 and parts[:2] == ["api", "locks"] and parts[3] == "release":
                # the Jobs tab's "Force release" of a lock held by an unknown or dead process (lead, pass 66): the page
                # confirms inline first; a plain release only lets go of a lock this server process holds
                name = parts[2]
                if name not in locks.NAMES:
                    return self._error(404, "no lock %s" % name)
                data, err = self._body()
                data = data if isinstance(data, dict) else {}
                ok = locks.force_release(name) if bool(data.get("force")) else locks.release(name)
                return self._send(200 if ok else 409, {"ok": ok, "locks": locks.status_all(),
                                                       "error": "" if ok else "held by another process: send force"})
            if parts[:2] == ["api", "jobs"]:
                return self._post_jobs(parts[2:])
            if parts[:2] == ["api", "drivers"] and parts[-1] == "open" and len(parts) in (3, 4):
                # pass 93 (lane PREVIEW): Explorer on a driver's folder (drivers_io.open_folder: a library folder only)
                data, err = self._body()
                return DRVIO.api_post(self, sys.modules[__name__], parts[1:], data if isinstance(data, dict) else {})
            if parts[:2] == ["api", "frames"]:
                # pass 95 (lane VACE): stage / unstage / pin / copy / repair / ask / export / register (frames_io.py)
                data, err = self._body()
                return FRIO.api_post(self, sys.modules[__name__], parts[2:], data if isinstance(data, dict) else {})
            if parts[:2] == ["api", "eyes"]:
                # pass 98 (lane GEMINI): Check with Gemini (an evaluate job over the whole look; eyes_io.py)
                data, err = self._body()
                return EYESIO.api_post(self, sys.modules[__name__], parts[2:], data if isinstance(data, dict) else {})
            if parts[:2] == ["api", "requests"]:
                # pass 96 (lane REQ): create, pause / resume / stop / cancel / step, approve / reject / pick (requests_io.py)
                data, err = self._body()
                return REQIO.api_post(self, sys.modules[__name__], parts[2:], data if isinstance(data, dict) else {})
            if parts[:2] == ["api", "sim"]:
                # pass 77 (lane SIMUI): the Sim tab's run, settings, keep / delete / cancel, unlock (sim_io.py)
                return SIMIO.api_post(self, sys.modules[__name__], parts[2:])
            if parts[:2] == ["api", "boss_attacks"]:
                # pass 72 (lane BOSS): new, save, assign, delete (boss_attacks_io.py)
                return BAIO.api_post(self, sys.modules[__name__], parts[2:])
            return self._error(404, "unknown API path")
        except Exception as e:
            import traceback
            traceback.print_exc()
            self._error(500, "%s: %s" % (type(e).__name__, e))

    def _post_content(self, parts):
        kind = parts[0]
        if kind not in EDIT_KINDS:
            return self._error(404, "unknown kind %s (one of %s)" % (kind, ", ".join(EDIT_KINDS)))
        data, err = self._body()
        if err and err != "no body":
            return self._error(400, err)
        data = data if isinstance(data, dict) else {}
        if len(parts) == 1:
            return self._result(create_content(kind, data.get("id"), data.get("template"), data.get("name", ""),
                                               data.get("flavour", ""), data.get("doc", ""), bool(data.get("copy_art", False)),
                                               data.get("fields")))
        cid = parts[1]
        if not ID_RE.match(cid):
            return self._error(400, "bad id")
        if len(parts) == 3:
            op = parts[2]
            if op == "save":
                return self._result(write_content(kind, cid, data.get("json"), data.get("base_mtime")))
            if op == "variant":
                res = write_variant_kind(kind, cid, data.get("code"))
                return self._send(200 if res.get("ok") else 400, res)
            if op == "retire":
                return self._result(set_retired(kind, cid, data.get("retired", True)))
            if op == "availability":
                return self._result(set_availability(kind, cid, data))
            if op == "delete":
                return self._result(delete_content(kind, cid, bool(data.get("cascade", False))))
            if op == "icon":
                # pass 76 (lane ICON): {op: revert | use, code ("" = the base), ref, confirm}
                return self._result(icon_op(kind, cid, str(data.get("code") or ""), str(data.get("op") or ""), data))
            if op == "make_path":
                if kind != "weapon":
                    return self._error(400, "make_path is for weapons")
                return self._result(make_path(cid, data.get("names")))
            if op == "look":
                if "op" in data and "codes" in data:
                    return self._result(look_op(kind, cid, data.get("codes"), str(data.get("op", "")), data))
                return self._result(add_look(kind, cid, data.get("code"), data.get("note", ""), data.get("recipe")))
            return self._error(404, "unknown content op %s" % op)
        if len(parts) == 4 and parts[2] == "look":
            code = parts[3]
            if not CODE_RE.match(code):
                return self._error(400, "bad look code")
            return self._result(look_op(kind, cid, [code], str(data.get("op", "")), data))
        return self._error(404, "unknown API path")

    def _test_launch(self, data):
        """POST /api/test_launch {character?, look?, enemy?, variant?, count?, map?} -> a `launch` job (the editor binary
        into the debug arena with that hero or creature; INTERFACES §3 launch keys)."""
        spec = {"map": str(data.get("map") or "red_canyon"), "count": int(_num(data.get("count"), 3))}
        for key, src in (("character", "character"), ("look", "look"), ("spawn_enemy", "enemy"), ("variant", "variant")):
            if data.get(src):
                spec[key] = str(data[src])
        if "character" in spec and not ID_RE.match(spec["character"]):
            return self._error(400, "bad hero id")
        if "spawn_enemy" in spec and not ID_RE.match(spec["spawn_enemy"]):
            return self._error(400, "bad creature id")
        target = {"kind": "hero" if "character" in spec else "enemy", "id": spec.get("character") or spec.get("spawn_enemy") or "arena",
                  "code": spec.get("look") or spec.get("variant") or ""}
        res = _enqueue("launch", target, spec, "test in game: %s" % target["id"])
        if res.get("job") is None:
            return self._send(503, {"ok": False, "error": res.get("error"), "spec": spec})
        self._send(200, {"ok": True, "job": res["job"], "spec": spec})

    def _post_jobs(self, parts):
        data, err = self._body()
        if err and err != "no body":
            return self._error(400, err)
        data = data if isinstance(data, dict) else {}
        if not parts:
            if not data.get("kind"):
                return self._error(400, "a job needs {kind, target, spec}")
            st, body = jobs_call("enqueue", str(data["kind"]), data.get("target") or {}, data.get("spec") or {}, data.get("title"))
            return self._send(st, body)
        if parts == ["requeue_interrupted"]:
            # pass 97 (lane SAFE, OPS-03): "Re-queue all" {ids?, all?} -> {requeued, skipped, refused}; only on a click
            st, body = jobs_call("requeue_interrupted", data.get("ids") if isinstance(data.get("ids"), list) else None,
                                 "all" if data.get("all") else "restart")
            return self._send(st, body)
        jid = parts[0]
        if not re.match(r"^[A-Za-z0-9_-]+$", jid):
            return self._error(400, "bad job id")
        if len(parts) == 1:
            st, body = jobs_call("edit", jid, data.get("spec"), data.get("title"))
            return self._send(st, body)
        op = parts[1]
        if op == "cancel":
            st, body = jobs_call("cancel", jid)
        elif op == "requeue":
            st, body = jobs_call("requeue", jid, data.get("reroll"))
        elif op == "pick":
            st, body = jobs_call("pick", jid, data.get("choice"))
        elif op == "install":
            # pass 76 (lane ICON): an icon for the look in play or the base waits for confirm: true (the page asks: now ->
            # new); every icon install gets a file of its own (install_guard: nothing is overwritten)
            gst, gopts = install_guard(jid, data)
            if gst is not None:
                return self._send(gst, gopts)
            st, body = jobs_call("install", jid, data.get("choice"), gopts if gopts is not None else (data.get("options") or data.get("badge")))
        elif op == "move":
            st, body = jobs_call("move", jid, int(_num(data.get("delta"), 0)))
        elif op == "delete":
            st, body = jobs_call("delete", jid)
        elif op == "merge":
            # the Jobs tab's "Merge again" / "Re-dump this file (changes its layout)" on an unmerged landing (lead, pass 66)
            st, body = jobs_call("merge", jid, bool(data.get("redump")))
        elif op == "push_workflows":
            # the card's "Send to ComfyUI": the job's workflows into the page's Workflows sidebar (open links follow)
            st, body = jobs_call("push_workflows", jid)
        else:
            return self._error(404, "unknown jobs op %s" % op)
        return self._send(st, body)


# ---------------------------------------------------------------- pass 97 (lane SAFE): health and safety (OPS-03, WF-08)

# WF-08: the editor binds 127.0.0.1 (main(), free_port); a POST is refused when its Host is not this editor's loopback
# address (a page that rebinds its own name to 127.0.0.1), when it carries an Origin that is not this editor's own page
# (another site in Garry's browser), or when a JSON route gets a body that is not application/json (a form or a
# text/plain "simple request"). /api/upload keeps its own body (the raw file). A request with no Origin (urllib, curl,
# art_request.py, puppet.py, the selftests) passes on a loopback Host.
GUARD_HOSTS = ("127.0.0.1", "localhost")
GUARD_RAW_BODY_ROUTES = (["api", "upload"],)


def _split_host(value):
    """'127.0.0.1:8787' -> ('127.0.0.1', '8787'); '[::1]:8787' -> ('::1', '8787'); 'localhost' -> ('localhost', '')."""
    v = (value or "").strip().lower()
    if v.startswith("["):
        name, _, rest = v[1:].partition("]")
        return name, rest[1:] if rest.startswith(":") else ""
    name, _, port = v.partition(":")
    return name, port


def _request_guard(h, body_check=True):
    """None when the request may go on, else (status, error text): 403 for a foreign Host or Origin, 415 for a JSON
    route's body sent as another content type. A missing Host (no browser omits it) passes: the socket is loopback."""
    try:
        port = str(h.server.server_address[1])
    except Exception:   # noqa: BLE001  (a handler stand-in without a server: the selftests' fakes)
        port = ""
    host = h.headers.get("Host")
    if host is not None:
        name, hp = _split_host(host)
        if name not in GUARD_HOSTS or (hp and port and hp != port):
            return 403, ("this editor answers only on http://127.0.0.1:%s or http://localhost:%s (the request named Host %s)"
                         % (port, port, host))
    origin = h.headers.get("Origin")
    if origin is not None:
        o = origin.strip().lower().rstrip("/")
        if o not in ("http://127.0.0.1:%s" % port, "http://localhost:%s" % port):
            return 403, ("a request from another page (Origin %s) is refused: only the editor's own page, or a script "
                         "without an Origin, may change things" % origin)
    if not body_check:
        return None
    parts = [p for p in unquote(h.path.split("?", 1)[0]).split("/") if p]
    if parts in GUARD_RAW_BODY_ROUTES:
        return None
    try:
        length = int(h.headers.get("Content-Length") or 0)
    except ValueError:
        length = 0
    if length > 0:
        ctype = (h.headers.get("Content-Type") or "").split(";", 1)[0].strip().lower()
        if ctype != "application/json":
            return 415, ("a POST body must be JSON sent with Content-Type: application/json (got %s)"
                         % (h.headers.get("Content-Type") or "no Content-Type"))
    return None


def _guard_refuse(h, refused):
    """Answer a refused request; the body is never read, so the connection is closed after the answer."""
    h.close_connection = True
    return h._error(refused[0], refused[1], guard=True)


def _state_changing_get(parts):
    """The GET routes that write anything (WF-08's list): /api/frames/<kind>/<id>/<code> registers a look new to the
    frames store (frames_store.look_summary(register=True)). Every other GET only reads (or fills an in-memory cache)."""
    return len(parts) == 5 and parts[:2] == ["api", "frames"]


# OPS-03: what /api/status says about the toolchain (tools/doctor.py, cached) and the restart's interrupted jobs
DOCTOR_LIVE = [False]      # main() turns it on: a selftest that imports this module never starts the doctor's thread
DOCTOR_EVERY = 600.0       # seconds between two refreshes at most
_doctor_cache = {"t": 0.0, "summary": None, "running": False, "error": ""}
_doctor_lock = threading.Lock()


def _doctor_refresh():
    try:
        import doctor   # tools/doctor.py (read-only checks; quick = no ssh login and no walk of tools/dl)
        rep = doctor.run(quick=True)
        summ = doctor.summary(rep)
        err = ""
    except Exception as e:   # noqa: BLE001
        summ, err = None, "%s: %s" % (type(e).__name__, e)
    with _doctor_lock:
        _doctor_cache.update(t=time.time(), running=False, error=err)
        if summ is not None:
            _doctor_cache["summary"] = summ


def doctor_status():
    """/api/status.doctor: the last summary (None before main() enabled it; {pending: true} until the first one ends).
    A stale one starts a refresh on a daemon thread; a request never waits for it."""
    if not DOCTOR_LIVE[0]:
        return None
    with _doctor_lock:
        if time.time() - _doctor_cache["t"] >= DOCTOR_EVERY and not _doctor_cache["running"]:
            _doctor_cache["running"] = True
            threading.Thread(target=_doctor_refresh, name="doctor", daemon=True).start()
        if _doctor_cache["summary"] is not None:
            return dict(_doctor_cache["summary"], refreshing=_doctor_cache["running"])
        return {"pending": True, "error": _doctor_cache["error"]}


def _safe_status(rec, m):
    """status_record() plus `interrupted` (the jobs the last restart interrupted, for "Re-queue all"), `interrupted_ids`,
    `doctor` and `ai_hosts` (the hosts in use; never the key's contents)."""
    try:
        ids = m.interrupted_ids() if m is not None and hasattr(m, "interrupted_ids") else []
    except Exception:   # noqa: BLE001
        ids = []
    rec["interrupted"], rec["interrupted_ids"] = len(ids), ids
    rec["doctor"] = doctor_status()
    try:
        rec["ai_hosts"] = {k: ai_hosts.get(k) for k in ("comfy", "lmstudio", "ollama", "ssh")}
    except Exception:   # noqa: BLE001
        rec["ai_hosts"] = None
    return rec


# OPS-03: closing the console window does what Ctrl+C does (main()'s finally: jobs.stop(), the `jobs` lock released), so
# no dead lock is left behind; recover() at the next start stays the backstop for a kill nobody can catch
_exit_state = {"done": False, "jobs": None}
_console_handler_ref = []   # the ctypes callback: kept alive while the process runs
CTRL_EVENTS = {2: "the console window was closed", 5: "log off", 6: "shut down"}


def _exit_cleanup(reason="exit", say=False):
    """jobs.stop() once (the workers told to stop, the `jobs` lock released); the window gives a closing process about
    five seconds, so each worker is waited for half a second at most. True when it ran now."""
    if _exit_state["done"] or _exit_state["jobs"] is None:
        return False
    _exit_state["done"] = True
    try:
        _exit_state["jobs"].stop(timeout=0.5)
        msg = "stopped (%s): the job queue's lock is released" % reason
    except Exception as e:   # noqa: BLE001
        msg = "jobs: stop on %s: %s" % (reason, e)
    if say:
        try:
            print(msg, flush=True)
        except Exception:   # noqa: BLE001  (the console may be gone already)
            pass
    return True


def _console_ctrl(event):
    """SetConsoleCtrlHandler's callback. Close / log off / shut down -> _exit_cleanup, True. Ctrl+C (0) and Ctrl+Break (1)
    -> False: Python's own handler goes on (KeyboardInterrupt, as today)."""
    event = int(event)
    if event in CTRL_EVENTS:
        _exit_cleanup(CTRL_EVENTS[event], say=True)
        return True
    return False


def _install_exit_handlers(jobs):
    """main(): the console-close handler (Windows), Ctrl+Break as Ctrl+C, and atexit; each a no-op when not available."""
    import atexit
    import signal
    _exit_state["jobs"] = jobs
    atexit.register(_exit_cleanup, "exit")
    if hasattr(signal, "SIGBREAK"):
        try:
            signal.signal(signal.SIGBREAK, signal.default_int_handler)
        except (ValueError, OSError):
            pass
    if os.name == "nt":
        try:
            import ctypes
            from ctypes import wintypes
            cb = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.DWORD)(lambda ev: bool(_console_ctrl(ev)))
            if ctypes.windll.kernel32.SetConsoleCtrlHandler(cb, True):
                _console_handler_ref.append(cb)
        except Exception as e:   # noqa: BLE001
            print("note: no console-close handler (%s); the next start still takes over a dead jobs lock" % e)


# ---------------------------------------------------------------- main

def free_port(start):
    """`start`, or the first free port after it (another editor, or something else, may hold it)."""
    for port in range(start, start + 20):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    return start


def main():
    ap = argparse.ArgumentParser(description="88fits Level Editor server")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--no-browser", action="store_true")
    ap.add_argument("--no-jobs", action="store_true", help="do not start the AI job workers (jobs.py)")
    # pass 96 (lead): an unattended run (the loop's live proof) stops itself once nothing is queued or running
    ap.add_argument("--exit-idle-after", type=float, default=0.0, metavar="SECONDS",
                    help="after this many seconds, stop the server at the first moment no job is queued or running")
    args = ap.parse_args()
    OPSIO.server_boot()   # pass 97 (lane PROGRESS): the console also into tools/dl/jobs/server.log; the events log on
    if not os.path.isdir(CONTENT):
        print("no content folder at %s: run this from the 88fits checkout" % CONTENT)
        return 1
    port = free_port(args.port)
    if port != args.port:
        print("port %d is busy, using %d" % (args.port, port))
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.daemon_threads = True
    url = "http://127.0.0.1:%d/" % port
    print("88fits Level Editor: %s   (repo %s)" % (url, ROOT))
    if not os.path.isfile(GODOT):
        print("note: the Godot binary is not at %s; Save will write the JSON but cannot import it" % GODOT)
    jobs = jobs_module()
    if jobs is not None:
        try:
            # the claim names this port, so a later editor can tell a live holder from a phantom; --no-jobs = view only
            jobs.init(HOOKS, ROOT, port=port, view_only=bool(args.no_jobs))
            if args.no_jobs:
                print("jobs: --no-jobs: this editor shows the queue and changes nothing (no workers; the routes refuse changes)")
            elif jobs.is_readonly():
                ro = jobs.status().get("readonly") or {}
                print("jobs: ANOTHER Level Editor runs the job queue (%s, pid %s): this one shows it read-only and refuses changes; "
                      "queue from that page, or close it and restart this one" % (ro.get("who") or "?", ro.get("pid") or "?"))
            else:
                jobs.start_workers()
                print("jobs: the queue is up (tools/dl/jobs/queue.json)")
        except Exception as e:
            print("jobs: could not start the workers: %s: %s" % (type(e).__name__, e))
            jobs = None
    else:
        print("jobs: %s (the Jobs tab will say so)" % (_jobs_error[0] or "the jobs module is not here yet"))
    if jobs is not None:
        OPSIO.server_start(jobs, port)   # pass 97 (lane PROGRESS): the `start` event; the archive now and once a day
    _install_exit_handlers(jobs)   # pass 97 (lane SAFE, OPS-03): closing this window = Ctrl+C (the jobs lock released)
    DOCTOR_LIVE[0] = True          # pass 97 (lane SAFE): /api/status.doctor, refreshed on a daemon thread every 10 min at most
    doctor_status()
    print("Ctrl+C stops it.")
    if args.exit_idle_after > 0:
        def _idle_watch() -> None:
            time.sleep(args.exit_idle_after)
            while True:
                try:
                    st = jobs.status() if jobs is not None else {}
                    if int(st.get("running", 0) or 0) == 0 and int(st.get("queued", 0) or 0) == 0:
                        print("exit-idle-after: nothing queued or running, stopping")
                        httpd.shutdown()
                        return
                except Exception:
                    pass
                time.sleep(15)
        threading.Thread(target=_idle_watch, daemon=True).start()
        print("exit-idle-after: this editor stops itself once idle after %.0f s" % args.exit_idle_after)
    if not args.no_browser:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        httpd.server_close()
        if jobs is not None:
            try:
                jobs.stop()
            except Exception as e:
                print("jobs: stop: %s" % e)
    return 0


if __name__ == "__main__":
    # pass 96 (lead): modules that look the server up by name (frames_io._default_enqueue) find it when it runs as __main__
    sys.modules.setdefault("server", sys.modules[__name__])
    sys.exit(main())

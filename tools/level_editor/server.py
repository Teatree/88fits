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
                            (68); POST /api/jobs, /api/jobs/<id>[/cancel|requeue|pick|install|move|delete]

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
              ".ogg": "audio/ogg", ".mp3": "audio/mpeg"}
# the folders the API reads, by the kind the page names (pass 66 added the heroes and the items)
KIND_FOLDERS = {"enemy": "enemies", "boss": "bosses", "elite": "elites", "pickup": "pickups", "hero": "characters",
                "weapon": "weapons", "evolution": "evolutions", "passive": "passives", "mutation": "mutations",
                "quest": "quests", "perk": "perks"}
# the kinds the asset editors create, save and delete (pass 69: a hero's perks, edited from the Heroes tab)
EDIT_KINDS = ("enemy", "boss", "hero", "weapon", "evolution", "passive", "mutation", "perk")
# the kinds that carry art looks (`variants`)
LOOK_KINDS = ("enemy", "boss", "hero")
# every content type the game scans (JsonContent.TYPES): a new id must be free under all of them
ALL_TYPES = ["weapons", "evolutions", "passives", "mutations", "perks", "enemies", "bosses", "elites", "characters",
             "talents", "quests", "maps", "pickups", "structures"]
# the keys of a boss attack the estimate times its script by (pass 57)
SCRIPT_KEYS = ("name", "windup", "duration", "count", "enemy", "interval", "warn", "spawn")
# INTERFACES §0.1 (BALANCING §13): a new weapon starts hidden with its three template mutations and its evolution
NEW_WEAPON_STARTS_HIDDEN = True
# pass44_test.gd's quest-locked band of the base items (pass 69 re-pinned its floor to 0.28: the Salt, the Frisbee and
# five passive items came unlocked; selftest_L69 reads the bounds from the test file)
BAND_LO, BAND_HI = 0.28, 0.56
# tools/dl roots the page may read through /dl/<rel> (plus any root whose name starts with "icons")
DL_ROOTS = ("jobs", "drivers", "ai_raw_anime", "ai_anim", "review", "title_heroes", "uploads")
DL_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".json", ".txt")
UPLOAD_MAX = 200 * 1024 * 1024
UPLOAD_EXTS = {"2d": (".png", ".jpg", ".jpeg", ".webp", ".gif"), "3d": (".fbx", ".glb", ".gltf", ".obj", ".dae", ".blend", ".zip")}
QA_URL = "http://127.0.0.1:1234/v1/models"

sys.path.insert(0, os.path.join(ROOT, "tools"))
import locks  # noqa: E402  (tools/locks.py: the repo-wide Godot and ComfyUI locks, the PC save kept aside)
import content_io as cio  # noqa: E402
import vocab as VOCAB  # noqa: E402

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
                                "evolves_from", "text"},
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
    elif kind == "passive":
        rec.update({"line": bool(d.get("line", False)), "max_level": d.get("max_level", 8), "levels": d.get("levels", []),
                    "repeat_last_level": bool(d.get("repeat_last_level", True)), "evolves_into": str(d.get("evolves_into", "")),
                    "evolves_from": str(d.get("evolves_from", "")), "text": str(d.get("text", "")),
                    "pairs_with": str(d.get("pairs_with", "")), "trade": str(d.get("trade", ""))})
    elif kind == "mutation":
        rec.update({"weapon": str(d.get("weapon", "")), "mutation_kind": str(d.get("kind", "motion")), "hero": str(d.get("hero", "")),
                    "text": str(d.get("text", "")), "vfx": str(d.get("vfx", "")), "effects": d.get("effects", []),
                    "params": d.get("params", {}), "behavior": str(d.get("behavior", "")), "visual": str(d.get("visual", ""))})
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
    if not os.path.isfile(GODOT):
        return False, ("Godot binary not found at %s: the JSON is saved, but the game plays the .tres. Run the import "
                       "yourself: Godot --headless --path game --script res://tools/import_json.gd -- only=%s"
                       % (GODOT, target))
    args = ["--headless", "--path", GAME, "--script", "res://tools/import_json.gd", "--", "only=%s" % target]
    lk = locks.acquire("godot", who, note="import_json only=%s" % target, timeout=LOCK_WAIT, log=lambda m: None)
    if lk is None:
        s = locks.status("godot") or {}
        holder = "%s%s" % (s.get("who", "?"), (" / " + s["job"]) if s.get("job") else "")
        job = _enqueue("import", {"kind": "content", "id": target}, {"targets": target.split(",")}, "import %s" % target)
        more = ("an import job was queued instead (%s)" % job["job"]["id"]) if job.get("job") else \
            ("no import job could be queued: %s" % job.get("error", "the jobs module is not here yet"))
        return None, "the Godot lock has been held by %s for %d s: %s" % (holder, int(s.get("age_s", 0)), more)
    try:
        locks.keep_save()
        try:
            p = subprocess.run([GODOT] + args, capture_output=True, text=True, timeout=IMPORT_TIMEOUT, cwd=ROOT,
                               encoding="utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            return False, "the import did not finish in %d s" % IMPORT_TIMEOUT
        except OSError as e:
            return False, "could not run the import: %s" % e
        finally:
            locks.restore_save()
    finally:
        lk.release()
    text = (p.stdout or "") + (p.stderr or "")
    lines = [l for l in text.replace("\r", "").split("\n") if l.strip()]
    tail = "\n".join(lines[-12:])
    ok = p.returncode == 0 and "SCRIPT ERROR" not in text and "import_json: wrote" in text
    return ok, tail


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
    import_ok, output = run_import("maps/%s" % map_id)
    return {"ok": True, "wrote": rel(path), "backup": backup_rel,
            "import_ok": import_ok, "output": output}


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
    re-dumped), then the JSON -> .tres import of that one folder. Creatures (pass 54) and heroes (pass 66)."""
    if kind not in LOOK_KINDS:
        return {"ok": False, "error": "only enemies, bosses and heroes have looks"}
    _, path = content_path(kind, cid)
    if path is None:
        return {"ok": False, "error": "no %s %s" % (kind, cid)}
    if not isinstance(code, str) or not CODE_RE.match(code):
        return {"ok": False, "error": "the body needs a variant code: {\"code\": \"SK-B\"}"}
    with _write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        playable = playable_codes(os.path.dirname(path), d)
        if code not in playable:
            vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
            known = ", ".join(sorted(playable)) or "none"
            why = "its strip is not painted yet" if code in vs else "it has no such variant"
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
        if str(u.get("id", "")) == cid or str(c.get("enemy", "")) == cid or str(c.get("weapon", "")) == cid:
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
           "looks": look_records(kind, cid, folder, d, path) if kind in LOOK_KINDS else [],
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
            if kind == "hero" and "frame_px" not in update and isinstance(existing.get("recipe"), dict) and existing["recipe"].get("frame_px"):
                update["frame_px"] = existing["recipe"]["frame_px"]
            update["fresh"] = True
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
        return {"ok": True, "layout": layout, "file": rel(path), "keys": keys, "backup": backup_rel, "code": code,
                "base": base, "entry": d2["variants"][code]}

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

    def set_look_files(self, kind, cid, code, files):
        """pass 68 (D8): a candidate picked for a look lands in its entry: {"icon": "<id>_icon_<x>.png"} (a badge or an
        icon beside the JSON) and/or {"title": "hero_<id>_<x>.png"} (a hero's title cut-out under art/ui/wanted/). The
        entry is edited in place (content_io's entry writer), with a backup; no `fresh` (the strip is not touched) and no
        import here (the job queues one). The look must exist: a pick never creates an entry."""
        if kind not in LOOK_KINDS:
            return {"ok": False, "layout": "unmerged", "error": "only enemies, bosses and heroes have looks"}
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
    return {"ok": True, "root": ROOT, "godot": os.path.isfile(GODOT), "backups": BACKUPS, "content": CONTENT,
            "blender": blender_path(), "qa_online": qa, "locks": lk, "comfy": lk.get("comfy"), "godot_lock": lk.get("godot"),
            "jobs": jobs, "jobs_available": m is not None, "jobs_error": _jobs_error[0] if m is None else "",
            "methods": os.path.isfile(METHODS), "new_weapon_starts_hidden": NEW_WEAPON_STARTS_HIDDEN,
            # whether the ComfyUI page has the 88fits_open extension (the "open in ComfyUI" links need it)
            "comfy_open_ext": (m.comfy_extension_state() if m is not None and hasattr(m, "comfy_extension_state") else None)}


# ---------------------------------------------------------------- drivers, refs, methods

def list_drivers():
    """tools/dl/drivers/*/meta.json (lane B writes kind, views, frames, loop, fbx|src, pitch, notes, action): [{name,
    kind pose|depth, views, frames, meta, frames_url, sheet, sheets}]. A pose folder has <view>_sheet.png and
    all_sheet.png and frames <view>/driver_NN.png; a depth folder has <view>/clay.png and <view>/ctl_NN.png."""
    out = []
    if not os.path.isdir(DRIVERS):
        return out
    for name in sorted(os.listdir(DRIVERS)):
        folder = os.path.join(DRIVERS, name)
        meta_path = os.path.join(folder, "meta.json")
        if not os.path.isdir(folder) or not os.path.isfile(meta_path):
            continue
        try:
            meta = load_json(meta_path)
        except (OSError, ValueError):
            meta = {}
        if not isinstance(meta, dict):
            meta = {}
        on_disk = sorted(v for v in os.listdir(folder) if os.path.isdir(os.path.join(folder, v)))
        views = [str(v) for v in meta["views"] if str(v) in on_disk] if isinstance(meta.get("views"), list) else on_disk
        kind = str(meta.get("kind", "")) if meta.get("kind") in ("pose", "depth") else (
            "depth" if ("mode" in meta or "action" in meta or "extent" in meta) else "pose")
        sheet = None
        sheets = {}
        for cand in ("all_sheet.png", os.path.join("side", "clay.png"), os.path.join("front", "clay.png")):
            if os.path.isfile(os.path.join(folder, cand)):
                sheet = "/dl/drivers/%s/%s" % (name, cand.replace("\\", "/"))
                break
        for v in views:
            for cand in ("%s_sheet.png" % v, os.path.join(v, "clay.png")):
                if os.path.isfile(os.path.join(folder, cand)):
                    sheets[v] = "/dl/drivers/%s/%s" % (name, cand.replace("\\", "/"))
                    break
        frames = meta.get("frames")
        if frames is None and views:
            frames = len([f for f in os.listdir(os.path.join(folder, views[0])) if re.match(r"^(driver|ctl)_\d+\.png$", f)])
        out.append({"name": name, "kind": kind, "views": views, "frames": frames, "loop": meta.get("loop"),
                    "source": meta.get("fbx") or meta.get("glb") or meta.get("src"), "action": meta.get("action"),
                    "notes": meta.get("notes", ""), "meta": meta, "frames_url": "/dl/drivers/%s/<view>/" % name,
                    "frame_pattern": "ctl_%02d.png" if kind == "depth" else "driver_%02d.png",
                    "sheet": sheet, "sheets": sheets, "mtime": int(os.path.getmtime(meta_path))})
    return out


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
    if os.path.isdir(d3):
        for slug in sorted(os.listdir(d3)):
            folder = os.path.join(d3, slug)
            if not os.path.isdir(folder):
                continue
            files = [f for f in os.listdir(folder) if os.path.isfile(os.path.join(folder, f))]
            model = next((f for f in sorted(files) if f.lower().endswith(UPLOAD_EXTS["3d"])), None)
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
    names = sorted(os.listdir(base)) if os.path.isdir(base) else []
    picked = []
    for name in reversed(names):
        if len(picked) >= FIT_MAX_RUNS:
            break
        if not name.endswith(".json") or name.startswith("index"):
            continue
        s = run_summary(os.path.join(base, name))
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
QUIET_PREFIXES = ("/api/jobs", "/api/job/", "/api/status", "/dl/", "/icon/", "/sprite/", "/art/", "/examples/", "/sound/")


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
        try:
            if parts[:1] == ["api"]:
                return self._api_get(parts[1:], query)
            if parts[:1] == ["icon"]:
                return self._icon(parts[1:])
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
        if parts == ["refs"]:
            return self._send(200, list_refs())
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
            if parts[3] == "next_codes":
                n = query.get("n", ["1"])[0]
                try:
                    n = int(n)
                except ValueError:
                    n = 1
                res = next_codes(kind, cid, n)
                return self._send(200 if res.get("ok") else 404, res)
            return self._error(404, "unknown API path")
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
            st, body = jobs_call("list", since)
            return self._send(st, body)
        if len(parts) == 2 and parts[0] == "job":
            st, body = jobs_call("get", parts[1])
            return self._send(st, body)
        return self._error(404, "unknown API path")

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
            st, body = jobs_call("install", jid, data.get("choice"), data.get("options") or data.get("badge"))
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
    args = ap.parse_args()
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
    print("Ctrl+C stops it.")
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
    sys.exit(main())

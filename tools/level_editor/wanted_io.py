"""Pass 111, lane WANTED: the Level Editor's routes for the Bounty Board's config (game/content/wanted/wanted.json, read
by game/core/systems/WantedBoard.gd at boot; plain JSON, no .tres, so a save needs no import) and the art the tab's
poster imitation draws that no other route serves (the stage pictures, the chest, the coin, the badges).

server.py hands every /api/wanted request here with itself as `srv` (its CONTENT, GAME, BACKUPS, backup,
restore_numbers, the write lock), so a selftest that points those at a temporary copy tests these routes on it too.

  GET  /api/wanted                       {ok, json, file, mtime, exists, types}: the config as on disk
  GET  /api/wanted/art/<folder>/<file>   a picture from game/art/ui/<stages|badges|wanted|sources>/ (png, jpg), or a face
                                         from game/ui/fonts/ (ttf: the posters' slab and serif)
  GET  /api/wanted/sources               (pass 113) the power-ups and structures with their effect (the heal sources)
  GET  /api/wanted/structure_icon/<id>   (pass 113) a structure's icon (the Totem Pole, the Healing Well)
  POST /api/wanted/save                  {json, base_mtime}: the whole config back (a 409 when the file changed on disk
                                         since the page read it), checked (an object, `tasks` a list of known types,
                                         each with its difficulty), one backup, one write in the file's own layout
                                         (one top key a line, one task a line), the file's floats kept
"""
import json
import os
import re

import content_io as cio

REL = os.path.join("wanted", "wanted.json")
TYPES = ["kill_enemy", "kill_weapon", "kill_specials", "kill_elites", "kill_total", "boss_fast", "hp_floor", "beat_stage",
         "hero_level", "max_weapon", "evolve_item", "open_chests", "collect_coins",
         # pass 113 (lane TASKS)
         "damage_weapon", "heal_item", "heal_source", "item_level", "barrels", "totems", "element_damage"]
# pass 113 (lane TASKS): "sources" serves the fire (art/ui/sources/fire.png) the fire tasks show
ART_FOLDERS = {"stages": ("art", "ui", "stages"), "badges": ("art", "ui", "badges"), "wanted": ("art", "ui", "wanted"),
               "fonts": ("ui", "fonts"), "sources": ("art", "ui", "sources")}
_ID_RE = re.compile(r"^[a-z0-9_]+$")
_ART_RE = re.compile(r"^[A-Za-z0-9_-]+\.(png|jpg|ttf)$")
_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".ttf": "font/ttf"}


def path_of(srv):
    return os.path.join(srv.CONTENT, REL)


def read(srv):
    """GET /api/wanted."""
    p = path_of(srv)
    if not os.path.isfile(p):
        return {"ok": True, "json": None, "exists": False, "file": srv.rel(p), "mtime": None, "types": TYPES}
    try:
        d = json.loads(cio.read_text(p))
    except (OSError, ValueError) as e:
        return {"ok": False, "error": "%s is not valid JSON: %s" % (srv.rel(p), e), "status": 400}
    return {"ok": True, "json": d, "exists": True, "file": srv.rel(p), "mtime": srv.mtime_of(p), "types": TYPES}


def check(obj):
    """'' when `obj` is a config the game can read, else why not."""
    if not isinstance(obj, dict):
        return "the config is a JSON object"
    tasks = obj.get("tasks")
    if not isinstance(tasks, list):
        return "tasks must be a list"
    seen = set()
    for t in tasks:
        if not isinstance(t, dict):
            return "a task entry is not an object"
        ty = str(t.get("type", ""))
        if ty not in TYPES:
            return "unknown task type %r (one of %s)" % (ty, ", ".join(TYPES))
        if ty in seen:
            return "%s is listed twice" % ty
        seen.add(ty)
        dif = t.get("difficulty")
        if not (isinstance(dif, list) and len(dif) == 2 and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in dif)):
            return "%s: difficulty is two numbers [easy end, hard end]" % ty
        w = t.get("weight", 0)
        if not isinstance(w, (int, float)) or isinstance(w, bool) or w < 0:
            return "%s: weight is a number of 0 or more" % ty
        n = t.get("n")
        if n is not None and not (isinstance(n, list) and all(isinstance(e, list) and len(e) == 2 for e in n)):
            return "%s: n is one [min, max] per stage" % ty
    for k in ("enabled", "creatures_met_only", "items_seen_only"):
        if k in obj and not isinstance(obj[k], bool):
            return "%s is true or false" % k
    for k in ("unlock", "reward", "progress"):
        if k in obj and not isinstance(obj[k], dict):
            return "%s is an object" % k
    cur = (obj.get("reward") or {}).get("currency", "gold")
    if not isinstance(cur, str) or not re.match(r"^[a-z0-9_]+$", cur):
        return "reward.currency is a currency id (gold)"
    return ""


def dump(obj):
    """The file's layout: one top key a line (`tasks` one task a line), keys in the order given, a final newline."""
    def one(v):
        return json.dumps(v, ensure_ascii=False, separators=(", ", ": "))
    keys = list(obj.keys())
    lines = ["{"]
    for i, k in enumerate(keys):
        end = "," if i < len(keys) - 1 else ""
        v = obj[k]
        if k == "tasks" and isinstance(v, list):
            if not v:
                lines.append('  "tasks": []%s' % end)
                continue
            lines.append('  "tasks": [')
            for j, t in enumerate(v):
                lines.append("    %s%s" % (one(t), "," if j < len(v) - 1 else ""))
            lines.append("  ]%s" % end)
        else:
            lines.append("  %s: %s%s" % (json.dumps(k), one(v), end))
    lines.append("}")
    return "\n".join(lines) + "\n"


def save(srv, new_obj, base_mtime=None):
    """POST /api/wanted/save."""
    err = check(new_obj)
    if err:
        return {"ok": False, "error": err, "status": 400}
    p = path_of(srv)
    with srv._write_lock:
        cur = srv.mtime_of(p) if os.path.isfile(p) else None
        if cur is not None and base_mtime is not None and isinstance(base_mtime, (int, float)) and abs(float(base_mtime) - cur) > 0.0015:
            return {"ok": False, "error": "changed on disk", "mtime": cur, "status": 409}
        old = None
        if os.path.isfile(p):
            try:
                old = json.loads(cio.read_text(p))
            except (OSError, ValueError):
                old = None
        merged = srv.restore_numbers(old, new_obj) if isinstance(old, dict) else new_obj
        if isinstance(old, dict) and merged == old:
            return {"ok": True, "unchanged": True, "mtime": cur, "file": srv.rel(p)}
        bk = srv.backup("wanted", p) if os.path.isfile(p) else None
        os.makedirs(os.path.dirname(p), exist_ok=True)
        cio.write_atomic(p, dump(merged))
        mt = srv.mtime_of(p)
    return {"ok": True, "backup": bk, "mtime": mt, "file": srv.rel(p),
            "note": "the game reads the file when it starts: restart it (or ship a build) to play the new board"}


def art_path(srv, folder, name):
    """The file /api/wanted/art/<folder>/<name> names, or None (only the four folders, plain names, png, jpg, ttf)."""
    sub = ART_FOLDERS.get(folder)
    if sub is None or not _ART_RE.match(name or ""):
        return None
    full = os.path.join(srv.GAME, *sub, name)
    return full if os.path.isfile(full) else None


def sources(srv):
    """GET /api/wanted/sources (pass 113, lane TASKS): the power-ups and the structures, with what they do, for the heal
    source tasks (a power-up or a structure whose effect heals; TaskTally.pickup_heals / structure_heals): {ok, pickups
    [{id, name, effect, value, small, credit_stat, hidden, icon}], structures [{id, name, effect, hidden, outcomes,
    per_map, icon}]}."""
    out = {"ok": True, "pickups": [], "structures": []}
    for kind, folder in (("pickups", "pickups"), ("structures", "structures")):
        base = os.path.join(srv.CONTENT, folder)
        if not os.path.isdir(base):
            continue
        for cid in sorted(os.listdir(base)):
            path = os.path.join(base, cid, cid + ".json")
            if not _ID_RE.match(cid) or not os.path.isfile(path):
                continue
            try:
                d = json.loads(cio.read_text(path))
            except (OSError, ValueError):
                continue
            params = d.get("params") if isinstance(d.get("params"), dict) else {}
            rec = {"id": cid, "name": str(d.get("name", cid)), "effect": str(d.get("effect", "")), "hidden": bool(d.get("hidden", False))}
            if kind == "pickups":
                rec.update({"value": d.get("value", 0), "small": bool(params.get("small", False)),
                            "credit_stat": str(params.get("credit_stat", "")), "icon": "/icon/pickup/%s" % cid})
            else:
                outs = params.get("outcomes")
                rec.update({"outcomes": outs if isinstance(outs, list) else None, "per_map": params.get("per_map") if isinstance(params.get("per_map"), dict) else None,
                            "icon": "/api/wanted/structure_icon/%s" % cid})
            out[kind].append(rec)
    return out


def structure_icon(srv, cid):
    """A structure's picture as the game's posters draw it: its painting on the map (game/art/sprites/props/st_<id>.png),
    else its icon (content/structures/<id>/<id>_icon.png, or its JSON's `icon`); None for neither."""
    if not _ID_RE.match(cid or ""):
        return None
    painted = os.path.join(srv.GAME, "art", "sprites", "props", "st_%s.png" % cid)
    if os.path.isfile(painted):
        return painted
    folder = os.path.join(srv.CONTENT, "structures", cid)
    names = [cid + "_icon.png"]
    try:
        d = json.loads(cio.read_text(os.path.join(folder, cid + ".json")))
        if isinstance(d.get("icon"), str) and re.match(r"^[A-Za-z0-9_.-]+\.png$", os.path.basename(d["icon"])):
            names.insert(0, os.path.basename(d["icon"]))
    except (OSError, ValueError):
        pass
    for n in names:
        full = os.path.join(folder, n)
        if os.path.isfile(full):
            return full
    return None


def api_get(handler, srv, parts, query):
    if parts == []:
        return handler._result(read(srv))
    # pass 113 (lane TASKS): the heal sources and a structure's icon
    if parts == ["sources"]:
        return handler._result(sources(srv))
    if len(parts) == 2 and parts[0] == "structure_icon":
        full = structure_icon(srv, parts[1])
        if not full:
            return handler._error(404, "no such icon")
        return handler._file(full, "image/png", cache="max-age=300")
    if len(parts) == 3 and parts[0] == "art":
        full = art_path(srv, parts[1], parts[2])
        if not full:
            return handler._error(404, "no such picture")
        return handler._file(full, _TYPES[os.path.splitext(full)[1].lower()], cache="max-age=300")
    return handler._error(404, "unknown API path")


def api_post(handler, srv, parts):
    data, err = handler._body()
    if err and err != "no body":
        return handler._error(400, err)
    data = data if isinstance(data, dict) else {}
    if parts == ["save"]:
        return handler._result(save(srv, data.get("json"), data.get("base_mtime")))
    return handler._error(404, "unknown API path")

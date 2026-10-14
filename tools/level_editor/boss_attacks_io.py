"""Pass 72, lane BOSS: the Level Editor's routes for the custom boss attacks (content/boss_attacks/<id>/<id>.json, played by
game/core/data/BossAttackDef.gd and EnemyManager's custom-attack runner; Garry: "add the ability to create custom attacks
for bosses. Like colouring the projectile, deciding the ranges, etc. Like create custom ones that I can name").

server.py hands every /api/boss_attacks request here with itself as `srv` (its CONTENT, BACKUPS, GODOT, run_import,
backup, the write lock), so a selftest that points those at a temporary copy tests these routes on it too.

  GET  /api/boss_attacks                 every attack (its JSON, file, mtime, the creatures whose script names it), the
                                         creatures with a script (bosses first), the built-in names, the kinds, the sounds
  POST /api/boss_attacks/new             {id, name, template (an attack id) | kind}: a new attack from a template or a blank
  POST /api/boss_attacks/<id>/save       {json, base_mtime}: the whole attack back (key by key in place; a 409 when the
                                         file changed on disk since the page read it), then the JSON -> .tres import
  POST /api/boss_attacks/<id>/assign     {creature, on}: add {"name": id} to (or take every entry of it out of) that
                                         creature's boss.attacks, then its import
  POST /api/boss_attacks/<id>/delete     {cascade}: refused while a script names it unless cascade (then it leaves those
                                         scripts first); the folder is moved to the backups, never deleted outright
"""
import json
import os
import shutil
import time

import content_io as cio

FOLDER = "boss_attacks"
KINDS = ["rain", "volley", "ring", "slam", "script"]
# BossAttackDef.SCRIPTS: the built-in attack names (EnemyManager's runner); a custom attack never takes one as its id
BUILTINS = ["roll", "spawn_ring", "slam_at", "blink", "burrow", "rain", "erupt", "spit_volley", "slam", "rumble",
            "brand", "tumbleweed_volley", "swoop", "boulder"]
# BossAttackDef.DEFAULTS (selftest_BOSS.py checks all three tables against the GDScript)
DEFAULTS = {
    "projectile": {"look": "spike", "tint": "#D0242F", "size": 1.0, "glow": 1.0, "flight": 1.0, "arc": 6.0, "speed": 12.0,
                   "range": 18.0, "hit_radius": 0.5, "trail": True},
    "pattern": {"shape": "rings", "center": "boss", "radius_min": 3.0, "radius_max": 16.0, "spacing": 3.2, "count": 0,
                "jitter": 0.2, "gap": 1.0, "turn": True, "order": "out", "spread_deg": 360.0, "aim": "hero", "waves": 1,
                "wave_gap": 0.5, "width": 1.2},
    "landing": {"radius": 0.9, "mode": "stagger"},
    "telegraph": {"kind": "circles", "color": "#ED4A5C", "seconds": 0.9, "all_at_once": False},
    "timing": {"windup": 1.0, "stagger": 1.5, "cooldown": 0.0, "hold": -1.0},
    "sounds": {"windup": "", "fire": "en_boss_attack", "land": ""},
    "spew": {"crouch": 0.35, "burst": 0.12, "mouth": 0.62, "squash": 0.82, "stretch": 1.25},
}
# the creature folders whose JSON may carry a script (boss.attacks)
SCRIPTED = (("boss", "bosses"), ("enemy", "enemies"))


def _dir(srv):
    return os.path.join(srv.CONTENT, FOLDER)


def _path(srv, aid):
    return os.path.join(_dir(srv), aid, aid + ".json")


def _read(path):
    try:
        src = cio.read_text(path)
        return src, json.loads(src)
    except (OSError, ValueError):
        return None, None


def _names(d):
    boss = d.get("boss") if isinstance(d.get("boss"), dict) else {}
    out = []
    for a in boss.get("attacks", []) if isinstance(boss.get("attacks"), list) else []:
        if isinstance(a, dict) and a.get("name"):
            out.append(str(a["name"]))
    return out


def creatures(srv):
    """Every creature whose JSON has a boss block (the bosses, then the scripted Elites and casters): what the Boss attacks
    tab assigns to. [{id, name, kind, archetype, attacks (names), damage, radius, size, file, mtime}]"""
    out = []
    for kind, folder in SCRIPTED:
        base = os.path.join(srv.CONTENT, folder)
        if not os.path.isdir(base):
            continue
        for cid in sorted(os.listdir(base)):
            path = os.path.join(base, cid, cid + ".json")
            if not os.path.isfile(path) or not srv.ID_RE.match(cid) or cid.startswith("training_dummy"):
                continue
            _, d = _read(path)
            if not isinstance(d, dict) or (kind == "enemy" and not isinstance(d.get("boss"), dict)):
                continue
            out.append({"id": cid, "name": str(d.get("name", cid)), "kind": kind, "archetype": str(d.get("archetype", "")),
                        "attacks": _names(d), "damage": d.get("damage", 0), "radius": d.get("radius", 0.5),
                        "size": d.get("size", 1.0), "hidden": bool(d.get("hidden", False)),
                        "file": srv.rel(path), "mtime": srv.mtime_of(path)})
    return out


def _sounds(srv):
    path = os.path.join(srv.CONTENT, "sounds", "soundmap.json")
    _, d = _read(path)
    s = d.get("sounds") if isinstance(d, dict) else None
    return sorted(s.keys()) if isinstance(s, dict) else []


def list_all(srv):
    """GET /api/boss_attacks."""
    crs = creatures(srv)
    attacks = []
    base = _dir(srv)
    if os.path.isdir(base):
        for aid in sorted(os.listdir(base)):
            path = _path(srv, aid)
            if not os.path.isfile(path):
                continue
            src, d = _read(path)
            if not isinstance(d, dict):
                attacks.append({"id": aid, "name": aid, "kind": "?", "file": srv.rel(path), "mtime": srv.mtime_of(path),
                                "json": None, "error": "not valid JSON", "used_by": []})
                continue
            attacks.append({"id": aid, "name": str(d.get("name", aid)), "kind": str(d.get("kind", "rain")),
                            "doc": str(d.get("doc", "")), "file": srv.rel(path), "mtime": srv.mtime_of(path), "json": d,
                            "tres": os.path.isfile(os.path.join(base, aid, aid + ".tres")),
                            "used_by": [c["id"] for c in crs if aid in c["attacks"]]})
    return {"ok": True, "attacks": attacks, "creatures": crs, "builtins": BUILTINS, "kinds": KINDS, "defaults": DEFAULTS,
            "sounds": _sounds(srv)}


def _id_taken(srv, aid):
    """Where `aid` is already an id (any content type, or a built-in attack name), or ''."""
    if aid in BUILTINS:
        return "a built-in attack's name"
    for t in list(srv.ALL_TYPES) + [FOLDER]:
        if os.path.isdir(os.path.join(srv.CONTENT, t, aid)):
            return "content/%s/%s" % (t, aid)
    return ""


def _check(srv, aid, obj):
    if not isinstance(obj, dict):
        return "the body's json must be the whole attack"
    if str(obj.get("id", aid)) != aid:
        return "the body's id does not match the attack"
    if str(obj.get("kind", "rain")) not in KINDS:
        return "unknown kind %s (%s)" % (obj.get("kind"), ", ".join(KINDS))
    if obj.get("kind") == "script" and str(obj.get("script", "")) not in BUILTINS:
        return "a script attack names one of the built-in attacks (%s)" % ", ".join(BUILTINS)
    return ""


def blank(kind, aid, name):
    """A new attack of `kind` with the game's defaults spelt out (boss_model.js blank() makes the same)."""
    k = kind if kind in KINDS else "rain"
    a = {"id": aid, "name": name or aid, "doc": "", "kind": k}
    if k == "script":
        a.update({"script": "slam", "params": {"windup": 1.0, "radius": 6.0, "damage": 30, "knockback": 6, "telegraph": "ring"}})
        return a
    a["projectile"] = dict(DEFAULTS["projectile"])
    a["pattern"] = dict(DEFAULTS["pattern"])
    if k == "rain":
        a["landing"] = dict(DEFAULTS["landing"])
        # pass 73 (lane GROUND): a volley rain's spew (boss_model.js blank() makes the same)
        a["spew"] = dict(DEFAULTS["spew"])
    a["telegraph"] = dict(DEFAULTS["telegraph"], kind="circles" if k == "rain" else "lines" if k == "volley" else "ring")
    a.update({"damage": 0.75, "knockback": 4.0, "lift": 0.0})
    a["timing"] = dict(DEFAULTS["timing"])
    a["sounds"] = dict(DEFAULTS["sounds"])
    if k == "volley":
        a["pattern"].update({"count": 12, "spread_deg": 360, "waves": 2, "wave_gap": 0.5})
    if k == "ring":
        a["pattern"].update({"radius_max": 14, "width": 1.2, "count": 2, "wave_gap": 0.8})
    if k == "slam":
        a["pattern"].update({"radius_max": 6})
    return a


def create(srv, aid, name="", template="", kind="rain"):
    """POST /api/boss_attacks/new: a copy of the attack `template` (its id and name replaced) or a blank of `kind`."""
    aid = str(aid or "")
    if not srv.ID_RE.match(aid) or not aid[:1].isalpha():
        return {"ok": False, "error": "the id is lower-case letters, digits and _, starting with a letter", "status": 400}
    taken = _id_taken(srv, aid)
    if taken:
        return {"ok": False, "error": "%s is taken (%s)" % (aid, taken), "status": 409}
    if template:
        _, t = _read(_path(srv, str(template)))
        if not isinstance(t, dict):
            return {"ok": False, "error": "no attack %s to copy" % template, "status": 404}
        obj = {}
        for k, v in t.items():
            obj[k] = aid if k == "id" else (name or "%s (copy)" % t.get("name", template)) if k == "name" else json.loads(json.dumps(v))
    else:
        obj = blank(kind, aid, name)
    path = _path(srv, aid)
    with srv._write_lock:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        cio.write_atomic(path, cio.dump_new(obj))
    ok, out = srv.run_import("%s/%s" % (FOLDER, aid))
    return {"ok": True, "id": aid, "json": obj, "mtime": srv.mtime_of(path), "file": srv.rel(path), "import_ok": ok, "output": out}


def save(srv, aid, new_obj, base_mtime=None):
    """POST /api/boss_attacks/<id>/save: key by key in place (a changed key's span rewritten, the file's floats kept, a
    removed key's lines gone, a new key after the one before it), one backup, one write, then the import."""
    err = _check(srv, aid, new_obj)
    if err:
        return {"ok": False, "error": err, "status": 400}
    path = _path(srv, aid)
    with srv._write_lock:
        if not os.path.isfile(path):
            return {"ok": False, "error": "no attack %s (make it with New first)" % aid, "status": 404}
        cur = srv.mtime_of(path)
        if base_mtime is not None and isinstance(base_mtime, (int, float)) and abs(float(base_mtime) - cur) > 0.0015:
            return {"ok": False, "error": "changed on disk", "mtime": cur, "status": 409}
        src = cio.read_text(path)
        old = json.loads(src)
        changed = [k for k in new_obj if k not in old or srv.restore_numbers(old[k], new_obj[k]) != old[k]]
        removed = [k for k in old if k not in new_obj]
        if not changed and not removed:
            return {"ok": True, "unchanged": True, "changed": [], "removed": [], "mtime": cur, "import_ok": True,
                    "output": "nothing changed: nothing written"}
        text = src
        for k in removed:
            text = cio.del_top_block(text, k)
            if text is None:
                return {"ok": False, "error": "%s cannot be edited line by line (key %s)" % (srv.rel(path), k), "status": 400}
        keys_new = list(new_obj.keys())
        for k in [k for k in old if k in changed]:
            text = cio.set_top_block(text, k, srv.restore_numbers(old[k], new_obj[k]))
            if text is None:
                return {"ok": False, "error": "%s cannot be edited line by line (key %s)" % (srv.rel(path), k), "status": 400}
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
                return {"ok": False, "error": "%s cannot be edited line by line (new key %s)" % (srv.rel(path), k), "status": 400}
            present.append(k)
        bk = srv.backup(aid, path)
        cio.write_atomic(path, text)
        mt = srv.mtime_of(path)
    ok, out = srv.run_import("%s/%s" % (FOLDER, aid))
    return {"ok": True, "changed": changed, "removed": removed, "backup": bk, "mtime": mt, "import_ok": ok, "output": out}


def _creature_path(srv, cid):
    for kind, folder in SCRIPTED:
        path = os.path.join(srv.CONTENT, folder, cid, cid + ".json")
        if os.path.isfile(path):
            return kind, folder, path
    return None, None, None


def _set_script(srv, cid, fn):
    """The creature `cid`'s boss.attacks list through `fn(list) -> list`, written as one key in place (backup, import)."""
    kind, folder, path = _creature_path(srv, cid)
    if path is None:
        return {"ok": False, "error": "no creature %s under content/bosses or content/enemies" % cid, "status": 404}
    with srv._write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        boss = d.get("boss") if isinstance(d.get("boss"), dict) else {}
        boss = json.loads(json.dumps(boss))
        before = list(boss.get("attacks", [])) if isinstance(boss.get("attacks"), list) else []
        after = fn(before)
        if after == before:
            return {"ok": True, "unchanged": True, "attacks": _names(d), "mtime": srv.mtime_of(path)}
        boss["attacks"] = after
        places = [("before", "sfx"), ("end", None)] if "boss" not in d else ()
        text = cio.set_top_block(src, "boss", srv.restore_numbers(d.get("boss", {}), boss) if "boss" in d else boss, places)
        if text is None:
            return {"ok": False, "error": "%s cannot be edited line by line" % srv.rel(path), "status": 400}
        bk = srv.backup(cid, path)
        cio.write_atomic(path, text)
        mt = srv.mtime_of(path)
        names = _names(json.loads(text))
    ok, out = srv.run_import("%s/%s" % (folder, cid))
    return {"ok": True, "attacks": names, "backup": bk, "mtime": mt, "import_ok": ok, "output": out, "creature": cid}


def assign(srv, aid, cid, on):
    """POST /api/boss_attacks/<id>/assign: `on` appends {"name": aid} to the creature's script (once); off takes every
    entry naming it out."""
    if not os.path.isfile(_path(srv, aid)):
        return {"ok": False, "error": "no attack %s (save it first)" % aid, "status": 404}
    if not isinstance(cid, str) or not srv.ID_RE.match(cid):
        return {"ok": False, "error": "bad creature id", "status": 400}

    def change(lst):
        has = any(isinstance(a, dict) and a.get("name") == aid for a in lst)
        if on:
            return lst if has else lst + [{"name": aid}]
        return [a for a in lst if not (isinstance(a, dict) and a.get("name") == aid)]
    return _set_script(srv, cid, change)


def delete(srv, aid, cascade=False):
    """POST /api/boss_attacks/<id>/delete: refused while a creature's script names it, unless `cascade` (it leaves those
    scripts first); the folder goes to the backups (backups/boss_attacks/<id>-<stamp>/), never deleted outright."""
    folder = os.path.dirname(_path(srv, aid))
    if not os.path.isdir(folder):
        return {"ok": False, "error": "no attack %s" % aid, "status": 404}
    users = [c["id"] for c in creatures(srv) if aid in c["attacks"]]
    if users and not cascade:
        return {"ok": False, "error": "%s is in the script of %s: take it out first, or delete with cascade" % (aid, ", ".join(users)),
                "used_by": users, "status": 409}
    left = []
    for cid in users:
        res = assign(srv, aid, cid, False)
        if not res.get("ok"):
            return {"ok": False, "error": "could not take it out of %s: %s" % (cid, res.get("error")), "status": 400}
        left.append(cid)
    dest_root = os.path.join(srv.BACKUPS, FOLDER)
    os.makedirs(dest_root, exist_ok=True)
    dest = os.path.join(dest_root, "%s-%s" % (aid, time.strftime("%Y%m%d-%H%M%S")))
    with srv._write_lock:
        shutil.move(folder, dest)
    return {"ok": True, "deleted": aid, "moved_to": srv.rel(dest), "left": left}


def api_get(handler, srv, parts, query):
    if parts == []:
        return handler._send(200, list_all(srv))
    return handler._error(404, "unknown API path")


def api_post(handler, srv, parts):
    data, err = handler._body()
    if err and err != "no body":
        return handler._error(400, err)
    data = data if isinstance(data, dict) else {}
    if parts == ["new"]:
        return handler._result(create(srv, data.get("id"), str(data.get("name", "")), str(data.get("template", "") or ""),
                                      str(data.get("kind", "rain"))))
    if len(parts) == 2:
        aid, op = parts
        if not srv.ID_RE.match(aid):
            return handler._error(400, "bad id")
        if op == "save":
            return handler._result(save(srv, aid, data.get("json"), data.get("base_mtime")))
        if op == "assign":
            return handler._result(assign(srv, aid, data.get("creature"), bool(data.get("on", True))))
        if op == "delete":
            return handler._result(delete(srv, aid, bool(data.get("cascade", False))))
    return handler._error(404, "unknown API path")

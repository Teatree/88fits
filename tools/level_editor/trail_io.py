"""Pass 129, lane TRAIL-EDITOR: the Level Editor's routes for the Trail (game/content/trail/trail.json, read by
game/core/systems/Trail.gd at run time; plain JSON, no .tres, so a save needs no import; docs/trail_schema.md).

server.py hands every /api/trail request here with itself as `srv` (its CONTENT, GAME, backup, restore_numbers, the
write lock), so a selftest that points those at a temporary copy tests these routes on it too.

  GET  /api/trail               {ok, json, file, mtime, exists, picks}: the file as on disk and the pick lists the
                                tab's cells and checks use: outlaws, skins ("<outlaw>:<CODE>"), weapons, passives (mark
                                card | item), maps with their stages, structures, powerups, features, icons (the files
                                in game/art/ui/trail/ without .png), stats (the player stat names), currencies, motifs
  GET  /api/trail/icon/<name>   an upgrade type's icon, game/art/ui/trail/<name>.png
  POST /api/trail/save          {json, base_mtime}: the whole file back (a 409 when it changed on disk since the page
                                read it), checked (the shape the game reads; the page's own checks are trail_model.js),
                                one backup, one atomic write with LF, keys in the order sent, the file's floats kept
                                (a 2.0 the page sent back as 2 is written 2.0 again)

As a command (the same checks the page shows, for a lane or a script that wrote the file):
  python tools/level_editor/trail_io.py --check [path/to/trail.json]      needs Node; exit 1 on an error
"""
import json
import os
import re
import sys

import content_io as cio

REL = os.path.join("trail", "trail.json")
ICONS = ("art", "ui", "trail")
KINDS = ("node", "choice", "optional")
GIVES = ("upgrade", "outlaw", "skin", "weapon", "passive", "stage", "map", "structure", "powerup", "feature")
VALUE_KINDS = ("percent", "flat", "count", "seconds", "word")
MOTIFS = ["cactus", "star", "skull", "horseshoe", "moon", "flame", "dust", "none"]
FEATURES = ["wanted"]
_ID_RE = re.compile(r"^[a-z0-9_]+$")
_NODE_ID_RE = re.compile(r"^[A-Za-z0-9_]+$")
_ICON_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def path_of(srv):
    return os.path.join(srv.CONTENT, REL)


def _num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def _folders(srv, kind):
    """(id, its JSON as a dict) for every content folder of `kind` that holds a readable <id>.json."""
    base = os.path.join(srv.CONTENT, kind)
    for cid in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        path = os.path.join(base, cid, cid + ".json")
        if not _ID_RE.match(cid) or not os.path.isfile(path):
            continue
        try:
            d = json.loads(cio.read_text(path))
        except (OSError, ValueError):
            continue
        if isinstance(d, dict):
            yield cid, d


def stat_names(srv):
    """The player stats a Trail effect may name: the editor's own table (vocab.py) and whatever StatSheet.gd's
    PLAYER_DEFAULTS lists now (a stat another lane just added shows up without a vocab edit)."""
    names = set()
    try:
        import vocab
        names.update(vocab.PLAYER_DEFAULTS)
        names.update(vocab.PLAYER_STATS_EXTRA)
    except Exception:   # noqa: BLE001  (the list is a help, never a reason to fail the route)
        pass
    game = getattr(srv, "GAME", None) or os.path.dirname(srv.CONTENT)
    try:
        src = cio.read_text(os.path.join(game, "core", "systems", "StatSheet.gd"))
        m = re.search(r"const\s+PLAYER_DEFAULTS\s*:?=\s*\{(.*?)\n\}", src, re.S)
        if m:
            names.update(re.findall(r'"([a-z0-9_]+)"\s*:', m.group(1)))
    except OSError:
        pass
    return sorted(names)


def icon_names(srv):
    game = getattr(srv, "GAME", None) or os.path.dirname(srv.CONTENT)
    base = os.path.join(game, *ICONS)
    if not os.path.isdir(base):
        return []
    return sorted(f[:-4] for f in os.listdir(base) if f.endswith(".png") and _ICON_RE.match(f[:-4]))


def picks(srv):
    """The lists a node's gift is picked from, each entry {id, name, icon, ...}."""
    out = {"outlaws": [], "skins": [], "weapons": [], "passives": [], "maps": [], "structures": [], "powerups": [],
           "features": list(FEATURES), "icons": icon_names(srv), "stats": stat_names(srv), "currencies": [],
           "motifs": list(MOTIFS)}
    for cid, d in _folders(srv, "characters"):
        name = str(d.get("name", cid))
        hidden = bool(d.get("hidden", False)) or d.get("availability") == "hidden"
        out["outlaws"].append({"id": cid, "name": name, "icon": "/icon/hero/%s" % cid, "hidden": hidden,
                               "availability": str(d.get("availability", "available")), "price": d.get("price")})
        for code, entry in (d.get("variants") or {}).items() if isinstance(d.get("variants"), dict) else []:
            skin = entry.get("skin") if isinstance(entry, dict) else None
            if not isinstance(skin, dict):
                continue
            out["skins"].append({"id": "%s:%s" % (cid, code), "outlaw": cid, "code": code, "hidden": hidden,
                                 "name": "%s, %s" % (name, skin.get("name") or code), "icon": "/icon/hero/%s/%s" % (cid, code)})
    for cid, d in _folders(srv, "weapons"):
        out["weapons"].append({"id": cid, "name": str(d.get("name", cid)), "icon": "/icon/weapon/%s" % cid, "hidden": bool(d.get("hidden", False))})
    for cid, d in _folders(srv, "passives"):
        out["passives"].append({"id": cid, "name": str(d.get("name", cid)), "icon": "/icon/passive/%s" % cid,
                                "mark": "card" if d.get("line") else "item", "evolved": bool(d.get("evolves_from")),
                                "hidden": bool(d.get("hidden", False))})
    out["passives"].sort(key=lambda p: (p["evolved"], p["mark"], p["name"].lower()))
    for cid, d in _folders(srv, "maps"):
        tl = d.get("timeline_data") if isinstance(d.get("timeline_data"), dict) else {}
        stages = []
        for k, s in enumerate(tl.get("stage_list") or []):
            if isinstance(s, dict) and s.get("id"):
                sid = str(s["id"])
                pic = "%s_%s.jpg" % (cid, sid)
                game = getattr(srv, "GAME", None) or os.path.dirname(srv.CONTENT)
                has = os.path.isfile(os.path.join(game, "art", "ui", "stages", pic))
                stages.append({"id": sid, "name": str(s.get("name", sid)), "index": k,
                               "icon": ("/api/wanted/art/stages/%s" % pic) if has else None})
        out["maps"].append({"id": cid, "name": str(d.get("name", cid)), "stages": stages, "icon": stages[0]["icon"] if stages else None})
    for cid, d in _folders(srv, "structures"):
        out["structures"].append({"id": cid, "name": str(d.get("name", cid)), "icon": "/api/wanted/structure_icon/%s" % cid, "hidden": bool(d.get("hidden", False))})
    for cid, d in _folders(srv, "pickups"):
        out["powerups"].append({"id": cid, "name": str(d.get("name", cid)), "icon": "/icon/pickup/%s" % cid, "hidden": bool(d.get("hidden", False))})
    out["currencies"] = [cid for cid, _ in _folders(srv, "currencies")] or ["gold"]
    return out


def read(srv):
    """GET /api/trail."""
    p = path_of(srv)
    base = {"ok": True, "file": srv.rel(p), "picks": picks(srv)}
    if not os.path.isfile(p):
        return dict(base, json=None, exists=False, mtime=None)
    try:
        d = json.loads(cio.read_text(p))
    except (OSError, ValueError) as e:
        return {"ok": False, "error": "%s is not valid JSON: %s" % (srv.rel(p), e), "status": 400}
    return dict(base, json=d, exists=True, mtime=srv.mtime_of(p))


def check(obj):
    """'' when `obj` has the shape the game reads, else why not (the first fault). The rules a designer breaks (a level
    without a required node, a node out of reach...) are the page's checks, trail_model.js `check`."""
    if not isinstance(obj, dict):
        return "the Trail is a JSON object"
    pr = obj.get("price")
    if not isinstance(pr, dict) or not all(_num(pr.get(k)) for k in ("base", "k", "power", "round")):
        return "price is {base, k, power, round}, four numbers"
    if not isinstance(obj.get("currency"), str) or not _ID_RE.match(obj["currency"]):
        return "currency is a currency id (gold)"
    secs = obj.get("sections")
    if not isinstance(secs, list) or not all(isinstance(s, dict) and isinstance(s.get("from"), int) and not isinstance(s.get("from"), bool) for s in secs):
        return "sections is a list of {from, name, top, bottom, motif}"
    ups = obj.get("upgrades")
    if not isinstance(ups, dict):
        return "upgrades is an object, one entry per upgrade type"
    for t, u in ups.items():
        if not isinstance(u, dict) or u.get("kind") not in VALUE_KINDS:
            return "upgrade type %s: kind is one of %s" % (t, ", ".join(VALUE_KINDS))
        for e in u.get("effects") or []:
            if not isinstance(e, dict) or not e.get("stat") or e.get("op") not in ("add", "mul") or not _num(e.get("per")):
                return "upgrade type %s: every effect needs stat, op (add, mul) and a number per" % t
    nodes = obj.get("nodes")
    if not isinstance(nodes, list):
        return "nodes is a list"
    seen = set()
    for i, n in enumerate(nodes):
        if not isinstance(n, dict):
            return "node %d is not an object" % (i + 1)
        nid = n.get("id")
        if not isinstance(nid, str) or not _NODE_ID_RE.match(nid):
            return "node %d needs an id (letters, digits, _)" % (i + 1)
        if nid in seen:
            return "two nodes share the id %s" % nid
        seen.add(nid)
        if not isinstance(n.get("level"), int) or isinstance(n.get("level"), bool) or n["level"] < 1:
            return "%s: level is a whole number, 1 or more" % nid
        if n.get("kind") not in KINDS:
            return "%s: kind is node, choice or optional" % nid
        g = n.get("gives")
        if not isinstance(g, dict) or g.get("type") not in GIVES:
            return "%s: gives.type is one of %s" % (nid, ", ".join(GIVES))
        if g["type"] == "upgrade" and g.get("upgrade") not in ups:
            return "%s: unknown upgrade type %r" % (nid, g.get("upgrade"))
        if "from" in n and not (isinstance(n["from"], list) and all(isinstance(f, str) for f in n["from"])):
            return "%s: from is a list of node ids" % nid
        for k in ("price", "price_mult", "x"):
            if k in n and not _num(n[k]):
                return "%s: %s is a number" % (nid, k)
    end = obj.get("end")
    if end is not None and not isinstance(end, dict):
        return "end is {text}"
    return ""


def _one(v):
    return json.dumps(v, ensure_ascii=False, separators=(", ", ": "))


def dump(obj):
    """The file's layout: two spaces, keys in the order given, LF, a final newline; `sections` one section a line,
    `upgrades` one type a line and `nodes` one node a line, so a changed node is a one-line diff among hundreds."""
    keys = list(obj.keys())
    lines = ["{"]
    for i, k in enumerate(keys):
        end = "," if i < len(keys) - 1 else ""
        v = obj[k]
        if k in ("nodes", "sections") and isinstance(v, list) and v:
            lines.append("  %s: [" % json.dumps(k))
            for j, item in enumerate(v):
                lines.append("    %s%s" % (_one(item), "," if j < len(v) - 1 else ""))
            lines.append("  ]%s" % end)
        elif k == "upgrades" and isinstance(v, dict) and v:
            lines.append('  "upgrades": {')
            names = list(v.keys())
            for j, t in enumerate(names):
                lines.append("    %s: %s%s" % (json.dumps(t, ensure_ascii=False), _one(v[t]), "," if j < len(names) - 1 else ""))
            lines.append("  }%s" % end)
        else:
            lines.append("  %s: %s%s" % (json.dumps(k), _one(v), end))
    lines.append("}")
    return "\n".join(lines) + "\n"


def save(srv, new_obj, base_mtime=None):
    """POST /api/trail/save."""
    err = check(new_obj)
    if err:
        return {"ok": False, "error": err, "status": 400}
    p = path_of(srv)
    with srv._write_lock:
        cur = srv.mtime_of(p) if os.path.isfile(p) else None
        if cur is not None and base_mtime is not None and _num(base_mtime) and abs(float(base_mtime) - cur) > 0.0015:
            return {"ok": False, "error": "changed on disk", "mtime": cur, "status": 409}
        old = None
        if os.path.isfile(p):
            try:
                old = json.loads(cio.read_text(p))
            except (OSError, ValueError):
                old = None
        merged = srv.restore_numbers(old, new_obj) if isinstance(old, dict) else new_obj
        if isinstance(old, dict) and merged == old and list(merged.keys()) == list(old.keys()) \
                and [n.get("id") for n in merged["nodes"]] == [n.get("id") for n in old.get("nodes") or [] if isinstance(n, dict)]:
            return {"ok": True, "unchanged": True, "mtime": cur, "file": srv.rel(p)}
        bk = srv.backup("trail", p) if os.path.isfile(p) else None
        os.makedirs(os.path.dirname(p), exist_ok=True)
        cio.write_atomic(p, dump(merged))
        mt = srv.mtime_of(p)
    return {"ok": True, "backup": bk, "mtime": mt, "file": srv.rel(p), "nodes": len(merged["nodes"]),
            "note": "the game reads the file when it starts: restart it (or ship a build) to play the new Trail"}


def icon_path(srv, name):
    """The file /api/trail/icon/<name> names (a plain name, with or without .png), or None."""
    name = name[:-4] if name.endswith(".png") else name
    if not _ICON_RE.match(name or ""):
        return None
    game = getattr(srv, "GAME", None) or os.path.dirname(srv.CONTENT)
    full = os.path.join(game, *ICONS, name + ".png")
    return full if os.path.isfile(full) else None


def api_get(handler, srv, parts, query):
    if parts == []:
        return handler._result(read(srv))
    if len(parts) == 2 and parts[0] == "icon":
        full = icon_path(srv, parts[1])
        if not full:
            return handler._error(404, "no such icon")
        return handler._file(full, "image/png", cache="max-age=30")
    return handler._error(404, "unknown API path")


def api_post(handler, srv, parts):
    data, err = handler._body()
    if err and err != "no body":
        return handler._error(400, err)
    data = data if isinstance(data, dict) else {}
    if parts == ["save"]:
        return handler._result(save(srv, data.get("json"), data.get("base_mtime")))
    return handler._error(404, "unknown API path")


def _main(argv):
    """--check [file]: the page's checks (trail_model.js under Node) with the pick lists read from the content folders."""
    import shutil
    import subprocess
    import tempfile
    import threading
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))

    class _Srv:
        GAME = os.path.join(root, "game")
        CONTENT = os.path.join(root, "game", "content")
        _write_lock = threading.Lock()

        @staticmethod
        def rel(p):
            return os.path.relpath(p, root).replace("\\", "/")

    if not argv or argv[0] != "--check":
        print(__doc__)
        return 2
    node = shutil.which("node")
    if not node:
        print("node is not here: the checks live in trail_model.js")
        return 2
    target = argv[1] if len(argv) > 1 else path_of(_Srv)
    try:
        shape = check(json.loads(cio.read_text(target)))
    except (OSError, ValueError) as e:
        print("ERROR %s: %s" % (target, e))
        return 1
    if shape:
        print("ERROR (the shape the game reads) %s" % shape)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(picks(_Srv), f)
    try:
        r = subprocess.run([node, os.path.join(here, "trail_model.js"), target, f.name], capture_output=True, text=True, encoding="utf-8")
    finally:
        os.remove(f.name)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    return 1 if (shape or r.returncode) else 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))

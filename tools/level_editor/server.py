#!/usr/bin/env python3
"""The Level Editor's local server (pass 53).

    python tools/level_editor/server.py [--port 8787] [--no-browser]

Serves this folder (index.html, the scripts, the styles) on 127.0.0.1 and a small JSON API over the content folders:

    GET  /api/maps                 the maps: [{id, name, file}]
    GET  /api/map/<id>             the whole map JSON (the page edits `timeline_data`, every other key rides along)
    POST /api/map/<id>             the whole map JSON back: a backup, a pretty write, then the JSON -> .tres import
    GET  /api/enemies              every creature of content/enemies and content/bosses (the palette)
    GET  /api/elites               the elite modifiers [{id, name}]
    GET  /api/pickups              the power-ups [{id, name, small}]
    GET  /api/schema               docs/waves_schema.md as text (the Instructions tab)
    GET  /icon/<kind>/<id>[/<code>]  a creature's icon PNG (kind enemy|boss|elite|pickup; code = an art variant)
    POST /api/enemy/<id>/variant   {"code": "SK-B"}: the creature's default look (pass 54): its JSON's top-level
                                   `variant`, after a backup, then the JSON -> .tres import of that one creature

Garry (the user) is not a programmer, so the server stays plain: the standard library only, nothing installed, nothing
fetched from the internet. It writes exactly two kinds of thing: the map JSON it was asked to save, and (pass 54) the
one key `variant` of a creature JSON when the Creatures tab sets a default look; both after a backup under
tools/level_editor/backups/, and nothing else. The import is the same command CLAUDE.md gives for a hand edit:
    Godot --headless --path game --script res://tools/import_json.gd -- only=maps/<id>   (or only=enemies/<id>)
"""
import argparse
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")
GODOT = os.path.join(ROOT, "Godot_v4.7.2-stable_win64", "Godot_v4.7.2-stable_win64.exe")
BACKUPS = os.path.join(HERE, "backups")
SCHEMA = os.path.join(ROOT, "docs", "waves_schema.md")
KEEP_BACKUPS = 30
IMPORT_TIMEOUT = 120
ID_RE = re.compile(r"^[a-z0-9_]+$")
CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")
STATIC_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".md": "text/markdown; charset=utf-8",
    ".json": "application/json; charset=utf-8",
}
# the folders the API reads, by the kind the page names
KIND_FOLDERS = {"enemy": "enemies", "boss": "bosses", "elite": "elites", "pickup": "pickups"}

_write_lock = threading.Lock()


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


def creature_record(kind, cid, folder, d):
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
    variants = []
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    base_code = str(d.get("variant_base", ""))
    playable = playable_codes(folder, d)
    if base_code and base_code not in vs:
        # the top-level strip is a look of its own even when the JSON gives it no entry (JsonContent adds it)
        variants.append({"code": base_code, "note": "the top-level strip", "icon": "/icon/%s/%s/%s" % (kind, cid, base_code),
                         "ready": True, "base": True})
    for code, entry in vs.items():
        entry = entry if isinstance(entry, dict) else {}
        variants.append({"code": str(code), "note": str(entry.get("note", "")),
                         "icon": "/icon/%s/%s/%s" % (kind, cid, code),
                         # `ready`: the game can play it (the base strip, or an entry whose strip is on disk); a code
                         # still waiting for its painting falls back to the base in play
                         "ready": str(code) in playable, "base": str(code) == base_code})
    # pass 54: the icon the game shows is the in-play variant's (JsonContent.build swaps it in after _common), so the
    # page gets that one as `icon_play` beside the top-level `icon`; nine creatures differ (the skeleton plays SK-A).
    # `play` is the code the game really plays: the JSON's `variant` when it can, else the base strip's
    want = str(d.get("variant", base_code))
    play = want if want in playable else base_code
    icon_play = "/icon/%s/%s/%s" % (kind, cid, play) if play and play in vs else "/icon/%s/%s" % (kind, cid)
    variance = d.get("variance") if isinstance(d.get("variance"), dict) else {}
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
        "variants": variants,
        "icon": "/icon/%s/%s" % (kind, cid),
        "icon_play": icon_play,
    }


def playable_codes(folder, d):
    """The art variant codes the game can play for this creature JSON (JsonContent._enemy): the base strip's code
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


def resolve_file(folder, name):
    """A content file named in a JSON: res:// under game/, else beside the JSON; None when it is not on disk."""
    if name.startswith("res://"):
        full = os.path.join(GAME, name[len("res://"):].replace("/", os.sep))
    else:
        full = os.path.join(folder, os.path.basename(name))
    return full if os.path.isfile(full) else None


def list_creatures():
    out = []
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
            out.append(creature_record(kind, cid, folder, d))
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


def icon_path(kind, cid, code):
    """The PNG of a creature's icon, or of one of its art variants: the variant entry's `icon` file when it has one, else
    the JSON's top-level `icon`, else <id>_icon.png (the game's own order, JsonContent.build; pass 54 added the middle
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


# ---------------------------------------------------------------- writing a map

def restore_numbers(old, new):
    """The page's JavaScript turns 1.0 into 1 (it has one number type), so the write puts the float back wherever the file
    on disk had one at the same place (a dict key, a list index, a wave matched by its id). Numbers that are new stay as
    the page sent them."""
    if isinstance(old, bool) or isinstance(new, bool):
        return new
    if isinstance(old, float) and isinstance(new, int):
        return float(new)
    if isinstance(old, dict) and isinstance(new, dict):
        return {k: (restore_numbers(old[k], v) if k in old else v) for k, v in new.items()}
    if isinstance(old, list) and isinstance(new, list):
        by_id = {}
        for o in old:
            if isinstance(o, dict) and isinstance(o.get("id"), str):
                by_id.setdefault(o["id"], o)
        out = []
        for i, v in enumerate(new):
            if isinstance(v, dict) and isinstance(v.get("id"), str) and v["id"] in by_id:
                out.append(restore_numbers(by_id[v["id"]], v))
            elif i < len(old):
                out.append(restore_numbers(old[i], v))
            else:
                out.append(v)
        return out
    return new


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


def run_import(target):
    """JSON -> .tres for one content folder only (`maps/red_canyon`, `enemies/skeleton`); (ok, output tail)."""
    if not os.path.isfile(GODOT):
        return False, ("Godot binary not found at %s: the JSON is saved, but the game plays the .tres. Run the import "
                       "yourself: Godot --headless --path game --script res://tools/import_json.gd -- only=%s"
                       % (GODOT, target))
    cmd = [GODOT, "--headless", "--path", GAME, "--script", "res://tools/import_json.gd", "--", "only=%s" % target]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=IMPORT_TIMEOUT, cwd=ROOT,
                           encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        return False, "the import did not finish in %d s" % IMPORT_TIMEOUT
    except OSError as e:
        return False, "could not run the import: %s" % e
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


# ---------------------------------------------------------------- a creature's default look (pass 54)

def creature_file(cid):
    """(kind, json path) of the creature `cid` under content/enemies or content/bosses, or (None, None)."""
    if not ID_RE.match(cid) or cid.startswith("training_dummy"):
        return None, None
    for kind in ("enemy", "boss"):
        path = os.path.join(CONTENT, KIND_FOLDERS[kind], cid, cid + ".json")
        if os.path.isfile(path):
            return kind, path
    return None, None


def write_variant(cid, code):
    """Set the creature JSON's top-level `variant` to `code` (one of the looks the game can play: the base strip or an
    entry of `variants` whose strip is on disk): a backup like a map's, the file written back with its own key order, its
    numbers as they were (json keeps 10.0 a float), its own line endings and final newline, `variant` replaced in place
    or added just before `variants`, then the JSON -> .tres import of that one creature. The Creatures tab's "Set as
    default look" (pass 54; `tools/import_json.gd` accepts only=<type>/<id>). A JSON re-dumped this way differs from
    every creature file only on that one line."""
    kind, path = creature_file(cid)
    if path is None:
        return {"ok": False, "error": "no creature %s under content/enemies or content/bosses" % cid}
    if not isinstance(code, str) or not CODE_RE.match(code):
        return {"ok": False, "error": "the body needs a variant code: {\"code\": \"SK-B\"}"}
    with _write_lock:
        with open(path, "rb") as f:
            raw = f.read()
        src = raw.decode("utf-8")
        d = json.loads(src)
        playable = playable_codes(os.path.dirname(path), d)
        if code not in playable:
            vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
            known = ", ".join(sorted(playable)) or "none"
            why = "its strip is not painted yet" if code in vs else "it has no such variant"
            return {"ok": False, "error": "%s cannot play %s: %s (it can play: %s)" % (cid, code, why, known)}
        before = str(d.get("variant", ""))
        if "variant" in d:
            d["variant"] = code
        else:
            out = {}
            for k, v in d.items():
                if k == "variants":
                    out["variant"] = code
                out[k] = v
            if "variant" not in out:
                out["variant"] = code
            d = out
        text = json.dumps(d, indent=2, ensure_ascii=False)
        if src.endswith("\n"):
            text += "\n"
        if "\r\n" in src:
            text = text.replace("\n", "\r\n")
        backup_rel = backup(cid, path)
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(text.encode("utf-8"))
        os.replace(tmp, path)
    import_ok, output = run_import("%s/%s" % (KIND_FOLDERS[kind], cid))
    return {"ok": True, "id": cid, "kind": kind, "variant": code, "was": before,
            "wrote": rel(path), "backup": backup_rel,
            "import_ok": import_ok, "output": output}


# ---------------------------------------------------------------- the handler

class Handler(BaseHTTPRequestHandler):
    server_version = "88fits-level-editor/1.0"

    def log_message(self, fmt, *args):
        # one quiet line per API call; the page's files and the icons say nothing
        if self.path.startswith("/api/"):
            sys.stdout.write("%s %s\n" % (self.command, self.path))
            sys.stdout.flush()

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _error(self, code, msg):
        self._send(code, {"ok": False, "error": msg})

    def do_GET(self):
        path = unquote(self.path.split("?", 1)[0])
        parts = [p for p in path.split("/") if p]
        try:
            if parts[:1] == ["api"]:
                return self._api_get(parts[1:])
            if parts[:1] == ["icon"]:
                return self._icon(parts[1:])
            return self._static(parts)
        except Exception as e:  # a bug should show in the page, not kill the server
            import traceback
            traceback.print_exc()
            self._error(500, "%s: %s" % (type(e).__name__, e))

    def _api_get(self, parts):
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
        if parts == ["status"]:
            return self._send(200, {"ok": True, "root": ROOT, "godot": os.path.isfile(GODOT), "backups": BACKUPS})
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
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=60")
        self.end_headers()
        self.wfile.write(data)

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
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 50 * 1024 * 1024:
            return None, "no body"
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8")), None
        except ValueError as e:
            return None, "the body is not JSON: %s" % e

    def do_POST(self):
        path = unquote(self.path.split("?", 1)[0])
        parts = [p for p in path.split("/") if p]
        try:
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
            return self._error(404, "unknown API path")
        except Exception as e:
            import traceback
            traceback.print_exc()
            self._error(500, "%s: %s" % (type(e).__name__, e))


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
    print("Ctrl+C stops it.")
    if not args.no_browser:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

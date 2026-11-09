"""Pass 137, lane LOCKIT: the Level Editor's Strings tab (every text a player reads, name -> text) and its CSV.

Where a text lives (one source of truth a string; docs/howto/texts_and_localization.html):
  - the code's words (screens, buttons, toasts, the generated sentences of game/core/systems/TextGen.gd): rows of
    game/content/strings/en.json, a flat {key: text}, keys sorted, LF, UTF-8 without BOM (Loc.gd reads it);
  - a content item's own words stay in its JSON: weapon.revolver.name <-> content/weapons/revolver/revolver.json `name`
    (CONTENT below), an Outlaw's skin name in its variants[CODE].skin.name, the Trail's section and upgrade words in
    content/trail/trail.json, the Wanted tasks' words in content/wanted/wanted.json. Written back where they live with
    the Level Editor's own writers (content_io for a content JSON, then the import; trail_io / wanted_io for those files).

Variables: {name}; {name?one:many} picks the first part when the value is exactly "1"; {{ and }} are literal braces. The
renderer below is Loc.gd's twin (and strings_model.js the page's); the three are pinned by fixtures/loc_cases.json.

server.py hands /api/strings requests here with itself as `srv` (CONTENT, GAME, ROOT, backup, run_import, _write_lock):
  GET  /api/strings                  {ok, rows, groups, files}: every row {key, group, text, where, kind, vars, samples,
                                     icon (a key the icon route takes, or ""), readonly}
  GET  /api/strings/icon?key=<key>   the content item's icon for a row (404 when it has none)
  GET  /api/strings/guide            docs/howto/texts_and_localization.html
  GET  /api/strings/csv[?group=<g>]  the rows as CSV (UTF-8 with a BOM, for Excel): key,group,text,variables,where
  POST /api/strings/save             {changes: {key: text}}: checked, then each written where it lives (a backup each, an
                                     atomic write), the content folders imported; nothing is written when one is wrong
  POST /api/strings/import           {csv, apply}: the CSV checked against the rows; without apply the summary of what
                                     would change (errors, warnings, changes); with apply and no error, saved as above

As a command:  python tools/level_editor/strings_io.py --export out.csv | --check-csv in.csv | --render "<text>" k=v ...
"""
import csv
import io
import json
import os
import re
import sys

import content_io as cio

EN_REL = os.path.join("strings", "en.json")
SAMPLES_REL = os.path.join("tools", "dl", "loc", "samples.json")
GUIDE_REL = os.path.join("docs", "howto", "texts_and_localization.html")
CSV_HEADER = ["key", "group", "text", "variables", "where"]
KEY_RE = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)+$")
_ID_RE = re.compile(r"^[a-z0-9_]+$")

# content folder -> (the key's first word, the top-level text fields a player reads)
CONTENT = [
    ("weapons", "weapon", ["name", "flavour"]),
    ("evolutions", "evolution", ["name", "flavour"]),
    ("mutations", "mutation", ["name", "flavour", "text"]),
    ("passives", "passive", ["name", "flavour", "text"]),
    ("perks", "perk", ["name", "flavour", "text"]),
    ("characters", "outlaw", ["name", "flavour", "trait_name", "trait_text"]),
    ("enemies", "enemy", ["name", "flavour"]),
    ("bosses", "boss", ["name", "flavour"]),
    ("elites", "elite", ["name", "flavour"]),
    ("pickups", "powerup", ["name", "flavour"]),
    ("structures", "structure", ["name", "flavour"]),
    ("maps", "map", ["name", "flavour"]),
    ("quests", "quest", ["name"]),
    ("currencies", "currency", ["name", "flavour"]),
    ("boss_attacks", "boss_attack", ["name"]),
]
ICON_FOLDERS = {word: folder for folder, word, _ in CONTENT if folder not in ("maps", "quests", "boss_attacks")}
# a map's stage_list words (rows stage.<map>.<stage id>.<field>, read-only: pass 137)
STAGE_FIELDS = ["name", "description", "difficulty"]

# the sub-tabs: (id, label, key prefixes); the first that matches wins, "gen." last (the shared words)
GROUPS = [
    ("outlaws", "Outlaws", ["outlaw.", "perk.", "gen.outlaw.", "gen.perk."]),
    ("enemies", "Enemies & Bosses", ["enemy.", "boss.", "elite.", "boss_attack.", "gen.enemy.", "gen.boss."]),
    ("weapons", "Weapons", ["weapon.", "gen.weapon."]),
    ("mutations", "Mutations & Evolutions", ["mutation.", "evolution.", "gen.mutation.", "gen.evolution."]),
    ("items", "Cards & Items", ["passive.", "gen.passive.", "gen.card."]),
    ("progress", "Quests, Wanted & Trail", ["quest.", "wanted.", "trail.", "gen.quest.", "gen.wanted.", "gen.trail."]),
    ("world", "Stages & Structures", ["map.", "stage.", "structure.", "powerup.", "currency.", "gen.structure.", "gen.stage."]),
    ("stats", "Stats", ["stat.", "gen.stat."]),
    ("screens", "Screens", ["ui."]),
    ("messages", "Messages", ["toast.", "hint.", "banner.", "msg."]),
    ("words", "Words", ["gen."]),
]


def group_of(key):
    for gid, _label, prefixes in GROUPS:
        if any(key.startswith(p) for p in prefixes):
            return gid
    return "other"


# ---------------------------------------------------------------- the renderer (Loc.gd's twin)

def _closing(src, i):
    depth = 0
    while i < len(src):
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def parse(src, problems=None):
    """[str | {"v", "raw", "one"?, "many"?}]; `problems` (a list) collects what is broken."""
    segs, buf, i, n = [], "", 0, len(src)
    while i < n:
        c = src[i]
        if c == "{":
            if src[i + 1:i + 2] == "{":
                buf += "{"
                i += 2
                continue
            close = _closing(src, i)
            if close < 0:
                if problems is not None:
                    problems.append("a { with no } (write {{ for a brace that shows)")
                buf += src[i:]
                break
            if buf:
                segs.append(buf)
                buf = ""
            segs.append(_placeholder(src[i + 1:close], src[i:close + 1], problems))
            i = close + 1
            continue
        if c == "}":
            if src[i + 1:i + 2] == "}":
                buf += "}"
                i += 2
                continue
            if problems is not None:
                problems.append("a } with no { (write }} for a brace that shows)")
        buf += c
        i += 1
    if buf:
        segs.append(buf)
    return segs


def _placeholder(inner, raw, problems):
    q = inner.find("?")
    if q < 0:
        name = inner.strip()
        if problems is not None and not _ID_RE.match(name or "-"):
            problems.append("{%s} is not a variable name (letters, digits and _ only)" % inner)
        return {"v": name, "raw": raw}
    rest = inner[q + 1:]
    depth, split = 0, -1
    for j, c in enumerate(rest):
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == ":" and depth == 0:
            split = j
            break
    name = inner[:q].strip()
    if problems is not None and not _ID_RE.match(name or "-"):
        problems.append("{%s} is not a variable name (letters, digits and _ only)" % inner[:q])
    if split < 0:
        if problems is not None:
            problems.append("{%s} needs a ':' between its two parts ({n?one:many})" % inner)
        part = parse(rest, problems)
        return {"v": name, "raw": raw, "one": part, "many": part}
    return {"v": name, "raw": raw, "one": parse(rest[:split], problems), "many": parse(rest[split + 1:], problems)}


def _is_one(v):
    if isinstance(v, bool):
        return False
    if isinstance(v, (int, float)):
        return v == 1
    return str(v).strip() == "1"


def _emit(segs, vals):
    out = []
    for s in segs:
        if isinstance(s, str):
            out.append(s)
        elif s["v"] not in vals:
            out.append(s["raw"])
        elif "one" in s:
            out.append(_emit(s["one"] if _is_one(vals[s["v"]]) else s["many"], vals))
        else:
            out.append(str(vals[s["v"]]))
    return "".join(out)


def render(template, vals):
    return _emit(parse(template), vals or {})


def variables(template):
    out = []

    def walk(segs):
        for s in segs:
            if isinstance(s, dict):
                if s["v"] not in out:
                    out.append(s["v"])
                if "one" in s:
                    walk(s["one"])
                    walk(s["many"])
    walk(parse(template))
    return out


def problems(template):
    found = []
    parse(template, found)
    return list(dict.fromkeys(found))


# Excel's mangled characters: UTF-8 read as Windows-1252 and saved again ("â€™" for ’, "Ã©" for é), or the
# replacement character for a byte that was lost
_MOJIBAKE = re.compile("(â€|Ã.|Â[^A-Za-z]|�)")


# ---------------------------------------------------------------- the rows

def _game(srv):
    return getattr(srv, "GAME", None) or os.path.dirname(srv.CONTENT)


def _root(srv):
    return getattr(srv, "ROOT", None) or os.path.dirname(_game(srv))


def en_path(srv):
    return os.path.join(srv.CONTENT, EN_REL)


def read_en(srv):
    p = en_path(srv)
    if not os.path.isfile(p):
        return {}
    d = json.loads(cio.read_text(p))
    return d if isinstance(d, dict) else {}


def dump_en(d):
    return json.dumps({k: d[k] for k in sorted(d)}, ensure_ascii=False, indent=2) + "\n"


def read_samples(srv):
    p = os.path.join(_root(srv), SAMPLES_REL)
    try:
        d = json.loads(cio.read_text(p))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _folders(srv, folder):
    base = os.path.join(srv.CONTENT, folder)
    for cid in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        path = os.path.join(base, cid, cid + ".json")
        if not _ID_RE.match(cid) or not os.path.isfile(path):
            continue
        try:
            d = json.loads(cio.read_text(path))
        except (OSError, ValueError):
            continue
        if isinstance(d, dict):
            yield cid, path, d


def _code_key(code):
    return re.sub(r"[^a-z0-9_]", "_", code.lower())


def rows(srv):
    """Every row, sorted by key. `loc` tells save() where to write: {"file": "en"} | {"file": "content", "path", "field",
    "folder"} | {"file": "skin", "path", "code", "folder"} | {"file": "trail", ...} | {"file": "wanted", "index", "field"}."""
    out = []
    samples = read_samples(srv)
    for k, v in read_en(srv).items():
        out.append({"key": k, "text": str(v), "where": "content/strings/en.json", "loc": {"file": "en"}})
    for folder, word, fields in CONTENT:
        for cid, path, d in _folders(srv, folder):
            rel = "content/%s/%s/%s.json" % (folder, cid, cid)
            for f in fields:
                if isinstance(d.get(f), str) and d[f] != "":
                    out.append({"key": "%s.%s.%s" % (word, cid, f), "text": d[f], "where": "%s `%s`" % (rel, f),
                                "loc": {"file": "content", "path": path, "field": f, "folder": "%s/%s" % (folder, cid)}})
            if folder == "characters" and isinstance(d.get("variants"), dict):
                for code, e in d["variants"].items():
                    sk = e.get("skin") if isinstance(e, dict) else None
                    if isinstance(sk, dict) and isinstance(sk.get("name"), str) and sk["name"]:
                        out.append({"key": "outlaw.%s.skin.%s.name" % (cid, _code_key(code)), "text": sk["name"],
                                    "where": "%s variants.%s.skin.name" % (rel, code),
                                    "loc": {"file": "skin", "path": path, "code": code, "folder": "characters/%s" % cid}})
    tp = os.path.join(srv.CONTENT, "trail", "trail.json")
    if os.path.isfile(tp):
        try:
            t = json.loads(cio.read_text(tp))
        except (OSError, ValueError):
            t = {}
        for i, s in enumerate(t.get("sections") or []):
            if isinstance(s, dict) and isinstance(s.get("name"), str):
                out.append({"key": "trail.section.%d.name" % int(s.get("from", i)), "text": s["name"],
                            "where": "content/trail/trail.json sections[%d].name" % i,
                            "loc": {"file": "trail", "path": ["sections", i, "name"]}})
        for ty, u in (t.get("upgrades") or {}).items():
            for f in ("name", "text"):
                if isinstance(u, dict) and isinstance(u.get(f), str) and u[f]:
                    out.append({"key": "trail.upgrade.%s.%s" % (ty, f), "text": u[f],
                                "where": "content/trail/trail.json upgrades.%s.%s" % (ty, f),
                                "loc": {"file": "trail", "path": ["upgrades", ty, f]}})
        end = t.get("end")
        if isinstance(end, dict) and isinstance(end.get("text"), str):
            out.append({"key": "trail.end.text", "text": end["text"], "where": "content/trail/trail.json end.text",
                        "loc": {"file": "trail", "path": ["end", "text"]}})
    wp = os.path.join(srv.CONTENT, "wanted", "wanted.json")
    if os.path.isfile(wp):
        try:
            w = json.loads(cio.read_text(wp))
        except (OSError, ValueError):
            w = {}
        for i, task in enumerate(w.get("tasks") or []):
            for f in ("name", "text"):
                if isinstance(task, dict) and isinstance(task.get(f), str) and task[f]:
                    out.append({"key": "wanted.%s.%s" % (task.get("type", i), f), "text": task[f],
                                "where": "content/wanted/wanted.json tasks[%d].%s" % (i, f),
                                "loc": {"file": "wanted", "path": ["tasks", i, f]}})
    # pass 137 (lane W2-HUB): a map's stage words (timeline_data.stage_list[k] name / description / difficulty), shown
    # read-only: the map file belongs to the Timeline tab's writer (and holds Garry's edits), so they are edited there
    for mid, mpath, md in _folders(srv, "maps"):
        tl = md.get("timeline_data") if isinstance(md.get("timeline_data"), dict) else {}
        for i, st in enumerate(tl.get("stage_list") or []):
            if not isinstance(st, dict):
                continue
            sid = str(st.get("id", i))
            for f in STAGE_FIELDS:
                if isinstance(st.get(f), str) and st[f] != "":
                    out.append({"key": "stage.%s.%s.%s" % (mid, sid if _ID_RE.match(sid) else str(i), f), "text": st[f],
                                "where": "content/maps/%s/%s.json timeline_data.stage_list[%d].%s (edit it in the Timeline tab)" % (mid, mid, i, f),
                                "loc": {"file": "stage", "path": mpath, "index": i, "field": f}})
    for r in out:
        r["group"] = group_of(r["key"])
        r["vars"] = variables(r["text"])
        sm = samples.get(r["key"])
        r["samples"] = dict(sm.get("vars") or {}) if isinstance(sm, dict) else {}
        for v in r["samples"]:
            if v not in r["vars"]:
                r["vars"].append(v)
        parts = r["key"].split(".")
        r["icon"] = r["key"] if parts[0] in ICON_FOLDERS and len(parts) >= 3 else ""
        r["readonly"] = r["loc"]["file"] == "stage"
    out.sort(key=lambda r: r["key"])
    return out


def icon_path(srv, key):
    """The icon a row shows: the content item its key names (weapon.revolver.desc -> weapons/revolver/revolver_icon.png;
    an Outlaw's skin row shows that skin's icon when it has one)."""
    parts = (key or "").split(".")
    if len(parts) < 2 or parts[0] not in ICON_FOLDERS or not _ID_RE.match(parts[1]):
        return None
    base = os.path.join(srv.CONTENT, ICON_FOLDERS[parts[0]], parts[1])
    names = []
    if parts[0] == "outlaw" and len(parts) >= 4 and parts[2] == "skin":
        letter = parts[3].split("_")[-1]
        names.append("%s_icon_%s.png" % (parts[1], letter))
    names.append("%s_icon.png" % parts[1])
    for n in names:
        if os.path.isfile(os.path.join(base, n)):
            return os.path.join(base, n)
    if os.path.isdir(base):
        more = sorted(f for f in os.listdir(base) if f.startswith(parts[1] + "_icon") and f.endswith(".png"))
        if more:
            return os.path.join(base, more[0])
    return None


def read(srv):
    rs = rows(srv)
    counts = {}
    for r in rs:
        counts[r["group"]] = counts.get(r["group"], 0) + 1
    groups = [{"id": g, "label": label, "count": counts.get(g, 0)} for g, label, _ in GROUPS]
    if counts.get("other"):
        groups.append({"id": "other", "label": "Other", "count": counts["other"]})
    for r in rs:
        r.pop("loc", None)
    return {"ok": True, "rows": rs, "groups": groups, "en": "game/content/strings/en.json",
            "samples": SAMPLES_REL.replace("\\", "/"), "guide": "/api/strings/guide"}


# ---------------------------------------------------------------- checks

def check_text(row, text):
    """(errors, warnings) for a new text of `row` (a row as rows() gives it, with its old text and its known vars)."""
    errs, warns = [], []
    if not isinstance(text, str):
        return ["the text is not a string"], []
    if row.get("readonly") and text != row.get("text", ""):
        return ["read-only here: a stage's words are edited in the Timeline tab (the map file)"], []
    if text.strip() == "":
        errs.append("the text is empty")
    errs += problems(text)
    if _MOJIBAKE.search(text) and not _MOJIBAKE.search(row.get("text", "")):
        errs.append("the text has mangled characters (%s): the file lost its UTF-8; save it as \"CSV UTF-8\"" % _MOJIBAKE.search(text).group(0))
    known = set(row.get("vars") or [])
    used = set(variables(text)) if not problems(text) else set()
    unknown = sorted(used - known)
    if unknown:
        errs.append("unknown variable%s %s (this text has: %s)" % ("s" if len(unknown) > 1 else "", ", ".join("{%s}" % u for u in unknown),
                                                                  ", ".join("{%s}" % k for k in sorted(known)) or "none"))
    dropped = sorted(set(variables(row.get("text", ""))) - used) if not errs else []
    if dropped:
        warns.append("no longer shows %s" % ", ".join("{%s}" % d for d in dropped))
    return errs, warns


# ---------------------------------------------------------------- saving

def _set_path(obj, path, value):
    cur = obj
    for p in path[:-1]:
        cur = cur[p]
    cur[path[-1]] = value


def save(srv, changes):
    """POST /api/strings/save: {key: text}. Every change is checked first; one wrong = nothing written."""
    if not isinstance(changes, dict) or not changes:
        return {"ok": False, "error": "no changes", "status": 400}
    with srv._write_lock:
        by_key = {r["key"]: r for r in rows(srv)}
        errors, warnings, todo = [], [], []
        for key, text in changes.items():
            row = by_key.get(key)
            if row is None:
                errors.append({"key": key, "error": "unknown key"})
                continue
            e, w = check_text(row, text)
            errors += [{"key": key, "error": x} for x in e]
            warnings += [{"key": key, "warning": x} for x in w]
            if text != row["text"]:
                todo.append((row, text))
        if errors:
            return {"ok": False, "errors": errors, "warnings": warnings, "error": "%d problem(s): nothing was written" % len(errors), "status": 400}
        if not todo:
            return {"ok": True, "unchanged": True, "written": [], "warnings": warnings}
        # every file's new text first (a layout the writer cannot keep stops everything before a byte is written)
        en, content, trail, wanted = None, {}, None, None
        for row, text in todo:
            loc = row["loc"]
            if loc["file"] == "en":
                en = en if en is not None else read_en(srv)
                en[row["key"]] = text
            elif loc["file"] in ("content", "skin"):
                src = content.get(loc["path"], (None, cio.read_text(loc["path"]), loc["folder"]))[1]
                if loc["file"] == "content":
                    new = cio.set_top_block(src, loc["field"], text)
                else:
                    entry = json.loads(src)["variants"][loc["code"]]
                    skin = dict(entry["skin"])
                    skin["name"] = text
                    new = cio.set_variant_entry(src, loc["code"], {"skin": skin})
                if new is None:
                    return {"ok": False, "error": "layout: %s is not one top-level key a line; nothing was written" % srv.rel(loc["path"]), "status": 400}
                content[loc["path"]] = (src, new, loc["folder"])
            elif loc["file"] == "trail":
                trail = trail if trail is not None else json.loads(cio.read_text(os.path.join(srv.CONTENT, "trail", "trail.json")))
                _set_path(trail, loc["path"], text)
            elif loc["file"] == "wanted":
                wanted = wanted if wanted is not None else json.loads(cio.read_text(os.path.join(srv.CONTENT, "wanted", "wanted.json")))
                _set_path(wanted, loc["path"], text)
        written = []
        if en is not None:
            p = en_path(srv)
            if os.path.isfile(p):
                srv.backup("strings_en", p)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            cio.write_atomic(p, dump_en(en))
            written.append(srv.rel(p))
        for path, (_src, new, _folder) in content.items():
            srv.backup(os.path.basename(path)[:-5], path)
            cio.write_atomic(path, new)
            written.append(srv.rel(path))
    # the trail and wanted writers take the write lock themselves (their own checks, backup and layout)
    if trail is not None:
        import trail_io
        r = trail_io.save(srv, trail)
        if not r.get("ok"):
            return {"ok": False, "error": "the Trail's file: %s" % r.get("error"), "written": written, "status": 400}
        written.append(r.get("file"))
    if wanted is not None:
        import wanted_io
        r = wanted_io.save(srv, wanted)
        if not r.get("ok"):
            return {"ok": False, "error": "the Wanted file: %s" % r.get("error"), "written": written, "status": 400}
        written.append(r.get("file"))
    import_ok, output = True, "no content JSON changed: no import (en.json, trail.json and wanted.json are read as they are)"
    folders = sorted({f for (_s, _n, f) in content.values()})
    if folders and hasattr(srv, "run_import"):
        import_ok, output = srv.run_import(",".join(folders), "level_editor strings save")
    return {"ok": True, "written": written, "changed": len(todo), "warnings": warnings, "import_ok": import_ok, "output": output}


# ---------------------------------------------------------------- CSV

def export_csv(srv, group=None):
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\r\n", quoting=csv.QUOTE_MINIMAL)
    w.writerow(CSV_HEADER)
    for r in rows(srv):
        if group and r["group"] != group:
            continue
        w.writerow([r["key"], r["group"], r["text"], " ".join("{%s}" % v for v in r["vars"]), r["where"]])
    return "﻿" + buf.getvalue()


def import_csv(srv, text, apply=False):
    """The CSV checked against the rows: {ok, errors [{line, key, error}], warnings, changes [{key, old, new}], summary};
    with apply and no error the changes are saved (save())."""
    if not isinstance(text, str) or not text.strip():
        return {"ok": False, "errors": [{"line": 0, "key": "", "error": "the file is empty"}], "status": 400}
    if text.startswith("﻿"):
        text = text[1:]
    try:
        table = list(csv.reader(io.StringIO(text, newline="")))
    except csv.Error as e:
        return {"ok": False, "errors": [{"line": 0, "key": "", "error": "not a CSV: %s" % e}], "status": 400}
    errors, warnings, changes = [], [], []
    if not table or [h.strip().lower() for h in table[0][:3]] != CSV_HEADER[:3]:
        got = ",".join(table[0]) if table else ""
        return {"ok": False, "errors": [{"line": 1, "key": "", "error": "the first line must be the header %s (it is: %s)" % (",".join(CSV_HEADER), got[:120])}], "status": 400}
    head = [h.strip().lower() for h in table[0]]
    ki, ti = head.index("key"), head.index("text")
    by_key = {r["key"]: r for r in rows(srv)}
    seen = {}
    for n, rec in enumerate(table[1:], start=2):
        if not rec or all(not c.strip() for c in rec):
            continue
        if len(rec) <= max(ki, ti):
            errors.append({"line": n, "key": rec[0] if rec else "", "error": "the line has %d column(s), it needs key and text" % len(rec)})
            continue
        key, new = rec[ki].strip(), rec[ti]
        if key in seen:
            errors.append({"line": n, "key": key, "error": "the key is here twice (line %d too)" % seen[key]})
            continue
        seen[key] = n
        row = by_key.get(key)
        if row is None:
            errors.append({"line": n, "key": key, "error": "unknown key (a new text needs its key in the code first; ask Claude)"})
            continue
        # Excel turns the file's line breaks into \r\n inside a cell: the game's texts use \n
        new = new.replace("\r\n", "\n")
        e, w = check_text(row, new)
        errors += [{"line": n, "key": key, "error": x} for x in e]
        warnings += [{"line": n, "key": key, "warning": x} for x in w]
        if not e and new != row["text"]:
            changes.append({"key": key, "old": row["text"], "new": new, "where": row["where"]})
    summary = "%d text%s change%s" % (len(changes), "" if len(changes) == 1 else "s", "s" if len(changes) == 1 else "")
    if changes:
        summary += ": " + ", ".join(c["key"] for c in changes[:12]) + (" and %d more" % (len(changes) - 12) if len(changes) > 12 else "")
    res = {"ok": not errors, "errors": errors, "warnings": warnings, "changes": changes, "rows": len(seen), "summary": summary}
    if errors:
        res["summary"] = "%d error(s): nothing will be written. %s" % (len(errors), summary)
        res["status"] = 400
        return res
    if apply and changes:
        saved = save(srv, {c["key"]: c["new"] for c in changes})
        res["saved"] = saved
        res["ok"] = bool(saved.get("ok"))
        if not res["ok"]:
            res["status"] = 400
    return res


# ---------------------------------------------------------------- routes

def api_get(handler, srv, parts, query):
    if parts == []:
        return handler._result(read(srv))
    if parts == ["icon"]:
        full = icon_path(srv, (query.get("key") or [""])[0])
        if not full:
            return handler._error(404, "no icon")
        return handler._file(full, "image/png", cache="max-age=60")
    if parts == ["guide"]:
        full = os.path.join(_root(srv), GUIDE_REL)
        if not os.path.isfile(full):
            return handler._error(404, "no guide at %s" % GUIDE_REL)
        return handler._file(full, "text/html; charset=utf-8", cache="no-store")
    if parts == ["csv"]:
        group = (query.get("group") or [""])[0] or None
        return handler._send(200, export_csv(srv, group).encode("utf-8"), "text/csv; charset=utf-8")
    return handler._error(404, "unknown API path")


def api_post(handler, srv, parts):
    data, err = handler._body()
    if err and err != "no body":
        return handler._error(400, err)
    data = data if isinstance(data, dict) else {}
    if parts == ["save"]:
        return handler._result(save(srv, data.get("changes")))
    if parts == ["import"]:
        return handler._result(import_csv(srv, data.get("csv"), bool(data.get("apply"))))
    return handler._error(404, "unknown API path")


def _cli_srv():
    import threading
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))

    class _Srv:
        ROOT = root
        GAME = os.path.join(root, "game")
        CONTENT = os.path.join(root, "game", "content")
        _write_lock = threading.Lock()

        @staticmethod
        def rel(p):
            return os.path.relpath(p, root).replace("\\", "/")
    return _Srv


def _main(argv):
    if len(argv) >= 2 and argv[0] == "--export":
        with open(argv[1], "w", encoding="utf-8", newline="") as f:
            f.write(export_csv(_cli_srv()))
        print("wrote %s" % argv[1])
        return 0
    if len(argv) >= 2 and argv[0] == "--check-csv":
        with open(argv[1], encoding="utf-8-sig", newline="") as f:
            r = import_csv(_cli_srv(), f.read(), apply=False)
        print(r["summary"])
        for e in r.get("errors", []):
            print("ERROR line %s %s: %s" % (e["line"], e["key"], e["error"]))
        for w in r.get("warnings", []):
            print("warning line %s %s: %s" % (w["line"], w["key"], w["warning"]))
        return 0 if r["ok"] else 1
    if len(argv) >= 1 and argv[0] == "--render":
        vals = dict(a.split("=", 1) for a in argv[2:] if "=" in a)
        print(render(argv[1], vals))
        print("problems: %s" % (problems(argv[1]) or "none"))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))

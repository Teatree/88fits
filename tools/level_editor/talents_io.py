"""Pass 116, lane EDITOR: the Level Editor's Mirror tab routes (the Upgrade board's talents, game/content/talents/<id>/,
"the Mirror" in code; Registry.talents_list orders them by the first rank's price, then `order`, then the id).

server.py hands every /api/talents request here with itself as `srv` (its CONTENT, backup, restore_numbers, the write
lock, run_import_info), so a selftest that points those at a temporary copy tests these routes on it too.

  GET  /api/talents                     {ok, talents: [{id, json, file, mtime, icons: {talent, forms: [url|None]}}], order}
                                        in board order
  GET  /api/talents/icon/<id>/<file>    a picture from the talent's folder (png)
  POST /api/talents/save                {id, json, base_mtime, no_import?}: the talent back (a 409 when the file changed on
                                        disk since the page read it), checked (forms a list of two, cost a list of numbers),
                                        one backup, only the changed top keys rewritten in the file's own layout
                                        (content_io.set_top_key), the file's floats kept; then the .tres imported
"""
import json
import os
import re

import content_io as cio

_ID_RE = re.compile(r"^[a-z0-9_]+$")
_PNG_RE = re.compile(r"^[A-Za-z0-9_.-]+\.png$")


def folder(srv):
    return os.path.join(srv.CONTENT, "talents")


def _path(srv, tid):
    return os.path.join(folder(srv), tid, tid + ".json")


def first_price(d):
    c = d.get("cost") if isinstance(d.get("cost"), list) else []
    try:
        return int(c[0]) if c else 0
    except (TypeError, ValueError):
        return 0


def board_key(d):
    """TalentDef.board_before: the first rank's price, then `order`, then the id."""
    try:
        order = int(d.get("order", 0))
    except (TypeError, ValueError):
        order = 0
    return (first_price(d), order, str(d.get("id", "")))


def _icons(srv, tid, d):
    base = os.path.join(folder(srv), tid)
    url = lambda n: ("/api/talents/icon/%s/%s" % (tid, n)) if n and _PNG_RE.match(n) and os.path.isfile(os.path.join(base, n)) else None
    forms = []
    for k, f in enumerate(d.get("forms") or []):
        name = str(f.get("icon")) if isinstance(f, dict) and f.get("icon") else "%s_%d_icon.png" % (tid, k)
        forms.append(url(os.path.basename(name)))
    return {"talent": url(str(d.get("icon") or tid + "_icon.png")), "forms": forms}


def read(srv):
    """GET /api/talents."""
    out = []
    base = folder(srv)
    for tid in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        p = _path(srv, tid)
        if not _ID_RE.match(tid) or not os.path.isfile(p):
            continue
        try:
            d = json.loads(cio.read_text(p))
        except (OSError, ValueError) as e:
            out.append({"id": tid, "json": None, "error": "%s is not valid JSON: %s" % (srv.rel(p), e), "file": srv.rel(p)})
            continue
        out.append({"id": tid, "json": d, "file": srv.rel(p), "mtime": srv.mtime_of(p), "icons": _icons(srv, tid, d)})
    out.sort(key=lambda t: board_key(t["json"]) if isinstance(t.get("json"), dict) else (1 << 40, 0, t["id"]))
    return {"ok": True, "talents": out, "order": [t["id"] for t in out]}


def check(obj, tid):
    """'' when `obj` is a talent the game can read, else why not."""
    if not isinstance(obj, dict):
        return "the talent is a JSON object"
    if str(obj.get("id", tid)) != tid:
        return "the id cannot change here (%s)" % tid
    forms = obj.get("forms")
    if not isinstance(forms, list) or not forms or not all(isinstance(f, dict) for f in forms):
        return "forms must be a list of objects"
    cost = obj.get("cost")
    if not isinstance(cost, list) or not all(isinstance(c, (int, float)) and not isinstance(c, bool) and c >= 0 for c in cost):
        return "cost must be a list of prices (numbers, 0 or more)"
    r = obj.get("ranks", 6)
    if not isinstance(r, int) or isinstance(r, bool) or r < 1:
        return "ranks must be a whole number, 1 or more"
    for f in forms:
        for e in f.get("effects") or []:
            if not isinstance(e, dict) or not e.get("stat") or e.get("op") not in ("add", "mul", "set") or not isinstance(e.get("value"), (int, float)):
                return "every effect needs stat, op (add, mul, set) and a number value"
    return ""


def save(srv, tid, new_obj, base_mtime=None, do_import=True):
    """POST /api/talents/save."""
    if not _ID_RE.match(str(tid or "")):
        return {"ok": False, "error": "bad id", "status": 400}
    p = _path(srv, tid)
    if not os.path.isfile(p):
        return {"ok": False, "error": "no talent %s (the tab never creates talents)" % tid, "status": 404}
    err = check(new_obj, tid)
    if err:
        return {"ok": False, "error": err, "status": 400}
    with srv._write_lock:
        cur = srv.mtime_of(p)
        if base_mtime is not None and isinstance(base_mtime, (int, float)) and abs(float(base_mtime) - cur) > 0.0015:
            return {"ok": False, "error": "changed on disk", "mtime": cur, "status": 409}
        src = cio.read_text(p)
        old = json.loads(src)
        merged = srv.restore_numbers(old, new_obj)
        if merged == old:
            return {"ok": True, "unchanged": True, "mtime": cur, "file": srv.rel(p)}
        text = src
        for k in merged:
            if k not in old or merged[k] != old[k]:
                text = cio.set_top_key(text, k, merged[k]) if text is not None else None
        for k in old:
            if k not in merged and text is not None:
                text = cio.del_top_block(text, k)
        if text is None or json.loads(text) != merged:   # the layout-keeping edit must say exactly what the page sent
            return {"ok": False, "error": "could not rewrite %s in its own layout" % srv.rel(p), "status": 500}
        bk = srv.backup("talent_" + tid, p)
        cio.write_atomic(p, text)
        mt = srv.mtime_of(p)
    out = {"ok": True, "backup": bk, "mtime": mt, "file": srv.rel(p)}
    if do_import:
        info = srv.run_import_info("talents/" + tid, "level_editor Mirror tab")
        out.update(imported=info.get("ok"), import_output=info.get("output", ""), import_job=info.get("job"))
    return out


def api_get(handler, srv, parts, query):
    if parts == []:
        return handler._result(read(srv))
    if len(parts) == 3 and parts[0] == "icon" and _ID_RE.match(parts[1]) and _PNG_RE.match(parts[2]):
        full = os.path.join(folder(srv), parts[1], parts[2])
        if not os.path.isfile(full):
            return handler._error(404, "no such icon")
        return handler._file(full, "image/png", cache="max-age=30")
    return handler._error(404, "unknown API path")


def api_post(handler, srv, parts):
    data, err = handler._body()
    if err and err != "no body":
        return handler._error(400, err)
    data = data if isinstance(data, dict) else {}
    if parts == ["save"]:
        return handler._result(save(srv, str(data.get("id") or ""), data.get("json"), data.get("base_mtime"), not data.get("no_import")))
    return handler._error(404, "unknown API path")

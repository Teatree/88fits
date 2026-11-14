"""Pass 149, lane EDITOR: the Level Editor's routes for the Store (game/content/store/store.json version 2, read by
game/core/systems/StorePacks.gd at run time; plain JSON, no .tres, so a save needs no import; docs/store_schema.md, lane
STORE). The tab is store.js on store_model.js (the bonus tags, the coin offer rule, the checks).

server.py hands every /api/store request here with itself as `srv` (its CONTENT, GAME, backup, restore_numbers, the write
lock), so a selftest that points those at a temporary copy tests these routes on it too.

  GET  /api/store                  {ok, json, file, mtime, exists, currencies, stages, trail_top, pictures}: the file as on
                                   disk; the currency registry (id, name, word, icon_url); the first map's stages (the
                                   coin offers scale by the latest one unlocked); the Trail's top level (the preview's
                                   last column); the pictures in game/art/ui/store/ as res:// paths
  GET  /api/store/picture?path=res://art/...   a picture under game/art/ (png, jpg, webp), for the pack and offer rows
  POST /api/store/save             {json, base_mtime}: the whole file back (a 409 when it changed on disk since the page
                                   read it), checked (the shape the game reads; the page's own checks are store_model.js),
                                   a key the page does not know kept from the file on disk (top level, in a block, in a
                                   pack or offer by its id), one backup, one atomic write with LF in the file's layout (a
                                   block a key a line, a pack or offer a line), the file's floats kept
"""
import json
import os
import re

import content_io as cio

REL = os.path.join("store", "store.json")
RIBBONS = ("", "most_popular", "best_value")
_ID_RE = re.compile(r"^[a-z0-9_]+$")
_PIC_RE = re.compile(r"^res://art/[A-Za-z0-9_./-]+\.(png|jpg|jpeg|webp)$")
# the keys the tab edits, per block: anything else in the file is kept as it is on disk
KNOWN = {
    "": ("version", "gems", "coins", "revive"),
    "gems": ("currency", "show_bonus", "packs"),
    "coins": ("currency", "pay", "show_bonus", "offers", "scaling"),
    "revive": ("price", "currency", "per_run"),
    "scaling": ("stage_mult", "trail_step", "trail_per_step", "round_sig"),
    "pack": ("id", "amount", "price_cents", "price_text", "ribbon", "picture"),
    "offer": ("id", "gems", "coins", "ribbon", "picture"),
}


def path_of(srv):
    return os.path.join(srv.CONTENT, REL)


def _num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def _int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def _game(srv):
    return getattr(srv, "GAME", None) or os.path.dirname(srv.CONTENT)


def currencies(srv):
    """The currency registry ({id, name, word, colour, icon_url}), gold standing in when content/currencies holds none."""
    try:
        import vocab
        recs = vocab.currency_records(srv.CONTENT)
    except Exception:   # noqa: BLE001
        recs = [{"id": "gold", "name": "Gold", "word": "gold", "colour": "#C9932F"}]
    return [{"id": r["id"], "name": r.get("name", r["id"]), "word": r.get("word", r["id"]), "colour": r.get("colour", ""),
             "icon_url": "/api/currencies/%s/icon" % r["id"]} for r in recs]


def currency_ids(srv):
    return [r["id"] for r in currencies(srv)]


def stages(srv):
    """The first map's stages (sorted by id, as the game's Registry lists maps: the one map, red_canyon), [{id, name}]."""
    base = os.path.join(srv.CONTENT, "maps")
    for mid in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        p = os.path.join(base, mid, mid + ".json")
        if not _ID_RE.match(mid) or not os.path.isfile(p):
            continue
        try:
            d = json.loads(cio.read_text(p))
        except (OSError, ValueError):
            continue
        tl = d.get("timeline_data") if isinstance(d, dict) and isinstance(d.get("timeline_data"), dict) else {}
        out = [{"id": str(s.get("id", "")), "name": str(s.get("name", s.get("id", "")))} for s in tl.get("stage_list") or [] if isinstance(s, dict)]
        if out:
            return {"map": mid, "list": out}
    return {"map": None, "list": []}


def trail_top(srv):
    """The Trail's top level (the highest node level in content/trail/trail.json), or None."""
    try:
        d = json.loads(cio.read_text(os.path.join(srv.CONTENT, "trail", "trail.json")))
    except (OSError, ValueError):
        return None
    levels = [n.get("level") for n in (d.get("nodes") or []) if isinstance(n, dict) and _int(n.get("level"))] if isinstance(d, dict) else []
    return max(levels) if levels else None


def pictures(srv):
    """Every picture in game/art/ui/store/ as a res:// path (the rows' picture picks)."""
    base = os.path.join(_game(srv), "art", "ui", "store")
    if not os.path.isdir(base):
        return []
    return sorted("res://art/ui/store/%s" % f for f in os.listdir(base) if re.match(r"^[A-Za-z0-9_-]+\.(png|jpg|jpeg|webp)$", f))


def picture_file(srv, res):
    """The file a res://art/... picture names (only under game/art, only a picture), or None."""
    if not isinstance(res, str) or not _PIC_RE.match(res) or ".." in res:
        return None
    game = os.path.abspath(_game(srv))
    full = os.path.abspath(os.path.join(game, *res[len("res://"):].split("/")))
    if not full.startswith(os.path.join(game, "art") + os.sep):
        return None
    return full if os.path.isfile(full) else None


def read(srv):
    """GET /api/store."""
    p = path_of(srv)
    st = stages(srv)
    base = {"ok": True, "file": srv.rel(p), "currencies": currencies(srv), "stages": st["list"], "map": st["map"],
            "trail_top": trail_top(srv), "pictures": pictures(srv)}
    if not os.path.isfile(p):
        return dict(base, json=None, exists=False, mtime=None)
    try:
        d = json.loads(cio.read_text(p))
    except (OSError, ValueError) as e:
        return {"ok": False, "error": "%s is not valid JSON: %s" % (srv.rel(p), e), "status": 400}
    return dict(base, json=d, exists=True, mtime=srv.mtime_of(p))


def check(obj, currencies=None):
    """'' when `obj` has the shape the game reads (version 2), else why not (the first fault). The rules a designer breaks
    (a price text that does not name its price, a ribbon twice...) are the page's checks, store_model.js `check`. With
    `currencies` (the ids of content/currencies) every currency named must be one of them."""
    if not isinstance(obj, dict):
        return "the Store is a JSON object"
    if obj.get("version") != 2:
        return "version is 2"

    def cur(v, what):
        if not isinstance(v, str) or not _ID_RE.match(v):
            return "%s is a currency id" % what
        if currencies is not None and v not in currencies:
            return "%s %s is not in content/currencies (%s)" % (what, v, ", ".join(currencies))
        return ""

    def items(lst, what, keys):
        if not isinstance(lst, list):
            return "%s is a list" % what
        for i, x in enumerate(lst):
            if not isinstance(x, dict):
                return "%s %d is not an object" % (what, i + 1)
            if not isinstance(x.get("id"), str) or not _ID_RE.match(x["id"]):
                return "%s %d needs an id (a-z, 0-9, _)" % (what, i + 1)
            for k in keys:
                if not _int(x.get(k)) or x[k] <= 0:
                    return "%s: %s is a whole number above 0" % (x["id"], k)
            if x.get("ribbon", "") not in RIBBONS:
                return "%s: ribbon is one of none, most_popular, best_value" % x["id"]
            if "picture" in x and not isinstance(x["picture"], str):
                return "%s: picture is a res:// path" % x["id"]
        return ""

    g = obj.get("gems")
    if not isinstance(g, dict):
        return "gems is {currency, show_bonus, packs}"
    e = cur(g.get("currency"), "gems.currency") or items(g.get("packs"), "gem pack", ("amount", "price_cents"))
    if e:
        return e
    for p in g["packs"]:
        if not isinstance(p.get("price_text"), str) or not p["price_text"]:
            return "%s: price_text is the words on its button ($4.99)" % p["id"]
    c = obj.get("coins")
    if not isinstance(c, dict):
        return "coins is {currency, pay, show_bonus, offers, scaling}"
    e = cur(c.get("currency"), "coins.currency") or cur(c.get("pay"), "coins.pay") or items(c.get("offers"), "coin offer", ("gems", "coins"))
    if e:
        return e
    ids = [x["id"] for x in g["packs"] + c["offers"]]
    if len(set(ids)) != len(ids):
        return "two packs or offers share an id"
    sc = c.get("scaling")
    if not isinstance(sc, dict):
        return "coins.scaling is {stage_mult, trail_step, trail_per_step, round_sig}"
    sm = sc.get("stage_mult")
    if not (isinstance(sm, list) and sm and all(_num(x) and x > 0 for x in sm)):
        return "coins.scaling.stage_mult is a list of numbers above 0"
    if not _int(sc.get("trail_step")) or sc["trail_step"] < 0:
        return "coins.scaling.trail_step is a whole number, 0 or more (0 = no Trail steps)"
    if not _num(sc.get("trail_per_step")) or sc["trail_per_step"] < 0:
        return "coins.scaling.trail_per_step is a number, 0 or more"
    if not _int(sc.get("round_sig")) or sc["round_sig"] < 1:
        return "coins.scaling.round_sig is a whole number, 1 or more"
    r = obj.get("revive")
    if not isinstance(r, dict):
        return "revive is {price, currency, per_run}"
    for k in ("price", "per_run"):
        if not _int(r.get(k)) or r[k] < 0:
            return "revive.%s is a whole number, 0 or more" % k
    return cur(r.get("currency"), "revive.currency")


def _keep(old, new, known):
    """`new` with every key of `old` the page does not know (not in `known`) put back where `new` lacks it."""
    if not isinstance(old, dict) or not isinstance(new, dict):
        return new
    out = dict(new)
    for k, v in old.items():
        if k not in known and k not in out:
            out[k] = v
    return out


def _keep_list(old, new, known):
    by_id = {x["id"]: x for x in old if isinstance(x, dict) and isinstance(x.get("id"), str)} if isinstance(old, list) else {}
    return [_keep(by_id.get(x.get("id")), x, known) if isinstance(x, dict) else x for x in new]


def merge_unknown(old, new):
    """Pass 149: the keys the page does not know kept from the file on disk: at the top, in each block, in scaling, in a
    pack or an offer (matched by its id). A key the page knows is taken as sent."""
    if not isinstance(old, dict):
        return new
    out = _keep(old, new, KNOWN[""])
    for blk in ("gems", "coins", "revive"):
        if isinstance(out.get(blk), dict):
            out[blk] = _keep(old.get(blk), out[blk], KNOWN[blk])
    og, oc = old.get("gems") if isinstance(old.get("gems"), dict) else {}, old.get("coins") if isinstance(old.get("coins"), dict) else {}
    if isinstance(out.get("gems"), dict) and isinstance(out["gems"].get("packs"), list):
        out["gems"]["packs"] = _keep_list(og.get("packs"), out["gems"]["packs"], KNOWN["pack"])
    if isinstance(out.get("coins"), dict):
        if isinstance(out["coins"].get("offers"), list):
            out["coins"]["offers"] = _keep_list(oc.get("offers"), out["coins"]["offers"], KNOWN["offer"])
        if isinstance(out["coins"].get("scaling"), dict):
            out["coins"]["scaling"] = _keep(oc.get("scaling"), out["coins"]["scaling"], KNOWN["scaling"])
    return out


def _one(v):
    return json.dumps(v, ensure_ascii=False, separators=(", ", ": "))


def dump(obj):
    """The file's layout (lane STORE's): two spaces, keys in the order given, LF, a final newline; a block (gems, coins)
    one key a line, its list (packs, offers) one item a line; scaling and revive on one line."""
    lines = ["{"]
    keys = list(obj.keys())
    for i, k in enumerate(keys):
        end = "," if i < len(keys) - 1 else ""
        v = obj[k]
        if isinstance(v, dict) and k in ("gems", "coins") and v:
            lines.append("  %s: {" % json.dumps(k))
            sub = list(v.keys())
            for j, sk in enumerate(sub):
                send = "," if j < len(sub) - 1 else ""
                sv = v[sk]
                if isinstance(sv, list) and sv and all(isinstance(x, dict) for x in sv):
                    lines.append("    %s: [" % json.dumps(sk))
                    for m, x in enumerate(sv):
                        lines.append("      %s%s" % (_one(x), "," if m < len(sv) - 1 else ""))
                    lines.append("    ]%s" % send)
                else:
                    lines.append("    %s: %s%s" % (json.dumps(sk), _one(sv), send))
            lines.append("  }%s" % end)
        else:
            lines.append("  %s: %s%s" % (json.dumps(k), _one(v), end))
    lines.append("}")
    return "\n".join(lines) + "\n"


def save(srv, new_obj, base_mtime=None):
    """POST /api/store/save."""
    err = check(new_obj, currency_ids(srv))
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
        # a version 1 file (pass 147's packs) is replaced whole: its keys mean something else in version 2
        v2 = isinstance(old, dict) and old.get("version") == 2
        merged = srv.restore_numbers(old, merge_unknown(old, new_obj)) if v2 else new_obj
        if isinstance(old, dict) and merged == old and dump(merged) == dump(old):
            return {"ok": True, "unchanged": True, "mtime": cur, "file": srv.rel(p)}
        bk = srv.backup("store", p) if os.path.isfile(p) else None
        os.makedirs(os.path.dirname(p), exist_ok=True)
        cio.write_atomic(p, dump(merged))
        mt = srv.mtime_of(p)
    return {"ok": True, "backup": bk, "mtime": mt, "file": srv.rel(p),
            "note": "the game reads the file when it starts: restart it (or ship a build) to see the new Store"}


def api_get(handler, srv, parts, query):
    if parts == []:
        return handler._result(read(srv))
    if parts == ["picture"]:
        res = (query.get("path") or [""])[0] if isinstance(query, dict) else ""
        full = picture_file(srv, res)
        if not full:
            return handler._error(404, "no such picture")
        return handler._file(full, cache="max-age=30")
    return handler._error(404, "unknown API path")


def api_post(handler, srv, parts):
    data, err = handler._body()
    if err and err != "no body":
        return handler._error(400, err)
    data = data if isinstance(data, dict) else {}
    if parts == ["save"]:
        return handler._result(save(srv, data.get("json"), data.get("base_mtime")))
    return handler._error(404, "unknown API path")

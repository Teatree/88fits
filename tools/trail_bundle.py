"""Pass 130 (lane HOUSE): the Trail's bundle for the Python tools (watch.py, sim_batch.py, replay.py).

Garry: "whenever we do show the level of trail, we also show the stats increases as just a bundle (a list of
comma-separated increases) ... in one build, the trail is giving one set of stat increases and in the other build it's
giving a different set. It's important to know which is which."

One line that says what a Trail gives: "Attack damage +12%, Max health +30%, Reroll a run +2 · unlocks: 2 outlaws,
3 items, 1 stage"; "nothing yet" for a Trail that gives nothing. This file is the twin of game/core/systems/Trail.gd
(bundle_text, tally, amount_text) as tools/level_editor/trail_bundle.js is: CHANGE ALL THREE. The fixture
game/tests/fixtures/trail_bundle.json pins them together (tools/level_editor/selftest_HOUSE130.py runs this file and
the JavaScript on it, game/tests/pass130_HOUSE_test.gd the GDScript).

    python tools/trail_bundle.py [none|quarter|half|full|<level>] [--optional] [--file <trail.json>]

prints the bundle of that Trail Level on the game's own Trail file (every level's when no level is named).
"""
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TRAIL_FILE = os.path.join(HERE, "..", "game", "content", "trail", "trail.json")

EMPTY = "nothing yet"
# [one, many, the gift types counted together], in the order they are written (Trail.UNLOCK_WORDS)
UNLOCK_WORDS = [("outlaw", "outlaws", ("outlaw",)), ("skin", "skins", ("skin",)), ("item", "items", ("weapon", "passive")),
                ("stage", "stages", ("stage",)), ("map", "maps", ("map",)), ("structure", "structures", ("structure",)),
                ("power-up", "power-ups", ("powerup",)), ("feature", "features", ("feature",))]
GIFTS = ["upgrade", "outlaw", "skin", "weapon", "passive", "stage", "map", "structure", "powerup", "feature"]
NAMED = {"none": 0.0, "quarter": 0.25, "half": 0.5, "full": 1.0}
MINUS = "−"


def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _num(v, fallback):
    return float(v) if _is_num(v) else fallback


def _gd_round(v):
    """Godot's round(): half away from zero."""
    return int(-math.floor(-v + 0.5)) if v < 0 else int(math.floor(v + 0.5))


def plain(a):
    """Trail._plain: a whole number as it is, else one decimal when that says it, else two."""
    if abs(a - _gd_round(a)) < 0.001:
        return str(_gd_round(a))
    if abs(a * 10.0 - _gd_round(a * 10.0)) < 0.001:
        return "%.1f" % a
    return "%.2f" % a


def amount_text(kind, value):
    """Trail.amount_text: "+3%", "+2.5%", "+2", "+0.3", "+2 s"; "" for a word."""
    sg = "+" if value >= 0 else MINUS
    a = abs(value)
    if kind == "percent":
        return sg + plain(a * 100.0) + "%"
    if kind == "count":
        return sg + str(_gd_round(a))
    if kind == "seconds":
        return sg + plain(a) + " s"
    if kind == "word":
        return ""
    return sg + plain(a)


def _s(v):
    return "" if v is None else str(v)


def bundle_text(block, types=None):
    """Trail.bundle_text: the line from a block's `upgrades` {type: summed value}, in the block's own order with the
    words of its `types` {type: {name, kind, text}} when it carries them; a block without `types` reads by `types` (a
    Trail file's `upgrades`), in that file's order. Then the block's `unlocks` {gift type: count} in short."""
    b = block if isinstance(block, dict) else {}
    ups = b.get("upgrades") if isinstance(b.get("upgrades"), dict) else {}
    own = b.get("types") if isinstance(b.get("types"), dict) else None
    build = types if isinstance(types, dict) else {}
    if own is not None:
        order = list(ups.keys())
    else:
        order = [t for t in build.keys() if t in ups]
        order += [t for t in ups.keys() if t not in order]
    parts = []
    for t in order:
        uv = own.get(t) if own is not None else build.get(t)
        u = uv if isinstance(uv, dict) else {}
        kind = "flat" if u.get("kind") is None else str(u.get("kind"))
        name = _s(u.get("name"))
        words = _s(u.get("text"))
        if kind == "word":
            parts.append(name if name != "" else (words if words != "" else str(t)))
            continue
        value = _num(ups[t], 0.0)
        if abs(value) < 0.0000001:
            continue
        parts.append("%s %s" % (words if words != "" else (name if name != "" else str(t)), amount_text(kind, value)))
    got = []
    un = b.get("unlocks")
    if isinstance(un, dict):
        for one, many, gifts in UNLOCK_WORDS:
            n = sum(_gd_round(un[g]) for g in gifts if _is_num(un.get(g)))
            if n > 0:
                got.append("%d %s" % (n, one if n == 1 else many))
    out = ", ".join(parts)
    if got:
        out += (" · " if out != "" else "") + "unlocks: " + ", ".join(got)
    return out if out != "" else EMPTY


def of(trail, types=None):
    """A record's `trail` block as its bundle: the line the record carries (`bundle`, written by the build that played
    the run), else the line worked out from its `upgrades` and `types`; "" for no block at all."""
    if not isinstance(trail, dict):
        return ""
    if isinstance(trail.get("bundle"), str) and trail["bundle"] != "":
        return trail["bundle"]
    return bundle_text(trail, types)


def nodes_of(data):
    """A Trail file's nodes as the rules read them (Trail._norm): an id once, kind node | choice | optional, level >= 1."""
    out, seen = [], set()
    for e in (data.get("nodes") if isinstance(data, dict) and isinstance(data.get("nodes"), list) else []):
        if not isinstance(e, dict):
            continue
        nid = _s(e.get("id"))
        if nid == "" or nid in seen:
            continue
        seen.add(nid)
        kind = e.get("kind") if e.get("kind") in ("choice", "optional") else "node"
        out.append({"id": nid, "level": max(_gd_round(e["level"]) if _is_num(e.get("level")) else 1, 1), "kind": kind,
                    "group": _s(e.get("group")) if kind == "choice" else "",
                    "gives": e.get("gives") if isinstance(e.get("gives"), dict) else {}})
    return out


def levels_of(data):
    return max([n["level"] for n in nodes_of(data)] or [0])


def _snap4(v):
    return math.floor(v / 0.0001 + 0.5) * 0.0001


def tally(data, ids):
    """Trail.tally: what the nodes `ids` of a Trail file give, added up: {upgrades (the file's order of upgrade types),
    unlocks (GIFTS' order)}. Ids the file has no node for are skipped."""
    by_id = dict((n["id"], n) for n in nodes_of(data))
    sums, gifts = {}, {}
    for raw in ids or []:
        n = by_id.get(str(raw))
        if n is None:
            continue
        g = n["gives"]
        gtype = _s(g.get("type"))
        if gtype == "upgrade":
            ut = _s(g.get("upgrade"))
            sums[ut] = sums.get(ut, 0.0) + _num(g.get("value"), 0.0)
        elif gtype != "":
            gifts[gtype] = gifts.get(gtype, 0) + 1
    build = data.get("upgrades") if isinstance(data, dict) and isinstance(data.get("upgrades"), dict) else {}
    upgrades = {}
    for ut in build.keys():
        if ut in sums:
            upgrades[ut] = _snap4(sums[ut])
    for ut in sums.keys():
        if ut not in upgrades:
            upgrades[ut] = _snap4(sums[ut])
    unlocks = dict((g, gifts[g]) for g in GIFTS if gifts.get(g))
    return {"upgrades": upgrades, "unlocks": unlocks}


def level_of(arg, levels):
    """trail_arg.gd level_of: a name's share of the levels (rounded half up), a number kept inside 0..levels; -1 else."""
    a = _s(arg).strip().lower()
    if a == "":
        return 0
    if a in NAMED:
        return int(math.floor(NAMED[a] * levels + 0.5))
    if re.match(r"^[+-]?\d+$", a):
        return max(0, min(int(levels), int(a)))
    return -1


def ids_upto(data, level, optional=False):
    """trail_arg.gd ids_upto: every plain node of levels 1..level, one member of each choice group in turn (the k-th
    group in file order its member k mod its size), the optional nodes only with `optional`."""
    nodes = nodes_of(data)
    groups, order = {}, []
    for n in nodes:
        if n["kind"] == "choice":
            key = (n["level"], n["group"])
            if key not in groups:
                groups[key] = []
                order.append(key)
            groups[key].append(n["id"])
    pick = set(groups[key][k % len(groups[key])] for k, key in enumerate(order))
    return [n["id"] for n in nodes if n["level"] <= level
            and (n["kind"] == "node" or (n["kind"] == "choice" and n["id"] in pick) or (n["kind"] == "optional" and optional))]


def read_trail(path=None):
    """The Trail file as it is ({} when it cannot be read)."""
    try:
        with open(path or TRAIL_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def for_ids(ids, data=None):
    """The bundle of the nodes `ids` on the Trail file `data` (the game's own when None)."""
    data = read_trail() if data is None else data
    return bundle_text(tally(data, ids), data.get("upgrades"))


def for_arg(arg, optional=False, data=None):
    """The bundle of the Trail a trail= argument names (none, quarter, half, full or a level) on the Trail file `data`
    (the game's own when None); "" for an argument that names nothing."""
    data = read_trail() if data is None else data
    lv = level_of(arg, levels_of(data))
    if lv < 0:
        return ""
    return for_ids(ids_upto(data, lv, optional), data)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    optional = "--optional" in argv
    path = None
    if "--file" in argv:
        i = argv.index("--file")
        path = argv[i + 1] if i + 1 < len(argv) else None
        args = [a for a in args if a != path]
    data = read_trail(path)
    levels = levels_of(data)
    if not data:
        print("no Trail file at %s" % (path or TRAIL_FILE))
        return 1
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass
    if args:
        lv = level_of(args[0], levels)
        if lv < 0:
            print("'%s' is not none, quarter, half, full or a level (0 to %d)" % (args[0], levels))
            return 1
        print("Trail Level %d of %d: %s" % (lv, levels, for_arg(args[0], optional, data)))
        return 0
    for lv in range(0, levels + 1):
        print("Trail Level %d of %d: %s" % (lv, levels, for_arg(str(lv), optional, data)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

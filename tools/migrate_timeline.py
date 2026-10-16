#!/usr/bin/env python3
"""Pass 84 (lane SPAWN): one spawning language. An old map's swarm / elite / elite_every events and waves[] entries
become roster rows (WaveTimeline "Pass 84" keys, docs/waves_schema.md "Pass 84"); bosses and Elite mini-bosses stay
events. The same converter as the Level Editor's tools/level_editor/model.js convertLegacy (the page converts on load
and saves rows); tools/level_editor/selftest_SPAWN84.py checks the two agree on every legacy kind.

    python tools/migrate_timeline.py --map red_canyon            # what it would do (nothing written)
    python tools/migrate_timeline.py --map red_canyon --write    # backup in tools/level_editor/backups/, then the file
    python tools/migrate_timeline.py --map red_canyon --check    # exit 1 while the map still has something to convert

The file is written the way the Level Editor writes it (json.dumps indent 2, ensure_ascii False, a final newline): only
the roster (rows appended after the old ones, so their places and fixed-number keys stay) and the events (the converted
ones gone) change; every number Garry set is kept as it was. Standard library only.
"""
import argparse
import copy
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

ROW_ENEMY_ROSTER = "roster"
SWARM_RING_RADIUS = 16
SWARM_COUNT_DEF = 40
ELITE_EVERY_DEF = 90
WAVE_BURST_DEF = 5
ROW84_ORDER = ["id", "name", "t", "until", "enemy", "enemy_weights", "variant", "weights", "pace", "every", "offset", "count",
               "pattern", "ring_radius", "pack", "respect_cap", "respect_hard_cap", "channel", "elite", "special", "banner", "chance", "t_jitter", "role", "stats"]
LEGACY_EVENTS = ("swarm", "elite", "elite_every")


def _num(v, d):
    """model.js num(): a number, or `d` for a missing, empty or non-numeric value."""
    if v is None or v == "" or isinstance(v, (dict, list, bool)):
        return d
    try:
        n = float(v)
    except (TypeError, ValueError):
        return d
    return n if math.isfinite(n) else d


def _trunc(v):
    return int(math.ceil(v)) if v < 0 else int(math.floor(v))


def _has(o, k):
    return isinstance(o, dict) and k in o and o[k] is not None and o[k] != ""


def _ordered(o):
    out = {}
    for k in ROW84_ORDER:
        if k in o:
            out[k] = o[k]
    for k in o:
        if k not in out:
            out[k] = o[k]
    return out


def _int_like(x):
    """A JS number written back as JSON: 3.0 -> 3 (JSON.stringify drops the .0), so the twins' output compares equal."""
    if isinstance(x, float) and x.is_integer():
        return int(x)
    return x


def event_to_row(ev, skin=""):
    """model.js eventToRow."""
    if not isinstance(ev, dict):
        return None
    typ = str("" if ev.get("type") is None else ev.get("type"))
    if typ not in LEGACY_EVENTS:
        return None
    t = 0 if ev.get("t") is None else ev["t"]
    r = {"t": t}
    r["name"] = ev["name"] if _has(ev, "name") else ("Swarm" if typ == "swarm" else "Coloured elite" if typ == "elite" else "Elites every")
    enemy = copy.deepcopy(ev["enemy"]) if _has(ev, "enemy") and not (isinstance(ev["enemy"], list) and not ev["enemy"]) else ""
    if typ == "swarm" and enemy == "" and skin:
        enemy = str(skin)
    if typ != "swarm" and enemy == "":
        enemy = ROW_ENEMY_ROSTER
    r["enemy"] = enemy
    if isinstance(enemy, list) and isinstance(ev.get("weights"), list) and ev["weights"]:
        r["enemy_weights"] = copy.deepcopy(ev["weights"])
    if _has(ev, "variant"):
        r["variant"] = ev["variant"]
    r["weights"] = [[t, 1]]
    if _has(ev, "chance"):
        r["chance"] = ev["chance"]
    if _has(ev, "t_jitter"):
        r["t_jitter"] = ev["t_jitter"]
    if typ == "swarm":
        count = SWARM_COUNT_DEF if ev.get("count") is None or ev.get("count") == "" else _trunc(_num(ev.get("count"), SWARM_COUNT_DEF))
        p = str("" if ev.get("pattern") is None else ev.get("pattern"))
        pattern = p if p in ("pack", "scatter", "in_front") else "ring"
        r.update({"pace": "once", "count": count, "pattern": pattern})
        if pattern == "ring":
            r["ring_radius"] = SWARM_RING_RADIUS
        if pattern == "pack":
            r["pack"] = _trunc(_num(ev.get("pack"), 0)) if _num(ev.get("pack"), 0) > 0 else count
        r["respect_cap"] = False
        r["respect_hard_cap"] = False
        if ev.get("special"):
            r["special"] = True
        else:
            r["banner"] = "SWARM!"
        r["role"] = "special" if ev.get("special") else "swarm"
    else:
        r["pace"] = "once" if typ == "elite" else "waves"
        if typ == "elite_every":
            r["every"] = ELITE_EVERY_DEF if ev.get("interval") is None or ev.get("interval") == "" else copy.deepcopy(ev["interval"])
        r["count"] = 1
        r["respect_cap"] = False
        r["elite"] = str(ev["mod"]) if _has(ev, "mod") else "random"
        r["role"] = "elite"
    if isinstance(ev.get("stats"), dict) and ev["stats"]:
        r["stats"] = copy.deepcopy(ev["stats"])
    return r


def wave_to_rows(w, notes):
    """model.js waveToRows."""
    if not isinstance(w, dict):
        return []
    t = 0 if w.get("t") is None else w["t"]
    burst = max(_trunc(_num(w.get("burst"), WAVE_BURST_DEF)), 1)
    every = _num(w.get("every"), 0)
    total = max(_trunc(_num(w.get("count"), 0)), 0)
    label = w["name"] if _has(w, "name") else w["id"] if _has(w, "id") else ""
    alts = [a for a in w.get("alts")] if isinstance(w.get("alts"), list) else []
    alts = [a for a in alts if isinstance(a, dict)]
    lst = alts if alts else [w]
    s = 0.0
    for a in alts:
        s += max(_num(a.get("chance"), 1), 0)
    out = []
    for a in lst:
        r = {"t": t}
        if label != "":
            r["name"] = label
        if every > 0:
            until = _num(t, 0) + every * math.ceil(total / burst) if total > 0 else None
            if _has(w, "until"):
                until = _num(w["until"], 0) if until is None else min(until, _num(w["until"], 0))
            if until is not None:
                r["until"] = _int_like(until)
        elif _has(w, "until"):
            r["until"] = w["until"]
        r["enemy"] = copy.deepcopy(a["enemy"]) if _has(a, "enemy") else ""
        if _has(a, "variant"):
            r["variant"] = a["variant"]
        r["weights"] = [[t, 1]]
        if every > 0:
            r.update({"pace": "waves", "every": _int_like(every), "count": burst})
        else:
            r["pace"] = "once"
            r["count"] = min(burst, total) if total > 0 else burst
        if _has(w, "pattern"):
            r["pattern"] = w["pattern"]
        if _has(a, "pack"):
            r["pack"] = a["pack"]
        if w.get("respect_cap") is False:
            r["respect_cap"] = False
        if w.get("channel") == "hell":
            r["channel"] = "hell"
        if _has(w, "elite"):
            r["elite"] = str(w["elite"])
        if _has(w, "toast"):
            r["banner"] = w["toast"]
        if len(alts) > 1:
            r["chance"] = _int_like(max(_num(a.get("chance"), 1), 0) / s if s > 0 else 0)
        if isinstance(a.get("stats"), dict) and a["stats"]:
            r["stats"] = copy.deepcopy(a["stats"])
        out.append(r)
    name = label or "@%s" % (_int_like(t),)
    if len(alts) > 1:
        notes.append("wave %s: its %d alternatives became %d rows, each with its share as its chance (rolled apart now, not one of them)" % (name, len(alts), len(alts)))
    if every > 0 and total > 0 and total % burst:
        notes.append("wave %s: its last burst brought %d, the row's last wave brings %d" % (name, total % burst, burst))
    if _has(w, "elite"):
        notes.append("wave %s: its elite creatures wait for colour now (they came plain before it)" % name)
    return out


def convert_legacy(tl, skin=""):
    """model.js convertLegacy, in place: {converted, events, waves, ids, notes}."""
    res = {"converted": 0, "events": 0, "waves": 0, "ids": [], "notes": []}
    if not isinstance(tl, dict):
        return res
    evs = tl.get("events") if isinstance(tl.get("events"), list) else []
    wvs = tl.get("waves") if isinstance(tl.get("waves"), list) else []
    rows, keep = [], []
    for ev in evs:
        r = event_to_row(ev, skin)
        if r:
            rows.append(r)
            res["events"] += 1
        else:
            keep.append(ev)
    for w in wvs:
        rs = wave_to_rows(w, res["notes"])
        if rs:
            rows.extend(rs)
            res["waves"] += 1
    if not rows:
        return res
    if not isinstance(tl.get("roster"), list):
        tl["roster"] = []
    used = set(r.get("id") for r in tl["roster"] if isinstance(r, dict))
    n = 1
    for r in rows:
        while ("r%d" % n) in used:
            n += 1
        r["id"] = "r%d" % n
        used.add(r["id"])
        tl["roster"].append(_ordered(r))
        res["ids"].append(r["id"])
    if res["events"]:
        tl["events"] = keep
    if res["waves"]:
        tl["waves"] = []
    res["converted"] = len(rows)
    return res


def has_legacy(tl):
    if not isinstance(tl, dict):
        return False
    if isinstance(tl.get("waves"), list) and any(isinstance(w, dict) for w in tl["waves"]):
        return True
    return any(isinstance(ev, dict) and str(ev.get("type")) in LEGACY_EVENTS for ev in (tl.get("events") or []))


def map_file(map_id):
    return os.path.join(ROOT, "game", "content", "maps", map_id, map_id + ".json")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--map", default="red_canyon")
    ap.add_argument("--file", default="", help="another map JSON (a test's copy)")
    ap.add_argument("--write", action="store_true", help="write the converted map (a backup first)")
    ap.add_argument("--check", action="store_true", help="exit 1 while something is left to convert")
    ap.add_argument("--no-backup", action="store_true", help="--write without the backup (a test's copy)")
    a = ap.parse_args(argv)
    path = os.path.abspath(a.file) if a.file else map_file(a.map)
    with open(path, "rb") as f:
        raw = f.read()
    data = json.loads(raw.decode("utf-8"))
    tl = data.get("timeline_data")
    if not isinstance(tl, dict):
        print("migrate_timeline: %s has no timeline_data" % path)
        return 2
    if a.check:
        left = has_legacy(tl)
        print("migrate_timeline: %s %s" % (os.path.basename(path), "still has events or waves to convert" if left else "is rows only"))
        return 1 if left else 0
    skins = data.get("skins") if isinstance(data.get("skins"), dict) else {}
    skin = str(list(skins.values())[0]) if skins else ""
    res = convert_legacy(tl, skin)
    print("migrate_timeline: %s: %d rows from %d events and %d waves (ids %s)" % (
        os.path.basename(path), res["converted"], res["events"], res["waves"], ", ".join(res["ids"]) or "none"))
    for n in res["notes"]:
        print("  note: " + n)
    if not res["converted"] or not a.write:
        return 0
    # the editor's own writer (server.write_map): the file round-trips through it byte for byte
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if not a.no_backup:
        sys.path.insert(0, os.path.join(HERE, "level_editor"))
        import server  # noqa: E402  (its backup(): tools/level_editor/backups/<map>-<stamp>.json)
        print("migrate_timeline: backup %s" % server.backup(a.map, path))
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)
    print("migrate_timeline: wrote %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())

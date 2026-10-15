"""The run record's CSVs for every run file in a folder at once (pass 74, Garry: "Make it so that I can actually download
the data as a .csv file"). The same files analytics/dashboard.html's buttons give for one run (its csv-lib script; the
lane's test runs both on one record and compares them byte for byte, so change the two together).

usage: python tools/analytics_csv.py [--runs <folder>] [--tools] [--out <folder>] [--only <stamp> ...] [--no-history]
  --runs      the folder of run files (default analytics/runs: the runs played from the editor binary; the PC build's
              are in %APPDATA%\\Godot\\app_userdata\\88fits\\analytics\\runs)
  --tools     analytics/runs/tools (the tool runs: smoke_run, perf_late, captures) instead
  --out       where the CSVs go (default analytics/runs/csv/played, .../tools or .../other: git ignores them all)
  --only      only these runs (stamps like 2026-10-14T14-59-23, or file names)
  --no-history  no history file
Writes, for every run file: 88fits_<stamp>_rows.csv (one line a second of play, every column; a map as group.key; the
build's snapshots carried forward) and 88fits_<stamp>_events.csv (one line an event, every field a column); and one
88fits_<now>_history.csv: a line per run file, every header field (the line the game writes to the index, made here
from the file). UTF-8 with a BOM (Excel), commas, numbers with a dot, CR LF line ends.
"""
import argparse
import datetime
import decimal
import glob
import json
import math
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BOM = "﻿"
# the row's plain keys, in this order; a key the record left out is 0 (it means 0), boss_hp and boss_now empty (no boss
# up). Pass 78: the pass-77 keys xp_total, hp_lost, hp_healed, boss_now, near3, near6 (the page's list is the same)
BASE = ["t", "clock", "stage", "phase", "wave", "level", "xp", "xp_next", "xp_total", "hp", "hp_max", "shield", "invuln", "gold",
        "banked", "kills", "adren", "cresc", "desp", "steady", "est_total", "took_raw", "hits", "evaded", "shielded", "healed",
        "regen", "hp_lost", "hp_healed", "elite_kills", "alive", "cap", "load", "hard_cap", "press", "press_hp", "press_dmg",
        "boss_hp", "boss_now", "specials_alive", "near3", "near6"]
EMPTY_WHEN_MISSING = ["boss_hp", "boss_now"]
# the second's tallies by id, flattened as group.key; a missing one is 0
MAPS = ["est", "dmg", "took", "took_kind", "hits_by", "healed_by", "killed", "spawned", "alive_by", "gold_in", "gold_out"]
# the build's snapshots: on a row only when they changed; carried forward to every second until the next one
CARRY = ["mults", "stats", "weapons", "passives", "lines", "perks"]
WEAPON_FIELDS = ["level", "dmg", "cd", "amount", "pierce", "area", "est", "mut"]
EVENT_FIRST = ["t", "clock", "kind", "id", "name", "level"]
HISTORY_FIRST = ["file", "stamp", "started", "version", "schema", "tool", "headless", "hero", "hero_name", "hero_look",
                 "map", "map_rev", "seed", "result", "length", "clock", "stage", "endless_wave", "level", "kills", "gold",
                 "strongbox", "revives", "gold_before", "damage", "top_source", "dps_end", "hp_lost", "hits_taken", "bosses",
                 "specials_killed", "elites_killed", "killer", "totems", "talents", "build"]
# RunAnalytics.INDEX_SKIP: the header blocks the index leaves out
INDEX_SKIP = ["names", "hit_log", "samples", "events", "build", "totals", "timeline", "quests", "talents", "talent_forms",
              "totems", "stat_names", "build_text"]

_MISSING = object()


# ---------------------------------------------------------------- JavaScript's way with values (the page's CSVs)

def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def js_num(x):
    """String(x) for a JavaScript number: the shortest digits that read back, as JS lays them out."""
    if isinstance(x, int):
        if abs(x) < 2 ** 53:
            return str(x)
        x = float(x)
    if not math.isfinite(x):
        return ""
    if x == 0:
        return "0"
    sign = "-" if x < 0 else ""
    d = decimal.Decimal(repr(abs(x)))
    _, digits, exp = d.as_tuple()
    ds = "".join(str(c) for c in digits).rstrip("0") or "0"
    # the decimal point sits n digits into ds
    n = len(digits) + exp
    k = len(ds)
    if k <= n <= 21:
        s = ds + "0" * (n - k)
    elif 0 < n <= 21:
        s = ds[:n] + "." + ds[n:]
    elif -6 < n <= 0:
        s = "0." + "0" * (-n) + ds
    else:
        e = n - 1
        s = ds[0] + ("." + ds[1:] if k > 1 else "") + "e" + ("+" if e >= 0 else "-") + str(abs(e))
    return sign + s


def js_str(v):
    """String(v) for a value read from JSON (a missing key is undefined)."""
    if v is _MISSING:
        return "undefined"
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if is_num(v):
        return js_num(v)
    if isinstance(v, str):
        return v
    if isinstance(v, list):
        return ",".join("" if x is None else js_str(x) for x in v)
    return "[object Object]"


def js_json(v):
    """JSON.stringify(v)."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if is_num(v):
        return js_num(v) if math.isfinite(v) else "null"
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ",".join(js_json(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ",".join(json.dumps(str(k), ensure_ascii=False) + ":" + js_json(x) for k, x in v.items()) + "}"
    return json.dumps(str(v), ensure_ascii=False)


def text(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if is_num(v):
        return js_num(v) if math.isfinite(v) else ""
    if isinstance(v, str):
        return v
    if isinstance(v, list):
        return "; ".join(js_json(x) if isinstance(x, (dict, list)) else text(x) for x in v)
    return js_json(v)


_QUOTE = re.compile(r'[",\r\n]')


def cell(v):
    s = text(v)
    if _QUOTE.search(s) or re.match(r"\s", s) or re.search(r"\s\Z", s):
        return '"' + s.replace('"', '""') + '"'
    return s


def to_csv(columns, rows):
    out = [",".join(cell(c) for c in columns)]
    for r in rows:
        out.append(",".join(cell(v) for v in r))
    return "\r\n".join(out) + "\r\n"


def _t(r):
    t = r.get("t") if isinstance(r, dict) else None
    return float(t) if is_num(t) and math.isfinite(t) else 0.0


# ---------------------------------------------------------------- the three tables (dashboard.html's csv-lib)

def rows_table(run):
    """This run's rows: one line a second, every scalar column, each map flattened as group.key."""
    rows = sorted([r for r in (run.get("samples") or []) if isinstance(r, dict)], key=_t)
    base, extra, extra_maps, map_keys = set(), set(), set(), {}
    carry = {"mults": set(), "stats": set(), "passives": set(), "lines": set()}
    wids, wfields = [], set()
    perks = False
    for r in rows:
        for k, v in r.items():
            if k in BASE:
                base.add(k)
                continue
            if k in CARRY:
                if k == "weapons":
                    for w in (v if isinstance(v, list) else []):
                        if not isinstance(w, dict):
                            continue
                        wid = js_str(w.get("id", _MISSING))
                        if wid not in wids:
                            wids.append(wid)
                        for f in w:
                            if f != "id":
                                wfields.add(f)
                elif k == "perks":
                    perks = True
                elif isinstance(v, dict):
                    carry[k].update(v.keys())
                continue
            if k in MAPS or isinstance(v, dict):
                if k not in MAPS:
                    extra_maps.add(k)
                map_keys.setdefault(k, set())
                if isinstance(v, dict):
                    map_keys[k].update(v.keys())
                continue
            extra.add(k)
    base_cols = [k for k in BASE if k in base]
    extra_cols = sorted(extra)
    maps = [g for g in MAPS if g in map_keys] + sorted(extra_maps)
    map_cols = [(g, sorted(map_keys[g])) for g in maps]
    wf = [f for f in WEAPON_FIELDS if f in wfields] + sorted(f for f in wfields if f not in WEAPON_FIELDS)
    cols = base_cols + extra_cols
    for g, ks in map_cols:
        cols += [g + "." + k for k in ks]
    mults_k, stats_k = sorted(carry["mults"]), sorted(carry["stats"])
    pass_k, lines_k = sorted(carry["passives"]), sorted(carry["lines"])
    cols += ["mults." + k for k in mults_k] + ["stats." + k for k in stats_k]
    for wid in wids:
        cols += ["weapons." + wid + "." + f for f in wf]
    cols += ["passives." + k for k in pass_k] + ["lines." + k for k in lines_k]
    if perks:
        cols.append("perks")
    # a run that ended before its first second still gets a header
    if not cols:
        return ["t"], []
    st = {g: None for g in CARRY}

    def pick(o, k):
        return o[k] if isinstance(o, dict) and k in o and o[k] is not None else ""

    out = []
    for r in rows:
        for g in CARRY:
            if g in r:
                st[g] = r[g]
        line = []
        for k in base_cols:
            line.append(r[k] if k in r and r[k] is not None else ("" if k in EMPTY_WHEN_MISSING else 0))
        for k in extra_cols:
            line.append(r[k] if k in r and r[k] is not None else "")
        for g, ks in map_cols:
            m = r.get(g)
            for k in ks:
                line.append(m[k] if isinstance(m, dict) and k in m and m[k] is not None else 0)
        line += [pick(st["mults"], k) for k in mults_k]
        line += [pick(st["stats"], k) for k in stats_k]
        for wid in wids:
            w = None
            if isinstance(st["weapons"], list):
                for x in st["weapons"]:
                    if isinstance(x, dict) and js_str(x.get("id", _MISSING)) == wid:
                        w = x
                        break
            line += [pick(w, f) for f in wf]
        line += [pick(st["passives"], k) for k in pass_k]
        line += [pick(st["lines"], k) for k in lines_k]
        if perks:
            line.append(st["perks"] if isinstance(st["perks"], list) else "")
        out.append(line)
    return cols, out


def events_table(run):
    """This run's events: one line each, every field a column (the id's name beside it)."""
    evs = sorted([e for e in (run.get("events") or []) if isinstance(e, dict)], key=_t)
    names = run.get("names") if isinstance(run.get("names"), dict) else {}
    keys = set()
    for e in evs:
        keys.update(e.keys())
    cols = EVENT_FIRST + [k for k in sorted(keys) if k not in EVENT_FIRST]
    out = []
    for e in evs:
        line = []
        for k in cols:
            if k == "name":
                nid = js_str(e["id"]) if "id" in e else None
                line.append(names[nid] if nid is not None and nid in names else (e["name"] if "name" in e else ""))
            else:
                line.append(e[k] if k in e and e[k] is not None else "")
        out.append(line)
    return cols, out


def history_table(runs):
    """The history: one line per run, every field a column."""
    lst = [r for r in runs if isinstance(r, dict)]
    keys = set()
    for r in lst:
        keys.update(r.keys())
    cols = [k for k in HISTORY_FIRST if k in keys] + [k for k in sorted(keys) if k not in HISTORY_FIRST]
    return cols, [[r[k] if k in r and r[k] is not None else "" for k in cols] for r in lst]


# ---------------------------------------------------------------- the index row from a run file (RunAnalytics.index_row)

def flatten_into(row, key, v):
    if isinstance(v, dict):
        for k, x in v.items():
            flatten_into(row, key + "." + str(k), x)
    elif isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            row[key] = "; ".join(_gd_str(x) for x in v)
        else:
            row[key] = len(v)
    else:
        row[key] = v


def _gd_str(x):
    if x is None:
        return "<null>"
    if isinstance(x, bool):
        return "true" if x else "false"
    return str(x)


def _build_text(d):
    """A record without build_text (before schema 2): its build in one line (the file's order: its keys are sorted)."""
    names = d.get("names") or {}
    nm = lambda i: names.get(i, i)
    b = d.get("build") or {}
    ws = []
    for w in b.get("weapons") or []:
        muts = w.get("mutations") or []
        ws.append("%s %d%s" % (nm(str(w.get("id", ""))), int(w.get("level", 1)), (" +%d" % len(muts)) if muts else ""))
    ps = ["%s %d" % (nm(str(i)), int(lv)) for i, lv in list((b.get("passives") or {}).items()) + list((b.get("lines") or {}).items())]
    ks = [nm(str(i)) for i in b.get("perks") or []]
    return " | ".join(" · ".join(g) for g in (ws, ps, ks) if g)


def index_row(d, fname):
    row = {"file": str(d.get("stamp", os.path.splitext(fname)[0])) + ".json"}
    for k, v in d.items():
        if k not in INDEX_SKIP:
            flatten_into(row, k, v)
    ranks = 0
    tal = d.get("talents")
    if isinstance(tal, dict):
        for tid, picks in tal.items():
            n = len(picks) if isinstance(picks, list) else 0
            row["talents." + str(tid)] = n
            ranks += n
    row["talents"] = ranks
    row["totems"] = len(d["totems"]) if isinstance(d.get("totems"), list) else 0
    dbw = (d.get("totals") or {}).get("damage_by_weapon") or {}
    dmg, top, top_v = 0.0, "", -1.0
    for i, v in dbw.items():
        v = float(v)
        dmg += v
        if v > top_v:
            top_v, top = v, str(i)
    # Godot's roundf (half away from zero) and snappedf, then its JSON's 15 significant digits, as the index holds them
    row["damage"] = math.copysign(math.floor(abs(dmg) + 0.5), dmg)
    row["top_source"] = top
    lost, hits = 0.0, 0
    samples = [r for r in d.get("samples") or [] if isinstance(r, dict)]
    for r in samples:
        tk = r.get("took")
        if isinstance(tk, dict):
            lost += sum(float(x) for x in tk.values())
        hits += int(r.get("hits", 0) or 0)
    row["hp_lost"] = float("%.15g" % (math.floor(lost / 0.1 + 0.5) * 0.1))
    row["hits_taken"] = hits
    row["dps_end"] = float(samples[-1].get("est_total", 0.0)) if samples else 0.0
    row["build"] = str(d["build_text"]) if "build_text" in d else _build_text(d)
    counts = {"boss_end": 0, "special_kill": 0, "elite_kill": 0}
    killer = ""
    for e in d.get("events") or []:
        kind = str(e.get("kind", ""))
        if kind in counts:
            counts[kind] += 1
        elif kind == "death":
            killer = str(e.get("id", ""))
    row["bosses"] = counts["boss_end"]
    row["specials_killed"] = counts["special_kill"]
    row["elites_killed"] = counts["elite_kill"]
    row["killer"] = killer
    return row


# ---------------------------------------------------------------- files

def read_run(path):
    with open(path, encoding="utf-8-sig") as f:
        s = f.read().strip()
    m = re.match(r"^window\.RUN\s*=\s*", s)
    if m:
        s = re.sub(r";\s*$", "", s[m.end():])
    return json.loads(s)


def write_csv(path, columns, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(BOM + to_csv(columns, rows))


def now_stamp():
    return datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--runs", default=None)
    ap.add_argument("--tools", action="store_true")
    ap.add_argument("--out", default=None)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--no-history", action="store_true")
    a = ap.parse_args(argv)
    if a.runs:
        runs_dir, kind = os.path.abspath(a.runs), "other"
    elif a.tools:
        runs_dir, kind = os.path.join(ROOT, "analytics", "runs", "tools"), "tools"
    else:
        runs_dir, kind = os.path.join(ROOT, "analytics", "runs"), "played"
    if not os.path.isdir(runs_dir):
        print("no folder %s" % runs_dir)
        return 2
    out_dir = os.path.abspath(a.out) if a.out else os.path.join(ROOT, "analytics", "runs", "csv", kind)
    os.makedirs(out_dir, exist_ok=True)
    files = sorted(f for f in glob.glob(os.path.join(runs_dir, "*.json")) if os.path.basename(f) != "index.json")
    if a.only:
        want = set(os.path.splitext(os.path.basename(x))[0] for x in a.only)
        files = [f for f in files if os.path.splitext(os.path.basename(f))[0] in want]
    hist, n = [], 0
    for path in files:
        fname = os.path.basename(path)
        try:
            run = read_run(path)
        except Exception as e:  # a half-written or foreign file: said and skipped
            print("skipped %s: %s" % (fname, e))
            continue
        if not isinstance(run, dict) or "samples" not in run:
            print("skipped %s: not a run file" % fname)
            continue
        stamp = str(run.get("stamp") or os.path.splitext(fname)[0])
        cols, rows = rows_table(run)
        write_csv(os.path.join(out_dir, "88fits_%s_rows.csv" % stamp), cols, rows)
        cols, rows = events_table(run)
        write_csv(os.path.join(out_dir, "88fits_%s_events.csv" % stamp), cols, rows)
        hist.append(index_row(run, fname))
        n += 1
    if hist and not a.no_history:
        cols, rows = history_table(hist)
        write_csv(os.path.join(out_dir, "88fits_%s_history%s.csv" % (now_stamp(), "_tools" if kind == "tools" else "")), cols, rows)
    print("analytics_csv: %d run files from %s -> %s%s" % (n, runs_dir, out_dir, "" if a.no_history or not hist else " (and a history)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

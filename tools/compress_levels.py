"""Pass 48 (Garry, 2026-10-04: "5 levels for weapons"): every base weapon goes from eight levels to five, the level-8
power kept at level 5.

    python tools/compress_levels.py            # compress (once) and verify
    python tools/compress_levels.py --check    # verify only, nothing written

The new levels are [ [], old 2+3, old 4+5, old 6, old 7+8 ] (old[i] = the effect list at index i of the JSON's
`levels`; index 0 is the empty level 1). Inside a new level the effects that share stat, op and target are merged: adds
summed, muls compounded as (1+a)(1+b)-1 (StatSheet multiplies them), sets keep the last; merged floats are rounded to 4
decimals. `"max_level": 5` is written explicitly (JsonContent's default stays 8). Evolutions are left alone.

Before the first rewrite the old levels of every weapon are frozen in tools/dl/levels_v47.json; every run then prints,
per weapon, its level-5 totals beside the frozen level-8 totals and fails when any differ. A weapon already at five
levels is not compressed again (the script can run twice).
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEAPONS = os.path.join(ROOT, "game", "content", "weapons")
FROZEN = os.path.join(ROOT, "tools", "dl", "levels_v47.json")
GROUPS = [[], [1, 2], [3, 4], [5], [6, 7]]   # old indices that make each new level (new level 1 stays empty)


def key_of(e):
    return (e.get("stat", ""), e.get("op", "add"), e.get("target", "self") or "self")


def merge_level(effects):
    """Effects with the same stat, op and target folded into one, in the order each first appears."""
    out = []
    by_key = {}
    for e in effects:
        k = key_of(e)
        if k not in by_key:
            by_key[k] = dict(e)
            out.append(by_key[k])
            continue
        m = by_key[k]
        a = m.get("value", 0)
        b = e.get("value", 0)
        op = k[1]
        if op == "mul":
            v = (1.0 + a) * (1.0 + b) - 1.0
        elif op == "set":
            v = b
        else:
            v = a + b
        if isinstance(v, float):
            v = round(v, 4)
            if v == int(v) and isinstance(a, int) and isinstance(b, int):
                v = int(v)
        m["value"] = v
    return out


def compress(levels):
    old = list(levels) + [[] for _ in range(max(0, 8 - len(levels)))]
    new = []
    for g in GROUPS:
        lv = []
        for i in g:
            lv.extend(old[i] if isinstance(old[i], list) else [])
        new.append(merge_level(lv))
    return new


def totals(levels, upto):
    """What levels 1..upto add up to, per (stat, op, target): adds summed, muls multiplied (as 1+x), the last set."""
    acc = {}
    for lv in levels[:upto]:
        for e in lv if isinstance(lv, list) else []:
            k = key_of(e)
            v = float(e.get("value", 0))
            if k[1] == "mul":
                acc[k] = acc.get(k, 1.0) * (1.0 + v)
            elif k[1] == "set":
                acc[k] = v
            else:
                acc[k] = acc.get(k, 0.0) + v
    return acc


def fmt(acc):
    parts = []
    for k in sorted(acc):
        stat, op, target = k
        v = acc[k]
        if op == "mul":
            parts.append("%s x%.4g" % (stat, v))
        elif op == "set":
            parts.append("%s =%.4g" % (stat, v))
        else:
            parts.append("%s %+.4g" % (stat, v))
        if target != "self":
            parts[-1] += " (%s)" % target
    return ", ".join(parts)


def write_json(path, data, eol):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(json.dumps(data, indent=2, ensure_ascii=False) + ("\n" if eol else ""))


def with_max_level(d, n):
    """The JSON with "max_level" set to n, placed just before "levels" when it is new."""
    if "max_level" in d:
        d["max_level"] = n
        return d
    out = {}
    for k, v in d.items():
        if k == "levels":
            out["max_level"] = n
        out[k] = v
    if "max_level" not in out:
        out["max_level"] = n
    return out


def main():
    check_only = "--check" in sys.argv
    files = []
    for folder in sorted(os.listdir(WEAPONS)):
        p = os.path.join(WEAPONS, folder, folder + ".json")
        if os.path.isfile(p):
            files.append((folder, p))
    frozen = {}
    if os.path.isfile(FROZEN):
        with open(FROZEN, encoding="utf-8") as f:
            frozen = json.load(f)
    elif check_only:
        print("no frozen copy at %s: nothing to check against" % FROZEN)
        return 1
    else:
        # freeze the old levels before anything is rewritten
        for wid, p in files:
            with open(p, encoding="utf-8") as f:
                frozen[wid] = json.load(f).get("levels", [])
        os.makedirs(os.path.dirname(FROZEN), exist_ok=True)
        with open(FROZEN, "w", encoding="utf-8", newline="") as f:
            f.write(json.dumps(frozen, indent=2, ensure_ascii=False) + "\n")
        print("froze the old levels of %d weapons in %s" % (len(frozen), FROZEN))
    bad = 0
    for wid, p in files:
        with open(p, encoding="utf-8") as f:
            raw = f.read()
        d = json.loads(raw)
        levels = d.get("levels", [])
        done = len(levels) == 5 and int(d.get("max_level", 8)) == 5
        if not done and not check_only:
            d["levels"] = compress(levels)
            d = with_max_level(d, 5)
            write_json(p, d, raw.endswith("\n"))
            levels = d["levels"]
        old = frozen.get(wid)
        if old is None:
            print("%-14s no frozen levels" % wid)
            bad += 1
            continue
        want = totals(old, 8)
        got = totals(levels, 5)
        same = set(want) == set(got) and all(abs(want[k] - got[k]) <= 1e-4 * max(1.0, abs(want[k])) for k in want)
        if not same:
            bad += 1
        print("%-14s %s  L5: %s" % (wid, "ok  " if same else "DIFF", fmt(got)))
        if not same:
            print("%-14s       L8: %s" % ("", fmt(want)))
    print("%d weapons, %d differ" % (len(files), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

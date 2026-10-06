#!/usr/bin/env python3
"""The Level Editor's self-test (pass 54). Standard library only:

    python tools/level_editor/selftest.py

1. The page's maths (tools/level_editor/model.js, run under node) against a Python copy of the game's own formulas
   (game/core/data/WaveTimeline.gd sample_points / curve_mult, WaveDirector._roster_weight, EnemyManager.spawn's health
   and damage): point sampling, the three curve formulas, the old weight -> weight_late slide against the presence
   keyframes the page converts it to (weights <-> weight_late), row ids, one creature's HP and ATK.
2. The server (tools/level_editor/server.py): a creature record's in-play icon, variance and knockback; Save keeping a
   float where the file had one when the rows come back reordered (matched by id); "Set as default look" on a temporary
   copy of a creature (only its `variant` line changes, the file's own line endings and final newline kept, an unpainted
   or unknown code refused). Nothing under game/ is written.

Without node the first part is skipped (said so) and the second still runs. Exit code 0 = every check passed.
"""
import json
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import server  # noqa: E402

FAILS = []
PASSES = [0]


def check(cond, what):
    if cond:
        PASSES[0] += 1
    else:
        FAILS.append(what)
        print("FAIL:", what)


# ---------------------------------------------------------------- the game's formulas, in Python


def sample_points(points, t):
    """WaveTimeline.sample_points."""
    prev_t, prev_v, seen = 0.0, 0.0, False
    for p in points:
        if not isinstance(p, list) or len(p) < 2:
            continue
        pt, pv = float(p[0]), float(p[1])
        if not seen:
            if t <= pt:
                return pv
            seen = True
        elif t <= pt:
            return prev_v + (pv - prev_v) * ((t - prev_t) / max(pt - prev_t, 0.001))
        prev_t, prev_v = pt, pv
    return prev_v


def curve_mult(c, t):
    """WaveTimeline.curve_mult."""
    if not isinstance(c, dict) or not c:
        return 1.0
    points = c.get("points", []) if isinstance(c.get("points", []), list) else []
    mode = str(c.get("mode", "points" if points else "formula"))
    if mode == "points":
        return sample_points(points, t) if points else 1.0
    if mode != "formula":
        return 1.0
    f = c.get("formula", {}) if isinstance(c.get("formula", {}), dict) else {}
    a, b, m = float(f.get("a", 0.0977)), float(f.get("b", 1.25)), t / 60.0
    kind = str(f.get("kind", "power"))
    if kind == "linear":
        return 1.0 + a * m
    if kind == "power":
        return max(1.0 + a * m, 0.0) ** b
    if kind == "exponential":
        return max(1.0 + a, 0.0) ** m
    return 1.0


def roster_weight(r, t, late_t):
    """WaveDirector._roster_weight."""
    ws = r.get("weights")
    if isinstance(ws, list) and ws:
        return max(sample_points(ws, t), 0.0)
    w = float(r.get("weight", 1.0))
    if "weight_late" not in r:
        return w
    start = float(r.get("t", 0.0))
    f = min(max((t - start) / max(late_t - start, 1.0), 0.0), 1.0)
    return w + (float(r.get("weight_late", w)) - w) * f


def stage_mult(tl, s, t):
    sm = tl.get("stage_mults", [])
    if not sm:
        return 1.0
    if s < len(sm):
        return float(sm[s])
    last = float(sm[-1])
    run_end = float(tl.get("stage_length", 300)) * int(tl.get("stages", 3))
    into = max(t - run_end, 0.0)
    wm = float(tl.get("endless_wave_mult", 1.0))
    if wm > 1.0:
        return last * wm ** math.floor(into / max(float(tl.get("endless_wave_seconds", 60)), 1.0))
    return last


def creature_at(tl, c, stats, t, level):
    """EnemyManager.spawn's health (regular / Elite archetype / boss) and the pass-54 damage (stage x level x
    creature_damage_mult x damage curve)."""
    st = stats or {}
    s = int(math.floor(t / float(tl.get("stage_length", 300))))
    sm = stage_mult(tl, s, t)
    lv_hp = 1 + float(tl.get("level_hp_per_level", 0)) * max(level - 1, 0)
    lv_dmg = 1 + float(tl.get("level_damage_per_level", 0)) * max(level - 1, 0)
    chm = float(tl.get("creature_hp_mult", 1.0))
    cdm = float(tl.get("creature_damage_mult", 1.0))
    hp_t = curve_mult(tl["hp_curve"], t) if tl.get("hp_curve") else (1 + float(tl.get("hp_growth", 0.08)) * t / 60) ** float(tl.get("hp_power", 1.2))
    dmg_t = curve_mult(tl["damage_curve"], t) if tl.get("damage_curve") else 1.0
    hp = float(st.get("hp", c["hp"])) * float(st.get("hp_mult", 1.0))
    dmg = float(st.get("damage", c["damage"])) * float(st.get("damage_mult", 1.0))
    if c.get("archetype") == "boss":
        per = float((st.get("boss") or {}).get("hp_mult_per_stage", (c.get("boss") or {}).get("hp_mult_per_stage", 1.6)))
        hp = hp * per ** s * max(sm, 1.0)
    elif c.get("archetype") == "elite":
        per = float((st.get("elite") or {}).get("hp_mult_per_stage", (c.get("elite") or {}).get("hp_mult_per_stage", 1.8)))
        hp = hp * per ** s * max(sm, 1.0) * chm
    else:
        hp = hp * sm * hp_t * lv_hp * chm
    return hp, dmg * sm * lv_dmg * cdm * dmg_t


# ---------------------------------------------------------------- model.js under node


NODE_RUNNER = r"""
const M = require(process.argv[2]);
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.sample = q.sample.map(([pts, t]) => M.samplePoints(pts, t));
  out.curve = q.curve.map(([c, t]) => M.curveMult(c, t));
  out.conv = q.conv.map(([tl]) => { const copy = JSON.parse(JSON.stringify(tl)); const n = M.normaliseRoster(copy); return { roster: copy.roster, n }; });
  out.weight = q.weight.map(([r, t, late]) => M.rowWeight(r, t, late));
  out.creature = q.creature.map(([tl, c, st, t, lv]) => { const r = M.creatureAt(tl, c, st, t, lv); return [r.hp, r.atk, r.arch]; });
  out.knock = q.knock.map(([c, st]) => M.knockbackOf(c, st));
  out.seed = q.seed.map(([tl, f]) => M.seedPoints(tl, f));
  process.stdout.write(JSON.stringify(out));
});
"""


def run_node(query):
    node = shutil.which("node")
    if not node:
        return None
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
        f.write(NODE_RUNNER)
        runner = f.name
    try:
        p = subprocess.run([node, runner, os.path.join(HERE, "model.js")], input=json.dumps(query), capture_output=True,
                           text=True, encoding="utf-8", timeout=60)
    finally:
        os.remove(runner)
    if p.returncode != 0:
        print(p.stderr)
        check(False, "model.js ran under node")
        return {}
    return json.loads(p.stdout)


def close(a, b, eps=1e-9):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


# the Red Canyon roster as it was before lane WD converted it (explore_x1 section 7), with the late time 860
OLD_RED_CANYON = [
    {"t": 0, "until": 86, "enemy": "red_goblin", "weight": 9, "weight_late": 3},
    {"t": 0, "until": 86, "enemy": "red_goblin_runt", "weight": 3, "weight_late": 1.2},
    {"t": 86, "until": 171, "enemy": "lesser_scorpion", "weight": 8, "weight_late": 5},
    {"t": 430, "enemy": "dust_mummy", "weight": 3.0, "weight_late": 5},
    {"t": 487, "enemy": "bull_beetle", "weight": 2.0, "weight_late": 3},
    {"t": 559, "enemy": "horned_toad", "weight": 2, "weight_late": 4},
    {"t": 860, "enemy": "dust_shaman", "weight": 1, "weight_late": 2},
    {"t": 430, "enemy": "blue_slime", "weight": 10, "channel": "hell"},
    {"t": 602, "enemy": "hammer_giant", "weight": 1.5, "channel": "hell"},
    {"t": 860, "enemy": "imp", "weight": 9, "channel": "hell"},
    {"t": 860, "enemy": "hellhound", "weight": 8, "channel": "hell"},
    {"t": 171, "until": 300, "enemy": "skeleton", "weight": 5.0},
    {"t": 171, "until": 300, "enemy": "skeleton_knight", "weight": 5.0},
    {"t": 171, "until": 250, "enemy": "spit_cactus", "weight": 1},
    {"t": 250, "until": 368, "enemy": "bull_beetle", "weight": 2},
    {"t": 300, "until": 430, "enemy": "red_goblin", "weight": 2},
    {"t": 300, "until": 430, "enemy": "red_goblin_runt", "weight": 2},
]


def model_checks():
    rnd = random.Random(54)
    q = {"sample": [], "curve": [], "conv": [], "weight": [], "creature": [], "knock": [], "seed": []}
    # 1. point sampling: random sorted lists, times before, between, on and after the points
    for _ in range(60):
        n = rnd.randint(1, 6)
        ts = sorted(rnd.sample(range(0, 1500, 7), n))
        pts = [[t, round(rnd.uniform(0, 12), 2)] for t in ts]
        for t in [-10, 0, ts[0], ts[-1], ts[-1] + 50] + [rnd.uniform(0, 1500) for _ in range(5)]:
            q["sample"].append([pts, t])
    q["sample"].append([[], 100])
    q["sample"].append([[[430, 3.0], [430, 5]], 430])
    q["sample"].append([[[430, 3.0], [430, 5]], 431])
    # 2. curves: every formula kind, default a / b, points mode, empty, an unknown mode
    curves = [
        {"mode": "formula", "formula": {"kind": "power", "a": 0.0977, "b": 1.25}, "points": [[0, 1.0], [430, 1.9414]]},
        {"mode": "formula", "formula": {"kind": "linear", "a": 0.05}},
        {"mode": "formula", "formula": {"kind": "exponential", "a": 0.04}},
        {"mode": "formula", "formula": {"kind": "linear", "a": 0.0}, "points": [[0, 1.0], [1290, 1.0]]},
        {"mode": "formula", "formula": {}},
        {"mode": "formula", "formula": {"kind": "bogus"}},
        {"mode": "points", "points": [[0, 1.0], [430, 2.0], [860, 2.5]], "formula": {"kind": "power"}},
        {"points": [[100, 1.5], [200, 3.0]]},
        {"formula": {"kind": "linear", "a": 0.1}},
        {"mode": "points", "points": []},
        {"mode": "wobble", "points": [[0, 2]]},
        {},
    ]
    for c in curves:
        for t in (0, 59, 300, 430, 645, 860, 1290, 1600):
            q["curve"].append([c, t])
    # 3. the old shape -> presence keyframes: Red Canyon before WD, a late time before a row's start, ids
    q["conv"].append([{"weight_late_t": 860, "roster": json.loads(json.dumps(OLD_RED_CANYON))}])
    q["conv"].append([{"weight_late_t": 300, "roster": [{"t": 400, "enemy": "imp", "weight": 4, "weight_late": 1},
                                                          {"id": "r2", "t": 0, "enemy": "imp", "weight": 2},
                                                          {"id": "r2", "t": 10, "enemy": "imp", "weights": [[10, 1], [20, 3]]}]}])
    # the latest old-shape backup the editor keeps, if any (a real file Garry saved)
    olds = []
    bdir = server.BACKUPS
    if os.path.isdir(bdir):
        for name in sorted(os.listdir(bdir), reverse=True):
            if name.startswith("red_canyon-") and name.endswith(".json"):
                try:
                    tl = server.load_json(os.path.join(bdir, name)).get("timeline_data", {})
                except (OSError, ValueError):
                    continue
                if any("weight" in r for r in tl.get("roster", [])):
                    olds.append((name, tl))
                    break
    for name, tl in olds:
        q["conv"].append([tl])
    # 4. one creature's numbers (regular, Elite archetype, boss) on a Red Canyon-like timeline
    tl = {"stage_length": 430, "stages": 3, "stage_mults": [1.0, 2.2, 3.34], "creature_hp_mult": 1.3, "creature_damage_mult": 1.25,
          "level_hp_per_level": 0.05, "level_damage_per_level": 0.03, "endless_wave_seconds": 86, "endless_wave_mult": 1.12,
          "hp_curve": {"mode": "formula", "formula": {"kind": "power", "a": 0.0977, "b": 1.25}},
          "damage_curve": {"mode": "points", "points": [[0, 1.0], [860, 1.5]]}}
    tl_legacy = {"stage_length": 430, "stages": 3, "stage_mults": [1.0, 2.2, 3.34], "creature_hp_mult": 1.3, "hp_growth": 0.0977, "hp_power": 1.25}
    walker = {"id": "skeleton", "kind": "enemy", "archetype": "walker", "hp": 10, "damage": 3}
    elite = {"id": "dune_scorpion", "kind": "enemy", "archetype": "elite", "hp": 260, "damage": 10, "elite": {"hp_mult_per_stage": 1.8}}
    boss = {"id": "gila_grande", "kind": "boss", "archetype": "boss", "hp": 2400, "damage": 20, "boss": {"hp_mult_per_stage": 1.6}}
    cases = [(tl, walker, {}, 240, 1), (tl, walker, {"hp": 20, "damage_mult": 2}, 240, 10), (tl, walker, {}, 1400, 5),
             (tl, elite, {}, 645, 1), (tl, elite, {"elite": {"hp_mult_per_stage": 2.0}}, 1000, 7), (tl, boss, {}, 860, 1),
             (tl_legacy, walker, {}, 600, 1), (tl_legacy, boss, {"hp_mult": 0.5}, 1290, 3)]
    for c in cases:
        q["creature"].append(list(c))
    q["knock"] = [[{"damage": 4}, {}], [{"damage": 4, "knockback": 5.5}, {}], [{"damage": 100}, {}], [{"damage": 0.5}, {}],
                  [{"damage": 4}, {"knockback": 6, "knockback_mult": 0.5}], [{"damage": 4}, {"damage": 16}]]
    q["seed"] = [[{"stage_length": 430, "stages": 3}, {"kind": "power", "a": 0.0977, "b": 1.25}]]

    res = run_node(q)
    if res is None:
        print("node not found: the model.js checks are skipped (install Node.js to run them)")
        return
    if not res:
        return
    for (pts, t), got in zip(q["sample"], res["sample"]):
        check(close(got, sample_points(pts, t)), "sample_points %s at %s: js %s" % (pts, t, got))
    for (c, t), got in zip(q["curve"], res["curve"]):
        check(close(got, curve_mult(c, t)), "curve_mult %s at %s: js %s py %s" % (c, t, got, curve_mult(c, t)))
    # conversion: the converted rows weigh what the old rows weighed at every second (but the first second after a row
    # that starts at or after weight_late_t, where the old slide ramped over one second and the keyframes do too)
    for (src,), got in zip(q["conv"], res["conv"]):
        late = float(src.get("weight_late_t", 600))
        rows_old, rows_new = src["roster"], got["roster"]
        check(len(rows_old) == len(rows_new), "conversion keeps every row")
        ids = [r.get("id") for r in rows_new]
        check(all(isinstance(i, str) and i for i in ids) and len(set(ids)) == len(ids), "every row has a unique id: %s" % ids)
        for o, n in zip(rows_old, rows_new):
            check("weight" not in n and "weight_late" not in n and isinstance(n.get("weights"), list), "row %s in the new shape" % n.get("id"))
            if "weights" in o and o["weights"]:
                check(n["weights"] == o["weights"], "a row with keyframes keeps them")
                continue
            for t in range(0, 1800, 5):
                check(close(roster_weight(n, t, late), roster_weight(o, t, late), 1e-9), "row %s %s weighs the same at %s: %s vs %s" % (
                    n.get("id"), o.get("enemy"), t, roster_weight(n, t, late), roster_weight(o, t, late)))
    # the page's converter agrees with lane WD's conversion of Red Canyon (informational when Garry has edited the rows)
    cur = server.load_json(server.map_path("red_canyon")).get("timeline_data", {}).get("roster", [])
    mine = res["conv"][0]["roster"]
    same_rows = len(cur) == len(mine) and all(c.get("enemy") == m.get("enemy") and c.get("t") == m.get("t") for c, m in zip(cur, mine))
    if same_rows and all("weights" in c for c in cur):
        for c, m in zip(cur, mine):
            check([[float(a), float(b)] for a, b in c["weights"]] == [[float(a), float(b)] for a, b in m["weights"]] and c.get("id") == m.get("id"),
                  "row %s: the page converts as WD did (%s vs %s)" % (c.get("id"), m["weights"], c["weights"]))
    else:
        print("note: Red Canyon's roster no longer matches the pre-pass-54 rows; the WD agreement check is skipped")
    for (tlc, c, st, t, lv), got in zip(q["creature"], res["creature"]):
        hp, atk = creature_at(tlc, c, st, t, lv)
        check(close(got[0], hp) and close(got[1], atk), "%s at %s level %s with %s: js HP %s ATK %s, py HP %s ATK %s" % (c["id"], t, lv, st, got[0], got[1], hp, atk))
    expect_kb = [3.4, 5.5, 7.0, 2.5, 3.0, 6.8]
    for (c, st), got, want in zip(q["knock"], res["knock"], expect_kb):
        check(close(got["value"], want, 1e-6), "knockback of %s with %s: %s, want %s" % (c, st, got, want))
    seeded = res["seed"][0]
    check([p[0] for p in seeded] == [0, 430, 860, 1290], "seed points at the stage marks: %s" % seeded)
    check(all(close(p[1], round(curve_mult({"mode": "formula", "formula": {"kind": "power", "a": 0.0977, "b": 1.25}}, p[0]), 4), 1e-12) for p in seeded),
          "seed points on the formula, 4 decimals: %s" % seeded)


# ---------------------------------------------------------------- the server


def server_checks():
    recs = {c["id"]: c for c in server.list_creatures()}
    sk = recs.get("skeleton")
    check(sk is not None, "the palette lists the skeleton")
    if sk:
        check(sk["icon_play"] == "/icon/enemy/skeleton/%s" % sk["play"], "the skeleton's in-play icon is its variant's: %s" % sk["icon_play"])
        check(isinstance(sk["variance"], dict) and "tints" in sk["variance"], "the record carries the variance block")
        check(sk["knockback"] is None or isinstance(sk["knockback"], (int, float)), "knockback is a number or null")
        check(any(v.get("ready") for v in sk["variants"]), "the skeleton's variants say which are painted")
    check(not any(cid.startswith("training_dummy") for cid in recs), "no training dummy in the palette")
    # a base strip without its own entry is a look of its own
    for c in recs.values():
        if c["variant_base"]:
            check(any(v["code"] == c["variant_base"] for v in c["variants"]), "%s lists its base strip %s" % (c["id"], c["variant_base"]))

    # Save: rows reordered come back matched by id, so a float stays a float
    old = {"timeline_data": {"roster": [{"id": "r1", "t": 0, "weights": [[0, 3.0], [860, 5.0]]}, {"id": "r2", "t": 10, "weights": [[10, 2.0]]}]}}
    new = {"timeline_data": {"roster": [{"id": "r2", "t": 10, "weights": [[10, 2]]}, {"id": "r1", "t": 0, "weights": [[0, 3], [860, 5]]}]}}
    merged = server.restore_numbers(old, new)
    text = json.dumps(merged)
    check('"weights": [[10, 2.0]]' in text and '[[0, 3.0], [860, 5.0]]' in text, "restore_numbers matches reordered rows by id: %s" % text)

    # "Set as default look" on a temporary copy (no Godot: the import is reported as not run)
    tmp = tempfile.mkdtemp(prefix="le_selftest_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        folder = os.path.join(server.CONTENT, "enemies", "testbeast")
        os.makedirs(folder)
        for f in ("a.png", "b.png"):
            open(os.path.join(folder, f), "wb").close()
        d = {"id": "testbeast", "name": "Test Beast", "hp": 10.0, "damage": 3, "variant_base": "TB-0", "variant": "TB-A",
             "variants": {"TB-0": {"note": "base"}, "TB-A": {"sprite": "a.png"}, "TB-B": {"sprite": "b.png"}, "TB-C": {"sprite": "missing.png"}}}
        path = os.path.join(folder, "testbeast.json")
        for crlf, final_nl in ((False, False), (True, True)):
            text = json.dumps(d, indent=2, ensure_ascii=False)
            if final_nl:
                text += "\n"
            if crlf:
                text = text.replace("\n", "\r\n")
            with open(path, "wb") as f:
                f.write(text.encode("utf-8"))
            res = server.write_variant("testbeast", "TB-B")
            check(res.get("ok") and not res.get("import_ok"), "write_variant writes and reports the import it could not run: %s" % res)
            after = open(path, "rb").read().decode("utf-8")
            before_lines, after_lines = text.splitlines(True), after.splitlines(True)
            changed = [(a, b) for a, b in zip(before_lines, after_lines) if a != b]
            check(len(before_lines) == len(after_lines) and len(changed) == 1 and '"TB-B"' in changed[0][1],
                  "only the variant line changes (crlf %s, final newline %s): %s" % (crlf, final_nl, changed))
            check(("\r\n" in after) == crlf and after.endswith("\n") == final_nl, "line endings and final newline kept (crlf %s)" % crlf)
            check(json.loads(after)["hp"] == 10.0 and '"hp": 10.0' in after, "numbers kept as they were")
            check(server.write_variant("testbeast", "TB-0").get("ok"), "the base strip's code can be set")
        check(not server.write_variant("testbeast", "TB-C").get("ok"), "a variant without its strip on disk is refused")
        check(not server.write_variant("testbeast", "TB-Z").get("ok"), "an unknown code is refused")
        check(not server.write_variant("testbeast", "../x").get("ok"), "a bad code is refused")
        check(not server.write_variant("nobody", "TB-A").get("ok"), "an unknown creature is refused")
        # a creature without `variant` gets it just before `variants`
        d2 = {k: v for k, v in d.items() if k != "variant"}
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(d2, indent=2))
        server.write_variant("testbeast", "TB-A")
        keys = list(json.loads(open(path, encoding="utf-8").read()).keys())
        check(keys.index("variant") == keys.index("variants") - 1, "variant added just before variants: %s" % keys)
        check(len([f for f in os.listdir(server.BACKUPS) if f.startswith("testbeast-")]) >= 3, "every write left a backup")
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    model_checks()
    server_checks()
    print("%d checks passed, %d failed" % (PASSES[0], len(FAILS)))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())

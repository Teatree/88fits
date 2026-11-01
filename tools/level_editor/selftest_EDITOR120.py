"""Pass 120, lane EDITOR: a roster row's card (SPD beside HP and ATK, the schedule's pacing and pattern), a row set to
Special with an Elite modifier (both) or for a creature with no variance block (the map's Coloured specials), and the
Spawned so far estimate split into what rows always bring and what comes by chance.

Garry (2026-11-01): "upon highlight we surface the HP and ATK stats at the top, but I think we should also surface SPD
(Speed) at the same level of visual priority. Also, let's surface the Schedule `Pacing` (with the seconds next to it)
and the `Pattern` of spawning (with the Pack param next to it as well)"; "I wanted to make the 4th Spider Row a
guaranteed specials with a Split modifier, but I can't tell if I made it so they are guaranteed to spawn as specials";
"`Spawned so far` is an estimate yes, but let's make it so it estimates the number of Elitted Regular enemies with the
accounting for our guaranteed Elitted Regular enemies".

Groups: model.js speedOf (the row's speed in m/s, speed_mult, the stage, move_pace with its 0.05 floor,
creature_speed_mult, a size range never changing it) against the game's sources (EnemyDef's override tables,
WaveTimeline.speed_mult, EnemyManager.spawn, Run.move_pace); rowSchedule's words; forcedSpecial (the creature's own, the
map's, the game's; the colour's fallback = EnemyDef.SPECIAL_TINT); the estimate's new tallies (colForced, modRow, both)
on fixtures, its colour waits, an elite row's elites filed under the row, the JS and Python twins agreeing; fields.js
(the Coloured specials card's Colour, the rows' help); app.js without the old warning; timeline.js's card and readout;
the real map read, never pinned (Garry's numbers are his).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import copy
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const dir = path.dirname(process.argv[2]);
const M = require(process.argv[2]);
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.speed = q.speed.map(([tl, c, st, t]) => M.speedOf(tl, c, st, t));
  out.sched = q.sched.map(([r, c, si]) => M.rowSchedule(r, c, si));
  out.forced = q.forced.map(([c, st, d]) => M.forcedSpecial(c, st, d));
  out.colour = M.SPECIAL_COLOUR;
  out.est = q.est.map(([tl, cr, o]) => { const e = M.spawnEstimate(tl, cr, o); return { points: e.points, ids: e.ids, marks: e.marks, fights: e.fights, colourAt: e.colourAt, colourWaits: e.colourWaits }; });
  // the real map, read (never pinned): every row's speed and schedule, and the stitched estimate's colour waits
  const m = q.map;
  if (m) {
    const byId = {};
    for (const c of m.cr) byId[c.id] = c;
    const tl = m.tl;
    out.mapRows = (tl.roster || []).map((r) => {
      const id = Array.isArray(r.enemy) ? r.enemy[0] : r.enemy;
      const c = byId[id] || null;
      return { id: r.id, enemy: id, known: !!c, spd: c ? M.speedOf(tl, c, r.stats, Number(r.t) || 0).spd : null, sched: M.rowSchedule(r, c, tl.spawn_interval == null ? 0.5 : tl.spawn_interval), elite: M.rowElite(r), until: r.until };
    });
    const e = M.stagesEstimate(tl, m.cr, { turnover: 0.06 });
    out.mapWaits = e.colourWaits;
    out.mapStages = e.colourAts || [];
    let bad = 0;
    for (const p of e.points) if (p.reg - p.col - p.mod + p.both < -1e-6 || p.colForced > p.col + 1e-6 || p.modRow > p.mod + 1e-6 || p.both > Math.min(p.col, p.mod) + 1e-6) bad++;
    out.mapBadPoints = bad;
    out.mapPoints = e.points.length;
  }
  out.scalar = FIELDS.SCALARS.filter((d) => d.key === 'special_defaults.tint').map((d) => [d.key, d.group, d.type, d.def, d.help || '']);
  out.help = {};
  for (const d of FIELDS.roster) if (d.key === 'elite' || d.key === 'special') out.help[d.key] = d.help;
  out.swarmHelp = (FIELDS.event.find((d) => d.key === 'special') || {}).help || '';
  out.api = ['speedOf', 'forcedSpecial', 'rowSchedule'].filter((k) => typeof M[k] !== 'function');
  process.stdout.write(JSON.stringify(out));
});
"""


def _main_module():
    mod = sys.modules.get("__main__")
    if mod is not None and hasattr(mod, "spawn_estimate") and hasattr(mod, "estimate_diff"):
        return mod
    import selftest
    return selftest


def _close(a, b, eps=1e-9):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


def _read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# ---------------------------------------------------------------- fixtures

def _cr_a():
    return {"id": "a", "name": "A", "kind": "enemy", "archetype": "walker", "hp": 10, "damage": 2, "speed": 3, "cap_share": 1,
            "pack_size": 3, "max_alive": 0, "variance": {"speed": 0.08, "special_chance": 0.5, "special": {"tint": "#123456"}}}


def _cr_nv():
    return {"id": "nv", "name": "NV", "kind": "enemy", "archetype": "walker", "hp": 20, "damage": 3, "speed": 2, "cap_share": 1,
            "pack_size": 3, "max_alive": 0}


def _tl(roster, cak=0, extra=None):
    tl = {"stage_length": 100, "stages": 1, "cap_curve": [[0, 30]], "cap_max": 100, "hard_cap": 300, "burst_min": 10,
          "burst_max": 10, "spawn_interval": 0.5, "colour_after_kills": cak, "roster": roster, "events": []}
    if extra:
        tl.update(extra)
    return tl


PLAIN = {"id": "r1", "t": 0, "enemy": "a", "weights": [[0, 1]]}
BOTH = {"id": "r2", "t": 20, "until": 30, "enemy": "nv", "weights": [[20, 1]], "pace": "once", "count": 3, "pattern": "scatter",
        "special": True, "elite": "splitter", "respect_cap": False}


def checks(check, run_node, server):
    cr = [_cr_a(), _cr_nv()]
    opts = {"turnover": 0.05, "end": 60}
    # pass 120 follow-up (the lead, WaveDirector.colour_open_for): a Special row never waits for colour, its modifier
    # too; an elite row without Special waits as before
    elite_only = {"id": "r6", "t": 20, "until": 30, "enemy": "nv", "weights": [[20, 1]], "pace": "once", "count": 3, "pattern": "scatter", "elite": "shielded", "respect_cap": False}
    late = dict(elite_only, until=55)
    named = {"id": "r3", "t": 10, "until": 40, "enemy": "nv", "weights": [[10, 1]], "pace": "once", "count": 3, "pattern": "pack", "elite": "shielded", "respect_cap": False}
    draw = {"id": "r4", "t": 5, "enemy": "roster", "weights": [[5, 1]], "pace": "waves", "every": 10, "count": 1, "elite": "random", "respect_cap": False}
    spec = {"id": "r5", "t": 15, "until": 20, "enemy": "nv", "weights": [[15, 1]], "pace": "once", "count": 4, "pattern": "scatter", "special": True, "respect_cap": False}
    nopat = {"id": "r7", "t": 20, "until": 30, "enemy": "nv", "weights": [[20, 1]], "pace": "once", "count": 2, "special": True, "elite": "splitter"}
    cont = {"id": "r8", "t": 10, "until": 40, "enemy": "nv", "weights": [[10, 1]], "special": True, "elite": "splitter", "pack": 1}
    est_q = [
        [_tl([PLAIN, BOTH]), cr, opts],                          # 0: Special + an Elite modifier, colour at once: 3 both
        [_tl([PLAIN, BOTH, elite_only], cak=100000), cr, opts],  # 1: colour never comes: the Special row comes, the elite row waits
        [_tl([PLAIN, late], cak=40), cr, opts],                  # 2: colour comes late inside an elite row's window: it comes then
        [_tl([PLAIN, named, draw]), cr, opts],                   # 3: a named elite row and the roster draw
        [_tl([PLAIN, spec]), cr, opts],                          # 4: a Special row of a creature with no variance block
        [_tl([PLAIN, nopat], cak=100000), cr, opts],             # 5: a pattern-less Special elite row (the coloured-elite arrivals) before colour
        [_tl([PLAIN, cont], cak=100000), cr, opts],              # 6: a continuous Special elite row before colour
    ]
    sp_tl = {"stage_list": [{"id": "s1", "length": 100}, {"id": "s2", "length": 100}], "speed_per_stage": 0.1, "move_pace": 0.9, "creature_speed_mult": 0.9}
    a = _cr_a()
    speed_q = [
        [sp_tl, a, {}, 50], [sp_tl, a, {"speed": 2.1}, 150], [sp_tl, a, {"speed_mult": 0.5}, 50], [sp_tl, a, {"speed": 2, "speed_mult": 1.5}, 50],
        [sp_tl, a, {"speed": [1, 2]}, 50], [{"move_pace": 0}, a, {}, 0], [{}, a, {"size": [2, 3]}, 0], [{}, a, {"variance": {"speed": 0.2}}, 0],
    ]
    sched_q = [
        [{"t": 0}, a, 0.7], [{"t": 0, "interval": 3}, a, 0.7],
        [{"t": 480, "pace": "waves", "every": 5, "count": 15, "pattern": "scatter", "pack": 15}, a, 0.7],
        [{"t": 0, "pace": "waves", "every": [12, 8], "count": 15}, a, 0.7],
        [{"t": 469, "pace": "once", "count": 3, "pattern": "scatter", "pack": 15, "special": True, "elite": "splitter"}, a, 0.7],
        [{"t": 469, "pace": "once", "offset": 3, "count": 3}, a, 0.7],
        [{"t": 0, "pattern": "ring", "ring_radius": 16}, a, 0.7], [{"t": 0, "pattern": "ring"}, a, 0.7], [{"t": 0, "pattern": "single"}, a, 0.7],
        [{"t": 301, "enemy": "roster", "pace": "waves", "every": 129, "count": 1, "elite": "random"}, None, 0.7],
        [{"t": 0, "stats": {"pack": 6}}, a, 0.7], [{"t": 0, "pace": "waves", "every": 0, "count": 4}, a, 0.7],
        [{"t": 60, "pace": "once", "chance": 0.6, "t_jitter": 5, "count": 2}, a, 0.7], [{"t": 0, "pace": "waves", "every": 5, "pack": 15}, a, 0.7],
        [{"t": 469, "pace": "once", "count": 3, "pattern": "scatter", "pack": 15, "elite": "splitter"}, a, 0.7],
    ]
    forced_q = [
        [_cr_nv(), {}, {"damage": 3.5}], [_cr_nv(), {}, {"tint": "#112233"}], [a, {}, {}], [a, {"variance": {"special": {"hp": 4}}}, {"hp": 6}],
        [a, {}, {"tint": "  "}], [_cr_nv(), {"variance": {"special": {"tint": "#445566"}}}, {}],
    ]
    # the real map, read
    mq = None
    try:
        with open(os.path.join(CONTENT, "maps", "red_canyon", "red_canyon.json"), encoding="utf-8") as f:
            mtl = json.load(f)["timeline_data"]
        mcr = []
        for kind in ("enemies", "bosses"):
            d = os.path.join(CONTENT, kind)
            if not os.path.isdir(d):
                continue
            for cid in sorted(os.listdir(d)):
                p = os.path.join(d, cid, cid + ".json")
                if os.path.isfile(p):
                    with open(p, encoding="utf-8") as f:
                        mcr.append(json.load(f))
        mq = {"tl": mtl, "cr": mcr}
    except (OSError, ValueError, KeyError) as e:
        check(False, "EDITOR120: Red Canyon readable: %s" % e)
    res = run_node({"speed": speed_q, "sched": sched_q, "forced": forced_q, "est": est_q, "map": mq}, RUNNER)
    if res is None:
        check(True, "EDITOR120: node not found, the page checks skipped")
        return
    if not res:
        return
    check(res["api"] == [], "EDITOR120: model.js exports speedOf, forcedSpecial and rowSchedule: missing %s" % res["api"])

    # ---- speedOf
    sp = res["speed"]
    want = [3 * 0.81, 2.1 * 1.1 * 0.81, 3 * 0.5 * 0.81, 2 * 1.5 * 0.81, 3 * 0.81, 3 * 0.05, 3, 3]
    for k, (got, w) in enumerate(zip(sp, want)):
        check(_close(got["spd"], w, 1e-9), "EDITOR120: speedOf case %d: %.4f m/s, want %.4f (%s)" % (k, got["spd"], w, json.dumps(speed_q[k][2])))
    check(sp[0]["over"] is False and sp[0]["set"] == "creature" and sp[0]["stage"] == 0 and _close(sp[0]["jitter"], 0.08),
          "EDITOR120: speedOf: the creature's own speed, no override, stage 1, the variance's ±8%%: %s" % sp[0])
    check(sp[1]["over"] is True and sp[1]["set"] == "row" and sp[1]["stage"] == 1 and _close(sp[1]["stageMult"], 1.1),
          "EDITOR120: speedOf: a row's speed is m/s in place of the creature's (Garry's r68: 2.1), stage 2 x1.1: %s" % sp[1])
    check(sp[2]["over"] is True and sp[2]["set"] == "creature" and _close(sp[2]["mult"], 0.5), "EDITOR120: speedOf: speed_mult multiplies the creature's own: %s" % sp[2])
    check(sp[4]["over"] is False, "EDITOR120: speedOf: a list where a number belongs is skipped, as EnemyDef.with_overrides skips it")
    check(_close(sp[5]["movePace"], 0.05), "EDITOR120: speedOf: move_pace never under 0.05 (Run.move_pace)")
    check(_close(sp[7]["jitter"], 0.2), "EDITOR120: speedOf: the row's variance speed spread wins: %s" % sp[7]["jitter"])
    # the game's sources the formula copies
    ed = _read("game/core/data/EnemyDef.gd")
    wt = _read("game/core/data/WaveTimeline.gd")
    em = _read("game/core/systems/EnemyManager.gd")
    rn = _read("game/core/autoload/Run.gd")
    check('"speed": "speed"' in ed and '"speed_mult": "speed"' in ed, "EDITOR120: EnemyDef's overrides: `speed` sets the field, `speed_mult` multiplies it")
    check("return 1.0 + speed_per_stage * float(stage_index)" in wt, "EDITOR120: WaveTimeline.speed_mult is 1 + speed_per_stage x the stage")
    check("var esp := def.speed * stage_speed_mult" in em and "speed[i] = esp * pace" in em and "pace = Run.move_pace() * creature_speed_mult" in em,
          "EDITOR120: EnemyManager.spawn: walk = speed x stage_speed_mult x pace (move_pace x creature_speed_mult)")
    check("maxf(map.timeline.move_pace, 0.05)" in rn, "EDITOR120: Run.move_pace never under 0.05")

    # ---- rowSchedule
    s = res["sched"]
    check(s[0]["pacing"] == "Continuous · drawn every 0.7 s" and s[0]["pattern"] == "Pack" and s[0]["patternDefault"] and s[0]["packText"] == "packs of 3" and s[0]["packFrom"] == "creature",
          "EDITOR120: a plain row: continuous at the spawn check, Pack (default), the creature's pack: %s" % s[0])
    check(s[1]["pacing"] == "Continuous · its own draw every 3 s", "EDITOR120: a row with its own Draw every: %s" % s[1]["pacing"])
    check(s[2]["pacing"] == "Waves every 5 s · 15 a wave" and s[2]["pattern"] == "Scatter" and s[2]["packText"] == "pack 15" and s[2]["packFrom"] == "row" and not s[2]["patternDefault"],
          "EDITOR120: a waves row: its seconds and count, Scatter with its pack: %s" % s[2])
    check(s[3]["pacing"] == "Waves every 8–12 s · 15 a wave" and "a fresh gap each wave" in s[3]["pacingNote"], "EDITOR120: every [min, max] (reversed read in order): %s" % s[3])
    check(s[4]["pacing"] == "Once at 7:49 · 3 in it" and "never waits for colour" in s[4]["pacingNote"] and s[4]["packText"] == "pack 15",
          "EDITOR120: Garry's r68 shape: once at 7:49, 3, scatter pack 15, a Special elite row that never waits for colour: %s" % s[4])
    check("it waits for colour" in s[14]["pacingNote"] and "never waits" not in s[14]["pacingNote"],
          "EDITOR120: the same row without Special waits for colour: %s" % s[14]["pacingNote"])
    check(s[5]["pacing"] == "Once at 7:52 (7:49 + 3 s) · 3 in it", "EDITOR120: a once row's offset: %s" % s[5]["pacing"])
    check(s[6]["pattern"] == "Ring 16 m" and s[7]["pattern"] == "Ring 11.7 m" and "no Ring radius" in s[7]["patternNote"], "EDITOR120: the ring's radius, its own or the rows' 11.7 m: %s / %s" % (s[6]["pattern"], s[7]["pattern"]))
    check(s[8]["pattern"] == "Single" and s[8]["packText"] == "one at a time", "EDITOR120: Single reads no pack: %s" % s[8])
    check(s[9]["pattern"] == "As Elites" and s[9]["packFrom"] == "draw" and s[9]["pacing"] == "Waves every 129 s · 1 a wave",
          "EDITOR120: Elites every (the roster draw, no pattern): the coloured-elite arrivals: %s" % s[9])
    check(s[10]["packFrom"] == "override" and s[10]["packText"] == "packs of 6", "EDITOR120: Overrides -> Pack: %s" % s[10])
    check(s[11]["pacing"] == "Once at 0:00 · 4 in it", "EDITOR120: waves every 0 = one wave: %s" % s[11]["pacing"])
    check("60% of runs" in s[12]["pacingNote"] and "± 5 s" in s[12]["pacingNote"], "EDITOR120: chance and jitter in the note: %s" % s[12]["pacingNote"])
    check(s[13]["pacing"] == "Waves every 5 s · 15 a wave", "EDITOR120: Per wave empty = the row's Pack (WaveTimeline.row_wave_count): %s" % s[13]["pacing"])

    # ---- forcedSpecial
    fs = res["forced"]
    check(res["colour"] == "#8A1428", "EDITOR120: model.js SPECIAL_COLOUR is crimson #8A1428: %s" % res["colour"])
    check(re.search(r'const SPECIAL_TINT := "#8A1428"', ed) is not None, "EDITOR120: the game's EnemyDef.SPECIAL_TINT is the page's #8A1428")
    check(fs[0]["hasVar"] is False and _close(fs[0]["hp"], 15) and fs[0]["from"]["hp"] == "game" and _close(fs[0]["damage"], 3.5) and fs[0]["from"]["damage"] == "map"
          and fs[0]["tint"] == "#8A1428" and fs[0]["tintFrom"] == "game",
          "EDITOR120: no variance block: the map's numbers where set, else the game's, the crimson: %s" % fs[0])
    check(fs[1]["tint"] == "#112233" and fs[1]["tintFrom"] == "map", "EDITOR120: the map's Coloured specials Colour: %s" % fs[1]["tint"])
    check(fs[2]["hasVar"] is True and fs[2]["tint"] == "#123456" and fs[2]["tintFrom"] == "own", "EDITOR120: the creature's own colour wins: %s" % fs[2]["tint"])
    check(_close(fs[3]["hp"], 4) and fs[3]["from"]["hp"] == "own", "EDITOR120: a row's variance override wins over the map's: %s" % fs[3]["hp"])
    check(fs[4]["tint"] == "#123456", "EDITOR120: an empty map colour is no colour: %s" % fs[4]["tint"])
    check(fs[5]["hasVar"] is True and fs[5]["tint"] == "#445566", "EDITOR120: a row's own variance gives a bare creature its special colour: %s" % fs[5])

    # ---- the estimate: the new tallies, the colour waits, the twins
    st = _main_module()
    labels = ["both", "colour never", "colour late", "named + draw", "special no variance", "pattern-less special elite", "continuous special elite"]
    for k, ((tl, crs, o), js) in enumerate(zip(est_q, res["est"])):
        py = st.spawn_estimate(tl, crs, o)
        bad = st.estimate_diff(js, py)
        check(not bad, "EDITOR120: the estimate twins agree (%s): %s" % (labels[k], bad[:4]))
        lay = [p["t"] for p in js["points"] if p["reg"] - p["col"] - p["mod"] + p["both"] < -1e-6 or p["colForced"] > p["col"] + 1e-6 or p["modRow"] > p["mod"] + 1e-6]
        check(not lay, "EDITOR120: the layers stay sane (%s): plain >= 0, forced <= coloured, named <= modified: %s" % (labels[k], lay[:5]))
    end = [e["points"][-1] for e in res["est"]]
    p0 = end[0]
    check(_close(p0["both"], 3) and _close(p0["modRow"], 3) and _close(p0["mod"], 3) and _close(p0["colForced"], 3) and p0["col"] >= 3 - 1e-9,
          "EDITOR120: Special + Splitter, colour open: 3 both, 3 forced coloured, 3 elite-modified from a row: both %.2f colForced %.2f modRow %.2f mod %.2f col %.2f"
          % (p0["both"], p0["colForced"], p0["modRow"], p0["mod"], p0["col"]))
    check("roster:1" in p0["src"] and _close(p0["src"]["roster:1"], 3), "EDITOR120: the both row filed under its key: %s" % p0["src"].get("roster:1"))
    # (pass 120 follow-up, the lead's WaveDirector.colour_open_for: a Special row never waits for colour, its modifier too)
    p1 = end[1]
    w1 = res["est"][1]["colourWaits"]
    t20 = [p for p in res["est"][1]["points"] if p["t"] == 21]
    check(_close(p1["both"], 3) and _close(p1["modRow"], 3) and _close(p1["src"].get("roster:1", 0), 3) and t20 and _close(t20[0]["both"], 3),
          "EDITOR120: colour never comes: the Special elite row still brings its 3, both, at its second (0:20): %s" % {k: p1[k] for k in ("mod", "both", "col")})
    check(p1["src"].get("roster:2", 0) < 1e-9, "EDITOR120: ... the elite row without Special brings nothing: %s" % p1["src"].get("roster:2"))
    check(len(w1) == 1 and w1[0]["key"] == "roster:2" and w1[0]["at"] is None and _close(w1[0]["from"], 20) and _close(w1[0]["until"], 30),
          "EDITOR120: only the elite row without Special waits, due at 0:20, never came, the window closing at 0:30: %s" % w1)
    p2 = end[2]
    w2 = res["est"][2]["colourWaits"]
    ca2 = res["est"][2]["colourAt"]
    check(len(w2) == 1 and w2[0]["at"] is not None and 20 < w2[0]["at"] < 55 and ca2 is not None and abs(w2[0]["at"] - ca2) <= 1.0 + 1e-9,
          "EDITOR120: colour late inside an elite row's window: it comes within a second of colour (%s): %s" % (ca2, w2))
    check(_close(p2["modRow"], 3) and _close(p2["both"], 0), "EDITOR120: ... and brings its 3 elite-modified: %s" % p2["modRow"])
    p3 = end[3]
    check(_close(p3["modRow"], 3) and p3["mod"] - p3["modRow"] > 0.5 and _close(p3["both"], 0),
          "EDITOR120: a named elite row counts as always (3), the roster draw by chance: modRow %.2f, drawn %.2f" % (p3["modRow"], p3["mod"] - p3["modRow"]))
    check(p3["src"].get("roster:2", 0) > 0.5, "EDITOR120: the roster draw's elites are filed under its row (pass 120): %s" % p3["src"].get("roster:2"))
    p4 = end[4]
    check(_close(p4["colForced"], 4) and _close(p4["mod"], 0) and p4["col"] >= 4 - 1e-9 and p4["col"] - p4["colForced"] > 0.1,
          "EDITOR120: a Special row of a bare creature: 4 forced coloured, the plain row's by chance on top: forced %.2f chance %.2f" % (p4["colForced"], p4["col"] - p4["colForced"]))
    p5 = end[5]
    check(_close(p5["both"], 2) and not res["est"][5]["colourWaits"] and _close(p5["src"].get("roster:1", 0), 2),
          "EDITOR120: a pattern-less Special elite row before colour: its 2 arrivals come at once, both, never held: both %.2f" % p5["both"])
    p6 = end[6]
    check(p6["both"] > 1 and _close(p6["both"], p6["mod"]) and p6["src"].get("roster:1", 0) > 1,
          "EDITOR120: a continuous Special elite row is drawn before colour, every one both: both %.2f mod %.2f" % (p6["both"], p6["mod"]))

    # ---- fields.js, app.js, timeline.js
    sc = res["scalar"]
    check(len(sc) == 1 and sc[0][1] == "Coloured specials" and sc[0][2] == "swatch" and sc[0][3] == "#8A1428" and "forced special" in sc[0][4],
          "EDITOR120: Settings -> Coloured specials -> Colour (a swatch, the game's crimson, its help): %s" % sc)
    h = res["help"]
    check("AND wears the modifier" in h.get("elite", "") and "never roll the coloured special by chance" in h.get("elite", "").replace("They never roll", "never roll"),
          "EDITOR120: the row's Elite modifier help: both with Special, never by chance: %s" % h.get("elite", "")[:120])
    check("no variance block comes as its special too" in h.get("special", "") and "each is both" in h.get("special", ""),
          "EDITOR120: the row's Special help: a bare creature comes as its special too; with a modifier both")
    check("comes plain" not in res["swarmHelp"] and "no variance block comes as its special too" in res["swarmHelp"], "EDITOR120: the swarm's Special help follows the new rule")
    app = _read("tools/level_editor/app.js")
    check("an elite-modified creature never comes as its special" not in app, "EDITOR120: app.js no longer warns on Special with an Elite modifier")
    tjs = _read("tools/level_editor/timeline.js")
    for frag in ["`SPD ${fmtN(spd.spd, 2)}`", "scheduleLines(o.schedule, c)", "forcedLines(c, st, at, o)", "colourWaitLines(i, r)", "from rows that always bring one",
                 "from Special rows", "p.reg - p.col - p.mod + (p.both || 0)", "has no variance block, so its special takes the map's Coloured specials",
                 "const [span0, span1] = estSpan(est);", "neverReason(i, r)", "is held by ${others"]:
        check(frag in tjs, "EDITOR120: timeline.js has %s" % frag)
    check("Make a row of guaranteed specials, with an Elite modifier too" in _read("tools/level_editor/instructions.js"), "EDITOR120: the Instructions tab says how to make a row of guaranteed specials")
    check("forcedSpecial(" in _read("tools/level_editor/inspector.js") and "forcedSpecial(" in _read("tools/level_editor/enemies.js"),
          "EDITOR120: the inspector's Special note and the Enemies tab's Special block follow the new rule")
    check("it comes plain" not in tjs, "EDITOR120: timeline.js no longer says a bare creature comes plain")
    css = _read("tools/level_editor/style.css")
    check(".hc-stats.hc-sched" in css and ".hc-unit" in css and ".hc-dflt" in css, "EDITOR120: style.css styles the schedule lines, SPD's unit and the default marks")

    # ---- the real map, read (never pinned)
    if mq is not None and "mapRows" in res:
        rows = res["mapRows"]
        bad_spd = [r["id"] for r in rows if r["known"] and not (r["spd"] is not None and math.isfinite(r["spd"]) and r["spd"] > 0)]
        check(not bad_spd, "EDITOR120: Red Canyon: every row's creature walks at a speed above 0: %s" % bad_spd)
        bad_sched = [r["id"] for r in rows if not (r["sched"]["pacing"] and r["sched"]["pattern"] and r["sched"]["packText"])]
        check(not bad_sched, "EDITOR120: Red Canyon: every row's card has its pacing and its pattern: %s" % bad_sched)
        by_key = {"roster:%d" % i: r for i, r in enumerate(rows)}
        never = [w for w in res["mapWaits"] if w["at"] is None]
        odd = [w for w in never if not by_key.get(w["key"], {}).get("elite")]
        check(not odd, "EDITOR120: Red Canyon: only elite rows wait for colour: %s" % odd)
        spw = [w for w in res["mapWaits"] if (mq["tl"].get("roster") or [{}] * 999)[int(w["key"].split(":")[1])].get("special") is True]
        check(not spw, "EDITOR120: Red Canyon: no Special row waits for colour (pass 120): %s" % spw)
        late_ok = []
        for w in never:
            ca = res["mapStages"][w["stage"]] if w["stage"] < len(res["mapStages"]) else None
            late_ok.append(w["until"] is None or ca is None or ca >= w["until"] - 1.0)
        check(all(late_ok), "EDITOR120: Red Canyon: a wait that never came closed before that stage's colour: %s" % never)
        check(res["mapBadPoints"] == 0, "EDITOR120: Red Canyon: the stitched estimate's layers stay sane at all %d points (%d not)" % (res["mapPoints"], res["mapBadPoints"]))
        names = ", ".join("%s (%s, due %s)" % (by_key.get(w["key"], {}).get("id"), by_key.get(w["key"], {}).get("enemy"), round(w["from"], 1)) for w in never)
        print("EDITOR120: Red Canyon: %d rows; elite rows whose window closes before colour in the estimate: %s" % (len(rows), names or "none"))

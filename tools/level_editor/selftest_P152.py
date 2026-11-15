"""Pass 152: Show on screen walks the whole run. Garry (2026-11-15): "I'd want the Show on Screen feature to support the
Boss and the Endless cycle as well. I should be able to just point at a minute of the run (including boss and endless and
see it)". The run estimate keeps a point a second of a stage run's boss fight (model.js `fightPoints`: the run clock
stands still in the fight, so `points` cannot hold them); the pop-up's slider walks the stage, the fight, the portal's
countdown and Endless on one clock (onscreen.js runSegments / segAt / pointAt / rowsFor), a fight or an Endless window's
bodies are given to the window's rows by their tallies (onscreen_model.js layout `keys`, `isOpen`, `tally`), the fighting
boss stands up the screen and keeps its ground (`boss`).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

RUNNER = r"""
const path = require('path');
const M = require(process.argv[2]);
const O = require(path.join(path.dirname(process.argv[2]), 'onscreen_model.js'));
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  const byId = Object.fromEntries(q.creatures.map((c) => [c.id, c]));
  const est = M.spawnEstimate(q.tl, q.creatures, { stage: 0, end: q.end, turnover: 0.2, bossSeconds: 30 });
  const fp = est.fightPoints || [];
  out.fight = fp.map((p) => [p.fight, p.boss, p.win, p.t]);
  out.full = (M.spawnEstimate(q.tl, q.creatures, { end: q.end, turnover: 0.2, bossSeconds: 30 }).fightPoints || []).length;
  out.cacFight = fp.length ? (fp[fp.length - 1].by.cac || [0])[0] - (fp[0].by.cac || [0])[0] : 0;
  out.points = est.points.length;
  // the layout in the fight: the window's rows by their tallies, the stage's after them (closed), the boss
  const b = M.windowBlock(q.tl, 0, 'boss');
  const wr = M.bossFightRows(b);
  const rows = wr.concat(q.tl.roster);
  const keys = wr.map((_, i) => 'bossrow:0:' + i + ':').concat(q.tl.roster.map((_, i) => 'roster:' + i));
  const p = fp[fp.length - 1];
  const L = O.layout(p, fp[0], rows, byId, { seed: 5, turnover: 0.2, keys, isOpen: (ri) => ri < wr.length, boss: { id: p.boss }, variations: M });
  const boss = L.bodies.filter((x) => x.boss);
  out.boss = boss.map((x) => [x.id, x.x, x.z, x.crown]);
  out.cacRows = L.bodies.filter((x) => x.id === 'cac').map((x) => x.ri);
  out.near = Math.min(...L.bodies.filter((x) => !x.boss).map((x) => Math.hypot(x.x - boss[0].x, x.z - boss[0].z) - x.radius - boss[0].radius));
  out.counts0 = L.counts[0] ? [L.counts[0].id, L.counts[0].n, !!L.counts[0].boss] : null;
  // the tally of a prefix sums a row's tabs
  out.tally = [O.tally({ 'endlessrow:0:1:0': 2, 'endlessrow:0:1:1': 3, 'endlessrow:0:10:0': 7, 'roster:1': 4 }, 'endlessrow:0:1:'), O.tally({ 'roster:1': 4 }, 'roster:1')];
  process.stdout.write(JSON.stringify(out));
});
"""


def checks(check, run_node, server):
    creatures = [
        {"id": "old", "hp": 10, "damage": 2, "pack_size": 4, "archetype": "walker", "cap_share": 1, "size": 1, "radius": 0.4, "speed": 2},
        {"id": "cac", "hp": 20, "damage": 3, "pack_size": 2, "archetype": "walker", "cap_share": 1, "size": 1, "radius": 0.4, "speed": 2},
        {"id": "king", "hp": 500, "damage": 10, "pack_size": 1, "archetype": "boss", "kind": "boss", "size": 4, "radius": 1.2},
    ]
    tl = {"hard_cap": 300, "cap_max": 300, "cap_curve": [[0, 60], [200, 60]], "spawn_interval": 0.5, "burst_min": 4, "burst_max": 4,
          "colour_after_kills": 0, "roster": [{"id": "r1", "t": 0, "enemy": "old", "weights": [[0, 3]]}],
          "events": [{"t": 100, "type": "boss", "enemy": "king"}],
          "endless": {"portal_seconds": 60, "every": 10, "first_wave": 40, "wave_size": 10, "cap": 1.0, "roster_window": 60},
          "stage_list": [{"id": "s1", "name": "One", "length": 100, "boss": "king",
                          "boss_fight": {"length": 120, "max_count": 30, "roster": [{"id": "bf1-1", "t": 0, "enemy": "cac", "weights": [[0, 2]]}]}}]}
    res = run_node({"creatures": creatures, "tl": tl, "end": 100 + 60 + 60}, RUNNER)
    if res is None:
        print("P152: node not found: the fight points and the layout's checks under Node are skipped")
    elif res:
        f = res["fight"]
        secs = [x[0] for x in f]
        check(secs == list(range(0, 31)), "P152: a stage run keeps a point a second of its boss fight, 0..30: %s" % secs[:5])
        check(all(x[1] == "king" and x[3] == 100 for x in f), "P152: each fight point names the boss and stands at the boss's second")
        check(all(x[2] == "boss" for x in f[1:]), "P152: the fight points say the boss fight window plays")
        check(res["full"] == 0, "P152: a whole-map run keeps no fight points (only a stage run's pop-up reads them)")
        check(res["cacFight"] > 5, "P152: the window's creature comes during the fight's points: %.1f" % res["cacFight"])
        check(res["boss"] and res["boss"][0][0] == "king" and abs(res["boss"][0][1]) < 1e-9 and res["boss"][0][2] < -5 and res["boss"][0][3] is False,
              "P152: the fighting boss stands up the screen, uncrowned, where it was put: %s" % res["boss"])
        check(res["near"] > -1e-3, "P152: the crowd is pushed off the boss (no body inside it): %.3f" % res["near"])
        check(res["counts0"] == ["king", 1, True], "P152: the boss heads the counts: %s" % res["counts0"])
        check(res["cacRows"] and all(ri == 0 for ri in res["cacRows"]), "P152: the window's creature wears the window's row (its tally under bossrow:0:0:): %s" % res["cacRows"][:5])
        check(res["tally"] == [5, 4], "P152: a prefix key sums a window row's tabs, a plain key reads itself: %s" % res["tally"])
    js = open(os.path.join(HERE, "onscreen.js"), encoding="utf-8").read()
    mdl = open(os.path.join(HERE, "model.js"), encoding="utf-8").read()
    css = open(os.path.join(HERE, "style.css"), encoding="utf-8").read()
    app = open(os.path.join(HERE, "app.js"), encoding="utf-8").read()
    ins = open(os.path.join(HERE, "instructions.js"), encoding="utf-8").read()
    for want in ("function runSegments(est, w)", "function segAt(segs, u)", "function pointAt(state, u)", "function rowsFor(state, u)", "function peakRun(state)",
                 "function buildSegBar(state)", "keys: R.keys, isOpen: R.isOpen, boss:", "App.endlessSpan(s)", "e.shiftKey ? 60 : 1"):
        check(want in js, "P152: onscreen.js has %s" % want)
    check("return { points, fightPoints," in mdl and "if (SR) fightPoints.push(fightPoint(0));" in mdl, "P152: model.js returns the fight's points")
    check(".onscreen-segs" in css and ".onscreen-seg.seg-fight" in css, "P152: style.css styles the run's parts bar")
    check("endlessSpan, ENDLESS_VIEW_CYCLES" in app, "P152: App exports endlessSpan")
    check("Pass 152: the slider walks the <b>whole run</b>" in ins, "P152: the Instructions tab explains the whole run")
    for name in ("onscreen.js", "onscreen_model.js", "selftest_P152.py"):
        with open(os.path.join(HERE, name), "rb") as fh:
            check(b"\r\n" not in fh.read(), "P152: %s has LF line endings" % name)

"""Pass 151: the run estimate plays the windows. Garry (2026-11-15): "I added conditional controls to the endless mode, but
I don't see it reflected in the composition section of the timeline. I'm concerned that the endless section doesn't seem
to encompass the entirety of the cycle". The run estimate (model.js spawnEstimate) now plays a stage's boss fight window
while the boss lives and its Endless window from Endless's start (model.js windowStepper, the same rules as the cycle
estimate windowCycle and the game's BossFightWindow / EndlessWindow), so On screen, Composition and Challenge show what
the windows bring: their rows' creatures and variations, Max count growing a cycle, from_cycle / until_cycle; the stage's
own rows, the floor and the specials stand still in a window; a stage tab shows three whole cycles of its Endless
window (app.js endlessSpan); the Challenge chart prices a window row's tab from its key (timeline.js windowNumbers: its
stats at the stage's end, times Endless's growth step); the panel's chips stay inside the drawing.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

RUNNER = r"""
const M = require(process.argv[2]);
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  const run = (tl, extra) => M.spawnEstimate(tl, q.creatures, Object.assign({ stage: 0, end: q.end, turnover: 0.2, bossSeconds: 30 }, extra || {}));
  const pick = (est) => {
    const ser = M.estimateSeries(est);
    const pts = [];
    for (let k = 0; k < ser.t.length; k++) {
      const by = {};
      const same = est.points.filter((x) => Math.round(x.t) === ser.t[k]);
      const p = same.length ? same[same.length - 1] : {};
      for (const id of Object.keys(p.by || {})) by[id] = p.by[id][0];
      pts.push({ t: ser.t[k], alive: ser.alive[k], cap: ser.cap[k], by });
    }
    return { stage: est.stage, pts };
  };
  out.win = pick(run(q.tl));
  out.off = pick(run(q.tlOff));
  out.vars = pick(run(q.tlVars));
  // the cycle estimate is the stepper's too
  // the points name the window playing (the On screen lane draws its Max count as bodies)
  const e = run(q.tl);
  out.wins = Array.from(new Set(e.points.map((p) => p.win)));
  out.cycle = M.windowCycle(q.tl, 0, Object.fromEntries(q.creatures.map((c) => [c.id, c])), { turnover: 0.2 }, 'endless');
  out.stepper = typeof M.windowStepper === 'function';
  process.stdout.write(JSON.stringify(out));
});
"""


def _at(pts, t):
    """The last point at or before second t."""
    best = None
    for p in pts:
        if p["t"] <= t + 1e-9:
            best = p
    return best


def checks(check, run_node, server):
    creatures = [
        {"id": "gob", "hp": 10, "damage": 2, "pack_size": 4, "archetype": "walker", "cap_share": 1},
        {"id": "cac", "hp": 20, "damage": 3, "pack_size": 2, "archetype": "walker", "cap_share": 1},
        {"id": "cac2", "hp": 20, "damage": 3, "pack_size": 2, "archetype": "walker", "cap_share": 1},
        {"id": "old", "hp": 10, "damage": 2, "pack_size": 4, "archetype": "walker", "cap_share": 1},
        {"id": "king", "hp": 500, "damage": 10, "pack_size": 1, "archetype": "boss", "kind": "boss"},
    ]
    erows = [
        {"id": "en1-1", "t": 0, "enemy": "gob", "weights": [[0, 4], [30, 4]]},
        {"id": "en1-2", "t": 5, "enemy": "cac", "pace": "once", "count": 3, "from_cycle": 2, "weights": [[5, 1]]},
    ]
    base = {"hard_cap": 300, "cap_max": 300, "cap_curve": [[0, 60], [200, 60]], "spawn_interval": 0.5, "burst_min": 4, "burst_max": 4,
            "colour_after_kills": 0,
            "roster": [{"id": "r1", "t": 0, "enemy": "old", "weights": [[0, 3]]}],
            "events": [{"t": 100, "type": "boss", "enemy": "king"}],
            "endless": {"portal_seconds": 60, "every": 10, "first_wave": 40, "wave_size": 10, "cap": 1.0, "roster_window": 60}}

    def tl_with(window, boss=True):
        st = {"id": "s1", "name": "One", "length": 100, "boss": "king"}
        if boss:
            st["boss_fight"] = {"length": 20, "max_count": 15, "roster": [{"id": "bf1-1", "t": 0, "enemy": "cac", "weights": [[0, 2]]}]}
        if window is not None:
            st["endless_window"] = window
        t = dict(base)
        t["stage_list"] = [st]
        return t

    window = {"length": 30, "max_count": 20, "max_count_growth": 10, "roster": erows}
    var_rows = [{"id": "en1-1", "t": 0, "enemy": "gob", "weights": [[0, 4], [30, 4]], "variations": [{"percent": 50, "enemy": "cac2"}]}]
    end = 100 + 60 + 90
    q = {"creatures": creatures, "end": end, "tl": tl_with(window),
         "tlOff": tl_with(dict(window, enabled=False)),
         "tlVars": tl_with({"length": 30, "max_count": 20, "roster": var_rows}, boss=False)}
    res = run_node(q, RUNNER)
    if res is None:
        print("P151: node not found: the run estimate's window checks under Node are skipped")
    elif res:
        check(res["stepper"], "P151: model.js exports windowStepper")
        w = res["win"]
        st = w["stage"] or {}
        check(st.get("endlessWindow") is True and st.get("bossWindow") is True, "P151: the stage run says both windows played: %s" % st)
        check(st.get("endlessCycles", 0) >= 3, "P151: three cycles of Endless were played: %s" % st.get("endlessCycles"))
        pts = w["pts"]
        e0 = 100 + 60   # Endless starts
        a0, a1 = _at(pts, e0), _at(pts, end)
        check(a0 is not None and a1 is not None, "P151: points at Endless's start and the view's end")
        if a0 and a1:
            # the stage's own row stands still in a window: no more of its creature after Endless starts
            check(abs(a1["by"].get("old", 0) - a0["by"].get("old", 0)) < 1e-6,
                  "P151: the stage's row brings nothing in an Endless window: old %.2f -> %.2f" % (a0["by"].get("old", 0), a1["by"].get("old", 0)))
            check(a1["by"].get("gob", 0) > a0["by"].get("gob", 0) + 20, "P151: the window's continuous row brings its creature: gob %.1f -> %.1f" % (a0["by"].get("gob", 0), a1["by"].get("gob", 0)))
        # the boss fight window brought its creature, the stage's row did not grow in the fight (the clock stands still there)
        b0 = _at(pts, 100)
        check(b0 is not None and b0["by"].get("cac", 0) > 0, "P151: the boss fight window's row came in the fight: cac %s" % (b0 and b0["by"].get("cac", 0)))
        # from_cycle 2: the once row comes only once the second cycle has begun (its 5 s mark)
        c1 = _at(pts, e0 + 25)
        c2 = _at(pts, e0 + 30 + 10)
        cac_c1 = c1["by"].get("cac", 0) if c1 else -1
        cac_b = b0["by"].get("cac", 0) if b0 else 0
        check(c1 is not None and abs(cac_c1 - cac_b) < 1e-6, "P151: the from-cycle-2 row is quiet in cycle 1: cac %.2f (after the fight %.2f)" % (cac_c1, cac_b))
        check(c2 is not None and c2["by"].get("cac", 0) > cac_b + 2.5, "P151: the from-cycle-2 row comes in cycle 2: cac %.2f" % (c2["by"].get("cac", 0) if c2 else -1))
        # Max count grows a cycle (the limit the charts show), the crowd stays under it
        caps = [(_at(pts, e0 + c * 30 + 15) or {}).get("cap") for c in range(3)]
        check(caps == [20, 30, 40], "P151: the window's Max count is the chart's limit, +10 a cycle: %s" % caps)
        over = [p for p in pts if p["t"] > e0 + 1 and p["alive"] > p["cap"] + 3.5]
        check(not over, "P151: the crowd keeps under the window's Max count (the boss's body aside): %s" % over[:2])
        # the window switched off: the old Endless draws the stage's late rows
        o = res["off"]
        ost = o["stage"] or {}
        oa0, oa1 = _at(o["pts"], e0), _at(o["pts"], end)
        check(ost.get("endlessWindow") is False, "P151: a switched-off window plays the old Endless: %s" % ost)
        check(oa0 and oa1 and oa1["by"].get("old", 0) > oa0["by"].get("old", 0) + 20, "P151: the old Endless draws the stage's late row")
        check(oa1 and oa1["by"].get("gob", 0) < 1e-6, "P151: the old Endless never brings a window's creature")
        # a row's variations: the tab's creature at its share
        v = res["vars"]
        va = _at(v["pts"], end)
        g, c2v = (va["by"].get("gob", 0), va["by"].get("cac2", 0)) if va else (0, 0)
        check(g > 0 and c2v > 0 and abs(g - c2v) / (g + c2v) < 0.1, "P151: a 50%% tab brings half the row's bodies: gob %.1f, cac2 %.1f" % (g, c2v))
        check(set(res.get("wins") or []) == {None, "boss", "endless"}, "P151: the points name the window playing: %s" % res.get("wins"))
        cyc = res["cycle"] or {}
        check(cyc.get("maxBy") == [20, 30, 40] and len(cyc.get("spawned", [])) == 3, "P151: the cycle estimate runs on the stepper: %s" % cyc.get("maxBy"))
    # the page's wiring
    app = open(os.path.join(HERE, "app.js"), encoding="utf-8").read()
    tlj = open(os.path.join(HERE, "timeline.js"), encoding="utf-8").read()
    bfj = open(os.path.join(HERE, "boss_fights.js"), encoding="utf-8").read()
    mdl = open(os.path.join(HERE, "model.js"), encoding="utf-8").read()
    check("ENDLESS_VIEW_CYCLES = 3" in app and "function endlessSpan(s)" in app and "Math.max(AFTER_STAGE, endlessSpan(viewStage()))" in app,
          "P151: a stage tab shows three whole cycles of its Endless window (app.js endlessSpan)")
    check("function winRowOf(k)" in tlj and "function windowNumbers(key, t)" in tlj and "parts[0] === 'endlessrow'" in tlj,
          "P151: the Challenge chart prices a window row's tab from its key (timeline.js windowNumbers)")
    check("chipsW" in bfj and "W - PAD_R - chipsW" in bfj, "P151: the window panel keeps a late row's chips inside the drawing")
    check("bossWin = windowOn(tl, stage, 'boss') ? makeWin('boss') : null;" in mdl and "enWin = windowOn(tl, SR.i, 'endless') ? makeWin('endless') : null;" in mdl,
          "P151: the run estimate starts the boss fight's and Endless's windows (model.js makeWin)")
    check("const win = pt.win || null;" in tlj and "v.capB[j] = win ? cap : TimelineModel.capBodies(cap, load, L.bodies, 1);" in tlj,
          "P151: the On screen lane draws a window's Max count as bodies (never turned from load at the mix)")

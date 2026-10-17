"""Pass 87, lane STOOLS: the stages in the Level Editor (Garry: "LevelEditor will have tabs in the Timeline for each Stage
(more Stages can be added and it should be fairly simple to add (choosing the colouring should be possible too))").

Groups: the stage windows (model.js stageList / stageWindow / stageAt / stageMarks / runEnd against the Python twin and
by hand, a map with a stage_list and one without); the stage edits (stage_model.js: a length kept or stretched, a stage
added and deleted, the boss set, the fallback list written, the checks); the estimate of a STAGE RUN (spawnEstimate's
opts.stage) against its Python twin in selftest.py on fixtures and on Red Canyon, and by hand (it starts at its window
with nothing spawned, plays its own events only, the stage's boss at its end, the portal's timer after it; "All" stitches
the stage runs); the page's wiring (the strip, the card, the view's axis, the rows of a stage tab). The Sim, the Watch and
the analytics checks are added below as they land.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

RUNNER = r"""
const M = require(process.argv[2]);
const SM = require(process.argv[2].replace(/model\.js$/, 'stage_model.js'));
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.win = q.win.map(([tl, ts]) => ({ list: M.stageList(tl).map((w) => [w.i, w.id, w.name, w.start, w.end, w.length, w.boss]), n: M.stages(tl), end: M.runEnd(tl),
    at: ts.map((t) => M.stageAt(tl, t)), marks: M.stageMarks(tl), w5: [M.stageStart(tl, 5), M.stageEnd(tl, 5), M.stageLen(tl, 5)], has: M.hasStageList(tl), seed: M.seedPoints(tl, { kind: 'linear', a: 0.5 }) }));
  const pick = (e) => ({ points: e.points, ids: e.ids, marks: e.marks, fights: e.fights, colourAt: e.colourAt, stage: e.stage });
  out.est = q.est.map(([tl, cr, opts]) => pick(M.spawnEstimate(tl, cr, opts)));
  out.all = q.all.map(([tl, cr, opts]) => { const e = M.stagesEstimate(tl, cr, opts); return { t: e.points.map((p) => p.t), all: e.points.map((p) => p.all), fights: e.fights.map((f) => [f.t, f.boss]), stages: e.stages }; });
  out.ops = q.ops.map(([tl, op, args]) => {
    const d = JSON.parse(JSON.stringify(tl));
    let res;
    if (op === 'len') res = SM.setLength(d, args[0], args[1], args[2]);
    else if (op === 'lenPreview') { res = SM.lengthPreview(d, args[0], args[1], args[2]); }
    else if (op === 'add') res = SM.addStage(d);
    else if (op === 'del') res = SM.removeStage(d, args[0]);
    else if (op === 'boss') res = SM.setBoss(d, args[0], args[1]);
    else if (op === 'ensure') res = SM.ensureList(d);
    else if (op === 'field') res = SM.setField(d, args[0], args[1], args[2]);
    else if (op === 'issues') res = SM.issues(d);
    return { tl: d, res, win: M.stageList(d).map((w) => [w.start, w.end]) };
  });
  out.filters = q.filters.map((e) => SM.filterOf(e));
  out.api = ['stageList', 'stageWindow', 'stageStart', 'stageEnd', 'stageLen', 'stageMarks', 'hasStageList', 'portalTimer', 'stagesEstimate'].filter((k) => typeof M[k] !== 'function')
    .concat(['ensureList', 'setLength', 'lengthPreview', 'addStage', 'removeStage', 'removePreview', 'setBoss', 'setField', 'issues', 'filterOf', 'bossOf', 'bossEventOf'].filter((k) => typeof SM[k] !== 'function'));
  out.timer = q.timer.map(([tl, s]) => M.portalTimer(tl, s));
  out.ewave = q.ewave.map(([tl, w, s]) => [M.endlessWaveSize(tl, w, s), M.endlessMults(tl, w, s)]);
  process.stdout.write(JSON.stringify(out));
});
"""


def _main_module():
    mod = sys.modules.get("__main__")
    if mod is not None and hasattr(mod, "spawn_estimate") and hasattr(mod, "estimate_diff"):
        return mod
    import selftest
    return selftest


def _node(q):
    node = shutil.which("node")
    if not node:
        return None
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
        f.write(RUNNER)
        runner = f.name
    try:
        p = subprocess.run([node, runner, os.path.join(HERE, "model.js")], input=json.dumps(q), capture_output=True, text=True,
                           encoding="utf-8", timeout=300)
    finally:
        os.remove(runner)
    if p.returncode != 0:
        print(p.stderr[-3000:])
        return None
    return json.loads(p.stdout)


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


# a small map of three stages (100 / 140 / 60 s) with rows across them, a once row before stage 2, events in each window,
# step points at the boundaries, the stage 3 boss only in its entry
ST_TL = {
    "stage_length": 300, "stages": 3,
    "stage_list": [{"id": "s1", "name": "Dawn", "length": 100, "boss": "bossy"},
                   {"id": "s2", "name": "Dusk", "length": 140, "boss": "bossy2", "filter": {"color": "#2a4a8c", "strength": 0.35}},
                   {"id": "s3", "name": "Night", "length": 60, "boss": "bossy", "hell": True}],
    "stage_mults": [1, 2, 3], "hell_cap": [0, 0, 0.3], "path_times": [[20, 60], [30, 90], [20]],
    "cap_curve": [[0, 20], [100, 30], [240, 40], [300, 50]], "cap_max": 120, "hard_cap": 150, "burst_min": 3, "burst_max": 6,
    "spawn_interval": 0.7, "colour_after_kills": 10, "portal_wave": {"count": 8},
    "hp_curve": {"mode": "points", "points": [[0, 1], [100, 1.5], [100, 2], [240, 3], [240, 3.5], [300, 4]]},
    "damage_curve": {"mode": "points", "points": [[0, 1], [300, 2]]},
    "specials": {"from": 50, "interval": [20, 30], "max_alive": 1, "pool": [{"enemy": "tank"}, {"enemy": "fod", "stage": 3}]},
    "roster": [
        {"id": "r1", "t": 0, "enemy": "fod", "weights": [[0, 5], [100, 3]], "until": 120},
        {"id": "r2", "t": 60, "enemy": "tank", "weights": [[60, 2], [200, 4]]},
        {"id": "r3", "t": 95, "enemy": "fod", "weights": [[95, 1]], "until": 125, "pace": "once", "count": 12},
        {"id": "r4", "t": 130, "enemy": "fod", "weights": [[130, 4], [230, 6]], "until": 240, "pace": "waves", "every": 20, "count": 6},
        {"id": "r5", "t": 245, "enemy": "hellish", "weights": [[245, 3]], "channel": "hell"},
        {"id": "r6", "t": 150, "enemy": "tank", "weights": [[150, 1]], "until": 200, "pace": "once", "count": 5, "special": True},
    ],
    "events": [{"t": 50, "type": "elite_boss", "enemy": "eli"}, {"t": 100, "type": "boss", "enemy": "bossy"},
               {"t": 170, "type": "elite_boss", "enemy": "eli"}, {"t": 240, "type": "boss", "enemy": "bossy2"}],
}
ST_CR = [
    {"id": "fod", "kind": "enemy", "archetype": "walker", "hp": 10, "damage": 2, "cap_share": 1, "pack_size": 3, "max_alive": 0,
     "variance": {"special_chance": 0.05}},
    {"id": "tank", "kind": "enemy", "archetype": "walker", "hp": 60, "damage": 6, "cap_share": 2, "pack_size": 1, "max_alive": 0},
    {"id": "hellish", "kind": "enemy", "archetype": "walker", "hp": 20, "damage": 3, "cap_share": 1, "pack_size": 2, "max_alive": 0},
    {"id": "eli", "kind": "enemy", "archetype": "elite", "hp": 300, "damage": 9, "cap_share": 3, "pack_size": 1, "max_alive": 1},
    {"id": "bossy", "kind": "boss", "archetype": "boss", "hp": 2000, "damage": 20, "cap_share": 5,
     "boss": {"script": [{"name": "spawn_ring", "windup": 1, "count": 6, "enemy": "fod"}], "cooldown_between": 3}},
    {"id": "bossy2", "kind": "boss", "archetype": "boss", "hp": 3000, "damage": 25, "cap_share": 5},
]
ST_OPTS = {"turnover": 0.07, "bossSeconds": 20, "portalSeconds": 10, "skin": "fod", "boss": "bossy"}


def _stage_checks(check, st, server):
    py_list = st.stage_list_py
    legacy = {"stage_length": 430, "stages": 3}
    ts = [0, 99.9, 100, 239.9, 240, 299, 300, 359, 360, 1000]
    rc = server.load_json(server.map_path("red_canyon"))
    rc_tl = rc.get("timeline_data", {})
    creatures = server.list_creatures()
    skin = list((rc.get("skins") or {}).values())[0] if rc.get("skins") else ""
    rc_opts = {"turnover": 0.0557, "bossSeconds": 44.2, "portalSeconds": 34.9, "skin": skin, "boss": rc.get("boss", "")}

    # Red Canyon with Garry's lengths written by the editor's own stretch (the pass 87 migration's rule), whatever the file
    mig = None
    est_q, all_q = [], []
    for s in range(3):
        est_q.append([ST_TL, ST_CR, dict(ST_OPTS, stage=s)])
    est_q.append([ST_TL, ST_CR, dict(ST_OPTS, stage=1, turnover=[[0, 0.02], [60, 0.09]])])
    est_q.append([ST_TL, ST_CR, dict(ST_OPTS, stage=9)])
    est_q.append([legacy and dict(ST_TL, stage_list=None), ST_CR, dict(ST_OPTS, stage=1)])
    for s in range(3):
        est_q.append([rc_tl, creatures, dict(rc_opts, stage=s)])
    all_q.append([ST_TL, ST_CR, ST_OPTS])
    q = {"win": [[ST_TL, ts], [legacy, ts], [{"stage_list": [{"length": 0}, "x", {"name": "", "length": 50}]}, [0, 10, 300, 360]], [rc_tl, ts]],
         "est": est_q, "all": all_q, "ops": [], "filters": [{}, {"filter": {"color": "#FF0000", "strength": 2}}, {"filter": {"color": "red", "strength": 0.3}}, None],
         "timer": [[{}, None], [{"endless": {"portal_seconds": 45}}, None], [{"endless": {"portal_seconds": 45}, "stage_list": [{"length": 10, "endless": {"portal_seconds": 30}}, {"length": 10}]}, 0],
                   [{"endless": {"portal_seconds": 45}, "stage_list": [{"length": 10, "endless": {"portal_seconds": 30}}, {"length": 10}]}, 1], [{"endless": {"portal_seconds": 0}}, 0]],
         "ewave": [[{}, 1, 0], [{}, 2, 0], [{}, 5, 0], [{"endless": {"first_wave": 50, "wave_size": 10, "wave_growth": 3, "hp": 2, "hp_growth": 0.5, "speed": 1.5, "speed_growth": 0.5, "speed_max": 2}}, 4, 0]]}
    # the edits
    q["ops"] = [
        [ST_TL, "len", [1, 200, "keep"]],
        [ST_TL, "len", [1, 60, "keep"]],
        [ST_TL, "len", [1, 70, "stretch"]],
        [ST_TL, "len", [0, 150, "stretch"]],
        [ST_TL, "add", []],
        [ST_TL, "del", [1]],
        [ST_TL, "del", [0]],
        [ST_TL, "del", [2]],
        [ST_TL, "boss", [2, "bossy2"]],
        [ST_TL, "boss", [0, ""]],
        [legacy, "ensure", []],
        [dict(rc_tl), "ensure", []],
        [ST_TL, "field", [1, "filter", {"color": "#AABBCC", "strength": 0.456}]],
        [ST_TL, "field", [0, "name", ""]],
        [{"stage_list": [{"id": "a", "length": 0}, {"id": "a", "length": 30, "filter": {"color": "blue", "strength": 3}}]}, "issues", []],
        [{"stage_list": [{"id": "only", "length": 30}]}, "del", [0]],
        [ST_TL, "lenPreview", [1, 70, "keep"]],
        [dict(legacy, events=[{"t": 430, "type": "boss", "enemy": "k"}, {"t": 860, "type": "boss", "enemy": "g"}, {"t": 1290, "type": "boss", "enemy": "b"}]), "len", [1, 600, "stretch"]],
    ]
    js = _node(q)
    check(js is not None, "stools87: model.js and stage_model.js ran under node")
    if js is None:
        return
    check(js["api"] == [], "stools87: the stage API is there (%s missing)" % js["api"])
    # ---- the windows
    w0 = js["win"][0]
    check(w0["list"] == [[0, "s1", "Dawn", 0, 100, 100, "bossy"], [1, "s2", "Dusk", 100, 240, 140, "bossy2"], [2, "s3", "Night", 240, 300, 60, "bossy"]],
          "stools87: a stage_list's windows start at the sum of the earlier lengths (%s)" % w0["list"])
    check(w0["n"] == 3 and w0["end"] == 300 and w0["marks"] == [0, 100, 240, 300] and w0["has"] is True, "stools87: stages, the run's end and the marks")
    check(w0["at"] == [0, 0, 1, 1, 2, 2, 2, 2, 2, 2], "stools87: stageAt by window, the last stage past the end (a stage_list map: WaveTimeline.stage_at) (%s)" % w0["at"])
    check(w0["w5"] == [420, 480, 60], "stools87: a window past the stages goes on at the last length (%s)" % w0["w5"])
    check(w0["seed"] == [[0, 1], [100, round(1 + 0.5 * 100 / 60, 4)], [240, 3], [300, round(1 + 0.5 * 5, 4)]], "stools87: a formula seeds its points at each window's start (%s)" % w0["seed"])
    w1 = js["win"][1]
    check(w1["list"] == [[0, "s1", "Stage 1", 0, 430, 430, ""], [1, "s2", "Stage 2", 430, 860, 430, ""], [2, "s3", "Stage 3", 860, 1290, 430, ""]]
          and w1["has"] is False and w1["end"] == 1290, "stools87: without a stage_list, stage_length x stages as before")
    check(w1["at"] == [max(0, int(t // 430)) for t in ts], "stools87: the fallback's stageAt is floor(t / stage_length) as before (%s)" % w1["at"])
    w2 = js["win"][2]
    check([x[3:6] for x in w2["list"]] == [[0, 300, 300], [300, 350, 50]] and w2["list"][1][2] == "Stage 2",
          "stools87: a bad entry is skipped, a length under 1 s is stage_length, an empty name is 'Stage k' (%s)" % w2["list"])
    for k, (tl, _) in enumerate(q["win"]):
        pl = py_list(tl)
        check([[x["i"], x["id"], x["name"], x["start"], x["end"], x["length"], x["boss"]] for x in pl] == js["win"][k]["list"],
              "stools87: the Python twin's stage list equals model.js's (%d)" % k)
    check(js["timer"] == [60, 45, 30, 45, 0], "stools87: the portal's countdown: the stage's endless block, the map's, else 60 (%s)" % js["timer"])
    for k, (tl, s) in enumerate(q["timer"]):
        check(st.portal_timer_py(tl, s) == js["timer"][k], "stools87: the Python twin's portal countdown %d" % k)
    ew = js["ewave"]
    check([x[0] for x in ew] == [120, 30, 36, 16], "stools87: Endless wave sizes: the huge first, then wave_size + growth x (k - 2) (%s)" % [x[0] for x in ew])
    m4 = ew[3][1]
    check(abs(m4["hp"] - 2 * 1.5 ** 3) < 1e-9 and abs(m4["speed"] - 2) < 1e-9 and abs(ew[0][1]["atk"] - 1.2) < 1e-9,
          "stools87: Endless's HP compounds per wave, its speed grows linearly to speed_max (%s)" % m4)
    for k, (tl, w, s) in enumerate(q["ewave"]):
        check(st.endless_wave_size_py(tl, w, s) == ew[k][0], "stools87: the Python twin's wave size %d" % k)
    check(js["filters"] == [{"color": "#000000", "strength": 0}, {"color": "#ff0000", "strength": 1}, {"color": "#000000", "strength": 0.3}, {"color": "#000000", "strength": 0}],
          "stools87: a filter as the game reads it: #rrggbb lower case, strength 0..1, else no tint (%s)" % js["filters"])

    # ---- the estimate of a stage run: the twins
    for k, (tl, cr, opts) in enumerate(est_q):
        py = st.spawn_estimate(copy.deepcopy(tl), cr, opts)
        d = st.estimate_diff(js["est"][k], py)
        check(not d, "stools87: stage run estimate %d (stage %s) equals its Python twin%s" % (k, opts.get("stage"), (": " + "; ".join(d[:4])) if d else ""))
        check(js["est"][k]["stage"] == py["stage"], "stools87: stage run %d names its window alike (%s / %s)" % (k, js["est"][k]["stage"], py["stage"]))
    # by hand
    e1 = js["est"][1]
    p0 = e1["points"][0]
    check(p0["t"] == 100 and p0["all"] == 0 and p0["alive"] == 0, "stools87: stage 2's run starts at its window (1:40) with nothing spawned (%s)" % [p0["t"], p0["all"]])
    check([f["t"] for f in e1["fights"]] == [240] and e1["fights"][0]["boss"] == "bossy2", "stools87: stage 2's run meets only its own boss, at its end (%s)" % e1["fights"])
    check(e1["stage"] == {"i": 1, "start": 100, "end": 240, "portal": 60, "endless": 120, "waves": 13}, "stools87: the run says its window, the portal's countdown and its Endless (%s)" % e1["stage"])
    check(abs(e1["points"][-1]["t"] - 420) < 1e-9, "stools87: the portal's minute and then Endless are drawn after its end, to the view's end 7:00 (%s)" % e1["points"][-1]["t"])
    portal_pts = [p for p in e1["points"] if 240 < p["t"] <= 300]
    check(len(portal_pts) == 60 and all(abs(p["all"] - portal_pts[0]["all"]) < 1e-9 for p in portal_pts), "stools87: nothing comes in the portal's minute after a portal wave (%d points)" % len(portal_pts))
    en_marks = [m for m in e1["marks"] if m["kind"] == "swarm" and m["t"] >= 300]
    check(len(en_marks) == 13 and abs(en_marks[0]["t"] - 300) < 1e-9 and abs(en_marks[0]["n"] - 120) < 1e-6 and abs(en_marks[1]["n"] - 30) < 1e-6,
          "stools87: Endless: 120 at once as the countdown runs out, then a wave every 10 s (%s)" % [(m["t"], round(m["n"], 1)) for m in en_marks[:3]])
    check(not any(m["kind"] == "elite" and m["t"] < 100 for m in e1["marks"]) and any(m["kind"] == "elite" and m["t"] == 170 for m in e1["marks"]),
          "stools87: only the window's own Elite comes (2:50, not 0:50)")
    check("roster:2" not in e1["points"][-1]["src"], "stools87: a once row 5 s before the window is dropped (a stage run's director skips it)")
    check(e1["points"][-1]["src"].get("roster:5", 0) > 0, "stools87: the window's own once row (a special) comes")
    e2 = js["est"][2]
    check([f["t"] for f in e2["fights"]] == [300] and e2["fights"][0]["boss"] == "bossy", "stools87: stage 3's boss comes from its entry when no boss event is at its end (%s)" % e2["fights"])
    e0 = js["est"][0]
    check([f["t"] for f in e0["fights"]] == [100] and e0["points"][0]["t"] == 0, "stools87: stage 1's run is 0:00 to its boss at 1:40")
    check(js["est"][4]["stage"]["i"] == 2, "stools87: a stage past the last is the last")
    lg = js["est"][5]
    check(lg["stage"]["start"] == 300 and lg["stage"]["end"] == 600 and lg["fights"] == [] and any(p["after"] and p["t"] == 600 for p in lg["points"]),
          "stools87: a map without a list plays its stage 2 window (5:00-10:00); no boss there: the portal opens at its end all the same (%s)" % lg["stage"])
    for s in range(3):
        e = js["est"][6 + s]
        check(e["stage"] is not None and e["points"][0]["all"] == 0 and len(e["fights"]) == 1, "stools87: Red Canyon's stage %d run: fresh, one boss (%s)" % (s + 1, [f["boss"] for f in e["fights"]]))
    a = js["all"][0]
    check(all(a["t"][i] <= a["t"][i + 1] for i in range(len(a["t"]) - 1)), "stools87: All's stitched points are in time order")
    check(a["fights"] == [[100, "bossy"], [240, "bossy2"], [300, "bossy"]] and [x["i"] for x in a["stages"]] == [0, 1, 2], "stools87: All stitches the three runs (%s)" % a["fights"])
    i100 = [i for i, t in enumerate(a["t"]) if t == 100]
    check(len(i100) >= 1 and a["all"][i100[-1]] == 0, "stools87: All starts the count again at each window (a fresh run): 0 spawned at 1:40")

    # ---- the edits
    ops = js["ops"]
    o = ops[0]   # stage 2 100 -> 200 s, keep
    tl = o["tl"]
    check(o["win"] == [[0, 100], [100, 300], [300, 360]] and o["res"]["delta"] == 60 and o["res"]["mode"] == "keep", "stools87: a longer stage moves the later windows (%s)" % o["win"])
    rows = {r["id"]: r for r in tl["roster"]}
    check(rows["r5"]["t"] == 305 and rows["r5"]["weights"] == [[305, 3]], "stools87: a later stage's row moves with its window (%s)" % rows["r5"])
    check(rows["r4"]["t"] == 130 and rows["r4"]["until"] == 300 and rows["r4"]["weights"] == [[130, 4], [230, 6]], "stools87: keep: the stage's own row keeps its times; one that ran to its end runs to the new end (%s)" % rows["r4"])
    check(rows["r2"]["weights"] == [[60, 2], [200, 4]], "stools87: a keyframe inside the stage stays (keep)")
    check([e["t"] for e in tl["events"]] == [50, 100, 170, 300], "stools87: the stage's boss goes with its end, its Elite stays (%s)" % [e["t"] for e in tl["events"]])
    check(tl["hp_curve"]["points"] == [[0, 1], [100, 1.5], [100, 2], [300, 3], [300, 3.5], [360, 4]] and tl["cap_curve"] == [[0, 20], [100, 30], [300, 40], [360, 50]],
          "stools87: the curve points at and after the end move with it (%s)" % tl["hp_curve"]["points"])
    check(tl["stage_list"][1]["length"] == 200 and tl["path_times"] == ST_TL["path_times"] and tl["specials"]["from"] == 50,
          "stools87: the length is written; mutation offers (seconds into a stage) and an earlier specials' start stay")
    o = ops[1]   # stage 2 -> 60 s, keep: what lies past 2:40 is cut
    tl = o["tl"]
    rows = {r["id"]: r for r in tl["roster"]}
    check(o["win"] == [[0, 100], [100, 160], [160, 220]], "stools87: a shorter stage moves the later ones back (%s)" % o["win"])
    check("r6" in rows and rows["r6"]["until"] == 160 and rows["r4"]["until"] == 160 and rows["r4"]["weights"] == [[130, 4]] and "row r6" in o["res"]["ends"],
          "stools87: keep, shorter: ends past the new end come back to it, keyframes there drop (%s)" % [rows["r4"], rows.get("r6"), o["res"]["ends"]])
    check([e["t"] for e in tl["events"]] == [50, 100, 160] and o["res"]["cut"] == ["elite_boss at 2:50"],
          "stools87: keep, shorter: the Elite past the new end is cut, the boss lands on the new end (%s; cut %s)" % ([e["t"] for e in tl["events"]], o["res"]["cut"]))
    check(rows["r5"]["t"] == 165, "stools87: the next stage's row moved back with its window")
    o = ops[2]   # stage 2 -> 70 s, stretch
    tl = o["tl"]
    rows = {r["id"]: r for r in tl["roster"]}
    check(o["res"]["cut"] == [] and rows["r4"]["t"] == 115 and rows["r4"]["until"] == 170 and rows["r4"]["weights"] == [[115, 4], [165, 6]],
          "stools87: stretch: the stage's own times scale by new / old from its start, nothing is cut (%s)" % rows["r4"])
    check([e["t"] for e in tl["events"]] == [50, 100, 135, 170] and rows["r2"]["weights"] == [[60, 2], [150, 4]],
          "stools87: stretch: its Elite and the keyframes inside scale too (%s)" % [e["t"] for e in tl["events"]])
    o = ops[3]   # stage 1 100 -> 150 stretch
    tl = o["tl"]
    rows = {r["id"]: r for r in tl["roster"]}
    check(o["win"] == [[0, 150], [150, 290], [290, 350]] and rows["r1"]["weights"] == [[0, 5], [150, 3]] and rows["r1"]["until"] == 170 and tl["specials"]["from"] == 75,
          "stools87: stretching stage 1 moves its rows, its specials' start and every later thing (%s)" % [o["win"], rows["r1"], tl["specials"]["from"]])
    o = ops[4]   # add
    tl = o["tl"]
    check(o["win"][-1] == [300, 360] and o["res"]["i"] == 3 and o["res"]["id"] == "s4" and tl["stage_list"][3]["name"] == "Stage 4"
          and tl["stage_list"][3]["boss"] == "bossy" and tl["stage_list"][3]["hell"] is True,
          "stools87: + Stage appends a copy of the last one's settings (%s)" % tl["stage_list"][3])
    check(tl["events"][-1] == {"t": 360, "type": "boss", "enemy": "bossy"} and tl["stage_mults"] == [1, 2, 3, 3] and tl["hell_cap"] == [0, 0, 0.3, 0.3]
          and tl["path_times"] == [[20, 60], [30, 90], [20], [20]] and len(tl["roster"]) == len(ST_TL["roster"]),
          "stools87: its boss at its end, the per-stage lists one longer, no new rows (%s)" % [tl["events"][-1], tl["stage_mults"]])
    o = ops[5]   # delete stage 2
    tl = o["tl"]
    rows = {r["id"]: r for r in tl["roster"]}
    check(o["res"]["ok"] and o["win"] == [[0, 100], [100, 160]] and [s["id"] for s in tl["stage_list"]] == ["s1", "s3"], "stools87: deleting stage 2 closes its window (%s)" % o["win"])
    check("r4" not in rows and "r6" not in rows and rows["r5"]["t"] == 105 and rows["r1"]["until"] == 100 and rows["r2"]["t"] == 60,
          "stools87: its rows go, a row spanning into it ends at its start, a later row moves back (%s)" % sorted(rows))
    check([e["t"] for e in tl["events"]] == [50, 100] and tl["stage_mults"] == [1, 3] and tl["path_times"] == [[20, 60], [20]] and tl["hell_cap"] == [0, 0.3],
          "stools87: its Elite and boss go (stage 1's boss stays), its per-stage entries go (%s)" % [e["t"] for e in tl["events"]])
    check(tl["hp_curve"]["points"] == [[0, 1], [100, 1.5], [100, 3.5], [160, 4]], "stools87: the curve keeps stage 1's end and stage 3's start as a step (%s)" % tl["hp_curve"]["points"])
    check(tl["specials"]["pool"][1]["stage"] == 2, "stools87: a special that came from stage 3 now comes from stage 2")
    o = ops[6]   # delete stage 1
    tl = o["tl"]
    rows = {r["id"]: r for r in tl["roster"]}
    check(o["win"] == [[0, 140], [140, 200]] and [e["t"] for e in tl["events"]] == [70, 140] and rows["r2"]["t"] == 0 and "r1" in rows and rows["r1"]["until"] == 20,
          "stools87: deleting stage 1: what spans into stage 2 starts at 0:00 (%s)" % [o["win"], [e["t"] for e in tl["events"]], rows.get("r1")])
    o = ops[7]   # delete the last stage
    check(o["res"]["ok"] and o["win"] == [[0, 100], [100, 240]] and "r5" not in {r["id"] for r in o["tl"]["roster"]} and [e["t"] for e in o["tl"]["events"]] == [50, 100, 170, 240],
          "stools87: deleting the last stage keeps stage 2's boss at its end")
    o = ops[8]
    check(o["tl"]["stage_list"][2]["boss"] == "bossy2" and o["tl"]["events"][-1] == {"t": 300, "type": "boss", "enemy": "bossy2"}, "stools87: a boss set on a stage without a boss event makes one at its end")
    o = ops[9]
    check(o["tl"]["stage_list"][0]["boss"] == "" and all(not (e["type"] == "boss" and e["t"] == 100) for e in o["tl"]["events"]), "stools87: no boss removes its boss event")
    o = ops[10]
    check(o["res"] is True and [(s["id"], s["length"], s["hell"]) for s in o["tl"]["stage_list"]] == [("s1", 430, False), ("s2", 430, False), ("s3", 430, True)],
          "stools87: ensureList writes the fallback list (hell from the third stage, as Game.gd's hell ground) (%s)" % o["tl"]["stage_list"])
    o = ops[11]
    check(isinstance(o["tl"].get("stage_list"), list) and len(o["tl"]["stage_list"]) >= 1, "stools87: Red Canyon's list is there or written")
    o = ops[12]
    check(o["tl"]["stage_list"][1]["filter"] == {"color": "#aabbcc", "strength": 0.46}, "stools87: a filter is written lower case, its strength to 2 places (%s)" % o["tl"]["stage_list"][1]["filter"])
    check(ops[13]["tl"]["stage_list"][0]["name"] == "Stage 1", "stools87: an empty name is Stage k")
    iss = ops[14]["res"]
    msgs = " | ".join(x["msg"] for x in iss)
    check(any(x["level"] == "error" and "length" in x["msg"] for x in iss) and any("used twice" in x["msg"] for x in iss) and any("not #rrggbb" in x["msg"] for x in iss)
          and any("strength" in x["msg"] for x in iss) and all("i" in x for x in iss), "stools87: the checks: a bad length, a twice-used id, a bad colour and strength (%s)" % msgs)
    check(ops[15]["res"]["ok"] is False and ops[15]["win"] == [[0, 30]], "stools87: the last stage cannot be deleted")
    pv = ops[16]
    check(pv["tl"] == ST_TL and pv["res"]["delta"] == -70, "stools87: a preview changes nothing")
    o = ops[17]
    check([e["t"] for e in o["tl"]["events"]] == [430, 1030, 1460] and o["win"] == [[0, 430], [430, 1030], [1030, 1460]],
          "stools87: Red Canyon's old shape: stage 2 stretched to 10:00 puts the Gila at 17:10 (%s)" % o["win"])


def _page_checks(check):
    idx = _read(HERE, "index.html")
    a, b, c = idx.find('src="stage_model.js"'), idx.find('src="stage_tabs.js"'), idx.find('src="timeline.js"')
    check(0 < a < b < c, "stools87: index.html loads stage_model.js and stage_tabs.js before timeline.js")
    app = _read(HERE, "app.js")
    for frag in ["stageView: 'all',", "const viewStart = () =>", "function setStageView(v)", "stageList, stageStart, stageEnd, stageLen, stageWindow, viewStage, viewStart, setStageView, portalSeconds,",
                 "M.stagesEstimate(tl(), S.enemies, opts)", "if (s.kind === 'stage')", "mark(`stage:${m.i}`, m.level, m.msg)"]:
        check(frag in app, "stools87: app.js has %s" % frag)
    tl = _read(HERE, "timeline.js")
    for frag in ["const x = (t) => (t - T0) / spp;", "const tAt = (clientX) => (clientX - svgLeft()) * spp + T0;", "function renderStageTabs()", "function rowInView(r)",
                 "if (!rowInView(r)) return;", "stageBar = el('div', { class: 'tl-stagebar' });", "App.select({ kind: 'stage', i: k })"]:
        check(frag in tl, "stools87: timeline.js has %s" % frag)
    check("px * spp)" not in tl, "stools87: every sampled line reads its second through the view's start (no px * spp left)")
    ins = _read(HERE, "inspector.js")
    check("else if (sel.kind === 'stage' && typeof StageTabs !== 'undefined') StageTabs.card(container, sel.i);" in ins, "stools87: the inspector draws a stage's card")
    tabs = _read(HERE, "stage_tabs.js")
    for frag in ["function renderStrip(host)", "function card(container, i)", "function addStage()", "function deleteStage(i)", "function lengthConfirm(host, i, len)",
                 "'Keep its times'", "Stretch ×", "type: 'color'" if "type: 'color'" in tabs else "Forms.swatchInput(", "type: 'range'", "drawSwatch(canvas", "'Hell ground'"]:
        check(frag in tabs, "stools87: stage_tabs.js has %s" % frag)
    css = _read(HERE, "style.css")
    check(".tl-stagebar {" in css and ".stg-tab.active {" in css and ".stg-confirm {" in css, "stools87: the strip's and the card's styles")


SIM_RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const A = require(path.join(dir, 'sim_avg.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = { agg: q.agg.map((c) => { const r = A.aggregate(c.players, c.settings, {}, {}); return { summary: r.summary, players: r.players }; }) };
  process.stdout.write(JSON.stringify(out));
});
"""


def _stage_players():
    """Four hand-made stage runs of stage 2 (sim_run.gd's meta since pass 87): one fell before the boss, one after it, two
    in Endless (12 s and 40.5 s), and one from before pass 87 (no outcome)."""
    def run(n, meta):
        ts = list(range(1, n + 1))
        m = {"end_reason": "death", "end_t": float(n), "wall_s": 20.0, "boot_s": 10.0, "build_text": "Revolver 1"}
        m.update(meta)
        return {"t": ts, "hp": [100] * n, "hp_max": [100] * n, "dps": [10] * n, "est": [10] * n, "alive": [5] * n, "press_hp": [50] * n,
                "press_dmg": [5] * n, "kills": ts, "deaths": [0] * (n - 1) + [1], "level": [1] * n, "gold_total": ts, "xp_total": ts,
                "clock": [430 + t for t in ts], "stage": [2] * n, "took": [3] * n, "healed": [1] * n, "hits": [1] * n,
                "kills_by": {"goblin": ts}, "alive_by": {"goblin": [5] * n}, "dmg_by": {"revolver": [10 * t for t in ts]}, "events": [], "meta": m}
    return [(1, run(8, {"stage": 2, "outcome": "died", "boss_killed": False, "endless_s": 0}), {"seed": 1}),
            (2, run(9, {"stage": 2, "outcome": "died_after_boss", "boss_killed": True, "endless_s": 0}), {"seed": 2}),
            (3, run(10, {"stage": 2, "outcome": "died_endless", "boss_killed": True, "endless_s": 12}), {"seed": 3}),
            (4, run(10, {"stage": 2, "outcome": "died_endless", "boss_killed": True, "endless_s": 40.5}), {"seed": 4}),
            (5, run(6, {}), {"seed": 5})]


def _sim_checks(check):
    import sim_batch as SB
    import watch as W
    s, probs = SB.clean_settings({"stage": 2})
    check(s["stage"] == 2 and not probs, "stools87: a sim's settings keep its stage (%s)" % probs)
    s, probs = SB.clean_settings({})
    check(s["stage"] == 1, "stools87: a sim plays stage 1 unless told")
    s, probs = SB.clean_settings({"stage": 0})
    check(s["stage"] == 1 and probs, "stools87: stage 0 is refused (back to 1)")
    s, probs = SB.clean_settings({"stage": 9}, maps={"red_canyon"})
    n_st = len(SB.map_stages("red_canyon"))
    check(s["stage"] == n_st and any("stage must be 1 to" in x for x in probs), "stools87: a stage past the map's last is refused (%s)" % probs)
    class _P:
        json, log, seed = "p01.json", "p01.log", 5
    args = SB.player_args(SB.clean_settings({"stage": 3})[0], _P(), "SNAP", "OUT", 900)
    check("stage=3" in args, "stools87: every player of the sim is told its stage (%s)" % [a for a in args if a.startswith("stage")])
    sts = SB.map_stages("red_canyon")
    check(sts and sts[0]["start"] == 0 and all(sts[i]["start"] == sts[i - 1]["end"] for i in range(1, len(sts))) and all(x["boss"] for x in sts),
          "stools87: map_stages reads the map's windows and bosses (%s)" % [(x["id"], x["start"], x["end"], x["boss"]) for x in sts])
    syn = SB.synthetic_player(1, 7, {"stage": 2, "limit": 120})
    check(abs(syn["clock"][0] - sts[1]["start"]) <= 1.01 and syn["stage"][0] == 2, "stools87: a made-up stage 2 run starts at its window (%s)" % [syn["clock"][0], syn["stage"][0]])
    st1 = SB.synthetic_player(1, 7, {"limit": 120})
    check(st1["clock"][0] <= 1.01 and st1["stage"][0] == 1, "stools87: a made-up stage 1 run is as before")
    # the twins on stage runs: the per-player stage fields and the stage_run summary
    ps = _stage_players()
    st = {"players": 5, "limit": 10, "death": "end", "stage": 2}
    py = json.loads(json.dumps(SB.aggregate(ps, st, {}, game_dir=os.path.join(ROOT, "nogame"))))
    sr = py["summary"]["stage_run"]
    check(sr == {"runs": 4, "stage": 2, "boss_killed": 3, "outcomes": {"died": 1, "died_after_boss": 1, "died_endless": 2}, "endless_runs": 2, "endless_s_median": 26.25},
          "stools87: the sim's summary counts the boss kills, the outcomes and Endless (%s)" % sr)
    check([p.get("outcome") for p in py["players"]] == ["died", "died_after_boss", "died_endless", "died_endless", None], "stools87: each player says how his stage run ended")
    out = _node_sim({"agg": [{"players": [{"k": k, "d": d, "rec": r} for k, d, r in ps], "settings": st}]})
    if out is not None:
        js = out["agg"][0]
        check(js["summary"].get("stage_run") == sr and [p.get("outcome") for p in js["players"]] == [p.get("outcome") for p in py["players"]]
              and [p.get("endless_s") for p in js["players"]] == [p.get("endless_s") for p in py["players"]],
              "stools87: sim_avg.js is sim_batch.py on stage runs (%s / %s)" % (js["summary"].get("stage_run"), sr))
    check(SB.aggregate(_stage_players()[4:], {"players": 1, "limit": 10}, {}, game_dir=os.path.join(ROOT, "nogame"))["summary"]["stage_run"] is None,
          "stools87: a sim from before pass 87 has no stage_run summary")
    # the Watch's launcher: --stage, the save's stages
    import argparse
    a = argparse.Namespace(hero="drifter", seed=5, map="red_canyon", limit="0", speed="1", death="end", unlocks="all", mute=False,
                           no_numbers=False, log_speed="30", paused=False, stub=False, bot_preset="", bot=[], autoquit=False, wall=0,
                           shots="", shots_at="", size="", profile=False, actions="", skip_draw="1")
    check("stage=1" in W.build_args(a, {}, "none", None, "", "C:/l"), "stools87: the Watch plays stage 1 unless told")
    a.stage = 3
    check("stage=3" in W.build_args(a, {}, "none", None, "", "C:/l"), "stools87: --stage 3 reaches the Watch")
    check(W.ref_stage_ok(2, 2) and W.ref_stage_ok(None, 1) and not W.ref_stage_ok(None, 2) and not W.ref_stage_ok(3, 2),
          "stools87: the Watch's grey line is a Sim of the same stage (an old whole-run Sim only for stage 1)")
    tmp = tempfile.mkdtemp(prefix="le_stools87_")
    try:
        save = os.path.join(tmp, "save.json")
        json.dump({"once": ["boss_red_canyon_1"], "totals": {"kills_of_enemy": {}}}, open(save, "w", encoding="utf-8"))
        keep = SB.locks.RESTORE_PENDING
        SB.locks.RESTORE_PENDING = os.path.join(tmp, "no_restore_pending")
        try:
            got, note = SB.save_stages(tmp)
            check(got.get("red_canyon", [])[:1] == [True] and not any(got.get("red_canyon", [])[1:]), "stools87: an unmigrated save's stages from its old boss flags (%s)" % got)
            json.dump({"once": ["stages_migrated"], "stages_beaten": {"red_canyon": [True, True]}}, open(save, "w", encoding="utf-8"))
            got, note = SB.save_stages(tmp)
            check(got == {"red_canyon": [True, True]}, "stools87: a migrated save's stages_beaten as it is (%s)" % got)
            gk = sts[1]["boss"]
            json.dump({"once": [], "totals": {"kills_of_enemy": {gk: 2}}}, open(save, "w", encoding="utf-8"))
            got, note = SB.save_stages(tmp)
            check(got.get("red_canyon", [None, None])[1] is True, "stools87: a kill of stage 2's boss counts it beaten (%s)" % got)
        finally:
            SB.locks.RESTORE_PENDING = keep
        setup = os.path.join(tmp, "setup.json")
        keep2 = W.SB.save_board, W.SB.list_sims, W.SB.save_stages
        W.SB.save_board = lambda: ({}, "")
        W.SB.list_sims = lambda: []
        W.SB.save_stages = lambda: ({"red_canyon": [True]}, "read from x")
        try:
            W.write_setup(setup)
        finally:
            W.SB.save_board, W.SB.list_sims, W.SB.save_stages = keep2
        d = json.load(open(setup, encoding="utf-8"))
        check(d.get("save_stages") == {"red_canyon": [True]} and d.get("save_stages_note") == "read from x", "stools87: the Watch's setup file carries the save's stages")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    # the bot's answer at the portal (pass 87: no going on to the next stage)
    pv = SB.bot_presets()
    check(pv and all(v.get("portal") == "endless" for v in pv.values()), "stools87: every bot preset plays on into Endless (%s)" % {k: v.get("portal") for k, v in pv.items()})
    check(SB.clean_bot("portal=extract")[0] == {"portal": "extract"} and SB.clean_bot({"portal": "go_on"})[1], "stools87: the bot's portal option: endless or extract")
    bot_src = _read(ROOT, "game", "tools", "bot", "Bot.gd")
    check('const PORTAL_CHOICES := ["endless", "extract"]' in bot_src and 'g.portal_dialog.decided.emit(out)' in bot_src
          and bot_src.count('str(opts.get("portal", "endless")) == "extract"') >= 3, "stools87: Bot.gd walks to the portal and extracts only when told")
    check('"specials", "portal"]' in _read(ROOT, "game", "tools", "sim_run.gd"), "stools87: sim_run.gd passes the bot's portal option")
    check('["portal", "Portal", ["endless", "extract"]]' in _read(ROOT, "game", "tools", "watch", "WatchSetup.gd"), "stools87: the Watch's bot form has Portal")
    # the Level Editor's routes and job spec pass the stage on
    jobs_src = _read(HERE, "jobs.py")
    check('"stage": _f("int", 1, False,' in jobs_src and '"--stage", str(int(s.get("stage", 1) or 1))' in jobs_src, "stools87: the sim job's spec and command carry the stage")
    io_src = _read(HERE, "sim_io.py")
    check('"--stage", str(int(s.get("stage", 1) or 1))' in io_src, "stools87: the Sim tab's Watch button passes the stage")
    sim_js = _read(HERE, "sim.js")
    check("field('Stage', stSel," in sim_js and "stage: Math.max(1, Math.min(Number(f.stage) || 1, App.stages()))" in sim_js, "stools87: the Sim tab's Stage box")


def _node_sim(q):
    node = shutil.which("node")
    if not node:
        return None
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
        f.write(SIM_RUNNER)
        runner = f.name
    try:
        p = subprocess.run([node, runner, os.path.join(HERE, "sim_avg.js")], input=json.dumps(q), capture_output=True, text=True, encoding="utf-8", timeout=120)
    finally:
        os.remove(runner)
    if p.returncode != 0:
        print(p.stderr[-2000:])
        return None
    return json.loads(p.stdout)


def _analytics_checks(check):
    ra = _read(ROOT, "game", "core", "systems", "RunAnalytics.gd")
    for frag in ["static func stage_header() -> Dictionary:", "func stage_end_fields() -> Dictionary:", "header.merge(stage_header(), true)",
                 '_connect(dir, "stage_cleared"', '_putf(row, "en",']:
        check(frag in ra, "stools87: RunAnalytics.gd has %s" % frag)
    check('_connect(dir, "endless_started"' not in ra and 'RunAnalytics.I.event("endless", "", Run.stage + 1)' in _read(ROOT, "game", "game", "Game.gd"),
          "stools87: Endless begun is recorded once (Game's event, not the recorder's too)")
    an = _read(ROOT, "game", "core", "autoload", "Analytics.gd")
    for frag in ['"stage_beaten": "stage_beaten", "endless": "endless_started"', "func stage_props() -> Dictionary:", 'p["choice"] = "extract" if bool(p.get("extract", false)) else "not_yet"']:
        check(frag in an, "stools87: Analytics.gd has %s" % frag)
    sch = _read(ROOT, "analytics", "SCHEMA.md")
    for frag in ["`stage_index`, `stage_id`, `stage_name`", "`outcome`, `boss_killed`, `stage_clock`, `endless_s`, `run_time`", "| `en` |", "| `stage_beaten` |", "**Stages (pass 87).**"]:
        check(frag in sch, "stools87: SCHEMA.md documents %s" % frag)
    dash = _read(ROOT, "analytics", "dashboard.html")
    for frag in ['<select id="stagefilter">', "function stageKey(r)", "const OUTCOME_WORDS", "stageOk(r)", "function syncStageFilter()"]:
        check(frag in dash, "stools87: dashboard.html has %s" % frag)
    pb = _read(ROOT, "tools", "posthog_boards.py")
    for frag in ['("88fits · Stages",', "STAGE = \"coalesce(nullIf(toString(properties.stage_id), ''), concat('s', toString(properties.stage)))\"",
                 '("Runs a day, by stage", trend("run_end", "ActionsBar", breakdown="stage_id"))', "When each player first beat each stage"]:
        check(frag in pb, "stools87: posthog_boards.py has %s" % frag[:60])


def checks(check, run_node, server):
    st = _main_module()
    _stage_checks(check, st, server)
    _page_checks(check)
    _sim_checks(check)
    _analytics_checks(check)

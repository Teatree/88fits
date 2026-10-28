"""Pass 110, lane BOSS (the editor half): the boss fight windows (timeline_data.stage_list[k].boss_fight {enabled,
length, max_count, roster}). Garry (2026-10-28): "Just add a 2 minute window in the Timeline where I can set up the cycle
of enemies that will be spawning ... as long as the Boss Fight is continuing it will be those enemies at that pace that
will be spawning."

Groups: model.js's window helpers under Node on hand-made timelines (the block's getters and defaults, the rows open at a
fight second and their shares, the row ids, the windows' own checks with their words, the cycle estimate: waves a cycle,
once a cycle, Max count held, a row's max_alive held, a chance and a presence of 0, no window = null); the page's own
validation (app.js validate, run in a Node vm with util / model / fields / stage_model loaded and the real creature,
elite and power-up lists from server.py): a map without windows carries no window keys and a correct window changes no
other check (no churn), a bad window's errors and warnings, the real red_canyon.json has no error-level issue (Save is not
blocked); the page's words and wiring (FIELDS' "Boss fights" section after the spawn rows, index.html loads
boss_fights.js after timeline.js and its stylesheet, the inspector's window row form and window card, the timeline's
hook, App's window functions).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import copy
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const M = require(process.argv[2]);
const dir = path.dirname(process.argv[2]);
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  // ---- model.js
  const tl = q.tl;
  out.on = [0, 1, 2, 3].map((s) => M.bossFightOn(tl, s));
  out.has = [0, 1, 2, 3].map((s) => M.bossFight(tl, s) != null);
  out.len = [0, 1, 2].map((s) => M.bossFightLen(M.bossFight(tl, s)));
  out.max = [0, 1, 2].map((s) => M.bossFightMax(M.bossFight(tl, s)));
  out.rows = [0, 1, 2].map((s) => M.bossFightRows(M.bossFight(tl, s)).length);
  out.noList = M.bossFightEntry({ stage_length: 300, stages: 3, roster: [] }, 0);
  out.def = M.BOSS_FIGHT_DEF;
  out.fresh = M.newBossFight();
  out.open = q.at.map((ct) => M.bossFightRowsAt(M.bossFight(tl, 0), ct, 600).map((o) => [o.i, Math.round(o.w * 1000) / 1000, o.paced, o.drawn, Math.round(o.norm * 1000) / 1000]));
  out.ends = M.bossFightRows(M.bossFight(tl, 0)).map((r) => M.bossRowEnd(M.bossFight(tl, 0), r));
  out.ids = [M.newBossRowId(tl, 0), M.newBossRowId(tl, 1), M.newBossRowId(tl, 2)];
  out.checksGood = M.bossFightChecks(tl);
  out.checksBad = M.bossFightChecks(q.bad);
  out.cycles = q.cyc.map(([t, s, opts]) => {
    const c = M.bossFightCycle(t, s, q.byId, opts);
    if (!c) return null;
    return { length: c.length, max: c.max, cycles: c.cycles, n: c.alive.length, peak: c.peak, maxAlive: Math.max(...c.alive), full: c.full, spawned: c.spawned,
      rows: c.rows.map((x) => ({ i: x.i, waves: x.waves, spawned: x.spawned, perWave: x.perWave, pace: x.pace })) };
  });
  // ---- the page's validation, in a vm
  const store = {};
  const stub = () => null;
  const ctx = { console, setTimeout, clearTimeout, setInterval, clearInterval, performance: { now: () => Date.now() },
    document: { addEventListener: stub, getElementById: stub, querySelector: stub, querySelectorAll: () => [], createElement: () => ({ style: {}, setAttribute: stub, appendChild: stub, addEventListener: stub }) },
    window: { addEventListener: stub }, location: { search: '', hash: '', pathname: '/' }, history: {},
    localStorage: { getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: (k) => { delete store[k]; } } };
  vm.createContext(ctx);
  for (const f of ['util.js', 'model.js', 'fields.js', 'stage_model.js', 'app.js']) vm.runInContext(fs.readFileSync(path.join(dir, f), 'utf8'), ctx, { filename: f });
  const validate = vm.runInContext(`(function (q) {
    App.S.enemies = q.creatures; App.S.byId = {};
    for (const c of q.creatures) App.S.byId[c.id] = c;
    App.S.elites = q.elites; App.S.pickups = q.pickups;
    const res = {};
    for (const name of Object.keys(q.maps)) {
      const m = JSON.parse(JSON.stringify(q.maps[name]));
      const before = JSON.stringify(m.timeline_data.stage_list);
      Model.normaliseRoster(m.timeline_data);
      App.S.map = m; App.S.tl = m.timeline_data; App.S.sel = null;
      const v = App.validate();
      res[name] = { errors: v.errors, warnings: v.warnings, stageListSame: JSON.stringify(m.timeline_data.stage_list) === before };
    }
    // the App's window functions on a copy (no page: render is a no-op without a map tab element)
    return res;
  })`, ctx);
  out.page = validate(q.page);
  out.fields = vm.runInContext('FIELDS.SECTIONS.map((s) => ({ id: s.id, kind: s.kind, name: s.name, what: s.what, lanes: s.lanes }))', ctx);
  out.appApi = vm.runInContext("['bossBlock', 'bossRows', 'bossRowsAt', 'addBossFight', 'removeBossFight', 'setBossFight', 'newBossRow', 'moveBossRow', 'moveBossRowTo', 'shiftBossRow'].filter((k) => typeof App[k] !== 'function')", ctx);
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def _window(rows, **kw):
    b = {"length": 120, "max_count": 30, "roster": rows}
    b.update(kw)
    return b


def checks(check, run_node, server):
    # ---------------------------------------------------------------- hand-made timelines
    rows0 = [
        {"id": "bf1-1", "t": 0, "enemy": "gob", "weights": [[0, 4], [120, 4]]},
        {"id": "bf1-2", "t": 10, "until": 100, "enemy": "cac", "pace": "waves", "every": 30, "count": 4, "weights": [[10, 1], [100, 1]]},
        {"id": "bf1-3", "t": 60, "enemy": "gob", "pace": "once", "count": 10, "respect_cap": False, "weights": [[60, 1], [120, 1]]},
        {"id": "bf1-4", "t": 30, "until": 90, "enemy": "gob", "weights": [[30, 1], [90, 1]]},
    ]
    tl = {"hard_cap": 500, "spawn_interval": 0.7, "burst_min": 3, "burst_max": 12,
          "roster": [{"id": "r1", "t": 0, "enemy": "gob", "weights": [[0, 1]]}, {"id": "bf1-5", "t": 0, "enemy": "gob", "weights": [[0, 1]]}],
          "stage_list": [
              {"id": "s1", "length": 430, "boss_fight": _window(rows0)},
              {"id": "s2", "length": 600, "boss_fight": {"enabled": False, "roster": [{"id": "bf2-1", "t": 0, "enemy": "gob"}]}},
              {"id": "s3", "length": 780},
          ]}
    bad = {"hard_cap": 100, "stage_list": [
        {"id": "s1", "length": 100, "boss_fight": {"length": 0, "max_count": 2.5, "roster": [
            {"id": "x", "t": 130, "enemy": "gob", "channel": "hell"},
            {"id": "x", "t": 5, "until": 300, "enemy": "gob", "weights": [[-5, 1], [400, 1]]},
            "not a row"]}},
        {"id": "s2", "length": 100, "boss_fight": {"enabled": "yes", "max_count": 900, "roster": []}},
        {"id": "s3", "length": 100, "boss_fight": "nope"},
        {"id": "s4", "length": 100, "boss_fight": {"max_count": 0, "roster": {"not": "a list"}}},
    ]}
    by_id = {"gob": {"id": "gob", "pack_size": 5, "max_alive": 0}, "cac": {"id": "cac", "pack_size": 2, "max_alive": 0},
             "few": {"id": "few", "pack_size": 4, "max_alive": 3}}
    base = {"hard_cap": 500, "spawn_interval": 0.5, "burst_min": 4, "burst_max": 4, "stage_list": [{"id": "s1", "length": 300}]}

    def with_window(b):
        t = copy.deepcopy(base)
        t["stage_list"][0]["boss_fight"] = b
        return t
    cyc = [
        # 0: a waves row every 30 s of 5, off the cap, nobody killed, no Max count: 4 waves a cycle, 20 a cycle
        [with_window({"length": 120, "max_count": -1, "roster": [{"t": 0, "enemy": "gob", "pace": "waves", "every": 30, "count": 5, "respect_cap": False}]}), 0, {"turnover": 0}],
        # 1: a once row of 7 at 0:50: one wave a cycle, three cycles
        [with_window({"length": 100, "max_count": -1, "roster": [{"t": 50, "enemy": "gob", "pace": "once", "count": 7}]}), 0, {"turnover": 0, "cycles": 3}],
        # 2: a continuous row under Max count 25 (the boss counts): never above it
        [with_window({"length": 120, "max_count": 25, "roster": [{"t": 0, "enemy": "gob", "weights": [[0, 3]]}]}), 0, {"turnover": 0.06}],
        # 3: a row's max_alive 3 holds whatever the room
        [with_window({"length": 120, "max_count": -1, "roster": [{"t": 0, "enemy": "few", "pace": "waves", "every": 10, "count": 10}]}), 0, {"turnover": 0}],
        # 4: chance 0.5 halves a wave; a presence of 0 at a wave holds it (waves at 0, 40, 80: the one at 40 held)
        [with_window({"length": 120, "max_count": -1, "roster": [{"t": 0, "enemy": "gob", "pace": "waves", "every": 40, "count": 8, "chance": 0.5, "respect_cap": False, "weights": [[0, 1], [39, 1], [40, 0], [41, 1]]}]}), 0, {"turnover": 0}],
        # 5: a timer row (every [20, 40]): the middle, 30 s: 4 waves a cycle
        [with_window({"length": 120, "max_count": -1, "roster": [{"t": 0, "enemy": "gob", "pace": "waves", "every": [20, 40], "count": 2, "respect_cap": False}]}), 0, {"turnover": 0}],
        # 6: no window
        [copy.deepcopy(base), 0, {}],
        # 7: Max count 10 cuts a wave of 30 to the room (the boss in): 9 the first wave
        [with_window({"length": 60, "max_count": 10, "roster": [{"t": 0, "enemy": "gob", "pace": "once", "count": 30}]}), 0, {"turnover": 0, "cycles": 1}],
    ]
    # the page's validation: the real map as it is, without any window, with a good window, with a bad one, a map with no
    # stage list
    rc = server.load_json(server.map_path("red_canyon"))
    plain = copy.deepcopy(rc)
    for e in plain.get("timeline_data", {}).get("stage_list", []) or []:
        if isinstance(e, dict):
            e.pop("boss_fight", None)
    good = copy.deepcopy(plain)
    gsl = good["timeline_data"]["stage_list"]
    gsl[0]["boss_fight"] = {"length": 120, "max_count": 30, "roster": [
        {"id": "bf1-1", "t": 0, "enemy": "red_goblin", "weights": [[0, 5], [120, 5]], "role": "fodder"},
        {"id": "bf1-2", "t": 20, "enemy": "spit_cactus", "pace": "waves", "every": 40, "count": 2, "weights": [[20, 1], [120, 1]], "role": "ranged"},
        {"id": "bf1-3", "t": 60, "enemy": "red_goblin", "pace": "once", "count": 12, "pattern": "ring", "weights": [[60, 1], [120, 1]], "role": "swarm"}]}
    badm = copy.deepcopy(plain)
    badm["timeline_data"]["stage_list"][1]["boss_fight"] = {"length": 120, "max_count": -3, "roster": [
        {"id": "bf2-1", "t": 30, "until": 20, "enemy": "nobody_at_all"},
        {"id": "bf2-2", "t": 0, "enemy": "red_goblin", "pace": "sometimes"},
        {"id": "bf2-3", "t": 0, "enemy": "red_goblin", "pace": "waves", "every": 30, "offset": 200, "count": 3}]}
    nolist = {"id": "x", "timeline_data": {"stage_length": 300, "stages": 3, "roster": [{"id": "r1", "t": 0, "enemy": "red_goblin", "weights": [[0, 1]]}], "events": []}}
    page = {"creatures": server.list_creatures(), "elites": server.list_elites(), "pickups": server.list_pickups(),
            "maps": {"real": rc, "plain": plain, "good": good, "bad": badm, "nolist": nolist}}
    q = {"tl": tl, "bad": bad, "at": [0, 15, 59.9, 60, 95, 119.9, 120, 200], "byId": by_id, "cyc": cyc, "page": page}
    res = run_node(q, RUNNER)
    if res is None:
        print("BOSS110: node not found: the window checks under Node are skipped")
    elif res:
        # ---------------------------------------------------------------- the block's getters
        check(res["on"] == [True, False, False, False] and res["has"] == [True, True, False, False], "BOSS110: a window is on unless enabled false; none on a stage without one or past the stages: %s %s" % (res["on"], res["has"]))
        check(res["len"] == [120, 120, 120] and res["max"] == [30, 40, 40], "BOSS110: length 120 and Max count 40 when the block leaves them out: %s %s" % (res["len"], res["max"]))
        check(res["rows"] == [4, 1, 0], "BOSS110: the rows of each window: %s" % res["rows"])
        check(res["noList"] is None, "BOSS110: a map without a stage list has no window")
        check(res["def"] == {"length": 120, "max_count": 40} and res["fresh"] == {"length": 120, "max_count": 40, "roster": []}, "BOSS110: a new window is a 2:00 cycle, Max count 40, no rows: %s" % res["fresh"])
        op = dict(zip(q["at"], res["open"]))
        check([x[0] for x in op[0]] == [0] and [x[0] for x in op[15]] == [0, 1], "BOSS110: open at 0:00 the first row, at 0:15 the waves row too: %s %s" % (op[0], op[15]))
        check([x[0] for x in op[60]] == [0, 1, 2, 3] and [x[0] for x in op[95]] == [0, 1, 2] and [x[0] for x in op[119.9]] == [0, 2], "BOSS110: rows open by their t and until on the fight clock: %s / %s / %s" % (op[60], op[95], op[119.9]))
        check(op[120] == [] and op[200] == [], "BOSS110: nothing is open at or past the cycle's end (the cycle starts again at 0:00)")
        sh = {x[0]: x for x in op[60]}
        check(sh[1][3] is False and sh[1][4] == 0 and sh[2][3] is False and abs(sh[0][4] - 0.8) < 1e-9 and abs(sh[3][4] - 0.2) < 1e-9, "BOSS110: the shares are the drawn rows' weights (4 : 1), a waves or once row is not drawn: %s" % op[60])
        check(res["ends"] == [120, 100, 120, 90], "BOSS110: a bar ends at its until, else the cycle's end: %s" % res["ends"])
        check(res["ids"] == ["bf1-6", "bf2-2", "bf3-1"], "BOSS110: a new window row's id is bf<stage>-<n>, used by no window row and no roster row: %s" % res["ids"])
        check(res["checksGood"] == [], "BOSS110: a correct window has no window issue: %s" % res["checksGood"])
        cb = res["checksBad"]
        has = lambda key, level, frag: any(x["key"] == key and x["level"] == level and frag in x["msg"] for x in cb)
        check(has("bossfight:0", "error", "at least 1"), "BOSS110: a cycle shorter than 1 s is an error")
        check(has("bossfight:0", "error", "whole number of creatures"), "BOSS110: a Max count that is not a whole number is an error")
        check(has("bossrow:0:0", "warn", "never spawns"), "BOSS110: a row starting past the cycle's end is warned")
        check(has("bossrow:0:0", "warn", "Channel (hell) means nothing"), "BOSS110: a row's channel is warned as ignored")
        check(has("bossrow:0:1", "error", "used twice"), "BOSS110: a row id used twice in the windows is an error")
        check(has("bossrow:0:1", "warn", "past the cycle's end") and has("bossrow:0:1", "warn", "outside the cycle"), "BOSS110: an until and presence points past the cycle are warned")
        check(has("bossrow:0:2", "error", "must be a block"), "BOSS110: a row that is not a block is an error")
        check(has("bossfight:1", "error", "on or off") and has("bossfight:1", "warn", "above the hard cap") and has("bossfight:1", "warn", "nothing spawns in the fight"), "BOSS110: enabled not a switch, a Max count over the hard cap, an empty window: %s" % [x for x in cb if x["key"] == "bossfight:1"])
        check(has("bossfight:2", "error", "must be a block"), "BOSS110: a boss_fight that is not a block is an error")
        check(has("bossfight:3", "error", "must be a list") and has("bossfight:3", "warn", "Max count 0"), "BOSS110: rows that are not a list, Max count 0")
        # ---------------------------------------------------------------- the cycle estimate
        c = res["cycles"]
        check(c[0]["rows"][0]["waves"] == [4, 4] and [round(v, 6) for v in c[0]["rows"][0]["spawned"]] == [20, 20] and c[0]["n"] == 241, "BOSS110: a waves row every 30 s of 5 brings 4 waves, 20 creatures, every 2:00 cycle (a point a second, two cycles): %s" % c[0])
        check(c[1]["rows"][0]["waves"] == [1, 1, 1] and [round(v, 6) for v in c[1]["spawned"]] == [7, 7, 7], "BOSS110: a once row comes once in every cycle: %s" % c[1]["rows"])
        check(c[2]["maxAlive"] <= 25 + 1e-6 and c[2]["peak"] <= 25 + 1e-6 and c[2]["full"] > 60, "BOSS110: a continuous row fills to Max count (the boss counts) and never past it: peak %s, %s s full" % (c[2]["peak"], c[2]["full"]))
        check(c[3]["maxAlive"] <= 3 + 1 + 1e-6, "BOSS110: a row's max_alive holds (3 of it, the boss beside): %s" % c[3]["maxAlive"])
        check(c[4]["rows"][0]["waves"] == [2, 2] and [round(v, 6) for v in c[4]["rows"][0]["spawned"]] == [8, 8], "BOSS110: a chance of 0.5 halves a wave and a presence of 0 holds one (0:00 and 1:20 come, 0:40 is held): %s" % c[4]["rows"])
        check(c[5]["rows"][0]["waves"] == [4, 4], "BOSS110: every [20, 40] plays its middle, 30 s: %s" % c[5]["rows"])
        check(c[6] is None, "BOSS110: no window, no cycle estimate")
        check(abs(c[7]["spawned"][0] - 9) < 1e-6, "BOSS110: Max count 10 cuts a wave of 30 to the room (9 beside the boss), the rest owed: %s" % c[7]["spawned"])
        # ---------------------------------------------------------------- the page's validation
        pg = res["page"]
        keys = lambda name, level: [x["key"] for x in pg[name]["errors" if level == "error" else "warnings"]]
        boss_keys = lambda name: [k for k in keys(name, "error") + keys(name, "warn") if k.startswith(("bossfight:", "bossrow:"))]
        check(not boss_keys("plain") and not boss_keys("nolist"), "BOSS110: a map without windows carries no window issue (no churn): %s" % (boss_keys("plain") + boss_keys("nolist")))
        check(pg["plain"]["stageListSame"] and pg["good"]["stageListSame"] and pg["real"]["stageListSame"], "BOSS110: loading leaves the stage list and its windows as the file has them")
        strip = lambda name: sorted("%s|%s" % (x["key"], x["msg"]) for x in pg[name]["errors"] + pg[name]["warnings"] if not x["key"].startswith(("bossfight:", "bossrow:")))
        check(strip("plain") == strip("good"), "BOSS110: a correct window changes no other check of the map")
        check(not [x for x in pg["good"]["errors"] if x["key"].startswith(("bossfight:", "bossrow:"))], "BOSS110: a correct window on Red Canyon has no error: %s" % [x for x in pg["good"]["errors"]][:4])
        bk = {(x["key"], x["msg"]) for x in pg["bad"]["errors"]}
        bw = {(x["key"], x["msg"]) for x in pg["bad"]["warnings"]}
        check(any(k == "bossrow:1:0" and "unknown creature" in m for k, m in bk), "BOSS110: a window row runs the roster row's checks: an unknown creature is an error")
        check(any(k == "bossrow:1:0" and "is not after t" in m for k, m in bk), "BOSS110: a window row's until before its t is an error")
        check(any(k == "bossrow:1:1" and "unknown pacing" in m for k, m in bk), "BOSS110: a window row's unknown pacing is an error")
        check(any(k == "bossrow:1:2" and "cycle's end" in m for k, m in bw), "BOSS110: a waves row whose first wave is past the cycle's end is warned")
        check(any(k == "bossfight:1" and "whole number" in m for k, m in bk), "BOSS110: a Max count under -1 is an error")
        real_err = pg["real"]["errors"]
        check(not real_err, "BOSS110: the real red_canyon.json has no error-level issue (Save is not blocked): %s" % real_err[:4])
        nwin = sum(1 for e in (rc.get("timeline_data", {}).get("stage_list") or []) if isinstance(e, dict) and isinstance(e.get("boss_fight"), dict))
        nrows = sum(len(e["boss_fight"].get("roster") or []) for e in (rc.get("timeline_data", {}).get("stage_list") or []) if isinstance(e, dict) and isinstance(e.get("boss_fight"), dict))
        print("BOSS110: red_canyon.json has %d boss fight windows, %d rows; %d warnings on them" % (nwin, nrows, len([x for x in pg["real"]["warnings"] if x["key"].startswith(("bossfight:", "bossrow:"))])))
        # ---------------------------------------------------------------- fields.js, App
        secs = [s["id"] for s in res["fields"]]
        bf = [s for s in res["fields"] if s["id"] == "bossfight"]
        check("bossfight" in secs and secs.index("bossfight") == secs.index("rows") + 1, "BOSS110: FIELDS has the Boss fights section right after the spawn rows: %s" % secs)
        check(bf and bf[0]["kind"] == "edit" and bf[0]["name"] == "Boss fights" and bf[0]["lanes"] == [] and len(bf[0]["what"]) > 40, "BOSS110: the section is an editing one with its words")
        check(res["appApi"] == [], "BOSS110: App has the window functions: missing %s" % res["appApi"])
    # ---------------------------------------------------------------- the page's files and words
    idx = _read("index.html")
    a, b2 = idx.find('src="timeline.js"'), idx.find('src="boss_fights.js"')
    check(0 < a < b2, "BOSS110: index.html loads boss_fights.js after timeline.js")
    check('href="boss_fights.css"' in idx, "BOSS110: index.html links boss_fights.css")
    bfj = _read("boss_fights.js")
    for frag in ["Add a boss fight window", "Max count", "counted as bodies", "Remove window", "the cycle starts again", "fight clock (0:00 = the boss arrives)", "estimate: alive over two cycles", "still draw a boss fight without its window"]:
        check(frag in bfj, "BOSS110: boss_fights.js says \"%s\"" % frag)
    ins = _read("inspector.js")
    for frag in ["function bossEnv(", "function bossFightForm(", "function bossPaceNote(", "function bossCycleNote(", "Boss fight row", "Once a cycle: ", "Channel: none in a boss fight window"]:
        check(frag in ins, "BOSS110: inspector.js has %s" % frag)
    tlj = _read("timeline.js")
    check("BossFights.render(bfHost)" in tlj and "BossFights.summary()" in tlj and "sel.kind === 'bossrow'" in tlj, "BOSS110: timeline.js draws the section, its summary and scrolls to a window row")
    app = _read("app.js")
    for frag in ["s.kind === 'bossrow'", "bossrow:${s.s}:${s.i}", "M.bossFightChecks(d)", "rowChecks(r, `bossrow:${w.i}:${i}`"]:
        check(frag in app, "BOSS110: app.js has %s" % frag)
    doc = _read(os.path.join("..", "..", "docs", "level_editor.md"))
    check("## Pass 110: boss fight windows" in doc, "BOSS110: docs/level_editor.md has its Pass 110 section")

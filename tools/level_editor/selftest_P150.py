"""Pass 150, lane EDITOR: the Endless windows (timeline_data.stage_list[k].endless_window {enabled, length, max_count,
max_count_growth, roster}) and every spawn row's variation tabs (`variations`: [{percent, ...a full copy of the row's own
keys}]). Garry (2026-11-14): "For Endless Mode specifically I want similar type of Controls as the Boss Fights has. Add
another section underneath 'Boss fights' and allow for adding enemy rows there as many as I like ... For All of enemy
rows, make the selected row section 25% wider and add ability to add tabs at the top. Each tab represents a variation of
the enemies that this node will spawn. Each tab shows the % probability of that variations spawning. Each tab, when
created by default has 50% probability and the From and Until numbers marked yellow as they are (inherited) from the
original, meaning if I change those it changes for all variations. All other parameters can be adjusted as User wants.
When creating a new tab it always copies all data from the original. Tabs can be removed, Original cannot."

Groups: model.js under Node (the variation maths: the tabs' shares, a tab's merged row, a new tab's copy, the share set
with the others scaled, removing a tab, the variation view routing the shared keys to the original, the checks, the
estimates' expansion; the Endless window: its getters and defaults, Max count growing a cycle under the hard cap, rows by
cycle, the checks with their words, row ids, the cycle estimate with growth, from / until cycle and variations; the boss
fight window unchanged); the page in a vm (app.js validate on the real map, a good and a bad map; the App's tab actions on
a row: + Variation, the share box, ×, a re-selected row keeping its tab, Delete / Duplicate of an Endless row; tidy on
Save); the page's words and wiring (the Endless section under Boss fights, From / Until cycle on window rows only, the
bite slow rows, the wider inspector, the factory in boss_fights.js, the inspector's tabs and window card).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import copy
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
  const r1 = () => JSON.parse(JSON.stringify(q.row));
  // ---- the variation maths
  out.noTabs = M.variationPercents(r1());
  let r = r1();
  out.tab1 = M.addVariation(r);
  out.afterAdd1 = { pct: M.variationPercents(r), v: JSON.parse(JSON.stringify(r.variations[0])), keys: Object.keys(r.variations[0]) };
  out.tab2 = M.addVariation(r);
  out.afterAdd2 = M.variationPercents(r);
  M.setVariationPercent(r, 0, 10);
  out.setOrig10 = { pct: M.variationPercents(r), stored: r.variations.map((v) => v.percent) };
  M.setVariationPercent(r, 1, 33.33);
  out.setV1 = { pct: M.variationPercents(r), stored: r.variations.map((v) => v.percent) };
  M.setVariationPercent(r, 2, 100);
  out.setV2all = { pct: M.variationPercents(r), stored: r.variations.map((v) => v.percent) };
  M.setVariationPercent(r, 0, 40);
  out.origFromZero = { pct: M.variationPercents(r), stored: r.variations.map((v) => v.percent) };
  // the rounding never takes the variations past 100
  const rr = r1(); M.addVariation(rr); M.addVariation(rr); M.addVariation(rr);
  const sums = [];
  for (const p of [33.33, 12.34, 66.66, 99.95, 0.04, 50.05]) { M.setVariationPercent(rr, 2, p); sums.push(Math.round(rr.variations.reduce((a, v) => a + v.percent, 0) * 1000) / 1000); }
  out.sums = sums;
  out.over = M.variationPercents({ enemy: 'a', variations: [{ percent: 80, enemy: 'b' }, { percent: 60, enemy: 'c' }] });
  out.neg = M.variationPercents({ enemy: 'a', variations: [{ percent: -20, enemy: 'b' }] });
  // a tab's merged row
  r = r1(); M.addVariation(r);
  r.variations[0].enemy = 'cac'; r.variations[0].variant = 'SC-A'; delete r.variations[0].stats; r.variations[0].elite = 'random';
  r.variations[0].t = 999; r.variations[0].until = 5;   // shared keys in a variation are ignored
  out.merged = M.variationRow(r, 1);
  out.merged0 = M.variationRow(r, 0) === r;
  out.mergedNone = M.variationRow(r, 5);
  // the variation view: own keys on the variation, shared keys on the original
  r = r1(); M.addVariation(r);
  const v = M.variationView(r, 1);
  v.enemy = 'cac'; v.t = 20; v.stats.hp = 9; delete v.until; v.every = 45; v.weights = [[20, 2]]; v.pack = 7;
  out.view = { origT: r.t, origUntil: r.until === undefined, origEnemy: r.enemy, origEvery: r.every, origWeights: r.weights, origPack: r.pack === undefined,
    varEnemy: r.variations[0].enemy, varHp: r.variations[0].stats.hp, origHp: r.stats.hp, varPack: r.variations[0].pack, varHasT: 't' in r.variations[0],
    viewT: v.t, viewEnemy: v.enemy, viewPercent: v.percent === undefined, inPattern: 'pattern' in v, inWeights: 'weights' in v,
    keys: Object.keys(v).sort(), json: JSON.parse(JSON.stringify(v)), of: v.__variationOf === r, tab: v.__variationTab };
  out.viewNone = M.variationView(r, 3);
  // remove a tab: its share goes back to the original; the last one takes the key away
  r = r1(); M.addVariation(r); M.addVariation(r);
  M.removeVariation(r, 1);
  out.removed1 = { pct: M.variationPercents(r), n: r.variations.length };
  out.removeOrig = M.removeVariation(r, 0);
  M.removeVariation(r, 1);
  out.removedAll = 'variations' in r;
  // the checks
  out.checks = q.badVars.map((x) => M.variationChecks(x));
  // tidy on save
  const td = { enemy: 'a', variations: [{ percent: 10, enemy: 'b', t: 5, until: 9, weights: [[0, 1]], id: 'x' }] };
  M.tidyVariations(td);
  out.tidy = td.variations[0];
  // the estimates' rows
  out.expand = M.expandVariations(q.expand).map((x) => ({ i: x.i, tab: x.tab, share: Math.round(x.share * 1000) / 1000, enemy: x.r.enemy, chance: x.r.chance, weights: x.r.weights, count: x.r.count, variations: 'variations' in x.r }));
  // ---- the Endless window
  const tl = q.tl;
  out.on = [0, 1, 2, 3].map((s) => M.windowOn(tl, s, 'endless'));
  out.len = [0, 1, 2].map((s) => M.windowLen(M.windowBlock(tl, s, 'endless'), 'endless'));
  out.max = [0, 1, 2].map((s) => M.windowMax(M.windowBlock(tl, s, 'endless'), 'endless'));
  out.growth = [0, 1].map((s) => M.windowGrowth(M.windowBlock(tl, s, 'endless'), 'endless'));
  out.bossGrowth = M.windowGrowth({ max_count: 10, max_count_growth: 5 }, 'boss');
  out.maxAt = [0, 1, 2, 3, 10].map((c) => M.windowMaxAt(M.windowBlock(tl, 0, 'endless'), 'endless', c, tl.hard_cap));
  out.maxAtNone = M.windowMaxAt({ max_count: -1, max_count_growth: 9 }, 'endless', 3, 500);
  out.fresh = M.newWindow('endless');
  out.freshBoss = M.newWindow('boss');
  out.def = M.ENDLESS_WINDOW_DEF;
  out.kinds = { boss: M.windowKind('boss').key, endless: M.windowKind('endless').key, unknown: M.windowKind('x').kind };
  out.bossStill = { block: M.bossFight(tl, 0) != null, endless: M.windowBlock(tl, 0, 'boss') != null };
  out.ids = [M.newBossRowId(tl, 0, 'endless'), M.newBossRowId(tl, 1, 'endless'), M.newBossRowId(tl, 0, 'boss'), M.newBossRowId(tl, 0)];
  out.cyc = q.cycleRows.map((x) => [M.rowCycles(x), [1, 2, 3, 4].map((c) => M.rowInCycle(x, c))]);
  out.open = [1, 2, 3].map((c) => M.windowRowsAt(M.windowBlock(tl, 0, 'endless'), 10, 600, 'endless', c).map((o) => o.i));
  out.openAny = M.windowRowsAt(M.windowBlock(tl, 0, 'endless'), 10, 600, 'endless').map((o) => o.i);
  out.cycleIssues = q.cycleRows.map((x) => M.cycleKeyIssues(x));
  out.checksGood = M.windowChecks(tl, 'endless');
  out.checksBad = M.windowChecks(q.bad, 'endless');
  out.bossChecksBad = M.windowChecks(q.bad, 'boss');
  out.cycles = q.cyc.map(([t, s, opts, kind]) => {
    const c = M.windowCycle(t, s, q.byId, opts, kind);
    if (!c) return null;
    return { length: c.length, max: c.max, maxBy: c.maxBy, cycles: c.cycles, n: c.alive.length, peak: c.peak, maxAlive: Math.max(...c.alive), spawned: c.spawned,
      rows: c.rows.map((x) => ({ i: x.i, waves: x.waves, spawned: x.spawned, pace: x.pace })) };
  });
  // ---- the page in a vm
  const store = {};
  const stub = () => null;
  const fake = () => new Proxy(function () {}, {
    get(t, k) {
      if (k === 'style' || k === 'dataset') return {};
      if (k === 'classList') return { add() {}, remove() {}, toggle() {}, contains() { return false; } };
      if (k === Symbol.toPrimitive) return () => '';
      if (k === 'then') return undefined;
      return fake();
    },
    set() { return true; },
    apply() { return fake(); },
  });
  const ctx = { console, setTimeout, clearTimeout, setInterval, clearInterval, performance: { now: () => Date.now() }, Proxy, Reflect,
    document: { addEventListener: stub, getElementById: () => fake(), querySelector: () => null, querySelectorAll: () => [], createElement: () => fake(), createElementNS: () => fake(), createTextNode: () => fake(), body: fake() },
    window: { addEventListener: stub, removeEventListener: stub }, location: { search: '', hash: '', pathname: '/' }, history: {},
    localStorage: { getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: (k) => { delete store[k]; } } };
  vm.createContext(ctx);
  for (const f of ['util.js', 'model.js', 'fields.js', 'stage_model.js', 'app.js']) vm.runInContext(fs.readFileSync(path.join(dir, f), 'utf8'), ctx, { filename: f });
  vm.runInContext('var Timeline = { render() {}, scrollToSelection() {}, viewCenter() { return 0; } }; var Inspector = { render() {}, live() {} };', ctx);
  const page = vm.runInContext(`(function (q) {
    App.S.enemies = q.creatures; App.S.byId = {};
    for (const c of q.creatures) App.S.byId[c.id] = c;
    App.S.elites = q.elites; App.S.pickups = q.pickups;
    const res = {};
    for (const name of Object.keys(q.maps)) {
      const m = JSON.parse(JSON.stringify(q.maps[name]));
      Model.normaliseRoster(m.timeline_data);
      App.S.map = m; App.S.tl = m.timeline_data; App.S.sel = null;
      const v = App.validate();
      res[name] = { errors: v.errors, warnings: v.warnings };
    }
    // the App's tab actions on the good map's first roster row and its Endless row
    const m = JSON.parse(JSON.stringify(q.maps.good));
    delete m.timeline_data.roster[0].variations;
    App.S.map = m; App.S.tl = m.timeline_data; App.S.tab = 'timeline'; App.S.history = []; App.S.future = [];
    const acts = {};
    App.S.sel = { kind: 'roster', i: 0 };
    acts.tab0 = App.selTab();
    App.addRowVariation();
    acts.afterAdd = { sel: Object.assign({}, App.S.sel), tab: App.selTab(), pct: Model.variationPercents(App.selected()), history: App.S.history.length };
    App.setRowVariationPercent(1, 20);
    acts.afterPct = Model.variationPercents(App.selected());
    App.select({ kind: 'roster', i: 0 });
    acts.reselect = App.selTab();
    App.select({ kind: 'roster', i: 1 });
    acts.other = App.selTab();
    App.select({ kind: 'roster', i: 0, v: 1 });
    App.selectTab(0);
    acts.toOrig = App.selTab();
    App.selectTab(1);
    App.addRowVariation();
    acts.second = { tab: App.selTab(), pct: Model.variationPercents(App.selected()) };
    App.removeRowVariation(1);
    acts.removed = { tab: App.selTab(), n: Model.variationList(App.selected()).length, pct: Model.variationPercents(App.selected()) };
    App.removeRowVariation(1);
    acts.allGone = { tab: App.selTab(), has: 'variations' in App.selected(), sel: Object.assign({}, App.S.sel) };
    App.undo();
    acts.undone = Model.variationList(App.selected()).length;
    // an Endless row: + Row, select, duplicate, delete, nudge
    const before = App.winRows('endless', 0).length;
    App.newWindowRow('endless', 0, 'waves', 12);
    acts.newRow = { n: App.winRows('endless', 0).length - before, sel: Object.assign({}, App.S.sel), row: App.selected() };
    App.duplicateSelected();
    acts.dup = { n: App.winRows('endless', 0).length - before, id: App.selected().id, sel: Object.assign({}, App.S.sel) };
    App.nudge(5);
    acts.nudged = App.selected().t;
    App.deleteSelected();
    acts.deleted = App.winRows('endless', 0).length - before;
    App.setWindow('endless', 0, 'max_count_growth', 15);
    acts.growth = Model.windowBlock(App.tl(), 0, 'endless').max_count_growth;
    App.addWindow('endless', 2);
    acts.added = Model.windowBlock(App.tl(), 2, 'endless');
    App.removeWindow('endless', 2);
    acts.removedWin = Model.windowBlock(App.tl(), 2, 'endless');
    acts.selKey = (App.S.sel = { kind: 'endlessrow', s: 0, i: 0 }, App.selKey());
    acts.selItem = App.selected() === App.winRows('endless', 0)[0];
    acts.cardKey = (App.S.sel = { kind: 'endless', s: 0 }, App.selKey());
    acts.cardNone = (App.S.sel = { kind: 'endless', s: 2 }, App.selected());
    res.acts = acts;
    return res;
  })`, ctx)(q.page);
  out.page = page;
  out.fields = vm.runInContext('FIELDS.SECTIONS.map((s) => s.id)', ctx);
  out.endlessSection = vm.runInContext("FIELDS.SECTIONS.find((s) => s.id === 'endless')", ctx);
  out.cycleFields = vm.runInContext("FIELDS.roster.filter((d) => d.key === 'from_cycle' || d.key === 'until_cycle').map((d) => ({ key: d.key, window: d.window, type: d.type }))", ctx);
  out.biteRows = vm.runInContext("FIELDS.SCALARS.filter((d) => d.key.indexOf('bite_slow.') === 0).map((d) => ({ key: d.key, def: d.def, group: d.group }))", ctx);
  out.appApi = vm.runInContext("['winBlock', 'winRows', 'winRowsAt', 'addWindow', 'removeWindow', 'setWindow', 'newWindowRow', 'moveWindowRow', 'moveWindowRowTo', 'shiftWindowRow', 'isRowSel', 'selTab', 'selectTab', 'addRowVariation', 'removeRowVariation', 'setRowVariationPercent', 'bossBlock', 'bossRows', 'addBossFight', 'newBossRow'].filter((k) => typeof App[k] !== 'function')", ctx);
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def checks(check, run_node, server):
    row = {"id": "r1", "t": 10, "until": 100, "enemy": "gob", "variant": "G-A", "weights": [[10, 5], [100, 5]], "pace": "waves",
           "every": 30, "count": 6, "stats": {"hp": 5}, "pattern": "ring", "role": "fodder", "chance": 0.5, "offset": 2}
    bad_vars = [
        {"enemy": "a", "variations": "nope"},
        {"enemy": "a", "variations": [{"percent": "ten", "enemy": "b"}, {"percent": -5, "enemy": "c"}, "x", {"percent": 10}, {"percent": 10, "enemy": "d", "t": 4, "until": 9}]},
        {"enemy": "a", "variations": [{"percent": 70, "enemy": "b"}, {"percent": 50, "enemy": "c"}]},
        {"enemy": "a", "variations": [{"percent": 50, "enemy": "b"}]},
    ]
    expand = [
        {"t": 0, "enemy": "a", "weights": [[0, 4], [60, 8]], "variations": [{"percent": 25, "enemy": "b"}]},
        {"t": 0, "enemy": "c", "pace": "once", "count": 5, "chance": 0.8, "variations": [{"percent": 50, "enemy": "d", "count": 2}]},
        {"t": 0, "enemy": "e", "weights": [[0, 1]]},
        {"t": 0, "enemy": "f", "variations": [{"percent": 100, "enemy": "g"}]},
    ]
    erows = [
        {"id": "en1-1", "t": 0, "enemy": "gob", "weights": [[0, 4], [180, 4]]},
        {"id": "en1-2", "t": 0, "enemy": "gob", "pace": "once", "count": 30, "until_cycle": 1, "weights": [[0, 1], [180, 1]]},
        {"id": "en1-3", "t": 5, "enemy": "cac", "pace": "waves", "every": 30, "count": 3, "from_cycle": 2, "weights": [[5, 1], [180, 1]]},
        {"id": "en1-4", "t": 0, "enemy": "gob", "from_cycle": 2, "until_cycle": 3, "weights": [[0, 1], [180, 1]]},
    ]
    tl = {"hard_cap": 130, "spawn_interval": 0.5, "burst_min": 4, "burst_max": 4,
          "roster": [{"id": "r1", "t": 0, "enemy": "gob", "weights": [[0, 1]]}],
          "stage_list": [
              {"id": "s1", "length": 430, "endless_window": {"length": 180, "max_count": 60, "max_count_growth": 25, "roster": erows},
               "boss_fight": {"length": 120, "max_count": 30, "roster": [{"id": "bf1-1", "t": 0, "enemy": "gob"}]}},
              {"id": "s2", "length": 600, "endless_window": {"enabled": False, "roster": [{"id": "en2-1", "t": 0, "enemy": "gob"}]}},
              {"id": "s3", "length": 780},
          ]}
    cycle_rows = [{}, {"from_cycle": 2}, {"until_cycle": 1}, {"from_cycle": 2, "until_cycle": 3}, {"from_cycle": 0}, {"until_cycle": 1.5},
                  {"from_cycle": 3, "until_cycle": 2}]
    bad = {"hard_cap": 100, "stage_list": [
        {"id": "s1", "length": 100, "endless_window": {"length": 0, "max_count": 2.5, "max_count_growth": -3, "roster": [
            {"id": "x", "t": 200, "enemy": "gob", "channel": "hell", "from_cycle": 0},
            {"id": "x", "t": 5, "until": 300, "enemy": "gob", "until_cycle": 1, "from_cycle": 2},
            "not a row"]},
         "boss_fight": {"length": 60, "max_count": 10, "max_count_growth": 4, "roster": [{"id": "b1", "t": 0, "enemy": "gob"}]}},
        {"id": "s2", "length": 100, "endless_window": {"enabled": "yes", "max_count": 900, "roster": []}},
        {"id": "s3", "length": 100, "endless_window": "nope"},
        {"id": "s4", "length": 100, "endless_window": {"max_count": 0, "max_count_growth": 10, "roster": [{"t": 0, "enemy": "gob"}]}},
    ]}
    by_id = {"gob": {"id": "gob", "pack_size": 5, "max_alive": 0}, "cac": {"id": "cac", "pack_size": 2, "max_alive": 0}}
    base = {"hard_cap": 500, "spawn_interval": 0.5, "burst_min": 4, "burst_max": 4, "stage_list": [{"id": "s1", "length": 300}]}

    def with_endless(b, boss=None):
        t = copy.deepcopy(base)
        t["stage_list"][0]["endless_window"] = b
        if boss is not None:
            t["stage_list"][0]["boss_fight"] = boss
        return t
    cyc = [
        # 0: a once row of 10 a cycle, three cycles, nobody killed, no Max count: 10 a cycle
        [with_endless({"length": 60, "max_count": -1, "roster": [{"t": 0, "enemy": "gob", "pace": "once", "count": 10}]}), 0, {"turnover": 0}, "endless"],
        # 1: Max count 20 growing 15 a cycle, a continuous row and nobody killed: the crowd steps up 20, 35, 50
        [with_endless({"length": 60, "max_count": 20, "max_count_growth": 15, "roster": [{"t": 0, "enemy": "gob", "weights": [[0, 3]]}]}), 0, {"turnover": 0}, "endless"],
        # 2: the growth never past the hard cap (500 bodies): 400, 490, 500, 500
        [with_endless({"length": 30, "max_count": 400, "max_count_growth": 90, "roster": [{"t": 0, "enemy": "gob", "pace": "once", "count": 5}]}), 0, {"turnover": 0, "cycles": 4}, "endless"],
        # 3: from cycle 2 / until cycle 1: the opening wave only in cycle 1, the waves row from cycle 2
        [with_endless({"length": 60, "max_count": -1, "roster": [{"t": 0, "enemy": "gob", "pace": "once", "count": 30, "until_cycle": 1},
                                                                  {"t": 0, "enemy": "cac", "pace": "waves", "every": 20, "count": 2, "from_cycle": 2}]}), 0, {"turnover": 0}, "endless"],
        # 4: a once row of 10 with a 30% variation of 20: 0.7 x 10 + 0.3 x 20 = 13 a cycle, one entry for the row
        [with_endless({"length": 60, "max_count": -1, "roster": [{"t": 0, "enemy": "gob", "pace": "once", "count": 10, "respect_cap": False,
                                                                   "variations": [{"percent": 30, "enemy": "cac", "pace": "once", "count": 20}]}]}), 0, {"turnover": 0}, "endless"],
        # 5: no Endless window
        [copy.deepcopy(base), 0, {}, "endless"],
        # 6: the boss fight window by the same function: the boss counts as a body (Max count 10, a wave of 30: 9 come)
        [with_endless({"length": 60, "roster": []}, {"length": 60, "max_count": 10, "roster": [{"t": 0, "enemy": "gob", "pace": "once", "count": 30}]}), 0, {"turnover": 0, "cycles": 1}, "boss"],
        # 7: an Endless window with the same row: no boss, all 10 come
        [with_endless({"length": 60, "max_count": 10, "roster": [{"t": 0, "enemy": "gob", "pace": "once", "count": 30}]}), 0, {"turnover": 0, "cycles": 1}, "endless"],
    ]
    # the page: the real map as it is, without any Endless window or variation, with good ones, with bad ones
    rc = server.load_json(server.map_path("red_canyon"))
    plain = copy.deepcopy(rc)
    td = plain.get("timeline_data", {})
    for e in td.get("stage_list", []) or []:
        if isinstance(e, dict):
            e.pop("endless_window", None)
            for blk in ("boss_fight",):
                if isinstance(e.get(blk), dict):
                    for r in e[blk].get("roster", []) or []:
                        if isinstance(r, dict):
                            r.pop("variations", None)
    for r in td.get("roster", []) or []:
        if isinstance(r, dict):
            r.pop("variations", None)
    good = copy.deepcopy(plain)
    gtd = good["timeline_data"]
    gtd["roster"][0]["variations"] = [{"percent": 30, "enemy": "goblin_runt", "variant": "RUN-B", "elite": "speedy"}]
    gsl = gtd["stage_list"]
    gsl[0]["endless_window"] = {"length": 180, "max_count": 80, "max_count_growth": 20, "roster": [
        {"id": "en1-1", "t": 0, "enemy": "red_goblin", "weights": [[0, 5], [180, 5]], "role": "fodder",
         "variations": [{"percent": 25, "enemy": "goblin_runt", "variant": "RUN-B", "role": "fodder"}]},
        {"id": "en1-2", "t": 30, "enemy": "spit_cactus", "pace": "waves", "every": 40, "count": 2, "weights": [[30, 1], [180, 1]], "role": "ranged", "from_cycle": 2},
        {"id": "en1-3", "t": 60, "enemy": "red_goblin", "pace": "once", "count": 40, "pattern": "ring", "ring_radius": 16, "weights": [[60, 1], [180, 1]], "role": "swarm", "until_cycle": 1}]}
    badm = copy.deepcopy(plain)
    btd = badm["timeline_data"]
    btd["roster"][0]["variations"] = [{"percent": 80, "enemy": "nobody_at_all"}, {"percent": 40, "variant": "RUN-B"}, {"percent": 5, "enemy": "goblin_runt", "variant": "NOPE-Z"}]
    btd["roster"][1]["from_cycle"] = 2
    btd["stage_list"][1]["endless_window"] = {"length": 120, "max_count": -3, "roster": [
        {"id": "en2-1", "t": 30, "until": 20, "enemy": "nobody_at_all"},
        {"id": "en2-2", "t": 0, "enemy": "red_goblin", "pace": "sometimes", "from_cycle": "two"}]}
    page = {"creatures": server.list_creatures(), "elites": server.list_elites(), "pickups": server.list_pickups(),
            "maps": {"real": rc, "plain": plain, "good": good, "bad": badm}}
    q = {"row": row, "badVars": bad_vars, "expand": expand, "tl": tl, "cycleRows": cycle_rows, "bad": bad, "byId": by_id, "cyc": cyc, "page": page}
    res = run_node(q, RUNNER)
    if res is None:
        print("P150: node not found: the variation and Endless window checks under Node are skipped")
    elif res:
        # ---------------------------------------------------------------- the variation maths
        check(res["noTabs"] == [100], "P150: a row without tabs is the Original at 100%%: %s" % res["noTabs"])
        a1 = res["afterAdd1"]
        check(res["tab1"] == 1 and a1["pct"] == [50, 50], "P150: + Variation makes tab 1 at 50%%, the Original 50%%: %s" % a1)
        check(a1["keys"][0] == "percent" and a1["v"] == {"percent": 50, "enemy": "gob", "variant": "G-A", "count": 6, "stats": {"hp": 5}, "pattern": "ring", "role": "fodder"},
              "P150: a new tab copies every own key of the Original (none of the shared ones), percent first: %s" % a1["v"])
        check(res["tab2"] == 2 and res["afterAdd2"] == [25, 25, 50], "P150: a second tab gets 50%%, the others scaled to the other 50: %s" % res["afterAdd2"])
        so = res["setOrig10"]
        check(so["pct"][0] == 10 and so["stored"] == [30, 60], "P150: the Original set to 10%%: the variations keep their ratio (25 : 50 -> 30 : 60): %s" % so)
        s1 = res["setV1"]
        check(s1["stored"][0] == 33.3 and abs(sum(s1["pct"]) - 100) < 1e-6 and abs(s1["pct"][0] / s1["pct"][2] - 10 / 60) < 0.01, "P150: a variation set to 33.33%% stores 33.3, the others scaled together: %s" % s1)
        s2 = res["setV2all"]
        check(s2["stored"] == [0, 100] and s2["pct"][0] == 0, "P150: a tab set to 100%% leaves 0 to the others: %s" % s2)
        of = res["origFromZero"]
        check(of["pct"][0] == 40 and of["stored"] == [0, 60], "P150: the Original raised from 0 takes its share from the others in their ratio: %s" % of)
        check(all(x <= 100.0 + 1e-9 for x in res["sums"]), "P150: the stored percents never add up past 100 after rounding: %s" % res["sums"])
        check([round(x, 3) for x in res["over"]] == [0, 57.143, 42.857], "P150: variations past 100 are scaled to 100, the Original 0: %s" % res["over"])
        check(res["neg"] == [100, 0], "P150: a negative percent counts as 0: %s" % res["neg"])
        m = res["merged"]
        check(m["enemy"] == "cac" and m["variant"] == "SC-A" and m["elite"] == "random" and "stats" not in m and "percent" not in m,
              "P150: a tab's row is the variation's keys (a key it lacks it lacks, no percent): %s" % m)
        check(m["t"] == 10 and m["until"] == 100 and m["pace"] == "waves" and m["every"] == 30 and m["weights"] == [[10, 5], [100, 5]] and m["chance"] == 0.5 and m["offset"] == 2 and m["id"] == "r1",
              "P150: a tab's row takes every shared key from the Original, whatever the variation says: %s" % m)
        check(res["merged0"] is True and res["mergedNone"] is None, "P150: tab 0 is the row itself, a missing tab nothing")
        vw = res["view"]
        check(vw["origT"] == 20 and vw["origUntil"] and vw["origEvery"] == 45 and vw["origWeights"] == [[20, 2]] and vw["varHasT"] is False,
              "P150: in a variation's tab From, Until, Every and the presence write to the Original: %s" % vw)
        check(vw["origEnemy"] == "gob" and vw["varEnemy"] == "cac" and vw["varHp"] == 9 and vw["origHp"] == 5 and vw["varPack"] == 7 and vw["origPack"],
              "P150: in a variation's tab its own keys write to the variation only: %s" % vw)
        check(vw["viewT"] == 20 and vw["viewEnemy"] == "cac" and vw["viewPercent"] and vw["inPattern"] and vw["inWeights"] and vw["of"] and vw["tab"] == 1,
              "P150: the tab's view reads the shared keys from the Original and hides percent: %s" % vw)
        check("percent" not in vw["json"] and vw["json"]["t"] == 20 and vw["json"]["enemy"] == "cac" and "until" not in vw["json"], "P150: the view's JSON is the tab's row: %s" % vw["json"])
        check(res["viewNone"] is None, "P150: no view for a tab that is not there")
        check(res["removed1"] == {"pct": [50, 50], "n": 1}, "P150: removing a tab gives its share back to the Original: %s" % res["removed1"])
        check(res["removeOrig"] is False and res["removedAll"] is False, "P150: the Original cannot be removed; the last tab gone takes `variations` away")
        ch = res["checks"]
        has = lambda k, level, frag: any(x["level"] == level and frag in x["msg"] for x in ch[k])
        check(has(0, "error", "must be a list"), "P150: variations that is not a list is an error: %s" % ch[0])
        check(has(1, "error", "Variation 1: its % is not a number") and has(1, "error", "Variation 2: a negative %") and has(1, "error", "Variation 3 is not a block")
              and has(1, "error", "Variation 4 has no creature") and has(1, "warn", "Variation 5 holds t, until"), "P150: a tab's own errors and a shared key in a tab: %s" % ch[1])
        check(has(2, "warn", "add up to 120%"), "P150: tabs past 100%% warn: %s" % ch[2])
        check(ch[3] == [], "P150: a correct tab has no variation issue: %s" % ch[3])
        check(res["tidy"] == {"percent": 10, "enemy": "b"}, "P150: Save drops the shared keys a tab was given by hand: %s" % res["tidy"])
        ex = res["expand"]
        check([(x["i"], x["tab"], x["share"]) for x in ex] == [(0, 0, 0.75), (0, 1, 0.25), (1, 0, 0.5), (1, 1, 0.5), (2, 0, 1), (3, 1, 1)],
              "P150: the estimates play one row per tab with a share above 0, tied to its parent: %s" % [(x["i"], x["tab"], x["share"]) for x in ex])
        check(ex[0]["weights"] == [[0, 3], [60, 6]] and ex[1]["weights"] == [[0, 1], [60, 2]] and ex[1]["enemy"] == "b", "P150: a drawn row's tabs split its presence by their shares: %s" % ex[:2])
        check(abs(ex[2]["chance"] - 0.4) < 1e-9 and abs(ex[3]["chance"] - 0.4) < 1e-9 and ex[3]["count"] == 2 and ex[3]["enemy"] == "d", "P150: a paced row's tabs split its waves by chance: %s" % ex[2:4])
        check(ex[4].get("chance") is None and ex[4]["weights"] == [[0, 1]] and not any(x["variations"] for x in ex), "P150: a row without tabs plays as it is; no tab row carries variations")
        # ---------------------------------------------------------------- the Endless window
        check(res["on"] == [True, False, False, False], "P150: an Endless window is on unless enabled false: %s" % res["on"])
        check(res["len"] == [180, 180, 180] and res["max"] == [60, 100, 100] and res["growth"] == [25, 0] and res["bossGrowth"] == 0,
              "P150: an Endless window's defaults (180 s, Max count 100, no growth); a boss fight window never grows: %s %s %s" % (res["len"], res["max"], res["growth"]))
        check(res["maxAt"] == [60, 85, 110, 130, 130] and res["maxAtNone"] == -1, "P150: Max count grows by its growth a cycle, never past the hard cap; -1 stays: %s" % res["maxAt"])
        check(res["fresh"] == {"length": 180, "max_count": 100, "max_count_growth": 0, "roster": []} and res["freshBoss"] == {"length": 120, "max_count": 40, "roster": []},
              "P150: a new Endless window and a new boss fight window: %s %s" % (res["fresh"], res["freshBoss"]))
        # pass 153: the pulse's four keys (off by default, as WaveTimeline.endless_window_pulse reads a block without them)
        check(res["def"] == {"length": 180, "max_count": 100, "max_count_growth": 0, "pulse_on": 0, "pulse_off": 0, "pulse_rows": 1, "pulse_burst": 1},
              "P150: ENDLESS_WINDOW_DEF matches the game's: %s" % res["def"])
        check(res["kinds"] == {"boss": "boss_fight", "endless": "endless_window", "unknown": "boss"}, "P150: the two window kinds' blocks: %s" % res["kinds"])
        check(res["bossStill"] == {"block": True, "endless": True}, "P150: the boss fight window reads as before")
        check(res["ids"] == ["en1-5", "en2-2", "bf1-2", "bf1-2"], "P150: a new Endless row id is en<stage>-<n> (no window or roster row uses it): %s" % res["ids"])
        cy = res["cyc"]
        check(cy[0][1] == [True, True, True, True] and cy[1][1] == [False, True, True, True] and cy[2][1] == [True, False, False, False] and cy[3][1] == [False, True, True, False],
              "P150: From cycle / Until cycle open a row in those cycles only: %s" % [x[1] for x in cy])
        check(res["open"] == [[0, 1], [0, 2, 3], [0, 2, 3]] and res["openAny"] == [0, 1, 2, 3], "P150: the rows open at a second of a cycle, by their cycles: %s %s" % (res["open"], res["openAny"]))
        ci = res["cycleIssues"]
        check(ci[0] == [] and ci[3] == [] and any("From cycle is a whole number" in x["msg"] for x in ci[4]) and any("Until cycle is a whole number" in x["msg"] for x in ci[5])
              and any(x["level"] == "warn" and "never spawns" in x["msg"] for x in ci[6]), "P150: From / Until cycle checks: %s" % ci)
        check(res["checksGood"] == [], "P150: a correct Endless window has no window issue: %s" % res["checksGood"])
        cb = res["checksBad"]
        hasb = lambda key, level, frag: any(x["key"] == key and x["level"] == level and frag in x["msg"] for x in cb)
        check(hasb("endless:0", "error", "at least 1") and hasb("endless:0", "error", "whole number of creatures") and hasb("endless:0", "error", "Growth / cycle is a number"),
              "P150: a bad cycle, Max count and growth are errors: %s" % [x for x in cb if x["key"] == "endless:0"])
        check(hasb("endlessrow:0:0", "warn", "never spawns") and hasb("endlessrow:0:0", "warn", "Channel (hell) means nothing in an Endless window") and hasb("endlessrow:0:0", "error", "From cycle is a whole number"),
              "P150: an Endless row past the cycle, with a channel, a bad From cycle: %s" % [x for x in cb if x["key"] == "endlessrow:0:0"])
        check(hasb("endlessrow:0:1", "error", "used twice in the Endless windows") and hasb("endlessrow:0:1", "warn", "past the cycle's end") and hasb("endlessrow:0:1", "warn", "before From cycle"),
              "P150: a duplicate id, an until past the cycle, Until cycle before From cycle: %s" % [x for x in cb if x["key"] == "endlessrow:0:1"])
        check(hasb("endlessrow:0:2", "error", "must be a block"), "P150: an Endless row that is not a block is an error")
        check(hasb("endless:1", "error", "on or off") and hasb("endless:1", "warn", "above the hard cap") and hasb("endless:1", "warn", "nothing spawns in Endless"),
              "P150: enabled not a switch, Max count over the hard cap, an empty window: %s" % [x for x in cb if x["key"] == "endless:1"])
        check(hasb("endless:2", "error", "endless_window must be a block"), "P150: a window that is not a block is an error")
        check(not any(x["key"] == "endless:3" and "Max count 0" in x["msg"] for x in cb), "P150: Max count 0 with growth is no warning (it grows)")
        check(any(x["key"] == "bossfight:0" and x["level"] == "warn" and "means nothing in a boss fight window" in x["msg"] for x in res["bossChecksBad"]),
              "P150: a boss fight window with Growth / cycle is warned: %s" % res["bossChecksBad"])
        c = res["cycles"]
        check(c[0] and c[0]["cycles"] == 3 and [round(x, 3) for x in c[0]["spawned"]] == [10, 10, 10] and c[0]["n"] == 181, "P150: an Endless window plays three cycles by default: %s" % c[0])
        check(c[1] and c[1]["maxBy"] == [20, 35, 50] and abs(c[1]["maxAlive"] - 50) < 1.01, "P150: the estimate's crowd steps up with Max count's growth: %s" % str(c[1] and (c[1]["maxBy"], c[1]["maxAlive"])))
        check(c[2] and c[2]["maxBy"] == [400, 490, 500, 500], "P150: the growth never past the hard cap: %s" % (c[2] and c[2]["maxBy"]))
        r3 = {x["i"]: x for x in c[3]["rows"]} if c[3] else {}
        check(c[3] and r3[0]["spawned"][0] == 30 and r3[0]["spawned"][1] == 0 and r3[0]["spawned"][2] == 0 and r3[1]["spawned"][0] == 0 and r3[1]["waves"][1] == 3 and r3[1]["spawned"][1] == 6,
              "P150: until cycle 1 and from cycle 2 in the estimate: %s" % c[3])
        check(c[4] and len(c[4]["rows"]) == 1 and abs(c[4]["spawned"][0] - 13) < 1e-6 and c[4]["rows"][0]["waves"] == [1, 1, 1],
              "P150: a row's tabs play by their shares, summed into one row: %s" % c[4])
        check(c[5] is None, "P150: no Endless window = no estimate")
        check(c[6] and abs(c[6]["spawned"][0] - 9) < 1e-6 and c[7] and abs(c[7]["spawned"][0] - 10) < 1e-6, "P150: a boss counts against Max count, Endless has none: %s %s" % (str(c[6] and c[6]["spawned"]), str(c[7] and c[7]["spawned"])))
        # ---------------------------------------------------------------- the page
        pg = res["page"]
        errs = lambda name: [e for e in pg[name]["errors"]]
        check(errs("real") == [], "P150: the real red_canyon.json has no error-level issue (Save is not blocked): %s" % errs("real")[:5])
        check(errs("good") == [] and not any(k for k in pg["good"]["warnings"] if k["key"].startswith("endless") or "Variation" in k["msg"]),
              "P150: a good Endless window and good tabs change no check: %s" % ([e for e in pg["good"]["errors"]] + [w for w in pg["good"]["warnings"] if w["key"].startswith("endless") or "Variation" in w["msg"]])[:6])
        plainw = {(w["key"], w["msg"]) for w in pg["plain"]["warnings"]}
        goodw = {(w["key"], w["msg"]) for w in pg["good"]["warnings"]}
        check(goodw - plainw == set(), "P150: no new warning from the good map's windows and tabs: %s" % sorted(goodw - plainw)[:5])
        be = pg["bad"]["errors"] + pg["bad"]["warnings"]
        hp = lambda key, frag: any(x["key"] == key and frag in x["msg"] for x in be)
        check(hp("roster:0", "Variation 1: unknown creature \"nobody_at_all\"") and hp("roster:0", "Variation 2 has no creature") and hp("roster:0", "add up to 125%")
              and hp("roster:0", "has no art variant \"NOPE-Z\"") and hp("roster:0", "Variation 3: "), "P150: a tab's creature and look are checked, its words led by its tab: %s" % [x for x in be if x["key"] == "roster:0"])
        check(hp("roster:1", "From cycle / Until cycle mean something only on a boss fight or Endless window row"), "P150: From cycle on a stage row is warned")
        check(hp("endless:1", "whole number of creatures") and hp("endlessrow:1:0", "unknown creature") and hp("endlessrow:1:0", "is not after t") and hp("endlessrow:1:1", "From cycle is a whole number"),
              "P150: a bad Endless window's rows get a row's checks: %s" % [x for x in be if x["key"].startswith("endless")])
        ac = pg["acts"]
        check(ac["tab0"] == 0 and ac["afterAdd"]["tab"] == 1 and ac["afterAdd"]["sel"].get("v") == 1 and ac["afterAdd"]["pct"] == [50, 50] and ac["afterAdd"]["history"] == 1,
              "P150: + Variation opens tab 1 at 50%%, one undo step: %s" % ac["afterAdd"])
        check(ac["afterPct"] == [80, 20], "P150: the share box sets a tab and the Original takes the rest: %s" % ac["afterPct"])
        check(ac["reselect"] == 1 and ac["other"] == 0 and ac["toOrig"] == 0, "P150: picking the same row again keeps its tab; another row opens on its Original; selectTab(0) goes back")
        check(ac["second"]["tab"] == 2 and ac["second"]["pct"] == [40, 10, 50], "P150: a second tab from the Original's tab: %s" % ac["second"])
        check(ac["removed"] == {"tab": 1, "n": 1, "pct": [50, 50]}, "P150: × on tab 1 keeps the open tab (renumbered) and gives the share back: %s" % ac["removed"])
        check(ac["allGone"]["tab"] == 0 and ac["allGone"]["has"] is False and "v" not in ac["allGone"]["sel"] and ac["undone"] == 1, "P150: the last tab gone, the Original open; Ctrl+Z brings it back: %s" % ac["allGone"])
        check(ac["newRow"]["n"] == 1 and ac["newRow"]["sel"] == {"kind": "endlessrow", "s": 0, "i": 3} and ac["newRow"]["row"]["pace"] == "waves" and ac["newRow"]["row"]["t"] == 12 and ac["newRow"]["row"]["id"] == "en1-4",
              "P150: + Row in an Endless window: %s" % ac["newRow"])
        check(ac["dup"]["n"] == 2 and ac["dup"]["id"] == "en1-5" and ac["dup"]["sel"]["i"] == 4 and ac["nudged"] == 17 and ac["deleted"] == 1, "P150: Duplicate, nudge and Delete on an Endless row: %s" % ac)
        check(ac["growth"] == 15 and ac["added"] == {"length": 180, "max_count": 100, "max_count_growth": 0, "roster": []} and ac["removedWin"] is None, "P150: setting, adding and removing an Endless window")
        check(ac["selKey"] == "endlessrow:0:0" and ac["selItem"] is True and ac["cardKey"] == "endless:0" and ac["cardNone"] == {"kind": "endless", "s": 2, "none": True},
              "P150: the Endless selections' keys and items: %s" % [ac["selKey"], ac["cardKey"], ac["cardNone"]])
        ids = res["fields"]
        check("endless" in ids and ids.index("endless") == ids.index("bossfight") + 1, "P150: the Endless section sits right under Boss fights: %s" % ids)
        check(res["endlessSection"]["kind"] == "edit", "P150: the Endless section is an editing one")
        check(res["cycleFields"] == [{"key": "from_cycle", "window": True, "type": "int"}, {"key": "until_cycle", "window": True, "type": "int"}], "P150: From / Until cycle are window-row fields: %s" % res["cycleFields"])
        check(res["biteRows"] == [{"key": "bite_slow.frac", "def": 0.25, "group": "Scaling"}, {"key": "bite_slow.seconds", "def": 1, "group": "Scaling"}], "P150: the bite slow rows (25%% for 1 s): %s" % res["biteRows"])
        check(res["appApi"] == [], "P150: the App's window and tab functions: missing %s" % res["appApi"])
    # ---------------------------------------------------------------- the page's words and wiring
    pages = {n: _read(n) for n in ("boss_fights.js", "inspector.js", "timeline.js", "style.css", "index.html", "onscreen.js", "onscreen_model.js", "app.js")}
    bf = pages["boss_fights.js"]
    check("const WindowPanels = (kind) =>" in bf and "const BossFights = WindowPanels('boss');" in bf and "const EndlessWindows = WindowPanels('endless');" in bf,
          "P150: boss_fights.js draws both sections from one factory")
    check("Endless clock (0:00 = the portal closes)" in bf and "'Growth / cycle'" in bf and "Add an Endless window" in bf, "P150: the Endless panel's words and controls")
    ins = pages["inspector.js"]
    check("function variationTabs(container, r, tab)" in ins and "'+ Variation'" in ins and "inherited from the Original" in ins and "Model.variationView(r0, tab)" in ins,
          "P150: the row form's tab bar, its view and the inherited marks")
    check("else if (sel.kind === 'endlessrow') rosterForm(container, item, sel.i, windowEnv('endless', sel.s, sel.i, item));" in ins and "else if (sel.kind === 'endless') windowForm(container, sel.s, 'endless');" in ins,
          "P150: the inspector opens an Endless row and an Endless window's card")
    check("if (def.window && !env.boss) continue;" in ins, "P150: From / Until cycle only on a window row")
    tlj = pages["timeline.js"]
    check("EndlessWindows.render(enHost)" in tlj and "if (id === 'endless') {" in tlj and "chip-vars" in tlj, "P150: the Timeline draws the Endless section and the variation chip")
    css = pages["style.css"]
    check(".inspector { flex: 0 0 538px;" in css and "{ .inspector { flex-basis: 463px; } }" in css, "P150: the inspector is 25% wider (538 px, 463 px under 1440)")
    check(".frow.vinherit" in css and ".vtab.active" in css, "P150: the tab bar and the yellow inherited fields have their styles")
    check("variations: Model" in pages["onscreen.js"] and "function tabRow(row, id, vm, r)" in pages["onscreen_model.js"], "P150: Show on screen draws a row's tabs")
    idx = pages["index.html"]
    check(idx.index('src="timeline.js"') < idx.index('src="boss_fights.js"') < idx.index('src="inspector.js"'), "P150: boss_fights.js loads after timeline.js and before the inspector")

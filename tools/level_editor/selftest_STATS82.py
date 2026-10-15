"""Pass 82 (lane STATS): chests, power-ups and totems through a run; the how-to made findable.

selftest.py discovers this file and hands it `check`, `run_node` and the `server` module. Nothing here runs Godot (the
GDScript twin is pinned to the same fixture by game/tests/pass82_stats_test.gd).

  rule     sim_model.js pickupKind() and tools/analytics_csv.py pickup_kind() name the same kind for every event of the
           fixture (testdata/stats82_pickups.json `kinds`): a `chest` event (taken, skipped, a boss's), a `pickup` whose
           `small` is not set, a `totem` event; nothing else (structure, totem_offer, a small pickup, "Chest", 42)
  series   the counts so far at each row (sim_avg.js series() from the record, pickupCounts, the Python twin) are the
           fixture's `expect`, the totals its `totals`
  average  sim_avg.js aggregate() and tools/sim_batch.py aggregate() give the same chests / powerups / totems (series,
           per player, the summary's means) on made-up runs and on the fixture's run
  charts   the Sim's chart "Chests, power-ups, totems" (id pickups) with its three lines and colours, the tile, missing()
           naming it for a result without the series (an older sim), the compared sim's lines dashed
  csv      the dashboard's csv-lib (run under Node) and tools/analytics_csv.py write the same rows CSV, byte for byte, on
           the fixture and on the dash78 record, with the three columns after the row's own
  page     the dashboard draws its own card and the marks, the Remote runs view shows the how-to's steps, its links lead to
           files that exist; analytics/README.md's index names every how-to
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
TESTDATA = os.path.join(HERE, "testdata")
ANALYTICS = os.path.join(ROOT, "analytics")

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'sim_model.js'));
const A = require(path.join(dir, 'sim_avg.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  const rec = q.fixture.record;
  out.kinds = rec.events.map((e) => M.pickupKind(e));
  out.counts = M.pickupCounts(rec.events, rec.samples.map((r) => r.t));
  out.totals = M.pickupTotals(rec.events);
  const p = A.fromRecord(rec);
  out.fromRecord = { chests: p.chests, powerups: p.powerups, totems: p.totems, n: p.t.length };
  out.series = A.series(rec.samples, rec.events, [], {}, {});
  out.player = p;
  // the averages: the made-up runs Python gave, and the fixture's run beside two of them
  out.agg = q.agg.map((c) => { const r = A.aggregate(c.players, c.settings, {}, {}); return { series: r.series, summary: r.summary, players: r.players, t: r.t }; });
  // the charts
  const res = A.aggregate(q.agg[0].players, q.agg[0].settings, {}, {});
  const cmp = A.aggregate(q.agg[1].players, q.agg[1].settings, {}, {});
  const defs = M.charts(res, cmp, {});
  const c = defs.find((x) => x.id === 'pickups');
  out.chart = c ? { section: c.section, title: c.title, how: c.how, lines: c.lines.map((l) => [l.key, l.label, l.color, l.values.length]), overlay: c.overlay.map((l) => l.label), fmt: c.fmt } : null;
  out.ids = defs.map((x) => x.id);
  out.tiles = M.tiles(res).map((t) => [t.label, t.value]);
  out.missing = M.missing(res);
  const old = JSON.parse(JSON.stringify(res));
  for (const k of ['chests', 'powerups', 'totems']) delete old.series[k];
  delete old.summary.chests_mean; delete old.summary.powerups_mean; delete old.summary.totems_mean;
  out.oldIds = M.charts(old, null, {}).map((x) => x.id);
  out.oldMissing = M.missing(old);
  out.oldTiles = M.tiles(old).map((t) => t[0]);
  const one = A.aggregate([{ k: 1, d: p, rec: {} }], { limit: 100000, hero: 'drifter' }, {}, rec.names);
  const c1 = M.charts(one, null, {}).find((x) => x.id === 'pickups');
  out.one = c1 ? { how: c1.how, last: c1.lines.map((l) => l.values[l.values.length - 1]) } : null;
  out.series82 = M.PICKUP_SERIES;
  // the page's CSVs: its csv-lib script run here with the Sim's rule beside it
  globalThis.SimModel = M;
  (0, eval)(q.csvlib);
  out.csv = q.csvRecords.map((r) => { const t = globalThis.RunCSV.rowsTable(r); return globalThis.RunCSV.toCSV(t.columns, t.rows); });
  process.stdout.write(JSON.stringify(out));
});
"""


def _load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _csvlib():
    html = open(os.path.join(ANALYTICS, "dashboard.html"), encoding="utf-8").read()
    m = re.search(r'<script id="csv-lib">(.*?)</script>', html, re.S)
    return html, (m.group(1) if m else "")


def checks(check, run_node, server):
    import analytics_csv as AC
    import sim_batch as SB
    from selftest_DASH78 import _diff
    fx = _load(os.path.join(TESTDATA, "stats82_pickups.json"))
    rec = fx["record"]
    exp = fx["expect"]
    # ---- the rule and the counts, Python's twin
    kinds_py = [AC.pickup_kind(e) for e in rec["events"]]
    check(kinds_py == fx["kinds"], "STATS82 rule: analytics_csv.pickup_kind names the fixture's kinds: %s" % kinds_py)
    counts_py = AC.pickup_counts(rec["events"], [AC._t(r) for r in rec["samples"]])
    check(all(counts_py[k] == exp[k] for k in ("chests", "powerups", "totems")),
          "STATS82 series: analytics_csv.pickup_counts gives the fixture's counts: %s" % counts_py)
    # ---- the averages' inputs: made-up runs (they carry the three since pass 82) and the fixture's run
    st1 = {"players": 4, "limit": 600, "death": "gold"}
    st2 = {"players": 3, "limit": 300, "death": "keep"}
    ps1 = [(k, SB.synthetic_player(k, 10 * k + 3, st1), {"seed": k}) for k in range(1, 5)]
    ps2 = [(k, SB.synthetic_player(k, 40 + k, st2), {"seed": 40 + k}) for k in range(1, 4)]
    for k, d, _ in ps1 + ps2:
        n = len(d["t"])
        ok = all(len(d[x]) == n and all(b >= a for a, b in zip(d[x], d[x][1:])) for x in ("chests", "powerups", "totems"))
        check(ok, "STATS82 made-up run %d: chests, powerups, totems as long as t[] and never falling" % k)
    html, csvlib = _csvlib()
    check(bool(csvlib), "STATS82 page: the dashboard's csv-lib script is there")
    dash78 = _load(os.path.join(TESTDATA, "dash78_series_in.json"))["record"]
    q = {"fixture": fx, "agg": [{"players": [{"k": k, "d": d, "rec": r} for k, d, r in ps], "settings": st} for ps, st in ((ps1, st1), (ps2, st2))],
         "csvlib": csvlib, "csvRecords": [rec, dash78]}
    out = run_node(q, RUNNER)
    if out is None:
        print("STATS82: node is not here: the page checks are skipped")
        return
    if not out:
        return
    check(out["kinds"] == fx["kinds"], "STATS82 rule: sim_model.js pickupKind names the fixture's kinds: %s" % out["kinds"])
    check(all(out["counts"][k] == exp[k] for k in ("chests", "powerups", "totems")), "STATS82 series: pickupCounts gives the fixture's counts: %s" % out["counts"])
    check(out["totals"] == exp["totals"], "STATS82 series: pickupTotals counts every event (one after the last row too): %s" % out["totals"])
    fr = out["fromRecord"]
    check(fr["n"] == len(rec["samples"]) and all(fr[k] == exp[k] for k in ("chests", "powerups", "totems")),
          "STATS82 series: sim_avg.js fromRecord carries the counts as long as t[]: %s" % fr)
    check(all(out["series"][k] == exp[k] for k in ("chests", "powerups", "totems")), "STATS82 series: sim_avg.js series() (sim_run.gd's twin) has them")
    # ---- JS and Python average the same
    pyres = [SB.aggregate(ps, st, {}, game_dir=os.path.join(ROOT, "nogame")) for ps, st in ((ps1, st1), (ps2, st2))]
    for i, (py, js) in enumerate(zip(pyres, out["agg"])):
        py = json.loads(json.dumps(py))
        d = []
        for k in ("chests", "powerups", "totems"):
            _diff(py["series"].get(k), js["series"].get(k), "series/" + k, d)
            _diff([p.get(k) for p in py["players"]], [p.get(k) for p in js["players"]], "players/" + k, d)
            _diff(py["summary"].get(k + "_mean"), js["summary"].get(k + "_mean"), "summary/" + k + "_mean", d)
        check(not d and py["series"].get("chests"), "STATS82 average %d: sim_avg.js and sim_batch.py give the same chests, powerups, totems: %s" % (i, d[:4]))
    # the fixture's run (as the page maps it) beside two made-up runs: Python's average of the same players
    mixed = [(1, out["player"], {"seed": 1})] + ps1[:2]
    pym = json.loads(json.dumps(SB.aggregate(mixed, {"players": 3, "limit": 600}, {}, game_dir=os.path.join(ROOT, "nogame"))))
    q2 = {"fixture": fx, "agg": [{"players": [{"k": k, "d": d, "rec": r} for k, d, r in mixed], "settings": {"players": 3, "limit": 600}}, q["agg"][1]],
          "csvlib": csvlib, "csvRecords": []}
    out2 = run_node(q2, RUNNER)
    if out2:
        d = []
        for k in ("chests", "powerups", "totems"):
            _diff(pym["series"].get(k), out2["agg"][0]["series"].get(k), "series/" + k, d)
            _diff(pym["summary"].get(k + "_mean"), out2["agg"][0]["summary"].get(k + "_mean"), "summary/" + k, d)
        check(not d, "STATS82 average: a real run's counts beside made-up runs average the same in JS and Python: %s" % d[:4])
    # ---- the chart, the tile, an older result
    c = out["chart"]
    check(c is not None and c["section"] == "rewards" and c["title"] == "Chests, power-ups, totems" and c["fmt"] == "level",
          "STATS82 chart: 'Chests, power-ups, totems' in the rewards section: %s" % (c and c["title"]))
    if c:
        check([x[:3] for x in c["lines"]] == [["chests", "chests", "#c98500"], ["powerups", "power-ups", "#3987e5"], ["totems", "totems", "#d55181"]],
              "STATS82 chart: three lines, one colour each (amber, blue, magenta): %s" % c["lines"])
        check(c["overlay"] == ["compared: chests", "compared: power-ups", "compared: totems"], "STATS82 chart: the compared sim's three lines: %s" % c["overlay"])
        check("Chests opened (taken or skipped, boss chests too)" in c["how"] and "small ones underfoot" in c["how"] and "Totem Pole gifts taken" in c["how"]
              and "averaged over the runs still playing" in c["how"], "STATS82 chart: its words say what counts: %s" % c["how"])
    check(out["ids"].index("pickups") == out["ids"].index("kills") + 1, "STATS82 chart: after the kills: %s" % out["ids"])
    check(any(t[0] == "Chests · power-ups · totems a run" and t[1].count(" · ") == 2 for t in out["tiles"]), "STATS82 tiles: the means a run: %s" % out["tiles"])
    check(not any("Chests, power-ups" in x for x in out["missing"]), "STATS82 missing: nothing missing when the runs carry them")
    check("pickups" not in out["oldIds"] and any("Chests, power-ups, totems" in x for x in out["oldMissing"]),
          "STATS82 older sim: no chart, and missing() names it: %s" % out["oldMissing"])
    o1 = out["one"]
    check(o1 is not None and o1["last"] == [exp["chests"][-1], exp["powerups"][-1], exp["totems"][-1]] and "Each step is one picked up" in o1["how"]
          and "this run" in o1["how"], "STATS82 chart: one run draws its own steps: %s" % o1)
    check([s["key"] for s in out["series82"]] == ["chests", "powerups", "totems"], "STATS82 PICKUP_SERIES: the three keys in order")
    # ---- the CSVs, byte for byte
    for name, r, js in (("the fixture", rec, out["csv"][0]), ("the dash78 record", dash78, out["csv"][1])):
        cols, rows = AC.rows_table(r)
        py = AC.to_csv(cols, rows)
        check(py == js, "STATS82 csv: the page's rows CSV is analytics_csv.py's on %s (%d vs %d chars)" % (name, len(js), len(py)))
        i = cols.index("chests") if "chests" in cols else -1
        check(i > 0 and cols[i:i + 3] == ["chests", "powerups", "totems"] and not any("." in x for x in cols[:i]),
              "STATS82 csv: the three columns after the row's own on %s" % name)
    cols, rows = AC.rows_table(rec)
    i = cols.index("chests")
    check([r[i] for r in rows] == exp["chests"] and [r[i + 1] for r in rows] == exp["powerups"] and [r[i + 2] for r in rows] == exp["totems"],
          "STATS82 csv: the columns hold the counts so far")
    cols0, rows0 = AC.rows_table({"samples": [], "events": rec["events"]})
    check(cols0 == ["t"] and rows0 == [], "STATS82 csv: a run without rows keeps its one-column header")
    # ---- the page
    check("renderOffers, renderPickups, renderTotems" in html and "function renderPickups(grid, S)" in html,
          "STATS82 page: the dashboard's own card 'Chests, power-ups and totems' is drawn")
    check("dots: dots || []" in html and "const dots = pkDots(S);" in html, "STATS82 page: Progression's level chart marks each one")
    check("How do I get players\\' runs? (step by step)" in html and "remoteHowto(c, !idx);" in html and "python tools/posthog_runs.py" in html,
          "STATS82 page: the Remote runs view shows the steps")
    for href in re.findall(r'href="((?:howto/)?[A-Za-z0-9_]+\.md)"', html):
        check(os.path.isfile(os.path.join(ANALYTICS, href)), "STATS82 page: its link %s leads to a file" % href)
    check('href="README.md"' in html and 'href="howto/03_remote_runs.md"' in html, "STATS82 page: links to the index and the remote-runs how-to")
    readme = open(os.path.join(ANALYTICS, "README.md"), encoding="utf-8").read()
    for f in sorted(os.listdir(os.path.join(ANALYTICS, "howto"))):
        if f.endswith(".md"):
            check(("howto/" + f) in readme.split("## The dashboard")[0], "STATS82 README: the index at the top names howto/%s" % f)
    howto = open(os.path.join(ANALYTICS, "howto", "03_remote_runs.md"), encoding="utf-8").read()
    check("python tools/posthog_runs.py" in howto and "tools/posthog_personal_key.txt" in howto and "analytics/remote/<player>/" in howto
          and "v0.64" in howto, "STATS82 howto 03: the command, the key file, where the files land, the builds that send")

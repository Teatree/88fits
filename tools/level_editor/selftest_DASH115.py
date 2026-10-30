"""Pass 115, lane DASH: the run dashboard's new cards and the Sim's health bars. selftest.py discovers this file and hands
it `check`, `run_node` and the `server` module. Nothing here runs Godot or touches the network.

Garry: "Danger Health Lost a second is a weird metric ... Just show Current HP instead with bars. Show different coloured
bars for damage taken. Make it be per 5 seconds"; "Hero Level ... Hero Items Count"; "Individual Weapon Real DPS ... For
each item that was affected by other items we list those as icons as well"; "There should be info about what level of
Mirror Upgrade Player was when they played"; "I need to know Player Mirror Upgrades while watching the replay".

Groups:
  bars    tools/sim_batch.py and sim_avg.js derive the 5 s health bars (hp_low5, took5, healed5) by hand on a made-up run
          (the lowest health of each 5 s as % of max HP, the damage and the healing summed), hp_min read where a run has
          it, a run's last bucket short; the two give the same result (selftest_DASH78 compares every series too)
  chart   sim_model.js draws "hp5" in Danger's place (bars every rules.hp_bucket seconds: the lowest health, the damage on
          its top, the healing under the line), its axis below 0, its readout at a second (the bucket's values), its
          table, a result without the bars named among the missing; nothing draws Danger any more
  record  sim_avg.js fromRecord keeps a schema 5 record's hp_min (the lowest inside each second) and an older record has
          none; analytics_csv.py's rows CSV carries hp_min (empty when the row has none) and its index row the board's
          most and gold, the big blocks left out
  page    the dashboard's scripts parse; its new cards (renderBoard, renderLevelItems, renderWeaponDps, renderHealth5) are
          in its steps; the Remote runs list and the average's runs carry a board column; the markers plugin draws a
          highlight and the icon strip follows the plot area
  replay  tools/replay.py prints the Upgrade board of a recording's save (ranks, forms, gold at today's prices)
"""
import json
import os
import re
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
const path = require('path');
const dir = path.dirname(process.argv[2]);
const A = require(path.join(dir, 'sim_avg.js'));
const M = require(path.join(dir, 'sim_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.agg = q.agg.map((c) => { const r = A.aggregate(c.players, c.settings, {}, {}); return { series: r.series, rules: r.rules, t: r.t, markers: r.markers }; });
  const res = A.aggregate(q.agg[0].players, q.agg[0].settings, {}, {});
  const defs = M.charts(res, null, {});
  out.ids = defs.map((c) => c.id);
  const hp5 = defs.find((c) => c.id === 'hp5');
  out.hp5 = hp5 ? { section: hp5.section, step: hp5.bars.step, items: hp5.bars.items.map((b) => [b.key, b.label, !!b.on, !!b.below]), how: hp5.how, fmt: hp5.fmt,
    range: M.chartRange(hp5), parts: M.barParts(hp5).map((p) => [p.bottom.slice(0, 12), p.top.slice(0, 12)]), read: M.readout(hp5, 7), table: M.table(hp5, 5).head,
    ticks: [M.tickLabel(-50, 100, 'pcta'), M.fmtVal(-12.4, 'pcta')] } : null;
  const bare = JSON.parse(JSON.stringify(res));
  for (const k of ['hp_low5', 'took5', 'healed5']) delete bare.series[k];
  out.bareIds = M.charts(bare, null, {}).map((c) => c.id);
  out.lacking = M.missing(bare);
  out.recs = q.records.map((rec) => { const p = A.fromRecord(rec); return { hp_min: p.hp_min || null, keys: Object.keys(p).sort() }; });
  const one = A.aggregate([{ k: 1, d: A.fromRecord(q.records[0]), rec: {} }], { limit: 100000, hero: 'drifter' }, {}, {});
  out.one = { low: one.series.hp_low5 ? one.series.hp_low5.mean : null, took: one.series.took5 ? one.series.took5.mean : null, healed: one.series.healed5 ? one.series.healed5.mean : null };
  process.stdout.write(JSON.stringify(out));
});
"""


def _player(hp, hp_max, took, healed, hp_min=None):
    n = len(hp)
    d = {"t": list(range(1, n + 1)), "hp": hp, "hp_max": hp_max, "took": took, "healed": healed, "dps": [10] * n, "level": [1] * n,
         "kills": list(range(n)), "deaths": [0] * n, "clock": list(range(1, n + 1)), "stage": [1] * n, "events": [],
         "meta": {"end_reason": "limit", "end_t": float(n), "wall_s": 10.0, "boot_s": 1.0}}
    if hp_min is not None:
        d["hp_min"] = hp_min
    return d


def _bars_by_hand(d, T, B=5):
    """The rule in plain Python on whole seconds 0..T (the grid puts a run's first row, t=1, at second 1; second 0 takes
    its state, a rate 0)."""
    n = len(d["t"])
    hp = [d["hp"][0]] + d["hp"]
    hm = [d["hp_max"][0]] + d["hp_max"]
    low = ([d["hp_min"][0]] + d["hp_min"]) if "hp_min" in d else hp
    took = [0] + d["took"]
    healed = [0] + d["healed"]
    end = n
    lo5, tk5, hl5 = [None] * (T + 1), [None] * (T + 1), [None] * (T + 1)
    for b0 in range(0, end + 1, B):
        b1 = min(end, b0 + B - 1)
        lo = min(max(0.0, min(hp[s], low[s])) / hm[s] for s in range(b0, b1 + 1))
        tk = sum(took[s] / hm[s] for s in range(b0, b1 + 1))
        hl = sum(healed[s] / hm[s] for s in range(b0, b1 + 1))
        for s in range(b0, b1 + 1):
            lo5[s], tk5[s], hl5[s] = 100.0 * lo, 100.0 * tk, 100.0 * hl
    return lo5, tk5, hl5


def _record(with_min):
    rows = []
    hps = [100, 90, 60, 60, 80, 80, 40, 40, 70, 100, 100, 95]
    for i, h in enumerate(hps):
        r = {"t": float(i + 1), "clock": float(i + 1), "stage": 1, "level": 1, "hp": float(h), "hp_max": 100.0}
        if i in (2, 6):
            r["took"] = {"goblin": 30.0}
        if i == 4:
            r["healed"] = 20.0
            r["healed_by"] = {"Heart": 20.0}
        if with_min and i == 3:
            r["hp_min"] = 25.0
        rows.append(r)
    return {"schema": 5 if with_min else 4, "hero": "drifter", "hero_name": "Drifter", "length": 12.0, "result": "death", "samples": rows,
            "events": [{"t": 7.0, "clock": 7.0, "kind": "death", "id": "goblin"}, {"t": 8.0, "clock": 8.0, "kind": "revive", "id": "ad"}]}


def _close(a, b):
    if a is None or b is None:
        return a is None and b is None
    return abs(a - b) < 1e-6


def checks(check, run_node, server):
    import sim_batch as SB
    import analytics_csv as AC
    a = _player([100, 80, 50, 50, 90, 90, 90, 30, 30, 60, 60], [100] * 11, [0, 20, 30, 0, 0, 0, 0, 60, 0, 0, 0], [0, 0, 0, 0, 40, 0, 0, 0, 0, 30, 0])
    b = _player([100, 100, 100, 100, 100, 70, 70], [100, 100, 100, 100, 100, 120, 120], [0, 0, 0, 0, 0, 30, 0], [0] * 7,
                hp_min=[100, 100, 20, 100, 100, 50, 70])
    T = 11
    for name, d in (("a run without hp_min", a), ("a run with hp_min and a shorter end", b)):
        series, end, _bds = SB.player_grid(d, T)
        lo5, tk5, hl5 = _bars_by_hand(d, T)
        ok = all(_close(series["hp_low5"][s], lo5[s]) and _close(series["took5"][s], tk5[s]) and _close(series["healed5"][s], hl5[s]) for s in range(T + 1))
        check(ok, "bars: sim_batch's 5 s bars by hand on %s: %s %s" % (name, series["hp_low5"], lo5))
    series, _e, _b = SB.player_grid(b, T)
    check(_close(series["hp_low5"][0], 20.0) and _close(series["hp_low5"][5], 50.0 / 120 * 100) and series["hp_low5"][8] is None,
          "bars: the dip inside a second (hp_min 20) is the bucket's lowest; a bucket's share of its own max HP; none past the run's end: %s" % series["hp_low5"])
    st = {"players": 2, "limit": T, "death": "end"}
    players = [(1, a, {"seed": 1}), (2, b, {"seed": 2})]
    py = json.loads(json.dumps(SB.aggregate(players, st, {}, game_dir=os.path.join(ROOT, "nogame"))))
    check(py["rules"].get("hp_bucket") == 5 and "hp_low5" in py["series"] and "healed5" in py["series"], "bars: sim_batch's result carries the bars and their seconds: %s" % py["rules"])
    q = {"agg": [{"players": [{"k": k, "d": d, "rec": r} for k, d, r in players], "settings": st}], "records": [_record(True), _record(False)]}
    out = run_node(q, RUNNER)
    if out is None:
        print("DASH115: node is not here: the page maths checks are skipped")
    elif out:
        js = out["agg"][0]
        diffs = [k for k in ("hp_low5", "took5", "healed5", "hp_min") if (py["series"].get(k) != js["series"].get(k))]
        check(not diffs and js["rules"].get("hp_bucket") == 5, "bars: sim_avg.js gives sim_batch.py's bars exactly: %s" % diffs)
        check("hp5" in out["ids"] and "danger" not in out["ids"], "chart: the health bars in Danger's place, Danger drawn nowhere: %s" % out["ids"])
        h = out["hp5"] or {}
        check(h.get("section") == "difficulty" and h.get("step") == 5 and h.get("fmt") == "pcta"
              and h.get("items") == [["hp_low5", "lowest health", False, False], ["took5", "damage taken", True, False], ["healed5", "health back", False, True]],
              "chart: hp5's bars: the lowest health, the damage on its top, the healing under the line: %s" % h.get("items"))
        check(h.get("range", {}).get("lo", 0) < 0 and h.get("range", {}).get("hi", 0) >= 100, "chart: hp5's axis goes under 0 for the healing: %s" % h.get("range"))
        low, top = h["parts"][0], h["parts"][1]
        check(all(top[0][i] == low[1][i] for i in range(12) if low[1][i] is not None), "chart: the damage bar sits on the lowest health's top")
        rd = h.get("read") or []
        check(len(rd) == 3 and all(r["kind"] == "bar" for r in rd) and "(0:05–0:09)" in rd[0]["label"] and rd[0]["value"] == js["series"]["hp_low5"]["mean"][5],
              "chart: the readout at 0:07 reads the bucket 0:05-0:09: %s" % rd[:1])
        check(h.get("ticks") == ["50%", "12%"] and h.get("table", [None])[1:] == ["lowest health", "damage taken", "health back"],
              "chart: the healing's axis and values said without a sign; the table's columns: %s %s" % (h.get("ticks"), h.get("table")))
        check(all(x > 60 for x in [len(h.get("how", ""))]) and "5 s" in h.get("how", ""), "chart: hp5 says what it shows")
        check("hp5" not in out["bareIds"] and any("Health in 5 s bars" in x for x in out["lacking"]) and not any("Danger" in x for x in out["lacking"]),
              "chart: a result without the bars draws none and names them among the missing: %s" % out["lacking"])
        new, old = out["recs"]
        check(new["hp_min"] is not None and new["hp_min"][3] == 25.0 and new["hp_min"][0] == 100.0 and old["hp_min"] is None and "hp_min" not in old["keys"],
              "record: fromRecord keeps schema 5's hp_min (the row's hp where it did not dip) and an older record has none: %s" % new["hp_min"])
        one = out["one"]
        # the made-up record: second 4 dips to 25 (hp_min), seconds 3 and 7 take 30, second 5 heals 20; buckets 0-4, 5-9, 10-12
        check(one["low"] is not None and one["low"][0] == 25.0 and one["low"][5] == 40.0 and one["took"][0] == 30.0 and one["took"][5] == 30.0
              and one["healed"][0] == 0.0 and one["healed"][5] == 20.0,
              "record: one run's bars on the dashboard's numbers (the lowest, the damage, the healing): %s %s %s" % (one["low"][:6], one["took"][:6], one["healed"][:6]))
    # the CSVs: hp_min a row column (empty without one), the index row's board numbers and its big blocks left out
    rec = _record(True)
    rec["board"] = {"talents": [{"id": "grit", "picks": [0, 1], "max": 6, "gold": 2250}], "ranks": 2, "max": 48, "gold": 2250, "spent": 2000}
    rec["weapon_sources"] = {"revolver": [{"s": "passive:brawn", "w": "+10% attack damage"}]}
    rec["weapon_family"] = {"golden_revolver": "revolver"}
    rec["icons"] = {"revolver": "content/weapons/revolver/revolver_icon.png"}
    rec["stamp"] = "2026-10-30T10-00-00"
    cols, rws = AC.rows_table(rec)
    i = cols.index("hp_min") if "hp_min" in cols else -1
    check(i > cols.index("hp_max") and rws[3][i] == 25.0 and rws[0][i] == "", "record: the rows CSV's hp_min (empty where the row has none): %s" % (cols[:14],))
    row = AC.index_row(rec, "x.json")
    check(row.get("board_max") == 48 and row.get("board_gold") == 2250 and not any(str(k).split(".")[0] in ("board", "weapon_sources", "weapon_family", "icons") for k in row),
          "record: the index row: the board's most and gold, schema 5's big blocks left out: %s" % sorted(k for k in row if "board" in k))
    # the page's csv-lib and analytics_csv.py give the same rows CSV byte for byte on a record with hp_min (FPS101's runner)
    import selftest_FPS101 as F
    F._csv_checks(check, [("dash115", rec)])
    _page_checks(check)
    _replay_checks(check)


def _page_checks(check):
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    steps = re.search(r"const steps = \[(.*?)\];", html, re.S)
    st = steps.group(1) if steps else ""
    order = [st.find(x) for x in ("renderFacts", "renderBoard", "renderPower", "renderHeroPower", "renderLevelItems", "renderWeaponDps", "renderHealth,", "renderHealth5")]
    check(all(x >= 0 for x in order) and order == sorted(order), "page: the new cards in the run's steps (board after the facts, level and items and the weapons after Hero power, the 5 s bars after health): %s" % order)
    for fn in ("function renderBoard(", "function renderLevelItems(", "function renderWeaponDps(", "function renderHealth5(", "function boardShort(", "function iconStrip(", "function sourcesBySid("):
        check(fn in html, "page: the dashboard defines %s" % fn)
    check("'board', 'kills', 'version'" in html and "boardShort(r)" in html, "page: the Remote runs list has a board column")
    check("'level', 'board', 'kills', 'coins'" in html, "page: the average's runs carry a board column")
    check("o.hl ||" in html and "chart.$iconPlace" in html, "page: the markers plugin draws the highlight; the icon strip follows the plot (a function kept on the chart)")
    check("record (recorded before 0.98)" in html and "const OLD_WORDS" in html, "page: an older record's missing data said in plain words")
    node = shutil.which("node")
    if node:
        scripts = re.findall(r"<script(?: id=\"[^\"]*\")?>(.*?)</script>", html, re.S)
        tmp = tempfile.mkdtemp(prefix="le_dash115_")
        try:
            for k, s in enumerate(scripts):
                p = os.path.join(tmp, "s%d.js" % k)
                open(p, "w", encoding="utf-8").write(s)
                r = subprocess.run([node, "--check", p], capture_output=True, text=True)
                check(r.returncode == 0, "page: the dashboard's script %d parses: %s" % (k, r.stderr[-200:]))
            for f in ("sim_model.js", "sim_plot.js", "sim_avg.js"):
                r = subprocess.run([node, "--check", os.path.join(HERE, f)], capture_output=True, text=True)
                check(r.returncode == 0, "page: %s parses" % f)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    plot = open(os.path.join(HERE, "sim_plot.js"), encoding="utf-8").read()
    check("M.barParts(c)" in plot and "sim-fall" in plot and "row.kind === 'bar'" in plot, "page: sim_plot.js draws the bars, the falls and revives, a bar's readout key")


def _replay_checks(check):
    import replay as RP
    tmp = tempfile.mkdtemp(prefix="le_dash115_rp_")
    try:
        p = os.path.join(tmp, "x_replay.json")
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"kind": "88fits_replay", "look": "DM-G", "save": {"talents": {"grit": {"picks": [0, 1]}, "drive": {"form": 1, "rank": 2}}, "talent_spent": 10}}, f)
        lines = RP.board_lines(p)
        defs = RP._talent_defs()
        grit = next((t for t in defs if t["id"] == "grit"), None)
        check(len(lines) == len(defs) + 2 and "4 of %d ranks" % sum(t["ranks"] for t in defs) in lines[0] and lines[-1] == "the hero's look: DM-G",
              "replay: replay.py prints the board (every talent, the ranks of the whole board) and the look: %s" % lines[:1])
        gl = [ln for ln in lines if ln.strip().startswith(grit["name"])] if grit else []
        check(bool(gl) and " 2/%d " % grit["ranks"] in gl[0] and "AB" in gl[0] and grit["forms"][0] in gl[0] and grit["forms"][1] in gl[0],
              "replay: a talent's line: its ranks, A/B a rank, both forms by name: %s" % gl)
        dl = [ln for ln in lines if "Drive" in ln]
        check(bool(dl) and "BB" in dl[0], "replay: an old {form, rank} save reads as that form rank times: %s" % dl)
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"kind": "88fits_replay"}, f)
        check(RP.board_lines(p) == ["the Upgrade board: not in this recording"], "replay: a recording without a save says so")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

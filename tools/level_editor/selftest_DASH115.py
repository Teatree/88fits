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
          most and gold (a schema 5 record), the big blocks left out; pass 129: a schema 6 record's row has the Trail's
          three keys and none of the board's, as RunAnalytics.index_row
  page    the dashboard's scripts parse; its new cards (renderTrail, renderLevelItems, renderWeaponDps, renderHealth5) are
          in its steps; the Remote runs list and the average's runs carry a trail column; the markers plugin draws a
          highlight and the icon strip follows the plot area
  trail   pass 129 (schema 6: the Upgrade board left the game): the dashboard's own functions run under node on a made-up
          DOM: a schema 6 record draws The Trail (level of levels, nodes of nodes and how many paid, gold, every upgrade
          type's sum written by its kind, its icon key); a schema 5 record still draws its board as "Upgrade board
          (before the Trail)"; one with both draws both; one with neither says so; the lists' short words
  replay  tools/replay.py prints the Trail of a recording's save (the nodes paid for, their gold, the upgrades summed by
          type and written by kind, the unlocks; --board the old name); a recording from before the Trail says so
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
    check(row.get("talents") == 0 and "trail_level" not in row, "record: a schema 5 record without talents still has its talents column (0), no Trail keys: %s" % row.get("talents"))
    # pass 129 (schema 6): the Trail's three keys as RunAnalytics.index_row writes them, none of the board's
    rec6 = _record(True)
    rec6.update({"schema": 6, "stamp": "2026-11-06T10-00-00", "trail": _trail_block(), "chest_banks": {"jade_key": {"chests": 2}},
                 "icons": {"trail:might": "art/ui/trail/might.png"}})
    row6 = AC.index_row(rec6, "y.json")
    check(row6.get("trail_level") == 12 and row6.get("trail_bought") == 14 and row6.get("trail_spent") == 3450,
          "record: a schema 6 index row has the Trail's level, nodes bought and gold: %s" % {k: v for k, v in row6.items() if k.startswith("trail")})
    check(not any(str(k).split(".")[0] in ("talents", "talent_forms", "board", "board_max", "board_gold", "trail", "chest_banks", "icons") for k in row6),
          "record: a schema 6 index row has no talents, no board columns and none of the big blocks: %s" % sorted(k for k in row6 if "talent" in k or "board" in k or "." in k)[:6])
    hcols, _hrows = AC.history_table([row6, row])
    check(hcols.index("totems") < hcols.index("trail_level") < hcols.index("trail_bought") < hcols.index("trail_spent") < hcols.index("talents"),
          "record: the history CSV puts the Trail's columns after totems (an older row's talents after them)")
    old2 = {"schema": 2, "stamp": "2026-01-01T10-00-00", "talents": {"grit": [0, 1], "drive": [1]}, "talent_forms": {"grit": ["a", "b"]}}
    rowo = AC.index_row(old2, "o.json")
    check(rowo.get("talents") == 3 and rowo.get("talents.grit") == 2 and rowo.get("talents.drive") == 1,
          "record: an older record's talents columns are written as before: %s" % {k: v for k, v in rowo.items() if k.startswith("talents")})
    # the page's csv-lib and analytics_csv.py give the same rows CSV byte for byte on a record with hp_min (FPS101's runner)
    import selftest_FPS101 as F
    F._csv_checks(check, [("dash115", rec)])
    _page_checks(check)
    _trail_checks(check, run_node)
    _replay_checks(check)


def _page_checks(check):
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    steps = re.search(r"const steps = \[(.*?)\];", html, re.S)
    st = steps.group(1) if steps else ""
    order = [st.find(x) for x in ("renderFacts", "renderTrail", "renderPower", "renderHeroPower", "renderLevelItems", "renderWeaponDps", "renderHealth,", "renderHealth5")]
    check(all(x >= 0 for x in order) and order == sorted(order) and "renderBoard" not in st,
          "page: the new cards in the run's steps (the Trail after the facts, level and items and the weapons after Hero power, the 5 s bars after health): %s" % order)
    for fn in ("function renderTrail(", "function trailOf(", "function trailShort(", "function trailAmount(", "function renderBoard(", "function renderLevelItems(", "function renderWeaponDps(", "function renderHealth5(", "function boardShort(", "function iconStrip(", "function sourcesBySid("):
        check(fn in html, "page: the dashboard defines %s" % fn)
    check("'trail', 'kills', 'version'" in html and html.count("trailShort(r)") >= 2 and "boardShort(r), fmt" not in html, "page: the Remote runs list has a trail column")
    check("'level', 'trail', 'kills', 'coins'" in html, "page: the average's runs carry a trail column")
    check("trail: 'The Trail', talent: 'Upgrade board'" in html and "'trail_level', 'trail_bought', 'trail_spent', 'trail_bundle', 'talents', 'build'];" in html,
          "page: a source of kind trail reads The Trail (an older record's talent still Upgrade board); the history CSV's first columns name the Trail's")
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


def _trail_block(full=True):
    """A header's `trail` as RunAnalytics.trail_block writes it (schema 6); without levels, nodes, types as a record
    written before schema 6 had it."""
    b = {"level": 12, "bought": ["n%03d" % k for k in range(1, 15)], "paid": 11, "spent": 3450,
         "upgrades": {"might": 0.12, "reroll": 1.0, "calm": 2.0, "omen": 1.0, "grub": 25.5}}
    if full:
        b.update({"levels": 60, "nodes": 100, "types": {
            "might": {"name": "Might", "kind": "percent", "text": "Attack damage"}, "reroll": {"name": "Reroll", "kind": "count", "text": "Rerolls"},
            "calm": {"name": "Calm", "kind": "seconds", "text": "Untouchable time"}, "omen": {"name": "Omen", "kind": "word", "text": "A sign"},
            "grub": {"name": "Grubstake", "kind": "flat", "text": "Starting coins"}}})
    return b


# the dashboard's own Trail and board functions on a made-up DOM (every node an object with its class, text and children)
TRAIL_RUNNER = r"""
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const mk = (tag, cls, text) => ({ tag, cls: cls || '', text: text == null ? '' : String(text), kids: [], style: {}, appendChild(k) { this.kids.push(k); return k; } });
  const el = mk;
  const fmtI = (n) => (n == null || n === '' || isNaN(n)) ? '–' : Math.round(+n).toLocaleString('en-US');
  const titleCase = (x) => String(x);
  const card = (title, desc, opts) => { const c = mk('card'); c.title = title; c.desc = desc; c.slug = (opts || {}).slug; c._tables = []; return c; };
  const tileIn = (wrap, lbl, val, sub) => { const t = mk('tile'); t.lbl = lbl; t.val = String(val); t.sub = sub || ''; wrap.appendChild(t); return t; };
  const tableView = (c, columns, rows) => { c._tables.push({ head: columns.map((x) => x.label), rows }); };
  const iconEl = (S, key) => { const n = mk('ico'); n.key = key; return n; };
  const hoverTip = () => {};
  const F = new Function('el', 'fmtI', 'titleCase', 'card', 'tileIn', 'tableView', 'iconEl', 'hoverTip',
    "const OLD_WORDS = 'OLDW', BOARD_MAX_OLD = 48, TRAIL_OLD_WORDS = 'OLD6';\n" + q.src +
    "\nreturn { renderTrail, trailOf, trailWords, trailShort, trailAmount, boardShort };")(el, fmtI, titleCase, card, tileIn, tableView, iconEl, hoverTip);
  const walk = (n, f) => { f(n); for (const k of n.kids || []) walk(k, f); };
  const out = { runs: [], short: q.rows.map((r) => F.trailShort(r)), amounts: q.amounts.map(([k, v]) => F.trailAmount(k, v)) };
  for (const rec of q.records) {
    const grid = mk('grid');
    F.renderTrail(grid, { run: rec });
    const cards = grid.kids.map((c) => {
      const o = { title: c.title, slug: c.slug, tiles: [], amounts: [], icons: [], notes: [], names: [], table: c._tables.map((t) => ({ head: t.head, rows: t.rows })) };
      walk(c, (n) => {
        if (n.tag === 'tile') o.tiles.push([n.lbl, n.val, n.sub]);
        if (n.cls === 'tamt') o.amounts.push(n.text);
        if (n.tag === 'ico') o.icons.push(n.key);
        if (n.cls === 'oldnote') o.notes.push(n.text);
        if (n.tag === 'b') o.names.push(n.text);
      });
      return o;
    });
    const t = F.trailOf(rec);
    out.runs.push({ cards, short: F.trailShort(rec), words: t ? F.trailWords(t) : null });
  }
  process.stdout.write(JSON.stringify(out));
});
"""


def _trail_checks(check, run_node):
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    names = ("trailAmount", "trailOf", "trailWords", "trailBundle", "trailShort", "renderTrail", "boardOf", "boardShort", "renderBoard")   # pass 130: trailBundle (renderTrail names it)
    parts = [re.search(r"\n  function %s\(.*?\n  \}\n" % n, html, re.S) for n in names]
    check(all(parts), "trail: the dashboard's Trail and board functions are found: %s" % [n for n, m in zip(names, parts) if not m])
    if not all(parts):
        return
    board5 = {"talents": [{"id": "grit", "name": "Grit", "picks": [0, 1], "max": 6, "gold": 2250, "forms": ["Thick Hide", "Second Skin"], "texts": ["a", "b"]}],
              "ranks": 2, "max": 48, "gold": 2250, "spent": 2000}
    recs = [{"schema": 6, "trail": _trail_block(), "icons": {"trail:might": "art/ui/trail/might.png"}},
            {"schema": 5, "board": board5, "talents": {"grit": [0, 1]}},
            {"schema": 5, "board": board5, "talents": {"grit": [0, 1]}, "trail": _trail_block(False)},
            {"schema": 2, "talents": {"grit": [0, 1]}, "talent_forms": {"grit": ["Thick Hide", "Second Skin"]}, "names": {"grit": "Grit"}},
            {"schema": 1}]
    q = {"src": "".join(m.group(0) for m in parts), "records": recs,
         "rows": [{"trail_level": 7}, {"talents": 12, "board_max": 56}, {"talents": 3}, {"trail_level": 0, "talents": 5}],
         "amounts": [["percent", 0.03], ["percent", 0.025], ["flat", 2], ["flat", 0.3], ["count", 1], ["seconds", 2], ["word", 1], ["percent", -0.1]]}
    out = run_node(q, TRAIL_RUNNER)
    if out is None:
        print("DASH115: node is not here: the Trail card's checks are skipped")
        return
    if not out:
        return
    check(out["amounts"] == ["+3%", "+2.5%", "+2", "+0.3", "+1", "+2 s", "", "\u221210%"], "trail: a sum written by its kind (Trail.amount_text): %s" % out["amounts"])
    check(out["short"] == ["level 7", "board 12 / 56", "board 3 / 48", "level 0"], "trail: an index row in short (the Trail Level; an older row's board): %s" % out["short"])
    s6, s5, both, old, none = out["runs"]
    c = s6["cards"]
    check(len(c) == 1 and c[0]["title"] == "The Trail" and c[0]["slug"] == "trail", "trail: a schema 6 record draws one card, The Trail: %s" % [(x["title"], x["slug"]) for x in c])
    t = {x[0]: x for x in c[0]["tiles"]} if c else {}
    check(t.get("Trail Level", [0, ""])[1] == "12 of 60" and t.get("Nodes bought", [0, ""])[1] == "14 of 100" and "11 paid for" in t.get("Nodes bought", [0, 0, ""])[2]
          and "3 at no cost" in t.get("Nodes bought", [0, 0, ""])[2] and t.get("Gold spent", [0, ""])[1] == "3,450",
          "trail: its tiles: Trail Level N of levels, nodes bought of nodes (how many paid for, how many at no cost), gold spent: %s" % c[0]["tiles"])
    check(c[0]["amounts"] == ["+12%", "+1", "+2 s", "bought", "+25.5"] and c[0]["names"] == ["Might", "Reroll", "Calm", "Omen", "Grubstake"]
          and c[0]["icons"] == ["trail:" + k for k in ("might", "reroll", "calm", "omen", "grub")] and not c[0]["notes"],
          "trail: every upgrade type bought: its name, its sum by its kind, its icon key trail:<type>: %s %s" % (c[0]["amounts"], c[0]["icons"]))
    tb = c[0]["table"][0] if c[0]["table"] else {}
    check(tb.get("head") == ["upgrade", "id", "kind", "total", "written", "what it adds to"] and tb.get("rows", [[]])[0] == ["Might", "might", "percent", 0.12, "+12%", "Attack damage"],
          "trail: the card's table (its CSV): %s" % tb.get("head"))
    check(s6["short"] == "level 12" and s6["words"] == "Trail Level 12 of 60 \u00b7 14 of 100 nodes bought (11 paid for) \u00b7 3,450 gold spent", "trail: a record in short and in the facts' words: %s" % s6["words"])
    c = s5["cards"]
    check(len(c) == 1 and c[0]["title"] == "Upgrade board (before the Trail)" and c[0]["slug"] == "upgrade-board" and c[0]["tiles"][0][:2] == ["Ranks bought", "2 of 48"]
          and "talent:grit" in c[0]["icons"] and s5["short"] == "board 2 / 48",
          "trail: a schema 5 record (a board, no Trail) still draws its board, under the title Upgrade board (before the Trail): %s" % [(x["title"], x["tiles"][:1]) for x in c])
    c = both["cards"]
    check([x["title"] for x in c] == ["The Trail", "Upgrade board (before the Trail)"] and c[0]["tiles"][0][:2] == ["Trail Level", "12"]
          and c[0]["amounts"][:2] == ["+0.12", "+1"] and c[0]["names"][0] == "might" and any("OLD6" in n for n in c[0]["notes"]) and both["short"] == "level 12",
          "trail: a record from between the Trail's arrival and schema 6 draws both; its Trail names each type by its id with its plain sum: %s" % [(x["title"], x["amounts"][:2], x["notes"]) for x in c])
    c = old["cards"]
    check(len(c) == 1 and c[0]["title"] == "Upgrade board (before the Trail)" and old["short"] == "board 2 / 48", "trail: a record with only talents draws the old board: %s" % [x["title"] for x in c])
    c = none["cards"]
    check(len(c) == 1 and c[0]["title"] == "The Trail" and len(c[0]["notes"]) == 1 and "Neither the Trail nor the older Upgrade board" in c[0]["notes"][0] and none["short"] == "\u2013",
          "trail: a record with neither says so in one line: %s" % [x["notes"] for x in c])


def _replay_checks(check):
    import replay as RP
    tmp = tempfile.mkdtemp(prefix="le_dash115_rp_")
    try:
        # the Trail's file as a fixture (Garry edits the real one): five upgrade types, one of each kind, and three unlocks
        tf = os.path.join(tmp, "trail.json")
        with open(tf, "w", encoding="utf-8") as f:
            json.dump({"upgrades": {"might": {"name": "Might", "kind": "percent", "text": "Attack damage"}, "reroll": {"name": "Reroll", "kind": "count", "text": "Rerolls"},
                                    "calm": {"name": "Calm", "kind": "seconds", "text": "Untouchable time"}, "omen": {"name": "Omen", "kind": "word", "text": "A sign"},
                                    "grub": {"name": "Grubstake", "kind": "flat", "text": "Starting coins"}},
                       "nodes": [{"id": "n1", "level": 1, "gives": {"type": "upgrade", "upgrade": "might", "value": 0.06}},
                                 {"id": "n2", "level": 2, "gives": {"type": "upgrade", "upgrade": "might", "value": 0.065}},
                                 {"id": "n3", "level": 3, "gives": {"type": "outlaw", "id": "zz_fx_outlaw"}},
                                 {"id": "n4", "level": 4, "gives": {"type": "upgrade", "upgrade": "reroll", "value": 1}},
                                 {"id": "n5", "level": 5, "gives": {"type": "weapon", "id": "zz_fx_gun"}},
                                 {"id": "n6", "level": 6, "gives": {"type": "stage", "map": "zz_map", "stage": "s2"}},
                                 {"id": "n7", "level": 7, "gives": {"type": "upgrade", "upgrade": "calm", "value": 2}},
                                 {"id": "n8", "level": 8, "gives": {"type": "upgrade", "upgrade": "grub", "value": 25}},
                                 {"id": "n9", "level": 9, "gives": {"type": "upgrade", "upgrade": "omen", "value": 1}},
                                 {"id": "n10", "level": 10, "gives": {"type": "upgrade", "upgrade": "might", "value": 0.5}}]}, f)
        p = os.path.join(tmp, "x_replay.json")
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"kind": "88fits_replay", "look": "DM-G", "save": {"heroes_owned": ["zz_fx_outlaw"],
                       "trail": {"bought": ["n1", "n2", "n4", "n5", "n7", "n8", "n9", "gone1"], "spent": 4321, "had": ["stage:zz_map:s2"]}}}, f)
        lines = RP.trail_lines(p, tf)
        check(bool(lines) and lines[0] == "the Trail the run began with: 8 nodes paid for, 4,321 gold; 2 more count as bought at no cost (the save already had what they give)"
              and lines[-1] == "the outlaw's look: DM-G",
              "replay: replay.py prints the Trail (the nodes paid for, their gold, the ones the save already had) and the look: %s" % lines[:1])
        ups = [ln.split() for ln in lines[2:7]] if len(lines) > 7 else []
        check(len(lines) > 7 and lines[1].strip() == "upgrades, summed by type:"
              and [u[:2] for u in ups] == [["Might", "+12.5%"], ["Reroll", "+1"], ["Calm", "+2"], ["Omen", "bought"], ["Grubstake", "+25"]] and ups[2][2] == "s" and ups[0][2:] == ["Attack", "damage"],
              "replay: every upgrade type's sum by its kind (percent, count, seconds, word, flat), a node not bought left out: %s" % lines[2:7])
        rest = [ln.strip() for ln in lines[7:-1]]
        check(rest == ["outlaws: zz_fx_outlaw (the save had it)", "weapons: zz_fx_gun", "stages: zz_map s2 (the save had it)", "1 paid node is not in today's Trail file: gone1"],
              "replay: the unlocks bought by type (an outlaw owned and a stage the save had count at no cost), a paid node gone from the file named: %s" % rest)
        check(RP.amount_text("percent", 0.03) == "+3%" and RP.amount_text("percent", 0.025) == "+2.5%" and RP.amount_text("seconds", 2) == "+2 s"
              and RP.amount_text("count", 1.0) == "+1" and RP.amount_text("word", 1) == "" and RP.amount_text("flat", 0.3) == "+0.3",
              "replay: amount_text is Trail.amount_text")
        for flag in ("--trail", "--board"):
            r = subprocess.run([sys.executable, os.path.join(TOOLS, "replay.py"), flag, p], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
            got = [ln for ln in r.stdout.splitlines() if ln.startswith("replay: ")]
            said = any("--board is the old name for --trail" in ln for ln in got)
            check(r.returncode == 0 and any("the Trail the run began with: 8 nodes paid for, 4,321 gold" in ln for ln in got) and said == (flag == "--board"),
                  "replay: `replay.py %s <file>` prints the Trail%s: %s" % (flag, " and says it is --trail's old name" if flag == "--board" else "", got[:3]))
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"kind": "88fits_replay", "look": "DM-G", "save": {"talents": {"grit": {"picks": [0, 1]}, "drive": {"form": 1, "rank": 2}}, "talent_spent": 10}}, f)
        check(RP.trail_lines(p, tf) == ["the Trail: not in this recording (recorded before the Trail; its save had the old Upgrade board: 4 ranks, 10 gold paid)", "the outlaw's look: DM-G"],
              "replay: a recording from before the Trail says so and what its board held: %s" % RP.trail_lines(p, tf)[:1])
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"kind": "88fits_replay"}, f)
        check(RP.trail_lines(p, tf) == ["the Trail: not in this recording"], "replay: a recording without a save says so")
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"kind": "88fits_replay", "save": {"trail": {"bought": [], "spent": 0, "had": []}}}, f)
        check(RP.trail_lines(p, tf) == ["the Trail the run began with: 0 nodes paid for, 0 gold", "    no upgrade bought"], "replay: a fresh save's Trail: %s" % RP.trail_lines(p, tf))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

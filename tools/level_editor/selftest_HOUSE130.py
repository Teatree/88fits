"""Pass 130, lane HOUSE: every tool that shows a Trail Level also says what that level gives. selftest.py discovers this
file and hands it `check`, `run_node` and the `server` module. Nothing here runs Godot or touches the network.

Garry: "whenever we do show the level of trail, we also show the stats increases as just a bundle (a list of
comma-separated increases) ... in one build, the trail is giving one set of stat increases and in the other build it's
giving a different set. It's important to know which is which."

The bundle is one line ("Attack damage +12%, Max HP +30, Rerolls +2 · unlocks: 2 outlaws, 3 items, 1 stage"; "nothing
yet") with three writers: game/core/systems/Trail.gd (bundle_text, tally; game/tests/pass130_HOUSE_test.gd),
tools/level_editor/trail_bundle.js and tools/trail_bundle.py. All three read game/tests/fixtures/trail_bundle.json.

Groups:
  fixture  trail_bundle.js under node and trail_bundle.py read every fixture row the same: the blocks (empty, percent,
           count, seconds, flat, word, a loss, a sum of 0, unlocks, a block with its own types, an older block without),
           the tallies of node ids, a tool's trail= argument (the level, the nodes, the line)
  real     on the game's own Trail file the two give the same line at every Trail Level, with and without the optional
           nodes (whatever Garry's nodes are today), and the same nodes as sim_batch.py's own trail_ids_upto
  page     the dashboard and the Level Editor load trail_bundle.js; the dashboard's functions run under node on a
           made-up DOM: the Trail card's first line is the bundle (the record's own line, or worked out for a record
           without), the facts line, a row's hover hint, the warning for runs at one level with different bundles
  tools    analytics_csv.py's index row carries trail_bundle; sim_batch.py's settings_trail_bundle and watch.py's
           trail_gives read a game folder's Trail file; replay.py's trail_gave_lines prints the recording's own line and
           says when today's file would give something else; the Sim tab shows the line beside the Trail control and in
           a finished sim's header; sim_run.gd, the probe and the Watch name it
"""
import json
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
FIXTURE = os.path.join(ROOT, "game", "tests", "fixtures", "trail_bundle.json")
TRAIL = os.path.join(ROOT, "game", "content", "trail", "trail.json")

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const TB = require(path.join(dir, 'trail_bundle.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const fx = q.fixture;
  const out = {};
  out.cases = fx.cases.map((c) => TB.text(c.block, c.build ? fx.trail.upgrades : null));
  out.tallies = fx.tallies.map((c) => { const t = TB.tally(fx.trail, c.ids); return { t, ups: Object.keys(t.upgrades), uns: Object.keys(t.unlocks), line: TB.text(t, fx.trail.upgrades) }; });
  out.args = fx.args.map((c) => { const r = TB.forArg(fx.trail, c.arg, c.optional); return r ? { level: r.level, ids: r.ids, line: r.bundle } : { level: -1, ids: [], line: '' }; });
  out.levels = TB.levelsOf(fx.trail);
  out.of = [TB.of(null), TB.of({ bundle: 'its own line', upgrades: { might: 1 } }), TB.of({ upgrades: { might: 0.12 }, types: { might: { kind: 'percent', text: 'Attack damage' } } }), TB.of({})];
  out.kinds = TB.kinds([{ bundle: 'A' }, { bundle: 'B' }, { bundle: 'A' }, null, {}]);
  const real = q.real;
  out.real = [];
  if (real) {
    const top = TB.levelsOf(real);
    for (let lv = 0; lv <= top; lv++) for (const opt of [false, true]) { const r = TB.forArg(real, String(lv), opt); out.real.push([lv, opt, r.ids, r.bundle]); }
    out.realNamed = ['none', 'quarter', 'half', 'full'].map((a) => TB.forArg(real, a, false).level);
  }
  // the dashboard's own functions on a made-up DOM
  if (q.src) {
    const mk = (tag, cls, text) => ({ tag, cls: cls || '', text: text == null ? '' : String(text), kids: [], style: {}, title: '', appendChild(k) { this.kids.push(k); return k; } });
    const fmtI = (n) => (n == null || n === '' || isNaN(n)) ? '–' : Math.round(+n).toLocaleString('en-US');
    const card = (title, desc, opts) => { const c = mk('card'); c.ctitle = title; c._tables = []; return c; };
    const tileIn = (wrap, lbl, val, sub) => { const t = mk('tile'); wrap.appendChild(t); return t; };
    const tableView = () => {};
    const iconEl = () => mk('ico');
    const doc = { createTextNode: (t) => mk('#text', '', t) };
    const F = new Function('el', 'fmtI', 'titleCase', 'card', 'tileIn', 'tableView', 'iconEl', 'hoverTip', 'TrailBundle', 'document',
      "const OLD_WORDS = 'OLDW', BOARD_MAX_OLD = 48, TRAIL_OLD_WORDS = 'OLD6';\n" + q.src +
      "\nreturn { renderTrail, trailBundle, trailMixes, trailHint, trailShort };")(mk, fmtI, String, card, tileIn, tableView, iconEl, () => {}, TB, doc);
    out.bundles = q.records.map((r) => F.trailBundle(r));
    out.cards = q.records.map((r) => {
      const grid = mk('grid'); F.renderTrail(grid, { run: r });
      const c = grid.kids[0]; const first = c && c.kids[0];
      return first ? { cls: first.cls, text: first.kids.map((k) => k.text).join(''), title: first.title, next: c.kids[1] ? c.kids[1].cls : '' } : null;
    });
    out.mixes = F.trailMixes(q.mixRuns);
    out.hints = q.records.map((r) => F.trailHint(mk('td'), r).title);
  }
  process.stdout.write(JSON.stringify(out));
});
"""


def _close(a, b):
    return abs(float(a) - float(b)) < 1e-6


def checks(check, run_node, server):
    import trail_bundle as TB
    fx = json.load(open(FIXTURE, encoding="utf-8"))
    trail = fx["trail"]
    real = TB.read_trail(TRAIL)

    # ---- fixture: the Python
    bad = [c["name"] for c in fx["cases"] if TB.bundle_text(c["block"], trail["upgrades"] if c.get("build") else None) != c["want"]]
    check(len(fx["cases"]) > 15 and not bad, "fixture: trail_bundle.py reads every fixture block (%d): %s" % (len(fx["cases"]), bad[:3]))
    bad = []
    for c in fx["tallies"]:
        t = TB.tally(trail, c["ids"])
        if (list(t["upgrades"]) != list(c["upgrades"]) or list(t["unlocks"].items()) != list(c["unlocks"].items())
                or not all(_close(t["upgrades"][k], c["upgrades"][k]) for k in c["upgrades"]) or TB.bundle_text(t, trail["upgrades"]) != c["want"]):
            bad.append(c["name"])
    check(not bad, "fixture: trail_bundle.py adds up node ids (the file's order of types, the unlocks by gift type): %s" % bad[:3])
    bad = []
    for c in fx["args"]:
        lv = TB.level_of(c["arg"], TB.levels_of(trail))
        ids = TB.ids_upto(trail, lv, c["optional"]) if lv >= 0 else []
        if lv != c["level"] or ids != c["ids"] or TB.for_arg(c["arg"], c["optional"], trail) != c["want"]:
            bad.append(c["arg"])
    check(not bad, "fixture: trail_bundle.py names the Trail of a trail= argument (level, nodes, line): %s" % bad[:3])
    check(TB.of(None) == "" and TB.of({"bundle": "its own line", "upgrades": {"might": 1}}) == "its own line" and TB.of({}) == "nothing yet",
          "fixture: trail_bundle.py of(): a record's own line wins, a block without is worked out, no block is ''")

    # ---- the JavaScript, the same rows
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    names = ("trailAmount", "trailOf", "trailWords", "trailBundle", "trailMixes", "trailHint", "trailShort", "renderTrail", "boardOf", "boardShort", "renderBoard")
    parts = [re.search(r"\n  function %s\(.*?\n  \}\n" % n, html, re.S) for n in names]
    check(all(parts), "page: the dashboard's Trail functions are found: %s" % [n for n, m in zip(names, parts) if not m])
    types = {"might": {"name": "Might", "kind": "percent", "text": "Attack damage"}, "reroll": {"name": "Reroll", "kind": "count", "text": "Rerolls"}}
    blk = {"level": 12, "levels": 60, "bought": ["a", "b"], "nodes": 100, "paid": 2, "spent": 300, "upgrades": {"might": 0.12, "reroll": 2}, "types": types}
    own = dict(blk, bundle="Attack damage +12%, Rerolls +2 · unlocks: 1 outlaw", unlocks={"outlaw": 1})
    other = dict(blk, bundle="Damage +20%, Rerolls +2")
    recs = [{"schema": 6, "trail": own}, {"schema": 6, "trail": blk}, {"schema": 5}, {"trail_level": 7, "trail_bundle": "Max HP +30"}, {"trail_level": 7}]
    mix = [{"trail": own}, {"trail": other}, {"trail": own}, {"trail": dict(own, level=3)}, {"trail_level": 12, "trail_bundle": "Damage +20%, Rerolls +2"}, {"trail_level": 5}]
    out = run_node({"fixture": fx, "real": real or None, "src": "".join(m.group(0) for m in parts) if all(parts) else "", "records": recs, "mixRuns": mix}, RUNNER)
    if out is None:
        print("HOUSE130: node is not here: trail_bundle.js's checks are skipped")
    elif out:
        bad = [c["name"] for c, got in zip(fx["cases"], out["cases"]) if got != c["want"]]
        check(not bad, "fixture: trail_bundle.js reads every fixture block as Trail.gd and the Python do: %s" % bad[:3])
        bad = [c["name"] for c, got in zip(fx["tallies"], out["tallies"])
               if got["ups"] != list(c["upgrades"]) or got["uns"] != list(c["unlocks"]) or got["line"] != c["want"]
               or not all(_close(got["t"]["upgrades"][k], c["upgrades"][k]) for k in c["upgrades"]) or got["t"]["unlocks"] != c["unlocks"]]
        check(not bad, "fixture: trail_bundle.js adds up node ids the same: %s" % bad[:3])
        bad = [c["arg"] for c, got in zip(fx["args"], out["args"]) if got["level"] != c["level"] or got["ids"] != c["ids"] or got["line"] != c["want"]]
        check(not bad and out["levels"] == TB.levels_of(trail), "fixture: trail_bundle.js names the Trail of a trail= argument the same: %s" % bad[:3])
        check(out["of"] == ["", "its own line", "Attack damage +12%", "nothing yet"] and out["kinds"] == [["A", 2], ["B", 1], ["nothing yet", 1]],
              "fixture: trail_bundle.js of() and kinds(): %s %s" % (out["of"], out["kinds"]))
        # ---- real: the game's own file, level by level
        if real:
            import sim_batch as SB
            nodes = SB.trail_nodes(TRAIL)
            diff = [(lv, opt) for lv, opt, ids, line in out["real"]
                    if line != TB.for_arg(str(lv), opt, real) or ids != TB.ids_upto(real, lv, opt) or ids != SB.trail_ids_upto(nodes, lv, opt)]
            top = TB.levels_of(real)
            check(len(out["real"]) == 2 * (top + 1) and not diff,
                  "real: on game/content/trail/trail.json the JavaScript, the Python and sim_batch agree at every Trail Level (0 to %d, with and without the optional nodes): %s" % (top, diff[:4]))
            check(out["realNamed"] == [TB.level_of(a, top) for a in ("none", "quarter", "half", "full")] == [SB.trail_level_of(a, top) for a in ("none", "quarter", "half", "full")],
                  "real: none, a quarter, half and full name the same levels everywhere: %s" % out["realNamed"])
            check(out["real"][0][3] == "nothing yet" and (top == 0 or out["real"][-1][3] != "nothing yet"), "real: Trail Level 0 gives nothing yet, the top level something")
        # ---- page: the dashboard's functions
        if out.get("cards"):
            check(out["bundles"] == [own["bundle"], "Attack damage +12%, Rerolls +2", "", "Max HP +30", ""],
                  "page: a run's bundle: the record's own line, worked out for a record without, an index row's trail_bundle, '' when none: %s" % out["bundles"])
            c0, c1 = out["cards"][0], out["cards"][1]
            check(bool(c0) and c0["cls"] == "trail-gave" and c0["text"] == "Gave: " + own["bundle"] and "build that played" in c0["title"] and c0["next"] == "tiles",
                  "page: the Trail card's first line is what the Trail gave, before the tiles: %s" % c0)
            check(bool(c1) and c1["text"] == "Gave: Attack damage +12%, Rerolls +2" and "worked out here" in c1["title"],
                  "page: a record without its own line has it worked out, and the hint says so: %s" % c1)
            check(out["hints"] == ["the Trail gave: " + own["bundle"], "the Trail gave: Attack damage +12%, Rerolls +2", "", "the Trail gave: Max HP +30", ""],
                  "page: a run row's Trail cell says what the Trail gave on hover: %s" % out["hints"])
            m = out["mixes"]
            check(len(m) == 1 and m[0]["level"] == "level 12" and m[0]["kinds"] == [[own["bundle"], 2], ["Damage +20%, Rerolls +2", 2]],
                  "page: runs at one Trail Level with different bundles are found (one level, two bundles; a level with one bundle and a run that does not say are left out): %s" % m)
    check('<script src="../tools/level_editor/trail_bundle.js"></script>' in html and "'trail_spent', 'trail_bundle', 'talents'" in html
          and "add('The Trail gave', tb)" in html and "These runs come from builds whose Trail gave different things" in html and "if (j === 7) trailHint(" in html,
          "page: the dashboard loads trail_bundle.js, names the bundle on the facts line, warns when averaged runs differ, hints the lists' Trail cells")
    index = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
    simjs = open(os.path.join(HERE, "sim.js"), encoding="utf-8").read()
    check(index.find('<script src="trail_bundle.js"></script>') > 0 and index.find('<script src="trail_bundle.js"></script>') < index.find('<script src="sim.js"></script>'),
          "page: the Level Editor loads trail_bundle.js before the Sim tab")
    check("TrailBundle.forArg(S.trailDoc, f.trail, !!f.trail_optional)" in simjs and "'Gives: '" in simjs and "'The Trail gave: ' + meta.trail_bundle" in simjs
          and "These runs come from builds whose Trail gave different things" in simjs,
          "page: the Sim tab says what the Trail gives beside its control and in a finished sim's header (a warning when its runs differ)")

    # ---- tools
    import analytics_csv as AC
    row = AC.index_row({"schema": 6, "stamp": "2026-11-06T10-00-00", "trail": own}, "x.json")
    row2 = AC.index_row({"schema": 6, "stamp": "2026-11-06T10-00-00", "trail": blk}, "y.json")
    check(row.get("trail_bundle") == own["bundle"] and row2.get("trail_bundle") == "Attack damage +12%, Rerolls +2"
          and AC.HISTORY_FIRST.index("trail_spent") + 1 == AC.HISTORY_FIRST.index("trail_bundle"),
          "tools: analytics_csv.py's index row carries trail_bundle (the record's own line; worked out without one), after trail_spent")
    tmp = tempfile.mkdtemp(prefix="le_house130_")
    try:
        os.makedirs(os.path.join(tmp, "content", "trail"))
        tf = os.path.join(tmp, "content", "trail", "trail.json")
        json.dump(trail, open(tf, "w", encoding="utf-8"))
        import sim_batch as SB
        import watch as W
        import replay as RP
        half = next(c["want"] for c in fx["args"] if c["arg"] == "half" and not c["optional"])
        check(SB.settings_trail_bundle({"trail": "half"}, tmp) == half and SB.settings_trail_bundle({"trail": "none"}, tmp) == "nothing yet"
              and SB.settings_trail_bundle({"board_was": "a quarter", "trail": "quarter"}, tmp) == "",
              "tools: sim_batch.py says what a sim's Trail gives from a game folder's Trail file (nothing for a sim of the old board)")
        check(W.trail_gives("half", False, [], tmp) == half and W.trail_gives("save", False, ["a2", "c1"], tmp) == "Max HP +30 · unlocks: 1 outlaw"
              and W.trail_gives("none", False, [], tmp) == "nothing yet",
              "tools: watch.py says what the Watch's Trail gives (a level, or the PC save's own nodes)")
        p = os.path.join(tmp, "x_replay.json")
        save = {"heroes_owned": ["astro"], "trail": {"bought": ["a1", "a2"], "spent": 90, "had": []}}
        json.dump({"kind": "88fits_replay", "save": save}, open(p, "w", encoding="utf-8"))
        today = "Attack damage +5%, Max HP +30 · unlocks: 1 outlaw"
        got = RP.trail_gave_lines(p, tf)
        check(got == ["the Trail gave (worked out from today's Trail file; the recording carries no line of its own): " + today],
              "tools: replay.py works the line out for a recording without one (an outlaw the save owns counts): %s" % got)
        json.dump({"kind": "88fits_replay", "save": save, "trail": {"level": 1, "levels": 8, "bundle": today}}, open(p, "w", encoding="utf-8"))
        got = RP.trail_gave_lines(p, tf)
        check(got == ["the Trail gave (Trail Level 1 of 8), as the build that recorded it wrote: " + today], "tools: replay.py prints the recording's own line: %s" % got)
        json.dump({"kind": "88fits_replay", "save": save, "trail": {"level": 1, "levels": 8, "bundle": "Damage +9%"}}, open(p, "w", encoding="utf-8"))
        got = RP.trail_gave_lines(p, tf)
        check(len(got) == 2 and got[0].endswith("wrote: Damage +9%") and got[1].strip() == "today's Trail file would give those nodes something else: " + today,
              "tools: replay.py says when today's Trail file would give those nodes something else: %s" % got)
        json.dump({"kind": "88fits_replay", "save": {"talents": {}}}, open(p, "w", encoding="utf-8"))
        check(RP.trail_gave_lines(p, tf) == [], "tools: a recording from before the Trail has no such line")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    src = {n: open(os.path.join(ROOT, *n.split("/")), encoding="utf-8").read() for n in (
        "game/tools/sim_run.gd", "game/tools/difficulty_probe.gd", "game/tools/watch/Watch.gd", "game/tools/trail_arg.gd", "tools/sim_batch.py", "tools/posthog_boards.py")}
    check('"trail_bundle": str(_trail_info.get("bundle", ""))' in src["game/tools/sim_run.gd"] and 'res["meta"]["trail_bundle"] = rows[0][0]' in src["tools/sim_batch.py"]
          and 'res["meta"]["trail_bundles"]' in src["tools/sim_batch.py"],
          "tools: a sim's runs say what their Trail gave (sim_run.gd's meta) and the result keeps it (the runs that differ listed)")
    check('"bundle": Trail.bundle()' in src["game/tools/trail_arg.gd"] and "probe: the Trail gives" in src["game/tools/difficulty_probe.gd"]
          and "watch: the Trail gives" in src["game/tools/watch/Watch.gd"],
          "tools: trail_arg.gd hands every tool the bundle; the probe's header and the Watch's console line print it")
    pb = src["tools/posthog_boards.py"]
    check('("88fits · Trail"' in pb and "TRAIL_MILESTONES = [5, 10, 20, 30, 45, 60, 70]" in pb and "properties.trail_bundle AS the_trail_gives" in pb
          and "quantile(0.25)" in pb and "runs_to_reach" in pb and "coins_spent" in pb,
          "tools: posthog_boards.py has the board 88fits · Trail (the distribution, the quartiles, the milestones, runs to reach a level, coins, the bundle by build)")

"""Pass 77, lane SIMUI: the run sim's driver (tools/sim_batch.py), its job kind (jobs.py "sim"), its routes (sim_io.py)
and the Sim tab's page-free maths (sim_model.js). selftest.py discovers this file and hands it `check`, `run_node` and
the `server` module. Nothing here runs Godot or writes under game/ or tools/dl/sim: every folder is a temporary one.

Groups:
  agg      the averaging by hand on three tiny runs (the playing count, means over the runs still playing, the 5 s DPS
           smoothing, p10/p90, deaths over every run carried past a run's end, a gap in t carried, breakdown means and
           their order, the stage and boss medians, the summary from each run's own end, a failed run left out) and on
           made-up runs in lane SIMRUN's schema (shapes, head.json, --aggregate again)
  sync     the snapshot: what is copied, skipped (export, reports, .godot), deleted and kept (the snapshot's own .import
           and .uid), the .godot seed, project.godot's own user folder (idempotent), every import reason and none for a
           plain script edit, content JSONs newer than their .tres
  lock     the sim lock: taken, refused while held, a dead owner reclaimed, a folder without owner.json never
  job      the kind "sim": its lane and fields, the checks, the plan (the driver's argv, its own folders, no lock),
           the stages and the parser, the title and the ETA, a real run of the driver (--synthetic) through the job
           worker's own functions to done with its result, a cancel that kills the tree, a re-queue's own folder
  routes   /api/sim/settings, history, result/<id>, keep, delete, run (refused, queued, refused while one runs), status,
           unlock; ids that are not a sim folder refused
  page     sim_model.js under Node: the twelve charts and their words, the folds (7 + Other, colours shared by the
           creature charts, never reused), the ticks and labels, the readout, the table and the CSV, the settings'
           checks, and its ETA against sim_batch.eta_seconds; index.html / app.js / jobs.js wiring
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'sim_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  const defs = M.charts(q.res, null, {});
  out.ids = defs.map((c) => c.id);
  out.how = defs.map((c) => [c.id, c.title, c.how.length, c.lines.length, c.bands.length, c.stack ? c.stack.items.length + (c.stack.other ? 1 : 0) : 0, c.overlay.length]);
  const cmp = M.charts(q.res, q.cmp, { cmpLabel: 'B' });
  out.overlays = cmp.map((c) => [c.id, c.overlay.length, c.overlay.length ? c.overlay[0].label : '']);
  out.raw = M.charts(q.res, null, { raw: true }).find((c) => c.id === 'dps');
  out.raw = [out.raw.lines[0].key, out.raw.bands.length];
  out.max = defs.map((c) => [c.id, M.chartMax(c)]);
  const dps = defs.find((c) => c.id === 'dps');
  out.read = M.readout(dps, q.t);
  const kills = defs.find((c) => c.id === 'kills');
  out.readKills = M.readout(kills, q.t).map((r) => [r.kind, r.label]);
  const alive = defs.find((c) => c.id === 'alive_by');
  const colA = {}, colK = {};
  for (const it of alive.stack.items) colA[it.id] = it.color;
  for (const it of kills.stack.items) colK[it.id] = it.color;
  out.shared = Object.keys(colA).filter((id) => colK[id]).map((id) => colA[id] === colK[id]);
  out.palette = Array.from(new Set(Object.values(colA).concat(Object.values(colK))));
  out.table = M.table(dps, 60, q.res.t.length - 1);
  out.table = [out.table.head, out.table.rows.length, out.table.rows[0][0], out.table.rows[out.table.rows.length - 1][0]];
  out.csv = M.csv(dps, q.res.t.length - 1).split('\n').slice(0, 3);
  out.tiles = M.tiles(q.res).map((t) => [t.label, t.value]);
  // a breakdown of ten ids folds to seven and Other, in first-seen order, colours from the slots in order
  const bd = { kind: 'cum', mean: {}, score: {} };
  for (let i = 0; i < 10; i++) { const id = 'c' + i; bd.mean[id] = [0, i === 3 ? 0 : 1, 2 + i]; bd.score[id] = 10 - i; }
  const f = M.fold(bd, { c0: 'Zero' }, 7);
  out.fold = { ids: f.items.map((x) => x.id), colors: f.items.map((x) => x.color), other: f.other ? [f.other.label, f.other.ids, f.other.values] : null, label0: f.items.find((x) => x.id === 'c0').label };
  const small = { kind: 'cum', mean: { a: [1, 2], b: [0, 1] }, score: { a: 2, b: 1 } };
  const f2 = M.fold(small, {}, 7);
  out.fold2 = [f2.items.length, !!f2.other];
  // a pinned colour map with every slot used: a new id goes into Other, never a grey item
  const pin = {}; M.SLOTS.forEach((c, i) => { pin['p' + i] = c; });
  const f3 = M.fold({ kind: 'cum', mean: { x: [0, 5], p0: [0, 1] }, score: { x: 5, p0: 1 } }, {}, 7, pin);
  out.fold3 = [f3.items.map((x) => x.id), f3.other ? f3.other.ids : null];
  // the readout names the three biggest inside Other at that second
  const bdo = { kind: 'level', mean: {}, score: {} };
  for (let i = 0; i < 10; i++) { bdo.mean['c' + i] = [i, i + 1]; bdo.score['c' + i] = 10 - i; }
  const ro = { settings: { players: 2 }, summary: { ok: 2 }, series: {}, playing: [2, 2], t: [0, 1], names: { c9: 'Nine' }, breakdowns: { alive_by: bdo } };
  out.otherSub = M.readout(M.charts(ro, null, {}).find((c) => c.id === 'alive_by'), 1).filter((r) => r.label.startsWith('Other')).map((r) => [r.label, r.value, r.sub]);
  out.ticks = [M.timeTicks(1500, 700), M.timeTicks(120, 700), M.yTicks(M.niceMax(640, 4), 4), M.niceMax(0, 4), M.niceMax(97, 4)];
  out.labels = [M.tickLabel(5000, 15000), M.tickLabel(2500, 4000), M.tickLabel(2e6, 3e6), M.tickLabel(25, 100, 'pct'), M.tickLabel(0, 1e6)];
  out.fmt = [M.fmtT(1500), M.fmtT(59.6), M.fmtT(3725), M.parseT('25:00'), M.parseT('1500'), M.parseT('7m'), M.parseT('x'), M.fmtNum(1234.4), M.fmtNum(12345), M.fmtNum(2.345), M.fmtNum(1.5e6)];
  out.names = [M.shortName('The Tumbleweed King'), M.shortName('Gila Grande'), M.shortName('Brander')];
  out.clean = q.clean.map((s) => { const c = M.cleanSettings(s, { max_workers: 14, max_players: 100 }); return [c.settings.players, c.settings.workers, c.settings.limit, c.settings.death, c.problems.length]; });
  out.eta = q.eta.map((e) => M.etaSeconds(e.s, e.speed, e.cores, e.sync));
  out.smooth = M.smooth([10, 0, 0, 0, 0, 10, null, 4, 4], 5);
  out.settingsLine = M.settingsLine({ players: 10, limit: 1500, board: 1.5, death: 'gold', seed: 3, hero: 'drifter' }, 'Drifter');
  out.fastLine = M.settingsLine({ players: 2, limit: 120, board: 0, death: 'end', seed: 1, hero: 'drifter', fast: false }, 'Drifter');
  out.fastClean = [M.cleanSettings({}).settings.fast, M.cleanSettings({ fast: false }).settings.fast, M.cleanSettings({ fast: 'off' }).settings.fast, M.cleanSettings({ fast: true }).settings.fast];
  out.sections = M.SECTIONS.map((x) => x.id);
  out.secOf = {}; for (const c of defs) if (['dps', 'playing', 'danger', 'gold', 'build'].includes(c.id)) out.secOf[c.id] = c.section;
  out.lacking = M.missing(q.res);
  out.lackingBare = M.missing(q.bare);
  out.idsBare = M.charts(q.bare, null, {}).map((c) => c.id);
  const dg = defs.find((c) => c.id === 'danger');
  const rg = M.chartRange(dg);
  out.range = [rg.lo, rg.hi, M.yTicksRange(rg.lo, rg.hi, 5)];
  out.board = [M.setRank('AAB', 2), M.setRank('AB', 4), M.setRank('', 3, 1), M.picksWords('AAB', [{ name: 'Padding' }, { name: 'Plate' }]),
    M.boardWords({ talents: { grit: 'AA', study: 'BB' }, board: -1, board_label: 'my save' }), M.boardRanks({ grit: 'AAB', drive: 'A' }),
    (M.presetOf({ grit: 'AA' }, [{ key: 'x', talents: { grit: 'AA' } }]) || {}).key, M.presetOf({ grit: 'A' }, [{ key: 'x', talents: { grit: 'AA' } }])];
  out.secTicks = [M.tickLabel(150, 150, 'sec'), M.tickLabel(50, 100, 'sec'), M.fmtVal(1.234, 'pct1'), M.fmtVal(1.4, 'mult')];
  // a partial result (5 of 10 runs in): the share of runs playing is of the 5, not of the 10 asked for
  const part = Object.assign({}, q.res, { settings: Object.assign({}, q.res.settings, { players: 10 }) });
  out.partial = [M.runsIn(part), M.runsIn({ playing: [3, 3], settings: { players: 10 } }), M.runsIn({ settings: { players: 7 } }),
    M.charts(part, null, {}).find((c) => c.id === 'playing').lines[0].values[0]];
  process.stdout.write(JSON.stringify(out));
});
"""


def _write(path, text, mtime=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    if mtime is not None:
        os.utime(path, (mtime, mtime))


def _tiny_players():
    """Three hand-made runs of 10 s: A plays to 10, B dies at 5 (death=end), C plays to 10 with a gap at t=4."""
    def run(ts, hp, dps, kills, deaths, level, alive_by=None, kills_by=None, events=None, end_reason="limit"):
        n = len(ts)
        d = {"t": ts, "hp": hp, "hp_max": [100] * n, "dps": dps, "est": [10] * n, "alive": [5] * n, "press_hp": [50] * n,
             "press_dmg": [5] * n, "kills": kills, "deaths": deaths, "level": level, "gold_total": list(range(n)),
             "xp_total": [x * 2 for x in range(n)], "clock": ts, "stage": [1] * n,
             "kills_by": kills_by or {"goblin": kills}, "alive_by": alive_by or {"goblin": [5] * n},
             "dmg_by": {"revolver": [sum(dps[:i + 1]) for i in range(n)]}, "events": events or [],
             "meta": {"end_reason": end_reason, "end_t": float(ts[-1]), "wall_s": 20.0, "boot_s": 10.0, "build_text": "Revolver 1"}}
        return d
    a = run(list(range(1, 11)), [100] * 10, [10, 0, 0, 0, 0, 10, 0, 0, 0, 0], list(range(1, 11)), [0] * 10, [1, 1, 2, 2, 2, 3, 3, 3, 4, 4],
            kills_by={"goblin": list(range(1, 11)), "slime": [0] * 7 + [1, 2, 3]},
            events=[{"t": 0, "kind": "stage", "stage": 1}, {"t": 4, "kind": "boss_start", "id": "king", "mult": 1.2, "hp": 500},
                    {"t": 7, "kind": "boss_end", "id": "king"}, {"t": 8, "kind": "stage", "stage": 2}])
    b = run([1, 2, 3, 4, 5], [100, 80, 60, 20, 0], [20] * 5, [1, 2, 3, 4, 5], [0, 0, 0, 0, 1], [1, 1, 1, 2, 2],
            events=[{"t": 3, "kind": "boss_start", "id": "king", "mult": 0.8, "hp": 400}, {"t": 5, "kind": "death"}], end_reason="death")
    c = run([1, 2, 3, 5, 6, 7, 8, 9, 10], [90, 90, 90, 70, 70, 70, 70, 70, 70], [0] * 9, [2, 4, 6, 8, 10, 12, 14, 16, 18], [0] * 9,
            [1, 1, 1, 1, 2, 2, 2, 2, 2], events=[{"t": 6, "kind": "boss_start", "id": "king"}, {"t": 9, "kind": "boss_end", "id": "king"},
                                                 {"t": 10, "kind": "stage", "stage": 2}])
    return a, b, c


def _agg_checks(check, SB, tmp):
    a, b, c = _tiny_players()
    a["meta"].update(unlocks="all", assists=1)
    b["meta"].update(unlocks="all", assists=2)
    players = [(1, a, {"seed": 1}), (2, b, {"seed": 2}), (3, c, {"seed": 3}), (4, None, {"seed": 4, "problem": "no JSON written", "end_t": 0})]
    r = SB.aggregate(players, {"players": 4, "limit": 10, "death": "end"}, {"partial": False}, game_dir=os.path.join(tmp, "nogame"))
    check(r["t"] == list(range(11)), "agg: one entry a second 0..T (T = the longest run): %s" % r["t"][-1])
    check(r["playing"] == [3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2], "agg: the runs still playing (B ends at 5, the failed run never counts): %s" % r["playing"])
    hp = r["series"]["hp"]["mean"]
    check(abs(hp[1] - (100 + 100 + 90) / 3.0) < 0.01 and abs(hp[7] - (100 + 70) / 2.0) < 0.01, "agg: HP the mean over the runs still playing: %s %s" % (hp[1], hp[7]))
    check(abs(hp[4] - (100 + 20 + 90) / 3.0) < 0.01, "agg: a missing second (C has no t=4) carries the second before: %s" % hp[4])
    check(abs(hp[0] - (100 + 100 + 90) / 3.0) < 0.01, "agg: second 0 takes each run's first row: %s" % hp[0])
    # DPS: A's [10,0,0,0,0,10] smoothed over 5 s, B 20 flat, C 0
    dps = r["series"]["dps"]["mean"]
    a5 = 10 / 5.0      # at t=5: A's window 1..5 holds 10,0,0,0,0
    check(abs(dps[5] - (a5 + 20 + 0) / 3.0) < 0.01, "agg: DPS smoothed over 5 s per run, then averaged: %s" % dps[5])
    check(abs(r["series"]["dps_raw"]["mean"][6] - (10 + 0) / 2.0) < 0.01, "agg: the raw per-second DPS kept as dps_raw: %s" % r["series"]["dps_raw"]["mean"][6])
    lv = r["series"]["level"]
    # at t=2: A 1, B 1, C 1 -> p10 = p90 = 1; at t=5: A 2, B 2, C 1 -> sorted [1,2,2]: p10 = 1.2, p90 = 2
    check(abs(lv["p10"][5] - 1.2) < 1e-6 and abs(lv["p90"][5] - 2.0) < 1e-6, "agg: p10/p90 linear between the nearest ranks: %s %s" % (lv["p10"][5], lv["p90"][5]))
    de = r["series"]["deaths"]
    check(de["over"] == "all" and abs(de["mean"][5] - 1 / 3.0) < 0.01 and abs(de["mean"][10] - 1 / 3.0) < 0.01,
          "agg: deaths averaged over every run, an ended run keeping its count: %s" % de["mean"])
    kb = r["breakdowns"]["kills_by"]
    check(kb["kind"] == "cum" and kb["order"][0] == "goblin" and abs(kb["mean"]["slime"][10] - 3 / 2.0) < 0.01,
          "agg: a breakdown's id a run never had counts 0 for it (slime at 10: (3 + 0) / 2): %s" % kb["mean"]["slime"][10])
    mk = r["markers"]
    king = [x for x in mk["bosses"] if x["id"] == "king"]
    check(len(king) == 1 and king[0]["start"] == 4 and king[0]["n"] == 3 and king[0]["beaten"] == 2 and king[0]["end"] == 8,
          "agg: a boss's start and end the medians of the runs that met it (start 3,4,6 -> 4; end 7,9 -> 8): %s" % king)
    check(abs((king[0]["mult"] or 0) - 1.0) < 1e-6, "agg: the boss's HP pegging the median of the runs that report it: %s" % king[0]["mult"])
    check(king[0]["fight_s"] == 3, "agg: a fight's length from each run's own start and end (A 4-7, C 6-9): %s" % king[0]["fight_s"])
    check(mk["stages"] == [{"stage": 2, "t": 9, "n": 2, "min": 8, "max": 10}], "agg: a stage start the median of the runs that got there: %s" % mk["stages"])
    check(r["meta"].get("unlocks") == "all" and r["meta"].get("assists") == 3, "agg: the header says every item was unlocked and counts the bot's assists: %s" % r["meta"])
    sm = r["summary"]
    check(sm["players"] == 4 and sm["ok"] == 3 and sm["failed"] == 1 and sm["reached_limit"] == 2, "agg: the summary counts (2 of 3 reached the stop, 1 failed): %s" % sm)
    check(abs(sm["kills_mean"] - (10 + 5 + 18) / 3.0) < 0.05 and abs(sm["deaths_mean"] - 1 / 3.0) < 0.01, "agg: the summary from each run's own end: %s" % sm)
    pl = {p["k"]: p for p in r["players"]}
    check(pl[2]["end_reason"] == "death" and pl[4]["ok"] is False and pl[4]["problem"] == "no JSON written", "agg: per run its end and a failed run's reason: %s" % pl[4])
    check(pl[1]["rate"] is None, "agg: a run under 30 s of play is too short to measure a speed: %s" % pl[1]["rate"])
    check(all(len(v) == 11 for s_ in r["series"].values() for v in s_.values() if isinstance(v, list)), "agg: every series as long as t")
    # made-up runs in lane SIMRUN's schema
    st = {"players": 4, "limit": 600, "death": "gold"}
    ps = []
    for k in range(1, 5):
        d = SB.synthetic_player(k, k, st)
        path = os.path.join(tmp, "synth", "players", "p%02d.json" % k)
        SB.write_json(path, d)
        dd, prob = SB.load_player(path)
        check(dd is not None and not prob, "agg: a made-up run loads: %s" % prob)
        ps.append((k, dd, {"seed": k}))
    res = SB.aggregate(ps, st, {}, game_dir=os.path.join(tmp, "nogame"))
    T = len(res["t"]) - 1
    full = [p for p in res["players"] if p["end_t"] and p["end_t"] >= 30]
    check(full and all(abs(p["rate"] - p["end_t"] / (p["wall_s"] - 12.0)) < 0.02 for p in full),
          "agg: a run's speed from its meta (play over wall less boot): %s" % [(p["end_t"], p["wall_s"], p["rate"]) for p in full][:2])
    check(0 < T <= 600 and all(len(a_) == T + 1 for bd in res["breakdowns"].values() for a_ in bd["mean"].values()), "agg: the breakdowns as long as t (T=%d)" % T)
    check({"dmg_by", "kills_by", "alive_by", "gold_by"} <= set(res["breakdowns"]) and res["breakdowns"]["gold_by"]["kind"] == "cum",
          "agg: the four breakdowns, coins by source cumulative: %s" % sorted(res["breakdowns"]))
    h = SB.head_of(res)
    check(set(h) >= {"meta", "settings", "summary", "hero_name", "T", "bosses"} and len(json.dumps(h)) < 20000, "agg: head.json is small: %d bytes" % len(json.dumps(h)))
    SB.write_json(os.path.join(tmp, "synth", "settings.json"), dict(SB.DEFAULTS, players=4, limit=600))
    again = SB.reaggregate(os.path.join(tmp, "synth"), log=lambda m: None)
    check(again["summary"]["ok"] == 4 and os.path.isfile(os.path.join(tmp, "synth", "head.json")), "agg: --aggregate writes result.json and head.json again")
    bad, why = SB.load_player(os.path.join(tmp, "nope.json"))
    check(bad is None and why == "no JSON written", "agg: a missing file is 'no JSON written'")
    SB.write_json(os.path.join(tmp, "short.json"), {"t": [1, 2], "hp": [1], "level": [1, 1]})
    bad, why = SB.load_player(os.path.join(tmp, "short.json"))
    check(bad is None and "hp" in why, "agg: a series shorter than t is refused: %s" % why)
    check(SB.pct([1.0, 2.0, 2.0], 0.1) == 1.2 and SB.pct([5.0], 0.9) == 5.0 and SB.pct([], 0.5) is None, "agg: the quantile rule")


def _round2_checks(check, SB, tmp):
    import locks
    # the board talent by talent
    # pass 88 (lane MIRROR): Spite is Stakes (Difficulty / Boss), which no preset buys (SB.PRESET_SKIP)
    check(SB.board_talents(1.5) == {"grit": "AA", "drive": "A", "stride": "AA", "fortune": "A", "choice": "AA", "nerve": "B", "study": "BB"}
          and SB.board_ranks(SB.board_talents(1.5)) == 11 and SB.board_ranks(SB.board_talents(6)) == 42 and SB.board_talents(0) == {},
          "r2: the presets as difficulty_probe's FORMS and rank_for, Stakes left out (a quarter = 11 of 48 ranks)")
    t, p = SB.clean_talents("grit:AAB,drive:1,nerve:2:B")
    check(t == {"grit": "AAB", "drive": "B", "nerve": "BB"} and not p, "r2: the talents' text in its three shapes: %s %s" % (t, p))
    t, p = SB.clean_talents({"grit": {"picks": [0, 1, 0]}, "study": {"rank": 2, "form": 1}, "spite": [1, 1], "stride": 3})
    check(t == {"grit": "ABA", "stride": "AAA", "study": "BB", "spite": "BB"}, "r2: the save's shapes read (picks, rank+form, a list, a rank): %s" % t)
    t, p = SB.clean_talents({"nope": "A", "grit": "AAAAAAA", "drive": "XYZ"})
    check(len(p) == 3 and t == {"grit": "AAAAAA"}, "r2: an unknown talent, more than 6 ranks and bad letters are problems: %s" % p)
    check(SB.talents_arg({"study": "BB", "grit": "A"}) == "grit:A,study:BB" and SB.talents_arg({}) == "none", "r2: the arg in the talents' order")
    check(SB.preset_of(SB.board_talents(3)) == "half" and SB.preset_of({"grit": "B"}) is None, "r2: a board equal to a preset is that preset")
    s, _ = SB.clean_settings({"talents": {"grit": "AB"}, "board_label": "my save"})
    check(s["board"] == -1.0 and s["board_label"] == "my save" and s["talents"] == {"grit": "AB"}, "r2: a custom board: board -1, its label kept")
    s, _ = SB.clean_settings({"talents": SB.board_talents(6)})
    check(s["board"] == 6.0 and s["board_label"] == "full", "r2: talents equal to a preset name it")
    s, _ = SB.clean_settings({"talents": {}, "board": 3})
    check(s["talents"] == SB.board_talents(3), "r2: an empty board means the preset board= names (a job spec's default {})")
    # the death policies and at once
    s, p = SB.clean_settings({"death": "gold"})
    check(p and s["death"] == "end", "r2: gold is no longer a policy to run")
    s, p = SB.clean_settings({"death": "gold"}, legacy=True)
    check(not p and s["death"] == "gold" and SB.death_label("gold") == "revive with gold, then the run ends", "r2: an older sim's gold reads without a problem")
    s, _ = SB.clean_settings({"players": 3})
    check(s["workers"] == 3 and SB.clean_settings({})[0]["workers"] == min(10, SB.max_workers()) and SB.clean_settings({"workers": 2})[0]["workers"] == 2,
          "r2: at once auto = as many as the runs, at most cores - 2")
    # the runner's capabilities
    old_runner = os.path.join(tmp, "old", "tools", "sim_run.gd")
    _write(old_runner, 'match k:\n\t\t\t"board": _board = float(v)\n\t\t\t"death": _death = v\n\tif not _death in ["gold", "end", "keep"]:\n')
    new_runner = os.path.join(tmp, "new", "tools", "sim_run.gd")
    _write(new_runner, 'match k:\n\t\t\t"talents": _talent_arg = v\n\t\t\t"fast": _fast = v != "0"\n\tif not _death in ["ad", "end", "keep"]:\n')
    co, cn = SB.runner_caps(os.path.join(tmp, "old")), SB.runner_caps(os.path.join(tmp, "new"))
    # pass 80 (lane BOT, re-pinned on purpose): the caps carry "bot" (the runner's BOT_ARGS: the bot's options)
    check(co == {"runner": True, "talents": False, "deaths": ["gold", "end", "keep"], "fast": False, "bot": False}
          and cn == {"runner": True, "talents": True, "deaths": ["ad", "end", "keep"], "fast": True, "bot": False}
          and SB.runner_caps(os.path.join(tmp, "none"))["runner"] is False, "r2: the runner's capabilities read off its parser: %s %s" % (co, cn))
    bot_runner = os.path.join(tmp, "botr", "tools", "sim_run.gd")
    _write(bot_runner, "\n".join(['const BOT_ARGS := ["preset", "skill"]', "match k:", '\t\t\t"talents": _talent_arg = v',
                                  '\t\t\t"fast": _fast = v != "0"', '\tif not _death in ["ad", "end", "keep"]:', ""]))
    cb = SB.runner_caps(os.path.join(tmp, "botr"))
    s_bot, _ = SB.clean_settings({"bot": {"preset": "sim77", "skill": 0.5}})
    check(cb["bot"] is True and SB.caps_problem(s_bot, cn).startswith("the runner") and SB.caps_problem(s_bot, cb) == "",
          "p80: a runner without BOT_ARGS refuses bot options, one with them plays them: %s" % cb)
    s_custom, _ = SB.clean_settings({"talents": {"grit": "B"}})
    s_ad, _ = SB.clean_settings({"death": "ad"})
    check("only the board presets" in SB.caps_problem(s_custom, co) and "death policy 'ad'" in SB.caps_problem(s_ad, co) and SB.caps_problem(s_custom, cn) == ""
          and SB.caps_problem(SB.clean_settings({})[0], co) == "", "r2: an older runner refuses a custom board and an unknown policy, plays a preset")

    class P:
        json, log, seed = "p.json", "p.log", 4
    a = SB.player_args(SB.clean_settings({"talents": {"grit": "AAB"}})[0], P, "snap", "out", 900, cn)
    b = SB.player_args(SB.clean_settings({"board": 0, "fast": False})[0], P, "snap", "out", 900, cn)
    c = SB.player_args(SB.clean_settings({})[0], P, "snap", "out", 900, co)
    check("talents=grit:AAB" in a and "board=0" in a and "fast=1" in a and not any(x.startswith("talents=") for x in b) and "fast=0" in b
          and "board=1.5" in c and not any(x.startswith("fast=") for x in c), "r2: the runner's args (talents only when there are ranks; fast=0/1 when it has the mode): %s" % a[-4:])
    # pass 80 (lane BOT): the bot's options through the settings, the runner's args and the presets read off Bot.gd
    b80, bp80 = SB.clean_bot("preset=careless,skill=0.3,totems=0,stray=500,nope=1")
    check(b80 == {"preset": "careless", "skill": 0.3, "stray": 200.0, "totems": False} and len(bp80) == 2,
          "p80: clean_bot coerces, clamps and refuses: %s %s" % (b80, bp80))
    check(SB.bot_arg(b80) == "preset=careless,skill=0.3,stray=200,totems=0", "p80: bot_arg: %s" % SB.bot_arg(b80))
    check(SB.clean_bot({"preset": "sim77"})[0] == {"preset": "sim77"} and SB.clean_bot("")[0] == {} and SB.clean_settings({})[0]["bot"] == {},
          "p80: no bot options = the runner's default")
    s80, _ = SB.clean_settings({"bot": "preset=sim77,explore=0.5"})
    a80 = SB.player_args(s80, P, "snap", "out", 900, dict(cn, bot=True))
    n80 = SB.player_args(s80, P, "snap", "out", 900, dict(cn, bot=False))
    check("preset=sim77" in a80 and "explore=0.5" in a80 and not any(x.startswith("preset=") for x in n80),
          "p80: the runner's args carry the bot's options when it reads them: %s" % a80[-3:])
    pres = SB.bot_presets()
    check(set(pres) == {k for k, _, _ in SB.BOT_PRESETS} and all(set(v) == set(SB.BOT_KEY_NAMES) for v in pres.values())
          and pres["sim77"]["cards"] == "tier" and pres["explorer"]["totems"] is True,
          "p80: every preset in game/tools/bot/Bot.gd names every option the page offers: %s" % {k: sorted(v) for k, v in pres.items()})
    eff, src = SB.bot_effective({"preset": "sim77", "skill": 0.4}, pres)
    check(eff["skill"] == 0.4 and src["skill"] == "set" and src["explore"] == "preset" and eff["explore"] == pres["sim77"]["explore"],
          "p80: the effective options say where each comes from")
    # pass 90 (lane BOT): the Survivor preset (the Explorer, the safety style, the ring breakout); the safety style brings
    # the breakout unless it is set too (Bot.resolve_opts)
    check(pres["survivor"]["breakout"] is True and pres["survivor"]["style"] == "safety" and pres["explorer"]["breakout"] is False
          and SB.clean_bot("preset=survivor,breakout=0")[0] == {"preset": "survivor", "breakout": False},
          "p90: the survivor preset and the breakout option: %s" % pres.get("survivor"))
    e90, s90 = SB.bot_effective({"preset": "explorer", "style": "safety"}, pres)
    e90b, _ = SB.bot_effective({"preset": "explorer", "style": "safety", "breakout": False}, pres)
    check(e90["breakout"] is True and s90["breakout"] == "style" and e90b["breakout"] is False
          and SB.bot_effective({"preset": "explorer"}, pres)[0]["breakout"] is False,
          "p90: the safety style brings the breakout unless it is set: %s %s" % (e90.get("breakout"), e90b.get("breakout")))
    # my save: the PC save, or the copy tools/locks.py keeps aside
    saved = (locks.SAVE_DIR, locks.KEEP_DIR, locks.RESTORE_PENDING)
    try:
        locks.SAVE_DIR = os.path.join(tmp, "save")
        locks.KEEP_DIR = os.path.join(tmp, "keep")
        locks.RESTORE_PENDING = os.path.join(locks.KEEP_DIR, "restore_pending.json")
        _write(os.path.join(locks.SAVE_DIR, "save.json"), json.dumps({"talents": {"grit": {"picks": [0, 0, 1]}, "study": {"rank": 2, "form": 1}}}))
        b1, note = SB.save_board()
        check(b1 == {"grit": "AAB", "study": "BB"} and "save.json" in note, "r2: my save read from the PC save: %s" % b1)
        _write(os.path.join(locks.KEEP_DIR, "save.json.keep"), json.dumps({"talents": {"spite": {"picks": [1]}}}))
        _write(locks.RESTORE_PENDING, "{}")
        check(SB.save_board()[0] == {"spite": "B"}, "r2: while a tool has the save aside, the kept copy is the save")
    finally:
        locks.SAVE_DIR, locks.KEEP_DIR, locks.RESTORE_PENDING = saved
    # the derived series on a run with every field
    d = SB.synthetic_player(1, 5, {"limit": 600, "death": "keep"})
    series, end, bds = SB.player_grid(d, 600)
    i = 300
    hm, took, healed = series["hp_max"][i], series["took"], series["healed"]
    want = sum(100.0 * (took[j] or 0) / series["hp_max"][j] for j in range(i - 4, i + 1)) / 5.0
    check(abs(series["danger"][i] - want) < 1e-6, "r2: danger = HP lost a second as %% of max HP over 5 s: %s %s" % (series["danger"][i], want))
    wantn = sum(100.0 * ((took[j] or 0) - (healed[j] or 0)) / series["hp_max"][j] for j in range(i - 4, i + 1)) / 5.0
    check(abs(series["danger_net"][i] - wantn) < 1e-6, "r2: the net after healing")
    boss = SB._boss_abs(d, series, end, 600)
    ku = [j for j in range(end + 1) if series["keep_up"][j] is not None]
    j = ku[len(ku) // 2]
    check(abs(series["keep_up"][j] - max(0.0, series["press_hp"][j] - (boss[j] or 0)) / series["dps"][j]) < 1e-6, "r2: keeping up = (crowd HP - boss HP) / DPS")
    bsec = [j for j in range(end + 1) if series["boss_s"][j] is not None]
    check(bsec and all((boss[j] or 0) > 0 for j in bsec) and abs(series["boss_s"][bsec[0]] - boss[bsec[0]] / series["dps"][bsec[0]]) < 1e-6,
          "r2: the boss's own seconds only while one lives")
    check(all(v in (0.0, 100.0) for v in series["trouble"][:end + 1]) and series["kills_ps"][end] is not None, "r2: in trouble 0 or 100 a second; kills a second")
    frac = dict(d)
    frac.pop("boss_hp_abs")
    frac = json.loads(json.dumps(frac))
    sr2, end2, _ = SB.player_grid(frac, 600)
    b2 = SB._boss_abs(frac, sr2, end2, 600)
    fights = [j for j in range(end2 + 1) if (sr2["boss_hp"][j] or 0) > 0]
    check(fights and all(abs(b2[j] - sr2["boss_hp"][j] * [3000, 21000, 90000][0 if j < 600 else 1]) < 1e-6 for j in fights[:3]),
          "r2: without boss_hp_abs: the fraction x the max HP its boss_start reported")
    res = SB.aggregate([(k, SB.synthetic_player(k, k, {"limit": 300, "death": "keep"}), {"seed": k}) for k in range(1, 5)], {"players": 4, "limit": 300, "death": "keep"},
                       game_dir=os.path.join(tmp, "nogame"))
    ku = res["series"]["keep_up"]
    check(set(ku) == {"median", "p10", "p90", "n"} and "mean" not in ku and ku["n"][100] == 4 and res["rules"]["medians"] == ["keep_up", "boss_s", "challenge"],   # pass 84 (lane SIMVIEW): challenge
          "r2: the ratios as a middle value with its band and its count of runs")
    check({"took_by", "healed_by", "held_by"} <= set(res["breakdowns"]) and res["breakdowns"]["held_by"]["kind"] == "level", "r2: the new breakdowns")
    res2 = SB.aggregate([(1, dict(SB.synthetic_player(1, 1, {"limit": 120, "talents": {"grit": "AAA"}}), meta=dict(SB.synthetic_player(1, 1, {"limit": 120})["meta"], talents={"grit": 1})), {"seed": 1})],
                        {"players": 1, "limit": 120, "talents": {"grit": "AAA"}}, game_dir=os.path.join(tmp, "nogame"))
    check(res2["meta"].get("board_differs") == ["run 1 played grit 1 (asked 3)"], "r2: a run that played another board than asked is named: %s" % res2["meta"].get("board_differs"))
    m3 = dict(SB.synthetic_player(1, 1, {"limit": 120})["meta"], talents={"grit": 3}, talent_forms={"grit": "AAB"})
    res3 = SB.aggregate([(1, dict(SB.synthetic_player(1, 1, {"limit": 120}), meta=m3), {"seed": 1})], {"players": 1, "limit": 120, "talents": {"grit": "AAA"}},
                        game_dir=os.path.join(tmp, "nogame"))
    check(res3["meta"].get("board_differs") == ["run 1 played grit AAB (asked AAA)"], "r2: with the runner's forms the board is checked rank by rank: %s" % res3["meta"].get("board_differs"))
    # what the runs played: their meta.fast (none: a runner from before the sim mode, everything drawn)
    def _played(fast):
        rows = []
        for k in (1, 2):
            d = {"t": [0, 1, 2], "hp": [100, 100, 100], "hp_max": [100, 100, 100], "level": [1, 1, 2], "meta": {"seed": k, "hero": "drifter"}}
            if fast is not None:
                d["meta"]["fast"] = fast
            rows.append((k, d, {"k": k, "seed": k, "end_reason": "limit", "end_t": 2, "wall_s": 10, "problem": ""}))
        return SB.aggregate(rows, {"players": 2, "limit": 2, "board": 0}, {})["meta"].get("sim_mode")
    check([_played(True), _played(False), _played(None)] == [True, False, False],
          "r2: result.meta.sim_mode = what the runs played (a runner without the mode drew everything): %s" % [_played(True), _played(False), _played(None)])
    # the speed record counts only the runs that played most of the stop (an early death played the light early game)
    saved_dir = SB.SIM_DIR
    SB.SIM_DIR = os.path.join(tmp, "speed")
    try:
        os.makedirs(SB.SIM_DIR, exist_ok=True)
        runs = [{"ok": True, "end_t": 1500.0, "wall_s": 540.0, "rate": 2.5 + 0.1 * i, "boot_s": 22.0} for i in range(9)]
        early = [{"ok": True, "end_t": 200.0 + 30 * i, "wall_s": 60.0, "rate": 5.0 + 0.1 * i, "boot_s": 20.0} for i in range(8)]
        rec = SB.record_speed(runs + early[:1], 10, 60, fast=True, limit=1500)
        check(rec is not None and rec["players"] == 9 and abs(rec["play_per_wall"] - 2.9) < 1e-6 and abs(rec["slow"] - 2.5) < 1e-6 and rec["fast"] is True,
              "r2: the speed record: the long runs' median, the slowest run's pace (an early death left out): %s" % rec)
        check(SB.record_speed(runs[:2] + early, 10, 60, fast=True, limit=1500) is None,
              "r2: no record when most runs died early (the two survivors had the PC to themselves)")
        check(SB.record_speed([dict(r, end_t=120.0) for r in runs[:2]], 2, 60, fast=True, limit=120) is None,
              "r2: a short test sim (2 x 120 s) records no speed")
        SB.record_speed(runs[:6], 6, 60, fast=True, limit=1500)
        sp = SB.load_speed(fast=True)
        check(sp["measured"] and sp["n"] == 1 and sp["workers"] == 6 and abs(sp["slow"] - 2.5) < 1e-6,
              "r2: load_speed reads the records at the latest number at once (6), unscaled: %s" % sp)
    finally:
        SB.SIM_DIR = saved_dir


def _sync_checks(check, SB, tmp):
    src, dst = os.path.join(tmp, "src"), os.path.join(tmp, "dst")
    old = time.time() - 1000
    _write(os.path.join(src, "project.godot"), 'config_version=5\n\n[application]\n\nconfig/name="88fits"\nconfig/version="0.62"\n\n[autoload]\n\nRun="*res://Run.gd"\n', old)
    _write(os.path.join(src, "core", "a.gd"), "class_name Foo\nextends Node\n", old)
    _write(os.path.join(src, "art", "b.png"), "png", old)
    _write(os.path.join(src, "art", "b.png.import"), "[remap]\n", old)
    _write(os.path.join(src, "content", "maps", "m", "m.json"), "{}", old + 500)
    _write(os.path.join(src, "content", "maps", "m", "m.tres"), "tres", old)
    _write(os.path.join(src, "content", "enemies", "g", "g.json"), "{}", old)
    _write(os.path.join(src, "content", "enemies", "g", "g.tres"), "tres", old + 10)
    _write(os.path.join(src, "export", "x.apk"), "apk", old)
    _write(os.path.join(src, "reports", "r.xml"), "r", old)
    _write(os.path.join(src, ".godot", "imported", "b.png-1.ctex"), "ctex", old)
    _write(os.path.join(src, ".godot", "shader_cache", "s.bin"), "s", old)
    _write(os.path.join(src, "tools", "x.tmp"), "tmp", old)
    logs = []
    r = SB.sync_snapshot(src, dst, log=logs.append)
    have = sorted(SB._walk(dst))
    check(have == ["art/b.png", "art/b.png.import", "content/enemies/g/g.json", "content/enemies/g/g.tres", "content/maps/m/m.json",
                   "content/maps/m/m.tres", "core/a.gd", "project.godot"], "sync: copies the game minus export, reports, .godot and *.tmp: %s" % have)
    check(os.path.isfile(os.path.join(dst, ".godot", "imported", "b.png-1.ctex")) and not os.path.isdir(os.path.join(dst, ".godot", "shader_cache")),
          "sync: a new snapshot's .godot seeded from the real one, without the shader cache")
    check(r["fresh"] and "a new snapshot" in r["import_reasons"], "sync: a new snapshot imports: %s" % r["import_reasons"][:2])
    pg = open(os.path.join(dst, "project.godot"), encoding="utf-8").read()
    check("config/use_custom_user_dir=true" in pg and 'config/custom_user_dir_name="88fits_sim"' in pg and pg.index("[application]") < pg.index("use_custom_user_dir") < pg.index("[autoload]"),
          "sync: project.godot gets its own user folder inside [application]")
    check(SB.patch_project(pg) == pg and SB.patch_project(pg.replace("88fits_sim", "x")).count("custom_user_dir_name") == 1, "sync: the patch is idempotent and replaces an old value")
    check(abs(os.path.getmtime(os.path.join(dst, "core", "a.gd")) - os.path.getmtime(os.path.join(src, "core", "a.gd"))) < 0.01, "sync: mtimes kept")
    r = SB.sync_snapshot(src, dst, log=logs.append)
    check(r["copied"] == 0 and r["removed"] == 0 and not r["import_reasons"] and not r["fresh"], "sync: nothing changed, nothing copied: %s" % r)
    _write(os.path.join(src, "core", "a.gd"), "class_name Foo\nextends Node\nvar x := 1\n")
    r = SB.sync_snapshot(src, dst, log=logs.append)
    check(r["copied"] == 1 and not r["import_reasons"], "sync: a script edited without a class_name change imports nothing: %s" % r["import_reasons"])
    _write(os.path.join(src, "core", "a.gd"), "class_name Bar\nextends Node\n")
    r = SB.sync_snapshot(src, dst, log=logs.append)
    check(any("class_name" in x for x in r["import_reasons"]), "sync: a class_name change imports: %s" % r["import_reasons"])
    _write(os.path.join(src, "core", "c.gd"), "extends Node\n")
    _write(os.path.join(src, "core", "c.gd.uid"), "uid://abc\n")
    r = SB.sync_snapshot(src, dst, log=logs.append)
    check(any("script added" in x for x in r["import_reasons"]) and any("uid" in x for x in r["import_reasons"]), "sync: a new script and its uid import: %s" % r["import_reasons"])
    _write(os.path.join(src, "art", "b.png"), "png2")
    r = SB.sync_snapshot(src, dst, log=logs.append)
    check(any("asset changed" in x for x in r["import_reasons"]), "sync: a changed picture imports: %s" % r["import_reasons"])
    _write(os.path.join(src, "ui", "New.tscn"), "[gd_scene]\n")
    r = SB.sync_snapshot(src, dst, log=logs.append)
    check(any("scene or resource added" in x for x in r["import_reasons"]), "sync: a new scene imports (its uid): %s" % r["import_reasons"])
    _write(os.path.join(src, "ui", "New.tscn"), "[gd_scene]\n# edited\n")
    r = SB.sync_snapshot(src, dst, log=logs.append)
    check(r["copied"] == 1 and not r["import_reasons"], "sync: an edited scene imports nothing: %s" % r["import_reasons"])
    # the snapshot's own import products beside a file that is still there are kept; a file gone from the game goes
    _write(os.path.join(dst, "art", "b.png.import2"), "x")
    _write(os.path.join(dst, "core", "a.gd.uid"), "uid://own\n")
    _write(os.path.join(src, "art", "d.png"), "png", old)
    SB.sync_snapshot(src, dst, log=logs.append)
    os.remove(os.path.join(src, "art", "d.png"))
    _write(os.path.join(dst, "art", "e.png.import"), "[remap]")
    r = SB.sync_snapshot(src, dst, log=logs.append)
    check(os.path.isfile(os.path.join(dst, "core", "a.gd.uid")) and not os.path.isfile(os.path.join(dst, "art", "b.png.import2"))
          and not os.path.isfile(os.path.join(dst, "art", "d.png")) and not os.path.isfile(os.path.join(dst, "art", "e.png.import")),
          "sync: a .uid of a file still there is kept; strays and a removed picture (and an orphan .import) go")
    check(any("asset removed" in x for x in r["import_reasons"]), "sync: a removed picture imports: %s" % r["import_reasons"])
    check(SB.stale_json(dst) == ["maps/m"], "sync: a content JSON newer than its .tres is listed for import_json: %s" % SB.stale_json(dst))
    check(SB.import_reason("content/maps/m/m.json", "changed") == "" and SB.import_reason("x.ogg", "added").startswith("an asset"), "sync: a JSON is no import, a sound is")


def _lock_checks(check, SB, tmp):
    saved = SB.LOCK_DIR
    try:
        SB.LOCK_DIR = os.path.join(tmp, "locks")
        check(SB.lock_status() is None and SB.lock_acquire("t", wait=False, log=lambda m: None), "lock: free, taken")
        st = SB.lock_status()
        check(st["pid"] == os.getpid() and st["alive"] and st["owner_file"], "lock: owner.json names this process: %s" % st)
        check(not SB.lock_acquire("t2", wait=False, log=lambda m: None), "lock: refused while a live process holds it")
        check(SB.lock_release() and SB.lock_status() is None, "lock: released")
        os.makedirs(SB.lock_path())
        _write(os.path.join(SB.lock_path(), "owner.json"), json.dumps({"pid": 999999, "who": "a dead sim", "since": time.time() - 50}))
        said = []
        check(SB.lock_acquire("t3", wait=False, log=said.append) and any("reclaimed" in m for m in said), "lock: a dead owner's lock is reclaimed: %s" % said)
        SB.lock_release()
        os.makedirs(SB.lock_path())
        check(not SB.lock_acquire("t4", wait=False, log=lambda m: None) and SB.lock_status()["who"] == "unknown process", "lock: a folder without owner.json is never taken over")
        check(SB.lock_force_release() and SB.lock_status() is None, "lock: Force release removes it")
    finally:
        SB.LOCK_DIR = saved


class _Handler:
    def __init__(self, body=None):
        self.body = body
        self.sent = None

    def _send(self, code, body, ctype="application/json; charset=utf-8", cache="no-store"):
        if isinstance(body, (bytes, bytearray)):
            body = json.loads(body.decode("utf-8"))
        self.sent = (code, body)

    def _error(self, code, msg, **extra):
        self.sent = (code, dict({"ok": False, "error": msg}, **extra))

    def _body(self):
        return (self.body, None) if self.body is not None else (None, "no body")


class _JobsStub:
    def __init__(self):
        self.jobs = []
        self.calls = []

    def list(self, since_rev=None):
        return {"rev": 1, "jobs": list(self.jobs)}

    def status(self):
        return {"readonly": None}


def _routes_checks(check, SB, tmp):
    import sim_io as SIO
    saved = (SB.SIM_DIR, SB.LOCK_DIR)
    stub = _JobsStub()

    class Srv:
        GAME = os.path.join(ROOT, "game")

        @staticmethod
        def list_maps():
            return [{"id": "red_canyon", "name": "Red Canyon", "file": "game/content/maps/red_canyon/red_canyon.json"}]

        @staticmethod
        def jobs_module():
            return stub

        @staticmethod
        def jobs_call(name, *args):
            stub.calls.append((name,) + args)
            if name == "enqueue":
                job = {"id": "j-sim-1", "kind": "sim", "state": "queued", "plan": {"sim_id": "j-sim-1"}, "spec": args[2]}
                stub.jobs.append(job)
                return 200, {"ok": True, "job": job}
            if name == "cancel":
                return 200, {"ok": True}
            return 404, {"ok": False}

    def get(parts, query=None):
        h = _Handler()
        SIO.api_get(h, Srv, parts, query or {})
        return h.sent

    def post(parts, body=None):
        h = _Handler(body or {})
        SIO.api_post(h, Srv, parts)
        return h.sent

    try:
        SB.SIM_DIR = os.path.join(tmp, "sim")
        SB.LOCK_DIR = os.path.join(tmp, "locks")
        for name, extra in (("s-old", ["--seed", "5"]), ("s-new", ["--death", "keep"])):
            rc = SB.main(["--out", os.path.join(SB.runs_dir(), name), "--synthetic", "--players", "3", "--workers", "3", "--limit", "120", "--sim-dir", SB.SIM_DIR] + extra)
            check(rc == 0, "routes: a made-up sim %s written (rc %s)" % (name, rc))
            time.sleep(0.05)
        os.utime(os.path.join(SB.runs_dir(), "s-old"), (time.time() - 100, time.time() - 100))
        code, body = get(["history"])
        ids = [s["id"] for s in body["sims"]]
        check(code == 200 and set(ids) == {"s-old", "s-new"} and all(s["state"] == "done" and s["has_result"] and s["synthetic"] for s in body["sims"]),
              "routes: the history lists both sims, done, with a result: %s" % [(s["id"], s["state"]) for s in body["sims"]])
        check(all(s["drawn"] is False for s in body["sims"]), "routes: a sim in the sim mode is not named as drawn")
        hp = os.path.join(SB.runs_dir(), "s-old", "head.json")
        hd = SB.read_json(hp)
        hd["meta"]["sim_mode"] = False
        SB.write_json(hp, hd)
        code, body = get(["history"])
        check([s["drawn"] for s in body["sims"] if s["id"] == "s-old"] == [True], "routes: a history row says when the runs drew everything (meta.sim_mode false)")
        code, body = get(["result", "s-new"])
        check(code == 200 and body["settings"]["death"] == "keep" and "series" in body, "routes: result/<id> serves result.json")
        for bad in (["result", ".."], ["result", "nope"], ["result", "a b"]):
            check(get(bad)[0] == 404, "routes: %s is refused" % "/".join(bad))
        code, body = get(["settings"])
        check(code == 200 and body["defaults"]["players"] == 10 and any(h["id"] == "drifter" for h in body["heroes"]) and body["max_workers"] == max(1, (os.cpu_count() or 4) - 2)
              and [b["label"] for b in body["boards"]] == ["none", "a quarter", "half", "full"]
              and [d["value"] for d in body["deaths"]] == [k for k, _, _ in SB.DEATHS if k in SB.runner_caps(Srv.GAME)["deaths"]]
              and sorted(t["id"] for t in body["talents"]) == sorted(SB.TALENT_ORDER)
              and [t["first_price"] for t in body["talents"]] == sorted(t["first_price"] for t in body["talents"]) and [p["key"] for p in body["presets"]][:4] == ["none", "quarter", "half", "full"]
              and "frame by frame" in body["speed_words"],
              "routes: settings: the defaults, the heroes, the boards, the death modes, the processors")
        check(post(["s-old", "keep"], {"keep": True})[1]["kept"] is True and os.path.isfile(os.path.join(SB.runs_dir(), "s-old", "kept")), "routes: keep")
        code, body = get(["history"])
        check(any(s["id"] == "s-old" and s["kept"] for s in body["sims"]), "routes: the history says kept")
        gone = SB.prune_history(keep=0, log=lambda m: None)
        check(gone == ["s-new"] and os.path.isdir(os.path.join(SB.runs_dir(), "s-old")), "routes: pruning spares a kept sim: %s" % gone)
        check(post(["s-old", "keep"], {"keep": False})[1]["kept"] is False, "routes: unkeep")
        code, body = post(["run"], {"settings": {"players": 0, "hero": "nobody"}})
        check(code == 400 and "players" in body["error"] and "nobody" in body["error"], "routes: run refuses bad settings with every reason: %s" % body.get("error"))
        code, body = post(["run"], {"settings": {"players": 3, "workers": 2, "limit": 300, "hero": "drifter", "map": "red_canyon"}})
        check(code == 200 and body["job"]["kind"] == "sim" and body["sim_id"] == "j-sim-1" and stub.calls[-1][1] == "sim" and stub.calls[-1][3]["players"] == 3,
              "routes: run queues a sim job with the checked settings: %s" % (stub.calls[-1][:2],))
        check((SB.read_json(SB.settings_file()) or {}).get("players") == 3, "routes: run remembers the settings")
        code, body = post(["run"], {"settings": {"players": 3}})
        check(code == 409 and "one at a time" in body["error"], "routes: a second sim is refused while one is queued: %s" % body.get("error"))
        code, body = get(["status"])
        check(code == 200 and body["job"]["id"] == "j-sim-1" and body["sim_id"] == "j-sim-1", "routes: status names the sim queued")
        code, body = post(["j-sim-1", "cancel"])
        check(code == 200 and stub.calls[-1][0] == "cancel", "routes: cancel goes through the job queue")
        stub.jobs.clear()
        check(get(["status"])[1]["job"] is None, "routes: no sim queued, no job in the status")
        check(post(["s-old", "delete"])[0] == 200 and not os.path.isdir(os.path.join(SB.runs_dir(), "s-old")), "routes: delete")
        check(post(["s-old", "delete"])[0] == 404, "routes: a sim that is gone is a 404")
        os.makedirs(SB.lock_path())
        _write(os.path.join(SB.lock_path(), "owner.json"), json.dumps({"pid": 999999, "who": "dead"}))
        check(post(["unlock"], {})[0] == 200 and SB.lock_status() is None, "routes: unlock releases a dead owner's lock")
        check(post(["nope", "explode"])[0] == 404 and get(["what"])[0] == 404, "routes: unknown paths are 404")
    finally:
        SB.SIM_DIR, SB.LOCK_DIR = saved


def _job_checks(check, SB, tmp):
    import locks
    import jobs
    saved = {k: getattr(jobs, k) for k in ("JOBS_DIR", "QUEUE_FILE", "DL", "RAW", "ANIM", "REVIEW", "LAUNCH_FILE")}
    saved_locks = {k: getattr(locks, k) for k in ("LOCK_DIR",)}
    saved_state = (jobs._state, jobs._hooks, jobs._root, dict(jobs._lane_current), jobs._queue_lock, jobs._readonly)
    try:
        jobs.JOBS_DIR = os.path.join(tmp, "jobs")
        jobs.QUEUE_FILE = os.path.join(jobs.JOBS_DIR, "queue.json")
        jobs.DL = os.path.join(tmp, "dl")
        for k in ("RAW", "ANIM", "REVIEW"):
            setattr(jobs, k, os.path.join(tmp, "dl", k.lower()))
        jobs.LAUNCH_FILE = os.path.join(tmp, "user", "debug_launch.json")
        locks.LOCK_DIR = os.path.join(tmp, "locks")
        jobs._state = {"rev": 0, "jobs": []}
        jobs._queue_lock, jobs._readonly = None, None
        jobs.init({"content_path": lambda kind, cid: (None, None)}, ROOT)
        check("sim" in jobs.LANES and jobs.SPECS["sim"]["lane"] == "sim", "job: the sim kind on a lane of its own")
        f = jobs.SPECS["sim"]["fields"]
        check(set(f) >= {"hero", "players", "workers", "limit", "board", "talents", "board_label", "death", "seed", "map", "fps", "note", "fast"}
              and f["death"]["options"] == ["end", "ad", "keep"] and f["death"]["default"] == "end" and f["workers"]["default"] == 0,
              "job: the fields: %s" % sorted(f))
        v = jobs.validate_spec("sim", {"players": "12", "board": "3", "limit": "600"})
        check(v["players"] == 12 and v["board"] == 3.0 and v["limit"] == 600 and v["death"] == "end" and v["talents"] == SB.board_talents(3)
              and v["workers"] == min(12, SB.max_workers()), "job: the spec coerced, the board talent by talent, at once auto: %s" % {k: v[k] for k in ("players", "board", "limit", "workers")})
        v2 = jobs.validate_spec("sim", {"talents": {"grit": "AAB"}, "board_label": "my save"})
        check(v2["talents"] == {"grit": "AAB"} and v2["board"] == -1.0 and v2["board_label"] == "my save", "job: a board talent by talent wins over the preset: %s" % v2["talents"])
        for bad in ({"players": 0}, {"death": "maybe"}, {"death": "gold"}, {"limit": 5}, {"board": 9}, {"talents": {"nope": "A"}}, {"talents": {"grit": "AAAAAAA"}}):
            try:
                jobs.validate_spec("sim", bad)
                check(False, "job: %s refused" % bad)
            except ValueError as e:
                check(True, "job: %s refused (%s)" % (bad, str(e)[:60]))
        j = jobs.enqueue("sim", {"kind": "sim", "id": "red_canyon"}, {"players": 3, "workers": 2, "limit": 120, "synthetic": True, "synthetic_speed": 0})
        job = jobs._find(j["id"])
        plan = job["plan"]
        out = os.path.join(jobs.DL, "sim", "runs", job["id"])
        argv = [str(x) for x in plan["steps"][0]]
        check(job["lane"] == "sim" and plan["mode"] == "sim" and plan["lock"] is None and not plan.get("keep_save"), "job: the plan: its own mode, no lock, no save keep")
        check(argv[0] == sys.executable and argv[2].endswith("sim_batch.py") and argv[argv.index("--out") + 1] == out and argv[argv.index("--sim-dir") + 1] == os.path.join(jobs.DL, "sim")
              and "--synthetic" in argv and argv[argv.index("--talents") + 1] == SB.talents_arg(SB.board_talents(1.5)) and argv[argv.index("--players") + 1] == "3" and argv[argv.index("--job") + 1] == job["id"],
              "job: the driver's argv: %s" % " ".join(argv[2:]))
        # pass 80 (lane BOT): the bot's options ride the job to the driver's --bot (none: no --bot, the runner's default)
        check("bot" in f and "--bot" not in argv, "p80: the sim job has a bot field; no options, no --bot")
        plan_b = jobs.sim_plan({"id": "j-p80-bot", "spec": jobs.validate_spec("sim", {"players": 2, "limit": 120, "bot": {"preset": "sim77", "skill": 0.5}})})
        argv_b = [str(x) for x in plan_b["steps"][0]]
        check("--bot" in argv_b and argv_b[argv_b.index("--bot") + 1] == "preset=sim77,skill=0.5", "p80: the job's bot options on the driver's argv: %s" % argv_b[-6:])
        check(plan["sim_id"] == job["id"] and plan["sim_out"].endswith(job["id"]) and job["equiv"].startswith("python tools/sim_batch.py --out "), "job: the sim's folder named by the job: %s" % plan["sim_out"])
        names = [s["name"] for s in job["progress"]["stages"]]
        check(names == ["snapshot", "run 1", "run 2", "run 3", "charts"], "job: the stages: %s" % names)
        check(job["title"].startswith("Sim · ") and "× 3" in job["title"] and job["eta_s"] > 0, "job: the title and an ETA: %s, %s s" % (job["title"], job["eta_s"]))
        # the parser on the driver's lines
        probe = json.loads(json.dumps(job))
        for line in ("sim: waiting for the sim lock (held by sim_batch, pid 9, for 3 s): one sim at a time",):
            jobs.parse_line(probe, line)
        check(probe["progress"]["stage"].startswith("waiting for the sim lock"), "job: the lock wait in the card: %s" % probe["progress"]["stage"])
        for line in ("sim: sync: copied 3 files (0.1 MB), removed 0, in 1.5 s", "sim: run 1/3 started (seed 1)", "sim: run 2/3 started (seed 2)", "sim: run 1 at 1:00 (level 2)"):
            jobs.parse_line(probe, line)
        p = probe["progress"]
        st = {s["name"]: s["state"] for s in p["stages"]}
        check(st["snapshot"] == "done" and st["run 1"] == "running" and st["run 2"] == "running" and p["stage"].startswith("0 of 3 runs done · run 1 at 1:00 · run 2 at 0:00"),
              "job: the runs running and their clocks: %s" % p["stage"])
        jobs.parse_line(probe, "sim: run 2/3 failed: no JSON written (exit 1)")
        jobs.parse_line(probe, "sim: run 1/3 done: limit at 2:00, 0 deaths, 33 s (exit 0)")
        st = {s["name"]: s for s in probe["progress"]["stages"]}
        check(st["run 1"]["state"] == "done" and st["run 2"]["state"] == "failed" and "no JSON" in (st["run 2"].get("note") or "") and probe["progress"]["stage"].startswith("2 of 3 runs done"),
              "job: done and failed runs: %s" % probe["progress"]["stage"])
        jobs.parse_line(probe, "sim: done: 2 of 3 runs in 0:48 -> x")
        check({s["name"]: s["state"] for s in probe["progress"]["stages"]}["charts"] == "done" and probe["progress"]["stage"] == "done: 2 of 3 runs", "job: the end")
        # a real run of the driver (made-up runs, no Godot) through the worker's own functions
        taken = jobs._take_next("sim")
        check(taken is job and job["state"] == "running" and jobs._take_next("comfy") is None, "job: the sim lane takes it (the other lanes do not)")
        jobs._run(job)
        check(job["state"] == "done" and os.path.isfile(os.path.join(out, "result.json")) and os.path.isfile(os.path.join(out, "head.json")),
              "job: the driver ran to done with its result: %s %s" % (job["state"], job.get("error")))
        res = SB.read_json(os.path.join(out, "result.json"))
        check(res and res["meta"]["job"] == job["id"] and res["summary"]["ok"] == 3 and not res["meta"]["partial"], "job: the result names its job, 3 runs, not partial")
        st = {s["name"]: s["state"] for s in job["progress"]["stages"]}
        check(all(v == "done" for v in st.values()), "job: every stage done: %s" % st)
        check(not os.path.isdir(os.path.join(locks.LOCK_DIR, "sim.lock")), "job: a made-up sim never takes the sim lock")
        # a re-queue gets a folder of its own (a new history entry)
        jobs.requeue(job["id"])
        check(job["plan"]["sim_out"].endswith(job["id"] + "_a2"), "job: a re-queue's own folder: %s" % job["plan"]["sim_out"])
        jobs.cancel(job["id"])
        # a cancel kills the driver's tree
        j2 = jobs.enqueue("sim", {"kind": "sim", "id": "red_canyon"}, {"players": 2, "workers": 2, "limit": 600, "synthetic": True, "synthetic_speed": 5})
        job2 = jobs._find(j2["id"])
        jobs._take_next("sim")
        th = threading.Thread(target=jobs._run, args=(job2,), daemon=True)
        th.start()
        t0 = time.time()
        while time.time() - t0 < 30 and not any(s["state"] == "running" and s["name"].startswith("run") for s in job2["progress"]["stages"]):
            time.sleep(0.2)
        pid = job2.get("pid")
        jobs.cancel(job2["id"])
        th.join(30)
        check(job2["state"] == "cancelled" and pid and not locks.pid_alive(pid), "job: Cancel kills the driver (state %s, pid %s alive %s)" % (job2["state"], pid, pid and locks.pid_alive(pid)))
    finally:
        for k, v in saved.items():
            setattr(jobs, k, v)
        for k, v in saved_locks.items():
            setattr(locks, k, v)
        jobs._state, jobs._hooks, jobs._root, cur, jobs._queue_lock, jobs._readonly = saved_state
        jobs._lane_current.update(cur)
        jobs._live.clear()


def _page_checks(check, run_node, SB, tmp):
    st = {"players": 4, "limit": 600, "death": "gold"}
    ps = [(k, SB.synthetic_player(k, k, st), {"seed": k}) for k in range(1, 5)]
    res = SB.aggregate(ps, st, {}, game_dir=os.path.join(ROOT, "game"))
    cmp = SB.aggregate([(k, SB.synthetic_player(k, 40 + k, dict(st, death="keep")), {"seed": 40 + k}) for k in range(1, 4)], dict(st, death="keep", players=3), {},
                       game_dir=os.path.join(tmp, "nogame"))
    speed = {"play_per_wall": 3.1, "workers": 6, "boot_s": 14}
    eta = [{"s": dict(SB.DEFAULTS), "speed": speed, "cores": 16, "sync": 20}, {"s": dict(SB.DEFAULTS, players=10, workers=10), "speed": speed, "cores": 16, "sync": 20},
           {"s": dict(SB.DEFAULTS, players=3, workers=6, limit=600), "speed": {}, "cores": 8, "sync": 120},
           {"s": dict(SB.DEFAULTS), "speed": {"play_per_wall": 3.0, "slow": 2.6, "workers": 10, "boot_s": 20}, "cores": 16, "sync": 20}]
    clean = [{"players": 0}, {"players": 5, "workers": 9}, {"limit": 5}, {"death": "no"}, {}]
    bare = json.loads(json.dumps(res))
    for k in ("danger", "danger_net", "keep_up", "boss_s", "near3", "near6", "trouble", "hits_ps", "spawned_ps", "kills_ps", "mult_hp", "mult_dmg", "cap"):
        bare["series"].pop(k, None)
    for k in ("took_by", "healed_by", "held_by"):
        bare["breakdowns"].pop(k, None)
    out = run_node({"res": res, "cmp": cmp, "bare": bare, "t": 300, "eta": eta, "clean": clean}, RUNNER)
    if out is None:
        print("SIM77 page: node is not here: the page checks are skipped")
        return
    if not out:
        return
    # pass 82 (lane STATS): "pickups" (chests, power-ups, totems) after the kills
    check(out["ids"] == ["dps", "hp", "playing", "deaths", "danger", "keep_up", "near", "alive_by", "trouble", "hurt", "hits", "heal", "cap", "flow",
                         "strength", "gold", "dmg", "kills", "pickups", "level", "xp", "build"],
          "page: the charts in Garry's order, the difficulty ones round 2's (made-up runs carry every field): %s" % out["ids"])
    check(out["sections"] == ["hero", "death", "difficulty", "rewards", "growth", "perf"] and out["secOf"] == {"dps": "hero", "playing": "death", "danger": "difficulty",
                                                                                                       "gold": "rewards", "build": "growth"},
          "page: the five sections: %s" % out["sections"])
    check(out["lacking"] == [] and len(out["lackingBare"]) == 9 and out["idsBare"] == ["dps", "hp", "playing", "deaths", "alive_by", "gold", "dmg", "kills", "pickups", "level", "xp"],
          "page: a result without round 2's data draws the rest and names what is missing: %s" % out["idsBare"])
    check(out["range"][0] < 0 and 0 in out["range"][2] and out["range"][2][0] == out["range"][0] and out["range"][2][-1] == out["range"][1],
          "page: an axis below 0 for the net danger, with 0 a tick: %s" % out["range"])
    check(all(h[2] > 60 for h in out["how"]), "page: every chart says what it shows and how it was averaged")
    hw = {h[0]: h for h in out["how"]}
    check(hw["dps"][3] == 2 and hw["dps"][4] == 1 and hw["hp"][3] == 2 and hw["alive_by"][5] >= 2 and hw["kills"][5] >= 2 and hw["dmg"][5] >= 2,
          "page: DPS real + estimate with a band, HP and max HP, the stacks: %s" % out["how"])
    ov = {o[0]: o for o in out["overlays"]}
    check(all(ov[k][1] == 1 for k in ("dps", "hp", "playing", "deaths", "danger", "keep_up", "near", "alive_by", "gold", "dmg", "kills", "level", "xp"))
          and ov["dps"][2] == "compared: real DPS", "page: the charts get the compared sim's line: %s" % out["overlays"][:3])
    check(out["raw"] == ["dps_raw", 0], "page: the per-second DPS has no band: %s" % out["raw"])
    check(dict(out["max"])["playing"] == 100 and all(m[1] > 0 for m in out["max"]), "page: the axis tops (the share chart to 100%%): %s" % out["max"])
    rd = out["read"]
    check(rd[0]["kind"] == "line" and rd[0]["value"] == res["series"]["dps"]["mean"][300] and "–" in rd[0]["sub"] and rd[1]["dash"] == "3 3",
          "page: the readout at a second: the value, the band, the estimate dashed: %s" % rd[:2])
    check(out["readKills"][0] == ["total", "total"] and all(k == "stack" for k, _ in out["readKills"][1:]), "page: a stack's readout: the total, then each part")
    check(all(out["shared"]) and len(out["shared"]) >= 1 and len(out["palette"]) <= 8, "page: the creature charts share their colours, at most eight: %s" % out["palette"])
    tb = out["table"]
    check(tb[0][0] == "time" and tb[2] == 0 and tb[3] == len(res["t"]) - 1 and tb[1] == (len(res["t"]) - 1) // 60 + 1 + (1 if (len(res["t"]) - 1) % 60 else 0),
          "page: the table every minute and the last second: %s" % tb[1:])
    check(out["csv"][0].startswith("time,") and out["csv"][1].startswith("0,") and out["csv"][2].startswith("1,"), "page: the CSV every second: %s" % out["csv"][:2])
    tl = [t[0] for t in out["tiles"]]
    check(tl[:6] == ["Runs that reached 10:00", "A run ended at (median)", "Deaths a run", "Level at the end", "Kills a run", "Coins a run"], "page: the stat tiles: %s" % tl)
    fo = out["fold"]
    check(fo["ids"] == ["c0", "c1", "c2", "c4", "c5", "c6", "c3"] and fo["colors"] == ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300", "#9085e9"],
          "page: a fold keeps the 7 biggest in first-seen order with the slots in order: %s" % fo["ids"])
    check(fo["other"][0] == "Other (3)" and fo["other"][1] == ["c7", "c8", "c9"] and fo["other"][2] == [0, 3, 3 * 2 + 7 + 8 + 9] and fo["label0"] == "Zero",
          "page: the rest summed into Other: %s" % fo["other"])
    check(out["fold2"] == [2, False], "page: a small breakdown has no Other")
    check(out["otherSub"] == [["Other (3)", 27, "10 Nine, 9 c8, 8 c7"]], "page: the readout names the biggest inside Other: %s" % out["otherSub"])
    check(out["fold3"] == [["p0"], ["x"]], "page: with every slot used, a new id goes into Other: %s" % out["fold3"])
    tk = out["ticks"]
    check(tk[0][:3] == [0, 180, 360] and tk[1][:3] == [0, 30, 60] and tk[2] == [0, 200, 400, 600, 800] and tk[3] == 1 and tk[4] == 100, "page: ticks: %s" % tk)
    check(out["labels"] == ["5K", "2,500", "2M", "25%", "0"], "page: one unit per axis: %s" % out["labels"])
    check(out["fmt"] == ["25:00", "1:00", "1:02:05", 1500, 1500, 420, None, "1,234", "12.3K", "2.35", "1.5M"], "page: formats: %s" % out["fmt"])
    check(out["names"] == ["Tumbleweed", "Gila", "Brander"], "page: a boss marker's short name: %s" % out["names"])
    check(out["clean"] == [[1, 1, 1500, "end", 1], [5, 5, 1500, "end", 0], [10, 10, 30, "end", 1], [10, 10, 1500, "end", 1], [10, 10, 1500, "end", 0]],
          "page: the settings' checks (workers never above runs): %s" % out["clean"])
    saved = SB.cores
    try:
        for e, js in zip(eta, out["eta"]):
            SB.cores = lambda c=e["cores"]: c
            py = SB.eta_seconds(e["s"], dict(e["speed"]) if e["speed"] else {"play_per_wall": 2.5, "boot_s": 18.0, "workers": 6}, sync_s=e["sync"])
            check(py == js, "page: the ETA is sim_batch's: js %s py %s (%s)" % (js, py, e["s"]["players"]))
    finally:
        SB.cores = saved
    sm = out["smooth"]
    check(sm[:6] == [10, 5, 10 / 3.0, 2.5, 2, 2] and sm[6] is None and sm[7:] == [4, 4], "page: the rolling mean restarts after a gap: %s" % sm)
    check(out["partial"] == [4, 3, 7, 100], "page: shares and words count the runs in the result (a partial one too): %s" % out["partial"])
    check(out["board"] == ["AA", "ABBB", "BBB", "2 Padding, 1 Plate", "my save (4 of 48 ranks)", 4, "x", None], "page: the board editor's maths: %s" % out["board"])
    check(out["secTicks"] == ["2:30", "50 s", "1.2%", "×1.4"], "page: the new formats: %s" % out["secTicks"])
    check(out["settingsLine"] == "Drifter · 10 runs to 25:00 · Upgrade board a quarter · revive with gold, then the run ends · seed 3", "page: the header line: %s" % out["settingsLine"])
    check(out["fastLine"].endswith(" · everything drawn (sim mode off)") and out["fastClean"] == [True, False, False, True],
          "page: the Drawing switch: the settings carry fast (on unless switched off), the header names a sim that drew everything: %s %s" % (out["fastLine"], out["fastClean"]))
    # the wiring
    html = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
    check('data-tab="sim"' in html and 'id="tab-sim" class="tab-panel page"' in html and 'href="sim.css"' in html, "page: index.html has the tab, its panel and its styles")
    tabs = [m for m in __import__("re").findall(r'data-tab="([a-z]+)"', html)]
    check(tabs[:2] == ["timeline", "sim"], "page: the Sim tab right after Timeline (Garry, round 2): %s" % tabs[:4])
    order = [html.find('src="%s"' % n) for n in ("app.js", "boss_attacks.js", "sim_model.js", "sim.js", "instructions.js")]
    check(all(x > 0 for x in order) and order == sorted(order), "page: sim_model.js then sim.js after app.js, before instructions.js: %s" % order)
    app = open(os.path.join(HERE, "app.js"), encoding="utf-8").read()
    check("S.tab === 'sim' && typeof Sim !== 'undefined') Sim.render(panel)" in app, "page: app.js renders the Sim tab")
    jjs = open(os.path.join(HERE, "jobs.js"), encoding="utf-8").read()
    check("if (t.kind === 'sim') { App.switchTab('sim'); return; }" in jjs and "kind === 'sim' || (job && job.kind === 'sim')" in jjs, "page: a sim job's card opens the Sim tab")
    p = subprocess.run(["node", "--check", os.path.join(HERE, "sim.js")], capture_output=True, text=True)
    check(p.returncode == 0, "page: sim.js parses: %s" % p.stderr[-200:])


def checks(check, run_node, server):
    import sim_batch as SB
    tmp = tempfile.mkdtemp(prefix="le_sim77_")
    try:
        _agg_checks(check, SB, tmp)
        _round2_checks(check, SB, os.path.join(tmp, "r2"))
        _sync_checks(check, SB, os.path.join(tmp, "sync"))
        _lock_checks(check, SB, tmp)
        _routes_checks(check, SB, os.path.join(tmp, "routes"))
        _job_checks(check, SB, os.path.join(tmp, "job"))
        _page_checks(check, run_node, SB, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

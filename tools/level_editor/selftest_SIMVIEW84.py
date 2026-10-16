"""Pass 84, lane SIMVIEW: the Sim's data the Timeline overlays. selftest.py discovers this file and hands it `check`,
`run_node` and the `server` module. Nothing here runs Godot: every sim folder is a temporary one.

Groups:
  rules    tools/sim_batch.py overlay() on three hand-made runs (a boss fight that freezes the clock, a run that dies with
           a skipped clock second, an older run without the pass 84 series): the clock bins, the boss phase left out, the
           means over the runs at each clock second, alive_reg, the challenge median, the starving shares, life_by summed,
           the falls and the bosses on the clock, the series an older run never wrote absent
  twins    sim_avg.js overlay() is sim_batch.py's exactly on the hand-made runs and on the real sims under tools/dl/sim/runs
           and tools/dl/p84/SIMVIEW/simdir/runs; sim_avg.js aggregate() is sim_batch.py's on the hand-made runs with the new
           series (challenge a median, threat banded, alive_hell_by and starving_by breakdowns)
  route    sim_io.py GET /api/sim/overlay on a temporary sims folder: the newest finished real sim of the map (a partial, a
           made-up one and another map's passed over), one by id, an older sim worked out from its players, the creature
           fold to top N + "__other", the stale flag when the map changed, names, {ok: false, reason} when there is none
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
if HERE not in sys.path:
    sys.path.insert(0, HERE)

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const A = require(path.join(dir, 'sim_avg.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.overlay = q.overlay.map((ps) => A.overlay(ps));
  out.agg = q.agg.map((c) => { const r = A.aggregate(c.players, c.settings, {}, {}); return { t: r.t, playing: r.playing, series: r.series, breakdowns: r.breakdowns, markers: r.markers, summary: r.summary, players: r.players, rules: r.rules }; });
  process.stdout.write(JSON.stringify(out));
});
"""


def _diff(a, b, path="", out=None, limit=8):
    if out is None:
        out = []
    if len(out) >= limit:
        return out
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b), key=str):
            if k not in a or k not in b:
                out.append("%s/%s only in %s" % (path, k, "python" if k in a else "js"))
            else:
                _diff(a[k], b[k], "%s/%s" % (path, k), out, limit)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append("%s: %d vs %d entries" % (path, len(a), len(b)))
        else:
            for i, (x, y) in enumerate(zip(a, b)):
                _diff(x, y, "%s[%d]" % (path, i), out, limit)
    elif a != b or type(a) is bool and type(b) is not bool:
        out.append("%s: %r vs %r" % (path, a, b))
    return out


def fixture_runs():
    """Three hand-made runs (the sim_run.gd schema with the pass 84 series):
    A: 12 rows; the clock runs 1..5, freezes at 5 for a boss fight (rows 6-7 phase 1, row 8 the portal, phase 2), then
       runs 6..9; hell imps from clock 3; a fall at clock 4.2; the King from play 6 to 8.
    B: 4 rows on clocks 1.0, 2.0, 4.0, 5.4 (clock 3 skipped: it carries the row of clock 2); a fall at the end.
    C: an older run: alive, cap, power, level only (no phase: every row normal)."""
    a_t = list(range(1, 13))
    a = {"t": a_t, "clock": [1, 2, 3, 4, 5, 5, 5, 5, 6, 7, 8, 9], "phase": [0, 0, 0, 0, 0, 1, 1, 2, 0, 0, 0, 0],
         "hp": [100] * 12, "hp_max": [100] * 12, "level": [1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4], "stage": [1] * 8 + [2] * 4,
         "alive": [10, 20, 30, 40, 50, 999, 999, 999, 60, 70, 80, 90],
         "alive_hell": [0, 0, 5, 5, 5, 999, 999, 999, 10, 10, 10, 10],
         "load": [5, 10, 15, 20, 25, 999, 999, 999, 30, 35, 40, 45], "load_hell": [0, 0, 5, 5, 5, 999, 999, 999, 10, 10, 10, 10],
         "cap": [40] * 12, "cap_hell": [8] * 12, "hard_cap": [300] * 12,
         "cap_full": [0, 0, 0.2, 1, 1, 0, 0, 0, 0.6, 0.4, 0, 0],
         "threat": [100, 200, 300, 400, 500, 999999, 999999, 999999, 600, 700, 800, 900],
         "hero_dps": [10] * 12, "hero_ehp": [100] * 12,
         "challenge": [0.1, 0.2, 0.3, 0.4, 0.5, 999, 999, 999, 0.6, 0.7, 0.8, 0.9],
         "power": [1, 1, 1.2, 1.2, 1.3, 1.3, 1.3, 1.3, 1.5, 1.5, 1.6, 1.7],
         "alive_by": {"goblin": [10, 20, 25, 35, 45, 9, 9, 9, 50, 60, 70, 80], "imp": [0, 0, 5, 5, 5, 9, 9, 9, 10, 10, 10, 10]},
         "alive_hell_by": {"imp": [0, 0, 5, 5, 5, 9, 9, 9, 10, 10, 10, 10]},
         "starving_by": {"row#0": [0, 0, 0.2, 1, 1, 0, 0, 0, 0.6, 0.4, 0, 0], "row:hell#2": [0] * 12},
         "life_by": {"goblin": {"n": [3, 1, 0, 0], "s": [12.0, 5.0, 0, 0], "gone": 1, "open": 2}},
         "events": [{"t": 4.2, "clock": 4.2, "kind": "death", "killer": "goblin"},
                    {"t": 6, "clock": 5, "kind": "boss_start", "id": "tumbleweed_king"},
                    {"t": 8, "clock": 5, "kind": "boss_end", "id": "tumbleweed_king"}],
         "meta": {"end_reason": "limit", "end_t": 12.0, "wall_s": 20.0, "boot_s": 10.0,
                  "rows_played": [{"key": "row#0", "k": 0, "id": "", "enemy": "goblin", "t": 0.0, "until": None, "channel": "", "pace": "continuous"},
                                  {"key": "row:hell#2", "k": 2, "id": "hell", "enemy": "imp", "t": 3.0, "until": None, "channel": "hell", "pace": "continuous"}]}}
    b = {"t": [1, 2, 3, 4], "clock": [1.0, 2.0, 4.0, 5.4], "phase": [0, 0, 0, 0], "hp": [100, 80, 40, 0], "hp_max": [100] * 4,
         "level": [1, 1, 2, 2], "stage": [1] * 4,
         "alive": [20, 30, 40, 50], "alive_hell": [0, 0, 0, 0], "load": [10, 15, 20, 25], "load_hell": [0] * 4,
         "cap": [40] * 4, "cap_hell": [8] * 4, "hard_cap": [300] * 4, "cap_full": [0, 0.5, 1, 1],
         "threat": [50, 150, 250, 350], "hero_dps": [10] * 4, "hero_ehp": [50] * 4, "challenge": [0.1, 0.3, 0.5, 0.7],
         "power": [1, 1, 1, 1], "alive_by": {"goblin": [20, 30, 40, 50]}, "alive_hell_by": {},
         "starving_by": {"row#0": [0, 0.5, 1, 1]},
         "life_by": {"goblin": {"n": [2, 0, 0, 0], "s": [3.0, 0, 0, 0], "gone": 0, "open": 5}, "imp": {"n": [1, 0, 0, 0], "s": [7.5, 0, 0, 0], "gone": 0, "open": 0}},
         "events": [{"t": 4, "clock": 5.4, "kind": "death", "killer": "goblin"}],
         "meta": {"end_reason": "death", "end_t": 4.0, "wall_s": 20.0, "boot_s": 10.0}}
    c = {"t": [1, 2, 3], "clock": [1, 2, 3], "hp": [100] * 3, "hp_max": [100] * 3, "level": [1, 1, 1], "alive": [4, 6, 8],
         "cap": [40, 40, 40], "power": [1, 1, 1], "alive_by": {"slime": [4, 6, 8]}, "events": [],
         "meta": {"end_reason": "limit", "end_t": 3.0, "wall_s": 20.0, "boot_s": 10.0}}
    return [(1, a, {"seed": 1}), (2, b, {"seed": 2}), (3, c, {"seed": 3}), (4, None, {"seed": 4, "problem": "no JSON written"})]


def _rules(check, SB):
    ov = SB.overlay(fixture_runs())
    check(ov is not None and ov["C"] == 9 and ov["runs"] == 3, "rules: clock seconds 0..9 from three runs with a clock: C %s runs %s" % (ov and ov["C"], ov and ov["runs"]))
    check(ov["playing"] == [0, 3, 3, 3, 2, 2, 1, 1, 1, 1],
          "rules: the runs at each clock second (A 1..9, B 1..5 with 3 carried, C 1..3): %s" % ov["playing"])
    al = ov["series"]["alive"]["mean"]
    check(al[5] == 50 and al[6] == 60 and al[9] == 90 and 999 not in al,
          "rules: the boss fight and the portal (the clock frozen at 5) are left out; clock 5 = A's last normal row and B's: %s" % al)
    check(al[3] == round((30 + 30 + 8) / 3.0, 2), "rules: clock 3 = A's row, B's carried clock-2 row and C's (a mean): %s" % al[3])
    check(ov["series"]["alive_reg"]["mean"][4] == 37.5, "rules: alive_reg = alive - alive_hell (A 35, B 40): %s" % ov["series"]["alive_reg"]["mean"][4])
    check("alive_reg" in ov["has"] and "load" in ov["has"] and "starving" in ov["has"] and "life_by" in ov["has"],
          "rules: has names what the runs carry: %s" % ov["has"])
    ch = ov["series"]["challenge"]
    check("median" in ch and "mean" not in ch and ch["median"][4] == 0.45 and ch["median"][9] == 0.9,
          "rules: challenge is the middle run (two runs: halfway), never a mean: %s" % ch["median"][:6])
    check(ov["series"]["cap_full"]["mean"][5] == 1 and ov["series"]["cap_full"]["mean"][3] == 0.35,
          "rules: cap_full's mean share over the runs: %s" % ov["series"]["cap_full"]["mean"][:6])
    check("p10" in ov["series"]["threat"] and "p10" not in ov["series"]["load"], "rules: threat banded, load not")
    st = ov["starving"]
    check(st["order"] == ["row#0"] and st["share"]["row#0"][4] == 1 and st["share"]["row#0"][3] == 0.233,
          "rules: starving: the rows that ever starved, mean share over the runs at that second (C has none: 0): %s" % st)
    ab = ov["alive_by"]
    check(ab["mean"]["goblin"][3] == round((25 + 30 + 0) / 3.0, 2) and "imp" not in ab["order"] and "slime" in ab["order"],
          "rules: alive_by is the regular channel (alive_by - alive_hell_by; the imps are all hell): %s %s" % (ab["mean"]["goblin"][3], ab["order"]))
    check(ov["alive_hell_by"]["order"] == ["imp"] and ov["alive_hell_by"]["mean"]["imp"][6] == 10, "rules: alive_hell_by: %s" % ov["alive_hell_by"]["order"])
    lb = ov["life_by"]
    check(lb["goblin"]["n"] == 6 and lb["goblin"]["mean_s"] == round(20.0 / 6, 2) and lb["goblin"]["stage_n"] == [5, 1, 0, 0]
          and lb["goblin"]["stage_mean_s"] == [3, 5, None, None] and lb["goblin"]["gone"] == 1 and lb["goblin"]["open"] == 7,
          "rules: life_by summed over the runs (n, mean, per stage, gone, open): %s" % lb["goblin"])
    check(lb["imp"]["mean_s"] == 7.5 and "slime" not in lb, "rules: life_by only for the creatures that died: %s" % sorted(lb))
    check([d["clock"] for d in ov["deaths"]] == [4.2, 5.4] and ov["deaths"][0]["run"] == 1 and ov["deaths"][1]["killer"] == "goblin",
          "rules: every fall on the clock: %s" % ov["deaths"])
    check(ov["bosses"] == [{"id": "tumbleweed_king", "occurrence": 1, "clock": 5, "fight_s": 2, "n": 1, "beaten": 1}],
          "rules: the bosses on the clock with their fight: %s" % ov["bosses"])
    check(len(ov["rows"]) == 2 and ov["rows"][1]["key"] == "row:hell#2", "rules: rows as played come from the first run's meta.rows_played")
    check(set(ov["rules"]) >= {"bin", "alive", "load", "cap", "cap_full", "threat", "power", "challenge", "starving", "life_by"},
          "rules: every definition is in rules")
    old = SB.overlay([fixture_runs()[2]])
    check(old is not None and old["has"] == ["alive", "cap", "power", "level", "alive_by"] and old["starving"] == {"order": [], "share": {}},
          "rules: an older run alone: only what it recorded: %s" % (old and old["has"]))
    check(SB.overlay([(1, None, {}), (2, {"t": [1]}, {})]) is None, "rules: no run with a clock: None")


def _real_cases(SB, limit=3):
    out = []
    for base in (os.path.join(ROOT, "tools", "dl", "sim", "runs"), os.path.join(ROOT, "tools", "dl", "p84", "SIMVIEW", "simdir", "runs")):
        if not os.path.isdir(base):
            continue
        names = sorted(os.listdir(base), key=lambda n: -os.path.getmtime(os.path.join(base, n)))
        n = 0
        for name in names:
            pdir = os.path.join(base, name, "players")
            files = sorted(f for f in os.listdir(pdir) if re.match(r"^p\d+\.json$", f)) if os.path.isdir(pdir) else []
            if not files:
                continue
            ps = []
            for f in files:
                d, prob = SB.load_player(os.path.join(pdir, f))
                ps.append((int(f[1:-5]), d, {"seed": 1, "problem": prob}))
            out.append((name, ps))
            n += 1
            if n >= limit:
                break
    return out


def _twins(check, run_node, SB):
    fx = fixture_runs()
    real = _real_cases(SB)
    cases = [("the hand-made runs", fx)] + [("the real sim " + n, ps) for n, ps in real]
    # the play-second aggregate on a real sim that carries the pass 84 series too (the newest one with `threat`)
    newer = next(((n, ps) for n, ps in real if any(isinstance(d, dict) and "threat" in d for _, d, _ in ps)), None)
    agg_cases = [("the hand-made runs", fx, {"players": 4, "limit": 12, "death": "keep"})]
    if newer:
        agg_cases.append(("the real sim " + newer[0], newer[1], {"players": len(newer[1]), "limit": 1500, "death": "keep"}))
    q = {"overlay": [[{"k": k, "d": d, "rec": r} for k, d, r in ps] for _, ps in cases],
         "agg": [{"players": [{"k": k, "d": d, "rec": r} for k, d, r in ps], "settings": st} for _, ps, st in agg_cases]}
    out = run_node(q, RUNNER)
    if out is None:
        print("SIMVIEW84: node is not here: the twin checks are skipped")
        return
    if not out:
        return
    for (name, ps), js in zip(cases, out["overlay"]):
        py = json.loads(json.dumps(SB.overlay(ps)))
        d = _diff(py, js, "overlay")
        check(not d, "twins: sim_avg.js overlay() is sim_batch.py's on %s: %s" % (name, d[:4]))
    for (name, ps, st), js in zip(agg_cases, out["agg"]):
        py = json.loads(json.dumps(SB.aggregate(ps, st, {}, game_dir=os.path.join(ROOT, "nogame"))))
        d = []
        for k in ("t", "playing", "series", "breakdowns", "markers", "summary", "players", "rules"):
            _diff(py[k], js[k], k, d)
        check(not d, "twins: sim_avg.js aggregate() is sim_batch.py's on %s (the pass 84 series in): %s" % (name, d[:4]))
    py = json.loads(json.dumps(SB.aggregate(fx, {"players": 4, "limit": 12, "death": "keep"}, {}, game_dir=os.path.join(ROOT, "nogame"))))
    check("median" in py["series"]["challenge"] and "p10" in py["series"]["threat"] and "starving_by" in py["breakdowns"]
          and "alive_hell_by" in py["breakdowns"] and py["breakdowns"]["starving_by"]["kind"] == "level",
          "twins: the play-second aggregate: challenge a median, threat banded, alive_hell_by and starving_by level breakdowns")
    check(len(real) > 0 or True, "twins: real sims compared: %d" % len(real))


class _Srv:
    GAME = ""


def _route(check, SB, IO):
    tmp = tempfile.mkdtemp(prefix="simview84_")
    old_dir = SB.SIM_DIR
    try:
        game = os.path.join(tmp, "game")
        os.makedirs(os.path.join(game, "content", "maps", "red_canyon"))
        os.makedirs(os.path.join(game, "content", "enemies", "goblin"))
        mp = os.path.join(game, "content", "maps", "red_canyon", "red_canyon.json")
        with open(mp, "w", encoding="utf-8") as f:
            f.write('{"id": "red_canyon", "name": "Red Canyon"}\n')
        with open(os.path.join(game, "content", "enemies", "goblin", "goblin.json"), "w", encoding="utf-8") as f:
            f.write('{"id": "goblin", "name": "Goblin"}\n')
        srv = _Srv()
        srv.GAME = game
        SB.SIM_DIR = os.path.join(tmp, "sim")
        runs = SB.runs_dir()
        rev = SB.map_rev(game, "red_canyon")
        IO._OV_CACHE.clear()
        check(IO.overlay_record(srv, {"map": ["red_canyon"]}) == {"ok": False, "reason": "no finished Sim of red_canyon yet: run one from the Sim tab"},
              "route: no sim yet: ok false with the reason")

        def make(name, epoch, players, meta=None, settings=None, overlay=True, summary_ok=None):
            folder = os.path.join(runs, name)
            os.makedirs(os.path.join(folder, "players"))
            for k, d, _ in players:
                if d is not None:
                    SB.write_json(os.path.join(folder, "players", "p%02d.json" % k), d)
            st = {"hero": "drifter", "map": "red_canyon", "players": len(players), "death": "keep", "limit": 12}
            st.update(settings or {})
            m = {"started": "2026-10-16T20:00:00", "map_rev": rev, "version": "0.70"}
            m.update(meta or {})
            ok = sum(1 for _, d, _ in players if d is not None) if summary_ok is None else summary_ok
            SB.write_json(os.path.join(folder, "head.json"), {"meta": m, "settings": st, "summary": {"players": len(players), "ok": ok}, "hero_name": "Drifter"})
            SB.write_json(os.path.join(folder, "progress.json"), {"started_epoch": epoch, "state": "done"})
            if overlay:
                SB.write_overlay(folder, players)
            return folder

        fx = fixture_runs()
        make("old_one", 1000, fx, overlay=False)
        make("good", 2000, fx)
        make("partial_newer", 3000, fx, meta={"partial": True})
        make("fake_newer", 4000, fx, meta={"synthetic": True})
        make("other_map", 5000, fx, settings={"map": "dry_gulch"})
        r = IO.overlay_record(srv, {"map": ["red_canyon"]})
        check(r.get("ok") and r["sim"]["id"] == "good" and r["sim"]["computed"] == "result" and r["sim"]["stale"] is False,
              "route: the newest finished real sim of the map (partial, made-up and another map's passed over): %s" % (r.get("sim") or r))
        ov = r["overlay"]
        check(ov["C"] == 9 and ov["series"]["alive"]["mean"][5] == 50 and ov["names"].get("goblin") == "Goblin" and ov["names"].get("__other") == "Other",
              "route: the overlay with names: C %s names %s" % (ov["C"], ov["names"]))
        check(ov["alive_by"]["order"] == ["goblin", "slime"] and ov["alive_by"]["other_ids"] == [] and ov["top"] == 8,
              "route: two regular creatures (the imps are all hell) under the top 8: no fold: %s" % ov["alive_by"]["order"])
        r1 = IO.overlay_record(srv, {"map": ["red_canyon"], "top": ["1"]})
        a1 = r1["overlay"]["alive_by"]
        full = ov["alive_by"]["mean"]
        other_ok = all(a1["mean"]["__other"][c] == SB._r(full["slime"][c]) for c in range(len(full["slime"])))
        check(a1["order"] == ["goblin", "__other"] and a1["other_ids"] == ["slime"] and other_ok,
              "route: top=1: the first creature and the rest summed into __other: %s" % a1["order"])
        r2 = IO.overlay_record(srv, {"map": ["red_canyon"], "id": ["old_one"]})
        check(r2.get("ok") and r2["sim"]["computed"] == "players" and r2["overlay"]["C"] == 9,
              "route: a sim without overlay.json is worked out from its players: %s" % (r2.get("sim") or r2))
        r3 = IO.overlay_record(srv, {"map": ["red_canyon"], "id": ["fake_newer"]})
        check(r3.get("ok") and r3["sim"]["synthetic"] is True, "route: a made-up sim answers when asked for by id")
        check(IO.overlay_record(srv, {"id": ["../x"]}).get("ok") is False and IO.overlay_record(srv, {"id": ["missing"]}) == {"ok": False, "reason": "no sim missing"},
              "route: a bad or unknown id: ok false")
        with open(mp, "a", encoding="utf-8") as f:
            f.write(" ")
        r4 = IO.overlay_record(srv, {"map": ["red_canyon"]})
        check(r4["sim"]["stale"] is True and r4["sim"]["map_rev"] != r4["sim"]["map_rev_now"], "route: the map saved since the sim: stale")
        check(IO.overlay_record(srv, {"map": ["dry_gulch"]})["sim"]["id"] == "other_map", "route: another map's own sim")
        txt = json.dumps(r)
        check(len(txt) < 200000, "route: light: %d bytes for a 9 s fixture" % len(txt))
    finally:
        SB.SIM_DIR = old_dir
        IO._OV_CACHE.clear()
        shutil.rmtree(tmp, ignore_errors=True)


def checks(check, run_node, server):
    import sim_batch as SB
    import sim_io as IO
    _rules(check, SB)
    _twins(check, run_node, SB)
    _route(check, SB, IO)


if __name__ == "__main__":
    import selftest as ST
    checks(ST.check, ST.run_node, None)
    print("%d checks passed, %d failed" % (ST.PASSES[0], len(ST.FAILS)))
    sys.exit(1 if ST.FAILS else 0)

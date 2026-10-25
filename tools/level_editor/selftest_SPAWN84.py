"""Pass 84, lane SPAWN: one spawning language (Garry: "spawning options are important to me ... But I do agree that
there are too many ways of spawning an enemy right now").

Groups: the converter (model.js convertLegacy against tools/migrate_timeline.py convert_legacy on every legacy kind:
swarms of every pattern, special, lists, missing creatures, chance and jitter; coloured elites; Elites every with a
number, a range and nothing; waves[] with one and several alternatives, every 0, a remainder, until, hell, elite, toast;
bosses and Elite mini-bosses kept; a second conversion changes nothing); the estimate's twins on fixtures with every new
key (once, every ranges, list and "roster" creatures, elite rows with and without a pattern, special, chance, the floor,
the life option) including the new point fields; the migrated Red Canyon's estimate equal to the old one's; the shown
difficulty by hand; the API the Timeline lane builds on; Red Canyon migrated on disk and its file in the editor's layout.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import copy
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import migrate_timeline as MT  # noqa: E402

RUNNER = r"""
const M = require(process.argv[2]);
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.conv = q.conv.map(([tl, skin]) => { const c = JSON.parse(JSON.stringify(tl)); const r = M.convertLegacy(c, { skin }); return { tl: c, res: r, again: M.convertLegacy(JSON.parse(JSON.stringify(c)), { skin }).converted, legacy: M.hasLegacy(tl), after: M.hasLegacy(c) }; });
  out.est = q.est.map(([tl, cr, opts]) => { const e = M.spawnEstimate(tl, cr, opts); return { points: e.points, ids: e.ids, marks: e.marks, fights: e.fights, colourAt: e.colourAt, series: M.estimateSeries(e) }; });
  out.pair = q.pair.map(([tl, cr, opts, skin]) => {
    const b = JSON.parse(JSON.stringify(tl));
    M.convertLegacy(b, { skin });
    const ea = M.spawnEstimate(tl, cr, opts), eb = M.spawnEstimate(b, cr, opts);
    return { a: { points: ea.points, ids: ea.ids, marks: ea.marks, fights: ea.fights, colourAt: ea.colourAt }, b: { points: eb.points, ids: eb.ids, marks: eb.marks, fights: eb.fights, colourAt: eb.colourAt } };
  });
  out.diff = q.diff.map(([tl, c, row, t, opts]) => M.creatureDifficulty(tl, c, row, t, opts));
  out.level = q.level.map(([opts, t]) => M.levelAt(opts, t));
  out.api = ['convertLegacy', 'hasLegacy', 'eventToRow', 'waveToRows', 'rowSingleEnemy', 'rowElite', 'rowInMix', 'rowTimer', 'creatureDifficulty',
    'levelAt', 'estimateSeries', 'spawnEstimate', 'rowPaced', 'rowWaveEvery'].filter((k) => typeof M[k] !== 'function');
  out.consts = { roster: M.ROW_ENEMY_ROSTER, ring: M.SWARM_RING_RADIUS, roles: M.ROW_ROLES, paces: M.ROW_PACES, keys: M.ROW84_KEYS, lvl: M.DEFAULT_LEVEL_CURVE };
  out.flags = q.flags.map((r) => [M.rowSingleEnemy(r), M.rowElite(r), M.rowInMix(r), M.rowTimer(r), M.rowPaced(r), M.rowWaveEvery(r)]);
  process.stdout.write(JSON.stringify(out));
});
"""


def _main_module():
    mod = sys.modules.get("__main__")
    if mod is not None and hasattr(mod, "spawn_estimate") and hasattr(mod, "estimate_diff"):
        return mod
    import selftest
    return selftest


def _close(a, b, eps=1e-9):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


def _same_dict(a, b, eps=1e-9):
    if set(a) != set(b):
        return False
    return all(_close(a[k], b[k], eps) for k in a)


# ---------------------------------------------------------------- fixtures

LEGACY_EVENTS = [
    {"t": 120, "type": "swarm", "enemy": "red_goblin", "variant": "RG-B", "count": 1, "pattern": "in_front", "special": True, "name": "Special Goblin"},
    {"t": 610, "type": "swarm", "enemy": "fire_ant", "count": 24, "name": "Ant swarm", "stats": {"hp_mult": 0.78}},
    {"t": 700, "type": "swarm", "enemy": "imp", "count": 12, "pattern": "pack"},
    {"t": 710, "type": "swarm", "enemy": "imp", "count": 12, "pattern": "pack", "pack": 4},
    {"t": 720, "type": "swarm", "enemy": "imp", "pattern": "scatter"},
    {"t": 730, "type": "swarm", "enemy": ["imp", "fire_ant"], "weights": [2, 1], "count": 9, "pattern": "single"},
    {"t": 740, "type": "swarm", "count": 8, "chance": 0.5, "t_jitter": 20},
    {"t": 215, "type": "elite_boss", "enemy": ["dune_scorpion", "sun_prophet"]},
    {"t": 250, "type": "elite"},
    {"t": 260, "type": "elite", "enemy": "skeleton", "mod": "frenzied", "variant": "SK-A", "stats": {"hp_mult": 2}},
    {"t": 301, "type": "elite_every", "interval": 129},
    {"t": 350, "type": "elite_every", "interval": [60, 90], "enemy": ["skeleton", "goblin"], "weights": [1, 3]},
    {"t": 360, "type": "elite_every"},
    {"t": 430, "type": "boss", "enemy": "tumbleweed_king"},
]
LEGACY_WAVES = [
    {"id": "w1", "t": 100, "until": 200, "count": 23, "burst": 5, "every": 10, "pattern": "ring", "enemy": "skeleton", "pack": 3, "toast": "AMBUSH!"},
    {"id": "w2", "name": "Mixed", "t": 300, "count": 0, "burst": 7, "every": 0, "alts": [{"chance": 2, "enemy": "imp"}, {"chance": 1, "enemy": "goblin", "variant": "GB-B", "stats": {"hp": 30}}]},
    {"t": 400, "burst": 4, "every": 15, "channel": "hell", "elite": "random", "respect_cap": False, "enemy": "imp"},
    {"t": 500, "count": 3, "burst": 5, "every": 0, "enemy": "goblin", "until": 520},
]


def _est_fixtures():
    cr = [
        {"id": "a", "kind": "enemy", "archetype": "walker", "hp": 10, "damage": 2, "cap_share": 1, "pack_size": 5, "max_alive": 0, "variance": {"special_chance": 0.05}},
        {"id": "b", "kind": "enemy", "archetype": "walker", "hp": 20, "damage": 3, "cap_share": 0.5, "pack_size": 8},
        {"id": "c", "kind": "enemy", "archetype": "walker", "hp": 40, "damage": 4, "cap_share": 1, "pack_size": 2, "max_alive": 6, "can_be_elite": False},
        {"id": "e", "kind": "enemy", "archetype": "elite", "hp": 400, "cap_share": 1, "pack_size": 1},
        {"id": "z", "kind": "boss", "archetype": "boss", "hp": 3000, "cap_share": 1, "pack_size": 1},
    ]
    base = {"stage_length": 120, "stages": 2, "cap_curve": [[0, 20], [100, 40]], "cap_max": 100, "hard_cap": 90, "burst_min": 3,
            "burst_max": 9, "spawn_interval": 0.5, "colour_after_kills": 12, "boss_cap_frac": 0.5, "portal_cap": 0, "hell_cap": [0.3, 0.5]}
    tls = []
    t1 = dict(base, roster=[
        {"id": "r1", "t": 0, "enemy": "a", "weights": [[0, 3]]},
        {"id": "r2", "t": 10, "until": 200, "enemy": "b", "weights": [[10, 2]], "pace": "waves", "every": [8, 20], "count": 12, "pattern": "ring"},
        {"id": "r3", "t": 30, "enemy": ["a", "b", "c"], "enemy_weights": [1, 2, 0], "weights": [[30, 1]], "pace": "once", "count": 30, "respect_cap": False, "special": True},
        {"id": "r4", "t": 40, "enemy": "roster", "weights": [[40, 1]], "pace": "waves", "every": 25, "count": 2, "elite": "random"},
        {"id": "r5", "t": 45, "enemy": "roster", "weights": [[45, 1]], "pace": "waves", "every": 20, "count": 6, "pattern": "scatter", "elite": "frenzied", "stats": {"hp_mult": 2}},
        {"id": "r6", "t": 50, "enemy": "c", "weights": [[50, 1]], "pace": "once", "count": 4, "chance": 0.25},
        {"id": "r7", "t": 60, "until": 230, "enemy": ["b", "c"], "weights": [[60, 1], [150, 2]]},
        {"id": "r8", "t": 20, "enemy": "roster", "weights": [[20, 0.5]]},
        {"id": "r9", "t": 70, "enemy": "b", "weights": [[70, 1]], "elite": "random"},
        {"id": "r10", "t": 80, "enemy": "a", "channel": "hell", "weights": [[80, 2]], "special": True},
    ], events=[{"t": 120, "type": "boss", "enemy": "z"}, {"t": 90, "type": "elite_boss", "enemy": "e"}], floor_curve=[[0, 5], [60, 25], [200, 30]])
    tls.append([t1, cr, {"turnover": [0.05, 0.08], "bossSeconds": 15, "portalSeconds": 6, "end": 300, "boss": "z"}])
    tls.append([t1, cr, {"turnover": 0.07, "life": {"a": 4, "b": 9}, "bossSeconds": 10, "portalSeconds": 5, "end": 260, "boss": "z"}])
    t2 = dict(base, roster=[{"id": "r1", "t": 0, "enemy": "b", "weights": [[0, 1]]}], floor_curve=[[0, 60]], cap_curve=[[0, 25]])
    tls.append([t2, cr, {"turnover": 0.2, "end": 90}])
    # an old-shape timeline with every legacy event the estimate reads, its twin agreement and its converted pair
    t3 = dict(base, roster=[{"id": "r1", "t": 0, "enemy": "a", "weights": [[0, 2]]}, {"id": "r2", "t": 5, "enemy": "b", "weights": [[5, 1]]}],
              events=[{"t": 20, "type": "swarm", "enemy": "b", "count": 15}, {"t": 30, "type": "swarm", "enemy": "a", "count": 3, "pattern": "in_front", "special": True},
                      {"t": 35, "type": "elite"}, {"t": 50, "type": "elite_every", "interval": [30, 40]}, {"t": 120, "type": "boss", "enemy": "z"}])
    return tls, cr, t3


# ---------------------------------------------------------------- the checks

def checks(check, run_node, server):
    st = _main_module()
    rc = server.load_json(server.map_path("red_canyon"))
    rc_tl = rc.get("timeline_data", {})
    skin = list((rc.get("skins") or {}).values())[0] if rc.get("skins") else ""
    creatures = server.list_creatures()
    rc_opts = {"turnover": 0.0557, "bossSeconds": 44.2, "portalSeconds": 34.9, "skin": skin, "boss": rc.get("boss", "")}
    # the old Red Canyon (the newest backup that still has its swarm events, else the file itself before migration)
    old_rc = _old_red_canyon(server)

    conv_q = [[{"roster": [{"id": "r1", "t": 0, "enemy": "skeleton"}], "events": copy.deepcopy(LEGACY_EVENTS), "waves": copy.deepcopy(LEGACY_WAVES)}, "skeleton"],
              [{"roster": [], "events": copy.deepcopy(LEGACY_EVENTS[:3])}, ""],
              [{"events": [{"t": 1, "type": "swarm"}]}, "goblin"],
              [{"roster": [{"id": "r1", "t": 0, "enemy": "skeleton"}], "events": [{"t": 430, "type": "boss", "enemy": "tumbleweed_king"}]}, ""]]
    if old_rc is not None:
        conv_q.append([old_rc["timeline_data"], skin])
    tls, cr, t3 = _est_fixtures()
    est_q = tls + [[t3, cr, {"turnover": 0.06, "bossSeconds": 12, "portalSeconds": 5, "end": 240, "boss": "z", "skin": "a"}]]
    pair_q = [[t3, cr, {"turnover": 0.06, "bossSeconds": 12, "portalSeconds": 5, "end": 240, "boss": "z", "skin": "a"}, "a"]]
    if old_rc is not None:
        pair_q.append([old_rc["timeline_data"], creatures, rc_opts, skin])
    by_id = {c["id"]: c for c in creatures}
    sk = by_id.get("skeleton")
    diff_q = []
    if sk:
        diff_q = [[rc_tl, sk, {"t": 176, "enemy": "skeleton", "stats": {"hp": 20}}, 200, {"level": 9}],
                  [rc_tl, sk, {"t": 176, "enemy": "skeleton", "stats": {"hp_mult": 1.5}}, 500, {"level": 20}],
                  [rc_tl, sk, {"t": 600, "enemy": "skeleton", "pace": "once"}, 600, {"levelCurve": [[0, 1], [600, 31]]}]]
    level_q = [[{}, 0], [{"level": 7.4}, 999], [{"levelCurve": [[0, 1], [100, 11]]}, 50]]
    flags_q = [{"enemy": "x"}, {"enemy": "roster"}, {"enemy": ["a", "b"]}, {"enemy": "x", "elite": "random", "pace": "waves"}, {"enemy": "x", "pace": "once"},
               {"enemy": "x", "special": True}, {"enemy": "x", "pace": "waves", "every": [10, 30]}, {"enemy": "x", "elite": False}]
    res = run_node({"conv": conv_q, "est": est_q, "pair": pair_q, "diff": diff_q, "level": level_q, "flags": flags_q}, RUNNER)
    if res is None:
        print("SPAWN84: node not found, the model checks are skipped")
        _file_checks(check, server)
        return
    if not res:
        return

    # ---- the converter twins
    for (tl, sk_id), got in zip(conv_q, res["conv"]):
        mine = copy.deepcopy(tl)
        r = MT.convert_legacy(mine, sk_id)
        check(json.dumps(got["tl"], sort_keys=True) == json.dumps(_js_numbers(mine), sort_keys=True),
              "SPAWN84: convertLegacy = migrate_timeline.convert_legacy (%d events, %d waves): js %s py %s" % (
                  len(tl.get("events") or []), len(tl.get("waves") or []), json.dumps(got["tl"])[:300], json.dumps(mine)[:300]))
        check(got["res"]["ids"] == r["ids"] and got["res"]["converted"] == r["converted"] and got["res"]["notes"] == r["notes"],
              "SPAWN84: the converters report the same: %s / %s" % (got["res"], r))
        check(got["again"] == 0 and not got["after"], "SPAWN84: a converted timeline converts to nothing again (no churn)")
        check(got["legacy"] == MT.has_legacy(tl), "SPAWN84: hasLegacy = has_legacy")
        # bosses and Elite mini-bosses stay events; nothing else does
        check(all(str(e.get("type")) in ("boss", "elite_boss") for e in (got["tl"].get("events") or [])), "SPAWN84: only bosses and Elites stay events")
        # the old rows keep their places
        old_rows = tl.get("roster") or []
        check(got["tl"].get("roster", [])[:len(old_rows)] == old_rows, "SPAWN84: the old rows keep their places and keys")
    full = res["conv"][0]["tl"]
    rows = {r.get("name", r["id"]): r for r in full["roster"][1:]}
    sg = rows.get("Special Goblin", {})
    check(sg.get("pace") == "once" and sg.get("count") == 1 and sg.get("pattern") == "in_front" and sg.get("special") is True and "banner" not in sg
          and sg.get("respect_cap") is False and sg.get("role") == "special" and sg.get("variant") == "RG-B" and sg.get("weights") == [[120, 1]],
          "SPAWN84: a special swarm -> a once special row, no banner: %s" % sg)
    ant = rows.get("Ant swarm", {})
    check(ant.get("pattern") == "ring" and ant.get("ring_radius") == 16 and ant.get("banner") == "SWARM!" and ant.get("count") == 24
          and ant.get("stats") == {"hp_mult": 0.78} and ant.get("role") == "swarm", "SPAWN84: a ring swarm keeps its 16 m ring, count, banner, stats: %s" % ant)
    packs = [r for r in full["roster"] if r.get("t") in (700, 710)]
    check([r.get("pack") for r in packs] == [12, 4], "SPAWN84: a pack swarm without a pack is one pack of its count; with one, its own: %s" % [r.get("pack") for r in packs])
    lst = [r for r in full["roster"] if r.get("t") == 730]
    check(lst and lst[0].get("enemy") == ["imp", "fire_ant"] and lst[0].get("enemy_weights") == [2, 1] and lst[0].get("pattern") == "ring",
          "SPAWN84: a list swarm keeps its list as enemy + enemy_weights; 'single' was a ring for a swarm: %s" % lst)
    nm = [r for r in full["roster"] if r.get("t") == 740]
    check(nm and nm[0].get("enemy") == "skeleton" and nm[0].get("chance") == 0.5 and nm[0].get("t_jitter") == 20 and nm[0].get("count") == 8,
          "SPAWN84: a swarm with no creature takes the skin, its chance and jitter: %s" % nm)
    sc = [r for r in full["roster"] if r.get("t") == 720]
    check(sc and sc[0].get("count") == 40 and sc[0].get("pattern") == "scatter" and "pack" not in sc[0], "SPAWN84: a swarm without a count: 40: %s" % sc)
    ee = [r for r in full["roster"] if r.get("t") == 301]
    check(ee and ee[0].get("pace") == "waves" and ee[0].get("every") == 129 and ee[0].get("enemy") == "roster" and ee[0].get("elite") == "random"
          and ee[0].get("count") == 1 and ee[0].get("role") == "elite" and "until" not in ee[0], "SPAWN84: Elites every -> a waves row of the roster creature: %s" % ee)
    ee2 = [r for r in full["roster"] if r.get("t") == 350]
    check(ee2 and ee2[0].get("every") == [60, 90] and ee2[0].get("enemy_weights") == [1, 3], "SPAWN84: an Elites-every range and list: %s" % ee2)
    ee3 = [r for r in full["roster"] if r.get("t") == 360]
    check(ee3 and ee3[0].get("every") == 90, "SPAWN84: Elites every without an interval: 90 s")
    el = [r for r in full["roster"] if r.get("t") == 260]
    check(el and el[0].get("pace") == "once" and el[0].get("elite") == "frenzied" and el[0].get("enemy") == "skeleton" and el[0].get("variant") == "SK-A",
          "SPAWN84: a coloured elite -> a once elite row: %s" % el)
    w1 = [r for r in full["roster"] if r.get("t") == 100]
    check(w1 and w1[0].get("until") == 150 and w1[0].get("count") == 5 and w1[0].get("every") == 10 and w1[0].get("banner") == "AMBUSH!" and w1[0].get("pack") == 3,
          "SPAWN84: a waves[] entry -> a waves row until its last burst: %s" % w1)
    w2 = [r for r in full["roster"] if r.get("t") == 300]
    check(len(w2) == 2 and [r.get("chance") for r in w2] == [2 / 3, 1 / 3] and w2[0].get("pace") == "once" and w2[1].get("stats") == {"hp": 30},
          "SPAWN84: a two-alternative wave -> two rows with their shares as chances: %s" % w2)
    check(len(res["conv"][0]["res"]["notes"]) >= 3, "SPAWN84: the converter says what a row cannot say exactly: %s" % res["conv"][0]["res"]["notes"])

    # ---- the estimate twins with every new key
    for (tl, crs, opts), js in zip(est_q, res["est"]):
        py = st.spawn_estimate(tl, crs, opts)
        bad = st.estimate_diff(js, py) + _new_fields_diff(js, py)
        check(not bad, "SPAWN84: the estimate twins agree with the pass 84 keys (%d rows): %s" % (len(tl.get("roster") or []), bad[:4]))
    e1 = res["est"][0]
    pts = e1["points"]
    by_t = {p["t"]: p for p in pts if not p["after"]}
    # the once row at 30 s: 30 specials of a and b (2:1, never c), on top of the cap
    p29, p31 = by_t.get(29), by_t.get(31)
    if p29 and p31:
        da = p31["by"]["a"][1] - p29["by"]["a"][1]
        db = p31["by"].get("b", [0, 0])[1] - p29["by"].get("b", [0, 0])[1]
        check(abs(da - 10) < 0.6 and abs(db - 20) < 0.6, "SPAWN84: a once special row of a list brings its count as specials by its shares: a %.2f b %.2f" % (da, db))
        check(p31["by"].get("c", [0, 0, 0])[0] < 1e-9, "SPAWN84: a list creature at weight 0 never comes")
    check(any(p.get("full", 0) > 0 for p in pts), "SPAWN84: the estimate marks seconds the cap was full")
    check(any(p.get("starve") for p in pts), "SPAWN84: the estimate names starving rows")
    check(all(isinstance(p.get("aliveBy"), dict) and sum(p["aliveBy"].values()) <= p["alive"] + 1e-6 for p in pts),
          "SPAWN84: every point carries aliveBy (never more than the crowd)")
    mods = [m for m in e1["marks"] if m["kind"] == "mod"]
    check(mods and min(m["t"] for m in mods) >= (e1["colourAt"] or 0), "SPAWN84: the elite rows wait for colour (first %s, colour at %s)" % (mods[0]["t"] if mods else None, e1["colourAt"]))
    ser = e1["series"]
    check(len(ser["t"]) == len(ser["alive"]) == len(ser["cap"]) == len(ser["full"]) and ser["t"] == sorted(set(ser["t"])),
          "SPAWN84: estimateSeries is one entry a whole second")
    s30 = ser["t"].index(30) if 30 in ser["t"] else -1
    check(s30 >= 0 and sum(ser["spawnedRow"].get("roster:2", [0])[s30:s30 + 2]) > 29.9, "SPAWN84: estimateSeries' spawnedRow shows the once row's 30 in its second")
    # the floor: a lone row under a flat cap of 25 with a floor of 60: the crowd fills to the cap at once and stays full
    e3 = res["est"][2]
    p1 = [p for p in e3["points"] if p["t"] == 1][0]
    check(p1["load"] > 24.9 and p1["floor"] == 60, "SPAWN84: the floor fills to the cap at once (load %.2f at 1 s)" % p1["load"])
    # the life option: a's crowd turns over faster than b's (4 s against 9 s)
    e2 = res["est"][1]
    check(e2["points"][-1]["kills"] > e1["points"][-1]["kills"] * 0.5, "SPAWN84: the life option keeps the crowd turning over")

    # ---- the converted timelines' estimates equal the old ones'
    for (tl, crs, opts, skn), pr in zip(pair_q, res["pair"]):
        bad = _old_shape_diff(pr["a"], pr["b"])
        check(not bad, "SPAWN84: the converted timeline's estimate = the old one's (%s): %s" % ("Red Canyon" if crs is creatures else "fixture", bad[:4]))

    # ---- the shown difficulty, by hand
    for (tl, c, row, t, opts), got in zip(diff_q, res["diff"]):
        want_lv = round(opts["level"]) if "level" in opts else round(st.sample_points(opts["levelCurve"], t))
        stats = row.get("stats", {})
        t0 = t if row.get("pace") == "once" else row["t"]
        hp_time = 1 if "hp" in stats else st.hp_time(tl, t0)
        stage = int(t // tl["stage_length"])
        sm = st.stage_mult(tl, stage, t)
        hp = (stats.get("hp", c.get("hp", 0))) * hp_time * stats.get("hp_mult", 1) * sm * (1 + tl.get("level_hp_per_level", 0) * (want_lv - 1)) * tl.get("creature_hp_mult", 1)
        check(got and got["level"] == want_lv and _close(got["hp"], hp, 1e-9), "SPAWN84: creatureDifficulty %s at %s = hp %s level %s (got %s)" % (row, t, hp, want_lv, got and [got["hp"], got["level"]]))
    check(res["level"][0] == 1 and res["level"][1] == 7 and res["level"][2] == 6, "SPAWN84: levelAt: the default curve, a number, a curve: %s" % res["level"])

    # ---- the API the Timeline lane builds on
    check(not res["api"], "SPAWN84: model.js exports the pass 84 API: missing %s" % res["api"])
    c = res["consts"]
    check(c["roster"] == "roster" and c["ring"] == 16 and c["paces"] == ["continuous", "waves", "once"] and "enemy_weights" in c["keys"]
          and c["roles"] == ["fodder", "swarm", "tank", "ranged", "elite", "special", ""] and len(c["lvl"]) >= 3, "SPAWN84: the constants: %s" % c)
    want_flags = [[True, "", True, False, False, 30], [False, "", False, False, False, 30], [False, "", False, False, False, 30],
                  [True, "random", False, True, True, 30], [True, "", False, False, True, 0], [True, "", False, False, False, 30],
                  [True, "", True, True, True, 20], [True, "", True, False, False, 30]]
    check(res["flags"] == want_flags, "SPAWN84: rowSingleEnemy / rowElite / rowInMix / rowTimer / rowPaced / rowWaveEvery: %s" % res["flags"])
    # the twins of the flags in the Python estimate copy
    check([[st.row_single_enemy_py(r), st.row_elite_py(r), st.row_in_mix_py(r), st.row_timer_py(r), st.row_paced_py(r), st.row_wave_every_py(r)] for r in flags_q] == want_flags,
          "SPAWN84: the Python copy's row flags = model.js's")
    _file_checks(check, server)


def _js_numbers(v):
    """A Python value as JSON.parse(JSON.stringify(...)) gives it back: whole floats as ints."""
    return json.loads(json.dumps(v), parse_float=lambda s: int(float(s)) if float(s).is_integer() else float(s))


def _new_fields_diff(js, py):
    out = []
    for pj, pp in zip(js["points"], py["points"]):
        for k in ("cap", "load", "floor", "full"):
            if not _close(pj.get(k, 0), pp.get(k, 0)):
                out.append("%s at %s: js %s py %s" % (k, pj["t"], pj.get(k), pp.get(k)))
        if not _same_dict(pj.get("aliveBy", {}), pp.get("aliveBy", {})):
            out.append("aliveBy at %s: js %s py %s" % (pj["t"], pj.get("aliveBy"), pp.get("aliveBy")))
        if not _same_dict(pj.get("starve", {}), pp.get("starve", {})):
            out.append("starve at %s: js %s py %s" % (pj["t"], pj.get("starve"), pp.get("starve")))
        if len(out) > 5:
            break
    return out


def _old_shape_diff(a, b):
    """The old estimate's fields of two estimates (the old timeline's and the converted one's); src keys differ by design
    (the converted rows are roster:<i> sources), so they are left out."""
    out = []
    if len(a["points"]) != len(b["points"]):
        return ["%d points against %d" % (len(a["points"]), len(b["points"]))]
    for pa, pb in zip(a["points"], b["points"]):
        for k in ("t", "after", "all", "reg", "col", "mod", "elite", "special", "boss", "minion", "kills", "alive"):
            if not (pa[k] == pb[k] if isinstance(pa[k], bool) else _close(pa[k], pb[k], 1e-9)):
                out.append("%s at %s: %s / %s" % (k, pa["t"], pa[k], pb[k]))
        if set(pa["by"]) != set(pb["by"]) or not all(all(_close(x, y) for x, y in zip(pa["by"][i], pb["by"][i])) for i in pa["by"]):
            out.append("by at %s" % pa["t"])
        if len(out) > 5:
            break
    ma = [(m["t"], m["kind"], m["id"], round(m["n"], 9)) for m in a["marks"]]
    mb = [(m["t"], m["kind"], m["id"], round(m["n"], 9)) for m in b["marks"]]
    if ma != mb:
        out.append("marks differ: %s / %s" % ([x for x in ma if x not in mb][:3], [x for x in mb if x not in ma][:3]))
    return out


def _old_red_canyon(server):
    """Red Canyon with its swarm / Elites-every events: the file itself before the migration, else the newest backup
    that still has them (tools/level_editor/backups/red_canyon-*.json)."""
    rc = server.load_json(server.map_path("red_canyon"))
    if MT.has_legacy(rc.get("timeline_data", {})):
        return rc
    bdir = os.path.join(HERE, "backups")
    if not os.path.isdir(bdir):
        return None
    for f in sorted((f for f in os.listdir(bdir) if f.startswith("red_canyon-") and f.endswith(".json")), reverse=True):
        try:
            with open(os.path.join(bdir, f), encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        if MT.has_legacy(d.get("timeline_data", {})):
            return d
    return None


def _file_checks(check, server):
    path = server.map_path("red_canyon")
    with open(path, "rb") as f:
        raw = f.read()
    d = json.loads(raw.decode("utf-8"))
    check(json.dumps(d, indent=2, ensure_ascii=False).encode("utf-8") + b"\n" == raw,
          "SPAWN84: red_canyon.json is in the Level Editor's own layout (json.dumps indent 2 + a newline round-trips it)")
    tl = d["timeline_data"]
    check(not MT.has_legacy(tl), "SPAWN84: Red Canyon spawns through rows only (no swarm / elite / elite_every event, no waves[])")
    once = [r for r in tl["roster"] if r.get("pace") == "once"]
    # pass 106 re-pin: Garry also makes unnamed once rows (r19, r30 on 2026-10-25): the named swarms are still there
    named = [r for r in once if r.get("name")]
    check(len(named) >= 5 and all(isinstance(r.get("weights"), list) for r in once), "SPAWN84: Red Canyon's swarms are named once rows with presence")
    ids = [r.get("id") for r in tl["roster"]]
    check(len(ids) == len(set(ids)), "SPAWN84: Red Canyon's row ids are unique")

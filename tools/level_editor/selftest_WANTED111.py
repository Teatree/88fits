"""Pass 111, lane WANTED: the Level Editor's Wanted tab (the Bounty Board's config, game/content/wanted/wanted.json).

  model    wanted_model.js under Node: the reward formula pinned to the same numbers the game's gdUnit suite pins
           (pass111_wanted_test.gd), the difficulty from where a number fell, the ranges grown with progression (a
           lower-is-harder number shrunk, a max kept), the draw by weight (a one-poster board's frequencies), the exact
           chances (the board's add up to the posters), three different types a board;
  context  contextFrom on the real Red Canyon, its creatures, items and heroes: only creatures on the stage's roster long
           enough, never a hidden one or a boss, nothing unmet when "met every creature" is off, never more Elites than
           the stage brings, the creature seconds the same as an independent Python count of the roster;
  routes   wanted_io on a temporary copy: a read of no file, a save in the file's layout (one task a line), the floats
           kept, a backup, a 409 on a stale page, a 400 on a broken config; the art route's folders and nothing else;
  wiring   server.py imports and routes it, index.html has the tab, its section, its css and scripts, app.js renders it
           and saves it on Ctrl+S; the game's WantedBoard.gd, wanted_model.js and wanted_io.py name the same types; the
           game's own config passes the checks.
selftest.py discovers this file and hands `checks` its counter.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const Model = require(process.argv[2]);
const WM = require(path.join(dir, 'wanted_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  const cfg = WM.normalized(q.cfg);
  out.rewards = [[1, 0, 0], [3, 0, 0], [2.5, 2, 1], [4.5, 3, 2], [1.3, 1, 0]].map(([d, p, s]) => WM.rewardFor(cfg, d, p, s));
  out.dif = [WM.difficultyOf(1, 3, 100, [100, 200], false), WM.difficultyOf(1, 3, 200, [100, 200], false), WM.difficultyOf(1, 3, 150, [100, 200], false),
    WM.difficultyOf(1, 3, 100, [100, 200], true), WM.difficultyOf(1, 3, 40, [100, 200], false), WM.difficultyOf(2, 4, 5, [5, 5], false)];
  out.skulls = [0.4, 2.6, 9].map(WM.skullsOf);
  const kt = WM.taskCfg(cfg, 'kill_total'), bf = WM.taskCfg(cfg, 'boss_fast'), hf = WM.taskCfg(cfg, 'hp_floor');
  out.kt = [WM.scaledRange(cfg, 'kill_total', kt, 0, 0), WM.scaledRange(cfg, 'kill_total', kt, 0, 3), WM.scaledRange(cfg, 'kill_total', kt, 2, 0)];
  out.bf = [WM.scaledRange(cfg, 'boss_fast', bf, 0, 0), WM.scaledRange(cfg, 'boss_fast', bf, 0, 3)];
  out.hf = WM.scaledRange(cfg, 'hp_floor', hf, 0, 30);
  out.hfMax = hf.max;
  // a one-poster board of three types weighing 1, 2 and 7 (and a fourth one switched off)
  const small = WM.normalized({ choices: 1, tasks: [
    { type: 'kill_total', weight: 1, difficulty: [1, 2], n: [[100, 200]], step: 10, text: 'a' },
    { type: 'open_chests', weight: 2, difficulty: [1, 2], n: [[4, 8]], step: 1, text: 'b' },
    { type: 'collect_coins', weight: 7, difficulty: [1, 2], n: [[100, 300]], step: 25, text: 'c' },
    { type: 'hero_level', on: false, weight: 50, difficulty: [1, 2], n: [[10, 20]], step: 1, text: 'd' }] });
  const plain = { map: 'red_canyon', stage: 0, stage_name: 'Sundown', P: 0, hero: { id: 'drifter', name: 'The Drifter', start: 'revolver' }, boss: {}, creatures: [], gear: [], elite_boss: [], elite_estimate: 0, weapons: [], cards: [] };
  const rnd = WM.mulberry32(111);
  const count = { kill_total: 0, open_chests: 0, collect_coins: 0, hero_level: 0 };
  const N = 6000;
  for (let i = 0; i < N; i++) { const b = WM.roll(small, plain, rnd); count[b[0].type]++; }
  out.freq = Object.fromEntries(Object.entries(count).map(([k, v]) => [k, v / N]));
  out.smallChances = WM.typeChances(small, plain);
  // the real map
  const tl = q.map.timeline_data;
  const stages = Model.stageList(tl);
  out.stages = stages.map((s) => [s.name, s.start, s.end, s.boss]);
  const hero = q.heroes.find((h) => h.id === 'drifter');
  out.ctx = [];
  out.boards = [];
  for (let k = 0; k < stages.length; k++) {
    for (const metAll of [true, false]) {
      const ctx = WM.contextFrom({ tl, map: 'red_canyon', stage: k, stages, creatures: q.enemies, weapons: q.items.weapons, lines: q.items.lines, hero, P: 0, beaten: false, metAll, seenAll: metAll, unlocksDone: metAll });
      out.ctx.push({ k, metAll, creatures: ctx.creatures, elite_estimate: ctx.elite_estimate, weapons: ctx.weapons.map((w) => w.id), start: ctx.hero.start, boss: ctx.boss, cards: ctx.cards.map((c) => c.id) });
      const r2 = WM.mulberry32(1000 + k);
      const ch = WM.typeChances(WM.normalized(q.real), ctx);
      const posters = [];
      const types = {};
      for (let i = 0; i < 300; i++) {
        const b = WM.roll(WM.normalized(q.real), ctx, r2);
        posters.push(b.length);
        for (const c of b) {
          types[c.type] = (types[c.type] || 0) + 1;
          out.boards.push({ k, metAll, type: c.type, target: c.target, kind: c.target_kind, n: c.n, d: c.d, reward: c.reward, still: c.still, name: c.name, text: c.text, skulls: c.skulls });
        }
      }
      out.ctx[out.ctx.length - 1].sizes = posters;
      out.ctx[out.ctx.length - 1].types = types;
      out.ctx[out.ctx.length - 1].boardSum = Object.values(ch).reduce((a, x) => a + x.board, 0);
      out.ctx[out.ctx.length - 1].eligible = WM.eligibleTypes(WM.normalized(q.real), ctx).length;
    }
  }
  out.issuesReal = WM.issues(WM.normalized(q.real));
  out.issuesBad = WM.issues(WM.normalized({ tasks: [{ type: 'nope', weight: 1 }, { type: 'kill_total', weight: 1, difficulty: [1] }] }));
  out.order = WM.TYPE_ORDER;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    with open(os.path.join(*parts), "r", encoding="utf-8") as f:
        return f.read()


def _union(spans):
    total, a0, b0 = 0.0, None, None
    for a, b in sorted(spans):
        if b0 is None or a > b0:
            if b0 is not None:
                total += b0 - a0
            a0, b0 = a, b
        else:
            b0 = max(b0, b)
    if b0 is not None:
        total += b0 - a0
    return total


def model_checks(check, run_node, server):
    cfg = json.loads(_read(GAME, "content", "wanted", "wanted.json"))
    with open(os.path.join(GAME, "content", "maps", "red_canyon", "red_canyon.json"), "r", encoding="utf-8") as f:
        mp = json.load(f)
    q = {"cfg": cfg, "real": cfg, "map": mp, "enemies": server.list_creatures(), "items": server.list_items(), "heroes": server.list_heroes()}
    r = run_node(q, RUNNER) or {}
    if not r:
        check(False, "WANTED111 wanted_model.js ran under Node")
        return
    check(r["rewards"] == [100, 220, 475, 1165, 175], "WANTED111 the reward formula, pinned as the game's suite pins it: %s" % r["rewards"])
    check(r["dif"] == [1, 3, 2, 3, 1, 3], "WANTED111 the difficulty from where the number fell: %s" % r["dif"])
    check(r["skulls"] == [1, 3, 5], "WANTED111 skulls 1 to 5: %s" % r["skulls"])
    kt = r["kt"]
    check(kt[1][0] > kt[0][0] and kt[1][1] > kt[0][1] and kt[2][1] > kt[0][1], "WANTED111 ranges grow with progression and stage: %s" % kt)
    check(r["bf"][1][0] < r["bf"][0][0], "WANTED111 a lower-is-harder number shrinks with progression: %s" % r["bf"])
    check(r["hf"][1] <= r["hfMax"], "WANTED111 the health floor never passes its max: %s" % r["hf"])
    fr = r["freq"]
    check(fr["hero_level"] == 0, "WANTED111 a type switched off never comes")
    check(abs(fr["kill_total"] - 0.1) < 0.02 and abs(fr["open_chests"] - 0.2) < 0.025 and abs(fr["collect_coins"] - 0.7) < 0.025,
          "WANTED111 one poster: the types come by their weights (1 : 2 : 7): %s" % fr)
    sc = r["smallChances"]
    check(abs(sc["collect_coins"]["first"] - 0.7) < 1e-9 and abs(sc["kill_total"]["board"] - 0.1) < 1e-9 and "hero_level" not in sc,
          "WANTED111 the chances table: the share of the weight; one poster's board chance is the same: %s" % sc)
    check(not r["issuesReal"]["errors"], "WANTED111 the game's wanted.json has no errors: %s" % r["issuesReal"]["errors"])
    check(len(r["issuesBad"]["errors"]) >= 2, "WANTED111 issues() names an unknown type and a broken difficulty: %s" % r["issuesBad"]["errors"])
    # the real map's contexts
    tl = mp["timeline_data"]
    recs = {c["id"]: c for c in q["enemies"]}
    min_s = next(t for t in cfg["tasks"] if t["type"] == "kill_enemy")["min_seconds"]
    cap = next(t for t in cfg["tasks"] if t["type"] == "kill_enemy")["per_minute_cap"]
    for c in r["ctx"]:
        k = c["k"]
        s0, s1 = r["stages"][k][1], r["stages"][k][2]
        spans = {}
        for row in tl.get("roster", []):
            if not isinstance(row, dict) or isinstance(row.get("enemy"), list) or str(row.get("enemy", "")) == "roster":
                continue
            if row.get("elite") not in (None, "", False, True) or row.get("special") or str(row.get("pace", "")) == "once":
                continue
            a = max(float(row.get("t", 0)), s0)
            b = min(float(row["until"]) if row.get("until") is not None else 1e18, s1)
            if b > a:
                spans.setdefault(row["enemy"], []).append((a, b))
        py = {}
        for cid, sp in spans.items():
            d = recs.get(cid)
            if d and not d["hidden"] and not d["retired"] and d["archetype"] != "boss" and d["kind"] != "boss" and not cid.startswith("training_dummy"):
                py[cid] = _union(sp)
        js = {x["id"]: x["seconds"] for x in c["creatures"]}
        check(set(js) == set(py) and all(abs(js[i] - py[i]) < 1e-6 for i in js),
              "WANTED111 stage %d: the creatures' seconds on the roster match an independent count: js %s py %s" % (k + 1, js, py))
        check(all(n == 3 for n in c["sizes"]) or c["eligible"] < 3, "WANTED111 stage %d (met %s): every board has three posters" % (k + 1, c["metAll"]))
        if c["eligible"] >= 3:
            check(abs(c["boardSum"] - 3.0) < 1e-6, "WANTED111 stage %d: the board chances add up to the three posters: %s" % (k + 1, c["boardSum"]))
        check(c["start"] == "revolver", "WANTED111 the Drifter's own gun is the Revolver: %s" % c["start"])
        if not c["metAll"]:
            for t in ("kill_enemy", "boss_fast", "hp_floor"):
                check(t not in c["types"], "WANTED111 stage %d, nothing met: no %s poster" % (k + 1, t))
            check(c["weapons"] == ["revolver"] or set(c["weapons"]) >= {"revolver"}, "WANTED111 nothing seen: his own gun is still a target")
    bad = {"creature": [], "roster": [], "cap": [], "elites": [], "reward": [], "words": []}
    for b in r["boards"]:
        k = b["k"]
        if b["kind"] == "enemy":
            d = recs.get(b["target"])
            if d is None or d["hidden"] or d["retired"] or d["archetype"] == "boss":
                bad["creature"].append(b["target"])
            secs = next((cr["seconds"] for cx in r["ctx"] if cx["k"] == k and cx["metAll"] == b["metAll"]
                         for cr in cx["creatures"] if cr["id"] == b["target"]), None)
            if secs is None or secs < min_s:
                bad["roster"].append((b["target"], secs))
            elif b["type"] == "kill_enemy" and b["n"] > max(cap * secs / 60.0, 5):
                bad["cap"].append((b["target"], b["n"], secs))
        if b["type"] == "kill_elites":
            est = next(cx["elite_estimate"] for cx in r["ctx"] if cx["k"] == k and cx["metAll"] == b["metAll"])
            if b["n"] > max(est, 1):
                bad["elites"].append((b["n"], est))
        if b["reward"] % 5 != 0 or b["reward"] <= 0 or not 1 <= b["skulls"] <= 5:
            bad["reward"].append(b)
        if b["name"] == "" or b["text"] == "" or "{" in b["name"] + b["text"]:
            bad["words"].append((b["name"], b["text"]))
    n = len(r["boards"])
    check(not bad["creature"], "WANTED111 %d posters: every creature target is a real, shown creature: %s" % (n, bad["creature"][:5]))
    check(not bad["roster"], "WANTED111 every creature target is on the stage's roster long enough: %s" % bad["roster"][:5])
    check(not bad["cap"], "WANTED111 never more kills than the cap a minute allows: %s" % bad["cap"][:5])
    check(not bad["elites"], "WANTED111 never more Elites than the stage brings: %s" % bad["elites"][:5])
    check(not bad["reward"], "WANTED111 every poster's reward is a multiple of 5 and its skulls 1 to 5: %s" % bad["reward"][:3])
    check(not bad["words"], "WANTED111 every poster's words are filled: %s" % bad["words"][:5])
    types_seen = {b["type"] for b in r["boards"] if b["metAll"]}
    check(types_seen == set(r["order"]), "WANTED111 met everything: every type turns up on some board: missing %s" % (set(r["order"]) - types_seen))
    return r


def route_checks(check, server):
    import wanted_io as WIO
    tmp = tempfile.mkdtemp(prefix="le_wanted_")
    saved = (server.CONTENT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.BACKUPS = os.path.join(tmp, "backups")
        os.makedirs(server.CONTENT)
        res = WIO.read(server)
        check(res["ok"] and res["exists"] is False and res["json"] is None, "WANTED111 routes: no file reads as none: %s" % res)
        cfg = json.loads(_read(GAME, "content", "wanted", "wanted.json"))
        res = WIO.save(server, cfg)
        check(res.get("ok") and res.get("backup") is None, "WANTED111 routes: the first save writes (no backup of nothing): %s" % res)
        path = os.path.join(server.CONTENT, "wanted", "wanted.json")
        text = open(path, encoding="utf-8").read()
        check(json.loads(text) == cfg, "WANTED111 routes: what was saved reads back the same")
        lines = text.splitlines()
        check(lines[0] == "{" and lines[-1] == "}" and sum(1 for ln in lines if ln.startswith('    {"type": ')) == len(cfg["tasks"]),
              "WANTED111 routes: the file's layout: one top key a line, one task a line")
        # the page sends whole numbers for floats: they stay floats in the file
        page = json.loads(json.dumps(cfg))
        page["tasks"][0]["weight"] = 15
        page["tasks"][0]["difficulty"] = [1, 3]
        mt = WIO.read(server)["mtime"]
        res = WIO.save(server, page, mt)
        back = json.loads(open(path, encoding="utf-8").read())
        check(res.get("ok") and res.get("backup"), "WANTED111 routes: a second save leaves a backup: %s" % res)
        check(back["tasks"][0]["weight"] == 15 and back["tasks"][0]["difficulty"] == [1.0, 3.0] and isinstance(back["tasks"][0]["difficulty"][0], float),
              "WANTED111 routes: the change is written and the file's floats are kept: %s" % back["tasks"][0])
        res = WIO.save(server, page, 12345.0)
        check(not res.get("ok") and res.get("status") == 409, "WANTED111 routes: a stale page is refused (409): %s" % res)
        res = WIO.save(server, dict(page), WIO.read(server)["mtime"])
        check(res.get("ok") and res.get("unchanged"), "WANTED111 routes: nothing changed writes nothing: %s" % res)
        for bad, why in ((["x"], "not an object"), ({"tasks": "x"}, "tasks not a list"), ({"tasks": [{"type": "nope", "difficulty": [1, 2]}]}, "unknown type"),
                         ({"tasks": [{"type": "kill_total", "difficulty": [1]}]}, "broken difficulty"),
                         ({"tasks": [{"type": "kill_total", "difficulty": [1, 2]}, {"type": "kill_total", "difficulty": [1, 2]}]}, "a type twice"),
                         ({"enabled": "yes", "tasks": []}, "enabled not a bool")):
            res = WIO.save(server, bad)
            check(not res.get("ok") and res.get("status") == 400, "WANTED111 routes: a broken config is refused (%s): %s" % (why, res))
        # the art route: the four folders, plain names, nothing else
        check(WIO.art_path(server, "stages", "red_canyon_s1.jpg") is not None, "WANTED111 routes: a stage picture is served")
        check(WIO.art_path(server, "badges", "skull.png") is not None and WIO.art_path(server, "wanted", "coin.png") is not None,
              "WANTED111 routes: the badges and the coin are served")
        check(WIO.art_path(server, "fonts", "AlfaSlabOne-Regular.ttf") is not None, "WANTED111 routes: the slab face is served")
        for f, n in (("stages", "../x.jpg"), ("..", "skull.png"), ("content", "a.png"), ("badges", "skull.svg"), ("badges", "nope.png")):
            check(WIO.art_path(server, f, n) is None, "WANTED111 routes: refused %s/%s" % (f, n))
    finally:
        server.CONTENT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def wiring_checks(check, order):
    srv = _read(HERE, "server.py")
    check("import wanted_io as WIO" in srv and 'if parts[:1] == ["wanted"]:' in srv and 'if parts[:2] == ["api", "wanted"]:' in srv,
          "WANTED111 wiring: server.py imports wanted_io and routes /api/wanted (GET and POST)")
    html = _read(HERE, "index.html")
    check('data-tab="wanted"' in html and 'id="tab-wanted"' in html and 'href="wanted.css"' in html
          and '<script src="wanted_model.js"></script>' in html and '<script src="wanted.js"></script>' in html,
          "WANTED111 wiring: index.html has the tab, its section, its css and its scripts")
    app = _read(HERE, "app.js")
    check("S.tab === 'wanted' && typeof Wanted !== 'undefined') Wanted.render(panel)" in app and "await Wanted.save(); return;" in app,
          "WANTED111 wiring: app.js renders the tab and saves it on Ctrl+S")
    gd = _read(GAME, "core", "systems", "WantedBoard.gd")
    m = re.search(r"const TYPE_ORDER := \[(.*?)\]", gd, re.S)
    gd_order = re.findall(r'"([a-z_]+)"', m.group(1)) if m else []
    import wanted_io as WIO
    check(gd_order == order == WIO.TYPES, "WANTED111 wiring: the game, the page and the server name the same types: %s / %s / %s" % (gd_order, order, WIO.TYPES))
    cfg = json.loads(_read(GAME, "content", "wanted", "wanted.json"))
    check(WIO.check(cfg) == "", "WANTED111 wiring: the game's wanted.json passes the server's check: %s" % WIO.check(cfg))
    check([t["type"] for t in cfg["tasks"]] == gd_order and cfg["choices"] == 3 and cfg["unlock"]["runs"] >= 1,
          "WANTED111 wiring: wanted.json lists every type in order, three posters, and no board for a first-time player")
    t = _read(GAME, "tests", "pass111_wanted_test.gd")
    check("is_equal(1165)" in t and "is_equal(475)" in t, "WANTED111 wiring: the game's suite pins the same rewards")


def checks(check, run_node, server):
    r = model_checks(check, run_node, server) or {}
    route_checks(check, server)
    wiring_checks(check, r.get("order", []))

"""Pass 69, lane LE: the Level Editor for what pass 69 added, checked. selftest.py discovers this file (`extra_checks`) and
hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes under game/
(the server's operations run on a temp tree, selftest_S's Pointed).

Groups:
  vocab   the behaviours SaltShaker and Frisbee, their params keys, the ten new player stats and their help lines, the
          perk specials (vocab.py and assets_fields.js agree; every perk in the content names a special the table knows);
  typed   AFIELDS.PARAM_GROUPS against the game's sources (every key a behaviour reads, every default the code's own) and
          the content (every key of the pass's params under a typed group has a row), paramGroupsFor / paramInherited;
  model   the "word" stat kind (TextGen.describe_effect / _sum_effects), questText against the heroes' unlock quests;
  rules   the perk and hero rules on the content (zero errors), the by-id special warning, the availability `after` sync;
  server  a hero's requirement written, edited and removed (unlock_<hero>, unlocks {type character}); a purchase hero never
          hidden; a perk read, saved, created from a template for a hero and deleted; /api/heroes' quest and perk records;
          /api/items' weapon params.
Also the helpers selftest_P / selftest_S use for their shape rules: pass44_band(), content_band(), content_passives().
"""
import json
import os
import re
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")


# ---------------------------------------------------------------- shape helpers (selftest_P, selftest_S)

def pass44_band():
    """The bounds pass44_test.gd asserts on the quest-locked share of the base items (pass 69: 0.28-0.56)."""
    with open(os.path.join(GAME, "tests", "pass44_test.gd"), "r", encoding="utf-8") as f:
        src = f.read()
    m = re.search(r"assert_float\(share\)\.is_between\(([0-9.]+),\s*([0-9.]+)\)", src)
    return (float(m.group(1)), float(m.group(2))) if m else (0.33, 0.56)


def _load(type_folder):
    out = []
    base = os.path.join(CONTENT, type_folder)
    for d in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        p = os.path.join(base, d, d + ".json")
        if os.path.isfile(p):
            with open(p, "r", encoding="utf-8") as f:
                j = json.load(f)
            j.setdefault("id", d)
            out.append(j)
    return out


def content_band():
    """The quest-locked band as pass44_test counts it, from the content folder: non-hidden base weapons and base passives
    (no evolves_from, not hidden), locked = those a quest unlocks."""
    quests = {(str((q.get("unlocks") or {}).get("type")), str((q.get("unlocks") or {}).get("id"))) for q in _load("quests")}
    base = [("weapon", w["id"]) for w in _load("weapons") if not w.get("hidden")]
    base += [("passive", p["id"]) for p in _load("passives") if not p.get("hidden") and not p.get("evolves_from")]
    locked = sum(1 for b in base if b in quests)
    return {"locked": locked, "base": len(base)}


def content_passives():
    """{lines, items, quests}: the base lines, the passive items (not lines, not evolved forms) and every quest."""
    ps = _load("passives")
    lines = [p for p in ps if p.get("line") and not p.get("evolves_from")]
    items = [p for p in ps if not p.get("line")]
    return {"lines": len(lines), "items": len(items), "quests": len(_load("quests"))}


# ---------------------------------------------------------------- Node: the page's tables and maths

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = M;
const F = require(path.join(dir, 'assets_fields.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.groups = F.PARAM_GROUPS.map((g) => ({ id: g.id, behaviors: g.behaviors, show: g.show, present: g.present || null, src: g.src || '', help: g.help || '',
    rows: g.rows.map((r) => ({ key: r.key, type: r.type, def: r.def === undefined ? '__undef__' : r.def, help: r.help || '', label: r.label || '', options: (r.options || []).map((o) => o.v) })) }));
  out.paramsKeys = F.PARAMS_KEYS;
  out.behaviors = F.VOCAB.behaviors.map((o) => o.v);
  out.specials = Object.keys(F.PERK_SPECIALS).map((k) => ({ k, by: F.PERK_SPECIALS[k].by, params: F.PERK_SPECIALS[k].params }));
  out.groupsFor = q.groupsFor.map(([beh, own, fam, opened]) => F.paramGroupsFor(beh, own, fam, opened).map((x) => `${x.group.id}:${x.on ? 'on' : 'off'}${x.set ? ':set' : ''}`));
  out.inherited = q.inherited.map(([gid, key, inherit]) => { const g = F.PARAM_GROUPS.find((x) => x.id === gid); const r = g.rows.find((x) => x.key === key); return F.paramInherited(r, inherit); });
  out.words = q.words.map((e) => M.describeEffect(e));
  out.wordsAll = M.describeEffects(q.words);
  out.summary = M.levelsSummary({}, q.levels).map((r) => r.stat);
  out.help = q.stats.map((s) => M.statHelp(s));
  out.kinds = q.stats.map((s) => [M.statName(s), M.statKind(s)]);
  out.questText = q.quests.map((x) => M.questText(x));
  out.band = M.BAND;
  // the rules on the content's heroes and perks (the page's flat lists)
  const lists = { heroes: q.heroes, items: { weapons: q.weapons, evolutions: [], mutations: q.mutations, passives: q.passives, quests: q.questsAll }, enemies: [] };
  out.perkIssues = q.perks.map((d) => { const i = M.issues('perk', d, { rules: F.RULES, id: d.id, kind: 'perk', lists }); return { id: d.id, errors: i.errors, warnings: i.warnings }; });
  out.heroIssues = q.heroes.map((d) => { const i = M.issues('hero', d, { rules: F.RULES, id: d.id, kind: 'hero', lists, record: d.__record }); return { id: d.id, errors: i.errors, warnings: i.warnings }; });
  out.copyIssues = q.copies.map(([d, id]) => { const i = M.issues('perk', d, { rules: F.RULES, id, kind: 'perk', lists }); return { id, warnings: i.warnings.map((w) => w.msg) }; });
  // the hero availability rows' sync
  const av = F.hero.find((r) => r.key === 'availability'), hid = F.hero.find((r) => r.key === 'hidden');
  out.sync = q.sync.map(([d, which, v]) => { const x = JSON.parse(JSON.stringify(d)); (which === 'availability' ? av : hid).after(x, v); return x; });
  out.perkTable = { rows: F.perk.map((r) => [r.key, r.section, r.type]), sections: F.SECTIONS.perk };
  out.typedRows = ['weapon', 'mutation'].map((k) => F[k].filter((r) => r.type === 'params_fields').map((r) => r.section));
  out.specialOptions = F.perkSpecialOptions(null).map((o) => o.v);
  // util.js's path helpers step into lists by index (a weapon's or passive's level steps: "levels.2")
  const U = new Function(fs.readFileSync(path.join(dir, 'util.js'), 'utf8') + '\nreturn U;')();
  const doc = { levels: [[], [{ stat: 'a' }], []], params: { salt: { radius: 1.4 } } };
  out.paths = {
    get: [U.getPath(doc, 'levels.1'), U.getPath(doc, 'levels.1.0.stat'), U.getPath(doc, 'levels.9'), U.getPath(doc, 'params.salt.radius'), U.getPath(doc, 'params.x.y')],
  };
  U.setPath(doc, 'levels.2', [{ stat: 'b' }]);
  U.setPath(doc, 'levels.1', []);
  U.setPath(doc, 'levels.0', null);
  U.setPath(doc, 'params.salt.radius', null);
  U.setPath(doc, 'params.final.salt.color', '#000000');
  out.paths.after = doc;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read_src(*rels):
    out = []
    for r in rels:
        try:
            with open(os.path.join(GAME, r), "r", encoding="utf-8") as f:
                out.append(f.read())
        except OSError:
            out.append("")
    return "\n".join(out)


# the files that read each behaviour's typed keys (a leaf name must appear quoted in them)
SOURCES = {
    "SaltShaker": ("core/behaviors/SaltShaker.gd", "core/systems/SaltPatches.gd", "game/Game.gd", "core/systems/TextGen.gd",
                   "core/systems/WeaponInstance.gd", "player/Player.gd"),
    "Frisbee": ("core/behaviors/Frisbee.gd", "core/autoload/Run.gd", "core/systems/TextGen.gd", "core/systems/WeaponInstance.gd",
                "core/systems/EnemyManager.gd"),
    "ProjectileEmitter": ("core/behaviors/ProjectileEmitter.gd", "core/systems/ProjectileManager.gd", "core/systems/EnemyManager.gd",
                          "core/systems/TextGen.gd"),
}


def _leaf_default(src, leaf):
    """Every default the code reads `leaf` with: .get("leaf", <number>) or ("leaf", <number>) helpers."""
    vals = re.findall(r'\.get\("%s",\s*(-?[0-9.]+)\)' % re.escape(leaf), src)
    vals += re.findall(r'_f\(\w+,\s*"%s",\s*(-?[0-9.]+)\)' % re.escape(leaf), src)
    return [float(v) for v in vals]


def vocab_checks(check):
    import vocab
    check({"SaltShaker", "Frisbee"} <= set(vocab.BEHAVIOURS) and vocab.PARAMS_KEYS.get("SaltShaker") == ["salt", "shaker"]
          and {"bend_deg", "disc", "carry", "loop", "proc_mult", "falloff"} <= set(vocab.PARAMS_KEYS.get("Frisbee", []))
          and {"launch", "heat_look", "fire_without_target", "stream"} <= set(vocab.PARAMS_KEYS["ProjectileEmitter"]),
          "L69 vocab.py knows the Salt's and the Frisbee's behaviours and the pass's params keys")
    new = ["counter_damage", "counter_haste", "counter_speed", "counter_seconds", "heavyweight", "overheal", "heal_pulse", "last_stand",
           "xp_pull_radius", "xp_pull_rate"]
    check(all(s in vocab.PLAYER_DEFAULTS and s in vocab.STAT_NAMES and vocab.STAT_HELP.get(s) for s in new) and vocab.STAT_NAMES["xp_pull_rate"][1] == "word",
          "L69 the ten new player stats: defaults, TextGen names (xp_pull_rate a word) and a help line each")
    probs = [p for p in vocab.check_against_source(GAME) if "perk special" in p or "STAT_HELP" in p]
    check(not probs, "L69 every perk special and its numbers' defaults are the game's (Run.perk_param, Decoy.param): %s" % probs)
    used = {}
    for p in _load("perks"):
        used.setdefault(str(p.get("special", "")), []).append(p["id"])
    src = _read_src("game/Game.gd", "core/autoload/Run.gd", "player/Player.gd", "core/systems/EnemyManager.gd", "core/systems/Decoy.gd")
    unknown = {s: ids for s, ids in used.items() if s not in vocab.PERK_SPECIALS and ('"%s"' % s) in src}
    check(not unknown, "L69 every special the content's perks use and the game reads is in the table: %s" % unknown)
    check(vocab.PERK_SPECIALS["decoy"]["by"] == "special" and vocab.PERK_SPECIALS["periodic_buff"]["by"] == "special"
          and vocab.PERK_SPECIALS["high_noon"]["by"] == "id", "L69 decoy and periodic_buff work on any perk; high_noon only on its own")
    t = vocab.table(CONTENT, GAME)
    check(t["perk_specials"] is vocab.PERK_SPECIALS and t["stat_help"] is vocab.STAT_HELP, "L69 /api/vocab serves perk_specials and stat_help")


def node_checks(check, run_node):
    import vocab
    heroes = _load("characters")
    perks = _load("perks")
    mutations = _load("mutations")
    for m in mutations:
        m.setdefault("kind", "motion")
    weapons = _load("weapons")
    quests = _load("quests")
    # a hero's record as /api/heroes builds it (perks and hero mutations by hero id)
    for h in heroes:
        h["__record"] = {"perks": [p["id"] for p in perks if p.get("hero") == h["id"]],
                         "hero_mutations": [m["id"] for m in mutations if m.get("hero") == h["id"]]}
    salt = next(w for w in weapons if w["id"] == "salt")
    ball = next(w for w in weapons if w["id"] == "basketball")
    q = {
        "groupsFor": [["SaltShaker", salt.get("params", {}), {}, {}], ["Frisbee", {}, {}, {}], ["ProjectileEmitter", {}, ball.get("params", {}), {}],
                      ["ProjectileEmitter", {}, {}, {}], ["ProjectileEmitter", {"fire_without_target": True}, {}, {}], ["ProjectileEmitter", {}, {}, {"nonstop": True}],
                      ["Orbiter", {}, {}, {}]],
        "inherited": [["salt", "salt.radius", [[salt.get("params", {}), "the Salt's params"]]], ["salt", "salt.luck_mult", [[salt.get("params", {}), "the Salt's params"]]],
                      ["launch", "launch.chance", []], ["disc", "disc.look", []]],
        "words": [{"stat": "xp_pull_rate", "op": "add", "value": 0.25, "target": "player"}, {"stat": "xp_pull_rate", "op": "add", "value": 0, "target": "player"},
                  {"stat": "xp_pull_radius", "op": "add", "value": 5, "target": "player"}, {"stat": "overheal", "op": "add", "value": 0.2, "target": "player"}],
        "levels": [[], [{"stat": "xp_pull_rate", "op": "add", "value": 0.25}, {"stat": "xp_pull_radius", "op": "add", "value": 1}]],
        "stats": ["counter_damage", "heavyweight", "overheal", "heal_pulse", "last_stand", "xp_pull_radius", "xp_pull_rate"],
        "quests": [x for x in quests if (x.get("unlocks") or {}).get("type") == "character"],
        "heroes": heroes, "perks": perks, "weapons": weapons, "mutations": mutations, "questsAll": quests, "passives": _load("passives"),
        "copies": [[dict(next(p for p in perks if p["id"] == "inflatable_may"), id="lucky_doll"), "lucky_doll"],
                   [dict(next(p for p in perks if p["id"] == "high_noon"), id="noon_two"), "noon_two"]],
        "sync": [[{"hidden": False, "availability": "purchase"}, "availability", "hidden"], [{"hidden": True, "availability": "hidden"}, "availability", "purchase"],
                 [{"availability": "available"}, "availability", "purchase"], [{"hidden": False, "availability": "available"}, "hidden", True],
                 [{"hidden": True, "availability": "hidden"}, "hidden", False]],
    }
    res = run_node(q, RUNNER)
    if not res:
        check(False, "L69 the Node checks ran (is node on the PATH?)")
        return
    # ---- vocab: the page's tables and the server's agree
    check({"SaltShaker", "Frisbee"} <= set(res["behaviors"]) and res["paramsKeys"].get("SaltShaker") == ["salt", "shaker"]
          and set(res["paramsKeys"].get("Frisbee", [])) == set(vocab.PARAMS_KEYS["Frisbee"]),
          "L69 assets_fields.js lists the two behaviours and the Frisbee's keys as vocab.py does")
    js_sp = {x["k"]: x for x in res["specials"]}
    py_sp = vocab.PERK_SPECIALS
    diff = [k for k in set(js_sp) | set(py_sp) if k not in js_sp or k not in py_sp or js_sp[k]["by"] != py_sp[k]["by"]
            or {a: (None if b is None else float(b)) for a, b in js_sp[k]["params"].items()} != {a: (None if b is None else float(b)) for a, b in py_sp[k]["params"].items()}]
    check(not diff, "L69 the page's perk specials are vocab.py's (by, params, defaults): %s" % diff)
    check(set(res["specialOptions"]) == set(py_sp), "L69 the perk form's special select lists every special")
    # ---- typed params against the game's sources and the content
    groups = res["groups"]
    check(len(groups) >= 11 and {"salt", "shaker", "frisbee_flight", "disc", "carry", "trick", "loop", "launch", "heat_look", "ball_tint", "nonstop"} <= {g["id"] for g in groups},
          "L69 the typed groups: salt, shaker, the Frisbee's five, the ball's three and Trigger Happy's: %s" % [g["id"] for g in groups])
    bad_top, bad_leaf, bad_def, no_help = [], [], [], []
    for g in groups:
        for beh in g["behaviors"]:
            src = _read_src(*SOURCES.get(beh, ()))
            for r in g["rows"]:
                top = r["key"].split(".")[0]
                if top not in res["paramsKeys"].get(beh, []) and top not in vocab.PARAMS_KEYS.get(beh, []):
                    bad_top.append("%s %s" % (beh, r["key"]))
                leaf = r["key"].split(".")[-1]
                if '"%s"' % leaf not in src:
                    bad_leaf.append("%s %s" % (beh, r["key"]))
                if isinstance(r["def"], (int, float)) and not isinstance(r["def"], bool):
                    found = _leaf_default(src, leaf)
                    if found and float(r["def"]) not in found:
                        bad_def.append("%s %s: page %s, code %s" % (beh, r["key"], r["def"], found))
                if not r["help"] or not r["label"]:
                    no_help.append(r["key"])
    check(not bad_top, "L69 every typed row sits under a params key its behaviour reads (PARAMS_KEYS): %s" % bad_top)
    check(not bad_leaf, "L69 every typed row's key is read by the game (quoted in the behaviour's sources): %s" % bad_leaf)
    check(not bad_def, "L69 every typed row's default is the code's own: %s" % bad_def)
    check(not no_help and all(g["help"] and g["src"] for g in groups), "L69 every typed row and group is explained: %s" % no_help)
    # every key of the pass's content params under a typed namespace has a row (the forms never hide one in the JSON)
    rows = {r["key"] for g in groups for r in g["rows"]}
    typed_tops = {"salt", "shaker", "disc", "carry", "loop", "falloff", "launch", "heat_look", "stun"}
    flat_tops = {r["key"] for g in groups for r in g["rows"] if "." not in r["key"]}

    def leaves(obj, pre=""):
        for k, v in obj.items():
            if k == "final" and isinstance(v, dict):
                yield from leaves(v, pre)
            elif isinstance(v, dict) and not (pre + k).startswith(("salt.crystals", "salt.crunch")):
                yield from leaves(v, pre + k + ".")
            elif isinstance(v, dict):
                for k2 in v:
                    yield pre + k + "." + k2
            else:
                yield pre + k
    want_ids = {"salt", "frisbee", "sea_salt", "salt_spill", "thing_about_luck", "salt_flats", "carry", "poison_razors", "frisbee_trick_shot",
                "alley_oop", "trigger_happy", "hiwa_kai", "flying_saucer", "slam_dunk", "basketball"}
    docs = [d for d in _load("weapons") + _load("mutations") + _load("evolutions") if d["id"] in want_ids]
    check(len(docs) == len(want_ids), "L69 the pass's weapons, mutations and evolutions are in the content: %s" % sorted(want_ids - {d["id"] for d in docs}))
    missing = []
    for d in docs:
        for leaf in leaves(d.get("params") or {}):
            top = leaf.split(".")[0]
            if leaf in rows:
                continue
            if top in typed_tops or (top in flat_tops and "." not in leaf) or (top == "tint" and leaf.startswith(("tint.body", "tint.seams", "tint.vertex"))):
                missing.append("%s %s" % (d["id"], leaf))
    check(not missing, "L69 every key the pass's content sets under a typed group has a typed row: %s" % missing)
    gf = res["groupsFor"]
    check(gf[0] == ["salt:on:set", "shaker:on:set"] and gf[1] == ["frisbee_flight:on", "disc:on", "carry:on", "trick:on", "loop:on"], "L69 the Salt shows its two groups, the Frisbee its five: %s / %s" % (gf[0], gf[1]))
    check("launch:on" in gf[2] and "heat_look:on:set" in gf[2] and "nonstop:off" in gf[2], "L69 a ball's mutation shows the launch, the Heat look and the colour, not the nonstop fire: %s" % gf[2])
    check(all(x.endswith(":off") for x in gf[3]) and "nonstop:on:set" in gf[4] and "nonstop:on" in gf[5] and gf[6] == [],
          "L69 a plain gun shows none, Trigger Happy's nonstop when set or opened; an Orbiter has no typed group: %s %s %s %s" % (gf[3], gf[4], gf[5], gf[6]))
    inh = res["inherited"]
    check(inh[0] == [1.4, "the Salt's params"] and inh[1] == [1, "the game's default"] and inh[2] == [None, "none: off"] and inh[3] == ["plain", "the game's default"],
          "L69 an empty typed box says what applies and where from: %s" % inh)
    check(res["typedRows"] == [["Params"], ["Effect"]], "L69 the weapon form's Params and the mutation form's Effect carry the typed rows: %s" % res["typedRows"])
    # ---- the "word" stat kind and the quest words
    w = res["words"]
    check(w[0] == "pulls more often" and w[1] == "" and w[2] == "+5 m EXP pull radius" and w[3] == "+20% overheal past full health"
          and res["wordsAll"] == "pulls more often, +5 m EXP pull radius, +20% overheal past full health",
          "L69 describeEffect mirrors TextGen: a word stat says its name, never a number: %s / %s" % (w, res["wordsAll"]))
    check(res["summary"] == ["xp_pull_radius"], "L69 levelsSummary leaves a word stat out of the totals: %s" % res["summary"])
    check(all(res["help"]) and res["kinds"][-1] == ["pulls more often", "word"], "L69 every new stat has a help line and its TextGen name and kind")
    want = {"unlock_buck": "Survive 15 minutes in one run.", "unlock_calavera": "Kill the stage 1 boss on Red Canyon.",
            "unlock_ironwood": "Kill 2,500 creatures, all time.", "unlock_may": "Reach level 30 in one run.",
            "unlock_mira": "Kill 99,999,999 creatures, all time.", "unlock_solenne": "Extract after stage 2 on Red Canyon."}
    got = {x["id"]: t for x, t in zip(q["quests"], res["questText"])}
    check(all(got.get(k) == v for k, v in want.items() if k in got) and len(got) >= 6, "L69 questText reads the heroes' requirements as TextGen.quest_text: %s" % got)
    lo, hi = pass44_band()
    check(abs(res["band"]["lo"] - lo) < 1e-9 and abs(res["band"]["hi"] - hi) < 1e-9, "L69 the page's band bounds are pass44_test's: %s / %s-%s" % (res["band"], lo, hi))
    # ---- rules on the content
    perr = [(x["id"], x["errors"]) for x in res["perkIssues"] if x["errors"]]
    check(not perr and len(res["perkIssues"]) == len(perks), "L69 zero errors on the %d perks on disk: %s" % (len(perks), perr))
    herr = [(x["id"], x["errors"]) for x in res["heroIssues"] if x["errors"]]
    check(not herr, "L69 zero errors on the heroes on disk: %s" % herr)
    hw = {x["id"]: [w2["msg"] for w2 in x["warnings"]] for x in res["heroIssues"]}
    on_title = [h["id"] for h in heroes if str(h.get("availability", "hidden" if h.get("hidden") else "available")) != "hidden"]
    disagree = [i for i in on_title if any("disagree" in m for m in hw.get(i, []))]
    check(not disagree, "L69 every hero on the title has hidden and availability in step: %s" % disagree)
    unwhole = {i: [m for m in hw.get(i, []) if "pass66_shape_test" in m] for i in on_title}
    check(not any(unwhole.values()), "L69 every hero on the title is whole as the page counts it (a perk, one hero mutation in play): %s" % {k: v for k, v in unwhole.items() if v})
    cw = {x["id"]: x["warnings"] for x in res["copyIssues"]}
    check(not any("checked by the perk's id" in m for m in cw["lucky_doll"]) and any("checked by the perk's id" in m for m in cw["noon_two"]),
          "L69 a decoy copy under a new id is fine; a High Noon copy is warned (the game checks the id): %s" % cw)
    s = res["sync"]
    check(s[0]["hidden"] is True and s[1]["hidden"] is False and "hidden" not in s[2] and s[3]["availability"] == "hidden" and s[4]["availability"] == "available",
          "L69 Availability and Hidden keep each other in step (one undo step): %s" % s)
    pa = res["paths"]
    check(pa["get"] == [[{"stat": "a"}], "a", None, 1.4, None] if len(pa["get"]) == 5 and pa["get"][2] is None else False,
          "L69 U.getPath steps into lists by index (the level steps showed no effects before): %s" % pa["get"])
    check(pa["after"] == {"levels": [[], [], [{"stat": "b"}]], "params": {"final": {"salt": {"color": "#000000"}}}},
          "L69 U.setPath keeps a list on the way (it became an object before) and never deletes a list element: %s" % pa["after"])
    pt = res["perkTable"]
    check(pt["sections"] == ["Identity", "Card", "Special", "Art"] and all(sec in pt["sections"] for _, sec, _ in pt["rows"])
          and ["special", "Special", "select"] in pt["rows"] and ["params_typed", "Special", "perk_params"] in pt["rows"],
          "L69 the perk form: Identity, Card, Special (the special and its numbers), Art")


def server_checks(check, server):
    import selftest_S as S
    tmp = tempfile.mkdtemp(prefix="le_l69_")
    try:
        content = S.build_tree(tmp)
        with S.Pointed(server, content, S.FakeJobs()):
            hpath = os.path.join(content, "characters", "hero_a", "hero_a.json")
            qpath = os.path.join(content, "quests", "unlock_hero_a", "unlock_hero_a.json")
            r = server.set_availability("hero", "hero_a", {"availability": "purchase", "price": 300, "quest": {"condition": {"type": "kills_total", "count": 2500}}})
            h = json.load(open(hpath, encoding="utf-8"))
            qd = json.load(open(qpath, encoding="utf-8")) if os.path.isfile(qpath) else {}
            check(r["ok"] and r.get("quest") == "unlock_hero_a" and h["hidden"] is False and h["availability"] == "purchase" and h["price"] == 300
                  and qd.get("unlocks") == {"type": "character", "id": "hero_a"} and qd.get("condition") == {"type": "kills_total", "count": 2500}
                  and "glass jar" in qd.get("art_prompt", ""), "L69 a hero's requirement: content/quests/unlock_<hero> with unlocks {type character}; a hero to buy not hidden: %s %s" % (r.get("wrote"), qd))
            heroes = {x["id"]: x for x in server.list_heroes()}
            rc = server.read_content("hero", "hero_a")
            check(heroes["hero_a"]["quest"]["id"] == "unlock_hero_a" and rc["quest"]["id"] == "unlock_hero_a" and heroes["hero_a"]["hidden_in_play"] is False
                  and heroes["hero_a"]["perk_records"][0]["id"] == "perk_a", "L69 /api/heroes and /api/content/hero carry the requirement and the perk records")
            r = server.set_availability("hero", "hero_a", {"availability": "purchase", "quest": {"condition": {"type": "reach_level", "level": 30}, "quest_text": "Reach level 30."}})
            qd = json.load(open(qpath, encoding="utf-8"))
            check(r["ok"] and qd["condition"] == {"type": "reach_level", "level": 30} and qd["quest_text"] == "Reach level 30." and qd["id"] == "unlock_hero_a",
                  "L69 the requirement edited in place: %s" % r.get("wrote"))
            check(server.set_availability("hero", "hero_a", {"availability": "purchase", "quest": {"condition": {"type": "win_lottery"}}})["status"] == 400,
                  "L69 a requirement with an unknown condition is refused")
            r = server.set_availability("hero", "hero_a", {"availability": "available", "quest": None})
            h = json.load(open(hpath, encoding="utf-8"))
            check(r["ok"] and not os.path.isdir(os.path.dirname(qpath)) and r.get("quest") is None and h["availability"] == "available" and h["hidden"] is False,
                  "L69 the requirement removed (the quest moves to the backups), the hero free: %s" % r.get("wrote"))
            r = server.set_availability("hero", "hero_a", {"availability": "hidden"})
            check(r["ok"] and json.load(open(hpath, encoding="utf-8"))["hidden"] is True, "L69 availability hidden hides him")
            # a perk: read, saved key by key, created for a hero from a template, deleted
            rc = server.read_content("perk", "perk_a")
            check(rc["ok"] and rc["kind"] == "perk" and rc["json"]["hero"] == "hero_a", "L69 /api/content/perk/<id> reads a perk")
            d = dict(rc["json"], special="decoy", params={"every": 25.0, "radius": 6.0}, text="A doll.")
            r = server.write_content("perk", "perk_a", d, rc["mtime"])
            pd = json.load(open(os.path.join(content, "perks", "perk_a", "perk_a.json"), encoding="utf-8"))
            check(r["ok"] and pd["special"] == "decoy" and pd["params"] == {"every": 25.0, "radius": 6.0} and pd["text"] == "A doll." and list(pd)[:2] == ["id", "name"],
                  "L69 a perk saved in place (its special and numbers): %s" % r.get("changed"))
            r = server.create_content("perk", "perk_b", "perk_a", "Perk B", "", "", False, {"hero": "hero_b"})
            pb = json.load(open(os.path.join(content, "perks", "perk_b", "perk_b.json"), encoding="utf-8"))
            check(r["ok"] and pb["hero"] == "hero_b" and pb["special"] == "decoy" and pb["name"] == "Perk B" and "hidden" not in pb,
                  "L69 + New perk: a copy of the template for another hero")
            r = server.delete_content("perk", "perk_b")
            check(r["ok"] and not os.path.isdir(os.path.join(content, "perks", "perk_b")), "L69 a perk made in the editor can be deleted")
            items = server.list_items()
            zap = next(w for w in items["weapons"] if w["id"] == "zapper")
            check(isinstance(zap.get("params"), dict), "L69 /api/items' weapon records carry their params (a mutation's typed boxes inherit them)")
            check("perk" in server.EDIT_KINDS and {"special", "params", "hero", "effects", "text"} <= server.EDITOR_OWNED["perk"], "L69 perks are an edit kind the server owns the keys of")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def page_checks(check):
    """The page's files: the new module is loaded and the hooks call it."""
    with open(os.path.join(HERE, "index.html"), "r", encoding="utf-8") as f:
        html = f.read()
    i_assets, i_typed, i_heroes = html.find('src="assets.js"'), html.find('src="typed_forms.js"'), html.find('src="heroes.js"')
    check(0 <= i_assets < i_typed < i_heroes, "L69 index.html loads typed_forms.js after assets.js and before heroes.js")
    src = {n: open(os.path.join(HERE, n), "r", encoding="utf-8").read() for n in ("assets.js", "heroes.js", "items.js", "instructions.js", "typed_forms.js")}
    check("TypedForms.params(" in src["assets.js"] and "TypedForms.perkParams(" in src["assets.js"] and "perk: 'heroes'" in src["assets.js"],
          "L69 assets.js renders the typed rows and opens perks on the Heroes tab")
    check("TypedForms.perkEditor(" in src["heroes.js"] and "TypedForms.requirement(" in src["heroes.js"] and "TypedForms.newPerkDialog(" in src["heroes.js"],
          "L69 heroes.js: the perk form, the requirement, + New perk")
    check("TypedForms.iconCandidates(" in src["items.js"], "L69 items.js shows an item's icon candidates with Install")
    check("function pass69(" in src["instructions.js"] and "pass69(root)" in src["instructions.js"], "L69 the Instructions tab has its Pass 69 section")
    with open(os.path.join(ROOT, "docs", "level_editor.md"), "r", encoding="utf-8") as f:
        doc = f.read()
    with open(os.path.join(ROOT, "docs", "assets_schema.md"), "r", encoding="utf-8") as f:
        schema = f.read()
    check("## Pass 69" in doc, "L69 docs/level_editor.md has its Pass 69 section")
    keys = ["salt.radius", "momentum_on_enter", "bend_deg", "carry.chance", "proc_mult", "loop.radius", "launch.chance", "heat_look", "tint.body",
            "fire_without_target", "stream", "decoy", "special_defaults", "xp_pull_rate", "overheal", "heroes_owned", "unlock_<hero>"]
    check(all(k in schema for k in keys), "L69 docs/assets_schema.md has a row for every new key: missing %s" % [k for k in keys if k not in schema])


def checks(check, run_node, server):
    vocab_checks(check)
    node_checks(check, run_node)
    server_checks(check, server)
    page_checks(check)

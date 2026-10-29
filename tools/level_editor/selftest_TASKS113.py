"""Pass 113, lane TASKS: the seven new task types in the Level Editor (QuestDef's header, WantedBoard.gd's TYPES).
selftest.py discovers this file (`extra_checks`) and hands it its `check` counter. Nothing here writes anything.

  fields   assets_fields.js under Node: the six task quest types in the Condition list, each shows its own rows (the weapon,
           the healing item, the heal source, the element, the count, "In one run") and only those; every row key once;
           the item_level Level box's limits follow the item's own levels;
  words    assets_model.js questTaskText says what TextGen.quest_task_text says (the samples pass113_TASKS_test.gd pins),
           and make_bible.quest_text the same;
  pictures questPicture names the still QuestTracker.picture_of names, and every art file it points at is on disk;
  items    the healing items (passiveHeals) and the items' top levels (itemTopLevel) agree with an independent Python
           reading of the content on disk;
  vocab    vocab.py QUEST_TYPES names the six with their keys, QuestTracker's cases and the table agree, condition_problem
           refuses a broken task condition and an item_level past the item's levels (server.item_top_level);
  wanted   wanted_model.js: the seven Wanted types in the game's order, the context of the real map (the Heart and the
           Healing Well as heal sources, ten Totem Poles, fire and poison, the healing items), many rolls (an item's level
           inside its own levels, never more gifts than poles, a target's own factor on its range, the words filled);
  routes   wanted_io: the new types pass its check, /sources lists the power-ups and structures with what they do, the
           structure icons and the fire are served;
  wiring   index.html loads tasks.js, Assets.idOptions hands the task pickers to it, the three quest editors show the
           picture, Forms.control reads `limits`, server.py names a quest by its healing item, skins_io checks a goal.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")
TASKS = ["damage_with_weapon", "heal_with_item", "heal_with_source", "element_damage", "barrels_total", "totems_total"]
WANTED = ["damage_weapon", "heal_item", "heal_source", "item_level", "barrels", "totems", "element_damage"]
HEAL_STATS = ["lifesteal", "regen", "still_regen", "crit_heal_chance", "heal_drop"]
LADDER = ["common", "uncommon", "rare", "epic", "legendary"]

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = M;
const F = require(path.join(dir, 'assets_fields.js'));
global.AFIELDS = F;
const WM = require(path.join(dir, 'wanted_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.types = F.VOCAB.questTypes.map((o) => o.v);
  out.elements = (F.VOCAB.questElements || []).map((o) => o.v);
  out.keys = F.QUEST_ROWS.map((r) => r.key);
  out.shown = {};
  for (const t of q.tasks) out.shown[t] = F.QUEST_ROWS.filter((r) => typeof r.only !== 'function' || r.only({ condition: { type: t } })).map((r) => r.key);
  out.kindOf = {};
  for (const r of F.QUEST_ROWS) if (r.type === 'id_select') out.kindOf[r.key] = r.kind;
  // the Level box's limits for an item_level quest, with the page's lists standing in (Assets.flatItems)
  global.Assets = { flatItems: () => q.flat };
  const lv = F.QUEST_ROWS.find((r) => r.key === 'condition.level');
  out.limits = q.limitSamples.map((c) => (lv && lv.limits ? lv.limits({ condition: c }) : null));
  // words and pictures
  const nm = { items: { weapons: q.flat.weapons.concat(q.flat.evolutions), passives: q.flat.passives } };
  out.words = q.wordSamples.map((c) => M.questText({ condition: c }, nm));
  out.bareWords = q.wordSamples.map((c) => M.questText({ condition: c }));
  const kindOf = (id) => { if (q.flat.weapons.some((w) => w.id === id) || q.flat.evolutions.some((w) => w.id === id)) return 'weapon'; const p = q.flat.passives.find((x) => x.id === id); return p ? (p.line ? 'card' : 'passive') : ''; };
  out.pics = q.picSamples.map((c) => M.questPicture(c, kindOf));
  // the healing items and the top levels, on the /api/items records
  out.heals = q.flat.passives.filter((p) => !p.evolves_from && (M.passiveHeals(p) || (p.evolved && M.passiveHeals(p.evolved)) || (p.evolves_into && M.passiveHeals(q.flat.passives.find((x) => x.id === p.evolves_into))))).map((p) => p.id).sort();
  out.tops = {};
  for (const w of q.flat.weapons) out.tops[w.id] = M.itemTopLevel(w, 'weapon');
  for (const p of q.flat.passives) out.tops[p.id] = M.itemTopLevel(p, 'passive');
  // the Wanted model
  out.order = WM.TYPE_ORDER;
  out.targetFirst = WM.TARGET_FIRST;
  out.healStats = WM.HEAL_STATS;
  const cfg = WM.normalized(q.cfg);
  const tl = q.map.timeline_data;
  const stages = [{ name: 'Sundown', start: 0, end: 430, boss: 'tumbleweed_king' }, { name: 'Nightfall', start: 430, end: 1030, boss: '' }];
  const hero = q.heroes.find((h) => h.id === 'drifter') || { id: 'drifter' };
  const ctxOf = (all, k) => WM.contextFrom({ tl, map: 'red_canyon', stage: k || 0, stages, creatures: q.enemies, weapons: q.items.weapons, lines: q.items.lines,
    passives: q.items.passives, sources: q.sources, hero, P: 0, beaten: false, metAll: all, seenAll: all, unlocksDone: all });
  const ctx = ctxOf(true, 0);
  out.ctx = { heal_sources: ctx.heal_sources, totem_poles: ctx.totem_poles, elements: ctx.elements.map((e) => e.id), heal_items: ctx.heal_items.map((x) => x.id),
    passive_items: ctx.passive_items.map((x) => [x.id, x.max_level]) };
  const fresh = ctxOf(false, 0);
  out.fresh = { heal_item: WM.targetsOf(cfg, 'heal_item', fresh).length, damage_weapon: WM.targetsOf(cfg, 'damage_weapon', fresh).map((w) => w.id) };
  out.rolls = [];
  const rnd = WM.mulberry32(113);
  for (let i = 0; i < 400; i++) {
    for (const t of q.wanted) {
      const c = WM.makeContract(cfg, t, ctx, rnd);
      if (c) out.rolls.push({ type: t, target: c.target, kind: c.target_kind, n: c.n, d: c.d, skulls: c.skulls, reward: c.reward, name: c.name, text: c.text, still: c.still });
    }
  }
  // a target's own factor (the heal_item row's target_mult)
  const one = WM.normalized({ tasks: [{ type: 'heal_item', weight: 1, difficulty: [1, 3], n: [[100, 200]], step: 1, target_mult: { cake: 0.25 }, text: 'x {n}' }] });
  const cctx = { stage: 0, P: 0, hero: {}, heal_items: [{ id: 'cake', name: 'Cake', kind: 'passive', seen: true }] };
  out.cake = [];
  for (let i = 0; i < 60; i++) out.cake.push(WM.makeContract(one, 'heal_item', cctx, rnd).n);
  out.issues = WM.issues(cfg);
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _load(kind):
    out = {}
    for f in sorted(glob.glob(os.path.join(CONTENT, kind, "*", "*.json"))):
        if os.path.basename(f) != os.path.basename(os.path.dirname(f)) + ".json":
            continue
        try:
            d = json.loads(_read(f))
        except ValueError:
            continue
        out[d.get("id", os.path.basename(os.path.dirname(f)))] = d
    return out


WORD_SAMPLES = [
    ({"type": "damage_with_weapon", "weapon": "revolver", "count": 1000}, "Deal 1,000 damage with the Revolver."),
    ({"type": "damage_with_weapon", "weapon": "revolver", "count": 1000, "in_one_run": True}, "Deal 1,000 damage with the Revolver in one run."),
    ({"type": "heal_with_item", "item": "thirst", "count": 2000}, "Restore 2,000 HP with Death."),
    ({"type": "heal_with_source", "source": "pickup:heart", "count": 500}, "Restore 500 HP with Hearts."),
    ({"type": "heal_with_source", "source": "structure:healing_well", "count": 300}, "Restore 300 HP with Healing Wells."),
    ({"type": "heal_with_source", "source": "pickup:", "count": 50}, "Restore 50 HP with power-ups."),
    ({"type": "element_damage", "element": "fire", "count": 20000}, "Deal 20,000 fire damage."),
    ({"type": "element_damage", "element": "poison", "count": 5000}, "Deal 5,000 poison damage."),
    ({"type": "barrels_total", "count": 40}, "Break 40 barrels."),
    ({"type": "totems_total", "count": 10}, "Take 10 Totem gifts."),
    ({"type": "totems_total", "count": 1}, "Take a Totem gift."),
]
PIC_SAMPLES = [
    ({"type": "damage_with_weapon", "weapon": "revolver"}, {"kind": "weapon", "id": "revolver"}),
    ({"type": "heal_with_item", "item": "mend"}, {"kind": "card", "id": "mend"}),
    ({"type": "heal_with_item", "item": "siesta"}, {"kind": "passive", "id": "siesta"}),
    ({"type": "heal_with_source", "source": "pickup:heart"}, {"kind": "pickup", "id": "heart"}),
    ({"type": "heal_with_source", "source": "structure:healing_well"}, {"kind": "structure", "id": "healing_well"}),
    ({"type": "heal_with_source", "source": "pickup:"}, {}),
    ({"type": "element_damage", "element": "poison"}, {"kind": "art", "id": "poison"}),
    ({"type": "element_damage", "element": "fire"}, {"kind": "art", "id": "fire"}),
    ({"type": "barrels_total"}, {"kind": "art", "id": "barrel"}),
    ({"type": "totems_total"}, {"kind": "structure", "id": "totem_pole"}),
    ({"type": "item_level", "id": "orbit_saws", "kind": "weapon"}, {"kind": "weapon", "id": "orbit_saws"}),
    ({"type": "item_level", "kind": "weapon", "level": 3}, {}),
    ({"type": "kills_of_enemy", "enemy": "skeleton"}, {"kind": "enemy", "id": "skeleton"}),
]
ART_FILES = {"barrel": ("art", "ui", "wanted", "barrel.png"), "poison": ("art", "ui", "wanted", "poison.png"),
             "fire": ("art", "ui", "sources", "fire.png")}


def _heals(p, by_id):
    def carries(d):
        for lv in (d or {}).get("levels", []) or []:
            for e in lv if isinstance(lv, list) else []:
                t = str(e.get("target", "player"))
                if isinstance(e, dict) and e.get("stat") in HEAL_STATS and float(e.get("value", 0) or 0) > 0 and not (t == "all_weapons" or t.startswith("weapon:") or t.startswith("tag:")):
                    return True
        return False
    return carries(p) or carries(by_id.get(p.get("evolves_into", "")))


def _top(d, kind):
    if kind == "weapon":
        return max(int(d.get("max_level", 8) or 1), 1)
    if d.get("line") or d.get("evolves_from"):
        return max(int(d.get("max_level", 8) or 1), 1)
    if d.get("single"):
        return 1
    r = d.get("rarity", "common")
    return len(LADDER) - 1 - (LADDER.index(r) if r in LADDER else 0) + 2


def checks(check, run_node, server):
    import vocab
    import wanted_io as WIO
    items = server.list_items()
    flat_w = [w for w in items["weapons"]]
    flat_e = [w["evolution"] for w in items["weapons"] if w.get("evolution")]
    flat_p = []
    for l in items["lines"]:
        flat_p.append(l)
        if l.get("evolved"):
            flat_p.append(l["evolved"])
    flat_p += items["passives"]
    flat = {"weapons": flat_w, "evolutions": flat_e, "passives": flat_p}
    cfg = json.loads(_read(os.path.join(CONTENT, "wanted", "wanted.json")))
    mp = json.loads(_read(os.path.join(CONTENT, "maps", "red_canyon", "red_canyon.json")))
    sources = WIO.sources(server)
    limit_samples = [{"type": "item_level", "id": "orbit_saws", "level": 3}, {"type": "item_level", "id": "siesta", "level": 2},
                     {"type": "item_level", "id": "mend", "level": 2}, {"type": "item_level", "kind": "weapon", "level": 3},
                     {"type": "item_level", "id": "beer", "rung": "epic"}, {"type": "reach_level", "level": 10}]
    q = {"tasks": TASKS, "wanted": WANTED, "flat": flat, "items": items, "cfg": cfg, "map": mp, "sources": sources,
         "enemies": server.list_creatures(), "heroes": server.list_heroes(), "limitSamples": limit_samples,
         "wordSamples": [c for c, _ in WORD_SAMPLES], "picSamples": [c for c, _ in PIC_SAMPLES]}
    r = run_node(q, RUNNER) or {}
    if not r:
        check(False, "TASKS113 the fields and the models ran under node")
        return
    # ---- fields
    check(all(t in r["types"] for t in TASKS), "TASKS113 the six task types are in the Condition list: %s" % r["types"])
    check(r["elements"] == ["fire", "poison", ""], "TASKS113 the elements fire, poison, both: %s" % r["elements"])
    check(len(r["keys"]) == len(set(r["keys"])), "TASKS113 every quest row key once: %s" % r["keys"])
    want_rows = {
        "damage_with_weapon": {"condition.weapon", "condition.count", "condition.in_one_run"},
        "heal_with_item": {"condition.item", "condition.count", "condition.in_one_run"},
        "heal_with_source": {"condition.source", "condition.count", "condition.in_one_run"},
        "element_damage": {"condition.element", "condition.count", "condition.in_one_run"},
        "barrels_total": {"condition.count", "condition.in_one_run"},
        "totems_total": {"condition.count", "condition.in_one_run"},
    }
    common = {"name", "condition.type", "quest_text"}
    for t, rows in want_rows.items():
        got = set(r["shown"].get(t, [])) - common
        check(got == rows, "TASKS113 the %s form shows %s: %s" % (t, sorted(rows), sorted(got)))
    check(r["kindOf"].get("condition.item") == "heal_item" and r["kindOf"].get("condition.source") == "heal_source" and r["kindOf"].get("condition.id") == "any_item",
          "TASKS113 the pickers: a healing item, a heal source, any item for item_level: %s" % r["kindOf"])
    lim = r["limits"]
    check(lim[0].get("max") == 5 and lim[1].get("max") == _top(_load("passives")["siesta"], "passive") and lim[2].get("max") == _top(_load("passives")["mend"], "passive")
          and lim[3] == {} and lim[4] == {} and lim[5] == {} and "1 to 5" in str(lim[0].get("hint", "")),
          "TASKS113 an item_level quest's Level stays inside the item's own levels (a rung or no item: no limit): %s" % lim)
    # ---- words
    want = [w for _, w in WORD_SAMPLES]
    check(r["words"] == want, "TASKS113 questText says the task quests as TextGen does: %s" % [(a, b) for a, b in zip(r["words"], want) if a != b])
    check(all(x and x != "Complete a challenge." for x in r["bareWords"]), "TASKS113 without names every task quest still reads: %s" % r["bareWords"])
    sys.path.insert(0, TOOLS)
    cwd = os.getcwd()
    try:
        os.chdir(ROOT)
        import make_bible
        bible = [make_bible.quest_text({"condition": c}) for c, _ in WORD_SAMPLES]
        stages = [make_bible.quest_stage({"condition": c}) for c, _ in WORD_SAMPLES]
    finally:
        os.chdir(cwd)
    check(bible == want, "TASKS113 the bible says them the same: %s" % [(a, b) for a, b in zip(bible, want) if a != b])
    check(all(s == 1 for s in stages), "TASKS113 the bible's stage hints (stage 1 can do them): %s" % stages)
    # ---- pictures
    wantp = [p for _, p in PIC_SAMPLES]
    check(r["pics"] == wantp, "TASKS113 questPicture names QuestTracker.picture_of's still: %s" % [(c, a, b) for (c, _), a, b in zip(PIC_SAMPLES, r["pics"], wantp) if a != b])
    for k, parts in ART_FILES.items():
        check(os.path.isfile(os.path.join(GAME, *parts)), "TASKS113 the %s picture is on disk: %s" % (k, "/".join(parts)))
    check(os.path.isfile(os.path.join(CONTENT, "structures", "totem_pole", "totem_pole_icon.png")), "TASKS113 the Totem Pole's icon is on disk")
    wp = _read(os.path.join(GAME, "ui", "wanted", "WPoster.gd"))
    check(all(('"%s": "res://%s"' % (k, "/".join(p))) in wp for k, p in ART_FILES.items()) and '"pickup":' in wp and '"structure":' in wp,
          "TASKS113 WPoster draws the barrel, the flask, the fire, a power-up and a structure")
    # ---- items
    passives = _load("passives")
    py_heals = sorted(pid for pid, d in passives.items() if not d.get("evolves_from") and _heals(d, passives))
    check(r["heals"] == py_heals, "TASKS113 the healing items read off the content: page %s / python %s" % (r["heals"], py_heals))
    check({"thirst", "mend", "hot_springs", "siesta", "vulture", "cake"} <= set(py_heals) and "snake_oil" not in py_heals,
          "TASKS113 the healing items are Death, Temperance, Hot Springs, Siesta, Vulture and Cake (not Snake Oil): %s" % py_heals)
    weapons = _load("weapons")
    bad = []
    for wid, d in weapons.items():
        if r["tops"].get(wid) != _top(d, "weapon") or vocab.item_top_level(d, "weapon") != _top(d, "weapon"):
            bad.append(wid)
    for pid, d in passives.items():
        if pid in r["tops"] and (r["tops"][pid] != _top(d, "passive") or vocab.item_top_level(d, "passive") != _top(d, "passive")):
            bad.append(pid)
    check(not bad, "TASKS113 every item's top level: the page, vocab and the ladder agree: %s" % bad)
    # ---- vocab
    check({t: vocab.QUEST_TYPES.get(t) for t in TASKS} == {"damage_with_weapon": ["weapon", "count", "in_one_run"], "heal_with_item": ["item", "count", "in_one_run"],
          "heal_with_source": ["source", "count", "in_one_run"], "element_damage": ["element", "count", "in_one_run"], "barrels_total": ["count", "in_one_run"],
          "totems_total": ["count", "in_one_run"]}, "TASKS113 vocab.QUEST_TYPES names the six task types and their keys")
    probs = [p for p in vocab.check_against_source(GAME) if p.startswith("quest types")]
    check(not probs, "TASKS113 QuestTracker's cases and vocab's table agree: %s" % probs)
    cp = vocab.condition_problem
    top = server.item_top_level
    good = [{"type": "damage_with_weapon", "weapon": "revolver", "count": 50000}, {"type": "heal_with_source", "source": "pickup:heart", "count": 5, "in_one_run": True},
            {"type": "heal_with_source", "source": "structure:", "count": 5}, {"type": "element_damage", "element": "", "count": 9},
            {"type": "item_level", "id": "orbit_saws", "level": 5}, {"type": "item_level", "kind": "card", "level": 4}, {"type": "kills_total", "count": 1}]
    badc = [{"type": "damage_with_weapon", "weapon": "revolver", "count": 0}, {"type": "barrels_total", "count": 3, "in_one_run": "yes"},
            {"type": "heal_with_source", "source": "heart", "count": 5}, {"type": "heal_with_source", "source": "tree:oak", "count": 5},
            {"type": "element_damage", "element": "ice", "count": 9}, {"type": "item_level", "id": "orbit_saws", "level": 6}, {"type": "nope"}]
    check(all(cp(c, top) == "" for c in good), "TASKS113 condition_problem lets good conditions through: %s" % [cp(c, top) for c in good])
    check(all(cp(c, top) != "" for c in badc), "TASKS113 condition_problem refuses a broken one (count 0, in_one_run not a bool, a source without its kind, an element, the Orbit Saws to 6): %s" % [cp(c, top) for c in badc])
    check(top("orbit_saws") == 5 and top("nope_not_here") == 0, "TASKS113 server.item_top_level reads an item's top level")
    # ---- wanted
    check(r["order"][-7:] == WANTED and WIO.TYPES[-7:] == WANTED, "TASKS113 the seven Wanted types close the order in the page and the server: %s" % r["order"])
    gd = _read(os.path.join(GAME, "core", "systems", "WantedBoard.gd"))
    m = re.search(r"const TARGET_FIRST := \[(.*?)\]", gd, re.S)
    check(m and re.findall(r'"([a-z_]+)"', m.group(1)) == r["targetFirst"], "TASKS113 the game and the page roll the same types target first: %s" % r["targetFirst"])
    tt = _read(os.path.join(GAME, "core", "systems", "TaskTally.gd"))
    m2 = re.search(r"const HEAL_STATS := \[(.*?)\]", tt, re.S)
    check(m2 and re.findall(r'"([a-z_]+)"', m2.group(1)) == r["healStats"] == HEAL_STATS, "TASKS113 the game and the page heal by the same stats: %s" % r["healStats"])
    ctx = r["ctx"]
    srcs = [("%s:%s" % (x["kind"], x["id"])) for x in ctx["heal_sources"]]
    check("pickup:heart" in srcs and "structure:healing_well" in srcs and "pickup:cake_slice" not in srcs,
          "TASKS113 the map's heal sources: the Heart (kills and barrels), the Healing Well (placed), never a Cake Slice: %s" % srcs)
    check(ctx["totem_poles"] == 10 and ctx["elements"] == ["fire", "poison"], "TASKS113 ten Totem Poles, fire and poison reachable: %s / %s" % (ctx["totem_poles"], ctx["elements"]))
    check({"mend", "hot_springs", "siesta", "vulture", "cake"} <= set(ctx["heal_items"]), "TASKS113 the healing items a run may get: %s" % ctx["heal_items"])
    check(r["fresh"]["heal_item"] == 0 and r["fresh"]["damage_weapon"] == ["revolver"],
          "TASKS113 a fresh save: no healing item seen yet; the hero's own gun only: %s" % r["fresh"])
    bad = {"level": [], "totems": [], "words": [], "reward": [], "still": []}
    tops = r["tops"]
    seen = set()
    for b in r["rolls"]:
        seen.add(b["type"])
        if b["type"] == "item_level" and not (2 <= b["n"] <= tops.get(b["target"], 0)):
            bad["level"].append((b["target"], b["n"], tops.get(b["target"])))
        if b["type"] == "totems" and not (1 <= b["n"] <= ctx["totem_poles"]):
            bad["totems"].append(b["n"])
        if "{" in b["name"] + b["text"] or not b["text"]:
            bad["words"].append((b["name"], b["text"]))
        if b["reward"] % 5 or not 1 <= b["skulls"] <= 5:
            bad["reward"].append(b)
        if not b["still"] or not b["still"].get("kind"):
            bad["still"].append(b["type"])
    check(seen == set(WANTED), "TASKS113 every new Wanted type rolls on the real map: %s" % sorted(seen))
    for k, v in bad.items():
        check(not v, "TASKS113 %d rolls: %s right: %s" % (len(r["rolls"]), k, v[:5]))
    check(all(25 <= n <= 50 for n in r["cake"]), "TASKS113 a target's own factor scales its range (Cake x0.25 of 100-200): %s" % sorted(set(r["cake"]))[:10])
    check(not r["issues"]["errors"], "TASKS113 the game's wanted.json has no errors: %s" % r["issues"]["errors"])
    # ---- routes
    check(WIO.check(cfg) == "", "TASKS113 the game's wanted.json passes the server's check: %s" % WIO.check(cfg))
    pk = {p["id"]: p for p in sources["pickups"]}
    st = {s["id"]: s for s in sources["structures"]}
    check(pk.get("heart", {}).get("effect") == "heal" and pk.get("cake_slice", {}).get("credit_stat") == "heal_drop" and st.get("healing_well", {}).get("effect") == "heal"
          and (st.get("totem_pole", {}).get("per_map") or {}).get("min") == 10,
          "TASKS113 /api/wanted/sources: the Heart heals, a Cake Slice is heal_drop's, the Healing Well heals, ten Totem Poles at least")
    check(WIO.structure_icon(server, "totem_pole") and WIO.structure_icon(server, "healing_well") and WIO.structure_icon(server, "../x") is None,
          "TASKS113 the structure icons are served (and nothing outside)")
    check(WIO.art_path(server, "sources", "fire.png") and WIO.art_path(server, "wanted", "barrel.png") and WIO.art_path(server, "wanted", "poison.png"),
          "TASKS113 the fire, the barrel and the flask are served")
    # ---- wiring
    html = _read(os.path.join(HERE, "index.html"))
    check(html.find('<script src="tasks.js"></script>') > html.find('<script src="wanted.js"></script>') > 0, "TASKS113 index.html loads tasks.js after wanted.js")
    asrc = _read(os.path.join(HERE, "assets.js"))
    check("TaskPics.options(kind, mk)" in asrc, "TASKS113 Assets.idOptions hands the healing items and sources to tasks.js")
    for f in ("typed_forms.js", "items.js", "skins.js"):
        check("TaskPics.row(draft)" in _read(os.path.join(HERE, f)), "TASKS113 %s shows the goal's picture" % f)
    check("def.limits" in _read(os.path.join(HERE, "forms.js")), "TASKS113 Forms.control reads a row's limits")
    srv = _read(os.path.join(HERE, "server.py"))
    check('str(c.get("item", ""))' in srv and "VOCAB.condition_problem" in srv, "TASKS113 server.py names a quest by its healing item and checks the conditions")
    check("VOCAB.condition_problem" in _read(os.path.join(HERE, "skins_io.py")), "TASKS113 skins_io checks a goal's condition")
    try:
        refs = server.references_to("passive", "mend")["quests"]
        check("unlock_thirst" in refs, "TASKS113 references_to still names the quests that name an item: %s" % refs)
    except Exception as e:
        check(False, "TASKS113 references_to: %s" % e)

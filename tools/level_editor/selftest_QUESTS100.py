"""Pass 100, lane QUESTS: the build quests (QuestDef's header: hero_level, item_level, evolve_item, weapon_paths,
items_maxed) in the Level Editor. selftest.py discovers this file (`extra_checks`) and hands it its `check` counter.
Nothing here writes anything.

  fields   assets_fields.js under Node: the five types in the Condition list, the item kinds and rungs, each type
           shows its own fields in the quest form (and only those), every row key once;
  words    assets_model.js questText mirrors TextGen.quest_build_text (names from the content on disk) and agrees with
           make_bible.quest_text on every quest on disk; without names it still says something for every type;
  vocab    vocab.py QUEST_TYPES names the five with their keys, the served table carries the kinds and rungs, and
           check_against_source finds QuestTracker's cases and the table equal;
  server   references_to names the quests that name an item (`id`) or a hero (`hero`);
  forms    items.js and typed_forms.js pick the quest's ids by the row's kind (a hero, any item), not always a weapon;
  content  the converted quests read as the game says them.
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
CONTENT = os.path.join(ROOT, "game", "content")
TYPES = ["hero_level", "item_level", "evolve_item", "weapon_paths", "items_maxed"]

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = M;
const F = require(path.join(dir, 'assets_fields.js'));
global.AFIELDS = F;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.types = F.VOCAB.questTypes.map((o) => o.v);
  out.kinds = (F.VOCAB.questItemKinds || []).map((o) => o.v);
  out.rungs = (F.VOCAB.questRungs || []).map((o) => o.v);
  out.keys = F.QUEST_ROWS.map((r) => r.key);
  out.shown = {};
  for (const t of q.types) out.shown[t] = F.QUEST_ROWS.filter((r) => typeof r.only !== 'function' || r.only({ condition: { type: t } })).map((r) => r.key);
  out.kindOf = {};
  for (const r of F.QUEST_ROWS) if (r.type === 'id_select') out.kindOf[r.key] = r.kind;
  const hero = (id) => { const h = q.heroes.find((x) => x.id === id); return h ? h.name : ''; };
  out.named = q.quests.map((x) => M.questText(x, { hero, items: q.items }));
  out.bare = q.samples.map((x) => M.questText(x));
  out.sampleNamed = q.samples.map((x) => M.questText(x, { hero, items: q.items }));
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
    out = []
    for f in sorted(glob.glob(os.path.join(CONTENT, kind, "*", "*.json"))):
        if os.path.basename(f) != os.path.basename(os.path.dirname(f)) + ".json":
            continue
        try:
            out.append(json.loads(_read(f)))
        except ValueError:
            pass
    return out


def _items():
    """The page's flat item lists (Assets.flatItems' shape, the fields questText reads)."""
    ws = [{"id": d["id"], "name": d.get("name", d["id"]), "is_evolution": bool(d.get("is_evolution")), "evolves_into": d.get("evolves_into", "")} for d in _load("weapons")]
    es = [{"id": d["id"], "name": d.get("name", d["id"]), "is_evolution": True, "evolves_into": ""} for d in _load("evolutions")]
    ps = [{"id": d["id"], "name": d.get("name", d["id"]), "line": bool(d.get("line")), "evolves_into": d.get("evolves_into", ""), "evolves_from": d.get("evolves_from", "")} for d in _load("passives")]
    ms = [{"id": d["id"], "weapon": d.get("weapon", ""), "hidden": bool(d.get("hidden")), "hero": d.get("hero", ""), "kind": "hero" if d.get("kind") == "hero" else d.get("kind", "motion")} for d in _load("mutations")]
    return {"weapons": ws + es, "passives": ps, "mutations": ms}


SAMPLES = [
    {"condition": {"type": "hero_level", "hero": "drifter", "level": 12}},
    {"condition": {"type": "item_level", "kind": "weapon", "id": "orbit_saws", "level": 5}},
    {"condition": {"type": "item_level", "kind": "card", "level": 4}},
    {"condition": {"type": "item_level", "kind": "passive", "rung": "legendary"}},
    {"condition": {"type": "item_level", "id": "beer", "level": 3}},
    {"condition": {"type": "evolve_item", "id": "salt"}},
    {"condition": {"type": "evolve_item", "id": "mend"}},
    {"condition": {"type": "evolve_item", "id": "gas_mask"}},
    {"condition": {"type": "evolve_item", "kind": "card"}},
    {"condition": {"type": "weapon_paths", "weapon": "revolver"}},
    {"condition": {"type": "weapon_paths"}},
    {"condition": {"type": "items_maxed", "kind": "weapon", "count": 3}},
    {"condition": {"type": "items_maxed", "kind": "any", "count": 1}},
]
# TextGen.quest_build_text's words for the samples (pass100_QUESTS_test pins the game's side)
WANT = [
    "Reach level 12 with Drifter.",
    "Get the Orbit Saws to level 5 in one run.",
    "Get a card to level 4 in one run.",
    "Get a passive item to Legendary in one run.",
    "Get Beer to level 3 in one run.",
    "Evolve the Salt into the Hiwa Kai.",
    "Evolve Temperance into Temperance Risen.",
    "Get Gas Mask to Evolved in one run.",
    "Evolve any card.",
    "Take all 3 mutations of the Revolver in one run.",
    "Take all of one weapon's mutations in one run.",
    "Hold 3 weapons at max level at once.",
    "Hold 1 item at max level at once.",
]


def checks(check, run_node, server):
    quests = _load("quests")
    heroes = [{"id": d["id"], "name": d.get("name", d["id"])} for d in _load("characters")]
    q = {"types": TYPES, "quests": quests, "heroes": heroes, "items": _items(), "samples": SAMPLES}
    r = run_node(q, RUNNER) or {}
    if not r:
        check(False, "QUESTS100 the fields and the model ran under node")
        return
    # ---- fields
    check(all(t in r["types"] for t in TYPES), "QUESTS100 the five build types are in the Condition list: %s" % r["types"])
    check(r["kinds"] == ["any", "weapon", "card", "passive"] and r["rungs"][-2:] == ["legendary", "evolved"],
          "QUESTS100 the item kinds and the rungs: %s / %s" % (r["kinds"], r["rungs"]))
    check(len(r["keys"]) == len(set(r["keys"])), "QUESTS100 every quest row key once: %s" % r["keys"])
    want_rows = {
        "hero_level": {"condition.hero", "condition.level"},
        "item_level": {"condition.kind", "condition.id", "condition.level", "condition.rung"},
        "evolve_item": {"condition.kind", "condition.id"},
        "weapon_paths": {"condition.weapon"},
        "items_maxed": {"condition.kind", "condition.count"},
    }
    common = {"name", "condition.type", "quest_text"}
    for t, rows in want_rows.items():
        got = set(r["shown"].get(t, [])) - common
        check(got == rows, "QUESTS100 the %s form shows %s: %s" % (t, sorted(rows), sorted(got)))
    check(r["kindOf"].get("condition.hero") == "hero" and r["kindOf"].get("condition.id") == "any_item" and r["kindOf"].get("condition.weapon") == "weapon",
          "QUESTS100 the id rows pick a hero, any item, a weapon: %s" % r["kindOf"])
    # ---- words
    check(r["sampleNamed"] == WANT, "QUESTS100 questText says the build quests as TextGen does: %s" % [(a, b) for a, b in zip(r["sampleNamed"], WANT) if a != b])
    check(all(x and x != "Complete a challenge." for x in r["bare"]), "QUESTS100 without names every build quest still reads: %s" % r["bare"])
    sys.path.insert(0, TOOLS)
    cwd = os.getcwd()
    try:
        os.chdir(ROOT)
        import make_bible
        bible = [make_bible.quest_text(x) for x in quests]
        stages = {x["id"]: make_bible.quest_stage(x) for x in quests}
    finally:
        os.chdir(cwd)
    diff = [(x["id"], a, b) for x, a, b in zip(quests, r["named"], bible) if a != b and (x.get("condition") or {}).get("type") in TYPES]
    check(not diff, "QUESTS100 the page and the bible say every build quest on disk the same: %s" % diff)
    check(stages.get("unlock_land_mine") == 2 and stages.get("unlock_sabre") == 1 and stages.get("unlock_thirst") == 1,
          "QUESTS100 the bible's stage hints follow QuestTracker.stage_hint: %s" % {k: stages.get(k) for k in ("unlock_land_mine", "unlock_sabre", "unlock_thirst")})
    # ---- vocab
    import vocab
    check(all(t in vocab.QUEST_TYPES for t in TYPES) and vocab.QUEST_TYPES["hero_level"] == ["hero", "level"] and vocab.QUEST_TYPES["items_maxed"] == ["kind", "count"],
          "QUESTS100 vocab.QUEST_TYPES names the build types and their keys")
    probs = [p for p in vocab.check_against_source(os.path.join(ROOT, "game")) if p.startswith("quest types")]
    check(not probs, "QUESTS100 QuestTracker's cases and vocab's table agree: %s" % probs)
    check(vocab.QUEST_ITEM_KINDS == ["any", "weapon", "card", "passive"] and "legendary" in vocab.QUEST_RUNGS, "QUESTS100 the kinds and rungs tables")
    # ---- server
    try:
        refs_w = server.references_to("weapon", "orbit_saws")["quests"]
        refs_h = server.references_to("hero", "calavera")["quests"]
        check("unlock_sabre" in refs_w and "unlock_may" in refs_h and "unlock_calavera" in refs_h,
              "QUESTS100 references_to names the quests that name an item or a hero: %s / %s" % (refs_w, refs_h))
    except Exception as e:  # the server's content dir may point at a temp copy in another group: report, do not crash
        check(False, "QUESTS100 references_to: %s" % e)
    # ---- forms
    for f in ("items.js", "typed_forms.js"):
        src = _read(os.path.join(HERE, f))
        check("Assets.idOptions(def.kind || 'weapon')" in src and "Assets.idOptions('weapon') || []" not in src,
              "QUESTS100 %s picks a quest's ids by the row's kind" % f)
    # ---- content
    by_id = {x["id"]: x for x in quests}
    conv = {"unlock_sabre": "item_level", "unlock_haste": "item_level", "unlock_overkill": "item_level", "unlock_land_mine": "evolve_item",
            "unlock_thirst": "evolve_item", "unlock_ricochet": "weapon_paths", "unlock_fadeaway": "hero_level", "unlock_may": "hero_level"}
    bad = [k for k, t in conv.items() if (by_id.get(k, {}).get("condition") or {}).get("type") != t]
    check(not bad, "QUESTS100 the converted quests carry their build types: %s" % bad)
    named = dict(zip([x["id"] for x in quests], r["named"]))
    check(named.get("unlock_may", "").startswith("Reach level ") and named.get("unlock_may", "").endswith(" with Calavera.")
          and named.get("unlock_ricochet") == "Take all 3 mutations of the Revolver in one run.",
          "QUESTS100 May's and Ricochet's requirements read: %s / %s" % (named.get("unlock_may"), named.get("unlock_ricochet")))

#!/usr/bin/env python
"""The Trail's nodes, as readable data, and the two fits behind them (pass 129, lane TRAIL-SETUP; pass 140, lane TRAIL:
plan v2 of docs/progression/progression_plan.html with Garry's changes, 130 nodes on 70 levels; pass 141, lane TRAIL:
one lane, Garry: "The 2 lanes seem redundant, I can't progress unless I buy both ... I'd rather have fewer variety and
higher value increase to the power nodes. Also it's ok to just increase the total number of levels": one thing to buy a
level (a plain node or one choice group), 109 nodes on 83 levels).

  python tools/trail_setup.py --check              the design's own rules (counts, the mix, no type twice within five
                                                   levels, no unlock in a choice, the unlock set, ...); exit 1 on a fault
  python tools/trail_setup.py --tables             the power table (the model below) and the price table (the journey
                                                   model below), as Markdown
  python tools/trail_setup.py --fit                searches `price` (k, power) so the journey model buys the last level
                                                   by run TARGET_RUNS, its early levels near the plan's checkpoints
  python tools/trail_setup.py --probe-plan <dir>   a candidate Trail file + the plan game/tools/_p129_SETUP_power.gd
                                                   measures (the real stat sheet, HeroPower.gd)
  python tools/trail_setup.py --write [--force]    writes `nodes` and `price` into game/content/trail/trail.json through
                                                   the Level Editor's own writer (tools/level_editor/trail_io.dump),
                                                   every other block as it is

--write refuses when the file's nodes are not the ones this script wrote last (tools/trail_setup.stamp holds their
hash): Garry edits the Trail in the Level Editor, and his nodes are never overwritten without --force (carry his
edits into DESIGN first: pass 140 kept his Might 0.05 on level 1).

The design is DESIGN below: one row a level. Schema: docs/trail_schema.md. Why each number: BALANCING.md (pass 129,
pass 140 81.TRAIL).
"""
import argparse
import hashlib
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
TRAIL = os.path.join(ROOT, "game", "content", "trail", "trail.json")
STAMP = os.path.join(HERE, "trail_setup.stamp")
sys.path.insert(0, os.path.join(HERE, "level_editor"))

# ---------------------------------------------------------------- the design

UNLOCK_MULT = 0.5   # pass 140: an item, Card or skin node costs half its level's price
OUTLAW_MULT = 2.0   # pass 140: an outlaw twice his level's price (pass 129: his own fixed price)


def up(kind, value, **kw):
    """An upgrade node: type and its own amount. kw: name (a milestone's own name), mult (price multiplier),
    price (its own price), meet (rails meeting: it names every member of the choice group right below it in `from`,
    `need` any, so the rails of the road taken and of the roads not taken meet on it; pass 129 and 140 named the two
    lanes' nodes of the level below)."""
    return dict(kw, give={"type": "upgrade", "upgrade": kind, "value": value})


def outlaw(cid):
    return {"give": {"type": "outlaw", "id": cid}, "outlaw": cid, "mult": OUTLAW_MULT}


def weapon(wid):
    return {"give": {"type": "weapon", "id": wid}, "mult": UNLOCK_MULT}


def passive(pid):
    return {"give": {"type": "passive", "id": pid}, "mult": UNLOCK_MULT}


def skin(cid, code):
    return {"give": {"type": "skin", "id": "%s:%s" % (cid, code)}, "mult": UNLOCK_MULT}


def stage(sid):
    return {"give": {"type": "stage", "map": "red_canyon", "stage": sid}}


def choice(*members):
    return {"choice": list(members)}


def opt(node, **kw):
    return dict(node, optional=True, **kw)


# Stakes: an optional node, on for good; the old board's rank (creatures or bosses +10% HP and attack, +4% speed, a
# hidden +5% XP and coins). A challenge, not power: a quarter of the curve's price.
STAKES = dict(mult=0.25)

# level: the nodes on it, left to right (required first, optional after). Pass 141 (Garry, Polish #4: "The 2 lanes seem
# redundant, I can't progress unless I buy both, what's the point of having 2 at a time? ... I'd rather have fewer variety
# and higher value increase to the power nodes. Also it's ok to just increase the total number of levels"): ONE thing to
# buy a level, a plain node or one choice group, the optional nodes beside as before. Pass 140's 56 plain power nodes
# became 35: neighbouring nodes of a type merged into one of their summed amount (each stands at its members' middle in
# pass 140's order, "a + b" below), four thin types left the Trail (Hot Lead, Care Package, Tight Grip, Loose Coins: one
# node each); every unlock keeps its own level in pass 140's order, the twelve choice groups and the ten optional nodes are
# pass 140's; the three rails-meeting milestones each stand right after a choice group and name its members (`need` any).
# The modelled power of the last level is pass 140's to the digit (the same sums: might 0.30, Grit 0.51, Dead Eye 0.07
# plain, Tempo 0.24, Poultice 1.5, Aegis 85, Plate 0.22, Kill Shot 0.35, ...).
DESIGN = [
    # ---- the opening: plain nodes only, the first three power, no type twice; the first items from level 5
    (1, [up("might", 0.05, price=10)]),   # Garry's 0.05 (pass 130), its own price
    (2, [up("health", 0.15)]),   # 2 + 9
    (3, [up("boots", 0.019)]),
    (4, [up("magnet", 0.12)]),
    (5, [passive("haste")]),
    (6, [passive("pocket_watch")]),
    (7, [up("study", 0.11)]),   # 6 + 40
    (8, [passive("clover")]),
    (9, [passive("powder_keg")]),
    (10, [up("crit_chance", 0.07)]),   # 3 + 12 + 58
    (11, [up("greed", 0.06)]),
    (12, [passive("field_notes")]),
    (13, [choice(up("area", 0.08), up("tempo", 0.04))]),
    (14, [passive("lightning_in_a_bottle")]),
    (15, [up("shield", 20)]),   # 8 + 13
    (16, [weapon("tumbleweed")]),
    (17, [passive("magnet"), opt(up("grubstake", 25))]),
    (18, [passive("mule_kick")]),
    (19, [up("tempo", 0.08), opt(up("stakes", 0.1), **STAKES)]),   # 5 + 19
    (20, [passive("assayers_scale")]),
    (21, [weapon("rocket_pod")]),
    (22, [outlaw("calavera")]),
    (23, [up("regen", 0.9)]),   # 7 + 27
    (24, [choice(up("health", 0.1), up("evade", 0.05))]),
    (25, [passive("jade_key")]),
    (26, [stage("dust")]),
    (27, [up("plate", 0.06)]),   # 13 + 25
    (28, [passive("pocket_bible"), opt(up("boss_stakes", 0.1), **STAKES)]),
    # ---- the middle: a choice about one level in eight
    (29, [up("might", 0.15)]),   # 15 + 33
    (30, [weapon("hornet_nest")]),
    (31, [passive("tin_star")]),
    (32, [outlaw("solenne")]),
    (33, [up("shield", 25)]),   # 20 + 27
    (34, [passive("grindstone")]),
    (35, [choice(up("might", 0.08), up("crit_chance", 0.05))]),
    (36, [passive("ruby_key"), opt(up("stakes", 0.1), **STAKES)]),
    (37, [weapon("zap_beam"), opt(up("spirit", 0.1))]),
    (38, [passive("prospector")]),
    (39, [up("luck", 0.1)]),   # 14 + 44
    (40, [up("reroll", 1, name="A Second Look", mult=2)]),
    (41, [outlaw("fadeaway")]),
    (42, [choice(up("boots", 0.025), up("magnet", 0.2))]),
    (43, [passive("undertakers_shovel")]),
    (44, [up("crit_damage", 0.35), opt(up("boss_stakes", 0.1), **STAKES)]),   # 24 + 40
    (45, [skin("astro", "AST-D")]),   # Astro's second skin (AST-D Splashdown once lane ART installs it: tools/dl/p141/TRAIL/retarget_skins.py)
    (46, [stage("s3")]),
    (47, [weapon("turret_buddy")]),
    (48, [up("plate", 0.06)]),   # 32 + 42
    (49, [passive("hot_sauce")]),
    (50, [outlaw("buck"), opt(up("stakes", 0.1), **STAKES)]),
    (51, [choice(up("shield", 25), up("regen", 0.6))]),
    (52, [passive("slow_burn")]),
    (53, [up("big_game", 0.1)]),
    (54, [up("health", 0.22)]),   # 35 + 50
    (55, [up("banish", 1, name="Not This One", mult=2)]),
    # ---- the last third: a choice about one level in four, three-way and four-way ones, rails meeting
    (56, [passive("fools_gold")]),
    (57, [up("tempo", 0.1), opt(up("boss_stakes", 0.1), **STAKES)]),   # 37 + 51
    (58, [choice(up("crit_chance", 0.05), up("crit_damage", 0.25))]),
    (59, [up("bounty", 0.15)]),
    (60, [weapon("land_mine")]),
    (61, [choice(up("area", 0.1), up("duration", 0.12))]),
    (62, [up("amount", 1, name="Extra Barrel", mult=3, meet=True), opt(up("stakes", 0.1), **STAKES)]),
    (63, [up("shield", 40)]),   # 45 + 58
    (64, [choice(up("might", 0.1), up("crit_chance", 0.05), up("big_game", 0.15))]),
    (65, [passive("ricochet")]),
    (66, [up("regen", 0.6)]),
    (67, [passive("iron_horse"), opt(up("boss_stakes", 0.1), **STAKES)]),
    (68, [choice(up("boots", 0.031), up("evade", 0.05))]),
    (69, [up("skip", 1, name="Pass the Bottle", mult=2, meet=True)]),
    (70, [passive("overkill")]),
    (71, [choice(up("health", 0.14), up("plate", 0.05), up("regen", 0.8))]),
    (72, [up("extra_life", 1, name="Boot Hill Pass", mult=2.5, meet=True)]),
    (73, [up("tonic", 0.15)]),
    (74, [up("might", 0.1)]),
    (75, [up("tempo", 0.06)]),
    (76, [up("area", 0.1)]),
    (77, [choice(up("greed", 0.1), up("luck", 0.1), up("power_drop", 0.2), up("long_buff", 0.2))]),
    (78, [up("evade", 0.05)]),
    (79, [passive("personal_storm")]),
    (80, [up("health", 0.14)]),
    (81, [up("second_wind", 0.15)]),
    (82, [choice(up("might", 0.12), up("tempo", 0.07))]),
    (83, [up("plate", 0.1, name="Iron Hide", mult=2)]),   # pass 140's Iron Hide 0.06 + its 51's 0.04
]

# The items, Cards and skin on the Trail (pass 140), gift type by id: pass 129's eight less Death (thirst) and The
# Ghost (evade), which come from tasks now; plan v2's new unlock nodes less Berserk and the Nuke; The Miner and The Ember.
ITEMS = {
    # kept from pass 129
    "tumbleweed": "weapon", "hornet_nest": "weapon", "turret_buddy": "weapon", "land_mine": "weapon",
    "ricochet": "passive", "overkill": "passive",
    # plan v2 (its TRAIL_UNLOCKS)
    "haste": "passive", "pocket_watch": "passive", "clover": "passive", "powder_keg": "passive", "field_notes": "passive",
    "lightning_in_a_bottle": "passive", "magnet": "passive", "mule_kick": "passive", "assayers_scale": "passive",
    "rocket_pod": "weapon", "jade_key": "passive", "pocket_bible": "passive", "tin_star": "passive", "grindstone": "passive",
    "ruby_key": "passive", "zap_beam": "weapon", "undertakers_shovel": "passive", "hot_sauce": "passive",
    "fools_gold": "passive", "iron_horse": "passive", "personal_storm": "passive",
    # Death's and The Ghost's old slots
    "prospector": "passive", "slow_burn": "passive",
}
SKINS = ["astro:AST-D"]
OUTLAWS = ["calavera", "solenne", "fadeaway", "buck"]   # title order; the Drifter, Ironwood and (pass 140) Astro start open, May comes from a task
STAGE_LEVELS = {"dust": 26, "s3": 46}
# Garry: "make sure not to damage our mix of choice/optional and regular nodes" (pass 129's set, kept in pass 140 and 141)
MIX = {"choice_groups": 12, "choice_nodes": 28, "optional": 10, "meet": 3}
NODE_COUNT = 109
LEVELS = 83
UNLOCK_TYPES = ("outlaw", "skin", "weapon", "passive", "stage", "map", "structure", "powerup", "feature")
NOT_ON_TRAIL = ("structure", "powerup", "feature", "map")   # Garry (pass 140): "Remove Power-ups from the Trails, but keep Stage"
COUNT_TYPES = ("amount", "extra_life", "reroll", "skip", "banish")
# Pass 141: the thin types that left the Trail (one node each in pass 140; "fewer variety"); their upgrade blocks stay in
# the file for the Level Editor
RETIRED_TYPES = ("shot_speed", "care_package", "grip", "loose_coins")
GAP = 5   # never the same upgrade type twice within five levels


def build_nodes():
    """DESIGN as the file's nodes: ids n001.. in file order (level by level, required left to right, optional last),
    keys in the Level Editor's order (trail_model.js NODE_KEYS)."""
    nodes = []
    prev_required = []
    for level, row in DESIGN:
        flat = []
        for e in row:
            if "choice" in e:
                for m in e["choice"]:
                    flat.append(dict(m, kind="choice", group="g%02d" % level))
            elif e.get("optional"):
                flat.append(dict(e, kind="optional"))
            else:
                flat.append(dict(e, kind="node"))
        flat.sort(key=lambda e: e["kind"] == "optional")
        required = []
        for e in flat:
            n = {"id": "n%03d" % (len(nodes) + 1), "level": level, "kind": e["kind"]}
            if e["kind"] == "choice":
                n["group"] = e["group"]
            if e.get("meet"):
                # pass 141: the members of the choice group right below (one lane: the level below holds one thing)
                n["from"] = list(prev_required)
                n["need"] = "any" if len(prev_required) > 1 else "all"
            n["gives"] = dict(e["give"])
            if "price" in e:
                n["price"] = e["price"]
            if "mult" in e:
                n["price_mult"] = e["mult"]
            if "name" in e:
                n["name"] = e["name"]
            nodes.append(n)
            if e["kind"] != "optional":
                required.append(n["id"])
        prev_required = required
    return nodes


# ---------------------------------------------------------------- reading a node list

def is_up(n):
    return n["gives"]["type"] == "upgrade"


def groups_of(nodes):
    """Choice groups in file order: [[node, ...], ...]."""
    out, seen = [], {}
    for n in nodes:
        if n["kind"] == "choice":
            key = (n["level"], n.get("group", ""))
            if key not in seen:
                seen[key] = []
                out.append(seen[key])
            seen[key].append(n)
    return out


def even_pick(nodes, pattern=0):
    """Choices taken evenly: the k-th choice group (file order) takes its member (k + pattern) mod its size. Two
    patterns (0, 1) between them take both sides of every two-way choice. -> the ids taken."""
    return {g[(k + pattern) % len(g)]["id"] for k, g in enumerate(groups_of(nodes))}


def bought_upto(nodes, level, pattern=0):
    """Every required node of levels 1..level, the choices as even_pick takes them; no optional node."""
    pick = even_pick(nodes, pattern)
    return [n["id"] for n in nodes if n["level"] <= level and (n["kind"] == "node" or n["id"] in pick)]


def totals(nodes, ids):
    ids = set(ids)
    t = {}
    for n in nodes:
        if n["id"] in ids and is_up(n):
            t[n["gives"]["upgrade"]] = t.get(n["gives"]["upgrade"], 0.0) + float(n["gives"]["value"])
    return t


def third_of(level, top):
    return 0 if level <= round(top / 3.0) else (1 if level <= round(2 * top / 3.0) else 2)


def node_mix(nodes):
    """The counts pass 140 reports (and keeps the choice / optional / meet part of today)."""
    return {"nodes": len(nodes), "levels": max(n["level"] for n in nodes), "plain": sum(1 for n in nodes if n["kind"] == "node"),
            "choice_nodes": sum(1 for n in nodes if n["kind"] == "choice"), "choice_groups": len(groups_of(nodes)),
            "optional": sum(1 for n in nodes if n["kind"] == "optional"), "meet": sum(1 for n in nodes if len(n.get("from", [])) >= 2),
            "unlocks": sum(1 for n in nodes if n["gives"]["type"] != "upgrade"),
            "upgrades": sum(1 for n in nodes if is_up(n) and n["kind"] != "optional")}


# ---------------------------------------------------------------- the design's own rules

def check_design(nodes):
    probs = []
    top = max(n["level"] for n in nodes)
    if len(nodes) != NODE_COUNT:
        probs.append("%d nodes, not %d" % (len(nodes), NODE_COUNT))
    if top != LEVELS:
        probs.append("%d levels, not %d" % (top, LEVELS))
    by_level = {}
    for n in nodes:
        by_level.setdefault(n["level"], []).append(n)
    for l in range(1, top + 1):
        row = by_level.get(l, [])
        req = [n for n in row if n["kind"] != "optional"]
        # pass 141 (Garry: "The 2 lanes seem redundant"): one thing to buy a level, a plain node or one choice group
        plain = [n for n in req if n["kind"] == "node"]
        groups = {n.get("group", "") for n in req if n["kind"] == "choice"}
        if not req:
            probs.append("level %d has no required node" % l)
        elif not ((len(plain) == 1 and not groups) or (not plain and len(groups) == 1)):
            probs.append("level %d has %d plain nodes and %d choice groups (one thing a level)" % (l, len(plain), len(groups)))
        if len(row) > 4:
            probs.append("level %d has %d nodes (4 at most)" % (l, len(row)))
        if l <= 8 and any(n["kind"] != "node" for n in row):
            probs.append("level %d: the opening is plain nodes only" % l)
        if l <= 3 and not all(is_up(n) for n in row):
            probs.append("level %d: the first three levels are power nodes" % l)
        if len([n for n in row if is_up(n) and n["gives"]["upgrade"] in ("stakes", "boss_stakes")]) > 1:
            probs.append("level %d: two Stakes nodes" % l)
    opening = [n["gives"]["upgrade"] for l in range(1, 9) for n in by_level[l] if is_up(n)]
    if len(set(opening)) != len(opening):
        probs.append("the opening repeats an upgrade type")
    first_choice = min(n["level"] for n in nodes if n["kind"] == "choice")
    if first_choice < 9:
        probs.append("a choice at level %d, before level 9" % first_choice)
    first_opt = min(n["level"] for n in nodes if n["kind"] == "optional")
    if first_opt < 10:
        probs.append("an optional node at level %d" % first_opt)
    # no type twice within five levels
    last = {}
    for n in nodes:
        if is_up(n):
            t = n["gives"]["upgrade"]
            if t in last and n["level"] != last[t] and n["level"] - last[t] < GAP:
                probs.append("%s at levels %d and %d (within %d levels)" % (t, last[t], n["level"], GAP))
            if t in last and n["level"] == last[t]:
                probs.append("%s twice on level %d" % (t, n["level"]))
            last[t] = n["level"]
    # every upgrade type of the file used but the retired ones (pass 141), and those never
    with open(TRAIL, encoding="utf-8") as f:
        types = list(json.load(f)["upgrades"].keys())
    used = {n["gives"]["upgrade"] for n in nodes if is_up(n)}
    for t in types:
        if t not in used and t not in RETIRED_TYPES:
            probs.append("upgrade type %s is never used" % t)
    for t in used:
        if t not in types:
            probs.append("unknown upgrade type %s" % t)
        if t in RETIRED_TYPES:
            probs.append("upgrade type %s left the Trail in pass 141" % t)
    # unlocks: never in a choice, never optional; no power-up, structure, feature or map (Garry, pass 140); the
    # outlaws in title order at twice their level's price; both stages at their levels; the items and the skin at half
    for n in nodes:
        g = n["gives"]
        if g["type"] in UNLOCK_TYPES and n["kind"] != "node":
            probs.append("%s: an unlock that is not a plain node" % n["id"])
        if g["type"] in NOT_ON_TRAIL:
            probs.append("%s: a %s node (not on the Trail since pass 140)" % (n["id"], g["type"]))
        if g["type"] in ("outlaw", "weapon", "passive", "skin"):
            want = OUTLAW_MULT if g["type"] == "outlaw" else UNLOCK_MULT
            if "price" in n or abs(n.get("price_mult", 1.0) - want) > 1e-9:
                probs.append("%s: %s %s is not at x%g of its level's price" % (n["id"], g["type"], g["id"], want))
    got = [n["gives"]["id"] for n in nodes if n["gives"]["type"] == "outlaw"]
    if got != OUTLAWS:
        probs.append("outlaws %s, not %s" % (got, OUTLAWS))
    lv = [n["level"] for n in nodes if n["gives"]["type"] == "outlaw"]
    if lv and not (0.2 * top <= lv[0] <= 0.3 * top and 0.55 * top <= lv[-1] <= 0.65 * top):
        probs.append("outlaws from level %d to %d" % (lv[0], lv[-1]))
    stages = {n["gives"]["stage"]: n["level"] for n in nodes if n["gives"]["type"] == "stage"}
    if stages != STAGE_LEVELS:
        probs.append("stage nodes %s, not %s" % (stages, STAGE_LEVELS))
    items = [n["gives"]["id"] for n in nodes if n["gives"]["type"] in ("weapon", "passive")]
    if sorted(items) != sorted(ITEMS):
        probs.append("item nodes: missing %s, extra %s" % (sorted(set(ITEMS) - set(items)), sorted(set(items) - set(ITEMS))))
    for n in nodes:
        if n["gives"]["type"] in ("weapon", "passive"):
            if ITEMS.get(n["gives"]["id"], "") != n["gives"]["type"]:
                probs.append("%s: %s is not a %s" % (n["id"], n["gives"]["id"], n["gives"]["type"]))
            if not 4 <= n["level"] <= top - 3:
                probs.append("%s: an item at level %d" % (n["id"], n["level"]))
    skins = [n["gives"]["id"] for n in nodes if n["gives"]["type"] == "skin"]
    if skins != SKINS:
        probs.append("skin nodes %s, not %s" % (skins, SKINS))
    # Stakes: four and four, optional, from about level 14
    for t in ("stakes", "boss_stakes"):
        st = [n for n in nodes if is_up(n) and n["gives"]["upgrade"] == t]
        if len(st) != 4 or any(n["kind"] != "optional" or abs(n["gives"]["value"] - 0.1) > 1e-9 for n in st):
            probs.append("%s: four optional nodes of 0.10" % t)
    # the choices: sizes, a 3-way and a 4-way late, more by third
    gs = groups_of(nodes)
    for g in gs:
        if not 2 <= len(g) <= 4:
            probs.append("choice on level %d has %d members" % (g[0]["level"], len(g)))
        if len({n["gives"]["upgrade"] for n in g}) != len(g):
            probs.append("choice on level %d repeats a type" % g[0]["level"])
    per = [0, 0, 0]
    for g in gs:
        per[third_of(g[0]["level"], top)] += 1
    if not (per[0] <= per[1] <= per[2]):
        probs.append("choices by third %s do not rise" % per)
    if not any(len(g) == 3 and third_of(g[0]["level"], top) == 2 for g in gs) or not any(len(g) == 4 and third_of(g[0]["level"], top) == 2 for g in gs):
        probs.append("no 3-way or no 4-way choice in the last third")
    # the mix of choice / optional / rails-meeting nodes, as pass 129 set it (Garry: keep it)
    mix = node_mix(nodes)
    for k, v in MIX.items():
        if mix[k] != v:
            probs.append("mix: %s %d, not %d" % (k, mix[k], v))
    # pass 141: a rails-meeting node names every member of the choice group right below it, `need` any
    for n in nodes:
        if len(n.get("from", [])) >= 2:
            below = [m for m in by_level.get(n["level"] - 1, []) if m["kind"] == "choice"]
            if sorted(n["from"]) != sorted(m["id"] for m in below) or n.get("need") != "any":
                probs.append("%s: rails meet from the choice group right below it, need any" % n["id"])
    # count types: rare, named, with a price multiplier
    for n in nodes:
        if is_up(n) and n["gives"]["upgrade"] in COUNT_TYPES and (not n.get("name") or n.get("price_mult", 1) <= 1):
            probs.append("%s: a count milestone needs a name and a price multiplier" % n["id"])
    return probs


def shape_text(nodes):
    top = max(n["level"] for n in nodes)
    rows = []
    for t in range(3):
        ns = [n for n in nodes if third_of(n["level"], top) == t]
        lv = sorted({n["level"] for n in ns})
        kinds = {k: len([n for n in ns if n["kind"] == k]) for k in ("node", "choice", "optional")}
        cl = len({n["level"] for n in ns if n["kind"] == "choice"})
        unl = len([n for n in ns if n["gives"]["type"] in UNLOCK_TYPES])
        rows.append("| levels %d-%d | %d | %d | %d on %d levels | %d | %d |" % (lv[0], lv[-1], len(ns), kinds["node"], kinds["choice"], cl, kinds["optional"], unl))
    return "\n".join(["| third | nodes | plain | choice | optional | of them unlocks |", "|---|---|---|---|---|---|"] + rows)


# ---------------------------------------------------------------- fit 1: power (the model; the probe is the proof)

# Measured by game/tools/_p129_SETUP_power.gd (tools/dl/p128/TRAILSETUP/power/): a fresh Drifter at level 1 with the
# Revolver and at level 30 with the probe's plain build (five weapons, five cards, no mutation); today's full board in
# its strongest forms (Muscle, Plate, Poultice at rank 7). amount_gain: what +1 projectile adds to the full DPS (the
# lone Revolver doubles, the level-30 build gains a quarter); tempo_eff: the share of an attack-speed gain the build's
# DPS shows (blades and pools do not fire faster).
BASE = {
    "l1": {"max_hp": 100.0, "regen": 0.0, "shield": 0.0, "dr": 0.0, "evade": 0.0, "crit_chance": 0.02, "crit_damage": 2.0, "amount_gain": 1.0, "tempo_eff": 1.0},
    "l30": {"max_hp": 125.97, "regen": 0.9, "shield": 0.0, "dr": 0.05, "evade": 0.0, "crit_chance": 0.31, "crit_damage": 2.0, "amount_gain": 0.252, "tempo_eff": 0.65},
}
BOARD_POWER = {"l1": 2.327, "l30": 2.195}   # the full board over a fresh save (power ratio), from the probe while the board existed (it left in pass 129: this is its last measurement)
TRAIL129_END = {"l1": 4.124, "l30": 2.905}   # pass 129's 100 nodes at their last level, by this model (Garry, pass 140: "110% is fine, bigger is fine too")
TRAIL140_END = {"l1": 4.729, "l30": 3.267}   # pass 140's 130 nodes at their last level, by this model (the probe: x3.28 at level 30); pass 141 keeps at least this
SUSTAIN = 30.0   # HeroPower.SUSTAIN_SECONDS


def power_ratio(t, which="l1"):
    """The model: the power of a hero with the Trail totals `t` over the same hero without them (HeroPower: the square
    root of full DPS x effective HP). The Trail's sums are one effect a stat, so a `mul` multiplies and an `add` adds."""
    b = BASE[which]
    crit0 = 1.0 + b["crit_chance"] * (b["crit_damage"] - 1.0)
    crit1 = 1.0 + min(b["crit_chance"] + t.get("crit_chance", 0.0), 1.0) * (b["crit_damage"] + t.get("crit_damage", 0.0) - 1.0)
    tempo = 1.0 + b["tempo_eff"] * (1.0 / max(1.0 - t.get("tempo", 0.0), 0.05) - 1.0)
    dps = (1.0 + t.get("might", 0.0)) * tempo * crit1 / crit0 * (1.0 + b["amount_gain"] * t.get("amount", 0.0))
    ehp0 = (b["max_hp"] + b["shield"] + SUSTAIN * b["regen"]) / ((1.0 - b["dr"]) * (1.0 - b["evade"]))
    ehp1 = (b["max_hp"] * (1.0 + t.get("health", 0.0)) + b["shield"] + t.get("shield", 0.0) + SUSTAIN * (b["regen"] + t.get("regen", 0.0))) \
        / ((1.0 - min(b["dr"] + t.get("plate", 0.0), 0.8)) * (1.0 - min(b["evade"] + t.get("evade", 0.0), 0.9)))
    return math.sqrt(dps * ehp1 / ehp0)


def power_at(nodes, level, which="l1"):
    """Both even patterns' mean."""
    return sum(power_ratio(totals(nodes, bought_upto(nodes, level, p)), which) for p in (0, 1)) / 2.0


def stage_level(nodes, sid):
    for n in nodes:
        if n["gives"]["type"] == "stage" and n["gives"].get("stage") == sid:
            return n["level"]
    return 0


def power_table(nodes):
    top = max(n["level"] for n in nodes)
    out = ["| Trail level | power, level 1 | share of the board's gain | power, level 30 | share of the board's gain |", "|---|---|---|---|---|"]
    for l in sorted(set(list(range(10, top + 1, 10)) + [stage_level(nodes, "dust"), stage_level(nodes, "s3"), top])):
        cells = []
        for w in ("l1", "l30"):
            p = power_at(nodes, l, w)
            cells += ["%.2f" % p, "%.0f%%" % (100.0 * (p - 1.0) / (BOARD_POWER[w] - 1.0))]
        out.append("| %d | %s |" % (l, " | ".join(cells)))
    out.append("| the full board | %.2f | 100%% | %.2f | 100%% |" % (BOARD_POWER["l1"], BOARD_POWER["l30"]))
    out.append("")
    out.append("The last level over pass 129's last level: x%.3f at level 1, x%.3f at level 30 (Garry: 110%% or more is fine)." % (
        power_at(nodes, top, "l1") / TRAIL129_END["l1"], power_at(nodes, top, "l30") / TRAIL129_END["l30"]))
    out.append("The last level over pass 140's last level: x%.3f at level 1, x%.3f at level 30 (pass 141: at least x1)." % (
        power_at(nodes, top, "l1") / TRAIL140_END["l1"], power_at(nodes, top, "l30") / TRAIL140_END["l30"]))
    return "\n".join(out)


# ---------------------------------------------------------------- fit 2: prices (the journey model, plan v2)

# Pass 140: the price was fitted by the progression plan's journey (docs/progression/progression_plan.html section 4;
# its script tools/dl/p139/PROG/plan.py), carried here so --fit and --tables need nothing outside tools/. A middling
# player's runs: before each run the power of their Trail Level; they play the open stage that pays best and try the
# next once they have a quarter chance at its boss; the clear chance is the stage's demand band times their learning;
# the purse is the stage pay Garry accepted (ECON); after the run they buy the next required nodes while the purse holds.
TARGET_RUNS = 50
STAGE_NAMES = ["Sundown", "Nightfall", "The Dust Bowl", "Blood Moon"]
STAGE_LEN = [430 / 60.0, 600 / 60.0, 780 / 60.0, 960 / 60.0]
# c: coins before the boss = c * minutes^2 (x1, x1.33, x2, x2.85 of pass 139's); boss: a boss kill's purse, chest and
# coins (x1, 1.5, 2, 2); wage: Wages a stage-minute survived; bounty: a poster's pay (x1, x3, x7, x14), half the runs
# finish one. Coins x25 is a cheat and never in here.
ECON = {"c": [10, 40, 60, 100], "boss": [505, 1500, 3000, 6000], "wage": [30, 80, 150, 240], "bounty": [150, 450, 1050, 2100]}
# Pass 141: lane ECON's measured purses (tools/dl/p140/ECON/status.md, the sim's runs of pass 140): the coins and Elite
# purses before the boss came to Sundown 100%, Nightfall 78%, the Dust Bowl 46%, Blood Moon 87% of the plan's (`c`); the
# boss chests, Wages and posters as the plan. The lead since made an Elite's purse follow the stage's coin factor (BALANCING
# 81.LEAD), which lifts the measured ones, so the measured set is the slow end. The price is fitted on it.
MEASURED_SHARE = [1.0, 0.78, 0.46, 0.87]
PURSES = {"plan": ECON, "measured": dict(ECON, c=[c * m for c, m in zip(ECON["c"], MEASURED_SHARE)])}
FIT_ON = "measured"
OVERHEAD = 1.5   # minutes a run spends outside the stage clock (the descent, the boss's intro, the Results, menus)
# The demand band of each stage on HeroPower (level-30 build, x a fresh save): below p0 the boss is out of reach, at p1
# a middling player clears it cmax of the time.
STAGE_BAND = [
    {"p0": 0.97, "p1": 1.20, "cmax": 0.90},
    {"p0": 1.12, "p1": 1.45, "cmax": 0.85},
    {"p0": 1.35, "p1": 1.85, "cmax": 0.80},
    {"p0": 1.70, "p1": 2.55, "cmax": 0.75},
]
START_GOLD = 50   # Save.START_GOLD


def skill(run):
    """A new player's own learning: 0.15 on run 1, 0.56 on run 3, 0.77 on run 5, 0.9 by run 8."""
    return 1.0 - 0.85 * math.exp(-(run - 1) / 3.0)


def outcome(si, power, run, board_open, greed, econ=None):
    """Expected (purse, clear chance, minutes when they fall) for stage si at this power on this run (the plan's
    round-2 Sundown: run 1 falls at about 3:00); `econ` one of PURSES (default the plan's ECON)."""
    ECON = econ or PURSES["plan"]
    b = STAGE_BAND[si]
    x = max(0.0, min(1.0, (power - b["p0"]) / (b["p1"] - b["p0"])))
    sk = skill(run)
    c = x * b["cmax"] * sk
    if si == 0:
        reach = max(0.12, min(0.95, 0.38 + 0.6 * (0.35 + 0.65 * x) * sk))
    else:
        reach = max(0.15, min(0.95, 0.3 + 0.6 * x * sk))
    L = STAGE_LEN[si]
    md = L * reach
    die = ECON["c"][si] * md * md + ECON["wage"][si] * md
    win = ECON["c"][si] * L * L + ECON["boss"][si] + ECON["wage"][si] * L
    purse = (c * win + (1 - c) * die) * (1.0 + greed)
    if board_open:
        purse += 0.5 * ECON["bounty"][si] * (0.5 + 0.5 * x)
    return purse, c, md


def price_of(n, cfg):
    if "price" in n:
        return int(n["price"])
    raw = cfg["base"] + cfg["k"] * math.pow(n["level"], cfg["power"])
    step = cfg["round"]
    v = math.floor(raw / step + 0.5) * step if step > 0 else math.floor(raw + 0.5)
    return max(int(math.floor(v * n.get("price_mult", 1.0) + 0.5)), 0)


def required_order(nodes):
    pick = even_pick(nodes)
    return [n for n in nodes if n["kind"] == "node" or n["id"] in pick]


def simulate(nodes, cfg, runs=400, purses=None):
    """The journey played on purse set `purses` (PURSES' key, default FIT_ON). -> rows, one a run: {run, stage, si, clear,
    minutes, play_min, purse, level, nodes, bought}."""
    econ = PURSES[purses or FIT_ON]
    order = required_order(nodes)
    last_of = {}
    for i, n in enumerate(order):
        last_of[n["level"]] = i
    top = max(n["level"] for n in nodes)
    gates = {1: 0, 2: stage_level(nodes, "dust"), 3: stage_level(nodes, "s3")}
    gold, i, level, greed = float(START_GOLD), 0, 0, 0.0
    cleared = [0.0, 0.0, 0.0, 0.0]
    rows = []
    for run in range(1, runs + 1):
        p30 = power_at(nodes, level, "l30")
        board = run >= 2   # the Bounty Board opens after one finished run
        best = None
        for si in range(4):
            if si > 0 and (cleared[si - 1] < 0.7 or level < gates.get(si, 0)):
                continue
            purse, c, md = outcome(si, p30, run, board, greed, econ)
            if best is None or purse > best[0]:
                best = (purse, si, c, md)
        purse, si, c, md = best
        for sj in range(si + 1, 4):   # a stage never cleared and now in reach: tried once the chance is a quarter
            if cleared[sj - 1] >= 0.7 and level >= gates.get(sj, 0):
                pj, cj, mj = outcome(sj, p30, run, board, greed, econ)
                if cleared[sj] < 0.7 and cj >= 0.25:
                    purse, si, c, md = pj, sj, cj, mj
        cleared[si] += c
        gold += purse
        bought = []
        while i < len(order) and price_of(order[i], cfg) <= gold:
            n = order[i]
            gold -= price_of(n, cfg)
            bought.append(n)
            if is_up(n) and n["gives"]["upgrade"] == "greed":
                greed += float(n["gives"]["value"])
            if last_of[n["level"]] == i:
                level = n["level"]
            i += 1
        L = STAGE_LEN[si]
        rows.append({"run": run, "stage": STAGE_NAMES[si], "si": si, "clear": c, "minutes": md,
                     "play_min": c * L + (1 - c) * md + OVERHEAD, "purse": int(round(purse)), "level": level, "nodes": i,
                     "bought": bought})
        if level >= top:
            break
    return rows


def done_run(rows, level):
    for r in rows:
        if r["level"] >= level:
            return r["run"]
    return None


# Pass 141: the run each unlock came at in pass 140 (its Trail on the plan's purses, tools/dl/p141/TRAIL/work/baseline.py):
# the one-lane Trail keeps them near these while its last level moves to run TARGET_RUNS on the measured purses.
PASS140_RUNS = {"haste": 2, "pocket_watch": 2, "clover": 3, "powder_keg": 3, "field_notes": 5, "lightning_in_a_bottle": 5,
                "tumbleweed": 6, "magnet": 6, "mule_kick": 7, "assayers_scale": 8, "rocket_pod": 8, "calavera": 9, "jade_key": 9,
                "dust": 10, "pocket_bible": 10, "hornet_nest": 11, "tin_star": 11, "solenne": 12, "grindstone": 13, "ruby_key": 14,
                "zap_beam": 15, "prospector": 16, "fadeaway": 18, "undertakers_shovel": 19, "astro:AST-B": 19, "s3": 20,
                "turret_buddy": 21, "hot_sauce": 22, "buck": 23, "slow_burn": 25, "fools_gold": 27, "land_mine": 30, "ricochet": 35,
                "iron_horse": 35, "overkill": 38, "personal_storm": 43}


def unlock_key(n):
    g = n["gives"]
    return str(g.get("id", g.get("stage", "")))


def unlock_runs(rows):
    """The run each unlock is bought in: {thing id: run}."""
    out = {}
    for r in rows:
        for n in r["bought"]:
            if not is_up(n):
                out[unlock_key(n)] = r["run"]
    return out


def fit(nodes, base=20, step=10, say=False):
    """k and power: the last level bought by run TARGET_RUNS on the FIT_ON purses, every unlock near the run it came at
    in pass 140 (PASS140_RUNS; a skin node retargeted keeps its slot's run)."""
    best = None
    top = max(n["level"] for n in nodes)
    slot = {unlock_key(n): unlock_key(n) for n in nodes if not is_up(n)}
    for n in nodes:
        if n["gives"]["type"] == "skin":
            slot[unlock_key(n)] = "astro:AST-B"
    for p in [x / 20.0 for x in range(24, 46)]:
        lo, hi = 0.01, 2000.0
        for _ in range(36):
            mid = (lo + hi) / 2.0
            rows = simulate(nodes, {"base": base, "k": mid, "power": p, "round": step}, runs=TARGET_RUNS + 1)
            if rows[-1]["level"] >= top and rows[-1]["run"] <= TARGET_RUNS:
                lo = mid
            else:
                hi = mid
        cfg = {"base": base, "k": float("%.3g" % lo), "power": p, "round": step}
        rows = simulate(nodes, cfg, runs=TARGET_RUNS + 5)
        got = unlock_runs(rows)
        diffs = [got.get(u, TARGET_RUNS + 5) - PASS140_RUNS[slot[u]] for u in slot]
        err = sum(d * d for d in diffs) / float(len(diffs))
        if done_run(rows, top) != TARGET_RUNS:
            err += 50
        if say:
            print("power %.2f k %-7g -> unlocks off pass 140's runs by %+.1f on average (rms %.1f), the top at run %s" % (
                p, cfg["k"], sum(diffs) / float(len(diffs)), math.sqrt(sum(d * d for d in diffs) / float(len(diffs))), done_run(rows, top)))
        if best is None or err < best[0]:
            best = (err, cfg)
    return best[1]


def price_table(nodes, cfg):
    rows = simulate(nodes, cfg)
    plan_rows = simulate(nodes, cfg, purses="plan")
    pick = even_pick(nodes)
    top = max(n["level"] for n in nodes)
    out = ["| level | nodes | what | price | cumulative (required) | done after run (measured) | stage farmed, purse | done after run (plan) |", "|---|---|---|---|---|---|---|---|"]
    cum, count = 0, 0
    for l in range(1, top + 1):
        row = [n for n in nodes if n["level"] == l]
        count += len(row)
        req = [n for n in row if n["kind"] == "node" or n["id"] in pick]
        cum += sum(price_of(n, cfg) for n in req)
        what = []
        for n in row:
            g = n["gives"]
            w = ("%s %s" % (g["upgrade"], ("%g" % g["value"]))) if is_up(n) else "%s %s" % (g["type"], g.get("id", g.get("stage", "")))
            what.append(("(%s)" % w) if n["kind"] == "optional" else w)
        sep = " / " if any(n["kind"] == "choice" for n in row) else ", "
        prices = sorted({price_of(n, cfg) for n in row if n["kind"] != "optional"})
        opt = [price_of(n, cfg) for n in row if n["kind"] == "optional"]
        ptxt = " / ".join("{:,}".format(p) for p in prices) + ("".join(" ({:,})".format(p) for p in opt))
        r = done_run(rows, l)
        rp = done_run(plan_rows, l)
        out.append("| %d | %d | %s | %s | %s | %s | %s | %s |" % (l, count, sep.join(what), ptxt, "{:,}".format(cum), r if r else "-",
                                                                  ("%s, %s" % (rows[r - 1]["stage"], "{:,}".format(rows[r - 1]["purse"]))) if r else "", rp if rp else "-"))
    return "\n".join(out)


def summary(nodes, cfg):
    top = max(n["level"] for n in nodes)
    pick = even_pick(nodes)
    req = sum(price_of(n, cfg) for n in nodes if n["kind"] == "node" or n["id"] in pick)
    opt = sum(price_of(n, cfg) for n in nodes if n["kind"] == "optional")
    outl = sum(price_of(n, cfg) for n in nodes if n["gives"]["type"] == "outlaw")
    lines = ["price: base %g, k %g, power %g, round %g" % (cfg["base"], cfg["k"], cfg["power"], cfg["round"])]
    for name in ("measured", "plan"):
        rows = simulate(nodes, cfg, purses=name)
        lines.append("on the %s purses:" % name)
        for r in (1, 2, 3, 5, 10, 20, 30, 40, 50):
            if r <= len(rows):
                x = rows[r - 1]
                lines.append("  after run %d: Trail Level %d, %d required nodes bought (that run: %s, purse %s)" % (
                    r, x["level"], x["nodes"], x["stage"], "{:,}".format(x["purse"])))
        lines.append("  the last level after run %s; play time to it %.1f hours" % (done_run(rows, top), sum(x["play_min"] for x in rows) / 60.0))
        got = unlock_runs(rows)
        lines.append("  unlocks (run; pass 140's on the plan's purses): " + ", ".join(
            "%s %d (%s)" % (k, v, PASS140_RUNS.get(k, PASS140_RUNS["astro:AST-B"] if ":" in k else "-")) for k, v in sorted(got.items(), key=lambda kv: kv[1])))
    lines.append("every required node: %s coins (the outlaws %s of it); the %d optional nodes %s more" % (
        "{:,}".format(req), "{:,}".format(outl), len([n for n in nodes if n["kind"] == "optional"]), "{:,}".format(opt)))
    lines.append("power at the last level: x%.3f (level 1), x%.3f (level 30) of a fresh save; x%.3f / x%.3f of pass 140's last level" % (
        power_at(nodes, top, "l1"), power_at(nodes, top, "l30"), power_at(nodes, top, "l1") / TRAIL140_END["l1"], power_at(nodes, top, "l30") / TRAIL140_END["l30"]))
    return "\n".join(lines)


# ---------------------------------------------------------------- the file

def nodes_hash(nodes):
    return hashlib.sha1(json.dumps(nodes, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


def read_trail():
    with open(TRAIL, encoding="utf-8") as f:
        return json.load(f)


def write(nodes, cfg, force):
    import trail_io
    data = read_trail()
    cur = data.get("nodes") or []
    stamp = open(STAMP, encoding="utf-8").read().strip() if os.path.isfile(STAMP) else ""
    if cur and nodes_hash(cur) != stamp and not force:
        print("trail_setup: %s holds %d nodes this script did not write (edited in the Level Editor since); nothing written. "
              "--force overwrites them." % (os.path.relpath(TRAIL, ROOT), len(cur)))
        return 1
    data["price"] = {"base": cfg["base"], "k": cfg["k"], "power": cfg["power"], "round": cfg["round"]}
    data["nodes"] = nodes
    err = trail_io.check(data)
    if err:
        print("trail_setup: the Level Editor's writer refuses the file: %s" % err)
        return 1
    with open(TRAIL, "w", encoding="utf-8", newline="\n") as f:
        f.write(trail_io.dump(data))
    with open(STAMP, "w", encoding="utf-8", newline="\n") as f:
        f.write(nodes_hash(nodes) + "\n")
    print("trail_setup: wrote %d nodes on %d levels and price %s into %s" % (len(nodes), max(n["level"] for n in nodes), json.dumps(data["price"]), os.path.relpath(TRAIL, ROOT)))
    return 0


def probe_plan(nodes, cfg, out_dir):
    """A candidate Trail file and the set-ups the power probe measures: a fresh save, the Trail at every tenth level
    (both even patterns), the two stage levels, and the amount node alone. (Until the Upgrade board left the game, later
    in pass 129, the plan also measured the full board in its strongest forms: BOARD_POWER keeps that last measurement.)"""
    import trail_io
    out_dir = os.path.abspath(out_dir)   # the game reads the candidate by its absolute path
    os.makedirs(out_dir, exist_ok=True)
    data = read_trail()
    data["price"] = dict(cfg)
    data["nodes"] = nodes
    cand = os.path.join(out_dir, "candidate_trail.json")
    with open(cand, "w", encoding="utf-8", newline="\n") as f:
        f.write(trail_io.dump(data))
    top = max(n["level"] for n in nodes)
    configs = [{"name": "fresh"}]
    for l in sorted(set(list(range(10, top + 1, 10)) + [stage_level(nodes, "dust"), stage_level(nodes, "s3"), top])):
        for p in (0, 1):
            configs.append({"name": "trail_L%d_%s" % (l, "ab"[p]), "bought": bought_upto(nodes, l, p)})
    amount = [n["id"] for n in nodes if is_up(n) and n["gives"]["upgrade"] == "amount"]
    configs.append({"name": "amount_only", "bought": amount})
    plan = os.path.join(out_dir, "plan.json")
    with open(plan, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"trail": cand.replace("\\", "/"), "configs": configs}, f, indent=1)
    print("trail_setup: %s and %s (%d set-ups)" % (cand, plan, len(configs)))
    return 0


# the fitted curve (pass 140: the plan's fit, {base 20, k 6.21, power 1.9, round 10}; pass 141: --fit on the one-lane
# Trail and lane ECON's measured purses, the last level after run 50, the unlocks near pass 140's runs; --fit prints the
# search, --write writes this)
PRICE = {"base": 20, "k": 1.16, "power": 2.25, "round": 10}


def main():
    ap = argparse.ArgumentParser(description="the Trail's nodes")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--tables", action="store_true")
    ap.add_argument("--fit", action="store_true")
    ap.add_argument("--probe-plan")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    nodes = build_nodes()
    probs = check_design(nodes)
    for p in probs:
        print("FAULT " + p)
    if a.fit:
        cfg = fit(nodes, PRICE["base"], PRICE["round"], say=True)
        print("best: %s" % json.dumps(cfg))
        print(summary(nodes, cfg))
    if a.tables:
        print(shape_text(nodes))
        print()
        print(json.dumps(node_mix(nodes)))
        print()
        print(power_table(nodes))
        print()
        print(summary(nodes, PRICE))
        print()
        print(price_table(nodes, PRICE))
    if a.probe_plan:
        probe_plan(nodes, PRICE, a.probe_plan)
    if a.write:
        if probs:
            print("trail_setup: the design has faults; nothing written")
            return 1
        return write(nodes, PRICE, a.force)
    if not (a.fit or a.tables or a.probe_plan or a.write):
        print("trail_setup: %d nodes on %d levels, %d faults" % (len(nodes), max(n["level"] for n in nodes), len(probs)))
    return 1 if probs else 0


if __name__ == "__main__":
    sys.exit(main())

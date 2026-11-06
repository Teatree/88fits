#!/usr/bin/env python
"""Pass 129 (lane TRAIL-SETUP): the Trail's first 100 nodes, as readable data, and the two fits behind them.

  python tools/trail_setup.py --check              the design's own rules (counts, shares by third, no type twice
                                                   within five levels, no unlock in a choice, ...); exit 1 on a fault
  python tools/trail_setup.py --tables             the power table (the model below) and the price table (the purse
                                                   model below), as Markdown
  python tools/trail_setup.py --fit                searches `price` (k, power) against the purse model's checkpoints
  python tools/trail_setup.py --probe-plan <dir>   a candidate Trail file + the plan game/tools/_p129_SETUP_power.gd
                                                   measures (the real stat sheet, HeroPower.gd)
  python tools/trail_setup.py --write [--force]    writes `nodes` and `price` into game/content/trail/trail.json through
                                                   the Level Editor's own writer (tools/level_editor/trail_io.dump),
                                                   every other block as it is

--write refuses when the file's nodes are not the ones this script wrote last (tools/trail_setup.stamp holds their
hash): Garry edits the Trail in the Level Editor from now on, and his nodes are never overwritten without --force.

The design is DESIGN below: one row a level. Schema: docs/trail_schema.md. Why each number: BALANCING.md (pass 129).
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

def up(kind, value, **kw):
    """An upgrade node: type and its own amount. kw: name (a milestone's own name), mult (price multiplier),
    price (its own price), meet (it names every required node of the level below in `from`: rails meeting)."""
    return dict(kw, give={"type": "upgrade", "upgrade": kind, "value": value})


def outlaw(cid):
    return {"give": {"type": "outlaw", "id": cid}, "outlaw": cid}


def weapon(wid):
    return {"give": {"type": "weapon", "id": wid}}


def passive(pid):
    return {"give": {"type": "passive", "id": pid}}


def stage(sid):
    return {"give": {"type": "stage", "map": "red_canyon", "stage": sid}}


def choice(*members):
    return {"choice": list(members)}


def opt(node, **kw):
    return dict(node, optional=True, **kw)


# Stakes: an optional node, on for good; the old board's rank (creatures or bosses +10% HP and attack, +4% speed, a
# hidden +5% XP and coins). A challenge, not power: a quarter of the curve's price.
STAKES = dict(mult=0.25)

# level: the nodes on it, left to right (required first, optional after)
DESIGN = [
    # ---- the opening: eight plain nodes, each a different upgrade a new player feels at once
    (1, [up("might", 0.06, price=10)]),
    (2, [up("health", 0.1)]),
    (3, [up("boots", 0.03)]),
    (4, [up("magnet", 0.12)]),
    (5, [up("tempo", 0.04)]),
    (6, [up("study", 0.05)]),
    (7, [up("regen", 0.4)]),
    (8, [up("greed", 0.06)]),
    (9, [outlaw("astro")]),
    (10, [choice(up("area", 0.08), up("tempo", 0.04))]),
    (11, [weapon("tumbleweed")]),
    (12, [up("crit_chance", 0.03), opt(up("grubstake", 25))]),
    (13, [up("plate", 0.04)]),
    (14, [up("luck", 0.06), opt(up("stakes", 0.1), **STAKES)]),
    (15, [up("might", 0.07)]),
    (16, [outlaw("calavera")]),
    (17, [choice(up("health", 0.1), up("evade", 0.05))]),
    (18, [up("shield", 15)]),
    (19, [up("tempo", 0.04)]),
    (20, [stage("dust"), opt(up("boss_stakes", 0.1), **STAKES)]),
    (21, [weapon("hornet_nest")]),
    (22, [up("shot_speed", 0.1)]),
    (23, [outlaw("solenne")]),
    # ---- the middle third: a choice about one level in six
    (24, [up("crit_damage", 0.15)]),
    (25, [choice(up("might", 0.08), up("crit_chance", 0.05))]),
    (26, [up("care_package", 0.002), opt(up("stakes", 0.1), **STAKES)]),
    (27, [up("regen", 0.5), opt(up("spirit", 0.1))]),
    (28, [passive("thirst")]),
    (29, [up("reroll", 1, name="A Second Look", mult=2)]),
    (30, [outlaw("fadeaway")]),
    (31, [choice(up("boots", 0.04), up("magnet", 0.2))]),
    (32, [up("plate", 0.04), opt(up("boss_stakes", 0.1), **STAKES)]),
    (33, [up("might", 0.08)]),
    (34, [weapon("turret_buddy")]),
    (35, [up("health", 0.1)]),
    (36, [stage("s3")]),
    (37, [up("tempo", 0.05)]),
    (38, [outlaw("buck"), opt(up("stakes", 0.1), **STAKES)]),
    (39, [choice(up("shield", 25), up("regen", 0.6))]),
    (40, [up("study", 0.06)]),
    (41, [passive("evade")]),
    (42, [up("big_game", 0.1)]),
    (43, [up("banish", 1, name="Not This One", mult=2)]),
    (44, [up("grip", 0.1), opt(up("boss_stakes", 0.1), **STAKES)]),
    (45, [outlaw("may")]),
    (46, [choice(up("crit_chance", 0.05), up("crit_damage", 0.25))]),
    (47, [up("bounty", 0.15)]),
    # ---- the last third: a choice about one level in four, three-way and four-way ones, rails meeting
    (48, [weapon("land_mine")]),
    (49, [choice(up("area", 0.1), up("duration", 0.12))]),
    (50, [up("health", 0.12), opt(up("stakes", 0.1), **STAKES)]),
    (51, [up("plate", 0.04), up("tempo", 0.05)]),
    (52, [up("extra_life", 1, name="Boot Hill Pass", mult=2.5, meet=True)]),
    (53, [choice(up("might", 0.1), up("crit_chance", 0.05), up("big_game", 0.15))]),
    (54, [passive("ricochet")]),
    (55, [up("regen", 0.6)]),
    (56, [up("loose_coins", 0.003), opt(up("boss_stakes", 0.1), **STAKES)]),
    (57, [choice(up("boots", 0.05), up("evade", 0.05))]),
    (58, [up("shield", 25), up("crit_damage", 0.2)]),
    (59, [up("skip", 1, name="Pass the Bottle", mult=2, meet=True)]),
    (60, [passive("overkill")]),
    (61, [choice(up("health", 0.14), up("plate", 0.05), up("regen", 0.8))]),
    (62, [up("tonic", 0.15)]),
    (63, [up("might", 0.1), up("tempo", 0.06), up("area", 0.1)]),
    (64, [up("amount", 1, name="Extra Barrel", mult=3, meet=True)]),
    (65, [choice(up("greed", 0.1), up("luck", 0.1), up("power_drop", 0.2), up("long_buff", 0.2))]),
    (66, [up("evade", 0.05)]),
    (67, [up("health", 0.14)]),
    (68, [up("second_wind", 0.15)]),
    (69, [choice(up("might", 0.12), up("tempo", 0.07))]),
    (70, [up("plate", 0.06, name="Iron Hide", mult=2)]),
]

# the eight items moved off their unlock quests (the status file and BALANCING say why each)
ITEMS_MOVED = {
    "tumbleweed": ("weapon", "unlock_tumbleweed", "kill 150 Skeletons"),
    "hornet_nest": ("weapon", "unlock_hornet_nest", "kill 40 Armadillos"),
    "evade": ("passive", "unlock_evade", "reach stage 4 in one run"),
    "turret_buddy": ("weapon", "unlock_turret_buddy", "open 10 chests"),
    "thirst": ("passive", "unlock_thirst", "evolve The Lovers (mend)"),
    "land_mine": ("weapon", "unlock_land_mine", "evolve the Salt"),
    "ricochet": ("passive", "unlock_ricochet", "take all three path mutations of the Revolver"),
    "overkill": ("passive", "unlock_overkill", "raise a passive item to Legendary"),
}
OUTLAWS = ["astro", "calavera", "solenne", "fadeaway", "buck", "may"]   # title order; the Drifter and Ironwood stay
UNLOCK_TYPES = ("outlaw", "skin", "weapon", "passive", "stage", "map", "structure", "powerup", "feature")
COUNT_TYPES = ("amount", "extra_life", "reroll", "skip", "banish")
GAP = 5   # never the same upgrade type twice within five levels


def outlaw_price(cid):
    with open(os.path.join(ROOT, "game", "content", "characters", cid, cid + ".json"), encoding="utf-8") as f:
        return int(json.load(f)["price"])


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
                n["from"] = list(prev_required)
                n["need"] = "all"
            n["gives"] = dict(e["give"])
            if "outlaw" in e:
                n["price"] = outlaw_price(e["outlaw"])
            elif "price" in e:
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


# ---------------------------------------------------------------- the design's own rules

def check_design(nodes):
    probs = []
    top = max(n["level"] for n in nodes)
    if len(nodes) != 100:
        probs.append("%d nodes, not 100" % len(nodes))
    if not 66 <= top <= 74:
        probs.append("%d levels, not about 70" % top)
    by_level = {}
    for n in nodes:
        by_level.setdefault(n["level"], []).append(n)
    for l in range(1, top + 1):
        row = by_level.get(l, [])
        if not [n for n in row if n["kind"] != "optional"]:
            probs.append("level %d has no required node" % l)
        if len(row) > 4:
            probs.append("level %d has %d nodes (4 at most)" % (l, len(row)))
        if l <= 8 and (len(row) != 1 or row[0]["kind"] != "node" or not is_up(row[0])):
            probs.append("level %d: the opening is one plain upgrade a level" % l)
        if len([n for n in row if is_up(n) and n["gives"]["upgrade"] in ("stakes", "boss_stakes")]) > 1:
            probs.append("level %d: two Stakes nodes" % l)
    opening = [by_level[l][0]["gives"].get("upgrade") for l in range(1, 9)]
    if len(set(opening)) != 8:
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
    # every upgrade type of the file used
    with open(TRAIL, encoding="utf-8") as f:
        types = list(json.load(f)["upgrades"].keys())
    used = {n["gives"]["upgrade"] for n in nodes if is_up(n)}
    for t in types:
        if t not in used:
            probs.append("upgrade type %s is never used" % t)
    for t in used:
        if t not in types:
            probs.append("unknown upgrade type %s" % t)
    # unlocks: never in a choice, never optional; the outlaws in title order; both stages; the eight items
    for n in nodes:
        if n["gives"]["type"] in UNLOCK_TYPES and n["kind"] != "node":
            probs.append("%s: an unlock that is not a plain node" % n["id"])
    got = [n["gives"]["id"] for n in nodes if n["gives"]["type"] == "outlaw"]
    if got != OUTLAWS:
        probs.append("outlaws %s, not %s" % (got, OUTLAWS))
    lv = [n["level"] for n in nodes if n["gives"]["type"] == "outlaw"]
    if lv and not (lv[0] <= 10 and 40 <= lv[-1] <= 48):
        probs.append("outlaws from level %d to %d" % (lv[0], lv[-1]))
    stages = [n["gives"]["stage"] for n in nodes if n["gives"]["type"] == "stage"]
    if stages != ["dust", "s3"]:
        probs.append("stage nodes %s" % stages)
    items = [n["gives"]["id"] for n in nodes if n["gives"]["type"] in ("weapon", "passive")]
    if sorted(items) != sorted(ITEMS_MOVED):
        probs.append("item nodes %s" % items)
    for n in nodes:
        if n["gives"]["type"] in ("weapon", "passive"):
            if ITEMS_MOVED.get(n["gives"]["id"], ("",))[0] != n["gives"]["type"]:
                probs.append("%s: %s is not a %s" % (n["id"], n["gives"]["id"], n["gives"]["type"]))
            if not 6 <= n["level"] <= 60:
                probs.append("%s: an item at level %d" % (n["id"], n["level"]))
    # Stakes: four and four, optional, from about level 14
    for t in ("stakes", "boss_stakes"):
        st = [n for n in nodes if is_up(n) and n["gives"]["upgrade"] == t]
        if len(st) != 4 or any(n["kind"] != "optional" or abs(n["gives"]["value"] - 0.1) > 1e-9 for n in st):
            probs.append("%s: four optional nodes of 0.10" % t)
    # the choices: sizes, a 3-way and a 4-way late, shares by third
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
    meet = [n for n in nodes if len(n.get("from", [])) >= 2]
    if not 3 <= len(meet) <= 5:
        probs.append("%d nodes where rails meet (3 to 5)" % len(meet))
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


def power_table(nodes):
    top = max(n["level"] for n in nodes)
    out = ["| Trail level | power, level 1 | share of the board's gain | power, level 30 | share of the board's gain |", "|---|---|---|---|---|"]
    for l in sorted(set(list(range(10, top + 1, 10)) + [18, 36, top])):
        cells = []
        for w in ("l1", "l30"):
            p = power_at(nodes, l, w)
            cells += ["%.2f" % p, "%.0f%%" % (100.0 * (p - 1.0) / (BOARD_POWER[w] - 1.0))]
        out.append("| %d | %s |" % (l, " | ".join(cells)))
    out.append("| the full board | %.2f | 100%% | %.2f | 100%% |" % (BOARD_POWER["l1"], BOARD_POWER["l30"]))
    out.append("")
    out.append("Node 100 over the full board: x%.2f at level 1, x%.2f at level 30 (the band is 1.25 to 1.4)." % (
        power_at(nodes, top, "l1") / BOARD_POWER["l1"], power_at(nodes, top, "l30") / BOARD_POWER["l30"]))
    return "\n".join(out)


# ---------------------------------------------------------------- fit 2: prices (the purse model)

# What a run banks, by the stage farmed. `clear`: the purse of a run that beats the boss and leaves; a run that falls
# on the way banks a share of it. Sources: the run sim (tools/dl/p128/TRAILSETUP/sim: Drifter, 6 players a stage,
# --death end: Sundown with no board 14 coins (the bot falls at 2:00), Nightfall with a quarter 41 (1:04), the Dust
# Bowl with half 2,024 (the one clear 5,064), Blood Moon with the full board 7,810 (9,700 to 13,700 at the boss)),
# and, because the bot falls far sooner than a person on the first two stages, the players' own run records
# (analytics/remote, version 0.97 to 1.00, 13 to 15 board ranks: Sundown cleared 963 to 1,344, Nightfall cleared
# 3,724 and 4,352, fallen half-way 1,120 to 1,857; the Dust Bowl 4,739 fallen at the boss).
# open: the Trail level it can be farmed from (the stage before it beaten; the Dust Bowl and Blood Moon also their
# node); share: what a run banks of `clear` when it opens; ready: the Trail level a run clears it (Nightfall with a
# quarter of the board's gain, level 18; the Dust Bowl with three eighths; Blood Moon near the full board's power).
STAGES = [
    {"name": "Sundown", "clear": 1200, "open": 0, "share": 0.25, "ready": 8, "bounty": 150},
    {"name": "Nightfall", "clear": 4000, "open": 8, "share": 0.30, "ready": 18, "bounty": 150},
    {"name": "The Dust Bowl", "clear": 5300, "open": 18, "share": 0.35, "ready": 27, "bounty": 200},
    {"name": "Blood Moon", "clear": 12000, "open": 36, "share": 0.25, "ready": 55, "bounty": 250},
]
LEARN = [0.1, 0.4, 0.7, 0.9]   # the first four runs: a new player's own learning (run 1 banks about 30 coins)
RUNS = 100
CHECKPOINTS = {20: 35, 50: 65}   # nodes on the levels done by that run


def purse(run, level, greed):
    """(coins a run banks, the stage farmed): the best-paying stage open at this Trail level."""
    best, name = 0.0, ""
    for s in STAGES:
        if level < s["open"]:
            continue
        f = min(1.0, (level - s["open"]) / float(max(s["ready"] - s["open"], 1)))
        share = s["share"] + (1.0 - s["share"]) * f
        v = (s["clear"] * (1.0 + greed) + s["bounty"]) * share
        if v > best:
            best, name = v, s["name"]
    if run <= len(LEARN):
        best *= LEARN[run - 1]
    return int(round(best)), name


def price_of(n, cfg):
    if "price" in n:
        return int(n["price"])
    raw = cfg["base"] + cfg["k"] * math.pow(n["level"], cfg["power"])
    step = cfg["round"]
    v = math.floor(raw / step + 0.5) * step if step > 0 else math.floor(raw + 0.5)
    return max(int(math.floor(v * n.get("price_mult", 1.0) + 0.5)), 0)


def simulate(nodes, cfg, runs=400):
    """The purse model played: after every run the player buys the next required nodes in order while the purse
    holds (choices as even_pick takes them, optional nodes never). -> {level: the run it is done}, the stage farmed a
    run, the purse a run."""
    pick = even_pick(nodes)
    order = [n for n in nodes if n["kind"] == "node" or n["id"] in pick]
    top = max(n["level"] for n in nodes)
    last_of = {}
    for i, n in enumerate(order):
        last_of[n["level"]] = i
    done_at, farmed, banked = {}, [], []
    gold, i, level, greed = 0, 0, 0, 0.0
    for run in range(1, runs + 1):
        p, name = purse(run, level, greed)
        gold += p
        farmed.append(name)
        banked.append(p)
        while i < len(order) and price_of(order[i], cfg) <= gold:
            n = order[i]
            gold -= price_of(n, cfg)
            if is_up(n) and n["gives"]["upgrade"] == "greed":
                greed += float(n["gives"]["value"])
            if last_of[n["level"]] == i:
                level = n["level"]
                done_at[level] = run
            i += 1
        if level >= top:
            break
    return done_at, farmed, banked


def nodes_by(nodes, done_at, run):
    lv = max([l for l, r in done_at.items() if r <= run] or [0])
    return len([n for n in nodes if n["level"] <= lv]), lv


def fit(nodes, base=40, step=10, say=False):
    """k and power: every required node by run RUNS, and the checkpoints as near as the curve allows."""
    best = None
    top = max(n["level"] for n in nodes)
    p = 1.5
    while p <= 2.6001:
        lo, hi = 0.01, 200.0
        for _ in range(40):   # the largest k that still finishes by run RUNS
            mid = (lo + hi) / 2.0
            d, _f, _b = simulate(nodes, {"base": base, "k": mid, "power": p, "round": step})
            if d.get(top, 10 ** 9) <= RUNS:
                lo = mid
            else:
                hi = mid
        k = float("%.2g" % lo)
        cfg = {"base": base, "k": k, "power": round(p, 2), "round": step}
        d, _f, _b = simulate(nodes, cfg)
        err = sum((nodes_by(nodes, d, r)[0] - want) ** 2 for r, want in CHECKPOINTS.items()) + (d.get(top, 999) - RUNS) ** 2
        if say:
            print("power %.2f k %-7g -> %s nodes by run 20, %s by run 50, the top at run %s (err %d)" % (
                p, k, nodes_by(nodes, d, 20)[0], nodes_by(nodes, d, 50)[0], d.get(top), err))
        if best is None or err < best[0]:
            best = (err, cfg)
        p += 0.05
    return best[1]


def price_table(nodes, cfg):
    d, farmed, banked = simulate(nodes, cfg)
    pick = even_pick(nodes)
    top = max(n["level"] for n in nodes)
    out = ["| level | nodes | what | price | cumulative (required) | reached at run | stage farmed, purse |", "|---|---|---|---|---|---|---|"]
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
        r = d.get(l)
        out.append("| %d | %d | %s | %s | %s | %s | %s |" % (l, count, sep.join(what), ptxt, "{:,}".format(cum), r if r else "-",
                                                             ("%s, %s" % (farmed[r - 1], "{:,}".format(banked[r - 1]))) if r else ""))
    return "\n".join(out), d, farmed, banked


def summary(nodes, cfg):
    d, farmed, banked = simulate(nodes, cfg)
    top = max(n["level"] for n in nodes)
    pick = even_pick(nodes)
    req = sum(price_of(n, cfg) for n in nodes if n["kind"] == "node" or n["id"] in pick)
    opt = sum(price_of(n, cfg) for n in nodes if n["kind"] == "optional")
    lines = ["price: base %g, k %g, power %g, round %g" % (cfg["base"], cfg["k"], cfg["power"], cfg["round"])]
    for r in (1, 2, 3, 4, 5, 10, 20, 50, 75, 100):
        n, lv = nodes_by(nodes, d, r)
        lines.append("after run %d: Trail Level %d, %d of the 100 nodes on done levels (purse of that run %s, %s)" % (
            r, lv, n, "{:,}".format(banked[r - 1]) if r <= len(banked) else "-", farmed[r - 1] if r <= len(farmed) else "-"))
    lines.append("every required node: %s coins (the outlaws %s of it), done at run %s; the %d optional nodes %s more" % (
        "{:,}".format(req), "{:,}".format(sum(outlaw_price(o) for o in OUTLAWS)), d.get(top), len([n for n in nodes if n["kind"] == "optional"]), "{:,}".format(opt)))
    lines.append("coins banked over the first 100 runs: %s" % "{:,}".format(sum(banked[:100])))
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
    for l in sorted(set(list(range(10, top + 1, 10)) + [18, 36, top])):
        for p in (0, 1):
            configs.append({"name": "trail_L%d_%s" % (l, "ab"[p]), "bought": bought_upto(nodes, l, p)})
    amount = [n["id"] for n in nodes if is_up(n) and n["gives"]["upgrade"] == "amount"]
    configs.append({"name": "amount_only", "bought": amount})
    plan = os.path.join(out_dir, "plan.json")
    with open(plan, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"trail": cand.replace("\\", "/"), "configs": configs}, f, indent=1)
    print("trail_setup: %s and %s (%d set-ups)" % (cand, plan, len(configs)))
    return 0


# the fitted curve (python tools/trail_setup.py --fit prints the search; --write writes this)
PRICE = {"base": 40, "k": 7.2, "power": 1.95, "round": 10}


def main():
    ap = argparse.ArgumentParser(description="the Trail's first 100 nodes")
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
        print(power_table(nodes))
        print()
        print(summary(nodes, PRICE))
        print()
        print(price_table(nodes, PRICE)[0])
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

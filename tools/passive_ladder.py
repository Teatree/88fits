#!/usr/bin/env python3
"""Pass 95 (lane PASSIVES): the passive items' levels redistributed onto the rarity ladder (Garry: "the number of
Upgrades is reduced to the number of upgrades they have left to reach Legendary + Evolved Rarity ... redistribute that
power among fewer upgrades ... I do expect that stats on the 1st level will be higher").

    python tools/passive_ladder.py [--check] [--old tools/dl/p95/PASSIVES/old] [--only cake,beer] [--table out.md]

The rule (PassiveDef.ladder_levels): an item of rarity r has (rungs from r to legendary) + 1 (Evolved) upgrades, so
levels = common 6, uncommon 5, rare 4, epic 3 (legendary 2). Every rung's effects are explicit below (LADDER), one list
an effect: Garry tunes each rung in the Level Editor. The scheme the numbers follow (balancing_PASSIVES.md):
level 1 = 1.2-1.5 x the old level 1 (fatter the rarer), each rung after it about 0.8 of an old step, the Evolved
rung the biggest step (about 1.5 rungs, "not as crazy"); an item that lost rungs (rare 5 -> 4, epic 5 -> 3) tops out at
0.7-0.9 of its old top, one that kept its count (uncommon, the 3-level epics) at about its old top, one that gained a
rung (common 5 -> 6, overkill 3 -> 5, ricochet 4 -> 5, the 3-level rares) a little above it. A capped stat never passes
its cap (the Magnet's 8.5 m, Hot Streak's +100%, chances under 100%). The hand-written card texts that named numbers
are rewritten (TEXT, TRADE).

--check only compares the JSON on disk with the table (exit 1 on a difference); without it the tool writes `levels`,
`max_level`, `text` / `trade` into each item's JSON in place (its key order, indent and line endings kept: the file
is re-dumped only when the dump of the unchanged file equals the file, else it refuses) and prints the table: item,
rarity, old levels and top, new rungs, new top, ratio. Then tools/import_json.gd -- only=passives/<ids> writes the .tres.
"""
import argparse
import json
import os
import sys
from collections import OrderedDict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASSIVES = os.path.join(REPO, "game", "content", "passives")
OLD_DEFAULT = os.path.join(REPO, "tools", "dl", "p95", "PASSIVES", "old")
RARITIES = ["common", "uncommon", "rare", "epic", "legendary"]


def ladder_levels(rarity):
    i = RARITIES.index(rarity) if rarity in RARITIES else 0
    return len(RARITIES) - 1 - i + 2


def rung_name(rarity, level, top):
    if level >= top:
        return "Evolved"
    i = min((RARITIES.index(rarity) if rarity in RARITIES else 0) + level - 1, len(RARITIES) - 1)
    return RARITIES[i].capitalize()


def E(stat, value, op="add", target="player"):
    return OrderedDict([("stat", stat), ("op", op), ("value", value), ("target", target)])


# ---- the table: id -> [level 1 effects, rung 2, ..., Evolved]; the count must equal ladder_levels(rarity)
LADDER = {
    # common: 6 levels (common, uncommon, rare, epic, legendary, Evolved); 5 before
    "barrel_rush": [[E("barrel_speed", 0.3), E("barrel_seconds", 4.0)]] + [[E("barrel_speed", 0.08), E("barrel_seconds", 0.6)]] * 4
                   + [[E("barrel_speed", 0.12), E("barrel_seconds", 0.9)]],
    "beer": [[E("might", 0.15, "mul"), E("max_hp", -0.05, "mul")]] + [[E("might", 0.1, "mul"), E("max_hp", -0.04, "mul")]] * 4
            + [[E("might", 0.14, "mul"), E("max_hp", -0.05, "mul")]],
    "cake": [[E("heal_drop", 0.004)]] + [[E("heal_drop", 0.0025)]] * 4 + [[E("heal_drop", 0.0035)]],
    "cold_snap": [[E("freeze_chance", 0.03)]] + [[E("freeze_chance", 0.015)]] * 4 + [[E("freeze_chance", 0.02)]],
    "pickpocket": [[E("coin_drop", 0.005)]] + [[E("coin_drop", 0.003)]] * 4 + [[E("coin_drop", 0.005)]],
    "quickdraw": [[E("projectile_speed", 0.2, "mul")]] + [[E("projectile_speed", 0.12, "mul")]] * 4 + [[E("projectile_speed", 0.18, "mul")]],
    # uncommon: 5 levels (uncommon, rare, epic, legendary, Evolved); 5 before (Overkill 3, Ricochet 4, Phoenix Feather 1)
    "adrenaline": [[E("adrenaline_speed", 0.0055), E("adrenaline_might", 0.004)]] + [[E("adrenaline_speed", 0.003), E("adrenaline_might", 0.0025)]] * 3
                  + [[E("adrenaline_speed", 0.005), E("adrenaline_might", 0.0035)]],
    "big_game_hunter": [[E("elite_damage", 0.2)]] + [[E("elite_damage", 0.12)]] * 3 + [[E("elite_damage", 0.18)]],
    "counterpunch": [[E("counter_damage", 1.0), E("counter_haste", 0.25), E("counter_speed", 0.2), E("counter_seconds", 2.5)]]
                    + [[E("counter_haste", 0.04), E("counter_speed", 0.025), E("counter_seconds", 0.2)]] * 3
                    + [[E("counter_damage", 0.5), E("counter_haste", 0.06), E("counter_speed", 0.04), E("counter_seconds", 0.3)]],
    "hush_money": [[E("gold_on_hit", 3)]] + [[E("gold_on_hit", 2)]] * 3 + [[E("gold_on_hit", 3)]],
    "kindling": [[E("fire_damage", 0.2, "mul", "all_weapons")]] + [[E("fire_damage", 0.12, "mul", "all_weapons")]] * 3 + [[E("fire_damage", 0.18, "mul", "all_weapons")]],
    "loose_change": [[E("coin_on_hit", 0.32)]] + [[E("coin_on_hit", 0.08)]] * 3 + [[E("coin_on_hit", 0.12)]],
    "overkill": [[E("overkill", 0.4)]] + [[E("overkill", 0.15)]] * 3 + [[E("overkill", 0.25)]],
    "phoenix_feather": [[E("phoenix_revive", 1)], [E("revive_hp", 0.15)], [E("revive_hp", 0.15)], [E("revive_hp", 0.2)], [E("phoenix_revive", 1)]],
    "pocket_watch": [[E("powerup_duration", 0.2), E("powerup_chance", 0.05)], [E("powerup_duration", 0.12)],
                     [E("powerup_duration", 0.12), E("powerup_chance", 0.04)], [E("powerup_duration", 0.12)],
                     [E("powerup_duration", 0.2), E("powerup_chance", 0.05)]],
    "powder_keg": [[E("powder_keg_chance", 0.065)]] + [[E("powder_keg_chance", 0.02)]] * 3 + [[E("powder_keg_chance", 0.03)]],
    "reach": [[E("area", 0.1, "mul")]] + [[E("area", 0.06, "mul")]] * 3 + [[E("area", 0.1, "mul")]],
    "ricochet": [[E("ricochet", 0.25)]] + [[E("ricochet", 0.13)]] * 3 + [[E("ricochet", 0.2)]],
    "siesta": [[E("still_regen", 1.4)]] + [[E("still_regen", 0.8)]] * 3 + [[E("still_regen", 1.2)]],
    "venom": [[E("poison_damage", 0.2, "mul", "all_weapons")]] + [[E("poison_damage", 0.12, "mul", "all_weapons")]] * 3 + [[E("poison_damage", 0.18, "mul", "all_weapons")]],
    "vulture": [[E("crit_heal_chance", 0.06)]] + [[E("crit_heal_chance", 0.03)]] * 3 + [[E("crit_heal_chance", 0.05)]],
    # rare: 4 levels (rare, epic, legendary, Evolved); 5 before (Brimstone Brand and Guillotine 3)
    "brimstone_brand": [[E("brand_chance", 0.2)], [E("brand_chance", 0.1)], [E("brand_chance", 0.1)], [E("brand_chance", 0.15)]],
    "desperado": [[E("desperado", 0.16)], [E("desperado", 0.1)], [E("desperado", 0.1)], [E("desperado", 0.15)]],
    "guillotine": [[E("execute_frac", 0.09)], [E("execute_frac", 0.04)], [E("execute_frac", 0.04)], [E("execute_frac", 0.06)]],
    "heavyweight": [[E("heavyweight", 0.012)], [E("heavyweight", 0.0015)], [E("heavyweight", 0.0015)], [E("heavyweight", 0.0025)]],
    "hot_streak": [[E("kill_might", 0.07)], [E("kill_might", 0.04)], [E("kill_might", 0.04)], [E("kill_might", 0.06)]],
    "skedaddle": [[E("hurt_speed", 0.25), E("hurt_speed_seconds", 2.0)], [E("hurt_speed", 0.03), E("hurt_speed_seconds", 0.3)],
                  [E("hurt_speed", 0.03), E("hurt_speed_seconds", 0.3)], [E("hurt_speed", 0.05), E("hurt_speed_seconds", 0.5)]],
    "steady_hand": [[E("still_might", 0.13)], [E("still_might", 0.04)], [E("still_might", 0.04)], [E("still_might", 0.05)]],
    # epic: 3 levels (epic, legendary, Evolved); 5 before (Gas Mask, the Magnet), 3 before (the rest)
    "gas_mask": [[E("gas_mask_cap", 0.12)], [E("gas_mask_cap", 0.08)], [E("gas_mask_cap", 0.1)]],
    "hot_springs": [[E("max_hp", 26), E("regen", 0.65), E("heal_pulse", 5)], [E("max_hp", 6), E("regen", 0.2)], [E("max_hp", 10), E("regen", 0.35)]],
    "last_stand": [[E("last_stand", 1.3)], [E("last_stand", 0.3)], [E("last_stand", 0.5)]],
    "magnet": [[E("xp_pull_radius", 6.0)], [E("xp_pull_radius", 1.0), E("xp_pull_rate", 0.5)], [E("xp_pull_radius", 1.5), E("xp_pull_rate", 0.5)]],
    "sinners_greed": [[E("greed", 0.4), E("xp_gain", 0.2)], [E("greed", 0.2), E("xp_gain", 0.1)], [E("greed", 0.3), E("xp_gain", 0.15)]],
    "snake_oil": [[E("overheal", 0.25)], [E("overheal", 0.06)], [E("overheal", 0.1)]],
}

# the hand-written card lines that named the old numbers (a new card shows `text` verbatim; the upgrades read the rungs)
TEXT = {
    "barrel_rush": "Smash a barrel to run 30% faster for 4 s. Each rung after: +8% and +0.6 s more; Evolved +12% and +0.9 s.",
    "cold_snap": "A hit may freeze a creature for 1 second: blue, still and harmless. 3% at level 1, 11% once Evolved. Bosses shrug it off.",
    "counterpunch": "After an evade, your next attack deals double damage, and for 2.5 s you attack 25% faster and move 20% faster. Evolved: 2.5 times.",
    "desperado": "The more you are hurt, the harder you hit: +1.6% attack damage for every 10% of health you are missing at level 1 (+16% near death), up to +51% once Evolved.",
    "gas_mask": "1% damage reduction for every poisoned enemy, up to 12% (20% at level 2, 30% once Evolved).",
    "guillotine": "Finishes the job: a creature left under the threshold by any of your hits dies on the spot. 9% of its health at level 1, 23% once Evolved. Bosses are spared.",
    "heavyweight": "+1.2% attack damage for every 10 max HP you have (+0.15% a rung, Evolved +0.25%).",
    "hot_springs": "+26 max HP and +0.65 HP regen a second. Every heal sends out a pulse that hurts enemies within 3 m: 5 damage, +2 for each HP healed, up to 40.",
    "hot_streak": "Kills make you stronger for the rest of the run: +7% attack damage per 1,000 kills (more each rung), up to +100%.",
    "last_stand": "When a hit leaves you under 30% health, time slows for 2 s and you deal 2.3 times the damage (more each rung).",
    "loose_change": "A hit has a 32% chance to knock a coin worth 10 gold out of you (+8% a rung, Evolved +12%). It lands a few steps away: go and get it.",
    "magnet": "Every few seconds, at random, pulls every EXP gem within 6 m to you. Rungs reach farther and pull more often.",
    "phoenix_feather": "Two seconds after you fall, you get back up with the revive's blast, once a run. Each rung raises the health you rise with; Evolved: a second life.",
    "pocket_watch": "Power-ups you pick up last 20% longer, more each rung (+76% once Evolved); at levels 1, 3 and Evolved they also drop more often (+14% in all).",
    "powder_keg": "A kill has a 6.5% chance to blow up (+2% a rung, Evolved +3%): a quarter of its max health to everything within 2.4 m, and a shove. Kills from the blast never blow.",
    "siesta": "Standing still heals you: +1.4 health a second, more each rung.",
    "skedaddle": "After a hit, run 25% faster for 2 s (+3% and +0.3 s a rung, Evolved +5% and +0.5 s).",
    "snake_oil": "Heals can fill your health past full, up to 25% of max HP more, shown pink on your health bar. Regen stops at full.",
    "steady_hand": "The longer you stand still, the harder you hit: +13% attack damage a second (faster each rung), up to +100%. Moving drops it.",
    "vulture": "A critical hit may heal you for 2% of your max health. 6% of crits at level 1, 20% once Evolved.",
}
TRADE = {"beer": "−4 to −5% max HP a level"}


# ---- the sums
def sum_effects(levels, upto):
    """{stat|op|target: total} over levels[0:upto], last level repeated when the list is short (repeat_last_level)."""
    acc = OrderedDict()
    for k in range(upto):
        lv = levels[min(k, len(levels) - 1)] if levels else []
        for e in lv:
            key = (e["stat"], e.get("op", "add"), e.get("target", "player"))
            v = float(e["value"])
            if key not in acc:
                acc[key] = 0.0
            if e.get("op", "add") == "mul":
                acc[key] = (1.0 + acc[key]) * (1.0 + v) - 1.0
            elif e.get("op", "add") == "set":
                acc[key] = v
            else:
                acc[key] += v
    return acc


def fmt(v):
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    s = "%.4f" % v
    return s.rstrip("0").rstrip(".")


def read_json(path):
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-8")
    return json.loads(text, object_pairs_hook=OrderedDict), raw


def dump_like(doc, raw):
    """json.dumps in the file's own style (2 spaces, UTF-8, its line endings and its trailing newline)."""
    s = json.dumps(doc, indent=2, ensure_ascii=False)
    crlf = b"\r\n" in raw
    if crlf:
        s = s.replace("\n", "\r\n")
    if raw.endswith(b"\n"):
        s += "\r\n" if crlf else "\n"
    return s.encode("utf-8")


def table_row(pid, old, new):
    """One line of the table: the rarity, old levels and top, the new rungs, the new top and the ratio per stat."""
    rar = new.get("rarity", "common")
    old_n = int(old.get("max_level", 5))
    old_top = sum_effects(old.get("levels", []), old_n)
    new_n = len(new["levels"])
    new_top = sum_effects(new["levels"], new_n)
    ratios = []
    for key, v in new_top.items():
        o = old_top.get(key)
        if o is not None and abs(o) > 1e-9:
            ratios.append("%s %s -> %s (x%.2f)" % (key[0], fmt(o), fmt(v), v / o))
        else:
            ratios.append("%s new %s" % (key[0], fmt(v)))
    rungs = " | ".join(", ".join("%s %s%s" % (e["stat"], "x" if e.get("op") == "mul" else "+", fmt(float(e["value"]))) for e in lv) for lv in new["levels"])
    return "| %s | %s | %d | %d | %s | %s |" % (pid, rar, old_n, new_n, rungs, "; ".join(ratios))


def main(argv=None):
    ap = argparse.ArgumentParser(description="the passive items onto the rarity ladder (pass 95)")
    ap.add_argument("--check", action="store_true", help="compare the JSON on disk with the table, write nothing")
    ap.add_argument("--old", default=OLD_DEFAULT, help="the folder of the old JSONs (the table's 'before')")
    ap.add_argument("--only", default="", help="item ids, comma-separated")
    ap.add_argument("--table", default="", help="write the table as Markdown here")
    args = ap.parse_args(argv)
    only = [s for s in args.only.split(",") if s] or None
    rows = ["| item | rarity | old levels | new levels | rungs (level 1 | rung 2 | ... | Evolved) | top: old -> new (ratio) |", "|---|---|---|---|---|---|"]
    bad, written, same = [], [], []
    for pid in sorted(LADDER):
        if only and pid not in only:
            continue
        path = os.path.join(PASSIVES, pid, pid + ".json")
        if not os.path.isfile(path):
            bad.append("%s: no JSON" % pid)
            continue
        doc, raw = read_json(path)
        if doc.get("line") or doc.get("evolves_from"):
            bad.append("%s: a line or an evolved form: not on the ladder" % pid)
            continue
        rar = str(doc.get("rarity", "common"))
        want_n = ladder_levels(rar)
        levels = LADDER[pid]
        if len(levels) != want_n:
            bad.append("%s: the table has %d rungs, the ladder of a %s item %d" % (pid, len(levels), rar, want_n))
            continue
        old_path = os.path.join(args.old, pid + ".json")
        old = read_json(old_path)[0] if os.path.isfile(old_path) else doc
        new = OrderedDict(doc)
        new["levels"] = [list(lv) for lv in levels]
        new["max_level"] = want_n
        if pid in TEXT:
            new["text"] = TEXT[pid]
        if pid in TRADE:
            new["trade"] = TRADE[pid]
        rows.append(table_row(pid, old, new))
        if args.check:
            if doc.get("levels") != [[dict(e) for e in lv] for lv in levels] or int(doc.get("max_level", 0)) != want_n \
                    or (pid in TEXT and doc.get("text") != TEXT[pid]) or (pid in TRADE and doc.get("trade") != TRADE[pid]):
                bad.append("%s: the JSON differs from the table" % pid)
            continue
        if dump_like(doc, raw) != raw:
            bad.append("%s: the file is not in json.dumps's layout: edit it by hand" % pid)
            continue
        out = dump_like(new, raw)
        if out == raw:
            same.append(pid)
            continue
        with open(path, "wb") as f:
            f.write(out)
        written.append(pid)
    print("\n".join(rows))
    if args.table:
        with open(args.table, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(rows) + "\n")
    if args.check:
        print("passive_ladder --check: %s" % ("every item matches the table" if not bad else "; ".join(bad)))
    else:
        print("passive_ladder: %d written (%s), %d unchanged%s" % (len(written), ", ".join(written), len(same), ("; " + "; ".join(bad)) if bad else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

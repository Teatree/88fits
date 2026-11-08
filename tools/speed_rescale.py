"""Pass 134 (lane SPEED; Garry, 2026-11-08: "Increase the starting movement speed of all enemies and heroes by 15% but
such that the consequent movement speed increases all adjust in such a way that the max speed remains the same ...
Don't change the camera"): every walk speed x1.15 where it lives, every speed increase shrunk by one exponent a side.

  python tools/speed_rescale.py --check     the plan: every source with its number before / after, the exponents, the
                                            top stacks and the proof in m/s (nothing written); tools/dl/p134/SPEED/plan.json
  python tools/speed_rescale.py --write     applies the plan (small edits in place, every other number kept), then run
                                            import_json.gd
  --top lasting|full                        which stack is "the top" (default lasting, the lead's pick: the Outlaw's
                                            lasting build, The Chariot Risen, the Trail's Boots, the Wolf gifts; full:
                                            every increase that can hold at once at its best, the timed ones included)
  --timed keep|shrink                       the timed boosts (Sprint, War Drum, Adrenaline, Barrel Rush, Skedaddle,
                                            Counterpunch, Jezyk's charge): default keep (they multiply a speed that is
                                            today's at the lasting top, so they land where they did); shrink: by the
                                            same exponent as the rest

The rule (BALANCING 75.SPEED): a side's top stack P_top is the product of every increase at its best (a flat add counted
as its share of the base); every increase's multiplier (1 + m) becomes (1 + m)^a with a = 1 - ln(1.15) / ln(P_top), so
the start is 15% faster and the top lands where it did. A cap that is a multiplier (Endless speed_max) shrinks the same
way; an absolute m/s cap (far_speed.max_speed) stays; slows are not increases and stay. Increases a level adds to one
summed stat (Barrel Rush, Skedaddle, Counterpunch, Adrenaline a stack) are shrunk on their running total, so every level
lands on the rule exactly; the Trail's Boots nodes (one summed effect, choices between them) each on its own.

--write refuses a second time (plan.json "applied": the numbers would shrink again); --force writes anyway.
"""
import argparse
import glob
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")
MAP = os.path.join(CONTENT, "maps", "red_canyon", "red_canyon.json")
TRAIL = os.path.join(CONTENT, "trail", "trail.json")
STATSHEET = os.path.join(GAME, "core", "systems", "StatSheet.gd")
TRAIL_SETUP = os.path.join(HERE, "trail_setup.py")
PLAN = os.path.join(ROOT, "tools", "dl", "p134", "SPEED", "plan.json")
PASSIVE_LADDER = os.path.join(HERE, "passive_ladder.py")
VOCAB = os.path.join(HERE, "level_editor", "vocab.py")

START = 1.15            # Garry's 15%
BASE_DIGITS = 3         # m/s
MULT_DIGITS = 4         # an increase's m
JEZYK_REF_LEVEL = 30    # the level Jezyk's per-level trait is fitted at (it grows without end; the tools' late build)
ADRENALINE_MAX = 20     # Run.ADRENALINE_MAX


# ---------------------------------------------------------------- JSON with the place of every value

def spans(text):
    """{path tuple: (start, end)} of every value in a JSON text (keys as str, list indices as int)."""
    out = {}
    n = len(text)

    def ws(i):
        while i < n and text[i] in " \t\r\n":
            i += 1
        return i

    def string(i):
        j = i + 1
        while text[j] != '"':
            j += 2 if text[j] == "\\" else 1
        return json.loads(text[i:j + 1]), j + 1

    def val(i, path):
        i = ws(i)
        c = text[i]
        start = i
        if c == "{":
            i = ws(i + 1)
            if text[i] == "}":
                out[path] = (start, i + 1)
                return i + 1
            while True:
                i = ws(i)
                k, i = string(i)
                i = ws(i)
                assert text[i] == ":", (path, i)
                i = val(i + 1, path + (k,))
                i = ws(i)
                if text[i] == ",":
                    i += 1
                    continue
                assert text[i] == "}", (path, i)
                out[path] = (start, i + 1)
                return i + 1
        if c == "[":
            i = ws(i + 1)
            if text[i] == "]":
                out[path] = (start, i + 1)
                return i + 1
            k = 0
            while True:
                i = val(i, path + (k,))
                k += 1
                i = ws(i)
                if text[i] == ",":
                    i += 1
                    continue
                assert text[i] == "]", (path, i)
                out[path] = (start, i + 1)
                return i + 1
        if c == '"':
            _, j = string(i)
            out[path] = (start, j)
            return j
        j = i
        while j < n and text[j] not in ",}] \t\r\n":
            j += 1
        out[path] = (start, j)
        return j

    val(0, ())
    return out


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def get(d, path):
    for k in path:
        d = d[k]
    return d


def fmt(x, digits):
    s = ("%." + str(digits) + "f") % x
    s = s.rstrip("0").rstrip(".") if "." in s else s
    return "0" if s in ("-0", "") else s


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


# ---------------------------------------------------------------- the sources

class Plan:
    def __init__(self):
        self.items = []     # every number changed: {side, id, file, path, before, after, note}
        self.json_cache = {}

    def data(self, path):
        if path not in self.json_cache:
            self.json_cache[path] = json.loads(read(path))
        return self.json_cache[path]

    def add(self, side, sid, file, path, before, after, note=""):
        self.items.append({"side": side, "id": sid, "file": rel(file), "path": list(path), "before": before,
                           "after": after, "note": note})


def level_effects(d, stat):
    """[(path, value)] of each level's effect on `stat` in a passive JSON, in level order."""
    out = []
    for li, lv in enumerate(d.get("levels", [])):
        for ei, e in enumerate(lv):
            if isinstance(e, dict) and e.get("stat") == stat:
                out.append((("levels", li, ei, "value"), float(e["value"])))
    return out


def passive(name):
    return os.path.join(CONTENT, "passives", name, name + ".json")


def outlaw_sources(plan):
    """The Outlaw's increases: [{id, label, file, kind, ...}] and their factor at the top (today's numbers)."""
    trail = plan.data(TRAIL)
    srcs = []
    # the lines (Cards): The Chariot a level (each level its own factor), The Chariot Risen in its place at the top
    st = plan.data(passive("stride"))
    srcs.append({"id": "stride", "digits": 3, "label": "The Chariot (stride), each level", "file": passive("stride"), "kind": "mul",
                 "paths": [p for p, _ in level_effects(st, "move_speed")], "top": None, "lasting": False,
                 "why_not_top": "evolves into The Chariot Risen, which takes its place"})
    rr = plan.data(passive("roadrunner"))
    rp = level_effects(rr, "move_speed")
    srcs.append({"id": "roadrunner", "digits": 3, "label": "The Chariot Risen (roadrunner)", "file": passive("roadrunner"), "kind": "mul",
                 "paths": [p for p, _ in rp], "top": 1.0 + rp[0][1], "lasting": True})
    # the Trail's Boots nodes: one summed effect (Trail.effects), each node shrunk on its own (choices between them)
    bp = [(("nodes", i, "gives", "value"), float(nd["gives"]["value"])) for i, nd in enumerate(trail["nodes"])
          if (nd.get("gives") or {}).get("upgrade") == "boots"]
    srcs.append({"id": "trail_boots", "label": "the Trail's Boots nodes (%s)" % ", ".join(
        trail["nodes"][p[1]]["id"] for p, _ in bp), "file": TRAIL, "kind": "mul", "paths": [p for p, _ in bp],
        "top": 1.0 + sum(v for _, v in bp), "lasting": True, "digits": 3})
    # the Sprint power-up
    sp_f = os.path.join(CONTENT, "pickups", "sprint", "sprint.json")
    sp = plan.data(sp_f)
    spi = [i for i, e in enumerate(sp["effects"]) if e.get("stat") == "move_speed"][0]
    sprint_m = float(sp["effects"][spi]["value"])
    srcs.append({"id": "sprint", "timed": True, "digits": 3, "label": "the Sprint power-up", "file": sp_f, "kind": "mul",
                 "paths": [("effects", spi, "value")], "top": 1.0 + sprint_m, "lasting": False})
    # the War Drum: halved while the Sprint runs (params.stack), and the Sprint is in the top
    wd_f = os.path.join(CONTENT, "structures", "war_drum", "war_drum.json")
    wd = plan.data(wd_f)
    wdi = [i for i, e in enumerate(wd["params"]["effects"]) if e.get("stat") == "move_speed"][0]
    wm = float(wd["params"]["effects"][wdi]["value"])
    keep = 1.0
    for s in wd["params"].get("stack", []):
        if s.get("with") == "sprint" and "move_speed" in s.get("stats", []):
            keep = float(s.get("keep", 1.0))
    srcs.append({"id": "war_drum", "timed": True, "digits": 3, "label": "the War Drum's boost (x%g while the Sprint runs)" % keep, "file": wd_f,
                 "kind": "mul", "paths": [("params", "effects", wdi, "value")], "top": 1.0 + keep * wm, "keep": keep,
                 "lasting": False})
    # the Wolf totem gift: every totem of the map gives it at its most, x the Trail's Spirit Guide
    tp_f = os.path.join(CONTENT, "structures", "totem_pole", "totem_pole.json")
    tp = plan.data(tp_f)
    wi = [i for i, b in enumerate(tp["params"]["boons"]) if b.get("stat") == "move_speed"][0]
    wolf = tp["params"]["boons"][wi]
    spirit = sum(float(nd["gives"]["value"]) for nd in trail["nodes"] if (nd.get("gives") or {}).get("upgrade") == "spirit")
    n_tot = int(tp["params"]["per_map"]["max"])
    srcs.append({"id": "totem_wolf", "label": "the Wolf totem gift (%d totems at most, Spirit Guide +%g)" % (n_tot, spirit),
                 "file": tp_f, "kind": "fixed", "base": ("params", "boons", wi), "wolf": wolf, "spirit": spirit, "n": n_tot,
                 "top": (1.0 + float(wolf["max"]) * (1.0 + spirit)) ** n_tot, "lasting": True,
                 "why_fixed": "kept 1..3%: a totem roll is said in whole percents and must read true (pass 76, "
                              "pass76_totem_test), so it stays in the top as it is and the rest shrink round it"})
    # the passive items whose levels add to one speed stat, read as one factor
    for name, stat, stacks, label in [("adrenaline", "adrenaline_speed", ADRENALINE_MAX, "Adrenaline (a stack, x%d)" % ADRENALINE_MAX),
                                      ("barrel_rush", "barrel_speed", 1, "Barrel Rush"),
                                      ("skedaddle", "hurt_speed", 1, "Skedaddle"),
                                      ("counterpunch", "counter_speed", 1, "Counterpunch")]:
        d = plan.data(passive(name))
        le = level_effects(d, stat)
        srcs.append({"id": name, "timed": True, "label": label, "file": passive(name), "kind": "cum", "paths": [p for p, _ in le],
                     "digits": 5 if stacks > 1 else 3,
                     "values": [v for _, v in le], "stacks": stacks, "top": 1.0 + stacks * sum(v for _, v in le),
                     "lasting": False})
    # Jezyk's own (shrunk by the same exponent, outside the top: his trait grows with his level without an end)
    bk_f = os.path.join(CONTENT, "characters", "buck", "buck.json")
    bk = plan.data(bk_f)
    srcs.append({"id": "jezyk_momentum", "timed": True, "digits": 3, "label": "Jeżyk's momentum (Full Tilt's charge, full)", "file": bk_f, "kind": "mul",
                 "paths": [("momentum", "speed_bonus")], "top": None, "lasting": False,
                 "why_not_top": "Jeżyk's alone"})
    tpl = [i for i, e in enumerate(bk.get("trait_per_level", [])) if e.get("stat") == "move_speed" and float(e["value"]) > 0]
    srcs.append({"id": "jezyk_trait", "label": "Jeżyk's trait a level (fitted at level %d)" % JEZYK_REF_LEVEL, "file": bk_f,
                 "kind": "per_level", "paths": [("trait_per_level", i, "value") for i in tpl], "ref": JEZYK_REF_LEVEL,
                 "top": None, "lasting": False, "why_not_top": "Jeżyk's alone, and it has no top (it grows with his level)"})
    return srcs


def creature_sources(plan):
    m = plan.data(MAP)["timeline_data"]
    trail = plan.data(TRAIL)
    srcs = []
    # the stages: Nightfall by speed_per_stage (no speed_mult of its own), the Dust Bowl and the Blood Moon their own
    stage_tops = []
    for k, s in enumerate(m["stage_list"]):
        if "speed_mult" in s:
            srcs.append({"id": "stage_%s" % s["id"], "label": "%s's speed_mult" % s["name"], "file": MAP, "kind": "factor",
                         "paths": [("timeline_data", "stage_list", k, "speed_mult")], "top": None, "lasting": False})
            stage_tops.append(float(s["speed_mult"]))
        elif k > 0:
            stage_tops.append(1.0 + float(m.get("speed_per_stage", 0.0)) * k)
    srcs.append({"id": "speed_per_stage", "label": "speed_per_stage (Nightfall 1 + it)", "file": MAP, "kind": "mul",
                 "paths": [("timeline_data", "speed_per_stage")], "top": None, "lasting": False})
    srcs.append({"id": "stage_top", "label": "the fastest stage", "kind": "none", "top": max(stage_tops), "lasting": False})
    # Endless: its first factor, its cap (a multiplier: shrinks), its growth (reaches the cap after as many waves)
    e = m["endless"]
    srcs.append({"id": "endless", "label": "Endless speed / speed_max / speed_growth", "file": MAP, "kind": "endless",
                 "e": e, "top": float(e["speed_max"]), "lasting": False})
    # the Trail's Stakes: danger_speed is `per` x the Stakes bought; per fitted on every Stakes node of its kind
    for up in ("stakes", "boss_stakes"):
        effs = trail["upgrades"][up]["effects"]
        ei = [i for i, x in enumerate(effs) if x["stat"].endswith("danger_speed")][0]
        per = float(effs[ei]["per"])
        s_top = sum(float(nd["gives"]["value"]) for nd in trail["nodes"] if (nd.get("gives") or {}).get("upgrade") == up)
        srcs.append({"id": "trail_" + up, "label": "the Trail's %s: danger_speed per (all %g bought)" % (up, s_top),
                     "file": TRAIL, "kind": "per", "paths": [("upgrades", up, "effects", ei, "per")], "s_top": s_top,
                     "top": (1.0 + per * s_top) if up == "stakes" else None, "lasting": False,
                     "why_not_top": "a boss's or an Elite's by its kind; the top creature is a regular one in Speedy"})
    # the Speedy elite modifier
    sp_f = os.path.join(CONTENT, "elites", "speedy", "speedy.json")
    sp = plan.data(sp_f)
    si = [i for i, x in enumerate(sp["effects"]) if x.get("stat") == "speed"][0]
    srcs.append({"id": "elite_speedy", "digits": 3, "label": "the Speedy elite modifier", "file": sp_f, "kind": "mul",
                 "paths": [("effects", si, "value")], "top": 1.0 + float(sp["effects"][si]["value"]), "lasting": False})
    # far_speed: the far crowd's catch-up multiplier (its absolute max_speed stays)
    srcs.append({"id": "far_speed", "label": "far_speed.max_mult (max_speed %g m/s kept)" % float(m["far_speed"]["max_speed"]),
                 "file": MAP, "kind": "keep", "top": None, "lasting": False,
                 "why_not_top": "kept as it is: its absolute max_speed binds long before x%g on the top stack (so the far "
                                "top is that cap), and it is the far crowd's catch-up with the Outlaw (pass 128 raised it "
                                "so a fast Jezyk no longer outruns it; selftest BLOB128 pins it)" % float(m["far_speed"]["max_mult"])})
    return srcs


def exponent(p_top):
    return 1.0 - math.log(START) / math.log(p_top)


def shrink(m, a):
    return (1.0 + m) ** a - 1.0


def plan_side(plan, side, srcs, a):
    """Every source's new numbers into plan.items; returns the top factor after (rounded numbers)."""
    top_after = 1.0
    for s in srcs:
        kind = s["kind"]
        new_top = None
        if kind == "mul":
            for p in s["paths"]:
                v = float(get(plan.data(s["file"]), p))
                nv = round(shrink(v, a), s.get("digits", MULT_DIGITS))
                plan.add(side, s["id"], s["file"], p, v, nv)
            if s["top"] is not None:
                if s["id"] == "trail_boots":
                    new_top = 1.0 + sum(float(it["after"]) for it in plan.items if it["id"] == "trail_boots")
                elif s["id"] == "war_drum":
                    new_top = 1.0 + s["keep"] * plan.items[-1]["after"]
                else:
                    new_top = 1.0 + plan.items[-1]["after"]
        elif kind == "factor":
            p = s["paths"][0]
            v = float(get(plan.data(s["file"]), p))
            nv = round(v ** a, MULT_DIGITS)
            plan.add(side, s["id"], s["file"], p, v, nv)
            if s["top"] is not None:
                new_top = nv
        elif kind == "cum":
            n = s["stacks"]
            total = n * sum(s["values"])
            share = shrink(total, a) / total
            got = 0.0
            dg = s.get("digits", MULT_DIGITS + 1)
            for k, (p, v) in enumerate(zip(s["paths"], s["values"])):
                nv = round(v * share, dg)
                if k == len(s["paths"]) - 1:
                    # the Evolved rung takes up the rounding, so the top lands on the rule
                    nv = round(shrink(total, a) / n - got, dg)
                got += nv
                plan.add(side, s["id"], s["file"], p, v, nv, "every rung x%.5f (fitted at the top)" % share)
            s["share"] = share
            new_top = 1.0 + n * got
        elif kind == "keep":
            pass
        elif kind == "fixed":
            new_top = s["top"]
        elif kind == "per_level":
            for p in s["paths"]:
                v = float(get(plan.data(s["file"]), p))
                nv = round(shrink(v * s["ref"], a) / s["ref"], MULT_DIGITS)
                plan.add(side, s["id"], s["file"], p, v, nv, "fitted at level %d" % s["ref"])
        elif kind == "totem":
            w = s["wolf"]
            step = float(w.get("step", 0.0)) or float(w["min"])
            nstep = round(shrink(float(w["max"]), a) * step / float(w["max"]), MULT_DIGITS + 1)
            for k in ("min", "max", "step"):
                if k in w:
                    nv = round(nstep * float(w[k]) / step, MULT_DIGITS + 1)
                    plan.add(side, s["id"], s["file"], s["base"] + (k,), float(w[k]), nv, "the step's own shrink, the range in steps")
            nmax = [it for it in plan.items if it["id"] == "totem_wolf" and it["path"][-1] == "max"][0]["after"]
            new_top = (1.0 + nmax * (1.0 + s["spirit"])) ** s["n"]
        elif kind == "endless":
            e = s["e"]
            sp0, g, mx = float(e["speed"]), float(e["speed_growth"]), float(e["speed_max"])
            waves = (mx / sp0 - 1.0) / g
            nsp0, nmx = round(sp0 ** a, MULT_DIGITS), round(mx ** a, MULT_DIGITS)
            ng = round((nmx / nsp0 - 1.0) / waves, MULT_DIGITS + 1)
            base = ("timeline_data", "endless")
            plan.add(side, "endless", MAP, base + ("speed",), sp0, nsp0)
            plan.add(side, "endless", MAP, base + ("speed_max",), mx, nmx)
            plan.add(side, "endless", MAP, base + ("speed_growth",), g, ng,
                     "the cap after the same %.1f growth steps" % waves)
            new_top = nmx
        elif kind == "per":
            p = s["paths"][0]
            v = float(get(plan.data(s["file"]), p))
            nv = round(shrink(v * s["s_top"], a) / s["s_top"], 3)
            plan.add(side, s["id"], s["file"], p, v, nv, "fitted on all %g of its Stakes" % s["s_top"])
            if s["top"] is not None:
                new_top = 1.0 + nv * s["s_top"]
        elif kind == "none":
            # the fastest stage: its own speed_mult (planned above) or speed_per_stage's
            nv = [it for it in plan.items if it["side"] == side and it["id"].startswith("stage_")]
            new_top = max([float(it["after"]) for it in nv] + [1.0])
        s["top_after"] = new_top
        if new_top is not None and s.get("in_top", True):
            top_after *= new_top
    return top_after


def _spirit(plan):
    trail = plan.data(TRAIL)
    return sum(float(nd["gives"]["value"]) for nd in trail["nodes"] if (nd.get("gives") or {}).get("upgrade") == "spirit")


def plan_bases(plan):
    """Every walk speed where it lives, x1.15."""
    txt = read(STATSHEET)
    mm = re.search(r'"move_speed": ([0-9.]+),', txt)
    v = float(mm.group(1))
    plan.add("base", "outlaw_base", STATSHEET, ["PLAYER_DEFAULTS", "move_speed"], v, round(v * START, BASE_DIGITS))
    for kind in ("enemies", "bosses"):
        for f in sorted(glob.glob(os.path.join(CONTENT, kind, "*", "*.json"))):
            if os.path.basename(f) != os.path.basename(os.path.dirname(f)) + ".json":
                continue
            d = plan.data(f)
            if isinstance(d.get("speed"), (int, float)) and float(d["speed"]) != 0.0:
                plan.add("base", "boss" if kind == "bosses" else "creature", f, ("speed",), float(d["speed"]),
                         round(float(d["speed"]) * START, BASE_DIGITS))
    m = plan.data(MAP)["timeline_data"]
    rows = [(("timeline_data", "roster", i), r) for i, r in enumerate(m.get("roster", []))]
    for k, s in enumerate(m.get("stage_list", [])):
        for j, r in enumerate(((s.get("boss_fight") or {}).get("roster") or [])):
            rows.append((("timeline_data", "stage_list", k, "boss_fight", "roster", j), r))
    for p, r in rows:
        sp = (r.get("stats") or {}).get("speed")
        if isinstance(sp, (int, float)):
            plan.add("base", "row " + str(r.get("id", p[-1])), MAP, p + ("stats", "speed"), float(sp),
                     round(float(sp) * START, BASE_DIGITS), "a row's own walk speed (absolute)")
        elif isinstance(sp, list):
            for q, x in enumerate(sp):
                plan.add("base", "row " + str(r.get("id", p[-1])), MAP, p + ("stats", "speed", q), float(x),
                         round(float(x) * START, BASE_DIGITS), "a row's own walk speed range (absolute)")


def pct(x):
    """A share as the hand-written texts say it (as TextGen does): a whole percent when it is one, else one decimal."""
    v = x * 100.0
    if abs(v - round(v)) < 0.05:
        return "%d%%" % int(round(v))
    return "%.1f%%" % v


# the hand-written texts that name a speed number (the card texts TextGen does not write); each must read as today's
# text with today's numbers, or the plan stops
TEXTS = [
    ("barrel_rush", passive("barrel_rush"), "text",
     "Smash a barrel to run {0} faster for 4 s. Each rung after: +{1} and +0.6 s more; Evolved +{5} and +0.9 s."),
    ("counterpunch", passive("counterpunch"), "text",
     "After an evade, your next attack deals double damage, and for 2.5 s you attack 25% faster and move {0} faster. "
     "Evolved: 2.5 times."),
    ("skedaddle", passive("skedaddle"), "text",
     "After a hit, run {0} faster for 2 s (+{1} and +0.3 s a rung, Evolved +{3} and +0.5 s)."),
    ("jezyk_momentum", os.path.join(CONTENT, "characters", "buck", "buck.json"), "trait_text",
     "Starts 15% slower. While he is not hit his charge climbs over 10 s to +{0} speed, +60% attack damage and +20% "
     "evade chance; a hit that lands knocks off half of it."),
]
# the tools that hold a copy of a changed number (so they never undo it, and their checks agree)
LADDER_STATS = {"adrenaline": "adrenaline_speed", "barrel_rush": "barrel_speed", "counterpunch": "counter_speed",
                "skedaddle": "hurt_speed"}


def plan_copies(plan):
    """The texts, passive_ladder.py's LADDER and TEXT, trail_setup.py's DESIGN Boots and vocab.py's PLAYER_DEFAULTS."""
    def vals(sid, when):
        return [float(it[when]) for it in plan.items if it["id"] == sid]
    for sid, f, key, tpl in TEXTS:
        if not vals(sid, "before"):
            continue
        old = tpl.format(*[pct(v) for v in vals(sid, "before")])
        new = tpl.format(*[pct(v) for v in vals(sid, "after")])
        cur = plan.data(f).get(key)
        assert cur == old, "%s %s reads %r, not %r" % (rel(f), key, cur, old)
        plan.add("text", sid, f, (key,), old, new, "the hand-written text")
        if sid in LADDER_STATS:
            plan.add("copy", sid, PASSIVE_LADDER, ["TEXT", sid], json.dumps(old, ensure_ascii=False),
                     json.dumps(new, ensure_ascii=False), "passive_ladder.py's TEXT")
    for sid, stat in LADDER_STATS.items():
        seen = set()
        for it in [x for x in plan.items if x["id"] == sid and x["side"] == "outlaw"]:
            if it["before"] in seen:
                continue
            seen.add(it["before"])
            plan.add("copy", sid, PASSIVE_LADDER, ["LADDER", sid, stat],
                     'E("%s", %s)' % (stat, fmt(it["before"], 6)), 'E("%s", %s)' % (stat, fmt(it["after"], MULT_DIGITS + 1)),
                     "passive_ladder.py's LADDER")
    for it in [x for x in plan.items if x["id"] == "trail_boots"]:
        plan.add("copy", "trail_boots", TRAIL_SETUP, ["DESIGN", "boots"], 'up("boots", %s)' % fmt(it["before"], 6),
                 'up("boots", %s)' % fmt(it["after"], MULT_DIGITS + 1), "trail_setup.py's DESIGN")
    ob = [x for x in plan.items if x["id"] == "outlaw_base"][0]
    plan.add("copy", "outlaw_base", VOCAB, ["PLAYER_DEFAULTS", "move_speed"], '"move_speed": %s,' % fmt(ob["before"], 6),
             '"move_speed": %s,' % fmt(ob["after"], BASE_DIGITS), "the Level Editor's copy of PLAYER_DEFAULTS")


def build(top_mode, timed="keep"):
    plan = Plan()
    plan_bases(plan)
    o = outlaw_sources(plan)
    c = creature_sources(plan)
    if top_mode == "lasting":
        for s in o:
            if not s.get("lasting"):
                s["in_top"] = False
    if timed == "keep":
        # a timed boost multiplies whatever speed he has: with the lasting top at today's, a boost kept at its number
        # lands where it did (the lead, pass 134), so it is listed and left alone
        for s in o:
            if s.get("timed"):
                s["kind"], s["top"] = "keep", None
                s["why_not_top"] = "a timed boost, kept at its number (it multiplies a speed that is today's at the top)"
    o_top = math.prod(s["top"] for s in o if s["top"] is not None and s.get("in_top", True))
    c_top = math.prod(s["top"] for s in c if s["top"] is not None)
    # an increase kept as it is stays in the top; the others shrink so the whole lands on today's top
    o_fixed = math.prod(s["top"] for s in o if s["kind"] == "fixed" and s.get("in_top", True))
    a_o, a_c = exponent(o_top / o_fixed), exponent(c_top)
    o_after = plan_side(plan, "outlaw", o, a_o)
    c_after = plan_side(plan, "creatures", c, a_c)
    plan_copies(plan)
    return plan, o, c, {"outlaw": {"top_before": o_top, "a": a_o, "top_after": START * o_after},
                        "creatures": {"top_before": c_top, "a": a_c, "top_after": START * c_after}}


def proof(plan, sides):
    """The Outlaw (the Drifter) and a Blue Slime in m/s, at the start and at the top, before / after."""
    m = plan.data(MAP)["timeline_data"]
    pace_o = float(m.get("move_pace", 1.0))
    pace_c = pace_o * float(m.get("creature_speed_mult", 1.0))
    ob = [it for it in plan.items if it["id"] == "outlaw_base"][0]
    sl = [it for it in plan.items if it["file"].endswith("blue_slime.json")][0]
    far_cap = float(m["far_speed"]["max_speed"])
    o, c = sides["outlaw"], sides["creatures"]
    out = {
        "outlaw_start_mps": [ob["before"] * pace_o, ob["after"] * pace_o],
        "outlaw_top_mps": [ob["before"] * pace_o * o["top_before"], ob["after"] * pace_o * o["top_after"] / START],
        "slime_sundown_start_mps": [sl["before"] * pace_c, sl["after"] * pace_c],
    }
    # the slime at Endless's cap after the Blood Moon with every Stakes bought, near the Outlaw (no far boost), then
    # wearing Speedy, then far (max_mult, under the absolute max_speed), before / after
    f = {"before": {}, "after": {}}
    for it in plan.items:
        if it["side"] in ("text", "copy"):
            continue
        for when in f:
            f[when][(it["id"], it["path"][-1])] = float(it[when])
    s_top = sum(float(nd["gives"]["value"]) for nd in plan.data(TRAIL)["nodes"] if (nd.get("gives") or {}).get("upgrade") == "stakes")
    near, speedy, far = [], [], []
    for when, base in (("before", sl["before"]), ("after", sl["after"])):
        g = f[when]
        x = base * pace_c * g[("stage_s3", "speed_mult")] * g[("endless", "speed_max")] * (1 + g[("trail_stakes", "per")] * s_top)
        near.append(x)
        y = x * (1 + g[("elite_speedy", "value")])
        speedy.append(y)
        far.append(min(y * float(m["far_speed"]["max_mult"]), max(far_cap, y)))
    out["slime_endless_cap_stakes_mps"] = near
    out["slime_endless_cap_stakes_speedy_mps"] = speedy
    out["slime_same_far_max_speed_capped_mps"] = far
    return out


# ---------------------------------------------------------------- writing

def apply(items, frm="before", to="after"):
    """Every item's `frm` number in its file replaced by its `to` number (--undo swaps them)."""
    by_file = {}
    for it in items:
        by_file.setdefault(it["file"], []).append(it)
    for f, file_items in list(by_file.items()):
        if file_items[0]["side"] != "copy":
            continue
        del by_file[f]
        path = os.path.join(ROOT, f)
        txt = read(path)
        for it in file_items:
            assert txt.count(it[frm]) >= 1, (f, it[frm])
            txt = txt.replace(it[frm], it[to])
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(txt)
    for f, file_items in by_file.items():
        path = os.path.join(ROOT, f)
        txt = read(path)
        if os.path.normcase(os.path.abspath(path)) == os.path.normcase(os.path.abspath(STATSHEET)):
            it = file_items[0]
            new = re.sub(r'("move_speed": )' + re.escape(fmt(it[frm], 6)) + r',', r'\g<1>' + fmt(it[to], BASE_DIGITS) + ',', txt, count=1)
            assert new != txt, "StatSheet.gd: move_speed %s not found" % it[frm]
            txt = new
        else:
            sp = spans(txt)
            edits = []
            for it in file_items:
                s, e = sp[tuple(it["path"])]
                if it["side"] == "text":
                    assert json.loads(txt[s:e]) == it[frm], (f, it["path"])
                    if frm == "before":
                        it["before_text"] = txt[s:e]
                    new = it["before_text"] if to == "before" else json.dumps(it[to], ensure_ascii=False)
                    edits.append((s, e, new))
                    continue
                old = float(txt[s:e])
                assert abs(old - float(it[frm])) < 1e-9, (f, it["path"], old, it[frm])
                digits = BASE_DIGITS if it["side"] == "base" else MULT_DIGITS + 1
                if frm == "before":
                    it["before_text"] = txt[s:e]
                new = it.get("before_text") if to == "before" and it.get("before_text") else fmt(float(it[to]), digits)
                edits.append((s, e, new))
            for s, e, t in sorted(edits, reverse=True):
                txt = txt[:s] + t + txt[e:]
            json.loads(txt)
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(txt)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--undo", action="store_true", help="puts every number of an applied plan back to its 'before'")
    ap.add_argument("--top", choices=["full", "lasting"], default="lasting")
    ap.add_argument("--timed", choices=["keep", "shrink"], default="keep",
                    help="the timed boosts (Sprint, War Drum, Adrenaline, Barrel Rush, Skedaddle, Counterpunch, Jezyk's charge): kept, or shrunk too")
    args = ap.parse_args()
    old = json.loads(read(PLAN)) if os.path.isfile(PLAN) else {}
    if args.undo:
        if not old.get("applied"):
            print("speed_rescale: nothing applied to undo")
            return 1
        apply(old["items"], "after", "before")
        old["applied"] = False
        with open(PLAN, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(old, fh, indent=1, ensure_ascii=False)
            fh.write("\n")
        print("speed_rescale: %d numbers put back; now import_json.gd" % len(old["items"]))
        return 0
    if old.get("applied") and not args.force:
        print("speed_rescale: already applied (%s); the numbers in the files are the plan's 'after'. --force plans "
              "again from what the files hold now." % rel(PLAN))
        if args.write:
            return 1
        return 0
    plan, o, c, sides = build(args.top, args.timed)
    pr = proof(plan, sides)
    print("top stack (%s)" % args.top)
    for side, srcs in (("outlaw", o), ("creatures", c)):
        sd = sides[side]
        print("\n%s: P_top %.4f -> a = %.5f; the top after %.4f (x%.4f of today's)" % (
            side, sd["top_before"], sd["a"], sd["top_after"], sd["top_after"] / sd["top_before"]))
        for s in srcs:
            if s["top"] is not None:
                inn = s.get("in_top", True)
                print("  %-58s top x%.4f -> x%.4f%s%s" % (s["label"], s["top"], s.get("top_after") or 0.0, "" if inn else "  (not in the top)",
                                                         "  (%s)" % s["why_fixed"] if s["kind"] == "fixed" else ""))
            else:
                print("  %-58s (outside the top: %s)" % (s["label"], s.get("why_not_top", "a stage at a time")))
    print("\nnumbers:")
    for it in plan.items:
        if it["side"] not in ("base", "copy", "text"):
            print("  %-10s %-16s %-60s %s -> %s %s" % (it["side"], it["id"], it["file"] + ":" + ".".join(map(str, it["path"])), fmt(it["before"], 6), fmt(it["after"], 6), it["note"]))
    nb = [it for it in plan.items if it["side"] == "base"]
    print("  bases: %d walk speeds x%g (%s)" % (len(nb), START, ", ".join("%s %s->%s" % (os.path.basename(it["file"]).replace(".json", "") if not it["id"].startswith("row") else it["id"], fmt(it["before"], 6), fmt(it["after"], 6)) for it in nb[:6])) + " ...")
    for it in plan.items:
        if it["side"] == "text":
            print("  text       %-16s %s\n             -> %s" % (it["id"], it["before"], it["after"]))
    print("  copies: " + ", ".join(sorted({"%s (%d)" % (it["file"], sum(1 for x in plan.items if x["file"] == it["file"])) for it in plan.items if it["side"] == "copy"})))
    print("\nproof (m/s, pace included):")
    for k, v in pr.items():
        print("  %-36s before %.3f  after %.3f  (x%.4f)" % (k, v[0], v[1], v[1] / v[0]))
    out = {"pass": 134, "top": args.top, "timed": args.timed, "start": START, "sides": sides, "proof": pr, "items": plan.items,
           "applied": False}
    if args.write:
        apply(plan.items)
        out["applied"] = True
        print("\nwritten: %d changes in %d files; now import_json.gd" % (
            len(plan.items), len({it["file"] for it in plan.items})))
    os.makedirs(os.path.dirname(PLAN), exist_ok=True)
    with open(PLAN, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

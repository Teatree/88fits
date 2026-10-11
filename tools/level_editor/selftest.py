#!/usr/bin/env python3
"""The Level Editor's self-test (pass 54). Standard library only:

    python tools/level_editor/selftest.py

1. The page's maths (tools/level_editor/model.js, run under node) against a Python copy of the game's own formulas
   (game/core/data/WaveTimeline.gd sample_points / curve_mult, WaveDirector._roster_weight, EnemyManager.spawn's health
   and damage): point sampling, the three curve formulas, the old weight -> weight_late slide against the presence
   keyframes the page converts it to (weights <-> weight_late), row ids, one creature's HP and ATK.
2. The server (tools/level_editor/server.py): a creature record's in-play icon, variance and knockback; Save keeping a
   float where the file had one when the rows come back reordered (matched by id); "Set as default look" on a temporary
   copy of a creature (only its `variant` line changes, the file's own line endings and final newline kept, an unpainted
   or unknown code refused). Nothing under game/ is written.

3. Pass 58: a row's HP and ATK fixed from its start (R1: rowNumbers and creatureAt's t0, hand-checked and against the
   Python copy), the estimate's per-source tallies and the Actual HP x / ATK x lanes (average and largest, by hand on a
   small timeline and against the Python copy on Red Canyon), the size and colour range checks and maths (the tint mixed
   in linear light like the billboard shader), the records' strips and blood, the line-level key writer (mixed line
   endings kept) and the blood endpoint on temporary copies (one line changed, bad colours refused, over HTTP too).
   The pass 58 review: a coloured row's special shade against EnemyDef.tint_special_color (and its constants read from
   EnemyDef.gd), the variance special a row reads, the Actual lane's own top, an "Elites every" event's firings, and a
   one-number size list read as the game reads it (a range of one size).

4. Pass 61: snapping (model.js snapTargets / snapDrag / snapGridStep): the cap's points winning over nearer rows, the
   8-pixel range at several zooms, the dragged item never its own target, Alt and the toggle, an edge's lowest time, a bar
   moved by either end, the minutes grid only when nothing else is near, and 500 random drags (a hand-made timeline and
   Red Canyon read from disk) against a Python copy.

Without node the first part is skipped (said so) and the second still runs. Exit code 0 = every check passed.
"""
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import server  # noqa: E402

FAILS = []
PASSES = [0]


def check(cond, what):
    if cond:
        PASSES[0] += 1
    else:
        FAILS.append(what)
        print("FAIL:", what)


# ---------------------------------------------------------------- the game's formulas, in Python


def sample_points(points, t):
    """WaveTimeline.sample_points."""
    prev_t, prev_v, seen = 0.0, 0.0, False
    for p in points:
        if not isinstance(p, list) or len(p) < 2:
            continue
        pt, pv = float(p[0]), float(p[1])
        if not seen:
            if t <= pt:
                return pv
            seen = True
        elif t <= pt:
            return prev_v + (pv - prev_v) * ((t - prev_t) / max(pt - prev_t, 0.001))
        prev_t, prev_v = pt, pv
    return prev_v


def curve_mult(c, t):
    """WaveTimeline.curve_mult."""
    if not isinstance(c, dict) or not c:
        return 1.0
    points = c.get("points", []) if isinstance(c.get("points", []), list) else []
    mode = str(c.get("mode", "points" if points else "formula"))
    if mode == "points":
        return sample_points(points, t) if points else 1.0
    if mode != "formula":
        return 1.0
    f = c.get("formula", {}) if isinstance(c.get("formula", {}), dict) else {}
    a, b, m = float(f.get("a", 0.0977)), float(f.get("b", 1.25)), t / 60.0
    kind = str(f.get("kind", "power"))
    if kind == "linear":
        return 1.0 + a * m
    if kind == "power":
        return max(1.0 + a * m, 0.0) ** b
    if kind == "exponential":
        return max(1.0 + a, 0.0) ** m
    return 1.0


def roster_weight(r, t, late_t):
    """WaveDirector._roster_weight."""
    ws = r.get("weights")
    if isinstance(ws, list) and ws:
        return max(sample_points(ws, t), 0.0)
    w = float(r.get("weight", 1.0))
    if "weight_late" not in r:
        return w
    start = float(r.get("t", 0.0))
    f = min(max((t - start) / max(late_t - start, 1.0), 0.0), 1.0)
    return w + (float(r.get("weight_late", w)) - w) * f


def stage_mult(tl, s, t):
    sm = tl.get("stage_mults", [])
    if not sm:
        return 1.0
    if s < len(sm):
        return float(sm[s])
    last = float(sm[-1])
    run_end = float(tl.get("stage_length", 300)) * int(tl.get("stages", 3))
    into = max(t - run_end, 0.0)
    wm = float(tl.get("endless_wave_mult", 1.0))
    if wm > 1.0:
        return last * wm ** math.floor(into / max(float(tl.get("endless_wave_seconds", 60)), 1.0))
    return last


def hp_time(tl, t):
    return curve_mult(tl["hp_curve"], t) if tl.get("hp_curve") else (1 + float(tl.get("hp_growth", 0.08)) * t / 60) ** float(tl.get("hp_power", 1.2))


def dmg_time(tl, t):
    return curve_mult(tl["damage_curve"], t) if tl.get("damage_curve") else 1.0


def arch_of(c):
    if c.get("archetype") == "boss" or c.get("kind") == "boss":
        return "boss"
    return "elite" if c.get("archetype") == "elite" else "regular"


def row_numbers(tl, c, stats, t0):
    """Pass 58, R1 (WV's "For ED"): a row's HP and ATK fixed from its start t0. hp_time = 1 when the stats have `hp`,
    else the HP curve at t0; Row HP = (stats.hp, else JSON hp x hp_time) x hp_mult; ATK the same; an Elite-archetype
    creature or a boss takes no curve. The multiples are row / JSON."""
    st = stats or {}
    arch = arch_of(c)
    hp_over, dmg_over = st.get("hp") is not None, st.get("damage") is not None
    ht = hp_time(tl, t0) if arch == "regular" and not hp_over else 1.0
    dt = dmg_time(tl, t0) if arch == "regular" and not dmg_over else 1.0
    jh, jd = float(c.get("hp", 0)), float(c.get("damage", 0))
    hp = (float(st["hp"]) if hp_over else jh * ht) * float(st.get("hp_mult", 1.0))
    atk = (float(st["damage"]) if dmg_over else jd * dt) * float(st.get("damage_mult", 1.0))
    return {"arch": arch, "hp": hp, "atk": atk, "hp_time": ht, "dmg_time": dt,
            "hp_mult": hp / jh if jh > 0 else None, "atk_mult": atk / jd if jd > 0 else None}


def fixed_from(tl, t0, t):
    """WaveDirector.source_for after lane WV's fix round: a row's numbers are fixed from its start t0 through the stages;
    in endless wave N (from 1) from the later of t0 and the wave's start, stage_length x stages + (N - 1) x
    endless_wave_seconds (60 when the map has none)."""
    frm = max(numv(t0, 0), 0)
    end = float(tl.get("stage_length", 300)) * max(1, int(tl.get("stages", 3)))
    if not t >= end:
        return frm
    ews = max(float(tl.get("endless_wave_seconds", 60)), 1.0)
    return max(frm, end + math.floor((t - end) / ews) * ews)


def look_of(c, variant):
    """WaveDirector._look_of: "" for the creature's own look (no code, its default, a code it does not have)."""
    v = "" if variant is None else str(variant)
    if not c or v == "" or v == str(c.get("variant") or ""):
        return ""
    return v if any(str(x.get("code")) == v for x in (c.get("variants") or []) if isinstance(x, dict)) else ""


def wave_end_of(w):
    """App.waveEnd: `until`, else the last burst of a counted wave, else never."""
    t = numv(w.get("t"), 0)
    if w.get("until") not in (None, ""):
        return numv(w.get("until"), INF)
    count, burst, every = numv(w.get("count"), 0), max(1, numv(w.get("burst"), 1)), numv(w.get("every"), 0)
    return t + every * math.ceil(count / burst) if count > 0 else INF


def open_source_of(tl, by_id, cid, variant, t, late_t=600):
    """WaveDirector.open_source_of: the heaviest roster row (either channel) open at t with weight above 0 bringing the
    creature in the same look, else the first wave in its window with an alternative that does. (kind, i, k, t0, stats)."""
    c = by_id.get(cid)
    if not c:
        return None
    look = look_of(c, variant)
    best, best_w = None, 0.0
    for i, r in enumerate(tl.get("roster") or []):
        if not is_obj(r) or str(r.get("enemy") or "") != cid or look_of(c, r.get("variant")) != look:
            continue
        start = numv(r.get("t"), 0)
        until = INF if r.get("until") in (None, "") else numv(r.get("until"), INF)
        if not (start <= t < until):
            continue
        w = roster_weight(r, t, late_t)
        if w > best_w:
            best_w, best = w, ("roster", i, 0, max(start, 0), r.get("stats") if is_obj(r.get("stats")) else {})
    if best:
        return best
    for i, w in enumerate(tl.get("waves") or []):
        if not is_obj(w) or not (numv(w.get("t"), 0) <= t < wave_end_of(w)):
            continue
        alts = w.get("alts") if isinstance(w.get("alts"), list) and w.get("alts") else [w]
        for k, a in enumerate(alts):
            if is_obj(a) and str(a.get("enemy") or "") == cid and look_of(c, a.get("variant")) == look:
                return ("wave", i, k, max(numv(w.get("t"), 0), 0), a.get("stats") if is_obj(a.get("stats")) else {})
    return None


def event_numbers(tl, by_id, cid, variant, stats, t, late_t=600):
    """WaveDirector.event_numbers: the curves at t, except that each half (HP, ATK) the event's own stats leave alone is
    the row's (fixed from its start, afresh in endless) while a row or wave brings the creature in the same look; a boss
    or an Elite never joins. (hp, atk, joined, hp_joined, dmg_joined, hp_from, dmg_from)."""
    c = by_id.get(cid)
    st = stats or {}
    at = max(numv(t, 0), 0)
    own = row_numbers(tl, c or {"hp": 0, "damage": 0}, st, at)
    out = {"hp": own["hp"], "atk": own["atk"], "joined": None, "hp_joined": False, "dmg_joined": False, "hp_from": at, "dmg_from": at}
    if not c or own["arch"] != "regular":
        return out
    hp_own, dmg_own = ("hp" in st or "hp_mult" in st), ("damage" in st or "damage_mult" in st)
    if hp_own and dmg_own:
        return out
    src = open_source_of(tl, by_id, cid, variant, at, late_t)
    if not src:
        return out
    frm = fixed_from(tl, src[3], at)
    rn = row_numbers(tl, c, src[4], frm)
    out["joined"] = list(src[:3])
    if not hp_own:
        out.update(hp=rn["hp"], hp_joined=True, hp_from=frm)
    if not dmg_own:
        out.update(atk=rn["atk"], dmg_joined=True, dmg_from=frm)
    return out


def creature_at(tl, c, stats, t, level, t0=None):
    """EnemyManager.spawn's health (regular / Elite archetype / boss) and damage. Pass 58 (R1): a regular creature's
    numbers are its row's, fixed from the row's start t0 (the curves read at t0, an override takes none), times the stage
    at t, the hero level and creature_hp_mult / creature_damage_mult; an Elite or a boss as before (its damage on the live
    curve at t). t0 None = t."""
    st = stats or {}
    s = int(math.floor(t / float(tl.get("stage_length", 300))))
    sm = stage_mult(tl, s, t)
    lv_hp = 1 + float(tl.get("level_hp_per_level", 0)) * max(level - 1, 0)
    lv_dmg = 1 + float(tl.get("level_damage_per_level", 0)) * max(level - 1, 0)
    chm = float(tl.get("creature_hp_mult", 1.0))
    cdm = float(tl.get("creature_damage_mult", 1.0))
    hp = float(st.get("hp", c["hp"])) * float(st.get("hp_mult", 1.0))
    dmg = float(st.get("damage", c["damage"])) * float(st.get("damage_mult", 1.0))
    row = row_numbers(tl, c, st, t if t0 is None else fixed_from(tl, t0, t))
    if arch_of(c) == "boss":
        per = float((st.get("boss") or {}).get("hp_mult_per_stage", (c.get("boss") or {}).get("hp_mult_per_stage", 1.6)))
        hp = hp * per ** s * max(sm, 1.0)
    elif arch_of(c) == "elite":
        per = float((st.get("elite") or {}).get("hp_mult_per_stage", (c.get("elite") or {}).get("hp_mult_per_stage", 1.8)))
        hp = hp * per ** s * max(sm, 1.0) * chm
    else:
        return row["hp"] * sm * lv_hp * chm, row["atk"] * sm * lv_dmg * cdm
    return hp, dmg * sm * lv_dmg * cdm * dmg_time(tl, t)


def actual_sources(tl):
    """model.js actualSources: every roster row and every wave alternative with its creature, stats and start."""
    out = []
    for i, r in enumerate(tl.get("roster") or []):
        if is_obj(r):
            out.append({"key": "roster:%d" % i, "id": str(r.get("enemy") or ""), "stats": r.get("stats") if is_obj(r.get("stats")) else {}, "t0": max(numv(r.get("t"), 0), 0)})
    for i, w in enumerate(tl.get("waves") or []):
        if not is_obj(w):
            continue
        alts = w.get("alts") if isinstance(w.get("alts"), list) else []
        lst = [(a, k) for k, a in enumerate(alts) if is_obj(a)] if alts else [(w, 0)]
        for a, k in lst:
            out.append({"key": "wave:%d:%d" % (i, k), "id": str(a.get("enemy") or ""), "stats": a.get("stats") if is_obj(a.get("stats")) else {}, "t0": max(numv(w.get("t"), 0), 0)})
    return out


def actual_at(tl, by_id, est, t, win=10):
    """model.js actualAt: the sources that spawned in the `win` seconds round t (the estimate's tallies), their
    multiples, and the spawn-weighted average and the largest of the HP and ATK multiples."""
    hi = point_at(est, t + win / 2)
    lo = point_at(est, t - win / 2) if t - win / 2 >= 0 else None
    rows = []
    for s in actual_sources(tl):
        c = by_id.get(s["id"])
        if not c:
            continue
        n = (hi["src"].get(s["key"], 0) if hi else 0) - (lo["src"].get(s["key"], 0) if lo else 0)
        if not n > 1e-9:
            continue
        rn = row_numbers(tl, c, s["stats"], fixed_from(tl, s["t0"], t))
        atk = rn["atk_mult"]
        if atk is not None and rn["arch"] != "regular":
            atk *= dmg_time(tl, t)
        rows.append({"key": s["key"], "n": n, "hp": rn["hp_mult"], "atk": atk})

    def agg(key):
        sw = sv = 0.0
        mx = None
        for r in rows:
            if r[key] is None:
                continue
            sw += r["n"]
            sv += r["n"] * r[key]
            mx = r[key] if mx is None or r[key] > mx else mx
        return {"avg": sv / sw if sw > 0 else None, "max": mx}
    return {"rows": rows, "hp": agg("hp"), "atk": agg("atk")}


# ---------------------------------------------------------------- the spawn estimate, in Python (pass 57)
#
# A line-by-line copy of model.js's spawnEstimate (the "Spawned so far" lane): the same steps in the same order, so the two
# agree to the last bit (only + - * / and comparisons; JavaScript's Math.round is floor(x + 0.5) here, Python's round()
# rounds halves to even). The checks run both on the same timelines and compare every point.

EST_HZ = 20
MAX_BODIES = 320
HAIR = 1e-4
EST_DEF = {"turnover": 0.06, "bossSeconds": 60, "portalSeconds": 30}
TL_SPAWN_DEF = {"cap_start": 100, "cap_per_minute": 10, "cap_max": 250, "hard_cap": 300, "cap_per_stage": 0,
                "boss_cap_frac": 0.3, "portal_cap": 10, "portal_spawn_seconds": 30, "burst_min": 5, "burst_max": 20,
                "spawn_interval": 0.5, "colour_after_kills": 0}
INF = float("inf")


def js_round(x):
    return math.floor(x + 0.5)


def trunc(v):
    return math.ceil(v) if v < 0 else math.floor(v)


def numv(v, d):
    """model.js num(): a number, or `d` for a missing, empty or non-numeric value."""
    if v is None or v == "" or isinstance(v, (dict, list)):
        return d
    try:
        n = float(v)
    except (TypeError, ValueError):
        return d
    return n if math.isfinite(n) else d


def is_obj(x):
    return isinstance(x, dict)


def pick_shares(v, weights=None):
    if v is None or v == "":
        ids = []
    elif isinstance(v, list):
        ids = [str(x) for x in v]
    else:
        ids = [str(v)]
    if not ids:
        return []
    if isinstance(v, list) and isinstance(weights, list) and weights:
        ws = [max(numv(weights[k], 0) if k < len(weights) else 1, 0) for k in range(len(ids))]
        total = 0.0
        for w in ws:
            total += w
        if total > 0:
            return [{"id": i, "share": ws[k] / total} for k, i in enumerate(ids) if ws[k] / total > 0]
    return [{"id": i, "share": 1 / len(ids)} for i in ids]


def elite_count(formats, pack):
    f = formats if is_obj(formats) else {}
    s, p, r = max(numv(f.get("single"), 0), 0), max(numv(f.get("pack"), 0), 0), max(numv(f.get("ring"), 0), 0)
    total = s + p + r
    if not total > 0:
        return 1
    return (s + (p + r) * pack) / total


def burst_once(rows, start):
    out = [0.0] * len(rows)
    W = 0.0
    for x in rows:
        if x["w"] > 0:
            W += x["w"]
    if not W > 0 or not start > 0:
        return out
    mass, rem = 1.0, start
    step = 0
    while step < 64 and mass > 1e-9 and rem > 1e-9:
        cm = cr = 0.0
        for k, x in enumerate(rows):
            if not x["w"] > 0:
                continue
            p = x["w"] / W
            n = 1 if x["single"] else x["pack"]
            fit = rem / x["s"]
            if fit < n:
                n = fit
            if x["room"] < n:
                n = x["room"]
            out[k] += mass * p * n
            left = rem - n * x["s"]
            if left > 1e-9 and n > 1e-9:
                cm += p
                cr += p * left
        if not cm > 0:
            break
        rem = cr / cm
        mass *= cm
        step += 1
    return out


def burst_avg(rows, room, lo, hi):
    acc = [0.0] * len(rows)
    nb = 0
    last_start, last = None, None
    for b in range(lo, hi + 1):
        start = min(b, room)
        if start != last_start:
            last = burst_once(rows, start)
            last_start = start
        for k in range(len(rows)):
            acc[k] += last[k]
        nb += 1
    if nb > 0:
        for k in range(len(rows)):
            acc[k] /= nb
    return acc


def boss_brood(script, cooldown, seconds, pace):
    out = []
    if not isinstance(script, list) or not script:
        return out
    pc = pace if pace > 0 else 1
    t = 2
    k = 0
    while k < 1000 and t < seconds:
        a = script[k % len(script)] if is_obj(script[k % len(script)]) else {}
        name = str("" if a.get("name") is None else a.get("name"))
        wind = numv(a.get("windup"), 1) / pc
        at = t + wind
        busy = wind
        if name == "roll":
            busy += numv(a.get("duration"), 1.2) / pc
        if name in ("rain", "erupt"):
            busy += numv(a.get("count"), 10) * numv(a.get("interval"), 0.3) + numv(a.get("warn"), 0.55) / pc + 0.3
        if at <= seconds:
            if name == "spawn_ring":
                out.append({"t": at, "id": str("coyote" if a.get("enemy") is None else a.get("enemy")), "n": max(trunc(numv(a.get("count"), 10)), 0)})
            elif name == "erupt" and a.get("spawn"):
                out.append({"t": at, "id": str(a["spawn"]), "n": max(trunc(numv(a.get("count"), 10)), 0)})
        t += busy + cooldown
        k += 1
    return out


def stage_length(tl):
    v = numv(tl.get("stage_length"), 300)
    return v or 300


def spawn_estimate(tl, creatures, opts=None):
    """model.js spawnEstimate, step for step."""
    o = opts if is_obj(opts) else {}
    by_id = {}
    if isinstance(creatures, list):
        for c in creatures:
            if c and c.get("id"):
                by_id[c["id"]] = c
    elif is_obj(creatures):
        by_id.update(creatures)

    def g(key):
        return numv(tl.get(key), TL_SPAWN_DEF[key])

    SL = stage_length(tl)
    NST = max(1, numv(tl.get("stages"), 3))
    end = numv(o.get("end"), 0) if o.get("end") is not None else NST * SL + max(120, js_round(SL * 0.35))
    tin = o.get("turnover")
    tv_curve = [[numv(q[0], 0), max(numv(q[1], 0), 0)] for q in tin if isinstance(q, list) and len(q) >= 2] \
        if isinstance(tin, list) and tin and isinstance(tin[0], list) else None
    tv_stages = [max(numv(v, EST_DEF["turnover"]), 0) for v in tin] if tv_curve is None and isinstance(tin, list) and tin else None
    tv_flat = max(numv(None if isinstance(tin, list) else tin, EST_DEF["turnover"]), 0)
    boss_steps = max(1, js_round(min(max(numv(o.get("bossSeconds"), EST_DEF["bossSeconds"]), 0), 1800) * EST_HZ))
    portal_steps = max(1, js_round(min(max(numv(o.get("portalSeconds"), EST_DEF["portalSeconds"]), 0), 1800) * EST_HZ))
    burst_every = max(1, js_round(g("spawn_interval") * EST_HZ))
    b_lo = trunc(g("burst_min"))
    b_hi = max(trunc(g("burst_max")), b_lo)
    hard, cap_max, cap_per_stage = trunc(g("hard_cap")), trunc(g("cap_max")), trunc(g("cap_per_stage"))
    colour_after = trunc(g("colour_after_kills"))
    boss_frac = g("boss_cap_frac")
    portal_cap, portal_spawn = trunc(g("portal_cap")), g("portal_spawn_seconds")
    pw_block = tl.get("portal_wave") if is_obj(tl.get("portal_wave")) else {}
    portal_wave_count = trunc(numv(pw_block.get("count"), 0))
    hell_cap = tl.get("hell_cap") if isinstance(tl.get("hell_cap"), list) else []
    curve = tl.get("cap_curve") if isinstance(tl.get("cap_curve"), list) else []
    late_t = numv(tl.get("weight_late_t"), 600)
    pace = numv(tl.get("move_pace"), 1) if numv(tl.get("move_pace"), 1) > 0 else 1
    ev_list = tl.get("events") if isinstance(tl.get("events"), list) else []

    def_cache = {}

    def def_of(cid, stats):
        st = stats if is_obj(stats) else {}
        key = cid + "|" + json.dumps(st, sort_keys=True)
        if key in def_cache:
            return def_cache[key]
        c = by_id.get(cid)
        d = None
        if c:
            vr = c.get("variance") if is_obj(c.get("variance")) else {}
            vo = st.get("variance") if is_obj(st.get("variance")) else {}
            has_var = len(vr) > 0 or len(vo) > 0
            d = {
                "id": cid,
                "arch": "boss" if c.get("archetype") == "boss" or c.get("kind") == "boss" else "elite" if c.get("archetype") == "elite" else "regular",
                "share": numv(st.get("cap_share"), numv(c.get("cap_share"), 1)),
                "pack": max(trunc(numv(st.get("pack"), numv(c.get("pack_size"), 1))), 1),
                "maxAlive": trunc(numv(st.get("max_alive"), numv(c.get("max_alive"), 0))),
                "canBeElite": bool(st["can_be_elite"]) if st.get("can_be_elite") is not None else c.get("can_be_elite") is not False,
                "eliteWeight": max(numv(st.get("elite_weight"), 1), 0),
                "formats": st.get("elite_formats") if is_obj(st.get("elite_formats")) else {},
                "chance": max(numv(vo.get("special_chance"), numv(vr.get("special_chance"), 0)), 0) if has_var else 0,
            }
            cb = c.get("boss") if is_obj(c.get("boss")) else {}
            sb = st.get("boss") if is_obj(st.get("boss")) else {}
            script = [a for a in cb["script"] if is_obj(a)] if isinstance(cb.get("script"), list) else []
            if is_obj(sb.get("attacks")):
                script = [a for a in script if a.get("name") not in sb["attacks"] or bool(sb["attacks"][a.get("name")])]
            elif isinstance(sb.get("attacks"), list):
                script = [a for a in sb["attacks"] if is_obj(a)]
            cooldown = numv(sb.get("cooldown_between"), numv(cb.get("cooldown_between"), 2))
            rate = numv(st.get("attack_rate_mult"), 1)
            if rate > 0 and rate != 1:
                cooldown /= rate
            d["script"] = script
            d["cooldown"] = cooldown
        def_cache[key] = d
        return d

    roster = []
    for ri, r in enumerate(tl.get("roster") if isinstance(tl.get("roster"), list) else []):
        if not is_obj(r):
            continue
        d = def_of(str("" if r.get("enemy") is None else r.get("enemy")), r.get("stats"))
        if d:
            until = 1e9 if r.get("until") is None or r.get("until") == "" else numv(r.get("until"), 1e9)
            roster.append({"r": r, "d": d, "key": "roster:%d" % ri, "t": numv(r.get("t"), 0), "until": until, "hell": r.get("channel") == "hell",
                           "pack": max(trunc(numv(r.get("pack"), d["pack"])), 1), "single": r.get("pattern") == "single"})

    alive = {}
    sp_live = []
    S = {"k": 0, "play": 0, "stage": 0, "phase": 0, "phase_left": 0, "portal_t": 0.0, "spawn_step": 0, "fight": None,
         "endless": False, "en_next_boss": 0.0, "en_next_elite": 0.0, "en_next_elite_boss": 0.0, "en_boss_i": 0,
         "boss_alive": None, "kills": 0.0, "colour_at": None, "ev_i": 0, "held_retry": 0.0, "sp_left": -1}
    cum, col, mod = {}, {}, {}
    src_cum = {}
    cat = {"reg": 0.0, "col": 0.0, "mod": 0.0, "elite": 0.0, "special": 0.0, "boss": 0.0, "minion": 0.0}
    marks, fights = [], []

    def clock():
        return S["k"] / EST_HZ

    def now():
        return S["k"] / EST_HZ if S["phase"] == 0 else S["k"] / EST_HZ + HAIR

    def turnover_now():
        if tv_curve is not None:
            v = sample_points(tv_curve, clock()) if tv_curve else 0
        elif tv_stages is not None:
            v = tv_stages[min(max(S["stage"], 0), len(tv_stages) - 1)]
        else:
            v = tv_flat
        return min(v, 1)

    def alive_of(cid):
        n = 0.0
        for a in alive.values():
            if a["id"] == cid:
                n += a["n"]
        return n

    def bodies():
        n = 0.0
        for a in alive.values():
            n += a["n"]
        return n + len(sp_live) + (1 if S["boss_alive"] else 0)

    def load_of(ids):
        l = 0.0
        for a in alive.values():
            if a["id"] in ids:
                l += a["n"] * a["share"]
        return l

    def load_all():
        l = 0.0
        for a in alive.values():
            l += a["n"] * a["share"]
        for s in sp_live:
            l += s["share"]
        return l + (S["boss_alive"]["share"] if S["boss_alive"] else 0)

    def total():
        return cat["reg"] + cat["elite"] + cat["special"] + cat["boss"]

    def colour_open():
        return S["kills"] >= colour_after

    def bump(m, cid, n):
        m[cid] = m.get(cid, 0) + n

    def add(d, n, kind):
        if not n > 0 or not d:
            return
        key = d["id"] + "|" + repr(float(d["share"]))
        a = alive.get(key)
        if a:
            a["n"] += n
        else:
            alive[key] = {"id": d["id"], "share": d["share"], "n": n}
        bump(cum, d["id"], n)
        if kind == "elite":
            cat["elite"] += n
            return
        cat["reg"] += n
        if kind == "mod":
            cat["mod"] += n
            bump(mod, d["id"], n)
            return
        if d["arch"] == "regular" and d["chance"] > 0 and colour_open():
            c = n * d["chance"]
            cat["col"] += c
            bump(col, d["id"], c)

    def cap_now():
        t = now()
        base = sample_points(curve, t) if curve else trunc(g("cap_start")) + g("cap_per_minute") * (t / 60)
        cap = min(trunc(base + cap_per_stage * S["stage"]), cap_max)
        if S["phase"] == 1:
            return trunc(cap * boss_frac)
        if S["phase"] == 2:
            if portal_wave_count > 0:
                return 0
            if portal_spawn >= 0 and S["portal_t"] >= portal_spawn:
                return 0
            return cap if portal_cap < 0 else portal_cap
        return cap

    def hell_frac():
        return numv(hell_cap[min(max(S["stage"], 0), len(hell_cap) - 1)], 0) if hell_cap else 0

    def rows_at(tr, hell):
        out = []
        for x in roster:
            if not (tr >= x["t"] and tr < x["until"]):
                continue
            if hell is not None and x["hell"] != hell:
                continue
            out.append(x)
        return out

    def open_rows(rows):
        out = []
        for x in rows:
            room = INF
            if x["d"]["maxAlive"] > 0:
                room = x["d"]["maxAlive"] - alive_of(x["d"]["id"])
                if not room > 1e-9:
                    continue
            out.append({"x": x, "room": room})
        return out

    waves = []
    for wi, w in enumerate(tl.get("waves") if isinstance(tl.get("waves"), list) else []):
        if not is_obj(w):
            continue
        alts = [(a, k) for k, a in enumerate(w.get("alts") if isinstance(w.get("alts"), list) else []) if is_obj(a)]
        lst = alts if alts else [({"chance": 1, "enemy": w.get("enemy"), "pack": w.get("pack"), "stats": w.get("stats")}, 0)]
        s = 0.0
        for a, _k in lst:
            s += max(numv(a.get("chance"), 1), 0)
        branches = []
        for a, k in lst:
            p = ((max(numv(a.get("chance"), 1), 0) / s) if s > 0 else 0) if alts else 1
            d = def_of(str("" if a.get("enemy") is None else a.get("enemy")), a.get("stats"))
            if p > 0:
                branches.append({"p": p, "d": d, "key": "wave:%d:%d" % (wi, k), "spawned": 0, "next": numv(w.get("t"), 0), "done": not d})
        waves.append({"t": numv(w.get("t"), 0), "until": None if w.get("until") is None or w.get("until") == "" else numv(w.get("until"), 0),
                      "count": trunc(numv(w.get("count"), 0)), "burst": max(trunc(numv(w.get("burst"), 5)), 1),
                      "every": numv(w.get("every"), 0), "respect": w.get("respect_cap") is not False,
                      "hell": w.get("channel") == "hell", "elite": str(w["elite"]) if w.get("elite") else "", "branches": branches})

    def hell_ids(rows):
        s = set()
        for x in rows:
            s.add(x["d"]["id"])
        t = clock()
        for w in waves:
            if not w["hell"] or t < w["t"] or (w["until"] is not None and t >= w["until"]):
                continue
            for b in w["branches"]:
                if not b["done"] and b["d"]:
                    s.add(b["d"]["id"])
        return s

    def channel_room(hell):
        cap = cap_now()
        hl = load_of(hell_ids(rows_at(clock(), True)))
        return hell_frac() * cap - hl if hell else cap - (load_all() - hl)

    def tick_waves():
        t = clock()
        for w in waves:
            if t < w["t"]:
                continue
            room = None
            for b in w["branches"]:
                if b["done"]:
                    continue
                if w["until"] is not None and t >= w["until"]:
                    b["done"] = True
                    continue
                if w["count"] > 0 and b["spawned"] >= w["count"]:
                    b["done"] = True
                    continue
                fired = 0
                while t >= b["next"] and fired < 8:
                    fired += 1
                    n = w["burst"]
                    if w["count"] > 0:
                        n = min(n, w["count"] - b["spawned"])
                    n = min(n, math.floor(hard - bodies()))
                    if w["respect"]:
                        if room is None:
                            room = channel_room(w["hell"])
                        n = min(n, max(math.ceil(room / max(b["d"]["share"], 0.05)), 1)) if room > 0 else 0
                    came = n if n > 0 else 0
                    if came > 0:
                        add(b["d"], b["p"] * came, "mod" if w["elite"] and colour_open() else "reg")
                        bump(src_cum, b["key"], b["p"] * came)
                        b["spawned"] += came
                    if w["every"] <= 0:
                        if came > 0:
                            b["done"] = True
                        else:
                            b["next"] = t + burst_every / EST_HZ
                        break
                    b["next"] += w["every"]
                    if w["count"] > 0 and b["spawned"] >= w["count"]:
                        b["done"] = True
                        break
                if not b["done"] and fired >= 8 and t >= b["next"]:
                    b["next"] = t

    held, timers = [], []

    def spawn_elite(enemy, weights, stats, p):
        if not colour_open():
            held.append({"enemy": enemy, "weights": weights, "stats": stats, "p": p})
            return
        st = stats if is_obj(stats) else {}
        n, cid = 0.0, ""
        picks = pick_shares(enemy, weights)
        if not picks:
            cands = [c for c in open_rows(rows_at(clock(), None)) if c["x"]["d"]["canBeElite"] and c["x"]["d"]["eliteWeight"] > 0]
            s = 0.0
            for c in cands:
                s += c["x"]["d"]["eliteWeight"]
            for c in cands:
                d = def_of(c["x"]["d"]["id"], st) if len(st) else c["x"]["d"]
                if not d:
                    continue
                pack = max(trunc(numv(c["x"]["r"].get("pack"), d["pack"])), 1)
                m = p * (c["x"]["d"]["eliteWeight"] / s) * elite_count(d["formats"], pack)
                add(d, m, "mod")
                n += m
                if not cid:
                    cid = d["id"]
        else:
            for pk in picks:
                d = def_of(pk["id"], st)
                if not d:
                    continue
                m = p * pk["share"] * elite_count(d["formats"], d["pack"])
                add(d, m, "mod")
                n += m
                if not cid:
                    cid = d["id"]
        if n > 0:
            marks.append({"t": clock(), "kind": "mod", "id": cid, "n": n})

    def spawn_elite_boss(enemy, weights, stats, p):
        n, cid = 0.0, ""
        for pk in pick_shares(enemy, weights):
            d = def_of(pk["id"], stats)
            if not d:
                continue
            add(d, p * pk["share"], "elite")
            n += p * pk["share"]
            if not cid:
                cid = d["id"]
        if n > 0:
            marks.append({"t": clock(), "kind": "elite", "id": cid, "n": n})

    def start_boss(enemy, weights, stats):
        picks = [pk for pk in pick_shares(enemy, weights) if def_of(pk["id"], stats)]
        if not picks:
            return
        share = 0.0
        for pk in picks:
            d = def_of(pk["id"], stats)
            bump(cum, d["id"], pk["share"])
            share += pk["share"] * d["share"]
        cat["boss"] += 1
        S["boss_alive"] = {"share": share}
        S["phase"], S["phase_left"] = 1, boss_steps
        S["fight"] = {"t": clock(), "boss": picks[0]["id"], "seconds": boss_steps / EST_HZ, "portal": portal_steps / EST_HZ,
                      "before": total() - 1, "spawned": 0, "minions": 0, "brood": []}
        for pk in picks:
            d = def_of(pk["id"], stats)
            for b in boss_brood(d["script"], d["cooldown"], boss_steps / EST_HZ, pace):
                S["fight"]["brood"].append({"step": S["play"] + max(1, js_round(b["t"] * EST_HZ)), "id": b["id"], "n": b["n"] * pk["share"]})
        S["fight"]["brood"].sort(key=lambda b: b["step"])
        marks.append({"t": clock(), "kind": "boss", "id": picks[0]["id"], "n": 1})

    def run_event(ev, p):
        stats = ev.get("stats") if is_obj(ev.get("stats")) else {}
        typ = str("" if ev.get("type") is None else ev.get("type"))
        if typ == "elite":
            spawn_elite(ev.get("enemy"), ev.get("weights"), stats, p)
        elif typ == "elite_every":
            iv = ev.get("interval")
            lo = numv(iv[0], 90) if isinstance(iv, list) and iv else numv(iv, 90)
            hi = numv(iv[-1], 90) if isinstance(iv, list) and iv else lo
            timers.append({"next": clock(), "mean": (lo + hi) / 2, "enemy": ev.get("enemy"), "weights": ev.get("weights"), "stats": stats, "p": p})
        elif typ == "swarm":
            picks = pick_shares(ev.get("enemy"), ev.get("weights"))
            if not picks and o.get("skin"):
                picks = [{"id": str(o["skin"]), "share": 1}]
            n = min(p * max(trunc(numv(ev.get("count"), 40)), 0), max(MAX_BODIES - bodies(), 0))
            cid = ""
            for pk in picks:
                d = def_of(pk["id"], stats)
                if d:
                    add(d, n * pk["share"], "reg")
                    if not cid:
                        cid = d["id"]
            if n > 0 and cid:
                marks.append({"t": clock(), "kind": "swarm", "id": cid, "n": n})
        elif typ == "boss":
            if p >= 0.5:
                start_boss(ev["enemy"] if "enemy" in ev else o.get("boss"), ev.get("weights"), stats)
        elif typ == "elite_boss":
            spawn_elite_boss(ev.get("enemy"), ev.get("weights"), stats, p)

    events = [{"ev": ev, "i": i, "t": max(numv(ev.get("t"), 0), 0) if is_obj(ev) else 0} for i, ev in enumerate(ev_list)]
    events = [e for e in events if is_obj(e["ev"]) and numv(e["ev"].get("chance"), 1) > 0]
    events.sort(key=lambda e: (e["t"], e["i"]))
    boss_ids = [ev["enemy"] for ev in ev_list if is_obj(ev) and ev.get("type") == "boss" and isinstance(ev.get("enemy"), str) and ev["enemy"] in by_id]
    last_elite_boss = None
    for ev in ev_list:
        if is_obj(ev) and ev.get("type") == "elite_boss":
            last_elite_boss = ev

    def process_events():
        t = clock()
        while S["ev_i"] < len(events):
            e = events[S["ev_i"]]
            if e["t"] > t:
                break
            S["ev_i"] += 1
            run_event(e["ev"], min(max(numv(e["ev"].get("chance"), 1), 0), 1))
            if S["phase"] != 0:
                return
        for tm in timers:
            if t >= tm["next"]:
                if not colour_open():
                    tm["next"] = t + 1
                    continue
                tm["next"] = t + tm["mean"]
                spawn_elite(tm["enemy"], tm["weights"], tm["stats"], tm["p"])
        if held and t >= S["held_retry"]:
            S["held_retry"] = t + 1
            if colour_open():
                h = held.pop(0)
                spawn_elite(h["enemy"], h["weights"], h["stats"], h["p"])
        if S["endless"]:
            if t >= S["en_next_elite"]:
                if colour_open():
                    S["en_next_elite"] = t + SL * 0.15
                    spawn_elite("", None, {}, 1)
                else:
                    S["en_next_elite"] = t + 1
            if t >= S["en_next_boss"] and o.get("boss"):
                S["en_next_boss"] = t + SL
                S["en_next_elite_boss"] = t + SL * 0.5
                cid = boss_ids[S["en_boss_i"] % len(boss_ids)] if boss_ids else str(o["boss"])
                S["en_boss_i"] += 1
                run_event({"type": "boss", "enemy": cid}, 1)
            if S["en_next_elite_boss"] > 0 and t >= S["en_next_elite_boss"] and last_elite_boss and pick_shares(last_elite_boss.get("enemy")):
                S["en_next_elite_boss"] = 0
                run_event({"type": "elite_boss", "enemy": last_elite_boss.get("enemy")}, 1)

    sp_block = tl.get("specials") if is_obj(tl.get("specials")) else {}
    sp_on = len(sp_block) > 0
    sp_from = numv(sp_block.get("from"), SL * 0.5)
    sp_iv = sp_block.get("interval") if isinstance(sp_block.get("interval"), list) and sp_block.get("interval") else [20, 40]
    sp_steps = max(1, js_round(((numv(sp_iv[0], 20) + numv(sp_iv[-1], 40)) / 2) * EST_HZ))
    sp_max = trunc(numv(sp_block.get("max_alive"), 1))

    def tick_specials():
        if not sp_on:
            return
        if S["stage"] == 0 and clock() < sp_from:
            return
        pool = []
        for row in sp_block.get("pool") if isinstance(sp_block.get("pool"), list) else []:
            cid = str("" if row.get("enemy") is None else row.get("enemy")) if is_obj(row) else str(row)
            st = trunc(numv(row.get("stage"), 1)) if is_obj(row) else 1
            if cid in by_id and S["stage"] + 1 >= st:
                pool.append(cid)
        if not pool:
            return
        if len(sp_live) >= sp_max:
            S["sp_left"] = -1
            return
        if S["sp_left"] < 0:
            S["sp_left"] = sp_steps
        S["sp_left"] -= 1
        if S["sp_left"] > 0:
            return
        S["sp_left"] = -1
        tv = turnover_now()
        life = max(1, js_round(EST_HZ / tv)) if tv > 0 else INF
        share = 0.0
        for cid in pool:
            bump(cum, cid, 1 / len(pool))
            share += def_of(cid, None)["share"] / len(pool)
        cat["special"] += 1
        sp_live.append({"share": share, "die": S["play"] + life})
        marks.append({"t": clock(), "kind": "special", "id": "/".join(pool), "n": 1})

    def burst_rows(lst, room, left):
        t = now()
        rows = [{"w": roster_weight(c["x"]["r"], t, late_t), "s": max(c["x"]["d"]["share"], 0.05), "pack": c["x"]["pack"],
                 "single": c["x"]["single"], "room": c["room"]} for c in lst]
        got = burst_avg(rows, room, b_lo, b_hi)
        s = 0.0
        for n in got:
            s += n
        scale = left / s if s > left else 1
        used = 0.0
        for i, c in enumerate(lst):
            n = got[i] * scale
            add(c["x"]["d"], n, "reg")
            bump(src_cum, c["x"]["key"], n)
            used += n
        return left - used

    def spawn_burst():
        cap = cap_now()
        if cap <= 0:
            return
        tr = now() if S["phase"] == 0 else now() - 1
        hell_rows = rows_at(tr, True)
        hl = load_of(hell_ids(hell_rows))
        room = cap - (load_all() - hl)
        left = hard - bodies()
        if left <= 0:
            return
        regular = open_rows(rows_at(tr, False))
        if room > 0 and regular:
            left = burst_rows(regular, room, left)
        hell_room = hell_frac() * cap - hl
        if hell_room > 0 and left > 0 and hell_rows:
            ho = open_rows(hell_rows)
            if ho:
                burst_rows(ho, hell_room, left)

    def portal_wave():
        if portal_wave_count <= 0:
            return
        lst = open_rows(rows_at(now() - 1, False))
        if not lst:
            return
        left = min(portal_wave_count, math.floor(hard - bodies()))
        if left <= 0:
            return
        t = now()
        rows = [{"w": roster_weight(c["x"]["r"], t, late_t), "s": 1, "pack": c["x"]["pack"], "single": c["x"]["single"], "room": INF} for c in lst]
        got = burst_once(rows, left)
        for i, c in enumerate(lst):
            add(c["x"]["d"], got[i], "reg")

    points = []

    def record(after):
        by = {cid: [cum[cid], col.get(cid, 0), mod.get(cid, 0)] for cid in cum}
        points.append({"t": clock(), "after": after, "all": total(), "reg": cat["reg"], "col": cat["col"], "mod": cat["mod"],
                       "elite": cat["elite"], "special": cat["special"], "boss": cat["boss"], "minion": cat["minion"], "kills": S["kills"], "alive": bodies(), "by": by,
                       "src": dict(src_cum)})

    record(False)
    end_k = js_round(end * EST_HZ)
    guard = 0
    while (S["k"] < end_k or S["phase"] != 0) and guard < 4000000:
        guard += 1
        S["play"] += 1
        kd = turnover_now() / EST_HZ
        if kd > 0:
            for a in alive.values():
                dn = a["n"] * kd
                a["n"] -= dn
                S["kills"] += dn
        for i in range(len(sp_live) - 1, -1, -1):
            if sp_live[i]["die"] <= S["play"]:
                sp_live.pop(i)
                S["kills"] += 1
        if S["colour_at"] is None and colour_open():
            S["colour_at"] = clock()
        if S["phase"] == 0:
            S["k"] += 1
            process_events()
            if S["phase"] == 0:
                tick_waves()
        elif S["phase"] == 1:
            S["phase_left"] -= 1
            while S["fight"] and S["fight"]["brood"] and S["fight"]["brood"][0]["step"] <= S["play"]:
                b = S["fight"]["brood"].pop(0)
                d = def_of(b["id"], None)
                n = min(b["n"], max(MAX_BODIES - bodies(), 0))
                if d and n > 0:
                    add(d, n, "reg")
                    cat["minion"] += n
                    S["fight"]["minions"] += n
            if S["phase_left"] <= 0:
                S["boss_alive"] = None
                S["kills"] += 1
                S["phase"], S["phase_left"], S["portal_t"] = 2, portal_steps, 0.0
                portal_wave()
        else:
            S["phase_left"] -= 1
            S["portal_t"] += 1 / EST_HZ
        if S["phase"] != 2:
            tick_specials()
        S["spawn_step"] -= 1
        if S["spawn_step"] <= 0:
            S["spawn_step"] = burst_every
            spawn_burst()
        if S["phase"] == 2 and S["phase_left"] <= 0:
            S["stage"] += 1
            if S["stage"] >= NST:
                S["endless"] = True
                S["en_boss_i"] = 0
                S["en_next_boss"] = clock() + SL
                S["en_next_elite"] = clock() + SL * 0.15
                S["en_next_elite_boss"] = clock() + SL * 0.5
            S["phase"] = 0
            S["fight"]["spawned"] = total() - S["fight"]["before"] - 1
            del S["fight"]["brood"]
            fights.append(S["fight"])
            S["fight"] = None
            record(True)
            continue
        if S["k"] % EST_HZ == 0 and (S["phase"] == 0 or points[-1]["t"] != clock()):
            record(False)
    last = points[-1]["by"]
    ids = sorted(last, key=lambda cid: (-last[cid][0], cid))
    return {"points": points, "ids": ids, "marks": marks, "fights": fights, "colourAt": S["colour_at"]}


# ---------------------------------------------------------------- model.js under node


NODE_RUNNER = r"""
const M = require(process.argv[2]);
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.sample = q.sample.map(([pts, t]) => M.samplePoints(pts, t));
  out.curve = q.curve.map(([c, t]) => M.curveMult(c, t));
  out.conv = q.conv.map(([tl]) => { const copy = JSON.parse(JSON.stringify(tl)); const n = M.normaliseRoster(copy); return { roster: copy.roster, n }; });
  out.weight = q.weight.map(([r, t, late]) => M.rowWeight(r, t, late));
  out.creature = q.creature.map(([tl, c, st, t, lv, t0]) => { const r = M.creatureAt(tl, c, st, t, lv, t0); return [r.hp, r.atk, r.arch]; });
  out.rows = (q.rows || []).map(([tl, c, st, t0]) => { const r = M.rowNumbers(tl, c, st, t0); return [r.hp, r.atk, r.hpMult, r.atkMult, r.arch]; });
  out.size = (q.size || []).map((v) => [M.sizeIssues(v), M.sizeRange(v)]);
  out.tint = (q.tint || []).map((v) => [M.tintIssues(v), M.tintRange(v)]);
  out.hue = (q.hue || []).map(([h0, h1, f]) => [M.hueSpan(h0, h1), M.hueAt(h0, h1, f)]);
  out.hsv = (q.hsv || []).map(([h, s, v]) => M.hsvToRgb(h, s, v));
  out.px = (q.px || []).map(([rgb, tint, amount]) => M.tintPixel(rgb, tint, amount));
  out.special = (q.special || []).map(([r, ss, f]) => M.tintSpecial(r, ss, f));
  out.vspecial = (q.vspecial || []).map(([c, st]) => M.varianceSpecial(c, st));
  out.ascale = (q.ascale || []).map(([own, top]) => M.actualScale(own, top));
  out.firings = (q.firings || []).map(([ev, n, end]) => M.eliteEveryTimes(ev, n, end));
  out.fixed = (q.fixed || []).map(([tl, t0, t]) => M.fixedFrom(tl, t0, t));
  out.events = (q.events || []).map(([tl, byId, id, variant, stats, t]) => {
    const r = M.eventNumbers(tl, byId, id, variant, stats, t);
    return { hp: r.hp, atk: r.atk, joined: r.joined ? [r.joined.kind, r.joined.i, r.joined.k] : null, hpJoined: r.hpJoined, dmgJoined: r.dmgJoined, hpFrom: r.hpFrom, dmgFrom: r.dmgFrom, share: r.joined ? r.joined.share : null };
  });
  out.knock = q.knock.map(([c, st]) => M.knockbackOf(c, st));
  out.seed = q.seed.map(([tl, f]) => M.seedPoints(tl, f));
  process.stdout.write(JSON.stringify(out));
});
"""


def run_node(query, runner_src=None):
    node = shutil.which("node")
    if not node:
        return None
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
        f.write(runner_src or NODE_RUNNER)
        runner = f.name
    try:
        p = subprocess.run([node, runner, os.path.join(HERE, "model.js")], input=json.dumps(query), capture_output=True,
                           text=True, encoding="utf-8", timeout=60)
    finally:
        os.remove(runner)
    if p.returncode != 0:
        print(p.stderr)
        check(False, "model.js ran under node")
        return {}
    return json.loads(p.stdout)


def close(a, b, eps=1e-9):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


# the Red Canyon roster as it was before lane WD converted it (explore_x1 section 7), with the late time 860
OLD_RED_CANYON = [
    {"t": 0, "until": 86, "enemy": "red_goblin", "weight": 9, "weight_late": 3},
    {"t": 0, "until": 86, "enemy": "red_goblin_runt", "weight": 3, "weight_late": 1.2},
    {"t": 86, "until": 171, "enemy": "lesser_scorpion", "weight": 8, "weight_late": 5},
    {"t": 430, "enemy": "dust_mummy", "weight": 3.0, "weight_late": 5},
    {"t": 487, "enemy": "bull_beetle", "weight": 2.0, "weight_late": 3},
    {"t": 559, "enemy": "horned_toad", "weight": 2, "weight_late": 4},
    {"t": 860, "enemy": "dust_shaman", "weight": 1, "weight_late": 2},
    {"t": 430, "enemy": "blue_slime", "weight": 10, "channel": "hell"},
    {"t": 602, "enemy": "hammer_giant", "weight": 1.5, "channel": "hell"},
    {"t": 860, "enemy": "imp", "weight": 9, "channel": "hell"},
    {"t": 860, "enemy": "hellhound", "weight": 8, "channel": "hell"},
    {"t": 171, "until": 300, "enemy": "skeleton", "weight": 5.0},
    {"t": 171, "until": 300, "enemy": "skeleton_knight", "weight": 5.0},
    {"t": 171, "until": 250, "enemy": "spit_cactus", "weight": 1},
    {"t": 250, "until": 368, "enemy": "bull_beetle", "weight": 2},
    {"t": 300, "until": 430, "enemy": "red_goblin", "weight": 2},
    {"t": 300, "until": 430, "enemy": "red_goblin_runt", "weight": 2},
]


def model_checks():
    rnd = random.Random(54)
    q = {"sample": [], "curve": [], "conv": [], "weight": [], "creature": [], "knock": [], "seed": []}
    # 1. point sampling: random sorted lists, times before, between, on and after the points
    for _ in range(60):
        n = rnd.randint(1, 6)
        ts = sorted(rnd.sample(range(0, 1500, 7), n))
        pts = [[t, round(rnd.uniform(0, 12), 2)] for t in ts]
        for t in [-10, 0, ts[0], ts[-1], ts[-1] + 50] + [rnd.uniform(0, 1500) for _ in range(5)]:
            q["sample"].append([pts, t])
    q["sample"].append([[], 100])
    q["sample"].append([[[430, 3.0], [430, 5]], 430])
    q["sample"].append([[[430, 3.0], [430, 5]], 431])
    # 2. curves: every formula kind, default a / b, points mode, empty, an unknown mode
    curves = [
        {"mode": "formula", "formula": {"kind": "power", "a": 0.0977, "b": 1.25}, "points": [[0, 1.0], [430, 1.9414]]},
        {"mode": "formula", "formula": {"kind": "linear", "a": 0.05}},
        {"mode": "formula", "formula": {"kind": "exponential", "a": 0.04}},
        {"mode": "formula", "formula": {"kind": "linear", "a": 0.0}, "points": [[0, 1.0], [1290, 1.0]]},
        {"mode": "formula", "formula": {}},
        {"mode": "formula", "formula": {"kind": "bogus"}},
        {"mode": "points", "points": [[0, 1.0], [430, 2.0], [860, 2.5]], "formula": {"kind": "power"}},
        {"points": [[100, 1.5], [200, 3.0]]},
        {"formula": {"kind": "linear", "a": 0.1}},
        {"mode": "points", "points": []},
        {"mode": "wobble", "points": [[0, 2]]},
        {},
    ]
    for c in curves:
        for t in (0, 59, 300, 430, 645, 860, 1290, 1600):
            q["curve"].append([c, t])
    # 3. the old shape -> presence keyframes: Red Canyon before WD, a late time before a row's start, ids
    q["conv"].append([{"weight_late_t": 860, "roster": json.loads(json.dumps(OLD_RED_CANYON))}])
    q["conv"].append([{"weight_late_t": 300, "roster": [{"t": 400, "enemy": "imp", "weight": 4, "weight_late": 1},
                                                          {"id": "r2", "t": 0, "enemy": "imp", "weight": 2},
                                                          {"id": "r2", "t": 10, "enemy": "imp", "weights": [[10, 1], [20, 3]]}]}])
    # the latest old-shape backup the editor keeps, if any (a real file Garry saved)
    olds = []
    bdir = server.BACKUPS
    if os.path.isdir(bdir):
        for name in sorted(os.listdir(bdir), reverse=True):
            if name.startswith("red_canyon-") and name.endswith(".json"):
                try:
                    tl = server.load_json(os.path.join(bdir, name)).get("timeline_data", {})
                except (OSError, ValueError):
                    continue
                if any("weight" in r for r in tl.get("roster", [])):
                    olds.append((name, tl))
                    break
    for name, tl in olds:
        q["conv"].append([tl])
    # 4. one creature's numbers (regular, Elite archetype, boss) on a Red Canyon-like timeline
    tl = {"stage_length": 430, "stages": 3, "stage_mults": [1.0, 2.2, 3.34], "creature_hp_mult": 1.3, "creature_damage_mult": 1.25,
          "level_hp_per_level": 0.05, "level_damage_per_level": 0.03, "endless_wave_seconds": 86, "endless_wave_mult": 1.12,
          "hp_curve": {"mode": "formula", "formula": {"kind": "power", "a": 0.0977, "b": 1.25}},
          "damage_curve": {"mode": "points", "points": [[0, 1.0], [860, 1.5]]}}
    tl_legacy = {"stage_length": 430, "stages": 3, "stage_mults": [1.0, 2.2, 3.34], "creature_hp_mult": 1.3, "hp_growth": 0.0977, "hp_power": 1.25}
    walker = {"id": "skeleton", "kind": "enemy", "archetype": "walker", "hp": 10, "damage": 3}
    elite = {"id": "dune_scorpion", "kind": "enemy", "archetype": "elite", "hp": 260, "damage": 10, "elite": {"hp_mult_per_stage": 1.8}}
    boss = {"id": "gila_grande", "kind": "boss", "archetype": "boss", "hp": 2400, "damage": 20, "boss": {"hp_mult_per_stage": 1.6}}
    cases = [(tl, walker, {}, 240, 1), (tl, walker, {"hp": 20, "damage_mult": 2}, 240, 10), (tl, walker, {}, 1400, 5),
             (tl, elite, {}, 645, 1), (tl, elite, {"elite": {"hp_mult_per_stage": 2.0}}, 1000, 7), (tl, boss, {}, 860, 1),
             (tl_legacy, walker, {}, 600, 1), (tl_legacy, boss, {"hp_mult": 0.5}, 1290, 3)]
    for c in cases:
        q["creature"].append(list(c))
    # pass 58, R1: a row's numbers fixed from its start t0 (the 6th item); the hand-checked ones are read back below
    r1_cases = [(tl, walker, {}, 900, 10, 192), (tl, walker, {"hp": 20}, 900, 10, 192), (tl, walker, {}, 200, 1, 192),
                (tl, walker, {}, 400, 1, 192), (tl, elite, {}, 1000, 7, 200), (tl, elite, {}, 1000, 7, None),
                (tl, walker, {"damage": 6, "hp_mult": 1.5}, 600, 4, 100), (tl, boss, {}, 860, 1, 0), (tl_legacy, walker, {}, 700, 3, 50),
                # lane WV's fix round: in endless a row is fixed afresh from its wave's start (1376 here, not 192)
                (tl, walker, {}, 1400, 5, 192)]
    q["creature"] += [list(c) for c in r1_cases]
    q["rows"] = [[tl, walker, {}, 192], [tl, walker, {"hp": 20}, 192], [tl, walker, {"damage": 6, "damage_mult": 2}, 430],
                 [tl, elite, {"hp_mult": 2}, 645], [tl, boss, {}, 860], [tl, {"id": "z", "hp": 0, "damage": 0}, {}, 10]]
    # pass 58, R2 / R3: the size and colour ranges' checks and maths
    q["size"] = [None, 1.4, [1.2, 1.6], [1.6, 1.2], [0, 1], [-1], [2], [1, 2, 3], "x", [None, 1], True, 0, [1.5, 1.5]]
    q["tint"] = [None, {"hue": [200, 260]}, {"hue": [340, 20], "sat": 0.5, "val": 0.8, "amount": 1}, {"hue": 120},
                 {"hue": [10, 400]}, {"hue": [10, 20], "amount": 1.5}, {"sat": 0.5}, {"hue": []}, "red", {"hue": ["a", 2]},
                 {"hue": [0, 360], "val": -0.1}]
    q["hue"] = [[200, 260, 0.5], [340, 20, 0.5], [340, 20, 0], [340, 20, 1], [0, 360, 1], [90, 90, 0.7], [350, 10, 0.75]]
    q["hsv"] = [[0, 1, 1], [120, 1, 1], [240, 1, 1], [60, 0.5, 0.8], [300, 0.85, 1.0], [0, 0, 0.5], [359.9, 1, 1]]
    q["px"] = [[[0.5, 0.5, 0.5], [1, 0, 0], 0], [[0.5, 0.5, 0.5], [1, 0, 0], 1], [[1, 1, 1], [0, 0, 1], 0.5], [[0.2, 0.4, 0.6], [0.2, 0.4, 0.6], 0.7]]
    # the review of pass 58: a coloured row's special (EnemyDef.tint_special_color), the variance block it reads, the
    # Actual lane's own top, and an "Elites every" event's firings
    q["special"] = [[{"h0": 200, "h1": 260, "sat": 0.85, "val": 1, "amount": 0.5}, 0.45, 0.5],
                    [{"h0": 330, "h1": 30, "sat": 0.9, "val": 0.6, "amount": 0.9}, 0.45, 0.5],
                    [{"h0": 120, "h1": 120, "sat": 0.2, "val": 0.5, "amount": 0.1}, None, 0],
                    [{"h0": 10, "h1": 50, "sat": 1, "val": 0.3, "amount": 0.2}, 0.7, 1]]
    skel_var = {"size": 0.2, "tints": ["#FFFFFF"], "tint_strength": 0.18, "special_chance": 0.12,
                "special": {"size": 1.5, "hp": 2.0, "tint": "#6E1A2A", "tint_strength": 0.45}}
    q["vspecial"] = [[{"variance": skel_var}, {}], [{"variance": skel_var}, {"variance": {"special": {"tint_strength": 0.8}}}],
                     [{"variance": skel_var}, {"variance": {"special_chance": 0}}], [{}, {}],
                     [{"variance": {"special_chance": 0.1}}, {}], [{}, {"variance": {"special_chance": 0.2}}]]
    q["ascale"] = [[5.21, 20], [5.21, 2.33], [5.21, 5.0], [5.21, 5.3], [0, 3], [4, None]]
    q["firings"] = [[{"t": 301, "interval": 129}, 4, 1290], [{"t": 301, "interval": [60, 120]}, 3, None],
                    [{"t": 1200, "interval": 129}, 4, 1290], [{"t": 0, "interval": 0}, 4, None], [{"t": 100}, 2, None]]
    # lane WV's fix round: endless fixes every row afresh at each wave, and an event of a creature a row or a wave
    # brings then plays that row's numbers (WaveDirector.source_for, event_numbers, open_source_of)
    tl_short = {"stage_length": 300, "stages": 3}
    q["fixed"] = [[tl, 860, 1400], [tl, 192, 1000], [tl, 1300, 1400], [tl, 1500, 1500], [tl, 0, 1290], [tl_short, 100, 1400], [tl, 860, 1375.9]]
    ev_tl = dict(tl, roster=[
        {"id": "a", "t": 192, "until": 400, "enemy": "skeleton", "weights": [[192, 5]], "stats": {"hp": 20}},
        {"id": "b", "t": 300, "until": 600, "enemy": "skeleton", "weights": [[300, 8]]},
        {"id": "c", "t": 0, "until": 100, "enemy": "skeleton", "variant": "SK-B", "weights": [[0, 3]]},
        {"id": "d", "t": 860, "enemy": "imp", "channel": "hell", "weights": [[860, 9]]},
        {"id": "z", "t": 500, "until": 700, "enemy": "skeleton", "weights": [[500, 0], [700, 0]]}],
        waves=[{"t": 700, "until": 800, "enemy": "skeleton", "stats": {"damage": 9}},
               {"t": 1000, "count": 10, "burst": 5, "every": 10, "alts": [{"chance": 1, "enemy": "goblin"}, {"chance": 3, "enemy": "imp", "variant": "IM-B"}]}])
    ev_by = {"skeleton": {"id": "skeleton", "hp": 10, "damage": 3, "variant": "SK-A", "variants": [{"code": "SK-A"}, {"code": "SK-B"}]},
             "imp": {"id": "imp", "hp": 20, "damage": 5, "variant": "", "variants": [{"code": "IM-B"}]},
             "goblin": {"id": "goblin", "hp": 8, "damage": 2, "variants": []},
             "dune_scorpion": {"id": "dune_scorpion", "archetype": "elite", "hp": 260, "damage": 10, "variants": []}}
    q["events"] = [[ev_tl, ev_by, cid, var, st, t] for cid, var, st, t in [
        ("skeleton", "", {}, 250), ("skeleton", "", {}, 350), ("skeleton", "SK-A", {}, 350), ("skeleton", "SK-B", {}, 50),
        ("skeleton", "SK-B", {}, 350), ("skeleton", "", {"hp": 50}, 350), ("skeleton", "", {"hp": 50, "damage_mult": 2}, 350),
        ("skeleton", "", {}, 650), ("skeleton", "", {}, 750), ("imp", "", {}, 900), ("imp", "", {}, 1400), ("imp", "IM-B", {}, 1005),
        ("goblin", "", {}, 1005), ("dune_scorpion", "", {}, 350), ("nobody", "", {}, 350), ("skeleton", "XX-9", {}, 350)]]
    q["knock"] = [[{"damage": 4}, {}], [{"damage": 4, "knockback": 5.5}, {}], [{"damage": 100}, {}], [{"damage": 0.5}, {}],
                  [{"damage": 4}, {"knockback": 6, "knockback_mult": 0.5}], [{"damage": 4}, {"damage": 16}]]
    q["seed"] = [[{"stage_length": 430, "stages": 3}, {"kind": "power", "a": 0.0977, "b": 1.25}]]

    res = run_node(q)
    if res is None:
        print("node not found: the model.js checks are skipped (install Node.js to run them)")
        return
    if not res:
        return
    for (pts, t), got in zip(q["sample"], res["sample"]):
        check(close(got, sample_points(pts, t)), "sample_points %s at %s: js %s" % (pts, t, got))
    for (c, t), got in zip(q["curve"], res["curve"]):
        check(close(got, curve_mult(c, t)), "curve_mult %s at %s: js %s py %s" % (c, t, got, curve_mult(c, t)))
    # conversion: the converted rows weigh what the old rows weighed at every second (but the first second after a row
    # that starts at or after weight_late_t, where the old slide ramped over one second and the keyframes do too)
    for (src,), got in zip(q["conv"], res["conv"]):
        late = float(src.get("weight_late_t", 600))
        rows_old, rows_new = src["roster"], got["roster"]
        check(len(rows_old) == len(rows_new), "conversion keeps every row")
        ids = [r.get("id") for r in rows_new]
        check(all(isinstance(i, str) and i for i in ids) and len(set(ids)) == len(ids), "every row has a unique id: %s" % ids)
        for o, n in zip(rows_old, rows_new):
            check("weight" not in n and "weight_late" not in n and isinstance(n.get("weights"), list), "row %s in the new shape" % n.get("id"))
            if "weights" in o and o["weights"]:
                check(n["weights"] == o["weights"], "a row with keyframes keeps them")
                continue
            for t in range(0, 1800, 5):
                check(close(roster_weight(n, t, late), roster_weight(o, t, late), 1e-9), "row %s %s weighs the same at %s: %s vs %s" % (
                    n.get("id"), o.get("enemy"), t, roster_weight(n, t, late), roster_weight(o, t, late)))
    # the page's converter agrees with lane WD's conversion of Red Canyon (informational when Garry has edited the rows)
    cur = server.load_json(server.map_path("red_canyon")).get("timeline_data", {}).get("roster", [])
    mine = res["conv"][0]["roster"]
    same_rows = len(cur) == len(mine) and all(c.get("enemy") == m.get("enemy") and c.get("t") == m.get("t") for c, m in zip(cur, mine))
    if same_rows and all("weights" in c for c in cur):
        for c, m in zip(cur, mine):
            check([[float(a), float(b)] for a, b in c["weights"]] == [[float(a), float(b)] for a, b in m["weights"]] and c.get("id") == m.get("id"),
                  "row %s: the page converts as WD did (%s vs %s)" % (c.get("id"), m["weights"], c["weights"]))
    else:
        print("note: Red Canyon's roster no longer matches the pre-pass-54 rows; the WD agreement check is skipped")
    for case, got in zip(q["creature"], res["creature"]):
        tlc, c, st, t, lv = case[:5]
        t0 = case[5] if len(case) > 5 else None
        hp, atk = creature_at(tlc, c, st, t, lv, t0)
        check(close(got[0], hp) and close(got[1], atk), "%s at %s level %s from %s with %s: js HP %s ATK %s, py HP %s ATK %s" % (c["id"], t, lv, t0, st, got[0], got[1], hp, atk))
    # R1 by hand (Red Canyon-like: the power curve 0.0977 / 1.25, stage 3 x3.34 at 15:00, level 10 = x1.45 HP, x1.27 ATK)
    r1 = res["creature"][len(cases):]
    ht192 = (1 + 0.0977 * 192 / 60) ** 1.25
    dt192 = 1 + 0.5 * 192 / 860
    check(close(r1[0][0], 10 * ht192 * 3.34 * 1.45 * 1.3) and close(r1[0][1], 3 * dt192 * 3.34 * 1.27 * 1.25),
          "R1: a row from 3:12 met at 15:00 keeps the HP curve of 3:12 (x%.4f), the stage steps live: %s" % (ht192, r1[0]))
    check(close(r1[1][0], 20 * 3.34 * 1.45 * 1.3), "R1: a row with hp 20 takes no curve: %s" % r1[1])
    check(close(r1[2][0], r1[3][0]) and close(r1[2][1], r1[3][1]), "R1: the same row at 3:20 and 6:40 (stage 1): the same HP and ATK: %s %s" % (r1[2], r1[3]))
    check(close(r1[4][0], r1[5][0]) and close(r1[4][1], r1[5][1]), "R1: an Elite ignores the row's start: %s %s" % (r1[4], r1[5]))
    ht100 = (1 + 0.0977 * 100 / 60) ** 1.25
    check(close(r1[6][0], 10 * ht100 * 1.5 * 2.2 * 1.15 * 1.3) and close(r1[6][1], 6 * 2.2 * 1.09 * 1.25),
          "R1: hp_mult on the curve's HP, a damage override takes no curve: %s" % r1[6])
    rows = res["rows"]
    check(close(rows[0][2], ht192) and close(rows[0][0], 10 * ht192) and close(rows[0][3], dt192), "rowNumbers: the multiples at 3:12: %s" % rows[0])
    check(close(rows[1][0], 20) and close(rows[1][2], 2.0) and close(rows[1][3], dt192), "rowNumbers: an hp override over the JSON's 10 is x2: %s" % rows[1])
    check(close(rows[2][1], 12) and close(rows[2][3], 4.0), "rowNumbers: damage 6 x damage_mult 2 over the JSON's 3 is x4 (no curve): %s" % rows[2])
    check(close(rows[3][2], 2.0) and rows[3][4] == "elite", "rowNumbers: an Elite takes no curve, only hp_mult: %s" % rows[3])
    check(close(rows[4][2], 1.0) and rows[4][4] == "boss", "rowNumbers: a boss takes no curve: %s" % rows[4])
    check(rows[5][2] is None and rows[5][3] is None, "rowNumbers: no multiple when the JSON's number is 0: %s" % rows[5])
    for (tlc, c, st, t0), got in zip(q["rows"], rows):
        py = row_numbers(tlc, c, st, t0)
        check(close(got[0], py["hp"]) and close(got[1], py["atk"]) and (got[2] is None) == (py["hp_mult"] is None) and got[4] == py["arch"],
              "rowNumbers %s from %s with %s: js %s py %s" % (c["id"], t0, st, got, py))
    # R2: sizes
    sz = res["size"]
    want_ok = [True, True, True, False, False, False, True, False, False, False, False, False, True]
    for v, (issues, rng), ok in zip(q["size"], sz, want_ok):
        check((not issues) == ok, "size %r: %s (want %s)" % (v, issues or "fine", "fine" if ok else "an issue"))
    check(sz[2][1] == {"min": 1.2, "max": 1.6, "range": True} and sz[1][1] == {"min": 1.4, "max": 1.4, "range": False}, "sizeRange: a pair and a number: %s %s" % (sz[2][1], sz[1][1]))
    check(sz[3][1]["min"] == 1.2 and sz[3][1]["max"] == 1.6 and "backwards" in sz[3][0][0], "a reversed pair is an error, read as the game swaps it: %s" % (sz[3],))
    # the review of pass 58: EnemyDef.size_range_of reads [2] as Vector2(2, 2), a range (no spread, the radius following)
    check(sz[6][1] == {"min": 2, "max": 2, "range": True}, "a one-number list is a range of one size, as the game reads it: %s" % (sz[6][1],))
    check(sz[12][1] == {"min": 1.5, "max": 1.5, "range": True}, "two equal numbers are a range of one size too: %s" % (sz[12][1],))
    # R3: colour ranges
    tn = res["tint"]
    want_ok = [True, True, True, True, False, False, False, False, False, False, False]
    for v, (issues, rng), ok in zip(q["tint"], tn, want_ok):
        check((not issues) == ok, "tint %r: %s (want %s)" % (v, issues or "fine", "fine" if ok else "an issue"))
    check(tn[1][1] == {"h0": 200, "h1": 260, "sat": 0.85, "val": 1, "amount": 0.5}, "tintRange fills R3's defaults (0.85, 1.0, 0.5): %s" % tn[1][1])
    check(tn[3][1]["h0"] == 120 and tn[3][1]["h1"] == 120, "a plain hue is that hue (WV): %s" % tn[3][1])
    hu = res["hue"]
    check(hu[0] == [60, 230] and hu[1] == [40, 0] and hu[2][1] == 340 and hu[3][1] == 20 and hu[4][1] == 0 and hu[5] == [0, 90] and close(hu[6][1], 5),
          "hues: 200..260 halfway 230; 340..20 wraps through red (span 40, halfway 0); 350..10 three quarters = 5: %s" % hu)
    hs = res["hsv"]
    import colorsys
    for (h, s, v), got in zip(q["hsv"], hs):
        want = colorsys.hsv_to_rgb((h % 360) / 360.0, s, v)
        check(all(close(a, b, 1e-9) for a, b in zip(got, want)), "hsvToRgb(%s, %s, %s): %s, want %s" % (h, s, v, got, want))

    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    def srgb(c):
        return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    for (rgb, tint, amount), got in zip(q["px"], res["px"]):
        k = amount * 0.65
        want = [min(max(srgb(lin(a) * (1 - k) + b * k), 0), 1) for a, b in zip(rgb, tint)]
        check(all(close(a, b, 1e-9) for a, b in zip(got, want)), "tintPixel(%s, %s, %s): %s, want %s (the shader's mix in linear light)" % (rgb, tint, amount, got, want))
    check(all(close(a, b, 1e-9) for a, b in zip(res["px"][0], [0.5, 0.5, 0.5])), "amount 0 leaves the pixel as painted")

    # the review of pass 58: a coloured row's special, EnemyDef.tint_special_color (saturation + SPECIAL_SAT_ADD 0.15 at
    # most 1, value x SPECIAL_VAL_MULT 0.7, strength max(amount, the special's tint_strength, 0.6 when it has none) +
    # SPECIAL_STRENGTH_ADD 0.15 at most 1), with the hue EnemyDef.roll_hue gives at u = f
    def roll_hue(h0, h1, u):
        span = h1 - h0
        if span < 0:
            span += 360
        return (h0 + min(max(u, 0), 1) * span) % 360
    for (r, ss, f), got in zip(q["special"], res["special"]):
        h = roll_hue(r["h0"], r["h1"], f)
        want = colorsys.hsv_to_rgb(h / 360.0, min(r["sat"] + 0.15, 1.0), r["val"] * 0.7)
        amt = min(max(r["amount"], 0.6 if ss is None else ss) + 0.15, 1.0)
        check(close(got["h"], h) and all(close(a, b, 1e-9) for a, b in zip(got["rgb"], want)) and close(got["amount"], amt),
              "tintSpecial(%s, %s, %s): %s, want hue %s rgb %s strength %s" % (r, ss, f, got, h, want, amt))
    # the game's own constants, read from EnemyDef.gd, are the ones the copy above (and model.js) use
    gd = os.path.join(ROOT, "game", "core", "data", "EnemyDef.gd")
    if os.path.isfile(gd):
        src = open(gd, encoding="utf-8").read()
        for name, want in (("SPECIAL_SAT_ADD", 0.15), ("SPECIAL_VAL_MULT", 0.7), ("SPECIAL_STRENGTH_ADD", 0.15)):
            m = re.search(r"const\s+%s\s*:?=\s*([0-9.]+)" % name, src)
            check(m is not None and close(float(m.group(1)), want), "EnemyDef.%s is %s, as model.js tintSpecial assumes (%s)" % (name, m.group(1) if m else "missing", want))
    sp = res["special"]
    check(close(sp[0]["h"], 230) and close(sp[0]["amount"], 0.65) and close(max(sp[0]["rgb"]), 0.7),
          "special by hand: 200-260 at amount 0.5 with the skeleton's 0.45 is hue 230 at value 0.7, strength 0.65: %s" % sp[0])
    check(close(sp[1]["h"], 0) and close(sp[1]["amount"], 1.0), "special by hand: 330-30 through red, middle hue 0, strength capped at 1: %s" % sp[1])
    check(close(sp[2]["amount"], 0.75), "special by hand: no tint_strength = the game's 0.6, + 0.15: %s" % sp[2])
    vs = res["vspecial"]
    want_vs = [(0.12, 0.45, 1.5), (0.12, 0.8, 1.5), (0, 0.45, 1.5), (0, 0.6, 1.3), (0.1, 0.6, 1.3), (0.2, 0.6, 1.3)]
    for (c, st), got, (ch, stg, sz_) in zip(q["vspecial"], vs, want_vs):
        check(close(got["chance"], ch) and close(got["strength"], stg) and close(got["size"], sz_),
              "varianceSpecial(%s, %s): %s, want chance %s strength %s size %s (the row's variance deep-merged over the creature's)" % (c, st, got, ch, stg, sz_))
    want_sc = [5.21 * 1.5, 5.21, 5.21, 5.3 * 1.15, 1.5 * 1.5, 4]
    for (own, top), got, want in zip(q["ascale"], res["ascale"], want_sc):
        check(close(got, want), "actualScale(%s, %s): %s, want %s (the curve's top while the rows fit under it, else up to 1.5 times it)" % (own, top, got, want))
    want_fi = [[301, 430, 559, 688], [301, 391, 481], [1200], [0], [100, 190]]
    for (ev, n, end), got, want in zip(q["firings"], res["firings"], want_fi):
        check(len(got) == len(want) and all(close(a, b) for a, b in zip(got, want)), "eliteEveryTimes(%s, %s, %s): %s, want %s" % (ev, n, end, got, want))

    # lane WV's fix round, endless: every row fixed afresh at each wave (1290 + N x 86 on the Red Canyon-like timeline)
    want_fx = [1376, 192, 1376, 1500, 1290, 1380, 1290]
    for (tlc, t0, t), got, want in zip(q["fixed"], res["fixed"], want_fx):
        check(close(got, want) and close(got, fixed_from(tlc, t0, t)), "fixedFrom(t0 %s, t %s): %s, want %s" % (t0, t, got, want))
    r1x = res["creature"][len(cases) + len(r1_cases) - 1]
    check(close(r1x[0], 10 * hp_time(tl, 1376) * stage_mult(tl, 3, 1400) * 1.2 * 1.3),
          "R1 in endless: a row from 3:12 met at 23:20 takes the curve at its wave's start 22:56, not 3:12: %s" % r1x)
    # lane WV's fix round, events: the joined row's numbers for the halves the event leaves alone
    ev_cases = q["events"]
    for case, got in zip(ev_cases, res["events"]):
        tlc, by, cid, var, st, t = case
        py = event_numbers(tlc, by, cid, var, st, t)
        check(close(got["hp"], py["hp"]) and close(got["atk"], py["atk"]) and got["joined"] == py["joined"] and got["hpJoined"] == py["hp_joined"]
              and got["dmgJoined"] == py["dmg_joined"] and close(got["hpFrom"], py["hp_from"]) and close(got["dmgFrom"], py["dmg_from"]),
              "eventNumbers(%s %r %s at %s): js %s py %s" % (cid, var, st, t, got, py))
    ev = res["events"]
    dt = lambda s_: 1 + 0.5 * s_ / 860  # noqa: E731 (the damage curve's points [[0, 1], [860, 1.5]])
    check(ev[0]["joined"] == ["roster", 0, 0] and close(ev[0]["hp"], 20) and close(ev[0]["atk"], 3 * dt(192)) and close(ev[0]["hpFrom"], 192),
          "an event at 4:10 joins row a: its own hp 20 (no curve) and the damage curve at its 3:12: %s" % ev[0])
    check(ev[1]["joined"] == ["roster", 1, 0] and close(ev[1]["hp"], 10 * hp_time(tl, 300)), "two rows open: the heavier (b, 8 over 5) lends its numbers: %s" % ev[1])
    check(ev[2]["joined"] == ev[1]["joined"], "the creature's default code is its own look: %s" % ev[2])
    check(ev[3]["joined"] == ["roster", 2, 0] and ev[4]["joined"] is None and close(ev[4]["hp"], 10 * hp_time(tl, 350)),
          "another look joins only a row in that look: %s / %s" % (ev[3], ev[4]))
    check(not ev[5]["hpJoined"] and ev[5]["dmgJoined"] and close(ev[5]["hp"], 50) and close(ev[5]["atk"], 3 * dt(300)),
          "an event's own hp is its own; the half it leaves alone joins: %s" % ev[5])
    check(ev[6]["joined"] is None and close(ev[6]["atk"], 3 * dt(350) * 2), "both halves its own: no join: %s" % ev[6])
    check(ev[7]["joined"] is None, "a row at weight 0 brings nothing: %s" % ev[7])
    check(ev[8]["joined"] == ["wave", 0, 0] and close(ev[8]["atk"], 9) and close(ev[8]["hp"], 10 * hp_time(tl, 700)), "no row: an open wave lends its numbers: %s" % ev[8])
    check(ev[10]["joined"] == ["roster", 3, 0] and close(ev[10]["hp"], 20 * hp_time(tl, 1376)) and close(ev[10]["hpFrom"], 1376),
          "in endless the joined row is fixed afresh at the wave's start: %s" % ev[10])
    check(ev[11]["joined"] == ["wave", 1, 1] and close(ev[11]["share"], 0.75) and ev[12]["joined"] == ["wave", 1, 0],
          "a wave's alternative that brings the creature in that look joins (its share of the roll): %s / %s" % (ev[11], ev[12]))
    check(ev[13]["joined"] is None and ev[14]["joined"] is None, "an Elite by its kind, or an unknown creature, never joins: %s / %s" % (ev[13], ev[14]))
    check(ev[15]["joined"] == ev[1]["joined"], "an unknown code is the creature's own look: %s" % ev[15])
    expect_kb = [3.4, 5.5, 7.0, 2.5, 3.0, 6.8]
    for (c, st), got, want in zip(q["knock"], res["knock"], expect_kb):
        check(close(got["value"], want, 1e-6), "knockback of %s with %s: %s, want %s" % (c, st, got, want))
    seeded = res["seed"][0]
    check([p[0] for p in seeded] == [0, 430, 860, 1290], "seed points at the stage marks: %s" % seeded)
    check(all(close(p[1], round(curve_mult({"mode": "formula", "formula": {"kind": "power", "a": 0.0977, "b": 1.25}}, p[0]), 4), 1e-12) for p in seeded),
          "seed points on the formula, 4 decimals: %s" % seeded)


# ---------------------------------------------------------------- the "Spawned so far" estimate (pass 57)

ESTIMATE_RUNNER = r"""
const M = require(process.argv[2]);
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const t0 = Date.now();
  const ests = q.cases.map(([tl, cr, opts]) => M.spawnEstimate(tl, cr, opts));
  const out = ests.map((e) => ({ points: e.points, ids: e.ids, marks: e.marks, fights: e.fights, colourAt: e.colourAt }));
  // pass 58: the Actual HP x / ATK x lanes read the estimate's per-source tallies
  const byIdOf = (cr) => { const m = {}; for (const c of cr) m[c.id] = c; return m; };
  const actual = (q.actual || []).map(([k, t, win]) => {
    const a = M.actualAt(q.cases[k][0], byIdOf(q.cases[k][1]), ests[k], t, win);
    return { hp: a.hp, atk: a.atk, total: a.total, rows: a.rows.map((r) => ({ key: r.key, n: r.n, hp: r.hp, atk: r.atk, share: r.share, t0: r.t0, start: r.start })) };
  });
  const series = (q.series || []).map(([k, end, step, win]) => M.actualSeries(q.cases[k][0], byIdOf(q.cases[k][1]), ests[k], end, step, win));
  const at = q.at.map(([k, t, before]) => { const e = M.spawnEstimate(q.cases[k][0], q.cases[k][1], q.cases[k][2]); const p = M.estimateAt(e, t, before); return [p.t, p.after, p.all]; });
  const brood = q.brood.map(([script, cd, secs, pace]) => M.bossBrood(script, cd, secs, pace));
  process.stdout.write(JSON.stringify({ out, at, brood, actual, series, ms: Date.now() - t0 }));
});
"""

# the hand-checked case: one row of a pack-10 creature under a flat cap of 10, bursts of exactly 10 load every 0.5 s,
# 10 % of the crowd killed a second (0.5 % a step): the first burst fills the crowd to 10, then every burst refills what
# the ten steps since killed, 10 x (1 - 0.995^10)
EST_A_TL = {"stage_length": 100, "stages": 1, "cap_curve": [[0, 10]], "cap_max": 100, "hard_cap": 300, "burst_min": 10,
            "burst_max": 10, "spawn_interval": 0.5, "colour_after_kills": 5,
            "roster": [{"id": "r1", "t": 0, "enemy": "a", "weights": [[0, 1]]}],
            "events": [{"t": 30, "type": "swarm", "enemy": "b", "count": 20}, {"t": 40, "type": "elite_boss", "enemy": "e"},
                       {"t": 50, "type": "boss", "enemy": "z"}],
            "boss_cap_frac": 0.5, "portal_cap": 0}
EST_A_CR = [{"id": "a", "kind": "enemy", "archetype": "walker", "cap_share": 1, "pack_size": 10, "max_alive": 0, "variance": {"special_chance": 0.1}},
            {"id": "b", "kind": "enemy", "archetype": "walker", "cap_share": 1, "pack_size": 5},
            {"id": "e", "kind": "enemy", "archetype": "elite", "cap_share": 1, "pack_size": 1},
            {"id": "z", "kind": "boss", "archetype": "boss", "cap_share": 1, "pack_size": 1}]

# every rule at once on a small two-stage map: waves (alternatives, count, until, every 0, no cap, an elite modifier,
# the hell channel), held elites, elite_every with [min, max] and formats, swarms (the map's skin, a weighted list at
# 50 %), an Elite pair by weights, a boss under 0.5 (no fight), an event dated on a boss (after the portal), the map's
# boss, the specials with a stage-2 pool row, a max_alive row, single / scatter / ring / in_front rows, the portal cap
# for 10 s of the wait, then endless
EST_C_CR = [
    {"id": "fod", "kind": "enemy", "archetype": "walker", "cap_share": 0.5, "pack_size": 5, "max_alive": 0, "variance": {"special_chance": 0.1, "tints": ["#ff0000"]}},
    {"id": "tank", "kind": "enemy", "archetype": "tank", "cap_share": 1.0, "pack_size": 2, "max_alive": 0, "variance": {"special_chance": 0.05}},
    {"id": "big", "kind": "enemy", "archetype": "brute", "cap_share": 2.5, "pack_size": 1, "max_alive": 2, "can_be_elite": False, "variance": {}},
    {"id": "hellish", "kind": "enemy", "archetype": "runner", "cap_share": 0.6, "pack_size": 6, "variance": {"special_chance": 0.08}},
    {"id": "eli", "kind": "enemy", "archetype": "elite", "cap_share": 1.0, "pack_size": 1, "variance": {}},
    {"id": "eli2", "kind": "enemy", "archetype": "elite", "cap_share": 1.0, "pack_size": 1},
    {"id": "spec", "kind": "enemy", "archetype": "spitter", "cap_share": 1.0, "pack_size": 1, "max_alive": 1, "can_be_elite": False},
    {"id": "spec2", "kind": "enemy", "archetype": "brute", "cap_share": 1.0, "pack_size": 1, "max_alive": 1},
    {"id": "bossy", "kind": "boss", "archetype": "boss", "cap_share": 1.0, "pack_size": 1,
     "boss": {"cooldown_between": 2.0, "script": [{"name": "roll", "windup": 1.0, "duration": 1.2}, {"name": "spawn_ring", "windup": 0.8, "count": 5, "enemy": "fod"}]}},
    {"id": "bossy2", "kind": "boss", "archetype": "boss", "cap_share": 1.0, "pack_size": 1},
]
EST_C_TL = {
    "stage_length": 120, "stages": 2, "cap_curve": [[0, 8], [60, 30], [120, 40], [200, 60]], "cap_max": 50, "hard_cap": 90,
    "boss_cap_frac": 0.5, "burst_min": 2, "burst_max": 7, "spawn_interval": 0.7, "hell_cap": [0, 0.5], "colour_after_kills": 20,
    "portal_cap": -1, "portal_spawn_seconds": 10,
    "specials": {"from": 40, "interval": [10, 20], "max_alive": 1, "pool": [{"enemy": "spec"}, {"enemy": "spec2", "stage": 2}]},
    "roster": [
        {"id": "r1", "t": 0, "until": 100, "enemy": "fod", "weights": [[0, 6], [80, 2]]},
        {"id": "r2", "t": 20, "enemy": "tank", "weights": [[20, 0], [50, 3]], "pattern": "single",
         "stats": {"variance": {"special_chance": 0.3}, "elite_formats": {"single": 1, "pack": 1}}},
        {"id": "r3", "t": 30, "enemy": "big", "weights": [[30, 1]], "pattern": "scatter"},
        {"id": "r4", "t": 100, "enemy": "fod", "weights": [[100, 4]], "pattern": "ring", "pack": 8,
         "stats": {"cap_share": 1.0, "elite_weight": 3, "elite_formats": {"ring": 1}}},
        {"id": "r5", "t": 120, "enemy": "hellish", "weights": [[120, 5]], "channel": "hell", "pattern": "in_front"},
    ],
    "waves": [
        {"id": "w1", "t": 10, "count": 12, "burst": 4, "every": 3,
         "alts": [{"chance": 0.75, "enemy": "fod", "pack": 4}, {"chance": 0.25, "enemy": "tank", "stats": {"cap_share": 2}}]},
        {"id": "w2", "t": 70, "until": 90, "burst": 6, "every": 5, "respect_cap": False, "enemy": "tank", "elite": "random"},
        {"id": "w3", "t": 130, "count": 10, "burst": 10, "every": 0, "channel": "hell", "enemy": "hellish"},
    ],
    "events": [
        {"t": 5, "type": "elite", "enemy": "tank"},
        {"t": 45, "type": "elite_every", "interval": [20, 40]},
        {"t": 50, "type": "swarm", "count": 15},
        {"t": 55, "type": "swarm", "enemy": ["fod", "tank"], "weights": [3, 1], "count": 12, "chance": 0.5},
        {"t": 60, "type": "elite_boss", "enemy": ["eli", "eli2"], "weights": [2, 1]},
        {"t": 70, "type": "boss", "enemy": "bossy", "chance": 0.3},
        {"t": 120, "type": "boss", "enemy": "bossy"},
        {"t": 120, "type": "swarm", "enemy": "fod", "count": 10},
        {"t": 240, "type": "boss"},
    ],
}
EST_C_OPTS = {"turnover": [0.05, 0.08], "bossSeconds": 20, "portalSeconds": 15, "skin": "fod", "boss": "bossy2", "end": 400}

# pass 58, the Actual lanes by hand: three rows of one pack-5 creature at equal weights (so every burst gives each open row
# the same), A plain from 0:00, B with hp 30 / damage 4 (x3 / x2 of the JSON's 10 / 2), C plain from 0:50 (its multiples
# the curves at 0:50 for good: x1.5 HP, x2 ATK); a no-cap wave of 2 a second from 0:30 to 0:40 with hp_mult 2 (x2.6)
EST_D_TL = {"stage_length": 100, "stages": 1, "cap_curve": [[0, 10]], "cap_max": 100, "hard_cap": 300, "burst_min": 10,
            "burst_max": 10, "spawn_interval": 0.5, "hp_curve": {"mode": "points", "points": [[0, 1], [100, 2]]},
            "damage_curve": {"mode": "points", "points": [[0, 1], [100, 3]]},
            "roster": [{"id": "rA", "t": 0, "enemy": "a", "weights": [[0, 1]]},
                       {"id": "rB", "t": 0, "enemy": "a", "weights": [[0, 1]], "stats": {"hp": 30, "damage": 4}},
                       {"id": "rC", "t": 50, "enemy": "a", "weights": [[50, 1]]}],
            "waves": [{"id": "w1", "t": 30, "until": 40, "burst": 2, "every": 1, "respect_cap": False, "enemy": "a", "stats": {"hp_mult": 2}}]}
EST_D_CR = [{"id": "a", "kind": "enemy", "archetype": "walker", "hp": 10, "damage": 2, "cap_share": 1, "pack_size": 5, "max_alive": 0}]


def est_close(a, b, eps=1e-9):
    if a is None or b is None:
        return a is b
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


def estimate_diff(js, py):
    """Where the page's estimate and the Python copy differ (empty: they agree)."""
    out = []
    if len(js["points"]) != len(py["points"]):
        return ["%d points against %d" % (len(js["points"]), len(py["points"]))]
    for pj, pp in zip(js["points"], py["points"]):
        if pj["t"] != pp["t"] or pj["after"] != pp["after"]:
            out.append("point at %s/%s after %s/%s" % (pj["t"], pp["t"], pj["after"], pp["after"]))
            break
        for k in ("all", "reg", "col", "mod", "elite", "special", "boss", "minion", "kills", "alive"):
            if not est_close(pj[k], pp[k]):
                out.append("%s at %s: js %s py %s" % (k, pj["t"], pj[k], pp[k]))
        if set(pj["by"]) != set(pp["by"]):
            out.append("ids at %s: js %s py %s" % (pj["t"], sorted(pj["by"]), sorted(pp["by"])))
        else:
            for cid in pj["by"]:
                if not all(est_close(x, y) for x, y in zip(pj["by"][cid], pp["by"][cid])):
                    out.append("%s at %s: js %s py %s" % (cid, pj["t"], pj["by"][cid], pp["by"][cid]))
        # pass 58: what each roster row and wave alternative spawned (the Actual lanes' weights)
        sj, sp = pj.get("src", {}), pp.get("src", {})
        if set(sj) != set(sp):
            out.append("sources at %s: js %s py %s" % (pj["t"], sorted(sj), sorted(sp)))
        else:
            for key in sj:
                if not est_close(sj[key], sp[key]):
                    out.append("source %s at %s: js %s py %s" % (key, pj["t"], sj[key], sp[key]))
        if len(out) > 5:
            break
    if js["ids"] != py["ids"]:
        out.append("ids order: js %s py %s" % (js["ids"], py["ids"]))
    if len(js["marks"]) != len(py["marks"]):
        out.append("%d marks against %d" % (len(js["marks"]), len(py["marks"])))
    else:
        for mj, mp in zip(js["marks"], py["marks"]):
            if not (est_close(mj["t"], mp["t"]) and mj["kind"] == mp["kind"] and mj["id"] == mp["id"] and est_close(mj["n"], mp["n"])):
                out.append("mark js %s py %s" % (mj, mp))
                break
    if len(js["fights"]) != len(py["fights"]) or not all(est_close(a["t"], b["t"]) and a["boss"] == b["boss"] and est_close(a["spawned"], b["spawned"])
                                                       for a, b in zip(js["fights"], py["fights"])):
        out.append("fights js %s py %s" % (js["fights"], py["fights"]))
    if not est_close(js["colourAt"], py["colourAt"]):
        out.append("colour js %s py %s" % (js["colourAt"], py["colourAt"]))
    return out


def point_at(est, t, before=False):
    pts = est["points"]
    best = 0
    for i, p in enumerate(pts):
        if p["t"] <= t:
            best = i
    if before and pts[best]["t"] == t:
        while best > 0 and pts[best - 1]["t"] == pts[best]["t"]:
            best -= 1
    return pts[best]


def estimate_checks():
    rc = server.load_json(server.map_path("red_canyon"))
    rc_tl = rc.get("timeline_data", {})
    creatures = server.list_creatures()
    skin = list((rc.get("skins") or {}).values())[0] if rc.get("skins") else ""
    rc_opts = {"turnover": 0.0557, "bossSeconds": 44.2, "portalSeconds": 34.9, "skin": skin, "boss": rc.get("boss", "")}
    cases = [
        [EST_A_TL, EST_A_CR, {"turnover": 0.1, "bossSeconds": 10, "portalSeconds": 5, "end": 70}],
        [EST_A_TL, EST_A_CR, {"turnover": 0, "end": 45}],
        [EST_C_TL, EST_C_CR, EST_C_OPTS],
        [rc_tl, creatures, rc_opts],
        [rc_tl, creatures, dict(rc_opts, turnover=[0.0573, 0.0441])],
        [rc_tl, creatures, dict(rc_opts, turnover=[[30, 0.03], [90, 0.07], [330, 0.09], [600, 0.05]])],
        [EST_C_TL, EST_C_CR, dict(EST_C_OPTS, turnover=7, bossSeconds=1e9, portalSeconds=-5, end=300)],
        [EST_D_TL, EST_D_CR, {"turnover": 0.1, "end": 100}],
    ]
    king = [{"name": "roll", "windup": 1.0, "duration": 1.2}, {"name": "tumbleweed_volley", "windup": 0.8, "count": 12},
            {"name": "spawn_ring", "windup": 0.8, "count": 12, "enemy": "tumbleweed_minion"}, {"name": "slam", "windup": 1.2}]
    brood_cases = [[king, 2.0, 44.2, 0.9], [king, 2.0, 10.0, 0.9], [king, 1.0, 44.2, 1.0], [[{"name": "erupt", "windup": 1.0, "count": 6, "interval": 0.5, "spawn": "imp"}], 3.0, 20, 1.0], [[], 2.0, 60, 1.0]]
    actual_q = [[7, 20, 10], [7, 70, 10], [7, 35, 10], [7, 2, 10], [3, 200, 10], [3, 450, 10], [3, 900, 10], [3, 1300, 10],
                [3, 60, 4], [2, 45, 10], [2, 135, 10], [2, 75, 6], [5, 330, 10], [3, 1420, 10]]
    q = {"cases": cases, "at": [[0, 50, True], [0, 50, False], [0, 50.5, True], [0, 49.99, False], [3, 430, True], [3, 430, False]], "brood": brood_cases,
         "actual": actual_q, "series": [[3, 1500, 5, 10], [7, 100, 1, 10]]}
    res = run_node(q, ESTIMATE_RUNNER)
    if res is None:
        print("node not found: the estimate's model.js checks are skipped")
        return
    if not res:
        return
    names = ["hand-checked", "nothing dies", "every rule", "Red Canyon flat", "Red Canyon per stage", "Red Canyon curve", "silly numbers", "Actual by hand"]
    import time
    t0 = time.time()
    pys = [spawn_estimate(tl, cr, opts) for tl, cr, opts in cases]
    py_secs = time.time() - t0
    print("estimate: model.js %d ms for %d runs (and %d lookups), the Python copy %.1f s" % (res["ms"], len(cases), len(q["at"]), py_secs))
    for name, js, py in zip(names, res["out"], pys):
        diff = estimate_diff(js, py)
        check(not diff, "the estimate of %s: model.js and the Python copy agree: %s" % (name, diff[:6]))
        # the books balance at every point: the total is its four parts and the sum of the creatures
        bad = [p["t"] for p in js["points"] if not (est_close(p["all"], p["reg"] + p["elite"] + p["special"] + p["boss"], 1e-9)
                                                     and est_close(p["all"], sum(v[0] for v in p["by"].values()), 1e-9)
                                                     and p["col"] <= p["reg"] + 1e-9 and p["mod"] <= p["reg"] + 1e-9)]
        check(not bad, "%s: every point's total is its parts and its creatures (first bad at %s)" % (name, bad[:3]))
        alls = [p["all"] for p in js["points"]]
        check(all(b >= a - 1e-9 for a, b in zip(alls, alls[1:])), "%s: the total never falls" % name)
        ts = [p["t"] for p in js["points"]]
        check(all(b >= a for a, b in zip(ts, ts[1:])), "%s: the points run in clock order" % name)

    # the hand-checked numbers
    a = res["out"][0]
    refill = 10 - 10 * 0.995 ** 10
    p29 = point_at(a, 29)
    # bursts at steps 1, 11, ..., 571 by 29 s (k = 580): 58 bursts, the first fills 10, the other 57 refill
    check(est_close(p29["all"], 10 + 57 * refill, 1e-9), "hand-checked: 10 + 57 refills of 10 x (1 - 0.995^10) by 0:29: %s, want %s" % (p29["all"], 10 + 57 * refill))
    check(est_close(p29["alive"], 10 * 0.995 ** 9, 1e-9), "hand-checked: nine steps after the last refill 10 x 0.995^9 alive: %s" % p29["alive"])
    check(est_close(p29["kills"], p29["all"] - p29["alive"], 1e-9), "hand-checked: what spawned and is not alive was killed")
    p30, p31 = point_at(a, 30), point_at(a, 31)
    check(est_close(p30["by"].get("b", [0])[0], 20, 1e-12), "hand-checked: the swarm brings its 20 at 0:30 on top of the cap: %s" % p30["by"].get("b"))
    check(p31["by"]["a"][0] - p30["by"]["a"][0] < 1e-9, "hand-checked: the swarm over the cap stops the roster's refills for a while")
    check(point_at(a, 39)["elite"] == 0 and point_at(a, 40)["elite"] == 1, "hand-checked: the Elite at 0:40")
    pb, pa = point_at(a, 50, True), point_at(a, 50)
    check(pb["boss"] == 1 and pa["after"] and pa["t"] == 50 and not pb["after"], "hand-checked: the boss at 0:50, a point before and after its fight")
    check(len(a["fights"]) == 1 and a["fights"][0]["seconds"] == 10 and a["fights"][0]["portal"] == 5, "hand-checked: one fight of 10 s and a 5 s wait: %s" % a["fights"])
    check(est_close(a["colourAt"], 5.05, 1e-9) or (a["colourAt"] is not None and 4 < a["colourAt"] < 6),
          "hand-checked: colour after the 5th kill, about 5 s in (10 a second x 0.5 %% a step): %s" % a["colourAt"])
    # coloured: 10 % of what spawned once colour came (the first refill after it)
    pc = point_at(a, 29)
    before_colour = point_at(a, math.floor(a["colourAt"]))
    want = 0.1 * (pc["by"]["a"][0] - before_colour["by"]["a"][0])
    check(abs(pc["col"] - want) <= 0.1 * refill + 1e-9, "hand-checked: 10 %% of the spawns after colour came are coloured: %s, want about %s" % (pc["col"], want))
    z = res["out"][1]
    check(all(est_close(p["by"].get("a", [0])[0], 10, 1e-12) for p in z["points"] if 1 <= p["t"] < 30), "nothing dies: the crowd fills to the cap once and nothing more comes")
    check(est_close(point_at(z, 31)["all"], 30, 1e-12) and est_close(point_at(z, 44)["all"], 31, 1e-12), "nothing dies: the swarm's 20 and the Elite still come")
    # the lookups: at a fight's own second the point before it unless asked for after, past it the point after
    at = res["at"]
    check(at[0][2] == pb["all"] and not at[0][1] and at[1][1] and at[1][2] == pa["all"], "estimateAt at a fight's second: before %s / after %s" % (at[0], at[1]))
    check(at[2][1] and at[2][2] == pa["all"] and at[3][0] == 49, "estimateAt just past and just before the fight: %s %s" % (at[2], at[3]))
    check(at[4][0] == 430 and not at[4][1] and at[5][1], "estimateAt on Red Canyon's first boss: %s %s" % (at[4], at[5]))

    # a boss's own script: the King on Red Canyon's pace 0.9 rings 12 minions every 4 x 2 s of cooldown plus the wind-ups
    # (1.0 + 0.8 + 0.8 + 1.2) / 0.9 and the roll's 1.2 / 0.9: the first ring as its wind-up ends, 2 + (1.0 + 1.2) / 0.9 + 2
    # + 0.8 / 0.9 + 2 + 0.8 / 0.9 = 10.22 s in, then one a cycle of 8 + 3.8 / 0.9 + 1.2 / 0.9 = 13.56 s
    br = res["brood"]
    first = 2 + (1.0 + 1.2) / 0.9 + 2 + 0.8 / 0.9 + 2 + 0.8 / 0.9
    cyc = 8 + 3.8 / 0.9 + 1.2 / 0.9
    check([round(b["t"], 6) for b in br[0]] == [round(first + k * cyc, 6) for k in range(3)] and all(b["n"] == 12 and b["id"] == "tumbleweed_minion" for b in br[0]),
          "the King's script in a 44.2 s fight: three rings of 12 (as the records show: 36 minions in a 44 s fight): %s" % br[0])
    check(br[1] == [], "a fight over before the first ring brings none: %s" % br[1])
    check([round(b["t"], 6) for b in br[2]] == [7.8, 16.8, 25.8, 34.8, 43.8], "a 1 s cooldown at pace 1: a 9 s cycle, five rings in 44.2 s: %s" % [round(b["t"], 2) for b in br[2]])
    # an eruption holds the caster for its strikes: 1 + 6 x 0.5 + 0.55 + 0.3 = 4.85 s, so one every 7.85 s from 3 s
    check([round(b["t"], 6) for b in br[3]] == [3, 10.85, 18.7] and br[3][0]["id"] == "imp" and br[3][0]["n"] == 6, "an eruption with a spawn brings one a strike: %s" % br[3])
    check(br[4] == [], "no script, no minions")
    for (script, cd, secs, pace), got in zip(brood_cases, br):
        py = boss_brood(script, cd, secs, pace)
        check(len(py) == len(got) and all(est_close(a["t"], b["t"]) and a["n"] == b["n"] and a["id"] == b["id"] for a, b in zip(py, got)), "boss_brood agrees with bossBrood: %s vs %s" % (py, got))
    silly = res["out"][6]
    check(all(f["seconds"] == 1800 and f["portal"] == 0.05 for f in silly["fights"]) and all(p["alive"] >= 0 for p in silly["points"]),
          "a 1e9 s fight is kept to half an hour, a negative wait to a step, a 700 %% kill rate to the whole crowd: %s" % [(f["seconds"], f["portal"]) for f in silly["fights"]])
    rc_est = res["out"][3]
    f430 = [f for f in rc_est["fights"] if f["t"] == 430]
    check(f430 and f430[0]["minions"] > 0, "Red Canyon's first fight brings the King's minions: %s" % (f430[0] if f430 else None))

    # every rule: the parts each did what they should
    c = res["out"][2]
    kinds = {}
    for m in c["marks"]:
        kinds.setdefault(m["kind"], []).append(m)
    check([m["t"] for m in kinds.get("swarm", [])][:3] == [50, 55, 120.05], "every rule: swarms at 0:50, 0:55 (its 50 %%) and the one dated on the boss after the portal: %s" % [(m["t"], m["n"]) for m in kinds.get("swarm", [])])
    sw = kinds.get("swarm", [])
    check(len(sw) >= 2 and est_close(sw[1]["n"], 6, 1e-12) and sw[0]["id"] == "fod", "every rule: the skin's swarm, and 12 x 50 %% = 6 from the list: %s" % [(m["id"], m["n"]) for m in sw])
    check([f["boss"] for f in c["fights"]] == ["bossy", "bossy2", "bossy"], "every rule: the 30 %% boss never fights; the map's boss at 4:00; endless brings the timeline's: %s" % [(f["t"], f["boss"]) for f in c["fights"]])
    el = kinds.get("elite", [])
    check(len(el) >= 1 and el[0]["t"] == 60 and el[0]["id"] == "eli", "every rule: the Elite pair at 1:00: %s" % el[:1])
    p60 = point_at(c, 61)
    check(est_close(p60["by"].get("eli", [0])[0], 2 / 3, 1e-12) and est_close(p60["by"].get("eli2", [0])[0], 1 / 3, 1e-12), "every rule: the Elites split 2 : 1: %s %s" % (p60["by"].get("eli"), p60["by"].get("eli2")))
    mods = kinds.get("mod", [])
    check(mods and mods[0]["t"] >= c["colourAt"] and mods[0]["t"] > 5, "every rule: the 0:05 elite waits for colour (opened %s): first at %s" % (c["colourAt"], mods[0]["t"] if mods else None))
    sp = kinds.get("special", [])
    # the countdown starts on the step that reaches 0:40 and spends its first step there, as the game's frame does
    check(sp and abs(sp[0]["t"] - 55) <= 0.05 + 1e-9 and sp[0]["id"] == "spec", "every rule: the first special 15 s after 0:40: %s" % sp[:1])
    check(any(m["id"] == "spec/spec2" for m in sp), "every rule: stage 2 adds its own special to the pool")
    big = [p["by"].get("big", [0])[0] for p in c["points"]]
    check(max(big) > 0, "every rule: the max_alive row spawns")
    p125 = point_at(c, 140)
    check(p125["by"].get("hellish", [0])[0] > 0 and point_at(c, 119)["by"].get("hellish", [0])[0] == 0, "every rule: the hell row only from stage 2, where hell_cap opens")
    check(p125["col"] > 0 and point_at(c, 15)["col"] == 0, "every rule: no colour before 20 kills, colour after")
    check(point_at(c, 89)["mod"] > point_at(c, 69)["mod"], "every rule: the elite wave's tanks wear their modifier")
    w1 = point_at(c, 45)
    check(w1["by"]["fod"][0] > 0 and w1["by"]["tank"][0] > 0, "every rule: the wave's two alternatives both count, by their chances")
    fb = [f for f in c["fights"] if f["boss"] == "bossy"]
    # bossy's 20 s fight: roll at 2 (busy 2.2), ring at 2 + 2.2 + 2 + 0.8 = 7.0, next ring 4.4 + 2.2 + 0.8 + ... = 7.0 + 0.8 + 2 + 2.2 + 2 + 0.8 = 14.8
    check(fb and est_close(fb[0]["minions"], 10, 1e-9), "every rule: bossy's script rings 5 twice in its 20 s fight: %s" % fb[:1])
    mb = [f for f in c["fights"] if f["boss"] == "bossy2"]
    check(mb and mb[0]["minions"] == 0, "every rule: a boss without a script brings none")

    # pass 58: the per-source tallies and the Actual HP x / ATK x lanes
    for name, js in zip(names, res["out"]):
        bad = []
        for p in js["points"]:
            reg = sum(v for k, v in p["src"].items())
            if reg > p["reg"] + 1e-6:
                bad.append(p["t"])
        check(not bad, "%s: the rows' and waves' tallies never pass the regular crowd spawned (first bad at %s)" % (name, bad[:3]))
    d = res["out"][7]
    p40 = point_at(d, 40)
    check(est_close(p40["src"].get("wave:0:0", 0), 20, 1e-12), "Actual by hand: the wave's 10 bursts of 2 are its tally: %s" % p40["src"].get("wave:0:0"))
    pa = point_at(d, 49)
    check(est_close(pa["src"]["roster:0"], pa["src"]["roster:1"], 1e-12) and "roster:2" not in pa["src"],
          "Actual by hand: two rows at equal weights spawn the same; C not yet: %s" % pa["src"])
    pb = point_at(d, 90)
    check(est_close(pb["src"]["roster:2"] - point_at(d, 60)["src"]["roster:2"], pb["src"]["roster:0"] - point_at(d, 60)["src"]["roster:0"], 1e-12),
          "Actual by hand: three rows at equal weights spawn the same: %s" % pb["src"])
    act = {tuple(k[:2]): a for k, a in zip(actual_q, res["actual"])}
    a20, a70, a35, a2 = act[(7, 20)], act[(7, 70)], act[(7, 35)], act[(7, 2)]
    check(est_close(a20["hp"]["avg"], 2.0, 1e-12) and est_close(a20["hp"]["max"], 3.0, 1e-12), "Actual HP at 0:20: half x1, half x3 = avg x2, max x3: %s" % a20["hp"])
    check(est_close(a20["atk"]["avg"], 1.5, 1e-12) and est_close(a20["atk"]["max"], 2.0, 1e-12), "Actual ATK at 0:20: avg x1.5, max x2: %s" % a20["atk"])
    check(est_close(a70["hp"]["avg"], (1 + 3 + 1.5) / 3, 1e-12) and est_close(a70["hp"]["max"], 3.0, 1e-12),
          "Actual HP at 1:10: C keeps the curve of its start 0:50 (x1.5, while the curve says x1.7): avg %s" % a70["hp"])
    check(est_close(a70["atk"]["avg"], (1 + 2 + 2) / 3, 1e-12) and est_close(a70["atk"]["max"], 2.0, 1e-12), "Actual ATK at 1:10: (1 + 2 + 2) / 3: %s" % a70["atk"])
    w35 = [r for r in a35["rows"] if r["key"] == "wave:0:0"]
    # the window is 0:30 to 0:40: the point at 0:30 already holds the first burst, the wave ends before 0:40's, so 9 x 2
    check(w35 and est_close(w35[0]["hp"], 1.3 * 2, 1e-12) and est_close(w35[0]["n"], 18, 1e-12) and est_close(w35[0]["t0"], 30, 1e-12),
          "Actual at 0:35: the wave's 18 in the window carry x2.6 (the curve at its start 0:30 x hp_mult 2): %s" % w35)
    # the no-cap wave keeps the crowd over the cap of 10 from 0:30, so the roster refills nothing until it has thinned:
    # the window holds the wave alone (avg = max = x2.6); at 0:25 its first burst weighs in beside A and B
    check(len(a35["rows"]) == 1 and est_close(a35["hp"]["max"], 2.6, 1e-12) and est_close(a35["hp"]["avg"], 2.6, 1e-12) and abs(sum(r["share"] for r in a35["rows"]) - 1) < 1e-9,
          "Actual at 0:35: the wave alone over the cap: %s" % [(r["key"], r["n"]) for r in a35["rows"]])
    check(a2["hp"]["avg"] is not None and a2["total"] > 0, "Actual at 0:02: the window starts at 0:00: %s" % a2["hp"])
    # the page and the Python copy agree on every sample
    by_ids = [{c0["id"]: c0 for c0 in cr} for _tl, cr, _o in cases]
    for (k, t, win), got in zip(actual_q, res["actual"]):
        py = actual_at(cases[k][0], by_ids[k], pys[k], t, win)
        same = len(py["rows"]) == len(got["rows"]) and all(est_close(a, b) for a, b in [(got["hp"]["avg"], py["hp"]["avg"]), (got["hp"]["max"], py["hp"]["max"]), (got["atk"]["avg"], py["atk"]["avg"]), (got["atk"]["max"], py["atk"]["max"])])
        check(same, "actualAt(%s at %s, window %s): js hp %s atk %s (%d rows), py hp %s atk %s (%d rows)" % (names[k], t, win, got["hp"], got["atk"], len(got["rows"]), py["hp"], py["atk"], len(py["rows"])))
    # lane WV's fix round: in endless every row is fixed afresh at its wave's start (Red Canyon: 21:30 + 86 s a wave)
    rc_tl = cases[3][0]
    rc_end = float(rc_tl.get("stage_length", 300)) * int(rc_tl.get("stages", 3))
    rc_ews = max(float(rc_tl.get("endless_wave_seconds", 60)), 1.0)
    w_start = rc_end + math.floor((1420 - rc_end) / rc_ews) * rc_ews
    rows1420 = act[(3, 1420)]["rows"]
    check(rows1420 and all(est_close(r["t0"], max(r["start"], w_start), 1e-12) for r in rows1420),
          "Actual in endless: every row at 23:40 fixed from its wave's start %s: %s" % (w_start, [(r["key"], r["start"], r["t0"]) for r in rows1420]))
    rc200 = act[(3, 200)]
    check(rc200["hp"]["max"] is not None and rc200["hp"]["max"] >= rc200["hp"]["avg"] - 1e-12, "Red Canyon at 3:20: the max is never under the average: %s" % rc200["hp"])
    ser = res["series"][1]
    check(len(ser["ts"]) == 101 and est_close(ser["hp"]["avg"][20], a20["hp"]["avg"], 1e-12) and est_close(ser["hp"]["max"][70], 3.0, 1e-12),
          "actualSeries samples actualAt each second: %d samples" % len(ser["ts"]))
    rs = res["series"][0]
    check(all(m is None or a is None or m >= a - 1e-9 for a, m in zip(rs["hp"]["avg"], rs["hp"]["max"])), "Red Canyon: the HP max never under the average")


def fit_checks():
    """fit_turnover on hand-made records: the pooled kill rate, the stages, the curve, the fights and waits, which
    records count and the fallback."""
    tmp = tempfile.mkdtemp(prefix="le_fit_")

    def rec(name, kills, alive, n=120, mapid="red_canyon", headless=False, start=0.0, jump=False, boss=None, stage2=0):
        samples = []
        for i in range(n):
            t = start + i + 1.0
            samples.append({"t": t, "clock": t + (500 if jump and i == 5 else 0), "stage": 1, "killed": {"x": kills}, "alive_by": {"x": alive / 2, "y": alive / 2}, "alive": alive + 3})
        for i in range(stage2):
            t = start + n + i + 1.0
            samples.append({"t": t + 60, "clock": t, "stage": 2, "killed": {"x": kills * 2}, "alive_by": {"x": alive}, "alive": alive})
        samples.append({"t": n + 1.0, "clock": n * 1.0, "stage": 1, "phase": 1, "killed": {"x": 99}, "alive_by": {"x": 1}})
        events = []
        if boss:
            events = [{"kind": "boss_start", "t": boss[0]}, {"kind": "boss_end", "t": boss[1]}, {"kind": "portal", "t": boss[2]}]
        with open(os.path.join(tmp, name), "w", encoding="utf-8") as f:
            json.dump({"schema": 1, "map": mapid, "hero": "astro", "version": "0.42", "result": "death", "length": n,
                       "headless": headless, "samples": samples, "events": events}, f)

    try:
        empty = server.fit_turnover("red_canyon", runs_dir=tmp)
        check(empty["source"] == "fallback" and empty["turnover"] == 0.06 and empty["boss_seconds"] == 60 and empty["portal_seconds"] == 30,
              "no records: the fallback 6 %%, 60 s and 30 s: %s" % empty)
        rec("2026-10-01T10-00-00.json", 2, 40, boss=(121, 161, 181))
        rec("2026-10-01T11-00-00.json", 3, 30, boss=(121, 151, 171))
        rec("2026-10-01T12-00-00.json", 50, 10, headless=True)
        rec("2026-10-01T13-00-00.json", 50, 10, mapid="other")
        rec("2026-10-01T14-00-00.json", 50, 10, jump=True)
        rec("2026-10-01T15-00-00.json", 50, 10, n=30)
        f = server.fit_turnover("red_canyon", runs_dir=tmp)
        check(f["source"] == "records" and [r["file"] for r in f["runs"]] == ["2026-10-01T10-00-00.json", "2026-10-01T11-00-00.json"],
              "only Garry's own runs of this map, played as they came, a minute or more: %s" % [r["file"] for r in f["runs"]])
        # pooled: 120 s x (2 kills over 40 alive) and 120 s x (3 over 30): (240 + 360) / (4800 + 3600)
        check(close(f["turnover"], round(600 / 8400, 4)), "the pooled kill rate over the creatures alive (dying left out): %s" % f["turnover"])
        check(f["by_stage"] == [round(600 / 8400, 4)], "one stage of records, one number: %s" % f["by_stage"])
        check([p[0] for p in f["curve"]] == [30, 90] and close(f["curve"][0][1], round(300 / 4200, 4)),
              "minute by minute of the run clock, a minute with under 30 s of records left out: %s" % f["curve"])
        check(f["boss_seconds"] == 35.0 and f["portal_seconds"] == 20.0 and f["fights"] == 2, "the mean fight (40 and 30 s) and wait (20 s): %s %s" % (f["boss_seconds"], f["portal_seconds"]))
        fa = server.fit_turnover("red_canyon", include_headless=True, runs_dir=tmp)
        check(len(fa["runs"]) == 3, "/all takes the tools' headless runs too: %d" % len(fa["runs"]))
        rec("2026-10-01T16-00-00.json", 2, 40, stage2=100)
        f2 = server.fit_turnover("red_canyon", runs_dir=tmp)
        check(len(f2["by_stage"]) == 2 and close(f2["by_stage"][1], 0.1), "a stage with a minute of records gets its own number (4 over 40): %s" % f2["by_stage"])
        for i in range(14):
            rec("2026-10-02T%02d-00-00.json" % i, 1, 50)
        f3 = server.fit_turnover("red_canyon", runs_dir=tmp)
        check(len(f3["runs"]) == server.FIT_MAX_RUNS and f3["runs"][-1]["file"] == "2026-10-02T13-00-00.json",
              "the latest %d runs count: %s .. %s" % (server.FIT_MAX_RUNS, f3["runs"][0]["file"], f3["runs"][-1]["file"]))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- the server


def server_checks():
    recs = {c["id"]: c for c in server.list_creatures()}
    sk = recs.get("skeleton")
    check(sk is not None, "the palette lists the skeleton")
    if sk:
        check(sk["icon_play"] == "/icon/enemy/skeleton/%s" % sk["play"], "the skeleton's in-play icon is its variant's: %s" % sk["icon_play"])
        check(isinstance(sk["variance"], dict) and "tints" in sk["variance"], "the record carries the variance block")
        check(sk["knockback"] is None or isinstance(sk["knockback"], (int, float)), "knockback is a number or null")
        check(any(v.get("ready") for v in sk["variants"]), "the skeleton's variants say which are painted")
    check(not any(cid.startswith("training_dummy") for cid in recs), "no training dummy in the palette")
    # pass 58: the look in play's strip and its cell (the colour preview), every look's strip, the blood colour
    if sk:
        check(sk["sprite_play"] == "/sprite/enemy/skeleton/%s" % sk["play"] and isinstance(sk["frame_px"], int) and sk["frame_px"] > 0,
              "the skeleton's record names its strip in play and its cell: %s %s" % (sk["sprite_play"], sk["frame_px"]))
        check(all(v.get("sprite", "").startswith("/sprite/enemy/skeleton/") for v in sk["variants"]), "every look names its strip")
        sp = server.sprite_path("enemy", "skeleton", sk["play"])
        check(sp is not None and os.path.basename(sp) == "skeleton_sprite_a.png" if sk["play"] == "SK-A" else sp is not None, "the strip in play is on disk: %s" % sp)
        check(os.path.basename(server.sprite_path("enemy", "skeleton", "") or "") == "skeleton_sprite.png", "no code: the top-level strip")
        check(os.path.basename(server.sprite_path("enemy", "skeleton", "NOPE") or "") == "skeleton_sprite.png", "an unknown code: the top-level strip")
    check(server.sprite_path("enemy", "../etc", "") is None and server.sprite_path("elite", "speedy", "") is None, "a bad id or kind has no strip")
    check(all(c["blood"] is None or server.HEX_RE.match(c["blood"]) for c in recs.values()), "every record's blood is #rrggbb or null")
    # a base strip without its own entry is a look of its own
    for c in recs.values():
        if c["variant_base"]:
            check(any(v["code"] == c["variant_base"] for v in c["variants"]), "%s lists its base strip %s" % (c["id"], c["variant_base"]))

    # Save: rows reordered come back matched by id, so a float stays a float
    old = {"timeline_data": {"roster": [{"id": "r1", "t": 0, "weights": [[0, 3.0], [860, 5.0]]}, {"id": "r2", "t": 10, "weights": [[10, 2.0]]}]}}
    new = {"timeline_data": {"roster": [{"id": "r2", "t": 10, "weights": [[10, 2]]}, {"id": "r1", "t": 0, "weights": [[0, 3], [860, 5]]}]}}
    merged = server.restore_numbers(old, new)
    text = json.dumps(merged)
    check('"weights": [[10, 2.0]]' in text and '[[0, 3.0], [860, 5.0]]' in text, "restore_numbers matches reordered rows by id: %s" % text)

    # "Set as default look" on a temporary copy (no Godot: the import is reported as not run)
    tmp = tempfile.mkdtemp(prefix="le_selftest_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        folder = os.path.join(server.CONTENT, "enemies", "testbeast")
        os.makedirs(folder)
        for f in ("a.png", "b.png"):
            open(os.path.join(folder, f), "wb").close()
        d = {"id": "testbeast", "name": "Test Beast", "hp": 10.0, "damage": 3, "variant_base": "TB-0", "variant": "TB-A",
             "variants": {"TB-0": {"note": "base"}, "TB-A": {"sprite": "a.png"}, "TB-B": {"sprite": "b.png"}, "TB-C": {"sprite": "missing.png"}}}
        path = os.path.join(folder, "testbeast.json")
        for crlf, final_nl in ((False, False), (True, True)):
            text = json.dumps(d, indent=2, ensure_ascii=False)
            if final_nl:
                text += "\n"
            if crlf:
                text = text.replace("\n", "\r\n")
            with open(path, "wb") as f:
                f.write(text.encode("utf-8"))
            res = server.write_variant("testbeast", "TB-B")
            check(res.get("ok") and not res.get("import_ok"), "write_variant writes and reports the import it could not run: %s" % res)
            after = open(path, "rb").read().decode("utf-8")
            before_lines, after_lines = text.splitlines(True), after.splitlines(True)
            changed = [(a, b) for a, b in zip(before_lines, after_lines) if a != b]
            check(len(before_lines) == len(after_lines) and len(changed) == 1 and '"TB-B"' in changed[0][1],
                  "only the variant line changes (crlf %s, final newline %s): %s" % (crlf, final_nl, changed))
            check(("\r\n" in after) == crlf and after.endswith("\n") == final_nl, "line endings and final newline kept (crlf %s)" % crlf)
            check(json.loads(after)["hp"] == 10.0 and '"hp": 10.0' in after, "numbers kept as they were")
            check(server.write_variant("testbeast", "TB-0").get("ok"), "the base strip's code can be set")
        check(not server.write_variant("testbeast", "TB-C").get("ok"), "a variant without its strip on disk is refused")
        check(not server.write_variant("testbeast", "TB-Z").get("ok"), "an unknown code is refused")
        check(not server.write_variant("testbeast", "../x").get("ok"), "a bad code is refused")
        check(not server.write_variant("nobody", "TB-A").get("ok"), "an unknown creature is refused")
        # a creature without `variant` gets it just before `variants`
        d2 = {k: v for k, v in d.items() if k != "variant"}
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(d2, indent=2))
        server.write_variant("testbeast", "TB-A")
        keys = list(json.loads(open(path, encoding="utf-8").read()).keys())
        check(keys.index("variant") == keys.index("variants") - 1, "variant added just before variants: %s" % keys)
        check(len([f for f in os.listdir(server.BACKUPS) if f.startswith("testbeast-")]) >= 3, "every write left a backup")

        # pass 58: a file with LF lines and a CRLF only on its last line (fire_ant, the red goblins): the default look
        # changes that one line and keeps every line's own ending (the old re-dump made the whole file CRLF)
        mixed = json.dumps(d, indent=2, ensure_ascii=False) + "\r\n"   # LF lines, the closing brace's line CRLF
        with open(path, "wb") as f:
            f.write(mixed.encode("utf-8"))
        check(mixed.count("\r\n") == 1, "the mixed test file has one CRLF: %d" % mixed.count("\r\n"))
        server.write_variant("testbeast", "TB-B")
        after = open(path, "rb").read().decode("utf-8")
        changed = [(a, b) for a, b in zip(mixed.splitlines(True), after.splitlines(True)) if a != b]
        check(after.count("\r\n") == 1 and len(changed) == 1 and '"TB-B"' in changed[0][1], "mixed line endings kept by the default look: %s" % changed)

        # pass 58, R4: the blood colour, written like the default look
        bfolder = os.path.join(server.CONTENT, "enemies", "bleeder")
        os.makedirs(bfolder)
        bd = {"id": "bleeder", "name": "Bleeder", "hp": 10.0, "damage": 3.0, "knockback": 2.94, "radius": 0.52, "size": 1.75, "drops": {"small": 1.0}, "variance": {"tints": ["#FFFFFF"]}}
        bpath = os.path.join(bfolder, "bleeder.json")
        btext = json.dumps(bd, indent=2, ensure_ascii=False) + "\r\n"   # LF lines, the closing brace's line CRLF (fire_ant's shape)
        with open(bpath, "wb") as f:
            f.write(btext.encode("utf-8"))
        res = server.write_blood("bleeder", "#8a1428")
        after = open(bpath, "rb").read().decode("utf-8")
        a_lines, b_lines = btext.splitlines(True), after.splitlines(True)
        check(res.get("ok") and res.get("blood") == "#8A1428" and res.get("was") is None, "write_blood writes a new colour in capitals, as the files spell theirs: %s" % {k: res.get(k) for k in ("ok", "blood", "was", "error")})
        check(len(b_lines) == len(a_lines) + 1 and all(x in b_lines for x in a_lines), "a missing blood is one new line, every old line kept byte for byte")
        keys = list(json.loads(after).keys())
        check(keys.index("blood") == keys.index("size") + 1, "blood goes just after size, where lane FX put every creature's: %s" % keys)
        check('  "blood": "#8A1428",\n' in b_lines and after.count("\r\n") == btext.count("\r\n"), "its line is LF like its neighbour, the file's CRLFs kept")
        check(json.loads(after)["hp"] == 10.0 and '"hp": 10.0' in after, "numbers kept as they were")
        n_backups = len([f for f in os.listdir(server.BACKUPS) if f.startswith("bleeder-")])
        same = server.write_blood("bleeder", "#8a1428")
        check(same.get("ok") and same.get("unchanged") and len([f for f in os.listdir(server.BACKUPS) if f.startswith("bleeder-")]) == n_backups,
              "the colour it has already writes nothing (any case): %s" % same.get("output"))
        res2 = server.write_blood("bleeder", " #33cc99 ")
        after2 = open(bpath, "rb").read().decode("utf-8")
        changed = [(a, b) for a, b in zip(after.splitlines(True), after2.splitlines(True)) if a != b]
        check(res2.get("ok") and res2.get("was") == "#8A1428" and len(changed) == 1 and '"#33CC99"' in changed[0][1] and len(after2.splitlines()) == len(after.splitlines()),
              "a new colour replaces its own line in place: %s" % changed)
        for bad in ("red", "#12345", "#1234567", "#GGGGGG", "8a1428", 123, None, "", ["#8a1428"]):
            r = server.write_blood("bleeder", bad)
            check(not r.get("ok") and "#rrggbb" in r.get("error", ""), "a bad colour is refused: %r -> %s" % (bad, r.get("error")))
        check(open(bpath, "rb").read().decode("utf-8") == after2, "a refused colour leaves the file alone")
        check(not server.write_blood("nobody", "#8a1428").get("ok") and not server.write_blood("../x", "#8a1428").get("ok"), "an unknown creature is refused")
        check({c["id"]: c for c in server.list_creatures()}["bleeder"]["blood"] == "#33CC99", "the record carries the colour written")
        # a creature with no size and no knockback: after damage
        b2 = {"id": "bleeder2", "name": "B2", "hp": 5, "damage": 1, "radius": 0.5}
        os.makedirs(os.path.join(server.CONTENT, "enemies", "bleeder2"))
        p2 = os.path.join(server.CONTENT, "enemies", "bleeder2", "bleeder2.json")
        with open(p2, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(b2, indent=2) + "\n")
        server.write_blood("bleeder2", "#123456")
        k2 = list(json.loads(open(p2, encoding="utf-8").read()).keys())
        check(k2.index("blood") == k2.index("damage") + 1, "no size and no knockback: blood after damage: %s" % k2)

        # the route itself, over HTTP on a free port (a bad body and a good one)
        import threading
        import urllib.request
        import urllib.error
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        th = threading.Thread(target=httpd.serve_forever, daemon=True)
        th.start()
        try:
            base = "http://127.0.0.1:%d" % httpd.server_address[1]

            def post(url, body):
                req = urllib.request.Request(base + url, data=body, method="POST", headers={"Content-Type": "application/json"})
                try:
                    with urllib.request.urlopen(req, timeout=20) as r:
                        return r.status, json.loads(r.read().decode("utf-8"))
                except urllib.error.HTTPError as e:
                    return e.code, json.loads(e.read().decode("utf-8"))
            st, body = post("/api/enemy/bleeder/blood", json.dumps({"color": "#abcdef"}).encode("utf-8"))
            check(st == 200 and body.get("ok") and body.get("blood") == "#ABCDEF", "POST /api/enemy/bleeder/blood: %s %s" % (st, body.get("error")))
            st, body = post("/api/enemy/bleeder/blood", json.dumps({"color": "blue"}).encode("utf-8"))
            check(st == 400 and not body.get("ok"), "a bad colour over HTTP is a 400: %s" % st)
            st, body = post("/api/enemy/bleeder/blood", b"not json")
            check(st == 400, "a body that is not JSON is a 400: %s" % st)
            with urllib.request.urlopen(base + "/sprite/enemy/bleeder", timeout=20) as r:
                check(False, "a creature without a strip has no /sprite: %s" % r.status)
        except urllib.error.HTTPError as e:
            check(e.code == 404, "a creature without a strip: /sprite is a 404: %s" % e.code)
        finally:
            httpd.shutdown()
            httpd.server_close()
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- pass 61: snapping


SNAP_RUNNER = r"""
const M = require(process.argv[2]);
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.consts = { px: M.SNAP_PX, grid_px: M.SNAP_GRID_PX, grid_min_px: M.SNAP_GRID_MIN_PX, tier: M.SNAP_TIER };
  out.targets = q.targets.map(([tl, self]) => M.snapTargets(tl, self));
  out.drag = q.drag.map(([tl, edges, opts]) => M.snapDrag(tl, edges, opts));
  out.grid = q.grid.map((spp) => M.snapGridStep(spp));
  out.clock = q.clock.map((s) => M.clockText(s));
  process.stdout.write(JSON.stringify(out));
});
"""

SNAP_TIER_PY = {"cap": 0, "row": 1, "wave": 1, "event": 2, "stage": 3, "grid": 4}
SNAP_EVENT_WORD_PY = {"boss": "boss", "elite_boss": "Elite", "elite": "coloured elite", "elite_every": "Elites every", "swarm": "swarm"}


def js_round_half_up(v):
    """Math.round: halves go up (Python's round() goes to even)."""
    return int(math.floor(v + 0.5))


def clock_py(s):
    v = abs(js_round_half_up(float(s or 0)))
    h, m, sec = v // 3600, (v % 3600) // 60, v % 60
    return "%d:%02d:%02d" % (h, m, sec) if h > 0 else "%d:%02d" % (m, sec)


def snap_targets_py(tl, self_ref=None):
    """model.js snapTargets in Python: the cap's points, the rows' and waves' starts and ends, the events, the stage
    marks, each a whole second; the dragged item's own left out."""
    me = self_ref if isinstance(self_ref, dict) else {}
    out = []

    def add(t, kind, label):
        if t is None or t == "":
            return
        try:
            v = float(t)
        except (TypeError, ValueError):
            return
        if not math.isfinite(v) or v < 0:
            return
        out.append({"t": js_round_half_up(v), "kind": kind, "tier": SNAP_TIER_PY[kind], "label": label})

    for k, p in enumerate(tl.get("cap_curve") or []):
        if not isinstance(p, list) or len(p) < 2 or (me.get("kind") == "cap" and me.get("k") == k):
            continue
        add(p[0], "cap", "cap " + clock_py(p[0]))
    for i, r in enumerate(tl.get("roster") or []):
        if not isinstance(r, dict) or (me.get("kind") == "roster" and me.get("i") == i):
            continue
        name = str(r["id"]) if r.get("id") else "row %d" % (i + 1)
        add(numv(r.get("t"), 0), "row", name + " start")
        add(r.get("until"), "row", name + " end")
    for i, w in enumerate(tl.get("waves") or []):
        if not isinstance(w, dict) or (me.get("kind") == "wave" and me.get("i") == i):
            continue
        name = str(w["id"]) if w.get("id") else str(w["name"]) if w.get("name") else "wave %d" % (i + 1)
        add(numv(w.get("t"), 0), "wave", name + " start")
        e = wave_end_of(w)
        if e != math.inf:
            add(e, "wave", name + " end")
    for i, ev in enumerate(tl.get("events") or []):
        if not isinstance(ev, dict) or (me.get("kind") == "event" and me.get("i") == i):
            continue
        word = str(ev["name"]) if ev.get("name") else SNAP_EVENT_WORD_PY.get(ev.get("type"), str(ev.get("type") or "event"))
        add(numv(ev.get("t"), 0), "event", "%s %s" % (word, clock_py(numv(ev.get("t"), 0))))
    sl, n = stage_length(tl), max(1, int(numv(tl.get("stages"), 3)))
    for k in range(n + 1):
        add(k * sl, "stage", "stage %d start" % (k + 1) if k < n else "the run's end")
    return out


def snap_grid_py(spp):
    s = spp if spp and spp > 0 else 1
    if 30 / s >= 36:
        return 30
    if 60 / s >= 36:
        return 60
    return 0


def snap_drag_py(tl, edges, opts):
    """model.js snapDrag in Python: the lowest tier in range (8 px), then the nearest, then the first edge; the grid at
    4 px only when nothing else is in range."""
    if not opts.get("on") or opts.get("alt"):
        return None
    spp = opts.get("spp") if opts.get("spp", 0) > 0 else 1
    targets = opts["targets"] if isinstance(opts.get("targets"), list) else snap_targets_py(tl, opts.get("self"))
    best = None
    for e in edges:
        et, lo = float(e["t"]), float(e.get("min", 0) if e.get("min") is not None else 0)
        for tg in targets:
            dist = abs(tg["t"] - et)
            if dist > 8 * spp + 1e-9 or tg["t"] < lo - 1e-9:
                continue
            if best is None or tg["tier"] < best["target"]["tier"] or (tg["tier"] == best["target"]["tier"] and dist < best["dist"] - 1e-9):
                best = {"delta": tg["t"] - et, "t": tg["t"], "edge": e["edge"], "target": tg, "dist": dist}
    if best:
        return best
    g = snap_grid_py(spp)
    if not g:
        return None
    for e in edges:
        et, lo = float(e["t"]), float(e.get("min", 0) if e.get("min") is not None else 0)
        gt = js_round_half_up(et / g) * g
        dist = abs(gt - et)
        if dist > 4 * spp + 1e-9 or gt < lo - 1e-9:
            continue
        if best is None or dist < best["dist"] - 1e-9:
            best = {"delta": gt - et, "t": gt, "edge": e["edge"], "dist": dist,
                    "target": {"t": gt, "kind": "grid", "tier": 4, "label": "%s %s" % ("minute" if gt % 60 == 0 else "half minute", clock_py(gt))}}
    return best


def snap_checks():
    """Pass 61: the Snap toggle's maths (model.js snapTargets / snapDrag / snapGridStep): the target choice with the
    cap's points first, the range of 8 screen pixels at several zooms, the dragged item never its own target, Alt and
    the toggle turning it off, the edges' lowest times, a bar moved by either end, the minutes grid only when nothing
    else is near; then the JS against a Python copy on random drags over a hand-made timeline and over Red Canyon (read
    only: nothing is written)."""
    tl = {"stage_length": 430, "stages": 3,
          "cap_curve": [[0, 10], [150, 30], [150, 60], [363, 100], [430.4, 54]],
          "roster": [{"id": "r1", "t": 0, "until": 122}, {"id": "r2", "t": 146, "until": 300}, {"t": 250, "until": 368},
                     {"id": "r4", "t": 368}, {"id": "r5", "t": 600, "until": ""}],
          "waves": [{"id": "w1", "t": 200, "count": 20, "burst": 5, "every": 2.5}, {"name": "rush", "t": 500, "until": 520},
                    {"t": 700}],
          "events": [{"type": "elite_boss", "t": 215}, {"type": "elite_every", "t": 301, "interval": 129},
                     {"type": "boss", "t": 430}, {"type": "swarm", "t": 559, "name": "Ant swarm"}, {"type": "elite", "t": 864}]}
    # a handle's lowest time: row a's end handle (its start at 100, so its end at 101 or later) with row b starting at 99
    tlm = {"stage_length": 430, "roster": [{"id": "a", "t": 100, "until": 200}, {"id": "b", "t": 99}]}
    tlm2 = dict(tlm, cap_curve=[[104, 5]])
    E = lambda t, edge="point", lo=0: {"t": t, "edge": edge, "min": lo}  # noqa: E731
    on = lambda spp, **kw: dict({"spp": spp, "on": True}, **kw)  # noqa: E731
    drags = [
        # 0-5: the cap's points first: a cap point 3 s off beats a row's start 1 s off; at 7.9 px it still wins; at
        # 8.5 px it is out of range and the row wins; a row beats a nearer event; a cap point beats the boss and the
        # stage mark at its second; in one tier the nearest (at 2 s/px: a wave's end 8 s off over its start 12 s off)
        [tl, [E(147, "end", 1)], on(1)],
        [tl, [E(142.1, "end", 1)], on(1)],
        [tl, [E(141.5, "end", 1)], on(1)],
        [tl, [E(302, "end", 1)], on(1)],
        [tl, [E(433)], on(1)],
        [tl, [E(512)], on(2)],
        # 6-11: the range is 8 screen pixels at any zoom: 1 s/px 8 s in, 8.5 s out; 0.25 s/px 2 s in, 2.5 s and 7 s out;
        # 4 s/px 32 s in
        [tl, [E(608)], on(1)],
        [tl, [E(608.5)], on(1)],
        [tl, [E(602)], on(0.25)],
        [tl, [E(602.5)], on(0.25)],
        [tl, [E(607)], on(0.25)],
        [tl, [E(632)], on(4)],
        # 12-15: Alt held, the toggle off, Alt with the toggle off, and a target right under the edge with Alt: no snap
        [tl, [E(150)], on(1, alt=True)],
        [tl, [E(150)], {"spp": 1, "on": False}],
        [tl, [E(150)], {"spp": 1, "on": False, "alt": True}],
        [tl, [E(149)], on(1, alt=True)],
        # 16-18: never itself: row r2's end handle at its own end (300) finds the Elites every at 301 instead; the row
        # moved whole by its start at its own 146 finds the cap at 150; cap point 3 dragged at its own 363 finds the
        # third row's end (368)
        [tl, [E(300, "end", 147)], on(1, self={"kind": "roster", "i": 1})],
        [tl, [E(146, "start", 0), E(300, "end", 154)], on(1, self={"kind": "roster", "i": 1})],
        [tl, [E(363)], on(1, self={"kind": "cap", "k": 3})],
        # 19-20: an edge's lowest time: row a's end handle (min 101) at 102 passes over row b's start at 99 (nothing
        # else near: no snap); with a cap point at 104 it takes that
        [tlm, [E(102, "end", 101)], on(1, self={"kind": "roster", "i": 0})],
        [tlm2, [E(102, "end", 101)], on(1, self={"kind": "roster", "i": 0})],
        # 21-22: a bar moved whole: its start is far from everything, its end 2 s from the cap (delta -2); both ends in
        # range: the start 1 s from a row's end (tier 1) and the end 4 s from a cap point (tier 0): the cap wins (+4)
        [tl, [E(254, "start", 0), E(365, "end", 111)], on(1, self={"kind": "roster", "i": 2})],
        [tl, [E(121, "start", 0), E(359, "end", 238)], on(1)],
        # 23-26: the grid: half minutes at 0.5 s/px (2 s pull), nothing at 3 s; a target in range beats an exact grid
        # line; whole minutes at 1 s/px; none at 2 s/px
        [{"stage_length": 430}, [E(92)], on(0.5)],
        [{"stage_length": 430}, [E(93)], on(0.5)],
        [{"stage_length": 430, "events": [{"type": "boss", "t": 92}]}, [E(90)], on(0.5)],
        [{"stage_length": 430}, [E(118)], on(1)],
        [{"stage_length": 430}, [E(118)], on(2)],
        # 28: an event beats a stage mark (the stage 3 start 1 s off, a coloured elite 3 s off)
        [tl, [E(861)], on(1)],
    ]
    q = {
        "targets": [[tl, None], [tl, {"kind": "roster", "i": 1}], [tl, {"kind": "wave", "i": 0}], [tl, {"kind": "event", "i": 2}],
                    [tl, {"kind": "cap", "k": 1}], [tl, {"kind": "weight", "i": 1}], [{}, None], [{"stage_length": 300, "stages": 2, "cap_curve": [[-5, 1], ["x", 2], [7]]}, None]],
        "drag": drags,
        "grid": [0.25, 0.5, 0.8333, 0.84, 1, 1.6666, 1.7, 5, 0, -1],
        "clock": [0, 59.5, 150, 3599, 3600, 4000.2],
    }
    # JS against the Python copy: random drags on the hand-made timeline and on Red Canyon as it is on disk
    rc_tl = server.load_json(server.map_path("red_canyon")).get("timeline_data", {})
    rnd = random.Random(61)
    rand_q = []
    for base in (tl, rc_tl):
        rows, waves, evs, caps = base.get("roster") or [], base.get("waves") or [], base.get("events") or [], base.get("cap_curve") or []
        for _ in range(250):
            spp = rnd.choice([0.05, 0.25, 0.47, 1, 1.37, 2.5, 6])
            kind = rnd.choice(["roster", "wave", "event", "cap", "weight", None])
            n = {"roster": len(rows), "wave": len(waves), "event": len(evs), "cap": len(caps)}.get(kind, 0)
            self_ref = None
            if kind in ("roster", "wave", "event") and n:
                self_ref = {"kind": kind, "i": rnd.randrange(n)}
            elif kind == "cap" and n:
                self_ref = {"kind": "cap", "k": rnd.randrange(n)}
            t0 = rnd.choice([rnd.uniform(0, 1400), rnd.choice([0, 150, 300, 430, 860]) + rnd.uniform(-12, 12)])
            t0 = max(0, round(t0))
            edges = [E(t0, "start", 0)]
            if rnd.random() < 0.5:
                ln = rnd.randint(1, 200)
                edges.append(E(t0 + ln, "end", ln))
            opts = {"spp": spp, "on": rnd.random() > 0.08, "alt": rnd.random() < 0.08, "self": self_ref}
            rand_q.append([base, edges, opts])
    q["drag"] = drags + rand_q
    res = run_node(q, SNAP_RUNNER)
    if res is None:
        print("node not found: the snapping checks are skipped")
        return
    if not res:
        return
    c = res["consts"]
    check(c["px"] == 8 and c["grid_px"] == 4 and c["grid_min_px"] == 36, "snap: 8 px for targets, 4 px for the grid, half minutes from 36 px apart: %s" % c)
    tr = c["tier"]
    check(tr["cap"] < tr["row"] == tr["wave"] < tr["event"] < tr["stage"] < tr["grid"], "snap: the tiers put the cap first, then rows and waves, events, stages, the grid: %s" % tr)
    # the targets
    allt = res["targets"][0]
    key = lambda lst: sorted((x["kind"], x["t"], x["label"]) for x in lst)  # noqa: E731
    check(key(allt) == key(snap_targets_py(tl)), "snap: the targets match the Python copy")
    labels = {x["label"]: x for x in allt}
    for lab, t, kind in [("cap 0:00", 0, "cap"), ("cap 2:30", 150, "cap"), ("cap 6:03", 363, "cap"), ("cap 7:10", 430, "cap"),
                         ("r1 start", 0, "row"), ("r1 end", 122, "row"), ("row 3 start", 250, "row"), ("row 3 end", 368, "row"),
                         ("r4 start", 368, "row"), ("r5 start", 600, "row"), ("w1 start", 200, "wave"), ("w1 end", 210, "wave"),
                         ("rush start", 500, "wave"), ("rush end", 520, "wave"), ("wave 3 start", 700, "wave"),
                         ("Elite 3:35", 215, "event"), ("Elites every 5:01", 301, "event"), ("boss 7:10", 430, "event"),
                         ("Ant swarm 9:19", 559, "event"), ("stage 1 start", 0, "stage"), ("stage 2 start", 430, "stage"),
                         ("stage 3 start", 860, "stage"), ("the run's end", 1290, "stage")]:
        x = labels.get(lab)
        check(x is not None and x["t"] == t and x["kind"] == kind and x["tier"] == SNAP_TIER_PY[kind], "snap: the target %r at %s (%s): %s" % (lab, t, kind, x))
    check(len([x for x in allt if x["kind"] == "cap"]) == 5, "snap: every cap point is a target (two at 2:30 too)")
    check(not any(x["label"] in ("r4 end", "r5 end", "wave 3 end") for x in allt), "snap: an open row, a blank until and a wave with no count and no until have no end")
    check(labels["w1 end"]["t"] == 210 and all(isinstance(x["t"], int) for x in allt), "snap: every target a whole second (the wave's end at 200 + 2.5 × 4 = 210)")
    check(labels["cap 7:10"]["t"] == 430, "snap: a cap point at 430.4 s is the target 430")
    no_r2 = res["targets"][1]
    check(not any(x["label"].startswith("r2 ") for x in no_r2) and len(no_r2) == len(allt) - 2, "snap: a dragged row is not its own target (start and end)")
    no_w1 = res["targets"][2]
    check(not any(x["label"].startswith("w1 ") for x in no_w1) and len(no_w1) == len(allt) - 2, "snap: a dragged wave is not its own target")
    no_boss = res["targets"][3]
    check(not any(x["kind"] == "event" and x["t"] == 430 for x in no_boss) and any(x["kind"] == "cap" and x["t"] == 430 for x in no_boss) and len(no_boss) == len(allt) - 1,
          "snap: a dragged event is not its own target (the cap point and the stage mark at the same second stay)")
    no_cap1 = res["targets"][4]
    caps1 = [x for x in no_cap1 if x["kind"] == "cap"]
    check(len(caps1) == 4 and sum(1 for x in caps1 if x["t"] == 150) == 1, "snap: a dragged cap point is not its own target (its twin at 2:30 stays)")
    check(len(res["targets"][5]) == len(allt), "snap: a presence keyframe leaves every target in (its own row's start and end too)")
    check(key(res["targets"][6]) == key([{"kind": "stage", "t": t, "label": l} for t, l in [(0, "stage 1 start"), (300, "stage 2 start"), (600, "stage 3 start"), (900, "the run's end")]]),
          "snap: an empty timeline has the default stage marks: %s" % res["targets"][6])
    bad = res["targets"][7]
    check([x["kind"] for x in bad].count("cap") == 0 and len(bad) == 3, "snap: a negative, a non-number and a one-number cap point are no targets: %s" % bad)
    # the drags by hand
    d = res["drag"]
    want = [
        (150, "cap", "cap 2:30"), (150, "cap", "cap 2:30"), (146, "row", "r2 start"), (300, "row", "r2 end"), (430, "cap", "cap 7:10"),
        (520, "wave", "rush end"),
        (600, "row", "r5 start"), None, (600, "row", "r5 start"), None, None, (600, "row", "r5 start"),
        None, None, None, None,
        (301, "event", "Elites every 5:01"), (150, "cap", "cap 2:30"), (368, "row", "row 3 end"),
        None, (104, "cap", "cap 1:44"),
        (363, "cap", "cap 6:03"), (363, "cap", "cap 6:03"),
        (90, "grid", "half minute 1:30"), None, (92, "event", "boss 1:32"), (120, "grid", "minute 2:00"), None,
        (864, "event", "coloured elite 14:24"),
    ]
    for k, w in enumerate(want):
        got = d[k]
        if w is None:
            check(got is None, "snap drag %d: no snap, got %s" % (k, got and got["target"]["label"]))
        else:
            ok = got is not None and got["t"] == w[0] and got["target"]["kind"] == w[1] and got["target"]["label"] == w[2]
            check(ok, "snap drag %d: %s, got %s" % (k, w, got and (got["t"], got["target"]["kind"], got["target"]["label"])))
    check(d[21] is not None and d[21]["edge"] == "end" and d[21]["delta"] == -2, "snap: a bar moved whole snaps by its end, the start moving the same 2 s: %s" % d[21])
    check(d[22] is not None and d[22]["edge"] == "end" and d[22]["delta"] == 4, "snap: both ends in range, the end's cap point beats the start's nearer row: %s" % d[22])
    check(d[0] is not None and d[0]["dist"] == 3 and d[0]["delta"] == 3, "snap: the cap point won from 3 s while a row start sat 1 s away")
    # the grid's spacing at each zoom
    check(res["grid"] == [30, 30, 30, 60, 60, 60, 0, 0, 60, 60], "snap: the grid's spacing per zoom (a zoom of 0 or below read as 1 s/px): %s" % res["grid"])
    check(res["clock"] == ["0:00", "1:00", "2:30", "59:59", "1:00:00", "1:06:40"], "snap: labels' clock: %s" % res["clock"])
    # JS against Python on the random drags
    agree = 0
    for (base, edges, opts), got in zip(rand_q, d[len(drags):]):
        py = snap_drag_py(base, edges, opts)
        same = (got is None and py is None) or (got is not None and py is not None and got["t"] == py["t"] and got["edge"] == py["edge"]
                                                 and got["target"]["kind"] == py["target"]["kind"] and got["target"]["label"] == py["target"]["label"]
                                                 and abs(got["delta"] - py["delta"]) < 1e-9)
        check(same, "snap: JS and Python agree on %s %s: js %s py %s" % (edges, opts, got and got["target"]["label"], py and py["target"]["label"]))
        if same:
            agree += 1
        # never itself, and never closer than the rules allow
        if got:
            spp = opts["spp"]
            check(got["dist"] <= (8 if got["target"]["kind"] != "grid" else 4) * spp + 1e-9, "snap: within 8 px (4 for the grid): %s at %s s/px" % (got, spp))
            me = opts.get("self") or {}
            if me and got["target"]["kind"] != "grid":
                others = {(x["label"], x["t"]) for x in snap_targets_py(base, me)}
                mine = {(x["label"], x["t"]) for x in snap_targets_py(base)} - others
                check((got["target"]["label"], got["t"]) not in mine, "snap: never its own start or end: %s" % got)
    snapped = sum(1 for g in d[len(drags):] if g)
    print("snapping: %d random drags, %d snapped, JS and Python agree on %d" % (len(rand_q), snapped, agree))


def extra_checks():
    """Pass 66: every `selftest_<name>.py` beside this file is a check group of its own (one per lane, so lanes never edit
    this file at once). Each exports `checks(check, run_node, server)` and uses the `check` counter it is handed."""
    import glob
    import importlib
    for path in sorted(glob.glob(os.path.join(HERE, "selftest_*.py"))):
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            mod = importlib.import_module(name)
            mod.checks(check, run_node, server)
        except Exception as e:  # a broken group is one failure, not a crash of the whole run
            import traceback
            traceback.print_exc()
            check(False, "%s: %s: %s" % (name, type(e).__name__, e))


def main():
    model_checks()
    estimate_checks()
    server_checks()
    fit_checks()
    snap_checks()
    extra_checks()
    print("%d checks passed, %d failed" % (PASSES[0], len(FAILS)))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())

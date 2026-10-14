#!/usr/bin/env python3
"""The run sim's driver (pass 77, lane SIMUI): N simulated players, each one headless run of the REAL game driven by a
bot (game/tools/sim_run.gd, lane SIMRUN), K at a time, on a snapshot copy of game/ with its own user folder, averaged per
second of play into result.json. The Level Editor's Sim tab starts it as a job (kind "sim", tools/level_editor/jobs.py);
it runs from a shell too:

    python tools/sim_batch.py --out tools/dl/sim/runs/try1 --hero drifter --players 10 --workers 6 --limit 1500 \\
        --board 1.5 --death gold --seed 1 [--map red_canyon] [--fps 60] [--note "after the cap change"]
    python tools/sim_batch.py --aggregate tools/dl/sim/runs/try1    # the players' files again into result.json (no Godot)
    python tools/sim_batch.py --out <dir> --synthetic [...]          # made-up players: the page's and the selftest's fixture

What it does, in order:
 1. The sim lock tools/dl/locks/sim.lock (one sim batch at a time). NOT the godot lock: the snapshot is another project
    folder with its own user:// folder (%APPDATA%/88fits_sim), so Garry's save, his imports and the tests are never
    blocked by a sim and never touched by one. The owner.json is the one tools/locks.py writes; a dead owner's lock is
    reclaimed, a bare folder without owner.json never is (the Sim tab offers a Force release).
 2. The snapshot: game/ -> tools/dl/sim/snap/game/, every file whose size or mtime differs copied (mtimes kept), every
    file gone from game/ deleted; never export/, reports/ or .godot/ (the snapshot's .godot is seeded once from the real
    one, minus its shader and export caches, then belongs to the snapshot's own imports). Its project.godot gets
    application/config/use_custom_user_dir=true and custom_user_dir_name="88fits_sim". `--headless --import` runs on
    the copy when an imported asset (a picture, a model, a sound, a font, a .import), a .uid, a new scene or resource, or
    a script's class_name changed, and when the copy is new. `import_json.gd -- only=...` runs on the copy for every
    content JSON newer than its .tres: the sim plays the saved JSON even when the real import lagged or was queued.
 3. The players: `Godot --headless --fixed-fps <fps> --path <snapshot> --log-file players/pNN.log --script
    res://tools/sim_run.gd -- out=players/pNN.json hero= seed=<seed + k - 1> limit= board= death= map= progress=10`,
    K at a time, each with a wall-time cap; a player is judged by its JSON (a headless run can exit 0xC0000005 at
    teardown after writing it). progress.json beside result.json says where every player is.
 4. The aggregation (aggregate(): the rules are in tools/dl/p77/balancing_SIMUI.md and docs/level_editor.md "Pass 77"):
    per second of play 0..T, every series the mean over the players still playing at that second; p10/p90 bands for
    HP, DPS, level and the crowd; DPS per player smoothed over 5 s first; deaths the mean over EVERY player (an ended
    run keeps its count); the breakdowns (damage by source, kills and the crowd by creature) as means; the stage and
    boss times as medians. result.json is written again after every finished player (`partial` until the end), so a
    cancelled sim keeps what finished.
 5. The history: tools/dl/sim/runs/ keeps the newest 10 sims plus every kept one (a `kept` file).

Standard library only (the Level Editor imports this module for its paths, the settings and the history).
"""
import argparse
import hashlib
import json
import math
import os
import random
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import locks  # noqa: E402  (pid_alive, the Godot binary's path)

GAME = os.path.join(ROOT, "game")
GODOT = locks.GODOT
SIM_DIR = os.path.join(ROOT, "tools", "dl", "sim")      # a module variable: the selftest points it at a temp folder
LOCK_DIR = locks.LOCK_DIR
USER_DIR_NAME = "88fits_sim"
HISTORY_KEEP = 10
PROGRESS_EVERY = 10          # sim_run.gd's progress line, play seconds
DPS_WINDOW = 5               # seconds a player's DPS is smoothed over before the averaging
FOLD_DEFAULT = 7             # the page folds a breakdown to this many entries + "Other"
SCHEMA = 1

# the settings and their defaults (INTERFACES "Lane SIMUI"; round 2: the board talent by talent, the death policies
# without gold, the number at once from the processors); the page, the job spec and the CLI share them
DEFAULTS = {"hero": "drifter", "players": 10, "workers": 0, "limit": 1500, "board": 1.5, "talents": None, "board_label": "",
            "death": "end", "seed": 1, "map": "red_canyon", "fps": 60, "note": "", "fast": True}
BOARDS = [(0.0, "none"), (1.5, "a quarter"), (3.0, "half"), (6.0, "full")]
PRESETS = [("none", 0.0), ("quarter", 1.5), ("half", 3.0), ("full", 6.0)]   # the page's preset keys
DEATHS = [("end", "end the run at the first death", "no revive: the run ends at the first death (the default: Garry took Get up with gold out)"),
          ("ad", "revive once with an ad, then end", "Down! answered with the ad revive while it is offered (a chance left), then the run ends"),
          ("keep", "keep playing, count every death",
           "the hero is put back on his feet at once and plays to the stop time; every down is counted (the difficulty probe's way)")]
LEGACY_DEATHS = {"gold": "revive with gold, then the run ends"}   # an older sim's setting, never offered again
# the Upgrade board (game/content/talents): difficulty_probe's FORMS, in its order (a fractional board alternates the
# ranks in this order); a talent's picks are one letter a rank bought, its form: A the first, B the second
TALENT_ORDER = ("grit", "drive", "stride", "fortune", "choice", "nerve", "study", "spite")
TALENT_FORMS = {"grit": 0, "drive": 0, "stride": 0, "fortune": 0, "choice": 0, "nerve": 1, "study": 1, "spite": 1}
MAX_RANK = 6
MAX_PLAYERS = 100
LIMIT_MIN, LIMIT_MAX = 30, 3 * 3600

# what kind of number each player series is: a level (carried forward), a cumulative count (carried forward, 0 before
# the first row) or a rate of that second (0 before the first row)
LEVEL_SERIES = ("hp", "hp_max", "est", "alive", "cap", "press_hp", "press_dmg", "boss_hp", "boss_hp_abs", "level", "clock", "stage",
                "phase", "gold", "near3", "near6", "mult_hp", "mult_dmg")
CUM_SERIES = ("gold_total", "kills", "xp_total", "deaths", "dmg_total")
RATE_SERIES = ("dps", "took", "healed", "hits", "spawned")
BAND_SERIES = ("hp", "dps", "level", "press_hp", "press_dmg", "danger", "near3", "near6")
# ratios (a crowd over a DPS) blow up where the DPS is small: their middle value and band, never a mean
MEDIAN_SERIES = ("keep_up", "boss_s")
RATE_WINDOW = 10   # seconds the per-second counts (kills, spawns, hits) are smoothed over, as the run dashboard's 10 s means
TROUBLE_FRAC = 0.30   # "in trouble": under this share of max HP (the run dashboard's survivability card)
BREAKDOWNS = {"dmg_by": "cum", "kills_by": "cum", "gold_by": "cum", "took_by": "cum", "healed_by": "cum", "alive_by": "level",
              "held_by": "level"}
# the damage sources that are no content item (RunAnalytics.SOURCE_NAMES: "blast" = creatures caught in a hostile blast,
# a boss's slam or a creature's grenade; "revive" = the Down! revive's blast)
SOURCE_WORDS = {"blast": "Blast", "revive": "Revive blast", "grand_finale": "Grand Finale", "powder_keg": "Powder Keg",
                "loose_rocket": "Loose rocket", "thorns": "Thorns", "other": "Other"}


def _now_iso(t=None):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t if t is not None else time.time()))


def runs_dir():
    return os.path.join(SIM_DIR, "runs")


def snap_game():
    return os.path.join(SIM_DIR, "snap", "game")


def speed_file():
    return os.path.join(SIM_DIR, "speed.json")


def settings_file():
    return os.path.join(SIM_DIR, "settings.json")


def lock_path():
    return os.path.join(LOCK_DIR, "sim.lock")


def cores():
    return os.cpu_count() or 4


def max_workers():
    return max(1, cores() - 2)


# ---------------------------------------------------------------- small file helpers

def read_json(path, tries=8):
    """A JSON file, or None (missing, half-written: a few quick tries, a writer may be replacing it)."""
    for i in range(tries):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except FileNotFoundError:
            return None
        except (OSError, ValueError):
            time.sleep(0.05 * (i + 1))
    return None


def write_json(path, obj, indent=None):
    """Atomic: a temp file then os.replace (retried: on Windows a reader holding the file refuses the replace)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=indent, ensure_ascii=False, separators=(",", ":") if indent is None else None)
    for i in range(40):
        try:
            os.replace(tmp, path)
            return True
        except OSError:
            time.sleep(0.05)
    try:
        os.remove(tmp)
    except OSError:
        pass
    return False


# ---------------------------------------------------------------- the settings

def board_label(v):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return str(v)
    for b, lab in BOARDS:
        if abs(b - v) < 1e-6:
            return lab
    return "%g ranks" % v


def death_label(v):
    for k, lab, _ in DEATHS:
        if k == v:
            return lab
    return LEGACY_DEATHS.get(v, str(v))


def auto_workers(players):
    """How many runs play at once when the setting says 0 (auto): as many as the runs, at most the logical processors
    less 2 (measured in pass 77: more at once is sooner overall, each run a little slower)."""
    return max(1, min(int(players), max_workers()))


# ---------------------------------------------------------------- the Upgrade board, talent by talent

def rank_for(m, k):
    """difficulty_probe.rank_for: a whole board gives every talent that many ranks; a half alternates ceiling / floor in
    TALENT_ORDER (1.5 = 2, 1, 2, 1, ...: 12 of 48 ranks)."""
    lo = int(math.floor(m))
    if m - lo <= 0.001:
        return max(0, min(MAX_RANK, lo))
    return max(0, min(MAX_RANK, lo + (1 if k % 2 == 0 else 0)))


def board_talents(m):
    """The board of a preset (0, 1.5, 3, 6 ranks a talent) as {talent: picks}, each rank in its FORMS form."""
    out = {}
    for k, tid in enumerate(TALENT_ORDER):
        r = rank_for(float(m), k)
        if r > 0:
            out[tid] = "AB"[TALENT_FORMS[tid]] * r
    return out


def picks_letters(v):
    """A talent's picks in any of the shapes they come in (the save's {picks: [0, 1]} or {rank, form}, a list of 0/1, a
    string of 0/1 or A/B) as letters A/B, at most MAX_RANK; None when it cannot be read."""
    if isinstance(v, dict):
        if isinstance(v.get("picks"), list):
            v = v["picks"]
        else:
            try:
                return "AB"[min(1, max(0, int(v.get("form", 0))))] * max(0, min(MAX_RANK, int(v.get("rank", 0))))
            except (TypeError, ValueError):
                return None
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return "A" * max(0, min(MAX_RANK, int(v)))
    if isinstance(v, list):
        try:
            return "".join("AB"[min(1, max(0, int(x)))] for x in v)[:MAX_RANK]
        except (TypeError, ValueError):
            return None
    if isinstance(v, str):
        t = v.strip().upper().replace("0", "A").replace("1", "B")
        return t[:MAX_RANK] if re.match(r"^[AB]*$", t) else None
    return None


def clean_talents(raw):
    """The board as {talent: picks letters} (talents without a rank left out): from a dict, or the arg's text
    "grit:AAB,drive:A" ("none" = empty). (board, problems)."""
    probs = []
    if raw is None:
        return {}, probs
    items = {}
    if isinstance(raw, str):
        txt = raw.strip()
        if txt.lower() in ("", "none"):
            return {}, probs
        for part in txt.split(","):
            if not part.strip():
                continue
            bits = part.strip().split(":")
            if len(bits) == 3:   # <id>:<rank>:<form>
                try:
                    items[bits[0]] = "AB"[1 if bits[2].strip().upper() in ("1", "B") else 0] * int(bits[1])
                except ValueError:
                    probs.append("talents: %r is not <id>:<rank>:<form>" % part)
            elif len(bits) == 2:
                items[bits[0]] = bits[1]
            else:
                probs.append("talents: %r is not <id>:<picks>" % part)
    elif isinstance(raw, dict):
        items = raw
    else:
        return {}, ["talents must be {talent: picks} or \"grit:AAB,drive:A\""]
    out = {}
    for tid, v in items.items():
        tid = str(tid).strip()
        if tid not in TALENT_FORMS:
            probs.append("talents: no talent %r (one of %s)" % (tid, ", ".join(TALENT_ORDER)))
            continue
        p = picks_letters(v)
        if p is None:
            probs.append("talents: %s's picks %r are not 0-6 letters A/B" % (tid, v))
            continue
        if len(str(v if not isinstance(v, (dict, list)) else "")) > MAX_RANK and isinstance(v, str):
            probs.append("talents: %s has more than %d ranks" % (tid, MAX_RANK))
        if p:
            out[tid] = p
    return {k: out[k] for k in TALENT_ORDER if k in out}, probs


def talents_arg(t):
    """The runner's talents= text: "grit:AAB,drive:A", or "none"."""
    return ",".join("%s:%s" % (k, t[k]) for k in TALENT_ORDER if t.get(k)) or "none"


def preset_of(t):
    """The preset ("none", "quarter", "half", "full") whose board this is, else None (a custom board)."""
    for key, m in PRESETS:
        if board_talents(m) == (t or {}):
            return key
    return None


def board_ranks(t):
    return sum(len(v) for v in (t or {}).values())


def board_text(t, label=""):
    """The board in words: "a quarter (12 of 48 ranks)", "my save (20 of 48 ranks)", "custom (...)"."""
    pre = preset_of(t)
    name = label or (board_label(dict(PRESETS)[pre]) if pre else "custom")
    return "%s (%d of %d ranks)" % (name, board_ranks(t), MAX_RANK * len(TALENT_ORDER))


def save_board(save_dir=None):
    """The PC save's Upgrade board ({talent: picks}) for the "my save" preset: %APPDATA%/Godot/app_userdata/88fits/
    save.json, or the copy tools/locks.py keeps aside while a Godot tool has the save (restore pending). (board, note)."""
    d = save_dir or locks.SAVE_DIR
    paths = []
    if os.path.isfile(locks.RESTORE_PENDING):
        paths.append(os.path.join(locks.KEEP_DIR, "save.json.keep"))
    paths.append(os.path.join(d, "save.json"))
    for p in paths:
        data = read_json(p, tries=2)
        if isinstance(data, dict):
            tal = data.get("talents") if isinstance(data.get("talents"), dict) else {}
            board, _ = clean_talents({k: v for k, v in tal.items() if k in TALENT_FORMS})
            return board, "read from %s" % p
    return None, "no save found at %s" % paths[-1]


def caps_problem(s, caps):
    """Why the runner cannot play these settings ("" when it can): a death policy it refuses, a custom board it would
    play as no board (an older runner reads only board= presets)."""
    if not caps.get("runner", True):
        return "game/tools/sim_run.gd is not there: nothing can play the runs"
    if caps.get("deaths") and s.get("death") not in caps["deaths"]:
        return "the runner (game/tools/sim_run.gd) does not know the death policy %r yet (it knows %s)" % (s.get("death"), ", ".join(caps["deaths"]))
    if not caps.get("talents") and float(s.get("board", 0)) < 0:
        return ("the runner (game/tools/sim_run.gd) plays only the board presets (none, a quarter, half, full) until it reads "
                "talents=: this board is %s" % board_text(s.get("talents"), s.get("board_label")))
    return ""


def runner_caps(game_dir=None):
    """What the runner (game/tools/sim_run.gd) understands, read off its argument parser: talents= (the board talent by
    talent), the death policies, fast= (lane SIMRUN's sim mode). An older runner ignores an argument it does not know
    and refuses a death policy it does not know."""
    p = os.path.join(game_dir or GAME, "tools", "sim_run.gd")
    try:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            src = f.read()
    except OSError:
        return {"runner": False, "talents": False, "deaths": [], "fast": False}
    m = re.search(r"_death\s+in\s+\[([^\]]*)\]", src)
    deaths = re.findall(r'"([a-z]+)"', m.group(1)) if m else ["gold", "end", "keep"]
    return {"runner": True, "talents": bool(re.search(r'^\s*"talents"\s*:', src, re.M)), "deaths": deaths,
            "fast": bool(re.search(r'^\s*"fast"\s*:', src, re.M))}


def fmt_t(s):
    s = int(round(float(s or 0)))
    return "%d:%02d" % (s // 60, s % 60) if s < 3600 else "%d:%02d:%02d" % (s // 3600, (s % 3600) // 60, s % 60)


def clean_settings(raw, heroes=None, maps=None, legacy=False):
    """The settings coerced and checked: (settings, problems). Unknown keys dropped; a problem is a plain sentence.
    `legacy` reads an older sim's settings (its death policy "gold") without a problem."""
    raw = raw if isinstance(raw, dict) else {}
    s = dict(DEFAULTS)
    probs = []

    def num(key, kind, lo, hi):
        v = raw.get(key, DEFAULTS[key])
        try:
            v = kind(float(v)) if kind is int else float(v)
        except (TypeError, ValueError):
            probs.append("%s must be a number (got %r)" % (key, v))
            return DEFAULTS[key]
        if v < lo or v > hi:
            probs.append("%s must be between %s and %s (got %s)" % (key, lo, hi, v))
            v = min(hi, max(lo, v))
        return v

    s["players"] = num("players", int, 1, MAX_PLAYERS)
    s["workers"] = num("workers", int, 0, max_workers())   # 0 = auto (as many as the runs, at most cores - 2)
    s["limit"] = num("limit", int, LIMIT_MIN, LIMIT_MAX)
    s["seed"] = num("seed", int, 0, 2 ** 31 - 1)
    s["fps"] = num("fps", int, 10, 240)
    b = raw.get("board", DEFAULTS["board"])
    try:
        b = float(b)
    except (TypeError, ValueError):
        probs.append("board must be one of %s" % ", ".join("%g" % x for x, _ in BOARDS))
        b = DEFAULTS["board"]
    if b < 0 or b > 6:
        probs.append("board must be between 0 and 6 ranks (got %g)" % b)
        b = min(6.0, max(0.0, b))
    s["board"] = b
    # the board talent by talent (round 2): given, it wins over board= (which then only names a preset it equals)
    traw = raw.get("talents")
    if traw is None or traw == "" or traw == {}:   # not given (a job spec's default {}): the preset board= names
        s["talents"] = board_talents(b)
        s["board_label"] = board_label(b)
    else:
        t, tp = clean_talents(traw)
        probs += tp
        s["talents"] = t
        pre = preset_of(t)
        s["board"] = dict(PRESETS)[pre] if pre else -1.0
        lab = str(raw.get("board_label") or "").strip()
        s["board_label"] = lab[:40] if lab else (board_label(s["board"]) if pre else "custom")
    d = str(raw.get("death", DEFAULTS["death"]))
    ok_deaths = [k for k, _, _ in DEATHS] + (list(LEGACY_DEATHS) if legacy else [])
    if d not in ok_deaths:
        probs.append("death must be one of %s (got %r)" % (", ".join(k for k, _, _ in DEATHS), d))
        d = DEFAULTS["death"]
    s["death"] = d
    s["fast"] = str(raw.get("fast", True)).strip().lower() not in ("0", "false", "no", "off")
    for key in ("hero", "map"):
        v = str(raw.get(key, DEFAULTS[key]) or "").strip()
        if not re.match(r"^[a-z0-9_]+$", v):
            probs.append("%s must be an id (letters, digits, _): %r" % (key, v))
            v = DEFAULTS[key]
        s[key] = v
    if heroes is not None and s["hero"] not in heroes:
        probs.append("no hero %r" % s["hero"])
    if maps is not None and s["map"] not in maps:
        probs.append("no map %r" % s["map"])
    s["note"] = str(raw.get("note", "") or "").strip()[:200]
    if s["workers"] <= 0:
        s["workers"] = auto_workers(s["players"])
    if s["workers"] > s["players"]:
        s["workers"] = s["players"]
    return s, probs


# ---------------------------------------------------------------- the speed and the ETA

def load_speed(path=None, fast=True):
    """The measured speed {play_per_wall, slow, boot_s, workers, ...}: the medians of the last 5 records made in the
    runner's current mode (its sim mode on: `fast`; a record from before the mode existed counts as off) at the most
    recent record's number at once (the ETA scales from there with speed_at); none in that mode: the records whatever
    their mode; none at all: a first guess."""
    d = read_json(path or speed_file()) or {}
    hist = [h for h in (d.get("history") or []) if isinstance(h, dict) and float(h.get("play_per_wall") or 0) > 0]
    if not hist:
        # pass 77's first measures: 2.3 to 2.7 play seconds a wall second, six at once, before the sim mode
        return {"play_per_wall": 2.5, "boot_s": 18.0, "workers": 6, "measured": False, "n": 0, "fast": fast}
    same = [h for h in hist if bool(h.get("fast", False)) == bool(fast)] or hist
    k = int(same[-1].get("workers") or 6)
    use = [h for h in same if int(h.get("workers") or 6) == k][-5:]   # measured at that number at once: no scaling
    ppw = statistics.median(float(h["play_per_wall"]) for h in use)
    slow = statistics.median(float(h.get("slow") or h["play_per_wall"]) for h in use)
    boot = statistics.median(float(h.get("boot_s") or 18.0) for h in use)
    return {"play_per_wall": ppw, "slow": slow, "boot_s": boot, "workers": k, "measured": True, "n": len(use), "fast": bool(use[-1].get("fast", False)),
            "updated": use[-1].get("updated", "")}


def speed_at(ppw, k_meas, k):
    """The play speed of one run when k run at once, from a speed measured with k_meas at once: a run keeps about two
    logical processors busy (the game's thread and its workers), so past half the processors they share."""
    half = max(1.0, cores() / 2.0)
    load = lambda n: max(1.0, float(n) / half)   # noqa: E731
    return ppw * load(k_meas) / load(k)


def eta_seconds(settings, speed=None, sync_s=20.0):
    """About how long a sim takes: the snapshot, then the players in rounds of `workers`, each its boot plus `limit`
    play seconds at the measured play-seconds-per-wall-second (speed_at for another count at once). An upper bound for
    the death modes that end runs early."""
    s, _ = clean_settings(settings)
    sp = speed or load_speed()
    k = max(1, min(int(s["workers"]), int(s["players"])))
    # a round of runs ends with its slowest run: that pace when it was measured
    ppw = speed_at(float(sp.get("slow") or sp.get("play_per_wall") or 2.5), max(1, int(sp.get("workers") or 6)), k)
    per = float(sp.get("boot_s") or 18.0) + s["limit"] / max(0.05, ppw)
    rounds = math.ceil(s["players"] / float(k))
    return int(round(sync_s + rounds * per + 3))


def record_speed(players, workers, fps, fast=True, limit=None):
    """Add this sim's measured speed to speed.json (the last 20 kept): per run, its play seconds over its wall seconds
    after the boot (the boot = the wall time at its first progress line less that line's play time at the run's rate);
    `slow` = the slowest of them (a round of runs ends with its slowest run). Only runs that played at least 60% of the
    stop (and 300 s) count: a run that died early played only the light early game, several times faster than the late
    one. And only a sim where most runs (80%) played that long is recorded: when most die early the survivors have the
    PC to themselves and run faster than that many at once would."""
    rates, boots = [], []
    longest = max([float(p.get("end_t") or 0) for p in players if p.get("ok")] or [0.0])
    floor = max(300.0, 0.6 * float(limit or longest))
    n_ok = sum(1 for p in players if p.get("ok"))
    for p in players:
        if not p.get("ok") or not p.get("wall_s") or not p.get("end_t") or float(p["end_t"]) < floor:
            continue
        play = float(p["end_t"])
        if p.get("rate"):
            rates.append(float(p["rate"]))
            boots.append(float(p.get("boot_s") or 0.0))
        elif play >= 30:
            boot = float(p.get("boot_s") or 0.0)
            rates.append(play / max(1.0, float(p["wall_s"]) - boot))
            boots.append(boot)
    if len(rates) < max(2, math.ceil(0.8 * n_ok)):
        return None   # too few long runs to say (a short test sim, or most runs died early)
    d = read_json(speed_file()) or {}
    hist = [h for h in (d.get("history") or []) if isinstance(h, dict)]
    rec = {"play_per_wall": round(statistics.median(rates), 3), "slow": round(min(rates), 3),   # a round ends with its slowest run
           "boot_s": round(statistics.median(boots), 1) if boots else 18.0,
           "workers": int(workers), "fps": int(fps), "players": len(rates), "fast": bool(fast), "updated": _now_iso()}
    hist.append(rec)
    write_json(speed_file(), {"history": hist[-20:]}, indent=1)
    return rec


# ---------------------------------------------------------------- the sim lock (tools/locks.py's owner.json, its own name)

def lock_status():
    """None when free; else {owner_file, pid, who, job, note, since, beat, host, age_s, alive}."""
    p = lock_path()
    if not os.path.isdir(p):
        return None
    d = {"owner_file": False, "pid": 0, "who": "unknown process", "job": "", "note": "", "host": ""}
    o = read_json(os.path.join(p, "owner.json"), tries=3)
    if isinstance(o, dict):
        d.update(o)
        d["owner_file"] = True
    try:
        since = float(d.get("since") or os.path.getmtime(p))
    except (OSError, TypeError, ValueError):
        since = time.time()
    d["since"] = since
    d["age_s"] = max(0.0, time.time() - since)
    d["alive"] = locks.pid_alive(d.get("pid")) if d["owner_file"] else None
    return d


def lock_force_release():
    p = lock_path()
    try:
        if os.path.exists(os.path.join(p, "owner.json")):
            os.remove(os.path.join(p, "owner.json"))
        os.rmdir(p)
    except OSError:
        pass
    return not os.path.isdir(p)


def lock_acquire(who, job="", note="", wait=True, poll=2.0, log=print, should_stop=None):
    """Take the sim lock; waits (saying who holds it) unless `wait` is False. A dead owner's lock is reclaimed. True when
    taken."""
    os.makedirs(LOCK_DIR, exist_ok=True)
    said = False
    while True:
        try:
            os.mkdir(lock_path())
        except FileExistsError:
            st = lock_status()
            if st is not None and st["owner_file"] and st["alive"] is False:
                log("sim: the sim lock was held by pid %s (%s), which is gone: reclaimed" % (st.get("pid"), st.get("who")))
                lock_force_release()
                continue
            if not wait or (should_stop and should_stop()):
                return False
            if not said:
                st = st or {}
                log("sim: waiting for the sim lock (held by %s%s, pid %s, for %d s): one sim at a time" % (
                    st.get("who", "?"), (" / " + st["job"]) if st.get("job") else "", st.get("pid"), int(st.get("age_s", 0))))
                said = True
            time.sleep(poll)
            continue
        with open(os.path.join(lock_path(), "owner.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump({"pid": os.getpid(), "who": str(who), "job": str(job), "note": str(note), "since": time.time(),
                       "beat": time.time(), "host": os.environ.get("COMPUTERNAME", "")}, f)
        return True


def lock_release():
    st = lock_status()
    if st is None:
        return True
    if st["owner_file"] and int(st.get("pid") or 0) != os.getpid():
        return False
    return lock_force_release()


# ---------------------------------------------------------------- the snapshot

SKIP_TOP = ("export", "reports", ".godot")
IMPORT_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".tga", ".bmp", ".exr", ".hdr", ".glb", ".gltf", ".fbx", ".obj",
               ".blend", ".dae", ".wav", ".ogg", ".mp3", ".ttf", ".otf", ".woff", ".woff2", ".fnt", ".csv"}
NEW_RES_EXTS = {".tscn", ".tres", ".res", ".scn", ".gdshader"}
CLASS_RE = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)


def _walk(base):
    """{rel path: (size, mtime)} under `base`, minus SKIP_TOP at the top, __pycache__ and *.tmp files."""
    out = {}
    if not os.path.isdir(base):
        return out
    for root, dirs, files in os.walk(base):
        rel_root = os.path.relpath(root, base)
        if rel_root == ".":
            dirs[:] = [d for d in dirs if d not in SKIP_TOP]
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for f in files:
            if f.endswith(".tmp"):
                continue
            p = os.path.join(root, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            rel = os.path.relpath(p, base).replace("\\", "/")
            out[rel] = (st.st_size, st.st_mtime)
    return out


def _class_name(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            m = CLASS_RE.search(f.read(8192))
        return m.group(1) if m else ""
    except OSError:
        return ""


def patch_project(text):
    """project.godot with its own user:// folder: [application] config/use_custom_user_dir=true and
    config/custom_user_dir_name="88fits_sim" (any earlier value of either replaced)."""
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(nl)
    keep = [ln for ln in lines if not re.match(r"^config/(use_custom_user_dir|custom_user_dir_name)\s*=", ln)]
    want = ["config/use_custom_user_dir=true", 'config/custom_user_dir_name="%s"' % USER_DIR_NAME]
    try:
        i = keep.index("[application]")
    except ValueError:
        return nl.join(keep + ["", "[application]", ""] + want + [""])
    j = i + 1
    while j < len(keep) and not keep[j].startswith("["):
        j += 1
    # after the section's last non-empty line
    k = j
    while k > i + 1 and keep[k - 1].strip() == "":
        k -= 1
    return nl.join(keep[:k] + want + keep[k:])


def _copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".sync.tmp"
    shutil.copy2(src, tmp)
    for i in range(20):
        try:
            os.replace(tmp, dst)
            return
        except OSError:
            time.sleep(0.05)
    os.replace(tmp, dst)


def import_reason(rel, change, old_class="", new_class=""):
    """Why a changed file makes the snapshot import again ("" = it does not): change is added | changed | removed."""
    ext = os.path.splitext(rel)[1].lower()
    if rel.endswith(".import"):
        return "an import setting (%s)" % rel
    if ext in IMPORT_EXTS:
        return "an asset %s (%s)" % (change, rel)
    if ext == ".uid":
        return "a uid file %s (%s)" % (change, rel)
    if ext in NEW_RES_EXTS and change != "changed":
        return "a scene or resource %s (%s)" % (change, rel)
    if ext == ".gd" and change != "changed":
        return "a script %s (%s)" % (change, rel)
    if ext == ".gd" and old_class != new_class:
        return "a script's class_name (%s: %s -> %s)" % (rel, old_class or "none", new_class or "none")
    return ""


def stale_json(snap):
    """The content folders whose <id>.json is newer than its <id>.tres in the snapshot (type/id; "sounds" for the sound
    map): import_json runs on them so the sim plays the saved JSON."""
    out = []
    content = os.path.join(snap, "content")
    if not os.path.isdir(content):
        return out
    for typ in sorted(os.listdir(content)):
        tdir = os.path.join(content, typ)
        if not os.path.isdir(tdir):
            continue
        if typ == "sounds":
            j, t = os.path.join(tdir, "soundmap.json"), os.path.join(tdir, "soundmap.tres")
            if os.path.isfile(j) and os.path.isfile(t) and os.path.getmtime(j) > os.path.getmtime(t) + 1.0:
                out.append("sounds")
            continue
        for cid in sorted(os.listdir(tdir)):
            j = os.path.join(tdir, cid, cid + ".json")
            t = os.path.join(tdir, cid, cid + ".tres")
            if os.path.isfile(j) and os.path.isfile(t) and os.path.getmtime(j) > os.path.getmtime(t) + 1.0:
                out.append("%s/%s" % (typ, cid))
    return out


def sync_snapshot(src=None, dst=None, log=print):
    """game/ -> the snapshot (see the module doc). Returns {copied, removed, bytes, fresh, import_reasons, secs, kept}."""
    src = src or GAME
    dst = dst or snap_game()
    t0 = time.time()
    os.makedirs(dst, exist_ok=True)
    fresh = not os.path.isdir(os.path.join(dst, ".godot"))
    reasons = []
    copied = removed = kept = 0
    nbytes = 0
    if fresh:
        sg = os.path.join(src, ".godot")
        if os.path.isdir(sg):
            log("sim: sync: a new snapshot: its .godot seeded from the real one (the imported files; a one-time copy)")
            shutil.copytree(sg, os.path.join(dst, ".godot"), ignore=shutil.ignore_patterns("shader_cache", "exported"), dirs_exist_ok=True)
        reasons.append("a new snapshot")
    have = _walk(src)
    old = _walk(dst)
    for rel, (size, mtime) in sorted(have.items()):
        sp = os.path.join(src, rel)
        dp = os.path.join(dst, rel)
        if rel == "project.godot":
            try:
                with open(sp, "r", encoding="utf-8", newline="") as f:
                    want = patch_project(f.read())
                cur = None
                if os.path.isfile(dp):
                    with open(dp, "r", encoding="utf-8", newline="") as f:
                        cur = f.read()
                if cur != want:
                    with open(dp, "w", encoding="utf-8", newline="") as f:
                        f.write(want)
                    copied += 1
            except OSError as e:
                log("sim: sync: project.godot: %s" % e)
            continue
        o = old.get(rel)
        if o is not None and o[0] == size and abs(o[1] - mtime) < 0.01:
            continue
        change = "added" if o is None else "changed"
        old_class = _class_name(dp) if (rel.endswith(".gd") and o is not None) else ""
        try:
            _copy(sp, dp)
        except OSError as e:
            log("sim: sync: could not copy %s: %s" % (rel, e))
            continue
        copied += 1
        nbytes += size
        r = import_reason(rel, change, old_class, _class_name(sp) if rel.endswith(".gd") else "")
        if r:
            reasons.append(r)
    for rel in sorted(old):
        if rel in have:
            continue
        # the snapshot's own import products beside a file that is still there are kept (a .import or .uid the real
        # project has not written yet): deleting them would import again on every sim
        if (rel.endswith(".import") and rel[:-len(".import")] in have) or (rel.endswith(".uid") and rel[:-len(".uid")] in have):
            kept += 1
            continue
        try:
            os.remove(os.path.join(dst, rel))
            removed += 1
        except OSError as e:
            log("sim: sync: could not remove %s: %s" % (rel, e))
            continue
        r = import_reason(rel, "removed")
        if r:
            reasons.append(r)
    # empty folders left by removals
    for root, dirs, files in os.walk(dst, topdown=False):
        rel_root = os.path.relpath(root, dst).replace("\\", "/")
        if rel_root == "." or rel_root.split("/")[0] in SKIP_TOP:
            continue
        if not dirs and not files:
            try:
                os.rmdir(root)
            except OSError:
                pass
    return {"copied": copied, "removed": removed, "kept": kept, "bytes": nbytes, "fresh": fresh, "import_reasons": reasons,
            "secs": round(time.time() - t0, 1)}


# ---------------------------------------------------------------- running Godot

def kill_tree(pid):
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True, timeout=30)
        else:
            os.kill(pid, 9)
        return True
    except Exception:
        return False


def run_godot(args, log_file, timeout, log=print, label="godot"):
    """One Godot process on the snapshot (no lock: the sim lock covers it), its output to `log_file`. (rc, secs, tail)."""
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    cmd = [GODOT] + list(args)
    t0 = time.time()
    with open(log_file, "w", encoding="utf-8", newline="\n") as lf:
        lf.write("$ %s\n" % " ".join(cmd))
        lf.flush()
        try:
            p = subprocess.Popen(cmd, cwd=ROOT, stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        except OSError as e:
            return -1, 0.0, ["could not start Godot: %s" % e]
        try:
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            kill_tree(p.pid)
            rc = -9
            lf.write("\nsim_batch: killed after %d s\n" % timeout)
    secs = time.time() - t0
    try:
        with open(log_file, "r", encoding="utf-8", errors="replace") as f:
            tail = [x.rstrip() for x in f.read().splitlines()[-12:]]
    except OSError:
        tail = []
    return rc, secs, tail


def project_version(snap):
    try:
        with open(os.path.join(snap, "project.godot"), "r", encoding="utf-8") as f:
            m = re.search(r'^config/version="([^"]*)"', f.read(), re.M)
        return m.group(1) if m else ""
    except OSError:
        return ""


def map_rev(game_dir, map_id):
    """The saved map the sim played: {file, sha (12 hex of the JSON's bytes), saved (its mtime), name}."""
    p = os.path.join(game_dir, "content", "maps", map_id, map_id + ".json")
    try:
        with open(p, "rb") as f:
            data = f.read()
        st = os.stat(p)
        name = map_id
        try:
            name = str(json.loads(data.decode("utf-8")).get("name") or map_id)
        except ValueError:
            pass
        return {"file": "game/content/maps/%s/%s.json" % (map_id, map_id), "sha": hashlib.sha1(data).hexdigest()[:12],
                "saved": _now_iso(st.st_mtime), "saved_epoch": st.st_mtime, "name": name}
    except OSError:
        return {"file": "", "sha": "", "saved": "", "saved_epoch": 0, "name": map_id}


# ---------------------------------------------------------------- one player

# sim_run.gd's progress line (keys_SIMRUN.md); read loosely: any "t=<s>" with optional clock=, level=, hp=, kills=
RE_PROGRESS = re.compile(r"\bt=(\d+(?:\.\d+)?)")
RE_KV = re.compile(r"\b(clock|level|hp|hp_max|kills|alive|deaths|stage)=([\d.:/]+)")


class Player:
    def __init__(self, k, seed, out_dir):
        self.k = k
        self.seed = seed
        self.json = os.path.join(out_dir, "players", "p%02d.json" % k)
        self.log = os.path.join(out_dir, "players", "p%02d.log" % k)
        self.proc = None
        self.state = "queued"
        self.started = None
        self.ended = None
        self.t = 0.0
        self.info = {}
        self.end_reason = ""
        self.end_t = 0.0
        self.problem = ""
        self.tail = []
        self._pos = 0
        self.first_seen = None   # (wall seconds since its start, play seconds) at its first progress line
        self.last_seen = None
        self.said_t = 0.0

    def rate(self):
        """Play seconds a wall second between its first and last progress lines (None before two lines)."""
        if not self.first_seen or not self.last_seen or self.last_seen[1] - self.first_seen[1] < 20:
            return None
        dw = self.last_seen[0] - self.first_seen[0]
        return (self.last_seen[1] - self.first_seen[1]) / dw if dw > 0 else None

    def boot_s(self):
        r = self.rate()
        if not r or not self.first_seen:
            return None
        return max(0.0, self.first_seen[0] - self.first_seen[1] / r)

    def record(self):
        now = time.time()
        return {"k": self.k, "seed": self.seed, "state": self.state, "t": round(self.t, 1), "info": self.info,
                "wall_s": round(((self.ended or now) - self.started), 1) if self.started else 0.0,
                "end_reason": self.end_reason, "end_t": round(self.end_t, 1), "problem": self.problem,
                "pid": self.proc.pid if (self.proc is not None and self.state == "running" and hasattr(self.proc, "pid")) else None}

    def see(self, t):
        if self.started is None:
            return
        w = time.time() - self.started
        if self.first_seen is None:
            self.first_seen = (w, t)
        self.last_seen = (w, t)

    def read_progress_file(self):
        """sim_run.gd's <out>.progress (keys_SIMRUN.md): {t, clock, stage, level, deaths, hp, hp_max, kills, wall_s, state}."""
        d = read_json(self.json + ".progress", tries=1)
        if not isinstance(d, dict):
            return
        t = _num(d.get("t"), 0.0)
        if t > self.t:
            self.t = t
            self.see(t)
        for key in ("clock", "stage", "level", "deaths", "kills", "state"):
            if d.get(key) is not None:
                self.info[key] = str(d[key]) if key != "clock" else fmt_t(_num(d[key]))
        if d.get("hp") is not None:
            self.info["hp"] = "%d/%d" % (int(_num(d.get("hp"))), int(_num(d.get("hp_max"))))

    def read_log(self):
        """New lines of the player's --log-file: the progress lines move its clock."""
        try:
            with open(self.log, "r", encoding="utf-8", errors="replace") as f:
                f.seek(self._pos)
                chunk = f.read()
                self._pos = f.tell()
        except OSError:
            return []
        lines = chunk.splitlines()
        for ln in lines:
            if ln.strip():
                self.tail.append(ln.rstrip())
            m = RE_PROGRESS.search(ln) if ("sim" in ln or "progress" in ln) else None
            if m:
                try:
                    self.t = max(self.t, float(m.group(1)))
                except ValueError:
                    pass
                self.see(self.t)
                for key, val in RE_KV.findall(ln):
                    self.info[key] = val
        self.tail = self.tail[-30:]
        return lines


class SynthProc:
    """--synthetic: a made-up player "playing" in a thread at `speed` play seconds a wall second (0 = at once), with a
    Popen-like poll(); the progress moves as a real run's would."""

    def __init__(self, player, settings, speed):
        self.player = player
        self.data = synthetic_player(player.k, player.seed, settings)
        self.speed = float(speed or 0)
        self.rc = None
        self.pid = None
        self.th = threading.Thread(target=self._play, daemon=True)
        self.th.start()

    def _play(self):
        p, d = self.player, self.data
        end = len(d["t"])
        if self.speed > 0:
            t = 0.0
            while t < end:
                time.sleep(0.25)
                t = min(end, t + self.speed * 0.25)
                p.t = t
                p.see(t)
                p.info = {"level": str(d["level"][max(0, int(t) - 1)])}
        d["meta"]["wall_s"] = round(time.time() - p.started, 1) if self.speed > 0 else d["meta"]["wall_s"]
        write_json(p.json, d)
        self.rc = 0

    def poll(self):
        return self.rc


def player_args(settings, p, snap, out_dir, wall_cap, caps=None):
    """The runner's command line. The board goes both ways: board= the preset it equals (an older runner reads only
    that) and talents= talent by talent (lane SIMRUN's round 2: it wins over board=); fast=1 (the sim mode that skips
    the purely visual work) when the runner has it and the settings keep it on."""
    s = settings
    caps = caps or {}
    board = float(s["board"]) if float(s.get("board", 0)) >= 0 else 0.0
    args = ["--headless", "--fixed-fps", str(int(s["fps"])), "--path", snap, "--log-file", p.log,
            "--script", "res://tools/sim_run.gd", "--",
            "out=" + p.json, "hero=" + s["hero"], "seed=%d" % p.seed, "limit=%d" % int(s["limit"]), "board=%g" % board,
            "death=" + s["death"], "map=" + s["map"], "progress=%d" % PROGRESS_EVERY, "wall=%d" % max(60, int(wall_cap) - 45)]
    if s.get("talents"):
        args.append("talents=" + talents_arg(s["talents"]))   # an empty board: board=0 alone (the runner reads no "none")
    if caps.get("fast"):
        args.append("fast=%d" % (1 if s.get("fast", True) else 0))   # the runner's sim mode is on unless told fast=0
    return args


def load_player(path):
    """(data, problem): a player's JSON checked for the keys the aggregation needs."""
    d = read_json(path, tries=3)
    if d is None:
        return None, "no JSON written" if not os.path.isfile(path) else "the JSON does not parse"
    if not isinstance(d, dict):
        return None, "the JSON is not an object"
    t = d.get("t")
    if not isinstance(t, list) or not t:
        return None, "no samples (t[] is empty)"
    n = len(t)
    for key in ("hp", "level"):
        a = d.get(key)
        if not isinstance(a, list) or len(a) != n:
            return None, "%s[] is missing or not as long as t[] (%d)" % (key, n)
    return d, ""


# ---------------------------------------------------------------- the aggregation

def _num(v, default=0.0):
    try:
        f = float(v)
        return f if math.isfinite(f) else default
    except (TypeError, ValueError):
        return default


def _clock_s(v):
    """A clock value: seconds, or "m:ss"."""
    if isinstance(v, str) and ":" in v:
        bits = v.split(":")
        try:
            return float(bits[0]) * 60 + float(bits[1])
        except ValueError:
            return 0.0
    return _num(v)


def _r(x):
    if x is None:
        return None
    if isinstance(x, float):
        if not math.isfinite(x):
            return None
        ax = abs(x)
        x = round(x, 1) if ax >= 100 else round(x, 2) if ax >= 1 else round(x, 3)
        return int(x) if x == int(x) and ax < 1e15 else x
    return x


def pct(vals, q):
    """The q-th quantile (0..1) of a sorted list, linear between the nearest ranks (numpy's default)."""
    if not vals:
        return None
    if len(vals) == 1:
        return vals[0]
    pos = q * (len(vals) - 1)
    lo = int(math.floor(pos))
    hi = min(len(vals) - 1, lo + 1)
    return vals[lo] + (vals[hi] - vals[lo]) * (pos - lo)


def player_grid(d, T):
    """One player's series on whole seconds 0..T: {name: [values]}, its last second, and its breakdowns. A sample's
    second is round(t); the later sample wins a second two share; a second without a sample carries the one before
    (cumulative and level series), a rate is 0 before the first sample; seconds after the player's end are None."""
    t = [int(round(_num(x))) for x in d.get("t") or []]
    n = len(t)
    end = max(0, min(T, max(t) if t else 0))
    idx = [None] * (end + 1)
    for i, s in enumerate(t):
        if 0 <= s <= end:
            idx[s] = i
    first = next((i for i in idx if i is not None), None)

    def grid(arr, kind, conv=_num):
        out = [None] * (T + 1)
        if not isinstance(arr, list) or len(arr) != n or first is None:
            return out
        last = None
        for s in range(end + 1):
            i = idx[s]
            if i is not None:
                last = conv(arr[i])
                out[s] = last
            elif last is not None:
                out[s] = last if kind != "rate" else 0.0
            else:
                out[s] = conv(arr[first]) if kind == "level" else 0.0
        return out

    series = {}
    for key in LEVEL_SERIES:
        if key in d:
            series[key] = grid(d.get(key), "level", _clock_s if key == "clock" else _num)
    for key in CUM_SERIES:
        if key in d:
            series[key] = grid(d.get(key), "cum")
    for key in RATE_SERIES:
        if key in d:
            series[key] = grid(d.get(key), "rate")
    # any other numeric series as long as t[] (a field lane SIMRUN added): a level, carried forward
    for key, arr in d.items():
        if key in series or key in ("t", "events", "meta") or key in BREAKDOWNS or not isinstance(arr, list) or len(arr) != n:
            continue
        if arr and all(isinstance(x, (int, float)) or x is None for x in arr[: min(n, 50)]):
            series[key] = grid(arr, "level")
    if "dps" in series:
        raw = series["dps"]
        sm = [None] * (T + 1)
        acc = 0.0
        win = []
        for s in range(end + 1):
            v = raw[s] or 0.0
            win.append(v)
            acc += v
            if len(win) > DPS_WINDOW:
                acc -= win.pop(0)
            sm[s] = acc / float(len(win))
        series["dps_raw"] = raw
        series["dps"] = sm
    _derive_difficulty(d, series, end, T)
    bds = {}
    for name, kind in BREAKDOWNS.items():
        bd = d.get(name)
        if not isinstance(bd, dict):
            continue
        out = {}
        for key, arr in bd.items():
            if isinstance(arr, list) and len(arr) == n:
                out[str(key)] = grid(arr, kind)
        bds[name] = out
    # any other {id: [values]} block as long as t[] (e.g. a crowd HP by creature): a level breakdown
    for name, bd in d.items():
        if name in BREAKDOWNS or name in ("meta",) or not isinstance(bd, dict) or not name.endswith("_by"):
            continue
        out = {}
        for key, arr in bd.items():
            if isinstance(arr, list) and len(arr) == n:
                out[str(key)] = grid(arr, "level")
        if out:
            bds[name] = out
    return series, end, bds


def _run_rate(rec, m):
    """A run's play seconds a wall second after its boot: from its progress lines, else from its meta (end_t over
    wall_s less boot_s); None for a run too short to say."""
    if rec.get("rate"):
        return float(rec["rate"])
    play, wall, boot = _num(m.get("end_t")), _num(m.get("wall_s")), _num(m.get("boot_s"))
    if play >= 30 and wall - boot > 1:
        return play / (wall - boot)
    return None


def _rolling(arr, end, w):
    """A trailing mean over w seconds up to `end` (None after it); a missing second counts 0."""
    out = [None] * len(arr)
    acc, win = 0.0, []
    for s_ in range(end + 1):
        v = arr[s_] or 0.0
        win.append(v)
        acc += v
        if len(win) > w:
            acc -= win.pop(0)
        out[s_] = acc / float(len(win))
    return out


def _boss_abs(d, series, end, T):
    """The boss's current HP each second: the runner's absolute `boss_hp_abs`; else `boss_hp` when it holds HP (an
    absolute, above 1.5); else the fraction `boss_hp` x the max HP its boss_start event reported. 0 without a boss."""
    if "boss_hp_abs" in series:
        return [v if v is not None else None for v in series["boss_hp_abs"]]
    bh = series.get("boss_hp")
    if not bh:
        return None
    if max((v or 0.0) for v in bh) > 1.5:
        return bh
    mx = [0.0] * (T + 1)
    cur = 0.0
    evs = sorted((e for e in d.get("events") or [] if isinstance(e, dict) and e.get("kind") in ("boss_start", "boss_end")),
                 key=lambda e: _num(e.get("t")))
    i = 0
    for s_ in range(end + 1):
        while i < len(evs) and _num(evs[i].get("t")) <= s_ + 0.5:
            cur = _num(evs[i].get("hp")) if evs[i].get("kind") == "boss_start" else 0.0
            i += 1
        mx[s_] = cur
    return [(bh[s_] or 0.0) * mx[s_] if s_ <= end and bh[s_] is not None else None for s_ in range(T + 1)]


def _derive_difficulty(d, series, end, T):
    """Round 2 (Garry: "a better way of knowing how difficult a given second of the game is"): per run, per second,
    - danger: HP lost that second as % of max HP (before healing), danger_net: after healing (each over 5 s, as DPS);
    - keep_up: seconds of this run's own DPS (5 s) to clear the crowd alive without the boss ((crowd HP - boss HP) / DPS),
      boss_s: the boss alone (boss HP / DPS) while one lives; neither where the DPS is under 1;
    - trouble: 100 while under 30 % of max HP, else 0 (its mean = the share of runs in trouble);
    - kills_ps, spawned_ps, hits_ps: a second's kills (from the running total), spawns and hits, over 10 s."""
    hp, hm = series.get("hp"), series.get("hp_max")
    took, healed = series.get("took"), series.get("healed")
    if took and hm:
        lost = [100.0 * (took[s_] or 0.0) / hm[s_] if s_ <= end and hm[s_] else None for s_ in range(T + 1)]
        series["danger"] = _rolling([v or 0.0 for v in lost], end, DPS_WINDOW)
        if healed:
            net = [100.0 * ((took[s_] or 0.0) - (healed[s_] or 0.0)) / hm[s_] if s_ <= end and hm[s_] else 0.0 for s_ in range(T + 1)]
            series["danger_net"] = _rolling(net, end, DPS_WINDOW)
    if hp and hm:
        series["trouble"] = [(100.0 if (hp[s_] or 0.0) < TROUBLE_FRAC * hm[s_] else 0.0) if s_ <= end and hm[s_] else None for s_ in range(T + 1)]
    if series.get("kills"):
        k = series["kills"]
        per = [max(0.0, (k[s_] or 0.0) - (k[s_ - 1] or 0.0)) if s_ > 0 else (k[0] or 0.0) for s_ in range(end + 1)] + [None] * (T - end)
        series["kills_ps"] = _rolling(per, end, RATE_WINDOW)
    for key, out in (("spawned", "spawned_ps"), ("hits", "hits_ps")):
        if series.get(key):
            series[out] = _rolling(series[key], end, RATE_WINDOW)
    dps = series.get("dps")   # already smoothed over DPS_WINDOW
    crowd = series.get("press_hp")
    if dps and crowd:
        boss = _boss_abs(d, series, end, T) or [0.0] * (T + 1)
        ku, bs = [None] * (T + 1), [None] * (T + 1)
        for s_ in range(end + 1):
            dv = dps[s_] or 0.0
            if dv < 1.0:
                continue
            b = boss[s_] or 0.0
            ku[s_] = max(0.0, (crowd[s_] or 0.0) - b) / dv
            if b > 0.0:
                bs[s_] = b / dv
        series["keep_up"] = ku
        series["boss_s"] = bs


def _bd_end(g, name, i):
    """A player's (grid tuple's) breakdown value for id `i` at his own last second; 0 when he never had it."""
    a = g[3].get(name, {}).get(i)
    if not a:
        return 0.0
    return a[g[2]] or 0.0


def _medians(vals):
    vals = [v for v in vals if v is not None]
    return statistics.median(vals) if vals else None


def _median_series(grids, key, T):
    """A ratio series: its middle value over the runs that have one at that second (still playing, a DPS over 1), the
    10th and 90th percentiles, and how many runs it is over."""
    med, p10, p90, n = [], [], [], []
    for s_ in range(T + 1):
        vals = sorted(g[1][key][s_] for g in grids if key in g[1] and s_ < len(g[1][key]) and g[1][key][s_] is not None)
        n.append(len(vals))
        if not vals:
            med.append(None)
            p10.append(None)
            p90.append(None)
            continue
        med.append(_r(pct(vals, 0.5)))
        p10.append(_r(pct(vals, 0.1)))
        p90.append(_r(pct(vals, 0.9)))
    return {"median": med, "p10": p10, "p90": p90, "n": n}


def board_check(settings, ok_players):
    """Whether every run played the board asked for (lane SIMRUN's meta.talents {talent: ranks}): [] when they all did,
    else a sentence per run that did not (an older runner plays only board= presets)."""
    want = {k: len(v) for k, v in (settings.get("talents") or {}).items() if v}
    want_forms = {k: v for k, v in (settings.get("talents") or {}).items() if v}
    out = []
    for k, d, rec in ok_players:
        forms = (d.get("meta") or {}).get("talent_forms")
        if isinstance(forms, dict):
            # the runner's own picks, rank by rank (lane SIMRUN's meta.talent_forms): the board exactly
            forms = {str(a): str(b) for a, b in forms.items() if b}
            if forms != want_forms:
                diff = sorted(set(want_forms) | set(forms))
                out.append("run %d played %s" % (k, ", ".join("%s %s (asked %s)" % (t, forms.get(t, "-"), want_forms.get(t, "-")) for t in diff if forms.get(t) != want_forms.get(t))))
            continue
        got = (d.get("meta") or {}).get("talents")
        if not isinstance(got, dict):
            continue
        got = {str(a): int(_num(b)) for a, b in got.items() if int(_num(b)) > 0}
        if got != want:
            diff = sorted(set(want) | set(got))
            out.append("run %d played %s" % (k, ", ".join("%s %d (asked %d)" % (t, got.get(t, 0), want.get(t, 0)) for t in diff if got.get(t, 0) != want.get(t, 0))))
    return out


def markers(players):
    """The stage starts and the boss fights as medians over the players who reached them (events: stage {stage},
    boss_start / boss_end {id}); every death's time."""
    stages, bosses, deaths, revives = {}, {}, [], []
    for d in players:
        seen_stage = {}
        occ = {}
        cur = {}
        for e in d.get("events") or []:
            if not isinstance(e, dict):
                continue
            kind = str(e.get("kind", ""))
            t = _num(e.get("t"), None)
            if t is None:
                continue
            if kind == "stage":
                st = int(_num(e.get("stage"), 0))
                if st > 1 and st not in seen_stage:
                    seen_stage[st] = t
            elif kind == "boss_start":
                bid = str(e.get("id") or "boss")
                n = occ.get(bid, 0)
                occ[bid] = n + 1
                cur[bid] = (bid, n, t)
                b = bosses.setdefault((bid, n), {"start": [], "end": [], "mult": [], "hp": [], "fights": []})
                b["start"].append(t)
                if e.get("mult") is not None:
                    b["mult"].append(_num(e.get("mult"), 1.0))
                if e.get("hp") is not None:
                    b["hp"].append(_num(e.get("hp")))
            elif kind == "boss_end":
                bid = str(e.get("id") or "boss")
                c = cur.pop(bid, (bid, max(0, occ.get(bid, 1) - 1), None))
                b = bosses.setdefault((c[0], c[1]), {"start": [], "end": [], "mult": [], "hp": [], "fights": []})
                b["end"].append(t)
                if c[2] is not None:
                    b["fights"].append(t - c[2])   # this run's own fight
            elif kind == "death":
                deaths.append(t)
            elif kind == "revive":
                revives.append(t)
        for st, t in seen_stage.items():
            stages.setdefault(st, []).append(t)
    out_st = [{"stage": st, "t": _r(_medians(v)), "n": len(v), "min": _r(min(v)), "max": _r(max(v))} for st, v in sorted(stages.items())]
    out_b = []
    for (bid, n), v in sorted(bosses.items(), key=lambda kv: (_medians(kv[1]["start"]) or 1e9)):
        out_b.append({"id": bid, "occurrence": n + 1, "start": _r(_medians(v["start"])), "end": _r(_medians(v["end"])),
                      "n": len(v["start"]), "beaten": len(v["end"]),
                      "fight_s": _r(_medians(v["fights"])) if v["fights"] else None,
                      "mult": _r(_medians(v["mult"])), "hp": _r(_medians(v["hp"]))})
    return {"stages": out_st, "bosses": out_b, "deaths": sorted(_r(x) for x in deaths), "revives": sorted(_r(x) for x in revives)}


def content_names(game_dir, ids):
    """{id: display name} for the ids from the content folders (weapons, evolutions, passives, mutations, perks, enemies,
    bosses, characters, pickups, structures); the rest worded from the id."""
    want = set(i for i in ids if i)
    out = {}
    if want:
        for typ in ("weapons", "evolutions", "passives", "mutations", "perks", "enemies", "bosses", "characters", "pickups", "structures", "elites"):
            tdir = os.path.join(game_dir, "content", typ)
            if not os.path.isdir(tdir):
                continue
            for cid in os.listdir(tdir):
                if cid not in want or cid in out:
                    continue
                d = read_json(os.path.join(tdir, cid, cid + ".json"), tries=1)
                if isinstance(d, dict) and d.get("name"):
                    out[cid] = str(d["name"])
    for i in want:
        if i not in out:
            out[i] = SOURCE_WORDS.get(i) or i.replace("_", " ").capitalize()
    return out


def aggregate(players, settings, meta=None, game_dir=None):
    """`players`: [(k, data or None, record)] (record: {k, seed, end_reason, end_t, wall_s, problem}). The result dict
    (the rules: the module doc, balancing_SIMUI.md)."""
    s, _ = clean_settings(settings, legacy=True)
    ok = [(k, d, rec) for k, d, rec in players if d is not None]
    limit = int(_num((settings or {}).get("limit"), s["limit"]))   # as given (clean_settings clamps a short test's)
    ends = []
    grids = []
    T = 0
    for k, d, rec in ok:
        tt = [int(round(_num(x))) for x in d.get("t") or []]
        if tt:
            T = max(T, min(limit, max(tt)))
    for k, d, rec in ok:
        series, end, bds = player_grid(d, T)
        grids.append((k, series, end, bds, d))
        ends.append(end)
    n_all = len(grids)
    playing = [sum(1 for e in ends if s_ <= e) for s_ in range(T + 1)]
    names_series = set()
    for _, series, _, _, _ in grids:
        names_series.update(series.keys())
    out_series = {}
    for key in sorted(names_series):
        if key == "deaths":
            continue
        if key in MEDIAN_SERIES:
            out_series[key] = _median_series(grids, key, T)
            continue
        mean, p10, p90, med = [], [], [], []
        band = key in BAND_SERIES
        for s_ in range(T + 1):
            vals = [g[1][key][s_] for g in grids if key in g[1] and g[1][key][s_] is not None]
            if not vals:
                mean.append(None)
                if band:
                    p10.append(None)
                    p90.append(None)
                if key in ("clock", "stage"):
                    med.append(None)
                continue
            mean.append(_r(sum(vals) / len(vals)))
            if band or key in ("clock", "stage"):
                sv = sorted(vals)
                if band:
                    p10.append(_r(pct(sv, 0.1)))
                    p90.append(_r(pct(sv, 0.9)))
                if key in ("clock", "stage"):
                    med.append(_r(pct(sv, 0.5)))
        rec = {"mean": mean}
        if band:
            rec["p10"], rec["p90"] = p10, p90
        if key in ("clock", "stage"):
            rec = {"median": med}
        out_series[key] = rec
    # deaths: every player counts at every second, an ended run keeping its last count
    if any("deaths" in g[1] for g in grids):
        dm = []
        for s_ in range(T + 1):
            tot = 0.0
            for g in grids:
                arr = g[1].get("deaths")
                if not arr:
                    continue
                v = arr[min(s_, g[2])]
                tot += v or 0.0
            dm.append(_r(tot / max(1, n_all)))
        out_series["deaths"] = {"mean": dm, "over": "all"}
    # the breakdowns: means over the players still playing (an id a player never had counts 0 for him)
    out_bd = {}
    all_ids = set()
    bd_names = set()
    for g in grids:
        bd_names.update(g[3].keys())
    for name in sorted(bd_names):
        ids = set()
        for g in grids:
            ids.update(g[3].get(name, {}).keys())
        means = {}
        for i in ids:
            arr = []
            for s_ in range(T + 1):
                n = 0
                tot = 0.0
                for g in grids:
                    if s_ > g[2]:
                        continue
                    n += 1
                    a = g[3].get(name, {}).get(i)
                    if a is not None and a[s_] is not None:
                        tot += a[s_]
                arr.append(_r(tot / n) if n else None)
            means[i] = arr
        kind = BREAKDOWNS.get(name, "level")
        if kind == "cum":
            # by each player's final value (his own end), so a late death does not reorder them
            score = {i: sum(_bd_end(g, name, i) for g in grids) for i in ids}
        else:
            score = {i: sum(v for v in means[i] if v is not None) for i in ids}
        order = sorted(ids, key=lambda i: (-score[i], i))
        out_bd[name] = {"kind": kind, "order": order, "mean": means, "score": {i: _r(score[i] / max(1, n_all)) for i in ids}}
        all_ids.update(ids)
    # per player: how his run went
    plist = []
    for k, d, rec in players:
        m = (d or {}).get("meta") or {}
        g = next((x for x in grids if x[0] == k), None)

        def at_end(key):
            if g is None or key not in g[1]:
                return None
            return _r(g[1][key][g[2]])

        ev = (d or {}).get("events") or []
        plist.append({"k": k, "seed": rec.get("seed"), "ok": d is not None, "end_reason": str(m.get("end_reason") or rec.get("end_reason") or ("" if d else "failed")),
                      "end_t": _r(_num(m.get("end_t"), g[2] if g else 0)) if d else _r(rec.get("end_t") or 0),
                      "wall_s": _r(_num(m.get("wall_s"), rec.get("wall_s") or 0)) if d else _r(rec.get("wall_s") or 0),
                      "boot_s": _r(rec.get("boot_s") if rec.get("boot_s") is not None else m.get("boot_s")),
                      "rate": _r(_run_rate(rec, m)),
                      "problem": rec.get("problem", "") if d is None else "",
                      "deaths": at_end("deaths"), "revives": sum(1 for e in ev if isinstance(e, dict) and e.get("kind") == "revive"),
                      "level": at_end("level"), "kills": at_end("kills"), "gold": at_end("gold_total"), "xp": at_end("xp_total"),
                      "dmg": _r(sum(_bd_end(g, "dmg_by", i) for i in g[3].get("dmg_by", {}))) if g else None,
                      "fps": m.get("fps"), "build": str(m.get("build_text") or ""), "assists": m.get("assists"),
                      "end_stage": m.get("end_stage"), "endless_wave": m.get("endless_wave"), "talents": m.get("talents") or {}})
    mk = markers([d for _, d, _ in ok])
    names = content_names(game_dir or snap_game(), set(all_ids) | {b["id"] for b in mk["bosses"]} | {s["hero"]})
    reached = sum(1 for p in plist if p["ok"] and _num(p["end_t"]) >= limit - 1.5)

    def end_mean(key):
        vals = [_num(p[key]) for p in plist if p["ok"] and p[key] is not None]
        return _r(sum(vals) / len(vals)) if vals else None

    summary = {"players": len(players), "ok": n_all, "failed": len(players) - n_all, "reached_limit": reached,
               "median_end_t": _r(_medians([_num(p["end_t"]) for p in plist if p["ok"]])),
               "deaths_mean": end_mean("deaths"), "revives_mean": end_mean("revives"), "kills_mean": end_mean("kills"),
               "level_mean": end_mean("level"), "gold_mean": end_mean("gold"), "xp_mean": end_mean("xp"), "dmg_mean": end_mean("dmg"),
               "bosses": [{"id": b["id"], "occurrence": b["occurrence"], "reached": b["n"], "beaten": b["beaten"], "fight_s": b["fight_s"],
                           "mult": b.get("mult")} for b in mk["bosses"]]}
    res = {"schema": SCHEMA, "meta": dict(meta or {}), "settings": s, "names": names, "t": list(range(T + 1)), "playing": playing,
           "series": out_series, "breakdowns": out_bd, "markers": mk, "players": plist, "summary": summary,
           "rules": {"dps_window": DPS_WINDOW, "rate_window": RATE_WINDOW, "trouble": TROUBLE_FRAC, "bands": list(BAND_SERIES),
                     "medians": list(MEDIAN_SERIES), "fold": FOLD_DEFAULT}}
    res["meta"].setdefault("hero_name", names.get(s["hero"], s["hero"]))
    bc = board_check(s, ok)
    if bc:
        res["meta"]["board_differs"] = bc[:10]
    # what the runs played with (lane SIMRUN's meta): every item unlocked ("all") or the save's, the bot's assists
    ms = [d.get("meta") or {} for _, d, _ in ok]
    unl = sorted({str(m.get("unlocks")) for m in ms if m.get("unlocks")})
    if unl:
        res["meta"]["unlocks"] = unl[0] if len(unl) == 1 else "mixed"
    res["meta"]["assists"] = sum(int(_num(m.get("assists"), 0)) for m in ms)
    # the runner's sim mode as the runs played it (a runner from before it had none: everything drawn)
    if ms and not any(m.get("synthetic") for m in ms):
        res["meta"]["sim_mode"] = any(bool(m.get("fast")) for m in ms)
    return res


# ---------------------------------------------------------------- made-up players (the page's and the selftest's fixture)

def synthetic_player(k, seed, settings, creatures=None):
    """A plausible player file in lane SIMRUN's schema (tools/dl/p77/keys_SIMRUN.md), deterministic per seed: the hero
    levels up, weapons join, the crowd grows by stage, bosses at the clock's 7:10 / 14:20 / 21:30 freeze the clock, deaths
    follow the death mode. NOT the game: only for checking the aggregation and the page (meta.synthetic is true)."""
    s, _ = clean_settings(settings)
    rng = random.Random(int(seed) * 7919 + 17)
    limit = int(s["limit"])
    strength = rng.uniform(0.75, 1.3)
    creatures = creatures or ["red_goblin", "red_goblin_runt", "lesser_scorpion", "dust_mummy", "bull_beetle", "horned_toad", "werewolf",
                              "blue_slime", "spit_cactus"]
    weapons = ["revolver", "tommy_gun", "boomstick", "molotov", "zap_beam"]
    keys = ("t", "clock", "stage", "phase", "hp", "hp_max", "dps", "est", "alive", "cap", "press_hp", "press_dmg", "boss_hp", "gold_total",
            "gold", "dmg_total", "kills", "level", "xp_total", "took", "healed", "deaths", "near3", "near6", "hits", "spawned", "mult_hp",
            "mult_dmg", "boss_hp_abs")
    out = {k_: [] for k_ in keys}
    alive_by = {c: [] for c in creatures}
    kills_by = {c: [] for c in creatures}
    dmg_by = {w: [] for w in weapons + ["revive"]}
    gold_by = {g: [] for g in ("gems", "chest", "boss")}
    took_by = {c: [] for c in creatures[:5]}
    healed_by = {h: [] for h in ("regen", "heart", "lifesteal")}
    held_by = {h: [] for h in ("weapons", "evolutions", "lines", "passives", "perks")}
    tb = {c: 0.0 for c in took_by}
    hb = {h: 0.0 for h in healed_by}
    events = [{"t": 0.0, "clock": 0.0, "kind": "stage", "stage": 1}]
    clock, stage, hp, level, xp, gold, purse, kills, deaths = 0.0, 1, 100.0, 1, 0.0, 0.0, 0.0, 0.0, 0
    revives = {"gold": 0, "phoenix": 0, "keep": 0}
    kb = {c: 0.0 for c in creatures}
    db = {w: 0.0 for w in dmg_by}
    gb = {g: 0.0 for g in gold_by}
    boss_left, boss_i, portal_left = 0, 0, 0
    boss_at = [430, 860, 1290]
    boss_ids = ["tumbleweed_king", "gila_grande", "brander"]
    joined = {"revolver": 0}
    end_reason = "limit"
    for t in range(1, limit + 1):
        phase = 0
        if boss_left > 0:
            phase = 1
            boss_left -= 1
            if boss_left == 0:
                events.append({"t": float(t), "clock": clock, "kind": "boss_end", "id": boss_ids[boss_i]})
                boss_i += 1
                portal_left = 15
        elif portal_left > 0:
            phase = 2
            portal_left -= 1
            if portal_left == 0:
                events.append({"t": float(t), "clock": clock, "kind": "portal", "stage": stage})
                stage += 1
                events.append({"t": float(t), "clock": clock, "kind": "stage", "stage": stage})
        else:
            clock += 1
            if boss_i < 3 and clock >= boss_at[boss_i]:
                boss_left = int(rng.uniform(40, 90) / strength)
                events.append({"t": float(t), "clock": clock, "kind": "boss_start", "id": boss_ids[boss_i], "mult": round(rng.uniform(0.8, 1.6), 2),
                               "hp": [3000, 21000, 90000][boss_i]})
        xp += (2.5 + clock * 0.03) * strength * rng.uniform(0.6, 1.4)
        while sum((15 + 6 * L + 0.5 * L * L) * 2.1 for L in range(1, level + 1)) <= xp:
            level += 1
            events.append({"t": float(t), "clock": clock, "kind": "level", "level": level})
            if level in (3, 7, 12, 18):
                joined[weapons[len(joined)]] = t
        est = sum(12.0 * (1 + 0.18 * level) * strength * (1.0 if w == "revolver" else 0.8) for w in joined)
        dps = max(0.0, est * rng.uniform(0.4, 1.3) * (1.4 if phase == 1 else 1.0))
        for w in joined:
            db[w] += dps / len(joined)
        hp_max = 100.0 + 2.0 * level
        stage_mult = [1, 2.2, 3.34, 4.5][min(3, stage - 1)]
        cap = 40 + clock * 0.08
        alive = max(0.0, cap * rng.uniform(0.85, 1.1)) if phase != 2 else 0.0
        pressure = (0.7 + 0.2 * stage) / strength
        regen = 0.6 + 0.02 * level
        took = 0.0
        hits = 0
        if rng.random() < 0.03 * pressure * (3.0 if phase == 1 else 1.0):
            took = rng.uniform(8, 35) * pressure * (1 + 0.15 * (stage - 1))
            hits = 1 + int(rng.random() * 3)
            tb[creatures[min(4, int(clock // 300))]] += took
        hp = min(hp_max, hp + regen) - took
        if hp <= 0:
            deaths += 1
            events.append({"t": float(t), "clock": clock, "kind": "death", "killer": "bull_beetle", "hit": "melee"})
            if s["death"] == "end" or (s["death"] == "gold" and (revives["gold"] >= 1 or purse < 150)):
                hp = 0.0
                end_reason = "death"
            else:
                via = "gold" if s["death"] == "gold" else "keep"
                revives[via] += 1
                if via == "gold":
                    purse -= 150
                hp = hp_max * (0.5 if via == "gold" else 1.0)
                events.append({"t": float(t), "clock": clock, "kind": "revive", "via": via})
                db["revive"] += 300.0
        per = alive * 0.06 * strength * rng.uniform(0.5, 1.5)
        kills += per
        g_gems, g_chest = per * 0.12, (35.0 if rng.random() < 0.01 else 0.0)
        g_boss = 60.0 if (phase == 1 and boss_left == 0) else 0.0
        gb["gems"] += g_gems
        gb["chest"] += g_chest
        gb["boss"] += g_boss
        gold += g_gems + g_chest + g_boss
        purse += g_gems + g_chest + g_boss
        window = [c for i, c in enumerate(creatures) if i * 150 <= clock < i * 150 + 600] or creatures[-2:]
        for c in creatures:
            share = (1.0 / len(window)) if c in window else 0.0
            alive_by[c].append(int(round(alive * share)))
            kb[c] += per * share
            kills_by[c].append(int(kb[c]))
        for w in dmg_by:
            dmg_by[w].append(round(db[w], 1))
        for g in gold_by:
            gold_by[g].append(int(gb[g]))
        hb["regen"] += regen * 0.7
        hb["lifesteal"] += regen * 0.3
        if hp < hp_max * 0.5 and rng.random() < 0.01:
            hb["heart"] += 30.0
        for c in took_by:
            took_by[c].append(round(tb[c], 1))
        for h in healed_by:
            healed_by[h].append(round(hb[h], 1))
        nw = len(joined)
        for h, v in (("weapons", nw - (1 if level >= 25 else 0)), ("evolutions", 1 if level >= 25 else 0), ("lines", min(5, level // 6)),
                     ("passives", level // 4), ("perks", min(3, level // 15))):
            held_by[h].append(int(max(0, v)))
        boss_abs = ([3000, 21000, 90000][min(2, boss_i)] * 0.5) if phase == 1 else 0.0
        row = {"t": t, "clock": round(clock, 1), "stage": stage, "phase": phase, "hp": round(max(0.0, hp), 1), "hp_max": hp_max,
               "dps": round(dps, 1), "est": round(est, 1), "alive": int(round(alive)), "cap": int(cap), "press_hp": round(alive * 18 * stage_mult, 1),
               "press_dmg": round(alive * 4 * stage_mult, 1), "boss_hp": 0.5 if phase == 1 else 0.0, "gold_total": int(gold), "gold": int(max(0, purse)),
               "dmg_total": round(sum(db.values()), 1), "kills": int(kills), "level": level, "xp_total": round(xp, 1), "took": round(took, 1),
               "healed": round(regen, 2), "deaths": deaths, "near3": int(alive * 0.04 * pressure * rng.uniform(0.3, 1.7)),
               "near6": int(alive * 0.12 * pressure * rng.uniform(0.5, 1.5)), "hits": hits, "spawned": int(per * rng.uniform(0.8, 1.3)),
               "mult_hp": round(stage_mult * (1 + clock / 1500.0) * (1 + 0.03 * level), 3), "mult_dmg": round(stage_mult * (1 + clock / 3000.0), 3),
               "boss_hp_abs": round(boss_abs, 1)}
        for k_ in keys:
            out[k_].append(row[k_])
        if end_reason == "death":
            break
    end_t = float(out["t"][-1])
    events.append({"t": end_t, "clock": clock, "kind": "end", "reason": end_reason})
    out["alive_by"] = alive_by
    out["kills_by"] = kills_by
    out["dmg_by"] = {w: v for w, v in dmg_by.items() if any(v)}
    out["gold_by"] = gold_by
    out["took_by"] = took_by
    out["healed_by"] = healed_by
    out["held_by"] = held_by
    out["events"] = events
    out["meta"] = {"schema": 1, "hero": s["hero"], "seed": seed, "board": s["board"], "death": s["death"], "limit": limit, "map": s["map"],
                   "map_rev": "", "version": "synthetic", "fps": s["fps"], "wall_s": round(12.0 + end_t / 4.0, 1), "boot_s": 12.0,
                   "end_reason": end_reason, "end_t": end_t, "end_stage": stage, "end_level": level, "deaths": deaths, "revives": revives,
                   "assists": 0, "kills": int(kills), "gold_total": int(gold), "xp_total": round(xp, 1), "dmg_total": round(sum(db.values()), 1),
                   "build_text": " · ".join("%s %d" % (w.replace("_", " ").title(), 1 + level // 10) for w in joined), "rows": len(out["t"]),
                   "talents": {k: len(v) for k, v in (s.get("talents") or {}).items()}, "unlocks": "all", "synthetic": True}
    return out


# ---------------------------------------------------------------- the history

def head_of(res):
    """The small part of a result the history lists (head.json): meta, settings, summary, the hero's name, the bosses."""
    names = res.get("names") or {}
    mk = res.get("markers") or {}
    return {"schema": res.get("schema"), "meta": res.get("meta") or {}, "settings": res.get("settings") or {}, "summary": res.get("summary") or {},
            "hero_name": names.get((res.get("settings") or {}).get("hero", ""), ""), "T": len(res.get("t") or []) - 1,
            "bosses": [{"id": b.get("id"), "name": names.get(b.get("id"), b.get("id")), "start": b.get("start"), "end": b.get("end"),
                        "n": b.get("n"), "beaten": b.get("beaten")} for b in mk.get("bosses") or []]}


def list_sims():
    """Every sim folder under runs/: [{id, path, started (epoch), kept, running}] newest first."""
    base = runs_dir()
    out = []
    if not os.path.isdir(base):
        return out
    for name in os.listdir(base):
        p = os.path.join(base, name)
        if not os.path.isdir(p):
            continue
        prog = read_json(os.path.join(p, "progress.json"), tries=2) or {}
        started = _num(prog.get("started_epoch"), 0) or os.path.getmtime(p)
        running = prog.get("state") in ("starting", "waiting", "syncing", "importing", "running", "aggregating") and locks.pid_alive(prog.get("driver_pid"))
        out.append({"id": name, "path": p, "started": started, "kept": os.path.isfile(os.path.join(p, "kept")), "running": bool(running)})
    out.sort(key=lambda r: -r["started"])
    return out


def prune_history(keep=HISTORY_KEEP, log=print, protect=()):
    """The newest `keep` sims stay, and every kept or running one; older folders are deleted."""
    gone = []
    n = 0
    for r in list_sims():
        if r["kept"] or r["running"] or r["id"] in protect:
            continue
        n += 1
        if n <= keep:
            continue
        try:
            shutil.rmtree(r["path"])
            gone.append(r["id"])
        except OSError as e:
            log("sim: could not remove the old sim %s: %s" % (r["id"], e))
    if gone:
        log("sim: history: removed %d old sim%s (%s)" % (len(gone), "" if len(gone) == 1 else "s", ", ".join(gone)))
    return gone


# ---------------------------------------------------------------- the batch

class Batch:
    def __init__(self, args):
        self.args = args
        self.out = os.path.abspath(args.out)
        raw = {k: getattr(args, k) for k in DEFAULTS if hasattr(args, k)}
        raw["fast"] = not getattr(args, "no_fast", False)
        self.settings, probs = clean_settings(raw)
        if probs:
            raise SystemExit("sim: error: " + "; ".join(probs))
        self.job = args.job or ""
        self.players = [Player(k, self.settings["seed"] + k - 1, self.out) for k in range(1, self.settings["players"] + 1)]
        self.t0 = time.time()
        self.state = "starting"
        self.message = ""
        self.sync = {}
        self.snap = os.path.abspath(args.snap) if args.snap else snap_game()
        self.map_rev = {}
        self.version = ""
        self.lock_wait = ""
        self.last_progress = 0.0
        self.wall_cap = int(args.wall_cap or max(900, self.settings["limit"] * 2))
        self.speed = load_speed()
        self.caps = runner_caps(self.snap if os.path.isdir(self.snap) else GAME)
        self.result_players = 0
        self.last_partial = 0.0

    # -- reporting
    def say(self, msg):
        print(msg, flush=True)

    def progress(self, force=False):
        now = time.time()
        if not force and now - self.last_progress < 1.5:
            return
        self.last_progress = now
        done = sum(1 for p in self.players if p.state in ("done", "failed"))
        rec = {"id": os.path.basename(self.out), "job": self.job, "state": self.state, "message": self.message, "driver_pid": os.getpid(),
               "started": _now_iso(self.t0), "started_epoch": self.t0, "beat": now, "elapsed_s": round(now - self.t0, 1),
               "eta_s": self.eta_left(), "settings": self.settings, "done": done, "failed": sum(1 for p in self.players if p.state == "failed"),
               "total": len(self.players), "players": [p.record() for p in self.players], "lock_wait": self.lock_wait,
               "sync": self.sync, "result_players": self.result_players, "synthetic": bool(self.args.synthetic)}
        write_json(os.path.join(self.out, "progress.json"), rec)

    def eta_left(self):
        """Seconds left: each running run's remaining play at its own measured rate (its progress lines), the queued ones
        in rounds at the running runs' middle rate (else the last sims' speed)."""
        rates = sorted(r for r in (p.rate() for p in self.players if p.state in ("running", "done")) if r)
        ppw = rates[len(rates) // 2] if rates else float(self.speed.get("play_per_wall") or 2.5)
        limit = self.settings["limit"]
        k = max(1, self.settings["workers"])
        running = [p for p in self.players if p.state == "running"]
        queued = [p for p in self.players if p.state == "queued"]
        if self.state in ("starting", "waiting", "syncing", "importing"):
            return eta_seconds(self.settings, self.speed, sync_s=0)
        left_running = max([max(0.0, limit - p.t) / (p.rate() or ppw) + (0 if p.rate() else float(self.speed.get("boot_s") or 18.0)) for p in running] or [0.0])
        rounds = math.ceil(len(queued) / float(k)) if queued else 0
        return int(round(left_running + rounds * (limit / ppw + float(self.speed.get("boot_s") or 12.0))))

    # -- the steps
    def take_lock(self):
        self.state = "waiting"
        note = "%d x %s to %s" % (self.settings["players"], self.settings["hero"], fmt_t(self.settings["limit"]))

        def log(m):
            self.lock_wait = m
            self.say(m)
            self.progress(force=True)
        ok = lock_acquire("sim_batch", job=self.job, note=note, wait=True, log=log)
        self.lock_wait = ""
        return ok

    def do_sync(self):
        self.state = "syncing"
        self.progress(force=True)
        if self.args.no_sync:
            self.say("sim: sync: skipped (--no-sync): the snapshot plays as it is")
            self.sync = {"skipped": True}
        else:
            r = sync_snapshot(GAME, self.snap, log=self.say)
            self.sync = dict(r)
            self.say("sim: sync: copied %d files (%.1f MB), removed %d, in %.1f s%s" % (
                r["copied"], r["bytes"] / 1048576.0, r["removed"], r["secs"], " (a new snapshot)" if r["fresh"] else ""))
            if r["import_reasons"]:
                self.state = "importing"
                self.progress(force=True)
                why = r["import_reasons"][0] + ("" if len(r["import_reasons"]) == 1 else " and %d more" % (len(r["import_reasons"]) - 1))
                self.say("sim: import: the snapshot imports again: %s" % why)
                rc, secs, tail = run_godot(["--headless", "--path", self.snap, "--import"], os.path.join(SIM_DIR, "snap_import.log"),
                                           timeout=3600 if r["fresh"] else 1800, log=self.say)
                self.sync["import_s"] = round(secs, 1)
                self.sync["import_rc"] = rc
                self.say("sim: import: done in %.1f s (exit %s)" % (secs, rc))
                if rc not in (0,):
                    self.say("sim: import: the snapshot's import said: %s" % " | ".join(tail[-4:]))
            stale = stale_json(self.snap)
            if stale:
                self.state = "importing"
                self.progress(force=True)
                self.say("sim: import_json: %d content file%s newer than its .tres (%s)" % (len(stale), "" if len(stale) == 1 else "s", ", ".join(stale[:6]) + (" ..." if len(stale) > 6 else "")))
                rc, secs, tail = run_godot(["--headless", "--path", self.snap, "--script", "res://tools/import_json.gd", "--", "only=" + ",".join(stale)],
                                           os.path.join(SIM_DIR, "snap_import_json.log"), timeout=900, log=self.say)
                self.sync["json_imported"] = stale
                self.sync["json_import_s"] = round(secs, 1)
                self.say("sim: import_json: done in %.1f s (exit %s)" % (secs, rc))
        self.map_rev = map_rev(self.snap, self.settings["map"])
        self.version = project_version(self.snap)
        if not os.path.isfile(os.path.join(self.snap, "tools", "sim_run.gd")):
            raise RuntimeError("the snapshot has no tools/sim_run.gd (lane SIMRUN's runner): nothing can play")

    def start_player(self, p):
        os.makedirs(os.path.dirname(p.json), exist_ok=True)
        for f in (p.json, p.log):
            try:
                os.remove(f)
            except OSError:
                pass
        p.started = time.time()
        p.state = "running"
        if self.args.synthetic:
            p.proc = SynthProc(p, self.settings, self.args.synthetic_speed)
            self.say("sim: run %d/%d started (seed %d, made up)" % (p.k, len(self.players), p.seed))
            return
        cmd = [GODOT] + player_args(self.settings, p, self.snap, self.out, self.wall_cap, self.caps)
        try:
            p.proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
        except OSError as e:
            p.state, p.problem, p.ended = "failed", "could not start Godot: %s" % e, time.time()
            self.say("sim: error: run %d could not start: %s" % (p.k, e))
            return
        self.say("sim: run %d/%d started (seed %d)" % (p.k, len(self.players), p.seed))

    def finish_player(self, p, rc, killed=""):
        p.ended = time.time()
        p.read_log()
        data, problem = load_player(p.json)
        if data is not None:
            m = data.get("meta") or {}
            p.state = "done"
            p.end_reason = str(m.get("end_reason") or ("stuck: the wall-time cap" if killed else ""))
            p.end_t = _num(m.get("end_t"), _num((data.get("t") or [0])[-1]))
            p.t = max(p.t, p.end_t)
            n_deaths = int(_num((data.get("deaths") or [0])[-1]))
            self.say("sim: run %d/%d done: %s at %s, %d death%s, %d s (exit %s)" % (
                p.k, len(self.players), p.end_reason or "ended", fmt_t(p.end_t), n_deaths, "" if n_deaths == 1 else "s",
                int(p.ended - p.started), rc))
        else:
            p.state = "failed"
            p.problem = (killed + ": " if killed else "") + problem
            last = " | ".join(x for x in p.tail[-3:] if x)
            self.say("sim: run %d/%d failed: %s (exit %s)%s" % (p.k, len(self.players), p.problem, rc, (": " + last) if last else ""))
        done = sum(1 for x in self.players if x.state in ("done", "failed"))
        self.say("sim: progress %d/%d runs done" % (done, len(self.players)))
        # the partial result after every finished run while that is cheap; with many runs at most every 20 s (the
        # aggregation grows with the runs), and always at the end
        if done < len(self.players) and (done <= 12 or time.time() - self.last_partial >= 20.0):
            self.write_result(partial=True)
            self.last_partial = time.time()

    def run_players(self):
        self.state = "running"
        queue = list(self.players)
        k = max(1, self.settings["workers"])
        while queue or any(p.state == "running" for p in self.players):
            while queue and sum(1 for p in self.players if p.state == "running") < k:
                self.start_player(queue.pop(0))
            for p in self.players:
                if p.state != "running" or p.proc is None:
                    continue
                if not self.args.synthetic:
                    p.read_log()
                    p.read_progress_file()
                if p.t - p.said_t >= 60:
                    p.said_t = p.t
                    lv = p.info.get("level")
                    self.say("sim: run %d at %s%s" % (p.k, fmt_t(p.t), (" (level %s)" % lv) if lv else ""))
                rc = p.proc.poll()
                if rc is not None:
                    self.finish_player(p, rc)
                elif time.time() - p.started > self.wall_cap:
                    self.say("sim: run %d ran over its %d s wall-time cap: stopped" % (p.k, self.wall_cap))
                    kill_tree(p.proc.pid)
                    try:
                        p.proc.wait(timeout=20)
                    except subprocess.TimeoutExpired:
                        pass
                    self.finish_player(p, -9, killed="over the wall-time cap")
            self.progress()
            time.sleep(0.5)

    def write_result(self, partial):
        self.state = "aggregating" if not partial else self.state
        ps = []
        for p in self.players:
            if p.state not in ("done", "failed"):
                continue
            data, _ = load_player(p.json) if p.state == "done" else (None, "")
            ps.append((p.k, data, {"seed": p.seed, "end_reason": p.end_reason, "end_t": p.end_t, "wall_s": round((p.ended or time.time()) - (p.started or time.time()), 1),
                                   "problem": p.problem, "boot_s": p.boot_s(), "rate": p.rate()}))
        meta = self.meta(partial)
        res = aggregate(ps, self.settings, meta, game_dir=self.snap if os.path.isdir(self.snap) else GAME)
        write_json(os.path.join(self.out, "result.json"), res)
        write_json(os.path.join(self.out, "head.json"), head_of(res))
        self.result_players = len(ps)
        self.say("sim: result.json written (%s%d of %d runs)" % ("partial: " if partial else "", len(ps), len(self.players)))
        return res

    def meta(self, partial):
        return {"id": os.path.basename(self.out), "job": self.job, "started": _now_iso(self.t0), "started_epoch": self.t0,
                "ended": "" if partial else _now_iso(), "wall_s": round(time.time() - self.t0, 1), "partial": bool(partial),
                "players_done": sum(1 for p in self.players if p.state in ("done", "failed")), "players_total": len(self.players),
                "map_rev": self.map_rev, "version": self.version, "sync": self.sync, "synthetic": bool(self.args.synthetic),
                "workers": self.settings["workers"], "wall_cap": self.wall_cap, "fps": self.settings["fps"]}

    def run(self):
        os.makedirs(os.path.join(self.out, "players"), exist_ok=True)
        write_json(os.path.join(self.out, "settings.json"), self.settings, indent=1)
        s = self.settings
        self.say("sim: %d run%s of %s to %s, %d at once, Upgrade board %s, on death: %s, seed %d, map %s, %d fps -> %s" % (
            s["players"], "" if s["players"] == 1 else "s", s["hero"], fmt_t(s["limit"]), s["workers"], board_text(s.get("talents"), s.get("board_label")),
            death_label(s["death"]), s["seed"], s["map"], s["fps"], self.out))
        if not self.args.synthetic:
            why = caps_problem(s, self.caps)
            if why:
                raise RuntimeError(why)
        self.progress(force=True)
        if not self.args.synthetic:
            if not self.take_lock():
                raise RuntimeError("the sim lock could not be taken")
        try:
            if not self.args.synthetic:
                self.do_sync()
            else:
                self.map_rev = map_rev(GAME, s["map"])
                self.version = project_version(GAME)
                self.sync = {"skipped": True, "synthetic": True}
            self.run_players()
            res = self.write_result(partial=False)
            ok = res["summary"]["ok"]
            self.state = "done" if ok else "failed"
            self.message = "" if ok else "every run failed"
            self.progress(force=True)
            if not self.args.synthetic:
                # the speed of a sim in the runner's usual mode (a --no-fast comparison is never the ETA's)
                ran_fast = bool(self.caps.get("fast")) and bool(s.get("fast", True))
                sp = record_speed(res["players"], s["workers"], s["fps"], fast=ran_fast, limit=s["limit"]) if (ran_fast or not self.caps.get("fast")) else None
                if sp:
                    self.say("sim: speed: %.2f s of play a second per run, %d at once (boot %.0f s)" % (sp["play_per_wall"], s["workers"], sp["boot_s"]))
            prune_history(self.args.keep, log=self.say, protect=(os.path.basename(self.out),))
            if not ok:
                first = next((p.problem for p in self.players if p.problem), "")
                self.say("sim: error: every run failed%s" % ((": " + first) if first else ""))
                return 1
            self.say("sim: done: %d of %d runs in %s -> %s" % (ok, len(self.players), fmt_t(time.time() - self.t0), os.path.join(self.out, "result.json")))
            return 0
        finally:
            for p in self.players:
                if p.state == "running" and p.proc is not None and p.proc.poll() is None:
                    kill_tree(p.proc.pid)
            if not self.args.synthetic:
                lock_release()

    def stop(self, why):
        """Ctrl+C: the running players killed, what finished kept as a partial result."""
        for p in self.players:
            if p.state == "running" and p.proc is not None:
                kill_tree(p.proc.pid)
                p.state, p.problem, p.ended = "failed", why, time.time()
        self.state = "cancelled"
        self.message = why
        try:
            self.write_result(partial=True)
        except Exception as e:  # never hide the stop behind an aggregation error
            self.say("sim: the partial result could not be written: %s" % e)
        self.progress(force=True)


def reaggregate(folder, log=print):
    """--aggregate <dir>: the players' files in <dir>/players/ into result.json again (the settings from settings.json)."""
    folder = os.path.abspath(folder)
    settings = read_json(os.path.join(folder, "settings.json")) or {}
    old = read_json(os.path.join(folder, "result.json")) or {}
    s, _ = clean_settings(settings, legacy=True)   # an older sim's death policy ("gold") stays what it played
    ps = []
    pdir = os.path.join(folder, "players")
    for k in range(1, s["players"] + 1):
        path = os.path.join(pdir, "p%02d.json" % k)
        data, problem = load_player(path)
        if data is None and not os.path.isfile(path):
            continue
        ps.append((k, data, {"seed": s["seed"] + k - 1, "problem": problem}))
    meta = dict(old.get("meta") or {})
    meta.update({"id": os.path.basename(folder), "reaggregated": _now_iso()})
    res = aggregate(ps, s, meta, game_dir=snap_game() if os.path.isdir(snap_game()) else GAME)
    write_json(os.path.join(folder, "result.json"), res)
    write_json(os.path.join(folder, "head.json"), head_of(res))
    log("sim: result.json written again from %d players" % len(ps))
    return res


def main(argv=None):
    ap = argparse.ArgumentParser(description="88fits run sim: N headless runs of the game, averaged per second of play")
    ap.add_argument("--out", help="the sim's folder (result.json, progress.json, players/)")
    ap.add_argument("--hero", default=DEFAULTS["hero"])
    ap.add_argument("--players", type=int, default=DEFAULTS["players"])
    ap.add_argument("--workers", type=int, default=DEFAULTS["workers"], help="runs at once (0 = auto: as many as the runs, at most cores - 2)")
    ap.add_argument("--limit", type=int, default=DEFAULTS["limit"], help="play seconds each run stops at (1500 = 25:00)")
    ap.add_argument("--board", type=float, default=DEFAULTS["board"], help="the Upgrade board preset: 0 none, 1.5 a quarter, 3 half, 6 full")
    ap.add_argument("--talents", default=None, help="the board talent by talent: grit:AAB,drive:A,... (A/B = each rank's form); wins over --board")
    ap.add_argument("--board-label", default="", help="the board's name in the header (\"my save\")")
    ap.add_argument("--death", default=DEFAULTS["death"], choices=[k for k, _, _ in DEATHS])
    ap.add_argument("--no-fast", action="store_true", help="play without the runner's sim mode (every visual drawn), to compare")
    ap.add_argument("--seed", type=int, default=DEFAULTS["seed"])
    ap.add_argument("--map", default=DEFAULTS["map"])
    ap.add_argument("--fps", type=int, default=DEFAULTS["fps"])
    ap.add_argument("--note", default="")
    ap.add_argument("--job", default="", help="the Level Editor job that runs this (its id)")
    ap.add_argument("--wall-cap", type=int, default=0, help="seconds one run may take before it is stopped (default max(900, 2 x limit))")
    ap.add_argument("--keep", type=int, default=HISTORY_KEEP, help="the newest sims kept in tools/dl/sim/runs (kept ones never count)")
    ap.add_argument("--snap", default="", help="another snapshot folder (tests)")
    ap.add_argument("--sim-dir", default="", help="the sims' folder (default tools/dl/sim: runs/, snap/, speed.json); a test's own")
    ap.add_argument("--no-sync", action="store_true", help="play the snapshot as it is")
    ap.add_argument("--synthetic", action="store_true", help="made-up players, no Godot (the page's and the selftest's fixture)")
    ap.add_argument("--synthetic-speed", type=float, default=0.0, help="--synthetic: play seconds a wall second (0 = at once)")
    ap.add_argument("--aggregate", default="", help="aggregate an existing sim folder's players again")
    args = ap.parse_args(argv)
    global SIM_DIR
    if args.sim_dir:
        SIM_DIR = os.path.abspath(args.sim_dir)
    if args.aggregate:
        reaggregate(args.aggregate)
        return 0
    if not args.out:
        ap.error("--out is needed")
    if not args.synthetic and not os.path.isfile(GODOT):
        print("sim: error: the Godot binary is not at %s" % GODOT, flush=True)
        return 2
    b = Batch(args)
    try:
        return b.run()
    except KeyboardInterrupt:
        b.say("sim: stopped (Ctrl+C): the runs that finished are kept as a partial result")
        b.stop("stopped by Ctrl+C")
        return 130
    except Exception as e:
        b.state, b.message = "failed", "%s: %s" % (type(e).__name__, e)
        b.progress(force=True)
        print("sim: error: %s: %s" % (type(e).__name__, e), flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""The Watch's launcher (pass 80, lane WATCH; the design Garry approved: REQUEST.md in tools/dl/p80): one bot-played run of
the real game in a PC window, the phone's view on the left and a panel of numbers, charts and the bot's decisions on the
right (game/tools/watch/). It starts Godot windowed and returns.

    python tools/watch.py                                   # the Drifter, a quarter board, a random seed, the default bot
    python tools/watch.py --hero calavera --board half --seed 7 --speed 4 --bot skill=0.6 --bot style=greedy
    python tools/watch.py --talents grit:AAB,drive:A --limit 5:00 --ref auto
    python tools/watch.py --wait --timeout 900 --autoquit --limit 300 --speed 4      # a check: waits, prints the end

What it does, in order:
 1. The Watch lock tools/dl/locks/watch.lock (one Watch at a time; a dead owner's lock is reclaimed). NOT the godot lock:
    the Watch plays on its own snapshot of game/ with its own user folder (%APPDATA%/Godot/app_userdata/88fits_watch),
    so it never touches the PC save, never blocks the tests or the Level Editor's imports, and never blocks the Sim.
 2. The snapshot tools/dl/watch/snap/game, refreshed from game/ by tools/sim_batch.py's own code (sync_snapshot: what
    changed is copied, an import runs when an imported asset changed, import_json for every content JSON newer than its
    .tres), its project.godot pointed at the user folder 88fits_watch.
 3. Godot --fixed-fps 60 --path <snapshot> --script res://tools/watch/watch_main.gd -- <the run's arguments>, its log in
    tools/dl/watch/logs/; the lock's owner.json names Godot's pid (the window lets go of the lock when it closes).
The board: --board none|quarter|half|full|save|<ranks a talent> (save = the PC save's Upgrade board), or --talents
grit:AAB,drive:A,... talent by talent (A the first form, B the second). --ref auto finds the newest Sim result
(tools/dl/sim/runs/) of the same hero and board for the charts' grey line. The arguments: tools/dl/p80/keys_WATCH.md.
Pass 85: the window opens with the Hero Settings pop-up, filled with these options (Start Run starts the run down the
spawn beam; the header's "Restart run" opens it again); --go (or --autoquit) starts at once as before. The sound is off
unless --sound. watch.py writes tools/dl/watch/setup.json for the pop-up (the board presets, the PC save's board, the Sim
results for the grey line: write_setup).
Standard library only (the Level Editor's Sim tab starts it: sim_io.py POST /api/sim/watch).
"""
import argparse
import json
import os
import random
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import locks  # noqa: E402
import sim_batch as SB  # noqa: E402  (the snapshot code, the board's presets, the sims' history)

GAME = os.path.join(ROOT, "game")
WATCH_DIR = os.path.join(ROOT, "tools", "dl", "watch")
USER_DIR_NAME = "88fits_watch"
LOCK = os.path.join(locks.LOCK_DIR, "watch.lock")
SCRIPT = "res://tools/watch/watch_main.gd"
PRESETS = dict(SB.PRESETS)   # none, quarter, half, full -> ranks a talent


def snap_game():
    return os.path.join(WATCH_DIR, "snap", "game")


def say(msg):
    print("watch: " + msg, flush=True)


# ---------------------------------------------------------------- the lock (one Watch at a time)

def lock_status():
    """None when free; else {pid, who, since, alive, owner_file}."""
    if not os.path.isdir(LOCK):
        return None
    d = SB.read_json(os.path.join(LOCK, "owner.json"), tries=3)
    if not isinstance(d, dict):
        return {"owner_file": False, "pid": 0, "alive": None, "who": "unknown"}
    d["owner_file"] = True
    d["alive"] = locks.pid_alive(d.get("pid"))
    return d


def lock_release():
    try:
        if os.path.isfile(os.path.join(LOCK, "owner.json")):
            os.remove(os.path.join(LOCK, "owner.json"))
        os.rmdir(LOCK)
    except OSError:
        pass
    return not os.path.isdir(LOCK)


def lock_take(note=""):
    """Takes the lock for this launcher (the owner becomes Godot once it runs). (True, None) or (False, status)."""
    os.makedirs(locks.LOCK_DIR, exist_ok=True)
    for _ in range(2):
        try:
            os.mkdir(LOCK)
        except FileExistsError:
            st = lock_status()
            if st is not None and (st.get("alive") is False or (not st.get("owner_file") and time.time() - os.path.getmtime(LOCK) > 30)):
                say("the Watch lock was held by pid %s, which is gone: reclaimed" % st.get("pid"))
                lock_release()
                continue
            return False, st
        lock_owner(os.getpid(), note)
        return True, None
    return False, lock_status()


def lock_owner(pid, note=""):
    SB.write_json(os.path.join(LOCK, "owner.json"), {"pid": int(pid), "who": "watch", "job": "", "note": note, "since": time.time(),
                                                      "beat": time.time(), "host": os.environ.get("COMPUTERNAME", "")})


# ---------------------------------------------------------------- the run's settings

def parse_limit(v):
    """Seconds of play from "300", "5:00" or "1:02:00"; 0 = none."""
    v = str(v or "0").strip()
    if ":" in v:
        s = 0
        for part in v.split(":"):
            s = s * 60 + int(part or 0)
        return s
    return int(float(v))


def board_of(args):
    """(talents {id: letters}, label, problems) from --talents or --board."""
    if args.talents:
        t, probs = SB.clean_talents(args.talents)
        pre = SB.preset_of(t)   # the Sim tab passes a preset talent by talent: name it
        return t, (SB.board_label(PRESETS[pre]) if pre else "custom"), probs
    b = str(args.board or "quarter").strip().lower()
    if b == "save":
        t, note = SB.save_board()
        if t is None:
            return {}, "my save (not found)", [note]
        return t, "my save", []
    if b in PRESETS:
        return SB.board_talents(PRESETS[b]), SB.board_label(PRESETS[b]), []
    try:
        m = float(b)
    except ValueError:
        return SB.board_talents(1.5), "a quarter", ["--board %r is none, quarter, half, full, save or a number: a quarter plays" % args.board]
    return SB.board_talents(m), SB.board_label(m), []


def sim_talents(settings):
    """A Sim's board as {id: letters} (its talents, else its preset)."""
    t = settings.get("talents")
    if isinstance(t, dict) and t:
        c, _ = SB.clean_talents(t)
        return c
    try:
        return SB.board_talents(float(settings.get("board", 0) or 0))
    except (TypeError, ValueError):
        return {}


def find_ref(hero, talents, map_id):
    """The newest Sim result of the same hero, board and map (tools/dl/sim/runs/*/result.json): (path, label) or (None, why)."""
    for r in SB.list_sims():
        res = os.path.join(r["path"], "result.json")
        if not os.path.isfile(res) or r.get("running"):
            continue
        head = SB.read_json(os.path.join(r["path"], "head.json"), tries=2)
        s = (head or {}).get("settings") if isinstance(head, dict) else None
        if not isinstance(s, dict):
            whole = SB.read_json(res, tries=2) or {}
            s = whole.get("settings") or {}
        if str(s.get("hero")) != hero or str(s.get("map", "red_canyon")) != map_id:
            continue
        if sim_talents(s) != (talents or {}):
            continue
        return res, r["id"]
    return None, "no Sim result of %s with this board yet" % hero


def build_args(a, talents, label, ref, ref_label, lock_path, setup=None):
    """The Watch's command line after "--" (Watch.gd reads them). Pass 85: the sound is off unless --sound (--mute still
    means off); the Hero Settings pop-up opens first unless --go (or --autoquit, a check that closes itself); `setup` is
    the pop-up's file (write_setup)."""
    sound = bool(getattr(a, "sound", False)) and not bool(getattr(a, "mute", False))
    out = ["hero=" + a.hero, "seed=%d" % a.seed, "map=" + a.map, "talents=" + SB.talents_arg(talents),
           "board_label=" + SB.board_text(talents, label), "limit=%d" % parse_limit(a.limit), "speed=%g" % float(a.speed),
           "death=" + a.death, "unlocks=" + a.unlocks, "repo=" + ROOT.replace("\\", "/"), "lock=" + lock_path.replace("\\", "/"),
           "sound=%d" % (1 if sound else 0), "numbers=%d" % (0 if a.no_numbers else 1), "log_speed=%g" % float(a.log_speed)]
    if bool(getattr(a, "go", False)) or bool(getattr(a, "autoquit", False)):
        out.append("go=1")
    if bool(getattr(a, "seed_random", False)):
        out.append("seed_random=1")
    if setup:
        out.append("setup=" + os.path.abspath(setup).replace("\\", "/"))
    if a.paused:
        out.append("paused=1")
    if ref:
        out += ["ref=" + ref.replace("\\", "/"), "ref_label=" + ref_label]
    if a.stub:
        out.append("bot=stub")
    if a.bot_preset:
        out.append("bot.preset=" + a.bot_preset)
    for kv in a.bot or []:
        if "=" not in kv:
            raise SystemExit("watch: --bot takes key=value (got %r)" % kv)
        k, v = kv.split("=", 1)
        out.append("bot.%s=%s" % (k.strip(), v.strip()))
    if a.autoquit:
        out.append("autoquit=1")
    if a.profile:
        out.append("profile=1")
    if a.actions:
        out.append("actions=" + a.actions)
    if str(a.skip_draw) == "0":
        out.append("skip_draw=0")
    if a.wall:
        out.append("wall=%d" % int(a.wall))
    if a.shots:
        out += ["shots=" + os.path.abspath(a.shots).replace("\\", "/"), "shots_at=" + (a.shots_at or "")]
    if a.size:
        w, h = a.size.lower().split("x")
        out += ["w=%d" % int(w), "h=%d" % int(h)]
    return out


# ---------------------------------------------------------------- the Hero Settings pop-up's file (pass 85)

def ref_entries():
    """The finished Sim results the pop-up may draw as the charts' grey line, newest first: [{hero, map, talents, path,
    label}] (talents as the runner's text, "grit:AAB,..." or "none"); the pop-up takes the first of the run's hero, board
    and map (find_ref's rule)."""
    out = []
    for r in SB.list_sims():
        res = os.path.join(r["path"], "result.json")
        if not os.path.isfile(res) or r.get("running"):
            continue
        head = SB.read_json(os.path.join(r["path"], "head.json"), tries=2)
        s = (head or {}).get("settings") if isinstance(head, dict) else None
        if not isinstance(s, dict):
            whole = SB.read_json(res, tries=2) or {}
            s = whole.get("settings") or {}
        out.append({"hero": str(s.get("hero", "")), "map": str(s.get("map", "red_canyon")), "talents": SB.talents_arg(sim_talents(s)),
                    "path": res.replace("\\", "/"), "label": r["id"]})
    return out


def write_setup(path):
    """What the Watch's Hero Settings pop-up needs that only Python knows: the board presets talent by talent (none,
    quarter, half, full as the Sim's; save = the PC save's board, read only, or null with why in save_note) and the Sim
    results for the grey line. {presets: {name: {id: letters}}, labels: {name: words}, save_note, refs: ref_entries()}."""
    presets = {}
    labels = {}
    for name, m in SB.PRESETS:
        presets[name] = SB.board_talents(m)
        labels[name] = SB.board_label(m)
    t, note = SB.save_board()
    presets["save"] = t
    labels["save"] = "my save"
    try:
        refs = ref_entries()
    except Exception as e:  # a broken sim folder never stops the Watch
        refs = []
        note = (note + "; " if note else "") + "the Sim results: %s" % e
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    SB.write_json(path, {"presets": presets, "labels": labels, "save_note": note or "", "refs": refs})
    return path


# ---------------------------------------------------------------- the snapshot

def refresh_snapshot(no_sync=False):
    """game/ -> tools/dl/watch/snap/game with sim_batch's code (its user folder 88fits_watch); imports when needed."""
    SB.USER_DIR_NAME = USER_DIR_NAME   # patch_project names the snapshot's user folder from this
    snap = snap_game()
    if no_sync and os.path.isdir(os.path.join(snap, ".godot")):
        say("sync: skipped (--no-sync)")
        return snap
    r = SB.sync_snapshot(GAME, snap, log=say)
    say("sync: copied %d files (%.1f MB), removed %d, in %.1f s%s" % (r["copied"], r["bytes"] / 1048576.0, r["removed"], r["secs"],
                                                                   " (a new snapshot)" if r["fresh"] else ""))
    logs = os.path.join(WATCH_DIR, "logs")
    if r["import_reasons"]:
        why = r["import_reasons"][0] + ("" if len(r["import_reasons"]) == 1 else " and %d more" % (len(r["import_reasons"]) - 1))
        say("import: the snapshot imports again: %s" % why)
        rc, secs, tail = SB.run_godot(["--headless", "--path", snap, "--import"], os.path.join(logs, "snap_import.log"),
                                      timeout=3600 if r["fresh"] else 1800, log=say)
        say("import: done in %.1f s (exit %s)" % (secs, rc))
    stale = SB.stale_json(snap)
    if stale:
        say("import_json: %d content file%s newer than its .tres" % (len(stale), "" if len(stale) == 1 else "s"))
        rc, secs, tail = SB.run_godot(["--headless", "--path", snap, "--script", "res://tools/import_json.gd", "--", "only=" + ",".join(stale)],
                                      os.path.join(logs, "snap_import_json.log"), timeout=900, log=say)
        say("import_json: done in %.1f s (exit %s)" % (secs, rc))
    if not os.path.isfile(os.path.join(snap, "tools", "watch", "watch_main.gd")):
        raise SystemExit("watch: the snapshot has no tools/watch/watch_main.gd")
    return snap


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description="Watch one bot-played run of 88fits in a PC window (pass 80).")
    ap.add_argument("--hero", default="drifter")
    ap.add_argument("--board", default="quarter", help="none, quarter, half, full, save (the PC save's board) or ranks a talent")
    ap.add_argument("--talents", default="", help="the board talent by talent: grit:AAB,drive:A (wins over --board)")
    ap.add_argument("--seed", default="random", help="a number, or random")
    ap.add_argument("--map", default="red_canyon")
    ap.add_argument("--limit", default="0", help="end the run after this much play (300 or 5:00); 0 = until he falls")
    ap.add_argument("--speed", default="1", help="0.25, 0.5, 1, 2, 4 or 8 at the start")
    ap.add_argument("--paused", action="store_true", help="start paused")
    ap.add_argument("--death", default="end", help="Down! answered by the bot: end (the default), ad, keep (as the Sim)")
    ap.add_argument("--unlocks", default="all", choices=("all", "save"))
    ap.add_argument("--ref", default="auto", help="a Sim result.json for the charts' grey line, auto (the newest of this hero and board) or none")
    ap.add_argument("--bot", action="append", default=[], help="a bot option key=value (repeatable): skill=0.6, style=greedy, totems=off ...")
    ap.add_argument("--bot-preset", default="", help="the bot's preset (lane BOT's names: sim77, explorer, careless, expert)")
    ap.add_argument("--stub", action="store_true", help="the Watch's stand-in bot instead of tools/bot/Bot.gd")
    ap.add_argument("--sound", action="store_true", help="start with the sound on (pass 85: off by default)")
    ap.add_argument("--mute", action="store_true", help="start with the sound off (the default since pass 85)")
    ap.add_argument("--go", action="store_true", help="start the run at once, no Hero Settings pop-up first (--autoquit implies it)")
    ap.add_argument("--no-numbers", action="store_true", help="no floating damage numbers")
    ap.add_argument("--size", default="", help="the window, WxH (default 1920x1080, fitted to the screen)")
    ap.add_argument("--no-sync", action="store_true", help="play the snapshot as it is")
    ap.add_argument("--wait", action="store_true", help="wait for the window to close; the exit code is Godot's")
    ap.add_argument("--timeout", type=float, default=0, help="with --wait: kill it after this many seconds")
    ap.add_argument("--autoquit", action="store_true", help="close the window when the run ends")
    ap.add_argument("--wall", type=float, default=0, help="end the run after this many wall seconds (checks)")
    ap.add_argument("--shots", default="", help="a folder for window captures at --shots-at play seconds and at the end")
    ap.add_argument("--shots-at", default="", help="play seconds, comma-separated")
    ap.add_argument("--log-speed", default="30", help="the log's speed line every this many wall seconds")
    ap.add_argument("--profile", action="store_true", help="the log's speed line also says what a frame costs (drawn and not)")
    ap.add_argument("--actions", default="", help="checks: <p|w><seconds>:<pause|go|step|level|speed=x|shot=name|end|say>,...")
    ap.add_argument("--skip-draw", default="1", help="1 (default): above 1x the frames not drawn skip the drawing work; 0 keeps it")
    ap.add_argument("--log", default="", help="Godot's log file (default tools/dl/watch/logs/watch_<time>.log)")
    a = ap.parse_args(argv)
    a.seed_random = str(a.seed).lower() in ("random", "", "0")
    a.seed = random.randint(1, 99999) if a.seed_random else int(a.seed)
    talents, label, probs = board_of(a)
    for p in probs:
        say("board: " + p)
    if not os.path.isfile(locks.GODOT):
        raise SystemExit("watch: no Godot binary at %s" % locks.GODOT)
    ok, st = lock_take("%s seed %d" % (a.hero, a.seed))
    if not ok:
        say("a Watch is open already (pid %s): close its window first (one Watch at a time)" % (st or {}).get("pid"))
        return 3
    proc = None
    try:
        ref, ref_label = None, ""
        if str(a.ref).lower() == "auto":
            ref, why = find_ref(a.hero, talents, a.map)
            if ref:
                ref_label = why
                say("ref: %s" % os.path.relpath(ref, ROOT))
            else:
                say("ref: %s (no grey line)" % why)
        elif str(a.ref).lower() not in ("", "none"):
            ref = os.path.abspath(a.ref)
            ref_label = os.path.basename(os.path.dirname(ref))
        snap = refresh_snapshot(a.no_sync)
        logs = os.path.join(WATCH_DIR, "logs")
        os.makedirs(logs, exist_ok=True)
        log = os.path.abspath(a.log) if a.log else os.path.join(logs, "watch_%s.log" % time.strftime("%Y%m%d-%H%M%S"))
        setup = None
        try:
            setup = write_setup(os.path.join(WATCH_DIR, "setup.json"))
        except Exception as e:  # the pop-up then offers the command line's board and no presets
            say("setup: %s" % e)
        cmd = [locks.GODOT, "--fixed-fps", "60", "--path", snap, "--log-file", log, "--script", SCRIPT, "--"] + \
            build_args(a, talents, label, ref, ref_label, LOCK, setup)
        flags = 0
        if os.name == "nt" and not a.wait:
            flags = subprocess.CREATE_NEW_PROCESS_GROUP | getattr(subprocess, "DETACHED_PROCESS", 0x8)
        proc = subprocess.Popen(cmd, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                creationflags=flags, close_fds=True)
        lock_owner(proc.pid, "%s seed %d" % (a.hero, a.seed))
        say("started: %s, %s board (%s), seed %d, pid %d; log %s" % (a.hero, label, SB.talents_arg(talents), a.seed, proc.pid,
                                                                     os.path.relpath(log, ROOT)))
        if not a.wait:
            return 0
        try:
            rc = proc.wait(timeout=a.timeout if a.timeout > 0 else None)
        except subprocess.TimeoutExpired:
            say("timeout: %d s passed, the Watch is stopped" % int(a.timeout))
            SB.kill_tree(proc.pid)
            rc = -9
        try:
            with open(log, "r", encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
            for ln in lines:
                if ln.startswith("watch:") or "SCRIPT ERROR" in ln or "ERROR:" in ln:
                    print(ln)
        except OSError:
            pass
        say("exit %s" % rc)
        return rc
    finally:
        # a run that never started, or one that is over: the lock goes (a window still open keeps it)
        st = lock_status()
        if st is not None and st.get("pid") in (os.getpid(), getattr(proc, "pid", -1)) and (proc is None or proc.poll() is not None):
            lock_release()


if __name__ == "__main__":
    sys.exit(main())

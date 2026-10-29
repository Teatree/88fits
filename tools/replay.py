#!/usr/bin/env python3
"""Pass 114 (lane REPLAY): watch a recorded run again (analytics/howto/04_replays.md).

    python tools/replay.py --latest                 # the newest recording on this PC (downloaded or local)
    python tools/replay.py --latest --player "Lanky Tinker"
    python tools/replay.py <file>                   # one recording (a *_replay.json)
    python tools/replay.py --list [--player NAME]   # every recording: when, who, hero, stage, result, its build, kept?
    options: --speed 0.25|0.5|1|2|4|8  --paused  --seek 5:00  --sound  --w 1600 --h 900
             --nearest (play on the nearest build without asking when the right one is gone)  --dry-run
             --shots <dir> --demo --quit-after <s>  (the scripted capture tour)

Every recording names the build that recorded it. A replay is exact only on that build, so ship.sh keeps every PC build
in builds/<build id>/ (tools/builds.py) and this picks it:
- the build is kept: builds/<id>/88fits.exe opens the replay viewer (`--fixed-fps 64 -- replay=<file>`);
- a run from the editor binary ("editor-<version>"): the repo as it is now, on the Watch's snapshot of game/ (its own
  user folder, the Watch's lock; it says so: if the code changed since, the replay may part);
- the build is gone: it says so in plain words and offers the nearest kept build (--nearest takes it without asking);
  the viewer's header then says in red that the builds differ.
The PC's own save is never touched (the viewer plays on a sandboxed copy of the save the run started with).
Recordings are looked for in analytics/remote/<player>/replays/ (tools/posthog_runs.py downloads them), analytics/runs/
replays/ (runs from the editor binary) and the PC's user folder (runs played in the PC exe). Standard library only.
"""
import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import builds as B  # noqa: E402
import locks  # noqa: E402

LOG_DIR = os.path.join(ROOT, "tools", "dl", "replay", "logs")


def say(msg):
    print("replay: " + msg, flush=True)


def describe(h):
    b = h.get("build") or {}
    res = {"death": "died", "extract": "extracted", "abandon": "quit", "end": "ended"}.get(str(h.get("result", "")), str(h.get("result", "")))
    secs = float(h.get("play_s") or 0.0)
    return "%s | %s | %s stage %s | %s at %d:%02d | level %s | build %s" % (
        h.get("recorded", "?"), h.get("player") or "?", h.get("hero", "?"), h.get("stage", "?"), res, int(secs) // 60, int(secs) % 60,
        h.get("level", "?"), b.get("id", "?"))


def pick_latest(player=""):
    for p, h in B.recordings():
        if player and str(h.get("player", "")).lower() != player.lower():
            continue
        return p, h
    return None, None


def cmd_list(a):
    kept = {b["id"] for b in B.builds()}
    n = 0
    for p, h in B.recordings():
        if a.player and str(h.get("player", "")).lower() != a.player.lower():
            continue
        bid = str((h.get("build") or {}).get("id", ""))
        mark = "build kept" if bid in kept else ("editor run" if bid.startswith("editor-") else "BUILD MISSING")
        print("%s  [%s]\n    %s" % (describe(h), mark, p))
        n += 1
    if n == 0:
        say("no recordings found (looked in: %s)" % ", ".join(B.recording_dirs()) if B.recording_dirs() else
            "no recordings found: play a run (play data on), then `python tools/posthog_runs.py` for the phone's")
    return 0


def viewer_args(a, path):
    v = ["replay=" + path.replace("\\", "/"), "speed=" + str(a.speed), "w=%d" % a.w, "h=%d" % a.h]
    if a.paused:
        v.append("paused=1")
    if a.seek:
        v.append("seek=" + a.seek)
    if a.sound:
        v.append("sound=1")
    if a.shots:
        v.append("shots=" + os.path.abspath(a.shots).replace("\\", "/"))
    if a.demo:
        v.append("demo=1")
        if a.demo_seek:
            v.append("demo_seek=" + str(a.demo_seek))
    if a.quit_after:
        v.append("quit_after=%g" % a.quit_after)
    return v


def run_exe(exe, a, path, wait):
    cmd = [exe, "--fixed-fps", "64", "--resolution", "%dx%d" % (a.w, a.h), "--"] + viewer_args(a, path)
    say("starting: " + " ".join('"%s"' % c if " " in c else c for c in cmd))
    if a.dry_run:
        return 0
    os.makedirs(LOG_DIR, exist_ok=True)
    log = open(os.path.join(LOG_DIR, time.strftime("%Y%m%d_%H%M%S") + ".log"), "w", encoding="utf-8")
    p = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=os.path.dirname(exe))
    if wait:
        return p.wait()
    return 0


def run_editor(a, path, wait):
    """A run recorded from the editor binary: the Watch's snapshot of game/ (its own user folder) under the Watch lock."""
    import watch as W  # the snapshot and the lock (tools/watch.py)
    if a.dry_run:
        cmd = [locks.GODOT, "--fixed-fps", "64", "--resolution", "%dx%d" % (a.w, a.h), "--path", W.snap_game(), "--"] + viewer_args(a, path)
        say("would refresh the Watch's snapshot of game/ and start: " + " ".join(cmd))
        return 0
    ok, st = W.lock_take("replay")
    if not ok:
        say("the Watch is open (pid %s): close it first (one game window on the repo's snapshot at a time)" % (st or {}).get("pid"))
        return 2
    try:
        snap = W.refresh_snapshot(no_sync=a.no_sync)
        cmd = [locks.GODOT, "--fixed-fps", "64", "--resolution", "%dx%d" % (a.w, a.h), "--path", snap, "--"] + viewer_args(a, path)
        say("starting on the repo's snapshot: " + " ".join(cmd))
        if a.dry_run:
            return 0
        os.makedirs(LOG_DIR, exist_ok=True)
        log = open(os.path.join(LOG_DIR, time.strftime("%Y%m%d_%H%M%S") + "_editor.log"), "w", encoding="utf-8")
        p = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
        W.lock_owner(p.pid, "replay")
        if wait:
            return p.wait()
        return 0
    finally:
        if wait or a.dry_run:
            W.lock_release()


def main(argv=None):
    ap = argparse.ArgumentParser(description="Watch a recorded run again (pass 114).")
    ap.add_argument("file", nargs="?", default="")
    ap.add_argument("--latest", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--player", default="")
    ap.add_argument("--speed", default="1")
    ap.add_argument("--paused", action="store_true")
    ap.add_argument("--seek", default="")
    ap.add_argument("--sound", action="store_true")
    ap.add_argument("--w", type=int, default=1600)
    ap.add_argument("--h", type=int, default=900)
    ap.add_argument("--nearest", action="store_true", help="play on the nearest kept build without asking")
    ap.add_argument("--wait", action="store_true", help="wait for the window to close")
    ap.add_argument("--no-sync", action="store_true", help="(editor runs) do not refresh the snapshot")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--shots", default="")
    ap.add_argument("--demo", action="store_true")
    ap.add_argument("--demo-seek", default="")
    ap.add_argument("--quit-after", type=float, default=0.0)
    a = ap.parse_args(argv)
    if a.list:
        return cmd_list(a)
    if a.file:
        path = os.path.abspath(a.file)
        h = B.read_header(path)
        if not h:
            say("%s is not a replay file" % path)
            return 1
    else:
        path, h = pick_latest(a.player)
        if not path:
            say("no recordings found%s. On the phone: play a run with play data on, then run `python tools/posthog_runs.py`." %
                (" for %s" % a.player if a.player else ""))
            return 1
    say("the run: " + describe(h))
    say("the file: " + path)
    bid = str((h.get("build") or {}).get("id", ""))
    if bid.startswith("editor-") or bid.startswith("dev-"):
        say("recorded from the editor binary, not a shipped build: it replays on the repo AS IT IS NOW (if the code or "
            "the content changed since the run, the replay may go out of step; the viewer's light says so)")
        return run_editor(a, path, a.wait)
    b, exact = B.find(bid)
    if b is not None and exact and b["exe"]:
        say("playing on the build that recorded it: %s (%s)" % (bid, b["exe"]))
        return run_exe(b["exe"], a, path, a.wait)
    if b is None:
        say("the build that recorded this run (%s) is not kept on this PC, and no other build is (builds/ is empty). "
            "Ship a build first (bash tools/ship.sh keeps it), or replay a newer run." % bid)
        return 2
    say("the build that recorded this run (%s) is NOT kept on this PC. The nearest kept build is %s." % (bid, b["id"]))
    say("on another build the replay may go out of step (the viewer's header and light say so).")
    if not a.nearest:
        if not sys.stdin.isatty():
            say("run again with --nearest to play it on %s anyway" % b["id"])
            return 2
        ans = input("Play it on %s anyway? [y/N] " % b["id"]).strip().lower()
        if ans not in ("y", "yes"):
            return 2
    return run_exe(b["exe"], a, path, a.wait)


if __name__ == "__main__":
    sys.exit(main())

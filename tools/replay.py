#!/usr/bin/env python3
"""Pass 114 (lane REPLAY): watch a recorded run again (analytics/howto/04_replays.md).

    python tools/replay.py --latest                 # the newest recording on this PC (downloaded or local)
    python tools/replay.py --latest --player "Lanky Tinker"
    python tools/replay.py <file>                   # one recording (a *_replay.json)
    python tools/replay.py --list [--player NAME]   # every recording: when, who, hero, stage, result, its build, kept?
    python tools/replay.py --board [<file> | --latest]   # pass 115: only print the Upgrade board the run began with
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


# ---------------------------------------------------------------- pass 115 (lane DASH; Garry: "I need to know Player
# Mirror Upgrades while watching the replay"): the Upgrade board the recording's save began with, in the terminal (any
# recording, any build: the viewer of a build from 0.98 on shows it in its window too)

def _talent_defs():
    """The board's talents from game/content/talents (the repo as it is now), in the board's order (TalentDef.board_before:
    the cheaper first rank first, then `order`, then the id)."""
    out = []
    base = os.path.join(ROOT, "game", "content", "talents")
    for tid in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        f = os.path.join(base, tid, tid + ".json")
        try:
            with open(f, encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        cost = [int(x) for x in d.get("cost") or []]
        forms = [str((x or {}).get("name", "")) for x in (d.get("forms") or [])][:2]
        out.append({"id": str(d.get("id", tid)), "name": str(d.get("name", tid)), "ranks": int(d.get("ranks", 3)), "cost": cost,
                    "order": int(d.get("order", 0)), "forms": forms + [""] * (2 - len(forms))})
    out.sort(key=lambda t: (t["cost"][0] if t["cost"] else 0, t["order"], t["id"]))
    return out


def _picks(t):
    """A save's talent entry as its ranks' forms (Save.talent_picks): picks, else an old {form, rank}."""
    if not isinstance(t, dict):
        return []
    if isinstance(t.get("picks"), list):
        return [min(1, max(0, int(f))) for f in t["picks"]]
    return [min(1, max(0, int(t.get("form", 0))))] * int(t.get("rank", 0) or 0)


def board_lines(path):
    """The Upgrade board the recorded run began with, as lines of plain text (A = a rank of its first form, B its second,
    - not bought); [] when the recording has no save."""
    try:
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
    except (OSError, ValueError):
        return []
    sv = rec.get("save") if isinstance(rec, dict) else None
    if not isinstance(sv, dict) or not isinstance(sv.get("talents"), dict):
        return ["the Upgrade board: not in this recording"]
    tal = sv["talents"]
    rows, ranks, most, gold = [], 0, 0, 0
    for t in _talent_defs():
        pk = _picks(tal.get(t["id"]))
        g = sum(t["cost"][k] for k in range(len(pk)) if k < len(t["cost"]))
        ranks += len(pk)
        most += t["ranks"]
        gold += g
        n0 = pk.count(0)
        words = ", ".join(w for w in ("%s x%d" % (t["forms"][0], n0) if n0 else "", "%s x%d" % (t["forms"][1], len(pk) - n0) if len(pk) - n0 else "") if w)
        marks = "".join("AB"[f] for f in pk) + "-" * max(0, t["ranks"] - len(pk))
        rows.append("    %-10s %d/%d  %s  %s" % (t["name"], len(pk), t["ranks"], marks, words or "no rank"))
    spent = sv.get("talent_spent")
    head = "the Upgrade board the run began with: %d of %d ranks, %s gold at today's prices%s" % (
        ranks, most, "{:,}".format(gold), ("; the save says %s was paid" % "{:,}".format(int(spent))) if spent is not None and int(spent) != gold else "")
    look = str(rec.get("look") or "")
    return [head] + rows + (["the hero's look: " + look] if look else [])


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


## Builds stamped before this one draw the phone's camera-cutout band (CutoutBand) across the top of the whole replay
## window, over the header that names the builds; the viewer hides it from the next build on. For those builds the
## recording is handed over as a copy without the cutout (the phone view's HUD then starts at the top) - pass 114, lead.
BAND_HIDDEN_FROM = "20261029-1930"


def _stamp_of(exe):
    parts = os.path.basename(os.path.dirname(exe)).split("-")
    return "-".join(parts[1:3]) if len(parts) >= 3 else ""


def without_cutout(exe, path):
    if _stamp_of(exe) >= BAND_HIDDEN_FROM:
        return path
    try:
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
    except (OSError, ValueError):
        return path
    if float(rec.get("safe_top") or 0.0) <= 0.0:
        return path
    rec["safe_top"] = 0.0
    os.makedirs(LOG_DIR, exist_ok=True)
    out = os.path.join(LOG_DIR, "no_cutout_" + os.path.basename(path))
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(rec, f)
    say("this build draws the phone's camera-cutout band over the header: playing a copy without the cutout")
    return out


def run_exe(exe, a, path, wait):
    path = without_cutout(exe, path)
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
    ap.add_argument("--menu", action="store_true", help="the menu replay.cmd opens: download, list, replay")
    ap.add_argument("--board", action="store_true", help="only print the Upgrade board the run began with (pass 115)")
    a = ap.parse_args(argv)
    if a.menu:
        return menu(a)
    if a.list:
        return cmd_list(a)
    if a.board:
        path = os.path.abspath(a.file) if a.file else pick_latest(a.player)[0]
        if not path:
            say("no recordings found")
            return 1
        say("the file: " + path)
        for ln in board_lines(path):
            say(ln)
        return 0
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
    return play(a, path, h)


def play(a, path, h):
    say("the run: " + describe(h))
    say("the file: " + path)
    # pass 115 (lane DASH): the Upgrade board it began with (the viewer of a build from 0.98 on shows it too: B folds it)
    for ln in board_lines(path):
        say(ln)
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


# ---------------------------------------------------------------- the menu (replay.cmd; Garry: "why would I want this to
# be a separate tool? Just make it so that when I run the cmd, it asks me and gives me options")

def _numbered(a, limit=20):
    """The recordings newest first, numbered from 1 (at most `limit` shown); the list of (path, header)."""
    kept = {b["id"] for b in B.builds()}
    recs = [(p, h) for p, h in B.recordings() if not a.player or str(h.get("player", "")).lower() == a.player.lower()]
    if not recs:
        print("\n  No recordings yet. Choose 1 to download the phone's runs (play a run on the phone first, play data on).")
        return recs
    print()
    for i, (p, h) in enumerate(recs[:limit]):
        bid = str((h.get("build") or {}).get("id", ""))
        mark = "" if bid in kept or bid.startswith("editor-") else "  (its build is not on this PC)"
        print("  %2d) %s%s" % (i + 1, describe(h), mark))
    if len(recs) > limit:
        print("      ... and %d older (python tools/replay.py --list shows all)" % (len(recs) - limit))
    return recs


def _download():
    import posthog_runs as PR
    print()
    try:
        # only what concerns the replays (the run records' own lines are posthog_runs.py's; runs from before 0.97 have none)
        def log(m):
            m = str(m)
            if "replay" in m or "budget" in m or "not complete" in m or "failed" in m.lower():
                print("  " + m.replace("run_replay parts", "replay parts in PostHog"), flush=True)
        print("  Downloading from PostHog (a minute or so)...", flush=True)
        PR.download(log=log)
    except SystemExit as e:
        print("  The download stopped: %s" % e)
    except Exception as e:  # network, the key file, PostHog's budget: say it and stay in the menu
        print("  The download failed: %s" % e)


def _choose_and_play(a, recs):
    if not recs:
        return
    ans = input("\n  Which run? Enter its number (Enter = 1, the newest): ").strip()
    k = 1
    if ans:
        if not ans.isdigit() or not 1 <= int(ans) <= len(recs):
            print("  There is no run %s." % ans)
            return
        k = int(ans)
    path, h = recs[k - 1]
    print()
    play(a, path, h)
    print("\n  The replay opens in its own window (Space pause, 1-7 speed, click the reel to jump, Esc closes it).")


def menu(a):
    while True:
        print("\n88fits replays")
        print("  1) Download new runs from the phone, then list them")
        print("  2) List the runs on this PC")
        print("  3) Watch a run")
        print("  4) Quit")
        try:
            c = input("Choose 1-4: ").strip()
        except EOFError:
            return 0
        if c == "1":
            _download()
            _numbered(a)
        elif c == "2":
            _numbered(a)
        elif c == "3":
            _choose_and_play(a, _numbered(a))
        elif c in ("4", "q", "Q", ""):
            return 0
        else:
            print("  Type 1, 2, 3 or 4.")


if __name__ == "__main__":
    sys.exit(main())

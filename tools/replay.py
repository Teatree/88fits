#!/usr/bin/env python3
"""Pass 114 (lane REPLAY): watch a recorded run again (analytics/howto/04_replays.md).

    python tools/replay.py --latest                 # the newest recording on this PC (downloaded or local)
    python tools/replay.py --latest --player "Lanky Tinker"
    python tools/replay.py <file>                   # one recording (a *_replay.json)
    python tools/replay.py --list [--player NAME]   # every recording: when, who, hero, stage, result, its build, kept?
    python tools/replay.py --trail [<file> | --latest]   # pass 129: only print the Trail the run began with (the nodes
                                                         # paid for and their gold, the upgrades summed by type, the
                                                         # unlocks); --board, pass 115's Upgrade board, is its old name
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
    line = "replay: " + msg
    try:
        print(line, flush=True)
    except UnicodeEncodeError:   # a console that cannot show a name's letter (cp1252 and "Jeżyk"): shown as "?"
        enc = sys.stdout.encoding or "ascii"
        print(line.encode(enc, "replace").decode(enc), flush=True)


def describe(h):
    b = h.get("build") or {}
    res = {"death": "died", "extract": "extracted", "abandon": "quit", "end": "ended"}.get(str(h.get("result", "")), str(h.get("result", "")))
    secs = float(h.get("play_s") or 0.0)
    return "%s | %s | %s stage %s | %s at %d:%02d | level %s | build %s" % (
        h.get("recorded", "?"), h.get("player") or "?", h.get("hero", "?"), h.get("stage", "?"), res, int(secs) // 60, int(secs) % 60,
        h.get("level", "?"), b.get("id", "?"))


# ---------------------------------------------------------------- pass 115 (lane DASH; Garry: "I need to know Player
# Mirror Upgrades while watching the replay"), pass 129: the Trail the recording's save began with, in the terminal (any
# recording, any build; the viewer shows it in its window too: B folds it). Until pass 129 this printed the Upgrade
# board from game/content/talents, which left the game with the board: a recording from before the Trail says in one
# line what its save held.

TRAIL_FILE = os.path.join(ROOT, "game", "content", "trail", "trail.json")
# where a gift's own JSON (its `name`) lives, by the gift's type
GIFT_DIRS = {"outlaw": "characters", "weapon": "weapons", "passive": "passives", "structure": "structures",
             "powerup": "pickups", "map": "maps"}
GIFT_WORDS = {"outlaw": "outlaws", "skin": "skins", "weapon": "weapons", "passive": "cards and items", "stage": "stages",
              "map": "maps", "structure": "structures", "powerup": "power-ups", "feature": "features"}


def _trail_defs(trail_file=None):
    """The Trail as the repo has it now (game/content/trail/trail.json): ({upgrade type: {name, kind, text}}, [node]);
    ({}, []) when the file cannot be read."""
    try:
        with open(trail_file or TRAIL_FILE, encoding="utf-8") as fh:
            d = json.load(fh)
    except (OSError, ValueError):
        return {}, []
    ups = d.get("upgrades") if isinstance(d, dict) else None
    nodes = d.get("nodes") if isinstance(d, dict) else None
    return (ups if isinstance(ups, dict) else {}), [n for n in (nodes if isinstance(nodes, list) else []) if isinstance(n, dict)]


def _plain(a):
    if abs(a - round(a)) < 0.001:
        return str(int(round(a)))
    if abs(a * 10.0 - round(a * 10.0)) < 0.001:
        return "%.1f" % a
    return "%.2f" % a


def amount_text(kind, value):
    """A sum as its upgrade kind writes it (Trail.amount_text): "+3%", "+2.5%", "+2", "+1", "+2 s"; "" for a word."""
    sg = "+" if value >= 0 else "-"
    a = abs(value)
    if kind == "percent":
        return sg + _plain(a * 100.0) + "%"
    if kind == "count":
        return sg + str(int(a + 0.5))
    if kind == "seconds":
        return sg + _plain(a) + " s"
    if kind == "word":
        return ""
    return sg + _plain(a)


def gift_key(gives):
    """The key a gift is gated under (Trail.gift_key): "<type>:<id>" ("stage:<map>:<stage id>" for a stage); "" for an
    upgrade or a gift that names nothing."""
    t = str(gives.get("type", ""))
    if t in ("", "upgrade"):
        return ""
    gid = str(gives.get("id", ""))
    if t == "stage" and gid == "":
        m, st = str(gives.get("map", "")), str(gives.get("stage", ""))
        gid = "%s:%s" % (m, st) if m and st else ""
    return "%s:%s" % (t, gid) if gid else ""


def _gift_name(key):
    """A gift's name from its own JSON (game/content/<folder>/<id>/<id>.json, the repo as it is now), else its id."""
    t, _, gid = key.partition(":")
    folder = GIFT_DIRS.get(t)
    if folder and gid:
        try:
            with open(os.path.join(ROOT, "game", "content", folder, gid, gid + ".json"), encoding="utf-8") as fh:
                nm = str(json.load(fh).get("name", ""))
            if nm:
                return nm
        except (OSError, ValueError, AttributeError):
            pass
    return gid.replace(":", " ")


def _picks(t):
    """An old save's talent entry as its ranks' forms (the Upgrade board, until pass 129): picks, else {form, rank}."""
    if not isinstance(t, dict):
        return []
    if isinstance(t.get("picks"), list):
        return [min(1, max(0, int(f))) for f in t["picks"]]
    return [min(1, max(0, int(t.get("form", 0))))] * int(t.get("rank", 0) or 0)


def trail_lines(path, trail_file=None):
    """The Trail the recorded run began with, as lines of plain text: from the recording's save (`trail`: the nodes
    paid for, what they cost, the gifts the save already had) and the Trail's file as the repo has it now. How many
    nodes were paid for and their gold, every upgrade type's sum written by its kind, the unlocks bought by type (one
    the save already had counts as bought at no cost, as Trail.gd reads it); [] when the recording cannot be read."""
    try:
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
    except (OSError, ValueError):
        return []
    if not isinstance(rec, dict):
        return []
    sv = rec.get("save")
    look = str(rec.get("look") or "")
    tail = ["the outlaw's look: " + look] if look else []
    tr = sv.get("trail") if isinstance(sv, dict) else None
    if not isinstance(tr, dict):
        old = sv.get("talents") if isinstance(sv, dict) else None
        if isinstance(old, dict):
            ranks = sum(len(_picks(t)) for t in old.values())
            spent = sv.get("talent_spent")
            return ["the Trail: not in this recording (recorded before the Trail; its save had the old Upgrade board: "
                    "%d rank%s%s)" % (ranks, "" if ranks == 1 else "s",
                                      (", %s gold paid" % "{:,}".format(int(spent))) if spent is not None else "")] + tail
        return ["the Trail: not in this recording"] + tail
    paid = [str(x) for x in tr["bought"]] if isinstance(tr.get("bought"), list) else []
    had = set(str(x) for x in tr["had"]) if isinstance(tr.get("had"), list) else set()
    for key, pre in (("heroes_owned", "outlaw:"), ("skins_owned", "skin:")):
        if isinstance(sv.get(key), list):
            had.update(pre + str(x) for x in sv[key])
    head = "the Trail the run began with: %d node%s paid for, %s gold" % (
        len(paid), "" if len(paid) == 1 else "s", "{:,}".format(int(tr.get("spent", 0) or 0)))
    ups, nodes = _trail_defs(trail_file)
    if not nodes:
        return [head, "    game/content/trail/trail.json cannot be read: what the nodes give is not listed"] + tail
    paid_set, seen = set(paid), set()
    totals, unlocks, free = {}, {}, 0
    for n in nodes:
        nid = str(n.get("id", ""))
        g = n.get("gives") if isinstance(n.get("gives"), dict) else {}
        key = gift_key(g)
        is_paid = nid in paid_set
        if is_paid:
            seen.add(nid)
        elif not (key and key in had):
            continue
        else:
            free += 1
        t = str(g.get("type", ""))
        if t == "upgrade":
            ut = str(g.get("upgrade", ""))
            try:
                totals[ut] = totals.get(ut, 0.0) + float(g.get("value", 0) or 0)
            except (TypeError, ValueError):
                pass
        elif key:
            unlocks.setdefault(t, []).append(_gift_name(key) + ("" if is_paid else " (the save had it)"))
    if free:
        head += "; %d more count%s as bought at no cost (the save already had what they give)" % (free, "s" if free == 1 else "")
    rows = []
    for ut in list(ups.keys()) + sorted(k for k in totals if k not in ups):
        if ut not in totals or abs(totals[ut]) < 0.0000001:
            continue
        u = ups.get(ut) if isinstance(ups.get(ut), dict) else {}
        rows.append(("        %-16s %-8s %s" % (str(u.get("name", ut)), amount_text(str(u.get("kind", "flat")), totals[ut]) or "bought",
                                                str(u.get("text", "")))).rstrip())
    out = [head] + ((["    upgrades, summed by type:"] + rows) if rows else ["    no upgrade bought"])
    for t, names in unlocks.items():
        out.append("    %s: %s" % (GIFT_WORDS.get(t, t), ", ".join(names)))
    gone = [x for x in paid if x not in seen]
    if gone:
        out.append("    %d paid node%s not in today's Trail file: %s" % (len(gone), " is" if len(gone) == 1 else "s are", ", ".join(gone)))
    return out + tail


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
    if getattr(a, "code_note", ""):
        v.append("code_note=" + a.code_note)
    return v


def code_changes(h):
    """Pass 120 (lane REPLAY): for a run recorded from the editor binary, the commits that changed game/ since it was
    recorded (newest first, [(hash, subject)]), or None when git cannot tell. A recording from before pass 120 names no
    files of its own, so this is how the replay can say the game changed since (the viewer's header shows it)."""
    utc = int(h.get("recorded_utc") or 0)
    if utc <= 0:
        return None
    try:
        out = subprocess.run(["git", "log", "--since=@%d" % utc, "--format=%h %s", "--", "game"], cwd=ROOT,
                             capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    rows = []
    for ln in out.stdout.splitlines():
        if ln.strip():
            hh, _, subj = ln.partition(" ")
            rows.append((hh, subj))
    return rows


def code_words(h):
    """The plain words for code_changes (empty when nothing changed or git cannot tell)."""
    rows = code_changes(h)
    if not rows:
        return ""
    subj = rows[0][1].split(":")[0]
    if len(subj) > 40:
        subj = subj[:37] + "..."
    return "%d commit%s changed the game since this run (newest %s, %s): it goes out of step because the code changed, not through a fault in the replay." % (
        len(rows), "" if len(rows) == 1 else "s", rows[0][0], subj)


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
    ap.add_argument("--trail", action="store_true", help="only print the Trail the run began with (pass 129)")
    ap.add_argument("--board", action="store_true", help="the old name for --trail (pass 115's Upgrade board left the game in pass 129)")
    a = ap.parse_args(argv)
    if a.menu:
        return menu(a)
    if a.list:
        return cmd_list(a)
    if a.board:
        say("--board is the old name for --trail (the Upgrade board left the game in pass 129): this prints the Trail")
    if a.trail or a.board:
        path = os.path.abspath(a.file) if a.file else pick_latest(a.player)[0]
        if not path:
            say("no recordings found")
            return 1
        say("the file: " + path)
        for ln in trail_lines(path):
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
    # pass 115 (lane DASH), pass 129: the Trail it began with (the viewer shows it too: B folds it)
    for ln in trail_lines(path):
        say(ln)
    bid = str((h.get("build") or {}).get("id", ""))
    if bid.startswith("editor-") or bid.startswith("dev-"):
        say("recorded from the editor binary, not a shipped build: it replays on the repo AS IT IS NOW (if the code or "
            "the content changed since the run, the replay may go out of step; the viewer's light says so)")
        # pass 120 (lane REPLAY): say whether it did (the viewer's header says it too). A recording from pass 120 on names
        # its files (build.code) and the viewer compares them exactly; an older one is told by git's commits since
        words = "" if (h.get("build") or {}).get("code") else code_words(h)
        if words:
            say(words)
            a.code_note = words
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

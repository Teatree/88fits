"""Pass 114 (lane REPLAY): the builds a replay plays on.

Garry: "Handle having the builds saved in some kind of a simple manner. Maybe they are kept in the build folder and
whenever I try to replay anything via this tool, it automatically selects the correct build. Make sure that it is well
communicated which build is being replayed."

A recording (core/systems/RunReplay.gd) replays exactly only on the build that recorded it, so every PC build ship.sh
makes is kept under builds/<build id>/ (git-ignored): the exe (88fits.exe, the game packed inside, the replay viewer
in it) and its build.json. The build id is stamped into the game before the export (game/config/build.json, read by
RunReplay.build_info and written into every recording):

    <version>-<UTC yyyymmdd-hhmm>-<git short hash>[-dirty]      e.g. 0.97-20261029-1402-abc1234

    python tools/builds.py stamp [--dry-run]            write game/config/build.json (ship.sh, before the exports)
    python tools/builds.py keep <exe> [--dry-run]       copy the exported exe into builds/<id>/ (ship.sh, after the PC build)
    python tools/builds.py list                          every kept build: id, date, size, how many recordings name it
    python tools/builds.py prune [--keep N] [--dry-run]  keep every build a recording names + the newest N (default 6)
    python tools/builds.py find <id>                     the build's folder, or the nearest one (and says it is not the same)

Recordings looked at for "named": analytics/remote/**/replays/*.json (downloaded by tools/posthog_runs.py),
analytics/runs/replays/*.json and the PC's own user folder (%APPDATA%/Godot/app_userdata/88fits/analytics/replays).
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILDS = os.path.join(ROOT, "builds")
STAMP = os.path.join(GAME, "config", "build.json")
KEEP_NEWEST = 6
EXE_NAME = "88fits.exe"


def _git(*args):
    try:
        r = subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True, text=True, timeout=30)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def game_version():
    with open(os.path.join(GAME, "project.godot"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^config/version="(.*)"', line.strip())
            if m:
                return m.group(1)
    return "?"


def make_stamp(now=None):
    """{id, version, utc, git, dirty}: the build about to be exported from the tree as it is now."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    ver = game_version()
    git = _git("rev-parse", "--short=7", "HEAD") or "nogit"
    # the stamp itself and the git-ignored output never make a tree dirty
    st = _git("status", "--porcelain", "--untracked-files=no")
    dirty = any(line.strip() and not line.strip().endswith("game/config/build.json") for line in st.splitlines())
    utc = now.strftime("%Y-%m-%d %H:%M")
    bid = "%s-%s-%s%s" % (ver, now.strftime("%Y%m%d-%H%M"), git, "-dirty" if dirty else "")
    return {"id": bid, "version": ver, "utc": utc + " UTC", "git": git, "dirty": dirty}


def cmd_stamp(a):
    s = make_stamp()
    if a.dry_run:
        print("stamp (dry run): would write %s:\n%s" % (STAMP, json.dumps(s, indent=2)))
        return 0
    os.makedirs(os.path.dirname(STAMP), exist_ok=True)
    with open(STAMP, "w", encoding="utf-8", newline="\n") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
    print("build id %s (game/config/build.json)" % s["id"])
    return 0


def read_stamp():
    if not os.path.isfile(STAMP):
        return {}
    with open(STAMP, encoding="utf-8") as f:
        return json.load(f)


def cmd_keep(a):
    exe = os.path.abspath(a.exe)
    s = read_stamp()
    if not s:
        print("keep: no game/config/build.json (run `python tools/builds.py stamp` before the export)")
        return 1
    if not os.path.isfile(exe):
        print("keep: no exe at %s" % exe)
        return 1
    dst = os.path.join(BUILDS, s["id"])
    mb = os.path.getsize(exe) / 1048576.0
    if a.dry_run:
        print("keep (dry run): would copy %s (%.0f MB) to %s with build.json" % (exe, mb, dst))
    else:
        os.makedirs(dst, exist_ok=True)
        shutil.copy2(exe, os.path.join(dst, EXE_NAME))
        with open(os.path.join(dst, "build.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(s, f, indent=2)
            f.write("\n")
        print("kept build %s (%.0f MB) in %s" % (s["id"], mb, dst))
    a.keep = KEEP_NEWEST
    return cmd_prune(a)


def builds():
    """[{id, dir, exe, stamp, utc, mb}] newest first."""
    out = []
    if not os.path.isdir(BUILDS):
        return out
    for name in os.listdir(BUILDS):
        d = os.path.join(BUILDS, name)
        bj = os.path.join(d, "build.json")
        if not os.path.isfile(bj):
            continue
        try:
            with open(bj, encoding="utf-8") as f:
                s = json.load(f)
        except (OSError, ValueError):
            continue
        exe = os.path.join(d, EXE_NAME)
        out.append({"id": s.get("id", name), "dir": d, "exe": exe if os.path.isfile(exe) else "", "stamp": s,
                    "utc": s.get("utc", ""), "mb": os.path.getsize(exe) / 1048576.0 if os.path.isfile(exe) else 0.0})
    out.sort(key=lambda b: b["utc"], reverse=True)
    return out


def recording_dirs():
    dirs = [os.path.join(ROOT, "analytics", "runs", "replays")]
    dirs += glob.glob(os.path.join(ROOT, "analytics", "remote", "**", "replays"), recursive=True)
    appdata = os.environ.get("APPDATA", "")
    if appdata:
        dirs.append(os.path.join(appdata, "Godot", "app_userdata", "88fits", "analytics", "replays"))
    return [d for d in dirs if os.path.isdir(d)]


def recordings():
    """[(path, header)] of every recording on this PC (header: the file's small fields), newest first."""
    out = []
    seen = set()
    for d in recording_dirs():
        for p in glob.glob(os.path.join(d, "*.json")):
            h = read_header(p)
            if not h:
                continue
            # the same run in two places (the PC's user folder and the repo's mirror): listed once
            key = (h.get("recorded_utc"), h.get("player"), h.get("hero"), h.get("frames_n"))
            if key in seen:
                continue
            seen.add(key)
            out.append((p, h))
    out.sort(key=lambda ph: (ph[1].get("recorded_utc", 0), ph[0]), reverse=True)
    return out


def read_header(path):
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return {}
    if not isinstance(d, dict) or d.get("kind") != "88fits_replay":
        return {}
    keep = ("build", "recorded", "recorded_utc", "player", "hero", "look", "stage", "map", "result", "play_s", "level", "kills",
            "device", "platform", "frames_n", "decisions")
    h = {k: d.get(k) for k in keep}
    h["decisions"] = len(d.get("decisions") or [])
    return h


def named_ids():
    ids = {}
    for _p, h in recordings():
        bid = str((h.get("build") or {}).get("id", ""))
        if bid:
            ids[bid] = ids.get(bid, 0) + 1
    return ids


def cmd_list(_a):
    bl = builds()
    named = named_ids()
    if not bl:
        print("no builds kept yet in %s (ship.sh keeps every PC build it makes)" % BUILDS)
    total = 0.0
    for b in bl:
        total += b["mb"]
        n = named.get(b["id"], 0)
        print("%-40s %-20s %6.0f MB  %s%s" % (b["id"], b["utc"], b["mb"], ("named by %d recording%s" % (n, "" if n == 1 else "s")) if n else "",
                                               "" if b["exe"] else "  (no exe!)"))
    if bl:
        print("%d builds, %.1f GB in %s" % (len(bl), total / 1024.0, BUILDS))
    missing = [i for i in named if i not in {b["id"] for b in bl}]
    for i in missing:
        print("missing: %s (named by %d recording%s; no such build here)" % (i, named[i], "" if named[i] == 1 else "s"))
    return 0


def cmd_prune(a):
    bl = builds()
    named = named_ids()
    keep_n = max(int(getattr(a, "keep", KEEP_NEWEST)), 0)
    gone = 0
    for i, b in enumerate(bl):
        if i < keep_n or b["id"] in named:
            continue
        if a.dry_run:
            print("prune (dry run): would remove %s (%.0f MB)" % (b["id"], b["mb"]))
        else:
            shutil.rmtree(b["dir"], ignore_errors=True)
            print("pruned %s (%.0f MB)" % (b["id"], b["mb"]))
        gone += 1
    if gone == 0:
        print("prune: nothing to remove (%d builds: the newest %d and every one a recording names stay)" % (len(bl), keep_n))
    return 0


def find(bid):
    """(build or None, exact) for a recording's build id: that build, else the one kept nearest in time (same version
    first), else None."""
    bl = builds()
    for b in bl:
        if b["id"] == bid:
            return b, True
    if not bl:
        return None, False
    ver = bid.split("-")[0] if bid else ""
    m = re.match(r"^[^-]+-(\d{8})-(\d{4})", bid or "")
    when = (m.group(1) + m.group(2)) if m else ""

    def key(b):
        bm = re.match(r"^[^-]+-(\d{8})-(\d{4})", b["id"])
        bw = (bm.group(1) + bm.group(2)) if bm else ""
        same_ver = 0 if b["stamp"].get("version") == ver else 1
        dist = abs(int(bw) - int(when)) if (bw and when) else 10 ** 12
        return (same_ver, dist)
    return sorted(bl, key=key)[0], False


def cmd_find(a):
    b, exact = find(a.id)
    if b is None:
        print("no build kept for %s (builds/ is empty)" % a.id)
        return 1
    print(("%s: %s" if exact else "%s is not kept; the nearest is %s") % (a.id, b["dir"] if exact else b["id"]))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="The kept builds replays play on (pass 114).")
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("stamp")
    p.add_argument("--dry-run", action="store_true")
    p = sp.add_parser("keep")
    p.add_argument("exe")
    p.add_argument("--dry-run", action="store_true")
    sp.add_parser("list")
    p = sp.add_parser("prune")
    p.add_argument("--keep", type=int, default=KEEP_NEWEST)
    p.add_argument("--dry-run", action="store_true")
    p = sp.add_parser("find")
    p.add_argument("id")
    a = ap.parse_args(argv)
    return {"stamp": cmd_stamp, "keep": cmd_keep, "list": cmd_list, "prune": cmd_prune, "find": cmd_find}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())

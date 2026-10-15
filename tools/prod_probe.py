#!/usr/bin/env python3
"""The production build's launch check (pass 81, lane PROD): an exported exe (prod or dev) cold-started headless to its
title, `--repeat` times, under the godot lock, with its user:// folder redirected to a scratch APPDATA (the PC save is
kept aside and put back as well, belt and braces), each launch bounded (`--quit-after 900` frames, 180 s):

    python tools/prod_probe.py <exe> [--expect prod|dev] [--out <probe.json>] [--repeat 3] [--work <dir>]

The log must show the Registry's line and Boot's "Boot: engine and autoloads N ms, title loaded in N ms, built in N ms,
first frame N ms" (the cold start to the title, reported as the median) and no SCRIPT ERROR; the save must land in the
prod build's own folder (%APPDATA%/88fits), never the dev build's (%APPDATA%/Godot/app_userdata/88fits).
Exported templates take no --script and no scene on the command line (release builds disable path overrides), so a run
cannot be started from outside: game/tools/prod_run_check.gd starts one in the staging copy with prod forced (the same
scripts and the same pruned content). Prints "prod_probe: OK ..." (exit 0) or "prod_probe: FAIL ..." (exit 1).
Standard library only.
"""
import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from locks import held, keep_save, restore_save  # noqa: E402

BOOT_RE = re.compile(r"Boot: engine and autoloads (\d+) ms, title loaded in (\d+) ms, built in (\d+) ms, first frame (\d+) ms")
REG_RE = re.compile(r"Registry: (\d+) weapons, (\d+) passives, (\d+) enemies, (\d+) elites, (\d+) characters")


def _user_dirs(appdata):
    """Where the exe keeps user:// under this APPDATA: the prod build's own folder, or the dev build's."""
    return [os.path.join(appdata, "88fits"), os.path.join(appdata, "Godot", "app_userdata", "88fits")]


def _run(exe, args, appdata, log, timeout):
    env = dict(os.environ)
    env["APPDATA"] = appdata
    t0 = time.time()
    try:
        p = subprocess.run([exe, "--headless", "--log-file", log] + args, env=env, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
        rc = p.returncode
        out = (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired as e:
        rc = -1
        out = (e.stdout.decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")) + "\nprod_probe: killed after %d s" % timeout
    return rc, out, round(time.time() - t0, 1)


def probe(exe, expect, work, repeat=1, log=print):
    exe = os.path.abspath(exe)
    res = {"exe": exe, "expect": expect, "boots": [], "fails": []}
    if not os.path.isfile(exe):
        res["fails"].append("no exe at %s" % exe)
        return res
    if os.path.isdir(work):
        shutil.rmtree(work)
    os.makedirs(work)
    with held("godot", "prod_probe %s" % os.path.basename(exe)):
        # a parent that holds the lock (tools/ship_prod.sh, LOCK_HELD_GODOT=1) keeps and puts back the save itself
        own_keep = not os.environ.get("LOCK_HELD_GODOT")
        if own_keep:
            keep_save()
        try:
            # 1. the title, `repeat` cold starts
            for k in range(max(1, repeat)):
                appdata = os.path.join(work, "appdata_title_%d" % k)
                os.makedirs(appdata)
                rc, out, secs = _run(exe, ["--quit-after", "900"], appdata, os.path.join(work, "title_%d.log" % k), 180)
                m = BOOT_RE.search(out)
                r = REG_RE.search(out)
                if "SCRIPT ERROR" in out:
                    res["fails"].append("title launch %d: SCRIPT ERROR: %s" % (k, out[out.index("SCRIPT ERROR"):][:300]))
                if not m:
                    res["fails"].append("title launch %d: no Boot line (rc %s): %s" % (k, rc, out[-400:]))
                    continue
                b = [int(x) for x in m.groups()]
                res["boots"].append({"autoloads_ms": b[0], "title_load_ms": b[1], "title_build_ms": b[2], "first_frame_ms": b[3],
                                     "to_title_ms": sum(b), "wall_s": secs})
                if r:
                    res["registry"] = r.group(0)
                res["errors_title"] = len([ln for ln in out.splitlines() if ln.startswith("ERROR")])
            # 2. where the save went: the prod build's own folder, never the dev build's
            appdata = os.path.join(work, "appdata_title_0")
            ud = next((d for d in _user_dirs(appdata) if os.path.isfile(os.path.join(d, "save.json"))), "")
            res["user_dir"] = os.path.relpath(ud, appdata) if ud else ""
            if not ud:
                res["fails"].append("no save.json in either user folder after the title (did the game start?)")
            elif expect == "prod" and "app_userdata" in ud:
                res["fails"].append("the prod build used the dev build's user folder (%s)" % res["user_dir"])
            elif expect == "dev" and "app_userdata" not in ud:
                res["fails"].append("the dev build used another user folder (%s)" % res["user_dir"])
        finally:
            if own_keep:
                restore_save()
    if res["boots"]:
        res["to_title_ms_median"] = int(statistics.median(b["to_title_ms"] for b in res["boots"]))
        res["autoloads_ms_median"] = int(statistics.median(b["autoloads_ms"] for b in res["boots"]))
    return res


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("exe")
    ap.add_argument("--expect", default="prod", choices=["prod", "dev"])
    ap.add_argument("--out", default="")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--work", default=os.path.join(ROOT, "tools", "dl", "prod", "probe"))
    a = ap.parse_args(argv)
    res = probe(a.exe, a.expect, os.path.abspath(a.work), a.repeat)
    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            json.dump(res, f, indent=1)
    if res["fails"]:
        for f in res["fails"]:
            print("prod_probe: FAIL " + f)
        return 1
    print("prod_probe: OK %s: cold start to the title %s ms (engine and autoloads %s ms, median of %d), user folder %s" % (
        a.expect, res.get("to_title_ms_median"), res.get("autoloads_ms_median"), len(res["boots"]), res.get("user_dir")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

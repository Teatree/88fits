#!/usr/bin/env python3
"""The production build's staging copy (pass 81, lane PROD): game/ copied fresh to tools/dl/prod/stage/game, where the
pruner (tools/prod_prune.py) and the optimiser (tools/prod_optimise.py) work and the prod presets export from. The
source tree is never touched.

    python tools/prod_stage.py [--stage tools/dl/prod/stage] [--version-code N]

What the copy is:
 - every file of game/ except export/, reports/, tests/ and .godot/; its .godot seeded from the real one (the imported
   files, so nothing imports again that did not change; never shader_cache/ or exported/);
 - its project.godot with its own user:// folder: application/config/use_custom_user_dir=true,
   custom_user_dir_name="88fits" (the prod exe's save lives in %APPDATA%/88fits, never the dev build's
   %APPDATA%/Godot/app_userdata/88fits) and, for the editor binary's runs on the staging copy (the plan, the checks, the
   smoke run), custom_user_dir_name.editor="88fits_prod_stage";
 - its export_presets.cfg with the Android Prod preset's version/code from the game's version (0.67 -> 6700, so every
   prod APK updates the last one).
The copy is made fresh every time (the pruner deletes from it, so an incremental copy would have to undo that first).
Standard library only.
"""
import argparse
import os
import re
import shutil
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
STAGE = os.path.join(ROOT, "tools", "dl", "prod", "stage")
SKIP_TOP = ("export", "reports", "tests", ".godot")
SKIP_GODOT = ("shader_cache", "exported")
USER_DIR = "88fits"
USER_DIR_EDITOR = "88fits_prod_stage"


def stage_game(stage=STAGE):
    return os.path.join(stage, "game")


def version_code(version):
    """'0.67' -> 6700, '1.2.3' -> 10203: monotonic as the game's version grows."""
    parts = [int(p) if p.isdigit() else 0 for p in (str(version).split(".") + ["0", "0"])[:3]]
    return max(1, parts[0] * 10000 + parts[1] * 100 + parts[2])


def project_version(project_text):
    m = re.search(r'(?m)^config/version="([^"]*)"', project_text)
    return m.group(1) if m else "0"


def patch_project(text):
    """[application] gains its own user:// folder (any earlier value of these keys replaced)."""
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(nl)
    keep = [ln for ln in lines if not re.match(r"^config/(use_custom_user_dir|custom_user_dir_name)(\.[a-z_]+)?\s*=", ln)]
    want = ["config/use_custom_user_dir=true", 'config/custom_user_dir_name="%s"' % USER_DIR,
            'config/custom_user_dir_name.editor="%s"' % USER_DIR_EDITOR]
    i = keep.index("[application]")
    j = i + 1
    while j < len(keep) and not keep[j].startswith("["):
        j += 1
    k = j
    while k > i + 1 and keep[k - 1].strip() == "":
        k -= 1
    return nl.join(keep[:k] + want + keep[k:])


def patch_presets(text, code):
    """The Android Prod preset's version/code (only that preset's options section)."""
    m = re.search(r'(?ms)^\[preset\.(\d+)\]\s*\nname="Android Prod"', text)
    if not m:
        raise SystemExit("prod_stage: no 'Android Prod' preset in export_presets.cfg")
    sec = "[preset.%s.options]" % m.group(1)
    a = text.index(sec)
    b = text.find("\n[preset.", a + len(sec))
    b = len(text) if b < 0 else b
    body = re.sub(r"(?m)^version/code=\d+$", "version/code=%d" % code, text[a:b])
    return text[:a] + body + text[b:]


def copy_tree(src, dst):
    n = 0
    nbytes = 0
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        if rel == ".":
            dirs[:] = [d for d in dirs if d not in SKIP_TOP]
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        out = os.path.join(dst, rel) if rel != "." else dst
        os.makedirs(out, exist_ok=True)
        for f in files:
            if f.endswith(".tmp"):
                continue
            shutil.copy2(os.path.join(root, f), os.path.join(out, f))
            n += 1
            nbytes += os.path.getsize(os.path.join(out, f))
    return n, nbytes


def make_stage(stage=STAGE, code=None, log=print):
    t0 = time.time()
    dst = stage_game(stage)
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    n, nbytes = copy_tree(GAME, dst)
    sg = os.path.join(GAME, ".godot")
    if os.path.isdir(sg):
        shutil.copytree(sg, os.path.join(dst, ".godot"), ignore=shutil.ignore_patterns(*SKIP_GODOT), dirs_exist_ok=True)
    pp = os.path.join(dst, "project.godot")
    with open(pp, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    version = project_version(text)
    with open(pp, "w", encoding="utf-8", newline="") as f:
        f.write(patch_project(text))
    code = code or version_code(version)
    ep = os.path.join(dst, "export_presets.cfg")
    with open(ep, "r", encoding="utf-8", newline="") as f:
        pt = f.read()
    with open(ep, "w", encoding="utf-8", newline="") as f:
        f.write(patch_presets(pt, code))
    secs = time.time() - t0
    log("prod_stage: %d files (%.1f MiB) -> %s in %.0f s; version %s, Android version code %d" % (
        n, nbytes / 1048576.0, dst, secs, version, code))
    return {"files": n, "bytes": nbytes, "secs": round(secs, 1), "version": version, "version_code": code, "dir": dst}


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stage", default=STAGE)
    ap.add_argument("--version-code", type=int, default=0)
    a = ap.parse_args(argv)
    make_stage(os.path.abspath(a.stage), a.version_code or None)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

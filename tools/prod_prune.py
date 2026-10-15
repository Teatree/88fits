#!/usr/bin/env python3
"""The production build's pruner (pass 81, lane PROD, Garry: "no extra art (unless it's used in the Level timeline)").
Works on the STAGING copy only (tools/prod_stage.py), from the plan game/tools/prod_plan.gd writes (the reachability in
game/tools/prod_reach.gd):

    python tools/prod_prune.py --plan <plan.json> [--stage tools/dl/prod/stage] [--report <prune.json>] [--dry-run]
    python tools/prod_prune.py --selftest      # a small fixture pruned in a temp folder, every rule below checked

What goes (each with its reason in the report):
 1. every content folder the plan drops (a hidden hero, weapon, evolution, mutation, perk, creature, pickup,
    structure, and the quests for them), unless a file that stays names a file inside it (then the folder stays, said so);
 2. the looks the plan drops: their entries leave the item's JSON (a hero's or a card's played look becomes the base
    when it was not), and their files (strip, icon) leave the folder unless the rewritten JSON still names them; a
    hero's title cut-out (art/ui/wanted/) that only a dropped look or a dropped hero names;
 3. every <id>_ai.json (the painters' sidecars; the game never reads them);
 4. every sound file under content/sounds that the sound map does not name (the placeholders of sounds that have
    their real one);
 then a reference check: no .tscn/.tres/.gd/.json/.cfg file that stays may name (res://...) a file that went; one that
 does keeps it (or its whole folder). Prints the `only=` list of rewritten folders for import_json.
Standard library only.
"""
import argparse
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE = os.path.join(ROOT, "tools", "dl", "prod", "stage")
TITLE_DIR = os.path.join("art", "ui", "wanted")
TEXT_EXTS = (".tscn", ".tres", ".gd", ".json", ".cfg", ".godot", ".gdshader")
RES_RE = re.compile(r"res://[^\"'\s\)\]\},]+")
SOUND_EXTS = (".wav", ".ogg", ".mp3")


def _load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _dump(path, d):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, indent=1, ensure_ascii=False)
        f.write("\n")


def _size(path):
    """A file's bytes plus what Godot imported from it (.godot/imported files named by its .import)."""
    n = os.path.getsize(path) if os.path.isfile(path) else 0
    imp = path + ".import"
    if os.path.isfile(imp):
        n += os.path.getsize(imp)
    return n


def imported_size(game, path):
    imp = path + ".import"
    if not os.path.isfile(imp):
        return 0
    with open(imp, "r", encoding="utf-8", errors="replace") as f:
        s = f.read()
    seen = set()
    n = 0
    for m in re.finditer(r'"res://(\.godot/imported/[^"]+)"', s):
        p = os.path.join(game, m.group(1))
        if p not in seen and os.path.isfile(p):
            seen.add(p)
            n += os.path.getsize(p)
    return n


def _rel(game, p):
    return os.path.relpath(p, game).replace(os.sep, "/")


def _res(game, p):
    return "res://" + _rel(game, p)


def _strings(x, out):
    if isinstance(x, dict):
        for v in x.values():
            _strings(v, out)
    elif isinstance(x, list):
        for v in x:
            _strings(v, out)
    elif isinstance(x, str):
        out.add(x)
    return out


def rewrite_looks(game, key, look, d):
    """The item's JSON without its dropped looks; returns (new dict, candidate files to delete (names in the folder),
    candidate title files (names under art/ui/wanted))."""
    vs = d.get("variants") or {}
    drop = [c for c in look["drop"] if c in vs]
    keep = [c for c in look["keep"] if c in vs]
    play = look["play"]
    id_ = key.split("/", 1)[1]
    cand = set()
    titles = set()
    for c in drop:
        e = vs.get(c)
        if isinstance(e, dict):
            for k in ("sprite", "icon"):
                if e.get(k):
                    cand.add(str(e[k]))
            if e.get("title"):
                titles.add(str(e["title"]))
    nd = dict(d)
    if look.get("promote") and play in vs and isinstance(vs[play], dict):
        e = vs[play]
        old_icon = str(d.get("icon", id_ + "_icon.png"))
        # the old base's own files (top level) may go once nothing names them; a played look without an icon of its
        # own wears the base's (JsonContent), which is then named outright so it stays
        if look["kind"] == "hero":
            cand.add(str(d.get("sprite", id_ + "_sprite.png")))
            if e.get("sprite"):
                nd["sprite"] = e["sprite"]
            for k in ("anims", "fps"):
                if k in e:
                    nd[k] = e[k]
            nd["strip_cols"] = int(e.get("strip_cols", 0))
            if "frame_px" in e:
                nd["frame_px"] = e["frame_px"]
        cand.add(old_icon)
        nd["icon"] = str(e["icon"]) if e.get("icon") else old_icon
        nd["variant_base"] = play
        nd["variant"] = play
    nd["variants"] = {c: vs[c] for c in vs if c in keep}
    # whatever the rewritten JSON still names stays
    named = _strings(nd, set())
    cand = {f for f in cand if f and f not in named}
    kept_titles = {str(e.get("title")) for c, e in nd["variants"].items() if isinstance(e, dict) and e.get("title")}
    titles = {t for t in titles if t not in kept_titles and t != "hero_%s.png" % id_}
    return nd, cand, titles


def scan_refs(game, skip_files, skip_dirs):
    """{res path: [the files naming it]} over every text file of the staging copy that stays."""
    refs = {}
    for root, dirs, files in os.walk(game):
        rel_root = _rel(game, root)
        if rel_root == ".":
            dirs[:] = [x for x in dirs if x not in (".godot", "tools", "tests", "addons")]
        absdir = os.path.abspath(root)
        if any(absdir == sd or absdir.startswith(sd + os.sep) for sd in skip_dirs):
            dirs[:] = []
            continue
        for f in files:
            if not f.endswith(TEXT_EXTS) or f.endswith("_ai.json"):
                continue
            p = os.path.abspath(os.path.join(root, f))
            if p in skip_files:
                continue
            try:
                with open(p, "r", encoding="utf-8", errors="replace") as fh:
                    s = fh.read()
            except OSError:
                continue
            for m in RES_RE.finditer(s):
                refs.setdefault(m.group(0), []).append(_rel(game, p))
    return refs


def prune(stage, plan, dry=False, log=print):
    game = os.path.join(stage, "game")
    content = os.path.join(game, "content")
    report = {"dirs": [], "dirs_kept_by_ref": [], "looks": [], "files": [], "files_kept_by_ref": [], "titles": [],
              "ai_json": 0, "sounds": [], "only": [], "bytes": {}}
    # 1. the folders
    del_dirs = {}
    for key, why in sorted(plan.get("drop", {}).items()):
        p = os.path.abspath(os.path.join(content, *key.split("/")))
        if os.path.isdir(p):
            del_dirs[p] = (key, why)
    # a dropped hero's title cut-outs (his own and his looks')
    del_files = {}
    for p, (key, why) in del_dirs.items():
        if key.startswith("characters/"):
            id_ = key.split("/", 1)[1]
            jp = os.path.join(p, id_ + ".json")
            names = {"hero_%s.png" % id_}
            if os.path.isfile(jp):
                for e in (_load(jp).get("variants") or {}).values():
                    if isinstance(e, dict) and e.get("title"):
                        names.add(str(e["title"]))
            for n in names:
                tp = os.path.abspath(os.path.join(game, TITLE_DIR, n))
                if os.path.isfile(tp):
                    del_files[tp] = "the title cut-out of %s (%s)" % (key, why)
    # 2. the looks
    rewritten = {}
    for key, look in sorted(plan.get("looks", {}).items()):
        if not look.get("drop") and not look.get("promote"):
            continue
        folder = os.path.join(content, *key.split("/"))
        id_ = key.split("/", 1)[1]
        jp = os.path.join(folder, id_ + ".json")
        if not os.path.isfile(jp) or os.path.abspath(folder) in del_dirs:
            continue
        d = _load(jp)
        nd, cand, titles = rewrite_looks(game, key, look, d)
        rewritten[os.path.abspath(jp)] = (key, nd)
        report["looks"].append({"item": key, "play": look["play"], "dropped": look["drop"], "kept": list(nd["variants"].keys()),
                                "promoted": bool(look.get("promote"))})
        for f in cand:
            fp = os.path.abspath(os.path.join(folder, f))
            if os.path.isfile(fp):
                del_files[fp] = "a dropped look of %s" % key
        for t in titles:
            tp = os.path.abspath(os.path.join(game, TITLE_DIR, t))
            if os.path.isfile(tp):
                del_files[tp] = "the title cut-out of a dropped look of %s" % key
    # 3. the painters' sidecars
    for root, dirs, files in os.walk(content):
        for f in files:
            if f.endswith("_ai.json"):
                del_files[os.path.abspath(os.path.join(root, f))] = "a painter's sidecar (_ai.json)"
    # 4. the sounds the sound map does not name
    sdir = os.path.join(content, "sounds")
    smap = os.path.join(sdir, "soundmap.json")
    if os.path.isfile(smap):
        named = set()
        for e in (_load(smap).get("sounds") or {}).values():
            if isinstance(e, dict):
                named.add(os.path.normpath(os.path.join(sdir, str(e.get("file", "")))))
        for root, dirs, files in os.walk(sdir):
            for f in files:
                if f.lower().endswith(SOUND_EXTS):
                    p = os.path.abspath(os.path.join(root, f))
                    if os.path.normpath(p) not in named:
                        del_files[p] = "a sound file the sound map does not name"
    # the reference check: a file that stays may not name one that goes
    skip_files = set(del_files) | {os.path.join(os.path.dirname(jp), os.path.splitext(os.path.basename(jp))[0] + ".tres")
                                   for jp in rewritten}
    skip_files |= set(rewritten)
    changed = True
    while changed:
        changed = False
        refs = scan_refs(game, skip_files, set(del_dirs))
        # the rewritten JSONs as they will be
        for jp, (key, nd) in rewritten.items():
            for s in _strings(nd, set()):
                for m in RES_RE.finditer(s):
                    refs.setdefault(m.group(0), []).append(_rel(game, jp))
        for ref, who in refs.items():
            p = os.path.abspath(os.path.join(game, *ref[len("res://"):].split("/")))
            if p in del_files:
                report["files_kept_by_ref"].append({"file": _rel(game, p), "why": del_files.pop(p), "named_by": who[:3]})
                skip_files.discard(p)
                changed = True
            for dp in list(del_dirs):
                if p == dp or p.startswith(dp + os.sep):
                    key, why = del_dirs.pop(dp)
                    report["dirs_kept_by_ref"].append({"dir": key, "why": why, "named_by": who[:3], "file": ref})
                    changed = True
    # the bytes (source + imported) and the deletes
    tot = {"dirs": 0, "files": 0, "imported": 0}
    for dp, (key, why) in sorted(del_dirs.items(), key=lambda kv: kv[1][0]):
        nb = 0
        ni = 0
        for root, dirs, files in os.walk(dp):
            for f in files:
                fp = os.path.join(root, f)
                nb += os.path.getsize(fp)
                if not f.endswith(".import"):
                    ni += imported_size(game, fp)
        tot["dirs"] += nb
        tot["imported"] += ni
        report["dirs"].append({"dir": key, "why": why, "bytes": nb, "imported": ni})
        if not dry:
            shutil.rmtree(dp)
    for fp, why in sorted(del_files.items()):
        nb = _size(fp)
        ni = imported_size(game, fp)
        tot["files"] += nb
        tot["imported"] += ni
        rel = _rel(game, fp)
        if fp.endswith("_ai.json"):
            report["ai_json"] += 1
        elif "/sounds/" in "/" + rel:
            report["sounds"].append(rel)
        elif rel.startswith(TITLE_DIR.replace(os.sep, "/")):
            report["titles"].append(rel)
        else:
            report["files"].append({"file": rel, "why": why, "bytes": nb, "imported": ni})
        if not dry:
            for q in (fp, fp + ".import", fp + ".uid"):
                if os.path.isfile(q):
                    os.remove(q)
    for jp, (key, nd) in rewritten.items():
        report["only"].append(key)
        if not dry:
            _dump(jp, nd)
            # its .tres still names the dropped looks' files: gone until import_json writes it again (the Registry
            # reads the JSON meanwhile), so nothing loads a missing file
            tres = os.path.splitext(jp)[0] + ".tres"
            if os.path.isfile(tres):
                os.remove(tres)
    report["bytes"] = tot
    log("prod_prune: %d folders (%.1f MiB), %d look rewrites, %d look files, %d title cut-outs, %d _ai.json, %d sounds; "
        "%.1f MiB of imported art and sound gone%s" % (
            len(report["dirs"]), tot["dirs"] / 1048576.0, len(report["looks"]), len(report["files"]), len(report["titles"]),
            report["ai_json"], len(report["sounds"]), tot["imported"] / 1048576.0, " (dry run)" if dry else ""))
    for k in report["dirs_kept_by_ref"]:
        log("prod_prune: kept %s (dropped as %s): %s names %s" % (k["dir"], k["why"], ", ".join(k["named_by"]), k["file"]))
    for k in report["files_kept_by_ref"]:
        log("prod_prune: kept %s (%s): named by %s" % (k["file"], k["why"], ", ".join(k["named_by"])))
    return report


def selftest():
    """A small staging copy in a temp folder pruned by a hand-made plan, every rule checked. Returns the failures."""
    import tempfile
    fails = []
    tmp = tempfile.mkdtemp(prefix="prod_prune_selftest_")
    game = os.path.join(tmp, "game")

    def put(rel, text="x"):
        p = os.path.join(game, *rel.split("/"))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(text if isinstance(text, str) else json.dumps(text, indent=1))
        return p

    def exists(rel):
        return os.path.exists(os.path.join(game, *rel.split("/")))

    try:
        h = "content/characters/hero1/"
        put(h + "hero1.json", {"id": "hero1", "variant_base": "H-A", "variant": "H-B", "anims": {"idle": 4}, "strip_cols": 9,
                                "variants": {"H-A": {"note": "base"},
                                             "H-B": {"sprite": "hero1_sprite_b.png", "icon": "hero1_icon_b.png", "title": "hero_hero1_b.png",
                                                     "anims": {"idle": 2}, "strip_cols": 4},
                                             "H-C": {"sprite": "hero1_sprite_c.png", "title": "hero_hero1_c.png"}}})
        for f in ("hero1_sprite.png", "hero1_icon.png", "hero1_sprite_b.png", "hero1_icon_b.png", "hero1_sprite_c.png"):
            put(h + f)
            put(h + f + ".import", "[remap]\n")
        put(h + "hero1_ai.json", "{}")
        for f in ("hero_hero1.png", "hero_hero1_b.png", "hero_hero1_c.png"):
            put("art/ui/wanted/" + f)
        # a played look without an icon of its own wears the base's badge, which must stay
        h2 = "content/characters/hero2/"
        put(h2 + "hero2.json", {"id": "hero2", "variant_base": "X-A", "variant": "X-B",
                                "variants": {"X-A": {}, "X-B": {"sprite": "hero2_sprite_b.png"}}})
        for f in ("hero2_sprite.png", "hero2_icon.png", "hero2_sprite_b.png"):
            put(h2 + f)
        c = "content/enemies/crit/"
        put(c + "crit.json", {"id": "crit", "variant_base": "C-0", "variant": "C-A", "sprite": "crit_sprite.png",
                              "variants": {"C-0": {}, "C-A": {"sprite": "crit_sprite_a.png"}, "C-B": {"sprite": "crit_sprite_b.png"},
                                           "C-C": {"sprite": "crit_sprite_c.png", "icon": "crit_icon_c.png"}}})
        for f in ("crit_sprite.png", "crit_sprite_a.png", "crit_sprite_b.png", "crit_sprite_c.png", "crit_icon_c.png"):
            put(c + f)
        put("content/weapons/gone/gone.json", {"id": "gone"})
        put("content/weapons/gone2/gone2.json", {"id": "gone2"})
        put("content/weapons/gone2/gone2_model.glb")
        put("content/weapons/keep/keep.json", {"id": "keep"})
        put("content/weapons/keep/keep_visual.tscn", '[ext_resource type="PackedScene" path="res://content/weapons/gone2/gone2_model.glb" id="1"]\n')
        put("content/sounds/soundmap.json", {"sounds": {"a": {"file": "real/a.wav"}}})
        put("content/sounds/real/a.wav")
        put("content/sounds/placeholder/a.wav")
        plan = {"drop": {"weapons/gone": "hidden", "weapons/gone2": "hidden"},
                "looks": {"characters/hero1": {"kind": "hero", "play": "H-B", "base": "H-A", "keep": ["H-B"], "drop": ["H-A", "H-C"],
                                               "promote": True},
                          "characters/hero2": {"kind": "hero", "play": "X-B", "base": "X-A", "keep": ["X-B"], "drop": ["X-A"],
                                               "promote": True},
                          "enemies/crit": {"kind": "creature", "play": "C-A", "base": "C-0", "keep": ["C-0", "C-A", "C-C"],
                                           "drop": ["C-B"], "promote": False}}}
        rep = prune(tmp, plan, log=lambda s: None)
        hj = _load(os.path.join(game, *(h + "hero1.json").split("/")))
        cj = _load(os.path.join(game, *(c + "crit.json").split("/")))
        checks = [
            (not exists("content/weapons/gone"), "a dropped folder goes"),
            (exists("content/weapons/gone2/gone2.json"), "a dropped folder a kept scene names stays"),
            (rep["dirs_kept_by_ref"] and rep["dirs_kept_by_ref"][0]["dir"] == "weapons/gone2", "the report says why it stayed"),
            (hj["variant_base"] == "H-B" and hj["variant"] == "H-B" and list(hj["variants"]) == ["H-B"], "the hero's played look is the base and the only one"),
            (hj["sprite"] == "hero1_sprite_b.png" and hj["icon"] == "hero1_icon_b.png" and hj["anims"] == {"idle": 2} and hj["strip_cols"] == 4,
             "the hero's top level is the played look's art"),
            (not exists(h + "hero1_sprite.png") and not exists(h + "hero1_sprite.png.import") and not exists(h + "hero1_icon.png"),
             "the old base's strip and icon go"),
            (not exists(h + "hero1_sprite_c.png") and exists(h + "hero1_sprite_b.png") and exists(h + "hero1_icon_b.png"), "only the dropped look's files go"),
            (not exists(h + "hero1_ai.json"), "the painter's sidecar goes"),
            (not exists("art/ui/wanted/hero_hero1_c.png") and exists("art/ui/wanted/hero_hero1_b.png") and exists("art/ui/wanted/hero_hero1.png"),
             "only the dropped look's title cut-out goes"),
            (list(cj["variants"]) == ["C-0", "C-A", "C-C"] and cj["variant"] == "C-A" and cj["variant_base"] == "C-0", "the creature keeps base, played, named"),
            (not exists(c + "crit_sprite_b.png") and exists(c + "crit_sprite.png") and exists(c + "crit_icon_c.png"), "the creature's dropped look's strip goes"),
            (exists("content/sounds/real/a.wav") and not exists("content/sounds/placeholder/a.wav"), "an unnamed sound goes"),
            (sorted(rep["only"]) == ["characters/hero1", "characters/hero2", "enemies/crit"], "the rewritten folders are listed for import_json"),
            (exists(h2 + "hero2_icon.png") and not exists(h2 + "hero2_sprite.png")
             and _load(os.path.join(game, *(h2 + "hero2.json").split("/")))["icon"] == "hero2_icon.png",
             "a played look without its own icon keeps the base's badge, named outright"),
        ]
        fails = [msg for ok, msg in checks if not ok]
    except Exception as e:  # noqa: BLE001 - the self-test reports anything
        fails.append("selftest raised %r" % e)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return fails


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", default="")
    ap.add_argument("--stage", default=STAGE)
    ap.add_argument("--report", default="")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true", help="prune a small fixture in a temp folder and check every rule")
    a = ap.parse_args(argv)
    if a.selftest:
        fails = selftest()
        for f in fails:
            print("prod_prune selftest: FAIL " + f)
        print("prod_prune selftest: %s" % ("OK" if not fails else "%d failures" % len(fails)))
        return 1 if fails else 0
    if not a.plan:
        ap.error("--plan is required")
    stage = os.path.abspath(a.stage)
    if os.path.abspath(os.path.join(stage, "game")) == os.path.abspath(os.path.join(ROOT, "game")):
        raise SystemExit("prod_prune: refusing to prune the source tree")
    plan = _load(a.plan)
    rep = prune(stage, plan, dry=a.dry_run)
    if a.report:
        with open(a.report, "w", encoding="utf-8", newline="\n") as f:
            json.dump(rep, f, indent=1)
    print("prod_prune: only=" + ",".join(rep["only"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

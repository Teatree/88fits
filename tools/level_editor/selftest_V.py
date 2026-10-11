"""Lane V's checks (pass 66), discovered by selftest.py's extra_checks(): the strip player's pure maths under Node against
Python copies and the game's own tables (the strip order, Player.gd's view fallback chain, EnemyManager's mirror rule),
the frame grid on the real strips on disk, the three modules parse, methods.json's example pictures exist, preview.css is
balanced, docs/assets_schema.md has its sections. Standard library only; Node on PATH for the JS part (skipped without)."""
import json
import os
import re
import shutil
import struct
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

ENEMY_ORDER = ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
CHAR_ORDER = ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]
SUFFIX = {"enemy": {"front": "", "back": "_b", "side": "_s", "bd": "_bd", "fd": "_fd"}, "hero": {"back": "", "front": "_f", "side": "_s", "bd": "_bd", "fd": "_fd"}}
CHAIN = {"hero": {"": [""], "_bd": ["_bd", "_s", ""], "_s": ["_s", "_bd", "_fd", ""], "_fd": ["_fd", "_s", "_f"], "_f": ["_f", "_fd", ""]},
         "enemy": {"": [""], "_b": ["_b", ""], "_s": ["_s", ""], "_bd": ["_bd", "_b", ""], "_fd": ["_fd", ""]}}
BASE_ONLY = {"enemy": ["attack", "hit", "die"], "hero": ["die", "cheer", "turn"]}
VIEW_OF_SUFFIX = {"enemy": {"": "front", "_b": "back", "_s": "side", "_bd": "bd", "_fd": "fd"}, "hero": {"": "back", "_f": "front", "_s": "side", "_bd": "bd", "_fd": "fd"}}

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const SP = require(path.join(dir, 'strip_player.js'));
let q = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => { q += d; });
process.stdin.on('end', () => {
  const Q = JSON.parse(q);
  const out = {};
  out.offsets = Q.offsets.map((o) => SP.frameOffset(o.anims, o.anim, o.kind === 'hero' ? SP.CHAR_ORDER : SP.ENEMY_ORDER));
  out.totals = Q.totals.map((a) => SP.totalFrames(a));
  out.cells = Q.cells.map((c) => SP.cell(c.k, c.cols, c.px));
  out.keys = Q.keys.map((k) => SP.animKey(k.kind, k.anims, k.anim, k.dir));
  out.fps = Q.fps.map((f) => SP.previewFps(f.kind, f.anim, f.fps));
  out.mirror = Q.mirror.map((m) => SP.mirror(m.kind, m.view, m.facing, m.ff, m.bf));
  out.dirs = Q.dirs.map((d) => SP.dirList(d.kind, d.anims).map((x) => x.v));
  out.anims = Q.anims.map((a) => SP.animList(a.kind, a.anims).map((x) => x.v));
  out.consts = { cap: SP.MAX_ANIMATING, lru: SP.LRU_MAX, ppm: SP.PPM, hero: SP.HERO_SIZE, enemyOrder: SP.ENEMY_ORDER, charOrder: SP.CHAR_ORDER, chain: SP.CHAIN.hero };
  process.stdout.write(JSON.stringify(out));
});
"""


# ---------------------------------------------------------------- Python twins

def frame_offset(anims, anim, order):
    off = 0
    for a in order:
        if a == anim:
            return off
        off += int(anims.get(a, 0)) if anims.get(a, 0) and anims[a] > 0 else 0
    return -1


def total_frames(anims):
    return sum(int(v) for v in anims.values() if v and v > 0)


def cell(k, cols, px):
    c = cols if cols > 0 else max(1, k + 1)
    return [(k % c) * px, (k // c) * px]


def anim_key(kind, anims, anim, direction):
    k = "hero" if kind == "hero" else "enemy"
    has = lambda key: bool(anims.get(key, 0) and anims[key] > 0)  # noqa: E731
    if anim in BASE_ONLY[k] or not direction:
        return {"key": anim, "suffix": "", "asked": "", "fell": False, "view": VIEW_OF_SUFFIX[k][""], "ok": has(anim)}
    asked = SUFFIX[k].get(direction, "")
    for s in CHAIN[k].get(asked, [asked, ""]):
        if has(anim + s):
            return {"key": anim + s, "suffix": s, "asked": asked, "fell": s != asked, "view": VIEW_OF_SUFFIX[k][s], "ok": True}
    return {"key": anim + asked, "suffix": asked, "asked": asked, "fell": False, "view": VIEW_OF_SUFFIX[k][asked], "ok": False}


def preview_fps(kind, anim, fps):
    base = anim.split("_")[0]
    num = lambda key: float(fps[key]) if isinstance(fps.get(key), (int, float)) and fps[key] > 0 else 0  # noqa: E731
    if kind == "hero":
        if num(base):
            return num(base)
        return {"run": 14, "hit": 12, "die": 8, "turn": 8}.get(base, 6)
    if base == "run":
        return num("run") or 10
    if base == "die":
        return num("die") or 6
    return {"attack": 8, "hit": 8}.get(base, 6)


def mirror(kind, view, facing, ff, bf):
    left = facing == "left"
    if view in ("side", "bd", "fd"):
        return left
    if kind == "hero":
        return False
    faces = (bf or "right") if view == "back" else (ff or "right")
    if faces == "left":
        return not left
    if faces == "straight":
        return False
    return left


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def strip_cases():
    """The real strips the brief names: (kind, json path, strip file, code)."""
    out = []
    for kind, rel, code in (("enemy", "enemies/lesser_scorpion/lesser_scorpion.json", "LS-B"), ("enemy", "bosses/tumbleweed_king/tumbleweed_king.json", ""),
                            ("hero", "characters/solenne/solenne.json", "SOL-B")):
        path = os.path.join(GAME, "content", rel)
        if not os.path.isfile(path):
            continue
        d = load_json(path)
        entry = (d.get("variants") or {}).get(code, {}) if code else {}
        sprite = entry.get("sprite") or d.get("sprite")
        anims = entry.get("anims") or d.get("anims") or {}
        cols = entry.get("strip_cols") or d.get("strip_cols") or 0
        px = entry.get("frame_px") or d.get("frame_px") or (256 if kind == "hero" else 128)
        full = os.path.join(os.path.dirname(path), os.path.basename(str(sprite)))
        if os.path.isfile(full):
            out.append((kind, d["id"], code, anims, int(cols), int(px), full))
    return out


# ---------------------------------------------------------------- the checks

def checks(check, run_node, server):
    node = shutil.which("node")
    files = ["strip_player.js", "looks.js", "jobs.js"]

    # 1. the modules parse; the globals they define are the ones index.html expects
    for name in files:
        path = os.path.join(HERE, name)
        check(os.path.isfile(path), "V: %s exists" % name)
        if node and os.path.isfile(path):
            p = subprocess.run([node, "--check", path], capture_output=True, text=True, encoding="utf-8", timeout=60)
            check(p.returncode == 0, "V: node --check %s (%s)" % (name, p.stderr.strip()[:200]))
    with open(os.path.join(HERE, "strip_player.js"), "r", encoding="utf-8") as f:
        sp_src = f.read()
    check("const StripPlayer = (() =>" in sp_src and "const IconPreview = StripPlayer.IconPreview" in sp_src and "const CutoutPreview = StripPlayer.CutoutPreview" in sp_src, "V: strip_player.js defines StripPlayer, IconPreview, CutoutPreview")
    check("MAX_ANIMATING = 12" in sp_src and "LRU_MAX = 16" in sp_src and "PPM = 94" in sp_src, "V: the cap is 12, the LRU 16, the scale 94 px/m")
    check("rootMargin: '100px'" in sp_src, "V: the IntersectionObserver's margin is 100 px")
    with open(os.path.join(HERE, "looks.js"), "r", encoding="utf-8") as f:
        lg_src = f.read()
    check("const LookGrid = (() =>" in lg_src and "PAGE = 24" in lg_src, "V: looks.js defines LookGrid with pages of 24")
    check("'Duplicate…'" in lg_src and "function painterText" in lg_src and "duplicateOf: look.code" in lg_src and "painterText, render" in lg_src, "V: a look card offers Duplicate… and shows its painter (LookGrid.painterText)")
    with open(os.path.join(HERE, "jobs.js"), "r", encoding="utf-8") as f:
        jb_src = f.read()
    check("const Jobs = (() =>" in jb_src and "FAST = 2000" in jb_src and "jobs-badge" in jb_src, "V: jobs.js defines Jobs, polls every 2 s, drives #jobs-badge")
    check("opts.duplicateOf" in jb_src and "opts.painter" in jb_src and "srcStills" in jb_src and "class: 'jinh'" in jb_src, "V: the job form takes a duplicate (recipe and painter copied, the stills slug cleared, reuse offered) and greys inherited words")
    for route in ("/api/jobs?since=", "/api/status", "/api/methods", "/api/drivers", "/api/refs", "/api/upload", "/api/content/", "/look/"):
        check(route in jb_src or route in lg_src, "V: the page calls %s" % route)

    # 2. the game's tables the player copies, read from the source
    player_gd = os.path.join(GAME, "player", "Player.gd")
    enemy_def = os.path.join(GAME, "core", "data", "EnemyDef.gd")
    if os.path.isfile(player_gd):
        with open(player_gd, "r", encoding="utf-8") as f:
            src = f.read()
        m = re.search(r'var chain: Array = (\{.*?\})\.get\(_view', src)
        check(m is not None, "V: Player.gd's view fallback chain found")
        if m:
            game_chain = json.loads(m.group(1))
            check(game_chain == CHAIN["hero"], "V: the hero fallback chain equals Player.gd's (%s)" % json.dumps(game_chain))
        m = re.search(r'sprite\.setup\(tex, anims, \[([^\]]*)\], 1\.9, cols, fps\)', src)
        check(m is not None, "V: Player.gd's strip order and 1.9 m height found")
        if m:
            order = [x.strip().strip('"') for x in m.group(1).split(",")]
            check(order == CHAR_ORDER, "V: CHAR_ORDER equals Player.gd's order")
    if os.path.isfile(enemy_def):
        with open(enemy_def, "r", encoding="utf-8") as f:
            src = f.read()
        m = re.search(r'func frame_offset\(anim: String\) -> int:.*?for k in \[([^\]]*)\]', src, re.S)
        check(m is not None, "V: EnemyDef.frame_offset's order found")
        if m:
            order = [x.strip().strip('"') for x in m.group(1).split(",")]
            check(order == ENEMY_ORDER, "V: ENEMY_ORDER equals EnemyDef's order")
        check('front_faces: String = "right"' in src and 'back_faces: String = "right"' in src, "V: EnemyDef defaults front_faces / back_faces to right")

    # 3. the frame grid on the real strips
    cases = strip_cases()
    check(len(cases) >= 2, "V: at least two of the three real strips are on disk (%d)" % len(cases))
    q = {"offsets": [], "totals": [], "cells": [], "keys": [], "fps": [], "mirror": [], "dirs": [], "anims": []}
    expect = {"offsets": [], "totals": [], "cells": [], "keys": [], "fps": [], "mirror": []}
    for kind, cid, code, anims, cols, px, full in cases:
        size = png_size(full)
        total = total_frames(anims)
        c = cols or total
        rows = -(-total // c)
        check(size is not None and size[0] == c * px and size[1] == rows * px, "V: %s %s strip is %d x %d cells of %d px (%s)" % (cid, code or "base", c, rows, px, size))
        order = CHAR_ORDER if kind == "hero" else ENEMY_ORDER
        last_anim = [a for a in order if anims.get(a, 0) > 0][-1]
        x, y = cell(total - 1, cols, px)
        check(size is not None and x + px <= size[0] and y + px <= size[1], "V: %s's last frame lies inside the strip" % cid)
        for a in order:
            if anims.get(a, 0) > 0:
                q["offsets"].append({"kind": kind, "anims": anims, "anim": a})
                expect["offsets"].append(frame_offset(anims, a, order))
        q["totals"].append(anims)
        expect["totals"].append(total)
        for k in (0, 1, c - 1, c, total - 1):
            if 0 <= k < total:
                q["cells"].append({"k": k, "cols": cols, "px": px})
                expect["cells"].append(cell(k, cols, px))
        check(frame_offset(anims, last_anim, order) + anims[last_anim] == total, "V: %s's offsets sum to its total (%d)" % (cid, total))

    # 4. the view keys, the rates, the mirror rule: Python twin vs the JS
    e8 = {"idle": 4, "run": 12, "attack": 2, "hit": 1, "die": 8, "run_b": 12, "idle_b": 4, "run_s": 12, "idle_s": 4, "run_bd": 12, "idle_bd": 4, "run_fd": 12, "idle_fd": 4}
    e2 = {"idle": 4, "run": 12, "attack": 2, "hit": 1, "die": 8, "run_b": 12, "idle_b": 4}
    h8 = {"idle": 4, "run": 24, "hit": 4, "die": 5, "cheer": 1, "idle_f": 4, "run_f": 24, "idle_s": 4, "run_s": 24, "idle_bd": 4, "run_bd": 24, "idle_fd": 4, "run_fd": 24, "hit_f": 4, "hit_s": 4, "hit_bd": 4, "hit_fd": 4}
    h_old = {"idle": 4, "run": 24, "hit": 4, "die": 5, "cheer": 1, "idle_f": 4, "run_f": 24}
    for kind, anims in (("enemy", e8), ("enemy", e2), ("hero", h8), ("hero", h_old)):
        for anim in (BASE_ONLY[kind] + ["idle", "run"]):
            for d in ("front", "back", "side", "bd", "fd"):
                q["keys"].append({"kind": kind, "anims": anims, "anim": anim, "dir": d})
    expect["keys"] = [anim_key(x["kind"], x["anims"], x["anim"], x["dir"]) for x in q["keys"]]
    # a few pinned facts of the chain
    check(anim_key("hero", h_old, "run", "side")["key"] == "run" and anim_key("hero", h_old, "run", "side")["fell"], "V: a hero strip without a side view plays the back (Player.gd chain)")
    check(anim_key("hero", h_old, "idle", "fd")["key"] == "idle_f", "V: a hero's missing fd view falls to _s then _f")
    check(anim_key("enemy", e2, "run", "bd")["key"] == "run_b", "V: a 2-way creature's bd plays the back set")
    check(anim_key("enemy", e8, "die", "side")["key"] == "die" and not anim_key("enemy", e8, "die", "side")["fell"], "V: a creature's die is painted once, front set")
    for kind, anim, fps in (("enemy", "run", {"run": 20, "die": 12}), ("enemy", "run", {}), ("enemy", "die", {}), ("enemy", "idle", {"run": 20}), ("enemy", "attack", {}), ("hero", "run_f", {"run": 36}), ("hero", "run", {}), ("hero", "hit_bd", {"hit": 12}), ("hero", "hit", {}), ("hero", "die", {"die": 8}), ("hero", "cheer", {}), ("hero", "idle_s", {})):
        q["fps"].append({"kind": kind, "anim": anim, "fps": fps})
        expect["fps"].append(preview_fps(kind, anim, fps))
    check(preview_fps("enemy", "run", {}) == 10 and preview_fps("enemy", "die", {}) == 6 and preview_fps("hero", "run", {}) == 14 and preview_fps("hero", "hit", {}) == 12 and preview_fps("hero", "die", {}) == 8, "V: the preview rate defaults are the brief's")
    for kind in ("enemy", "hero"):
        for view in ("front", "back", "side", "bd", "fd"):
            for facing in ("right", "left"):
                for ff in ("right", "left", "straight"):
                    q["mirror"].append({"kind": kind, "view": view, "facing": facing, "ff": ff, "bf": ff})
                    expect["mirror"].append(mirror(kind, view, facing, ff, ff))
    check(mirror("enemy", "front", "left", "right", "right") and not mirror("enemy", "front", "left", "left", "right") and not mirror("enemy", "front", "left", "straight", "right") and not mirror("hero", "front", "left", "right", "right") and mirror("hero", "side", "left", "right", "right"), "V: the mirror rule follows EnemyManager._face_bit and Player's side-only mirror")
    q["dirs"] = [{"kind": "enemy", "anims": e8}, {"kind": "enemy", "anims": e2}, {"kind": "hero", "anims": h8}]
    q["anims"] = [{"kind": "enemy", "anims": e8}, {"kind": "hero", "anims": h8}]

    res = run_node(q, RUNNER) if node else None
    if res is None:
        print("V: node not found: the strip player's JS maths skipped")
    elif res == {}:
        check(False, "V: strip_player.js ran under node")
    else:
        check(res.get("offsets") == expect["offsets"], "V: frameOffset agrees with Python on every animation of the real strips (%d)" % len(expect["offsets"]))
        check(res.get("totals") == expect["totals"], "V: totalFrames agrees (%s)" % expect["totals"])
        check(res.get("cells") == expect["cells"], "V: cell() agrees on %d frames" % len(expect["cells"]))
        same = sum(1 for a, b in zip(res.get("keys", []), expect["keys"]) if a == b)
        check(same == len(expect["keys"]) and len(res.get("keys", [])) == len(expect["keys"]), "V: animKey agrees on %d of %d (anim, view) cases" % (same, len(expect["keys"])))
        check(res.get("fps") == expect["fps"], "V: previewFps agrees (%s)" % res.get("fps"))
        check(res.get("mirror") == expect["mirror"], "V: mirror() agrees on %d cases" % len(expect["mirror"]))
        dirs = res.get("dirs", [])
        check(len(dirs) == 3 and len(dirs[0]) == 8 and len(dirs[1]) == 2 and len(dirs[2]) == 8, "V: 8 directions with run_s, 2 without (%s)" % [len(d) for d in dirs])
        check(dirs and dirs[0] == ["front", "fd_r", "side_r", "bd_r", "back", "bd_l", "side_l", "fd_l"], "V: the eight directions in order")
        an = res.get("anims", [])
        check(an == [["idle", "run", "attack", "hit", "die"], ["idle", "run", "hit", "die", "cheer"]], "V: the animation lists show the base names with frames (%s)" % an)
        c = res.get("consts", {})
        check(c.get("cap") == 12 and c.get("lru") == 16 and c.get("ppm") == 94 and c.get("hero") == 1.9, "V: the exported constants")
        check(c.get("enemyOrder") == ENEMY_ORDER and c.get("charOrder") == CHAR_ORDER and c.get("chain") == CHAIN["hero"], "V: the exported orders and chain equal the game's")

    # 5. methods.json's example pictures (lane B's file; skipped while it is missing)
    mpath = os.path.join(HERE, "methods.json")
    if os.path.isfile(mpath):
        try:
            m = load_json(mpath)
            methods = m.get("methods", [])
            check(isinstance(methods, list) and methods, "V: methods.json has methods (%d)" % len(methods))
            missing = []
            for x in methods:
                ex = x.get("example") or {}
                img = ex.get("image")
                if img and not img.startswith("/"):
                    if not os.path.isfile(os.path.join(HERE, img.replace("/", os.sep))):
                        missing.append(img)
            check(not missing, "V: every methods.json example picture exists under tools/level_editor/ (missing: %s)" % missing)
            big = [p for p in (os.path.join(HERE, "examples", f) for f in os.listdir(os.path.join(HERE, "examples"))) if os.path.isfile(p) and os.path.getsize(p) > 150 * 1024] if os.path.isdir(os.path.join(HERE, "examples")) else []
            check(not big, "V: every example picture is at most 150 KB (%s)" % [os.path.basename(b) for b in big])
            for key in ("ref_wordings", "insert_3d_text", "timings_note"):
                check(key in m, "V: methods.json carries %s" % key)
            roles = {r.get("role") for r in m.get("ref_wordings", [])}
            check({"identity", "pose", "style"} <= roles or {"identity", "pose-and-anatomy"} <= roles, "V: ref_wordings cover identity, style and pose (%s)" % sorted(roles))
            for x in methods:
                for f in (x.get("recipe_fields") or []) + (x.get("job_fields") or []):
                    check(f.get("type") in ("number", "int", "text", "textarea", "select", "driver", "file", "bool", "json", "view_words"), "V: %s.%s has a type the form renders (%s)" % (x["id"], f.get("key"), f.get("type")))
                    if f.get("type") == "select":
                        check(isinstance(f.get("options"), list) and f["options"], "V: %s.%s select has options" % (x["id"], f.get("key")))
                    if f.get("type") == "view_words":
                        check(isinstance(f.get("views"), list) and f["views"], "V: %s.%s view_words names its views" % (x["id"], f.get("key")))
        except ValueError as e:
            check(False, "V: methods.json parses (%s)" % e)
    else:
        print("V: tools/level_editor/methods.json is not here yet: the example-picture checks skipped")

    # 6. preview.css: balanced braces, no stray style.css selectors redefined
    with open(os.path.join(HERE, "preview.css"), "r", encoding="utf-8") as f:
        css = f.read()
    check(css.count("{") == css.count("}") and css.count("{") > 40, "V: preview.css braces balance (%d rules)" % css.count("{"))
    check("\r" not in css and "\r" not in sp_src and "\r" not in lg_src and "\r" not in jb_src, "V: lane V's files are LF")
    for sel in (".sp-modal", ".lookgrid", ".jcard", ".jform", ".icon-preview", ".cutout", ".jobs-badge"):
        check(sel in css, "V: preview.css styles %s" % sel)

    # 7. the schema doc
    doc = os.path.join(ROOT, "docs", "assets_schema.md")
    check(os.path.isfile(doc), "V: docs/assets_schema.md exists")
    if os.path.isfile(doc):
        with open(doc, "r", encoding="utf-8") as f:
            text = f.read()
        for head in ("## Looks", "## Heroes", "## Items", "## The look record", "## The jobs queue", "## The ledger", "## Locks"):
            check(head in text, "V: assets_schema.md has the section %s" % head)
        for key in ("shelved", "fresh", "availability", "currency_type", "variant_base", "written", "unmerged", "created.json"):
            check(key in text, "V: assets_schema.md names %s" % key)

    # 8. the Instructions tab's new sections
    with open(os.path.join(HERE, "instructions.js"), "r", encoding="utf-8") as f:
        ins = f.read()
    for title in ("Pass 66: the asset editors", "Looks and previews", "Art jobs", "The Jobs tab", "/api/schema/assets"):
        check(title in ins, "V: instructions.js has %s" % title)

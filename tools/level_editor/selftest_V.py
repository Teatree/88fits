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
    files = ["strip_player.js", "looks.js", "jobs.js", "assets.js", "assets_fields.js", "instructions.js"]

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
    check("'Duplicate…'" in lg_src and "function painterText" in lg_src and "duplicateDraft(kind, id, record, s, look)" in lg_src and "return { painterText, " in lg_src, "V: a look card offers Duplicate… (a draft since pass 68) and shows its painter (LookGrid.painterText)")
    with open(os.path.join(HERE, "jobs.js"), "r", encoding="utf-8") as f:
        jb_src = f.read()
    check("const Jobs = (() =>" in jb_src and "FAST = 2000" in jb_src and "jobs-badge" in jb_src, "V: jobs.js defines Jobs, polls every 2 s, drives #jobs-badge")
    check("opts.duplicateOf" in jb_src and "opts.painter" in jb_src and "srcStills" in jb_src and "class: 'jinh'" in jb_src, "V: the job form takes a duplicate (recipe and painter copied, the stills slug cleared, reuse offered) and greys inherited words")
    check("'push_workflows'" in jb_src and "o.open_url" in jb_src and "/api/workflows/push" in jb_src and "comfy_open_ext" in jb_src and "filter((o) => o.open_url).length" in jb_src,
          "V: the job card opens each workflow in ComfyUI (open_url), offers Send to ComfyUI, the form pushes the templates, and the card redraws when a link lands")
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
    for name in ("assets.js", "assets_fields.js", "instructions.js", "style.css", "selftest_V.py", "selftest_P.py"):
        with open(os.path.join(HERE, name), "rb") as f:
            check(b"\r" not in f.read(), "V: %s is LF" % name)
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
    for title in ("Pass 66: the asset editors", "Looks and previews", "Art jobs", "The Jobs tab", "/api/schema/assets", "Pass 68: drafts, candidates and the queue order"):
        check(title in ins, "V: instructions.js has %s" % title)

    # 9. pass 68 (lane W): drafts, the required candidates, the defaults, the honest form, the queue order
    pass68_checks(check, run_node, node)


# ---------------------------------------------------------------- pass 68 (lane W): the page's drafts, candidates and queue

PURE_RUNNER = r"""
const path = require('path');
const fs = require('fs');
const dir = path.dirname(process.argv[2]);
global.U = new Function(fs.readFileSync(path.join(dir, 'util.js'), 'utf8') + '\nreturn U;')();
const J = require(path.join(dir, 'jobs.js'));
const L = require(path.join(dir, 'looks.js'));
let q = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => { q += d; });
process.stdin.on('end', () => {
  const Q = JSON.parse(q);
  const out = {};
  out.order = J.queueOrder(Q.queue).map((x) => [x.job.id, x.pos, x.n]);
  out.labels = [J.queueLabel(0, 3, 'comfy'), J.queueLabel(2, 3, 'comfy'), J.queueLabel(0, 1, 'godot')];
  out.differs = Q.painters.map(([a, b]) => J.painterDiffers(a, b));
  out.painterOf = Q.specs.map((s) => J.painterOfSpec(s));
  out.plans = Q.plans.map(([k, m]) => J.candidatePlan(k, m).map((p) => p.jk));
  out.refusals = Q.refusals.map(([k, m, c]) => J.candidateRefusal(J.candidatePlan(k, m), c));
  out.urls = Q.urls.map((u) => J.refUrl(u));
  out.words = Q.words.map(([jk, f, o]) => J.candidateWords(jk, f, o));
  out.tags = Q.tags.map(([k, v, d]) => J.sourceTag(k, v, d));
  out.flat = Q.flat.map(([spec, jk, specs]) => J.flatten(spec, jk, specs));
  out.rowKeys = Q.rowKeys.map(([m, isNew]) => J.lookRowKeys(m, isNew).map((k) => k.key));
  out.rerollModes = Q.rerollModes.map((m) => J.rerollModes(m));
  out.consts = { groups: J.GROUPS.map((g) => g[0]), lanes: J.LANE_ORDER, still: J.STILL_METHODS, min: J.MIN_CANDIDATES, cand: Object.fromEntries(Object.entries(J.CAND_FIELDS).map(([k, v]) => [k, v.map((f) => f.key)])), only: J.METHOD_ONLY };
  out.painterText = Q.painters2.map((p) => [L.painterText(p), L.painterShort(p)]);
  out.ownKeys = L.ownKeys({ recipe: Q.recipe });
  out.drafts = [L.isDraft({ ready: false, code: 'X-B' }, 'hero', 'x'), L.isDraft({ ready: true, code: 'X-A' }, 'hero', 'x'), L.isDraft({ ready: false, base: true, code: 'X-A' }, 'hero', 'x')];
  // the review fixes: held jobs and the ▲ / ▼ deltas, the held label, the cleared candidate fields, where a look's pictures show
  out.order2 = J.queueOrder(Q.queue2).map((x) => [x.job.id, x.pos, x.n, x.held, x.up, x.down]);
  out.heldLabels = Q.queue2.filter((j) => j.held).map((j) => J.heldLabel(j)).concat([J.heldLabel({ target: { kind: 'hero', id: 'mamy' } }), J.heldLabel({})]);
  out.cleared = Q.cleared.map(([jk, flat]) => J.withClearedFields(jk, flat));
  out.where = L.WHERE_SHOWN;
  process.stdout.write(JSON.stringify(out));
});
"""

FLOWS_RUNNER = r"""
// A small DOM for driving the Level Editor's page modules under Node (no jsdom here): elements, text, events,
// simple selectors, dialogs. Enough for U.el and the job form; not a browser.
function makeDom() {
  const listenersKey = Symbol('ls');
  class N {
    constructor() { this.childNodes = []; this.parentNode = null; }
    get children() { return this.childNodes.filter((n) => n.nodeType === 1); }
    get firstChild() { return this.childNodes[0] || null; }
    get lastChild() { return this.childNodes[this.childNodes.length - 1] || null; }
    appendChild(n) {
      if (n == null) return n;
      if (n.nodeType === 11) { for (const c of [...n.childNodes]) this.appendChild(c); return n; }
      if (n.parentNode) n.parentNode.removeChild(n);
      n.parentNode = this; this.childNodes.push(n); return n;
    }
    append(...ns) { for (const n of ns.flat()) if (n != null) this.appendChild(typeof n === 'string' || typeof n === 'number' ? doc.createTextNode(String(n)) : n); }
    removeChild(n) { const i = this.childNodes.indexOf(n); if (i >= 0) { this.childNodes.splice(i, 1); n.parentNode = null; } return n; }
    insertBefore(n, ref) {
      if (!ref) return this.appendChild(n);
      if (n.parentNode) n.parentNode.removeChild(n);
      const i = this.childNodes.indexOf(ref); this.childNodes.splice(i < 0 ? this.childNodes.length : i, 0, n); n.parentNode = this; return n;
    }
    replaceWith(n) { const p = this.parentNode; if (!p) return; if (n.parentNode) n.parentNode.removeChild(n); const i = p.childNodes.indexOf(this); p.childNodes.splice(i, 1, n); n.parentNode = p; this.parentNode = null; }
    remove() { if (this.parentNode) this.parentNode.removeChild(this); }
    get isConnected() { let n = this; while (n) { if (n === doc.body) return true; n = n.parentNode; } return false; }
    get textContent() { return this.nodeType === 3 ? this.data : this.childNodes.map((c) => c.textContent).join(''); }
    set textContent(v) { for (const c of this.childNodes) c.parentNode = null; this.childNodes = []; if (v !== '' && v != null) this.appendChild(doc.createTextNode(String(v))); }
    contains(n) { while (n) { if (n === this) return true; n = n.parentNode; } return false; }
  }
  class T extends N { constructor(d) { super(); this.nodeType = 3; this.data = String(d); } }
  class F extends N { constructor() { super(); this.nodeType = 11; } }
  class E extends N {
    constructor(tag) {
      super();
      this.nodeType = 1; this.tagName = String(tag).toUpperCase(); this.attrs = {}; this[listenersKey] = {}; this.dataset = {}; this.style = {};
      Object.assign(this, { id: '', title: '', hidden: false, disabled: false, type: '', name: '', value: '', checked: false, selected: false, open: false, placeholder: '', src: '', href: '', alt: '', min: '', max: '', step: '', spellcheck: true, accept: '', target: '', rel: '', loading: '', width: 0, height: 0, colspan: 1, scrollTop: 0, scrollHeight: 0, innerHTML: '' });
      if (this.tagName === 'DIALOG') this.open = false;
      if (this.tagName === 'INPUT') this.files = null;
    }
    setAttribute(k, v) { if (k === 'class') this.attrs.class = String(v); else { this.attrs[k] = String(v); if (k.startsWith('data-')) this.dataset[k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = String(v); } }
    getAttribute(k) { return k === 'class' ? (this.attrs.class || null) : (k in this.attrs ? this.attrs[k] : null); }
    get className() { return this.attrs.class || ''; }
    set className(v) { this.attrs.class = String(v); }
    get classList() {
      const self = this; const list = () => (self.attrs.class || '').split(/\s+/).filter(Boolean);
      return { add: (...c) => { self.attrs.class = Array.from(new Set(list().concat(c))).join(' '); }, remove: (...c) => { self.attrs.class = list().filter((x) => !c.includes(x)).join(' '); },
        toggle: (c, on) => { const has = list().includes(c); const want = on === undefined ? !has : !!on; if (want && !has) self.classList.add(c); if (!want && has) self.classList.remove(c); return want; }, contains: (c) => list().includes(c) };
    }
    get options() { return this.querySelectorAll('option'); }
    addEventListener(t, fn) { (this[listenersKey][t] = this[listenersKey][t] || []).push(fn); }
    removeEventListener(t, fn) { const l = this[listenersKey][t] || []; const i = l.indexOf(fn); if (i >= 0) l.splice(i, 1); }
    dispatch(t, extra) {
      let stopped = false; const ev = Object.assign({ type: t, target: this, currentTarget: this, stopPropagation() { stopped = true; }, preventDefault() {} }, extra || {});
      let n = this;
      while (n && !stopped) { for (const fn of [...((n[listenersKey] || {})[t] || [])]) fn.call(n, ev); if (t === 'click' || t === 'input') n = n.parentNode; else break; }
      return ev;
    }
    click() { if (this.disabled) return; if (this.tagName === 'INPUT' && (this.type === 'checkbox')) { this.checked = !this.checked; this.dispatch('change'); } if (this.tagName === 'INPUT' && this.type === 'radio') { this.checked = true; this.dispatch('change'); } this.dispatch('click'); }
    showModal() { this.open = true; }
    close() { if (!this.open && !this.isConnected) return; this.open = false; this.dispatch('close'); }
    focus() {} blur() {} scrollIntoView() {} select() {}
    matches(sel) { return matchCompound(this, sel.trim()); }
    closest(sel) { let n = this; while (n && n.nodeType === 1) { if (n.matches(sel)) return n; n = n.parentNode; } return null; }
    querySelectorAll(sel) { const out = []; const parts = sel.split(',').map((s) => s.trim()); const walk = (n) => { for (const c of n.children) { if (parts.some((p) => matchSel(c, p, this))) out.push(c); walk(c); } }; walk(this); return out; }
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
  }
  // selectors: compound parts (tag, .class, [attr], [attr="v"], :not(...) is not supported) joined by descendant spaces
  function attrOf(e, k) { if (k === 'class') return e.attrs.class; if (k.startsWith('data-')) { const dk = k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase()); return e.dataset[dk] != null ? String(e.dataset[dk]) : (k in e.attrs ? e.attrs[k] : undefined); } return k in e.attrs ? e.attrs[k] : (e[k] != null && e[k] !== '' && typeof e[k] !== 'object' ? String(e[k]) : undefined); }
  function matchCompound(e, s) {
    const re = /^([a-zA-Z0-9]*)((?:\.[\w-]+|\[[^\]]+\])*)$/; const m = re.exec(s); if (!m) throw new Error('selector not supported: ' + s);
    if (m[1] && e.tagName !== m[1].toUpperCase()) return false;
    const rest = m[2]; const toks = rest.match(/\.[\w-]+|\[[^\]]+\]/g) || [];
    for (const t of toks) {
      if (t[0] === '.') { if (!e.classList.contains(t.slice(1))) return false; continue; }
      const a = /^\[([\w-]+)(?:="([^"]*)")?\]$/.exec(t); if (!a) throw new Error('attr selector not supported: ' + t);
      const v = attrOf(e, a[1]); if (v === undefined) return false; if (a[2] !== undefined && v !== a[2]) return false;
    }
    return true;
  }
  function matchSel(e, sel, root) {
    const parts = sel.split(/\s+/).filter(Boolean);
    if (!matchCompound(e, parts[parts.length - 1])) return false;
    let n = e.parentNode, i = parts.length - 2;
    while (i >= 0 && n && n !== root.parentNode) { if (n.nodeType === 1 && matchCompound(n, parts[i])) i--; n = n.parentNode; }
    return i < 0;
  }
  const doc = {
    createElement: (t) => new E(t), createElementNS: (ns, t) => new E(t), createTextNode: (d) => new T(d), createDocumentFragment: () => new F(),
    body: null, hidden: false, readyState: 'complete', addEventListener() {}, activeElement: null,
    getElementById(id) { const walk = (n) => { for (const c of n.children) { if (c.id === id || c.attrs.id === id) return c; const r = walk(c); if (r) return r; } return null; }; return walk(doc.body); },
    querySelector(s) { return doc.body.querySelector(s); }, querySelectorAll(s) { return doc.body.querySelectorAll(s); },
  };
  doc.body = new E('body');
  return { document: doc, E, T };
}

// Drive the job form and the look grid through the DOM shim; argv[2] = tools/level_editor, argv[3] = the shim, stdin =
// {methods, specs}. Prints a JSON list of [name, ok, detail].
const fs = require('fs'), path = require('path');
const dir = path.dirname(process.argv[2]);
let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => { input += d; });
process.stdin.on('end', () => { main(JSON.parse(input)).catch((e) => { out.push(['harness crashed', false, String(e && e.stack || e)]); done(); }); });
const out = [];
const check = (name, ok, detail) => out.push([name, !!ok, detail === undefined ? '' : (typeof detail === 'string' ? detail : JSON.stringify(detail))]);
function done() { process.stdout.write(JSON.stringify(out), () => process.exit(0)); }

async function main(Q) {
  const { document } = makeDom();
  global.document = document;
  global.window = global;
  global.requestAnimationFrame = (fn) => setTimeout(fn, 0);
  global.CSS = { escape: (s) => s };
  global.confirm = () => true;
  const posts = [];
  const state = { jobs: [], defaults: Q.defaults || {}, heroLooks: Q.heroLooks.slice() };
  const json = (data, status) => ({ ok: (status || 200) < 400, status: status || 200, json: async () => data });
  global.fetch = async (url, opts) => {
    const u = String(url);
    const method = (opts && opts.method) || 'GET';
    const body = opts && opts.body && typeof opts.body === 'string' ? JSON.parse(opts.body) : null;
    if (method === 'POST') {
      posts.push({ url: u, body });
      if (u === '/api/jobs') return json({ ok: true, job: { id: 'j20261012-120000-' + String(posts.length).padStart(4, '0') } });
      if (/^\/api\/content\/[^/]+\/[^/]+\/look$/.test(u)) { state.heroLooks = state.heroLooks.filter((l) => l.code !== 'MAM-D').concat([{ code: 'MAM-D', ready: false, base: false, note: body.note, recipe: body.recipe }]); return json({ ok: true, code: 'MAM-D', looks: state.heroLooks }); }
      if (u === '/api/workflows/push') return json({ ok: false });
      return json({ ok: true });
    }
    if (u.startsWith('/api/jobs?since=')) return json({ rev: 1, jobs: state.jobs });
    if (u === '/api/jobs/specs') return json(Q.specs);
    if (u.startsWith('/api/jobs/defaults')) {
      const q = new URLSearchParams(u.split('?')[1]);
      const d = state.defaults[q.get('kind') + '|' + q.get('target')];
      return d ? json(d) : json({ ok: false, error: 'no defaults for ' + q.get('target') }, 400);
    }
    if (u === '/api/methods') return json(Q.methods);
    if (u === '/api/drivers') return json([{ name: 'run', kind: 'pose', views: ['front'], frames: 24 }, { name: 'beetle_walk', kind: 'depth', views: ['side'], frames: 12 }]);
    if (u === '/api/refs') return json({ '2d': [{ name: 'turn.png', url: '/dl/uploads/2d/turn.png', path: 'tools/dl/uploads/2d/turn.png' }], '3d': [] });
    if (u === '/api/heroes') return json([{ id: 'mamy', name: 'Mamy', kind: 'hero', looks: state.heroLooks }]);
    if (u === '/api/enemies') return json([{ id: 'goblin', name: 'Goblin', variants: Q.goblinLooks }]);
    if (/\/next_codes\?n=/.test(u)) { const n = Number(u.split('n=')[1]); return json({ ok: true, codes: (u.includes('/hero/') ? ['MAM-D', 'MAM-E', 'MAM-F'] : ['GOB-F', 'GOB-G']).slice(0, n) }); }
    if (u === '/api/content/hero/mamy') return json({ ok: true, json: { id: 'mamy', name: 'Mamy', art_prompt: 'a mime woman; standing straight', portrait_prompt: 'mock surprise', screen: 'blue' } });
    if (u === '/api/content/enemy/goblin') return json({ ok: true, json: { id: 'goblin', name: 'Goblin', art_prompt: 'a goblin' } });
    if (u === '/api/status') return json({});
    if (u === '/api/workflows') return json({ files: [] });
    return json({ ok: false, error: 'no route ' + u }, 404);
  };
  const statuses = [];
  global.App = { S: { tab: 'heroes', enemies: [] }, status: (t, k) => statuses.push([t, k]), toast() {}, switchTab(t) { global.App.S.tab = t; }, render() {}, refreshCreatures: async () => {} };
  const players = () => ({ el: document.createElement('div'), setStrip() {}, destroy() {}, url: '', destroyed: false });
  global.StripPlayer = { create: players, createSeq: players, openImage() {}, HERO_SIZE: 1.9, totalFrames: () => 0, MAX_ANIMATING: 12, LRU_MAX: 16 };
  global.U = new Function(fs.readFileSync(path.join(dir, 'util.js'), 'utf8') + '\nreturn U;')();
  const opened = [];
  global.Assets = { ensureSaved: async () => true, refreshRecord: async () => null, methodOf: () => 'hero_pose5', recipeEditor: () => null };
  global.LookGrid = require(path.join(dir, 'looks.js'));
  global.Jobs = require(path.join(dir, 'jobs.js'));
  const J = global.Jobs;
  const tick = (ms) => new Promise((r) => setTimeout(r, ms || 0));
  const dialogs = () => document.body.querySelectorAll('dialog').filter((d) => d.isConnected);
  const lastDialog = () => { const d = dialogs(); return d[d.length - 1]; };
  const lineOf = (dlg, label) => dlg.querySelectorAll('div.fieldline').find((l) => { const lb = l.querySelector('label'); return lb && lb.textContent === label; });
  const button = (root, text) => root.querySelectorAll('button').find((b) => b.textContent === text);
  const jobsPosted = (from) => posts.slice(from).filter((p) => p.url === '/api/jobs').map((p) => p.body);

  // 1. a new hero look: the counts start at 3 and 3, Queue posts the look and its two candidate jobs, the dialog closes
  let p0 = posts.length;
  await J.openForm('hero', 'mamy', { mode: 'look', method: 'hero_pose5' });
  await tick(5);
  let dlg = lastDialog();
  check('new hero look: the form opens', !!dlg);
  const badgeLine = lineOf(dlg, 'badge candidates'), titleLine = lineOf(dlg, 'title cut-out candidates');
  check('new hero look: badge and title cut-out counts shown', !!badgeLine && !!titleLine);
  check('new hero look: both counts default to 3', badgeLine && titleLine && badgeLine.querySelector('input').value === 3 && titleLine.querySelector('input').value === 3, [badgeLine && badgeLine.querySelector('input').value, titleLine && titleLine.querySelector('input').value]);
  const fh = (line) => (line && line.querySelector('div.fh') ? line.querySelector('div.fh').textContent : '');
  check('review: the counts say where the picks show (the badge on the hero sheet, the cut-out on the Painted title only)', fh(badgeLine).includes('the hero sheet, the results') && fh(titleLine).includes('Painted title only') && fh(titleLine).includes('the Live title, the default'), [fh(badgeLine).slice(-140), fh(titleLine).slice(-200)]);
  check('new hero look: no re-roll radios', !dlg.querySelectorAll('input').some((i) => i.type === 'radio' && i.name === 'reroll'));
  check('new hero look: the 2D / 3D reference rows are gone', !dlg.textContent.includes('+ Add a reference') && !dlg.textContent.includes('+ From the driver library'));
  check('new hero look: hero looks say they take no picture', dlg.textContent.includes('Hero looks paint from words'));
  check('new hero look: the front_from_picture fields are hidden', !lineOf(dlg, 'ref') && !lineOf(dlg, 'keep') && !lineOf(dlg, 'Reference picture'));
  // refuse fewer than 3
  const bi = badgeLine.querySelector('input'); bi.value = 2; bi.dispatch('change');
  button(dlg, 'Queue').click(); await tick(5);
  check('new hero look: Queue refuses 2 badge candidates', jobsPosted(p0).length === 0 && dlg.querySelector('span.err').textContent.includes('at least 3 badge candidates'), dlg.querySelector('span.err').textContent);
  bi.value = 3; bi.dispatch('change');
  button(dlg, 'Queue').click(); await tick(20);
  let sent = jobsPosted(p0);
  check('new hero look: Queue posts the look then its badge and title jobs', sent.length === 3 && sent[0].kind === 'look' && sent[1].kind === 'hero_badge' && sent[2].kind === 'hero_title', sent.map((s) => s.kind));
  check('new hero look: the candidates target the new code', sent.length === 3 && sent[1].target.code === 'MAM-D' && sent[2].target.code === 'MAM-D' && sent[0].target.code === 'MAM-D', sent.map((s) => s.target));
  check('new hero look: the candidates carry 3 seeds and no words', sent.length === 3 && sent[1].spec.seeds === 3 && sent[2].spec.seeds === 3 && !('character' in sent[1].spec) && !('prompt' in sent[1].spec) && !('ref' in sent[2].spec), sent.slice(1).map((s) => s.spec));
  check('new hero look: the dialog closes once the look is queued', !dlg.isConnected);

  // 2. a draft's Generate…: the source box, the painter from the recipe, its recipe posted with from and method
  p0 = posts.length;
  const draftRecipe = { method: 'hero_pose5', from: 'MAM-B', painter: { model: 'dev', steps: 32, turbo: true }, art_prompt: 'a mime woman' };
  await J.openForm('hero', 'mamy', { mode: 'look', code: 'MAM-D', draft: true, method: 'hero_pose5', recipe: draftRecipe, painter: draftRecipe.painter, from: 'MAM-B', note: 'from MAM-B' });
  await tick(5);
  dlg = lastDialog();
  check('draft: the head names the draft', dlg.querySelector('div.sp-modal-head').textContent.includes('generate the draft (made from MAM-B)'), dlg.querySelector('div.sp-modal-head').textContent);
  check('draft: the source box offers the reuse of MAM-B\'s paintings', dlg.textContent.includes('A draft made from MAM-B') && dlg.textContent.includes('reuse MAM-B\'s paintings'));
  check('draft: the counts are required (3 and 3)', lineOf(dlg, 'badge candidates') && lineOf(dlg, 'badge candidates').querySelector('input').value === 3 && lineOf(dlg, 'title cut-out candidates').querySelector('input').value === 3);
  button(dlg, 'Queue').click(); await tick(20);
  sent = jobsPosted(p0);
  check('draft: Queue posts the look for MAM-D and two candidate jobs', sent.length === 3 && sent[0].target.code === 'MAM-D', sent.map((s) => [s.kind, s.target.code]));
  check('draft: the look keeps its recipe (from, method), the painter goes to the model fields', sent[0] && sent[0].spec.recipe.from === 'MAM-B' && sent[0].spec.recipe.method === 'hero_pose5' && !sent[0].spec.recipe.painter && sent[0].spec.model === 'dev' && sent[0].spec.steps === 32, sent[0] && sent[0].spec);
  check('draft: the candidates run on the look\'s painter', sent[1] && sent[1].spec.model === 'dev' && sent[1].spec.steps === 32 && sent[2].spec.model === 'dev', sent.slice(1).map((s) => s.spec));
  check('draft: no re-roll goes out with a new look', sent[0] && !sent[0].spec.reroll);

  // 3. a re-roll: the radios, new seeds by default, no "one view" for a hero; a painter change selects "repaint the stills"
  p0 = posts.length;
  await J.openForm('hero', 'mamy', { mode: 'look', code: 'MAM-B', reroll: true, method: 'hero_pose5', recipe: { painter: { model: 'klein', steps: 0 } }, painter: { model: 'klein', steps: 0 } });
  await tick(5);
  dlg = lastDialog();
  const radios = () => dlg.querySelectorAll('input').filter((i) => i.type === 'radio' && i.name === 'reroll');
  const radioLabels = () => radios().map((r) => r.parentNode.textContent);
  check('re-roll: the radios show, "redo one view" only for gen_ctl', radios().length === 4 && !radioLabels().includes('redo one view'), radioLabels());
  check('re-roll: "new seeds" is selected', radios().find((r) => r.checked) && radios().find((r) => r.checked).parentNode.textContent === 'new seeds');
  check('re-roll: candidates are optional (0)', lineOf(dlg, 'badge candidates') && lineOf(dlg, 'badge candidates').querySelector('input').value === 0);
  const modelSel = lineOf(dlg, 'model') && lineOf(dlg, 'model').querySelector('select');
  check('re-roll: the Model settings show the model select', !!modelSel);
  if (modelSel) { modelSel.value = 'dev'; modelSel.dispatch('change'); }
  await tick(1);
  dlg = lastDialog();
  check('re-roll: a painter change selects "repaint the stills" with a note', radios().find((r) => r.checked) && radios().find((r) => r.checked).parentNode.textContent === 'repaint the stills' && dlg.textContent.includes('differ from the painter MAM-B was painted with'), radios().map((r) => [r.parentNode.textContent, r.checked]));
  button(dlg, 'Queue').click(); await tick(20);
  sent = jobsPosted(p0);
  check('re-roll: one look job with reroll {mode: stills}, no candidates', sent.length === 1 && sent[0].spec.reroll && sent[0].spec.reroll.mode === 'stills' && sent[0].target.code === 'MAM-B', sent.map((s) => [s.kind, s.spec.reroll]));

  // 4. a creature re-roll with gen_ctl: "redo one view" with its view
  await J.openForm('enemy', 'goblin', { mode: 'look', code: 'GOB-B', reroll: true, method: 'creature_ctl', recipe: {} });
  await tick(5);
  dlg = lastDialog();
  check('gen_ctl re-roll: "redo one view" is offered', radioLabels().includes('redo one view'), radioLabels());
  check('gen_ctl: look_ref is a picture field with Change… and Upload…', dlg.querySelectorAll('div.jpic').some((x) => !!button(x, 'Change…') && !!button(x, 'Upload…')));
  button(dlg, 'Cancel').click();

  // 5. a new creature look: icon candidates 3, posted as icon_cands with the code
  p0 = posts.length;
  await J.openForm('enemy', 'goblin', { mode: 'look', method: 'creature_free2' });
  await tick(5);
  dlg = lastDialog();
  check('new creature look: icon candidates 3', lineOf(dlg, 'icon candidates') && lineOf(dlg, 'icon candidates').querySelector('input').value === 3);
  check('new creature look: "paints from words" with the front-from-picture hint', dlg.textContent.includes('This method paints from words: to start from a picture'));
  button(dlg, 'Queue').click(); await tick(20);
  sent = jobsPosted(p0);
  check('new creature look: the look and an icon_cands job for GOB-F', sent.length === 2 && sent[1].kind === 'icon_cands' && sent[1].target.code === 'GOB-F' && sent[1].spec.seeds === 3, sent.map((s) => [s.kind, s.target.code, s.spec.seeds]));

  // 6. the badge form: the defaults fill the fields, tagged; Queue sends them with the code
  p0 = posts.length;
  await J.openForm('hero', 'mamy', { mode: 'badge', method: 'hero_badge', code: 'MAM-C' });
  await tick(5); await tick(5);
  dlg = lastDialog();
  const ch = lineOf(dlg, 'Character'), act = lineOf(dlg, 'Action'), rf = lineOf(dlg, 'Reference picture');
  check('badge: Character, Action and Reference picture shown', !!ch && !!act && !!rf);
  check('badge: the defaults are in the fields', ch && ch.querySelector('textarea').value === 'a mime woman' && act.querySelector('textarea').value === 'mock surprise' && rf.querySelector('input').value === 'tools/dl/ai_raw_anime/mamy_c_front.png', [ch && ch.querySelector('textarea').value, act && act.querySelector('textarea').value, rf && rf.querySelector('input').value]);
  check('badge: each says where it came from', ch && ch.querySelector('span.jsrc').textContent === 'from art_prompt without its pose clause' && rf.querySelector('span.jsrc').textContent.startsWith('from MAM-C'), [ch && ch.querySelector('span.jsrc').textContent, rf && rf.querySelector('span.jsrc').textContent]);
  check('badge: the reference has a thumbnail from ref_url', rf && rf.querySelector('img') && rf.querySelector('img').src === '/dl/ai_raw_anime/mamy_c_front.png');
  check('badge: no recipe fields that flatten would drop', !lineOf(dlg, 'portrait_prompt') && !lineOf(dlg, 'badge.head_width'));
  check('review: the badge form says where the pick shows', dlg.querySelector('p.jwhere') && dlg.querySelector('p.jwhere').textContent.startsWith('Where the pick shows: the badge is what the hero sheet, the results'), dlg.querySelector('p.jwhere') && dlg.querySelector('p.jwhere').textContent);
  const ta = act.querySelector('textarea'); ta.value = 'winking'; ta.dispatch('change');
  check('badge: an edit says it is yours', act.querySelector('span.jsrc').textContent.startsWith('yours'));
  button(dlg, 'Queue').click(); await tick(20);
  sent = jobsPosted(p0);
  check('badge: one hero_badge job for MAM-C with the fields', sent.length === 1 && sent[0].kind === 'hero_badge' && sent[0].target.code === 'MAM-C' && sent[0].spec.character === 'a mime woman' && sent[0].spec.prompt === 'winking' && sent[0].spec.ref === 'tools/dl/ai_raw_anime/mamy_c_front.png', sent[0]);

  // 7. the title form: pose, holds, camera, the extra reference
  await J.openForm('hero', 'mamy', { mode: 'title', method: 'hero_title' });
  await tick(5); await tick(5);
  dlg = lastDialog();
  check('title: Pose, Holds, Camera, Extra reference shown', ['Character', 'Pose', 'Holds', 'Camera', 'Reference picture', 'Extra reference', 'Extra reference words'].every((l) => !!lineOf(dlg, l)), ['Character', 'Pose', 'Holds', 'Camera', 'Reference picture', 'Extra reference', 'Extra reference words'].filter((l) => !lineOf(dlg, l)));
  check('title: the pose default filled', lineOf(dlg, 'Pose') && lineOf(dlg, 'Pose').querySelector('textarea').value === 'standing confidently in a heroic pose, full body');
  check('review: the cut-out form says it shows on the Painted title only', dlg.querySelector('p.jwhere') && dlg.querySelector('p.jwhere').textContent.startsWith('Where the pick shows: the cut-out shows on the Painted title only (Settings, debug mode: Main menu → Painted)'), dlg.querySelector('p.jwhere') && dlg.querySelector('p.jwhere').textContent);
  const det = dlg.querySelectorAll('details').find((d) => d.textContent.startsWith('Show the words'));
  if (det) { det.open = true; det.dispatch('toggle'); }
  check('title: the words put the character right after "this exact character"', det && det.querySelector('pre').textContent.includes('this exact character, a mime woman, for a mobile game'), det && det.querySelector('pre').textContent.slice(0, 400));
  button(dlg, 'Cancel').click();

  // 8. the Jobs tab: Up next first, numbered per lane in the worker's order (a resuming pick first), a held job after the
  // runnable ones of its lane, unnumbered and unmovable (review); ▲ / ▼ swap a card with its neighbour on screen
  state.jobs = [
    { id: 'j-1-aaaa', kind: 'look', state: 'running', lane: 'comfy', target: { kind: 'hero', id: 'mamy', code: 'MAM-B' }, title: 'running one' },
    { id: 'j-2-bbbb', kind: 'import', state: 'queued', lane: 'godot', target: {}, title: 'an import' },
    { id: 'j-3-cccc', kind: 'look', state: 'queued', lane: 'comfy', target: { kind: 'hero', id: 'mamy', code: 'MAM-D' }, title: 'second comfy' },
    { id: 'j-4-dddd', kind: 'hero_badge', state: 'queued', lane: 'comfy', front: true, target: { kind: 'hero', id: 'mamy', code: 'MAM-C' }, title: 'a picked badge' },
    { id: 'j-5-eeee', kind: 'look', state: 'done', lane: 'comfy', target: { kind: 'hero', id: 'mamy', code: 'MAM-A' }, title: 'done one', ended: '2026-10-12T10:00:00' },
    { id: 'j-6-ffff', kind: 'hero_title', state: 'waiting', lane: 'comfy', target: { kind: 'hero', id: 'mamy', code: 'MAM-C' }, title: 'waiting one', choices: [] },
    { id: 'j-7-abcd', kind: 'hero_title', state: 'queued', lane: 'comfy', held: true, target: { kind: 'hero', id: 'mamy', code: 'MAM-D' }, title: 'held cut-outs', spec: { ref: 'tools/dl/ai_raw_anime/mamy_d_front.png' } },
    { id: 'j-8-bcde', kind: 'icon_cands', state: 'queued', lane: 'comfy', target: { kind: 'enemy', id: 'goblin', code: 'GOB-F' }, title: 'goblin icons' },
  ];
  global.App.S.tab = 'jobs';
  const panel = document.createElement('div'); document.body.appendChild(panel);
  J.render(panel); await tick(10);
  const heads = panel.querySelectorAll('div.jobs-group').map((g) => g.querySelector('h2').textContent);
  check('jobs tab: Up next, Waiting, Running, Finished in that order', heads.length === 4 && heads[0].startsWith('Up next · 5') && heads[1].startsWith('Waiting for a pick') && heads[2].startsWith('Running') && heads[3].startsWith('Finished'), heads);
  check('review: the Up next header counts the held job in its lane', heads[0] === 'Up next · 5 (comfy 4, 1 waiting for a front · godot 1)', heads[0]);
  const upnext = panel.querySelectorAll('div.jobs-group')[0];
  const qcards = upnext.querySelectorAll('article.jcard');
  const titles = qcards.map((c) => c.querySelector('span.jtitle').textContent);
  check('jobs tab: comfy before godot, the picked job first in its lane, the held job after the runnable ones', JSON.stringify(titles) === JSON.stringify(['a picked badge', 'second comfy', 'goblin icons', 'held cut-outs', 'an import']), titles);
  const labels = qcards.map((c) => c.querySelectorAll('div.jcard-sub')[1].textContent);
  check('jobs tab: the runnable jobs numbered per lane in the worker\'s order', labels[0].includes('#1 of 3 in the comfy lane · next') && labels[1].includes('#2 of 3 in the comfy lane') && labels[2].includes('#3 of 3 in the comfy lane') && labels[4].includes('#1 of 1 in the godot lane · next'), labels);
  check('review: the held job says what it waits for, unnumbered', labels[3].startsWith('waiting for MAM-D\'s front') && !labels[3].includes('#') && qcards[3].querySelector('span.warn-text').title.includes('tools/dl/ai_raw_anime/mamy_d_front.png'), labels[3]);
  const arrows = qcards.map((c) => [button(c, '▲').disabled, button(c, '▼').disabled]);
  check('review: ▲ ▼ only where a move changes the order (the picked job stays first, the held job does not move)', JSON.stringify(arrows) === JSON.stringify([[true, true], [true, false], [false, true], [true, true], [true, true]]), arrows);
  let p8 = posts.length;
  button(qcards[1], '▼').click(); await tick(10);
  button(qcards[2], '▲').click(); await tick(10);
  const moves = posts.slice(p8).filter((p) => /\/move$/.test(p.url)).map((p) => [p.url, p.body.delta]);
  check('review: ▼ on "second comfy" and ▲ on "goblin icons" swap them with each other (one step in their group, past the picked and the held job)', JSON.stringify(moves) === JSON.stringify([['/api/jobs/j-3-cccc/move', 1], ['/api/jobs/j-8-bcde/move', -1]]), moves);
  global.App.S.tab = 'heroes';
  panel.remove();

  // 9. the look grid: a stub without a live look job is a draft with Generate…; Duplicate… posts a draft, no job
  state.jobs = [];
  await J.poll();
  const grid = document.createElement('div'); document.body.appendChild(grid);
  const doc = { kind: 'hero', id: 'mamy', data: { id: 'mamy', variants: { 'MAM-B': { sprite: 'mamy_sprite_b.png', recipe: { painter: { model: 'klein', steps: 0 }, art_prompt: 'a mime', stills: '', seed_offset: 7 } } } }, ui: { look: 'MAM-B' }, looks: Q.heroLooks };
  const rec = { kind: 'hero', id: 'mamy', name: 'Mamy', looks: Q.heroLooks.concat([{ code: 'MAM-D', ready: false, base: false, note: 'from MAM-B', recipe: { method: 'hero_pose5', from: 'MAM-B', painter: { model: 'dev', steps: 32 } } }]), variant: 'MAM-A', variant_base: 'MAM-A' };
  const selected = [];
  LookGrid.render(grid, rec, doc, { kind: 'hero', id: 'mamy', onSelect: (c) => selected.push(c), lookOp: async () => true });
  const cardOf = (code) => grid.querySelectorAll('article.lg-card').find((c) => c.dataset.code === code);
  const dcard = cardOf('MAM-D');
  check('grid: the stub without a job is a draft with Generate…', dcard && dcard.querySelector('span.chip.draft') && button(dcard, 'Generate…') && !button(dcard, 'Re-roll…') && !button(dcard, 'Badge candidates…'), dcard && dcard.textContent.slice(0, 200));
  const bcard = cardOf('MAM-B');
  check('grid: a hero look offers badge and cut-out candidates, not square icons', bcard && button(bcard, 'Badge candidates…') && button(bcard, 'Cut-out candidates…') && !button(bcard, 'Icon candidates…'));
  const acard = cardOf('MAM-A');
  const formCalls = [];
  const realOpen = J.openForm;
  J.openForm = async (k, i, o) => { formCalls.push([k, i, o]); return null; };
  button(bcard, 'Badge candidates…').click();
  button(acard, 'Badge candidates…').click();
  check('grid: a look\'s badge candidates target its code; the base look\'s the hero\'s own', formCalls.length === 2 && formCalls[0][2].mode === 'badge' && formCalls[0][2].code === 'MAM-B' && formCalls[1][2].code === undefined, formCalls.map((f) => f[2]));
  formCalls.length = 0;
  button(cardOf('MAM-D'), 'Generate…').click(); await tick(20);
  check('grid: Generate… opens the form for MAM-D as a draft with its recipe and painter', formCalls.length === 1 && formCalls[0][2].draft === true && formCalls[0][2].code === 'MAM-D' && formCalls[0][2].from === 'MAM-B' && formCalls[0][2].painter && formCalls[0][2].painter.model === 'dev' && !formCalls[0][2].reroll, formCalls.map((f) => f[2]));
  J.openForm = realOpen;
  p0 = posts.length;
  button(cardOf('MAM-B'), 'Duplicate…').click(); await tick(30);
  const dup = posts.slice(p0);
  check('grid: Duplicate… posts one draft (no job)', dup.length === 1 && dup[0].url === '/api/content/hero/mamy/look' && !dup.some((p) => p.url === '/api/jobs'), dup.map((p) => p.url));
  const dr = dup[0] && dup[0].body.recipe;
  check('grid: the draft\'s recipe: method set, painter kept, stills and seed_offset dropped, from = MAM-B', dr && dr.method === 'hero_pose5' && dr.from === 'MAM-B' && dr.painter && dr.painter.model === 'klein' && !('stills' in dr) && !('seed_offset' in dr) && dr.art_prompt === 'a mime', dr);
  check('grid: the draft is selected', doc.ui.look === 'MAM-D' && selected.includes('MAM-D'), [doc.ui.look, selected]);
  // a live look job turns the draft back into a stub without Generate…
  state.jobs = [{ id: 'j-9-9999', kind: 'look', state: 'queued', lane: 'comfy', target: { kind: 'hero', id: 'mamy', code: 'MAM-D' } }];
  await J.poll(); await tick(5);
  const dcard2 = grid.querySelectorAll('article.lg-card').find((c) => c.dataset.code === 'MAM-D');
  check('grid: with its job queued the draft is a stub with a queued chip', dcard2 && !button(dcard2, 'Generate…') && dcard2.querySelector('span.chip.stub') && dcard2.textContent.includes('queued'), dcard2 && dcard2.textContent.slice(0, 160));

  // 10. editing a queued badge job (review): a field cleared in the form goes out as '' so the server fills it again
  const bj = { id: 'j-10-1010', kind: 'hero_badge', method: 'hero_badge', state: 'queued', lane: 'comfy', target: { kind: 'hero', id: 'mamy', code: 'MAM-C' }, title: 'Mamy MAM-C · badge candidates ×3',
    spec: { method: 'hero_badge', seeds: 3, character: 'a mime woman', prompt: 'a custom wink', ref: 'tools/dl/uploads/2d/custom.png', variant: 'MAM-C', defaults_from: { character: 'art_prompt without its pose clause' } } };
  state.jobs = [bj];
  await J.poll();
  p0 = posts.length;
  await J.openForm('hero', 'mamy', { job: bj });
  await tick(5); await tick(5);
  dlg = lastDialog();
  const erf = lineOf(dlg, 'Reference picture'), eact = lineOf(dlg, 'Action'), ech = lineOf(dlg, 'Character');
  check('review edit: the form shows the job\'s own values', erf && eact && ech && erf.querySelector('input').value === 'tools/dl/uploads/2d/custom.png' && eact.querySelector('textarea').value === 'a custom wink' && ech.querySelector('textarea').value === 'a mime woman', [erf && erf.querySelector('input').value, eact && eact.querySelector('textarea').value]);
  if (erf && eact) {
    const eri = erf.querySelector('input'); eri.value = ''; eri.dispatch('change');
    const eat = eact.querySelector('textarea'); eat.value = ''; eat.dispatch('change');
    check('review edit: the cleared fields say the server fills them again', erf.querySelector('span.jsrc').textContent.startsWith('empty: the server fills it from MAM-C\'s front still') && eact.querySelector('span.jsrc').textContent.startsWith('empty: the server fills it from portrait_prompt'), [erf.querySelector('span.jsrc').textContent, eact.querySelector('span.jsrc').textContent]);
  }
  button(dlg, 'Save changes').click(); await tick(20);
  const eposts = posts.slice(p0).filter((p) => p.url === '/api/jobs/j-10-1010');
  const es = eposts.length ? eposts[0].body.spec : {};
  check('review edit: Save changes posts the cleared reference and action as \'\' and the character as it was', eposts.length === 1 && es.ref === '' && es.prompt === '' && es.character === 'a mime woman' && es.seeds === 3, es);
  out.push(['data:edit_badge', true, JSON.stringify({ posted: es, stored: bj.spec, target: bj.target })]);

  // 11. the look grid draws itself again only for its own asset's jobs, never under the open edit or confirm box, and the
  // edit box keeps what was typed through any redraw (review)
  state.jobs = [];
  await J.poll(); await tick(5);
  LookGrid.select('MAM-B', 'hero', 'mamy');
  const before = cardOf('MAM-B');
  state.jobs = [{ id: 'j-11-0001', kind: 'look', state: 'queued', lane: 'comfy', target: { kind: 'enemy', id: 'goblin', code: 'GOB-F' } }];
  await J.poll(); await tick(5);
  check('review grid: a job of another asset leaves the grid alone', !!before && cardOf('MAM-B') === before);
  state.jobs = state.jobs.concat([{ id: 'j-11-0002', kind: 'hero_badge', state: 'queued', lane: 'comfy', target: { kind: 'hero', id: 'mamy', code: 'MAM-B' } }]);
  await J.poll(); await tick(5);
  const after = cardOf('MAM-B');
  check('review grid: a job of this asset draws the grid again with the job\'s chip', !!after && after !== before && after.textContent.includes('queued · badges'), after && after.textContent.slice(0, 160));
  button(cardOf('MAM-B'), 'Edit note / recipe').click(); await tick(1);
  let ebox = grid.querySelector('div.lg-edit');
  const enote = ebox && ebox.querySelector('input'), erec = ebox && ebox.querySelector('textarea');
  check('review grid: Edit note / recipe opens its box', !!enote && !!erec);
  if (enote && erec) {
    enote.value = 'typed note'; enote.dispatch('input');
    erec.value = '{"art_prompt": "typed words"}'; erec.dispatch('input');
    state.jobs = state.jobs.map((j) => (j.id === 'j-11-0002' ? Object.assign({}, j, { state: 'running' }) : j));
    await J.poll(); await tick(5);
    check('review grid: a job of this asset changing state leaves the open edit box alone', grid.querySelector('div.lg-edit input') === enote && enote.value === 'typed note' && erec.isConnected);
    LookGrid.select('MAM-B', 'hero', 'mamy');   // a redraw all the same (this asset's own job landing redraws the editor pane)
    ebox = grid.querySelector('div.lg-edit');
    check('review grid: the edit box keeps the typed note and recipe through a redraw', !!ebox && ebox.querySelector('input') !== enote && ebox.querySelector('input').value === 'typed note' && ebox.querySelector('textarea').value === '{"art_prompt": "typed words"}', ebox && [ebox.querySelector('input').value, ebox.querySelector('textarea').value]);
    if (ebox) button(ebox, 'Cancel').click();
    await tick(1);
    check('review grid: closing the box draws the grid with the jobs as they are now', !grid.querySelector('div.lg-edit') && cardOf('MAM-B').textContent.includes('running · badges'), cardOf('MAM-B') && cardOf('MAM-B').textContent.slice(0, 160));
  }
  button(cardOf('MAM-B'), 'Remove').click(); await tick(1);
  const cbox = grid.querySelector('div.lg-confirm');
  state.jobs = state.jobs.filter((j) => j.id !== 'j-11-0002');
  await J.poll(); await tick(5);
  check('review grid: a job change leaves the open confirm box alone', !!cbox && grid.querySelector('div.lg-confirm') === cbox && cbox.isConnected);
  if (cbox) button(cbox, 'Cancel').click();
  await tick(1);
  check('review grid: once the confirm box closes the grid shows the job gone', !grid.querySelector('div.lg-confirm') && !cardOf('MAM-B').textContent.includes('badges'), cardOf('MAM-B') && cardOf('MAM-B').textContent.slice(0, 160));
  const fbox = grid.querySelector('input.lg-filter');
  const proto = Object.getPrototypeOf(fbox);
  const realFocus = proto.focus;
  proto.focus = function () { document.activeElement = this; };
  proto.setSelectionRange = function (a, b) { this.selectionStart = a; this.selectionEnd = b; };
  document.activeElement = fbox; fbox.selectionStart = 2; fbox.selectionEnd = 3;
  state.jobs = state.jobs.concat([{ id: 'j-11-0003', kind: 'hero_title', state: 'queued', lane: 'comfy', target: { kind: 'hero', id: 'mamy', code: 'MAM-B' } }]);
  await J.poll(); await tick(5);
  const fbox2 = grid.querySelector('input.lg-filter');
  check('review grid: the filter box keeps its focus and caret through a redraw', !!fbox2 && fbox2 !== fbox && document.activeElement === fbox2 && fbox2.selectionStart === 2 && fbox2.selectionEnd === 3, [fbox2 === fbox, fbox2 && fbox2.selectionStart]);
  proto.focus = realFocus; delete proto.setSelectionRange; document.activeElement = null;

  // 12. the look's facts and its candidate buttons say where the game shows the badge and the cut-out (review)
  const whereEl = grid.querySelector('div.lg-where');
  check('review grid: the look\'s facts say where the badge and the cut-out show', !!whereEl && whereEl.textContent.includes('the hero sheet, the results') && whereEl.textContent.includes('Painted title only') && whereEl.textContent.includes('the Live title, the default'), whereEl && whereEl.textContent);
  const bcb = button(cardOf('MAM-B'), 'Badge candidates…'), ccb = button(cardOf('MAM-B'), 'Cut-out candidates…');
  check('review grid: the badge and cut-out candidate buttons say where the pick shows', !!bcb && bcb.title.includes('the hero sheet, the results') && !!ccb && ccb.title.includes('Painted title only'), [bcb && bcb.title, ccb && ccb.title]);
  done();
}
"""


# ---------------------------------------------------------------- pass 68 review fixes (the page lane)

# A comfy lane in the server's list order: A, F1 (a resuming pick), H1 (held: a look's candidates waiting for its front),
# B, C, F2 (resuming), H2 (held), D; a godot lane G1, G2 woven in. The worker takes F1, F2, A, B, C, D and then the held.
# H1 and H2 are held the server's way (jobs._waits_for_look): candidate jobs whose reference is not on disk while a look
# job of their target is live (LIVE_LOOKS, running and waiting, so not in the queue).
NO_REF = "tools/dl/ai_raw_anime/__selftest_v_no_such_front__.png"
QUEUE2 = [
    {"id": "A", "lane": "comfy", "target": {"kind": "enemy", "id": "goblin", "code": "GOB-F"}},
    {"id": "G1", "lane": "godot"},
    {"id": "F1", "lane": "comfy", "front": True},
    {"id": "H1", "lane": "comfy", "held": True, "kind": "hero_title", "spec": {"ref": NO_REF}, "target": {"kind": "hero", "id": "mamy", "code": "MAM-D"}},
    {"id": "B", "lane": "comfy"},
    {"id": "G2", "lane": "godot"},
    {"id": "C", "lane": "comfy"},
    {"id": "F2", "lane": "comfy", "front": True},
    {"id": "H2", "lane": "comfy", "held": True, "kind": "icon_cands", "spec": {"ref": NO_REF}, "target": {"kind": "enemy", "id": "goblin", "code": "GOB-F"}},
    {"id": "D", "lane": "comfy"},
]
LIVE_LOOKS = [{"id": "L1", "kind": "look", "state": "running", "lane": "comfy", "target": {"kind": "hero", "id": "mamy", "code": "MAM-D"}},
              {"id": "L2", "kind": "look", "state": "waiting", "lane": "comfy", "target": {"kind": "enemy", "id": "goblin", "code": "GOB-F"}}]


def worker_order(jobs_mod, lane):
    """The order jobs.py's _take_next takes one lane's queued jobs, its own hold rule (_waits_for_look) deciding: the
    runnable resuming picks (front) in list order, then the other runnable ones in list order, the held ones last."""
    q = [j for j in jobs_mod._state["jobs"] if j.get("state") == "queued" and j.get("lane") == lane]
    run = [j for j in q if not jobs_mod._waits_for_look(j)]
    return [j["id"] for j in run if j.get("front")] + [j["id"] for j in run if not j.get("front")] + [j["id"] for j in q if j not in run]


def move_checks(check, order2):
    """The page's ▲ / ▼ deltas (queueOrder's up / down) run through the server's own jobs.move on QUEUE2 held in memory
    (jobs._state swapped, _save and _writable stubbed, all put back after): every enabled arrow must swap its card with
    the neighbour shown above or below it in the order the worker takes the jobs; the server holds what the page marks."""
    import jobs
    lane_of = {j["id"]: j.get("lane", "") for j in QUEUE2}
    shown = {}
    for row in order2:
        shown.setdefault(lane_of[row[0]], []).append(row[0])
    fresh = lambda: {"rev": 0, "jobs": [dict(j, state="queued") for j in QUEUE2] + [dict(x) for x in LIVE_LOOKS]}  # noqa: E731
    saved = (jobs._state, jobs._save, jobs._writable)
    tried, bad, marks = 0, [], None
    try:
        jobs._save = lambda: None
        jobs._writable = lambda: None
        jobs._state = fresh()
        marks = {j["id"]: bool(jobs._waits_for_look(j)) for j in jobs._state["jobs"] if j["state"] == "queued"}
        for jid, _pos, _n, _held, up, down in order2:
            for delta, step in ((up, -1), (down, 1)):
                if not delta:
                    continue
                jobs._state = fresh()
                jobs.move(jid, delta)
                want = list(shown[lane_of[jid]])
                i = want.index(jid)
                want[i], want[i + step] = want[i + step], want[i]
                got = worker_order(jobs, lane_of[jid])
                tried += 1
                if got != want:
                    bad.append("%s %+d: %s, wanted %s" % (jid, delta, got, want))
    finally:
        jobs._state, jobs._save, jobs._writable = saved
    check(marks == {j["id"]: bool(j.get("held")) for j in QUEUE2}, "V68 review: the server holds exactly the jobs the page shows as held (jobs._waits_for_look): %s" % marks)
    check(tried == 10 and not bad, "V68 review: every enabled arrow, sent to the server's jobs.move, swaps the card with its neighbour on screen (%d moves; wrong: %s)" % (tried, bad))


def review_pure_checks(check, res):
    o = res.get("order2")
    check(o == [["F1", 0, 6, False, 0, 1], ["F2", 1, 6, False, -1, 0], ["A", 2, 6, False, 0, 1], ["B", 3, 6, False, -1, 1], ["C", 4, 6, False, -1, 1], ["D", 5, 6, False, -1, 0],
                ["H1", -1, 6, True, 0, 0], ["H2", -1, 6, True, 0, 0], ["G1", 0, 2, False, 0, 1], ["G2", 1, 2, False, -1, 0]],
          "V68 review: Up next numbers the runnable jobs in the worker's order (resuming picks first), the held ones after them unnumbered and unmovable; ▲ / ▼ step within a group and are off at its ends: %s" % o)
    check(res.get("heldLabels") == ["waiting for MAM-D's front", "waiting for GOB-F's front", "waiting for mamy's front", "waiting for its look's front"], "V68 review: a held job says whose front it waits for: %s" % res.get("heldLabels"))
    c = res.get("cleared") or []
    check(len(c) == 4 and c[0] == {"character": "a mime", "seeds": 3, "prompt": "", "ref": ""}, "V68 review: an edited badge job sends '' for its cleared Action and Reference picture (the server fills them again): %s" % (c[:1],))
    check(len(c) == 4 and c[1] == {"character": "", "pose": "p", "holds": "", "camera": "", "ref": "", "extra_ref": "", "extra_words": ""} and c[2] == {"subject": "a goblin", "screen": "", "ref": "", "file": ""},
          "V68 review: every empty title and icon field goes out as '', a typed one as it is: %s" % (c[1:3],))
    check(len(c) == 4 and c[3] == {"method": "hero_pose5", "recipe": {}}, "V68 review: a look job's edit gets no candidate keys: %s" % (c[3:],))
    w = res.get("where") or {}
    check("hero sheet" in w.get("badge", "") and "results" in w.get("badge", "") and "arena" in w.get("badge", ""), "V68 review: the badge is said to show on the hero sheet, the results and the arena: %s" % w.get("badge"))
    check("Painted title only" in w.get("cutout", "") and "Main menu" in w.get("cutout", "") and "Live title, the default" in w.get("cutout", ""), "V68 review: the cut-out is said to show on the Painted title only, the default Live title drawing the strip: %s" % w.get("cutout"))
    move_checks(check, o or [])


def edit_refill_checks(check, posted, stored, target, defaults):
    """The badge job the flows edited, through the server's own steps of jobs.edit: the posted spec merged over the stored
    one, jobs.validate_spec, jobs._seed_candidates (candidate_defaults stubbed with the flow's defaults, put back after).
    The '' of a cleared field brings the default back; without it the old value would stay (the review's bug)."""
    import jobs
    saved = jobs.candidate_defaults
    try:
        jobs.candidate_defaults = lambda kind, t: {"fields": dict(defaults["fields"]), "sources": dict(defaults["sources"]), "ref_url": None, "ref_exists": True}

        def server_edit(spec):
            merged = json.loads(json.dumps(stored))
            merged.update(spec)
            new = jobs.validate_spec("hero_badge", merged)
            jobs._seed_candidates("hero_badge", target, new)
            return new
        new = server_edit(posted)
        check(new.get("ref") == defaults["fields"]["ref"] and new.get("prompt") == defaults["fields"]["prompt"] and new.get("character") == stored["character"],
              "V68 review: a badge job edited with its reference and action cleared comes back with the defaults (ref %s, prompt %s), its character kept" % (new.get("ref"), new.get("prompt")))
        old = server_edit({k: v for k, v in posted.items() if v != ""})
        check(old.get("ref") == stored["ref"] and old.get("prompt") == stored["prompt"], "V68 review: without the '' the cleared fields would have kept their old values (the bug): %s" % ([old.get("ref"), old.get("prompt")],))
    finally:
        jobs.candidate_defaults = saved


def contract_specs():
    """jobs.py's SPECS with the fields the pass-68 contract adds (D3 look.reroll; D6 the badge and title fields), where
    the server does not carry them yet: the page is checked against the contract."""
    import jobs
    specs = json.loads(json.dumps(jobs.SPECS))

    def f(t, d=None):
        return {"type": t, "default": d, "required": False, "help": ""}
    specs["look"]["fields"].setdefault("reroll", f("json", {}))
    for k in ("character", "prompt", "ref", "variant"):
        specs["hero_badge"]["fields"].setdefault(k, f("str", ""))
    for k in ("character", "pose", "holds", "camera", "extra_ref", "extra_words", "ref", "variant"):
        specs["hero_title"]["fields"].setdefault(k, f("str", ""))
    for k in ("subject", "ref", "screen", "file"):
        specs["icon_cands"]["fields"].setdefault(k, f("str", ""))
    return specs


def pass68_checks(check, run_node, node):
    read = lambda name: open(os.path.join(HERE, name), "r", encoding="utf-8").read()  # noqa: E731
    jb, lg, asrc, css, st, af = read("jobs.js"), read("looks.js"), read("assets.js"), read("preview.css"), read("style.css"), read("assets_fields.js")
    # the routes and the pieces, read from the source
    check("`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/look`, { note, recipe }" in lg and "async function duplicateDraft" in lg and "async function generate" in lg,
          "V68: Duplicate… posts a draft (add_look {note, recipe}) and Generate… opens the form; no job from Duplicate")
    check("Assets.ensureSaved(doc," in lg and "async function ensureSaved(doc, why)" in asrc and "ensureSaved, refreshRecord" in asrc, "V68: Duplicate… and Generate… save (or refuse) a dirty document first")
    check("/api/jobs/defaults?kind=" in jb and "function loadDefaults" in jb and "function pictureControl" in jb and "function pickPicture" in jb, "V68: the candidate forms read GET /api/jobs/defaults and show the reference as a picture with the library and Upload")
    check("mode: 'badge', method: 'hero_badge'" in lg and "method: 'hero_badge', mode: 'badge'" in asrc and "round ? el('button'" in asrc, "V68: a hero's icon buttons open badge candidates (looks.js, assets.js)")
    check(".chip.draft" in css and ".jpic-thumb" in css and ".jsrc" in css and ".rnote.draft" in st, "V68: preview.css styles the draft chip, the picture field and the source tags; style.css the draft note")
    check("key: 'appearance'" in af and af.count("key: 'appearance'") == 2, "V68: the hero and the creature forms carry `appearance` (the candidates' Character)")
    check("'+ Add a reference'" not in jb and "'+ From the driver library'" not in jb, "V68: the 2D / 3D reference rows (read by no tool) are gone from the form")
    # the review fixes, read from the source (the flows below drive them)
    check("withClearedFields(job.kind, flatten(one, job.kind, specs))" in jb, "V68 review: an edit of a candidate job posts its cleared fields as '' (withClearedFields)")
    check("if (s.edit || s.confirm) return false;" in lg and "jobsSig(current.kind, current.id) === s.jobSig" in lg and "s.jobSig = jobsSig(kind, id);" in lg,
          "V68 review: the look grid redraws for its own asset's jobs only, never under the edit or confirm box")
    check("e.noteDraft" in lg and "e.recipeText" in lg, "V68 review: the edit box keeps what was typed (noteDraft, recipeText) apart from what Save compares with")
    check("x.held" in jb and "heldLabel(j)" in jb and "{ delta: up }" in jb and "{ delta: down }" in jb, "V68 review: Up next shows held jobs and moves a card by its delta to the neighbour on screen")
    check("WHERE_SHOWN" in lg and "whereShown('cutout')" in jb and "whereShown('badge')" in jb and "shownWhere('cutout')" in asrc and "shownWhere('badge')" in asrc and "lg-where" in lg,
          "V68 review: the look's facts, the candidate forms and help, and assets.js's badge and cut-out buttons say where the game shows each picture")
    if not node:
        print("V68: node not found: the pass-68 JS checks skipped")
        return
    # the pure helpers
    q = {
        "queue": [{"id": "a", "lane": "local"}, {"id": "b", "lane": "comfy"}, {"id": "c", "lane": "godot"}, {"id": "d", "lane": "comfy", "front": True}, {"id": "e", "lane": "comfy"}, {"id": "f", "lane": "zzz"}],
        "painters": [[{"model": "klein", "steps": 0}, {"model": "klein"}], [{"model": "dev", "steps": 32, "turbo": True}, {"model": "dev", "steps": 32, "guidance": 0, "turbo": True, "stills": "reused", "reused": ["x"]}],
                     [{"model": "dev"}, {"model": "klein"}], [{"model": "klein", "steps": 4}, {"model": "klein", "steps": 0}], [{"model": "dev", "turbo": False}, {"model": "dev", "turbo": True}]],
        "specs": [{"job": {"model": "dev", "steps": 32}, "flags": {}}, {"job": {}, "flags": {"dev": True}}, {"job": {"model": "klein", "steps": 8}, "flags": {"dev": True}}],
        "plans": [["hero", "hero_pose5"], ["hero", "hero_fit"], ["enemy", "creature_pose2"], ["boss", "creature_ctl"], ["enemy", "recolour"], ["enemy", "front_from_picture"], ["weapon", "icon_cands"]],
        "refusals": [["hero", "hero_pose5", {"icon_candidates": 3, "cutout_candidates": 3}], ["hero", "hero_pose5", {"icon_candidates": 2, "cutout_candidates": 3}], ["enemy", "creature_free2", {"icon_candidates": 0}], ["enemy", "recolour", {}]],
        "urls": ["tools/dl/uploads/2d/x.png", "ai_raw_anime/mamy_c_front.png", "D:/_projects/88fits/tools/dl/ai_raw_anime/a b.png", "_REFERENCES/2d/w.webp", "/dl/uploads/2d/y.png", "C:/elsewhere/y.png", "game/art/ui/wanted/hero_x.png", ""],
        "words": [["hero_badge", {"character": "a mime woman", "prompt": "mock surprise"}, {"screen": "blue"}], ["hero_badge", {}, {"screen": "blue"}],
                  ["hero_title", {"character": "a mime woman", "pose": "miming a wall", "holds": "nothing", "camera": "from the front", "extra_ref": "x.png", "extra_words": "a beret."}, {"screen": "blue"}],
                  ["icon_cands", {"subject": "a goblin", "ref": "x.png"}, {"creature": True}], ["icon_cands", {"subject": "a sword"}, {"creature": False}],
                  ["icon_cands", {"subject": "a sword.", "ref": "sword_ref.png"}, {"creature": False}], ["hero_badge", {"character": "a mime woman;", "prompt": "a wink"}, {"screen": "blue"}],
                  ["hero_title", {"character": "a mime", "pose": "p", "holds": "h", "camera": "c", "extra_words": "a beret"}, {"screen": "blue"}]],
        "tags": [["character", "abc", {"fields": {"character": "abc"}, "sources": {"character": "art_prompt without its pose clause"}}], ["character", "xyz", {"fields": {"character": "abc"}, "sources": {}}], ["ref", "", {"fields": {"ref": "r.png"}, "sources": {"ref": "MAM-C's front still"}}], ["ref", "", {"fields": {}, "sources": {}}]],
        "flat": [[{"method": "hero_pose5", "recipe": {}, "flags": {}, "counts": {"seeds": 3}, "job": {"model": "dev"}, "reroll": {"mode": "view", "view": "fd"}}, "look", {"look": {"fields": {"method": {}, "recipe": {}, "reroll": {}, "model": {}, "seeds": {}}}}],
                 [{"method": "front_from_picture", "recipe": {"stills": "wwa"}, "flags": {}, "counts": {}, "job": {"ref": "tools/dl/uploads/2d/w.png"}, "reroll": {"mode": ""}}, "look", None],
                 [{"method": "hero_pose5", "recipe": {}, "flags": {}, "counts": {}, "job": {}, "reroll": {"mode": "seeds"}}, "look", {"look": {"fields": {"method": {}, "recipe": {}}}}]],
        "rowKeys": [["hero_pose5", True], ["hero_pose5", False], ["creature_ctl", True], ["recolour", True], ["creature_free8", True]],
        "rerollModes": ["hero_pose5", "creature_pose2", "hero_fit", "creature_ctl", "creature_proc", "recolour", "front_from_picture"],
        "painters2": [{"model": "dev", "steps": 32, "turbo": True, "stills": "reused"}, {"model": "klein", "steps": 0, "stills": "3 of 12 painted", "reused": ["a", "b", "c", "d", "e", "f", "g", "h", "i"]}, {"model": "klein"}],
        "recipe": {"painter": {}, "method": "hero_pose5", "from": "MAM-B", "seed_offset": 3, "art_prompt": "a", "stills": "c"},
        # the review fixes: a comfy lane with two resuming picks and two held candidate jobs among the others, a godot lane
        "queue2": QUEUE2,
        "cleared": [["hero_badge", {"character": "a mime", "seeds": 3}], ["hero_title", {"pose": "p", "holds": None}], ["icon_cands", {"subject": "a goblin", "screen": None}],
                    ["look", {"method": "hero_pose5", "recipe": {}}]],
    }
    res = run_node(q, PURE_RUNNER)
    if not res:
        check(False, "V68: jobs.js and looks.js load under Node")
    else:
        check(res["order"] == [["d", 0, 3], ["b", 1, 3], ["e", 2, 3], ["c", 0, 1], ["a", 0, 1], ["f", 0, 1]], "V68: Up next runs comfy, godot, local, then other lanes; a resuming pick first; the server's order kept within a lane: %s" % res["order"])
        check(res["labels"] == ["#1 of 3 in the comfy lane · next", "#3 of 3 in the comfy lane", "#1 of 1 in the godot lane · next"], "V68: the cards are numbered per lane: %s" % res["labels"])
        check(res["differs"] == [False, False, True, True, True], "V68: painterDiffers compares the model, the passes, dev's guidance and Turbo, never the bookkeeping: %s" % res["differs"])
        check(res["painterOf"] == [{"model": "dev", "steps": 32, "guidance": 0, "turbo": True}, {"model": "dev", "steps": 0, "guidance": 0, "turbo": True}, {"model": "klein", "steps": 8}], "V68: the form's painter follows the model select, else the dev flag: %s" % res["painterOf"])
        check(res["plans"] == [["hero_badge", "hero_title"], ["hero_badge", "hero_title"], ["icon_cands"], ["icon_cands"], [], [], []], "V68: a new hero look comes with badge and title cut-out candidates, a creature with icon candidates, a recolour and a front from a picture with none: %s" % res["plans"])
        r = res["refusals"]
        check(r[0] == "" and "at least 3 badge candidates" in r[1] and "at least 3 icon candidates" in r[2] and r[3] == "", "V68: Queue refuses fewer than 3 candidates on a new look: %s" % r)
        check(res["urls"] == ["/dl/uploads/2d/x.png", "/dl/ai_raw_anime/mamy_c_front.png", "/dl/ai_raw_anime/a%20b.png", "", "/dl/uploads/2d/y.png", "", "", ""], "V68: a picture path shows through /dl/ when it lies in tools/dl, else no preview: %s" % res["urls"])
        w = res["words"]
        check(w[0].startswith("A close-up portrait of this exact character for a mobile game avatar icon: a mime woman, only the head and shoulders") and ", mock surprise, facing the viewer" in w[0] and "bright blue (#0000FF)" in w[0], "V68: the badge words put the character first and the action after: %s" % w[0][:160])
        check(w[1].startswith("A close-up portrait of this exact character for a mobile game avatar icon: only the head") and "smiling at the viewer" in w[1], "V68: no character, no words for it; the action falls back to smiling")
        check(w[2].startswith("A full-body character illustration of this exact character, a mime woman, for a mobile game's hero select screen: miming a wall, from the front,") and "nothing. a beret. Keep the same face" in w[2] and "anime art style" in w[2], "V68: the title words put the character right after \"this exact character\": %s" % w[2][:200])
        check(w[3].startswith("The reference image shows this exact creature: keep its shape, colors and proportions. a goblin. Mobile game item icon") and w[3].endswith("no watermark.") and "green (#00FF00)" in w[3], "V68: a creature's icon with a picture begins with the reference sentence")
        check(w[4].startswith("a sword. Mobile game item icon"), "V68: an item's icon is its subject and the icon style")
        check(w[5].startswith("Copy this exact object from the reference image: its silhouette, proportions, parts and colours, seen from the same angle. a sword. Mobile"), "V68: an item's icon with a picture leads with the COPY sentence, the subject's full stop dropped (gen_icon_cands.icon_words): %s" % w[5][:160])
        check("avatar icon: a mime woman, only the head" in w[6] and "a wink, facing the viewer" in w[6], "V68: the character's trailing punctuation is cleaned as the tools do: %s" % w[6][:120])
        check("h. a beret Keep the same face" in w[7], "V68: the title's extra words go in even without an extra picture (gen_title_heroes.title_inputs): %s" % w[7][-260:-150])
        t = res["tags"]
        check(t[0] == "from art_prompt without its pose clause" and t[1].startswith("yours") and t[2].startswith("empty: the server fills it from MAM-C's front still") and t[3].startswith("empty: the tool"), "V68: each candidate field says where its value came from: %s" % t)
        fl = res["flat"]
        check(fl[0].get("reroll") == {"mode": "view", "view": "fd"} and fl[0].get("model") == "dev" and fl[0].get("seeds") == 3, "V68: the re-roll goes out as spec.reroll {mode, view} (a SPECS field): %s" % fl[0])
        check(fl[1].get("stills") == "wwa" and fl[1].get("ref") == "tools/dl/uploads/2d/w.png" and "reroll" not in fl[1], "V68: a front from a picture sends its stills slug as the job field jobs.py reads: %s" % fl[1])
        check("reroll" not in fl[2], "V68: a server without spec.reroll gets none (flatten keeps SPECS fields only): %s" % fl[2])
        rk = res["rowKeys"]
        check(rk[0] == ["art_prompt", "motion", "anim_negative", "seed_offset", "screen"] and "seed_offset" not in rk[1] and rk[2][:3] == ["prompt", "keep", "detail"] and rk[3] == [] and "directions" in rk[4], "V68: a look row offers the keys its method's tool reads (art_prompt for gen_art, prompt / keep / detail for gen_ctl, seed_offset on a new look): %s" % rk)
        check(res["rerollModes"] == [["seeds", "clips", "stills"], ["seeds", "clips", "stills"], ["clips"], ["clips", "view"], ["seeds", "stills"], [], []],
              "V68: the form offers only the re-roll modes jobs.py's _apply_reroll accepts per method: %s" % res["rerollModes"])
        c = res["consts"]
        check(c["groups"] == ["queued", "waiting", "running", "finished"] and c["lanes"] == ["comfy", "godot", "local"], "V68: the Jobs tab draws Up next first: %s" % c["groups"])
        check("hero_pose5" in c["still"] and c["min"] == 3, "V68: hero_pose5 joins the slug methods; the minimum is 3")
        check(c["cand"] == {"hero_badge": ["character", "prompt", "ref"], "hero_title": ["character", "pose", "holds", "camera", "ref", "extra_ref", "extra_words"], "icon_cands": ["subject", "ref", "screen", "file"]}, "V68: the candidate fields are D6's: %s" % c["cand"])
        check(all(c["only"].get(k) == ["front_from_picture"] for k in ("ref", "prompt", "keep", "stills", "picture")), "V68: ref, prompt, keep, stills and picture show for front_from_picture only")
        pt = res["painterText"]
        check("stills reused from earlier paintings" in pt[0][0] and pt[0][1] == "dev 32 (stills reused)" and "stills: 3 of 12 painted (the other 9 reused)" in pt[1][0] and pt[2][1] == "Klein", "V68: the painter line says when the stills were reused: %s" % pt)
        check(res["ownKeys"] == ["art_prompt", "stills"], "V68: from, painter, method and seed_offset are bookkeeping, not own keys: %s" % res["ownKeys"])
        check(res["drafts"] == [True, False, False], "V68: a stub without a live look job is a draft; a painted look or the base is not: %s" % res["drafts"])
        review_pure_checks(check, res)
    # the flows, driven through a small DOM: the form and the look grid as Garry clicks them
    try:
        specs = contract_specs()
    except Exception as e:  # jobs.py half-written by another lane: say so, do not crash the group
        check(False, "V68: jobs.SPECS readable (%s)" % e)
        return
    methods = load_json(os.path.join(HERE, "methods.json"))
    hero_looks = [
        {"code": "MAM-A", "ready": True, "base": True, "default": True, "note": "the base", "recipe": None},
        {"code": "MAM-B", "ready": True, "base": False, "note": "B", "recipe": {"painter": {"model": "klein", "steps": 0}, "art_prompt": "a mime", "stills": "", "seed_offset": 7}},
    ]
    goblin_looks = [{"code": "GOB-A", "ready": True, "base": True, "default": True, "recipe": None}, {"code": "GOB-B", "ready": True, "base": False, "recipe": {"pose": "walk"}}]
    defaults = {
        "hero_badge|hero/mamy/MAM-C": {"ok": True, "fields": {"character": "a mime woman", "prompt": "mock surprise", "ref": "tools/dl/ai_raw_anime/mamy_c_front.png", "variant": "MAM-C"},
                                       "sources": {"character": "art_prompt without its pose clause", "prompt": "portrait_prompt", "ref": "MAM-C's front still"},
                                       "ref_url": "/dl/ai_raw_anime/mamy_c_front.png", "ref_exists": True},
        "hero_title|hero/mamy": {"ok": True, "fields": {"character": "a mime woman", "pose": "standing confidently in a heroic pose, full body", "ref": "tools/dl/ai_raw_anime/mamy_front.png", "variant": ""},
                                 "sources": {"character": "art_prompt without its pose clause", "pose": "the default pose", "ref": "the base look's front still"},
                                 "ref_url": "/dl/ai_raw_anime/mamy_front.png", "ref_exists": True},
    }
    res = run_node({"methods": methods, "specs": specs, "heroLooks": hero_looks, "goblinLooks": goblin_looks, "defaults": defaults}, FLOWS_RUNNER)
    if not isinstance(res, list):
        check(False, "V68: the form and the look grid ran under the DOM shim")
        return
    data = {}
    for name, ok, detail in res:
        if name.startswith("data:"):   # what a flow hands back for a check on this side
            data[name[5:]] = json.loads(detail)
            continue
        check(ok, "V68 flow: %s%s" % (name, "" if ok else " (%s)" % str(detail)[:400]))
    check(len(res) >= 70, "V68: the flows ran to the end (%d steps)" % len(res))
    eb = data.get("edit_badge")
    check(isinstance(eb, dict), "V68 review: the flows handed back the edited badge job's spec")
    if isinstance(eb, dict):
        edit_refill_checks(check, eb["posted"], eb["stored"], eb["target"], defaults["hero_badge|hero/mamy/MAM-C"])

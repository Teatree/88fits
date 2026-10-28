"""Pass 111, lane ENEMY: a creature strip's optional LEFT-heading sets (idle_l, run_l, attack_l, hit_l, run_bl, idle_bl
after idle_fd). selftest.py discovers this file (`extra_checks`) and hands it its `check` counter and `run_node`.
Writes only to a temporary folder.

Groups: every copy of the creature strip order in tools and the game names the same list (artkit.ENEMY_ORDER, vocab,
make_bible, frames_store, assets_model.js, strip_player.js, the selftest twins, EnemyDef.frame_offset; EnemyManager's
ANIM_NAMES the same names in its index order); the Frames view keys and labels the two left groups ("front, heading
left", "back, heading left"); the strip player plays a left set heading left and mirrors nothing of such a creature;
tools/add_left_sets.py on a synthetic creature (a grid strip with its own anims, a one-row look that inherits its anims)
appends exact unmirrored copies, keeps every existing frame and the JSON's layout, skips a look that has them and
rebuilds them the same with --force; the Cyclopean Mummy's looks carry them on disk.
"""
import json
import os
import random
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
GAME = os.path.join(ROOT, "game")
for p in (TOOLS, HERE):
    if p not in sys.path:
        sys.path.insert(0, p)

LEFT = ["idle_l", "run_l", "attack_l", "hit_l", "run_bl", "idle_bl"]

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const SP = require(path.join(dir, 'strip_player.js'));
const FM = require(path.join(dir, 'frames_model.js'));
const AM = require(path.join(dir, 'assets_model.js'));
let q = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => { q += d; });
process.stdin.on('end', () => {
  const Q = JSON.parse(q);
  const out = { spOrder: SP.ENEMY_ORDER, amOrder: AM.ENEMY_ORDER, fmViews: FM.VIEWS, fmLabels: FM.VIEW_LABEL,
    groupLabels: [FM.groupLabel({ base: 'run', view: 'front_l' }), FM.groupLabel({ base: 'idle', view: 'back_l' })],
    frameLabel: FM.frameLabel('CM-F', 'run', 'front_l', 3, 1), spLabels: [SP.viewLabel('front_l'), SP.viewLabel('back_l')] };
  out.keys = Q.keys.map((k) => { const r = SP.animKey('enemy', k.anims, k.anim, k.dir, k.facing); return [r.key, r.view, !!r.left, SP.mirror('enemy', r.view, k.facing, k.ff || 'right', k.ff || 'right', k.anims)]; });
  out.amMirror = Q.keys.map((k) => AM.mirror('enemy', k.dir, k.facing, k.ff || 'right', k.ff || 'right', k.anims));
  out.fps = ['run_l', 'run_bl', 'idle_l', 'attack_l'].map((a) => AM.previewFps('enemy', a, { run: 15 }));
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _list_after(src, pattern):
    m = re.search(pattern, src, re.S)
    if not m:
        return None
    return [x.strip().strip('"').strip("'") for x in m.group(1).replace("\n", " ").split(",") if x.strip()]


def checks(check, run_node, server):
    import artkit
    order = list(artkit.ENEMY_ORDER)
    check(order[:13] == ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
          and order[13:] == LEFT, "LEFT111: artkit.ENEMY_ORDER is the old 13 then the six left sets: %s" % order[13:])
    check(artkit.LEFT_SETS == {"idle_l": "idle", "run_l": "run", "attack_l": "attack", "hit_l": "hit", "run_bl": "run_b", "idle_bl": "idle_b"},
          "LEFT111: artkit.LEFT_SETS copies each left set from its right-heading one")
    # every Python copy
    import vocab
    import frames_store as FS
    check(list(vocab.ENEMY_ORDER) == order, "LEFT111: vocab.ENEMY_ORDER == artkit's")
    check(list(FS.ENEMY_ORDER) == order, "LEFT111: frames_store.ENEMY_ORDER == artkit's")
    for f in ("make_bible.py", os.path.join("level_editor", "selftest_P.py"), os.path.join("level_editor", "selftest_V.py")):
        got = _list_after(_read(TOOLS, f), r'\nENEMY_ORDER = \[([^\]]*)\]')
        check(got == order, "LEFT111: %s's ENEMY_ORDER == artkit's (%s)" % (f, got[13:] if got else None))
    ed = _read(GAME, "core", "data", "EnemyDef.gd")
    got = _list_after(ed, r'func frame_offset\(anim: String\) -> int:.*?for k in \[([^\]]*)\]')
    check(got == order, "LEFT111: EnemyDef.frame_offset packs in artkit's order (%s)" % (got[13:] if got else None))
    em = _read(GAME, "core", "systems", "EnemyManager.gd")
    names = _list_after(em, r'const ANIM_NAMES := \[([^\]]*)\]')
    check(names is not None and sorted(names) == sorted(order) and len(names) == len(order),
          "LEFT111: EnemyManager.ANIM_NAMES names the same %d strips (%s)" % (len(order), names))
    # the Frames store's keys: two more views, round trips, labels
    for key in LEFT:
        base, view = FS.anim_parts("enemy", key)
        check(view in ("front_l", "back_l") and FS.anim_key("enemy", base, view) == key and base in ("idle", "run", "attack", "hit"),
              "LEFT111: frames_store keys %s as %s / %s" % (key, base, view))
    for key in ("idle", "run_b", "idle_b", "run_s", "run_bd", "idle_fd", "die"):
        base, view = FS.anim_parts("enemy", key)
        check(FS.anim_key("enemy", base, view) == key and not view.endswith("_l"), "LEFT111: %s keeps its old view (%s)" % (key, view))
    check(FS.anim_parts("hero", "run_f") == ("run", "front") and FS.anim_parts("hero", "idle") == ("idle", "back"), "LEFT111: hero keys unchanged")
    check(FS.label_of(code="CM-F", base="run", view="front_l", slot=3, n=1) == "CM-F / Run / Front heading left / Frame 03 / v1",
          "LEFT111: the frame label names the left view")
    import frames_io
    check("front_l" in frames_io.VIEWS and "back_l" in frames_io.VIEWS, "LEFT111: the Frames routes accept the two left views")
    # the page modules
    e2 = {"idle": 4, "run": 12, "attack": 2, "hit": 1, "die": 5, "run_b": 12, "idle_b": 4}
    eL = dict(e2, idle_l=4, run_l=12, attack_l=2, hit_l=1, run_bl=12, idle_bl=4)
    eP = dict(e2, idle_l=4, run_l=12)    # left front sets only: the back and attack fall to the right ones, unmirrored
    keys = []
    for anims in (e2, eL, eP):
        for anim in ("idle", "run", "attack", "hit", "die"):
            for d in ("front", "back"):
                for facing in ("right", "left"):
                    keys.append({"anims": anims, "anim": anim, "dir": d, "facing": facing})
    keys.append({"anims": e2, "anim": "run", "dir": "front", "facing": "left", "ff": "left"})
    keys.append({"anims": eL, "anim": "run", "dir": "front", "facing": "right", "ff": "left"})
    res = run_node({"keys": keys}, RUNNER)
    if res is None:
        print("LEFT111: node not found: the page checks skipped")
    elif not res:
        check(False, "LEFT111: strip_player.js / frames_model.js / assets_model.js ran under node")
    else:
        check(res["spOrder"] == order and res["amOrder"] == order, "LEFT111: strip_player.js and assets_model.js orders == artkit's")
        check("front_l" in res["fmViews"] and "back_l" in res["fmViews"] and res["fmLabels"].get("front_l") == "front, heading left"
              and res["fmLabels"].get("back_l") == "back, heading left", "LEFT111: the Frames view labels the two left groups: %s" % res["fmLabels"])
        check(res["groupLabels"] == ["run · front, heading left", "idle · back, heading left"], "LEFT111: group tabs %s" % res["groupLabels"])
        check(res["frameLabel"] == "CM-F / Run / Front heading left / Frame 03 / v1", "LEFT111: the JS frame label == the Python one")
        check(res["spLabels"] == ["front, heading left", "back, heading left"], "LEFT111: the strip player names the left views")
        got = res["keys"]
        exp = []
        for anims in (e2, eL, eP):
            lsets = anims.get("idle_l", 0) > 0 or anims.get("run_l", 0) > 0
            for anim in ("idle", "run", "attack", "hit", "die"):
                for d in ("front", "back"):
                    for facing in ("right", "left"):
                        right = anim + ("_b" if d == "back" and anim in ("idle", "run") and anims.get(anim + "_b") else "")
                        view = "back" if right.endswith("_b") else "front"
                        key = right
                        if lsets and facing == "left":
                            lk = {"idle": "idle_l", "run": "run_l", "attack": "attack_l", "hit": "hit_l", "run_b": "run_bl", "idle_b": "idle_bl"}.get(right)
                            if lk and anims.get(lk):
                                key, view = lk, ("back_l" if view == "back" else "front_l")
                        mir = (facing == "left") if not lsets else False
                        exp.append([key, view, lsets, mir])
        exp.append(["run", "front", False, False])     # front_faces "left" heading left: the inverted mirror, as ever
        exp.append(["run", "front", True, False])      # a left-set look ignores front_faces: never mirrored
        same = sum(1 for a, b in zip(got, exp) if a == b)
        check(same == len(exp) and len(got) == len(exp), "LEFT111: the strip player's left sets and mirror agree on %d of %d cases; first diff %s"
              % (same, len(exp), next(((k, a, b) for k, (a, b) in enumerate(zip(got, exp)) if a != b), None)))
        check(res["amMirror"][-1] is False and res["amMirror"][-2] is False and any(res["amMirror"]), "LEFT111: assets_model.mirror never mirrors a left-set look")
        check(res["fps"] == [15, 15, 6, 8], "LEFT111: preview rates of the left keys follow their base (%s)" % res["fps"])
    _tool_checks(check)
    _mummy_checks(check, order)


def _cells(rng, n, px):
    from PIL import Image
    out = []
    for k in range(n):
        im = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        for _ in range(6):
            x, y = rng.randrange(px), rng.randrange(px)
            im.putpixel((x, y), (rng.randrange(256), rng.randrange(256), rng.randrange(256), 255))
        im.putpixel((0, 0), (k * 7 % 256, 255, 0, 255))   # every cell unlike its mirror
        out.append(im)
    return out


def _tool_checks(check):
    import add_left_sets as ALS
    from PIL import Image, ImageChops, ImageOps
    rng = random.Random(111)
    px = 8
    tmp = tempfile.mkdtemp(prefix="left111_")
    try:
        folder = os.path.join(tmp, "enemies", "testbug")
        os.makedirs(folder)
        an_a = {"idle": 2, "run": 3, "attack": 1, "hit": 1, "die": 2, "run_b": 3, "idle_b": 2}
        top = {"idle": 1, "run": 2, "attack": 1, "hit": 1, "die": 1}
        cells_a = _cells(rng, 14, px)
        cols_a = 5
        sa = Image.new("RGBA", (cols_a * px, 3 * px), (0, 0, 0, 0))
        for k, c in enumerate(cells_a):
            sa.paste(c, ((k % cols_a) * px, (k // cols_a) * px))
        sa.save(os.path.join(folder, "testbug_sprite_a.png"))
        cells_b = _cells(rng, 6, px)
        sb = Image.new("RGBA", (6 * px, px), (0, 0, 0, 0))
        for k, c in enumerate(cells_b):
            sb.paste(c, (k * px, 0))
        sb.save(os.path.join(folder, "testbug_sprite_b.png"))
        Image.new("RGBA", (6 * px, px), (0, 0, 0, 0)).save(os.path.join(folder, "testbug_sprite.png"))
        doc = {"id": "testbug", "name": "Test Bug", "frame_px": px, "anims": top, "variant_base": "TB-0",
               "variants": {"TB-0": {"note": "base"},
                            "TB-A": {"note": "grid", "sprite": "testbug_sprite_a.png", "anims": an_a, "strip_cols": cols_a, "fps": {"run": 12}},
                            "TB-B": {"note": "one row, inherits anims", "sprite": "testbug_sprite_b.png"},
                            "TB-C": {"note": "no strip on disk", "sprite": "testbug_sprite_c.png"}}}
        jpath = os.path.join(folder, "testbug.json")
        text0 = json.dumps(doc, indent=2) + "\n"
        with open(jpath, "w", encoding="utf-8", newline="") as f:
            f.write(text0)
        quiet = lambda *a: None  # noqa: E731
        res = ALS.process("testbug", ["all"], content=tmp, backup=os.path.join(tmp, "bk"), log=quiet)
        by = {r["code"]: r for r in res}
        check(by.get("TB-A", {}).get("ok") and by.get("TB-B", {}).get("ok") and not by.get("TB-C", {}).get("ok"),
              "LEFT111: add_left_sets did TB-A and TB-B, skipped TB-C without its strip: %s" % [(r["code"], r.get("ok")) for r in res])
        text1 = open(jpath, encoding="utf-8").read()
        d1 = json.loads(text1)
        a1 = d1["variants"]["TB-A"]
        check(a1["anims"] == dict(an_a, idle_l=2, run_l=3, attack_l=1, hit_l=1, run_bl=3, idle_bl=2) and list(a1["anims"])[-6:] == LEFT and a1["strip_cols"] == cols_a,
              "LEFT111: TB-A's anims gain the six counts after its own, strip_cols kept: %s" % a1["anims"])
        b1 = d1["variants"]["TB-B"]
        check(b1.get("anims") == dict(top, idle_l=1, run_l=2, attack_l=1, hit_l=1) and "strip_cols" not in b1,
              "LEFT111: TB-B (inheriting the top anims, no back set) gets its own anims with the four front left sets, still one row: %s" % b1.get("anims"))
        check(d1["anims"] == top and d1["variants"]["TB-0"] == {"note": "base"}, "LEFT111: the top level and the base look untouched (no --base)")
        # the layout: every line of the old file is still there in order, the new lines are the left counts (and TB-B's anims)
        old_lines = text0.splitlines()
        new_lines = text1.splitlines()
        it = iter(new_lines)
        kept = all(any(nl.rstrip(",") == ol.rstrip(",") for nl in it) for ol in old_lines)
        added = [l.strip() for l in new_lines if l.rstrip(",") not in {o.rstrip(",") for o in old_lines}]
        check(kept and all(re.match(r'^("(\w+)": \d+,?|"anims": \{|\},?)$', a) for a in added),
              "LEFT111: the JSON keeps its layout; only count lines (and TB-B's anims object) added: %s" % added[:12])
        # the strips: old frames where they were, copies identical and unmirrored
        sa1 = Image.open(os.path.join(folder, "testbug_sprite_a.png")).convert("RGBA")
        check(sa1.size == (cols_a * px, 6 * px), "LEFT111: TB-A grows by rows: %s (14 + 12 frames at 5 columns)" % (sa1.size,))
        def cell(img, k, cols):
            return img.crop(((k % cols) * px, (k // cols) * px, (k % cols) * px + px, (k // cols) * px + px))
        check(all(ImageChops.difference(cell(sa1, k, cols_a), cell(sa, k, cols_a)).getbbox() is None for k in range(14)),
              "LEFT111: TB-A's old frames are where they were, unchanged")
        off = {}
        n = 0
        for a in ALS.ORDER:
            off[a] = n
            n += a1["anims"].get(a, 0)
        ok = True
        mirrored = 0
        for lk, src in ALS.LEFT.items():
            for j in range(a1["anims"].get(lk, 0)):
                c1, c0 = cell(sa1, off[lk] + j, cols_a), cell(sa1, off[src] + j, cols_a)
                ok = ok and ImageChops.difference(c1, c0).getbbox() is None
                mirrored += ImageChops.difference(c1, ImageOps.mirror(c0)).getbbox() is None
        check(ok and mirrored == 0, "LEFT111: TB-A's left frames are exact copies of their right ones, none mirrored")
        sb1 = Image.open(os.path.join(folder, "testbug_sprite_b.png")).convert("RGBA")
        check(sb1.size == (11 * px, px), "LEFT111: TB-B stays one row of 6 + 5 frames: %s" % (sb1.size,))
        check(len(os.listdir(os.path.join(tmp, "bk", "testbug"))) == 3, "LEFT111: the old strips and the JSON are backed up first")
        # a second run skips; --force rebuilds the same
        res2 = ALS.process("testbug", ["TB-A"], content=tmp, backup=os.path.join(tmp, "bk"), log=quiet)
        check(not res2[0]["ok"] and open(jpath, encoding="utf-8").read() == text1, "LEFT111: a look with left sets is skipped")
        res3 = ALS.process("testbug", ["TB-A", "TB-B"], force=True, content=tmp, backup=os.path.join(tmp, "bk"), log=quiet)
        check(all(r["ok"] for r in res3) and open(jpath, encoding="utf-8").read() == text1
              and ImageChops.difference(Image.open(os.path.join(folder, "testbug_sprite_a.png")).convert("RGBA"), sa1).getbbox() is None,
              "LEFT111: --force rebuilds the same strip and the same JSON")
        # a dry run writes nothing; an unknown anim is refused
        res4 = ALS.process("testbug", ["all"], base=True, dry=True, content=tmp, backup=os.path.join(tmp, "bk"), log=quiet)
        check(open(jpath, encoding="utf-8").read() == text1 and any(r["ok"] for r in res4), "LEFT111: --dry-run writes nothing")
        try:
            ALS.build(sa, dict(an_a, wobble=2), cols_a, px)
            refused = False
        except ValueError:
            refused = True
        check(refused, "LEFT111: a strip with an animation outside the order is refused")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _mummy_checks(check, order):
    from PIL import Image
    folder = os.path.join(GAME, "content", "enemies", "cyclopean_mummy")
    p = os.path.join(folder, "cyclopean_mummy.json")
    if not os.path.isfile(p):
        return
    d = json.load(open(p, encoding="utf-8"))
    for code in ("CM-A", "CM-B", "CM-C", "CM-D", "CM-E", "CM-F", "CM-G"):
        e = (d.get("variants") or {}).get(code)
        if not isinstance(e, dict) or not e.get("sprite"):
            continue
        an = e.get("anims") or {}
        total = sum(int(an.get(a, 0)) for a in order)
        cols = int(e.get("strip_cols", 0)) or total
        im = Image.open(os.path.join(folder, e["sprite"]))
        rows = -(-total // cols)
        check(all(int(an.get(k, 0)) > 0 for k in LEFT) and im.size == (cols * d["frame_px"], rows * d["frame_px"]),
              "LEFT111: the Cyclopean Mummy's %s carries the six left sets in a %dx%d strip (%d frames)" % (code, im.size[0], im.size[1], total))

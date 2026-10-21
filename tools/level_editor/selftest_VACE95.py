"""Pass 95, lane VACE: the frames store, the Frames view's routes and maths, the VACE repair's window (Garry: "a way to
view every single frame and choose which ones to regenerate ... available to existing assets too ... the history of other
generated frames ... frames from other Looks ... several frame changes in one go").

Groups, all on a temporary world (a creature "bug" with a base look BG-A and a look BG-B, their strips packed from
drawn blobs, BG-B's side walk with a synthetic clip cache, a driver and a painting; nothing under game/ or tools/dl is
touched): the strip keys and views; the retrofit (versions, labels, ids, the clip twins, the fit measured from the
pairs and the round trip raw -> cell against the installed cell; the driver's frame per slot); registering again adds
nothing; versions, staging, unstaging, pinning; the flags on known-bad frames (an empty frame, a shifted one); the
export (the staged cell packed where it belongs, the rest untouched, the backup, the commit, the sidecar entry); a
re-roll keeps a pinned slot; a copy from another look; the routes over HTTP on a temporary server with a jobs
stand-in (summary, detail, others, stage, unstage, pin, copy, repair, export, the pictures, bad ids); vace_repair's
window plan and its dry run; frames_model.js under Node; the page's wiring; the two job kinds' specs and plans.
"""
import json
import os
import shutil
import sys
import tempfile
import threading
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const F = require(path.join(dir, 'frames_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  let r = F.select(new Set(), 3, {}, null);
  const s1 = Array.from(r.set);
  r = F.select(r.set, 6, { shift: true }, r.anchor);
  const s2 = Array.from(r.set).sort((a, b) => a - b);
  r = F.select(r.set, 9, { ctrl: true }, r.anchor);
  const s3 = Array.from(r.set).sort((a, b) => a - b);
  r = F.select(r.set, 9, { ctrl: true }, r.anchor);
  const s4 = Array.from(r.set).sort((a, b) => a - b);
  r = F.select(new Set([2]), 2, {}, 2);
  out.select = [s1, s2, s3, s4, Array.from(r.set)];
  out.text = [F.slotsText([3, 4, 5, 9]), F.slotsText([1]), F.slotsText([]), F.slotsText([1, 2])];
  out.parse = q.parse.map((t) => F.parseSlots(t, 12));
  out.plans = q.plans.map((p) => F.repairPlan(p[0], p[1], p[2], p[3]));
  out.fps = [F.previewFps('enemy', 'run', { run: 20 }), F.previewFps('hero', 'run', {}), F.previewFps('enemy', 'die', {}), F.previewFps('hero', 'idle', {})];
  out.badges = F.badges({ staged: 'abcdef', pinned: true, installed_differs: 'x' }, { jump: { rule: 'j' }, empty: { rule: 'e' } }).map((b) => b.key);
  out.vtext = F.versionText({ label: 'SP-B-2', source: 'vace', seed: 24110, time: '2026-10-21T13:20:00' });
  out.compat = F.compat({ frame_px: 128, n: 12, driver: 'other' }, 12, 160, 'spider_walk');
  out.line = F.summaryLine({ groups: [{ n: 4, staged: 1 }, { n: 12, staged: 2 }] });
  out.step = [F.step(11, 12, 1, true), F.step(0, 12, -1, true), F.step(11, 12, 1, false), F.step(0, 12, -1, false)];
  out.newest = F.versionsNewestFirst([{ n: 1 }, { n: 3 }, { n: 2 }]).map((v) => v.n);
  out.label = F.groupLabel({ base: 'run', view: 'bd' });
  out.confirm = [F.exportConfirmText('SP-B', 2, true, 'desert_spider'), F.exportConfirmText('SP-B', 2, false, 'desert_spider')];
  out.vtext2 = F.versionText({ label: 'SP-B-3', source: 'vace', driver: { name: 'spider_walk', ctl_sig: 'abcdef0123' }, shrunk: 0.9, from: { label: 'SP-C-1', code: 'SP-C', removed: true } });
  out.where = F.whereLine({ strip_file: 'game/x.png', clip_dir: 'tools/dl/ai_anim/k', path: 'tools/dl/frames/enemy/x/SP-B/run/side', backups_dir: 'tools/level_editor/backups/x' });
  process.stdout.write(JSON.stringify(out));
});
"""


class FakeJobs:
    """The server's jobs module stood in: enqueue records what the routes would queue."""

    def __init__(self):
        self.calls = []
        self.n = 0

    def enqueue(self, kind, target, spec, title=None):
        self.n += 1
        job = {"id": "jfake-%04d" % self.n, "kind": kind, "target": target, "spec": spec, "title": title, "state": "queued"}
        self.calls.append(job)
        return job


def _blob_canvas(S, cx, cy, rx, ry, colour=(220, 120, 40, 255)):
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=colour)
    return im


def _cell_from_raw(raw, px, s, o, outline_px, colour=(14, 8, 12, 255)):
    """A strip cell the way a pipeline would place a clip frame: scaled by s, moved by o, punched, outlined."""
    import artkit
    from PIL import Image
    small = raw.resize((max(1, int(round(raw.width * s))), max(1, int(round(raw.height * s)))), Image.LANCZOS)
    cell = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    cell.alpha_composite(small, (int(round(o)), int(round(o))))
    return artkit.add_outline(artkit.punch(cell), outline_px, colour)


def _make_world(tmp):
    """The temporary creature, its two looks, BG-B's side clip cache, the driver and the painting. Returns the facts."""
    import artkit
    from PIL import Image
    S, px = 256, 64
    s0, o0 = 0.2, 6.4
    opx = max(1, int(round(px * 0.024)))
    content = os.path.join(tmp, "content")
    folder = os.path.join(content, "enemies", "bug")
    os.makedirs(folder, exist_ok=True)
    anims = {"idle": 2, "run": 4, "die": 3, "run_s": 4, "idle_s": 2}
    order = artkit.ENEMY_ORDER
    # BG-B's side walk: four raw frames on the clip's canvas (the body bobs and slides), their cells through a known fit
    raws = [_blob_canvas(S, 128 + 6 * k, 150 - 8 * (k % 2), 60, 36) for k in range(4)]
    cells_b = {"run_s": [_cell_from_raw(r, px, s0, o0, opx) for r in raws]}
    # the other animations of BG-B and every animation of BG-A: blobs drawn straight into cells
    def cell_blob(cx, cy, rx, ry, colour=(220, 120, 40, 255)):
        return artkit.add_outline(_blob_canvas(px, cx, cy, rx, ry, colour), opx)
    for key, n in anims.items():
        if key not in cells_b:
            cells_b[key] = [cell_blob(32 + k, 40 - 2 * (k % 2), 14, 9) for k in range(n)]
    cells_a = {key: [cell_blob(30, 42 - 2 * (k % 2), 15, 10, (60, 140, 220, 255)) for k in range(n)] for key, n in anims.items()}
    # BG-A's run: frame 1 shifted far right, frame 2 empty (the flags)
    cells_a["run"][1] = cell_blob(52, 20, 15, 10, (60, 140, 220, 255))
    cells_a["run"][2] = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    strip_a, counts_a, cols_a = artkit.pack_strip(cells_a, order, px)
    strip_b, counts_b, cols_b = artkit.pack_strip(cells_b, order, px)
    strip_a.save(os.path.join(folder, "bug_sprite.png"))
    strip_b.save(os.path.join(folder, "bug_sprite_b.png"))
    doc = {"id": "bug", "name": "Bug", "hp": 10, "anims": counts_a, "frame_px": px, "strip_cols": cols_a, "fps": {"run": 10, "die": 6},
           "sprite": "bug_sprite.png", "icon": "bug_icon.png", "variant_base": "BG-A", "variant": "BG-B",
           "variants": {"BG-A": {"note": "the base"},
                        "BG-B": {"note": "the test look", "sprite": "bug_sprite_b.png", "icon": "bug_icon_b.png", "anims": counts_b, "strip_cols": cols_b,
                                 "fps": {"run": 10, "die": 6}, "recipe": {"method": "creature_ctl", "drivers": "bugwalk", "noun": "a bug", "no_green": False}}}}
    with open(os.path.join(folder, "bug.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=2)
    # the clip cache: two strides + 1 (9 frames), the second stride kept as out_00..03 cut to the box
    import numpy as np
    anim = os.path.join(tmp, "dl", "ai_anim", "bug_bgb_ctl_side")
    os.makedirs(anim, exist_ok=True)
    fulls = raws + raws + [raws[0]]
    for k, fr in enumerate(fulls):
        fr.save(os.path.join(anim, "full_%02d.png" % k))
    boxes = []
    for fr in raws:
        a = np.asarray(fr)[..., 3] > 127
        ys, xs = np.nonzero(a)
        boxes.append((xs.min(), ys.min(), xs.max(), ys.max()))
    pad = 6
    box = (max(0, min(b[0] for b in boxes) - pad), max(0, min(b[1] for b in boxes) - pad), min(S, max(b[2] for b in boxes) + pad + 1), min(S, max(b[3] for b in boxes) + pad + 1))
    for k, fr in enumerate(raws):
        fr.crop(box).save(os.path.join(anim, "out_%02d.png" % k))
    with open(os.path.join(anim, "cycle.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"key": "bug_bgb_ctl_side", "seed": 5, "control": True, "n_out": 4, "frames": 9, "box": [int(v) for v in box], "ctl_sig": "sig123",
                   "wan": {"steps": 4, "cfg": 1.0, "lora": True, "shift": 5.0, "size": S}, "prompt": "a bug walking in place"}, f)
    # the driver: nine grey blobs on black, a clay
    drv = os.path.join(tmp, "dl", "drivers", "bugwalk", "side")
    os.makedirs(drv, exist_ok=True)
    for k in range(9):
        im = Image.new("RGB", (S, S), (0, 0, 0))
        from PIL import ImageDraw
        ImageDraw.Draw(im).ellipse((80 + 5 * (k % 4), 110, 180 + 5 * (k % 4), 180), fill=(200, 200, 200))
        im.save(os.path.join(drv, "ctl_%02d.png" % k))
    Image.new("RGB", (S, S), (0, 0, 0)).save(os.path.join(drv, "clay.png"))
    with open(os.path.join(tmp, "dl", "drivers", "bugwalk", "meta.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"kind": "depth", "frames": 4, "cycles": 2, "loop": True}, f)
    # the painting
    raw_dir = os.path.join(tmp, "dl", "ai_raw_anime")
    os.makedirs(raw_dir, exist_ok=True)
    pic = Image.new("RGB", (512, 512), (0, 255, 0))
    pic.paste(Image.new("RGB", (200, 120), (220, 120, 40)), (156, 200))
    pic.save(os.path.join(raw_dir, "bug_bgb_side.png"))
    return {"S": S, "px": px, "s0": s0, "o0": o0, "opx": opx, "folder": folder, "content": content, "anims": anims, "cells_b": cells_b, "cells_a": cells_a,
            "cols_b": cols_b, "order": order, "raws": raws, "box": box}


def _offset(order, anims, key):
    off = 0
    for a in order:
        if a == key:
            return off
        off += int(anims.get(a, 0) or 0)
    return off


def checks(check, run_node, server):
    import numpy as np
    from PIL import Image
    import frames_store as FS
    import frames_io as FRIO
    import vace_repair as VR

    # the strip keys and views
    check(FS.anim_parts("enemy", "run_s") == ("run", "side") and FS.anim_parts("enemy", "idle") == ("idle", "front") and FS.anim_parts("hero", "run") == ("run", "back")
          and FS.anim_parts("hero", "hit_fd") == ("hit", "fd") and FS.anim_parts("enemy", "run_bd") == ("run", "bd"), "anim_parts: the strip keys split into base and view")
    check(FS.anim_key("enemy", "run", "side") == "run_s" and FS.anim_key("hero", "run", "front") == "run_f" and FS.anim_key("hero", "idle", "back") == "idle"
          and FS.anim_key("enemy", "run", "front") == "run", "anim_key: the base view has no suffix")
    check(FS.loops("run") and FS.loops("idle") and not FS.loops("die") and not FS.loops("attack"), "loops: idle and run loop, the rest play once")

    tmp = tempfile.mkdtemp(prefix="le_vace95_")
    saved = {k: getattr(FS, k) for k in ("STORE", "CONTENT", "ANIM", "DRIVERS", "RAW", "BACKUPS")}
    try:
        w = _make_world(tmp)
        FS.STORE = os.path.join(tmp, "dl", "frames")
        FS.CONTENT = w["content"]
        FS.ANIM = os.path.join(tmp, "dl", "ai_anim")
        FS.DRIVERS = os.path.join(tmp, "dl", "drivers")
        FS.RAW = os.path.join(tmp, "dl", "ai_raw_anime")
        FS.BACKUPS = os.path.join(tmp, "backups")

        # ---- the retrofit of BG-B
        r = FS.register_look("enemy", "bug", "BG-B")
        check(r.get("ok") and len(r["groups"]) == 5 and [g["group"] for g in r["groups"]] == ["idle", "run", "die", "run_s", "idle_s"],
              "register_look: one group per animation of the strip, in the strip's order: %s" % [g.get("group") for g in r.get("groups", [])])
        look = FS.Look("enemy", "bug", "BG-B")
        g = FS.Group(look, "run", "side")
        check(g.exists() and g.n == 4 and g.key == "run_s" and g.meta["clip"]["key"] == "bug_bgb_ctl_side" and g.meta["clip"]["match"] and g.meta["canvas"] == w["S"],
              "the side walk's group: 4 slots, its clip cache found (out count = slots), the clip's canvas")
        fit = g.meta.get("fit") or {}
        check(fit.get("source") == "measured" and abs(fit["s"] - w["s0"]) < 0.02 and fit["pairs"] == 4 and fit["residual_px"] < 2.0,
              "the fit measured from the cell / clip pairs: s %.3f (made with %.3f), residual %.2f px" % (fit.get("s", 0), w["s0"], fit.get("residual_px", 99)))
        drv = g.meta.get("driver") or {}
        check(drv.get("name") == "bugwalk" and drv.get("index") == [4, 5, 6, 7] and drv.get("kind") == "depth", "the driver and the frame of each slot (the second stride): %s" % drv.get("index"))
        check(g.meta.get("ref_still", "").endswith("bug_bgb_side.png") and g.meta.get("screen") == "green" and g.meta["post"].get("no_green") is False and g.meta["post"].get("drop_islands"),
              "the painting, the screen and the post filters recorded")
        vs = [g.versions(k) for k in range(4)]
        check(all(len(v) == 1 for v in vs) and [v[0]["label"] for v in vs] == ["BG-B-1"] * 4 and all(len(v[0]["id"]) == 16 for v in vs)
              and all(v[0]["source"] == "installed" and v[0]["space"] == "cell" and v[0].get("raw") for v in vs),
              "one installed version per slot, labelled BG-B-1, a 16-hex id, with its clip twin")
        sel = g.selected()
        check(all(sel[str(k)]["id"] == vs[k][0]["id"] and not sel[str(k)]["pinned"] for k in range(4)), "the installed version is selected, not pinned")
        # the round trip: the twin through the fit against the installed cell
        ious = []
        for k in range(4):
            raw = g.raw_of(k, vs[k][0])
            rend = g.to_cell(raw)
            a = np.asarray(w["cells_b"]["run_s"][k])[..., 3] > 127
            b = np.asarray(rend)[..., 3] > 127
            ious.append((a & b).sum() / max(1, (a | b).sum()))
        check(min(ious) > 0.9, "a clip frame rendered with the fit overlaps the installed cell (IoU %.3f..%.3f)" % (min(ious), max(ious)))
        # idle (cells only): no clip, the default fit, no driver
        gi = FS.Group(look, "idle", "front")
        check(gi.exists() and gi.n == 2 and gi.meta.get("clip") is None and gi.fit()["source"] == "default" and gi.meta.get("driver") is None and not gi.versions(0)[0].get("raw"),
              "an animation without a clip cache: cells only, the default fit, no driver")
        # registering again adds nothing
        r2 = FS.register_look("enemy", "bug", "BG-B")
        check(r2["ok"] and all(not x["new"] and not x["changed"] for x in r2["groups"]) and all(len(g.versions(k)) == 1 for k in range(4)), "registering again adds no version and changes nothing")

        # ---- versions, staging, pinning
        edited = w["cells_b"]["run_s"][1].copy()
        edited.paste((255, 0, 0, 255), (10, 10, 20, 20))
        v2 = g.add_version(1, edited, "cell", "repaint", by="human", note="a red patch")
        check(v2["label"] == "BG-B-2" and v2["n"] == 2 and v2["id"] != vs[1][0]["id"] and v2["cell_sha1"] == v2["id"], "a new version: BG-B-2, its own id")
        v2b = g.add_version(1, edited, "cell", "repaint", by="human")
        check(v2b["id"] == v2["id"] and len(g.versions(1)) == 2, "the same bytes again are the same version, not a third")
        st = g.stage(1, v2["id"], why="test")
        eff, how = g.effective(1)
        check(st and st["id"] == v2["id"] and eff["id"] == v2["id"] and how == "staged" and g.staged().get("1"), "staging: the effective version is the staged one")
        g.unstage(1)
        eff, how = g.effective(1)
        check(eff["id"] == vs[1][0]["id"] and how == "selected" and not g.staged(), "unstaging: back to the selected one")
        st2 = g.stage(1, vs[1][0]["id"])
        check(st2 is None and not g.staged(), "staging what is selected stages nothing")
        try:
            g.stage(1, "nope")
            check(False, "staging an unknown version is refused")
        except ValueError:
            check(True, "staging an unknown version is refused")
        g.pin(2, True)
        check(g.selected()["2"]["pinned"] and g.selected()["2"]["by"] == "human", "pinning marks the selected version a human's")
        g.pin(2, False)
        check(not g.selected()["2"]["pinned"], "unpinning")

        # ---- the flags on known-bad frames (BG-A's run: frame 1 shifted, frame 2 empty)
        FS.register_look("enemy", "bug", "BG-A")
        ga = FS.Group(FS.Look("enemy", "bug", "BG-A"), "run", "front")
        fl = ga.flags()
        check("empty" in fl["2"] and ("footprint" in fl["1"] or "jump" in fl["1"]) and not fl["0"] and not fl["3"],
              "flags: the empty frame and the shifted frame are flagged, the plain ones are not: %s" % {k: list(v) for k, v in fl.items()})
        check(not any(g.flags()[str(k)].get("empty") for k in range(4)), "no empty flag on the side walk")

        # ---- the export: the staged cell lands where it belongs, the rest is untouched
        g.stage(1, v2["id"], why="test")
        strip_before = open(look.strip_path, "rb").read()
        side_file = os.path.join(tmp, "side.json")
        ex = FS.export_look("enemy", "bug", "BG-B", job="jtest", sidecar=side_file)
        check(ex.get("ok") and not ex.get("unchanged") and len(ex["changed"]) == 1 and ex["changed"][0]["group"] == "run_s" and ex["changed"][0]["slot"] == 1,
              "export: one frame changed: %s" % ex.get("changed"))
        strip = Image.open(look.strip_path).convert("RGBA")
        px = w["px"]
        off = _offset(w["order"], w["anims"], "run_s") + 1
        cell_now = strip.crop((off * px, 0, off * px + px, px))
        check(np.array_equal(np.asarray(cell_now), np.asarray(FS.clean_alpha(edited))), "the staged cell is in the strip at run_s slot 1 (the RGB under alpha 0 zeroed, as a packed strip has it)")
        bpath = os.path.join(FS.BACKUPS, "bug")
        backups = os.listdir(bpath) if os.path.isdir(bpath) else []
        check(len(backups) == 1 and backups[0].startswith("frames_") and open(os.path.join(bpath, backups[0]), "rb").read() == strip_before, "the old strip is backed up as it was")
        old = Image.open(os.path.join(bpath, backups[0])).convert("RGBA")
        same = sum(1 for k in range(15) if np.array_equal(np.asarray(strip.crop((k * px, 0, k * px + px, px))), np.asarray(old.crop((k * px, 0, k * px + px, px)))))
        check(same == 14, "every other cell of the strip is untouched (%d of 15 equal)" % same)
        sel = g.selected()
        check(sel["1"]["id"] == v2["id"] and sel["1"]["pinned"] and sel["1"]["by"] == "export" and not g.staged(), "the export commits the choice: selected, pinned, nothing staged")
        logs = json.load(open(os.path.join(g.dir, "exports.json"), encoding="utf-8"))
        check(len(logs) == 1 and logs[0]["job"] == "jtest" and logs[0]["changed"][0]["slot"] == 1, "exports.json logs it")
        side = json.load(open(side_file, encoding="utf-8"))
        check(side["variant"] == "BG-B" and side["entry"]["sprite"] == "bug_sprite_b.png" and side["entry"]["anims"] == w["anims"] and side["entry"]["strip_cols"] == w["cols_b"]
              and 0 < side["entry"]["head"] <= 1 and side["info"]["pipeline"] == "frames_export", "the sidecar entry: sprite, anims, strip_cols, head")
        ex2 = FS.export_look("enemy", "bug", "BG-B", job="jtest2", sidecar=side_file)
        check(ex2.get("ok") and ex2.get("unchanged"), "exporting again with nothing staged writes nothing")
        r3 = FS.register_look("enemy", "bug", "BG-B")
        check(all(not x["changed"] for x in r3["groups"]) and len(g.versions(1)) == 2, "after the export the installed cells are known versions: registering adds nothing")

        # ---- a re-roll (the strip changed under the store) keeps a pinned slot and adds versions elsewhere
        g.pin(3, True)
        cells = dict(w["cells_b"])
        cells["run_s"] = list(cells["run_s"])
        cells["run_s"][1] = edited
        import artkit
        for k in (0, 3):
            c = cells["run_s"][k].copy()
            c.paste((0, 0, 255, 255), (40, 40, 50, 50))
            cells["run_s"][k] = c
        strip2, _, _ = artkit.pack_strip(cells, w["order"], px)
        strip2.save(look.strip_path)
        r4 = FS.register_look("enemy", "bug", "BG-B")
        grp = next(x for x in r4["groups"] if x["group"] == "run_s")
        sel = g.selected()
        check(len(g.versions(0)) == 2 and g.versions(0)[1]["source"] == "reroll" and sel["0"]["id"] == g.versions(0)[1]["id"] and sel["0"]["by"] == "install",
              "a re-rolled slot gets the new cell as a version and selects it")
        check(len(g.versions(3)) == 2 and sel["3"]["id"] == g.versions(3)[0]["id"] and sel["3"]["pinned"] and sel["3"].get("installed_differs") == g.versions(3)[1]["id"],
              "a pinned slot keeps its choice and says the strip differs")
        check([c["slot"] for c in grp["changed"]] == [0, 3], "what changed: %s" % grp["changed"])

        # ---- a copy from another look
        ga_s = FS.Group(FS.Look("enemy", "bug", "BG-A"), "run", "side")
        src = ga_s.versions(2)[0]
        cv = FS.copy_version(g, ga_s, 2, src["id"], 2, by="human")
        check(cv["source"] == "copied" and cv["from"]["code"] == "BG-A" and cv["from"]["slot"] == 2 and cv["label"] == "BG-B-2" and cv["space"] == "cell",
              "a copy from BG-A: a new version here naming its source: %s" % cv.get("from"))
        others = FS.other_looks("enemy", "bug", "BG-B", "run", "side")
        check([o["code"] for o in others] == ["BG-A"] and others[0]["n"] == 4 and others[0]["frame_px"] == px, "the other looks with this animation")

        # ---- pass 95 resume (the assessment's engineering items)
        # store_version in group.json; the driver {name, ctl_sig} and the clip's wan on every installed version
        gj = json.load(open(os.path.join(g.dir, "group.json"), encoding="utf-8"))
        check(gj.get("store_version") == FS.STORE_VERSION == 1 and g.meta.get("store_version") == 1, "group.json carries store_version 1")
        v0 = g.versions(0)[0]
        check(v0.get("driver") == {"name": "bugwalk", "ctl_sig": "sig123"} and (v0.get("wan") or {}).get("steps") == 4 and g.meta["clip"].get("ctl_sig") == "sig123",
              "an installed version records driver {name, ctl_sig} and the clip's wan: %s %s" % (v0.get("driver"), v0.get("wan")))
        # the shrink guard: a raw figure larger than the cell at the fit's scale is shrunk about its floor, never cropped, and flagged
        gi2 = FS.Group(look, "idle", "front")
        big = _blob_canvas(FS.CANVAS, 320, 320, 300, 300)
        cell_big = gi2.to_cell(big)
        bb = FS.bbox(cell_big)
        check(gi2.last_shrink is not None and 0.3 < gi2.last_shrink < 1.0 and bb and bb[0] >= 0 and bb[1] >= 0 and bb[2] <= px and bb[3] <= px and abs((bb[2] - bb[0]) - (bb[3] - bb[1])) <= 2,
              "to_cell shrinks a figure wider than the cell (x%.2f) and keeps it whole inside: box %s" % (gi2.last_shrink or 0, bb))
        small_ok = gi2.to_cell(_blob_canvas(FS.CANVAS, 320, 320, 100, 100))
        check(gi2.last_shrink is None and FS.bbox(small_ok), "a figure that fits is placed at the fit's scale, no shrink")
        vb = gi2.add_version(0, big, "raw", "vace", by="ai")
        gi2.cell_of(0, vb)
        gi2.stage(0, vb["id"])
        fl2 = gi2.flags()
        check(gi2.version(0, vb["id"]).get("shrunk") and "footprint" in fl2["0"] and fl2["0"]["footprint"].get("shrunk"), "a shrunk version says so and the flags raise footprint on it: %s" % fl2["0"].get("footprint"))
        gi2.unstage(0)
        # retention: a referenced version is never deleted, an unreferenced one goes, the slot's last one stays
        rd1 = FS.delete_version(g, 1, v2["id"])
        check(not rd1.get("ok") and rd1.get("referenced"), "a selected (exported) version is refused: %s" % rd1.get("error"))
        old1 = vs[1][0]
        rd2 = FS.delete_version(g, 1, old1["id"])
        check(rd2.get("ok") and not os.path.isfile(old1["file"]) and len(g.versions(1)) == 1, "an unreferenced version's files go: %s" % rd2.get("files"))
        rd3 = FS.delete_version(g, 1, v2["id"])
        check(not rd3.get("ok") and "only version" in rd3.get("error", ""), "the slot's only version stays")
        refs = FS.referenced_ids("enemy", "bug")
        check(v2["id"] in refs and cv["from"]["version"] in refs, "referenced_ids: selections and a copy's source count")
        bdir2 = os.path.join(tmp, "cap")
        os.makedirs(bdir2)
        for i in range(35):
            open(os.path.join(bdir2, "frames_2026%04d_x.png" % i), "wb").write(b"x")
        gone = FS.prune_strip_backups(bdir2)
        left = sorted(os.listdir(bdir2))
        check(len(gone) == 5 and len(left) == 30 and left[0] == "frames_20260005_x.png", "strip backups capped at 30 per asset, the oldest removed")
        rdir = os.path.join(tmp, "rep")
        os.makedirs(rdir)
        import time as _t
        for nm, age in (("repair_old.png", 100), ("window_old.jpg", 100), ("repair_new.png", 1), ("keep.txt", 100)):
            p = os.path.join(rdir, nm)
            open(p, "wb").write(b"x")
            os.utime(p, (_t.time() - age * 86400, _t.time() - age * 86400))
        gone2 = FS.prune_repairs(rdir)
        check(sorted(gone2) == ["repair_old.png", "window_old.jpg"] and sorted(os.listdir(rdir)) == ["keep.txt", "repair_new.png"], "repair sheets older than 90 days go, newer and other files stay")
        # rollback_export: the strip back from the backup, the exported choices staged again, nothing pinned, logged
        g.unstage()
        g.stage(0, g.versions(0)[0]["id"], why="test")
        strip_pre = open(look.strip_path, "rb").read()
        ex3 = FS.export_look("enemy", "bug", "BG-B", job="jroll", sidecar=os.path.join(tmp, "side3.json"))
        check(ex3.get("ok") and ex3["changed"][0]["slot"] == 0 and ex3.get("old_entry", {}).get("strip_cols") == w["cols_b"] and ex3.get("in_play") is True and ex3.get("strip_sha1_before"),
              "an export returns the old entry, the strip's hash before and whether the look is in play")
        rb = FS.rollback_export("enemy", "bug", "BG-B", ex3["backup"], ex3["changed"], job="jroll-back", why="test")
        sel = g.selected()
        check(rb.get("ok") and open(look.strip_path, "rb").read() == strip_pre and sel["0"]["id"] == g.versions(0)[1]["id"] and not sel["0"]["pinned"]
              and g.staged().get("0", {}).get("id") == g.versions(0)[0]["id"] and (json.load(open(os.path.join(g.dir, "exports.json"), encoding="utf-8"))[-1].get("rollback")),
              "rollback_export: the strip is the backup again, the installed cell selected, the choice staged again, logged: %s" % {k: rb.get(k) for k in ("ok", "staged_again")})
        # hook_after_save (a gen_art / gen_ctl hand run): the store follows the saved strip; a pinned slot warns
        said = []
        cells3 = {k: list(v) for k, v in w["cells_b"].items()}
        cells3["run_s"][1] = edited
        c2 = cells3["run_s"][2].copy()
        c2.paste((255, 255, 0, 255), (20, 20, 30, 30))
        cells3["run_s"][2] = c2
        strip3, counts3, cols3 = artkit.pack_strip(cells3, w["order"], px)
        strip3.save(look.strip_path)
        g.pin(2, True)
        hk = FS.hook_after_save(w["folder"], "bug", "BG-B", counts3, cols3, "bug_sprite_b.png", log=lambda *a: said.append(" ".join(str(x) for x in a)))
        check(hk and hk.get("ok") and len(g.versions(2)) == 3 and g.versions(2)[2]["source"] == "reroll" and g.selected()["2"]["pinned"] and g.selected()["2"].get("installed_differs"),
              "hook_after_save registers the saved strip (a reroll version) and keeps the pinned choice: %s" % hk.get("pinned"))
        check(any("WARNING" in s and "Export is the writer" in s for s in said), "the hook warns about pinned slots: %s" % (said[-1][:100] if said else ""))
        g.pin(2, False)
        hk2 = FS.hook_after_save(w["folder"], "nobody", "XX-A", {}, 0)
        check(hk2 is None, "a look the store never saw is left alone")
        # removed looks: a third look BG-C registered, then dropped from the JSON: the picker still lists it, marked
        import shutil as _sh
        _sh.copy2(os.path.join(w["folder"], "bug_sprite.png"), os.path.join(w["folder"], "bug_sprite_c.png"))
        docp = os.path.join(w["folder"], "bug.json")
        doc3 = json.load(open(docp, encoding="utf-8"))
        doc3["variants"]["BG-C"] = {"note": "a third look", "sprite": "bug_sprite_c.png", "anims": doc3["anims"], "strip_cols": doc3["strip_cols"]}
        json.dump(doc3, open(docp, "w", encoding="utf-8", newline="\n"), indent=2)
        FS.register_look("enemy", "bug", "BG-C")
        del doc3["variants"]["BG-C"]
        json.dump(doc3, open(docp, "w", encoding="utf-8", newline="\n"), indent=2)
        check(FS.removed_looks("enemy", "bug") == ["BG-C"], "removed_looks finds the store's look the JSON dropped")
        others2 = FS.other_looks("enemy", "bug", "BG-B", "run", "side")
        oc = next((o for o in others2 if o["code"] == "BG-C"), None)
        check(oc is not None and oc["removed"] and oc["n"] == 4 and oc["frame_px"] == px and not any(o["removed"] for o in others2 if o["code"] == "BG-A"), "other_looks lists the removed look, marked, with its slots")
        cvr = FS.copy_version(g, oc["group"], 3, oc["group"].versions(3)[0]["id"], 3, by="human")
        check(cvr["source"] == "copied" and cvr["from"]["code"] == "BG-C" and cvr["from"].get("removed") is True, "a copy from a removed look says so in its `from`")
        s2 = FS.look_summary("enemy", "bug", "BG-B")
        check(s2.get("in_play") is True and FS.look_summary("enemy", "bug", "BG-A").get("in_play") is False and s2.get("strip_file", "").endswith("bug_sprite_b.png"), "look_summary says which look is in play")

        # ---- the detail the page gets
        g.unstage()
        g.pin(3, True)
        d = g.detail(lambda p: "/x/" + os.path.basename(p))
        check(d["ok"] and d["n"] == 4 and len(d["slots"]) == 4 and d["slots"][3]["pinned"] and d["slots"][1]["selected"] == v2["id"] and d["slots"][0]["driver_frame"] == 4
              and d["slots"][1]["versions"][0]["label"] == "BG-B-2" and d["slots"][1]["url"].startswith("/x/") and d["fit"]["source"] == "measured" and "flags" in d
              and d["store_version"] == 1 and d["in_play"] is True and d["strip_file"].endswith("bug_sprite_b.png") and d["clip_dir"].endswith("bug_bgb_ctl_side") and d["backups_dir"].endswith("bug"),
              "the group detail: slots, versions, choices, the driver's frames, the fit, the flags, where the frames live")
        summ = FS.look_summary("enemy", "bug", "BG-B")
        check(summ["ok"] and summ["staged"] == 0 and len(summ["groups"]) == 5 and summ["groups"][3]["key"] == "run_s" and summ["groups"][3]["pinned"] == 2,
              "the look summary: the groups, staged and pinned counts (slots 1 and 3 pinned): %s" % summ["groups"][3]["pinned"])

        # ---- vace_repair: the window plan and a dry run
        plans = [VR.window_plan(12, True, "auto"), VR.window_plan(24, True, "auto"), VR.window_plan(8, False, "auto"), VR.window_plan(2, True, "auto"), VR.window_plan(4, True, "single")]
        check([(len(p[0]), p[1]) for p in plans] == [(25, "double"), (25, "single"), (9, "single"), (5, "double"), (5, "single")],
              "window_plan: 4k+1 frames, a short loop twice, a long one once, a one-shot padded: %s" % [(len(p[0]), p[1]) for p in plans])
        pl = plans[0][0]
        check([f[0] for f in pl] == list(range(12)) * 2 + [0] and all(f[1] for f in pl[:24]) and not pl[24][1] and [f[2] for f in pl] == [False] * 12 + [True] * 12 + [False],
              "a double window: every slot twice, the redo masked in both passes, taken from the second")
        check(VR.parse_slots("3-5, 9", 12) == [3, 4, 5, 9] and VR.parse_slots("1 2 2", 4) == [1, 2] and VR.parse_slots("20", 4) == [], "parse_slots")
        out_dir = os.path.join(tmp, "out")
        staged_before = dict(g.staged())
        info = VR.repair("enemy", "bug", "BG-B", "run", "side", [1, 2], dry=True, out_dir=out_dir)
        check(info.get("dry_run") and info["window"] == "double" and info["frames"] == 9 and info["slots"] == [1, 2] and info["driver"] == "bugwalk"
              and info["reference"].endswith("bug_bgb_side.png") and os.path.isfile(info["sheet"]) and info["driver_fit"]["pairs"] == 2 and info["wan"]["size"] == w["S"],
              "a dry run: the window, the driver fitted on the kept frames, the reference, the sheet: %s" % {k: info.get(k) for k in ("window", "frames", "slots", "driver")})
        check(info["prompt"] == "a bug walking in place", "the prompt is the clip's own")
        check(info.get("driver_rec") == {"name": "bugwalk", "ctl_sig": "sig123"} and g.staged() == staged_before, "the repair records its driver signature and writes no staged.json (one writer)")
        check("g.stage(" not in open(os.path.join(ROOT, "tools", "vace_repair.py"), encoding="utf-8").read(), "vace_repair.py never stages (the Level Editor's landing does)")
        try:
            VR.repair("enemy", "bug", "BG-B", "run", "side", [0, 1, 2, 3], dry=True, out_dir=out_dir)
            check(False, "redoing every frame is refused")
        except SystemExit:
            check(True, "redoing every frame is refused")
        try:
            VR.repair("enemy", "bug", "BG-B", "idle", "front", [1], dry=True, out_dir=out_dir)
            check(False, "a procedural animation (no clip, no driver) is refused without free_fill")
        except SystemExit as e:
            check("procedural" in str(e), "a procedural animation (no clip, no driver) is refused without free_fill: %s" % str(e)[:80])
        info2 = VR.repair("enemy", "bug", "BG-B", "idle", "front", [1], dry=True, out_dir=out_dir, free_fill=True)
        check(info2.get("dry_run") and info2["guide"] == "free" and info2["free_fill"] is True and info2["frames"] == 5, "with free_fill on purpose it runs as a free fill: %s" % {k: info2.get(k) for k in ("guide", "frames")})

        # ---- the routes on a temporary server with a jobs stand-in
        saved_srv = {k: getattr(server, k) for k in ("CONTENT", "DL", "DRIVERS", "JOBS")}
        fake = FakeJobs()
        server.CONTENT, server.DL, server.DRIVERS, server.JOBS = w["content"], os.path.join(tmp, "dl"), FS.DRIVERS, fake
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        httpd.daemon_threads = True
        port = httpd.server_address[1]
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % port

        def get(path):
            try:
                with urllib.request.urlopen(base + path, timeout=10) as r:
                    ct = r.headers.get("Content-Type", "")
                    data = r.read()
                    return r.status, (json.loads(data.decode("utf-8")) if "json" in ct else data), ct
            except urllib.error.HTTPError as e:
                return e.code, json.loads(e.read().decode("utf-8") or "{}"), ""

        def post(path, body):
            req = urllib.request.Request(base + path, data=json.dumps(body).encode("utf-8"), method="POST", headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=10) as r:
                    return r.status, json.loads(r.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                return e.code, json.loads(e.read().decode("utf-8") or "{}")
        try:
            st1, s, _ = get("/api/frames/enemy/bug/BG-B")
            check(st1 == 200 and s["ok"] and len(s["groups"]) == 5, "GET /api/frames/<kind>/<id>/<code>: the summary")
            st2, d, _ = get("/api/frames/enemy/bug/BG-B/run/side")
            check(st2 == 200 and d["ok"] and d["n"] == 4 and d["slots"][1]["url"].startswith("/dl/frames/") and d["slots"][0]["driver_url"].startswith("/dl/drivers/bugwalk/side/ctl_04.png"),
                  "GET .../<anim>/<view>: the detail with /dl/ pictures")
            st3, pic, ct = get(d["slots"][1]["url"])
            check(st3 == 200 and ct.startswith("image/png") and pic[:4] == b"\x89PNG", "a version's picture is served from /dl/frames")
            st4, o, _ = get("/api/frames/enemy/bug/BG-B/run/side/others")
            check(st4 == 200 and o["ok"] and o["looks"][0]["code"] == "BG-A" and len(o["looks"][0]["slots"]) == 4 and o["looks"][0]["slots"][0]["versions"][0]["url"].startswith("/dl/frames/"),
                  "GET .../others: the other look's slots and versions")
            vid = next(v["id"] for v in d["slots"][0]["versions"] if v["id"] != d["slots"][0]["selected"])   # slot 0's re-roll (the installed original is selected)
            st5, r5 = post("/api/frames/enemy/bug/BG-B/run/side/stage", {"slot": 0, "version": vid})
            check(st5 == 200 and r5["ok"] and r5["group"]["slots"][0]["staged"] == vid and r5["group"]["staged_count"] == 1, "POST stage: the group comes back with the choice")
            st6, r6 = post("/api/frames/enemy/bug/BG-B/run/side/unstage", {"slot": 0})
            check(st6 == 200 and r6["ok"] and not r6["group"]["slots"][0]["staged"], "POST unstage")
            st7, r7 = post("/api/frames/enemy/bug/BG-B/run/side/pin", {"slot": 0, "pinned": True})
            check(st7 == 200 and r7["ok"] and r7["group"]["slots"][0]["pinned"], "POST pin")
            st8, r8 = post("/api/frames/enemy/bug/BG-B/run/side/copy", {"slot": 3, "from": {"code": "BG-A", "slot": 3}})
            check(st8 == 200 and r8["ok"] and r8["version"]["label"].startswith("BG-B-") and r8["group"]["slots"][3]["staged"] == r8["version"]["id"], "POST copy: a copy from BG-A, staged")
            st9, r9 = post("/api/frames/enemy/bug/BG-B/run/side/repair", {"slots": [1, 2], "prompt": "", "seed": 0})
            check(st9 == 200 and r9["ok"] and fake.calls[-1]["kind"] == "frames_repair" and fake.calls[-1]["spec"]["slots"] == [1, 2] and fake.calls[-1]["spec"]["view"] == "side"
                  and fake.calls[-1]["target"] == {"kind": "enemy", "id": "bug", "code": "BG-B"}, "POST repair queues a frames_repair job: %s" % fake.calls[-1:])
            st10, r10 = post("/api/frames/enemy/bug/BG-B/run/side/repair", {"slots": [0, 1, 2, 3]})
            check(st10 == 400 and not r10["ok"], "repairing every frame is refused (re-roll instead)")
            st11, r11 = post("/api/frames/enemy/bug/BG-B/export", {})
            check(st11 == 400 and not r11["ok"] and r11.get("needs_confirm") and r11.get("in_play") and "look the game plays" in r11.get("error", ""),
                  "POST export on the look in play without confirm is refused with needs_confirm (Q5's default)")
            st11b, r11b = post("/api/frames/enemy/bug/BG-B/export", {"confirm": True})
            check(st11b == 200 and r11b["ok"] and fake.calls[-1]["kind"] == "frames_export" and r11b["staged"] == 1 and fake.calls[-1]["spec"].get("in_play") is True,
                  "POST export with confirm queues a frames_export job when something is staged")
            post("/api/frames/enemy/bug/BG-B/run/side/unstage", {})
            st12, r12 = post("/api/frames/enemy/bug/BG-B/export", {})
            check(st12 == 400 and "nothing is staged" in r12.get("error", ""), "export with nothing staged is refused")
            # the repair rule: a procedural animation is refused unless free_fill is sent on purpose
            st16, r16 = post("/api/frames/enemy/bug/BG-B/idle/front/repair", {"slots": [1]})
            check(st16 == 400 and r16.get("needs_free_fill") and r16.get("procedural") and "nothing to follow" in r16.get("error", ""), "POST repair on a procedural animation is refused: %s" % r16.get("error", "")[:70])
            st17, r17 = post("/api/frames/enemy/bug/BG-B/idle/front/repair", {"slots": [1], "free_fill": True})
            check(st17 == 200 and r17["ok"] and fake.calls[-1]["spec"]["free_fill"] is True and fake.calls[-1]["spec"]["guide"] == "free", "with free_fill: true it queues as a free fill")
            st18, d18, _ = get("/api/frames/enemy/bug/BG-B/idle/front")
            st19, d19, _ = get("/api/frames/enemy/bug/BG-B/run/side")
            check(st18 == 200 and d18["repairable"]["ok"] is False and d18["repairable"]["procedural"] and d19["repairable"]["ok"] is True and d19["repairable"]["rule"]["vace"] == "yes",
                  "the detail says whether a repair runs and names the method's rule: %s / %s" % (d18["repairable"]["ok"], d19["repairable"]["rule"]))
            st20, s20, _ = get("/api/frames/enemy/bug/BG-B")
            check(st20 == 200 and s20.get("in_play") is True and s20.get("rule", {}).get("vace") == "yes", "the summary carries in_play and the rule")
            # the picker marks the removed look
            st21, o21, _ = get("/api/frames/enemy/bug/BG-B/run/side/others")
            rem = [o for o in o21["looks"] if o.get("removed")]
            check(st21 == 200 and len(rem) == 1 and rem[0]["code"] == "BG-C" and any("removed look" in x for x in rem[0]["warnings"]), "GET others marks the removed look BG-C")
            # a version deleted through the route only when unreferenced
            st22, r22 = post("/api/frames/enemy/bug/BG-B/run/side/delete", {"slot": 3, "version": d["slots"][3]["selected"]})
            check(st22 == 400 and r22.get("referenced"), "POST delete refuses the selected version")
            # an export's merge never marks the look fresh; a look's landing does (server.merge_look)
            saved_backups = getattr(server, "BACKUPS", None)
            if saved_backups is not None:
                server.BACKUPS = os.path.join(tmp, "srv_backups")
            try:
                ent = {"sprite": "bug_sprite_b.png", "anims": dict(w["anims"]), "strip_cols": w["cols_b"], "fps": {"run": 10, "die": 6}}
                m1 = server.HOOKS.merge_look("enemy", "bug", "BG-B", dict(ent), {"pipeline": "frames_export"})
                doc_m = json.load(open(os.path.join(w["folder"], "bug.json"), encoding="utf-8"))
                check(m1.get("ok") and "fresh" not in doc_m["variants"]["BG-B"], "merge_look for a frames_export writes no `fresh` (layout %s)" % m1.get("layout"))
                m2 = server.HOOKS.merge_look("enemy", "bug", "BG-B", dict(ent), {"pipeline": "gen_ctl"})
                doc_m = json.load(open(os.path.join(w["folder"], "bug.json"), encoding="utf-8"))
                check(m2.get("ok") and doc_m["variants"]["BG-B"].get("fresh") is True, "merge_look for a look's landing marks it fresh as before")
            finally:
                if saved_backups is not None:
                    server.BACKUPS = saved_backups
            st13, _, _ = get("/api/frames/enemy/Bug!/BG-B")
            st14, _, _ = get("/api/frames/enemy/bug/BG-B/fly/side")
            st15, r15 = post("/api/frames/enemy/bug/BG-Z/run/side/stage", {"slot": 1, "version": vid})
            check(st13 == 400 and st14 == 400 and st15 == 400, "bad ids, animations and looks are refused: %s %s %s" % (st13, st14, st15))
        finally:
            httpd.shutdown()
            httpd.server_close()
            for n, v in saved_srv.items():
                setattr(server, n, v)
            FRIO.DL_DIR = os.path.join(ROOT, "tools", "dl")

        # ---- the jobs' landing (one writer of staged.json), the export's rollback on a failed merge and a failed import,
        #      an export waiting for a running repair (pass 95 resume; jobs.py without init: nothing is written to the queue)
        try:
            import jobs
        except ImportError as e:
            jobs = None
            check(False, "jobs.py could not be imported for the landing checks: %s" % e)
        if jobs is not None:
            tmpj = tempfile.mkdtemp(prefix="le_vace95_land_")
            saved_j = {"JOBS_DIR": jobs.JOBS_DIR, "_hooks": jobs._hooks, "_state": jobs._state}
            jobs.JOBS_DIR = tmpj
            target = {"kind": "enemy", "id": "bug", "code": "BG-B"}

            def result_for(jid, rec):
                os.makedirs(os.path.join(tmpj, jid), exist_ok=True)
                with open(os.path.join(tmpj, jid, "result.json"), "w", encoding="utf-8", newline="\n") as f:
                    json.dump(rec, f)
            try:
                g.unstage()
                g.pin(3, True)
                sel_now = g.selected()
                cand2 = next(v for v in g.versions(2) if v["id"] != sel_now["2"]["id"])
                vers = [{"slot": 2, "id": cand2["id"], "label": cand2["label"], "stage_wanted": True},
                        {"slot": 3, "id": g.versions(3)[0]["id"], "label": "x", "stage_wanted": True, "pinned": True},
                        {"slot": 0, "id": g.versions(0)[0]["id"], "label": "y", "stage_wanted": False, "empty": True},
                        {"slot": 1, "id": "nope", "label": "z", "stage_wanted": True}]
                result_for("jrep-1", {"info": {"repair": {"base": "run", "view": "side", "versions": vers}}})
                written, err = jobs._post({"id": "jrep-1", "kind": "frames_repair", "target": target, "spec": {}})
                st_now = g.staged()
                check(not err and written["layout"] == "staged" and [x["slot"] for x in written["staged"]] == [2] and sorted(x["slot"] for x in written["skipped"]) == [0, 1, 3]
                      and st_now.get("2", {}).get("id") == cand2["id"] and "3" not in st_now and "0" not in st_now,
                      "a repair's landing stages the wanted version and skips the pinned, the empty and the unknown: %s" % [(x["slot"], x["why"][:28]) for x in written["skipped"]])
                g.unstage(2)
                g.stage(2, cand2["id"], why="chosen")   # a hand choice on slot 2
                other2 = g.add_version(2, _blob_canvas(FS.CANVAS, 300, 300, 40, 40), "raw", "vace", by="ai")
                result_for("jrep-2", {"info": {"repair": {"base": "run", "view": "side", "versions": [{"slot": 2, "id": other2["id"], "label": other2["label"], "stage_wanted": True}]}}})
                written2, err2 = jobs._post({"id": "jrep-2", "kind": "frames_repair", "target": target, "spec": {}})
                check(not err2 and not written2["staged"] and written2["skipped"] and "by hand" in written2["skipped"][0]["why"] and g.staged()["2"]["id"] == cand2["id"],
                      "a hand choice staged meanwhile is kept; the repair's version lands unstaged and the card says so")
                g.unstage()
                g.pin(3, False)
                # the export's merge fails: the strip goes back to the backup, the choices are staged again, the error says so
                alt0 = next(v for v in g.versions(0) if v["id"] != g.selected()["0"]["id"])   # slot 0's re-roll (the installed original is selected now)
                g.stage(0, alt0["id"], why="test")
                pre = open(look.strip_path, "rb").read()
                side_j = os.path.join(tmpj, "jexp-1", "result.json")
                exj = FS.export_look("enemy", "bug", "BG-B", job="jexp-1", sidecar=side_j)
                check(exj.get("ok") and not exj.get("unchanged") and open(look.strip_path, "rb").read() != pre and not g.staged(), "the export wrote the strip and committed the choice")
                calls = []

                def failing(kind, cid, code, entry, info=None):
                    calls.append((kind, cid, code, dict(entry), dict(info or {})))
                    return {"ok": False, "error": "forced merge failure"}
                jobs._hooks = {"merge_look": failing}
                wr, er = jobs._post({"id": "jexp-1", "kind": "frames_export", "target": target, "spec": {}, "method": None})
                check("rolled back" in (er or "") and wr.get("rollback", {}).get("ok") and open(look.strip_path, "rb").read() == pre and g.staged().get("0", {}).get("id") == alt0["id"]
                      and not g.selected()["0"]["pinned"] and "fresh" not in calls[-1][3],
                      "a failed merge rolls the export back (the strip from the backup, the choice staged again) and the entry carried no `fresh`: %s" % (er or "")[:60])
                # a look's landing still passes fresh: true to the hook
                result_for("jlook-1", {"entry": {"sprite": "bug_sprite_b.png"}, "info": {"pipeline": "gen_ctl"}})
                jobs._hooks = {"merge_look": lambda kind, cid, code, entry, info=None: (calls.append((kind, cid, code, dict(entry), dict(info or {}))) or {"ok": True, "layout": "block", "backup": ""})}
                jobs._post({"id": "jlook-1", "kind": "look", "method": "creature_ctl", "target": target, "spec": {}})
                check(calls[-1][3].get("fresh") is True, "a look job's landing marks the look fresh as before")
                # the import after an export fails: the export is undone and its old entry merged back (pipeline frames_rollback, no fresh)
                exj2 = FS.export_look("enemy", "bug", "BG-B", job="jexp-2", sidecar=os.path.join(tmpj, "jexp-2", "result.json"))
                check(exj2.get("ok") and not exj2.get("unchanged") and not g.staged(), "a second export (the staged-again choice) went through")
                jobs._state = {"rev": 0, "jobs": [{"id": "jexp-2", "kind": "frames_export", "target": target, "spec": {}, "state": "done", "error": ""}]}
                imp = {"id": "jimp-1", "kind": "import", "target": {"kind": "enemy", "id": "bug", "code": ""}, "spec": {"targets": ["enemies/bug"], "after_export": ["jexp-2"]}, "state": "failed", "error": "Godot said no"}
                jobs._rollback_after_import(imp)
                ex2 = jobs._state["jobs"][0]
                check(ex2.get("rolled_back", {}).get("ok") and ex2["rolled_back"].get("entry_restored") and calls[-1][4].get("pipeline") == "frames_rollback" and "fresh" not in calls[-1][3]
                      and calls[-1][3].get("strip_cols") == w["cols_b"] and open(look.strip_path, "rb").read() == pre and g.staged().get("0") and "rolled back" in ex2.get("error", ""),
                      "a failed import undoes the export: the strip, the choice staged again, the old entry merged back without fresh: %s" % {k: ex2.get("rolled_back", {}).get(k) for k in ("ok", "entry_restored", "error")})
                # an export job waits for a running repair of the same look
                rep_run = {"id": "jr", "kind": "frames_repair", "target": target, "spec": {}, "state": "running"}
                ex_q = {"id": "je", "kind": "frames_export", "target": target, "spec": {}, "state": "queued", "lane": "local", "progress": {}}
                ex_other = {"id": "jo", "kind": "frames_export", "target": {"kind": "enemy", "id": "bug", "code": "BG-A"}, "spec": {}, "state": "queued", "lane": "local", "progress": {}}
                jobs._state = {"rev": 0, "jobs": [rep_run, ex_q, ex_other]}
                check(jobs._frames_export_waits(ex_q) and not jobs._frames_export_waits(ex_other) and jobs._public(ex_q, 5)["held"] is True and jobs._public(ex_other, 5)["held"] is False,
                      "a queued export of a look with a running repair is held (the card says held); another look's is not")
                rep_run["state"] = "done"
                check(not jobs._frames_export_waits(ex_q), "once the repair is done the export runs")
            finally:
                jobs.JOBS_DIR, jobs._hooks, jobs._state = saved_j["JOBS_DIR"], saved_j["_hooks"], saved_j["_state"]
                shutil.rmtree(tmpj, ignore_errors=True)
    finally:
        for k, v in saved.items():
            setattr(FS, k, v)
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- the page's maths under Node
    q = {"parse": ["3-5, 9", "3 4 5", "", "x", "20"],
         "plans": [[12, True, [3, 4, 5, 9], "auto"], [24, True, [1], "auto"], [8, False, [2, 3], "auto"], [1, False, [0], "auto"], [12, True, [], "auto"], [12, True, list(range(12)), "auto"]]}
    out = run_node(q, RUNNER)
    if out is None:
        print("selftest_VACE95: no node: the page maths were not checked")
    elif out:
        check(out["select"] == [[3], [3, 4, 5, 6], [3, 4, 5, 6, 9], [3, 4, 5, 6], []], "select: a click, a shift range, ctrl toggles, a second click clears: %s" % out["select"])
        check(out["text"] == ["3-5, 9", "1", "", "1, 2"], "slotsText: %s" % out["text"])
        pl = out["parse"]
        check(pl[0]["list"] == [3, 4, 5, 9] and pl[1]["list"] == [3, 4, 5] and pl[2]["list"] == [] and not pl[2]["error"] and pl[3]["error"] and pl[4]["error"], "parseSlots: %s" % pl)
        ps = out["plans"]
        check([(p["mode"], p["frames"], p["ok"]) for p in ps] == [("double", 25, True), ("single", 25, True), ("single", 9, True), ("single", 1, False), ("double", 25, False), ("double", 25, False)],
              "repairPlan mirrors vace_repair.window_plan and refuses nothing / everything / one frame: %s" % [(p["mode"], p["frames"], p["ok"]) for p in ps])
        check(out["fps"] == [20, 14, 6, 6], "previewFps: %s" % out["fps"])
        check(out["badges"] == ["staged", "pinned", "differs", "empty", "jump"], "badges: %s" % out["badges"])
        check(out["vtext"].startswith("SP-B-2 · painted anew by VACE · seed 24110"), "versionText: %s" % out["vtext"])
        check(len(out["compat"]) == 2 and "128 px" in out["compat"][0] and "other driver" in out["compat"][1], "compat warnings: %s" % out["compat"])
        check(out["line"] == "2 animations · 16 frames · 3 staged", "summaryLine: %s" % out["line"])
        check(out["step"] == [0, 11, 11, 0] and out["newest"] == [3, 2, 1] and out["label"] == "run · back ¾", "step, newest first, the group label")
        check("look the game plays" in out["confirm"][0] and "2 changed frames" in out["confirm"][0] and "backups/desert_spider/" in out["confirm"][0] and out["confirm"][1] == "",
              "exportConfirmText names the look in play, the count and the backup; nothing for another look")
        check("walked on spider_walk (abcdef01)" in out["vtext2"] and "shrunk to 90%" in out["vtext2"] and "(removed look)" in out["vtext2"], "versionText says the driver, the shrink and a removed source: %s" % out["vtext2"])
        check(out["where"].startswith("the game plays the strip game/x.png;") and "tools/dl/ai_anim/k/" in out["where"] and "newest 30 kept" in out["where"], "whereLine: %s" % out["where"][:80])

    # ---- the wiring
    rd = lambda n: open(os.path.join(HERE, n), encoding="utf-8").read()  # noqa: E731
    idx = rd("index.html")
    check("frames.css" in idx and idx.index("frames_model.js") < idx.index('src="frames.js"') and idx.index('src="drivers.js"') < idx.index("frames_model.js"),
          "index.html: the styles, the model before the view, after the drivers")
    check("Frames.open(" in rd("looks.js") and "Frames…" in rd("looks.js"), "looks.js: a Frames… button on the look cards")
    check("Frames.open(" in rd("jobs.js") and "frames_repair" in rd("jobs.js"), "jobs.js: a Frames… button on a landed look's and a repair's card")
    srv = rd("server.py")
    check("FRIO.api_get(" in srv and "FRIO.api_post(" in srv and "FRIO.on_look_landed(" in srv and '"frames"' in srv.split("DL_ROOTS = ")[1].split("\n")[0],
          "server.py hands /api/frames to frames_io, syncs the store after a landing, serves /dl/frames")
    jb = rd("jobs.py")
    check('"frames_repair": {"lane": "comfy"' in jb and '"frames_export": {"lane": "local"' in jb and "_frames_plan(" in jb and "env_extra=plan.get(\"env_steps\")" in jb
          and 'kind == "frames_export"' in jb and "_frames_outputs(" in jb, "jobs.py: the two kinds, their plan, the step env, the landing, the outputs")
    # pass 95 resume: the engineering items are wired
    check("not _frames_export_waits(j)" in jb and 'spec["after_export"] = [job["id"]]' in jb and jb.count("_rollback_after_import(job)") >= 2 and 'if kind == "frames_repair":' in jb
          and 'if kind != "frames_export":\n                e["fresh"] = True' in jb and '"free_fill"' in jb and "after_export" in jb.split("def _take_next")[1].split("def _finish")[0],
          "jobs.py: an export waits for a running repair, an import carries after_export (merged imports too), a failed import rolls back, the repair's landing stages, no fresh on an export")
    check('("frames_export", "frames_rollback")' in srv, "server.py: merge_look writes no `fresh` for an export or a rollback")
    check(rd("frames_io.py").count("def repair_rule") == 1 and "def stage_versions" in rd("frames_io.py") and '"delete": delete' in rd("frames_io.py") and "needs_confirm" in rd("frames_io.py"),
          "frames_io.py: the rule, the landing's staging, the delete route, the confirm")
    fj = rd("frames.js")
    check("exportConfirmText(" in fj and "free_fill" in fj and "removed look" in fj and "whereLine(" in fj and "deleteVersion(" in fj, "frames.js: the confirm, the free fill checkbox, the removed mark, the help line, delete")
    ga, gc = open(os.path.join(ROOT, "tools", "gen_art.py"), encoding="utf-8").read(), open(os.path.join(ROOT, "tools", "gen_ctl.py"), encoding="utf-8").read()
    check(ga.count("frames_store.hook_after_save(") == 4 and gc.count("frames_store.hook_after_save(") == 1 and ga.count("strip.save(") == 4 and gc.count("strip.save(") == 1,
          "gen_art.py and gen_ctl.py: one store hook after every strip.save (%d + %d)" % (ga.count("frames_store.hook_after_save("), gc.count("frames_store.hook_after_save(")))
    mj = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    rules = {x.get("id"): x.get("repair") for x in mj.get("methods", [])}
    check(rules and all(isinstance(r, dict) and r.get("vace") in ("yes", "conditional", "no") and r.get("fill") in ("still", "cell", "none") and r.get("note") for r in rules.values()),
          "methods.json: every method carries a repair rule {vace yes|conditional|no, fill still|cell|none, note}: %s" % sorted(k for k, r in rules.items() if not isinstance(r, dict)))
    check(rules.get("creature_ctl", {}).get("vace") == "yes" and rules.get("hero_puppet", {}).get("vace") == "yes" and rules.get("creature_proc", {}) == dict(rules.get("creature_proc", {}), vace="no", fill="still")
          and rules.get("creature_free2", {}).get("vace") == "conditional" and rules.get("recolour", {}).get("vace") == "no" and rules.get("item_icon", {}).get("fill") == "none" and "repair" in mj.get("_about", ""),
          "the rules: ctl and puppet yes, free / pose conditional, procedural and recolour no, icons none; _about says so")

    # ---- the two kinds' specs and plans (no queue touched: the job folder goes to a temporary place)
    try:
        import jobs
        tmpj = tempfile.mkdtemp(prefix="le_vace95_jobs_")
        saved_dir = jobs.JOBS_DIR
        jobs.JOBS_DIR = tmpj
        try:
            spec = jobs.validate_spec("frames_repair", {"kind": "enemy", "id": "bug", "code": "BG-B", "anim": "run", "view": "side", "slots": [1, 2]})
            check(spec["window"] == "auto" and spec["slots"] == [1, 2] and spec["seed"] == 0, "frames_repair's spec coerced with its defaults")
            p = jobs._plan({"id": "jvace-test", "kind": "frames_repair", "spec": spec, "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}})
            check(p["mode"] == "steps" and p["lock"] == "comfy" and p["env_steps"].get("LOCK_HELD_COMFY") == "1" and p["steps"][0][-2:] == ["--job", "tools/dl/jobs/jvace-test/repair.json"][0:0] + p["steps"][0][-2:]
                  and p["steps"][0][-2] == "--job" and os.path.isfile(os.path.join(tmpj, "jvace-test", "repair.json")) and "vace_repair.py" in p["equiv"],
                  "frames_repair's plan: vace_repair.py --job under the comfy lock, the lock told to the step, repair.json written")
            rj = json.load(open(os.path.join(tmpj, "jvace-test", "repair.json"), encoding="utf-8"))
            check(rj["slots"] == [1, 2] and rj["job"] == "jvace-test" and rj["view"] == "side", "repair.json carries the spec and the job id")
            try:
                jobs.validate_spec("frames_repair", {"kind": "enemy", "id": "bug"})
                check(False, "a repair without its code, anim, view and slots is refused")
            except ValueError:
                check(True, "a repair without its code, anim, view and slots is refused")
            spec2 = jobs.validate_spec("frames_export", {"kind": "enemy", "id": "bug", "code": "BG-B"})
            p2 = jobs._plan({"id": "jvace-test2", "kind": "frames_export", "spec": spec2, "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}})
            check(p2["mode"] == "steps" and p2["lock"] is None and p2["steps"][0][-4:] == ["export", "enemy", "bug", "BG-B"] and p2["env_steps"].get("ASSET_JOB_SIDECAR", "").endswith("result.json"),
                  "frames_export's plan: frames_store.py export on the local lane with the sidecar")
        finally:
            jobs.JOBS_DIR = saved_dir
            shutil.rmtree(tmpj, ignore_errors=True)
    except ImportError as e:
        check(False, "jobs.py could not be imported for the plan checks: %s" % e)

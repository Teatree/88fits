"""Pass 93, lane PREVIEW: the driver library and its viewer (Garry: "I only see names and can't tell what the actual
animation will look like ... this preview should also include the frame index somewhere").

Groups: drivers_io on a temporary drivers folder with every layout on disk (a pose driver with sheets and poses.json, a
depth walk with clay and look, a one-shot death with clay_NN, a softened copy without meta.json, a folder without
frames, a stray file): the listing's kinds, views in the game's order, frame counts per view from the files (not a depth
meta's poses per stride), first indices, stills, made-from, how it plays, size and file count, used_by from content
recipes (pose_drivers, ctl_drivers, drivers, death_drivers, pose, death "pose:<x>"); one driver's detail (every frame's
index and URL, stills, the view's sheet); the routes over HTTP (/api/drivers, /api/drivers/<name>, 404s,
/api/painted_death, POST open with the opener swapped for a recorder, refusals outside the library); the painted death
(tools/dl/ai_anim/<key>_death: full_NN, out_NN, the cached keep) and gen_ctl's key; the page's maths under Node
(drivers_model.js: viewOfKey, pickView, parseList, toggle, clamp, evenPick, playOrder, step, filter, sort,
paintedFits, frameUrl); methods.json's death_keep picker keys; the page's wiring (index.html, app.js, assets.js,
jobs.js). Nothing here writes outside a temporary folder.
"""
import json
import os
import shutil
import sys
import tempfile
import threading
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

PNG = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00"
       b"\x00\rIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82")


def _png(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(PNG)


def _json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f)


def _make_library(tmp):
    drv = os.path.join(tmp, "drivers")
    # a pose walk: five views of 13 frames, sheets, poses.json, meta
    for v in ("back", "bd", "side", "fd", "front"):
        for i in range(13):
            _png(os.path.join(drv, "walkx", v, "driver_%02d.png" % i))
        _json(os.path.join(drv, "walkx", v, "poses.json"), [])
        _png(os.path.join(drv, "walkx", "%s_sheet.png" % v))
    _png(os.path.join(drv, "walkx", "all_sheet.png"))
    _json(os.path.join(drv, "walkx", "meta.json"), {"kind": "pose", "fbx": "walking.fbx", "frames": 12, "loop": True,
                                                    "views": ["back", "bd", "side", "fd", "front"], "spread": {"views": ["back"]}})
    # a depth walk: front and side, 25 frames each (meta frames 12 = poses per stride), clay + look
    for v in ("side", "front"):
        for i in range(25):
            _png(os.path.join(drv, "bugwalk", v, "ctl_%02d.png" % i))
        _png(os.path.join(drv, "bugwalk", v, "clay.png"))
        _png(os.path.join(drv, "bugwalk", v, "look.png"))
    _json(os.path.join(drv, "bugwalk", "meta.json"), {"kind": "depth", "mode": "gait", "loop": False, "frames": 12, "cycles": 2,
                                                      "total": 25, "src": "tools/dl/uploads/3d/bug/bug.glb", "views": ["front", "side"]})
    # a one-shot death: front only, clay_NN key poses
    for i in range(25):
        _png(os.path.join(drv, "bugdeath", "front", "ctl_%02d.png" % i))
    _png(os.path.join(drv, "bugdeath", "front", "clay.png"))
    for k in (6, 12, 24):
        _png(os.path.join(drv, "bugdeath", "front", "clay_%02d.png" % k))
    _json(os.path.join(drv, "bugdeath", "meta.json"), {"kind": "depth", "mode": "death", "action": "Bug|death", "frames": 12,
                                                       "total": 25, "loop": False, "views": ["front"]})
    # gen_ctl's softened copy: no meta.json, one view
    for i in range(25):
        _png(os.path.join(drv, "bugwalk_soft10", "front", "ctl_%02d.png" % i))
    _png(os.path.join(drv, "bugwalk_soft10", "front", "clay.png"))
    # no frames at all, and a stray log beside the folders
    os.makedirs(os.path.join(drv, "empty_one", "front"), exist_ok=True)
    with open(os.path.join(drv, "stray.log"), "w") as f:
        f.write("x")
    # content that names them
    content = os.path.join(tmp, "content")
    _json(os.path.join(content, "enemies", "bug", "bug.json"), {
        "id": "bug", "variant": "BG-B", "variant_base": "BG-A", "pose": "walkx", "death": "pose:walkx",
        "variants": {"BG-A": {"recipe": {}}, "BG-B": {"recipe": {"method": "creature_ctl", "drivers": "bugwalk", "death_drivers": "bugdeath"}},
                     "BG-C": {"recipe": {"drivers": "bugwalk"}}}})
    _json(os.path.join(content, "characters", "hx", "hx.json"), {
        "id": "hx", "variant": "HX-A", "variants": {"HX-A": {"recipe": {"pose_drivers": {"back": "walkx", "bd": "walkx"}, "ctl_drivers": {"fd": "bugwalk"}}}}})
    # a painted death in ai_anim
    anim = os.path.join(tmp, "dl", "ai_anim")
    key = "bug_bgb_death"
    for i in range(25):
        _png(os.path.join(anim, key, "full_%02d.png" % i))
    for i in range(8):
        _png(os.path.join(anim, key, "out_%02d.png" % i))
    _json(os.path.join(anim, key, "cycle.json"), {"keep": [1, 4, 7, 10, 13, 16, 20, 24], "seed": 5, "ctl_dir": os.path.join(drv, "bugdeath", "front")})
    return drv, content, anim


RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const D = require(path.join(dir, 'drivers_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.views = q.keys.map((k) => D.viewOfKey(k));
  out.pick = [D.pickView(['front', 'side'], 'back'), D.pickView(['front', 'side'], 'front'), D.pickView(['back'], null), D.pickView([], 'x')];
  out.parse = q.parse.map((v) => D.parseList(v));
  out.toggle = [D.toggle([1, 4, 7], 5), D.toggle([1, 4, 7], 4), D.toggle([], 3), D.toggle([7, 1], 0), D.toggle(null, 2)];
  out.clamp = D.clamp([3, 30, 3, -1, 24, 2.5], 25);
  out.even = [D.evenPick(25, 8), D.evenPick(5, 8), D.evenPick(0, 8), D.evenPick(13, 1)];
  out.play = D.playOrder([24, 1, 30, 1], 25);
  out.step = [D.step(0, 5, -1, true), D.step(4, 5, 1, true), D.step(4, 5, 1, false), D.step(0, 5, -1, false), D.step(2, 0, 1, true)];
  out.filter = [D.filter(q.lib, '', 'depth').map((d) => d.name), D.filter(q.lib, '', 'death').map((d) => d.name), D.filter(q.lib, 'bug BG-B', 'all').map((d) => d.name),
    D.filter(q.lib, '', 'unused').map((d) => d.name), D.filter(q.lib, '', 'pose').map((d) => d.name)];
  out.sort = [D.sort(q.lib, 'size').map((d) => d.name), D.sort(q.lib, 'name').map((d) => d.name)];
  out.fits = [D.paintedFits('tools/dl/drivers/bugdeath/front', 'bugdeath'), D.paintedFits('C:\\t\\drivers\\bugdeath_soft10b\\front', 'bugdeath'),
    D.paintedFits('tools/dl/drivers/other/front', 'bugdeath'), D.paintedFits('tools/dl/drivers/bugdeath_softer/front', 'bugdeath'), D.paintedFits(null, 'bugdeath')];
  out.url = [D.frameUrl('/dl/drivers/a/front/ctl_%02d.png', 7), D.frameUrl(D.framePattern({ name: 'a', kind: 'pose' }, 'side'), 12)];
  out.keepText = [D.keepText([1, 4, 7, 10, 13, 16, 20, 24], D.DEATH_KEEP_DEFAULT), D.keepText(null, [1, 2]), D.keepText([3], null)];
  out.size = [D.sizeText(512), D.sizeText(2048), D.sizeText(5 * 1024 * 1024)];
  process.stdout.write(JSON.stringify(out));
});
"""


def checks(check, run_node, server):
    import drivers_io as DIO

    tmp = tempfile.mkdtemp(prefix="le_preview93_")
    try:
        drv, content, anim = _make_library(tmp)
        lib = DIO.list_drivers(drv, content)
        by = {d["name"]: d for d in lib}
        check(sorted(by) == ["bugdeath", "bugwalk", "bugwalk_soft10", "walkx"], "the listing: every folder with frames, with or without meta.json; no empty folder, no stray file: %s" % sorted(by))
        w = by["walkx"]
        check(w["kind"] == "pose" and w["views"] == ["back", "bd", "side", "fd", "front"] and w["frames"] == 13 and w["counts"]["front"] == 13,
              "a pose driver: its kind, the meta's view order, 13 frames on disk per view: %s %s" % (w["views"], w["counts"]))
        check(w["frame_pattern"] == "driver_%02d.png" and w["frames_url"] == "/dl/drivers/walkx/<view>/" and w["sheet"] == "/dl/drivers/walkx/all_sheet.png"
              and w["sheets"]["side"] == "/dl/drivers/walkx/side_sheet.png", "the keys the pass 66 listing had are still there")
        check("walking.fbx" in w["made"] and "spread=" in w["made"] and '"views"' in w["made"] and w["plays"] == "loop" and not w["death"],
              "made from: the model, the tweak (as JSON), loops: %s" % w["made"])
        b = by["bugwalk"]
        check(b["kind"] == "depth" and b["views"] == ["front", "side"] and b["frames"] == 25 and b["meta"]["frames"] == 12,
              "a depth walk counts its 25 files, not the meta's 12 poses a stride: %s" % b["counts"])
        check(b["plays"] == "loop" and b["loop"] is False, "a made gait walk loops in the viewer although its meta says loop false (pass 92's meta)")
        check(b["stills_count"] == {"front": 2, "side": 2}, "clay and look are the stills: %s" % b["stills_count"])
        d = by["bugdeath"]
        check(d["death"] and d["plays"] == "once" and d["views"] == ["front"] and d["stills_count"]["front"] == 4,
              "a death plays once, front only, clay + three clay_NN stills: %s" % d["stills_count"])
        s = by["bugwalk_soft10"]
        check(not s["has_meta"] and s["parent"] == "bugwalk" and s["kind"] == "depth" and "softened copy of bugwalk" in s["made"] and "10 px" in s["made"],
              "a softened copy without meta.json: its parent, its kind, what made it: %s" % s["made"])
        check(s["plays"] == "loop" and s["source"] == "tools/dl/uploads/3d/bug/bug.glb", "the copy takes its parent's source and plays as a walk")
        on_disk = sum(os.path.getsize(os.path.join(dp, f)) for dp, _dn, fn in os.walk(os.path.join(drv, "walkx")) for f in fn)
        check(w["size"] == on_disk and w["files"] == 5 * 13 + 5 + 5 + 1 + 1,
              "size and files: frames, poses.json, sheets, all_sheet, meta.json: %d files, %d bytes" % (w["files"], w["size"]))
        check(all(isinstance(x["mtime"], int) and x["mtime"] > 0 for x in lib), "every driver has a date")
        check(w["path"].endswith("drivers/walkx") and w["abs_path"].endswith("drivers/walkx"), "the folder's path: %s" % w["path"])
        u = {x["name"]: x["used_by"] for x in lib}
        keys_w = sorted((r["kind"], r["id"], r["code"], r["key"]) for r in u["walkx"])
        check(keys_w == [("enemy", "bug", "", "death"), ("enemy", "bug", "", "pose"), ("hero", "hx", "HX-A", "pose_drivers.back"), ("hero", "hx", "HX-A", "pose_drivers.bd")],
              "used_by: a creature's own pose and its 'pose:<driver>' death, a hero look's pose_drivers per view: %s" % keys_w)
        keys_b = sorted((r["id"], r["code"], r["key"], r["played"]) for r in u["bugwalk"])
        check(keys_b == [("bug", "BG-B", "drivers", True), ("bug", "BG-C", "drivers", False), ("hx", "HX-A", "ctl_drivers.fd", True)],
              "used_by: recipes' drivers and ctl_drivers, the played look marked: %s" % keys_b)
        check([r["key"] for r in u["bugdeath"]] == ["death_drivers"] and u["bugwalk_soft10"] == [], "death_drivers counted; a copy no recipe names is unused")
        check(next(r for r in u["walkx"] if r["key"] == "pose")["played"] is False, "the creature's own keys count as played only when its base look plays")

        # one driver's detail
        det = DIO.describe(drv, "bugdeath", DIO.used_by_index(content), detail=True)
        fr = det["view_detail"]["front"]["frames"]
        check([f["i"] for f in fr] == list(range(25)) and fr[7]["file"] == "ctl_07.png" and fr[7]["url"].startswith("/dl/drivers/bugdeath/front/ctl_07.png?v="),
              "every frame's index is its file's number, with its URL: %s" % fr[7])
        st = det["view_detail"]["front"]["stills"]
        check([x["label"] for x in st] == ["clay", "clay at frame 6", "clay at frame 12", "clay at frame 24"], "stills in order: %s" % [x["label"] for x in st])
        det_w = DIO.describe(drv, "walkx", {}, detail=True)
        check(any(x["file"] == "side_sheet.png" for x in det_w["view_detail"]["side"]["stills"]) and det_w["view_detail"]["side"]["poses"],
              "a pose view shows its contact sheet as a still and says it has poses.json")
        check(DIO.describe(drv, "empty_one", {}) is None and DIO.describe(drv, "../drivers", {}) is None and DIO.describe(drv, "nope", {}) is None,
              "no frames, a path, a missing folder: no driver")
        det_s = DIO.describe(drv, "bugwalk_soft10", {}, detail=True)
        check(det_s["meta_parent"] and det_s["meta_parent"].get("mode") == "gait", "a copy's detail carries its parent's meta")

        # the painted death
        check(DIO.death_key("bug", "BG-B") == "bug_bgb_death" and DIO.death_key("dune_scorpion", "SC-A") == "dune_scorpion_sca_death", "gen_ctl's death key")
        pd = DIO.painted_death(anim, "bug", "BG-B")
        check(pd["exists"] and [f["i"] for f in pd["frames"]] == list(range(25)) and len(pd["kept"]) == 8 and pd["keep"] == [1, 4, 7, 10, 13, 16, 20, 24],
              "the painted death: 25 full frames by index, 8 kept, the cached keep")
        check(pd["frames"][3]["url"].startswith("/dl/ai_anim/bug_bgb_death/full_03.png"), "the painted frames' URLs: %s" % pd["frames"][3]["url"])
        none = DIO.painted_death(anim, "bug", "BG-C")
        check(none["ok"] and not none["exists"] and none["frames"] == [], "a look without a painted death: exists false")
        check(not DIO.painted_death(anim, "../x", "A")["ok"] and not DIO.painted_death(anim, "bug", "A/B")["ok"], "bad ids refused")

        # open: only library folders, the opener swapped for a recorder
        opened = []
        saved = DIO.OPENER[0]
        DIO.OPENER[0] = lambda p: opened.append(p)
        try:
            r1 = DIO.open_folder(drv, "walkx", "side")
            r2 = DIO.open_folder(drv, None)
            r3 = DIO.open_folder(drv, "..", None)
            r4 = DIO.open_folder(drv, "walkx", "../../x")
            r5 = DIO.open_folder(drv, "nope")
            r6 = DIO.open_folder(drv, None, "side")
        finally:
            DIO.OPENER[0] = saved
        check(r1["ok"] and r2["ok"] and len(opened) == 2 and os.path.realpath(opened[0]) == os.path.realpath(os.path.join(drv, "walkx", "side"))
              and os.path.realpath(opened[1]) == os.path.realpath(drv), "Open folder opens a driver's view and the library: %s" % opened)
        check(not r3["ok"] and not r4["ok"] and not r5["ok"] and not r6["ok"], "outside the library, a missing folder, a view without a driver: refused")

        # the routes over HTTP (a server on a free port, its folders pointed at the temporary ones)
        names = ("DRIVERS", "CONTENT", "DL")
        saved_srv = {n: getattr(server, n) for n in names}
        server.DRIVERS, server.CONTENT, server.DL = drv, content, os.path.join(tmp, "dl")
        DIO.OPENER[0] = lambda p: opened.append(p)
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        th = threading.Thread(target=httpd.serve_forever, daemon=True)
        th.start()
        base = "http://127.0.0.1:%d" % httpd.server_address[1]

        def get(path):
            try:
                with urllib.request.urlopen(base + path, timeout=10) as r:
                    return r.status, json.loads(r.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                return e.code, json.loads(e.read().decode("utf-8") or "{}")

        def post(path, body):
            req = urllib.request.Request(base + path, data=json.dumps(body).encode("utf-8"), method="POST", headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=10) as r:
                    return r.status, json.loads(r.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                return e.code, json.loads(e.read().decode("utf-8") or "{}")
        try:
            st1, body = get("/api/drivers")
            check(st1 == 200 and sorted(d["name"] for d in body) == ["bugdeath", "bugwalk", "bugwalk_soft10", "walkx"], "GET /api/drivers")
            st2, one = get("/api/drivers/bugwalk")
            check(st2 == 200 and one["ok"] and len(one["view_detail"]["side"]["frames"]) == 25 and one["used_by"], "GET /api/drivers/<name>: the detail")
            st3, _ = get("/api/drivers/nope")
            st4, _ = get("/api/drivers/empty_one")
            check(st3 == 404 and st4 == 404, "a missing or frameless driver is a 404")
            st5, pd2 = get("/api/painted_death/bug/BG-B")
            check(st5 == 200 and pd2["exists"] and len(pd2["frames"]) == 25, "GET /api/painted_death/<enemy>/<code>")
            st6, _ = get("/api/painted_death/Bug!/BG-B")
            check(st6 in (400, 404), "a bad id is refused: %s" % st6)
            n0 = len(opened)
            st7, o1 = post("/api/drivers/walkx/open", {"view": "front"})
            st8, o2 = post("/api/drivers/open", {})
            st9, o3 = post("/api/drivers/nope/open", {})
            check(st7 == 200 and o1["ok"] and st8 == 200 and o2["ok"] and st9 == 400 and len(opened) == n0 + 2,
                  "POST open: a driver's view, the library; a missing one refused (%s %s %s)" % (st7, st8, st9))
        finally:
            httpd.shutdown()
            httpd.server_close()
            DIO.OPENER[0] = saved
            for n, v in saved_srv.items():
                setattr(server, n, v)

        # the page's maths under Node
        lib_js = [{"name": x["name"], "kind": x["kind"], "death": x["death"], "made": x["made"], "source": x["source"], "views": x["views"],
                   "used_by": x["used_by"], "size": x["size"], "mtime": x["mtime"]} for x in lib]
        q = {"keys": ["pose_drivers.back", "variants.A.recipe.pose_drivers.fd", "pose", "variants.X.recipe.pose_front", "death_drivers",
                      "variants.X.recipe.death_keep", "drivers", "fit_source"],
             "parse": [[1, 4, 7], "1, 4, 7", "1 4 7", "[2,3]", "", None, "1, x", [1.5], [-1], 5, {"a": 1}],
             "lib": lib_js}
        out = run_node(q, RUNNER)
        if out is None:
            print("selftest_PREVIEW93: no node: the page maths were not checked")
        elif out:
            check(out["views"] == ["back", "fd", "back", "front", "front", "front", "side", "side"], "viewOfKey: %s" % out["views"])
            check(out["pick"] == ["side", "front", "back", None], "pickView: %s" % out["pick"])
            pl = out["parse"]
            check(pl[0]["list"] == [1, 4, 7] and pl[1]["list"] == [1, 4, 7] and pl[2]["list"] == [1, 4, 7] and pl[3]["list"] == [2, 3],
                  "parseList reads arrays, commas, spaces and JSON: %s" % pl[:4])
            check(pl[4]["list"] is None and not pl[4]["error"] and pl[5]["list"] is None and pl[9]["list"] == [5], "empty is no list; one number is a list of one")
            check(all(pl[k]["error"] for k in (6, 7, 8, 10)), "a word, a fraction, a negative, an object: errors: %s" % [pl[k]["error"] for k in (6, 7, 8, 10)])
            check(out["toggle"] == [[1, 4, 5, 7], [1, 7], [3], [0, 7, 1], [2]], "toggle: in by number, out wherever it is: %s" % out["toggle"])
            check(out["clamp"] == {"list": [3, 24], "outside": [30, -1, 2.5]}, "clamp: once each, inside the clip: %s" % out["clamp"])
            check(out["even"] == [[3, 6, 9, 12, 15, 18, 21, 24], [0, 1, 2, 3, 4], [], [12]], "evenPick: the last frame in: %s" % out["even"])
            check(out["play"] == [24, 1], "playOrder keeps the list's order: %s" % out["play"])
            check(out["step"] == [4, 0, 4, 0, 0], "step wraps when looping, stops at the ends when not: %s" % out["step"])
            f = out["filter"]
            check(f[0] == ["bugdeath", "bugwalk", "bugwalk_soft10"] and f[1] == ["bugdeath"] and f[2] == ["bugdeath", "bugwalk"] and f[3] == ["bugwalk_soft10"] and f[4] == ["walkx"],
                  "filter by kind, by words (a look using it), unused: %s" % f)
            check(out["sort"][1] == ["bugdeath", "bugwalk", "bugwalk_soft10", "walkx"] and out["sort"][0][0] in ("bugwalk", "walkx"), "sort: %s" % out["sort"])
            check(out["fits"] == [True, True, False, False, True], "paintedFits: the driver or its softened copy only: %s" % out["fits"])
            check(out["url"] == ["/dl/drivers/a/front/ctl_07.png", "/dl/drivers/a/side/driver_12.png"], "frame URLs: %s" % out["url"])
            check(out["keepText"][0].endswith("(the default)") and out["keepText"][1] == "the default: 1 2" and out["keepText"][2] == "1 frame: 3", "keepText: %s" % out["keepText"])
            check(out["size"] == ["512 B", "2 KB", "5.0 MB"], "sizeText: %s" % out["size"])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # methods.json: death_keep is picked off its death driver's frames
    with open(os.path.join(HERE, "methods.json"), encoding="utf-8") as fh:
        meth = json.load(fh)
    ctl = next((m for m in meth.get("methods", []) if m.get("id") == "creature_ctl"), {})
    dk = next((x for x in ctl.get("recipe_fields", []) if x.get("key") == "death_keep"), {})
    check(dk.get("type") == "json" and dk.get("picker") == "frames" and dk.get("frames_of") == "death_drivers" and dk.get("view") == "front"
          and dk.get("default") == [1, 4, 7, 10, 13, 16, 20, 24], "methods.json: death_keep's picker keys and gen_ctl's default")
    # the page's wiring
    rd = lambda n: open(os.path.join(HERE, n), encoding="utf-8").read()  # noqa: E731
    idx = rd("index.html")
    check('data-tab="drivers"' in idx and 'id="tab-drivers"' in idx and idx.index("drivers_model.js") < idx.index('src="drivers.js"') and "drivers.css" in idx,
          "index.html: the Drivers tab, its panel, its scripts in order, its styles")
    check("Drivers.render(panel)" in rd("app.js"), "app.js draws the Drivers tab")
    a = rd("assets.js")
    check("Drivers.thumb(" in a and "case 'frame_list'" in a and "f.picker === 'frames'" in a, "assets.js: driver fields play, death_keep is picked")
    j = rd("jobs.js")
    check("Drivers.thumb(" in j and "Drivers.keepField(" in j and "recipeValue:" in j and "Drivers.open(nm" in j, "jobs.js: the job form's driver fields, death_keep, a driver job's preview")
    srv = rd("server.py")
    check("DRVIO.list_drivers(DRIVERS, CONTENT)" in srv and "painted_death" in srv, "server.py hands the routes to drivers_io")

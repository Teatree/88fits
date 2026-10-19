"""The driver library's routes (pass 93, lane PREVIEW). Garry: "I only see names and can't tell what the actual animation
will look like ... I would also like to know where these are kept ... this preview should also include the frame index".

A driver is a folder under tools/dl/drivers/<name>/: one sub-folder per game view (front, fd = front three-quarter, side,
bd = back three-quarter, back), each holding the frames a video model is steered along:

    pose (OpenPose stick figures, the heroes' and humanoid creatures' walks; tools/pose_driver.py):
        <view>/driver_00.png .. driver_NN.png   one stick figure per frame (coloured bones on black)
        <view>/poses.json                       the keypoints of every frame
        <view>_sheet.png, all_sheet.png         contact sheets of one view / of all five
    depth (grey depth videos of a 3D model, the creatures' walks and deaths; tools/blender_depth_drivers.py and the
    per-creature Blender scripts):
        <view>/ctl_00.png .. ctl_NN.png         one depth frame per frame (near = light, far = dark)
        <view>/clay.png                         the model in grey clay, standing (the painters copy it)
        <view>/look.png                         the model in its own colours (when it has them)
        <view>/clay_NN.png                      a one-shot's clay at frame NN (a death's key poses)
    meta.json                                   what made it: kind, frames, loop, the model (fbx / src), the clip, ...
    <name>_soft<r>[b]/                          (pass 92) a depth driver with its body blurred by r px, written by
                                                gen_ctl when a look's ctl_soft / death_soft asks for it (no meta.json)

server.py hands GET /api/drivers here (list_drivers), GET /api/drivers/<name> (one driver with every frame and still),
GET /api/painted_death/<enemy>/<code> (a creature_ctl look's painted death: tools/dl/ai_anim/<key>_death/full_NN.png,
the frames death_keep picks from) and POST /api/drivers/<name>/open (Explorer on the folder, Windows only; the name must
be a folder of the library). Frame indices are the numbers in the file names (0-based): death_keep's indices are them.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

VIEWS = ("front", "fd", "side", "bd", "back")
VIEW_LABEL = {"front": "front", "fd": "front three-quarter", "side": "side", "bd": "back three-quarter", "back": "back"}
NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")
CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")
ID_RE = re.compile(r"^[a-z0-9_]+$")
FRAME_RE = re.compile(r"^(driver|ctl)_(\d+)\.png$")
CLAY_RE = re.compile(r"^clay_(\d+)\.png$")
FULL_RE = re.compile(r"^full_(\d+)\.png$")
SOFT_RE = re.compile(r"^(.+)_soft(\d+)(b?)$")
# the content keys that name a driver (a look's recipe or the asset's own): one name, or {view: name}
DRIVER_KEYS = ("drivers", "death_drivers", "pose", "pose_front", "fit_source")
DRIVER_MAPS = ("pose_drivers", "ctl_drivers")
USED_KINDS = (("enemy", "enemies"), ("boss", "bosses"), ("hero", "characters"))
# what Explorer is opened with (the selftest swaps it for a recorder)
OPENER = [None]


def _rel(path):
    try:
        return os.path.relpath(path, ROOT).replace("\\", "/")
    except ValueError:   # another drive (a test's temporary folder)
        return os.path.abspath(path).replace("\\", "/")


def _load(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return None


def _view_order(names):
    """The game's views first in the game's order (front, fd, side, bd, back), anything else after, sorted."""
    known = [v for v in VIEWS if v in names]
    return known + sorted(v for v in names if v not in VIEWS)


def view_files(folder):
    """One view folder: {frames: [(index, file)], kind pose|depth|None, stills: [(label, file)], poses: bool, size, newest}.
    Frames are driver_NN.png (pose) or ctl_NN.png (depth), sorted by their number; stills are clay.png, look.png and the
    one-shot's clay_NN.png. One scandir (its stat is free on Windows): the listing of ~100 folders stays fast."""
    names = []
    size = 0
    newest = 0.0
    try:
        with os.scandir(folder) as it:
            for e in it:
                if e.is_file():
                    names.append(e.name)
                    try:
                        st = e.stat()
                        size += st.st_size
                        newest = max(newest, st.st_mtime)
                    except OSError:
                        pass
    except OSError:
        pass
    frames = {"driver": [], "ctl": []}
    stills = []
    clays = []
    for f in names:
        m = FRAME_RE.match(f)
        if m:
            frames[m.group(1)].append((int(m.group(2)), f))
            continue
        m = CLAY_RE.match(f)
        if m:
            clays.append((int(m.group(1)), f))
    if "clay.png" in names:
        stills.append(("clay", "clay.png"))
    if "look.png" in names:
        stills.append(("look", "look.png"))
    for k, f in sorted(clays):
        stills.append(("clay at frame %d" % k, f))
    # a folder with both (never written so far) shows the depth: the creature tools' frames
    kind = "depth" if frames["ctl"] else ("pose" if frames["driver"] else None)
    fr = sorted(frames["ctl"] if kind == "depth" else frames["driver"])
    return {"frames": fr, "kind": kind, "stills": stills, "poses": "poses.json" in names, "size": size, "newest": newest,
            "files": len(names)}


def _top_files(folder):
    """The folder's own files (meta.json, the sheets): (size, count, newest)."""
    size = 0
    n = 0
    newest = 0.0
    try:
        with os.scandir(folder) as it:
            for e in it:
                if e.is_file():
                    try:
                        st = e.stat()
                        size += st.st_size
                        newest = max(newest, st.st_mtime)
                        n += 1
                    except OSError:
                        pass
    except OSError:
        pass
    return size, n, newest


def made_from(meta, kind, parent=None, soft=None):
    """One sentence on what made a driver, from its meta.json (or its name, for a softened copy)."""
    if soft is not None:
        r, body = soft
        return "%s, its depth blurred by %d px%s (gen_ctl's ctl_soft / death_soft, pass 92)" % (
            ("a softened copy of " + parent) if parent else "a softened copy", r, " on the body only" if body else "")
    if not isinstance(meta, dict) or not meta:
        return "no meta.json: what made it is not recorded"
    src = meta.get("fbx") or meta.get("glb") or meta.get("src") or ""
    bits = []
    mode = meta.get("mode")
    if kind == "pose":
        bits.append("OpenPose stick figures")
        if src:
            bits.append("from " + os.path.basename(str(src)))
        if meta.get("action"):
            bits.append("clip " + str(meta["action"]))
        if meta.get("frames"):
            bits.append("%s frames" % meta["frames"])
        for k in ("body", "arms", "fwd", "rig", "amp", "lean", "spread", "scale", "op"):
            if meta.get(k) not in (None, "", {}, []):
                bits.append("%s=%s" % (k, json.dumps(meta[k]) if isinstance(meta[k], (dict, list)) else meta[k]))
    else:
        bits.append("depth video")
        if src:
            bits.append("of " + os.path.basename(str(src)))
        if meta.get("action"):
            bits.append("clip " + str(meta["action"]))
        if mode:
            bits.append("mode " + str(mode))
        if meta.get("total"):
            bits.append("%s frames" % meta["total"])
        if meta.get("frames") and meta.get("cycles"):
            bits.append("%s poses a stride x %s" % (meta["frames"], meta["cycles"]))
        if meta.get("amp") not in (None, 1, 1.0):
            bits.append("legs swung x%s" % meta["amp"])
        if meta.get("depth"):
            bits.append("depth " + str(meta["depth"]))
    if str(mode or "") in ("gait", "cycle"):
        bits.append("a loop")   # a made gait's meta says loop false (pass 92); it walks round
    elif meta.get("loop") is not None:
        bits.append("a loop" if meta.get("loop") else "played once")
    return ", ".join(bits)


def _is_death(name, meta):
    m = meta if isinstance(meta, dict) else {}
    if str(m.get("mode") or "") in ("death", "oneshot", "flip_curl"):
        return True
    return bool(re.search(r"(^|_)death(_|$)", name))


def used_by_index(content_dir):
    """{driver name: [{kind, id, code, key, played}]}: every look (and the asset itself) of the enemies, bosses and heroes
    whose recipe names the driver (drivers, death_drivers, pose, pose_front, fit_source, pose_drivers.<view>,
    ctl_drivers.<view>, death "pose:<driver>")."""
    out = {}
    if not content_dir or not os.path.isdir(content_dir):
        return out

    def add(name, rec):
        if isinstance(name, str) and name.strip():
            out.setdefault(name.strip(), []).append(rec)

    def scan(obj, base):
        if not isinstance(obj, dict):
            return
        for k in DRIVER_KEYS:
            if isinstance(obj.get(k), str):
                add(obj[k], dict(base, key=k))
        for k in DRIVER_MAPS:
            if isinstance(obj.get(k), dict):
                for v, n in obj[k].items():
                    add(n, dict(base, key="%s.%s" % (k, v)))
        d = obj.get("death")
        if isinstance(d, str) and d.startswith("pose:"):
            add(d[5:], dict(base, key="death"))

    for kind, sub in USED_KINDS:
        top = os.path.join(content_dir, sub)
        if not os.path.isdir(top):
            continue
        for cid in sorted(os.listdir(top)):
            doc = _load(os.path.join(top, cid, cid + ".json"))
            if not doc:
                continue
            played = str(doc.get("variant") or doc.get("variant_base") or "")
            scan(doc, {"kind": kind, "id": cid, "code": "", "played": not played or played == str(doc.get("variant_base") or "")})
            vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
            for code, e in vs.items():
                if isinstance(e, dict):
                    scan(e.get("recipe") if isinstance(e.get("recipe"), dict) else {}, {"kind": kind, "id": cid, "code": code, "played": code == played})
    # one entry per (asset, look, key)
    for name, recs in out.items():
        seen = set()
        uniq = []
        for r in recs:
            t = (r["kind"], r["id"], r["code"], r["key"])
            if t not in seen:
                seen.add(t)
                uniq.append(r)
        out[name] = uniq
    return out


def describe(drivers_dir, name, used=None, detail=False):
    """One driver as the page shows it, or None when the folder holds no frames. The keys /api/drivers always had (name,
    kind, views, frames, loop, source, action, notes, meta, frames_url, frame_pattern, sheet, sheets, mtime) plus:
    counts {view: frames}, first {view: first index}, path (repo-relative), has_meta, mode, death, made (a sentence),
    parent (a softened copy's source), size, files, used_by; with `detail` every view's frames [{i, url}] and stills
    [{label, url}]. `frames` is the frame count on disk of its first view (a depth meta's own `frames` is the poses per
    stride; it stays in meta)."""
    folder = os.path.join(drivers_dir, name)
    if not NAME_RE.match(name) or not os.path.isdir(folder):
        return None
    meta_path = os.path.join(folder, "meta.json")
    has_meta = os.path.isfile(meta_path)
    meta = (_load(meta_path) or {}) if has_meta else {}
    subdirs = [v for v in os.listdir(folder) if os.path.isdir(os.path.join(folder, v))]
    infos = {v: view_files(os.path.join(folder, v)) for v in subdirs}
    infos = {v: i for v, i in infos.items() if i["frames"]}
    if not infos:
        return None
    on_disk = _view_order(list(infos))
    if isinstance(meta.get("views"), list):
        listed = [str(v) for v in meta["views"] if str(v) in infos]
        views = listed + [v for v in on_disk if v not in listed]
    else:
        views = on_disk
    parent = None
    soft = None
    sm = SOFT_RE.match(name)
    if sm and not has_meta:
        soft = (int(sm.group(2)), bool(sm.group(3)))
        if os.path.isdir(os.path.join(drivers_dir, sm.group(1))):
            parent = sm.group(1)
            meta_parent = _load(os.path.join(drivers_dir, parent, "meta.json")) or {}
        else:
            meta_parent = {}
    else:
        meta_parent = {}
    kinds = {i["kind"] for i in infos.values()}
    if meta.get("kind") in ("pose", "depth"):
        kind = str(meta["kind"])
    else:
        kind = "depth" if "depth" in kinds else "pose"
    eff = meta or meta_parent
    loop = eff.get("loop") if "loop" in eff else None
    if loop is None:
        loop = not _is_death(name, eff)
    # how the viewer plays it at first: a walk loops (a made gait's meta says loop false, pass 92), a death plays once
    plays = "once" if _is_death(name, eff) or str(eff.get("mode") or "") == "oneshot" else ("loop" if loop or str(eff.get("mode") or "") in ("cycle", "gait") else "once")
    sheet = None
    sheets = {}
    for cand in ("all_sheet.png", os.path.join("side", "clay.png"), os.path.join("front", "clay.png")):
        if os.path.isfile(os.path.join(folder, cand)):
            sheet = "/dl/drivers/%s/%s" % (name, cand.replace("\\", "/"))
            break
    for v in views:
        for cand in ("%s_sheet.png" % v, os.path.join(v, "clay.png")):
            if os.path.isfile(os.path.join(folder, cand)):
                sheets[v] = "/dl/drivers/%s/%s" % (name, cand.replace("\\", "/"))
                break
    counts = {v: len(infos[v]["frames"]) for v in views}
    first = {v: infos[v]["frames"][0][0] for v in views}
    tsize, tfiles, tnew = _top_files(folder)
    size = tsize + sum(i["size"] for i in infos.values())
    files = tfiles + sum(i["files"] for i in infos.values())
    mtime = int(os.path.getmtime(meta_path)) if has_meta else int(max([tnew] + [i["newest"] for i in infos.values()]))
    rec = {"name": name, "kind": kind, "views": views, "frames": counts[views[0]], "loop": bool(loop),
           "source": eff.get("fbx") or eff.get("glb") or eff.get("src"), "action": eff.get("action"),
           "notes": eff.get("notes", ""), "meta": meta, "frames_url": "/dl/drivers/%s/<view>/" % name,
           "frame_pattern": "ctl_%02d.png" if kind == "depth" else "driver_%02d.png",
           "sheet": sheet, "sheets": sheets, "mtime": mtime,
           # pass 93
           "counts": counts, "first": first, "path": _rel(folder), "abs_path": os.path.abspath(folder).replace("\\", "/"),
           "has_meta": has_meta, "mode": eff.get("mode") or ("cycle" if loop else "oneshot"), "death": _is_death(name, eff), "plays": plays,
           "made": made_from(meta, kind, parent, soft), "parent": parent, "size": size, "files": files,
           "stills_count": {v: len(infos[v]["stills"]) for v in views},
           "used_by": (used or {}).get(name, [])}
    if detail:
        per = {}
        for v in views:
            vdir = os.path.join(folder, v)
            ver = int(os.path.getmtime(vdir)) if os.path.isdir(vdir) else 0
            per[v] = {"label": VIEW_LABEL.get(v, v),
                      "frames": [{"i": i, "file": f, "url": "/dl/drivers/%s/%s/%s?v=%d" % (name, v, f, ver)} for i, f in infos[v]["frames"]],
                      "stills": [{"label": lab, "file": f, "url": "/dl/drivers/%s/%s/%s?v=%d" % (name, v, f, ver)} for lab, f in infos[v]["stills"]],
                      "poses": infos[v]["poses"], "path": _rel(vdir)}
            # a pose driver's own contact sheet of the view (<view>_sheet.png beside the folders) stands as its still
            sh = os.path.join(folder, "%s_sheet.png" % v)
            if os.path.isfile(sh):
                per[v]["stills"].append({"label": "%s_sheet.png (every frame)" % v, "file": "%s_sheet.png" % v,
                                         "url": "/dl/drivers/%s/%s_sheet.png?v=%d" % (name, v, int(os.path.getmtime(sh)))})
        rec["view_detail"] = per
        rec["meta_parent"] = meta_parent if parent else None
    return rec


def list_drivers(drivers_dir, content_dir=None):
    """Every driver folder with frames (with or without meta.json), sorted by name."""
    out = []
    if not os.path.isdir(drivers_dir):
        return out
    used = used_by_index(content_dir)
    for name in sorted(os.listdir(drivers_dir)):
        if not NAME_RE.match(name) or not os.path.isdir(os.path.join(drivers_dir, name)):
            continue
        rec = describe(drivers_dir, name, used)
        if rec is not None:
            out.append(rec)
    return out


def death_key(enemy, code):
    """gen_ctl's cache key of a look's death clip: <id>_<code lower, no dash>_death (tools/gen_ctl.py)."""
    return "%s_%s_death" % (enemy, str(code).lower().replace("-", ""))


def painted_death(anim_dir, enemy, code):
    """A creature_ctl look's painted death in tools/dl/ai_anim/<key>_death/: every frame Wan painted (full_NN.png, the
    indices death_keep picks), the frames it kept (out_NN.png) and the keep the cache was cut with (cycle.json)."""
    if not ID_RE.match(enemy or "") or not CODE_RE.match(code or ""):
        return {"ok": False, "error": "bad id or code"}
    key = death_key(enemy, code)
    d = os.path.join(anim_dir, key)
    if not os.path.isdir(d):
        return {"ok": True, "exists": False, "key": key, "path": _rel(d), "frames": [], "kept": [], "keep": None}
    meta = _load(os.path.join(d, "cycle.json")) or {}
    names = os.listdir(d)
    ver = int(os.path.getmtime(d))
    full = sorted((int(m.group(1)), f) for f in names for m in [FULL_RE.match(f)] if m)
    kept = sorted(f for f in names if re.match(r"^out_\d+\.png$", f))
    return {"ok": True, "exists": True, "key": key, "path": _rel(d),
            "frames": [{"i": i, "url": "/dl/ai_anim/%s/%s?v=%d" % (key, f, ver)} for i, f in full],
            "kept": ["/dl/ai_anim/%s/%s?v=%d" % (key, f, ver) for f in kept],
            "keep": meta.get("keep") if isinstance(meta.get("keep"), list) else None,
            "seed": meta.get("seed"), "ctl_dir": _rel(meta["ctl_dir"]) if isinstance(meta.get("ctl_dir"), str) else None}


def open_folder(drivers_dir, name, view=None):
    """Explorer on a driver's folder (or one view's): only a folder of the library, only on Windows."""
    if (name is not None and not NAME_RE.match(name)) or (view is not None and not NAME_RE.match(view)) or (name is None and view):
        return {"ok": False, "error": "bad name"}
    base = os.path.realpath(drivers_dir)
    if name is None:
        target = base   # the library itself
    else:
        target = os.path.realpath(os.path.join(drivers_dir, name, view) if view else os.path.join(drivers_dir, name))
    if not (target == base or target.startswith(base + os.sep)) or not os.path.isdir(target):
        return {"ok": False, "error": "no driver folder %s" % ((name or "") + ("/" + view if view else ""))}
    opener = OPENER[0]
    if opener is None:
        if sys.platform != "win32":
            return {"ok": False, "error": "opening a folder works on Windows only: the path is %s" % _rel(target), "path": _rel(target)}
        opener = lambda p: subprocess.Popen(["explorer", os.path.normpath(p)])  # noqa: E731
    try:
        opener(target)
    except OSError as e:
        return {"ok": False, "error": "%s" % e, "path": _rel(target)}
    return {"ok": True, "path": _rel(target)}


# ---------------------------------------------------------------- the routes

def _dirs(srv):
    drivers = getattr(srv, "DRIVERS", os.path.join(ROOT, "tools", "dl", "drivers"))
    content = getattr(srv, "CONTENT", os.path.join(ROOT, "game", "content"))
    anim = getattr(srv, "ANIM_DIR", None) or os.path.join(getattr(srv, "DL", os.path.join(ROOT, "tools", "dl")), "ai_anim")
    return drivers, content, anim


def api_get(h, srv, parts, query=None):
    """parts after /api/: ["drivers"], ["drivers", <name>], ["painted_death", <enemy>, <code>]."""
    drivers, content, anim = _dirs(srv)
    if parts == ["drivers"]:
        return h._send(200, list_drivers(drivers, content))
    if len(parts) == 2 and parts[0] == "drivers":
        if not NAME_RE.match(parts[1]):
            return h._error(404, "bad driver name")
        rec = describe(drivers, parts[1], used_by_index(content), detail=True)
        if rec is None:
            return h._error(404, "no driver %s (a folder of tools/dl/drivers with frames)" % parts[1])
        return h._send(200, dict(rec, ok=True))
    if len(parts) == 3 and parts[0] == "painted_death":
        res = painted_death(anim, parts[1], parts[2])
        return h._send(200 if res.get("ok") else 400, res)
    return h._error(404, "unknown driver route")


def _res(res):
    return (200 if res.get("ok") else 400), res


def api_post(h, srv, parts, body=None):
    """parts after /api/: ["drivers", "open"] (the library), ["drivers", <name>, "open"] with an optional {view}."""
    drivers, _content, _anim = _dirs(srv)
    if parts == ["drivers", "open"]:
        return h._send(*_res(open_folder(drivers, None)))
    if len(parts) == 3 and parts[0] == "drivers" and parts[2] == "open":
        view = body.get("view") if isinstance(body, dict) and body.get("view") else None
        res = open_folder(drivers, parts[1], view)
        return h._send(200 if res.get("ok") else 400, res)
    return h._error(404, "unknown driver route")

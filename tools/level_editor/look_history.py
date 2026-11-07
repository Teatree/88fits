"""Pass 132c (Garry: "allow for seeing history in the LevelEditor as well so I don't ask you all the time"): a look's
past versions, shown and restored from the page.

Where the versions come from:
  - git: every commit that touched the look's strip, icon, provenance file (<id>_<x>_ai.json) or the creature's JSON
    (a version = the strip + icon + entry at that commit; commits that changed none of the three for this look are folded);
  - snapshots: tools/level_editor/backups/looks/<id>/<CODE>/<stamp>/ (strip, icon, _ai.json, entry.json), taken by
    "Keep a copy" (op snapshot) and before every restore (what a restore replaces is never lost; a job's re-roll between
    two commits is only in a snapshot Garry took first).

GET  /api/content/<kind>/<id>/look/<CODE>/history   -> {ok, versions: [...]} newest first, each with its own preview urls
GET  /lookhist/<kind>/<id>/<CODE>/<ref>/<sprite|icon>   -> the picture of that version (ref = git:<sha> | snap:<stamp>)
POST /api/content/<kind>/<id>/look/<CODE> {op: "restore", ref} | {op: "snapshot"}   (look_op hands them here)
"""
import json
import os
import re
import shutil
import subprocess
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
SNAPS = os.path.join(HERE, "backups", "looks")
REF_RE = re.compile(r"^(git:[0-9a-f]{7,40}|snap:[0-9]{8}-[0-9]{6}(?:-[0-9]+)?)$")
MAX_GIT = 40
ENTRY_KEYS = ("note", "anims", "strip_cols", "fps", "head", "fresh", "shelved", "sprite", "icon", "shadow")


def _git(*args, binary=False):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, timeout=60)
    if r.returncode != 0:
        return None
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def _rel(path):
    """Repo-relative with forward slashes (what git takes); absolute when the path is on another drive (the selftests' temp)."""
    try:
        r = os.path.relpath(path, ROOT)
    except ValueError:
        return os.path.abspath(path).replace(os.sep, "/")
    return r.replace(os.sep, "/")


def _entry_of(d, code):
    """A look's entry in a creature's JSON; the base look without an entry of its own reads the top-level keys."""
    vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
    if code in vs and isinstance(vs[code], dict):
        return dict(vs[code]), True
    if code == str(d.get("variant_base", "")):
        return {k: d[k] for k in ("sprite", "icon", "anims", "strip_cols", "fps", "head", "shadow") if k in d}, False
    return None, False


def _files_of(cid, entry, folder_rel):
    """(sprite, icon, ai) repo-relative paths the entry names (the base's defaults when it names none)."""
    sprite = str(entry.get("sprite") or (cid + "_sprite.png"))
    icon = str(entry.get("icon") or (cid + "_icon.png"))
    m = re.match(r"^%s_sprite_([a-z0-9]+)\.png$" % re.escape(cid), sprite)
    ai = "%s_%s_ai.json" % (cid, m.group(1)) if m else "%s_ai.json" % cid
    return ("%s/%s" % (folder_rel, sprite), "%s/%s" % (folder_rel, icon), "%s/%s" % (folder_rel, ai))


def _summary(entry):
    out = {k: entry[k] for k in ENTRY_KEYS if k in entry}
    rec = entry.get("recipe") if isinstance(entry.get("recipe"), dict) else {}
    out["recipe_keys"] = sorted(rec.keys())
    for k in ("death", "pose_drivers", "recolour_of", "seed", "anim_seed", "walk"):
        if k in rec:
            out["recipe_" + k] = rec[k]
    return out


def history(kind, cid, code, folder, json_path):
    """Every version of the look, newest first. folder = the creature's folder (absolute), json_path its JSON."""
    folder_rel = _rel(folder)
    json_rel = _rel(json_path)
    with open(json_path, "rb") as f:
        now = json.loads(f.read().decode("utf-8"))
    entry_now, _ = _entry_of(now, code)
    if entry_now is None:
        return {"ok": False, "error": "%s has no look %s" % (cid, code), "status": 404}
    sp_now, ic_now, _ = _files_of(cid, entry_now, folder_rel)
    now_hash = {p: (_git("hash-object", os.path.join(ROOT, p)) or "").strip() for p in (sp_now, ic_now)}
    versions = []
    # --- snapshots
    sdir = os.path.join(SNAPS, cid, code)
    if os.path.isdir(sdir):
        for stamp in sorted(os.listdir(sdir), reverse=True):
            meta_p = os.path.join(sdir, stamp, "entry.json")
            if not os.path.isfile(meta_p):
                continue
            try:
                meta = json.load(open(meta_p, encoding="utf-8"))
            except (OSError, ValueError):
                continue
            entry = meta.get("entry") if isinstance(meta.get("entry"), dict) else {}
            same = all(os.path.isfile(os.path.join(sdir, stamp, n)) and (_git("hash-object", os.path.join(sdir, stamp, n)) or "").strip() == now_hash[p]
                       for n, p in (("sprite.png", sp_now), ("icon.png", ic_now)))
            versions.append({"ref": "snap:" + stamp, "kind": "snapshot", "when": meta.get("when", stamp), "title": str(meta.get("why", "a copy")),
                             "same_as_now": same, "entry": _summary(entry),
                             "has_sprite": os.path.isfile(os.path.join(sdir, stamp, "sprite.png")),
                             "has_icon": os.path.isfile(os.path.join(sdir, stamp, "icon.png"))})
    # --- git
    log = _git("log", "--format=%H%x1f%ct%x1f%s", "-n", str(MAX_GIT), "--", folder_rel) or ""
    last_key = None
    for line in log.splitlines():
        bits = line.split("\x1f")
        if len(bits) != 3:
            continue
        sha, ts, subject = bits
        text = _git("show", "%s:%s" % (sha, json_rel))
        if text is None:
            continue
        try:
            d = json.loads(text)
        except ValueError:
            continue
        entry, _ = _entry_of(d, code)
        if entry is None:
            continue
        sp, ic, _ai = _files_of(cid, entry, folder_rel)
        sp_h = (_git("rev-parse", "--verify", "-q", "%s:%s" % (sha, sp)) or "").strip()
        ic_h = (_git("rev-parse", "--verify", "-q", "%s:%s" % (sha, ic)) or "").strip()
        key = (sp_h, ic_h, json.dumps(entry, sort_keys=True))
        if key == last_key:
            versions[-1]["since"] = time.strftime("%Y-%m-%d %H:%M", time.localtime(int(ts)))
            continue
        last_key = key
        versions.append({"ref": "git:" + sha[:12], "kind": "git", "when": time.strftime("%Y-%m-%d %H:%M", time.localtime(int(ts))),
                         "title": subject, "same_as_now": sp_h == now_hash[sp_now] and ic_h == now_hash[ic_now],
                         "entry": _summary(entry), "has_sprite": bool(sp_h), "has_icon": bool(ic_h)})
    return {"ok": True, "code": code, "versions": versions, "now": _summary(entry_now),
            "now_committed": bool(versions) and any(v["kind"] == "git" and v["same_as_now"] for v in versions)}


def _version_files(kind, cid, code, ref, folder, json_path):
    """{sprite: bytes|None, icon: bytes|None, ai: bytes|None, entry: dict, own: bool} of a version, or an error dict."""
    if not REF_RE.match(ref or ""):
        return {"error": "bad version ref", "status": 400}
    folder_rel = _rel(folder)
    if ref.startswith("snap:"):
        sdir = os.path.join(SNAPS, cid, code, ref[5:])
        meta_p = os.path.join(sdir, "entry.json")
        if not os.path.isfile(meta_p):
            return {"error": "no such snapshot", "status": 404}
        meta = json.load(open(meta_p, encoding="utf-8"))
        out = {"entry": meta.get("entry") or {}, "own": bool(meta.get("own", True))}
        for key, name in (("sprite", "sprite.png"), ("icon", "icon.png"), ("ai", "ai.json")):
            p = os.path.join(sdir, name)
            out[key] = open(p, "rb").read() if os.path.isfile(p) else None
        return out
    sha = ref[4:]
    text = _git("show", "%s:%s" % (sha, _rel(json_path)))
    if text is None:
        return {"error": "no such commit, or the creature had no JSON then", "status": 404}
    entry, own = _entry_of(json.loads(text), code)
    if entry is None:
        return {"error": "the look did not exist at that commit", "status": 404}
    sp, ic, ai = _files_of(cid, entry, folder_rel)
    return {"entry": entry, "own": own, "sprite": _git("show", "%s:%s" % (sha, sp), binary=True),
            "icon": _git("show", "%s:%s" % (sha, ic), binary=True), "ai": _git("show", "%s:%s" % (sha, ai), binary=True)}


def picture(kind, cid, code, ref, which, folder, json_path):
    """The strip or icon of a version as PNG bytes, or None."""
    got = _version_files(kind, cid, code, ref, folder, json_path)
    return got.get("sprite" if which == "sprite" else "icon") if "error" not in got else None


def snapshot(cid, code, folder, json_path, why):
    """A copy of the look as it is now under backups/looks/<id>/<CODE>/<stamp>/; the stamp."""
    with open(json_path, "rb") as f:
        d = json.loads(f.read().decode("utf-8"))
    entry, own = _entry_of(d, code)
    if entry is None:
        return None
    sp, ic, ai = _files_of(cid, entry, _rel(folder))
    stamp = time.strftime("%Y%m%d-%H%M%S")
    sdir = os.path.join(SNAPS, cid, code, stamp)
    n = 0
    while os.path.isdir(sdir):
        n += 1
        sdir = os.path.join(SNAPS, cid, code, "%s-%d" % (stamp, n))
    os.makedirs(sdir)
    ignore = os.path.join(HERE, "backups", ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8", newline="\n") as f:
            f.write("*\n")
    for src, name in ((sp, "sprite.png"), (ic, "icon.png"), (ai, "ai.json")):
        full = os.path.join(ROOT, src.replace("/", os.sep))
        if os.path.isfile(full):
            shutil.copyfile(full, os.path.join(sdir, name))
    with open(os.path.join(sdir, "entry.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"entry": entry, "own": own, "why": why, "when": time.strftime("%Y-%m-%d %H:%M")}, f, indent=2, ensure_ascii=False)
    return os.path.basename(sdir)


def restore(kind, cid, code, ref, folder, json_path, cio, write_lock):
    """The look's strip, icon, provenance file and entry as they were in `ref`; a snapshot of what they are now first.
    Returns {ok, snapshot, files, entry} or an error dict. The caller imports and reports."""
    got = _version_files(kind, cid, code, ref, folder, json_path)
    if "error" in got:
        return {"ok": False, "error": got["error"], "status": got["status"]}
    with write_lock:
        kept = snapshot(cid, code, folder, json_path, "before restoring %s" % ref)
        src = cio.read_text(json_path)
        d = json.loads(src)
        entry_now, own_now = _entry_of(d, code)
        if entry_now is None:
            return {"ok": False, "error": "%s has no look %s" % (cid, code), "status": 404}
        target = got["entry"]
        sp, ic, ai = _files_of(cid, target if got["own"] else entry_now, _rel(folder))
        written = []
        for key, relp in (("sprite", sp), ("icon", ic), ("ai", ai)):
            data = got.get(key)
            if data is None:
                continue
            full = os.path.join(ROOT, relp.replace("/", os.sep))
            tmp = full + ".tmp"
            with open(tmp, "wb") as f:
                f.write(data)
            os.replace(tmp, full)
            written.append(relp)
        if got["own"] and own_now:
            update = dict(target)
            for k in entry_now:
                if k not in target:
                    update[k] = cio.REMOVE
            text = cio.set_variant_entry(src, code, update)
            if text is None:
                return {"ok": False, "error": "the JSON could not be edited in place", "status": 500}
            cio.write_atomic(json_path, text)
        return {"ok": True, "snapshot": kept, "files": written, "entry": _summary(target)}

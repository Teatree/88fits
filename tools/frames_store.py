"""The frames store (pass 95, lane VACE): every frame of every animation of every look, as versions a human picks
between. Garry: "a way to view every single frame and choose which ones to regenerate ... available to existing assets
too ... keep the history of other generated frames and let me choose between them ... allow using frames from other
Looks ... several frame changes in one go without needing to wait for the save export".

    tools/dl/frames/<kind>/<id>/<CODE>/<anim>/<view>/            one GROUP per animation x view of a look
        group.json          what the group is: the strip key (run_s), the slots, frame_px, fps, the fit (how a clip
                            frame maps into a strip cell), the clip cache and the driver it was walked on
        slot_NN/            one SLOT per frame of the animation (NN = the frame's index in the animation, 0-based)
            vNNN.png        a VERSION's picture: a strip cell (space "cell") or a clip frame on its 640 canvas
                            (space "raw", keyed RGBA, the screen gone)
            vNNN.json       its provenance: id, label, source, from, seed, prompt, model, workflow, time, by, qa
            vNNN_raw.png    the clip frame behind an installed cell, when the clip cache still had it (a twin)
            vNNN_cell.png   a raw version rendered into a strip cell with the group's fit (made when first needed)
        selected.json       the chosen version per slot (what the installed strip shows, or what the next export
                            packs), `pinned` when a human chose it: a re-roll never replaces a pinned choice
        staged.json         choices made in the page and not yet exported (the preview plays them at once)
        exports.json        every export: when, the job, what changed

A version's id is a hash of its PNG (immutable: the same bytes are the same version wherever they sit); its label
<CODE>-<n> is the n-th version of that slot in look CODE (SP-A-1 = the installed frame, SP-A-2 the first repair),
readable, never an identity. A frame copied from another look becomes a new version here (never a link), its `from`
saying where it came from.

Spaces: a strip cell is the finished frame (scaled to the standing cell, outlined, placed at the floor: what the game
shows); a clip frame is what the video model painted at 640 px before artkit placed it. The group's `fit` (cell =
canvas * s + o, measured from the installed cells and their clip twins, else a default) turns a raw version into a cell
exactly like the pipeline's placement (artkit.place_clip_frames: one scale and one offset for every frame of a clip, so
the bounce survives), then punch + outline, then the look's own post filters (gen_ctl's drop_islands and no_green, a
recipe's remap_hues). A cell version is used as it is.

    python tools/frames_store.py register enemy desert_spider SP-B      the retrofit (or a sync after a landing)
    python tools/frames_store.py info enemy desert_spider SP-B [run side]
    python tools/frames_store.py flags enemy desert_spider SP-B run side
    python tools/frames_store.py export enemy desert_spider SP-B          packs the strip from the selected versions
    python tools/frames_store.py stage enemy desert_spider SP-B run side 3 <version id>   a hand run's version staged
    python tools/frames_store.py rollback enemy desert_spider SP-B <backup.png> ['[{"group":"run_s","slot":3,"id":"..."}]']

Pass 95 resume (the assessment's engineering items): one writer of staged.json (the repair job returns its versions,
the Level Editor's landing stages them; vace_repair.py never writes staged.json); the shrink guard in to_cell (a
figure larger than the cell is shrunk, not cropped, and flagged); `driver {name, ctl_sig}` and the clip's `wan` on
every installed version; `store_version` in group.json; rollback_export (the strip put back, the choices staged
again); retention (never a referenced version deleted, 30 strip backups an asset, repair sheets 90 days);
hook_after_save for gen_art / gen_ctl hand runs; removed looks served to the picker, marked.
"""
import hashlib
import io
import json
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import artkit  # noqa: E402

# every root is a module variable so the selftest can point the store, the content and the caches at temporary copies
STORE = os.path.join(REPO, "tools", "dl", "frames")
CONTENT = os.path.join(REPO, "game", "content")
ANIM = os.path.join(REPO, "tools", "dl", "ai_anim")
DRIVERS = os.path.join(REPO, "tools", "dl", "drivers")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_anime")
BACKUPS = os.path.join(REPO, "tools", "level_editor", "backups")

KIND_FOLDERS = {"enemy": "enemies", "boss": "bosses", "hero": "characters"}
ENEMY_ORDER = list(artkit.ENEMY_ORDER)
CHAR_ORDER = list(artkit.CHAR_ORDER)
VIEWS = ("front", "fd", "side", "bd", "back")
# the strip key's suffix per view: a creature's base set is its front, a hero's base set is his back
SUFFIX = {"enemy": {"front": "", "back": "_b", "side": "_s", "bd": "_bd", "fd": "_fd"},
          "hero": {"back": "", "front": "_f", "side": "_s", "bd": "_bd", "fd": "_fd"}}
LOOPS = ("idle", "run")
ID_RE = re.compile(r"^[a-z0-9_]+$")
CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")
NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")
CANVAS = 640
DEFAULT_OUTLINE = {"enemy": (0.024, (14, 8, 12, 255)), "hero": (0.012, (38, 24, 30, 255))}
FLAG_RULES = {"jump": 1.7, "footprint": (0.72, 1.35), "seam": 2.2, "silhouette": 0.5, "empty": 0.004}
# pass 95 resume (the assessment's AN-06 / AN-14): every group.json says which store layout wrote it; retention: a
# version is never deleted while anything references it (selected, staged, an export, a copy's `from`), the strip
# backups an export makes are capped per asset like the JSON backups (30), the repair sheets are kept 90 days, raws
# are kept (the only full-resolution copy once a re-roll moves the clip aside)
STORE_VERSION = 1
RETENTION = {"strip_backups": 30, "repair_days": 90}
# pass 96 (lane PAGE, Garry's decisions 1 and 10): the label every page and result names a frame by, and the rule that
# a frame version is never deleted (the Delete button is gone; delete_version refuses, kept so callers still work)
VIEW_WORD = {"front": "Front", "fd": "Front ¾", "side": "Side", "bd": "Back ¾", "back": "Back"}
NEVER_DELETED = ("frame versions are never deleted (pass 96, Garry's rule): every version of every frame is kept for reuse; "
                 "stage another one instead")


def label_of(v=None, group=None, code=None, base=None, view=None, slot=None, n=None):
    """Garry's frame label, the one formatter (pass 96, decision 1): `SP-A / Run / Side / Frame 07 / v2`. `Frame 07` is
    the 0-based slot the sheet numbers, zero-padded; `v2` the version's number in that slot (the record's `label`
    `SP-A-2` stays for scripts). Takes a version record (+ its group), a group alone (the slot's name), or the parts."""
    if isinstance(v, dict):
        slot = v.get("slot", slot) if slot is None else slot
        n = v.get("n", n) if n is None else n
    g = group
    if g is not None:
        code = code or getattr(getattr(g, "look", None), "code", None) or (g.meta.get("code") if hasattr(g, "meta") else None)
        base = base or getattr(g, "base", None)
        view = view or getattr(g, "view", None)
    parts = [str(code or "?")]
    if base:
        parts.append(str(base).capitalize())
    if view:
        parts.append(VIEW_WORD.get(str(view), str(view).capitalize()))
    if slot is not None:
        parts.append("Frame %02d" % int(slot))
    if n is not None:
        parts.append("v%d" % int(n))
    return " / ".join(parts)


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def _rel(path):
    try:
        return os.path.relpath(path, REPO).replace("\\", "/")
    except ValueError:
        return os.path.abspath(path).replace("\\", "/")


def _load(path, default=None):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _save(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def clean_alpha(img):
    """The RGB under alpha 0 zeroed (artkit.add_outline leaves the outline colour there; a strip cell cut from a packed
    strip has zeros): the same picture is then the same bytes wherever it comes from."""
    a = np.asarray(img.convert("RGBA")).copy()
    a[a[..., 3] == 0] = 0
    return Image.fromarray(a, "RGBA")


def same_picture(a, b, tol=3):
    """Two cells that show the same thing: the same size and alpha, the colours within `tol` where visible
    (artkit.pack_strip's alpha_composite rounds a semi-transparent edge pixel by one)."""
    if a.size != b.size:
        return False
    x, y = np.asarray(a.convert("RGBA")).astype(np.int16), np.asarray(b.convert("RGBA")).astype(np.int16)
    if not np.array_equal(x[..., 3], y[..., 3]):
        return False
    vis = x[..., 3] > 0
    if not vis.any():
        return True
    return int(np.abs(x[..., :3] - y[..., :3])[vis].max()) <= tol


def sha_of(data):
    return hashlib.sha1(data).hexdigest()[:16]


def player_kind(kind):
    return "hero" if kind == "hero" else "enemy"


def order_of(kind):
    return CHAR_ORDER if player_kind(kind) == "hero" else ENEMY_ORDER


def anim_parts(kind, key):
    """A strip key split into (base, view): run_s -> (run, side); a key without a suffix is the kind's base view."""
    pk = player_kind(kind)
    for sfx, view in (("_bd", "bd"), ("_fd", "fd"), ("_b", "back"), ("_s", "side"), ("_f", "front")):
        if key.endswith(sfx) and SUFFIX[pk].get(view) == sfx:
            return key[: -len(sfx)], view
    return key, ("back" if pk == "hero" else "front")


def anim_key(kind, base, view):
    """(run, side) -> run_s; the base view of the kind has no suffix. None for a view the kind does not key."""
    sfx = SUFFIX[player_kind(kind)].get(view)
    if sfx is None:
        return None
    return base + sfx


def loops(base):
    return base in LOOPS


def code_part(code):
    return str(code or "").lower().replace("-", "")


def letter_of(code):
    return str(code or "").split("-")[-1].lower()


def bbox(img, thr=127):
    """(x0, y0, x1, y1) of the alpha over `thr` (x1, y1 exclusive), or None when (nearly) empty."""
    a = np.asarray(img.convert("RGBA"))[..., 3] > thr
    ys, xs = np.nonzero(a)
    if len(xs) < 8:
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


# ---------------------------------------------------------------- the look: its JSON, strip and recipe

class Look:
    """One look of a creature, boss or hero as the store sees it: the JSON's entry (the base look's values are the
    top-level ones, as JsonContent reads them), its strip, anims, frame_px, fps and recipe."""

    def __init__(self, kind, cid, code, content=None, override=None):
        if kind not in KIND_FOLDERS or not ID_RE.match(cid or "") or not CODE_RE.match(code or ""):
            raise ValueError("bad look %s/%s/%s" % (kind, cid, code))
        self.kind, self.cid, self.code = kind, cid, code
        self.removed = False
        self.content = content or CONTENT
        self.folder = os.path.join(self.content, KIND_FOLDERS[kind], cid)
        self.json_path = os.path.join(self.folder, cid + ".json")
        self.doc = _load(self.json_path)
        if not isinstance(self.doc, dict):
            raise ValueError("no %s %s (%s)" % (kind, cid, _rel(self.json_path)))
        vs = self.doc.get("variants") if isinstance(self.doc.get("variants"), dict) else {}
        self.base_code = str(self.doc.get("variant_base", ""))
        self.is_base = code == self.base_code
        self.entry = vs.get(code) if isinstance(vs.get(code), dict) else None
        if self.entry is None and not self.is_base:
            raise ValueError("%s has no look %s" % (cid, code))
        self.entry = self.entry or {}
        self.recipe = self.entry.get("recipe") if isinstance(self.entry.get("recipe"), dict) else {}
        d = self.doc
        pk = player_kind(kind)
        # the values the game reads for this look: its own, else the top level's (JsonContent)
        self.sprite_name = str(d.get("sprite", cid + "_sprite.png")) if self.is_base else str(self.entry.get("sprite", ""))
        self.anims = (d.get("anims") if self.is_base or not isinstance(self.entry.get("anims"), dict) else self.entry["anims"]) or {}
        self.fps = (d.get("fps") if self.is_base or not isinstance(self.entry.get("fps"), dict) else self.entry["fps"]) or {}
        self.strip_cols = int(d.get("strip_cols", 0) or 0) if self.is_base else int(self.entry.get("strip_cols", 0) or 0)
        top_px = int(d.get("frame_px", 256 if pk == "hero" else 128) or (256 if pk == "hero" else 128))
        self.frame_px = top_px if self.is_base else int(self.entry.get("frame_px") or self.recipe.get("frame_px") or top_px)
        # the recipe keys the pipelines read, the look's own over the asset's (gen_art lays the recipe over the JSON)
        self.d = dict(d)
        self.d.update(self.recipe)
        # pass 95 resume: a pipeline that has just saved a strip knows its counts better than the entry on disk (the
        # sidecar is merged later): hook_after_save hands them over so the cut never follows a stale entry
        if isinstance(override, dict):
            if override.get("sprite"):
                self.sprite_name = str(override["sprite"])
            if isinstance(override.get("anims"), dict) and override["anims"]:
                self.anims = dict(override["anims"])
            if override.get("strip_cols"):
                self.strip_cols = int(override["strip_cols"])

    @property
    def in_play(self):
        """The look the game plays: the JSON's `variant`, else its base (JsonContent's rule)."""
        return self.code == str(self.doc.get("variant") or self.doc.get("variant_base") or "")

    @property
    def strip_path(self):
        return os.path.join(self.folder, self.sprite_name) if self.sprite_name and not self.sprite_name.startswith("res://") else ""

    def has_strip(self):
        return bool(self.strip_path) and os.path.isfile(self.strip_path)

    def method(self):
        m = str(self.recipe.get("method") or "")
        if m:
            return m
        if self.recipe.get("drivers"):
            return "creature_ctl"
        return "hero" if self.kind == "hero" else "creature"

    def outline(self):
        """(px, colour) as gen_ctl / gen_art outline the frames of this kind."""
        pk = player_kind(self.kind)
        frac, col = DEFAULT_OUTLINE[pk]
        frac = float(self.d.get("outline_frac", frac) or frac)
        oc = self.d.get("outline_color")
        if isinstance(oc, str) and re.match(r"^#?[0-9a-fA-F]{6}$", oc):
            oc = oc.lstrip("#")
            col = (int(oc[0:2], 16), int(oc[2:4], 16), int(oc[4:6], 16), 255)
        return max(1, int(round(self.frame_px * frac))), col

    def cells(self):
        """{strip key: [cells]} cut from the installed strip in the kind's order with the look's anims counts."""
        if not self.has_strip():
            return {}
        strip = Image.open(self.strip_path).convert("RGBA")
        px = self.frame_px
        total = sum(int(self.anims.get(a, 0) or 0) for a in order_of(self.kind))
        cols = self.strip_cols if self.strip_cols > 0 else max(1, total)
        out = {}
        k = 0
        for a in order_of(self.kind):
            n = int(self.anims.get(a, 0) or 0)
            frames = []
            for _ in range(n):
                x, y = (k % cols) * px, (k // cols) * px
                frames.append(strip.crop((x, y, x + px, y + px)))
                k += 1
            if n > 0:
                out[a] = frames
        return out

    def clip_keys(self, base, view):
        """The clip cache keys this animation x view could have been cut from, in the order to try."""
        cp = code_part(self.code)
        cid = self.cid
        keys = []
        if self.kind == "hero":
            ck = cid if self.is_base else cid + "_" + cp
            if base == "run":
                keys += [ck + "_pose_run_" + view, ck + "_ctl_run_" + view, ck + "_run" + (SUFFIX["hero"].get(view) or "_b")]
        else:
            ak = cid if self.is_base else cid + "_" + cp
            key = cid + "_" + cp
            if base == "run":
                keys.append(key + "_ctl_" + view)
                if view == "front":
                    keys += [ak + "_pose_f", ak + "_walk_f"]
                elif view == "back":
                    keys += [ak + "_pose_b", ak + "_walk_b"]
                else:
                    keys.append(ak + "_walk_" + view)
            elif base == "die" and view == ("front" if self.kind != "hero" else "back"):
                keys += [key + "_death", ak + "_death"]
        return keys

    def driver_for(self, base, view, n):
        """The driver this animation x view was walked along and the driver frame of each slot: {name, dir, pattern,
        kind, index: [n]} or None. creature_ctl keeps the second stride of two (ctl_(n+k)); a death keeps death_keep;
        a Wan Animate walk keeps driver frames 1..n (the clip's first frame is the one the model gets wrong most)."""
        r = self.d
        name = None
        pattern = "ctl_%02d.png"
        idx = None
        if self.kind == "hero":
            ctl = r.get("ctl_drivers") if isinstance(r.get("ctl_drivers"), dict) else {}
            pose = r.get("pose_drivers") if isinstance(r.get("pose_drivers"), dict) else {}
            if base == "run" and ctl.get(view):
                name, idx = str(ctl[view]), [n + k for k in range(n)]
            elif base == "run" and bool(r.get("pose_driven", True)):
                name, pattern, idx = str(pose.get(view) or "run"), "driver_%02d.png", [k + 1 for k in range(n)]
        elif r.get("drivers") and base == "run":
            name, idx = str(r["drivers"]), [n + k for k in range(n)]
        elif r.get("death_drivers") and base == "die" and view == "front":
            keep = r.get("death_keep") or [1, 4, 7, 10, 13, 16, 20, 24]
            keep = [int(v) for v in keep] if isinstance(keep, (list, tuple)) else []
            if len(keep) == n:
                name, idx = str(r["death_drivers"]), keep
        elif r.get("pose") and base == "run" and view in ("front", "back"):
            name, pattern, idx = str(r.get("pose_front") if view == "front" and r.get("pose_front") else r["pose"]), "driver_%02d.png", [k + 1 for k in range(n)]
        if not name or not NAME_RE.match(name):
            return None
        vdir = os.path.join(DRIVERS, name, view)
        if not os.path.isdir(vdir):
            return None
        have = [os.path.isfile(os.path.join(vdir, pattern % i)) for i in idx]
        if not all(have):
            # a driver with fewer frames than the kept stride (a one-stride clip): the first stride then
            idx2 = [k for k in range(n)]
            if pattern == "ctl_%02d.png" and all(os.path.isfile(os.path.join(vdir, pattern % i)) for i in idx2):
                idx = idx2
            else:
                return None
        return {"name": name, "view": view, "dir": _rel(vdir), "pattern": pattern, "kind": "depth" if pattern.startswith("ctl") else "pose", "index": idx}

    def ref_still(self, view):
        """The painting of this view (the clip's reference), when the cache has it."""
        cands = []
        if self.kind == "hero":
            skeys = self.d.get("still_keys") if isinstance(self.d.get("still_keys"), dict) else {}
            if skeys.get(view):
                cands.append(str(skeys[view]))
            slug = str(self.d.get("stills") or "")
            cands.append(self.cid + ("_" + slug if slug else "") + "_" + view)
            cands.append(self.cid + "_" + view)
        else:
            cands.append(self.cid + "_" + code_part(self.code) + "_" + view)
            slug = str(self.d.get("stills") or "")
            cands.append(self.cid + ("_" + slug if slug else "") + "_" + view)
            cands.append(self.cid + "_" + view)
        for k in cands:
            p = os.path.join(RAW, k + ".png")
            if os.path.isfile(p):
                return _rel(p)
        return ""

    def screen(self):
        """The screen colour the clips were painted on: the recipe's / the JSON's `screen`, else green."""
        s = str(self.d.get("screen", "green") or "green").lower()
        return "blue" if s == "blue" else "green"

    def post(self):
        """The post filters the pipeline laid on the frames after the clip (what a raw version gets on its way to a cell)."""
        out = {"drop_islands": True}
        if self.recipe.get("drivers") or self.method() == "creature_ctl":
            ng = self.d.get("no_green", True)
            out["no_green"] = ng if ng in (False, "rb") else True
        rh = self.d.get("remap_hues")
        if isinstance(rh, dict) and rh.get("ranges"):
            out["remap_hues"] = rh
        return out


# ---------------------------------------------------------------- a group: one animation x view, its slots and versions

class Group:
    def __init__(self, look, base, view, store=None):
        self.look = look
        self.base, self.view = base, view
        self.key = anim_key(look.kind, base, view)
        self.store = store or STORE
        self.dir = os.path.join(self.store, look.kind, look.cid, look.code, base, view)
        self.meta = _load(os.path.join(self.dir, "group.json"), {}) or {}
        self.last_shrink = None

    # -- paths
    def slot_dir(self, slot):
        return os.path.join(self.dir, "slot_%02d" % int(slot))

    def exists(self):
        return bool(self.meta) and os.path.isdir(self.dir)

    @property
    def n(self):
        return int(self.meta.get("n", 0) or 0)

    def save_meta(self):
        self.meta.setdefault("store_version", STORE_VERSION)
        _save(os.path.join(self.dir, "group.json"), self.meta)

    # -- versions
    def versions(self, slot):
        """[{...json, n, file}] of a slot, in version order (n)."""
        d = self.slot_dir(slot)
        out = []
        if not os.path.isdir(d):
            return out
        for f in sorted(os.listdir(d)):
            m = re.match(r"^v(\d{3})\.json$", f)
            if m:
                v = _load(os.path.join(d, f), {}) or {}
                v["n"] = int(m.group(1))
                v["file"] = os.path.join(d, "v%03d.png" % v["n"])
                out.append(v)
        return out

    def version(self, slot, vid):
        for v in self.versions(slot):
            if v.get("id") == vid:
                return v
        return None

    def add_version(self, slot, img, space, source, by="ai", raw=None, **prov):
        """A new version of a slot from a picture (`img` RGBA: a cell or a 640 canvas), unless the same bytes are a
        version already (then that one). Returns the version record."""
        img = clean_alpha(img)
        data = png_bytes(img)
        vid = sha_of(data)
        for v in self.versions(slot):
            if v.get("id") == vid:
                return v
        d = self.slot_dir(slot)
        os.makedirs(d, exist_ok=True)
        n = len(self.versions(slot)) + 1
        with open(os.path.join(d, "v%03d.png" % n), "wb") as f:
            f.write(data)
        rec = {"id": vid, "label": "%s-%d" % (self.look.code, n), "slot": int(slot), "space": space, "source": source, "by": by,
               "time": _now(), "size": list(img.size)}
        rec.update({k: v for k, v in prov.items() if v is not None})
        if raw is not None:
            raw.convert("RGBA").save(os.path.join(d, "v%03d_raw.png" % n))
            rec["raw"] = True
            rec["canvas"] = list(raw.size)
        if space == "cell":
            rec["cell_sha1"] = vid
        _save(os.path.join(d, "v%03d.json" % n), rec)
        rec["n"] = n
        rec["file"] = os.path.join(d, "v%03d.png" % n)
        return rec

    def update_version(self, slot, vid, **fields):
        for v in self.versions(slot):
            if v.get("id") == vid:
                rec = {k: x for k, x in v.items() if k not in ("n", "file")}
                rec.update(fields)
                rec = {k: x for k, x in rec.items() if x is not None}   # a field set to None is dropped (shrunk cleared)
                _save(os.path.join(self.slot_dir(slot), "v%03d.json" % v["n"]), rec)
                return rec
        return None

    def raw_of(self, slot, v):
        """The 640-canvas picture of a version (its own when raw, its twin when installed), else None."""
        if v.get("space") == "raw":
            return Image.open(v["file"]).convert("RGBA")
        p = os.path.join(self.slot_dir(slot), "v%03d_raw.png" % v["n"])
        if os.path.isfile(p):
            return Image.open(p).convert("RGBA")
        return None

    # -- the fit: canvas -> cell
    def fit(self):
        f = self.meta.get("fit")
        if isinstance(f, dict) and f.get("s"):
            return f
        px = self.look.frame_px
        S = int(self.meta.get("canvas") or CANVAS)
        s = px / (S * 0.8)
        return {"s": s, "ox": -S * 0.1 * s, "oy": -S * 0.1 * s, "source": "default", "canvas": S}

    def canvas_size(self):
        return int(self.meta.get("canvas") or CANVAS)

    def to_cell(self, raw_img):
        """A raw canvas frame placed into a strip cell with the group's fit, then punch + outline + the post filters,
        the way the pipeline finished its frames. The shrink guard of artkit.place_clip_frames (pass 95 resume, AN-04):
        a figure that would overflow the cell at the fit's scale is shrunk to fit about its floor and centre instead of
        being cropped (the pipeline would have shrunk the whole clip; here only this frame, so `last_shrink` says by how
        much and the flags raise `footprint` on it)."""
        f = self.fit()
        px = self.look.frame_px
        S = raw_img.width
        img = raw_img.convert("RGBA")
        post = self.look.post()
        if post.get("drop_islands"):
            img = drop_islands(img)
        s, ox, oy = float(f["s"]), float(f["ox"]), float(f["oy"])
        self.last_shrink = None
        opx0 = self.look.outline()[0]
        fb = bbox(img)
        if fb:
            inner = max(1, px - 2 * opx0)
            bw, bh = (fb[2] - fb[0]) * s, (fb[3] - fb[1]) * s
            if bw > inner or bh > inner:
                k = min(inner / bw, inner / bh)
                # the figure's floor and centre stay where the fit put them, then clamped into the cell
                cx, floor = (fb[0] + fb[2]) / 2.0 * s + ox, fb[3] * s + oy
                s2 = s * k
                ox2, oy2 = cx - (fb[0] + fb[2]) / 2.0 * s2, floor - fb[3] * s2
                ox2 = min(max(ox2, opx0 - fb[0] * s2), px - opx0 - fb[2] * s2)
                oy2 = min(max(oy2, opx0 - fb[1] * s2), px - opx0 - fb[3] * s2)
                s, ox, oy = s2, ox2, oy2
                self.last_shrink = round(k, 4)
        w = max(1, int(round(S * s)))
        small = img.resize((w, max(1, int(round(img.height * s)))), Image.LANCZOS)
        # the scaled canvas laid into the cell at the fit's offset (alpha_composite wants a destination inside the cell,
        # so the part that falls inside is cut out first)
        pad = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        ox, oy = int(round(ox)), int(round(oy))
        sx0, sy0 = max(0, -ox), max(0, -oy)
        dx0, dy0 = max(0, ox), max(0, oy)
        cw, ch = small.width - sx0, small.height - sy0
        if cw > 0 and ch > 0 and dx0 < px and dy0 < px:
            piece = small.crop((sx0, sy0, sx0 + min(cw, px - dx0), sy0 + min(ch, px - dy0)))
            pad.alpha_composite(piece, (dx0, dy0))
        opx, ocol = self.look.outline()
        out = artkit.add_outline(artkit.punch(pad), opx, ocol)
        ng = post.get("no_green")
        if ng:
            out = no_green(out, ng)
        rh = post.get("remap_hues")
        if rh:
            out = artkit.remap_hues(out, rh.get("ranges", []), rh.get("to", 230), rh.get("sat", 0.55), rh.get("min_sat", 0.16), rh.get("max_sat", 1.01))
        return clean_alpha(out)

    def cell_of(self, slot, v):
        """The strip cell of a version (its own picture, or the raw rendered with the fit, kept beside it)."""
        if v.get("space") == "cell":
            return Image.open(v["file"]).convert("RGBA")
        p = os.path.join(self.slot_dir(slot), "v%03d_cell.png" % v["n"])
        sig = json.dumps(self.fit(), sort_keys=True)
        if os.path.isfile(p) and v.get("cell_fit") == sig:
            return Image.open(p).convert("RGBA")
        cell = self.to_cell(Image.open(v["file"]).convert("RGBA"))
        cell.save(p)
        self.update_version(slot, v["id"], cell_fit=sig, cell_sha1=sha_of(png_bytes(cell)), shrunk=getattr(self, "last_shrink", None))
        return cell

    def cell_url_file(self, slot, v):
        """The file the page shows for a version's cell (made if needed): (path, name)."""
        if v.get("space") == "cell":
            return v["file"]
        self.cell_of(slot, v)
        return os.path.join(self.slot_dir(slot), "v%03d_cell.png" % v["n"])

    # -- choices
    def selected(self):
        return (_load(os.path.join(self.dir, "selected.json"), {}) or {}).get("slots") or {}

    def staged(self):
        return (_load(os.path.join(self.dir, "staged.json"), {}) or {}).get("slots") or {}

    def _write_sel(self, slots):
        _save(os.path.join(self.dir, "selected.json"), {"slots": slots})

    def _write_staged(self, slots):
        _save(os.path.join(self.dir, "staged.json"), {"slots": slots})

    def select(self, slot, vid, by="human", pinned=None):
        slots = self.selected()
        cur = slots.get(str(slot)) or {}
        rec = {"id": vid, "by": by, "time": _now(), "pinned": bool(cur.get("pinned")) if pinned is None else bool(pinned)}
        slots[str(slot)] = rec
        self._write_sel(slots)
        return rec

    def pin(self, slot, pinned=True):
        slots = self.selected()
        cur = slots.get(str(slot))
        if not cur:
            return None
        cur["pinned"] = bool(pinned)
        if pinned:
            cur["by"] = "human"
        self._write_sel(slots)
        return cur

    def stage(self, slot, vid, why="chosen"):
        if not self.version(slot, vid):
            raise ValueError("slot %s has no version %s" % (slot, vid))
        slots = self.staged()
        sel = self.selected().get(str(slot)) or {}
        if sel.get("id") == vid:
            slots.pop(str(slot), None)   # staging what is selected = no change pending
        else:
            slots[str(slot)] = {"id": vid, "time": _now(), "why": why}
        self._write_staged(slots)
        return slots.get(str(slot))

    def unstage(self, slot=None):
        slots = self.staged()
        if slot is None:
            slots = {}
        else:
            slots.pop(str(slot), None)
        self._write_staged(slots)
        return slots

    def effective(self, slot):
        """The version the preview plays and the next export packs: the staged one, else the selected one."""
        st = self.staged().get(str(slot))
        if st:
            v = self.version(slot, st["id"])
            if v:
                return v, "staged"
        sel = self.selected().get(str(slot))
        if sel:
            v = self.version(slot, sel["id"])
            if v:
                return v, "selected"
        vs = self.versions(slot)
        return (vs[0], "first") if vs else (None, "none")

    def effective_cells(self, staged=True):
        """The cells the preview plays and an export packs; staged=False (pass 96): the selected versions only, the
        "before" of a staged batch."""
        out = []
        for k in range(self.n):
            v, _ = self.effective(k) if staged else self.selected_version(k)
            out.append(self.cell_of(k, v) if v else Image.new("RGBA", (self.look.frame_px,) * 2, (0, 0, 0, 0)))
        return out

    def selected_version(self, slot):
        """The selected version of a slot (what the last export or install chose), else the first; (version, how)."""
        sel = self.selected().get(str(slot))
        if sel:
            v = self.version(slot, sel["id"])
            if v:
                return v, "selected"
        vs = self.versions(slot)
        return (vs[0], "first") if vs else (None, "none")

    def name_of(self, slot, v=None):
        """Garry's label of a slot or of one of its versions (label_of with this group's code, base and view)."""
        return label_of(v, self, slot=slot) if v is not None else label_of(None, self, slot=slot)

    # -- registration (the retrofit, and a sync after a landing)
    def register(self, cells, force=False):
        """The installed strip's cells of this animation x view as versions: a new group gets its baseline (version 1
        per slot, `installed`), with the clip cache's frame as a twin when the cache still has the clip (the fit is
        measured from the pairs); a known group whose strip changed gets the new cells as versions (`reroll`),
        selected unless the slot is pinned. Returns what happened."""
        look = self.look
        n = len(cells)
        was = self.exists()
        px_before = int(self.meta.get("frame_px") or 0) if was else 0   # pass 96: a landing that changed the cell size
        if not was:
            self.meta = {"kind": look.kind, "id": look.cid, "code": look.code, "base": self.base, "view": self.view, "key": self.key,
                         "n": n, "frame_px": look.frame_px, "loop": loops(self.base), "created": _now(), "canvas": CANVAS, "store_version": STORE_VERSION}
        changed = []
        clip = self._clip(n) if (not was or force) else self.meta.get("clip")
        raws = self._raw_frames(clip, n) if clip else None
        # the driver first: every installed version records what it was walked on (name + the depth video's signature),
        # so a repair made on an older driver is visible later (pass 95 resume, AN-06 / E5)
        drv = look.driver_for(self.base, self.view, n) if ((not was or force) or not self.meta.get("driver")) else self.meta.get("driver")
        drv_rec = {"name": drv["name"], "ctl_sig": (clip or {}).get("ctl_sig")} if drv else None
        sel = self.selected()
        for k, cell in enumerate(cells):
            cell = clean_alpha(cell)
            data = png_bytes(cell)
            vid = sha_of(data)
            cur = sel.get(str(k)) or {}
            existing = [v for v in self.versions(k) if v.get("cell_sha1") == vid or v.get("id") == vid]
            if not existing:
                # the same picture by eye (pack_strip rounds a semi-transparent edge pixel): the chosen one first
                vs = self.versions(k)
                vs.sort(key=lambda v: 0 if v.get("id") == cur.get("id") else 1)
                for v in vs:
                    try:
                        if same_picture(cell, self.cell_of(k, v)):
                            existing = [v]
                            break
                    except (OSError, ValueError):
                        continue
            if existing:
                v = existing[0]
                if cur.get("id") != v["id"]:
                    if cur.get("pinned"):
                        cur["installed_differs"] = v["id"]
                        sel[str(k)] = cur
                    else:
                        sel[str(k)] = {"id": v["id"], "by": "install", "time": _now(), "pinned": False}
                        changed.append({"slot": k, "to": v["label"], "why": "installed"})
                elif cur.get("installed_differs"):
                    cur.pop("installed_differs", None)   # the strip shows the pinned choice again (an export, a rollback)
                    sel[str(k)] = cur
                continue
            raw = raws[k] if raws else None
            v = self.add_version(k, cell, "cell", "installed" if not was else "reroll", by="pipeline", raw=raw,
                                 clip_key=clip.get("key") if clip else None, clip_frame=k if clip else None,
                                 driver=drv_rec, wan=(clip or {}).get("wan"))
            if cur.get("pinned"):
                cur["installed_differs"] = v["id"]
                sel[str(k)] = cur
            else:
                sel[str(k)] = {"id": v["id"], "by": "install", "time": _now(), "pinned": False}
            changed.append({"slot": k, "to": v["label"], "why": "installed" if not was else "re-rolled"})
        # pass 96 (lane PAGE, AN-09 Q4): the pins a landing left behind are reported, never guessed: a pinned slot past
        # the new frame count, or a pinned cell of another size (frame_px changed), cannot be re-applied; its pin moves
        # to group.json `lost_pins` (the version stays, nothing is deleted) and the landing's own cell is selected
        misfit = []
        for ks in sorted(list(sel.keys()), key=lambda x: int(x) if x.isdigit() else 0):
            try:
                k = int(ks)
            except ValueError:
                continue
            cur = sel.get(ks) or {}
            if k >= n:
                if cur.get("pinned"):
                    misfit.append({"slot": k, "id": cur.get("id"), "why": "count", "name": self.name_of(k, self.version(k, cur.get("id")) or {"n": None}),
                                   "text": "the animation has %d frames now" % n})
                    self.meta.setdefault("lost_pins", []).append(dict(cur, slot=k, why="the animation has %d frames now" % n, lost=_now()))
                sel.pop(ks, None)
            elif cur.get("pinned") and cur.get("installed_differs") and was and px_before and px_before != look.frame_px:
                misfit.append({"slot": k, "id": cur.get("id"), "why": "frame_px", "name": self.name_of(k, self.version(k, cur.get("id")) or {"n": None}),
                               "text": "the cells are %d px now (the pinned frame is %d px)" % (look.frame_px, px_before)})
                self.meta.setdefault("lost_pins", []).append(dict(cur, slot=k, why="the cells are %d px now" % look.frame_px, lost=_now()))
                sel[ks] = {"id": cur["installed_differs"], "by": "install", "time": _now(), "pinned": False, "was_pinned": cur.get("id")}
        self._write_sel(sel)
        self.meta["n"] = n
        self.meta["frame_px"] = look.frame_px
        self.meta["fps"] = look.fps
        self.meta["clip"] = clip
        self.meta["driver"] = drv
        self.meta["ref_still"] = look.ref_still(self.view)
        self.meta["screen"] = look.screen()
        self.meta["method"] = look.method()
        self.meta["post"] = look.post()
        opx, ocol = look.outline()
        self.meta["outline"] = {"px": opx, "color": list(ocol)}
        if raws and (not isinstance(self.meta.get("fit"), dict) or force):
            self.meta["fit"] = self._measure_fit(cells, raws, opx)
        if self.look.has_strip():
            st = os.stat(look.strip_path)
            self.meta["strip"] = {"file": look.sprite_name, "mtime": int(st.st_mtime), "size": st.st_size}
        self.meta["registered"] = _now()
        self.save_meta()
        return {"group": self.key, "new": not was, "changed": changed, "clip": (clip or {}).get("key"), "driver": (self.meta.get("driver") or {}).get("name"),
                "fit": self.meta.get("fit", {}).get("source") if isinstance(self.meta.get("fit"), dict) else "default",
                "misfit": misfit, "pinned_differs": sorted(int(k) for k, s in sel.items() if s.get("pinned") and s.get("installed_differs"))}

    def _clip(self, n):
        """The clip cache this group was cut from: the first candidate key whose out_NN count equals the slots."""
        for key in self.look.clip_keys(self.base, self.view):
            d = os.path.join(ANIM, key)
            meta = _load(os.path.join(d, "cycle.json"))
            if not isinstance(meta, dict):
                continue
            outs = sorted(f for f in os.listdir(d) if re.match(r"^out_\d+\.png$", f))
            fulls = sorted(f for f in os.listdir(d) if re.match(r"^full_\d+\.png$", f))
            rec = {"key": key, "dir": _rel(d), "out": len(outs), "full": len(fulls), "box": meta.get("box"), "seed": meta.get("seed"),
                   "size": int((meta.get("wan") or {}).get("size") or meta.get("size") or CANVAS), "prompt": meta.get("prompt", ""),
                   "kind": "control" if meta.get("control") else "oneshot" if meta.get("oneshot") else "pose" if meta.get("pose") else "flf" if meta.get("flf") else "free",
                   "match": len(outs) == n}
            if meta.get("wan"):
                rec["wan"] = meta["wan"]
            for k2 in ("ctl_sig", "ref_hash"):   # the depth video's and the painting's signatures (gen_ctl's cache keys)
                if meta.get(k2):
                    rec[k2] = meta[k2]
            return rec
        return None

    def _raw_frames(self, clip, n):
        """The clip's out_NN frames put back on the clip's canvas (they were cut to the clip's box): the raw twins."""
        if not clip or not clip.get("match") or not clip.get("box"):
            return None
        d = os.path.join(REPO, clip["dir"])
        S = int(clip.get("size") or CANVAS)
        box = clip["box"]
        out = []
        for k in range(n):
            p = os.path.join(d, "out_%02d.png" % k)
            if not os.path.isfile(p):
                return None
            fr = Image.open(p).convert("RGBA")
            canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            canvas.alpha_composite(fr, (int(box[0]), int(box[1])))
            out.append(canvas)
        self.meta["canvas"] = S
        return out

    def _measure_fit(self, cells, raws, opx):
        """cell = raw * s + o from the installed cells and their clip twins: the scale from the figure heights (the cell's
        figure less its outline), the offset from the corners, medians over the slots; the residual says how well."""
        ss, oxs, oys = [], [], []
        pairs = []
        for cell, raw in zip(cells, raws):
            cb, rb = bbox(cell), bbox(raw)
            if not cb or not rb:
                continue
            ih = (cb[3] - cb[1]) - 2 * opx
            iw = (cb[2] - cb[0]) - 2 * opx
            rh, rw = rb[3] - rb[1], rb[2] - rb[0]
            if ih <= 0 or rh <= 0:
                continue
            ss.append(ih / rh)
            if rw > 0 and iw > 0:
                ss.append(iw / rw)
            pairs.append((cb, rb))
        if not ss:
            return {"s": self.look.frame_px / (CANVAS * 0.8), "ox": -CANVAS * 0.1 * self.look.frame_px / (CANVAS * 0.8),
                    "oy": -CANVAS * 0.1 * self.look.frame_px / (CANVAS * 0.8), "source": "default", "canvas": CANVAS}
        s = float(np.median(ss))
        for cb, rb in pairs:
            oxs.append((cb[0] + opx) - rb[0] * s)
            oys.append((cb[1] + opx) - rb[1] * s)
        ox, oy = float(np.median(oxs)), float(np.median(oys))
        res = []
        for cb, rb in pairs:
            res.append(max(abs((cb[0] + opx) - (rb[0] * s + ox)), abs((cb[1] + opx) - (rb[1] * s + oy)),
                           abs((cb[2] - opx) - (rb[2] * s + ox)), abs((cb[3] - opx) - (rb[3] * s + oy))))
        return {"s": s, "ox": ox, "oy": oy, "source": "measured", "pairs": len(pairs), "residual_px": float(np.median(res)) if res else None,
                "worst_px": float(max(res)) if res else None, "canvas": self.meta.get("canvas", CANVAS)}

    # -- flags (deterministic, no AI)
    def flags(self, staged=True):
        """Per slot, what looks off about the effective frame: a jump from both neighbours, a footprint far off the
        median, an empty frame, a loop seam, a silhouette unlike the driver's. Numbers and the rule each one broke.
        staged=False (pass 96): the flags of the selected versions alone (the "before" of a staged batch)."""
        n = self.n
        cells = self.effective_cells(staged=staged)
        masks = []
        boxes = []
        for c in cells:
            a = np.asarray(c)[..., 3] > 127
            m = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((64, 64), Image.BOX)).astype(np.float32) / 255.0
            masks.append(m)
            boxes.append(bbox(c))
        empties = [float((np.asarray(c)[..., 3] > 127).mean()) for c in cells]

        def dist(i, j):
            return float(np.abs(masks[i] - masks[j]).mean())

        loop = loops(self.base)
        neigh = []
        for i in range(n):
            if n > 1:
                neigh.append(dist(i, (i + 1) % n) if (loop or i + 1 < n) else None)
            else:
                neigh.append(None)
        valid = [d for d in neigh if d is not None]
        med_step = float(np.median(valid)) if valid else 0.0
        ws = [b[2] - b[0] for b in boxes if b]
        hs = [b[3] - b[1] for b in boxes if b]
        mw, mh = (float(np.median(ws)) if ws else 0.0), (float(np.median(hs)) if hs else 0.0)
        drv = self.meta.get("driver")
        out = {}
        for i in range(n):
            f = {}
            if empties[i] < FLAG_RULES["empty"]:
                f["empty"] = {"area": round(empties[i], 4), "rule": "the figure covers under %.1f%% of the cell" % (FLAG_RULES["empty"] * 100)}
            ev, _ = self.effective(i) if staged else self.selected_version(i)
            if ev and ev.get("shrunk"):
                f["footprint"] = {"shrunk": ev["shrunk"], "rule": "its figure was larger than the cell at the group's fit: shrunk to %d%% to fit (the pipeline would have shrunk the whole clip)" % int(round(float(ev["shrunk"]) * 100))}
            if boxes[i] and mw > 0 and mh > 0:
                rw, rh = (boxes[i][2] - boxes[i][0]) / mw, (boxes[i][3] - boxes[i][1]) / mh
                lo, hi = FLAG_RULES["footprint"]
                if not (lo <= rw <= hi and lo <= rh <= hi):
                    f["footprint"] = dict(f.get("footprint") or {}, w=round(rw, 2), h=round(rh, 2),
                                          rule=((f.get("footprint") or {}).get("rule", "") + "; " if f.get("footprint") else "") + "the figure's box is outside %.2f-%.2f of the median" % (lo, hi))
            if n >= 3:
                p, q = (i - 1) % n, (i + 1) % n
                if loop or (0 < i < n - 1):
                    both = dist(p, i) + dist(i, q)
                    across = dist(p, q)
                    score = both / max(across, 1e-6)
                    if across > 1e-6 and score > FLAG_RULES["jump"] and both > 2.0 * med_step:
                        f["jump"] = {"score": round(score, 2), "rule": "it differs from both neighbours %.1fx more than they differ from each other" % score}
            if loop and n >= 4 and i == n - 1 and med_step > 0:
                seam = dist(n - 1, 0) / med_step
                if seam > FLAG_RULES["seam"]:
                    f["seam"] = {"score": round(seam, 2), "rule": "the last frame to the first differs %.1fx the median step: the loop jumps" % seam}
            if drv and i < len(drv.get("index") or []):
                iou = self._silhouette_iou(i, drv, staged=staged)
                if iou is not None and iou < FLAG_RULES["silhouette"]:
                    f["silhouette"] = {"iou": round(iou, 2), "rule": "its silhouette overlaps the driver's frame by only %d%% (boxes aligned)" % int(iou * 100)}
            out[str(i)] = f
        return out

    def _silhouette_iou(self, slot, drv, staged=True):
        v, _ = self.effective(slot) if staged else self.selected_version(slot)
        if not v:
            return None
        raw = self.raw_of(slot, v)
        if raw is None:
            return None
        p = os.path.join(REPO, drv["dir"], drv["pattern"] % drv["index"][slot])
        if not os.path.isfile(p):
            return None
        d = Image.open(p).convert("L")
        dm = np.asarray(d) > 12
        rm = np.asarray(raw)[..., 3] > 127
        rb, db = bbox(raw), None
        ys, xs = np.nonzero(dm)
        if len(xs) < 8 or not rb:
            return None
        db = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
        # the driver's box fitted onto the frame's box, then the overlap
        dcrop = Image.fromarray((dm[db[1]:db[3], db[0]:db[2]] * 255).astype(np.uint8)).resize((rb[2] - rb[0], rb[3] - rb[1]), Image.BILINEAR)
        a = np.asarray(dcrop) > 127
        b = rm[rb[1]:rb[3], rb[0]:rb[2]]
        inter = float((a & b).sum())
        union = float((a | b).sum())
        return inter / union if union > 0 else None

    # -- what the page shows
    def detail(self, url_of):
        """The group as the page wants it: every slot with its versions (urls through `url_of(path)`), the choices,
        the flags, the driver frames, the fit."""
        sel, st = self.selected(), self.staged()
        drv = self.meta.get("driver")
        slots = []
        for k in range(self.n):
            vs = []
            for v in self.versions(k):
                rec = {x: v.get(x) for x in ("id", "label", "n", "source", "space", "by", "time", "from", "seed", "prompt", "model", "job", "qa", "clip_key", "clip_frame", "raw", "note",
                                             "driver", "wan", "shrunk", "window", "control", "reference")}
                rec["url"] = url_of(self.cell_url_file(k, v))
                rec["src_url"] = url_of(v["file"])
                rec["name"] = self.name_of(k, v)   # pass 96: Garry's label (`SP-A / Run / Side / Frame 07 / v2`)
                vs.append(rec)
            eff, how = self.effective(k)
            cur = sel.get(str(k)) or {}
            rec = {"slot": k, "versions": vs, "selected": cur.get("id"), "pinned": bool(cur.get("pinned")), "installed_differs": cur.get("installed_differs"),
                   "staged": (st.get(str(k)) or {}).get("id"), "effective": eff["id"] if eff else None, "effective_how": how,
                   "url": url_of(self.cell_url_file(k, eff)) if eff else None, "name": self.name_of(k), "was_pinned": cur.get("was_pinned")}
            if drv:
                rec["driver_url"] = url_of(os.path.join(REPO, drv["dir"], drv["pattern"] % drv["index"][k]))
                rec["driver_frame"] = drv["index"][k]
            slots.append(rec)
        return {"ok": True, "kind": self.look.kind, "id": self.look.cid, "code": self.look.code, "base": self.base, "view": self.view, "key": self.key,
                "n": self.n, "loop": loops(self.base), "frame_px": self.look.frame_px, "fps": self.look.fps, "slots": slots,
                "staged_count": len(st), "fit": self.fit(), "clip": self.meta.get("clip"), "driver": drv, "ref_still": self.meta.get("ref_still"),
                "ref_url": url_of(os.path.join(REPO, self.meta["ref_still"])) if self.meta.get("ref_still") else None,
                "method": self.meta.get("method"), "post": self.meta.get("post"), "path": _rel(self.dir), "flags": self.flags(),
                "store_version": self.meta.get("store_version"), "in_play": bool(getattr(self.look, "in_play", False)),
                "lost_pins": self.meta.get("lost_pins") or [],   # pass 96: pins a landing could not re-apply (the versions stay)
                # where the frames live (the page's help line): the strip the game plays, the clip cache, the backups
                "strip_file": _rel(self.look.strip_path) if getattr(self.look, "strip_path", "") else "",
                "clip_dir": (self.meta.get("clip") or {}).get("dir"), "backups_dir": _rel(os.path.join(BACKUPS, self.look.cid))}


# ---------------------------------------------------------------- the look's groups

def groups_of(look, store=None):
    """[(base, view, key, count)] of the look's animations in the strip's order."""
    out = []
    for key in order_of(look.kind):
        n = int(look.anims.get(key, 0) or 0)
        if n > 0:
            base, view = anim_parts(look.kind, key)
            out.append((base, view, key, n))
    return out


def register_look(kind, cid, code, force=False, store=None, content=None):
    """The retrofit of an existing look (or a sync after a landing): every animation x view of its installed strip
    registered (Group.register). Returns {ok, groups: [...]}; a look without a strip registers nothing."""
    look = Look(kind, cid, code, content)
    if not look.has_strip():
        return {"ok": False, "error": "%s %s has no strip (%s)" % (cid, code, look.sprite_name or "no sprite named"), "groups": []}
    cells = look.cells()
    out = []
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        out.append(g.register(cells.get(key, []), force=force))
    return {"ok": True, "kind": kind, "id": cid, "code": code, "strip": look.sprite_name, "groups": out}


def look_summary(kind, cid, code, store=None, content=None, register=True):
    """Every group of a look with its counts (registering it first when it is new): the Frames view's tabs."""
    look = Look(kind, cid, code, content)
    if not look.has_strip():
        return {"ok": False, "error": "no strip for %s %s" % (cid, code), "groups": []}
    gs = []
    need = False
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        if not g.exists() or g.n != n or (g.meta.get("strip") or {}).get("mtime") != int(os.stat(look.strip_path).st_mtime):
            need = True
    if need and register:
        register_look(kind, cid, code, store=store, content=content)
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        st = g.staged()
        vers = sum(len(g.versions(k)) for k in range(g.n))
        gs.append({"base": base, "view": view, "key": key, "n": n, "staged": len(st), "versions": vers, "loop": loops(base),
                   "clip": (g.meta.get("clip") or {}).get("key"), "driver": (g.meta.get("driver") or {}).get("name"),
                   "fit": (g.meta.get("fit") or {}).get("source", "default"), "pinned": sum(1 for s in g.selected().values() if s.get("pinned"))})
    return {"ok": True, "kind": kind, "id": cid, "code": code, "strip": look.sprite_name, "frame_px": look.frame_px, "fps": look.fps,
            "method": look.method(), "groups": gs, "staged": sum(x["staged"] for x in gs), "is_base": look.is_base,
            "in_play": look.in_play, "strip_file": _rel(look.strip_path), "pinned": sum(x["pinned"] for x in gs)}


class StoreLook:
    """A look the JSON no longer lists (removed: its strip moved to backups/deleted/) as the store still knows it from its
    group.json files: enough for Group to serve its versions to the picker (pass 95 resume, AN-07 / AN-14: the picker
    marks them "removed"; their frames stay copyable, a copy never links back)."""

    def __init__(self, kind, cid, code, store=None):
        self.kind, self.cid, self.code = kind, cid, code
        self.removed = True
        self.is_base = False
        self.in_play = False
        self.entry = {}
        self.recipe = {}
        self.d = {}
        self.sprite_name = ""
        self.strip_path = ""
        root = os.path.join(store or STORE, kind, cid, code)
        self.anims, self._outline, self._post, self.fps, self.frame_px = {}, None, {"drop_islands": True}, {}, (256 if player_kind(kind) == "hero" else 128)
        for base in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            for view in sorted(os.listdir(os.path.join(root, base))) if os.path.isdir(os.path.join(root, base)) else []:
                meta = _load(os.path.join(root, base, view, "group.json"))
                if not isinstance(meta, dict) or not meta.get("key"):
                    continue
                self.anims[meta["key"]] = int(meta.get("n", 0) or 0)
                self.frame_px = int(meta.get("frame_px") or self.frame_px)
                self.fps = meta.get("fps") or self.fps
                if meta.get("outline"):
                    self._outline = (int(meta["outline"].get("px", 1)), tuple(meta["outline"].get("color", DEFAULT_OUTLINE[player_kind(kind)][1])))
                if meta.get("post"):
                    self._post = meta["post"]

    def has_strip(self):
        return False

    def method(self):
        return "removed"

    def outline(self):
        if self._outline:
            return self._outline
        frac, col = DEFAULT_OUTLINE[player_kind(self.kind)]
        return max(1, int(round(self.frame_px * frac))), col

    def post(self):
        return dict(self._post)


def removed_looks(kind, cid, store=None, content=None):
    """The codes the store holds for an asset that its JSON no longer lists."""
    root = os.path.join(store or STORE, kind, cid)
    if not os.path.isdir(root):
        return []
    try:
        doc = _load(os.path.join(content or CONTENT, KIND_FOLDERS[kind], cid, cid + ".json"), {}) or {}
    except KeyError:
        return []
    vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    listed = set(vs) | {str(doc.get("variant_base", ""))}
    return sorted(c for c in os.listdir(root) if c not in listed and os.path.isdir(os.path.join(root, c)) and not c.startswith("_"))


def other_looks(kind, cid, code, base, view, store=None, content=None):
    """Every other look of the same asset that has this animation x view, with its slots' versions (labels, urls
    through the caller) and the compatibility facts: frame_px, slot count. Looks never registered are registered."""
    look = Look(kind, cid, code, content)
    vs = look.doc.get("variants") if isinstance(look.doc.get("variants"), dict) else {}
    codes = [c for c in vs] + ([look.base_code] if look.base_code and look.base_code not in vs else [])
    out = []
    for c in sorted(set(codes)):
        if c == code:
            continue
        try:
            other = Look(kind, cid, c, content)
        except ValueError:
            continue
        if not other.has_strip():
            continue
        key = anim_key(kind, base, view)
        n = int(other.anims.get(key, 0) or 0)
        if n <= 0:
            continue
        g = Group(other, base, view, store)
        if not g.exists():
            register_look(kind, cid, c, store=store, content=content)
            g = Group(other, base, view, store)
        out.append({"code": c, "note": str(other.entry.get("note", "")), "n": n, "frame_px": other.frame_px, "group": g, "removed": False})
    # the looks the JSON no longer lists, from their group.json (marked removed; their versions stay copyable)
    for c in removed_looks(kind, cid, store, content):
        if c == code:
            continue
        other = StoreLook(kind, cid, c, store)
        key = anim_key(kind, base, view)
        n = int(other.anims.get(key, 0) or 0)
        g = Group(other, base, view, store)
        if n <= 0 or not g.exists():
            continue
        out.append({"code": c, "note": "removed look (its strip is under tools/level_editor/backups/deleted/%s/)" % cid, "n": n, "frame_px": other.frame_px, "group": g, "removed": True})
    return out


def copy_version(dst, src_group, src_slot, src_vid, dst_slot, by="human"):
    """A version of another look's slot copied into this slot (a new version here, its `from` naming the source);
    raw when the source has a raw picture (this look's fit then sizes it), else the cell (resized when the cells differ)."""
    sv = src_group.version(src_slot, src_vid)
    if not sv:
        raise ValueError("no version %s in %s slot %s" % (src_vid, src_group.key, src_slot))
    frm = {"kind": src_group.look.kind, "id": src_group.look.cid, "code": src_group.look.code, "base": src_group.base, "view": src_group.view,
           "slot": int(src_slot), "version": src_vid, "label": sv.get("label")}
    if getattr(src_group.look, "removed", False):
        frm["removed"] = True
    raw = src_group.raw_of(src_slot, sv)
    if raw is not None and sv.get("space") == "raw":
        return dst.add_version(dst_slot, raw, "raw", "copied", by=by, **{"from": frm})
    if raw is not None:
        v = dst.add_version(dst_slot, raw, "raw", "copied", by=by, **{"from": frm})
        return v
    cell = src_group.cell_of(src_slot, sv)
    if cell.width != dst.look.frame_px:
        cell = cell.resize((dst.look.frame_px, dst.look.frame_px), Image.LANCZOS)
        frm["resized_from_px"] = sv.get("size", [cell.width])[0]
    return dst.add_version(dst_slot, cell, "cell", "copied", by=by, **{"from": frm})


# ---------------------------------------------------------------- the export

def export_look(kind, cid, code, job=None, store=None, content=None, backups=None, sidecar=None):
    """The strip packed again from every group's effective versions with the pipeline's own packing (artkit.pack_strip
    in the kind's order), the old strip kept under tools/level_editor/backups/<id>/, the staged choices committed, the
    entry (sprite, anims, strip_cols, head) written as a job sidecar (result.json) for the Level Editor to merge, or
    returned. Nothing is written when the packed strip equals the installed one."""
    look = Look(kind, cid, code, content)
    if not look.has_strip():
        return {"ok": False, "error": "no strip for %s %s" % (cid, code)}
    summary = look_summary(kind, cid, code, store, content)
    frames = {}
    changed = []
    cells_now = look.cells()
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        st = g.staged()
        sel = g.selected()
        seq = []
        for k in range(n):
            v, how = g.effective(k)
            cell = g.cell_of(k, v) if v else cells_now.get(key, [None] * n)[k]
            seq.append(cell)
            if str(k) in st:
                changed.append({"group": key, "slot": k, "to": v.get("label") if v else None, "id": v.get("id") if v else None,
                                "name": g.name_of(k, v) if v else g.name_of(k), "why": "staged"})
            elif (sel.get(str(k)) or {}).get("pinned") and (sel.get(str(k)) or {}).get("installed_differs") and v:
                # pass 96 (AN-09 Q4): a pinned choice the installed strip does not show is packed again (the re-apply)
                changed.append({"group": key, "slot": k, "to": v.get("label"), "id": v.get("id"), "name": g.name_of(k, v), "why": "pinned"})
        frames[key] = seq
    strip, counts, cols = artkit.pack_strip(frames, order_of(kind), look.frame_px)
    data = png_bytes(strip)
    old = open(look.strip_path, "rb").read()
    if data == old and not changed:
        return {"ok": True, "unchanged": True, "strip": look.sprite_name, "changed": []}
    stamp = time.strftime("%Y%m%d-%H%M%S")
    bdir = os.path.join(backups or BACKUPS, cid)
    os.makedirs(bdir, exist_ok=True)
    ignore = os.path.join(backups or BACKUPS, ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8", newline="\n") as f:
            f.write("*\n")
    backup = os.path.join(bdir, "frames_%s_%s" % (stamp, look.sprite_name))
    shutil.copy2(look.strip_path, backup)
    prune_strip_backups(bdir)
    # the entry as it was (the rollback's old entry when the merge or the import fails after this)
    old_entry = {k: look.entry.get(k) for k in ("sprite", "anims", "strip_cols", "head", "fps") if look.entry.get(k) is not None} if not look.is_base else \
        {k: look.doc.get(k) for k in ("sprite", "anims", "strip_cols", "head", "fps") if look.doc.get(k) is not None}
    tmp = look.strip_path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, look.strip_path)
    # the choices committed: staged -> selected (pinned: a human chose it), the export logged
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        st = g.staged()
        for k, rec in st.items():
            g.select(int(k), rec["id"], by="export", pinned=True)
        g.unstage()
        logp = os.path.join(g.dir, "exports.json")
        log = _load(logp, []) or []
        log.append({"time": _now(), "job": job, "strip_sha1": sha_of(data), "changed": [c for c in changed if c["group"] == key], "backup": _rel(backup)})
        _save(logp, log)
        gs = os.stat(look.strip_path)
        g.meta["strip"] = {"file": look.sprite_name, "mtime": int(gs.st_mtime), "size": gs.st_size}
        g.save_meta()
    entry = {"sprite": look.sprite_name, "anims": counts, "strip_cols": cols}
    if kind != "hero":
        idle_run = frames.get("idle", []) + frames.get("run", [])
        if idle_run:
            entry["head"] = round(max(figure_top(f) for f in idle_run), 3)
    if look.fps:
        entry["fps"] = look.fps
    reapplied = [c for c in changed if c.get("why") == "pinned"]
    out = {"ok": True, "strip": look.sprite_name, "file": _rel(look.strip_path), "backup": _rel(backup), "changed": changed, "entry": entry,
           "strip_sha1": sha_of(data), "strip_sha1_before": sha_of(old), "cols": cols, "frames": sum(counts.values()), "old_entry": old_entry, "in_play": look.in_play,
           "names": [c["name"] for c in changed], "reapplied": len(reapplied)}
    side = sidecar or os.environ.get("ASSET_JOB_SIDECAR", "")
    if side:
        rec = {"id": cid, "folder": look.folder, "variant": code, "entry": entry, "top": {}, "info": {"pipeline": "frames_export", "changed": changed, "backup": _rel(backup),
                                                                                                "old_entry": old_entry, "strip_sha1": sha_of(data), "strip_sha1_before": sha_of(old),
                                                                                                "in_play": look.in_play, "names": out["names"], "reapplied": len(reapplied),
                                                                                                "outputs": [{"label": "strip", "type": "strip", "file": _rel(look.strip_path)}]}}
        os.makedirs(os.path.dirname(side) or ".", exist_ok=True)
        with open(side, "w", encoding="utf-8", newline="\n") as f:
            json.dump(rec, f, indent=1, ensure_ascii=False)
        out["sidecar"] = side
    return out


def figure_top(cell_img):
    a = np.asarray(cell_img)[..., 3] > 127
    ys = np.nonzero(a.max(axis=1))[0]
    return (cell_img.height - float(ys.min())) / cell_img.height if len(ys) else 0.0


def staged_batch(kind, cid, code, url_of=None, store=None, content=None):
    """pass 96 (lane PAGE, Garry's decision 5): what the next Export of a look replaces, as the one confirm box lists
    it: every staged change as a before / after pair (the selected version -> the staged one, both named in Garry's
    form) with the flag deltas (the flags the change raises and clears), plus the pinned slots whose installed cell
    differs (packed again by the export: the re-apply), whether the game plays the look and where the old strip goes."""
    look = Look(kind, cid, code, content)
    url = url_of or (lambda p: _rel(p))
    items = []
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        st = g.staged()
        sel = g.selected()
        pinned_differs = [int(k) for k, s in sel.items() if s.get("pinned") and s.get("installed_differs") and int(k) < n]
        if not st and not pinned_differs:
            continue
        before = g.flags(staged=False) if st else {}
        after = g.flags(staged=True) if st else {}
        for ks, rec in sorted(st.items(), key=lambda x: int(x[0])):
            k = int(ks)
            to = g.version(k, rec.get("id"))
            frm, _ = g.selected_version(k)
            if not to:
                continue
            fb, fa = set((before.get(ks) or {}).keys()), set((after.get(ks) or {}).keys())
            items.append({"group": key, "base": base, "view": view, "slot": k, "name": g.name_of(k), "why": "staged",
                          "from": _batch_side(g, k, frm, url), "to": _batch_side(g, k, to, url), "source": to.get("source"),
                          "staged_why": rec.get("why"), "flags": {"raised": sorted(fa - fb), "cleared": sorted(fb - fa),
                                                                   "after": {f: (after.get(ks) or {}).get(f, {}).get("rule") for f in sorted(fa)}}})
        for k in sorted(pinned_differs):
            if str(k) in st:
                continue
            cur = sel.get(str(k)) or {}
            to = g.version(k, cur.get("id"))
            frm = g.version(k, cur.get("installed_differs"))
            if not to:
                continue
            items.append({"group": key, "base": base, "view": view, "slot": k, "name": g.name_of(k), "why": "pinned",
                          "from": _batch_side(g, k, frm, url) if frm else None, "to": _batch_side(g, k, to, url), "source": to.get("source"),
                          "staged_why": "a pinned choice the installed strip does not show: re-applied", "flags": {"raised": [], "cleared": [], "after": {}}})
    return {"ok": True, "kind": kind, "id": cid, "code": code, "items": items, "staged": sum(1 for i in items if i["why"] == "staged"),
            "pinned_reapply": sum(1 for i in items if i["why"] == "pinned"), "in_play": look.in_play, "strip_file": _rel(look.strip_path),
            "backup_dir": _rel(os.path.join(BACKUPS, cid)), "replaces_installed": look.has_strip()}


def _batch_side(g, k, v, url):
    if not v:
        return None
    return {"id": v.get("id"), "label": v.get("label"), "n": v.get("n"), "name": g.name_of(k, v), "source": v.get("source"),
            "url": url(g.cell_url_file(k, v)), "seed": v.get("seed"), "job": v.get("job"), "time": v.get("time")}


def reapply_pins(kind, cid, code, override=None, log=None, job=None, store=None, content=None, backups=None):
    """pass 96 (lane PAGE, AN-09 Q4, a hand run): the strip just saved by gen_art / gen_ctl packed again in-process with
    the pinned versions on the pinned slots and the run's new cells everywhere else, written over that strip before the
    JSON dump (the run's own counts through `override`), logged in exports.json (`why: reapply`). Nothing staged
    changes. Returns {ok, pinned: N, slots: [(group, slot)], names, misfit, backup}; pinned 0 = nothing to do."""
    say = log or (lambda *a: None)
    look = Look(kind, cid, code, content, override=override)
    if not look.has_strip():
        return {"ok": False, "error": "no strip", "pinned": 0}
    frames, hits, names = {}, [], []
    cells_now = look.cells()
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        sel = g.selected()
        seq = []
        for k in range(n):
            cur = sel.get(str(k)) or {}
            if cur.get("pinned") and cur.get("installed_differs"):
                v = g.version(k, cur.get("id"))
                if v:
                    seq.append(g.cell_of(k, v))
                    hits.append((key, k))
                    names.append(g.name_of(k, v))
                    continue
            seq.append(cells_now.get(key, [None] * n)[k])
        frames[key] = seq
    if not hits:
        return {"ok": True, "pinned": 0, "slots": [], "names": []}
    strip, counts, cols = artkit.pack_strip(frames, order_of(kind), look.frame_px)
    data = png_bytes(strip)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    bdir = os.path.join(backups or BACKUPS, cid)
    os.makedirs(bdir, exist_ok=True)
    backup = os.path.join(bdir, "frames_%s_%s" % (stamp, look.sprite_name))
    shutil.copy2(look.strip_path, backup)
    prune_strip_backups(bdir)
    tmp = look.strip_path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, look.strip_path)
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        mine = [k for (kk, k) in hits if kk == key]
        if not mine:
            continue
        sel = g.selected()
        for k in mine:
            cur = sel.get(str(k)) or {}
            cur.pop("installed_differs", None)   # the strip shows the pinned choice again
            sel[str(k)] = cur
        g._write_sel(sel)
        logp = os.path.join(g.dir, "exports.json")
        lg = _load(logp, []) or []
        lg.append({"time": _now(), "job": job, "strip_sha1": sha_of(data), "why": "reapply",
                   "changed": [{"group": key, "slot": k, "id": (sel.get(str(k)) or {}).get("id"), "why": "pinned", "name": g.name_of(k, g.version(k, (sel.get(str(k)) or {}).get("id")))} for k in mine],
                   "backup": _rel(backup)})
        _save(logp, lg)
        gs = os.stat(look.strip_path)
        g.meta["strip"] = {"file": look.sprite_name, "mtime": int(gs.st_mtime), "size": gs.st_size}
        g.save_meta()
    say("frames_store: re-applied %d pinned frame%s into %s (%s; the run's strip is kept under %s)" % (
        len(hits), "" if len(hits) == 1 else "s", look.sprite_name, ", ".join(names[:6]) + (", ..." if len(names) > 6 else ""), _rel(backup)))
    return {"ok": True, "pinned": len(hits), "slots": hits, "names": names, "backup": _rel(backup), "strip_sha1": sha_of(data), "counts": counts, "cols": cols}


def misfit_text(misfit):
    """One line for the pins a landing could not re-apply: "2 pinned frames could not be re-applied: the animation has 8 frames now"."""
    ms = [m for m in (misfit or []) if m]
    if not ms:
        return ""
    whys = []
    for m in ms:
        if m.get("text") and m["text"] not in whys:
            whys.append(m["text"])
    return "%d pinned frame%s could not be re-applied: %s (%s; their versions are kept)" % (
        len(ms), "" if len(ms) == 1 else "s", "; ".join(whys), ", ".join(str(m.get("name") or m.get("slot")) for m in ms[:6]) + (", ..." if len(ms) > 6 else ""))


def rollback_export(kind, cid, code, backup, changed=None, job=None, why="", store=None, content=None):
    """An export undone (pass 95 resume, AN-09: the merge or the import after it failed): the strip put back from the
    export's backup, the exported choices unpinned and STAGED again (nothing Garry chose is lost: the next Export packs
    them once the cause is fixed), the installed cells selected again, the rollback logged in exports.json. The old
    entry is the caller's to merge back (the Level Editor's hook); this touches only the strip and the store."""
    look = Look(kind, cid, code, content)
    bpath = os.path.join(REPO, backup) if not os.path.isabs(backup) else backup
    if not os.path.isfile(bpath):
        return {"ok": False, "error": "no backup at %s" % _rel(bpath)}
    data = open(bpath, "rb").read()
    tmp = look.strip_path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, look.strip_path)
    staged_again = []
    by_group = {}
    for c in changed or []:
        by_group.setdefault(c.get("group"), []).append(c)
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        for c in by_group.get(key, []):
            k = int(c.get("slot", -1))
            if k < 0 or not c.get("id") or not g.version(k, c["id"]):
                continue
            g.pin(k, False)
            staged_again.append({"group": key, "slot": k, "id": c["id"]})
    reg = register_look(kind, cid, code, store=store, content=content)   # the installed cells selected again (nothing pinned now)
    for base, view, key, n in groups_of(look):
        g = Group(look, base, view, store)
        for c in staged_again:
            if c["group"] == key:
                try:
                    g.stage(c["slot"], c["id"], why="staged again by the rollback")
                except ValueError:
                    pass
        logp = os.path.join(g.dir, "exports.json")
        log = _load(logp, []) or []
        log.append({"time": _now(), "job": job, "rollback": True, "strip_sha1": sha_of(data), "backup": _rel(bpath), "why": why,
                    "staged_again": [c for c in staged_again if c["group"] == key]})
        _save(logp, log)
    return {"ok": True, "strip": look.sprite_name, "restored_from": _rel(bpath), "staged_again": staged_again, "register": reg.get("ok")}


# ---------------------------------------------------------------- retention (pass 95 resume, AN-14)

def prune_strip_backups(bdir, keep=None):
    """The newest `keep` strip backups of an asset kept (frames_<stamp>_<file>.png), the older removed, like the JSON
    backups (server.KEEP_BACKUPS = 30)."""
    keep = RETENTION["strip_backups"] if keep is None else int(keep)
    if not os.path.isdir(bdir):
        return []
    mine = sorted(f for f in os.listdir(bdir) if f.startswith("frames_") and f.endswith(".png"))
    gone = []
    for f in mine[:-keep] if keep > 0 else mine:
        try:
            os.remove(os.path.join(bdir, f))
            gone.append(f)
        except OSError:
            pass
    return gone


def prune_repairs(out_dir=None, days=None, now=None):
    """The repair sheets and window pictures (tools/dl/frames/_repairs) older than `days` removed; the versions they
    led to live in the slots and are never touched."""
    days = RETENTION["repair_days"] if days is None else float(days)
    d = out_dir or os.path.join(STORE, "_repairs")
    if not os.path.isdir(d):
        return []
    now = time.time() if now is None else float(now)
    gone = []
    for f in os.listdir(d):
        p = os.path.join(d, f)
        if not os.path.isfile(p) or not re.match(r"^(repair|window|dry_run)_", f):
            continue
        try:
            if now - os.path.getmtime(p) > days * 86400:
                os.remove(p)
                gone.append(f)
        except OSError:
            pass
    return gone


def referenced_ids(kind, cid, store=None):
    """Every version id anything in the asset's store refers to: a selection (and what it says differs), a staged
    choice, an export's changes, a copy's `from` in any look of the asset. A version in this set is never deleted."""
    root = os.path.join(store or STORE, kind, cid)
    refs = set()
    if not os.path.isdir(root):
        return refs
    for code in os.listdir(root):
        croot = os.path.join(root, code)
        if not os.path.isdir(croot) or code.startswith("_"):
            continue
        for base in os.listdir(croot):
            for view in os.listdir(os.path.join(croot, base)) if os.path.isdir(os.path.join(croot, base)) else []:
                gdir = os.path.join(croot, base, view)
                if not os.path.isdir(gdir):
                    continue
                for s in ((_load(os.path.join(gdir, "selected.json"), {}) or {}).get("slots") or {}).values():
                    refs.add(s.get("id"))
                    if s.get("installed_differs"):
                        refs.add(s["installed_differs"])
                for s in ((_load(os.path.join(gdir, "staged.json"), {}) or {}).get("slots") or {}).values():
                    refs.add(s.get("id"))
                for e in _load(os.path.join(gdir, "exports.json"), []) or []:
                    for c in e.get("changed") or []:
                        refs.add(c.get("id"))
                    for c in e.get("staged_again") or []:
                        refs.add(c.get("id"))
                for sd in os.listdir(gdir):
                    sdir = os.path.join(gdir, sd)
                    if not (sd.startswith("slot_") and os.path.isdir(sdir)):
                        continue
                    for f in os.listdir(sdir):
                        if re.match(r"^v\d{3}\.json$", f):
                            v = _load(os.path.join(sdir, f), {}) or {}
                            frm = v.get("from") if isinstance(v.get("from"), dict) else {}
                            if frm.get("version"):
                                refs.add(frm["version"])
    refs.discard(None)
    return refs


def delete_version(group, slot, vid, store=None):
    """RETIRED (pass 96, Garry's decision 10: every reusable frame version is kept indefinitely): always refuses, kept
    as a function so nothing that calls it breaks. The refusal names the version when it exists. Nothing is removed."""
    v = group.version(slot, vid)
    name = group.name_of(slot, v) if v else "%s slot %s" % (vid, slot)
    return {"ok": False, "retired": True, "referenced": bool(v and vid in referenced_ids(group.look.kind, group.look.cid, store or group.store)),
            "error": "%s stays: %s" % (name, NEVER_DELETED)}


# ---------------------------------------------------------------- the hand-run hook (pass 95 resume, AN-10)

def hook_after_save(folder, cid, code, counts=None, cols=None, sprite=None, log=None):
    """One line after every strip.save in gen_art / gen_ctl: when the look already has a store, its groups are
    registered again from the strip just saved (the pipeline's own counts and cols, since the JSON entry is written
    later), so the store never lags a hand run; with pinned slots a warning says the strip replaced a human choice and
    Export is the writer for this look. A look the store never saw is left alone (the Frames view registers it when
    opened). Never raises."""
    say = log or (lambda *a: print(*a, flush=True))
    try:
        kind = {"enemies": "enemy", "bosses": "boss", "characters": "hero"}.get(os.path.basename(os.path.dirname(os.path.abspath(folder))))
        if not kind:
            return None
        doc = _load(os.path.join(folder, cid + ".json"), {}) or {}
        code = str(code or doc.get("variant_base") or "")
        if not code or not CODE_RE.match(code):
            return None
        if not os.path.isdir(os.path.join(STORE, kind, cid, code)):
            return None
        ov = {"anims": counts, "strip_cols": cols, "sprite": sprite}
        look = Look(kind, cid, code, override=ov)
        if not look.has_strip():
            return None
        cells = look.cells()
        pinned = []
        misfit = []
        out = []
        for base, view, key, n in groups_of(look):
            g = Group(look, base, view)
            r = g.register(cells.get(key, []))
            out.append(r)
            misfit += [dict(m, group=key) for m in (r.get("misfit") or [])]
            pinned += [(key, int(k)) for k, s in g.selected().items() if s.get("pinned") and s.get("installed_differs")]
        reapplied = None
        if pinned:
            # pass 96 (Garry's decision 4): the run's new cells never displace a pinned frame: the strip is packed again
            # in-process with the pinned versions before the JSON dump (the new cells are versions already, nothing is lost)
            reapplied = reapply_pins(kind, cid, code, override=ov, log=say)
            if not reapplied.get("ok"):
                say("frames_store: WARNING %s %s has %d pinned frame(s) (%s) this run's strip replaced and the re-pack failed (%s): "
                    "open Frames... in the Level Editor and Export to put the pinned choices back" % (
                        cid, code, len(pinned), ", ".join("%s/%d" % p for p in pinned[:6]) + (", ..." if len(pinned) > 6 else ""), reapplied.get("error")))
        else:
            say("frames_store: %s %s registered again from the saved strip (%d animations)" % (cid, code, len(out)))
        if misfit:
            say("frames_store: WARNING %s %s: %s" % (cid, code, misfit_text(misfit)))
        return {"ok": True, "pinned": pinned, "groups": out, "reapplied": reapplied, "misfit": misfit}
    except Exception as e:   # noqa: BLE001  a store problem must never fail a painting run
        say("frames_store: the store hook failed for %s %s: %s: %s" % (cid, code, type(e).__name__, e))
        return {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}


# ---------------------------------------------------------------- the post filters (copies of gen_ctl's, so the store needs no gen_art import)

def drop_islands(img, frac=0.08, gap=6):
    """gen_ctl.drop_islands: alpha blobs smaller than `frac` of the largest that lie more than `gap` px from it, cleared."""
    try:
        from scipy import ndimage
    except ImportError:
        return img
    a = np.asarray(img.convert("RGBA")).copy()
    mask = a[..., 3] > 40
    labels, n = ndimage.label(mask)
    if n <= 1:
        return img
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    main = int(np.argmax(sizes)) + 1
    near = ndimage.binary_dilation(labels == main, iterations=gap)
    gone = 0
    for i, sz in enumerate(sizes, start=1):
        if i != main and sz < sizes.max() * frac and not (near & (labels == i)).any():
            a[labels == i, 3] = 0
            gone += 1
    return Image.fromarray(a, "RGBA") if gone else img


def no_green(img, mode=True):
    """gen_ctl.no_green: any green in a frame is the screen's spill, held down to red (mode "rb": to max(red, blue))."""
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 0
    r, gch = a[..., 0].astype(np.int16), a[..., 1].astype(np.int16)
    cap = np.maximum(r, a[..., 2].astype(np.int16)) if mode == "rb" else r
    a[..., 1] = np.where(m & (gch > cap), cap, gch).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


# ---------------------------------------------------------------- the command line

def _main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    cmd, kind, cid, code = argv[0], argv[1], argv[2], argv[3]
    if cmd == "register":
        r = register_look(kind, cid, code, force="--force" in argv)
        print(json.dumps(r, indent=1))
        return 0 if r.get("ok") else 1
    if cmd == "info":
        if len(argv) >= 6:
            g = Group(Look(kind, cid, code), argv[4], argv[5])
            d = g.detail(lambda p: _rel(p))
            d["slots"] = [{k: v for k, v in s.items() if k != "versions"} | {"versions": [x["label"] + " " + x["source"] for x in s["versions"]]} for s in d["slots"]]
            print(json.dumps(d, indent=1))
        else:
            print(json.dumps(look_summary(kind, cid, code), indent=1))
        return 0
    if cmd == "flags":
        g = Group(Look(kind, cid, code), argv[4], argv[5])
        print(json.dumps(g.flags(), indent=1))
        return 0
    if cmd == "export":
        r = export_look(kind, cid, code, job=os.environ.get("ASSET_JOB_ID"))
        print(json.dumps(r, indent=1))
        return 0 if r.get("ok") else 1
    if cmd == "stage" and len(argv) >= 8:
        # a hand run's repair staged by hand (vace_repair.py never writes staged.json: the Level Editor's landing does)
        g = Group(Look(kind, cid, code), argv[4], argv[5])
        print(json.dumps(g.stage(int(argv[6]), argv[7], why="staged by hand"), indent=1))
        return 0
    if cmd == "rollback" and len(argv) >= 5:
        r = rollback_export(kind, cid, code, argv[4], changed=json.loads(argv[5]) if len(argv) > 5 else None, job="cli", why="by hand")
        print(json.dumps(r, indent=1))
        return 0 if r.get("ok") else 1
    print("unknown command %s" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))

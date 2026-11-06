"""Pass 131 (lane RECUI): the "Recolour an existing look" method's one reading of its settings.

The job form writes a block (methods.json `recolour.*`, in the look's recipe as `recolour`, in the job as `spec.recolour`):

    {"from": "CC-B", "mode": "lift", "ranges": [[0, 360]], "to": 40, "set_sat": 0.05, "v_lo": 0.7, ..., "keep_edge": 4,
     "passes": [{"mode": "lift", "ranges": [[0, 40]], "to": 40, "min_sat": 0.05, "cells": [18]}]}

The block's own fields are the first pass; `passes` are further passes run in order on its result (each its own set of
the same fields, plus `cells`: the frames of the strip it runs on alone). This module turns that into
tools/recolour_strip.py's flags (`pass_args`), the job's command lines (`steps`), the words the finished look records
(`record`: `recolour_of` + `recolour_passes`, the shape the shell-made looks of passes 107 and 122 have, +
`recolour_icon_extra`), reads such a recorded line back (`parse_pass`), and runs the passes on one frame and the icon in
memory for the form's before / after (`preview`, POST /api/recolour/preview: no job, nothing written).

jobs.py imports it; nothing heavy is imported until a preview is asked for.
"""
import base64
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)

MODES = ("hue", "tint", "lift")
# what each mode reads (tools/recolour_strip.py): key -> flag, in the order the recorded line is written
FLAGS = (("to", "--to"), ("to_dark", "--to-dark"), ("sat", "--sat"), ("set_sat", "--set-sat"), ("value", "--value"),
         ("v_lo", "--v-lo"), ("v_hi", "--v-hi"), ("gamma", "--gamma"), ("min_sat", "--min-sat"), ("max_sat", "--max-sat"),
         ("min_val", "--min-val"), ("max_val", "--max-val"), ("src_hi", "--src-hi"), ("soft", "--soft"),
         ("hue_soft", "--hue-soft"), ("mass", "--mass"), ("grow", "--grow"), ("mass_sat", "--mass-sat"))
MODE_KEYS = {
    "hue": ("to", "sat", "min_sat", "max_sat"),
    "tint": ("to", "set_sat", "value", "min_sat", "max_sat", "min_val"),
    "lift": ("to", "to_dark", "sat", "set_sat", "v_lo", "v_hi", "gamma", "min_sat", "max_sat", "min_val", "max_val", "src_hi",
             "soft", "hue_soft", "mass", "grow", "mass_sat"),
}
INT_KEYS = ("mass", "grow", "keep_edge")
NUM_KEYS = tuple(k for k, _ in FLAGS) + ("keep_edge",)
_FLAG_KEY = {flag: key for key, flag in FLAGS}
# the recolour block's keys that are not a pass's
BLOCK_ONLY = ("from", "passes", "keep_edge")


def _num(v):
    """A number as the command line and the recorded line carry it: 357, 0.3, never 357.0."""
    f = float(v)
    return str(int(f)) if f == int(f) else ("%.6f" % f).rstrip("0").rstrip(".")


def _blank(v):
    return v is None or v == "" or v == [] or v == {}


def clean_ranges(v, where="ranges"):
    """Hue ranges as [[a, b], ...]: a list of pairs, one pair, or the words "340-360, 0-20". Each 0..360 with a < b: a
    range through red is two ranges."""
    if _blank(v):
        return None
    if isinstance(v, str):
        v = [p.strip().split("-") for p in v.replace(";", ",").split(",") if p.strip()]
    if isinstance(v, (list, tuple)) and len(v) == 2 and not isinstance(v[0], (list, tuple)):
        v = [v]
    out = []
    for r in v if isinstance(v, (list, tuple)) else [v]:
        try:
            a, b = float(r[0]), float(r[1])
            if len(r) != 2:
                raise ValueError
        except (TypeError, ValueError, IndexError, KeyError):
            raise ValueError("%s: each hue range is two numbers, from-to, such as 55-135 (got %r)" % (where, r))
        if a < 0 or b > 360 or a >= b:
            raise ValueError("%s: a hue range runs from a lower to a higher number inside 0-360 (got %s-%s); "
                             "to go through red give two ranges: 340-360 and 0-20" % (where, _num(a), _num(b)))
        out.append([int(a) if a == int(a) else a, int(b) if b == int(b) else b])
    return out or None


def clean_cells(v, where="cells"):
    if _blank(v):
        return None
    if isinstance(v, str):
        v = [p for p in v.replace(";", ",").replace(" ", ",").split(",") if p != ""]
    if not isinstance(v, (list, tuple)):
        v = [v]
    try:
        out = [int(c) for c in v]
    except (TypeError, ValueError):
        raise ValueError("%s: frame numbers counted from 0, such as 18 or 18,61 (got %r)" % (where, v))
    if any(c < 0 for c in out):
        raise ValueError("%s: a frame number is 0 or more (got %r)" % (where, out))
    return out or None


def clean_pass(p, where="recolour"):
    """One pass's fields checked and tidied: only what was given is kept (an absent field is the tool's own default)."""
    if not isinstance(p, dict):
        raise ValueError("%s: a pass is a set of fields (got %r)" % (where, p))
    out = {}
    mode = p.get("mode")
    if not _blank(mode):
        if str(mode) not in MODES:
            raise ValueError("%s.mode: one of %s (got %r)" % (where, ", ".join(MODES), mode))
        out["mode"] = str(mode)
    r = clean_ranges(p.get("ranges"), where + ".ranges")
    if r:
        out["ranges"] = r
    for k in NUM_KEYS:
        if k in p and not _blank(p[k]):
            try:
                f = float(p[k])
            except (TypeError, ValueError):
                raise ValueError("%s.%s: a number (got %r)" % (where, k, p[k]))
            out[k] = int(f) if (k in INT_KEYS or f == int(f)) else f
    if "to" in out and not 0 <= out["to"] <= 360:
        raise ValueError("%s.to: a hue from 0 to 360 (got %s)" % (where, _num(out["to"])))
    c = clean_cells(p.get("cells"), where + ".cells")
    if c:
        out["cells"] = c
    return out


def clean(rc):
    """The whole block: {from, <the first pass's fields>, keep_edge, passes: [...]}. Raises ValueError in plain words."""
    if not isinstance(rc, dict):
        raise ValueError("recolour: a set of fields with `from`, the look to recolour")
    src = str(rc.get("from") or "").strip()
    if not src:
        raise ValueError("recolour needs recolour.from: the look to recolour")
    out = {"from": src}
    first = clean_pass({k: v for k, v in rc.items() if k not in BLOCK_ONLY or k == "keep_edge"}, "recolour")
    first.pop("cells", None)   # the first pass is the whole strip: a pass on chosen frames is an extra pass
    out.update(first)
    extra = rc.get("passes")
    if not _blank(extra):
        if not isinstance(extra, (list, tuple)):
            raise ValueError("recolour.passes: a list of passes")
        ps = []
        for k, p in enumerate(extra):
            q = clean_pass(p, "recolour.passes[%d]" % k)
            q.pop("keep_edge", None)
            if q:
                ps.append(q)
        if ps:
            out["passes"] = ps
    return out


def passes_of(rc):
    """The passes in the order they run: the block's own fields, then `passes`."""
    first = {k: v for k, v in (rc or {}).items() if k not in BLOCK_ONLY}
    return [first] + [p for p in ((rc or {}).get("passes") or []) if isinstance(p, dict)]


def pass_args(p, with_cells=True):
    """One pass as recolour_strip.py's flags (no --src / --dst): only what its mode reads, only what was given."""
    mode = str(p.get("mode") or "hue")
    a = ["--mode", mode] if p.get("mode") else []
    r = p.get("ranges")
    if r:
        a += ["--ranges", ",".join("%s-%s" % (_num(x[0]), _num(x[1])) for x in r if isinstance(x, (list, tuple)) and len(x) == 2)]
    for key, flag in FLAGS:
        if key in MODE_KEYS.get(mode, MODE_KEYS["hue"]) and not _blank(p.get(key)):
            a += [flag, _num(p[key])]
    if with_cells and p.get("cells"):
        a += ["--cells", ",".join(str(int(c)) for c in p["cells"])]
    return a


def icon_extra(rc):
    """What the icon's passes get on top (lift only: recolour_strip's --keep-edge, the icon's grey outer stroke kept)."""
    n = int((rc or {}).get("keep_edge") or 0)
    return ["--keep-edge", str(n)] if n > 0 else []


def record(rc):
    """What the finished look's recipe says ran: {recolour_of, recolour_passes[, recolour_icon_extra]}: the shape of the
    looks recoloured from a shell (RG-C, IMP-A, BB-E, LS-D), so both kinds read alike."""
    out = {"recolour_of": str((rc or {}).get("from") or ""), "recolour_passes": [" ".join(pass_args(p)) for p in passes_of(rc)]}
    extra = icon_extra(rc)
    if extra:
        out["recolour_icon_extra"] = " ".join(extra)
    return out


def parse_pass(line):
    """A recorded line ("--mode lift --ranges 340-360,0-12 --to 26 ...") back as a pass's fields."""
    words = str(line or "").split()
    out = {}
    i = 0
    while i < len(words):
        w, v = words[i], (words[i + 1] if i + 1 < len(words) else None)
        if "=" in w:
            w, v = w.split("=", 1)
            i -= 1
        i += 2
        if v is None:
            continue
        if w == "--mode":
            out["mode"] = v
        elif w == "--ranges":
            out["ranges"] = clean_ranges(v)
        elif w == "--cells":
            out["cells"] = clean_cells(v)
        elif w == "--keep-edge":
            out["keep_edge"] = int(float(v))
        elif w in _FLAG_KEY:
            f = float(v)
            out[_FLAG_KEY[w]] = int(f) if f == int(f) else f
    return out


def steps(rc, py, src_files, dst_files, preview=None, skip_icon=False):
    """The job's command lines. `src_files` / `dst_files`: {"sprite": path, "icon": path} (as the command line names
    them). The first pass reads the source look, every later pass the result so far; the strip's last pass writes the
    preview sheet (the source look beside the result, the frames of any `cells` pass among them)."""
    tool = os.path.join(TOOLS, "recolour_strip.py")
    ps = passes_of(rc)
    cells = sorted({int(c) for p in ps for c in (p.get("cells") or [])})
    out = []
    for suffix in ("sprite", "icon"):
        if suffix == "icon" and skip_icon:
            continue
        for k, p in enumerate(ps):
            a = [py, tool, "--src", src_files[suffix] if k == 0 else dst_files[suffix], "--dst", dst_files[suffix]] + pass_args(p)
            if suffix == "icon":
                a += icon_extra(rc) if str(p.get("mode") or "hue") == "lift" else []
            elif preview and k == len(ps) - 1:
                a += ["--preview", preview]
                if k > 0:
                    a += ["--preview-src", src_files[suffix]]
                if cells:
                    a += ["--preview-cells", ",".join(str(c) for c in cells)]
            out.append(a)
    return out


# ---- the form's before / after --------------------------------------------------------------------------------------

def _strip_tool():
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    import recolour_strip   # noqa: E402  (PIL + numpy: only when a preview is asked for)
    return recolour_strip


def _data_url(im, max_px=256):
    from PIL import Image
    if max(im.size) > max_px:
        k = max_px / float(max(im.size))
        im = im.resize((max(int(im.width * k), 1), max(int(im.height * k), 1)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def preview(rc, sprite_path, icon_path, frame=0, names=None):
    """The passes run in memory on a few frames of the source strip (frame `frame`, the first run frame as the caller
    counts it, and each frame a `cells` pass names) and on its icon. Nothing is written. Returns
    {ok, shots: [{label, before, after}], seconds, notes}; before / after are PNG data URLs."""
    import time
    from PIL import Image
    t0 = time.time()
    rc = clean(rc)
    RS = _strip_tool()
    ps = passes_of(rc)
    shots, notes = [], []
    if sprite_path and os.path.isfile(sprite_path):
        strip = Image.open(sprite_path).convert("RGBA")
        cell = strip.height
        n = max(strip.width // cell, 1)
        want = [min(max(int(frame), 0), n - 1)]
        for p in ps:
            for c in p.get("cells") or []:
                if c < n and c not in want:
                    want.append(c)
                elif c >= n:
                    notes.append("frame %d is past the strip's last frame (%d): that pass skips it" % (c, n - 1))
        for f in want[:4]:
            before = strip.crop((f * cell, 0, (f + 1) * cell, cell))
            after = before
            for p in ps:
                if p.get("cells") and f not in p["cells"]:
                    continue
                after = RS.apply_image(after, pass_args(p, with_cells=False))
            label = (names or {}).get(f) or "frame %d" % f
            shots.append({"label": label, "frame": f, "before": _data_url(before), "after": _data_url(after)})
    else:
        notes.append("the source look's strip is not on disk")
    if icon_path and os.path.isfile(icon_path):
        before = Image.open(icon_path).convert("RGBA")
        after = before
        for p in ps:
            if p.get("cells") and 0 not in p["cells"]:
                continue   # recolour_strip skips a cell outside the icon's one-frame grid
            after = RS.apply_image(after, pass_args(p, with_cells=False) + (icon_extra(rc) if str(p.get("mode") or "hue") == "lift" else []))
        shots.append({"label": "icon", "frame": -1, "before": _data_url(before), "after": _data_url(after)})
    return {"ok": True, "shots": shots, "notes": notes, "seconds": round(time.time() - t0, 3), "passes": record(rc)["recolour_passes"]}

"""Pass 111 (lane ENEMY): a creature look's LEFT-heading sets, appended to its strip as unmirrored copies.

Garry (the Cyclopean Mummy): "instead it's always facing the face direction. But I want you to achieve this by changing
the spritesheet itself instead of just doing this in code ... I want to still make tiny changes to where the Mummy is
facing, but I want to do it myself."

A creature strip may carry six optional animations after idle_fd (artkit.ENEMY_ORDER, EnemyDef.frame_offset):
idle_l, run_l, attack_l, hit_l (the front set as shown while the creature heads screen-LEFT) and run_bl, idle_bl (the
back set heading left). A look whose strip has idle_l or run_l is never mirrored by the game: heading right it shows its
ordinary frames as painted, heading left the left set as painted (die has no left copy). This tool appends them as exact,
unmirrored copies of the right-heading frames (idle_l = idle, run_l = run, attack_l = attack, hit_l = hit, run_bl = run_b,
idle_bl = idle_b; only those the look has), so the creature always faces as painted until someone edits them.

    python tools/add_left_sets.py --id cyclopean_mummy --looks CM-F,CM-G
    python tools/add_left_sets.py --id cyclopean_mummy --looks all            every look in `variants` with its own sprite
    python tools/add_left_sets.py --id cyclopean_mummy --looks all --base     ... and the top-level strip too
    python tools/add_left_sets.py --id cyclopean_mummy --looks CM-F --force   rebuild CM-F's left sets from its right ones
    python tools/add_left_sets.py ... --dry-run                               say what would change, write nothing

For each look: the strip PNG (game/content/enemies/<id>/<sprite>) is cut by the look's anims (frame k at column
k % cols, row k // cols; cols = its strip_cols, or every frame in one row when 0; the cell is the look's frame_px), the
copies are appended after the last frame, the look's strip_cols is kept (the new frames fill the next rows, every existing
frame stays exactly where it is; a one-row strip that would pass 16000 px gets strip_cols = its old frame count), the old
PNG is backed up under tools/dl/p111/enemy/left_sets_backup/<id>/ first, and the look's `anims` gets the six counts by a
small text edit of the JSON (its layout kept; only that `anims` object, and `strip_cols` when it had to be set, change).
A look that already has left sets is skipped unless --force (rebuilt from the right-heading frames: any hand edits of the
left frames are lost; the old strip is in the backup). Then:

    bash tools/godot.sh --headless --path game --import
    bash tools/godot.sh --headless --path game --script res://tools/import_json.gd -- only=enemies/<id>

`--content <dir>` points at another content root (the selftest's temporary copy); `--backup <dir>` another backup root.
"""
import argparse
import json
import math
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
from PIL import Image  # noqa: E402
import artkit  # noqa: E402

CONTENT = os.path.join(REPO, "game", "content")
BACKUP = os.path.join(REPO, "tools", "dl", "p111", "enemy", "left_sets_backup")
ORDER = list(artkit.ENEMY_ORDER)
LEFT = dict(artkit.LEFT_SETS)            # left key -> the right-heading key it copies
LEFT_KEYS = [k for k in ORDER if k in LEFT]
BASE_ORDER = [k for k in ORDER if k not in LEFT]
MAX_WIDTH = 16000


# ---------------------------------------------------------------- a JSON text's value spans (layout-keeping edits)

_WS = " \t\r\n"


def _skip_ws(s, i):
    while i < len(s) and s[i] in _WS:
        i += 1
    return i


def _string_end(s, i):
    """s[i] == '"': the index after the closing quote."""
    i += 1
    while True:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1
        i += 1


def _value_end(s, i):
    """The index after the JSON value starting at s[i]."""
    c = s[i]
    if c == '"':
        return _string_end(s, i)
    if c in "{[":
        close = "}" if c == "{" else "]"
        i = _skip_ws(s, i + 1)
        if s[i] == close:
            return i + 1
        while True:
            if c == "{":
                i = _skip_ws(s, _string_end(s, i))
                i = _skip_ws(s, i + 1)          # the colon
            i = _skip_ws(s, _value_end(s, i))
            if s[i] == ",":
                i = _skip_ws(s, i + 1)
                continue
            if s[i] == close:
                return i + 1
            raise ValueError("bad JSON at %d" % i)
    m = re.compile(r"-?[0-9.eE+\-]+|true|false|null").match(s, i)
    if not m:
        raise ValueError("bad JSON value at %d" % i)
    return m.end()


def members(s, start):
    """[(key, key_start, value_start, value_end)] of the object whose '{' is at s[start]."""
    out = []
    i = _skip_ws(s, start + 1)
    if s[i] == "}":
        return out
    while True:
        k0 = i
        k1 = _string_end(s, i)
        key = json.loads(s[k0:k1])
        i = _skip_ws(s, k1)
        i = _skip_ws(s, i + 1)
        v0 = i
        v1 = _value_end(s, i)
        out.append((key, k0, v0, v1))
        i = _skip_ws(s, v1)
        if s[i] == ",":
            i = _skip_ws(s, i + 1)
            continue
        return out


def value_span(s, path):
    """(start, end) of the value at `path` (a list of object keys) in the JSON text, or None."""
    i = _skip_ws(s, 0)
    for key in path:
        if s[i] != "{":
            return None
        hit = [m for m in members(s, i) if m[0] == key]
        if not hit:
            return None
        i = hit[-1][2]
    return i, _value_end(s, i)


def _line_indent(s, pos):
    """The whitespace that starts the line holding s[pos]."""
    ls = s.rfind("\n", 0, pos) + 1
    m = re.match(r"[ \t]*", s[ls:])
    return m.group(0)


def member_indent(s, obj_start):
    """The indent of an object's members (its first member's line), else its own line's + 2 spaces."""
    ms = members(s, obj_start)
    if ms and "\n" in s[obj_start:ms[0][1]]:
        return _line_indent(s, ms[0][1])
    return _line_indent(s, obj_start) + "  "


def render_flat(obj, like):
    """A flat {key: number} object written in the style of `like` (its old text): one line, or one member a line with
    the old member and closing indents."""
    items = ['"%s": %s' % (k, json.dumps(v)) for k, v in obj.items()]
    if "\n" not in like:
        return "{" + ", ".join(items) + "}"
    m = re.search(r"\n([ \t]*)\"", like)
    mi = m.group(1) if m else "  "
    ci = re.search(r"\n([ \t]*)\}\s*$", like)
    ci = ci.group(1) if ci else mi[:-2]
    return "{\n" + ",\n".join(mi + it for it in items) + "\n" + ci + "}"


def set_member(s, obj_path, key, value_text):
    """`key`'s value in the object at `obj_path` set to `value_text` (replaced in place when it exists, else a member
    added after the last one in the object's own indentation). The new text."""
    span = value_span(s, obj_path)
    if span is None or s[span[0]] != "{":
        raise ValueError("no object at %s" % obj_path)
    ms = members(s, span[0])
    hit = [m for m in ms if m[0] == key]
    if hit:
        _, _, v0, v1 = hit[-1]
        return s[:v0] + value_text + s[v1:]
    if not ms:
        ind = _line_indent(s, span[0]) + "  "
        close = span[1] - 1
        return s[:span[0] + 1] + "\n" + ind + json.dumps(key) + ": " + value_text + "\n" + _line_indent(s, span[0]) + s[close:]
    last = ms[-1]
    multi = "\n" in s[span[0]:span[1]]
    sep = (",\n" + _line_indent(s, last[1])) if multi else ", "
    return s[:last[3]] + sep + json.dumps(key) + ": " + value_text + s[last[3]:]


# ---------------------------------------------------------------- the strips

def look_facts(doc, code, base):
    """(sprite, anims, strip_cols, frame_px, path_in_json) of one look as the game reads it (JsonContent: a variant's
    anims default to the top level's, its strip_cols to 0; a creature's frame_px is its entry's / recipe's or the top's)."""
    top_px = int(doc.get("frame_px", 128) or 128)
    if base:
        anims = doc.get("anims") if isinstance(doc.get("anims"), dict) else {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1}
        return (str(doc.get("sprite", doc["id"] + "_sprite.png")), dict(anims), int(doc.get("strip_cols", 0) or 0), top_px, [])
    e = doc["variants"][code]
    rec = e.get("recipe") if isinstance(e.get("recipe"), dict) else {}
    anims = e.get("anims") if isinstance(e.get("anims"), dict) else (doc.get("anims") if isinstance(doc.get("anims"), dict) else {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1})
    px = int(e.get("frame_px") or rec.get("frame_px") or top_px)
    return (str(e["sprite"]), dict(anims), int(e.get("strip_cols", 0) or 0), px, ["variants", code])


def cut(img, anims, cols, px, order):
    """{anim: [cells]} of a strip packed in `order` (frame k at column k % cols, row k // cols)."""
    out = {}
    k = 0
    for a in order:
        n = int(anims.get(a, 0) or 0)
        cells = []
        for _ in range(max(n, 0)):
            x, y = (k % cols) * px, (k // cols) * px
            cells.append(img.crop((x, y, x + px, y + px)))
            k += 1
        if cells:
            out[a] = cells
    return out


def build(img, anims, cols, px):
    """(new strip, new anims, cols written (0 = one row), the left counts) with the left sets appended as copies."""
    unknown = [a for a in anims if a not in ORDER and int(anims.get(a, 0) or 0) > 0]
    if unknown:
        raise ValueError("anims %s are not in the strip order: not touched" % unknown)
    right = {a: int(anims[a]) for a in BASE_ORDER if int(anims.get(a, 0) or 0) > 0}
    n0 = sum(right.values())
    one_row = cols <= 0
    c = cols if cols > 0 else max(n0, 1)
    rows0 = int(math.ceil(n0 / float(c)))
    if img.width < c * px or img.height < rows0 * px:
        raise ValueError("the strip is %dx%d, its anims need %d columns x %d rows of %d px" % (img.width, img.height, c, rows0, px))
    cells = cut(img, right, c, px, BASE_ORDER)
    left = {}
    for lk in LEFT_KEYS:
        src = LEFT[lk]
        if src in cells:
            cells[lk] = [cl.copy() for cl in cells[src]]
            left[lk] = len(cells[lk])
    if not left:
        raise ValueError("the look has none of %s to copy" % sorted(set(LEFT.values())))
    seq = []
    for a in ORDER:
        seq.extend(cells.get(a, []))
    n = len(seq)
    out_cols = cols
    if one_row:
        if n * px <= MAX_WIDTH:
            c = n
        else:
            c = n0
            out_cols = n0
    rows = int(math.ceil(n / float(c)))
    strip = Image.new("RGBA", (c * px, rows * px), (0, 0, 0, 0))
    for k, cl in enumerate(seq):
        strip.paste(cl, ((k % c) * px, (k // c) * px))
    new_anims = dict(right)
    new_anims.update(left)
    return strip, new_anims, out_cols, left


def has_left(anims):
    return any(int(anims.get(k, 0) or 0) > 0 for k in LEFT_KEYS)


def process(cid, codes, base=False, force=False, dry=False, content=None, backup=None, register=True, log=print):
    """Every look in `codes` (and the top-level strip with `base`) given its left sets. A list of results."""
    content = content or CONTENT
    backup = backup or BACKUP
    folder = os.path.join(content, "enemies", cid)
    jpath = os.path.join(folder, cid + ".json")
    with open(jpath, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    doc = json.loads(text)
    vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    want = []
    if codes == ["all"]:
        want = [c for c in vs if isinstance(vs[c], dict) and vs[c].get("sprite")]
    else:
        want = list(codes)
    jobs = [(c, False) for c in want] + ([(str(doc.get("variant_base", "")) or "(base)", True)] if base else [])
    results = []
    stamp = time.strftime("%Y%m%d_%H%M%S")
    new_text = text
    for code, is_base in jobs:
        if not is_base and (code not in vs or not isinstance(vs[code], dict) or not vs[code].get("sprite")):
            log("%s %s: no such look with its own sprite: skipped" % (cid, code))
            results.append({"code": code, "ok": False, "why": "no look"})
            continue
        sprite, anims, cols, px, jp = look_facts(doc, code, is_base)
        if has_left(anims) and not force:
            log("%s %s: already has left sets %s: skipped (--force rebuilds them)" % (cid, code, {k: anims[k] for k in LEFT_KEYS if k in anims}))
            results.append({"code": code, "ok": False, "why": "has left sets"})
            continue
        spath = os.path.join(folder, sprite)
        if not os.path.isfile(spath):
            log("%s %s: strip %s missing: skipped" % (cid, code, sprite))
            results.append({"code": code, "ok": False, "why": "no strip"})
            continue
        img = Image.open(spath).convert("RGBA")
        try:
            strip, new_anims, out_cols, left = build(img, anims, cols, px)
        except ValueError as ex:
            log("%s %s: %s" % (cid, code, ex))
            results.append({"code": code, "ok": False, "why": str(ex)})
            continue
        res = {"code": code, "ok": True, "sprite": sprite, "anims": new_anims, "left": left, "strip_cols": out_cols,
               "size_before": list(img.size), "size": list(strip.size), "frames": sum(new_anims.values())}
        # the JSON: this look's anims object (re-rendered in its own style) and strip_cols when it had to be set
        own = doc.get("anims") if not jp else vs[code].get("anims")
        if not isinstance(own, dict):
            # the look inherits its anims: it gets its own object, one member a line under the look's members
            mi = member_indent(new_text, value_span(new_text, jp)[0])
            new_text = set_member(new_text, jp, "anims", render_flat(new_anims, "{\n" + mi + "  \"x\": 1\n" + mi + "}"))
        else:
            sp = value_span(new_text, jp + ["anims"])
            old = new_text[sp[0]:sp[1]]
            if render_flat(anims, old) != old:
                log("%s %s: note: the anims object's own layout differs from the one-member-a-line style; written in that style" % (cid, code))
            new_text = new_text[:sp[0]] + render_flat(new_anims, old) + new_text[sp[1]:]
        if out_cols != cols:
            new_text = set_member(new_text, jp, "strip_cols", str(out_cols))
        log("%s %s: %s %dx%d -> %dx%d, %d -> %d frames, left sets %s%s" % (cid, code, sprite, img.width, img.height, strip.width, strip.height,
            sum(int(anims.get(a, 0) or 0) for a in BASE_ORDER), res["frames"], left, (", strip_cols %d" % out_cols) if out_cols != cols else ""))
        if not dry:
            bdir = os.path.join(backup, cid)
            os.makedirs(bdir, exist_ok=True)
            shutil.copy2(spath, os.path.join(bdir, "%s.%s.png" % (os.path.splitext(sprite)[0], stamp)))
            strip.save(spath)
        results.append(res)
    if not dry and new_text != text:
        json.loads(new_text)   # still JSON
        bdir = os.path.join(backup, cid)
        os.makedirs(bdir, exist_ok=True)
        shutil.copy2(jpath, os.path.join(bdir, "%s.%s.json" % (cid, stamp)))
        with open(jpath, "w", encoding="utf-8", newline="") as f:
            f.write(new_text)
        log("%s: %s written (backup in %s)" % (cid, os.path.relpath(jpath, REPO) if jpath.startswith(REPO) else jpath, os.path.relpath(bdir, REPO) if bdir.startswith(REPO) else bdir))
    if not dry and register and content == CONTENT:
        # the Frames store's groups of a look it already knows, registered again from the new strip (the left groups too)
        try:
            import frames_store as FS
            for r in results:
                if r.get("ok") and not r["code"].startswith("("):
                    FS.hook_after_save(folder, cid, r["code"], log=log)
        except Exception as ex:   # never fails the run: the Frames view registers a look when it opens it
            log("frames store not refreshed (%s): it registers the look when the Frames view opens it" % ex)
    return results


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--id", required=True, help="the creature id (game/content/enemies/<id>)")
    ap.add_argument("--looks", default="all", help="look codes, comma-separated, or 'all' (every look with its own sprite)")
    ap.add_argument("--base", action="store_true", help="the top-level strip too")
    ap.add_argument("--force", action="store_true", help="rebuild left sets a look already has from its right-heading frames")
    ap.add_argument("--dry-run", action="store_true", help="say what would change, write nothing")
    ap.add_argument("--content", default=None, help="another content root (tests)")
    ap.add_argument("--backup", default=None, help="another backup root (tests)")
    a = ap.parse_args(argv)
    codes = ["all"] if a.looks.strip().lower() == "all" else [c.strip() for c in a.looks.split(",") if c.strip()]
    res = process(a.id, codes, base=a.base, force=a.force, dry=a.dry_run, content=a.content, backup=a.backup)
    ok = [r for r in res if r.get("ok")]
    print("%d look(s) given left sets%s; %d skipped" % (len(ok), " (dry run: nothing written)" if a.dry_run else "", len(res) - len(ok)))
    if ok and not a.dry_run:
        print("next: bash tools/godot.sh --headless --path game --import && bash tools/godot.sh --headless --path game "
              "--script res://tools/import_json.gd -- only=enemies/%s" % a.id)
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Pass 128 (lane ENV; Garry: "Create 5 additional variations of each of the 2.5d environment art assets that we have in
the game. Don't add them to the game just yet ... I will call them by name."): candidates for five new variations of
each scenery prop kind, listed in tools/env_variations.json. Nothing here writes into game/ except --install, which
the lead runs later for the ones Garry names.

The painting and the finishing are tools/gen_prop_variants.py's own (render: Flux.2 Klein 1024 with the style anchor
and the original prop's raw render as references, a cart state painted over its Blender render; finish: the fit, the
warm thin outline, the mute), so a candidate is finished exactly as a prop in the game is.

  python tools/gen_env_variations.py --only saguaro_big [--seeds 2] [--force]     # that kind's candidates + its sheet
  python tools/gen_env_variations.py [--only a,b,...]                             # several kinds: ONE PROCESS A KIND
                                                                                  # (the ComfyUI lock changes hands)
  python tools/gen_env_variations.py --ids agave_c,skull_e --first 2 --seeds 2    # a re-roll: seeds s2 and s3 of those
  python tools/gen_env_variations.py --sheets [--only a,b]                        # the sheets again, nothing painted
  python tools/gen_env_variations.py --collect                                    # picks.json -> picks/<id>.png
  python tools/gen_env_variations.py --install "Old Giant" skull_c ... [--dry-run]
      # LATER, the lead: the picked painting of each named variation (its name on the page or its id) into
      # game/art/sprites/props/<id>.png and its props.json row (file, height, radius, cell, variant_of), through
      # gen_prop_variants.pick. Then: python tools/prop_shadows.py (measures the new rows' shadows; a cart state's
      # shadow is set by hand like the cart's), the Godot --import, and the props tests.

Files (all under tools/dl/p128/ENV, git-ignored):
  raw/<id>_<seed>.png          the raw renders (seed = the row's seed + k * 977)
  cands/<base>/<id>_s<k>.png   finished candidates (the game's cell size, transparent)
  sheets/<base>.png            one contact sheet a kind: the original and today's variants, then every candidate, on sand
  picks.json                   {id: {"pick": k, "weak": bool, "note": str}}, written by hand after looking at the sheets
  picks/<id>.png               the picked candidate of every variation (--collect)
  renders.log                  one line per render really made (the count)
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
LIST = os.path.join(HERE, "env_variations.json")
ENV = os.path.join(REPO, "tools", "dl", "p128", "ENV")
RAWS = os.path.join(ENV, "raw")
CANDS = os.path.join(ENV, "cands")
SHEETS = os.path.join(ENV, "sheets")
PICKS = os.path.join(ENV, "picks")
PICKS_JSON = os.path.join(ENV, "picks.json")
RENDER_LOG = os.path.join(ENV, "renders.log")
PROPS = os.path.join(REPO, "game", "art", "sprites", "props")
ORIG_RAW = os.path.join(REPO, "tools", "dl", "ai_raw_props")
# the mean colour of the game's sand (game/art/env/sand_ripples_pebbles.png)
SAND = (214, 188, 145)

_mods = None


def painter():
    """gen_prop_variants and gen_props, imported with a bare command line (they read sys.argv when they load)."""
    global _mods
    if _mods is None:
        keep = sys.argv
        sys.argv = [keep[0]]
        sys.path.insert(0, HERE)
        import gen_prop_variants as gpv
        import gen_props as gp
        sys.argv = keep
        _mods = (gpv, gp)
    return _mods


def load_list():
    data = json.load(open(LIST, encoding="utf-8"))
    return data["kinds"], data["rows"]


def bases(rows):
    out = []
    for r in rows:
        if r["base"] not in out:
            out.append(r["base"])
    return out


def kind_numbers(base):
    """(height m, radius m, cell px, screen) of a kind: gen_props' table, or gen_prop_variants' for the kinds born there."""
    gpv, gp = painter()
    if base in gp.PROPS:
        _, height, radius, cell, _, screen = gp.PROPS[base]
    else:
        _, _, _, height, radius, cell, _, screen = gpv.VARIANTS[base]
    return height, radius, cell, screen


def variant_row(kinds, row):
    """A row of the list as gen_prop_variants.VARIANTS keeps one (the reference by its full path)."""
    gpv, gp = painter()
    height, radius, cell, screen = kind_numbers(row["base"])
    # the kind's own raw render, unless the row names another or none (`"ref": null`: a shape the reference would undo)
    ref = row["ref"] if "ref" in row else kinds[row["base"]]["ref"]
    if ref:
        ref = os.path.join(ORIG_RAW, ref)
    return (row["base"], ref, row["subject"] + gp.NO_FACE, height, radius, cell, int(row["seed"]), screen)


def cand_path(row, k):
    return os.path.join(CANDS, row["base"], "%s_s%d.png" % (row["id"], k))


def paint(base, ids, first, seeds, force):
    gpv, gp = painter()
    kinds, rows = load_list()
    gpv.RAW = RAWS
    gpv.FORCE = force
    os.makedirs(os.path.join(CANDS, base), exist_ok=True)
    for row in rows:
        if row["base"] != base or (ids and row["id"] not in ids):
            continue
        vrow = variant_row(kinds, row)
        grade = None
        if row.get("render"):
            # a cart state: painted over its own Blender render, with the cart's denoise and grade
            fr = dict(gpv.FROM_RENDER[base], ref=row["render"])
            gpv.FROM_RENDER[row["id"]] = fr
            grade = fr.get("grade")
        for k in range(first, first + seeds):
            out = cand_path(row, k)
            if os.path.exists(out) and not force:
                continue
            raw = os.path.join(RAWS, "%s_%d.png" % (row["id"], vrow[6] + k * 977))
            fresh = force or not os.path.exists(raw)
            img = gpv.render(row["id"], vrow, k)
            if fresh:
                with open(RENDER_LOG, "a", encoding="utf-8", newline="\n") as f:
                    f.write("%s %s s%d seed %d\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), row["id"], k, vrow[6] + k * 977))
            gpv.finish(img, vrow[5], grade).save(out)
    return sheet(base)


def font(size):
    for name in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def in_game(base):
    """[(id, picture)] the kind's own painting, then today's variants of it (props.json `variant_of`)."""
    man = json.load(open(os.path.join(PROPS, "props.json"), encoding="utf-8"))
    out = [(base, os.path.join(PROPS, base + ".png"))]
    for id_, row in man.items():
        if isinstance(row, dict) and row.get("variant_of") == base and not row.get("hidden"):
            out.append((id_, os.path.join(PROPS, row.get("file", id_ + ".png"))))
    return out


def load_picks():
    return json.load(open(PICKS_JSON, encoding="utf-8")) if os.path.exists(PICKS_JSON) else {}


def sheet(base):
    """The kind's contact sheet: a column a variation (its name on top), a row a seed; the first row the original and
    today's variants. The pick (picks.json) is framed, a weak one says so."""
    _, rows = load_list()
    rows = [r for r in rows if r["base"] == base]
    picks = load_picks()
    seeds = 0
    for r in rows:
        k = 0
        while os.path.exists(cand_path(r, k)):
            k += 1
        seeds = max(seeds, k)
    tile, gap, lab = 264, 10, 24
    cols = max(len(rows), 1)
    w = gap + cols * (tile + gap)
    h = gap + (1 + seeds) * (tile + lab + gap) + lab
    img = Image.new("RGBA", (w, h), SAND + (255,))
    dr = ImageDraw.Draw(img)
    f_big, f_small = font(17), font(13)
    ink = (40, 20, 10, 255)

    def put(path, col, line, text):
        x = gap + col * (tile + gap)
        y = gap + line * (tile + lab + gap) + (lab if line > 0 else 0)
        im = Image.open(path).convert("RGBA").resize((tile, tile), Image.LANCZOS)
        img.alpha_composite(im, (x, y))
        dr.text((x + 2, y + tile + 3), text, fill=ink, font=f_small)
        return x, y

    for i, (id_, path) in enumerate(in_game(base)[:cols]):
        put(path, i, 0, id_ + (" (original)" if id_ == base else " (in the game)"))
    y_names = gap + tile + lab + gap
    for c, r in enumerate(rows):
        dr.text((gap + c * (tile + gap) + 2, y_names + 2), r["name"], fill=ink, font=f_big)
        p = picks.get(r["id"], {})
        for k in range(seeds):
            path = cand_path(r, k)
            if not os.path.exists(path):
                continue
            mark = ""
            if p.get("pick") == k:
                mark = "  PICK" + (" (weak)" if p.get("weak") else "")
            x, y = put(path, c, 1 + k, "%s s%d%s" % (r["id"], k, mark))
            if mark:
                dr.rectangle((x - 3, y - 3, x + tile + 2, y + tile + 2), outline=(170, 40, 30, 255) if p.get("weak") else (30, 110, 50, 255), width=3)
    os.makedirs(SHEETS, exist_ok=True)
    out = os.path.join(SHEETS, base + ".png")
    img.convert("RGB").save(out)
    print("sheet", out, flush=True)
    return out


def collect():
    """picks.json -> picks/<id>.png (the full-size transparent painting of every pick)."""
    _, rows = load_list()
    picks = load_picks()
    os.makedirs(PICKS, exist_ok=True)
    missing = []
    for r in rows:
        p = picks.get(r["id"])
        src = cand_path(r, int(p["pick"])) if p is not None else ""
        if not p or not os.path.exists(src):
            missing.append(r["id"])
            continue
        shutil.copyfile(src, os.path.join(PICKS, r["id"] + ".png"))
    print("collect: %d picks in %s%s" % (len(rows) - len(missing), PICKS, ("; missing: " + ", ".join(missing)) if missing else ""))
    return missing


def install(names, dry_run):
    """The named variations (a name as the page shows it, or an id) into the game through gen_prop_variants.pick."""
    gpv, _ = painter()
    kinds, rows = load_list()
    by = {}
    for r in rows:
        by[r["id"].lower()] = r
        by[r["name"].lower()] = r
    todo = []
    for n in names:
        r = by.get(n.strip().lower())
        if r is None:
            raise SystemExit("install: no variation is called %r (names and ids are in tools/env_variations.json)" % n)
        src = os.path.join(PICKS, r["id"] + ".png")
        if not os.path.exists(src):
            raise SystemExit("install: %s has no picked painting at %s (run --collect)" % (r["id"], src))
        todo.append((r, src))
    tmp = tempfile.mkdtemp(prefix="env_install_")
    try:
        for r, src in todo:
            vrow = variant_row(kinds, r)
            print("install: %-16s %-18s -> game/art/sprites/props/%s.png  variant_of %s  height %s  radius %s  cell %s%s"
                  % (r["id"], '"' + r["name"] + '"', r["id"], r["base"], vrow[3], vrow[4], vrow[5], "  (dry run)" if dry_run else ""))
            if dry_run:
                continue
            gpv.VARIANTS[r["id"]] = vrow
            shutil.copyfile(src, os.path.join(tmp, r["id"] + "_c0.png"))
            gpv.CANDS = tmp
            gpv.pick([r["id"] + "=0"])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if not dry_run:
        print("install: now run  python tools/prop_shadows.py  (a cart state's shadow by hand, as cart_toppled's), the Godot --import and the props tests")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--ids", default="")
    ap.add_argument("--seeds", type=int, default=2)
    ap.add_argument("--first", type=int, default=0)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--sheets", action="store_true")
    ap.add_argument("--collect", action="store_true")
    ap.add_argument("--install", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.install:
        return install(a.install, a.dry_run)
    if a.collect:
        return collect()
    _, rows = load_list()
    ids = [s for s in a.ids.split(",") if s]
    todo = [s for s in a.only.split(",") if s]
    for s in todo:
        if s not in bases(rows):
            raise SystemExit("no kind %r in %s" % (s, LIST))
    if not todo:
        todo = [b for b in bases(rows) if not ids or any(r["base"] == b and r["id"] in ids for r in rows)]
    if a.sheets:
        for b in todo:
            sheet(b)
        return
    if len(todo) == 1:
        paint(todo[0], ids, a.first, a.seeds, a.force)
        return
    # several kinds: a process each, so the ComfyUI lock is let go between kinds and another lane gets its turn
    for b in todo:
        cmd = [sys.executable, os.path.abspath(__file__), "--only", b, "--seeds", str(a.seeds), "--first", str(a.first)]
        if ids:
            cmd += ["--ids", ",".join(ids)]
        if a.force:
            cmd.append("--force")
        rc = subprocess.call(cmd)
        if rc != 0:
            print("gen_env_variations: %s ended with %d" % (b, rc), flush=True)


if __name__ == "__main__":
    main()

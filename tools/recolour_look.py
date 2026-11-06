"""Pass 131: a recolour look of a creature from a shell, start to finish (what tools/dl/p107 and p122's one-off scripts did
by hand): the passes run on the source look's strip and icon, a preview sheet for the eye, then --write puts the two
pictures beside the creature's JSON and the look's entry after its source (the file's own layout kept).

  python tools/recolour_look.py --id carrion_crow --from CC-B --code CC-C --passes "<recolour_strip.py flags>" ["<pass 2>" ...]
        [--note "..."] [--write]
      # without --write: tools/dl/recolour_look/<id>_<code>.png (+ _icon.png) and <id>_<code>_preview.png
      #   (the source over the result: first idle, three run frames, the attack, the hit, a death frame, a back frame, the icon)
      # --write: <id>_sprite_<letter>.png, <id>_icon_<letter>.png and variants[CODE] = {note, fresh, recipe {recolour_of,
      #   recolour_passes}, sprite, icon, + the source's shadow, anims, strip_cols, head, fps, attack_views, attack_throw,
      #   front_faces, back_faces}; then lossy_imports, the Godot --import and import_json -- only=enemies
  A pass is the flags of tools/recolour_strip.py without --src / --dst (its header explains each); every pass runs on the
  result of the one before, on the strip and on the icon alike (a pass with --cells skips the icon by itself).
"""
import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "tools", "dl", "recolour_look")
COPY_KEYS = ["shadow", "anims", "strip_cols", "head", "fps", "attack_views", "attack_throw", "front_faces", "back_faces", "frame_px"]
SAND = (214, 188, 145, 255)


def folder_of(id_):
    for kind in ("enemies", "bosses"):
        p = os.path.join(REPO, "game", "content", kind, id_)
        if os.path.isfile(os.path.join(p, id_ + ".json")):
            return p
    raise SystemExit("no creature or boss %r" % id_)


def look_of(d, id_, code):
    """(sprite file, icon file, the entry the look's numbers come from) of look `code`: its variants entry, or the
    creature's own strip when the code is its base."""
    v = (d.get("variants") or {}).get(code)
    if v is None:
        raise SystemExit("%s has no look %s (it has %s)" % (id_, code, ", ".join((d.get("variants") or {}).keys())))
    sprite = v.get("sprite") or (id_ + "_sprite.png")
    icon = v.get("icon") or (id_ + "_icon.png")
    src = {k: v.get(k, d.get(k)) for k in COPY_KEYS if v.get(k, d.get(k)) is not None}
    return sprite, icon, src


def run_passes(src, dst, passes):
    shutil.copyfile(src, dst)
    for p in passes:
        r = subprocess.run([sys.executable, os.path.join(HERE, "recolour_strip.py"), "--src", dst, "--dst", dst] + shlex.split(p),
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit("recolour_strip failed on %s: %s%s" % (p, r.stdout[-400:], r.stderr[-400:]))


def frames_of(numbers, px, strip):
    anims = numbers.get("anims") or {}
    cols = int(numbers.get("strip_cols") or (strip.width // px))
    off, at = {}, 0
    for k, n in anims.items():
        off[k] = at
        at += int(n)

    def cell(a, f):
        n = off.get(a, 0) + f
        x, y = (n % cols) * px, (n // cols) * px
        return (x, y, x + px, y + px)
    want = [("idle", 0), ("run", 0), ("run", 4), ("run", 8), ("attack", 0), ("hit", 0), ("die", max(int(anims.get("die", 1)) - 1, 0)), ("run_b", 2)]
    return [(a, cell(a, f)) for a, f in want if int(anims.get(a, 0)) > f]


def preview(src_strip, dst_strip, src_icon, dst_icon, numbers, out):
    a, b = Image.open(src_strip).convert("RGBA"), Image.open(dst_strip).convert("RGBA")
    px = int(numbers.get("frame_px") or a.height)
    cells = frames_of(numbers, px, a)
    t = 200
    sheet = Image.new("RGBA", ((len(cells) + 1) * t, 2 * t + 18), SAND)
    dr = ImageDraw.Draw(sheet)
    for i, (name, box) in enumerate(cells):
        for j, im in enumerate((a, b)):
            sheet.alpha_composite(im.crop(box).resize((t, t), Image.LANCZOS), (i * t, j * t))
        dr.text((i * t + 4, 2 * t + 3), name, fill=(40, 20, 10, 255))
    for j, p in enumerate((src_icon, dst_icon)):
        if os.path.exists(p):
            sheet.alpha_composite(Image.open(p).convert("RGBA").resize((t, t), Image.LANCZOS), (len(cells) * t, j * t))
    dr.text((len(cells) * t + 4, 2 * t + 3), "icon", fill=(40, 20, 10, 255))
    sheet.convert("RGB").save(out)


def write_entry(path, d, txt, code, src_code, entry):
    ea = json.dumps(d, indent=2, ensure_ascii=True) + ("\n" if txt.endswith("\n") else "") == txt
    if not ea and json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if txt.endswith("\n") else "") != txt:
        raise SystemExit("%s does not round-trip (indent 2): add the entry by hand" % path)
    out = {}
    for k, v in d["variants"].items():
        if k == code:
            continue
        out[k] = v
        if k == src_code:
            out[code] = entry
    d["variants"] = out
    open(path, "w", encoding="utf-8", newline="\n").write(json.dumps(d, indent=2, ensure_ascii=ea) + ("\n" if txt.endswith("\n") else ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--from", dest="src", required=True)
    ap.add_argument("--code", required=True)
    ap.add_argument("--passes", nargs="+", required=True)
    ap.add_argument("--note", default="")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    folder = folder_of(a.id)
    path = os.path.join(folder, a.id + ".json")
    txt = open(path, "rb").read().decode("utf-8")
    d = json.loads(txt)
    sprite, icon, numbers = look_of(d, a.id, a.src)
    letter = a.code.split("-")[-1].lower()
    os.makedirs(OUT, exist_ok=True)
    stem = os.path.join(OUT, "%s_%s" % (a.id, a.code))
    run_passes(os.path.join(folder, sprite), stem + ".png", a.passes)
    run_passes(os.path.join(folder, icon), stem + "_icon.png", a.passes)
    preview(os.path.join(folder, sprite), stem + ".png", os.path.join(folder, icon), stem + "_icon.png", numbers, stem + "_preview.png")
    print("recolour_look: %s -> %s" % (a.code, stem + "_preview.png"))
    if not a.write:
        return
    entry = {"note": a.note or ("a recolour of %s" % a.src), "fresh": True,
             "recipe": {"recolour_of": a.src, "recolour_passes": a.passes},
             "sprite": "%s_sprite_%s.png" % (a.id, letter), "icon": "%s_icon_%s.png" % (a.id, letter)}
    for k in COPY_KEYS:
        if k in numbers and k != "frame_px":
            entry[k] = numbers[k]
    shutil.copyfile(stem + ".png", os.path.join(folder, entry["sprite"]))
    shutil.copyfile(stem + "_icon.png", os.path.join(folder, entry["icon"]))
    write_entry(path, d, txt, a.code, a.src, entry)
    print("recolour_look: wrote %s into %s; now python tools/lossy_imports.py, the Godot --import and import_json -- only=enemies" % (a.code, path))


if __name__ == "__main__":
    main()

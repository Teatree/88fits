"""Pass 111 (lane SKINS): the full-body stills the hero sheet's Looks tiles show.

For each look a hero sells as a skin (variants[CODE].skin.purchasable) and the look every player owns (the JSON's
`variant`), the first frame of its front idle (`idle_f`, else `idle`) is cut from the look's strip, trimmed to the
figure with a small margin and written beside the strip as content/characters/<hero>/<hero>_still_<code_slug>.png
(code_slug = the code lower-cased, '-' as '_': MAY-B -> may_b). CharacterDef.look_still_path finds it by that name
(or by `skin.still` when a look names its own file); without one the tile shows the look's badge.

    python tools/skin_stills.py                 # every hero that sells skins: his owned look and every skin
    python tools/skin_stills.py --hero may      # one hero
    python tools/skin_stills.py --hero may --code MAY-B [--force]
    then: bash tools/godot.sh --headless --path game --import   (Godot must import the new PNGs)

The frame order is the game's (player/Player.gd, the BillboardSprite order): idle, run, turn, hit, die, cheer, idle_f,
run_f, idle_s, run_s, idle_bd, run_bd, idle_fd, run_fd, hit_f, hit_s, hit_bd, hit_fd.
"""
import argparse
import glob
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARS = os.path.join(ROOT, "game", "content", "characters")
ORDER = ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd",
         "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]
# the margin kept round the figure, as a share of its height
MARGIN = 0.06


def slug(code):
    return code.lower().replace("-", "_")


def still_name(hero, code):
    return "%s_still_%s.png" % (hero, slug(code))


def frame_index(anims, want):
    k = 0
    for a in ORDER:
        n = int(anims.get(a, 0) or 0)
        if a == want and n > 0:
            return k
        k += n
    return None


def cut(strip_path, anims, cols, fpx):
    im = Image.open(strip_path).convert("RGBA")
    idx = frame_index(anims, "idle_f")
    if idx is None:
        idx = frame_index(anims, "idle") or 0
    if cols <= 0:
        cols = max(im.width // fpx, 1)
    x, y = (idx % cols) * fpx, (idx // cols) * fpx
    fr = im.crop((x, y, x + fpx, y + fpx))
    box = fr.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
    if box is None:
        return fr
    h = box[3] - box[1]
    m = int(round(h * MARGIN))
    box = (max(box[0] - m, 0), max(box[1] - m, 0), min(box[2] + m, fpx), min(box[3] + m, fpx))
    return fr.crop(box)


def looks_of(d, hero, only_code=None):
    """[(code, entry)] to cut: the owned look and every look sold as a skin (or `only_code`)."""
    vs = d.get("variants") or {}
    home = d.get("variant") if d.get("variant") in vs else None
    sells = [c for c, e in vs.items() if isinstance(e, dict) and (e.get("skin") or {}).get("purchasable")
             and not e.get("shelved") and c != home]
    if only_code:
        return [(only_code, vs.get(only_code, {}))] if only_code in vs else []
    if not sells:
        return []
    out = [(home, vs[home])] if home else []
    return out + [(c, vs[c]) for c in sorted(sells)]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hero", default="")
    ap.add_argument("--code", default="")
    ap.add_argument("--force", action="store_true", help="cut again when the still is there already")
    a = ap.parse_args(argv)
    made = 0
    for jp in sorted(glob.glob(os.path.join(CHARS, "*", "*.json"))):
        if jp.endswith("_ai.json"):
            continue
        hero = os.path.basename(os.path.dirname(jp))
        if os.path.splitext(os.path.basename(jp))[0] != hero or (a.hero and hero != a.hero):
            continue
        with open(jp, encoding="utf-8") as f:
            d = json.load(f)
        for code, e in looks_of(d, hero, a.code or None):
            e = e if isinstance(e, dict) else {}
            sprite = e.get("sprite") or d.get("sprite") or hero + "_sprite.png"
            sp = os.path.join(os.path.dirname(jp), sprite)
            if not os.path.isfile(sp):
                print("skin_stills: %s %s has no strip (%s)" % (hero, code, sprite))
                continue
            out = os.path.join(os.path.dirname(jp), (e.get("skin") or {}).get("still") or still_name(hero, code))
            if os.path.isfile(out) and not a.force:
                print("skin_stills: %s %s kept (%s)" % (hero, code, os.path.basename(out)))
                continue
            anims = e.get("anims") or d.get("anims") or {}
            cols = int(e.get("strip_cols", d.get("strip_cols", 0)) or 0)
            fpx = int(e.get("frame_px", d.get("frame_px", 256)) or 256)
            img = cut(sp, anims, cols, fpx)
            img.save(out)
            made += 1
            print("skin_stills: %s %s -> %s %s" % (hero, code, os.path.relpath(out, ROOT), img.size))
    print("skin_stills: %d made" % made)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

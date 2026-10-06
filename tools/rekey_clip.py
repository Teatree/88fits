"""Key a cached clip again with an item's current key settings, without painting it again (pass 54, Solenne's boots).

A pose clip in tools/dl/ai_anim/<key>/ keeps every frame keyed at full size (full_NN.png): the keyer only changes the
figure's edge and spilled pixels, so the screen and anything it cut away keep their colours underneath. This keys
those frames again with the JSON's key settings (key_sat, key_min_value, key_cut_shadow, key_clamp_screen; see
artkit.key_background), crops them to the clip's box (cycle.json) and writes out_NN.png and the contact sheet, so the
next gen_art run packs the strip from them.

    python tools/rekey_clip.py --id solenne [--keys solenne_pose_run_back,solenne_pose_run_bd]   (default: every
    tools/dl/ai_anim/<id>_pose_* folder)
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import artkit  # noqa: E402
import gen_art as g  # noqa: E402
from PIL import Image  # noqa: E402


def opt(name, default=None):
    for a in sys.argv[1:]:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
        if a == "--" + name and sys.argv.index(a) + 1 < len(sys.argv):
            return sys.argv[sys.argv.index(a) + 1]
    return default


def item_json(cid):
    for folder in glob.glob(os.path.join(g.CONTENT, "*", cid)):
        p = os.path.join(folder, cid + ".json")
        if os.path.exists(p):
            return json.load(open(p, encoding="utf-8"))
    raise SystemExit("no content item " + cid)


def rekey(folder):
    meta = json.load(open(os.path.join(folder, "cycle.json"), encoding="utf-8"))
    n = int(meta.get("n_out", 0))
    box = tuple(meta["box"])
    out = []
    for k in range(n):
        fp = os.path.join(folder, "full_%02d.png" % k)
        if not os.path.exists(fp):
            raise SystemExit("missing " + fp)
        keyed = artkit.key_background(Image.open(fp).convert("RGB"), 0.16, 0.7)
        keyed.save(fp)
        f = keyed.crop(box)
        f.save(os.path.join(folder, "out_%02d.png" % k))
        out.append(f)
    artkit.contact_sheet(out, n, 200).save(os.path.join(folder, "cycle_sheet.png"))
    print("rekey_clip: %s %d frames" % (os.path.basename(folder), n))


def main():
    cid = opt("id")
    if not cid:
        raise SystemExit(__doc__)
    d = item_json(cid)
    artkit.KEY_SAT = float(d.get("key_sat", 0.35))
    artkit.KEY_MIN_V = float(d.get("key_min_value", 0.2))
    artkit.KEY_CUT_SHADOW = bool(d.get("key_cut_shadow", True))
    artkit.KEY_CLAMP_SCREEN = bool(d.get("key_clamp_screen", False))
    keys = [k for k in (opt("keys") or "").split(",") if k]
    folders = [os.path.join(g.ANIM if hasattr(g, "ANIM") else os.path.join(g.REPO, "tools", "dl", "ai_anim"), k) for k in keys] if keys else \
        sorted(glob.glob(os.path.join(g.REPO, "tools", "dl", "ai_anim", cid + "_pose_*")))
    for f in folders:
        if os.path.exists(os.path.join(f, "cycle.json")):
            rekey(f)


if __name__ == "__main__":
    main()

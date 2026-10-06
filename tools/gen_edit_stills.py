"""Front paintings as Klein edits of a reference picture, several seeds, picked by eye (pass 53: the Werewolf from
Garry's _REFERENCES/2d/Werewolf.webp in three levels of cartooniness; the same route the Vulture Raider and the HG-C
giant took from scratch scripts). The pick lands in tools/dl/ai_raw_anime as <id>_<stills>_front.png + .json, the
cache gen_art.py reads for a variant whose recipe says "stills": "<stills>", so `gen_art.py --only <id>
--variant=<CODE>` then paints the back and the dead painting from it and walks it.

    python tools/gen_edit_stills.py --id werewolf --stills wwa --ref "_REFERENCES/2d/Werewolf.webp" --seeds 4 \
        --prompt "a hulking werewolf with dark shaggy fur ..." [--screen blue] [--keep "small yellow eyes"]
        -> tools/dl/ai_raw_anime/werewolf_wwa_front_c0..c3.png and tools/dl/review/werewolf_wwa_front_cands.png
    python tools/gen_edit_stills.py --id werewolf --stills wwa --pick 2        (installs c2 as werewolf_wwa_front)

--no-style-ref leaves the style anchor out (the reference alone sets the look). The prompt is the creature; the
script adds the view ("full body, front view, standing and facing the viewer, feet fully visible"), the house style
and the screen colour, and runs gen_art's render (vision QA, geometry) once per seed.
"""
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ARGS = sys.argv[1:]
sys.argv = ["gen_art.py", "--no-import", "--skip-qa"] if "--skip-qa" in ARGS else ["gen_art.py", "--no-import"]
sys.path.insert(0, HERE)
import gen_art as g  # noqa: E402
import comfy  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402


def opt(name, default=None):
    for i, a in enumerate(ARGS):
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
        if a == "--" + name and i + 1 < len(ARGS):
            return ARGS[i + 1]
    return default


def sheet(keys, name):
    ims = [Image.open(os.path.join(g.RAW, k + ".png")).convert("RGB") for k in keys]
    W = 400
    out = Image.new("RGB", (W * len(ims), W + 28), (30, 30, 36))
    dr = ImageDraw.Draw(out)
    for i, (k, im) in enumerate(zip(keys, ims)):
        out.paste(im.resize((W, W), Image.LANCZOS), (i * W, 28))
        dr.text((i * W + 6, 6), k, fill=(255, 230, 140))
    d = os.path.join(REPO, "tools", "dl", "review")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, name)
    out.save(p)
    return p


def main():
    cid, stills = opt("id"), opt("stills")
    if not cid or not stills:
        raise SystemExit(__doc__)
    key = "%s_%s_front" % (cid, stills)
    pick = opt("pick")
    if pick is not None:
        for ext in (".png", ".json"):
            shutil.copy(os.path.join(g.RAW, "%s_c%s%s" % (key, pick, ext)), os.path.join(g.RAW, key + ext))
        print("gen_edit_stills: %s_c%s installed as %s" % (key, pick, key))
        return
    ref_path, prompt = opt("ref"), opt("prompt")
    if not ref_path or not prompt:
        raise SystemExit(__doc__)
    n = int(opt("seeds", "4"))
    bg = g.BG_BLUE if opt("screen", "green") == "blue" else g.BG_GREEN
    refs = [] if "--no-style-ref" in ARGS else list(g.ensure_anchor_uploaded())
    ref_img = Image.open(os.path.join(REPO, ref_path)).convert("RGBA")
    flat = Image.new("RGB", ref_img.size, (255, 255, 255))
    flat.paste(ref_img, mask=ref_img.getchannel("A"))
    look = comfy.upload_pil(flat, cid + "_" + stills + "_ref.png")
    keep = opt("keep", "")
    style_words = "The first reference image shows the art style only; do not copy its subjects. The second" if refs else "The"
    p = (style_words + " reference image is the creature: redraw this exact creature as a finished 2D anime game creature "
         "illustration of " + prompt + ". Full body, front view, standing and facing the viewer, feet fully visible, the whole "
         "creature inside the picture." + ((" Keep " + keep + ".") if keep else "") + " " + g.STYLE + ". " + bg + ".")
    seed = g.seed_for(cid + stills)
    keys = []
    for k in range(n):
        ck = "%s_c%d" % (key, k)
        g.render(ck, p, refs + [look], {"subject": prompt.split(",")[0], "view": "front", "subjects_max": 1}, seed + 1000 * k, tries=1)
        keys.append(ck)
    path = sheet(keys, key + "_cands.png")
    print("gen_edit_stills: look at %s, then --pick N" % path)


if __name__ == "__main__":
    main()

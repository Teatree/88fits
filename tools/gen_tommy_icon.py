"""The Tommy Gun icons painted from the game's own 3D gun: tools/dl/tommy_ref.png (blender_tommy.py's three-quarter render
of Garry's reference model, pass 44) is the reference the image model copies, so the 2D and the 3D are one gun. Flux.2 dev,
one render at a time; `--seeds=N` paints N candidates per icon into tools/dl/tommy_icons/ with a review sheet, and
`--pick tommy_gun=k chicago_typewriter=k` installs the chosen ones.

  python tools/gen_tommy_icon.py [--seed=N] [--seeds=4]
  python tools/gen_tommy_icon.py --pick tommy_gun=2 chicago_typewriter=0
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(REPO, "tools", "dl", "tommy_ref.png")
CONTENT = os.path.join(REPO, "game", "content")

# pass 44 (Garry: the drum read as a flat disc fitted sideways; change the angle so its roundness shows): the gun is seen from
# the front-left at three-quarters and a little above, the way the reference render is, so the big drum under the receiver
# reads as a thick round drum, its round face and its rim both visible
SHAPE = ("a Thompson M1928 submachine gun, this exact gun, copying its silhouette, proportions and viewing angle from the reference: "
         "seen from the front-left at three-quarters and a little from above, the muzzle pointing towards the upper right of the "
         "picture and the wooden shoulder stock towards the lower left; the long barrel with cooling fins and the compensator at the "
         "muzzle leaves the front of the receiver high up; the big round 50-round drum magazine sits BELOW the receiver just ahead of "
         "the trigger guard and reads as a thick solid cylinder, its round face and its curved rim both clearly visible; the vertical "
         "wooden foregrip stands under the barrel ahead of the drum; the raked wooden pistol grip behind the trigger; nothing else in "
         "the picture")


OUT = os.path.join(REPO, "tools", "dl", "tommy_icons")
JOBS = [("weapons", "tommy_gun", "black steel, dark walnut wood", 41),
        ("evolutions", "chicago_typewriter", "black steel with polished gold trim on the drum, the barrel fins and the receiver, dark walnut wood", 42)]


def pick(pairs):
    for pair in pairs:
        wid, n = pair.split("=")
        kind = [j[0] for j in JOBS if j[1] == wid][0]
        img = Image.open(os.path.join(OUT, "%s_c%s.png" % (wid, n))).convert("RGB")
        icon, _ = ga.finish(img, 256, 0.92, False, None, 0.006)
        icon.save(os.path.join(CONTENT, kind, wid, wid + "_icon.png"))
        ga.log("installed %s candidate %s" % (wid, n))


def main():
    if "--pick" in sys.argv:
        pick(sys.argv[sys.argv.index("--pick") + 1:])
        return
    ga.DEV = True
    seed = 0
    seeds = 1
    for a in sys.argv[1:]:
        if a.startswith("--seed="):
            seed = int(a.split("=", 1)[1])
        if a.startswith("--seeds="):
            seeds = int(a.split("=", 1)[1])
    ref = comfy.upload(open(REF, "rb").read(), "tommy_ref.png")
    os.makedirs(OUT, exist_ok=True)
    for kind, wid, finish_words, k in JOBS:
        prompt = "%s, %s. %s. %s." % (SHAPE, finish_words, ga.ICON_STYLE, ga.BG_GREEN)
        if seeds <= 1:
            img, inf = ga.render(wid + "_icon4", prompt, [ref], {"subject": "a Thompson submachine gun", "view": None, "subjects_max": 1}, 7000 + k + seed)
            icon, _ = ga.finish(img, 256, 0.92, False, None, 0.006)
            icon.save(os.path.join(CONTENT, kind, wid, wid + "_icon.png"))
            ga.log("icon written for " + wid)
            continue
        # several candidates, picked by eye (vision QA passes a drum drawn flat)
        from PIL import ImageDraw
        tiles = []
        for n in range(seeds):
            p = os.path.join(OUT, "%s_c%d.png" % (wid, n))
            if not os.path.exists(p):
                img, inf = ga.render(wid + "_icon4_c%d" % n, prompt, [ref], {"subject": "a Thompson submachine gun", "view": None, "subjects_max": 1}, 7000 + k + seed + n * 7919, tries=1)
                img.save(p)
            tiles.append(Image.open(p).convert("RGB"))
        sheet = Image.new("RGB", (512 * len(tiles), 540), (30, 30, 36))
        dr = ImageDraw.Draw(sheet)
        for n, t in enumerate(tiles):
            sheet.paste(t.resize((512, 512)), (512 * n, 28))
            dr.text((512 * n + 8, 6), "%s c%d" % (wid, n), fill=(255, 255, 255))
        sheet.save(os.path.join(OUT, "review_%s.png" % wid))
        ga.log("review sheet for " + wid)
    ga.log("gen_tommy_icon: done")


if __name__ == "__main__":
    main()

"""The Tommy Gun icons painted from the game's own 3D gun: tools/dl/tommy_ref.png (blender_tommy.py's side render) is
the reference the image model copies, so the 2D and the 3D are one gun. Flux.2 dev, one render at a time.

  python tools/gen_tommy_icon.py [--seed=N]
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

SHAPE = ("a Thompson M1928 submachine gun, this exact gun, copying its silhouette and proportions from the reference: the long "
         "barrel with cooling fins and the Cutts compensator at the muzzle leaves the FRONT of the receiver high up, in line with "
         "the bolt handle on top; the big round 50-round drum magazine hangs BELOW the receiver just ahead of the trigger guard; the "
         "vertical wooden foregrip stands under the barrel ahead of the drum; the raked wooden pistol grip behind the trigger and the "
         "wooden shoulder stock at the back; seen from the left side in profile, muzzle pointing to the right, stock to the left, "
         "nothing else in the picture")


def main():
    ga.DEV = True
    seed = 0
    for a in sys.argv[1:]:
        if a.startswith("--seed="):
            seed = int(a.split("=", 1)[1])
    ref = comfy.upload(open(REF, "rb").read(), "tommy_ref.png")
    jobs = [("weapons", "tommy_gun", "black steel, dark walnut wood", 41),
            ("evolutions", "chicago_typewriter", "black steel with polished gold trim on the drum, the barrel fins and the receiver, dark walnut wood", 42)]
    for kind, wid, finish_words, k in jobs:
        prompt = "%s, %s. %s. %s." % (SHAPE, finish_words, ga.ICON_STYLE, ga.BG_GREEN)
        img, inf = ga.render(wid + "_icon3", prompt, [ref], {"subject": "a Thompson submachine gun", "view": None, "subjects_max": 1}, 7000 + k + seed)
        icon, _ = ga.finish(img, 256, 0.92, False, None, 0.006)
        icon.save(os.path.join(CONTENT, kind, wid, wid + "_icon.png"))
        ga.log("icon written for " + wid)
    ga.log("gen_tommy_icon: done")


if __name__ == "__main__":
    main()

"""The launcher icon as one painted illustration on Flux.2 dev, instead of the portrait badge on a gradient.

  python tools/gen_app_icon.py --seeds=3,7      renders one candidate per seed into tools/dl/app_icon/cand_<seed>.png
  python tools/gen_app_icon.py --pick=7         copies that candidate to tools/dl/app_icon/icon_src.png and writes the
                                                icon files (gen_art.app_icon composes from icon_src.png when it exists)

Astro's front still is the identity reference and the style anchor keeps the line; the prompt asks for the things the
old icon lacked: something bright in the visor instead of a black disc, the thumbs-up glove as a second read, a sun halo
so the white suit pops off the warm sky, and the subject inside the middle of the frame for the adaptive safe zone.
"""
import os
import io
import sys
import time
import shutil

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "tools", "dl", "app_icon")
FRONT = os.path.join(REPO, "tools", "dl", "ai_raw_anime", "astro_front.png")

PROMPT = ("Square app icon illustration for a mobile game, in the exact art style of the style reference. This exact astronaut character "
          "from the chest up, leaning into the frame with a big cheerful thumbs-up in her orange glove. Her round white helmet has a dark "
          "mirrored visor, and the visor clearly reflects a small golden desert sun and one green saguaro cactus, bright and readable. "
          "A huge low golden sun sits directly behind her head like a halo, on a warm orange-to-sand gradient sky, with two dark saguaro "
          "cactus silhouettes in the bottom corners and nothing else. Thick clean black outlines, bright saturated flat colours with simple "
          "cel shading, high contrast. The character is centred and fills most of the frame, her whole helmet inside the middle of the "
          "picture with room around it. No text, no letters, no logo, no border, no frame, no watermark.")


def render(seeds):
    os.makedirs(OUT, exist_ok=True)
    refs = ga.ensure_anchor_uploaded() + [comfy.upload(open(FRONT, "rb").read(), "astro_front_ref.png")]
    for s in seeds:
        t0 = time.time()
        imgs, _ = comfy.run(comfy.flux2_dev(PROMPT, s, 1024, 1024, refs=refs, steps=8, guidance=4.0, turbo=True, prefix="88fits/app_icon"))
        img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
        img.save(os.path.join(OUT, "cand_%d.png" % s))
        ga.log("app icon candidate seed %d in %.0fs -> %s" % (s, time.time() - t0, os.path.join(OUT, "cand_%d.png" % s)))
        ga.log("  " + comfy.release_models())


def pick(seed):
    src = os.path.join(OUT, "cand_%d.png" % seed)
    if not os.path.exists(src):
        raise SystemExit("no candidate " + src)
    im = Image.open(src).convert("RGB")
    # the model likes to paint its own rounded white icon frame: keep what is inside it, and step in a little further so
    # the rounded corners' white never reaches the launcher's square
    import numpy as np
    arr = np.asarray(im)
    ink = (arr < 235).any(axis=2)
    ys, xs = np.where(ink)
    if len(xs):
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        inset = int(0.045 * max(x1 - x0, y1 - y0))
        im = im.crop((x0 + inset, y0 + inset, x1 - inset, y1 - inset))
    im.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "icon_src.png"))
    ga.app_icon()
    ga.log("icon files written from seed %d" % seed)


if __name__ == "__main__":
    seeds = [3, 7]
    picked = None
    for a in sys.argv[1:]:
        if a.startswith("--seeds="):
            seeds = [int(x) for x in a.split("=", 1)[1].split(",") if x]
        elif a.startswith("--pick="):
            picked = int(a.split("=", 1)[1])
    if picked is not None:
        pick(picked)
    else:
        render(seeds)

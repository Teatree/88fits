"""Icon variants to choose from (pass 33.4): four serious portraits of the Drifter for his character icon and four
launcher icons of his hat lying on the sand, rendered on Flux.2 dev with the style anchor (and his front painting, so
the face and the hat are his), then laid out on two lettered contact sheets to pick from on a phone.

  python tools/gen_icon_variants.py                          renders what is missing, writes the sheets
  python tools/gen_icon_variants.py --use hat=B drifter=C    installs a pick: the hat painting as the launcher icon
                                                             (tools/dl/app_icon/icon_src.png -> gen_art.app_icon) and
                                                             the portrait as the Drifter's icon (drifter_icon.png)
  --force re-renders; --only=hat or --only=drifter renders one set.

Lessons kept from the earlier icons: the painting comes from dev with the style anchor for the game's line; the subject
sits inside the middle two thirds (the launcher's adaptive mask); no text, no frame (the model likes to paint its own
rounded white frame, which is cropped off, as gen_app_icon.pick does); a portrait is an edit of the hero's own front
painting so the face holds, cut to a round badge by gen_art.portrait_badge; and nothing is named that the model would
draw literally (the old "finger-guns" came back as real pistols).

Output: tools/dl/icon_variants/{hat,drifter}_{A..D}.png (the raw paintings), drifter_{A..D}_badge.png,
hat_{A..D}_icon.png (cropped), sheet_hat.png and sheet_drifter.png."""
import io
import os
import shutil
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "tools", "dl", "icon_variants")
FRONT = os.path.join(REPO, "tools", "dl", "ai_raw_anime", "drifter_front.png")
DRIFTER = os.path.join(REPO, "game", "content", "characters", "drifter")
FORCE = "--force" in sys.argv
ONLY = None
for _a in sys.argv:
    if _a.startswith("--only="):
        ONLY = _a.split("=", 1)[1]
LETTERS = "ABCD"

PORTRAIT = ("A close-up portrait of this exact character for a mobile game avatar icon: only the head and shoulders, the head filling "
            "half of the frame, %s, the shoulders and chest running off the bottom edge of the frame, no legs, no full body. Keep the "
            "same face, hat, outfit, colors and art style as the reference. %s.")
DRIFTER_LOOKS = [
    "a steady serious stare straight at the viewer, jaw set, mouth in a flat line, no smile, the wide hat brim level over his brow, "
    "the collar of his brown duster turned up around his neck, the dark red scarf at his throat",
    "chin lowered, eyes looking up at the viewer from under the brim of his wide hat, the brim's shadow across his brow, a hard "
    "serious look, no smile, the duster collar turned up, the dark red scarf pulled up to his chin",
    "his head turned a little to one side, a cold sidelong look at the viewer, lips pressed together, no smile, the wide hat worn "
    "low, the duster collar turned up, the dark red scarf tied at his throat",
    "eyes narrowed against a desert wind, a grim determined look, a faint dusting of stubble on his jaw, no smile, the wide hat "
    "pulled low, the duster collar turned up, the dark red scarf around his neck blowing to one side",
]

HAT = ("Square app icon illustration for a mobile game, in the exact art style of the style reference: one single wide-brimmed dark "
       "brown leather hat, the same hat the character in the second reference wears, lying on its own on golden desert sand, %s. "
       "Only the hat: no person, no head, no hands. The hat is centred and fills the middle of the picture with room all around it. "
       "Thick clean black outlines, bright saturated flat colours with simple cel shading, high contrast. No text, no letters, no "
       "logo, no border, no frame, no watermark.")
HAT_SCENES = [
    "seen from a little above at three-quarters, crown up, a soft cool shadow on the sand beside it, warm golden light, smooth "
    "sand fading to a warm glow at the edges",
    "seen low from the side, resting crown up on a small sand ridge, a huge low golden sun right behind it in an orange sky, its "
    "long shadow reaching towards the viewer",
    "seen from straight above, crown up, the round brim a clean circle, fine wind ripples in the sand all around it and a crisp "
    "dark shadow on one side",
    "tipped over on its side with the brim sunk a little into the sand, a few grains of sand blowing past, a faint red canyon "
    "wall far behind under a pale warm sky",
]


def _render(key, prompt, refs, seed):
    os.makedirs(OUT, exist_ok=True)
    raw = os.path.join(OUT, key + ".png")
    if os.path.exists(raw) and not FORCE:
        return Image.open(raw).convert("RGB")
    t0 = time.time()
    imgs, _ = comfy.run(comfy.flux2_dev(prompt, seed, 1024, 1024, refs=refs, steps=8, guidance=4.0, turbo=True, prefix="88fits/" + key))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  render %-12s seed %-5d %5.0fs" % (key, seed, time.time() - t0))
    ga.log("  " + comfy.release_models())
    return img


def _crop_frame(im):
    """The painted rounded frame the model likes to add, cut off, and a step further in (gen_app_icon.pick)."""
    arr = np.asarray(im)
    ink = (arr < 235).any(axis=2)
    ys, xs = np.where(ink)
    if len(xs):
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        inset = int(0.045 * max(x1 - x0, y1 - y0))
        im = im.crop((x0 + inset, y0 + inset, x1 - inset, y1 - inset))
    return im.resize((1024, 1024), Image.LANCZOS)


def _font(size):
    for p in ("C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/segoeuib.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def _sheet(tiles, title, path, rounded):
    """A 2x2 sheet of the four tiles with a big letter under each, sized to read on a phone."""
    T = 480
    pad = 30
    lab = 90
    W = 2 * T + 3 * pad
    H = 110 + 2 * (T + lab) + pad
    sheet = Image.new("RGB", (W, H), (22, 20, 30))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 30), title, fill=(255, 205, 90), font=_font(46))
    for k, im in enumerate(tiles):
        x = pad + (k % 2) * (T + pad)
        y = 110 + (k // 2) * (T + lab)
        t = im.convert("RGBA").resize((T, T), Image.LANCZOS)
        mask = Image.new("L", (T * 4, T * 4), 0)
        if rounded:
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, T * 4 - 1, T * 4 - 1), radius=T * 4 // 5, fill=255)
        else:
            ImageDraw.Draw(mask).ellipse((0, 0, T * 4 - 1, T * 4 - 1), fill=255)
        mask = mask.resize((T, T), Image.LANCZOS)
        if not rounded:
            # a badge sits on the game's dark character plate
            plate = Image.new("RGB", (T, T), (40, 36, 58))
            sheet.paste(plate, (x, y), mask)
        sheet.paste(t, (x, y), mask if rounded else t)
        d.text((x + T // 2 - 30, y + T + 6), LETTERS[k], fill=(255, 255, 255), font=_font(64))
    sheet.save(path)
    ga.log("sheet " + path)


def render_all():
    anchor = ga.ensure_anchor_uploaded()
    front = comfy.upload(open(FRONT, "rb").read(), "drifter_front_ref.png")
    if ONLY in (None, "drifter"):
        badges = []
        for k, look in enumerate(DRIFTER_LOOKS):
            img = _render("drifter_" + LETTERS[k], PORTRAIT % (look, ga.BG_BLUE), [front], 401 + k)
            badge = ga.portrait_badge(img)
            badge.save(os.path.join(OUT, "drifter_%s_badge.png" % LETTERS[k]))
            badges.append(badge)
        _sheet(badges, "Drifter icon: A B C D", os.path.join(OUT, "sheet_drifter.png"), False)
    if ONLY in (None, "hat"):
        icons = []
        for k, scene in enumerate(HAT_SCENES):
            img = _render("hat_" + LETTERS[k], HAT % scene, anchor + [front], 501 + k)
            icon = _crop_frame(img)
            icon.save(os.path.join(OUT, "hat_%s_icon.png" % LETTERS[k]))
            icons.append(icon)
        _sheet(icons, "Game icon: A B C D", os.path.join(OUT, "sheet_hat.png"), True)


def use(picks):
    if "hat" in picks:
        src = os.path.join(OUT, "hat_%s_icon.png" % picks["hat"])
        os.makedirs(os.path.join(REPO, "tools", "dl", "app_icon"), exist_ok=True)
        shutil.copy(src, os.path.join(REPO, "tools", "dl", "app_icon", "icon_src.png"))
        ga.app_icon()
        ga.log("launcher icon: hat " + picks["hat"])
    if "drifter" in picks:
        src = os.path.join(OUT, "drifter_%s_badge.png" % picks["drifter"])
        shutil.copy(src, os.path.join(DRIFTER, "drifter_icon.png"))
        ga.log("Drifter icon: " + picks["drifter"])


if __name__ == "__main__":
    if "--use" in sys.argv:
        picks = {}
        for a in sys.argv[sys.argv.index("--use") + 1:]:
            if "=" in a:
                k, v = a.split("=", 1)
                picks[k] = v.upper()
        use(picks)
    else:
        render_all()

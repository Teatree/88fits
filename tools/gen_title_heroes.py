"""Title-screen hero cut-outs (the Wanted title's carousel, pass 40): a full-body splash painting per hero.

Each hero is painted with Flux.2 Klein from its front sprite still (tools/dl/ai_raw_anime/<id>_front.png, the identity
reference) standing in a confident pose facing the viewer, on the screen colour its still was painted on; then keyed,
trimmed and fitted to the title's 520 x 700 box at 1.27x (660 x 888, the phone's scale). Several seeds per hero; they are
picked by eye from the review sheet (vision QA passes extra fingers and ears), then installed:

    python tools/gen_title_heroes.py [--only astro,drifter] [--seeds 4] [--first-seed 11]
        -> tools/dl/title_heroes/<id>_<n>.png (keyed, fitted) + raw renders + tools/dl/title_heroes/review_<id>.png
    python tools/gen_title_heroes.py --pick astro=2 drifter=1
        -> game/art/ui/wanted/hero_<id>.png (the title's WPlaceholder slot `hero_<id>` draws it)
"""
import io
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import artkit  # noqa: E402
import comfy  # noqa: E402
from gen_art import STYLE, BG_BLUE, BG_GREEN  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_anime")
OUT = os.path.join(REPO, "tools", "dl", "title_heroes")
SLOT_DIR = os.path.join(REPO, "game", "art", "ui", "wanted")
BOX = (660, 888)          # the title's 520 x 700 box at 1.27x
RENDER = (832, 1120)      # the same shape, multiples of 16

# the pose each hero strikes (built from its portrait_prompt: the same gesture, the whole body)
POSES = {
    "astro": "standing tall in a confident heroic stance with one hand on her hip and the other giving a cheerful thumbs-up in an "
             "orange glove; her round helmet visor is a completely dark opaque black mirror with no face visible behind it",
    "drifter": "standing with his feet apart, one hand tipping the brim of his wide hat with two fingers, a confident half-smile, "
               "his long brown duster coat and red scarf swaying in the wind",
    "dad": "standing with his hands on his hips and his chest puffed out, grinning proudly under his thick brown mustache",
    "buck": "standing relaxed with one thumb hooked in the collar of his teal t-shirt, a slow easy grin and one eyebrow raised",
    "mira": "standing with one gloved hand raised holding up a fat gold nugget, grinning with a wink, her long braid over her shoulder",
}


def log(*a):
    print(*a, flush=True)


def hero_json(hid):
    return json.load(open(os.path.join(REPO, "game", "content", "characters", hid, hid + ".json"), encoding="utf-8"))


def screen_of(still):
    """The screen colour the hero's still was painted on (it was chosen to key well): blue or green."""
    r, g, b = still.convert("RGB").getpixel((8, 8))
    return BG_GREEN if g > b else BG_BLUE


def fit(rgba):
    """Trim to the figure and fit it to BOX: 95 % of the height, feet 2 % off the bottom, centred."""
    bbox = rgba.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    fig = rgba.crop(bbox)
    k = min(BOX[1] * 0.95 / fig.height, BOX[0] * 0.98 / fig.width)
    fig = fig.resize((max(1, round(fig.width * k)), max(1, round(fig.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", BOX, (0, 0, 0, 0))
    out.alpha_composite(fig, ((BOX[0] - fig.width) // 2, BOX[1] - fig.height - round(BOX[1] * 0.02)))
    return out


def paint(hid, seeds, first):
    d = hero_json(hid)
    still = Image.open(os.path.join(RAW, hid + "_front.png"))
    bg = screen_of(still)
    artkit.KEY_SAT = float(d.get("key_sat", 0.35))
    artkit.GRADE = d.get("grade")
    ref = comfy.upload_pil(still.convert("RGB"), "title_ref_" + hid + ".png")
    pose = POSES.get(hid, str(d.get("portrait_prompt", "standing confidently")))
    prompt = ("A full-body character illustration of this exact character for a mobile game's hero select screen: " + pose +
              ", facing the viewer, seen from the front at eye level, the whole figure visible from the top of the head down to the "
              "feet with empty space around it, no weapon. Keep the same face, outfit, colors and proportions as the reference. " +
              STYLE + ". " + bg + ".")
    os.makedirs(OUT, exist_ok=True)
    made = []
    for n in range(seeds):
        seed = first + n * 101
        imgs, secs = comfy.run(comfy.klein(prompt, seed, RENDER[0], RENDER[1], refs=[ref], prefix="88fits/title_" + hid))
        raw = Image.open(io.BytesIO(imgs[0])).convert("RGB")
        raw.save(os.path.join(OUT, "%s_%d_raw.png" % (hid, n)))
        cut = fit(artkit.key_background(raw))
        cut.save(os.path.join(OUT, "%s_%d.png" % (hid, n)))
        made.append(cut)
        log("  %s #%d seed %d  %.1fs" % (hid, n, seed, secs))
    json.dump({"prompt": prompt, "seeds": [first + n * 101 for n in range(seeds)], "ref": hid + "_front.png"},
              open(os.path.join(OUT, hid + ".json"), "w", encoding="utf-8"), indent=1)
    review(hid, made)


def review(hid, cuts):
    """The candidates side by side on the title's paper, numbered, to pick by eye."""
    pad = 20
    sheet = Image.new("RGB", (len(cuts) * (BOX[0] + pad) + pad, BOX[1] + 2 * pad + 40), (243, 230, 200))
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(os.path.join(REPO, "game", "ui", "fonts", "AlfaSlabOne-Regular.ttf"), 34)
    except Exception:
        font = ImageFont.load_default()
    for i, c in enumerate(cuts):
        x = pad + i * (BOX[0] + pad)
        dr.rectangle([x - 2, pad - 2, x + BOX[0] + 1, pad + BOX[1] + 1], outline=(36, 27, 20), width=2)
        sheet.paste(c, (x, pad), c)
        dr.text((x + 8, pad + BOX[1] + 4), "#%d" % i, fill=(36, 27, 20), font=font)
    sheet.save(os.path.join(OUT, "review_%s.png" % hid))
    log("  review: " + os.path.join(OUT, "review_%s.png" % hid))


def pick(pairs):
    os.makedirs(SLOT_DIR, exist_ok=True)
    for p in pairs:
        hid, n = p.split("=")
        src = os.path.join(OUT, "%s_%s.png" % (hid, n))
        dst = os.path.join(SLOT_DIR, "hero_%s.png" % hid)
        Image.open(src).save(dst)
        log("installed %s -> %s" % (src, dst))


def main():
    args = sys.argv[1:]
    if "--pick" in args:
        pick(args[args.index("--pick") + 1:])
        return
    only = ["astro", "drifter", "dad", "buck", "mira"]
    seeds, first = 4, 11
    for a in args:
        if a.startswith("--only"):
            only = a.split("=", 1)[1].split(",") if "=" in a else args[args.index(a) + 1].split(",")
        elif a.startswith("--seeds="):
            seeds = int(a.split("=")[1])
        elif a.startswith("--first-seed="):
            first = int(a.split("=")[1])
    for hid in only:
        log("painting " + hid)
        paint(hid, seeds, first)


if __name__ == "__main__":
    main()

"""Pass 83 (lane TOTEM): the Spirit Pole's carved segments and its thunderbird crest, painted with Flux.2 Klein on the AI
server (tools/comfy.py; one job at a time: comfy.py takes tools/dl/locks/comfy.lock for the whole process). A scratch
generator, no Level Editor method (Garry, 2026-10-16).

Every gift the Totem Pole can give (content/structures/totem_pole `params.boons`) gets a square carved segment of the
same pole, in the in-play pole painting's style (tools/dl/icons_le_j20261014-005810-ba60/totem_pole_c2.png, the 1024 px
source of art/sprites/props/st_totem_pole.png): the spirit's carved, painted head (painted alone on a green screen and
keyed) laid on ONE shared cedar block (the pole's bare log, painted once with `--block`), so every segment has the same
wood, the same edges and the same carving depth, and stacked segments join as one column; a motif hints the gift's
stat. The finished segment is opaque (the key's edge falls on the head's thick black outline, over wood: no fringe on
the screen). The crest is painted on a green screen and keyed with clean alpha.

  python tools/gen_totem_icons.py --block --seeds 4                     # the bare cedar block -> cands/block_c<k>.png
  python tools/gen_totem_icons.py --pick block=1                        # -> cands/block.png (every segment's wood)
  python tools/gen_totem_icons.py --only bear --seeds 4                 # heads -> cands/<id>_c<k>.png, _cut (keyed), _seg
  python tools/gen_totem_icons.py --anchor bear=2                       # a picked head as a second reference (too strong: every head grew its ears; unused)
  python tools/gen_totem_icons.py --reseg [--only bear]                 # the keyed heads laid again on the block
  python tools/gen_totem_icons.py --make-block 2 --box 150:200:770:820 # the block from a bare-log painting (cands/block.png)
  python tools/gen_totem_icons.py --crest --seeds 4
  python tools/gen_totem_icons.py --pick bear=2 wolf=0 crest=1          # -> game/art/ui/totem/spirit_<id>.png, crest.png
Options: --seed-step N (other seeds), --fill F (the head's share of the block, default 0.9).
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import comfy  # noqa: E402

OUT = os.path.join(REPO, "tools", "dl", "p83", "TOTEM", "cands")
ART = os.path.join(REPO, "game", "art", "ui", "totem")
POLE = os.path.join(REPO, "tools", "dl", "icons_le_j20261014-005810-ba60", "totem_pole_c2.png")
ANCHOR = os.path.join(OUT, "anchor.png")
SIDE = 256

STYLE = ("in the exact cartoon style of the reference totem pole: warm red-brown cedar wood, thick clean black outlines, flat "
         "cel shading with one soft highlight, painted in deep red, black, turquoise and cream, big round white eyes with black "
         "pupils, wide carved mouths with cream teeth, simple chunky readable shapes, mobile game art")
FORMAT = ("One single carved and painted wooden head cut from a totem pole, exactly like the stacked faces of the reference "
          "totem pole: seen straight from the front, symmetrical, a solid chunky block of carved red-brown cedar shaped as "
          "the animal's head, about as wide as it is tall, with a flat straight bottom edge (no neck, no body, no pole above or "
          "below it, no wings, no base). The whole head inside the picture with a small margin. No text, no letters")
BG = "Isolated on a flat solid bright green (#00FF00) background that fills the entire frame, no ground, no shadow, no text"
BLOCK = ("The reference image is a carved wooden totem pole. Paint one square section of its bare log, seen straight from the "
         "front, filling the whole square from edge to edge: smooth red-brown cedar wood with a few fine vertical grain lines, "
         "rounded like a cylinder so it shades a little darker towards the left and right edges, a straight dark carved "
         "groove along the very top edge and another along the very bottom edge. Nothing carved on it, no face, no paint, "
         "no planks, no seams, no background, no text. In the exact cartoon style of the reference: flat cel shading, clean "
         "dark lines, mobile game art")

# the gifts: id -> (what the segment's head is, the stat's motif)
SPIRITS = {
    "bear": ("a carved bear's head with small round ears at the top corners, a broad brown muzzle and a black nose, a fierce open "
             "mouth showing big cream fangs", "three deep claw-scratch marks carved and painted turquoise on each cheek "
             "(strength)"),
    "wolf": ("a carved wolf's head painted cream-white and grey: two TALL POINTED TRIANGULAR wolf ears standing straight up, "
             "a long narrow snout with a black nose, slanted eyes, a wide grin of sharp cream teeth (a wolf, not a bear: no "
             "round ears)", "turquoise carved wind streaks sweeping back along both cheeks like speed lines (speed)"),
    "whale": ("a carved whale's head painted dark blue-grey with a cream belly band, a wide curved mouth, a turquoise blowhole "
              "spout curling up from the top of its head", "a big red carved heart on its forehead (health)"),
    "thunderbird": ("a carved thunderbird's head: NO EARS, a smooth rounded bird's head with feather crests carved over the "
                    "brow, fierce eyes, and a huge hooked yellow beak curving down over its chin (a bird, not a bear)", "two "
                    "turquoise zigzag lightning bolts carved on either side of the beak (quickness)"),
    "seal": ("a carved seal's head painted grey: NO EARS, a smooth round bald head like a ball, big dark eyes, a small black "
             "nose, long cream whiskers (a seal, not a bear)", "a red horseshoe magnet with cream tips held in its mouth (a "
             "pull)"),
    "salmon": ("a carved salmon's head seen from the front: NO EARS, a pointed fish head painted red with a turquoise lower "
               "jaw, a hooked open mouth, round fish eyes on the sides, carved gill lines and small fins at the cheeks (a fish, "
               "not a bear)", "three turquoise carved water droplets on its brow and a small red heart on its cheek (healing)"),
    "frog": ("a carved frog's head painted turquoise: NO EARS, a wide flat head with two big round bulging eyes sitting on "
             "top of it and a very wide red-lipped mouth across the whole face (a frog, not a bear)", "a glowing turquoise "
             "crystal gem held in its wide mouth (experience)"),
    "killer_whale": ("a carved killer whale's head painted glossy black with white eye patches, a wide mouth of sharp cream "
                     "teeth", "a tall black dorsal fin rising like a blade from the top of its head and a small red four-point "
                     "star sparkle beside it (a critical strike)"),
    "bullhead": ("a carved bullhead fish's head: NO EARS, a very broad flat heavy fish head wider than it is tall, painted "
                 "red-brown, a row of turquoise spines along its brow, small eyes, thick lips and a wide frowning fish mouth (a "
                 "fish, not a bear)", "a round carved wooden shield with a turquoise rim held below its chin (protection)"),
    "raven": ("a carved raven's head painted glossy black: NO EARS, a smooth rounded bird's head with turquoise feather "
              "marks, and a long straight black beak pointing straight down (a bird, not a bear)", "a shining round golden sun "
              "disc held in the tip of its beak (good luck)"),
    "serpent": ("a carved two-headed serpent: NO EARS, a round human-like central face in the middle, and a turquoise "
                "serpent head with an open mouth facing out to the left and another facing out to the right, their scaly "
                "bodies curling round the central face", "carved turquoise rings rippling out round the central face (reach)"),
}

CREST = ("The reference image is a carved wooden totem pole. Paint only its top: the carved thunderbird crest that crowns the "
         "pole, seen straight from the front, its two carved wooden wings spread wide and level to the left and the right with "
         "black and turquoise feather tips, its proud head with a curved yellow beak in the middle at the top, and its body a "
         "broad carved block that ends in a flat straight cut at the bottom where it sits on the pole below. Wide and short "
         "picture, the whole bird inside the frame. " + STYLE + ". " + BG)


def arg_list(name):
    out = []
    a = sys.argv[1:]
    for i, x in enumerate(a):
        if x == "--" + name:
            for y in a[i + 1:]:
                if y.startswith("--"):
                    break
                out.extend(s for s in y.split(",") if s)
        elif x.startswith("--" + name + "="):
            out.extend(s for s in x.split("=", 1)[1].split(",") if s)
    return out


def opt(name, default=None):
    v = arg_list(name)
    return v[0] if v else default


def sheet(paths, dst, label):
    ims = [Image.open(p).convert("RGBA") for p in paths]
    W = 300
    out = Image.new("RGB", (W * len(ims), W + 26), (60, 40, 30))
    dr = ImageDraw.Draw(out)
    for i, im in enumerate(ims):
        bg = Image.new("RGBA", im.size, (90, 70, 60, 255))
        bg.alpha_composite(im)
        t = bg.copy()
        t.thumbnail((W, W), Image.LANCZOS)
        out.paste(t.convert("RGB"), (i * W, 26))
        dr.text((i * W + 6, 6), "%s c%d" % (label, i), fill=(255, 230, 140))
    out.save(dst)
    return dst


def _save(dst, data, meta):
    with open(dst, "wb") as f:
        f.write(data)
    with open(dst[:-4] + ".json", "w", encoding="utf-8", newline="\n") as f:
        json.dump(meta, f, indent=1)


def _seed(base, k):
    return base + 17 * k + int(opt("seed-step", "0") or 0)


def uploads():
    refs = [comfy.upload_pil(Image.open(POLE).convert("RGB"), "p83_totem_pole_ref.png")]
    if os.path.isfile(ANCHOR):
        refs.append(comfy.upload_pil(Image.open(ANCHOR).convert("RGB"), "p83_totem_anchor_ref.png"))
    return refs


def seg_prompt(sid, with_anchor):
    head, motif = SPIRITS[sid]
    lead = ("The first reference image is the totem pole whose carving style and colours to copy. " +
            ("The second reference image shows the exact format, size and finish of one head; paint a NEW head in that same "
             "format, with the same carving depth and outline weight, but a different animal. " if with_anchor else ""))
    return lead + FORMAT + ". The head: " + head + "; with " + motif + ". " + STYLE + ". " + BG + "."


def paint_block(seeds):
    os.makedirs(OUT, exist_ok=True)
    refs = [comfy.upload_pil(Image.open(POLE).convert("RGB"), "p83_totem_pole_ref.png")]
    paths = []
    for k in range(seeds):
        seed = _seed(83700, k)
        ims, secs = comfy.run(comfy.klein(BLOCK, seed, 1024, 1024, refs=refs, prefix="88fits/p83_totem_block"))
        dst = os.path.join(OUT, "block_c%d.png" % k)
        _save(dst, ims[0], {"id": "block", "seed": seed, "prompt": BLOCK, "secs": round(secs, 1)})
        print("gen_totem_icons: block c%d seed %d (%.0f s)" % (k, seed, secs))
        paths.append(dst)
    print("gen_totem_icons: review", sheet(paths, os.path.join(OUT, "review_block.png"), "block"))


def paint_segments(ids, seeds):
    os.makedirs(OUT, exist_ok=True)
    refs = uploads()
    for sid in ids:
        p = seg_prompt(sid, len(refs) > 1)
        paths = []
        for k in range(seeds):
            seed = _seed(83000 + 1000 * list(SPIRITS).index(sid), k)
            ims, secs = comfy.run(comfy.klein(p, seed, 1024, 1024, refs=refs, prefix="88fits/p83_totem_" + sid))
            dst = os.path.join(OUT, "%s_c%d.png" % (sid, k))
            _save(dst, ims[0], {"id": sid, "seed": seed, "prompt": p, "secs": round(secs, 1)})
            cut = key_clean(Image.open(dst))
            cut.save(dst[:-4] + "_cut.png")
            segment(cut).save(dst[:-4] + "_seg.png")
            print("gen_totem_icons: %s c%d seed %d (%.0f s)" % (sid, k, seed, secs))
            paths.append(dst[:-4] + "_seg.png")
        print("gen_totem_icons: review", sheet(paths, os.path.join(OUT, "review_%s.png" % sid), sid))


def paint_crest(seeds):
    os.makedirs(OUT, exist_ok=True)
    pole = Image.open(POLE).convert("RGB").crop((0, 0, 1024, 560))
    refs = [comfy.upload_pil(pole, "p83_totem_crest_ref.png")]
    paths = []
    for k in range(seeds):
        seed = _seed(83900, k)
        ims, secs = comfy.run(comfy.klein(CREST, seed, 1280, 640, refs=refs, prefix="88fits/p83_totem_crest"))
        dst = os.path.join(OUT, "crest_c%d.png" % k)
        _save(dst, ims[0], {"id": "crest", "seed": seed, "prompt": CREST, "secs": round(secs, 1)})
        key_clean(Image.open(dst)).save(dst[:-4] + "_cut.png")
        print("gen_totem_icons: crest c%d seed %d (%.0f s)" % (k, seed, secs))
        paths.append(dst[:-4] + "_cut.png")
    print("gen_totem_icons: review", sheet(paths, os.path.join(OUT, "review_crest.png"), "crest"))


# ---------------------------------------------------------------- finishing

def key_clean(img):
    """A painting off its green screen: artkit's key (hue distance, stray blobs dropped, despill), then the alpha made
    clean: every pixel either the figure (255) or nothing (0) except a 1 px antialiased rim, holes filled, one piece
    only, no green left in the rim, cropped to the figure."""
    import artkit
    rgba = artkit.key_background(img.convert("RGB"), cut_shadow=False)
    a = np.asarray(rgba).astype(np.float32)
    solid = a[..., 3] > 127
    try:
        from scipy import ndimage
        solid = ndimage.binary_fill_holes(solid)
        lab, n = ndimage.label(solid)
        if n > 1:
            sizes = ndimage.sum(solid, lab, range(1, n + 1))
            solid = lab == (1 + int(np.argmax(sizes)))
    except ImportError:
        pass
    m = Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    al = np.asarray(m).astype(np.float32) / 255.0
    al[al < 0.12] = 0.0
    al[al > 0.88] = 1.0
    rgb = a[..., :3]
    # the rim keeps no green: its green held down to the larger of red and blue
    g_cap = np.maximum(rgb[..., 0], rgb[..., 2])
    rim = al < 1
    rgb[..., 1] = np.where(rim & (rgb[..., 1] > g_cap), g_cap, rgb[..., 1])
    # a figure pixel that was keyed out but filled back (a hole) keeps the painting's own colour
    src = np.asarray(img.convert("RGB")).astype(np.float32)
    hole = (al > 0) & (a[..., 3] < 127)
    rgb[hole] = src[hole]
    rgb[al == 0] = 0
    out = np.concatenate([rgb, (al * 255.0)[..., None]], axis=2).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(out, "RGBA")
    bb = im.getchannel("A").getbbox()
    return im.crop(bb) if bb else im


def block_image():
    """The shared cedar block every segment is laid on: cands/block.png at SIDE px, or (before one is picked) a plain
    cylinder-shaded cedar square with a groove top and bottom."""
    p = os.path.join(OUT, "block.png")
    if os.path.isfile(p):
        return Image.open(p).convert("RGBA").resize((SIDE, SIDE), Image.LANCZOS)
    x = np.linspace(-1.0, 1.0, SIDE)
    shade = 0.78 + 0.22 * np.sqrt(np.clip(1.0 - x * x, 0.0, 1.0))
    base = np.array([150, 70, 40], np.float32)
    arr = np.tile((base[None, :] * shade[:, None])[None, :, :], (SIDE, 1, 1))
    arr[:6] *= 0.45
    arr[-6:] *= 0.45
    return Image.fromarray(np.concatenate([arr, np.full((SIDE, SIDE, 1), 255.0)], axis=2).astype(np.uint8), "RGBA")


BLOCK_BASE = (146, 64, 36)


def make_block(src, box):
    """The shared block from a painted bare log: the grain of `box` cut from its middle (the drum's outline and lid left
    out), its own light and shade taken out, laid on one cedar colour shaded like a cylinder the same on both sides, and
    a carved groove along the top and the bottom edge (the joints between segments) -> cands/block.png at 1024."""
    im = Image.open(src).convert("RGB").crop(box).resize((1024, 1024), Image.LANCZOS)
    lum = np.asarray(im.convert("L")).astype(np.float32)
    low = np.asarray(im.convert("L").filter(ImageFilter.GaussianBlur(40))).astype(np.float32)
    detail = np.clip(lum / np.maximum(low, 1.0), 0.35, 1.25)
    x = np.linspace(-1.0, 1.0, 1024)
    shade = 0.72 + 0.28 * np.sqrt(np.clip(1.0 - x * x, 0.0, 1.0))
    base = np.array(BLOCK_BASE, np.float32)
    arr = base[None, None, :] * shade[None, :, None] * detail[:, :, None]
    g = 22
    arr[:g] *= 0.35
    arr[-g:] *= 0.35
    arr[g:g + 8] *= 1.18
    arr[-g - 8:-g] *= 0.8
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "block.png"))
    print("gen_totem_icons: block made from %s %s" % (os.path.basename(src), box))


def segment(cut):
    """A keyed head laid on the cedar block: fitted to `--fill` of the square (its width or its height, whichever binds),
    centred across and standing a little above the bottom joint."""
    fill = float(opt("fill", "0.9"))
    blk = block_image()
    room = SIDE * fill
    k = min(room / float(cut.width), room / float(cut.height))
    h = cut.resize((max(1, int(round(cut.width * k))), max(1, int(round(cut.height * k)))), Image.LANCZOS)
    x = (SIDE - h.width) // 2
    y = SIDE - int(round(SIDE * (1.0 - fill) * 0.5)) - h.height
    blk.alpha_composite(h, (x, max(0, y)))
    return blk


def crest_crop(im, below=0.06):
    """The crest without the bare post the painting runs down from the bird: cut straight across `below` of its height
    under the row where the wings end (the first row under the widest one no wider than 1.25 x the post), so its foot is
    a flat cut that sits behind the top segment."""
    a = np.asarray(im)[..., 3] > 0
    w = a.sum(axis=1)
    h = len(w)
    post = max(1, int(np.median(w[int(h * 0.8):])))
    top = int(np.argmax(w))
    end = h
    for y in range(top, h):
        if w[y] <= post * 1.25:
            end = y
            break
    end = min(h, end + int(round(h * below)))
    return im.crop((0, 0, im.width, end))


def finish_crest(src_cut, width=720):
    im = crest_crop(Image.open(src_cut).convert("RGBA"))
    k = width / float(im.width)
    im = im.resize((width, max(1, int(round(im.height * k)))), Image.LANCZOS)
    # resizing softens the rim again: keep it, but nothing faint far out
    a = np.asarray(im).copy()
    al = a[..., 3]
    al[al < 20] = 0
    a[..., :3][al == 0] = 0
    return Image.fromarray(a, "RGBA")


def pick(pairs):
    for pr in pairs:
        key, k = pr.split("=")
        if key == "crest":
            finish_crest(os.path.join(OUT, "crest_c%s_cut.png" % k)).save(os.path.join(ART, "crest.png"))
            print("gen_totem_icons: crest <- crest_c%s" % k)
        elif key == "block":
            Image.open(os.path.join(OUT, "block_c%s.png" % k)).convert("RGB").save(os.path.join(OUT, "block.png"))
            print("gen_totem_icons: block <- block_c%s" % k)
        else:
            cut = Image.open(os.path.join(OUT, "%s_c%s_cut.png" % (key, k))).convert("RGBA")
            # opaque: the block is, and the head lies on it
            seg = segment(cut)
            seg.putalpha(255)
            seg.save(os.path.join(ART, "spirit_%s.png" % key))
            print("gen_totem_icons: spirit_%s <- c%s" % (key, k))


def reseg(ids):
    for sid in ids:
        segs = []
        for c in sorted(glob.glob(os.path.join(OUT, "%s_c[0-9]_cut.png" % sid))):
            segment(Image.open(c).convert("RGBA")).save(c.replace("_cut.png", "_seg.png"))
            segs.append(c.replace("_cut.png", "_seg.png"))
        if segs:
            print("gen_totem_icons: review", sheet(segs, os.path.join(OUT, "review_%s.png" % sid), sid))


def main():
    a = sys.argv[1:]
    if "--pick" in a:
        pick(arg_list("pick"))
        return
    if "--anchor" in a:
        key, k = arg_list("anchor")[0].split("=")
        Image.open(os.path.join(OUT, "%s_c%s.png" % (key, k))).convert("RGB").save(ANCHOR)
        print("gen_totem_icons: anchor <- %s c%s" % (key, k))
        return
    if "--make-block" in a:
        k = opt("make-block", "2")
        box = tuple(int(v) for v in (opt("box", "140,200,860,860") or "").split(":")) if ":" in (opt("box", "") or "") else (140, 200, 860, 860)
        make_block(os.path.join(OUT, "block_c%s.png" % k), box)
        return
    if "--reseg" in a:
        reseg(arg_list("only") or list(SPIRITS))
        return
    seeds = int(opt("seeds", "4"))
    if "--crest" in a:
        paint_crest(seeds)
        return
    if "--block" in a:
        paint_block(seeds)
        return
    ids = arg_list("only") or list(SPIRITS)
    for sid in ids:
        if sid not in SPIRITS:
            raise SystemExit("gen_totem_icons: no spirit %r (%s)" % (sid, ", ".join(SPIRITS)))
    paint_segments(ids, seeds)


if __name__ == "__main__":
    main()

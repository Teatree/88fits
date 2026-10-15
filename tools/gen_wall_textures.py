"""Pass 80 (lane WALLS; Garry: "the textures on the mountains behind the walls look too low res and walls don't have any
proper textures to begin with. Make the walls look like sandstone castle walls (but western)"): Red Canyon's rock and
wall paintings from the AI server, made seamless, normalised to a neutral grey mean so the map's colour keys
(timeline_data wall_colors / rock_color) stay the colour drawn.

  python tools/gen_wall_textures.py cands --kind cliff|wall|top [--seeds 4] [--size 1024] [--prompt N] [--ref boulder]
      Flux.2 Klein text-to-image candidates -> tools/dl/p80/WALLS/tex/raw/<kind>_p<N>_s<seed>.png + a review sheet
  python tools/gen_wall_textures.py seam <raw.png> [--band 0.14] [--seed 7]
      seamless: the picture rolled by half (its edges meet in a cross through the middle), the cross repainted by Klein
      under a noise mask with the rest as context, the repaint laid back in under a feathered mask (so the edges are the
      original's own middle, exact on every wrap) -> <raw>_seam.png + a 2x2 tiled preview
  python tools/gen_wall_textures.py neutral <seam.png> --out <name> [--size 1024] [--keep 0.35] [--value 0.8]
      the painting brought to a neutral grey mean (each channel over its own mean, the hue variation kept `keep` of
      what it was), its mean value `value`, resized, written to game/art/env/<name>.png
The ComfyUI lock is comfy.py's (taken on the first upload or queue, held for the whole process).
"""
import argparse
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import comfy  # noqa: E402

REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "tools", "dl", "p80", "WALLS", "tex")
ENV = os.path.join(REPO, "game", "art", "env")

STYLE = ("stylized hand-painted mobile game texture in the style of Clash of Clans and Hearthstone, crisp painted detail, "
         "even flat lighting, no cast shadows, fills the whole frame edge to edge, seamless tileable texture")
PROMPTS = {
    "cliff": [
        "Flat front view of a desert canyon cliff face: layered red sandstone with horizontal sedimentary strata bands of "
        "varied thickness, small rock ledges, vertical cracks and joints, chipped edges, faint darker desert-varnish "
        "streaks running down, no sky, no horizon, no plants. " + STYLE,
        "Flat front view of a weathered sandstone canyon wall: many thin horizontal rock layers stacked in bands, some "
        "layers jutting out as ledges, broken blocks, deep vertical fractures, rough grainy rock surface, no sky, no "
        "horizon, no plants. " + STYLE,
        "Orthographic texture of eroded red rock cliff, stratified sandstone layers in horizontal bands, cracked into "
        "big angular blocks, crisp outlines on the cracks, painted highlights on the ledges, no sky, no plants. " + STYLE,
        "Flat front view of a natural eroded desert cliff face, NOT bricks and NOT masonry: organic wavy sedimentary "
        "strata that swell and taper across the frame, soft rounded weathered ledges, irregular fractures, crumbling "
        "overhangs, wind-carved hollows, grainy red-orange sandstone with paler and darker layers, no sky, no plants. " + STYLE,
        "Flat front view of a Monument Valley mesa cliff face, natural rock, not bricks: long horizontal layers of "
        "sandstone with uneven thickness, eroded soft edges, random irregular vertical joints, scree crumbs on the "
        "ledges, darker streaks of desert varnish, no sky, no plants. " + STYLE,
        "Wide distant flat front view of a huge 100 metre tall Monument Valley mesa cliff face filling the frame, natural "
        "rock, not bricks: dozens of thin horizontal sandstone layers of uneven thickness, many small ledges with scree, "
        "random irregular vertical joints and fractures, darker streaks of desert varnish, small detail everywhere, no "
        "sky, no ground, no plants. " + STYLE,
    ],
    "wall": [
        "Flat front view of a dressed sandstone block wall: rectangular cut stone blocks of a few sizes laid in straight "
        "level courses, thin light mortar joints, warm buff sandstone, slightly weathered with chipped edges and small "
        "pits, a Spanish mission fort in the American Southwest, no windows, no doors, no plants. " + STYLE,
        "Flat front view of an old western fort wall built of large tan sandstone blocks in regular horizontal courses, "
        "each block with bevelled chiselled edges and painted highlights, thin pale mortar lines, weathered, like the "
        "Alamo mission walls, no windows, no plants. " + STYLE,
        "Orthographic texture of ashlar masonry: big smooth rectangular sandstone bricks in neat running-bond courses, "
        "soft rounded worn edges, light mortar, subtle colour variation between blocks, dusty desert stone, no windows, "
        "no plants. " + STYLE,
    ],
    "top": [
        "Top-down view of worn sandstone paving flagstones of a fort's wall walk, big rectangular slabs, thin mortar "
        "joints, dust in the cracks, no plants. " + STYLE,
    ],
}
REFS = {"boulder": os.path.join(REPO, "game", "art", "sprites", "props", "boulder.png")}


def _png(img):
    b = io.BytesIO()
    img.save(b, "PNG")
    return b.getvalue()


def _sheet(paths, out, cell=512):
    ims = [Image.open(p).convert("RGB").resize((cell, cell), Image.LANCZOS) for p in paths]
    cols = min(4, len(ims))
    rows = (len(ims) + cols - 1) // cols
    sh = Image.new("RGB", (cols * cell, rows * cell), (40, 40, 40))
    for k, im in enumerate(ims):
        sh.paste(im, ((k % cols) * cell, (k // cols) * cell))
    sh.save(out)
    print("sheet", out)


def cands(a):
    os.makedirs(os.path.join(OUT, "raw"), exist_ok=True)
    plist = PROMPTS[a.kind]
    which = [a.prompt] if a.prompt is not None else list(range(len(plist)))
    refs = ()
    tag = ""
    if a.ref:
        im = Image.open(REFS.get(a.ref, a.ref)).convert("RGBA")
        bg = Image.new("RGBA", im.size, (128, 128, 128, 255))
        bg.alpha_composite(im)
        refs = (comfy.upload(_png(bg.convert("RGB")), "p80_walls_ref_%s.png" % os.path.basename(a.ref).split(".")[0]),)
        tag = "_r"
    made = []
    for p in which:
        for s in range(a.seeds):
            seed = a.seed0 + s
            g = comfy.klein(plist[p], seed, width=a.size, height=a.size, refs=refs, prefix="88fits/p80_walls_%s" % a.kind)
            imgs, secs = comfy.run(g)
            path = os.path.join(OUT, "raw", "%s_p%d%s_s%d.png" % (a.kind, p, tag, seed))
            with open(path, "wb") as f:
                f.write(imgs[0])
            made.append(path)
            print("cand", path, "%.0fs" % secs)
    _sheet(made, os.path.join(OUT, "%s%s_sheet_%d.png" % (a.kind, tag, a.seed0)))


def _cross_mask(n, band):
    """White where the rolled picture's seams cross the middle: a band `band` x n wide round x = n/2 and y = n/2."""
    m = np.zeros((n, n), np.float32)
    h = int(n * band * 0.5)
    c = n // 2
    m[:, c - h:c + h] = 1.0
    m[c - h:c + h, :] = 1.0
    return m


def _lay_back(rolled, gen, n, band, soft=0.0):
    """The repaint laid back into the rolled picture: all of it inside the band, a short feather just over the band's
    edge (outside it the repaint is only the kept picture through the VAE), so the edges stay the original's middle;
    with a soft mask the same blur as the sampler's mask."""
    blur = n * band * soft if soft > 0 else max(2.0, n * 0.005)
    fm = Image.fromarray((_cross_mask(n, band) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur))
    fm = np.asarray(fm).astype(np.float32)[..., None] / 255.0
    return rolled * (1.0 - fm) + gen * fm


def seam(a):
    src = Image.open(a.src).convert("RGB")
    n = src.width
    arr = np.asarray(src).astype(np.float32) / 255.0
    rolled = np.roll(np.roll(arr, n // 2, axis=0), n // 2, axis=1)
    mask = _cross_mask(n, a.band)
    rolled_img = Image.fromarray((rolled * 255).astype(np.uint8))
    up = comfy.upload(_png(rolled_img), "p80_walls_seam_src.png")
    if a.soft > 0:
        # a soft mask (DifferentialDiffusion repaints the middle first and the edges last, so the band grows into what is
        # kept instead of meeting it at a hard line)
        mimg = Image.fromarray((_cross_mask(n, a.band * 1.4) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(n * a.band * a.soft))
    else:
        mimg = Image.fromarray((mask * 255).astype(np.uint8))
    mimg = mimg.convert("RGB")
    upm = comfy.upload(_png(mimg), "p80_walls_seam_mask.png")
    prompt = a.prompt_text or PROMPTS[a.kind][a.prompt or 0]
    g = comfy.Graph()
    m = g.add("UNETLoader", "Flux.2 Klein 9B", unet_name=comfy.KLEIN_UNET, weight_dtype="default")
    if a.soft > 0:
        m = g.add("DifferentialDiffusion", model=(m, 0))
    c = g.add("CLIPLoader", "Qwen3 8B text encoder", clip_name=comfy.KLEIN_CLIP, type="flux2", device="default")
    v = g.add("VAELoader", vae_name=comfy.VAE)
    pos = g.add("CLIPTextEncode", "prompt", clip=(c, 0), text=prompt)
    neg = g.add("ConditioningZeroOut", conditioning=(pos, 0))
    li = g.add("LoadImage", "rolled", image=up)
    enc = g.add("VAEEncode", pixels=(li, 0), vae=(v, 0))
    if a.ref:
        # (the rolled picture as Klein's reference makes it copy the seams it should repaint: off by default)
        pos = g.add("ReferenceLatent", conditioning=(pos, 0), latent=(enc, 0))
        neg = g.add("ReferenceLatent", conditioning=(neg, 0), latent=(enc, 0))
    lm = g.add("LoadImageMask", "seam mask", image=upm, channel="red")
    masked = g.add("SetLatentNoiseMask", samples=(enc, 0), mask=(lm, 0))
    guider = g.add("CFGGuider", model=(m, 0), positive=(pos, 0), negative=(neg, 0), cfg=1.0)
    sampler = g.add("KSamplerSelect", sampler_name="euler")
    sig = g.add("Flux2Scheduler", steps=a.steps, width=n, height=n)
    noise = g.add("RandomNoise", noise_seed=a.seed)
    out = g.add("SamplerCustomAdvanced", noise=(noise, 0), guider=(guider, 0), sampler=(sampler, 0), sigmas=(sig, 0), latent_image=(masked, 0))
    dec = g.add("VAEDecode", samples=(out, 0), vae=(v, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix="88fits/p80_walls_seam")
    imgs, secs = comfy.run(g)
    gen = np.asarray(Image.open(io.BytesIO(imgs[0])).convert("RGB").resize((n, n), Image.LANCZOS)).astype(np.float32) / 255.0
    base = os.path.splitext(a.src)[0]
    base = base + a.tag
    Image.fromarray(np.clip(gen * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(base + "_seamgen.png")
    res = _lay_back(rolled, gen, n, a.band * (1.4 if a.soft > 0 else 1.0), a.soft)
    outp = base + "_seam.png"
    Image.fromarray(np.clip(res * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(outp)
    tiled = np.tile(res, (2, 2, 1))
    Image.fromarray(np.clip(tiled * 255.0 + 0.5, 0, 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save(base + "_seam_tiled.png")
    print("seam", outp, "%.0fs" % secs)


def neutral(a):
    img = Image.open(a.src).convert("RGB")
    if a.size and img.width != a.size:
        img = img.resize((a.size, a.size), Image.LANCZOS)
    arr = np.asarray(img).astype(np.float32) / 255.0
    lin = np.where(arr <= 0.04045, arr / 12.92, ((arr + 0.055) / 1.055) ** 2.4)
    mean = lin.reshape(-1, 3).mean(axis=0)
    lum = (lin * np.array([0.299, 0.587, 0.114], np.float32)).sum(axis=2, keepdims=True)
    # each channel over its own mean: a neutral mean, the relative hue variation kept `keep` of what it was
    rel = lin / np.maximum(mean, 1e-4)
    lum_rel = lum / max(float((mean * np.array([0.299, 0.587, 0.114])).sum()), 1e-4)
    out = lum_rel * (1.0 - a.keep) + rel * a.keep
    # its mean value: `value` in sRGB terms (a key tint then is about the colour drawn)
    target = ((a.value + 0.055) / 1.055) ** 2.4
    out = out * target / max(float(out.mean()), 1e-4)
    srgb = np.where(out <= 0.0031308, out * 12.92, 1.055 * np.power(np.clip(out, 0, None), 1 / 2.4) - 0.055)
    res = Image.fromarray(np.clip(srgb * 255.0 + 0.5, 0, 255).astype(np.uint8))
    path = os.path.join(ENV, a.out + ".png")
    res.save(path)
    print("wrote", path, res.size, "mean", np.asarray(res).reshape(-1, 3).mean(axis=0))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd")
    c = sub.add_parser("cands")
    c.add_argument("--kind", default="cliff")
    c.add_argument("--seeds", type=int, default=4)
    c.add_argument("--seed0", type=int, default=1)
    c.add_argument("--size", type=int, default=1024)
    c.add_argument("--prompt", type=int, default=None)
    c.add_argument("--ref", default="")
    s = sub.add_parser("seam")
    s.add_argument("src")
    s.add_argument("--kind", default="cliff")
    s.add_argument("--prompt", type=int, default=None)
    s.add_argument("--prompt-text", default="")
    s.add_argument("--band", type=float, default=0.14)
    s.add_argument("--seed", type=int, default=7)
    s.add_argument("--steps", type=int, default=4)
    s.add_argument("--ref", action="store_true")
    s.add_argument("--soft", type=float, default=0.0)
    s.add_argument("--tag", default="")
    n = sub.add_parser("neutral")
    n.add_argument("src")
    n.add_argument("--out", required=True)
    n.add_argument("--size", type=int, default=0)
    n.add_argument("--keep", type=float, default=0.35)
    n.add_argument("--value", type=float, default=0.8)
    a = ap.parse_args()
    if a.cmd == "cands":
        cands(a)
    elif a.cmd == "seam":
        seam(a)
    elif a.cmd == "neutral":
        neutral(a)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()

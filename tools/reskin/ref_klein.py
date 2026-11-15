"""A reskin's reference picture (tools/reskin/README.md): Klein edits of the model's own render (stage.py's ref_side.png,
the paint model's front view), the render's silhouette kept as the alpha, so nothing outside the mesh is painted.
  python tools/reskin/ref_klein.py --src <ref_side.png> --out <dir> --prompt "<the look>" [--seeds 4] [--seed0 15200]
  python tools/reskin/ref_klein.py --out <dir> --pick k          -> <dir>/ref_rgba.png
The hell hound wolf's prompt (2026-11-15) is HELL_HOUND below (--prompt hellhound)."""
import io, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from PIL import Image

HELL_HOUND = ("Turn this wolf into a hell hound. Keep exactly the same pose, the same body shape and outline, the same camera "
              "and the same size and place in the picture. Its fur is charred black and dark smoky grey, with jagged cracks of "
              "glowing molten lava, bright orange and yellow, running along its ribs, shoulders, spine, neck and legs, like "
              "cooling magma under burnt skin; glowing ember-red eyes; a fiery orange glow inside its open mouth; the tips of "
              "its mane and tail fur smouldering orange like embers; dark claws. A demonic creature from hell, detailed game "
              "texture, even soft light. Plain white background, nothing outside the body, no flames, no smoke, no ground.")


def arg(a, k, d=None):
    return a[a.index(k) + 1] if k in a else d


def main():
    a = sys.argv[1:]
    out = os.path.abspath(arg(a, "--out"))
    os.makedirs(out, exist_ok=True)
    if "--pick" in a:
        k = int(arg(a, "--pick"))
        Image.open(os.path.join(out, "cand_%d_rgba.png" % k)).save(os.path.join(out, "ref_rgba.png"))
        print("picked", k, "->", os.path.join(out, "ref_rgba.png"))
        return
    import comfy
    prompt = arg(a, "--prompt")
    if prompt in (None, "hellhound"):
        prompt = HELL_HOUND
    seeds = int(arg(a, "--seeds", 4))
    seed0 = int(arg(a, "--seed0", 15200))
    src = Image.open(os.path.abspath(arg(a, "--src"))).convert("RGBA")
    white = Image.new("RGBA", src.size, (255, 255, 255, 255))
    white.alpha_composite(src)
    name = comfy.upload_pil(white.convert("RGB"), "reskin_src.png")
    alpha = src.getchannel("A")
    for k in range(seeds):
        pngs, secs = comfy.run(comfy.klein(prompt, seed0 + k, width=1024, height=1024, refs=[name], prefix="88fits/reskin"))
        im = Image.open(io.BytesIO(pngs[0])).convert("RGB").resize(src.size, Image.LANCZOS)
        im.save(os.path.join(out, "cand_%d.png" % k))
        rgba = im.convert("RGBA")
        rgba.putalpha(alpha)
        rgba.save(os.path.join(out, "cand_%d_rgba.png" % k))
        print("cand", k, "%.0fs" % secs, flush=True)
    w, h = 512, 512
    sheet = Image.new("RGB", (w * (seeds + 1), h), (40, 40, 40))
    sheet.paste(white.convert("RGB").resize((w, h)), (0, 0))
    for k in range(seeds):
        sheet.paste(Image.open(os.path.join(out, "cand_%d.png" % k)).resize((w, h)), (w * (k + 1), 0))
    sheet.save(os.path.join(out, "sheet.png"))
    print("sheet", os.path.join(out, "sheet.png"))


if __name__ == "__main__":
    main()

"""The Big Mouth's companion, painted (pass 33.2): a floating cartoon mouth in the sheet's anime style, one render with the
lips shut and one edit of it opened in a big "aaah", keyed, fitted to one height and packed as a two-frame strip
(idle, open) for a BillboardSprite, so the mouth always faces the camera like every character. The 3D mouth it
replaces was a torus with boxes for teeth and read as a red doughnut.

  python tools/gen_mouth.py [--force] [--klein]

Output: game/content/weapons/big_mouth/big_mouth_sprite.png (2 frames of 256 px) and the two raw renders in
tools/dl/ai_raw_props/."""
import io
import os
import sys
import time

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(REPO, "game", "content", "weapons", "big_mouth", "big_mouth_sprite.png")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_props")
FORCE = "--force" in sys.argv
DEV = "--klein" not in sys.argv
CELL = 256

CLOSED = ("a floating cartoon mouth for a game, just the lips on their own: big glossy full red lips pressed together in a "
          "cheeky smirk, a small bright highlight on the lower lip, no face, no eyes, no nose, no skin around them")
OPEN = ("This exact pair of cartoon lips opened wide in a big round shout, like saying aaah: a row of white upper teeth, a row "
        "of white lower teeth, a pink tongue and a dark red throat inside, the lips stretched round the opening. Keep the same "
        "red, the same glossy highlights, the same art style and the same size in the frame, no face, no eyes, no nose. %s.")


def _render(key, prompt, refs, seed):
    os.makedirs(RAW, exist_ok=True)
    raw = os.path.join(RAW, "%s_%d.png" % (key, seed))
    if os.path.exists(raw) and not FORCE:
        return Image.open(raw).convert("RGB")
    t0 = time.time()
    if DEV:
        imgs, _ = comfy.run(comfy.flux2_dev(prompt, seed, 1024, 1024, refs=refs, steps=8, guidance=4.0, turbo=True, prefix="88fits/" + key))
    else:
        imgs, _ = comfy.run(comfy.klein(prompt, seed, 1024, 1024, refs=refs, prefix="88fits/" + key))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  render %-18s seed %-6d %5.0fs" % (key, seed, time.time() - t0))
    if DEV:
        ga.log("  " + comfy.release_models())
    return img


def main():
    bg = ga.BG_GREEN
    closed = _render("fx_big_mouth", ga.styled(CLOSED, "Seen from the front, the whole mouth visible, nothing else in the frame, no shadow.", bg),
                     ga.ensure_anchor_uploaded(), 61)
    ref = [comfy.upload_pil(closed, "fx_big_mouth_ref.png")]
    opened = _render("fx_big_mouth_open", OPEN % bg, ref, 62)
    # both frames at one scale, taken from the open mouth (the bigger one), centred in the cell
    k_open = artkit.crop_alpha(artkit.punch(artkit.key_background(opened)))
    scale = CELL * 0.86 / max(k_open.width, k_open.height)
    frames = []
    for img in (closed, opened):
        cell_img, _ = ga.finish(img, CELL, 0.86, False, scale, 0.012, None, (60, 14, 24, 255))
        frames.append(cell_img)
    strip = Image.new("RGBA", (CELL * 2, CELL), (0, 0, 0, 0))
    for k, f in enumerate(frames):
        strip.alpha_composite(f, (k * CELL, 0))
    strip.save(OUT)
    ga.log("gen_mouth: wrote " + OUT)


if __name__ == "__main__":
    main()

"""2.5D props for Dry Gulch: cacti, rocks, bones, a dead tree, a signpost, painted in the sheet's anime style by the same
Flux.2 Klein server as the creatures (style anchor as reference), keyed, outlined thinly, muted a little so they sit
behind the characters instead of competing with them, and written as one PNG per prop plus a manifest the map reads.

  python tools/gen_props.py [--only id,id] [--force]

Output: game/art/sprites/props/<id>.png (cell x cell, feet on the floor) and game/art/sprites/props/props.json
  {"<id>": {"file": "<id>.png", "height": metres, "radius": collider metres (0 = walk through), "cell": px}}"""
import json
import os
import sys

from PIL import Image, ImageEnhance

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(REPO, "game", "art", "sprites", "props")

# id: (prompt, world height in metres, collider radius in metres, cell px, seed)
PROPS = {
    "saguaro_big": ("a tall green saguaro cactus with three thick upraised arms, ribbed, with small spines", 4.4, 0.55, 384, 101),
    "saguaro_small": ("a medium green saguaro cactus with one arm, ribbed, with small spines", 2.8, 0.45, 256, 102),
    "barrel_cactus": ("a fat round barrel cactus with curved spines and a ring of pink flowers on top", 1.1, 0.5, 192, 103),
    "prickly_pear": ("a prickly pear cactus cluster of flat green paddles with red fruit on the edges", 1.4, 0.5, 192, 104),
    "agave": ("a spiky blue-green agave plant with thick pointed leaves", 1.3, 0.5, 192, 105),
    "dead_shrub": ("a dry dead desert shrub of grey-brown twigs", 1.2, 0.0, 192, 106),
    "dead_tree": ("a gnarled dead desert tree with bare twisted branches and cracked grey bark", 4.2, 0.4, 384, 107),
    "rock_small": ("a small rounded sandstone rock, orange and tan with a few cracks", 0.8, 0.7, 128, 108),
    "rock_big": ("a big rounded sandstone rock, orange and tan with cracks and a flat top", 1.6, 1.4, 256, 109),
    "boulder": ("a huge sandstone boulder with layered orange and tan bands", 2.8, 2.3, 384, 110),
    "skull": ("a big bleached cow skull with long horns, half buried in sand", 0.9, 0.0, 192, 111),
    "skull_small": ("a small bleached skull lying on its side in sand", 0.5, 0.0, 128, 112),
    "bones": ("a scattered pile of bleached bones with a ribcage and a femur on sand", 0.7, 0.0, 192, 113),
    "signpost": ("a weathered wooden signpost with two crooked arrow boards nailed to it", 3.0, 0.25, 256, 114),
}

ONLY = None
for a in sys.argv[1:]:
    if a.startswith("--only="):
        ONLY = a.split("=", 1)[1].split(",")
FORCE = "--force" in sys.argv


def mute(img_rgba, amount=0.18):
    """Props sit behind the cast: a little less saturation and contrast than the creatures get."""
    rgb = img_rgba.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(1.0 - amount)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.0 - amount * 0.5)
    out = rgb.convert("RGBA")
    out.putalpha(img_rgba.getchannel("A"))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest_p = os.path.join(OUT, "props.json")
    manifest = json.load(open(manifest_p, encoding="utf-8")) if os.path.exists(manifest_p) else {}
    refs = ga.ensure_anchor_uploaded()
    for id_, (subject, height, radius, cell, seed) in PROPS.items():
        if ONLY and id_ not in ONLY:
            continue
        png = os.path.join(OUT, id_ + ".png")
        if os.path.exists(png) and not FORCE:
            manifest[id_] = {"file": id_ + ".png", "height": height, "radius": radius, "cell": cell}
            continue
        prompt = ga.styled("a desert prop for a game: " + subject, "Seen from the front at eye level, the whole object visible, its base resting on the floor line, nothing else in the frame.", ga.BG_GREEN)
        img, inf = ga.render("prop_" + id_, prompt, refs, {"subject": subject, "view": None, "subjects_max": 1}, seed)
        # a thinner, warmer outline than the creatures, and a touch of mute, so props read as scenery
        cell_img, _ = ga.finish(img, cell, 0.9, True, None, 0.007, None, (70, 46, 30, 230))
        mute(cell_img).save(png)
        manifest[id_] = {"file": id_ + ".png", "height": height, "radius": radius, "cell": cell}
        ga.log("prop %-14s %dpx  %.1f m  r %.2f  (%s)" % (id_, cell, height, radius, "ok" if not inf.get("qa", {}).get("problems") else "qa flagged"))
    json.dump(manifest, open(manifest_p, "w", encoding="utf-8", newline="\n"), indent=1)
    # a contact sheet for the review folder
    sheet = artkit.contact_sheet([Image.open(os.path.join(OUT, v["file"])) for v in manifest.values()], 7, 160)
    sheet.save(os.path.join(REPO, "tools", "dl", "review", "props.png"))
    ga.log("gen_props: %d props in %s" % (len(manifest), OUT))


if __name__ == "__main__":
    main()

"""2.5D props for Dry Gulch: cacti, rocks, bones, a dead tree, a signpost, painted one by one in the sheet's anime style
with the style anchor as reference, keyed off a screen that cannot swallow the prop's own colour (blue for greenery,
green for the blue agave), checked for holes and for faces (re-rolled on either), outlined thinly, muted a little so
they sit behind the characters, and written as one PNG per prop plus a manifest the map reads.

Model: `--dev` (the default for the shipped set) uses Flux.2 dev, the big model: it paints better, but with its 18 GB
text encoder it does not fit the server's 47 GB of RAM twice, so after every render the models are unloaded and, when
that does not give the RAM back, the ComfyUI service is restarted (comfy.release_models); a prop costs about five
minutes. `--klein` uses Flux.2 Klein 9B (20 s a render).

  python tools/gen_props.py [--only id,id] [--force] [--dev]

Output: game/art/sprites/props/<id>.png (cell x cell, base on the floor) and game/art/sprites/props/props.json
  {"<id>": {"file": "<id>.png", "height": metres, "radius": collider metres (0 = walk through), "cell": px}}
An entry's other keys are kept (pass 83: `shadow`, measured by tools/prop_shadows.py; the variants' `variant_of` and
`weight`, painted by tools/gen_prop_variants.py, which this table does not list)."""
import io
import json
import os
import sys
import time

from PIL import Image, ImageDraw, ImageEnhance

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(REPO, "game", "art", "sprites", "props")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_props")

NO_FACE = ", no face, no eyes, no mouth, not a character, just the object"
# id: (prompt, world height m, collider radius m (small: the hero should be able to stand behind it), cell px, seed, screen)
PROPS = {
    "saguaro_big": ("a tall green saguaro cactus with two thick upraised arms, ribbed, with small spines" + NO_FACE, 4.4, 0.22, 384, 11, "blue"),
    "saguaro_small": ("a medium green saguaro cactus with one short arm, ribbed, with small spines" + NO_FACE, 2.8, 0.19, 256, 12, "blue"),
    "barrel_cactus": ("a fat round green barrel cactus with curved yellow spines and a ring of small pink flowers on top" + NO_FACE, 1.1, 0.25, 192, 13, "blue"),
    "agave": ("a spiky blue-green agave plant with thick pointed leaves fanning out from the ground" + NO_FACE, 1.3, 0.0, 192, 15, "green"),   # radius 0 since pass 54: the hero walks through it
    "dead_shrub": ("a dry dead desert shrub of tangled grey-brown twigs" + NO_FACE, 1.2, 0.0, 192, 16, "blue"),
    "dead_tree": ("a gnarled dead desert tree with bare twisted branches and cracked grey bark" + NO_FACE, 4.2, 0.19, 384, 17, "blue"),
    "rock_small": ("a small rounded sandstone rock, orange and tan with a few cracks" + NO_FACE, 0.8, 0.22, 128, 18, "blue"),
    "rock_big": ("a big rounded sandstone rock, orange and tan with cracks and a flat top" + NO_FACE, 1.6, 0.37, 256, 19, "blue"),
    "boulder": ("a huge sandstone boulder with layered orange and tan bands" + NO_FACE, 2.8, 0.62, 384, 20, "blue"),
    "skull": ("a big bleached cow skull with long curved horns, half buried in sand" + NO_FACE, 0.9, 0.0, 192, 21, "blue"),
    "skull_small": ("a small bleached animal skull lying on its side in the sand" + NO_FACE, 0.5, 0.0, 128, 22, "blue"),
    "bones": ("a scattered pile of bleached bones with a ribcage and a long femur on sand" + NO_FACE, 0.7, 0.0, 192, 23, "blue"),
    "signpost": ("a weathered wooden signpost with two crooked arrow boards nailed to a post" + NO_FACE, 3.0, 0.12, 256, 24, "blue"),
    # trees and bushes
    "mesquite_tree": ("a wide low mesquite tree with a twisted trunk and a broad crown of small green leaves" + NO_FACE, 4.0, 0.25, 384, 31, "blue"),
    "joshua_tree": ("a tall joshua tree with a shaggy trunk and several branches ending in spiky green leaf balls" + NO_FACE, 4.6, 0.22, 384, 32, "blue"),
    "palo_verde": ("a slender palo verde tree with smooth green bark and a light airy crown of tiny leaves and yellow blossoms" + NO_FACE, 3.8, 0.19, 384, 33, "blue"),
    "desert_bush": ("a round dense desert bush of small dusty green leaves" + NO_FACE, 1.3, 0.0, 192, 34, "blue"),
    "creosote_bush": ("a sparse creosote bush of thin dark branches with tiny yellow-green leaves and small yellow flowers" + NO_FACE, 1.6, 0.0, 192, 35, "blue"),
    # pass 28: three more kinds of greenery (the oasis palms, and two for the green patches)
    "fan_palm": ("a tall desert fan palm tree with a slender rough trunk, a shaggy skirt of dead brown fronds hanging under a crown of big green fan-shaped leaves" + NO_FACE, 5.2, 0.2, 384, 36, "blue"),
    "ocotillo": ("an ocotillo plant: a spray of many long thin thorny whip-like grey-green stems fanning up from one point on the ground, each tipped with a bright red flower cluster" + NO_FACE, 3.2, 0.15, 256, 37, "blue"),
    "yucca": ("a yucca plant: a dense round ball of stiff sword-shaped blue-green leaves on a short trunk, with one tall central stalk of creamy white bell flowers" + NO_FACE, 2.6, 0.22, 256, 38, "blue"),
    # the structures, painted like the rest of the scenery (the map holds nothing in 3D any more)
    "st_healing_well": ("a small round stone well with a wooden roof and a bucket, cool blue water glowing inside" + NO_FACE, 2.4, 0.0, 256, 41, "green"),
    "st_loot_cache": ("a half-buried wooden treasure chest with brass corners and a padlock, gold coins spilling out" + NO_FACE, 1.6, 0.0, 192, 42, "blue"),
    "st_beacon": ("a tall glowing purple crystal shard standing on a small pile of rocks" + NO_FACE, 3.0, 0.0, 256, 43, "green"),
    "st_shop": ("a small travelling merchant stall with a striped red and white awning, a wooden counter and hanging wares" + NO_FACE, 2.6, 0.0, 256, 44, "green"),
    "st_war_drum": ("a big tribal war drum on a wooden stand with two crossed drumsticks and red tassels" + NO_FACE, 1.7, 0.0, 192, 45, "blue"),
    "st_dice_shrine": ("a small stone shrine with two giant carved dice on top, purple candles at its base" + NO_FACE, 2.0, 0.0, 256, 46, "blue"),
    # pass 48 (Garry): nothing on it that looks like it should move: no sparks, no lightning, no electricity
    "st_uber_magnet": ("a giant red and silver horseshoe magnet standing upright on a square grey stone plinth, solid painted metal, clean and still, nothing glowing, no sparks, no lightning, no electricity, no energy, no motion lines" + NO_FACE, 2.2, 0.0, 256, 48, "blue"),
    # the Strongbox (pass 33.1): a chest on a balloon, painted like every other structure
    "st_gold_bank": ("a small sturdy wooden treasure chest with dark iron bands, a gold lock and a round gold coin emblem on the front, closed, standing on the ground, and a big shiny red balloon tied to the top of its lid by a thin white string, the balloon floating straight up above the chest" + NO_FACE, 2.8, 0.0, 256, 50, "green"),
    # pass 35: the Teleport, a stone ring gate; its middle is left open (the game swirls the portal in the hole)
    "st_teleport": ("an ancient round teleport gate: one big upright ring of carved grey-brown stone blocks standing on a low stepped stone base, "
                    "small pale pink runes carved all around the ring, the inside of the ring completely empty and open so you can see straight "
                    "through the round hole" + NO_FACE, 3.2, 0.0, 256, 52, "green"),
    "st_hooded_figure": ("a tall mysterious figure standing perfectly still in a ragged dark violet hooded cloak that reaches the ground, the deep hood hiding the whole face in black shadow, hands hidden inside the long sleeves, a faint violet glow from inside the hood", 2.4, 0.0, 256, 48, "green"),
}
# the spent versions: an edit of the lit painting, so the shape stays and only the life goes out of it
OFF = {
    "st_healing_well": "the water gone, the well dry and dark inside, the bucket hanging still, no glow",
    "st_loot_cache": "the chest open and empty, the lid up, no coins, the wood dull",
    "st_beacon": "the crystal dark and unlit, dull grey-purple, no glow",
    "st_shop": "the stall shuttered, the awning rolled up, the counter bare, no wares",
    "st_war_drum": "the drum skin torn through, the sticks lying on the ground, the tassels limp",
    "st_dice_shrine": "the candles out, the dice greyed and cracked, the shrine dark",
    "st_uber_magnet": "the magnet dark, rusty and dull, still standing on the same square grey stone plinth, no sparks, no glow",
    "st_teleport": "the runes dark and dead, the stone dull grey and cracked, one block chipped, no glow at all, the middle of the ring still empty and open",
    "st_hooded_figure": "the figure gone: only the ragged dark violet cloak left lying empty in a heap on the ground, nobody inside it, no hood standing, no glow",
}
OFF_PROMPT = ("This exact object, spent and switched off: %s. Keep the same shape, size, position, viewpoint and art style; "
              "only the life has gone out of it. %s.")

ONLY = None
for a in sys.argv[1:]:
    if a.startswith("--only="):
        ONLY = a.split("=", 1)[1].split(",")
FORCE = "--force" in sys.argv
DEV = "--klein" not in sys.argv


def mute(img_rgba, amount=0.18):
    """Props sit behind the cast: a little less saturation and contrast than the creatures get."""
    rgb = img_rgba.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(1.0 - amount)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.0 - amount * 0.5)
    out = rgb.convert("RGBA")
    out.putalpha(img_rgba.getchannel("A"))
    return out


def hole_fraction(keyed_rgba):
    """Transparent pixels enclosed by the object (the keyer ate part of it), as a fraction of the object's area."""
    a = keyed_rgba.getchannel("A").point(lambda v: 255 if v > 127 else 0).convert("L")
    w, h = a.size
    # flood the outside with grey from every border pixel; what stays black inside is a hole
    padded = Image.new("L", (w + 2, h + 2), 0)
    padded.paste(a, (1, 1))
    ImageDraw.floodfill(padded, (0, 0), 128)
    px = padded.load()
    holes = 0
    solid = 0
    for y in range(1, h + 1):
        for x in range(1, w + 1):
            v = px[x, y]
            if v == 0:
                holes += 1
            elif v == 255:
                solid += 1
    return holes / max(solid, 1)


def has_face(img):
    r = ga.vision_json(img, "Look at this object. Does it have a face, eyes or a mouth drawn on it? Answer JSON only: {\"face\": true or false}", 60)
    return bool(r.get("face", False)) if isinstance(r, dict) else False


# twiggy things have real gaps between branches, which the enclosed-pixel check cannot tell from keyer holes
OPEN_CANOPY = {"dead_shrub", "mesquite_tree", "joshua_tree", "palo_verde", "desert_bush", "creosote_bush", "dead_tree", "fan_palm", "ocotillo", "yucca",
               "st_healing_well", "st_loot_cache", "st_beacon", "st_shop", "st_war_drum", "st_dice_shrine", "st_uber_magnet", "st_hooded_figure", "st_teleport"}


def render_prop(id_, subject, screen, seed, ref_img=None, prompt=None):
    """Up to three seeds: the first render with no holes and no face wins; else the best of them. With `ref_img` the
    render is an edit of that image (the spent structures are edits of the lit ones)."""
    os.makedirs(RAW, exist_ok=True)
    bg = ga.BG_BLUE if screen == "blue" else ga.BG_GREEN
    if prompt is None:
        prompt = ga.styled("a desert prop for a game: " + subject,
                           "Seen from the front at eye level, the whole object visible, its base resting on the floor line, no ground patch, "
                           "no cast shadow, nothing else in the frame.", bg)
    refs = ga.ensure_anchor_uploaded() if ref_img is None else [comfy.upload_pil(ref_img, id_ + "_ref.png")]
    best = None
    for attempt in range(3):
        s = seed + attempt * 977
        raw = os.path.join(RAW, "%s_%d.png" % (id_, s))
        if os.path.exists(raw) and not FORCE:
            img = Image.open(raw).convert("RGB")
        else:
            t0 = time.time()
            if DEV:
                imgs, _ = comfy.run(comfy.flux2_dev(prompt, s, 1024, 1024, refs=refs, steps=8, guidance=4.0, turbo=True, prefix="88fits/prop_" + id_))
            else:
                imgs, _ = comfy.run(comfy.klein(prompt, s, 1024, 1024, refs=refs, prefix="88fits/prop_" + id_))
            img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
            img.save(raw)
            ga.log("  render %-14s seed %-6d %5.0fs" % (id_, s, time.time() - t0))
            if DEV:
                ga.log("  " + comfy.release_models())
        keyed = artkit.punch(artkit.key_background(img))
        holes = hole_fraction(artkit.crop_alpha(keyed))
        face = has_face(img)
        score = (0 if face else 1, -holes)
        ga.log("  check  %-14s holes %.3f  face %s" % (id_, holes, face))
        if best is None or score > best[0]:
            best = (score, img, holes, face)
        if holes < (0.4 if id_.replace("_off", "") in OPEN_CANOPY else 0.004) and not face:
            break
    return best[1], best[2], best[3]


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest_p = os.path.join(OUT, "props.json")
    manifest = json.load(open(manifest_p, encoding="utf-8")) if os.path.exists(manifest_p) else {}
    for id_, (subject, height, radius, cell, seed, screen) in PROPS.items():
        # the entry's own extra keys stay (pass 49: "hidden" keeps a painting out of the scatter, "off" names a spent one)
        manifest[id_] = dict(manifest.get(id_, {}), **{"file": id_ + ".png", "height": height, "radius": radius, "cell": cell})
        if ONLY and id_ not in ONLY:
            continue
        png = os.path.join(OUT, id_ + ".png")
        if os.path.exists(png) and not FORCE:
            continue
        img, holes, face = render_prop(id_, subject, screen, seed)
        # a thinner, warmer outline than the creatures, and a touch of mute, so props read as scenery
        cell_img, _ = ga.finish(img, cell, 0.9, True, None, 0.007, None, (70, 46, 30, 230))
        mute(cell_img).save(png)
        ga.log("prop %-14s %dpx  %.1f m  r %.2f  holes %.3f  face %s" % (id_, cell, height, radius, holes, face))
        json.dump(manifest, open(manifest_p, "w", encoding="utf-8", newline="\n"), indent=1)
        if id_ in OFF:
            bg = ga.BG_BLUE if screen == "blue" else ga.BG_GREEN
            off_img, oh, of = render_prop(id_ + "_off", subject, screen, seed + 500, ref_img=img, prompt=OFF_PROMPT % (OFF[id_], bg))
            off_cell, _ = ga.finish(off_img, cell, 0.9, True, None, 0.007, None, (70, 46, 30, 230))
            mute(off_cell, 0.4).save(os.path.join(OUT, id_ + "_off.png"))
            manifest[id_]["off"] = id_ + "_off.png"
            ga.log("prop %-14s spent version  holes %.3f  face %s" % (id_, oh, of))
            json.dump(manifest, open(manifest_p, "w", encoding="utf-8", newline="\n"), indent=1)
    json.dump(manifest, open(manifest_p, "w", encoding="utf-8", newline="\n"), indent=1)
    sheet = artkit.contact_sheet([Image.open(os.path.join(OUT, v["file"])) for v in manifest.values() if os.path.exists(os.path.join(OUT, v["file"]))], 7, 160)
    sheet.save(os.path.join(REPO, "tools", "dl", "review", "props.png"))
    ga.log("gen_props: %d props in %s" % (len(manifest), OUT))


if __name__ == "__main__":
    main()

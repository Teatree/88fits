"""Recolour a finished sprite strip or icon frame by frame (pass 53, the Red Goblins): the same animation, the same
lines, only the hues inside the given ranges moved to another hue, so a creature's skin changes colour without a
single new render (Garry: "I want their skin to be red ... Otherwise same animation, same style, same everything").

    python tools/recolour_strip.py --src game/content/enemies/goblin/goblin_sprite_d.png \
        --dst game/content/enemies/red_goblin/red_goblin_sprite.png --ranges 60-130 --to 355 --sat 1.0
    python tools/recolour_strip.py --src ... --dst ... --ranges 60-130,140-170 --to 12 --sat 0.85 --min-sat 0.2

`--ranges` are hue intervals in degrees (several, comma-separated); a visible pixel inside one with saturation past
`--min-sat` (and at most `--max-sat`) takes hue `--to` at `--sat` times its saturation; value and alpha are kept, so
the shading and the outline survive (artkit.remap_hues). `--preview <png>` also writes the first, a middle and the
last frame of the source beside the result for a look. Works on a single icon too (one frame).
`--mode tint --to 222 --set-sat 0.55 --value 0.6 --min-sat 0.06 --max-sat 0.55 --min-val 0.3` (pass 54, the dark-blue
skeletons): a pale material turned dark and saturated (artkit.tint_range): the hue is set, the saturation set to
`--set-sat`, the value multiplied by `--value`; pixels darker than `--min-val` (lines, sockets, the outline) and anything
grey or cool (the knight's steel) are left alone.
`--mode lift --ranges 340-360,0-40 --to 40 --set-sat 0.1 --v-lo 0.55 --v-hi 1 --gamma 1 --min-sat 0.6 --min-val 0.3
--src-hi 1 --soft 0.04` (pass 107, the white beetle shells, the bright ants, the bone scorpion; artkit.lift_range): the
selected pixels take hue `--to`, saturation `--set-sat` (or `--sat` times their own when it is absent) and a value
remapped from [min-val, src-hi] onto [v-lo, v-hi]; anything darker than `--min-val` (lines, the outline) stays; the
edges of the selection are blended over +-`--soft`, the hue ranges' ends over `--hue-soft` degrees; `--to-dark <hue>`
gives the darkest shades their own hue (gold with amber shadows); `--mass 3 [--grow 5]` keeps only selected areas at
least 7 px thick (pixels of the hue, value and saturation >= `--mass-sat`, default 0.4 x min-sat), grown back
5 px (the shell, not the thin legs of the same red); `--keep-edge 4` leaves the figure's outer 4 px as they are (an
icon's grey outer stroke). Ranges wrap by listing two (340-360,0-40).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import artkit  # noqa: E402
from PIL import Image  # noqa: E402


def opt(name, default=None):
    for a in sys.argv[1:]:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
        if a == "--" + name:
            i = sys.argv.index(a)
            if i + 1 < len(sys.argv):
                return sys.argv[i + 1]
    return default


def main():
    src, dst = opt("src"), opt("dst")
    if not src or not dst:
        raise SystemExit(__doc__)
    ranges = [[float(v) for v in r.split("-")] for r in opt("ranges", "60-130").split(",") if "-" in r]
    to = float(opt("to", "355"))
    sat = float(opt("sat", "1.0"))
    min_sat = float(opt("min-sat", "0.2"))
    max_sat = float(opt("max-sat", "1.01"))
    img = Image.open(src).convert("RGBA")
    if opt("mode", "hue") == "lift":
        # pass 107: a material made lighter (white shells, bright ants, a bone scorpion); value remapped onto [v-lo, v-hi]
        ss = opt("set-sat")
        out = artkit.lift_range(img, ranges, to, None if ss is None else float(ss), sat, float(opt("v-lo", "0.5")),
                                float(opt("v-hi", "1.0")), float(opt("gamma", "1.0")), min_sat, max_sat,
                                float(opt("min-val", "0.0")), float(opt("src-hi", "1.0")), float(opt("soft", "0.04")),
                                float(opt("hue-soft", "0")), None if opt("to-dark") is None else float(opt("to-dark")),
                                int(opt("mass", "0")), None if opt("grow") is None else int(opt("grow")),
                                None if opt("mass-sat") is None else float(opt("mass-sat")), int(opt("keep-edge", "0")))
    elif opt("mode", "hue") == "tint":
        # pass 54: a pale material to a dark saturated one (the dark-blue skeletons); value is scaled, saturation set
        out = artkit.tint_range(img, ranges, to, float(opt("set-sat", "0.55")), float(opt("value", "0.6")), min_sat, max_sat,
                                float(opt("min-val", "0.3")))
    else:
        out = artkit.remap_hues(img, ranges, to, sat, min_sat, max_sat)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    out.save(dst)
    print("recolour_strip: %s -> %s (%dx%d, hues %s -> %.0f, sat x%.2f)" % (src, dst, out.width, out.height, ranges, to, sat))
    prev = opt("preview")
    if prev:
        cell = img.height
        n = max(img.width // cell, 1)
        picks = sorted(set([0, n // 2, n - 1]))
        sheet = Image.new("RGBA", (cell * len(picks) * 2, cell), (40, 40, 48, 255))
        for k, f in enumerate(picks):
            sheet.paste(img.crop((f * cell, 0, (f + 1) * cell, cell)), (k * 2 * cell, 0), img.crop((f * cell, 0, (f + 1) * cell, cell)))
            sheet.paste(out.crop((f * cell, 0, (f + 1) * cell, cell)), ((k * 2 + 1) * cell, 0), out.crop((f * cell, 0, (f + 1) * cell, cell)))
        sheet.save(prev)
        print("  preview: " + prev)


if __name__ == "__main__":
    main()

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
icon's grey outer stroke); `--max-val 0.6` (pass 127, the Dust Bunny's looks) leaves what is brighter as it is (white eyes on a
body with no hue to tell them apart by). Ranges wrap by listing two (340-360,0-40).
`--cells 18[,61]` (pass 122, the Blood Moon's cool looks): the pass runs on those frames of the strip grid alone (frame k at
`((k % cols) * cell, (k // cols) * cell)`, the cell `--cell-px` or the image's height, cols = width // cell), every other
pixel copied as it is: a creature's `hit` frame (idle + run + attack frames in) is a white-washed flash of the material whose
saturation falls under the strip pass's `--min-sat`, so it takes a second pass of its own with a lower one. A cell outside the
grid (the icon, one frame) is skipped with a note, so a look's passes apply to its strip and its icon alike, in turn.
Pass 131: `--preview-src <png>` names the picture the preview shows as "before" (a second pass reads the first pass's
result), `--preview-cells 18` adds frames to the preview; `apply_image(im, argv)` runs one pass on a picture in memory
(the Level Editor's preview before a job is queued: tools/level_editor/recolour_io.py).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import artkit  # noqa: E402
from PIL import Image  # noqa: E402


_ARGV = None   # pass 131: apply_image() reads a pass's flags from a list of its own instead of the command line


def opt(name, default=None):
    argv = sys.argv[1:] if _ARGV is None else _ARGV
    for i, a in enumerate(argv):
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
        if a == "--" + name:
            if i + 1 < len(argv):
                return argv[i + 1]
    return default


def apply_image(im, argv):
    """Pass 131 (the Level Editor's recolour preview): one pass's flags (a list as on the command line, without --src /
    --dst / --cells) applied to one RGBA picture in memory, by the same code a strip goes through."""
    global _ARGV
    saved = _ARGV
    _ARGV = [str(a) for a in argv]
    try:
        return _apply(im.convert("RGBA"))
    finally:
        _ARGV = saved


def _ranges():
    return [[float(v) for v in r.split("-")] for r in opt("ranges", "60-130").split(",") if "-" in r]


def _apply(im):
    ranges = _ranges()
    to = float(opt("to", "355"))
    sat = float(opt("sat", "1.0"))
    min_sat = float(opt("min-sat", "0.2"))
    max_sat = float(opt("max-sat", "1.01"))
    if opt("mode", "hue") == "lift":
        # pass 107: a material made lighter (white shells, bright ants, a bone scorpion); value remapped onto [v-lo, v-hi]
        ss = opt("set-sat")
        return artkit.lift_range(im, ranges, to, None if ss is None else float(ss), sat, float(opt("v-lo", "0.5")),
                                 float(opt("v-hi", "1.0")), float(opt("gamma", "1.0")), min_sat, max_sat,
                                 float(opt("min-val", "0.0")), float(opt("src-hi", "1.0")), float(opt("soft", "0.04")),
                                 float(opt("hue-soft", "0")), None if opt("to-dark") is None else float(opt("to-dark")),
                                 int(opt("mass", "0")), None if opt("grow") is None else int(opt("grow")),
                                 None if opt("mass-sat") is None else float(opt("mass-sat")), int(opt("keep-edge", "0")),
                                 float(opt("max-val", "1.01")))
    if opt("mode", "hue") == "tint":
        # pass 54: a pale material to a dark saturated one (the dark-blue skeletons); value is scaled, saturation set
        return artkit.tint_range(im, ranges, to, float(opt("set-sat", "0.55")), float(opt("value", "0.6")), min_sat, max_sat,
                                 float(opt("min-val", "0.3")))
    return artkit.remap_hues(im, ranges, to, sat, min_sat, max_sat)


def main():
    src, dst = opt("src"), opt("dst")
    if not src or not dst:
        raise SystemExit(__doc__)
    ranges = _ranges()
    to = float(opt("to", "355"))
    sat = float(opt("sat", "1.0"))
    img = Image.open(src).convert("RGBA")

    cells = [int(v) for v in opt("cells", "").split(",") if v.strip() != ""]
    if cells:
        # pass 122: the pass on these frames of the strip grid alone (a creature's hit frame), the rest copied as it is
        cell = int(opt("cell-px", str(img.height)))
        cols, rows = max(img.width // cell, 1), max(img.height // cell, 1)
        out = img.copy()
        for k in cells:
            if k < 0 or k >= cols * rows:
                print("recolour_strip: cell %d is outside the %dx%d grid of %s: skipped" % (k, cols, rows, src))
                continue
            x, y = (k % cols) * cell, (k // cols) * cell
            out.paste(_apply(img.crop((x, y, x + cell, y + cell))), (x, y))
    else:
        out = _apply(img)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    out.save(dst)
    print("recolour_strip: %s -> %s (%dx%d, hues %s -> %.0f, sat x%.2f%s)" % (src, dst, out.width, out.height, ranges, to, sat,
                                                                         (", cells %s" % cells) if cells else ""))
    prev = opt("preview")
    if prev:
        # pass 131: --preview-src <png> is the picture shown as "before" (a later pass reads the pass before it, the sheet
        # shows the look it all started from); --preview-cells 18,25 adds those frames to the sheet (a hit frame's pass)
        if opt("preview-src") and os.path.isfile(opt("preview-src")):
            before = Image.open(opt("preview-src")).convert("RGBA")
            if before.size == img.size:
                img = before
        cell = img.height
        n = max(img.width // cell, 1)
        picks = sorted(set([0, n // 2, n - 1] + [int(v) for v in opt("preview-cells", "").split(",") if v.strip().isdigit() and int(v) < n]))
        sheet = Image.new("RGBA", (cell * len(picks) * 2, cell), (40, 40, 48, 255))
        for k, f in enumerate(picks):
            sheet.paste(img.crop((f * cell, 0, (f + 1) * cell, cell)), (k * 2 * cell, 0), img.crop((f * cell, 0, (f + 1) * cell, cell)))
            sheet.paste(out.crop((f * cell, 0, (f + 1) * cell, cell)), ((k * 2 + 1) * cell, 0), out.crop((f * cell, 0, (f + 1) * cell, cell)))
        sheet.save(prev)
        print("  preview: " + prev)


if __name__ == "__main__":
    main()

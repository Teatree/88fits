"""Side by side: a render of the game's screen next to the Wanted mock it should match.

    python tools/wanted_compare.py <render.png> <mock name or path> [out.png] [--diff] [--crop=x,y,w,h]

The mock may be a name under design_handoff_88fits_wanted/screens (07-level-up). --diff adds a third panel: the
absolute difference, brightened, so misplaced edges stand out. --crop compares one region at full size.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCKS = os.path.join(REPO, "design_handoff_88fits_wanted", "screens")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    render = Image.open(args[0]).convert("RGB")
    mock_p = args[1] if os.path.exists(args[1]) else os.path.join(MOCKS, args[1] + ("" if args[1].endswith(".png") else ".png"))
    # the mocks are transparent where the world would be: over white, as the design tool showed them
    m = Image.open(mock_p).convert("RGBA")
    mock = Image.alpha_composite(Image.new("RGBA", m.size, (255, 255, 255, 255)), m).convert("RGB")
    out = args[2] if len(args) > 2 else os.path.splitext(args[0])[0] + "_vs.png"
    if render.size != mock.size:
        render = render.resize(mock.size)
    crop = next((f.split("=", 1)[1] for f in flags if f.startswith("--crop=")), None)
    scale = 0.5
    if crop:
        x, y, w, h = [int(v) for v in crop.split(",")]
        render = render.crop((x, y, x + w, y + h))
        mock = mock.crop((x, y, x + w, y + h))
        scale = 1.0 if w <= 700 else 700.0 / w
    panels = [render, mock]
    if "--diff" in flags:
        panels.append(ImageEnhance.Brightness(ImageChops.difference(render, mock)).enhance(2.5))
    w = int(panels[0].width * scale)
    h = int(panels[0].height * scale)
    sheet = Image.new("RGB", (w * len(panels) + 10 * (len(panels) - 1), h + 30), (30, 30, 30))
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(panels):
        sheet.paste(p.resize((w, h)), (i * (w + 10), 30))
        d.text((i * (w + 10) + 6, 8), ["game", "mock", "difference"][i], fill=(240, 240, 240))
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()

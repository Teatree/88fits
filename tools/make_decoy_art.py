"""Pass 69 (lane HERO): the art May's Inflatable May needs that is not painted.

- game/art/ui/decoy_question.png: the pink "?" that bobs over every creature the doll fooled (Alfa Slab One, pink with
  a dark plum outline and a small shine), drawn by core/shaders/decoy_mark.gdshader.
- game/content/characters/may/may_decoy.png (only when missing, or with --doll): a PLACEHOLDER doll until lane ART paints
  the real one (an inflatable vinyl May): her cheer frame (arms up, scarecrow-like) blown up sideways, washed pink, a
  vinyl shine and a nozzle. Core/systems/Decoy.gd sizes whatever painting is there by its opaque box.

    python tools/make_decoy_art.py [--doll]
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FONT = os.path.join(ROOT, "game", "ui", "fonts", "AlfaSlabOne-Regular.ttf")
MARK = os.path.join(ROOT, "game", "art", "ui", "decoy_question.png")
MAY = os.path.join(ROOT, "game", "content", "characters", "may")
DOLL = os.path.join(MAY, "may_decoy.png")
PINK = (255, 79, 174, 255)
PLUM = (59, 8, 40, 255)


def question_mark(size=128):
    big = size * 4
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    font = ImageFont.truetype(FONT, int(big * 0.82))
    d = ImageDraw.Draw(img)
    box = d.textbbox((0, 0), "?", font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    at = ((big - w) // 2 - box[0], (big - h) // 2 - box[1])
    stroke = int(big * 0.07)
    d.text(at, "?", font=font, fill=PINK, stroke_width=stroke, stroke_fill=PLUM)
    # a small shine on the hook's upper left
    shine = Image.new("L", (big, big), 0)
    ImageDraw.Draw(shine).ellipse((big * 0.30, big * 0.16, big * 0.46, big * 0.27), fill=150)
    shine = shine.filter(ImageFilter.GaussianBlur(big * 0.015))
    inner = Image.new("L", (big, big), 0)
    ImageDraw.Draw(inner).text(at, "?", font=font, fill=255)
    shine = ImageChops.multiply(shine, inner)
    img = Image.composite(Image.new("RGBA", (big, big), (255, 255, 255, 255)), img, shine)
    return img.resize((size, size), Image.LANCZOS)


def placeholder_doll():
    d_json = os.path.join(MAY, "may.json")
    import json
    d = json.load(open(d_json, encoding="utf-8"))
    code = d.get("variant") or ""
    entry = (d.get("variants") or {}).get(code) or {}
    strip = os.path.join(MAY, entry.get("sprite") or "may_sprite.png")
    anims = entry.get("anims") or d.get("anims") or {}
    cols = int(entry.get("strip_cols") or d.get("strip_cols") or 1)
    px = int(entry.get("frame_px") or d.get("frame_px") or 256)
    order = ["idle", "run", "turn", "hit", "die", "cheer"]
    k = sum(int(anims.get(n, 0)) for n in order[:5])  # the cheer frame: arms up, a scarecrow's stance
    im = Image.open(strip).convert("RGBA")
    fr = im.crop(((k % cols) * px, (k // cols) * px, (k % cols) * px + px, (k // cols) * px + px))
    fr = fr.crop(fr.getbbox())
    # blown up: wider and a touch shorter, rounder
    fr = fr.resize((int(fr.width * 1.28), int(fr.height * 0.94)), Image.LANCZOS)
    a = fr.split()[3]
    pink = Image.new("RGBA", fr.size, (255, 120, 196, 255))
    fr = Image.blend(fr, pink, 0.38)
    # the vinyl shine: a soft white streak down the left of the body
    shine = Image.new("L", fr.size, 0)
    ImageDraw.Draw(shine).ellipse((fr.width * 0.30, fr.height * 0.22, fr.width * 0.42, fr.height * 0.62), fill=120)
    shine = ImageChops.multiply(shine.filter(ImageFilter.GaussianBlur(fr.width * 0.03)), a)
    fr = Image.composite(Image.new("RGBA", fr.size, (255, 255, 255, 255)), fr, shine)
    fr.putalpha(a)
    out = Image.new("RGBA", (fr.width + 16, fr.height + 16), (0, 0, 0, 0))
    out.alpha_composite(fr, (8, 8))
    # the nozzle at the hip
    ImageDraw.Draw(out).ellipse((out.width * 0.62, out.height * 0.52, out.width * 0.62 + 9, out.height * 0.52 + 9), fill=(250, 235, 245, 255), outline=PLUM)
    return out


def main():
    os.makedirs(os.path.dirname(MARK), exist_ok=True)
    question_mark().save(MARK)
    print("wrote", MARK)
    if "--doll" in sys.argv or not os.path.exists(DOLL):
        placeholder_doll().save(DOLL)
        print("wrote placeholder", DOLL)


if __name__ == "__main__":
    main()

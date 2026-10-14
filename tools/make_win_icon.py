"""The Windows icon (pass 73, Garry: "Can you make an icon for the PC build"): game/icon.ico with every size Windows asks
for, made from the app icon game/icon.png (the hat in the sand the phone shows).

Godot's own conversion shrank the whole 1024 px picture into every size, so at 16-48 px (Explorer's lists, the taskbar,
the title bar) the hat was a brown speck on a sand square. Here each size is framed for its size:
  96, 128, 256 px   the whole picture, as on the phone
  40, 48, 64 px     closer, the hat about two thirds of the tile
  16, 20, 24, 32 px the hat nearly filling the tile, sharpened a little
with rounded corners (transparent outside). Sizes under 256 are stored as 32-bit BMP entries (every Windows reads
them), 256 as PNG (the usual layout).

Godot's Windows export embeds the file in 88fits.exe (export_presets.cfg, "Windows Desktop": application/icon); the
running game's window and taskbar use it once application/config/windows_native_icon names it (project.godot).

  python tools/make_win_icon.py [--src game/icon.png] [--out game/icon.ico] [--preview sheet.png] [--if-stale]

--if-stale writes only when the .ico is missing or older than the picture or this script (ship.sh runs it so).
"""
import argparse
import io
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
# the hat in the 1024 px picture (its dark pixels' box, measured in pass 73); the crops are centred on it
HAT_BOX = (244, 372, 779, 702)
# how much of the tile's width the hat takes at each band of sizes (None = the whole picture)
FILL = {16: 0.88, 20: 0.88, 24: 0.86, 32: 0.84, 40: 0.70, 48: 0.68, 64: 0.66, 96: None, 128: None, 256: None}
CORNER = 0.14       # corner radius, a fraction of the side
SUPER = 4           # the corner mask drawn this much larger, then shrunk (smooth edges)


def crop_for(src: Image.Image, size: int) -> Image.Image:
    fill = FILL.get(size)
    w, h = src.size
    if fill is None:
        return src
    k = w / 1024.0
    x0, y0, x1, y1 = [v * k for v in HAT_BOX]
    side = (x1 - x0) / fill
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    left = min(max(cx - side * 0.5, 0.0), w - side)
    top = min(max(cy - side * 0.5, 0.0), h - side)
    return src.crop((round(left), round(top), round(left + side), round(top + side)))


def frame(src: Image.Image, size: int) -> Image.Image:
    im = crop_for(src, size).convert("RGBA").resize((size, size), Image.LANCZOS)
    if size <= 32:
        im = im.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=1))
    # rounded corners: the mask drawn large and shrunk
    m = Image.new("L", (size * SUPER, size * SUPER), 0)
    r = max(1.0, size * CORNER) * SUPER
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size * SUPER - 1, size * SUPER - 1), radius=r, fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    a = im.getchannel("A")
    im.putalpha(Image.composite(a, Image.new("L", a.size, 0), m))
    return im


def bmp_entry(im: Image.Image) -> bytes:
    """A 32-bit DIB icon entry: BITMAPINFOHEADER (height doubled), BGRA rows bottom-up, then the 1-bit AND mask."""
    w, h = im.size
    header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    px = im.convert("RGBA").tobytes()
    rows = []
    for y in range(h - 1, -1, -1):
        row = bytearray()
        for x in range(w):
            i = (y * w + x) * 4
            r, g, b, a = px[i], px[i + 1], px[i + 2], px[i + 3]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    stride = ((w + 31) // 32) * 4
    mask = []
    for y in range(h - 1, -1, -1):
        bits = bytearray(stride)
        for x in range(w):
            if px[(y * w + x) * 4 + 3] == 0:
                bits[x // 8] |= 0x80 >> (x % 8)
        mask.append(bytes(bits))
    return header + b"".join(rows) + b"".join(mask)


def png_entry(im: Image.Image) -> bytes:
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def write_ico(images: list, path: str) -> None:
    blobs = [png_entry(im) if im.size[0] >= 256 else bmp_entry(im) for im in images]
    out = bytearray(struct.pack("<HHH", 0, 1, len(images)))
    offset = 6 + 16 * len(images)
    for im, blob in zip(images, blobs):
        w, h = im.size
        out += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    for blob in blobs:
        out += blob
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, path)


def preview(images: list, path: str) -> None:
    """Every size at 1:1 on white and on a dark taskbar grey, then each enlarged x4 (pixels kept) to judge."""
    big = sum(im.size[0] for im in images) + 10 * (len(images) + 1)
    sheet = Image.new("RGBA", (big, 2 * 266 + 4 * 64 + 30), (255, 255, 255, 255))
    x = 10
    for im in images:
        sheet.alpha_composite(im, (x, 5))
        x += im.size[0] + 10
    dark = Image.new("RGBA", (big, 266), (32, 32, 36, 255))
    x = 10
    for im in images:
        dark.alpha_composite(im, (x, 5))
        x += im.size[0] + 10
    sheet.alpha_composite(dark, (0, 266))
    x = 10
    for im in images:
        if im.size[0] <= 48:
            z = im.resize((im.size[0] * 4, im.size[1] * 4), Image.NEAREST)
            sheet.alpha_composite(z, (x, 2 * 266 + 10))
            x += z.size[0] + 10
    sheet.save(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(ROOT, "game", "icon.png"))
    ap.add_argument("--out", default=os.path.join(ROOT, "game", "icon.ico"))
    ap.add_argument("--preview", default="")
    ap.add_argument("--if-stale", action="store_true")
    a = ap.parse_args()
    if a.if_stale and os.path.exists(a.out):
        newest = max(os.path.getmtime(a.src), os.path.getmtime(os.path.abspath(__file__)))
        if os.path.getmtime(a.out) >= newest:
            print("make_win_icon: %s is up to date" % os.path.relpath(a.out, ROOT))
            return 0
    src = Image.open(a.src).convert("RGBA")
    images = [frame(src, s) for s in SIZES]
    write_ico(images, a.out)
    if a.preview:
        preview(images, a.preview)
    print("make_win_icon: %s, %d sizes (%s), %d bytes" % (os.path.relpath(a.out, ROOT), len(images),
          ", ".join(str(s) for s in SIZES), os.path.getsize(a.out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

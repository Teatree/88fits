"""Assembles docs/design/design-bible.html from docs/design/src/part*.html.

  python tools/make_bible.py [--shots=<dir>]

--shots converts the PNG captures in <dir> (from screenshot_run.gd) to WebP in docs/design/img/ first. The cast,
hero-cycle and icon sheets are always rebuilt from the content folders. {{IMG:name|alt}} inlines img/<name>.webp,
{{CSS}} the stylesheet, {{SOUND_ROWS}} the sound table from src/sounds.json filtered by the live soundmap."""
import base64
import glob
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = "docs/design/src"
IMG = "docs/design/img"
CONTENT = "game/content"
SHOTS = None
for a in sys.argv[1:]:
    if a.startswith("--shots="):
        SHOTS = a.split("=", 1)[1]


def to_webp(png, name, quality=82):
    im = Image.open(png).convert("RGB")
    im.save(os.path.join(IMG, name + ".webp"), "WEBP", quality=quality, method=6)


def uri(name):
    p = os.path.join(IMG, name + ".webp")
    return "data:image/webp;base64," + base64.b64encode(open(p, "rb").read()).decode("ascii")


def font(size):
    for cand in ("game/ui/fonts/Baloo2.ttf", "C:/Windows/Fonts/segoeui.ttf"):
        if os.path.exists(cand):
            return ImageFont.truetype(cand, size)
    return ImageFont.load_default()


ENEMY_ORDER = ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
CHAR_ORDER = ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]


def strip_frames(folder, id_):
    d = json.load(open(os.path.join(folder, id_ + ".json"), encoding="utf-8"))
    im = Image.open(os.path.join(folder, id_ + "_sprite.png")).convert("RGBA")
    cell = int(d.get("frame_px", 128))
    cols = int(d.get("strip_cols", im.width // cell))
    order = ENEMY_ORDER if "attack" in d["anims"] else CHAR_ORDER
    off = {}
    n = 0
    for k in order:
        off[k] = n
        n += int(d["anims"].get(k, 0))

    def frame(i):
        x = (i % cols) * cell
        y = (i // cols) * cell
        return im.crop((x, y, x + cell, y + cell))
    return d, cell, off, frame


def stack(rows, name):
    W = max(r.width for r in rows)
    out = Image.new("RGB", (W, sum(r.height for r in rows)), (26, 24, 34))
    y = 0
    for r in rows:
        out.paste(r, (0, y), r)
        y += r.height
    out.save(os.path.join(IMG, name + ".webp"), "WEBP", quality=84, method=6)


def cast_sheet():
    """Icon + six walk frames per desert creature, the boss last."""
    ids = [("enemies", "goblin"), ("enemies", "goblin_runt"), ("enemies", "fire_ant"), ("enemies", "roadrunner"), ("enemies", "spit_cactus"),
           ("enemies", "dust_mummy"), ("enemies", "bull_beetle"), ("enemies", "dune_scorpion"), ("bosses", "tumbleweed_king")]
    H = 150
    rows = []
    f = font(22)
    f2 = font(17)
    for t, id_ in ids:
        folder = os.path.join(CONTENT, t, id_)
        if not os.path.exists(os.path.join(folder, id_ + "_sprite.png")):
            continue
        d, cell, off, frame = strip_frames(folder, id_)
        icon = Image.open(os.path.join(folder, id_ + "_icon.png")).convert("RGBA").resize((H, H), Image.LANCZOS)
        n = int(d["anims"].get("run", 0))
        picks = [off["run"] + int(k * n / 6) for k in range(6)] if n else []
        row = Image.new("RGBA", (H + 20 + 6 * (H + 6) + 240, H + 10), (26, 24, 34, 255))
        row.paste(icon, (0, 5), icon)
        for k, i in enumerate(picks):
            fr = frame(i).resize((H, H), Image.LANCZOS)
            row.paste(fr, (H + 20 + k * (H + 6), 5), fr)
        dr = ImageDraw.Draw(row)
        x = H + 20 + 6 * (H + 6) + 14
        dr.text((x, H // 2 - 26), d["name"], fill=(240, 236, 248, 255), font=f)
        dr.text((x, H // 2 + 4), "%s / %s" % (d.get("archetype", ""), d.get("brain", "")), fill=(135, 127, 158, 255), font=f2)
        rows.append(row)
    if rows:
        stack(rows, "cast")


def hero_cycles():
    """Astro: five views x eight of the 24 run frames, then the nine-frame hit reaction."""
    folder = os.path.join(CONTENT, "characters", "astro")
    if not os.path.exists(os.path.join(folder, "astro_sprite.png")):
        return
    d, cell, off, frame = strip_frames(folder, "astro")
    S = 128
    views = [("run", "back"), ("run_bd", "back-diagonal"), ("run_s", "side"), ("run_fd", "front-diagonal"), ("run_f", "front")]
    f = font(18)
    rows = []
    for key, label in views:
        n = int(d["anims"].get(key, 0))
        row = Image.new("RGBA", (150 + 8 * (S + 4), S + 6), (26, 24, 34, 255))
        ImageDraw.Draw(row).text((8, S // 2 - 10), label, fill=(181, 174, 200, 255), font=f)
        for k in range(8):
            fr = frame(off[key] + int(k * n / 8)).resize((S, S), Image.LANCZOS)
            row.paste(fr, (150 + k * (S + 4), 3), fr)
        rows.append(row)
    n = int(d["anims"].get("hit_f", 0))
    row = Image.new("RGBA", (150 + 9 * (S + 4), S + 6), (26, 24, 34, 255))
    ImageDraw.Draw(row).text((8, S // 2 - 10), "hit (front)", fill=(255, 133, 144, 255), font=f)
    for k in range(n):
        fr = frame(off["hit_f"] + k).resize((S, S), Image.LANCZOS)
        row.paste(fr, (150 + k * (S + 4), 3), fr)
    rows.append(row)
    stack(rows, "hero_cycles")


def icon_sheet():
    icons = sorted(glob.glob(os.path.join(CONTENT, "*", "*", "*_icon.png")))
    S = 96
    cols = 10
    rows = (len(icons) + cols - 1) // cols
    out = Image.new("RGB", (cols * (S + 8) + 8, rows * (S + 8) + 8), (26, 24, 34))
    for k, p in enumerate(icons):
        im = Image.open(p).convert("RGBA").resize((S, S), Image.LANCZOS)
        out.paste(im, (8 + (k % cols) * (S + 8), 8 + (k // cols) * (S + 8)), im)
    out.save(os.path.join(IMG, "icons.webp"), "WEBP", quality=84, method=6)


def fire_gif(shots):
    """The fire capture sequence (screenshot_run's fire_seq_NN.png) cropped to the pack, as a looping gif."""
    frames = sorted(glob.glob(os.path.join(shots, "fire_seq_*.png"))) if shots else []
    if not frames:
        return
    ims = [Image.open(f).convert("RGB").crop((300, 560, 900, 1160)).resize((300, 300), Image.LANCZOS) for f in frames[::2]]
    ims = [im.quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for im in ims]
    ims[0].save(os.path.join(IMG, "fire.gif"), save_all=True, append_images=ims[1:], duration=200, loop=0, optimize=True)


def props_sheet():
    """The painted scenery with labels, from art/sprites/props/props.json."""
    mp = os.path.join("game", "art", "sprites", "props", "props.json")
    if not os.path.exists(mp):
        return
    man = json.load(open(mp, encoding="utf-8"))
    ids = list(man.keys())
    S = 150
    cols = 7
    rows = (len(ids) + cols - 1) // cols
    out = Image.new("RGB", (cols * (S + 12) + 12, rows * (S + 36) + 12), (26, 24, 34))
    f = font(15)
    for k, id_ in enumerate(ids):
        im = Image.open(os.path.join("game", "art", "sprites", "props", man[id_]["file"])).convert("RGBA").resize((S, S), Image.LANCZOS)
        x, y = 12 + (k % cols) * (S + 12), 12 + (k // cols) * (S + 36)
        out.paste(im, (x, y), im)
        ImageDraw.Draw(out).text((x + 4, y + S + 4), "%s  %.1f m" % (id_, man[id_]["height"]), fill=(181, 174, 200), font=f)
    out.save(os.path.join(IMG, "props.webp"), "WEBP", quality=84, method=6)


def sound_rows():
    live = json.load(open(os.path.join(CONTENT, "sounds", "soundmap.json"), encoding="utf-8"))["sounds"]
    rows = json.load(open(os.path.join(SRC, "sounds.json"), encoding="utf-8"))
    out = []
    grp = None
    for r in rows:
        if r["id"] not in live:
            continue
        if r["group"] != grp:
            grp = r["group"]
            out.append('      <tr class="grp"><td colspan="3">%s</td></tr>' % grp)
        out.append('      <tr><td class="id">%s</td><td>%s</td><td>%s</td></tr>' % (r["id"], r["trigger"], r["prompt"]))
    return "\n".join(out)


def main():
    os.makedirs(IMG, exist_ok=True)
    if SHOTS:
        for png in sorted(glob.glob(os.path.join(SHOTS, "[0-9][0-9]*.png"))):
            # only the numbered captures; the fire_seq frames go through fire_gif and collages stay in the scratchpad
            to_webp(png, os.path.splitext(os.path.basename(png))[0])
            print("shot", os.path.basename(png))
    fire_gif(SHOTS)
    cast_sheet()
    hero_cycles()
    icon_sheet()
    props_sheet()
    html = "".join(open(os.path.join(SRC, "part%d.html" % k), encoding="utf-8").read() for k in range(1, 5))
    html = html.replace("{{CSS}}", open(os.path.join(SRC, "bible.css"), encoding="utf-8").read())
    html = html.replace("{{SOUND_ROWS}}", sound_rows())
    missing = []

    def img(m):
        name, alt = m.group(1), m.group(2)
        if not os.path.exists(os.path.join(IMG, name + ".webp")):
            missing.append(name)
            return '<img class="shot" alt="%s (capture missing)">' % alt
        return '<img class="shot" src="%s" alt="%s">' % (uri(name), alt)
    html = re.sub(r"\{\{IMG:([^|}]+)\|([^}]*)\}\}", img, html)

    def gif(m):
        name, alt = m.group(1), m.group(2)
        p = os.path.join(IMG, name + ".gif")
        if not os.path.exists(p):
            missing.append(name)
            return '<img alt="%s (capture missing)">' % alt
        return '<img src="data:image/gif;base64,%s" alt="%s" style="width:360px;max-width:100%%;height:auto;border-radius:12px">' % (base64.b64encode(open(p, "rb").read()).decode("ascii"), alt)
    html = re.sub(r"\{\{GIF:([^|}]+)\|([^}]*)\}\}", gif, html)
    open("docs/design/design-bible.html", "w", encoding="utf-8", newline="\n").write(html)
    print("bible written, %d KB, missing images: %s" % (len(html.encode("utf-8")) // 1024, missing or "none"))


if __name__ == "__main__":
    main()

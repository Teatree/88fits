"""The pictures for the design bible's art pipeline section (15b, "How the art is made"): the Goblin, the Drifter, the
Big Mouth, the Tommy Gun and the shorter examples, step by step, cut from the files the pipeline itself left behind:
the raw renders (tools/dl/ai_raw_anime/, ai_raw_props/, icon_variants/), the clips (tools/dl/ai_anim/), the pose
drivers (tools/dl/drivers/), the finished strips and icons (game/content/, game/art/) and three in-game captures from
the debug arena in tools/dl/pipeline_caps/ (close_a/close_b: the Drifter with the Tommy Gun and the Big Mouth among goblins,
retaken in pass 33.9 with the new goblin; extra_a: the Sun
Prophet and a skeleton). The cut-out steps are made again here with tools/artkit.py, the same code the pipeline runs.

  python tools/make_pipeline_figs.py        then  python tools/make_bible.py

Writes docs/design/img/ap_*.webp (ap_gob_walk and ap_dr_run are animated). tools/dl is not in git, so the pictures are
made once and kept with the bible's other images."""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import artkit  # noqa: E402

IMG = os.path.join(REPO, "docs", "design", "img")
DL = os.path.join(REPO, "tools", "dl")
RAW = os.path.join(DL, "ai_raw_anime")
PROPS_RAW = os.path.join(DL, "ai_raw_props")
ANIM = os.path.join(DL, "ai_anim")
DRIVERS = os.path.join(DL, "drivers")
CAPS = os.path.join(DL, "pipeline_caps")
CONTENT = os.path.join(REPO, "game", "content")

# the bible's palette (docs/design/src/bible.css)
BG2 = (26, 24, 34)
BG3 = (36, 31, 49)
LINE = (67, 59, 92)
INK = (240, 236, 248)
INK2 = (181, 174, 200)
INK3 = (135, 127, 158)
ACCENT = (255, 177, 59)
GOOD = (70, 211, 154)
DANGER = (238, 74, 92)

ENEMY_ORDER = artkit.ENEMY_ORDER
CHAR_ORDER = artkit.CHAR_ORDER


def font(size):
    return ImageFont.truetype(os.path.join(REPO, "game", "ui", "fonts", "Baloo2.ttf"), size)


def save(img, name, q=80):
    img.convert("RGB").save(os.path.join(IMG, name + ".webp"), "WEBP", quality=q, method=6)
    print("wrote", name, "%.0f KB" % (os.path.getsize(os.path.join(IMG, name + ".webp")) / 1024.0))


def panel(w, h, bg=BG3):
    return Image.new("RGBA", (w, h), bg + (255,))


def fit(img, w, h, bg=BG3, pad=0):
    """`img` scaled to fit w x h (keeping its shape) and centred on `bg`."""
    im = img.convert("RGBA")
    s = min((w - 2 * pad) / im.width, (h - 2 * pad) / im.height)
    small = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = panel(w, h, bg)
    out.alpha_composite(small, ((w - small.width) // 2, (h - small.height) // 2))
    return out


def label(img, text, at=(10, 8), size=22, fill=INK, shade=True):
    d = ImageDraw.Draw(img)
    f = font(size)
    if shade:
        x0, y0, x1, y1 = d.textbbox(at, text, font=f)
        pad = 5
        over = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(over).rounded_rectangle((x0 - pad, y0 - pad + 2, x1 + pad, y1 + pad), 8, fill=(18, 17, 24, 190))
        img.alpha_composite(over)
    d.text(at, text, font=f, fill=fill)
    return img


def row(images, cell_w, cell_h, gap=8, bg=BG2, cell_bg=BG3, labels=None, lsize=20):
    out = panel(len(images) * cell_w + (len(images) - 1) * gap, cell_h, bg)
    for k, im in enumerate(images):
        c = fit(im, cell_w, cell_h, cell_bg, 4)
        if labels:
            # bottom left: the page puts each card's step number over the top left corner
            label(c, labels[k], (8, cell_h - lsize - 12), lsize)
        out.alpha_composite(c, (k * (cell_w + gap), 0))
    return out


def stack(rows_, gap=8, bg=BG2):
    w = max(r.width for r in rows_)
    out = panel(w, sum(r.height for r in rows_) + gap * (len(rows_) - 1), bg)
    y = 0
    for r in rows_:
        out.alpha_composite(r, ((w - r.width) // 2, y))
        y += r.height + gap
    return out


def raw(name, folder=RAW):
    return Image.open(os.path.join(folder, name + ".png")).convert("RGB")


def cut(img_rgb, cell, frac=0.02, color=(14, 8, 12, 255), fill=0.88):
    """The pipeline's own finishing on a still: key the screen, lift contrast, fit the cell, outline."""
    keyed = artkit.punch(artkit.key_background(img_rgb))
    canvas, _ = artkit.fit_cell(keyed, cell, fill, True)
    return artkit.add_outline(canvas, max(1, int(round(cell * frac))), color)


def strip_cells(kind, id_, order):
    """Every cell of a finished strip, by animation name."""
    folder = os.path.join(CONTENT, kind, id_)
    d = json.load(open(os.path.join(folder, id_ + ".json"), encoding="utf-8"))
    st = Image.open(os.path.join(folder, d.get("sprite", id_ + "_sprite.png"))).convert("RGBA")
    cell = int(d.get("frame_px", 128))
    cols = int(d.get("strip_cols", 0)) or st.width // cell
    out, k = {}, 0
    for name in order:
        n = int(d.get("anims", {}).get(name, 0))
        frames = []
        for _ in range(n):
            x, y = (k % cols) * cell, (k // cols) * cell
            frames.append(st.crop((x, y, x + cell, y + cell)))
            k += 1
        if frames:
            out[name] = frames
    return out


def checklist(img, items, w=360):
    """A render with the vision model's grade on it: one line per check, a tick or a cross."""
    c = fit(img, w, w, BG3)
    over = Image.new("RGBA", c.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    f = font(19)
    lh = 27
    h = lh * len(items) + 14
    d.rounded_rectangle((10, w - h - 10, w - 10, w - 10), 10, fill=(18, 17, 24, 215))
    y = w - h - 3
    for text, ok in items:
        col = GOOD if ok else DANGER
        cx, cy = 28, y + 13
        d.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=col + (255,))
        if ok:
            d.line([(cx - 5, cy), (cx - 1, cy + 4), (cx + 5, cy - 4)], fill=(18, 17, 24, 255), width=3)
        else:
            d.line([(cx - 4, cy - 4), (cx + 4, cy + 4)], fill=(18, 17, 24, 255), width=3)
            d.line([(cx - 4, cy + 4), (cx + 4, cy - 4)], fill=(18, 17, 24, 255), width=3)
        d.text((46, y), text, font=f, fill=INK + (255,))
        y += lh
    c.alpha_composite(over)
    return c


def crop_cap(name, box, w, h=None):
    im = Image.open(os.path.join(CAPS, name + ".png")).convert("RGBA").crop(box)
    if h is None:
        h = int(w * im.height / im.width)
    return im.resize((w, h), Image.LANCZOS)


def anim_webp(frames, name, fps, q=78):
    frames = [f.convert("RGB") for f in frames]
    frames[0].save(os.path.join(IMG, name + ".webp"), "WEBP", save_all=True, append_images=frames[1:], duration=int(round(1000.0 / fps)),
                   loop=0, quality=q, method=6)
    print("wrote", name, "(animated, %d frames) %.0f KB" % (len(frames), os.path.getsize(os.path.join(IMG, name + ".webp")) / 1024.0))


S = 360      # a card's picture
W2 = 736     # a wide card's picture (two cards and the gap)


def overlay_driver(still_rgb, driver_dir, k=0, S=640):
    """A pose driver frame drawn over the painting it animates, both at the height the video model gets them: the
    drivers put every figure's head top at 0.214 of the frame and its ankles near 0.866 (pose_driver FILL 0.72, seen
    25 degrees from above), and the painting goes in head top to soles, its ankles 0.932 of the way down (the goblin)."""
    meta = json.load(open(os.path.join(driver_dir, "poses.json"), encoding="utf-8"))
    pts = [(u * S, v * S) for u, v, vis in meta["frames"][k]["body"]]
    keyed = artkit.crop_alpha(artkit.key_background(still_rgb, 0.05, 0.45))
    top_y, ank_y = 0.214 * S, max(pts[10][1], pts[13][1])
    h = (ank_y - top_y) / 0.932
    sc = h / keyed.height
    small = keyed.resize((int(keyed.width * sc), int(keyed.height * sc)), Image.LANCZOS)
    cx = (pts[8][0] + pts[11][0]) / 2
    canvas = panel(S, S, BG3)
    canvas.alpha_composite(small, (int(cx - small.width / 2), int(top_y)))
    drv = Image.open(os.path.join(driver_dir, "driver_%02d.png" % k)).convert("RGBA")
    drv.putalpha(drv.convert("L").point(lambda v: 255 if v > 20 else 0))
    canvas.alpha_composite(drv)
    return canvas


def goblin():
    # pass 33.9: six fronts, one kept by eye (the vision model passed all six, the four-eared one included)
    picks = (("a tail", 0), ("four ears", 1), ("fine", 2), ("horns", 3), ("fine", 4), ("kept", 5))
    ims = [raw("goblin_front_c%d" % k).crop((112, 60, 912, 1000)) for _, k in picks]
    save(stack([row(ims[:3], 240, 282, 8, BG2, BG3, [t for t, _ in picks[:3]], 18),
                row(ims[3:], 240, 282, 8, BG2, BG3, [t for t, _ in picks[3:]], 18)], 8), "ap_gob_picks")
    q = json.load(open(os.path.join(RAW, "goblin_front.json"), encoding="utf-8"))["qa"]
    save(checklist(raw("goblin_front"), [("one subject", q["subjects"] == 1), ("flat background", q["background"] == "flat"),
                                         ("nothing cut off", not q["cropped"]), ("front view", q["view"] == "front"),
                                         ("it is a goblin", bool(q["matches"]))]), "ap_gob_qa")
    save(fit(raw("goblin_back"), S, S), "ap_gob_back")
    save(fit(cut(raw("goblin_front"), 320), S, S), "ap_gob_cut")
    save(fit(raw("goblin_dead"), S, S), "ap_gob_dead")
    # the skeleton: Mixamo's orc as it comes, and fitted to the goblin (pose_driver.py body=...)
    front = raw("goblin_front")
    both = [overlay_driver(front, os.path.join(DRIVERS, d, "front")).crop((120, 100, 520, 600)) for d in ("orc_walk", "orc_walk_goblin")]
    save(row(both, 364, 455, 8, BG2, BG3, ["Mixamo's orc", "fitted to the goblin"], 19), "ap_gob_fit")
    # the walk on it: fitted stick frames above, the painted frames Wan Animate made from them below
    clip = os.path.join(ANIM, "goblin_pose_f")
    ks = [0, 3, 6, 9]
    top = [Image.open(os.path.join(DRIVERS, "orc_walk_goblin", "front", "driver_%02d.png" % k)).convert("RGB").crop((140, 100, 500, 600)) for k in ks]
    bot = [Image.open(os.path.join(clip, "out_%02d.png" % k)).convert("RGBA") for k in ks]
    save(stack([row(top, 176, 200, 8, BG2, (0, 0, 0), ["frame %d" % (k + 1) for k in ks], 17), row(bot, 176, 200, 8)]), "ap_gob_animate")
    cells = strip_cells("enemies", "goblin", ENEMY_ORDER)
    # the fall: the eight die cells the game plays, from the first-last-frame clip
    die = cells["die"]
    save(stack([row(die[:4], 176, 176, 8), row(die[4:], 176, 176, 8)], 8), "ap_gob_fall")
    rows_ = []
    for names, title in ((["idle"], "idle 4"), (["run"], "walk 12 (front)"), (["attack", "hit"], "attack 2 · hit 1"), (["die"], "die 8"),
                         (["run_b"], "walk 12 (back)"), (["idle_b"], "idle 4 (back)")):
        fs = [f for n in names for f in cells.get(n, [])]
        r = panel(W2, 64, BG2)
        label(r, title, (4, 18), 19, INK2, False)
        x = 200
        for f in fs:
            r.alpha_composite(f.resize((52, 52), Image.LANCZOS), (x, 6))
            x += 44
        rows_.append(r)
    save(stack([panel(W2, 26, BG2)] + rows_, 4), "ap_gob_strip")
    save(crop_cap("close_a", (0, 425, 585, 640), W2), "ap_gob_game")
    # the finished walk, front and back, and the fall, at the game's rates (walk 15 fps; the fall 12 fps, then held)
    frames = []
    for k in range(24):
        c = panel(3 * 240 + 16, 240, BG2)
        for j, name in enumerate(("run", "run_b")):
            c.alpha_composite(fit(cells[name][k % 12].resize((384, 384), Image.LANCZOS), 240, 240, BG3), (j * 248, 0))
        # the fall runs at 12 fps against the walk's 15: frame k of the 15 fps loop shows die frame k * 12 / 15,
        # standing for the first half second and holding the body at the end
        t = k / 15.0 - 0.4
        f = cells["idle"][0] if t < 0 else die[min(len(die) - 1, int(t * 12))]
        c.alpha_composite(fit(f.resize((384, 384), Image.LANCZOS), 240, 240, BG3), (2 * 248, 0))
        frames.append(c)
    anim_webp(frames, "ap_gob_walk", 15)


def drifter():
    save(fit(raw("drifter_front"), S, S), "ap_dr_front")
    views = [raw("drifter_" + v) for v in ("back", "side", "bd", "fd")]
    save(row(views, 178, 250, 8, BG2, BG3, ["back", "side", "¾ back", "¾ front"], 19), "ap_dr_views")
    drv = [Image.open(os.path.join(DRIVERS, "run", v, "driver_03.png")).convert("RGB") for v in ("back", "bd", "side", "fd", "front")]
    save(row([d.crop((120, 80, 520, 600)) for d in drv], 140, 190, 6, BG2, (0, 0, 0), ["back", "¾ b", "side", "¾ f", "front"], 17), "ap_dr_drivers")
    side = os.path.join(ANIM, "drifter_pose_run_side")
    ks = [0, 6, 12, 18]
    top = [Image.open(os.path.join(DRIVERS, "run", "side", "driver_%02d.png" % k)).convert("RGB").crop((100, 60, 540, 620)) for k in ks]
    bot = [Image.open(os.path.join(side, "out_%02d.png" % k)).convert("RGBA") for k in ks]
    save(stack([row(top, 176, 200, 8, BG2, (0, 0, 0), ["frame %d" % (k + 1) for k in ks], 17), row(bot, 176, 200, 8)]), "ap_dr_animate")
    save(fit(raw("drifter_hurt_front"), S, S), "ap_dr_hurt")
    save(fit(raw("drifter_dead"), S, S), "ap_dr_dead")
    save(fit(raw("drifter_cheer"), S, S), "ap_dr_cheer")
    icon = Image.open(os.path.join(CONTENT, "characters", "drifter", "drifter_icon.png")).convert("RGBA")
    save(row([raw("drifter_portrait"), icon], 178, 220, 8), "ap_dr_portrait")
    cells = strip_cells("characters", "drifter", CHAR_ORDER)
    rows_ = []
    for name, title in (("run", "back"), ("run_bd", "¾ back"), ("run_s", "side"), ("run_fd", "¾ front"), ("run_f", "front")):
        r = panel(W2, 84, BG2)
        label(r, title, (4, 26), 19, INK2, False)
        fs = cells[name]
        x = 110
        for k in range(0, len(fs), 3):
            r.alpha_composite(fs[k].resize((80, 80), Image.LANCZOS), (x, 2))
            x += 78
        rows_.append(r)
    save(stack([panel(W2, 26, BG2)] + rows_, 2), "ap_dr_strip")
    save(crop_cap("close_a", (200, 560, 600, 920), W2 // 2 + 40), "ap_dr_game")
    # the five run cycles side by side at the game's 36 fps
    frames = []
    names = ("run_s", "run_fd", "run_f", "run_bd", "run")
    for k in range(24):
        c = panel(5 * 150 + 4 * 6, 170, BG2)
        for j, name in enumerate(names):
            c.alpha_composite(fit(cells[name][k], 150, 170, BG3), (j * 156, 0))
        frames.append(c)
    anim_webp(frames, "ap_dr_run", 36)


def big_mouth():
    m = json.load(open(os.path.join(RAW, "big_mouth_icon2.json"), encoding="utf-8"))["qa"]
    save(fit(raw("big_mouth_icon2"), S, S), "ap_bm_raw")
    save(checklist(raw("big_mouth_icon2"), [("one subject", m["subjects"] == 1), ("flat background", m["background"] == "flat"),
                                            ("no text", not m["text"]), ("clear of the edges", "touches-edge" not in m["problems"])]), "ap_bm_qa")
    icon = Image.open(os.path.join(CONTENT, "weapons", "big_mouth", "big_mouth_icon.png")).convert("RGBA")
    save(fit(icon, S, S, BG3, 30), "ap_bm_icon")
    save(crop_cap("close_a", (20, 100, 270, 200), S), "ap_bm_hud")
    # pass 34: the mouth is a Blender model again (tools/blender_mouth.py): its previews shut, open and gold, and in play
    mouth = os.path.join(DL, "mouth")
    prev = [Image.open(os.path.join(mouth, n)).convert("RGB").crop((96, 150, 416, 400)) for n in
            ("big_mouth_preview_shut.png", "big_mouth_preview_open.png", "loud_mouth_preview_open.png")]
    save(row(prev, 236, 190, 8, BG2, BG3, ["shut", "open", "evolved"], 18), "ap_mouth_model")
    save(crop_cap("mouth_3d", (330, 1000, 850, 1340), S), "ap_mouth_game")


def tommy():
    save(fit(Image.open(os.path.join(DL, "tommy_ref.png")).convert("RGB"), S, S), "ap_tg_model")
    save(fit(raw("tommy_gun_icon3"), S, S), "ap_tg_raw")
    ics = [Image.open(os.path.join(CONTENT, k, i, i + "_icon.png")).convert("RGBA") for k, i in (("weapons", "tommy_gun"), ("evolutions", "chicago_typewriter"))]
    save(row(ics, 178, 178, 8, BG2, BG3, ["Tommy Gun", "evolved"], 18), "ap_tg_icons")
    save(crop_cap("close_b", (196, 846, 446, 1096), S), "ap_tg_game")


def others():
    views = [raw("sun_prophet_" + v) for v in ("front", "fd", "side", "bd", "back")]
    save(row(views, 140, 200, 6, BG2, BG3, ["front", "¾ f", "side", "¾ b", "back"], 17), "ap_sp_views")
    save(crop_cap("extra_a", (0, 560, 420, 1100), 280), "ap_sp_game")
    zb = Image.open(os.path.join(DRIVERS, "walk_zombie_low", "back", "driver_03.png")).convert("RGB").crop((120, 80, 520, 600))
    zf = Image.open(os.path.join(DRIVERS, "walk_zombie_high", "front", "driver_03.png")).convert("RGB").crop((120, 80, 520, 600))
    sk = strip_cells("enemies", "skeleton", ENEMY_ORDER)
    save(row([zf, sk["run"][3], zb, sk["run_b"][3]], 132, 180, 6, BG2, BG3, ["driver", "front", "driver", "back"], 16), "ap_sk_walk")
    save(row(sk["die"], 104, 120, 6), "ap_sk_collapse")
    fin = Image.open(os.path.join(REPO, "game", "art", "sprites", "props", "saguaro_big.png")).convert("RGBA")
    save(row([raw("saguaro_big_11", PROPS_RAW), fin], 178, 250, 8, BG2, BG3, ["raw", "in the game"], 18), "ap_pr_saguaro")
    badges = [Image.open(os.path.join(REPO, "game", "art", "ui", "badges", b + ".png")).convert("RGBA") for b in ("crown", "skull", "gear")]
    save(row([raw("badge_crown_71", PROPS_RAW)] + badges, 132, 132, 6, BG2, BG3, ["raw", "crown", "skull", "gear"], 16), "ap_badges")
    iv = os.path.join(DL, "icon_variants")
    hat = [Image.open(os.path.join(iv, n + ".png")).convert("RGBA") for n in ("hat_A_icon", "hat_A_cut", "hat_A_empty_541", "hat_A_half_icon")]
    save(row(hat, 174, 174, 6, BG2, BG3, ["A, picked", "hat cut out", "dunes repainted", "half size"], 16), "ap_launcher")
    save(fit(Image.open(os.path.join(DL, "review", "phone.png")).convert("RGB"), W2, 436, BG2), "ap_review")


def variant_cells(kind, id_, sprite):
    """The cells of one art variant's strip (its counts from the JSON's variants entry)."""
    folder = os.path.join(CONTENT, kind, id_)
    d = json.load(open(os.path.join(folder, id_ + ".json"), encoding="utf-8"))
    anims, cols = d.get("anims", {}), int(d.get("strip_cols", 0))
    for v in (d.get("variants") or {}).values():
        if isinstance(v, dict) and v.get("sprite") == sprite:
            anims, cols = v.get("anims", anims), int(v.get("strip_cols", cols))
    st = Image.open(os.path.join(folder, sprite)).convert("RGBA")
    cell = int(d.get("frame_px", 128))
    cols = cols or st.width // cell
    out, k = {}, 0
    for name in ENEMY_ORDER:
        fr = []
        for _ in range(int(anims.get(name, 0))):
            x, y = (k % cols) * cell, (k // cols) * cell
            fr.append(st.crop((x, y, x + cell, y + cell)))
            k += 1
        if fr:
            out[name] = fr
    return out


def variants():
    """Section 15b's art variants: the goblins' and the runts' four sheets side by side, a walk frame and a fall frame."""
    for id_, pre, codes in (("goblin", "goblin", "abcd"), ("goblin_runt", "goblin_runt", "abcd")):
        tiles, labels = [], []
        for c in codes:
            sprite = pre + "_sprite.png" if c == "a" else "%s_sprite_%s.png" % (pre, c)
            if not os.path.exists(os.path.join(CONTENT, "enemies", id_, sprite)):
                continue
            cells = variant_cells("enemies", id_, sprite)
            walk = cells["run"][3]
            die = cells["die"][-1]
            t = panel(232, 150, BG3)
            t.alpha_composite(walk.resize((118, 118), Image.LANCZOS), (2, 16))
            t.alpha_composite(die.resize((118, 118), Image.LANCZOS), (112, 16))
            tiles.append(t)
            labels.append(("GOB-" if id_ == "goblin" else "RUN-") + c.upper())
        save(row(tiles, 232, 150, 8, BG2, BG3, labels, 17), "ap_var_" + ("gob" if id_ == "goblin" else "runt"))


def fire_ant():
    """Section 15b's fire ant: the Blender blockout, the side candidates, the five views, control frames against the
    painted walk, the four variants, and the walk moving."""
    drv = os.path.join(DRIVERS, "ant_anta")
    clays = [Image.open(os.path.join(drv, v, "clay.png")).convert("RGB").crop((70, 150, 570, 530)) for v in ("front", "fd", "side", "bd", "back")]
    depth = Image.open(os.path.join(drv, "side", "ctl_03.png")).convert("RGB").crop((70, 150, 570, 530))
    save(row(clays + [depth], 150, 114, 6, BG2, (0, 0, 0), ["front", "¾ f", "side", "¾ b", "back", "depth"], 15), "ap_ant_blockout")
    cands = [raw("fire_ant_anta_side_k%d" % k).crop((0, 180, 1024, 860)) for k in range(4)]
    save(row(cands, 178, 118, 6, BG2, BG3, ["k0", "k1 · kept", "k2", "k3"], 15), "ap_ant_sides")
    views = [raw("fire_ant_anta_" + v).crop((40, 60, 984, 1004)) for v in ("front", "fd", "side", "bd", "back")]
    save(row(views, 142, 142, 6, BG2, BG3, ["front", "¾ f", "side", "¾ b", "back"], 15), "ap_ant_views")
    clip = os.path.join(ANIM, "fire_ant_anta_ctl_side")
    ks = [12, 15, 18, 21]
    top = [Image.open(os.path.join(drv, "side", "ctl_%02d.png" % k)).convert("RGB").crop((70, 170, 570, 510)) for k in ks]
    bot = [Image.open(os.path.join(clip, "full_%02d.png" % k)).convert("RGBA").crop((40, 120, 600, 520)) for k in ks]
    save(stack([row(top, 176, 120, 8, BG2, (0, 0, 0), ["frame %d" % (k + 1) for k in ks], 15), row(bot, 176, 120, 8)]), "ap_ant_control")
    tiles, labels = [], []
    for c in "abcd":
        sp = "fire_ant_sprite_%s.png" % c
        if not os.path.exists(os.path.join(CONTENT, "enemies", "fire_ant", sp)):
            continue
        cells = variant_cells("enemies", "fire_ant", sp)
        t = panel(232, 150, BG3)
        # a side walk frame, or the back one for a two-way ant (ANT-A since v0.25)
        t.alpha_composite(cells.get("run_s", cells.get("run_b", cells["run"]))[2].resize((150, 150), Image.LANCZOS), (-10, 0))
        t.alpha_composite(cells["run"][2].resize((118, 118), Image.LANCZOS), (118, 16))
        tiles.append(t)
        labels.append("ANT-" + c.upper())
    if tiles:
        save(row(tiles, 232, 150, 8, BG2, BG3, labels, 17), "ap_ant_variants")
    # the chosen ant walking, side and front, at the game's rate
    d = json.load(open(os.path.join(CONTENT, "enemies", "fire_ant", "fire_ant.json"), encoding="utf-8"))
    code = str(d.get("variant", "")) or "ANT-A"
    sp = (d.get("variants", {}).get(code, {}) or {}).get("sprite")
    if sp and os.path.exists(os.path.join(CONTENT, "enemies", "fire_ant", sp)):
        cells = variant_cells("enemies", "fire_ant", sp)
        fps = int((d["variants"][code].get("fps") or {}).get("run", 20))
        frames = []
        names = [n for n in ("run_s", "run", "run_b") if n in cells]
        for k in range(len(cells["run"])):
            c = panel(len(names) * 228 - 8, 220, BG2)
            for j, name in enumerate(names):
                c.alpha_composite(fit(cells[name][k % len(cells[name])].resize((300, 300), Image.LANCZOS), 220, 220, BG3), (j * 228, 0))
            frames.append(c)
        anim_webp(frames, "ap_ant_walk", fps)


def main():
    os.makedirs(IMG, exist_ok=True)
    goblin()
    drifter()
    big_mouth()
    tommy()
    others()
    variants()
    fire_ant()


if __name__ == "__main__":
    main()

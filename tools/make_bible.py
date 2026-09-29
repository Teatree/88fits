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


def creature_order():
    """Every creature in the order the timeline meets it: roster by arrival, then the Elites, then the bosses, so the cast
    sheet and the creature table come from the same data and neither can forget a creature."""
    tl = json.load(open(os.path.join("game", "content", "maps", "red_canyon", "red_canyon.json"), encoding="utf-8"))["timeline_data"]
    arrive = {r["enemy"]: float(r.get("t", 0)) for r in tl.get("roster", [])}
    ids = [("enemies", i) for i, _ in sorted(arrive.items(), key=lambda kv: kv[1])]
    # the specials come on their own clock (pass 33.4), after the roster
    for row in tl.get("specials", {}).get("pool", []):
        sid = row.get("enemy") if isinstance(row, dict) else row
        if ("enemies", sid) not in ids:
            ids.append(("enemies", sid))
    elites, bosses = [], []
    for ev in tl.get("events", []):
        if ev.get("type") == "elite_boss":
            e = ev.get("enemy")
            for x in (e if isinstance(e, list) else [e]):
                if ("enemies", x) not in ids and ("enemies", x) not in elites:
                    elites.append(("enemies", x))
        if ev.get("type") == "boss" and ("bosses", ev.get("enemy")) not in bosses:
            bosses.append(("bosses", ev.get("enemy")))
    return ids + sorted(elites) + bosses


def cast_sheet():
    """Icon + six walk frames per creature in timeline order, the Elites and bosses last."""
    ids = creature_order()
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


def creature_rows():
    """The creature table from the content: every enemy and boss, ordered by when the map's roster brings them in."""
    import glob
    tl = json.load(open(os.path.join("game", "content", "maps", "red_canyon", "red_canyon.json"), encoding="utf-8"))["timeline_data"]
    arrive = {r["enemy"]: float(r.get("t", 0)) for r in tl.get("roster", [])}
    elite_ids = set()
    boss_ids = []
    for ev in tl.get("events", []):
        if ev.get("type") == "elite_boss":
            e = ev.get("enemy")
            for x in (e if isinstance(e, list) else [e]):
                elite_ids.add(x)
        if ev.get("type") == "boss" and ev.get("enemy") not in boss_ids:
            boss_ids.append(ev.get("enemy"))
    defs = {}
    for f in glob.glob(os.path.join("game", "content", "enemies", "*", "*.json")) + glob.glob(os.path.join("game", "content", "bosses", "*", "*.json")):
        if f.endswith("_ai.json"):
            continue
        d = json.load(open(f, encoding="utf-8"))
        defs[d["id"]] = d

    def mmss(t):
        return "%d:%02d" % (int(t) // 60, int(t) % 60)

    def numbers(d):
        parts = ["%g hp" % d.get("hp", 0)]
        if d.get("armor"):
            parts.append("%g armor" % d["armor"])
        parts.append("%g m/s" % d.get("speed", 0))
        parts.append("%g dmg" % d.get("damage", 0))
        ps = int(d.get("pack_size", 1))
        parts.append({1: "alone", 2: "pairs"}.get(ps, "packs of %d" % ps))
        return " · ".join(parts)

    rows = []
    for id_, t in sorted(arrive.items(), key=lambda kv: kv[1]):
        d = defs.get(id_)
        if not d:
            continue
        rows.append('      <tr><td><span class="name">%s</span><span class="sub">from %s · %s</span></td><td>%s</td><td class="num">%s</td><td>%s</td></tr>' % (
            d.get("name", id_), mmss(t), d.get("flavour", ""), d.get("brain", ""), numbers(d), d.get("doc", "")))
    sp = tl.get("specials", {})
    for row in sp.get("pool", []):
        sid = row.get("enemy") if isinstance(row, dict) else row
        d = defs.get(sid)
        if not d:
            continue
        st = int(row.get("stage", 1)) if isinstance(row, dict) else 1
        when = ("special from %s" % mmss(float(sp.get("from", 150)))) if st <= 1 else ("special from stage %d" % st)
        rows.append('      <tr><td><span class="name">%s</span><span class="sub">%s · %s</span></td><td>%s</td><td class="num">%s</td><td>%s</td></tr>' % (
            d.get("name", sid), when, d.get("flavour", ""), d.get("brain", ""), numbers(d), d.get("doc", "")))
    rows.append('      <tr><td><span class="name">Elite variants</span><span class="sub">every 90 s from 3:30</span></td><td>base brain</td><td class="num">1.4–1.6× size</td><td>Any roster creature with a modifier: armoured, swift, splitting, exploding (never the spit cactus or a special: <code>can_be_elite</code>). Always a chest.</td></tr>')
    for id_ in sorted(elite_ids):
        d = defs.get(id_)
        if d:
            rows.append('      <tr><td><span class="name">%s</span><span class="sub">the Elite · 2:30 · 7:30 · 12:30</span></td><td>%s</td><td class="num">%s</td><td>%s</td></tr>' % (
                d.get("name", id_), d.get("brain", ""), numbers(d), d.get("doc", "")))
    for id_ in boss_ids:
        d = defs.get(id_)
        if d:
            rows.append('      <tr><td><span class="name">%s</span><span class="sub">boss</span></td><td>boss</td><td class="num">%s</td><td>%s</td></tr>' % (
                d.get("name", id_), numbers(d), d.get("doc", "")))
    return "\n".join(rows)


def _load_type(t):
    out = {}
    for f in glob.glob(os.path.join("game", "content", t, "*", "*.json")):
        if os.path.basename(f) != os.path.basename(os.path.dirname(f)) + ".json":
            continue
        d = json.load(open(f, encoding="utf-8"))
        out[d["id"]] = d
    return out


def _esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def mutation_rows():
    """The 19 x 3 path table from content/mutations: a row per weapon in the weapon table's order, the hero mutations after."""
    muts = _load_type("mutations")
    weapons = _load_type("weapons")
    order = ["peashooter", "boomstick", "flare_gun", "tommy_gun", "poison_dart", "tumbleweed", "zap_beam", "orbit_saws", "branding_iron",
             "rattlesnake", "lob_grenade", "molotov", "skull_rain", "land_mine", "turret_buddy", "rocket_pod", "hornet_nest", "sabre", "pike"]
    for wid in sorted(weapons):
        if wid not in order:
            order.append(wid)
    rows = []
    for wid in order:
        w = weapons.get(wid)
        if not w:
            continue
        cells = []
        for kind in ("element", "volume", "motion"):
            m = next((x for x in muts.values() if x.get("weapon") == wid and x.get("kind") == kind), None)
            if m is None:
                cells.append("<td>—</td>")
                continue
            el = (" <span class=\"chip %s\">%s</span>" % ("e" if m.get("element") == "fire" else "g", m.get("element"))) if m.get("element") else ""
            cells.append("<td><b>%s</b>%s<br>%s<span class=\"sub\">%s</span></td>" % (_esc(m["name"]), el, _esc(m.get("text", "")), _esc(m.get("vfx", ""))))
        rows.append("      <tr><td><span class=\"name\">%s</span></td>%s</tr>" % (_esc(w.get("name", wid)), "".join(cells)))
    heroes = [m for m in muts.values() if m.get("hero")]
    heroes.sort(key=lambda m: m["hero"])
    for m in heroes:
        wname = weapons.get(m["weapon"], {}).get("name", m["weapon"])
        rows.append("      <tr><td><span class=\"name\">%s</span><span class=\"sub\">%s's %s</span></td><td colspan=\"3\"><b>%s</b>: %s <span class=\"sub\">%s</span></td></tr>" % (
            _esc(m["hero"].capitalize()), _esc(m["hero"].capitalize()), _esc(wname), _esc(m["name"]), _esc(m.get("text", "")), _esc(m.get("vfx", ""))))
    return "\n".join(rows)


def _describe_effects(effs):
    parts = []
    names = {"max_hp": "max HP", "move_speed": "move speed", "might": "might", "lifesteal": "lifesteal", "regen": "regen", "thorns": "thorns",
             "armor": "armor", "cooldown": "cooldowns", "magnet": "pickup radius", "area": "area", "shield_max": "shield",
             "evade": "evade", "evade_invuln": "s untouchable after an evade", "regen_delay": "regen wait after a hit",
             "lifesteal_cap": "lifesteal cap a second", "shield_delay": "shield recharge wait", "shield_rate": "shield recharge a second"}
    for e in effs:
        st = names.get(e.get("stat"), e.get("stat"))
        v = float(e.get("value", 0))
        if e.get("op") == "set":
            unit = "%" if e.get("stat") in ("lifesteal_cap", "shield_rate") else " s"
            shown = v * 100 if unit == "%" else v
            parts.append("%s %g%s" % (st, shown, unit))
            continue
        if e.get("stat") in ("evade",):
            parts.append("%s%g%% evade" % ("+" if v >= 0 else "−", abs(v * 100)))
            continue
        if e.get("op") == "mul":
            parts.append("%s%d%% %s" % ("+" if v >= 0 else "−", abs(round(v * 100)), st))
        elif st == "regen":
            parts.append("%s%g HP/s" % ("+" if v >= 0 else "−", abs(v)))
        elif st == "lifesteal":
            parts.append("%s%g%% lifesteal" % ("+" if v >= 0 else "−", abs(v * 100)))
        else:
            parts.append("%s%g %s" % ("+" if v >= 0 else "−", abs(v), st))
    return ", ".join(parts)


def line_rows():
    lines = _load_type("lines")
    rows = []
    for lid in ["vigour", "stride", "mend", "brawn", "thirst", "bristle"] + sorted(k for k in lines if k not in ["vigour", "stride", "mend", "brawn", "thirst", "bristle"]):
        l = lines.get(lid)
        if not l or l.get("evolves_from"):
            continue
        lv = l.get("levels", [])
        per = _describe_effects([e for e in (lv[0] if lv else []) if float(e.get("value", 0)) > 0 or e.get("stat") in ("thorns", "regen")])
        extras = []
        if not l.get("repeat_last_level", True) and len(lv) > 1:
            for k, rank in enumerate(lv[1:], start=2):
                ex = [e for e in rank if e.get("stat") != lv[0][0].get("stat")]
                if ex:
                    extras.append("rank %d: %s" % (k, _describe_effects(ex)))
        # the evolution (pass 33.2): what the maxed line becomes, in full
        evo = lines.get(l.get("evolves_into", ""), {})
        ecell = ("<b>%s</b>: %s%s" % (_esc(evo["name"]), _esc(_describe_effects(evo.get("levels", [[]])[0])),
                 (" (trade: %s)" % _esc(evo["trade"])) if evo.get("trade") else "")) if evo else "—"
        rows.append("      <tr><td><span class=\"name\">%s</span><span class=\"sub\">%s</span></td><td>%s%s</td><td>%s</td><td class=\"num\">%d</td><td>%s</td></tr>" % (
            _esc(l["name"]), _esc(l.get("flavour", "")), _esc(per), (" (" + "; ".join(extras) + ")") if extras else "", _esc(l.get("trade") or "none"), int(l.get("max_level", 4)), ecell))
    return "\n".join(rows)


def perk_rows():
    perks = _load_type("perks")
    muts = _load_type("mutations")
    chars = _load_type("characters")
    weapons = _load_type("weapons")
    rows = []
    for cid in sorted(chars):
        c = chars[cid]
        p = next((x for x in perks.values() if x.get("hero") == cid), None)
        hm = next((x for x in muts.values() if x.get("hero") == cid), None)
        pcell = "<b>%s</b>: %s" % (_esc(p["name"]), _esc(p.get("text", ""))) if p else "—"
        mcell = "<b>%s</b> (%s): %s" % (_esc(hm["name"]), _esc(weapons.get(hm["weapon"], {}).get("name", hm["weapon"])), _esc(hm.get("text", ""))) if hm else "—"
        rows.append("      <tr><td><span class=\"name\">%s</span><span class=\"sub\">%s · %s</span></td><td>%s</td><td>%s</td></tr>" % (
            _esc(c.get("name", cid)), _esc(c.get("trait_name", "")), _esc(weapons.get(c.get("favourite_weapon", ""), {}).get("name", "")), pcell, mcell))
    return "\n".join(rows)


def talent_rows():
    """The Mirror's talents from content/talents: both forms of each, the ranks and what they cost."""
    ts = _load_type("talents")
    rows = []
    for t in sorted(ts.values(), key=lambda x: int(x.get("order", 0))):
        forms = t.get("forms", [])
        cost = " / ".join("%d g" % int(c) for c in t.get("cost", []))
        a = forms[0] if len(forms) > 0 else {}
        b = forms[1] if len(forms) > 1 else {}
        rows.append("      <tr><td><span class=\"name\">%s</span><span class=\"sub\">%s</span></td><td><b>%s</b> — %s</td><td><b>%s</b> — %s</td><td>%d ranks · %s</td></tr>" % (
            _esc(t.get("name", t.get("id", ""))), _esc(t.get("flavour", "")),
            _esc(a.get("name", "")), _esc(a.get("text", "")),
            _esc(b.get("name", "")), _esc(b.get("text", "")),
            int(t.get("ranks", 3)), _esc(cost)))
    return "\n".join(rows)


def props_sheet():
    """The painted scenery with labels, from art/sprites/props/props.json."""
    mp = os.path.join("game", "art", "sprites", "props", "props.json")
    if not os.path.exists(mp):
        return
    man = json.load(open(mp, encoding="utf-8"))
    ids = list(man.keys())
    # the structures' spent versions sit at the end, after their lit ones
    ids += [id_ + "_off" for id_ in ids if man[id_].get("off")]
    S = 150
    cols = 7
    rows = (len(ids) + cols - 1) // cols
    out = Image.new("RGB", (cols * (S + 12) + 12, rows * (S + 36) + 12), (26, 24, 34))
    f = font(15)
    for k, id_ in enumerate(ids):
        base = man[id_.replace("_off", "")]
        fn = base["off"] if id_.endswith("_off") else base["file"]
        im = Image.open(os.path.join("game", "art", "sprites", "props", fn)).convert("RGBA").resize((S, S), Image.LANCZOS)
        x, y = 12 + (k % cols) * (S + 12), 12 + (k // cols) * (S + 36)
        out.paste(im, (x, y), im)
        ImageDraw.Draw(out).text((x + 4, y + S + 4), "%s  %.1f m" % (id_, base["height"]), fill=(181, 174, 200), font=f)
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
    html = html.replace("{{CREATURES}}", creature_rows())
    html = html.replace("{{MUTATIONS}}", mutation_rows()).replace("{{LINES}}", line_rows()).replace("{{PERKS}}", perk_rows()).replace("{{TALENTS}}", talent_rows())
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

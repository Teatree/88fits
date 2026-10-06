"""Assembles docs/design/design-bible.html from docs/design/src/part*.html.

  python tools/make_bible.py [--shots=<dir>]

--shots converts the PNG captures in <dir> (from screenshot_run.gd) to WebP in docs/design/img/ first. The cast,
hero-cycle and icon sheets are always rebuilt from the content folders. {{IMG:name|alt}} inlines img/<name>.webp,
{{CSS}} the stylesheet, {{SOUND_ROWS}} the sound table from src/sounds.json filtered by the live soundmap."""
import base64
import glob
import io
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
    order = ENEMY_ORDER if "attack" in d.get("anims", {}) else CHAR_ORDER
    off = {}
    n = 0
    for k in order:
        off[k] = n
        n += int(d.get("anims", {}).get(k, 0))

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
        n = int(d.get("anims", {}).get("run", 0))
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
        n = int(d.get("anims", {}).get(key, 0))
        row = Image.new("RGBA", (150 + 8 * (S + 4), S + 6), (26, 24, 34, 255))
        ImageDraw.Draw(row).text((8, S // 2 - 10), label, fill=(181, 174, 200, 255), font=f)
        for k in range(8):
            fr = frame(off[key] + int(k * n / 8)).resize((S, S), Image.LANCZOS)
            row.paste(fr, (150 + k * (S + 4), 3), fr)
        rows.append(row)
    n = int(d.get("anims", {}).get("hit_f", 0))
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
    # when the Elites come, read off the timeline (pass 46: the clock was stretched, the times must follow it)
    elite_times = {}
    elite_every = None
    boss_ids = []
    for ev in tl.get("events", []):
        if ev.get("type") == "elite_boss":
            e = ev.get("enemy")
            for x in (e if isinstance(e, list) else [e]):
                elite_times.setdefault(x, []).append(float(ev.get("t", 0)))
        if ev.get("type") == "elite_every" and elite_every is None:
            elite_every = ev
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
    placed = set()

    def row(d, sub, brain=None):
        placed.add(d["id"])
        return '      <tr><td class="it-i">%s</td><td><span class="name">%s</span><span class="sub">%s</span></td><td>%s</td><td class="num">%s</td><td>%s</td></tr>' % (
            creature_pic(d), d.get("name", d["id"]), sub, d.get("brain", "") if brain is None else brain, numbers(d), d.get("doc", ""))

    for id_, t in sorted(arrive.items(), key=lambda kv: kv[1]):
        d = defs.get(id_)
        if not d:
            continue
        rows.append(row(d, "from %s · %s" % (mmss(t), d.get("flavour", ""))))
    sp = tl.get("specials", {})
    for r in sp.get("pool", []):
        sid = r.get("enemy") if isinstance(r, dict) else r
        d = defs.get(sid)
        if not d:
            continue
        st = int(r.get("stage", 1)) if isinstance(r, dict) else 1
        when = ("special from %s" % mmss(float(sp.get("from", 150)))) if st <= 1 else ("special from stage %d" % st)
        rows.append(row(d, "%s · %s" % (when, d.get("flavour", ""))))
    if elite_every is not None:
        iv = elite_every.get("interval", 90)
        iv_text = ("%g–%g s" % (float(iv[0]), float(iv[-1]))) if isinstance(iv, list) else ("%g s" % float(iv))
        rows.append('      <tr><td class="it-i"></td><td><span class="name">Elite variants</span><span class="sub">every %s from %s</span></td><td>base brain</td><td class="num">1.4–1.6× size</td><td>Any roster creature with a modifier: armoured, swift, splitting, exploding (never the spit cactus or a special: <code>can_be_elite</code>). Always a chest.</td></tr>' % (
            iv_text, mmss(float(elite_every.get("t", 0)))))
    for id_ in sorted(elite_times):
        d = defs.get(id_)
        if d:
            rows.append(row(d, "the Elite · " + " · ".join(mmss(t) for t in sorted(elite_times[id_]))))
    for id_ in boss_ids:
        d = defs.get(id_)
        if d:
            rows.append(row(d, "boss", "boss"))
    # pass 53: creatures that are in the content but on no row (the Red Goblins and the Werewolf wait for the Level Editor)
    waiting = [d for i, d in sorted(defs.items()) if i not in placed and not d.get("retired") and not d.get("hidden")
               and not i.startswith("training_dummy") and d.get("archetype") not in ("boss",) and i != "tumbleweed_minion"]
    if waiting:
        rows.append('      <tr class="it-grp"><td colspan="5">In the content, on no row yet: place them with the Level Editor (tools\\level_editor.cmd) · %d</td></tr>' % len(waiting))
        for d in waiting:
            rows.append(row(d, "not placed · " + d.get("flavour", "")))
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


# A passive stat's shown name and how its number reads (a copy of TextGen.STATS for the stats the passives touch: the
# table is written from the JSON, without the game).
_STATS = {"max_hp": ("max HP", "num"), "move_speed": ("move speed", "num"), "might": ("attack damage", "pct"),
          "lifesteal": ("life steal", "pct"), "regen": ("HP/s", "num"), "thorns": ("thorns damage", "num"),
          "damage_reduction": ("damage reduction", "pct"), "cooldown": ("cooldown", "sec"), "magnet": ("pickup radius", "num"),
          "area": ("area of effect", "pct"), "greed": ("coin gain", "pct"), "shield_max": ("shield", "num"),
          "evade": ("evade chance", "pct"), "evade_invuln": ("untouchable after an evade", "sec"),
          "regen_delay": ("regen wait after a hit", "sec"), "lifesteal_cap": ("life steal cap a second", "pct"),
          "shield_delay": ("shield recharge wait", "sec"), "shield_rate": ("shield recharge a second", "pct"),
          "crit_chance": ("crit chance", "pct"), "execute_frac": ("execute threshold", "pct"), "xp_gain": ("XP gain", "pct"),
          "overkill": ("overkill splash", "pct"), "ricochet": ("ricochet chance", "pct"), "amount": ("projectiles", "count"),
          "projectile_speed": ("projectile speed", "pct"), "fire_damage": ("burn per tick", "num"),
          "poison_damage": ("poison per tick", "num"), "heal_drop": ("cake drop chance", "pct"),
          "coin_drop": ("coin bag drop chance", "pct"), "brand_chance": ("chance a kill burns the ground", "pct"),
          "adrenaline_speed": ("speed per kill stack", "pct"), "adrenaline_might": ("attack damage per kill stack", "pct"),
          "desperado": ("attack damage as health falls", "pct"),
          # pass 47: the new lines and passive items (TextGen.STATS has the same words)
          "luck": ("luck", "pct"), "crit_damage": ("crit damage", "pct"), "debuff_duration": ("debuff duration", "pct"),
          "difficulty": ("difficulty", "pct"), "still_regen": ("HP/s standing still", "num"),
          "still_might": ("attack damage a second standing still (to +100%)", "pct"),
          "barrel_speed": ("move speed after a barrel", "pct"), "barrel_seconds": ("barrel boost", "sec"),
          "xp_drop_chance": ("extra XP gem chance", "pct"), "elite_damage": ("damage to Elites and bosses", "pct")}
_PREFIX = {"desperado": "up to "}


def _describe_effects(effs):
    parts = []
    for e in effs:
        stat = e.get("stat")
        st, kind = _STATS.get(stat, (stat, "num"))
        v = float(e.get("value", 0))
        sign = "+" if v >= 0 else "−"
        if e.get("op") == "set":
            shown = "%g%%" % (v * 100) if kind == "pct" else ("%g s" % v if kind == "sec" else "%g" % v)
            parts.append("%s %s" % (st, shown))
        elif e.get("op") == "mul":
            parts.append("%s%s%d%% %s" % (_PREFIX.get(stat, ""), sign, abs(round(v * 100)), st))
        elif stat == "regen":
            parts.append("%s%g HP/s" % (sign, abs(v)))
        elif kind == "pct":
            parts.append("%s%s%g%% %s" % (_PREFIX.get(stat, ""), sign, abs(round(v * 1000) / 10), st))
        elif kind == "sec":
            parts.append("%s%g s %s" % (sign, abs(v), st))
        else:
            if kind == "count" and abs(v) == 1 and st.endswith("s"):
                st = st[:-1]
            parts.append("%s%g %s" % (sign, abs(v), st))
    return ", ".join(parts)


def _harms(e):
    """The price a passive charges (its trade says it in words): less health, speed or attack damage, longer cooldowns."""
    v = float(e.get("value", 0))
    if e.get("stat") == "cooldown":
        return e.get("op") == "mul" and v > 0
    return e.get("stat") in ("max_hp", "move_speed", "might", "area", "damage_reduction", "regen", "luck") and v < 0


def passive_rows():
    """The passives table (pass 46: the lines folded into the passives): every base passive in play, by name, with what
    a level gives (the harm its trade names left to the trade), the trade, its top level and what it evolves into."""
    ps = _load_type("passives")
    rows = []
    for pid in sorted(ps, key=lambda k: ps[k].get("name", k)):
        p = ps[pid]
        if p.get("evolves_from") or p.get("hidden"):
            continue
        lv = p.get("levels", [])
        first = lv[0] if lv else []
        per = _describe_effects([e for e in first if not (p.get("trade") and _harms(e))])
        extras = []
        if not p.get("repeat_last_level", True) and len(lv) > 1:
            for k, step in enumerate(lv[1:], start=2):
                ex = [e for e in step if not (p.get("trade") and _harms(e))]
                if ex and ex != first:
                    extras.append("level %d: %s" % (k, _describe_effects(ex)))
        # the evolution (pass 33.2 on the lines): what the maxed passive becomes, in full
        evo = ps.get(p.get("evolves_into", ""), {})
        evo_fx = [e for e in (evo.get("levels") or [[]])[0] if not (evo.get("trade") and _harms(e))]
        ecell = ("<b>%s</b>: %s%s" % (_esc(evo["name"]), _esc(_describe_effects(evo_fx)),
                 (" (trade: %s)" % _esc(evo["trade"])) if evo.get("trade") else "")) if evo else "—"
        sub = p.get("flavour", "")
        if int(p.get("from_stage", 0)) > 1:
            sub += " · stage %d only" % int(p["from_stage"])
        rows.append("      <tr><td><span class=\"name\">%s</span><span class=\"sub\">%s</span></td><td>%s%s</td><td>%s</td><td class=\"num\">%d</td><td>%s</td></tr>" % (
            _esc(p["name"]), _esc(sub), _esc(per), (" (" + "; ".join(extras) + ")") if extras else "", _esc(p.get("trade") or "none"), int(p.get("max_level", 8)), ecell))
    return "\n".join(rows)


def perk_rows():
    perks = _load_type("perks")
    muts = _load_type("mutations")
    chars = _load_type("characters")
    weapons = _load_type("weapons")
    passives = _load_type("passives")
    rows = []
    for cid in sorted(chars):
        c = chars[cid]
        ps = sorted((x for x in perks.values() if x.get("hero") == cid), key=lambda x: x.get("name", ""))
        hm = next((x for x in muts.values() if x.get("hero") == cid), None)
        # pass 53: every perk of the hero (the table showed the first only); a hidden one says so
        pcell = "<br>".join("<b>%s</b>%s: %s" % (_esc(x["name"]), " (hidden)" if x.get("hidden") else "", _esc(x.get("text", ""))) for x in ps) or "—"
        mcell = "<b>%s</b> (%s): %s" % (_esc(hm["name"]), _esc(weapons.get(hm["weapon"], {}).get("name", hm["weapon"])), _esc(hm.get("text", ""))) if hm else "—"
        # the favourite: a weapon, or (pass 46, Ironwood's Cake) a passive
        fav = weapons.get(c.get("favourite_weapon", ""), {}).get("name", "") or passives.get(c.get("favourite_passive", ""), {}).get("name", "")
        rows.append("      <tr><td><span class=\"name\">%s</span><span class=\"sub\">%s · %s</span></td><td>%s</td><td>%s</td></tr>" % (
            _esc(c.get("name", cid)), _esc(c.get("trait_name", "")), _esc(fav), pcell, mcell))
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


# ---------------------------------------------------------------- 08 Items (Garry, 2026-10-02: one section, a clean list)
# Every weapon with its mutations and evolution, the lines and the passives, each with its icon from its content folder
# and what keeps it out of a run: hidden, a quest, a hero, a stage. Read from game/content when the bible is built.

ICON_PX = 96   # pass 53: every picture zooms in a pop-up, so the icons travel at 96 px (128 pushed the page past 16 MB)
_ICON_CACHE = {}


def pic_uri(p, px=ICON_PX):
    """A PNG under the repo as an embedded WebP no bigger than px (pass 53: creature pictures and hero portraits too)."""
    key = (p, px)
    if key not in _ICON_CACHE:
        if not os.path.exists(p):
            _ICON_CACHE[key] = ""
        else:
            im = Image.open(p).convert("RGBA")
            im.thumbnail((px, px), Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, "WEBP", quality=88, method=6)
            _ICON_CACHE[key] = "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode("ascii")
    return _ICON_CACHE[key]


def icon_uri(kind, id_):
    """An item's icon as a small embedded WebP (its <id>_icon.png)."""
    return pic_uri(os.path.join(CONTENT, kind, id_, id_ + "_icon.png"))


def creature_pic(d, px=72):
    """The creature's picture for the creature table (pass 53, Garry: "add each enemy visual in the list of enemies"):
    the icon of the art variant it plays (variants[variant].icon), else its own icon."""
    kind = "bosses" if d.get("archetype") == "boss" else "enemies"
    folder = os.path.join(CONTENT, kind, d["id"])
    v = (d.get("variants") or {}).get(d.get("variant", ""), {})
    name = v.get("icon") if isinstance(v, dict) and v.get("icon") else d["id"] + "_icon.png"
    u = pic_uri(os.path.join(folder, name), 160)
    if not u:
        return '<span class="it-noico" style="width:%dpx;height:%dpx"></span>' % (px, px)
    return '<img class="cre-pic" src="%s" width="%d" height="%d" alt="%s" loading="lazy">' % (u, px, px, _esc(d.get("name", d["id"])))


# The plates the game puts every icon on (pass 47): weapons light blue, lines light yellow, passive items in their rarity's
# World of Warcraft colour, mutations plum, perks turquoise, evolutions dark inside a brass ring. W.gd is read for the
# exact colours when it names them, so the bible and the game cannot drift.
PLATE = {"weapon": "#BFE0F2", "line": "#F7E9A3", "mutation": "#4A3358", "perk": "#3F8F8A", "evolved": "#241B14",
         "ring": "#C9932F"}
RARITY_PLATE = {"common": "#D2CFC7", "uncommon": "#1EFF00", "rare": "#0070DD", "epic": "#A335EE", "legendary": "#FF8000"}   # common: the light grey of pass 53 (Garry), W.gd overrides every one below
RARITY_ORDER = ("common", "uncommon", "rare", "epic", "legendary")


def _read_plates():
    """The plate colours as W.gd defines them (WEAPON_BLUE, LINE_YELLOW, RARITY_PLATE; the evolved plate is INK in a BRASS
    ring), when it does."""
    import re
    path = os.path.join("game", "ui", "wanted", "W.gd")
    if not os.path.exists(path):
        return
    src = open(path, encoding="utf-8").read()
    for name, key in (("WEAPON_BLUE", "weapon"), ("LINE_YELLOW", "line"), ("PLUM", "mutation"), ("TURQUOISE", "perk"),
                      ("INK", "evolved"), ("BRASS", "ring")):
        m = re.search(r"const\s+%s\s*:?=\s*Color\(\"#?([0-9a-fA-F]{6})" % name, src)
        if m:
            PLATE[key] = "#" + m.group(1).upper()
    for r in RARITY_ORDER:
        m = re.search(r"\"%s\"\s*:\s*Color\(\"#?([0-9a-fA-F]{6})" % r, src[src.find("RARITY_PLATE"):] if "RARITY_PLATE" in src else "")
        if m:
            RARITY_PLATE[r] = "#" + m.group(1).upper()


_read_plates()


def _plate(kind, d):
    """The plate colour (and the brass ring for an evolution) an item's icon sits on in the game."""
    if kind == "evolutions" or (kind == "passives" and d.get("evolves_from")):
        return PLATE["evolved"], True
    if kind == "weapons":
        # pass 48: a weapon's plate climbs the rarity colours with its level; the bible shows it at level 1 (common)
        return RARITY_PLATE["common"], False
    if kind == "mutations":
        return PLATE["mutation"], False
    if kind == "perks":
        return PLATE["perk"], False
    if kind == "passives":
        if _is_line(d):
            # pass 48: lines climb the colours with their level too (common at level 1, epic at 4)
            return RARITY_PLATE["common"], False
        return RARITY_PLATE.get(d.get("rarity", "common"), RARITY_PLATE["common"]), False
    return "", False


def _ico(kind, id_, px):
    u = icon_uri(kind, id_)
    d = _items().get(kind, {}).get(id_, {}) if kind in ("weapons", "evolutions", "mutations", "passives") else {}
    bg, ring = _plate(kind, d) if d else ("", False)
    if kind == "perks":
        bg = PLATE["perk"]
    elif kind == "characters":
        bg = "#2A2330"
    style = ""
    if bg:
        style = ' style="background:%s%s"' % (bg, (";box-shadow:inset 0 0 0 2px " + PLATE["ring"]) if ring else "")
    if not u:
        return '<span class="it-noico" style="width:%dpx;height:%dpx%s"></span>' % (px, px, (";background:" + bg) if bg else "")
    return '<img class="it-ico" src="%s" width="%d" height="%d" alt="" loading="lazy"%s>' % (u, px, px, style)


def _items():
    """Everything the item tables read, loaded once."""
    if not hasattr(_items, "d"):
        _items.d = {t: _load_type(t) for t in ("weapons", "evolutions", "mutations", "passives", "quests", "characters", "enemies", "bosses", "maps", "perks")}
    return _items.d


def _timeline():
    m = _items()["maps"].get("red_canyon", {})
    return m.get("timeline_data", m.get("timeline", {})) or {}


def _creature_name(id_):
    D = _items()
    e = D["enemies"].get(id_) or D["bosses"].get(id_) or {}
    return e.get("name", id_.replace("_", " ").title())


def _creature_count(id_, n):
    name = _creature_name(id_)
    if n <= 1:
        return "the " + name
    if name.endswith(("s", "x")):
        plural = name + "es"
    elif name.endswith("y") and name[-2:-1].lower() not in "aeiou":
        plural = name[:-1] + "ies"
    else:
        plural = name + "s"
    return "%d %s" % (n, plural)


def quest_text(q):
    """TextGen.quest_text in Python: a quest's words as the Collection shows them."""
    if q.get("quest_text"):
        return q["quest_text"]
    c = q.get("condition", {})
    t = c.get("type", "")
    n = int(c.get("count", 0))
    mp = _items()["maps"].get(c.get("map", "red_canyon"), {}).get("name", "Red Canyon")
    if t == "kills_with_weapon":
        w = _items()["weapons"].get(c.get("weapon", ""), {})
        return "Kill %d creatures with the %s." % (n, w.get("name", str(c.get("weapon", "")).title()))
    if t == "kills_of_enemy":
        return "Kill %s." % _creature_count(c.get("enemy", ""), n)
    if t == "kills_in_run_of_enemy":
        return "Kill %s in one run." % _creature_count(c.get("enemy", ""), n)
    if t == "reach_level":
        return "Reach level %d in one run." % int(c.get("level", 0))
    if t == "survive_minutes":
        return "Survive %d minutes in one run." % int(c.get("minutes", 0))
    if t == "survive_minutes_no_lift":
        return "Survive %d minutes without lifting your thumb." % int(c.get("minutes", 0))
    if t == "open_chests":
        return "Open %d chests." % n
    if t == "evolve_any":
        k = int(c.get("count", 1))
        return "Evolve any weapon%s." % ("" if k <= 1 else " %d times" % k)
    if t == "extract_after_stage":
        return "Extract after stage %d on %s." % (int(c.get("stage", 1)), mp)
    if t == "kill_boss":
        return "Kill the stage %d boss on %s." % (int(c.get("stage", 1)), mp)
    if t == "kills_total":
        return "Kill %d creatures, all time." % n
    if t == "runs_total":
        return "Play %d runs." % n
    if t == "pickups_total":
        return "Pick up %d power-ups." % n
    if t == "gold_total":
        return "Earn %d gold, all time." % n
    if t == "reach_stage":
        return "Reach stage %d." % int(c.get("stage", 1))
    return "Complete a challenge."


def _first_arrival(enemy_id):
    tl = _timeline()
    best = -1.0
    for row in tl.get("roster", []):
        if isinstance(row, dict) and row.get("enemy") == enemy_id:
            t = float(row.get("t", 0))
            best = t if best < 0 or t < best else best
    for ev in tl.get("events", []):
        if isinstance(ev, dict):
            ids = ev.get("enemy") if isinstance(ev.get("enemy"), list) else [ev.get("enemy", "")]
            if enemy_id in ids:
                t = float(ev.get("t", 0))
                best = t if best < 0 or t < best else best
    sp = tl.get("specials", {}) if isinstance(tl.get("specials"), dict) else {}
    for row in sp.get("pool", []):
        if isinstance(row, dict) and row.get("enemy") == enemy_id:
            t = float(sp.get("from", 0)) + max(float(row.get("stage", 1)) - 1.0, 0.0) * float(tl.get("stage_length", 300))
            best = t if best < 0 or t < best else best
    return best


def quest_stage(q):
    """QuestTracker.stage_hint in Python: the first stage the quest can be done on (0 = any)."""
    c = q.get("condition", {})
    t = c.get("type", "")
    stage_len = max(float(_timeline().get("stage_length", 300)), 1.0)
    if t in ("kills_of_enemy", "kills_in_run_of_enemy"):
        a = _first_arrival(c.get("enemy", ""))
        return int(a // stage_len) + 1 if a >= 0 else 0
    if t in ("kill_boss", "reach_stage", "extract_after_stage"):
        return int(c.get("stage", 1))
    if t in ("survive_minutes", "survive_minutes_no_lift"):
        return int(-(-float(c.get("minutes", 0)) * 60.0 // stage_len))
    if t == "evolve_any":
        return 2
    if t == "reach_level":
        lv = int(c.get("level", 0))
        return 1 if lv <= 12 else (2 if lv <= 24 else 3)
    return 0


def _locks():
    """{(kind, id): quest} for every item a quest unlocks."""
    out = {}
    for q in _items()["quests"].values():
        u = q.get("unlocks", {})
        if u.get("type") in ("weapon", "passive"):
            out[(u["type"], u.get("id", ""))] = q
    return out


def _hero_name(cid):
    return _items()["characters"].get(cid, {}).get("name", cid.title())


def _hero_hidden(cid):
    return bool(_items()["characters"].get(cid, {}).get("hidden"))


def _chip(cls, text, title=""):
    return '<span class="chip %s"%s>%s</span>' % (cls, (' title="%s"' % _esc(title)) if title else "", _esc(text))


def _status_cell(chips, notes=(), default=True):
    """The status chips (and the lock's words under them); a top-level item with none is "open", a mutation or an
    evolution with none shows nothing, since it follows its weapon."""
    if not chips and default:
        chips = [_chip("it-open", "open")]
    body = " ".join(chips)
    for n in notes:
        body += '<span class="sub">%s</span>' % n
    return "<td class=\"it-status\">%s</td>" % body


def _lock_chips(kind, id_):
    q = _locks().get((kind, id_))
    if not q:
        return [], []
    st = quest_stage(q)
    note = _esc(quest_text(q)) + (" · stage %d" % st if st else " · any stage")
    return [_chip("it-lock", "locked")], [note]


_BEHAVIOUR = {"ProjectileEmitter": "shots", "Orbiter": "orbit", "Lobber": "lobs", "Beam": "chain lightning", "Spawner": "turret",
              "MissilePod": "homing", "Thruster": "blade", "LaserBeam": "beam", "Smasher": "hammer", "GravityGun": "grab & throw",
              "ConeWave": "cone wave", "MineLayer": "mines"}
_BLAST_M = {"Lobber", "MissilePod", "MineLayer"}   # their area is a blast radius in metres; elsewhere it is a scale


def _g(v):
    return "%g" % round(float(v), 2)


def _stat_line(d):
    """A weapon's base numbers on one line: damage, how many, how often, how far, and what else it carries."""
    b = d.get("base", {})
    beh = d.get("behavior", "")
    parts = []
    if "damage" in b:
        parts.append("%s damage" % _g(b["damage"]) + (" a tick" if beh == "LaserBeam" else ""))
    if int(b.get("amount", 1)) > 1:
        parts.append("×%d" % int(b["amount"]))
    if beh == "Spawner":
        life = float(b.get("lifetime", 0))
        parts.append("a turret every %s s" % _g(b.get("cooldown", 0)) + (", stays" if life >= 999 else ", lasts %s s" % _g(life)))
    elif "cooldown" in b:
        parts.append(("touch every %s s" if beh == "Orbiter" else "every %s s") % _g(b["cooldown"]))
    if beh == "LaserBeam" and b.get("duration"):
        parts.append("pours %s s" % _g(b["duration"]))
    if beh in _BLAST_M and float(b.get("area", 0)) > 0:
        parts.append("%s m blast" % _g(b["area"]))
    if b.get("orbit_radius"):
        parts.append("orbit %s m" % _g(b["orbit_radius"]))
    if b.get("range"):
        parts.append(("%s m reach" if beh in ("Thruster", "Smasher") else "%s m") % _g(b["range"]))
    if beh == "MineLayer" and b.get("lifetime"):
        parts.append("mines last %s s" % _g(b["lifetime"]))
    p = int(b.get("pierce", 0))
    if p >= 40:
        parts.append("pierces everything")
    elif p > 0:
        parts.append("pierce %d" % p)
    if b.get("chains"):
        parts.append("chains %d" % int(b["chains"]))
    if b.get("fire_damage"):
        parts.append("burns %s a tick" % _g(b["fire_damage"]))
    if b.get("poison_damage"):
        parts.append("poisons %s a tick" % _g(b["poison_damage"]) + (" ×%d" % int(b["poison_stacks"]) if int(b.get("poison_stacks", 1)) > 1 else ""))
    return " · ".join(parts)


_MUT_KIND = {"element": 0, "volume": 1, "motion": 2, "stance": 3, "hero": 4}


def _mut_kind_chip(m):
    k = m.get("kind", "")
    if k == "element":
        el = m.get("element", "")
        return _chip("e" if el == "fire" else "g", "element · " + el if el else "element")
    if k == "hero":
        return _chip("b", "hero mutation")
    return _chip("", k)


def _weapon_group(wid, w, locks, D):
    if w.get("hidden"):
        return 3
    if w.get("hero"):
        return 1
    if ("weapon", wid) in locks:
        return 2
    return 0


def item_weapon_rows():
    D = _items()
    W, E, M, C = D["weapons"], D["evolutions"], D["mutations"], D["characters"]
    locks = _locks()
    playable = {cid: c for cid, c in C.items() if not c.get("hidden")}
    groups = [("Open from the first run", []), ("Hero weapons: only that hero finds them", []),
              ("Locked until a quest is done", []), ("Hidden: kept in the content, never offered", [])]
    for wid in sorted(W, key=lambda k: W[k].get("name", k)):
        groups[_weapon_group(wid, W[wid], locks, D)][1].append(wid)
    rows = []
    for title, ids in groups:
        if not ids:
            continue
        rows.append('      <tr class="it-grp"><td colspan="5">%s · %d</td></tr>' % (_esc(title), len(ids)))
        for wid in ids:
            w = W[wid]
            hidden = bool(w.get("hidden"))
            chips, notes = [], []
            if hidden:
                chips.append(_chip("it-hid", "hidden"))
            if w.get("hero"):
                chips.append(_chip("b", "%s only" % _hero_name(w["hero"]).lower()))
            lc, ln = _lock_chips("weapon", wid)
            chips += lc
            notes += ln
            for cid, c in playable.items():
                if c.get("start_weapon") == wid:
                    chips.append(_chip("g", "start · %s" % c.get("name", cid).lower()))
                if c.get("favourite_weapon") == wid:
                    chips.append(_chip("p", "favourite · %s" % c.get("name", cid).lower()))
            rows.append('      <tr class="it-w%s"><td class="it-i">%s</td><td><span class="name">%s</span><span class="sub">%s</span></td><td>%s <span class="it-beh">%s</span></td><td class="it-what">%s</td>%s</tr>' % (
                " it-off" if hidden else "", _ico("weapons", wid, 44), _esc(w.get("name", wid)), _esc(w.get("flavour", "")),
                _chip("w", "weapon"), _esc(_BEHAVIOUR.get(w.get("behavior", ""), w.get("behavior", ""))), _esc(_stat_line(w)),
                _status_cell(chips, notes)))
            muts = [m for m in M.values() if m.get("weapon") == wid]
            muts.sort(key=lambda m: (_MUT_KIND.get(m.get("kind", ""), 9), m.get("hero", ""), m.get("name", "")))
            for m in muts:
                mchips = []
                off = hidden
                if m.get("hero"):
                    mchips.append(_chip("b", "%s only" % _hero_name(m["hero"]).lower()))
                    if _hero_hidden(m["hero"]):
                        mchips.append(_chip("it-hid", "hidden", "its hero is hidden"))
                        off = True
                if hidden:
                    mchips.append(_chip("it-hid", "hidden", "its weapon is hidden"))
                elif m.get("hidden"):
                    # pass 48: a mutation taken off the table is kept in its folder ("hidden": true) to come back later
                    mchips.append(_chip("it-hid", "hidden", "kept in the content, never offered"))
                    off = True
                rows.append('      <tr class="it-m%s"><td class="it-i">%s</td><td><span class="name"><span class="it-tree">└</span>%s</span></td><td>%s</td><td class="it-what">%s</td>%s</tr>' % (
                    " it-off" if off else "", _ico("mutations", m["id"], 32), _esc(m.get("name", m["id"])), _mut_kind_chip(m),
                    _esc(m.get("text", "")), _status_cell(mchips, default=False)))
            evo = E.get(w.get("evolves_into", ""))
            if evo:
                echips = []
                if evo.get("hero") or w.get("hero"):
                    echips.append(_chip("b", "%s only" % _hero_name(evo.get("hero") or w["hero"]).lower()))
                if hidden or evo.get("hidden"):
                    echips.append(_chip("it-hid", "hidden", "its weapon is hidden"))
                rows.append('      <tr class="it-e%s"><td class="it-i">%s</td><td><span class="name"><span class="it-tree">└</span>%s</span><span class="sub">%s</span></td><td>%s</td><td class="it-what"><span class="it-req">level %d + all %d mutations, at a chest</span> %s</td>%s</tr>' % (
                    " it-off" if (hidden or evo.get("hidden")) else "", _ico("evolutions", evo["id"], 36), _esc(evo.get("name", evo["id"])),
                    _esc(evo.get("flavour", "")), _chip("w it-evo", "evolution"),
                    # pass 48: an evolution needs the weapon at its top level and every one of its path mutations (hero ones not)
                    int(w.get("max_level", 8)), sum(1 for m in muts if not m.get("hero") and not m.get("hidden")),
                    _esc(_stat_line(evo)), _status_cell(echips, default=False)))
            # pass 48: the evolutions this weapon had before, kept hidden (an "evolved_from" it no longer evolves into)
            for old_id in sorted(k for k, e in E.items() if e.get("evolved_from") == wid and k != w.get("evolves_into", "") and e.get("hidden")):
                oe = E[old_id]
                rows.append('      <tr class="it-e it-off"><td class="it-i">%s</td><td><span class="name"><span class="it-tree">└</span>%s</span><span class="sub">%s</span></td><td>%s</td><td class="it-what">%s</td>%s</tr>' % (
                    _ico("evolutions", old_id, 36), _esc(oe.get("name", old_id)), _esc(oe.get("flavour", "")), _chip("w it-evo", "old evolution"),
                    _esc(_stat_line(oe)), _status_cell([_chip("it-hid", "hidden", "kept to bring back: un-hide it and point the weapon's evolves_into at it")], default=False)))
    return "\n".join(rows)


def _passive_effect(p):
    """What one level gives (the harm a trade names left to the trade), with any level that differs."""
    lv = p.get("levels", [])
    first = lv[0] if lv else []
    per = _describe_effects([e for e in first if not (p.get("trade") and _harms(e))])
    extras = []
    if not p.get("repeat_last_level", True) and len(lv) > 1:
        for k, step in enumerate(lv[1:], start=2):
            ex = [e for e in step if not (p.get("trade") and _harms(e))]
            if ex and ex != first:
                extras.append("level %d: %s" % (k, _describe_effects(ex)))
    text = p.get("text", "")
    if text:
        # its own words say how it scales; the first level's numbers are enough beside them
        return text + (" · " + per if per else "")
    return per + ((" (" + "; ".join(extras) + ")") if extras else "")


def _passive_chips(pid, p, D):
    chips, notes = [], []
    if p.get("hidden"):
        chips.append(_chip("it-hid", "hidden"))
    if int(p.get("from_stage", 0)) > 1:
        chips.append(_chip("e", "stage %d+" % int(p["from_stage"])))
    lc, ln = _lock_chips("passive", pid)
    chips += lc
    notes += ln
    for cid, c in D["characters"].items():
        if not c.get("hidden") and c.get("favourite_passive") == pid:
            chips.append(_chip("p", "favourite · %s" % c.get("name", cid).lower()))
    return chips, notes


def _element_chip(p):
    el = p.get("element", "")
    return (" " + _chip("e" if el == "fire" else "g", el)) if el else ""


def _is_line(p):
    """A line item (pass 47: "line": true in its JSON, 6 slots beside the weapons, 4 levels, evolves); before the flag the
    evolving passives were the lines."""
    return bool(p.get("line") or p.get("evolves_into") or p.get("evolves_from"))


def _rarity_chip(p):
    """A passive item's rarity, in its World of Warcraft colour (the game shows it as the plate's colour)."""
    r = p.get("rarity", "common")
    r = r if r in RARITY_PLATE else "common"
    return " " + _chip("it-r it-r-" + r, r)


def item_line_rows():
    D = _items()
    P = D["passives"]
    rows = []
    for pid in sorted((k for k, p in P.items() if _is_line(p) and not p.get("evolves_from")), key=lambda k: P[k].get("name", k)):
        p = P[pid]
        chips, notes = _passive_chips(pid, p, D)
        evo = P.get(p.get("evolves_into", ""), {})
        ecell = "—"
        if evo:
            efx = _passive_effect(evo)
            ecell = '<div class="it-evocell">%s<div><span class="name">%s</span><span class="sub">%s%s</span></div></div>' % (
                _ico("passives", evo["id"], 32), _esc(evo.get("name", "")), _esc(efx),
                (" · trade: " + _esc(evo["trade"])) if evo.get("trade") else "")
        rows.append('      <tr class="it-l%s"><td class="it-i">%s</td><td><span class="name">%s</span><span class="sub">%s</span></td><td class="it-what">%s</td><td data-label="trade">%s</td><td class="num" data-label="levels">%d</td><td data-label="evolves into">%s</td>%s</tr>' % (
            " it-off" if p.get("hidden") else "", _ico("passives", pid, 40), _esc(p.get("name", pid)), _esc(p.get("flavour", "")),
            _esc(_passive_effect(p)), _esc(p.get("trade") or "none"), int(p.get("max_level", 5)), ecell, _status_cell(chips, notes)))
    return "\n".join(rows)


def item_passive_rows():
    D = _items()
    P = D["passives"]
    locks = _locks()
    ids = [k for k, p in P.items() if not _is_line(p)]
    # open first, then the locked, then the stage-gated, then the hidden; by name inside each
    def grp(k):
        p = P[k]
        return 3 if p.get("hidden") else (2 if int(p.get("from_stage", 0)) > 1 else (1 if ("passive", k) in locks else 0))
    rows = []
    def rank(k):
        r = P[k].get("rarity", "common")
        return RARITY_ORDER.index(r) if r in RARITY_ORDER else 0
    for pid in sorted(ids, key=lambda k: (grp(k), rank(k), P[k].get("name", k))):
        p = P[pid]
        chips, notes = _passive_chips(pid, p, D)
        rows.append('      <tr class="it-p%s"><td class="it-i">%s</td><td><span class="name">%s</span>%s%s<span class="sub">%s</span></td><td class="it-what">%s</td><td class="num" data-label="levels">%d</td>%s</tr>' % (
            " it-off" if p.get("hidden") else "", _ico("passives", pid, 40), _esc(p.get("name", pid)), _rarity_chip(p), _element_chip(p), _esc(p.get("flavour", "")),
            # a passive item's price (Beer's max HP) is its trade: this table has no trade column, so it rides in the text
            _esc(_passive_effect(p) + ((" · trade: " + p["trade"]) if p.get("trade") else "")), int(p.get("max_level", 5)), _status_cell(chips, notes)))
    return "\n".join(rows)


def item_hero_rows():
    """Section 08 (pass 53, Garry: "Items doesn't feature any of the hero specific items. They should be featured as
    grouped to the hero (with their icon to boot)"): under each hero (its portrait icon), the perks (icons; a hidden one
    greyed and said), its own weapon, the evolution and the hero mutation; the favourite is a chip. Hidden heroes last."""
    D = _items()
    C, P, W, E, M, PS = D["characters"], D["perks"], D["weapons"], D["evolutions"], D["mutations"], D["passives"]
    rows = []
    order = sorted(C, key=lambda k: (bool(C[k].get("hidden")), C[k].get("name", k)))
    for cid in order:
        c = C[cid]
        hidden_hero = bool(c.get("hidden"))
        perks = sorted((p for p in P.values() if p.get("hero") == cid), key=lambda p: p.get("name", ""))
        own = sorted((w for w in W.values() if w.get("hero") == cid), key=lambda w: w.get("name", ""))
        hm = sorted((m for m in M.values() if m.get("hero") == cid), key=lambda m: m.get("name", ""))
        fav = W.get(c.get("favourite_weapon", ""), {}).get("name", "") or PS.get(c.get("favourite_passive", ""), {}).get("name", "")
        n = len(perks) + len(own) + len(hm) + sum(1 for w in own if E.get(w.get("evolves_into", "")))
        head = '%s <span class="name">%s</span> <span class="sub">%s%s%s</span>' % (
            _ico("characters", cid, 36), _esc(c.get("name", cid)),
            _esc(c.get("trait_name", "")), (" · favourite: " + _esc(fav)) if fav else "", " · hidden hero" if hidden_hero else "")
        rows.append('      <tr class="it-grp it-hero%s"><td colspan="5">%s · %d</td></tr>' % (" it-off" if hidden_hero else "", head, n))
        for p in perks:
            off = hidden_hero or bool(p.get("hidden"))
            chips = [_chip("it-hid", "hidden", "kept in the content, never offered")] if p.get("hidden") else []
            rows.append('      <tr class="it-p%s"><td class="it-i">%s</td><td><span class="name">%s</span></td><td>%s</td><td class="it-what">%s</td>%s</tr>' % (
                " it-off" if off else "", _ico("perks", p["id"], 36), _esc(p.get("name", p["id"])), _chip("k", "perk"),
                _esc(p.get("text", "")), _status_cell(chips, default=not off)))
        for w in own:
            off = hidden_hero or bool(w.get("hidden"))
            chips = [_chip("g", "start")] if c.get("start_weapon") == w["id"] else []
            if w.get("hidden"):
                chips.append(_chip("it-hid", "hidden"))
            rows.append('      <tr class="it-w%s"><td class="it-i">%s</td><td><span class="name">%s</span><span class="sub">%s</span></td><td>%s</td><td class="it-what">%s</td>%s</tr>' % (
                " it-off" if off else "", _ico("weapons", w["id"], 44), _esc(w.get("name", w["id"])), _esc(w.get("flavour", "")),
                _chip("w", "weapon"), _esc(_stat_line(w)), _status_cell(chips, default=not off)))
            evo = E.get(w.get("evolves_into", ""))
            if evo:
                rows.append('      <tr class="it-e%s"><td class="it-i">%s</td><td><span class="name"><span class="it-tree">└</span>%s</span><span class="sub">%s</span></td><td>%s</td><td class="it-what">%s</td>%s</tr>' % (
                    " it-off" if off or evo.get("hidden") else "", _ico("evolutions", evo["id"], 36), _esc(evo.get("name", evo["id"])),
                    _esc(evo.get("flavour", "")), _chip("w it-evo", "evolution"), _esc(_stat_line(evo)), _status_cell([], default=False)))
        for m in hm:
            off = hidden_hero or bool(m.get("hidden"))
            rows.append('      <tr class="it-m%s"><td class="it-i">%s</td><td><span class="name">%s</span><span class="sub">on the %s</span></td><td>%s</td><td class="it-what">%s</td>%s</tr>' % (
                " it-off" if off else "", _ico("mutations", m["id"], 32), _esc(m.get("name", m["id"])),
                _esc(W.get(m.get("weapon", ""), {}).get("name", m.get("weapon", ""))), _mut_kind_chip(m), _esc(m.get("text", "")),
                _status_cell([_chip("it-hid", "hidden")] if m.get("hidden") else [], default=False)))
    return "\n".join(rows)


def item_counts():
    """The numbers in the Items section's opening line."""
    D = _items()
    W, E, M, P = D["weapons"], D["evolutions"], D["mutations"], D["passives"]
    hw = sum(1 for w in W.values() if w.get("hidden"))
    hm = sum(1 for m in M.values() if m.get("hero"))
    lines = sum(1 for p in P.values() if _is_line(p) and not p.get("evolves_from"))
    plain = sum(1 for p in P.values() if not _is_line(p))
    locked = len(_locks())
    return ("<b>%d weapons</b> (%d hidden), each with its mutations (<b>%d</b> in all, %d of them a hero's own) and its evolution (<b>%d</b>); "
            "<b>%d lines</b> and the %d they evolve into; <b>%d passive items</b>. %d of the weapons, lines and passives are locked "
            "behind a quest.") % (len(W), hw, len(M), hm, len(E), lines, lines, plain, locked)


def unlock_rows():
    """Section 13's unlocks table, from content/quests: what each quest opens, its words and the stage that can do it."""
    D = _items()
    rows = []
    for q in sorted(D["quests"].values(), key=lambda q: (quest_stage(q) or 9, q.get("name", ""))):
        u = q.get("unlocks", {})
        t = u.get("type", "")
        src = {"weapon": "weapons", "passive": "passives", "character": "characters"}.get(t, "")
        it = D.get(src, {}).get(u.get("id", ""), {}) if src else {}
        if t == "character" and it.get("hidden"):
            continue
        kind = "line" if t == "passive" and _is_line(it) else ("hero" if t == "character" else t)
        cls = {"weapon": "w", "passive": "p", "line": "p", "hero": "b"}.get(kind, "")
        ico = _ico(src, u.get("id", ""), 28) if src in ("weapons", "passives") else ""
        st = quest_stage(q)
        rows.append('      <tr><td class="it-i">%s</td><td><span class="name">%s</span></td><td>%s</td><td>%s</td><td class="num">%s</td></tr>' % (
            ico, _esc(it.get("name", q.get("name", ""))), _chip(cls, kind), _esc(quest_text(q)), st if st else "any"))
    return "\n".join(rows)


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
    # {{PASSIVES}} is the passives table (pass 46); {{LINES}}, its name while the lines were apart, still fills it
    html = html.replace("{{MUTATIONS}}", mutation_rows()).replace("{{PASSIVES}}", passive_rows()).replace("{{LINES}}", passive_rows())
    html = html.replace("{{PERKS}}", perk_rows()).replace("{{TALENTS}}", talent_rows())
    # 08 Items (2026-10-02): every weapon with its mutations and evolution, the lines, the passives; 13's unlocks
    # the plate colours the game uses (pass 47), for the Items legend's swatches
    for k, v in PLATE.items():
        html = html.replace("{{PLATE:%s}}" % k, v)
    for k, v in RARITY_PLATE.items():
        html = html.replace("{{RARITY:%s}}" % k, v)
    html = html.replace("{{ITEM_COUNTS}}", item_counts()).replace("{{ITEM_WEAPONS}}", item_weapon_rows())
    html = html.replace("{{ITEM_LINES}}", item_line_rows()).replace("{{ITEM_PASSIVES}}", item_passive_rows()).replace("{{UNLOCKS}}", unlock_rows())
    html = html.replace("{{ITEM_HERO}}", item_hero_rows())
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

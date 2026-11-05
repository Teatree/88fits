# -*- coding: utf-8 -*-
"""Pass 126 (lane IDEAS; Garry: "It currently doesn't look very presentable ... I don't like that it looks like that"): the phone mocks
of the ideas book's Upgrade board section, as inline HTML/CSS/SVG in the game's real look (game/ui/wanted/R.gd's tokens, Ultra and
Rubik, the real icons from game/content, the real menu backdrop). Used by tools/make_ideas_doc.py; the words and the tree live in
docs/ideas/content.py.

A mock's sizes are written in `u`: 1u is 3 canvas px of the game's 1080 x 1920 canvas, so a phone is 360u wide. U() turns "14u" into
calc(14*var(--u)), where --u is 1/360 of the phone's own width (a container unit), so a mock stays sharp and in proportion at any
width. Every asset is embedded once, as a CSS class, however often the mocks use it.
"""
import base64
import html
import io
import os
import re

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GAME = os.path.join(ROOT, "game")
ART = os.path.join(ROOT, "docs", "ideas", "art")
TODAY = os.path.join(ROOT, "tools", "dl", "p126", "IDEAS", "today")
TODAY_KEPT = os.path.join(ROOT, "docs", "ideas", "art")

VERY_GOOD_RUN = 1140
PH = 760  # a phone's height in u: 360 x 760 is the Pixel 8 Pro's shape under its status bar


def U(s):
    return re.sub(r"(?<![\w.#-])(-?\d+(?:\.\d+)?)u\b", lambda m: "calc(%s*var(--u))" % m.group(1), s)


def num(n):
    return "{:,}".format(int(round(n)))


def esc(s):
    return html.escape(str(s), quote=False)


# ------------------------------------------------------------------------------------------------ assets

ICONS = {
    # the sixteen forms
    "drive_0": "content/talents/drive/drive_0_icon.png", "drive_1": "content/talents/drive/drive_1_icon.png",
    "grit_0": "content/talents/grit/grit_0_icon.png", "grit_1": "content/talents/grit/grit_1_icon.png",
    "stride_0": "content/talents/stride/stride_0_icon.png", "stride_1": "content/talents/stride/stride_1_icon.png",
    "study_0": "content/talents/study/study_0_icon.png", "study_1": "content/talents/study/study_1_icon.png",
    "fortune_0": "content/talents/fortune/fortune_0_icon.png", "fortune_1": "content/talents/fortune/fortune_1_icon.png",
    "choice_0": "content/talents/choice/choice_0_icon.png", "choice_1": "content/talents/choice/choice_1_icon.png",
    "nerve_0": "content/talents/nerve/nerve_0_icon.png", "nerve_1": "content/talents/nerve/nerve_1_icon.png",
    "spite_0": "content/talents/spite/spite_0_icon.png", "spite_1": "content/talents/spite/spite_1_icon.png",
    # milestones wear icons the game already has
    "m_deadeye": "content/passives/deadeye/deadeye_icon.png", "m_stakes": "content/talents/spite/spite_0_icon.png",
    "m_area": "content/passives/reach/reach_icon.png", "m_cards": "content/passives/hot_streak/hot_streak_icon.png",
    "m_iron": "content/weapons/revolver/revolver_icon.png", "m_revive": "content/passives/phoenix_feather/phoenix_feather_icon.png",
    "m_amount": "content/passives/multishot/multishot_icon.png", "m_legend": "content/passives/tin_star/tin_star_icon.png",
    # heroes' round badges, in the look each one plays
    "drifter_icon": "content/characters/drifter/drifter_icon.png", "ironwood_icon": "content/characters/ironwood/ironwood_icon.png",
    "astro_icon": "content/characters/astro/astro_icon.png", "calavera_icon": "content/characters/calavera/calavera_icon.png",
    "solenne_icon": "content/characters/solenne/solenne_icon.png", "fadeaway_icon_c": "content/characters/fadeaway/fadeaway_icon_c.png",
    "buck_icon_f": "content/characters/buck/buck_icon_f.png", "may_icon_p": "content/characters/may/may_icon_p.png",
    # the tab bar's own icons, the coin
    "tab_store": "content/passives/hush_money/hush_money_icon.png", "tab_battle": "content/weapons/revolver/revolver_icon.png",
    "tab_coll": "content/passives/field_notes/field_notes_icon_b.png", "coin": "art/ui/wanted/coin.png",
    "guitarra": "content/weapons/guitarra/guitarra_icon.png",
}
CUTOUTS = {"drifter": "art/ui/wanted/hero_drifter.png", "calavera": "art/ui/wanted/hero_calavera.png", "ironwood": "art/ui/wanted/hero_ironwood.png"}
BUILDINGS = ["pouch_silver", "st_sheriff", "st_chapel", "st_fortune", "st_saloon", "st_doc", "st_livery", "st_outfitter", "st_gun1", "st_gun2", "st_gun3", "st_gun4"]


def _b64_image(im, fmt, **kw):
    buf = io.BytesIO()
    im.save(buf, fmt, **kw)
    return base64.b64encode(buf.getvalue()).decode()


def _webp(path, px, q=80):
    im = Image.open(path).convert("RGBA")
    im.thumbnail((px, px), Image.LANCZOS)
    return "data:image/webp;base64," + _b64_image(im, "WEBP", quality=q, method=6)


def asset_css():
    out = []
    for k, p in ICONS.items():
        px = 112 if k.startswith("tab_") or k == "coin" else 168
        out.append(".ic-%s{background-image:url(%s)}" % (k, _webp(os.path.join(GAME, p), px)))
    for k, p in CUTOUTS.items():
        out.append(".cut-%s{background-image:url(%s)}" % (k, _webp(os.path.join(GAME, p), 620, 82)))
    for k in BUILDINGS:
        p = os.path.join(ART, k + ".webp")
        if os.path.exists(p):
            out.append(".bd-%s{background-image:url(data:image/webp;base64,%s)}" % (k, base64.b64encode(open(p, "rb").read()).decode()))
    plate = Image.open(os.path.join(GAME, "art/ui/royale/backdrop_plate.jpg")).convert("RGB")
    plate.thumbnail((600, 1334), Image.LANCZOS)
    out.append(".plate{background-image:url(data:image/jpeg;base64,%s)}" % _b64_image(plate, "JPEG", quality=68, optimize=True))
    return "\n".join(out)


def today_img(name, alt):
    """A capture of today's screen (kept in docs/ideas/art so the page rebuilds without tools/dl)."""
    p = os.path.join(TODAY_KEPT, "today_" + name + ".jpg")
    return '<img src="data:image/jpeg;base64,%s" alt="%s">' % (base64.b64encode(open(p, "rb").read()).decode(), html.escape(alt, quote=True))


def keep_today_captures():
    """Copies tools/dl/p126/IDEAS/today/*.png into docs/ideas/art as small JPEGs when the captures are newer."""
    for name, src in (("board", "03-mirror.png"), ("short", "03d-mirror-many-held.png"), ("choose", "03b-mirror-talent-open.png")):
        s = os.path.join(TODAY, src)
        d = os.path.join(TODAY_KEPT, "today_" + name + ".jpg")
        if os.path.exists(s) and (not os.path.exists(d) or os.path.getmtime(s) > os.path.getmtime(d)):
            im = Image.open(s).convert("RGB")
            im.thumbnail((640, 1138), Image.LANCZOS)
            im.save(d, "JPEG", quality=80, optimize=True)


# ------------------------------------------------------------------------------------------------ the tree's numbers

def round_price(p):
    return int(round(p / 25.0) * 25) if p < 2000 else int(round(p / 50.0) * 50)


def plain_price(n):
    return round_price(100 + 3 * n * n)


def expand_tree(C):
    """TREE_SECTIONS into rows with their numbers. A fork takes three rows; `entries` holds it once."""
    entries = []
    n = 0
    fork_i = mile_i = 0
    for si, sec in enumerate(C.TREE_SECTIONS):
        for r in sec["rows"]:
            if r[0] == "plain":
                n += 1
                entries.append(dict(kind="plain", n=n, sec=si, name=r[1], icon=C.FORMS[r[2]]["icon"], effect=r[3], price=plain_price(n)))
            elif r[0] == "hero":
                n += 1
                h = C.HEROES[r[1]]
                entries.append(dict(kind="hero", n=n, sec=si, id=r[1], name=h["name"], icon=h["icon"], weapon=h["weapon"], price=h["price"]))
            elif r[0] == "mile":
                n += 1
                mile_i += 1
                entries.append(dict(kind="mile", n=n, sec=si, name=r[1], icon=r[2], effect=r[3], price=2 * plain_price(n), idx=mile_i))
            else:
                fork_i += 1
                entries.append(dict(kind="fork", n=n + 1, sec=si, a=r[1], b=r[2], idx=fork_i, prices=[plain_price(n + 1 + k) for k in range(3)]))
                n += 3
    return entries


def tree_stats(C):
    """Numbers the words quote: gold and ranks up the tree against today's board."""
    entries = expand_tree(C)
    rows = []  # (n, gold so far, ranks held so far, kind)
    gold = 0
    ranks = 0
    gold_noheroes = 0
    for e in entries:
        if e["kind"] == "fork":
            for k, p in enumerate(e["prices"]):
                gold += p
                gold_noheroes += p
                ranks += 1
                rows.append((e["n"] + k, gold, ranks, "fork", gold_noheroes))
        else:
            gold += e["price"]
            if e["kind"] != "hero":
                gold_noheroes += e["price"]
            if e["kind"] == "plain":
                ranks += 1
            rows.append((e["n"], gold, ranks, e["kind"], gold_noheroes))
    # today's board without Stakes, cheapest first (a valid order: a talent's prices rise with its rank)
    firsts = [150, 300, 325, 375, 400, 425, 450]
    today = sorted(k * k * r for r in firsts for k in range(1, 8))
    def today_gold(rk):
        return sum(today[:rk])
    def tree_gold_noheroes(rk):
        for r in rows:
            if r[2] >= rk:
                return r[4]
        return rows[-1][4]
    secs = []
    for si, sec in enumerate(C.TREE_SECTIONS):
        ns = [e for e in entries if e["sec"] == si]
        first = ns[0]["n"]
        last = ns[-1]["n"] + (2 if ns[-1]["kind"] == "fork" else 0)
        g0 = next((r[1] for r in rows if r[0] == first - 1), 0)
        g1 = next(r[1] for r in rows if r[0] == last)
        r1 = next(r[2] for r in rows if r[0] == last)
        secs.append(dict(name=sec["name"], ready=sec["ready"], first=first, last=last, gold=g1 - g0, cum=g1, ranks=r1,
                         forks=sum(1 for e in ns if e["kind"] == "fork"), miles=sum(1 for e in ns if e["kind"] == "mile"), heroes=sum(1 for e in ns if e["kind"] == "hero")))
    compare = [(rk, today_gold(rk), tree_gold_noheroes(rk)) for rk in (6, 12, 19, 26, 36, 49)]
    return dict(entries=entries, rows=rows, secs=secs, compare=compare, total=rows[-1][1], total_power=rows[-1][4], heroes=sum(h["price"] for h in C.HEROES.values()),
                today_full=sum(k * k for k in range(1, 8)) * 2525, today_no_stakes=sum(today))


def belt_stats(C):
    firsts = dict(muscle=375, padding=450, boots=425, notes=400, omen=300, wind=150)
    pouches = 600 + 1500 + 4000
    lv = lambda L: sum(k * k for k in range(1, L + 1))
    six = sum(firsts.values())
    return dict(half=lv(3) * six + pouches, full=lv(5) * six + pouches, all=lv(5) * 2 * 2525 + pouches, pouches=pouches)


def fill_words(s, st, bt):
    return s.format(b_half=num(bt["half"]), today_half=num(14 * 2525), b_full=num(bt["full"]), b_full_runs=num(bt["full"] / VERY_GOOD_RUN), b_all=num(bt["all"]),
                    a_total=num(st["total"]), a_runs=num(st["total"] / VERY_GOOD_RUN))


# ------------------------------------------------------------------------------------------------ the kit, as CSS

KIT_CSS = U("""
.phones{display:grid;gap:26px 20px;grid-template-columns:repeat(auto-fill,minmax(min(100%,330px),1fr));margin:14px 0 20px}
figure.ph{margin:0;min-width:0}
.spanrest{grid-column:1/-1;min-width:0;align-self:start}
@media (min-width:1100px){.spanrest{grid-column:span 2}}
figure.ph figcaption{padding:12px 2px 0;color:var(--dim);font-size:15px}
figure.ph figcaption b{color:var(--ink)}
.phw{container-type:inline-size;width:100%;max-width:410px;margin:0 auto}
.sc{--u:calc(100cqw/360);position:relative;width:100%;aspect-ratio:360/760;overflow:hidden;border-radius:16u;background-color:#0a1024;background-size:cover;background-position:center;font-family:var(--body);color:#fff;box-shadow:0 0 0 3px #05070f,0 0 0 4px #39456a;line-height:1.15;text-align:left;isolation:isolate}
.sc *{box-sizing:border-box}
.sc p{margin:0;max-width:none}
.abs{position:absolute}
.ic{display:block;background-repeat:no-repeat;background-position:center;background-size:contain}
.ul{font-family:var(--display);font-weight:400;color:#fff6dc;letter-spacing:.01em;text-shadow:.05em 0 #0e1f4a,-.05em 0 #0e1f4a,0 .05em #0e1f4a,0 -.05em #0e1f4a,.04em .04em #0e1f4a,-.04em .04em #0e1f4a,.04em -.04em #0e1f4a,-.04em -.04em #0e1f4a,0 .1em 0 #0e1f4a}
.ul.gd{color:#ffdc73}
.lab{font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:#cfe3ff}
.hi{color:#ffe48a;font-weight:700}
.dimw{position:absolute;inset:0;background:linear-gradient(rgba(8,12,28,.5),rgba(8,12,28,.5))}
.sheet{position:absolute;background:rgba(13,19,43,.72);border:1u solid rgba(14,31,74,.9);border-radius:2u}
/* header */
.hd-back{position:absolute;left:14u;top:20u;width:30u;height:33u;border-radius:2u;border:1.33u solid #0e1f4a;background:linear-gradient(#4a5670 44%,#2f3a50 44%);box-shadow:0 2.67u 0 #141b2b,0 4u 0 #0e1f4a;color:#fff6dc;font:400 14u/28u var(--display);text-align:center}
.hd-t{position:absolute;left:54u;top:22u;font-size:21u;line-height:28u}
.wal{position:absolute;right:13u;top:23u;height:24u;padding:0 7u 0 5u;display:flex;align-items:center;gap:4u;background:rgba(8,10,18,.72);box-shadow:inset 0 0 0 .67u rgba(255,255,255,.08);border-radius:1.5u;font:400 12u/1 var(--display);color:#fff}
.wal .ic{width:15u;height:15u}
/* the tab bar */
.band{position:absolute;left:0;right:0;bottom:0;height:66.7u;background:linear-gradient(#27314a,#1a2238);border-top:1.33u solid #0e1f4a;box-shadow:inset 0 1u 0 rgba(255,255,255,.1)}
.tabs{position:absolute;left:8u;right:8u;bottom:0;height:74.7u;display:flex;gap:3.33u;align-items:flex-end}
.tab{position:relative;flex:1 1 0;min-width:0;height:58.7u;border-radius:2.67u 2.67u 0 0;border:1.33u solid #0e1f4a;border-bottom:0;background:linear-gradient(#4a5670 44%,#2f3a50 44%);display:flex;flex-direction:column;align-items:center;justify-content:flex-end;padding-bottom:7u;gap:2u}
.tab .ic{width:27u;height:27u}
.tab .w{font:400 6.2u/1 var(--display);color:#fff6dc;text-shadow:0 .6u 0 #0e1f4a;white-space:nowrap}
.tab.on{flex:1.4 1 0;height:74.7u;background:linear-gradient(#ffdc73 44%,#f5b82a 44%)}
.tab.on .ic{width:34.7u;height:34.7u}
.tab.on .w{font-size:8.2u;color:#0e1f4a;text-shadow:none}
.tab.lk{background:linear-gradient(#8f98ab 44%,#6b7488 44%)}
.tab.lk .ic{filter:grayscale(.85) brightness(.8)}
.tab.lk .w{color:#c8cdd8}
.badge{position:absolute;right:-3u;top:-5u;width:15u;height:15u;border-radius:50%;background:#27314a;border:1.2u solid #0e1f4a;color:#ffdc73;font:700 8u/12.6u var(--body);text-align:center}
.tab .round{border-radius:50%;box-shadow:0 0 0 1.33u #0e1f4a;background-color:#27314a}
/* item frames: the game's radial rarity fill, a rim and a navy outline */
.fr{position:absolute;display:block;border-radius:2u;box-shadow:0 0 0 1u #0e1f4a;border:1.6u solid var(--rim);background:radial-gradient(circle at 50% 42%,var(--l),var(--b) 55%,var(--d))}
.fr>.ic{position:absolute;inset:6%;filter:drop-shadow(0 .7u 0 rgba(0,0,0,.35))}
.r-common{--l:#cdd5de;--b:#95a1b0;--d:#67727f;--rim:#e4e9ee}
.r-uncommon{--l:#9fe18b;--b:#63c944;--d:#419529;--rim:#d5ffc9}
.r-rare{--l:#7cc9ff;--b:#2f8de6;--d:#1c5aa8;--rim:#b4e1ff}
.r-epic{--l:#de9fff;--b:#a650e8;--d:#6a2bb0;--rim:#f0ccff}
.r-epic.glow{box-shadow:0 0 0 1u #0e1f4a,0 0 8u rgba(166,80,232,.85)}
.r-legend{--l:#ffea92;--b:#f6b72a;--d:#c47d0a;--rim:#fff5c0;border-width:2.6u;border-image:linear-gradient(#fff5c0,#f6b72a 40%,#c47d0a 70%,#ffe28a) 1;border-radius:0;box-shadow:0 0 0 1u #0e1f4a,0 0 11u rgba(246,183,42,.95)}
.r-locked{--l:#8f98ab;--b:#6b7488;--d:#363c4a;--rim:#aab2c2}
.fr.off{--l:#4a5570;--b:#343e58;--d:#232b42;--rim:#5d6a88}
.fr.off>.ic{filter:grayscale(.92) brightness(.82)}
.fr.shut{--l:#232a3e;--b:#1a2030;--d:#121725;--rim:#2b334a;box-shadow:0 0 0 1u #0a1228}
.fr.shut>.ic{filter:grayscale(1) brightness(.32)}
.pq{position:absolute;left:50%;bottom:-4.5u;transform:translateX(-50%);height:10u;padding:0 2.4u;display:flex;align-items:center;background:linear-gradient(#fff,#e4e8ef);color:#0b0d14;font:700 7u/1 var(--body);border:1u solid #0e1f4a;border-radius:1.3u;white-space:nowrap}
.check{position:absolute;right:-3u;top:-3u;width:12u;height:12u;border-radius:50%;background:#5fc43a;border:1u solid #0e1f4a;color:#fff;font:800 7.5u/10u var(--body);text-align:center}
.up{position:absolute;right:-3u;top:-3u;width:12u;height:12u;border-radius:50%;background:#e2402f;border:1u solid #0e1f4a;color:#fff;font:800 8u/10u var(--body);text-align:center}
.xx{position:absolute;inset:0;background:linear-gradient(45deg,transparent 46%,rgba(226,64,47,.55) 46%,rgba(226,64,47,.55) 54%,transparent 54%),linear-gradient(-45deg,transparent 46%,rgba(226,64,47,.55) 46%,rgba(226,64,47,.55) 54%,transparent 54%)}
.ring{position:absolute;border-radius:6u;box-shadow:0 0 0 1.6u #ffdc73,0 0 10u 2u rgba(255,220,115,.85);pointer-events:none}
/* buttons: colour says what it does */
.btn{position:absolute;display:flex;align-items:center;justify-content:center;gap:2.4u;border-radius:2u;border:1.33u solid #0e1f4a;box-shadow:0 2.67u 0 var(--base),0 4u 0 #0e1f4a;background:linear-gradient(var(--top) 44%,var(--bot) 44%);font-family:var(--display);color:#fff6dc;white-space:nowrap;text-shadow:.05em 0 #0e1f4a,-.05em 0 #0e1f4a,0 .05em #0e1f4a,0 -.05em #0e1f4a,0 .08em 0 #0e1f4a}
.btn::before{content:"";position:absolute;left:0;right:0;top:0;height:1u;background:rgba(255,255,255,.45)}
.btn .ic{width:1.15em;height:1.15em;flex:none}
.b-green{--top:#a3ea74;--bot:#5fc43a;--base:#2a7416}
.b-blue{--top:#4a8ae0;--bot:#2360bd;--base:#123375}
.b-gold{--top:#ffdc73;--bot:#f5b82a;--base:#a86d06;color:#0e1f4a;text-shadow:none}
.b-slate{--top:#4a5670;--bot:#2f3a50;--base:#141b2b}
.b-short{--top:#8f98ab;--bot:#6b7488;--base:#363c4a;color:#ff8e7e}
/* panels */
.slate{position:absolute;border-radius:2u;border:1.33u solid #0e1f4a;background:linear-gradient(#3a4661,#27314a 60%,#1f2840);box-shadow:0 2.67u 0 #0e1f4a,inset 0 1u 0 rgba(255,255,255,.14)}
.cell{position:relative;background:#1a2238;border:1u solid #0e1f4a;border-radius:2u}
.plateb{position:absolute;background:rgba(8,10,18,.68);box-shadow:inset 0 0 0 .67u rgba(255,255,255,.08);border-radius:1.5u}
.scrim{position:absolute;inset:0;background:rgba(0,0,0,.8)}
.modal{position:absolute;left:15u;width:330u;border-radius:2u;border:1.33u solid #1b3a86;background:linear-gradient(#3e4b68,#2a3550 60%,#222b45);box-shadow:0 2.67u 0 #0e1f4a,inset 0 1u 0 rgba(255,255,255,.14);padding:12u 13u 16u;display:flex;flex-direction:column;gap:6u}
.star{font:400 8.4u/1 var(--display);color:#ffdc73;letter-spacing:.24em;text-align:center;text-shadow:0 .08em 0 #0e1f4a}
.mtitle{font-size:21u;line-height:1.05;text-align:center}
.flav{font:italic 500 9u/1.2 var(--body);color:#cfe3ff;text-align:center}
.note{font:500 8u/1.25 var(--body);color:#cfe3ff;text-align:center}
.rays{position:absolute;border-radius:50%;background:repeating-conic-gradient(from 0deg,rgba(255,230,150,.35) 0 8deg,transparent 8deg 20deg);-webkit-mask:radial-gradient(circle,#000 30%,transparent 70%);mask:radial-gradient(circle,#000 30%,transparent 70%)}
/* the tree */
.tree{position:absolute;left:0;width:100%}
.tree svg{position:absolute;left:0;top:0;width:100%;height:100%;overflow:visible}
.nl{position:absolute;font-size:7.6u;line-height:1.16;color:#cfe3ff;white-space:normal}
.nl b{display:block;font-weight:700;color:#fff;font-size:8.6u}
.nl .pr{display:flex;align-items:center;gap:1.4u;color:#ffdc73;font-weight:700;margin-top:.8u}
.nl .pr .ic{width:8u;height:8u;flex:none}
.nl.off{color:#a7b2c9}
.nl.off b{color:#d3dae8}
.nl.off .pr{color:#c7b67a}
.nl.shut{color:#566079}
.nl.shut b{color:#667087;text-decoration:line-through}
.nl.r{text-align:right}
.nl.r .pr{justify-content:flex-end}
.forksign{position:absolute;left:125u;width:110u;text-align:center}
.forksign .ul{font-size:11.5u;display:block}
.forksign small{display:block;font:500 7.2u/1.15 var(--body);color:#cfe3ff;margin-top:1.5u}
.or{display:block;font:italic 500 9u/1 var(--body);color:#fff;margin-top:3u}
.ttag{position:absolute;padding:1.6u 3u;border-radius:1.3u;border:1u solid #0e1f4a;font:700 6.4u/1 var(--body);letter-spacing:.08em;background:#f5b82a;color:#0e1f4a;white-space:nowrap}
.tmile{font:400 11.5u/1.05 var(--display);color:#ffdc73}
.hround{position:absolute;border-radius:50%;background-color:#27314a;box-shadow:0 0 0 1.4u #0e1f4a,0 0 0 3.2u #ffdc73,0 0 0 4.4u #0e1f4a}
.hround.off{filter:grayscale(.9) brightness(.78);box-shadow:0 0 0 1.4u #0e1f4a,0 0 0 3.2u #6b7488,0 0 0 4.4u #0e1f4a}
.secband{position:absolute;left:0;right:0;height:16u;display:flex;align-items:center;justify-content:center;gap:5u;font:700 7.2u/1 var(--body);letter-spacing:.2em;text-transform:uppercase;color:#fff6dc}
.secband::before,.secband::after{content:"";flex:1;height:.8u;background:rgba(255,246,220,.4)}
.sky-sundown{--sky:linear-gradient(rgba(36,22,62,.72),rgba(20,18,50,.8))}
.sky-nightfall{--sky:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='260' height='260'%3E%3Cg fill='%23fff'%3E%3Ccircle cx='24' cy='32' r='1.1' opacity='.7'/%3E%3Ccircle cx='96' cy='12' r='.8' opacity='.5'/%3E%3Ccircle cx='160' cy='70' r='1.3' opacity='.6'/%3E%3Ccircle cx='230' cy='40' r='.8' opacity='.6'/%3E%3Ccircle cx='58' cy='120' r='.9' opacity='.45'/%3E%3Ccircle cx='200' cy='150' r='1' opacity='.6'/%3E%3Ccircle cx='128' cy='190' r='.8' opacity='.5'/%3E%3Ccircle cx='18' cy='220' r='1.2' opacity='.55'/%3E%3Ccircle cx='246' cy='236' r='.9' opacity='.5'/%3E%3C/g%3E%3C/svg%3E"),linear-gradient(rgba(10,20,60,.86),rgba(12,24,70,.82))}
.sky-dust{--sky:repeating-linear-gradient(168deg,rgba(255,214,150,.05) 0 7px,transparent 7px 46px),linear-gradient(rgba(70,44,18,.9),rgba(58,36,16,.86))}
.sky-blood{--sky:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='240' height='240'%3E%3Cg fill='%23ff9a5a'%3E%3Ccircle cx='30' cy='50' r='1.1' opacity='.55'/%3E%3Ccircle cx='150' cy='24' r='.8' opacity='.45'/%3E%3Ccircle cx='210' cy='120' r='1.2' opacity='.5'/%3E%3Ccircle cx='84' cy='170' r='.9' opacity='.45'/%3E%3Ccircle cx='180' cy='220' r='.8' opacity='.4'/%3E%3C/g%3E%3C/svg%3E"),linear-gradient(rgba(70,12,14,.9),rgba(52,10,16,.88))}
.thumb{position:absolute;right:1.6u;width:2.2u;border-radius:1.1u;background:rgba(255,255,255,.34)}
.dock{position:absolute;left:8u;right:8u;height:84u}
.dock .nm{position:absolute;left:66u;top:9u;right:6u;font:400 12u/1 var(--display);color:#fff6dc}
.dock .fx{position:absolute;left:66u;top:24u;right:6u;font:500 8.4u/1.1 var(--body);color:#cfe3ff}
.stripw{container-type:inline-size;width:100%}
.strip{--u:calc(100cqw/360);position:relative;width:100%;overflow:hidden;border-radius:6u;background-image:var(--sky),none;background-color:#0d1430;font-family:var(--body);color:#fff;line-height:1.15;box-shadow:0 0 0 1px #39456a}
.strip *{box-sizing:border-box}
.strip p{margin:0;max-width:none}
.strips{display:grid;gap:18px;grid-template-columns:repeat(auto-fill,minmax(min(100%,330px),1fr));align-items:end;margin:12px 0 16px}
.striph{font:700 13px/1.25 var(--body);letter-spacing:.06em;color:var(--dim);margin:0 0 6px}
/* Main Street */
.road{position:absolute;left:0;right:0;top:0;bottom:0;background:linear-gradient(90deg,transparent 0,transparent 36%,rgba(120,84,48,.32) 41%,rgba(120,84,48,.2) 50%,rgba(120,84,48,.32) 59%,transparent 64%,transparent 100%),linear-gradient(#ecd3a0,#e3bf85)}
.bd{position:absolute;background-repeat:no-repeat;background-position:center bottom;background-size:contain}
.lot{position:absolute;width:172u;height:150u}
.sign{position:absolute;left:50%;transform:translateX(-50%);bottom:0;min-width:118u;padding:3u 5u 3.5u;background:linear-gradient(#3a4661,#27314a);border:1.2u solid #0e1f4a;border-radius:1.6u;box-shadow:0 1.6u 0 #0e1f4a;text-align:center}
.sign .ul{font-size:9.6u;display:block;white-space:nowrap}
.pips{display:flex;gap:1.1u;justify-content:center;margin-top:2u}
.pips i{display:block;width:6.4u;height:6.4u;border-radius:1u;background:rgba(8,10,18,.6);background-size:contain;background-position:center;background-repeat:no-repeat}
.pips i.h{background-color:#95a1b0;box-shadow:0 0 0 .6u #0e1f4a}
.chip{position:absolute;right:6u;top:2u;height:13.5u;padding:0 3u;display:flex;align-items:center;gap:1.4u;border-radius:1.5u;border:1u solid #0e1f4a;font:700 7.6u/1 var(--body);color:#fff;box-shadow:0 1.2u 0 #0e1f4a}
.chip .ic{width:8u;height:8u}
.chip.ok{background:linear-gradient(#a3ea74 44%,#5fc43a 44%);text-shadow:0 .6u 0 #0e1f4a}
.chip.no{background:linear-gradient(#8f98ab 44%,#6b7488 44%);color:#ffb3a8;text-shadow:0 .6u 0 #0e1f4a}
.chip.wait{background:linear-gradient(#4a5670 44%,#2f3a50 44%);color:#cfe3ff}
.fig{position:absolute;background-repeat:no-repeat;background-position:center bottom;background-size:contain;filter:drop-shadow(0 1u 1u rgba(0,0,0,.35))}
/* the comparison and the rest of the page */
.cmp{width:100%;border-collapse:collapse;font-size:15px}
.cmp th,.cmp td{padding:9px 11px;text-align:left;vertical-align:top;border-bottom:1px solid var(--line)}
.cmp th{font:400 17px/1.2 var(--display);color:#fff6dc}
.cmp td:first-child{font-weight:700;color:var(--dim)}
@media (max-width:760px){.cmp thead{display:none}.cmp,.cmp tbody,.cmp tr,.cmp td{display:block}.cmp tr{padding:9px 4px;border-bottom:1px solid var(--line)}.cmp td{border:0;padding:2px 4px}.cmp td:first-child{font:700 13px/1.3 var(--body);letter-spacing:.06em;text-transform:uppercase;color:var(--gold);padding-bottom:4px}.cmp td[data-l]{display:grid;grid-template-columns:22px minmax(0,1fr)}.cmp td[data-l]::before{content:attr(data-l);font-weight:700;color:var(--dim)}.ectab{font-size:14px}.ectab th,.ectab td{padding:6px 6px}.ectab th{font-size:11.5px;letter-spacing:.02em}}
.cmpw{overflow-x:auto;background:var(--panel);padding:6px 8px;margin:10px 0 18px}
.ectab{width:100%;border-collapse:collapse;font-size:15px}
.ectab th,.ectab td{padding:7px 10px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
.ectab th{color:var(--dim);font-weight:700;font-size:13px;letter-spacing:.05em;text-transform:uppercase}
.ectab td.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.ectab th.n{text-align:right}
.ecw{overflow-x:auto;background:var(--panel);padding:4px 6px;margin:8px 0 14px}
.today{display:grid;gap:18px;grid-template-columns:repeat(auto-fit,minmax(min(100%,250px),1fr));align-items:start}
.today figure{margin:0;min-width:0}
.today figure img{max-width:300px;margin:0 auto;box-shadow:0 0 0 3px #05070f,0 0 0 4px #39456a;border-radius:10px}
.today figcaption{color:var(--dim);font-size:14.5px;padding:9px 2px 0;text-align:center}
.why2{display:grid;gap:10px 22px;grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr));margin:12px 0}
.why2 > div{min-width:0}
.why2 p{font-size:15.5px}
.propo{border-top:3px solid var(--gold);padding-top:18px;margin-top:30px}
.kinds{display:grid;gap:10px 18px;grid-template-columns:repeat(auto-fit,minmax(min(100%,250px),1fr));margin:10px 0 14px}
.kinds > div{background:var(--panel);padding:10px 12px;min-width:0}
.kinds p{font-size:15px;margin:0}
pre.j{background:#0b1124;color:#d6e0f6;padding:12px 14px;font:13px/1.45 ui-monospace,Consolas,monospace;overflow-x:auto;margin:8px 0 14px;max-width:100%}
.quote{border-left:4px solid var(--gold);padding:6px 14px;color:var(--ink);font-style:italic;margin:8px 0 14px;background:#2b2410;max-width:none}
.pill.build{background:var(--green);color:#10260a;margin-left:6px;white-space:nowrap}
.buildline{background:#16301a;border-left:4px solid var(--green);padding:7px 11px;font-size:14.5px;color:#d9f5cf;margin:0 0 9px;max-width:none}
.buildbox{background:#16301a;border-left:4px solid var(--green);padding:12px 14px;margin:10px 0 18px}
.buildbox h4{color:#a9ec8e;margin-bottom:6px}
.buildbox ul{margin:0;padding-left:20px;display:grid;gap:4px;font-size:15px}
.newbox{background:#2b2410;border-left:4px solid var(--gold);padding:10px 14px;margin:14px 0 4px;max-width:none}
.newbox a{color:var(--gold);font-weight:700}
.reco{background:#2b2410;border-left:4px solid var(--gold);padding:14px 16px;margin:12px 0 8px}
.reco p{max-width:none}
@media (prefers-reduced-motion:no-preference){.ring.pulse{animation:pulse 1.6s ease-in-out infinite}@keyframes pulse{50%{box-shadow:0 0 0 1.6u #ffdc73,0 0 16u 4u rgba(255,220,115,.55)}}}
""")


# ------------------------------------------------------------------------------------------------ pieces

def s(x):
    return U(x)


def icon(k, style):
    return '<i class="ic ic-%s" style="%s"></i>' % (k, s(style))


def coin_price(p, cls=""):
    return '<i class="ic ic-coin"></i>%s' % num(p)


def tabbar(mark=False):
    def t(cls, ic, word, extra="", inner=""):
        return '<div class="tab %s">%s%s<span class="w">%s</span></div>' % (cls, inner, '<i class="ic ic-%s %s"></i>' % (ic, extra), word)
    badge = '<span class="badge">&#128274;</span>'
    return ('<div class="band"></div><div class="tabs">' + t("lk", "tab_store", "STORE", inner=badge)
            + t("", "drifter_icon", "HEROES", "round") + t("", "tab_battle", "BATTLE") + t("on", "spite_1", "UPGRADE") + t("", "tab_coll", "COLLECTIONS") + '</div>')


def header(gold):
    return ('<div class="hd-back">&#8249;</div><div class="hd-t ul">UPGRADE</div><div class="wal"><i class="ic ic-coin"></i>%s</div>' % num(gold))


def frame(k, x, y, size, rarity="r-common", cls="", plaque=None, extra=""):
    pq = '<span class="pq">%s</span>' % plaque if plaque else ""
    return '<span class="fr %s %s" style="%s"><i class="ic ic-%s"></i>%s%s</span>' % (rarity, cls, s("left:%su;top:%su;width:%su;height:%su" % (x, y, size, size)), k, pq, extra)


def button(kind, label, x, y, w, h, px, price=None):
    inner = ('<i class="ic ic-coin"></i>%s' % num(price) if price is not None else "")
    if price is not None and label:
        inner += '<span style="%s">&middot;</span>' % s("margin:0 .5u")
    inner += esc(label)
    return '<div class="btn %s" style="%s">%s</div>' % (kind, s("left:%su;top:%su;width:%su;height:%su;font-size:%su" % (x, y, w, h, px)), inner)


# ------------------------------------------------------------------------------------------------ the tree's layout

SEC_RARITY = ["r-common", "r-uncommon", "r-rare", "r-epic"]
SKY = ["sky-sundown", "sky-nightfall", "sky-dust", "sky-blood"]
ROW = 54.0
TRUNK_X = 180.0
LEFT_X = 92.0
RIGHT_X = 268.0
NODE = 40.0


def layout(entries):
    """Bottom up. Every entry gets y (its foot, in u from the tree's foot) and h; a node's centre is measured from the foot too."""
    y = 0.0
    out = []
    prev_sec = None
    for e in entries:
        e = dict(e)
        if prev_sec is not None and e["sec"] != prev_sec:
            y += 20.0  # the section's band
            e["band_at"] = y - 18.0
        prev_sec = e["sec"]
        e["y"] = y
        if e["kind"] == "plain":
            e["h"] = ROW
            e["cy"] = y + ROW / 2
        elif e["kind"] == "hero":
            e["h"] = 66.0
            e["cy"] = y + 33.0
        elif e["kind"] == "mile":
            e["h"] = 96.0
            e["cy"] = y + 48.0
        else:
            e["h"] = 18.0 + 3 * ROW + 18.0
            e["cys"] = [y + 18.0 + ROW * (k + 0.5) for k in range(3)]
        y += e["h"]
        out.append(e)
    return out, y


def _path(x1, y1, x2, y2):
    my = (y1 + y2) / 2
    return "M%.1f %.1fC%.1f %.1f %.1f %.1f %.1f %.1f" % (x1, y1, x1, my, x2, my, x2, y2)


def status(e, k, bought, picks, unrolled):
    """A node's state: own / next / off / shut / open (the unrolled tree's full colour)."""
    if unrolled:
        return "open"
    if e["kind"] == "fork":
        n = e["n"] + (k[1] if k else 0)
        pick = picks.get(e["idx"])
        side = k[0] if k else None
        if pick and side != pick:
            return "shut"
        if n <= bought:
            return "own"
        if n == bought + 1:
            return "next"
        return "off"
    if e["n"] <= bought:
        return "own"
    return "next" if e["n"] == bought + 1 else "off"


LINE = {"own": "#f5b82a", "next": "#ffdc73", "off": "#55607c", "shut": "#2a3248", "open": "#c9d3e8"}


def edge_svg(segs, H, width=360):
    """Segments (x1,y1,x2,y2,state), y up from the foot, drawn in two strokes: a navy under-stroke and the colour."""
    under = []
    over = []
    for (x1, y1, x2, y2, st) in sorted(segs, key=lambda q: {"shut": 0, "off": 1, "open": 2, "next": 3, "own": 4}[q[4]]):
        d = _path(x1, H - y1, x2, H - y2)
        under.append('<path d="%s" stroke="#0a1436" stroke-width="%s" fill="none" stroke-linecap="round"/>' % (d, 7.6 if st != "shut" else 5))
        dash = ' stroke-dasharray="5 5"' if st == "next" else ""
        over.append('<path d="%s" stroke="%s" stroke-width="%s" fill="none" stroke-linecap="round"%s/>' % (d, LINE[st], 4.2 if st != "shut" else 2.4, dash))
    return '<svg viewBox="0 0 %d %.1f" preserveAspectRatio="none" aria-hidden="true">%s%s</svg>' % (width, H, "".join(under), "".join(over))


def render_tree(C, entries, bought=0, picks=None, unrolled=False, prices=True):
    """One stretch of the tree as a block of absolute pieces: returns (html, height in u)."""
    picks = picks or {}
    laid, H = layout(entries)
    segs = []
    nodes = []
    prev = []  # the points the next entry's line starts from: (x, y, state)
    for e in laid:
        if e.get("band_at") is not None:
            sec = C.TREE_SECTIONS[e["sec"]]
            nodes.append('<div class="secband" style="%s">%s</div>' % (s("top:%.1fu" % (H - e["band_at"] - 16.0)), esc(sec["name"])))
        rarity = SEC_RARITY[e["sec"]]
        if e["kind"] == "fork":
            fa, fb = C.FORMS[e["a"]], C.FORMS[e["b"]]
            for side, x, f in (("a", LEFT_X, fa), ("b", RIGHT_X, fb)):
                last = None
                for k in range(3):
                    st = status(e, (side, k), bought, picks, unrolled)
                    cy = e["cys"][k]
                    if k == 0:
                        for (px, py, pst) in prev:
                            segs.append((px, py, x, cy, _edge_state(pst, st)))
                    else:
                        segs.append((x, last[0], x, cy, _edge_state(last[1], st)))
                    last = (cy, st)
                    nodes.append(_fork_node(f, x, cy, k, st, rarity, e["prices"][k], side, prices))
            nodes.append('<div class="forksign" style="%s"><span class="ul">%s</span><span class="or">or</span></div>' % (s("top:%.1fu" % (H - e["cys"][1] - 15)), esc(fa["talent"].upper())))
            sa = status(e, ("a", 2), bought, picks, unrolled)
            sb = status(e, ("b", 2), bought, picks, unrolled)
            prev = [(LEFT_X, e["cys"][2], sa), (RIGHT_X, e["cys"][2], sb)]
        else:
            st = status(e, None, bought, picks, unrolled)
            for (px, py, pst) in prev:
                segs.append((px, py, TRUNK_X, e["cy"], _edge_state(pst, st)))
            nodes.append(_trunk_node(e, st, rarity, H, prices))
            prev = [(TRUNK_X, e["cy"], st)]
    return edge_svg(segs, H) + "".join(nodes), H


def _edge_state(a, b):
    if "shut" in (a, b):
        return "shut"
    if a == "open" or b == "open":
        return "open"
    if b == "own":
        return "own"
    if b == "next":
        return "next"
    return "off"


def _fr_cls(st, rarity):
    if st == "off":
        return rarity, "off"
    if st == "shut":
        return rarity, "shut"
    return rarity, ""


def _fork_node(f, x, cy, k, st, rarity, price, side, prices):
    top = "calc(var(--H)*1u - %.1fu)" % (cy + NODE / 2)
    rar, cls = _fr_cls(st, rarity)
    roman = ["I", "II", "III"][k]
    fr = '<span class="fr %s %s" style="%s"><i class="ic ic-%s"></i><span class="pq">%s</span></span>' % (
        rar, cls, s("left:%.1fu;top:var(--t%d);width:%.1fu;height:%.1fu" % (x - NODE / 2, 0, NODE, NODE)), f["icon"], roman)
    fr = fr.replace("var(--t0)", "__TOP__%.1f__" % (cy + NODE / 2))
    ring = ""
    if st == "next":
        ring = '<span class="ring pulse" style="%s"></span>' % s("left:%.1fu;top:__TOP__%.1f__;width:%.1fu;height:%.1fu" % (x - NODE / 2 - 1, cy + NODE / 2 + 1, NODE + 2, NODE + 2))
    lab_st = {"off": "off", "shut": "shut"}.get(st, "")
    pr = '<span class="pr"><i class="ic ic-coin"></i>%s</span>' % num(price) if prices and st not in ("own", "shut") else ""
    words = '<b>%s %s</b>%s%s' % (esc(f["name"]) if len(f["name"]) < 9 else esc(f["name"].split(" ")[-1] if " " in f["name"] else f["name"]), roman, esc(f["step"]), pr)
    if side == "a":
        lab = '<div class="nl r %s" style="%s">%s</div>' % (lab_st, s("left:4u;width:%.1fu;top:__TOP__%.1f__" % (x - NODE / 2 - 8, cy + 15)), words)
    else:
        lab = '<div class="nl %s" style="%s">%s</div>' % (lab_st, s("left:%.1fu;width:%.1fu;top:__TOP__%.1f__" % (x + NODE / 2 + 4, 360 - x - NODE / 2 - 8, cy + 15)), words)
    return ring + fr + lab


def _trunk_node(e, st, rarity, H, prices):
    cy = e["cy"]
    k = e["kind"]
    lab_st = "off" if st == "off" else ""
    pr = '<span class="pr"><i class="ic ic-coin"></i>%s</span>' % num(e["price"]) if prices and st != "own" else ""
    if k == "plain":
        rar, cls = _fr_cls(st, rarity)
        fr = '<span class="fr %s %s" style="%s"><i class="ic ic-%s"></i></span>' % (rar, cls, s("left:%.1fu;top:__TOP__%.1f__;width:%.1fu;height:%.1fu" % (TRUNK_X - NODE / 2, cy + NODE / 2, NODE, NODE)), e["icon"])
        ring = '<span class="ring pulse" style="%s"></span>' % s("left:%.1fu;top:__TOP__%.1f__;width:%.1fu;height:%.1fu" % (TRUNK_X - NODE / 2 - 1, cy + NODE / 2 + 1, NODE + 2, NODE + 2)) if st == "next" else ""
        lab = '<div class="nl %s" style="%s"><b>%s</b>%s%s</div>' % (lab_st, s("left:%.1fu;width:%.1fu;top:__TOP__%.1f__" % (TRUNK_X + NODE / 2 + 5, 360 - TRUNK_X - NODE / 2 - 9, cy + 15)), esc(e["name"]), esc(e["effect"]), pr)
        return ring + fr + lab
    if k == "hero":
        sz = 50.0
        rc = "off" if st == "off" else ""
        fr = '<i class="ic ic-%s hround %s" style="%s"></i>' % (e["icon"], rc, s("left:%.1fu;top:__TOP__%.1f__;width:%.1fu;height:%.1fu" % (TRUNK_X - sz / 2, cy + sz / 2, sz, sz)))
        ring = '<span class="ring pulse" style="%s;border-radius:50%%"></span>' % s("left:%.1fu;top:__TOP__%.1f__;width:%.1fu;height:%.1fu" % (TRUNK_X - sz / 2 - 4, cy + sz / 2 + 4, sz + 8, sz + 8)) if st == "next" else ""
        lab = ('<div class="nl %s" style="%s"><b style="%s">%s</b>Hero: brings %s%s</div>'
               % (lab_st, s("left:%.1fu;width:%.1fu;top:__TOP__%.1f__" % (TRUNK_X + sz / 2 + 7, 360 - TRUNK_X - sz / 2 - 11, cy + 19)), s("font-size:10u"), esc(e["name"]), esc(e["weapon"]), pr))
        return ring + fr + lab
    # a milestone
    sz = 66.0
    rays = '<span class="rays" style="%s"></span>' % s("left:%.1fu;top:__TOP__%.1f__;width:%.1fu;height:%.1fu" % (TRUNK_X - 70, cy + 70, 140, 140)) if st in ("next", "open", "own") else ""
    fr = '<span class="fr r-legend %s" style="%s"><i class="ic ic-%s"></i></span>' % ("off" if st == "off" else "", s("left:%.1fu;top:__TOP__%.1f__;width:%.1fu;height:%.1fu" % (TRUNK_X - sz / 2, cy + sz / 2, sz, sz)), e["icon"])
    tag = '<span class="ttag" style="%s">MILESTONE</span>' % s("left:%.1fu;top:__TOP__%.1f__" % (TRUNK_X + sz / 2 + 8, cy + 27))
    lab = ('<div class="nl %s" style="%s"><span class="tmile">%s</span><span style="%s">%s</span>%s</div>'
           % (lab_st, s("left:%.1fu;width:%.1fu;top:__TOP__%.1f__" % (TRUNK_X + sz / 2 + 8, 360 - TRUNK_X - sz / 2 - 12, cy + 15)), esc(e["name"]), s("display:block;margin-top:1.5u"), esc(e["effect"]), pr))
    return rays + fr + tag + lab


def finish_tops(htm, H):
    """Node tops were written from the tree's foot: __TOP__y__ becomes (H - y)u."""
    return re.sub(r"__TOP__([\d.]+)__", lambda m: "calc(%.1f*var(--u))" % (H - float(m.group(1))), htm)


def tree_block(C, entries, bought=0, picks=None, unrolled=False):
    h, H = render_tree(C, entries, bought, picks, unrolled)
    return finish_tops(h, H), H


# ------------------------------------------------------------------------------------------------ Proposal A's phones

def slice_rows(entries, a, b):
    out = []
    for e in entries:
        last = e["n"] + (2 if e["kind"] == "fork" else 0)
        if e["n"] >= a and last <= b:
            out.append(e)
    return out


def a_main(C, st):
    # bought through row 19, Field Notes taken at the fork below; the next node is a plain one, then Solenne, a fork, a milestone
    ents = slice_rows(st["entries"], 17, 25)
    htm, H = tree_block(C, ents, bought=19, picks={next(e["idx"] for e in st["entries"] if e["n"] == 17): "a"})
    top = 50.0
    vp_h = 693.0 - 84.0 - 10.0 - top
    next_e = next(e for e in st["entries"] if e["n"] == 20)
    tree_y = 26.0   # how far the view is scrolled: the milestone whole at the top, the fork below running off the foot
    return ('<div class="sc plate sky-nightfall">'
            '<div class="dimw"></div>' + header(1540) +
            '<div class="sheet" style="%s;background-image:var(--sky)"><div style="%s">'
            '<div class="tree" style="%s">%s</div></div>'
            '<div class="plateb" style="%s"><span class="lab" style="%s">Row 20 of 64 &middot; Nightfall</span></div>'
            '<div class="btn b-slate" style="%s">RESET</div><div class="thumb" style="%s"></div>'
            '</div>' % (s("left:4u;right:4u;top:%.1fu;height:%.1fu" % (top, vp_h)), s("position:absolute;inset:0;overflow:hidden"),
                        s("top:%.1fu;height:%.1fu" % (tree_y, H)), htm,
                        s("left:6u;top:6u;height:15u;padding:0 5u;display:flex;align-items:center"), s("font-size:6.8u"),
                        s("right:7u;top:6u;width:44u;height:15u;font-size:7u"), s("top:300u;height:70u")) +
            _dock(next_e, "Bull Hide", "+5% max HP, +3% damage reduction", "Next up: Solenne, then a fork. Milestone in 5 rows.", next_e["price"], "padding", 1) +
            tabbar() + '</div>')


def _dock(e, name, fx, sub, price, form_key, rarity_i, kind="b-green", word="BUY", icon_key=None, short=None):
    ik = icon_key or {"padding": "grit_0"}.get(form_key, form_key)
    return ('<div class="slate dock" style="%s">%s'
            '<div class="nm ul">%s</div><div class="fx">%s</div>'
            '<div class="fx" style="%s">%s</div>%s</div>'
            % (s("top:%.1fu" % (693.0 - 84.0 - 7)),
               frame(ik, 8, 13, 50, SEC_RARITY[rarity_i], "", None),
               esc(name), esc(fx), s("top:35u;font-size:7.4u;color:#ffe48a"), esc(sub),
               button(kind, word, 66, 48, 270, 25, 11.5, price)))


def a_fork(C, st):
    # the fork of Omen or Greed comes up: the tree dims under the shared pop-up, two sides, each with what its three nodes add
    e = next(x for x in st["entries"] if x["kind"] == "fork" and x["n"] == 22)
    f1, f2 = C.FORMS[e["a"]], C.FORMS[e["b"]]
    ents = slice_rows(st["entries"], 17, 25)
    htm, H = tree_block(C, ents, bought=21, picks={next(x["idx"] for x in st["entries"] if x["n"] == 17): "a"})
    def cell(f, word):
        rows = "".join('<span class="fr r-uncommon" style="%s"><i class="ic ic-%s"></i><span class="pq">%s</span></span>'
                       % (s("left:%su;top:30u;width:26u;height:26u" % (66 + i * 31)), f["icon"], r) for i, r in enumerate(["I", "II", "III"]))
        return ('<div class="cell" style="%s">%s<div class="abs ul" style="%s">%s</div>%s'
                '<div class="abs" style="%s"><span class="hi">%s</span></div>'
                '<div class="btn b-green" style="%s"><i class="ic ic-coin"></i>%s<span style="%s">&middot;</span>TAKE %s</div></div>'
                % (s("height:108u"), frame(f["icon"], 8, 9, 50, "r-uncommon"),
                   s("left:66u;top:9u;font-size:14u;white-space:nowrap"), esc(f["name"]), rows,
                   s("left:167u;top:30u;width:136u;font:500 8.6u/1.2 var(--body)"), esc(f["three"]),
                   s("left:8u;right:8u;top:70u;height:25u;font-size:11u"), num(e["prices"][0]), s("margin:0 .5u"), word.upper()))
    top = 50.0
    vp_h = 693.0 - top
    return ('<div class="sc plate sky-nightfall"><div class="dimw"></div>' + header(1640) +
            '<div class="sheet" style="%s;background-image:var(--sky)"><div style="%s"><div class="tree" style="%s">%s</div></div></div>'
            % (s("left:4u;right:4u;top:%.1fu;height:%.1fu" % (top, vp_h)), s("position:absolute;inset:0;overflow:hidden"), s("top:%.1fu;height:%.1fu" % (vp_h - H + 130, H)), htm) +
            tabbar() + '<div class="scrim"></div>'
            '<div class="modal" style="%s"><div class="star">&#9733; FORK %d OF 14 &#9733;</div><div class="mtitle ul">%s</div><div class="flav">%s</div>%s%s'
            '<div class="note">Choose one. The other side closes, and comes back only with Reset Upgrades.</div>'
            '<div class="btn b-slate" style="%s">CLOSE</div></div>'
            % (s("top:124u"), e["idx"], esc(f1["talent"].upper()), esc(C.FLAVOUR[f1["talent"]]), cell(f1, f1["name"]), cell(f2, f2["name"]),
               s("position:relative;height:32u;font-size:13u;margin-top:2u")) + '</div>')


def a_mile(C, st):
    e = next(x for x in st["entries"] if x["kind"] == "mile" and x["name"] == "Wide Load")
    ents = slice_rows(st["entries"], 30, 37)
    picks = {}
    for x in st["entries"]:
        if x["kind"] == "fork" and x["n"] <= 34:
            picks[x["idx"]] = "a"
    htm, H = tree_block(C, ents, bought=34, picks=picks)
    top = 50.0
    vp_h = 693.0 - top
    return ('<div class="sc plate sky-dust"><div class="dimw"></div>' + header(8120) +
            '<div class="sheet" style="%s;background-image:var(--sky)"><div style="%s"><div class="tree" style="%s">%s</div></div></div>'
            % (s("left:4u;right:4u;top:%.1fu;height:%.1fu" % (top, vp_h)), s("position:absolute;inset:0;overflow:hidden"), s("top:%.1fu;height:%.1fu" % (vp_h - H + 40, H)), htm) +
            tabbar() + '<div class="scrim"></div>'
            '<span class="rays" style="%s"></span>'
            '<div class="abs star" style="%s">&#9733; MILESTONE %d OF 8 &#9733;</div>'
            '<div class="abs ul gd" style="%s">WIDE LOAD</div>' % (s("left:30u;top:80u;width:300u;height:300u"), s("left:0;right:0;top:66u"), e["idx"], s("left:0;right:0;top:82u;text-align:center;font-size:27u")) +
            frame(e["icon"], 115, 150, 130, "r-legend") +
            '<div class="abs" style="%s"><div style="%s">+15%% area of effect</div><div style="%s">on every weapon, in every run, for good</div></div>'
            % (s("left:24u;right:24u;top:306u;text-align:center"), s("font:700 15u/1.2 var(--body);color:#ffe48a"), s("font:500 9.6u/1.3 var(--body);color:#fff;margin-top:2u")) +
            '<div class="slate" style="%s"><div class="abs" style="%s">The nodes around it give one step of one stat. This one gives what no rank on the old board could, for twice the price of a node in this row.</div></div>'
            % (s("left:24u;right:24u;top:352u;height:50u"), s("left:9u;right:9u;top:9u;font:500 9u/1.3 var(--body);color:#cfe3ff")) +
            button("b-green", "BUY", 40, 430, 280, 42, 17, e["price"]) +
            button("b-slate", "CLOSE", 40, 488, 280, 30, 13) + '</div>')


def a_hero(C, st):
    e = next(x for x in st["entries"] if x["kind"] == "hero" and x["id"] == "calavera")
    ents = slice_rows(st["entries"], 12, 21)
    picks = {x["idx"]: "a" for x in st["entries"] if x["kind"] == "fork" and x["n"] <= 14}
    htm, H = tree_block(C, ents, bought=15, picks=picks)
    top = 50.0
    vp_h = 693.0 - top
    return ('<div class="sc plate sky-nightfall"><div class="dimw"></div>' + header(2180) +
            '<div class="sheet" style="%s;background-image:var(--sky)"><div style="%s"><div class="tree" style="%s">%s</div></div></div>'
            % (s("left:4u;right:4u;top:%.1fu;height:%.1fu" % (top, vp_h)), s("position:absolute;inset:0;overflow:hidden"), s("top:%.1fu;height:%.1fu" % (vp_h - H + 150, H)), htm) +
            tabbar() + '<div class="scrim"></div>'
            '<span class="rays" style="%s"></span>'
            '<div class="abs star" style="%s">&#9733; A NEW HERO &#9733;</div>'
            '<div class="abs ul" style="%s">CALAVERA</div>'
            '<div class="fig cut-calavera" style="%s"></div>' % (s("left:20u;top:90u;width:320u;height:320u"), s("left:0;right:0;top:66u"), s("left:0;right:0;top:82u;text-align:center;font-size:27u"), s("left:70u;top:118u;width:220u;height:280u")) +
            '<div class="abs" style="%s">Plays the Guitarra. Row 16 on the tree, and the first thing you buy in Nightfall.</div>'
            % s("left:30u;right:30u;top:402u;text-align:center;font:500 10u/1.3 var(--body);color:#fff") +
            button("b-green", "UNLOCK", 40, 442, 280, 42, 17, e["price"]) +
            button("b-slate", "CLOSE", 40, 500, 280, 30, 13) + '</div>')


def strips_html(C, st):
    out = []
    for i, (a, b) in enumerate(C.TREE_STRIPS):
        ents = slice_rows(st["entries"], a, b)
        htm, H = tree_block(C, ents, unrolled=True)
        sec = ents[-1]["sec"]
        pad_top = 8.0
        label = "Part %d of %d: rows %d to %d" % (i + 1, len(C.TREE_STRIPS), a, b)
        out.append('<div><p class="striph">%s &middot; read it from the foot up</p><div class="stripw"><div class="strip %s" style="%s"><div class="tree" style="%s">%s</div></div></div></div>'
                   % (label, SKY[sec], s("height:%.1fu" % (H + pad_top)), s("top:%.1fu;height:%.1fu" % (pad_top, H)), htm))
    return '<div class="strips">%s</div>' % "".join(out)


# ------------------------------------------------------------------------------------------------ Proposal B's phones

LEVEL_RARITY = {1: "r-common", 2: "r-uncommon", 3: "r-rare", 4: "r-epic glow", 5: "r-legend"}


def b_main():
    pouch = [  # kind, x, y, icon, level, locked price
        ("IRON", 14, 60, "drive_0", 3, None), ("IRON", 288, 60, "grit_0", 2, None),
        ("LEATHER", 14, 138, "stride_0", 2, None), ("LEATHER", 288, 138, "study_0", 1, None),
        ("SILVER", 14, 216, "fortune_0", 2, None), ("SILVER", 288, 216, None, 0, 4000),
    ]
    p = ""
    for kind, x, y, ic, lv, lockp in pouch:
        p += '<div class="plateb" style="%s"><span class="lab" style="%s">%s</span></div>' % (s("left:%su;top:%su;width:58u;height:11u;display:flex;align-items:center;justify-content:center" % (x, y)), s("font-size:5.8u;letter-spacing:.1em"), kind)
        if ic:
            p += frame(ic, x, y + 13, 58, LEVEL_RARITY[lv], "", "LV %d" % lv)
        else:
            p += ('<span class="fr r-locked off" style="%s"><span class="abs" style="%s">&#128274;</span></span>' % (s("left:%su;top:%su;width:58u;height:58u" % (x, y + 13)), s("left:0;right:0;top:9u;text-align:center;font-size:17u")))
            p += '<div class="chip no" style="%s"><i class="ic ic-coin"></i>%s</div>' % (s("left:%su;right:auto;top:%su" % (x + 7, y + 49)), num(lockp))
    shelf = [
        ("IRON", [("drive_0", "Muscle", 3, True), ("drive_1", "Tempo", 1, False), ("grit_0", "Padding", 2, True), ("grit_1", "Plate", 1, False)]),
        ("LEATHER", [("stride_0", "Boots", 2, True), ("stride_1", "Lodestone", 0, False), ("study_0", "Field Notes", 1, True), ("study_1", "Poultice", 0, False)]),
        ("SILVER", [("fortune_0", "Omen", 2, True), ("fortune_1", "Greed", 0, False), ("choice_0", "Reroll", 1, False), ("choice_1", "Banish", 0, False)]),
        ("", [("nerve_0", "Skip", 0, False), ("nerve_1", "Second Wind", 1, False), ("spite_0", "Difficulty", 0, False), ("spite_1", "Boss", 0, False)]),
    ]
    rows = ""
    y = 8.0
    for kind, items in shelf:
        if kind:
            rows += '<span class="lab abs" style="%s">%s</span>' % (s("left:9u;top:%.1fu;font-size:6.2u" % y), kind)
            y += 9.0
        for i, (ic, nm, lv, eq) in enumerate(items):
            x = 8 + i * 82.5
            cls = "" if lv > 0 else "off"
            rar = LEVEL_RARITY[lv] if lv > 0 else "r-locked"
            ex = '<span class="check">&#10003;</span>' if eq else ""
            rows += frame(ic, x + 13, y, 48, rar, cls, "LV %d" % lv if lv else None, ex)
            rows += '<span class="abs" style="%s">%s</span>' % (s("left:%.1fu;width:78u;top:%.1fu;text-align:center;font:600 7.4u/1 var(--body);color:#fff" % (x - 2, y + 56)), esc(nm))
        y += 72.0
    return ('<div class="sc plate"><div class="dimw" style="background:linear-gradient(rgba(8,12,28,.35),rgba(8,12,28,.15) 45%,rgba(8,12,28,.5))"></div>' + header(1240) + p +
            '<div class="fig cut-drifter" style="%s"></div>'
            '<div class="plateb" style="%s"><div class="ul" style="%s">DRIFTER\'S BELT</div><div style="%s"><span class="hi">+26%%</span> attack &middot; <span class="hi">+21%%</span> max HP &middot; <span class="hi">+10%%</span> speed &middot; <span class="hi">+10%%</span> XP &middot; <span class="hi">+0.24</span> luck</div></div>'
            % (s("left:84u;top:56u;width:192u;height:236u"), s("left:14u;right:14u;top:294u;height:37u;text-align:center;padding-top:4u"), s("font-size:10.5u"), s("font:500 8u/1 var(--body);color:#fff;margin-top:3u")) +
            '<div class="slate" style="%s">%s</div>' % (s("left:6u;right:6u;top:337u;height:344u"), rows) +
            tabbar() + '</div>')


def b_charm():
    pips = ""
    for i in range(5):
        on = i < 1
        pips += '<span class="fr %s %s" style="%s">%s</span>' % ("r-common" if on else "r-locked", "" if on else "off", s("left:%su;top:0;width:30u;height:30u" % (i * 37)), '<i class="ic ic-drive_1"></i>' if on else '')
    def swap(ic, nm, lv, x):
        return (frame(ic, x + 8, 9, 42, LEVEL_RARITY[lv], "", "LV %d" % lv) +
                '<div class="abs" style="%s"><b style="%s">%s</b>Swap it out</div>' % (s("left:%su;top:15u;width:88u;font:500 7.8u/1.2 var(--body);color:#cfe3ff" % (x + 55)), s("display:block;color:#fff;font-size:9.4u"), nm))
    return ('<div class="sc plate"><div class="dimw"></div>' + header(1240) + tabbar() + '<div class="scrim"></div>'
            '<div class="modal" style="%s"><div class="star">&#9733; IRON CHARM &#9733;</div><div class="mtitle ul">TEMPO</div><div class="flav">Hit sooner.</div>'
            '<div style="%s">%s</div>'
            '<div class="cell" style="%s">'
            '%s<div class="abs" style="%s"><div style="%s">LV 1 &rarr; LV 2</div><div style="%s"><span class="hi">-6%%</span> &rarr; <span class="hi">-12%%</span> cooldown</div></div>'
            '<div class="btn b-green" style="%s"><i class="ic ic-coin"></i>1,500<span style="%s">&middot;</span>LEVEL UP</div></div>'
            '<div class="lab" style="%s">Your Iron pouches are full. Put it in place of:</div>'
            '<div class="cell" style="%s">%s%s</div>'
            '<div class="note">Swapping is free, between any two runs. Each hero keeps his own belt. Levels stay with the charm for every hero.</div>'
            '<div class="btn b-slate" style="%s">CLOSE</div></div>'
            % (s("top:120u"), s("position:relative;height:32u;width:178u;margin:3u auto 2u"), pips,
               s("height:108u"), frame("drive_1", 9, 9, 54, "r-common", "", "LV 1"),
               s("left:74u;top:12u;right:8u"), s("font:700 9.6u/1 var(--body);color:#fff"), s("font:500 12.5u/1.2 var(--body);color:#fff;margin-top:4u"),
               s("left:9u;right:9u;top:72u;height:25u;font-size:12u"), s("margin:0 .5u"),
               s("font-size:6.8u;text-align:center;margin-top:3u"),
               s("height:62u"), swap("drive_0", "Muscle", 3, 6), swap("grit_0", "Padding", 2, 158),
               s("position:relative;height:32u;font-size:13u;margin-top:2u")) + '</div>')


def b_pouch():
    return ('<div class="sc plate"><div class="dimw"></div>' + header(4310) + tabbar() + '<div class="scrim"></div>'
            '<span class="rays" style="%s"></span>'
            '<div class="abs star" style="%s">&#9733; A SIXTH POUCH &#9733;</div>'
            '<div class="abs ul" style="%s">SILVER POUCH</div>' % (s("left:30u;top:88u;width:300u;height:300u"), s("left:0;right:0;top:66u"), s("left:0;right:0;top:82u;text-align:center;font-size:23u")) +
            '<span class="fr r-rare" style="%s"><span class="bd bd-pouch_silver" style="%s"></span></span>' % (s("left:115u;top:148u;width:130u;height:130u"), s("inset:6%;background-position:center")) +
            '<div class="abs" style="%s"><div style="%s">Carry one more luck charm</div><div style="%s">On every hero. This is the only thing that lifts the belt\'s ceiling, so each one is a step you choose to take.</div></div>'
            % (s("left:28u;right:28u;top:306u;text-align:center"), s("font:700 14u/1.2 var(--body);color:#ffe48a"), s("font:500 9.6u/1.3 var(--body);color:#fff;margin-top:3u")) +
            button("b-green", "BUY", 40, 402, 280, 42, 17, 4000) +
            button("b-slate", "CLOSE", 40, 460, 280, 30, 13) + '</div>')


# ------------------------------------------------------------------------------------------------ Proposal C's phones

def c_main():
    # (building art, name, x, y, picks: 0/1 icons, chip)
    d = "drive"
    def pips(picks, a, b):
        out = ""
        for k in range(7):
            if k < len(picks):
                out += '<i class="h ic-%s"></i>' % (a if picks[k] == 0 else b)
            else:
                out += "<i></i>"
        return '<div class="pips">%s</div>' % out
    lots = [
        ("st_saloon", "Saloon", 6, 62, [0, 1, 0, 0], "choice_0", "choice_1", ("wait", None)),
        ("st_fortune", "Fortune Teller", 182, 62, [0, 0, 1], "fortune_0", "fortune_1", ("ok", 4800)),
        ("st_gun2", "Gunsmith", 6, 216, [0, 1, 0], "drive_0", "drive_1", ("ok", 6000)),
        ("st_outfitter", "Outfitter", 182, 216, [0, 0, 1], "grit_0", "grit_1", ("no", 7200)),
        ("st_doc", "Doc's", 6, 370, [0, 0], "study_0", "study_1", ("ok", 3600)),
        ("st_livery", "Livery", 182, 370, [0, 1, 0], "stride_0", "stride_1", ("no", 6800)),
    ]
    h = ""
    for art, nm, x, y, picks, a, b, chip in lots:
        h += '<div class="lot" style="%s"><div class="bd bd-%s" style="%s"></div><div class="sign"><span class="ul">%s</span>%s</div>' % (s("left:%su;top:%su" % (x, y)), art, s("left:4u;right:4u;top:0;bottom:24u"), esc(nm), pips(picks, a, b))
        if chip[0] == "wait":
            h += '<div class="chip wait">BUILD UP THE DOC</div>'
        else:
            h += '<div class="chip %s"><i class="ic ic-coin"></i>%s</div>' % (chip[0], num(chip[1]))
        h += '</div>'
    # the next two lots peek in at the top, the street's foot under the tab bar
    h += '<div class="lot" style="%s"><div class="bd bd-st_sheriff" style="%s"></div><div class="sign"><span class="ul">Sheriff\'s Office</span>%s</div><div class="chip ok"><i class="ic ic-coin"></i>1,600</div></div>' % (s("left:6u;top:524u"), s("left:4u;right:4u;top:0;bottom:24u"), pips([0, 0, 1], "spite_0", "spite_1"))
    h += '<div class="lot" style="%s"><div class="bd bd-st_chapel" style="%s"></div><div class="sign"><span class="ul">Chapel</span>%s</div><div class="chip ok"><i class="ic ic-coin"></i>2,400</div></div>' % (s("left:182u;top:524u"), s("left:4u;right:4u;top:0;bottom:24u"), pips([1, 1, 0], "nerve_0", "nerve_1"))
    figs = ('<div class="fig cut-drifter" style="%s"></div><div class="fig cut-ironwood" style="%s"></div>' % (s("left:150u;top:300u;width:58u;height:78u"), s("left:158u;top:462u;width:50u;height:68u")))
    return ('<div class="sc" style="background:#e3bf85"><div class="road"></div>' + h + figs +
            '<div class="abs" style="%s"></div>' % s("left:0;right:0;top:0;height:60u;background:linear-gradient(rgba(14,31,74,.92),rgba(14,31,74,.75) 70%,rgba(14,31,74,0))") + header(6240) + tabbar() + '</div>')


def c_sheet():
    def opt(ic, nm, step, owned, y):
        return ('<div class="cell" style="%s">%s<div class="abs ul" style="%s">%s</div><div class="abs" style="%s"><span class="hi">%s</span> a rank<br>%d owned</div>'
                '<div class="btn b-green" style="%s"><i class="ic ic-coin"></i>6,000<span style="%s">&middot;</span>BUY</div></div>'
                % (s("height:64u"), frame(ic, 8, 8, 46, "r-common"), s("left:62u;top:8u;font-size:12.5u"), esc(nm), s("left:62u;top:25u;width:110u;font:500 8.4u/1.25 var(--body);color:#fff"), esc(step), owned,
                   s("left:180u;top:16u;width:118u;height:28u;font-size:10.5u"), s("margin:0 .5u")))
    pips = "".join('<span class="fr %s %s" style="%s">%s</span>' % ("r-common" if k < 3 else "r-locked", "" if k < 3 else "off", s("left:%su;top:0;width:32u;height:32u" % (k * 38)),
                                                                   ('<i class="ic ic-%s"></i>' % ["drive_0", "drive_1", "drive_0"][k]) if k < 3 else "") for k in range(7))
    return ('<div class="sc" style="background:#e3bf85"><div class="road"></div>' + header(6240) + tabbar() + '<div class="scrim"></div>'
            '<div class="modal" style="%s"><div class="star">&#9733; RANK 4 OF 7 &#9733;</div><div class="mtitle ul">GUNSMITH</div><div class="flav">Hit harder, or hit sooner.</div>'
            '<div style="%s"><div class="bd bd-st_gun2" style="%s"></div><div class="abs ul" style="%s">&rarr;</div><div class="bd bd-st_gun3" style="%s"></div></div>'
            '<div class="note" style="%s">Rank 4 turns the shack into a storefront.</div>'
            '<div style="%s">%s</div>%s%s'
            '<div class="note">Choose one. It stays; Reset Upgrades is the only way to choose again.</div>'
            '<div class="btn b-slate" style="%s">CLOSE</div></div>'
            % (s("top:92u"), s("position:relative;height:120u"), s("left:6u;top:0;width:128u;height:116u"), s("left:138u;top:44u;width:28u;text-align:center;font-size:24u"), s("left:170u;top:-2u;width:136u;height:120u;filter:drop-shadow(0 0 8u rgba(255,220,115,.75))"),
               s("color:#ffe48a"), s("position:relative;height:34u;width:262u;margin:0 auto"), pips,
               opt("drive_0", "Muscle", "+8% attack", 2, 0), opt("drive_1", "Tempo", "-6% cooldown", 1, 0),
               s("position:relative;height:30u;font-size:13u;margin-top:2u")) + '</div>')


def c_grew():
    steps = [("st_gun1", "Tent", "rank 1", False), ("st_gun2", "Shack", "rank 3", False), ("st_gun3", "Storefront", "rank 4", True), ("st_gun4", "The Works", "rank 7", False)]
    row = ""
    for i, (art, nm, rk, on) in enumerate(steps):
        x = 8 + i * 83
        op = "" if i <= 2 else "filter:grayscale(.9) brightness(.55);"
        row += ('<div class="abs" style="%s"><div class="bd bd-%s" style="%s"></div><div style="%s">%s</div><div style="%s">%s</div></div>'
                % (s("left:%su;top:8u;width:80u;height:88u%s" % (x, ";box-shadow:0 0 0 1.4u #ffdc73;border-radius:2u;background:rgba(255,220,115,.12)" if on else "")), art, s("left:4u;right:4u;top:3u;height:60u;" + op),
                   s("position:absolute;left:0;right:0;top:66u;text-align:center;font:700 7.6u/1 var(--body);color:#fff"), nm, s("position:absolute;left:0;right:0;top:76u;text-align:center;font:500 6.8u/1 var(--body);color:#cfe3ff"), rk))
    return ('<div class="sc" style="background:#e3bf85"><div class="road"></div>' + header(240) + tabbar() + '<div class="scrim"></div>'
            '<span class="rays" style="%s"></span>'
            '<div class="abs star" style="%s">&#9733; RANK 4 &#9733;</div>'
            '<div class="abs ul gd" style="%s">THE GUNSMITH GREW</div>'
            '<div class="bd bd-st_gun3" style="%s"></div>' % (s("left:10u;top:70u;width:340u;height:340u"), s("left:0;right:0;top:62u"), s("left:0;right:0;top:78u;text-align:center;font-size:18.5u;white-space:nowrap"), s("left:60u;top:104u;width:240u;height:240u")) +
            '<div class="abs" style="%s">It now gives <span class="hi">+26%%</span> attack damage and <span class="hi">-6%%</span> cooldown</div>' % s("left:20u;right:20u;top:352u;text-align:center;font:500 11u/1.3 var(--body);color:#fff") +
            '<div class="slate" style="%s">%s</div>' % (s("left:15u;right:15u;top:398u;height:108u"), row) +
            button("b-gold", "NICE", 40, 524, 280, 40, 17) + '</div>')


def phone(inner, caption):
    return '<figure class="ph"><div class="phw">%s</div><figcaption>%s</figcaption></figure>' % (inner, caption)

# -*- coding: utf-8 -*-
"""Pass 124: the ideas document for Garry -> docs/ideas/outlaw_ideas.html (one self-contained page, the art embedded).
Words and prompts: docs/ideas/content.py. Art: tools/gen_ideas_art.py -> docs/ideas/art/.

    python tools/make_ideas_doc.py
"""
import base64
import html
import importlib.util
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ART = os.path.join(ROOT, "docs", "ideas", "art")
OUT = os.path.join(ROOT, "docs", "ideas", "outlaw_ideas.html")
spec = importlib.util.spec_from_file_location("ideas_content", os.path.join(ROOT, "docs", "ideas", "content.py"))
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)


def e(s):
    return html.escape(str(s), quote=False)


def md(s):
    s = e(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", s)


def img(i, alt=""):
    p = os.path.join(ART, i + ".jpg")
    if not os.path.exists(p):
        return ""
    b = base64.b64encode(open(p, "rb").read()).decode()
    return '<img src="data:image/jpeg;base64,%s" alt="%s">' % (b, html.escape(alt, quote=True))


def past_card(x):
    return ('<article class="card"><div class="pic">%s</div><div class="body"><h3>%s</h3><p class="tag">%s</p><p>%s</p><p class="why"><b>What it adds:</b> %s</p></div></article>'
            % (img(x["id"], x["name"]), e(x["name"]), e(x["tag"]), md(x["what"]), md(x["adds"])))


def var_card(x, wild=False):
    return ('<article class="wide%s"><div class="pic">%s</div><div class="body"><h3>%s</h3><p class="tag">%s</p>'
            '<dl><dt>The look</dt><dd>%s</dd><dt>Why it reads as a new place</dt><dd>%s</dd><dt>What it changes in play</dt><dd>%s</dd><dt>What it costs</dt><dd>%s</dd></dl></div></article>'
            % (" wild" if x["name"].startswith("WILD") else "", img(x["id"], x["name"]), e(x["name"].replace("WILD: ", "")) + (' <span class="pill hot">wild</span>' if x["name"].startswith("WILD") else ""), e(x["tag"]),
               md(x["look"]), md(x["apart"]), md(x["play"]), md(x["cost"])))


def gen_card(x):
    pic = img(x["id"], x["name"])
    if x["id"] == "gen_biomes":
        pic = DIAGRAM_BIOMES
    elif x["id"] == "gen_hard":
        pic = DIAGRAM_HARD
    return ('<article class="card"><div class="pic">%s</div><div class="body"><h3>%s</h3><p class="tag">%s</p><p>%s</p><p class="why"><b>Why:</b> %s</p><p class="cost"><b>Cost:</b> %s</p></div></article>'
            % (pic, e(x["name"]), e(x["tag"]), md(x["what"]), md(x["why"]), md(x["cost"])))


def enemy_card(x, extra=""):
    return ('<article class="mon"><div class="pic">%s</div><div class="body"><h3>%s</h3><p class="tag">%s</p>%s<p>%s</p></div></article>'
            % (img(x["id"], x["name"]), e(x["name"]), e(x["role"]), extra, md(x["text"])))


def unique_card(x):
    return ('<article class="wide unique"><div class="pic square">%s</div><div class="body"><h3>%s</h3><p class="tag">%s</p>'
            '<dl><dt>How it works</dt><dd>%s</dd><dt>The counter</dt><dd>%s</dd><dt>What it needs</dt><dd>%s</dd></dl></div></article>'
            % (img(x["id"], x["name"]), e(x["name"]), e(x["role"]), md(x["how"]), md(x["counter"]), md(x["build"])))


def old_item(x):
    return ('<article class="item"><div class="ico">%s</div><div class="body"><h3>%s</h3><p class="tag">%s · idea from %s</p><p>%s</p><p class="why"><b>The choice:</b> %s</p></div></article>'
            % (img(x["id"], x["name"]), e(x["name"]), e(x["slot"]), e(x["from_"]), md(x["text"]), md(x["choice"])))


def new_item(x, slot):
    return ('<article class="item"><div class="ico">%s</div><div class="body"><h3>%s</h3><p class="tag">%s</p><p class="gap"><b>The hole it fills:</b> %s</p><p>%s</p><p class="why"><b>The choice:</b> %s</p></div></article>'
            % (img(x["id"], x["name"]), e(x["name"]), slot, md(x["gap"]), md(x["text"]), md(x["choice"])))


def tle_card(x, pvp=False):
    money = "".join("<li>%s</li>" % md(m) for m in x["money"])
    mid = '<dt>How it works with few players</dt><dd>%s</dd>' % md(x["small"]) if pvp else '<dt>Why it works with this meta</dt><dd>%s</dd>' % md(x["why"])
    return ('<article class="wide tle"><div class="pic">%s</div><div class="body"><h3>%s</h3><p class="tag">%s</p><dl><dt>How it plays</dt><dd>%s</dd>%s</dl>'
            '<div class="money"><b>Main monetization drivers</b><ol>%s</ol></div></div></article>'
            % (img(x["id"], x["name"]), e(x["name"]), e(x["length"]), md(x["what"]), mid, money))


# two small maps drawn by hand, for the ideas that have no painting
def mini(body, title):
    return '<svg viewBox="0 0 240 150" role="img" aria-label="%s"><rect width="240" height="150" fill="#e2bf8c"/>%s</svg>' % (html.escape(title, quote=True), body)


DIAGRAM_BIOMES = ('<div class="minis">' + mini(
    '<path d="M0 0H130C120 40 90 60 60 70 30 80 10 75 0 90Z" fill="#8fae62"/><path d="M130 0H240V70C200 80 170 60 150 40 140 25 135 10 130 0Z" fill="#c98f62"/>'
    '<path d="M0 90C10 75 30 80 60 70 90 60 120 40 130 0 135 10 140 25 150 40 170 60 200 80 240 70V150H0Z" fill="#e8d3a6"/>'
    '<ellipse cx="50" cy="40" rx="24" ry="13" fill="#6fb6d6"/>'
    '<g fill="#3f6b3a"><circle cx="20" cy="18" r="5"/><circle cx="95" cy="30" r="5"/><circle cx="85" cy="12" r="4"/><circle cx="18" cy="62" r="4"/></g>'
    '<g fill="#7a4a2e"><path d="M175 20l10 -14 10 14Z"/><path d="M210 45l10 -14 10 14Z"/><path d="M160 45l8 -11 8 11Z"/></g>'
    '<g fill="#b98e5a"><path d="M40 118q20 -14 40 0Z"/><path d="M120 110q24 -16 48 0Z"/><path d="M180 128q20 -12 40 0Z"/></g>'
    '<text x="44" y="60" font-size="11" fill="#1a2440">oasis</text><text x="178" y="62" font-size="11" fill="#1a2440">badlands</text><text x="100" y="140" font-size="11" fill="#1a2440">dune sea</text>', "A map split into three districts") + '</div>')

DIAGRAM_HARD = ('<div class="minis">' + mini(
    '<path d="M0 44C50 30 90 70 130 62 180 50 200 90 240 80" fill="none" stroke="#6d3f26" stroke-width="20"/><path d="M0 44C50 30 90 70 130 62 180 50 200 90 240 80" fill="none" stroke="#c98f62" stroke-width="11"/>'
    '<text x="10" y="135" font-size="12" fill="#1a2440">a dry canyon with two crossings</text><rect x="74" y="52" width="16" height="22" fill="#e2bf8c"/><rect x="170" y="56" width="16" height="26" fill="#e2bf8c"/>', "A canyon") + mini(
    '<path d="M18 40L80 22 104 70 60 108 16 84Z" fill="#8b5433"/><path d="M144 44L212 26 226 92 170 118 134 88Z" fill="#8b5433"/>'
    '<path d="M104 70L134 88" stroke="#1a2440" stroke-width="2" stroke-dasharray="4 4"/><text x="70" y="140" font-size="12" fill="#1a2440">two mesas, one gap</text>', "Two mesas") + mini(
    '<path d="M120 26A64 50 0 1 1 72 110" fill="none" stroke="#6d3f26" stroke-width="15"/><path d="M58 96A64 50 0 0 1 96 30" fill="none" stroke="#6d3f26" stroke-width="15"/>'
    '<path d="M108 74l10 -14 10 14Z" fill="#ffd35c"/><text x="52" y="143" font-size="12" fill="#1a2440">a ring with two ways in</text>', "A ring of rock") + '</div>')


def page():
    snow_scene = "".join('<figure class="scene">%s<figcaption>%s</figcaption></figure>' % (img(x["id"], x["caption"]), e(x["caption"])) for x in C.SNOW_SCENES)
    env = "".join("<div><h4>%s</h4><p>%s</p></div>" % (e(a), md(b)) for a, b in C.SNOW_ENV)
    land = "".join("<p>%s</p>" % md(x) for x in C.SNOW_LAND)
    hard = "".join("<div><h4>%s</h4><p>%s</p></div>" % (e(a), md(b)) for a, b in C.SNOW_HARD)
    uses = lambda x: '<p class="uses">Uses: %s</p>' % e(x["uses"])
    parts = {
        "@@PF@@": "".join(past_card(x) for x in C.PAST_FEATURES),
        "@@PC@@": "".join(past_card(x) for x in C.PAST_CONTENT),
        "@@VAR@@": "".join(var_card(x) for x in C.VARIATIONS),
        "@@GEN@@": "".join(gen_card(x) for x in C.GENERATION),
        "@@SNOWS@@": snow_scene, "@@ENV@@": env, "@@LAND@@": land, "@@HARD@@": hard,
        "@@FOD@@": "".join(enemy_card(x) for x in C.FODDER),
        "@@SPE@@": "".join(enemy_card(x, uses(x)) for x in C.SPECIALS),
        "@@UNI@@": "".join(unique_card(x) for x in C.UNIQUE),
        "@@OLD@@": "".join(old_item(x) for x in C.OLD_ITEMS),
        "@@NP@@": "".join(new_item(x, "Passive item") for x in C.NEW_PASSIVES),
        "@@NC@@": "".join(new_item(x, "Card") for x in C.NEW_CARDS),
        "@@NW@@": "".join(new_item(x, "Weapon") for x in C.NEW_WEAPONS),
        "@@TLEI@@": "".join("<p>%s</p>" % md(x) for x in C.TLE_INTRO),
        "@@TP@@": "".join(tle_card(x) for x in C.TLE_PVE),
        "@@TV@@": "".join(tle_card(x, True) for x in C.TLE_PVP),
    }
    t = TEMPLATE
    for k, v in parts.items():
        t = t.replace(k, v)
    return t


TEMPLATE = """<title>Outlaw Ideas Book</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;700&family=Ultra&display=swap">
<style>
/* Layout: a long catalogue in the game's navy and gold: a section head, then grids of painted cards */
:root { --bg:#10172c; --panel:#1a2440; --panel2:#222e50; --ink:#e9eefb; --dim:#a4b0cc; --gold:#ffd35c; --line:#2f3b5c; --hot:#ff6b8f; --green:#7fd65a;
  --display:'Ultra', Georgia, serif; --body:'Rubik', system-ui, sans-serif; color-scheme: dark; }
body { background:var(--bg); color:var(--ink); font:400 16.5px/1.5 var(--body); padding-block:30px 70px; padding-left:max(16px, env(safe-area-inset-left, 0px)); padding-right:max(16px, env(safe-area-inset-right, 0px)); }
main { max-width:1180px; margin:0 auto; display:flex; flex-direction:column; gap:54px; }
h1 { font:400 clamp(36px,6vw,62px)/1.08 var(--display); margin:0 0 10px; color:#fff6dc; text-wrap:balance; }
h2 { font:400 clamp(25px,3.6vw,36px)/1.15 var(--display); margin:0 0 8px; color:#fff6dc; text-wrap:balance; }
h3 { font:400 21px/1.2 var(--display); margin:0 0 3px; color:#fff6dc; }
h4 { font:700 16.5px/1.3 var(--body); margin:0 0 3px; color:var(--gold); }
h5 { font:700 14px/1 var(--body); letter-spacing:.14em; text-transform:uppercase; color:var(--gold); margin:26px 0 12px; }
p { margin:0 0 9px; max-width:74ch; }
img { display:block; width:100%; height:auto; }
.lead { font-size:19px; max-width:70ch; }
.note { color:var(--dim); font-size:15px; }
.pickline { background:#2b2410; padding:10px 14px; border-left:4px solid var(--gold); margin:10px 0 18px; max-width:none; }
nav { display:flex; flex-wrap:wrap; gap:6px 16px; font-size:15px; }
nav a { color:var(--gold); }
.grid { display:grid; gap:16px; grid-template-columns:repeat(auto-fill,minmax(270px,1fr)); }
.card, .mon, .item, .wide { background:var(--panel); min-width:0; }
.card .body, .mon .body { padding:12px 14px 14px; }
.tag { color:var(--gold); font-size:14.5px; font-weight:500; margin-bottom:7px; }
.why, .cost, .gap, .uses { font-size:15px; color:var(--dim); }
.why b, .cost b, .gap b { color:var(--ink); }
.uses { color:var(--green); }
.mons { display:grid; gap:14px; grid-template-columns:repeat(auto-fill,minmax(210px,1fr)); }
.mon .pic { background:#cbd5e4; }
.mon p { font-size:15px; }
.wide { display:grid; grid-template-columns:minmax(0,5fr) minmax(0,6fr); margin-bottom:16px; }
.wide .pic { min-width:0; }
.wide .pic img { height:100%; object-fit:cover; }
.wide .pic.square { background:#cbd5e4; }
.wide .pic.square img { object-fit:contain; }
.wide .body { padding:16px 18px; min-width:0; }
.wide.wild { outline:2px solid var(--hot); }
dl { margin:6px 0 0; display:grid; gap:7px; }
dt { font:700 13px/1.2 var(--body); letter-spacing:.07em; text-transform:uppercase; color:var(--dim); }
dd { margin:0 0 3px; font-size:15.5px; }
.pill { font:700 12px/1 var(--body); letter-spacing:.08em; text-transform:uppercase; padding:3px 7px; vertical-align:middle; }
.hot { background:var(--hot); color:#2a0612; }
.items { display:grid; gap:14px; grid-template-columns:repeat(auto-fill,minmax(420px,1fr)); }
.item { display:grid; grid-template-columns:128px minmax(0,1fr); gap:0; }
.item .ico { background:#2c3a60; }
.item .ico img { height:128px; object-fit:cover; }
.item .body { padding:12px 14px; min-width:0; }
.item p { font-size:15px; }
.scenes { display:grid; gap:14px; grid-template-columns:repeat(auto-fit,minmax(320px,1fr)); margin-bottom:18px; }
figure.scene { margin:0; background:var(--panel); min-width:0; }
figure.scene figcaption { padding:9px 12px; color:var(--dim); font-size:14.5px; }
.cols { display:grid; gap:12px 22px; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); }
.cols > div { min-width:0; }
.cols p { font-size:15.5px; }
.money { background:#2b2410; padding:10px 14px; margin-top:12px; border-left:4px solid var(--gold); }
.money b { color:var(--gold); }
.money ol { margin:6px 0 0; padding-left:20px; font-size:15px; display:grid; gap:3px; }
.minis { display:grid; gap:6px; background:#0d1428; padding:6px; }
.minis svg { width:100%; height:auto; display:block; font-family:var(--body); }
code { font-size:.92em; color:var(--gold); }
@media (max-width:760px) { .wide { grid-template-columns:minmax(0,1fr); } .items { grid-template-columns:minmax(0,1fr); } .item { grid-template-columns:96px minmax(0,1fr); } .item .ico img { height:96px; } }
</style>
<main>
<header>
<h1>Outlaw Survivors: the ideas book</h1>
<p class="lead">Everything you asked for, with concept art painted by the local AI (Flux.2 Klein on your server, in the game's style). Nothing here is built. Numbers are starting points for the Level Editor. The pictures are concepts: any words painted in them are the AI's nonsense.</p>
<nav><a href="#last">Last time's ten ideas</a><a href="#var">Map variations</a><a href="#gen">Map generation</a><a href="#snow">The Snow Map</a><a href="#foes">Snow enemies</a><a href="#old">Items not taken</a><a href="#new">15 new items</a><a href="#tle">Time-limited events</a></nav>
</header>

<section id="last">
<h2>The ten ideas from last time</h2>
<p>The list you asked for before this one, now with art.</p>
<h5>Features</h5><div class="grid">@@PF@@</div>
<h5>Content</h5><div class="grid">@@PC@@</div>
</section>

<section id="var">
<h2>Map variations</h2>
<p>On top of Nightfall and Blood Moon. Each stays a desert but changes at least four of these at once, because a filter alone only reads as "the same map, tinted": <b>the ground's texture and pattern</b>, <b>the set of props</b>, <b>where the light comes from</b>, <b>what's moving in the air</b>, and <b>one small rule</b> that makes you play it differently. All of it is data, like the stages' filters today.</p>
<p class="pickline"><b>If I had to pick:</b> Salt Flat Noon first. It's cheap, and it's the strongest contrast with what you have. Then Roswell, as the one people will screenshot and share.</p>
@@VAR@@
</section>

<section id="gen">
<h2>Map generation</h2>
<p>Why the seed doesn't feel like much today: it moves things around, but every run has the same ingredients in the same proportions, so the eye reads the same place. What makes a map memorable is <b>unevenness</b>: something big here, nothing there, a route you have to take. Seven ideas.</p>
<p class="pickline"><b>If I had to pick:</b> Districts and Named traits first (both cheap, big effect), then One big landmark. Real walls have the largest effect on play, but they need new creature steering.</p>
<div class="grid">@@GEN@@</div>
</section>

<section id="snow">
<h2>The Snow Map</h2>
<p>A high Colorado valley, flat for the top-down camera. To be more than a reskin it needs three things the desert doesn't have: a <b>big slippery lake</b>, <b>long walls that shape routes</b> and <b>tracks left in the snow</b>.</p>
<div class="scenes">@@SNOWS@@</div>
<h5>What environment art it needs</h5><div class="cols">@@ENV@@</div>
<h5>The landscape</h5>@@LAND@@
<h5>The hard map elements</h5><div class="cols">@@HARD@@</div>
</section>

<section id="foes">
<h2>Snow enemies</h2>
<p>Twenty, painted as they might look before the sprite pipeline. Snow is pale, so I kept dark shapes and strong accents wherever I could: the white ones (hare, goat, yeti) need a dark outline or a stronger rim in play.</p>
<h5>Ten fodder: they just walk at you</h5><div class="mons">@@FOD@@</div>
<h5>Seven that do things, with mechanics the game already has</h5><div class="mons">@@SPE@@</div>
<h5>Three with new mechanics</h5>@@UNI@@
</section>

<section id="old">
<h2>Items: the ideas you haven't taken</h2>
<p>From the legendary list (pass 118) and the earlier list (pass 116). Taken and left out: Iron Horse, Pocket Bible, Fool's Gold, Undertaker's Shovel, Lightning in a Bottle, and the Blacksmith's Anvil, which became the Grindstone.</p>
<div class="items">@@OLD@@</div>
</section>

<section id="new">
<h2>Items: fifteen new ones</h2>
<p>Same brief as before: holes compared with Megabonk, Vampire Survivors, Lonely Survivor and Survivor.io, and each with a real choice in it, including when you would <b>not</b> take it. Different from everything above.</p>
<h5>Eight passive items</h5><div class="items">@@NP@@</div>
<h5>Two Cards</h5><div class="items">@@NC@@</div>
<h5>Five weapons</h5><div class="items">@@NW@@</div>
</section>

<section id="tle">
<h2>Time-limited events</h2>
@@TLEI@@
<p class="pickline"><b>If I had to pick an order:</b> Bounty Season first: it's the steady earner and it's built on posters you already have. Then The Daily Canyon Board, because it brings people back every day and shows off the replays. Hero Debut Trial whenever a new hero is ready.</p>
<h5>PvE events</h5>@@TP@@
<h5>Competitive events, and how they work with few players</h5>
<p>The problem with a small player base is empty boards and long waits. All three below avoid it the same way: <b>nothing needs two people online</b>. You compete with real recorded runs, which your replay system can already store and verify, and each player only sees a small group. I'd tell players plainly when a rival is a past run.</p>
@@TV@@
<p class="note">Sources for the market notes: <a href="https://naavik.co/deep-dives/survivorio-archeros-footsteps/">Naavik on Survivor.io and Archero</a>, <a href="https://jwittsf.design.blog/2020/04/12/breaking-down-archeros-hero-adventure-event">Breaking down Archero's Hero Adventure event</a>, <a href="https://gameindustrylibrary.com/documents/in-game-events-snapshot-2021?page=3">GameRefinery's in-game events snapshot</a>. They're older and don't split revenue by feature, so take them as direction, not as numbers.</p>
</section>
</main>
"""


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page())
    print("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1048576.0))


if __name__ == "__main__":
    main()

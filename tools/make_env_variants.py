"""Pass 128 (lane ENV; Garry: "create an HTML where you list the environment asset images and their named 5
variations. I will go through them and say which ones to add, which ones to forget. I will call them by name."):
the page docs/env_variants/index.html, one self-contained file.

A section per scenery prop kind (tools/env_variations.json's order): the kind's own painting and today's variants
(tagged "in the game"), then its five new variations (the picks of tools/gen_env_variations.py: tools/dl/p128/ENV/
picks/<id>.png, picks.json for the "weak" tag), each on the game's sand colour at the same scale inside its section
(the quad's `height`), its name large and its id small beneath. Pictures are embedded as 320 px JPEGs (q 85).

  python tools/make_env_variants.py [--out docs/env_variants/index.html]
"""
import base64
import html
import io
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import gen_env_variations as gev  # noqa: E402

OUT = os.path.join(REPO, "docs", "env_variants", "index.html")
TILE = 320
QUALITY = 85

# what a kind is called on the page
TITLES = {
    "saguaro_big": "Big Saguaro", "saguaro_small": "Small Saguaro", "barrel_cactus": "Barrel Cactus", "agave": "Agave",
    "dead_shrub": "Dead Shrub", "dead_tree": "Dead Tree", "mesquite_tree": "Mesquite Tree", "palo_verde": "Palo Verde",
    "rock_small": "Small Rock", "rock_big": "Big Rock", "boulder": "Boulder", "skull": "Cow Skull",
    "skull_small": "Small Skull", "bones": "Bones", "joshua_tree": "Joshua Tree", "desert_bush": "Desert Bush",
    "creosote_bush": "Creosote Bush", "brittlebush": "Brittlebush", "fan_palm": "Fan Palm", "ocotillo": "Ocotillo",
    "cart_toppled": "Toppled Cart",
}

CSS = """
/* one dark look on purpose (Garry reads dark reports; the sand tiles carry the light): no light palette */
:root {
  --bg: #1b1612; --surface: #262019; --ink: #f1e6d4; --muted: #b4a18b; --line: #3c3128; --accent: #ea8f60;
  --game-bg: #2b3a27; --game-ink: #b7d8aa; --weak-bg: #4b241d; --weak-ink: #f4b3a6; --sand: #d6bc91;
  color-scheme: dark;
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; scroll-behavior: smooth; }
body {
  margin: 0; padding-block: 0 48px; padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px)); background: var(--bg); color: var(--ink);
  font: 16px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  overflow-wrap: anywhere;
}
main { max-width: 1040px; margin: 0 auto; }
h1, h2, .name { font-family: Rockwell, "Roboto Slab", Georgia, "Times New Roman", serif; }
h1 { font-size: 2rem; line-height: 1.15; margin: 28px 0 8px; }
.lead { margin: 0 0 14px; color: var(--muted); max-width: 62ch; }
.how {
  margin: 0 0 18px; padding: 12px 14px; background: var(--surface); border: 1px solid var(--line);
  border-left: 4px solid var(--accent); border-radius: 10px; max-width: 62ch;
}
.how b { color: var(--accent); }
.how p { margin: 0; }
.how p + p { margin-top: 6px; color: var(--muted); font-size: 0.92rem; }
nav { display: flex; flex-wrap: wrap; gap: 8px; margin: 0 0 8px; padding: 0; }
nav a {
  display: inline-block; padding: 6px 11px; border: 1px solid var(--line); border-radius: 999px;
  background: var(--surface); color: var(--ink); text-decoration: none; font-size: 0.9rem;
}
nav a:hover, nav a:focus-visible { border-color: var(--accent); color: var(--accent); }
section { margin-top: 34px; padding-top: 18px; border-top: 2px solid var(--line); scroll-margin-top: 8px; }
.head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 12px; margin-bottom: 12px; }
h2 { font-size: 1.5rem; line-height: 1.2; margin: 0; }
.meta { color: var(--muted); font-size: 0.85rem; }
.top { margin-left: auto; color: var(--muted); font-size: 0.85rem; text-decoration: none; }
.top:hover { color: var(--accent); }
.sub { margin: 14px 0 8px; color: var(--muted); font-size: 0.78rem; letter-spacing: 0.08em; text-transform: uppercase; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(132px, 1fr)); gap: 12px; }
@media (min-width: 860px) { .grid { grid-template-columns: repeat(5, 1fr); } }
figure { margin: 0; min-width: 0; background: var(--surface); border: 1px solid var(--line); border-radius: 12px; overflow: hidden; }
figure img { display: block; width: 100%; height: auto; aspect-ratio: 1 / 1; background: var(--sand); }
figcaption { padding: 8px 10px 10px; }
.name { display: block; font-size: 1.2rem; line-height: 1.2; font-weight: 700; }
.old .name { font-size: 1rem; font-weight: 400; color: var(--muted); }
.id { display: block; margin-top: 2px; color: var(--muted); font: 0.75rem/1.3 ui-monospace, Consolas, "Courier New", monospace; }
.tag { display: inline-block; margin-top: 6px; padding: 1px 8px; border-radius: 999px; font-size: 0.72rem; font-weight: 600; }
.tag.game { background: var(--game-bg); color: var(--game-ink); }
.tag.weak { background: var(--weak-bg); color: var(--weak-ink); }
footer { margin-top: 40px; padding-top: 14px; border-top: 1px solid var(--line); color: var(--muted); font-size: 0.85rem; }
"""


def tile(png, share):
    """The painting (its square cell) on sand, `share` of the tile tall, standing on the tile's bottom edge: a JPEG data URI."""
    im = Image.open(png).convert("RGBA")
    px = max(8, int(round(TILE * share)))
    im = im.resize((px, px), Image.LANCZOS)
    bg = Image.new("RGBA", (TILE, TILE), gev.SAND + (255,))
    bg.alpha_composite(im, ((TILE - px) // 2, TILE - px))
    buf = io.BytesIO()
    bg.convert("RGB").save(buf, "JPEG", quality=QUALITY, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def figure(src, name, id_, alt, old=False, weak=False):
    tags = ""
    if old:
        tags += '<span class="tag game">in the game</span>'
    if weak:
        tags += '<span class="tag weak">weak</span>'
    return ('<figure%s><img src="%s" width="%d" height="%d" loading="lazy" alt="%s"><figcaption><span class="name">%s</span>'
            '<span class="id">%s</span>%s</figcaption></figure>'
            % (' class="old"' if old else "", src, TILE, TILE, html.escape(alt, quote=True), html.escape(name), html.escape(id_), tags))


def build():
    _, rows = gev.load_list()
    picks = gev.load_picks()
    man = json.load(open(os.path.join(gev.PROPS, "props.json"), encoding="utf-8"))
    kinds = gev.bases(rows)
    names = [r["name"] for r in rows]
    if len(set(n.lower() for n in names)) != len(names):
        raise SystemExit("make_env_variants: two variations share a name")
    weak_n = sum(1 for r in rows if picks.get(r["id"], {}).get("weak"))
    missing = []
    parts = []
    for base in kinds:
        height = float(man[base]["height"])
        olds = gev.in_game(base)
        news = [r for r in rows if r["base"] == base]
        tallest = max([float(man[i]["height"]) for i, _ in olds] + [float(r.get("height", height)) for r in news])
        title = TITLES.get(base, base)
        old_figs = []
        for id_, path in olds:
            label = "Original" if id_ == base else "Variant " + id_[len(base) + 1:].upper()
            old_figs.append(figure(tile(path, float(man[id_]["height"]) / tallest), label, id_, "%s, %s, in the game" % (title, label.lower()), old=True))
        new_figs = []
        for r in news:
            p = picks.get(r["id"], {})
            path = os.path.join(gev.PICKS, r["id"] + ".png")
            if not os.path.exists(path):
                path = gev.cand_path(r, int(p.get("pick", 0)))
            if not os.path.exists(path):
                missing.append(r["id"])
                continue
            new_figs.append(figure(tile(path, float(r.get("height", height)) / tallest), r["name"], r["id"],
                                   "%s variation: %s" % (title, r["name"]), weak=bool(p.get("weak"))))
        parts.append(
            '<section id="%s"><div class="head"><h2>%s</h2><span class="meta">%s &middot; %s m tall in the game</span>'
            '<a class="top" href="#top">back to top</a></div>'
            '<p class="sub">In the game now</p><div class="grid">%s</div>'
            '<p class="sub">New variations</p><div class="grid">%s</div></section>'
            % (base, html.escape(title), base, ("%.2f" % height).rstrip("0").rstrip("."), "".join(old_figs), "".join(new_figs)))
    nav = "".join('<a href="#%s">%s</a>' % (b, html.escape(TITLES.get(b, b))) for b in kinds)
    n_new = len(rows) - len(missing)
    weak_line = (" A red <b>weak</b> tag marks one that came out poorly on both tries; it is listed anyway." if weak_n else "")
    page = (
        '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n<title>Prop Variations</title>\n'
        "<style>%s</style>\n</head>\n<body>\n<main id=\"top\">\n"
        "<h1>Prop Variations</h1>\n"
        '<p class="lead">%d new variations of the %d scenery props of Red Canyon, five each. None of them is in the game yet.</p>\n'
        '<div class="how"><p>Go through them and answer by name: <b>&ldquo;add Old Giant, forget Lone Spear&rdquo;</b>. '
        "Anything you do not mention stays out.</p>"
        "<p>Every picture stands on the game's sand colour. A green <b>in the game</b> tag marks what a map already "
        "places: it is here for comparison only.%s</p></div>\n"
        "<nav aria-label=\"Props\">%s</nav>\n%s\n"
        "<footer>Pass 128, lane ENV. Painted with Flux.2 Klein from each prop's own painting and the style anchor, "
        "finished like the props in the game. The list: tools/env_variations.json. The full-size pictures: "
        "tools/dl/p128/ENV/picks/.</footer>\n</main>\n</body>\n</html>\n"
        % (CSS, n_new, len(kinds), weak_line, nav, "\n".join(parts)))
    return page, missing, weak_n


def main():
    out = OUT
    if "--out" in sys.argv:
        out = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])
    page, missing, weak_n = build()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    # the copy the Artifact tool publishes: the title, the side-gutter promise and the style on top, then the body's own
    # content; no doctype, html, head or body tags (the publisher wraps the file in its own skeleton)
    css = page.split("<style>", 1)[1].split("</style>", 1)[0]
    body = page.split("<body>", 1)[1].rsplit("</body>", 1)[0]
    with open(os.path.join(os.path.dirname(out), "artifact.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write('<title>Prop Variations</title>\n<meta name="claude:viewport-fit-sides" content="cover">\n'
                "<style>%s</style>\n%s" % (css, body.strip("\n") + "\n"))
    print("make_env_variants: %s  %.2f MB  weak %d%s" % (out, os.path.getsize(out) / 1e6, weak_n, ("  NOT PAINTED: " + ", ".join(missing)) if missing else ""))


if __name__ == "__main__":
    main()

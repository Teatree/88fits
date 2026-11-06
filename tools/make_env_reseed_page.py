"""Pass 130 (Garry: "five variations, just using a different seed but ultimately trying to recreate the same thing ...
five variations of all the existing art assets ... I want variations for each please"): the page of re-draws,
docs/env_variants/redraws.html (one self-contained file) and redraws_artifact.html (the copy the Artifact tool publishes).

A section per scenery prop kind; inside it one row per painting of that kind in the game (the kind's own painting and
each of its variants on its own): the painting as it is in the game, then its five re-draws (tools/gen_env_reseed.py:
tools/dl/p130/ENV/cands/<id>_s<k>.png), named "<the painting's name> 1" to "5". tools/dl/p130/ENV/notes.json
({"<id>": {"weak": [k, ...], "note": "..."}}, written by hand after looking at the sheets) tags a re-draw that came out
poorly and puts a line under a row.

  python tools/make_env_reseed_page.py
"""
import html
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import gen_env_reseed as ger  # noqa: E402
import make_env_variants as mev  # noqa: E402

OUT = os.path.join(REPO, "docs", "env_variants", "redraws.html")
NOTES = os.path.join(ger.ENV, "notes.json")
SEEDS = 5

CSS_MORE = """
.row { margin-top: 18px; }
.row h3 { margin: 0 0 8px; font: 700 1.05rem/1.2 Rockwell, "Roboto Slab", Georgia, serif; }
.row h3 .id { display: inline; margin-left: 8px; font-weight: 400; }
.grid6 { display: grid; grid-template-columns: repeat(auto-fill, minmax(118px, 1fr)); gap: 10px; }
@media (min-width: 860px) { .grid6 { grid-template-columns: repeat(6, 1fr); } }
.grid6 .name { font-size: 1rem; }
.note { margin: 8px 0 0; color: var(--muted); font-size: 0.88rem; max-width: 70ch; }
"""


def painting_names():
    """{painting id: the name the page calls it by}: a kind's own painting "<Kind>", a lettered variant "<Kind> B", one
    of Garry's named variations its name."""
    man = json.load(open(os.path.join(ger.PROPS, "props.json"), encoding="utf-8"))
    env = {r["id"]: r["name"] for r in json.load(open(os.path.join(HERE, "env_variations.json"), encoding="utf-8"))["rows"]}
    out = {}
    for id_, row in man.items():
        base = row.get("variant_of") or id_
        title = mev.TITLES.get(base, base)
        if id_ == base:
            out[id_] = title
        elif id_ in env:
            out[id_] = env[id_]
        else:
            out[id_] = "%s %s" % (title, id_[len(base) + 1:].upper())
    return out


def build():
    man = json.load(open(os.path.join(ger.PROPS, "props.json"), encoding="utf-8"))
    notes = json.load(open(NOTES, encoding="utf-8")) if os.path.exists(NOTES) else {}
    names = painting_names()
    rows = ger.paintings()
    kinds = []
    for id_, _, _, _ in rows:
        base = man[id_].get("variant_of") or id_
        if base not in kinds:
            kinds.append(base)
    parts = []
    n_new = 0
    n_paint = 0
    missing = []
    for base in kinds:
        mine = [r[0] for r in rows if (man[r[0]].get("variant_of") or r[0]) == base]
        tallest = max(float(man[i]["height"]) for i in mine)
        title = mev.TITLES.get(base, base)
        body = []
        for id_ in mine:
            share = float(man[id_]["height"]) / tallest
            note = notes.get(id_, {})
            figs = [mev.figure(mev.tile(os.path.join(ger.PROPS, id_ + ".png"), share), "In the game", id_, "%s, in the game" % names[id_], old=True)]
            got = 0
            for k in range(SEEDS):
                p = os.path.join(ger.CANDS, "%s_s%d.png" % (id_, k))
                if not os.path.exists(p):
                    continue
                got += 1
                figs.append(mev.figure(mev.tile(p, share), "%s %d" % (names[id_], k + 1), "%s=%d" % (id_, k),
                                       "%s, re-draw %d" % (names[id_], k + 1), weak=k in note.get("weak", [])))
            if got == 0:
                missing.append(id_)
                continue
            n_new += got
            n_paint += 1
            body.append('<div class="row"><h3>%s<span class="id">%s</span></h3><div class="grid6">%s</div>%s</div>'
                        % (html.escape(names[id_]), id_, "".join(figs),
                           ('<p class="note">%s</p>' % html.escape(note["note"])) if note.get("note") else ""))
        if not body:
            continue
        parts.append('<section id="%s"><div class="head"><h2>%s</h2><span class="meta">%d painting%s in the game</span>'
                     '<a class="top" href="#top">back to top</a></div>%s</section>'
                     % (base, html.escape(title), len(body), "" if len(body) == 1 else "s", "".join(body)))
    nav = "".join('<a href="#%s">%s</a>' % (b, html.escape(mev.TITLES.get(b, b))) for b in kinds)
    page = (
        '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n<title>Prop Re-draws</title>\n'
        "<style>%s%s</style>\n</head>\n<body>\n<main id=\"top\">\n"
        "<h1>Prop Re-draws</h1>\n"
        '<p class="lead">%d re-draws of the %d scenery paintings in the game, five each: the same thing under a different '
        "seed. None of them is in the game.</p>\n"
        '<div class="how"><p>Each row is one painting: the first tile is what the game shows now, the next five are its '
        "re-draws. Answer by name: <b>&ldquo;replace Dead Shrub B with Dead Shrub B 2&rdquo;</b> swaps the painting, "
        "<b>&ldquo;add Joshua Tree C 3&rdquo;</b> keeps both. Anything you do not mention stays as it is.</p>"
        "<p>Every picture stands on the game's sand colour. A red <b>weak</b> tag marks a re-draw that came out poorly; "
        "it is listed anyway.</p></div>\n"
        "<nav aria-label=\"Props\">%s</nav>\n%s\n"
        "<footer>Pass 130. Painted with Flux.2 Klein from each painting itself and the style anchor, the colours matched "
        "to the painting, finished like the props in the game. tools/gen_env_reseed.py; the full-size pictures: "
        "tools/dl/p130/ENV/cands/.</footer>\n</main>\n</body>\n</html>\n"
        % (mev.CSS, CSS_MORE, n_new, n_paint, nav, "\n".join(parts)))
    return page, missing, n_new, n_paint


def main():
    page, missing, n_new, n_paint = build()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    css = page.split("<style>", 1)[1].split("</style>", 1)[0]
    body = page.split("<body>", 1)[1].rsplit("</body>", 1)[0]
    with open(os.path.join(os.path.dirname(OUT), "redraws_artifact.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write('<title>Prop Re-draws</title>\n<meta name="claude:viewport-fit-sides" content="cover">\n'
                "<style>%s</style>\n%s" % (css, body.strip("\n") + "\n"))
    print("make_env_reseed_page: %s  %.2f MB  %d re-draws of %d paintings%s"
          % (OUT, os.path.getsize(OUT) / 1e6, n_new, n_paint, ("  NOT PAINTED: " + ", ".join(missing)) if missing else ""))


if __name__ == "__main__":
    main()

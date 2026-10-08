"""The listening page for pass 60's sounds: docs/sfx_review.html and tools/dl/sfx60/sfx_review.zip.

Every non-music sound id with its trigger, prompt, kind and length; the sound the game plays (game/content/sounds/real/
<id>.wav, picked from the Stable Audio candidates) beside the other candidates of its engine, the best candidate of the
other engine as an alternate (AudioGen, the first run of pass 60), the old placeholder, and for the ten voice ids the
old Kokoro line kept in tools/dl/sfx60/old_voice/; each with its spectral centroid, so "lower than before" can be read
off the page, and the score the automatic pick used. Groups by prefix, one dark page, no scripts beyond
play-one-at-a-time.

The zip holds the same page with the wavs beside it (real/, cands/<engine>/, old/, old_voice/), so it can be dropped in
Drive and listened to on the phone. To change a pick after listening: python tools/ai_sfx.py --pick <id>=<k> (a Stable
candidate) or --pick <id>=audiogen:<k> (the AudioGen alternate), then this again.

Run: python tools/make_sfx_review.py [--no-zip]
"""
import html
import json
import os
import statistics
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ai_sfx as A  # noqa: E402

DOCS = os.path.join(A.ROOT, "docs")
PAGE = os.path.join(DOCS, "sfx_review.html")
ZIP = os.path.join(A.DL, "sfx_review.zip")
OLD_VOICE = os.path.join(A.DL, "old_voice")
PLACEHOLDER = os.path.join(A.SOUNDS, "placeholder")
ENGINE_NAME = {"stable": "Stable Audio", "audiogen": "AudioGen"}

# the ten Kokoro lines of pass 24-59 (tools/dl/backup/gen_voice_pass59.py), for the record
VOICE_LINES = {
    "pl_hurt": "Oof!", "pl_death": "Noooooo!", "pl_revive": "I'm back, baby!", "pl_jump": "Hup!",
    "ui_levelup": "Level up!", "ui_unlock": "Unlocked!", "wd_extract": "Extracted! Cha-ching.",
    "en_elite_spawn": "Uh oh.", "en_boss_roar": "Bow before the Tumbleweed King!",
    "en_boss_die": "My crown! My beautiful crown!",
}

CSS = """
:root { --bg:#15131a; --card:#1f1c27; --ink:#e8e2f2; --dim:#9b93ad; --line:#2f2a3b; --brass:#d9a441; --good:#5fc08a;
  --bad:#e06c6c; --pick:#2c3a2e; --alt:#2a2535; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.45 "Segoe UI", system-ui, sans-serif; }
header { padding:28px 32px 18px; border-bottom:1px solid var(--line); }
h1 { margin:0 0 6px; font-size:26px; letter-spacing:.3px; }
h1 small { color:var(--dim); font-size:14px; font-weight:400; margin-left:12px; }
.stats { display:flex; gap:28px; flex-wrap:wrap; color:var(--dim); margin-top:10px; }
.stats b { color:var(--ink); font-size:20px; display:block; }
.how { color:var(--dim); margin-top:12px; max-width:980px; }
.how code { color:var(--brass); background:#0f0d14; padding:1px 6px; border-radius:4px; }
nav { padding:12px 32px; border-bottom:1px solid var(--line); display:flex; gap:16px; flex-wrap:wrap; }
nav a { color:var(--brass); text-decoration:none; }
section { padding:18px 32px 8px; }
h2 { margin:14px 0 10px; font-size:19px; color:var(--brass); }
.row { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:12px 16px; margin:0 0 12px;
  display:grid; grid-template-columns: 330px 1fr; gap:10px 22px; }
.id { font-family: ui-monospace, Consolas, monospace; font-size:16px; color:#fff; }
.meta { color:var(--dim); font-size:13px; margin-top:2px; }
.trig { color:var(--ink); }
.prompt { color:#c9c2d8; font-style:italic; margin-top:6px; font-size:14px; }
.note { color:var(--brass); font-size:13px; margin-top:6px; }
.players { display:flex; flex-wrap:wrap; gap:10px 18px; align-items:flex-start; }
.pl { min-width:230px; }
.pl .lab { font-size:12px; color:var(--dim); text-transform:uppercase; letter-spacing:.6px; }
.pl .lab b { color:var(--ink); }
.pl.picked .lab b { color:var(--good); }
.pl.picked { background:var(--pick); border-radius:8px; padding:4px 6px 2px; margin:-4px -6px -2px; }
.pl.alt { background:var(--alt); border-radius:8px; padding:4px 6px 2px; margin:-4px -6px -2px; }
audio { width:230px; height:32px; display:block; margin-top:3px; filter: invert(.88) hue-rotate(180deg); }
.num { font-family: ui-monospace, Consolas, monospace; font-size:12px; color:var(--dim); margin-top:2px; }
.down { color:var(--good); } .up { color:var(--bad); }
footer { padding:20px 32px 40px; color:var(--dim); font-size:13px; }
@media (max-width: 900px) { .row { grid-template-columns: 1fr; } header, section, nav, footer { padding-left:16px; padding-right:16px; } }
"""

JS = """
document.addEventListener('play', function (e) {
  document.querySelectorAll('audio').forEach(function (a) { if (a !== e.target) a.pause(); });
}, true);
"""


def rel_paths(mode):
    """Where the page finds the wavs: next to the repo's docs/ (mode repo) or in the zip's folders (mode zip)."""
    if mode == "zip":
        return {"real": "real/", "cands": "cands/%s/", "old": "old/", "old_voice": "old_voice/"}
    return {"real": "../game/content/sounds/real/", "cands": "../tools/dl/sfx60/%s/proc/",
            "old": "../game/content/sounds/placeholder/", "old_voice": "../tools/dl/sfx60/old_voice/"}


def fmt_hz(v):
    return "%.0f Hz" % v if v is not None else "-"


def player(label, src, nums, cls="pl"):
    return ('<div class="%s"><div class="lab">%s</div><audio controls preload="none" src="%s"></audio>'
            '<div class="num">%s</div></div>' % (cls, label, html.escape(src), html.escape(nums)))


def cand_nums(c):
    return "%s · %.1f dB · %.2f s · score %.2f" % (fmt_hz(c["centroid"]), c["rms_db"], c["seconds"], c["score"])


def pick_of(sid, scores, picks):
    """(engine, pick dict, the picked candidate's measures) or (None, None, None)."""
    p = picks.get(sid)
    if not p:
        return None, None, None
    e = p.get("engine", "audiogen")
    c = next((c for c in scores.get(e, {}).get(sid, {}).get("cands", []) if c["k"] == p["k"]), None)
    return e, p, c


def alternates(sid, engine, scores):
    """The other engines' best candidates: [(engine, cand)]."""
    out = []
    for e in A.ENGINES:
        if e == engine:
            continue
        best = A.best_of(scores.get(e, {}).get(sid, {}).get("cands", []))
        if best is not None:
            out.append((e, best))
    return out


def row_html(sid, row, scores, picks, volume, paths):
    engine, p, chosen = pick_of(sid, scores, picks)
    old = (scores.get(engine or A.DEFAULT_ENGINE, {}).get(sid, {}).get("old")
           or scores.get("audiogen", {}).get(sid, {}).get("old") or {})
    kind = "%s · %.2f s%s" % (row["kind"], row["seconds"], (" · %+d st" % row["pitch"]) if row["pitch"] else "")
    left = ['<div><div class="id">%s</div><div class="meta">%s · volume %s dB</div>' % (sid, kind, volume),
            '<div class="meta trig">%s</div>' % html.escape(row["trigger"])]
    if row["prompt"] is None:
        left.append('<div class="note">Silenced: points at real/silence.wav (was the voice line "%s").</div>' % html.escape(VOICE_LINES.get(sid, "")))
    else:
        left.append('<div class="prompt">%s</div>' % html.escape(A.engine_prompt(engine or A.DEFAULT_ENGINE, row)))
        if sid in VOICE_LINES:
            left.append('<div class="note">Replaces the voice line "%s".</div>' % html.escape(VOICE_LINES[sid]))
    left.append("</div>")
    right = ['<div class="players">']
    oc = old.get("centroid")
    if row["prompt"] is not None:
        if chosen:
            nc = chosen["centroid"]
            delta = ""
            if oc:
                delta = ' <span class="%s">(%+.0f%%)</span>' % ("down" if nc < oc else "up", 100.0 * (nc - oc) / oc)
            right.append(player("<b>New</b> · %s c%d %s" % (ENGINE_NAME[engine], chosen["k"], "by ear" if p.get("manual") else "auto"),
                                paths["real"] + sid + ".wav", cand_nums(chosen), "pl picked")
                         .replace('</div></div>', '%s</div></div>' % delta, 1))
            for c in scores[engine].get(sid, {}).get("cands", []):
                if c["k"] == chosen["k"]:
                    continue
                right.append(player("%s c%d" % (ENGINE_NAME[engine], c["k"]), paths["cands"] % engine + "%s_c%d.wav" % (sid, c["k"]), cand_nums(c)))
            for e, c in alternates(sid, engine, scores):
                note = ""
                if c.get("prompt") and c["prompt"] != A.engine_prompt(e, row):
                    note = " (its own prompt)"
                right.append(player("%s alternate · c%d%s" % (ENGINE_NAME[e], c["k"], note), paths["cands"] % e + "%s_c%d.wav" % (sid, c["k"]),
                                    cand_nums(c), "pl alt"))
        else:
            right.append('<div class="pl"><div class="lab"><b>New</b></div><div class="num">not picked yet</div></div>')
    else:
        right.append(player("<b>New</b> · silence", paths["real"] + A.SILENCE, "50 ms of nothing", "pl picked"))
    if os.path.exists(os.path.join(PLACEHOLDER, sid + ".wav")):
        right.append(player("Old placeholder", paths["old"] + sid + ".wav", fmt_hz(oc) if oc else ""))
    if sid in VOICE_LINES and os.path.exists(os.path.join(OLD_VOICE, sid + ".wav")):
        right.append(player("Old voice", paths["old_voice"] + sid + ".wav", '"%s"' % VOICE_LINES[sid]))
    right.append("</div>")
    return '<div class="row" id="%s">%s%s</div>' % (sid, "".join(left), "".join(right))


def summary(scores, picks):
    olds, news, lower, n = [], [], 0, 0
    engines = {e: 0 for e in A.ENGINES}
    for sid in A.gen_ids():
        e, p, c = pick_of(sid, scores, picks)
        if c is None:
            continue
        engines[e] += 1
        oc = (scores[e].get(sid, {}).get("old") or {}).get("centroid")
        if oc is None:
            continue
        n += 1
        olds.append(oc)
        news.append(c["centroid"])
        lower += 1 if c["centroid"] < oc else 0
    size = sum(os.path.getsize(os.path.join(A.REAL, f)) for f in os.listdir(A.REAL) if f.endswith(".wav")) if os.path.isdir(A.REAL) else 0
    return {"n": n, "lower": lower, "old_med": statistics.median(olds) if olds else 0, "new_med": statistics.median(news) if news else 0,
            "mb": size / 1e6, "manual": sum(1 for p in picks.values() if p.get("manual")), "engines": engines}


def build(mode, scores, picks, volumes):
    paths = rel_paths(mode)
    st = summary(scores, picks)
    eng = ", ".join("%d %s" % (n, ENGINE_NAME[e]) for e, n in st["engines"].items() if n)
    out = ['<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">',
           "<title>88fits sounds, pass 60</title><style>%s</style></head><body>" % CSS,
           '<header><h1>88fits sounds, pass 60 <small>Stable Audio first, AudioGen as the alternate: every effect in a lower register, the voices gone</small></h1>',
           '<div class="stats"><div><b>%d</b>sounds regenerated</div><div><b>%d of %d</b>read lower than the placeholder</div>'
           '<div><b>%.0f Hz &rarr; %.0f Hz</b>median spectral centroid, old &rarr; new</div><div><b>%.1f MB</b>the real/ set</div>'
           '<div><b>%s</b>engines picked</div><div><b>%d</b>picks by ear</div></div>' % (
               len(A.gen_ids()), st["lower"], st["n"], st["old_med"], st["new_med"], st["mb"], eng or "-", st["manual"]),
           '<div class="how">Each row: the sound the game plays (<b>New</b>, green), the other candidates of its engine, the best candidate '
           'of the other engine as an alternate (violet), and the old placeholder (and the old voice line where there was one). The centroid '
           'is the spectral centre of gravity: lower reads duller and deeper (AudioGen is a 16 kHz model, so its clips have nothing above '
           '8 kHz and read lower by nature). To swap a pick after listening: <code>python tools/ai_sfx.py --pick %s=1</code> (a Stable '
           'candidate) or <code>--pick %s=audiogen:2</code> (the alternate), then <code>python tools/make_sfx_review.py</code>. '
           'pl_hurt and pl_jump are silent on purpose (Garry: no voice stuff).</div></header>' % ("pk_gem_s", "pk_gem_s")]
    groups = [g for g in A.GROUP_ORDER if g != "Music"]
    out.append("<nav>%s</nav>" % "".join('<a href="#g-%s">%s</a>' % (g, g) for g in groups))
    for g in groups:
        ids = [sid for sid, r in A.PROMPTS.items() if r["group"] == g]
        out.append('<section id="g-%s"><h2>%s <small style="color:#9b93ad;font-size:13px">%d</small></h2>' % (g, g, len(ids)))
        for sid in ids:
            out.append(row_html(sid, A.PROMPTS[sid], scores, picks, volumes.get(sid, 0), paths))
        out.append("</section>")
    out.append('<footer>Made by tools/make_sfx_review.py from tools/dl/sfx60/&lt;engine&gt;/scores.json and picks.json. Prompts live in '
               'tools/ai_sfx.py (and docs/design/src/sounds.json for the bible).</footer><script>%s</script></body></html>' % JS)
    return "\n".join(out)


def zip_files(scores, picks):
    """(zip path, disk path) for every wav the zip page references."""
    out = []
    for fn in sorted(os.listdir(A.REAL)):
        if fn.endswith(".wav"):
            out.append(("real/" + fn, os.path.join(A.REAL, fn)))
    for sid in A.gen_ids():
        engine, p, chosen = pick_of(sid, scores, picks)
        if chosen is None:
            continue
        for c in scores[engine].get(sid, {}).get("cands", []):
            if c["k"] != chosen["k"]:
                out.append(("cands/%s/%s_c%d.wav" % (engine, sid, c["k"]), A.proc_path(engine, sid, c["k"])))
        for e, c in alternates(sid, engine, scores):
            out.append(("cands/%s/%s_c%d.wav" % (e, sid, c["k"]), A.proc_path(e, sid, c["k"])))
    for fn in sorted(os.listdir(PLACEHOLDER)):
        if fn.endswith(".wav") and not fn.startswith(A.MUSIC_PREFIX):
            out.append(("old/" + fn, os.path.join(PLACEHOLDER, fn)))
    if os.path.isdir(OLD_VOICE):
        for fn in sorted(os.listdir(OLD_VOICE)):
            if fn.endswith(".wav"):
                out.append(("old_voice/" + fn, os.path.join(OLD_VOICE, fn)))
    return [(z, d) for z, d in out if os.path.exists(d)]


def main(argv):
    scores = A.all_scores()
    picks = A.read_json(A.picks_path(), {})
    volumes = {sid: r.get("volume_db", 0) for sid, r in A.soundmap_rows().items()}
    os.makedirs(DOCS, exist_ok=True)
    with open(PAGE, "w", encoding="utf-8", newline="\n") as f:
        f.write(build("repo", scores, picks, volumes))
    print("wrote", PAGE)
    if "--no-zip" in argv:
        return 0
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("sfx_review.html", build("zip", scores, picks, volumes))
        for zpath, disk in zip_files(scores, picks):
            z.write(disk, zpath)
    print("wrote %s (%.1f MB)" % (ZIP, os.path.getsize(ZIP) / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

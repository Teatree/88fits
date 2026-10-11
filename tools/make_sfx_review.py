"""The listening page for the sounds: docs/sfx_review.html and tools/dl/sfx60/sfx_review.zip (pass 60, extended in pass 64).

Pass 64 puts first what changed: the six music tracks (Stable Audio 3 medium, cut into loops by tools/ai_music.py:
the picked loop, a "seam" clip = its last 3 s followed by its first 3 s, so the loop point can be heard, the other
candidates and the old procedural placeholder) and the hype family (the UI, reward and pickup ids made on Stable
Audio 3 by `ai_sfx.py --engine sa3`: the new pick, its other candidates, the pass-60 sound it replaced
(tools/dl/backup/sfx_pass63/real/) and the placeholder). The 3D-world sounds follow, unchanged, folded away.

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
ENGINE_NAME = {"stable": "Stable Audio", "audiogen": "AudioGen", "sa3": "Stable Audio 3"}
BEFORE = os.path.join(A.ROOT, "tools", "dl", "backup", "sfx_pass63", "real")
OLD_MUSIC = os.path.join(A.ROOT, "tools", "dl", "backup", "sfx_pass63", "music")
# pass 65: sounds synthesised in numpy by tools/synth_sfx.py (they win over any ai_sfx pick of the same id); the pass-64
# files they replaced are in tools/dl/backup/sfx_pass64/
BEFORE65 = os.path.join(A.ROOT, "tools", "dl", "backup", "sfx_pass64")
SYNTH65 = [
    ("pk_gem_s", "Small XP gem: a short soft G6 ding (pass 67: quick repeats climb a pentatonic ladder, the three sizes one tune in C major)"),
    ("pk_gem_m", "Medium XP gem: a fuller E6 + B6 ding (its ladder is E minor pentatonic)"),
    ("pk_gem_l", "Large XP gem: a C6 ding-ding with a second strike and a long ring (its ladder is C major pentatonic)"),
    ("pl_hurt", "The hero is hit: a chiptune 'negative' blip, a stepped square falling 620 to 150 Hz with a crunch (at most one per 0.25 s)"),
    ("ui_slot_start", "Slot machine: the lever's ratchet and clunk as the reel starts, a western twang"),
    ("ui_slot_spin", "Slot machine: the spinning loop while the strip runs, its pitch following the strip's speed"),
    ("ui_slot_stop", "Slot machine: the clunk of the reel stopping on the landing cell, before the jackpot"),
]
SEAM_S = 3.0
LISTEN_FIRST = ["mu_run_1", "mu_title", "mu_boss", "ui_levelup", "ui_jackpot", "w_evo_reveal", "pk_chest_open", "ui_tap",
                "pk_gem_s", "pk_coin", "ui_buy", "ui_reel_tick"]

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
        return {"real": "real/", "cands": "cands/%s/", "old": "old/", "old_voice": "old_voice/", "before": "before/",
                "music": "music/", "music_cands": "music_cands/", "seam": "music_seam/", "old_music": "old_music/", "before65": "before65/", "ext": ".mp3"}
    return {"real": "../game/content/sounds/real/", "cands": "../tools/dl/sfx60/%s/proc/",
            "old": "../game/content/sounds/placeholder/", "old_voice": "../tools/dl/sfx60/old_voice/",
            "before": "../tools/dl/backup/sfx_pass63/real/", "music": "../game/content/sounds/music/",
            "music_cands": "../tools/dl/music64/loop/", "seam": "../tools/dl/music64/seam/",
            "old_music": "../tools/dl/backup/sfx_pass63/music/",
            "before65": "../tools/dl/backup/sfx_pass64/", "ext": ".wav"}


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
        e0 = engine or A.DEFAULT_ENGINE
        left.append('<div class="prompt">%s</div>' % html.escape(A.engine_prompt(e0, A.row_for(e0, sid))))
        if engine == "sa3":
            left.append('<div class="note">Pass 64, hype family: %s on Stable Audio 3 (%s).</div>' % (
                html.escape(A.HYPE[sid]["kind"]), ", ".join(A.HYPE[sid]["models"])))
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
                if e == "stable" and engine == "sa3":
                    continue    # the pass-60 pick is the "Before" player
                if c.get("prompt") and c["prompt"] != A.engine_prompt(e, A.row_for(e, sid)):
                    note = " (its own prompt)"
                right.append(player("%s alternate · c%d%s" % (ENGINE_NAME[e], c["k"], note), paths["cands"] % e + "%s_c%d.wav" % (sid, c["k"]),
                                    cand_nums(c), "pl alt"))
        else:
            right.append('<div class="pl"><div class="lab"><b>New</b></div><div class="num">not picked yet</div></div>')
    else:
        right.append(player("<b>New</b> · silence", paths["real"] + A.SILENCE, "50 ms of nothing", "pl picked"))
    if engine == "sa3" and os.path.exists(os.path.join(BEFORE, sid + ".wav")):
        right.append(player("Before (pass 60)", paths["before"] + sid + ".wav", "the dull one Garry heard", "pl alt"))
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


def music_data():
    """(tracks, scores, picks) from tools/ai_music.py's run, or empty when it has not run here."""
    import ai_music as M
    sc = A.read_json(os.path.join(M.DL, "scores.json"), {})
    pk = A.read_json(os.path.join(M.DL, "picks.json"), {})
    return M, sc, pk


def seam_path(M, sid, k):
    return os.path.join(M.DL, "seam", "%s_c%d.wav" % (sid, k))


def make_seams(M, sc):
    """A seam clip per loop candidate: its last SEAM_S seconds then its first SEAM_S seconds (the loop point in the
    middle), so the wrap can be heard without waiting a whole loop."""
    import numpy as np
    import soundfile as sf
    for sid, s in sc.items():
        for c in s.get("cands", []):
            src = M.loop_path(sid, c["k"])
            dst = seam_path(M, sid, c["k"])
            if not os.path.exists(src) or (os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src)):
                continue
            y, sr = sf.read(src, dtype="float32", always_2d=True)
            n = int(SEAM_S * sr)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            sf.write(dst, np.concatenate([y[-n:], y[:n]], axis=0), sr, subtype="PCM_16")


def music_nums(c):
    return "%.0f s · %d bars · %.0f BPM · seam %.3f · click %.1f · %.1f dB" % (
        c["seconds"], c["bars"], c["bpm"], c["dist"], c["seam_click"], c["rms_db"])


def music_html(M, sc, pk, paths):
    if not sc:
        return '<section id="g-music"><h2>Music</h2><div class="meta">tools/ai_music.py has not run here.</div></section>'
    ext = paths["ext"]
    out = ['<section id="g-music"><h2>Music <small style="color:#9b93ad;font-size:13px">Stable Audio 3 medium, seamless loops</small></h2>']
    for sid in M.ORDER:
        s = sc.get(sid)
        if not s:
            continue
        p = pk.get(sid, {})
        chosen = next((c for c in s["cands"] if c["k"] == p.get("k")), None)
        t = M.TRACKS[sid]
        left = ('<div><div class="id">%s</div><div class="meta">%s · loop %d-%d s · asked %d s</div>'
                '<div class="prompt">%s</div></div>' % (sid, html.escape(s.get("role", t["role"])), t["loop"][0], t["loop"][1],
                                                         t["gen"], html.escape(t["prompt"])))
        right = ['<div class="players">']
        if chosen:
            right.append(player("<b>New</b> · c%d %s" % (chosen["k"], "by ear" if p.get("manual") else "auto"),
                                paths["music"] + sid + ext, music_nums(chosen), "pl picked"))
            right.append(player("Loop seam · c%d (end &rarr; start)" % chosen["k"], paths["seam"] + "%s_c%d%s" % (sid, chosen["k"], ext),
                                "the loop point is in the middle", "pl alt"))
        for c in sorted(s["cands"], key=lambda c: c["score"]):
            if chosen and c["k"] == chosen["k"]:
                continue
            right.append(player("c%d · score %.2f" % (c["k"], c["score"]), paths["music_cands"] + "%s_c%d%s" % (sid, c["k"], ext),
                                music_nums(c)))
        if os.path.exists(os.path.join(OLD_MUSIC, sid + ".wav")):
            right.append(player("Old (procedural)", paths["old_music"] + sid + ext, "pass 1-63"))
        right.append("</div>")
        out.append('<div class="row" id="%s">%s%s</div>' % (sid, left, "".join(right)))
    out.append("</section>")
    return "\n".join(out)


def synth65_html(paths):
    """Pass 65's synthesised sounds: new against the pass-64 file (or the silence / nothing it replaced)."""
    import numpy as np
    import soundfile as sf
    out = ['<section id="g-p65"><h2>Pass 65: gem dings, the hero&rsquo;s hurt, the slot machine <small style="color:#9b93ad;font-size:13px">'
           'synthesised in numpy (tools/synth_sfx.py) after Garry&rsquo;s Vampire Survivors references, which are analysed only, never shipped; '
           'these files win over the rows further down</small></h2>']
    for sid, what in SYNTH65:
        src = os.path.join(A.REAL, sid + ".wav")
        nums = ""
        if os.path.exists(src):
            y, sr = sf.read(src)
            S = np.abs(np.fft.rfft(y))
            f = np.fft.rfftfreq(len(y), 1 / sr)
            nums = "%s · %.1f dB · %.2f s" % (fmt_hz((S * f).sum() / max(S.sum(), 1e-9)), 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12), len(y) / sr)
        right = ['<div class="players">', player("<b>New</b>", paths["real"] + sid + ".wav", nums, "pl picked")]
        if os.path.exists(os.path.join(BEFORE65, sid + ".wav")):
            right.append(player("Before (pass 64)", paths["before65"] + sid + ".wav", "the glassy ping", "pl alt"))
        elif sid == "pl_hurt":
            right.append('<div class="pl alt"><div class="lab">Before</div><div class="num">silent since pass 60</div></div>')
        else:
            right.append('<div class="pl alt"><div class="lab">Before</div><div class="num">a new id</div></div>')
        right.append("</div>")
        out.append('<div class="row" id="p65-%s"><div><div class="id">%s</div><div class="meta trig">%s</div></div>%s</div>' % (
            sid, sid, html.escape(what), "".join(right)))
    out.append("</section>")
    return "\n".join(out)


def build(mode, scores, picks, volumes):
    paths = rel_paths(mode)
    st = summary(scores, picks)
    M, msc, mpk = music_data()
    hype = [sid for sid in A.sfx_ids() if sid in A.HYPE]
    n_sa3 = sum(1 for sid in hype if picks.get(sid, {}).get("engine") == "sa3")
    out = ['<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">',
           "<title>88fits sounds, pass 64</title><style>%s</style></head><body>" % CSS,
           '<header><h1>88fits sounds, pass 64 <small>the hype is back: casino and western jingles, bright pickups, soft taps, and new music</small></h1>',
           '<div class="stats"><div><b>%d</b>music tracks (Stable Audio 3 medium)</div><div><b>%d of %d</b>UI and reward sounds on Stable Audio 3</div>'
           '<div><b>%d</b>3D-world sounds kept from pass 60</div><div><b>%d</b>picks by ear</div></div>' % (
               len(mpk), n_sa3, len(hype), len(A.gen_ids()) - len(hype), st["manual"]),
           '<div class="how">Garry: "having that for jingles of Level Up, Chest opens, etc, I like all of that ... sound like a casino a lot of '
           'the time ... button taps soft and simple". Each row: the sound the game plays (<b>New</b>, green), its other candidates, the sound it '
           'replaced (violet, <b>Before (pass 60)</b>) and the old placeholder. Music rows add a <b>loop seam</b> clip (the last 3 s then the '
           'first 3 s) so the loop point can be heard. To swap a pick after listening: <code>python tools/ai_sfx.py --pick ui_levelup=sa3:2</code> '
           '(a sound; <code>=stable:k</code> goes back to pass 60) or <code>python tools/ai_music.py --pick mu_run_1=3</code> (a track), then '
           '<code>python tools/make_sfx_review.py</code>.</div></header>']
    groups = [g for g in A.GROUP_ORDER if g != "Music"]
    nav = ['<a href="#g-first">Listen first</a>', '<a href="#g-p65">Pass 65</a>', '<a href="#g-music">Music</a>', '<a href="#g-hype">UI &amp; rewards</a>']
    nav += ['<a href="#g-%s">%s</a>' % (g, g) for g in groups]
    out.append("<nav>%s</nav>" % "".join(nav))
    first = [x for x in LISTEN_FIRST if x in A.PROMPTS or x in (M.TRACKS if M else {})]
    out.append('<section id="g-first"><h2>Listen first</h2><div class="how">%s</div></section>' % " · ".join(
        '<a style="color:#d9a441" href="#%s">%s</a>' % (x, x) for x in first))
    out.append(synth65_html(paths))
    out.append(music_html(M, msc, mpk, paths))
    out.append('<section id="g-hype"><h2>UI &amp; rewards <small style="color:#9b93ad;font-size:13px">%d · the hype family</small></h2>' % len(hype))
    for sid in hype:
        out.append(row_html(sid, A.PROMPTS[sid], scores, picks, volumes.get(sid, 0), paths))
    out.append("</section>")
    out.append('<section><h2>The 3D world <small style="color:#9b93ad;font-size:13px">unchanged since pass 60 (Garry: no hype there)</small></h2>')
    for g in groups:
        ids = [sid for sid, r in A.PROMPTS.items() if r["group"] == g and sid not in A.HYPE]
        if not ids:
            continue
        out.append('<details id="g-%s"><summary style="cursor:pointer;color:#d9a441;font-size:17px;margin:10px 0">%s (%d)</summary>' % (g, g, len(ids)))
        for sid in ids:
            out.append(row_html(sid, A.PROMPTS[sid], scores, picks, volumes.get(sid, 0), paths))
        out.append("</details>")
    out.append("</section>")
    out.append('<footer>Made by tools/make_sfx_review.py from tools/dl/sfx60/&lt;engine&gt;/scores.json, picks.json and tools/dl/music64/. '
               'Prompts live in tools/ai_sfx.py (HYPE, PROMPTS) and tools/ai_music.py (TRACKS).</footer><script>%s</script></body></html>' % JS)
    return "\n".join(out)


def to_mp3(src, dst, kbps=112):
    """A wav as mp3 for the zip (the music would be hundreds of MB as wav)."""
    import subprocess
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return dst
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-codec:a", "libmp3lame", "-b:a",
                    "%dk" % kbps, dst], check=True)
    return dst


def zip_files(scores, picks):
    """(zip path, disk path) for every file the zip page references."""
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
            if e == "stable" and engine == "sa3":
                continue
            out.append(("cands/%s/%s_c%d.wav" % (e, sid, c["k"]), A.proc_path(e, sid, c["k"])))
        if engine == "sa3":
            out.append(("before/%s.wav" % sid, os.path.join(BEFORE, sid + ".wav")))
    for sid, _ in SYNTH65:
        out.append(("before65/%s.wav" % sid, os.path.join(BEFORE65, sid + ".wav")))
    for fn in sorted(os.listdir(PLACEHOLDER)):
        if fn.endswith(".wav") and not fn.startswith(A.MUSIC_PREFIX):
            out.append(("old/" + fn, os.path.join(PLACEHOLDER, fn)))
    if os.path.isdir(OLD_VOICE):
        for fn in sorted(os.listdir(OLD_VOICE)):
            if fn.endswith(".wav"):
                out.append(("old_voice/" + fn, os.path.join(OLD_VOICE, fn)))
    M, msc, mpk = music_data()
    mp3 = os.path.join(M.DL, "mp3")
    for sid, s in msc.items():
        p = mpk.get(sid)
        for c in s.get("cands", []):
            k = c["k"]
            src = M.loop_path(sid, k)
            if not os.path.exists(src):
                continue
            if p and p["k"] == k:
                out.append(("music/%s.mp3" % sid, to_mp3(os.path.join(M.OUT, sid + ".wav"), os.path.join(mp3, "pick", sid + ".mp3"))))
                out.append(("music_seam/%s_c%d.mp3" % (sid, k), to_mp3(seam_path(M, sid, k), os.path.join(mp3, "seam", "%s_c%d.mp3" % (sid, k)), 160)))
            else:
                out.append(("music_cands/%s_c%d.mp3" % (sid, k), to_mp3(src, os.path.join(mp3, "cands", "%s_c%d.mp3" % (sid, k)), 96)))
        old = os.path.join(OLD_MUSIC, sid + ".wav")
        if os.path.exists(old):
            out.append(("old_music/%s.mp3" % sid, to_mp3(old, os.path.join(mp3, "old", sid + ".mp3"), 96)))
    return [(z, d) for z, d in out if os.path.exists(d)]


def main(argv):
    scores = A.all_scores()
    picks = A.read_json(A.picks_path(), {})
    volumes = {sid: r.get("volume_db", 0) for sid, r in A.soundmap_rows().items()}
    M, msc, mpk = music_data()
    make_seams(M, msc)
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

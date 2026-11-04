# -*- coding: utf-8 -*-
"""Pass 124: the Stage 2 performance report for Garry -> docs/perf/stage2_slowdown.html, charts drawn from his run record
(analytics/remote/Hungry_Outlaw_94/2026-11-04T14-57-42_01a1a6a3.json) and the PC probes (tools/dl/p124/LEAD/probes.txt).

    python tools/make_perf_report.py
"""
import html
import json
import os
import statistics as st

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
RUN = os.path.join(ROOT, "analytics", "remote", "Hungry_Outlaw_94", "2026-11-04T14-57-42_01a1a6a3.json")
OUT = os.path.join(ROOT, "docs", "perf", "stage2_slowdown.html")

C_STEP = "#f5b82a"
C_PROC = "#4a8ae0"
C_REST = "#5b6780"
C_CROWD = "#ff6b6b"
C_INK = "#e9eefb"
C_DIM = "#9aa7c4"
C_GRID = "#2a3552"
C_OK = "#5fc43a"


def timeline(samples):
    """The frame stacked by what took it, ten-second-free: three second means; the crowd on its own scale."""
    W, H = 900, 380
    L, R, T, B = 52, 56, 24, 40
    pts = []
    for i in range(0, len(samples), 2):
        w = samples[i:i + 2]
        def m(k):
            v = [x[k] for x in w if isinstance(x.get(k), (int, float))]
            return st.mean(v) if v else 0.0
        fr = max(m("frames"), 1.0)
        step = m("steps") * m("phys_ms") / fr
        proc = m("proc_ms")
        frame = m("frame_ms")
        rest = max(frame - step - proc, 0.0)
        pts.append((m("t"), step, proc, rest, m("alive")))
    tmax = 184.0
    ymax = 45.0
    cmax = 350.0
    X = lambda t: L + (W - L - R) * t / tmax
    Y = lambda v: H - B - (H - T - B) * min(v, ymax) / ymax
    YC = lambda v: H - B - (H - T - B) * min(v, cmax) / cmax
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="Frame time and crowd over the run">' % (W, H)]
    # the slow window
    o.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="#ff6b6b" opacity="0.09"/>' % (X(149), T, X(172) - X(149), H - T - B))
    o.append('<text x="%.1f" y="%d" fill="%s" font-size="13" text-anchor="middle">everything twice as slow</text>' % ((X(149) + X(172)) / 2, T + 14, C_CROWD))
    for v in (0, 10, 20, 30, 40):
        o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s"/>' % (L, W - R, Y(v), Y(v), C_GRID))
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12" text-anchor="end">%d</text>' % (L - 8, Y(v) + 4, C_DIM, v))
    for v in (0, 100, 200, 300):
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12">%d</text>' % (W - R + 8, YC(v) + 4, C_CROWD, v))
    for t in range(0, 181, 30):
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">%d:%02d</text>' % (X(t), H - B + 20, C_DIM, t // 60, t % 60))
    # stacked areas
    base = [0.0] * len(pts)
    for idx, col in ((1, C_STEP), (2, C_PROC), (3, C_REST)):
        top = [b + p[idx] for b, p in zip(base, pts)]
        d = "M" + " L".join("%.1f %.1f" % (X(p[0]), Y(t)) for p, t in zip(pts, top))
        d += " L" + " L".join("%.1f %.1f" % (X(p[0]), Y(b)) for p, b in zip(pts[::-1], base[::-1])) + " Z"
        o.append('<path d="%s" fill="%s" opacity="0.92"/>' % (d, col))
        base = top
    o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2" stroke-dasharray="6 5"/>' % (L, W - R, Y(16.7), Y(16.7), C_OK))
    o.append('<text x="%d" y="%.1f" fill="%s" font-size="12">60 fps budget, 16.7 ms</text>' % (L + 8, Y(16.7) - 7, C_OK))
    d = "M" + " L".join("%.1f %.1f" % (X(p[0]), YC(p[4])) for p in pts)
    o.append('<path d="%s" fill="none" stroke="%s" stroke-width="2.5"/>' % (d, C_CROWD))
    o.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="middle" transform="rotate(-90 %d %d)">milliseconds a frame</text>' % (14, (T + H - B) // 2, C_DIM, 14, (T + H - B) // 2))
    o.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="middle" transform="rotate(90 %d %d)">creatures alive</text>' % (W - 12, (T + H - B) // 2, C_CROWD, W - 12, (T + H - B) // 2))
    o.append("</svg>")
    return "".join(o)


def budget_lines():
    """Phone cost by crowd size, cool and warm: straight lines fitted to its runs (see the numbers under the chart)."""
    W, H = 900, 300
    L, R, T, B = 52, 20, 18, 38
    cool = lambda n: 7.5 + 3.89 + 0.0142 * n     # rest 7.5, phys 1.5 + .0113 n, proc 2.39 + .0029 n (first 5 minutes of a fresh run, 10-24)
    warm = lambda n: 5.8 + 3.82 + 0.034 * n      # rest 5.8, phys 1.27 + .0185 n, proc 2.55 + .0155 n (this run before 2:28)
    nmax = 500.0
    ymax = 30.0
    X = lambda n: L + (W - L - R) * n / nmax
    Y = lambda v: H - B - (H - T - B) * min(v, ymax) / ymax
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="Frame cost by crowd size on the phone">' % (W, H)]
    for v in (0, 10, 20, 30):
        o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s"/>' % (L, W - R, Y(v), Y(v), C_GRID))
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12" text-anchor="end">%d</text>' % (L - 8, Y(v) + 4, C_DIM, v))
    for n in range(0, 501, 100):
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">%d</text>' % (X(n), H - B + 20, C_DIM, n))
    o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2" stroke-dasharray="6 5"/>' % (L, W - R, Y(16.7), Y(16.7), C_OK))
    for f, col, name in ((cool, C_PROC, "phone cool"), (warm, C_STEP, "phone warm")):
        o.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="3"/>' % (X(0), Y(f(0)), X(500), Y(f(500)), col))
    nw = (16.67 - 5.8 - 3.82) / 0.034
    nc = (16.67 - 7.5 - 3.89) / 0.0142
    for n, col, name in ((nc, C_PROC, "about %d creatures, cool" % round(nc, -1)), (nw, C_STEP, "about %d creatures, warm" % round(nw, -1))):
        o.append('<circle cx="%.1f" cy="%.1f" r="6" fill="%s"/>' % (X(n), Y(16.67), col))
        o.append('<text x="%.1f" y="%.1f" fill="%s" font-size="13" text-anchor="middle">%s</text>' % (X(n), Y(16.67) + 24, C_INK, name))
    o.append('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="%s" stroke-width="2"/>' % (X(318), X(318), T, H - B, C_CROWD))
    o.append('<text x="%.1f" y="%d" fill="%s" font-size="13">318: your run at 3:01</text>' % (X(318) + 6, T + 14, C_CROWD))
    o.append("</svg>")
    return "".join(o)


def bars():
    """What a frame's CPU time went on with 288 creatures, PC measure (tools/dl/p124/LEAD/probes.txt, fire300)."""
    rows = [("Moving and colliding the crowd", 2.99, C_STEP, "enemies.sim"), ("Writing the crowd to the GPU", 1.87, C_STEP, "enemies.render"),
            ("Everything the timers don't name (engine, sending draw calls)", 2.09, C_REST, "the frame less the timed systems"),
            ("The hero", 0.43, C_PROC, "player"), ("Shots, flying and drawn", 0.29, C_PROC, "projectiles"), ("HUD", 0.14, C_PROC, "hud"),
            ("Weapons", 0.09, C_PROC, "weapons"), ("Particles", 0.07, C_PROC, "fx"), ("Gems and coins, 281 lying", 0.09, C_PROC, "pickups"), ("Structures", 0.06, C_PROC, "structures")]
    W = 900
    H = 34 * len(rows) + 10
    L = 410
    X = lambda v: L + (W - L - 70) * v / 3.2
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="Where a frame goes">' % (W, H)]
    for i, (name, v, col, key) in enumerate(rows):
        y = 8 + i * 34
        o.append('<text x="%d" y="%d" fill="%s" font-size="14" text-anchor="end">%s</text>' % (L - 12, y + 17, C_INK, html.escape(name)))
        o.append('<rect x="%d" y="%d" width="%.1f" height="22" fill="%s"/>' % (L, y + 2, X(v) - L, col))
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="13">%.2f ms</text>' % (X(v) + 8, y + 18, C_DIM, v))
    o.append("</svg>")
    return "".join(o)


SOLUTIONS = [
    dict(k="A", name="Set a crowd budget for the phone", gain="Biggest and immediate", ms="Worst frames 38 ms to about 18-20 ms", lose="Fewer bodies at the worst moment: at most about 250 instead of 320 and rising. At 319 creatures their pictures cover 77% of a screen, so 250 still looks like a swarm. Rows may run a little thin, which the Level Editor shows as starving.",
         work="Tiny: map data. The cap from 500 to about 250, or fewer than r22's 15 spiders every 5 s", risk="Balance: fewer kills means slightly less XP in that stretch", note="This can also be automatic: hold new spawns only while recent frames run over budget, so a cool phone and the PC keep the full crowd. That's a small rule, and it would be named in BALANCING."),
    dict(k="B", name="Take away the cliff", gain="Large, and only on bad frames", ms="Worst frames 38 ms to about 25-28 ms (from 26 fps to about 37)", lose="Nothing you can see in a screenshot. When the phone is overloaded the world would run in slight slow motion, or take slightly bigger steps, rather than drop to half frame rate.",
         work="Small to medium. One setting to try (one world step a frame), then a choice between slow motion and a longer step", risk="Replays record the steps, so they stay correct for new runs but need a re-test", note="With one world step a frame the extra 10 ms never lands. The world then runs at about 60% speed during the overload instead of stuttering at full speed, the same trade EVE Online makes with its time dilation."),
    dict(k="C", name="Rewrite the crowd's loops in compiled code (GDExtension, C++)", gain="Largest long-term: 2x to 3x the crowd", ms="Crowd work down by perhaps 70-85%: warm frames at 233 creatures from 38 ms to about 17 ms, and 500 creatures become possible", lose="Nothing visual at all. Content stays data and the Level Editor doesn't change.",
         work="Large: a pass or two. A compiled library for Android and for Windows in the build, and a careful move of the crowd's hot loops", risk="Moderate: every new build must keep replays exact, and a crash can no longer be read as easily from the phone. I would first do a one-pass trial on the separation loop only and measure it on your phone", note="I found no trustworthy public benchmark for this exact case: the 5x to 20x figures around are marketing. The trial is what gives you a real number."),
    dict(k="D", name="Move the crowd less often", gain="Medium", ms="Moving and colliding the crowd down by about 35-45%: warm frames down by 6-8 ms", lose="The crowd's spacing gets a bit looser: creatures push apart 30 times a second rather than 60, so tight clumps can overlap slightly more. Their walking stays smooth, as position still moves every step.",
         work="Medium: the far-away logic from pass 101 extended to creatures on screen", risk="Low. Rules change slightly, so old replays need their own build, which they already have", note="Today creatures on screen steer every 2nd tick and those off screen every 4th, but every creature still moves and separates every tick."),
    dict(k="E", name="Draw far-away creatures half as often", gain="Medium", ms="Writing the crowd to the GPU down by about 30-40%: frames down by 2-3 ms", lose="Creatures at the screen's edge update 30 times a second. On a slow walker that's hard to see; on a fast creature at the edge you may see a very slight step if you look for it.",
         work="Small to medium", risk="Low", note="The game writes every drawn creature's position and frame to the GPU every frame, one call at a time."),
    dict(k="F", name="Fewer draw calls for scenery", gain="Small to medium", ms="1-2 ms off the part that sends draw calls", lose="Nothing.", work="Medium", risk="Low", note="The PC probe counts about 170 draw calls and 700-790 objects. Scenery, walls and shadows could merge further. It also lowers power use, which helps with heat."),
    dict(k="G", name="Keep the phone cooler", gain="Delays the 2x slowdown rather than stops it", ms="Hard to promise: 1-2 ms directly, plus slower heating", lose="Lower world resolution: 3D scale 0.8 to 0.7 is 23% fewer pixels, so sand and creatures look a bit softer. The UI stays sharp. The Nightfall filter could also become part of each material instead of extra full-screen quads, with no visual loss but real work.",
         work="Scale: tiny. Filter: medium", risk="Low", note="Android has a thermal API that tells a game how close it is to throttling (ADPF). NCSoft's Lineage W went from falling to 32 fps on a Pixel 6 to a steady 60 by lowering quality before heat hit. Godot has no support for it, so it needs a small Android plugin. It could drive option A's automatic budget."),
    dict(k="H", name="Change the sprite sheets' file type or compression", gain="Doesn't fix this slowdown", ms="About 0-1 ms. Helps memory and loading instead", lose="If you use GPU compression (ETC2): small blocky artefacts along outlines and soft edges, most visible on hero close-ups and pale creatures. You'd want to check it by eye on 3 or 4 strips first.",
         work="Small to test, medium to roll out", risk="Low. It's per file and easy to undo", note="See the section below."),
]

SOURCES = [
    ("Godot docs: Optimization using MultiMeshes", "https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html", "We already draw this way. It says GDScript is fine for a few thousand instances, and other languages for far more."),
    ("Godot docs: importing images", "https://docs.godotengine.org/en/latest/classes/class_resourceimportertexture.html", "Lossy quality affects disk size only; VRAM compression lowers memory and sampling bandwidth; on the Compatibility renderer it means ETC2, since the high-quality ASTC option is ignored there."),
    ("Godot docs: General optimization", "https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html", "Measure first; the frame is set by the slower of CPU and GPU, so a GPU fix can't help a CPU-bound frame."),
    ("Horde add-on devlog (Spare Parts Studio)", "https://spare-parts-studio.itch.io/horde/devlog/1733372/horde-is-out-thousands-of-2d-enemies-for-godot-4", "Thousands of Godot enemies in plain GDScript, using flat arrays and one draw call per type. 3,300 enemies at 150 fps against 7 as nodes in a browser demo: the seller's own number, desktop. We already do both techniques."),
    ("Ezcha: Rendering a million objects in Godot", "https://ezcha.net/news/5-16-26-rendering-a-million-objects-in-godot", "A million static objects at 160 fps through server calls. It shows drawing isn't the limit when nothing moves: the cost is updating moving things from script, which is our case."),
    ("Godot forum: native code instead of GDScript", "https://forum.godotengine.org/t/performance-implications-of-using-native-code-instead-of-gdscript/120365", "The common advice: write it in GDScript first and move only proven hot spots to native code. No hard numbers."),
    ("r/godot: C# vs GDScript with large for loops", "https://axebps-redlib.hf.space/r/godot/comments/1g50mlq/c_vs_gdscript_performance_with_large_for_loops", "Community view that a hybrid works best. Anecdotal."),
    ("Viblo: Godot 4 on Android, 5 tips", "https://viblo.asia/p/toi-uu-hieu-nang-game-godot-4-tren-android-5-meo-thuc-te-G24B8GlGLz3", "ETC2/ASTC, profiling on the device, MultiMesh for hundreds of sprites. An anecdote; its numbers aren't verified."),
    ("Beebom: Tensor G3 benchmarks and thermals", "https://beebom.com/google-tensor-g3-benchmarks/", "A 15-minute CPU stress test lost about 60% of peak."),
    ("Notebookcheck: Pixel 8 stress tests", "https://www.notebookcheck.net/First-Pixel-8-and-Pixel-8-Pro-3D-Mark-stress-test-results-surface-paint-a-potentially-ugly-picture-for-Tensor-G3.757268.0.html", "A 58% CPU drop under sustained load. 2023 launch-era tests; updates may have changed this."),
    ("Android: ADPF story, NCSoft Lineage W", "https://developer.android.com/stories/games/lineagew-adpf", "60 fps fell to 32 on a Pixel 6 in 30 minutes; with thermal-aware quality it held 60."),
    ("Imagination: Do Not Use Discard", "https://docs.imgtec.com/starter-guides/powervr-architecture/html/topics/rules/do-not-use-discard.html", "Alpha test is costly on tile-based GPUs. This is PowerVR's guidance, not Mali's; I didn't find Arm numbers."),
]


def page(d):
    s = d["samples"]
    sol_rows = "".join(
        '<tr><td class="k">%s</td><td><b>%s</b><br><span class="dim">%s</span></td><td>%s</td><td>%s</td><td>%s</td></tr>' % (
            x["k"], html.escape(x["name"]), html.escape(x["gain"]), html.escape(x["ms"]), html.escape(x["lose"]), html.escape(x["work"]).replace("`", ""))
        for x in SOLUTIONS)
    sol_cards = "".join(
        '<div class="opt"><h3><span class="k">%s</span> %s</h3><p class="note">%s</p><p class="dim"><b>Risk:</b> %s</p></div>' % (
            x["k"], html.escape(x["name"]), html.escape(x["note"]).replace("`", ""), html.escape(x["risk"]))
        for x in SOLUTIONS)
    src = "".join('<li><a href="%s">%s</a>: %s</li>' % (html.escape(u), html.escape(n), html.escape(w)) for n, u, w in SOURCES)
    return TEMPLATE.replace("@@TIMELINE@@", timeline(s)).replace("@@BARS@@", bars()).replace("@@LINES@@", budget_lines()).replace("@@SOLROWS@@", sol_rows).replace("@@SOLCARDS@@", sol_cards).replace("@@SOURCES@@", src)


TEMPLATE = """<title>Stage 2 Slowdown</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;700&family=Ultra&display=swap">
<style>
/* Layout: one reading column in the game's own navy and gold; charts run the column's full width */
:root { --bg:#10172c; --panel:#1a2440; --ink:#e9eefb; --dim:#9aa7c4; --gold:#ffd35c; --line:#2f3b5c; --red:#ff6b6b; --green:#5fc43a; --blue:#6ea5ef;
  --display:'Ultra', Georgia, serif; --body:'Rubik', system-ui, sans-serif; color-scheme: dark; }
body { background:var(--bg); color:var(--ink); font:400 17px/1.55 var(--body); padding-block:32px 64px; padding-left:max(16px, env(safe-area-inset-left, 0px)); padding-right:max(16px, env(safe-area-inset-right, 0px)); }
main { max-width:980px; margin:0 auto; display:flex; flex-direction:column; gap:40px; }
h1 { font:400 clamp(34px,6vw,54px)/1.1 var(--display); margin:0 0 10px; color:#fff6dc; text-wrap:balance; }
h2 { font:400 clamp(23px,3.4vw,30px)/1.2 var(--display); margin:0 0 12px; color:#fff6dc; text-wrap:balance; }
h3 { font:700 18px/1.3 var(--body); margin:0 0 6px; }
p { margin:0 0 12px; max-width:72ch; }
.lead { font-size:20px; }
.eyebrow { font:700 13px/1 var(--body); letter-spacing:.14em; text-transform:uppercase; color:var(--gold); margin-bottom:10px; }
.dim { color:var(--dim); }
.causes { display:grid; gap:14px; }
.cause { background:var(--panel); padding:16px 18px; border-left:4px solid var(--gold); }
.cause.second { border-color:var(--red); }
.cause.third { border-color:var(--blue); }
.cause h3 { font-size:19px; }
.cause p { margin:0; }
figure { margin:0; background:var(--panel); padding:16px; }
figure svg { width:100%; height:auto; display:block; font-family:var(--body); }
figcaption { color:var(--dim); font-size:14.5px; margin-top:10px; }
.legend { display:flex; flex-wrap:wrap; gap:6px 18px; margin:0 0 10px; font-size:14px; color:var(--dim); }
.legend i { display:inline-block; width:12px; height:12px; margin-right:6px; vertical-align:-1px; }
.tablewrap { overflow-x:auto; }
table { border-collapse:collapse; width:100%; min-width:760px; font-size:15px; }
th { text-align:left; font-weight:700; color:var(--gold); padding:8px 10px; border-bottom:2px solid var(--line); vertical-align:bottom; }
td { padding:10px; border-bottom:1px solid var(--line); vertical-align:top; }
td.k, .k { font:400 20px/1 var(--display); color:var(--gold); }
.opts { display:grid; gap:14px; grid-template-columns:repeat(auto-fit,minmax(300px,1fr)); }
.opt { background:var(--panel); padding:14px 16px; min-width:0; }
.opt p { font-size:15.5px; margin-bottom:8px; }
.notcause { display:grid; gap:10px; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); }
.notcause div { border-top:2px solid var(--line); padding-top:8px; min-width:0; font-size:15.5px; }
.notcause b { display:block; }
.pick { background:#2b2410; padding:18px 20px; border-left:4px solid var(--gold); }
ul { margin:0; padding-left:20px; display:grid; gap:7px; max-width:80ch; }
a { color:var(--blue); }
code { font-size:.92em; color:var(--gold); }
</style>
<main>
<header>
<div class="eyebrow">Performance report, for your decision</div>
<h1>Why Stage 2 got slow on your Pixel 8 Pro</h1>
<p class="lead">In your run of 4 November (Drifter, Stage 2, 3:04 long) the game held 60 fps for 2:28, then fell to about 26 fps within 8 seconds. Three things stack up: too many creatures for the phone to run at 60 fps, a catch-up rule that turns a slightly late frame into a very late one, and the phone itself slowing down. I've changed nothing yet. Your options are in the middle of this page.</p>
</header>

<section>
<h2>The three causes, biggest first</h2>
<div class="causes">
<div class="cause"><h3>1. The crowd: 15 more spiders every 5 seconds, with nothing to stop it</h3><p>Stage 2's cap is 500 from the first second, and your row r22 sends 15 Desert Spiders every 5 s from 0:50. That's 3 a second against your level 9 hero's 1 kill a second, so the crowd hit 318 at 3:01, 241 of them spiders. Almost all the game's script time scales with this number: moving and colliding creatures and writing them to the GPU. A warm phone has room for about 210 at 60 fps.</p></div>
<div class="cause second"><h3>2. The cliff: one late frame costs twice the work</h3><p>The world runs in fixed 1/60 s steps. When a frame takes longer than 16.7 ms, the next frame runs two steps to catch up, which adds 10 ms, which makes it later still. So the phone doesn't get slightly slower, it falls off a step: from 17 ms to 38 ms with only 27% more creatures. It's why it felt sudden. Pass 102 capped this at two steps so that it can't spiral further, but the drop to half speed remains.</p></div>
<div class="cause third"><h3>3. The phone slows down when it's warm</h3><p>From 2:29 to 2:52, moving the crowd, drawing it and everything else all took about twice as long together, then all recovered together, with more creatures on screen than before. No game system behaves like that; a CPU changing speed does. Earlier runs show the same: the same crowd cost 2.4 ms a step at the start of a fresh run and 4.4 ms a few minutes in. Reviews measured the Pixel 8's chip losing 58-60% of its CPU speed under long load. This is my best reading, not a measurement: the record doesn't log the phone's temperature or clock speed. I'd like to add that.</p></div>
</div>
</section>

<section>
<h2>The run, second by second</h2>
<figure>
<div class="legend"><span><i style="background:#f5b82a"></i>World steps (moving the crowd, shots, hero)</span><span><i style="background:#4a8ae0"></i>Per-frame scripts (mostly writing the crowd to the GPU)</span><span><i style="background:#5b6780"></i>The rest (sending draw calls, waiting for the screen)</span><span><i style="background:#ff6b6b"></i>Creatures alive</span></div>
@@TIMELINE@@
<figcaption>Your phone's own numbers, averaged over 2 seconds. Up to 2:28 the "rest" is mostly idle waiting: there's spare time. In the red window the frame more than doubles while the crowd grows slowly. After 2:52 the crowd is bigger but the frame is much cheaper. That's cause 3 ending.</figcaption>
</figure>
</section>

<section>
<h2>How many creatures fit</h2>
<figure>
@@LINES@@
<figcaption>Frame time on your phone by crowd size: straight lines fitted to two stretches of play. Warm: this run before 2:28. Cool: the first five minutes of your long run of 24 October (version 0.88). Above the dashed line you lose 60 fps, and then the cliff adds about 10 ms more. The fits are approximate and don't include heavy builds with many shots.</figcaption>
</figure>
</section>

<section>
<h2>Where the time goes</h2>
<figure>
@@BARS@@
<figcaption>Milliseconds a frame with 288 creatures, measured on the PC with your run's creature mix and a stronger build so that gems pile up. Your phone runs the same work about 2 to 2.5 times slower when warm. Yellow is the crowd: 60% of the frame's total and 80% of the part we can name.</figcaption>
</figure>
<h3 style="margin-top:18px">What I ruled out</h3>
<div class="notcause">
<div><b>The spider's art</b>300 spiders against 300 skeletons on the PC: 7.67 ms against 7.43 ms. The count matters, not the creature.</div>
<div><b>Too many pixels of creatures</b>At 319 creatures, their pictures cover 0.77 of a screen. That's not much overdraw for a mobile GPU.</div>
<div><b>Damage numbers</b>About 0.35 ms at 288 creatures on the PC, when turned off. They have already been thinned since pass 102.</div>
<div><b>Gems lying around</b>281 gems cost 0.09 ms. Your run had 217 by the end.</div>
<div><b>Your build</b>Two weapons at level 2 and 1. Few shots were flying (0-5).</div>
<div><b>The new UI</b>The HUD costs 0.14 ms. I can't fully rule out the phone's GPU from here, but its load shows up in the "rest", which stayed at 5-6 ms outside the slow window.</div>
</div>
</section>

<section>
<h2>Your options, ranked</h2>
<p>Ranked by how much they help for how little you lose. Times are for the worst stretch of your run, 233 creatures on a warm phone, 38 ms a frame. They're my estimates from the numbers above, not measurements, except where the section says so.</p>
<div class="tablewrap"><table>
<thead><tr><th></th><th>Option</th><th>Effect</th><th>What you lose visually</th><th>Work</th></tr></thead>
<tbody>@@SOLROWS@@</tbody>
</table></div>
<div class="opts" style="margin-top:16px">@@SOLCARDS@@</div>
</section>

<section>
<h2>Would changing the sprite sheets help?</h2>
<p>Short answer: for this slowdown, barely. It would help memory and loading times. Here's why, and what each change does.</p>
<div class="tablewrap"><table>
<thead><tr><th>Change</th><th>What it does</th><th>Helps speed in a fight?</th><th>Visual cost</th></tr></thead>
<tbody>
<tr><td><b>PNG to WebP, or a better lossy setting</b></td><td>Our strips are already imported as lossy WebP. This only changes the size of the install: on the GPU each one is decoded back to full colour, 4 bytes a pixel. Godot's docs say so directly.</td><td>No</td><td>Slight at very low quality</td></tr>
<tr><td><b>GPU compression (ETC2)</b></td><td>Pictures stay compressed on the GPU at a quarter of the memory: Stage 2's played strips, about 123 MB, become about 31 MB. Less memory traffic means a little less heat, and pictures load faster at the start of a run with no decoding. Our renderer can't use the better ASTC format: the docs say that option is ignored in Compatibility.</td><td>Very little: the GPU isn't what's limiting these frames</td><td>Small blocks along outlines and soft edges. Godot's docs warn against it for 2D UI, but our sprites are drawn in the 3D scene. I'd test 3 or 4 strips by eye</td></tr>
<tr><td><b>Smaller frames</b> (say 256 px cells to 128-160 px for small creatures and looks)</td><td>Less memory, and at the phone's real size a creature shows at roughly 100-160 pixels, so large cells are partly wasted.</td><td>Very little</td><td>Softer sprites in close-ups: the arena's zoom and store captures would show it, normal play hardly</td></tr>
<tr><td><b>Trim the empty space round each frame</b> (tight quads)</td><td>Fewer see-through pixels for the GPU to test. On tile-based mobile GPUs, alpha-tested overdraw is costly.</td><td>Little: creature quads only cover 77% of a screen, so there's little to save</td><td>None</td></tr>
<tr><td><b>Fewer frames in a cycle</b> (12 to 8)</td><td>Saves memory, not time: a frame's cost is the same either way.</td><td>No</td><td>Choppier walks</td></tr>
</tbody>
</table></div>
<p style="margin-top:14px">The reason is simple: these frames are limited by script work on the CPU. A picture's format doesn't change how long the script takes to move a creature. Worth doing at some point for memory, install size and start-up, but not as the cure. I'd do it after the crowd work.</p>
</section>

<section>
<h2>What others do</h2>
<p>I found little written specifically about Godot survivor games on phones, so treat these as nearby experience. Reliable sources are the Godot and Android docs; the rest are reports from individuals.</p>
<ul>@@SOURCES@@</ul>
</section>

<section class="pick">
<h2>My recommendation</h2>
<p><b>A and B now.</b> Both are small and neither costs anything you can see in normal play. Together they should take the worst stretch from 26 fps to a steady 50-60 on your phone. I'd also add the phone's temperature to the run record, so the next report can show cause 3 as a fact.</p>
<p><b>Then a trial of C</b> on your phone. If it gives the speed I expect, it's the option that lets you keep 500 creatures and removes the need for D, E and most of G. If you'd rather not take on compiled code, D and E give most of the same gain in smaller steps.</p>
<p style="margin:0"><b>Tell me which letters you want</b> and I'll build them. For option A, also tell me whether to lower the Stage 2 cap by hand, or make the budget automatic, or both.</p>
</section>
</main>
"""


def main():
    d = json.load(open(RUN, encoding="utf-8"))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page(d))
    print("wrote", OUT, os.path.getsize(OUT))


if __name__ == "__main__":
    main()

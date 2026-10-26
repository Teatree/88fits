"""Builds the 88fits kick-off one pager (a 16:9 slide deck) from docs/onepager/src/onepager.html.

  python tools/make_onepager.py [--pdf] [--force]

Pictures: IMAGES below names each picture the deck uses and where it comes from (the game's art, the bible's captures,
the one pager lanes' captures and paintings in tools/dl/onepager/, git-ignored). Each is cropped, scaled and saved once
as docs/onepager/img/<key>.jpg (.png where it keeps transparency; kept in git, so the deck rebuilds without
tools/dl); --force remakes them all. JPEG because Chrome's PDF keeps a JPEG as it is but re-encodes WebP losslessly.
The template's {{IMG:key}} becomes a data URI (one self-contained HTML file, like the design bible), {{CHART:run}}
and {{CHART:velocity}} inline SVG charts drawn from real data (a phone run's record in analytics/remote/, the pass
dates in tools/dl/onepager/data/velocity.json, frozen into docs/onepager/data/ on first build).
--pdf prints the deck to docs/onepager/88fits_OnePager.pdf with headless Edge (one 1600x900 page a slide)."""
import base64
import glob
import json
import math
import os
import re
import subprocess
import sys
from datetime import date

from PIL import Image

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT_DIR = "docs/onepager"
SRC = OUT_DIR + "/src/onepager.html"
IMG = OUT_DIR + "/img"
DATA = OUT_DIR + "/data"
OUT = OUT_DIR + "/88fits_OnePager.html"
PDF = OUT_DIR + "/88fits_OnePager.pdf"
LANE = "tools/dl/onepager"
BIBLE = "docs/design/img"
FORCE = "--force" in sys.argv
EDGE = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"

# key: (source candidates, first existing wins; options)
#   crop: (x0, y0, x1, y1) as fractions of the source; w/h: the largest size kept; alpha: keep transparency;
#   trim: cut transparent margins first; q: WebP quality
IMAGES = {}


def pic(key, *srcs, **opt):
    IMAGES[key] = (list(srcs), opt)


# the game's own art
pic("logo_hat", "game/icon.png", w=360, alpha=True)
for hid, cut in (("drifter", "hero_drifter"), ("ironwood", "hero_ironwood"), ("astro", "hero_astro"),
                 ("calavera", "hero_calavera"), ("solenne", "hero_solenne"), ("fadeaway", "hero_fadeaway"),
                 ("buck", "hero_buck_f"), ("may", "hero_may_p")):
    pic("hero_" + hid, "game/art/ui/wanted/%s.png" % cut, h=620, alpha=True, trim=True)
for i in (1, 2, 3):
    pic("stage_s%d" % i, "game/art/ui/stages/red_canyon_s%d.jpg" % i, w=1248)
pic("style_anchor", "game/art/style/style_anchor.png", w=1100)

# the game's screens (the SHOTS lane's 1080x1920 captures first, the bible's 720x1280 ones as the fallback)
UI = {"ui_title": "06b_title_live", "ui_drawer": "65_hero_drawer", "ui_stages": "66_stages", "ui_cards": "02_cards",
      "ui_mutation": "29_mutation", "ui_chest": "13_chest", "ui_clear": "69_stage_clear", "ui_results": "70_results",
      "ui_upgrade": "07_homestead", "ui_collection": "08_collection", "ui_quest": "73_collection_quest",
      "ui_sheet": "65b_hero_sheet", "ui_totem": "62b_spirit_pole", "ui_pause": "03_pause_build",
      "ui_stats": "04_pause_stats", "ui_portal": "68_portal_countdown", "ui_endless": "68b_endless",
      "ui_stranger": "25_stranger", "ui_play": "01_play", "ui_far": "51_far_zoom", "ui_dragon": "63_dragons_breath",
      "ui_sniper": "64_saiga_sniper", "ui_boss_king": "05_boss", "ui_boss_gila": "23_gila", "ui_night": "60_nightfall",
      "ui_blood": "61_blood_moon", "ui_elite": "14_elite", "ui_paths": "31_paths_hud"}
for key, name in UI.items():
    pic(key, "%s/shots/ui/%s.png" % (LANE, name), "%s/%s.webp" % (BIBLE, name), w=720)


def lane_picks():
    """The lanes' manifests: {lane: [entries]} (only what exists on disk)."""
    out = {}
    for lane in ("shots", "concept", "refs", "tools"):
        p = os.path.join(LANE, lane, "manifest.json")
        if os.path.exists(p):
            try:
                out[lane] = json.load(open(p, encoding="utf-8"))
            except ValueError:
                out[lane] = []
    return out


# the lanes' pictures (filled in from their manifests; see LANE_MAP at the bottom)
LANE_MAP = {}
OVERRIDES = os.path.join(OUT_DIR, "src", "pictures.json")   # key -> {"src": path, crop, w, h, ...}: the lead's picks


def load_overrides():
    if os.path.exists(OVERRIDES):
        for key, spec in json.load(open(OVERRIDES, encoding="utf-8")).items():
            if key.startswith("_"):
                continue
            srcs = spec.get("src")
            srcs = srcs if isinstance(srcs, list) else [srcs]
            opt = {k: v for k, v in spec.items() if k != "src"}
            if key in IMAGES:
                srcs = srcs + IMAGES[key][0]
            IMAGES[key] = (srcs, opt)


def _trim(im):
    if im.mode != "RGBA":
        return im
    box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    return im.crop(box) if box else im


EXTS = (".jpg", ".png", ".webp")


def img_path(key):
    """The picture's file in docs/onepager/img (a JPEG, or a PNG where it keeps transparency), or None."""
    for ext in EXTS:
        p = os.path.join(IMG, key + ext)
        if os.path.exists(p):
            return p
    return None


def save_pic(im, key, q=82):
    """JPEG for opaque pictures (the PDF keeps them as they are), WebP for transparent ones (a quarter of a PNG's
    bytes in the page); the other formats of the same key are removed."""
    os.makedirs(IMG, exist_ok=True)
    alpha = im.mode == "RGBA" and im.getchannel("A").getextrema()[0] < 255
    dst = os.path.join(IMG, key + (".webp" if alpha else ".jpg"))
    for ext in EXTS:
        old = os.path.join(IMG, key + ext)
        if old != dst and os.path.exists(old):
            os.remove(old)
    if alpha:
        im.save(dst, "WEBP", quality=88, method=6)
    else:
        im.convert("RGB").save(dst, "JPEG", quality=q, optimize=True, progressive=True)
    return dst


def make_image(key):
    srcs, opt = IMAGES[key]
    src = next((s for s in srcs if s and os.path.exists(s)), None)
    dst = img_path(key)
    if src is None:
        return dst
    if not FORCE and dst and os.path.getmtime(dst) >= os.path.getmtime(src) \
            and os.path.getmtime(dst) >= os.path.getmtime(__file__) \
            and (not os.path.exists(OVERRIDES) or os.path.getmtime(dst) >= os.path.getmtime(OVERRIDES)):
        return dst
    im = Image.open(src)
    alpha = opt.get("alpha", False)
    im = im.convert("RGBA" if alpha else "RGB")
    if opt.get("trim"):
        im = _trim(im)
    c = opt.get("crop")
    if c:
        W, H = im.size
        im = im.crop((round(c[0] * W), round(c[1] * H), round(c[2] * W), round(c[3] * H)))
    w, h = opt.get("w"), opt.get("h")
    s = 1.0
    if w:
        s = min(s, w / im.width)
    if h:
        s = min(s, h / im.height)
    if s < 1.0:
        im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    dst = save_pic(im, key, opt.get("q", 84))
    print("img", key, "<-", src, im.size)
    return dst


def uri(key):
    p = img_path(key)
    if not p:
        raise SystemExit("missing picture: " + key)
    mime = {".jpg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}[os.path.splitext(p)[1]]
    return "data:%s;base64,%s" % (mime, base64.b64encode(open(p, "rb").read()).decode("ascii"))


def size_of(key):
    return Image.open(img_path(key)).size


# ---------------------------------------------------------------------------------------------------------------- charts

def _mmss(s):
    return "%d:%02d" % (int(s) // 60, int(s) % 60)


def run_data():
    """The recorded phone run behind the run chart, frozen into docs/onepager/data/run.json."""
    out = os.path.join(DATA, "run.json")
    if os.path.exists(out) and not FORCE:
        return json.load(open(out, encoding="utf-8"))
    src = "analytics/remote/Hungry_Outlaw_94/2026-10-23T18-50-34_01a16974.json"
    r = json.load(open(src, encoding="utf-8"))
    pts = []
    for s in r["samples"]:
        t = s.get("t", s.get("clock"))
        if round(t) % 5 == 0 or s is r["samples"][-1]:
            pts.append([round(t, 1), s.get("alive", 0), s.get("level", 1), s.get("kills", 0)])
    ev = {}
    for e in r["events"]:
        ev.setdefault(e.get("kind"), []).append(round(e.get("t", 0.0), 1))
    fm = sorted(s.get("frame_ms") for s in r["samples"] if s.get("frame_ms"))
    d = {"source": src, "device": r["device"], "hero": r["hero_name"], "stage": r["stage_name"],
         "run_time": r["run_time"], "kills": r["kills"], "level": r["level"], "endless_wave": r["endless_wave"],
         "max_alive": max(p[1] for p in pts), "frame_ms_median": fm[len(fm) // 2], "points": pts,
         "events": {k: ev.get(k, []) for k in ("elite", "boss_start", "boss_end", "endless", "death", "revive",
                                               "wave", "level", "chest", "structure", "totem", "mutation")}}
    os.makedirs(DATA, exist_ok=True)
    json.dump(d, open(out, "w", encoding="utf-8", newline="\n"), indent=0)
    return d


def chart_run():
    d = run_data()
    pts = d["points"]
    T = d["run_time"]
    W, L, R = 1000, 54, 18
    y0, top_h, gap, low_h = 40, 270, 56, 120
    x = lambda t: L + (W - L - R) * t / T
    ya = lambda a: y0 + top_h - top_h * a / 300.0
    yl0 = y0 + top_h + gap
    yl = lambda lv: yl0 + low_h - low_h * (lv - 1) / 49.0
    H = yl0 + low_h + 34
    ev = d["events"]
    boss_a, boss_b = ev["boss_start"][0], ev["boss_end"][0]
    endless = ev["endless"][0]
    o = ['<svg class="chart" viewBox="0 0 %d %d" role="img" aria-labelledby="run-t run-d">' % (W, H),
         '<title id="run-t">Creatures on screen and hero level, second by second</title>',
         '<desc id="run-d">A %s run on a %s: %d kills, level %d, %d Endless waves, up to %d creatures at once.</desc>'
         % (d["hero"], d["device"], d["kills"], d["level"], d["endless_wave"], d["max_alive"])]
    for a, b, cls in ((0, boss_a, "ph-stage"), (boss_a, boss_b, "ph-boss"), (boss_b, endless, "ph-portal"), (endless, T, "ph-end")):
        o.append('<rect class="%s" x="%.1f" y="%d" width="%.1f" height="%d"/>' % (cls, x(a), y0, x(b) - x(a), top_h))
        o.append('<rect class="%s" x="%.1f" y="%d" width="%.1f" height="%d"/>' % (cls, x(a), yl0, x(b) - x(a), low_h))
    o.append('<text class="ph-lab" x="%.1f" y="%d">Sundown: 7:10 to the boss</text>' % (x(0), y0 - 12))
    o.append('<text class="ph-lab" x="%.1f" y="%d" text-anchor="middle">Boss</text>' % ((x(boss_a) + x(boss_b)) / 2, y0 - 12))
    o.append('<text class="ph-lab" x="%.1f" y="%d" text-anchor="middle">Portal</text>' % ((x(boss_b) + x(endless)) / 2 + 4, y0 - 12))
    o.append('<text class="ph-lab" x="%.1f" y="%d">Endless: a wave every 10 s</text>' % (x(endless) + 30, y0 - 12))
    for a in (0, 100, 200, 300):
        o.append('<line class="grid" x1="%d" x2="%d" y1="%.1f" y2="%.1f"/>' % (L, W - R, ya(a), ya(a)))
        o.append('<text class="tick" x="%d" y="%.1f" text-anchor="end">%d</text>' % (L - 8, ya(a) + 4, a))
    for lv in (1, 25, 50):
        o.append('<line class="grid" x1="%d" x2="%d" y1="%.1f" y2="%.1f"/>' % (L, W - R, yl(lv), yl(lv)))
        o.append('<text class="tick" x="%d" y="%.1f" text-anchor="end">%d</text>' % (L - 8, yl(lv) + 4, lv))
    for m in range(0, int(T // 60) + 1, 2):
        o.append('<text class="tick" x="%.1f" y="%.1f" text-anchor="middle">%d:00</text>' % (x(m * 60), yl0 + low_h + 22, m))
    area = "M%.1f,%.1f " % (x(pts[0][0]), ya(0)) + " ".join("L%.1f,%.1f" % (x(p[0]), ya(p[1])) for p in pts) \
        + " L%.1f,%.1f Z" % (x(pts[-1][0]), ya(0))
    line = "M" + " L".join("%.1f,%.1f" % (x(p[0]), ya(p[1])) for p in pts)
    o.append('<path class="a-crowd" d="%s"/>' % area)
    o.append('<path class="l-crowd" d="%s"/>' % line)
    lvl = "M" + " L".join("%.1f,%.1f" % (x(p[0]), yl(p[2])) for p in pts)
    o.append('<path class="l-level" d="%s"/>' % lvl)
    o.append('<text class="axis-lab halo" x="%d" y="%d">Creatures on screen</text>' % (L + 8, y0 + 20))
    o.append('<text class="axis-lab halo" x="%d" y="%d">Hero level</text>' % (L + 8, yl0 + 20))
    # what filled the screen (the record's alive_by), in two staggered rows between the panels
    for t0, lab, row in ((14, "scorpions", 0), (78, "skeletons", 1), (150, "red goblins", 0), (246, "cactus walkers", 1),
                         (318, "werewolves", 0), (600, "werewolves and mummies", 1)):
        yy = y0 + top_h + 20 + 18 * row
        o.append('<line class="mark" x1="%.1f" x2="%.1f" y1="%d" y2="%d"/>' % (x(t0), x(t0), y0 + top_h, yy - 11))
        o.append('<text class="crowd-lab" x="%.1f" y="%d">%s</text>' % (x(t0) + 3, yy, lab))
    for t, lab in ((ev["elite"][0] if ev["elite"] else None, "Elite"), (boss_a, "the Tumbleweed King"),
                   (ev["revive"][0] if ev["revive"] else None, "Phoenix revive")):
        if t is None:
            continue
        o.append('<line class="mark" x1="%.1f" x2="%.1f" y1="%d" y2="%d"/>' % (x(t), x(t), y0, y0 + top_h))
        o.append('<text class="mark-lab halo" x="%.1f" y="%.1f">%s</text>' % (x(t) + 5, y0 + 44, lab))
    peak = max(pts, key=lambda p: p[1])
    o.append('<circle class="dot-crowd" cx="%.1f" cy="%.1f" r="5"/>' % (x(peak[0]), ya(peak[1])))
    o.append('<text class="end-lab halo" x="%.1f" y="%.1f" text-anchor="end">%d at once</text>' % (x(peak[0]) - 9, ya(peak[1]) + 5, peak[1]))
    last = pts[-1]
    o.append('<circle class="dot-level" cx="%.1f" cy="%.1f" r="5"/>' % (x(last[0]), yl(last[2])))
    o.append('<text class="end-lab halo" x="%.1f" y="%.1f" text-anchor="end">level %d</text>' % (x(last[0]) - 10, yl(last[2]) + 18, last[2]))
    o.append('<g class="hover" data-x0="%d" data-x1="%d" data-t="%s"><line class="cross" x1="0" x2="0" y1="%d" y2="%d"/>'
             '<rect class="hit" x="%d" y="%d" width="%d" height="%d"/></g>'
             % (L, W - R, T, y0, yl0 + low_h, L, y0, W - L - R, yl0 + low_h - y0))
    o.append("</svg>")
    series = [[p[0], p[1], p[2], p[3]] for p in pts]
    return "\n".join(o), json.dumps(series, separators=(",", ":"))


def velocity_data():
    out = os.path.join(DATA, "velocity.json")
    if not os.path.exists(out) or FORCE:
        os.makedirs(DATA, exist_ok=True)
        src = json.load(open(os.path.join(LANE, "data", "velocity.json"), encoding="utf-8"))
        json.dump(src, open(out, "w", encoding="utf-8", newline="\n"), indent=1)
    return json.load(open(out, encoding="utf-8"))


def chart_velocity():
    v = velocity_data()["passes"]
    days = {}
    for p, ds in v.items():
        days[ds] = max(days.get(ds, 0), int(p))
    d0 = date(2026, 9, 12)
    d1 = date(2026, 10, 26)
    n = (d1 - d0).days
    W, L, R, T, B = 1000, 46, 24, 30, 40
    H = 420
    x = lambda k: L + (W - L - R) * k / n
    y = lambda p: T + (H - T - B) * (1 - p / 110.0)
    o = ['<svg class="chart" viewBox="0 0 %d %d" role="img" aria-labelledby="vel-t vel-d">' % (W, H),
         '<title id="vel-t">Passes shipped, day by day</title>',
         '<desc id="vel-d">From the first idea on 12 September 2026 to pass 107 on 26 October 2026.</desc>']
    for p in (0, 25, 50, 75, 100):
        o.append('<line class="grid" x1="%d" x2="%d" y1="%.1f" y2="%.1f"/>' % (L, W - R, y(p), y(p)))
        o.append('<text class="tick" x="%d" y="%.1f" text-anchor="end">%d</text>' % (L - 8, y(p) + 4, p))
    for k, lab in ((0, "12 Sep"), (8, "20 Sep"), (18, "30 Sep"), (28, "10 Oct"), (38, "20 Oct"), (44, "26 Oct")):
        o.append('<text class="tick" x="%.1f" y="%d" text-anchor="middle">%s</text>' % (x(k), H - 12, lab))
    pts = [(0, 0)]
    best = 0
    for k in range(n + 1):
        ds = (d0.fromordinal(d0.toordinal() + k)).isoformat()
        best = max(best, days.get(ds, 0))
        pts.append((k, best))
    path = "M%.1f,%.1f" % (x(0), y(0))
    for k, p in pts[1:]:
        path += " H%.1f V%.1f" % (x(k), y(p))
    area = path + " V%.1f H%.1f Z" % (y(0), x(0))
    o.append('<path class="a-vel" d="%s"/>' % area)
    o.append('<path class="l-vel" d="%s"/>' % path)
    for k, p, lab, anchor, dy in ((1, 6, "the feel test", "start", -12), (18, 42, "the Wanted UI", "end", -12),
                                  (29, 66, "the Level Editor paints art", "end", -12),
                                  (35, 87, "three stages, Endless", "end", -12), (44, 107, "pass 107, v0.91", "end", -14)):
        o.append('<circle class="dot-vel" cx="%.1f" cy="%.1f" r="5"/>' % (x(k), y(p)))
        o.append('<text class="mark-lab" x="%.1f" y="%.1f" text-anchor="%s">%s</text>'
                 % (x(k) + (8 if anchor == "start" else -8), y(p) + dy, anchor, lab))
    o.append('<text class="axis-lab" x="%d" y="%d">Passes shipped</text>' % (L, T - 8))
    o.append("</svg>")
    return "\n".join(o)


# ----------------------------------------------------------------------------------------------------------- composites

ICON_PAIRS = [("revolver", "golden_revolver"), ("tommy_gun", "chicago_typewriter"), ("lob_grenade", "golden_pineapple"),
              ("orbit_saws", "saw_halo"), ("hornet_nest", "hive_queen"), ("basketball", "slam_dunk"),
              ("guitarra", "requiem"), ("zap_beam", "storm_cloud"), ("frisbee", "flying_saucer"),
              ("skull_rain", "grave_hail"), ("gravity_gun", "singularity"), ("rocket_pod", "hellfire_battery")]
ICON_PASSIVES = ["beer", "cake", "pocket_watch", "phoenix_feather", "cold_snap", "vulture"]


def _icon(kind, id_):
    return Image.open("game/content/%s/%s/%s_icon.png" % (kind, id_, id_)).convert("RGBA")


def composite_icons():
    """Weapons above their evolutions (two blocks of six), six passive items below: 6 x 5 icons on transparent."""
    dst = img_path("icons_grid")
    if dst and not FORCE and os.path.getmtime(dst) >= os.path.getmtime(__file__):
        return
    cell, gap, sep = 200, 14, 30
    cols = 6
    W = cols * cell + (cols - 1) * gap
    H = 5 * cell + 4 * gap + 2 * sep
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    y = 0
    for block in (ICON_PAIRS[:6], ICON_PAIRS[6:]):
        for r, kind in ((0, "weapons"), (1, "evolutions")):
            for c, pair in enumerate(block):
                ic = _icon(kind, pair[r]).resize((cell, cell), Image.LANCZOS)
                im.alpha_composite(ic, (c * (cell + gap), y))
            y += cell + gap
        y += sep
    for c, pid in enumerate(ICON_PASSIVES):
        ic = _icon("passives", pid).resize((cell, cell), Image.LANCZOS)
        im.alpha_composite(ic, (c * (cell + gap), y))
    im = im.resize((im.width * 3 // 4, im.height * 3 // 4), Image.LANCZOS)
    save_pic(im, "icons_grid")
    print("img icons_grid (composite)", im.size)


def composite_heroes():
    """Four heroes side by side, overlapping a little, feet on one line (the visual style slide)."""
    dst = img_path("style_heroes")
    if dst and not FORCE and os.path.getmtime(dst) >= os.path.getmtime(__file__):
        return
    cuts = ["hero_drifter", "hero_solenne", "hero_calavera", "hero_fadeaway"]
    ims = [_trim(Image.open("game/art/ui/wanted/%s.png" % c).convert("RGBA")) for c in cuts]
    H = 640
    ims = [i.resize((round(i.width * H / i.height), H), Image.LANCZOS) for i in ims]
    step = [round(i.width * .78) for i in ims]
    W = sum(step[:-1]) + ims[-1].width
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = 0
    for k, i in enumerate(ims):
        out.alpha_composite(i, (x, 0))
        x += step[k]
    save_pic(out, "style_heroes")
    print("img style_heroes (composite)", out.size)


# ------------------------------------------------------------------------------------------------- generated fragments

def _esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def loop_html(nodes):
    """The action loop: six plates on an ellipse with arrows between them (SVG behind, HTML plates on top)."""
    VW, VH = 640.0, 500.0
    cx, cy, rx, ry = 320.0, 250.0, 217.6, 205.0
    hw, hh, margin = 86.0, 40.0, 12.0
    ang = [-90 + 60 * k for k in range(6)]
    pos = [(cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a))) for a in ang]

    def inside(p, k):
        return abs(p[0] - pos[k][0]) <= hw + margin and abs(p[1] - pos[k][1]) <= hh + margin

    def pt(a):
        return (cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a)))

    arcs = []
    for k in range(6):
        a0, a1 = ang[k], ang[k] + 60
        s = a0
        while inside(pt(s), k) and s < a1:
            s += .5
        e = a1
        while inside(pt(e), (k + 1) % 6) and e > s:
            e -= .5
        p0, p1 = pt(s), pt(e)
        arcs.append('<path class="ring" d="M%.1f,%.1f A%.1f,%.1f 0 0 1 %.1f,%.1f" marker-end="url(#ah)"/>'
                    % (p0[0], p0[1], rx, ry, p1[0], p1[1]))
    svg = ('<svg viewBox="0 0 640 500" preserveAspectRatio="none" aria-hidden="true"><defs>'
           '<marker id="ah" viewBox="0 0 10 10" refX="6" refY="5" markerWidth="6" markerHeight="6" orient="auto">'
           '<path d="M0,0 L10,5 L0,10 z" class="arrow"/></marker></defs>' + "".join(arcs) + "</svg>")
    plates = []
    for k, n in enumerate(nodes):
        x, y = pos[k]
        plates.append('<div class="node" style="left:%.1f%%;top:%.1f%%"><p class="n">%d</p><b>%s</b><span>%s</span></div>'
                      % (100 * x / VW, 100 * y / VH, k + 1, _esc(n["t"]), _esc(n["s"])))
    return svg + "\n" + "\n".join(plates)


def venn_svg(v):
    o = ['<svg viewBox="0 0 520 400" role="img" aria-label="Where 88fits sits: between survivor-likes on phones and 3D survivor-likes">']
    o.append('<circle class="c1" cx="195" cy="232" r="150"/><circle class="c2" cx="325" cy="232" r="150"/>')

    def head(side, x, anchor):
        t = v[side]["title"].split("|")
        for k, line in enumerate(t):
            o.append('<text class="vl" x="%d" y="%d" text-anchor="%s">%s</text>' % (x, 22 + 24 * k, anchor, _esc(line)))
        o.append('<text class="vs" x="%d" y="%d" text-anchor="%s">%s</text>' % (x, 28 + 24 * len(t), anchor, _esc(v[side]["sub"])))

    head("left", 0, "start")
    head("right", 520, "end")

    def icons(lst, xs):
        for k, ic in enumerate(lst[:4]):
            key = ic["key"]
            if not img_path(key):
                continue
            x, y = xs[k]
            o.append('<g><title>%s</title><image href="%s" x="%d" y="%d" width="50" height="50" preserveAspectRatio="xMidYMid slice"/>'
                     '<rect x="%d" y="%d" width="50" height="50" rx="9" fill="none" stroke="#241b14" stroke-width="2"/></g>'
                     % (_esc(ic["name"]), uri(key), x, y, x, y))

    icons(v["left"].get("icons", []), [(66, 160), (122, 160), (66, 228), (122, 228)])
    right = v["right"].get("icons", [])
    if len(right) == 1 and img_path(right[0]["key"]):
        ic = right[0]
        o.append('<g><title>%s</title><image href="%s" x="364" y="182" width="92" height="92" preserveAspectRatio="xMidYMid slice"/>'
                 '<rect x="364" y="182" width="92" height="92" rx="12" fill="none" stroke="#241b14" stroke-width="2"/></g>'
                 % (_esc(ic["name"]), uri(ic["key"])))
    else:
        icons(right, [(350, 160), (406, 160), (350, 228), (406, 228)])
    o.append('<image href="%s" x="226" y="150" width="68" height="68"/>' % uri("logo_hat"))
    o.append('<text class="vc" x="260" y="248" text-anchor="middle">88fits</text>')
    o.append('<text class="vs" x="260" y="268" text-anchor="middle" style="font-size:12px">Megabonk&#8217;s run,</text>')
    o.append('<text class="vs" x="260" y="284" text-anchor="middle" style="font-size:12px">portrait, one thumb</text>')
    o.append("</svg>")
    return "".join(o)


def bench_html(b):
    if not b:
        return '<p class="t">The benchmark table is being filled in.</p>'
    cols = b["cols"]
    o = ['<table><colgroup><col style="width:calc(var(--u)*9.6)">' + "".join("<col>" for _ in cols) + "</colgroup><thead><tr><th></th>"]
    for c in cols:
        cls = ' class="us"' if c.get("us") else ""
        img = ('<div class="shot"><div class="fr"><img src="%s" alt="%s"></div></div>' % (uri(c["img"]), _esc(c["name"]))) if c.get("img") else ""
        o.append('<th%s><div class="game">%s<span class="title">%s</span></div></th>' % (cls, img, _esc(c["name"])))
    o.append("</tr></thead><tbody>")
    for row in b["rows"]:
        o.append("<tr><th>%s</th>" % _esc(row[0]))
        for k, cell in enumerate(row[1:]):
            cls = ' class="us"' if cols[k].get("us") else ""
            o.append("<td%s>%s</td>" % (cls, cell))
        o.append("</tr>")
    o.append("</tbody></table>")
    return "".join(o)


def hud_html(h):
    pins = "".join('<span class="pin" style="left:%.1f%%;top:%.1f%%">%d</span>' % (p["x"], p["y"], k + 1) for k, p in enumerate(h))
    lst = "".join("<li><div><b>%s</b><span>%s</span></div></li>" % (_esc(p["t"]), _esc(p["s"])) for p in h)
    return pins, lst


def steps_html(steps):
    o = []
    for k, s in enumerate(steps):
        st = []
        if s.get("ar"):
            st.append("--ar:%s" % s["ar"])
        if s.get("fit"):
            st.append("--fit:%s" % s["fit"])
        o.append('<figure class="shot step-pic" style="%s"><div class="fr"><img src="%s" alt="%s"></div>'
                 '<p class="n">%s</p><p class="t">%s</p></figure>'
                 % (";".join(st), uri(s["img"]), _esc(s.get("alt", s["t"])), _esc(s.get("n", "Step %d" % (k + 1))), _esc(s["t"])))
    return "".join(o)


# --------------------------------------------------------------------------------------------------------------- render

def used_keys(html, content):
    """Every picture the deck shows: {{IMG:key}} in the template, plus the keys content.json names."""
    keys = set(re.findall(r"\{\{IMG:([a-z0-9_]+)\}\}", html)) | {"logo_hat"}
    for lst in ("art1", "art2_puppet", "art2_icons"):
        keys |= {st["img"] for st in content.get(lst) or []}
    for side in ("left", "right"):
        keys |= {ic["key"] for ic in content["venn"][side].get("icons", [])}
    for c in (content.get("bench") or {}).get("cols", []):
        if c.get("img"):
            keys.add(c["img"])
    return keys


def render():
    load_overrides()
    content = json.load(open(os.path.join(OUT_DIR, "src", "content.json"), encoding="utf-8"))
    html = open(SRC, encoding="utf-8").read()
    keys = used_keys(html, content)
    for key in sorted(keys):
        if key in IMAGES:
            make_image(key)
    composite_icons()
    composite_heroes()
    # pictures no slide shows any more leave the folder
    for f in os.listdir(IMG):
        k, ext = os.path.splitext(f)
        if ext in EXTS and k not in keys:
            os.remove(os.path.join(IMG, f))
            print("removed unused", f)
    html = html.replace("{{LOOP}}", loop_html(content["loop"]))
    html = html.replace("{{VENN}}", venn_svg(content["venn"]))
    html = html.replace("{{BENCH}}", bench_html(content.get("bench")))
    pins, lst = hud_html(content.get("hud") or [])
    html = html.replace("{{HUD_PINS}}", pins).replace("{{HUD_LIST}}", lst)
    for name, key in (("ART1_STEPS", "art1"), ("ART2_PUPPET", "art2_puppet"), ("ART2_ICONS", "art2_icons")):
        html = html.replace("{{%s}}" % name, steps_html(content.get(key) or []))
    for name, val in content.get("text", {}).items():
        html = html.replace("{{%s}}" % name, val if name == "SHIP_LOG" else _esc(val))
    html = re.sub(r"\{\{ALT:([a-z0-9_]+)\}\}", lambda m: _esc(content["alt"].get(m.group(1), "")), html)
    html = re.sub(r"\{\{CAP:([a-z0-9_]+)\}\}", lambda m: _esc(content["cap"].get(m.group(1), "")), html)
    run_svg, run_series = chart_run()
    html = html.replace("{{CHART:run}}", run_svg).replace("{{DATA:run}}", run_series)
    html = html.replace("{{CHART:velocity}}", chart_velocity())
    rd = run_data()
    for k in ("kills", "level", "endless_wave", "max_alive"):
        html = html.replace("{{RUN:%s}}" % k, "{:,}".format(rd[k]))
    html = html.replace("{{RUN:frame}}", "%.1f" % rd["frame_ms_median"])
    missing = []

    def img(m):
        key = m.group(1)
        if not img_path(key):
            missing.append(key)
            return ""
        return uri(key)

    html = re.sub(r"\{\{IMG:([a-z0-9_]+)\}\}", img, html)
    # slide numbers: "No. {{NO}}" in each section's kicker, in order (the cover has none); {{NO:id}} names another slide
    ids = re.findall(r'<section class="slide" id="([a-z0-9]+)"', html)
    nos = {sid: "%02d" % k for k, sid in enumerate(ids)}
    parts = re.split(r'(<section class="slide" id="[a-z0-9]+")', html)
    for k in range(1, len(parts), 2):
        sid = re.search(r'id="([a-z0-9]+)"', parts[k]).group(1)
        parts[k + 1] = parts[k + 1].replace("No. {{NO}}", "No. " + nos[sid], 1)
    html = "".join(parts)
    html = re.sub(r"\{\{NO:([a-z0-9]+)\}\}", lambda mm: nos[mm.group(1)], html)
    # page numbers: every slide footer in order, "NN / total" (the cover and the summary carry none)
    total = html.count('<span class="pg"></span>')
    n = [0]

    def pg(m):
        n[0] += 1
        return '<span class="pg">%02d / %02d</span>' % (n[0], total)

    html = re.sub(r'<span class="pg"></span>', pg, html)

    def ar(m):
        key = m.group(1)
        if not img_path(key):
            return "1/1"
        w, h = size_of(key)
        return "%d/%d" % (w, h)

    html = re.sub(r"\{\{AR:([a-z0-9_]+)\}\}", ar, html)
    left = re.findall(r"\{\{[^}]+\}\}", html)
    if left:
        print("unfilled placeholders:", sorted(set(left)))
    if missing:
        print("MISSING pictures:", sorted(set(missing)))
    html = html.encode("ascii", "xmlcharrefreplace").decode("ascii")
    open(OUT, "w", encoding="utf-8", newline="\n").write(html)
    print("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))
    return not missing


def pdf():
    """Headless Edge prints the page. A fresh profile each time (an Edge already running on a profile takes the
    command over and never prints), the file awaited until its size holds still, then the browser stopped by pid."""
    import shutil
    import tempfile
    import time
    url = "file:///" + os.path.abspath(OUT).replace("\\", "/")
    os.makedirs(LANE, exist_ok=True)
    prof = tempfile.mkdtemp(prefix="edge_", dir=os.path.abspath(LANE))
    cmd = [EDGE, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--hide-scrollbars", "--no-first-run",
           "--user-data-dir=" + prof, "--run-all-compositor-stages-before-draw", "--virtual-time-budget=20000",
           "--print-to-pdf=" + os.path.abspath(PDF), url]
    if os.path.exists(PDF):
        os.remove(PDF)
    proc = subprocess.Popen(cmd)
    try:
        last, still = -1, 0
        for _ in range(360):
            size = os.path.getsize(PDF) if os.path.exists(PDF) else -1
            still = still + 1 if size == last and size > 0 else 0
            if still >= 4 or (proc.poll() is not None and size > 0 and still >= 1):
                break
            last = size
            time.sleep(.5)
    finally:
        if proc.poll() is None:
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
        time.sleep(1)
        shutil.rmtree(prof, ignore_errors=True)
    if not os.path.exists(PDF):
        raise SystemExit("Edge wrote no PDF")
    print("wrote", PDF, "%.1f MB" % (os.path.getsize(PDF) / 1e6))


if __name__ == "__main__":
    ok = render()
    if "--pdf" in sys.argv:
        pdf()
    sys.exit(0 if ok else 1)

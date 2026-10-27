"""The UI reference (2026-10-27): every screen of 88fits with its captures, what it is for, when it appears and what each
control does. The successor of the pass 38 redesign pack (docs/ui_review/, kept as it was).

    python tools/make_ui_screens.py [--pdf]

Reads docs/ui_screens/src/screens.json (one record per screen: when, purpose, controls, shows, rules, states; gathered
from the code) and the captures named in SHOTS below (game/tools/wanted_shots.gd, game/tools/uidoc_shots.gd, the one
pager's captures, the design bible's), writes docs/ui_screens/screens/*.jpg and docs/ui_screens/index.html; --pdf prints
docs/ui_screens/88fits_ui_screens.pdf through headless Edge."""
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "ui_screens")
SRC = os.path.join(OUT, "src", "screens.json")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
W = "tools/dl/uidoc/wanted/"
X = "tools/dl/uidoc/extra/"
U = "tools/dl/onepager/shots/ui/"
B = "docs/design/img/"

# screen id -> [(capture, caption)]
SHOTS = {
    "boot_loading": [("game/art/ui/splash.png", "the splash and its LOADING bar")],
    "consent_card": [(W + "19-consent.png", "first launch")],
    "title": [(W + "01-title.png", "an owned hero"), (W + "02-title-astro.png", "a hero on sale: BUY"),
              (W + "01c-title-locked-hero.png", "a locked hero: the requirement")],
    "hero_drawer": [(U + "65_hero_drawer.png", "the drawer over the title")],
    "hero_sheet": [(U + "65b_hero_sheet.png", "the Drifter's sheet")],
    "stages_menu": [(W + "18-stages.png", "stage 2 open, stage 3 locked"), (W + "18c-stages-all-beaten.png", "every stage beaten")],
    "upgrade_board": [(W + "03-mirror.png", "the board"), (W + "03b-mirror-talent-open.png", "a talent's sheet"),
                      (W + "03c-mirror-talent-full.png", "three ranks bought")],
    "collection": [(W + "04-collection.png", "Weapons"), (W + "04h-collection-enemies.png", "Enemies, with danger badges"),
                   (W + "04b-collection-weapon-page.png", "a weapon's page"), (W + "04d-collection-locked-page.png", "a locked item's page")],
    "settings": [(W + "05-settings.png", "Settings"), (W + "05b-settings-wipe-confirm.png", "Wipe the save?")],
    "dev_menu": [(W + "17-developer-menu.png", "the developer menu")],
    "hud": [("tools/dl/onepager/shots/r2/play_drifter_hud.png", "a fight on a phone"), (W + "06c-hud-full-build.png", "a full build, a boss bar"),
            (W + "06d-hud-levels.png", "plates in their levels' colours"), (W + "06e-hud-mutation-next.png", "MUTATION NEXT"),
            (W + "06b-hud-boss-banner.png", "a banner, edge pointers")],
    "damage_numbers": [(W + "06e-hud-phoenix.png", "hits, crits, heals; the Phoenix banner")],
    "level_up": [(W + "07-level-up.png", "three cards"), (W + "07b-level-up-spent.png", "no skips or banishes left")],
    "resume_gate": [(W + "09-gate-tap-to-go.png", "TAP TO GO")],
    "mutation_offer": [(W + "29b-path-reel.png", "the weapon reel"), (W + "08-path-offer.png", "the mutations"),
                       (W + "08b-path-no-skips.png", "no skips left")],
    "chest": [(W + "10c-chest-opening.png", "the chest opening"), (W + "10-chest.png", "landed"),
              (W + "10b-chest-boss.png", "the boss's mutation chest"), (W + "10e-chest-gold.png", "landed on gold")],
    "shop": [(W + "11-shop.png", "short of gold"), (W + "11b-shop-22.png", "a long build")],
    "stranger": [(W + "12-stranger.png", "an item for max HP"), (U + "26_stranger_deal.png", "a weapon offer")],
    "totem": [(U + "ui_totem.png", "three gifts")],
    "drum_moment": [(X + "drum_moment_late.png", "the drum's last hit")],
    "pause": [(W + "13-pause-build.png", "Build, a row opened"), (W + "13b-pause-stats.png", "Stats and a stat's sources"),
              (W + "13c-pause-options.png", "Options"), (W + "13d-pause-abandon-confirm.png", "Abandon the run?")],
    "down_revive": [(W + "14-down.png", "one chance left"), (W + "14b-down-hits.png", "with the debug hit log")],
    "portal": [(W + "15-stage-clear.png", "the countdown to Endless"), (W + "15b-stage-clear-last-seconds.png", "its last seconds")],
    "endless": [(W + "06f-hud-portal.png", "ENDLESS IN"), (W + "06g-hud-endless.png", "Endless, WAVE 3")],
    "results": [(W + "16-results.png", "extracted"), (W + "16c-results-sources.png", "every damage source, an unlock"),
                (W + "16b-results-down.png", "run over")],
    "survey": [(W + "19b-survey.png", "a rating page"), (W + "19c-survey-text-focused.png", "a text page")],
    "confirm": [(W + "13d-pause-abandon-confirm.png", "Abandon the run?")],
    "debug_arena": [(B + "57_arena_enemy.webp", "the ENEMY tab"), (B + "57b_arena_items.webp", "the ITEMS tab")],
}
GROUPS = [
    ("Before the game", ["boot_loading", "consent_card"]),
    ("The hub", ["title", "hero_drawer", "hero_sheet", "stages_menu", "upgrade_board", "collection", "settings"]),
    ("In a run: always on", ["spawn_beam", "hud", "hints", "damage_numbers", "last_stand_fx"]),
    ("In a run: screens that pause", ["level_up", "mutation_offer", "chest", "resume_gate", "shop", "stranger", "totem", "drum_moment", "pause", "down_revive"]),
    ("The end of a stage", ["portal", "endless", "results", "survey"]),
    ("Shared pieces", ["confirm"]),
    ("For testers only", ["player_debug_mode", "dev_menu", "debug_arena", "debug_panel", "debug_hand", "shop_screen_legacy"]),
]
CODE = re.compile(r"\s*\((?:[^()]|\(\w*\))*?(?:\.gd|\b[A-Z][a-z]+[A-Z][A-Za-z]+\b|\b[A-Z][A-Za-z0-9]+\.[A-Za-z_]\w*|\b[a-z]+_[a-z_]+\b)(?:[^()]|\(\w*\))*\)")
# the names the doc shows (the records keep the screens' own titles)
NAMES = {"boot_loading": "Loading", "consent_card": "Play data question", "title": "Title", "hero_drawer": "Hero drawer",
         "hero_sheet": "Hero sheet", "stages_menu": "Stages", "upgrade_board": "Upgrade board", "level_up": "Level-up cards",
         "resume_gate": "Tap to go", "mutation_offer": "Mutation offer", "chest": "Chest", "shop": "The Shop",
         "stranger": "The Stranger", "totem": "Totem (Spirit Pole)", "pause": "Pause", "down_revive": "Down!",
         "portal": "Stage clear (the portal)", "results": "Results", "survey": "Survey card", "confirm": "Question card",
         "dev_menu": "Developer menu", "shop_screen_legacy": "Old meta shop (unused)", "player_debug_mode": "Player debug mode",
         "spawn_beam": "Run start (the spawn beam)", "last_stand_fx": "Last Stand", "endless": "Endless"}


def clean(t):
    return re.sub(r"\s+([.,;:])", r"\1", CODE.sub("", str(t))).strip()


def e(t):
    return html.escape(clean(t))


def shot(src, key):
    os.makedirs(os.path.join(OUT, "screens"), exist_ok=True)
    dst = os.path.join(OUT, "screens", key + ".jpg")
    im = Image.open(os.path.join(REPO, src)).convert("RGB")
    s = 540 / im.width
    im = im.resize((540, round(im.height * s)), Image.LANCZOS)
    im.save(dst, "JPEG", quality=80, optimize=True, progressive=True)
    return "screens/" + key + ".jpg"


CSS = open(os.path.join(OUT, "src", "style.css"), encoding="utf-8").read()


def render():
    data = {s["id"]: s for s in json.load(open(SRC, encoding="utf-8"))}
    for f in os.listdir(os.path.join(OUT, "screens")) if os.path.isdir(os.path.join(OUT, "screens")) else []:
        os.remove(os.path.join(OUT, "screens", f))
    n_screens, n_shots = 0, 0
    nav, body = [], []
    num = 0
    for gname, ids in GROUPS:
        body.append('<h2 class="group">%s</h2>' % html.escape(gname))
        for sid in ids:
            s = dict(data[sid])
            s["name"] = NAMES.get(sid, s["name"])
            num += 1
            n_screens += 1
            shots = SHOTS.get(sid, [])
            imgs = []
            for k, (src, cap) in enumerate(shots):
                rel = shot(src, "%02d_%s_%d" % (num, sid, k + 1))
                n_shots += 1
                imgs.append('<figure><img src="%s" alt="%s" loading="lazy"><figcaption>%s</figcaption></figure>'
                            % (rel, html.escape(s["name"] + ": " + cap), html.escape(cap)))
            thumb = imgs and ('<img src="%s" alt="" loading="lazy">' % ("screens/%02d_%s_1.jpg" % (num, sid))) or '<span class="noimg">no picture</span>'
            nav.append('<a href="#%s">%s<span><b>%02d</b>%s</span></a>' % (sid, thumb, num, e(s["name"])))
            tag = ' <span class="tag">testers only</span>' if s.get("debug_only") else ""
            parts = ['<section class="screen" id="%s"><header><h3><span class="n">%02d</span>%s</h3>%s<code>%s</code></header>'
                     % (sid, num, e(s["name"]), tag, html.escape(s.get("file", "")))]
            parts.append('<p class="purpose">%s</p>' % e(s["purpose"]))
            parts.append('<div class="grid"><div class="shots">%s</div><div class="notes">' %
                         ("".join(imgs) or '<p class="noimg">No capture: this one is a moment in the run, described here.</p>'))
            parts.append('<h4>When it appears</h4><p>%s</p>' % e(s["when"]))
            if s.get("controls"):
                rows = "".join("<tr><th>%s</th><td>%s</td></tr>" % (e(c["name"]), e(c["does"])) for c in s["controls"])
                parts.append('<h4>What you can do</h4><div class="tbl"><table>%s</table></div>' % rows)
            if s.get("shows"):
                parts.append('<h4>What it shows</h4><ul>%s</ul>' % "".join("<li>%s</li>" % e(x) for x in s["shows"]))
            if s.get("rules"):
                parts.append('<h4>Rules</h4><ul>%s</ul>' % "".join("<li>%s</li>" % e(x) for x in s["rules"]))
            if s.get("states"):
                parts.append('<h4>States</h4><p class="states">%s</p>' % " · ".join(e(x) for x in s["states"]))
            parts.append("</div></div></section>")
            body.append("".join(parts))
    tpl = open(os.path.join(OUT, "src", "page.html"), encoding="utf-8").read()
    page = (tpl.replace("{{CSS}}", CSS).replace("{{NAV}}", "".join(nav)).replace("{{BODY}}", "\n".join(body))
            .replace("{{COUNTS}}", "%d screens · %d captures · 1080×1920" % (n_screens, n_shots)))
    open(os.path.join(OUT, "index.html"), "w", encoding="utf-8", newline="\n").write(page)
    print("wrote docs/ui_screens/index.html:", n_screens, "screens,", n_shots, "captures")


def pdf():
    outp = os.path.join(OUT, "88fits_ui_screens.pdf")
    prof = tempfile.mkdtemp(prefix="edge_")
    if os.path.exists(outp):
        os.remove(outp)
    url = "file:///" + os.path.join(OUT, "index.html").replace("\\", "/")
    p = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--no-first-run", "--user-data-dir=" + prof,
                          "--virtual-time-budget=20000", "--print-to-pdf=" + outp, url])
    last, still = -1, 0
    for _ in range(360):
        size = os.path.getsize(outp) if os.path.exists(outp) else -1
        still = still + 1 if size == last and size > 0 else 0
        if still >= 4:
            break
        last = size
        time.sleep(0.5)
    if p.poll() is None:
        subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"], capture_output=True)
    time.sleep(1)
    shutil.rmtree(prof, ignore_errors=True)
    print("wrote", outp, "%.1f MB" % (os.path.getsize(outp) / 1e6))


if __name__ == "__main__":
    render()
    if "--pdf" in sys.argv:
        pdf()

"""The UI reference (2026-10-27): every screen of 88fits with its captures, what it is for, when it appears and what each
control does. The successor of the pass 38 redesign pack (docs/ui_review/, kept as it was). Pass 127: every record and capture brought up to the Royale UI.

    python tools/make_ui_screens.py [--pdf]

Reads docs/ui_screens/src/screens.json (one record per screen: when, purpose, controls, shows, rules, states; gathered
from the code) and the captures named in SHOTS below (game/tools/wanted_shots.gd and the set folders named there), writes docs/ui_screens/screens/*.jpg and docs/ui_screens/index.html; --pdf prints
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
W = "tools/dl/uidoc/wanted/"          # game/tools/wanted_shots.gd
S = "tools/dl/p127/DOCS/set/"          # pass 127 (lane DOCS): each set from its own capture tool (bosschest: _p118_BOSSCHEST_shots.gd,
                                       # bounty: _p112_wanted_shots.gd, loading: load_shots.gd, startgo: _p120_STARTGO_shots.gd, g: store_shots.gd)
B = "tools/dl/p127/DOCS/set/bible/"    # game/tools/screenshot_run.gd

# screen id -> [(capture, caption)]
SHOTS = {
    "boot_loading": [(S + "loading/load_t0417.png", "the wordmark punching in (0.42 s)"), (S + "loading/load_t0433.png", "the hit: the impact frame"),
                     (S + "loading/load_t0550.png", "after the hit: ring, dust, chips"), (S + "loading/load_t1000.png", "settled: the strips scroll while the title loads")],
    "consent_card": [(W + "19-consent.png", "first launch")],
    "run_curtain": [(S + "startgo/painted_1080x1920_b_wipe_12.png", "the cylinder closing on the title"), (S + "startgo/painted_1080x1920_d_load_t0700.png", "the loading screen between"),
                    (S + "startgo/painted_1080x1920_e_open_07.png", "the cylinder opening on the spawn beam")],
    "title": [(W + "01-title.png", "an owned hero"), (W + "01d-title-buyable.png", "a hero on sale: BUY"), (W + "01e-title-buy-short.png", "short of gold"),
              (W + "01c-title-locked-hero.png", "a locked hero: the requirement")],
    "heroes": [(W + "40-heroes.png", "the shown hero selected"), (W + "40b-heroes-onsale.png", "a hero on sale"), (W + "40c-heroes-locked.png", "a locked hero"),
               (W + "40g-heroes-scrolled.png", "the page scrolled, the picker fixed"), (W + "40e-heroes-buy-confirm.png", "the buy question")],
    "hero_details": [(W + "41-hero-details.png", "the Drifter's details"), (W + "41b-hero-details-items.png", "his items"), (W + "41c-hero-details-looks.png", "skins in the details"),
                     (W + "41e-hero-details-locked.png", "a locked hero")],
    "skins": [(W + "40h-heroes-looks-popup.png", "the pop-up"), (W + "40l-heroes-looks-short.png", "short of gold"), (W + "40i-heroes-buy-look-confirm.png", "the buy question")],
    "stages_menu": [(W + "18-stages.png", "two stages open, the rest locked"), (W + "18c-stages-all-beaten.png", "every stage beaten"), (W + "18d-stages-first-visit.png", "the first visit")],
    "upgrade_board": [(W + "03-mirror.png", "the board"), (W + "03b-mirror-talent-open.png", "a talent's sheet"),
                      (W + "03d-mirror-many-held.png", "many ranks held"), (W + "03f-mirror-choose-maxed.png", "a form near full"), (W + "03g-mirror-reset-confirm.png", "Reset Upgrades?")],
    "collection": [(W + "04-collection.png", "Weapons"), (W + "04h-collection-enemies.png", "Enemies, with danger badges"),
                   (W + "04b-collection-weapon-page.png", "a weapon's page"), (W + "04l-collection-passive-page.png", "a passive item's page"), (W + "04d-collection-locked-page.png", "a locked item's page")],
    "settings": [(W + "05-settings.png", "Settings"), (W + "05b-settings-wipe-confirm.png", "Wipe the save?"), (W + "05d-settings-debug.png", "with the Debug panel")],
    "dev_menu": [(W + "17-developer-menu.png", "the developer menu")],
    "spawn_beam": [(S + "startgo/painted_1080x1920_f_run_042.png", "the hero coming down the beam")],
    "bounty_posters": [(S + "bounty/posters_hang.png", "three posters on strings"), (S + "bounty/taken_stamp.png", "a poster taken"), (S + "bounty/taken_flight.png", "flying to the plate")],
    "hud": [(S + "g/01_play.png", "a fight on a phone"), (W + "06c-hud-full-build.png", "a full build, a boss bar"), (W + "06e-hud-mutation-next.png", "MUTATION NEXT"),
            (W + "06b-hud-boss-banner.png", "a banner, edge pointers"), (W + "06i-hud-kills-hot.png", "the kill counter hot"), (S + "bounty/taken_plate.png", "a bounty plate")],
    "damage_numbers": [(W + "06e-hud-phoenix.png", "hits, crits, heals; the Phoenix banner")],
    "level_up": [(W + "07-level-up.png", "three cards"), (W + "07b-level-up-spent.png", "no skips or banishes left")],
    "resume_gate": [(W + "09-gate-tap-to-go.png", "TAP TO GO")],
    "mutation_offer": [(W + "29b-path-reel.png", "the weapon reel"), (W + "08-path-offer.png", "the mutations"),
                       (W + "08b-path-no-skips.png", "no skips left")],
    "chest": [(W + "10c-chest-opening.png", "the chest opening"), (W + "10-chest.png", "landed"),
              (W + "10b-chest-boss.png", "the purple chest's mutation"), (W + "10e-chest-gold.png", "landed on gold")],
    "boss_chest": [(S + "bosschest/popup_tumbleweed_king_b_knock.png", "the King's chest knocking (x2)"), (S + "bosschest/popup_tumbleweed_king_d_burst.png", "the burst"),
                   (S + "bosschest/popup_tumbleweed_king_f_spew_late.png", "the spew"), (S + "bosschest/popup_tumbleweed_king_h_claim.png", "JACKPOT! and CLAIM"),
                   (S + "bosschest/popup_black_sunday_h_claim.png", "Black Sunday's Collection Box"), (S + "bosschest/popup_brander_h_claim.png", "the Brander's, a slow kill (x1)")],
    "shop": [(W + "11-shop.png", "short of gold"), (W + "11b-shop-22.png", "a long build"), (W + "11c-shop-held.png", "a held card's upgrade")],
    "stranger": [(W + "12-stranger.png", "an item for max HP"), (B + "26_stranger_deal.png", "a weapon offer")],
    "totem": [(W + "30-totem.png", "three gifts"), (W + "30c-totem-4th.png", "the fourth of the map's poles")],
    "drum_moment": [(W + "30-drum-slap.png", "a slap"), (W + "30b-drum-words.png", "the last hit and the boost in words")],
    "grind_moment": [(W + "31-grind-sparks.png", "sharpening"), (W + "31b-grind-level.png", "a level"), (W + "31c-grind-evolved.png", "evolved")],
    "pause": [(W + "13-pause-build.png", "Build, a row opened"), (W + "13e-pause-build-passives.png", "Build: cards and passive items"), (W + "13b-pause-stats.png", "Stats and a stat's sources"),
              (W + "13c-pause-options.png", "Options"), (W + "13d-pause-abandon-confirm.png", "Abandon the run?")],
    "down_revive": [(W + "14c-down-plain.png", "one chance left"), (W + "14d-down-no-chance.png", "no chances left"), (W + "14b-down-hits.png", "with the debug hit log")],
    "portal": [(W + "15-stage-clear.png", "the countdown to Endless"), (W + "15b-stage-clear-last-seconds.png", "its last seconds")],
    "endless": [(W + "06f-hud-portal.png", "ENDLESS IN"), (W + "06g-hud-endless.png", "Endless, WAVE 3")],
    "results": [(W + "16-results.png", "extracted"), (W + "16c-results-sources.png", "every damage source, an unlock"),
                (W + "16b-results-down.png", "run over")],
    "survey": [(W + "19b-survey.png", "a rating page"), (W + "19c-survey-text-focused.png", "a text page")],
    "confirm": [(W + "13d-pause-abandon-confirm.png", "Abandon the run?")],
    "debug_arena": [(B + "57_arena_enemy.png", "the ENEMY tab"), (B + "57b_arena_items.png", "the ITEMS tab"), (B + "57c_arena_waves.png", "the WAVES tab")],
}
GROUPS = [
    ("Before the game", ["boot_loading", "consent_card", "run_curtain"]),
    ("The hub", ["title", "heroes", "hero_details", "skins", "stages_menu", "upgrade_board", "collection", "settings"]),
    ("In a run: always on", ["spawn_beam", "bounty_posters", "hud", "hints", "damage_numbers", "last_stand_fx"]),
    ("In a run: screens that pause", ["level_up", "mutation_offer", "chest", "boss_chest", "resume_gate", "shop", "stranger", "totem", "drum_moment", "grind_moment", "pause", "down_revive"]),
    ("The end of a stage", ["portal", "endless", "results", "survey"]),
    ("Shared pieces", ["confirm"]),
    ("For testers only", ["player_debug_mode", "dev_menu", "debug_arena", "debug_panel", "debug_hand", "shop_screen_legacy"]),
]
CODE = re.compile(r"\s*\((?:[^()]|\(\w*\))*?(?:\.gd|\b[A-Z][a-z]+[A-Z][A-Za-z]+\b|\b[A-Z][A-Za-z0-9]+\.[A-Za-z_]\w*|\b[a-z]+_[a-z_]+\b)(?:[^()]|\(\w*\))*\)")
# the names the doc shows (the records keep the screens' own titles)
NAMES = {"boot_loading": "Loading", "consent_card": "Play data question", "title": "Title", "heroes": "Heroes", "run_curtain": "Revolver wipe",
         "hero_details": "Hero details", "skins": "Skins", "bounty_posters": "Bounty posters", "grind_moment": "Grindstone moment", "stages_menu": "Stages", "upgrade_board": "Upgrade board", "level_up": "Level-up cards",
         "resume_gate": "Tap to go", "mutation_offer": "Mutation offer", "chest": "Chest", "boss_chest": "Boss chest", "shop": "The Shop",
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
    if not os.path.exists(os.path.join(REPO, src)):
        # pass 118 (lane BOSSCHEST): a capture another lane is still remaking is left out with a word, not a crash
        print("make_ui_screens: no capture", src, "(left out)")
        return None
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
                if rel is None:
                    continue
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

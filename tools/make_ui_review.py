"""The UI redesign pack for Claude Design (pass 34, reworked in pass 38): a brief, the game's painted art and one document
per screen with its screenshots, so the whole interface can be critiqued against the genre and redesigned from zero.
Today's UI is the thing under review: the brief asks for a new look, not a tidy-up of this one, so nothing here (the PDF's
own styling included) carries the game's current colours or fonts as a style to follow.

    bash tools/ui_review_capture.sh            # pass 116: every capture, 1080x1920, into tools/dl/p116/UIREVIEW/<set>/
    python tools/make_ui_review.py [--caps=<dir>]     # <dir>/<set>/<name>.png as each screen's "shots" names them

Writes docs/ui_review/: 00_brief.md, NN_<screen>.md per screen, ALL_IN_ONE.md (everything in one file), screens/*.jpg,
art_items.jpg and art_more.jpg (the art the new UI has to sit with, from the content folders' icons; hidden content left
out), index.html (the same pack as one page), 88fits_ui_review.pdf (the one file to give Claude Design: a cover, the
brief, the two art pages, then a page per screen with its screenshots beside its notes; printed by headless Edge from
print.html) and 88fits_ui_review.zip (all of it, plus the icons one by one under art/).
"""
import json
import os
import subprocess
import sys
import zipfile

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "ui_review")
CAPS = os.path.join(REPO, "tools", "dl", "p116", "UIREVIEW")
for a in sys.argv[1:]:
    if a.startswith("--caps="):
        CAPS = a.split("=", 1)[1]

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
CONTENT = os.path.join(REPO, "game", "content")
FONT_DIR = "C:/Windows/Fonts"

BRIEF = """# Outlaw Survivors (88fits) UI review: the brief

**For:** Claude Design

**From:** the 88fits team (Garry, who designs and plays it, and Claude Code, who builds it)

**What is attached:** {NSCREENS} screens and states in {NSHOTS} screenshots at the game's real size, 1080×1920, one page per screen, and two pages of the game's painted art. Captured from version 0.99 (pass 116, 2026-10-31).

## What we are asking for

Review the UI of Outlaw Survivors from the ground up. Today's UI is the thing under review: it is here to be judged, and replaced where it falls short, not to set the style.

- **The look is open.** Today's screens use one kit, the "Wanted" design (aged paper, ink outlines, brass, slab type). It went in at pass 39 after the first review. Keep what earns its place; nothing survives only because it exists.
- **Critique first, and be tough.** Look at every screen the way a senior UI and art lead for mobile games would. Say what does not work and why, even if it is a whole screen.
- **Compare with the genre.** Put each screen next to how the best games in the genre handle the same moment (see "Compare it with the genre"), and say what they do better and what we should take.
- **Then design the alternative** where one is needed: mock-ups at 1080×1920 for the screens and pieces you would change.
- **Strip it down.** If an element, a line of text, a button or a screen does not earn its place, cut it, merge it or move it. Fewer, bigger, clearer things beat many small ones. Tell us why.
- **Art counts as much as layout.** Backgrounds, framing, materials, colour, type, icon treatment and motion are all part of the review.

## The game in one minute

- Outlaw Survivors (the project and its files are called 88fits) is a portrait, one-thumb survivor shooter for Android phones (and a PC build), in the mould of Vampire Survivors, Megabonk and Survivor.io. The hero fires by himself; the player only steers, with a floating joystick, through a crowd of a few hundred creatures.
- One map, **Red Canyon**: a sunlit desert of sand, cacti, red rock, a dry river, oases and a sandstone fort wall. It has three **stages**, and each stage is its own run, chosen from the Stages menu: Sundown (about 7 minutes to the Tumbleweed King), Nightfall (10 minutes, a blue night, to the Gila Grande) and Blood Moon (13 minutes, a red hell, to the Brander). After a stage's boss a portal opens for 60 seconds: extract with the run's gold, or stay and fight **Endless** waves until you fall.
- At the start of a run the hero falls down a beam of light, then three **Wanted posters** float in: take one bounty (kill so many, use a weapon, open barrels...) and it pays coins at the end if done.
- Every level-up pauses the run for a pick of three cards (weapons, Cards, passive items, hero perks). At set times the next level-up is a **mutation offer** instead (a weapon's path). Chests spin a slot-machine reel. On the map: a travelling shop, the Stranger (a strong item for a slice of max HP), 10-12 Totem Poles (a small gift each), the War Drum (a 15-second boost), barrels with coins and power-ups.
- Between runs: the **Upgrade board** (eight talents, two forms each, six ranks, paid in gold), the **Collection**, **Settings**, and the heroes on the title: nine heroes, the Drifter free, the others bought with gold once their unlock quest is done; heroes have **skins** (looks) bought or earned.
- Art: anime-style painted heroes and creatures (cel shading, thick dark outline) standing as camera-facing cut-outs in a 3D desert. Item icons are in a Shop Titans style: one bold object, thick black outline, flat cel shading, painted at 256 px.
- Heroes: the Drifter (a cowboy, Revolver), Astro (a spacewoman, Gravity Gun), Calavera (a mariachi skeleton, Guitarra), Ironwood (Spear), Solenne (Sun Scepter), Fadeaway (a basketball player), Jeżyk (a bald blue Slav in a tracksuit, Frisbee), May (Tommy Gun) and Mira.
- Tone: short, dry, frontier humour. Names out of a western (the Drifter, the Stranger, WANTED, Stakes) and one-line jokes for flavour: "Pick one. The desert waits." (the level-up), "A piece of you, for a piece of the world." (the Stranger).

## Who plays, and how

- One hand, portrait, short sessions, often on the move.
- In a run the thumb steers from anywhere below the top strip: a floating joystick appears where it lands. So in-run information has to live where the thumb is not: today a strip across the top (XP rail, level, clock and kill counter, gold, pause, ten item slots, power-up plates), the hero's own bars, banners, toasts, and screens that pause the game.
- Menus are tapped with the same thumb, so the lower half of the screen is the easy reach.
- Tested on a Pixel 8 Pro. The game draws a 1080×1920 canvas; taller phones get extra height, and the width stays 1080. Every screen keeps clear of a camera cutout.

## Compare it with the genre

For each screen, look at how these games handle the same moment and say what to take, adapted to a portrait, one-thumb phone game rather than copied:

- **Vampire Survivors:** the original. A minimal HUD, a fast level-up list, a chest opening with a fanfare, a collection grid.
- **Survivor.io** and **Archero 2:** portrait, one thumb, built for phones. Chunky skill cards, levels shown as stars, big reward moments, polished menus between runs, stage select.
- **Megabonk:** the closest to our 3D camera. Upgrades coloured by rarity, chests, shrines, a character select.
- **Brotato:** the shop between waves, item rarity tiers, a stats panel people actually read.
- **20 Minutes Till Dawn** and **HoloCure:** leaner and cuter takes on the same loop; HoloCure's stamps and quests.

## The pieces

Every piece below is in the screenshots, most of them on several screens. Review each once, and the states that matter (pressed, disabled, selected, locked, empty).

- **Buttons:** the main call to action (PLAY, TAKE IT, DEAL, RESUME), secondary buttons, the REROLL · SKIP · BANISH row with its counts, the back square, switches, sliders and two-way choices.
- **The item card:** plate (kind by colour, a corner glyph), kind word, name, level stars, an UPGRADE / NEW / EVOLUTION tag, one effect line or "Damage 12 → 15" rows, the favourite's heart. Used by level-ups, mutation offers, the chest, the shop and the Stranger.
- **Plates by kind and level:** weapons, Cards (lines), passive items on a rarity ladder (common to legendary, then evolved), mutations, perks, creatures with danger badges (Elite crown, boss skull, special gear).
- **Marks:** level stars, a weapon's mutation rivets, a talent's six rank slots, progress bars on quests and posters, stamps (BEATEN, PAID, TAKEN, BANISHED, UNLOCKED).
- **Lists and grids:** the Collection's tiles and pages, the pause Build rows and Stats cells with their sources card.
- **Numbers:** gold (e.g. 102,682), kills, the run clock, costs and prices.
- **The in-run HUD:** see its page. **Health and threats:** the hero's HP and shield bars, a boss's name and HP, edge pointers to an off-screen boss, Elite or the portal.
- **Messages:** toasts, banners (BOSS DOWN, EVOLVED, ENDLESS, PHOENIX FEATHER), +XP / +gold pop-ups, floating damage numbers, first-play hints.
- **The modal frame:** every screen that pauses the run, the TAP TO GO gate after a pick, and the one "Hold on" question card for deeds that cannot be undone.
- **One-offs:** the hero carousel and plaque, the hero drawer, the hero's Wanted-poster sheet, the stage cards, the mirror's talent tiles, the chest's reel, the Spirit Pole, the floating Wanted posters, the drum moment, the Results' charts and count-ups.

## Words the game uses

- **Weapon:** fires by itself, 5 levels, 5 slots.
- **Card (a "line" in code):** a run-long trait named after a tarot card, 5 slots, 4 levels; a maxed Card can evolve ("<card> Risen").
- **Passive item:** a stat item, no slot cap, climbs a rarity ladder as it levels; not on the HUD (the pause Build tab lists them).
- **Perk:** a one-off power only one hero is offered.
- **Mutation:** each weapon has three paths; a mutation offer at set times gives one. All three plus level 5 = its **evolution** at a chest.
- **Chest:** dropped by Elites, specials and bosses; a reel lands on one item.
- **Elite, special and boss:** an Elite is a crowned, stronger creature; a special a rare glowing one with a sure chest; a boss ends each stage.
- **Portal, extract, Endless:** after the boss, 60 seconds to walk into the portal and extract; then Endless waves until death. Every end of a run banks the purse.
- **Bounty / Wanted poster:** an optional task taken at the start of a run, paid in coins at the end if done.
- **Totem Pole, the Stranger, the shop, the War Drum, barrels:** things on the map that pause for a choice or give a boost.
- **Upgrade board ("the Mirror" in code):** permanent talents bought with gold between runs; **Stakes** is the talent that makes runs harder for more XP and coins.
- **Reroll, skip, banish:** redraw the cards (per run), pass on an offer (per stage), strike an item out of the run (per stage).

## The art it has to sit with

The painted art stays; the UI around it is what we review. The two art pages (right after this brief in the PDF; art_items.jpg and art_more.jpg in the pack) show every item icon, the heroes, the creatures and the badges that float over them; the screenshots show the world. Your UI frames this art. If you think the icons' style fights your direction, say so.

## What the UI must do (how is open)

- Portrait 1080×1920, one thumb, clear of a camera cutout.
- The game pauses behind every screen that asks for a choice, and after a pick play resumes only on a tap, so a pick never drops the player straight into a hit.
- One paused screen at a time (death wins); whatever else is due waits its turn.
- Every item's icon, name and generated numbers can be found somewhere.
- Each screen's "Must still do" list. How it looks, where it sits and whether it shares a screen with something else is open.

## What we can build

- Anything made of layered panels, images, text, bars and simple shapes, animated with tweens. Nine-slice frames and painted art are fine: our art pipeline paints backgrounds, frames, badges and icons in any style you define, and Blender can model small 3D pieces.
- Gradients, glows and animated effects through shaders are fine. A full-screen blur over the running 3D world is too costly on phones.
- Any open font (TTF) and new sounds.
- Card text is generated from the game's data, so its length varies: names up to about 20 characters, descriptions up to three lines. A design has to survive that.

## Today's UI, for reference

So you know what you are looking at.

- The "Wanted" kit (ui/wanted/), built in code in Godot 4.7: hard-edged paper panels with ink borders and hard ink shadows, brass rivets and stars, slab-serif titles, nailed paper tags, stamps, item plates coloured by kind and level. Every screen is built from the same components.
- Colour: paper #f3e6c8, ink #241b14, brass #c9932f (the primary button, the coin), rock red #b4472b (danger, bosses), sage #6e8b5e (health, good), mutation plum, XP purple; dims are sepia.
- Type: Alfa Slab One for titles, numbers and buttons, Bitter (and its italic) for body text, JetBrains Mono only in the developer menu.
- The world behind the menus: the title stands the hero in the map itself (the "live" title).

## The screens

| # | Screen | When the player sees it | Shots |
|---|---|---|---|
{TABLE}

## What to send back

1. **The critique:** the ten biggest problems across the whole UI, most important first, one line each with why. Then, per screen, a verdict (keep, rework, merge or cut) and how the genre's best handle the same moment.
2. **Directions:** where the Wanted kit should go next, or up to three alternatives if you think it should be replaced. Each as a style tile (palette, type, shapes and materials, icon framing, a button, an item card) applied to the level-up cards and the in-run HUD.
3. **The screens you would change**, mocked at 1080×1920 with their states.
4. **The flow:** which screens to merge, remove or reorder, and how a new player gets from launch to the first run and the first bounty.
5. **Notes for the build:** sizes in px on the 1080×1920 canvas, colours in hex, fonts, and which pieces repeat, so we build each once.

## What we already suspect

These are our own doubts. Confirm them, overrule them, and don't stop at them.

- There is a lot of small text: card effect lines, the hero plaque's numbers, the hero sheet, the Upgrade board's tiles, the pause Stats tab.
- The run start has stacked up: the beam, then the bounty posters, then the first-play hints, then the first level-up.
- Players meet many named systems: Cards, passive items, mutations, evolutions, perks, Totem gifts, bounties, the Stranger, the War Drum, power-ups, Stakes.
- The HUD top strip is full: XP rail, level, clock with the kill counter and Endless states, gold, pause, ten slots, power-up plates, the bounty plate and build-up words.
- The Results screen plays a long show (banked gold, the chart, damage sources, the bounty, unlocks): is the order right, and is it too long?
- Rarity is shown on passive items only; weapons and Cards show levels by colour. Does a player read that?
"""

S = []

S.append({"id": "01_title", "name": "Title", "when": "on launch, and back from every hub screen and from Results",
 "shots": [("01-title", "wanted"), ("02-title-astro", "wanted"), ("01c-title-locked-hero", "wanted")],
 "job": "Pick a hero and start a run in one tap; reach the Upgrade board, the Collection and Settings.",
 "on": [
  "Top left the purse: a gold plate with a coin and the banked gold.",
  "The star line 'Wanted', the logo OUTLAW / SURVIVORS (the game's name on screen since pass 115) and 'Drag · Dodge · Survive'.",
  "The hero standing in the map itself, drawn as a run draws him, his start weapon's companion circling him; arrow squares either side and a swipe change hero (he runs in from the side the finger went); a dot per hero under him.",
  "The hero plaque: his name, a two-line flavour, up to three trait numbers (HP, SPEED, CRIT / LV ...), the START weapon and FAVOURITE item plates. A tap opens his Wanted-poster sheet; the square at its left opens the hero drawer.",
  "A hero on sale (his quest done, not bought): a BUY · <price> column over him; a tap asks 'Buy this hero?'.",
  "A locked hero: a black silhouette named 'Unknown', '?' for every number and plate, a padlock, and a 'To unlock' card with his quest and a progress bar; PLAY reads LOCKED.",
  "PLAY, the map line under it ('Red Canyon · best 7:10 · Lv 22 · stage 1 · 1,234 kills'), then Upgrade (turquoise, glowing, a brass '!' when a rank is affordable), Collection and Settings.",
  "Only in a tester's debug mode: ARENA top right. The first launch shows the play-data question over it (see its page)."],
 "keep": ["One tap to play with the last hero.", "Change hero, see who is locked and how to get him, buy one.",
          "Reach the Upgrade board, Collection and Settings.", "The purse."],
 "suspect": ["The plaque packs name, flavour, numbers and two plates into 200 px: hard to read at arm's length.",
             "Three ways to look at heroes (the carousel, the drawer, the sheet) may be one too many."],
 "ask": ["Should the hero carousel and the hero drawer be one thing?"]})

S.append({"id": "02_hero_drawer", "name": "Hero drawer", "when": "the square left of the title's hero plaque",
 "shots": [("65_hero_drawer", "bible")],
 "job": "See every hero at once and jump to one.",
 "on": ["Every hero that is not hidden as a badge tile in two rows, each in the look he is played in, the shown one framed.",
        "A hero not owned: a black silhouette badge with '?' on an aged tile, his price with a coin under it (on sale) or 'Locked'.",
        "While it is open the square's glyph is a close X; the title's swipe is off (the drawer takes sideways drags); it scrolls when the heroes do not fit."],
 "keep": ["Every hero, owned or not, in the carousel's order.", "Pick one in a tap."],
 "suspect": ["It covers the hero it is meant to choose."], "ask": []})

S.append({"id": "03_hero_sheet", "name": "Hero sheet and looks", "when": "a tap on the title's hero plaque",
 "shots": [("65b_hero_sheet", "bible"), ("hero_sheet_stats", "meta"), ("fadeaway_sheet_buy", "skins"), ("fadeaway_sheet_worn", "skins")],
 "job": "The hero's CV as a Wanted poster: who he is, his signature stat, the stats a run starts with, his items, and his looks.",
 "on": ["Portrait (the badge of the look he is played in), star line 'Wanted', the name, the slogan, 'Trait · <name>'.",
        "Signature stat: the trait's rule in words, its step per level in big numbers, and what it comes to at levels 1, 10, 20 and 40.",
        "'Stats · a run's start' (and 'your upgrades in' when the Upgrade board has ranks): every stat a run starts with, his signature stats in sage, multipliers as percents (e.g. 'Health on revive').",
        "Items: the start weapon, the favourite and what finding it gives (a bonus level), weapons only he can find, his hero mutation, his perks; each with its plate and the level-up card's words.",
        "LOOKS: a row of skin tiles. Locked ones are dark silhouettes with their quest (e.g. beat a stage); others show a price and BUY (a 'Hold on' question first; short of gold is refused); owned ones can be worn, the worn one marked. The title then draws him in that look.",
        "A hero not owned: 'Unknown' under a black badge, '?' everywhere, 'Unknown until this hero is yours'; locked: a 'To unlock' box; on sale: 'On sale' with his price.",
        "CLOSE, a tap on the dim or the back gesture close it; a long sheet scrolls with a paper fade at its foot."],
 "keep": ["Who the hero is and what makes him different, in numbers.", "His items.", "His looks: what each costs or needs, buy and wear."],
 "suspect": ["It is long: most players will read the top third only.", "Skins sit at the bottom of a stats sheet; is that where a player looks for them?"],
 "ask": ["Would the looks read better as their own screen or as a swipe on the title?"]})

S.append({"id": "04_stages", "name": "Stages", "when": "PLAY on the title, once the map's first stage has been beaten",
 "shots": [("18-stages", "wanted"), ("18c-stages-all-beaten", "wanted")],
 "job": "Choose which stage of the map to play; each stage is its own fresh run with the chosen hero.",
 "on": ["Header 'Stages' with the hero's badge; 'Red Canyon · <hero>' and the call 'Choose a Stage'.",
        "A card per stage (Sundown, Nightfall, Blood Moon): its picture with STAGE k and the name, 'Difficulty: Easy / Medium / Hard / Extremely Hard' in the stage's colour, a short description, the time to its boss and the boss.",
        "A sage BEATEN stamp on a beaten stage; a locked one aged with a padlock and 'To unlock: Beat the Tumbleweed King' (or 'Beat Stage k' before that boss was met); a boss never met is a silhouette, 'Boss not encountered yet'.",
        "A tap on an open card starts that stage at level 1; a locked card shakes."],
 "keep": ["The three stages, what each asks, which are open and which beaten.", "Start one in a tap."],
 "suspect": ["Until stage 1 is beaten PLAY skips this screen, so a new player never learns the stages exist."], "ask": []})

S.append({"id": "05_upgrade_board", "name": "Upgrade board", "when": "the title's Upgrade button, or Results' Upgrade button",
 "shots": [("board", "meta"), ("03b-mirror-talent-open", "wanted"), ("nerve_sheet_full", "meta")],
 "job": "The meta progression: spend banked gold on permanent talent ranks that hold for every hero.",
 "on": ["Header 'Upgrade' with the purse; a YOUR UPGRADES strip with a chip per talent that has ranks (its form's icon and ×rank).",
        "The mirror (two brass eyes in dark glass) and 'Something looks back. It wants gold.'",
        "A two-column grid of eight talent tiles, sorted by first-rank price: Grit, Drive, Stride, Study, Fortune, Choice, Nerve, Stakes. Each: name, both forms' icons ('or'), six rank slots (bought ones show their form's icon), what a rank gives, the next price on a paper tag or 'Full'.",
        "A tile opens its sheet: the rank bar large, flavour, 'Rank r of 6 owned', and one buy button per form (e.g. PADDING · 120 / PLATE · 120). Every rank keeps the form it was bought in. Rank k costs k² × rank 1.",
        "Nerve: Skip (+1 skip a stage) or Second Wind (the health he gets up with: 40% at base, 100% at six ranks). Stakes: Difficulty or Boss: harder creatures (or bosses and Elites) for a hidden +5% XP and coins a rank.",
        "'Take it all back' at the foot: a 'Hold on' question, then every rank goes and half the gold comes back."],
 "keep": ["What each talent does, what is bought, what the next rank costs.", "Two forms per rank, fixed once bought.", "Undo all for half."],
 "suspect": ["Two forms per rank across six ranks is a lot of reading per talent.", "Stakes (pay to make it harder) needs its reward said plainly; today it is hidden."],
 "ask": []})

S.append({"id": "06_collection", "name": "Collection", "when": "the title's Collection button",
 "shots": [("04-collection", "wanted"), ("04h-collection-enemies", "wanted"), ("04b-collection-weapon-page", "wanted"), ("04d-collection-locked-page", "wanted")],
 "job": "Browse every weapon, Card, passive item, perk and creature the player has met, and what locked ones need.",
 "on": ["Tabs: Weapons, Cards, Passives, Perks, Enemies; the open tab's found count in the header ('n / m'); '<n> kills all time' at the foot.",
        "Tiles: the plate in its colour and the name; enemies carry danger badges (boss skull, Elite crown, special gear). Not found yet: an aged plate with the icon's shadow. Behind a quest: the quest's words and a brass progress bar.",
        "An item page: plate, kind line ('Weapon · 5 levels'), the full text, kills with it, a levels grid; a weapon lists its three mutations (heroes' own marked, e.g. 'CALAVERA ONLY') and its evolution; a creature its numbers and 'Killed n times'.",
        "A locked item's page: 'Locked · <kind>', the quest, its progress, which stage can do it."],
 "keep": ["Everything met, its full numbers, and how to get what is locked."],
 "suspect": ["Five tabs of near-identical grids; the pages are walls of text."], "ask": []})

S.append({"id": "07_settings", "name": "Settings", "when": "the title's Settings button",
 "shots": [("settings", "meta"), ("05b-settings-wipe-confirm", "wanted")],
 "job": "Player options, privacy switches and wiping the save.",
 "on": ["Camera: Fixed ('north stays up') / Follow ('swings behind the hero').",
        "Sliders: joystick size 60-140%, screen shake 0-150%, sound and music.",
        "Switches for damage, heal, XP and coin numbers; floating text size Small / Normal / Large.",
        "First-play hints on/off and 'Show the hints again next run: Reset'.",
        "Anonymous play data and Questions after a run, each with a line on what it means.",
        "'Wipe the save' (rock): a 'Hold on' question.",
        "The version line 'Outlaw Survivors v0.99 · <player name>' and when the save was last written. Holding it 2 s opens the developer menu; ten taps on the hints switch turn the tester's debug mode on (both absent in the production build)."],
 "keep": ["Every option above; each saves at once."],
 "suspect": ["Hidden doors (hold, ten taps) live on a player screen."], "ask": []})

S.append({"id": "08_hud", "name": "In-run HUD", "when": "the whole run",
 "shots": [("06-hud", "wanted"), ("06c-hud-full-build", "wanted"), ("06e-hud-mutation-next", "wanted"), ("06b-hud-boss-banner", "wanted"),
           ("06i-hud-kills-hot", "wanted"), ("06g-hud-endless", "wanted")],
 "job": "Everything the player reads while playing, with nothing to tap below the strip except the floating joystick.",
 "on": ["An XP rail across the top edge (purple fill on ink).",
        "A row of paper plates: 'LV n' left, the clock centred, the run's gold with a coin, the brass pause disc right. A tap anywhere on the strip pauses.",
        "The kill counter under the clock: a small skull and the count, with dings that grow with the kill rate (pass 109).",
        "The clock's modes: the stage's time on paper; while the portal waits, 'ENDLESS IN' and the seconds left on rock; in Endless the time survived on ink with 'WAVE n'.",
        "MUTATION NEXT: when a mutation offer is due the LV plate turns plum and 'MUTATION NEXT' sits at the rail's end.",
        "Ten slots: five weapons from the left, five Cards from the right; a held item is its plate in its level's colour with a level tag and a weapon's mutation dots (glowing when it can evolve); empty slots are dashed.",
        "Under them: power-up plates with seconds left (Sprint, Magnet, the War Drum's boost in drum red), build-up words (Adrenaline, Hot Streak ...) and the taken bounty's plate with its progress.",
        "A boss's name slab and HP bar while it lives; edge pointers (a paper tag with the target's name and distance) for an off-screen boss, Elite or the portal.",
        "Toasts under all that, one at a time; banners at 38% height (BOSS DOWN, EVOLVED · NAME, ENDLESS, PHOENIX FEATHER); '+N XP' and '+N' gold rising from the hero; the hero's HP and shield bars under him jiggle when hit (the screen does not shake); floating damage numbers (white, crits yellow, fire orange, poison purple; on the hero red, blue, green)."],
 "keep": ["Level and XP, time (and the portal and Endless states), kills, gold, pause.", "The build in ten slots with levels and mutation marks.",
          "Timed boosts, the bounty, the boss, pointers, messages.", "The thumb's area and the crowd around the hero stay clear."],
 "suspect": ["The strip carries a great deal; the plates under the slots grow downward into the play area in a long run.",
             "Passive items are not on the HUD at all."],
 "ask": ["What would you drop from the strip first?"]})

S.append({"id": "09_bounty_posters", "name": "Wanted posters (the bounty)", "when": "the start of a run, right after the hero lands from the spawn beam",
 "shots": [("posters_hang", "bounty"), ("taken_stamp", "bounty"), ("taken_plate", "bounty")],
 "job": "Offer an optional task for this run, paid in coins at its end if done.",
 "on": ["The run pauses under a light dim; three Wanted posters drop in on strings from the top and sway gently, each hung by its nail: the task (kill so many of a creature, deal damage with a weapon, open barrels, use totems, restore HP...), its target and its reward in coins.",
        "A tap on one takes it: stamped TAKEN, the others fall away, and it flies into a bounty plate on the right under the item row, which shows its progress for the run.",
        "'No bounty' lets them all blow away.",
        "The reward is paid at the end of the run (Results shows it), only if the task was done."],
 "keep": ["Three tasks, take one or none, see its progress during the run."],
 "suspect": ["It pauses the run a second time right after the beam; a new player has not yet seen a creature."],
 "ask": ["Would the posters be better before the run, or as a plate that can be opened at will?"]})

S.append({"id": "10_levelup", "name": "Level-up cards", "when": "every level-up",
 "shots": [("07-level-up", "wanted"), ("07b-level-up-spent", "wanted")],
 "job": "Choose one of three upgrades: a new item or the next level of one held.",
 "on": ["A full rainbow XP rail along the top; star line 'Level up', 'LEVEL N' over a turning brass shine, confetti on entry, the dry line 'Pick one. The desert waits.'",
        "Three item cards dropping in: plate, kind word, name, level stars, an UPGRADE (brass) / NEW (sage) / EVOLUTION (ember) tag, one effect line, or for an upgrade its changes ('Damage 12 → 15') with the new stars pulsing; the hero's favourite has a brass heart.",
        "REROLL ×N (per run) · SKIP ×N · BANISH ×N (per stage). Banish mode turns the title red and stamps what may go; refused cards shake and say why. At 0 a button locks and says what gives more.",
        "Levels gained during a pause are banked and shown one after another; with nothing left to offer, +10 gold."],
 "keep": ["Three choices, readable in a glance.", "Reroll, skip, banish with their counts."],
 "suspect": ["The card's lower half (effect lines) is small for the most-read screen of the game."], "ask": []})

S.append({"id": "11_mutation", "name": "Mutation offer", "when": "at set times in each stage, in place of the next level-up's cards",
 "shots": [("29b-path-reel", "wanted"), ("08-path-offer", "wanted")],
 "job": "Take one of a weapon's path mutations; all three plus level 5 lead to its evolution.",
 "on": ["First a reel: the hero's weapons with an open path slide past a brass window, ticking and slowing, and stop on one (a tap skips to the landing).",
        "Head: 'Level N! Pick a mutation', the weapon's plate with a shine, its name and its mutation rivets (taken / offered).",
        "The mutation cards under it; one SKIP ×N. No reroll or banish here."],
 "keep": ["Which weapon, which mutations, how far along its path."],
 "suspect": ["The reel adds a wait to a pause the player did not ask for."], "ask": []})

S.append({"id": "12_tap_to_go", "name": "Tap to go", "when": "after a level-up pick, a mutation pick or a chest",
 "shots": [("09-gate-tap-to-go", "wanted")],
 "job": "Let the player re-grip before the run goes on, and show where the pick went.",
 "on": ["The dim lifting to a light sepia; the picked card shrinking and flying into its HUD slot, which takes a brass border.",
        "'TAP TO GO' and 'Still paused. They'll wait.' low on the screen; any touch resumes (with a second of blinking safety) and can start the joystick at once."],
 "keep": ["No pick drops the player straight into a hit."], "suspect": [], "ask": []})

S.append({"id": "13_chest", "name": "Chest", "when": "touching a chest (Elites, specials, bosses)",
 "shots": [("10c-chest-opening", "wanted"), ("10-chest", "wanted"), ("10b-chest-boss", "wanted")],
 "job": "The run's reward moment: a slot-machine reel lands on one item.",
 "on": ["Star line 'Loot' and CHEST in brass (a boss's: 'A path opens', MUTATION CHEST in purple).",
        "The chest drops in, knocks three times and throws its lid open; its light rises into the reel's row; slot-machine sounds.",
        "The reel of plates runs for about four seconds and lands; the landed plate grows with a brass glow; under it the kind, tag, name, stars and effect (gold: 'Straight into the purse').",
        "SKIP ×N · BANISH ×N (the reel spins again) · TAKE IT. Taps hurry the opening and the spin. A boss chest also pulls every pickup on the map in."],
 "keep": ["A reward with a fanfare, what it is, take or pass."], "suspect": [], "ask": []})

S.append({"id": "14_shop", "name": "The shop", "when": "standing in the travelling shop's ring on the map (once a stall)",
 "shots": [("11-shop", "wanted")],
 "job": "Spend the run's gold on one of three items.",
 "on": ["Star line 'One visit only', THE SHOP, the run's gold.", "'You hold': a wrapping row of plates for everything held.",
        "Three item cards with their prices as buttons; one short of gold is aged with '· N short'. One purchase, or LEAVE; either way the stall is spent."],
 "keep": ["What is for sale, what it costs, what the player holds."], "suspect": [], "ask": []})

S.append({"id": "15_stranger", "name": "The Stranger", "when": "standing in the hooded figure's ring on the map",
 "shots": [("12-stranger", "wanted")],
 "job": "A bargain: one strong item for a share of max HP for the rest of the run.",
 "on": ["A plum-black dim, star line 'No name', THE STRANGER; his cut-out holding the item and '“A piece of you, for a piece of the world.”'",
        "The item as a card; 'The price · max HP for the rest of the run' as a bar losing its end in hatched rock, 'max → new max'; 'No reroll. No second offer. He does not haggle.'",
        "DEAL or WALK AWAY; either way he is gone. His hooded figure is also the icon of what he gave in the pause Stats sources (pass 116)."],
 "keep": ["The item, the exact HP cost, yes or no."], "suspect": [], "ask": []})

S.append({"id": "16_totem", "name": "Spirit Pole (Totem gifts)", "when": "standing at one of the map's 10-12 Totem Poles",
 "shots": [("62_totem", "bible")],
 "job": "Pick one of three small stat gifts that last the whole run.",
 "on": ["'★ TOTEM k OF n ★' over the paused world in the modal dim, the HUD hidden.",
        "A carved pole on the left: the thunderbird crest on top, three spirit segments with carved faces on a cedar post.",
        "A nailed paper tag beside each: the amount big with its stat ('+2%' 'move speed'), the spirit ('Le-loo, the Wolf'), a roll gauge showing which third of its range the roll landed in (brass on a top third).",
        "Each row is one tap target; no close button. The chosen face flies to the toast slot ('Le-loo · +2% move speed'); the pole in the world greys."],
 "keep": ["Three gifts with their exact amounts, one tap to take."], "suspect": [], "ask": []})

S.append({"id": "17_drum", "name": "War Drum moment", "when": "using the War Drum on the map",
 "shots": [("drum_moment", "uidoc"), ("drum_moment_late", "uidoc")],
 "job": "A 2.2-second drum show that stops time and announces a 15-second boost.",
 "on": ["Time stops, the sound effects stop and the music holds; the drum fades in centre screen, squashing and springing on each slap, waves and ink slap lines from each hit.",
        "The last big hit flashes the screen and names the boost: '×2 DAMAGE · ×2 ATTACK SPEED · +15% SPEED' and knockback.",
        "Then the run goes on with a drum-red HUD plate counting the boost's 15 seconds. It cannot be skipped."],
 "keep": ["The boost said in words, and how long it lasts."], "suspect": [], "ask": []})

S.append({"id": "18_pause", "name": "Pause", "when": "a tap on the HUD's top strip or pause disc, or the app leaving the screen",
 "shots": [("13-pause-build", "wanted"), ("13b-pause-stats", "wanted"), ("13c-pause-options", "wanted"), ("13d-pause-abandon-confirm", "wanted")],
 "job": "Look at the build and the stats, change a few options, or abandon the run.",
 "on": ["'PAUSED' and '<clock> · Stage N' (or 'Endless'); tabs Build / Stats / Options; RESUME.",
        "Build: Weapons (n / 5), Cards (n / 5), Passives ('n · not on the HUD'), Perks; each row the plate, stars and what it does; a row opens on its numbers, its mutation chips and what evolving still needs.",
        "Stats: 'Changed this run', two columns of every stat with change pills (sage better, rock worse) since the run's start; a cell opens its sources card ('At the start': base, hero, Upgrade board; 'This run': cards, items, perks, mutations, levels, Totem gifts, the Stranger, timed buffs), each with its icon.",
        "Options: sound and music, screen shake, the floating numbers, and Abandon (a 'Hold on' question: the gold picked up so far comes home)."],
 "keep": ["The whole build and where every stat comes from.", "A few options; abandon with the gold kept."],
 "suspect": ["The Stats tab is the densest screen in the game."], "ask": []})

S.append({"id": "19_down", "name": "Down!", "when": "the hero's health reaches zero",
 "shots": [("14-down", "wanted")],
 "job": "Get up once or end the run.",
 "on": ["A rock dim, 'N CHANCE(S) LEFT', DOWN!; a paper disc counting down 8 seconds with 'get up', ticking in the last three.",
        "'<killer> put you down.' with its badge; '<clock> · N kills · Lv N'; 'Stay down and the N gold still comes home.'",
        "GET UP · WATCH AN AD (a stand-in: no ad plays yet; revives with a blast that clears round him; locked with NO CHANCES LEFT) and STAY DOWN (a 'Hold on' question). The gold revive is gone (pass 77).",
        "Phoenix Feather, when held, stands him up by himself instead (banner PHOENIX FEATHER)."],
 "keep": ["Who killed him, how many chances are left, get up or stay down.", "The gold comes home either way."],
 "suspect": ["'WATCH AN AD' with no ad behind it."], "ask": []})

S.append({"id": "20_stage_clear", "name": "Stage clear (the portal)", "when": "walking into the portal after a stage's boss",
 "shots": [("15-stage-clear", "wanted"), ("06f-hud-portal", "wanted")],
 "job": "Leave with the run's gold before Endless, or keep fighting.",
 "on": ["A BOSS DOWN tag and 'STAGE N CLEAR'.",
        "The Extract road: 'Safe · run ends' with the run's gold big in brass.",
        "The Endless card: 'Starts in' with the seconds counting down (rock in the last ones), what Endless is, 'The N gold comes home either way.'",
        "NOT YET: the run goes on ('The portal waits'); it asks again on the next step in. The countdown keeps running behind it; at zero it closes itself and Endless starts (an ENDLESS banner, then a wave every 10 seconds, the clock showing WAVE n).",
        "There is no 'next stage' road since pass 87: each stage is its own run."],
 "keep": ["Extract or stay, and how long is left to choose."], "suspect": [], "ask": []})

S.append({"id": "21_results", "name": "Results", "when": "after any run ends (extract, staying down, abandoning, falling in Endless)",
 "shots": [("16-results", "wanted"), ("results_paid_bounty_pay_04", "results"), ("results_open_end", "results"), ("16b-results-down", "wanted")],
 "job": "Tell the run's story: the gold banked, the kills and damage over time, the bounty, and what was unlocked.",
 "on": ["Star line (Extracted / Run over / Fell in Endless), the stage line ('STAGE 1 · SUNDOWN · BEATEN') in its colour, the run time big, 'Lv N · N kills · N chests · N evolutions'.",
        "The hero's badge and 'Banked' counting up along the run's purse curve, the purse before and after; a NEW BEST seal.",
        "Run performance: the kills chart drawn left to right with badges (a grave for each fall, a skull per boss, a crown per Elite, a gear per special), Kills and Damage counters, then 'Damage dealt' rows per source arriving as the line reaches the moment each joined.",
        "The bounty (pass 116): after the banked count the poster's panel fades in, its bar counts up to how far the run came, a stamp lands (PAID / FAILED / NOT DONE) and the reward shows as a coin and a gold '+N'; a paid one flies coins into Banked, which ticks up by N.",
        "'Unlocked this run' with UNLOCKED or FOR SALE stamps; 'Unlock progress' bars filling (this run's part in sage).",
        "PLAY AGAIN (the same stage and hero), Upgrade, Main Menu. A tap hurries the show, a second ends it. A survey card may follow (see its page)."],
 "keep": ["Gold banked and why, the run's arc, the bounty's result, what opened."],
 "suspect": ["The show is long; most players will tap through it."], "ask": ["What order would you play it in?"]})

S.append({"id": "22_first_launch_surveys", "name": "Play-data question and surveys", "when": "the first launch (over the title), and now and then after a run (over Results)",
 "shots": [("19-consent", "wanted"), ("19b-survey", "wanted")],
 "job": "Ask once whether anonymous play data may be sent; ask a few questions after a run now and then.",
 "on": ["PLAY DATA under 'A quick word': what is sent (the items you pick, where you fall, how smoothly it runs), that the player appears only as a generated name (e.g. 'Dusty Coyote 41'); NO THANKS / OK. Nothing is sent until it is answered.",
        "A survey card (written in PostHog): '1 / 3', the question, a rating row, choices or a text box; NEXT / SEND, NOT NOW, and 'Don't ask me again' under the card. At most one every three runs, never twice a session."],
 "keep": ["A clear yes or no to data, and an easy way out of every question."], "suspect": [], "ask": []})

S.append({"id": "23_debug", "name": "Developer menu and debug arena (testers only)", "when": "only for us: the developer menu (hold Settings' version line) and ARENA in debug mode",
 "shots": [("17-developer-menu", "wanted"), ("57_arena_enemy", "bible")],
 "job": "Every test switch and readout in one ink list, and a test room for every creature, item, hero, look and drop. Not for players.",
 "on": ["The developer menu: ink background, mono type; the arena, the debug switches, frame rate, the camera-cutout preview, analytics and survey tools, the save file's state.",
        "The arena: the map and the hero with nothing coming unless asked; a quick column on the right (ARENA, AGAIN, CLEAR, WAVES, LV +1) and a bottom sheet with ENEMY, WAVES, ITEMS, HERO, DROPS, WORLD and SHOTS tabs; the old UiKit look.",
        "Neither exists in the production build."],
 "keep": [], "suspect": [], "ask": ["Low priority: no redesign needed. Flag anything from it that leaks into the player's screens."]})

SCREENS = S


def md_screen(s, idx):
    lines = ["# %s · %s" % (s["id"].split("_")[0], s["name"]), ""]
    for k, (shot, _) in enumerate(s["shots"]):
        lines.append("![%s, screenshot %d](screens/%s_%d.jpg)" % (s["name"], k + 1, s["id"], k + 1))
    lines += ["", "**When it shows:** " + s["when"] + ".", "", "**Its job:** " + s["job"], "", "**On it now:**", ""]
    lines += ["- " + t for t in s["on"]]
    lines += ["", "**Must still do (how is open):**", ""] + ["- " + t for t in s["keep"]]
    if s["suspect"]:
        lines += ["", "**We suspect:**", ""] + ["- " + t for t in s["suspect"]]
    if s["ask"]:
        lines += ["", "**A question for you:**", ""] + ["- " + t for t in s["ask"]]
    return "\n".join(lines) + "\n"


def _inline(t):
    import re
    t = t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"`(.+?)`", r"<code>\1</code>", t)
    return t


def md_html(md, skip_h1=True):
    """The brief's small Markdown (headings, lists, bold, tables) as HTML."""
    out = []
    state = {"para": [], "lst": None, "table": []}

    def flush():
        if state["para"]:
            out.append("<p>" + _inline(" ".join(state["para"])) + "</p>")
            state["para"] = []
        if state["lst"]:
            tag, items = state["lst"]
            out.append("<%s>%s</%s>" % (tag, "".join("<li>" + _inline(x) + "</li>" for x in items), tag))
            state["lst"] = None
        if state["table"]:
            t = state["table"]
            head = [c.strip() for c in t[0].strip("|").split("|")]
            rows = [[c.strip() for c in r.strip("|").split("|")] for r in t[2:]]
            out.append('<div class="tbl"><table><thead><tr>' + "".join("<th>" + _inline(h) + "</th>" for h in head) + "</tr></thead><tbody>" +
                       "".join("<tr>" + "".join("<td>" + _inline(c) + "</td>" for c in r) + "</tr>" for r in rows) + "</tbody></table></div>")
            state["table"] = []
    for line in md.splitlines():
        if line.startswith("# "):
            flush()
            if not skip_h1:
                out.append("<h1>" + _inline(line[2:]) + "</h1>")
        elif line.startswith("## "):
            flush()
            out.append("<h2>" + _inline(line[3:]) + "</h2>")
        elif line.startswith("|"):
            if state["para"] or state["lst"]:
                flush()
            state["table"].append(line)
        elif line.startswith("- "):
            if state["para"] or state["table"] or (state["lst"] and state["lst"][0] != "ul"):
                flush()
            if state["lst"] is None:
                state["lst"] = ["ul", []]
            state["lst"][1].append(line[2:])
        elif len(line) > 2 and line[0].isdigit() and line[1:3] == ". ":
            if state["para"] or state["table"] or (state["lst"] and state["lst"][0] != "ol"):
                flush()
            if state["lst"] is None:
                state["lst"] = ["ol", []]
            state["lst"][1].append(line[3:])
        elif line.strip() == "":
            flush()
        else:
            if state["lst"] or state["table"]:
                flush()
            state["para"].append(line.strip())
    flush()
    return "\n".join(out)


PAGE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui_review_page.html")


def write_html(brief, allin):
    import datetime
    esc = lambda t: t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    ask_md = brief[brief.index("## What we are asking for"):brief.index("## The game in one minute")]
    rest = brief[brief.index("## The game in one minute"):]
    index = []
    secs = []
    for sc in SCREENS:
        n = sc["id"].split("_")[0]
        index.append('<a href="#s%s"><img src="screens/%s_1.jpg" alt="" loading="lazy"><span><b>%s</b>%s</span></a>' % (n, sc["id"], n, esc(sc["name"])))
        shots = "".join('<figure><img src="screens/%s_%d.jpg" alt="%s, screenshot %d" loading="lazy"><figcaption>%s_%d.jpg</figcaption></figure>'
                        % (sc["id"], k + 1, esc(sc["name"]), k + 1, sc["id"], k + 1) for k in range(len(sc["shots"])))
        notes = ['<h3>Its job</h3><p class="job">%s</p>' % _inline(sc["job"]),
                 "<h3>On it now</h3><ul>%s</ul>" % "".join("<li>%s</li>" % _inline(t) for t in sc["on"]),
                 '<h3>Must still do (how is open)</h3><ul class="keep">%s</ul>' % "".join("<li>%s</li>" % _inline(t) for t in sc["keep"])]
        if sc["suspect"]:
            notes.append('<h3>We suspect</h3><ul class="sus">%s</ul>' % "".join("<li>%s</li>" % _inline(t) for t in sc["suspect"]))
        if sc["ask"]:
            notes.append('<h3>A question</h3>%s' % "".join('<p class="q">%s</p>' % _inline(t) for t in sc["ask"]))
        when = sc["when"][0].upper() + sc["when"][1:]
        secs.append('<section class="screen" id="s%s"><header><h2><span class="n">%s</span>%s</h2><span class="when">%s</span></header>'
                    '<div class="grid"><div class="shots">%s</div><div class="notes">%s</div></div></section>'
                    % (n, n, esc(sc["name"]), esc(when), shots, "".join(notes)))
    nshots = sum(len(sc["shots"]) for sc in SCREENS)
    page = open(PAGE_PATH, encoding="utf-8").read()
    page = (page.replace("{COUNTS}", "%d screens · %d screenshots · 1080×1920" % (len(SCREENS), nshots))
            .replace("{ASK}", md_html(ask_md)).replace("{INDEX}", "".join(index)).replace("{BRIEF}", md_html(rest))
            .replace("{SCREENS}", "\n".join(secs)).replace("{DATE}", datetime.date.today().isoformat()).replace("{RAW}", esc(allin)))
    open(os.path.join(OUT, "index.html"), "w", encoding="utf-8", newline="\n").write(page)


PRINT_CSS = """
@page { size: 297mm 210mm; margin: 11mm 12mm; }
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { margin: 0; font-family: 'Segoe UI', Arial, sans-serif; font-size: 9.4pt; line-height: 1.38; color: #1a1a1a; background: #ffffff; }
h1, h2, h3 { font-family: 'Segoe UI', Arial, sans-serif; font-weight: 700; color: #111111; margin: 0 0 3mm; line-height: 1.1; }
h1 { font-size: 22pt; } h2 { font-size: 13pt; margin-top: 4mm; } h3 { font-size: 10.5pt; margin-top: 3mm; }
p { margin: 0 0 2.2mm; } ul, ol { margin: 0 0 2.2mm; padding-left: 5mm; } li { margin: 0 0 .7mm; }
strong { font-weight: 700; color: #111111; } code { font-family: Consolas, monospace; font-size: 9pt; }
.page { break-after: page; page-break-after: always; }
.cover { display: flex; gap: 10mm; height: 186mm; }
.cover .words { flex: 0 0 104mm; display: flex; flex-direction: column; justify-content: flex-end; }
.cover .name { font-size: 60pt; font-weight: 800; color: #111111; line-height: .95; }
.cover .sub { font-size: 14pt; color: #555555; margin: 3mm 0 6mm; }
.cover .rule { width: 34mm; height: 1.4mm; background: #111111; margin-bottom: 5mm; }
.cover .shots { flex: 1; min-width: 0; display: flex; gap: 3mm; align-items: flex-end; justify-content: flex-end; }
.cover .shots img { flex: none; width: 51mm; height: auto; border-radius: 2mm; }
.brief { column-count: 2; column-gap: 9mm; }
.brief h2 { break-after: avoid; }
.brief li { break-inside: avoid; }
.brief table { width: 100%; border-collapse: collapse; font-size: 8.4pt; break-inside: avoid; }
.brief th, .brief td { text-align: left; border-bottom: .3mm solid #cccccc; padding: .6mm 1.5mm; vertical-align: top; }
.brief .head p { margin: 0 0 .8mm; }
.art p { color: #444444; max-width: 250mm; }
.art img { display: block; width: 270mm; height: 158mm; object-fit: contain; object-position: top left; }
.screen { display: flex; gap: 8mm; height: 186mm; }
.screen .notes { flex: 0 0 110mm; overflow: hidden; font-size: 9pt; line-height: 1.34; }
.screen .notes li { margin: 0 0 .5mm; }
.screen .num { font-size: 11pt; font-weight: 700; color: #ffffff; background: #111111; border-radius: 1.5mm; padding: .5mm 2.4mm; display: inline-block; margin-bottom: 2mm; }
.screen .when { color: #555555; margin-bottom: 3mm; }
.screen h3 { font-size: 9.5pt; margin: 2.6mm 0 1mm; color: #555555; text-transform: uppercase; letter-spacing: .04em; }
.screen .shots { flex: 1; min-width: 0; display: flex; gap: 3mm; align-items: flex-start; justify-content: flex-start; }
.screen .shots figure { margin: 0; flex: 1 1 0; min-width: 0; max-width: 100mm; }
.screen .shots img { width: 100%; max-height: 176mm; object-fit: contain; object-position: top left; border-radius: 2mm; display: block; }
.screen .shots figcaption { font-size: 8pt; color: #777777; margin-top: 1mm; }
"""


def write_pdf(brief):
    """The whole pack as a printable page (A4 landscape: a cover, the brief in two columns, a page per screen with its
    screenshots beside its notes), then printed to 88fits_ui_review.pdf by headless Edge."""
    parts = ["<!doctype html><html><head><meta charset='utf-8'><title>88fits UI review brief</title><style>" + PRINT_CSS + "</style></head><body>"]
    cover_shots = ["01-title", "07-level-up", "06c-hud-full-build"]
    imgs = []
    for s in SCREENS:
        for k, (shot, _) in enumerate(s["shots"]):
            if shot in cover_shots and len(imgs) < 3:
                imgs.append("screens/%s_%d.jpg" % (s["id"], k + 1))
    sub = ("<div class='sub'>Outlaw Survivors · UI review brief for Claude Design · %d screens, %d screenshots at 1080×1920 · v0.99</div>"
           % (len(SCREENS), sum(len(x["shots"]) for x in SCREENS)))
    parts.append("<section class='page cover'><div class='words'><div class='rule'></div><div class='name'>88fits</div>"
                 + sub +
                 "<p><strong>Today's UI is here to be critiqued and replaced, not kept.</strong> Its colours, type, shapes and "
                 "layouts are all open; compare it with the best of the genre and design the alternative.</p>"
                 "<p>The brief follows, then the game's painted art, then one page per screen: what it is for, what is on it, what it "
                 "must still do, what we suspect, and its screenshots.</p></div><div class='shots'>" + "".join("<img src='%s'>" % i for i in imgs) + "</div></section>")
    parts.append("<section class='page'><h1>The brief</h1><div class='brief'>" + md_html(brief) + "</div></section>")
    parts.append("<section class='page art'><h1>The art it has to sit with · items</h1><p>" + _inline(ART_NOTE_ITEMS) + "</p><img src='art_items.jpg'></section>")
    parts.append("<section class='page art'><h1>The art it has to sit with · paths, heroes, creatures</h1><p>" + _inline(ART_NOTE_MORE) + "</p><img src='art_more.jpg'></section>")
    for i, s in enumerate(SCREENS):
        num = s["id"].split("_")[0]
        notes = ["<span class='num'>%s</span><h1>%s</h1><div class='when'>%s</div>" % (num, _inline(s["name"]), _inline("When it shows: " + s["when"] + "."))]
        notes.append("<h3>Its job</h3><p>" + _inline(s["job"]) + "</p>")
        notes.append("<h3>On it now</h3><ul>" + "".join("<li>" + _inline(t) + "</li>" for t in s["on"]) + "</ul>")
        notes.append("<h3>Must still do (how is open)</h3><ul>" + "".join("<li>" + _inline(t) + "</li>" for t in s["keep"]) + "</ul>")
        if s["suspect"]:
            notes.append("<h3>We suspect</h3><ul>" + "".join("<li>" + _inline(t) + "</li>" for t in s["suspect"]) + "</ul>")
        if s["ask"]:
            notes.append("<h3>A question for you</h3><ul>" + "".join("<li>" + _inline(t) + "</li>" for t in s["ask"]) + "</ul>")
        shots = "".join("<figure><img src='screens/%s_%d.jpg'><figcaption>%s, screenshot %d</figcaption></figure>" % (s["id"], k + 1, _inline(s["name"]), k + 1)
                        for k in range(len(s["shots"])))
        last = " page" if i < len(SCREENS) - 1 else ""
        parts.append("<section class='screen%s'><div class='notes'>%s</div><div class='shots'>%s</div></section>" % (last, "".join(notes), shots))
    parts.append("</body></html>")
    html_p = os.path.join(OUT, "print.html")
    open(html_p, "w", encoding="utf-8", newline="\n").write("".join(parts))
    pdf_p = os.path.join(OUT, "88fits_ui_review.pdf")
    if not os.path.exists(EDGE):
        print("ui review pack: Edge not found, no PDF (print.html is there to print by hand)")
        return
    url = "file:///" + os.path.abspath(html_p).replace("\\", "/")
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--print-to-pdf=" + pdf_p, url],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    print("ui review pack: %s (%.1f MB)" % (pdf_p, os.path.getsize(pdf_p) / 1048576.0 if os.path.exists(pdf_p) else 0.0))


ART_NOTE_ITEMS = ("Every weapon, evolution, passive, line and hero perk in the game today, as the painted icons (256 px, transparent): "
                  "one bold object, thick dark outline, flat cel shading. They stay; the frames, plates and cards around them are yours to design.")
ART_NOTE_MORE = ("The weapons' path picks (mutations), the heroes' portraits, the creatures, Elites and bosses as the collection shows "
                 "them, the badges that float over creatures in play (crown: Elite, skull: boss, gear: the specials), and the app icon.")


def _json(kind, cid):
    try:
        return json.load(open(os.path.join(CONTENT, kind, cid, cid + ".json"), encoding="utf-8"))
    except (OSError, ValueError):
        return None


def art_sections():
    """The painted art the new UI has to sit with, as two pages of (title, [(id, name, png)]). Hidden and retired content is
    left out, and so is whatever only hidden things bring: their evolutions, mutations and perks."""
    hidden_w, hidden_evo, hidden_h = set(), set(), set()
    for cid in os.listdir(os.path.join(CONTENT, "weapons")):
        d = _json("weapons", cid)
        if d and (d.get("hidden") or d.get("retired")):
            hidden_w.add(cid)
            hidden_evo.add(d.get("evolves_into"))
    for cid in os.listdir(os.path.join(CONTENT, "characters")):
        d = _json("characters", cid)
        if d and d.get("hidden"):
            hidden_h.add(cid)

    def icon_of(kind, cid, d):
        # a creature playing an art variant shows that variant's icon
        var = d.get("variant")
        name = ((d.get("variants") or {}).get(var) or {}).get("icon") if var else None
        path = os.path.join(CONTENT, kind, cid, name or cid + "_icon.png")
        return path if os.path.exists(path) else None

    def section(kind, keep=lambda cid, d: True):
        out = []
        for cid in sorted(os.listdir(os.path.join(CONTENT, kind))):
            d = _json(kind, cid)
            if not d or d.get("hidden") or d.get("retired") or not keep(cid, d):
                continue
            path = icon_of(kind, cid, d)
            if path:
                out.append((cid, d.get("name", cid), path))
        return out

    badges = [(b, b.capitalize() + " badge", os.path.join(REPO, "game", "art", "ui", "badges", b + ".png")) for b in ("crown", "skull", "gear")]
    items = [("Weapons", section("weapons")),
             ("Evolutions", section("evolutions", lambda cid, d: cid not in hidden_evo and d.get("evolved_from") not in hidden_w)),
             ("Passives", section("passives")),
             ("Hero perks", section("perks", lambda cid, d: d.get("hero") not in hidden_h))]
    more = [("Mutations (a weapon's path picks)", section("mutations", lambda cid, d: d.get("weapon") not in hidden_w and (d.get("hero") or "") not in hidden_h)),
            ("Creatures and Elites", section("enemies")),
            ("Heroes, bosses, badges and the app icon", section("characters") + section("bosses") + [b for b in badges if os.path.exists(b[2])]
             + [("app_icon", "App icon", os.path.join(REPO, "game", "icon.png"))])]
    return items, more


def _art_sheet(sections, path, cols=16, cell=150, label=30):
    """One contact sheet: a heading per section, the icons on a plain light ground, each named under it."""
    from PIL import ImageDraw, ImageFont
    try:
        f = ImageFont.truetype(os.path.join(FONT_DIR, "segoeui.ttf"), 16)
        fh = ImageFont.truetype(os.path.join(FONT_DIR, "segoeuib.ttf"), 26)
    except OSError:
        f = fh = ImageFont.load_default()
    pad, head = 24, 46
    rows = lambda n: (n + cols - 1) // cols
    h = pad * 2 + sum(head + rows(len(items)) * (cell + label) + 10 for _t, items in sections)
    img = Image.new("RGB", (pad * 2 + cols * cell, h), (238, 238, 238))
    dr = ImageDraw.Draw(img)
    y = pad
    for title, items in sections:
        dr.text((pad, y), "%s · %d" % (title, len(items)), fill=(20, 20, 20), font=fh)
        y += head
        for k, (_cid, name, src) in enumerate(items):
            x0 = pad + (k % cols) * cell
            y0 = y + (k // cols) * (cell + label)
            ic = Image.open(src).convert("RGBA")
            ic.thumbnail((cell - 16, cell - 16), Image.LANCZOS)
            img.paste(ic, (x0 + (cell - ic.width) // 2, y0 + (cell - ic.height) // 2), ic)
            t = name
            if dr.textlength(t, font=f) > cell - 6:
                while len(t) > 1 and dr.textlength(t + "…", font=f) > cell - 6:
                    t = t[:-1]
                t = t.rstrip() + "…"
            dr.text((x0 + (cell - dr.textlength(t, font=f)) / 2, y0 + cell - 4), t, fill=(60, 60, 60), font=f)
        y += rows(len(items)) * (cell + label) + 10
    img.save(path, "JPEG", quality=86, optimize=True)


def write_art():
    items, more = art_sections()
    _art_sheet(items, os.path.join(OUT, "art_items.jpg"))
    _art_sheet(more, os.path.join(OUT, "art_more.jpg"))
    return items + more


def main():
    os.makedirs(os.path.join(OUT, "screens"), exist_ok=True)
    for fn in os.listdir(os.path.join(OUT, "screens")):
        os.remove(os.path.join(OUT, "screens", fn))
    for fn in os.listdir(OUT):
        if fn[:2].isdigit() and fn.endswith(".md"):
            os.remove(os.path.join(OUT, fn))
    rows = []
    shot_files = []
    for s in SCREENS:
        rows.append("| %s | %s | %s | %d |" % (s["id"].split("_")[0], s["name"], s["when"], len(s["shots"])))
        for k, (shot, src) in enumerate(s["shots"]):
            im = Image.open(os.path.join(CAPS, src, shot + ".png")).convert("RGB")
            fn = "%s_%d.jpg" % (s["id"], k + 1)
            im.save(os.path.join(OUT, "screens", fn), "JPEG", quality=88, optimize=True)
            shot_files.append(fn)
    brief = BRIEF.replace("{TABLE}", "\n".join(rows))
    open(os.path.join(OUT, "00_brief.md"), "w", encoding="utf-8", newline="\n").write(brief)
    docs = []
    for i, s in enumerate(SCREENS):
        t = md_screen(s, i)
        open(os.path.join(OUT, s["id"] + ".md"), "w", encoding="utf-8", newline="\n").write(t)
        docs.append(t)
    art = write_art()
    art_md = ("# The art it has to sit with\n\n" + ART_NOTE_ITEMS + "\n\n![Item icons](art_items.jpg)\n\n" + ART_NOTE_MORE
              + "\n\n![Paths, heroes, creatures](art_more.jpg)\n")
    allin = brief + "\n\n---\n\n" + art_md + "\n\n---\n\n" + "\n\n---\n\n".join(docs)
    open(os.path.join(OUT, "ALL_IN_ONE.md"), "w", encoding="utf-8", newline="\n").write(allin)
    readme = ("# How to use this pack\n\nFor Claude Design: attach `88fits_ui_review.pdf` (the brief, the game's painted art and every "
              "screen with its screenshots beside its notes, in one file) and ask for the critique and the directions it "
              "describes. Attach no design system: the look is open. `art/` holds the icons one by one, to attach any the mocks should "
              "use. The Markdown files, `screens/` and the two art sheets hold the same content for tools that want them apart.\n\n"
              "Made by tools/make_ui_review.py from the game's own screenshots and the content folders' icons. Captures (1080x1920, "
              "windowed, bounded): `bash tools/ui_review_capture.sh` runs game/tools/wanted_shots.gd, uidoc_shots.gd, "
              "screenshot_run.gd, _p112_wanted_shots.gd, _p111_skins_shot.gd, _p116_RESULTS_shots.gd and _p115_META_shots.gd into "
              "tools/dl/p116/UIREVIEW/<set>/; then `python tools/make_ui_review.py [--caps=<dir>]`. The totem/ folder is a separate, "
              "older brief for the Totem screen alone. docs/ui_screens/ is the plain reference of every screen (not a review).\n")
    open(os.path.join(OUT, "README.md"), "w", encoding="utf-8", newline="\n").write(readme)
    json.dump({"screens": SCREENS}, open(os.path.join(OUT, "screens.json"), "w", encoding="utf-8", newline="\n"), indent=1, ensure_ascii=False)
    write_html(brief, allin)
    write_pdf(brief)
    zp = os.path.join(OUT, "88fits_ui_review.zip")
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        if os.path.exists(os.path.join(OUT, "88fits_ui_review.pdf")):
            z.write(os.path.join(OUT, "88fits_ui_review.pdf"), "88fits_ui_review/88fits_ui_review.pdf")
        for fn in ["README.md", "00_brief.md", "ALL_IN_ONE.md"] + [s["id"] + ".md" for s in SCREENS]:
            z.write(os.path.join(OUT, fn), "88fits_ui_review/" + fn)
        for fn in shot_files:
            z.write(os.path.join(OUT, "screens", fn), "88fits_ui_review/screens/" + fn)
        for fn in ["art_items.jpg", "art_more.jpg"]:
            z.write(os.path.join(OUT, fn), "88fits_ui_review/" + fn)
        for _title, items in art:
            for cid, _name, src in items:
                # a folder per kind, named after where the icon lives (content/<kind>/, the badges, the app icon)
                norm = src.replace("\\", "/")
                folder = norm.split("/content/")[1].split("/")[0] if "/content/" in norm else ("badges" if "/badges/" in norm else "app_icon")
                z.write(src, "88fits_ui_review/art/%s/%s.png" % (folder, cid))
    print("ui review pack: %d screens, %d shots, %s (%.1f MB)" % (len(SCREENS), len(shot_files), zp, os.path.getsize(zp) / 1048576.0))


if __name__ == "__main__":
    main()

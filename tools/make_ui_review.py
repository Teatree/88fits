"""The UI redesign pack for Claude Design (pass 34, reworked in pass 38): a brief, the game's painted art and one document
per screen with its screenshots, so the whole interface can be critiqued against the genre and redesigned from zero.
Today's UI is the thing under review: the brief asks for a new look, not a tidy-up of this one, so nothing here (the PDF's
own styling included) carries the game's current colours or fonts as a style to follow.

    python tools/make_ui_review.py --shots=<dir> --extra=<dir>
        <dir>: PNGs from tools/screenshot_run.gd (1080x1920); <extra>: PNGs from tools/ui_shots.gd

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
SHOTS = EXTRA = ""
for a in sys.argv[1:]:
    if a.startswith("--shots="):
        SHOTS = a.split("=", 1)[1]
    if a.startswith("--extra="):
        EXTRA = a.split("=", 1)[1]

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
CONTENT = os.path.join(REPO, "game", "content")
FONT_DIR = "C:/Windows/Fonts"

BRIEF = """# 88fits UI redesign: the brief

**For:** Claude Design

**From:** the 88fits team (Garry, who designs and plays it, and Claude Code, who builds it)

**What is attached:** 17 screens and states in 25 screenshots at the game's real size, 1080×1920, one page per screen, and two pages of the game's painted art.

## What we are asking for

Redesign the UI of 88fits from the ground up. Today's UI is the thing under review: it is here to be judged and replaced, not to set the style.

- **Start from zero on the look.** Our colours, fonts, corner radii, borders, panels, icon frames and layouts are all open. Nothing in today's UI survives because it exists; keep a thing only if you would have chosen it yourself.
- **Critique first, and be tough.** Look at every screen the way a senior UI and art lead for mobile games would. Say what does not work and why, even if it is a whole screen.
- **Compare with the genre.** Put each screen next to how the best games in the genre handle the same moment (see "Compare it with the genre"), and say what they do better and what we should take.
- **Then design the alternative:** a new visual direction for the whole game, with every screen and every piece under "The pieces" redone in it, as mock-ups at 1080×1920.
- **Strip it down.** If an element, a line of text, a button or a screen does not earn its place, cut it, merge it or move it. Fewer, bigger, clearer things beat many small ones. You do not need our permission; tell us why.
- **Art counts as much as layout.** Backgrounds, framing, materials, colour, type, icon treatment and motion are all part of the redesign.

## The game in one minute

- 88fits is a portrait, one-thumb survivor shooter for Android phones, in the mould of Vampire Survivors, Megabonk and Survivor.io. The hero fires by himself; the player only steers, with a floating joystick, through a crowd that grows to 150 to 240 creatures.
- A run lasts up to 15 minutes: three stages of five minutes on one map, Red Canyon, a sunlit desert of sand, cacti and red rock. After each stage's boss the player chooses: extract (bank the run's gold at ×1.25) or continue into a harder stage.
- Every level-up pauses the run for a card pick: weapons, passives, lines (run-long traits with a trade-off), and hero perks. At set times a weapon's path (three mutations) is offered. Chests spin a one-item reel. On the map: a travelling shop, the Stranger (a strong item for a slice of max HP), healing wells, a strongbox that banks gold.
- Between runs: The Mirror (eight talents, two forms each, three ranks, paid in gold), the Collection, Settings.
- Art: anime-style painted heroes and creatures (cel shading, thick dark outline) standing as camera-facing cut-outs in a 3D desert. Item icons are in a Shop Titans style: one bold object, thick black outline, flat cel shading, painted at 256 px.
- Heroes today: Astro, a spacewoman in a white suit, and the Drifter, a cowboy in a long duster.
- Tone: short, dry, frontier humour. Names out of a western (the Drifter, the Stranger, High Noon, WANTED) and one-line jokes for flavour: "Pick one. Throw it at the rest." (the Gravity Gun), "Everything looks like a nail." (the Hammer).

## Who plays, and how

- One hand, portrait, short sessions, often on the move.
- In a run the thumb steers from anywhere in the lower two thirds of the screen: a floating joystick appears where it lands. So in-run information has to live where the thumb is not. Today that is a strip across the top 250 px, the hero's own bars and modal screens that pause the game; where it goes in your design is open, as long as the thumb's area and the crowd around the hero stay clear.
- Menus are tapped with the same thumb, so the lower half of the screen is the easy reach.
- Tested on a Pixel 8 Pro. The game draws a 1080×1920 canvas; taller phones get extra height, and the width stays 1080.

## Compare it with the genre

88fits is made in the mould of these games. For each screen, look at how they handle the same moment and say what to take, adapted to a portrait, one-thumb phone game rather than copied:

- **Vampire Survivors:** the original. A minimal HUD, a fast level-up list, a chest opening with a fanfare, a collection grid.
- **Survivor.io** and **Archero 2:** portrait, one thumb, built for phones. Chunky skill cards, levels shown as stars, big reward moments, polished menus between runs.
- **Megabonk:** the closest to our 3D camera. Upgrades coloured by rarity, chests, a character select.
- **Brotato:** the shop between waves, item rarity tiers, a stats panel people actually read.
- **20 Minutes Till Dawn** and **HoloCure:** leaner and cuter takes on the same loop.

## The pieces

Every piece below is in the screenshots, most of them on several screens. Redesign each once, show it in use, and show the states that matter (pressed, disabled, selected, locked, empty).

- **Buttons:** the main call to action (PLAY, GO, Resume, Take it), secondary buttons, small rows of buttons (Reroll, Skip, Banish), back, on/off switches and two-way choices.
- **The item card:** icon, name, what kind of item it is, its level now and after the pick, what it does (generated text, up to three lines), a flavour line. Used by level-ups, path offers, the chest, the shop and the Stranger.
- **Icon framing by kind:** weapon, evolution, mutation, passive, line, perk, hero, creature.
- **Level and progress marks:** an item's level out of its maximum, a weapon's path picks (up to three), a talent's ranks, and rarity: every item is common, rare or epic, which decides how often it is offered and what it costs, and today's UI never shows it.
- **List rows:** the collection and the pause screen's build list, open and closed, locked and unlocked.
- **Tabs, sliders and switches.**
- **Numbers:** gold (six digits and more, e.g. 102682), kills, the run clock, costs.
- **The in-run HUD:** level and XP, the run clock, the stage, kills, gold, pause, and the build: up to six weapons and six passives with their levels, path picks, and slots locked until a later stage.
- **Health and threats:** the hero's health and shield bars; a boss's name and health; pointers to an off-screen boss, Elite or portal.
- **Messages:** toasts (+22 HP, Boomstick Lv 5, HOOKED!), banners (BOSS DOWN, EVOLVED: Earthshaker), the +5 XP pop-ups, first-play hints.
- **The floating joystick.**
- **The modal frame:** every screen that pauses the run (level-up, path offer, chest, shop, the Stranger, stage clear, down) and the tap-to-continue gate.
- **The menu frame:** back, a title, a scrolling page.
- **One-offs:** the Mirror's talent cards, the hero and map cards in Play setup, the chest's reel, the results summary with its damage bars.

## Words the game uses

- **Weapon:** fires by itself, up to 8 levels. Four slots in stage 1, six from stage 2.
- **Passive:** a stat boost for the run, up to 5 levels.
- **Line:** a run-long trait of the hero, often with a trade-off, taken in ranks; three or four a run; a maxed line can evolve.
- **Perk:** a one-off power that only one hero is offered.
- **Path and mutation:** at set times a weapon offers its three mutations (an element, more of it, or a new motion). The player takes one; the others come back next stage.
- **Evolution:** a weapon with two mutations can turn into its evolved form at a chest.
- **Chest:** dropped by Elites, bosses and some creatures; a reel lands on one item to take or sell.
- **Elite and boss:** an Elite is a named, crowned creature stronger than the crowd; a boss ends each stage.
- **Portal and extract:** after a stage's boss a portal opens: extract (bank the run's gold at ×1.25) or continue into a harder stage.
- **The Mirror:** permanent talents bought with gold between runs.
- **The Stranger:** a hooded figure on the map who trades a strong item for a slice of max HP.
- **Travelling shop, healing well, strongbox:** stalls on the map to buy an item, heal, or bank gold mid-run.
- **Reroll, skip, banish:** redraw the level-up cards, pass for gold, or strike one card out of the run.

## The art it has to sit with

The painted art stays for now; the UI around it is what we want redone. The two art pages (right after this brief in the PDF; art_items.jpg and art_more.jpg in the pack) show every item icon, the heroes, the creatures and the badges that float over them; the screenshots show the world, a sunlit 3D desert of sand, cacti and red rock. Your UI frames this art. If you think the icons' style fights your direction, say so.

## What the UI must do (how is open)

- Portrait 1080×1920, one thumb.
- The game pauses behind every screen that asks for a choice, and play resumes only on a tap, so a pick never drops the player straight into a hit. How that gate looks is up to you.
- Every item's icon, name and generated numbers can be found somewhere.
- Each screen's "Must still do" list. How it looks, where it sits and whether it shares a screen with something else is open.

## What we can build

- Anything made of layered panels, images, text, bars and simple shapes, animated with tweens. Nine-slice frames and painted art are fine: our art pipeline paints backgrounds, frames, badges and icons in any style you define, and Blender can model small 3D pieces.
- Gradients, glows and animated effects through shaders are fine. A full-screen blur over the running 3D world is too costly on phones.
- Any open font (TTF) and new sounds.
- Card text is generated from the game's data, so its length varies: names up to about 20 characters, descriptions up to three lines. A design has to survive that.

## Today's UI, for reference only

So you know what you are looking at. None of it has to stay.

- Built in code in Godot 4.7 from a small kit: panels and cards with rounded corners (18 to 30 px) and 2 to 4 px borders, bevelled buttons, chips, icon tiles framed in their kind's colour, progress bars, level pips, sliders, tabs and scrolling lists.
- Colour: navy grounds with lighter navy lines, white and grey-blue text, gold for the main button and the selected state, violet for XP, red for danger, green for good. Cards are coloured by kind: weapons gold, passives violet, mutations magenta, lines orange, perks green.
- Type: Lilita One for headings and buttons, Baloo 2 for body text.

## The screens

| # | Screen | When the player sees it | Shots |
|---|---|---|---|
{TABLE}

## What to send back

1. **The critique:** the ten biggest problems across the whole UI, most important first, one line each with why. Then, per screen, a verdict (keep, rework, merge or cut) and how the genre's best handle the same moment.
2. **Three visual directions**, clearly different from each other and from today's UI. Each one as a style tile (palette, type, shapes and materials, icon framing, a button, an item card) applied to two screens: the level-up cards and the in-run HUD. We pick one.
3. **Everything in the chosen direction:** every screen and every piece under "The pieces", mocked at 1080×1920 with their states.
4. **The flow:** which screens to merge, remove or reorder, and how a new player gets from launch to the first run.
5. **Notes for the build:** sizes in px on the 1080×1920 canvas, colours in hex, fonts, and which pieces repeat, so we build each once.

## What we already suspect

These are our own doubts. Confirm them, overrule them, and don't stop at them.

- The menus look like a generic dark app. Nothing in them says sunlit desert, anime, cowboys and a spacewoman: the painted art mostly stays inside the run.
- There is too much small text. A level-up card carries a kind tag, a name, a level chip, pips, a stat line and a flavour line. The Mirror and Play setup read like forms.
- Developer tools show on player screens: "Debug · Arena" on the title; "Last run's last second", "Recent system pauses" and the save file's path in Settings; "Debug panel" in the pause options; a small "debug" button on the level-up screen; a "dbg revive" on the Down! screen. They should move to one hidden developer menu.
- The in-run top strip is crowded: level, XP bar, stage and map, kills and alive count, the timer, gold, the pause button, six weapon slots and six passive slots with level badges and stage locks.
- Players meet Lines, Paths, Mutations, Evolutions and Perks. That may be too many named systems.
- The modal screens (level-up, path, chest, shop, the Stranger, stage clear) each look a little different. They could share one frame.
- The title's version label reads v0.4 (the game is at v0.27), and gold shows as a raw number (102682).
"""

SCREENS = [
    {"id": "01_title", "name": "Title", "when": "on launch, and after every run", "shots": [("06_title", "shots")],
     "job": "Start a run in one tap with the last hero and map, and reach everything else.",
     "on": ["Top left: total gold (a gold bar and 102682) and the best run (best 10:00 · L14).",
            "The 88fits wordmark in gold on navy, and the line DRAG · DODGE · SURVIVE.",
            "The chosen hero's round portrait badge on a flat band of desert brown.",
            "PLAY, a big gold button.",
            "A chip naming the hero and map: Drifter · Red Canyon · change ▸ (opens Play setup).",
            "Three buttons: The Mirror, Collection, Settings.",
            "Debug · Arena (a developer test room) and the version label, v0.4."],
     "keep": ["One tap to play with the last hero and map.", "A way to change hero and map.",
              "The Mirror, the Collection and Settings.", "Total gold."],
     "suspect": ["The lower half is flat bands of colour with a small badge; there is no sense of place.",
                 "The version label is wrong (v0.4) and Debug · Arena is open to players.",
                 "Gold is an unformatted number; the best-run chip is cryptic (L14 = level 14)."],
     "ask": ["Could the title carry the hero full-body in the desert, and let the player swipe heroes here instead of opening Play setup?"]},
    {"id": "02_play_setup", "name": "Play setup", "when": "from the title's hero chip", "shots": [("09_play_setup", "shots")],
     "job": "Choose a hero and a map, then go.",
     "on": ["Back and the title Play.",
            "Character: a card per hero with a round portrait, the name, the hero's trait in capitals (SPACE SUIT: +1 armor and +10% max HP. Every level-up patches the suit for 8% of her HP.), the favourite weapon and a flavour line. The chosen hero has a gold border.",
            "Map: one card, Red Canyon, with its flavour line and the best run on it (Best: 10:00 · level 14 · stage 2).",
            "GO, a big gold button. The lower half of the screen is empty.",
            "Two heroes can be played today; three more exist and are hidden for now. A locked hero would show its unlock quest."],
     "keep": ["Pick a hero, see what makes the hero different (the trait and the favourite weapon).", "Pick a map.", "Go."],
     "suspect": ["It reads like a settings form. The heroes are small badges beside a paragraph.",
                 "Half the screen is empty. The screen may not need to exist on its own (see the title)."],
     "ask": ["How would you show two heroes that play differently (armour and healing against speed and pickup range) at a glance?"]},
    {"id": "03_mirror", "name": "The Mirror", "when": "between runs, from the title and from the results", "shots": [("07_homestead", "shots"), ("mirror_bottom", "extra")],
     "job": "Spend gold on permanent talents between runs.",
     "on": ["Back, the title, and a line in gold: 106382 gold · 300 spent on the Mirror.",
            "Eight talent cards, one under another (Grit, Drive, Stride, Fortune, Choice, Nerve, Study, Spite). Each has the talent's name, three rank bars at the top right, a one-line subtitle (Thicker skin, or harder bones.), two form buttons with the chosen one in gold (Padding / Plate), the chosen form's effect (+10% max HP a rank.) and a button for the next rank (Rank 2 · 252 gold).",
            "Take it all back, at the bottom: empties the board and returns every coin."],
     "keep": ["All eight talents, each with its two forms, its three ranks and the price of the next rank.",
              "Switching form is free and keeps the ranks; the refund returns everything."],
     "suspect": ["Eight near-identical tall cards; the thing that matters (what a talent does) is the smallest text.",
                 "The rank bars read as a signal-strength icon.",
                 "It has no identity. The idea comes from the Mirror of Night in Hades: a mirror, a face in it, a gold frame could carry the screen."],
     "ask": ["Could the whole board fit on one screen without scrolling?"]},
    {"id": "04_collection", "name": "Collection", "when": "between runs, from the title", "shots": [("08_collection", "shots"), ("collection_hidden", "extra")],
     "job": "Everything in the game in one book: what each thing does, and how to unlock what is locked.",
     "on": ["One long list in sections: Weapons, Evolutions, Passives, Mutations (62 of them), Lines, Hero perks, Characters, Enemies.",
            "Each row: the icon in a frame, the name and the flavour line. A tap opens the row to show the generated description.",
            "Locked rows are dimmed and show their unlock quest; an unmet creature shows ??? and Not met yet.",
            "At the end, a separate part: Hidden · not in the game right now. Weapons, evolutions, mutations, creatures and heroes kept for later, marked HIDDEN in red (second screenshot).",
            "At the very bottom: N / M unlocks done · K kills all time."],
     "keep": ["Every item with its icon, name and description.", "How to unlock what is locked.", "The hidden part, kept apart from the rest."],
     "suspect": ["It is one scroll of more than 150 rows, with no tabs, filters or counts.",
                 "The rows show the flavour line, not what the item does.",
                 "The mutations swamp the list."],
     "ask": ["Tabs by kind, a grid of icons, per-weapon pages that hold the weapon's mutations and evolution?"]},
    {"id": "05_settings", "name": "Settings", "when": "from the title", "shots": [("10_settings", "shots"), ("settings_bottom", "extra")],
     "job": "Camera, controls, sound, hints, and wiping the save.",
     "on": ["Last run's last second: a line of debug output.",
            "Recent system pauses: six lines of debug output.",
            "Camera: Fixed · north up, or Follow · behind, with an explanation.",
            "Controls: an explanation of the joystick, then sliders for joystick size, screen shake, sound and music.",
            "First-play hints: ON, Show hints again next run, Debug panel: OFF.",
            "Wipe save (gold, unlocks, everything) in red, and the save file's path."],
     "keep": ["Camera mode, joystick size, screen shake, sound, music, hints, wipe save."],
     "suspect": ["It opens on debug output.", "Toggles are drawn as buttons whose label holds the state.",
                 "The slider labels and values are small."],
     "ask": []},
    {"id": "06_hud", "name": "In-run HUD", "when": "the whole run", "shots": [("01_play", "shots"), ("05_boss", "shots"), ("15_boss_arrow", "shots")],
     "job": "Show the run at a glance while the thumb steers: level, time, gold, the build, the boss, the hero's health.",
     "on": ["The top strip (250 px): LV 3 and the XP bar with STAGE 1 · RED CANYON; 106 kills · 6 alive; the big timer 01:01; gold with a coin; the round gold pause button.",
            "Under that, six weapon slots (square icons with level badges; slots that open in a later stage show a padlock and S2) and six passive slots (round).",
            "When a boss is up: its name and a long red bar under the strip, and its name again over it in the world. When it is off screen, a red chevron at the edge with the distance (BOSS 44 m); the portal gets a green one, the Elite an orange one.",
            "Toasts in the middle of the screen: +22 HP, Deadeye Lv 1, HOOKED!, SUPPLY DROP.",
            "Under the hero, his health bar and a blue shield bar. The joystick ring appears wherever the thumb lands.",
            "The world: violet XP gems, gold coins, red danger marks on the ground."],
     "keep": ["Level and XP, the timer, gold, pause, the build at a glance, the boss's health, the hero's health and shield."],
     "suspect": ["The strip carries more than twenty elements; the slots are small (about 60 px).",
                 "Text drawn over the world loses contrast on bright sand.",
                 "Toasts land in the middle of the action."],
     "ask": ["What would you take out of the strip altogether?"]},
    {"id": "07_levelup", "name": "Level-up cards", "when": "every level-up (every 20 to 40 seconds early in a run)", "shots": [("02_cards", "shots"), ("49_line_evolution", "shots")],
     "job": "Pick one of three or four upgrades, quickly, with the run paused.",
     "on": ["LEVEL 3! and pick one · game is paused.",
            "Three or four full-width cards. Each has the icon in a frame of its kind's colour; a kind tag (PASSIVE · NEW, WEAPON · UPGRADE, LINE · EVOLUTION OF ENERGY SHIELD); the name; a chip (NEW · LV 1, LV 3 → 4, EVOLVE); level pips; what it does (+25% pickup radius per level); and a flavour line.",
            "At the bottom: Reroll ×1, Skip +10 (skipping pays 10 gold), Banish ×1 (removes one card for the rest of the run). A small debug button (developer only).",
            "The second screenshot shows an evolved line card (Aegis) among ordinary ones."],
     "keep": ["Three or four choices with icon, name, what it does and how far along it is.", "Reroll, skip (pays gold) and banish, with how many are left."],
     "suspect": ["Each card is text-heavy; the kind tags are jargon.", "The lower half is empty and the three bottom buttons look alike."],
     "ask": ["How would you make the right pick obvious in under two seconds?"]},
    {"id": "08_path", "name": "Path offer", "when": "at set times in each stage, once per weapon", "shots": [("29_mutation", "shots")],
     "job": "Choose one of a weapon's three mutations. The two not chosen come back next stage; a weapon with two mutations can evolve at a chest.",
     "on": ["PATH · BOOMSTICK and one of these, the rest come back next stage · game is paused.",
            "Three magenta cards: MUTATION · BOOMSTICK · ELEMENT (or VOLUME, or MOTION), the name (Dragon's Breath), a PATH 1/3 chip, pips, the effect (Pellets ignite.) and a flavour line.",
            "Skip +10 and the debug button."],
     "keep": ["The three mutations with icon, name and effect.", "Skip."],
     "suspect": ["PATH · BOOMSTICK does not explain itself, and it looks almost the same as a level-up.",
                 "Element, volume and motion are our words, not the player's."],
     "ask": ["Should this feel like a bigger moment than a level-up?"]},
    {"id": "09_tap_to_continue", "name": "Tap to continue", "when": "after every pick and every chest", "shots": [("17_tap_to_continue", "shots")],
     "job": "Hold the pause until the player is ready, so a pick never drops them into a hit.",
     "on": ["TAP TO CONTINUE and the game is paused over the dimmed world, with a toast of what was taken (Chest: Boomstick Lv 5)."],
     "keep": ["The gate: play resumes only on a tap, and the tap can start the joystick."],
     "suspect": ["It is one more screen state between the pick and the play."],
     "ask": ["Could the chosen card fly to its slot on the strip while the gate waits?"]},
    {"id": "10_chest", "name": "Chest", "when": "opening a chest (from creatures, bosses and Elites)", "shots": [("13_chest", "shots")],
     "job": "The run's reward moment: a reel spins past the run's items for about four seconds and lands on one; take it or sell it.",
     "on": ["CHEST! and WEAPON · LV 4 → 5.",
            "One reel: the item's icon large in a gold frame between two arrows.",
            "The name (Boomstick), level pips and the next step (Next: +2 projectiles).",
            "Sell it · +5 gold, and Take it. A tap during the spin hurries it."],
     "keep": ["The spin, the item it lands on, take or sell."],
     "suspect": ["The best moment in a run looks like a form: a small reel, a busy world behind it, no build-up or payoff."],
     "ask": []},
    {"id": "11_shop", "name": "Travelling shop", "when": "stepping into the shop's ring on the map (once per shop)", "shots": [("12_shop", "shots")],
     "job": "Buy one of three items with the run's gold, or leave. Either way the stall is gone.",
     "on": ["TRAVELLING SHOP, a close button, and You have 0 gold.",
            "Three item cards like the level-up's, each ending in a price line (10 gold · not enough in red when short).",
            "Leave without buying."],
     "keep": ["Three items with price, what they do and whether the player can afford them.", "Leave."],
     "suspect": ["Three red not enough lines shout; the price is not a button.",
                 "The player cannot see what they already hold."],
     "ask": []},
    {"id": "12_stranger", "name": "The Stranger", "when": "stepping into the hooded figure's ring on the map", "shots": [("26_stranger_deal", "shots")],
     "job": "One strong item offered for a slice of max HP, for the rest of the run. Take it or walk away; he leaves either way.",
     "on": ["THE STRANGER and a quote: A piece of you, for a piece of the world.",
            "One offer card with the item's icon, name, level and effect.",
            "The price: 15% of your MAX HP, for the rest of this run. and No reroll. No second offer. He does not haggle.",
            "Walk away, and Deal. The hooded figure stands on the map behind."],
     "keep": ["The item, the price in max HP, deal or walk away."],
     "suspect": ["The Stranger is a speck in the background; the bargain has no drama.", "The price line competes with the item."],
     "ask": []},
    {"id": "13_pause", "name": "Pause", "when": "the pause button, or a tap on the top strip", "shots": [("03_pause_build", "shots"), ("04_pause_stats", "shots"), ("pause_options", "extra")],
     "job": "Stop the run; see the build and every number; change settings; give up.",
     "on": ["PAUSED with the time and stage; tabs Build, Stats, Options; a big Resume at the bottom.",
            "Build: a row per held item (icon, name, WEAPON · LV 3 / 8 and its path picks such as Watchtower · Bunker); a tap opens the live numbers.",
            "Stats: every stat with where it comes from (max HP 110: Base 100, Astro +10%), more than twenty of them.",
            "Options: camera, joystick size, screen shake, sound, music, reset first-play hints, the debug panel, and Abandon run in red."],
     "keep": ["Resume.", "The build with live numbers.", "The stats with their sources (for the players who want them).", "Sound, music, and abandoning the run."],
     "suspect": ["The Build rows do not say what each item does.", "Stats is a long table most players will never read.",
                 "Options repeats Settings."],
     "ask": []},
    {"id": "14_down", "name": "Down! (revive)", "when": "the hero's health reaches zero", "shots": [("21_revive", "shots")],
     "job": "A second chance: revive before the count runs out, or give up.",
     "on": ["DOWN! and get up before the count runs out · 1 chance left.",
            "A big count, 8, with a pause button beside it.",
            "THE LAST 30 SECONDS · newest first: a log of every hit (who, how much, what it did), with icons.",
            "Copy the log; Watch an ad · free revive (a stand-in: there are no ads yet); Revive · 150 gold (dimmed when short); Give up.",
            "A small dbg revive at the top right (developer only)."],
     "keep": ["The count.", "The ways to revive and their cost.", "Give up.", "What killed the hero (the full log is a test tool and can move to the developer menu)."],
     "suspect": ["The log fills the screen, and the count sits off to one side.", "A dramatic moment with a flat tone."],
     "ask": []},
    {"id": "15_stage_clear", "name": "Stage clear", "when": "after each stage's boss, stepping into the portal", "shots": [("portal_dialog", "extra")],
     "job": "The game's biggest decision: bank the gold now at ×1.25, or go on into a harder stage.",
     "on": ["STAGE 1 CLEAR in green.",
            "Extract now: bank 0 gold (×1.25 = 0). Continue: stage 2, harder waves, gold stays at ×1.0 until you extract or die.",
            "Extract (gold) and Continue to stage 2."],
     "keep": ["Both choices, with what each one means in gold."],
     "suspect": ["The core risk and reward of the game is told in two lines of small text instead of shown."],
     "ask": []},
    {"id": "16_results", "name": "Results", "when": "after a run ends (death, giving up or extracting)", "shots": [("results", "extra")],
     "job": "How the run went, what it earned, and the way into the next one.",
     "on": ["RUN OVER (or a win title after extracting) with Back.",
            "A table: time survived, stage reached, level, kills, gold collected, banked mid-run, extract bonus, chests opened, evolutions.",
            "Damage by weapon: a bar per weapon with its icon and share.",
            "When gold was earned, a line that gold is kept, and any unlocks.",
            "Play again (gold), The Mirror, Title."],
     "keep": ["Time, kills, level, gold earned, damage by weapon.", "Play again."],
     "suspect": ["It reads like a spreadsheet: no new best, no celebration, the hero is absent."],
     "ask": []},
    {"id": "17_debug_arena", "name": "Debug arena (developer only)", "when": "only for us: Debug · Arena on the title", "shots": [("57_arena_enemy", "shots")],
     "job": "A test room: the map and the hero with nothing coming unless we spawn it.",
     "on": ["A column of quick buttons on the right: ARENA, AGAIN, CLEAR, WAVES, LV +1, and a status line.",
            "A bottom sheet with tabs ENEMY, WAVES, ITEMS, HERO, DROPS, WORLD: grids of tiles to spawn creatures, set the clock, hand over items.",
            "Art variants: chips that spawn a creature with a candidate art, to compare in play."],
     "keep": ["All of it, for us."],
     "suspect": [],
     "ask": ["Low priority: no redesign needed. Flag anything from it that leaks into the player's screens, and suggest where one developer menu could live."]},
]


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
    parts = ["<!doctype html><html><head><meta charset='utf-8'><title>88fits UI redesign brief</title><style>" + PRINT_CSS + "</style></head><body>"]
    cover_shots = ["06_title", "02_cards", "01_play"]
    imgs = []
    for s in SCREENS:
        for k, (shot, _) in enumerate(s["shots"]):
            if shot in cover_shots and len(imgs) < 3:
                imgs.append("screens/%s_%d.jpg" % (s["id"], k + 1))
    parts.append("<section class='page cover'><div class='words'><div class='rule'></div><div class='name'>88fits</div>"
                 "<div class='sub'>UI redesign brief for Claude Design · 17 screens, 25 screenshots at 1080×1920</div>"
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
             ("Lines", section("lines")),
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
    rows = []
    shot_files = []
    for s in SCREENS:
        rows.append("| %s | %s | %s | %d |" % (s["id"].split("_")[0], s["name"], s["when"], len(s["shots"])))
        for k, (shot, src) in enumerate(s["shots"]):
            folder = SHOTS if src == "shots" else EXTRA
            im = Image.open(os.path.join(folder, shot + ".png")).convert("RGB")
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
              "screen with its screenshots beside its notes, in one file) and ask for the critique and the three visual directions it "
              "describes. Attach no design system: the look is open. `art/` holds the icons one by one, to attach any the mocks should "
              "use. The Markdown files, `screens/` and the two art sheets hold the same content for tools that want them apart.\n\n"
              "Made by tools/make_ui_review.py from the game's own screenshots (tools/screenshot_run.gd and tools/ui_shots.gd) and the "
              "content folders' icons.\n")
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

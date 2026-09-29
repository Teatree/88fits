# 88fits UI redesign: the brief

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
| 01 | Title | on launch, and after every run | 1 |
| 02 | Play setup | from the title's hero chip | 1 |
| 03 | The Mirror | between runs, from the title and from the results | 2 |
| 04 | Collection | between runs, from the title | 2 |
| 05 | Settings | from the title | 2 |
| 06 | In-run HUD | the whole run | 3 |
| 07 | Level-up cards | every level-up (every 20 to 40 seconds early in a run) | 2 |
| 08 | Path offer | at set times in each stage, once per weapon | 1 |
| 09 | Tap to continue | after every pick and every chest | 1 |
| 10 | Chest | opening a chest (from creatures, bosses and Elites) | 1 |
| 11 | Travelling shop | stepping into the shop's ring on the map (once per shop) | 1 |
| 12 | The Stranger | stepping into the hooded figure's ring on the map | 1 |
| 13 | Pause | the pause button, or a tap on the top strip | 3 |
| 14 | Down! (revive) | the hero's health reaches zero | 1 |
| 15 | Stage clear | after each stage's boss, stepping into the portal | 1 |
| 16 | Results | after a run ends (death, giving up or extracting) | 1 |
| 17 | Debug arena (developer only) | only for us: Debug · Arena on the title | 1 |

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

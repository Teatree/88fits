# Outlaw Survivors (88fits) UI review: the brief

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
| 01 | Title | on launch, and back from every hub screen and from Results | 3 |
| 02 | Hero drawer | the square left of the title's hero plaque | 1 |
| 03 | Hero sheet and looks | a tap on the title's hero plaque | 4 |
| 04 | Stages | PLAY on the title, once the map's first stage has been beaten | 2 |
| 05 | Upgrade board | the title's Upgrade button, or Results' Upgrade button | 3 |
| 06 | Collection | the title's Collection button | 4 |
| 07 | Settings | the title's Settings button | 2 |
| 08 | In-run HUD | the whole run | 6 |
| 09 | Wanted posters (the bounty) | the start of a run, right after the hero lands from the spawn beam | 3 |
| 10 | Level-up cards | every level-up | 2 |
| 11 | Mutation offer | at set times in each stage, in place of the next level-up's cards | 2 |
| 12 | Tap to go | after a level-up pick, a mutation pick or a chest | 1 |
| 13 | Chest | touching a chest (Elites, specials, bosses) | 3 |
| 14 | The shop | standing in the travelling shop's ring on the map (once a stall) | 1 |
| 15 | The Stranger | standing in the hooded figure's ring on the map | 1 |
| 16 | Spirit Pole (Totem gifts) | standing at one of the map's 10-12 Totem Poles | 1 |
| 17 | War Drum moment | using the War Drum on the map | 2 |
| 18 | Pause | a tap on the HUD's top strip or pause disc, or the app leaving the screen | 4 |
| 19 | Down! | the hero's health reaches zero | 1 |
| 20 | Stage clear (the portal) | walking into the portal after a stage's boss | 2 |
| 21 | Results | after any run ends (extract, staying down, abandoning, falling in Endless) | 4 |
| 22 | Play-data question and surveys | the first launch (over the title), and now and then after a run (over Results) | 2 |
| 23 | Developer menu and debug arena (testers only) | only for us: the developer menu (hold Settings' version line) and ARENA in debug mode | 2 |

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

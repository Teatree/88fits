# Wanted UI: what still differs from each PNG, and why

Pass 39, 2026-09-30. Each screen was rendered at 1080×1920 with `game/tools/wanted_shots.gd` (white behind the world, as the mocks were drawn) and set beside its PNG with `tools/wanted_compare.py`. Anything not listed below matches within a few pixels.

Most of what remains falls into three causes:

- **Data.** The mocks used sample numbers and hand-written lines. The game generates every line and number from the content folders. Examples: rarities, prices, stars, effect text, quest wording.
- **Rules.** A few mock lines describe rules the game does not have. These were left out rather than invented.
- **Capture timing.** The PNGs freeze some motion mid-flight. The captures show the resting frame.

## Screens

| # | Screen | Still differs | Why |
|---|---|---|---|
| 00 | Kit | Not a screen. Every component lives once in `game/ui/wanted/`, and no screen draws its own version. | — |
| 01 | Title (Drifter) | The **88fits** logo sits 3 px higher. | Godot's and Chrome's font metrics differ at 210 px. |
| | | Two dots, not three. | Only Astro and the Drifter are playable; Dad, Buck and Mira are hidden. Locked heroes ride the same carousel (pass 40): a flat dark silhouette with a padlock, a half-aged dot, the unlock requirement with a progress bar, PLAY reading LOCKED. The developer menu's "Hidden heroes as locked on the title" shows the look. |
| | | Astro comes first. | Heroes sort by id. |
| | | The world behind is our own desert still. | The mock's still never loaded in its own render, so white showed there. |
| 02 | Title (Astro) | Heal per level reads **5 %**, not 8 %. | `level_heal` is 0.05 in `astro.json`. Her `trait_text` still says 8 %, so **the data disagrees with itself** (pass 31 lowered the heal). One of the two needs changing. |
| | | Stats come in data order: HP, armour, heal. | Data order. |
| 03 | Mirror | Form names, texts and prices are the data's. Examples: "Reroll", "Skip Bonus", "Field Notes"; Choice costs 180; Omen's line wraps to two lines. | Data. |
| | | No locked talent. | No talent has an unlock quest. The locked card is built: aged, 55 %, the quest as a tag. |
| | | The mirror is drawn: brass ring, dark glass, two brass eyes looking out. | The talents hold for every hero, so no hero's face (pass 40). It is a slot waiting for `art/ui/wanted/mirror.png`. |
| 03b | Talent open | The board shows through the sepia dim. | The PNG draws the dim alone; the README calls it "a dim over the board". |
| | | The sheet is about 30 px taller. | Plate's text wraps to two lines (data). |
| | | The status line reads "+10% max HP", not "+10% HP". | The text generator's wording. |
| | | RANK 2's word, coin and price sit 14 px apart, not 16 and 10. | The button has one gap. |
| 04 | Collection | The board meets the tab strip. | The PNG leaves a 5 px gap, which looks like a slip; the README says the open tab opens into the board. |
| | | 19 weapons, of which 2 are locked. | Data. Captions are the quests' own words, such as "Kill 300 Armadillos". |
| | | Evolutions, paths and heroes are not tabs. | Evolutions and paths are on each weapon's page; heroes are on the title. |
| 04b | Weapon page | The description is generated and runs a line shorter. | Data. |
| | | "Best: Lv 8 · 14,208 damage in one run" became "39 kills with it, all time". | The save keeps no per-weapon best, and the brief says to keep the save format. |
| | | 7 level cells, not 8. | Boomstick has seven level-ups; the mock's aged "wider cone" cell has nothing behind it. |
| | | "−10% cooldown" wraps. | It is 2.6 px too wide for its cell. |
| | | The Evolution section sits about 45 px lower. | Slug's line runs to three lines. |
| 05 | Settings | Sliders use the settings' real ranges. Joystick size runs 0.6–1.4, so 100 sits mid-track. Shake runs 0–150 %, so 65 sits at 43 %. | Real ranges. |
| | | Version reads v0.28. | This build. |
| 06 | HUD | Slots, toasts and pointers show the capture's build. | Capture data. |
| | | The HUD hides under the full modals: cards, chest, shop, Stranger, pause, Down!, stage clear. The gate keeps it, as its PNG does. | The README asks for this on the chest; applied to all full modals. |
| 06b | HUD, boss + banner | The boss plate wears the **skull**, not the crown. | Since pass 33.3 the game gives bosses the skull and Elites the crown. |
| | | The evolved slot's tag reads 1. | An evolution restarts at level 1. |
| | | Evolved items are dark plates in a brass ring, not ember. | Pass 40: ember sat too close to brass on the phone, and evolved lines had no look of their own. |
| 06c | HUD, full build (no PNG) | A build that would shrink below 85 % on one row splits: weapons keep a row, passives and lines take a second; the tap-to-pause strip and everything under the slots move down. | Pass 40: at 62 % the plates crowded each other's level tags and spilled a stray row. |
| 07 | Level-up | Stars and lines come from data. No rarity seals anywhere since pass 43 (Garry: remove the indicator on every item). | Data. |
| 08 | Path offer | Each card shows the path's first sentence. | The README asks for "one effect line"; the PNG prints the whole text. |
| 09 | Gate | Captured at rest: the tag has landed and the slot wears brass. | The PNG freezes the tag mid-flight. The flight is built: 0.35 s, turns −8°, two streaks. |
| 10 | Chest | The reel's items and result come from the roll; Orbit Saws is common. | Data. |
| | | The glow is concentric rings. | The rules allow no blur. |
| 11 | Shop | Items, prices and "N short" come from the offer. | Data. |
| 12 | Stranger | Guillotine is rare with 3 levels, not epic with 5. Its line is generated. | Data. |
| | | The portrait is a striped slot. | Waiting for `stranger.png`. |
| 13 | Pause · Build | One-liners are generated, for example "Sends 3 seekers after enemies within 11 m". | The mock's lines were hand-written. |
| | | The open weapon's grid shows its own first three stats, for example turret lifetime. | Not always damage, cooldown and range. |
| 13b | Pause · Stats | Rows and sources are the real stat sheet's. | Data. |
| 13c | Pause · Options | Matches. | — |
| 14 | Down! | The killer line shows the skull for a boss. | Same as 06b. |
| 15 | Stage clear | Continue's lines come from the map's timeline: "+2 weapon slots open", "66 creatures at once, each ×2.2 as tough", "×1.0 gold, until you extract or die". | The mock's "×2 gold per pickup" and "Elites every minute" are not rules in the game. |
| 16 | Results | The unlock card is the quest the run finished; numbers are the run's. | Data. |
| 17 | Developer menu | No build number. | The game has none to show. |
| | | "Hidden items · 34". | Counts the data's hidden and retired items. |

## Placeholders

All painted (pass 42, Flux.2 dev at full steps, four seeds each, picked by eye, `tools/gen_ui_art.py`; the heroes in pass 40 with `tools/gen_title_heroes.py`):

- `hero_<id>.png`: the five heroes, full-body (Astro and the Drifter on the title; Dad, Buck and Mira as locked silhouettes)
- `stranger.png`: the hooded figure holding out a glowing offering (an edit of the Stranger's painting in the world)
- `strongbox.png`: an open strongbox heaped with gold (the Extract card), painted as an item icon (pass 43: the painted-scenery version read as a different art next to the icons)
- `portal.png`: a sandstone gate with the green vortex in it (the Continue card), an item icon likewise
- `mirror.png`: an ornate brass mirror, dark glass, two amber eyes looking out
- In the world, the portal a boss leaves behind is the same gate (`art/sprites/props/boss_portal.png`, a billboard like the scenery) with the swirl turning in its opening; the old green torus is only a fallback.

## Outside the mocks

These changes came with the rebuild:

- **Fonts.** Alfa Slab One, Bitter and JetBrains Mono are embedded with their OFL files.
- **Hints.** First-play hints use the toast slot: "Drag anywhere to walk", "She shoots by herself" (the hero's own pronoun, a new `pronoun` field in the hero JSON), and "The purple is XP". The level-up card carries the fourth.
- **Text generator.** The missile pod and the laser mouth have their own sentences now; before, Hornet Nest and Big Mouth showed only their names.
- **Save file.** No new keys, apart from three developer switches in the saved settings. Old saves load unchanged.
- **Analytics.** The game has none, so nothing to keep.
- **Touch check.** `touch_audit.gd` passes 695 of 695 controls at 1080×1920 and at the phone's shape.

## Pass 44 (2026-10-01)

- The Mirror is **Upgrade** on every button and title (the mock still says The Mirror); the title's Upgrade button is brass with a breathing glow and a mark when a rank can be bought.
- Results: "Main Menu" instead of "Title"; a death shows "Left in the sand" with the lost gold struck through and what the Strongbox banked (`16b-results-down`).
- Collection: tiles show only what has been met; a locked tile carries the quest's words and a progress bar and opens a requirement page (`04d-collection-locked-page`, `04e-collection-locked-tiles`). The mock had no such page.
- Level-up and chest: a sunburst, confetti and a stamped title on the reveal (`WCelebrate`), not in the mocks.
- The title's map line is empty until a run has been played, then shows the true best with kills.

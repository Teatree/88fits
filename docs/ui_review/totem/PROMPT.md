# The Totem Pole's gift screen: a redesign brief

**For:** Claude Design

**From:** the 88fits team (Garry designs and plays the game; Claude Code builds it)

**Attached:** 15 screenshots at the game's real size, 1080×1920 (`screens/`), all of them on one sheet (`00_overview.jpg`), the pole's painting and Garry's reference for the spirits' words (`art/`). Every file is described under "The pictures".

## What we are asking for

Garry, about the screen a Totem Pole opens: "Totem UI. It looks silly." Redesign it from the ground up, together with the pole's pieces in the world: the pieces that lead the player to a pole and tell him he has used it.

- **Today's screen is the thing under review.** It is here to be judged and replaced, not to set the style. Its colours, fonts, corner shapes, wooden planks, feathers, layout and the way it frames the painting are all open. Keep a thing only if you would have chosen it yourself.
- **Critique first, and be tough**, the way a senior UI and art lead for mobile games would.
- **Compare it with the genre**: how the best games handle the same moment (see "Compare it with the genre").
- **Then design three directions**, clearly different from each other and from today's screen, as mocks.
- **Strip it down.** If an element or a line of text does not earn its place, cut it or merge it, and tell us why.
- **Art counts as much as layout**: framing, materials, colour, type, icons, motion and sound cues are all part of it.

## The game in one minute

- 88fits is a portrait, one-thumb survivor shooter for Android phones, in the mould of Vampire Survivors, Megabonk and Survivor.io. The hero fires by himself; the player only steers, with a floating joystick that appears where the thumb lands, through a crowd that grows into the hundreds (`12_hud_in_play`).
- One map, Red Canyon: a sunlit, painted Western desert of sand, red rock, cacti, palms and an oasis. Heroes and creatures are anime-style painted cut-outs (cel shading, a thick dark outline) standing in a 3D desert under a high camera. Item icons are bold cel-shaded objects with a thick black outline.
- A run is three stages of about seven minutes, each ended by a boss, then an endless stretch. Every level-up pauses the run for a card pick (`13_sibling_level_up_cards`): weapons, fortune cards (run-long stat cards with four levels, for example The Chariot, +6% move speed a level), passive items and hero perks.
- Structures stand on the map, each with a ring on the sand to stand in: a travelling shop, the Stranger (a strong item for a slice of max HP, `14_sibling_the_stranger`), healing wells, a few others, and the Totem Poles. Wooden signposts point the way to them.
- Tone: short, dry frontier humour and Western names.

## What a Totem Pole is and how it works

Garry asked for them in October 2026: "Totem Poles scattered around the map. They have a smaller area that Player has to stand in to interact with them, but it takes just as much time to activate them. When activated a menu pops up offering Players a choice between 3 small stats improvements for that run." Each gift is titled with an animal's word from his reference picture, and "the size of the stat increase ranges quite a bit, with more common stats being more common than the others. Use thematical language and visuals for this menu, but also write the stats as simple numbers. The stat increases shouldn't be big, but not nothing. There are always between 10-12 of them on the map. Signs show to them as well. Visually they are a bit smaller than other Structures. When used they turn gray as well, but they don't get 'destroyed'."

How it works today:

1. **On the map.** 10 to 12 poles a run, spread over the map well apart from each other and from the other structures (about 14 m or more), never in the start clearing. A pole is a painted, camera-facing cut-out of a carved pole (a thunderbird with spread wings over four carved faces, a bear, a wolf and a frog among them), about three quarters of a typical structure's height (1.8 m against about 2.4 m). Its turquoise ring has about half the radius of the other structures' rings (1.2 m against 2.2 m) (`08_world_pole_and_signpost`).
2. **Signposts.** Four to six weathered signposts a map, each with one to four blank arms pointing at the nearest structures. A signpost points at one pole at most. The arms carry no words.
3. **Standing in the ring.** Standing in it for 3 seconds (as long as at the other structures) fills a pie on the sand; stepping out drains it (`09_world_standing_in_the_ring`).
4. **The screen.** When the pie is full the run pauses and the totem screen opens with three gifts (`01` to `07`). A tap on one takes it. There is no reroll, no skip and no way out without a pick.
5. **After the pick.** The screen closes at once and the run goes on: unlike the level-up, there is no "tap to go" gate, and the hero blinks invulnerable for a second. A toast names the gift ("EL-KOLIE, THE WHALE: +6 max HP", `10_world_after_the_pick`). The gift stays for the whole run. After the toast it shows only as a line in the pause screen's stat breakdown ("Totem: El-kolie").
6. **Used.** The pole turns grey and stays standing. Its ring is gone and it cannot be used again; the signpost arms that pointed at it go a shade paler (`11_world_used_pole_grey`).

**The gifts.** Eleven carved spirits, each titled with a word and its animal from Garry's reference (`art/garry_reference_the_words.jpg`, a labelled drawing of a carved pole). An offer draws three by weight, never two of one stat. The amount rolls anywhere in its range, and one to three feathers show which third of the range it landed in (three feathers: the top third). The numbers are small on purpose: a gift averages about 0.4 of one level of the fortune card for the same stat, so a whole map's poles add up to about one maxed card.

| Word | Animal | Gives | Range | Chance to be in an offer |
|---|---|---|---|---|
| Le-loo | the Wolf | move speed | +1% to +3% | 39% |
| El-kolie | the Whale | max HP | +2 to +6 | 39% |
| Chet-woot | the Bear | attack damage | +2% to +6% | 39% |
| Thunderbird | (none) | cooldown | −2% to −4% | 28% |
| Ol-hiyo | the Seal | pickup radius | +10% to +20% | 28% |
| Walalee | the Salmon | regen per second | +0.1 to +0.3 | 28% |
| Frog | (none) | XP gain | +2% to +4% | 28% |
| Skana | the Killer Whale | crit chance | +2% to +4% | 21% |
| Kuuma | the Bullhead | damage reduction | +1% to +3% | 21% |
| Raven | (none) | luck | +2% to +6% | 15% |
| Se-sook | the Two-headed Serpent | area of effect | +2% to +4% | 15% |

Each gift's line is generated from data as a plain number and the stat's name: "+2% move speed", "+5 max HP", "−4% cooldown", "+0.1 regen per second".

## Today's screen, the thing under review

`01`, `02` and `03` show three offers chosen to cover the range; `07` is an offer the game rolled by itself during play.

- A dark cedar-brown dim over the paused run.
- A header: "★ CARVED SPIRITS ★", then "THE TOTEM" in big slab capitals, then "Choose one gift. It stays with you all run." in italics.
- The pole's painting in the middle with a soft turquoise glow and a big feather drawn on either side.
- Three wooden planks low on the screen, in the thumb's reach. Each holds a paper disc with the amount ("+2%"), the spirit's word in slab capitals ("LE-LOO"), its animal in italics ("the Wolf"), the gift's line ("+2% move speed") and one to three feathers hanging at the right. A pressed plank darkens. As the screen opens, the painting and the planks slide up one after another.
- Today's fonts are Alfa Slab One and Bitter. The planks, the grain, the discs and the feathers are drawn in code.

**What we suspect** (confirm these, overrule them, and don't stop at them):

- Every plank says the amount twice (the disc and the line), while its biggest text is a word the player cannot read any meaning into ("CHET-WOOT"). What you actually get is the smallest line.
- The feathers rate the roll within that gift's own range, not the gift: three feathers on +2% luck are not better than one on +2% attack damage. Players may read them as rarity.
- The feathers beside the painting and on the planks are a Plains motif on a Pacific Northwest pole, and we suspect they are a big part of "silly". The pole is meant as a loose, respectful take on Northwest carving. Whatever replaces the feathers should treat the carved spirits with the same respect: as carved art, never as a costume or a joke.
- The painting is small and floats in the dim, so a third of the screen says little.
- Three equal brown boxes: nothing makes the moment feel like a gift from a spirit, and nothing makes one gift stand out from another.
- In the world the pole is small among the scenery and its ring is the only cue (`08`). Nothing tells the player how many poles are left or what he took from the earlier ones.
- After the pick the gift drops out of view: one toast, then a line deep in the pause screen.
- The screen comes 10 to 12 times a run for a small reward. It should read in a couple of seconds and let the player back into the fight; today it takes the whole screen with the weight of a level-up.

## What it must do (how is open)

- Offer three gifts. For each: the stat and its amount as a plain number, the spirit's word and its animal (three spirits have only a word), and how good the roll was (today's feathers or another way).
- Let one tap take a gift. Every target is thumb-sized and sits in the lower part of the screen, where the thumb rests.
- Open over the paused run, and hand the run back without dropping the player straight into a hit (today: a second of invulnerability).
- Fit the longest texts: "Se-sook, the Two-headed Serpent", "+0.1 regen per second", "+20% pickup radius", "Thunderbird".
- In the world: a pole the player can spot and tell apart from the scenery, its smaller ring and the 3-second stand, the used state (grey, standing, never destroyed) and the signposts that lead to it.
- If you think it needs a way out, a reroll, a picture for each spirit, a count of poles left, or a place where taken gifts stay in view, show it and say why.

## Compare it with the genre

Look at how these games handle the same moment (a small, run-long gift picked from a few, often at a spot on the map) and say what to take, adapted to a portrait, one-thumb phone game rather than copied:

- **Megabonk**: its charge shrines are the closest peer we know. You stand in a circle on the map until it charges, then pick one of a few stat boosts shown by rarity.
- **Vampire Survivors**: the fast level-up list, and the Arcana pick, where one big card changes the run.
- **Hades**: the boon pick, the classic "a god offers you one of three gifts": the giver's portrait, a rarity frame, one line of effect and one line of voice.
- **Archero (1 and 2)**: the angel and the devil between rooms (a heal or a stat; HP traded for a skill, our Stranger's cousin).
- **Brotato**: tiered item cards in its shop, and a stats panel people actually read.
- **Survivor.io**: chunky skill cards, levels shown as stars, big reward moments.
- Any other you think fits, such as Halls of Torment, 20 Minutes Till Dawn or HoloCure.

## The pictures

| File | What it shows |
|---|---|
| `00_overview.jpg` | All the screenshots below on one sheet. |
| `screens/01_totem_screen_offer_a.jpg` | Today's totem screen: Le-loo, the Wolf, +2% move speed (2 feathers); El-kolie, the Whale, +5 max HP (3); Chet-woot, the Bear, +2% attack damage (1). |
| `screens/02_totem_screen_offer_b.jpg` | The three spirits with no animal line: Thunderbird, −4% cooldown (3); Frog, +3% XP gain (2); Raven, +2% luck (1). |
| `screens/03_totem_screen_offer_c.jpg` | The longest words and a decimal: Se-sook, the Two-headed Serpent, +3% area of effect (2); Skana, the Killer Whale, +4% crit chance (3); Walalee, the Salmon, +0.1 regen per second (1). |
| `screens/04_totem_screen_offer_a_cutout.jpg`, `05_..._b_cutout.jpg`, `06_..._c_cutout.jpg` | The same three offers on a phone with a camera cutout: the top 130 px kept clear (the black dot marking the camera is drawn on for this brief). |
| `screens/07_totem_screen_rolled_in_play.jpg` | An offer the game rolled by itself when the hero stood in a pole's ring: El-kolie, +6 max HP (3); Kuuma, the Bullhead, +2% damage reduction (2); Frog, +2% XP gain (1). |
| `screens/08_world_pole_and_signpost.jpg` | The run as the player sees it (2:30, level 9): a pole and its ring on the red rock at the left, a signpost at the right whose arm points at it, the hero below. |
| `screens/09_world_standing_in_the_ring.jpg` | The hero standing in the pole's ring, the pie filling (the camera nearer than in play). |
| `screens/10_world_after_the_pick.jpg` | The run back on after a real tap: the toast "EL-KOLIE, THE WHALE: +6 max HP" and the pole already grey. |
| `screens/11_world_used_pole_grey.jpg` | The view of `08` after the pole was used: grey, without its ring, still standing. |
| `screens/12_hud_in_play.jpg` | The in-run HUD in a fight at 2:46: the XP bar, level, clock, gold, pause, the weapons at the left and the fortune cards at the right, and the floating joystick. |
| `screens/12b_hud_in_play_cutout.jpg` | The same with the camera cutout. |
| `screens/13_sibling_level_up_cards.jpg` | A sibling screen in the same run: the level-up card pick (a weapon, a fortune card and a passive item; reroll, skip and banish). |
| `screens/14_sibling_the_stranger.jpg` | A sibling screen in the same run: the Stranger's bargain, an item for a slice of max HP. |
| `art/totem_pole_painting.png` | The pole as the world and today's screen draw it (256 px). |
| `art/totem_pole_painting_used.png` | The grey of a used pole. |
| `art/totem_pole_painting_source.png` | The painting it was cut from (883×918). |
| `art/garry_reference_the_words.jpg` | Garry's reference for the spirits' words: a labelled drawing of a carved pole. |

## The art it has to sit with

- The pole's painting in its three files above. The pole's look followed a second reference "very loosely" (a black-and-white carved pole with spread wings); that one is a stock picture and is not attached.
- The 11 spirits have no pictures yet. Our art pipeline paints new art in the game's own style on request: the spirits as icons, carved faces or cards, frames, backgrounds, wood, feathers, or anything else a direction needs. Blender can model small 3D pieces, and new sounds are fine.
- The siblings (`12`, `13`, `14`) show today's in-run UI. They are context, not a style to follow: they may be redesigned too.

## Real technical limits

- A portrait canvas of 1080×1920 design px. Taller phones get extra height; the width stays 1080.
- A camera cutout at the top: on a notched phone the UI keeps the top 130 px clear (`04` to `06`, `12b`).
- Touch only, with one thumb: taps, no hover, no keyboard.
- Godot 4.7: every screen is built in code from a small kit (panels, nine-slice frames, painted images, text, shapes, shaders, tweens). Any open font works. Gradients, glows and animated effects through shaders are fine; a full-screen blur over the running 3D world is too costly on phones.
- The texts come from data, so their lengths vary (see the table of gifts).

## What to send back

1. **The critique** of today's screen and the pole's pieces in the world, the biggest problems first, one line each with why. Then a verdict for each piece: keep, rework, merge or cut. The pieces are the dim, the header, the painting, the planks, the disc, the word, the animal, the line and the feathers; the pole, its ring, the pie, the grey, the signposts and the toast.
2. **The genre comparison**: what the games above do better, and what to take.
3. **Three directions**, clearly different from each other and from today's screen. Mock each one at 1080×1920: the screen with three gifts, a gift pressed, the moment after the pick, the gift as a single piece at its three roll qualities, the pole in the world (fresh, being charged and used), how a player finds poles (signposts or anything better), and where taken gifts live afterwards, if anywhere.
4. **Your pick** and why. For it, give the sizes in px on the 1080×1920 canvas, the colours in hex, the fonts, the motion (open, press, close) with timings, and which pieces repeat.
5. **Your questions** for us, if any.

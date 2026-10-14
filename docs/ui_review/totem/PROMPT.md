# The Totem Pole's gift screen: a redesign brief

**For:** Claude Design

**From:** the 88fits team (Garry designs and plays the game; Claude Code builds it)

**Attached (2 pictures, the game's real size, 1080×1920):**
- `totem_screen.jpg`: today's gift screen, the thing to redesign.
- `totem_in_game.jpg`: the Totem Pole in the game, the hero standing in its ring while it charges.

## What we are asking for

Garry, about the screen a Totem Pole opens: "Totem UI. It looks silly." Redesign that screen from the ground up.

- **Today's screen is the thing under review**, not a style to follow. Its colours, fonts, corners, wooden planks, feathers and layout are all open. Keep a thing only if you would have chosen it yourself.
- **Critique it first, and be tough**, the way a senior UI and art lead for mobile games would.
- **Compare it with the genre**: how the best games handle the same moment.
- **Then design three directions**, clearly different from each other and from today's screen, as mocks.
- **Strip it down.** If an element or a line of text does not earn its place, cut it or merge it, and tell us why.

## The game in a few lines

- 88fits is a portrait, one-thumb survivor shooter for Android phones, in the mould of Vampire Survivors, Megabonk and Survivor.io. The hero fires by himself; the player only steers through a crowd that grows into the hundreds.
- One map: a sunlit, painted Western desert. Heroes and creatures are anime-style painted cut-outs with a thick dark outline; item icons are bold cel-shaded objects with a thick black outline. Tone: short, dry frontier humour.
- A run is three stages of about seven minutes, each ended by a boss. Every level-up pauses the run for a pick of cards (weapons, fortune cards, passive items).

## What a Totem Pole is and how it works

- **On the map**: 10 to 12 poles a run, well apart. A pole is a painted carved pole (a thunderbird with spread wings over carved faces), a bit smaller than the other structures, with a small turquoise ring on the sand (`totem_in_game.jpg`). Signposts point the way to them.
- **Charging**: the hero stands in the ring for 3 seconds; a pie fills on the sand; stepping out drains it.
- **The gift screen**: when the pie is full, the run pauses and the screen opens with **three gifts**. One tap takes one. There is no reroll, no skip and no way out without a pick.
- **After the pick**: the screen closes at once, the run goes on (the hero is safe for a second), a toast names the gift, and the gift lasts the whole run. The pole turns grey and stays standing; it cannot be used again.
- **The gifts** are small stat boosts, each from one of eleven carved spirits named in the words of Garry's reference (a word, and for most of them an animal). An offer draws three by weight, never two of one stat. The amount rolls within the gift's range; how high it rolled is shown (today with one to three feathers: the top third of the range is three feathers). The numbers are small on purpose: a whole map's poles add up to about one maxed fortune card.

| Word | Animal | Gives | Range |
|---|---|---|---|
| Le-loo | the Wolf | move speed | +1% to +3% |
| El-kolie | the Whale | max HP | +2 to +6 |
| Chet-woot | the Bear | attack damage | +2% to +6% |
| Thunderbird | (none) | cooldown | −2% to −4% |
| Ol-hiyo | the Seal | pickup radius | +10% to +20% |
| Walalee | the Salmon | regen per second | +0.1 to +0.3 |
| Frog | (none) | XP gain | +2% to +4% |
| Skana | the Killer Whale | crit chance | +2% to +4% |
| Kuuma | the Bullhead | damage reduction | +1% to +3% |
| Raven | (none) | luck | +2% to +6% |
| Se-sook | the Two-headed Serpent | area of effect | +2% to +4% |

## Today's screen, element by element (`totem_screen.jpg`)

| Element | What it is | What it does |
|---|---|---|
| The dim | A dark cedar-brown wash over the paused run | Pauses the fight behind and puts the focus on the choice |
| The eyebrow | "★ CARVED SPIRITS ★" in small spaced capitals | Names what is offering the gifts |
| The title | "THE TOTEM" in big slab capitals | Names the screen |
| The subline | "Choose one gift. It stays with you all run." in italics | The only instruction: pick one, it lasts the run |
| The painting | The pole's painting in the middle, a soft turquoise glow, a big feather drawn on each side | Shows who gives the gifts; pure decoration otherwise |
| The three planks | Three wooden boards low on the screen, in the thumb's reach | Each one is a gift and a button: a tap takes it |
| The disc (on a plank) | A paper disc with the amount ("+2%") | The gift's size at a glance |
| The word (on a plank) | The spirit's word in big slab capitals ("LE-LOO") | The gift's name, from Garry's reference |
| The animal (on a plank) | Its animal in italics ("the Wolf"); three spirits have none | Says which carved spirit it is |
| The line (on a plank) | The effect as a plain number and stat ("+2% move speed") | What the player actually gets |
| The feathers (on a plank) | One to three feathers at the right | How high the amount rolled within that gift's range |

As the screen opens, the painting and the planks slide up one after another; a pressed plank darkens.

**What must be on the screen** (how is open): three gifts; for each, the stat and its amount as a plain number, the spirit's word and its animal, and how good the roll was; one thumb-sized tap target per gift in the lower part of the screen; something that says these come from the totem. Everything else is optional. If you think it needs a way out, a reroll, a picture for each spirit, or a count of poles left, show it and say why.

**What we suspect** (confirm, overrule, and don't stop at these):
- Each plank says the amount twice (the disc and the line), while its biggest text is a word with no meaning to the player ("CHET-WOOT"). What you actually get is the smallest line.
- The feathers rate the roll inside that gift's own range, not the gift, so players may read them as rarity. They are also a Plains motif on a Pacific Northwest pole, likely a big part of "silly". Whatever replaces them should treat the carved spirits with respect: carved art, never a costume or a joke.
- The painting is small and floats in the dim, so a third of the screen says little.
- Three equal brown boxes: nothing makes it feel like a gift from a spirit, nothing makes one gift stand out.
- It comes 10 to 12 times a run for a small reward: it should read in a couple of seconds, yet it takes the whole screen with the weight of a level-up.

## Compare it with the genre

Say what to take from these, adapted to a portrait one-thumb phone game:
- **Megabonk**: its charge shrines are the closest peer (stand in a circle until it charges, then pick one of a few stat boosts shown by rarity).
- **Hades**: the boon pick (the giver's portrait, a rarity frame, one line of effect, one line of voice).
- **Vampire Survivors**: the fast level-up list.
- **Archero**: the angel between rooms.
- **Survivor.io** and **Brotato**: chunky reward cards and tiers.

## Real technical limits

- A portrait canvas of 1080×1920 design px; taller phones get extra height, the width stays 1080.
- A camera cutout on some phones: the top 130 px stay clear.
- Touch only, one thumb: taps, no hover, no keyboard.
- Godot 4.7: built in code from panels, nine-slice frames, painted images, text, shapes, shaders and tweens. Any open font works; glows and animated shader effects are fine; a full-screen blur over the running 3D world is too costly on phones.
- The texts come from data, so their lengths vary. The longest: "Se-sook, the Two-headed Serpent", "+0.1 regen per second", "+20% pickup radius".
- Our pipeline can paint new art in the game's style on request (the spirits as icons or carved faces, frames, wood, backgrounds).

## What to send back

1. **The critique**: the biggest problems first, one line each with why; then a verdict per element in the table above: keep, rework, merge or cut.
2. **The genre comparison**: what the games above do better, and what to take.
3. **Three directions**, each mocked at 1080×1920: the screen with three gifts, a gift pressed, and the gift as a single piece at its three roll qualities.
4. **Your pick** and why, with sizes in px on the 1080×1920 canvas, colours in hex, fonts, and the motion (open, press, close) with timings.
5. **Your questions** for us, if any.

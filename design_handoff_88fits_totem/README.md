# Handoff: 88fits Totem Pole gift screen — "The Spirit Pole" (direction 1b)

## Overview
Replaces the Totem Pole's gift screen (`reference/totem_screen_today.jpg`). The offer builds a pole: the thunderbird crest on top, the three offered spirits as carved segments stacked under it, a paper tag nailed beside each. Tapping a segment or its tag takes that gift. Same Wanted kit as the rest of the UI (paper, ink, brass; Alfa Slab One + Bitter; hard shadows, no blur).

## About the files
- `screens/01-totem-offer.png` — the screen, 1080×1920. The visual target.
- `screens/02-totem-offer-pressed.png` — the middle gift pressed (finger down, before release).
- `screens/03-gift-three-rolls.png` — one gift (Le-loo, the Wolf) at a low, middle and top roll, shown at half size.
- `design/88fits Totem.dc.html` — the design file (all three explored directions; **1b is the chosen one**). Open in a browser; every value is inline on the element. It is a reference, not code to port.
- `design/totem/` — art cut from today's screen: `crest.png` (thunderbird top of the pole), `pole.png` (whole pole), `face-wolf/bear/frog/seasnake.png` (96×96 letterboxed bands of the painted faces). **Low-res stand-ins** for painted spirit icons; use them only until the eleven carved faces are painted.
- `design/icons/` — low-res item icons used in the surrounding mocks; not needed for this screen.
- `reference/totem_in_game.jpg` — the pole in the world, hero charging in the ring.

## Fidelity
High. Colours, type, sizes, spacing, copy and motion are final. The four face crops are placeholders for painted art: the eleven spirits need carved-face icons (square, 256 px, thick dark outline, in the pole's paint style). Until then, spirits without a face show the plate empty with the word set in Alfa Slab One 40 centred.

## Canvas and safe area
1080×1920 design px; taller phones add height — this screen is **top-anchored** (label at y 300) so extra height goes below the base. Top 130 px: nothing on this screen sits there (first element at y 300). Touch only; every target is ≥ 240 px tall.

## Tokens
Colour: paper `#F3E6C8` · aged `#E2CFA4` · ink `#241B14` · ink soft `#5A4A3A` · brass `#C9932F` · brass dark `#A8792A` · rock `#B4472B` (segment plate) · turquoise `#3F8F8A` (press glow, in-world ring) · dim `rgba(48,30,14,.78)`.
Type: **Alfa Slab One** 400 for numbers; **Bitter** 400 / 600 / italic for everything else. Both Google Fonts (OFL).
Shape: no radius on tags; 10 px on segment plates, 6 px on the base; borders 5 px (tags) and 6 px (segments); hard ink shadow 8 px on tags, no blur; pressed = shadow 0 + translate.

## Layout (x, y from top-left of the 1080×1920 canvas)
- **Dim**: full screen `rgba(48,30,14,.78)` over the paused world. HUD hidden (as on level-up).
- **Label** "★ TOTEM 4 OF 11 ★": Bitter 600 30, tracking +35 %, `#F3E6C8`, left-aligned at (60, 300). Count = this pole's index / poles on the map (if the total is unknown at run start, use "★ 4TH TOTEM ★").
- **Crest**: thunderbird painting, 420 wide (aspect 360:108 → 126 tall), at (0, 372). Centred on the segment column (x 210).
- **Segments** (3): 300×300 at x 60; y **500, 840, 1180** (gap 40). Fill `#B4472B`, border 6 px `#241B14`, radius 10, inner carved shadow `inset 0 0 0 8px rgba(0,0,0,.18)`. Face icon 240×240 centred.
- **Tags** (3): 630×240 at x 390; y **530, 870, 1210** (30 below each segment's top, so vertically centred on it). Fill `#F3E6C8`, border 5 px ink, shadow 8 px ink, padding 0 30 0 40, content vertically centred, 10 px row gap:
  - **Effect line**: number Alfa Slab One 48 `#241B14` (`#A8792A` on a top-third roll) + stat Bitter 600 30 `#241B14`, same baseline, 14 px apart. e.g. "+2%" + "move speed"; "+5" + "max HP"; "+0.1" + "regen per second"; "−3%" + "cooldown".
  - **Spirit line**: Bitter italic 26 `#5A4A3A`: "Le-loo, the Wolf" (word, comma, animal). Word alone when the spirit has no animal: "Frog", "Raven", "Thunderbird".
  - **Gauge line**: range low end · 3 notches · range high end. Ends in Bitter 600 18 `#5A4A3A` ("+1%" … "+3%"); notches 56×18, border 3 px ink, 8 px apart; filled `#C9932F`, empty `#E2CFA4`.
  - **Nail**: 32 px brass circle, 4 px ink border, centred on the tag's left edge (x −19 from the tag), vertically centred.
- **Base**: 360×64 at (30, 1510). Fill `#B4472B`, border 6 px ink, radius 6, same inset shadow.
- Nothing else. No title, no subline, no buttons, no way out.

Longest texts fit at these sizes without shrinking: "Se-sook, the Two-headed Serpent" (italic 26 in 560 px), "+0.1 regen per second", "+20% pickup radius".

## The roll gauge
The roll's position inside **that gift's own range**, in thirds: 1, 2 or 3 notches filled. The ends are always written so a full gauge on speed never outranks an empty one on damage. On a top-third roll the number turns brass dark `#A8792A`. No feathers, no stars, no seal, no rarity colour: the gifts have no rarity and the screen must not invent one.

| Roll within range | Notches | Number colour |
|---|---|---|
| bottom third | ■ □ □ | `#241B14` |
| middle third | ■ ■ □ | `#241B14` |
| top third | ■ ■ ■ | `#A8792A` |

## States
- **Idle**: as `01-totem-offer.png`.
- **Pressed** (`02-totem-offer-pressed.png`): the pressed segment translates +14 px x and gains a glow `0 0 44px #3F8F8A` (shader glow is fine); its tag translates (8, 8), shadow to 0, 6 px `#C9932F` inner outline (inset 11 px); the other two gifts fade to 60 %. Release inside the segment or tag takes the gift; dragging out cancels (90 ms back). Taps elsewhere do nothing.
- **Spirit without painted art yet**: plate empty, the word in Alfa Slab One 40 `#F3E6C8` centred.

## Motion
- **Open · 460 ms**: pie completes → in-world ring flashes turquoise 120 ms → dim 0 → .78 over 160 ms. The crest drops in from y −80 to 372 over 220 ms (cubic ease-out). Segments rise into place from +60 px, 180 ms each, staggered 60 ms, top first; each tag slides in from +40 px x 40 ms after its segment, 160 ms. Base fades in last, 120 ms.
- **Press · 60 ms** to the pressed state; **release · 90 ms** back if cancelled.
- **Close · 420 ms**: the chosen segment's face lifts and flies to the toast slot (540, 300) over 300 ms ease-in-out, shrinking 240 → 72; the two other segments and tags drop out downwards 200 ms ease-in, the chosen tag fades 150 ms; crest and base fade 150 ms; dim lifts 150 ms. Toast "Le-loo · +2% move speed" with the face holds 1.2 s. Control returns at 300 ms; the hero is safe for 1 s as today. The in-world pole desaturates to grey over 400 ms and its ring fades.

## Data → UI
Per offered gift: `spirit.word`, `spirit.animal` (nullable), `stat.label`, `amount` (formatted with sign and unit: "+2%", "+5", "+0.1", "−3%"), `range.min`, `range.max` (formatted the same way), `rollThird` ∈ {1,2,3}, `spirit.icon`. Screen: `poleIndex`, `poleTotal` (nullable).

## Cut from today's screen, and why
Eyebrow and title: the crest and the label say "totem". Subline: a rule, taught by the first-play hint system, not here. The painting with two feathers: the pole is now the UI. The disc: the number moved into the effect line. Feathers: replaced by the range gauge. Wooden planks: replaced by the kit's paper tags. Added: the count, so eleven small gifts read as one accumulating thing.

# Handoff: 88fits UI — "Wanted"

## Overview
A full replacement of 88fits' in-game UI (17 screens, 22 states). Direction: **Wanted** — sun-bleached paper, ink outlines, brass, red rock. Menus are posters and plaques nailed onto the live desert; in-run modals dim the world to sepia. Every item lives on one plate shape; its *kind* is a plate colour plus one word, its *rarity* is a wax seal, its *level* is a row of stars.

## About the design files
`design/88fits Wanted.dc.html` is a **design reference built in HTML** — a prototype of the intended look, not production code. Open it in a browser (it needs the sibling `support.js`, `bg-run.png`, `icons/`). The task is to **recreate these screens in the game's existing UI system** (the engine's own UI nodes/widgets, sprites, fonts) using its established patterns. Do not port the HTML/CSS; read it for exact values.

`screens/*.png` are 1080×1920 renders of every screen state, one file per screen. Use them as the visual target.

## Fidelity
**High fidelity.** Colours, type, sizes, spacing and copy are final. Recreate pixel-close at 1080×1920, then let the layout stretch to other aspect ratios (see *Layout rules*). Three things are placeholders and marked as such in the mocks with striped dashed boxes: hero full-body cut-outs, the Stranger portrait, the strongbox / portal / chest art. Item icons are the existing 256 px icons (the mocks use low-res crops).

## Design tokens

### Colour
| token | hex | use |
|---|---|---|
| paper | `#F3E6C8` | panels, cards, buttons, HUD plates |
| aged | `#E2CFA4` | unselected tabs, locked cards, empty bar track, empty stars |
| ink | `#241B14` | every border, every hard shadow, body text, tabs' base line |
| ink soft | `#5A4A3A` | secondary text, italic lines, labels |
| brass | `#C9932F` | primary button, weapon plate, filled stars, rivets, coin, XP-free accents |
| brass dark | `#A8792A` | pressed primary, "WEAPON" label text, gold numbers |
| rock | `#B4472B` | line plate, danger button, boss HP fill, "the price" |
| sage | `#6E8B5E` | passive plate, health fill, positive stat numbers |
| turquoise | `#3F8F8A` | perk plate |
| ember | `#D9662A` | evolution plate, "EVOLVED" banner, elite pointer |
| plum | `#4A3358` | mutation plate, path chips |
| rare | `#3E6E9E` | wax seal, shield bar fill |
| epic | `#8A4FB0` | wax seal, XP bar fill |
| common | `#8A8F7A` | wax seal |
| toast green | `#7FE07F` | "+22 HP" toast |
| toast purple | `#B57BFF` | "+5 XP" toast |
| sepia dim | `rgba(48,30,14,.78)` | over the world behind in-run modals (Down!: `rgba(90,30,20,.82)`; Stranger: `rgba(30,18,26,.86)`; Chest: `rgba(48,30,14,.85)`; Gate: `.40`) |
| paper wash | `rgba(243,230,200,.82)` | over the world behind menus (Mirror, Collection, Settings, Results) |

### Type (both Google Fonts, OFL)
- **Alfa Slab One** 400 — every heading, number, button, card name, tab, stat value.
- **Bitter** 400 / 600 / 400-italic — effect text, notes, labels (600, letter-spacing +15 %, uppercase), italic flavour lines.
- Scale at 1080 wide: modal title 150 · hero numbers 110–300 · screen name 72 · card name 60 (56 on path/shop) · big button 84/72/60 · row name 36 · button 34 · effect text 30 · notes 26 · labels 20 · HUD gold/level 44 · HUD timer 72.
- **Nothing on the phone below 26 px** except the 20 px tracked labels and 22 px slot level tags.

### Shape
- Panels, cards, buttons, tabs: **no corner radius**.
- Icon plates: 10 px radius (12–14 on 150–200 px plates, 18 on the 260 px path hero, 24 on the 420 px chest hero).
- Circles: wax seals, hero portraits, pause button, the coin, the Down! countdown disc, the mirror.
- Borders: 4 px small (HUD plates, rows, slots) · 5 px cards and menu panels · 6 px hero panels and the big PLAY / RESUME.
- Shadow: **hard ink offset, no blur.** 5 px on HUD plates and small buttons · 6 px on kit cards · 8 px on level-up cards and bottom buttons · 10 px on hero panels and the primary CTA · 12 px on menu boards.
- Pressed: shadow → 0, translate by the shadow offset, background → brass dark (primary) or stays paper (secondary) with a 6 px brass inner outline on cards.
- Locked / can't afford: aged paper, no shadow, whole element at 45 % (60 % for shop cards so the price stays readable).
- Icon plate level tag: paper chip, 3 px ink border, Alfa Slab 22, at bottom-right overlapping by 10 px. Path rivets: 14 px brass circles at top-left.

### Spacing (1080 × 1920 canvas)
- Side margin 48 (36 for HUD plates and menu headers).
- Modal: star-line at y 110, title under it, italic line, content from y 470, button row bottom 90, button height ~110, gap 24.
- Menu: back square 96 × 96 at (36, 44); title 72 px slab beside it; gold plate top-right wherever gold can be spent; board from y ~190–200.
- HUD: XP rail 22 px ink at y 0 with a 14 px fill inset 4 px; LV plate at (36, 44); timer centred; gold plate right at 150 from edge; pause disc 88 px at right 36; item slots row at y 170 (weapons 96 px, passives/lines 80 px, gap 14, a 20 px gap between the groups); toast queue centred at y 300; boss bar at y 310 spanning 60–1020 when present.
- Thumb zone: in a run nothing interactive between y 700 and 1600.

## Components — build once, reuse
1. **Icon plate** — size · kind colour · optional level tag · optional path rivets · locked (aged plate, icon at brightness 0 / 30 % opacity).
2. **Wax seal** — 64–150 px circle, rarity colour, 3–6 px ink border, inset ring `inset 0 0 0 5px rgba(0,0,0,.15)`, Bitter 600 12–24 px tracked white label (COMMON / RARE / EPIC). Sits top-right of cards, top-right of collection tiles, top-right of the chest hero, on the weapon-page header.
3. **Item card** — paper, 5 px ink, hard shadow, brass rivet (32 px circle) centred on the top edge; plate left (150–170 px), text column: kind word (Bitter 600 20 tracked, in kind colour) · name (Alfa Slab 60) · stars (Alfa Slab 28: brass filled, paper-with-2px-ink-stroke = the star this pick gives, aged-with-stroke = empty) · one effect line (Bitter 30). Optional price button bottom-right (brass, coin, Alfa Slab 36). Variants: new / upgrade ("WEAPON · LV 5 → 6") / evolution (ember outline 6 px inset) / can't afford.
4. **Slab button** — primary (brass) · secondary (paper) · danger (rock with paper text) · pressed · locked. Alfa Slab 34–84, centred.
5. **Menu header**, **modal header** (star line + slab title + italic line).
6. **Tab strip** — selected tab paper, others aged with ink-soft text, 5 px borders, shared 5 px base line; the board below has no top border.
7. **Slider** — 26 px track (aged, 4 px ink), brass fill, 80 × 70 paper thumb with the value in Alfa Slab 28, thumb shadow 5 px.
8. **Switch** — 130 × 70, brass when on / aged when off, 50 px paper knob.
9. **Two-way choice** — one bordered strip split by a 5 px ink line; chosen half brass, other half paper with ink-soft text. Never a purchase.
10. **List row** — 96 px plate · name 36 · effect 24 ink-soft · stars or rivets · chevron. Open row: 4 px brass inner outline, a stat grid (aged, 4 px ink) and a path chip line below.
11. **Toast** — Alfa Slab 40, paper (or toast green / purple) with a 3 px ink stroke and a 3 px hard shadow; one at a time, 1.2 s each, under the timer.
12. **Banner** — replaces the whole HUD top row for 2 s; ink for "BOSS DOWN", ember with the weapon icon for "EVOLVED · NAME".
13. **Edge pointer** — paper tag with a 22 px triangle (rock = boss, sage = portal, ember = elite) and a distance; rides the screen edge, no border on the edge side.
14. **Bar** — 30–40 px track (aged, 4 px ink, hard shadow) with a flat fill; the boss bar has an ink name plate above it with the creature icon.
15. **Nine-slices for the engine**: paper panel (5 px ink + 8 px shadow), brass button, wax seal ring.

## Screens
Each PNG in `screens/` is the target. Exact copy is in the HTML. Per screen, what changed from today's build:

- **01 Title** — Play setup merged in. Gold plate top-left. "★ WANTED ★ / 88fits / DRAG · DODGE · SURVIVE" stack. Full-body hero (520 × 700) between two 72 px arrow squares, swipe or tap to change; three dots under it (third = locked hero). Hero plaque: name 56, italic line, 2–3 stat numbers (sage, Alfa Slab 34, tracked label under) and the starting/favourite weapon plate. PLAY 84 px brass. One line: "Red Canyon · best 10:00 · Lv 47 · stage 2". Three paper buttons: The Mirror · Collection · Settings. No version label, no debug entry.
- **02 Title swiped (Astro)** — same screen, second hero; stats +1 ARMOUR · +10% HP · 8% HEAL / LV · FAVOURITE plate.
- **03 The Mirror** — menu header with gold. Mirror portrait (300 px, brass frame) and "Something looks back. It wants gold." 2 × 4 talent board: name 44 · three rank notches (44 × 16) · form + effect line (Bitter 26) · price button (brass, coin, Alfa Slab 30). Eighth talent locked (aged, 55 %, "Reach stage 3 to unlock"). Footer link "Take it all back · refund 300".
- **03b Talent open** — sepia dim over the board; sheet: name 84 + notches, italic line, two-way choice (Padding / Plate, each with its effect), status line "Rank 1 owned · +10% HP" / "Switching form is free", RANK 2 · coin 252 brass 48, Close.
- **04 Collection** — header with "36 / 70 found". Tabs: Weapons 7/12 · Passives · Lines · Perks · Creatures. Board: 4-column grid of 200 px plates with names 24; found = brass plate with a 44 px seal; not found = aged plate, silhouette icon, unlock condition as the name ("Survive 8:00"). Footer "12,480 kills all time". Hidden items go to the developer menu.
- **04b Weapon page** — header: back · name 72 · seal. Hero card: 260 px plate, "WEAPON · 8 LEVELS", full description (Bitter 32), italic line, best stats. LEVELS: 4 × 2 grid of paper cells "2 +1 pellet" (level in brass slab 28). PATHS · TAKE ONE A STAGE: three plum-plate cards with name 30 and one line. EVOLUTION: aged card at 75 % with silhouette, name 44, "Not yet found. Open a chest with two paths taken."
- **05 Settings** — one screen, no scroll, no debug. CAMERA two-way choice (Fixed / Follow with a sub-line each). Sliders: Joystick size 100 · Screen shake 65 · Sound 80 · Music 0. Switch: First-play hints. Reset button for hints. Wipe row with a rock "Wipe" button ("asks twice"). Footer "88fits v0.27" — **hold 2 s opens the developer menu**.
- **06 HUD** — XP rail (epic purple fill) · LV 3 · 01:01 · coin 10 · pause disc. Slots: held items only — weapons 96 px brass plates with level tags and path rivets, then 80 px passive/line plates. Toast queue at y 300 ("+22 HP" green, previous toast fading at 60 %). Portal pointer on the right edge "PORTAL 80 m". Hero bars under the hero (health sage 14 px, shield rare 10 px). Joystick ring bottom-left, 300 px, 55 % ink ring, 110 px knob. No stage name, no kill/alive counters, no empty or locked slots.
- **06b HUD, boss + banner** — banner "EVOLVED · KILLER SWARM" (ember, hornet icon) replaces LV/timer/gold/pause for 2 s. Evolved weapon's plate turns ember. Boss: ink name plate with the crown icon + 30 px rock bar, y 310. Pointers "BOSS 43 m" (left, rock) and "ELITE" (right, ember). XP rail 61 %.
- **07 Level-up** — sepia dim. "★ WANTED ★ / LEVEL 3 / Pick one. The desert waits." Three item cards (Bristle RARE new line · Field Notes COMMON new passive, shown pressed · Boomstick EPIC LV 5 → 6). Bottom: REROLL ×1 · SKIP +10 · BANISH ×0 (locked). No debug button, no kind tag, no level chip, no flavour line.
- **08 Path offer** — "★ THE ROAD FORKS ★", the weapon plate 260 px, weapon name 96, path rivets "Path ○○○ · the two you leave come back next stage". Three MUTATION cards (plum plates, 160 px): Dragon's Breath · Birdshot · Slug, one effect line each. Single SKIP +10 centred. No Element / Volume / Motion words.
- **09 Gate ("tap to continue")** — not a screen. Dim drops to 40 %, the picked card shrinks and flies (rotating −8°) into its slot, which gains a brass border and a brass level tag; two motion streaks. "TAP TO GO" 64 px paper-with-ink-stroke at y 1500 with "Still paused. They'll wait." Any touch resumes and starts the joystick there.
- **10 Chest** — dim 85 %, brass light beam (trapezoid 700 wide at the base) from the top. "★ LOOT ★ / CHEST" (brass title). Reel: three plates, side ones 200 px at 45 % and 85 % scale, centre 420 px brass with a 14 px shadow and a 90 px brass glow, RARE seal 130 px at its top-right with a rarity glow. Result panel: "WEAPON · LV 3 → 4", name 84, stars 34, "Next: +15% orbit radius". Buttons SELL coin +4 (paper) · TAKE IT (brass 44, wider). Reel spins 4 s, tap to hurry. HUD hidden.
- **11 Shop** — "★ ONE VISIT ONLY ★ / THE SHOP" and the gold plate (56 px) under it. "YOU HOLD" row of 76 px plates. Three cards with price buttons bottom-right (brass); unaffordable card = aged, 60 %, price button paper with "· 8 short". Single LEAVE centred.
- **12 The Stranger** — plum-black dim 86 %. "★ NO NAME ★ / THE STRANGER". Portrait cut-out 840 × 660 holding the item. Quote line. Deal panel: item card (Guillotine, EPIC, "PASSIVE · STRAIGHT TO LV 2", stars ★★☆☆☆) + THE PRICE strip: label "THE PRICE · MAX HP FOR THE REST OF THE RUN" / "110 → 94", a 40 px bar with 85 % sage and the lost 15 % as rock/ink diagonal hatching, "No reroll. No second offer. He does not haggle." Buttons WALK AWAY (paper) · DEAL (brass 44, wider).
- **13 Pause · Build** — "PAUSED" 110 + "01:01 · Stage 1" plate. Tabs Build · Stats · Options. Board: one list row per held item (plate, name, one effect line, stars or rivets, chevron); one open row shows a 4-cell stat grid (damage · cooldown · range · this run) and path chips ("Watchtower", "Bunker" in plum) plus "one more and it can evolve". RESUME 60 px brass.
- **13b Pause · Stats** — Max HP opened as a breakdown card (Base 100 · Astro's suit +10% · Grit · Padding rank 1 +10% · Thirst rank 1 −6% in rock). 2-column list of the remaining stats, Alfa Slab values right-aligned, 2 px aged dividers. All on one screen.
- **13c Pause · Options** — Sound 80 · Music 0 sliders · Screen shake switch · divider · Abandon the run (rock button, "gold picked up so far is lost · asks twice"). Everything else lives in Settings.
- **14 Down!** — rock dim 82 %. "★ 1 CHANCE LEFT ★ / DOWN!" 170 px. Paper disc 520 px with the countdown 300 px and "get up". One line "[crown] The Tumbleweed King put you down." + "01:01 · 123 kills · Lv 3". Buttons: GET UP · WATCH AN AD (brass 44, full width) · GET UP coin 150 (locked, can't afford) · STAY DOWN (rock). No hit log, no dbg revive, no copy-log — those are in the developer menu.
- **15 Stage clear** — "BOSS DOWN" ink tag, "STAGE 1 CLEAR" 108, "05:00 · 412 kills · Lv 11. Bank it, or push your luck." Two tappable cards: **Extract** (SAFE · RUN ENDS, strongbox art 180 px, "This run's gold, at ×1.25", 312 struck → coin 390 in 96 px brass dark) · **Continue** (STAGE 2 · HARDER, portal art, "+2 weapon slots open", "×2 gold per pickup, kept at ×1.0", "240 creatures at once · Elites every minute", italic "Die out there and the 312 stays in the sand."). Footer "Tap a card. The portal stays open as long as you like."
- **16 Results** — paper wash. "★ EXTRACTED ★ / 10:00 (ink, 120) / Stage 2 · Lv 47 · 1,204 kills · 3 chests · 1 evolution". Hero panel: portrait 200 px, "Banked at ×1.25", coin +1,240 in 110 px brass dark counting up, "104,711 → 105,951", NEW BEST rock seal 150 px rotated 12° hanging off the top-right. DAMAGE BY WEAPON: four rows, 88 px plate (evolved one ember), 44 px bar with the name and number inside the fill, percentage right. UNLOCKED card (Orbit Saws, "survived 8:00"). PLAY AGAIN 72 brass; The Mirror · Title paper.
- **17 Developer menu** — ink background, JetBrains Mono. Rows: Arena › · Debug panel in run OFF · Debug buttons on modals OFF · Free revive button OFF · Hit log on Down! · copy OFF · Last run's last second › · Recent system pauses › · Hidden items · 14 › · Save file path. Entry: hold the version label in Settings for 2 s. The arena itself is unchanged.

## Interactions & motion
- Buttons: press = translate by the shadow offset, shadow to 0, 60 ms; release = back, 90 ms. Primary also darkens to brass dark.
- Cards: same press behaviour plus the 6 px brass inner outline while held; on confirm the card flies to its HUD slot over 350 ms (ease-in-out, scale 1 → 0.28, rotate 0 → −8°), the slot flashes its brass border for 400 ms, then the dim lifts from 78 % → 40 % over 300 ms and "TAP TO GO" fades in. Any touch resumes.
- Modal entry: dim 0 → 78 % over 200 ms; header stack drops 40 px with 250 ms ease-out; cards slide up 60 px staggered 60 ms each. Exit: reverse at 150 ms.
- Menus: paper wash fades in 200 ms; boards slide up 40 px.
- Toasts: appear at y 300, hold 1.2 s, fade 200 ms; queue, never stack more than two (second at 60 %).
- Banners: drop from y −120 to y 44 over 250 ms, hold 2 s, rise out; HUD top-row elements fade to 0 while the banner is up.
- Counters (gold on Results and Stage clear, the Down! countdown): count-up over 900 ms with an ease-out; digits use Alfa Slab tabular spacing.
- Chest reel: 4 s spin decelerating, items pass at 200 px scale 0.85 at 45 %, landing plate scales to 420 px with the glow; seal pops 0 → 1 with a small overshoot. Tap during the spin hurries to 0.6 s.
- Numbers: always thousands-separated; "L14" → "Lv 14"; timers mm:ss with no tenths outside the developer menu.

## State
- Title: `heroIndex`, `heroes[]` (locked flag + unlock text), `gold`, `best {time, level, stage}`.
- Mirror: `talents[8] {rank 0–3, form A|B, prices[3], locked}`; opening a talent is a modal over the board, `refundTotal`.
- Collection: `tab`, `found{}` with unlock text for missing entries, detail page per weapon (levels, paths, evolution).
- Settings: camera, joystick size, shake, sound, music, hints switch, version-hold timer (2 s) → developer menu.
- HUD: xp%, level, time, gold, held items (kind, level, rivets), toast queue, banner, boss {name, icon, hp%}, pointers [{kind, distance, edge}], hero bars.
- Pick modals (level-up / path / chest / shop / stranger): `offers[]`, `rerolls`, `banishes`, `skipGold`, `pressedIndex`, then `phase: picking | flying | gate`.
- Stage clear: two choices, extract multiplier ×1.25, next-stage summary.
- Results: run summary, banked gold, new best flag, damage by weapon, unlocks.

## Layout rules for other aspect ratios
Design at 1080 × 1920 and anchor: HUD top row and slots to the top edge; joystick and bottom button rows to the bottom edge; modal content centred vertically between the header (top-anchored) and the button row (bottom-anchored), with the card gap absorbing the slack (min gap 24, max 60). Side margins stay 48 at any width up to 1440; beyond that, centre a 1080 column. Never scale text below the sizes above.

## Assets
- `design/icons/*.png` — low-res crops of the existing 256 px item icons, for reference only; use the real icon files.
- `design/bg-run.png` — a still of the current arena used as the world behind the mocks; not an asset to ship.
- Fonts: Alfa Slab One and Bitter from Google Fonts (OFL); embed the TTFs.
- To paint: hero cut-outs 520 × 700 (Drifter, Astro, third hero), the Stranger 840 × 660, strongbox 180 × 180, portal 180 × 180, chest, the mirror frame 300 px.

## Files
- `design/88fits Wanted.dc.html` — the design (kit sheet, all 22 screen states, flow, build notes). Open in a browser; every value is inline on the element.
- `design/support.js`, `design/bg-run.png`, `design/icons/` — needed to render it.
- `screens/00-kit.png` — the component sheet.
- `screens/01-title.png` … `screens/17-developer-menu.png` — one 1080 × 1920 render per screen state.
- `PROMPT.md` — the prompt to paste into Claude Code.

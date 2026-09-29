# "Wanted" UI: implementation plan

Spec: `design_handoff_88fits_wanted/README.md` · targets: `design_handoff_88fits_wanted/screens/*.png` · exact values: `design/88fits Wanted.dc.html` (screens are authored at 1080×1920 inside the page, shown at half size).

## What is there today

- **UI framework:** Godot Control nodes built in code. `ui/UiKit.gd` holds the palette, the fonts and StyleBoxFlat factories; `UiFx.gd` the tweens; `TapCard`, `TouchSlider` and `TouchScroll` handle raw touch. Hub screens extend `ScreenBase` (their `.tscn` files only attach the script). In-run modals are CanvasLayer children that `game/Game.gd` creates (hud, cards, pause_screen, portal_dialog, structure_shop, chest_screen, revive_screen, stranger_screen, resume_gate, hints, debug_panel, arena_panel).
- **Fonts:** `ui/fonts/*.ttf` loaded by `UiKit.font()` / `font_head()` (Lilita One, Baloo 2).
- **Sprites and nine-slices:** none. Every box is a StyleBoxFlat; item art is each ContentDef's `icon` (`<id>_icon.png`, 256 px).
- **State:** `Run` (level, xp, gold, weapons/passives/lines/perks, rerolls/banishes/skips, stage, mutations), `Save` (gold, best, talents, unlocks, totals), `Settings` (camera_mode, stick_size, screen_shake, sfx/music volume, show_hints, debug_panel), `Registry` (defs), `Game` (the modals, the arena).
- There are no analytics events in the codebase.

## Approach

- A new kit in `game/ui/wanted/`: `W` (tokens, fonts, number formatting, label helpers), `HardBox` (a StyleBox: flat fill, ink border per side, hard offset shadow with no blur, optional corner radius, optional inner outline). HardBox stands in for the nine-slices: it is resolution-independent and draws exactly the listed borders and shadows. There is one class per component below.
- Every screen keeps its file, class name and public API, so Game.gd, the tools and the tests keep calling the same functions. The build code of each screen is rewritten on the new kit. `UiKit` stays for the debug arena (unchanged) and for world-effect colours.
- **Fonts:** AlfaSlabOne-Regular, Bitter[wght], Bitter-Italic[wght] and JetBrainsMono[wght] (all OFL, with their licences) go into `ui/fonts/`. None of them has a ★ glyph, so stars are drawn as shapes.
- **Menus:** the paper wash (82%) sits over a still of the desert (captured from the game, `art/ui/wanted/menu_backdrop.jpg`). The title's wash is its own gradient over the same still.

## Components (built once, in `game/ui/wanted/`)

| # | Component | Class | Used by |
|---|---|---|---|
| 1 | Icon plate (size, kind colour, level tag, path rivets, locked) | `WPlate` | HUD slots, cards, rows, collection, chest, results, title |
| 2 | Wax seal (rarity) | `WSeal` | cards, chest, collection, weapon page, results (NEW BEST) |
| 3 | Item card (new / upgrade / evolution / can't afford, price button, press state) | `WCard` | level-up, path, shop, Stranger |
| 4 | Slab button (primary, secondary, danger, pressed, locked) | `WButton` | everywhere |
| 5 | Menu header · modal header (star line, slab title, italic line) | `WMenuHeader` · `WModalHeader` | hub screens · in-run modals |
| 6 | Tab strip | `WTabs` | pause, collection |
| 7 | Slider with value thumb | `WSlider` (on TouchSlider) | settings, pause options |
| 8 | Switch | `WSwitch` | settings, pause options |
| 9 | Two-way choice | `WChoice` | settings camera, Mirror form |
| 10 | List row (closed, open with stat grid and path chips, locked) | `WRow` | pause build |
| 11 | Toast queue | `WToasts` | HUD |
| 12 | Banner | `WBanner` | HUD |
| 13 | Edge pointer | `WPointer` | HUD |
| 14 | Bar (plain, boss with name plate, hatched loss) | `WBar` | HUD, Stranger, results |
| 15 | Marks: stars, notches, rivets | `WMarks` | cards, rows, Mirror, path header |
| 16 | Coin and gold plate | `WCoin` · `W.gold_plate()` | HUD, title, menus, prices |
| 17 | Placeholder (stripes, dashed border, mono label; shows `art/ui/wanted/<slot>.png` when it exists) | `WPlaceholder` | title heroes, Stranger, strongbox, portal |

## Screens → files

| README | Screen | File(s) |
|---|---|---|
| 06, 06b | HUD, boss, banner, pointers, hero bars, joystick | `ui/HUD.gd` (rewritten build and draw; same API) |
| 07 | Level-up | `ui/CardScreen.gd` |
| 09 | Gate (tap to go) | `ui/ResumeGate.gd` (+ the card's flight to its HUD slot) |
| 08 | Path offer | `ui/CardScreen.gd` (path mode) |
| 10 | Chest | `ui/ChestScreen.gd` |
| 11 | Shop | `ui/StructureShop.gd` |
| 12 | The Stranger | `ui/StrangerScreen.gd` |
| 13, 13b, 13c | Pause: build, stats, options | `ui/PauseScreen.gd` |
| 14 | Down! | `ui/ReviveScreen.gd` |
| 15 | Stage clear | `ui/PortalDialog.gd` |
| 16 | Results | `ui/ResultsScreen.gd` |
| 01, 02 | Title with hero swipe (Play setup merged in) | `ui/TitleScreen.gd` (PlaySetup leaves the flow) |
| 03, 03b | The Mirror, talent sheet | `ui/HomesteadScreen.gd` |
| 04, 04b | Collection grid, weapon page | `ui/CollectionScreen.gd` |
| 05 | Settings (hold the version label 2 s → developer menu) | `ui/SettingsScreen.gd`, `core/autoload/Settings.gd` (new debug switches) |
| 17 | Developer menu | new `ui/DevMenu.gd` + `.tscn`; the arena (`ui/ArenaPanel.gd`) is unchanged |
| — | Shared menu shell | `ui/ScreenBase.gd` (menu header, paper wash, backdrop) |

## Merges and removals (from the README's flow)

- Play setup → the Title's hero swipe.
- Tap to continue → the gate: the dim lifts to 40%, the card flies to its slot, and "TAP TO GO" appears.
- Pause · Options keeps only sound, music, shake and abandon.
- One developer menu, opened by holding the Settings version label for 2 s, collects: the arena entry, the debug panel switch, the debug buttons on modals, the free revive button, the hit log and its copy button, the last run's last second, recent system pauses, the hidden collection items and the save path.
- HUD: the stage name, the kill and alive counters, and empty and locked slots all go.
- Cards: kind tags, level chips and flavour lines go.

## Verification

- `tools/wanted_shots.gd` renders every screen state at 1080×1920 with the mock's data, and `tools/wanted_compare.py` sets each render beside its PNG. The loop is: fix, re-render, move on.
- Then the parse check, the gdUnit tests (UI tests updated), the smoke run, the arena check and the touch audit (updated for the merged screens), then `tools/ship.sh`.

## Decisions

- Effect text stays generated from the game's data; the mock's hand-written lines are only the target format. A line reads "X a rank. Trade: Y." where the data separates the trade.
- In-run modals dim the live world. The mocks were rendered over a flat colour, so their backgrounds will differ.
- Rarity comes from each item's `rarity` (common, rare, epic).
- The first-run hints move into the toast slot ("drag anywhere to walk", "he shoots by himself", "the purple is XP"), and the first level-up says "the seal is how rare it is".

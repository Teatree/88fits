# The Level Editor (pass 53, pass 54)

A local tool page for the pacing and progression of a map's waves: which creatures appear when, how many, in what
bursts, with what numbers, and when the bosses, Elites and swarms come. It edits the `timeline_data` block of
`game/content/maps/<map>/<map>.json` (the schema is `docs/waves_schema.md`) on a calendar view, and Save writes the
JSON and runs the JSON -> .tres import so the next launch of the game plays it. Since pass 54 it writes one more thing,
and only when asked: a creature's default look (the top-level `variant` of its JSON), from the Creatures tab.

## Starting it

Double-click `tools\level_editor.cmd`. It finds Python 3 (`python`, else `py -3`), starts
`tools/level_editor/server.py` from the repo root and opens `http://127.0.0.1:8787/` in the default browser (the next
free port when 8787 is busy; the window says which). The window stays open while the editor runs; close it or press
Ctrl+C to stop. From a shell: `python tools/level_editor/server.py [--port 8787] [--no-browser]`.

Nothing is installed and nothing is fetched from the internet: Python's standard library serves one page of plain
HTML/CSS/JS (`tools/level_editor/`: `index.html`, `style.css`, `util.js`, `model.js` (the maths the game uses, no page
code), `fields.js` (every field, override, lane and help text in one table), `app.js`, `timeline.js`, `forms.js`,
`inspector.js`, `settings.js`, `creatures.js`, `instructions.js`). Chrome or Edge.

## The page

The top bar: the map selector, the map's name and file, the **Hero level** box (pass 54: the hero level the hover
cards, the readout and the curve tables assume; creatures gain `level_hp_per_level` of HP and `level_damage_per_level`
of damage for every level above 1; the browser remembers it, the map never sees it), **Undo / Redo**, **Revert** (back
to the saved file), **Export JSON** (download a copy), **Save** (Ctrl+S; disabled while nothing changed; red when an
error blocks it), the issue count, the zoom and the run clock under the mouse. Below it the status line: what Save did,
with the import's output a click away.

1. **Timeline**: the calendar. One time axis for the whole run (the stages as bands, mm:ss ticks, a skull per boss and
   a crown per Elite), lanes under it that scroll and zoom together:
   - **Cap**: the live cap curve. Its points are the **control points** of the curve (how many creatures may be
     alive): the line is linear between them and flat before the first and after the last. They are not spawn events;
     nothing spawns at a point. The director spawns up to the cap on its own interval (every `spawn_interval` seconds,
     a burst of `burst_min` to `burst_max` load units while there is room). Every point shows its cap as a faint label
     (pass 54), and its time on hover or while the lane is selected. Drag a point, double-click the line to add one,
     double-click a point to remove it. The hard cap is dashed, the hell channel's cap dotted, and each boss fight dips
     to `boss_cap_frac` of the cap.
   - **HP ×** and **ATK ×** (pass 54): the multiplier on every creature's health (`hp_curve`) and damage
     (`damage_curve`) over the run clock. A curve is either manual points (drag them, double-click the line to add one,
     double-click a point to remove it) or a formula (linear `1 + a·m`, power `(1 + a·m)^b`, exponential `(1 + a)^m`,
     m = minutes) drawn as the line, with its saved points faint. With no `hp_curve` the HP lane draws the legacy
     `hp_growth` / `hp_power` formula dashed; with no `damage_curve` the ATK lane is ×1. A double-click on a legacy line
     starts a curve of manual points taken from it at the stage marks. Click a lane for its inspector.
   - **Roster**: a bar per roster row from its start to its end (∞ = the run's end). Inside the bar the row's
     **presence keyframes** (pass 54, `weights`) are a filled area in the creature's colour; every row shares one weight
     scale (the hint above the rows says what a full bar is). Drag a point up or down for its weight and sideways for
     its time, double-click the bar to add a point where you clicked, double-click a point to remove it (a row keeps at
     least two). Keyframes outside the bar show as a faint dashed tail. The bar shows the look the game plays (the row's
     art variant, else the creature's in-play variant), the name, the weights ("w 3 → 5"), chips for the art variant,
     the pack and the pattern, a wrench when the row carries stat overrides, red for the hell channel. Drag the bar to
     move it (its keyframes travel with it), drag the right edge to end it, click to edit. "+ Row" adds one at the
     view's centre (weight 5 at two points half a stage apart). In the label column each row has a grip (drag it up or
     down), ▲ / ▼, its icon and name (a click selects it). The order is for this page only: the game draws by weight.
   - **Share** (pass 54): each creature's share of the draw over time, stacked, one colour per creature, normalised
     per channel (the regular crowd above, the hell channel below). The icons in the label column are the legend.
     Click it for a table of the shares at each stage's start and middle.
   - **Waves**: a block per wave with its name, its count / burst / every, its alternatives as coloured stripes with
     their share and icons, chips for "no cap", an elite modifier (crown), the hell channel, the pattern and the banner.
     Overlapping waves stack. "+ Wave" adds one with sensible defaults.
   - **Events**: a marker per event (skull boss, crown Elite, star coloured elite, a repeat glyph with a dotted trail for
     elite_every, a ring for a swarm), its label, whiskers for the jitter, faded under 100 % chance. "+ Event" picks a
     type.
   - **Specials**: the specials' band from its start with the pool's icons and the interval text.
   - **Paths**: a tick per path offer in each stage.

   **Hover cards** (pass 54): hovering a roster bar, a wave block, an alternative's stripe, an event flag, the specials
   band or the Share band shows a card for that second: the creature's picture, name and art variant, its **HP and
   ATK** as a creature spawned then would have them, an orange dot before a number an override changed, `*` after the
   pair when other stats are overridden (named on the next line), the factors (base × stage × time × level ×
   creature), the knockback, a coloured special's numbers when the creature has one, and the row's share of its
   channel's draw. Anywhere else a dashed cursor follows the mouse with the readout: the time, the stage, the cap, the
   HP and ATK multipliers and how they are made, the roster rows drawn then with their shares as bars, the waves running
   and the next event. Red "!" marks are errors, yellow ones warnings.

   The numbers are the game's (`EnemyManager.spawn`): an ordinary creature has HP = hp × the stage multiplier × the HP
   curve at that second × the hero-level factor × `creature_hp_mult`, and ATK = damage × the stage multiplier × the
   damage curve × the hero-level factor × `creature_damage_mult`. A row's overrides come first (`hp` / `damage` replace,
   `hp_mult` / `damage_mult` multiply). An Elite-archetype mini-boss has hp × `elite.hp_mult_per_stage`^stage × the
   stage multiplier × `creature_hp_mult` (no curve, no level); a boss hp × `boss.hp_mult_per_stage`^stage × the stage
   multiplier.

   The **inspector** on the right shows the form of whatever is selected: every field of the schema, typed (numbers
   with their range and step, the pattern, the channel, the event type), the creature's own numbers under the creature,
   and the **Overrides** section with the creature's own value as the grey placeholder of each box. Every creature, art
   variant, elite modifier and power-up choice is a **picture list** (pass 54): a button with the icon and the name; its
   list has 28 px icons, group headings (Creatures, Elites, Bosses, Specials, Retired, Hidden), a filter box (typing on
   the button filters too), ↑ / ↓, Enter and Esc. The icons are the looks the game plays. An empty art variant reads
   "in play: CODE": the look the creature's JSON plays.
   - A **roster row**: ▲ / ▼ in the header (and Alt+↑ / Alt+↓), the creature, from and until, the **Presence** points as
     a table (time, weight, the row's share of its channel at that time, × to remove, "+ point"), the channel, the
     pack, the pattern, the art variant, the overrides, then the row's weight and share at its start and one creature's
     HP and ATK then.
   - A **wave**: its fields and its alternatives as cards (chance, creature, variant, pack, overrides) with add, copy and
     remove. An **event**: its type's fields, the creature list with weights.
   - The **Cap** lane: the plain words about control points above, the points as numbers, the limits (hard cap, cap
     max, the boss fight's share, cap per stage, hell cap per stage, the older cap_start / cap_per_minute) and the cap at
     a few times.
   - The **HP ×** / **ATK ×** lanes: the mode (manual points or formula; switching to manual seeds the points from the
     formula at the stage marks so the line does not jump; both blocks stay in the file), the formula's kind and its a
     and b, the points table, "Re-seed from the formula", "Remove the curve", and what it makes at each stage's start and
     middle (curve × stage × level × creature multiplier = total).
   - The **Share** band: the table of shares.
   - The **Overrides** groups: Body (HP, damage, speed, size, radius, damage reduction, **Knockback (m/s)** and
     Knockback ×: pass 54, the grey number is the creature's `knockback`, or the game's default
     `clamp(3.4 × √(damage / 4), 2.5, 7)` from its damage when its JSON has none), Attacks, Ranged, Charge, Spawning
     (pack, max alive, cap share, XP ×, can be elite), Drops, Power-ups, **Elite** (pass 54: the variance block, that is
     the size and speed spread, the tints as colour swatches, the tint strength, and the coloured special's chance,
     size, HP, damage, XP, tint and tint strength; then **Elite weight**, how often a random coloured elite is drawn from
     this row, 0 = never; and **Comes alone / as its pack / as a ring**, three chances the sentence under them turns into
     shares), **Mini-boss (Elite archetype only)** (Elite HP × per stage, with a note when the creature is not an
     Elite-archetype one, since only those read it) and Boss (the attack script's attacks as checkboxes). A tint list
     that is not set shows the creature's own tints faded with "Edit a copy"; set, it is a swatch per tint with ×, "+"
     and "creature's own". A list set here replaces the creature's whole list.

   With nothing selected the inspector lists every issue; a click jumps to it.
2. **Settings**: every number of the timeline in a form with a one-line help each (the "?" unfolds it): stages, cap,
   spawning, portal, scaling, endless, items (weapon and line slots, the path offers per stage), the world, the power-up
   drops (per_kill, the roster with weight and hard bias), the specials. Pass 54: **Spawning** has the **Spawn sides**
   block (the mode, screen sides or the old facing rule; the four side weights round a little portrait screen whose
   edge bands are as thick as their shares, the percent under each; the facing share and spread, dimmed in sides mode;
   switching to sides with no weights starts from 55 / 15 / 15 / 15; "Remove the block" goes back to the facing rule),
   and **Scaling** has the HP × and ATK × curves (the inspector's form), `creature_hp_mult`, **`creature_damage_mult`**
   (multiplies every hostile damage), **`creature_speed_mult`** (pass 60: every creature, Elite and boss moves, winds up and
   shoots at this multiple; 0.9 on Red Canyon; the hero is not affected) and `hp_growth` / `hp_power` marked legacy (used only when `hp_curve` is absent).
   Keys the editor does not know are shown as they are and written back unchanged.
3. **Creatures**: the palette. A card per creature of `content/enemies` and `content/bosses`: the in-play look's icon,
   name, archetype / brain and the code it plays, HP / bite / speed / size, pack, cap share, XP, **knock** (its
   knockback in m/s, "(default)" when the game computes it), damage reduction, max alive, ranged, charge, attacks,
   drops, its tints and the special's colour as chips, the art variants as figures with the one in play ringed and
   dotted, badges for boss, elite, special, retired, hidden, never coloured and on the roster, the `doc` line, and
   "+ wave" / "+ roster row" buttons that start one with that creature. A filter box and "show retired and hidden" sit
   above. **Set as default look** (pass 54): click a figure that is not in play, then its button; the card asks "Make
   DM-A the default look of the Dust Mummy? ..." and "Yes, play DM-A" writes it (below), "Cancel" leaves everything as
   it was. A figure whose strip is not painted yet is faded and cannot be chosen. Every other creature number lives in
   the creature's own JSON. (Pass 58 made the default look an always-visible strip and added the blood colour: see
   "Pass 58" below.)
4. **Instructions**: what the editor is, "Pass 54: what is new", the model in one picture, every lane, field and
   override (generated from the same table the forms use), a worked example (Garry's "20 in bursts of 5 every 2 s, 50 %
   skeletons 10 hp 15 atk / 50 % goblins 15 hp 10 atk") with its block, its inspector values and the JSON it writes, how
   saving works, the .cmd files, the keys, and the schema doc from `docs/waves_schema.md`.

Keyboard: Ctrl+S save, Ctrl+Z / Ctrl+Y undo / redo, Delete removes the selection (a toast offers Undo), Ctrl+D
duplicates, ← / → nudge by 1 s (Shift: 10 s; a roster row's keyframes move with it), Alt+↑ / Alt+↓ move the selected
roster row, Esc deselects, + / − and Ctrl + wheel zoom, Fit shows the whole run.

## Old files (pass 54)

A roster row that still carries `weight` (and `weight_late`) is read as presence keyframes: `[[t, weight]]`, plus
`[max(weight_late_t, t + 1), weight_late]` when it slides, the game's own rule (`WaveDirector._roster_weight`; lane WD
converted Red Canyon the same way). Rows without an `id` get one (`r1`, `r2`, ..., unique in the file). The status line
says how many; the file on disk does not change until the next Save, which writes `weights` and `id` and drops `weight`
and `weight_late` from those rows. The timeline's own `weight_late_t` stays in the file untouched.

## Saving

Save runs the checks first. Errors block it: an unknown creature or art variant, a burst over the hard cap, `every` 0
with more than one burst to send, alternatives whose chances are all 0, an end before a start, an Elite event with no
creature, a cap point that is not `[seconds, cap]`; since pass 54 also a presence point that is not `[seconds, weight]`
or has a negative weight, a row id used twice, an HP or damage curve that is not `{mode, points, formula}`, has an
unknown mode or formula kind, or a negative multiplier, and `spawn_sides` with an unknown mode or a negative side
weight. Warnings never block: a wave with count 0 and no `until` (it runs forever), an event dated inside a boss fight
(the clock stands still, so it fires as the next stage starts), a boss away from a stage boundary, a hell row while
`hell_cap` is 0 everywhere, a path offer outside its stage, a cap curve out of time order; since pass 54 also a row
whose presence points are all 0 (it never spawns), presence or curve points out of time order, a curve in manual mode
with no points (×1 all run), and screen sides whose weights are all 0 (the game plays the facing rule). Save sorts
every point list into time order.

Then the server:
1. copies the file as it is to `tools/level_editor/backups/<map>-<yyyymmdd>-<hhmmss>.json` (the last 30 are kept; the
   folder is git-ignored);
2. writes `game/content/maps/<map>/<map>.json` pretty (indent 2, UTF-8, LF, a trailing newline), keeping every key the
   editor does not know, the file's own key order and whole numbers where the file had whole ones (`3.0` stays `3.0`),
   so a one-number change is a one-line diff; list items carrying an `id` (roster rows, waves) are matched by it, so a
   reordered row keeps its numbers as written;
3. runs `Godot --headless --path game --script res://tools/import_json.gd -- only=maps/<map>` (120 s timeout) and
   reports the result in the status line. The game plays the generated `<map>.tres`; without the import a saved JSON
   changes nothing in play. On a machine without `Godot_v4.7.2-stable_win64/` the JSON is saved and the line says the
   import must be run by hand.

The next launch from the editor binary (or the next ship) plays the new timeline. Commit the JSON (and the `.tres`
beside it). To go back, Revert in the page (before saving) or copy a backup over the JSON and import again.

## A creature's default look (pass 54)

"Yes, play CODE" on the Creatures tab posts `{"code": "CODE"}` to `/api/enemy/<id>/variant`. The server checks that the
game can play the code (the base strip's code, or a `variants` entry whose strip is on disk), copies the creature JSON
to `tools/level_editor/backups/<id>-<yyyymmdd>-<hhmmss>.json`, sets its top-level `variant` (in place, or just before
`variants` when the file had none) and writes the file back with its own key order, numbers, line endings and final
newline, so the diff is that one line; then it runs `import_json.gd -- only=enemies/<id>` (or `bosses/<id>`). The tab
reloads the creatures and rings the new look; every row, wave and event that names no art variant plays it from the
next launch. To undo it, set the old look the same way, or copy the backup back and import.

## The API (for scripts)

- `GET /api/maps`: `[{id, name, file}]`.
- `GET /api/map/<id>`: the map JSON as it is on disk.
- `POST /api/map/<id>`: the whole map JSON back; `{ok, wrote, backup, import_ok, output}`, or 400 with `{ok: false,
  error}` when the body is not that map.
- `GET /api/enemies`: a record per creature of `content/enemies` and `content/bosses` (the training dummies left out):
  `id, name, kind (enemy|boss), archetype, brain, hp, damage, speed, size, radius, pack_size, cap_share, max_alive,
  xp_mult, damage_reduction, contact_cd, drops, ranged, charge, kamikaze, artillery, boss {attacks, cooldown_between,
  hp_mult_per_stage}, elite, variance, knockback (null = the game's default), can_be_elite, hidden, retired, doc,
  flavour, variant (the JSON's), variant_base, play (the code the game really plays), variants [{code, note, icon,
  ready, base}], icon, icon_play`. Pass 54 added `variance`, `knockback`, `play`, `ready`, `base` and `icon_play`.
- `GET /api/elites`: `[{id, name, outline, icon}]`.
- `GET /api/pickups`: `[{id, name, small, weight, color, icon}]`.
- `GET /api/schema`: `docs/waves_schema.md` as text.
- `GET /api/status`: `{ok, root, godot, backups}`.
- `GET /icon/<kind>/<id>[/<code>]`: a PNG (kind enemy|boss|elite|pickup; code = an art variant: its own icon when the
  file is on disk, else the creature's, the game's order).
- `GET /api/turnover/<map>[/all]` (pass 57): the Spawned so far lane's assumptions fitted from `analytics/runs/*.json`:
  `{ok, map, source (records|fallback), runs, turnover, by_stage, curve, boss_seconds, portal_seconds}`.
- `POST /api/enemy/<id>/variant` (pass 54): body `{"code": "SK-B"}`; `{ok, id, kind, variant, was, wrote, backup,
  import_ok, output}`, or 400 with `{ok: false, error}` when the creature does not exist or the code is unknown or not
  painted yet (the error names the codes it can play). Pass 58: only that line of the file is written (see below).
- `POST /api/enemy/<id>/blood` (pass 58): body `{"color": "#8A1428"}`; `{ok, id, kind, blood, was, wrote, backup,
  import_ok, output}` (`unchanged: true` and nothing written when the creature already bleeds that colour, any case), or
  400 with `{ok: false, error}` when the creature does not exist or the colour is not `#rrggbb`.
- `GET /sprite/<kind>/<id>[/<code>]` (pass 58): a creature's animation strip PNG (kind enemy|boss; code = an art variant,
  the variant's own strip when it is on disk, else the top-level one). Cells are `frame_px` square; cell 0 is the standing
  idle frame the colour preview tints.
- `GET /api/enemies` (pass 58) adds `sprite_play` (the default look's strip), `frame_px`, `blood` (the JSON's, null when
  it has none) and a `sprite` URL on every variant.

## Self-test (pass 54)

`python tools/level_editor/selftest.py` (the standard library, plus Node.js for the first part): the page's maths
(`model.js`) against a Python copy of the game's formulas (point sampling, the three curve formulas, the old
`weight` / `weight_late` slide against the keyframes the page converts it to, row ids, a creature's HP and ATK), and
the server on temporary copies (the in-play icon, variance and knockback in a record, a reordered save keeping its
floats, "Set as default look" changing only its one line and refusing an unpainted or unknown code). It writes nothing
under `game/`. Pass 54: 13770 checks pass.

## The .cmd files

- `tools\level_editor.cmd`: starts the editor (above).
- `tools\ship.cmd`: runs `tools/ship.sh` through Git Bash with the arguments passed through (`--quick` skips the
  tests and the smoke run, `--no-install` leaves the phone alone). It looks for bash in `C:\Program Files\Git\bin`,
  then `C:\Program Files\Git\usr\bin`, then on PATH, and says clearly when none is found; it waits for a key at the end
  so the result can be read.

## Schema

`docs/waves_schema.md` is the contract: every key, every default, the pass-53 additions (waves, alternatives, stat
overrides, patterns, art variants, event names / chances / jitter / lists) and the pass-54 additions (presence
keyframes and row ids, the `variance` / `elite_weight` / `elite_formats` / `knockback` overrides, `creature_damage_mult`,
`hp_curve` / `damage_curve`, `spawn_sides`, a creature's `knockback`). The game side (`WaveDirector`, `WaveTimeline`,
`EnemyDef.with_overrides`) implements it; the editor writes exactly it.

## Pass 54

Garry's list for the editor (2026-10-06), and where each piece is:

- **Pictures in every creature choice**: the picture lists in the inspector and Settings (roster rows, wave
  alternatives, event creatures, the specials' pool, art variants, elite modifiers, power-ups). Every icon on the page
  is the look the game plays (nine creatures play a variant whose icon differs from the top-level one).
- **Cap points**: control points of the live cap curve, not spawn events (the Cap lane's help, its inspector, the
  Instructions); every point shows its cap.
- **Presence keyframes** replace `weight` / `weight_late`: points inside each roster bar, the Presence table, and the
  **Share** band under the Roster lane.
- **Elite overrides** are the variance block, the Elite weight and how a coloured elite arrives;
  `elite.hp_mult_per_stage` moved to Mini-boss.
- **Default look** from the Creatures tab (`POST /api/enemy/<id>/variant`).
- **Row order**: grip, ▲ / ▼, Alt+↑ / Alt+↓; stable row ids so Save keeps each row's numbers. Display only.
- **Hover cards** with HP and ATK at the hovered second, the override marks and the share; the **Hero level** box.
- **HP ×** and **ATK ×** lanes with the manual points / formula switch (`hp_curve`, `damage_curve`).
- **Spawn sides** (Settings → Spawning), **knockback** per creature (Body override, "knock" on the Creatures tab),
  **creature_damage_mult** (Settings → Scaling).
- Screenshots for the bible: `tools/dl/editor_shots/p54_timeline.png` (every lane), `p54_hover.png` (a roster card at
  hero level 10), `p54_curves.png` (the HP × inspector), `p54_roster_row.png` (a row selected: gutter, order buttons,
  presence points), `p54_creatures.png` (Set as default look asking to confirm), `p54_elite.png` (the Elite override
  group) and `p54_picker.png` (the creature picture list open).

## Pass 57

Garry's list for the editor (2026-10-07), and where each piece is:

- **Ring** and **In front** under Pattern (roster rows and waves; the swarm event takes In front, and keeps its own
  16 m ring). A ring puts the whole spawn evenly round the hero 11.7 m out (the debug arena's 9 m ring × 1.3, Garry:
  "about 30% further"): a row's pack, a wave's burst, all at once. A note under the field says how many make "a thick
  ring with few gaps" for that creature: one closed row shoulder to shoulder is 2π × 11.7 / (2 × radius × size), a
  thick ring about 1.5 times that, rounded to 5 (skeletons: about 105, 70 close one row), and what the row or wave
  spawns at once. In front puts every creature of the spawn at its own point 19–24 m up the screen within ±45° of
  straight up, whatever Settings → Spawning says (Garry: "basically an override to the Spawning part in the
  Settings"). `U.RING_RADIUS` in util.js mirrors `WaveDirector.RING_RADIUS`: change both together.
- **Spawned so far**, a lane under Cap: the cumulative number of creatures a run spawns by each second, an estimate
  (`model.js` `spawnEstimate`, a Python twin in selftest.py). It plays the director's rules second by second with
  expected values: the live cap and its curve, `boss_cap_frac` in the fights, `cap_share` load units, the presence
  keyframes, packs and patterns, `max_alive`, the hell channel, waves (alternatives by chance), swarms over the cap,
  Elites, specials, bosses, the portal wave and endless. A run only spawns what the hero kills, so it assumes the hero
  kills a share of the living crowd each second (the **kills** box, %/s) while the director refills to the cap, a boss
  fight of **boss** seconds and a portal wait of **portal** seconds. By default these come from Garry's own runs
  (`GET /api/turnover/<map>`: the latest 12 records in `analytics/runs/` from runs played from the editor binary;
  `/all` adds the headless tool runs), minute by minute where the records allow; with no records, 6 %/s, 60 s and
  30 s. Type a number to try another; clear the box to go back to the fit (kept per map in the browser). The lane is
  stacked: regular, coloured (the variance specials once `colour_after_kills` kills are made), Elites, specials,
  bosses, with a mark where each Elite, special and boss arrives and "+N in the fight" under each fight. Hover
  anywhere for a card with the time, the total, every creature by count (the coloured share of each), Elites,
  Specials, Bosses and the coloured total.
- Checked against a real run (`smoke_run.gd -- perf=1`, the astro bot, 2026-10-07): with the kill rate fitted minute
  by minute, the estimate was 4.4 % over the record at 2:00, 4.3 % at 4:00 and 8.2 % at 7:10 (19 % at 1:00, while
  the young build kills slowly). A flat rate is 95 % over at 1:00 and within 14 % after 2:00.
- `selftest.py`: 13832 checks pass (the estimate on seven timelines, JS against Python, and hand-checked cases).

## Pass 58

Garry's list for the editor (2026-10-07), and where each piece is. The game side is lane WV's (`docs/waves_schema.md`,
"Pass 58"); the editor shows exactly those rules.

- **A row keeps its numbers** (Garry: "I don't actually want it to change for the same 'wave' of enemies on the fly").
  A row reads the HP × and ATK × curves once, at its start `t0` (a roster row's `t`, a wave's `t`, an event's `t`; a
  special the second it comes): row HP = (its `hp`, else the creature's JSON hp × the HP curve at `t0`) × `hp_mult`, row
  ATK the same with `damage`, `damage_mult` and the damage curve. A row with its own `hp` / `damage` takes no curve. In the
  game the stage multiplier at the creature's spawn, `creature_hp_mult` / `creature_damage_mult` and the hero level at
  the row's first spawn (the Hero level box stands in for it) come on top; an Elite-archetype mini-boss and a boss keep
  their own rules. `model.js`: `rowNumbers`, `creatureAt(..., t0)`.
  - **The inspector**: a green line right under From / Until, in sight whether Overrides is open or not, says "Row HP
    39.01 · ATK 8, fixed from 8:46, the row's start", where each number comes from ("the Spit Cactus's 18 × the HP curve
    ×2.17 at 8:46", or "its own 25, typed in Overrides (no curve)") and what a creature of it has in play there ("In play
    at its start: HP 111.6 · ATK 22 (stage 2 ×2.2, creature ×1.3 / ×1.25, hero level 1 ×1 / ×1); one it sends in a
    later stage takes that stage's multiplier instead"). The grey numbers in Overrides → Body → HP and Damage are the
    same row HP and ATK. A wave shows the line under each creature (each alternative, the wave's start), an event under
    its creature (the second it fires); an "Elites every" lists its first four firings, each with the HP and ATK of its
    own second ("5:01 HP 16.46 · 7:10 HP 19.41 · ..."), since every firing takes the curves then. Pressing a bar selects
    it at once (a box still being typed in commits first, its own undo step), and while it is dragged the From / Until
    boxes, the title, the line, the grey numbers and the Presence times follow it (nothing else of the form is
    rebuilt). An Overrides block opened or closed by hand stays so when the form is drawn again.
  - **An event joins a row** (lane WV's fix round, `WaveDirector.event_numbers`): a swarm, a coloured elite (one named
    or drawn from the rows), a firing of an "Elites every", a special, a boss's brood or a boss / Elite event naming a
    regular creature, of a creature that a roster row of either channel (open then at a weight above 0, the heaviest when
    several) or else a wave in its window brings at that second in the same look (the same art variant; none, the
    default or an unknown code all mean the creature's own), plays that row's HP and ATK, fixed from the row's start, for
    each of the two its own Overrides leave alone (HP: `hp` / `hp_mult`; ATK: `damage` / `damage_mult`). The event's
    green line then reads "HP 55 · ATK 8, joining row r4 (the Fire Ant from 7:10)" (Red Canyon's 9:19 swarm; the 16:29
    imp swarm joins row r10), its grey HP and Damage show the row's numbers, its hover card says "Joins row r4", and an
    "Elites every" marks each firing that joins. `model.js`: `openSourceOf`, `eventNumbers`, `lookOf`.
  - **Endless** (the same fix round, `WaveDirector.source_for`): every row and wave fixes its numbers afresh at each
    endless wave N, from the later of its own start and the wave's start, stage_length × stages + (N - 1) ×
    endless_wave_seconds. The Actual lanes step there, the cards say "fixed afresh from 22:56, the start of this endless
    wave", and a row running into endless says so on its green line. `model.js`: `fixedFrom`.
  - **A long bar**: on a row or wave longer than three minutes whose HP curve has climbed more than 15% past its start
    by its last second (the run's end at most), the green line adds in yellow "By 21:30 the HP curve says ×4.11 while
    its creatures keep ×2.99 all the way: split the bar for a step up" (the review's suggestion; nothing blocks Save).
  - **The hover cards**: the factor line reads `time@3:12 1.41` and a line says the numbers are fixed from the row's
    start; a wave card says it for the wave. The cursor's readout says "a row starting now" and adds the actual line.
- **Actual HP ×** and **Actual ATK ×**: a lane above each curve, on the curve lane's scale while the rows' multiples
  fit under it; higher multiples give the Actual lane its own scale, up to 1.5 times as tall (`model.js` `actualScale`),
  and a ▲ with the number marks anything past its top, so the curve you drag never shrinks (one row with `hp` 200 over
  a creature's 10 had squashed it into the bottom fifth of its lane). At every
  second: the average of the multiples (row HP over the creature's JSON hp, row ATK over its damage) of the roster rows
  (both channels) and wave alternatives spawning in the 10 seconds round it, each weighted by what it spawns there (the
  Spawned so far estimate keeps a tally per row and per wave alternative, `src` on its points), drawn solid; the largest,
  dashed; the intended curve, dotted; nothing where none of the roster or the waves spawns. Hover for a card with the
  average, the largest and the intended, then every row behind them: its picture, name, row id or wave, start, multiple,
  why (the curve at its start, or its own HP) and its share of the spawns. The curve's inspector adds an "Intended and
  actual" table at the stage marks. During a drag the estimate is run again at most every 350 ms (it was the last one
  until the drop). `model.js`: `actualSources`, `actualAt`, `actualSeries`.
  - Red Canyon as Garry left it: the skeleton and knight rows (`hp` 20 and 35 over 10 and 15) carry ×2 and ×2.33 from
    3:12 where the curve says ×1.41; the fire ants (`hp` 55 over 36) ×1.53 from 7:10 where it says ×1.94; none of the
    roster spawns from 11:32 to 14:20; the imp and hellhound rows keep the ×2.99 of 14:20 to the end of stage 3 while the
    curve climbs to ×4.11 at 21:30, then each endless wave fixes them afresh (×4.11 from 21:30, ×4.35 from 22:56, ×4.58
    from 24:22, ...).
- **Size (m)** (Overrides → Body; R2, Garry: "editable as a kind of a range (between 3-5 for example) and there should be
  the default one already set for them so I have a reference"): a from and a to box. One number (or equal ones) writes a
  number, as before (the variance's spread on top, the radius unchanged); two write `[min, max]`: every creature of the
  row rolls its own size in the range instead of the spread, and its collision radius follows (radius × size / its own
  size) unless Radius is set. Under the boxes: the creature's own size and its spread ("its own: 1.75 m, spread ±20% =
  1.4–2.1 m"). A size of 0 or below, or a range that runs backwards, is an error (red boxes, Save blocked). The bar gets a
  "1.4–2.2 m" chip, the cards say it, and the Ring hint counts bodies at the middle of the range. A list of one size
  written by hand (`[2]`) is read as the game reads it (`EnemyDef.size_range_of`): a range of one size, every creature
  exactly 2 m, no spread, its radius following (the editor itself writes equal boxes as one number).
- **Colour** (a new override group; R3, Garry: "I'd like a colour slider and a preview showing the actual enemy"): "Add a
  colour range" writes `{"hue": [200, 260], "sat": 0.85, "val": 1, "amount": 0.5}`. The hue range is a strip of the
  colour wheel (0° to 360°) with a handle at each end (drag one, or press the strip to move the nearer one; an end below
  the start runs through red, the part left out is dimmed; ⇄ takes the other side of the wheel), the two hues in degrees,
  then Saturation, Brightness and Amount sliders, Clear, and the pictures, four to a row at about 90 px (a click shows
  one at 240 px): the row's look (its own art variant, else the default) as painted, then washed at five hues across
  the range, on the sand, then, for a creature with coloured specials, the special at the middle hue in its own shade:
  a coloured special of a colour-range row (once Colour after kills is reached) is a darker, stronger shade of the hue
  it rolled, saturation +0.15 (at most 1), brightness ×0.7, at the larger of Amount and the special's own tint strength
  (0.6 when it has none) +0.15 (at most 1) (`EnemyDef.tint_special_color`; `model.js` `tintSpecial`; a coloured-elite
  event or a wave wearing a modifier never rolls one, so it shows none). The pictures copy the billboard shader:
  `mix(rgb, tint, amount × 0.65)` on the painting in linear light with the tint's numbers as they are (`model.js`
  `tintPixel`; the game's Filmic tone mapping is left out), so a bright colour at a high amount looks pale in the game
  as it does here: lower the brightness for deep colours. A handle or a slider redraws the strip at once and the
  pictures once a frame; the file is written when it is let go (one undo step). The bar gets a swatch chip of the
  range; the cards show it. A hue outside 0–360 or a
  number outside 0–1 is an error.
- **Default look** (Garry: "I should be able to set the default Art Variant for those enemies from the Creatures tab").
  What was wrong with pass 54's button, seen in a browser: it was hidden (`display: none`) until a figure was hovered or
  clicked, and nothing on a card said it was there (the one hint was a grey line above the tab); on a card's first
  figure it stuck out past the card's edge, cut to "et as default look"; it took a click, the button and a confirm; and
  a row's look field said "in play: SL-C", which did not read as the default. The rows did follow it (a row that names
  no variant plays the JSON's), and every creature plays a look shown among its figures. The writer also re-dumped the
  whole file, which turned fire_ant's and the two red goblins' LF lines (they end in one CRLF) into CRLF throughout.
  Now every card has a **Default look** strip: its looks as 48 px pictures, the default ringed and tagged "default",
  every other painted look tagged "make default" (a click asks "Make SL-A the default look of the Blue Slime? ..." with
  "Yes, make SL-A the default" / "Cancel"), an unpainted one faded; a creature with one painting says so. The row's,
  alternative's and event's Art variant reads **Default (SL-C)** with its picture until one picks its own (which pins
  it; the list marks the default). New rows, waves and events still name none. The server writes only that one line
  (`set_top_key`: in place, or a new line before `variants`; parsed back and checked, else the old re-dump).
- **Blood** (R4): every card has a blood row: a splash in the colour, a colour picker and its hex. A change shows Save and
  ↺; Save posts `/api/enemy/<id>/blood`: a backup, the one `blood` line written in place (or a new line after `size`,
  where lane FX put every creature's, else after `knockback` or `damage`), in capitals like the files' other colours,
  every other byte as it was, then that creature's import; the card reloads with the new colour. A creature with none
  shows the game's default red (`#c70d0d`, "none set").
- `selftest.py`: 14038 checks pass: the above on top of pass 57's (R1 by hand and against the Python copy, the
  per-source tallies, the Actual average and largest on a hand-made timeline (three rows of one creature, a no-cap wave
  that keeps the crowd over the cap) and on Red Canyon, the size and colour checks, the tint mix, the records' strips and
  blood, the line writer on mixed line endings, the blood endpoint on temporary copies and over HTTP; after the review:
  the special's shade against `EnemyDef.tint_special_color` and its constants read from `EnemyDef.gd`, the variance
  special a row reads, the Actual lane's own top, an "Elites every" event's firings, the one-size list, and lane WV's
  fix round: the event join on sixteen hand-made cases (the heavier row, the look, a half the event sets itself, a row at
  weight 0, a wave and its alternative's share, endless, an Elite) and the endless re-fix, by hand and against the
  Python copy, in the Actual lanes too).

## Pass 60

- **Creature speed ×** (Settings → Scaling, `creature_speed_mult`): one multiplier for every creature's movement, wind-ups and
  hostile shots (Garry: "reduce the movement speed of all enemies by 10%" as a multiplier for all). The hero's own pace
  (`move_pace`) is separate. Red Canyon ships at 0.9.

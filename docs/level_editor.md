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
error blocks it), the issue count, the **Snap** toggle (pass 61, below), the zoom and the run clock under the mouse. Below
it the status line: what Save did, with the import's output a click away.

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
     `clamp(3.4 × √(damage / 4), 2.5, 7)` from its damage when its JSON has none; **Knockback resist**: pass 67, the
     other direction, the share of every shove from the hero's side the row's creatures shrug off, 0..1, the grey
     number the creature's own), Attacks, Ranged, Charge, Spawning
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
   knockback in m/s, "(default)" when the game computes it), damage reduction, **KB resist** (pass 67: the share of the
   hero's shoves it shrugs off, shown when it has one), max alive, ranged, charge, attacks,
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
roster row, Esc deselects, + / − and Ctrl + wheel zoom, Fit shows the whole run, S switches snapping on and off, and Alt
held while dragging places that drag freely (pass 61).

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
  xp_mult, damage_reduction, knockback_resist (pass 67; 0 when the JSON has none), contact_cd, drops, ranged, charge,
  kamikaze, artillery, boss {attacks, cooldown_between,
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

Pass 66 (the asset editors; `<kind>` is one of `enemy boss hero weapon evolution passive mutation`; every reply is
`{ok, ...}` or `{ok: false, error}` with 400/404/409 as noted; a content write edits the JSON line by line in place
(content_io.py), leaves a backup, and runs `import_json -- only=<type>/<id>` under the repo-wide Godot lock, or queues
an `import` job when the lock has been busy for 120 s):

- `GET /api/enemies` adds per record `looks` (the same records as `variants`), `sprite`, `anims`, `fps`, `strip_cols`,
  `head`, `badge`, `front_faces`, `back_faces`, `sfx`, `blocks`, `combo` ("brain|block+block"), `directions`, `file`,
  `mtime`, `deletable`. Every look record: `code, note, icon, sprite, ready, base, default, anims, fps, strip_cols,
  frame_px, head, front_faces, back_faces, shadow, shelved, fresh, imported (the PNG's .import exists and the .tres is
  newer than the JSON and the PNG; null = no PNG), sprite_mtime, sprite_file, icon_file, has_recipe, recipe`.
- `GET /api/heroes`: `[{id, name, flavour, order, pronoun, hidden, availability, price, currency_type, trait,
  trait_per_level, trait_name, trait_text, level_heal, favourite_*, start_weapon, specials, momentum, frame_px,
  strip_cols, fps, anims, sprite, icon, title (/art/wanted/hero_<id>.png or null), variant, variant_base, looks, perks,
  hero_mutations, weapons, file, mtime, deletable}]`, the five in play first by `order`.
- `GET /api/items`: `{weapons: [{...record, mutations (kind order, hero ones after), evolution, path, path_missing,
  locked_by}], lines: [{..., evolved}], passives, quests, band {locked, base, share, lo, hi}, orphans}`; every item's
  `availability` is derived: `hidden` -> hidden, a quest with `unlocks.id` -> locked, else available.
- `GET /api/content/<kind>/<id>`: `{kind, id, file, mtime, text, json, layout, editable, looks, refs {maps, quests,
  weapons, evolutions, mutations, characters, perks, passives}, availability, locked_by, quest, files, deletable,
  ledger, combos_seen, path_missing (weapons)}`; `GET .../next_codes?n=`: `{codes, base_created, prefix}`.
- `GET /api/templates/<kind>`: `[{id, kind, name, hidden, icon}]`, the retired and the dummies left out.
- `GET /api/vocab` (vocab.py: brains, blocks, attacks, telegraphs, stats, rarities with plate colours, behaviours,
  params keys, quest types, sound ids by prefix, elites, pickups, `combos_seen`; every list is listable, not extendable),
  `GET /api/methods` (`tools/level_editor/methods.json`, `{methods: []}` when missing), `GET /api/drivers`
  (`tools/dl/drivers/*/meta.json`: `{name, kind pose|depth, views, frames, loop, source, action, frames_url, frame_pattern,
  sheet, sheets}`), `GET /api/refs` (`tools/dl/uploads`: `{2d: [{name, url, path, size}], 3d: [{slug, file, probe,
  renders}]}`), `GET /api/status` (+ `blender`, `qa_online`, `locks`, `jobs`, `jobs_available`), `GET /api/schema/assets`
  (`docs/assets_schema.md`).
- `GET /icon/<kind>/<id>[/<code>]` for every kind above (+ `elite pickup quest perk`), `GET /sprite/hero/<id>[/<code>]`,
  `GET /art/wanted/hero_<id>.png`, `GET /dl/<rel>` (tools/dl under `jobs/ drivers/ ai_raw_anime/ ai_anim/ review/ icons*/
  title_heroes/ uploads/`, extensions png jpg jpeg webp gif json txt, a folder lists itself as JSON, `max-age=60`),
  `GET /examples/<name>.png`, `GET /sound/<id>` (a soundmap id's wav).
- `POST /api/content/<kind>`: `{id, template, name, flavour, doc (creatures), copy_art?, fields?}` -> `{id, kind, file,
  created, copied, job (a register job), job_error}`; 409 when the id exists under any content type. A creature gets its
  `knockback` written (EnemyDef's default from its damage); a hero starts `hidden` with `availability: "hidden"`, `price
  0`, `currency_type "gold"`; a weapon starts hidden with its three template mutations and template evolution (all hidden,
  `evolves_into` set); a passive starts available with its evolution links cleared. The id lands in the ledger
  `tools/dl/jobs/created.json` (local; only ledger ids can be deleted).
- `POST /api/content/<kind>/<id>/save`: `{json, base_mtime}` -> `{changed, removed, backup, import_ok, output, mtime}`;
  409 `{error: "changed on disk", mtime}` on a stale `base_mtime`; a key is removed only when the editor owns it; a file
  that cannot be edited line by line is refused (`error: "layout: ..."`), never re-dumped.
- `POST .../variant` `{code}` (creatures and heroes); `POST .../retire` `{retired}` (creatures; 409 `{refs}` when a map
  names it); `POST .../availability` (hero `{availability, price, currency_type}`, `hidden` kept in step; item
  `{availability: hidden|available|locked, quest?: {condition, quest_text, name}}` creates, edits or removes
  `content/quests/unlock_<id>`; a weapon turns available only when its path is complete: 409 `{missing}`);
  `POST .../delete` `{cascade?}` (ledger ids only, 403 otherwise; 409 `{refs}`; the folder moves to
  `backups/deleted/<id>/<stamp>/`); `POST /api/content/weapon/<id>/make_path` `{names?}` (the four templates, 409 when
  an id exists).
- `POST .../look` `{code?, note, recipe}` adds a stub entry (the first look of a file without variants writes
  `variant_base` and the base entry: creatures `<PREFIX>-0`, heroes `<PREFIX>-A`); `POST .../look/<code>` `{op:
  approve|shelve|unshelve|remove|note|recipe|default, ...}` and the bulk `POST .../look` `{op, codes}`; shelve and remove
  are refused for the look in play (409), remove also for the base code and a code a map pins (`{refs}`); a removed look's
  own PNGs, `.import` files and `_ai` marker move to `backups/deleted/<id>/<stamp>/`.
- `POST /api/upload` (the raw file; headers `X-Kind: 2d|3d`, `X-Filename`; streamed, 411 without Content-Length, 413 over
  200 MB) -> `{name, path, url (2d), slug, size, job (a ref_probe job for 3d)}`; `POST /api/test_launch` `{character?,
  look?, enemy?, variant?, count?, map?}` -> `{job}` (a launch job).
- The jobs (jobs.py; 503 `{ok: false}` while the module is not here): `GET /api/jobs[?since=<rev>]`, `GET /api/job/<id>`,
  `GET /api/jobs/specs`, `POST /api/jobs` `{kind, target, spec, title?}` -> `{job}`, `POST /api/jobs/<id>` (edit),
  `POST /api/jobs/<id>/cancel|requeue|pick|install|move|delete`; a bad body is a 400, an unknown job a 404, a state the
  call does not allow a 409.

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

## Pass 61: snapping

Garry (2026-10-08): "Add togglable snapping for Roster, Cap and anywhere else it makes sense for start and end, so when I
am placing an enemy wave or changing it's start or end time it snaps to Cap and other Enemy Waves (Cap prio)."

- **Snap on / Snap off**: a toggle at the left of the zoom buttons (the timeline's toolbar), or **S** on the keyboard (a
  toast says which). On by default; the browser remembers the choice (localStorage `88fits-editor-snap`), the map never
  sees it. Hold **Alt** while dragging to place that one drag freely; pressing or letting go of Alt in the middle of a
  drag switches at once, where the mouse stands.
- **What snaps** (the time only; a point's height never does): a roster row's bar moved whole (its start or its end,
  whichever finds the better target; its presence keyframes travel with it) and its end handle; a wave block moved whole
  (its start, or its end: `until`, or the last burst its count gives) and its end handle; an event flag; a presence
  keyframe; a cap point; an HP × / ATK × point (in manual-points mode). The specials band and the path ticks are not
  dragged on the timeline (Settings sets them), so they have nothing to snap. Typed numbers (the inspector, Settings), the
  ← / → nudges and points added by a double-click never snap: typing is exact.
- **What it snaps to**, within **8 screen pixels**: the range in seconds is 8 × the zoom's seconds per pixel, so it stays
  8 px at any zoom (about 11 s at Fit in a 1700 px window, 3.8 s at 0.47 s/px, 2 s at 0.25 s/px). When several targets
  are in range the first tier below wins, and within a tier the nearest:
  1. the **cap curve's control points** (Cap prio: a cap point in range beats everything below, even a nearer one);
  2. the other **roster rows'** starts and ends and the **waves'** starts and ends (an open row, or a wave with no `until`
     and no count, has no end to snap to);
  3. the **events** (bosses, Elites, coloured elites, Elites every, swarms) at their `t`;
  4. the **stage marks**: each stage's start and the run's end (the bosses usually sit there too, as events);
  5. last, only when nothing above is in range, **whole and half minutes**, from 4 px (half as far): half minutes while
     they are at least 36 px apart on screen (0.83 s/px or closer), whole minutes while those are (to 1.67 s/px), none
     farther out.

  The dragged item never snaps to itself: a row or a wave to neither of its own ends, an event to its own flag, a cap
  point to itself (another cap point at the same second is a target: it makes a step). A presence keyframe can snap to
  its own row's start and end. A handle's end stays at least a second past the start, and a bar moved whole never starts
  before 0:00: a target that would break either is passed over.
- **What you see** while the drag is held on a target: a thin line across every lane at the snapped second in the
  target's colour (cap points the cap curve's blue, rows pink, waves green, an event its flag's colour, the stage marks
  pale, the minutes grey); a tag above the mouse, "snapped to cap 6:03", "snapped to r16 start", "snapped to boss 7:10",
  "snapped to half minute 2:30"; the target ringed (a cap point white, a bar, block or flag outlined); and the clock line
  at the right of the toolbar ends "· snapped to cap 6:03" ("· its end snapped to ..." when a bar moved whole snapped by
  its end, since the clock shows its start). Let go and the line goes; Undo takes the drag back in one step, as before.
- **Saved as shown**: every target is a whole second (a wave whose count ends it between two seconds rounds to the nearer
  one; a cap point typed at 430.4 s is the target 430), so a snapped time is the whole number its box shows, written like
  any other time: one line in the diff.
- Code: `model.js` `SNAP_PX` 8, `SNAP_GRID_PX` 4, `SNAP_GRID_MIN_PX` 36, `SNAP_TIER` {cap 0, row 1, wave 1, event 2,
  stage 3, grid 4}, `snapTargets(tl, self)`, `snapGridStep(spp)`, `snapDrag(tl, edges, opts)` (no page code, checked under
  node). `timeline.js` builds the targets once when a drag starts (the dragged item's own left out), asks `snapDrag` on
  every move and draws the guide (`showSnap`, `.tl-snap`); the toggle is `#snap-toggle` (`Timeline.toggleSnap`,
  `Timeline.snapOn`).
- `selftest.py` `snap_checks`: the cap first (a cap point 3 s off over a row start 1 s off, still at 7.9 px, out at
  8.5 px), a row over a nearer event, an event over a stage mark, the nearest within a tier, the range at 0.25, 1, 2 and
  4 s per pixel, self left out (rows, waves, events, cap points), Alt and the toggle, an edge's lowest time, a bar moved by
  either end, the grid's spacing and its "only when nothing else" rule, and 500 random drags on a hand-made timeline and
  on Red Canyon (read from disk, never written) against a Python copy. 14994 checks pass.
- Checked in Chrome (Playwright) on Red Canyon without saving (a copy of the server with every write refused): the Bull
  Beetle row r15's end dragged to 6:06 at 0.47 s/px stops on the cap point at 6:03 although the Spit Cactus row r17
  starts nearer, at 6:08; dragged to 5:02 it stops on the Werewolf row r16's start at 5:00 rather than on the nearer
  Elites every at 5:01; with Snap off, or with Alt held, it stays at 6:06.

## Pass 66: the asset editors and the art jobs

Garry (2026-10-11): "It's time for me to start being able to create art assets for both Heroes, Enemies and Items on my
own ... I go to our LevelEditor HTML and I choose to either edit or create an Enemy, Hero or Item ... a 'form' or edit a
template of one ... Set the local AI model to generate some art assets for it ... previews for each of those ... a
`jobs queue` tab ... Make sure not to break any of the existing functionality of the LevelEditor." The design round
(three drafts, a synthesis, a critique) and the lanes' contract live in `tools/dl/p66/` (git-ignored); the keys it
adds to the content are in `docs/assets_schema.md`; the rules it adds to the game are BALANCING.md §13.

**The tabs.** `Timeline · Settings · Enemies · Heroes · Items · Jobs · Instructions`. Enemies is the Creatures tab
with an **Edit** on every card and a "**+ New from template**" dialog (template, name, id, flavour, a one-line doc, copy
the template's art); Heroes and Items are new, each a list pane (cards with status chips and a filter) and an editor
pane with a sticky header (`ENEMY · Test Beast · file · N changes · Save asset · Undo · Redo · Revert · Test in game ·
✕`), an issues line and collapsible sections. Every open asset is a document of its own: Ctrl+S, Ctrl+Z / Ctrl+Y and the
unsaved mark act on the document while one is open on the tab, and on the map otherwise; dirty documents stay open
while you switch ("Open documents (2) ▾"). The Timeline, Settings and Instructions tabs behave exactly as before.

**Creating.** The dialog writes the folder under `content/<type>/<id>/` at once (the template's numbers and art
words, its id, name, flavour and doc reset, the art keys dropped unless "copy the art", a creature's `knockback`
written out, a hero `hidden` with `availability: "hidden"`, a line or passive item available, a weapon hidden with its
three template path mutations and its template evolution, all hidden) and queues a **register** job: the placeholder
icon and strip (`gen_placeholders.gd -- only=`), `--import`, `lossy_imports.py`, `--import` again, `import_json`. The
id goes into a local ledger (`tools/dl/jobs/created.json`), the only ids **Delete** accepts (the folder moves to
`tools/level_editor/backups/deleted/`).

**Saving an asset.** Save asset posts the whole document with the file's modification time; a file changed on disk
meanwhile answers 409 ("Reload", "Keep mine", "Show the other"). The server writes only the keys that changed, each
on its own line in place (`content_io.set_top_block`, the pass-58 one-line writer grown to any value: a multi-line
block is rewritten with the file's own indent unit and parsed back), never removes a key it does not own, keeps `1.0`
as `1.0`, backs the file up, and refuses with "layout" when a file cannot be edited line by line (it never re-dumps on
its own); then `import_json` runs for that one folder under the repo-wide Godot lock (`tools/locks.py`,
`tools/dl/locks/godot.lock`), or an **import** job is queued when the lock is busy.

**The forms** (`assets_fields.js`, in fields.js's row vocabulary): an enemy / elite / boss form of 93 rows in 8
sections (identity, body, brain and its blocks, the attack script, spawning, drops, variance, sounds, looks, art
words), a hero form of 69 (identity, the trait with the sentence the game will show and "Set trait_text from the
rule", favourites, specials, availability / price / currency_type written but not wired, art words with driver
pickers, "His own": his weapon, hero mutation and perks), a weapon form of 51 (behaviour, targeting, base stats with
the game's defaults as placeholders, exactly five level steps, evolution and the path strip with "Create templates",
params as JSON with the behaviour's known keys as chips, sounds, availability with the unlock quest drawer, the
quest-locked band gauge), lines and passive items, mutations and evolutions. 124 rules (76 errors that block Save, 48
warnings) are the shape rules the tests hold (a doc line, a valid blood, knockback above zero, five levels, the three
path kinds, a hero's perks and mutation). Any brain and attack-block combination is allowed; one no creature in play
uses reads "untested in play". A boss's or Elite's script is a list of attack cards: the name picks that attack's keys,
a telegraph picture to scale (line, ring, ring at the hero, sector, fan, spokes with the game's own numbers), a
sequence line (wind-up, active, the gap between) and the pacing note (wind-ups last 1 / (move_pace ×
creature_speed_mult), ×1.23 on Red Canyon). Every select of the game's constants says "a new kind needs code: ask
Claude": the lists are listable, not extendable.

**Compare with** (enemies): the template or any creature against this one, with Δ%: HP, bite, speed, XP, knockback,
KB resist (pass 67), size, radius, pack; HP at 0:00, 5:00 and 12:00 after the chosen map's stage and curve multipliers; seconds to kill with
a level-1 Revolver; bites to kill the hero; the ring hint.

**Looks and previews.** Every creature and hero form has a **Looks** grid (24 a page, filters all / playable / new /
shelved / not painted / not imported, bulk Shelve / Remove) with a **strip player** per look: the animation (idle, run,
attack, hit, die, cheer) and the facing (2 or 8 directions, mirrored as the game mirrors), play / pause / step, speed,
zoom 1×, 2×, 4× and a full-size modal, on the sand at about 94 px/m with a 1 m bar ("approximate scale"). At most 12
players animate at once (the rest hold frame 0 and say so), only visible ones tick, hover-to-play in grids, decoded
strips kept in a cache of 16. Per look: Make default, Approve (clears `fresh`), Shelve (`shelved: true` hides it from
the arena's chips and the lists, a row naming it still plays it), Remove (the PNGs to `backups/deleted/`), Edit note /
recipe (raw JSON), Recipe (typed) (every field of the method with its source: own, inherited from the creature's own
art words, or the method's default; a look with no recipe recorded says so; keys the form has no row for are listed),
Re-roll, Duplicate (a new look from this one's recipe, words and painter under the next free code; "reuse the
paintings" redoes only the clips), Icon candidates. Each card names its method, how many keys its recipe holds of its
own and the painter it ran with (`variants[CODE].recipe.painter`, written by every look job; Re-roll and Duplicate
start from it; gen_art reads it on a hand run that names none). The editor pane's sticky header carries the look's
icon and the name, so the asset being edited stays in view while the pane scrolls. Icons preview at 128 / 64 / 36 on the rarity plate; a hero's title cut-out at a
quarter with a 1:1 view.

**Art jobs.** "+ Generate art" opens the job form: a card per method from `tools/level_editor/methods.json` (17: the
hero's five views on a Mixamo stride, a hero walk fitted to this painting, a creature front and back on free Wan clips
or on a Mixamo stride, eight directions on free clips, a creature walked on a 3D model's own motion, no video at all, a
front from a picture, a recolour, item icons, icon candidates, the hero badge, the hero title cut-out, pose and depth
drivers, the 3D probe and renders) with what it needs, makes, takes (median and worst), its weak spots and an example
from the game; the method's recipe fields typed; 2D reference rows (role identity / style / pose-and-anatomy, follow
loosely / closely / copy exactly, which map to the wordings that worked: there is no strength number, references
steer by which pictures go in, in what order, and the words); 3D reference rows (the driver library with each driver's
frames playing, or an upload: "Preferred: Mixamo-style FBX Binary, 30 fps, 'In Place' ticked, keyframe reduction
none"; a dropped model is probed by Blender and the form says what it can do: the icon render, the look reference,
pose drivers for a Mixamo-style humanoid, depth drivers for a model with its own clip); one row per look with its own
prompt, references, driver and seed and the codes it will get (`LS-D`, `LS-E`: the next free letters of the
creature's prefix; a creature's first look makes `<PREFIX>-0` the strip as it was, a hero's `-A`); icon and cut-out
candidate counts; seeds and re-roll choices; "Show the words that will be sent". Queue posts one job per look.
Every workflow a job runs is kept beside it (`<job>/workflows/NN_<render>_workflow.json` + `_api.json`) and saved into
the ComfyUI page's own Workflows sidebar (`workflows/88fits/<id>_<CODE>/`, the server's user data, through
`POST /api/userdata`); the card lists them as they land, each with "↗" (opens the ComfyUI page on that workflow: the
`88fits_open` web extension, `tools/comfy_ext/88fits_open`, installed on the server by `python tools/comfy.py
--install-ext`, reads `?open=<user-data path>`; the stock page knows only `?template=` and `?share=` links) and "file"
(the JSON to drag in); "Send to ComfyUI" pushes the ones a run did not (older jobs, a server that was down:
`POST /api/jobs/<id>/push_workflows`). The form's template workflows go the same way (`88fits/templates/`,
`POST /api/workflows/push`); `/api/status` says whether the extension is installed (`comfy_open_ext`).

**The Jobs tab.** The queue lives in `tools/dl/jobs/queue.json` with a folder per job (`job.json`, `log.txt`,
`result.json`); one Level Editor runs it (the `jobs` lock, `tools/dl/locks/jobs.lock`, claimed at start: a second
editor started while the first runs shows the queue read-only, refuses changes and says so in a banner, since two
writers of one queue file wiped each other's records; the lock's note names the port, so a lock left by an editor that
is gone is released on the next start; a new editor never kills a job an older editor still runs: it goes read-only
instead; `--no-jobs` is view-only); three lanes run one job each (comfy for the art, godot for register / import / Test in game, local for
Blender and installs), under the two repo-wide locks (one ComfyUI job at a time across the queue, Claude and every
script: `tools/dl/locks/comfy.lock`; one Godot process: `godot.lock`); the header says who holds what, and a lock left
by a process that died is reclaimed, one with no owner only by Force release. A card per job: queued (Edit, up / down,
Cancel), running (the stage of N with the stages ticked as they land, elapsed and an estimate, the log tail, the
stills with their QA verdict and the clips playing, Cancel), waiting for a pick (the candidates, Pick, Re-roll N more:
gen_ctl's side and view picks, the front-from-a-picture pick), done ("wrote <file> (variants) · one entry written in
place · backup", Open look, Re-queue, Re-roll with the cached stills and clips to redo, Install for candidates),
failed / interrupted (Re-queue, the error line). A job runs the tools exactly as Claude would (`equiv:` shows the
command) as a subprocess (`tools/asset_job.py`): under `ASSET_JOB_SIDECAR` gen_art and gen_ctl never open the
content JSON; they write `result.json` and the server merges the look's entry in place (`fresh: true`), then queues an
import. A landing that cannot be merged line by line ends "unmerged" with "Merge again" and "Re-dump this file
(changes its layout)" as explicit clicks. Edit works in every state but running (a look's recipe is written through to
the JSON); Cancel kills the process tree and, for a ComfyUI job, interrupts the server. **Test in game** queues a launch
job: the editor binary opens the debug arena with that hero in that look or that creature in that look
(`user://debug_launch.json`: `arena`, `look`, `spawn_enemy`, `variant`, `count`), the PC save kept aside and put back.

**Instructions**: "Pass 66: the asset editors", "Looks and previews" (two live players), "Art jobs" (the methods
table and the wordings from methods.json), "The Jobs tab", "Every field" for the asset kinds, and
`docs/assets_schema.md` at the end.

**Self-test**: `selftest.py` discovers `selftest_<lane>.py` groups (S 259 checks: the writer on every layout found on
disk, create / make_path / retire / delete, the vocabularies against the game source, the routes; J 222: the queue, every
transition, the progress parser on real logs, the sidecar dry run; P 106: the strip maths on the real strips, the codes,
the hero trait words, the rules on every document on disk; V 366: the player's maths and tables, methods.json, the
schema; B: methods.json, the examples, every driver's meta.json). 17,023 checks pass (14,994 at pass 61).

## Pass 68: drafts, candidates and honest re-rolls

- **Duplicate… makes a draft** and starts nothing: a new code with the source's recipe (its method recorded, its painter
  kept, its own stills and seed offset dropped, `from` = the source). The draft is selected and its typed recipe opens;
  edit it, Save asset, then press **Generate…** on its card (a purple *draft* chip). Generate… opens the job form for that
  code as a new look, with "reuse <source>'s paintings" (only the walks are made again).
- **A new look paints its own stills on its own seeds** (heroes too): Queue writes `stills: "<letter>"` and `seed_offset`
  into a new look's recipe; an existing look keeps `stills: ""` (the paintings it was made from). A removed look's code is
  not handed out again while its pictures are cached.
- **A new look comes with its candidates**: at least 3 icon candidates (a creature) or 3 badge and 3 title cut-out
  candidates (a hero), 3 by default; Queue refuses fewer. They are queued after the look, on its Model settings, with its
  front still as their reference; the Jobs tab shows one held "waiting for <code>'s front" until that still exists.
- **Badge, title cut-out and icon forms open filled in and editable**: Character (the look's or asset's `appearance`, else
  its art_prompt with the pose clause cut), Action (badge) or Pose, Holds and Camera (cut-out), and the Reference picture
  (a thumbnail; Change… picks from the library, Upload… adds one, ↺ goes back to the look's front still). Each field says
  where its value came from. A hero's icon is its round badge: "Icon candidates" on a hero are badge candidates.
- **Where the pictures show**: a look's badge on the hero sheet, the results, the Collection and the arena (the look the
  hero is played in); its cut-out on the Painted title only (Settings, debug mode: Main menu → Painted); the Live title,
  the default, draws the look's strip.
- **Re-roll does what it says**: repaint the stills (a look sharing its paintings forks them first; its walks are made
  again from the new stills), new seeds (stills and clips), keep the stills and redo the clips, redo one view (gen_ctl).
  A mode that cannot work for a method is refused with the reason. When the Model settings differ from the painter a look
  was painted with, the form selects "repaint the stills". The painter line says when stills were reused instead of
  painted ("stills reused", "N of M painted").
- **The Jobs tab** lists Up next first (per lane, in the order each lane takes them, numbered), then Waiting for a pick,
  Running and Finished.
- **The form is honest**: the 2D/3D reference rows show only where a tool reads them; a creature painted from words says
  to start from a picture with "A front from a picture".

Rules: BALANCING.md section 15. Contract and maps: tools/dl/p68/ (git-ignored).

## Pass 69: the new tools and how to use them

Garry: "make sure to update the LevelEditor and include instructions on how I would be able to use the newly created
tools in the future" (items and heroes). The same how-tos are on the Instructions tab, first after the intro.

What changed in the editor:

- **Typed params** (`AFIELDS.PARAM_GROUPS`, rendered by `typed_forms.js`): a weapon's *Params* section and a mutation's
  *Effect* section show the knobs the Salt (`SaltShaker`: *Salt patches*, *The floating shaker*), the Frisbee
  (`Frisbee`: *Flight*, *The disc*, *Carry*, *Trick Shot and stun*, *The loop*) and the basketball's new mechanisms
  (*Launch (Alley-Oop)*, *Heat on the ball*, *Ball colour (body and seams)*) and May's Trigger Happy (*Fire without a
  target*) read, one field each with its help. An empty box shows what applies without it and where that comes from (a
  mutation: its weapon's params; an evolution's `final`: its own params; else the game's default). An evolution edits
  either `params.final` (over the mutations: the "all three, amplified" numbers) or its own params. The JSON box stays
  under them for every other key. A group a weapon does not use is offered under "+ <group>" (a gun's Trigger Happy).
- **Perks have a form** (kind `perk`, the Heroes tab): *His own* lists a hero's perks with **Edit** and **+ New perk…**
  (a copy of any perk, named his). The form: Identity (name, flavour, hero, rarity, weight, hidden), Card (text,
  effects), Special (the mechanism from `PERK_SPECIALS` with its numbers as fields, the raw `params` JSON under them), Art.
  `decoy` and `periodic_buff` work on any perk; every other special is checked by its own perk's id in the game
  (`Run.has_perk("<id>")`): a copy under a new id keeps the numbers but never fires, and the form warns.
- **Heroes to buy** (lane UI wired them): Availability is *free* (`available`), *to buy* (`purchase`) or *hidden*;
  `hidden` follows it (only `hidden` hides; a hero to buy is on the title whatever `hidden` says). **Requirement** under it
  is his unlock quest: `content/quests/unlock_<hero>` with `unlocks {type: character, id}`, written, edited and removed at
  once by the availability op (`POST /api/content/hero/<id>/availability {availability, quest}`; `quest: null` removes
  it). The words are TextGen.quest_text's (mirrored by `AssetsModel.questText`).
- **Icon candidates install from the item**: an item's *Art* section (and a perk's) lists every finished `icon_cands`
  job of it, each picture with **Install** (an `install` job: the picture becomes `<id>_icon.png`, the old one backed up,
  imported). Rebound's three designs are three jobs.
- **The new stats** in the effect picker with a help line each (`vocab.STAT_HELP`): `counter_damage`, `counter_haste`,
  `counter_speed`, `counter_seconds`, `heavyweight`, `overheal`, `heal_pulse`, `last_stand`, `xp_pull_radius`,
  `xp_pull_rate`. `xp_pull_rate` is TextGen's new kind **word**: the card says "pulls more often", never a number, and it
  is left out of totals (the page mirrors both).
- **Special enemies** (lane EN): the Enemies tab's *Special* section, Settings → *Coloured specials* (the map's
  `special_defaults`), the swarm event's *Special* box.
- **Level steps show their effects** (a pass 66 bug): `U.getPath` stopped at a list, so every weapon's and passive's
  *Levels* showed no effects, and `U.setPath` turned `levels` into an object on the first edit; both now step into a list
  by index, and an emptied level stays `[]`.
- **The quest-locked band** wants 28-56% (pass44_test was re-pinned: the Salt, the Frisbee and five passive items came
  unlocked, 23 of 75); `server.BAND_LO / BAND_HI`, `AssetsModel.BAND`.

How-tos:

1. **A weapon like the Salt or the Frisbee**: Items → + New from template ▾ → a weapon → template Salt (patches) or
   Frisbee (discs) → Create (hidden, with three template mutations and a template evolution). Base stats (the Salt:
   damage a tick, cooldown between pours, amount = patches a pour, area × size, duration a patch lies; the Frisbee:
   damage, cooldown, amount = discs a volley, speed, range, knockback), Params → the typed groups, Levels (five, level 1
   empty), fill the path and name the evolution, Availability → available, Save asset.
2. **Add or hide a mutation** (Full Court Press): hide = its form → Availability → Hidden → Save. Add = + New from
   template ▾ → a mutation of a weapon → a template of the same weapon → Kind (the slot), text, effects / typed params.
   One non-hidden mutation per kind; a hero mutation is kind hero + its hero.
3. **A ball or disc look**: a basketball mutation → Effect → *Ball colour* (Body colour, glow, seam colour and glow) and
   *Heat on the ball*; a Frisbee mutation → *The disc* (look plain / razors / saucer, colours, size ×, haze); an
   evolution → Params → Edit: params.final.
4. **Swap an icon** (Rebound): the item → Art → Icon candidates → click a picture → Install.
5. **Special enemies**: Enemies → the creature → Special (chance, size ×, HP ×, ATK ×, XP ×, colour, colour strength,
   glow); all at once: Settings → Coloured specials.
6. **A special at a set second** (the Goblin moment, Red Canyon 2:00): Timeline → Events lane's + Event → Swarm →
   creature, Count 1, Pattern, Special ticked. Drag the star to move it; Delete removes it; Save.
7. **A hero's price and requirement**: Heroes → the hero → Availability → to buy → Price → Save asset; Requirement →
   + Add a requirement → condition and numbers → Create requirement (written at once).
8. **Free, to buy or hidden**: Availability (Hidden follows). A hero on the title needs a perk and exactly one hero
   mutation on his favourite weapon.
9. **A perk with the decoy** (Inflatable May): His own → + New perk… → template Inflatable May → Create → Special: every,
   first, throw min / max, flight, radius (keep it under half a screen), duration → Card text → Save asset.
10. **A run driver with level shoulders** (Fadeaway's sagging back, the raised side shoulder): pick lane ART's levelled
    drivers per view in Art words (`run_side` side, `run_spread_lvl` back; `run_sprint_lvl`, `run_dash_lvl`), or
    **+ New pose driver…** under them: the `driver_pose` job gained `amp`, `amp_bones`, `lean`, `arms: back` and
    `shoulders` / `shoulder_views` / `tuck` (tools/pose_shoulders.py writes `<name>_lvl`).
11. **A new hero look with candidates**: Looks & previews → + New look… → method and drivers → at least 3 badge and 3
    title cut-out candidates come with it (Queue refuses fewer) → Jobs tab: pick, Install → Approve the NEW look.
12. **The look he is played in**: its card → Make default (`variant`); Shelve the ones not to offer (not the one in play).

Server: `EDIT_KINDS` gained `perk` (`EDITOR_OWNED["perk"]`: hero, text, effects, special, params); `/api/heroes` records
carry `quest`, `perk_records` and `hidden_in_play`; `/api/items` weapon records carry `params`; `/api/vocab` serves
`perk_specials` and `stat_help`. Self-test: `selftest_L69.py` (the tables against the game's sources and the content, the
requirement and perk operations on a temp tree, the page's hooks and these docs).

## Pass 70: candidates, pictures, the base look, inherited words

Garry (2026-10-13, "LevelEditor"): candidates on different seeds; choose a look's icon and title cut-out from what the
jobs saved (and May's badge missing in the Heroes list); the 500 on the Bandit look ("tell me what I did wrong, add a
check"); removing MAY-A; every inherited value already in its box. The same how-tos are on the Instructions tab, first.

What changed:

- **Candidates on seeds of their own** (`tools/cand_seeds.py`). The cause: within a job the seeds always differed (a
  different seed is an unrelated noise), but a NEW job of the same look painted the same seeds again (MAY-E's badge jobs
  j..b9ac and j..aca1 both painted 2768, 3768, 4768; every title job of a hero 11, 112, 213, 314; icon jobs of one key
  the same four), and a front from a picture always painted `seed_for(id + slug) + 1000 k` and gave a re-run the cached
  files back. Now candidate k sits `CAND_STEP` (1,000,003) from k-1, a job moves its seeds by its id (`job_salt`, crc32 of
  the job id times 15,485,863), a re-run by its attempt (`ASSET_JOB_ATTEMPT` from `tools/asset_job.py` for the tools that
  take no `--attempt`), and gen_edit_stills moves its earlier candidates to `<key>_c<k>_old<stamp>` before it paints.
  gen_badge_cands, gen_title_heroes, gen_icon_cands, gen_edit_stills and gen_ctl's side and view candidates use it. The
  remaining likeness comes from the method: every candidate is an edit of one reference picture on a few-step model, so
  words asking for the reference's own pose (the title's default "standing confidently") come back as the reference.
- **Choose a look's badge, icon or cut-out from everything painted** (`LookGrid.picker` / `pickers`): beside a look's
  big player, and under a hero's badge and cut-out previews, "Choose <CODE>'s badge / title cut-out / icon from
  everything painted (N in M jobs)" lists every finished `hero_badge` / `hero_title` / `icon_cands` job of the asset,
  newest first; Install posts `POST /api/jobs/<job>/install {choice, options: {variant: <CODE>}}` ("" = the asset's own,
  the base look's top-level files). jobs.install puts the install job on that look: a badge `--pick <key> --variant`, a
  cut-out named by its file (`--pick <id>=<file>.png`), an icon with `icon_job.variant`. A base look that names its own
  cut-out keeps it (gen_title_heroes), a creature's own icon is the file its JSON names (gen_icon_cands).
- **The lists show the look in play**: `/api/heroes` records carry `icon_play` and `title_play` (the played look's badge
  and cut-out, `?v=<mtime>`); the Heroes cards use them. May showed none: the list read `/icon/hero/may` (her base
  look MAY-A's `may_icon.png`, a dark placeholder) while her badge is MAY-G's own `may_icon_g.png`.
- **The Bandit check.** What went wrong: job j20261013-001220-f286 had the picture's path in **Stills** (and in
  Reference). Stills is the short name the look's paintings are cached under (`bdb` -> `buckshot_dwarf_bdb_front.png`);
  gen_edit_stills built ComfyUI's upload name from it (`buckshot_dwarf_tools/dl/uploads/2d/bandit.png_ref.png`) and
  `/upload/image` answered 500. Now `vocab.STILLS_RE` (`[A-Za-z0-9_]{0,40}`) is checked by the job form (a red line under
  the box, Queue refuses), `jobs.validate_spec` and `requeue`, the server's recipe op, add_look and Save (a new bad value;
  one already on disk is the page's error rule), the recipe editor (an error that blocks Save asset) and gen_edit_stills
  (`SLUG_RE`, SystemExit with the words "Stills is a short name for this look's paintings, like bdb; the picture goes in
  Reference"); `comfy.upload_name` makes every upload name one plain file name (a path's parts joined with _, at most
  120 characters, .png).
- **Removing the base look**: a base card (not the default) has **Remove…**, which asks which look becomes the base (the
  looks with a strip of their own, the one in play first). `server.remove_base`: the top-level art keys
  (`BASE_ART_KEYS`: sprite, icon, anims, strip_cols, fps, a hero's frame_px, head) become the new base's (no file is
  renamed), `variant_base` names it, the old base's entry goes, the looks that inherited the old top-level anims / fps /
  head / frame_px get them written into their own entries, the old base's files that nothing names any more (+ its
  `<id>_ai.json`) move to `backups/deleted/<id>/<stamp>/` with `base_<CODE>.json`, then the import. The new base keeps its
  whole entry (recipe, note, cut-out, `icon_picked`): its jobs still run on its own recipe, and `merge_look` mirrors a
  landing on such a base to the top level (`set_look_files` its icon). `remove` without `new_base` on the base answers
  409 with `choices`; in a bulk remove the base is refused. The page takes a key the server changed on disk into an open
  document (`refreshRecord`), so a later Save never writes the old art back. **MAY-A was removed this way** (her base is
  MAY-G; backups in `tools/level_editor/backups/deleted/may/20261013-010009/`).
- **Inherited values in their boxes** (`Forms.inheritable`): a text, textarea or number box whose own value is empty
  shows the inherited one in the box (italic, dashed, "inherited from the creature's art_prompt"); an edit makes it the
  look's own when you leave the box; emptying it (or typing the inherited text back, or **↺ inherit**) inherits again;
  a box nobody changed writes nothing. In the typed recipe, the job form's *What to paint* and the typed params of a
  mutation or an evolution (values from another item; the game's own defaults stay placeholders). Selects, yes/no and
  drivers still name the inherited value in their empty choice.
- **Fixing one view**: **Run size** (the recipe key `run_scale`, lane ART's gen_art key: `{view: multiplier}`, 1 = as
  fitted, clamped 0.5..1.5; a `view_numbers` row per view in the typed recipe and the job form, methods.json's hero_pose5,
  hero_fit, creature_free2, creature_pose2, creature_free8) sizes one view's walk: gen_art fits every walk back to the
  standing height by its tallest frame, so a crouching side run comes out taller and a back run whose foot reaches
  toward the camera smaller, and a scaled driver cannot fix that (it is fitted back); a re-queue with nothing re-rolled
  only re-places the cached walks. `driver_tweak` (methods.json "A driver tweaked…", "+ Tweak a driver…" in a hero's
  Art words): a copy of a library driver with one change (op scale: a wide figure kept inside the clip / spread /
  occlude / shoulders, tools/pose_scale.py, pose_spread.py, pose_occlude.py, pose_shoulders.py); the re-roll **redo one view's walk** (`reroll {mode: "clip",
  view}`: only that view's clip moved aside and walked again, anim_seed + 1; creature_ctl's walk_seeds[view] + 1); and a
  re-queue now reads the look's recipe as its JSON holds it (it used to write the job's old copy back over a recipe
  edited since, so a one-view re-roll walked on the old driver).

- **The pick race** (lane ART): the pick of a front from a picture used to write its job's own copy of the recipe
  over the look's whole recipe, so a look job queued before the pick landed lost its words (BD-A's first walk ran on
  the base dwarf's). The pick now merges only `stills` into the look's recipe as the JSON holds it (`Hooks.merge_recipe`,
  under the write lock; no painter, no note).
- **A hung Godot step**: a `godot --import` once sat 12 minutes at no CPU holding the Godot lock for every lane
  (j20261013-031045-ad0e). A Godot step of a register or import job is killed after `GODOT_STEP_TIMEOUT` (600 s;
  `LE_GODOT_STEP_TIMEOUT` sets it, the job spec's `step_timeout` wins, 0 = never); the lock is freed, the job fails with
  "the step ran over its N s limit and was killed …: Re-queue to run it again". Test in game never times out.

How-tos:

1. **A look from a picture (the Bandit)**: Enemies → the creature → Looks → + New look… → *A front from a picture* →
   Reference picture: Upload… (bandit.png) → Stills: a short name (`bdb`) → prompt: ONE figure seen from the front
   (keep every detail of a turnaround prompt, drop "front and back on one sheet") → keep → 3+ candidates → Queue →
   Jobs: pick a front → the look's **Generate…** → the walk method → Queue → Approve.
2. **Choose a badge / icon / cut-out**: click the look → "Choose <CODE>'s badge from everything painted" → a picture →
   Install (an install job: backup, the look's entry, import).
3. **Remove a base look**: its card → Remove… → which look becomes the base → Yes.
4. **Change three words of an inherited prompt**: Recipe (typed)… → edit in the box → leave it → Save asset (↺ to undo).
5. **Fix one view** (May's side runs, Jeżyk's back run, hands that show): play the look per view against its idle. A
   view too tall or too small: Recipe (typed)… → **Run size: <view>** (0.88 = 12 % smaller) → Save asset → Re-roll… with
   re-roll *none* → Queue (the walks are only placed again). Hands or shoulders: the view's driver → another from the
   library, or + Tweak a driver… (spread / occlude / shoulders; scale only for a figure leaving the clip) → name it in
   the recipe → Save asset → Re-roll… → *redo one view's walk* → the view → Queue. A painting problem (straps, hands through
   clothes on a still): the view's hint words in place → Save asset → Jobs → the look's job → Re-roll… → tick that view's
   still and clip → Re-queue.

Self-test: `selftest_LE70.py` (the seeds of every candidate tool, the Stills rule everywhere and upload_name, the base
removal on a temp creature and hero and May's real JSON, the install into any look, the one-view re-roll and the
re-queue's recipe, driver_tweak's plans, Forms.inheritable under Node with a stub DOM, these docs). Garry's running
editor gets the page and server changes when it is restarted; the tool changes reach his queue at once.

## Pass 71: the Puppet method

Garry (2026-10-13): "I quite like this approach, add that in to LevelEditor with the considerations that I asked you
about earlier": choose which 2D reference feeds the 3D model, or have one painted locally; preview the animated 3D model
in the editor; the Puppet method in the job form like the others, with its warnings and timings. The trial (lane PUPPET,
`tools/dl/puppet/status_PUPPET.md`) made May a rigged 3D figure whose own renders guided her walks (MAY-P, MAY-Q); this
pass made it any hero's method. The same how-tos are on the Instructions tab ("Pass 71: the Puppet method").

What changed:

- **`tools/puppet.py` is any hero's.** `--look` (the source look), `--ref front=paint side=still:<key> back=<picture>|none`
  (the 3D reference per view: arms-out candidates painted locally by default, a still of any look, an uploaded picture,
  or no side / back), `--screen` (Jeżyk on green), `--painter klein|dev --steps --no-turbo --seeds --seed`, the edit's
  words per view (`--words-front/side/back`; the templates are any hero's, the front names the character from its
  `appearance`), `--clip` / `--idle` (Mixamo FBX files in `tools/dl/mixamo/`; the idle procedural by default),
  `--frame soles|ankles` (the stick figures framed by the soles: MAY-P's chunky boots left the canvas on the ankle
  framing), `--reroll front|views|shape`, `--reset-from <stage>` (moved to `old/<stamp>/`, never deleted), `--lane`
  (stops with `puppet: NEXT lane X`, `puppet: PICK front|views|shape`, `puppet: DONE guides`) and `--dry-run`
  (everything recorded, nothing reaches ComfyUI or Blender; a mirror of the hero's puppet folder so it knows what is on
  disk; the guides' stand-ins under the dry root). The guides are versioned: `<hero>_puppet_<clip>` (running.fbx =
  `run`, the trial's `may_puppet_run`), a new `_2`, `_3` when the framing, the clip or the GLB changed, so a look keeps
  walking on the guides it was made with; each guide folder holds its `silhouette.json`. `tools/puppet_blender.py`:
  `name=` (the mesh `<Name>`, the armature `<Name>_Rig`), `idle=<fbx>` (retargeted like the run), `frame=soles`, and the
  guides' `meta.json` says the framing, the clip and the GLB.
- **gen_art: `run_fit` and `fringe_remap`** (docs/assets_schema.md). `run_fit` sizes each view's walk by its median frame
  at the puppet's own run/idle height for that view (the trial's "next step": no run_scale to tune; run_scale still
  multiplies on top); `fringe_remap` moves the hues a view's painting lacks to its nearest own hue (the trial's rainbow
  fringes). Both off unless a look's recipe names them.
- **The method `hero_puppet`** (methods.json; the card's picture is the trial's May from the arms-out painting to the
  painted run, `examples/hero_puppet_may.png`; its weaknesses: Hunyuan3D-2mv's licence leaves out the EU, the UK and
  South Korea; the AMD card runs only ComfyUI's built-in 3D nodes, restarted before and after; a depth video carries no
  face; Klein's four hands; the projected colours; the fringes; the procedural idle; the trial's side face; the stage
  times measured on May and Jeżyk).
- **The job** (`jobs.py`, a `look` job with method `hero_puppet`): its phases are puppet.py runs through
  `tools/asset_job.py` (tool `puppet`), each on the lane its work needs: comfy for the arms-out paintings and the
  Hunyuan3D shape (under the ComfyUI lock), local for Blender (no ComfyUI lock: the child's env has no
  `LOCK_HELD_COMFY`). puppet.py's stop lines move the job: a pick → *waiting for a pick* with the candidates (the front;
  one side and one back picked together: `side=1,back=0`; the shape's tries in clay), `--pick` on the next phase; a lane
  change → queued again at the front of the other lane; DONE → the guides' names written into the look's recipe
  (`pose_drivers` every view, `ctl_drivers` the depth views, `run_fit` the silhouette; `hooks.merge_recipe`), then the
  walks on the comfy lane as hero_pose5's gen_art, merged and imported the same way. The look's recipe starts as the
  source look's (stills, seeds, words; never its run_scale or drivers) unless *paint this look's own stills*. The card:
  the puppet's stages ticked from the files on disk (a hero with a puppet: done), the candidates and the tries as they
  land, every ComfyUI workflow (saved in the page's sidebar, ↗), the pictures, the 3D viewer, the guides' sheets.
  **Re-roll…** offers *run the puppet again from a stage* (`--reset-from`, once); a pick's **Re-roll N more** paints
  that pick's candidates again (`--reroll`, new seeds); the job form's re-roll radios have the same stage choice.
  `puppet_problem` refuses at Queue a picture not on disk, a missing FBX or .blend, a clip not in tools/dl/mixamo.
- **The form** (`puppet.js`, called by jobs.js for hero_puppet): *The 3D puppet*: what is on disk (with the viewer),
  *start from* (the puppet he has · a new puppet · his .blend · a Mixamo-rigged FBX), the source look, the **3D
  reference** per view (paint arms-out locally with the words to edit, a look's still or an uploaded picture with its
  thumbnail and the arms warning, none for side/back), the painter, passes, candidates, screen, tries, triangles; the
  clips; the walks (depth or stick figure per view, framing, run size from the puppet, fringe remap, the walks' stills);
  the trial's timings. "Show the words that will be sent" starts with the arms-out words.
- **The 3D preview**: Google's `<model-viewer>` 4.0.0, vendored (`tools/level_editor/vendor/model-viewer-4.0.0.min.js`,
  self-contained, its licence note beside it; served by `/vendor/<file>`), loaded on a click (a poster first; a job card
  is rebuilt while it runs): the GLB's clips in a picker (run, idle), play / pause, speed, front / 3/4 / side / back,
  drag to turn, wheel to zoom. On the hero's **Art words** ("The 3D puppet": the viewer, the stages, the .blend and the
  RIG_HOWTO, the arms-out picks, the guides with their framing and run/idle ratios, **+ New look from the puppet…**) and
  on the job card. The server: `GET /api/puppet/<hero>`, `/dl/puppet/...` with `.glb` as `model/gltf-binary`.
- **Waiting and resuming cards** show their stages and what the job made so far (its workflows above all): a puppet job
  stops three times.
- **The settings** (Garry's follow-up: every improvement a setting of the method, visible with plain help, on by default):
  in the form's *The 3D puppet* → *The walks of this look* (`Puppet.WALK_SETTINGS`): **Size from the 3D model**
  (`puppet.run_fit`, the job writes `run_fit`), **Frame by the soles** (`puppet.frame: soles`), **Clean colour fringes**
  (`puppet.fringe`, the job writes `fringe_remap`), **Keep the face angle** (`puppet.face: nose`: puppet.py `--face`,
  puppet_blender `face=`; the stick figures' ears placed from the 3D model's measured nose, the trial's guide v3, so a
  side view stays in profile; `head` = on the head bone, the trial's first guide that turned May's side run to the
  camera; part of the guides' match, so another face angle makes new guides; and gen_art walks the back and bd views of
  such a look on its hint without the clauses that name the face, `gen_art.hint_for_view`: a depth video cannot tell a
  front from a back, and MAY-R's first back walk, on a hint that described her face for the front, ran facing the
  camera), and per view **Depth or stick figure**
  (`puppet.depth_views`; the depth video has no face, so the front walks on the stick figure). Every setting is recorded
  in the look's recipe under `puppet` (`jobs.PUPPET_SETTINGS`: source, stills, refs, painter, steps, turbo, seeds,
  words, screen, tries, faces, reuse, fbx, clip, idle, frame, face, depth_views, run_fit, fringe; written at Queue and
  Edit); `recipe.puppet` shows in **Recipe (typed)…** (methods.json's `puppet.*` rows) and a re-queue runs what it holds
  (the job's own copy is dropped). The job form shows them once, in *The 3D puppet* (not again among the recipe rows).
- `LE_JOBS_DIR` points a test editor (`--no-jobs`, its own port) at a queue of its own; unset = the real one.
- **Saved workflows open clean** (the lead, from lane PDOC): every job's "open in ComfyUI" link opened with its LoadImage
  nodes red ("Media input missing" / "4 errors found, resolve them before running"): the graphs name their pictures
  `88fits/<file>` (the upload's subfolder) and the page's LoadImage picker lists only the input folder's top level.
  `comfy.save_job_workflow` now rewrites the workflow it SAVES (the UI file and its sidebar copy; never the graph that
  runs, nor `_api.json`): each LoadImage names a top-level copy of the same bytes, `88fits_<sha1 10>_<file>`
  (`comfy.portable_ui`, `top_level_input`; uploaded once per picture and process; a picture that cannot be copied keeps
  its name). Named by its contents, a saved workflow keeps the exact picture even after a later job overwrites the
  subfolder file. Workflows saved before this keep their old names.
- **A dry run never writes into game/content**: `tools/asset_job.py --dry-run` of a real look's job let gen_art save its
  procedural strip, icon and `_ai.json` beside the real JSON (a dry run of MAY-Q's walks overwrote `may_sprite_q.png`
  and `may_q_ai.json` on 2026-10-13; both put back from git). gen_art now works on a copy of the JSON under
  `<job>/dry_content/<type>/<id>/` (`asset_job._dry_folder`); a temp copy elsewhere (the selftests') is used as it is.
  gen_ctl's dry run still finds its creature folder under game/content by itself: dry-run gen_ctl jobs on copies only.
- **A shared default** (found by the selftest): a look job posted without a `recipe` got jobs.py's one default dict, and
  `_seed_recipe` wrote that look's stills and seeds into it, so every later job without a recipe started with them.
  `validate_spec` now hands each spec its own copy (the page always sends a recipe; the API and scripts did not).

Proved (tools/dl/puppet/PLE/, status_PLE.md): **Jeżyk's puppet** (hero `buck`, look BUC-F, green screen) made by
puppet.py: 4 arms-out fronts in 92 s (one had four hands), 3 sides + 3 backs in 161 s, two Hunyuan3D tries 99 s + 87 s
(+ two restarts), clean, rig, the run, colours and the GLB, guides framed by the soles and the silhouette in 75 s of
Blender: `tools/dl/puppet/buck/buck_puppet.glb` (also in Drive's `puppets/`), guides `buck_puppet_run` (+ `_depth`);
his looks untouched. The job machinery on a queue of its own: Jeżyk's reuse job (every stage on disk, DONE, the recipe
update, the walks queued), Astro's first phase on the comfy lane (four fronts, the pick, its workflows in the sidebar),
`tools/asset_job.py --dry-run` of a new May puppet with the dev painter and a still for the side (every stage recorded)
and of the walks on MAY-Q.

Self-test: `selftest_PLE.py` (puppet.py's arguments, words, lanes, picks, versioned guides, reset and re-roll, the dry
mirror and a whole dry chain on a temp copy; puppet.js's copy of the templates; gen_art's run_fit and fringe_remap;
hero_puppet in jobs.py on a temp queue and tree: the spec, the refusals, the lanes, the argv, the stages, the recipe, the
markers, the phase ends, pick, requeue, the stage re-roll, the GLB output; the server's routes on Jeżyk's real puppet;
methods.json's card; the page hooks; these docs).

## Pass 76: the icon guard (an icon is never lost again)

Garry (2026-10-14): "Bring back the old Solenne icon, I made a variant of an Icon and can't find the old one. Make a fix
in LevelEditor to make sure that this doesn't happen."

**What happened to Solenne.** A badge painted "for the base" was installed into SOL-B, the look the game plays. The
editor wrote it into SOL-B's own entry without asking, so every screen (the title's hero drawer, the hero sheet, the
results) showed the new badge, and the old one (`solenne_icon.png`) was only on the other looks' tiles. Nothing was
deleted. Her old badge is back: SOL-B no longer names a badge of its own, so it shows hers again. The new one
(`solenne_icon_b.png`) is still on disk: open Solenne, select SOL-B, open **All icons on disk** and press **Use for
SOL-B** if you ever want it back.

**What is different now.** The editor needs a newer server: close the Level Editor and open it again
(`tools\level_editor.cmd`) to get all of this.

- **Nothing is overwritten.** Installing a candidate (a badge, an icon, a card) always writes a new file of its own,
  named after the job and the candidate: `solenne_icon_b_3d3c_c2.png` is candidate c2 of job #3d3c for SOL-B, and
  `solenne_icon_3d3c_c2.png` the same for the base. The file the look showed before stays where it was.
- **The editor asks before it changes what the game shows.** When the icon of **the look the game plays**, or of **the
  base look** (whose icon every look without one of its own shows too), would change, a box asks first: the picture
  now and the new one side by side, with their file names, and why it matters ("SOL-B is the look the game plays";
  "SOL-A is the base look: SOL-C, SOL-D and SOL-E show it too"). **Cancel** changes nothing. This box comes from
  every Install button: a look's "Choose ... from everything painted", the Jobs tab's candidates, an item's icon
  candidates. A look that is neither played nor the base changes at once (it still gets a file of its own).
- **Every change is remembered.** The look keeps a list of its icon changes (`icon_history` in its entry; the base's
  sits next to the JSON's top-level `icon`), each with the date, the old and new file names, why ("install c2 of
  #3d3c", "use backup/…") and a copy of the old picture.
- **Revert icon.** Under each look's picture (select a look in the Looks grid), and in an item's Art section, the
  **Icon now** box shows the picture the game uses for that look, its file and where it comes from (its own, the
  base's), with a **Revert icon** button: it undoes the last change (asking first for the look in play or the base).
  A look whose badge was picked before this pass (like SOL-B was) goes back to the base's badge. **Changes · N** lists
  every change, newest first.
- **All icons on disk.** The same box opens a gallery of every picture of that hero, creature or item that exists
  anywhere: its folder, the copies the editor keeps (`tools/level_editor/backups/<id>/`), the files of removed looks
  (`backups/deleted/<id>/`) and the copies older tools made (`tools/dl/backup/icons*/`). Each picture shows once, with
  the looks that use it; **Use for <look>** puts it on the selected look (a copy from a backup is first put back into
  the folder under its own name). Double-click a picture to see it big.
- **Backups.** Before the editor changes an icon it copies the picture being replaced into
  `tools/level_editor/backups/<id>/` (once per picture), beside the JSON backups. A job that may paint over an icon (a
  look's re-roll, an item's icon roll, an install) first copies all of the asset's icons there too. These copies are
  not in git (the folder's `.gitignore`).
- **A picked icon stays picked.** A look's re-roll used to name its own front crop as the look's icon again; a picked
  icon now stays (the server, gen_art and gen_ctl all keep it).

For scripts: `GET /api/content/<kind>/<id>/icons` (the gallery and each look's icon now), `GET
/iconfile/<kind>/<id>/<folder|backup|deleted|legacy>/...` (one picture), `POST /api/content/<kind>/<id>/icon {op:
"revert" | "use", code ("" = the base), ref, confirm}` (also the look ops `revert_icon` / `use_icon`), and `POST
/api/jobs/<job>/install` answers **409** with `confirm_needed` (now, next, played, base, shared_by) until it is sent
again with `confirm: true`. The keys: `icon_history` [{icon, shown, backup, to, at, why, picked | entry_icon}].

Self-test: `selftest_ICON76.py` (the question before an install into the look in play or the base, over HTTP too; a
pick's own file and the old file's bytes unchanged; Revert icon, a picture painted over since put back from its copy,
a pick from before the guard; the gallery and Use for this look from the folder, a backup and an older tool's copy;
the backups under `backups/<id>/`; the jobs' plan, landing and snapshot; the pick tools; the page; Solenne's JSON).

## Pass 76: a weapon family's looks

Garry (2026-10-14): the Grenade as a Dynamite Stick "as a Look (with several candidates), so I can switch back to the
grenade if I ever change my mind", and the Molotov in several flame versions. A weapon, its evolution and its mutations
now have looks the way the cards (pass 73) and the heroes have, and the whole family plays one look at a time.

**What a look is.** Each item keeps its own fields as its base look (A); its JSON's `variants` holds the others (B, C,
D...), each saying only what changes in that look: its name, flavour, card text (a mutation's), icon, visual, the
drawing params (the dynamite's models, a flame's style), and the weapon's thing words ("stick" / "sticks", which the
card text uses instead of "grenade"). A look never changes the numbers: the stats, levels and rules are the family's in
every look. A mutation or an evolution without an entry for the look the family plays simply wears its base.

**Which look plays.** The weapon's `variant` (its JSON) is the look of the whole family: the weapon, its mutations
(the Drifter's own one too) and its evolution. On the phone the debug arena's ITEMS tab has a **Weapon looks** row for
every family with two or more looks: a tap plays that look on this phone from then on (the cards, the HUD, the pause
screen, the Collection, and the weapon in your hands at once); **JSON** goes back to the weapon's own `variant`.

**In the editor.** Open the weapon (Items tab) and look at its **Art** section: every look of the family as a tile, its
icon on the item's plate at 112 and 48 px, its name, PLAYS on the one the game plays, the note, and under it the
family's other members in that look (faint when one has no look of that code and wears its base). **Play this look**
writes the weapon's `variant` and imports it; **Show** makes the icon preview above (and **+ Icon candidates**) follow
that look, so a repaint lands in it. An evolution's or a mutation's Art section says which look its family plays and
which one it wears, with its own looks and **Open <weapon>** (a member never plays a look of its own: play it on the
weapon). The weapon's card in the list says "look B of 4" and shows the name it plays under. A look whose icon or
visual file is not on disk yet cannot be played (its tile says "files missing").

For scripts: `POST /api/content/weapon/<id>/variant {code}` (an evolution or a mutation is refused); the weapon's
record in `/api/items` carries `family_looks` (per look: code, name, icon, note, shelved, fresh, exists, default, base,
members [{kind, id, role, name, icon, own, hidden}]) and every family member `play`, `icon_play`, `name_play`. The keys:
tools/dl/p76/keys_LOOKS.md (the lead folds them into docs/assets_schema.md). Self-test: `selftest_LOOKS76.py`.

## Pass 77: the Sim tab (the game plays your map, run after run)

Garry (2026-10-14): "Add a game sim tab which simulates a run ... simulate like 10 players (editable) and the output is
the average ... charts per second showing: Player DPS, Player HP, Death, Difficulty (composition of enemy HP and atk,
which are likely to be alive at that point), Coins (total gains), Total Damage Dealt (different sources breakdown as
well), Kills (different enemies breakdown), hero level, total exp gained ... consider the multipliers and all the enemy,
cap and stuff ... the sim requires a manual button press".

**What a sim is.** The real game plays the **saved** map, headless (no window), as many times as you ask, with a bot at
the controls, several runs side by side; every second of play is then averaged over the runs into charts. Because it is
the game itself, everything counts: the cap and the hard cap, the roster, the waves and events, every HP and ATK
multiplier (stage, time, hero level), specials, Elites, the bosses and their HP pegged to the hero's DPS, the Upgrade
board, the cards, chests and evolutions. The bot (lane SIMRUN, `game/tools/sim_run.gd` and `sim_pilot.gd`; its rules in
BALANCING.md): it kites the crowd the way the difficulty probe does, gathers the gems when the way is clear and it is
healthy, steps out of red warning rings, takes the level-up cards a sensible player would (an evolution, the hero's
favourite, a new weapon while a slot is free, a weapon's next level, a hero perk, a new card, a card's next level, a
passive item; ties at random; never a skip, reroll or banish), takes every chest, walks to the boss's chest and the
portal and always goes on, leaves the Stranger and the shop alone, takes the Totem Pole gift with the most feathers, and
answers Down! as you set. It plays with every item unlocked (the whole card pool, whatever the save has) and the Upgrade
board you choose. It plays like a steady player, not a great one: read the charts as "a run like this goes like this",
and compare sims with each other.

Nothing runs until you press **Run sim**. A sim copies the game into its own folder first (the snapshot,
`tools/dl/sim/snap/game`, with its own save folder `%APPDATA%\88fits_sim`), so it never touches your save, never waits
for the Godot lock and never blocks a Save, an import or the tests: you can keep editing and saving while it runs. It
plays what was saved when it started.

### Run a sim

The Sim tab sits right after Timeline. It is one page that scrolls as a whole: the settings on top, then the sim
running (when one is), the history, and the sim shown with its charts.

1. In **Run a sim** (**Hide settings** folds it to one line; **Show settings** opens it again):
   - **Hero**: who plays every run.
   - **Runs** (10): how many runs are played and averaged. More runs = smoother averages, longer to wait.
   - **At once** (auto): how many play side by side. Auto = as many as the runs, at most the PC's logical processors
     less 2 (14 on this PC): ten runs play all at once.
   - **Stop at** (25:00): play time. Boss fights and portal waits count (the timeline's clock stops during them, so a
     run that stops at 25:00 of play has reached about 21-23 minutes of the timeline).
   - **On death** (end the run at the first death): *end the run at the first death*; *revive once with an ad, then end*
     (Down! answered with the ad revive while it is offered); *keep playing, count every death* (the hero is put back on
     his feet at once and plays to the stop: every run lasts the whole time, and the Deaths chart counts every fall).
     "Revive with gold" is gone with Get up with gold. A policy the game's runner does not know yet is not offered.
   - **Seed** (1): run 1 plays this seed, run 2 the next, ... The same seed on the same saved map plays the same runs as
     far as the game allows (the structures' places and the Totem Poles' gifts stay random).
   - **Note**: a few words to find the sim in the history.
   - **Drawing** (skip it): on, the runs draw nothing and play no sound (the runner's sim mode, every rule kept: ten
     runs of 25:00 took 10:23 instead of 18:10); off, every frame is drawn and every sound played as in the game
     (slower: a check that the sim mode changes nothing). Offered when the game's runner has the sim mode; the header and the history say "everything
     drawn" for a sim that played with it off.
   - **Upgrade board**: the eight talents, each with its rank (0-6) and its form (Grit: Padding or Plate, ...). The
     buttons fill them: **none**, **a quarter** (12 of the 48 ranks), **half**, **full** (every talent in its usual form,
     as the difficulty probe plays them), **my save** (the talents bought in your save on this PC, forms rank by rank).
     Change any row and the board is **custom**. Every run plays the same board. A rank's forms can be mixed in your save
     ("2 Padding, 1 Plate"); choosing one form makes every rank that form.
2. Press **Run sim**. If the map has unsaved changes it asks first: **Save and run**, or **Run the saved map**. The line
   under the button says about how long it will take if every run lasts to the stop (a run that ends at a death makes
   it shorter), and the line under that why: a sim plays the real game frame by frame (60 frames to a second of play,
   every rule), headless, several runs at once; it learns this PC's speed from every full sim.
3. While it runs, the card under the settings shows each run's clock and level, how many are done and about how long is
   left (from the runs' own pace). **Cancel** stops it; the runs already finished stay as a partial result. The charts
   take over as soon as the first run of the sim you started finishes, and fill in as the others do. The sim is also a
   job in the **Jobs** tab (lane "sim": it never holds up the art or the imports); its card opens the Sim tab.

### Read the charts

The header says what the sim played: the hero, the settings, the board talent by talent, which save of the map (when it
was saved and a short code), the game version, when it ran and how long it took, "every item unlocked". Under it, the
**tiles**: how many runs reached the stop, when a run ended (the middle one), deaths, level, kills and coins per run
(each run counted at its own end), and each boss: how many of the runs that met it beat it, the fight's usual length and
its HP pegged to the hero's DPS.

The charts come in five sections, in the order you listed them. Every chart has play time along the bottom, the stage
starts as thin lines and the boss fights as amber washes (each the middle value of the runs that got there; hover one
for the details), and says in its own words what it shows and how it was averaged:

| Section | Chart | What it shows |
|---|---|---|
| The hero | **Player DPS** | the damage dealt each second by every source; each run smoothed over 5 s, then averaged; the pale band is the middle 80% of the runs; the dashed line is the build's own estimate (the pause screen's). **smoothed 5 s** switches to the raw per-second average |
| | **Player HP** | health and max health (dashed), the band the middle 80% |
| Death | **Runs still playing** | the share of the runs not yet ended |
| | **Deaths so far** | falls per run (revived or not), counted over every run: an ended run keeps its count |
| How hard is each second? | **Danger: health lost a second** | how much of his max health the hero loses each second before healing (the line) and after it (dashed: below 0 = he heals more than he loses). 2% means a full bar lasts 50 s |
| | **Keeping up with the crowd** | how many seconds of his own damage he would need to kill every creature alive, the boss left out: rising = falling behind, flat or falling = keeping up. Dashed: the boss alone. The middle run at each second, not the mean (a crowd over a DPS jumps where the DPS is small) |
| | **Close crowd** | creatures within 3 m of the hero (and 6 m, dashed): the ones that can reach him now |
| | **Who is alive** | the crowd split by creature |
| | **Runs in trouble** | the share of the runs whose hero is under 30% of his health |
| | **What hurt the hero** | health lost so far, by creature or attack |
| | **Hits taken** | hits that reached him each second (10 s mean) |
| | **Healing** | health healed so far, by what gave it |
| | **The crowd against the cap** | creatures alive and the director's cap at that second |
| | **Spawned and killed** | each second, over 10 s: kills above spawns = winning the room |
| | **How strong a creature spawned now is** | the HP × and damage × a creature spawned at that second gets (stage, timeline, hero level) |
| Rewards | **Coins gained** | every coin picked up so far, split by where it came from (spending not taken off) |
| | **Damage dealt** | all the damage so far, split by weapon, evolution, perk, blast |
| | **Kills** | creatures killed so far, split by creature |
| Growth | **Hero level** | the level, the band the middle 80% |
| | **Total XP gained** | every point of XP so far |
| | **The build: items held** | weapons, evolutions, lines, passive items and perks held |

A chart the runs cannot draw (the game's runner did not report its numbers) is left out and named under the section.
Crowd HP and crowd attack are no longer charts: a sum of the whole crowd's health counts the boss, and a sum of every
creature's hit is never what can land at once; Danger, Keeping up and Close crowd say how hard a second is instead.

A chart's average is over the runs **still playing** at that second (Runs still playing says how many): late in a sim
where many runs died, the average is of the stronger runs. The splits show the 7 biggest and the rest as Other (hover:
the biggest inside Other are named); the same creature has the same colour in Who is alive, What hurt the hero and Kills.

**Hover** any chart: a line follows the mouse on every chart and the numbers under each one say what they were at that
second (with the timeline's clock and the stage). Without the mouse they show the end. **Table** shows the numbers every
minute; **CSV** saves every second of that chart for a spreadsheet. **The N runs one by one** (under the charts) lists
each run: its seed, how and when it ended, its deaths, level, kills, coins and its build at the end.

What came from the run dashboard (analytics/dashboard.html) and what did not: the Sim took what helps judge a timeline
from an average of runs: what hurt the hero, hits taken, healing by source, the crowd against the cap, spawned against
killed, the creatures' strength multipliers and the build's growth. It left out what only means something for one run or
one player's choices: the last 30 seconds before a death, the card decisions (the bot's are rules, not choices), the
Stranger and the totems, quests, the stat sheet's growth and the stacking bonuses.

### Compare two versions

1. Run a sim. Change the map or a creature, save.
2. Run a sim again with the same settings and seed.
3. In the **History** (the last 10 sims, newest first; **Keep** one and it is never removed), press **Compare** on the
   older one, or pick it in **Compare with** above the charts: its lines come in grey dashes on every chart of the one
   shown, and the numbers under each chart give both. **Show** makes a sim the one shown.

The header warns when the map has been saved since the sim shown ran.

### Good to know

- How long a sim takes, measured on this PC (16 logical processors) with 10 runs of 25:00 that all play the whole time
  ("keep playing"): 10:23 with ten at once and the runner's sim mode (it skips the drawing, every rule kept; each run
  6:40 to 10:10, about 3 times as fast as real play); 18:10 with ten at once and the sim mode off; 23:39 with six at
  once before the sim mode existed. The default settings (end at the first death) took 9:04: two runs reached 25:00,
  the others died between 2:51 and 9:08. The time under the button comes from the last full sims at that number at
  once, at the pace of their slowest run (ten runs at once end with the slowest); a sim where most runs ended early
  teaches it nothing (the few left have the PC to themselves and run faster). The first sim copies the game into the snapshot
  (about 30 s) and imports it (about 15 s); after that only what changed is copied (a second or two), and the snapshot
  imports again only when a picture, model, sound, font or a script's class changed. A content JSON newer than its
  `.tres` is imported in the snapshot, so the sim plays the saved JSON even when the editor's own import was queued.
- A run that hangs (a screen up too long) or takes too long on the PC is stopped and marked "stuck"; its numbers up to
  then still count.
- One sim at a time (its own lock, `tools/dl/locks/sim.lock`). A lock left by a sim that was killed is released by the
  next one; the Sim tab offers **Release it** for a lock with no owner.
- Close the Level Editor and start it again once (`tools\level_editor.cmd`) to get the Sim tab's server part: an
  editor started before pass 77 says so on the tab.

### For scripts

    python tools/sim_batch.py --out tools/dl/sim/runs/<name> --hero drifter --players 10 [--workers 0] --limit 1500 \
        [--board 1.5 | --talents grit:AAB,study:BB [--board-label "my save"]] --death end --seed 1 [--map red_canyon] \
        [--fps 60] [--no-fast] [--note "..."]
    python tools/sim_batch.py --aggregate tools/dl/sim/runs/<name>     # the players' files again into result.json
    python tools/sim_batch.py --out <dir> --synthetic                  # made-up runs (the selftest's and the page's fixture)

`--talents`: one entry a talent, its picks one letter a rank (A its first form, B its second), as the save keeps them;
it wins over `--board` (a preset: 0, 1.5, 3, 6 ranks a talent). `--workers 0` = auto. `--no-fast` plays without the
runner's sim mode. The runs get `board=`, `talents=` (only with ranks), `death=` and `fast=0/1` (when the runner has it);
an older runner that knows neither `talents=` nor a policy is refused before anything plays (`caps_problem`).

A sim's folder `tools/dl/sim/runs/<id>/`: `settings.json`, `progress.json` (where every run is, rewritten every
second or two), `result.json` (the averages; rewritten after every finished run, `meta.partial` until the end),
`head.json` (what the history lists), `players/pNN.json` (each run as `sim_run.gd` wrote it, keys in
`tools/dl/p77/keys_SIMRUN.md`) and `players/pNN.log`. `tools/dl/sim/speed.json` keeps the measured speed of the last
full sims (play seconds a wall second per run: the middle run's and the slowest run's, `slow`; the boot; how many at
once; `fast` = the sim mode on). `result.json`: `t` (0..T play seconds), `playing`, `series`
{name: {mean, p10, p90} (bands for hp, dps, level, press_hp, press_dmg, danger, near3, near6), dps (5 s), dps_raw,
danger / danger_net (% of max HP a second, 5 s), keep_up / boss_s {median, p10, p90, n} (seconds of DPS), trouble (% of
runs), kills_ps / spawned_ps / hits_ps (10 s), deaths (over every run), clock / stage {median}}, `breakdowns` {dmg_by,
kills_by, gold_by, took_by, healed_by, alive_by, held_by: {kind cum|level, order, mean {id: []}, score}}, `markers`
{stages [{stage, t, n, min, max}], bosses [{id, occurrence, start, end, n, beaten, fight_s, mult, hp}], deaths,
revives}, `players` [{k, seed, ok, end_reason, end_t, wall_s, boot_s, rate, deaths, revives, level, kills, gold, xp,
dmg, build, assists}], `summary`, `names`, `settings` (with `talents`, `board_label`), `rules`, `meta` {started, ended,
wall_s, partial, players_done, players_total, map_rev {sha, saved, name}, version, sync, job, unlocks, assists,
board_differs, sim_mode (what the runs played: false = everything drawn)}.

The routes (`sim_io.py`): `GET /api/sim/settings` (the form's choices and defaults, the talents and their presets with
"my save", the runner's capabilities, the processors, the measured speed and its words, the saved map's code), `GET
/api/sim/status` (the sim queued or running: its job, its progress.json, the lock), `GET /api/sim/history`, `GET
/api/sim/result/<id>`; `POST /api/sim/run {settings}` (queued as a job of kind `sim`; 400 for bad settings, 409 while one
is queued or runs or when the runner cannot play them), `POST /api/sim/settings`, `POST /api/sim/<id>/keep {keep}`,
`POST /api/sim/<id>/delete`, `POST /api/sim/<id>/cancel`, `POST /api/sim/unlock {force}`. The job kind `sim` (jobs.py
SPECS: hero, players, workers, limit, board, talents, board_label, death, seed, map, fps, note, fast) runs on its own
lane `sim`. The charts' definitions are plain data in and out (`sim_model.js` `charts(result, compared, opts)`), so the
run dashboard can reuse them.

Self-test: `selftest_SIM77.py` (the averaging by hand on three tiny runs and on made-up ones; round 2's board, death
policies, at once, the runner's capabilities and arguments, my save, the derived difficulty series and the medians; the
snapshot's copy rules and import reasons; the sim lock; the job kind with a real run of the driver and a cancel; the
routes; the page's maths under Node, its sections and its wiring).

## Pass 81: pacing a row

A roster row's **Pacing** (the row form): Continuous (as before: drawn into the cap by its weight) or Waves every N s (`every`, `count` per wave, `offset`, Respect the cap, Also continuous). The Timeline draws yellow etches on every row: a line where it is drawn continuously, a tick at each wave; a `waves[]` block shows a tick at each burst; ticks under 3 px apart are thinned. Keys and rules: docs/waves_schema.md "Pass 81", BALANCING.md §28.PACE.

## Pass 84: the Timeline in sections, one way to spawn

Garry (2026-10-16): "spawning options are important to me ... better add too many controls than too few"; "I would
prefer the charts ... to be not too abstract"; "allow for the option to collapse some sections ... easy to tell where a
section was collapsed"; "Mark somehow (in a subtle way) which sections are view only, and which are tools for editing".

**Sections.** The Timeline tab is a stack of sections, each a bar (a chevron, its mark, its name, a line of what it is,
its own controls). A click on the bar collapses it: the bar stays where the section was, hatched with a dashed frame, a
summary of what it holds ("On screen · peak 260 alive at 1:53 · cap full 15 times") and *collapsed: click to open* in
yellow. Each map remembers its sections in the browser; **Collapse all / Open all** sit in Ruler and controls; the ruler
always stays. The inspector folds to a hatched strip (⇥ at its top right).

| Section | Mark | What it holds |
|---|---|---|
| Ruler and controls | pencil | the ruler (always shown), the marks' legend, collapse all / open all, the estimate's kill rate / boss / portal boxes, **lifetimes from the Sim**, **Sim to show** |
| On screen | eye | creatures alive per second: the estimate (the hell channel red on top), the Sim dashed, the cap in bodies, the floor dotted; red where the cap is full (hover: who starves) |
| Challenge | eye | seconds of the hero's damage to clear the screen (crowd HP ÷ his DPS), or health bars lost clearing it (HP × bite ÷ (DPS × EHP), the Sim's `challenge`); zones easy / fair / hard (two boxes per measure); the Sim's line and its deaths |
| Composition | eye | % of the crowd by creature (on screen, or spawned in the past N s; estimate or Sim) |
| Spawned so far | eye | the pass 57 running total |
| Spawn rows | pencil | every row, grouped by stage / role / both / none (each group folds), coloured by role or creature; quantity, HP / ATK at the start, badges |
| Events | pencil | bosses, Elite mini-bosses, the portal after each boss (click: its settings), specials, mutation offers |
| Curves | pencil | cap, **Floor** (new), Actual HP × (eye), HP ×, Actual ATK × (eye), ATK × |
| Warnings | eye | the estimate's findings with **Go to**: cap full and who starves, rows that never spawn or never make 1% of what spawns, the crowd's HP doubling in a second, a floor above the cap, identical rows overlapping |

**The marks.** An eye and a darker, recessed background: view only (worked out from the map, the estimate, the Sim).
A pencil and the normal surface: editing. Lanes carry the same marks on their labels; the inspector's groups too.

**The charts say what they are.** Each view section starts with *What is this?*, a legend naming every line and a box
*How it is worked out* with the recipe and the units (tools/level_editor/timeline_model.js `RECIPES`).

**One way to spawn.** Swarms, coloured elites and Elites every are spawn rows (lane SPAWN plays them in the game and the
sims; keys in docs/waves_schema.md "Pass 84"): Pacing Continuous / Waves every N s (Every may be [min, max]) / Once;
Creature one / a list with pick weights (`enemy_weights`) / the roster draw; Elite modifier, Special, Banner, Ring
radius, Chance, Jitter, Role, Name. An old map's swarm / elite / elite_every events and `waves[]` blocks are read as rows
when the map loads (Model.convertLegacy; the game plays both alike) and Save writes the rows. **+ Row** offers each kind
(continuous, waves, once: a swarm, a coloured elite, Elites every, a special); **+ Event** the bosses and Elites.

**The inspector** shows a row in groups that fold (each remembered): Schedule, Creature, Where and how, Presence, In
the estimate (its numbers at its start and a mini-chart: its spawns each second and its HP over its life), Overrides
(Body with Size × / Radius ×, Colour, Attacks, Ranged and Charge with every key of their blocks, and new: Kamikaze,
Artillery, Sniper, Flee on hit). Header: Duplicate, Delete, **Split at <cursor>** (the second part's numbers fixed
afresh there), **→ once / → waves / → continuous**. Not overridable per row (the game reads them from the creature
only): the brain, the death burst, a caster's spells.

Self-test: `selftest_TIMELINE84.py` (the view maths under Node against the estimate, the fields and their help, the
conversion on load and no churn, the page's words).

## Pass 87: stage tabs

The Timeline has a tab strip: All | Stage 1 | Stage 2 | ... | + Stage. A stage tab shows that stage's window (the ruler counts the stage's own clock) and its card in the inspector: name, difficulty line, description, picture, length (keep or stretch the later stages, with a confirm), boss, look (filter colour, strength, the creatures' share `actors`, a swatch) and hell. + Stage appends one; deleting asks. Settings has an Endless block. Reload the page after the pass 87 migration before saving the map (an old page writes the old timeline back). Keys: docs/waves_schema.md "Pass 87".

## Pass 93: the Drivers tab (see a driver, with its frame numbers)

A **driver** is the motion a video model paints over: a 3D model's own walk or death, rendered frame by frame. A look's
recipe names it (`pose_drivers.<view>` and `pose` / `pose_front` for the OpenPose walks, `drivers` and
`death_drivers` for the depth walks and deaths of creature_ctl, `ctl_drivers.<view>` for a puppet look) and the painter
follows it frame for frame.

**Where they are kept.** Every driver is a folder `tools/dl/drivers/<name>/` (on this PC
`D:/_projects/88fits/tools/dl/drivers/`), with one folder per game view inside it: `front`, `fd` (front three-quarter),
`side`, `bd` (back three-quarter), `back`. In a view folder:

| file | what it is |
|---|---|
| `driver_00.png`, `driver_01.png`, ... | OpenPose stick figures, one per frame (the heroes' and the humanoid creatures' walks; tools/pose_driver.py from a Mixamo FBX). `poses.json` holds their keypoints. |
| `ctl_00.png`, `ctl_01.png`, ... | depth frames of a 3D model, one per frame (the creatures' walks and deaths; Blender: light = near, dark = far). |
| `clay.png` | the model standing, in grey clay (what the painters copy) |
| `look.png` | the model in its own colours, when it has them |
| `clay_06.png`, `clay_12.png`, ... | a one-shot's (a death's) clay at that frame |

Beside the view folders: `meta.json` (what made it: the model, the clip, the frame count, loop or once, the tool's
settings), `<view>_sheet.png` and `all_sheet.png` (contact sheets of a pose driver). A folder named
`<driver>_soft10` (or `_soft10b`) is gen_ctl's softened copy of a depth driver (a look's `ctl_soft` / `death_soft`,
pass 92): it has no meta.json. The **frame index** is the number in the file name, counting from 0: `ctl_07.png` is
frame 7, and `death_keep`'s numbers are these. Outside the editor any picture viewer shows them: open a view folder in
Explorer and step through it (Windows Photos goes from file to file with the arrow keys).

A creature_ctl look's **painted death** (what Wan painted along the death driver) is kept in
`tools/dl/ai_anim/<creature>_<code without the dash, lower case>_death/` (`bull_beetle_bbc_death` for BB-C):
`full_00.png` ... `full_24.png` every painted frame (same numbering), `out_NN.png` the frames death_keep kept,
`cycle.json` the keep it was cut with.

**The Drivers tab** (beside Jobs) lists every driver as a card: it plays while the mouse is over it, its kind
(OpenPose, depth, death), the frames each view has, what made it, its date and size, and the looks that use it (green:
the look the game plays). Search by name, model, clip or the creature / hero using it; filter OpenPose / Depth / Deaths
/ Used / Unused; sort by name, date or size; Refresh reads the folder again. A click opens the **viewer**: one view at
a time (the tabs), the frame large with its index on it, play / pause (Space), one frame back and on (arrow keys),
first / last (Home / End), a scrub bar, the speed, loop on or off (a death starts with loop off: it plays once and
stops on the last frame), the clay and look stills beside it (a pose driver: its contact sheet), every frame below as
a numbered sheet (click one to show it), what made it, meta.json, the looks using it, and the folder with **Copy path**
and **Open folder** (the server opens Explorer on that folder; only folders of the library).

**Beside every driver field** (a look's recipe, Art words, the job form, the driver library of a tweak job) a small
frame plays while the mouse is over it, and **preview** opens the viewer on that driver and that field's view. A
finished driver job's card has **▶ preview <name>**.

**death_keep** (creature_ctl's death frames kept) is typed (`1, 4, 7, ...`) or picked: **Pick frames…** opens the
viewer on the death driver with every frame numbered; a click keeps or drops a frame (the small green number is its
place in the kept order, which is the order the strip plays them), **play the kept frames** plays only those, as the
strip's death will, **even 8** spreads eight over the clip with the last one in, **the default** puts back
`1 4 7 10 13 16 20 24`, **clear** empties the field (the default applies). When the look's death has been painted the
viewer shows the painted frames by default (switch *show* to the depth driver), and the field's tiles show the kept
painted frames; a new keep is cut again from the cached clip with no render. A death painted along another driver is
not shown as this one's.

Routes (tools/level_editor/drivers_io.py): `GET /api/drivers` (every folder with frames, meta.json or not: `counts`
per view, `first`, `path`, `made`, `plays`, `death`, `parent`, `size`, `files`, `used_by`, plus the pass 66 keys;
`frames` is now the frame files of its first view), `GET /api/drivers/<name>` (+ `view_detail`: every frame's index
and URL, the stills), `GET /api/painted_death/<enemy>/<code>`, `POST /api/drivers/<name>/open` `{view}` and
`POST /api/drivers/open` (the library). methods.json marks death_keep with `picker: "frames"`, `frames_of`, `view`.

## Pass 95: Frames (every frame of a look, its versions, repairs with VACE, one export)

Garry: "a way to view every single frame and choose which ones to regenerate ... available to existing assets too ...
options per frame (the history of other generated frames) ... frames from other Looks ... several frame changes in
one go without needing to wait for the save export thing to finish."

**Frames…** sits on every look card (Enemies and Heroes tabs, every look that has a strip, painted this pass or years
ago) and on a landed look's job card. It opens the **Frames view** on that look:

- **The tabs**: one per animation x view the strip holds (`run · side`, `die · front`, ...), with a green count of the
  frames staged in it and a pin where a choice is pinned.
- **The stage**: the frame large with its **slot** number (its index in the animation, 0-based: the number everything
  here uses), the previous and the next frame beside it, the driver's frame under it (what the clip was walked on; a
  repair follows it), play / pause (Space), one frame back and on (arrow keys), first / last (Home / End), the scrub
  bar, the speed (the game's own rate for that animation), loop, zoom 1x-3x.
- **The sheet**: every frame numbered. Click one to show it; shift-click a range; ctrl-click to add one. Badges: a
  green tick = staged, a pin = pinned, ≠ = the installed strip differs from the pinned choice, ⚠ = a flag (hover for
  the number and the rule).
- **The versions** of the shown slot, newest first: `SP-B-1` is the frame the strip was installed with, `SP-B-2` the
  first repair of that slot, and so on (the n-th version of that slot in that look). Each says what made it (the
  strip, VACE with its seed, a copy from another look) and when. **Click one to stage it**: the preview plays it at
  once, the tab counts it, nothing is written. **Pin** keeps a choice through later re-rolls of the look; **Unstage**
  is Undo (back to the selected one); **large** opens it big.
- **Repair with VACE…** on the selected frames: the words (the clip's own by default), a seed, the window (a short
  loop goes in twice plus its first frame, 25 frames, the chosen ones masked in both passes and taken from the
  second; a long one once; a one-shot as it is), the guide (the driver's frames fitted onto the kept figure, or
  **free**: filled from the neighbours alone). Queue = a `frames_repair` job on the comfy lane (the Jobs tab shows
  it); when it lands, the new frames appear here as versions and are **staged at the landing** (unless the slot is
  pinned, or you staged a choice on it meanwhile: then added, not staged, and the card says so; the repair process
  itself never writes the staging, so there is one writer). **Fill from neighbours…** is the same job with the guide
  set to free (no RIFE / FILM model is installed on the server). Every frame of the animation that is not chosen is
  kept: the model sees the whole cycle and paints only the masked ones. **The rule per method** (`methods.json`
  `repair`: `vace` yes / conditional / no, `fill` cell / still / none): a procedural animation (no clip cache, no
  driver: an idle, an attack, a hit, a hop walk, a recolour) is **refused** by the route and shown so by the button;
  the still is the thing to fix there. Tick **fill freely anyway** in the form to send it as a free fill on purpose.
- **From another look…**: every other look of the asset that has this animation, its versions of the same slot(s),
  with the warnings that matter (other cell size, other frame count, another driver). A click copies that frame in
  as a new version of this slot (never a link: the other look is not touched), staged.
- **Ask the local vision model**: LM Studio looks at the shown frame and answers a short JSON (limbs counted, broken,
  ghost, colour, a note). Honestly labelled: it cannot count limbs reliably (pass 92's lesson); it is a hint beside
  the deterministic flags, which are also hints: **empty** (the figure under 0.4% of the cell), **footprint** (its box
  outside 0.72-1.35 of the group's median), **jump** (it differs from both neighbours 1.7x more than they differ from
  each other), **seam** (a loop's last-to-first step over 2.2x the median), **silhouette** (it overlaps the driver's
  frame by under 50%, boxes aligned). They flag SP-B's side slot 0 and not its ghost-leg frames 3-5: ghost legs sit
  inside the silhouette. Your eye stays the judge; the sheet shows every frame.
- **Undo all** drops every staged choice of the look. **Export (n)** is the one write: a `frames_export` job packs
  the strip again from the staged and selected versions with the pipeline's own packing (the same cell placement,
  outline and order; nothing in the game changes shape), keeps the old strip under
  `tools/level_editor/backups/<id>/frames_<stamp>_<file>.png` (the newest 30 per asset kept), writes the look's
  entry (**without** the NEW mark: the frames are your own choice, not a landing), then the usual import job. The
  staged choices become the selected, pinned ones. **Exporting the look the game plays asks first** (a confirm box
  naming it; the route refuses without it). An export queued while a repair of the same look runs **waits** for it
  (the card says held). If the entry cannot be merged, or the import after it fails, the export is **rolled back**:
  the old strip is put back from its backup, the old entry merged back, and your choices are **staged again**, so
  nothing you chose is lost (the card says "rolled back"). A reload of the page keeps everything: the choices live in
  the store, not the page.
- **Where frames live** (the help line under the view): the game plays the strip under `game/content/<folder>/<id>/`;
  the video model's frames are in `tools/dl/ai_anim/<key>/` (`out_NN` kept, `full_NN` all); every version of every
  frame is in `tools/dl/frames/<kind>/<id>/<CODE>/<anim>/<view>/slot_NN/`; the old strip of every export in
  `tools/level_editor/backups/<id>/`. The versions drawer offers **Delete** on a version nothing refers to (never the
  selected, staged, exported or copied-from ones); **From another look…** lists removed looks too, marked.

**Where it is kept**: `tools/dl/frames/<kind>/<id>/<CODE>/<anim>/<view>/` is one group (an animation x a view);
`slot_NN/vNNN.png + vNNN.json` one version of one frame (its id is a hash of the picture; the json its provenance:
source, seed, prompt, model, workflow, time, who chose it, what the vision model said); `selected.json` the choice
per slot; `staged.json` what the next Export packs; `exports.json` every export. Nothing there is deleted by the
tools. A version is a **cell** (a finished strip cell) or a **raw** clip frame (640 px, keyed, what the video model
painted before artkit placed it): the group's **fit** (cell = canvas x s + o), measured from the installed cells and
their clip frames (`tools/dl/ai_anim/<key>/out_NN.png`), places a raw frame exactly as the pipeline placed the clip's,
then punch, the look's outline and its post filters (gen_ctl's drop_islands and no_green, a recipe's remap_hues). A
look painted before the clip cache was kept has cells only: a repair then puts the cells back on a canvas (softer
frames; the sheet says so).

**Every method** (what the store finds, the rule the route and the page read from `methods.json` `repair`, the
repair path, and where the store hook is):

| method | frames come from | store twin (raw) | guide a repair follows | rule (vace / fill) | repair path | store hook |
|---|---|---|---|---|---|---|
| creature_ctl (walks) | Wan Fun Control along a depth driver, the second stride (`<id>_<code>_ctl_<view>`) | yes (out_NN) | the driver's `ctl_(n+k)`, fitted on the kept figure | **yes** / cell | VACE (proven on SP-B's side walk) | `merge_look` -> `on_look_landed` (a job); `hook_after_save` after gen_ctl's `strip.save` (a hand run) |
| creature_ctl (death) | one-shot Fun Control along `death_drivers`, `death_keep` frames | yes | `ctl_keep[k]` | yes / cell | re-pick `death_keep` first (no render), then VACE | the same |
| creature_pose2 (front / back walks) | Wan Animate on an OpenPose driver (`<ak>_pose_f/_b`) | yes | `driver_(k+1)` | conditional / cell | VACE (a benchmark decides) | `merge_look`; `hook_after_save` after gen_art's `strip.save` |
| creature_free2 / creature_free8 (walks) | a free Wan clip cut by silhouette period (`<ak>_walk_<view>`) | yes | none (free fill) | conditional / cell | VACE, free | the same |
| creature deaths "clip" (a fall) | first-last-frame clip, 8 picked by silhouette (`<ak>_fall`) | no (the picks are not kept) | none | conditional / cell | VACE in cell space, free | the same |
| creature deaths "pose:<drv>" | Wan Animate one-shot | yes | — (not mapped) | conditional / cell | VACE, free | the same |
| hero_pose5 / hero_fit (runs) | Wan Animate on `pose_drivers.<view>` or run (`<ck>_pose_run_<view>`) | yes | `driver_(k+1)` | conditional / cell | VACE (a benchmark decides) | `merge_look`; `hook_after_save` after gen_art's hero `strip.save` |
| hero_puppet (runs) | Fun Control on `ctl_drivers.<view>` (`<ck>_ctl_run_<view>`), else as hero_pose5 | yes | `ctl_(n+k)` | **yes** / cell | VACE on the depth views | the same |
| free hero clips (the fallback) | a free Wan clip (`<ck>_run_<sfx>`) | yes | none | conditional / cell | VACE, free | the same |
| creature_proc, creature_pictures, idle / attack / hit / tilt deaths of every method | artkit from one painting (bobs, leans, a tilt) | no | none | **no** / still | history, copy from another look, export; the route refuses VACE unless "fill freely anyway" | the same (a procedural group has no clip and no driver: `repairable` says so) |
| recolour | the source look's strip recoloured | no (cells) | the source look's | no / cell | repair the source look and recolour again; history, copy, export | `merge_look` (the recolour job's landing) |
| hero hit / die / cheer | painted stills with a procedural wince / fall | no | none | (the method's) / still | history, copy, export | the same |
| an imported or hand-made strip (no method) | the strip itself | no | none | conditional (no rule) / cell | history, copy, export; VACE free fill in cell space | the retrofit when Frames… opens it |
| front_from_picture, item icons, badges, titles, drivers, 3D refs | no animation | — | — | no / none | — | — |

The store hook is one place for jobs: the server's `merge_look` (every method's landing, re-rolls, recolours and
the export itself go through it) calls `frames_io.on_look_landed`, which registers the look again: new cells become
versions (`reroll`), selected unless the slot is pinned (a pinned slot keeps its choice and shows ≠ until the next
Export). A **hand run** of `gen_art.py` / `gen_ctl.py` (no job, no merge) calls `frames_store.hook_after_save` right
after `strip.save`: a look the store knows is registered again from the strip just saved (with the run's own counts),
and a warning names the pinned frames the run replaced ("Export is the writer for this look"). An existing look is
registered the first time Frames… opens it (the retrofit); nothing is written under game/ until Export.

**Hardening (pass 95 resume, after the tooling assessment's AN-01..AN-14)**: one writer of `staged.json` (the repair
process returns its versions with `stage_wanted`, the landing stages them); the shrink guard of
`artkit.place_clip_frames` in `Group.to_cell` (a repaired figure larger than the cell at the group's fit is shrunk
about its floor, never cropped; the version says `shrunk` and the flags raise `footprint`); every installed version
records `driver {name, ctl_sig}` and the clip's `wan`, so a repair made on an older driver can be told; `store_version:
1` in every `group.json`; a confirm before exporting the look in play; an export waits for a running repair of the same
look; rollback on a failed merge or import; no NEW mark on an export; retention: never a referenced version deleted
(`delete_version` refuses what a selection, a staging, an export or a copy's `from` names), 30 strip backups per asset,
repair sheets 90 days, raws kept; the picker marks removed looks (their frames stay copyable from the store).

**Numbers** (SP-B's side walk, 12 frames, the R9700): the model pair installed in 9 minutes (2 x 17.3 GB fp8);
ComfyUI loads each as `WAN21_Vace`, 16.5 GB, fully on the card; one repair of a 25-frame window at 640 px: 137-143 s
(plus the lock wait); the fit measured at 0.5 px residual; the retrofit of a 13-animation look: 3.4 s.

**Scripts**: `python tools/frames_store.py register|info|flags|export <kind> <id> <CODE> [<anim> <view>]`;
`python tools/vace_repair.py --kind enemy --id desert_spider --code SP-B --anim run --view side --slots 3-5,9
[--prompt ...] [--seed N] [--window auto|single|double] [--guide driver|free] [--dry-run] [--out DIR]`. Routes:
`GET /api/frames/<kind>/<id>/<code>[/<anim>/<view>[/others]]`, `POST .../<anim>/<view>/stage|unstage|pin|copy|repair|ask`,
`POST /api/frames/<kind>/<id>/<code>/export|register`; pictures `/dl/frames/...`. Jobs `frames_repair` (comfy lane)
and `frames_export` (local lane; its entry lands like a look's, then an import). Self-test: `selftest_VACE95.py`.

## Pass 96: the request card and the frame layer's rules

Garry's decisions on the tooling assessment (revision 2, points 1, 2, 4, 5, 10, 11, 12) written into the Frames view
and the Jobs tab; nothing older changed its behaviour (the Frames view, the Drivers tab, the job cards and every
dialog work as before; `selftest_VACE95.py`'s 130 checks are green, five of them re-pinned on purpose: Delete is gone
and the hook re-applies instead of warning).

**The frame label** (decision 1): every place the page or a result names a frame says `SP-A / Run / Side / Frame 07 /
v2`: the look, the animation, the view (`Front`, `Front ¾`, `Side`, `Back ¾`, `Back`), the frame (the 0-based slot the
sheet numbers, zero-padded) and the version (`v2` = the second version of that slot). One formatter writes it
(`frames_store.label_of`, `FramesModel.frameLabel` in the page); every served version and slot carries it as `name`
(the drawer, the picker, the staged list under the sheet, the stage line, the job card, `result.json`'s `names`, the
summary). The record's short `label` (`SP-A-2`) stays for scripts; identity is still the content hash.

**One confirmation for every export** (decision 5): Export on ANY look with an installed strip (not only the one the
game plays) first shows one box listing the whole staged batch: every changed frame as a before / after pair with its
line (`Run / Side / Frame 07 <- SP-A / Run / Side / Frame 07 / v2 (VACE)`), the flags the change raises or clears,
whether the game plays the look, the backup folder; the pinned choices the strip does not show yet are listed too
("a pinned choice re-applied"). One click (**Export all N**) sends `confirm: true` for all of it; the route
(`POST /api/frames/<kind>/<id>/<code>/export`) refuses without it and answers the batch. `GET
/api/frames/<kind>/<id>/<code>/batch` is the same batch without queuing; the request card's Approve opens the same box
(`Frames.confirmBox`).

**Pinned frames are never overwritten** (decision 4): when a job's strip lands on a look with pinned slots (a re-roll,
a repaint), the landing registers the new cells as versions and **queues a `frames_export` that packs the pinned
versions back** onto the pinned slots with the new cells everywhere else, with no confirmation (it restores Garry's
own choice; F3's N1 default) and the card note "re-applied N pinned frames (export job ...)". A hand run of
`gen_art.py` / `gen_ctl.py` does the same **in-process** right after `strip.save` and before the JSON dump
(`frames_store.hook_after_save` -> `reapply_pins`; the run's own strip is kept under `tools/level_editor/backups/<id>/`,
the log says "re-applied N pinned frames"). A landing that changed the frame count or the cell size reports the pins
that no longer fit ("N pinned frames could not be re-applied: the animation has M frames now" / "the cells are P px
now"), moves them to the group's `lost_pins` (shown in the view's info block) and keeps every version.

**No deletion of versions** (decision 10): the Delete button is gone; `delete_version` and `POST .../delete` refuse
always (`retired: true`); every version of every frame is kept for reuse. (The strip-backup cap of 30 per asset
stays: every replaced cell is a registered version.)

**The picker's filters** (decision 2): From another look… filters by look, animation and view (one group fetched at
a time; another animation or view only on purpose, with an amber warning), time (the last day / week / month) and
source (installed, re-rolled, VACE, copied, repainted, old roll, archived; "only raw"), newest first; the marks
"removed look", "old roll" and "archived" show where the store has them (the import of old rolls and archived strips
into the store is Phase 4: not built yet).

**The Jobs tab** (decision 11, UI-04 part 1 and UI-02 part 1): a running card is no longer rebuilt every poll (the
card signature has no clock in it; the elapsed time ticks on its own 1 s timer), and the page's own state lives apart
from the server's records (`Jobs.S.ui`, a Map per job id): a picked candidate, an open re-roll panel, the spec / command
folds and the log's scroll place survive a poll that rebuilds the card. A still appears on the card the moment its
`render ... ok` line is printed (not at the next 5 s cache check). The header carries an honest connection line:
"connected · last answer hh:mm:ss", "no answer from the Level Editor since hh:mm:ss (...): retrying every 15 s",
"the server answers but has no jobs API", or "another editor runs the queue (...)": four different things, said
apart.

**The request card** (1.7; decision 12 keeps the loop's state on the look card for a later pass): a **Requests**
group at the top of the Jobs tab, one card per art request (`GET /api/requests`, `tools/level_editor/requests.py`): the
state chip, `iteration k of n`, the budget bars (re-rolls, repair rounds with the worst group, lane time, evaluator
calls, cloud $) as spent of budget, the last operation and why, `waiting_for` in words, the one-paragraph summary,
the findings beside the latest job's outputs (a badge per failed item with the rule text and the model's name, the
gates line with the model calls and dollars; from `<job>/findings.json`), the provisional winner's sheet, the
request's jobs folded underneath (their own cards stay in their groups; a click scrolls to one), and the buttons the
state allows: **Pause / Resume / Step / Stop** (and Cancel), **Approve…** (the batch box over the provisional look,
then `approve {confirm: true}`), **Reject…** (a reason, kept with the rejected versions), **Pick another…** (a candidate
look, or the Frames view on the provisional group to stage or pin a version by hand). A server without the requests
route shows no group and nothing else changes. The page-free parts live in `jobs_model.js` (`sig`, `elapsedText`,
`connectionLine`, `requestFold`, `budgetBars`, `findingsBadges`), checked under Node by `selftest_PAGE96.py`.

**Keys**: `tools/dl/p96/keys_PAGE.md`. Self-test: `selftest_PAGE96.py` (the batch's shape and refusal, the pin
re-apply on a fake landing with pinned slots and with a changed slot count / cell size, the hook's in-process re-pack,
`label_of`, `delete_version` refusing, the filters' maths, `sig` without the time term, the harvest on a canned line,
the connection line's words, the request fold).

## Pass 96: the loop (the evaluator, its tiers, the planner and the commands a request may run on its own)

A request (REQ's `art_request.py start`, the Jobs tab's request card) runs the **Auto-iterate loop**: after every job of
the request lands, the step function asks the planner for ONE op, validates it, runs it through the page's own functions,
records it, and goes on until the hard gates pass or the budget is spent; then it waits for Garry's one approval. What
it does on its own, what it never does, and where every call is written down:

**The evaluator** (`tools/vision_eval.py`, one adapter for every eye):
- **Tier 0, deterministic, free, on every frame**: the Frames view's flags (`empty`, `footprint`, `jump`, `seam`,
  `silhouette`, each with its number and rule) on every animation x view of the look, and gen_art's geometry on the
  paintings (`empty`, `touches-edge`). These are the **hard gates**: the loop's `pass` is theirs alone.
- **Tier 1, the local eye, free**: LM Studio on this PC (the configured `qwen2.5-vl-7b`), shown the flagged frames plus
  one clean frame a group (three times the size on grey, as the Ask button shows them), asked the fixed `frame_blind`
  rubric. Its answers are **advisory** (a badge with the model's name): it cannot count limbs (pass 95's measurement),
  so nothing it says passes or fails a frame.
- **Tier 2, the cloud eye, metered**: a pinned cheap Claude model (the Messages API, the key only from the git-ignored
  `tools/keys/anthropic.env`; never the environment) or Gemini (the official API, `tools/keys/gemini.env`; built,
  untested: no key exists) on **one numbered contact sheet** per decision point, only when the request's `cloud_dollars`
  is above 0 and the tiers disagree or a hard finding needs confirming. **$0 = off** (the default). Advisory too.
- **Honest rules**: every picture is copied to `img_<n>.png` in a temporary folder before any call and the backend gets
  bytes only; the question is a fixed rubric from `tools/qa_rubrics.json` (no look note, job title, recipe word or file
  name: the label leak); a per-model answer budget (`gemma` 1200 tokens, the 7B 220, Claude 2048: a thinking model given
  220 returns nothing); an empty or unparsable answer is **no verdict**, never ok; answers are cached by
  sha1(picture) + rubric + model under `tools/dl/qa/cache/`.
- **The ledger** `tools/dl/qa/ledger.json`: every call (backend, model, pictures, ms, tokens, dollars, request id,
  rubric), every refusal and why. Ceilings: the request's `cloud_dollars` and the global
  `cloud_ceiling_dollars_per_day` of `tools/level_editor/request_defaults.json`; a call that would pass either is
  refused and logged; an unpriced model (Gemini until G3 measures it) is refused under a ceiling. The price table
  (dated) lives in `vision_eval.py`. `python tools/vision_eval.py --ledger` prints the totals, `--keys` says which
  key files exist (today: none).
- **The findings record** `<job>/findings.json` (the `evaluate` job kind, the local lane, no lock): `items[]` with
  `kind` measured / model / human, `field`, `value`, `ok`, `rule`, `group`, `slot`, `box`, `model`, `tier`;
  `gates {hard_failures, advisory, pass}`; the sheet `findings_sheet.png` (every frame, the flagged ones framed red);
  one summary line in the job's notes ("findings: 2 hard, 1 advisory (run/side: 3 jump, 4 jump); qwen... x3; $0.0000").
- **The old callers are unchanged**: `gen_art.qa()` asks the same question (the `still_gate` rubric, word for word) with
  the same request body and gets the same fields back; `--skip-qa` still skips; the Frames view's Ask button asks
  `frames_io.ASK` (= the `frame_ask` rubric). One change inside `gen_art.render()`: the geometry runs **before** the
  model, so an empty or edge-touching still fails on its numbers and never costs a vision call (the report gains
  `skipped_model`; under `--skip-qa` the report is exactly the old one).

**The planner** (`tools/level_editor/loop.py`, `next_op(record, findings)`, one op per iteration, cheapest first):
1. no fresh findings for the last landed job -> `ask` (an evaluate job; the findings are re-made after every change);
2. the hard gates pass -> `select_provisional` (the effective frames staged as the winner), then nothing more;
3. a hard finding on frames of a group with a clip and a driver -> `repair` of those slots (spans) at the method's first
   rung (`methods.json` `repair.profile` / `repair.escalation`, GATES's benchmark; built-in: single -> double ->
   reroll_view); when a repair of the same slots did not lower their hard count, the next rung; after the ladder, or
   when the group failed twice without improvement, `reroll_view`;
4. a hard finding on a painting (empty, touches the edge), or on frames of a procedural group (no clip, no driver: the
   still is the thing) -> `requeue` of the look job with words from the defect -> words table and a new seed;
5. the **plateau rule**: never the same op twice in a row on the same target;
6. a budget unit missing for the move -> the next move, else `select_provisional`.
The budgets (rerolls 2, repair rounds 2 per animation x view, evaluator calls 60, lane seconds, cloud dollars 0) are
REQ's; the step function counts every dispatched op.

**The commands** (`tools/level_editor/commands.py`): one shape `{op, target, args, why}` (unknown keys refused); the
Auto-iterate allow-list `requeue`, `reroll_view`, `repair`, `stage`, `copy` (within the asset), `ask`, `note`,
`select_provisional`, `stop`; **never** `export`, `install`, `default`, `approve`, `pin`, `remove`, `delete`,
`unstage`, a pinned slot, or anything outside the request's asset and look; Observe = no op; Step = the same verbs one
at a time. `validate` checks the schema, the mode, the target, the pins and the budget; `dispatch` runs the op
through the SAME functions the page uses (`jobs_call` requeue / edit, `frames_io.repair_job` / `stage` / `copy`, an
`evaluate` job) and answers a refusal without raising. **`select_provisional` stages, never pins, never exports,
never touches the JSON's `variant`**: the game cannot play anything the loop made until Garry's one confirm exports it.

**Keys**: the `evaluate` job's spec (`kind`, `id`, `code`, `groups`, `tiers`, `request`, `cloud_dollars`, `backend`,
`model`); `request_defaults.json` `tiers` (GATES) and `cloud_ceiling_dollars_per_day` (0 = the cloud tier off);
`methods.json` `repair.profile` / `repair.escalation` (GATES); `tools/keys/anthropic.env`, `tools/keys/gemini.env`
(git-ignored; `X_API_KEY=...` or a bare token). Dry runs: `asset_job --dry-run` now works for a `creature_ctl` look
too (its stand-in took no `init`), writes into the job's copy of the creature folder (`GEN_CTL_FOLDER`) like gen_art's
has since pass 71, and never tells the frames store (a dry run's stand-in cells used to register as versions).

## Pass 96: requests (one command from Claude, the loop on its own, one approval from Garry)

**What Claude types.** `python tools/art_request.py start --kind enemy --id desert_spider --code SP-G --from SP-B --goal "a
cleaner side walk"` (stdlib; it finds the running Level Editor through the jobs lock's note, or `--editor`; `--code` absent
= the next free code, created as a stub entry whose recipe copies `--from`; `--rerolls N --repair-rounds N --minutes N
--evals N --cloud-dollars X` set the budget; `--mode auto|step|observe`; `--prompt`, `--appearance`, `--word key=value`
fill the brief). It prints the request id and the page link. Then `status <rid>` (one line: the state, iteration k of n,
the running job, the budget line), `result <rid>` (the paragraph and the paths; **"waiting for Garry's approval"** while
it is, exit 2; exit 0 only once the export's import landed), `sheet <rid>` (the review sheet's path), `cancel | pause |
resume <rid>`, `list`, `job <job id>` (`GET /api/job/<id>/summary`: state, stage ticks, hard / advisory counts, output
paths, the sheet, one paragraph; never a log or a picture). There is **no approve verb for Claude**: the approval is
Garry's, in the page (the request card's one box).

**What the record holds** (`tools/dl/jobs/requests/<rid>.json`, `v` 1): the goal; the **brief** (`art_prompt`, `appearance`,
`words`: immutable once created, the file refuses a changed one); the asset (`kind`, `id`, `code`, `method`, `from`); the
mode (`auto` = Auto-iterate, the default; `step` = one op per Step; `observe` = no loop: the landing waits for approval);
the **budget** (`rerolls` 2, `repair_rounds` 2 per animation x view, `lane_seconds` 5400, `evaluator_calls` 60,
`cloud_dollars` 0 = the metered tiers off; `tools/level_editor/request_defaults.json` `budget` over the built-ins, the
request's own values over that) and **spent** (lane seconds from the jobs' own clocks, evaluator calls and dollars from
the findings' `model_calls`, re-rolls and repair rounds from the ops); the state (`running`, `paused`, `waiting` with
`waiting_for` `approval` | `pick`, `approved`, `done`, `failed`, `stopped`, `cancelled`); the jobs (every one stamped
`request: <rid>`: the look, the imports that follow it, the evaluate jobs, the repairs, the export); the **iterations**
(`{n, started, ended, job, findings, op, gates, note}` plus what the planner noted beside the op, such as `hard_before`);
the **provisional** winner (`{code, groups: {"run/side": {staged: [..], pinned: [..]}}}`: a staged selection, never a pin,
never an export, never the JSON's `variant`); the **history** (every event: created, job, op, waiting, paused, resumed,
stopped, cancelled, approved, rejected, picked, provisional, note, done, failed); the **result** once done (`code`,
`strip_sha1`, `entry`, `import_job`, `export_job`, `changed`, `flags` and `verdicts` from the findings, `summary`, `sheet`,
`strip`); `toast` / `note` (the last human-facing line) and `stop_reason` (why it waits).

**How the loop runs** (`requests.step`, the frame; the body is lane LOOP's `loop.next_op` and `commands.validate` /
`dispatch`): a job of the request ends (any way: jobs.py's `_request_after` after `_after_exit`, a hand cancel, a worker
crash; an import merged into another's counts as ended with that one) -> the record is loaded -> nothing while the
request is paused / stopped / cancelled / done, or while another job of the request (not an import) is queued, running
or waiting for a pick (`waiting_for: pick`) -> the budget spent -> `waiting`, `waiting_for: approval`, a toast -> else
the planner is asked for ONE op from the newest findings; `None` = the gates passed (or nothing more to try) ->
waiting for approval; an op -> validated (a refusal is recorded and the request waits), dispatched through the page's
own functions, the iteration recorded, the budget counted; a direct op (a note, a staging, the provisional pick) lets
the step ask again at once (at most 8 in one step), a queued job ends the step until that job lands. Mode `step`
pauses after every op (Step runs the next); Pause lets the running job finish, then nothing more runs until Resume;
Stop cancels the request's queued and running jobs and keeps what landed (approve it, or cancel); Cancel cancels every
job of it, imports too.

**Garry's one confirm** (`POST /api/requests/<rid>/approve {confirm: true}`, the card's box): the batch = the
provisional look's staged frames and the pinned frames the installed strip does not show (PAGE's
`frames_store.staged_batch`); a NEW look is approved (`look_op approve`) and, with anything to pack, one `frames_export`
with `confirm: true` is queued; the request is `approved` until the export's import lands, then `done` with the result.
With nothing to pack it is done at once with the landed entry. `reject {why}` unstages the provisional look, writes
`review: {verdict: rejected, why, by: human}` on those versions (AN-13) and lets the loop go on (mode auto) or waits for
Step (mode step). `pick {code}` names another look of the asset as the provisional one; `pick {group, slot, version}`
pins that version (selected, pinned, marked as differing from the strip so the export re-applies it); then mode auto
continues from it, mode step waits.

**The routes** (`tools/level_editor/requests_io.py`): `POST /api/requests` {goal, asset, brief?, mode?, budget?} -> {rid,
fold}; `GET /api/requests` -> {requests: [folds]}; `GET /api/requests/<rid>` -> the fold (state, waiting_for, iteration
{n, of = re-rolls + repair rounds + 1}, budget, spent, budget_line, provisional, summary = one paragraph composed by
code, sheet, findings {job, gates, sheet}, jobs [{id, kind, state, title, stage, error}], history_tail, iterations,
result, toast, page); `POST /api/requests/<rid>/pause|resume|stop|cancel|step|approve|reject|pick`; `GET
/api/job/<id>/summary`. Errors: 404 no such request or job, 400 a bad body, 409 a state that refuses the verb (an
approve without confirm answers 409 with `needs_confirm` and the batch).

**The cancel fix** (WF-06c): `comfy.run` prints `comfy: prompt <id>` once ComfyUI took the graph; the job keeps it
(`comfy_prompt`); a cancel of a running comfy job sends `POST /queue {delete: [that id]}` and `/interrupt` only while
that id is the one running; a job without a recorded id gets `/interrupt` alone; **never `/queue {clear: true}`** (a
Stop on a request no longer kills a hand run's prompt).

**Nothing old changes**: a job without `request` runs exactly as before (no key on its record, the same import after
its landing); `GET /api/jobs?since=0` returns everything; the existing routes keep their answers (a job's record gains
`request` and `comfy_prompt` only when they exist). Tests: `selftest_REQ96.py` (the record, the budgets, the fold, the
step frame with a fake planner, the controls, approve / reject / pick, the routes, the CLI, the summary, the cancel
against a fake ComfyUI, the no-regression proofs) and `selftest_SLICE.py` (the whole sentence offline in about 10 s on
the real workers: a stand-in tool, the real `frames_store.export_look`, a fake evaluator and planner, `art_request.py`
over HTTP, Garry's confirm, `result`).

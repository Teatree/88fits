# The wave timeline schema (pass 53)

The map's `timeline_data` block (`game/content/maps/<map>/<map>.json`) drives `WaveDirector`. Everything that existed
before pass 53 still works unchanged; this page lists the whole schema with the pass-53 additions marked **new**. The
Level Editor (`tools\level_editor.cmd`) edits exactly this. After any hand edit run
`"$GODOT" --headless --path game --script res://tools/import_json.gd -- only=maps/<map>` (the editor's Save does it):
the game plays `<map>.tres`, which is generated from the JSON.

Every time is in **seconds of the run clock** (`Run.elapsed`), which runs only in the normal phase: it stands still
through a boss fight and the portal wait, so nothing dated inside those fires until the hero walks on. Stage 2 starts
at `stage_length`, stage 3 at `2 × stage_length`.

## Scalars (unchanged)
`stage_length`, `stages`, `stage_mults[]`, `cap_curve[[t, cap], ...]`, `cap_start`/`cap_per_minute`/`cap_max`/
`hard_cap`, `cap_per_stage`, `speed_per_stage`, `boss_cap_frac`, `portal_cap`, `portal_spawn_seconds`,
`portal_wave{count}`, `specials{from, interval[min,max], max_alive, pool[{enemy, stage}]}`, `hp_growth`, `hp_power`,
`creature_hp_mult`, `level_hp_per_level`, `level_damage_per_level`, `burst_min`, `burst_max`, `spawn_interval`,
`weight_late_t`, `pickups{per_kill, roster[{id, weight, hard_bias}]}`, `structures{count, min_spacing}`,
`path_times[[...], ...]`, `weapon_cap[]`, `passive_cap[]`, `colour_after_kills`, `contact_cap`, `xp_need_mult`,
`move_pace`, `hell_cap[]`, `endless_wave_seconds`, `endless_wave_mult`.

## Roster rows
```json
{"t": 0, "until": 300, "enemy": "skeleton", "weight": 10, "weight_late": 3, "channel": "hell",
 "pack": 5, "pattern": "pack", "variant": "SK-B", "stats": { ...overrides... }}
```
- `t` / `until` (optional): the row is drawn while `t <= clock < until`.
- `weight` slides to `weight_late` by `weight_late_t` (the director's `_roster_weight`; pass 54: `weights`, below, replaces
  the three).
- `channel: "hell"`: the hell channel's own cap (`hell_cap`).
- **new** `pack`: how many spawn together (default the creature's `pack_size`).
- **new** `pattern`: `"pack"` (the default: the pack at one point, spread out), `"scatter"` (each one at its own spawn
  point), `"single"` (one creature per draw, whatever the pack); pass 57: `"ring"` (the pack evenly round the hero at
  11.7 m) and `"in_front"` (each of the pack at its own point at the top of the screen, whatever `spawn_sides` says): see
  "Pass 57" below. Any other value plays as `"pack"`.
- **new** `variant`: the art variant code to spawn with (default the creature's own).
- **new** `stats`: overrides (see below).

## Waves (**new**)
Explicit windows on top of the roster, under `"waves": [ ... ]`:
```json
{"id": "w1", "name": "Opening skeletons", "t": 0, "until": 30, "count": 20, "burst": 5, "every": 2.0,
 "pattern": "pack", "respect_cap": true, "channel": "regular", "elite": "", "toast": "",
 "alts": [
   {"chance": 0.5, "enemy": "skeleton", "variant": "", "pack": 5, "stats": {"hp": 10, "damage": 15}},
   {"chance": 0.5, "enemy": "goblin",   "variant": "", "pack": 5, "stats": {"hp": 15, "damage": 10}}
 ]}
```
- From `t`, a burst of `burst` creatures every `every` seconds (the first at `t`), until `count` have come (0 = no
  total) or the clock reaches `until` (missing = no end). `id` and `name` are the editor's labels.
- `alts`: one of them is rolled **once per wave per run** (fresh every run, not the map seed) by `chance` (the chances
  are normalised). A wave with no `alts` carries `enemy` / `variant` / `pack` / `stats` itself (= one alt).
- `pattern`: as a roster row. `pack` on the alt caps how many of a burst stand together; a burst bigger than the pack
  is several packs. A `"ring"` is the whole burst round the hero at once, whatever the pack; `"in_front"` puts each
  creature of the burst at its own point at the top of the screen (pass 57).
- `respect_cap` (default true): the burst spawns only into free cap room (load units, each creature its `cap_share`,
  against `channel`'s cap: `"regular"` or `"hell"`); false = on top of the cap like a SWARM event (the `hard_cap`
  still holds).
- `elite`: `""` none, `"random"` a random modifier, or a modifier id (explosive, shielded, speedy, splitter): every
  creature of the wave wears it. Waits for `colour_after_kills` like the elite events (spawns plain until then).
- `toast`: a banner shown at the first burst ("SWARM!").

## Events
```json
{"t": 215, "type": "elite_boss", "enemy": ["dune_scorpion", "sun_prophet"], "weights": [2, 1],
 "name": "First Elite", "chance": 1.0, "t_jitter": 20, "stats": {}, "variant": "", "mod": "", "count": 36,
 "pattern": "ring", "interval": [100, 160]}
```
Types: `elite` {enemy?, mod?}, `elite_every` {interval}, `swarm` {enemy, count}, `boss` {enemy}, `elite_boss`
{enemy}. **New** on every type: `name` (label), `chance` (0..1, rolled per run; default 1), `t_jitter` (± seconds,
rolled per run), `stats`, `variant`. **New**: `enemy` may be a list on every type, with an optional parallel
`weights` list (equal when missing; `elite_boss` lists were already random). `elite_every.interval` may be
`[min, max]` (a fresh random interval every firing). `swarm.pattern`: `"ring"` (the default, as before: a ring 16 m
round the hero, ignores the cap), `"pack"` or `"scatter"` (through the spawn points, ignores the cap); pass 57:
`"in_front"` (every one at its own point at the top of the screen, ignores the cap). The swarm keeps its own 16 m ring:
the rows' and waves' `"ring"` is 11.7 m.

## Stat overrides (`stats`, **new**)
Every key optional; a missing key keeps the creature's own number. Multipliers (`*_mult`) stack on the base. Pass 58:
`size` may also be a range `[min, max]` and `tint` a colour range, and a row that sets `hp` (or `damage`) takes no time
curve on it (see "Pass 58" below).
```json
{"hp": 10, "hp_mult": 1.5, "damage": 3, "damage_mult": 1.2, "speed": 1.6, "speed_mult": 1.1,
 "size": 1.2, "radius": 0.5, "damage_reduction": 0.1, "knockback_mult": 1.5,
 "contact_cd": 0.6, "attack_rate_mult": 1.0, "projectile_speed_mult": 1.0,
 "ranged": {"cooldown": 2.5, "projectile_speed": 6.0, "range": 7.0}, "charge": {"cooldown": 4.0, "speed": 9.0},
 "pack": 5, "max_alive": 0, "cap_share": 1.0, "xp_mult": 1.5, "can_be_elite": true,
 "drops": {"small": 1.0, "medium": 0.05, "large": 0.0, "gold": 0.02, "chest": 0.003, "pickup": {"id": "rage", "chance": 0.1}},
 "pickup_chance_mult": 1.0, "pickup_weights": {"heart": 6, "rage": 3, "sprint": 3, "shield": 2, "magnet_pulse": 2, "nuke": 2},
 "elite": {"hp_mult_per_stage": 1.8},
 "boss": {"hp_mult_per_stage": 1.6, "cooldown_between": 4.5, "attacks": {"burrow": false, "spit_volley": true}}}
```
- `contact_cd`: seconds between bites (the creature's default 0.6; new `EnemyDef.contact_cd`).
- `attack_rate_mult`: 2 = attacks twice as often: divides `ranged.cooldown`, `charge.cooldown`, `kamikaze.windup`,
  `boss.cooldown_between`, `contact_cd`.
- `projectile_speed_mult`: multiplies `ranged.projectile_speed` (or `speed`), `artillery.missile.speed`, and the
  `speed` of every boss attack that has one.
- `knockback_mult`: multiplies `charge.knockback`, `ranged.knockback`, `kamikaze.knockback` and each boss attack's, and
  (pass 54) the creature's contact `knockback` (its own, else the rule from its damage).
- `ranged` / `charge` / `drops` / `elite` / `boss`: deep-merged over the creature's block. `boss.attacks` is a map
  name → on/off: `false` removes that attack from the list; `true` keeps it (an unknown name adds nothing).
- `pickup_chance_mult` scales the timeline's `pickups.per_kill` for this creature's kills; `pickup_weights` replaces
  the timeline's pickup roster for its kills (ids → weights, missing = not dropped).
- Implementation: `EnemyDef.with_overrides(stats)` returns a cached copy whose `type_key()` is `id[@variant][#hash]`;
  `EnemyManager.spawn(def_id, at, elite, scale_mult, hp_mult, variant, overrides, src)` (pass 58: `src`, the source's
  fixed numbers); `alive_of(id)` and `max_alive` count every type of that id.

## Where the new creatures sit (pass 53)
`skeleton` and `skeleton_knight` from 0:00 at 9 : 3 (three skeletons to a knight); `lesser_scorpion` the second
creature met (1:00); `fire_ant` from 5:00 as 0.6 of a mummy (36 HP, bite 8, size 1.15). `red_goblin`,
`red_goblin_runt` and `werewolf` are in the content and the editor's palette and on no row: Garry places them.

## Pass 54 additions

### Roster rows
- `id` (string, optional): a stable label the editor assigns (`r1`, `r2`, ...) so a reordered row keeps its numbers on save;
  the game ignores it.
- `weights`: presence keyframes `[[t, w], ...]`, the row's draw weight over the run clock, linear between the points and flat
  before the first and after the last (`WaveDirector._roster_weight` through `WaveTimeline.sample_points`, the cap curve's
  rule). A weight below 0 counts as 0, a row at 0 is never drawn, and a burst whose open rows are all at 0 brings nothing,
  so `[[0, 0], [60, 0], [120, 5]]` is a row that fades in from 1:00 to 2:00. It replaces `weight` / `weight_late` /
  `weight_late_t`: a row that still carries only `weight` (and `weight_late`) slides as before, which is the same as
  `[[t, weight], [weight_late_t, weight_late]]`, so old files play unchanged (`weight_late_t` stays in the timeline for
  them). Red Canyon's rows were converted that way in pass 54; its shaman row, dated on `weight_late_t` itself, reads
  `[[860, 1], [861, 2]]`, the old one-second slide.
- `stats.knockback`: the creature's contact knockback on the hero (see Creature JSON).
- `stats.variance`: deep-merged over the creature's `variance` block (`size`, `speed`, `tints`, `tint_strength`,
  `special_chance`, `special {size, hp, damage, xp, tint, tint_strength}`; a `tints` list given here replaces the
  creature's whole): the coloured variance specials per row.
- `stats.elite_weight` (default 1, below 0 = 0): this row's weight when a random Elite candidate is drawn for an `elite` /
  `elite_every` event with no creature named, and for endless's elite-modded creatures (0 = never, like
  `can_be_elite: false`; it was an even draw).
- `stats.elite_formats {single, pack, ring}` (chances, normalised; default single 1, all 0 = single): how an elite-modified
  creature drawn from this row arrives: alone at a spawn point, as its whole pack (the row's `pack`, else the creature's
  `pack_size`) at one spawn point every one wearing the modifier, or as a ring of `pack` of them 12 m round the hero. One
  toast either way ("SPEEDY SKELETON ×5"); the modifier is the event's `mod` or a random one, as before.
- `elite_weight`, `elite_formats` and `variance` are part of the overrides' hash, so two rows that differ only there are two
  EnemyManager types.

### Scalars
- `creature_damage_mult` (default 1.0): multiplies EVERY hostile damage: bites, shots, spit, artillery missiles, kamikaze
  blasts, death bursts, boss and caster attacks and the Brander's ring. Red Canyon: 1.25 (pass 54). WaveDirector hands it to
  `EnemyManager.creature_damage_mult` every tick of the normal phase; the debug arena plays its creatures at 1 (its dummies
  say what they bite for).
- `hp_curve` and `damage_curve`: `{"mode": "points" | "formula", "points": [[t, mult], ...], "formula": {"kind": "linear" |
  "power" | "exponential", "a": 0.0977, "b": 1.25}}`. The multiplier on creature HP (replaces `hp_growth` / `hp_power` when
  present; absent = the old pair) and on creature damage (a new factor, absent = 1; `EnemyManager.damage_time_mult`) over
  the run clock. Pass 58: each roster row, wave and event reads them once, at its own start, and keeps that value for
  every creature it brings (see "Pass 58"). `points` is linear between the points, flat outside; `formula` with `m` = minutes: linear `1 + a*m`, power
  `(1 + a*m)^b` (today's hp_growth / hp_power form), exponential `(1 + a)^m`. Both blocks may be present and `mode` picks;
  without a `mode` the points are used when there are any, else the formula; `a` defaults to 0.0977 and `b` to 1.25; an
  unknown mode or kind is 1 (`WaveTimeline.curve_mult`). Red Canyon: `hp_curve` the power formula 0.0977 / 1.25 (its old
  pair, kept beside it) with points computed from it at the stage marks (1.0, 1.9414, 2.9878, 4.1143 at 0, 430, 860,
  1290 s), `damage_curve` flat at 1.
- `spawn_sides {mode, top, bottom, left, right, facing_share, facing_spread_deg}`: where the roster's bursts, the waves,
  the specials, a random Elite and a creature moved up from far behind come from (`WaveDirector._spawn_point`). `mode:
  "sides"`: a screen side by weight (top / bottom / left / right in camera space, top = north = -Z under the fixed camera,
  the follow camera's yaw turns them with it; a missing side weighs 0), then a point 19-24 m out within ±45° of that side's
  axis. `mode: "facing"`: the old rule (`facing_share`, default 0.7, of the spawns within ±`facing_spread_deg`, default 60,
  of where the hero faces; the rest anywhere). Absent, or sides whose weights are all 0 = `facing`. Red Canyon: sides
  55 / 15 / 15 / 15. Rings and swarms, the portal wave and bosses are placed as before, and the Elite bosses keep the old
  facing rule (with the block's `facing_share` / `facing_spread_deg` when it names them) whatever the mode. A row's, a
  wave's or a swarm's `"in_front"` pattern (pass 57) ignores the block: always the top of the screen.

### Creature JSON
- `knockback` (top level, m/s): the shove the hero takes from this creature's bite. Absent (or 0) = `EnemyDef.default_knockback
  (damage)` = `clamp(3.4 * sqrt(damage / 4), 2.5, 7.0)` (about 35 % over the old fixed 2.5 for a 4-damage creature);
  `EnemyDef.hit_knockback()` is the number in force. Every creature and boss JSON carries one since pass 54
  (`tools/set_knockback.py` wrote the rule's value, 2 decimals, right after `damage`; the training dummies have none). A
  hostile shot shoves by `ranged.knockback` when it has one, else `knockback * 0.7`; `charge.knockback`,
  `kamikaze.knockback`, `artillery.missile.knockback` and boss attacks keep their own numbers. Overridable per row
  (`stats.knockback`), and `stats.knockback_mult` multiplies it too (a multiplier of 0 leaves no shove).

## Pass 57: the Ring and In front patterns
- `"ring"` (roster rows and waves; Garry: "spawn in a Ring around the Player (kind of like what we have in the debug
  option in the Arena), but about 30% further from the Player"): the creatures of one spawn stand evenly round the hero on
  a circle of `WaveDirector.RING_RADIUS` = the arena's ring (9 m) x 1.3 = **11.7 m**, from a random start angle, each slid
  up to 0.2 of the even spacing round the circle and up to 0.6 m in or out (`RING_SLIDE`, `RING_JITTER`), so a full ring
  reads as a thick band; each point is clamped to the arena like every spawn point (pass 58: a ring that would cross the
  wall spreads over the arc of it inside the arena instead, and steps off rocks and the lake; see "Pass 58"). A roster
  row's spawn is its pack, cut
  as always to what one burst holds (`burst_max` load units over the creature's `cap_share`: at most 24 skeletons on Red
  Canyon) and to the cap's room; a wave's is its whole `burst`, cut by `count`, the hard cap and, with `respect_cap`, the
  cap's free room. Counted like `"pack"` everywhere (the cap rules are unchanged). In the portal wave a ring row is still a
  ring round the hero. The swarm event's ring stays 16 m and the elite format `"ring"` 12 m.
- The editor's hint under the Pattern field (`U.ringCount` in `tools/level_editor/util.js`): one closed row shoulder to
  shoulder is the circle (2 x pi x 11.7 = 73.5 m) over a body's width, 2 x its radius (the row's `stats.radius` when set:
  the game keeps bodies that far apart, a painting's `size` does not change it); "a thick ring with few gaps" (Garry) is
  about 1.5 times that, rounded to 5: the skeleton (radius 0.52) closes one row with 70 and makes a thick ring with about
  105. The swarm's own ring gets the same hint at 16 m.
- `"in_front"` (roster rows, waves and swarm events; Garry: "spawn above the Player, basically an override to the
  Spawning part in the Settings"): every creature of the spawn at its own point 19-24 m from the hero (clamped to the
  arena) within 45 degrees either side of straight up the screen (the side `spawn_sides` calls top; the follow camera's yaw
  turns it), whatever `spawn_sides` says, mode sides or facing: a loose band across the top. Packs sharing a top point
  were tried too and read less as "they come from above". In the portal wave an in-front row still comes from the top.

## Pass 58: a row's numbers fixed from its start, size ranges, colour ranges

### A row's HP and ATK are fixed from its start
Garry: "While I want the HP of enemies to increase over time, I don't actually want it to change for the same 'wave' of
enemies on the fly, because then it feels weird for the Player that shooting the same enemy with the same weapon suddenly
doesn't kill it even though it was killing them just a 20 seconds ago."
- Every spawn source has a start second `t0` on the run clock: a roster row its `t` (0 when it has none); a wave its `t`
  (the alternative rolled for this run decides its overrides); an event the second it actually spawns (its `t` +- its
  rolled `t_jitter`; each `elite_every` firing on its own; an elite held back by `colour_after_kills` when it is let out).
  Specials and a boss's brood (its `spawn_ring` attack, an `erupt`'s creatures) come on the numbers of the moment they
  come.
- **An event joins the row that brings its creature** (the fix round of pass 58: a fire-ant swarm at 9:19 came with 520
  HP beside the 7:10 fire-ant row's 322-HP ants, the very "shooting the same enemy with the same weapon suddenly doesn't
  kill it" this rule is for): while a roster row (either channel, open and at a weight above 0 at that moment; the
  heaviest when several are) or else a wave (inside its window, not spent) brings the same creature in the same look (the
  same art variant, the creature's own look when none is named), an event of it (a swarm, an elite or `elite_every`, a
  special, a boss's brood, an Elite boss event that names a regular creature) plays that row's numbers for each half its
  own `stats` leave alone: HP (`hp`, `hp_mult`) and ATK (`damage`, `damage_mult`), each the row's override and the row's
  fixed factors (its `hp_time` / `dmg_time` and its hero-level factor). A half the event sets itself is its own, at the
  moment it fires. An elite drawn from a roster row (an `elite` event that names no creature) comes on that row's
  numbers. `WaveDirector.event_numbers(id, variant, stats)` -> `{stats, src, joined}`, `open_source_of(id, variant)`.
- The portal wave brings each row's creatures on that row's own numbers (the fix round: they stand beside the ones the
  hero was just shooting).
- The time factors are read once, at `t0`: `hp_time = hp_mult_at(t0)` and `dmg_time = damage_mult_at(t0)`, except that
  a source whose `stats` set `hp` takes no HP curve (1) and one that sets `damage` no damage curve (Garry: "the
  multiplier will inform what the HP should be for enemy rows whose stats weren't overridden").
- The hero-level factors `1 + level_hp_per_level x (L - 1)` and `1 + level_damage_per_level x (L - 1)` use the hero's
  level `L` at the source's first spawn of the run, and keep it for every later creature of that row or wave.
- **Endless fixes the rows afresh at each endless wave** (the fix round: Red Canyon's two hell rows have no `until`, so
  without it stage 3 and the whole of endless kept 14:20's curve and hero level, and only the x1.12 a wave was left of
  endless's growth): from the last stage's portal on, every row and wave takes `t0` = the later of its own `t` and the
  start of the endless wave it spawns in (`stage_length x stages + (N - 1) x endless_wave_seconds` for wave N, from 1)
  and the hero's level at its first creature in that wave. The step comes with the wave's toast (WAVE N), like the stage
  multiplier's, so nothing changes in the middle of a wave. Before endless, a row with no `until` keeps the numbers of its
  start for the rest of the run's stages: split a long bar where its creatures should get tougher.
- **Row HP** = (`stats.hp` if set, else the creature's JSON `hp` x `hp_time`) x `stats.hp_mult` (1 when missing); **row
  ATK** the same with `damage`, `damage_mult` and `dmg_time`. The Level Editor's stats show these numbers.
- In game a creature's HP = row HP x the stage multiplier at its spawn (`Run.stage_mult()`: it steps at a new stage and
  each endless wave, both announced) x `creature_hp_mult` x the row's hero-level factor x what goes on top (the variance
  special, an elite modifier, a split child's half). Its damage the same with `creature_damage_mult`. Every hit it deals
  later (its bite, its shots, its attack script, its death burst, a kamikaze blast, a rocket) uses those same factors of
  its own (`EnemyManager.stage_of`, `lvd_of`, `host_of`), never the live curve; an attack script's own `damage` takes
  `dmg_time` too (1 for a row that sets `damage`).
- Bosses and the Elite-archetype creatures (the Dune Scorpion, the Sun Prophet, the Stone Golem) keep their own rules, as
  before (no time curve on their HP). A creature spawned by hand (the arena's ENEMY tab, a test, a tool) plays the live
  numbers as before. `EnemyManager.hostile_mult()` stays for what no creature owns (the Brander's ring of fire).
- Implementation: `WaveDirector.fixed_numbers(t0, stats)` -> `{t0, hp_time, dmg_time, lv_hp, lv_dmg}`;
  `source_for(key, t0, stats)` makes a roster row's ("row:<id>#<index in the roster>", "row#<index>" for a row without
  an id: two rows sharing an id keep their own) or a wave's ("wave#<index>"; in endless "@w<N>" on the end) at its first
  spawn and keeps it (`source_state(key)` reads it); `EnemyManager.spawn(..., src)` plays it (`fixed`, `f_stage`,
  `f_hpt`, `f_lvh`, `f_dmt`, `f_lvd` per creature; `src_of(i)` hands a split child its parent's, with the stage at the
  parent's spawn and, the fix round, its rolled size `f_bsz` and hue `f_tu`, so a child is never bigger than its parent
  nor another colour; `brood_numbers(id)` is a brood's, the director's `event_numbers`, else `now_src()`). `spawn_pack`,
  `spawn_ring` and `spawn_boss` pass it on.
- What it does to Red Canyon as Garry left it: the rows without `stats.hp` keep the HP of their first second all through
  (the red goblins 13 HP at level 1 from 0:00 to 2:02, where they had grown to 16.3), and the rows that set `hp` lose the
  curve they had on top of it (fire ants at 7:10 at level 1: 305 HP before, 157 now; skeletons at 3:12: 36.5 -> 26). ATK
  is unchanged there (the damage curve is flat) except for the hero's level being the row's first. The hero levels along
  a row, and pass 57 gave each later creature the higher level, so a row's last creature also loses
  `0.05 / (1 + 0.05 x (L - 1))` of its HP for every level the hero gained during the row (5 % at level 1, 3.4 % at 10,
  2.6 % at 20, 2 % at 30), and `0.03 / (1 + 0.03 x (L - 1))` of its damage.

### Size ranges
- `stats.size` (a roster row, a wave or its alt, an event): a number as before (the creature's size; the variance's
  size jitter on top; the radius unchanged), or `[min, max]` (Garry: "editable as a kind of a range (between 3-5 for
  example)"): every creature rolls its own size uniformly in the range (two numbers in either order, each at least
  0.05; `size_mult` scales both ends), in place of the variance's size jitter; the variance special's size factor
  lifts it at most to the range's top (the fix round, below) and an elite modifier's scale still multiplies on top.
  Its collision radius follows: the JSON radius (x `radius_mult`) x rolled size / the JSON size, unless the row sets
  `radius`. The shadow and the badge follow the rolled size. One EnemyManager type per row, whatever each creature
  rolled (`EnemyDef.size_range`, `size_ref`, `radius_follows`; the copy's `size` stays the painting's JSON size).
- The fix round: a variance special of a size-range row stays inside the range: its size factor (x1.5 on the skeleton)
  lifts the rolled size towards the top and is cut there, `min(rolled x factor, max)`, its HP, damage, XP and colour
  still the special's (a [3, 5] row's specials had stood up to 7.5). An elite modifier's scale still goes on top (an
  elite-modded creature is bigger by its kind: x1.4 to x1.6). A split child takes its parent's roll (x the split's 0.6).
- Bodies that wide outgrow the crowd grid's 2.5 m cells: since the fix round a creature wider than half a cell scans as
  many cells as its reach needs and a narrow one also feels the wide ones past its 3 x 3 cells (while there are no more
  than 16 of them), so two giants no longer stand inside each other (`EnemyManager.BIG_R`, `_big`, `_grid_max_r`).

### Colour ranges
- `stats.tint`: `{"hue": [h0, h1], "sat": 0.85, "val": 1.0, "amount": 0.5}` (Garry: "a version that kind of colours all
  the enemies that come out of that wave"): hue in degrees 0..360 (a single number = that hue), `sat`, `val`, `amount`
  0..1 with those defaults. Each creature rolls `u` in 0..1 and takes the hue `fmod(h0 + u x span, 360)` with `span = h1 -
  h0`, plus 360 when that is negative (so `[340, 20]` runs through red). Its tint is `Color.from_hsv(h / 360, sat, val)` at
  strength `amount`, drawn as `mix(rgb, tint, amount x 0.65)` (EnemyManager.vtint, the billboard's mix). It is on from the
  row's first creature (it is the row's design: `colour_after_kills` holds only the random variance palette and the
  specials) and replaces the variance palette's tint; an elite modifier's colour and the burn, poison, freeze, stun and
  status tints still win (`EnemyManager.tint_of`).
- A variance special of a colour-range row keeps the row's colour instead of its own tint (in its wine it read as having
  "lost the colour" of its wave): a darker, stronger shade of the hue that creature rolled,
  `Color.from_hsv(h / 360, min(sat + 0.15, 1), val x 0.7)` at strength `min(max(amount, the special's tint_strength) +
  0.15, 1)` (`EnemyDef.tint_special_color`, SPECIAL_SAT_ADD / SPECIAL_VAL_MULT / SPECIAL_STRENGTH_ADD), and its size
  factor as before. Tuned by eye in the arena: value x 0.55 at the plain strength came out muddy on green skeletons and
  maroon, not blue, on red goblins in a blue row. A row without a tint keeps the special's own tint, exactly as before.

### Spawn points by the wall (the review of pass 57)
- A hero standing by the arena's wall had the "ring" pattern's outer part clamped onto the wall right beside him (a
  105-ring 64 m out: 7 within 2 m) and the "in_front" points at the north wall the same (47% within 6 m). Now a ring
  spreads all its creatures evenly over the arc of it inside the arena (`EnemyManager.ring_arc`, `ring_spots`), every
  spot a ring's width from him; the swarm's 16 m ring, the elite format's 12 m ring and a boss's brood ring do the same
  round their centre. A 19-24 m spawn point (every side, facing, in_front, the Elite bosses, the cull) and the portal
  wave's 15-20 m point turn round the least way that keeps them inside the arena at the same distance
  (`EnemyManager.point_inside`) instead of being clamped onto the wall. Counts are kept.
- Ring spots (on the screen at 11.7 m) step off a rock's painted foot (its collider / 0.62 + 0.5 m) and out of the lake
  (`EnemyManager.spawn_clear`): up to 0.4 of the spacing round the ring and up to 3 m out or 2.5 m in, the smallest move
  first; in_front points the same by up to 12 degrees round and 1.5 m in or out. When nothing near is clear the spot stays
  (the steering walks a creature out of a rock, and one in the lake wades).
- The lake (the fix round: by the oasis 11 to 14 % of the ring and in_front spots stayed in the water, and a 105-ring
  there cost 8 to 10 ms on the PC): it is cut out of a ring like the wall, by the circle's arc inside the lake a body and
  the jitter wider than the water (`EnemyManager.ring_in_disc`, the map's `lake_center()` / `lake_radius()` through
  `lake_of`), and the ring's creatures spread over the dry arcs that are left, each its share by length
  (`_dry_arcs`, `_spots_on`); the rocks a ring must keep off are gathered once a ring (`_clear_ctx`). An in_front point in
  the lake turns past the lake's whole width at its distance, the nearer way first (`EnemyManager.lake_turns`), then
  steps off rocks as before. Measured on Red Canyon (seed 4242, lake 6.76 m): no spot in the lake or on a rock out of
  10,500 (105-rings round heroes 3 m from the shore), 3,000 (the swarm's ring) and 2,100 (in_front with the lake ahead);
  a 105-ring there 0.17 ms on average, 0.54 ms at worst.

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
`move_pace`, `hell_cap[]`, `endless_wave_seconds`, `endless_wave_mult`; pass 54 added `creature_damage_mult`, `spawn_sides`,
`hp_curve`, `damage_curve` (below), pass 60 `creature_speed_mult` (the last section).

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
 "size": 1.2, "radius": 0.5, "damage_reduction": 0.1, "knockback_mult": 1.5, "knockback_resist": 0,
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
- `knockback_resist` (pass 67): sets the creature's `knockback_resist` for this row's creatures, 0..1 (clamped): the
  share of every shove from the hero's side they shrug off (see Creature JSON); the other way round from `knockback`.
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
- `stats.knockback_resist` (pass 67): the share of the hero's shoves the row's creatures shrug off, 0..1 (see Creature JSON).
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
- `knockback_resist` (top level, pass 67, 0..1, default 0): the other way round: the share of every shove from the hero's
  side this creature shrugs off, applied as x (1 - resist) on the push: a weapon hit's `kb_force / max(size, 0.8)`, a
  blast's `throw_radius` (the hero's nuke ring, Thruster Burst and Grand Finale, and hostile throws alike: a rocket, a
  boulder, the stalactites), the Lasso's pull and Buck's Ram. 1 = never moved; the boss's own 0.15 stays on top of it
  (every boss keeps 0). Not a damage reduction. Lifts, bounces, the twister's fling, the Singularity's drag and a
  charger's side-shove are not knockbacks and ignore it. The Hammer Giant carries 0.67 (a third of its old push; Garry,
  pass 67). Clamped on read (`JsonContent._enemy`) and in `with_overrides`; overridable per row
  (`stats.knockback_resist`). Written right after `knockback` in the JSON, never between `damage` and `knockback`
  (pass54_waves_test pins that order). `EnemyManager` keeps the share taken per type (`_t_kbt`).

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

## Pass 60: creature_speed_mult

### Scalars
- `creature_speed_mult` (default 1.0): multiplies EVERY creature's pace: each creature, Elite and boss walks, charges and
  rolls at this multiple of its speed, winds up and warns 1/mult as long, and its shots (spit, shards, barbs, the harpoon,
  the tumbleweeds, the boulder, the rumble, the Vulture Raider's rocket) fly at it too; the hero is not affected (he keeps
  `move_pace`, which is everyone's knob). Red Canyon: 0.9 (pass 60, Garry: "reduce the movement speed of all enemies by
  10%" as "a multiplier for all"). WaveDirector hands it to `EnemyManager.creature_speed_mult` at a run's start and every
  tick of the normal phase, the debug arena included, and EnemyManager folds it into its `pace` (so `hostile_clock()`
  carries it). Level Editor: Settings, Scaling, "Creature speed x".

## Pass 67: `weapon_grade` (a top-level map key beside `skins`, not part of `timeline_data`)

How this map's light wants the 3D weapon models drawn: `"weapon_grade": {"value": 0.78, "saturation": 1.3, "glow": 0.3}`
on Red Canyon (the numbers are the file's; BALANCING.md section 2 has the row and section 14 the rule). Red Canyon's warm
sun, ambient and fog pull every lit mesh toward the sand, so `WeaponBehavior.grade_materials` grades every lit, opaque,
untextured StandardMaterial3D of a weapon's visual in HSV: saturation x `saturation` (clamped to 1), value x `value`; a
material that already emits has its emission graded the same way (a gold that glows stays the same gold). One copy per
material, so parts sharing one still merge (MeshMerge) and the draw calls do not grow; the unshaded and see-through FX
(shot cores, halos, sparks, smoke, flashes) and anything built in code are left alone. `glow` is the companion glow's
energy (pass 53's `WeaponBehavior.GLOW` 0.45 when the key is absent). A missing `value` / `saturation` takes
`WeaponBehavior.GRADE`; `{"value": 1, "saturation": 1}` turns the grade off. A weapon's own `params.grade` (the Items
tab's params; a mutation's or an evolution's `final` too) wins over the map's, key by key. The title screen's companion
and the spawn beam's warm-up read the same block. The editor's Save keeps the key (every top-level key of the file rides
along, one added while the page was open too); the page does not edit it.

## Pass 69: the coloured specials (`special_defaults`, a swarm's `special`)

### Events
- `swarm.special` (bool, default false): every creature the swarm brings comes as its **variance special** for sure
  (`EnemyManager.force_special`, held by `WaveDirector._run_event` around the spawn): whatever its `special_chance`,
  before `colour_after_kills`, with no SWARM! banner. Its numbers are the creature's Special block (below). A creature
  with no `variance` block has no special and comes plain. Red Canyon's special Goblin (Garry: "a single 'Special'
  regular Goblin appears at the end of the first wave"):
  `{"t": 120, "type": "swarm", "enemy": "red_goblin", "variant": "RG-B", "count": 1, "pattern": "in_front",
  "special": true, "name": "Special Goblin"}`: the first roster row (r1, the red goblins, RG-B) runs 0:00-2:02, so the
  special one walks in from the top of the screen at 2:00 and plays that row's numbers (an event joins the row that
  brings the same creature, pass 58), x10 HP, x2 ATK, x1.25 size. The editor: the event's "Special" box (swarm only), a
  star after its label and its glyph in the creature's special colour on the Events lane.

### Scalars
- `special_defaults` (optional block, default `{}`): `{"size", "hp", "damage", "xp", "tint_strength", "glow"}`, the
  map's numbers for a variance special that the creature's own `variance.special` does not name. Each number is the
  creature's own, else this block's, else the game's `EnemyDef.SPECIAL_DEFAULTS` (size 1.25, hp 10, damage 2, xp 2,
  tint_strength 0.6, glow 0.6; `EnemyDef.special_value`). `WaveTimeline.special_defaults`, handed to
  `EnemyManager.special_defaults` by `WaveDirector._apply_mults`. Red Canyon has none (every creature names its own
  size, hp and damage; none names a glow, so the game's 0.6 or this block's `glow` is every special's glow). The editor:
  Settings, "Coloured specials".

### Creature JSON (`variance.special`)
- New key `glow` (0..1): the emissive rim `enemy_billboard.gdshader` draws round a special in its colour (the tint's hue
  at full brightness, breathing 0.8-1 at about half a hertz), 1 + 4.2 x glow screen pixels wide with a lighter core 0.6 + glow px wide, and the painted outline
  lit by 0.85 x glow; burn, poison and freeze tint it while they last; the harpooner's red tether rim wins. It rides on
  INSTANCE_CUSTOM.y as 64 x level (0..16) above the flip bit and the tether's level (`EnemyManager.special_glow_code`).
- A special's size is exactly `size` x the creature's (the plain ones' `variance.size` spread no longer applies to it), so
  it is never smaller than a big plain one; a size-range row still stops it at the range's top.
- Pass 69's numbers on every creature with a chance: `special_chance` a third of what it was (4 decimals), `size` 1.25,
  `hp` 10.0, `damage` 2.0 (XP and colours as they were). The editor: Enemies tab, "Special" (Chance, Size x, HP x, ATK x,
  XP x, Colour, Colour strength, Glow), with what applies and from where, and the plain one beside its special.
- `tint` may be any colour (pass27_test wanted a dark one before; the editor now only warns on a light or grey one).
- A row's `stats.variance.special.glow` overrides it like the other special numbers ("Special glow" in the Elite group).

## Pass 73: target priority and growing out of the ground

### Map timeline (`content/maps/<id>/<id>.json` `timeline_data`, WaveTimeline, JsonContent.timeline_from_dict)

| Key | Type | Default | What it does |
|---|---|---|---|
| `target_priority` | block | `{}` (= the defaults) | the weapons' target priority (EnemyManager.priority_target), handed on by WaveDirector._apply_mults |
| `target_priority.enabled` | bool | true | every weapon that picks its target takes a special, an Elite or the boss within reach first (only the first shot of a volley spread over different creatures) |
| `target_priority.reach` | m | 10 | how near the hero (a turret: itself) it must be; never past the weapon's own range |
| `specials.pool[] {"enemy": "saiga_sniper"}` | row | | Red Canyon's new row, beside the Rocketeer's |

The Settings tab shows `target_priority.*` in a new **Targeting** card (fields.js SCALAR_GROUPS += 'Targeting');
the Specials card's words name the Sniper.

### Map `timeline_data.spawn_rise` (WaveTimeline.spawn_rise; Settings → Spawning)

| key | type | default (absent) | meaning |
|---|---|---|---|
| seconds | s | 0.45 | every spawn rises out of the sand over this long (× 1/pace); 0 = off |
| big_seconds | s | 0.9 | the same for an Elite or a boss by its kind |
| targetable | 0..1 | 0.7 | the share of the way up from which a weapon may choose it as its target (area damage hits it all along) |
| dust | × | 1.0 | the dust puff's size × its size (0 = none; only on the screen) |

WaveTimeline: `SPAWN_RISE_DEFAULTS`, `spawn_rise_value(key)`; JsonContent reads the block as it is.

## Pass 79: mutation offers come as level-ups (lane MUT)

### Map timeline (`timeline_data`, WaveTimeline, JsonContent.timeline_from_dict)

| Key | Type | Default | What it does |
|---|---|---|---|
| `path_times` | `[[s, ...], ...]` | `[[55, 115, 175, 230, 270], [35, 90, 145, 200, 245, 280]]` | unchanged in shape: seconds into each stage (the last list holds for later stages). What changed is what a time means: a **mutation offer falls due** there (Run.mutlvl_tick) and waits for the hero's **next level-up**, which shows it in place of the three cards (a weapon drawn among those with the stage's pick open, its whole path on the table). Offers queue, one a level-up, and stay due across a stage's end; one that falls due while no weapon has a pick open is spent with nothing; a level-up whose offer finds none open is an ordinary one. Nothing opens on the clock any more. The editor: Settings -> Items, "Mutation offers per stage"; the timeline's "Mutations" lane |
| `xp_need_mult` | number | 1 | unchanged in meaning (a level L needs (15 + 6L + L^2/2) x this); Red Canyon's 1.65 since pass 79 (3.1 with the offers on the clock; 4.1 at the pass's start), measured with the run sim so a minute brings as many three-card level-ups as before and the mutation level-ups on top |
| `mutation_levels_scale` | bool | false | false: what grows with the hero's level (`level_hp_per_level`, `level_damage_per_level`, his trait, Barrel Rush's gems, Ram, Supply Drop) reads his card levels, his level less the level-ups that were mutation offers (Run.card_level); true: every level-up counts. The editor: Settings -> Scaling, "Mutation levels scale" |

Run state (not in the map): `Run.mutlvl_due` (offers due, waiting), `Run.mutlvl_ready` (mutation level-ups claimed
whose screen has not opened), `Run.mutation_levels` (level-ups that were mutation offers). A run record's events gain
`mutation_due` (an offer fell due: `due`, `slot`; or was dropped: `dropped` with `at_level_up` / `at_screen`).

## Pass 79: the rim's and walls' colours (lane WORLD)

### Map: `timeline_data` (WaveTimeline; the Level Editor's Settings tab, World card; docs/waves_schema.md)
| key | type | default (empty / absent) | meaning |
|---|---|---|---|
| `rock_color` | "#RRGGBB" | RedCanyon.ROCK_COLOR **#785C5E** (0.47, 0.36, 0.37) | the red-rock rim's colour (the ground from `rim_start` 44 m out to the wall). The terrain shader recolours the rock painting (redrock.png) to it: the painting's luminance over its mean (`rock_tex_lum` 0.184, linear) times this colour taken into linear light, so the bands and cracks stay as light and dark and the hue is the key's. Pass 78's was #9E573D (0.62, 0.34, 0.24) over an orange painting. |
| `wall_colors` | {key: "#RRGGBB"} | RedCanyon.WALL_COLORS | the walls' colours; a key left out (or unreadable) plays its default |
| `wall_colors.near` | "#RRGGBB" | **#856B6E** (0.52, 0.42, 0.43) | the ring of cliffs right behind the boundary wall (arena_radius + 4 m): a tint over the sandstone painting, grey since pass 79, so the tint is the colour (was (0.78, 0.6, 0.5) over orange bands) |
| `wall_colors.far` | "#RRGGBB" | **#705963** (0.44, 0.35, 0.39) | the second ring of cliffs (+26 m) (was (0.62, 0.42, 0.36)) |
| `wall_colors.farther` | "#RRGGBB" | **#594A57** (0.35, 0.29, 0.34) | the outermost ring on the horizon (+52 m) (was (0.46, 0.30, 0.30)) |
| `wall_colors.stone` | "#RRGGBB" | **#7A6363** (0.48, 0.39, 0.39) | the stacked-stone boundary wall's even blocks (vertex colour, sRGB; the outer face 25% darker) (was (0.60, 0.40, 0.30)) |
| `wall_colors.light` | "#RRGGBB" | **#8C7370** (0.55, 0.45, 0.44) | its odd blocks, a shade lighter so the courses read (was (0.68, 0.47, 0.35)) |
| `wall_colors.cap` | "#RRGGBB" | **#544045** (0.33, 0.25, 0.27) | the wall's top (was (0.40, 0.26, 0.21)) |
| `wall_colors.riser` | "#RRGGBB" | **#47383B** (0.28, 0.22, 0.23) | the steps between blocks (was (0.34, 0.22, 0.18)) |
| `wall_colors.boulders` | "#RRGGBB" | **#6B5457** (0.42, 0.33, 0.34) | the boulders along the wall's top (was (0.5, 0.33, 0.26)) |

Red Canyon's file names all nine (the defaults). The Level Editor shows them as swatches in the World card (an empty box
shows the game's default faded, "the game's #..."). A page opened before pass 79 saves its timeline without them: the
game then plays the same defaults. Why the authored colours lean a touch rosy: the sun (1.0, 0.85, 0.65) and the ambient
(0.95, 0.80, 0.66) are warm and push every colour towards orange on the screen (help text says so).

Code: WaveTimeline `rock_color: String`, `wall_colors: Dictionary`, `static color_of(v, fallback)` ("#RRGGBB", "RRGGBB",
[r, g, b] 0..1, else fallback); JsonContent.timeline_from_dict reads both; RedCanyon `ROCK_COLOR`, `WALL_COLORS`,
`rock_color`, `wall_colors`, `_read_colours()` (before anything is built, from Run.map.timeline).
Shader `core/shaders/terrain_painted.gdshader`: `rock_flat` default (0.47, 0.36, 0.37), new `uniform float rock_tex_lum
= 0.184` (the rock painting's mean linear luminance; pass79_world_test checks it against redrock.png within 10%).
`tools/gen_textures.py --only sandstone,redrock` writes only those (sandstone.png is grey bands since pass 79).

## Pass 80: the fort wall and the oases

### The fort wall, the cliffs, the sign (lane WALLS)

#### Map: `timeline_data.wall_colors` (WaveTimeline; RedCanyon.WALL_COLORS by default; the World card's swatches)
The three cliff keys and `rock_color` keep pass 79's meaning and values. The boundary wall's keys change meaning with the
wall (a western sandstone fort wall since pass 80, drawn UNSHADED: each colour is the colour drawn, times the block
painting art/env/fort_wall.png, grey at about 0.8 on average). Red Canyon's file names all eight with these defaults.

| key | type | default | meaning (pass 80) | pass 79 |
|---|---|---|---|---|
| `rock_color` | "#RRGGBB" | #785C5E | the red rock: now only the ground OUTSIDE the wall (from arena_radius + 0.4 m out) | the rim from 44 m to the wall |
| `wall_colors.near` / `far` / `farther` | "#RRGGBB" | #856B6E / #705963 / #594A57 | the three cliff rings, a tint over the new rock painting art/env/cliff_rock.png (grey on average) | the same over the grey sandstone bands |
| `wall_colors.stone` | "#RRGGBB" | **#C59E7B** | the fort wall's sandstone blocks: the inner face (its foot 32% darker), the parapet, the merlons' faces, the towers; the outer face 25% darker | stacked stone, even blocks (#7A6363) |
| `wall_colors.light` | "#RRGGBB" | **#DEC09F** | the dressed trim: the cap course under the walk, the merlons' rounded tops, the parapet's top, the towers' cap course | the odd blocks (#8C7370) |
| `wall_colors.cap` | "#RRGGBB" | **#A58266** | the wall-walk along the top and the towers' roofs | the wall's top (#544045) |
| `wall_colors.riser` | "#RRGGBB" | **#7A604E** | the shaded sides: the steps where the walk climbs, the merlons' sides, the cap course's underside | the steps between blocks (#47383B) |
| `wall_colors.beams` | "#RRGGBB" | **#4F3626** | NEW: the vigas, the round wooden beam ends under the walk and on the towers (lit, unlike the wall) | (`boulders` #6B5457: gone with the boulders) |

Fields.js rows updated (labels: Wall stone, Wall trim, Wall walk, Wall shade, Wall beams; help says what each paints and
the game's default); `wall_colors.boulders` row replaced by `wall_colors.beams`. selftest_WORLD79.py's WALL_KEYS re-pinned
(boulders -> beams). WaveTimeline's comment says so. **docs/waves_schema.md** (the lead): the five wall rows above,
`wall_colors.boulders` -> `wall_colors.beams`, rock_color's meaning.

#### RedCanyon (game/world/maps/red_canyon/RedCanyon.gd)
| name | kind | default | meaning |
|---|---|---|---|
| `rim_start` | export | 44.0 (unchanged) | where the sand starts to rise towards the wall (no longer where red rock starts) |
| `rim_height` | export | 2.2 (unchanged) | how far the sand has risen at the wall (rim fraction squared) |
| `rim_bumps` | export, NEW | 0.45 m | the rim's bumps at the wall (were 1.2 m of broken rock) |
| `rim_bump_freq` | export, NEW | 1.4 | their frequency over the dunes' noise (was 2.5) |
| `ROCK_FROM` | const, NEW | 0.4 m | the ground's red rock starts this far past the arena's edge (under the wall) |
| `rock_weight(p: Vector2) -> float` | func, NEW | | 1 from arena_radius + ROCK_FROM out, else 0 (the terrain's vertex blue) |
| `HELL_WALL` | const, NEW | (0.97, 0.79, 0.72) | stage 3's tint on the fort wall's material (the ground's own hell multiply) |
| `WALLS` | const | preload CanyonWalls.gd | the builders |

#### CanyonWalls (game/world/maps/red_canyon/CanyonWalls.gd, new, RefCounted, static builders)
`fort_wall(map, r, segs, colours, noise) -> Node3D` ("FortWall": "Wall" MeshInstance3D + "Vigas" MultiMeshInstance3D;
RedCanyon._boundary_wall adds "Posts" and the skulls as before), `wall_material()`, `cliff_material(tint)`,
`ridge(map, arena_radius, r, h, h_var, segs, mat, noise_off, noise, tile) -> MeshInstance3D`.
Constants (all metres unless said): WALL_TEX "res://art/env/fort_wall.png", CLIFF_TEX "res://art/env/cliff_rock.png",
THICK 1.7, SINK 0.8, WALK_H 2.0, STEP 0.25, BATTER 0.12, CAP_H 0.22, CAP_OUT 0.1, PARAPET_T 0.55, PARAPET_H 0.45,
MERLON_W 1.0, MERLON_GAP 0.7, MERLON_SIDE 0.22, MERLON_ARC 0.24, MERLON_ARC_PTS 8, TILE 3.2, VIGA_EVERY 1.7, VIGA_R 0.1,
VIGA_OUT 0.45, VIGA_DOWN 0.42, TOWER_EVERY_DEG 30, TOWER_W 5.0, TOWER_OUT 1.4, TOWER_H 1.4, FOOT_DARK 0.32,
FOOT_RISE 0.9, PATCH 0.07, BEAM_WOOD (0.36, 0.25, 0.16), CLIFF_TILES [14, 20, 28], CLIFF_ROWS [0.33, 0.66],
CLIFF_RELIEF 0.9. RedCanyon `_ridge(r, h, h_var, segs, mat, noise_off, tile = 14.0)` gained `tile`.

#### Shader: core/shaders/sign_depth.gdshader
| uniform | default | meaning |
|---|---|---|
| `squash` | 0.02 (unchanged) | the share of the depth a vertex owes to its HEIGHT over the sign's foot that is kept |
| `squash_h` | **0.25**, NEW | the share of the depth it owes to its run over the GROUND that is kept (was squash's 0.02 too) |
| `bias` | 0.03 (unchanged) | metres the whole sign goes back |

#### Art and tools
- art/env/cliff_rock.png 2048 x 2048, art/env/fort_wall.png 1024 x 1024 (import: VRAM compressed, mipmaps; both grey on
  average). art/env/sandstone.png stays (gen_textures.py) but nothing loads it any more (the invisible fence boxes used
  its material).
- tools/gen_wall_textures.py (new): `cands --kind cliff|wall|top [--seeds --seed0 --size --prompt --ref]`,
  `seam <raw> [--band --soft --steps --seed --tag]`, `neutral <seam> --out <name> [--size --keep --value]`.
  The picks: `cands --kind cliff --prompt 5 --size 2048 --seed0 33` (s35), `seam ... --band 0.14 --soft 0.25 --steps 8
  --seed 7`, `neutral ... --out cliff_rock --keep 0.15 --value 0.8`; `cands --kind wall --seed0 1` (p0 s1),
  `seam ... --band 0.16 --soft 0.25 --steps 8 --seed 11 --tag _x11`, `neutral ... --out fort_wall --keep 0.15 --value 0.82`.
- tools/blender_sign.py NAIL_UP 0.004 -> 0.012 (art/props/sign.glb regenerated).

### The oases and the water (lane OASIS)

#### Map file, `timeline_data` (WaveTimeline; JsonContent reads them; Red Canyon names both)
| Key | Type | Default (the game's) | Meaning |
|---|---|---|---|
| `water_slow` | float 0..0.95 | 0.1 (`WaveTimeline.WATER_SLOW_DEFAULT`) | the share of the walking speed water takes from anyone wading (the hero, every creature, Elites, bosses); never a push, knockback or pull, nor anyone in the air or under the sand. 0 = off. A map that names none plays the default. |
| `oases` | object | `{}` = all defaults (`WaveTimeline.OASES_DEFAULTS`) | Red Canyon's oasis count and spacing (RedCanyon._roll_oases): |
| `oases.min` | int 1..6 | 2 | oases every run rolls at least |
| `oases.max` | int 1..6 (>= min) | 3 | the most a run rolls |
| `oases.extra_chance` | float 0..1 | 0.35 | the chance of each oasis past `min`, up to `max` (0.35 = a third oasis in about a third of the runs) |
| `oases.gap` | float m | 10 | the least open ground between two oases' dishes (each dish reaches 1.6 x its lake's radius); a larger gap can leave a run an oasis short where the map has no room |

Red Canyon's file: `"water_slow": 0.1`, `"oases": {"min": 2, "max": 3, "extra_chance": 0.35, "gap": 10}` (the defaults,
written out so the World card shows them).

#### Level Editor (tools/level_editor/fields.js, World card; checked by selftest_OASIS80.py)
Rows `water_slow` ("Water slow"), `oases.min` ("Oases (at least)"), `oases.max` ("Oases (at most)"),
`oases.extra_chance` ("Chance of one more oasis"), `oases.gap` ("Oasis spacing (m)"), each with help and the game's
default as its grey placeholder.

#### Code API (for other lanes and tools)
- `RedCanyon.lakes()` -> `[{center: Vector2, radius, level, floor, disc}]` (the first lake first); `lake_count()`;
  `lake_index(p: Vector2)` (the lake p is in or whose shore is nearest); `in_water(p)` (any lake);
  `water_level(p := Vector3.INF)` / `water_disc(p := Vector3.INF)` (the lake at or nearest p; no argument = the first
  lake, so old callers are unchanged); `lake_center()` / `lake_radius()` = the first lake; `oases_config()`;
  consts `LAKE_DISH` 1.6, `LAKE_R` (5.5, 7.5), `LAKE_WET` 1.02, `BUSH_LAKE_RELAX` 200, `BUSH_LAKE_NEAR` 6,
  `BUSH_EXTRA_TRIES` 200.
- `EnemyManager.map_lakes(map)` (any map: its lakes(), else its one lake_center/lake_radius/water_disc),
  `lakes_of(map)` -> `[Vector3(x, z, wet radius)]`, `lake_of(map)` = the first; `add_lake()` beside `set_lake()` for
  tests; `in_lake(p)` any lake; `_wade_tick()` (once a tick: marks who wades in `_wade_k`, the factor the walk reads), `_wade_mult(i)` (the same rule for one creature, tools and tests), `_wade_slow`.
- `Player._wade_mult()`, `Player.water_slow()` (static), `Player.WADE_AIR` 0.35.
- `Game._wade_level(lakes, at, fallback)`, `Game._discs_of(map)`, `Game._nearest_disc(discs, at)` (static).

## Pass 81: row pacing and the map's looks

### A roster row paced as waves (lane PACE)

All on a roster row (`timeline_data.roster[]`), read by WaveDirector as the plain dictionary (JsonContent and the .tres
carry them unchanged; no new export on WaveTimeline). The editor's fields: FIELDS.roster in tools/level_editor/fields.js
(`paced: true` marks the five waves-only ones).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `pace` | string | `"continuous"` | `"continuous"`: drawn into the cap by its weight at every spawn check, as every row always was. `"waves"`: comes as waves (below). Any other value plays continuous (the editor flags it). |
| `every` | number (s) | 30 | waves only: seconds between waves, the first at `t` + `offset`; 0 or less = one wave only. |
| `count` | int | the row's `pack`, else the creature's pack size (after `stats.pack`) | waves only: creatures a wave (at least 1), in the row's `pattern` and packs of its `pack`. |
| `offset` | number (s) | 0 | waves only: the first wave this long after `t` (below 0 = 0). |
| `respect_cap` | bool | true | waves only: true = a wave fills its channel's free room (at least one while any), the rest comes first at each spawn check as room frees until the row's next wave or its end; false = the whole wave at once on top of the cap (hard cap and max_alive still hold). |
| `trickle` | bool | false | waves only: true = also drawn continuously by its weight between its waves. |

A row's `weights` (presence) on a waves row: a wave due while the row weighs 0 does not come; the size of the weight
scales nothing (it still counts where every row is drawn by weight: the portal wave, the heaviest-row rule of an event
joining a row's numbers, and in the continuous draw with `trickle`).

GDScript: `WaveTimeline.ROW_PACES`, `ROW_WAVE_EVERY_DEFAULT` (30), `row_paced(r)`, `row_drawn(r)`, `row_wave_every(r)`,
`row_wave_start(r)`, `row_wave_index(r, t)`, `row_wave_time(r, k)`, `row_wave_times(r, end, limit)`,
`row_wave_count(r, pack_size)`; `WaveDirector.row_wave_state(index)` -> {k, owed, came, waves} (tests, tools).
model.js: `ROW_PACES`, `ROW_WAVE_EVERY_DEF`, `ROW_WAVE_KEYS`, `ETCH_MIN_PX` (3), `rowPaced`, `rowDrawn`, `rowWaveEvery`,
`rowWaveStart`, `rowWaveTimes`, `rowEtchTimes`, `rowWaveCount`, `waveBurstTimes`, `presenceSpans`, `thinTimes`.

docs/level_editor.md (Timeline tab, roster lane): the yellow etches along each bar's foot (a line where a continuous row
is drawn, a tick at each wave of a row paced as waves, both on a trickling one, a tick at each burst of a `waves[]`
block; ticks under 3 px apart thinned, every m-th kept, never merged), the chip "↻ 30 s ×20", the row form's Pacing
select and its five fields, the hover card's next wave; Settings -> Spawning: Burst min / max and Spawn check every
are the continuous rows' pacing.

### The water, the sand, the oasis ground (lane MAP)

No new content JSON keys (red_canyon.json untouched). The knobs are shader uniforms (set on the materials, defaults in
the shader files) and RedCanyon constants.

#### core/shaders/water_lake.gdshader (new; RedCanyon._water_material, one ShaderMaterial for every lake, `_water_mat`)
| uniform | type | default | meaning |
|---|---|---|---|
| noise_tex | sampler2D | art/env/noise_rgb.png (set by RedCanyon) | three smooth tileable noises, read raw |
| deep_color | vec3 (colour) | (0.04, 0.34, 0.50) | the middle |
| shallow_color | vec3 (colour) | (0.20, 0.62, 0.66) | towards the shore |
| shore_color | vec3 (colour) | (0.58, 0.62, 0.48) | wet sand through thin water (35% over the last 0.2 of the radius) |
| foam_color | vec3 (colour) | (0.93, 0.96, 0.92) | the lapping line and the glints |
| sky_color | vec3 (colour) | (0.78, 0.88, 0.94) | the far water's sky |
| deep_alpha / shallow_alpha | float | 0.9 / 0.62 | see-through in the middle / at the shore |
| shore_at / shore_wobble | float | 0.95 / 0.05 | where the water ends (fraction of the disc), how far the noise moves it (capped 0.985) |
| ripple_scale / ripple_speed | float | 0.085 / 0.022 | noise tiles a metre / drift |
| ripple_light / ripple_sharp | float | 0.08 / 2.2 | the ripple web's light and thinness |
| foam_strength | float | 0.35 | the lapping line |
| glint_scale / glint_from / glint_strength | float | 1.1 / 0.955 / 0.7 | glint size (tiles a metre), rarity, brightness |
| sky_strength | float | 0.35 | the far water's sky |
| hell | float 0-1 | 0 | stage 3, set by RedCanyon._apply_hell |

#### core/shaders/terrain_painted.gdshader (new uniforms)
| uniform | type | default | meaning |
|---|---|---|---|
| noise_tex | sampler2D | art/env/noise_rgb.png (set by RedCanyon) | macro variation, the oasis edge and grass |
| macro_scale / macro_strength | float | 0.019 / 0.07 | the sand's broad light and shade: tiles a metre / +- strength |
| oasis_ragged | float | 0.32 | noise added to the vertex alpha (the oasis edge) |
| oasis_damp_from / oasis_wet_from | float | 0.1 / 0.72 | where damp earth / wet sand begin (in the broken alpha) |
| oasis_damp / oasis_wet | vec3 (linear multiplier) | (0.93, 0.90, 0.80) / (0.80, 0.77, 0.72) | their shades |
| oasis_wet_grey | float 0-1 | 0.3 | how much of wet sand's colour goes to grey first |
| oasis_grass / oasis_grass_amount | vec3 (colour) / float | (0.40, 0.52, 0.27) / 0.5 | the sparse green on the damp ground |

#### world/maps/red_canyon/RedCanyon.gd
| name | type | value | meaning |
|---|---|---|---|
| OASIS_WET_TO | const float | 0.6 | metres past a lake's edge still fully wet |
| OASIS_REACH / OASIS_REACH_PER_R | const float | 3.5 / 0.45 | the oasis ground's reach: metres + this many of the radius |
| OASIS_WOBBLE | const float | 2.2 | metres the reach moves either way (noise) |
| NOISE_TEX | const String | res://art/env/noise_rgb.png | the shared noise |
| oasis_wet(p: Vector2) -> float | func | | 0..1, the vertex alpha the terrain shader reads |
| _water_material() -> ShaderMaterial | func | | the lakes' one material (also `_water_mat`) |
| vertex colour alpha | | | the oasis ground (r river, g shade, b rock as before) |

#### tools/gen_textures.py
| name | meaning |
|---|---|
| `noise_rgb` maker (`--only=noise_rgb`) | art/env/noise_rgb.png, 256 px, three noises (seeds 101-103) |
| SAND_SRC | tools/art_src/sand_klein_s8102.png, the painting sand() starts from |
| SAND_CONTRAST | 0.06: the painting's light and dark per standard deviation |
| sand_tileable(a), sand_procedural(size) | the painting made tileable; the old sand (its mean = the colour; the fallback) |

## Pass 82: the sand and the XP curve

### The sand (lane SAND)

#### content/maps/red_canyon/red_canyon.json (timeline_data)
| key | type | default | meaning |
|---|---|---|---|
| sand | String | "" (= "pass81") | which sand the open ground is painted with: "pass81" (pass 81's, today's), "dunes" (Soft dunes), "dunes_pebbles" (Soft dunes + pebbles), "ripples" (Wind ripples), "ripples_pebbles" (Wind ripples + pebbles). An unknown id plays pass81. Not in the file today (Garry picks). |

Read by JsonContent.timeline_from_dict -> WaveTimeline.sand (`@export var sand: String = ""`) -> RedCanyon.map_sand_id.
Level Editor: Settings tab, World card, row "Sand" (fields.js, type select, def 'pass81', the five named in words with
help); under it a preview of the chosen sand in the game (tools/level_editor/sand_previews.png, settings.js).

#### world/maps/red_canyon/RedCanyon.gd
| name | type | value | meaning |
|---|---|---|---|
| SANDS | const Dictionary | id -> {file, scale, name, short} | the five sands; `scale` = the painting's size on the ground against pass 81's (sand_scale) |
| SAND_DEFAULT | const String | "pass81" | the sand for none / an unknown id / a missing painting |
| sand_id | var String | | the sand the terrain is painted with now |
| map_sand_id() -> String | func | | the map file's sand, or the default |
| sand_or_default(id) -> String | static func | | `id` when SANDS has it and its painting exists, else SAND_DEFAULT |
| sands() -> Dictionary | func | | SANDS (the arena lists it) |
| set_sand(id) | func | | paints the built terrain with sand `id` on the spot (the arena's WORLD tab) |

#### core/shaders/terrain_painted.gdshader
| uniform | type | default | meaning |
|---|---|---|---|
| sand_scale | float | 1.0 | the sand painting's tiling x tiles_per_metre (below 1 = bigger on the ground); the river bed and the rock keep theirs |

#### ui/ArenaPanel.gd
WORLD tab: a "Sand" row (node SandChoice) with the five by their `short` labels (Pass 81, Dunes, Dunes+P, Ripples,
Rip+P); `sand_options() -> Array` ([id, short] for every sand). For the visit only.

#### tools/gen_sand.py (new)
| command | what |
|---|---|
| `--paint [--prompts dunes,pebbles,drift,drift_pebbles] [--seeds 8201,...]` | Klein paintings -> tools/dl/p82/SAND/ai/raw_<prompt>_s<seed>.png (comfy lock) |
| `--seam [--only <stem>,...] [--force]` | the three-repaint tiling -> ai/tile_<stem>.png (model outputs kept as fixA/B/C_<stem>.png) |
| `--cands [--only ..] [--band --fine --chroma --scale --tag --no-proc]` | candidates at today's colour + a list for the shots tool |
| `--keep [--only <id>,...]` | the picked tiles -> tools/art_src/sand_<id>_src.png |
| (no flag) `[--only <id>,...]` | writes game/art/env/sand_<id>.png from SANDS (prompt, seed, band, fine, chroma) |
| `--previews <shots dir>` | tools/level_editor/sand_previews.png from the shots tool's sand_<id>.png |

#### game/tools/_p82_SAND_shots.gd (new, a capture tool)
`-- out=<dir> list=<txt "name path [scale]"> [seed=5] [spots=sand,lake,crowd,far] [key=<sand id>] [vp=864x1920]`:
the candidates swapped onto the terrain at the same spots in one run, shot through an 864x1920 SubViewport (the phone's
3D canvas) whatever the desktop allows; `key=` builds the map with that sand as the file would and shoots it.
`game/tools/_p82_SAND_arena_shot.gd`: the arena's WORLD tab and its Sand row.

### The XP curve (lane XP)

All in `timeline_data` of a map JSON. Read by JsonContent.timeline_from_dict into `WaveTimeline.xp_curve` (Dictionary,
read as it is), played by `XpCurve.need` (game/core/data/XpCurve.gd) through `Run.xp_to_next`. The Level Editor's
Settings tab draws them in the **XP per level** card (with `xp_need_mult`, which moved there from Scaling).

| key | type | default | meaning |
|---|---|---|---|
| `xp_curve` | block | absent | the XP growth: `{"type": <type>, <type>: {numbers}}`. Absent / `{}` / unknown type = today's quadratic exactly. Every type × `xp_need_mult` |
| `xp_curve.type` | `quadratic` \| `linear` \| `exponential` \| `power` \| `table` | `quadratic` | which block is played; the others are kept in the file, not played |
| `xp_curve.quadratic.base` | number | 15 | base + linear × L + quad × L² |
| `xp_curve.quadratic.linear` | number | 6 | the XP added per level |
| `xp_curve.quadratic.quad` | number | 0.5 | the L² part |
| `xp_curve.linear.base` | number | 21.5 | base + step × (L − 1): what level 1 needs |
| `xp_curve.linear.step` | number | 16.5 | what each level needs more than the one before |
| `xp_curve.exponential.base` | number | 40 | base × growth^(L − 1): what level 1 needs |
| `xp_curve.exponential.growth` | number | 1.11 | each level needs this many times the one before |
| `xp_curve.exponential.cap` | number | 0 | the most any level needs (before × xp_need_mult); 0 = no cap |
| `xp_curve.power.base` | number | 6.5 | base × L^power: what level 1 needs |
| `xp_curve.power.power` | number | 1.33 | the exponent |
| `xp_curve.table.points` | [[level, XP], ...] | today's curve at 1, 5, 10, 20, 30, 40, 50, 60 | straight between listed levels; before the first: the first's XP; levels rounded, the last listed for a level wins; no readable point = the default |
| `xp_curve.table.after_growth` | number (fraction) | 0.025 | past the last listed level each level needs this much more than the one before (0 = repeats) |

Example: `"xp_curve": {"type": "exponential", "exponential": {"base": 40, "growth": 1.1, "cap": 4000}}`.

Run record (analytics/SCHEMA.md, lane STATS's file): `map_settings.xp_curve` = `{"type": ..., <that type's numbers with
the defaults filled in>}` (RunAnalytics.map_settings), beside `xp_need_mult`.

## Pass 83: boss HP, power, a row's draw interval

### Boss HP by seconds and the hero's power (lane SCALE)

| Key | Where | Type | Default | Meaning |
|---|---|---|---|---|
| `boss_hp_scaling.mode` | map `timeline_data` | "seconds" \| "dps" | "seconds" (WaveTimeline.BOSS_HP_MODE_DEFAULT) | how a boss's HP is set when it arrives: seconds of the hero's full DPS, or pass 72's peg to the recent real DPS |
| `boss_hp_scaling.seconds` | map `timeline_data` | {boss id: number} | {tumbleweed_king 25, gila_grande 40, brander 60} (BOSS_SECONDS_DEFAULTS) | seconds of full DPS the boss lasts at least; 0 = its data HP |
| `power_hp_scaling` | map `timeline_data` | number | 1 | creature HP × power ^ (this − 1); 1 = none |
| `power_hp_max` | map `timeline_data` | number | 10 | the cap on that factor (1 ÷ it the least) |
| row `power` | run record samples | number (0.01) | — | the hero's power level (HeroPower) |
| row `full_dps` | run record samples | number (0.1) | — | full DPS on one target (HeroPower.full_dps) |
| row `ehp` | run record samples | number (0.1) | — | effective HP (HeroPower.ehp) |
| row `power_hp` | run record samples | number (0.001) | missing = 1 | the creatures' HP factor the power gives |
| `boss_start` `mode`, `seconds`, `full_dps` | run record events | — | — | the seconds mode's numbers when a boss came |
| `map_settings.boss_hp_scaling.mode/.seconds`, `map_settings.power_hp_scaling/.power_hp_max` | run record header | — | — | as played |
| sim series `power` | sim_run.gd / sim_avg.js / sim_batch.py | level series (band) | — | the Sim's and the dashboard's Hero power chart |

Code: `HeroPower` (core/systems/HeroPower.gd: full_dps, ehp, power_from, measure, now, current, boss_dps_now, forget,
crowd_of, element_dps, weapon_dps, crit_factor); WaveTimeline.boss_hp_mode / boss_seconds / boss_seconds_hp /
power_hp_factor; WaveDirector.boss_seconds_target / power_hp_mult; EnemyManager.boss_hp_target.
Level Editor: fields.js rows may carry `showIf(tl)` (settings.js skips a row whose showIf is false).

### A row's draw interval (lane TIMELINE)

| Key | Where | Type | Default | Meaning |
|---|---|---|---|---|
| `interval` | a roster row (`timeline_data.roster[]`) | number (s) | none (= the map's `spawn_interval`, the spawn check) | A row in the continuous draw (a continuous row, or a waves row with `trickle`) is drawn on its own clock: a draw at the frame it opens, then every `interval` real seconds (through boss fights and the portal wait, like the spawn check), instead of at the director's spawn check. Each draw is a burst of randi(burst_min..burst_max) load units x the row's weight / the weight of every open drawn row of its channel. Below 0.1 counts as 0.1. Not a number above 0 (0, negative, a string, a bool) = no own clock. Ignored on a waves row that does not trickle. |

Read by WaveDirector as the plain dictionary (JsonContent and the .tres carry it unchanged; no new export on
WaveTimeline). The editor's field: FIELDS.roster in tools/level_editor/fields.js, label "Draw every (s)", `drawn: true`
(shown while the row is in the continuous draw), placeholder the map's spawn_interval.

GDScript: `WaveDirector.ROW_INTERVAL_MIN` (0.1), `row_has_interval(r)`, `row_draw_interval(r, spawn_interval)` (static),
`_tick_row_intervals(delta)`, `_interval_part(roster, due)`, `_spawn_burst(due := [])`, `_burst_from(roster, room,
bodies, due := [])`, `_row_draw_left` (row key -> seconds to its next draw).

model.js: `ROW_INTERVAL_MIN`, `rowHasInterval`, `rowDrawInterval`, `rowDrawTimes(r, t0, t1, si, lateT, limit)`,
`windowShares(est, t0, t1)` -> {t0, t1, all, src, share, other}; `burstAvg(rows, room, lo, hi, frac)`.

Page settings (the browser's, never the map): the window box `#win-secs` next to Snap on, seconds 1..120, default 5,
localStorage `88fits-editor-window`; `Timeline.setWindow(n)`, `Timeline.winSecs`.

Removed: the Timeline's Share lane (FIELDS.LANES `share`, timeline.js renderShare / shareCard, inspector.js shareForm,
App.select kind `share`, its CSS).

## Pass 84: one spawning language

### Rows, the floor, the converter (lane SPAWN)

#### Roster row (`timeline_data.roster[]`): new keys (every older key unchanged)
| key | type | default | meaning |
|---|---|---|---|
| `pace` | "continuous" \| "waves" \| **"once"** | "continuous" | "once": one wave at `t` + `offset`, `count` creatures (default `pack`, else the creature's pack size). Once rows stay out of the mix (see below). |
| `every` | number \| **[min, max]** | 30 | waves row's gap. [min, max]: a fresh random gap each wave (a timer: the next wave is that gap after the one it fired). The editor's etches and the estimate use the middle. |
| `enemy` | id \| **[ids]** \| **"roster"** | | a list: one creature per wave (per draw for a continuous row) drawn by `enemy_weights`; "roster": each creature drawn from the mix rows live at that second by their creature's `elite_weight` (the coloured-elite draw), coming with that row's variant, stats and fixed numbers unless this row sets its own `variant` / `stats`. |
| `enemy_weights` | [numbers] | evenly | the list's pick weights, parallel to `enemy` (an entry past their end weighs 1, 0 never comes). **Not `weights`**: on a row `weights` is the presence keyframes [[t, w], ...] (pass 54), so the events' pick list is `enemy_weights` on a row. |
| `elite` | "" \| "random" \| modifier id | "" | every creature of the row wears it. Without a `pattern`: each of `count` is one coloured-elite *arrival* (WaveDirector._spawn_elite: alone, as its pack or a ring by the creature's `elite_formats`, the "MOD NAME" toast), ignoring the cap and the hard cap like the events. With a `pattern`: `count` creatures in that pattern, each wearing it, under the row's respect_cap. Waits for colour (`colour_after_kills`): an elite wave asks again each second; a continuous elite row is out of the draw until then. An elite paced row is a timer whose gap Hot Sauce shortens (elite_pace). |
| `special` | bool | false | every creature comes as its coloured variance special (EnemyManager.force_special), colour or not; no banner unless `banner`. |
| `banner` | text | "" | a toast (the swarm orange) the first time a wave brings anything ("SWARM!"). |
| `ring_radius` | m | none | pattern "ring" with a radius: the classic even ring of that radius round the hero (EnemyManager.spawn_ring, the swarm event's; converted swarms 16). Without it a ring row is the thick band at 11.7 m (pass 57). |
| `respect_hard_cap` | bool | true | false: the row's waves come on top of the map's hard_cap too, stopped only by the body limit (EnemyManager.MAX 320), as the swarm events did. Read by every paced row (pass 81's too). Converted swarms carry false. |
| `chance` | 0..1 | 1 | a once or waves row's roll per run (skipped when it fails), as an event's chance. |
| `t_jitter` | s | 0 | a once or waves row moves by a draw inside +- this per run (never before 0), as an event's. |
| `role` | "fodder" \| "swarm" \| "tank" \| "ranged" \| "elite" \| "special" \| "" | "" | the editor's colour and grouping only; the game ignores it. |
| `name` | text | | a label; the game ignores it. |

**The mix**: a row that names one creature by its id, has no `elite`, no `special` and is not `once`
(WaveTimeline.row_in_mix). Only the mix is read where the game asks "who is on the roster now": the portal wave, a
coloured Elite's candidates (the "roster" draw), and the pass 58 join (an event's / once row's numbers from the row that
brings the same creature then).

**Numbers** (pass 58's R1 kept): a mix row's creatures are fixed from its start (as before); a list row's each creature
from the row's start (key `row:<id>#<k>|<creature>`); a "roster" creature plays its drawn row's numbers; a **once** row
takes the event rule (the moment it fires, or a mix row's that brings the same creature and look then: what a swarm did).

#### Map keys
| key | type | default | meaning |
|---|---|---|---|
| `floor_curve` | [[t, n], ...] | [] (none) | the density floor: while fewer than n creatures are alive on the regular channel the director draws the regular continuous rows at once, every frame (not waiting for the spawn check), a pack at a time by weight, each cut to the lack, the cap's room and the hard cap; at most 64 a frame. Absent = today's play. Linear between points, flat outside (sample_points). |

#### Events
Events keep only `boss` and `elite_boss`. An old map's `swarm` / `elite` / `elite_every` events and `waves[]` still play
in the game exactly as before; the Level Editor converts them to rows on load (Model.convertLegacy) and saves rows;
`python tools/migrate_timeline.py --map <id> [--write | --check]` does the same to a file.

#### Conversion (Model.convertLegacy == migrate_timeline.convert_legacy)
- swarm -> {name (event's, else "Swarm"), t, enemy (a list keeps `enemy_weights` from the event's `weights`), variant,
  weights [[t, 1]], pace "once", count (default 40), pattern (pack / scatter / in_front as given, else "ring" +
  ring_radius 16), pack (pattern pack: the event's pack, else the count: one point), respect_cap false,
  respect_hard_cap false, special true or
  banner "SWARM!", chance, t_jitter, role "special" | "swarm", stats}
- elite -> {name "Coloured elite", t, enemy (or "roster"), weights, pace "once", count 1, respect_cap false, elite (mod or
  "random"), role "elite", stats ...}
- elite_every -> as elite with pace "waves", every = interval (number or [min, max]; default 90), name "Elites every".
- waves[] entry -> one row per alternative: pace "waves" (every > 0: every, count = burst, until = t + every x
  ceil(count / burst) and/or its until) or "once" (count = burst, cut to its count), pattern, pack, respect_cap,
  channel, elite, banner = toast, chance = the alternative's share when it has several, stats. Notes say what differs.
- Rows appended after the roster with fresh ids r<n>; a map with nothing to convert is untouched.

#### Model.js API (lane TIMELINE)
See status_SPAWN.md "FORMAT READY".

### The Timeline tab (lane TIMELINE)

No new game keys of its own: the row keys are lane SPAWN's (keys_SPAWN.md); the Level Editor edits all of them.

#### Map keys the editor now edits
| key | type | default | where |
|---|---|---|---|
| `floor_curve` | [[seconds, creatures], ...] | none | Settings → Cap (field type `floor_points`), the Curves → Floor lane (drag, double-click), its inspector |
| roster row `pace` "once", `every` [min, max], `enemy` list / "roster", `enemy_weights`, `elite`, `special`, `banner`, `ring_radius`, `chance`, `t_jitter`, `role`, `name` | see keys_SPAWN.md | | the row form (inspector groups Schedule, Creature, Where and how) |

#### Overrides the row form gained (all read by EnemyDef.with_overrides already)
`size_mult`, `radius_mult`; `ranged.keep_distance|telegraph|damage|splash|count|cone_deg|knockback`;
`charge.windup|duration|trigger_range|knockback`; `kamikaze.trigger|windup|radius|damage|knockback`;
`artillery.stand_off|windup|reload|missile.speed|missile.turn|missile.damage|missile.area`;
`sniper.stand_off|first|aim|lock|interval|spoil_on_hit`; `flee_on_hit.seconds|speed_mult|interrupts`.
Not overridable per row (the game reads them from the creature only): `brain`, `death_burst`, `caster`, burrowing.

#### Page settings (localStorage, never written to the map)
| key | what |
|---|---|
| `88fits-editor-sections-<map>` | collapsed sections, spawn-row groups (`group:<key>`) and open recipe boxes (`how:<id>`) |
| `88fits-editor-tlprefs` | group rows by, colour rows by, composition mode and source, challenge measure |
| `88fits-editor-zones84` | the Challenge zone limits per measure |
| `88fits-editor-sim-<map>` | the Sim shown ('-' = none) |
| `88fits-editor-simlife` | the estimate takes the Sim's lifetimes |
| `88fits-editor-insp-folded` | the inspector folded |
| `88fits-editor-igroups` | the row form's open groups |

#### New files
- tools/level_editor/timeline_model.js (page-free; `TimelineModel`), loaded after model.js, before timeline.js.
- tools/level_editor/selftest_TIMELINE84.py.

### The Sim's overlay (lane SIMVIEW)

No content or map key: everything is tool output. Definitions: balancing_SIMVIEW.md. The route's shape:
status_SIMVIEW.md "OVERLAY READY".

#### A player's JSON (game/tools/sim_run.gd; schema stays 1, additions only; tools/dl/p77/keys_SIMRUN.md's table grows)
| Key | Type | Meaning |
|---|---|---|
| `alive_hell` | series int | creatures alive on the hell channel |
| `load`, `load_hell` | series float 0.1 | the regular / hell channel's crowd in cap units (each its cap_share) |
| `cap_hell` | series float 0.1 | hell_cap_at(stage) x the cap |
| `hard_cap` | series int | the map's body limit |
| `cap_full` | series 0..1 (0.01) | share of the second's checks (every 0.2 s of play) the regular channel had no room |
| `threat` | series float 1 | sum of max_hp x bite / contact_cd over the creatures alive, the boss left out |
| `hero_dps`, `hero_ehp` | series float 0.1 | HeroPower full DPS and effective HP |
| `challenge` | series float 0.001 | threat / (hero_dps x hero_ehp) |
| `alive_hell_by` | {id: [int]} | alive on the hell channel by creature |
| `starving_by` | {row key: [0..1 (0.01)]} | share of the second's checks the row starved |
| `life_by` | {id: {n: [4 ints], s: [4 floats], gone, open}} | deaths and seconds lived per stage slot (1, 2, 3, after) |
| `meta.rows_played` | [{key, k, id, enemy, t, until, channel, pace}] | the roster as played (`meta.rows` stays the row count) |
| `meta.simview_ms` | float | the sampler's cost, ms of wall time a second of play |

#### A sim folder
| File | Meaning |
|---|---|
| `overlay.json` | sim_batch.py overlay(): the runs by clock second (status_SIMVIEW.md's `overlay` block, without `names`/`top`) |

#### result.json (sim_batch.py aggregate(), sim_avg.js aggregate())
`series.threat` gains p10/p90; `series.challenge` is {median, p10, p90, n}; `breakdowns.alive_hell_by` and
`breakdowns.starving_by` (kind "level"); the other new series are plain means.

#### Route
`GET /api/sim/overlay?map=<id>[&id=<sim>][&top=N]` (tools/level_editor/sim_io.py overlay_record): always 200;
`{ok: true, sim: {...}, overlay: {...}}` or `{ok: false, reason}`.

#### Page modules
- tools/level_editor/sim_avg.js: `SimAvg.overlay(players)` (players [{k, d, rec}]), `SimAvg.overlayRows(d)`,
  `OVERLAY_SERIES`, `OVERLAY_BANDS`, `OVERLAY_MEDIANS`, `OVERLAY_RULES` (the definitions' text).
- tools/level_editor/sim_model.js: the Sim tab's "The crowd against the cap" draws `load` (dotted) when the sim has
  it; new charts `cap_full` ("Cap full", % of the second) and `challenge` ("The crowd against the hero", median + band)
  when the sim has them (older sims: unchanged chart list).

## Pass 87: stages

### stage_list, Endless (lane SGAME)

#### timeline_data.stage_list (Array, default [])
One entry per stage, in order. Stage k's window on the run clock starts at the sum of the earlier `length`s.
| key | type | default (key left out) | meaning |
|---|---|---|---|
| id | string | "s<k>" | the stage's id (analytics, the menu's picture name) |
| name | string | "Stage <k>" | the Stages menu's and the Results' name |
| length | number (s) | `stage_length` | seconds before its boss (its window's length); Red Canyon 430 / 600 / 780 |
| boss | enemy id | the boss event at the window's end (else the last inside it) | the boss that ends the stage; the director brings it at the window's end when no boss fight began (no boss event there, or one whose t_jitter moved it past) |
| description | string | "" | the Stages menu's words |
| difficulty | string | "" | the Stages menu's difficulty line |
| filter | {color "#rrggbb", strength 0..1} | {"#000000", 0} | the world's tint (lane SLOOK draws it; SLOOK may add `actors`) |
| hell | bool | stage index >= 2 | the hell look (the red ground, pass 43) |
| shot | res:// path | "" | the Stages menu's picture (lane SLOOK: res://art/ui/stages/<map>_s<k>.jpg) |
| endless | object | {} | Endless keys for this stage only (each wins over the map's `endless` key of the same name) |
[] = the fallback (maps without the block): `stages` windows of `stage_length`, names "Stage k", hell from stage 3.
`stage_length` / `stages` stay in the file as that fallback.

#### timeline_data.endless (Object, default {}; a key left out plays WaveTimeline.ENDLESS_DEFAULTS)
| key | default | meaning |
|---|---|---|
| portal_seconds | 60 | the portal's countdown to Endless after the boss, seconds of the run clock (stands still behind every screen but the portal dialog) |
| every | 10 | seconds between Endless waves (Endless's own clock, Run.endless_time) |
| first_wave | 120 | creatures in the huge first wave (round the hero, past the live cap; the hard cap holds) |
| wave_size | 30 | creatures in wave 2 |
| wave_growth | 2 | more creatures in each later wave: wave k = wave_size + wave_growth x (k - 2) |
| cap | 1.0 | the crowd kept up between the waves, x the stage-end cap (load units); 0 = the waves alone |
| hp | 1.5 | wave 1's HP multiplier on the creatures' fixed numbers (the late roster's, from each row's own start) |
| atk | 1.2 | wave 1's damage multiplier |
| speed | 1.15 | wave 1's speed multiplier (times the stage's speed_per_stage) |
| hp_growth | 0.15 | COMPOUNDING per wave: wave k = hp x (1 + hp_growth)^(k-1) |
| atk_growth | 0.1 | COMPOUNDING per wave, as hp_growth |
| speed_growth | 0.02 | LINEAR per wave: wave k = speed x (1 + speed_growth x (k-1)) ... |
| speed_max | 1.6 | ... never past this |
| xp_share | 0.35 | a kill's XP in Endless, a share of what it would drop (gems, Prospector's, Eureka's) |
| coin_chance | 0.05 | a creature's coin roll happens only this share of the time in Endless (very rarely) |
| roster_window | 60 | the "late roster" Endless draws from: the mix rows (one creature, no elite, not a special, not a once row; any pace, either channel) open in the stage's last this-many seconds, each at its weight at its last open second there (the map's skins when none) |
No bosses, Elites or specials come in Endless; power-ups and creature chests drop as before.
The old `endless_wave_seconds` / `endless_wave_mult` / `endless_mult_per_minute` are no longer played (the old endless
after stage 3 is gone).

#### Launch key (user://debug_launch.json, Run.launch_override)
| key | type | meaning |
|---|---|---|
| stage | int, 1-based | the stage the run plays (a fresh run at its window's start); the sim's `stage=k`, the Watch, smoke_run's boss=2, hell_check (3) |

#### Save
| key | type | meaning |
|---|---|---|
| stages_beaten | {map id: [bool, ...]} | a stage's boss killed in a run of it; stage i+1 unlocks once stage i is beaten; filled once from old saves ("stages_migrated" in `once`) |

#### Code API (for other lanes)
See the API READY block at the top of tools/dl/p87/status_SGAME.md.

### The stage filter (lane SLOOK)

All in `timeline_data.stage_list[k]` (SGAME's entry; STOOLS edits them in the stage tabs).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `filter.color` | "#rrggbb" (or [r, g, b] 0..1) | "#ffffff" | the colour of the stage's "glass" over the world. The world is drawn x white.lerp(color, strength) on the screen: black dims, a blue cools and dims, a red warms and dims. A bad colour plays as none. |
| `filter.strength` | float 0..1 | 0 | how strong the glass is (0 = none: stage 1; the quads are not drawn at all). |
| `filter.actors` | float 0..1 (optional) | 0.35 (`StageLook.ACTORS_DEFAULT`) | the share of the strength the creatures, the hero, power-ups and flowers take (the paintings that are not scenery), so they stay brighter than the ground. 1 = tinted like the world, 0 = untouched. The Level Editor need not show it; it may offer it as "creatures" next to strength. |
| `hell` | bool | false (without a stage_list: true from the third stage) | pass 43's hell ground (RedCanyon.set_hell: redder darker sand, the water and the fort wall with it, warmer ambient and haze); now read from the entry instead of "stage index >= 2". |

What the filter does NOT tint (drawn after it, readability): the ground marks (every telegraph ring, disc, line, cone,
the Salt's patches, scorches, spills, the structures' rings), the creatures' and props' ground shadows, gems, coins and
their glints, the creatures' outlines behind scenery, every effect (bursts, blood, flames, tracers, beams), the
projectiles, badges, damage numbers and all UI. The dust gusts and the dust devil ARE tinted (they draw before it).

Code: `StageLook.of(game).show_stage(s)` (Game's stage_started), `StageLook.filter_mults(entry) -> [world, creatures]`,
`StageLook.entry_of(timeline, s)`, `StageLook.hell_of(timeline, s)`, `StageLook.PRIORITY` (-7).

Pictures: `art/ui/stages/<map>_s<k>.jpg` (k from 1), 1248 x 480 JPG (q 0.88), made by
`bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/stage_shots.gd`
(then `--import`); the entry's `shot` names it. Re-run it after changing a stage's filter or roster so the card shows it.

### The retune (lane TUNE)

No new key, param, special or stat. Lane TUNE changed only numbers in `game/content/maps/red_canyon/red_canyon.json`
(timeline_data), all of them keys that already exist and that the Level Editor already edits:

| Key | What changed | Where in the editor |
|---|---|---|
| `roster[].stats.hp_mult` (stage-2 and stage-3 rows, once-rows included) | the migrated number x a stage factor ramping through the window (see balancing_TUNE.md) | a row's form, HP x |
| `roster[r18].t` | 430 -> 431 (the blue slimes start a second into stage 2, so they read stage 2's side of the 7:10 steps) | a row's form, start |
| `damage_curve.points` after 430 s | stage 2's and stage 3's own ramps (balancing_TUNE.md) | Curves -> ATK x |
| `cap_curve` | a point a second into each window (stage 2: 25, stage 3: 35) and one back on the old line later | Curves -> Cap |
| `events[elite_boss at 730 / 1420].stats.hp_mult` | 0.94 -> 0.8, 1.33 -> 0.45 | the event's form |
| `events[boss at 1030 / 1810].stats.hp_mult` (new on those events; the key existed) | 0.3 / 0.15: only the data-HP floor of the seconds mode | the event's form |
| `endless.atk`, `endless.hp_growth`, `endless.atk_growth`, `endless.speed_growth` | lane SGAME's defaults 1.2 / 0.15 / 0.1 / 0.02 -> see balancing_TUNE.md | Settings -> Endless (lane STOOLS) |

`stage_mults` [1, 2.2, 3.34] are Garry's and are unchanged (they also set the coins' worth: x round(stage mult), so
stage 2 still pays x2 and stage 3 x3).

### Stages in the tools and the analytics (lane STOOLS)

Every new key, argument and field this lane added (the map's `stage_list` and `endless` blocks themselves are lane
SGAME's: keys_SGAME.md; the filter's `actors` is lane SLOOK's: keys_SLOOK.md). Defaults in brackets.

#### Level Editor (tools/level_editor)
- **Map keys the page edits** (no new ones): `timeline_data.stage_list[k]` {`id`, `name`, `length`, `boss`, `description`,
  `difficulty`, `filter` {`color` "#rrggbb", `strength` 0..1, `actors` 0..1 (SLOOK's, 0.35 unset)}, `hell`, `shot`} on a
  stage's card; `timeline_data.endless.*` (portal_seconds, every, first_wave, wave_size, wave_growth, cap, hp, hp_growth,
  atk, atk_growth, speed, speed_growth, speed_max, xp_share, coin_chance, roster_window) in Settings -> Endless. The old
  `endless_wave_seconds` / `endless_wave_mult` stay in Settings as "Old ..." (not played since pass 87).
- **Page settings** (browser only, never in the map): `88fits-editor-stageview-<map>` (the open stage tab: `all` or a
  0-based index); `88fits-editor-sim-<map>[-s<k>]` (each tab's Sim).
- **model.js API** (page-free, Node): `STAGE_LIST_KEYS`, `hasStageList(tl)`, `stageList(tl)` -> [{i, id, name, start, end,
  length, boss, entry}], `stageWindow(tl, s)`, `stageStart/stageEnd/stageLen(tl, s)`, `stageMarks(tl)`; `stageAt(tl, t)`
  (with a stage_list: the last stage past the end, as WaveTimeline.stage_at); `fixedFrom` (with a stage_list: always the
  row's start); `STAGE_EDGE` (0.5 s), `ENDLESS_DEFAULTS`, `endlessValue(tl, key, s)`, `portalTimer(tl, s)`,
  `endlessWaveSize(tl, wave, s)`, `endlessMults(tl, wave, s)`; `spawnEstimate(tl, creatures, {stage: k, ...})` (a stage
  run; its result's `stage` {i, start, end, portal, endless, waves}); `stagesEstimate(tl, creatures, opts)` (every stage
  run stitched: the All tab).
- **stage_model.js** (`StageModel`, page-free, Node): `FILTER_DEF`, `FILTER_PRESETS` (none, evening, bloodmoon, dawn,
  storm, night), `filterOf(entry)`, `bossEventOf(tl, s)`, `bossOf(tl, s)`, `ensureList(tl)`, `newStageId(tl)`,
  `mapTimes(tl, f, endFix)`, `setLength(tl, s, len, 'keep'|'stretch')`, `lengthPreview`, `addStage(tl)`,
  `removeStage(tl, s)`, `removePreview`, `setBoss(tl, s, id)`, `setField(tl, s, key, value)`, `describe`, `issues(tl)`
  -> [{i, level, msg}] (validation keys `stage:<i>`).
- **App** (app.js) gained `stageList, stageStart, stageEnd, stageLen, stageWindow, viewStage, viewStart, setStageView,
  portalSeconds`; selection kind `{kind: 'stage', i}`.

#### The bot (game/tools/bot/Bot.gd)
- Option `portal`: "endless" (every preset) | "extract"; `PORTAL_CHOICES`; in sim_run.gd's BOT_ARGS, sim_batch's BOT_KEYS, the Watch's bot
  form (`bot.portal=`).

#### The Sim
- **tools/sim_batch.py**: settings `stage` (int, 1-based [1], 1..20 and at most the map's stages); CLI `--stage k`;
  each player's command gets `stage=k`; `map_stages(map_id)` (the map's windows and bosses as the game reads them);
  `save_stages(save_dir=None)` -> ({map: [bool...]}, note) (the PC save's stages beaten, an unmigrated save's from its
  old boss flags and kill totals); result.json `players[].stage`, `.outcome`, `.boss_killed`, `.endless_s`;
  `summary.stage_run` {runs, stage, boss_killed, outcomes {outcome: count}, endless_runs, endless_s_median} (null for a
  sim from before pass 87). Twin: tools/level_editor/sim_avg.js (`stageRunSummary`).
- **game/tools/sim_run.gd** meta: `stage` (1-based), `outcome` (Run.outcome() for a run that ended by itself; a run the sim
  stopped: `stopped`, `stopped_after_boss` or `stopped_endless`), `boss_killed`, `endless_s`,
  `stage_clock` (the `stage=` argument itself is lane SGAME's).
- **tools/level_editor/jobs.py** sim spec: `stage` (int [1]); the job passes `--stage`. sim_io.py's Watch button passes
  `--stage`. The Sim tab's form: `stage` (its Stage box).

#### The Watch
- **tools/watch.py**: `--stage k` (1-based [1]) -> the Watch's `stage=k`; setup.json gains `save_stages` {map: [bool]}
  and `save_stages_note`; `refs[].stage` (0 = a whole-run Sim from before pass 87); `ref_stage_ok(sim_stage, stage)`.
- **game/tools/watch**: arg `stage=` (1-based); settings `stage` (WatchSetup.defaults_from_args / collect);
  `WatchSetup.stage_open(beaten, k, all)`; `WatchSetup.ref_for(refs, hero, map, picks, stage = 1)`;
  `Watch.launch_of(hero, map, seed, spawn, stage = 1)` (launch key `stage`); `Watch.stages_beaten_for(mode, map, mdef,
  doc)`; check actions `setup.stage=<k>`, `setup.unlocks=all|save`.

#### The run record (game/core/systems/RunAnalytics.gd; analytics/SCHEMA.md)
- Header (at the start and the end): `stage_index` (0-based), `stage_id`, `stage_name`, `stage_start`, `stage_length`,
  `stage_count` (`stage` stays 1-based); at the end: `outcome` (extracted | died_endless | died_after_boss | died | quit),
  `boss_killed`, `stage_clock`, `endless_s`, `run_time`. `RunAnalytics.stage_header()` (static), `stage_end_fields()`,
  `STAGE_END_PROPS`.
- Row: `en` (seconds into Endless; missing before it). Phase 3 = Endless.
- Events: `stage_beaten` (level = the stage, `stage_clock`); Endless begun is Game's own `endless` event (lane SGAME).

#### PostHog (game/core/autoload/Analytics.gd; tools/posthog_boards.py)
- Super properties of every run event: `stage_id`, `in_endless` (bool), `endless_wave` (0 outside); `stage` as before.
- Events: `stage_beaten`, `endless_started`; `stage_cleared.choice` = `extract` | `not_yet` (before: also continue/stay).
- `run_end` adds `stage_id`, `stage_name`, `stage_index`, `stage_length`, `stage_count`, `outcome`, `boss_killed`,
  `stage_clock`, `endless_s`, `run_time`.
- Boards: new "88fits · Stages" (https://eu.posthog.com/project/290195/dashboard/1031751); "Runs a day, by stage" on
  Pulse; stage_id and outcome on Players' "Recent runs"; "Deaths by stage, in Endless or before" on Deaths. HogQL
  `STAGE` = the event's stage_id, else "s" + its stage.

#### The dashboard (analytics/dashboard.html)
- A Stage filter (`#stagefilter`, remembered as `runwatch.stage`): every list (history, opened runs, remote runs) by
  stage_id (an older run by the stage it ended in); the summary's Stage tile, the facts' Stage and How it ended, the
  history's stage name / outcome / endless columns.

## Pass 110: a stage's boss-fight window (lane BOSS)

Garry (2026-10-28): "Just add a 2 minute window in the Timeline where I can set up the cycle of enemies that will be
spawning ... as long as the Boss Fight is continuing it will be those enemies at that pace that will be spawning."

#### timeline_data.stage_list[k].boss_fight (Object, optional)
| key | type [default] | meaning |
|---|---|---|
| `enabled` | bool [true] | false keeps the block but the fight plays as before |
| `length` | seconds [120] | one cycle; at least 1 (`WaveTimeline.BOSS_FIGHT_LENGTH_DEFAULT`) |
| `max_count` | int [40] | the most creatures alive (**bodies**, whatever their cap share) while the window spawns: the boss, its summons and what is left of the stage's crowd count; -1 = no limit but `hard_cap` (`BOSS_FIGHT_MAX_COUNT_DEFAULT`) |
| `roster` | Array [[]] | spawn rows with the roster's keys (Pass 53, 54, 57, 58, 81, 83, 84), every time on the **fight clock** (0 = the boss arrives): `t`, `until` (absent = the cycle's end), the `weights` keyframes, `offset` |

Rows read every roster key as on `timeline_data.roster`, with these differences: `channel` is ignored (one limit:
`max_count`); `chance` and `t_jitter` are rolled per cycle; "roster" as the creature draws from the window's own open mix
rows (one creature, no elite, not special, not once) by their Elite weight; `id` is the editor's label ("bf<stage>-<n>").

#### The rule (game/core/systems/BossFightWindow.gd; WaveDirector `boss_window`, `boss_window_on()`)
- From the boss's arrival (`WaveDirector._start_boss` -> `BossFightWindow.begin(director, Run.stage)`) until it dies
  (`_on_boss_died` -> `stop()`), a stage with an enabled block spawns **only** its rows: the stage's rows, the own-interval
  rows, the density floor and the specials' clock stand still. A stage without one keeps today's fight (`boss_cap_frac`
  of the cap, the stage's last rows drawn).
- The fight clock is real seconds since the boss arrived (a paused game holds it); the cycle loops every `length`: every
  row's state starts afresh (a once row comes again, a waves row's schedule restarts from t + offset, what a wave still
  owed is dropped).
- Continuous rows (and waves rows with `trickle`) draw at the director's spawn check (`spawn_interval`) or on their own
  `interval` clock: a burst of burst_min..burst_max **creatures** x their share of the open drawn rows' weight (Pass 83),
  cut to the room under `max_count` and the hard cap, by the presence weight at the fight clock.
- Waves / once rows: `count` a wave, cut to the room under `max_count` with `respect_cap` (default; at least one while any
  room), the rest owed until the row's next wave or its end (each spawn check first); `respect_cap` false = on top of
  `max_count`; the hard cap holds unless `respect_hard_cap` is false. An elite row without a `pattern` brings coloured-elite
  arrivals (`WaveDirector._spawn_elite`), on top of every limit as on the roster. `max_alive` (the row's or the
  creature's) holds, counting every living one of that creature (the stage's leftovers too).
- Numbers (Pass 58's R1): each row's creatures are fixed at its first spawn of the run from `stage_end(k)` on the run clock
  (`WaveDirector.source_for("boss<k>:<id>#<i>", stage_end, stats)`: the HP and ATK curves there, the hero's level then),
  times the stage multiplier at the spawn and the row's overrides.
- `WaveDirector.current_cap()` in such a fight returns `max_count` (the hard cap for -1), in bodies.
- A boss's own `spawn_ring` summons keep their rules but are cut to the hard cap's room
  (`WaveDirector.summon_room(want)`, asked through `EnemyManager.summon_count`), with or without a window.
- Headless runs log each window spawn as `spawn84 bossfight <id> <n> <clock>`.

#### Code API
- WaveTimeline: `boss_fight(i)` ({} when none or off), `has_boss_fight(i)`, `boss_fight_length(i)`,
  `boss_fight_max_count(i)`, `boss_fight_rows(i)`, static `boss_fight_open(rows, ct)`; consts
  `BOSS_FIGHT_LENGTH_DEFAULT` 120, `BOSS_FIGHT_MAX_COUNT_DEFAULT` 40.
- BossFightWindow (RefCounted): `begin(director, stage) -> bool`, `stop()`, `tick(delta)`, `spawn_check()`,
  `cap_value()`, `room()`, `hard_room()`, `cycle_time()`, `key_of(row, k)`, `row_state(k)`; fields `active`, `stage`,
  `length`, `max_count`, `rows`, `clock`, `cycle`, `cycles`, `came_by` {key: creatures}, `came_total`.
- WaveDirector: `boss_window`, `boss_window_on()`, `summon_room(want)`. EnemyManager: `summon_count(want)`.
- The Level Editor's side (Boss fights section, the row form, the checks, model.js helpers): docs/level_editor.md
  "Pass 110". Tests: game/tests/pass110_boss_window_test.gd, tools/level_editor/selftest_BOSS110.py. Probe:
  game/tools/_p110_BOSS_fight_probe.gd (`stage= build= level= hero= secs= before= seed= window=0|1`).

## Pass 111: far creatures walk faster (lane ENEMY)

Garry (2026-10-28): "Regular Enemies should walk considerably faster when they are far enough from the Player. This is an
option that I can control and switch off if I don't like it. This should also apply to Bosses, but not to Elites or
Special Enemies."

#### timeline_data.far_speed (Object, optional)
| key | type [default] | meaning |
|---|---|---|
| `enabled` | bool [true] | false = off: every creature walks at its own speed wherever it is |
| `distance` | metres [14] | how far from the hero (flat) the speed-up starts; inside it nothing changes |
| `ramp` | metres [6] | over how many metres past `distance` the multiplier grows (a smoothstep) to `max_mult`; 0 = all at once |
| `max_mult` | number [2.0] | the walk's multiplier at `distance` + `ramp` and beyond (1 = no speed-up) |
| `bosses` | bool [true] | a boss far from the hero walks faster by the same rule |

A key left out (the whole block too) plays `WaveTimeline.FAR_SPEED_DEFAULTS`. Red Canyon's file names the defaults:
`"far_speed": {"enabled": true, "distance": 14.0, "max_mult": 2.0, "ramp": 6.0, "bosses": true}`: x1 up to 14 m, x1.5 at
17 m, x2 from 20 m (the screen shows about 12 m to the sides and 20 m up and down; the roster's rings come at 18 m).

#### The rule (EnemyManager `far speed` section)
- Only the walk a creature's brain chooses (`_steer`'s `spd`: chase, flock, kite, the kamikaze's run, a boss walking
  between attacks, ...) is multiplied, on top of every other speed (creature_speed_mult, the stage, Endless, slows).
  A charge, a boss's scripted roll or jump, a flee on hit, a push, a pull or a throw keep their own speed.
- Never an Elite (by its kind, or one wearing an Elite modifier), a special type (the gear badge: the Vulture Raider,
  the harpooner, the Saiga Sniper), a coloured variance special or a training dummy. Bosses only while `bosses`.
- The arena plays it too (it is where the walks are looked at, as `creature_speed_mult`). The despawn rule is unchanged.
- Cheap: one distance compare per steer for everything inside `distance`; the type's kind is read from a per-type table.

#### Code API
- WaveTimeline: `far_speed` (Dictionary), `FAR_SPEED_DEFAULTS`, `far_speed_cfg()`. JsonContent reads the block as it is.
- WaveDirector `_apply_mults` -> `EnemyManager.set_far_speed(cfg)`.
- EnemyManager: `far_speed_on`, `set_far_speed(cfg)`, static `far_kind_of(def)` (FAR_NEVER / FAR_REGULAR / FAR_BOSS),
  static `far_speed_mult(dist, distance, ramp, max_mult)`, `far_speed_k(i, dist)`.
- Level Editor: Settings, Scaling card, rows `far_speed.enabled` ("Far creatures walk faster"), `far_speed.distance`,
  `far_speed.ramp`, `far_speed.max_mult` ("Far speed ×"), `far_speed.bosses` ("Bosses too"), with a line that reads the
  multiplier at three distances; model.js `FAR_SPEED_DEFAULTS`, `farSpeedCfg`, `farSpeedMult`, `farSpeedIssues`.
- The run sim (tools/sim_batch.py) plays the game's own code, so its runs follow the block too.
- Tests: game/tests/pass111_enemy_test.gd; tools/level_editor/selftest_ENEMY111.py.

## Pass 111: map chests (lane CHEST), reverted in pass 112

Pass 111's `world_chests` (chests laid off the screen on a clock, a CHEST edge tag) and `chest_contents` (a power-up out
of an opened chest, the reel's knobs per chest type) were taken out again in pass 112: Garry meant barrels ("when I was
talking about chest appearing and stuff I actually meant barrels. Not chests ... revert the chests to be as they were").
Chests play as in pass 110; the map names neither key. The same asks, applied to barrels: "Pass 112: barrels" below.

## Pass 112: barrels come back and throw power-ups (lane BARREL)

Garry (2026-10-28): "Chests - when I was talking about chest appearing and stuff I actually meant barrels. Not chests.
So apply whatever I said in that prompt to barrels" (pass 111's words: "should respawn every now and then. They should
also have a chance of a power up dropping from them. The power ups don't immediately get claimed and used by the hero.
They jump far enough out for it to be a conscious decision for the Player. I should be able to set the frequency and
content probabilities of both [barrel] types on LevelEditor. [They] never spawn where Player can see them").

#### timeline_data.barrels (Object, optional; no block = today's barrels)
`{"respawn": {...}, "brown": {...}, "black": {...}}`. The start's placement is unchanged (BarrelField: 35 barrels by the
map's seed, 22% black plus two that are always black).

`respawn`:
| key | type [default] | meaning |
|---|---|---|
| `enabled` | bool [false] | true lays barrels again; left out or false: none come back |
| `first` | seconds [45] | of the respawn clock before the first is due |
| `every` | seconds or [min, max] [[40, 60]] | from one to the next, rolled each time; under 5 counts as 5 |
| `max_lying` | int [35] | barrels standing at most, the start's included (35 = only smashed ones come back); a turn that finds that many standing is skipped (the next waits its full `every`); 0 = no limit |
| `max_per_stage` | int [0] | respawns a stage at most; 0 = no limit |
| `min_dist`, `max_dist` | metres [20, 40] | how far from the hero (flat); when every spot of that band is on the screen the band past it to 1.5 x `max_dist` is tried |
| `black_chance` | 0..1 [0.22] | the chance one that comes back is black (the start's own share, BarrelField.LIGHT_FRAC) |
| `view_margin` | metres [2] | how far past the camera's view the barrel and its shadow must keep when it appears |
| `in_boss`, `in_portal`, `in_endless` | bool [true, false, false] | whether the clock runs (and barrels come back) in the boss fight, the portal's countdown, Endless |

`brown` / `black` (what each kind holds):
| key | type [default brown / black] | meaning |
|---|---|---|
| `powerup_chance` | 0..1 [0 / 0] | the chance smashing it throws a power-up out, on top of its gems and coins |
| `powerups` | [{id, weight}] or {id: weight} [[]] | which one, by weight; empty = the map's `pickups.roster` (the drops' mix) |
| `throw_distance` | metres or [min, max] [[5, 7]] | how far from the barrel it lands |
| `gems_small` | int [8 / 10] | small XP gems it bursts into (each 1 + 0.15 x the hero's card level) |
| `gems_medium` | int [0 / 4] | medium XP gems (each 4 small) |
| `coins` | int or [min, max] [0 / [1, 5]] | its coins, rolled per barrel (BarrelField.COIN_MIN..COIN_MAX for black) |

Red Canyon: respawn on, first 45, every [40, 60], max_lying 35, 20-40 m, black 22%, margin 2, in the boss fight only;
brown power-up 8%, black 30%, both with the drops' mix written out (heart 6, rage 3, sprint 3, shield 2, magnet_pulse 2,
nuke 2), throw [5, 7]; gems and coins as before (8; 10 + 4 and 1-5 coins).

#### The rules (game/core/systems/BarrelSpawns.gd; BarrelField's spawn_* host methods, respawn_at, _throw_powerup)
- The respawn clock (`BarrelSpawns.clock`) counts the seconds of the phases it runs in, from the run's start (each stage
  is its own run). A due turn: past `max_per_stage` none come any more; with `max_lying` standing the turn is skipped;
  else a spot is searched (48 tries in the band, 48 in the far band) and a barrel laid there; no spot: tried again 3 s
  later. Only while the director runs a stage, never in the debug arena (`Run.arena`).
- A spot is never seen: the barrel with its shadow (`SEEN_SPHERES`: 0.75 m round its middle) lies outside the camera's
  frustum by `view_margin`. It keeps the start's rules (BarrelField.spawn_ok: inside 0.92 of the arena's radius, off the
  flats' middle, out of the water, off the rocks, out of every painting's cover band and structure ring) and MIN_GAP
  (6.5 m) from every barrel standing.
- The kind is rolled (`black_chance`); it takes a smashed barrel's slot of that kind (its instance and its shadow stand
  up there), else one of its kind's BarrelField.SPARE (24) spare instances, else a smashed slot of the other kind.
- A respawned barrel's coins are rolled from its kind's `coins` on the barrels' own dice and are extra gold: only the
  start's barrels are held back from the creatures' first coins (pass 87's coin debt).
- Smashing a barrel (BarrelField._break) bursts its kind's gems and coins, then rolls its kind's `powerup_chance` on the
  barrels' own dice (seeded from the run's seed in the sim); the power-up is drawn by weight and thrown
  (`PickupManager.throw_powerup`, `Powerup.throw_to`): a hop 0.55 s + 0.035 s a metre long, 1.8 m + 0.22 m a metre high
  (6 m: 0.76 s, 3.1 m up), landing `throw_distance` m from the barrel on a clear spot (in the arena, off the rocks' feet
  and the water, out of the cover bands, 1.2 m from any power-up) chosen in this order: within 80 degrees of straight
  away from the hero AND wholly on the screen below the HUD's strip; any way on the screen; any way. In the air it is
  never taken and its lifetime stands still; it is never pulled by a magnet (`no_magnet`: a coin bag's own pull too);
  the vacuums never touched power-ups. It then lies its own `lifetime` (content/pickups/<id>).
- No edge tag points at barrels (35 standing on the map: a tag would always be up).

#### Code API
- BarrelSpawns (RefCounted, reads no autoload): consts `RESPAWN_DEFAULTS`, `CONTENT_DEFAULTS`, `TYPES`, `EVERY_MIN` 5,
  `RETRY_S` 3, `TRIES` 48, `FAR_BAND` 1.5, `SEEN_SPHERES`, `PHASE_*`; static `respawn_of(block)`, `contents_of(block,
  black)` (coins as Vector2i, throw_distance as Vector2), `weight_list(v)`, `pick_weighted(list, rng)`, `range_of(v,
  fallback)`, `roll(range, rng)`, `phase_allowed(cfg, phase)`, `seen(planes, p, margin)`, `turns_in(cfg, length)`;
  instance `setup(block, seed)`, `tick(host, delta, phase)`, `spawn_now(host) -> bool`, `find_spot(host)`; fields `cfg`,
  `on`, `clock`, `next_at`, `spawned`, `skipped`, `missed`, `rng`.
- BarrelField: `SPARE`, `spawns`, `respawned`, `powerups_thrown`, `contents(black)`, `respawn_clock()`, `spawn_hero()`,
  `spawn_planes()`, `spawn_ctx()`, `spawn_ok(p, ctx)`, `respawn_at(at, black) -> bool`, `_slot_for(kind)`,
  `_throw_powerup(contents, at, pickups)`.
- PickupManager: `throw_powerup(def, at, dist, rng) -> Powerup`, `powerup_throw_spot(at, dist, rng)`, `view_camera()`,
  `thrown_powerups`, `THROW_TRIES`, `THROW_CLEAR`; `spawn_special(...) -> Powerup`. Powerup: `flying`, `no_magnet`,
  `throw_to(from, to)`, `throw_point(f)`.
- The Level Editor's side: docs/level_editor.md "Pass 112". Tests: game/tests/pass112_barrel_test.gd,
  tools/level_editor/selftest_BARREL112.py. Capture: game/tools/_p112_BARREL_shots.gd; probe (a real run, the hero
  smashing a barrel every few seconds): game/tools/_p112_BARREL_probe.gd.

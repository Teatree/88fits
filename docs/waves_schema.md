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

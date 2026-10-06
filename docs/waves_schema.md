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
  point), `"single"` (one creature per draw, whatever the pack).
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
  is several packs.
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
round the hero, ignores the cap), `"pack"` or `"scatter"` (through the spawn points, ignores the cap).

## Stat overrides (`stats`, **new**)
Every key optional; a missing key keeps the creature's own number. Multipliers (`*_mult`) stack on the base.
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
  `EnemyManager.spawn(def_id, at, elite, scale_mult, hp_mult, variant, overrides)`; `alive_of(id)` and `max_alive`
  count every type of that id.

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
  the run clock. `points` is linear between the points, flat outside; `formula` with `m` = minutes: linear `1 + a*m`, power
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
  facing rule (with the block's `facing_share` / `facing_spread_deg` when it names them) whatever the mode.

### Creature JSON
- `knockback` (top level, m/s): the shove the hero takes from this creature's bite. Absent (or 0) = `EnemyDef.default_knockback
  (damage)` = `clamp(3.4 * sqrt(damage / 4), 2.5, 7.0)` (about 35 % over the old fixed 2.5 for a 4-damage creature);
  `EnemyDef.hit_knockback()` is the number in force. Every creature and boss JSON carries one since pass 54
  (`tools/set_knockback.py` wrote the rule's value, 2 decimals, right after `damage`; the training dummies have none). A
  hostile shot shoves by `ranged.knockback` when it has one, else `knockback * 0.7`; `charge.knockback`,
  `kamikaze.knockback`, `artillery.missile.knockback` and boss attacks keep their own numbers. Overridable per row
  (`stats.knockback`), and `stats.knockback_mult` multiplies it too (a multiplier of 0 leaves no shove).

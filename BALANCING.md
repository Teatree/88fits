# Balancing 88fits

Every balance number is in a JSON file under `game/content/`, one folder per thing.

**After editing a JSON:** press **JSON → .tres** in the Godot editor's Content dock (or run
`"$GODOT" --headless --path game --script res://tools/import_json.gd`). The game reads the generated `.tres` before the
JSON, so a JSON edit shows only after this step. `bash tools/ship.sh` does it automatically before building.

**To try a change at once:** Debug · Arena on the title screen (debug mode on): spawn any creature, give yourself any
item at any level, call any wave. `analytics/dashboard.html` charts a played run's damage against the crowd.

## 1. Enemies
`game/content/enemies/<id>/<id>.json` (bosses in `content/bosses/`, coloured Elite modifiers in `content/elites/`)

| field | what it does |
|---|---|
| `hp`, `speed`, `damage` | health, move speed, damage of a touch |
| `size`, `radius` | how tall it stands in metres (the hero is 1.9; the skeletons 1.75 and the knight 1.85 since pass 49) and how wide its body is (hits, crowding) |
| `damage_reduction` | share taken off every hit (0.25 = 25%) |
| `knockback` (pass 54) | metres a second the hero is shoved when this creature bites him (a row may set `stats.knockback` or `knockback_mult`). Without one: `clamp(3.4 x sqrt(damage / 4), 2.5, 7)`, about 35 % over the old flat 2.5 for a 4-damage creature (`EnemyDef.default_knockback`); every creature and boss JSON carries its number now (`tools/set_knockback.py`): skeleton 2.94, knight 3.4, fire ant 4.81, mummy 6.36, beetle 6.8, bosses 7. Bosses and Elites shove x1.6. A shot without its own `ranged.knockback` shoves 0.7 of its shooter's number; the dwarf's shotgun and the rocketeer's rocket keep theirs |
| `xp_mult`, `drops` | XP worth; gem sizes, `gold`, `chest` chance, a `pickup` |
| `pack_size`, `max_alive`, `cap_share` | how many come together, the most alive at once, how much of the live cap one takes |
| `variance` | size/speed jitter, tints, `special_chance` and `special` (the dark "coloured" ones) |
| `charge`, `ranged`, `artillery`, `caster`, `boss.attacks` | the brain's numbers: every attack's damage, wind-up, cooldown |
| `shadow` | the blob shadow under a low, wide creature (pass 47): `scale` [width, depth] times the plain one, `up` metres up the screen to slide it under the body, `drop` the share of the cell the painting sinks so its legs stand on the sand. Try numbers in the arena by eye. The Dune Scorpion `[1.45, 1.7]`, 0.55, 0.065; the Bull Beetle `[1.45, 1.7]`, 0.35, 0.07 (pass 50) |

**A charger's look and push** (pass 50, the Bull Beetle's `charge` block; a charger without these keys charges as before,
as the Dune Scorpion does):

| key | what it does | beetle |
|---|---|---|
| `shake` | metres it shakes from side to side at the end of its wind-up (it builds up from a quarter of that); it also rocks on its feet | 0.09 |
| `crouch` | how far it squats while winding up (a share of its height); it launches stretched by 1.6 times that and digs in squashed by it at the end | 0.12 |
| `legs` | how fast its legs run while charging, times its walk; through the wind-up they scrabble in place, speeding up to it | 2.5 |
| `lean` | degrees it leans into the run (the full angle when it charges straight across the screen, none up or down it) | 7 |
| `dust` | the dust: pawed back in the wind-up, a burst at the launch, a trail behind the run, a skid at the end (1 = full, 0 = none) | 1.0 |
| `shove` | metres a second it shoves each creature in its way out to the side while charging (about 0.17 m aside per 1, once per pass; never a boss, an Elite or anything bigger than it) | 2.8 |
| `shove_walk` | the same while it walks, for what is in front of it | 1.0 |

## 2. Items
| where | what |
|---|---|
| `content/weapons/<id>` | `base` (damage, cooldown, amount, range, pierce, area, knockback, speed, element stats) and `levels`: five levels (pick-up + 4 upgrades, pass 48), one list of effects per level, e.g. `{"stat": "damage", "op": "mul", "value": 0.2}` = +20%; a level may change several stats at once. `targeting`: `"priority"` aims at the strongest close creature (single-target weapons), `"nearest"`, `"densest"` ... |
| `content/evolutions`, `content/mutations` | evolved weapons; mutations' `effects` and `params` |
| `params.ignite_chance` (pass 51) | the share of the creatures a fire weapon's shot hits that catch fire, rolled once a creature a shot (1 = every one, the default). Dragon's Breath 0.6; the Blunderbuss sets 1.0 back in its `params.final` (merged after the mutations it keeps), so the evolution's fire is sure. A fire that jumps from a burning creature keeps its own odds (`fire_spread`) |
| `params.double_every`, `double_gap` (pass 51) | Both Barrels: every Nth shot fires a second shot `double_gap` seconds after the first (0.15, aimed afresh, its own flash and bang); the Blunderbuss doubles every 2nd |
| `params.fire_blind` (pass 53) | a "forward" gun (the Boomstick) fires only with a creature inside its range; `fire_blind: true` (the Blunderbuss's `final`) keeps firing on its clock with nobody near |
| `params.blast_fx {scale, flash}` (pass 53) | Heavy Warhead: a rocket's blast drawn `scale` times bigger with a white flash and hotter sparks (`Fx.burst_strength`); `size_mult` 1.35 draws the rocket bigger and its hit radius follows (0.3 x size) |
| `params.cluster {chance, count, damage_frac, radius, life, spread, max, trigger, chain}` (pass 53) | Cluster Munitions: with `chance` a blast scatters `count` bomblets within `spread` m that lie `life` s; a creature within `trigger` m pops one for `damage_frac` of the rocket's damage in `radius` m; at most `max` live per weapon (the oldest goes); `chain` true pops every bomblet within 1.2 m (the Hellfire Battery) |
| `params.pressure {max, seconds, start, hit_keeps}` (pass 53) | Pressure Cooker: the pod's fire interval is divided by 1 + start + (max - start) x ramp, ramp = seconds since the hero was last hit / `seconds` (0..1); a hit (HP or shield) sets the ramp to `hit_keeps` of itself (0 = all gone); the pod's materials warm to orange with the ramp. `overpressure {every}` (the battery's `final`): at full ramp every Nth volley fires twice |
| `params.turret.boom {radius, damage_mult, knockback}` (pass 53) | Last Stand: a turret going (time up, or the cap replacing the oldest) blasts `damage_mult` x its shot damage in `radius` m. `params.focus {mult, seconds}` (Iron Bastion's `final`): a creature hit by a bastion round takes +`mult` from every hit for `seconds` (EnemyManager's mark) |
| `params.thrust.amount_mode` (pass 53) | `"blades"`: in slice mode every blade of `amount` sweeps together in one stroke, fanned `fan_deg` apart (the Spear's Wide Sweep: more spears, not more thrusts); absent (the Sabre): `amount` = swings a stroke, alternating |
| `params.thrust.stun {chance, seconds}` (pass 53) | Stunning Thrust: every hit rolls `chance` to stun for `seconds` (`EnemyManager.stun`: no walking, no attacks, a pale yellow tint; never a boss or an Elite); the Thunder Lance's is 1.0 / 0.8 |
| `params.thrust.alternate`, `alternate_knock` (pass 53) | the Thunder Lance: strokes alternate a sweep and a thrust whose knockback is x`alternate_knock` (1.5); `params.stunned_mult` (its `final`) multiplies its damage on a stunned creature; `thrust.crackle` draws one lightning crackle from the tip on a sweep that hits |
| `params.thrust.windback`, `hitstop`, `flex` (pass 53) | the thrust's bite: pulled back 20 % of the reach over `windback` (0.05 s), out eased, `hitstop` (0.04 s) at full reach when it bit, the shaft overshooting to `flex` (1.06); a streak behind the tip and sparks on a hit. Numbers in the JSON win over these defaults |
| `params.crit_refund` (pass 53) | the Whirlwind: a swing that crits gives back this share of the cooldown (0.2) once a swing; `thrust.slice_deg` 360 = a full circle a swing; `params.trail_color` the crescent's colour when the weapon has no element |
| `params.out_speed_mult`, `back_speed_mult`, `return_damage_mult`, `second_pass` (pass 53) | Thorny Weed rolls out at 0.7 of its speed over the same ground (its life stretched) and comes back at 1.4; the Dust Devil 0.8 / 1.5, x2 damage on the way back and one more out-and-back before it is freed (25 degrees to one side) |
| `params.aura {radius, slow, seconds, every, tint, pull}` (pass 53) | Dust Wake: every `every` s the weed slows what stands within `radius` by `slow` for `seconds` and tints it (dark green, Curare's colour for slowed); the Dust Devil's `pull` drags them toward the weed at that speed. The weed draws a spinning dust ring of that radius |
| `WeaponBehavior.GLOW` 0.45, `params.glow` (pass 53) | every dim material of a companion or held model (no emission of its own) emits its albedo at this energy so the 3D things round the hero read on the sand (Garry: "they are quite dim"); `glow: 0` on a weapon turns it off, a number sets its own |
| mutation effects with `"target": "player"` | land on the hero's sheet for every weapon (Critical Thinking: `crit_chance add 0.10`) |
| `params.echo_zap {chance, count, damage_frac, gap}` (pass 53) | Echo Zap (the Zap Beam's; "Aftershock" is the Hammer's name already): every arc hit has `chance` to be followed by `count` zaps `gap` s apart on the same creature for `damage_frac` of the hit, with a visible discharge; the Storm Cloud's `final` lifts the chance to 0.35 |
| `params.sun {warn, radius, flash, beam_alpha, ring_alpha, glint, hold_when_empty, weight_power, tint, thin}` (pass 54) | the Sun Scepter (`core/behaviors/SunScepter.gd`, Solenne's own): every `cooldown` it calls `amount` pillars of sunlight on creatures on the screen, picked at random with weight 1 / max(distance, 1.5)^`weight_power` (closer = likelier, never the same one twice a strike); with nothing on the screen it holds (no strike, no cooldown). Each pillar warns `warn` s (the loose rocket's red ring, much fainter: `ring_color`, `ring_alpha` 0.35 against the rocket's 0.9; and a soft beam, `beam_alpha` 0.55, aimed where the creature will be, led at most 2.5 m), then hits everything within `radius` x area; no camera shake. Base 14 damage, 1.1 s, 1.3 m; level 3 two pillars, level 5 three |
| `params.zenith {every, frac, radius, max_pillars}` (pass 54) | Zenith (the Sun Scepter's evolution, in its `final`): every `every`th strike (10) puts a pillar on every creature on the screen (at most 40) for `frac` (80 %) of the damage; the ring round the sun head fills with the count |
| `params.gold_dust {chance, coins}` (pass 54) | Gold Dust: a creature the weapon kills drops `coins` coin with `chance` (30 %), paid in `Game._kill_effects` so a kill by its burn counts too |
| `params.tint {albedo, emission, energy}` (pass 54) | a mutation that recolours its weapon's shot (`ProjectileEmitter.tint_kind`: a lazily registered copy of the kind with its own material): Thorny Weed's darker thorny brown. The base tumbleweed is now `art/props/tumbleweed_dark.glb` (74, 46, 24) with a faint glow, and the Dust Devil stays black with a warm rim, so all three read on the sand |
| `params.shine {idle, flare, sweep, pop, charge}`, `params.staff_tint`, `params.handle_ring` (pass 55) | how the Sun Scepter looks, no numbers that hit: the sunburst at the sun at rest (`idle`: 0 on the sceptre, 0.4 on Zenith plus `charge` x its count) and at a strike (`flare` 1.1, Zenith 1.7; the sweep `sweep` 2.6, swelling by `pop`); every strike also shakes the whole sceptre for 0.25 s (`SunScepter.SHAKE_*`). Heat Stroke's `staff_tint` turns the handle a little orange, Flicker's `handle_ring` loads a ring round the handle; `params.marks` false keeps the floating mutation emblems off the family |
| `params.roll_radius` (pass 55) | a shot that rolls like a wheel the way it flies, v / (roll_radius x size) radians a second (the tumbleweed 0.6, the Dust Devil 0.75) |
| player stats `buff_duration`, `heal_mult` (pass 54) | `buff_duration` stretches every timed buff on the hero (power-ups, structures, Pollen, Barrel Rush, the shield; `Run.buff_seconds`); `heal_mult` multiplies every heal and her regen (`Player.heal`, `_tick_regen`). Solenne's trait Magic Hour: buffs and debuffs x1.25, cooldown x0.87 (+15 % attack speed), max HP x0.8; her perks Afterglow (heals x1.4) and Sunburn (a burning or poisoned creature takes +20 % from her); Lingering Light (burns and poison +30 % harder and longer) and Long Day (buffs x2) are in the content, hidden |
| the mutation offer's weapon (pass 54) | drawn at random among the weapons with a path still open this stage (`Run.next_path_weapon`), shown by a pre-reel of those weapons' plates (`ui/wanted/WWeaponReel.gd`); it was the highest-levelled one |
| `params.lay_ahead` (pass 51) | a mine weapon's drops are flicked that many metres ahead of the hero while he walks (at his feet while he stands). Jackrabbit Mines 2.0; the Land Mine has none |
| `mutations/wide_reach` `params.spring.sense` | how far a mine springs at a creature: 2.8 m since pass 51 (was 3.5). The Jackrabbit's own `jackrabbit.sense` is 6 |
| `content/passives/<id>` | lines and passive items: `levels`, `max_level`, `line`, `evolves_into`; `rarity` and `weight` for the offers |
| `content/characters`, `content/perks` | heroes (trait, start weapon, favourite), their perks |
| `StatSheet.PLAYER_DEFAULTS` (code) | what every hero starts with before his trait: 1% crit chance since pass 52 (crits do x2), one reroll a run, 2 skips and 1 banish a stage. Calavera's trait adds +5% crit, Deadeye +8% a level |
| `content/talents` | the Upgrade board: cost per rank, effects |

A weapon evolves at a chest once it is at level 5 and holds **all three** of its mutations (pass 48).

**Chances inside mutations** are `chance` in the mutation's `params`: Thor's Wrath (`params.thor.chance`) and Giant Slayer
(`params.giant_slayer.chance`) are 0.5 since pass 49, half of all hammer impacts.

**Hot Streak (pass 49):** `content/passives/hot_streak`, stat `kill_might` = attack damage per 1,000 kills made while it is held,
0.05 a level (+5% per 1,000 kills at level 1, +25% at level 5, so the +100% cap comes at 20,000 kills at level 1 and 4,000 at
level 5; a full stage 1 is about 2,800 kills). Nothing takes it away. The cap is `STREAK_CAP` (1.0 = +100%) and the 1,000 is
`STREAK_PER`, both in `game/core/autoload/Run.gd`.

**Hidden things come back (pass 48):** a mutation or an evolution with `"hidden": true` is kept in its folder but never offered.
To bring a mutation back, delete that line (and hide the new one that took its slot, or the weapon has four). To bring an old
evolution back, delete its `hidden` line and set the weapon's `evolves_into` to its id. The old Golden Revolver and Earthshaker are
kept as `golden_revolver_v47` and `earthshaker_v47`.

Offer odds: weight × rarity × luck boost × 1.5 if held × 0.88 per level past the first × 3 for a line's evolution
(constants in `game/core/systems/CardPool.gd`, explained in the design bible, section 10 "The odds").

### What a level-up offers (the rules, pass 52)

A level-up shows **three cards**, always (luck no longer adds a fourth: it only makes the rarer items likelier). The cards
are drawn one at a time from everything that may be offered, in proportion to its weight (`core/systems/CardPool.gd`):

| rule | where |
|---|---|
| **Weapons**: a new one only while a weapon slot is free (5, `Run.MAX_WEAPONS`), and at most one new weapon a level-up; a level of one you hold until its 5th. Evolved weapons never level from cards | `CardPool.level_up_offer` |
| **Lines**: a new one only while a line slot is free (5, `Run.MAX_LINES`); a level of one you hold until its 4th; a maxed line offers its **evolution** instead (weighted x3), which takes its slot | the same |
| **Passive items**: always, no slots and no cap; new, or a level of one you hold until its top | the same |
| **Perks** (the hero's own): at most one a level-up, at most once in five level-ups (`Run.perk_gap`), each once a run, weighted x4 | the same |
| **Mutations never come in a level-up.** They have their own table at the map's `path_times` (stage 1: seven slots from 1:19, later stages eight from 0:50): the weapon with the highest level that still has a mutation open this stage gets its whole path (its open element, volume and motion mutations, then the hero's own option) on one table. One mutation per weapon per stage, from its first level (`Run.MUTATION_FROM_LEVEL` 1). Boss chests always roll a mutation, and the Stranger sells one | `Run.path_due`, `next_path_weapon`, `CardPool.path_offer` |
| **Evolution** comes from a chest, once a weapon is at its 5th level and holds all three of its path mutations (a hero's own is optional) | `Run.evolution_ready` |
| Not offered: anything banished this run, anything locked behind an unlock quest (unless you already hold it), hidden items, another hero's own weapons (the Gravity Gun is Astro's, the Revolver the Drifter's, the Guitarra Calavera's), stage-3 items before stage 3 (Brimstone Brand, Sinner's Greed: `from_stage`) | `Registry.unlocked_*`, `stage_open` |
| **Weights**: an item's `weight` x its rarity (common 1, uncommon 0.75, rare 0.55, epic 0.3, legendary 0.15) x (1 + luck x the tier's lift: uncommon 0.5, rare 1, epic 1.5, legendary 2) x 1.5 if you hold it x 0.88 for every level past the first | `CardPool.weight_of` |
| **Choices**: 2 skips and 1 banish a stage, shared with the mutation tables and chests; 1 reroll a run (the Mirror adds more). A skip pays nothing; a banish swaps that one card and keeps the item out for the run | `Run.refill_choices` |
| The hero's **favourite** says FAVOURITE on its card and comes at a bonus level (Calavera's Skull Rain, Ironwood's Brawn at level 2) | `Run.first_passive_level`, `CardPool.apply_favourite` |
| Nothing left to offer: +10 gold instead | `Game._show_next_level_cards` |

## 3. Waves and pacing
`game/content/maps/red_canyon/red_canyon.json`, the `timeline_data` block:

| field | what it does |
|---|---|
| `stage_length` | seconds a stage (430) |
| `cap_curve` | how many creatures may be alive at each second: `[[0, 10], [60, 16], ...]` |
| `roster` | who joins and when: `{"t": 0, "enemy": "skeleton", "weight": 10, "weight_late": 3}` |
| `events` | swarms, Elites (215 / 645 / 1075 s), bosses at stage ends |
| `specials`, `elite_every`, `colour_after_kills` | rocketeer/harpooner timing, Elite cadence, when coloured ones start |
| `burst_min`, `burst_max`, `spawn_interval` | how they arrive |
| `creature_hp_mult`, `stage_mults`, `hp_growth`, `hp_power` | everyone's HP: overall, per stage, over a stage |
| `level_hp_per_level`, `level_damage_per_level` | creatures grow with the hero's level |
| `contact_cap` | the most one touch takes, as a share of max HP |
| `xp_need_mult` | levelling speed: the XP each level asks, times the curve 15 + 6L + 0.5L² (2.1 since pass 52, 5% over 2.0) |
| `path_times` | when mutation offers come |
| `move_pace` | **everyone's speed** (0.6, set by hand before pass 52; 0.8 in pass 48, 1.0 = pass 47's speed). The hero, every creature, charges and rolls move at it; to keep dodging fair, hostile shots, boulders and rumbles fly at it too and every red warning lasts 1 / it as long (a 1 s ring warns 1.25 s at 0.8, 1.67 s at 0.6). Attack cooldowns and spawns do not change. One number for the whole game. |
| `portal_wave` | `{"count": 12}`: one small wave when the boss dies, then nothing spawns until you walk through the portal |
| `weapon_cap`, `passive_cap` | slots (5 / 5 since pass 52; 6 / 6 in pass 47) |

## 3b. Waves, overrides and the Level Editor (pass 53)
The whole schema is `docs/waves_schema.md`. Three layers feed the crowd, all in the map's `timeline_data`:

| layer | what it is | where to tune |
|---|---|---|
| the **cap curve** | how many may be alive at each second; the roster and cap-respecting waves spawn only into free room (load units: a creature counts its `cap_share`) | `cap_curve`, `hard_cap`, `boss_cap_frac` |
| the **roster** | rows drawn by weight while the row is open (`t` to `until`); a row may set `pack`, `pattern` (pack / scatter / single), an art `variant` and `stats` overrides | `roster[]` |
| **waves** | explicit windows on top: from `t`, `burst` creatures every `every` seconds until `count` or `until`; one of its `alts` (weighted) is rolled afresh every run; `respect_cap` false spawns on top of the cap like a SWARM; `elite` wears a modifier on all of them | `waves[]` |
| **events** | swarms, Elites (`elite_every` with an `interval` of `[min, max]`), the Elite creature, bosses; an `enemy` may be a weighted list; `chance` and `t_jitter` roll per run; `stats` and `variant` ride along | `events[]` |

**Stat overrides** (`stats` on a row, a wave alt or an event): hp, damage, speed, size, radius, damage_reduction, `*_mult` on top,
`contact_cd` (seconds between bites), `attack_rate_mult`, `projectile_speed_mult`, `knockback_mult`, `pack`, `max_alive`,
`cap_share`, `xp_mult`, `drops{small, medium, large, gold, chest, pickup{id, chance}}`, `pickup_chance_mult`,
`pickup_weights{id: weight}`, `elite{hp_mult_per_stage}`, `boss{hp_mult_per_stage, cooldown_between, attacks{name: on/off}}`.
A missing key keeps the creature's own number (`EnemyDef.with_overrides`).

**The editor**: double-click `tools\level_editor.cmd` (a local page in the browser: Timeline, Settings, Creatures,
Instructions). Save writes `game/content/maps/<map>/<map>.json`, backs the old file up under
`tools/level_editor/backups/` and runs the JSON -> .tres import, so the editor binary plays it on the next launch;
commit the JSON. After a hand edit of the JSON, run the import yourself:
`"$GODOT" --headless --path game --script res://tools/import_json.gd -- only=maps/red_canyon`.

**Pass 53 pacing (Garry)**: skeletons and knights from 0:00 at 9 : 3 (three skeletons to a knight), the Lesser
Scorpion from 1:00 (the skeleton's numbers, packs of four), the fire ants from 5:00 as 0.6 of a mummy (36 HP, bite 8,
size 1.15, packs of eight); the Red Goblin, the Red Runt and the Werewolf (all the skeleton's numbers) are in the
content and the editor's palette and on no row until you place them.

## 3c. Pass 54: harder bites, spawn sides, HP and damage curves, presence keyframes, elite rows
Every key is in `docs/waves_schema.md` ("Pass 54 additions"); the Level Editor edits all of them.

| key | what it does | Red Canyon |
|---|---|---|
| `creature_damage_mult` | multiplies every hostile damage: bites, shots, spit, artillery, kamikaze blasts, death bursts, every boss and caster attack, the Brander's ring of fire (`EnemyManager.hostile_mult()`). The debug arena keeps 1 | 1.25 (Garry: +25 %) |
| `spawn_sides {mode, top, bottom, left, right, facing_share, facing_spread_deg}` | `"sides"`: a roster burst, a wave, a special, a random Elite and a creature culled from far behind arrive on a screen side drawn by weight, then 19-24 m out within ±45 degrees of it (top = north, the camera's up). `"facing"` (or no block, or all four 0): the old rule, `facing_share` of the spawns within ±`facing_spread_deg` of where the hero faces. Rings, swarms, the portal wave, bosses and Elite bosses are placed as before | sides 55 / 15 / 15 / 15 |
| `hp_curve {mode, points, formula}` | the creature-HP multiplier over the run clock (replaces `hp_growth` / `hp_power`, which stay as the fallback). `mode: "points"`: linear between `[t, mult]` points, flat outside; `"formula"`: `linear` 1 + a x minutes, `power` (1 + a x minutes)^b, `exponential` (1 + a)^minutes | power, a 0.0977, b 1.25 (the old pair): x1.94 at 7:10, x2.99 at 14:20, x4.11 at 21:30 |
| `damage_curve` | the same for creature damage (new: there was no time growth on damage before) | flat 1 |
| roster `weights [[t, w], ...]` | presence keyframes: the row's draw weight over the run, linear between points, flat outside; a row at 0 is never drawn. Replaces `weight` / `weight_late` / `weight_late_t` (old rows still slide as before) | every row converted, ids `r1`..`r17` |
| row `stats.variance` | the coloured variance specials per row, merged over the creature's `variance` (size and speed jitter, tints, `special_chance`, `special {size, hp, damage, xp, tint}`) | - |
| row `stats.elite_weight` | the row's weight when an `elite` / `elite_every` event with no creature named draws one (0 = never; random Elites used to be drawn evenly) | 1 |
| row `stats.elite_formats {single, pack, ring}` | how that modified creature arrives: alone, as its whole pack all wearing the modifier, or as a ring of `pack` of them 12 m round the hero (chances, normalised) | single |

## 4. Aim
Single-target weapons (`"targeting": "priority"`) pick the creature with the smallest distance ÷ weight, where weight is its max HP
over the crowd's average, from 1 to `PRIORITY_CAP` (3, in `game/core/systems/EnemyManager.gd`); bosses and Elites count as the cap.
At 3 a boss three times farther than a goblin is still the one they aim at; at 1 they aim at the nearest, as before.

## 5. Scenery
`game/art/sprites/props/props.json` lists every painted prop. `"hidden": true` on an entry keeps that painting out of the desert
(the signpost and the yucca since pass 49); delete the line to bring it back. The painting stays in the folder either way.

## 6. Arena dummies
Developer menu (hold the version line in Settings) and the arena panel's WORLD tab, saved in Settings:

| setting | what it does |
|---|---|
| health, count | the field: undying or 100 / 500 / 2,000 / 10,000 HP (a killed one stands up again after 5 s), 10 to 30 of them |
| patrol | the field dummies (and an idle attacker) walk left and right, 2 m either side of their spot (pass 49) |
| attacker health | the dummies **+ MELEE DUMMY** and **+ RANGED DUMMY** add (undying, 100, 500, 2,000); REMOVE ATTACKERS takes them away |
| Elite dummy, Boss dummy | health (Elite: undying, 500 to 50,000; Boss: undying, 2,000 to 200,000) and behaviour: stand, patrol, melee (chases you within 12 m of its spot and bites), ranged (spits like the Spit Cactus) |

The attackers' and the big dummies' damage, size and spit are numbers in their own JSON: `content/enemies/training_dummy_melee`
(10 a bite), `training_dummy_ranged` (8 a spit, the Spit Cactus's `ranged` block), `training_dummy_elite` (20 / 14),
`training_dummy_boss` (30 / 22; it counts as an Elite, so one touch takes at most 22% of your health). The first attacker turns
god mode off; dying in the arena puts you back on your feet at once (HERO's "Go down" still opens the Down! screen).

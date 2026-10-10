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
| `PickupManager` gem looks (pass 56): `GEM_GROW` 1.05, `HOP_EXTRA_MIN/MAX` 40/60 s, `HOP_EXTRA_HEIGHT` 0.3 m, `HOP_EXTRA_GAP` 0.75 s, `GLINT_EVERY` (medium 4-6.5 s, large 3-5 s), `GLINT_MAX` 8 | how the XP gems look and move, no numbers that pay: octahedrons 5 % bigger than v0.41's wedges, the old float kept, a very rare extra hop (each gem once in 40-60 s, never more than one starting on the screen every 0.75 s), and a star glint now and then on the medium and large gems only (at most 8 at once). Garry's words: "an occasional, very rare, little extra hop" |
| player stats `buff_duration`, `heal_mult` (pass 54) | `buff_duration` stretches every timed buff on the hero (power-ups, structures, Pollen, Barrel Rush, the shield; `Run.buff_seconds`); `heal_mult` multiplies every heal and her regen (`Player.heal`, `_tick_regen`). Solenne's trait Magic Hour since pass 61: debuff duration +1.5 % a level and nothing else (no buffs, cooldown or HP; section 8); her perks Afterglow (heals x1.4) and Sunburn (a burning or poisoned creature takes +20 % from her); Lingering Light (burns and poison +30 % harder and longer) and Long Day (buffs x2) are in the content, hidden |
| the mutation offer's weapon (pass 54) | drawn at random among the weapons with a path still open this stage (`Run.next_path_weapon`), shown by a pre-reel of those weapons' plates (`ui/wanted/WWeaponReel.gd`); it was the highest-levelled one |
| `params.lay_ahead` (pass 51) | a mine weapon's drops are flicked that many metres ahead of the hero while he walks (at his feet while he stands). Jackrabbit Mines 2.0; the Land Mine has none |
| `mutations/wide_reach` `params.spring.sense` | how far a mine springs at a creature: 2.8 m since pass 51 (was 3.5). The Jackrabbit's own `jackrabbit.sense` is 6 |
| `content/passives/<id>` | lines and passive items: `levels`, `max_level`, `line`, `evolves_into`; `rarity` and `weight` for the offers |
| `content/characters`, `content/perks` | heroes (`trait_per_level`: the 1-2 stats that grow every level since pass 61, `order` on the title, start weapon, favourite), their perks |
| `StatSheet.PLAYER_DEFAULTS` (code) | what every hero starts with before his trait: 1% crit chance since pass 52 (crits do x2), one reroll a run, 2 skips and 1 banish a stage. the Drifter's trait adds +1% crit a level (pass 61), Deadeye +8% a level |
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
| **Choices**: 2 skips and 1 banish a stage, shared with the mutation tables and chests; 1 reroll a run (the Mirror adds more). A skip pays nothing; a banish swaps that one card and keeps the item out for the run. **Pass 58** (Garry: "Banish option should not allow Banishing items that Player already has, because this way they can lock themselves out of progression"): a banish never strikes an item you hold (a weapon, a line or a passive item at any level), an evolution, or a path mutation of a weapon you hold; a new item, a perk or a hero's own optional mutation may go. With nothing banishable on the table the button locks and says why; a refused tap spends nothing. Chests follow the same rule. Once a weapon evolves, its base weapon is never offered again (level-ups, the Stranger); a hero's own mutation banished from a boss chest never comes back | `Run.refill_choices`, `Run.banish_refusal`, `CardPool.banishable` |
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
| `level_hp_per_level`, `level_damage_per_level` | creatures grow with the hero's level (pass 58: the hero's level when a roster row or wave first spawns, kept for every creature of that row) |
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
| `hp_curve {mode, points, formula}` | the creature-HP multiplier over the run clock (replaces `hp_growth` / `hp_power`, which stay as the fallback; pass 58: read once at each row's start, see 3d). `mode: "points"`: linear between `[t, mult]` points, flat outside; `"formula"`: `linear` 1 + a x minutes, `power` (1 + a x minutes)^b, `exponential` (1 + a)^minutes | power, a 0.0977, b 1.25 (the old pair): x1.94 at 7:10, x2.99 at 14:20, x4.11 at 21:30 |
| `damage_curve` | the same for creature damage (new: there was no time growth on damage before) | flat 1 |
| roster `weights [[t, w], ...]` | presence keyframes: the row's draw weight over the run, linear between points, flat outside; a row at 0 is never drawn. Replaces `weight` / `weight_late` / `weight_late_t` (old rows still slide as before) | every row converted, ids `r1`..`r17` |
| row `stats.variance` | the coloured variance specials per row, merged over the creature's `variance` (size and speed jitter, tints, `special_chance`, `special {size, hp, damage, xp, tint}`) | - |
| row `stats.elite_weight` | the row's weight when an `elite` / `elite_every` event with no creature named draws one (0 = never; random Elites used to be drawn evenly) | 1 |
| row `stats.elite_formats {single, pack, ring}` | how that modified creature arrives: alone, as its whole pack all wearing the modifier, or as a ring of `pack` of them 12 m round the hero (chances, normalised) | single |

## 3d. Pass 57 and 58: spawn patterns, a row's numbers fixed from its start, size and colour ranges
Every key is in `docs/waves_schema.md` ("Pass 57", "Pass 58"); the Level Editor edits all of them.

| key / rule | what it does |
|---|---|
| `pattern: "ring"` (pass 57) | the whole spawn evenly round the hero 11.7 m out (the arena's 9 m ring x 1.3): a row's pack, a wave's burst, all at once. The editor's note under Pattern says how many make a thick ring (skeletons: about 105). Near the wall the ring spreads over the arc inside the arena (pass 58) |
| `pattern: "in_front"` (pass 57) | each creature at its own point 19-24 m up the screen within 45 degrees of straight up, whatever `spawn_sides` says |
| **A row's numbers are fixed from its start** (pass 58, Garry: "a single wave of those enemies will stay consistent for the duration of their spawns") | a roster row's (or wave's) creatures all get the HP curve and the damage curve read at the row's start `t` (an event at the moment it fires), and the hero-level factor from the row's first spawn. A row with its own `stats.hp` (or `damage`) takes **no** curve: that number is the row's HP (Garry: "the multiplier will inform what the HP should be for enemy rows whose stats weren't overridden"). On top, as before: the stage multiplier (it steps at a new stage and at each endless wave), `creature_hp_mult` / `creature_damage_mult`, the variance special, elite modifiers. Bosses and the Elite creatures keep their own rules. An event (a swarm, an Elite, a special, a boss's brood) of a creature a row is bringing at that moment, in the same look, joins that row's numbers; the portal wave takes the numbers of the row it drew. In endless every row fixes its numbers afresh at each WAVE. A bar with no end keeps its start's numbers for the rest of its stages: split a long bar to make it grow. The editor's **Actual HP x** / **Actual ATK x** lanes show what the rows really carry against the intended curve |
| `stats.size: [min, max]` (pass 58) | every creature of the row rolls its size in the range (instead of the variance's jitter); its radius follows unless `stats.radius` is set; the variance special stays inside the range (an elite modifier's scale still adds its own). A plain number works as before |
| `stats.tint {hue: [h0, h1], sat, val, amount}` (pass 58) | every creature of the row is coloured by a hue rolled in the range (wrapping through red), strength `amount` (the shader mixes amount x 0.65). A coloured row's variance special takes a darker, stronger shade of its hue. Elite colours, burns, poison and freezes still show over it |
| creature `blood` (pass 58) | the colour of its death splash (a brief puff of droplets at the body); set per creature on the Level Editor's Creatures tab |
| the Strongbox's coins (pass 58) | purely visual: the purse is banked the moment the hero uses the box; 3D coins then fly from the hero into it for 3 to 3.6 s (one coin a gold up to about 37, about 89 at 400 gold, at most 120), quicker and denser the more gold, and the box lifts off after the last one |

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

## 7. Pass 60: the shop's prices, the Pressure Cooker, knockback, banish, creature speed, the magnet

- **The in-run shop** (`ui/StructureShop.gd`; Garry: an item is worth about half the gold a player earns in a stage, by
  item type). Price = `PRICE_BASE_BY_STAGE` [300, 500, 700] (the run's stage, endless = stage 3) x kind (`KIND_MULT`:
  weapon 1.0, evolution 1.0, line 0.85, passive item 0.7, perk 0.7) x rarity (`RARITY_MULT`: common 0.8, uncommon 0.9,
  rare 1.0, epic 1.2, legendary 1.4) x (1 + `LEVEL_STEP` 0.12 x the level already held) x `EVOLUTION_MULT` 1.4 for an
  evolution, rounded to 5, never under 40. Examples at stage 1 / 2 / 3: a common weapon 240 / 400 / 560, a rare line
  255 / 425 / 595, a common passive item 170 / 280 / 390, an epic passive item 250 / 420 / 590, a legendary weapon
  420 / 700 / 980; a weapon upgrade from Lv 3 costs x1.36. A stage pays about 630 / 1,000 / 1,450 gold (coins, the Elite
  purses 90 / 150 / 210, the boss 260 / 400 / 540 + coins, a loot cache 60), so about two items a stage and usually none
  before the first boss (about 250 gold arrives before it). One shop a run, one card a visit (unchanged).
- **Pressure Cooker** (Rocket Pod motion path, `params.pressure {max 2.0, seconds 15, hit_vent 0.5}`; the Hellfire
  Battery `{max 2.0, seconds 15, start 0.25, hit_vent 0.5}`): the pressure 0..1 climbs by dt / seconds while the hero
  stands still (`Player.is_still()`: 0.5 s of grace under 0.3 m/s), drops to 0 the moment he moves, and a hit on his
  health or on the Energy Shield multiplies it by (1 - hit_vent) (the Invincibility bubble's absorb does not vent it);
  fire interval = cooldown / (1 + start + (max - start) x pressure): three volleys where one went at the top, after 15 s
  of standing; for `VENT_HOLD` 0.8 s after a hit the ramp neither climbs nor dumps (the hit's knock carries the hero a
  step, which is not him moving). The pod glows with it (no HUD label). The pass-53 "unhit for 20 s" rule is gone (Garry: "it's never going
  to trigger").
- **Knockback** (`player/Player.gd`): the Invincibility power-up (`shield_t > 0`) nulls every knockback (bites, charges,
  slams, the burrow, rumbles, hostile shots, blasts); the Energy Shield line, the revive/level-up blink and god mode do
  not. A creature's knock (bites, charges, slams: `hit_knock` / `shove`) is thrown out of the crowd: `escape_dir` scores
  16 flat directions by the creatures within `ESCAPE_REACH` 4.5 m (each weighs 1 - d / 4.5 toward its side) minus
  `ESCAPE_PUSH_W` 0.6 x the push's own direction, and takes the emptiest; a lone biter still pushes straight away, two
  creatures either side push out through the gap. Within `KNOCK_SETTLE` 0.45 s of the last creature knock a second one
  may not reverse it (the component against the last knock is dropped, at least `SETTLE_KEEP` 0.35 of the magnitude
  kept). Hostile shots, blasts and ranged hits keep their own line. Caps unchanged (`HIT_KNOCK_MAX` 9 m/s, `KNOCK_GRACE`
  1 s, `STICK_LOCK` 0.12 s).
- **Banish**: no mutation can be banished anywhere ("A mutation cannot be banished."), hero mutations included (pass 58
  had let those go on the boss chest). The mutation offer never had a Banish button; the boss chest locks it with the
  reason. Skips are unchanged.
- **Creature speed**: the map's `creature_speed_mult` (0.9 on Red Canyon, default 1; Level Editor: Settings > Scaling >
  "Creature speed x") multiplies every creature's, Elite's and boss's pace: the walk speed at spawn, charges and rolls,
  wind-ups / warnings / telegraphs (1 / mult as long), every hostile shot, boulder and rumble (`hostile_clock()`), the
  Vulture Raider's rocket; not the hero (`move_pace`), not poison / fire ticks, attack cooldowns or spawn clocks. Red
  Canyon's effective creature pace is 0.9 x 0.9 = 0.81.
- **The Dune Scorpion's burrow**: `windup` 2.3 s (was 1.3; the Gila Grande keeps 1.4): a sand mound (0.3 x size wide,
  0.45 of that tall) swells at the ring's centre over the wind-up, then the pop: a soft-dust poof (`Fx.pop_dust`), the
  damage and knockback as before, and the figure rises out of the sand over `RISE_TIME` 0.4 s (divided by the creature
  pace), hittable but not biting until up.
- **The magnet arc** (not balance, for the record): the big pulls (Magnet Pulse, Uber Magnet, the boss chest's opening,
  the Elite's vacuum gem, Turret Family's attractors) throw every gem (and coin) up in a wave rippling out from the hero
  (a wait of 0.035 s a metre, at most 0.5 s + 0.12 s of jitter), 2.4-3.8 m up with a little outward drift, a hang of
  0.06-0.16 s, then the ordinary dive; a gem 8 m out is in within 1.9 s, 20 m out in about 2.6 s. The walk-up pull keeps
  its hop. Gems are x0.78 darker with a 0.3 glow at rest and glow in their own hue while charged (`gem.gdshader`).
- **Sounds**: every effect comes from Stable Audio (`tools/ai_sfx.py`), levelled to -14 dBFS RMS with peaks at -2 dBFS;
  13 rows' `volume_db` moved by 6 dB toward the old balance (ui_pause, ui_locked, w_lob_throw, en_goblin_die,
  en_cactus_die, en_beetle_die, en_scorpion_die up; w_zap_hit, w_molotov_boom, en_golem_die, en_king_volley,
  w_hawk_sting, w_guitarra_strum down); the effects sit about 6 dB further under the music than the placeholders did.


## 8. Pass 61: heroes that grow with their level, gems that stay

- **Hero traits** (`content/characters/<id>/<id>.json` `"trait_per_level"`; Garry: "Heroes have 1-2 unique stats, and
  they scale as they level up"): one effect per stat worth N x the hero's level, so level 1 already carries N; nothing
  else in the trait (`"trait": []`). Start weapons, favourites and their bonuses, and perks are unchanged.

  | Hero | Per level | Lv 1 | Lv 15 | Lv 25 | Lv 40 |
  |---|---|---|---|---|---|
  | Drifter | crit chance +1 % (crits do x2) | 2 % with everyone's 1 % | 16 % | 26 % | 41 % |
  | Astro | max HP +2 (current HP rises with it); `level_heal` 8 % of max HP every level-up | 102 | 130 | 150 | 180 |
  | Calavera | attack damage +1 % | +1 % | +15 % | +25 % | +40 % |
  | Ironwood | regen +0.1 HP/s, regen delay -0.05 s (never under 0.5 s: `StatSheet.STAT_FLOORS`) | 0.1/s, 2.95 s | 1.5/s, 2.25 s | 2.5/s, 1.75 s | 4.0/s, 1.0 s |
  | Solenne | debuff duration +1.5 % (burns, poison, slows, marks, pins; not buffs) | +1.5 % | +22.5 % | +37.5 % | +60 % |

  Against the old flat traits: the Drifter is ahead in damage at every level but lost +10 % speed and +25 % pickup
  radius; Calavera hits softer until about level 28 (0.80 of before at Lv 5) and has his full health back (100 against 85); Astro is about
  even at Lv 5 and well ahead from Lv 15; Ironwood is behind until Lv 12 (1.2/s), far ahead late (his perk Unbroken
  already skips the regen delay); Solenne lost +15 % attack speed, buffs x1.25 and -20 % HP and beats her old debuff
  length from Lv 17. Creatures were not retuned: they grow +5 % HP and +3 % damage per hero level (`level_hp_per_level`,
  `level_damage_per_level`), so no trait outpaces them. If run records show more early deaths for Calavera, Solenne or
  Ironwood, raise their N, not the creatures.
- **A max HP rise brings the same health with it** (`Player.refresh_stats`, for every hero and every source: Astro's
  levels, Vigour and Ironclad, a Stranger deal that nets positive); a fall keeps the share of health the hero had, as
  before. Nothing raises and lowers max HP repeatedly, so it cannot be farmed for healing.
- **XP gems and coins never fuse or vanish** (Garry: "I'd prefer that they don't disappear ever, but don't affect the
  performance negatively at all"): the merge and the coin cap are gone; the pool starts at 2,048 and doubles when full (a real run never needs it to).
  A pickup lying on the sand costs nothing per frame (a 4 m grid read only round the hero's magnet and the turrets' pulls;
  the float and spin run in the shader): 3,000 lying gems cost 0.04 ms a frame on the PC against 0.8 ms for the old
  600-cap. A big pull (Magnet Pulse, Uber Magnet, the boss chest, the Elite's vacuum gem) walks at most 80 pickups a tick;
  on-screen ones do the pass-60 arc (at most 600 flying), off-screen ones fly in from just past the screen's edge when
  they would have crossed it (at most 80 at once) and, with that stream full, are collected unseen at the moment they
  would have arrived (their XP and gold arrive then; nothing vanishes on the screen). A real run with a crowd weapon
  leaves about 560 gems lying at 5:40 and 880 at 7:00 (the old merge started at 300).
- **Not balance, for the record**: the Upgrade board shows each form's icon in a rank bar; the XP bar is 65 px; the
  sand and river colours; bush patches (5-7 a run, 4-6 bushes, no colliders); signs 1.4x taller.

## 9. Pass 62: pierce drop-off, Pocket Watch, the Spit Cactus, two hero mutations

- **Pierce drop-off** (`params.pierce_falloff {step, floor, first_mult}` on the weapon; Settings' Debug panel and the
  developer menu switch it, `Settings.pierce_falloff`, default on; off = the old numbers exactly): a shot fired with
  pierce >= 1 (or the Spear's thrust line) deals damage x first_mult x max(step^(n-1), floor) to the n-th creature it
  hits, step 0.8, floor 0.4. A pierce-0 shot, ricochets and bounces, blasts, cones, Birdshot's lane, DoT ticks and
  sweeps are untouched. first_mult: 1.15 Tommy Gun, Revolver, Golden Revolver, the Spear; 1.2 Chicago Typewriter and
  Thunder Lance (thrust); 1.1 Boomstick (it pierces only at level 5), Iron Bastion. Share of today's damage: a lone
  target 110-120 %, two in a line about 100-108 %, three 90-98 %, four 85-89 %. Turret Buddy has no pierce on any route
  (its data is inert) and the Blunderbuss hurts with a cone blast (no data).
- **Pocket Watch** (passive item, uncommon, 5 levels): power-ups picked up from the ground last +15 % a level
  (`powerup_duration`, x1.75 at 5: Berserk 20 -> 35 s, Sprint 15 -> 26 s, Shield 6 -> 10.5 s), and at levels 1, 3 and 5
  they drop +4 % more often (`powerup_chance`, x1.12 at 5, on the timeline's per-kill chance). Structures, Pollen,
  Barrel Rush and the Supply Drop are untouched.
- **Spit Cactus**: its spit hurts only where it lands (`ranged.land_only`; the splash 1.2 m + the hero's body 0.4, a red
  ring at the landing spot for the whole flight), flies x0.9 (`projectile_speed` 5.4), with a faint trail and a pulse
  (`ranged.trail`, `ranged.pulse`; the ranged training dummies spit the same way).
- **Heartseeker** (Ironwood's hero mutation on the Spear): every 4th stroke (`params.crit_stroke.every`) is a forced
  crit on everything it hits (`EnemyManager.HIT_CRIT`, the hero's crit damage) and reaches x1.2; with Wide Sweep it is
  the sweep, on the Thunder Lance the thrust half.
- **Sun Cocktail** (Solenne's hero mutation on the Molotov): a bottle bursts where it lands for 150 % of its damage in
  0.9 x the pool's radius (1.8 m at the base area) with a weak knockback 2.4 (a grenade's is 7), the fire pool as before.
  **Solenne's favourite is the Molotov** (arrives at level 2); Haste is no longer hers.
- **Stages 2 and 3** (Red Canyon; stage 1 is Garry's and unchanged): creature damage x0.65 through stage 2 and x0.55 ->
  x0.6 through stage 3 (`damage_curve` points; the bosses keep their stage's value), creature HP by each row's
  `stats.hp_mult` on a ramp that starts low at a stage's start (the x2.2 / x1.52 stage step lands all at once while the
  hero grows within the stage): 7:11 x0.38 -> 12:00 x2.0 -> 14:20 x2.1, 14:21 x0.55 -> 19:04 x2.0 -> 21:30 x2.1; hammer
  giants x1.0 / x0.8 HP and x0.7 damage; the Elites at 10:45 / 17:55 x1.3 / x1.9 HP. Targets (Garry): stage 2 clearable
  with half the Mirror (every talent at rank 3), stage 3 with the full Mirror; calibrated with
  `tools/difficulty_probe.gd` against stage 1 with an empty Mirror (Garry's real runs: an extraction at 8:24, most deaths
  4:30-7:45). The rule for big hits: a rocket is about half of the Mirror hero's health in each stage, a slam under it.
  Stage 2's fit is reasonable; stage 3's "needs the full Mirror, not half" rests on the per-hit numbers (the bot could
  outrun stage 3's crowd with a full build). `stage_mults` are untouched (they also set coin value and boss HP).
- **The Mirror's sustain is front-loaded**: Thirst rank 1 already reaches the lifesteal cap (4 % of max HP a second), so
  ranks 2-6 of Thirst add almost nothing; worth a look.

## 10. Pass 63: the Upgrade board's ranks are choices

- Every rank of a talent is bought in one of its two forms and keeps it (`Save.talent_picks(id)`: the forms rank by rank;
  `Save.buy_talent(def, form)`); there is no form switch any more. The price follows the talent's rank (`cost_of_rank`),
  whatever the form; each form's ranks fold on their own (two Padding ranks and one Plate rank = +21 % max HP (x1.1 x1.1)
  and +6 % damage reduction). Take it all back returns half the gold and is the only way to choose again. An old save's
  {form, rank} reads as that form `rank` times.

## 11. Pass 64: the Strongbox returns, easier stages 2 and 3

- **Strongbox**: after one is used and flies away, another drifts down 30-60 s of run later (`gold_bank.json`
  `params.respawn`), at a random valid spot at least 20 m from the hero; one at a time. Every structure keeps 3 m from
  the lake (new).
- **Stages 2 and 3** (targets: stage 2 with a quarter of the Upgrade board, about 1.5 of 6 ranks a talent; stage 3 with
  half): creature damage x0.5 in stage 2 and x0.39 -> 0.43 in stage 3 (`damage_curve`); row HP ramps 0.27 -> 1.46
  (stage 2) and 0.39 -> 1.42 (stage 3); the Elites at 10:45 / 17:55 x0.94 / x1.33 HP; hammer giants x0.72 / x0.56 HP and
  x0.7 / x0.55 damage. A stage-2 rocket is about 0.4 of a quarter-board hero's health, a stage-3 one about 0.5 of a
  half-board hero's. Stage 1 is unchanged. First knobs to nudge: the 9:45-11:45 skeleton/knight rows, the ATK x points
  (keep stage 2 above about 0.46, or its bites fall under stage 1's), the Elite HP.

## 12. Pass 65 (not balance, named so they are not surprises)

- Blob shadows lie on the slope under each figure; the hero's stays on the sand when he jumps.
- Gem pickups ring higher on quick repeats (0.5 semitone a step for small and medium gems, 1.0 for large, within 0.3 s,
  at most 10 steps); the hero's hurt sound plays at most every 0.25 s.


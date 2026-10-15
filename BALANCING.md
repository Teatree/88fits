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
| `knockback_resist` (pass 67) | the other way round: the share of every shove from the hero's side this creature shrugs off, 0..1 (default 0; 1 = never moved). A weapon hit's push is `kb_force / max(size, 0.8) x (1 - resist)` (x 0.15 more for the boss, which keeps resist 0); a blast's `throw_radius` (the hero's nuke ring, Thruster Burst, Grand Finale, and hostile throws alike: a rocket, a boulder, the stalactites), the Lasso's pull and Buck's Ram take the same share off. Not a damage reduction. Lifts, bounces, the twister's fling, the Singularity's drag and a charger's side-shove are not knockbacks and ignore it. The Hammer Giant 0.67: a third of its old push (Garry, pass 67). A row may set `stats.knockback_resist`; the Level Editor's Body row ("Knockback resist") and the card's "KB resist" show it. Rule 14.1 |
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
| `WeaponBehavior.GLOW` 0.45, `params.glow` (pass 53) | every dim material of a companion or held model (no emission of its own) emits its albedo at this energy so the 3D things round the hero read on the sand (Garry: "they are quite dim"); `glow: 0` on a weapon turns it off, a number sets its own; since pass 67 the map's `weapon_grade.glow` (Red Canyon 0.3) is the energy when the weapon names none |
| the map's `weapon_grade {value, saturation, glow}`, `params.grade` (pass 67, rule 14.1) | every lit material of a weapon's 3D model (a shaded, opaque, untextured StandardMaterial3D: held guns, companions, blades, hammers, turrets, the Spear's model) is drawn in a copy graded in HSV: value x `value` (Red Canyon 0.78), saturation x `saturation` (1.3, clamped at 1); a material that already emits (the gold guns, the sceptre's sun) has its emission graded alike, so its gold stays gold; the glow above then emits the graded colour. Garry: the 3D weapons "get lost in the background". One copy per material (MeshMerge still joins the parts), the source never written; the unshaded and see-through FX, the textured and everything built in code (the Golden Pineapple's grenade, the turret fallback, the silver rounds, the rust blades, the default shot) are left alone. `params.grade` on a weapon (a mutation's or an evolution's `final` too) wins key by key; `{"value": 1, "saturation": 1}` = as the file has it |
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

## 12. Sounds: pass 65 and pass 67 (not balance, named so they are not surprises)

- Blob shadows lie on the slope under each figure; the hero's stays on the sand when he jumps (pass 65).
- The hero's hurt sound plays at most every 0.25 s (pass 65).
- **The gem tune** (pass 67, Garry: "make the EXP gem pickups work into a kind of a tune when the player picks up several
  one after the other"; it replaces pass 65's quarter-tone slide, which the ±0.5 semitone jitter and three separate
  counters had hidden). The three gem rows of `content/sounds/soundmap.json` share one counter (`chain_group: "gems"`):
  a gem picked within `chain_window` 0.6 s of the one before takes the next step of the tune; a longer pause starts it
  again from the first note. A step is a note of the row's `ladder` (semitone offsets from the ding's own note): small
  gems (G6) and large gems (C6) climb a major pentatonic `[0, 2, 4, 7, 9, 12, 14, 16, 19]`, medium gems (E6) a minor one
  `[0, 3, 5, 7, 10, 12, 15, 17, 19]`, so whatever sizes land in a row, every note is in C major. Gems that land within
  `chain_min_ms` 70 ms of a step's first play repeat its note (a vacuum's flood plays about 14 notes a second instead of
  jumping to the top); the top note holds (`chain_end: "hold"`; `"wrap"` would start the ladder again). The ladder's
  last step is the top unless `chain_max` is lower (the rows' 10 is not: set 5 to stop at the octave). The rows'
  `pitch_spread` is 0 so the notes are exact; `chain_step` stays in the rows but only rules a row that has no `ladder`
  (the pass 65 rule, unchanged for such rows). The `voices` caps (6/4/2 plays per 400 ms) still drop the plays over
  them, and a dropped play does not advance the tune. Code: `Audio.chain_pitch`; the keys are listed in
  `JsonContent.soundmap_from_dict`.
- **The chest's sounds** (pass 67, Garry: "chill with the chest ending sound"). At a chest now: the touch plays
  `pk_chest_open` (-3 dB) in the world, once (the lid's crack no longer plays it a second time); the knocks play
  `ui_chest_knock` (-4 dB; its `voices` 2 lets two of the three through); the reel runs `ui_slot_start` (-8) /
  `ui_slot_spin` (-12) and lands with `ui_slot_stop` (-10 dB, was -6) and `ui_jackpot` (-9 dB, was -3) for every kind,
  an evolution included; TAKE IT plays the tap and `ui_chest_take` (the poker chip's clack, `real/ui_card_pick.wav` at
  -6 dB) instead of the purchases' ka-ching (`ui_buy` stays at -3 dB on the Upgrade board and in the shops); an
  evolution's mega-win `w_evo_reveal` (0 dB) plays once, with the EVOLVED banner and the shake, when the evolution is
  taken (`Game._on_evolved`), no longer at the landing as well. The level-up's mutation reel lands on the same, quieter
  `ui_jackpot`. The files are unchanged; only rows and call sites moved.
- **Placeholder ids** (pass 67, for the basketball and the jump-away item): `w_ball_throw`, `w_ball_bounce`,
  `w_ball_catch` (weapon), `pk_timeout` (pickup: a referee's whistle), `ui_buzzer` (ui: a shot-clock buzzer) play
  `placeholder/<id>.wav` from `tools/gen_sfx.py` until they are made real with `tools/ai_sfx.py` (a `PROMPTS` row, then
  `--only <id>` and `--pick`).
- **every touch of the ball is heard.** A weapon with `catch` plays its "hit" sound (w_ball_bounce) on every creature it touches (the throw, each hop, each touch home), held to the sound map's voices; the catch plays its "catch" sound (w_ball_catch) at his hands. (The ProjectileManager plays no other weapon's hit sound but the Spear's first strike.) (pass 67)

## 13. Pass 66: the Level Editor's assets (not balance: named so they are not surprises)

13.1 **A new hero starts hidden.** The Heroes tab creates him with `hidden: true`, `availability: "hidden"`, `price 0`
and `currency_type "gold"`. `availability` is "hidden", "available" or "purchase"; anything but "available" keeps him
out of play (JsonContent folds it into `hidden`, so a "purchase" hero is a hidden hero until the loop is wired). `price`
and `currency_type` are written and shown nowhere: the hero purchase loop is parked at Garry's word ("don't worry about
it for now, just make a note of this question and next time I ask about this, just remind me").

13.2 **A new line or passive item starts available**, at its template's weight (its rarity's usual) and rarity, and is
offered as any other: no quest, no stage gate unless the template had one.

13.3 **A new weapon starts hidden with its path templates.** The Items tab creates a weapon with three template path
mutations (`<w>_element`, `<w>_volume`, `<w>_motion`; kinds element, volume, motion) and a template evolution
(`<w>_evolved`, `evolves_into` set), all five `hidden: true` (`NEW_WEAPON_STARTS_HIDDEN` in server.py). The weapon may
turn available only when each template mutation has `text` and at least one effect or param and the evolution has a
`name`; the availability check lists what is missing. A hidden weapon's hidden templates are never offered and count
for no test (pass26 and pass66_shape look at the weapons in play).

13.4 **A shelved look stays a look.** `variants[CODE].shelved: true` takes a creature's or a hero's look out of the
arena's chips and the editor's default lists (`variant_codes()`), but `variant_def(code)`, `Registry.enemy_with` and a
wave row or a kept hero look naming it still play it. The look the game plays (`variant`) cannot be shelved. The
arena's "Shelved looks: Show" lists them dimmed.

13.5 **`<PREFIX>-0` is the strip as it was.** A creature that had no `variants` gets `variant_base: "<PREFIX>-0"` with
the first look the editor adds ("the top-level strip, before the Level Editor's looks"); a hero's first base is
`<PREFIX>-A`. PREFIX is the most common prefix of the existing codes, else `variant_base`'s, else the initials of the
id's words (a one-word id its first three letters). The next suffix is the first free letter, then AA onwards.

13.6 **One ComfyUI job and one Godot process at a time**, repo-wide: `tools/dl/locks/comfy.lock` and
`tools/dl/locks/godot.lock` (mkdir locks with an owner.json; `tools/locks.py`, `tools/godot.sh`). The lanes'
`tools/dl/p6X/godot.lock` retires. A lock whose owner is dead is reclaimed; one without an owner.json is only ever
released by hand.

13.7 **A placeholder strip keeps `strip_cols` 0.** The create flow copies no `anims`, `strip_cols`, `fps` or `head`
from the template (the placeholder is one row); `gen_placeholders.gd -- only=<type>/<id>` fills just the new folder.

13.8 **The count pins are shape rules.** `pass66_shape_test.gd` holds them and the editor checks the same rules on
Save: every weapon in play has exactly one element, one volume and one motion mutation and an evolution naming it
back; every line evolves and every evolved passive has a source; every hero in play has at least one perk and exactly
one hero mutation on his favourite weapon (on his start weapon when his favourite is a passive); the title's heroes are
the non-hidden ones by `order`, orders distinct; a crown is an Elite's alone and every plain Elite wears one; every
creature has a `knockback` above 0, a `blood` and a `doc`; passive items take common to epic, never legendary;
`Registry.problems` is empty; every roster row names a creature in play in a look it has; a hidden hero has no hero
mutation in play. The old counts (113 mutations, 61 passives, 18 perks, exactly five heroes, exactly four crowns) are
gone.

13.9 **Any brain and attack-block combination is allowed.** One that no creature in play uses is marked "untested in
play" on the Enemies tab, not refused.

13.10 **"Locked" is a quest.** An item is locked when a quest's `unlocks.id` names it; the Items tab's availability op
creates or removes `content/quests/unlock_<id>/` in the shape of `unlock_adrenaline.json`. The quest-locked share of the
items in play (pass44_test: 0.33-0.56) is shown on the Items tab with a warning when a change would leave the band; the
test stays as it is, pending Garry.

13.11 **A fresh look plays at once.** A look that has just landed is `fresh: true` until Approve; it is selectable in
the arena and by a wave row meanwhile. Approve only clears the review mark.

13.12 **A created enemy has its own numbers.** `knockback` is written out as `EnemyDef.default_knockback(damage)`
(`clamp(3.4 * sqrt(damage / 4), 2.5, 7.0)`), `blood` comes from the template and `doc` is asked for at creation, so
"every creature has a knockback, a blood and a doc" holds for it. A removed look's PNGs and `.import` files move to
`tools/level_editor/backups/deleted/<id>/<stamp>/`, never deleted outright; Delete of a created id is allowed only for
ids in the local ledger `tools/dl/jobs/created.json`.

## 14. Pass 67 (Polish 2)

Garry's Polish 2 list (2026-10-11): darker weapon materials, the Hammer Giant at a third of its knockback, a quieter chest, a gem tune, Buck back in play and more powerful, and a new escape hero, Fadeaway, with a basketball. Every number below is in a JSON file and is his to tune; the designs are tools/dl/p67/design_spec.json.

### Balance

14.1 **A creature may shrug off knockback.** `knockback_resist` (creature JSON, top level, 0..1, default 0; §1) is
the share of every shove from the hero's side the creature does not take, applied as `x (1 - resist)` on the push: a
weapon hit's `kb_force / max(size, 0.8)` (every behaviour's hit and blast goes through `EnemyManager.damage`), a
blast's `throw_radius` (the hero's nuke ring, Thruster Burst and Grand Finale, and hostile throws alike: the
rocketeer's rocket, a loose rocket, the golem's boulder and stalactites), the Lasso's pull and Buck's Ram. 1 = never
moved. The boss's own 0.15 stays a separate factor on top (compose, never replace), and every boss keeps resist 0. It
is not a damage reduction: the hit lands whole. Lifts, bounces, the twister's landing fling, the Singularity's drag and
a charger's side-shove are not knockbacks and ignore it (they keep their own rules). The Hammer Giant carries 0.67, a
third of its old push (Garry: "the Hammer Giant should take 1/3 of the knockback it currently does"); its size (3.4 m)
was its only weight before. A roster row overrides it as `stats.knockback_resist` (clamped), the Level Editor edits it
in the Body group of the Enemies tab and of a row's overrides, and `EnemyManager` keeps the share taken per type
(`_t_kbt`). In a JSON it sits right after `knockback` (never between `damage` and `knockback`: pass54_waves_test pins
that order); `pass67_kb_test.gd` pins the maths.

14.2 **Buck is back in play, the seventh hero.** Garry: "Movement Speed Hero: bring back the gazelle guy, do the speed
thing but make it more powerful; look through the items and see if they still make sense." `buck.json`: `hidden` false,
`availability` "available", `order` 7 (Fadeaway holds 6). No `start_weapon`: he lands with his favourite, the Tommy Gun
(Registry.start_weapon_for's favourite fallback, pass45_runflow pins it), with its +2 amount; his perks are Ram and
Overdrive, his hero mutation Drum Roll on the Tommy Gun. No unlock quest and price 0 (the purchase loop is parked). The
look in play is BUC-B (run_spread back views); BUC-C stays shelved.

14.3 **Buck's charge (`momentum`), three stats.** `momentum` {`ramp_seconds` 10, `speed_bonus` 0.8, `might_bonus` 0.6,
`evade_bonus` 0.2, `hit_loss` 0.5}: while he is not hit the charge climbs from 0 to full over `ramp_seconds` (+10% a
second) and adds, at full, +80% move speed, +60% attack damage and +20% evade chance (evade is an add, the other two
muls; all three under one "Momentum NN%" source on the pause sheet, `Run._build_player_sheet`). At level 1: 3.6 x 0.85 x
1.01 = 3.09 m/s uncharged, 5.56 m/s at full (a plain hero runs 3.6; Sprint + Roadrunner 6.1); at level 40 4.28 and 7.71
m/s. No move-speed cap exists (StatSheet.STAT_FLOORS holds regen_delay only). The evade guards the charge itself: an
evaded hit never touches it. A block without `evade_bonus` adds no evade (the Level Editor's default is 0).

14.4 **A hit that lands knocks off `hit_loss` of the charge** (0.5: full -> half, full again 5 s later; two in a row
leave a quarter). Only a hit that reaches his health counts (`Player.take_damage`, after the evade, the shield power-up,
the Energy Shield and the invulnerability returns): evaded, shielded and immune hits keep the charge whole, and Ram's
contact is no hit at all. `hit_loss` 1.0 is the old full reset and the default when the key is absent (a hero made in
the Level Editor with the momentum special keeps the old rule unless it is set).

14.5 **The charge climbs while he stands still**, as it always has (`Player._tick_momentum` does not look at movement):
a Buck parked behind a turret still reaches full speed, damage, evade and Ram. Kept on purpose and named here so no
later pass "fixes" it; if Garry wants it to climb only on the move, it is a one-line `moving` check in
`Player._tick_momentum` (a new rule, to be named here then).

14.6 **The charge always lands on exactly full.** The sheet follows the charge in quarter-second steps, and skipped a
step smaller than 0.02; after a half-loss the steps could end at 0.98x and the charge then stayed there for good, under
Ram's 0.99 and the words' FULL. The last step now always lands on 1.0 (`Player._tick_momentum`). A bug fix, not a new
number.

14.7 **Full Tilt: +1% move speed a level, beside the flat -15%.** `trait_per_level` [move_speed mul 0.01] (Run.hero_sheet
folds 0.01 x level as "Full Tilt (Lv N)"), and the flat `trait` -15% move speed stays (pinned by pass23 and pass21): a
first for a played hero, two speed sources on one sheet, on purpose ("Slow to start"). Uncharged he reaches a plain
hero's pace at about level 18 (0.85 x 1.18 = 1.00; 0.98 at level 15) and runs +19% at level 40 (0.85 x 1.40). Nobody
else grows speed a level (the Drifter lost his in pass 61). His trait in words is the rule, then his `trait_text`
(TextGen.hero_trait appends a hero's trait_text when he has a level rule and a special: "Gain 1% move speed per level.
Starts 15% slower. While he is not hit his charge climbs over 10 s to +80% speed, +60% attack damage and +20% evade
chance; a hit that lands knocks off half of it.").

14.8 **Overdrive (Buck's second perk): a gear of attack damage every 5 s at full charge.** `content/perks/overdrive`
{`every` 5.0, `step` 0.05, `max` 0.25}, special "overdrive": every `every` seconds spent at full charge (>= 0.99) is a
gear, `step` more attack damage each (a mul, its own source "Overdrive +N%"), `max / step` gears at most (5, +25%). A
hit that lands drops every gear and the clock (and half the charge, so counting waits for full again: 5 s to refill,
5 s more for the first gear); evaded and shielded hits keep them; a new run and a hero swap start with none. Five gears
on full charge: x1.6 x 1.25 = x2.0 attack damage, after 35 s untouched at full speed (Calavera at level 40 with
Crescendo full is x1.96), gone on one landed hit. Attack damage, never cooldown: see the next rule.

14.9 **A cooldown shorter than the Tommy Gun's burst cuts the burst's tail.** A new pull clears the rounds still queued
(`ProjectileEmitter._fire`, `_burst.clear()`): at level 5 with Drum Mag, his +2 and Drum Roll at full the burst is 24
rounds 50 ms apart (1.2 s) on a 1.23 s cooldown, so any cooldown cut (the Haste line, the Mirror's Tempo form, a
Berserk...) drops rounds from its end. Not new, named now; the reason Overdrive gives attack damage.

14.10 **Ram: the spikes grow 2 a level, from the perk's `from` charge.** `content/perks/ram` {`thorns_mult` 3.0, `flat`
12.0, `per_level` 2.0, `shove` 9.0, `from` 0.99}: at a charge of `from` or more, a creature that touches him is shoved
(`shove`, by its knockback share, pass 67 lane K) and takes `flat` + `per_level` x his level + `thorns_mult` x his thorns
instead of biting him (14 at level 1, 32 at level 10, 52 at level 20, 92 at level 40, plus three times any Thorns);
`thorns_mult` alone had left it the flat 12 for a hero with no thorns (nothing against stage 3). Never a boss and never
a charging creature (the counterplay, said on the card); the touch is no hit, so the charge stays. `per_level` and
`from` are read from the perk (absent: 0 and 0.99), Garry's to tune.

14.11 **Drum Roll is unchanged**: +1 round in the Tommy Gun's burst for every quarter of the charge (`momentum_rounds` 4,
+4 at full: the gauge's four notches); its card now says "every notch of his charge".

14.12 **Fadeaway, the sixth hero in play (Footwork).** `content/characters/fadeaway`: a basketball player in a purple and gold
88 jersey (Garry: "African American, somewhat reminiscent of Boondocks"), title order 6, he. His trait is one stat,
Footwork: +0.5% evade chance a level (`trait_per_level` evade add 0.005; +10% at level 20, +20% at 40), under the 90%
cap every evade roll has (Player.take_damage). His favourite is a passive, Evade, offered from level 2 when it first
comes (`favourite_passive_bonus {type level, value 2}`, Ironwood's Brawn idiom; a hero's favourite passive is offered
whatever its quest), so his hero mutation, Free Throw, sits on his start weapon (§13.8). His start weapon is his own
Basketball (`start_weapon`, `hero: fadeaway`: no other hero is offered it). He came from the Level Editor's "New from
template" (the Drifter's), so he starts with no unlock quest, `price` 0 (the purchase loop is parked: §13.1).

14.13 **The Basketball's numbers.** Damage 20, cooldown 1.4 s, one ball (amount 1, pierce 0), speed 16 m/s, range 9 m,
knockback 4, priority targeting (the strongest creature within range). Level 2: +25% damage, −10% cooldown; level 3: +1
amount (one more bounce), +20% speed; level 4: +30% damage; level 5: +1 amount, −12% cooldown (32.5 damage, 1.11 s, 3
hops). One hop at 85% within 7 m (`ricochet_any {count 1, frac 0.85, reach 7}`); the way home strikes 2 at 75%, x1.25
speed; the catch gives back 35% of the cooldown and a trip that scored adds one Heat, +5% a stack, 10 at most. Drawn as
the game's own 3D ball (`art/props/basketball.glb`, 0.22 m, its vertex colours: `basketball_visual.tscn` gives the GLB
a material that reads them, since the import leaves them off), rolling as it flies (`roll_radius` 0.22); no ball in his
hand between throws (his art: empty hands).

14.14 **Its path and evolution.** On Fire (element, fire): +4 burn a tick, +2 s of burning (over the 1.8 s default: 3.8
s), +30% spread (80%), the ball glowing red-orange with a short flame tracer. Full Court Press (volume): +2 amount (two
more bounces) and the hop looks 10 m. Rebound (motion): the way home strikes every creature on its line at full damage,
x1.6 speed. Free Throw (his hero mutation, optional, outside the path): every evaded hit throws a free ball at once, at
most one every 0.8 s. Slam Dunk, at level 5 with all three at a chest: damage 36, cooldown 1.2 s, speed 18, range 10,
knockback 6, 3 hops at 90% within 10 m, the way home strikes everything at full damage x1.6, the catch gives back 40%,
his Heat is kept for the run (`heat_keep`), and at Heat 10 every catch dunks: 150% of the damage to everything within
3.5 m, thrown out by 12. The path it keeps folds under it (Full Court Press's +2: 5 hops) and its own gold tint has the
last word over On Fire's red (`final`).

14.15 **The basketball's amount counts bounces.** A weapon with `params.amount_mode` "bounces" (the basketball, Slam
Dunk) throws one ball a throw whatever its amount; `ricochet_any.count` plus every amount past the first are the hops
it makes (ProjectileEmitter._throw_ball seeds them into the shot), so levels 3 and 5, Multishot, Full Court Press and
Buzzer Beater (any +amount) each send the ball on to one more creature, never a second ball. The card says "it bounces
to N more enemies within R m", a level's change row "Bounces 1 → 2", the Build tab's amount row "bounces N" and its
ricochet row "each bounce 85%".

14.16 **A hop takes the nearest creature the ball has not touched within `ricochet_any.reach`** (absent: 7 m, the Pea
Cannon's and the Golden Revolver's RICOCHET_REACH; the basketball 7, Full Court Press and Slam Dunk 10), for `frac` of
the throw's damage (85%; Slam Dunk 90%), every hop from the throw's own damage, never compounding. A ball never hops on
its way home.

14.17 **The ball always comes back (`return_on_hit`).** When its pierce is spent on a creature and it has no hop left,
or nobody stands within reach, it turns for home there instead of ending; a hop whose creature died in the air flies
out its short life (the hop's distance over its speed + 0.3 s, 0.4 s at least) and turns where it got to; a throw that
meets nobody flies its range and turns (the boomerang's turn). It comes home at `back_speed_mult` of its launch speed
(1.25; Rebound and Slam Dunk 1.6) steered at him, and is caught within 0.9 m of him. A way home has 6 s (it always
reaches him first): no ball is lost.

14.18 **The way home strikes `return_pierce` creatures at `return_damage_mult` of the throw** (the basketball 2 at 75%;
Rebound and Slam Dunk 80 at 100%, i.e. everything on its line), then flies on through the rest to his hand touching
nothing. A returning weapon without `return_on_hit` keeps the old rule: 80 touches home when it has no `return_pierce`
(the Tumbleweed's Boomerang, the Dust Devil), and it ends when they are spent.

14.19 **The rebound.** When the ball turns at the creature it just struck (no hop left, or nobody within reach), that
creature is struck once more as the ball leaves (the next physics tick, wherever the step home took the ball), at the
way home's damage, if it still stands; it is one of the way home's touches. A lone target takes the throw and the
rebound, 20 + 15 at level 1 (with Rebound two full touches). A turn at the range's end or after a lost hop has no
rebound. Why a rule and not chance: the touch test is centre to centre, so the ball usually stepped clear of the
creature it turned at and the double touch the design counts on came only sometimes (ProjectileManager marks the
creature, index and spawn serial, at the turn).

14.20 **The catch gives back `catch.refund` of the cooldown** (35%; Slam Dunk 40%): that share of the weapon's cooldown
as the sheet has it comes off what is left of the cooldown running, never below none left. Every caught ball counts (a
free throw, a ball that hit nothing). A ball with a second pass is caught at the end of its second trip, never at the
relaunch.

14.21 **Heat.** Fadeaway's Heat (Run.heat) rises by 1 for every caught ball whose trip struck at least one creature (the
throw, its hops, the way home and the rebound all count), up to `catch.heat_max` (10). Each Heat is `catch.heat_per`
more damage on the throw (5%, +50% at 10; the hops and the way home are shares of the throw, so they warm with it), and
the ball leaves glowing Heat / heat_max. A hit that reaches his health drops Heat to 0; an evade, a hit his shield
takes or immunity keep it; Slam Dunk's `heat_keep` keeps it through anything. Heat is 0 at the start of every run (and
after the arena's hero swap); only a weapon with `catch` raises or cools it. The Build tab's estimate uses the Heat he
has at that moment.

14.22 **Free Throw: a hit he evades throws a ball at once** (`free_throw {every, damage_mult}`, the hero mutation),
outside the cooldown, which runs on untouched; the ball is the throw's damage x `damage_mult` (1) with his Heat on it,
drawn white. Then no other for `every` seconds (0.8), counted from a ball that went: with nobody within range no ball
goes and no gap starts.

14.23 **Slam Dunk's dunk** (`catch.slam {at_heat, radius, damage_frac, knockback}`): at Heat `at_heat` (10, full) or
more every catch, scored or not, is a dunk: the weapon's damage x `damage_frac` (36 x 1.5 = 54; Heat does not multiply
it) to everything within `radius` (3.5 m) of him, thrown out by `knockback` (12), with a ring on the sand and a shake.
With heat_keep his Heat never falls, so once it is full every catch dunks.

14.24 **The estimate of a bounce weapon** (WeaponInstance._ball_hits, the Build tab's dps and the recorder's): a throw is
1 + (count + amount − 1) x frac + min(return_pierce, 2) x return_damage_mult throws' worth (two touches home at most: a
crowd seldom lines up behind a ball; the rebound is one of them), times 1 + Heat x heat_per, over the cooldown as the
sheet says it (the catch's refund is left out). The basketball at level 1: 67 a throw, 48 dps at no Heat; level 5 148.

14.25 **Timeout: a pickup beside him on a clock, one at a time.** The perk (`special` "timeout", `params {every 20,
first 10, side 3, pickup "timeout"}`) puts the Timeout pickup down `side` metres to his left or right, square to the way
he faces (ahead he would take it by accident while running, behind lies the crowd chasing him), on the side with fewer
creatures within 2.5 m of the spot (a toss when even), kept inside the wall, on the ground. The first lands `first`
seconds after the perk is held, then `every` seconds after the last one was taken or faded: one lies at a time and the
clock waits while it does, so it can be kept for the Elite or the boss. It lies 30 s (`lifetime`; the last 4 s blink).
The drop is quiet (the pickup's `quiet`: no chest fanfare), a faint purple ring where it lands. The clock runs on game
time: not while paused, not while he is down (Game._tick_perks).

14.26 **The leap (pickup effect "leap").** Stepping on a Timeout throws him clear: towards the emptiest of 12 ways
(`directions`; Thruster Burst's scan: the way whose point 5 m out has the fewest creatures within 2.5 m), and of
equally empty ways the one most away from the creatures within `slow_radius` of him, with none there the way he faces
(Thruster Burst keeps the first of equal ways); Thruster Burst's push 28 and lift 5 (his own move: the Invincibility
bubble does not stop it, a knock-immune Shield neither); untouchable 0.8 s (`invuln`, the longer of it and what he
had); the creatures within 3.5 m of where he stood move 50% slower for 2 s (`slow`, `slow_seconds`, `slow_radius`; a
hero's perk, so Ducktape does not stretch it), tinted Curare's dark green meanwhile. A whistle (`pk_timeout`) and the
toast TIMEOUT. It counts as a power-up taken (not `small`: the pickups quest counter).

14.27 **No map rolls the Timeout.** A pickup drops from kills only when the map's `pickups.roster` names it; the Timeout
is in none (its `weight` 0 is the cake slice's and the coin bag's convention): only the perk, or the arena's DROPS tab,
puts one down.

14.28 **Periodic buffs: Buzzer Beater.** A perk whose `special` is "periodic_buff" runs its own clock: `first` seconds
after it is held, then every `every`, its `buff` effects (target player) for `seconds` x buff_duration, as a timed buff
under the perk's name (the pause sheet's "Buzzer Beater"); it ends without a "wore off" toast (its own toast says how
long: "BUZZER BEATER: 5 s"), with the buzzer (`ui_buzzer`) and a gold flash. Buzzer Beater: 12 s, then every 24 s (the
shot clock), 5 s of cooldown −35% and +2 amount on every weapon (the ball: two more bounces). Several such perks each
keep their own clock; any later "every N s, this buff" perk is content only.

14.29 **The arena's hero swap starts his clocks over.** Swapping heroes in the arena zeroes Heat and the Timeout's and
the periodic buffs' clocks (Game.arena_swap_hero), as it does Buck's momentum and Calavera's Crescendo; a perk handed
back through ITEMS starts at its `first` again.

### Not balance (named so they are not surprises)

14.30 **The 3D weapons are graded darker and richer under the map's light.** Garry: the 3D weapons "get lost in the
background". Every lit material of a weapon's visual (a shaded, opaque, untextured StandardMaterial3D: held guns,
companions, blades, hammers, turrets, the Spear's model) is drawn in a copy graded in HSV by the map's top-level
`weapon_grade` block (`WeaponBehavior.grade_materials`, run before the pass-53 glow and the merge): value x `value` (Red
Canyon 0.78), saturation x `saturation` (1.3, clamped at 1); a material that already emits has its emission graded the
same way, so the gold guns stay gold; the companion glow then emits the graded colour at the block's `glow` (0.3;
`WeaponBehavior.GLOW` 0.45 when the key is absent). Why: the Blender scripts typed sRGB numbers into linear colour (the
imports came out lighter: the Tommy's wood landed on the sand's own tone) and Red Canyon's warm sun, ambient and fog pull
every lit mesh toward the sand, while every painted sprite is unshaded and keeps its colour. One copy per material
(MeshMerge still joins the parts, the draw calls do not grow), the source resources never written; a model of several
surfaces shot through the ProjectileManager (the Spear) draws a copy of its mesh wearing the copies. Left alone: the
unshaded and see-through FX (shot cores, halos, sparks, smoke, flashes, aura rings), textured materials, ShaderMaterials
and everything built in code (the Golden Pineapple's grenade in `Lobber._use_model`, the turret's primitive fallback, the
silver rounds, the rust blades, the default shot material). A weapon's `params.grade` (a mutation's or an evolution's
`final` too) wins over the map's key by key; `{"value": 1, "saturation": 1}` leaves a weapon as its file has it; a
missing key takes `WeaponBehavior.GRADE` {0.78, 1.3}. The title's companion and the spawn beam's warm-up read the same
block. Not a Settings switch: the numbers are content (the map JSON, kept by the Level Editor's Save).

14.31 **The hero's gauge under the slots** (ui/HUD.gd, `Run.hero_gauge()` -> {label, value 0..1, notches, color} or {}):
Buck's MOMENTUM (four notches) and Fadeaway's HEAT (Run.heat over the held ball's `catch.heat_max`, a notch a point)
show as a label and a thin WBar 14 px under the slots across the slots' row; every other hero has none and the column
under the slots (power-ups, the boss's bar, the words, the toasts) sits where it did; with a gauge it hangs under it.
The fill is paper (Heat: ember) and turns gold over the last quarter; a drop (a hit that landed) shows at once with a
rock-red flash and a 0.2 s shake; a climb eases in at 0.8 a second (the charge reaches the sheet in quarter-second steps);
a gold outline rings it while Overdrive holds a gear. The words under the slots begin with the hero's: "MOMENTUM 72%",
"MOMENTUM FULL", "RAM" (while Ram is live), "OVERDRIVE +15%", "HEAT +20%" (Run.heat x the ball's `catch.heat_per`).
The dust and streak trail behind him stays the in-world sign.

14.32 **The title plaque shows Buck's level step** ("+1%" over "SPEED / LV") and his flavour line ("Slow to start.
Impossible to stop."), as for every hero with a level rule; the -15% start and the charge are in the hero sheet's rule
(the CV), the Collection and the arena's HERO note. The Level Editor's trait preview mirrors TextGen (the rule, then his
words) and neither offers "Set trait_text from the rule" nor warns about the difference for a hero with a special.

14.33 **Fadeaway's art.** FAD-B (the Level Editor's hero_pose5: five views on the Mixamo run, the back views on run_spread) is
the look in play and approved. Its back-view flinch was painted again on its own (the first faced the viewer: the
flinch prompt's "grimace" fought "seen from behind"); the new one is seen from behind with his hands on his back
(gen_art's flinch wording asks for "one hand raised towards the chest" in every view). The badge is the sly
closed-mouth half-smile (`badge.still` fadeaway_portrait_c1), the title cut-out holds the ball at his hip
(`title_pose`, `title_holds`, `title_extra_ref` tools/dl/basketball_ref.png), the item icons were painted and picked by
eye (the ball's from the 3D render). The perk Timeout and the pickup Timeout share an id across two content types (the
design's names; `stride` is the passive-and-talent precedent): the game keys each by its type, the Level Editor's create
flow would refuse the second, and both wear the same whistle icon.

## 15. Pass 68: looks, drafts and candidates (not balance: named so they are not surprises)

Garry (2026-10-12): the title cut-out and icon candidates should already know the hero, with a reference picture; a new
look must come with its icon and cut-out candidates; Duplicate must not start painting; a duplicate on another model had
come out byte-identical (MAM-C = MAM-B); the upcoming jobs belong at the top of the Jobs tab.

15.1 **A new look paints its own stills, on its own seeds.** A look job for a NEW look (a code that is not the base strip's
`variant_base` and has no strip yet: a new code, a draft, a failed job's stub) writes `stills: "<letter>"` into its recipe
(MAM-D paints `mamy_d_front`, `_back`, `_side`, `_fd`, `_bd`, `_cheer`, `_hurt_<view>`, `_dead`) and `seed_offset`
(`1 + crc32(code) % 9973`; every seed of the look moves by 104729 a step). Heroes too (`hero_pose5`); `hero_fit` never: it
walks the hero's own paintings by design. Before pass 68 a hero look read the hero's cached paintings (`<id>_<view>`), so
MAM-C repainted nothing and its Flux.2 dev setting changed nothing, and two new looks with the same words (DM-E and
DM-F) painted the same picture on the same seed.

15.2 **An existing look keeps the paintings it was made from.** A job for a look that has a strip, or for the base, writes
`stills: ""` when its recipe names none (never a letter) and no `seed_offset`, so re-running it reuses its pictures and
looks painted before pass 68 keep their seeds. The recipe records the `method` that ran.

15.3 **Re-roll does what it says** (the job form's choices, applied once at Queue):
- *repaint the stills*: a look that shares its paintings (`stills: ""`, or a slug another look names) first gets a slug
  and seed offset of its own, so the shared pictures are never touched; a look with its own slug moves its seed offset
  by one and paints its stills again (the old ones kept as `<key>_old<stamp>`). Its walks are made again from the new
  stills (a painter only paints stills: kept clips would be the old walks).
- *new seeds*: as above, and new clip seeds too.
- *keep the stills, redo the clips*: the clips walked again on the next clip seed.
- *redo one view*: creature_ctl's view candidates.
Refused with a reason: stills or seeds on hero_fit (its stills are every look's) and creature_ctl (from the picked side),
clips on creature_proc (no clips), any re-roll of a front from a picture or a recolour. When the Model settings differ from
the painter the look was painted with, the form selects "repaint the stills" and says why. A job card's Re-roll… on a look
that shares its paintings forks them the same way. A forced repaint is spent once the job is done: a later plain
Re-queue reuses the new stills.

15.4 **The painter is honest.** When a look lands, its stills older than the attempt's start were reused from the cache:
the recipe's `painter` then says `stills: "reused"` (or `"N of M painted"`) with the keys, and the card says the painter
changed nothing. The run's marker names the model that really painted.

15.5 **Duplicate makes a draft.** Duplicate… writes a new look entry with the source's recipe (the method recorded, the
painter kept, its own stills and seed offset dropped, `from` = the source's code) and starts nothing. The draft shows a
purple *draft* chip and **Generate…**; its recipe is edited in the typed recipe editor first. Generate… saves an unsaved
document first and opens the job form for that code as a new look, with "reuse <source>'s paintings" (only the walks are
made again).

15.6 **A new look comes with at least 3 icon candidates, and a hero's with at least 3 title cut-out candidates.** The job
form of a new look (+ New look…, + Generate art…, a draft's Generate…) asks for both, 3 by default and at least 3 (Queue
refuses fewer); a creature's icon candidates are icon_cands, a hero's are round badge candidates (hero_badge), the cut-out
is hero_title. They are queued after the look's own job, on its Model settings, with its front still as their reference
(a candidate job waits in the queue while the look that paints its picture has not finished). On Flux.2 dev the six
candidates add about half an hour after a hero look; on Klein about two minutes. A recolour and a front from a picture
need none; on a re-roll the counts are optional.

15.7 **Candidate jobs know the hero and see a picture.** A badge, title cut-out or icon job's empty words are filled from
the asset at Queue, and the form shows them before Queue, each tagged with where it came from: the *character* (the
look's or the asset's `appearance` when set, else its `art_prompt` with the trailing pose clause cut: "standing straight,
arms relaxed at her sides" contradicts a badge's action), the *action* (a badge: `portrait_prompt`), the *pose*, *holds*
and *camera* (a cut-out: `title_*`, the tool's tables, else "standing confidently in a heroic pose, full body"), and the
*reference picture* (the look's own front still; any picture may replace it: Change… or Upload…). The words put the
character right after "this exact character". A hero's icon is its round badge: icon candidates are refused for a hero
(their pick had written a square icon over the badge). Before pass 68 an icon job sent only the typed words and no
picture, so "mamy icon, she is miming…" painted four women in aprons.

15.8 **Candidates are the job's own.** Badge candidates are kept per job (`<id>_portrait_<tag>_c<k>`), title cut-outs too
(`title_heroes/<id>[_<letter>]_<tag>_<n>.png`), icon candidates in the job's folder; a re-run of a candidate job paints
new ones on new seeds (it used to hand back the old pictures), and a job's Install installs its own pick.

15.9 **A pick for a look lands in that look.** A badge or icon picked for a look writes `<id>_icon_<letter>.png` and
`variants[CODE].icon`, marked `icon_picked: true` so the look's later runs keep it (gen_art paints a creature look's
icon from its front still on every run); a cut-out picked for a look writes `art/ui/wanted/hero_<id>_<letter>.png` and
`variants[CODE].title`; the hero's own badge and cut-out are left alone. The base strip's code counts as the hero's (or
creature's) own: its pick writes `<id>_icon.png` and the top-level badge, or `hero_<id>.png`. A pick never marks the look
NEW and never touches its strip; the replaced cut-out is kept in tools/dl/backup/title/. gen_art, gen_ctl and a recolour
all leave a picked look icon in place.

15.10 **A hero is drawn in the look he is played in.** The played look is the one kept for him (the arena's USE FROM NOW
ON), else the JSON's `variant`, else the base. His round badge follows it on the hero sheet, the results, the unlock
banner, the arena's tiles and the Hidden list (it showed the JSON's look before); the painted title shows the played
look's own cut-out (`variants[CODE].title`), else `hero_<id>.png`, never another look's. The live title (the default
menu) draws the played look's strip and has no cut-out at all, so a look's cut-out shows only with the painted title
style.

15.11 **The Jobs tab lists what comes next first**: Up next, Waiting for a pick, Running, Finished. Up next is grouped by
lane (comfy, godot, local) in the order each lane will take them, numbered per lane; ▲ ▼ move a job one place within its
group. A candidate job waiting for its look's front still is shown after the others of its lane, "waiting for <code>'s
front", and does not move.

15.12 **The job form is honest about pictures.** The 2D and 3D reference rows show only for the methods that read them;
a creature look painted from words says to start from a picture with "A front from a picture" first. (A reference typed
into a look job before pass 68 was silently ignored.)

15.13 **A removed look's code is not handed out again while its pictures are cached.** The next free code skips a code
whose stills (`ai_raw_anime/<id>_<letter>_*`, `<id>_<codepart>_*`) or clips (`ai_anim/<id>_<codepart>_*`) are still on
disk: the cache is keyed by name, so a new look on DM-F's code would have painted nothing and come back as the removed
DM-F.

15.14 **A candidate job's base look uses its own front.** For the base strip, the default reference is the base look's
own front still (its recipe's keys: BB-C's `bull_beetle_bbc_front`, WW-A's `werewolf_wwa_front`), else `<id>_front`.

15.15 **An edited job keeps what was applied.** Saving an edited job does not apply its re-roll a second time; a cleared
candidate field is filled again from the defaults; a re-queue after a stopped attempt repaints only the stills that
attempt did not reach.

## 16. Pass 69 (v0.55): new weapons, passives, heroes to buy, stronger specials

Garry's request (2026-10-12, tools/dl/p69/REQUEST.md, "Megabonk is a big inspiration"). Each lane's rules as it
wrote them; the numbers are data unless a rule says code.

### 16.BB The basketball: Heat on the ball, Alley-Oop, Slam Dunk, no hero gauge

16.BB1 **No hero gauge.** The HUD draws no gauge for any hero (pass 67's MOMENTUM / HEAT bar under the slots is gone) and
the words under the slots no longer carry MOMENTUM, RAM, OVERDRIVE or HEAT (Garry: "No UI indicators of any kind
please"; "This indicator should only be present on the 3d object of the ball itself"). Momentum shows on the hero
(Player.gd's VFX, unchanged), Heat on the ball (16.BB2). `Run.hero_gauge()` is gone; `Run.catch_params()` stays.

16.BB2 **Heat shows on the ball** (`params.heat_look`, the basketball and Slam Dunk): every ball in flight follows Run.heat
/ catch.heat_max (10) live, frame by frame. Its seams glow like cracks of lava: their emission moves from their own
toward `color` (#FF5A10) and on toward `hot` (#FFC060) near the top, the energy up to `seam_glow_max` 1.6 (Slam Dunk
2.2); the body only warms toward `color` up to `glow_max` 0.45, so it still reads as an orange basketball (Slam Dunk 0
and Alley-Oop's `heat_look.surfaces` "seams": the black and the dark blue bodies never glow). From `trail_from` (10% =
1 Heat) an orange bead trail, denser (a bead every 0.05 s down to 0.02 s), bigger (0.45 to 1.0) and longer-lived (0.15
to 0.35 s) as Heat climbs; from `flame_from` (40% = 4 Heat) flame tongues lick behind it (40% to 90% of the beads); from
`halo_from` (90% = 9 Heat) a soft orange halo 1.8x the ball's radius in two shells (0.22 opacity at the top; Slam Dunk
1.9x, 0.25). At full Heat the glow and the halo beat at `pulse_hz` 3 Hz by `pulse` 35% either way (Slam Dunk 40%). A
drop in Heat (a hit on his health without heat_keep) puts the balls in flight out at once with a puff of steam off each.
Purely a look: Heat's damage (+5% a point) is unchanged. Tuned by eye on captures (pass 69 lane BB): a first cut with
the whole ball glowing at 2.2 washed it to a pale disc and a pale halo hid it; the glow moved into the seams.

16.BB3 **Full Court Press is hidden** (`"hidden": true`, kept in its folder): never offered, no longer part of the
basketball's path; a run's evolution now needs On Fire, Alley-Oop and Rebound. Slam Dunk loses the +2 bounces Full
Court Press folded in (5 hops became 3: its own ricochet_any count 3 at 90% within 10 m), traded for the launch and the
amplified combo below. Not retuned (Garry asked for amplification, not for the old hops).

16.BB4 **Alley-Oop** (mutation, volume, rare, `params.launch {chance 0.15, height 3.5, air_time 0.9,
fall_damage_frac 1.0}`): every hit of the ball a creature lives through (the throw, each hop, the way home's touches,
the rebound, a free throw) rolls 15%. A plain creature flies straight up 3.5 m (up in the first 30% of 0.9 s, easing
out; a hang to 50% with a 4% float; the drop easing in), cannot move, bite or attack while up (its wind-up, charge or
scripted attack is dropped as a stun drops it; its burns and poisons keep ticking), and lands with a spray of sand and a thud (`w_grav_land`)
taking 1.0 x that hit's damage through the normal damage path (so it scales with every damage increase, Heat included,
may crit, counts for kills and XP). The boss, an Elite or an elite-modded creature that rolls it takes the fall's
damage at once with a sand puff, no flight. A creature already in the air (a launch, a bounce, a tornado), held by the
Gravity Gun, buried, rising out of the sand, roping the hero or still in the spawn beam is not thrown: its roll does
nothing. A creature killed up there falls to the sand (22 m/s²) while its death plays. The ball turns dark blue
(`tint.body` #0A4FA8 out of the sky's ambient light (`tint.ambient` false; the first #1B2E7A rendered violet on the sand, Slam Dunk's black brown), a faint #1A5CFF glow at 0.28, near-black seams #05081A; its Heat only in the seams). With On
Fire too, the later-taken mutation's glow colour wins (the body stays blue). Its landing is a spray of sand (Fx.sand,
0.55-1.0 by size), not the burrow's pop_dust: a quarter of the hits throwing creatures up buried the crowd in dust.

16.BB5 **Slam Dunk** keeps the path and amplifies it (`params.final`, the evolution's last word, as the Blunderbuss and
the Golden Revolver do): Rebound's way home strikes everything on it (return_pierce 80) at x1.2 the throw (Rebound
x1.0), x1.6 speed; On Fire's burn x1.5 (a level-1 effect `fire_damage mul +0.5`: 4 -> 6 a tick, its duration and
spread as On Fire has them); Alley-Oop's launch at 25% with the fall at x1.5 the hit (height 3.5 m, 0.9 s kept); its own
dunk at full Heat and Heat kept for the run as before. The ball is black (`tint.body` #141414, a faint #1A0700 glow at
0.2, roughness 0.45) with ember seams (#2A0A02 glowing #FF5A14 at 1.3); its Heat glows in the seams only.

16.BB6 **The estimate counts the falls.** WeaponInstance._ball_hits multiplies a throw's touches by 1 + launch.chance x
fall_damage_frac (Alley-Oop x1.15, Slam Dunk x1.375), big game's instant falls and the plain creatures' landings alike.
The words (TextGen.launch_words, in the ball's description): "Each hit has a N% chance to throw the enemy into the air:
it can't attack up there and takes the hit again (or M% of the hit) when it lands."

### 16.SALT The Salt

## The Salt (`content/weapons/salt`, behaviour SaltShaker)

- Uncommon, weight 8, in the pool for every hero (not hero-only), tags `salt`, `ground`.
- Base: damage 6 a tick, cooldown 1.6 s, amount 1 patch a pour, area 1.0, duration 4 s. Levels: 2 = damage +25%, area
  +10%; 3 = +1 patch; 4 = cooldown −15%, damage +25%; 5 = +1 patch, area +15%. At level 5: 9.4 a tick, 1.36 s, 3 patches,
  radius 1.77 m, 4 s.
- A patch: radius `salt.radius` 1.4 m x area x `salt.area_mult`; lies duration x `salt.duration_mult` seconds; fades in
  over 0.25 s and out over its last 0.6 s (it works the whole time).
- **The pour**: every cooldown, `amount` patches back along the hero's way: the first 0.4 m behind his heels, each next
  one `salt.spacing` 1.2 m further back along the path he walked; the ones his way is too short for (he stood still or
  just turned up) go round his feet on a sunflower spiral (0.96 m x sqrt(k) out), the first on his feet.
- **The bite** (new rule): every `salt.tick` 0.5 s, every creature standing in any working patch takes ONE hit of damage
  x `salt.damage_mult` through the weapon's own path (crits, Cold Snap, Vulture, kill credit to the Salt). Overlapping
  patches never hit a creature twice in a tick, so a thicker trail is a longer and wider trail, not a stronger one.
- **The cap** (new rule): at most `salt.max_patches` 40 lie at once; one more sends the oldest still whole into its 0.6 s
  fade, and a fading-for-the-cap patch hurts nothing and lucks nothing.
- The estimate (pause screen dps): one creature in every patch lying (amount x lasts / cooldown of them, 40 at most),
  hit every tick; Hiwa Kai's crunch adds one hit of mult x a tick per patch life.

## The path

- **Sea Salt** (element): pink (#F4A3C4) patches and shaker contents, patches last x1.75, a tick x0.95.
- **Salt Spill** (volume): patches x1.6 wider (radius).
- **Thing About Luck** (motion, new rule): a creature killed while it stands in a working Salt patch (where it fell is
  inside one) rolls the timeline's power-up drop with the per-kill chance x3 (`salt.luck_mult`). Any weapon's kill counts,
  not only the Salt's. Bosses and Elites roll as their roster says (no other change); the creature's own `drops.pickup`
  and the chests are untouched. Code: `Game._salt_luck_at` -> `WaveDirector.drop_pickup_from(..., luck)`.
- **Salt Flats** (Jeżyk's hero mutation, new rule): when the hero walks INTO a patch he was outside of on the last frame
  (and moved that frame), his momentum (the speed-up) goes to full at once (`Player.max_momentum`: the sheet follows at
  once; it gives no Overdrive gears, those still come from time at full). A patch laid round his feet counts only once he
  has walked out of it and back in; staying inside never charges again; a hit still knocks the charge down as before.
- **Hiwa Kai** (evolution, needs all three + level 5): base damage 13, cooldown 1.2 s, amount 3, area 1.0, duration 4 s;
  its `final` amplifies the path: patches last x2 (Sea Salt's x1.75), x1.8 wider (Salt Spill's x1.6: radius 2.52 m), the
  luck x4 (Thing About Luck's x3); damage_mult 1 (Sea Salt's x0.95 penalty dropped). Black salt (#161616) with 7 hard black
  crystals on every patch. Its own feature (new rule): **the crystals bite**: a creature found in the salt at a tick that
  was not in it at the tick before takes one extra hit of x2 a tick's damage (the crunch), and every creature standing in
  the salt moves 30% slower (refreshed each tick for tick + 0.15 s, not stretched by Ducktape; a boss is slowed like any
  creature here).

## The shaker

- Floats 1.2 m from the hero at 1.25 m, circles him at 0.55 rad/s, bobs 0.08 m; tips over away from him and shakes for
  0.45 s at every pour, grains falling from its cap. Model `art/props/salt_shaker.glb` at scale 2 (about 0.6 m tall).

### 16.FRIS The Frisbee

## The Frisbee (`content/weapons/frisbee`, behaviour `Frisbee`)

- Common, weight 9, in the pool for every hero (no `hero`); Jeżyk starts with it (lane HERO).
- Base: damage 14, cooldown 1.2 s, amount 1, speed 13 m/s, range 12 m, knockback 1.5; `pierce 999` is only a marker
  (the behaviour cuts through everything and ignores pierce). Levels: 2 = +25% damage, -10% cooldown; 3 = +1 frisbee;
  4 = +30% damage, +2 m range; 5 = +1 frisbee, -12% cooldown.
- Aim: the nearest creature within range (on the screen), else where he faces; it throws even with nobody there.
- The arc: each disc leaves its aim line at `bend_deg` 25 + `bend_per_extra` 12 per extra frisbee (amount 3 = 49) to a
  side picked at random per disc, then turns back at a steady rate so it crosses the line at the target's distance
  (clamped to 3 m..range; the whole turn capped at the bend + 60 degrees, so a close target gets a gentler hook that
  passes near it). A volley's aim lines fan 16 degrees apart.
- It flies its whole range (12 m: about 0.9 s), then glides 0.45 s (slowing, sinking to the sand, fading) and hits
  nothing while it glides.
- Hits: every creature within 0.55 m x size_mult x area of the disc (plus the creature's radius), once a flight;
  the n-th creature after the first takes 0.85^n of the damage, never under 0.25 (the floor from the 10th creature
  on). Knockback along its flight. Poison and fire as the sheet says.
- The disc: radius 0.36 m x size_mult x area (0.72 m across; Carry and the saucer 1.08 m). The weapon's `area` (Reach and the like) makes it bigger and cut wider.
- Estimate (pause screen dps): a disc counted as cutting 3 creatures at the drop-off (1 + 0.85 + 0.72 = 2.57).

## Carry (`carry`, volume)

- The first creature a disc hits (never later ones) rides it 10% of the time, to the end of the flight, and is set down
  where the disc comes down (end of the glide). One a disc. It is held by the Gravity Gun's grip, so never a boss, an
  Elite archetype, an elite-modded creature or one whose `can_be_grabbed` is false (the rocketeer, the harpooner), and
  nothing hits it while it rides (it takes the first hit, then no hits from anything until set down). It still cuts
  everything else on the way. The disc is x1.5 larger (and cuts x1.5 wider).
- Card text exactly: "It has a 10% chance to carry the enemy away."

## Poison Razors (`poison_razors`, element poison)

- poison_damage +4, poison_stacks +1, poison_duration +4 s (the game's poison: a tick every 2 s). Hot-pink disc with
  eight steel razor blades round the rim.

## Trick Shot (`frisbee_trick_shot`, motion; id note: `trick_shot` is the Revolver's)

- `proc_mult` 1.25 for this weapon only: life steal (x1.25 of what its damage steals; the per-second cap unchanged),
  crit chance x1.25, Cold Snap's freeze chance x1.25, Vulture's heal-on-crit chance x1.25, and a `stun` the weapon may
  carry x1.25 (Run.trick_proc_mult, read in Run.add_damage and EnemyManager.damage). No look change.
- **Not satisfiable as asked**: nothing in the game gives the Frisbee a stun today (the only stun is the Spear's
  Stunning Thrust), so Trick Shot's stun share does nothing until a stun reaches the frisbee (`params.stun {chance,
  seconds}` on the weapon, a mutation or the Level Editor). The card still names stun, as Garry asked.

## The Flying Saucer (`flying_saucer`, evolution)

- Base: damage 30, cooldown 1.0, amount 3, speed 15, range 15, knockback 2; poison_damage 2 and poison_duration 2 on
  top of the razors' 4 and 4 = x1.5.
- Amplified path: carry chance 0.2 and the ride ends with a drop hit of 1.0 x the disc's damage; proc_mult 1.5;
  poison x1.5; the saucer disc (chrome and pink, glowing razors, a glass bubble, a faint green haze) x1.5 larger.
- Its own feature: once a flight, at a random point between 30% and 70% of its range, the disc flies one full circle
  of 1.3 m (the way it is already turning), then goes on along its arc. The loop does not count against the range.

### 16.PAS Five new passive items and the Magnet

Every number below is data (the item's JSON `levels`) unless marked **code** (a named constant).

## Counterpunch (uncommon, weight 8, 5 levels, `content/passives/counterpunch`)
- An **evade** (Player.take_damage's evade branch) arms the next attack and starts a quiet timed boost (no "wore off"
  toast). Nothing happens on a shielded, immune or landed hit.
- **The next attack** = the first weapon to *fire* after the evade (WeaponBehavior._process: a `_fire()` that returned
  true). Every hit that weapon lands deals x(1 + `counter_damage`) = **x2** until that weapon fires again or
  **1.0 s** of the buffs' clock passes (**code** `Run.COUNTER_HIT_WINDOW`), whichever is first. Applied in
  EnemyManager.damage to weapon hits only (never a poison or burn tick), before the crit roll (so a crit on it is x2
  x crit damage). Another evade while armed only refreshes; the arm is spent by the next fire.
- **The boost**: `counter_haste` weapon speed (the `haste` stat, mul: cooldowns divided) and `counter_speed` move speed
  (mul) for `counter_seconds`. Level 1: +20% / +15% / 2.0 s; each level +5% / +3% / +0.25 s; level 5: +40% / +27% /
  3.0 s. Another evade starts the clock again (at the new numbers after a level). Solenne's `buff_duration` stretches
  it (it goes through Run.add_timed_effects like every buff).
- An orange burst and a short "snap" (`it_counterpunch`) on the evade that armed it.

## Heavyweight (rare, weight 7, 5 levels)
- Attack damage (might, mul, its own source "Heavyweight +N%") = `heavyweight` x **whole** tens of max HP
  (floor(max HP / 10)). Level 1: +1% per 10; +0.25% a level; level 5: +2% per 10. At 100 max HP: +10%..+20%; at 250:
  +25%..+50%.
- Recomputed whenever the passives are folded (a level, an item, any sheet rebuild), so it follows max HP from Vigour,
  Hot Springs, Astro's levels, the Stranger's cut. Timed buffs that would change max HP mid-buff do not exist today.

## Snake Oil (epic, weight 5, 3 levels)
- Cap = `overheal` x max HP: **20% / 30% / 40%**.
- Any heal through Player.heal (pickups, Cake, Heart, the level-up heal, life steal, Vulture, the Healing Well) first
  fills the bar; what is left goes into the overheal up to the cap. **Regen** (and Siesta, Deep Breath) stops at full
  and never fills it.
- A hit (after damage reduction) takes the overheal first, then health; the Energy Shield still takes whole hits before
  either. The overheal never decays. It is clamped to the cap whenever the sheet changes (losing a level of max HP,
  the item gone).
- The HUD's HP bar runs on to the right past full by overheal / max HP of its width, drawn pink (#E86AA8) after a 1 px
  ink divider.
- Hot Springs counts overheal healed as healed.

## Hot Springs (epic, weight 5, 3 levels)
- +20 / +30 / +40 max HP and +0.5 / +0.8 / +1.2 regen a second (totals).
- Every heal (regen ticks included; overheal counts) is summed; a pulse goes out when the sum is above 0 and the last
  pulse was at least **0.5 s** ago (**code** `Player.HEAL_PULSE_GAP`): damage = `heal_pulse` (4) + **2** x HP healed
  since the last pulse (**code** `HEAL_PULSE_PER_HP`), at most **40** (**code** `HEAL_PULSE_CAP`), to every creature
  within **3 m** (**code** `HEAL_PULSE_RADIUS`). Not scaled by attack damage (a flat number, like Thorns). Damage source
  `hot_springs` (Results lists it with the item's icon). It is a non-weapon source but goes through EnemyManager.damage
  with an id, so it can crit, freeze (Cold Snap) and execute like Powder Keg's blast.
- Look: a green-gold ring racing out over the 3 m (brighter for a bigger heal); a soft chime (`it_heal_pulse`) only for a
  heal of 3 HP or more, so regen's steady pulses stay quiet.
- With regen alone at level 3: a pulse every 0.5 s of 4 + 2 x 0.6 = 5.2 damage (about 10 a second round him).
- A known synergy (named so it is not a surprise): the pulse's damage feeds life steal like every damage he deals, and
  life steal's heal sends the next pulse, so with Thirst / Bloodthirst it keeps going while creatures stand in it, bounded
  by life steal's cap a second (`lifesteal_cap`, 4% of max HP) and the 0.5 s gap: about 4 + 2 x 2.9 = 10 damage every
  0.5 s at 145 max HP. The probe (arena, a crowd held round him at 40x HP) saw ~90 pulses a minute.

## Last Stand (epic, weight 5, 3 levels)
- Trigger: a hit that reaches his health (after the shield and the overheal) and leaves him alive under **30%** of max HP
  (**code** `Run.LAST_STAND_BELOW`), while it is not already running and off cooldown. Already being under 30% counts
  (the next hit sets it off once the cooldown is over).
- Effect: the engine clock at **0.5x** (**code** `LAST_STAND_SCALE`: everything, the hero too, bullet time) for **2.0 s
  of real time** (**code** `LAST_STAND_SECONDS`; 1 s of game time; real time = each frame's delta without the engine's
  scale, a stall over 0.5 s counted as 0.5 s), and attack damage x(1 + `last_stand`) =
  **x2 / x2.5 / x3** (might mul, source "Last Stand", kept through rebuilds while it runs).
- Cooldown **20 s** of the buffs' clock (stage clock + held time) from the trigger (**code** `LAST_STAND_COOLDOWN`),
  never shown or named anywhere.
- The clock is always given back: a paused run (card screen, pause board, chest, Down!, any modal) runs at 1x and the
  window's seconds wait; the hero falling, the run ending or the effect node leaving the tree end it at once (time 1x,
  the damage off). It restores the clock it found (the arena's game speed), never a hit-stop's 0.08. The hit-stop on the
  triggering hit and on hits during the window is skipped (its own `time_scale >= 0.999` guard).
- Look (not High Noon's gold flash): the world drained to a cold blue-grey (88% graded), a red rim round the screen's
  edges swelling on a heartbeat (1.6 beats a second, lub-dub), on its own canvas layer under the HUD; a toast
  "LAST STAND"; one low sound (`it_last_stand`: a sinking whoom under two heartbeats). Fades in 0.12 s, out 0.35 s.

## Magnet (reworked: common -> **epic**, weight 10 -> 6, 5 levels)
- No `magnet` (pickup radius) stat any more: the walk-up pickup radius is the hero's own (1.5 m base, talents, perks).
- Every few seconds at random, every **EXP gem** (never a coin, chest, vacuum or power-up) lying, landing or hopping
  within `xp_pull_radius` comes to the hero on the magnet arc (the big pull's look: thrown up charged, diving in).
  Radius 5 / 6 / 7 / 7.75 / 8.5 m, never over **8.5 m** (**code** `PickupManager.XP_PULL_MAX_R`, "a large explosion").
- The wait between pulls: random between 3 and 8 s (**code** `XP_PULL_EVERY`), divided by 1 + `xp_pull_rate` (0 at
  level 1, +0.25 a level, 1.0 at level 5: 1.5-4 s). Rolled on the pickups' own dice (the run's random sequence is
  untouched). The texts never name the wait: `xp_pull_rate` is a "word" stat ("pulls more often").
- A faint purple ring at the reach and a short "zwoop" (`it_xp_pull`) when a pull took at least one gem; nothing when
  none lay in reach. No pulls while the hero is down.
- Pairs with nothing new (its `pairs_with: turret_buddy` stays informational).

## TextGen
- New stat kind **"word"**: the stat is said by its name only ("pulls more often"), never with a number, and left out of
  totals and change rows (_sum_effects). `describe_effects` skips an empty part.

### 16.EN Special enemies, the special Goblin, the spawn beam

## Coloured (variance) specials
- **Chance**: every creature's `variance.special_chance` is a third of what it was, to 4 decimals (Garry: "about 3 times
  more rare"): skeleton, goblin, red goblin 0.12 -> 0.04; slime, runts, imp, jackalope, lizard, knight, cactus, hobgoblin,
  tumbleweed minion, fire ant 0.1 -> 0.0333; beetle, mummy, hellhound, toad, crab 0.08 -> 0.0267; armadillo 0.06 -> 0.02;
  dwarf 0.05 -> 0.0167. Still x (1 + difficulty) with Hot Sauce, still only after the map's `colour_after_kills`.
- **Numbers** (Garry: "1.25 times bigger ... HP x10 ... ATK x2"): `special.size` 1.25, `special.hp` 10.0,
  `special.damage` 2.0 on every creature with a chance (and the shaman's chance-0 block); `xp` kept (3 on all).
  INTERFACES read "1.25 times bigger" as 1.25 x a plain one, like HP x10 and ATK x2 are x a plain one: before pass 69
  the specials were 1.25-1.6 x, so most are a little SMALLER than they were (e.g. the goblin 1.5 -> 1.25) though far
  tougher. If Garry meant 1.25 x the old special, Size x in the editor's Special block is the knob (per creature).
- **Exactly x1.25** (new rule): a special's size is its size factor x the creature's own size; the plain ones' size
  spread (`variance.size`, 0.2 on most: 0.8-1.2) no longer applies to it, so a special is never smaller than a big
  plain one (with the spread a 1.25 special could have come out at 1.0).
- A size-range row's special still stops at the range's top (the pass-58 rule, unchanged): there it may be barely bigger.
- **Fallbacks** (new rule): a special number the creature's `variance.special` does not name takes the map's
  `timeline_data.special_defaults`, else `EnemyDef.SPECIAL_DEFAULTS` = {size 1.25, hp 10, damage 2, xp 2,
  tint_strength 0.6, glow 0.6} (the code defaults were 1.3 / 1.6 / 1.2 / 2 / 0.6 before; no creature in play relied on
  them for size/hp/damage).
- **Glow** (new): `special.glow` 0..1, default 0.6 (no creature names one: the map's default or the game's 0.6 applies):
  an emissive rim round a special in its tint's hue at full brightness, 1 + 4.2 x glow screen pixels wide (3.5 px at 0.6) with a lighter core 0.6 + glow px wide next to the figure, breathing
  between 0.8 and 1 of its brightness at ~0.5 Hz, and the painted outline lit by 0.85 x glow. Off while it dies. Burn,
  poison, freeze and a weapon's held tint colour the rim while they last; the harpooner's red tether rim wins.
- **Colour**: any colour may be picked now; pass27_test's "dark and saturated" (value < 0.6, saturation > 0.4) is the
  editor's warning, no longer a test rule.

## The special Goblin moment (Red Canyon)
- One `swarm` event with `"special": true`: one `red_goblin` (look RG-B, the first row's) at **2:00** (120 s), from the
  top of the screen (`in_front`). The first roster row r1 (the red goblins) runs 0:00-2:02 and the scorpion charge comes
  at 2:03, so it closes the goblin wave. The green `goblin` is retired (pass 45), so "the regular Goblin" is the red one.
- A forced special: x10 HP, x2 ATK, x1.25 size over the row's own red goblin (the event joins row r1's fixed numbers),
  whatever its chance, before `colour_after_kills` (50 kills on Red Canyon), with no SWARM! banner; XP x3, its glow.
  Garry can move it (drag the flag), change the creature/count/pattern or untick Special in the editor, or delete it.

## The spawn beam
- The two beam quads fade in from nothing 0.15 m above the highest sand under their width (5 samples across the beam,
  2.2 m behind the hero) to whole 2.6 m higher (`Game.SPAWN_BEAM_FADE_GAP` 0.15, `SPAWN_BEAM_FADE` 2.6;
  shine_aura.gdshader `fade_y`, a smoothstep in world height). The pool of light on the sand is unchanged; the chest's
  beam has no fade (fade_y off by default).

### 16.HERO Jeżyk and May

## May (hero `may`, was `mamy`; hidden until lane UI makes her purchasable)
- Trait unchanged (Garry's): No Time, cooldown -1.5% per level.
- **Favourite: Tommy Gun**, bonus **cooldown -15%** (her thing is attack speed; Buck's old +2 rounds went with him).
  Start weapon unchanged (Garry's `big_mouth`).
- **Trigger Happy** (hero mutation on the Tommy Gun, rare, weight 8): the Tommy fires on its clock even with nobody in
  range (straight along her facing, `fire_without_target`), and its burst is **streamed**: the rounds spread evenly over
  the whole cooldown (gap = cooldown x 0.97 / rounds; `stream`), so it never stops. Effects: **damage x0.65** (the
  contract's number) and **cooldown x0.6** (two thirds more rounds a second). Why the cooldown: "shoot all the time
  without stop" with the old round rate would only add rounds into empty sand, a straight nerf after the x0.65; with
  x1.67 rounds the fight DPS is x1.08 of the plain Tommy (x0.65 x 1/0.6), a modest gain for her signature mutation,
  paid for by every round being a third weaker (worse into armoured creatures, pierce falloff the same). StatSheet
  multiplies every mul effect, so both are true factors on top of the levels and the other mutations: with Drum Mag
  (amount +6, damage x0.65) the stream is 12+ rounds per 0.84 s, each x0.42 of a plain round.
- **Inflatable May** (perk, rare, weight 6, special `decoy`): first throw **6 s** after she takes it, then every **30 s**;
  the doll lands **4-7 m** away in a random direction (inside the arena, off the rocks when it can), flies **0.6 s**;
  where it lands a faint pink circle of **6.5 m** (under half the portrait screen's width at the base zoom); for
  **2.0 s** every creature inside (Elites too; never a boss) goes for the doll instead of her, including any that walk
  into the circle meanwhile (scanned every 0.15 s); their bites on it hurt nobody; then it pops. Rules to name: a fooled
  creature never bites the hero while fooled even if it touches her on the way; scripted attacks (casters, the Hammer
  Giant's slam) still read the hero's position; a fooled shooter aims its shots at the doll.

## Jeżyk (hero `buck`)
- Name Jeżyk; momentum numbers unchanged (ramp 10 s, +80% speed, +60% damage, +20% evade, hit_loss 0.5); trait text
  unchanged (it never named the deer).
- **Start weapon: Frisbee. Favourite: Salt**, bonus **area +25%** (wider patches for Salt Flats to cross into; Astro's
  favourite bonus is +20% area, the Tommy's old +2 rounds would triple the patches per pour of a 1-patch weapon).
- Hero mutation **Salt Flats** (lane SALT's); **Drum Roll hidden** (kept, out of play).
- Perks unchanged (Overdrive, Ram).

### 16.UI Heroes to unlock and buy, the hero drawer

## The rule
- A hero is **owned** when free (`availability` "available") or bought (`Save.heroes_owned`). Only an owned hero can
  start a run (the title's PLAY reads LOCKED and refuses; a save whose last hero is not owned opens on the Drifter).
- `availability` "purchase": **locked** until his unlock quest `unlock_<id>` is done (no quest: on sale at once), then
  **on sale** for `price` gold until bought. Buying spends the price once (sink "hero"); nothing refunds it.
- `availability` "available" with an unlock quest: locked until the quest is done, then owned, nothing to pay.
- `availability` "hidden": out of play. A "purchase" hero is never hidden, whatever `hidden` says.
- A save from before pass 69 owns only the free heroes (Drifter, Astro), whoever it played (Garry asked for locks).
- The quests are checked as every unlock quest is: totals at the title, single-run conditions during a run.
  `reach_level` and `survive_minutes` count only in a run played after pass 69 (an older best run does not count).
- A hero not owned is unknown on the title, in the drawer and on his sheet (name, stats, items hidden); the run's banner
  for his quest says "A NEW HERO IS FOR SALE" and the results "For sale · A new hero".

## The numbers (Garry's asks in brackets)
| hero | availability | requirement | price (gold) |
|---|---|---|---|
| Drifter | available | none | 0 |
| Astro | available | none | 0 |
| Calavera | purchase | kill the Tumbleweed King once (kill_boss, Red Canyon, stage 1) | 300 |
| Ironwood | purchase | 2,500 kills in total (kills_total) | 400 |
| Solenne | purchase | extract after stage 2 once (extract_after_stage, Red Canyon, stage 2) | 600 |
| Jeżyk (buck) | purchase | survive 15 minutes in one run (survive_minutes) | 500 |
| May | purchase | reach level 30 in one run (reach_level) | 700 |
| Fadeaway | purchase | none ["make Fadeaway purchasable with just 50 coins so I can test"] | 50 |
| Mira | purchase | kill 99,999,999 creatures (kills_total) ["bring back Mira with unattainable requirements"] | 9,999 |
| Dad | hidden | (unlock_dad kept, not shown or tracked) | - |

Why these: the order of the heroes on the title roughly tracks how far a player gets (the first boss at 7:10, 2,500 kills
over a few runs, stage 2's portal at 14:20, 15 minutes is into stage 3, level 30 is a late stage-2 level); prices sit
under a talent rank or two each, so a hero costs about one good run's purse (a run banks a few hundred gold).

### 16.LE The Level Editor

Editor rules only (what the page writes, warns or refuses); the game's numbers are the other lanes'.

- **A hero's `hidden` follows Availability**: the page and the availability op write `hidden = (availability == "hidden")`
  (lane UI's JsonContent rule: a hero to buy is never hidden; a free hero with hidden: true stays hidden). Ticking Hidden
  sets availability hidden; unticking a hidden hero sets him free. A disagreeing file is a warning with a fix button.
- **A hero's requirement** is the quest `unlock_<hero>` with `unlocks {type: character, id}`; the op refuses a condition
  type QuestTracker does not know (400) and an id taken by something else (409). Removing it moves the quest folder to
  `tools/level_editor/backups/deleted/`.
- **Warnings on a hero on the title** (free or to buy): no perk; not exactly one hero mutation in play (hidden ones do not
  count); to buy at price 0.
- **Perk warnings**: a special the game runs nothing for; a by-id special on a perk of another id (the mechanism never
  fires); no special and no effects; params keys its special does not read. Errors: no hero, a hero that is not there,
  bad effects, params not an object.
- **Evolution levels**: one level, `levels[0]`, may carry effects (applied at level 1: Slam Dunk's burn x1.5); only more
  than one level warns.
- **The quest-locked band** the Items tab draws and warns on: 0.28-0.56 (pass44_test's bounds; server.BAND_LO / BAND_HI,
  AssetsModel.BAND).

### 16.LEAD The lead's review fixes

16.L1 **A dark ball stays dark on the sand.** A ball tint's `ambient` false (`ProjectileManager.tint_material`:
`disable_ambient_light`) leaves the sky's warm ambient light out of the ball's body. Alley-Oop's body is #0A4FA8 with a
#1A5CFF glow at 0.28 and Slam Dunk's #141414, both with `ambient` false: with the ambient light the first navy
(#1B2E7A) rendered violet and the black ball brown. The Level Editor's ball colour group has the switch ("Lit by the
sky").

16.L2 **The locked hero's mask is black on the live title.** The title stage draws a hero not owned without the scene's
fog (`BillboardSprite.set_fogless`: copies of the billboard shaders with `fog_disabled`), so his LOCKED_TINT mask reads
black, not the warm brown the desert haze made of it; the mask's lifting at a purchase puts the fog back.

16.L3 **Last Stand's rim is thin and see-through**: 0.085 of the screen width (+0.045 on the beat), its red at most 62%
over the cold-graded world and falling off squared towards the middle, so creatures coming in from the edges stay
visible for the two seconds (the first version painted a solid red band a quarter of the screen wide).

## 17. Pass 70 (v0.56): lines, the trampoline, coins kept on death, dearer unlocks

Garry's request (2026-10-13, tools/dl/p70/REQUEST.md). Each lane's rules as it wrote them.

### 17.TRAMP Hang Time's trampoline, May's puck

## Hang Time (Fadeaway's perk `hang_time`, special `trampoline`; replaces the Timeout)

- **Kit.** Rare, weight 6, Fadeaway's (with Buzzer Beater). The Timeout perk and the Timeout pickup are retired:
  `hidden: true`, their folders, the `timeout` special and the `leap` pickup effect kept (the arena can still hand them
  out; §14.25-14.27 describe a retired item now).
- **The clock.** The first trampoline `first` **10 s** after the perk is held, then `every` **20 s** after the last one
  folded away (the clock waits while one falls, stands or folds: one at a time). Game time only: not while paused, not
  while he is down (Game._tick_perks).
- **Where.** `side` **3.5 m** to his left or right, square to the way he faces (ahead he would run onto it by accident,
  behind lies the crowd), on the side with fewer creatures within 2.5 m of the spot; a rock's circle (+100) or the water
  (+50) counts against a side, so it never lands on a rock or in the lake when the other side is clear; a toss when
  even; inside the arena, on the ground.
- **The drop.** It falls from 7 m in 0.45 s (a blue ring marks the spot meanwhile), lands with sand kicked up at its
  feet, a blue ring, a small shake; it cannot throw him while falling.
- **Standing.** `lifetime` **30 s**; the last 3 s it blinks; then it folds away (0.55 s). It also folds 0.45 s after its
  last jump (`uses` **1**: one jump each; a lane addition so Garry can allow more), and at once when the perk goes (the
  arena's hero swap).
- **The trigger.** His centre comes within `radius` **1.1 m** of its middle (the mat is 1 m in radius, the pad reaches
  1.28 m) while he is on the ground, alive and out of the spawn beam, having been outside the frame before. Standing
  there when it landed does not count (he steps off and back on); being in the air does not count (a landing on it
  with `uses` > 1 does: a chain bounce).
- **The way he flies.** The way he was walking (his flat speed, when at least 0.5 m/s); pushed in standing still, the
  way he faces.
- **The arc.** Up at 4h/T under his own in-air gravity 8h/T^2 (26.4 m/s^2 against his usual 24), so the top is
  `launch_height` **4 m** over the take-off and he is `air_time` **1.1 s** in the air on level ground (a little longer
  landing lower, shorter landing higher); along at `launch_distance` / `air_time` = 8 / 1.1 = **7.27 m/s**, so **8 m**
  on level ground. He faces the way he flies.
- **Air control.** The stick adds `air_control` **35%** of his walking speed (move_speed x the map's pace x the stick's
  throttle) to the arc's speed, in any direction: he bends the arc (at Red Canyon's 4.5 m/s walk, 5 x pace 0.9: 1.6 m/s,
  about 1.7 m aside over a flight), never stops it (full stick against it still carries him forward at 7.27 - 1.6 =
  about 5.7 m/s, some 6.3 m).
- **Untouchable.** While airborne take_damage returns at once (no hit, no evade roll, nothing off the shield, nothing in
  the Down! list), and no hostile shove, knock, pull or blast moves him (Player.knock_immune); his own moves still
  push. No second launch while he flies. No grace after the landing: he can be hit the moment he touches down.
- **The landing.** When the ground meets him (at least 0.08 s in) or, as a safety, after 3 air times: a squash, the
  thud (pl_land), the trampoline's dust ring and ring on the sand, a shake. A fall (a debug kill) ends a flight.
- **The camera** rides 30% of his height over the take-off (Player.camera_y, CameraRig's usual 4/s ease), so the jump
  reads on the screen; its zoom pulls out with his flat speed by the usual rule.
- **Not balance.** The mat: a spring (stiffness 260, damping 6.5) kicked to the full dip (0.32 m bowl, the GLB's "Dip")
  on a jump, rebounding past flat and settling; the frame squashes as it lands. The mat and the pad are drawn without
  the fog (the haze browned the black mat and turned the pad lavender) and without shine on the pad, which glows a
  little of its own blue (0.45). Sounds pk_trampoline_drop, pk_trampoline_boing (synthesised).

## Inflatable May's puck (perk `inflatable_may`, Decoy.gd)

- What flies is a small black puck (0.25 m across, 7 cm thick) on the old throw (`flight` 0.6 s, the 2.2 m arc). It
  comes down **0.5 m** short of the doll's spot on the line from her, slides there in **0.25 s** (slowing to a stop)
  with a hiss (pk_decoy_hiss), and the doll blows up out of it in **0.3 s** (scale 0 -> 1.12 at 70% of it -> 1, a
  wobble). Only then do the circle and the fooling (`duration` 2 s) start: nobody is fooled while it slides or
  inflates.
- So the doll fools from **1.15 s** after the throw (was 0.6 s) and is gone 3.15 s after it; the 30 s clock still
  counts from the throw. Code constants (Decoy.SLIDE, SLIDE_TIME, INFLATE_TIME, INFLATE_PEAK), not perk params.

### 17.LINES Six line items and their evolutions

Six line items (four levels each, `line: true`, one of the five line slots, evolve when maxed) and their evolutions. A
line's levels compound when they are `mul` (the sheet multiplies each level's 1 + value: Brawn's rule), so "+40% a
level" is x3.84 at level 4. An evolution replaces its line's levels, so each evolution carries more than the maxed line
of its own stat, plus its twist.

| line (rarity, weight) | per level | at level 4 | evolution | its level |
|---|---|---|---|---|
| **Lodestone** (common, 10; new) | pickup radius (`magnet`) x1.4 | x3.84 (1.5 m -> 5.8 m) | **Mother Lode** | pickup radius x4.5 (6.75 m) and every 12 s every XP gem on the screen flies to the hero |
| **Mule Kick** (common, 9; new) | knockback x1.25, all weapons | x2.44 | **Bucking Bronco** | knockback x3.0, all weapons, and a 35% chance a knocked plain creature is thrown up and away |
| **Slow Burn** (common, 9; new) | debuff duration x1.2 | x2.07 | **Prairie Fire** | debuff duration x2.2, and a burn or poison that ends (or whose creature dies) jumps to the nearest enemy, up to 3 times |
| **Tin Star** (uncommon, 8; new) | damage reduction +5% | +20% | **Marshal's Star** | damage reduction +25%, and a gold star blocks one whole hit every 10 s |
| **Prospector** (common, 9; was a passive item of 5 levels) | extra XP gem chance +6% | +24% | **Eureka** | extra XP gem chance +35%, and a 4% chance a kill bursts into 5 more gems |
| **Gold Tooth** (common, 10; was a passive item of 5 levels) | coin gain x1.1 | x1.46 | **Gold Rush** | coin gain x1.6, and +1% attack damage for every 100 gold gained while held (up to +50%) |

Decisions and why:
- **Lodestone** follows the contract's +40% (the old common Magnet was +25% over five levels, x3.05; Lodestone's four
  levels give x3.84: "a bit more powerful"). The pass-69 Magnet (the epic EXP pulls) stays a passive item, unchanged.
- **Bucking Bronco's knockback x3.0** (mul 2.0): the contract says "knockback x1.5"; read as x1.5 of the maxed line
  (x2.44 -> about x3.7) it would throw the Spear's targets about 9 m (a knock flies about push / 6 m), so x3.0 keeps it a
  clear step up (x1.23 of the maxed line) and leaves the launch as the star.
- **Mule Kick multiplies** each weapon's own `knockback` (target `all_weapons`): a weapon built with none (Big Mouth,
  Loudmouth, the Guitarra, the Salt, the Singularity) stays at none. The weapon's pause rows show the raised number.
- **Slow Burn duplicates Ducktape** (pass 47: +15% debuff duration a level -> Shackles). Both read `debuff_duration` and
  stack. Per the contract; the lead may hide one.
- Prospector and Gold Tooth keep their ids and their per-level numbers (Garry's); only `max_level` went 5 -> 4.

Rules (each new):
- **Debuff duration** (`debuff_duration`: Ducktape, Slow Burn, Prairie Fire, Shackles, Solenne's trait) now also stretches
  a **freeze** (Cold Snap's 1 s) and a **stun** (the Spear's, the Frisbee's Trick Shot): every status the hero puts on a
  creature. Still never a knockback, a lift, a bounce, a launch (Alley-Oop's, the Bronco's: their air time is their own),
  a twister, a hero's perk (scaled = false), or the Salt's slow (refreshed each tick while the creature stands in it).
- **Bucking Bronco** (`bronco_chance` 0.35): rolled on every hit from the hero's side (a weapon id; never the revive or a
  loose rocket) that knocks a creature back and leaves it alive; one roll per hit. A plain creature (never the boss, an
  Elite or an elite-modded creature: they take only the knock; never one already in the air, held, buried or rising) is
  thrown 2.8 m up and 1.5 + 0.3 x the push m/s away along the knock, at least 2.5 m and at most 6 m, over 0.8 s, kept
  inside the arena; up there it cannot walk, bite or attack; it lands in a puff with the launch's thud; no fall damage.
- **Prairie Fire** (`debuff_jump` 3): a burn or a poison that runs out on a creature, or whose creature dies with it on,
  jumps to the nearest other creature within 4 m that does not carry that same source, at the item's full seconds
  (stretched once more by debuff duration, as a new one would be), keeping its damage, stacks and spread; each source
  jumps at most 3 times. A fire never jumps onto the boss (as a fire never spreads onto him); a poison may. An ember
  (orange) or green streak shows the jump. Blight's hand-on (a poison mutation) still works beside it.
- **Marshal's Star** (`star_block_every` 10): a gold star over the hero's head while ready. The next hit that would reach
  him, after the Invincibility bubble, the blink after a hit and an evade, and before damage reduction and the Energy
  Shield, is blocked whole: no damage, no shove of its own (a blast's throw still carries him), BLOCK over him, a gold
  burst and the iron clang, then the usual blink (`hit_invuln`, 0.5 s). The star comes back 10 s later on the buffs' clock
  (a pause or a menu stops it). It starts ready.
- **Mother Lode** (`gem_sweep_every` 12): the first sweep 1 s after it is taken, then every 12 s: every XP gem on the
  screen (within 32 m and seen by the camera; never a coin, a vacuum or a chest; one already on its way is left) flies
  to him on the magnet arc; a gold ring at his feet and the pull's sound when any came.
- **Eureka** (`vein_chance` 0.04): rolled on every kill that rolls Prospector's extra gem (so it needs `xp_drop_chance`,
  which Eureka carries): 5 more gems of the creature's base size, each worth what that gem is from it, burst out in a
  fountain (1.6-3.2 m/s out, 6 m/s up) and land round it; a gold flash and the big gem's ding. The manager's own dice.
- **Gold Rush** (`gold_might` 0.01): every 100 gold gained (after coin gain, any gold that pays the purse: coins, purses,
  chests) while it is held adds +1% attack damage for the rest of the run, +50% at most (GOLD_RUSH_CAP); spending gold
  takes nothing back; gold gained before it was held does not count. Its own source on the pause screen ("Gold Rush
  +N%"); the sheets are rebuilt when the percent moves.

### 17.ECON Coins kept on death, prices x2.5, elite and boss coins x5, no Strongbox, the Collection button

Garry (2026-10-13): "Make Coins stay if Player dies. But make the prices for every unlock that we have right now
considerably more expensive. Make Elites and Bosses give much more Coins. Remove the Balloon Chest thing now."

## Rules (new or changed)

1. **Every end banks the purse.** Death, abandon and extraction all put the whole run purse (`Run.run_gold`) into the
   save once, at `Game.end_run` (`Game.bank_run_end`). Analytics reason `run_bank` for every end (PostHog `gold_meta`);
   `run_end.result` (death / abandon / extract) tells them apart. `gold_lost` is now non-zero only for a **quit** (the
   app closed mid-run, so `end_run` never ran; that purse is still lost). `Run.last_result.lost` is always 0.
   Abandoning counts as a death and so banks too (decision: losing it on abandon would only punish the honest quit,
   since walking into the crowd keeps the gold anyway).
2. **Prices x2.5** for every gold unlock.
   - Talents (`content/talents/*/cost`): each rank x2.5. A half rounds to the nearest 5, halves up (pass 46's curve
     test, rank k = 5 * round(first * mult / 5), still holds). The whole board costs 86,440 (was 34,572). Ranks 1-3 of
     all eight cost 19,430 (was 7,772). The Take it all back refund is still half of what was really spent
     (`Save.talent_spent`), so ranks bought at the old prices refund at the old prices. No exploit.
   - Heroes (`content/characters/*/price`): Calavera 750 (300), Ironwood 1,000 (400), Solenne 1,500 (600), Jeżyk (buck)
     1,250 (500), May 1,750 (700), Fadeaway 1,000 (50 was a stand-in; INTERFACES set 1,000), Mira 9,999 (unchanged,
     behind her quest). All six for sale: 7,250 (was 2,550). Owned heroes stay owned.
3. **Elites and bosses x5 gold**, everywhere they give it:
   - An Elite's purse (any Elite kind, or a creature with an Elite modifier): `Game.ELITE_PURSE` = [450, 300] →
     450 + 300 per stage index (stage 1: 450, stage 2: 750, stage 3: 1,050). Was 90 + 60 per stage.
   - A boss's purse: `Game.BOSS_PURSE` = [1300, 700] → 1,300 / 2,000 / 2,700. Was 260 + 140 per stage.
   - A boss's coins on the sand (`drops.coins` in the boss JSON, each a 5-gold coin times the stage's rounded multiplier
     1/2/3): King 60 (was 12 by default), Gila Grande 150 (30), Brander 200 (40). `Game.BOSS_COINS` = 60 is the default
     for a boss with no `coins` key (was 12). Coin count x5, not coin value, so the payout is visible.
   - An Elite's or a boss's own `drops.gold` coin (1-3 gold) is worth `PickupManager.BIG_COIN_MULT` = 5 times as much.
   - Mira's Motherlode (x1.5) and greed still multiply the purses as before.
   - Not changed: a chest's gold (the 50-gold fallback card is any chest's, not an Elite's); bounties; the shop.
4. **The Strongbox is retired.** `content/structures/gold_bank` has `hidden: true`; `StructureManager.in_play` keeps
   every hidden structure off every map (the default roster and a roster that names it). Its content folder, painting
   and `bank` effect code are kept; since it never spawns it never returns (pass 64's return primitive stays for any
   structure with `params.respawn`). The map's `structures.count` stays Garry's 9: with 8 kinds now, every kind still
   appears once and the ninth slot is drawn by weight (healing well 4, beacon 3, loot cache 3, shop 2, teleport 2,
   war drum 2, hooded figure 1, uber magnet 1: a second healing well 4 times in 18). Lower the count to 8 in the
   Level Editor for exactly one of each.

## What a run earns now against the prices (estimates from the formulas and pass 49-51's local runs)

| run | before (pass 69) | now (pass 70) |
|---|---|---|
| dies at 5:00 on stage 1 (one Elite down) | 0 banked (left in the sand) | ~600 (coins ~150 + Elite 450) |
| stage 1 cleared, extract (Elite + King) | ~600-900 | ~2,400-2,600 (Elite 450 + King 1,300 + 300 in coins + creature coins) |
| stage 2 cleared, extract (2 Elites + King + Gila) | ~4,300 (one local Ironwood run, 0.51, greed and Pickpocket in it) | ~8,000-9,000 |
| one boss alone | King ~322, Gila ~704, Brander ~1,146 | King ~1,610, Gila ~3,520, Brander ~5,730 |

So one King is worth about one hero (750-1,750); a stage-1 clear buys the cheapest two; the whole hero roster is about
three stage-1 clears; the full Upgrade board (86,440) is about ten stage-2 extractions. Deep runs progress a bit
faster than before (income x2-3, prices x2.5), early deaths much faster (they used to pay nothing).

## Watch

- The Portal decision lost its gold stake ("Head home, or push on."): continuing now only risks the run, never the
  purse. If extraction should still reward something, a later pass could give it a bonus (pass 43 removed the old x1.25).
- An early quit to the title is not possible without abandon; a phone killing the app mid-run still loses the purse
  (quit).

### 17.LE The Level Editor

17.LE1 **Candidates on seeds of their own.** Every candidate tool (gen_badge_cands, gen_title_heroes, gen_icon_cands,
gen_edit_stills, gen_ctl's side and view candidates) paints candidate k on `base + job_salt(job id) + k × 1,000,003`
(tools/cand_seeds.py: `job_salt` = (crc32(job id letters and digits) % 49,999 + 1) × 15,485,863; a hand run has no job
move). `base` keeps each tool's own moves (the look's seed_offset × 104,729, a re-run's attempt × 104,729). A re-run's
attempt reaches the tools without `--attempt` as `ASSET_JOB_ATTEMPT` (tools/asset_job.py). gen_edit_stills moves its
earlier `<key>_c<k>` candidates to `<key>_c<k>_old<stamp>` before every paint. (Before: a new job of a look repainted the
previous job's seeds; a front from a picture always the same seeds and, re-run, the cached files.)

17.LE2 **Stills is a slug.** A look's `stills` (recipe or job field) is `[A-Za-z0-9_]{0,40}`; the job form, Queue,
jobs.validate_spec, requeue, the recipe op, add_look, Save (a new bad value) and gen_edit_stills refuse anything else
with "Stills is a short name for this look's paintings, like bdb; the picture goes in Reference"; the page's error rule
blocks Save asset while a document holds one. Every ComfyUI upload name goes through `comfy.upload_name` (a path's parts
joined with _, letters digits - _ . only, at most 120 characters, .png).

17.LE3 **Removing the base look.** Allowed (not the look in play, not with a map row pinning it, never in a bulk remove);
the new base is named (`new_base`; the page offers the looks with a strip of their own on disk, the one in play first).
The top-level `sprite`, `icon`, `anims`, `strip_cols` (absent = 0), `fps`, `frame_px` (heroes) and `head` become the new
base's own values where it has them (kept where it inherited them); no file is renamed; the old entry goes; the other
looks with a strip that inherited the old top-level anims / fps / head (creatures) / frame_px (heroes) get the old
values (or the game's default) written into their entries; the old top-level strip and icon (when nothing else names
them), their .import files and `<id>_ai.json` move to `tools/level_editor/backups/deleted/<id>/<stamp>/` with
`base_<CODE>.json`. A base whose entry names its own `sprite` mirrors every landing to the top level (merge_look), and a
picked icon (set_look_files). May: MAY-A removed, MAY-G her base (2026-10-13 01:00).

17.LE4 **A pick goes to the look you choose.** An install from the look picker writes the candidate as that look's own
(badge: `<id>_icon_<letter>.png`; cut-out: `hero_<id>_<letter>.png`; creature icon: `<id>_icon_<letter>.png`; the base
look: the asset's own files, a base entry's own `title` when it names one, a creature's JSON `icon`); the picker lists
finished jobs only, newest first, any look's.

17.LE5 **The lists show the look in play.** `/api/heroes`' `icon_play` and `title_play` are the badge and cut-out of the
JSON's `variant` when the game can play it, else the base's (the editor does not read the phone's kept look).

17.LE6 **Inherited values in the box.** A text, textarea or number field whose own value is empty shows the inherited
value inside it, marked; an edit that differs from it is written as the look's own (on leaving the box); an empty box
or the inherited text typed back is no own value (the key is left out); an untouched box writes nothing. Applies to the
typed recipe, the job form's recipe fields and the typed params' values inherited from another item; the game's own
defaults stay placeholders.

17.LE7 **One view's walk.** `reroll {mode: "clip", view}` moves only that view's clip(s) aside and adds 1 to the look's
`anim_seed` (creature_ctl: `walk_seeds[view]`); refused for creature_proc and a view the look does not walk. A re-queue
of a look job reads the look's recipe from its JSON first (the job's own copy no longer overwrites a recipe edited
since).

17.LE8 **driver_tweak** writes a new driver folder only (a name in use or the source's own name is refused): op scale
(pose_scale.py, default 0.85 on back,bd), spread (0.06), occlude, shoulders (level 0.3, views back,bd, tuck off). Scale
only keeps a wide figure inside the clip: gen_art fits every walk back to the standing height, so it never changes a
view's size in the sprite.

17.LE9 **A view's size is `run_scale`** (lane ART's gen_art key, {view: multiplier}, default 1, clamped 0.5..1.5): the
Level Editor shows it as "Run size: <view>" (a `view_numbers` row per view) in the typed recipe and the job form for
hero_pose5, hero_fit, creature_free2, creature_pose2, creature_free8 (not creature_ctl, not creature_proc); a re-queue
with nothing re-rolled only re-places the cached walks.

17.LE10 **The pick writes only `stills`.** The pick of a front from a picture merges `stills` into the look's recipe as
the JSON holds it at that moment (server `Hooks.merge_recipe`, under the write lock), never the job's copy of the
recipe, never its painter or note.

17.LE11 **A Godot step has a time limit.** A step that runs the Godot binary in a register or import job is killed after
600 s (`GODOT_STEP_TIMEOUT`; env `LE_GODOT_STEP_TIMEOUT`; the job's `step_timeout` wins; 0 = never); the job fails with
"the step ran over its N s limit and was killed (…): Re-queue to run it again", and the Godot lock is freed. Test in
game (launch) never times out.

### 17.ART The art's rule

17.ART1 **A view's walk can be sized** (`recipe.run_scale` {view: multiplier}, default 1, clamped 0.5..1.5, heroes and creatures walked by gen_art): gen_art fits each view's walk by its tallest frame, so a side run that crouches in every frame came out up to a third taller than the standing figure and a back run with a foot reaching to the camera smaller; the multiplier corrects it (May {side 0.88, fd 0.92}; Jeżyk BUC-F {back 1.07, bd 1.06, side 0.90, fd 0.91, front 0.90}). A scaled driver cannot do this (the walk is fitted back to the standing height).

## 18. Pass 71 (v0.57): the Puppet method (not balance: named so they are not surprises)

No game rule changed (no content, no game code). New tool-side rules and their numbers:

- **The Puppet method (`hero_puppet`)**: a hero look whose walks are guided by the hero's own rigged 3D puppet
  (`tools/puppet.py`). Defaults: the source look = the one he is played in; the 3D reference = arms-out paintings
  (Klein, 4 front candidates, the side and the back half of that, at least 3; seeds `2026101377 + k * 1000003`, + 17
  side, + 31 back, a re-roll shifts by `--seed N * 7919`); Hunyuan3D-2mv 2 tries (seed `12345 + k * 7919`, a re-roll
  `+ N * 104729`), 30 steps, cfg 5, octree 380, 60,000 triangles after the clean; the clip `running.fbx` as "run", the
  idle procedural; guides framed by the soles; depth (Wan 2.2 Fun Control) for fd, side, bd, back and the puppet's
  OpenPose for the front; run_fit on; fringe_remap off; the walks on the source look's stills.
- **Guides are versioned**: `<hero>_puppet_<clip>` (running.fbx = `run`); a new folder `_2`, `_3`, ... whenever the
  framing, the clip or the GLB (newer than the guides' meta.json by more than 1 s) differs. Old guides are never moved.
- **A stage re-run / a fresh puppet moves files aside**, never deletes: `tools/dl/puppet/<hero>/old/<stamp>/`.
- **`run_fit`** (gen_art, any hero look's recipe): each driven walk scaled so its MEDIAN frame height = the standing
  figure's height x the ratio (from `silhouette.json` per view, or `{view: ratio}`), clamped **0.6..1.4**; replaces the
  tallest-frame fit (x0.99) for those views; `run_scale` (0.5..1.5) still multiplies on top.
- **`fringe_remap`** (gen_art): hue bins of 24; a bin is the painting's own when it holds **0.3 %** of the figure or a
  neighbour does; a clip pixel saturated over **0.2** (`min_sat`) in a foreign bin takes the mean hue of the painting's
  nearest own bin and **0.85x** (`sat`) its saturation; value and alpha kept. Off unless named.
- **Job lanes**: a puppet phase runs on comfy when it paints or makes the shape (holding the ComfyUI lock), on local for
  Blender (no ComfyUI lock; its env has no LOCK_HELD_COMFY); a phase that finds its work on the other lane re-queues
  itself at the front of that lane. The walks run on comfy as hero_pose5's.
- **The method's timings** (methods.json): median 1260 s, worst 2700 s; measured: arms-out front 1.5-2 min, side + back
  2.5-2.7 min, Hunyuan3D 3.5-4.5 min (two tries and two restarts), Blender about 30 s, guides about 1 min, a depth walk
  about 2.5 min, a stick-figure walk about 1 min; a hero who has a puppet: the walks only, about 11 min.
- **Saved workflows**: a job's saved UI workflow names top-level copies of its pictures, `<subfolder>_<sha1 10>_<file>`
  (at most 120 characters), one upload per picture and process; the graph that runs is unchanged.

## Follow-up (Garry, 2026-10-13): the improvements are settings of hero_puppet
- **Size from the 3D model** (`puppet.run_fit`, default **on**), **Frame by the soles** (`puppet.frame`, default
  **soles**), **Clean colour fringes** (`puppet.fringe`, default **on**: changed from off), **Keep the face angle**
  (`puppet.face`, default **nose**: the stick figures' ears 9 cm x the head's scale behind the measured nose and 1 cm
  up, as pose_driver places them; `head` = on the head bone's axis), **Depth or stick figure** per view
  (`puppet.depth_views`, default fd, side, bd, back on depth; the front on the stick figure).
- Every setting is recorded in the look's `recipe.puppet`; a re-queue runs the recipe's values (the job's copy dropped).
- The guides' match includes the face angle (a meta without `face` = nose, the trial's v3 guides).
- **Keep the face angle** also means (gen_art `hint_for_view`): a look whose recipe has `puppet.face: nose` walks its back
  and bd views on its hint without the `;`-clauses that name the face (face, eyes, smile, cheek, mouth, nose, lips,
  eyebrows). Other looks and the other views keep the whole hint.
- **run_fit counts the outline**: the median frame's target height is (standing height x ratio) - 2 x the outline
  (round(cell x 0.012) a side), since the outline is added after the scale (the first MAY-R walks stood +2 % in
  every view without it).

## 19. Pass 72 (v0.58): knockback, specials, bosses, the Results show

Garry's request (2026-10-13, tools/dl/p72/REQUEST.md). Each lane's rules as it wrote them.

### 19.ITEMS The basketball's colour, Rebound's icon, knockback halved, first seed everywhere

## Hero knockback halved (Garry: "Half all the knockback effect, it's too easy to make enemies basically unable to get to you")
- New map number `timeline_data.hero_knockback_mult` (WaveTimeline.hero_knockback_mult, default 1.0). **Red Canyon: 0.5.**
  Editable in the Level Editor's Settings, group Scaling, "Hero knockback ×".
- Applied (EnemyManager.hero_knock_mult) to EVERY push the hero's side gives a creature:
  - a hit's kb_force from any hero source through EnemyManager.damage() (every weapon, mutation, evolution, line, passive, perk,
    the ball, the frisbee, thorns, the revive's ring, Overkill's splash, Slam Dunk's dunk, the Nuke's hit, the Supply Drop, the Powder Keg);
  - `hero_throw_radius` (new): the Nuke's no-damage throw (the revive ring), Thruster Burst, Grand Finale;
  - Buck's Ram shove; the tornado's toss (12 m/s, now 6 on Red Canyon); the Guitarra chord's landing shove (ConeWave bounce);
  - Bucking Bronco's throw distance: clamp(1.5 + 0.3 x push, 2.5, 6.0) m x the multiplier (2.5..6 m becomes 1.25..3 m).
- Untouched: a creature's push on the hero, hostile pushes on the crowd (`EnemyManager.HOSTILE_PUSH_IDS` = "loose_rocket" (a dead
  rocketeer's rocket), "blast" (a hostile blast's friendly fire); rocket_blast / loose_rocket_blast / boulder_land keep the plain
  throw_radius), a charger's side-shove, an Elite split's spread, the pull (Lasso, Wide Orbit: a tow toward the hero, not a push),
  knockback_resist (still multiplies on top), the boss's 0.15 (on top), Alley-Oop's straight-up launch, stuns.
- The arena uses the map's number too (it is where weapons are looked at).

## The basketball's colour
- Free Throw's ball is drawn as the ball (its own look: orange plain, dark blue with Alley-Oop, black on Slam Dunk). Pass 67's
  white Free Throw tint (ProjectileEmitter.FREE_TINT: white albedo + white glow x1.4) is gone; it was the white ball Garry saw
  (with Free Throw a share of his balls flew pure white).
- New `heat_look.body_green_max` (basketball: 0.3): the body's heat glow never adds more green light than
  max(its cold glow's green, 0.3), so a body that already glows (On Fire's tint #FF3A00 x1.6) stays orange at every Heat
  instead of bleaching to yellow-white at the top (emission pushed to #FF5A10 x1.6 x the 1.35 beat). The plain ball
  (no glow of its own, glow_max 0.45: green 0.21 at the beat's peak) never reaches the cap. Slam Dunk and Alley-Oop glow only
  in their seams (surfaces "seams"), so the cap never applies to them.

### 19.SPEC Specials bigger, tougher, capped, dropping chests; outlines only behind scenery

## Coloured (variance) specials: bigger, tougher, a chest, at most three
- **Numbers** (Garry: "Specials should be more noticeable. They should be bigger ... higher HP"): `special.size` 1.25 -> **1.5**,
  `special.hp` 10 -> **15** on every creature with a special block (22: the 21 with a chance and the shaman's chance-0
  block); `damage` x2 and `xp` (3 on all) unchanged; the colour and the glow unchanged. `EnemyDef.SPECIAL_DEFAULTS` (the
  game's fallback) is now {size 1.5, hp 15, damage 2, xp 2, tint_strength 0.6, glow 0.6, chest_chance 0.35}. A special is
  still exactly its size factor x the creature's own size (the plain spread does not apply; in a size-range row it stops
  at the range's top).
- **The chest** (new rule; Garry: "way more of a chance of dropping a box"): a variance special the hero kills drops a
  chest with chance **0.35** (`variance.special.chest_chance`, the creature's own, else the map's
  `timeline_data.special_defaults.chest_chance`, else the game's 0.35; clamped 0..1). It rolls on the death (`_die`), so a
  nuke's or Brimstone's kill rolls too; a special freed without a death (a stage cleared, a despawn) drops none, nor does
  a training dummy, nor while a capture tool holds the kill chests back (`no_random_chests`). It is on top of anything
  else the kill pays: the creature's own `drops.chest` (Game) and Hot Sauce's chest (0.05 x difficulty, one per 40 s)
  roll apart, so one special can, rarely, drop two. Before: a special dropped only its creature's `drops.chest` (0-1 %)
  and Hot Sauce's.
- **At most three alive** (new rule; Garry: "There should be a limit to how many of them are there"): at most
  `special_defaults.max_alive` coloured specials live at once, **3** on Red Canyon (the game's default
  `EnemyDef.SPECIAL_MAX_ALIVE` 3 when the map names none; **0 = no limit**, as a creature's own max_alive). A roll that
  would make a 4th makes a plain creature (its palette tint, its plain size spread, plain HP, no glow); the dice are rolled
  first and only then refused, so below the cap the run's random sequence is what it was. A **forced special** (a swarm
  event with Special ticked, e.g. the Special Goblin at 2:00) **always comes**, past the cap too, and counts as alive. A
  dying special stops counting at its death (`_die`), a freed one at its freeing (`_free`). Why 3: at x15 HP a late
  crowd of 250 at a 0.04 chance would carry about ten of them at once.
- The editor's spawn estimate ("Spawned so far") keeps the expected coloured specials alive under the same cap (they die
  at the crowd's turnover; a forced swarm comes past it), so its coloured counts match the game's rule.

## Outlines only behind scenery
- **Rule** (new; Garry: "Make the outline of the enemies not appear when they're behind other enemies, only when they're
  behind environmental things"): a creature's see-through outline (enemy_silhouette, its second pass) shows only where
  the nearest thing in front of it is **scenery**: a painted prop (cacti, trees, rocks, bones, bushes), a painted structure
  or the portal, a sign, a barrel, the boundary wall with its posts and skulls, the near cliffs. Behind another creature
  (a boss and an Elite included) or the hero it shows nothing. The hero's own outline is unchanged (it shows wherever
  anything stands in front of him). The sand and the dunes are not scenery here (a creature low behind a dune is not
  outlined: none was asked for, and it keeps the feet of creatures on slopes from ghosting).
- **How**: the stencil buffer (Godot 4.7, the Compatibility renderer). Every opaque thing writes a value where it draws
  (the last one drawn at a pixel is the nearest): creatures, the hero, power-ups, flowers 1 (PickupManager.PAINTING_STENCIL,
  as since pass 54); scenery **2** (SceneryStencil.VALUE: prop_billboard, sign_depth, the structures' and the portal's
  copy of sprite_billboard (SceneryStencil.scenery_shader), the barrels', the wall's and the cliffs' materials
  (SceneryStencil.mark / mark_tree)). The outline pass reads `== 2`. The gems, coins and their glints (and the
  Strongbox coin stream's shadows) now read `== 0` (they read `!= 1` before): still under every painting, and now also
  under the barrels, signs and wall where they overlap (they had drawn over them).
- **Cost** (measured, PC RTX 4070, 504x1122, 250 creatures among 14 props, GPU time a frame): outline pass with the
  stencil 0.587 ms, the old outline 0.595 ms, no outline 0.579 ms; draw calls 80 either way (the pass adds one per
  creature type, as before). perf_late (build six, late stage 3, ~220 creatures): 184-202 draw calls and 1.07-1.24 ms
  render CPU before, 186-204 and 1.14-1.25 after (noise). No extra draw call, no extra pass.

### 19.BOSS Boss HP pegged to DPS, the Gila's cactus rain, custom boss attacks

## Boss HP pegged to the hero's DPS (Garry: "Boss Max HP should scale up the bigger the Player's DPS is in that moment. It shouldn't be 1 to 1")

- **Where**: map JSON `timeline_data.boss_hp_scaling {enabled, exponent, window, min, max, ref_dps: {boss id: DPS}}`
  (WaveTimeline.boss_hp_scaling, `BOSS_HP_SCALING_DEFAULTS` {enabled false, exponent 0.5, window 45, min 0.75, max 3.0}).
  Level Editor: Settings → **Boss HP** (the five numbers, a reference DPS per boss, the chart, the thinking).
- **Rule**: when a boss (archetype `boss`) arrives through the director (`WaveDirector._start_boss`), its HP (hp ×
  hp_mult_per_stage^stage × max(stage mult, 1), unchanged) is multiplied by
  `clamp((dps / ref_dps[boss]) ^ exponent, min, max)` (`WaveTimeline.boss_hp_mult`, `WaveDirector.boss_dps_scale`,
  `EnemyManager.boss_hp_scale` held around the spawn).
- **dps** = `Run.recent_dps(window)`: the damage `Run.add_damage` recorded over the last `window` seconds of
  `buff_clock()` (the clock that also runs through boss fights and portal waits), divided by the window, or by the run's
  seconds so far when the run is younger than the window. It counts what a hit took off (never past what the creature had
  left: a 500 hit on a 20 HP goblin is 20), every weapon and damage source. 240 one-second buckets (`Run.DPS_BUCKETS`).
- **Off / untouched**: scaling off (`enabled` false or no block): ×1. A boss without a `ref_dps`: ×1. The debug arena:
  ×1 always (bosses keep their data HP). Elites and Elite bosses (archetype `elite`), a creature spawned by hand: never
  scaled. The HP bar shows the scaled HP.
- **Endless**: a returning boss's reference grows with its own HP growth since its stage: ref × (hpm^stage_now ×
  max(stage mult now, 1)) / (hpm^own_stage × max(stage mult of its stage, 1)), its own stage being the stage its first
  timeline boss event closes (`ceil(t / stage_length) - 1`: 430 s = stage 1's end = index 0). Why: endless already grows
  the boss's HP with the stage multiplier; a build that kept up with that is not tripled on top.
- **Why the exponent 0.5** (Garry asked for "not 1 to 1, still a reward"): twice the reference DPS = 1.41× the HP, the fight
  29% shorter; four times = 2× the HP, the fight half as long; half the reference = 0.71× → the floor 0.75. Exponent 1 =
  every fight as long as at the reference (no reward), 0 = no scaling. Floor 0.75 = a weak build gets a softer boss, never
  a pushover; ceiling 3 = reached at 9× the reference DPS, a monster build never meets a sponge.
- **Red Canyon** (the map JSON, end of timeline_data): enabled, exponent 0.5, window 45, min 0.75, max 3.0, ref_dps
  Tumbleweed King **600**, Gila Grande **4500**, the Brander **20000**.
- **How the references were measured** (`tools/difficulty_probe.gd`, new `DPS45` line = Run.recent_dps(45) at the end of
  the window; the window ends at the boss's second, `t0 = boss - 75, secs = 75`; pass 64's typical builds and Upgrade
  boards: the King b1 level 22 Mirror 0, the Gila b2 level 33 Mirror 1.5, the Brander b3 level 43 Mirror 3; Calavera and
  Drifter, seeds 11 and 23; log tools/dl/p72/BOSS/ref1.log):
  - King (7:10): 658, 676, 583, 405 → mean 580 → **600**
  - Gila (14:20): 3796, 4160, 4522, 6077 → mean 4639 → **4500**
  - Brander (21:30): 20260, 15661, 24803, 21185 → mean 20477 → **20000**
  A hero at the reference meets each boss exactly as before pass 72 (×1).
- **Caution for tuning**: the DPS is what the crowd let him deal; when the crowd dies faster than it comes the DPS shows
  the crowd's HP supply more than the build. With `boss=1` (fight1.log) the reference builds met their bosses at ×0.96 to
  ×1.15 (as intended: they are the references); the bot's fight lengths swing from 10 s to over 450 s between runs of the
  same cell (it kites away from bosses and its weapons pick the crowd), so they say nothing about a player's fight.

## Custom boss attacks (content/boss_attacks)

- A content type: `content/boss_attacks/<id>/<id>.json` (BossAttackDef), named in a creature's `boss.attacks` as
  `{"name": "<id>"}` next to the built-ins; the entry's own keys override (min_range, max_range, reach, windup, telegraph).
  An id may never be a built-in attack's name (BossAttackDef.SCRIPTS). Any scripted creature can run one (bosses, Elites,
  casters), on the same runner.
- **Damage** of every custom hit: `damage` × the creature's bite (its JSON `damage`) × stage_of × lvd_of × host_of (the
  factors every scripted attack carries). Knockback: Player.take_damage's `knock` (a hit or a shield's catch moves him; an
  evade, the Invincibility bubble or an airborne hero never); `lift` > 0 adds Player.blast after a landed hit.
- **Clock**: everything a custom attack puts in the air runs on the creatures' shot clock (delta × pace, delta carrying
  High Noon's time_scale: `EnemyManager.hostile_clock`); the wind-up and every telegraph last 1/pace as long as their data
  seconds (Red Canyon pace 0.9 × 0.9 = 0.81: a 1.0 s wind-up = 1.23 s).
- **rain**: the landing points (BossAttackDef.points) round the boss (or the hero's spot at the wind-up's start): laid out
  by `shape` (rings: rings max(0.87 × spacing, 2 × radius + gap + 2 × jitter) apart from radius_min, each with
  floor(2πr / spacing) points, every other ring turned half a step; grid: a hex grid; spiral: a sunflower spiral at the
  hex density; random: a Poisson disc at 0.9 × spacing), spacing raised to at least 2 × landing radius + gap, each point
  jittered by up to min(jitter × spacing / 2, (spacing − (2r + gap)) / 2), the whole turned at random (`turn`), ordered
  (`order`: out / in / random / sweep), then **the gap rule**: a point closer than 2 × landing radius + gap to a kept one
  is dropped (so between any two circles there is always `gap` metres of sand), then `count` (0 = all). Spots past the
  arena's wall (arena radius − 1) are left out. Landing times: the k-th spot lands at flight + stagger × k / (n − 1). Each
  spot's red circle (Telegraphs.ring, filled, growing) shows `telegraph.seconds` before its landing; the spike is thrown
  from the boss's back (0.75 × its size up) at land − flight on a parabola `arc` metres over the straight line. On
  landing: the hero is hit when his middle is within landing radius + 0.2 m; a sand puff and a flash ring; the land sound
  only within 14 m of him and at most one every 0.12 s of the clock; the spike stays stuck 0.55 s. The fire sound plays
  every 0.35 s while spikes leave. The boss stands while its spikes leave (`timing.hold` −1 = the stagger).
- **volley**: `count` shots a wave over `spread_deg` round its aim (at the hero / random / fixed east), `waves` waves
  `wave_gap` apart, straight at `speed` for `range` m, 1 m over the ground; a shot hits once when it passes within
  hit_radius + 0.3 m of the hero. **ring**: `count` rings `wave_gap` apart racing to `radius_max` over radius_max / speed
  seconds with Telegraphs.race_ring's ease-out (front = R × (1 − (1 − f)³)), `width` thick; each hits the hero once as it
  passes. **slam**: a blast of `radius_max` (+0.4) round the boss or the hero's spot at the wind-up. **script**: a
  built-in under its own name with its own keys (`script`, `params`).
- **Rest**: `timing.cooldown` > 0 replaces the creature's `cooldown_between` after this attack; 0 keeps the creature's.

## The Gila Grande's red cactus rain (replaces its rumble)

- `content/boss_attacks/cactus_rain`: kind rain; projectile spike, tint #D0242F, size 1.7, glow 1.2, flight 1.1 s, arc
  7 m, trail; pattern rings, centre the boss, radius 3.6-16 m (past the Gila's 2.4 m body), spacing 3.2, jitter 0.25, gap
  1.0 (the hero is 0.9 m wide), turned at random, nearest first; landing radius 0.9; telegraph circles #ED4A5C 0.9 s;
  damage 0.75 × bite (24 → 18 before the factors; the rumble was 16 flat × the same factors); knockback 4, no lift;
  wind-up 1.0 s, stagger 1.5 s, the boss's own rest (2.2 s), stands while its spikes leave; sounds fire en_cactus_spit,
  land en_stalactite_hit.
- Typical layout: 64 spots (89 with no jitter), the narrowest gap ≥ 1.0 m (1.09-1.12 m seen), the circles covering about
  20% of the ring; the rain lands from 1.1 s to 2.6 s after it fires (×1/pace on the map: 1.36-3.2 s).
- The Gila's script: roll, cactus_rain, burrow, spawn_ring (the rumble stays a built-in any script may name).

### 19.RESULTS The animated Results screen

All numbers are constants in `ui/ResultsScreen.gd` (the show), `ui/wanted/WKillChart.gd` (the chart) and
`core/systems/RunTimeline.gd` (the record). None is content data; none changes play.

## The run's record (RunTimeline, `Run.timeline`)
- A new record at every `Run.start`; Game attaches it in `_ready` for a real run (never the arena) and ticks its clock
  from `Game._process` (unpaused play only, like the run recorder's `play_t`), so a boss fight or a portal wait, where
  the stage clock stands still, keeps its seconds on the chart. Its length is the play time, so the chart's right end
  can be later than the stage clock shown above it (10:00 survived, 11:30 played).
- Sampled every whole second: the purse (gold in AND out: a shop or a revive shows as a dip), the kills in that second,
  all damage dealt so far. Every 5 s (`SRC_STEP`): each damage id's damage so far.
- Kill kinds: **boss** = the creature that is the boss (`boss_index`) or a boss archetype; **Elite** = the Elite
  archetype or any creature wearing an elite modifier; **special** = a variance special (the big dark one, `vspecial`)
  OR a creature with the gear badge (the rocketeer, the harpooner: the game's own "special" badge); else plain. A
  training dummy is not counted. Each boss, Elite and special kill and every time the hero goes down (`Player.died`:
  the falls he got up from and the last one) is a marker with its moment.
- A damage source "joins" the run when it is first owned (a weapon, an evolution, a passive, a perk or a mutation: the
  build is scanned on every `build_changed`), else when it first hit (fire, poison, explosions, a power-up, the revive's
  blast: within a second). The starting weapon is the first weapon owned and always comes first.
- The counted unlocks' progress (`QuestTracker.progress`, the quests counted across runs) is kept as the run begins.

## Sequence 1, "Run performance" (the board held at the top; pass 74)
- Lead-in 0.35 s (the board's slide, `LEAD_IN`), then the gold (2.5 s, `GOLD_TIME`), the pop (0.3 s, `POP_TIME`), the
  chart part (3.2 s, `JOINT_TIME`, a little longer only when its last row needs it). About 6.35 s in all.
- **While the gold counts** nothing of the rest of the board shows: the "Run performance" label, the chart block (its
  frame, the plot, the stage lines, the Kills and Damage counters), the "Damage dealt" label and every source row wait
  unseen in their places (their space kept, so nothing on the board moves when they come). The gold is as before: the
  "+N" shows the purse at the same share of the run's play time, ending exactly on what was banked.
- **The pop**, as the gold ends: the chart block grows from 85 % of its size (`POP_FROM`) past it and back (an
  ease-out-back of strength 2.6, `POP_BACK`: about 3 % over at its middle) while it fades in over the first half of the
  pop (`POP_FADE` 0.5), drawn as one picture (a CanvasGroup, so its ink shadow and its plot do not show through the
  paper while it fades). The two labels and the starting weapon's row fade in with it. A soft card sound.
- **The chart part**, one clock for everything: the line crosses the whole run in `JOINT_TIME` (3.2 s), its marks pop as
  it reaches them (as before), the Kills and Damage counters show what the run had reached at the line's moment (as
  before), and the source rows play on the same clock:
  - each row comes in when the line reaches the moment its source joined the run (first owned, else first hit:
    RunTimeline.joined), the starting weapon's at the start (it came with the pop), one the record never saw at the
    line's end; never sooner than `ROW_BEAT` (0.12 s) after the row before, so rows whose sources joined together come
    a beat apart and each can be read; a row fades in over `ROW_FADE` (0.2 s) with a card sound, and the board eases
    down to keep it above the buttons (never up);
  - each row's bar, number and percent show that source's damage so far at the line's moment (its 5 s samples, linear
    between them, 0 at the run's start and exactly its total at the end: RunTimeline.source_damage_at), the percent of
    the run's FINAL total damage, so a bar only grows and ends on its share; a source that joined later in the run comes
    in near the end with a short bar;
  - when the last rows' moments and beats run past `JOINT_TIME` (sources that joined in the run's last seconds), the
    part runs on until the last row has faded in (its moment + `ROW_FADE`); the line stays whole meanwhile.
- **A run with no story** (a tool's or a test's: nothing recorded): the rows keep the biggest-first order and come in
  spread evenly over the chart part (row k at k / n of `JOINT_TIME`, still a beat apart), each growing from its own
  moment to its total at the end.
- The board does not move under a finger or the wheel while the show plays; it eases down by itself only so the newest
  row is not hidden under the buttons (never up). Taps as before: one hurries the sequence x4, a second ends it at once
  (everything in place, its final values, no sounds).

## Sequence 2 (only when the run unlocked something or brought an unlock closer)
- 2.0 s pause, then 0.7 s scroll to the unlocks (their label 40 px under the top of the view, as far as the board goes).
- Each unlock completed this run: 1.2 s (a run landing several: 4.0 s for all of them, never under 0.7 s each); the
  panel fades in with its plate a silhouette, at 35 % of its time the plate shows its art, the panel flashes, an
  UNLOCKED stamp (FOR SALE on a hero to buy) slams down over its corner, a celebration burst over the plate.
- Then every unlock whose kept progress grew (counted quests not done; nearest to done first): each bar fills from where
  it stood to where it stands (this run's part in sage), 0.35 s apart, 0.55 s each, the lot in 3.0 s at most.
- Sequence 1 about 6.35 s; a run that unlocked nothing and brought nothing closer ends there. With four unlocks brought
  closer about 10.65 s; with one unlock landed too about 11.85 s (the second sequence as in pass 72: 2.0 s pause, 0.7 s
  scroll, 1.2 s an unlock, the bars at most 3.0 s).

## Taps
- A tap anywhere but on a button (any finger lift, a drag included, while the show plays) hurries the sequence playing
  ×4 from then on (the current part and the rest of that sequence); a second tap in the same sequence ends it at once
  (no sounds, no bursts). The second sequence starts at normal speed with its own 2 s pause. The buttons work at any
  time and a tap on one never hurries the show.
- The end-of-run survey (pass 59) now waits for the show to end (then its 1.4 s).

### 19.INTEG Garry's edits during the pass

- **A map that names no `hero_knockback_mult` halves** (WaveTimeline.HERO_KNOCKBACK_DEFAULT 0.5; the WaveTimeline
  class default and JsonContent's fallback; was 1.0). The halving is the game's rule, not only Red Canyon's, so a map
  JSON saved without the key (a Level Editor page opened before pass 72 saves timeline_data from its own copy and drops
  keys it never saw) keeps Garry's halving. Without any map at all (a bare EnemyManager in a test) the push stays x1.
  Level Editor: Settings > Scaling "Hero knockback ×" shows 0.5 as its grey default.
- **Boss HP pegged to DPS is on by default**: a `boss_hp_scaling` key the map leaves out, the whole block too, plays the
  game's value: enabled true (was false), exponent 0.5, window 45 s, floor 0.75, ceiling 3
  (WaveTimeline.BOSS_HP_SCALING_DEFAULTS), and a boss its `ref_dps` leaves out takes WaveTimeline.BOSS_REF_DPS_DEFAULTS
  (Tumbleweed King 600, Gila Grande 4500, the Brander 20000: lane BOSS's measurements). `"enabled": false` turns it off;
  a boss's ref 0 = that boss is never scaled; a boss neither the map nor the defaults name is never scaled; the debug
  arena never scales. Level Editor: Settings > Boss HP shows "on" and each boss's measured reference as grey defaults.
- **Specials on a map without `special_defaults`** already played pass 72's numbers (EnemyDef.SPECIAL_DEFAULTS: x1.5
  size, x15 HP, x2 damage, 35% chest; SPECIAL_MAX_ALIVE 3): unchanged, now pinned by pass72_integ_test.
- **The goblin runt is in play again** (`retired` false): Garry put it back on his stage-1 roster (row r2, 2:21-3:20,
  speed 4, never an Elite) on 2026-10-13. The goblin stays retired.
- **A hero on sale with no unlock quest is buyable at once** (Registry.hero_state "buyable" on a clean save): Astro since
  Garry's 2026-10-13 edit (300 gold), Fadeaway (1,000) before. A save that played Astro while she was free does not own
  her now (Save.load_save opens it on the Drifter until she is bought; the developer menu's own_every_hero still owns all).

## 20. Pass 73 (v0.59): priority targets, the Saiga Sniper, burrows and rain, fortune cards, Totem Poles

Garry's request (2026-10-14, tools/dl/p73/REQUEST.md). Each lane's rules as it wrote them.

### 20.SNIPER Target priority, the Saiga Sniper, flee on hit, the Raider's rocket

Every number below is data (the file named) unless marked *code*; Garry tunes the data in the Level Editor.

## Target priority (map `timeline_data.target_priority`, WaveTimeline.TARGET_PRIORITY_DEFAULTS)
- **Rule**: every weapon that chooses its target takes a *priority creature* first when one is within
  `reach` = min(the weapon's own targeting range, `target_priority.reach` **10 m**) of the hero; among several, the
  nearest. `enabled` **true**. A map without the block plays the defaults (on, 10 m). Red Canyon names the block.
- **Priority creature** (*code*, EnemyManager.is_priority): a coloured variance special, a gear-badge creature (the
  Vulture Raider, the Harpoon Troglodyte, the Saiga Sniper), an Elite by its kind, a creature wearing an elite
  modifier, the boss. Never one dying, buried, held, or still under 70% risen (lane GROUND's grid rule).
- **Where it is measured from** (*code*): the hero; a turret from itself; a homing seeker's retarget from the hero.
  On the screen only, as the weapon's own pick (Settings.ranged_on_screen), unless the weapon hunts off the screen
  (missiles, hawks).
- **Which weapons** (*code*): every pick through WeaponBehavior.aim_index (the guns, the held gun's tracking and the
  companion, the Spear and Sabre lines, the turrets, the Missile Pod's lock, the Frisbee) and now the Guitarra's chords
  and Big Mouth's beam (they went to the nearest by hand); the "healthy" and "random" picks; missile seekers.
- **Volleys spread over different creatures keep that rule; only their first shot takes the priority one** (*code*):
  the Sun Scepter's first pillar (the rest drawn as before, none twice), the Zap Beam's first link (the chain goes on
  as before), the Lobber's first bomb (the others on other crowds), the Hammer's first head and the Gravity Gun's first
  throw (WeaponBehavior.crowd_spots' first spot), the Singularity's black hole, the first Tarantula Hawk (one hawk a
  creature).
- **Untouched**: orbits and auras (Orbiter), the Salt's patches, mines and their triggers, the Golden Pineapple's
  landing stick, a dead Raider's loose rocket.
- **Cost** (perf_late build=six, stage 3, headless PC, 2 × 20 s each): the query scans a short list of the priority
  creatures alive (gathered once a tick), so it costs nothing measurable; the weapons' own time reads 0.44-0.71 ms a
  frame with the rule on against 0.44-0.45 off, the spread being what they hit when an Elite or a special is in reach
  (frame 6.1-7.0 ms on, 6.8 off: noise).

## The Saiga Sniper (`content/enemies/saiga_sniper/saiga_sniper.json`, block `sniper`)
- A special (gear badge), never an Elite (`can_be_elite` false), never grabbed, at most 1 alive (`max_alive`).
  HP **35**, XP × **3.5** (the Vulture Raider's), walk **3.2** m/s, bite 8, bite knock 4.81, size 3.0, radius 0.8,
  drops as the Raider's.
- **Spawn**: placed at `stand_off` **26 m** from the hero (never nearer, inside the wall), like the Raider.
  First aim `first` **2.5 s** after he arrives.
- **Walk** (*code* rules, data numbers): hero nearer than `flee_range` **14 m** -> he runs straight away (sliding along
  the wall when backed against it), never aims; farther than `follow` **38 m** -> walks back in; between -> stands and
  aims when his rest is over.
- **Aim**: frozen (no walk, the `attack` strip = his aiming pose, front or back half by his facing), `aim` **2.0 s** of
  red lines gathering on the hero and following him (a quick ease, 10/s, *code*), then the lock: `lock` **1.0 s** of a
  still, blinking line (3 -> 11 Hz, *code*), then the shot. Both × 1/pace like every wind-up: on Red Canyon
  (move_pace 0.9 × creature_speed_mult 0.9 = 0.81) the aim shows **2.47 s** and the hold **1.23 s**. (For exactly 2.0 /
  1.0 s there, set aim 1.62 and lock 0.81.)
- **The lines** (`cone_deg` **44**, `lines` **14**; *code*: the k-th appears at (aim − 0.2) × (k / lines)^0.6, so they
  come closer and closer together; each sweeps in from its side of the cone, starting at 75-100 % of the half cone, over
  0.8 s for the first down to 0.2 s for the last; sides alternate; every one lands by the lock; the line on the hero
  brightens with each arrival).
- **The shot** (`beam`): from the muzzle (`muzzle` {up 1.95, side 1.3, forward 0.2}, to be fitted to ART's painting)
  along the locked line for `length` **60 m**, `width` **0.5 m**, shown `seconds` **0.15 s** (a white core in a red glow),
  then a red afterglow and sparks (2.4 a metre, *code*) shimmering and fading over `sparks` **1.5 s**.
- **The hero** is hit when his feet are within half the width + **0.4 m** (*code*) of the line: damage =
  `damage_mult` **0.7** × the missile damage of `damage_from` (**rocketeer**: 22 -> 15.4) × the sniper's own stage,
  hero-level and hostile factors (as the rocket's); knock `knockback` **5** m/s along the beam. A fixed `damage` 15.4 is
  used when `damage_from` names nobody.
- **Creatures on the line** (their feet within half the width + their radius): `creature_frac` **5 %** of their max HP,
  at most `creature_max` **40**, from nobody (no crit, no item effects), and pushed `push` **3 m** off the line to the
  side they stood on (an 18 m/s knock × their knockback_resist share; a boss 0.15 × that). It is a hit: their flee on
  hit, a Raider's rocket slow.
- **After the shot** (*code*, SNIPER_AFTER_HOLD **0.35 s**): he keeps the aiming pose through the beam's flash and a
  breath after, then may move (he had dropped to his walk on the very frame the beam showed).
- **Interval**: `interval` **9 s** ± `interval_jitter` **1.5 s** from shot to shot (the rest after a shot = interval ±
  jitter − (aim + lock) / pace, never under 0.5 s, *code*).
- **A spoiled aim**: a hit (flee on hit), a stun, a freeze, a launch, a grab or the hero's death drops the aim (no shot);
  the next aim waits at least `recover` **2.5 s**.
- **Red Canyon**: one row `{"enemy": "saiga_sniper"}` in `specials.pool` beside the Raider's (no `stage`: from stage 1,
  as his). The pool draws evenly among its open rows and keeps one special at a time (`max_alive` 1), so in stage 1 the
  Sniper and the Raider now come equally often, **each half as often as the Raider alone did**; from stage 2 a third
  each with the harpooner. (If Garry wants the Raider's own rate kept, raise `specials.max_alive` to 2 or shorten
  `specials.interval`.)
- Sounds (synthesised by tools/synth_sfx.py): `en_sniper_aim` (2 s whine, −10 dB), `en_sniper_lock` (−1 dB),
  `en_sniper_shot` (0 dB). The hint "SAIGA SNIPER: step off his red line before he fires. Hit him to spoil his aim."
  shows once.

## Flee on hit (any creature, block `flee_on_hit`)
- `seconds` **1.0**, `speed_mult` **1.8**, `interrupts` **true** (the Sniper's numbers; none on any other creature).
- **Rule** (*code*): a hit that takes health (never a poison or fire tick) sends it straight away from the hero at its
  speed × `speed_mult` for `seconds` (along the wall when backed against it, round the rocks), its brain idle; a new hit
  starts the clock again, never a faster run. Never a boss; not while held, buried or in the air.
- With `interrupts`: a wind-up under way is dropped (its next try waits ≥ 1 s; the Raider's rocket stays in the tube
  and he reloads), a scripted attack is dropped (its script waits ≥ 1 s), the Sniper's aim is dropped (`recover`).

## The Vulture Raider's rocket (`rocketeer.json`, `artillery.missile.hit_slow`)
- `mult` **0.5**, `recover` **3.0 s**, `shake` **0.35 s**.
- **Rule** (*code*): every hit on the Raider (never a tick) drops each of his rockets under guidance to `mult` of its
  speed at once; it climbs back to full in a straight line over `recover` seconds; a hit while it climbs starts the
  climb again from `mult` (never lower). The recovery runs on the creatures' shot clock like every hostile shot's flight
  (× 1/pace: **3.7 s** on Red Canyon). It shakes for `shake` s: position ±0.16 m and nose ±16° (*code*), fading out.
  No `hit_slow` = never slowed (any other artillery creature).
- Fix: a Raider whose wind-up was dropped (a stun, a launch, now a hit's flee) waited for good for a rocket that never
  left; he now winds up again.

### 20.GROUND The Gila's rain and burrow, the Scorpion's burrow, summons, growing out of the ground

## The Gila's cactus rain, reworked (content/boss_attacks/cactus_rain; Garry: "each spot where the projectile will fall is highlighted. At once they wait for a little bit and then the boss does his animation of all those projectiles flying out of his mouth but they all land around the same time. Also make it so that the projectiles are bigger and they affect a bigger area so there is less space for the player to hide in")

- **New attack keys** (BossAttackDef, the Boss attacks tab): `landing.mode` "stagger" (pass 72: one after another
  from the boss's back over `timing.stagger`) | "volley" (one spew from the mouth); `telegraph.all_at_once`; the `spew`
  group {crouch, burst, mouth, squash, stretch}.
- **All at once** (`telegraph.all_at_once` true, a rain): every landing circle lights up together `telegraph.seconds`
  before the spikes leave and stays lit until its own spike lands. The wind-up the runner plays is
  max(`timing.windup`, `telegraph.seconds`) (BossAttackDef.windup_seconds), so the circles can show that long; when
  the wind-up is longer they light `telegraph.seconds` before its end. In the game the circles are held ground marks at
  full radius (a disc at 0.26 alpha and a ring pulsing 0.74 ± 0.14 while they wait; after the spew the disc fills to
  0.46 as its spike comes down and the ring blinks in its last 0.3 s), each released as its spike lands, all of them
  if the boss dies or leaves its attack before the spew. No outline of the area then.
- **Volley** (`landing.mode` "volley"): the spots are laid out at the wind-up's start (the pass-72 layout and gap rule);
  at the spew every spike leaves the boss's mouth (its feet, up its painting `spew.mouth` × its size, 0.45 m towards the
  camera) within `spew.burst` seconds (at random) and flies `projectile.flight` + (`timing.stagger` − burst) × dn,
  dn = 0 for the spot nearest the centre .. 1 for the farthest (BossAttackDef.volley_times), so every spike lands within
  `timing.stagger` of the others, the nearest first. The boss stands `spew.burst` + 0.35 s after the spew (hold −1).
- **The spew's animation**: through the last `spew.crouch` seconds of the wind-up (× 1/pace) the boss is squashed from 1
  to `spew.squash` (shorter and wider); at the spew it stretches to `spew.stretch` (taller and narrower, easing back to
  1 at the creatures' usual rate), a light flash (0.25) and a burst of the shots' colour at its mouth.
- **Red Canyon's cactus rain**: volley, all at once, `telegraph.seconds` 1.4 and `timing.windup` 1.4 (1.73 s on the map,
  pace 0.81), `timing.stagger` 0.25, flight 1.1, arc 7, spikes `projectile.size` 2.72 (pass 72's 1.7 × 1.6), landing
  radius 1.4 m (pass 72: 0.9; the hero is hit when his middle is within 1.6 m), pattern rings 3.6-16 m, spacing 3.9
  (pass 72: 3.2), gap 1.0 (the rule), jitter 0.25; spew crouch 0.35, burst 0.12, mouth 0.62, squash 0.82, stretch 1.25.
  Damage 0.75 × bite and knockback 4 unchanged. Typical: 59 spots, the narrowest gap 1.0-1.1 m, the median gap between
  neighbours 1.1-1.2 m (Garry: "less space"; pass 72: 1.1-1.4 m), the circles cover about 48% of the ring (pass 72:
  20%); on the map the spikes land 1.36-1.65 s after the spew, all within about 0.3 s.

## Burrowing you can see; the Gila's three hidden seconds and its predicted eruption (Garry: "the boss just disappears and then pops out. It would be nice if I can actually see him burrowing into the ground ... also true for the Scorpion Elite"; "wait for 3 seconds ... not showing the player where the attack is going to happen ... tries to guess where the player is going to be ... in the next 2 steps or so"; "throw other enemies out of the way and the Player too. Enemies don't get a lot of damage ... a real throw instead of just a knockback. Scorpion attack also does this, but not as strong")

- **Keys** of a `burrow` entry (the creature's boss.attacks; the Enemies tab's attack card), all optional, the old
  behaviour without them: `sink` (s, 0), `rise` (s, 0.4 = RISE_TIME), `predict` (s, 0), `warn` (s, 0.4), `mound` (true),
  `throw_up` (m, 0), `throw_out` (m, 0), `throw_air` (s, empty = from the height), `throw_control` (0.15),
  `creature_up` (m, 0), `creature_out` (m, 0), `creature_damage` (share of max HP, 0). The wind-up still runs from the
  dig to the eruption (× 1/pace).
- **The sink**: with `sink` > 0 the creature sinks out of sight where it stands over `sink` / pace seconds (the
  ground-clip below), a ring of dust round it at the start (Fx.dig_ring), sand spraying off it every 0.09 s (Fx.dig_spray)
  and a small poof (pop_dust at 0.6 × its size) as the sand closes; then it is hidden (not drawn, not hit, no shadow).
  It can be hit while it sinks (and is passed over as a target once it is under 70% of the way out). A burrow dropped
  before it erupts (its attack ends or another starts) brings it back up at RISE_TIME's rate.
- **The ring and the mound** (no `predict`): as pass 60, the ring at the hero's spot at the wind-up's start and the mound
  swelling there, the mound kept through the sink. **Predict** (> 0): nothing shows (no ring, no mound, no shadow) until
  `warn` / pace seconds before the eruption; then the spot is fixed at the hero's place plus his flat velocity ×
  `predict` (EnemyManager.predict_spot), kept on the walkable map (the map's clamp_to_arena), and a red ring of the
  burrow's radius shows there for what is left of the wind-up.
- **The eruption**: up at the spot over `rise` / pace seconds through the ground-clip (pop_dust at its size, a flash ring
  at its radius, the camera's kick 1.3 with a throw, 1.0 without). The hero within radius + 0.5 m takes damage × stage ×
  host (as pass 60). With `throw_up` > 0 and a hit that landed (or an Energy Shield's catch; never an evade, the
  Invincibility bubble, an immune blink or a hero already in the air) he is thrown on his airborne arc
  (Player.trampoline_launch): `throw_up` m up, `throw_out` m away from the eruption's middle (away from where it dug in
  when he stands within 0.3 m of the middle), over `throw_air` s or sqrt(8 × up / 24) (his gravity: 2.5 m = 0.91 s,
  1.3 m = 0.66 s), the stick bending the arc by `throw_control` of his walk; nothing hits him in the air (pass 70's
  rule). Without `throw_up` the old shove of `knockback`.
- **The crowd**: every creature within radius + 0.5 m but the burrower goes `creature_up` m up (pass 69's launch: no
  walk, bite or attack in the air) over clamp(sqrt(8 × up / 24), 0.45, 1.4) s, drifting `creature_out` × (1 −
  knockback_resist) m away from the middle, and takes `creature_damage` × its max HP as it lands (no hero credit). One
  that cannot go up (the boss, an Elite or an elite-modded one, one already in the air or rising) takes it at once and a
  shove of 3 × `creature_out` m/s × its share (× 0.15 for the boss).
- **The Gila Grande's burrow**: windup 4.0 = sink 0.6 + 3.0 under unseen + warn 0.4 (on Red Canyon, pace 0.81: 0.74 +
  3.7 + 0.49 = 4.94 s), radius 5 (Garry's), damage 32, telegraph none, predict 0.6, rise 0.6, throw_up 2.5, throw_out
  4.0, creature_up 2.5, creature_out 4.0, creature_damage 0.03. Note: with a 0.49 s warning and a 5 m radius a hero who
  keeps his line is hit; the counter is to change course while it is under (the warning and the radius are the knobs).
- **The Dune Scorpion's burrow**: windup 2.3 (sink 0.6, then about 1.7 under with its ring and mound), radius 4.6,
  damage 24, telegraph ring_at_hero, rise 0.6, throw_up 1.3, throw_out 2.0, creature_up 1.3, creature_out 2.0,
  creature_damage 0.03.

## Summons (Garry: "Spawning enemies with a skill should never allow for any special enemies. Also spawn 4 more. Do the same for Tumbleweed King and the other Boss")

- A creature brought by an attack (spawn_ring; an erupt's young) never rolls its variance special (EnemyManager.
  force_plain, held by the runner round the spawn); its tints still roll.
- spawn_ring counts: the Tumbleweed King 12 → 16 tumbleweed minions, the Gila Grande 8 → 12 sand lizards, the Brander
  10 → 14 imps.

## Growing out of the ground (Garry: "currently the enemies just kind of appear. Let's make it so that they grow out of the ground. Kind of like expand out of it or something")

- **Where**: map `timeline_data.spawn_rise` {seconds, big_seconds, targetable, dust} (WaveTimeline.spawn_rise,
  SPAWN_RISE_DEFAULTS {0.45, 0.9, 0.7, 1.0}; a key or the whole block left out plays the default; seconds 0 = off),
  handed to EnemyManager.set_spawn_rise by WaveDirector._apply_mults (a run and the arena). Without a director (tests,
  tools) spawns appear at once as before. Red Canyon names 0.45 / 0.9 / 0.7 / 1.0. Level Editor: Settings → Spawning.
- **Rule**: every creature that spawns (roster, waves, events, summons, an erupt's young, the arena; not one waiting
  buried, the ambush brain) rises out of the sand over `seconds` / pace (0.56 s on Red Canyon; an Elite or a boss by its
  kind `big_seconds` / pace = 1.11 s): its spawn state lasts the whole rise (it stands, bites nobody, starts no attack).
  The lead's rule (pass 73): no weapon CHOOSES it as its target until it is `targetable` (0.7) of the way up
  (EnemyManager.targetable: nearest_index, priority_index, priority_target, random_in_range, densest_point, screen_ok =
  the crowd spots and the Gravity Gun, a beam's chain, a shot's ricochet and "ahead" picks, the Land Mine's sense, the
  Orbiter's strike), but area damage hits it all along (it stays in the crowd's grid: blasts, the revive, the Nuke,
  patches, beams, rings, ground fire, the sniper's line). A burrower rising or sinking follows the same rule.
- **Look**: the billboard's ground-clip cuts the part under the sand along a ragged line, the painting just above it
  sand-dusted (0.12 m + 0.04 × its height, 85% sand at the cut); the figure a touch stretched (1.12 → 1) as it pushes
  up; a small dust puff at its feet (4-7 puffs and 3-6 grains × `dust` × its size, only on the screen, thinned with the
  rest when the screen is busy unless it is an Elite's or a boss's); a creature 2.4 m or taller sprays sand off itself
  every 5 ticks all the way up.
- **Cost**: the cut's share rides in the instance transform's basis z column (MODEL_MATRIX[2].y, read by nothing else;
  no new buffer, no new draw call); perf_late (build six, 30 s, 504×1122, fixed 60): enemies.render 0.81-0.91 ms
  (before 0.90-0.93), enemies.sim 2.1-2.4 ms (before 2.5-2.6), draw calls 190-199 (before 191-196), ~230 creatures.

### 20.STRUCT Totem Poles and the Stranger

Every number below lives in `game/content/structures/totem_pole/totem_pole.json` unless a code constant is named.

## Totem Poles on the map
- **Count**: 10-12 a run (`params.per_map.min` 10, `max` 12; a fresh draw each run), placed **apart from the weighted
  draw**: the map's `structures.count` (9 on Red Canyon) still counts only the other structures, and every other kind
  still lands at least once. A structure without `per_map` is drawn as before.
- **Spread**: each pole is the best of `StructureManager.PER_MAP_CANDIDATES` (16) fair spots, the one farthest from
  everything already standing; a fair spot is inside `PER_MAP_BAND` (0.24-0.88 of the arena's radius), passes the
  structures' start rules (18 m off the flats' centre, `per_map.spacing` 14 m off every structure and pole, 3.5 m past
  an obstacle circle, off bushes and water; the distances relax to half as the `PER_MAP_TRIES` 500 tries run out), off
  the dry river's bed (`RIVER_CLEAR` 1.5 m past its half width) and out of every painting's cover band. Seed 11 gave
  12 poles with the nearest two 18.5 m apart.
- **Interaction**: ring radius 1.2 m (the others 2.2 m), the same 3.0 s to stand in it as most structures; no light on
  the PC (`glow` false: the ring shows it, and a dozen lights cost frames).
- **Size**: `height` 1.8 m = 75% of the other structures' median (2.4 m); the painting is drawn 1.15 x that tall, like
  every structure.
- **Signs**: at most one arm of a sign points at a pole (`params.per_sign` 1, SignField.per_sign_cap), so the arms
  still lead to the shop, the Stranger and the rest (nearest first, as before).
- **Used**: the pole turns grey (its own painting desaturated: `StructureManager.SPENT_GREY_BRIGHTNESS` 0.86,
  `SPENT_GREY_CONTRAST` 0.92, saturation 0, tinted `SPENT_GREY_TINT` 0.93) and stays standing; it is never used again.
  (`params.spent "grey"`; a structure with an `_off` painting keeps it.)
- **A returning Strongbox** (pass 64's `params.respawn`, out of play since pass 70) keeps the map's spacing from the
  other structures and only a pole's own 14 m from a pole.

## The gifts
(Pass 76 replaced the ranges in this table: see §23.TOTEM. The rolling, the feathers and the weights below still hold.)
- **Offer**: 3 gifts (`params.choices`), drawn by `weight` without putting one back, never two of one stat.
- **Amount**: even between the gift's `min` and `max`, snapped to its `step` (1% for percents, 1 max HP, 0.1 regen).
- **Feathers**: 1-3 feathers on a plank = which third of its range the amount's size landed in (TotemBoons.quality);
  looks only.
- **Duration**: the whole run; a death and a revive keep them; a new run starts without any. Each gift is its own
  source on the sheet ("Totem: Le-loo"), so two poles giving the same spirit stack (percent gifts multiply, as every
  `mul` does). A max HP gift brings the same health with it (Player.refresh_stats, as any max HP rise).
- **Nothing to refuse**: a pick is free; the menu has no leave button. A pole whose pool is empty only says its name.
- **The pool** (name, animal, stat, range, weight; 23.5 weight in all):

| Word | Animal | Stat | Range | Weight |
|---|---|---|---|---|
| Le-loo | the Wolf | move speed (mul) | +3 to +7% | 3 |
| El-kolie | the Whale | max HP (add) | +6 to +14 | 3 |
| Chet-woot | the Bear | attack damage (might, mul) | +3 to +7% | 3 |
| Thunderbird | | cooldown (mul) | -2 to -5% | 2 |
| Ol-hiyo | the Seal | pickup radius (magnet, mul) | +8 to +18% | 2 |
| Walalee | the Salmon | regen per second (add) | +0.2 to +0.5 | 2 |
| Frog | | XP gain (mul) | +4 to +8% | 2 |
| Skana | the Killer Whale | crit chance (add) | +2 to +4% | 1.5 |
| Kuuma | the Bullhead | damage reduction (armour, add) | +2 to +4% | 1.5 |
| Raven | | luck (add) | +3 to +6% | 1 |
| Se-sook | the Two-headed Serpent | area of effect (mul) | +3 to +6% | 1 |

  Area of effect (Se-sook) is the one stat past INTERFACES' list: the reference's eleventh word needed a gift, and the
  two-headed serpent "reaching both ways" reads as area. Armour is the game's damage reduction ("+3% damage
  reduction" on the plank).

### 20.CARDS The line items as fortune cards

The line items became fortune cards (Garry: "For our purposes I thought Fortune Teller Cards would work best"). Not one
number moved: every level table, weight, rarity, trade and cap is as it was; the ids are as they were (saves, quests,
analytics, the Level Editor's references). What changed is what the player reads and sees:

## Names
- Each line is a tarot card, each evolution its card "Risen" (the pattern chosen: the shortest that fits the level-up
  card's name column; "Ascendant" ran to 817 px at the card's 60 px slab where the column holds about 700, "Risen" tops
  out at 659 px with The Hourglass Risen).

| line (id) | card | evolution (id) | card |
|---|---|---|---|
| brawn | The Sun | juggernaut | The Sun Risen |
| bristle | The Thorn | cactus_hide | The Thorn Risen |
| clover | The Star | golden_horseshoe | The Star Risen |
| deadeye | The Eye | eagle_eye | The Eye Risen |
| ducktape | The Hourglass | shackles | The Hourglass Risen |
| energy_shield | The Guardian | aegis | The Guardian Risen |
| evade | The Ghost | ghost_step | The Ghost Risen |
| field_notes | The Sage | almanac | The Sage Risen |
| gold_tooth | The King | gold_rush | The King Risen |
| haste | The Tower | quicksilver | The Tower Risen |
| hot_sauce | The Devil | ghost_pepper | The Devil Risen |
| lodestone | The Magnet | mother_lode | The Magnet Risen |
| mend | Temperance | second_wind | Temperance Risen |
| mule_kick | The Storm | bucking_bronco | The Storm Risen |
| multishot | The Hydra | barrage | The Hydra Risen |
| prospector | The Miner | eureka | The Miner Risen |
| slow_burn | The Ember (new; Garry's list had none) | prairie_fire | The Ember Risen |
| stride | The Chariot | roadrunner | The Chariot Risen |
| thirst | Death | bloodthirst | Death Risen |
| tin_star | The Emperor | marshals_star | The Emperor Risen |
| vigour | The Giant | ironclad | The Giant Risen |

- The seven unlock quests of lines carry their card's name (their `name`; ids kept).
- Texts: every flavour is the card read aloud (no numbers in it); the seven cards with a card text of their own lead with
  the card and keep the rule's numbers plain ("The Star smiles on you: +10% luck a level, so ...").
- Every player-facing "Line"/"Lines" says "Card"/"Cards": the level-up/chest/shop card's word (CARD; an evolution
  "EVOLVES THE SUN"), the Collection's tab, the pause screen's Build group, the arena's ITEMS section, the hero sheet's
  "Favourite card". The code and the JSON keep `line`. Two texts that named a card by hand now read its name: the pause
  breakdown's Gold Rush source ("The King Risen +12%") and the damage log's star block ("blocked by The Emperor Risen").

## Looks (new rules)
- Every card has looks: **A** the icon it had before the cards (an object), **B** a single card tilted 10 degrees
  clockwise (the least detail), **C** the card on a small fan of card backs, **D** three cards fanned with the card in
  front, **E** the card held up in a black lace glove (the most detail). A Risen card has a gilded gold border, a base
  card a cream one.
- The look the game plays is the card's JSON `variant`: **B for all 42** (A, the old objects, no longer matches the tarot
  names: The Sun showed a flexed arm, The Star a clover). The icon of the look played is the item's icon everywhere.
- A phone may keep another look for every card (the arena's ITEMS tab, "Card look"; Save `card_look`): it wins over the
  JSON for every card that has that look; "JSON" gives each card its own back. A shelved look is never worn.
- The Level Editor's "Set every card to look X" sets the JSON `variant` of every card that has look X painted; a card
  without it keeps its own.
- The B icons are turned to one lean at install (10 degrees clockwise, measured per painting), so the 42 lean alike.
- The kind glyph on a card's plate is a tilted card with a star (was a scroll); the file is still art/ui/wanted/kind_line.png.

### 20.UIPC The hero plaque and the PC build

## The title's hero plaque (ui/TitleScreen.gd constants)
- **One size for every hero.** The plaque is PLAQUE_H = 200 px tall for every hero in every state (owned, on sale,
  locked, a hidden one previewed). It is as wide as the screen leaves: 770 px on a 1080 canvas.
  - The Hero Collections button is a 200 px square beside it (pass 70's rule kept).
  - Since nothing about the plaque changes, the hero above it, PLAY, the dots and the map line never move on a swipe.
- **One set of sizes, the same for every hero.**

  | Text | Size | Before |
  |---|---|---|
  | Name | 52 | 56 |
  | Flavour | 24, line height 29 | 24 |
  | Trait numbers | 30 | 34 |
  | Every label (trait labels, START / FAVOURITE, Details ›) | 18 | 14-16 |
  | Item plates | 84 | 92 |

  Padding inside the 5 px border: 30 px on the sides, 19 px top and bottom. The plates' column is 216 px wide, 20 px
  from the words.
- **The flavour gets at most 2 lines.** Jeżyk's is the only one that needs both.
- **The trait's numbers flow under the flavour** as "+1% CRIT / LV" pairs, each label on its number's baseline. They
  take a second row when they need it (Ironwood's two). The plates sit top right, "Details ›" bottom right.
- **At most 2 item plates** (PLATES_MAX): the start weapon and the favourite. A hero's other own weapon ("Special")
  shows only while there is room. The hero's sheet lists everything.
- **Words that do not fit are cut at the plaque's edge; nothing grows.** pass73_uipc_test fails if any hero in any state
  does not fit, so a new hero with a longer name or flavour is caught before he ships.
- **The hero above the plaque keeps clear of the title's words under a camera cutout.** His room starts 440 px down
  plus the cutout's inset (W.safe_top()). On a 16:9 screen with a 130 px inset he is drawn about 6% smaller, 570 px
  down; on a taller phone (20:9) nothing changes.

## The PC build
- **Version.** The exe's version info (FileVersion, ProductVersion) is application/config/version from project.godot
  (0.58 → 0.58.0.0). The Windows preset leaves its own version fields empty so Godot falls back to it.
  - ship.sh checks the exported exe against it (tools/exe_info.py --expect-version) and warns on a mismatch.
- **Icon.** game/icon.ico (tools/make_win_icon.py) holds 16, 20, 24, 32, 40, 48, 64, 96, 128 and 256 px.
  - Framing: the whole picture at 96 px and up; the hat about 2/3 of the tile at 40-64; 84-88% at 16-32, sharpened;
    corners rounded at 14% of the side.
  - Godot embeds 16, 32, 48, 64, 128 and 256 in the exe.
  - ship.sh makes the .ico again when game/icon.png is newer.
- **Signing is off unless tools/keys/codesign.env exists** (git-ignored).
  - With the file, ship.sh signs with tools/sign_exe.ps1 (SHA-256, time-stamped by http://timestamp.digicert.com
    unless CODESIGN_TIMESTAMP=none).
  - A signing that fails keeps the exe out of Drive. The APK still ships.
- **ship.sh deletes the old export before exporting**, so a failed export cannot send the previous exe to Drive again.

## 21. Pass 74 (v0.60): the Results show on one clock, the run dashboard

Garry's request (2026-10-14, tools/dl/p74/REQUEST.md). Each lane's rules as it wrote them.

### 21.RESULTS The chart pops in after the gold; the line, the counters and the sources together

Garry (2026-10-14): "The empty chart shouldn't just be sitting there, it should pop-in after the Coin count sequence is concluded." and "I wanted the chart, the kill count, the damage dealt and the individual damage sources sequence to play together at the same time." The rules are in §19.RESULTS ("Sequence 1", marked pass 74, and the whole show's length under "Sequence 2"); every number is a constant in `ui/ResultsScreen.gd` (LEAD_IN 0.35 s, GOLD_TIME 2.5 s, POP_TIME 0.3 s, POP_FROM 0.85, POP_BACK 2.6, POP_FADE 0.5, JOINT_TIME 3.2 s, ROW_BEAT 0.12 s, ROW_FADE 0.2 s); none changes play.

### 21.ANALYTICS The local run record (schema 2) and the dashboard

The record is not balance, but these are rules Garry never asked for in these words, so they are written down.

- **Schema 2.** `core/systems/RunAnalytics.gd` writes `schema: 2` from v0.60. The dashboard still opens schema 1 files
  (every card that needs a schema 2 key hides itself when the run has none). `analytics/SCHEMA.md` lists every key and
  says which schema added it.
- **Where a run's file goes.** Always `user://analytics/runs/<stamp>.json`. On the PC, when the game runs from the
  repo (the editor binary), also a copy in the repo: a **played** run in `analytics/runs/` (with `latest.js` and the
  index), a **tool's run** in `analytics/runs/tools/` (its own `latest.js` and index). A tool's run is a headless one
  or one started with `--script` / `-s` (smoke_run, perf_late, hell_check, captures, the gdUnit runner):
  `RunAnalytics.is_tool_process()`, written in the header as `tool`. So the dashboard opens on the last run Garry
  played, not on the last smoke run; its "Tool runs" switch shows the others.
- **How many files are kept (the lead's rule).** A **phone** keeps the newest **50** run files in
  `user://analytics/runs` (`RunAnalytics.KEEP_FILES`, by name = by start time), pruned at the end of a run (a mid-run
  checkpoint never prunes); `RunAnalytics.prunes_here()` = `OS.has_feature("mobile")`. **The PC never prunes**: the
  editor binary, the PC exe, tools and tests keep every file (a run played in the PC exe lives only in
  `%APPDATA%\Godot\app_userdata\88fits\analytics\runs`, there is room, and Garry drags them into the dashboard). The
  repo's `analytics/runs/` and `analytics/runs/tools/` are never pruned (git ignores them). The index keeps its last
  500 rows as before (`INDEX_KEEP`).
- **What reaches PostHog.** Nothing new except two event kinds through `Analytics.KIND_EVENTS`: `totem` (a Totem
  Pole's gift taken) as `totem_taken`, and `special_kill` (a coloured special killed, with `chest` and `weapon`) as
  `special_killed`. `boss_start` (PostHog `boss_started`) now also carries `hp`, `dps`, `ref`, `mult`, `window`, and an
  item event of a line carries `line: true`; no board changes. Everything else new stays in the local file only:
  `special`, `elite_mod`, `elite_kill`, `stranger`, `stranger_decline`, `totem_offer`, and every new header and row
  key.
- **Healing by source.** A row's `healed_by` names what healed the hero in that second: the source `Player.heal` was
  given (a pickup's or a structure's name: Heart, Cake Slice, Healing Well, Vulture), `lifesteal` and `level_up` (the
  hero's level patch) for the two unnamed heals (named by the signal that caused them, heard right after Game heals),
  and `other` for any unnamed heal left. It sums to `healed`. Regen (with Siesta and Deep Breath) never went through
  `Player.heal`: it is its own key, `regen`, and is NOT in `healed` (as before).
- **Specials and Elites.** `special` = a coloured variance special came (`forced` when a Special swarm made it);
  `special_kill` says whether its death dropped a chest (the crowd's special-chest count moved). `elite_mod` = a
  creature wearing an Elite modifier came; `elite_kill` = an Elite by its kind or a modifier-wearer fell (`mod` only
  for the latter). The gear-badge specials (rocketeer, Saiga Sniper, harpooner) are plain creature ids, as before;
  the Saiga Sniper's aims, shots, hits on the hero and spoiled aims are in the header's `crowd` block.
- **CSV.** Every CSV is UTF-8 with a BOM (Excel), comma-separated, numbers with a dot, lines ending CR LF, named
  `88fits_<stamp>_<what>.csv`. The rows CSV writes one line per second with a key the record leaves out as 0 (it means
  0), except `boss_hp` (empty: no boss up); the build's snapshots (stats, weapons, passive items, lines, perks, the
  creature multipliers) carry forward to every second until the next one. A list of plain values is one cell joined
  with "; ". `python tools/analytics_csv.py` writes the same rows and events CSVs for every run file in a folder and a
  history with one line per file.
- (lead) The Level Editor's kill-rate fit ("Spawned so far") reads the played runs in `analytics/runs/`; its "include
  tool runs" option also reads `analytics/runs/tools/` (server.fit_turnover), where every tool run lands since pass 74.
- (lead) The dashboard's build chips name the lines "card", as the game does since pass 73.

## 22. Pass 75 (v0.61): the Revolver's punch and its trick spin (not balance: named so they are not surprises)

Garry (2026-10-14): "Let's work on the 3D object of the revolver. The shots still feel sluggish and jerky. Let's make it
so the revolver does a little spin every now and then right after firing a shot. There should be much more visible impact
on the revolver every time it shoots as well, a bigger punch." No damage, cooldown, range or timing changed. The numbers
are the Revolver's and the Golden Revolver's `params.familiar.kick` / `params.familiar.spin` (the same in both; the game's
fallbacks `ProjectileEmitter.KICK_DEFAULTS` / `SPIN_DEFAULTS`); every other companion gun has neither and is as before.

- **What was wrong.** The old kick (every companion: 10 cm back, the muzzle tipped 0.28 rad, gone in 0.11 s) went through
  the companion's eased follow of the hero, which let about 1.5 cm of the 10 through; it showed a frame after the round
  left (the gun was placed before the pull fired); and between shots the gun pointed along the hero's line to the target
  while its rounds flew along its own, up to some 15 degrees apart, so every shot jerked it round and it drifted back.
- **The kick** (`kick`): on the frame the round leaves, never smoothed, the gun slides `back` 0.32 m along its barrel, its
  muzzle climbs `climb` 0.55 rad (31 degrees), it twists `twist` 0.14 rad (8 degrees) to a side picked at random and swells
  by `pop` 28 %; then a spring brings it back past rest and settles it: amp x e^(-`decay` 9 t) x cos(2 pi `hz` 3.2 t), so
  about 25 % past rest the other way at 0.16 s (the barrel forward, the gun a little thin) and at rest by about 0.5 s
  (`ProjectileEmitter.punch()`). A round on a gun still kicking adds half of what is left (`KICK_STACK_MAX` 2.2 kicks at
  most); a silver round (the Golden Revolver's Silver Bullet form) kicks `SILVER_PUNCH` 1.3 times as hard (its old recoil
  value 1.7 and its camera kick stay for the old path and the camera).
- **The aim**: between shots the gun points along its own line from where it circles to the target (not the hero's), and
  each round lines the barrel up with the round as it leaves; the round leaves from where the gun was before its kick.
- **The trick spin** (`spin`): after the last round of a pull, with `chance` 0.3, the gun twirls `turns` 1 full turn about
  its trigger guard (`axis` "x": the muzzle goes down first; "y" would spin it flat) in `seconds` 0.5, fast out of the
  hand and slowing to the catch (1 - (1 - f)^3), lifting `hop` 0.15 m at the middle. Never within `gap` 2 s of the last
  spin, never during a hip shot or another twirl, and only when it ends before the next pull (the weapon's clock, or a
  whole cooldown when the pull's own round was its last, must be at least `seconds` + 0.05). The twirl is heard (the hip
  shot's `w_hip_spin`). At level 1 (a pull a second) about one pull in three after the gap.
- **The muzzle pop**: both revolver visuals gained a "Flash" (one hot sphere 0.24 m, 0.06 s, orange-gold; WeaponBehavior
  .muzzle_flash fires it with the sparks, as the Tommy Gun's).
- Tests: game/tests/pass75_revolver_test.gd (8). Capture: game/tools/_p75_revolver_shot.gd (frame by frame round a pull,
  `force_spin=1`, `level=`, `zoom=`).

## 23. Pass 76 (v0.62): the Dynamite Stick, weapon looks, the Molotov's flames, the pause stats

Garry's request (2026-10-14, tools/dl/p76/REQUEST.md). Each lane's rules as it wrote them.

### 23.LOOKS Weapon-family looks

Where it lives: game/core/data/ItemLooks.gd (reading, wearing, the params overlay), Registry.item_family /
played_item_look / apply_item_looks, Save.item_looks, TextGen.weapon_nouns / thing_word, ArenaPanel._weapon_looks.
Keys: tools/dl/p76/keys_LOOKS.md.

1. **One look per family.** A weapon family (the weapon, its evolutions, every mutation of it, hero mutations
   included) plays one look at a time: the look this phone keeps for it (the arena's ITEMS tab, Save `item_looks`),
   else the weapon's JSON `variant`, else its base (`variant_base`, "A"). A kept look that has since been shelved, or
   that the weapon can no longer play, gives way to the JSON's. A wipe drops the kept looks.
2. **A look never changes the rules.** It changes names, flavour, a mutation's card text, icons, the visual scene, the
   thing words and drawing params; the stats, levels, mutations' effects and the evolution recipe are the family's in
   every look. (The engine lays any `params` key; keeping rule keys out of a look's params is the authors' rule,
   keys_LOOKS.md.)
3. **A member without that look wears its base.** A mutation or an evolution with no entry for the code the family
   plays is drawn and named as its top level (a hero mutation with an icon-only entry keeps its name and text).
4. **A look whose file is missing is left out.** An entry naming an icon or a visual that is not on disk (not imported)
   is dropped when the content is read: in that look the item wears its base. On the weapon this means the family
   cannot play it (the chips and the Level Editor leave it out).
5. **Params overlay.** A look's `params` replace the item's top-level params one level deep (a nested block is replaced
   whole); an evolution's `final` block is laid one level deeper (a look can change one of its keys and keep the rest);
   a `null` removes a key (`{"final": {"tint": null}}` drops the Golden Pineapple's gold tint in that look).
6. **Thing words.** A Lobber's card text names the look's thing ("Lobs 1 stick", "Lobs 2 sticks"; with a fire or a
   poison weapon "Lobs 2 jugs of fire", "Lobs 1 poison stick"), and so does a weapon's amount row ("Sticks 1 → 2").
   An evolution without words of its own uses its weapon's; one word given alone makes the other ("stick" ->
   "sticks"); without any, the old words ("grenade(s)", "bottle(s) of fire", "poison bomb(s)").
7. **Switching in the arena.** A tap on a family's look chip puts the look on at once: the cards, the HUD, the pause
   screen, the Collection, and a weapon of that family held now is set up again in the new look (a fresh behaviour: its
   cooldown starts over, so it may throw at once; shots already in the air keep the old model until they land).
8. **The cards (pass 73) are apart.** The fortune cards' Card look and a weapon family's look are separate choices;
   neither moves the other.

### 23.DYN The dynamite's rules, the Drifter's favourite, the Peashooter hidden

## Numbers (Garry: "a slightly bigger area of effect", "Double the knockback for any of its explosions")
- Lob Grenade (the Dynamite Stick in looks B-D) base `area` 2.5 -> **2.8** m, `knockback` 7.0 -> **14.0**.
- Golden Pineapple (Boomtown) `knockback` 9.0 -> **18.0**; its `area` stays 3.0.
- The evolution's bomblets push at the blast's knockback x 0.5 as before, so they double too (9.0); so do Frag's (Coffin
  Nails') spikes (x 0.5 of the shot's: 7.0 off the stick, 9.0 off the evolution).
- Every other number of the family is unchanged (damage, cooldown, amount, range, speed, levels, the path, the
  evolution's `final`).

## The fuse (`params.fuse` in lob_grenade's and golden_pineapple's base params, so every look has it)
- **Ground fuse**: a lobbed shot that lands and is not caught by Sticky lies where it landed for `fuse.seconds`
  (**1.0 s**), then blows as before (the same blast, area, element, Frag's spikes, the evolution's bomblets).
- **Bomblets** (the evolution's four) carry the fuse too: one that lands by no creature lies `fuse.bomblet_seconds`
  (default: `seconds`, **1.0 s**) before it blows; one that lands by a creature rides it as before
  (`sticky.bomblet_seconds` 0.7 s). (Choice, named here: every stick of the family has a fuse.)
- **Sticky**: a shot that lands within `sticky.reach` of a creature rides it as before (Sticky 1.3 s, the evolution
  1.3 s then 40% wider); no ground fuse then. A shot lying on the sand never catches a creature that walks up to it
  later (choice: nothing new was asked of Sticky).
- **The spark** burns at the shot's fuse tip in flight, on the sand and riding a creature, and goes out
  `fuse.out_before` (**0.5 s**) before the shot's blast, with a small wisp of smoke: on the sand when 0.5 s of the
  fuse is left, riding when 0.5 s of the ride is left. A ride cut short (its creature dies) blows with the spark still
  lit. A fuse no longer than out_before goes out as the shot lands. At most 40 sparks are drawn at once.
- **Lying**: with `fuse.lie` (true) a long model lies on its side (a model 1.25x taller than wide is laid down; one long
  along X or Z lies as it is; a squat one, a crate, sits as it is), turned along its throw give or take 20 degrees, on
  the slope; still (no spin, no slide). A shot Sticky catches rides its creature in that same pose (its flight's spin
  stopped), so the spark sits up at the fuse tip. A lying shot keeps its landing spot claimed so the next bomb picks
  another crowd, then LANDED_CLAIM (2 s) after the blast as before.
- The spark's look (data: `fuse.spark {color #FF9A2E, size 0.13}`): two glows (3.4x and 1.7x its size), a four-point
  twinkle turning in the camera's plane (3.8x long), a white-hot core, little sparks flung off about every 0.04 s; a
  bomblet's at 0.6x. Drawn over everything (like Sticky's blinker).
- The fuse delays the damage; the cooldown, the DPS estimate and the pause rows are unchanged.

## Mass mini crits (`params.mass_mini {min_hits 9}`, the Drifter's Fire in the Hole)
- A blast of the weapon's shot (its ground fuse, its Sticky ride, **each bomblet on its own**) that catches **9 or more**
  creatures ("more than 8") deals **every one of them a Mini Crit** (EnemyManager.HIT_MINI: x(1 + (crit_damage - 1) x
  0.5) = **x1.5** with the default x2 crit damage). Never instead of a full crit: a creature whose hit rolls a full crit
  takes the full crit.
- "Caught" = the creatures the blast strikes, counted before it strikes: alive, not dying, not hidden (burrowed) or held,
  within the blast's radius (the shot's area; a Sticky ride's blast_mult included). Frag's spikes, the Overkill splash
  and a land blast never count and never mini-crit by it.
- The evolution keeps it (the path and the hero's own stay on the evolved form).

## The Drifter and the Peashooter (Garry: "Make a Grenade The Drifters new fav Item", "Peashooter ... Hide it for now")
- The Drifter's `favourite_weapon` is **lob_grenade** (favourite_bonus unchanged: found at level 2), offered to him
  whatever its unlock quest (CardPool.offer_weapons, pass 62). His hero mutation is **Fire in the Hole** (rare, weight
  8, Fan the Hammer's shape), his only one (pass66_shape_test).
- The **Peashooter** is `hidden` (out of the offers, chests, the Stranger, the Collection's play list); its evolution
  (Pea Cannon) and its path hide with it (Registry.is_hidden). **Fan the Hammer** is `hidden` too. Both stay in the
  content: `Registry.start_weapon_for` and the arena still fall back to the Peashooter, tools may hand it out.

### 23.DYNART The dynamite looks (Dynamite Stick, Dynamite Bundle, Coffin Nails, Sticky, Fire in the Hole, Boomtown)

No number of the rules changes in a look (lane DYN owns the dynamite's rules: the fuse, the knockback, the area, the
mass mini crits; pass76_dynart_test checks every look leaves every rule as the grenade has it). What a player sees:

## The looks (game/content/{weapons/lob_grenade, mutations/new_equipment|frag|sticky|fire_in_the_hole, evolutions/golden_pineapple})
- **A** is the grenade (the top-level fields, today's art). Fire in the Hole has a painted grenade icon now (the olive
  grenade in a blast ringed by nine gold stars) in place of its placeholder.
- **B, C, D** are the dynamite, `fresh` until Garry approves one; the family plays the weapon's `variant` (**B**), or the
  look a phone keeps (the arena's ITEMS "Look" chips, Save.item_looks); Garry switches back to the grenade with A.
  - **B, classic paper stick**: a plain paper stick with dark printed rings near its ends, cream end plugs, a pale cord
    fuse with a charred tip; the bundle is three sticks in black tape; Boomtown is a wooden crate trimmed in gold, packed
    with nine red sticks, one fuse rising from the middle one (it sits up when it lies).
  - **C, chunky cartoon stick**: a fat stick with round shoulders and a narrow cream label in thick black borders, a
    thick black curly fuse; the bundle is four sticks tied with rope and a bow; Boomtown is a powder keg in four gold
    hoops with four red sticks strapped round it (it lies on its side).
  - **D, waxed miner's stick**: a slim glossy stick with crimped paper ends, a dark printed band with cream stripes, a
    silver blasting cap and a tarred fuse; the bundle is seven sticks in copper wire; Boomtown is a gilded bundle of
    seven red sticks under a brass cap, a gold band with a gold star.
- **Names, the same in B, C and D**: Lob Grenade -> **Dynamite Stick** (things: "stick" / "sticks"); New Equipment ->
  **Dynamite Bundle** ("... and a bundle of sticks 35% bigger."); Frag -> **Coffin Nails** ("The burst throws six coffin
  nails out past the blast."); **Sticky** and **Fire in the Hole** keep theirs (new icons only); Golden Pineapple ->
  **Boomtown** (things: crate(s) in B, keg(s) in C, bundle(s) in D; its flavour keeps 1.3 s, 40%, 12 and 4).
- **Colour rule**: the stick (and the bundle) is sandy brown; **Coffin Nails colours it red**, whichever came first, the
  bundle or the nails (the weapon's look names `models {stick|bundle: {tan, red, tip}}`; Dynamite Bundle's look sets
  `model_form: "bundle"`, Coffin Nails' `model_colour: "red"`).
- **How a shot moves** (the models, not a rule): the stick and the bundle fly across their flight, so they tumble like a
  thrown stick (a shot spins about the way it flies); they lie along their throw (DYN's lie); the spark burns at the fuse
  tip and goes out half a second before the blast.
- **Sticky in the dynamite looks** (Garry: "No need for visual changes to the 3d object"): the stick keeps its own paper
  (no amber resin tint) and its fuse spark shows alone (no red blinking light); its look entry removes both
  (`params: {tint: null, look: null}`). Its icon shows the stick in amber resin. In the grenade look (A) Sticky is still
  the glossy amber grenade with its blinking light.
- **Boomtown draws its own colours** in the dynamite looks (`params.final.tint: null`: the Golden Pineapple's gold tint
  is the grenade look's); the gold is the model's own trim.
- **Boomtown's bomblets** are small copies of Boomtown's own model (half size: small crates, kegs or gilded bundles):
  the Lobber has no separate bomblet model (no key for it); named here so it does not read as a bug.
- **Materials**: the paper is matte (`model_metallic` 0, `model_roughness` 0.85 B / 0.8 C / 0.6 D, the waxed one a
  little glossier); Boomtown 0 / 0.7 B, 0 / 0.65 C, 0.1 / 0.45 D. The papers were picked in the game's light on the sand
  (sandy brown that still reads against the sand: B #A47C52, C #B38755, D #A9825A; red B #B32A22, C #C22A20,
  D #B02A22). The game reads a GLB's vertex colours as sRGB values: tools/blender_dynamite.py writes them so.

### 23.MOLO The Molotov's flame looks

No rule changes: every number below is a drawing number. The Molotov, Methanol and the Moonshine burn, deal damage, last
and spread exactly as before in every look (A, B, C, D).

- **The flame on the wick** (`params.wick_flame`, WickFlames): stands at `offset` turned and scaled with the shot (so it
  follows the wick as the bottle turns), upright along the camera's up, leaning back by `lean` x the flat speed
  (0.045 s), up to 25% taller at 12 m/s flat. Per look: B torch 0.62 m, C streamer 0.6 m (tail 0.12 s, rising 1.4 m/s),
  D cartoon 0.55 m; the Moonshine's x1.15. Embers: B 10/s, C 8/s, D 5 sparks/s, living `life` x 0.7..1.25 (0.25-0.3 s),
  flung with 35-75% of the bottle's flat speed (so they scatter round the flame instead of lining up behind it).
- **Tumble**: B and D turn end over end at 1.0 turn a second, leaving the hand neck up; C flies base first (its visual
  turned a quarter) spinning about its own length at the old 12 rad/s; A keeps the old spin about its flight line.
- **The pool's flames** (`params.pool_flame`): the same flames as before in number and height (ElementCloud's clock and
  0.6 + r x 0.45 m, 0.6..1.9, x0.75..1.2) times the look's `size` (B/C torch 0.78, D cartoon 0.66 living x1.1), drawn by
  WickFlames instead of Fx. They are thinned in their own pool (256): past 40% of it a third of new ones are dropped,
  past 75% two thirds; the two at landing never are. (Fx's tongues were thinned by the shared effect budget, which the
  burning creatures fill, so today's pool looked sparser in a crowd.) The burning creatures' flames are unchanged.
- **Draw cost**: one MultiMesh (704 + 256 instances, one draw call, one shader) for every wick flame, streamer piece,
  ember, spark and pool flame of every look; a torch or cartoon bottle is one instance, a streamer about 8-12.
- **Which look plays**: the family plays `molotov.json`'s `variant`: **B** (the torch; lane MOLO's pick by eye);
  Save.item_looks (the arena's chips) wins over it. A, C and D stay playable (every new entry is `fresh`).
- **Warm-up**: the wick flames' MultiMesh is made under the spawn beam only when some played look wears `wick_flame`
  or `pool_flame` (otherwise at the first such bottle).

### 23.UI The pause Stats tab, the Results unlocks, the Revolver's tracer

## The pause Stats tab (ui/PauseScreen.gd, core/systems/StatSources.gd)
- **The start.** Run.start takes a snapshot of every stat on the hero's sheet once it is built (`Run.start_stats`: level
  1, the Upgrade board, nothing taken yet) and the hero it was taken for (`start_stats_hero`). `Run.start_stat(stat)`
  reads it; with no snapshot, or after the arena swapped heroes, a fresh level-1 sheet (`hero_sheet(character, 1)`).
- **Changed.** A stat is marked when it differs from the start by at least what its display shows: a percent stat 0.05
  points, a number, seconds or metres 0.05, a count 1 (TextGen.player_change returns "" below that).
- **The mark.** A pill before the value: a drawn triangle the way the number went (up/down), the amount, sage
  (W.SAGE) when better, rock (W.ROCK) when worse. Better/worse is TextGen._worse: higher is better except LOWER_BETTER
  (cooldown, shield_delay, regen_delay, star_block_every, gem_sweep_every), so a cooldown cut is green.
- **The amount.** As a share of the start (now / start - 1) when every effect on the stat multiplies (op "mul"):
  "Cooldown 90% -> 76%" reads "15%", as its "The Tower -15%" row does; otherwise in the value's own unit (a percent stat
  in points: crit chance 1% -> 9% reads "8%"; max HP with a Totem's flat +10 reads "12"). Whole numbers from 10 up,
  else to a tenth.
- **Unchanged** cells are dimmed (ink-soft at 62% alpha). Kills is a count: never marked, never dimmed, never opened.
- **Values.** The hero's cooldown and duration read as a percent of normal ("100%", "76%"; they read "1.00 s" before:
  they are multipliers on the hero's sheet). TextGen.PLAYER_SHARE.
- **Cells.** Max HP, the 19 of PauseScreen.STATS, the shield while it is above 0, then every other stat that moved since
  the start, in StatSheet.PLAYER_DEFAULTS order (then any other the sheet names); a stat said in words (TextGen kind
  "word", the Magnet's pulls) or as a rule sentence ("rule") never gets a cell. Kills last.
- **Open.** The first stat that moved (grid order) opens by itself, max HP when none did; a tap opens a stat's sources
  under its row, a tap on the open one closes them; the choice holds while the run lasts. A tap on a tab opens it at its
  top; an opened card scrolls into view without pushing its row off the top.
- **Sources.** "At the start": the base, the hero's flat trait (hidden heroes), his signature stat's level-1 step, the
  Upgrade board's ranks (one row a talent form: "Grit · Padding rank 3"). "This run": the signature stat's growth (the
  other level - 1 steps, "Magic Hour · Lv 12"), cards and passive items (with their level), a favourite's bonus, perks,
  mutations, Totem gifts (one row a spirit, "×2" when taken twice), the Stranger's cut, momentum, running bonuses under
  the item that gives them (Hot Streak, Desperado, Steady Hand, Adrenaline, Gold Rush, Heavyweight, Last Stand, Crescendo,
  Overdrive), then timed buffs with their seconds left. Rows merge by source id and op; a "mul" compounds as the sheet
  folds it (three Padding ranks of +10% are +33%); a row worth nothing is left out. Run amounts in a dark sage
  (#4a6b3c) or dark rock (#a03a22); start amounts in ink-soft, dark rock when they pull the wrong way.
- **Weapon-aimed effects** (target all_weapons, weapon:<id>, tag:<tag>) are not in the hero's numbers (get_stat's player
  scope never folded them) and are no longer listed in his breakdown either (StatSheet.breakdown in player scope).

## The Results unlocks (core/systems/QuestTracker.gd, ui/ResultsScreen.gd, game/Game.gd)
- A quest whose reward is a hero on sale (availability "purchase") the player already owns (bought, or the developer
  menu's "own every hero") is marked done quietly: never returned by check_all, never in "Unlocked this run", never on
  the in-run banner, never in "Unlock progress" (QuestTracker.owned_reward). A free hero (availability "available") is
  owned exactly when his quest is done, so his quest still announces him.
- FOR SALE (the Results stamp, "A new hero", the in-run "A NEW HERO IS FOR SALE") only while Registry.hero_state says
  "buyable".
- "Unlocked this run" lists only what the run's own checks completed (check_all(true)); Run.start empties it, and the
  title's quiet check (check_all(false)) no longer adds to it (pass 44 let the next Results list the title's quiet
  completions as "this run").

## The Revolver's tracer (content/weapons/revolver/revolver.json, core/systems/ProjectileManager.gd)
- tracer_color #7A1F17, tracer_alpha 0.85, tracer_size 1.35 (0.9 before; Silver Bullet's and Venom Rounds' shots are
  that thick too). The beads are drawn lighter than their hex (the 3D pipeline lifts them): #7A1F17 shows on the sand as
  a dim brick red (about #AF4E2F); #A33A2E, the brief's first pick, showed salmon (about #D6784F).
- `tracer_clear` (new weapon param, metres, default 0): no bead within it of the hero on the ground plane. The Revolver
  1.1 (its companion gun orbits at 1.2 m; a shot fired past him laid dim red beads on his coat that read as blood).
- Tracer colour order: a mutation's own tracer_color (its look: Toxic Peas, On Fire), then Silver Bullet's pale blue,
  then the weapon's element (fire orange, poison green), then the weapon's own tracer_color (its plain colour: the
  Revolver's dim red), then gold. The Golden Revolver has its own params: unchanged (silver, size 0.9).

### 23.TOTEM The Totem Pole's gifts reassessed

Garry (2026-10-14): "also some of the upgrades are very powerful, can you reassess them please". Where the numbers live:
`content/structures/totem_pole/totem_pole.json` `params.boons` (min, max, step, weight per gift); the rolls and the
feathers: `core/systems/TotemBoons.gd` (unchanged). Table maker: `python tools/dl/p76/TOTEM/gift_table.py`.

## The rule (new)
- **A gift's average is about 0.4 of one level of the line item for its stat**, so a map's 10-12 gifts come to about
  one maxed line (4 levels) in all. Pass 73's gifts averaged 0.67 of a level (10-12 gifts = 6.7-8.1 levels, about two
  maxed lines, with no slot taken); now 0.40 (4.0-4.9 levels).
- **Measured against** the line item that carries the stat: The Chariot (move speed +6% a level), The Giant (max HP +8% a
  level: 8 HP on the base 100), The Sun (attack damage +10%), The Tower (cooldown -8%), The Magnet (pickup radius +40%),
  Temperance (regen +0.45/s), The Sage (XP +8%), The Eye (crit chance +8%), The Emperor (damage reduction +5%), The Star
  (luck +10%). No line raises the area: the Serpent is measured against Reach (a passive item, +8% a level).
- **Mul stats in multiplier space**, because mul effects compound (StatSheet: (base + adds) x the product of (1 + v)):
  0.4 of a level of +m is (1 + m)^0.4 - 1, so ten average gifts of one stat are that line maxed, (1 + m)^4. An add stat
  is 0.4 x its level. A roll's average is the middle of its range (TotemBoons.roll draws evenly and snaps to the step;
  the two ends are half as likely, so the mean stays the midpoint).
- **Ranges**: whole steps of what the screen shows (TextGen writes a mul as whole percents, so every mul gift steps 1%:
  a 2.5% would read "+3%"); the smallest roll at least a third of the biggest (pass 73's "small but not nothing"); a span
  of steps that is not a multiple of three (2, 4 or 10 steps), so no roll sits exactly on a third of its range, where a
  rounding error picked the feathers (pass 73's Thunderbird -3% hung 1 feather while the Raven's +4%, at the same place
  in its range, hung 2), and 1, 2 and 3 feathers all come up (25/50/25% over 2 steps, 37.5/25/37.5% over 4, 35/30/35%
  over the Seal's 10).
- **Kept**: the weights (3, 3, 3, 2, 2, 2, 2, 1.5, 1.5, 1, 1), the feathers' rule (TotemBoons.quality: the third of its
  range a roll fell in), `per_map` 10-12, `spacing` 14, `choices` 3, the words.

## Choices where the rule leaves room
- **Wolf** +1-3% (0.34 of a Chariot level), not +2-4% (0.51): whole percents allow nothing nearer 0.4 with three values,
  and move speed was the gift Garry felt most.
- **Whale** +2-6 HP (average 4): 0.5 of the Giant's +8 HP on a fresh 100 HP hero; an add gift does not grow with the
  hero's own HP adds while the Giant's % does, so once a hero has grown (Astro +2 HP a level) it is about 0.4. The
  Giant's damage reduction (+5% at its 2nd and 4th levels) is left out: the Whale gives HP only.
- **Thunderbird** -2 to -4% (0.37), not its old -2 to -5% (0.43, nearer the rule): a 3-step span puts -3% on the third.
- **Killer Whale** +2-4% was on the rule already (0.38): unchanged.
- **Seal** goes UP a little (+8-18% -> +10-20%): it was under the rule (0.36 of a Magnet level).

## Before and after
| Gift | stat (op) | weight | in an offer | line item, one level | 0.4 of it | pass 73 range (avg) | levels | pass 76 range (avg) | levels | feathers 1/2/3 |
|---|---|---|---|---|---|---|---|---|---|---|
| Le-loo, the Wolf | move_speed (mul) | 3 | 39% | The Chariot +6% | +2.36% | +3 to +7% (+5%) | 0.84 | **+1 to +3% (+2%)** | 0.34 | 25/50/25 |
| El-kolie, the Whale | max_hp (add) | 3 | 39% | The Giant +8% (8 HP of 100) | +3.2 | +6 to +14 (+10) | 1.25 | **+2 to +6 (+4)** | 0.50 | 37.5/25/37.5 |
| Chet-woot, the Bear | might (mul) | 3 | 39% | The Sun +10% | +3.89% | +3 to +7% (+5%) | 0.51 | **+2 to +6% (+4%)** | 0.41 | 37.5/25/37.5 |
| Thunderbird | cooldown (mul) | 2 | 28% | The Tower -8% | -3.28% | -2 to -5% (-3.5%) | 0.43 | **-2 to -4% (-3%)** | 0.37 | 25/50/25 |
| Ol-hiyo, the Seal | magnet (mul) | 2 | 28% | The Magnet +40% | +14.4% | +8 to +18% (+13%) | 0.36 | **+10 to +20% (+15%)** | 0.42 | 35/30/35 |
| Walalee, the Salmon | regen (add) | 2 | 28% | Temperance +0.45/s | +0.18 | +0.2 to +0.5 (+0.35) | 0.78 | **+0.1 to +0.3 (+0.2)** | 0.44 | 25/50/25 |
| Frog | xp_gain (mul) | 2 | 28% | The Sage +8% | +3.13% | +4 to +8% (+6%) | 0.76 | **+2 to +4% (+3%)** | 0.38 | 25/50/25 |
| Skana, the Killer Whale | crit_chance (add) | 1.5 | 21% | The Eye +8% | +3.2% | +2 to +4% (+3%) | 0.38 | +2 to +4% (+3%), unchanged | 0.38 | 25/50/25 |
| Kuuma, the Bullhead | damage_reduction (add) | 1.5 | 21% | The Emperor +5% | +2% | +2 to +4% (+3%) | 0.60 | **+1 to +3% (+2%)** | 0.40 | 25/50/25 |
| Raven | luck (add) | 1 | 15% | The Star +10% | +4% | +3 to +6% (+4.5%) | 0.45 | **+2 to +6% (+4%)** | 0.40 | 37.5/25/37.5 |
| Se-sook, the Two-headed Serpent | area (mul) | 1 | 15% | Reach +8% (passive item) | +3.13% | +3 to +6% (+4.5%) | 0.57 | **+2 to +4% (+3%)** | 0.38 | 25/50/25 |

"in an offer": the chance a gift is one of an offer's three (200,000 simulated offers; the weights are unchanged, so
these are pass 73's too). "levels": the average roll in levels of its line item. Steps: 1 HP, 0.1 regen, 1% for the rest.

## What a run gets
- Offer-weighted average gift: 0.67 -> 0.40 line levels. A map's 10-12 gifts: 6.7-8.1 -> 4.0-4.9 levels (one maxed line
  is 4).
- The gift taken whenever offered (12 poles; mul gifts compound): the Wolf (4.7 picks) +26% -> +10% move speed; the
  Whale (4.7) +47 -> +19 max HP; the Bear (4.7) +26% -> +20% attack damage; the Thunderbird (3.3) -11% -> -10% cooldown;
  the Seal (3.3) +50% -> +59% pickup radius; the Salmon (3.3) +1.16 -> +0.66 regen/s; the Frog (3.3) +21% -> +10% XP; the
  Killer Whale (2.6) +7.7% crit (same); the Bullhead (2.6) +7.7% -> +5.1% damage reduction; the Raven (1.8) +7.9% ->
  +7.0% luck; the Serpent (1.8) +8.0% -> +5.3% area.
- Cap: damage reduction is capped at 0.8 (Player.gd:910). Twelve Bullheads at their best roll are +36%; with a maxed
  Emperor (+20%), its Risen (+25%) and a maxed Giant (+10%) a build could pass the cap, which holds.

## Tests
- `game/tests/pass73_struct_test.gd` re-pinned on purpose: `test_an_offer_is_three_different_stats_each_rolled_in_its_range`
  saw the Whale's 6 and 14; it now reads the Whale's min and max from the pool (2 and 6 today).
- New `game/tests/pass76_totem_test.gd` (5): every gift's average 0.3-0.55 of a level of its line (the line named per
  stat; mul in multiplier space); a map's gifts 3-5.8 levels in all (offer-weighted mean 0.33-0.47); every roll reads as
  the amount it gives (mul gifts whole percents); every gift hangs 1, 2 and 3 feathers by its third, its span never a
  multiple of three steps, its smallest roll at least a third of its biggest; the weights' order and the feathers' rule
  kept, the Bullhead far from the damage reduction cap.

## For the lead
- BALANCING.md §20.STRUCT ("The gifts", the pool table) still lists pass 73's ranges: the new ones above replace them
  (the weights, steps and the feathers' rule there stay true).

### 23.ICON The Level Editor's icon guard, Solenne's badge back

These are editor rules (no game numbers change). The constants live in tools/level_editor/server.py's "pass 76 (lane
ICON): the icon guard" section.

1. **An installed icon never overwrites a file.** An icon install (an `icon_cands` or `hero_badge` candidate, from a
   look's picker, the Jobs tab or an item's candidates) writes a file of its own: `<id>_icon[_<letter>]_<tag>_c<k>.png`
   (letter = the look code's last part, none for the base; tag = the last four letters/digits of the painting job's id;
   k = the candidate), then `_2`, `_3`, ... when that name (or its `.import`) is taken. The job form's named "Icon file"
   is used instead when no file has it. The pick tools refuse to write over another picture even if told to (they add
   `_2`; a file holding the very same bytes is reused). Title cut-outs are not covered (they still overwrite
   `hero_<id>_<x>.png`, backed up to tools/dl/backup/title/).
2. **The look in play and the base ask first.** An icon change (install, "Use for this look", "Revert icon") of the
   look the game plays (the JSON's `variant` when playable, else the base; a weapon family member: the look its weapon
   plays, lane LOOKS' `family_member_play`) or of the base look (`variant_base`; an asset without looks: its own icon)
   is refused with 409 `confirm_needed` until it is sent with `confirm: true`; the page shows the question (now -> new,
   file names, played, base, the looks that share the base's icon). Any other look changes at once. A job's landing
   never asks (the install was confirmed when it was queued).
3. **History.** Every change of a look's icon adds one step to `icon_history` beside the key it changes (a look: in
   its entry; the base: at the JSON's top level next to `icon`), at most **40** steps (`ICON_HISTORY_MAX`; the oldest
   dropped, their pictures stay on disk and in the backups).
4. **Copies.** Before an icon changes, the picture the look showed is copied to
   `tools/level_editor/backups/<id>/<stem>_<YYYYMMDD-HHMMSS>.png`, once per picture (SHA-1; a picture already there is
   not copied again). Before a `look`, `item_icon` or `install` job runs, every icon of its asset is copied there the
   same way. These copies are never trimmed (the JSON backups keep 30).
5. **Revert icon** undoes the last step: the key gets back what it said (a look's `icon_picked` as it was; a look that
   had no icon of its own drops its `icon` and shows the base's again). When the file a step names was painted over
   since, its copy is put back into the folder under the copy's own name. With no history: a look whose own icon was
   picked (made before pass 76, like Solenne's SOL-B) loses it; anything else is "nothing to revert" (409).
6. **A picked icon stays picked** through the look's re-rolls: the server's `merge_look` keeps the entry's picked icon
   (a re-roll names its front crop `<id>_icon_<x>.png`), and gen_art / gen_ctl keep the entry's own picked file.
7. **The gallery ("All icons on disk")** lists one tile per picture (SHA-1): the folder's `<id>_icon*.png` and any file
   the JSON names as an icon, `backups/<id>/`, removed looks' files under `backups/deleted/<id>/<stamp>/`, and the older
   tools' copies under `tools/dl/backup/icons*/` (only files named `<id>_icon*`). "Use for this look" on a copy puts it
   back into the folder under its own name (a fresh one when taken); a folder file with the same bytes is used instead.
8. **A candidate may be named by its id or its label** (`2` or `c2`; a title `1` or `#1`): both install the same
   candidate (the Jobs tab and an item's candidates sent the label, and gen_icon_cands then looked for `<key>_cc2.png`).

### 23.LEAD The lead's fixes

- The Stranger's screen under a camera cutout: the deal panel and the quote rise by what would overlap WALK AWAY / DEAL (24 px above them) and the portrait shrinks by as much, never below 0.6 of its size (ui/StrangerScreen.gd `_fit_layout`, again a frame after it opens).
- The arena's hero tiles read `Registry.hero_state`: "locked", "for sale", or nothing for an owned hero (a hero bought before his quest was done read "locked").

## 24. Pass 77 (v0.63): the run sim (not balance, named so they are not surprises), Down! without gold

Garry's request (2026-10-14/15, tools/dl/p77/REQUEST.md). Each lane's rules as it wrote them.

### 24.SIMRUN One simulated player and its bot

For BALANCING.md §24 (the lead). Code: `game/tools/sim_run.gd` (the run, the screens, the goals, the output) and
`game/tools/sim_pilot.gd` (the legs). Nothing here changes the game for a player: these are the simulated player's rules.

## 1. The run it plays
- One headless run of the real game (Game.tscn) at a fixed 60 fps (`--fixed-fps 60`: a weapon fires at most once a frame),
  launched from memory (`Run.launch_override`): hero, map, `map_seed = seed`, the recorder in memory.
- The save is sandboxed before anything changes (Save.begin_sandbox, never ended: nothing reaches the disk), with:
  - **every unlock quest done** (`unlocks=all`, the default): the whole content is in the card pool, whatever user
    folder the process runs in (`unlocks=save` keeps the folder's save);
  - **the Upgrade board** from `board` exactly as difficulty_probe writes it: its FORMS (grit 0, drive 0, stride 0,
    fortune 0, choice 0, nerve 1, study 1, spite 1; `grit=`/`spite=` change those two), ranks by `rank_for` (a whole
    number gives every talent that many; a half alternates ceiling/floor in FORMS order: board 1.5 = 12 of 48 ranks);
  - or, given `talents=` (Garry: "specify the hero and what upgrades they have"), the board talent by talent: each
    talent's ranks with each rank's form, written as Save.data.talents[id].picks (what Save.talent_picks reads, so the
    game folds it exactly as a bought board); a talent left out has no rank; it replaces `board=`.
- **Settings forced** to a player's: fixed camera (north up), ranged weapons pick only what is on the screen, pierce
  drop-off on, hints off, floating damage numbers off, debug mode off.
- **The screen** the ranged weapons test against: a 504 x 1122 window with the canvas expanding as on Android, so the
  visible canvas is 1080 x 2404 (a 9:20 phone). Headless Godot otherwise gives a 64 x 64 window and the PC's "keep"
  aspect (1080 x 1920, 9:16: a view 25 % wider than the phone's).
- **Seeds**: the player's seed gives the map layout (map_seed = seed; barrels and signs follow it), the global
  randf()/randi() stream (hash(seed, "global")), the level-up offers' and the chests' draws (CardPool.rng,
  hash(seed, "cards")), the director's dice (hash(seed, "director")), the creatures' and the pickups' own dice
  (hash(seed, "EnemyManager"/"PickupManager"), set right after their _ready), the bot's choices (hash(seed, "bot")) and
  the kite's strafe (hash(seed, "pilot")), and since 2026-10-15 where the structures stand (StructureManager.setup:
  hash(seed, "structures"); the barrels, placed clear of the structures' rings, follow) and the Totem Poles' gifts
  (Run.totem_rng, hash(seed, "totems")). **Stays random**: cosmetic dice (blood, the coin streams' flights, shines).
  seed + k gives each player his own map. **Repeatable**: in the fast mode a seed replays exactly (seed 66 to 5:00 and
  seed 73 to 10:00, twice each: every row of kills, damage, XP, health, level, crowd and gold, and every pick, equal);
  in the full game (`fast=0`) it does not (two runs of seed 66 parted at 0:08): the sounds' gaps and free players run
  on real time and each sound played draws its pitch from the global dice, so how many draws come before the next crit
  or drop hangs on the machine's speed. Same seeds on two versions of the content are a paired comparison only in the
  fast mode.
- **The fast mode** (`fast=1`, the default; Garry: "why it is that the sims are taking so long?"): the launch's
  `sim_fast` sets Run.sim_mode for the run, and the work that only draws or plays is skipped while every rule runs:
  the crowd's, the shots' and the pickups' drawing (EnemyManager, ProjectileManager, PickupManager `_process`: their
  `_render`, trails, sparks, wick flames), the ground marks' drawing (Telegraphs keeps ageing them: the bot reads the
  warnings), every Fx effect (particles, notes, blood, bolts, trails, wind), every sound (Audio.play), the HUD's and the
  damage numbers' frames, the hints. Nothing it skips moves a number. Measured: see the history notes (wall time
  before and after, and the same seeds both ways).
- **The run's clock** (both modes, since 2026-10-15; the launch's `sim_clock`, Run.sim_clock): a headless run goes 2.5
  to 4.5 times faster than real time (the full game about 2.7, the fast mode about 4.3), so a rule that counts real time
  plays differently in a sim than on a phone, where real time is game time. Two did: an Orbiter's repeat hit on the same
  creature (its `cooldown`, 0.25 s for the Orbit Saws: Orbit Saws, Branding Iron, Rattlesnake and their evolutions) and
  the sheet's rebuild throttle (DESPERADO_REBUILD_MS, 250 ms: Desperado, Steady Hand, Hot Streak). In a sim both now
  count the run's own clock (Run.rule_seconds = buff_clock), so they play at the phone's pace. So does the weapons'
  companions' bob (the familiars, the stray gun, the salt shaker: ConeWave, GravityGun, LaserBeam, MissilePod,
  ProjectileEmitter, SaltShaker, WeaponBehavior), a look that reached a rule where the companion is where the weapon
  fires from (the Big Mouth's beam starts at its mouth, LaserBeam.muzzle). Before this every sim
  (the difficulty probe's too, which keeps real time: its numbers stay comparable with pass 62/64's) had orbiters hitting
  a creature 2.5 to 4.5 times less often than a phone, and the fast mode's less often than the full game's.
- **The fast mode against the full game** (the same seeds both ways; a seed never replays across the two, since the
  full game's looks draw from the global dice, so only the spread over seeds compares them): before the run's clock the
  full game pulled ahead from about 5:00 (level +3.7 +- 1.3 at 7:00 over 28 pairs) and further in the first boss's
  fight, the fast player's boss living longer mostly where both held an orbiter (its saws hit a creature 1.6 times less
  often in the faster run); after it, ten pairs to 10:00 (seeds 71-80) end level: level +0.2 +- 1.4, XP +230 +- 1,640,
  kills -40 +- 390 at 10:00 (full minus fast), the fast player a little ahead from 5:00 to 7:00 (level -0.7 +- 0.3 at
  5:00, -1.4 +- 1.2 at 7:00), gone by 8:00. So the fast mode is the default; `fast=0` stays for a spot check, and a fast
  batch is never mixed with a full one in one comparison.
- **It ends** at the first recorder row at or past `limit` play seconds ("limit"), when Down! is given up ("death"), or
  by the watchdog: a screen (or a pause with none up) left more than 10 s of the frame clock ("stuck:<screen>"), the
  hero down more than 12 s with nothing asking ("stuck:down"), the wall clock past `wall` s ("stuck:wall"), no game
  after 120 s ("stuck:no_game"). The output is written in every case.

## 2. The legs (every unpaused frame)
In this order of precedence: a goal, else the sweep (the kite leaning towards pickups), with the red-ring dodge on top.

### 2a. The kite (pass 62's difficulty probe autopilot, moved to sim_pilot.gd unchanged; the probe still uses it)
- Keeps the nearest creature about KEEP 4.5 m off: under FLEE 2.6 m it flees (away + 0.5 sideways), under 4.5 m it
  drifts sideways round the crowd (sideways + 0.35 away), beyond it closes in (sideways - 0.4 away); creatures within
  10 m push away by 1/d^2; nothing near: walks to the nearest creature; none at all: a slow wander.
- The sideways drift flips every 3 to 7 s (its own seeded dice).
- Danger: a hammer giant, a Bull Beetle, any Elite or boss within 7 m pushes 6x a creature's (1/d^2), a hostile rocket
  within 10 m adds 3 straight away from it; while that push is over 0.4 he flees it (+ 0.25 sideways).
- Near the wall: pulled to the arena's middle from 45 % of its radius out, up to 1.5 x 1.4.

### 2b. The sweep (the run sim's: a player gathering his gems; the probe has none)
- The spot: every gem, coin and vacuum gem lying on the sand (PickupManager's grid of resting pickups, 4 m cells) past
  0.9 of his magnet's reach and within LURE_R 60 m (the whole field) is summed by cell; the cell with the most
  worth / (distance + 2)^1.5 wins, its worth-weighted middle the spot. Worth: a gem its XP, a coin 2 per gold, a vacuum
  gem 400; a power-up on the ground counts as 40 (a heart only while he is under 70 % of his health). Picked again every
  6 frames.
- The lean: 2.0 against the kite's 1 when no creature stands within 1.2 m of the way over its first 4 m (lane clear),
  0.3 of that (0.6) when one does, none while the danger push of 2a is over 0.4; all times his health's say: whole at
  70 % of his health or more, none at 35 % or less, linear between.
- Why: the kite alone keeps him off the crowd's front, where the gems fall: measured at 0.5 to 0.85 XP a kill (it left
  85 % of stage 1's XP on the sand until the boss chest's vacuum pulled it in). With the sweep, 1.1 to 1.4 XP a kill,
  levels 8 to 12 at 5:00 (seeds 3, 4, 5, board 1.5) against Garry's 0.59 run (Drifter: level 9 at 2:50, 11 at 4:16).

### 2c. The dodge (the run sim's)
- A hostile warning on the sand (Telegraphs' growing ring in the creatures' red: r >= 0.8, g < 0.42, b < 0.5, still
  winding up: a Stone Golem's boulder, a rocket, a slam, a spit's splash, a boss's ring) that he stands in, or within
  0.8 m of, pushes him out from its middle: 4.0 at the middle, a third of that at its edge, added after the sweep.
- A red line (Telegraphs' strip, added 2026-10-15 with the boss leash: the King's roll and his volley's spokes, a
  charge's or a spit's line) pushes him straight off its axis the same way, from its start to its end, within half its
  width (at least 0.3 m) plus 0.8 m. The cones (sectors) are not read.
- Why: without it the Stone Golem's boulders (about 62 a hit against 121 HP at 3:35) killed the bot in stage 1.

### 2d. Goals (the run sim's)
- In order: the boss's chest (must reach), then the portal once no boss chest lies there (must reach), then (while a
  boss lives) the boss itself when he is more than BOSS_LEASH 10 m from it, walking until he is within BOSS_BACK 7 m,
  else the nearest unopened chest within 30 m (CHEST_RANGE).
- **The boss leash** (added 2026-10-15): while a boss lives, the sweep's gems and power-ups and the chests he walks to
  count only within 10 m of the boss, and he walks back to it from further. Why: the boss log (seed 73) showed the sweep
  leading him 40 to 60 m off while the King followed at 1.3 m/s (it lost 1 % of its HP in two minutes), so the first
  boss fight lasted anything from 3 s to 6 minutes by where the gems lay, and the boss chest's vacuum (10 to 18 levels
  at once) came that much later. A player fights the boss: its arrow is on the HUD, his guns reach 9 to 10 m.
- The walk: straight at it; from 7.5 m out he sidesteps a creature nearer than 2.6 m (0.7) and the danger push (0.9), and
  turns along a rock in the way (the map's obstacle circles, within its radius + 2.5 m, ahead of him); within 1.5 m he
  walks straight in. The red-ring dodge applies, scaled the same way.
- A chest not reached in 20 play seconds is left alone for 30 s. A must-reach goal not reached in 45 play seconds: he is
  put on it (an "assist": an event and meta.assists; the portal is re-armed so it asks at once).
- The portal and the boss chest: if he walks into the portal while the boss's chest still lies there, "Not yet"; the
  portal asks again only once he has been 2.5 m out (Portal.REARM), so he steps 3.2 m out and back in.

## 3. The screens
- **Level-up cards**: the best tier on the table, ties at random (the bot's dice); never a skip, a reroll or a banish.
  Tiers, best first: 0 an evolution (a maxed line's evolution card), 1 the hero's favourite arriving (the card says
  FAVOURITE), 2 a new weapon (offered only while a weapon slot is free), 3 a level of a held weapon, **4 a hero perk (the
  contract names none: placed after the weapons, before the lines)**, 5 a new line (only while a line slot is free), 6 a
  level of a held line, 7 a passive item (new or a level), 8 anything else.
- **A mutation (path) offer**: one card at random (the hero's own mutation among them); the reel is skipped.
- **A chest**: taken (its intro skipped and its spin hurried, as a player's two taps).
- **The Stranger**: declined. **The shop**: left. **A Totem Pole**: the gift with the most feathers (its quality, 1 to 3),
  ties at random.
- **The portal**: continue, after stage 3 into endless; "Not yet" only as in 2d.
- **Down!** by `death` (end the default; the lead, 2026-10-14: gold revives leave Down!): end = stay down at once (the run
  ends); ad = GET UP on the ad revive once, while Down! offers it (its button there and not locked: a chance left,
  1 + the revives stat - revives used), and stay down at the next; keep = never asked: the moment he falls he is stood
  up at full health with no invulnerability (the probe's way) and the fall counted. `gold` is read as `ad`. Phoenix
  Feather (an item) stands him up on its own in every policy; its fall counts as a fall.

## 4. The output's rules (keys_SIMRUN.md)
- The lead's difficulty fields (Garry: the crowd's whole HP and attack are "meaningless", the hero is never attacked by
  all of it): `near3` / `near6` count the creatures up within 3 m and 6 m of the hero, flat (RunAnalytics.NEAR_CLOSE,
  NEAR_WIDE, also row keys for the dashboard); `boss_hp_abs` is the boss's health (row key `boss_now`), `boss_hp` its
  share; `took` is the damage taken that second before any healing (row key `hp_lost`), `healed` the healing that second
  with regen (row key `hp_healed`). The Sim tab charts Danger (took / hp_max a second), Keeping up ((press_hp -
  boss_hp_abs) / dps) and Close crowd (near3, near6) from them.
- Lane SIMUI's round 2: `hits` (the recorder's hits that second), `spawned` (summed), `mult_hp` / `mult_dmg` (stage x the
  time curve x the level's, from the recorder's `mults`, carried forward; without the map's constant creature mults),
  `took_by` / `healed_by` (cumulative by creature / source, regen as the source `regen`), `held_by` (weapons,
  evolutions, lines, passives, perks held, from the recorder's build snapshots, carried forward) and the `pick` event
  (item_kind, new, level, tier, the other cards).
- One entry per recorder row (one per second of unpaused play); `t` = ceil(row t - 0.05), so a part-second at the end
  closes as the next whole second and `t` always rises.
- dps = the row's damage of every source summed; dmg_by and dmg_total cumulative; kills = Run.kills (cumulative);
  kills_by cumulative of the rows' kills by creature; gold_total cumulative of the rows' gold in (greed included);
  gold_by cumulative by source; alive_by the row's count (not summed); took = HP lost that second; healed = heals +
  regen that second; deaths = the recorder's death events (falls) at or before the row; xp_total = the recorder's new
  cumulative XP (Run.xp_gained, after Field Notes).

### 24.SIMUI The sim's averaging, lock and history

Where they live: `tools/sim_batch.py` (aggregate, player_grid, markers, eta_seconds, sync_snapshot, the lock) and
`tools/level_editor/sim_model.js` (the folds, the readout, the page's ETA, the same formula). The bot's own rules (cards,
movement, Down!) are lane SIMRUN's (`balancing_SIMRUN.md`).

## The averaging (per second of play)
- **The axis**: whole seconds of play 0..T, T = the longest run's last second (at most the stop time). A sample's second
  is round(t); when two share a second the later wins; a second without a sample carries the second before (levels and
  totals), a rate (dps, took, healed) is 0 there; second 0 takes each run's first row (0 for a total or a rate).
- **A run plays** from 0 to its last second. `playing[s]` = the runs whose last second is at least s.
- **Every series is the mean over the runs still playing** at that second (HP, max HP, DPS, the estimate, the crowd's
  HP and attack, alive, cap, coins, damage, kills, level, XP, ...). Survivors only, by design: late in a sim where many
  runs died the average is of the stronger runs; `playing` says how many.
- **Deaths** (cumulative falls) are the one exception: the mean over **every** run at every second, an ended run keeping
  its last count.
- **DPS** is smoothed per run over the trailing **5 s** (DPS_WINDOW; the first seconds over what there is) before the
  averaging; its band comes from the smoothed values. The raw per-second mean is kept as `dps_raw` (the page's
  "per second" button).
- **Bands** (the pale areas): the 10th and 90th percentiles over the runs still playing, linear between the nearest
  ranks (numpy's default; 1 run = no width), for HP, DPS, level, crowd HP, crowd attack.
- **Breakdowns** (damage by source, kills by creature, coins by source, alive by creature): the mean per id over the runs
  still playing; an id a run never had counts 0 for that run. Order: by the sum of each run's final value (totals) or by
  the sum of the mean over time (alive).
- **Markers**: a stage's start = the median of the play times the runs reached it (n = how many got there); a boss's
  start and end = the medians over the runs that met it / beat it, matched by id and occurrence; its fight = the median
  of each run's own end - start; its HP pegging = the median of the runs' `mult`.
- **The clock and the stage** at each second: the median over the runs still playing (the readout's "clock 12:05").
- **The summary** counts each run at its own end (never survivors only): runs that reached the stop (end within 1.5 s
  of it), the median end, deaths, revives, kills, level, coins, XP and damage per run; per boss reached / beaten.
- **A failed run** (no JSON written, or one that does not load) is left out of every average and listed with its reason.
  A run is judged by its JSON, never by its exit code (a headless run can exit 0xC0000005 after writing it).
- **Partial results**: result.json is written again after every finished run while at most 12 have finished, then at
  most every 20 s, and at the end (`meta.partial` until then). A cancel keeps the last one.

## The page (sim_model.js)
- **Folds**: a split chart shows its **7 biggest** entries (by the score above) and sums the rest into "Other" (a
  neutral grey, never a ninth hue); with 8 entries or fewer none fold. The colours are the editor's validated dark
  series slots in fixed order, given in the order the entries first appear (the weapon taken first, the creature that
  came first); Who is alive and Kills share one colour map (at most 8 creatures coloured; a creature that finds no free
  colour goes into Other).
- The readout under a split chart lists every entry at that second, biggest first, and names the three biggest inside
  Other ("356K Other (35) (40.1K Boomstick, 39.5K Lob Grenade, 38.9K Big Mouth)").
- The crowd's HP and attack split by creature on their own when the runs report `press_hp_by` / `press_dmg_by` (lane
  SIMRUN's output has only the totals today: one line with its band).
- Shares and words count **the runs in the result** (its summary's runs with data), not the runs asked for: a partial
  result of 5 of 10 runs shows "Runs still playing" over the 5.
- A sim started with Run sim takes over the charts at its first finished run; a sim started elsewhere (a shell, the Jobs
  tab's Re-queue) never takes the view from the one shown (its History entry shows it, partial, as it fills).
- The compared sim: grey (#a8a79f), dashes 7-5, on every chart; a stacked chart compares its total only.
- The y axis: from 0 to the next round tick above the highest value drawn (lines, band tops, stack totals, the compared
  sim); the share chart 0-100%. One unit per axis (5K, 10K once the top reaches 10,000).

## The run, the snapshot, the lock
- **Snapshot**: game/ copied to `tools/dl/sim/snap/game/` (export/, reports/, .godot/ and *.tmp never; .godot seeded
  once from the real one minus shader_cache and exported), a file copied when its size or mtime differs (mtimes kept),
  a file gone from game/ deleted, except the snapshot's own `.import` / `.uid` beside a file still there. Its
  project.godot: `config/use_custom_user_dir=true`, `config/custom_user_dir_name="88fits_sim"` (user:// =
  %APPDATA%\88fits_sim: never Garry's save or runs).
- **The snapshot imports** (`--headless --import`) when the snapshot is new, or a `.import`, a picture/model/sound/font
  (png jpg jpeg webp svg tga bmp exr hdr glb gltf fbx obj blend dae wav ogg mp3 ttf otf woff woff2 fnt csv), a `.uid`,
  a new or removed scene or resource (tscn tres res scn gdshader), a new or removed script, or a script's class_name
  changed. A content `<id>.json` newer than its `<id>.tres` by more than 1 s is imported in the snapshot
  (`import_json.gd -- only=type/id,...`; the sound map as `sounds`), so the sim plays the saved JSON.
- **The lock exception**: one sim at a time through `tools/dl/locks/sim.lock` (tools/locks.py's owner.json; a dead
  owner's lock reclaimed, a folder without owner.json never: the Sim tab's Release). A sim never takes the Godot lock:
  its Godot processes (the snapshot's import, import_json, the runs) work on another project folder with its own user
  folder, so the editor's Save, imports and the tests are never blocked. (CLAUDE.md should say so; tools/locks.py's NAMES
  could list "sim" so `locks.py status` shows it: the format already fits.)
- **The runs**: `--headless --fixed-fps 60` (the fps setting) `--log-file players/pNN.log`, K at a time (auto by
  default since round 2: as many as the runs, at most the logical processors - 2), run k plays seed + k - 1. A run past its wall-time cap,
  max(900 s, 2 x the stop), is killed; the runner's own watchdog gets `wall=` that cap - 45 s so it writes what it has
  first.
- **The history**: `tools/dl/sim/runs/` keeps the newest **10** sims plus every kept one (a `kept` file); older folders
  are deleted when a sim ends. A running sim is never deleted.
- **The ETA** (round 2's rules, see below): the snapshot (20 s; 120 s for the first one) + rounds of K runs, each its
  boot + the stop / the slowest run's pace; past half the logical processors at once the runs share them (speed x
  load(measured K) / load(K), load(n) = max(1, n / (cores/2))). First guess before any record: 2.5 play seconds a wall
  second, an 18 s boot.

## Defaults (the Sim tab, the job, the CLI) (round 2)
10 runs, at once auto (as many as the runs, at most the logical processors - 2: 14 here), stop at 25:00 (1500 s), the
Upgrade board a quarter, on death: end the run at the first death, seed 1, the map in the editor (red_canyon), 60 fps,
the runner's sim mode on. Ranges: runs 1-100, stop 0:30-3:00:00, a talent 0-6 ranks, seed 0-2^31-1.

## Round 2 (Garry's notes on the first Sim tab, 2026-10-14)
- **The Upgrade board talent by talent**: `talents` {talent: picks}, one letter a rank bought, its form (A the first, B
  the second): exactly Save.data.talents[id].picks. The presets: difficulty_probe's FORMS (grit, drive, stride, fortune,
  choice: the first form; nerve, study, spite: the second) and rank_for (a whole board gives every talent that many
  ranks; 1.5 alternates 2 and 1 in that order: 12 of 48 ranks); "my save" = the PC save's talent picks (the copy
  tools/locks.py keeps aside while a Godot tool has the save). Given, the talents win over board= (which then only names
  a preset they equal: none 0, a quarter 1.5, half 3, full 6; else custom, board -1). The runs get `board=` (the preset or
  0) and `talents=` (only when there are ranks: an empty board is board=0 alone). An empty talents block in a job spec
  means "the preset board= names".
- **The death policies**: end (the default), ad (revive once with an ad while it is offered, then end), keep. Gold is
  gone with Get up with gold; an older sim's "gold" still reads (its label) but never runs.
- **The runner's capabilities** (read off game/tools/sim_run.gd's argument parser: a `"talents":` arm, a `"fast":` arm,
  the `_death in [...]` list): the page offers only the death policies the runner knows; a sim whose death policy the
  runner does not know, or whose board is custom while the runner reads no talents=, is refused before anything plays
  (the run route's 409 and the driver's error), since an older runner would play no board and a refused policy makes
  every run fail. `fast=1` / `fast=0` is sent only to a runner that has the sim mode (it is on unless told fast=0).
- **The board check**: a run whose meta.talents (ranks per talent) differs from the board asked is named in the
  header ("run 1 played grit 1 (asked 3)").
- **Difficulty, per run and second** (the derived series):
  - danger = 100 x HP lost that second (took: after shields and armour, before healing) / max HP; danger_net = 100 x
    (took - healed) / max HP (below 0 = healing more than lost); each over the trailing 5 s (DPS_WINDOW) like the DPS,
    then the mean over the runs still playing, a p10/p90 band on danger;
  - keep_up = (crowd HP alive - the boss's HP) / the run's DPS (its 5 s DPS), boss_s = the boss's HP / that DPS while a
    boss lives; neither where the DPS is under 1; the boss's HP: the runner's boss_hp_abs, else boss_hp when above 1.5
    (an absolute), else the fraction boss_hp x the max HP its boss_start event reported. These two are ratios that jump
    where the DPS is small, so their aggregate is the **median** over the runs that have a value at that second, with
    p10/p90 and the count of runs (`n`), never a mean (MEDIAN_SERIES);
  - trouble = 100 while HP is under 30% of max HP (TROUBLE_FRAC), else 0: its mean is the share of runs in trouble;
  - kills_ps (from the running total), spawned_ps, hits_ps: each second's count over the trailing 10 s (RATE_WINDOW,
    the run dashboard's 10 s means);
  - near3 / near6 (the runner's creatures within 3 / 6 m), mult_hp / mult_dmg (a creature spawned now): levels, means;
  - took_by, healed_by (cumulative) and held_by (items held: a level) as breakdowns.
  Crowd HP and crowd attack stay in result.json (press_hp, press_dmg) but are no charts.
- **The charts**: five sections in Garry's order (the hero; death; how hard is each second; rewards; growth); a chart
  whose data the runs lack is left out and named under its section. Who is alive, What hurt the hero and Kills share
  one creature colour map. A y axis goes below 0 only when a value does (the net danger), with 0 always a tick.
- **The page**: one scroll (no inner scroll areas); a plot that changes width is drawn again (a ResizeObserver, over
  8 px) and stretches with its card until then.
- **Speed and the ETA**: a speed record (tools/dl/sim/speed.json, the last 20) is made from the runs that played at
  least 60% of the stop (and 300 s): `play_per_wall` = their median rate (play seconds a wall second after the boot),
  `slow` = the slowest of them (a round of runs ends with its slowest run), the boot, K, `fast` (the runner's sim mode).
  A sim where fewer than 80% of its runs played that long makes no record: a run that died early played only the light
  early game, and when most die the few left have the PC to themselves and run faster than K at once would. The ETA
  takes the last 5 records of the chosen mode (the Drawing switch) at the most recent record's K (unscaled; the page
  scales to its own K with speed_at) and plays each round at the `slow` pace; the page says "if every run lasts that
  long" unless the runs keep playing. Measured (16 logical processors, 10 runs of 25:00, keep playing): 23:39 with 6 at
  once before the sim mode; 18:10 with 10 at once and the sim mode off (median 1.98, the slowest run 1.41 play s a wall
  second); 10:23 with 10 at once and the sim mode (median 2.97, slowest 2.55). The ETA now says 10:32 and 18:30 for
  those two.
- **The Drawing switch** (`fast`, on by default, offered when the runner has `fast=`): off sends `fast=0` (everything
  drawn and played). `result.meta.sim_mode` = what the runs played (any run's meta.fast; a runner from before the mode
  drew everything): the header and the history say "everything drawn" when it is false.

### 24.LEAD The lead's changes in this pass

- **Down! has no gold revive** (Garry: "Remove the 'Get up with gold' option from the down screen"): the screen offers GET
  UP · WATCH AN AD (a stand-in, no ads yet) and STAY DOWN. The engine's "gold" kind is kept (no button sends it).
- **A row may start on a boss second** (Garry's r18, blue slimes at 7:10 with the King): it reads the step of the stage
  before, as every row reads the HP/ATK step at its own start (pass62_pc re-pinned to this).
- **The XP multiplier is Garry's** (`timeline_data.xp_need_mult`, 4.1 since 2026-10-15; 2.1 before): pass52 reads it.
- **The difficulty probe runs on the run's own clock** (`"sim_clock": true`): the rules that counted real time (the
  Orbiter's repeat hit, the rebuild throttle) ran 2.5 to 4.5 times too seldom in a headless probe; probe numbers from
  pass 62/64 understate orbiter builds.
- **The Totem brief** (docs/ui_review/totem/, Drive totem_ui_brief, artifact YbXF7fMNgFJDZ7SdjKNhVf) carries only the
  totem screen and the pole in the game, with the screen explained element by element (Garry: "We only need the totem
  one").

## 25. Pass 78 (v0.64): run records through PostHog (not balance: named so they are not surprises)

Garry's request (2026-10-15, tools/dl/p78/REQUEST.md). The lane's rules as it wrote them.

### 25.DASH What a run sends, when, and how runs are averaged

No game number changed. The rules this pass adds, with where each lives:

## What a run sends to PostHog: `run_record` (core/autoload/Analytics.gd)
- **What**: the run's record file exactly as the game writes it (`user://analytics/runs/<stamp>.json`: header, a row a
  second, events; RunAnalytics schema 2), its UTF-8 gzipped (Godot's `COMPRESSION_GZIP`, zlib's default level), base64,
  cut into parts of at most **RECORD_PART_MAX = 100,000 characters**; one `run_record` event a part, with `part`, `parts`,
  `data`, `enc` (`gzip+base64`), `format` (**RECORD_FORMAT = 1**), `raw_bytes`, `gz_bytes`, `md5` (of the JSON's UTF-8),
  the run's properties (run_id, hero, hero_look, map, map_rev) and the usual super properties (install id, dev,
  app_version, device, ...).
- **Size budget** (PostHog: an event over 1 MB is discarded, posthog.com/docs/data/ingestion-warnings; a /batch/ request
  under 20 MB, docs/api/capture): a part is ~102 KB as an event, a tenth of the limit. Measured: a 25-minute record (real
  tool-run rows to 1500 s) is 1,016,069 characters of JSON -> 106,221 bytes gzipped -> 141,628 characters of base64 =
  **2 parts** (pass78_dash_test); the sims' per-player files would be ~140 KB the same way, so the whole record costs
  about what the Sim's schema would. A 1000-s run played on the PC: 908 KB -> 86 KB gz -> 115 KB base64.
- **Cap**: at most **RECORD_PARTS_MAX = 24 parts** (~2.4 MB of base64, a run of about five hours); past it the record goes
  without its rows (`samples` empty, `rows_left_out: true` on the record and on each part).
- **One request** carries at most **REQUEST_MAX = 400,000 characters** of events (at least one event; a run_record part
  counts its data + 2,048) besides the old BATCH_MAX = 50, so a phone uploads a part or two at a time
  (`Analytics.request_count`).
- **When**: at the run's end (RunAnalytics.finish -> Analytics.run_record before run_finish, then the queue is sent at
  once); a **quit** (the app closed mid-run): queued and saved on the way out, sent at the next launch (as run_end
  already was); a **killed** run (Android drops the app in the background after the run's checkpoint): the checkpoint
  leaves `user://analytics_pending_run.json` {file, the run's properties}; the next launch (Analytics._ready ->
  send_pending) sends that checkpoint's record with `result: "killed"` and `recovered: true`, unless the run ended after
  all (its file is no longer `in_progress`) or the file is gone; a crash without a checkpoint sends **nothing**. Any end
  of a run clears the note.
- **Never**: from a tool's script, a headless run or the test runner (`runtime_block`), the arena or the save's sandbox,
  with the Settings switch off, a missing/empty/non-phc_ key or `"enabled": false`; the run sim writes no record
  (`memory_only`). Before the play-data card is answered the parts wait in memory like every event; "No thanks"
  deletes them. Garry's email is in no record (no field holds it; the test checks no "@" in the event).
- **The queue cap still applies**: past QUEUE_CAP = 2000 waiting events the oldest go, a run_record part included (a run
  then stays "parts missing" in the download: weeks offline only).

## What the download does (tools/posthog_runs.py)
- Lists the run_record events since `--since` (default the last **30 days**; `--all` from 2026-01-01) with the query
  API (HogQL, keyset pages of **10,000** rows on the timestamp; no OFFSET: PostHog refuses it for personal keys), reading
  only uuid, timestamp, distinct_id and the person's player_name/label; then fetches the payloads **12 parts a query**,
  each query bounded by its parts' timestamps, of the runs not already in the folder (by event uuid).
- A run is written only when all its parts are there and check (the base64 reads, `gz_bytes`, `raw_bytes`, `md5`); a run
  with a part missing waits for the next download, a broken one is named and skipped.
- Player folders: the person's `player_name` made safe for a folder; a second install with the same name gets
  `_<first 6 of its install id>`; an install without a name is `id_<first 8 of its install id>`. `--player` matches the
  name, Garry's label or the install id (any case).
- PostHog's hourly read budget for personal keys answers 429 when spent: the download stops politely, keeps what came,
  and says when to try again. The e2e proof read 1.2 MB in 2 queries.

## The averages (tools/level_editor/sim_avg.js, the dashboard)
- `SimAvg.aggregate` is tools/sim_batch.py `aggregate()` line for line: every series the mean over the runs still playing
  at that second; DPS smoothed over 5 s per run first; p10/p90 bands for hp, dps, level, crowd HP/attack, danger, near3,
  near6 (linear between the nearest ranks); keep_up and boss_s as medians; deaths averaged over EVERY run (an ended run
  keeps its count); the breakdowns' means over the runs still playing (an id a run never had counts 0); the stage and boss
  marks as medians over the runs that reached them; values rounded as Python rounds (`round`, half to even on the exact
  binary value: `pyRound`). selftest_DASH78 checks it equal to the Python on made-up runs and a real 10-player sim.
- A run record becomes a Sim player by `SimAvg.fromRecord` = game/tools/sim_run.gd `series()` (the same per-second
  mapping, Godot's snappedf included; a committed fixture pins the two equal) with a meta in the runner's words
  (`end_reason` = the record's `result`, `end_t` = its `length`). A key an older record never wrote is left out so its
  chart hides instead of drawing zeros: `xp_total`, `near3`, `near6`, `boss_now` (pass 77), `lines` (schema 2), `gold_in`
  (pass 61). The evolutions among the weapons are the record's own evolution events' ids (the sim asks the Registry).
- A result of ONE run (the dashboard's open run, a one-player sim) draws no bands, no "Runs still playing" chart, and says
  "for this run" (sim_model.js; the Sim tab's 1-player sims read the same way now).
- The dashboard's averaged runs: whatever is ticked (files, a folder, remote runs); the time axis runs to the longest
  run; "the runs one by one" lists each run's own end.

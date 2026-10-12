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

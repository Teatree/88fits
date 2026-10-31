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
| **A mutation offer comes as a level-up** (pass 79; until then mutations never came in a level-up). It falls due at the map's `path_times` (seconds into each stage) and the hero's next level-up shows it in place of the three cards (§26.MUT, rules M1-M6): a weapon drawn at random among those that still have a mutation open this stage (pass 54; it was the highest-levelled one) gets its whole path (its open element, volume and motion mutations, then the hero's own option) on one table. One mutation per weapon per stage, from its first level (`Run.MUTATION_FROM_LEVEL` 1). Boss chests always roll a mutation, and the Stranger sells one | `Run.path_due`, `Run.mutlvl_tick`/`mutlvl_claim`, `next_path_weapon`, `CardPool.path_offer` |
| **Evolution** comes from a chest, once a weapon is at its 5th level and holds all three of its path mutations (a hero's own is optional) | `Run.evolution_ready` |
| Not offered: anything banished this run, anything locked behind an unlock quest (unless you already hold it), hidden items, another hero's own weapons (the Gravity Gun is Astro's, the Revolver the Drifter's, the Guitarra Calavera's), stage-3 items before stage 3 (Brimstone Brand, Sinner's Greed: `from_stage`) | `Registry.unlocked_*`, `stage_open` |
| **Weights**: an item's `weight` x its rarity (common 1, uncommon 0.75, rare 0.55, epic 0.3, legendary 0.15) x (1 + luck x the tier's lift: uncommon 0.5, rare 1, epic 1.5, legendary 2) x 1.5 if you hold it x 0.88 for every level past the first | `CardPool.weight_of` |
| **Choices**: 2 skips and 1 banish a stage, shared with the mutation tables and chests; 1 reroll a run (the Mirror adds more). A skip pays nothing; a banish swaps that one card and keeps the item out for the run. **Pass 58** (Garry: "Banish option should not allow Banishing items that Player already has, because this way they can lock themselves out of progression"): a banish never strikes an item you hold (a weapon, a line or a passive item at any level), an evolution, or a path mutation of a weapon you hold; a new item, a perk or a hero's own optional mutation may go. With nothing banishable on the table the button locks and says why; a refused tap spends nothing. Chests follow the same rule. Once a weapon evolves, its base weapon is never offered again (level-ups, the Stranger); a hero's own mutation banished from a boss chest never comes back | `Run.refill_choices`, `Run.banish_refusal`, `CardPool.banishable` |
| The hero's **favourite** says FAVOURITE on its card and comes at a bonus level (Calavera's Skull Rain, Ironwood's Brawn at level 2) | `Run.first_passive_level`, `CardPool.apply_favourite` |
| Nothing left to offer: +10 gold instead | `Game._show_next_level_cards` |
| **First-run Dynamite offer** (pass 109, Garry: "make it so Player always gets a dynamite stick offered to him on his 3rd level up ... among the worst items ... This will only stop happening when Player actually chooses the dynamite"): in every run, the first card screen of level 4 or later (his 3rd level-up; when that one is a mutation level-up, the next card screen) holds the Dynamite Stick (`lob_grenade`) as a new weapon, whatever its unlock quest, beside the two lowest-rarity cards the draw could offer then (common first, ties at random; never a new weapon, a perk, the hero's favourite, an evolution or a level that maxes an item that evolves), the Dynamite at a random place. Once a Dynamite card is picked at a level-up, the save's once-flag `ftue_dynamite_taken` ends it for good; picking it unlocks nothing for later runs. Not in the arena, nor when he holds it (or its evolution) or has no free weapon slot; a reroll or a banish's redraw draws normally. The developer menu's "First-run Dynamite offer" row brings it back | `FtueDynamite`, `Game._show_next_level_cards` |

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

## 26. Pass 79 (v0.65): mutations at level-ups, bodies that fly, line trails, the rim, the dynamite's lead

Garry's request (2026-10-15, tools/dl/p79/REQUEST.md). Each lane's rules as it wrote them.

### 26.MUT Mutation offers come as level-ups; the XP curve

Garry (2026-10-15): "Mutations are supposed to be level ups, not just random occurrences ... the mutations happen whenever
there is a level up". His pick: the offers stay (one per weapon per stage) but come as the level-up screen itself, in
place of the three cards; "decrease the level requirements to achieve the same power level considering the changes".

#### The rules (name them in §26)

| # | rule | where |
|---|---|---|
| M1 | A mutation offer **falls due** as a slot always did: the stage clock passes one of the map's `path_times` (Phase NORMAL only; stage 1: 79, 140, 200, 260, 315, 365, 405 s; stages 2-3: 50, 105, 160, 215, 270, 325, 380, 410 s; endless plays the last list once). One that falls due while no weapon has a pick open is spent with nothing, as before. Never in the arena | `Run.mutlvl_tick` (WaveDirector._process calls it instead of `Game.present_path_offer`) |
| M2 | A due offer **never opens on its own**. The hero's next level-up is a **mutation level-up**: its screen is the mutation offer (the weapon reel, the weapon's whole remaining path and the hero's own option, "Level N! Pick a mutation", SKIP on the stage's two skips, no reroll, no banish) in place of the three cards. Due offers **queue, one a level-up**, and stay due across a stage's end. The level-up is claimed when the XP crosses the line (a level banked behind another screen or while he is down keeps its kind) | `Run.mutlvl_claim` (in `add_xp`), `Game._show_next_level_cards` -> `Game._mutlvl_open` |
| M3 | A level-up whose due offer finds **no weapon with a pick open** is an ordinary one (three cards); the offer is dropped. The weapon is drawn **at random** among those open when the screen opens (as since pass 54); a claimed one whose weapons all lost their pick while banked (a boss chest's mutation) opens as three cards | `Run.mutlvl_claim`, `Run.mutlvl_take`, `Run.mutlvl_unclaim`, `Run.next_path_weapon` |
| M4 | **The HUD says it**: while an offer is due and a weapon has a pick open, the LV plate is the kit's mutation plum (`W.PLUM`) with paper letters and the XP rail's right end reads MUTATION NEXT (slab 30 px, paper, 4 px ink stroke, 24 px in). It goes when the level-up takes the offer | `HUD._refresh_mut_mark`, `Run.mutlvl_pending` |
| M5 | **The card levels.** A mutation level-up counts once it is claimed (a skipped offer too: `Run.mutation_levels`). What grows with the hero's level reads `Run.card_level()` = his level less his mutation level-ups: the creatures' level factor (`level_hp_per_level` 0.05, `level_damage_per_level` 0.03 per level above 1), his trait (`trait_per_level`, and its "Lv N" in the pause Stats), Barrel Rush's barrel gems (1 + 0.15 x level), Ram's `per_level`, Supply Drop's `damage_per_level`. So a minute brings the same scaling as before; the map's `mutation_levels_scale: true` counts every level-up instead | `Run.card_level`, WaveDirector._apply_mults / fixed_numbers, Run._build_player_sheet, BarrelField, EnemyManager (Ram), Game (Supply Drop), StatSources, RunAnalytics._trait |
| M6 | **Faster levels.** `xp_need_mult` (the XP curve 15 + 6L + 0.5L^2 times it) is set so that a minute brings about as many three-card level-ups as before and the mutation level-ups on top (measured, below). The quests that count the badge level (Quickdraw: level 10, Zap Beam: level 20, May: level 30) now come sooner: they read the badge, not the card level | `timeline_data.xp_need_mult` |

Docs fix (to the code since pass 54): BALANCING.md's table says "the weapon with the highest level that still has a
mutation open this stage gets its whole path": the weapon is drawn **at random** among those with a pick open
(`Run.next_path_weapon`, pass 54). The row should now read: "Mutations never come among the three cards. A mutation
offer falls due at the map's `path_times` and is the hero's next level-up (M1-M3)...". The design bible part2.html is
rewritten (Mutations' first bullet, Evolutions: level 5 + all three path mutations).

#### The XP curve

**Red Canyon's `xp_need_mult`: 3.1 -> 1.65.** Garry's numbers on the way: 2.1 until 2026-10-15, 4.1 at HEAD c16df32
(his morning change), **3.1** in his Level Editor save of 12:46 (the value when measured: the lead's baseline, "today").
The curve keeps its shape (15 + 6L + 0.5L^2) x the multiplier: one scalar holds within about two levels over 0-25 min,
so no shape key was added.

**How it was measured.** The run sim (tools/sim_batch.py, game/tools/sim_run.gd's bot) on lane MUT's own snapshot of
the tree (FX's and WORLD's final code included), Drifter, 20 players (seeds 1-20), 25:00, death = keep (stood up at
full HP, every fall counted), the Upgrade board a quarter, 60 fps. "Today" = the snapshot with the director's old line
(the offer pops up on the clock) at 3.1; "new" = the same snapshot with the new delivery. Per player and per 30 s:
the XP he had gained, the level that XP buys on today's curve, plus the mutation offers he had taken by then = the level
the new curve should give for that XP; the multiplier that fits best over 0-25:00 (least squares on the level):
**1.64** (RMS 1.54 levels; 1.6: 1.59, 1.7: 1.64, 1.5: 2.11), rounded to the editor's 0.05 step: **1.65**. Then a sim of
each confirms it (by play minute, means over the 20 players; "regular picks" = three-card level-ups taken):

| min | regular picks today | regular picks new | mutations today (clock) | mutation level-ups new | level today | level new | kills today | kills new | deaths today | deaths new |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.9 | 1.7 | 0.0 | 0.0 | 1.9 | 2.7 | 100 | 110 | 0.0 | 0.0 |
| 2 | 2.2 | 3.0 | 1.0 | 0.8 | 3.2 | 4.8 | 218 | 232 | 0.0 | 0.0 |
| 3 | 3.7 | 3.9 | 1.9 | 1.8 | 4.7 | 6.6 | 487 | 462 | 0.1 | 0.1 |
| 4 | 5.6 | 5.8 | 2.6 | 2.5 | 6.6 | 9.3 | 834 | 742 | 0.1 | 0.1 |
| 5 | 8.4 | 7.6 | 3.4 | 3.1 | 9.4 | 11.8 | 1400 | 1196 | 0.1 | 0.1 |
| 6 | 10.4 | 9.1 | 4.2 | 4.0 | 11.4 | 14.1 | 2036 | 1693 | 0.3 | 0.2 |
| 7 | 13.1 | 11.2 | 4.8 | 4.5 | 14.1 | 16.8 | 2601 | 2226 | 0.4 | 0.2 |
| 8 | 17.9 | 19.6 | 4.8 | 4.7 | 18.9 | 25.2 | 2997 | 2617 | 0.7 | 0.5 |
| 9 | 20.6 | 20.6 | 5.8 | 5.4 | 21.6 | 27.1 | 3242 | 2862 | 1.5 | 1.0 |
| 10 | 23.2 | 22.7 | 6.9 | 6.5 | 24.2 | 30.2 | 3842 | 3393 | 2.2 | 1.6 |
| 12 | 26.6 | 25.2 | 9.4 | 8.3 | 27.6 | 34.5 | 5084 | 4564 | 3.3 | 2.9 |
| 14 | 29.6 | 27.9 | 9.8 | 9.6 | 30.6 | 38.5 | 6524 | 5949 | 4.6 | 4.6 |
| 16 | 34.4 | 33.9 | 10.3 | 9.8 | 35.4 | 44.7 | 8061 | 7270 | 6.5 | 6.8 |
| 18 | 38.9 | 36.8 | 12.4 | 11.8 | 39.9 | 49.6 | 10843 | 9611 | 8.0 | 7.8 |
| 20 | 44.0 | 42.0 | 12.9 | 12.7 | 45.1 | 55.7 | 13338 | 11709 | 9.2 | 8.8 |
| 22 | 48.0 | 47.4 | 12.9 | 12.8 | 50.3 | 61.1 | 16024 | 13963 | 10.1 | 9.4 |
| 24 | 52.8 | 54.4 | 12.9 | 12.8 | 56.9 | 69.2 | 18957 | 16742 | 10.8 | 11.3 |
| 25 | 54.2 | 57.5 | 12.9 | 12.8 | 60.0 | 73.1 | 20492 | 18216 | 10.9 | 11.7 |

Reading it: the three-card level-ups by any minute stay within about two of today's (-1.9 at 7:00, -2.0 at 20:00,
+1.6 at 24:00; the standard error of a 20-player mean is 0.6 to 2 levels, so most of it is noise), the mutation picks
are the same (the level-up delivers them a few seconds after their slot: -0.4 at most but -1.1 at 12:00), and the level
on the badge is today's plus about 13 by 20:00. Kills differ by -11 to -17% here and by +7 to +17% in the same test at
4.1 (below): the spread of one player's kills is 25-35%, so neither is a trend. Past 24:00 (endless) the new curve runs
ahead (+3.3 picks at 25:00): the mutations stop at about 13 while the scalar keeps every level cheaper.

**The same at 4.1** (the brief's first baseline, on the snapshot before FX's and WORLD's last changes; 4.1 old vs
2.0 new, 20 players each; the fit there: 1.99, RMS 1.48):

| min | regular picks today | regular picks new | mutations today (clock) | mutation level-ups new | level today | level new | kills today | kills new | deaths today | deaths new |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.6 | 1.6 | 0.0 | 0.0 | 1.6 | 2.5 | 94 | 109 | 0.0 | 0.0 |
| 2 | 1.4 | 2.5 | 1.0 | 0.7 | 2.5 | 4.2 | 196 | 224 | 0.0 | 0.1 |
| 3 | 2.1 | 3.1 | 1.6 | 1.6 | 3.1 | 5.7 | 378 | 415 | 0.0 | 0.1 |
| 4 | 3.8 | 4.0 | 2.2 | 2.1 | 4.8 | 7.0 | 654 | 676 | 0.0 | 0.1 |
| 5 | 6.0 | 5.6 | 2.9 | 2.8 | 7.0 | 9.4 | 1035 | 1065 | 0.1 | 0.2 |
| 6 | 7.2 | 7.5 | 3.5 | 3.4 | 8.2 | 11.9 | 1444 | 1610 | 0.3 | 0.7 |
| 7 | 8.8 | 9.9 | 4.3 | 4.1 | 9.8 | 15.0 | 1925 | 2107 | 0.5 | 0.7 |
| 8 | 14.4 | 16.6 | 4.3 | 4.5 | 15.4 | 22.1 | 2277 | 2474 | 0.9 | 0.9 |
| 9 | 16.4 | 17.8 | 5.2 | 5.0 | 17.4 | 23.8 | 2503 | 2684 | 1.9 | 2.1 |
| 10 | 18.3 | 19.0 | 6.3 | 6.0 | 19.3 | 26.1 | 2964 | 3139 | 2.9 | 3.3 |
| 12 | 21.5 | 20.8 | 8.6 | 8.0 | 22.5 | 29.7 | 3912 | 4170 | 4.5 | 5.3 |
| 14 | 23.9 | 22.8 | 9.3 | 9.2 | 24.9 | 32.9 | 4998 | 5416 | 6.2 | 7.0 |
| 16 | 28.1 | 28.4 | 9.8 | 9.4 | 29.1 | 38.8 | 6052 | 6610 | 9.1 | 9.1 |
| 18 | 31.9 | 31.1 | 11.6 | 11.2 | 33.0 | 43.4 | 7868 | 8910 | 11.5 | 10.4 |
| 20 | 36.0 | 34.9 | 12.6 | 12.3 | 37.0 | 48.2 | 9769 | 11254 | 13.0 | 11.9 |
| 22 | 39.3 | 39.9 | 12.7 | 12.6 | 40.5 | 53.5 | 11692 | 13588 | 13.8 | 13.4 |
| 24 | 43.6 | 47.4 | 12.7 | 12.7 | 45.4 | 61.5 | 14015 | 16447 | 15.7 | 15.6 |
| 25 | 46.1 | 49.8 | 12.7 | 12.7 | 48.2 | 65.3 | 15406 | 18055 | 16.4 | 16.1 |

Side effects to know (not rules): the quests that count the badge level (Quickdraw 10, Zap Beam 20, May 30) come
sooner (in the 3.1 sims level 20 came at 7:30 on average instead of 8:10); PostHog's `path_offer` events are now level-ups too
(a board that counts `level_up` offers counts only the three-card ones); a level-up's heal (`level_heal`) and Suit
Seals' invulnerability come with every level-up, mutation ones included.

### 26.FX Bodies that follow through; line trails

#### Bodies follow through (EnemyManager, "pass 79 (lane FX): corpses follow through", the end of the file)
Garry: "enemies that die have their corpses follow through with their knockback. So when an explosion kills an enemy fly
off like the live ones."
- A creature that dies keeps the push it had (the killing hit's push is added before it dies, as for a live one, plus
  whatever push it still carried). Its body slides on with it while its death plays, the push dying away at
  `CORPSE_GROUND_DECAY` = 6 /s (the live crowd's own rate), inside the arena (the same clamp as the living: 2 m inside
  the arena's radius), on the ground's height, and sliding along a rock it runs into instead of entering it. A push
  under `CORPSE_STOP` = 0.05 m/s is spent.
- A kill by a blast also throws the body up. A blast is any `damage_radius` hit with a push (knockback > 0): the
  dynamite/grenade family, Powder Keg, the rockets, mines, Cluster bomblets, a turret's boom, the Vortex's pop,
  Overkill's splash, the revive blast, a hostile blast catching its own crowd (a kamikaze's, a death burst, a loose
  rocket). Height = `CORPSE_TOSS_PER` 0.3 m for every m/s of the body's push, at most `CORPSE_TOSS_MAX` 2.5 m; under
  `CORPSE_TOSS_MIN` 0.3 m there is no throw (the body only slides). It falls at `CORPSE_G` 22 m/s² (the launch's dead
  fall); while up, the push dies away at `CORPSE_AIR_DRAG` 1.5 /s only, so it sails; it lands in a little sand (no
  sound). Its death lasts at least the flight plus `CORPSE_REST` 0.6 s (it lies a moment, then sinks over the usual
  DIE_SINK 0.3 s); a short flight leaves the usual DIE_TIME 1.4 s.
- Examples (Red Canyon's hero_knockback_mult 0.5; a pack of skeletons, the final captures
  tools/dl/p79/FX/final_corpses): the dynamite (knockback 14) pushes ~3-5 m/s: thrown 0.75-1.4 m up, landing ~1.2-2.4 m
  out; Powder Keg (KEG_KNOCK 9) ~2-3 m/s: 0.6-0.85 m up, ~0.9-1.3 m out. A survivor of the same blast is shoved as
  before (~0.7 m for the dynamite), never thrown.
- Exceptions: the boss keeps his old death (no slide, no throw). Big game (an Elite, an elite-modded creature, a
  big-game type) slides but is never thrown up (only small creatures are ever launched alive). A body up in a launch
  (Alley-Oop, Bucking Bronco) falls as before and keeps Bucking Bronco's drift as its push. A body killed while up in
  the air by anything else (a tornado's toss, a bounce) now falls from there (it used to hang in the air through its
  death).
- Nothing changes for the living.

#### Tracer lines (ProjectileManager, "pass 79 (lane FX): the tracers' lines", the end of the file;
#### core/shaders/tracer_line.gdshader)
Garry: "The balls aren't good. Make a simple line trail, similar to that of the rocket. Should be thin. 1. Regular shot
dark red transparent 2. Silver - thicker, correct colour. 3. Then the line disappears like smoke."
- Every shot of a weapon with `tracer` lays a line behind it instead of beads: a piece every `TRACER_SEG_MIN` 0.3 m it
  flies (0.6 m while more than `TRACER_BUSY` 60 shots are in the air), from where it left (the muzzle).
- Width `tracer_width` (default `TRACER_WIDTH` 0.05 m), never under 1.5 screen pixels; colour as before
  (`_tracer_colour`: a mutation's own `tracer_color`, else Silver Bullet's, the element's, the weapon's own, gold), drawn
  exactly as written (sRGB); alpha `tracer_alpha` (0.9); life `tracer_life` (default TRAIL_LIFE 1.4 s).
- The smoke: over its life each piece fades (alpha x (1 - f)^1.5), widens to 1.9x, drifts up 0.45 m/s, sways up to
  0.06 m and greys 40% towards its own grey (shader uniforms widen 0.9, rise 0.45, fade_pow 1.5, sway 0.06,
  smoke_grey 0.4, min_px 1.5, edge_soft 0.45). The two ends of a piece are dated when the shot passed them, so a line
  fades from its tail towards the shot with no seams.
- `tracer_clear` (the Revolver's 1.1 m) cuts away the part of a line within that distance of the hero (ground plane).
- At most `TRACER_LINE_MAX` 2048 pieces at once (a ring): a busy screen cuts the oldest lines short, never slows down.
- The old bead keys `tracer_size`, `tracer_step`, `tracer_beads` (Drum Mag's three beads a drop) draw nothing now.
- Content set: Revolver #8B0A0A at 0.9, 0.045 m, 0.9 s (was the beads' #7A1F17 at 0.85, which the renderer showed as a
  salmon terracotta: the bead material read the colour as linear); Silver Bullet and the Golden Revolver's silver form
  #C9DCEF (pale silver-blue) at 0.9, 0.11 m (the old SILVER constant (0.55, 0.8, 1.0) shown as written is a sky blue);
  Drum Mag 0.065 m (a bolder line for its "denser trails"); Boomstick and Blunderbuss pellets 0.035 m; everything else
  0.05 m in its old colour and life.

### 26.WORLD The rim's and walls' colours; the dynamite thrown ahead

#### The map's sides (Garry: "Map the sides are too orange")
- Red Canyon's red-rock rim (from `rim_start` 44 m to the wall at 66 m) and its walls are drawn in the colours the map
  file names: timeline_data `rock_color` and `wall_colors` {near, far, farther, stone, light, cap, riser, boulders},
  "#RRGGBB" each; a key left out or unreadable plays RedCanyon's default. Defaults (= the file's today):
  rock **#785C5E** (0.47, 0.36, 0.37); cliffs near **#856B6E**, far **#705963**, farther **#594A57**; boundary wall stone
  **#7A6363**, light **#8C7370**, cap **#544045**, risers **#47383B**; boulders **#6B5457**.
  Pass 78's: rock (0.62, 0.34, 0.24) over an orange painting; cliffs (0.78, 0.6, 0.5), (0.62, 0.42, 0.36),
  (0.46, 0.30, 0.30) over orange sandstone; wall (0.60, 0.40, 0.30) / (0.68, 0.47, 0.35), cap (0.40, 0.26, 0.21),
  risers (0.34, 0.22, 0.18), boulders (0.5, 0.33, 0.26).
- The rock painting (redrock.png) is recoloured to `rock_color` in the terrain shader: its luminance over its own mean
  (`rock_tex_lum` **0.184**, linear) times the colour, so the bands and cracks are light and dark only and the hue is
  the key's. The cliffs' sandstone painting is grey bands (mean about 0.84) since pass 79, so a cliff colour is the colour
  drawn (times the painting's light and dark).
- On the phone's screen (seed 11, the same views before and after): the rim's rock hue 25 -> 22-24, saturation
  0.65-0.67 -> 0.53-0.56, value 0.80-0.82 -> 0.66-0.70; the boundary wall saturation 0.62 -> 0.53, the cliffs 0.66 -> 0.52.
  The sand (pass 61's sand_color / river_color, the sand and cracked paintings) is unchanged: sand on the screen
  (242, 210, 145) before and after.
- The sun and the sky's light are warm (sun (1.0, 0.85, 0.65), ambient (0.95, 0.80, 0.66)): every colour reads more
  orange on the screen than as authored, so the defaults lean a touch rosy (the editor's help says so). Not changed:
  the light, the fog (0.93, 0.66, 0.42 at 0.004), the sky, the posts (0.36, 0.25, 0.16), stage 3's hell tint (the hell
  rim reads hue 15, a clear red).

#### The dynamite's lead (Garry: "Throw the dynamite in front of the enemies.")
- `params.lead` on **lob_grenade** and **golden_pineapple** only (every other Lobber throws where it did): the bomb goes
  where its crowd will be when it blows. JSON block on both: share **1.0**, mode **"predict"**, max **6.0** m, gap
  **1.5** m, radius **3.0** m, hero_ahead **0.5** (Lobber.LEAD_* the same when a key is left out; `lead` may also be a
  bare number = the share, or true).
- **The wait** = the lob's flight, clamp(distance / speed, 0.35, 2.5) s as ProjectileManager.lob times it, + the
  fuse's `seconds` (1.0 s); a weapon carrying Sticky counts the flight only (it rides what it catches).
- **chase** (the line's far end): the crowd within `radius` of the chosen spot closes on where the hero will be
  (his position + his velocity x hero_ahead x the wait) at its mean walking speed (each creature's own speed, averaged,
  on the world's clock: High Noon's slow is in it; the push a hit gave it is not) for the wait, x share, stopping `gap`
  short of him; at most `max` m.
- **predict** (the default): LEAD_STEPS + 1 = **5** spots from the chosen one to the chase's (0, 1/4, 1/2, 3/4, all) are
  scored by how many creatures will stand inside the blast's radius (the weapon's `area`) there when it goes off: every
  creature within area + the line's length + 6 m, walking on its own, closes on where the hero will be at its own pace
  for the wait, stopping `gap` short of him; one standing still (biting, winding up) stays. The best spot wins; on a tie
  the one further ahead (Garry asked for "in front").
- **No lead**: a crowd within `gap` (1.5 m) of the hero; a crowd that stands; a Sticky throw at a priority target (the
  Golden Pineapple's every throw, so its lead only plays when no strongest creature is in reach); the "walk" mode is the
  straight extrapolation the contract named (its mean velocity x the wait, drawn back to `gap` from the hero), kept as a
  choice, not played.
- The led spot stays within the weapon's `range` of the hero and inside the arena (radius 66 - 1.5 m), on the ground
  there. A priority target (special, Elite, boss: pass 73's first bomb) is led by its own walk.
- **Spread** (pass 36): a led throw's crowd spot at the throw (`lead_from`) is claimed beside the led spot, so the next
  bomb weapon still picks another crowd.
- **Measured** (game/tools/_p79_WORLD_lead_probe.gd: Red Canyon, the Drifter in god mode with the Dynamite Stick alone,
  6 seeds x 60 s each way, the lead off then on; "caught" = creatures inside the blast as it goes off):
  - level 1, the run sim's kiting pilot, 1:30-2:30: caught a blast 8.61 -> **9.00** (+5%), kills a blast 2.78 -> **3.19**
    (+15%), kills a minute 77 -> **88** (+14%).
  - level 5 (area 3.8, two sticks), kiting, 2:30-3:30: caught 5.95 -> **6.48** (+9%), kills a blast 5.47 -> **5.84**
    (+7%), kills a minute 334 -> **353** (+6%).
  - level 5, the hero standing still: caught 8.56 -> **8.84** (+3%), kills a minute 462 -> **473** (+2%).
  - Paired on the same blasts (every blast also scored at every candidate spot at the moment it went off): the predict
    spot over the unled one +1.29 +- 0.13 (L1 kite, +16%), +0.83 +- 0.07 (L5 kite, +14%), +0.59 +- 0.07 (L5 standing,
    +7%); the contract's plain walk lead +0.09 +- 0.17, +0.03 +- 0.09, -0.22 +- 0.11 (no better than none: the crowd near
    the hero is a stream and the blast is wider than the lead); the plain chase +0.44, +0.18, -0.20.

## 27. Pass 80 (v0.66): the Watch and its bot, the wisp tracer, the fort wall, the oases

Garry's request (2026-10-15, tools/dl/p80/REQUEST.md). Each lane's rules as it wrote them.

### 27.BOT The bot: an explorer that uses the map and explains its choices

Everything here is the TOOL's (game/tools/bot/, never exported): the run sim's and the Watch's player. No game rule
changed. Where each number lives: Bot.gd (presets, the planner's commitment and hold, the Shop and the Stranger),
BotGoals.gd (knowledge, values, utility), BotCards.gd (the scores), BotLegs.gd (the legs and their dials).

#### The default
The Sim (sim_run.gd, tools/sim_batch.py, the Level Editor's Sim tab) and the Watch play the **Explorer** preset unless
told otherwise; `preset=sim77` is pass 77's bot exactly (proven: the same 10 seeds replay every series and event
identically, before and after the move and again with the final code).

#### Presets (Bot.PRESETS)
| | skill | style | reaction s | dodge | daring | stray m | explore | totems | barrels | power-ups | structures | shop | stranger | boss | cards |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sim77 | 1 | balanced | 0 | 1 | 0.5 | 60 | 0 | off | off | on | off | off | off | leash | tier |
| explorer | 0.9 | balanced | 0 | 1 | 0.5 | 60 | 0.6 | on | on | on | on | on | on | leash | score |
| careless | 0.4 | balanced | 0.6 | 0.5 | 0.8 | 60 | 0.4 | on | on | on | on | on | on | free | score |
| expert | 1 | balanced | 0.1 | 1 | 0.45 | 60 | 0.7 | on | on | on | on | on | on | leash | score |

#### Knowledge (BotGoals)
- Seen = within **12 m** of the hero once (SEE_R; no pointer shows structures, barrels or Totem Poles: exploring finds them).
  Power-ups count while within **18 m**, chests within **45 m**.
- The arena as **11 m** cells (CELL); a cell is visited once he has been within 12 m of its middle; explore walks to the
  unvisited one with the best utility.

#### Utility (one goal at a time)
utility = value x taste[kind] x mood[kind] x jitter[thing] x style[kind] / (1 + distance / **18 m**)
- taste: per run and kind, **0.6..1.4** (hash of the seed); mood: per kind and **120 s** spell of play, **0.7..1.3**; jitter:
  per thing, **0.85..1.15**. Same seed, same rolls; seeds differ ("sometimes power-ups, sometimes structures").
- Values: Totem Pole **80**; barrel **10**, black **28**, x**1.6** with Barrel Rush held; chest **70**; explore **30** x the
  explore dial x (0.5 + share of the arena unseen); power-ups: vacuum **35**, nuke **25**, buff **22**, shield **22**, gold
  **15**, pollen **12**, leap **10**, others **12**, a heal **90** x (1 - health) below **80%** health (none above); a
  power-up is no goal if it would expire before he arrives (life < distance / 3.6 m/s + 1 s).
  Structures: Healing Well **90** x (1 - health) below 80%; Uber Magnet **15 + 40** x (XP lying on the map / the next
  level's XP), at most **80**; Travelling Shop **45** only with **0.56** x the stage's shop base (300/500/700) in the purse
  and shop on; the Stranger **40** only at **60%** health or more and stranger on; Teleport **60** only under **40%**
  health with danger over **0.3**; War Drum (buff) **28**, XP Beacon **55**, Loot Cache **40**, dice **20**, others **15**;
  the Strongbox (bank) never.
- The sweep (the gems lying, pass 77's lure) is a candidate too: **2000** x (its worth / the next level's XP), at most
  **45** (gems wait on the sand; a Totem Pole near beats a pile).
- Style words (a factor on a kind): damage: War Drum x1.5, totem x1.1, explore x0.9; safety: Healing Well x1.5, heart
  x1.5, explore x0.7, barrel x0.8; greedy: barrel x1.5, chest x1.3, Loot Cache x1.5, gems x1.3, Uber Magnet x1.4, Shop x0.6.
- Far limit: **12 m** at 35% health or less, **75 m** from 80% up, times (1 - **0.6** x danger); a heal goal reaches **35 m**
  at least. Danger = damage taken fading over **30 s**, over max HP (0..1). While a boss lives (boss "leash") every goal
  must lie within **10 m** of it and explore waits.

#### Commitment (Bot)
- A new plan every **0.5 s**; a goal held is kept unless one **1.4** x better turns up (the sweep is no commitment); none
  under **4**; patience **8 s + 0.55 s** a metre + the structure's use time; given up = rests **40 s**.
- The kite wins when the crowd closes: **5** or more within **3 m**, a big one or a rocket pushing (danger push > **0.4**),
  or under **50%** health with a creature inside the flee distance; back to the goal when fewer than **3** are within 3 m,
  the push is under **0.2** and (hurt) none is inside flee distance, after **0.4 s**. Within **2.5 m** of a barrel, power-up
  or chest he grabs it whatever comes; a structure's use **60%** done goes on above **40%** health. Patience runs at half
  speed while he kites.
- He stands still inside **0.55** x a structure's ring radius to use it.
- The musts stay pass 77's: the boss's chest, then the portal (45 s then an assist), then back to a living boss (10 m / 7 m).

#### Scores (BotCards)
score = dps x w.dps + survival x w.survival x danger weight + plan x w.plan + greed x w.greed
- dps: % of the estimated DPS now (WeaponInstance.dps_estimate, the pause screen's) on temporary instances, at most
  **100**; stat effects through a copy of the hero's sheet with every weapon rebuilt; crit as (chance x (crit damage - 1)).
- survival points a unit: max HP **80** (a fraction; add as a share of max HP), damage reduction **150**, regen **30** (per
  % of max HP a second), move speed **60** (add as a share of 3.6 m/s), evade **120**, lifesteal **300**, shield **80**,
  revives / Phoenix **25**, hit invulnerability **10**, heal mult **30**, overheal **20**, heal pulse **40**, last stand
  **15**, thorns **20**, heal drop **60**, hurt speed **20**, still regen **15**, crit heal **40**, freeze **60**.
- greed points a unit: XP gain **60**, magnet **20** (add over 1.5 m), luck **40**, greed **40**, coin drop **30**, XP drop
  **60**, gold on hit / coin on hit **20**, power-up chance **20**, power-up duration **10**, XP pull radius **5**, rate
  **10**, vein **40**.
- plan: evolution **40**, favourite **20**, weapon level **6** (+**8** on the last), line level **3** / new line **4** (+**10**
  on the last), new weapon **10** x free weapon slots' share, mutation **10** (+**6** the path's last; **5** with no weapon
  of its family), perk **8**, passive item **2**, effects no table knows **3**.
- danger weight: 0.6 + danger + 0.5 x (1 - health), i.e. **0.6..2.1**.
- Style weights (dps / survival / plan / greed): balanced 1 / 1 / 1 / 0.6; damage 1.6 / 0.6 / 1 / 0.3; safety
  0.7 / 1.8 / 0.8 / 0.3; greedy 0.8 / 0.7 / 0.8 / 1.8.
- skill: each score read with a gaussian error of (1 - skill) x **25** points; the best read taken (skill 1: always the
  best). Small differences (Totem gifts) flip more often than big ones (a new weapon), as a player's would.
- The Shop: the best ware less its price x **0.03** points a gold x greed's weight, bought when that is **6** or more and he
  can pay. The Stranger: taken at **60%** health or more when the ware's score less the cut (its % of max HP x **0.8** x
  survival's weight x the danger weight) is **5** or more.

#### The legs' dials (BotLegs)
- daring: keep **4.5 + (0.5 - daring) x 4** m, flee **2.6 + (0.5 - daring) x 2** m (0.5 = pass 77's 4.5 / 2.6).
- reaction: a warning on the sand is seen once it has been up that long; the big ones' and rockets' push is the one of
  that many seconds ago. dodge: the share of warnings seen at all (a fixed roll per warning from its place, length and
  kind with the bot's seed). stray: the sweep's reach. boss free: no leash.

#### Measured (10 runs each: Drifter, a quarter board, 25:00, death=keep so every fall counts and every run plays to the end, seeds 1-10, game 0.65 + this lane's tools)
| bot | falls mean / median | first fall (median; runs with none) | level at 5/10/15/20/25 min | kills | XP | gold | Totem Poles (by 20:00) | barrels | other structures | power-ups | shop buys / visits (all runs) | Stranger deals / visits | metres walked | map seen | goals given up |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Sim (pass 77) | 13.9 / 8.0 | 9:36 (0 none) | 12 / 30 / 41 / 54 / 71 | 17.0k | 131k | 39.0k | 0.0 (0.0) | 16.9 | 0.8 | 81 | 0/0 | 0/2 | 6640 | 0% | 0.0 |
| Explorer (the default) | 13.4 / 6.5 | 9:44 (3 none) | 14 / 30 / 38 / 53 / 69 | 17.8k | 127k | 39.6k | 9.6 (9.1) | 26.0 | 6.7 | 64 | 4/8 | 4/11 | 6130 | 93% | 4.7 |
| Careless | 15.2 / 13.5 | 8:25 (1 none) | 12 / 27 / 36 / 50 / 66 | 16.4k | 121k | 33.7k | 9.2 (7.8) | 26.1 | 6.5 | 67 | 6/8 | 4/11 | 6159 | 91% | 5.2 |
| Expert | 6.2 / 3.0 | 11:03 (3 none) | 12 / 28 / 39 / 52 / 68 | 17.7k | 124k | 42.4k | 10.1 (9.1) | 25.2 | 6.4 | 79 | 3/8 | 6/11 | 6102 | 95% | 6.0 |

- Falls (death=keep counts every fall; one run with 40-50 falls moves a mean a lot, so the median and the first fall are
  the steadier numbers): the Explorer falls no more than pass 77's bot (median 6.5 against 8.0, three runs of ten never
  fall against none), the Expert least, the Careless most: the dials move the right way.
- The map: the Explorer uses 9.6 of the 10-12 Totem Poles a run (9.1 by 20:00), breaks 26 of the 33 barrels (pass 77's
  bot 17, by walking into them), uses 6.7 other structures (0.8), sees 93% of the arena; the Shop sells in about half
  its visits, the Stranger's deal is taken in a third (hurt or not worth the cut otherwise).
- The cost: about 3% less XP and 2 levels fewer at 25:00 than pass 77's sweep-only bot (the gems wait while he walks to a
  pole), the same kills and gold.
- The sims: tools/dl/p80/BOT/sim/runs/{base_head, m1_sim77, f_sim77, e1_explorer, e2_explorer, g_explorer, g_careless,
  g_expert}; base_head (the code before the move) and m1_sim77 / f_sim77 (preset=sim77 after) are identical player by
  player. Tuning between e1 and e2: the sweep's utility had been the gems' raw worth (it swamped every pole past 8
  minutes: 5.8 poles a run); it is now their worth over the next level's XP, capped at 45, the pole 80 (was 60), and the
  sweep is no commitment (a goal may take over at once).

### 27.WATCH The Watch tool

A tool, not the game: nothing here changes a phone's or a played run. Numbers live in game/tools/watch/*.gd.

#### Speed (WatchClock.gd)
- The speeds: pause, 0.25x, 0.5x, 1x, 2x, 4x, 8x (SPEEDS). Godot runs with `--fixed-fps 60`: every frame is one step of
  1/60 s of game time (one process step and one physics step) whatever the wall clock does.
- Up to 1x the clock slows: Engine.time_scale = the speed (each step that much shorter), 60 frames a wall second. The
  game's own writes to the time scale (the hit-stop's 0.08, Last Stand's slow clock) are kept and multiplied in
  (game_scale_of: a value the Watch did not write is the game's; the Watch's nominal value or 1 written back = the
  game's 1). Below 1x the hit-stop does not fire (the game asks for a clock of 1 first).
- Above 1x the step stays 1/60 s (a weapon still fires at most once a step; Run.rule_seconds counts the run's own
  clock: sim_clock), and the frames come 60 x the speed a wall second; a frame is drawn only when 1/DRAW_HZ = 1/60 s of
  wall time has passed since the last one drawn (RenderingServer.render_loop_enabled), 1/DRAW_HZ_FAST = 1/30 s from 4x
  on (a drawn frame costs about 4 ms more than one that is not: the game's step needs that time there), so at 4x seven
  frames in eight are not drawn.
- The frames not drawn skip the work that only draws (Run.sim_mode, the run sim's fast mode, set per frame; skip_draw=0
  keeps it): the crowd's, the shots' and the pickups' drawing, effects, the HUD's frame and the floating numbers. So above
  1x an effect or a tracer made on a frame that is not drawn is not shown, and the HUD's timers and the effects age on
  the drawn frames only (they run at wall speed).
- Frame pacing is the Watch's own (pace): --fixed-fps turns the engine's frame limit off, so each frame waits for its
  1/(60 x speed) s of wall time (1/60 s while paused); a frame that ran late is made up by the next ones not waiting, at
  most CATCH_UP_US = 0.25 s behind (past that the clock starts again from now: the run goes as fast as the PC lets it).
- The reached speed: game seconds over wall seconds of the frames that played (a screen up does not count), in
  half-second buckets, the newest 4; shown in the header (red, "short") when under SHORT = 90 % of the speed asked.
- Short of the speed asked (at least two buckets measured): the drawing steps down to DRAW_HZ_FAST = 30 frames a wall
  second at any speed (1x included: half the steps not drawn), so the steps get the time; after LOW_DRAW_RETRY_S = 20
  wall seconds of play it tries the full rate again (and at every new speed, step, run to a level-up or pause).
- Sound is off above 1x (and when switched off); the floating damage numbers are off above 2x.
- Step one second: STEP_SECONDS = 1 s of play at the speed running (1x from a pause), then paused. Next level-up: 8x
  until a level-up's cards are on screen (not a mutation offer), then paused before the bot picks.
- The Watch's pause holds the tree paused (re-asserted every physics and process frame, as a game timer between two
  screens may unpause it) and does not tick the bot; going on hands the tree back to the game's own paused state. The
  game's SubViewport is pausable (the game pauses as it does under the window's root); the Watch and its panel process
  always. Before the run is up, while paused and after the run, the frames come 60 a wall second.
- The badge over the phone view: PAUSED, STEP 1 s, TO THE NEXT LEVEL-UP 8x, RUN OVER, or the speed when it is not 1x
  (with the reached speed when short); nothing at a plain 1x.

#### The bot in the Watch (Watch.gd)
- A screen (cards, a chest, a totem, the Stranger, the shop, the portal, Down!, the TAP TO GO gate) stays HOLD_S = 0.8
  wall seconds at 1x (HOLD_S / speed above it) before the bot answers it, so it can be seen. One left up STUCK_S = 15
  wall seconds is reported in the header (Down! is then given up).
- The bot is tools/bot/Bot.gd (lane BOT) with the options passed; the stand-in (bot=stub) answers the screens as pass 77
  did and only kites.

#### The numbers (WatchData.gd, the Sim tab's definitions)
- Real DPS: damage dealt in a second (the recorder's rows), the mean of the last DPS_WINDOW = 5 s.
- Danger: HP lost in a second as % of max HP, the mean of the last 5 s.
- Keeping up: (the crowd's HP alive - the boss's HP) / real DPS, in seconds; none under 1 DPS.
- Creatures close: within 3 m and 6 m (the rows' near3 / near6).
- The real DPS change after a decision: the mean real DPS over the AFTER_S = 30 s after it against the BEFORE_S = 30 s
  before it (fewer at the start of a run), filled once the run has played 30 s past it (at the run's end, what there is);
  no percentage when the DPS before was under 1.
- Threat: HP lost and hits by creature over the last THREAT_S = 10 rows; a fall's last hits are the hero's damage log's
  newest 6 when the recorder's death event is read.
- The charts: the last WINDOW_S = 180 s of play scrolling (or the whole run, G), at most 360 points a line (buckets of
  means past that); the damage share in at most 240 columns, each its rows and the 4 s before them, the window's top 6
  sources by name and the rest "other", a source keeping its colour for the run. The grey line is the Sim result's mean
  of the same series (dps: its 5 s smoothed DPS; hp; level; danger), one value a second of play.
- The panel is refreshed every REFRESH_S = 1 wall second, the charts at most every CHART_EVERY = 0.5 s when new rows came.

#### The run
- The save sandboxed (nothing reaches the disk; the Watch's own user folder 88fits_watch anyway), runs_started 1, the
  board as given, every unlock quest done (unlocks=all), the settings as the Sim's (the north-up camera the bot steers
  by, ranged weapons on what is on screen, pierce drop-off, no hints, not debug), the damage numbers on (numbers=0 off).
- The launch in memory: hero, map, map_seed = seed, sim_clock (the rules that count real time count the run's clock),
  `watch: true`; the dice seeded as sim_run.gd seeds them. A seed does not replay exactly here (the drawing and the
  sounds draw from the global dice), so a Watch and a Sim player of the same seed share the map, not the run.
- The end: the record goes to analytics/runs/tools/ (RunAnalytics.mirror_root = the repo's analytics/), the decision log
  beside it as <stamp>_decisions.csv; the Game is freed before its Results screen comes (the last frame stays, dimmed).
- One Watch at a time (tools/dl/locks/watch.lock); it never takes the Godot lock or the Sim's.

### 27.TRAIL The tracer's wisp

##### 27.TRAIL The tracers' looks (pass 80, lane TRAIL)

###### Tracer styles (ProjectileManager, "pass 79 (lane FX): the tracers' lines" section; core/shaders/tracer_line.gdshader)
Garry: "The revolver trail looks awful, I don't like it at all. Search the internet for a better option than this, I want
a clear visible trail, but one that doesn't look this bad." Research: tools/dl/p80/TRAIL/research.md.
- Every tracer weapon draws one of five looks, `params.tracer_style`, default `TRACER_STYLE` = **wisp**:
  - **wisp** (the shipped look): a tapered streak riding with the bullet, its first `hot` 30% of the life (0.165 s at the
    default 0.55 s): full width at the bullet tapering to a point ((1 - f/hot)^0.75), a solid stroke of the colour
    (42% of the width) with a thin white-hot middle, a soft halo of the same colour round it (opacity 0.42 falling to
    0 at the edge), the colour lit to full brightness towards the bullet (head_glow 0.8). Under it a pale smoke of the
    colour mixed 78% to a warm white, fading in over the first quarter of the life and out after ((1 - f)^1.4, at
    most 0.38 opaque), widening from 0.72x to 2.4x the head width and rising 0.35 m/s. No sway, no grey.
  - **streak**: the streak alone, life 0.13 s (4.3 m behind a 33 m/s Revolver round), white middle for 70% of it, fading
    over its last 45%.
  - **ribbon**: life 0.3 s, tapering (1 - f) while widening 0.7x over its life (a wake), white middle for its first 40%,
    fading (1 - f)^1.1.
  - **toon**: hard bands (white middle 24% of the half-width, the colour, a dark outline past 74%: the rim colour x 0.62),
    0.6 of the width (no halo), tapering (1 - f)^0.35, opaque until its last 22%; life 0.2 s.
  - **line**: pass 79's line unchanged (life 1.4 s by default, 0.05 m, widens, drifts up, sways, greys).
- Each style's own life (`TRACER_STYLE_LIFE`: line 1.4, streak 0.13, ribbon 0.3, wisp 0.55, toon 0.2 s), head width
  (`TRACER_STYLE_WIDTH`: 0.1 m; the line 0.05) and hot part (`TRACER_STYLE_HOT`: streak 0.7, ribbon 0.4, wisp 0.3,
  toon 0.5) apply where the weapon sets no `tracer_life` / `tracer_width` / `tracer_hot` (0.02..1).
- Width `tracer_width` is now the width at the bullet including the glow; the head is never under 3 screen pixels (the
  line: 1.5, which pass 79 meant but never got: the Compatibility renderer flips the projection's y on a render target,
  so the pixel floor came out negative and did nothing).
- Colour and order unchanged (`_tracer_colour`). The rim (the stroke's edge, a darker shade of the same hue: colour^2.4
  x 0.9) takes 35% of a dark colour's edge and 90% of a light one's; a light colour (luminance 0.45..0.85 and up:
  Silver Bullet, gold) also gets a body 30% towards its rim and a halo 85% towards it, so it reads on the light sand
  (value contrast). A light and saturated colour (gold; `warm_light`: luminance 0.45..0.85 x saturation 0.25..0.55)
  gets its body 80% towards its rim instead (a deep amber, not a cream fill) and its white middle only over 30% of its
  usual length (the tip). Alpha blending only (additive washes out on the sand).
- Segment laying, `TRACER_SEG_MIN` 0.3 m (0.6 m past 60 shots), `TRACER_LINE_MAX` 2048 and `tracer_clear` as pass 79.

###### Content set (pass 80)
- Revolver: `tracer_style` "wisp" (named in its JSON so it is one word away), colour #C41E16 (was #8B0A0A: Garry's "dark
  red, see-through" kept as a readable crimson), alpha 0.9, width 0.2 m (was 0.045), its 0.9 s life dropped (the
  style's 0.55 s), `tracer_clear` 1.1 m kept.
- Silver Bullet and the Golden Revolver's `final`: width 0.3 m (was 0.11), #C9DCEF kept (the light-colour rim makes it
  a steel-blue edged silver).
- Drum Mag 0.13 m (was 0.065: still bolder than the Tommy Gun's 0.1).
- Tommy Gun and Chicago Typewriter: width the style's 0.1 m, life 0.3 s (was 0.2 for the line) with `tracer_hot` 0.45
  (0.135 s of streak, then a short smoke: a burst does not fill the screen).
- Boomstick and Blunderbuss pellets: width 0.08 m (was 0.035), life 0.25 s (was 0.16), `tracer_hot` 0.5.
- Dragon's Breath: its 0.28 s life dropped (it takes the Boomstick's 0.25 s; its fire is in the colour). On Fire's 0.3 s
  (the ball's "short flame tracer") and Toxic Peas' 0.45 s kept.
- Turrets, Iron Bastion: the wisp's own 0.55 s, 0.1 m.
- The rounds themselves (content visuals): the Tommy Gun's and the Chicago Typewriter's core box 0.12 x 0.12 x 0.95 m ->
  0.055 x 0.055 x 0.4 and its halo capsule r 0.105 h 1.08 -> r 0.055 h 0.5; the Boomstick's and the Blunderbuss's
  pellet core capsule r 0.055 h 0.36 -> r 0.035 h 0.22 and halo r 0.085 h 0.46 -> r 0.05 h 0.28 (they read as fat
  cream sticks with an orange outline; now a short white-hot tip in a thin amber halo, the tracer behind is the body).

### 27.WALLS Sand to the wall, the fort wall, the cliffs, the sign

#### Sand to the wall (Garry: "make the edges of the map just sand instead of that dark orange stuff, that orange-dark
#### stuff should be behind the walls")
- Inside the wall the ground is sand all the way to the wall's foot: the terrain's red-rock weight
  (RedCanyon.rock_weight, the vertex colour's blue) is **0** everywhere closer than arena_radius + ROCK_FROM (**66.4 m**)
  and **1** from there out (the strip between the wall and the cliffs, and the map's corners). Pass 79's rim was rock
  from rim_start (44 m) out, blended by noise, which drew a stair-stepped edge on the sand.
- The rim still rises: from `rim_start` **44 m** the sand climbs by `rim_height` **2.2 m** x (rim fraction)^2 at the wall
  (unchanged), with softer bumps: `rim_bumps` **0.45 m** at `rim_bump_freq` **1.4** x the dunes' noise (were 1.2 m at
  2.5x, "broken red rock"). rim_start now means where the sand starts rising towards the wall. Nothing about play
  changes but the ground's height near the rim (a few tenths of a metre at most).
- `rock_color` (#785C5E) is the ground outside the wall now; the scatter's "rock fields near the rim" (36 m out to 7 m
  inside the wall) stand on sand.

#### The cliffs (Garry: "the textures on the mountains behind the walls look too low res")
- A painted rock face, art/env/cliff_rock.png, **2048 x 2048**, seamless, VRAM compressed with mipmaps, anisotropic
  filtering. Painted by Flux.2 Klein 9B on the AI server (prompt "Monument Valley mesa cliff face ... dozens of thin
  horizontal sandstone layers", 2048 px, seed 35, one of 6 seeds at 2048 and 12 at 1024, picked by eye), made seamless
  (rolled by half, the seam cross repainted under a soft mask, DifferentialDiffusion, 8 steps), brought to a grey mean
  (0.8, 15% of its own hue kept) so `wall_colors.near/far/farther` stay the colours drawn.
- Each ring's own UVs in metres: round the ring a whole number of tiles, up the face the height, over the top the
  distance: one tile is **14 m** (near ring), **20 m** (far), **28 m** (farther), so the farther ranges' strata are
  bigger. The near ring is 146 texels a metre (the sand is 92). The face is pushed in and out by up to **0.9 m** at a
  third and two thirds of its height (and up and down by up to 0.6 m), so it breaks into ledges.
- The colours did not move: on the phone's canvas (seed 11, the north rim pulled out) the cliffs read hue 26-27,
  saturation 0.53-0.54, value 0.66-0.70 (before: 26-27, 0.51-0.52, 0.68-0.73).

#### The fort wall (Garry: "Make the walls look like sandstone castle walls (but western)")
- The boundary is a western sandstone fort wall (CanyonWalls.fort_wall) on the old footprint: **1.7 m** thick centred
  on the arena's edge (66 m), its foundation **0.8 m** under the ground. It has no collider and no obstacle: the hero is
  stopped by RedCanyon's invisible fence 1.1 m inside, as before (40 boxes, unchanged). Nothing of the wall reaches into
  the arena past the fence's inner side (64.65 m): its face at 65.15 m, the cap course and the towers' trim 0.1 m over
  it, the vigas' tips at 64.81 m (the wall) and 64.76 m (the towers).
- Its walk stands **2.0 m** over the ground at its foot, level along a stretch and stepping by **0.25 m** where the
  ground (smoothed over five stretches, 120 round the ring) climbs: 1.5 to 3.0 m over the very spot (the old wall's
  blocks stood 1.9 to 2.75 m). Above the walk the parapet (**0.55 m** thick on the outer edge) rises **0.45 m**, and on
  it rounded merlons (Spanish colonial "almenas") **1.0 m** wide every **1.7 m**, **0.46 m** tall (0.22 straight + 0.24
  arc). The inner face leans back **0.12 m**; a cap course **0.22 m** tall juts **0.10 m** under the walk.
- Vigas (round wooden beam ends, radius **0.10 m**) jut **0.45 m** from the face **0.42 m** under the cap course every
  **1.7 m**; three on each tower's face. A squat tower every **30 degrees** (12; the first at 15 degrees, none square to
  the north): **5 m** wide, standing **1.4 m** out past the outer face (its inner face flush with the wall's), its roof
  **1.4 m** over the walk, a parapet and three merlons on its inner and outer edges.
- The blocks: art/env/fort_wall.png, **1024 x 1024**, one tile every **3.2 m** (320 texels a metre), courses level in
  the world; Klein 9B ("dressed sandstone block wall ... Spanish mission fort", seed 1 of 6 candidates in 3 prompts,
  seamless repaint seed 11), grey on average (0.82).
- Drawn **unshaded**, like the painted scenery: the sun stands in the north-east, so a lit wall showed the camera (which
  looks north) its dark side round the whole north half. Its light and shade are painted into its vertex colours: tops
  `light` / `cap`, faces `stone`, the sides across `riser`, the outer face x 0.75, the foot x 0.68 up to 0.9 m over the
  ground, each stretch +-7% (noise). The vigas are lit (wood, `beams`).
- Colours (map keys, picked by eye from six palettes on the phone's canvas): stone **#C59E7B**, light **#DEC09F**, cap
  **#A58266**, riser **#7A604E**, beams **#4F3626**. Stage 3's hell multiplies the wall by (0.97, 0.79, 0.72) over its
  tween, as the ground.
- Kept: the 36 posts before the wall (one MultiMesh) and a skull on every fourth. Gone: pass 79's stacked blocks,
  battlements and the boulders on top.

#### The sign's z-fighting (Garry: "There is some z-fighting on the sign 3d. Fix it")
- Cause: sign_depth.gdshader (pass 60) draws a sign at its foot's depth and kept only **2%** of its own depth, so the
  board's stub behind the post and its part inside the post lay about a millimetre behind the post's face, under what
  the depth buffer tells apart 25-50 m away: they flickered through the post as the camera moved; the nail heads, 4 mm
  proud, flickered in and out of the wood.
- Fix: the depth a vertex owes to its height over the foot keeps `squash` **0.02** (the tall post never reaches over a
  hero south of its foot), the depth it owes to its run over the ground keeps `squash_h` **0.25**; `bias` 0.03 m
  unchanged. A board pointing straight at the camera (1.13 m out on the drawn sign) comes 0.2 m nearer than the foot; a
  hero against the post's south side (his feet 0.57 m from its axis) stands 0.4 m nearer, so he still draws over it. The nail heads stand **12 mm**
  proud (blender_sign.py, sign.glb regenerated).
- Measured (game/tools/_p80_WALLS_shots.gd `only=signdiag`: every sign drawn alone with the game's depth and with true
  depth, the hero walked past each in 10 places): the sign's pixels sorted differently from true depth **5.45% -> 0.40%**
  at the play zoom and **2.76% -> 0.30%** pulled out; what is left is single pixels along edges (the moved vertices
  rasterise a hair apart), no clusters.

#### Cost (perf)
- Draw calls unchanged (the wall mesh and the vigas' MultiMesh replace the wall mesh and the boulders' MultiMesh; the
  three cliff rings stay three). Primitives +19.7k (92.8k -> 112.6k on the PC's frame: the merlons, the vigas, the
  towers). Texture memory -0.7 MB (the old sandstone painting, 4 MB uncompressed, is no longer loaded; the two new
  paintings are VRAM compressed with mipmaps, about 3.4 MB together). perf_late build=six (504 x 1122, fixed 60):
  14.5 / 15.6 / 17.1 ms a frame after against 15.8 / 16.0 / 17.9 before, draw calls 183 / 188 / 207 against
  181 / 192 / 214 (a shared machine: noise).

### 27.OASIS Two or three oases; the water's slow

Garry (2026-10-15): "make the water slow everyone down when they walk though it, not by a lot, just 10%. And make it so
there are 2 oasis at least per level generation in the red canyon, sometimes 3".

#### The oases (RedCanyon._roll_oases; map keys in red_canyon.json timeline_data `oases`, WaveTimeline.OASES_DEFAULTS)
- **Count**: `min` 2 a run; then one more with `extra_chance` 0.35 each, up to `max` 3. Measured over 2,000 seeds:
  1,298 with two, 702 with three (35.1%), never fewer than two.
- **The first lake is rolled exactly as the one lake was** (the same draws, so a seed keeps its first oasis where it
  was: seed 5's at (28.5, -2.5), 5.64 m); the others after it.
- **Each extra lake** like the first: radius 5.5-7.5 m (RedCanyon.LAKE_R), centre 24 m out to 18 m inside the wall (24-48
  m from the middle), at least 8 m past its radius off the flats (the start stands in their middle), at least 5 m past its
  radius off the dry river's bed (half its width). New: every two lakes' dishes (each reaches 1.6 x its radius,
  LAKE_DISH) at least `gap` 10 m of open ground apart. A lake that finds no spot in 240 tries takes a third of the gap
  for 120 more, then no gap (dishes still apart) for 120; one past `min` that still finds none is left out. Over 2,000
  seeds the gap never had to relax (closest pair 10.0 m), river clearance never under 5 m, flats never under 8 m, every
  dish at least 6 m inside the arena's edge.
- **Each oasis has everything the one had**: the dish (knee-deep flat floor, `lake_depth` 0.45 under the shore, the
  surface 4 cm under the shore), the damp ring, its own water disc ("Oasis", "Oasis2", "Oasis3", one material), 8-10
  palms at the shore and 22-28 low greenery round it (the first lake's greenery drawn first, as before).
- **Everything that keeps out of the water keeps out of every lake** (in_water is true in any lake): barrels, structures
  and Totem Poles (3 m off), signs, flowers, the Trampoline, spawn spots (rings cut every lake's arc out; a point ahead
  turns past whichever lake holds it), the painted scenery (1.2 m off the water), the creature shadows and the hero's
  water cut (each lake's own disc and level).
- **Bush patches** (pass 61's five to seven a map): a patch keeps its centre 11 m + 0.6 of its radius off every lake's
  water as before; past 200 of its 300 tries (BUSH_LAKE_RELAX) only 6 m + 0.6 of its radius (BUSH_LAKE_NEAR), and a map
  still short of five patches gets 200 more tries (BUSH_EXTRA_TRIES) out to 10 m inside the wall, the regions 0.6 of
  their 18 m apart. Without this, three oases left 3 seeds in 60 with four patches (seed 11); with it, 200 seeds all have
  five to seven.

#### The water's slow (map key `water_slow` 0.1, WaveTimeline.WATER_SLOW_DEFAULT; 0 = off, held to 0..0.95)
- **Anyone walking in water moves at 1 - water_slow = 90% of his walking speed**: in any lake, out to in_water's edge
  (1.02 x the lake's radius; the drawn disc reaches 1.06).
- **The hero** (Player._wade_mult): his stick's walk (and a cannot_stop hero's walk on) x 0.9, on top of everything else
  (his speed stat, the map's pace, a harpoon rope's leash). Not slowed: in Hang Time's flight (airborne), more than 0.35 m
  over the ground (a launch, a leap: WADE_AIR), dead, in the spawn beam; never a shove, a knockback or a pull (his `_kb`).
- **Every creature, Elite and boss** (EnemyManager._wade_mult): its own move x 0.9 (vel: the walk, the crowd's spacing
  in it, a charge, a roll, a scripted move, a flight from a hit). Not slowed: a push, a knockback or a pull (kb), anyone
  in the air (tossed by a tornado, bounced, launched, held by the Gravity Gun: those never walk), under the sand
  (burrowed, hidden) or part-way (rising out of it, sinking into it). Its walk cycle keeps its pace (the legs are under
  the water).
- **The rocketeer's rocket keeps to 90% of the hero's dry speed** (Player.max_speed is unchanged): wading, he runs
  exactly as fast as it flies, so he cannot outrun it in the water (it still slows to half on every hit). Named, not
  changed.
- **Nothing new on screen**: the ripples already show who wades.
- Cost: once a tick the crowd's grid is asked which creatures stand in each lake (indices_in_radius, a few cells a lake)
  and those are marked (`_wade_k`); the walk reads one number a creature. Measured (tools/_p80_OASIS_bench.gd, 250
  creatures, a tenth of them wading, three lakes): 33 us a tick on the PC, under 1% of the crowd's 4 ms.

### 27.LEAD The lead's changes in this pass

- **The run record names the water** (`map_settings.water_slow`, `map_settings.oases` with the game's defaults under
  the map's keys; analytics/SCHEMA.md).
- **The gold tracers re-cut** after the first wisp read like pale sticks at phone size (the lead asked lane TRAIL for
  thinner amber streaks; the numbers in 27.TRAIL are the final ones).

## 28. Pass 81 (v0.67): water, sand, wave pacing, bees, the rocket, the Saiga, the production build

Garry's request (2026-10-15, tools/dl/p81/REQUEST.md). Each lane's rules as it wrote them.

### 28.MAP Water, sand, the oasis ground, the structures' ring

Nothing here changes play: the water's reach (in_water 1.02 of a lake's radius, the disc 1.06, the 10% slow, the dish)
is pass 80's. Every number below is a look.

#### The water (core/shaders/water_lake.gdshader, one material for every lake, RedCanyon._water_material)
- Unshaded, half see-through, no depth write, render priority -10 (under the ground marks, as before); no screen or
  depth reads; 4 samples of one 256 px noise texture (art/env/noise_rgb.png: three smooth tileable noises, r g b).
- Only the disc's top cap is drawn (its UV gives the radius: rn = |UV - (0.25, 0.75)| x 4); the side band and bottom
  are discarded.
- Colour: deep (0.04, 0.34, 0.50) in the middle to shallow (0.20, 0.62, 0.66) towards the shore (depth = 1 -
  smoothstep(0.18, edge, rn)); the last 0.2 of the radius mixes 35% towards shore_color (0.58, 0.62, 0.48), the wet
  sand seen through thin water; a slow swell x(0.93 + 0.14 noise).
- The shore: the water ends at shore_at 0.95 of the disc's radius (about 1.0 of the lake's), moved +-0.05
  (shore_wobble) by a still noise (tiles every 22 m), never past 0.985 (inside the disc's 40 sides); alpha fades out
  over the last 0.05.
- The drawn shore (0.90-0.985 of the disc, about 0.95-1.04 of the lake's radius) sits a little inside the disc that
  everything else reads (water_disc 1.06: the hero's cut, the blob shadows hidden under water, the wading rings from
  in_water 1.02): unchanged rules, so a creature standing in the last few centimetres of clear shore has no shadow.
- Alpha: deep_alpha 0.9 in the middle, shallow_alpha 0.62 at the shore (before the fade).
- Ripples: two noise layers (0.085 and 0.12 tiles a metre) drifting at ripple_speed 0.022 against each other; where
  their sum crosses the middle a soft light web (ripple_sharp 2.2, ripple_light 0.08, less in the shallows).
- Lapping line: a band 0.04-0.085 of the radius inside the edge, broken by the noise, breathing (sin 1.4 rad/s),
  foam (0.93, 0.96, 0.92) at foam_strength 0.35.
- Glints: a fine layer (1.1 tiles a metre) drifting faster; a glint where it passes glint_from 0.955 and the slow layer
  is light, strength 0.7, none in the shallows.
- Sky: (0.78, 0.88, 0.94) at sky_strength 0.35 x the grazing term (1 - N.V)^2 x 2.2 (the far water lighter).
- Hell (stage 3): RedCanyon._apply_hell sets the water's `hell` with the ground's; the water goes 70% of the way to
  col x (1.05, 0.72, 0.66) + (0.06, 0, 0).

#### The oasis ground (RedCanyon.oasis_wet in the terrain's vertex alpha; terrain_painted.gdshader)
- oasis_wet(p) = 1 up to OASIS_WET_TO 0.6 m past the nearest lake's edge (and under the water), falling (smoothstep)
  to 0 at OASIS_REACH 3.5 m + OASIS_REACH_PER_R 0.45 x the lake's radius (6-7 m for 5.5-7.5 m lakes), that reach moved
  +-OASIS_WOBBLE 2.2 m by slow noise (ragged, never a ring); the wettest lake wins.
- Shader: the alpha broken further by noise (oasis_ragged 0.32 at 1 m, 0.19 at 50 m); damp earth from 0.1 (full at
  0.4): x oasis_damp (0.93, 0.90, 0.80); sparse green on the damp ground (not the wet): oasis_grass (0.40, 0.52, 0.27)
  at oasis_grass_amount 0.5 where the noise passes 0.48-0.66; wet sand from 0.72 (full at 0.88): 30% to grey
  (oasis_wet_grey) then x oasis_wet (0.80, 0.77, 0.72).
- Gone: pass 80's damp ring (a 0.35 mix of the cracked river bed in the red channel from 0.75 to 1.9 radii).
- Every terrain corner now has its own colour (was one colour a 1 m quad: a faint checker on the sand, steps round the
  lakes). The vertex colour is 8 bits a channel, so the shade's 1.15 tops out at 1.0 (as it always did).

#### The sand (tools/gen_textures.py sand(), art/env/sand.png)
- A Flux.2 Klein painting (seed 8102, prompt in gen_textures.py; source tools/art_src/sand_klein_s8102.png), made
  tileable (two half-offset cross-fades, ramp over 0.8 of the half width), its light and dark laid over the procedural
  sand's mean colour (214.8, 188.6, 145.5; hue 37.3, saturation 0.323, value 0.842: pass 61's) at SAND_CONTRAST 0.06
  of that colour per standard deviation. The procedural sand is the fallback when the painting is missing.
- The terrain shader adds a broad light and shade over the sand (not the rock): x(1 +- macro_strength 0.07), the noise
  tiling every 53 m (macro_scale 0.019), so the painting's 11 m repeat stops showing.
- sand.png, cracked.png, redrock.png and noise_rgb.png import with mipmaps (they had none: the far sand shimmered).

#### The structures' ring (StructureManager)
- The dark clock hand on the progress pie's leading edge is gone (Garry's "black line"); the pie (alpha 0.62) and the
  breathing ring are unchanged. `Structure.hand` stays as a field, always null.

### 28.PACE A roster row paced as waves; the yellow etches

Garry (2026-10-15): "Add the ability to control the pacing of the waves. I mean the frequency at which enemy waves come.
And on top of the enemy node in the rows you should etch the yellow etches to show when the enemies will spawn. If it's
continuous (choose an option) it's shown as a continuous yellow line."

#### The game (WaveTimeline.row_* helpers, WaveDirector._tick_row_waves / _row_wave_spawn / _row_waves_owed)
- **`pace`** on a roster row: `"continuous"` (the default; a row without the key, or with any other value, plays as
  before, unchanged) or `"waves"`.
- A continuous row is what every row always was: drawn into its channel's cap by its presence weight at every spawn
  check (`spawn_interval`, Red Canyon 0.7 s), a burst of `burst_min`..`burst_max` load units (Red Canyon 3..12) shared
  by the open rows. Those three are the global pacing; their help in Settings -> Spawning now says so.
- A waves row: wave k comes at `t` + `offset` + k x `every` while the row is open (`t` <= clock < `until`; no `until`
  = on through the stages and endless).
  - `every`: seconds, default **30**; 0 or less = **one wave only** (at `t` + `offset`).
  - `offset`: seconds, default 0; below 0 counts as 0.
  - `count`: creatures a wave, default the row's `pack`, else the creature's pack size after the row's overrides
    (`stats.pack`); at least 1.
  - In the row's `pattern` (packs of the row's pack; scatter / single / in_front each at its own point; ring the
    spawn at once round the hero), `variant`, `stats`, `channel`.
  - **Presence gates, never scales**: a wave whose second finds the row at weight 0 (its `weights` keyframes) does not
    come; the weight's size changes nothing about the wave (`count` does).
  - **The cap** (`respect_cap`, default **true**): a wave is cut to the free room of its channel (regular: the cap less
    the regular load; hell: hell_cap x cap less the hell load), at least one creature while there is any room (the
    `waves[]` rule, ceil(room / cap_share)). What does not fit is **owed**: at the start of every spawn check of the
    normal phase it spawns first (before the continuous draw) as room frees, until the row's next wave falls due (the
    rest is dropped; the new wave owes its own count) or the row closes. `respect_cap: false`: the whole wave at once on
    top of the cap, like a SWARM.
  - Always: the map's `hard_cap` of bodies and the creature's `max_alive` (the row's override too) cut a wave and its
    owed rest.
  - **`trickle`** (default **false**): a waves row is not in the continuous draw between its waves; with `trickle:
    true` it is also drawn continuously by its weight, like a continuous row.
  - Normal phase only: the run clock stands still in a boss fight and the portal wait, so no wave falls due then, and
    what a wave owes waits until the clock runs again.
  - A clock that jumped (a tool: smoke_run, hell_check, the arena) fires **one** wave, the latest due; the skipped ones
    never come (no backlog).
  - Numbers: the row's own fixed numbers (pass 58: its HP and ATK from its `t`, the hero's level at its first spawn;
    afresh at each endless wave), the same key as its trickle's.
  - Unchanged for a waves row, as for any row: it is still a candidate for a coloured elite (by `stats.elite_weight`),
    the portal wave still draws it by its weight among the open regular rows, an event of the same creature still joins
    its numbers when it is the heaviest open row, and its creatures count in the hell load like any hell row's.
- Red Canyon: every row stays continuous (the lane changed no row; Garry sets Pacing himself).

#### The Level Editor
- Pacing select on the row form (Continuous / Waves every N s); with Waves: Every (s), Per wave, Offset (s), Respect
  the cap, Also continuous. Choosing Waves writes `pace` and `every` 30 when the row has none; choosing Continuous
  removes `pace` and the five waves-only keys (undo brings them back). The note under Pacing says when its waves come.
- The **yellow etches** along the foot of each roster bar: a 3 px line where a continuous row (or a waves row with Also
  continuous, a thinner line) is drawn, its weight above 0; a 10 px tick at each wave that comes (weight above 0 then);
  a `waves[]` block gets a tick at each burst (t + k x every until ceil(count / burst) bursts or until). Ticks closer
  than **3 px** on the screen (ETCH_MIN_PX) are **thinned** (every m-th kept), never merged into a line, so only a
  continuous row shows a line; the hover card says when its ticks are thinned and names the next wave.
- The chip on a waves bar: "↻ 30 s ×20" (every, per wave), "once ×20" for every 0.
- The Share lane, the readout and the Presence table's share column leave a waves row out of the draw ("waves", or
  "held" where its weight is 0); a trickling one is drawn as before.
- "Spawned so far" and the Actual HP / ATK lanes play waves rows by the same rules (expected values), so the curves
  follow a row set to waves.
- Validation: an unknown `pace` (error; the game plays it continuous), `every` below 0, `offset` below 0, `count`
  below 1, a wave over the hard cap (errors); a wave faster than a second ("reads as continuous"), more than 40 at once
  off the cap, a first wave not before `until`, a presence of 0 at every wave, the waves-only keys on a continuous row
  (warnings).

### 28.POLISH The bees' dashes, the rocket at 85%, the Saiga Sniper holds its ground

#### The Vulture Raider's rocket at 85% of the hero (`rocketeer.json` `artillery.missile.speed_of_hero` 0.9 -> **0.85**)
- **Rule** (*code*, ProjectileManager._fly_rocket + `rocket_clock_pace`): a guided rocket with `speed_of_hero` > 0 flies
  on the ground at **speed_of_hero x the hero's top speed** (Player.max_speed = his `move_speed` stat x the map's
  `move_pace`, every bonus in it: a Sprint makes it faster too, a harpoon rope slower), x High Noon's time_scale.
  How: its speed is set to max_speed x speed_of_hero / the creatures' pace (EnemyManager.pace = move_pace x
  creature_speed_mult), and it flies on the creatures' shot clock (hostile_clock = time_scale x pace), so the pace
  cancels out. Red Canyon, a hero on the base move_speed 3.6: 3.6 x 0.9 = 3.24 m/s -> rocket **2.75 m/s** (measured in
  the game, tools/_p81_POLISH_rocket_probe.gd: 2.754 / 3.240 = 85.0%; before: 0.81 = 2.62 m/s).
- **What it was**: only move_pace came out (pass 60), so creature_speed_mult (0.9 on Red Canyon) stayed in: the 0.9 was
  really **0.81** of his speed (pass 80 had named it "90%"). Now the creature speed knob no longer touches the rocket;
  the map's move_pace still never does (it is in both).
- **Kept**: its turn (`turn` 1.3 rad/s, on the shot clock), the slow and shake on every hit on the Raider (`hit_slow`
  {mult 0.5, recover 3 s, shake 0.35 s}: half of the 85% just after a hit), the loose rocket when he dies (own speeds).
- **Wading**: the hero walks at 90% in water (pass 80) and the rocket keeps to 85% of his dry speed: wading he now
  outruns it by 5% of his speed (it was 81% before, so this holds as it did).

#### The Saiga Sniper (`content/enemies/saiga_sniper/saiga_sniper.json`): no running away, the Spit Cactus's walk
- `speed` 3.2 -> **1.6** m/s (the Spit Cactus 1.15: x1.39; both x the creature pace, 0.81 on Red Canyon: 1.30 m/s
  against the cactus's 0.93; the hero 3.24 m/s on the base move_speed).
- `flee_on_hit` block **removed** (was seconds 1.0, speed_mult 1.8, interrupts true: x1.8 = 4.67 m/s, faster than the
  hero's 3.24 m/s, which is why he could never be caught).
- `sniper.flee_range` 14 -> **0** (and the code's default is now 0: a sniper runs only when its data names a range).
- `sniper.follow` 38 -> **16** m: the walk (*code*, the kite brain's way): farther than `follow` he walks straight at the
  hero; within it he holds where he is and aims when his rest is over; he never backs off, however close the hero comes
  (the cactus backs off inside keep_distance - 0.5; the Saiga does not). Why 16: twice the cactus's spit range (8), out
  of the weapons' priority reach (`target_priority.reach` 10 m), so the guns go for him only once the hero walks in;
  well on screen when north of the hero (the screen shows ~33 m up, ~7.5 m down, ~6.6 m to each side at zoom 1);
  the hero closes 16 m in ~4.9 s at 3.24 m/s, a bit more than one aim + hold (3.7 s on Red Canyon), so rushing him means
  one dodge, maybe two.
- `sniper.stand_off` **26** unchanged: he still comes in 26 m off; walking in to 16 m takes ~7.7 s at 1.30 m/s before
  his first aim (his first aim waited 2.5 s before; it can only start once he is inside `follow`).
- `sniper.spoil_on_hit` **true** (new; *code* default true): a hit that lands (never a poison or fire tick) drops his
  aim or lock under way (no shot; the next aim waits `recover` 2.5 s). This was pass 73's rule through flee on hit's
  `interrupts`; it stays, without the run (Garry asked to remove the running only).
- The look SS-A's walk `fps.run` 15 -> **8** (*data*, the look): the walk cycle plays at a fixed rate x pace, cut for
  3.2 m/s; at half the speed his feet would slide at twice the ground; 15 x 1.6 / 3.2 = 7.5, rounded to 8.
- Everything else of the sniper unchanged (aim 2.0 s, lock 1.0 s, both x 1/pace = 2.47 / 1.23 s; interval 9 +- 1.5 s;
  the beam, its damage 0.7 x the rocket's, the lines). The telegraph check (pass81_polish_test): at his range the hold
  is > 4x the time the hero needs to step off the line at his top speed ((0.25 + 0.4) m / 3.24 m/s = 0.2 s vs 1.23 s).
- **Flee on hit stays in code** for any creature (EnemyDef.flee_on_hit, EnemyManager.flee_start); **no creature uses it
  any more**. The sniper brain's flee_range retreat stays in code too (0 = off).
- Effect on threat: the Saiga now shoots only once he is within 16 m; a hero who keeps moving away outpaces him (3.24 vs
  1.3 m/s) and draws fewer shots than from pass 73's 14-38 m sniper; Garry tunes `follow` ("Walks in past") and `speed`
  in the Level Editor.

#### The Killer Bees' trails (`params.missile.trail_style`, ProjectileManager.BEE_LOOKS) - look, not balance
- A seeker with `missile.trail` 2 (a bee) or 4 (a bee on Pollen's buff) draws its look in the tracers' ring; the default
  look **"dash"** (BEE_TRAIL_STYLE; the three bee items name it): dashes **0.24 m** on in every **0.42 m**, colour dark
  honey-brown (0.29, 0.17, 0.04, alpha 0.9), red (0.75, 0.08, 0.05) on Pollen, head width **0.075 m** (at least 3 px),
  life **0.45 s** (was 1.4 s of beads), a segment every **0.3 m** flown (0.6 m with more than 60 shots in the air).
  Others: buzz (0.095 m, 0.34 s, weave 0.11 m every 0.9 m), bumble (0.07 m, 0.42 s), zip (0.13 m, 0.16 s), beads (pass
  49's). `trail_color` recolours the look (never Pollen's red). Rocket smoke (trail 1) unchanged; the hidden Homing
  Skulls mutation (trail 2, no style) also wears the dash.
- Cost: no per-frame work per bee any more (pass 49's beads were re-written every frame in the 800-bead ring); a bee
  writes one ring slot (transform + colour) per 0.3 m; the shader draws the ring's used part as before.

### 28.PROD The production build

Nothing in play changes in the dev build. The production build (presets "Android Prod" / "Windows Desktop Prod",
custom feature `prod`, `Settings.is_prod()`) differs only in what it leaves out, named here.

#### What prod switches off (Settings.PROD_LOCKED, held at the player's default)
| Switch | Prod value | What goes with it |
|---|---|---|
| debug_mode | false | the player's debug mode (the ten taps on the hints switch do nothing), the title's ARENA, the debug hand on the pick screens, holding the clock, the free respawn and the last hits on Down!, the Settings debug panel, the one-modal watch |
| debug_panel | false | the in-run debug panel (and F1 no longer toggles it) |
| debug_modal_buttons | false | the "debug" button on the modals |
| free_revive_button | false | Down!'s free revive |
| hit_log | false | Down!'s hit log and copy |
| preview_locked_heroes | false | hidden heroes previewed on the title |
| menu_style | "live" | the title is the live one (the Painted choice lived in the debug panel) |
| ranged_on_screen | true | ranged weapons aim only on screen (the debug panel's comparison switch) |
| pierce_falloff | true | the pierce drop-off stays on (the debug panel's / developer menu's switch) |

Also in prod: the developer menu (holding the Settings version line 2 s) does not open (and goes straight back to
Settings if reached); `user://debug_launch.json` and `Run.launch_override` are ignored (the file is left where it is);
`Run.arena_next` never opens the arena. A save written by a dev build with any of these on reads back locked.

#### What prod leaves out of the build (tools/prod_reach.gd -> tools/prod_prune.py, staging copy only)
- Content folders out of play: hidden heroes (Dad, Mira) and their perks and hero mutations; hidden weapons (Branding
  Iron, Flare Gun, Poison Dart, Rattlesnake, Spear) with their paths and evolutions; hidden evolutions (the _v47 ones,
  Bullet Hose, Cluster Bomb...), hidden mutations, hidden perks (Bounty Hunter, Lingering Light, Long Day, Serenade,
  Suit Seals...), hidden creatures (the five training dummies, Goblin, Hobgoblin, Jackalope, Sand Crab), the Timeout
  pickup, the Strongbox (gold_bank); the quests for any of them (unlock_dad, unlock_mira).
- Kept although hidden, because something names it: the Sand Lizard (the Gila summons it), the Peashooter with its
  Pea Cannon (code fallbacks: Registry.start_weapon_for, the arena), the Timeout perk (Game.gd reads it), and any
  folder a kept file names by path (the Grave Hail evolution uses Dia de Muertos's visual, Jackrabbit Mines
  Minefield's): those stay whole.
- Looks: a hero and a card keep only the look the game plays (the JSON's `variant`), made the base; a creature keeps its
  base, the look it plays and every look a map row or event names (e.g. RG-B, SK-E, KN-E, RR-B, ANT-B, DM-B, HG-C).
  A weapon family keeps all its looks. The title cut-outs only dropped looks or dropped heroes name go.
- Files the game never reads: every `<id>_ai.json` (the painters' sidecars), sound files the sound map does not name
  (128 placeholder WAVs of sounds that have their real one).

#### What prod changes in the art and sound (staging copy only)
- Music: the six tracks as Ogg Vorbis quality 4 (about 110 kbps at their 32 kHz; the dev build's QOA WAV is about
  200 kbps); any other sound of 10 s or more that does not loop would go the same way (none today). Audio.gd loops Ogg.
- The project icon (icon.png, only the window's icon at run time) 1024 -> 256 px; the four prop billboards still
  lossless (boss_portal, st_teleport, st_teleport_off, st_totem_pole) lossy WebP 0.85 like the rest; icon.ico out of
  the APK.
- Unchanged on purpose: the sprites and icons (lossy WebP 0.75 already), the 3D textures (VRAM-compressed with
  mipmaps where they had them), sprite strip sizes (frames are shown near their painted size), the terrain textures
  (lane MAP's this pass).

#### Identity
- Android: package `com.eightyeightfits.game.prod`, label "88fits", version code from the game's version
  (major x 10000 + minor x 100 + patch: 0.67 -> 6700), same keystore; the dev app's label is now "88fits Dev" (package
  unchanged, so its save stays).
- PC: the prod exe's save in `%APPDATA%/88fits` (the dev build's `%APPDATA%/Godot/app_userdata/88fits`); the dev exe's
  product name "88fits Dev".
- Analytics: every event carries `build` = "prod" | "dev" beside `dev`.

### 28.LEAD The lead's notes in this pass

- **The PC save put back**: a lane's stray smoke run at 21:19 (outside the Godot wrapper) had banked one run into the
  PC's real save (gold 6960 -> 13384, runs 14 -> 15); the lead restored the save's own previous copy (the dirty one kept
  in tools/dl/p81/lead/save_dirty_2119.json).
- **Two builds from now on**: the dev build (tools/ship.sh) after every user-facing change; the prod build
  (tools/ship_prod.sh, skill ship-prod) only when Garry asks.

## 29. Pass 82 (v0.68): the HP bar shakes, bodies fly from every weapon, sands, the Spirit Pole, XP growth, pickups charts

Garry's request (2026-10-16, tools/dl/p82/REQUEST.md). Each lane's rules as it wrote them.

### 29.FEEL The HP bar shakes instead of the screen; every kill throws its body

#### The hurt shakes the HP bar, not the screen
Garry: "Don't shake the screen when hero is damaged. Shake the hp bar instead. But do that a little bit."
- A hit that reaches the hero's health (Player.hit) no longer shakes the camera (it was `camera.shake(0.9)` on every
  hit). A harpoon's hook no longer adds its own `camera.shake(1.0)` (the hook's hit shakes the bar like any other).
- Instead the hero's bars (HP, with the shield bar under it) jiggle sideways: `HP_SHAKE_PX` 4 px +
  `HP_SHAKE_PX_PER_HP` 40 px for every whole max HP the hit took (`dealt / max_hp`), at most `HP_SHAKE_MAX_PX` 10 px,
  `HP_SHAKE_SWINGS` 3 swings over `HP_SHAKE_TIME` 0.25 s, dying away as (1 - u)^2, so the bars end exactly where they
  were. Canvas pixels (the 1080-wide canvas): a 10% hit is 8 px, 15% and over 10 px. A hit while one runs starts it
  again at the larger of the new size and what is left of the old one. (`ui/HUD.gd`, `Game._feel_hurt_bar_shake`.)
- Unchanged: a hit on the Energy Shield or the shield power-up, an evade, an immune hit: no jiggle (they never shook
  the camera either). Every other shake is as it was: blasts (a rocket or a boulder that catches the hero still shakes
  2.6 / 2.4 against 1.3 / 1.6 when it misses: the blast's, not the hurt's), slams, the Gila's rumble, a boss or an Elite
  down, an evolution, the spawn's landing, structures.

#### Every kill throws its body
Garry: "The explosion thing that affects the enemy's corpses with knockback should come from all weapons. I think
currently it's just the dynamite."
- Every kill by a hit (EnemyManager.damage: any weapon, its burn and poison ticks, a blast, Overkill's splash, the
  revive's blast, a hostile blast on its own crowd) now follows through like a blast's (`_corpse_follow`):
  - the body is driven along the killing hit (the hit's own direction: the shot's travel, the blade's swing, out of
    the blast, along the laser; a hit with none, e.g. a burn or poison tick, the Zap Beam, the salt, the Guitarra's
    wave, away from the hero) at no less than the floor push, and thrown up the floor toss;
  - the hit's weight w = (the hit's damage / the creature's max HP) / `CORPSE_HEAVY_RATIO` 4, + `CORPSE_CRIT_WEIGHT`
    0.35 for a crit (half for a mini crit), clamped 0..1;
  - floor push = lerp(`CORPSE_FLOOR_PUSH` 4 m/s, `CORPSE_HEAVY_PUSH` 5.5 m/s, w) x heft, heft = clamp(`CORPSE_HEFT_SIZE`
    1.5 / the body's size, `CORPSE_HEFT_MIN` 0.5, 1) (a goblin 1, a skeleton 0.86, the Hammer Giant 0.5); the push it
    already had along the hit is kept when bigger, its push across the hit kept;
  - toss height = lerp(`CORPSE_FLOOR_TOSS` 0.4 m, `CORPSE_HEAVY_TOSS` 0.8 m, w) + `CORPSE_HIT_TOSS_PER` 0.1 m per m/s of
    the push it had along the hit, at most `CORPSE_HIT_TOSS_MAX` 1.6 m; a blast's own throw (pass 79:
    `CORPSE_TOSS_PER` 0.3 m per m/s, `CORPSE_TOSS_MIN` 0.3, `CORPSE_TOSS_MAX` 2.5) wins when it is higher.
  - What that looks like (gravity `CORPSE_G` 22, air drag 1.5, ground decay 6, as pass 79): a chip of a kill throws a
    goblin 0.4 m up and ~1.5 m back; a one-shot many times over (w 1) 0.8 m up and ~2.4 m back; the dynamite as before
    (1.4-2.1 m up, 2.3-3.4 m out in the capture).
- Never: the boss (his death as before: no slide, no throw); big game (an Elite, an elite-modded creature: slides on
  the push it had, never thrown, as before); a body in a launch (Alley-Oop, Bucking Bronco: as before); a body still
  coming up out of the sand below `rise_targetable` (0.7: sinks where it is); a kill with no hit behind it (kill_all,
  a walking bomb's own blow-up). A body killed nearly up (rise_t >= rise_targetable) is shown whole and thrown.
- Nothing changes for the living. Bodies stay inside the arena, on or above the ground, off the rocks (pass 79's
  rules), and land in a little sand.
- Cost (A/B in the same run, 180 creatures, a kill every frame = 60 kills a second, PC): enemies.sim +0.19 ms/frame,
  fx +0.08 ms/frame; perf_late build=six shows no change beyond its noise.

### 29.SAND Five sands to choose from

Nothing here changes play: every number below is a look.

#### The five sands (RedCanyon.SANDS; the map file's `sand`)
- The map file's `timeline_data.sand` (WaveTimeline.sand) picks the painting the open ground is drawn with, as the
  terrain builds: `pass81` (art/env/sand.png, pass 81's, unchanged), `dunes`, `dunes_pebbles`, `ripples`,
  `ripples_pebbles` (art/env/sand_<id>.png). "" (no key), an id not in SANDS, or a painting that is missing plays
  SAND_DEFAULT = `pass81`. **The default stays pass 81's until Garry picks** (red_canyon.json has no `sand` key).
- Each sand's size on the ground: `scale` x the terrain's tiles_per_metre 0.09 (the shader's `sand_scale`; below 1 =
  bigger): pass81 1.0 (11.1 m a tile), dunes **0.8** (13.9 m a tile: its bands a little broader, like the reference's),
  dunes_pebbles 1.0, ripples 1.0, ripples_pebbles 1.0. Only the sand: the river bed (uv x 0.8) and the rock (uv x 0.7)
  keep their own tiling.
- Every new sand is laid over pass 81's exact mean colour (214.5, 188.3, 145.5) (within a level of 255; the pins of
  passes 54 and 61 hold: value > 0.835, saturation < 0.36, hue 33-40 degrees), so the river bed, the oases' ground and
  the walls still match; only its light and dark (and a pebble's own grey) come from the painting.
- The arena's WORLD tab switches the sand on the spot for the visit (RedCanyon.set_sand); a run plays the map file's.

#### How the four were made (tools/gen_sand.py)
- Flux.2 Klein paintings (1024 px, 4 steps), the reference (a watermarked stock photo) described in words only, never
  sent to the server or traced: PROMPTS "dunes" (soft broad wind-shaped wavy bands, a fine even grain, warm golden
  tan), "pebbles" (the same with a few small grey-brown pebbles far apart), "drift" (softer, irregular wind ripples),
  "drift_pebbles". Four seeds each (8201-8204); picked by eye in the game at phone size: dunes = dunes s8201,
  dunes_pebbles = pebbles s8201, ripples = drift s8203, ripples_pebbles = drift_pebbles s8202.
- Tileable by three repaints that never touch the tile's edges (seam_inpaint): the painting rolled half a tile, the
  cross where its old edges meet repainted by the model under a grey differential-diffusion mask (fully on the seam,
  less and less out to 256 px), the arms stopping 40-200 px short of the edges; then the two seams' ends repainted
  after rolling half a tile down and across. Each repaint is brought to the painting's cast (the mean difference over
  the barely-touched ring, then a 48 px smooth map of the rest) before it is blended in by the mask itself. Seeds:
  painting seed + 500, + 501, + 502.
- palette_from: the luminance split into the broad shading (blurred 6 px), normalised to **band 0.055** of the colour
  per SD (the reference's broad shading is about 5% of its brightness), and the fine rest kept as its ratio to the
  shading x **fine 0.7** (grain and pebbles keep 70% of their painted contrast); **chroma 0.5** of the painting's local
  colour (against its own 6 px blur) on the two pebble sands (a pebble stays a little grey; a broad cast never shows),
  0 on the plain two; then moved to the mean exactly.
- Sources kept in the repo: tools/art_src/sand_<id>_src.png (the tileable paintings before the palette).

#### Cost
One sand texture is loaded at a time, the same 1024 px, the same import as pass 81's (lossy WebP 0.85, mipmaps): no
change in memory or draw cost; the shader's only addition is one multiply (uv x sand_scale). The four new files add
about 0.6 MB of imported textures to a build (the dev and the prod build both ship all five: the switch is a map
setting).

### 29.WATCH The bot hunts specials; the game's Pause in the Watch; totals and marks

Everything here is the TOOLS' (game/tools/bot/, game/tools/watch/; never exported): the run sim's and the Watch's
player and the Watch's window. No game rule changed.

#### The bot hunts the specials (Bot.gd, BotGoals.gd; Garry: "Bot should try to find the Special Enemies when they appear")
- Option **`specials`** (bool): on in the Explorer, Careless and Expert presets, off in `sim77` (pass 77's bot stays
  itself). The planner runs whenever it is on (as for explore, totems, barrels, structures).
- **What the sims taught** (10-run batches, see Measured): specials chase the hero and the weapons take them first within
  10 m, so the bot that never hunts already kills 98.4% of the ~160 specials of a 25-minute run. Hunting every one
  (walking at it, or leaning the kite at it) killed no larger share and cost levels and half again to twice the falls
  (most in stages 2-3 and at the bosses); keeping the hunt as his goal while the weapons fought it still cost falls
  (blocking a heal or a chest). So the rule: **go and find the special that does not come, until it is in reach**.
- **Known**: a variance special (the glowing one, EnemyManager.vspecial) within **SPECIAL_SEE = 30 m** of him (specials
  spawn 19-24 m off at the screen's edge, so in practice the moment one comes); the one he hunts stays known up to
  **SPECIAL_KEEP = 45 m**. The Saiga Sniper's kind of "special" (a gear badge) is not one of them.
- **A goal** once he has known it **SPECIAL_WAIT = 5 s** and it is still **out of reach**: farther than **IN_REACH = 9 m**
  or off the screen (EnemyManager.onscreen). One in reach is the weapons' (they take it first).
- **When not**: while a boss lives (the boss is the fight); a new hunt needs **SPECIAL_HP = 50%** of his health, the one
  under way goes on down to **SPECIAL_HP_HELD = 40%** (a gap, so a health hovering at one line does not flip the goal
  every half second); the far limit by health and danger (12..75 m) cuts the reach as for every goal.
- **Its worth**: **V_SPECIAL = 60** points (a Totem Pole 80, a chest 70, the gems at most 45), no taste and no mood (always
  wanted), the thing's jitter (0.85..1.15) and the style's word: damage x1.2, greedy x1.3 (the chest), safety x0.7;
  divided by (1 + distance / 18 m) as every goal. **No commitment**: anything better (a heal, a chest) takes over at once
  (as the gems' sweep; other goals keep theirs unless one 1.4 times better turns up).
- **The hunt**: the kite leans towards the special (the gems' sweep rules with the special as the lure: the lean whole
  while the way is clear, 0.3 of it while a creature stands in the way, none with a big one or a rocket close, less the
  more he is hurt, none under 35%) until it is within **HUNT_NEAR = 6 m** and on the screen: **found**, the hunt ends and
  he plays on while the weapons take it; that special can be a hunt again only after SPECIAL_WAIT s more out of reach. The hold still wins (5 or more within 3 m, a big one's push, hurt with one inside
  the flee distance); a special is never "grabbed".
- **Patience**: 8 s + 0.55 s a metre + **SPECIAL_FIGHT_S = 20 s** of slack (the lean is slower than a walk; half while the
  kite holds); a hunt ends after **SPECIAL_MAX_S = 60 s** of play whatever; given up = the special rests 40 s.
- **The log**: the goal "a special: Red Goblin, a 35% chest, out of reach 6 s (14 m)" (its chest chance as the creature
  and the map's special_defaults say); its end "found the special Red Goblin after 4 s: in reach, the weapons take it
  first" or "the special Red Goblin is down after 7 s of the hunt, a chest dropped" (kind `special`); a give-up "gave up
  on a special: ... after N s".

#### The game's own Pause in the Watch (Watch.gd, WatchClock.gd; Garry: "Allow me access to Pause button in the game")
- The mouse on the phone view is a finger: a left press, the drag while held and the release become ScreenTouch /
  ScreenDrag of finger 0 (what the phone sends; no mouse events reach the game, so nothing that reads both fires twice),
  pushed into the game's SubViewport at the view's position x its pixels; the SubViewport's stretch puts it on the
  1080-wide canvas. The window's own touches emulated from the mouse are swallowed. Other buttons do nothing.
- Clicks never steer: the hero's PlayerInput is switched off for touches and keys in the Watch (`enabled` false; no stick
  from a click in the thumb zone, no WASD). The bot's writes drive him.
- The game's pause screen up (paused from the HUD's disc or its top strip) = "paused (in game)": the bot is not ticked
  (it answers only the run's own screens: cards, chests, totems, the Stranger, the shop, the portal, Down!, the gate), no
  stuck count, and the Watch runs the frames as at 1x (60 a wall second, every one drawn, time scale 1, the sound as
  set) so the screen and its Options work as on the phone; RESUME there goes on at the Watch's speed. The Watch's own
  pause still holds over it. The header's status says "paused (in game): Resume there goes on at 4x"; the speed badge
  over the phone view hides meanwhile (the screen says PAUSED and its RESUME sits where the badge would).

#### The totals and the marks (WatchData.gd, WatchPanel.gd, WatchChart.gd)
- The meaning is lane STATS' (sim_run.gd `pickup_kind`, the same as the Sim's chart and the dashboard): **chests** = every
  `chest` event (a chest opened: taken or skipped, a boss's too), **power-ups** = every `pickup` whose `small` is not
  set (Game.apply_pickup's own count), **totems** = every `totem` event (a Totem Pole's gift taken).
- Live tiles: **Chests**, **Power-ups**, **Totems** (the totals so far, each value in its mark's colour); **Specials** "killed / came" (the recorder's `special`
  and `special_kill`) with the chests their deaths dropped.
- The Level and XP chart: a mark at each pickup's play second along the plot's foot, one lane a kind: chests a gold
  square (top lane), power-ups a green circle, totems a pink triangle (bottom lane); the legend leads with "Chests N,
  Power-ups N, Totems N". In the last-3-minutes view and the whole run (G) both.

#### Measured (the specials hunt)
Drifter, a quarter board, 25:00, death=keep (every fall counted, every run to the end), the Explorer preset with
`specials=0` (off) or `1`; all on one private snapshot of game/ (tools/dl/p82/WATCH/simsnap), only the bot's files
changed between batches. Folders: tools/dl/p82/WATCH/sim/<name>/ (players/pNN.json; meta.bot.specials), the table
from tools/dl/p82/WATCH/sim_table.py.

| bot | runs | specials came / killed (share) | special chests | hunts (ended down) | a special stood, s | falls mean / median | first fall median | level 10 / 25 min | kills |
|---|---|---|---|---|---|---|---|---|---|
| off (A, seeds 1-10) | 10 | 175 / 172 (98.3%) | 60 | 0 (0) | - | 8.9 / 4.0 | 9:11 | 28.6 / 72.3 | 20.0k |
| off (A3, seeds 1-10, final code) | 10 | 146 / 143 (98.4%) | 50 | 0 (0) | 32 | 11.3 / 4.0 | 12:18 | 29.3 / 68.7 | 18.4k |
| off (A5, seeds 11-20) | 10 | 168 / 165 (98.4%) | 62 | 0 (0) | 26 | 7.6 / 3.0 | 8:04 | 29.7 / 72.1 | 19.9k |
| first cut: straight at every one (B) | 10 | 163 / 160 (98.3%) | 56 | 138 (99) | - | 13.3 / 6.5 | 9:28 | 26.8 / 66.3 | 16.6k |
| second cut: leaning at every one (B3) | 10 | 145 / 142 (98.0%) | 49 | 109 (64) | 39 | 18.3 / 8.5 | 8:17 | 27.4 / 64.1 | 15.6k |
| third cut: the ones that do not come, held in reach (B4, seeds 1-10) | 10 | 143 / 140 (98.4%) | 51 | 71 (39) | 31 | 18.6 / 14.0 | 8:08 | 26.7 / 68.7 | 16.3k |
| third cut (B5, seeds 11-20) | 10 | 154 / 152 (98.4%) | 54 | 86 (53) | 28 | 10.5 / 6.0 | 9:03 | 28.1 / 71.1 | 18.0k |
| final: the ones that do not come, until found (B6, seeds 1-10) | 10 | 144 / 142 (98.4%) | 47 | 141 (26) | 29 | 8.4 / 5.0 | 9:57 | 29.9 / 65.8 | 16.8k |
| final (B7, seeds 11-20) | 10 | 167 / 164 (98.4%) | 59 | 153 (28) | 25 | 12.6 / 6.0 | 9:01 | 28.9 / 70.8 | 18.5k |
| final + the re-hunt wait (B8, seeds 1-10) | 10 | 186 / 184 (98.5%) | 65 | 128 (33) | 28 | 9.5 / 4.5 | 11:06 | 30.3 / 70.9 | 19.7k |
| off, all 30 | 30 | 163 / 160 (98.4%) | 57 | 0 (0) | 29 | 9.3 / 4.0 | 9:19 | 29.2 / 71.0 | 19.4k |
| third cut, all 20 | 20 | 149 / 146 (98.4%) | 53 | 78 (46) | 29 | 14.6 / 8.0 | 8:31 | 27.4 / 69.9 | 17.1k |
| final, all 20 | 20 | 155 / 153 (98.4%) | 53 | 147 (27) | 27 | 10.5 / 6.0 | 9:09 | 29.4 / 68.3 | 17.6k |

- "hunts (ended down)": hunts started a run (the specials that fell before he reached them). Final (B8): 128 hunts a run,
  42 found (brought into reach), 33 fell first, none given up, the rest overtaken by a better goal (no commitment).
- "a special stood": the mean play seconds from a special's coming to its fall (Bot.special_tallies life_s).
- **The finding**: the bot that never hunts already kills 98.4% of the specials (they chase him, the weapons take them
  first within 10 m), so no rule raised that share; hunting every special cost levels and falls (B, B3), and keeping
  the hunt as the goal in reach still cost falls (B4/B5). The final rule (go for the one that does not come, until it is
  in reach; B8) plays at the baseline: falls 9.5 (median 4.5) against 9.3 (4), level 70.9 against 71.0 at 25:00.
- **Noise**: A and A3 are the same behaviour on the same seeds yet differ by 3.6 levels and 2.4 falls: BotGoals' per-thing
  jitter is keyed by object instance ids ("st:<id>", "chest:<id>"), so any code change in the run reshuffles later goal
  choices (pass 80's design, lane BOT). A 10-run batch is good to about +-4 levels and +-3 falls; compare by 20-30 runs.

### 29.TOTEM The Spirit Pole gift screen

No gift number changed: weights, ranges, steps, the 3 s charge (`interact_time`), the choices (3), the 1 s safety after
the pick and the analytics events are pass 76's. What the screen and the pole now do:

| Rule | Number | Where |
|---|---|---|
| The roll gauge: which third of **that gift's own range** the roll landed in (pass 73's `quality`: by size, the smaller end to the bigger), 1, 2 or 3 of 3 notches filled | thirds | TotemBoons.roll_third / quality |
| The number turns brass dark (#A8792A) on a top-third roll only; no rarity colour, stars, seals or feathers | third 3 | ui/TotemScreen.gd `_fill_tag` |
| Both range ends are written, the **smaller size first** whatever the sign (the Thunderbird's cooldown: "−2% ■■□ −4%") | | TotemBoons.range_texts |
| The label counts the gifts: "★ TOTEM n OF t ★", n = gifts taken this run + 1, t = Totem Poles standing on the map; t unknown (0): "★ nTH TOTEM ★"; n past t raises t to n | | Game._use_totem, TotemBoons.pole_label, StructureManager.count_of |
| One tap target per gift: its segment (and where it sits held) and its tag with the nail and the shadow; the gap beside the nail and everything else take nothing; a finger dragged off a gift cancels it (90 ms back); release on the gift takes it | | TotemScreen.GiftRow |
| A gift takes a finger only once its row has landed in the open motion (a tap on a piece still moving is not a choice) | 0.30-0.44 s after opening | TotemScreen `_open_motion` (`arrived`) |
| The run goes on 300 ms after the pick (pass 73: 160 ms); the screen is gone at 420 ms; the hero's 1 s safety as before | 0.30 / 0.42 s | TotemScreen T_CONTROL / T_CLOSE |
| A run sim (Run.sim_mode) plays no motion: the pick hands the gift back at once | | TotemScreen `_instant` |
| The toast "{Word} · {amount} {stat}" ("Le-loo · +2% move speed") with the spirit's face (72 px), in paper (it was the pole's turquoise, which the toast kit turned green, the health colour), 1.2 s as every toast | | Game._use_totem, WToasts icon toasts |
| The in-world pole keeps its paint and its ring while its screen is up; its ring flashes 0.12 s as the screen opens; once the gift is taken it drains to grey over 0.4 s and its ring fades, ending in pass 73's grey painting | `spent_motion {flash 0.12, fade 0.4}` | content/structures/totem_pole, StructureManager.flash_ring / spend_slowly |
| A structure with `spent_motion` skips use_structure's generic 0.5 s flash ring (it froze under the paused screen and played out after the pick) | | Game.use_structure |
| First-play hint: "Totem gifts last the whole run", once per save, 1.6 s on the run's clock after the first gift is taken (the rule the old screen's subline said) | 1.6 s | ui/Hints.gd totem_taken (Save hint id "totem") |
| A spirit with no painted face shows its word in Alfa Slab 40 on the empty plate; a word wider than the plate's border less 4 px a side (280 px) shrinks to fit (none does today: Thunderbird is 273 px) | 40 px, 280 px | TotemScreen WORD_PX / WORD_CLEAR |

### 29.XP XP growth types

Garry (2026-10-15): "EXP requirements - I feel like we don't have enough settings for EXP requirements. Say I want to make
the EXP requirements exponential instead of linear, it doesn't look like I can. I want that section to include types of
EXP growth displayed in a dropdown, each one with it's own 2 charts for cumulative and per level EXP requirements."

#### The rule

The XP the hero needs to go from level L to L + 1 is **curve(L) × the map's `xp_need_mult`** (Run.xp_to_next). The curve
is the map's `timeline_data.xp_curve` = `{"type": <type>, <type>: {its numbers}}` (game/core/data/XpCurve.gd). **Absent,
`{}` or an unknown type = today's quadratic 15 + 6L + 0.5L², to the bit** (the same float maths as every pass before).
Red Canyon names no curve (Garry's 1.65 stands): nothing changes until he picks a type in the Level Editor.

| type | curve(L), before xp_need_mult | defaults | by level 30 vs today's 7,322.5 |
|---|---|---|---|
| `quadratic` (today's) | base + linear × L + quad × L² | 15, 6, 0.5 | 100% |
| `linear` | base + step × (L − 1) (base = what level 1 needs) | 21.5, 16.5 | 100% |
| `exponential` | base × growth^(L − 1), never above `cap` (0 = no cap) | 40, 1.11, 0 | 97.5% |
| `power` | base × L^power | 6.5, 1.33 | 101% |
| `table` | `points` [[level, XP], ...]: straight between listed levels; levels before the first need the first's XP; past the last listed level each needs the last XP × (1 + `after_growth`)^(levels past it) (0 = it repeats) | today's curve at 1, 5, 10, 20, 30, 40, 50, 60 (21.5, 57.5, 125, 335, 645, 1055, 1565, 2175), +2.5% after | 102.5% |

- Each type keeps its own numbers in its own block (switching type in the editor keeps the others; only `type`'s is
  played). A number the block leaves out, or holds as a non-number, is the default above.
- The defaults were fitted so the total XP to level 30 is within 5% of today's: switching type does not wreck the first
  20 minutes. They differ elsewhere (before the multiplier; totals to the level, today's in brackets):
  - linear: 788 by 10 (548), 29,500 by 60 (46,610): dearer early, cheaper late.
  - exponential: 567 by 10, 20,931 by 40 (15,535), 171,318 by 60: a wall late; level 60 alone needs 18,900 (2,175).
  - power: 528 by 10, 38,033 by 60: close to today's to 40, cheaper late.
  - table: within 3% of today's to 60 (straight lines between today's own values).
- **Guards** (every type): a level needs at least 0.01 and at most 1e12 XP before the multiplier (XpCurve.MIN_NEED,
  MAX_NEED); NaN / infinity = 1e12 (the hero stops levelling there). The new types read a level below 1 as 1.
- **The arena** (levels by the button) and a run without a map keep today's curve × 1, whatever the map says.
- What the curve does not change: the level-up flow, the mutation level-ups (pass 79: a due mutation offer is the next
  level-up), the card levels (Run.card_level), the HUD, Field Notes (`xp_gain` scales the XP gained, not the need).
- The run record's `map_settings.xp_curve` names the type played and its numbers with the defaults filled in
  (RunAnalytics.map_settings).

#### The Level Editor's checks (tools/level_editor/xp_model.js `issues`, listed in the inspector and on the card)

Errors (block Save): `xp_curve` not a block; an unknown type; the type's numbers not a block; a number that is not a
number; a level 1-300 whose curve is 0 or less (the game would make it 0.01: levelling on nothing); a table with no
readable [level, XP] point; a negative exponential cap.
Warnings: a level under 150 whose need passes 1e12 (the hero stops levelling there); an exponential growth under 1; a
level that needs less than the one before (the first one named); a table point that is not [level, XP] (skipped); two
points on one level (the last counts); a block for something that is not a type, a key the type does not know.

#### The "when does a run get there" line (an estimate, not a rule)

Under the charts: the latest finished sim of the map (or the result the Sim tab shows): its mean `xp_total` a second,
fed to the chosen curve × the current xp_need_mult: the first second the XP reaches levels 10, 20 and 30, and the same
for today's curve. It assumes the same XP a second; a different curve changes the cards and so the kills.

### 29.STATS Chests, power-ups and totems through a run

No game number changed. The rules below are what the analytics count (they decide what Garry reads on the charts).

- **Chests picked up** = every recorder `chest` event: one per chest opened, taken or skipped (a skip spends the stage's
  skip and the game itself counts the chest as opened, `Run.chests_opened`), boss chests too. A banish re-rolls the same
  chest and adds no second count.
- **Power-ups** = every `pickup` event whose `small` is not set (true, or a number other than 0). This is the game's own
  definition (Game.apply_pickup: "the small things underfoot are not power-ups"; the `pickups` save total and the bot's
  `powerups` tally use it). Today: Heart, Magnet Pulse, Nuke, Berserk (`rage`), Shield, Sprint, Timeout (Fadeaway's
  perk). Not: Cake Slice, Coin Bag, Desert Poppy / Lupine / Marigold (`params.small: true`). A new pickup follows its
  JSON's `params.small`: no list to keep up.
- **Totems** = every `totem` event: a Totem Pole's gift taken (not the pole's `structure` use, not the `totem_offer`).
- **When it counts**: an event counts from the first row (a second of play) whose `t` reaches it: `event.t <= row.t +
  0.001`, the same as the deaths. A pickup in the run's last partial second, after its last row, is in the totals
  (`pickupTotals`, the dashboard's tiles and list) but not on the per-second line.
- **The Sim's average**: the mean over the runs still playing at that second (like kills and coins, not like deaths,
  which count every run); a run's own count at its end gives `players[].chests|powerups|totems` and the summary's
  `chests_mean|powerups_mean|totems_mean` (the tile "Chests · power-ups · totems a run").
- **Colours** (the Sim chart, the dashboard card and marks): chests amber `#c98500`, power-ups blue `#3987e5`, totems
  magenta `#d55181` (the palette's slots 4, 1, 5; checked as a set on the dark surface: every pair apart for colour-blind
  eyes, worst dE 13). Marks: a square a chest, a dot a power-up, a diamond a totem.
- **Made-up sims** (`sim_batch.py --synthetic`, a page test only) roll chests, power-ups and totems on dice of their own
  (seed x 104729 + 82), so the made-up numbers the older checks pin stay as they were.

### 29.LEAD The lead's changes in this pass

- **Blasts shake the same whether they catch the hero** (Garry: "Don't shake the screen when hero is damaged"): the
  Vulture Raider's rocket 1.3 and the boulder 1.6 always (they were 2.6 / 2.4 when they caught him); his hurt jiggles
  the HP bar (29.FEEL). Their hot flash on the screen when caught stays.
- **The design handoff** `design_handoff_88fits_totem/` sits at the repo root beside `design_handoff_88fits_wanted/`
  (the zip in tools/dl/p82/).

## 30. Pass 83 (v0.69): totem segments, heroes' prices, Thorns, shadows, boss HP by seconds, power, who spawns

Garry's request (2026-10-16, tools/dl/p83/REQUEST.md). Each lane's rules as it wrote them.

### 30.TOTEM Carved segments for every gift, a clean crest

No gift, weight, range or step changed (content/structures/totem_pole `params.boons` as Garry left it).

- **The Spirit Pole's art** (ui/TotemScreen.gd): every spirit's segment is an opaque 256 px carved square
  (game/art/ui/totem/spirit_<id>.png, 11 of 11 painted) drawn over its whole plate inside the 6 px ink border (288 px,
  was a 240 px face on the rock plate); the carved inset (8 px, black at 18 %) and the border are drawn again over it.
  A spirit added without a picture still shows its word on the empty rock plate.
- **The column**: a cedar post (200 px wide, game/art/ui/totem/cedar.png at 72 % light) shows between the segments,
  from the crest down into the base; the base is a cedar plinth (same size as before). The crest is centred on the
  column, at most 150 px tall, its foot 12 px behind the top segment (was a fixed 420 x 126 at (0, 372)).
- **A gift takes a finger** once its open motion has landed: by the motion itself or, if a slow frame held the motion
  back, by the clock (the moment its tag should have landed, about 0.3-0.44 s after the open). A tap before that is
  still no choice.

### 30.META Heroes' requirements and prices, the Collection, Thorns

#### 30.META.1 Heroes: requirements and prices (replaces §16.UI "The numbers")

Garry: "Most of the locked [heroes] have requirements - 2 are only unlocked for money".

Rule: the Drifter is the only free hero. Every other hero on the title is `availability: "purchase"`. Exactly **two**
are sold for gold alone (no unlock quest): **Ironwood and Astro**, the two heroes right after the Drifter in the title
order. Every other one is **locked** until his quest `unlock_<hero>` is done, then **on sale** for his price. Nobody is
"free after a quest" any more (Ironwood was, passes 73-82).

Why those two: the first runs' purse buys them (a first run that dies in stage 1 banks about 300-1,000; one that sees
the King about 3,700), so a new player learns the drawer's BUY and that gold buys heroes before any quest gates the rest.
The later heroes each ask for a step of the run first, and then cost about a quarter to a third of the run that unlocks
them, so they compete with the Upgrade board's ranks (500-4,500) without stalling it.

| hero (title order) | availability | requirement (quest) | kind | price (gold) | was |
|---|---|---|---|---|---|
| Drifter (1) | available | none | - | 0 | 0 |
| Ironwood (2) | purchase | **none (gold only)** | - | **300** | free after 2,500 kills (price 1,000 never charged) |
| Astro (3) | purchase | none (gold only) | - | 300 | 300 |
| Calavera (4) | purchase | kill the stage 1 boss on Red Canyon (the Tumbleweed King, 7:10) | kill_boss | 300 | 300 |
| Solenne (5) | purchase | extract after stage 2 on Red Canyon (the second portal, 14:20+) | extract_after_stage | 1,500 | 1,500 |
| Fadeaway (6) | purchase | **kill 3 Saiga Snipers, all time** (the special from 3:35, the beam he must dodge) | kills_of_enemy | **1,750** | none, 1,000 |
| Jeżyk / buck (7) | purchase | survive 15 minutes in one run (into stage 3) | survive_minutes | **2,000** | 1,250 |
| May (8) | purchase | reach level 30 in one run (late stage 2) | reach_level | **2,500** | 1,750 |
| Mira (9) | hidden | kill 99,999,999 creatures (unchanged, out of play) | kills_total | 9,999 | 9,999 |
| Dad | hidden | (unlock_dad kept, not shown or tracked) | - | - | - |

The early three keep Garry's 300 (he lowered Astro and Calavera to 300 himself on 2026-10-13). Six heroes on sale cost
8,650 in all (was 7,100). Prices never decrease along the title order (pass83_meta_test pins it).

What a run banks (sim, Drifter, no board, explorer bot, means of the players still playing: p77/p82 sims): about 1,000
by 7:10, 3,700-4,100 by 10:00 (the King's purse in), 6,700 by 14:20, 21,000 by 21:30. Saiga Snipers killed a run: about
0.7 by 7:10 and 1.3 by 10:00, so Fadeaway's three take two to four runs that pass stage 1's middle.

**Saves.** A save that had done `unlock_ironwood` (Ironwood was free then) owns him: `Save.FREED_BY_QUEST`
{"ironwood": "unlock_ironwood"}, checked at every load (idempotent: he is added to `heroes_owned`, nothing spent). A save
that bought Fadeaway keeps him (bought heroes stay bought); one that had not finds him locked behind the three Snipers
(kills counted before pass 83 count: kills_of_enemy is a lifetime total).

#### 30.META.2 Items: unlock requirements (reviewed, unchanged)

Items are never bought with gold (only heroes and the Upgrade board are; the in-run Shop's prices are §StructureShop),
so "prices for items" applies to heroes only. Every weapon/card/passive quest was checked against the timeline (a
creature's first arrival) and the sims' per-run kills; none needs an item locked behind itself (the only weapon-kill
quest is hidden Dad's), none is out of reach, and a hero's favourite or start weapon is offered to him whatever its
quest (CardPool.offer_weapons/offer_passives, Registry.start_weapon_for), so no hero is short of his own. No change.

| item | kind | requirement |
|---|---|---|
| Adrenaline (`adrenaline`) | passive | 400 kills, all time (the first run) |
| Big Mouth (`big_mouth`) | weapon | 300 Armadillos, all time (stage 2 from 8:56; ~350 a run by 10:00) |
| The Eye (`deadeye`) | card | evolve any weapon once |
| The Guardian (`energy_shield`) | card | survive 10 minutes in one run |
| The Ghost (`evade`) | card | reach stage 3 (Fadeaway's favourite: his whatever) |
| The Sage (`field_notes`) | card | play 3 runs |
| Guillotine (`guillotine`) | passive | kill the stage 2 boss (Gila Grande) |
| Hammer (`hammer`) | weapon | kill the stage 1 boss (the King; the same moment as Calavera's quest) |
| The Tower (`haste`) | card | 30 Bull Beetles, all time (from 5:06) |
| Killer Bees (`hornet_nest`) | weapon | 40 Armadillos, all time |
| Land Mine (`land_mine`) | weapon | 120 Fire Ants, all time (from 7:11) |
| Lob Grenade (`lob_grenade`) | weapon | 200 Fire Ants in one run (~250 a run by 10:00; the Drifter's favourite: his whatever) |
| Overkill (`overkill`) | passive | kill the Dune Scorpion (the 3:35 Elite in about a third of runs) |
| Spear (`pike`) | weapon | survive 4 minutes in one run (Ironwood lands with it whatever) |
| Quickdraw (`quickdraw`) | passive | reach level 10 in one run |
| Ricochet (`ricochet`) | passive | 30 Spit Cactuses, all time (from 4:17) |
| Rocket Pod (`rocket_pod`) | weapon | open 3 chests |
| Sabre (`sabre`) | weapon | 40 Skeleton Knights, all time (from 1:23; ~28 a run by 7:10) |
| The Chariot (`stride`) | card | survive 2 minutes without lifting the thumb |
| Death (`thirst`) | card | 60 Dust Mummies, all time (from 10:00; ~70 a run by 14:20) |
| Tumbleweed (`tumbleweed`) | weapon | 150 Skeletons, all time (from 0:53; 100-150 a run by 7:10) |
| Turret Buddy (`turret_buddy`) | weapon | open 10 chests |
| Zap Beam (`zap_beam`) | weapon | reach level 20 in one run |

#### 30.META.3 The Collection hides a hero's own items until he is owned

Garry: "Items that are hero specific should be hidden in the Collections Menu if that hero is not unlocked."
An item belongs to a hero when it is his own weapon (`WeaponDef.hero`: Revolver, Gravity Gun, Guitarra, Sun Scepter,
Basketball) or that weapon's evolution, a hero mutation (`MutationDef.hero`) or a perk (`PerkDef.hero`). While the save
does not own the hero (Registry.hero_state other than "owned": locked or on sale; a quest done but not bought is not
owned) the item is **left out** of the Collection: no tile (not a silhouette), not in the tab's count, not on a weapon
page's mutation list. It appears once he is owned. A favourite or a start weapon anyone may take (the Frisbee, the
Spear, Big Mouth, the Tommy Gun...) is nobody's own and always shows. The developer's Hidden list is never filtered.

#### 30.META.4 Thorns (the Upgrade board's Spite/Thorns nerfed)

Garry: "The Thorn Mirror Upgrade is way too OP, nerf it".

**Why it was too strong.** Thorns are a flat burst (`thorns` damage, unscaled by might, crits or the stage) to every
creature within 2.3 m each time a hit lands on the hero. Spite/Thorns gave +5 a rank, 30 at six ranks: as much as a
Thorn card at level 4 (8 a level, which costs 4 % cooldown a level), free from second 0 of every run. Stage-1 creatures
have about 16-30 HP in the first four minutes (skeleton 10 x 1.3 x the HP curve x the level factor) and 50-90 by 7:10,
so 30 thorns kill everything round him in one or two bursts: a hero who stands in the crowd wears an AoE aura of
30 x 2 bursts a second (the 0.5 s invulnerability between hits) = 60 damage a second on every creature touching him,
more than his starting Revolver. Pass 83's halved invulnerability (0.25 s) would have doubled it again (4 bursts a
second). It fades in stage 2 (x2.2 HP), which is why it reads as OP in the part of the run everyone plays most.

**The nerf.**
1. Spite/Thorns: **+2 thorns a rank** (was +5): 12 at six ranks, a Thorn card's level and a half. The text says "+2
   thorns a rank." (`content/talents/spite` form 0).
2. **Thorns answer at most one hit every 0.5 s** (`Game.THORNS_COOLDOWN`, the run's clock): the rate the 0.5 s
   invulnerability allowed until pass 83, so halving the invulnerability does not double thorns. It applies to every
   thorns source (the Thorn card, Cactus Hide, the talent): their per-second strength is exactly what it was in pass 82.
   Radius 2.3 m (`THORNS_RADIUS`) and push 6 (`THORNS_KNOCK`) unchanged, now named.
3. Thorns damage is recorded as the damage id **"thorns"** (the Results' Thorns row with the Thorn card's icon, the
   run record's damage sources, the DPS window), never through Run.add_damage, so it still feeds no life steal.

**Before / after** (Drifter, Revolver start, the board's Spite/Thorns only, `game/tools/_p83_META_thorns.gd`: he
stands still in the crowd from 0:00, HP refilled below 40 %, first card taken at each level-up; thorns' share of all
damage dealt, cumulative):

| Thorns ranks | thorns | 1:00 | 2:00 | 3:00 | 5:00 | thorns damage by 5:00 |
|---|---|---|---|---|---|---|
| 3 (half board) before | 15 | 58 % | 75 % | 79 % | 66 % | 53,262 |
| 3 after | 6 | 44 % | 54 % | 48 % | 20 % | 17,080 |
| 6 (full) before | 30 | 41 % | 38 % | 50 % | 35 % | 34,688 |
| 6 after | 12 | 55 % | 30 % | 24 % | 19 % | 17,400 |

Run sims (Drifter, 6 players, 10 minutes, `--bot daring=1 --death keep`: the explorer bot letting the crowd close in;
the board a quarter / half / full in the probe's forms with Spite as Thorns; thorns' share of damage, cumulative):

| board | 2:00 before / after | 4:00 | 7:10 | 10:00 |
|---|---|---|---|---|
| quarter (Thorns 1 rank) | 5.6 % / 4.1 % | 2.9 / 2.6 | 2.8 / 1.7 | 1.9 / 1.0 |
| half (3 ranks) | 10.5 % / 6.5 % | 4.9 / 3.1 | 2.6 / 1.4 | 1.9 / 0.7 |
| full (6 ranks) | 6.6 % / 5.0 % | 3.8 / 3.0 | 1.9 / 1.5 | 1.1 / 0.9 |

The bot keeps moving, so thorns stay a small share for it; the face-tank probe is the play the talent invited, where
thorns were half of all damage and now fall to about a fifth by 5:00 (thorns damage halved to a third).

### 30.SCENE Prop variants, ground shadows, the title scene

- **Prop variants** (props.json `variant_of`, `weight` default 1): wherever the map places a kind, its painting is the
  kind's own or one of its variants, picked by a hash of the spot (PropField.pick_look), weighted; the map's roll is never
  used, so a seed lays out the same spots, colliders and obstacle circles as before (the kind's `radius` makes the
  collider). Variants in play: agave_b, barrel_cactus_b, ocotillo_b, boulder_b, desert_bush_b, dead_shrub_b,
  joshua_tree_b, joshua_tree_c (each kind's own painting and its variants weigh 1: half the agaves are agave_b, a third
  of the joshua trees each look; desert_bush_b, the purple one, weighs 0.5: a third of the desert bushes).
- **Brittlebush**, a new bush kind (radius 0, walked through): in the bush patches' table at weight 2 (desert bush 3,
  creosote 3, dead shrub 2), the oasis greenery at 1 (of 13, the hidden yucca's 2 left out: 1 of 11), the tree stands' undergrowth at 1.5
  (desert bush 3, creosote 3, ocotillo 1, agave 1; the yucca hidden). A pick
  draws once whatever its table, so every seed keeps its spots; only which bush stands on some of them changes.
- **Ground shadows**: every painted prop, structure, barrel and sign post lies on one soft ellipse in the creatures' blob
  colour, drawn see-through at the creatures' shadow priority (under the gems and coins; a figure standing on one is
  drawn over it). Size per painting from its manifest `shadow` {w, d, x, z, a} (shares of the drawn quad's height:
  measured from the painting by tools/prop_shadows.py as 1.45 x a blend of the foot's width (0.45) and the lower body's
  (0.55), 0.7 of that deep, centred under the painted foot); darkness 0.55 solid things (rocks, the barrel cactus, every
  structure), 0.48 most plants, 0.40 airy ones (dead shrubs and trees, creosote, ocotillo, palo verde, brittlebush),
  0.28-0.30 the bones and skulls with their painted sand (0.40 the signpost painting). Barrels 0.95 x 0.66 m at 0.5;
  sign posts 1.25 x 0.8 m at 0.42. Each leans right (and a touch back) away from the paintings' upper-left light by
  0.08 (and 0.02) m per metre of the thing's height, at most 0.3 m. A broken barrel's shadow goes with it; a Strongbox's
  shrinks away over 2.2 s as its balloon lifts it (after the lift's 0.45 s beat) and grows back under one coming down
  (full by 6 m up).
- **The title's scene** (art/ui/title_scene.json): the map's own scatter is taken away within x -14..14, z -32..6 m of
  the hero's title spot and 12 paintings are laid by hand (a joshua tree and a saguaro framing the title, a low group
  either side of the hero, a dry shrub between them, a bush at each corner of his feet, faint shapes on the horizon);
  nothing within 1.3 m of his feet. The menus' backdrop still (art/ui/wanted/menu_backdrop.jpg) is that scene without
  the hero (tools/menu_backdrop.gd).

### 30.SCALE Boss HP by seconds of full DPS; the hero's power

#### Boss HP by seconds of full DPS (Garry: "at least 25 seconds of Player's FULL DPS on Tumbleweed king ... 40s for the next and a full minute to the last one")
- **Where**: map JSON `timeline_data.boss_hp_scaling.mode` ("seconds" | "dps") and `boss_hp_scaling.seconds` {boss id: s};
  WaveTimeline.BOSS_HP_MODE_DEFAULT "seconds", BOSS_SECONDS_DEFAULTS {tumbleweed_king 25, gila_grande 40, brander 60}.
  Red Canyon names them (mode "seconds", 25 / 40 / 60). Level Editor: Settings → Boss HP ("Boss HP is set by", one row of
  seconds a boss, the HP-against-full-DPS chart, the "How it works" box).
- **Rule**: when a boss arrives through the director (WaveDirector._start_boss), its HP = max(its data HP as before
  (hp × hp_mult_per_stage^stage × max(stage mult, 1)), the hero's FULL DPS on it right then × its seconds × (1 − its
  damage_reduction)) (WaveTimeline.boss_seconds_hp, WaveDirector.boss_seconds_target, EnemyManager.boss_hp_target held
  around the spawn). The HP bar shows that HP.
- **The game's default changed**: a map without `mode` (or without the block) now plays "seconds" (was pass 72's peg to
  the recent real DPS). The peg stays one choice away (`"mode": "dps"`); its exponent, window, floor, ceiling and ref_dps do
  nothing in the seconds mode. `enabled: false` = every boss at its data HP in either mode.
- **Never**: the debug arena, a boss of 0 seconds (or one neither the map nor the defaults name), Elites (by kind or
  modded), a boss spawned by hand outside the director.
- **Endless**: a returning boss takes its seconds of the full DPS the hero has then (the data HP grows with the stage as
  before; the larger wins).
- **FULL DPS** (HeroPower.full_dps, boss = true): Σ weapons (WeaponInstance.dps_estimate ÷ its crowd guess + its burn or
  poison kept up on one target) × the average crit (1 + crit_chance × (crit_damage − 1)) × (1 + elite_damage, Big Game
  Hunter). Crowd guesses taken out: Smasher, GravityGun, ConeWave ÷3; MineLayer, LaserBeam ÷2; SunScepter ÷1.6
  (WeaponInstance.SUN_CATCH); Frisbee ÷ frisbee_catch (2.57); Beam ÷ (1 + chains); a gun with a `blast` ÷ its blast_catch;
  ricochets are kept (measured: the Golden Revolver lands its whole estimate on a lone boss). Burn = fire_damage / 0.6 s,
  poison = poison_damage × stacks / 2 s. Left out: perks' own hits, thorns, Powder Keg, Overkill, marks, Sunburn.
- **Measured** (game/tools/_p83_SCALE_boss_probe.gd: difficulty_probe's builds, the boss held still 1.5 m beyond its radius
  in front of the hero, no crowd, no boss attacks; tools/dl/p83/SCALE/boss_b.log): every kill took at least the seconds:
  King 25 s → 29-42 s (Calavera 42.2, Drifter 36.0, Jeżyk 29.2, Fadeaway 32.6), Gila 40 s → 45-94 s (Calavera 50.9 (data
  HP won), Drifter 44.9, Jeżyk 93.6), Brander 60 s → 81-239 s (Calavera 80.7 (data HP won), Drifter 81.8, Fadeaway 93.8,
  Jeżyk 239.3: the Salt lands only where the boss walks). Real fights with the crowd and the kiting bot
  (difficulty_probe boss=1, tools/dl/p83/SCALE/real_a.log) run far longer (Gila 126-135 s, Brander 99 s+, the King 343 s
  or unfinished): the bot kites away from bosses and its weapons pick the crowd (pass 72's caution: bot fight lengths say
  little about a player's).

#### The hero's power level (Garry: "You will write how you calculate the hero power level")
- **power = √((full DPS ÷ 20.4) × (effective HP ÷ 100))** (HeroPower.power_from; BASE_DPS 20.4 = a fresh level-1 Drifter's
  Revolver (20.0) × his 1% crit, BASE_EHP 100 = his max HP): a fresh level-1 Drifter on a clean save is 1.0. Twice the DPS
  alone = 1.41, twice the DPS and twice the HP = 2.
- **Full DPS** as above without Big Game Hunter (boss = false).
- **Effective HP** = (max HP + shield_max + 30 s × (regen + lifesteal a second)) ÷ ((1 − damage_reduction, ≤ 0.8) ×
  (1 − evade, ≤ 0.9)); lifesteal a second = min(lifesteal × full DPS, max HP × lifesteal_cap) (HeroPower.ehp,
  SUSTAIN_SECONDS 30).
- **Why the root**: a fight's length against the hero grows with DPS × HP; the root keeps the number readable. Measured
  on difficulty_probe's builds: King (7:10) 3.0-4.7, Gila (14:20) 6.0-23.9, Brander (21:30) 14.3-49.4; heroes at level 1
  with their own weapon: Astro 0.83, Calavera 0.92, Jeżyk 1.0, Solenne 1.04, Ironwood 1.19, the Drifter 1.0 (by
  definition; 1.30 before the constant was set), May 1.63, Fadeaway 2.02 (no talents, the Drifter's sheet).
- Recorded every second in the run record (`power`, `full_dps`, `ehp`; `power_hp` when the map scales by it).

#### Enemy HP by power (Garry: "the higher the Player power level the higher the HP. Default scaling is 1, meaning no scaling at all")
- **Where**: map JSON `timeline_data.power_hp_scaling` (default 1 = none) and `power_hp_max` (default 10);
  WaveTimeline.POWER_HP_SCALING_DEFAULT / POWER_HP_MAX_DEFAULT. Level Editor: Settings → Hero power.
- **Rule**: every ordinary creature's HP × clamp(power ^ (scaling − 1), 1 ÷ max, max) (WaveTimeline.power_hp_factor):
  1 = ×1 at any power; 2 = the HP in step with the power (power 4: ×4); 1.5 = with its root (power 4: ×2); below 1 the
  creatures soften as he grows. Power 1 is ×1 at any scaling.
- **When it is read**: with the hero-level factor (folded into `lv_hp`): a roster row or a wave fixes it at its first
  spawn (pass 58's "the same wave does not change on the fly"; in endless at each endless wave), an event at its moment,
  a creature spawned by hand live. Never a boss (Boss HP has its own rule) nor an Elite by its kind; Elite-modded
  creatures yes. The debug arena: ×1. At scaling 1 the power is not even worked out.
- Red Canyon: not set (1, no scaling).

### 30.TIMELINE Who spawns: the window shares, a row's draw interval

Garry (2026-10-16): "for Continuous spawning, I would still like to control the interval of continuous spawning, the
0.7s can be a default. And since continuous spawning has these inevitable intervals the notches on the enemy node should
reflect that."

#### The game (WaveDirector._tick_row_intervals / _interval_part / _burst_from)
- A roster row in the continuous draw (a continuous row, or a waves row with `trickle`) may carry **`interval`**
  (seconds). Without it the row is drawn at the director's spawn check (`spawn_interval`, Red Canyon 0.7 s) exactly as
  before. **A map where no open row has the key plays exactly as before (the same code path and the same dice).**
- With it the row has **its own clock**: a draw on the frame it opens (its `t`), then every `interval` seconds while it
  is open (`t` <= clock < `until`). The clock runs in real seconds through boss fights and the portal wait, like the spawn
  check (the run clock stands still there).
- **What a draw holds**: every draw (the spawn check for the rows without the key, a row's own clock for a row with
  it) takes randi(`burst_min`..`burst_max`) load units **x frac**, frac = the drawing rows' weight / the weight of every
  open drawn row of the same channel (regular or hell) at that second. So a row's expected rate is a burst x (its
  weight / the channel's) / its interval: an interval equal to the spawn check brings what the spawn check did; **half the
  interval brings about twice as much, double about half**, a little at a time; the other rows keep their own rate (the
  spawn check draws them with their share only).
- **A cut burst below one creature** (load left < the creature's cap_share) brings one creature with that chance
  (load / cap_share), so a light row on its own clock is not rounded up to a creature at every draw. Only for a cut
  burst (frac < 1); a whole burst keeps today's rule (the last draw brings up to what the burst holds, rounded up).
- **Least interval 0.1 s** (`ROW_INTERVAL_MIN`): a smaller one counts as 0.1. Not a number above 0 = no own clock.
- Unchanged: the cap, the hell cap, the hard cap and `max_alive` (a row at its max_alive is out of the draw and out of
  the weights), the pack and pattern rules, a waves row's waves and what they owe (those come first at the spawn check,
  not at an own-clock draw), the numbers (pass 58), the portal wave.
- Red Canyon: no row was given an interval (Garry sets it in the Level Editor).

#### The Level Editor
- **Draw every (s)** on the row form (after the pacing fields), shown while the row is in the continuous draw; empty
  shows the map's spawn check as its grey number. The note under it says at the spawn check / own clock, about how many
  load units a draw holds at the row's start and how often against the spawn check. The Pacing note says the same.
- **Validation**: not a number above 0 (error: the game draws it at the spawn check); on a waves row that does not
  trickle (warning: ignored); under 0.1 (warning: counts as 0.1); faster than a quarter of the spawn check (warning: over
  4x what its weight says).
- **The yellow etches** of a continuous row are now **ticks**, a short one at each draw (the spawn check's rhythm k x
  spawn_interval from 0:00, or the row's own t + k x interval) where its weight is above 0; where they would be under
  **3 px** apart at the zoom they are drawn as a **dotted line** (never solid), with a note on hover. The waves rows' tall
  ticks are as in pass 81. (The spawn check runs on through boss fights, so later in a run a default row's ticks are its
  rhythm rather than its exact seconds: the hover says so.)
- **The window** ("past N s", the box next to Snap on; 1..120, default **5**, the browser remembers it; its tooltip and
  the readout title's explain it): every share the page shows is the **% of all creatures spawned in the past N seconds**
  before the pointer, read off the Spawned so far estimate (the cap and its room, the weights, the spawn check and the
  rows' own clocks, the waves and what they owe, the kill rate), on its whole-second points.
  - The readout ("the highlight") lists every roster row open now or spawning in the window and every waves[] block
    spawning in it with its share, largest first; rows open but at 0% dimmed; a waves row says its next wave; the rest
    (swarms, the elite-modified, specials, Elites, bosses, a boss's minions, the portal wave) as one "other" line.
  - On the lane, the roster bars that spawned nothing in the window **dim** while the pointer is on the timeline.
  - Hover a bar: its share of the past N s (and the old weight share, muted). Hover a wave tick (within 8 px): the
    wave's count and its share of the **N seconds from it** (with how many the cap let in by then). Hover a draw tick:
    how often, the load a draw holds (the average burst x its weight share), its share of the past N s. Hover a waves[]
    block's tick: the burst and its share of the N s from it.
- **The Share lane is removed** (its band, card, table, legend and the select kind).

### 30.LEAD The lead's changes in this pass

- **Invulnerability after a hit halved** (Garry): `hit_invuln` 0.5 -> **0.25 s** (StatSheet.PLAYER_DEFAULTS, Player's
  fallbacks, the Level Editor's vocab copies).
- **The sand**: Red Canyon plays `ripples_pebbles` (`timeline_data.sand`, Garry's pick "Rip+P"); the other four stay
  switchable in the Level Editor's World card and the arena's WORLD tab (dev).
- **A round hits a body where it is drawn** (lane SCALE found the King's 2.2 m body let scattered rounds through): a
  round of radius r touches a creature within r + max(pad, the creature's radius - 0.15 m) of its centre
  (`EnemyManager.indices_touching`; pad 0.35 for shots, 0.4 for missiles, as before), so an ordinary creature (radius up
  to 0.5 m) is hit exactly as before and a big one wherever it is drawn. Calavera's King kill with every shot able to
  land: 42.2 s -> 25.2 s (25 asked).
- **Garry's map edits re-pinned**: his cap curve (starts at 181) and side weights (30/20/20/20) are read from the file
  by content_test, pass17 and pass54_waves.

## 31. Pass 84 (v0.70): one spawning language, the Timeline tab, the Sim's overlay, shadows

Garry's request (2026-10-16, tools/dl/p84/REQUEST.md). Each lane's rules as it wrote them.

### 31.SPAWN One spawning language: rows that do everything

Every number and condition below is new in pass 84 (keys: keys_SPAWN.md; code: WaveTimeline.gd "one spawning
language", WaveDirector.gd "one spawning language (pass 84)", model.js spawnEstimate / convertLegacy).

#### The row is the one way to spawn
1. **A swarm is a "once" row.** Red Canyon's five swarm events (the Special Goblin 2:00, the ant swarm 10:10, the
   armadillo charge 13:20, the imp swarm 17:20, the ants 20:04) and its Elites-every (5:01, every 129 s) are rows now
   (tools/migrate_timeline.py, ids r6 r7 r8 r9 r17 r53, appended after the old rows). Their numbers are the events'.
2. **A once row** fires one wave at `t` + `offset`: `count` creatures (default its `pack`, else the creature's).
3. **The mix** (WaveTimeline.row_in_mix): a row that names one creature by id, with no `elite`, no `special`, not
   `once`. Only the mix is read for: the portal wave (12 bodies from the rows open at the stage's end), a coloured
   Elite's candidates and the "roster" creature (drawn by elite_weight), and the pass 58 join (an event's or once row's
   numbers from the mix row that brings the same creature and look then). So a swarm that became a row never feeds the
   portal wave or the Elites, as its event never did.
4. **Numbers** (pass 58's R1 kept): a mix row's creatures fixed from its start (unchanged); each creature of a list row
   from the row's start (its own key `row:<id>#<k>|<creature>`); a "roster" creature plays the numbers of the row it was
   drawn from (or this row's own stats when it sets some); a **once** row takes the event rule: the moment's numbers, or
   the mix row's that brings the same creature and look then (what the swarm events did).
5. **`enemy` lists and "roster"**: a list draws one creature per wave (a continuous row per draw) by `enemy_weights`
   (an entry past their end weighs 1, a 0 never comes); "roster" draws each creature from the mix rows live at that
   second by their creature's elite_weight (only creatures that can be Elites), grouped by the row drawn.
6. **`every` [min, max]**: a fresh gap drawn inside it after each wave (a timer: the next wave counts from the wave it
   fired, not from a fixed grid). A plain number keeps pass 81's fixed rhythm t + offset + k x every.
7. **Elite rows** (`elite` "random" or a modifier id):
   - without a `pattern`: each of `count` (default 1) is one coloured-elite arrival (WaveDirector._spawn_elite: alone, as
     its pack or a ring of 12 m by the creature's elite_formats, the "MOD NAME" toast); like the events they ignore the
     cap and the hard cap (respect_cap is not read for them);
   - with a `pattern`: `count` creatures in that pattern, every one wearing the modifier, under respect_cap;
   - **colour**: an elite wave waits for colour_after_kills (50 on Red Canyon), asking again every second; a
     continuous elite row is out of the draw until then;
   - **Hot Sauce**: an elite paced row's gap is divided by elite_pace() = 1 + 0.5 x the hero's `difficulty` (as the
     elite_every timers and endless's were; pass 47's rule, now on the rows too).
8. **`special`**: every creature of the row comes as its coloured variance special (force_special), colour or not, with
   no banner unless `banner` says. The specials' cap (special_defaults.max_alive 3) never stops a forced one.
9. **`banner`**: a toast in the swarm orange the first time a wave brings anything (once per wave).
10. **`ring_radius`**: pattern "ring" with a radius is the classic even ring at that radius (EnemyManager.spawn_ring: no
    jitter, a 0.1 rad slide); without it a ring row is pass 57's thick band at 11.7 m. Converted swarms: 16 m.
11. **`chance` / `t_jitter`** (once and waves rows): rolled once a run at start (the row's jitter first, then its chance,
    the events' order); a failed chance skips the row for the run; the jitter moves the whole row (its window and its
    waves) by a draw inside +- t_jitter, never before 0 s. Rows without them take no dice (an old map's dice unchanged).
12. **A once row whose second the clock jumped past by more than 2 s** (ROW_STALE_S: smoke_run, hell_check, the
    arena's clock) is dropped, as the jumped-over events were; in a run the rows tick every frame, so it never is.
13. **Differences from the events** (named, all rare):
    - **`respect_hard_cap`** (new, default true): false lets a paced row's waves past the map's hard_cap (260 on Red
      Canyon), stopped only by the 320 body limit, as the swarm events were; the converted swarms carry false. Found by
      the first sim: the Red Canyon crowd sits at the hard cap (259-260 alive) round 2:00, and a converted Special Goblin
      that kept the hard cap came 17-24 s late in half the runs. What the body limit cuts stays owed (the event dropped it).
    - a once row honours its creature's max_alive (the swarm event did not; no swarm creature of Red Canyon has one).
    - an elite once row that falls due before colour asks again every second instead of joining the held list (one
      released a second): the same second, give or take one.
    - a waves[] entry converted (no map has one): its last burst brings a full `burst`, not the remainder; several
      alternatives roll apart (each its share as its chance) instead of one per run; its elite creatures wait for colour
      instead of coming plain before it. The converter prints these as notes.

#### The density floor
14. `floor_curve` [[t, n], ...] (linear between points, flat outside; absent = none, today's play): every frame, while
    fewer than floor(n) creatures are alive on the regular channel (everything but the creatures the hell rows open then
    bring), the director draws the regular continuous rows (row_drawn; an elite row only once colour is open) at once:
    a row by its weight now, its pack (a "single" row one) at a time, each cut to the lack, the cap's room in load units
    (cap less the regular load) and the hard cap, until the floor is met, the room is gone or 64 came (FLOOR_FILL_MAX);
    at most 32 draws a frame. In boss fights and the portal wait too, never past their cap (0 after a portal wave).
    Red Canyon has none.

#### The estimate (model.js spawnEstimate == selftest.py spawn_estimate)
15. **Lifetime model**: by default a share `turnover` of the crowd dies a second (the old rule: an exponential lifetime
    of 1 / turnover s); with `opts.life` {id: seconds} (the Sim's life_by mean) that creature leaves at 1 / life a
    second instead.
16. once rows as their wave (count x chance, cut by the hard cap and, with respect_cap, the channel's room; a mark
    "swarm"); `every` ranges at their middle; list creatures by enemy_weights shares, "roster" by the mix rows'
    elite_weight shares, the load per body the shares' mean; elite rows without a pattern as coloured-elite arrivals
    (`mod`), with a pattern as `mod` creatures; special rows as `col` (forced); chance multiplies the count; jitter is
    ignored (it averages out, as for events); Hot Sauce is not modelled (no hero).
17. **The floor in the estimate**: each step after the draws, the lack is shared out over the open drawn regular rows by
    weight (each cut to its max_alive room), the whole scaled to the cap's room in load units and the hard cap.
18. **Full and starving** (per point, over the second's director spawn checks): `full` = the share of the checks at
    which the regular channel had no room (cap load or hard cap); `starve[row]` = the share of the checks at which an
    open drawn row weighing above 0 found its channel full, or a paced row still owed creatures.

#### The shown difficulty (model.js creatureDifficulty == WaveDirector.shown_numbers)
19. One HP and ATK per row and second: the creature's JSON hp (or the row's `stats.hp`) x hp_mult x the HP curve at the
    row's start (none when stats.hp is set; a once row: its own second) x the stage multiplier at the second x
    (1 + level_hp_per_level x (level - 1)) x creature_hp_mult; ATK the same with damage, damage_mult, the damage curve,
    level_damage_per_level and creature_damage_mult; the hero-power factor at power 1 (= 1). An Elite by its kind:
    elite.hp_mult_per_stage^stage x the stage x creature_hp_mult; a boss: boss.hp_mult_per_stage^stage x the stage. The
    level: the page's `level`, else a Sim's level curve, else DEFAULT_LEVEL_CURVE (the pass 84 baseline sim: the
    Drifter with a quarter of the board, the median level by the clock).

#### Proof: Red Canyon before and after (20-run sims each, private snapshots)
Private sims (tools/dl/p84/SPAWN/psim.py: tools/sim_batch.py with its own lock folder, user folder and snapshot, so
the shared Sim tab was never blocked): the Drifter, a quarter of the Upgrade board, the explorer bot, death "keep" (the
hero plays on to 25:00, every down counted), seeds 1-20, 60 fps. **head** = HEAD e158f49 (code and map as they were);
**old** = this pass's code with the old map (the events' own code path); **new** = this pass's code with the migrated
map (the rows). Mean +- standard deviation over the 20 runs; the swarm and Elite counts come from the director's own
`spawn84` log lines (head has none). Same-seed runs part ways within a few minutes whatever changes (they do between
head and old too), so the proof is statistical: every difference is well inside one standard error of the difference
(about sd x 0.32), and the director's lines show the converted rows fire exactly as the events did: every swarm whole
at its second in every run that reached it, the Elites at 5:01 and every 129 s after.

| measure                       | head              | old               | new               |
|-------------------------------|-------------------|-------------------|-------------------|
| runs                          | 20                | 20                | 20                |
| deaths a run                  | 28.9 +- 14.8      | 25.8 +- 17.1      | 24.4 +- 16.5      |
| end level                     | 46.6 +- 11.4      | 45.4 +- 11.5      | 48.7 +- 11.5      |
| kills a run                   | 11805.4 +- 6209.1 | 10921.1 +- 5687.8 | 12781.0 +- 6685.0 |
| level at 3:35                 | 7.7 +- 2.2        | 8.2 +- 2.8        | 7.8 +- 2.8        |
| level at 7:10                 | 18.9 +- 5.0       | 17.8 +- 6.1       | 18.6 +- 5.3       |
| level at 10:45                | 28.5 +- 4.6       | 26.9 +- 5.2       | 28.4 +- 5.3       |
| level at 14:20                | 33.2 +- 5.7       | 31.8 +- 6.7       | 34.1 +- 6.5       |
| level at 17:55                | 40.5 +- 7.1       | 39.2 +- 8.1       | 41.5 +- 7.8       |
| level at 21:30                | 46.2 +- 10.8      | 44.2 +- 11.3      | 48.4 +- 11.3      |
| kills red_goblin              | 871.0 +- 314.1    | 854.2 +- 424.1    | 924.5 +- 383.6    |
| kills fire_ant                | 739.2 +- 421.2    | 655.6 +- 306.4    | 775.7 +- 423.6    |
| kills armadillo               | 1059.2 +- 735.4   | 1017.9 +- 582.9   | 1186.8 +- 677.3   |
| kills imp                     | 1577.0 +- 1081.1  | 1467.0 +- 1073.8  | 1860.7 +- 1373.2  |
| kills skeleton                | 1341.5 +- 507.3   | 1201.8 +- 465.8   | 1373.6 +- 653.6   |
| kills lesser_scorpion         | 823.5 +- 170.8    | 733.1 +- 186.4    | 778.9 +- 211.5    |
| kills dune_scorpion           | 0.9 +- 0.7        | 1.0 +- 0.7        | 0.8 +- 0.9        |
| kills sun_prophet             | 0.7 +- 0.8        | 0.8 +- 0.9        | 1.1 +- 0.9        |
| kills stone_golem             | 1.2 +- 0.8        | 0.8 +- 0.8        | 0.8 +- 0.9        |
| kills fire_ant min 10-11      | 29.6 +- 10.1      | 25.3 +- 6.5       | 25.4 +- 7.4       |
| kills armadillo min 13-14     | 21.5 +- 2.9       | 25.4 +- 13.2      | 22.0 +- 4.0       |
| kills imp min 17-18           | 373.6 +- 224.3    | 382.1 +- 256.7    | 491.9 +- 353.2    |
| kills fire_ant min 20-21      | 215.1 +- 222.2    | 194.9 +- 201.5    | 246.3 +- 230.8    |
| swarm/once spawns a run (log) | n/a               | 4.8 +- 0.4        | 4.8 +- 0.4        |
| swarm creatures a run (log)   | n/a               | 95.4 +- 8.8       | 94.2 +- 9.8       |
| elite arrivals a run (log)    | n/a               | 8.3 +- 1.3        | 8.1 +- 1.1        |
| elite creatures a run (log)   | n/a               | 8.3 +- 1.3        | 8.1 +- 1.1        |

swarm spawns seen (old): red_goblin x1 @ 120 in 20 runs, fire_ant x24 @ 610 in 20 runs, armadillo x20 @ 800 in 20 runs, imp x30 @ 1040 in 20 runs, fire_ant x24 @ 1204 in 17 runs
swarm spawns seen (new): red_goblin x1 @ 120 in 20 runs, fire_ant x24 @ 610 in 20 runs, armadillo x20 @ 800 in 20 runs, imp x30 @ 1040 in 20 runs, fire_ant x24 @ 1204 in 16 runs
elite arrival clocks, first runs (old): 301,430,559,688,817,946 | 301,430,545,659,774,889 | 301,430,559,688,817,946 | 301,430,559,688,817,946 | 301,430,559,688,817,946
elite arrival clocks, first runs (new): 301,430,559,688,817,946 | 301,430,559,688,817,946 | 301,430,559,688,817,946 | 301,430,559,688,817,946 | 301,430,559,688,817,946

The first "new" sim (before `respect_hard_cap`) had the Special Goblin 17-24 s late in half the runs: the crowd sits at
the hard cap (259-260) round 2:00 and the row then kept the hard cap; with respect_hard_cap false on the converted
swarms (the events' rule) it comes at 2:00 in all 20 runs.

### 31.TIMELINE The Timeline tab: sections, marks, plain charts, the inspector

Nothing here changes play: these are the Level Editor's own numbers (tools/level_editor/timeline_model.js and
timeline.js). Page settings live in the browser (localStorage), never in the map.

#### On screen
- Alive = the estimate's crowd at each run second (model.js spawnEstimate, lane SPAWN; its `aliveBy` per creature when
  given). Split by source with a recurrence: alive_k(t) = alive_k(t-1) x (1 - kill rate)^dt + spawned_k since, then each
  creature's sources scaled to the estimate's count for that creature (only the split between rows of one creature
  comes from the recurrence). A source that brings several creatures (a list, the roster draw) is filed under its
  creatures.
- Regular vs hell: a source of a row / wave on channel "hell" is hell.
- The cap in bodies = cap ÷ (regular load ÷ regular bodies); load = Σ alive × cap_share (default 1). With nobody alive:
  the cap ÷ 1. The cap and the load come from the estimate's point (`cap`, `load`) when it has them, else the curve and
  the sources.
- Cap full = the estimate's `full` (share of the second's spawn checks with no room) ≥ 0.5; an estimate without it:
  load ≥ 97% of the cap (FULL_AT).
- Starving rows: the estimate's `starve` share ≥ 0.25 (STARVE_SHARE); without it: open, in the continuous draw,
  weight > 0, nothing spawned in the 5 s before (STARVE_S) while the cap was full all that time.

#### Challenge (two measures, a switch in the section bar)
- Seconds to clear = crowd HP ÷ hero DPS. Crowd HP = Σ over living creatures (bosses left out) of their HP in play: the
  row's HP fixed from its start (the creature × the HP curve there, or the row's own) × the stage multiplier ×
  creature_hp_mult × the hero-level box; non-row creatures (swarms, Elites, specials) at the curve of their second (read
  every 10 s); a coloured special counts its special HP (× special hp, the map's default 15) for the share of that
  creature's alive that is coloured.
- Health bars = Σ HP × ATK ÷ bite interval (contact_cd, default 0.6) ÷ (hero DPS × hero EHP) — SIMVIEW's `challenge`.
- Hero DPS / EHP: the Sim's `hero_dps` / `hero_ehp` (pass 84 Sims); an older Sim: its real damage a second (`dps`, 5 s
  window) and EHP 100; no Sim: a typical hero: power on PowerModel.TYPICAL at the stage marks (1, 3.5, 9, 23), straight
  between on a log scale and growing on after the last; DPS = 20.4 × power², EHP = 100 (the p83 Sim: EHP barely grows).
- Zones: seconds easy < 10, hard > 30; bars easy < 1, hard > 3 (page settings, one pair per measure; "fair" includes the
  hard limit itself).
- The Sim's line: seconds = its keep_up (median run, from result.json, normal phase only); bars = its `challenge` median.

#### Composition
- On screen: each creature's share of the alive count (estimate or the Sim's `alive_by`); spawned: its share of what
  spawned in the past N s (the top bar's "past" box). The ten largest over the view drawn, the rest grey "others"; the
  hover lists creatures with half a body or 0.5% and more.

#### Spawn rows
- Quantity: continuous "≈N/min" = what the estimate says the row spawned over its open life ÷ its open minutes (to the
  run's end when open); waves "C every E s" (or "E1–E2 s", "+ drawn" when it trickles); once "once C".
- HP / ATK on the bar: in play at the row's start (Model.shownDifficulty when lane SPAWN provides it, else the page's
  creatureAt with t0 = the row's start).
- A once row with no until is drawn as a short block (46 px or 10 s, whichever is longer).
- Suggest roles (only untagged rows, one undo step): special → special; an elite modifier → elite; once or off the cap
  → swarm; a creature with a ranged / artillery / sniper block → ranged; HP ≥ 60 or cap_share > 1 → tank; else fodder.

#### Warnings
- Cap full: every full stretch of 3 s or more, with the rows starving in it (sampled every 2 points).
- Never spawns: a row whose estimate total is under 0.5 (rows the estimate files under no source of their own, an
  elite or roster-draw or list row, are not judged).
- Tiny share: a continuous or waves row (not a once row: its share is its one wave) that never makes 1% of what spawned in any 10 s window (windows every 5 s from its start − 1 s).
- Difficulty jump: the crowd's HP on screen more than doubling from one run second to the next while 10 or more are
  alive (the 6 largest, with the row that spawned most then).
- Floor above the cap: the first second (every 5 s) the floor asks more bodies than the cap holds at the crowd's mix.
- Identical rows overlapping: the same creature, look, pacing, channel, pattern, every, count, elite, special and
  overrides, their spans overlapping.

#### Validation (app.js, errors block Save)
- Errors: pace not continuous / waves / once; every as a range not [min, max] with 0 ≤ min ≤ max; an unknown elite
  modifier; special not true/false; ring radius under 1 m; an empty creature list or an unknown creature in it; a floor
  point not [seconds, creatures] or negative.
- Warnings: a banner on a continuous row; a ring radius without the Ring pattern; an unknown role; special with an elite
  modifier; the roster draw with no elite modifier; a range's minimum under 1 s; a floor above the hard cap; a variant on
  the roster draw.

#### Split at cursor
- Row i at second t (inside its span): the row ends at t; a copy with a fresh id starts at t; the presence points before
  t stay with the first part, those after t go to the copy, both get the presence at t as a point; a once row's copy
  becomes continuous (it would fire again).

### 31.SIMVIEW The Sim's per-second data for the Timeline

Nothing here changes play: the sampler in game/tools/sim_run.gd only reads the game. These are the exact definitions
of the numbers the Timeline shows from a Sim (the same words are in overlay.json's `rules` for the page).

#### Per run, per second of play (game/tools/sim_run.gd, one entry per recorder row)
- **alive_hell**: creatures alive (not dying) whose creature id the hell channel brings at that moment (the director's
  own rule, WaveDirector._hell_load: an id is hell while a hell roster row or hell wave of the moment brings it).
  `alive_hell_by` the same by id.
- **load** / **load_hell**: the regular / hell channel's crowd in cap units: each creature alive (not dying) its type's
  `cap_share` (the fodder 0.5). The director spawns the regular rows while load < cap.
- **cap_hell** = hell_cap_at(stage) x current_cap(); **hard_cap**: the map's body limit.
- **cap_full** (0..1): checked every **0.2 s of play** (SV_CHECK_S): full when current_cap() > 0 and (load >= cap or
  alive_count() >= hard_cap); the value is the share of the second's checks that were full.
- **starving_by[row key]** (0..1): the share of the second's checks at which the row starved. A row starves at a check
  when (a) it is in the continuous draw (WaveTimeline.row_drawn: continuous, or waves + trickle), open at the director's
  clock (Run.elapsed, a second early outside the normal phase, as _spawn_burst reads it), weighs above 0
  (_roster_weight), its creature is under its max_alive, and its channel is full (regular: load >= cap; hell: load_hell
  >= cap_hell; either: alive >= hard_cap) while the cap is above 0; or (b) it is paced (pace other than continuous:
  waves, SPAWN's once) and the director's state for it (_row_waves[key].owed) still owes creatures. Keys:
  "row:<id>#<index>" or "row#<index>" (WaveDirector._row_key_at). Not covered: an old map's waves[] block (Red Canyon
  has none) and old swarm events with respect_cap (SPAWN migrates them to rows).
- **threat**: the sum over every creature alive (not dying; the boss left out) of max_hp x dmg / contact_cd (its bite's
  damage a second; the cadence at least 0.05 s). Both numbers are the creature's own as spawned (all multipliers in).
  The bite's 1.5x on a charge and the contact cap (contact_cap x his max HP) are not applied.
- **hero_dps**, **hero_ehp**: HeroPower's full DPS and effective HP (the recorder row's full_dps, ehp).
- **challenge** = threat / (hero_dps x hero_ehp); 0 when that product is 0.
- **life_by[id]**: per stage slot (stage 1, 2, 3, then everything after), deaths `n` and the seconds of play they lived
  `s` (spawn = the first frame the slot's spawn number is seen, death = EnemyManager.creature_dying); `gone` = freed
  without dying (a stage's clear: the slot reused or the run ended with it empty), `open` = still alive at the end.
  Neither gone nor open is in the mean (a censored mean: the longest-lived creatures are under-counted a little).

#### Averaged
- **Per play second** (result.json, sim_batch.py aggregate() and its twin sim_avg.js aggregate()): the new series are
  levels (mean over the runs still playing); `threat` banded (p10/p90); `challenge` a MEDIAN series (middle run and
  p10/p90, never a mean); alive_hell_by and starving_by level breakdowns (mean over the runs still playing).
- **Per clock second** (overlay.json, sim_batch.py overlay() and its twin sim_avg.js overlay()): each run's rows in the
  normal phase binned to c = floor(clock + 0.5), the later row winning, a skipped second inside a run carrying the row
  before; boss and portal rows left out. Means over the runs at that clock second; bands (p10/p90) for alive, threat,
  power; challenge a median; alive_by = the regular channel (alive_by - alive_hell_by per id); breakdown means count a
  run without the id as 0; ids whose sum is 0 dropped; life_by summed over runs (mean = total seconds / total deaths).
- **The route** (GET /api/sim/overlay): the newest sim of the map that is finished (not running, not partial, a run
  ok) and real (not --synthetic); creatures past the top N (default 8, 1..30) summed into "__other".

### 31.LEAD The lead's changes in this pass

- **Every creature on screen casts its shadow** (Garry: "The shadows on the enemies seem to have started to break. At
  certain angles and at certain distances they don't render"): with more than SHADOW_BUDGET (70) alive, only the first 70
  within 10 m of the hero had a shadow, so with Garry's crowd (cap from 181) the creatures up the portrait screen lost
  theirs. Now a creature casts one when the whole crowd is under the budget, within 10 m of the hero, or seen by the
  camera (`is_position_in_frustum` at its feet); its draped transform is reused until it moves 0.08 m, changes type or
  its shrink in the air (`EnemyManager._shadow_xform_cached`); the shadows' MultiMesh has a fixed box (never culled
  stale). Cost on the PC at 250 creatures: enemies.render about 1.4-1.7 ms (was about 0.9-1.0).
- **Hard cap and summons**: splits and boss summons are not held by the director's hard cap (SIMVIEW saw 262 / 260 once);
  unchanged, named here.

## 32. Pass 85 (v0.71): Fadeaway's puppet, the title, tints, trees, teleports, the Watch, the Dynamite Bandit

Garry's request (2026-10-17, tools/dl/p85/REQUEST.md). Each lane's rules as it wrote them.

### 32.FADE Fadeaway's Puppet look FAD-D

No game rule changed: no game code, no number. Fadeaway gained one art look, FAD-D (`variants.FAD-D`, `fresh: true`);
his played look stays FAD-C (`variant`) until Garry picks.

Art-pipeline facts worth a line in the Puppet method's section (§13 / pass 71):
- **FAD-D's recipe** (hero_puppet on FAD-C's stills `c`, seeds as FAD-C: seed_offset 2243; anim_seed 2): guides
  `fadeaway_puppet_run` (OpenPose, framed by the soles, face = nose) and `fadeaway_puppet_run_depth`; depth views
  **fd and back** only (`puppet.depth_views` ["fd","back"], `ctl_drivers` the same), front, side and bd on the stick
  figure; `run_fit` tools/dl/drivers/fadeaway_puppet_run/silhouette.json (run/idle medians: front 0.980, fd 0.947,
  side 0.938, bd 0.978, back 1.023); `fringe_remap` on.
- **Depth on a purple jersey**: Wan 2.2 Fun Control on the depth video painted his side and bd jerseys a dull
  grey-purple on two seed sets (the raw clip frames, not the fringe clean); the stick figure kept the still's purple.
  The default depth views (fd, side, bd, back) are not safe for a saturated purple outfit: check the side.
- **The rig's hand finder** (puppet_blender.find_joints) takes the hand's tip as the arm-side vertex farthest along
  the forearm down to 12 % of the height under the separated rows; wide flared shorts put that vertex on the hem
  (knee height) and the hand bones ran into the shorts (spikes in bendtest.png). Fixed for Fadeaway by
  tools/dl/p85/FADE/rig_fix.py: the tip = the farthest vertex within max(2.5 x arm radius, 5 % of the height) of the
  forearm's line, the wrist 0.095 x height before it. Not fixed in puppet_blender.py itself (not this lane's file): a
  candidate for the lead.

### 32.WORLD The title's sand and presets, natural tints, two trees, the teleports

- **The title's map** is built with the map's own file standing in for Run.map, so it wears the map's chosen sand
  (Red Canyon `ripples_pebbles`), its oases block and its rock and wall colours, as a run does (before, the title showed
  the pass 81 default sand until a run had started). The menus' backdrop still (art/ui/wanted/menu_backdrop.jpg) is
  re-shot from preset 0 on that sand.
- **Title presets**: art/ui/title_scene.json holds six arrangements for Red Canyon (Saguaro stand = pass 83's, Palm
  hollow, Boulder garden, Joshua grove, Ocotillo flats, Dead wood), 7 to 12 paintings each, one drawn at random each
  time the title opens (a kept world takes its last preset off and lays the new one in the same slots). Every painting
  stands more than 1.3 m from the hero's feet, inside the cleared box x -14..14, z -32..6 m.
- **Natural tints**: every painted prop kind varies its colour a little per placed prop, rolled from its spot (the same
  for a map seed): plants' greens (hue window 0.17-0.45) up to 0.03 yellower / 0.02 bluer, saturation x0.85-1.12, value
  x0.86-1.05; the agave's blue-greens similar (x0.84-1.05); trunks and dry wood (window 0.95-0.13) +-0.01 hue,
  x0.85-1.1 saturation, x0.92-1.05 value; dead shrubs and the dead tree greyer or browner (saturation x0.75-1.2); rocks
  and boulders barely (hue +-0.008, saturation x0.92-1.06, value x0.95-1.04); bones and skulls bleached or yellowed
  (saturation x0.8-1.15); flowers a little in hue (the purple sage +-0.02, brittlebush and palo verde yellows +-0.015,
  the ocotillo's red tips +-0.02). Greys and the dark outline are never tinted. Bounds for any rule: hue +-0.08,
  saturation x0.6-1.4, value x0.75-1.2. Structures, barrels and signs are not tinted.
- **Two trees**: fan_palm_b (a twin palm) is a variant of the fan palm (weight 1: half the palms); joshua_tree_d (a
  lopsided, leaning joshua tree, drawn 0.8 of the others' size in its 4.6 m quad, centred on its trunk) a fourth look
  of the joshua tree (a quarter of them). Both keep the kind's collider (radius 0.2 / 0.22).
- **Teleports**: the trigger ring 1.8 m (was 2.2), the painting 2.7 m (was 3.2; the portal swirl scales with it).
  3 per run, 4 in a third of the runs (`per_map.max_chance` 0.33), standing apart from the weighted draw like the Totem
  Poles: each the farthest of 16 fair spots within 0.24-0.88 of the arena's radius, 22 m (the map's spacing) from every
  other structure, off the river bed, out of the paintings' cover, and 40 m from another Teleport (`kin_spacing`; only
  when the last fifth of the tries finds nothing may that close to 30 m). The weighted draw keeps its count (9) without
  the Teleport, so the other kinds fill its old slot (two extra weighted picks instead of one).
- **Teleport landing**: the hero never comes out within 15 m of any Teleport (`land_clear`) nor within 2 m of the water
  (`land_water`), on top of the old rules (at least 0.6 of the arena's radius from where he stood, 1.5 m clear of the
  rocks, inside 0.82 of the arena's radius, where the crowd is thinnest of 40 spots tried).

### 32.TOOLS The Timeline's pan; the Watch's run setup, build icons, sound, the bot's goal

#### The bot and the power-ups (game/tools/bot/BotGoals.gd PU_*, Bot.gd)
Garry: "Bot should also sometimes strive to pick up pick-up power-ups. Right now it feels like he is ignoring them."
- A power-up lying is a goal candidate from **28 m** (`PU_SEE`; pass 80's `POWERUP_SEE` 18 m), within the far limit as
  before (a heart from 28 m whatever the far limit).
- Its worth now (`powerup_value`, replaces pass 80's flat `V_POWERUP` table, which stays for reference):
  heart **130 x (1 - health)** below **85%** health (none above); vacuum **30 + XP lying on the map / next level's XP x 70**,
  at most **120**; nuke **28 + 3 a creature within 8 m**, at most **90**; buff (rage, sprint) **32 + 30 x fight**; shield
  **30 + 30 x max(fight, 1 - health)**; gold **20**; any other **15**. fight = creatures within **8 m** (`PU_CROWD_R`) / **8**,
  at most 1.
- The run's taste x the spell's mood for power-ups is floored at **0.85** (`PU_TASTE_FLOOR`; other kinds keep 0.6..1.4 x
  0.7..1.3). Jitter, distance (/ (1 + d / 18)) and the other goals still decide: "sometimes, not always".
- Commit: within **5 m** (`PU_GRAB`; other goals 2.5 m) of a power-up goal the kite's hold never wins: he takes it.
- The XP lying on the map is now also counted while a vacuum power-up lies within 28 m (it was only for a standing Uber
  Magnet).
- Measured (tools/dl/p85/TOOLS/sim_before_keep vs sim_after_keep: 16 Drifter runs, a quarter board, 15:00, Down! = keep,
  seeds 1..16, explorer bot): power-ups taken **13.3 -> 32.5** a run (2.4x; 28% of the 115 a run that lay on the map),
  power-up goals **12.6 -> 46.3**, falls **11.4 -> 10.3**, level at 10:00 **32.9 -> 35.6**, at 15:00 **39.3 -> 43.3**, kills
  **5,995 -> 7,236**.

#### The Watch (game/tools/watch)
- The sound is **off** by default (watch.py `--sound` turns it on; the pop-up's Sound box; M in the window).
- The window opens with the **Hero Settings** pop-up (unless `--go`/`--autoquit`). Start Run starts the run the way the
  game does (the spawn beam; the bot does nothing until he lands). A random seed is drawn at every Start Run when Random
  is ticked.
- **Restart run** (header button, R): the run is held paused behind the pop-up; Start Run ends it (recorded as a tool run,
  with its decision log) and the new run starts two frames after that game is gone; Cancel goes back to it as it was.
- The charts' grey line for a run from the pop-up: the command line's Sim result while hero, board and map are the ones
  it was found for, else the newest finished Sim result of the same hero, board and map (setup.json refs), else none.
- The goal plaque: a new goal shows after it has held **0.35 s** of wall time (no flicker as the kite flips), fading in
  over **0.3 s**; it sits at the phone view's bottom middle, above the speed badge.

#### The Level Editor
- Timeline: holding the right mouse button inside the Spawn rows section (its lanes and labels) and dragging pans the
  view both ways; no context menu there (nor for 0.4 s after a pan); it never selects or moves a bar.

### 32.BANDIT The Spit Cactus's Dynamite Bandit look and his dynamite

**The Spit Cactus's dynamite** (content/enemies/spit_cactus `ranged`, EnemyManager._throw_dynamite,
ProjectileManager.hostile_dynamite; Garry: "Throw Dynamite Sticks instead of Cactus things - and they explode like the
Player's ones, after a 1 second delay ... they can fly faster ... aim a little in front of the Player (not like the
Harpooner) ... The throw should be in place ... always red and will still pulsate"):
- `ranged.shot: "dynamite"`: every lob of the kite brain is a stick of dynamite (the old spit is gone for every look of
  the cactus; the cactus look SC-0 throws it too).
- Wind-up: `telegraph` 0.7 s (unchanged) standing still, no ring while he winds up (the raised arm is the tell); the
  stick leaves his hand at the end of it from `dynamite.hand` {up 1.3, side 0.25, forward 0.1} m.
- Release hold: `release_hold` 0.35 s (x 1/pace) standing in the release pose, then he walks again.
- Aim: the hero's feet + `lead` 0.35 x his flat velocity x the stick's flight time (flat distance / speed, 0.4..2.0 s,
  on the creatures' clock), at most `lead_max` 2.5 m. A standing hero is aimed at his feet. (The harpooner leads with
  the whole velocity over the flight and half the wind-up.)
- Flight: `speed` 9.0 m/s (the spit flew at 5.4), the spit's arc, tumbling; the hero's red stick model at `scale` 0.6
  (0.52 m long), its halo counted from `halo_r` 0.2 m; harmless in the air (land_only); the cactus's
  `pulse` kept, its colour now red #FF2A1F; its `trail` now a faint smoke grey #6B625C (was green).
- The red ring: on the landing spot, the blast's radius, from the throw until the blast (flight + fuse).
- Fuse: lies `fuse` 1.0 s on the creatures' clock (High Noon and the pace stretch it), the hero's spark lit until
  `out_before` 0.5 s before the blast.
- Blast: radius `blast.radius` 2.0 m (the spit's splash was 1.2); the hero takes the creature's damage (unchanged:
  base 8 x the stage, curve and level multipliers) when he stands within radius + 0.4 m, and is thrown back
  `blast.knockback` 7 with `blast.lift` 2 unless he evaded; the crowd within 1.2 x the radius is thrown by
  `blast.push` 10 (no damage: throw_radius); the look and sound of the hero's Dynamite Stick blast (burst in
  #FFB34D, ground ring, camera kick 0.5, w_lob_boom).
- Sounds: the throw is w_lob_throw (was en_cactus_spit), the death en_goblin_die (was en_cactus_die).
- Difficulty probe (quarter board): see the lane report / history_BANDIT.md.

### 32.LEAD The lead's notes in this pass

- **Garry's map edits re-pinned** (2026-10-17: the hard cap 300, a flat stage-1 cap, no cap rushes in stages 2-3):
  pass332 and pass62_pc read his map (a positive cap all through every stage; the hard cap at least cap_max).
- **More structures**: the Teleports (3, 4 a third of the time) now come on top of the map's weighted structures count
  (9), so a map holds about 12-13 structures plus the Totem Poles (32.WORLD); Garry tunes the count in the Level Editor.
- **The puppet's hand finder**: lane FADE wrapped tools/puppet_blender.py's rig in tools/dl/p85/FADE/rig_fix.py (the
  hand tip = the farthest vertex near the forearm's line); folding it into the tool is open.

## 33. Pass 86 (v0.72): the Dynamite Bandit hops and grows

Garry (2026-10-17): "Make the Cactus jump up a little bit when he throws the Dynamite stick. Make em a bit bigger".
- **The hop**: through the release hold (`ranged.release_hold` 0.35 s) a thrower with `ranged.throw_jump` rises on a sine
  to that many metres and lands as the hold ends (EnemyManager._throw_hold_tick; never while launched or thrown).
  The Spit Cactus: `throw_jump` **0.45 m**.
- **Bigger**: the Spit Cactus `size` 1.5 -> **1.85** (+23%) and its body `radius` 0.45 -> **0.55** with it (so rounds
  still hit where he is drawn).

## 34. Pass 87 (v0.73): stages separated, Endless, stage looks, the Big Mouth, new looks, evade, black barrels

Garry's request (2026-10-17, tools/dl/p87/REQUEST.md, REQUEST_STAGES.md). Each lane's rules as it wrote them.

### 34.SGAME Stages as their own runs: windows, the portal's timer, Endless, unlocks

Garry (2026-10-17): "Now Player Unlocks Stages and is only able to enter them after having completed the previous one.
They differ in how long it takes to complete them as well." His answers: a stage picked from the menu is a fresh run;
lengths 7:10 / 10:00 / 13:00; the Stages menu opens on every Play once stage 1 is beaten; a death in Endless banks
everything.

**The windows.** The map keeps one timeline on the run clock (rows, events, curves as before); `timeline_data.stage_list`
cuts it into windows: stage k starts at the sum of the earlier `length`s. Red Canyon: Sundown 0..430, Nightfall
430..1030, Blood Moon 1030..1810 (WaveTimeline.stage_window). A map without the list keeps `stages` windows of
`stage_length` (the fallback).

**A stage run** (Run.start_stage, the Stages menu's Run.choose_stage, the launch's `stage`, 1-based): a fresh run (level
1, the hero's start weapon, the Upgrade board, nothing taken) whose run clock starts at the window's start. Everything
that reads the run clock reads it there: the stage multiplier of its index, the HP / damage curves, the cap curve, the
roster rows open then (a stage-2 run starts with the rows of 7:10), the path slots from the stage's first.
- What the timeline dated before the window never comes: every event before it, and a boss event on its first second
  (the stage before's boss). An `elite_every` event before it keeps its timer on its own rhythm; a timeline wave
  (`waves`) that began before it keeps its rhythm from the window's start; a "once" row past its second is dropped; a
  waves row fires only its latest wave due (pass 81's jumped-clock rule): Red Canyon's "Elites every" row (301 s, every
  129 s) brings its Elite at a stage-2 run's first second, as it did when stage 2 began after the portal.
- The specials' clock waits for `specials.from` (215 s) in stage 1 only; in a later stage run it runs from the start.
- The clock never passes the window's end: there the stage's boss comes (its boss event; with none, or one whose
  t_jitter moved it past, the boss the entry names, else the boss event at the end; a boss event whose `chance` failed
  means no boss this run); a stage with no boss at all opens its portal where the hero stands.
- The clock shown is the stage's: the HUD, the pause screen and Down! read 0:00 at the stage's start (Run.stage_clock).
- No going on to the next stage: there is no Continue any more (WaveDirector.continue_to_next_stage is gone).

**The boss down.** The stage is beaten (Save.mark_stage_beaten: the next stage unlocks), the boss's chest, the portal
and its one wave as before (portal_wave 12, then nothing), and the portal's countdown: `endless.portal_seconds` (60) on
the run clock. It stands still behind every screen (the level cards, a chest, the pause menu) except the portal dialog,
which keeps it running (Game.tick_portal_countdown). The dialog has only EXTRACT (and "not yet": the portal waits, the
countdown runs on). EXTRACT ends the run (extracted). At 0 the portal closes (its dialog too) and Endless starts.

**Endless** (WaveTimeline.endless block; a stage entry's own `endless` block wins key by key):
- A wave every `every` (10) s of Endless's own clock (the run clock stays at the window's end): wave 1 = `first_wave`
  (120) creatures, wave k >= 2 = `wave_size` (30) + `wave_growth` (2) x (k - 2), in packs of their row's pack (1..12)
  from all round the hero, past the live cap (the hard cap 300 holds).
- Between the waves the crowd is kept up to `cap` (1.0) x the stage-end cap, a burst (burst_min..burst_max) a spawn check.
- The creatures: the stage's late roster (the mix rows open in its last `roster_window` (60) s, at their weight there).
  Each wave fixes each row's numbers afresh: the row's own HP / damage curve value at its start and the hero's level at
  its first creature in the wave, times the wave's multipliers: HP x `hp` (1.5) x (1 + `hp_growth` (0.15))^(k-1) and
  damage x `atk` (1.2) x (1 + `atk_growth` (0.1))^(k-1), both COMPOUNDING; speed x `speed` (1.15) x (1 + `speed_growth`
  (0.02) x (k-1)), LINEAR, at most `speed_max` (1.6), fixed per creature at its spawn.
- No bosses, Elites or specials in Endless (the old endless's boss a stage and Elite every 0.15 stage are gone).
- A kill's XP is `xp_share` (0.35) of what it would drop (its gems, Prospector's, Eureka's); a creature's coin roll
  happens only `coin_chance` (0.05) of the time. Power-ups and creature chests drop as before.
- It goes until the hero falls; a death banks the purse as every end does (pass 70).

**Unlocks** (Save.stages_beaten {map: [bool]}): stage 1 always open; stage i once stage i-1 is beaten; the Stages menu
opens on Play once stage 1 is beaten. A save from before (once, "stages_migrated"): a stage counts as beaten when the
save holds the stage's "boss_<map>_<k>" flag or a kill of the stage's boss in its totals (King: stage 1, Gila: stage 2,
Brander: stage 3).

**What reads time now.** "Survive N minutes" quests count every second of the run played (Run.run_time: the stage's
clock, its boss fight, the portal countdown and Endless); the no-lift quest the stage's clock; the quest check runs
every 5 s of run_time; the Collection's stage hint for a survive quest is the first stage at least that long (else the
last). The best time (best_runs.time) and Results' time are run_time (an old save's best time, its run clock up to
21:30 and more, stays as it was). The boss DPS window (pass 72's "dps" mode) spans at most the run's own seconds.
Analytics: a "not yet" at the portal records portal_wait only (the "portal" event, PostHog's stage_cleared, is EXTRACT
now); Endless's start records an "endless" event (lane STOOLS maps it).

**Red Canyon migrated** (tools/dl/p87/SGAME/migrate_stages.py, backup red_canyon.pre87.json): stage 1 untouched; every
time of stage 2 (430..860) stretched x600/430 into 430..1030 and of stage 3 (860..1290) x780/430 into 1030..1810 (a
time within 1 s of a window's start keeps its offset, a 1-second step stays one): rows' t / until / weights, events,
weight_late_t (1030), the damage curve's points, the cap curve (points added at the old boundaries first, so stage 1's cap
is unchanged: [[0,200],[430,233.3],[1030,266.7],[1810,300]]), path_times of stages 2 and 3 (x600/430, x780/430). The
HP curve stays in "formula" mode on the run clock (a formula cannot be stretched): stage 2 now reads it to x3.42 at its
end (was x2.99) and stage 3 to x5.56 (was x4.11); its points block is the formula at the new stage marks. Lane TUNE
retunes stages 2-3 for a fresh hero.

### 34.TUNE Stages 2 and 3 for a fresh hero; Endless tuned

Garry: "Stages 2 and 3 retuned so a fresh hero can clear them, clearly harder than Stage 1" (a stage picked from the
Stages menu is a fresh run: level 1, the hero's start weapon). All numbers are in
`game/content/maps/red_canyon/red_canyon.json` `timeline_data` (the Level Editor edits every one of them); no code.

#### What stays

- Garry's stage 1 (0..430 s): every row, event, cap point, the ATK x points up to and including [430, 1.21], the HP
  curve (the power formula, pinned by pass62_pc_test through 7:10).
- `stage_mults` [1, 2.2, 3.34]: still the stages' multiplier on HP, ATK and the coins' worth (a coin pays
  x round(stage mult): stage 2 x2, stage 3 x3 as before). Lowering them would have cut stage 2's and 3's pay in half
  and a third; the fresh-hero numbers are made with the knobs below instead.
- The HP curve (formula, run clock): stage 2 reads it from 1.94 to 3.42, stage 3 from 3.42 to 5.56; the rows' HP x
  below absorb it.

#### The rules (new numbers)

1. **Stage-2 / stage-3 rows' HP x** (`roster[].stats.hp_mult`, every row and once-row starting in the window; the
   "Elites every" row draws its numbers from the rows): the migrated number (pass 62/64's and Garry's 2026-10-16 edits,
   kept in tools/dl/p87/TUNE/backup/red_canyon.migrated.json) x a factor that ramps linearly with the row's start
   through its window: **stage 2 x0.26 at 7:10 -> x1.4 at 17:10**, **stage 3 x0.30 at 17:10 -> x0.60 at 30:10**
   (2 decimals). What a creature of the rows carries on average (tools/dl/p87/TUNE/est.py, before the hero-level
   factor, which is the same in every stage): stage 1 HP 16 at 0:30 -> 57 at its end, ATK 4.5-6.3; stage 2 HP 45 ->
   262, ATK 7.3 -> 12.2; stage 3 HP 31 -> 279, ATK 6.4 -> 15.1 (before this lane: stage 2 HP 173 -> 254, ATK 27 -> 21;
   stage 3 HP 102 -> 558, ATK 35 -> 40, made for a hero arriving at level 22 / 33). Per row (stage 2): r18 / r19 / r20 0.26,
   r22 0.54, r23 0.67, r24 1.34, r25 / r26 0.71, r27 0.77, r28 0.80, r8 0.57, r29 1.48, r30 / r31 1.64, r51 1.66,
   r32 0.85, r9 1.84; (stage 3) r10 / r35 / r36 0.12, r37 / r38 0.15, r11 0.17, r39 0.23, r40 / r41 / r42 0.32, r43 0.37,
   r17 0.43, r33 / r34 0.46, r53 0.54, r44 / r45 0.70, r46 / r47 / r48 / r50 / r52 0.75, r49 0.30.
2. **ATK x curve after 7:10** (`damage_curve.points`): [430, 0.36], [900, 0.95], [1030, 0.80] | [1030, 0.28],
   [1700, 0.72], [1810, 0.56]. With the stage multiplier: stage 2's bites x0.79 at its start (stage 1: x1.21; stage 2's
   creatures bite 2-3x harder by nature: fire ants 8, slimes 7 against skeletons' 3) rising to x2.09 at 900 s (7:50
   into the stage); stage 3's x0.94 rising to x2.4 at 1700 s (11:10 into it). The last point of each window is the boss's own (a boss reads the live curve at the
   frozen clock): the Gila fights at x1.76 (was 3.06), the Brander at x1.87 (was 5.28); the rows starting after the knee
   keep the knee's value. Rows read the curve at their own start (pass 58), so the knee shapes the late rows, the end
   point only the boss (and anything spawned at the boss's second).
3. **r18** (blue slimes) starts at 431 instead of 430: a row starting on the boundary second read stage 1's side of the
   7:10 steps (ATK x 1.21 instead of stage 2's 0.36); stage 2's other openers start at 431 already.
4. **A soft start in each window** (`cap_curve`): [431, 25] then back on Garry's line at [670, 246.7] (stage 2) and
   [1031, 35] -> [1230, 275.2] (stage 3); the cap_max 150 still holds, so the live cap climbs from 25 to 150 in about
   two minutes (stage 2) and from 35 in about a minute and a half (stage 3), as stage 1's paced waves let the crowd
   build. The boss seconds (430, 1030) keep their old values (the King's and the Gila's fights read the cap there).
   The hell channel (stage 3, 0.4 of the cap) follows.
5. **The Elites** (elite_boss events, 5:00 into stages 2 and 3): HP x 0.8 (730 s, was 0.94) and 0.45 (1420 s, was 1.33).
   An Elite by its kind is elite.hp_mult_per_stage^stage x the stage multiplier x creature_hp_mult: a stage-2 stone golem
   ~2,140 HP, a stage-3 one ~3,290, against a fresh hero at level ~18-24 there.
6. **The bosses' data-HP floor** (boss events' `stats.hp_mult`, new on these events): Gila Grande x0.3 (floor 3,168 HP,
   was 10,560), the Brander x0.15 (floor 10,900, was 72,678). The seconds mode (pass 83: 40 s / 60 s of the hero's full
   DPS) rules as it does for the King; the old floors, made for a level-33/43 hero, held a weak fresh build's Brander at
   72,678 HP (2 to 10 minutes of fight in the sims).
7. **Endless** (`endless`, lane SGAME's block): first_wave **60** (was 120), hp **1.15** (1.5), atk **1.0** (1.2; Garry's
   first wave is "higher speed and HP"), speed **1.1** (1.15), hp_growth **0.11** (0.15), atk_growth **0.07** (0.1),
   speed_growth **0.015** (0.02); every 10, wave_size 30, wave_growth 2, cap 1.0, speed_max 1.6, xp_share 0.35,
   coin_chance 0.05, roster_window 60, portal_seconds 60 unchanged. Wave k: HP x1.15 x 1.11^(k-1), ATK x1.07^(k-1),
   speed x1.1 x (1 + 0.015 (k-1)): after 1 minute (wave 7) HP x2.15 / ATK x1.5, after 2 (wave 13) x4.0 / x2.25, after 3
   x7.5 / x3.4, after 4 x14 / x5.1.

#### How it was measured

The run sim (tools/sim_batch.py --stage k, lane STOOLS'), Drifter and Ironwood, the explorer bot (the Sim tab's
default), death=keep (stood up at full health, every fall counted; the first fall in Endless is its "death"), on a
private snapshot (tools/dl/p87/TUNE/sim). The bots are far weaker than a player: with death=end the explorer cleared
stage 1 with a quarter of the board 1 time in 10 and the expert 0 (both fall at ~1:40 to the skeleton knights), while
Garry cleared it at level 30 with a third of the board. So the targets are relative, as pass 64's were: **stage 2 with
a quarter of the board and stage 3 with half about as hard as stage 1 with none** (the stage every first-time player
clears; a bit harder is fine), and **each stage clearly harder than the one before at the same board**. Falls are split
by phase (the stage, the boss fight, the portal, Endless) from the run's phase series. Scripts and runs:
tools/dl/p87/TUNE (table.py builds the table, fallsmin.py the minute profile, est.py the rows' numbers by stage minute,
bake.py writes the numbers).

| sim | stage | hero | board | runs | clean clear | falls in the stage mean (median) | falls a minute | falls in the boss fight | damage taken a minute (x max HP) | under half HP | level 2:00 / 5:00 / end | boss fight s (n) | Endless: first fall s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **before** (migrated numbers) | S2 | drifter | quarter | 10 | 0% | 35.6 (38) | 3.56 | 19.1 | 4.99 | 44% | 2.5 / 7.5 / 16.5 | 128 (4) | - |
| **before** (migrated numbers) | S3 | drifter | half | 10 | 0% | 63.7 (67) | 4.90 | 34.0 | 7.32 | 41% | 3 / 7.5 / 18 | 147 (10) | 9 |
| anchor | S1 | drifter | none | 20 | 0% | 10.1 (9) | 1.41 | 6.0 | 1.80 | 44% | 5 / 10.5 / 17 | 84 (20) | 80 * |
| anchor | S1 | ironwood | none | 20 | 0% | 10.9 (11.5) | 1.53 | 7.5 | 1.94 | 41% | 5 / 9.5 / 15.5 | 125 (20) | 84 * |
| anchor | S1 | drifter | quarter | 10 | 10% | 3.1 (2.5) | 0.43 | 1.8 | 1.36 | 22% | 5 / 11 / 15 | 71 (10) | 28 * |
| anchor | S1 | drifter | half | 10 | 10% | 1.3 (1) | 0.18 | 1.0 | 1.19 | 6% | 5.5 / 11 / 14.5 | 77 (10) | 156 * |
| **after** | S2 | drifter | quarter | 20 | 5% | 9.3 (9.5) | 0.93 | 6.2 | 2.41 | 29% | 6 / 17.5 / 26 | 116 (20) | 68 |
| after (same numbers, seeds 301 again earlier) | S2 | drifter | quarter | 20 | 0% | 8.1 (7.5) | 0.81 | 6.3 | 2.25 | 29% | 6 / 19.5 / 26 | 130 (20) | 62 * |
| **after** | S2 | ironwood | quarter | 20 | 0% | 8.5 (7.5) | 0.85 | 11.9 | 2.60 | 25% | 7.5 / 21 / 28 | 194 (20) | 38 * |
| **after** | S3 | drifter | half | 20 | 5% | 13.4 (8.5) | 1.03 | 4.6 | 2.69 | 20% | 7 / 24.5 / 35.5 | 84 (19) | 38 * |
| after (same numbers, earlier) | S3 | drifter | half | 20 | 10% | 11.3 (4.5) | 0.87 | 3.9 | 2.39 | 19% | 7 / 23 / 40.5 | 93 (20) | 134 * |
| **after** | S3 | ironwood | half | 20 | 0% | 17.9 (15.5) | 1.37 | 5.2 | 3.80 | 24% | 7 / 20 / 35.5 | 132 (19) | 64 * |
| Endless check (seeds 401) | S1 | drifter | quarter | 10 | 10% | 3.3 (3) | 0.46 | 1.6 | 1.40 | 17% | 5 / 13.5 / 19 | 67 (10) | 141 (6 fell; 4 never, 283-327 s played) |
| **after**, Endless check (seeds 401) | S3 | ironwood | half | 10 | 0% | 12.5 (12) | 0.96 | 4.6 | 3.33 | 16% | 8.5 / 18.5 / 36 | 148 (10) | 65 (7 fell; 3 never, 153-260 s played) |
| harder than S1 at the same board | S2 | drifter | none | 10 | 0% | 24.3 (25.5) | 2.43 | 15.6 | 3.18 | 46% | 6.5 / 18 / 24 | 104 (4) | - |
| harder than S2 at the same board | S3 | drifter | quarter | 10 | 0% | 31.0 (30) | 2.38 | 5.5 | 4.37 | 38% | 5.5 / 17 / 28.5 | 96 (9) | - |

\* Endless measured with an earlier set of its keys (before rule 7's final numbers): SGAME's defaults for the "before"
rows and the S1 @ quarter / half anchors, then 1.0 / 0.12 / 0.08 (S1 @ none Drifter), 1.25-1.2 first wave x90-80 (the
others). "clean clear" = no fall at all before the boss died (what death=end counts); the bot rarely manages it even on
stage 1.

**Reading it.** Falls before the boss died (stage + boss fight), the two heroes averaged: stage 1 with no board 17.3 (16.1 / 18.4);
**stage 2 with a quarter 14.4-20.4 (mean 17.7)**; **stage 3 with half 15.2-23.1 (mean 19.9)**: each about stage 1's
first-time difficulty, stage 3 a little above it. At the same board each stage is far harder than the one before:
stage 2 with no board 40 falls (and only 4 of 10 had beaten the Gila by the
run's limit) against stage 1's 16-18; stage 3 with a quarter 36.5 against stage 2's 15.5. Time under
pressure follows: the damage taken a minute rises stage by stage at the intended boards (1.8-1.9 / 2.3-2.6 / 2.4-3.8 x
max HP), and each stage's profile has stage 1's shape (a calm first minute, the worst in its last third: stage 2 2.8-4.2
x max HP a minute in its last four minutes, stage 3 3.7-6.2 in its last three). The fresh hero levels faster than in stage
1 (stage 2's creatures drop 1.6-2.7x the XP of stage 1's): level ~6 at 2:00, ~18-20 at 5:00, ~26-28 at the Gila and
~35 at the Brander (stage 1: 5 / 10 / 16).

**The bosses.** The Gila's fight is the longest part of stage 2 (116-194 s in the sims; 40 s of full DPS by Garry's rule)
and about as deadly a second as the King's at no board; Ironwood (the spear, kited by the bot) has it hardest. The
Brander fights 84-132 s.

**Endless** (target: a typical hero dies within a few minutes; with the bot so much weaker than a player, who clears
a stage 1 the bot falls ten times in, the target in bot terms is a median first fall of about 1-3 minutes). With the
final keys (rule 7), the median first fall counting the runs that never fell: **after stage 1 with a quarter ~3 min**
(181 s), **after stage 2 with a quarter ~1.1 min** (68 s), **after stage 3 with half ~1.6 min** (96 s). Before (SGAME's
defaults: 120 at x1.5 HP, x1.2 ATK, +15% / +10% a wave) a third of the stage-2 heroes fell inside the first wave's 15 s
and the median was 47 s. A hero ends stage 2 at his limit (its last minutes take 3-4x his max HP a minute), so Endless
after stage 2 is the quickest; a stage's own `endless` block (stage_list[k].endless, lane SGAME's) can make one stage's
Endless gentler without touching the others. The slow brutes and spitters of the late roster (hammer giants, bull
beetles, spit cacti) do most of the killing: Endless's waves do not respect a row's max_alive (lane SGAME's rule), so
they pile up.

#### Where to nudge (in the Level Editor)

- A stage too hard / too soft overall: its rows' HP x together (the factor's two ends), or the ATK x knee.
- Its opening (the first two minutes decide a fresh run: a hero who falls behind early never levels out of it): the
  first ATK x point (0.36 / 0.28) and the cap's soft start (25 / 35). +30% HP and ATK on stage 3 took its falls from 4 to
  14 a run in one step; move a tenth at a time.
- The Gila / the Brander: their ATK x end points (0.80 / 0.56); their HP is Garry's 40 s / 60 s of full DPS.
- Endless: first_wave and hp for its opening; hp_growth / atk_growth for how long a strong hero lasts.

### 34.SUI The Stages menu, the portal's countdown, Endless on screen

Rules the screens follow (numbers are UI constants in the named files, not balance):

- **PLAY on the title** opens the Stages menu once stage 1 of the shown map is beaten (`Save.stages_menu_open`, and the
  map has more than one stage); before that PLAY starts stage 1 as always (`Run.choose_stage(0)`). The menu opens on
  every PLAY after that (Garry). ui/TitleScreen.gd `_on_play`.
- **The Stages menu** (ui/StagesScreen.gd): one card per entry of the map's `stage_list` (WaveTimeline.stage_entry). A
  card is open when `Save.stage_unlocked(map, i)` (stage 1 always; stage i once stage i-1 is beaten). An open card's
  tap starts that stage at once as a fresh run with the hero chosen on the title (`Run.choose_stage(i)`, Game.tscn). A
  locked card is aged, its picture under an ink wash at 62 % with a padlock, its line "To unlock: Beat <the boss of the
  stage before>"; a tap plays the locked sound, shakes the card (14 px, 0.32 s) and starts nothing. A beaten stage wears
  a sage BEATEN stamp.
- **The difficulty line's colour**: sage for the first stage, rock for the last stage and every `hell` stage, brass
  between (StagesScreen.tone).
- **The picture**: the entry's `shot` if it exists, else `art/ui/stages/<map>_s<k>.jpg`, covering a 972 x 374 box
  (2.6 : 1); striped placeholder until the file exists.
- **PLAY AGAIN** on the Results replays the same stage (`Run.choose_stage(Run.stage)`); Main Menu -> PLAY opens the menu.
- **The stage clear** (ui/PortalDialog.gd): one road, EXTRACT (the run's gold banked), and the Endless card counting
  down from the game's portal timer (`Game.portal_seconds_left`, whole seconds rounded up); the count turns rock and
  swells once a second in its last 10 s (ENDLESS_WARN). While the dialog is up it keeps the game's countdown running
  (`Game.tick_portal_countdown`, lane SGAME: the run is paused behind it); at 0 the game starts Endless and closes it.
  NOT YET / Esc / back close it with no decision, the countdown goes on. The Endless card's line takes the wave interval
  from the map (`endless.every`, the stage's own first).
- **The HUD's clock plate** (ui/HUD.gd `_tick_stage_clock`): paper with the stage's own clock (`Run.stage_clock`, 00:00
  at the stage's start) in play; rock with the seconds left and an ENDLESS IN tag hanging under it while the portal
  counts down (the tag swells each second of the last 10); ink with the time survived in Endless (`Run.endless_time`)
  and a WAVE n tag (rock) in Endless, the tag swelling on each new wave. The ENDLESS banner (rock) shows once as Endless
  starts. No toast per wave.
- **The Results' head** (ui/ResultsScreen.gd `stage_story`): the star line says Extracted (extracted), Fell in Endless
  (died in Endless) or Run over (anything else, a quit too); under it "STAGE k · <name> · BEATEN" in the stage's colour
  (BEATEN once its boss died: `Run.stage_beaten`, or extracted, or in Endless); the big time is the run's time
  (`Run.run_time`, as the best runs count it); an Endless line "Endless mm:ss · wave n" in rock when Endless ran.

### 34.SLOOK Nightfall and the Blood Moon; the stage pictures

- **A stage's filter** (`timeline_data.stage_list[k].filter`, StageLook): the world is drawn x white.lerp(`color`,
  `strength`) per channel on the screen (a coloured glass: 0 = none, the quads not drawn). The creatures, the hero,
  power-ups and flowers take `actors` x the strength (default **0.35**, `StageLook.ACTORS_DEFAULT`), so they stay brighter
  than the ground.
- **Not tinted** (drawn on top of the filter, so they read on any stage): every ground mark (telegraph rings, discs,
  lines, cones, spills, scorches, the Salt's patches, the structures' rings), ground shadows, gems, coins and glints,
  the outlines of creatures behind scenery, every effect, tracer and projectile, badges, damage numbers, the HUD and all
  screens. Tinted with the world: the sand, the water, the sky, props, structures, barrels, signs, the fort wall, the
  cliffs, lit 3D (weapon models, tumbleweeds), the dust gusts and the dust devil (now drawn before the filter:
  render priority -8, was 2 / 0).
- **Red Canyon** (tuned by eye on the phone's canvas, side by side; tools/dl/p87/SLOOK/read*_s*.png):
  - Stage 1 "Sundown": none (strength 0), as before.
  - Stage 2 "Nightfall": **#3D55C8 at 0.48** (the sand a slate blue-grey, about 0.63 / 0.68 / 0.89 of its red / green /
    blue), creatures at 0.35 of it.
  - Stage 3 "Blood Moon": **#6A1A28 at 0.6** over pass 43's hell ground (a dark crimson, about 0.65 / 0.46 / 0.49);
    a dark red reads the red warnings by brightness: a bright red filter (SGAME's first #B0303A 0.3, or #B02A2A 0.35)
    flattened the filled danger disc into the ground.
- **Hell** now comes from the stage's `hell` (true for Red Canyon's stage 3); a map without a stage list keeps pass 43's
  rule (the third stage on). The look is there at once when a stage run starts (no 3 s fade: a run is one stage now);
  a later change (the old flow) fades over 3 s.
- Cost: two fullscreen multiply quads (one draw each) only on a stage with a filter; nothing on stage 1. perf_late
  (504 x 1122, 60 fps, the stage-3 crowd, this PC): within noise with and without (GPU 0.52-0.75 ms either way, frame
  10.1-11.8 ms either way, +2 draw calls).
- The debug arena's WORLD tab: "Stage look" shows each stage's look on the spot (a run shows its own stage's).

### 34.STOOLS Stages in the Level Editor, the Sim, the Watch and the analytics

No game number changed in this lane; these are the rules of the Level Editor, the estimate, the Sim, the Watch and the
analytics, so they are not surprises.

#### The Level Editor's stage edits (tools/level_editor/stage_model.js)
- **A stage's length changed**: the later stages' windows move by the difference, and every time in them moves with
  them (rows' starts, ends and presence keyframes; the old waves; events; the cap, floor, HP and ATK curves' points;
  specials' `from`). The stage's own things: **Keep its times** (growing: its rows that ran to its old end run to the
  new end; shrinking: what starts past the new end is cut, ends past it come back to it, keyframes and curve points past
  it drop; the confirm names what is cut) or **Stretch** (its own times scale by new / old length from its start, rounded
  to 0.1 s; nothing is cut: the rule lane SGAME's migration used). The boss at its end goes with the end. Mutation
  offers (`path_times`) are seconds into a stage, so they never move.
- **+ Stage**: a copy of the last stage's settings (its length, boss, filter, hell; a new id `s<n>` and the name
  "Stage n"; no words), its boss event at its end (a copy of the last stage's), and the per-stage lists (stage_mults,
  hell_cap, path_times, weapon_cap, passive_cap) one entry longer (a copy of the last stage's) where they had one per
  stage. No rows.
- **Delete stage**: what lies wholly in its window goes (rows, waves, events, its boss); a row or wave spanning into it
  ends at its start (or, starting in it and running past it, starts at its start); keyframes and curve points strictly
  inside it drop (a step at its edges keeps the stage before's last value and the stage after's first); the later
  stages move back by its length; its entry in the per-stage lists goes; a special that came "from stage N" past it
  comes from N - 1. The last remaining stage cannot go. In the last stage, a row starting in it goes even when it has no
  end.
- **The first stage edit on a map without a stage list** writes one from the old windows (stage_length x stages): ids
  s1.., names "Stage k", each boss from its boss event, no filter, `hell` from the third stage (Game.gd's old rule).
- **Checks**: a length under 1 s or an id used twice is an error (blocks Save); no id, a filter colour that is not
  #rrggbb, a strength outside 0..1, or a stage with no boss at its end is a warning.

#### The estimate of a stage run (model.js spawnEstimate opts.stage; its twin in selftest.py)
- The clock starts at the window's start with an empty crowd and the stage's index; only the events inside the window
  play (none before its start, the previous stage's boss at its start left out, none after its end; the stage's boss
  at its end from its entry when no boss event is there); a once row more than 2 s before the start is dropped; the old
  waves[] blocks start no earlier than the window. The kill-rate curve (fitted on runs from 0:00) is read at the seconds
  the fresh hero has played. A window that ends with no boss fight opens its portal there.
- After the boss: the portal's countdown (`endless.portal_seconds`, the stage's own block first, 60) with the director's
  clock held at the window's end (the portal wave, then nothing); then Endless to the view's end: wave 1 (`first_wave`)
  at once, a wave every `every` s (`wave_size` + `wave_growth` x (k - 2)), past the cap and under the hard cap, drawn
  from the late roster (the mix rows open in the last `roster_window` s, by their weight at their last second there) by
  weight; between the waves the crowd kept up to the stage-end cap x `endless.cap` (a burst the mean of burst_min..max
  load at each spawn check); no specials, no own-interval rows, no floor in Endless.
- The "All" tab stitches every stage's run on the clock (each window's points from its own run: the counts start again
  at each window; an earlier stage's run is cut at its window's end, the last one runs on into its portal and Endless).
  The typical hero of the Challenge lane starts at power 1 at each window's start.
- `stageAt` past the run's end is the last stage on a map with a stage list (WaveTimeline.stage_at), and a row's numbers
  are never refixed by the old endless there (`fixedFrom`).

#### The Sim and the Watch
- A sim's `stage` (1-based, default 1) must be one of the map's stages. The bot never extracts (it answers the portal
  "not yet"), so a run goes on into Endless until the stop or its death; result.json's `summary.stage_run` counts the
  boss kills, the outcomes and the median seconds survived in Endless over the runs that reached it (a run the
  sim stopped in Endless counts its seconds so far: a floor, not its end). A run's outcome is Run.outcome() when it
  ended by itself (a death, an extraction); a run the sim stopped says `stopped`, `stopped_after_boss` or
  `stopped_endless`.
- The Watch's Stage row: with Every unlock on (tool mode) every stage may be chosen; off (the save's mode) only stage 1
  and each stage whose stage before the PC save has beaten (its `stages_beaten`; a save the game has not migrated yet:
  its old `boss_<map>_<k>` flags or a kill of the stage's boss in its totals, as Save._migrate_stages). The run's
  sandbox save gets every stage beaten (tool mode) or the PC save's flags.
- The Watch's grey line: the newest Sim of the same hero, board, map and stage; a whole-run Sim from before pass 87
  only for stage 1.

#### Analytics
- A run's `outcome`: Run.outcome() (extracted | died_endless | died_after_boss | died), "quit" for a run left from the
  pause menu or the app (result abandon / quit).
- PostHog's stage of an event (the boards' `STAGE`): its `stage_id`, else "s" + its `stage` (an event from before
  pass 87: the stage the run was in). The dashboard files a run from before pass 87 under the stage it ended in.
- The portal's `choice` is `extract` or `not_yet` (no going on to the next stage).

### 34.BIGMOUTH The Big Mouth without its tongue: the glow, the breath, the punch

- **Big Mouth wind-up** (`params.beam.windup.seconds`, 0.24 s on the Big Mouth and the Loudmouth; it was a fixed 0.12 s):
  each beam pours at the end of its wind-up. The cooldown clock starts at the pull (as before), so the wind-up is
  taken from the cooldown: the time between beams is unchanged (3.2 s at level 1), the first damage tick comes 0.24 s
  after the pull instead of 0.12 s. Damage, duration, tick and range are untouched.
- **A pull while the beam still pours** (a cooldown shorter than the beam: level 5 with cooldown cuts): the beam is
  re-aimed and pours on at once for a fresh `duration`, with a fresh punch, no wind-up (it used to wind up for 0.12 s
  with the old beam still pouring). A pull during a wind-up only re-aims it.
- **The punch** (visual only, `params.beam.punch`): as the beam leaves, the mouth kicks back along its aim `back` m
  (0.36; Loudmouth 0.45), its lips climb `climb` rad (0.2) and it swells by `pop` (0.2), then springs past rest and
  settles: amp x e^(-7.5 t) x cos(2 pi 2.8 t), gone in about 0.6 s. Every pulse while it pours (0.28 s) kicks again at
  `pulse` (0.3) of that; a kick on a mouth still settling adds half of what is left, 1.6 at most. The beam's line
  starts at the lips where they are, so the damage line moves with the punch by at most 0.36 m (0.45).
- **The throat glow** (visual only, `params.beam.throat`): 0 at rest; through the wind-up 0.2 + 0.6 f^2 (f = how far
  into it); 1 while it pours (a flicker of +-7%); it dies in about 0.1 s after. The flare fades as the mouth turns its
  back on the camera (dot of its facing and the camera direction, from -0.35 to 0.25).
- The beam's flash bursts sit 0.6 m and 0.9 m out along the line (were 0.25 m and 0.45 m) and the pulse's puff 0.7 m
  (was 0.3 m), so the lips, the throat and the punch show through them.

### 34.SOL Solenne on the Puppet method, catwalking (SOL-F, SOL-G)

No game rule changed: no game code, no number. Solenne gained two art looks, SOL-F (precise words) and SOL-G (loose
words), both `fresh: true`; her played look stays SOL-B (`variant`) until Garry picks.

Art-pipeline facts worth a line in the Puppet method's section (§13 / pass 71):
- **A walk clip other than the run**: the Puppet method takes any Mixamo clip (`puppet.clip`, `--clip
  catwalk_walking.fbx`): retargeted whole (36 frames, one stride), guides named `<hero>_puppet_catwalk_walking`
  (+ `_depth`), silhouette run/idle medians front 1.026, fd 0.969, side 0.941, bd 0.939, back 0.960.
- **The shoulder finder and a high collar**: puppet_blender.find_joints takes the shoulders' top as the first slab
  below the neck 1.6x the neck's width; Solenne's flared catsuit collar is that slab, so the arm roots landed at the
  collar's tips (x +-0.06 m on a body 0.20 m wide). Fixed for her by tools/dl/p87/SOL/rig_fix.py: the shoulder joint on
  the straight A-pose arm's own axis, an arm's radius below where the shoulder's round top pulls the body's edge in
  (+-0.087 m at 1.093 m), the elbow half way to the wrist. Not changed in puppet_blender.py (not this lane's file): a
  candidate for the lead, with pass 85's hand fix.
- **The far arm in the side view**: with the game's camera 25 degrees above, the far arm's hand (behind her on the back
  swing, in front on the forward swing) projects up to her upper chest; Wan Animate painted it as a hand at the back
  of her neck. tools/dl/p87/SOL/far_arm.py drops the far elbow, wrist and hand from the side guide in the frames where
  the far wrist sits above the middle of the torso (14 of 25 frames) -> `<guides>_farhide`, used for the side only.
- **Depth on glossy black**: Wan Fun Control on the depth guide painted a black glossy reflection pooled under her
  feet in every frame of the three-quarter back walk (SOL-F's first bd); the stick figure did not. Both looks walk only
  the back on depth (`puppet.depth_views ["back"]`), the rest on the stick figure (whose face points carry the face's
  direction).
- **Repainted stills, her own kept**: `puppet.stills "repaint"` with `still_keys` keeping her front, back, cheer, death
  and front/back hurts: only side, fd, bd and their hurts are the look's own (`solenne_f_*`, `solenne_g_*`), painted
  as 4 candidates on gen_art's own view prompts plus the look's words and picked by eye (tools/dl/p87/SOL/still_cands.py).

### 34.FADE Fadeaway fixed (FAD-E, FAD-F)

No game rule changed: no game code, no gameplay number. Fadeaway gained two art looks, FAD-E and FAD-F (`variants`,
`fresh: true`); his played look stays FAD-C (`variant`) until Garry picks.

Art-pipeline facts worth a line (§13 / the Puppet method's notes):
- **One size across the animations is the body's, not the box's.** A run frame with bent knees and a foot toward the
  camera stands lower for the same body: FAD-D's front run stood at 0.99 of its stand's height with its head 1.12-1.18x
  the stand's. The measure that sees it: the head's width (the widest row, alpha over half, in the top 23 px of the
  figure) or the standing head template-matched in each frame. FAD-E and FAD-F's runs: head within 1-2 % of the stand in
  every view; their median boxes then stand at 0.86-0.95 of the stand (the run crouches). pass87_FADE_test pins: run
  head within 5 %, run median box at most 5 % over the stand, the hit's box within 5 %.
- **Sizes per view** (recipe `run_scale`, multiplied on the puppet's `run_fit`): FAD-E front 0.885, fd 0.905, side
  0.905, bd 0.91, back 0.915; FAD-F front 0.91, fd 0.895, side 0.905, bd 0.93, back 0.88.
- **The puppet guide's neck** (tools/puppet.py guides): the puppet's Neck bone sits 0.18 of the torso above the shoulder
  line in the back views (an inverted V: sagging, slouched shoulders) and the running puppet's face only 0.13 torso
  above the shoulders in the front (a sunk head that inflates the fitted body). Fixed for Fadeaway in a copy of the
  guide (tools/dl/drivers/fadeaway_puppet_run_up, by tools/dl/p87/FADE/driver_fix.py): neck on the shoulder line +
  0.03 torso; face lifted to front/fd nose 0.29, side ears 0.36, bd ears 0.50, back ears 0.56 torso above the shoulder
  line. Not fixed in puppet.py itself (not this lane's file): every puppet look (MAY-P/Q/R, SOL's new ones, FAD-D)
  shares the cause; a candidate for the lead.
- **The back-diagonal's 88**: gen_art paints the bd still from the front still only, with no back words, so a back
  print never reaches it; a look that needs one paints bd from the front and the back still and names it in
  `still_keys.bd`. The Running clip also swings the bd shoulder line from square (0.113 of the frame) to edge-on
  (0.019) and the near arm's backswing crosses the back: the guide's bd shoulder width is held at 0.08 + 0.2 x (w -
  mean) (0.069-0.088) and its elbow and wrist kept at least 0.6 of the half shoulder width out on their own side.
- **Negative prompts take plain nouns**: the hero's `anim_negative` "no basketball, no extra arms ..." reads as a double
  negative; FAD-F's first back walk painted a ball in his hand. FAD-E/F say "a basketball, a ball in his hands, ...".
  Fadeaway's top-level anim_negative (FAD-B/C/D) still says "no ...": left as it was (Garry's looks).

### 34.MUMMY Four new mummies (DM-F..DM-I)

No gameplay number changed: the Dust Mummy's stats (hp 60, speed 0.85, damage 14, ...) are untouched and DM-0 stays the
look the game plays. The four new looks are art only (dust_mummy `variants`, all `fresh`); what they carry that a
player could notice once Garry picks one:

- Walk cadence per look (`fps.run`, from the recipe's `run_fps`; EnemyManager scales it by the creature's pace as for
  every creature): DM-F 10 (a slow shuffle), DM-G 15, DM-H 15, DM-I 12. The ground speed is the creature's own (0.85)
  whichever look plays.
- Death per look (`fps.die` in brackets): DM-F and DM-I fall on their backs (first-last-frame clips, 8 frames [12];
  the Falling Back Death driver was tried for DM-F and failed on the raised arms), DM-G falls back and rolls onto its
  face (clip, 8 frames [12], `anim_seed` 1), DM-H unravels into a heap of bandages (`death: collapse`: the painting
  drops apart in slices into the painted heap, 5 frames [8]).
- The look's size in the cell is the painting's (cell_fill 0.86 default); the creature's `size` 1.9 is unchanged.

### 34.FIXES The bandit's facing, the evade, the black barrels' coins

#### The Dynamite Bandit's facing (no numbers)
- The Spit Cactus's look SC-A: `variants.SC-A.back_faces: "left"` (its back walk, stand and throw were painted from
  Garry's back figure, which turns up-left: the back wind-up's free fist points left), `front_faces` stays "right".
- Rule: a look whose attack strip is painted both ways (`attack_views: "front_back"`) mirrors the attack's back half by
  `back_faces` (it read `front_faces` before), and its hand (`ranged.dynamite.hand.side`, muzzle_point) sits on the back
  set's side there (EnemyManager._face_strip). The Saiga Sniper has no facing keys: unchanged.

#### The evade shows
- An evaded hit's word (the hero's damage numbers, beside BLOCK): **EVADE** (was DODGE), colour **#cdb8ff** (lavender;
  BLOCK stays pale #e8f2ff), same size (PX_WORD 44) and merge window (WORD_MERGE 0.3 s); shown only with the damage
  numbers on, like BLOCK.
- The hero turns see-through: alpha **0.5** (Player.EVADE_GHOST_ALPHA) for **0.7 s** (EVADE_GHOST_HOLD), then a smooth
  ease back to whole by **1.0 s** (EVADE_GHOST_TIME). Another evade restarts the second (never adds up: never under 0.5).
  Cleared when he goes down. The hit blink (invuln) still hides him on its beats; the trampoline flight shows him
  see-through as on the ground. While see-through his legs in an oasis are not drawn under the water (his second pass
  leaves the water's part out) for that second.

#### The black barrels' coins (Garry: "The darker barrels should now give between 1-5 coins")
- "Darker" = the rare **black** barrels (matte black with brass hoops since pass 48; `light` in BarrelField's code, it
  was a light wood before pass 48), not the common brown ones: they are the darker barrels on the sand, and theirs is
  the "random number" (each spot rolls LIGHT_FRAC 0.22).
- BarrelField.COUNT **35** (was 33): the first 33 spots roll LIGHT_FRAC **0.22** as before, the last **2**
  (EXTRA_DARK) are always black. Black barrels a map: 33 x 0.22 + 2 = **9.26** on average (7.26 before).
- A black barrel bursts into **1-5 coins** (COIN_MIN 1, COIN_MAX 5, uniform whole numbers, mean 3), each worth
  **1** (COIN_VALUE; times the stage when taken, like every coin; greed applies), besides its 10 small + 4 medium gems
  (unchanged). Gold source "barrel". Brown barrels: gems only, as before.
- Each black barrel's count is rolled once per map, on the run's seed (BarrelField.coins, its own dice after the
  spots); all black barrels of a map hold 9.26 x 3 = **27.8 coins** on average.
- **The creatures' coins pay it back** (PickupManager.coin_debt, COIN_DEBT_SHARE **0.4**): when the barrels are laid
  out, the run owes the coins all its black barrels hold (BarrelField.coins_total, broken or not). While anything is
  owed, each coin a creature would drop (drops.gold, luck as before, Elites' and bosses' too) goes to the bill 40% of
  the time: the bill takes its value (1-3, x5 for the big ones, before the stage and greed) and it does not drop (the
  last one drops what is left of it once the bill is paid); the other 60% drop as ever. Once paid, the kills drop their
  coins as before. Purses, chests, boss showers, Loose Change, Gold Dust and the rest are untouched.
- What that makes: a run that breaks every black barrel ends with the coins it had before (the kills give the barrels'
  ~28 coins to the barrels); one that breaks none has ~28 coins less; a short run gives up only its share (40% of its
  kills' coins, at most the bill). 0.4 = the bill over a whole stage-1 run's kill coins (27.8 / 71.5 coin gold in the
  sim below, 0.39), so a stage-1 run pays it off about when the stage ends; in stages 2-3 (8x the coins a kill) it is
  paid in the first minute or two.
- Why not a multiplier on drops.gold (the brief's first idea): the creatures' coins a kill grow eightfold after stage 1
  (0.03 gold a kill in stage 1, 0.23-0.27 in stages 2-3, sim below), and with the stages as their own runs (pass 87
  SGAME) a run is 7-13 minutes of one stage: a multiplier fitted to a stage-1 run (about 0.6) would take about 400 gold
  from a stage-2 run and 1,300 from a stage-3 one while the barrels give back 56 / 83; fitted to today's whole 25-minute
  run it is 0.99 (nothing). The bill is capped at what the barrels hold whatever the run.

#### The numbers (run sim, Drifter, explorer bot (breaks the barrels it sees), a quarter board, seed 1, 10 runs each;
#### tools/dl/p87/FIXES/sim_*; the after runs on the same snapshot with only this lane's barrel/pickup code swapped in)
| | before | after |
|---|---|---|
| black barrels a map (expected / in the 10 after maps) | 7.26 | 9.26 / coins held 30.5 a map (18-40) |
| short runs (`--death end`, die at ~2-5 min): kills' coin gold a run | 13.5 (all ten died, 4:05 on average) | 476.9 with one 24-min survivor (4,731); the nine that died (2:00-4:48): 4.2 kill coins + 9.3 barrel gold = 13.5 |
| short runs: the bill paid / the barrels' coins picked up (mean of 10) | - | 10.4 / 11.5 (net about +1) |
| full 25-min runs (`--death keep`): kills | 16,493 | 16,521 |
| full runs: kills' coin gold in stage 1 (0-7:10) | 71.5 (sd 64) | 76.0 (sd 43) |
| full runs: kills' coin gold, whole run | 4,230 | 4,203 |
| full runs: barrel gold | 0 | 36.8 (bot broke 23.5 of 35 barrels; 22.8 of the 30.5 black coins) |
| full runs: the bill paid | - | 30.5 of 30.5 in every run (all paid) |
| full runs: all gold | 24,739 (sd ~7,000) | 23,620 |
- Coins a kill (before): 0.032 gold in stage 1, 0.23 in stage 2, 0.27 in stage 3 (stage multiplier, bigger drops.gold).
- What the sim can and cannot show: a run's kill coins swing 18-214 gold in stage 1 alone (an Elite's coin is x5), so
  ten runs cannot see a 28-coin shift in the totals; the accounting (the runner's P87DEBT line in each player's log,
  snapshot-only instrumentation) shows the rule doing what it says: every full run paid its whole bill (= the coins its
  black barrels held), the nine short runs paid 71 of their 109 would-be kill coins (65%, not 40%: few coins, and an
  Elite's x5 coin goes whole), and the bot's barrels gave back about what it paid
  (+1 short runs, +6 gold full runs: it breaks ~75% of the black barrels, some in later stages where coins count x2-3).
- An earlier after run with the bill taking every coin until paid (sim_after_keep) paid in full too; the 0.4 share was
  chosen so a short run gives up its share instead of all its first coins.

### 34.LEAD The lead's changes in this pass

- **Endless respects a creature's live limit** (lane TUNE found hammer giants, bull beetles and spit cacti piling up in
  Endless): a row whose creature is at its `max_alive` is left out of Endless's draw, and a wave or the fill brings only
  what is left of that limit (WaveDirector `_endless_pick`, `_endless_room`), as the roster's draw does (`_roster_open`).
- **Garry's answers** (2026-10-17): a stage picked from the menu is a fresh run, retuned; lengths 7:10 / 10:00 / 13:00;
  the Stages menu opens on every Play once stage 1 is beaten; a death in Endless banks everything.
- **The Armadillo** item in Garry's message was empty: nothing done.

## 35. Pass 88 (v0.74): the Big Mouth, no hero knockback, played looks, the Stages menu, Stakes

Garry's request (2026-10-18, tools/dl/p88/REQUEST.md). Each lane's rules as it wrote them.

### 35.MOUTH The Big Mouth: one punch, one white glow, a smooth title spin

All visual; no damage, timing or reach changed.

- **The punch comes once** (`params.beam.punch.pulse` 0 on the Big Mouth and the Loudmouth, and the default): the mouth
  kicks back as a beam starts from a shut mouth and settles in about 0.6 s while the beam still pours; the pulses every
  0.28 s only puff at the lips and ring on the sand. A pull while the beam still pours (a cooldown shorter than the
  beam) re-aims it and pours on with no new punch (pass 87 gave it a fresh one).
- **The Glow** (`params.beam.throat {gain 1, rim 0.35, walls 0.9}`): the throat is one white egg (`Glow`, as big as the old
  bowl, its core and skins together), hidden at rest; mostly lit the moment the wind-up starts (0.7 + 0.3 f through it,
  f = how far into it), full while the beam pours (a 6% flicker), out in about 0.11 s after (9 a second). White x `gain`,
  the beam's colour only at its edge (`rim` x the glow), the floor of the mouth glowing with it (white with a quarter of
  the beam's colour, energy `walls` x the glow). As it dies it darkens to the throat's dark (GLOW_DARK) and stays, dark,
  while the jaw is open more than 0.12 of its 80 degrees (the rest chew opens it 0.09 at most), so a closing mouth never
  shows the sand; then it hides. The floor of the mouth (`Floor`, `FloorBack`) shows and hides with it: at rest the
  mouth is its lips and teeth only. Pass 87's beam-coloured flare quad is gone.
- **The title's mouth** (May's companion on the live Main Menu): flown as a run flies it with no creature near: facing the
  camera all the way round its circle, tipped back 32 degrees, the jaw chewing 0 to 7 degrees, on the run's orbit (radius
  1.25 m, height 1.3 m, bob 0.09 m at 2.4 rad/s, 0.9 rad/s round; it was the guns' 1.35 m, 0.12 m at 3.1, 1.4 rad/s). It no
  longer takes the guns' flourish kick (every 3.5 to 5 s from a clock seeded by the hero, so it always fell at the same
  spot of the circle, the bottom left: the stutter) nor turns out from the hero as it circles.

### 35.TWEAKS No knockback on the hero; DM-G and FAD-E played; two shadows

- **No knockback on the hero** (Garry: "Remove the Knockback from being hit for Player entirely"): `Settings.hero_knockback`
  false by default. Off, no hit moves the hero: Player.shove, Player.hit_knock and a hostile Player.blast do nothing, and
  the two knockbacks that come through apply_knockback (Game.elite_explosion's push, the slam's push for a slam without
  `lift`) and the Gila's eruption throw (EnemyManager._erupt_throw_hero) ask Player.hit_knockback_on first. The hits
  still land (damage, shield, evade, invulnerability unchanged); no STICK_LOCK either (it came with the shove). The
  Down! list leaves out the words "knocked back" and "thrown" while the switch is off.
- **What still moves him**: his own dash, Thruster's lunge, Astro's thruster burst and the leap pickup (blast with
  hostile false), Hang Time's trampoline, teleports, and the two pulls that are the attack itself, not a knockback: the
  silk line's pull towards its shooter (apply_knockback) and the harpoon's leash (Game tether).
- **On** (the debug switch "Hero knockback", Settings' Debug panel and the developer menu; prod holds it off): every
  push as before pass 88 (HIT_KNOCK 2.5, HIT_KNOCK_MAX 9, KNOCK_GRACE 1 s, STICK_LOCK 0.12 s, the crowd escape).
- `hero_knockback_mult` (0.5, the hero's side pushing creatures) is unchanged.
- **A body's death sink** (`shadow.die_drop`, EnemyManager.die_sink): the death strip sinks by die_drop x the cell
  (x size x squash) at its last frame, eased in linearly by frame index (0 on the first death frame), on top of
  `shadow.drop`; clamped -0.5..0.5.

### 35.STAGEMENU The Stages menu, simpler

UI rules (ui/StagesScreen.gd; no balance numbers):

- **The call to action**: "Choose a Stage" (slab, 52 px) under the header, the small "RED CANYON · DRIFTER" line over it
  (`CALL_TO_ACTION`, `CTA_PX`).
- **The difficulty line**: "Difficulty: <word>". The word is the stage entry's `difficulty` (a word as written; a
  number 1..4 is a level; a leading "Difficulty:" is not doubled), else the stage's place: the first Easy, then Medium,
  Hard, and Extremely Hard for the fourth and every one after (`DIFFICULTY_WORDS`). Red Canyon writes Easy, Medium,
  Hard. Its colour rule is pass 87's (sage first, rock last and hell, brass between).
- **The descriptions** name no creature and no boss (Garry); one short line each.
- **A boss met** (`Save.enemy_met(id)`, the Collection's rule from pass 44): on the sand in a run once
  (`Save.seen("enemy", id)`, marked by EnemyManager.spawn, the debug arena's spawns included, as in the Collection) or
  killed once (`kills_of_enemy`). Until then his card shows the Collection's silhouette plate and "Boss not encountered
  yet" (grey) in place of his name, and the locked stage after his says "Beat Stage k" (k = the stage before) instead of
  "Beat the <boss>". Met: his icon and name as before.

### 35.MIRROR Stakes (Difficulty, Boss) for Spite; prices by power; cheapest first

#### Stakes (was Spite: Thorns +2 thorns a rank, Thirst +1% lifesteal a rank, both gone)
Talent id `spite` kept (saves, sims, tests know it); name **Stakes**, forms **Difficulty** and **Boss**,
`content/talents/spite/spite.json`, numbers per rank (the ranks add; the factor is 1 + the sum):

| form | HP | attack | speed | bounty (XP and coins, never written) | who |
|---|---|---|---|---|---|
| Difficulty | +10% `danger_hp` | +10% `danger_attack` | +4% `danger_speed` | +5% `danger_bounty` | every creature that is not a boss or an Elite by its kind (an elite-modded or special creature is a regular one) |
| Boss | +10% `boss_danger_hp` | +10% `boss_danger_attack` | +4% `boss_danger_speed` | +5% `boss_danger_bounty` | bosses and Elites by their kind (archetype boss / elite) |

Rules (core/systems/MirrorDanger.gd):
- HP, walking speed and the contact bite at the spawn (EnemyManager.spawn); every hit a creature throws (ranged, slams,
  boss attacks, death bursts) through `host_of`, so all of a creature's damage carries the attack factor.
- A boss's HP: the Boss form multiplies **after** the pass 83 seconds-of-full-DPS floor and the DPS scale (the floor
  still rules, the form lifts it); an Elite's after its own stage formula.
- Bounty: the creature's XP scale (its gems), its coin (PickupManager.drop_from: a whole number of coins, the fraction
  paid by chance, so +5% of a 2-coin drop is 2, or 3 one time in ten), an Elite's and a boss's purse and the boss's
  coins (Game._kill_effects). Bounty < danger on every form (a test pins the shape, not the numbers).
- Nothing in the arena (Run.arena: factor 1).
- The texts say only the danger ("Creatures +10% HP and attack, +4% speed a rank."); the bounty stats are TextGen kind
  **"hidden"** (never written, not on the pause Stats tab).
- Old saves: Spite ranks bought as Thorns / Thirst are erased and paid back in **full** at the old prices
  (500/900/1500/2250/3250/4500), talent_spent lowered by the same, once (`once: stakes_v88`; buying a Stakes rank also
  marks it, so a Stakes rank is never paid back); the Upgrade board says so once in two toasts ("SPITE IS NOW STAKES",
  "+2,900 GOLD BACK FOR 3 RANKS"). Full, not converted: the new forms make the game harder, which the player never chose.
- The sim's and the probes' preset boards (none / quarter / half / full) never buy Stakes (sim_batch.PRESET_SKIP; a
  quarter is now 11 of 48 ranks, full 42); a board set talent by talent may.

Measured (run sim, Drifter, 12 bots, seed 1, death=keep, stage 1):
- Difficulty x6 ranks, to 7:10: deaths 10.7 -> 21.4 (x2.0), kills -4%, level +1.8, gold +13%.
- Difficulty x1 rank: deaths 10.3 -> 12.3, gold -4% (noise; the bounty is small at one rank).
- Boss x6 ranks, to 10:00 (through the King): the King's fight 78 s -> 102 s, beaten 10 -> 8 of 12, deaths 13.9 -> 16.3,
  gold +9%.

#### Prices by power (each talent's first rank; the ladder stays pass 46's x1, 1.8, 3, 4.5, 6.5, 9 to the nearest 5)
Impact = the run sim with 6 ranks of one form and nothing else against an empty board (Drifter, 12 bots, seed 1,
death=keep, to 7:10): deaths and kills as logs, impact = (ln(deaths0/deaths) + ln(kills/kills0)) / 2 (noise about
+-0.06: Choice and Nerve, which the bot never uses, read 0.02-0.06). HeroPower (DPS x EHP, level 1) beside it.

| talent | form | deaths | kills | gold | impact | HeroPower x6 | price before | price after |
|---|---|---|---|---|---|---|---|---|
| (none) | | 10.67 | 2023 | 1172 | 0 | 1.00 | | |
| Stakes | Difficulty | 21.42 (+101%) | -4% | +13% | -0.37 (harder) | | 500 (Spite) | **100** |
| | Boss | 9.67 | +11% | +14% | 0.10 (noise: one Elite before 7:10) | | | |
| Fortune | Omen | 10.17 | +9% | +7% | 0.07 | 1.00 | 375 | **300** |
| | Greed | 9.58 | -2% | **+96%** | 0.04 | 1.00 | | |
| Choice | Reroll | 9.50 | 0% | -1% | 0.06 (bot never rerolls) | 1.00 | 450 | **325** |
| | Banish | 10.17 | -1% | -2% | 0.02 (bot never banishes) | 1.00 | | |
| Drive | Muscle | 8.50 | +11% | -6% | 0.17 | 1.19 | 400 | **375** |
| | Tempo | 9.67 | +23% | -1% | 0.15 | 1.17 | | |
| Study | Field Notes | 8.00 | +16% | +11% | 0.22 (level 27 vs 21) | 1.00 | 425 | **400** |
| | Poultice | 8.58 | +12% | +5% | 0.16 | ~1.24 | | |
| Stride | Boots | 5.92 (-45%) | -12% | -11% | 0.23 | 1.00 | 300 | **425** |
| | Lodestone | 8.67 | +21% | +15% | 0.20 (level 24) | 1.00 | | |
| Grit | Padding | 8.08 | +11% | -1% | 0.19 | 1.33 (x1.1 a rank compounds: +77% HP at 6) | 350 | **450** |
| | Plate | 7.17 (-33%) | 0% | -16% | 0.20 | 1.25 | | |
| Nerve | Skip | 10.83 | -1% | +1% | 0 (bot) | 1.00 | 550 | **500** |
| | Second Wind | 10.67 | -1% | +2% | 0 (death=keep never revives) | a whole extra life a revive | | |

Choices: the sims put Grit, Stride, Study and Drive close together (0.16-0.22), so they sit in one band 375-450, Grit
the top (HeroPower's strongest, Padding compounds), Stride up from the cheapest (the sims' best survival and level);
Choice and Nerve are what a player values and a bot cannot show (rerolls / banishes; skips and revives): Choice cheap
(325), Nerve the dearest (500: Second Wind is a whole life a rank); Fortune 300 (Omen weak, Greed pure income: +96%
gold at six ranks, priced low so it pays back); Stakes 100 (challenge for a little more gold and XP).

| talent | ranks 1-6 | total before | total after |
|---|---|---|---|
| Stakes (spite) | 100, 180, 300, 450, 650, 900 | 12,900 | 2,580 |
| Fortune | 300, 540, 900, 1350, 1950, 2700 | 9,680 | 7,740 |
| Choice | 325, 585, 975, 1465, 2115, 2925 | 11,610 | 8,390 |
| Drive | 375, 675, 1125, 1690, 2440, 3375 | 10,320 | 9,680 |
| Study | 400, 720, 1200, 1800, 2600, 3600 | 10,970 | 10,320 |
| Stride | 425, 765, 1275, 1915, 2765, 3825 | 7,740 | 10,970 |
| Grit | 450, 810, 1350, 2025, 2925, 4050 | 9,030 | 11,610 |
| Nerve | 500, 900, 1500, 2250, 3250, 4500 | 14,190 | 12,900 |
| **board** | | **86,440** | **74,190** |

The seven power talents together: 73,540 -> 71,610 (-3%, the economy's scale kept); the whole board -14% because
Spite's 12,900 of Thorns / Thirst power became 2,580 of Stakes.

#### Order
- The board lists talents by their first rank's price, cheapest first, then `order`, then id (TalentDef.board_before,
  Registry.talents_list); `order` rewritten 1-8 to match: Stakes, Fortune, Choice, Drive, Study, Stride, Grit, Nerve.
  A later price edit reorders the board by itself. The Level Editor's Sim tab lists them the same way (sim_io).

## 36. Pass 89 (v0.75): the special attacks push the hero again, at half

Garry (2026-10-18): "Player Knockback, make it so the special attacks still knock player back. Like rocketeer rockets,
dynamite, boss attacks, etc. but less than before. The regular melee attacks shouldn't have a knockback still".

- **Regular attacks never push the hero**: any creature's bite (a boss's and an Elite's bite too: EnemyManager's contact
  hit says `special_knock: false`), and a plain shot or splash with no weight of its own (the SHOT_KNOCK share of its
  shooter's bite).
- **Special attacks push at the map's `hero_special_knock`** (timeline_data, absent = WaveTimeline.HERO_SPECIAL_KNOCK_DEFAULT
  0.5; the Level Editor's Scaling card "Special knockback on hero x", 0..1): a charge that connects, every hostile blast
  (the rocketeer's rocket, the dynamite, the golem's boulder and swoop, the giant's and the bosses' slams, the Gila's
  rumble, the King's tumbleweeds), an Elite's death blast, a rock slam, a rain or eruption with a `knockback`, the Gila's
  eruption throw (height and distance x the share, time in the air x its root), a custom boss attack, every other boss
  attack (`kind` "boss": the Brander's lines), the Saiga Sniper's beam, and a shot with its own `knockback` (the
  Buckshot Dwarf's pellets, the Scorpion's and the Sun Prophet's volleys). A blast's lift is scaled like its push.
- Player.knock_share(special): 1 with the debug switch, else the share for a special push and 0 for a regular one;
  Player.is_special_hit(info): `info.special_knock` when named, else a boss's attack. shove() and a hostile blast() are
  special by definition; take_damage's own shove asks is_special_hit; Player.special_push(v) is a special push through
  the plain knockback (an Elite's blast, a slam without a lift).
- Unchanged: the Invincibility bubble and Hang Time's flight still hold off every push; his own moves (the dash, a lunge,
  Thruster Burst, the leap, the trampoline, a teleport) and the pulls (the silk line, the harpoon's rope) move him whole.
- The debug switch (Settings.hero_knockback, now labelled **Full hero knockback**) plays every push whole, bites
  included, as before pass 88; locked off in prod. The Down! list keeps "knocked back" / "thrown" unless the share is 0.
- Recorded in the run record's `map_settings.hero_special_knock`.

## 37. Pass 90 (v0.76): the Watch's bot (ring breakout, the special hunt) and the Watch

Garry's request (2026-10-18, tools/dl/p90/REQUEST.md). Each lane's rules as it wrote them. Tools only: nothing in the game's rules changed.

### 37.BOT The bot's ring breakout, the Survivor preset, hunting only the special types

Tools only (the run sim's and the Watch's bot); nothing here changes the game's rules.

#### The ring breakout (game/tools/bot/BotBreakout.gd; option `breakout`)
On in the new **Survivor** preset (the Explorer with the safety style) and whenever the style is given as `safety` and
`breakout` is not given; off in sim77, explorer, careless, expert.

Two things start a push:
1. **A fresh ring** (fresh_ring): at least **12** creatures first seen within **0.25 s** of each other, **6-24 m** off when
   first seen, within **1.5 m** of one distance (their median), evenly round him: no gap between two of them wider than
   **2.5 x** the even spacing, allowed at least **70°**, never more than **100°**; a gap whose middle (at the ring's distance)
   stands within **4 m** of the arena's edge is closed by the wall (a ring's spots there are pressed onto the wall). Reads
   more than **0.5 s** apart start the memory afresh (nobody is new after a pause or at the run's start).
2. **Shut in** (late, coverage): at least **12** creatures within **9 m**; each shuts the directions where walking would
   bring him within its radius + **0.5 m**, over **72** directions; open slits narrower than **15°** count as shut; at least
   **90%** shut and no gap wider than **25°**; and open ground past the wall he would cross (the bites past it, a lane twice
   as wide from 13 to 23 m, at most **3.0**).

The way (choose_way, **32** directions): cost = the wall (every creature within its radius + **0.75 m** of the line over
**13 m**, or for a fresh ring its radius + **3 m**: its bite weight x the metres he would walk that close, at least **0.5 m**;
bite weight = its damage over the crowd's mean, clamped **0.5-3**, x **2** for an Elite or a boss) + **0.5 x** the crowd past
the wall + the arena's edge (**1.5** a metre that the spots 8 and 16 m out stand past the arena's radius less **6 m**) + **3**
a rock within **8 m** in the way - a lean (**1.0 x** the cosine to his goal, or with no goal **1.5 x** the cosine to the
arena's middle x his distance from it over the arena's radius). The cheapest way is taken.

The push: full stick that way (round a rock's edge, nudged by half of a red warning's dodge push), no kite, held to its
end: a fresh ring once none of it has stood ahead of him within **2.5 m** (+ its radius) of his line for **0.4 s**; shut in,
once he has gone the wall's far side + **2.5 m** (at least **4 m**); never less than **0.6 s**, never more than **3 s**. Then a
**5 s** cooldown. The crowd is read every 2nd frame.

#### The hunt (game/tools/bot/BotGoals.gd special_candidates)
Only the special creature TYPES: a creature whose type wears the gear badge (EnemyDef.badge_for() == "gear": today the
Vulture Raider `rocketeer`, the Saiga Sniper `saiga_sniper`, the harpooner `harpoon_troglodyte`, the map's `specials`
pool). The coloured variance specials (EnemyManager.vspecial) are never hunted. Every other hunt rule unchanged (known
from 30 m after 5 s out of reach, past 9 m or off the screen, none while a boss lives, under 50% HP no new hunt, 40% for
the one held, value 60, the patience + 20 s, 60 s at most, rest 40 s).

#### Measurements (the run sim, tools/sim_batch.py, Drifter, a quarter of the board, death=keep: every fall counted)
"Ring falls" = falls to a ring row's creature inside that row's window (+15 s); "ring HP" = HP lost to it there
(tools/dl/p90/BOT/ring_stats.py; stage 1 rings: r3 0:47, r21 4:05-5:47 scorpion rings, r16 6:08-7:10 mummy rings; stage 2:
r29 werewolf rings 13:55-17:10).

| run | players | falls | ring falls | ring HP lost | HP lost | level at the end | pushes a run (ring / shut in) |
|---|---|---|---|---|---|---|---|
| stage 1, seeds 301+, breakout off | 24 | 10.08 | 5.88 | 779 | 1594 | 16.2 | - |
| stage 1, seeds 301+, breakout on | 24 | 9.38 | 4.75 | 645 | 1471 | 17.0 | 24.2 (8.5 / 15.7) |
| stage 1, seeds 401+, breakout off | 24 | 9.67 | 5.75 | 766 | 1586 | 16.5 | - |
| stage 1, seeds 401+, breakout on | 24 | 10.29 | 5.83 | 779 | 1638 | 16.4 | 24.6 (8.2 / 16.4) |
| stage 2, seeds 501+, breakout off | 24 | 16.46 | 2.58 | 439 | 2713 | 26.9 | - |
| stage 2, seeds 501+, breakout on | 24 | 15.38 | 2.04 | 425 | 2653 | 27.5 | 40.1 (8.0 / 32.1) |
| stage 1, seeds 401+, Survivor preset | 24 | 10.46 | 5.83 | 786 | 1726 | 15.0 | 24.5 (6.7 / 17.8) |

(the 301+ "on" run played the push's first end rule for a fresh ring; the others the final one.) Pooled: falls 12.07 off
against 11.68 on (-3%), ring falls 4.74 against 4.21 (-11%), ring HP 661 against 616 (-7%); the level the same or a
little higher. Per push: a fresh ring costs about 3-5 HP (2.1-2.3 s, 8 m), a shut-in push 11-12.5 HP (1.7-1.8 s, 5 m).
Within the noise of 24 runs (a run's falls vary 0-36), so read it as: the breakout does not cost the run anything and
takes a little off the rings.

What did not work on the way (stage 1, 12-24 runs each): a coverage trigger at 12 m (80% shut, gap 35°, 8 creatures)
fired in every crowd, 30-45 pushes a run, and cost ~1-3 falls and 1-3 levels a run (pushes away from the kill zone leave
the gems behind); a loose fresh ring (5 creatures, any distance, a 100° gap) caught the roster's timed bursts too
(31 a run): no better than off.

The Survivor preset plays the safety style too (pass 80's: cards scored for survival, healing goals up, exploring and
barrels down): on the same seeds it ended 1.4 levels lower than the Explorer with the breakout and fell about as often;
that is the safety style's price in this stage, not the breakout's.

#### The hunt, before and after (stage 1, seeds 101+, 12 runs each)
| | hunts a run | specials hunted came / killed | coloured specials came / killed |
|---|---|---|---|
| pass 82's hunt (the coloured ones) | 20.9 | 14.5 / 12.6 (coloured) | 14.5 / 12.6 |
| pass 90 (the special types only) | 1.2 | 1.7 / 0.9 (types) | 14.4 / 12.3 |

The coloured specials die as often without the hunt (85% against 87%: the weapons take them first within 10 m). Stage 2
(the harpooner joins): 2.9-3.6 hunts a run, 2.5 special types came, 1.6-2.0 killed.

### 37.WATCH The Watch: Damage taken, chart hover hints, revive at will

- **The Watch's Down! (`death`, default "ask")**: when the bot falls, the Watch pauses the run the frame after (the
  game's Down! waits 1.2 s on the game's clock, so it never comes) and waits: **Revive** (R) stands him up where he fell
  at **full health and full Energy Shield**, with the revive's **2 s of blinking** (Player.revive), **no blast**: the
  crowd is left as it is; **Revive with blast** (B) adds the game's own revive blast (Game.revive_blast: 4.8 m that
  kills the crowd and hurts Elites and bosses for a share, plus the 6 m push), which Down!'s revive always has;
  **End run** (E) ends the run as a death. As many revives as wanted; none costs gold or counts as a bought revive
  (Run.revives_used untouched). "auto": the Watch revives him itself **0.5 s of game time** after the fall (no
  blast). A fall Phoenix Feather takes is left to it. The screens that waited while he was down (banked level-ups, a
  chest) come after the revive as after the game's own (REVIVE_BEAT 0.6 s). A self-closing check (autoquit) treats
  "ask" as "end".
- **The record** says how often: `watch_revives` and `watch.revives` / `watch.revive_t` in the header, a "revive"
  event (id "watch") after each "death" event; the decision log and its CSV have a "down" and a "revive" line each.
- **Damage taken tab**: every hit from the hero's damage log (the same hits RunAnalytics.took counts), grouped by
  source name and attack (the first of the hit's words that names an attack; else bite / shot / attack by its kind;
  "knocked back", "thrown", "roped", "pulled", "slowed" never name one). HP lost = the hit's dealt; the Energy Shield's
  part apart; evaded hits counted (and their raw); the shield power-up's and Marshal's Star's blocks counted as
  blocked. Columns: the whole run, and the last 10 / 30 / 60 s (default 30).
- **Chart hover**: the hint names a mark or a moment within 6 px of the pointer; a line has a value only within 2.5 of
  its samples' widths of the pointer.

## 38. Pass 91 (v0.77): art tools only

No game numbers changed. The keyer skips the cast-shadow cut when the figure wears the screen colour (artkit.WEARS_SCREEN_SHARE 0.04); creature death `shatter` (artkit.shatter, about 14 pieces into a heap); method creature_pictures (front_ref, back_ref, picture_use as_is|redraw, screen auto).

## 39. Pass 92 (v0.78): the Desert Spider

# Pass 92, lane SPIDER: numbers and rules for BALANCING.md

- New creature `desert_spider` (Desert Spider), content/enemies/desert_spider/desert_spider.json. Not on any map (Garry places it).
  Starting numbers are the Fire Ant's (hp 36, speed 3.0 (ant 2.8), damage 8, knockback 4.81, drops small 1 / medium 0.6 /
  gold 0.12 / chest 0.008, xp_mult 2.4), with its own body: radius 0.5, size 1.3, pack_size 3, archetype swarmer, brain chase,
  blood #7BC43A, frame_px 160, shadow {scale [1.45, 1.5], up 0.45, drop 0.06}, fps run 20 / die 12, eight directions.
  It plays look SP-B (a creature with looks must play one; all four looks are `fresh` until Garry approves one).
- No new game rule. The new numbers are art-tool settings (blender_gait defaults; see keys_SPIDER.md).

## 40. Pass 93 (v0.79): art tools only

No game numbers changed. Made walks: `step` swing (default, pass 92) | track (stride 0.22, raise 0.12, crouch 0.1, knee up); `tips=1` writes tips.json, tools/gait_check.py names SIDEWAYS/BACKWARDS legs. gen_ctl recipe `fit_ref` (scale the painting onto the depth figure), `no_green` "rb" (green held to max(red, blue)). The Desert Spider still plays SP-B; SP-E and SP-F are fresh.

## 41. Pass 95 (v0.80): the muzzle, the Frisbee's trails, Fire forward, the passive ladder, the Dragon's Breath, despawning, the Magnet, the King and the Scorpion, VACE frame repair

Garry's request (2026-10-21, tools/dl/p95/REQUEST.md). Each lane's rules as it wrote them.

### 41.ITEMS The shot from the held gun's muzzle; the Frisbee's trail per look; the Fire forward debug switch

#### The shot leaves the held gun (ProjectileEmitter.shot_origin)
- A gun that is **held** (the forward guns: the Boomstick, the Blunderbuss, the Doomstick, with every mutation: Birdshot,
  Both Barrels, Slug, Dragon's Breath...) fires every round, pellet, ghost pellet of a blast, tracer and muzzle flash from
  the **muzzle as drawn this frame**: the gun is posed at the hero's hip (Player.tscn `Hip`, 0.55 m to his right, 0.7 m up)
  and turned to the shot's line, and the muzzle is the middle of the far end of its barrels (the vertices of its visible
  meshes within 3 cm of the furthest down the gun's -Z: twin barrels and a bell mouth average to the bore). The recoil
  squish (scale z 0.7 on the shot) and the turn are in it: the Boomstick's round starts 0.85 m x 0.7 = 0.6 m ahead of the
  hip at the barrel's height (0.09 m over the hip), 0.85 m once the gun has settled. Before: the hero's chest, 0.8 m up and
  0.5 m out (Player.aim_origin), a third of a metre behind the muzzle and higher than it.
- Only where the round starts moves: its line, speed, life (range / speed), the blast's hit test (from the hero) and the
  lead are what they were. The companions (the Revolver, Tommy Gun, Chicago Typewriter, Golden Revolver, Peashooter...)
  fire from their own mouths as before (pass 35, pass 75: 0.45 m along the line from the gun's rest place); a weapon
  with neither a held gun nor a companion from the chest as before.

#### The Frisbee's trail (Frisbee.trail_params, `params.disc.trail`)
- `disc.trail` is a block {style, length, width, alpha, colour}; `true` = the look's own style and numbers, `false` or
  style "none" = no trail. One style per look: plain -> **streak** (one faint pale ribbon with a brighter thread down its
  middle), razors (Poison Razors) -> **sparks** (two thin bright lines off the rim's edges, 0.9 radii out, and every other
  trail point a short spark flicking out and back), saucer (the Flying Saucer) -> **glow** (a wide soft glow with a brighter
  core). Carry inherits the plain streak at its 1.5x disc (the width is in disc radii, so it trails wider).
- The styles' numbers (code defaults = the content's): streak length 0.4 s, width 1.5 radii, alpha 0.6, colour the glow
  lerped 45% to white; sparks 0.32 s, 0.6 radii (the sparks' length), alpha 0.9, 30% to white; glow 0.48 s, 2.2 radii,
  alpha 0.45, 20% to white. Before pass 95: 0.22 s, 1.5 radii, alpha 0.32, 25% to white, one ribbon for every look, gone
  the instant the disc began its glide. Now the ribbon keeps fading out behind a disc gliding down (no new points are laid
  in the glide). A point every 0.025 s (TRAIL_STEP); every disc of a weapon draws into one ImmediateMesh: one draw call.

#### "Fire forward" (Settings.fire_forward, core/systems/FireForward.gd)
- A **debug switch**, off by default, PROD_LOCKED off (Settings' Debug panel row "Fire forward", the developer menu row;
  the run record's `settings.fire_forward`). Garry asked for it as a toggle; what it changes is a rule of play only when
  he turns it on.
- On, a weapon with `params.fire_forward` fires **along the hero's facing** (Player.forward) unless a living creature (not
  dying, not still rising) stands within **75% of the weapon's range** of the hero (FireForward.NEAR_FRAC x `range` as the
  weapon's sheet says it, so Reach and the like count): then it aims as it always did. Covered: the Sabre (range 2.6 ->
  1.95 m), the Spear = pike (4.6 -> 3.45 m), the Hammer (4.6 -> 3.45 m), the Frisbee (12 -> 9 m), the Tumbleweed (16 ->
  12 m), the Basketball (9 -> 6.75 m) and their evolutions (Whirlwind, Thunder Lance, Earthshaker, Flying Saucer, Dust
  Devil, Slam Dunk). The hidden Spear (`spear`), Halberd, Zweihänder and the old Earthshaker are not marked.
- The Sabre and the Spear stroke along the facing on their clock even with nobody there (before: no stroke without a
  target); the Hammer's blow lands **75% of its reach ahead** (3.45 m; its 1.6 m smash radius then covers to the range's
  end); the Frisbee's arc crosses its line at the range's end; the Tumbleweed rolls straight ahead (before: no shot
  without a target).
- The Basketball thrown forward: a throw that struck nothing by the end of its flight hops to a creature within its bounce
  reach (`ricochet_any.reach`, 7 m) as a hit would send it, else it **drops to the sand** (slows to 35% of its speed, falls
  under gravity, gone with a puff of sand on the ground or after 0.6 s): no return, no catch, no Heat, no refund. A throw
  that hit something plays on as any throw (its hops, the return, the catch).

#### Measured (captures tools/dl/p95/ITEMS/shots/, 1080x1920, the debug arena, camera zoom 0.62; sheets in thumbs/)
- The muzzle (`held_tip`, in the held gun's own frame; the hip pivot is the origin): the Boomstick (0, 0.095, -0.85):
  0.85 m down the barrel, 9.5 cm above the pivot; Both Barrels (0, 0.094, -0.85): the bore between the twin barrels;
  Birdshot the same gun; the Blunderbuss (0, 0.10, -1.15): the bell's mouth 1.15 m out. In every frame after the shot
  (boomstick_side_f02/f04, boomstick_f02, both_barrels, birdshot, blunderbuss, blunderbuss_side) the tracers and the muzzle
  smoke start at the barrel's end as drawn, none inside the hero or behind the gun. The Revolver, Tommy Gun and Chicago
  Typewriter report "no held tip" and fire from their companions' mouths as before (revolver/tommy/chicago frames).
- The trails (frisbee_plain, frisbee_razors, frisbee_carry, flying_saucer, frames f04..f45): plain = a faint pale
  yellow-green streak (0.72, 1.0, 0.45) from the hero to each disc, dimmer than the disc; razors = two thin pink edge lines
  (1.0, 0.39, 0.68) with the sparks; saucer = a wide soft pink glow (1.0, 0.40, 0.71) about 2 disc widths wide; Carry =
  the streak at its 1.5x disc. Each reads at the phone's canvas against the sand at a glance and none shouts.
- Fire forward (forward_sabre, forward_hammer, forward_frisbee; nobody alive): the Sabre's stroke dir (0, 0, -1) = the
  facing (0, 0, -1); the Hammer at level 3 (range 5.52 m) landed 4.14 m ahead = 0.75 x 5.52; the Frisbee's first disc
  left at 8 degrees off the facing (its arc's opening angle; dir0 (0.139, 0, -0.990)), crossing the line at the range's end.
- Tests: pass95_ITEMS_test 18/18; the older files my ids touch, 15 files 225/225, none re-pinned (pass35 16, pass48_melee
  20, pass48_projectiles 24, pass51 10, pass53_weapons_a 11, pass53_weapons_b 13, pass60_wp 18, pass61_wp1 17,
  pass62_it 20, pass66_shape 14, pass67_ball 12, pass69_fris 18, pass74_analytics 8, pass81_prod 15, pass88_tweaks 9);
  check_scripts 619 files, 0 errors; smoke_run 60 s OK (263 kills, 10 cards, 1 chest, 1 portal, errors []);
  touch_audit settings 64 of 64 controls answered a finger (the FireForward switch among the Debug panel's 4).

### 41.PASSIVES Passive items climb the rarity ladder to Evolved; power redistributed

#### The rule: passive items climb the rarity ladder

A passive item (content/passives, `line` false, no `evolves_from`; the 34 items) keeps its rarity and climbs the
rarity ladder one rung an upgrade: an item of rarity r has (the rungs from r to legendary) + 1 (Evolved) upgrades, so
its levels are common 6, uncommon 5, rare 4, epic 3 (legendary 2; no item is legendary). Level k stands on rung
RARITIES[idx(r) + k - 1]; the top level is **Evolved**, a rarity for passive items only (never for weapons or cards):
the dark plate ringed in brass like an evolved line, the item's Evolved icon (the same icon with a white outline round
its subject, `<id>_icon_evolved.png`, tools/evolved_icons.py), "Evolved" in the words (the card's EVOLVED tag in the
evolution's ember, "Next level (Evolved): ...", "Level 6 (Evolved): ... total."). `max_level` is derived from the rule
(PassiveDef.ladder_levels, applied in JsonContent.build); the JSON holds every rung's effects explicitly, so each rung
is Garry's to tune in the Level Editor (which warns when the list and the rule disagree). The lines (cards: 4 levels,
a Risen card when maxed) are untouched. (Garry, pass 95: "the number of Upgrades is reduced to the number of upgrades
they have left to reach Legendary + Evolved Rarity ... Evolved is a 'Rarity' for Passive Items".)

What follows from it, named:
- A held item's upgrade card says the rung it lands on after the kind's word ("PASSIVE · RARE"); a new item's card
  says only PASSIVE (its plate says its rarity, pass 47); the top says PASSIVE with the EVOLVED tag.
- The plate of a passive item takes its rung's colour wherever its level is known (cards, chests, the Stranger, the
  pause Build tab and Stats sources); the Collection shows the item in general: its rarity's colour and the base icon.
- The Stranger's two levels at once land on the rung of the level reached; a chest offers one rung; nothing past the
  top. An old level past the top (a tool, a record) reads as Evolved.
- Phoenix Feather (uncommon, 5 levels): level 1 one free revive; rungs 2-4 +15%, +15%, +20% health on revive
  (`revive_hp`, the gold revive's too); Evolved a second free revive (`phoenix_revive` 2, Run.phoenix_count): the item
  is "used" only when every life is spent.
- Shop prices still go by the item's own rarity (StructureShop RARITY_MULT), not the rung bought.

#### The redistribution (tools/passive_ladder.py; the old numbers under tools/dl/p95/PASSIVES/old/)

The scheme, from Garry's words ("redistribute that power among fewer upgrades ... not the same 100% over 2 ... the
power shouldn't just half either ... stats on the 1st level will be higher"):
- level 1 = 1.2-1.5 x the old level 1 (fatter the rarer: common ~1.3, uncommon ~1.35, rare ~1.4, epic ~1.5);
- each rung after it about 0.8 of an old step (the same-count items keep their old top, so their rungs are a touch
  under an old step; the Evolved rung is bigger than any old step);
- the Evolved rung the biggest single step, about 1.5 rungs ("not as crazy");
- the top: an item that lost rungs (rare 5 -> 4, epic 5 -> 3) ends at 0.75-0.9 of its old top; one that kept its
  count (the uncommons, the 3-level epics) at about its old top (x0.97-1.05); one that gained rungs (common 5 -> 6,
  Overkill 3 -> 5, Ricochet 4 -> 5, Brimstone Brand and Guillotine 3 -> 4, Phoenix Feather 1 -> 5) a little above it
  (x1.05-1.22; Beer's and Quickdraw's multiplicative stacks x1.21);
- a capped stat never passes its cap: the Magnet's 8.5 m (PickupManager.XP_PULL_MAX_R, so its top stays 8.5 m, reached
  in 3 picks instead of 5, level 1 at 6 m), Hot Streak's +100%, chances under 100%;
- by hand with a reason: Phoenix Feather (above), the Magnet (the cap), the Pocket Watch (the chance at levels 1, 3 and
  Evolved as before), Counterpunch (level 1 keeps "double damage", Evolved makes it x2.5), Hot Springs (same count: the
  old top kept, level 1 fatter), the 3-level epics.

The table (level 1 | rung 2 | ... | Evolved; the top old -> new and its ratio):

| item | rarity | old levels | new levels | rungs (level 1 | rung 2 | ... | Evolved) | top: old -> new (ratio) |
|---|---|---|---|---|---|
| adrenaline | uncommon | 5 | 5 | adrenaline_speed +0.0055, adrenaline_might +0.004 | adrenaline_speed +0.003, adrenaline_might +0.0025 | adrenaline_speed +0.003, adrenaline_might +0.0025 | adrenaline_speed +0.003, adrenaline_might +0.0025 | adrenaline_speed +0.005, adrenaline_might +0.0035 | adrenaline_speed 0.02 -> 0.0195 (x0.97); adrenaline_might 0.015 -> 0.015 (x1.00) |
| barrel_rush | common | 5 | 6 | barrel_speed +0.3, barrel_seconds +4 | barrel_speed +0.08, barrel_seconds +0.6 | barrel_speed +0.08, barrel_seconds +0.6 | barrel_speed +0.08, barrel_seconds +0.6 | barrel_speed +0.08, barrel_seconds +0.6 | barrel_speed +0.12, barrel_seconds +0.9 | barrel_speed 0.65 -> 0.74 (x1.14); barrel_seconds 6 -> 7.3 (x1.22) |
| beer | common | 5 | 6 | might x0.15, max_hp x-0.05 | might x0.1, max_hp x-0.04 | might x0.1, max_hp x-0.04 | might x0.1, max_hp x-0.04 | might x0.1, max_hp x-0.04 | might x0.14, max_hp x-0.05 | might 0.7623 -> 0.9194 (x1.21); max_hp -0.2262 -> -0.2335 (x1.03) |
| big_game_hunter | uncommon | 5 | 5 | elite_damage +0.2 | elite_damage +0.12 | elite_damage +0.12 | elite_damage +0.12 | elite_damage +0.18 | elite_damage 0.75 -> 0.74 (x0.99) |
| brimstone_brand | rare | 3 | 4 | brand_chance +0.2 | brand_chance +0.1 | brand_chance +0.1 | brand_chance +0.15 | brand_chance 0.45 -> 0.55 (x1.22) |
| cake | common | 5 | 6 | heal_drop +0.004 | heal_drop +0.0025 | heal_drop +0.0025 | heal_drop +0.0025 | heal_drop +0.0025 | heal_drop +0.0035 | heal_drop 0.015 -> 0.0175 (x1.17) |
| cold_snap | common | 5 | 6 | freeze_chance +0.03 | freeze_chance +0.015 | freeze_chance +0.015 | freeze_chance +0.015 | freeze_chance +0.015 | freeze_chance +0.02 | freeze_chance 0.1 -> 0.11 (x1.10) |
| counterpunch | uncommon | 5 | 5 | counter_damage +1, counter_haste +0.25, counter_speed +0.2, counter_seconds +2.5 | counter_haste +0.04, counter_speed +0.025, counter_seconds +0.2 | counter_haste +0.04, counter_speed +0.025, counter_seconds +0.2 | counter_haste +0.04, counter_speed +0.025, counter_seconds +0.2 | counter_damage +0.5, counter_haste +0.06, counter_speed +0.04, counter_seconds +0.3 | counter_damage 1 -> 1.5 (x1.50); counter_haste 0.4 -> 0.43 (x1.07); counter_speed 0.27 -> 0.315 (x1.17); counter_seconds 3 -> 3.4 (x1.13) |
| desperado | rare | 5 | 4 | desperado +0.16 | desperado +0.1 | desperado +0.1 | desperado +0.15 | desperado 0.6 -> 0.51 (x0.85) |
| gas_mask | epic | 5 | 3 | gas_mask_cap +0.12 | gas_mask_cap +0.08 | gas_mask_cap +0.1 | gas_mask_cap 0.4 -> 0.3 (x0.75) |
| guillotine | rare | 3 | 4 | execute_frac +0.09 | execute_frac +0.04 | execute_frac +0.04 | execute_frac +0.06 | execute_frac 0.21 -> 0.23 (x1.10) |
| heavyweight | rare | 5 | 4 | heavyweight +0.012 | heavyweight +0.0015 | heavyweight +0.0015 | heavyweight +0.0025 | heavyweight 0.02 -> 0.0175 (x0.87) |
| hot_springs | epic | 3 | 3 | max_hp +26, regen +0.65, heal_pulse +5 | max_hp +6, regen +0.2 | max_hp +10, regen +0.35 | max_hp 40 -> 42 (x1.05); regen 1.2 -> 1.2 (x1.00); heal_pulse 4 -> 5 (x1.25) |
| hot_streak | rare | 5 | 4 | kill_might +0.07 | kill_might +0.04 | kill_might +0.04 | kill_might +0.06 | kill_might 0.25 -> 0.21 (x0.84) |
| hush_money | uncommon | 5 | 5 | gold_on_hit +3 | gold_on_hit +2 | gold_on_hit +2 | gold_on_hit +2 | gold_on_hit +3 | gold_on_hit 10 -> 12 (x1.20) |
| kindling | uncommon | 5 | 5 | fire_damage x0.2 | fire_damage x0.12 | fire_damage x0.12 | fire_damage x0.12 | fire_damage x0.18 | fire_damage 1.0114 -> 0.9894 (x0.98) |
| last_stand | epic | 3 | 3 | last_stand +1.3 | last_stand +0.3 | last_stand +0.5 | last_stand 2 -> 2.1 (x1.05) |
| loose_change | uncommon | 5 | 5 | coin_on_hit +0.32 | coin_on_hit +0.08 | coin_on_hit +0.08 | coin_on_hit +0.08 | coin_on_hit +0.12 | coin_on_hit 0.65 -> 0.68 (x1.05) |
| magnet | epic | 5 | 3 | xp_pull_radius +6 | xp_pull_radius +1, xp_pull_rate +0.5 | xp_pull_radius +1.5, xp_pull_rate +0.5 | xp_pull_radius 8.5 -> 8.5 (x1.00); xp_pull_rate 1 -> 1 (x1.00) |
| overkill | uncommon | 3 | 5 | overkill +0.4 | overkill +0.15 | overkill +0.15 | overkill +0.15 | overkill +0.25 | overkill 1.02 -> 1.1 (x1.08) |
| phoenix_feather | uncommon | 1 | 5 | phoenix_revive +1 | revive_hp +0.15 | revive_hp +0.15 | revive_hp +0.2 | phoenix_revive +1 | phoenix_revive 1 -> 2 (x2.00); revive_hp new 0.5 |
| pickpocket | common | 5 | 6 | coin_drop +0.005 | coin_drop +0.003 | coin_drop +0.003 | coin_drop +0.003 | coin_drop +0.003 | coin_drop +0.005 | coin_drop 0.02 -> 0.022 (x1.10) |
| pocket_watch | uncommon | 5 | 5 | powerup_duration +0.2, powerup_chance +0.05 | powerup_duration +0.12 | powerup_duration +0.12, powerup_chance +0.04 | powerup_duration +0.12 | powerup_duration +0.2, powerup_chance +0.05 | powerup_duration 0.75 -> 0.76 (x1.01); powerup_chance 0.12 -> 0.14 (x1.17) |
| powder_keg | uncommon | 5 | 5 | powder_keg_chance +0.065 | powder_keg_chance +0.02 | powder_keg_chance +0.02 | powder_keg_chance +0.02 | powder_keg_chance +0.03 | powder_keg_chance 0.15 -> 0.155 (x1.03) |
| quickdraw | common | 5 | 6 | projectile_speed x0.2 | projectile_speed x0.12 | projectile_speed x0.12 | projectile_speed x0.12 | projectile_speed x0.12 | projectile_speed x0.18 | projectile_speed 1.0114 -> 1.2281 (x1.21) |
| reach | uncommon | 5 | 5 | area x0.1 | area x0.06 | area x0.06 | area x0.06 | area x0.1 | area 0.4693 -> 0.4411 (x0.94) |
| ricochet | uncommon | 4 | 5 | ricochet +0.25 | ricochet +0.13 | ricochet +0.13 | ricochet +0.13 | ricochet +0.2 | ricochet 0.8 -> 0.84 (x1.05) |
| siesta | uncommon | 5 | 5 | still_regen +1.4 | still_regen +0.8 | still_regen +0.8 | still_regen +0.8 | still_regen +1.2 | still_regen 5 -> 5 (x1.00) |
| sinners_greed | epic | 3 | 3 | greed +0.4, xp_gain +0.2 | greed +0.2, xp_gain +0.1 | greed +0.3, xp_gain +0.15 | greed 0.9 -> 0.9 (x1.00); xp_gain 0.45 -> 0.45 (x1.00) |
| skedaddle | rare | 5 | 4 | hurt_speed +0.25, hurt_speed_seconds +2 | hurt_speed +0.03, hurt_speed_seconds +0.3 | hurt_speed +0.03, hurt_speed_seconds +0.3 | hurt_speed +0.05, hurt_speed_seconds +0.5 | hurt_speed 0.4 -> 0.36 (x0.90); hurt_speed_seconds 3.5 -> 3.1 (x0.89) |
| snake_oil | epic | 3 | 3 | overheal +0.25 | overheal +0.06 | overheal +0.1 | overheal 0.4 -> 0.41 (x1.02) |
| steady_hand | rare | 5 | 4 | still_might +0.13 | still_might +0.04 | still_might +0.04 | still_might +0.05 | still_might 0.3 -> 0.26 (x0.87) |
| venom | uncommon | 5 | 5 | poison_damage x0.2 | poison_damage x0.12 | poison_damage x0.12 | poison_damage x0.12 | poison_damage x0.18 | poison_damage 1.0114 -> 0.9894 (x0.98) |
| vulture | uncommon | 5 | 5 | crit_heal_chance +0.06 | crit_heal_chance +0.03 | crit_heal_chance +0.03 | crit_heal_chance +0.03 | crit_heal_chance +0.05 | crit_heal_chance 0.2 -> 0.2 (x1.00) |

#### The texts

The hand-written card lines that named the old numbers were rewritten to the ladder's (TEXT in the tool): Barrel Rush,
Cold Snap, Counterpunch, Desperado, Gas Mask, Guillotine, Heavyweight, Hot Springs, Hot Streak, Last Stand, Loose
Change, the Magnet, Phoenix Feather, the Pocket Watch, Powder Keg, Siesta, Skedaddle, Snake Oil, Steady Hand,
Vulture; Beer's trade reads "−4 to −5% max HP a level". The generated lines: level 1 plainly ("+0.4% cake drop
chance."), a higher level "Level 3 (Rare): +0.9% cake drop chance total.", the next level "Next level (Rare): +0.25%
cake drop chance", a card's upgrade "Next: +0.25% cake drop chance." (no "a level": every rung is its own).

#### Measured

##### The run sim (tools/sim_batch.py: 12 Drifters, seeds 1-12, a quarter board, death ends the run, stage 1)

Before = the committed passives on a private copy of the snapshot (tools/dl/p95/PASSIVES/sim/before), after = the ladder
(sim/after); the same code otherwise. Mean (sd, median) over the 12 runs, Welch's t:

| measure | before | after | delta | t (df ~17-21) |
|---|---|---|---|---|
| run end (s) | 280 (73, 278) | 262 (54, 259) | -18 | 0.66 |
| hero level at the end | 11.9 (4.3, 11) | 10.2 (2.9, 9.5) | -1.8 | 1.11 |
| kills | 961 (501, 927) | 886 (366, 866) | -75 | 0.40 |
| damage dealt | 44,820 (35,842) | 35,989 (18,310) | -8,831 | 0.73 |
| XP | 2,254 (2,062) | 1,498 (1,096) | -756 | 1.07 |
| gold | 401 (340) | 311 (285) | -90 | 0.68 |
| chests | 4.1 (4.1) | 2.2 (2.2) | -1.9 | 1.36 |
| deaths a run | 1.25 | 1.25 | 0 | |

No measure moves beyond its noise (every t under 1.4: p above 0.19); the "before" set holds two runs that reached
levels 20 and 21 (424 s and 338 s) and without them it equals the "after" set (end 259 s vs 262, level 10.2 vs 10.2,
kills 799 vs 886). The bot held only 7 passive items (7 levels in all) across the 12 "before" runs and 8 (9 levels)
across the "after" ones: the explorer bot spends its picks on weapons and cards, so the sim barely exercises the
passives at all; the probe below measures them directly. A 30-run pair would halve the noise but not change this.

##### HeroPower (game/tools/_p95_PASSIVES_power.gd: a fresh Drifter with the Revolver, each item alone at level 1 and at its top, old rungs against new)

HeroPower (core/systems/HeroPower.gd) is the square root of full DPS x effective HP: it sees only damage, health,
regen and armour. The base here is 2.385 (DPS 116.1, EHP 100). Of the 34 items only three move it at all; the other 31
(chances, gold, coins, drops, pulls, on-kill and conditional stacks, speeds, revives) read +0.000 at every level, old and
new, so their balance rests on the table's ratios above. Power above the base:

| item | rarity | level 1 old -> new | top old -> new |
|---|---|---|---|
| beer | common | +0.075 -> +0.108 (x1.44) | +0.400 (lv 5) -> +0.508 (lv 6) (x1.27) |
| heavyweight | rare | +0.116 -> +0.139 (x1.19) | +0.228 (lv 5) -> +0.200 (lv 4) (x0.88) |
| hot_springs | epic | +0.386 -> +0.492 (x1.27) | +0.779 (lv 3) -> +0.797 (lv 3) (x1.02) |

The six common items (barrel_rush, beer, cake, cold_snap, pickpocket, quickdraw) maxed together: 2.785 -> 2.893 (DPS 205 -> 223, EHP 77.4 -> 76.7); only Beer
counts for HeroPower among them (its might stack 0.76 -> 0.92 with a sixth rung, its HP trade -22.6% -> -23.4%).

Verdict: nothing jumps out. Level 1 is a fifth to a half stronger, as Garry asked; Heavyweight, which lost a rung,
tops out at 0.88 of before; Hot Springs, with the same count, at 1.02; Beer, with a rung more, at 1.27 (a common item
that costs six picks to max). No retune after the measurement.

### 41.BREATH The Cologne and Lighter (Dragon's Breath): a fire-breath weapon, its path and evolution

#### The Dragon's Breath (content/weapons/dragons_breath; behaviour FireBreath)

Rare, weight 6 (the Molotov's), available to everyone, no hero's favourite. Level 1: a tick of **32** damage every
**1.0 s** to every creature whose body stands in a **50°** cone **5 m** long from the hero's face, for **2.0 s**, every
**9.0 s** (the slowest weapon in the game at every level: the Turret Buddy's 6.0 s is next; the rule is relative, "the
slowest weapon in the game", checked against every other weapon's base cooldown by the Level Editor's selftest, so the
number itself is Garry's to tune); every creature in the fire is set alight every tick with **6** fire damage (every
0.6 s) for **2.5 s**, spread 0.3. `amount` is seconds of breath: **+1.0 s per point past the first**, **6 s at most**
(so Multishot's three points make a 5 s breath; a 10-point amount buff a 6 s one). Level 2: damage +35%, range +0.5 m.
Level 3: cooldown −12%, fire damage +50%. Level 4: damage +35%, area +20% (the cone 60°). Level 5: cooldown −12%,
range +0.5 m, duration +1.0 s. At 5: 58.3 a tick, 6.97 s, 3.0 s (three ticks), 6 m, 60°, burn 9 / 2.5 s.

Rules (every one new, FireBreath.gd):
- **The cone follows his facing** and walks with him; it never aims. A creature counts when any of its body (its
  radius) is inside; dying, hidden and held ones never.
- **A tick on entry**: a creature takes its first tick the moment it stands in the fire, the next every `tick` s while
  it stays (counted by its spawn serial); the cadence is anchored to its entry (a tick that lands a frame late never
  delays the next); a creature that walks out and back in within a tick keeps its clock, one back after longer starts
  afresh. No tick on the breath's last frame (a 2 s breath ticks at 0 and 1 s; the estimate counts ceil(seconds / tick)).
- **The wait** (`breath.wait` 2 s): with the cooldown ready it waits for a creature to stand in the cone; past the
  wait it breathes where he faces if anyone at all is within `range` (aim_index: on the screen, up out of the sand).
- The breath keeps burning through a pause (the whoosh stops and starts again) and ends when the hero falls.
- Blue fire (`fire_blue`, Blue Flame and so the Fire Eater): the breath, its wash and every creature it lights burn blue.

#### The path

- **Blue Flame** (element, fire): range +25%, damage −20%, burns last +75%, fire_blue. (Methanol's trade, the Molotov's.)
- **Held Breath** (volume; `breath.still {seconds 2, duration_mult 2, damage_mult 1.5, ring true}`): a breath that
  starts after the hero has stood still AND unhit for 2 s lasts ×2 (after the amount cap), every tick deals ×1.5, and
  the fire comes from all sides (a 360° ring, the same reach). `Player.still_unhit_seconds` = min(still_seconds, seconds
  since the last hit that landed on his star, shield or health); an evaded or immune hit is a miss. A hit breaks the
  stillness for the NEXT breath only: a breath already burning is never cut. Steady Hand's `still_seconds` is untouched.
- **Backdraft** (motion; `breath.knock` 5, `look.intensity` 1.5): every tick also shoves the creature straight away
  from the hero with force 5 through EnemyManager.damage's push (/ its mass x knockback_resist x the map's
  hero_knockback_mult 0.5, a boss 0.15): about a metre a second for a skeleton. The flames x1.5.

#### The Fire Eater (content/evolutions/fire_eater)

80 a tick, 6.5 s, 3.5 s (four ticks), 7 m, 65° (area 1.3), burn 14 / 3.5 s, spread 0.5; `final`: knock 7, intensity
1.8, max_seconds 8. With its path (always all three): 64 a tick, 8.75 m, burn lasts 6.1 s, blue. **Thorns +8 on the
hero while it is held** (the Thorn's level 1): a weapon level effect aimed at "player" (new rule, WeaponDef.player_effects
/ Run._apply_weapon_player_effects, source "weapon:fire_eater" in the Stats tab); the thorns strike as Game._thorns_burst
does (THORNS_RADIUS 2.3 m, once every 0.5 s, recorded as "thorns"). The Fire Eater is the slowest evolution (the Iron
Bastion's 5.0 s is next).

#### The estimate

WeaponInstance.breath_dps = damage x ticks x BREATH_CATCH (3 creatures in the cone) / cooldown; HeroPower divides the 3
out and adds the burn for `element_uptime` = (breath seconds + fire_duration) / cooldown of the time (1 for every
other weapon: a 9 s weapon's burn is out most of the time, and a boss's HP is pegged to the hero's full DPS).

##### The table (game/tools/_p95_BREATH_dps.gd, a fresh level-1 Drifter's sheet; whole output tools/dl/p95/BREATH/dps.txt)

"dps" is the pause screen's estimate (WeaponInstance.dps_estimate), "1-target" HeroPower's (the crowd divided out, the
burn at its uptime). A level-5 row carries the weapon's whole path (Blue Flame's −20% damage is in the breath's).

| weapon | lvl | cooldown | a hit | range | burn | dps (pause) | 1-target (HeroPower) | path |
|---|---|---|---|---|---|---|---|---|
| dragons_breath | 1 | 9.00 | 32.0 | 5.0 | 6/2.5s | 21.3 | 12.1 | |
| dragons_breath | 5 | 6.97 | 46.7 | 7.5 | 9/4.4s | 60.2 | 35.1 | blue_flame, held_breath, backdraft |
| fire_eater | 1 | 6.50 | 64.0 | 8.8 | 14/6.1s | 118.2 | 62.7 | blue_flame, held_breath, backdraft |
| molotov | 1 | 2.40 | 8.0 | 10.0 | 4/1.8s | 3.3 | 10.0 | |
| molotov | 5 | 2.11 | 8.0 | 10.0 | 5/4.2s | 3.8 | 11.5 | accelerant, methanol, oil_slick |
| moonshine | 1 | 2.00 | 10.0 | 12.0 | 5/4.2s | 10.0 | 18.0 | accelerant, methanol, oil_slick |
| boomstick | 1 | 1.40 | 6.0 | 6.0 | | 21.4 | 21.4 | |
| boomstick | 5 | 1.26 | 9.4 | 6.0 | 4/1.8s | 95.1 | 45.0 | dragons_breath (the Boomstick's fire mutation), birdshot_lane, both_barrels |
| blunderbuss | 1 | 1.00 | 9.0 | 10.0 | 10/4.0s | 291.6 | 65.3 | the same |
| guitarra | 1 | 1.40 | 14.0 | 6.0 | | 30.0 | 10.0 | |
| guitarra | 5 | 1.55 | 22.8 | 12.0 | | 44.0 | 14.7 | tinnitus, far_reach, music_slap |
| requiem | 1 | 1.54 | 24.0 | 9.8 | | 46.8 | 15.6 | the same |
| hammer | 1 | 2.40 | 20.0 | 4.6 | | 25.0 | 8.3 | |
| hammer | 5 | 2.40 | 31.3 | 6.3 | | 117.2 | 39.1 | thors_wrath, giant_slayer, aftershock |
| revolver | 1 | 1.00 | 20.0 | 14.0 | | 20.0 | 20.0 | |
| revolver | 5 | 0.79 | 48.8 | 14.0 | | 258.5 | 258.5 | silver_bullet, hip_shot, trick_shot |
| turret_buddy | 1 | 6.00 | 4.0 | 8.0 | | 12.0 | 12.0 | (the next slowest weapon) |
| iron_bastion | 1 | 5.00 | 6.7 | 10.0 | | 20.2 | 20.2 | (the next slowest evolution) |

Where it stands among the 24 weapons in play ("decent damage", the brief: the middle at level 1):
- Level 1: **13th of 24 from the bottom on both columns** (the median: dps 21.3 beside the Boomstick's 21.4 and the
  Revolver's 20.0; 1-target 12.1 beside the Sun Scepter's 12.7 and the Turret Buddy's 12.0).
- Level 5 with its path: 6th of 24 (dps 60.2 against a median of 113; 1-target 35.1 against 67): the estimate counts 3
  creatures in the cone and Blue Flame's −20%; without the path 75 dps (10th). In a stage-2 crowd the 60° x 6 m cone
  holds more than 3, see the probe below.
- The Fire Eater: 8th of 24 evolutions (118 dps; the strongest, the Golden Revolver, 650); never above the strongest.

#### Measured in play (game/tools/difficulty_probe.gd; the Drifter's fixed builds with the Dragon's Breath in the Peashooter's slot)

Builds b1x / b2x / b3x (tools/difficulty_probe.gd BUILDS, the lane's rows): b1 at 5:00 with a quarter board (mirror
1.5), 130 s windows, two seeds; b2 at 14:20 inside Nightfall's window (stage=1) and b3 at 21:30 inside Blood Moon's
(stage=2), half a board (mirror 3), seed 11. "dealt/s" is the build's whole damage a second over the window; "lost/min"
the HP lost a minute in max-HP units net of healing. The probe is not deterministic (0.4 maxHP a minute between runs of
one seed): read the pairs together.

| window | build (the fifth slot) | seed | lost/min net | kills/min | dealt/s | DPS45 at the end |
|---|---|---|---|---|---|---|
| 5:00, a quarter board | b1: Peashooter L1 (est 11) | 11 | 0.65 | 193 | 549 | 535 |
| | | 12 | 1.09 | 180 | 433 | 234 |
| | b1x: Dragon's Breath L1 (est 27) | 11 | 0.90 | 196 | 498 | 436 |
| | | 12 | 0.28 | 193 | 512 | 485 |
| 14:20 (Nightfall), half a board | b2: Peashooter L3 + 2 mutations (est 91) | 11 | 0.00 | 692 | 3,795 | 2,533 |
| | b2x: Dragon's Breath L5 + its path (est 127) | 11 | 0.00 | 983 | 5,278 | 5,450 |
| 21:30 (Blood Moon), half a board | b3: Peashooter L5 + 2 mutations (est 268) | 11 | 0.00 | 1,873 | 5,568 | 6,116 |
| | b3x: the Fire Eater (est 369) | 11 | 0.00 | 1,937 | 5,306 | 5,499 |

Read: at level 1 the breath is a level-1 Peashooter (the pairs overlap within the probe's noise: kills 193-196 against
180-193, damage 498-512 against 433-549 a second). At level 5 with its path, in a 200-strong Nightfall crowd, the
build deals **39% more a second (5,278 against 3,795) and kills 42% more a minute (983 against 692)** than with the
Peashooter's slot: the 60° x 7.5 m cone holds far more than the estimate's 3 creatures, so "decent damage" at 1 and
strong at 5 hold in play even though the pause-screen estimate ranks it 6th of 24 at 5. The Fire Eater in the Blood
Moon window is a level-5 Peashooter's slot (−5% damage a second, +3% kills, one seed: the same within noise) beside
the Golden Revolver, Whirlwind and Saw Halo that carry that build; it stands 8th of 24 evolutions by the estimate,
never above the strongest. Nothing in the pairs changes the HP lost (every window at 0.0 net past 14:20 with half a
board).

The lead may want to change: the estimate's BREATH_CATCH (3) undersells the breath in a crowd (the b2 pair says 10+
in the cone); 4-5 would put the pause screen's number and the bot's card score nearer what it does, at the cost of
overstating it on a thin crowd (the brief asked for a conservative middle at level 1, which 3 gives).

### 41.WORLD Regular creatures despawn out of view; the Magnet power-up as a timed wide pull

#### Despawn: regular creatures far from the hero and out of view go (map `timeline_data.despawn`)
Garry: "in Vampire Survivors certain enemies despawn if the player walks far enough from them. Let's do that as well.
This, of course, only applies to regular enemies, not all of them. Also, we need to make sure that the despawning
happens out of Player's view. So never when enemies are above him. When enemies despawn they leave nothing behind."
Vampire Survivors moves a far creature to the other side of the screen; Megabonk's crowd stays near the hero. Ours vanish
and their rows spawn again near him, which is the same crowd density with no teleporting bodies.

- **Who**: a regular creature only. Never the boss, an Elite by its kind, one wearing an Elite modifier, a special type
  (the gear badge: the Vulture Raider, the harpooner, the Saiga Sniper), a coloured variance special, a boss's summon
  (a brood, an eruption's young) while its boss lives, a training dummy, one held by the Gravity Gun, roped, in the air
  (a launch, a toss, a bounce), still rising out of the sand or sinking into it, or dying already.
- **When**: every `every` = 0.5 s a pass over the crowd (at the top of the creatures' physics tick, before the grid is
  built, so a freed slot is never in that tick's cells). A creature goes when ALL hold: farther than `distance` = 40 m
  (flat) from the hero; OFF the screen by the camera's own frustum test grown by 1 m at his feet (EnemyManager
  refresh_onscreen, half the crowd refreshed a tick; without a camera that can say (tests, tools) everything counts as
  on the screen, so nothing ever goes); older than `grace` = 6 s since its spawn. `keep_share` = 0: none of the ones
  that could go is spared (above 0, that share is spared at each check, rolled again at the next).
- **What**: it vanishes at once: no death animation, no blood, no XP, no coins, no drops, no chest, no kill count, no
  quest progress, no analytics kill, no corpse, no `creature_dying` / `enemy_died` signal. The live counts drop as for
  a death (`count_alive`, the cap's load, `alive_of` for a row's max_alive, Endless's room), so the director's rows
  spawn again near the hero on their next check. Counted in the run record (`despawned`, by creature).
- **Where it is off**: the debug arena (creatures are spawned there to be looked at); a manager without a director
  (tests, tools) unless one calls `set_despawn`.
- **Room for a boss** (pass 107 fix, EnemyManager.spawn_boss / `_room_for_boss`): the map's `hard_cap` (500) is above
  the pool's 320 bodies (EnemyManager.MAX), so a late crowd fills every slot, and a cleared field's bodies keep theirs
  while their deaths play. A boss that finds no free slot now takes one: the dying body nearest its end goes at once,
  else the regular creature farthest from the hero vanishes as a despawn does (on or off the screen, whatever its age),
  else the farthest creature that is not a boss. Before, the boss simply did not come while the director had begun its
  fight (the clock stopped, the Brander's ring up and gone): the stage never reached its portal or Endless.
- **The older rule it replaces for regular creatures** (found by the probe, undocumented until now: WaveDirector
  `_cull_behind`, every 0.5 s, since an early pass): anything more than 30 m BEHIND the hero (behind = more than ~107
  degrees off his facing; never the boss, the Elite boss or an artillery creature) was moved up to a fresh spawn point
  19-24 m from him, in front, wherever it was and whatever it was (a coloured special, an Elite modifier, a boss's
  brood, a held one) and whether or not it could be seen. With the despawn rule ON, a regular creature
  (EnemyManager.despawn_kind) is left to the despawn rule and NEVER moved up (it walks after him, and goes at 40 m out
  of view); the ones the despawn rule never takes (a special type, a coloured special, an Elite modifier, a summon of a
  living boss, one held, roped, in the air or rising) are still moved up at 30 m behind, as before. With the rule OFF
  (`enabled` false, the arena) `_cull_behind` plays as before for everyone. Why: Garry asked for "despawn ... leave
  nothing behind"; the move-up is a teleport that keeps the crowd on him however far he runs, which is not that; and the
  probe showed no creature ever gets 40 m away while the move-up runs, so the two cannot both play on the same creature.
- **Why 40 / 6 / 0.5**: the screen shows about 12 m to the sides and 20 m up and down at the run's zoom (plus the 1 m
  margin); the roster's rings come at 18 m, the sides' bursts 19-24 m out, the Saiga Sniper stands off at 26 m (a
  special: excluded anyway); a teleport jumps 40 m, so the crowd left behind goes on the next check. 6 s of grace keeps
  a burst that landed behind a running hero (5 m/s: 30 m in 6 s) from being thrown away before it had a chance. Half a
  second between checks is the director's own spawn cadence (Red Canyon's spawn check is 0.7 s).
- **Measured** (game/tools/_p95_WORLD_probe.gd, a 120 s headless run of the real game on Red Canyon stage 1, the
  Drifter in god mode walking a square 25 s a side at his walking speed, so the crowd is left behind on every leg; the
  probe reads the crowd itself every frame and judges with the camera's own frustum test, not the manager's flags;
  log tools/dl/p95/WORLD/probe2.txt): **176 creatures despawned in 120 s** (Lesser Scorpion 77, Skeleton 68, Skeleton
  Knight 31: the regular rows of the first two minutes; no Elite, special or summon), the probe's own count of
  creatures gone without a death 176 (= the manager's), **0 violations** (not one went while on the screen or within
  40 m); the farthest living creature stayed at 33-41 m (40.7 m at most: the 40 m line plus the half second between
  checks) where it had been 30 m with the old move-up; alive 27-81 against a cap of 150, and after every walk-away the
  rows refilled (past half the cap after a despawn: yes; the least alive right after one: 13, at the end of the
  longest leg). About 1.5 creatures a second go while he walks away at 5 m/s, none while he stands (t 65-75 s of
  probe1, the same walk with the rule off: 0 despawned, the farthest never past 31 m, because `_cull_behind` kept
  moving the crowd up in front of him).

#### The Magnet power-up: a timed wide pull (content/pickups/magnet_pulse, effect `magnet`)
Garry: "Magnet - should not pull everything. Should just affect a big area and work for a time (like 10s) maybe. For
that time there should be a 2d magnet icon floating around the Player and the usual UI elements indicating that Player
is 'magnetizing' things in that moment. The area of effect should be quite big, around 2.5 times larger than the Magnet
Epic Item. Making the player move around and such."

- **Reach**: `params.radius_mult` = 2.5 × the reach the Magnet card gives at its level 1 (its `xp_pull_radius` add,
  read from the card at run time, so the power-up follows the card: 5 m before this pass = 12.5 m; lane PASSIVES'
  retune of the card's level 1 to 6 m = **15 m**, which is what the capture shows). Flat distance from the hero's feet.
- **Time**: `duration` = 10 s on the buffs' clock (it stands still through a pause), × the Pocket Watch's
  `powerup_duration` (1; 1.75 at level 5) × the hero's `buff_duration` (Solenne's Magic Hour 1.25), like Sprint, Berserk
  and the Shield. A second Magnet while one runs ADDS its seconds to what is left (the only timed power-up that extends
  rather than restarts: a second Sprint restarts its clock; a magnet thrown away would read as a bug).
- **What it pulls**: every tick, every EXP gem and every coin lying on the sand within the reach sets off for the hero
  on the magnet arc (pass 60's big-pull look). Never a chest, a power-up, a vacuum gem (the Elite's white gem: its own
  pull would take the whole map, which is what the old Magnet Pulse did), nor a gem still falling (it is taken the
  moment it lands). Walking about gathers more: the reach travels with him.
- **Shown**: the HUD's power-up plate with the seconds left (the pickup's icon, as Sprint's); the 2D magnet (the
  pickup's own icon, 0.8 m, orbiting his feet at 1.3 m and 1.55 m up, 1.4 rad/s, bobbing 0.12 m) with up to three faint
  dashed field lines curving to the nearest gems on their way (then to the nearest ones lying up to 1.6 × the reach
  away: where to walk), their dashes crawling towards the magnet, a spark every 0.12 s; a faint ring at the reach (0.45
  s) at the start and then every 0.6 s while anything came; the icon blinks over its last 1.5 s as a power-up on the
  ground does; the "pk_vacuum" sound at the start; "Magnet wore off" with the other buffs. The toast says the reach and
  the seconds from the data: "MAGNET: gems and coins within 15 m for 10 s".
- **The bot** prices it as it priced the Magnet Pulse: by the XP lying (BotGoals.powerup_value "vacuum" / "magnet").
- **Pickup weights, lifetime, colour, icon**: unchanged (weight 2, 40 s on the ground, #FFB52E).
- **What is gone**: the old Magnet Pulse's whole-map vacuum (coins and chests too). The Uber Magnet structure, a boss
  chest's opening and the Elite's vacuum gem still pull the whole map (`vacuum_all`).

### 41.BOSS The King's tumbleweed trail and three-stomp jump; the Scorpion Elite's tail sniper

#### The King's stomp (content/bosses/tumbleweed_king, row `stomp`; EnemyManager `_stomp_*`)
- The old `slam` row (one blast of 30 in 6 m after a 1.2 s wind-up) is now `stomp`: the same 1.2 s wind-up and ring,
  then a jump (2.2 m high: 0.35 s up on an ease-out, 0.2 s down on an ease-in) and a landing, three times, 0.45 s on the
  ground between a landing and the next hop. Landings come 1.0 s apart (gap 0.45 + up 0.35 + down 0.2); the first
  lands 0.55 s after the wind-up. The whole attack: 1.2 + 0.55 + 2 x 1.0 = 3.75 s, then the King's cooldown_between
  (2.0 s) as before.
- Damage a landing: 18 = 60% of the old slam's 30, in the same radius 6 m (+ 0.5 m for the hero's body), x the boss's
  stage x hero-level x host factors as every scripted attack. Danger against before: a hero who stands in the ring for
  all three takes 54 (x1.8 the old slam); one who walks out as the first lands (5 m/s, from the King's 2.2 m body to
  past 6.5 m: about a second) takes one or two (18 to 36); one who leaves during the wind-up, as before, takes none.
  The ring warns before every landing (the wind-up's 1.2 s for the first, then 0.55 s for the hop, then 1.0 s after
  each landing for the next), so the dodge is read, not guessed. In practice (the capture, the sim's bot) one landing
  is the common outcome: a touch under the old slam's 30.
- Push: knockback 6 as a special push (pass 89's hero_special_knock share, 0.5 on Red Canyon: 3 m/s), per landing; a
  row with `lift` throws instead (none in content).
- The pace knob and a hamper stretch the hops and gaps as they stretch a wind-up (the attack clock x pace: EnemyManager
  `pace` = Run.move_pace() x the timeline's creature_speed_mult: Red Canyon's 0.9 x 0.9 = 0.81). In the arena capture
  at that pace the landings came 1.25 s apart (75 frames at 60 fps) and the three took 3.75 s after the wind-up; at
  pace 1 they come 1.0 s apart as above.
- The landing's wave: a band of light racing out to 6 m over 0.5 s (Telegraphs.race_ring, width 0.3 of the radius), the
  ring's flash 0.4 s, Fx.stomp_dust (a ring of puffs covering about 0.6 of the radius, a column, 12 grains, 8 clods),
  a camera kick 1.2 (the old slam's shockwave was 1.0), the boulder's landing thud. Cosmetic.
- The `slam` script itself is unchanged (the Hammer Giant's, custom slams).

#### The Scorpion Elite's tail sniper (content/enemies/dune_scorpion, row `tail_sniper`; EnemyManager `_tail_*`)
- A fourth attack in its rotation (burrow, slam_at, spit_volley, tail_sniper; cooldown_between 4.5 s unchanged) with
  `chance` 0.7: as its turn comes it plays 7 times in 10, else the rotation moves on to the burrow. Its share of the
  Elite's attacks: 0.7 / 3.7 = 19%; about one attack in five. Skipped while the hero is within 5 m (`min_range`): up
  close its slam and burrow are the threat.
- The sequence: a 0.5 s wind-up (it stops), then frozen: aim 1.0 s (8 red lines gathering from the tail tip over a 40
  degree cone, following the hero) + lock 0.4 s (the line stands still: the time to step off it) + the beam, then 0.6 s
  frozen; three times: 3 x (1.0 + 0.4) + 3 x 0.6 = 6.0 s frozen in all, the beams 2.0 s apart. Each aim starts afresh
  at where the hero stands, so a hero who keeps moving across the line is missed by the beam he dodged and aimed at
  again by the next. All x 1/pace (the same creatures' pace as the stomp: the capture at Red Canyon's 0.81 had the
  beams 2.5 s apart).
- Damage a beam: 2 x the Saiga Sniper's base = 2 x (the Vulture Raider's rocket 22 x 0.7) = 30.8 before the Elite's own
  stage x hero-level x host factors (the Saiga's 15.4 before its own); against the Drifter's 100 HP at stage 1, level 1:
  three beams on a standing hero = 92.4, nearly a kill; one dodged = 61.6. The beam's knockback 5 as a special push
  (share 0.5), hit info "tail beam".
- The crowd on the beam's line: 5% of max HP each (at most 40) and a 3 m push aside, the Saiga's rule (the Elite thins
  its own escort when it fires through it).
- Nothing spoils the run but a stun, a freeze, a launch, a grab, hiding or death (the Saiga's spoil-on-hit does not
  apply: an Elite is under fire the whole time). After the run its own charge waits at least 0.8 s (TAIL_CHARGE_REST).
- Reading: identical to the Saiga's shot (SniperFx: the gathering lines, the lock, the laser, the sparks), from the
  tail tip (muzzle up 2.0 m at its size 3, 0.4 m behind the body along the aim).

#### The King's tumbleweed trail (content/bosses/tumbleweed_king, the volley row's `trail`; ProjectileManager TUMBLE_TRAIL)
- Cosmetic: every tumbleweed of the volley lays a dust ribbon in the tracers' ring (style "line": a soft band that
  widens x1.9, lifts at 0.45 m/s and greys like smoke over its life), a warm dark sand #7A5A30 at alpha 0.58, 0.5 m
  wide, 0.75 s life, a segment every 0.3 m rolled (0.6 m on a busy screen), from the ball's foot (0.35 m under its
  centre), and a real dust puff every 0.11 s (Fx.roll_dust, thinned on a busy screen). Twelve tumbleweeds x 2.6 s:
  about 160 live segments at most in the 2048 ring (the capture: 600 segments laid, 264 puffs over the volley).
  The first capture's darker, longer ribbon (#5C3F1E at 0.72, 0.55 m, 0.9 s) read as twelve shadow spokes at phone
  size, so it was lightened and shortened; the code default and the King's row carry the same numbers. Nothing in
  the sim.
- Pass 45's bead at the foot (tan at alpha 0.4: invisible on the sand) only remains for a trail of style "none".

#### New common attack key
- `chance` (0..1) on any `boss.attacks` row: rolled as the attack's turn comes; a miss skips to the next attack (the
  range skips' loop). Without it an attack always plays, as before.

### 41.VACE VACE frame repair in the Level Editor: the frames store, the Frames view, history, cross-look, export

No game rule, number or content value changes in this lane: the frames store, the Frames view and the VACE repair are
tooling. A look's strip changes only when Garry presses Export, and then only the frames he chose; the entry keeps
its anims counts, strip_cols and fps (head is measured again from the idle and run frames, as every landing does).

Tool thresholds, for the record (tools/frames_store.FLAG_RULES, hints on the sheet, never a verdict): jump 1.7 (a
frame differs from both neighbours 1.7x more than they differ from each other, and more than twice the median
step), footprint 0.72-1.35 of the group's median box, seam 2.2x the median step (loops), silhouette IoU under 0.5
against the driver's frame, empty under 0.4% of the cell.

## 42. Pass 96 (v0.81): the art-production loop (tools only; no game numbers)

Garry's word (tools/dl/p96/REQUEST.md): proceed with the approved plan, break nothing. Each lane's rules.

### 42.GATES Phase 0: the VACE window benchmark and profiles; the blind calibration set and the tier table

Tools only: nothing here changes the game. The numbers are measured (tools/dl/p96/GATES/bench/, tools/dl/qa_bench/results/).

#### G1: the VACE repair benchmark (tools/vace_bench.py)

**What a run is.** One `vace_repair.repair()` of existing cached frames (no re-walk, no new painting) on a copy of the
frames store (tools/dl/p96/GATES/bench/store; Garry's tools/dl/frames is never written), one subprocess a run so the
comfy lock is free between runs.

**The classes and their looks.** ctl = Desert Spider SP-B run/side (the demo's slots 3, 4, 5, 9; seeds 24110 and 7);
pose = Goblin GOB-D run/front (Wan Animate on the OpenPose driver bigguy_goblin); free = Buckshot Dwarf BD-A run/front
(creature_free2, no driver: a free fill, grey guide); cell = Red Goblin RG-A run/front (a recipe-less base: cells only,
no clip, no still: the reference is the fullest kept frame; free fill); mask = SP-B run/side slot 5 with a rectangle
over its front legs (the lower-left 45% x 55% of the figure's box).

**The matrix (27 runs).** ctl: window single (13 frames) / double (25) x strength 1.0 / 0.7 x the 4-step lightx2v LoRAs
at cfg 1.0 / 20 steps without them at cfg 3.5, two seeds = 16; pose and free: single / double x two seeds = 4 each;
cell: single / double, one seed = 2; mask: double, LoRAs, one seed = 1. The cheap runs go first, the 20-step runs last.

**The checks per redone slot** (E4's list, deterministic, no eye), on the composition with the run's versions staged:
- `empty`: no `empty` flag (the figure covers at least 0.4% of the cell);
- `jump`: no `jump` flag (frames_store: differs from both neighbours more than 1.7x their difference from each other and more than twice the median step);
- `footprint`: no `footprint` flag (the figure's box within 0.72-1.35 of the group's median; or shrunk to fit);
- `silhouette`: no `silhouette` flag (IoU against the driver's frame under 0.5), only where a driver exists AND the flag does not fire on more than half the installed frames of the group (the pose class: a stick figure against a body is always under 0.5: skipped and said);
- `seam`: when slot 0 or n-1 is redone, the seam flag on the last slot unchanged (never applies to the demo's slots);
- `area`: the figure's alpha area within 0.72-1.35 of the group's median (the effective cells);
- `colour`: the distance of the frame's figure to the view's still (a 6x6x6 RGB histogram of the pixels with alpha over 127, half the L1 distance; the still keyed as the clip's reference; with no still, the fullest kept frame) at most **1.25 x the kept frames' median distance** (`vace_bench.COLOUR_TOL`).

**Score of a run** = checks passed / checks over the redone slots (the brief's rule); `clean` = slots that pass every
check / slots (the stricter number, reported beside it); lone = a redone slot with no redone neighbour (slot 9), span =
the rest (3, 4, 5), scored apart.

**Why the colour check is an RGB histogram, not the hue histogram E4 names.** On the demo's pairs (the real store's
SP-B-2 / SP-B-3 versions, lane VACE's verdicts: 3, 4 good; 5, 9 bad on both seeds) the saturation-weighted hue
histogram put the GOOD repairs farther from the still (0.174, 0.187) than the bad ones (0.061-0.148), so it cannot be
a check. The RGB histogram does separate them: installed frames 0.275-0.350 (median 0.305), good repairs 0.342 /
0.371 (1.12x / 1.22x the median), bad 0.413 / 0.424 / 0.530 / 0.560 (1.35x-1.83x); the bad ones are also paler (mean
saturation 0.69-0.75 against 0.77-0.78). The tolerance 1.25 passes the two good and fails the four bad; it is set on
four points and says so (tools/dl/p96/GATES/calibrate_checks.log, spb_pairs.png).

**Choosing the profile per class** (`vace_bench.choose`): the best mean score over the seeds; two profiles within 0.02
(`TIE`) are a tie and the cheaper render wins; a class whose best mean score is under **0.6** (`PASS_MIN`) is not
reliable: `vace` stays (or becomes) `conditional` and its escalation is `["reroll_view"]`. A reliable class's escalation
is the plan's fixed ladder `["single", "double", "reroll_view"]` (INTERFACES; the profile's window says where a
hand run or an "auto" job starts, the ladder where the loop climbs when a repair did not help). The brief's
0.6 is a low bar with this check set (a run whose four slots all fail the colour check still scores about 0.83: the
other checks pass almost always), which is why `clean` is reported beside the score and the lead may pin a stricter rule.

**The profile's precedence in vace_repair.** An explicit argument (--window/--strength/--steps/--cfg/--lora) > the
method class's profile (methods.json) > the clip's own `wan` settings > pass 95's defaults (auto window, 1.0, 4 steps,
cfg 1.0, LoRAs on). A Level Editor repair job passes only its form's `window` ("auto" = the profile).

**The escalation rungs** (`vace_repair.next_rung`): `escalation[0]` first; after a rung whose repair's checks are no
better than before, the next; after the last, None (the loop stops repairing that group). `reroll_view` is not a repair.

##### The benchmark table

| class | window | strength | sampler | seeds | score (mean) | min | clean slots | render s | upload MB |
|---|---|---|---|---|---|---|---|---|---|
| ctl | single | 1.0 | 4-step LoRAs, cfg 1 | 2 | 0.959 | 0.917 | 0.875 | 122.0 | 1.65 |
| ctl | single | 0.7 | 4-step LoRAs, cfg 1 | 2 | 0.812 | 0.792 | 0.0 | 115.4 | 1.65 |
| ctl | double | 1.0 | 4-step LoRAs, cfg 1 | 2 | 0.916 | 0.875 | 0.5 | 137.75 | 2.88 |
| ctl | double | 0.7 | 4-step LoRAs, cfg 1 | 2 | 0.916 | 0.833 | 0.5 | 138.05 | 2.88 |
| pose | single | 1.0 | 4-step LoRAs, cfg 1 | 2 | 0.95 | 0.9 | 0.75 | 119.05 | 1.74 |
| pose | double | 1.0 | 4-step LoRAs, cfg 1 | 2 | 0.95 | 0.9 | 0.75 | 141.1 | 3.02 |
| free | single | 1.0 | 4-step LoRAs, cfg 1 | 2 | 0.9 | 0.9 | 0.5 | 123.9 | 2.5 |
| free | double | 1.0 | 4-step LoRAs, cfg 1 | 2 | 1.0 | 1.0 | 1.0 | 139.8 | 4.28 |
| cell | single | 1.0 | 4-step LoRAs, cfg 1 | 1 | 0.9 | 0.9 | 0.75 | 113.3 | 1.64 |
| cell | double | 1.0 | 4-step LoRAs, cfg 1 | 1 | 0.85 | 0.85 | 0.25 | 135.1 | 2.95 |
| mask | double | 1.0 | 4-step LoRAs, cfg 1 | 1 | 1.0 | 1.0 | 1.0 | 144.7 | 3.03 |
| ctl | single | 1.0 | 20 steps, no LoRA, cfg 3.5 | 2 | 0.959 | 0.917 | 0.875 | 197.75 | 1.65 |
| ctl | single | 0.7 | 20 steps, no LoRA, cfg 3.5 | 2 | 0.958 | 0.958 | 0.75 | 191.6 | 1.65 |
| ctl | double | 1.0 | 20 steps, no LoRA, cfg 3.5 | 2 | 0.938 | 0.875 | 0.75 | 315.05 | 2.88 |
| ctl | double | 0.7 | 20 steps, no LoRA, cfg 3.5 | 2 | 1.0 | 1.0 | 1.0 | 314.6 | 2.88 |

Chosen (written into methods.json 23:04, the ladder fixed 23:20): ctl double / 0.7 / 20 steps no LoRA cfg 3.5; pose single / 1.0 / LoRAs; free double / 1.0 / LoRAs; cell single / 1.0 / LoRAs; every class's escalation the fixed single -> double -> reroll_view (the other window's score: ctl single 0.958 at the same strength and sampler, pose double 0.95, free single 0.9, cell double 0.85). Every class is over 0.6: no rule became conditional. The ctl pick costs 315 s a repair against 122 s for the LoRA single window at 0.959: `vace_bench.TIE` 0.05 would pick the cheaper one.

#### FLAG_RULES: changed nothing, and why (tools/dl/p96/GATES/flag_rules_tune.log)

The only frame-level ground truth with neighbours is SP-B run/side with the demo's versions. Each demo version staged
ALONE among the installed frames (the loop's case) and judged by the geometry flags (jump, seam, footprint, silhouette,
empty) over a sweep of jump 1.2-2.0, silhouette 0.5-0.7, footprint (0.72-1.35) / (0.8-1.25) / (0.9-1.12):
- at today's rules the four bad versions are all missed (jump scores 1.24-1.46, IoU 0.52-0.60) and the two GOOD repairs
  are both flagged `jump` (scores 2.67 and 3.72: a clean repaint differs more from its ghost-legged neighbours than a
  pale tangle does);
- a silhouette threshold of 0.6 catches the four bad ones but flags 11 of the 12 installed frames (their IoU against the
  depth driver sits under 0.6: the painting walks at its own size, pass 94's finding);
- no setting lowers the misses without a new false alarm: **FLAG_RULES stays as it is** ({jump 1.7, footprint 0.72-1.35,
  seam 2.2, silhouette 0.5, empty 0.004}).
Consequence for the loop: a `jump` on a single repaired slot among untouched neighbours is NOT evidence against the
repair; the colour check is the one that separated good from bad on this set. The flags remain hints.

#### G2: the blind set and the tiers (tools/qa_bench.py, tools/qa_bench/manifest.json)

**The set.** 39 cases under blind ids C01..C39 (a fixed shuffle, seed 96): part D3's 16 (9 Klein side stills: SP-A/B/E/F/G
picks = clean, SP-F k0 9 legs, SP-H k1 11 legs, the cfg3 negative test ~9 legs, SP-G k1 skull face; 7 walk frames: SP-A v1
ghost legs 10, SP-D v1 face lost, SP-E unfitted ghost legs, SP-E fit 1 and fit 0.5 face lost, SP-E installed clean, SP-G
v2 clean), the SP-C v1 and SP-D v2 `before/` fronts (face lost; 3 frames), lane VACE's demo pairs (SP-B side slots 3-5
installed = ghost legs, SP-B-2 slots 3, 4 = clean, SP-B-2 5 = head reshaped + smears, SP-B-2 9 = pale tangle, SP-B-3 5
and 9 = worse: 9 frames), three other creatures' side picks (Dune Scorpion SC-D k0, Bull Beetle BB-C k1, Lesser Scorpion
LS-B k1: the still in use is the picked candidate by bytes and the look is in play = clean), and 8 weak cases (the
installed SP-C / SP-D fronts inferred clean from the pack decision; the six losers of those picks as "not chosen"). 31
strong cases = 19 defects + 12 clean; a say-clean evaluator scores miss rate 1.0, false alarms 0.0, clean-vs-defect 12/31.

**The rubric.** One text (manifest `rubric`): count the legs on each side, ghost legs, smears, the face (ok / missing /
wrong / n/a), notes; JSON only. The species' expected count is the only anchor ("a correct spider has exactly 8 legs, 4
on each side"); `--unanchored` replaces it with "count every leg you can see ... do not assume how many". Never a file
name, a status line or a verdict.

**Scoring.** legs = the exact count where one is recorded; ghost / face = the boolean where recorded; flagged = any of
(legs != the species' count, ghost, smears, face missing or wrong); miss rate = defects not flagged / defects; false-alarm
rate = clean flagged / clean; an empty or unparsable answer = no verdict (not flagged: a miss on a defect, never "ok");
agreement = the share of cases two runs of one model flag the same way (and with every field the same).

**The tier rule** (`qa_bench.tiers`): tier 0 deterministic on everything (the flags); tier 1 = the local model with the
best miss rate (ties: fewer false alarms, then faster) at zero cost, on flagged frames plus a sample; tier 2 = a cloud
eye on contact sheets at decision points, **off** (ceiling 0.0) until a key exists (tools/keys/anthropic.env or
gemini.env; the harness's own key is never used) and its blind numbers earn it; the pinned tier-2 id is
claude-haiku-5-5 (the cheapest current vision-capable model, $0.10 / $0.50 per MTok), off.

##### The evaluators' numbers (tools/dl/qa_bench/results/scores.md, 2026-10-21; 31 strong cases: 19 defects, 12 clean)

| evaluator (LM Studio on the PC's RTX 4070) | rubric | runs | miss rate (defects passed) | false-alarm rate (clean flagged) | legs right | ghost right | face right | clean-vs-defect | s / image | $ | run-to-run agreement (flag / every field) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| qwen2.5-vl-7b-instruct-abliterated | anchored | 2 | 0.474 (9/19) | 0.417 (5/12) | 14/22 | 38/50 | 32/56 | 34/62 | 1.1 (the first run 15.5 under VRAM pressure) | 0 | 1.0 / 1.0 |
| qwen2.5-vl-7b-instruct-abliterated | **unanchored** | 2 | **0.368 (7/19)** | 0.417 (5/12) | 14/22 | 38/50 | 36/56 | 38/62 | 1.6 | 0 | 1.0 / 1.0 |
| google/gemma-4-e4b | anchored | 2 | 0.605 (12/19, 11/19) | 0.167 (1/12, 3/12) | 13/22 | 38/50 | 34/56 | 35/62 | 8.2 | 0 | 0.923 / 0.872 |
| google/gemma-4-e4b | unanchored | 1 | 0.263 (5/19) | **0.833 (10/12)** | 2/11 | 19/25 | 17/28 | 16/31 | 8.7 | 0 | one run |
| a say-clean evaluator | | | 1.0 | 0.0 | | | | 12/31 | | | |

What the numbers mean (tools/dl/p96/GATES/qa_cases.log): the 7B answers "8 legs" for every spider whatever the picture
(9, 10, 11 legs all pass) and flags only a lost face or a smear; unanchored it still says 8 but calls two more lost faces
(C19, C28). Its five false alarms are the three scorpion stills (it calls the picked, in-play Dune Scorpion and Lesser
Scorpion faces "missing" every time), SP-G's clean v2 front, and the demo's two GOOD repairs (C10, C37: "face missing"
on a side walk). Gemma anchored flags little and misses most; unanchored it counts 6 or 12 legs on clean spiders and
flags 10 of 12 clean frames: a screen that passes nothing on. Neither sees a ghost leg (38/50 "right" is the say-no
baseline: 0 of the 7 ghost cases caught by either). Both are deterministic enough to trust a single run (the 7B exactly;
gemma on 92% of the flags).

**The tier table written** (request_defaults.json `tiers`): tier 1 = the 7B with the unanchored rubric (the best miss
rate among the configurations that flag at most half of the clean cases, `qa_bench.FA_MAX` 0.5: gemma unanchored is
out on that rule), on flagged frames + a sample, max_tokens 300; tier 2 = claude-haiku-5-5 on sheets, ceiling 0.0 (off;
no key). No tier earns single-frame escalation: none beats tier 0 + 1 on misses without new false alarms, as AI-07 asked.
The honest line for the request card: the local eye passes about 4 of 10 defects and flags about 4 of 10 clean frames;
the loop's provisional winner is a staged selection Garry approves, never an install.

#### G3: Gemini

No tools/keys/gemini.env: nothing was built beyond the key file's name and the refusal in `qa_bench.py run gemini`
(lane LOOP's adapter carries the GeminiBackend slot). When Garry buys the AI Studio key with billing, G3 =
`python tools/qa_bench.py run gemini <model> --repeat 2` through the adapter, then `score` and `tiers --write`.

### 42.REQ The request record, art_request.py and the routes; the cancel fix; the offline slice

These are tool rules, not game rules; they bound what the Auto-iterate loop may spend on one request.

- **The defaults** (Garry's point 8; `tools/level_editor/request_defaults.json` `budget`): 2 re-rolls per look, 2 repair
  rounds per animation x view, 5,400 s (90 min) of lane time, 60 evaluator calls, $0.00 of cloud spend. Every one can be
  set per request (`art_request.py start --rerolls --repair-rounds --minutes --evals --cloud-dollars`, or `POST
  /api/requests {budget}`) and globally in that file; a value under 0 reads as 0.
- **What counts**: a `requeue` or `reroll_view` op = one re-roll; a `repair` op = one repair round of its group
  (animation/view); an `ask` op = one evaluator call; lane seconds = the sum of the request's jobs' own clocks (started
  to ended, a running job to now, imports included); evaluator calls and dollars are recounted at every step from the
  findings' `model_calls` (the ops' `ask` count is a floor; a `charge` made outside the step is a floor too).
- **When the loop stops**: the moment the planner returns no op (the hard gates passed, or nothing more to try) the
  request waits for Garry's approval (stop early: no iteration is spent "to be sure"); any cap spent does the same
  with the reason on the record (lane seconds, evaluator calls, a cloud ceiling above 0, or BOTH re-rolls and repair
  rounds gone: with re-rolls gone and repair rounds left the planner may still repair, and the other way round). An op
  that would overspend its own unit is refused before it runs (no re-roll left, no repair round left for that group, no
  evaluator call left) and the request waits.
- **Iteration k of n**: n = re-rolls + repair rounds + 1 (the first landing), the card's and the CLI's "iteration 2 of 5".
- **One op per step; at most 8 direct ops in one step** (a note, a staging, the provisional pick chain inside one
  landing's step); a queued job ends the step until that job lands. Mode `step` pauses after every op.
- **Nothing automatic reaches the game**: the provisional winner is a staged selection; the export runs only on Garry's
  one confirm (`approve {confirm: true}`), covering the whole batch (staged frames + pinned re-applies); a fresh look is
  approved (its NEW mark dropped) in the same click.
- **A failed first job** with nothing landed fails the request; a failed export, or a failed import after it (the
  export rolled back by jobs.py), fails it too, with the reason; what landed before is kept.

### 42.LOOP The evaluator adapter, tiers, ledger and findings; the commands, the planner and the loop body

#### The tiers (vision_eval.evaluate_look)
- Tier 0 (deterministic, free) runs on every frame of every evaluated group: frames_store's FLAG_RULES (jump 1.7, footprint 0.72-1.35,
  seam 2.2, silhouette 0.5, empty 0.004; GATES may re-tune them) and gen_art's geometry on the paintings (empty; touches-edge = a margin
  under 12 px on the left, right or top, or under 20 px at the bottom; a bust may run off the bottom). These are the only HARD gates.
- Tier 1 (the local eye, free) sees the flagged frames plus ONE clean frame a group (the middle unflagged slot, the same every run), each
  three times its size on grey (110, 110, 120). Advisory only.
- Tier 2 (the cloud eye) runs only when the request's cloud_dollars > 0 AND (a hard finding exists OR the tiers disagree: a flagged frame the
  local eye called fine, or a clean frame it called broken); ONE contact sheet per decision point: the flagged slots and their neighbours
  (+-1), 160 px cells, numbered from 1, at most 6 a row. Advisory only.
- The gates: hard_failures = measured items not ok; advisory = model items not ok; pass = hard_failures == 0.

#### The ledger and the ceilings
- Every call and every refusal is logged (the newest 2,000 kept; the totals and the per-day totals kept whole).
- A cloud call is refused when: the model has no price row (unpriced); cloud_ceiling_dollars_per_day <= 0 (the default: off); the day's spend +
  the estimate > the day's ceiling; the request's cloud_dollars <= 0; the request's spend (from the ledger) + the estimate > its cloud_dollars.
- The estimate before a call: (1,500 tokens a picture + 400 + len(prompt)/3) x the input price + max_tokens x the output price.
- Prices ($/MTok, dated 2026-10-06): haiku-5-5 0.10/0.50, sonnet-5-5 2/10, opus-5-5 4/20, haiku-4-5 1/5, sonnet-5 2/10, opus-5 5/25 (cache reads
  at a tenth of the input price, cache writes at 1.25x: an estimate). Gemini: no row (G3 measures).
- The answer budget (max_tokens) per model: 220 by default, 1,200 for gemma / qwen3 / "thinking", 2,048 for claude / gemini; an explicit value wins.
- The cache key: sha1 of the pictures + the rubric id + the rubric text's sha1 + the model; a no-verdict answer is never cached.

#### The planner (loop.next_op), in order
1. No fresh findings (none, or older than the last landed job) -> ask; after an ask that gave no findings, or with no evaluator calls left
   -> select_provisional (never a second ask in a row).
2. hard_failures == 0 -> select_provisional once, then None.
3. Hard findings on frames of a repairable group (a clip or a driver) -> repair of the failing slots (as spans) at the first rung of the
   method's escalation (default single -> double -> reroll_view); the same slots failing after a repair with no lower hard count -> the
   next rung; a lower count -> the same rung again on what is left; after the last rung -> reroll_view; every frame of the group failing
   (slots >= n) -> reroll_view ("a new clip"); the group repaired / re-rolled twice without improvement -> reroll_view.
4. A hard finding on a painting, or on frames of a procedural group -> requeue with DEFECT_WORDS[field] joined (deduplicated) and seed =
   asset.seed + 7919 x (rerolls spent + 1) (gen_art.render's own stride between tries).
5. Candidates are tried cheapest first: repairs before re-rolls, a lower rung before a higher one, then by group name; a candidate without
   its budget unit is skipped; the plateau rule skips a candidate equal to the last iteration's op (verb + group + slots + rung/view/words).
6. Nothing left -> select_provisional, then None.

#### The commands
- Observe: no op. Auto / Step: requeue, reroll_view, repair, stage, copy, ask, note, select_provisional, stop. Never: export, install, default,
  approve, pin, unpin, remove, delete, unstage, shelve, variant, icon, merge, push_workflows.
- Budget units: requeue and reroll_view = 1 reroll; repair = 1 repair round of its group; ask = 1 evaluator call; the rest free. Counted by REQ's
  step function (requests.count_op), never by dispatch.
- repair never sends free_fill (a procedural group is refused by frames_io's own rule); its window = the rung (single | double); strength and
  steps come from the method's profile inside vace_repair (GATES).
- requeue lays the words on recipe.art_prompt (", " joined) and records them in recipe.loop_words; reroll_view moves the view's clip cache key
  aside through jobs.requeue (the walk seed moves as a hand re-roll's does).

#### DEFECT_WORDS (defect -> the words a requeue adds)
legs: "every leg fully drawn and attached, the right number of legs, no extra limbs"; ghost: "no ghost limbs, no faint or see-through duplicates
of any part"; face: "a clear face on the head with two eyes, no skull, no second face"; smear: "crisp clean line art, no blurred or smeared parts";
empty: "one whole figure centred in the frame, clearly visible against the flat background"; touches-edge: "the whole figure well inside the
frame with a clear margin on every side, nothing cut by the border"; broken, colour, silhouette, footprint, jump, seam: see loop.py.

### 42.PAGE The frame layer as Garry decided; the request card and the page's minimum

No game number, rule, cap or condition changed or added: this lane touched only the Level Editor (the frames store,
its routes, the page). Nothing for BALANCING.md §42.

Tool-side rules introduced (for the Level Editor doc, not the game): every export that replaces an installed strip
is confirmed once for the whole batch; a landing never displaces a pinned frame (a re-apply export, or an in-process
re-pack for a hand run); a pin past the new frame count or of another cell size is reported and kept, never guessed;
no frame version is ever deleted; the strip-backup cap of 30 per asset stays.

## 43. Pass 97 (v0.82): the live page (tools only; no game numbers)

Garry's word (tools/dl/p97/REQUEST.md): proceed with Phase 2. Each lane's rules.

### 43.LIVE Stable cards, the delta poll, hash routing, the look card's live block, the page side of progress, ops and health

No game number changed, no game rule added: lane LIVE touched only the Level Editor (tools/level_editor/) and its docs.
Nothing for BALANCING.md §43.

Page-side numbers (tool behaviour, not game balance), for the record:
- the delta's per-record bookkeeping is computed once per queue rev, at the first delta poll after it moved;
- the look card's history line asks GET /api/events at most once a minute per look while its stage shows;
- the Ops fold asks GET /api/ops?days=7 when opened and every 60 s while open;
- the page polls every 2 s while a look's live block shows a job (as on the Jobs tab), else 6 s (unchanged);
- the substage line says "(no tick for N s)" after 30 s without a tick.

### 43.PROGRESS ComfyUI's live progress, the events log and the archive, Ops, server.log, the error line

- **Progress lines** (tools/comfy.py): at most one `comfy: <prompt> <node> k/n` line per 2 s on one node (the newest
  state when the window opens; the 0.25 s receive tick flushes it), one at once when another node starts (the previous
  node's last unprinted step is dropped: the new node is the news), the error line at once. On only under a Level Editor
  job or with COMFY_PROGRESS=1. A failed or dropped socket: 1 + 2 tries (1 s, then 2 s apart), then quiet; /history is
  always the completion.
- **The substage** (jobs.parse_line): replaced by every step line; `since` kept while the node and prompt stay the same;
  removed when the job's stage name changes (a render or clip finished), at a new run, at the end. `comfy_error`
  cleared by a newer `comfy: prompt` line and at a new run. The step lines stay out of the card's short log tail.
- **The archive**: finished records (done, failed, cancelled) whose `ended` is more than 30 days old leave queue.json for
  archive/queue_<month ended>.json, at the editor's start (5 s after) and every 24 h, by the editor that runs the queue
  only; a record a live job points at (an import's after_export, a merged import's target) waits; a month file is
  written and read back before any record leaves; a failure leaves the queue whole. Requeue of an archived id puts a
  copy back in the queue.
- **The ETA**: the median seconds of the method's done (or waiting-after-a-phase) runs of at least 1 s that painted
  something (a still/clip/side stage with seconds; any run for kinds without such stages), per seed for a candidate set,
  from the live queue, once there are >= 5 of them; else methods.json's `time.median_s`; else BUILTIN_MEDIAN. Scaled by
  the pending stages as before. On the 468 rebuilt records: hero_pose5 244 s (15 runs; the tables say 570), import 30 s
  (98; 90), icon_cands 16.3 s a seed (219; methods.json 80), creature_proc 474 s (9; 90).
- **The error line**: the exception's own line or a tool's message (gen_art:, gen_ctl:, gen_edit_stills:,
  gen_badge_cands:, SCRIPT ERROR), else a line with asset_job:, "error" or FAILED, else "<how it exited> after: <last
  line>" (exit code N; a Windows crash code named: 0xC0000005 access violation, 0xC00000FD stack overflow, 0xC0000409
  stack buffer overrun, 0xC0000374 heap corruption, 0xC000013A console closed), newest first, on ANSI-stripped non-blank
  lines. On the 446 real logs: 440 as before; the 6 that differ were the ones whose old answer was an ANSI code alone.
- **Ops failure groups**: the sentence with numbers, hex codes, job ids and paths taken out (first 160 characters).
- **server.log**: 5 MB, three old files; **events.jsonl** rolled above 32 MB by the daily tick.

### 43.SAFE doctor.py, requirements.txt, ai_hosts.json, the console-close handler, Re-queue all, the request guard, net_check.py

No game numbers changed. Tool rules (for the record, none touches play):
- Re-queue all (`POST /api/jobs/requeue_interrupted`) takes the jobs the editor's last start marked interrupted (ended at
  or after the server process started), never runs on its own, and skips a Test in game (`launch`) job.
- The request guard: a POST needs a loopback Host (127.0.0.1 / localhost, the editor's port when named) and no foreign
  Origin (else 403); a JSON route's body needs Content-Type application/json (else 415); /api/upload keeps its raw body.
- The editor's doctor summary refreshes at most every 600 s, on a thread no request waits for.
- doctor.py warns under 10 GB free on the checkout's drive.

## 44. Pass 98 (v0.83): Gemini as the art checker (tools only; no game numbers)

Garry's word: Gemini first, the local model only as a surfaced backup. The rules:

1. **The order of the eyes** (Garry, 2026-10-22: "just use Gemini first. Then if there are errors with Gemini we use the
   local as backups"): tier 0 (deterministic flags + the stills' geometry) on every frame = the ONLY hard gates; then
   Gemini (tier 2, `antigravity`, gemini-3.8-flash-medium through Garry's Antigravity CLI) on numbered contact sheets of
   the flagged frames + one sampled clean frame per animation x view; the local LM Studio model (tier 1) runs ONLY on the
   frames of a Gemini call that failed. Applies whenever tier 2's eye is antigravity (the tier table's default since pass
   98, and every manual Gemini button). A job without tier 2 (tiers [0, 1], pass 96) still runs the local model first,
   unchanged.
2. **What counts as a Gemini failure (the local fallback follows)**: agy.exe missing; not logged in / no JSON from agy;
   a refused read (`denied_actions`); a timeout (print timeout 420 s, subprocess 480 s); an empty or unparsable answer;
   cells the answer skipped; the daily cap reached. NOT a failure: a request whose evaluator_calls are spent (those frames
   are "not asked", no fallback).
3. **The fallback is surfaced as an error**: findings `eye: "local (fallback)"` + `gemini_error`; a red line "Gemini
   failed: <reason> - checked by the local model instead" on the job card and on the request card; frame badges "Local
   (fallback)"; an events.jsonl entry (evaluator / fallback); the fallback calls' ledger rows carry the reason; the Ops
   line counts today's fallbacks. `fallback: false` on a job = no local call, the error still surfaced.
4. **Every model finding is advisory**: a badge with the model's name, never a gate, never a pass or fail of a frame.
5. **Gemini's daily cap**: 6 calls a day (the lead, after the quota ran out: Garry's subscription quota is weekly and about 40 single-picture calls emptied it; absent = 40) (`tiers["2"].daily_calls`), counted from the ledger (refusals and cache hits
   not counted; a failed call counts). One call = one contact sheet of at most **16 frames**. A request's
   `evaluator_calls` budget caps the sheets too (`calls_left` = budget minus spent when the ask is dispatched).
6. **When a request asks Gemini**: requests created from pass 98 on are stamped `eyes.tier2` (on when tier 2 is
   antigravity and `tiers["2"].requests` is not false; `brief.gemini: false` turns one off). Such a request asks tiers
   [0, 1, 2] at every check (the first one when the look lands); before select_provisional, findings made without tier 2
   get one more ask with it. Requests without the stamp plan exactly as in pass 96.
7a. **What a Gemini finding may drive (the blind bench, 2026-10-22, recorded in request_defaults tiers["2"]._measured:
    miss 0.0, false alarms 0.75, legs 2/11, ghost 22/25, face 21/28, ~91 s an image)**: a flagged cell's `defects`
    (vision_eval.defect_kinds) of ghost, smear or face (wrong / missing) may drive ONE repair of that frame in a
    repairable group (gates passing; never twice on the same frames; within repair_rounds) and puts its group first
    among the repairs; a leg count (or another defect) counts ONLY where tier 0's silhouette or footprint flag is on the
    same frame; a leg count alone is a badge only (its hover says the counts are unreliable).
7. **"Both eyes flag the same frame"** (a tier-1 and a tier-2 item, ok false, on the same group and slot; only when both
   actually ran, and the Gemini item counting under 7a): (a) among hard-finding repairs, that group goes first; (b) with the hard gates passing, ONE repair of
   the agreed frames of a repairable group (the method's first rung), never twice on the same frames, within the group's
   repair_rounds. Under rule 1 this is rare in the loop (the local model only sees frames Gemini failed on); in the
   Frames view it shows whenever Garry asked both (the red "both flag it" mark, the G+L cell mark).
8. **The cache**: the same sheet + rubric + model is answered from tools/dl/qa/cache (no call, not counted); the buttons
   may pass `fresh` to skip it.
9. **The sampled clean frame**: per group, the middle of the unflagged slots (the same choice as pass 96's tier 1).
11. **A spent subscription quota** (agy: "Individual quota reached ... Resets in <h m s>"; read from agy's JSON or its
    cli.log) is remembered in tools/dl/qa/agy_state.json until the reset: no Gemini call until then (refused at once, the
    local fallback runs and is surfaced), the buttons refuse with the date, the Ops line says "quota spent until".
    Garry's quota was spent by the blind benchmark on 2026-10-22 (39 single-picture calls): it resets about 2026-10-29 13:00.
10. **Measured**: one Gemini call on one picture took about 92-100 s in the blind bench (about 14,000 thinking tokens);
    the live proof's 4-frame sheet: see report_GEMINI.md.

## 45. Pass 100 (v0.85): build quests, the one-shot Phoenix, the stage look at the landing

Garry's words: tools/dl/p100/REQUEST.md. Each lane's rules.

### 45.QUESTS Unlock quests about levels, upgrades and evolutions

Garry (pass 100, "Meta Progression"): most unlock requirements are kill counts ("which is fine"); he wants more that ask
the player to reach a level with a given hero, upgrade an item (passive item, card, weapon) to a level, evolve an item.

#### The new rules (each is new; name them in BALANCING.md)

1. **Five build quests, all done in one run** (`QuestDef` header; `QuestTracker.run_progress` / `held_items`):
   `hero_level {hero, level}`, `item_level {kind, id?, level? | rung?}`, `evolve_item {id | kind}`, `weapon_paths {weapon?}`,
   `items_maxed {kind, count}`. They are read off the run's build as it stands, checked by the run's own once-a-second
   check, at the boss and at the run's end (`in_run`); the title's quiet check never completes one.
2. **An evolved form counts its source at the source's top level**: a weapon's evolution is its source at level 5, a
   Risen card its card at level 4. An evolution never undoes a level reached (the check runs once a second; a level-5 weapon
   evolved at a chest in the same second still counts).
3. **A passive item's "level" is its level number; its `rung` is the rarity rung.** Passive items climb the rarity ladder
   (pass 95), so level 3 is Rare for a common item and Evolved for an epic one. A quest that means "this good" names the
   rung (`rung`: uncommon, rare, epic, legendary, evolved) and then counts passive items only (cards and weapons never
   have a rung). `level` stays available and means the number.
4. **"Evolve" per kind**: a weapon evolves at a chest into its evolution; a card evolves into its Risen card; a passive
   item "evolves" onto its Evolved rung (its top level). An evolved form's id works in place of its source's.
5. **"Max level"** (items_maxed): a weapon at its max level or evolved, a card at its max level or Risen, a passive item
   on its Evolved rung. A one-shot item (top level 1: the Phoenix Feather, lane SMALL's `single`) never counts as maxed.
6. **weapon_paths** counts the weapon's path mutations (Registry.mutations_of: never a hidden one, never a hero's own),
   so "all three" is the same set the evolution needs; empty `weapon` = any weapon held.
7. **hero_level** counts only in a run with that hero (Run.max_level_reached).
8. **Progress**: the build quests show progress only while a run is on (the run record's quest before/after); outside a
   run they show none, like `reach_level` always has (the drawer and the Collection show no bar for them).
9. **Stage hints** (the Collection's "from stage N"): hero_level as reach_level (<= 12: 1, <= 24: 2, else 3); item_level 1
   (the Evolved rung 2); evolve_item 2 for a weapon (as evolve_any), 1 for a card or a passive item; weapon_paths 1;
   items_maxed 1 for one or two items, 2 for three or more.
10. **Save compatibility**: completion is stored by quest id (`Save.quests_done`), never by condition, so a quest done
    on a save stays done whatever its condition becomes; converted quests kept their ids.

#### Before / after (8 quests changed; every other quest is exactly as it was)

Kill quests before: 13 (12 in play + Mira's unattainable one; Dad's is hidden and kept). After: 6 (Adrenaline, Big
Mouth, Killer Bees, Lob Grenade, Tumbleweed, Mira) + Dad's hidden one. Converted: 7 kill quests (54%) and May's level quest.

Numbers used for "expected runs": the run sim (tools/dl/sim/runs: the Drifter with a quarter board reaches level 5 at
2:00, 8 at 4:00, 14 at 7:10 = the stage-1 boss; with no board the bot dies at ~2:30, level 5-6) and the path slots
(stage 1 offers a path mutation at 1:19, 2:20, 3:20, 4:20, 5:15, 6:05, 6:45). Garry's own played runs reach level 24-28
by 11-12 minutes. "Runs" means runs of a player aiming at the quest.

| Quest (unlocks) | Old | New | Why | Expected runs (old -> new) | Stage hint |
|---|---|---|---|---|---|
| unlock_sabre (Sabre, weapon) | Kill 40 Skeleton Knights (from 1:23) | Get the Orbit Saws to level 5 in one run (`item_level` weapon orbit_saws 5) | blade for blade: the Sabre is earned by maxing the spinning saws; the Orbit Saws is common, open from the start | 1-2 -> 1-3 | 1 -> 1 |
| unlock_haste (The Tower, card) | Kill 30 Bull Beetles (from 5:06) | Get a card to level 4 in one run (`item_level` card 4) | a card is earned by maxing a card; any of the open cards | 2-4 -> 1-2 (a touch earlier) | 1 -> 1 |
| unlock_overkill (Overkill, passive item) | Kill the Dune Scorpion (from 3:35) | Get a passive item to Legendary in one run (`item_level` passive, rung legendary) | the passive-item ladder quest: an epic item +1, a rare +2, an uncommon +3 | 1-3 -> 2-4 (a touch later) | 1 -> 1 |
| unlock_land_mine (Land Mine, weapon) | Kill 120 Fire Ants (stage 2, from 7:11) | Evolve the Salt into the Hiwa Kai (`evolve_item` salt) | ground for ground: the Salt lies on the ground like the mines; an evolution is a stage-2 goal like the old one | 2-4 -> 2-5 | 2 -> 2 |
| unlock_thirst (Death, card) | Kill 60 Dust Mummies (from 6:08) | Evolve Temperance into Temperance Risen (`evolve_item` mend) | healing to life steal: the heal card risen opens the drinking card | 2-4 -> 2-4 | 1 -> 1 |
| unlock_ricochet (Ricochet, passive item) | Kill 30 Spit Cactuses (from 4:17) | Take all 3 mutations of the Revolver in one run (`weapon_paths` revolver) | bullets that bounce, earned on the gun; the Revolver is the free Drifter's own; three path slots fall by 3:20 | 1-3 -> 1-3 | 1 -> 1 |
| unlock_fadeaway (Fadeaway, hero; 1,750 gold after) | Kill 3 Saiga Snipers (special, from 3:35) | Reach level 12 with Drifter (`hero_level` drifter 12) | a hero unlocked by levelling the starter; level 12 is about 5 minutes into a stage-1 run, early as before; his gold price is the real gate | 2-5 -> 1-3 | 1 -> 1 |
| unlock_may (May, hero; 2,500 gold after) | Reach level 30 in one run (any hero) | Reach level 30 with Calavera (`hero_level` calavera 30) | a hero unlocked by levelling another; Calavera is owned after the stage-1 boss and 300 gold, so no dead end; the level kept (Garry's 30) | late -> late (+1-3 runs: one hero) | 3 -> 3 |

Kept as they were (Garry's numbers untouched): Adrenaline (400 kills), Big Mouth (300 Armadillos), Killer Bees (40
Armadillos), Lob Grenade (200 Fire Ants in one run), Tumbleweed (150 Skeletons), Mira (unattainable), Dad (hidden), and
every non-kill quest (Jeżyk, Calavera, Solenne, the Eye, the Guardian, the Ghost, the Sage, Guillotine, Hammer, Spear,
Quickdraw, Rocket Pod, the Chariot, Turret Buddy, Zap Beam). `items_maxed` is built and tested but no unlock uses it yet
(Big Mouth was the candidate: "Hold 3 weapons at max level at once" would fit it if Garry wants another conversion).

The quest-locked share (pass44_test's band) is unchanged: 23 locked base items, the stage spread 14 / 8 / 1 (61% / 35%
/ 1), the same as before (every converted item quest kept its stage hint).

#### Chains (no dead ends)

Every name in a condition is in play and can be had: the Orbit Saws, the Salt, Temperance (mend) are open from the start;
the Revolver is the free Drifter's; the Drifter is free; Calavera is unlocked by the stage-1 boss (a boss quest) and
bought for 300 gold. pass100_QUESTS_test walks the chain from a new save and reaches every quest in play.

#### Open for Garry

- Fadeaway's level (12) and May's (30 with Calavera) are first guesses; the Level Editor's hero Requirement edits them.
- Overkill now asks for a Legendary passive item; if that lands too late in play, `rung: "epic"` is the easier step.

### 45.SMALL The one-shot Phoenix Feather, the stage look before the landing

- **Phoenix Feather is a one-shot item** (Garry, 2026-10-23: "should still be a revive item with 50% HP on revive. It can
  only be used once and doesn't feature any upgrades"): rarity uncommon, weight 6 (unchanged), one level = `phoenix_revive`
  +1. Taking it gives one free revive this run: two seconds after he falls he stands up at `revive_hp` health (base 50%)
  with the revive's blast, before the Down! screen. Once spent it stays in the build marked "(used)" and is never
  offered again; it is never offered as an upgrade at all (one level). Pass 95's rungs (+15% / +15% / +20% revive
  health, an Evolved second life) are gone.
- **Second Wind still raises a Phoenix revive** (lane SMALL's decision, one rule for every revive): the Upgrade board's
  Nerve -> Second Wind adds +15% revive health at ranks 2, 4, 6 to every revive (gold, ad, Phoenix), so a Phoenix revive
  is 50% / 65% / 80% / 95% with 0 / 1 / 2 / 3 of those ranks. The card says "half health (more with Second Wind)".
- **`single`** (any passive item): one level, off the rarity ladder, never offered again once held; the Collection's
  kind line reads "Passive · <rarity> · no upgrades".
- **The intro plays in the stage's look**: the run's stage filter and hell are on, at once, before the spawn beam lands
  (stage 2 Nightfall blue, stage 3 Blood Moon red + hell); the stage's start after the landing changes nothing. The
  spawn beam draws over the filter (render priority -6, the filter -7), so it reads as light at night and in hell.
- The bot (game/tools/bot/BotCards.gd) needs no change: a free revive is worth `SURVIVAL_PTS.phoenix_revive` 25 on the
  one card there is; it never valued the old rungs' revive health.

## 46. Pass 101 (v0.86): the six performance fixes

Garry's words: tools/dl/p101/REQUEST.md. Each lane's rules.

### 46.CROWD Drawing only what is on screen, separation on 1.25 m cells, slower off-screen steering

1. **Only creatures the camera can see are drawn.** A creature is drawn while its whole drawn picture can reach into the
   camera's view: the painting at its own size (Elites, specials, bosses, a size range: `size`), squash and stretch (its
   own, its type's launch stretch 1 + 1.6 x crouch, at least 1.3, x 1.05 + 0.05 for a charge's bounce and the walk's bob),
   up to 0.7 x size either side, lifted (a toss, a launch, a thrown body), sunk (shadow `drop`, `die_drop`) or still under
   the sand while rising, a charger's shake, bounce and roll, its badge (crown, skull, gear, at a boss's size), and its
   blob shadow; plus a border of 1.0 m + how far it moves at its own speed in 3 ticks + how far the camera's move and turn
   carry the view's edge at its distance in 3 ticks; and for 6 ticks after it leaves. Checked half the crowd a tick (each
   creature every 2nd tick). Not drawn = no painting, no shadow, no badge. The weapons' "on screen" rule (feet within
   1 m of the screen, Settings.ranged_on_screen) is unchanged and separate. (EnemyManager.drawn_vis, refresh_drawn,
   VIS_BORDER_M 1.0, VIS_LOOK_TICKS 3, VIS_HOLD 6, VIS_STRETCH 1.3.)
2. **Separation looks at 1.25 m cells** (was the 2.5 m query grid): a creature walks about 14 neighbours instead of ~49
   (a dense ring: ~36 instead of ~110). "Wide" = a radius over 0.625 m; a narrow creature finds every wide one it
   touches through its cell's list, however many (the old list of 16 wide bodies is no longer a cap). The push is the
   same push. The weapons' radius queries still use the 2.5 m grid and return the same creatures in the same order.
   Chosen by the overlap measure: 2.5 / 2.0 / 1.75 / 1.5 / 1.25 m all inside 2.5 m's seed-to-seed range of overlapping
   pairs; with the old 16-body cap 1.5 m and 1.25 m left 0.1 % and 0.8-1.1 % of creatures with a one-sided overlap,
   with the cell lists none at any size. (EnemyManager.SEP_CELL 1.25, _sep_bigs.)
3. **Creatures not drawn steer every 4th tick** (drawn ones every 2nd, as before; the boss, Elites, elite-modded
   creatures and any creature in a cell an obstacle reaches (4 m obstacle cells) always every 2nd). Their velocity
   holds between steers; each steer runs their clocks (slows, freezes, stuns, wind-ups, charges) for the ticks since
   their last steer; obstacle and crowd pushes are in every steer, and a far steer's push is baked in at half its
   rate (it is held twice as long, so a body is pushed as far a second as before); despawn and the director's move-up
   are unchanged. (EnemyManager.steer_far_every 4, far_push_scale.)

Numbers measured: see report / status_CROWD.md (overlap per cell size, the off-screen steer A/B, the sim before/after).

### 46.FPS The 60 fps cap on phones, frame times every second in the run record

- **The frame cap** (Settings.frame_cap, Engine.max_fps): 60 frames a second at most on a phone (Android; the `mobile`
  feature), the screen's own rate on the PC (0 = no cap but vsync's). Applies everywhere (title, menus, runs). The
  developer menu's "Frame rate" row switches 60 / MAX; the production build has no developer menu, so a prod phone plays
  at 60. Why 60: the world moves 60 times a second (physics ticks; nothing is interpolated), a frame drawn between two
  ticks repeats the last picture. Pass 100 measured 120 Hz costing about 25% more CPU a second than 60 Hz.
- **The run record's frame clock** (schema 3): a row's `frames` counts only frames that follow the last ticked one
  directly (Engine.get_process_frames advanced by 1), so a hitch of any length counts and the gap after a pause or a
  card screen does not; the run's old `fps` {avg, low} keeps its rule (frames over 250 ms left out as pauses). p95 =
  nearest rank (ceil(0.95 n)-th smallest). A headless run or one under --fixed-fps is marked `frame_timing.valid:
  false`; the averaged dashboard views leave its frame times out.

### 46.LOOKS Only the looks a run shows are loaded; every look still testable in the arena

- A look's sprite strip loads the first time something asks for it; the content (.tres) names no strip.
- A run loads and pins, under the spawn beam (Warmup.run -> RunLooks.prepare), the strips of every creature its stage
  window can bring in the look it brings it in (roster rows open in the window with their `variant`, waves/events in the
  window, specials whose stage has come, the stage's boss, the map's `boss` and `skins`, what a boss attack's
  `enemy`/`spawn` brings) and the hero's played look. Warmup now draws one type per creature of that set (was: every
  creature in the game).
- The arena pins only its training dummies; a look loads when it is picked or spawned.
- The title (TitleScreen._ready) unpins the last run's set; the live title keeps the strip of the hero it opens on.
- Beyond the pinned set, the most recently asked strips are kept up to LookArt.KEEP_MB = 160 MB (at 4 bytes a pixel); the
  oldest are let go first (a strip still drawn by a material stays alive regardless).
- A look's icon (other than the one played) loads when the look is worn or drawn (passives' card looks, creature and hero
  looks).

## 47. Pass 102 (v0.87): the late-Endless slowdown fixed, the Level Editor's cap made clear

Garry's words: tools/dl/p102/REQUEST.md. Each lane's rules.

### 47.STEADY No catch-up spiral, and the timings that show heat

- **The world's catch-up is capped at 2 steps a frame while the game plays** (`Game.CATCH_UP_STEPS` = 2, set on
  `Engine.max_physics_steps_per_frame` by Game._ready and put back to Godot's 8 by Game._exit_tree, so the title and
  the menus keep real time; was 8 everywhere). The world (the crowd, the shots, the hero, the pickups) steps at 60 Hz; a drawn
  frame that took longer than 2 steps' worth (33.3 ms, below 30 fps) runs only 2 and the game runs slower than real time
  by the rest, instead of piling up to 8 steps a frame (the catch-up spiral of Garry's phone run, 15-27 fps). Why 2: it
  never slows a device that holds 30 fps; at a phone 2.2x the PC on the pinned wave-48 crowd the model gives 24 fps at
  79% speed instead of 13 fps (cap 3: 18 fps at 90%; cap 1 would slow any frame under 60 fps).
- **The slowdown rule: the whole game slows together.** Godot cuts a frame's process delta by the steps it dropped
  (measured: a 50 ms frame under cap 2 gets a 33.3 ms delta), so everything on `_process` (weapons' cooldowns and fire,
  Fx, damage numbers, the HUD, the stage and buffs' clocks, the director, timers, tweens, Magnet, totems) advances by
  the world's time, not the wall's. The one rule that read the wall clock in play, `Run.rule_seconds()` (an orbiter's
  repeat hits, the sheet's rebuild throttle, the burst gaps, the companions' bob), now reads `Run.play_clock` (the
  frames' deltas summed; it stops while the tree is paused). The title and the menus run outside the Game scene
  with Godot's 8 (real time); inside a run the pause screen, the card screens and the HUD's tweens share the game's
  delta, which only differs from real time while a frame runs past 33 ms (a paused world costs little). Visual-only wall-clock wobbles (string shimmer, claws, halos, sparks, shield
  pulse, shader TIME) stay on real time. `--fixed-fps` (the sim, the Watch, probes) skips the cap.
- **Known, older than pass 102 (unchanged):** a weapon's cooldown restarts on the frame it fires (`cooldown_left =
  cooldown`), so its period rounds up to whole frames: at 30 fps (or while the cap holds the world back) a 1.0 s
  Revolver fires every 1.00-1.03 s (steady_check: 1.005 free, 1.014 at 30 fps, 1.024-1.037 overloaded).
- Run record (schema 4): `RunAnalytics.HEAT_BAND` = 50 creatures a crowd band, `HEAT_MIN_SECS` = 5 s of a minute in a
  band for its heat cell.

### 47.HITS Cheaper hits in a huge crowd: damage numbers, fire and poison, the hit sound

No damage, burn, poison or Endless number changed. These rules change only what is shown and heard, and how much
work the game does for it.

1. **Damage numbers when the screen is full** (ui/DamageNumbers.gd). From `CROWD` = 40 numbers in the air (of `CAP`
   60) the screen counts as full. Then:
   - a hit on a creature that still has a number of the same kind showing whole (younger than LIFE x HOLD =
     0.9 x 0.68 = 0.61 s) adds to that number: a running total that pops (BUMP) instead of a new number. A crit
     that joins turns the number a crit (yellow, crit size), as a crit within MERGE always did;
   - a plain hit with no number to join is let go unless it is at least `BIG_SHARE` (1.0) x the mean of the creature
     hit numbers in the air (only the biggest show); a crit or a mini crit with no number to join always shows (its
     own number, its hop);
   - a fire or poison tick with no number to join is let go once `TICK_CAP_CROWD` = 12 ticks are up (TICK_CAP 30
     below the crowd);
   - at CAP the oldest number is reused for the new one (nothing allocated per hit).
   Below 40 numbers everything is as in pass 101. The hero's numbers (hurt, shield, heal, EVADE, BLOCK) are never
   thinned. Settings.damage_numbers (the player's switch) and a tool's `suppressed` work as before.
2. **The hit sound** (EnemyManager.HIT_SOUND_GAP_MS = 120). A hit that does not kill plays its creature's hit sound
   at most once every 120 ms per sound id (creatures that share a sound share the gap; at most ~8 a second per sound;
   Audio's voice limit of `voices` per 0.4 s still applies on top). A crit always plays its hit sound; a kill plays the
   death sound as before. The training dummy's hit (it never dies) follows the same rule.
3. **Flames on burning creatures** (EnemyManager.FIRE_PUFF = 0.18 s, FIRE_FX_FULL = 80). A burning creature licks up a
   flame every 0.18 s while at most 80 burning creatures are drawn; above that every one's flames come every
   0.18 x (drawn burning / 80) s (216 burning on the screen: one every 0.49 s; the screen keeps about the same number of
   flames, as the particle pool of 400 was full and dropped most of them anyway). A creature off the screen
   (EnemyManager.drawn_vis 0) shows no flame and no poison puff. The burn itself, its ticks and its spread are unchanged.
4. **Burn and poison bookkeeping**: the same sums in the same order (a test runs pass 101's code beside the new one over
   one scene and seed and gets the same damage to the last bit, the same kills and the same spread dice); no rule.
5. **damage()'s hero numbers** (EnemyManager._hit_stats): crit_chance, crit_damage and execute_frac are read from the
   hero's sheet once and kept until the next physics tick, a build change, a new sheet or any change to the sheet's list
   of effects; every hit reads the same values as before (StatSheet.get_stat walks every effect, which a late build has
   by the hundred). No rule; listed so nobody looks for one.

## 48. Pass 103 (v0.88): a harder Endless with knockback resistance, the fire breath and Powder Keg toned down

Garry's words: tools/dl/p103/brief_PLAY.md. The rules:

#### Endless ramps harder (the lead's assumption for Garry to tune; he gave no numbers)

Red Canyon `timeline_data.endless`: `hp_growth` 0.11 -> **0.15**, `atk_growth` 0.07 -> **0.095** (the same proportion,
x1.364 on the growth rate). Wave 1's `hp` 1.15, `atk` 1.0, `speed` 1.1, `speed_growth` 0.015 and `speed_max` 1.6 are
unchanged. Every number stays in the map's `endless` block (the Level Editor's Endless card); none lived in code.
Waves every 10 s, wave k = hp x (1 + growth)^(k - 1), on the stage-end numbers.

| Endless time | wave | HP x before | HP x now | ATK x before | ATK x now | speed x (both) |
|---|---|---|---|---|---|---|
| 0:00 | 1 | 1.15 | 1.15 | 1.00 | 1.00 | 1.10 |
| 1:00 | 7 | 2.15 | 2.66 | 1.50 | 1.72 | 1.20 |
| 2:00 | 13 | 4.02 | 6.15 | 2.25 | 2.97 | 1.30 |
| 3:00 | 19 | 7.53 | 14.23 | 3.38 | 5.12 | 1.40 |
| 5:00 | 31 | 26.33 | 76.14 | 7.61 | 15.22 | 1.60 (cap) |

Speed cap unchanged (1.6, reached at about 5:00): the creatures already reach it, and with the knock resistance below a
faster crowd would close on the hero far quicker than the HP/ATK ramp alone; the harder ramp comes from HP, ATK and no
more pushing them back.

#### Endless knock resistance (new rule)

From Endless's start every creature resists the hero's NON-explosive pushes linearly: resistance =
`knock_resist_max` x min(Endless seconds / `knock_resist_seconds`, 1). Red Canyon: 90 s, 1.0 (0% at 0:00, 50% at 0:45,
100% at 1:30 and after: no push at all). It multiplies on top of the creature's own `knockback_resist` and the map's
`hero_knockback_mult` (0.5). A map that names neither key plays as before (`knock_resist_max` default 0).

Resisted (hero-side pushes): every weapon hit's knockback (damage()'s kb_force: guns, melee, the ball, the frisbee, the
breath, gravity-gun landings, the Singularity's pop, thorns, Molotov/Skull Rain landings, Supply Drop's crate), the
throws of `hero_throw_radius` (Thruster Burst, Grand Finale), Buck's Ram, the tornado's toss, the Guitarra chord's
bounce shove (the hop stays), Bucking Bronco's throw distance.

Explosive (never resisted):
- weapons tagged `explosive` (WeaponDef.tags; map key `knock_resist_exempt_tag`): Dynamite Stick / grenade
  `lob_grenade`, Cluster Bomb, Golden Pineapple, Rocket Pod, Hellfire Battery, Missile Massacre, Land Mine, Minefield,
  Jackrabbit Mines (all their pushes, the frag's shrapnel and the bomblets included);
- source ids (map key `knock_resist_exempt_sources`): `nuke` (the Nuke power-up and the revive ring's throw),
  `revive` (the comeback wave), `powder_keg`, `loose_rocket`, `blast` (a hostile blast's friendly fire);
- any hit flagged HIT_BLAST: a Last Stand turret's boom (turret `boom.explosive`, default true), a `land_blast` with
  `explosive: true` (none today: the Sun Cocktail's puff is fire, not a blast), the revive's 6 m throw.

Not touched: hostile pushes on creatures (the Sniper's beam, an eruption, a charger's shove), the pull/tow (Lasso, Wide
Orbit: it draws them in, not back), a corpse's throw (pass 82), the hero's own knockback.

#### Dragon's Breath knockback a third lower

The base weapon has no knock (`breath.knock` 0). Backdraft (the path's motion mutation, a shove every tick)
`params.breath.knock` 5.0 -> **3.3**; the Fire Eater (its evolution) `params.final.breath.knock` 7.0 -> **4.7**.
After the map's 0.5 (hero_knockback_mult) a tick now pushes 1.65 (was 2.5), the Fire Eater 2.35 (was 3.5).

#### Powder Keg damage to a third

Game.KEG_FRAC 0.25 -> **0.25 / 3 (0.0833)**: the blast deals a twelfth of the dead creature's max HP (was a quarter)
within 2.4 m, at every rank (the damage never depended on the rank). The chance is unchanged (6.5%, +2% a rung, Evolved
+3%: 15.5% at rank 5); the knock (9) unchanged and exempt from Endless's resistance. Card text: "a twelfth of its max
health".

## 49. Pass 105 (v0.89): structures, items, shots, barrels and chests out from under the stage filter

Garry's words: tools/dl/p105/brief_LOOK.md. The rules:

- A filtered stage (Nightfall, Blood Moon) darkens by what is nearest at a pixel (StageStencil's stencil table):
  the sand, the water and the scenery (props, signs, wall, cliffs) at the filter's `strength`; the creatures and the hero
  at `strength` x `actors` (0.35); **the structures, the portal and the barrels at `strength` x `structures` (0.3)**;
  **the weapons' own 3D models at `strength` x `items` (0: untinted)**; **every shot (the hero's and the creatures'),
  boulders, bomblets, boss attacks' projectiles, stalactites, the Tarantula Hawk, the chests and the falling Supply Drop:
  never**. Telegraphs, shadows, gems, coins, outlines and see-through effects stay drawn after the filter, untinted.
- `items` default 0, chosen by eye on the captures (tools/dl/p105/LOOK/contact_a.png, contact_b.png): at 0.15 the tint
  is about 5-9% (invisible at phone size) and would cost one more full-screen quad; untinted they read clearly and do
  not look pasted on (they are lit by the map's own light and fog).
- No lift (emission) was added to any creature shot: untinted, every kind read on both dark grounds in the captures
  (the pellet, dark metal by design, is the weakest; its Sundown look must not change).
- Sundown (no filter) draws no quad; its look is unchanged except where a gem or a creature's outline met a weapon's
  model, a shot or a chest: those now write their own stencil, so a gem no longer draws over them and an outline no
  longer shows through them (before, they kept whatever lay behind them).
- Cost: in a filtered stage 4 full-screen quads (sand, scenery, creatures, structures; was 2; +1 when `items` > 0);
  the marking adds no draw call (measured: 198 draws with the marks and without, same frozen frame).
- Not changed (said so, not asked): Fx's opaque debris boxes (barrel splinters, chips) and the Strongbox's coin stream
  still take the filter like the ground.

## 50. Pass 106 (v0.90): Endless faster, the War Drum, the Watch by hand, fire ants from a beetle

Garry's words: tools/dl/p106/REQUEST.md. Each lane's rules.

### 50.ENDLESS Endless creatures faster, the live ones too; the spider's death above its shadow

#### Endless speed: steeper, and live (the lead's numbers; Garry gave none)

Red Canyon `timeline_data.endless`: `speed_growth` 0.015 -> **0.04**, `speed_max` 1.6 -> **2.4** (`speed` 1.1 unchanged;
the HP/ATK growth and pass 103's knock resistance untouched). Linear as before: wave k = 1.1 x (1 + 0.04 x (k - 1)),
never past 2.4. Waves every 10 s.

| Endless time | wave | speed x before | speed x now |
|---|---|---|---|
| 0:00 | 1 | 1.10 | 1.10 |
| 1:00 | 7 | 1.20 | 1.36 |
| 2:00 | 13 | 1.30 | 1.63 |
| 3:00 | 19 | 1.40 | 1.89 |
| 4:00 | 25 | 1.50 | 2.16 |
| 5:00 | 31 | 1.60 (cap) | 2.40 (cap, from wave 31) |

**New rule (live speed):** every new Endless wave's speed factor reaches every regular creature already alive, not only
the new spawns: its walk speed becomes its own base x the CURRENT wave's factor (speed x new / old, the factor it carries
kept per creature, so it never applies twice). Creatures alive from before Endless began (factor 1) get it at wave 1.
Bosses, Elites by their kind and creatures wearing an elite modifier keep their speed (none come in Endless). A fresh
run starts at factor 1. Code: EnemyManager.set_endless_speed (called from WaveDirector._tick_endless), e_speed,
endless_speed_live.

Measured (game/tools/_p106_ENDLESS_kite.gd: the difficulty probe's kiting autopilot dropped into Endless after Sundown at
wave 20 for 60 s, the Drifter, Mirror 1.5, HP lost a minute in max-HP units, refilled below 40 %):

| build (probe) | before (0.015 / 1.6) | now (0.04 / 2.4) |
|---|---|---|
| b2 (the 14:20 build, level 30) | 6.1 maxHP/min, 353 kills/min | 7.3 maxHP/min, 448 kills/min |
| b1 (the 7:10 build, level 22), seed 11 / 12 | 3.8 / 8.2 maxHP/min | 37.4 / 37.4 maxHP/min |
| b1 at 0.025 / 2.0 | | 5.9 maxHP/min |
| b1 at 0.03 / 2.2 | | 32.8 maxHP/min |

At wave 20 the crowd's median walk is 2.51 m/s (was 1.83), its fastest 3.0 (was 2.2), the hero 3.57: no creature
outruns him yet; at the cap (x2.4) the fastest late-roster creatures reach about 3.75 m/s. A mid build (b2) still kites
at wave 20 (+20 % damage taken); a stage-1-end build (b1) that never grew is caught by the faster ring (it was already
losing 4-8 maxHP a minute before, i.e. dying in 8-16 s). The cliff for b1 lies between growth 0.025 and 0.03: Garry's
knob if wave 20 should stay survivable for a weak build.

Note for the lead: after Nightfall the Endless pool held only 3-4 creatures alive at a time in the probe (Garry's
Nightfall's last minute: a spit cactus row and a hammer giant row with max_alive limits, as pass 87's test notes), so
Endless after stage 2 is nearly empty on today's map whatever the speed.

#### Desert Spider: the death on its shadow

Cause: its shadow sits far up the screen (`shadow.up` 0.45 m at size 1.3: 0.35 of its size, about twice any other
creature's, tuned for the walking pose whose legs splay down the screen), while the death frames (SP-G, SP-H) lie low and
narrow in the cell (rows 86-136 of 160 against the walk's 72-148); and the last 0.3 s of every death (DIE_SINK) squashes
the painting down onto the foot point, which is below this shadow. So the corpse lay on the shadow's lower edge and then
sank under it.

Fix: Desert Spider `shadow.die_drop` **-0.15** (lifts the death painting 0.15 of the cell up the billboard, eased in over
the strip). **New rule:** a NEGATIVE die_drop holds its lift through the end-of-death sink (not scaled by the squash), so
the body flattens into the middle of its shadow; a positive die_drop (the Red Goblin's 0.2) sinks with the squash as
before (pass 88). No other creature has a negative die_drop.

### 50.DRUM The War Drum: time stops for a drum moment, then a 15 s boost

#### The War Drum (content/structures/war_drum, effect "buff" with params.moment)
- **Boost**: 15 s (params.seconds; was 30) on the buffs' clock, so the hero's buff_duration stretches it as every
  structure's buff (Solenne 1.25x); the Pocket Watch does not (a structure, as before). Effects (params.effects):
  might mul +1.0 (x2 attack damage; Berserk x1.5), haste mul +1.0 (x2 weapon speed = every cooldown halved; Berserk x2),
  move_speed mul +0.15 (+15%), knockback add +3 and mul +0.5 on every weapon (target all_weapons:
  (base + 3) x 1.5, e.g. Revolver 2 -> 7.5, Tommy Gun 0.6 -> 5.4, Hammer 10 -> 19.5; the map's hero_knockback_mult 0.5
  and the creatures' knockback_resist / Endless resistance still apply after). Area +25% is gone.
  Was: might +50%, area +25% for 30 s.
- **The stacking rule** (params.stack, DrumBoost.stacked_effects): while a timed buff named by a rule's `with` runs
  beside the drum's boost, each drum effect on one of the rule's `stats` gives `keep` of its bonus (value x keep):
  - with "rage" (the Berserk power-up), stats might + haste, keep 0.5: the drum's x2 damage and x2 weapon speed become
    x1.5 each, so together damage = 1.5 x 1.5 = x2.25 (not x3), weapon speed = 2 x 1.5 = x3 (not x4);
  - with "sprint" (the Sprint power-up), stat move_speed, keep 0.5: the drum's +15% becomes +7.5%
    (Sprint +40% x 1.075).
  Checked every frame: a Berserk or Sprint starting or ending while the drum runs retunes the drum's part at once
  (Run.retune_timed). Only the drum's part is reduced; the power-ups give their whole effect.
- **The moment** (params.moment): 2.2 s with time stopped (the run paused through the one-screen rule, Modal.DRUM,
  priority 35: after a chest's 40, before the level cards' 30): the run clock, the buffs' clock, creatures,
  projectiles, timers stand still; every one-shot sound effect stops (weapon loops hold with the run), the music holds
  at its position and goes on from there; touches are swallowed. The boost starts when it ends (so its 15 s are all
  in play), then the usual 1 s of blinking grace any screen gives. In the run sim (sim_mode) the moment is skipped and
  the boost starts at once (the paused moment costs no game time either way).
- **One use per drum**: unchanged (StructureManager: used, the spent painting); another drum used while one runs
  starts the 15 s again (Run.add_timed_effects, as every structure buff).
- **HUD**: a timed plate (the drum's icon on the drum's red, W.ROCK, its seconds) for any structure buff whose params
  carry `plate: true` (HUD.plate_key "structure:<id>").
- **Look while it runs** (params.aura): a ground ring under the hero thumping every 0.5 s (accents 1, 0.45, 0.7, 0.45)
  with a red wave racing out 1.65-3 m on every beat, red speed lines (3 heights) and red streaks while he runs; the
  Berserk's flames at his feet show too (haste above 1, as before).

### 50.WATCH The Watch: take the bot's run over and hand it back

- The Watch's "You play" (T): while on, the bot is never ticked: it neither steers nor answers any screen; nothing
  answers for you (the Watch's stuck report is off too). Every screen waits for your click.
- Handing back: the hero's own input is muted again and the stick released; the bot clears its plan (Bot.on_revived: goal,
  hold, hunt, breakout, danger memory) and re-plans from where he stands; a screen open at that moment is the bot's after
  HOLD_S (0.8 wall s at 1x), as any screen.
- The clock (Pause, the speeds 0.25x..8x, +/-, Step, Next level-up) is the same for you and the bot; Down! ("ask") is the
  Watch's box for both.
- Who plays outlives a Restart: a new run starts in the hands the last one ended in (`hand=1` / `--hand` starts there).

### 50.ANT Two Fire Ant looks from Garry's armored-beetle model

No gameplay rule or number changed: two new art looks of the Fire Ant (ANT-E, ANT-F, both fresh), the ant keeps playing
ANT-A with its stats untouched.

## 51. Pass 107 (v0.91): recolours, Stage 2's XP, the night Tumbleweed, room for a boss

Garry's words: tools/dl/p107/REQUEST.md. Each lane's rules.

### 51.XPT Stage 2's XP near Stage 1's pace; the Tumbleweed pale at night

- **Stage XP multiplier** (new rule): a stage_list entry's `xp_mult` (default 1, floor 0) multiplies every kill's XP in that stage (the gems a kill drops and Prospector's extra gem), through its boss, portal and Endless (Endless: times `endless.xp_share` as well). Red Canyon Nightfall (s2) = **0.7**; Sundown and Blood Moon unchanged (1).
- Why 0.7: run sim (Drifter, quarter board 1.5, bot default, death=keep, 12 players, limit 600 s). Before, Nightfall reached the levels Sundown reaches before its boss (3..17) in 0.74 of Sundown's time (geometric mean; levels 6-10 in 0.53-0.61 of the time). At 0.7 the geometric mean is 0.89 (11% sooner, inside the asked 5-15%). The shape still differs: Nightfall's roster is XP-rich from its first second (Buckshot Dwarves 10.8 XP a kill, Desert Spiders 9.6, against Sundown's opening goblins/skeletons/scorpions at 1.9), while Sundown speeds up only in its last three minutes (beetles 120, mummies 24): so at 0.7 levels 6-10 still come ~30% sooner and levels 14-17 10-35% later. A flat multiplier cannot match both ends; matching the shape is a roster edit (Garry's, see the report).
- **Night shot colours** (new rule): a weapon's `params.night_tint` replaces its shots' colours while the stage look has a filter (Nightfall, Blood Moon). Tumbleweed bleached straw #E9D59C, Dust Devil pale ash #D6D0C6. Sundown unchanged.
- Stage 3 (Blood Moon) shows the same front-loading (level 14.7 at 3:00 against Sundown's 7.2; reported, not changed).

## 52. Pass 109: the weapons' attack speed ramps up over their first upgrades

### 52.ATKSPD Level 1 slower, level 3 as before (new rule)

Garry: "The starting attack speed of all weapons should be reduced -15%, by upgrade 3 the attack speed is back to being
what it is now on upgrade 3. So the upgrade 2 is supposed to be only -7.5% of the current upgrade 2 attack speed."

- **The rule**: a weapon's attack speed (1 / its cooldown as its levels make it) is **85%** of the pass 108 number at level 1,
  **92.5%** at level 2, and exactly the pass 108 number at levels 3, 4 and 5. The hero's own attack speed (the Haste line,
  traits, talents, Berserk) is a multiplier on top and is unchanged.
- **How it is encoded** (content only, `content/weapons/<id>/<id>.json`): `base.cooldown` = old / 0.85 (rounded to 4
  decimals); the level-2 entry carries one more cooldown factor 0.85 / 0.925 (x0.9189, "−8% cooldown") and the level-3
  entry one more factor 0.925 (x0.925, "−8% cooldown"), each multiplied into that level's existing cooldown effect when it
  has one, so a card shows one cooldown line (the Revolver's level 2 "−17% cooldown" = x0.9 x 0.9189; the Big Mouth's
  level 3 "−21% cooldown" = x0.85 x 0.925). The Turret Buddy's level 3 is an add, so it is solved instead: −1.6175 s
  (7.0588 x 0.9189 − 1.6175 x 0.9189 = 5.0 s, as before). Levels 4 and 5 are untouched, and level 1 stays `[]`.
- **Which weapons**: all 27 whose cooldown is their attack clock, hidden ones included (Flare Gun, Peashooter, Poison
  Dart, the old `spear`), so one unhidden later follows the rule. **Not** the three Orbiters (Orbit Saws, Branding Iron,
  Rattlesnake): their `cooldown` is the gap between one blade's hits on one creature, while their rate comes from the
  blades' spin and count. **Not** the evolutions (they replace a maxed weapon, which is past level 3) and not the
  mutations (their cooldown effects are multipliers, so they keep their share).
- Older paragraphs that quote a weapon's base cooldown or its level-2/3 cooldown cut (the Basketball's 14.13, the Salt,
  the Frisbee, the Sun Scepter, the Dragon's Breath) give the pass 108 numbers; levels 3-5 still read true.
- Check: `python tools/check_attack_ramp.py [--ref a60ceda]` (every weapon's new / old attack speed per level against the
  commit before pass 109; the orbiters and the evolutions unchanged).

### 52.VFX The Raider's rocket that pops, the Rocket Pod that looks up, the breath as particles (lane VFX; looks, one timing rule)
- **The Vulture Raider's rocket** (core/shaders/rocket.gdshader + rocket_outline + rocket_xray, Game._rocket_material): no
  number changes (speed, turn, hit radius, size pulse as before). Unshaded hazard stripes (black and yellow, 7.5 a metre),
  the nose cone and red parts blinking red/white at 3 Hz, a rim; a hot halo `ROCKET_HALO` 0.055 m and a black edge
  `ROCKET_EDGE` 0.095 m round it (both write stencil 3: no stage filter dims them); its shape seen through anything in
  front of it. Four draws for all rockets together. Its smoke puffs now leave from its tail (`ROCKET_TAIL_M` 0.75 m behind
  its middle) instead of over its body.
- **The Rocket Pod family** (`params.familiar.launch_pitch` 60 degrees, `params.missile.rise` 0.75 on the Rocket Pod, the
  Hellfire Battery and the Missile Massacre; MissilePod): the launcher looks up before a volley and **the first rocket
  waits until it is 80% of the way up, at most 0.2 s** (`RAISED_SHARE`, `RAISE_WAIT`; at 60 fps it is about 0.12 s): the
  only timing change, the next volley's cooldown is unchanged. The rockets leave the open end of the tube in turn along the
  tubes (fanned at `UP_FAN` 0.35 of the old fan) and keep climbing through their corkscrew (`rise`: the nose eases to
  0.75 instead of 0.3) before they turn onto their targets; the launcher holds up 0.3 s after the last one and settles.
  The pod's cluster no longer turns a quarter per launch (a launcher with `launch_pitch` never does) and the kick only
  squashes it along the tubes. The Killer Bees' hive has no `launch_pitch`: unchanged.
- **The Dragon's Breath** (core/systems/BreathFlames.gd): no number changes; the look is two CPUParticles3D: flames (64
  alive at intensity 1, x intensity, x1.6 for a ring, 130 at most; 0.5 s life; first speed fitted so they travel 95% of
  the reach, slowing to 20%; spread = half the cone, flattened 0.65) and a core at the mouth (18, 0.18 s). Fx.breath_jet
  is no longer called; the wash and the scorch stay.

## 53. Pass 110: chests and specials, coins and prices, boss fight windows, explosions, the arena's screenshot tools

### 53.ECON Fewer chests, fewer but deadlier specials, half the big coins, a steeper Upgrade board, dearer heroes

Garry: "Reduce the number of chests to make them feel more special. Basically make it so the chance of Chest falling out
of a normal enemy is next to nothing while the Special versions of those enemies still guarantee a chest. Since that's
the case let's reduce the number of Specials in the end. Increase ATK of Specials quite a bit." and "Reduce the coins
gain from Boss, Elite and Specials. By 50%. Mirror costs should be more exponential (Polynomial) while the increases stay
the same. Starting point prices should stay the same though. Normalize the Hero costs as well. And increase them."

**Chests.**
- **Every regular creature** (anything not an Elite or a boss, the special creature types Rocketeer, Saiga Sniper and
  Harpooner included) drops a chest at `drops.chest` **0.0002**: about one chest in 5,000 kills, ~0.5 a 10-minute run
  (was 0.0014-0.03 by creature, the Hammer Giant 0.08, the Harpooner 0.35). Its JSON number, so a creature may be given
  its own again in the Level Editor.
- **A coloured special always drops a chest**: the map's `timeline_data.special_defaults.chest_chance` **1.0** (was
  0.35). Hot Sauce's extra roll is unchanged (a special can still, rarely, drop two).
- **Elites** (their kind or a modifier) always drop one, the **bosses** their boss chest and `drops.chests` - 1 more,
  the Bounty Hunter's bounty and the dice's ambush one each: all unchanged.
- **Fewer specials**: one at a time, the map's `special_defaults.max_alive` **1** (was 3), and every creature's
  `variance.special_chance` a third again (4 decimals: 0.04 -> 0.0133, 0.0333 -> 0.0111, 0.0267 -> 0.0089, 0.02 ->
  0.0067, 0.0167 -> 0.0056; a ninth of what they were before pass 69). The forced Special Goblin (r6, 2:00) still comes.
  The game's fallbacks for a map without these keys (EnemyDef.SPECIAL_DEFAULTS chest 0.35, SPECIAL_MAX_ALIVE 3) are
  unchanged; Red Canyon names its own.
- Measured (run sim: Drifter, quarter board, explorer bot, death = keep playing, 10 players, stage 1 to 10:00 with the
  King, stage 2 to 11:00; tools/dl/sim/runs/p110-econ-*):

  | per run | Sundown before | Sundown after | Nightfall before | Nightfall after |
  |---|---|---|---|---|
  | coloured specials that came | 22.9 | 8.3 | 13.9 | 3.5 |
  | specials killed / their chests | 21.2 / 7.7 | 7.9 / 7.9 | 13.1 / 5.0 | 3.3 / 3.3 |
  | chests from regular creatures (kills x chance) | ~9.4 | ~0.5 | ~11.3 | ~0.4 |
  | chests opened (every source) | 18.2 | 11.3 | 15.8 | 5.8 |
  | a special lives (s) | 49 | 38 | 87 | 137 |

  With one alive at a time, how many come is held mostly by how long each lives: in Nightfall a special lives over two
  minutes against the bot, so only 3-4 come in eleven minutes. Max alive 2 (Settings -> Coloured specials) would about
  double them; the chance (the Enemies tab) sets the gap after one dies.

**Specials' ATK.** x**3.5** (was x2): every creature's own `variance.special.damage` 3.5, and the map's
`special_defaults.damage` 3.5 for a creature that leaves it empty. It multiplies what a creature's `damage` drives: its
bite and its charge (each touch still at most `contact_cap` 22% of the hero's max HP, so the heavy biters such as the
mummies were already at the cap with x2), its straight shots, spit, buckshot and thrown dynamite. Not the fixed blasts
(the Horned Toad's death burst, the Sand Crab's own blast). HP x15, size x1.5, XP as before.

**Coins** (Elites, bosses and specials only; a regular creature's coin is unchanged).
- Elite purse `Game.ELITE_PURSE` [225, 150] (was [450, 300]): 225 on Sundown, 375 on Nightfall, 525 on Blood Moon.
- Boss purse `Game.BOSS_PURSE` [650, 350] (was [1300, 700]); the bosses' coins on the sand `drops.coins` King 30, Gila
  75, Brander 100 (were 60, 150, 200), `Game.BOSS_COINS` 30 for a boss that names none.
- An Elite's or a boss's own coin `PickupManager.BIG_COIN_MULT` 2.5 (was 5): 1-3 x 2.5, the half coin paid by chance
  (MirrorDanger.scaled_count), so exactly half on average.
- **A special's own coin** (new rule): its creature's ordinary `drops.gold` roll, now at `PickupManager.SPECIAL_COIN_MULT`
  0.5 of the chance (EnemyManager.died_special -> Game._drop_from_kill -> PickupManager.drop_from's `coin_mult`). Specials
  never had a coin bonus of their own, so this changes almost nothing in gold; the cut that matters is the purses.
- Mira's Motherlode (x1.5) and the Stakes' bounty still multiply the halved purses.
- Measured gold a run: Sundown 2,716 -> 1,809 (-33%: boss purse 1,040 -> 650, Elite purses 900 -> 450, boss coins 213
  -> 150); Nightfall 5,015 -> 2,325 (-54%: Elite purses 4,050 -> 1,800).

**The Upgrade board** (content/talents/*/cost): rank k costs **k x k times rank 1** (a quadratic): rank 1 is pass 88's
price, unchanged; every rank's effect is unchanged.

| talent | before (ranks 1-6) | after |
|---|---|---|
| Stakes | 100, 180, 300, 450, 650, 900 | 100, 400, 900, 1,600, 2,500, 3,600 |
| Fortune | 300, 540, 900, 1,350, 1,950, 2,700 | 300, 1,200, 2,700, 4,800, 7,500, 10,800 |
| Choice | 325, 585, 975, 1,465, 2,115, 2,925 | 325, 1,300, 2,925, 5,200, 8,125, 11,700 |
| Drive | 375, 675, 1,125, 1,690, 2,440, 3,375 | 375, 1,500, 3,375, 6,000, 9,375, 13,500 |
| Study | 400, 720, 1,200, 1,800, 2,600, 3,600 | 400, 1,600, 3,600, 6,400, 10,000, 14,400 |
| Stride | 425, 765, 1,275, 1,915, 2,765, 3,825 | 425, 1,700, 3,825, 6,800, 10,625, 15,300 |
| Grit | 450, 810, 1,350, 2,025, 2,925, 4,050 | 450, 1,800, 4,050, 7,200, 11,250, 16,200 |
| Nerve | 500, 900, 1,500, 2,250, 3,250, 4,500 | 500, 2,000, 4,500, 8,000, 12,500, 18,000 |

- The whole board: 74,190 -> 261,625 gold (x3.5). With the halved purses (~1,800 a Sundown run instead of ~2,700) that
  is about 145 Sundown runs to fill it instead of about 27. A gentler curve, k^1.5 (rank 6 at 14.7x rank 1, the board
  x1.7), is the same edit with other numbers.
- Ranks already bought keep their form and are never repriced; the next one costs the new price. Take it all back
  returns half of the gold **actually spent** (`Save.talent_spent`), so a rank bought cheap never refunds at the new
  price. The board's order (by rank 1's price) is unchanged.

**Heroes** (content/characters/*/price): every hero on sale costs **500 gold x his place in the title order**.

| hero (place) | before | after |
|---|---|---|
| Drifter (1) | free | free |
| Ironwood (2) | 300 | 1,000 |
| Astro (3) | 300 | 1,500 |
| Calavera (4) | 300 | 2,000 |
| Solenne (5) | 1,500 | 2,500 |
| Fadeaway (6) | 1,750 | 3,000 |
| Jeżyk (7) | 2,000 | 3,500 |
| May (8) | 2,500 | 4,000 |

All seven: 8,650 -> 17,500. Ironwood and Astro are still sold for gold alone, the rest after their unlock quest
(unchanged); Mira stays hidden (9,999, unattainable), Dad hidden. Buying is unchanged (Registry.hero_state, the drawer's
BUY, Save.buy_hero).

Tests: game/tests/pass110_econ_test.gd; re-pinned pass46_ui (the talent curve), pass69_en and pass72_spec (the chance a
ninth of pass 69's old one, ATK x3.5), pass45_bosses (the giant's chest), pass70_econ (the purses, the boss coins, the
big coin, the board's scale), pass61_an (the Elite purse read from Game.elite_purse), pass83_meta (the two gold-only
heroes cheaper than the rest); tools/level_editor/selftest_EN.py (ATK x3.5, the chance at most 0.0133).

### 53.ARENA The debug arena's screenshot tools (arena only; no run changes)

Garry, for the Google Play screenshots: "Ability to Spawn more than 1500 enemies in Arena (at once) + Ability to Spawn a
variety of enemies at once (in chunks of types of enemies, and in scatter as well as an option)", "Ability to slow down
time /2 and /4", "Ability to stop all enemy movement (while they still face the hero all the time)", and the hero
centred above a caption band, held by the camera. None of it reaches a run: every rule below is the debug arena's.

- **The pool.** A run keeps `EnemyManager.MAX` **320** creatures (unchanged). The arena grows the pool when a crowd needs
  more (`EnemyManager.grow_pool`, up to `ARENA_MAX` **3,000**), keeping every creature; it never shrinks while the arena
  is open (leaving the arena drops it with the scene).
- **The big crowd** (SHOTS tab, `ArenaPanel.mass_spawn`, `ui/ArenaShots.gd`): presets 100 / 500 / 1,000 / 1,500 / 2,000
  and -100 / -10 / +10 / +100 steps; one or more creatures and looks picked (none lit = the look the game plays), the
  count split evenly between them (a tool may give each its own count). Every spot is on the ground the camera sees (the
  screen grown by **12 %** of its width on each side), inside the arena's wall less 2 m, off the rocks' paintings and out
  of the lakes, and never inside the **clear circle** (default **4 m**; None, 2, 3, 4, 5, 6, 8 m).
  - **Ring**: an even cover (a hex lattice jittered by 0.32 of its spacing) from the clear circle out to the screen's
    edges, or a band **3 / 6 / 10 m** deep; the kinds mixed.
  - **Scatter**: spread at random over the same ground, the kinds mixed.
  - **Chunks**: one group a kind, a disc holding its share at the packing (**Loose 0.6, Normal 1.2, Tight 2.4**
    creatures a square metre), the groups round the hero from screen-up, squeezed to the portrait screen's width and
    pushed apart until no two touch.
  - Defaults: up at once (**no growing out of the sand**, no dust), **no specials** (none rolls its special), the field
    **cleared first** (the training dummies too); each creature faces the hero from its first frame. AGAIN repeats it.
- **The freeze** (`EnemyManager.crowd_freeze`; FREEZE in the quick column, key F): no creature walks, steers, bites,
  attacks, aims or drifts (its push, the crowd's shove and a tornado's swirl are dropped; a wind-up, a charge or a
  scripted attack is let go); the boss's and the casters' scripts, the Saiga Snipers' aims and the Scorpion Elite's tail
  beams wait; a frozen crowd never despawns. Each creature keeps turning to face the hero (its view and mirror as when it
  walks at him). **Walk in place** (the default) keeps the walk cycle going at the creature's own walk pace; **Pose**
  holds every picture on its frame. Hits, damage numbers, deaths, thrown bodies, burns and poisons go on: a frozen
  creature takes damage and dies as usual. A creature still rising out of the sand finishes rising.
- **The game's speed**: **1x, ½, ¼** (quick column, keys 1 / 2 / 4; WORLD also has 2x) set `Engine.time_scale`, so the
  world, the shots, the effects, the particles, the hero, the camera's easing and the shaders' clock slow together (a few
  cosmetic wobbles read the wall clock: the shield's pulse, a sparkle's twinkle, the tumbleweeds' sway; sounds keep their
  pitch). The arena puts its speed back if something else sets the clock to 1 (Last Stand's end).
- **The framing** (`CameraRig.frame_hero_y`; FRAME, key C; SHOTS' Caption band None / 20 / 25 / **30** / 35 / 40 % and
  -1 % / +1 %): the hero's middle (**0.9 m** above his feet) sits at the middle of what lies above the caption band
  ((1 - band) / 2 of the screen's height from the top: 35 % for a 30 % band), worked out every frame from the camera's
  distance, pitch and field of view (the fixed camera; `focus_ahead`), so walking, a hit or a dash never pulls it away.
  Off, the camera looks its usual **3.3 m** ahead of him. Zoom: Auto (the game's) or a held distance 0.4x to 4x of the
  base, in 0.1 steps. The band guide (a darkened band and a cross where his middle goes) shows while framing, never in a
  clean capture.
- **Clean capture** (HIDE UI, key H): the arena's column, the stats overlay and the HUD (bars, joystick, toasts, boss bar;
  kept when SHOTS' "HIDE hides" says Controls only) hide (and the damage numbers if SHOTS says Hide); an invisible **180 px** square in the top-left corner (or H) brings
  them back; a line says so for **3 s**. SAVE PNG / F12 hides everything for two drawn frames, saves the screen at the
  window's size to user://screenshots/arena_<date>.png and puts back what was showing.
- **The capture tool** game/tools/store_shots.gd stages the same from arguments (hero, look, weapons, level, stage look,
  sand, spot, crowd with counts, layout, clear circle, depth, packing, freeze, band or hero_y, zoom, boss, advance, speed,
  fire) and saves a PNG at the window's size (run it at 1080x1920); bounded by a 150 s watchdog and a frame cap.

Tests: game/tests/pass110_arena_test.gd; tools/arena_check.gd (a ring of 2,000, the freeze, the speed keys, the framing,
hiding and the corner), tools/touch_audit.gd arena_shots (real fingers on the SHOTS tab and the quick column).

### 53.VFX The hero's explosions drawn again, the breath behind him, the kill counter on the item row (lane VFX; looks only, no damage or radius changes)

Garry: "Explosions - at some point became quite invisible. And I mean for all the explosive weapons. Can you make them
better?", "when Player hero is facing up, or up-left or up-right the Fire Breath visual renders behind the hero 2.5d art
asset" and "Move the Kill Counter so it's vertically centered to the vertical center of the Item drawer."
- **Why the blasts vanished.** Every hero blast was one see-through pale-orange ball (Fx.burst) fading in a third of a
  second, plus a thin ring. Pass 61 made the sand paler (its painting's mean 203,162,102 -> 215,189,146), so the ball was
  drawn almost in the sand's own colour; and the ball came from the shared effect pool without `must`, which drops a third
  of such effects past a third full, two thirds past three quarters and all of them at its cap (a late-game crowd keeps it
  at 394 of 400). In a real fight most blasts showed only their ring.
- **New rule: every hero blast is drawn by its own pool** (Fx.weapon_blast / Fx.blast, core/shaders/blast_fx.gdshader;
  768 pieces, written once, animated by the shader; nothing else can crowd it out; see-through, so the stage filter never
  dims it; drawn over the death splashes). A full blast: a white-hot **flash** (about 0.8 x the radius round, 0.09 s), a
  cartoon **fireball** with a dark rim and cel shading (about 0.62 x the radius round growing to 0.7, plus three lumps;
  0.36 s at a 2.5 m blast, x sqrt(r / 2.5) within 0.8..1.25), 4-5 **smoke** puffs rising for about a second, 10-16 **sparks**
  and 5-9 **clods** flung out, a **shock ring** racing out to the real damage radius over 0.3 s, and a **scorch** 0.62 x the
  radius round (1.2 s, then fading over 2.2 s; at most one per spot a second, only for blasts of 1.2 m and more).
  The damage radius is unchanged everywhere; the ring marks it.
- **Who uses it.** Lobbed and fired blasts (ProjectileManager._explode: the Dynamite Stick/grenade family, the Golden
  Pineapple and its bomblets, the Cluster Bomb, the Rocket Pod, Hellfire Battery and Missile Massacre), Land Mines and
  their evolutions (Mine), Cluster Munitions' bomblets (Bomblets, power 0.8), the Turret Buddy's Last Stand (Turret),
  Powder Keg (Game._powder_keg, 2.4 m) and the Dynamite Bandit's stick (it hurts the hero, so it reads like his own).
  **Style:** a weapon tagged `explosive` blasts in full; a lobbed flask or skull without the tag (the Molotov, Skull Rain,
  their evolutions) only **splashes** (a smaller flash and ball, two lighter puffs, six sparks; no clods, scorch or kick).
  **Colour:** a weapon's own `params.blast_fx.color` (new key; the Golden Pineapple's gold `#FFC21F`), else fire
  weapons' orange-red, blue fire's blue, poison's green, else orange. **Power:** the Heavy Warhead's / Hellfire's
  `blast_fx.scale` (1.5 / 1.8) is the blast's power: the ball and flash 1 + 0.35 x (power - 1) bigger than the radius
  (the ring stays at the real radius), more sparks, clods and smoke.
- **New rule: merging and the budget.** A blast within 0.6 x the larger radius of one that went off less than 0.12 s ago
  only adds three sparks to it. Past 6 blasts in 0.3 s the rest go off cheap (flash, ball, four sparks).
- **New rule: the camera's kick.** It used to shake 0.5 on every lobbed or fired blast and every mine. Now only a blast of
  more than 2.2 m kicks, by 0.3 a metre past that (x its power, within 0.5..2), 0.6 at most, never twice within 0.25 s,
  and Settings' screen shake scales it as before (0 = none). A level-1 Dynamite Stick (2.8 m) kicks 0.18, a level-5 one
  (3.8 m) 0.48; Rocket Pod rockets (1.5-2 m), bomblets and splashes never kick.
- **New rule: a reserve for the effects that must show.** The shared effect pool holds 400 + 120: the 120 are only for
  effects marked `must` (the Raider's explosion, a launch's dust, the Nuke's flash, which is now `must`); before, at the
  cap they were dropped like the rest.
- **The Dragon's Breath behind him** (BreathFlames.set_behind, FireBreath.flames_behind, Player.faces_away): while the
  camera sees his back (his back and back-diagonal views: walking up, up-left or up-right the screen) the fire draws
  before his painting's second pass, so his painting covers it where they cross; in his side and front views over him as
  before. The whole fire switches when his view changes. A ring of fire (Held Breath) always stays over him.
- **The kill counter** (HUD._place_kills): its middle sits on the middle of the item slots' row (the first row if a long
  arena hand splits them), still centred under the clock between the weapons and the lines: about 30 px lower than pass
  109's spot. The ENDLESS IN / WAVE n tag ends about 11 px above it, so neither moves; should a taller tag ever reach it,
  the counter keeps 6 px under the tag (`KILLS_TAG_GAP`).

Tests: game/tests/pass110_vfx_test.gd (re-pinned on purpose: pass53_weapons_a's Heavy Warhead and Last Stand blasts and
pass85_bandit's stick, which recorded the old fx_burst). Captures: tools/dl/p110/boom/ (game/tools/_p110_boom_shots.gd),
tools/dl/p110/hud/.

### 53.BOSS Boss fight windows: what spawns while the boss lives (new rule, Garry's to edit)

Garry: "Currently I don't quite understand which enemies are going to be spawning during the Boss fight. During
Tumbleweed King there seem to be mostly Split Cactus enemies and they are endless and don't seem to follow the Max Count
rule either ... Just add a 2 minute window in the Timeline where I can set up the cycle of enemies that will be spawning
... They should be in lower numbers, but still a hazard. Do this for each Stage."

**Why it was so before.** The run clock stops at the stage's end while the boss lives, so the director kept drawing the
roster rows still open at that second (WaveDirector reads them a second early, 7:09 on Sundown) into `boss_cap_frac` of
the cap: 0.6 x Red Canyon's 500 = 300 load. Waves and once rows stop in a fight (they tick only in the normal phase), so
on Sundown only the continuous rows were left: the Spit Cactus row r54 (open 5:57 to 7:10, its own draw every 6 s, no
Max alive), a burst of 3 to 12 every 6 s into 300 load of room. Nothing ever closed it: the King's fight became 45 to 63
Spit Cacti and climbing (probe below), plus the specials' clock (a Saiga Sniper). Nightfall's fight drew its one
continuous row too (r51, Spit Cactus, Max alive 4: yet 5 to 14 alive, see "Max alive inside one burst"), Blood Moon's
every late row: some 230 creatures for the whole fight.

**The rule (game/core/systems/BossFightWindow.gd; keys docs/waves_schema.md "Pass 110").** A stage entry's
`boss_fight` {enabled, length 120, max_count 40, roster} holds spawn rows on the fight's own clock (0 = the boss
arrives). From the boss's arrival until it dies only those rows spawn: the stage's rows, the own-interval rows, the
density floor and the specials' clock stand still. The cycle loops every `length` s (rows start afresh each cycle: a
once row comes again, waves restart from t + offset, owed creatures are dropped, chance and jitter rolled again).
`max_count` is **bodies** alive (the boss, his summons and the stage's leftovers count): continuous rows top the fight up
to it (a burst of burst_min..burst_max **creatures** at each spawn check or own interval, by presence weight); waves and
once rows bring their count into its room (the rest owed) unless Respect the cap is off (then on top; the hard cap
still holds). A row's Max alive holds (all living ones of that creature count, leftovers too). Numbers are fixed at the
row's first spawn from the stage's end on the run clock (HP / ATK curves there, the hero's level then) x the stage
multiplier x the row's overrides. A stage without a window (or with On off) fights exactly as before.

**New rule: a boss's summons stop at the hard cap.** A boss's spawn_ring (the King's 16 tumbleweeds, the Gila's 12 sand
lizards, the Brander's 14 imps) keeps its count, its numbers and its never-special rule, but brings at most what is left
of the map's hard cap in bodies (WaveDirector.summon_room via EnemyManager.summon_count). With or without a window. On
Red Canyon (hard cap 500 > the pool's 320) it changes nothing today.

**New rule: Max alive inside one burst.** A creature's `max_alive` (its own or its row's Overrides) was checked once,
before a burst; a burst of several packs could go past it (Nightfall's Spit Cacti, Max alive 4, stood 14 strong in the
Gila's fight). The roster's draw and the density floor now cut every pack to what is left of it, and a row whose creature
is at its limit leaves the rest of that burst (WaveDirector._burst_from, _floor_fill). Waves rows, Endless and the
windows already held it.

**The cycles (red_canyon.json, stage_list[k].boss_fight; Garry's to tune in the Level Editor's Boss fights section).**
Each row's creature and look are from its stage's own roster; HP x are set so a creature comes about as tough as the
stage's last rows of it (they are fixed at the stage's end, later than those rows, so the factor is a bit lower).

*Sundown vs the Tumbleweed King: a 2:00 cycle, Max count 25 bodies.*

| row | creature (look, overrides) | pace | how many | why |
|---|---|---|---|---|
| bf1-1 Goblin trickle | Red Goblin RG-B (HP x1.0, no medium gems, as r1) | continuous, own draw every 3 s, weight 5 | packs of 3, scattered | the stage's own fodder keeps the King company: easy kills, XP, never a wall |
| bf1-2 Werewolf trickle | Werewolf (HP x1.2, size 1.25-2) | continuous, every 4 s, weight 3 | packs of 2 | the stage's last fodder, a little tougher |
| bf1-3 Dynamite pair | Spit Cactus (Max alive 2) | waves every 60 s from 0:20 (0:20, 1:20) | 2 a wave | dynamite to dodge while he rolls and stomps; never more than two (it was 45 to 63) |
| bf1-4 Beetle charge | Bull Beetle (Max alive 2) | once at 0:50, from the top of the screen, on top of the Max count | 2 | charge lines crossing his roll lines |
| bf1-5 Goblin ring | Red Goblin RG-B (HP x1.0) | once at 1:15, a ring round the hero, on top | 12 | a short swarm to break out of |

*Nightfall vs the Gila Grande: 2:00, Max count 30.*

| row | creature | pace | how many | why |
|---|---|---|---|---|
| bf2-1 Skeleton trickle | Skeleton SK-A (HP x0.6) | continuous, every 2.5 s, weight 5 | packs of 3 | the stage's fodder |
| bf2-2 Goblin trickle | Goblin (HP x1.0, size 1.2-1.8, as r57) | continuous, every 3 s, weight 3 | packs of 4 | the stage's fodder |
| bf2-3 Buckshot pair | Buckshot Dwarf (HP x0.6, ATK x2, Max alive 3, r28's yellow tint) | waves every 40 s from 0:15 (0:15, 0:55, 1:35) | 2 a wave | a cone of pellets while the spikes rain |
| bf2-4 Beetle charge | Bull Beetle BB-F (HP x1.0, Max alive 3) | once at 0:45, from the top, on top | 3 | lines to dodge between the eruptions |
| bf2-5 Spider rush | Desert Spider (HP x0.25, size 1-2, speed 2, as r22) | once at 1:20, a ring, on top | 8 | a fast ring as the cycle peaks |
| bf2-6 Hammer giant | Hammer Giant (HP x0.55, ATK x0.7, Max alive 1, as r60) | once at 1:40 | 1 | a slow brute that takes the safe ground away |

*Blood Moon vs the Brander: 2:00, Max count 40.*

| row | creature | pace | how many | why |
|---|---|---|---|---|
| bf3-1 Imp trickle | Imp (HP x0.35) | continuous, every 2 s, weight 6 | packs of 4 | hell's fodder (no channel in a window) |
| bf3-2 Hellhound trickle | Hellhound (HP x0.35) | continuous, every 3 s, weight 3 | packs of 2 | fast fodder that chases him through the brand lines |
| bf3-3 Knight trickle | Skeleton Knight KN-E (HP x0.6, r46's ember tint) | continuous, every 4 s, weight 2 | packs of 3 | the stage's sturdier fodder |
| bf3-4 Buckshot pair | Buckshot Dwarf (HP x0.6, Max alive 3) | waves every 30 s from 0:10 | 2 a wave | pellets while the ring closes |
| bf3-5 Beetle charge | Bull Beetle (HP x0.3, Max alive 2) | once at 0:40, from the top, on top | 2 | charges across the burning ring |
| bf3-6 Ant ring | Fire Ant ANT-B (HP x0.45, as r53) | once at 1:15, a ring, on top | 16 | the swarm moment |

**Measured** (game/tools/_p110_BOSS_fight_probe.gd: Calavera, the difficulty probe's b1 build at level 22 for Sundown, b2
at 25 for the others, dropped in 60 s before the boss, the hero never hurt, the boss held alive for 150 s of fight; alive
= bodies, the boss included; tools/dl/p110/boss/):

| fight | before (no window) | with the window |
|---|---|---|
| Sundown, the King | 118 alive as he came; Spit Cacti 22 -> 63 and still climbing, mean 72 over 150 s, 57 in the second half; at the end 45 cacti and a Saiga Sniper | 100 as he came (50 mummies, 22 cacti, 21 beetles from the stage's last minute), gone by about 0:40; then mean 26, at most 39 (with his 16-tumbleweed ring); at the end 12 goblins, 9 werewolves, 2 cacti |
| Nightfall, the Gila | 44 as she came; then 4 to 26: 5 to 14 Spit Cacti, her lizards, a Saiga Sniper; mean 13 | 37 as she came; mean 29, at most 40: skeletons, goblins, her lizards, 2-3 dwarves, the beetles, the spiders, the giant |
| Blood Moon, the Brander | 317 as he came; 190 to 300 all fight (every late row kept coming), mean 244 | 309 as he came, burnt down by his ring within 10 s; then mean 30, at most 43: imps, hellhounds, knights, the dwarf pairs, the beetles, the ant ring |

The first stretch of each fight is still the stage's own leftover crowd (nothing new comes while it is over Max count);
once it is gone the fight settles at the window's numbers.

Tests: game/tests/pass110_boss_window_test.gd (9), tools/level_editor/selftest_BOSS110.py (66).


## 54. Pass 111: map chests, the Bounty Board, hero skins and the currency layer, far creatures faster, the mummy's own left frames, the bomb and the chain

### 54.CHEST Map chests every now and then, never seen arriving; a power-up out of a chest, left for the player to fetch

**Reverted in pass 112** (Garry meant barrels): none of the rules below play any more; chests are as in pass 110. The
same asks, for barrels: 55.BARREL.

Garry: "Chests should respawn every now and then. They should also have a chance of a power up dropping from them. The
power ups don't immediately get claimed and used by the hero. They jump far enough out for it to be a conscious decision
for the Player. I should be able to set the frequency and content probabilities of both chest types on LevelEditor.
Chests never spawn where Player can see them."

Every number below is the map's (`timeline_data.world_chests`, `timeline_data.chest_contents`; Settings -> Chests in
the Level Editor); the game's own defaults (a map without the blocks) are today's: no map chests, no power-up out of a
chest, the reel as before. Keys and code: docs/waves_schema.md "Pass 111".

**Map chests (new rules).**
- On top of the chests creatures drop (pass 110's rules unchanged), the map lays a chest of its own: the first **60 s**
  into the stage, then one every **90 to 130 s** (rolled each time), at most **5 a stage**. The clock runs in the stage
  and in the boss fight; it stands still in the portal's countdown and in Endless, and never runs in the debug arena.
- At most **2** lie unopened at once: a turn that finds 2 lying is skipped (the next waits its full 90-130 s), so chests
  the player ignores never pile up. Dropped chests never count.
- **Never seen arriving**: the chest, its pool of light (4.6 m) and its 9 m beam are all outside the camera's real view
  by **3 m** when it appears (tested against the camera's frustum, so the late-run zoom-out is covered). It is laid
  **25 to 45 m** from the hero (out to 67.5 m when the camera shows all of that), inside the walkable round (0.86 of the
  arena's radius: short of the fort wall), off the rocks, 2.5 m out of the water, never behind a painting (a palm or a
  cactus), 3 m past a structure's ring and 8 m from another chest; no spot: it tries again 3 s later.
- **Lies for 150 s**: past that an unopened one disappears, only at a moment it is off the screen. A boss chest's call
  (the vacuum) pulling it to the hero keeps it.
- **Found by a tag**: the nearest map chest lying off the screen gets an edge tag like the boss's, the portal's and the
  Elite's: "CHEST 33 m", brass (violet for a boss chest). Dropped chests get no tag (they fall where the fight is).
- Boss chest chance **0**: every map chest is a normal chest.

**A power-up out of a chest (new rule).**
- When a chest is opened (any chest: a map chest, a special's, an Elite's, a boss's), a power-up hops out of it with
  its type's chance: **normal 35%**, **boss 50%**, drawn from the same mix as the kills' drops (Heart 6, Rage 3, Sprint 3,
  Shield 2, Magnet 2, Nuke 2 of 18).
- It is thrown **5 to 7 m** from the chest on a visible hop (6 m: 0.76 s in the air, 3.1 m up), landing on a clear spot
  (inside the arena, off the rocks and the water, not behind a painting, 1.2 m from any other power-up), first turned
  away from the hero and wholly on the screen below the HUD's top strip, then anywhere on the screen, then anywhere.
  The screen is narrow (about 6.5 m either side of the hero early in a run), so "on the screen" wins over "straight
  away from him": the player sees where it lands.
- In the air it cannot be taken and its clock stands still; on the sand it lies its own lifetime (Heart 22 s, the
  others 40 s) and the hero walks over for it or leaves it. Nothing pulls it in: not the hero's magnet, not a coin bag's
  own pull, not the Magnet power-up, not the boss chest's "everything comes to you" call (those never touched power-ups;
  the coin bag's pull is now off for one a chest threw).
- The game pauses for the chest's reel, so the hop plays as the reel closes.

**The reel's knobs, now per chest type** (unchanged numbers): a passive item not held yet weighs **0.45** against an
upgrade (pass 47's CHEST_NEW_MULT), the reel pays **50 gold** when nothing can grow, the boss chest holds a **mutation**
while one is open; an evolution that is ready still comes first.

**Measured** (run sim, the pass 110 setup: Drifter, quarter board, explorer bot, death = keep playing, 10 players, seed
1, stage 1 to 10:00 with the King; tools/dl/sim/runs/p111-chest-s1-before and -after; the after run had no stage cap,
which Sundown's 430 s never reaches):

| per run | before (no map chests) | after |
|---|---|---|
| chests opened (every source) | 11.5 | 15.0 (+3.5) |
| power-ups picked up | 16.8 | 17.0 |
| deaths (kept playing) | 7.8 | 5.8 |
| gold | 1,586 | 1,618 |

The bot opens about 3.5 of the ~4-5 map chests a Sundown run (it sees a chest from 45 m and goes for it; a real player
follows the tag). The power-ups it picked up hardly moved: chests throw about 1.2 more a run at 35% x 3.5, which is
inside the runs' spread (6 a player). A real-run probe (game/tools/_p111_CHEST_probe.gd, Sundown 0:00-6:50, the hero
walked to every map chest): 4 map chests at 1:00, 2:59, 4:37, 6:43 (gaps 119, 98, 126 s), all four off the screen when
they appeared, 6 chests opened, 1 power-up thrown (a Sprint, 6.0 m from its chest, 6.7 m from the hero, on the screen,
untouched until he walked to it).

Tests: game/tests/pass111_chest_test.gd (15), tools/level_editor/selftest_CHEST111.py (36).

### 54.WANTED The Bounty Board: Wanted posters before a stage run, paid when done; the big coins halved again

Garry: "Wanted Poster functionality ... It should function exactly as you described - extra coin rewards for completing
harder tasks. Make a nice config for me to be able to set it up easily in LevelEditor. Make it so I can set up the
weights of each different task probability. Always a choice of 3. I should be able to set up some difficulty score for
it. It should also scale with Player progression. Should not show locked items, heroes, enemies as a goal ... To balance
this out, reduce the coin rewards from non-regular enemies even further. The Wanted Poster is NOT available for Players
who are playing for the first time."

Every number is `game/content/wanted/wanted.json` (the Level Editor's **Wanted** tab); the game reads it when it starts
(core/systems/WantedBoard.gd). Code: WantedBoard.gd (the roll), WantedRun.gd (the run), ui/WantedBoardScreen.gd and
ui/wanted/WPoster.gd (the screen), tools/level_editor/wanted_model.js (the same roll in the page).

**When the board shows (new rules).**
- Before every stage run started from the menus: PLAY on the title (stage 1 while the Stages menu is shut), a stage's
  card on the Stages menu, and PLAY AGAIN on the Results. A tool's run (smoke, sim, Watch, the arena) never meets it.
- Only once the save has finished `unlock.runs` **1** run (Save totals `runs`: every run that reached its end, a death
  too). A first-time player's first run has no board. `enabled` false: never.
- `choices` **3** posters, three different task types; the board needs at least one type with a target, else it is
  skipped and the run starts.
- **The same three come back**: the posters rolled for a stage, map and hero are kept in the save (`wanted.boards`)
  until a choice is made, so leaving the board and coming back does not roll it again. Another stage or hero is a board
  of its own. Taking a poster or "No bounty" forgets every kept board; the next run gets a fresh roll.
- `rerolls` **0**: no re-roll button. With N, the board shows "Re-roll" (a fresh three; N times per board).
- "No bounty" starts the run without one. Backing out (the back square) goes to the Stages menu, or the title.

**Which types can be posted, and their targets.** A type is in the draw when it is `on`, weighs more than 0 and has a
target this run:
- `creatures_met_only` **true**: a creature or boss is a target only once the save has met it (Save.enemy_met: seen on
  the sand or killed). `items_seen_only` **true**: a weapon or card only once seen in a run; the hero's own gun always.
- Never hidden, retired, quest-locked (an item's unlock quest not done), another hero's own weapon, a weapon or card
  whose `from_stage` is later than this stage, a training dummy, or a boss for the creature tasks. The hero on a poster
  is the run's own (owned: he was picked to play).
- Creatures: on **this stage's roster** (a row naming one creature, no Elite modifier, not all specials, not a one-off)
  for at least `min_seconds` **40** inside the stage's window, counted once where rows overlap; drawn by those seconds.

**The draw.** Types by `weight` without putting back: the first poster's type is weight / total of the eligible
types; the next from the rest. The Wanted tab shows both chances per type ("first" and "on the board", exact).

**The number, the difficulty, the reward (new rules).**
- `n` holds one [easy end, hard end] range per stage (the last one for a later stage). Progression **P** = the stages
  of this map the save has beaten (0 to 3). The range is x(1 + `progress.param_growth` **0.15** x P) (a type may name
  its own `growth`); where a lower number is harder (the boss's seconds) it is divided by that instead. `max` caps it
  (the health floor 90%). The number is rolled evenly in the range and rounded to `step`.
- A creature is never asked for more than `per_minute_cap` **30** a minute of its seconds on the roster (Sundown's
  Bull Beetles, 1.2 minutes on the roster: at most 35). Elites never more than the stage brings (its `elite_boss`
  events plus its Elite rows' waves in the window).
- **Difficulty** = the type's `difficulty` [easy, hard]: easy at the range's easy end, hard at its hard end, straight
  between (a capped number below the range is the easy end); one decimal. Skulls on the poster = the difficulty
  rounded, 1 to 5. A weapon that is not the hero's own adds `other_bonus` **1**. Types without a number: Beat the
  stage (easy end when the stage was beaten before, hard end when never), Get a weapon to its top level (easy end +
  other bonus), Evolve (a card: easy end; his own weapon: hard end).
- **Gold** = (`base` **40** + `per_point` **60** x difficulty) x (1 + `progress_growth` **0.5** x P) x `stage_mult`
  [**1, 1.25, 1.5**] by stage, rounded to `round` **5**. On Sundown (Nightfall x1.25, Blood Moon x1.5):

  | difficulty | 0 stages beaten | 1 | 2 | 3 |
  |---|---|---|---|---|
  | 1 skull | 100 | 150 | 200 | 250 |
  | 2 | 160 | 240 | 320 | 400 |
  | 3 | 220 | 330 | 440 | 550 |
  | 4 | 280 | 420 | 560 | 700 |
  | 5 | 340 | 510 | 680 | 850 |

**The default task types** (weight; difficulty easy -> hard; the number per stage Sundown / Nightfall / Blood Moon,
before progression; what the poster shows):

| type | weight | difficulty | number | poster |
|---|---|---|---|---|
| Kill N of a creature `kill_enemy` | 14 | 1 -> 3 | 40-120 / 50-150 / 60-180, step 5, cap 30 a minute on the roster | the creature's front still |
| Kill N with a weapon `kill_weapon` | 10 | 1 -> 3 (+1 not his own) | 150-450 / 200-600 / 250-750, step 25; his own gun 3x as likely | the weapon's icon |
| Kill N specials `kill_specials` | 8 | 1.5 -> 3.5 | 3-8 / 4-10 / 5-12 | a geared creature met on the stage, gear badge |
| Kill N Elites `kill_elites` | 6 | 2 -> 3.5 | 1-2 / 2-4 / 3-5, never past the stage's Elites | an Elite met, crown badge |
| Kill N creatures `kill_total` | 6 | 1 -> 2.5 | 800-1,600 / 1,000-2,200 / 1,400-3,000, step 50 | the stage's picture, skull badge |
| Beat the boss within T `boss_fast` | 5 | 2.5 -> 4.5 | 45-75 / 60-100 / 80-130 s (lower is harder), step 5 | the boss's still (met only) |
| Beat the boss, never under P% HP `hp_floor` | 5 | 2.5 -> 4.5 | 30-60%, step 5, max 90 | the hero, heart badge (boss met only) |
| Beat the stage as the hero `beat_stage` | 6 | 1.5 (beaten before) / 3.5 (never) | | the stage's picture |
| Reach hero level L `hero_level` | 8 | 1 -> 3 | 14-22 / 16-26 / 18-30 | the hero's cut-out |
| Get a weapon to its top level `max_weapon` | 7 | 1.5 (+1 not his own) | its top level (5) | the weapon's icon |
| Evolve an item `evolve_item` | 5 | 2.5 (a card) / 4 (his weapon) | | the item's icon |
| Open N chests `open_chests` | 8 | 1 -> 2.5 | 4-8 / 6-11 / 8-14 | the chest |
| Collect N gold `collect_coins` | 8 | 1 -> 2.5 | 250-600 / 400-900 / 600-1,300, step 25 | the coin |

**How each is counted in the run** (this run only; the debug arena never):
- Kills of a creature (Run.kills_by_enemy), with a weapon (its family: the weapon and its evolution, Run.kills_by_weapon),
  in all (Run.kills); specials (a coloured special or a creature with the gear badge) and Elites (an Elite's kind or a
  creature in an Elite modifier, never a boss) counted as they die; the hero's level (his highest this run); chests
  opened (a skipped chest counts, as the run's own tally); gold picked up (after greed, every source; the bounty's own
  pay never counts).
- A weapon to its top level, an evolution: what the run holds (an evolved weapon counts as maxed).
- Beat the stage: the stage's boss killed. The health floor: the hero's health (a share of his max) never under P% from
  the run's start until the boss dies; going under fails it at once (a death and a revive do).
- The boss in time: from the boss's arrival to his death on the run's clock (pauses do not count); past the seconds with
  him alive fails it at once; another boss's death counts for nothing.

**Done, failed, paid.** DONE the moment it is met (a banner "BOUNTY DONE" with the target's icon, a toast "BOUNTY +N
GOLD", the HUD plate turns green). FAILED the moment it cannot be met any more (the plate greys). The gold is paid at the
run's end into the save (source `wanted_contract`), **only when done**, whatever the end (a death or an abandon too, as
the purse comes home since pass 70), once. The Results show a BOUNTY panel (+N, or how far it came, or FAILED) and the
gold line before -> after counts it. The HUD's plate sits on the right under the item row (under the boss's bar while a
boss lives): the target's icon, "BOUNTY", the progress ("15 / 35", "0:32 left", "low 64%", "DONE"). The pause screen's
Build tab lists it first. The run record carries `bounty` {type, target, n, d, reward, P, stage, have, need, done,
failed, paid, name, text, still} and the events `bounty_taken`, `bounty_done`, `bounty_failed`.

**The big coins halved again** (Garry: "reduce the coin rewards from non-regular enemies even further"; a regular
creature's coin unchanged):

| what | pass 110 | pass 111 |
|---|---|---|
| Elite purse `Game.ELITE_PURSE` (Sundown / Nightfall / Blood Moon) | [225, 150]: 225 / 375 / 525 | [112, 75]: 112 / 187 / 262 |
| Boss purse `Game.BOSS_PURSE` | [650, 350]: 650 / 1,000 / 1,350 | [325, 175]: 325 / 500 / 675 |
| Boss coins on the sand `drops.coins` (King / Gila / Brander), `Game.BOSS_COINS` | 30 / 75 / 100, 30 | 15 / 37 / 50, 15 |
| An Elite's or a boss's own coin `PickupManager.BIG_COIN_MULT` | 2.5 | 1.25 |
| A coloured special's own coin `PickupManager.SPECIAL_COIN_MULT` (its chance) | 0.5 | 0.25 |

The half coin of the odd numbers is dropped (112, 37). A Sundown run that kills the King gives up about 325 + 75 (the
boss) and about 115 an Elite, roughly 500 of the ~1,600 the run sim measured in pass 110 (53.ECON); a 1 to 3 skull
bounty pays 100 to 220 back on Sundown before progression.

Tests: game/tests/pass111_wanted_test.gd (19), the re-pinned pass70_econ_test.gd and pass110_econ_test.gd,
tools/level_editor/selftest_WANTED111.py; touch_audit `wanted`.

### 54.ENEMY The mummy faces as painted, the black bomb, far creatures walk faster, the harpoon's chain

**The Cyclopean Mummy faces as its sheet is painted (new rule, art only).** Garry: "Cyclops Mummy ... Let's make it so
that Cyclops Mummy doesn't actually do that, instead it's always facing the face direction. But I want you to achieve
this by changing the spritesheet itself". A creature look may carry its own left-heading sets after the usual ones:
`idle_l`, `run_l`, `attack_l`, `hit_l` (the front set while it heads screen-left) and `run_bl`, `idle_bl` (the back set
heading left); the death has one set. A look that has `idle_l` or `run_l` is **never mirrored by code**: heading left it
shows its left sets, heading right its usual sets, both exactly as painted; a left set the look lacks shows the right
one unmirrored; `front_faces` / `back_faces` do not apply to it. Every Cyclopean Mummy look (CM-A..CM-G) now has left
sets that are plain copies of its right-heading frames, so the mummy always looks the way it is painted, whichever way it
walks. Every other creature mirrors as before. A repaint of a look (gen_art, gen_ctl, a Level Editor re-roll) writes the
usual sets only and the look mirrors again until `python tools/add_left_sets.py --id <id> --looks <CODE>` is run.

**The Spit Cactus throws a black bomb (looks; one timing rule).** Garry: "Make it into one of those black round bombs
instead. Make it bigger and make the arch of its flight more obvious. It functions the same otherwise". `ranged.shot`
"bomb" throws by `ranged.bomb` (the `ranged.dynamite` block stays for "dynamite"): the same speed 9, fuse 1 s (out 0.5 s
before), lead 0.35 (at most 2.5 m), hand, blast (2 m, knockback 7, lift 2, push 10 x 1.2), ring and pulse as the stick.
- A glossy black ball 0.6 m across (scale 1; the stick was about 0.43 m long and a few cm thick) with a metal collar and
  a sparking cord fuse (spark 0.2, the stick's 0.13, its glow 0.45 of the usual so it does not tint the ball). It is
  kept out of the map's warm haze (`material.fog` false), which had browned it, and its red pulse glows behind it
  (`halo_back`), round its edge, instead of over it.
- **Higher arc, same time, same spot (new rule):** the top of its arc is `arc_height` **4.5 m** over the hand (the stick's
  was about 1.2 m), at most `arc_ratio` **0.75** x the throw's length (a 4 m throw tops out 3 m up). It keeps the
  stick's time in the air (the throw's length / 9 m/s, 0.4 to 2 s) and lands on the same spot, so it falls under a
  stronger gravity of its own (about 113 m/s^2 on a 5 m throw, 52 on an 8 m one; never less than the usual 24). The red ring and
  the fuse last exactly as long as before.
- It tumbles end over end at 4 rad/s (the stick turned at 11), trails a dark smoke ribbon from its fuse (0.3 m wide,
  0.85 s), a grey puff every 0.045 s and an orange spark every 0.03 s, and lands with a puff of sand (0.6). Never darkened
  by a stage filter, like every shot.

**Far creatures walk faster (new rule, Garry's to switch).** Garry: "Regular Enemies should walk considerably faster when
they are far enough from the Player ... an option that I can control and switch off ... also ... Bosses, but not ...
Elites or Special Enemies." Map `timeline_data.far_speed` (Settings -> Scaling in the Level Editor):
- `enabled` **on**, `distance` **14 m**, `ramp` **6 m**, `max_mult` **2.0**, `bosses` **on**: a creature farther than
  14 m (flat) from the hero walks faster, smoothly: x1 at 14 m, x1.5 at 17 m, x2 from 20 m out. The screen shows about
  12 m to the sides and 20 m up and down and the roster's rings come at 18 m, so the speed-up starts just off the sides
  of the screen and a new ring (18 m out) arrives at about x1.74.
- Only the walk the brain chooses (chase, flock, kite, a kamikaze's run, a boss walking between attacks) is multiplied,
  on top of every other speed (Creature speed x, the stage, Endless, slows). A charge, a boss's roll or jump, a flee on
  hit, a push, a pull or a throw keep their own speed.
- Never an Elite (by its kind or an Elite modifier), a special type (the Vulture Raider, the harpooner, the Saiga Sniper),
  a coloured special or a training dummy. The arena plays it too; the despawn rule is unchanged. The run sim plays it
  (it runs the game's code), so sim numbers from before this pass are a little gentler on the hero.

**The harpoon is a fat chain (looks only).** Garry: "Make it look like a fat chain so it's easier to understand what it
does. Make the whole shooting of the harpoon sequence more impressive and noticeable." `ranged.harpoon_fx` (looks):
- The rope is a chain of chunky iron links 0.56 m long, 0.4 m wide, 0.13 m thick, outlined dark and kept out of the
  map's haze, from the harpooner's hand (up 1.45 m, 0.55 m to its harpoon side) to a barbed iron hook with a red shaft
  (1.3 x, about 1.75 m long as drawn; the old one was a thin red stick).
- Wind-up (its 0.8 s telegraph, unchanged): it rears back up to 16 degrees away from its aim and crouches 10%,
  trembling over the last 30%; a white glint flashes off the hook in its hand 0.3 s before the throw; the red aim line
  as before.
- Launch: sparks off the hand, a hot white streak behind the hook, the chain paying out with a wave running down it.
- Hit: a clank of sparks at the hero and at the hand, the chain snaps taut with a shudder, and a **camera kick of 0.35**
  (scaled by the player's screen-shake setting; pass 82 had removed the hook's shake with the hurt's).
- While he is roped: the chain rattles when it hauls, sags a little when it holds; the hook sits in the hero.
- Miss: the chain goes slack and the hook is reeled back to the hand in 0.6 s.
- The gameplay is unchanged: the 0.8 s wind-up, 20 m/s, 19 m range, the lead, the 5 s rope, 70% walking away, the
  5.5 s cooldown; the shot still flies from the body's middle (the chain is drawn from the hand).

Tests: game/tests/pass111_enemy_test.gd (17), the re-pinned pass85_bandit_test.gd and pass87_fixes_test.gd;
tools/level_editor/selftest_ENEMY111.py, selftest_LEFT111.py.

### 54.SKINS Looks you earn and buy (skins), and every price ready for more than one currency

Garry: "Skins - Also, good idea, add the UI support for this. Make it easy to access for each hero. The logic for skins
will be similar to everything else - first you complete a goal, then you get access to buying skins." and "Add an
option in LevelEditor for each hero to make it so I can choose which Looks can be purchased, what goals Players have to
complete to get access to those and how much they should cost. As well as choice of currency ... get everything ready
for the currency selection functionality in every place where it matters. We aren't adding new currency yet."

**Skins (new rules).**
- A hero's look (`variants[CODE]` in content/characters/<hero>/<hero>.json) is sold to players when its
  `skin.purchasable` is on: `{"purchasable": true, "name": "Midnight Mime", "price": 2000, "currency_type": "gold",
  "unlock_quest": "skin_may_may_b"}`. Edited in the Level Editor (Heroes tab, a hero, **Skins**).
- **The look the game plays (the JSON's `variant`) is every player's** from the start; the sheet calls it "Classic"
  (its own `skin.name` when the JSON gives one). A look not sold and not bought is never shown to players.
- **Locked until its goal is done**: the quest whose `unlocks` is `{type: "skin", id: "<hero>:<CODE>"}` (else the one
  `skin.unlock_quest` names; content/quests/skin_<hero>_<code>/). No goal = on sale at once. The goal's progress is the
  quests' usual one (a counted goal shows its bar; an in-one-run goal completes during the run, with a banner "NEW LOOK
  FOR SALE: <name>" and a line on the Results' "Unlocked this run").
- **Then bought once** for `price` in `currency_type` (Save.buy_skin, the sink "skin"); only for a hero the player owns
  (a locked hero's sheet sells nothing). **Price 0** = the look is his as soon as the goal is done (nothing to buy).
- **Bought = worn at once**; any owned look is worn with a tap on its tile (Save.set_skin_worn). The worn look is what
  he is played in everywhere (Registry.played_look: the run, the title, the badge, the drawer, the Results, the
  analytics' hero_look). The arena's USE FROM NOW ON is a debug choice and wins over the worn skin; wearing a look from the
  sheet lets that debug choice go.
- A look **shelved** later (the Level Editor) is not shown or worn any more (he wears the played look); one bought stays
  bought (it comes back if it is unshelved). A look bought and later made not purchasable stays his.
- The production build keeps every look sold as a skin (tools/prod_reach.gd), beside the played one.
- The sheet's tile shows a full-body still `<hero>_still_<code>.png` cut by `python tools/skin_stills.py` from the
  look's strip (the front idle frame); without one it shows the look's badge.
- New goal type **beat_stage {map, stage, hero}**: in one run of that stage (1-based) kill its boss with that hero
  ("" = any hero): "Beat Nightfall with May.".

**The first set** (prices about half the hero's own price of pass 110, so about one good run's purse):

| hero | look | name | goal | price |
|---|---|---|---|---|
| May | MAY-B (black overalls and beret) | Midnight Mime | Beat Nightfall with May (beat_stage, stage 2) | 2,000 gold |
| Fadeaway | FAD-B (the all-purple kit, his first painting) | Purple Reign | Reach level 20 with Fadeaway (hero_level) | 1,500 gold |

Only these two heroes have a finished look that looks different from the one they wear: Solenne's other looks
(SOL-A..G) and Jeżyk's BUC-D/E are the same outfit with another walk, his deer looks are shelved, and the Drifter,
Astro, Calavera and Ironwood have one look each.

**Currencies (nothing changes for the player).**
- The currencies are content: content/currencies/<id>/<id>.json (`name`, `icon`, `colour`, `word`, `order`); only
  **gold** (its icon the coin). Every price outside a run is shown with its currency's own icon (WCoin.currency) and paid
  through core/systems/Currency.gd: a hero (`currency_type`), an Upgrade board rank (each talent's new `currency_type`,
  "gold"), a skin (`skin.currency_type`).
- **A currency id the content lacks reads as gold** (Currency.of; the Registry warns), so a price typed in a currency
  not made yet is sold for gold rather than never. The Level Editor refuses ids not in the registry.
- Gold stays in the save's "gold" key (every gold event and chart unchanged); any other currency would live in the save's
  "wallets". Take it all back pays half of each currency spent on the board back in that currency.
- Adding a currency: docs/assets_schema.md "Pass 111 (lane SKINS)".

Tests: game/tests/pass111_skins_test.gd (14); re-pinned pass81_prod_test (a hero keeps his played look and his skins);
tools/touch_audit.gd hero_skins; tools/level_editor/selftest_SKINS111.py.

## 55. Pass 112: the Monk, barrels instead of chests, floating Wanted posters, the breaking chain, the run that follows the hero's speed

### 55.MONK The Monk: a squad that walks as one, stops as one and fires bright blue spheres as one (new creature, new rules)

Garry: "New Bullet Hell Enemy - Monk ... they move at a group, meaning they all use the same direction logic, and try
their best to keep the same distance from each other. Also they attack at the same time. They don't attack often, about
half as often as Split Cactus, and ... they fully stop for 3 seconds when attacking. They run away like the Spit Cactus
as well, but they do it all together. Same attack distance ... They spawn in groups of 10, 20 or 30 ... Projectile Shot -
a bright, very noticeable blue energy sphere. Does not touch other enemies. The range of the projectile is about 25%
further than that of Drifter's Revolver." Content: content/enemies/monk (brain `squad`, its `squad` block); code:
core/systems/Squads.gd (the squads), core/systems/EnergyOrbs.gd + core/shaders/energy_orb.gdshader (the spheres). The
Monk is on **no stage's roster**: Garry places it in the Level Editor.

**The Monk's numbers** (content/enemies/monk/monk.json; every one Garry's to change there or in the Level Editor):
- HP **14** (the Spit Cactus 18), walk **1.3** m/s (the cactus 1.15), bite and sphere damage **8** (the cactus's spit),
  bite knockback 4.81, radius 0.55, size 1.85, blood "#CF1717". All of them grow with the stage, the HP/ATK curves, the
  hero's level and the Stakes exactly as every creature's do.
- Drops like a regular creature: a small gem always, a medium one 15%, a coin 3%, a chest 0.0002 (pass 110); XP x2.0
  (the cactus x3.0: a squad is many monks).
- Never an Elite (`can_be_elite` false), never a coloured special (`variance.special_chance` 0); a light size spread
  (8%), no speed spread (a squad walks at one pace), pale tints (white, warm, lilac at 0.15).
- `pack_size` 20 (the sizes' mean: what the Level Editor's charts and any spawn path that does not know squads use).

**Squads (new rule).** Monks spawned together are one squad.
- A roster row's draw brings **one whole squad**: its size drawn from `squad.sizes` **[10, 20, 30]** by `squad.weights`
  **[1, 1, 1]** (a third each), or the row's own **Pack** when the row sets one. The spawn check's burst never cuts a
  squad, and a squad takes the rest of that burst (one squad a draw). Whatever the row's pattern (scatter, single,
  ring, in front), a squad comes as a pack at one spawn point, in its formation.
- **Never a partial squad:** when the cap, the hard cap, the pool's free slots or the creature's max_alive cannot take the
  drawn size, the squad comes as the largest of its sizes that fits (30 -> 20 -> 10); when not even 10 fits it **waits**
  (the row sits out that burst). A row's own Pack never shrinks: it waits until it fits.
- A waves row (pace waves / once) owes its `count`, else its Pack, else one drawn size; it pays one squad a spawn check
  (at most 30 a squad: a count of 40 comes as 30 + 10), each squad whole or waiting as above.
- A few paths that do not know squads still bring them in one piece: Endless waves (at most 12 a pack there), the
  portal wave, the old `waves` list; and monks spawned one by one in the same moment (a ring with a ring radius, the
  arena's swarm) join one squad when they stand within 8.5 m of its first monk, else start their own.
- In the debug arena the ENEMY tab's "1" brings one squad of a drawn size; 5, 20 and 50 bring that many in squads of at
  most 30 (50 = 30 + 20).
- The Level Editor's Timeline charts count a continuous Monk row as one squad of its Pack (else 20) a draw.

**How a squad moves (new rule).** One decision for the whole squad, made at its centre:
- Its centre walks like a kiting Spit Cactus at the monks' walk: it **backs off** straight away from the hero while the
  squad's **near edge** (the centre's distance less the formation's radius) is nearer than **5.5 - 0.5 = 5 m**, **walks
  in** while the near edge is farther than **8 m**, and **stands** in between (`keep_distance` 5.5, `range` 8: the
  cactus's numbers; `band_from` "center" measures from the middle instead). A 20-squad's radius is about 3.5 m, so its
  middle stands about 8.5 to 11.5 m off the hero and its far side about 15 m.
- Every monk keeps its own slot of a round hex formation **1.4 m** between neighbours (`spacing`) round the centre; it
  steers to its slot at the squad's walk plus **2.5 x** the gap (`gain`), at most **1.5 x** its own walk (`catch_up`).
  When monks die the formation is made again for those left (the middle slots first, each to the nearest monk): it
  shrinks and closes up.
- They all face where the squad walks (backing off they turn their backs on the hero and walk away, as one), and face
  the hero while they stand. The crowd's push and the rocks still work on every monk; the centre slides along the arena's
  wall and is pushed out of a rock; it never gets more than **1.2 m** ahead of its monks (`leash`: a blocked squad waits
  for its stragglers). A squad still coming up out of the sand (more than half of it) waits for it.
- Far from the hero (pass 111's far speed) the whole squad speeds up together, read at its centre.
- Stuns, slows, freezes, pins, launches, grabs and knockback act on each monk as on any creature; the others carry on.

**The volley (new rule).** One clock for the whole squad:
- A volley may start **5.2 s** after the last one started (`cooldown`; the Spit Cactus throws every 2.6 s: half as
  often), the first **1.5 s** (+ up to 1 s at random per squad) after the squad forms (`first`), and only while the
  squad stands in its band.
- Then **every monk that is free** (on its feet, not stunned, frozen, held by the Gravity Gun, buried, in the air,
  spinning or fleeing) **stops dead** for **3.0 s** (`hold`): no walking at all; a hit's push and the crowd can still
  nudge it. Its hands rise over the first **0.5 s** (`rise`: the attack strip's wind-up frames), then stay up (its
  hands-up frames, one after the other twice a second, `breath_fps` 2).
- A blue glow gathers above its hood between its raised hands, from a fifth of the sphere's size to all of it (`glow.from`
  0.2), rising with the hands (`hands` {up 1.8, from_up 1.2, forward 0.25}: metres at its size, as a muzzle).
- At **1.0 s** (`release`) every monk still in its pose looses **one sphere at the hero in the same tick**, aimed at where
  he stands then (`orb.lead` 0: no lead). A monk stunned, launched or grabbed during the stop sits that volley out. The
  attack sound (w_sun_warn) plays once as the hands rise, the shot (w_zap_fire) once as the spheres leave.
- The 0.5 / 1.0 / 3.0 s are **plain seconds on every map** (Garry: "about 3 seconds"): unlike the other creatures'
  wind-ups, the map's pace knob (Red Canyon's move_pace 0.9 x creature_speed_mult 0.9 = 0.81) does not stretch them;
  High Noon's slow-down still slows them, as it slows every creature's clock. The 5.2 s cooldown is plain seconds too, so
  a squad in its band walks for about 2.2 s between stops.

**The sphere (new rule).** `squad.orb`:
- A bright blue ball **0.5 m** across (`size`; colour "#2F7BFF": a white-hot core, the blue, a darker blue rim that reads
  on the sand, a soft blue halo), breathing 12% either way three times a second, a faint trail of blue beads (one every
  0.04 s, fading over 0.35 s). Never darkened by a stage filter (Nightfall and Blood Moon show it as bright as Sundown).
- Slow: **4 m/s** on the creatures' shot clock (High Noon and the pace knob slow it like every hostile shot: 3.24 m/s on
  Red Canyon). Straight along the line it left on; it comes down from the hands to **1 m** over the sand (`hover`) in
  0.35 s and follows the ground there.
- It touches **nothing but the hero**: it flies through every creature, rock and shot. It is gone after **17.5 m**
  (`range`: 1.25 x the Revolver's 14 m; it bursts into a puff), or when it reaches the hero: his body within 0.22 m
  (`hit_radius`) + 0.5 m of it, in the usual height band. He takes the monk's damage x `damage_mult` 1 as a hostile
  shot's hit (an evade, the shield and the blink after a hit apply as to any shot; a sphere that reaches him in that
  blink is spent too), and, as every plain shot since pass 89, **no push** (`orb.knockback` above 0 would make it a
  special push).
- All the spheres in the air, the gathering glows and the beads are one draw call.

**The art's attack strip (for the looks).** A Monk look's `attack` strip is laid out front | back (`attack_views`
"front_back"): in each half the first frames are the hands rising (played through once over `rise`), the rest the hands
up (looping at `breath_fps`); with two frames a half the first rises and the second holds. A squad monk shows its attack
strip through a hit and in every view (the front half from the front and side views, the back half from behind and the
back diagonals). The death is the look's own strip (a fall on the face).

**The run sim's bot** steps out of the line of a sphere within 6 m flying at him (game/tools/bot/BotLegs.gd).

Tests: game/tests/pass112_monk_test.gd (12); re-pinned pass338_test (the frame table knows the squad's attack rule);
tools/level_editor/selftest_P.py (13 brain blocks). Captures: game/tools/_p112_MONK_shots.gd -> tools/dl/p112/monk/shots/.

### 55.BARREL Barrels come back now and then, never seen arriving; a power-up out of a smashed barrel, left for the player to fetch (54.CHEST reverted)

Garry: "Chests - when I was talking about chest appearing and stuff I actually meant barrels. Not chests. So apply
whatever I said in that prompt to barrels, and revert the chests to be as they were."

**Chests as they were.** Pass 111's map chests, the CHEST edge tag, the power-up out of a chest and the chest-content
settings are gone (54.CHEST): chests come only from drops again (pass 110's rules), the reel is pass 110's.

Every number below is the map's (`timeline_data.barrels`; Settings -> Barrels in the Level Editor); a map without the
block plays today's barrels (no respawn, no power-up, the same gems and coins). Keys and code: docs/waves_schema.md
"Pass 112".

**Barrels come back (new rules).**
- The map starts with its 35 barrels as before. A smashed one comes back: the first **45 s** into the stage, then one
  every **40 to 60 s** (rolled each time), only while fewer than **35** stand (the start's count: only smashed ones come
  back, the map never fills past its start); a turn that finds 35 standing is skipped and the next waits its full time.
  No cap a stage: at most 8 come back in Sundown, 12 in Nightfall, 15 in Blood Moon (one a turn, plus the boss fight's).
- The clock runs in the stage and in the boss fight; it stands still in the portal's countdown and in Endless, and never
  runs in the debug arena.
- **Never seen arriving**: the barrel and its shadow are outside the camera's real view by **2 m** when it appears (the
  camera's frustum, so the late-run zoom-out is covered). It comes back **20 to 40 m** from the hero (out to 60 m when the
  camera shows all of that), by the start's own rules: inside the arena, off the boss flats' middle, out of the water,
  off the rocks, never behind a painting or inside a structure, 6.5 m from any barrel standing.
- **22%** of them come back black (the start's own share). A black one that comes back holds 1-5 coins rolled then; they
  are extra gold (the creatures' coins hold back only the start's barrels' coins, pass 87).
- No edge tag points at barrels: with 35 on the map one would always be showing.

**A power-up out of a smashed barrel (new rule).**
- A **brown** barrel throws a power-up **8%** of the time, a **black** one **30%**, drawn from the same mix as the kills'
  drops (Heart 6, Berserk 3, Sprint 3, Shield 2, Magnet 2, Nuke 2 of 18), on top of its gems and coins (unchanged: brown 8
  small gems; black 10 small, 4 medium and its 1-5 coins).
- It is thrown **5 to 7 m** on a visible hop (6 m: 0.76 s in the air, 3.1 m up), landing on a clear spot (inside the
  arena, off the rocks and the water, not behind a painting, 1.2 m from any other power-up), first turned away from the
  hero and wholly on the screen below the HUD's top strip, then anywhere on the screen, then anywhere: the player sees
  where it lands.
- In the air it cannot be taken and its clock stands still; on the sand it lies its own lifetime (Heart 22 s, the others
  40 s) and the hero walks over for it or leaves it. Nothing pulls it in: not the hero's magnet, not a coin bag's own
  pull (off for a thrown one), not the Magnet power-up, not a vacuum.

**Measured** (run sim, the pass 110 setup: Drifter, quarter board, explorer bot, death = keep playing, 10 players, seed
1, stage 1 to 10:00 with the King; tools/dl/sim/runs/p112-barrel-s1-before and -after; "before" is today's code with no
`barrels` block):

| per run | before | after |
|---|---|---|
| barrels smashed | 17.6 | 22.2 (+4.6) |
| power-ups picked up | 15.7 | 16.2 |
| gold from barrels | 21.7 | 25.4 |
| chests opened | 9.6 | 10.8 |
| hero level at 10:00 | 25.5 | 26.3 |
| deaths (kept playing) | 9.5 | 9.9 |

At 22 barrels a run the chances throw about 2.8 power-ups (22 x (0.78 x 8% + 0.22 x 30%)); the bot picked up 0.5 more
than before, inside the runs' spread (6 a player), so it fetches only some of them. A real-run probe
(game/tools/_p112_BARREL_probe.gd, Sundown 0:00-7:10, the hero smashing the nearest barrel every 12 s): 36 smashed,
**8 came back** (at 0:45, 1:31, 2:16, 3:13, 3:57, 4:48, 5:47, 6:35), all eight off the screen when they appeared,
**6 power-ups thrown** (17% of 36), each landing 5.2-7.0 m from its barrel and 5.8-8.0 m from the hero, all six on the
screen, none touched until he walked over.

Tests: game/tests/pass112_barrel_test.gd (12), tools/level_editor/selftest_BARREL112.py.

### 55.WANTED The Wanted posters float in over the run after the descent (54.WANTED's board screen gone)

Garry: "Wanted Poster - this should appear at the beginning of a run right after the descend sequence. And make it so
it's not a full screen, but more like floating posters instead. Similar logic though."

**What changed (new rules; everything else is 54.WANTED as it was).**
- The full-screen Bounty Board before the run is gone: PLAY on the title, a stage's card on the Stages menu and PLAY
  AGAIN on the Results go straight into the run again, as before pass 111.
- **When**: `Game.BOUNTY_AFTER_LAND` **0.7 s** after the hero lands from the spawn beam (the dust settled; divided by the
  beam's hurry when the player sped the descent up), on the run's clock (it waits while the run is paused). Only after
  the real descent: a tool's instant start never shows them unless its launch says `bounty_board: true`.
- **Who**: as before, only once the save has finished `unlock.runs` **1** run (a first-time player never sees them),
  never in the debug arena, never when a tool's launch names its own `bounty` ("none", "roll" or a contract), and only
  when at least one poster can be posted.
- **The one-screen rule**: the posters are a screen of the rule (`Modal.BOUNTY`, priority **25**: after the level cards
  30 and the War Drum 35, before a mutation offer 20 and the shop, the Stranger and the totems 10). The run pauses under
  them; a level-up, a chest or anything else that comes meanwhile waits its turn and opens after them, never two at once.
- **How they look**: the board's three posters (54.WANTED's roll, weights, eligibility, numbers, rewards, art) hang on
  strings from above the screen's top edge, each by its nail, under a light dim (**0.34**; the card screens use 0.78) with
  the run seen behind them; they drop in on their strings and sway gently (**2.6°** either way, about one swing in three
  seconds, each its own pace, a 5 px bob). "WANTED" and a line over them, "No bounty" under them; the HUD steps aside
  while they hang.
- **A tap on a poster takes it** (one tap, no confirm): it is stamped TAKEN, the other two drop away, the HUD comes back
  and the poster flies into the bounty plate on the right under the item row (about **0.85 s** from the tap), the plate
  pops in as it lands, and the run goes on with a second of grace (no TAP TO GO gate). **"No bounty"**: the wind blows the
  three away off the right edge (**0.5 s**) and the run goes on without a contract. A second tap does nothing.
- **The same three** still come back if the run is left at the posters (the app closed, the run abandoned there): the
  board kept in the save (54.WANTED) is forgotten only when a poster is taken or "No bounty" is tapped.
- **Re-rolls** (`rerolls`, **0** by default): with N, a "Re-roll" button over "No bounty" drops three new posters, N times
  per board.
- The HUD plate, the pause screen's row, the Results' BOUNTY panel, the pay at the run's end and the run record are
  unchanged.
- **Tools**: the run sim starts instantly (no posters). The Watch's bot answers "No bounty" (its option `bounty`:
  "none" by default, "random", "first"). smoke_run's launch asks for the posters and takes the first; touch_audit
  `wanted` taps every control, then takes a poster for real and, in a second run, taps No bounty for real.

Tests: game/tests/pass112_wanted_test.gd (8), the updated pass111_wanted_test.gd (18).

### 55.ENEMY The harpoon's chain breaks, the hero's run follows his speed, the bombs and harpoons ready from the start

**The chain breaks (looks only).** Garry: "Harpooner - the chain should break when it breaks. Like there should be a
visual of this." When the rope ends any other way than a miss's reel (its 5 s run out, the harpooner killed, a
teleport, the hero falling; Game.tether_end while the run goes on), the chain snaps where it hung: `break.at` **0.55**
of the way from the hand (give or take 0.08), a clank of sparks and a white tink (`tink` **1.1** m) at the break, **8**
iron bits flung out, a metallic hit sound (`w_spear_hit`). The hand's half springs back `recoil` **70%** of the way to
the harpooner's hand, the hook's half drops where it broke, both loose ends lash `whip` **0.55** m across and die away,
the halves fall flat on the sand, the hook drops off the hero to his feet, and over the last 40% of `seconds` **0.9**
every link and the hook shrink away. A miss still reels home as in 54.ENEMY. The keys are `ranged.harpoon_fx.break` (the
Level Editor's Harpoon look row). Nothing in the gameplay changes.

**The run cycle follows his speed (new rule).** Garry: "moving slowly should slow down the hero's animation." His run
cycle plays at his walk's share of his full speed (his move speed with every buff): a stick pushed half way plays it at
half speed, the harpoon's rope (walking away from the harpooner: 70%), the oasis water (90%) and a wall he runs into slow
it as much as they slow him. It never plays slower than **0.35** of the painted rate (he never freezes mid-stride) or
faster than **1.0** (a Sprint or Rage keeps the cycle as painted, as before), and follows his speed at **12** a second.
A hero's JSON may set its own `run_anim` {min, max, follow} (the Heroes tab's "Run cycle follows his speed").

**Bombs and harpoons ready from the start (no rule change).** Garry: "the new bombs and harpoons take a second to load
when they are first seen. Make it so they are preloaded during the loading of the run". Under the spawn beam the
warm-up now also loads every creature's thrown model (the bomb, the dynamite stick) and draws the harpoon's chain and
hook, the bomb's fuse smoke and the Monk's energy orbs once; and it lasts at least **6** drawn frames (it lasted 0.3 s,
which the run's first slow frames could use up in one or two frames, so the pipelines it drew were not all ready). The
probe (game/tools/_p112_ENEMY_firstuse.gd, PC, vsync off): the first bomb throw's worst frame 12 to 14 ms before (plus
6 ms the frame before), 2.4 to 4.8 ms after; the first harpoon 20 to 22 ms before, 2.4 to 4.5 ms after; the first chain
break 13 to 18 ms before, 2.8 to 3.7 ms after; a quiet frame is 1.5 ms. A phone compiles far slower than this PC, so
the hitch it removes there is larger.

Tests: game/tests/pass112_enemy_test.gd (12).

## 56. Pass 113: new task types, the bosses' bullet heaven, rare dust devils that look like tornadoes, the Monk's cloud, locked looks as silhouettes

### 56.TWISTER Dust devils come now and then, form where you can see them, and look like tornadoes

Garry (2026-10-28): "Tornadoes still don't look like tornadoes and are quite confusing. Make them rarer too."

What changed, in plain words:
- **Rarer.** The one dust devil that circled the middle of the map for the whole run is gone. Now one comes now and then:
  the first 1:30 into a stage, then one every 2 to 3 minutes (rolled each time), each staying 20 to 30 seconds, never
  more than one at a time. That is about 3 in Sundown, 4 in Nightfall and 5 in Blood Moon. They come only in a stage's own
  time: none in the boss fight, the portal countdown or Endless, and one still standing when the boss arrives fades away.
- **You see it coming.** It always forms on the screen, 7 to 11 m from the hero: a bank of dust churns up on the sand
  first, then the funnel rises out of it over 2.5 seconds. While it forms it grabs nothing. Its reach is drawn on the
  sand as a ring of swirling dust (2.9 m round its middle: faint while it forms, full while it can throw you, gone when
  it leaves). The first one of a run says "DUST DEVIL: keep out of its ring" at the top of the screen, never again that
  run. You hear it too (its wind loop, louder the nearer it is).
- **It crosses the screen and leaves.** It moves at 1.4 m/s (you walk about 3.6) on a line across the view that passes
  3 m to one side of where you stood when it formed, swaying a little; it turns back before the canyon wall. At the end
  of its life it stops grabbing, its ring goes, the funnel thins away over 2 seconds and its dust puffs out.
- **What it does is unchanged** (Garry did not ask): it throws the hero 8 m/s up and 3.6 m/s away from its middle when
  he is inside its ring, at most once every 1.2 s; it lifts every creature within 2.4 m, spins it round, flings it out
  and it lands hurt (8% of its health), as before.
- **The look** (TornadoFx, also worn by the Tumbleweed King's Royal Dust Devil): a funnel narrow at the ground (0.6 m)
  and wide at the top (2.1 m), 7 m tall (about four heroes), leaning and snaking a little, with dark bands and pale
  streaks spiralling up it (four bands up its height, turning 0.9 times a second), a ragged top breaking up into the air,
  a looser shell of pale wisps turning faster, a churning bank of dust round its foot as wide as its grab radius, and 28
  bits of debris (clods, twigs, bark chips and, one in eight, a little tumbleweed) riding round and up it. It takes a
  stage's evening or blood-moon tint like the sand it stands on, and a creature it spins shows its outline through the
  dust (as one behind a cactus does).

Every number is the map's (`timeline_data.dust_devils`; the Level Editor's Settings tab, card "Dust devils", next to
Barrels, the game's numbers in grey; docs/waves_schema.md "Pass 113"): enabled, first, every, life, max_alive, radius,
speed, wander (across the view / drifts about / the old loop round the flats), miss, form_dist, form_seconds,
fade_seconds, toss {up, out, cooldown}, lift, warn, in_boss, in_portal, in_endless. The debug arena's WORLD tab has CALL
A DUST DEVIL and SEND IT AWAY.

New rules (none of these existed before pass 113):
- 56.TWISTER.1 A dust devil forms only inside the camera's view with its whole ring, 7 to 11 m from the hero, on open
  sand (inside 0.85 of the arena, out of the water, half its ring clear of every rock); a due one that finds no such spot
  tries again 3 s later.
- 56.TWISTER.2 It grabs (throws the hero, lifts creatures) only between the end of its forming and the start of its
  fading; creatures already in the air keep swirling round it while it fades.
- 56.TWISTER.3 The next one is due `every` seconds after the last one formed (start to start); one due while
  `max_alive` stand comes as soon as one has gone.
- 56.TWISTER.4 The clock runs only in the phases the block allows (by default the stage's own time); leaving them, every
  one standing fades away at once.
- 56.TWISTER.5 The first one of a run toasts once (`warn`).
- 56.TWISTER.6 Its wind sound plays while one stands, quieter 1.1 dB a metre past 6 m and with its strength; it stops
  while the game is paused.

Tests: game/tests/pass113_TWISTER_test.gd; game/tests/pass87_slook_test.gd test_draw_order (every part before the
filter); tools/level_editor/selftest_TWISTER113.py.

### 56.TASKS Seven new task types, for unlocks, skins and the Wanted posters

Garry: "Add the following task types everywhere in the game where we have tasks: Deal N Damage with Weapon (weapon
picture); Restore N HP with Item (Life steal, Regen, Stand Still Regen, Crit Restore HP, etc); Restore N HP with (Heal
Power-up, Structure); Upgrade Item to N Level (any item, only available levels); Destroy N Barrels; Claim N Totems; Deal
N Poison/Fire damage ... This should apply as an addition to any place where we have tasks, so unlocking of heroes,
unlocking of items, wanted functionality, etc."

Every task type is now in all three places: an unlock quest (a hero's Requirement, an item's quest lock, a skin's
goal: the Level Editor's Condition list) and a Wanted poster (the Wanted tab). Code: core/systems/TaskTally.gd (the
counting), QuestTracker.gd (quests), WantedBoard.gd / WantedRun.gd (posters); words in TextGen.quest_task_text.

**What each one counts (new rules).**
- 56.TASKS.1 **Damage with a weapon** counts the damage the weapon's whole family deals (the weapon and its evolution:
  the Revolver and the Golden Revolver together), what each creature still had in it (never the overkill), as the
  Results screen's damage already counts it. A weapon's path mutations are its own damage. Kills with a weapon stay as
  they were (only the exact weapon).
- 56.TASKS.2 **Fire and poison damage** count the ticks of a burn (fire) and of a poison (poison) the hero's side
  started, whatever started them: the Molotov's pool, the Dragon's Breath's flames, a fire or poison path mutation
  (Accelerant, Blight, Venom...), Kindling, a fire spreading from creature to creature. A weapon's own direct hit is not
  fire or poison damage even when the weapon is a fire one (the breath's cone, the Molotov's splash count as its
  burns only); the boss's ring of fire burning the crowd and every hostile blast never count. The burn and poison ticks
  also count as their weapon's damage (rule 1).
- 56.TASKS.3 **HP restored with an item** counts the health an item actually gives back (none while the bar is full):
  Death's (and Death Risen's) life steal, Temperance's (and Temperance Risen's) and Hot Springs' regen, Siesta's
  stand-still regen, Vulture's crit heal, Cake's slices. An item heals because its levels give one of the healing stats
  (life steal, regen, stand-still regen, crit heal chance, cake drop chance); no item is named in code, so a new healing
  item counts by itself. When several sources give the same stat, each heal is split by their shares of it: Temperance
  0.45 regen and Hot Springs 0.65 regen share a regen tick 41% / 59%; Ironwood's own regen (his trait), a talent's or a
  Totem gift's is in the stat but counts for no item. Regen and Siesta together: each part goes to its own items. An
  evolved card counts for its source (Death Risen heals "with Death"). Snake Oil heals nothing itself (it holds what
  other heals spill over, which counts for whatever healed). Afterglow (Solenne's perk) makes every heal bigger: the
  bigger heal counts.
- 56.TASKS.4 **HP restored with a power-up or a structure** counts what the Heart (a power-up dropped by kills or out of
  a barrel), the Healing Well and a dice shrine's full heal give back (none while the bar is full). A Cake Slice is not a
  power-up: it counts for the Cake (its pickup names the stat that drops it, `params.credit_stat: "heal_drop"`). A quest
  may name one source ("pickup:heart") or any of a kind ("pickup:" any healing power-up, "structure:" any healing
  structure).
- 56.TASKS.5 **An item to level N**: the existing `item_level` quest (pass 100, one run). The Level Editor only lets a
  quest ask for levels the item has (1 to its top: a weapon's 5, a card's 4, a passive item's rarity ladder, common 6 ..
  epic 3), and the server refuses one past them.
- 56.TASKS.6 **Barrels**: one for every barrel the hero breaks, brown and black alike (the ones that come back too).
- 56.TASKS.7 **Totem gifts**: one for every gift taken at a Totem Pole; a pole left without taking a gift counts for
  nothing.

**Quests count across runs, or in one run (new rules).**
- 56.TASKS.8 The six quest types (damage_with_weapon, heal_with_item, heal_with_source, element_damage, barrels_total,
  totems_total) add up across runs, like "Kill N with a weapon". Ticking **In one run** makes one count only inside a
  single run: then its words end "in one run." and its bar shows only while a run is on (like "Reach level N").
- 56.TASKS.9 What a run counts reaches the save once, at the run's end (a death, an abandon and extracting alike),
  rounded to whole points. While the run is on, the quests read the save plus the run so far, so a quest can be
  completed in the middle of a run (the UNLOCKED banner at once) and its bar moves during the run. A run left by closing
  the app mid-run loses its counts, as it loses its purse.
- 56.TASKS.10 Nothing counts in the debug arena, in the run sim, in the Watch or in any tool run (smoke_run, captures):
  their counts never reach the save and never complete a quest. (A headless test may switch it on.)
- 56.TASKS.11 Stage hints (the Collection's "Stage N can do it"): stage 1 for every task quest, or the stage a named
  weapon or item first comes from (its `from_stage`).

**The pictures (new).**
- 56.TASKS.12 Every poster and quest of these types shows a picture: the weapon's icon, the item's icon, the Heart, the
  Healing Well's painting, the item's icon (an item to level N), the barrel (painted this pass), the Totem Pole, the fire
  (the damage sources' own) or the poison flask (painted this pass). The Collection's locked box and the hero sheet's
  "To unlock" box now show a quest's picture (40 px) left of its words, for every quest that names one thing (a weapon,
  a creature, an item, a hero, a stage, the chest, the coin, the barrel...); a quest about "any item" shows the words
  alone.

**The Wanted posters (new rules; everything else is 54.WANTED / 55.WANTED).** Each counts inside the run only. A type
with nothing to target this run is never offered.

| type | weight | difficulty | number Sundown / Nightfall / Blood Moon (before progression) | target |
|---|---|---|---|---|
| Deal N damage with a weapon `damage_weapon` | 8 | 1 -> 3 (+1 not his own) | 12,000-36,000 / 20,000-60,000 / 30,000-90,000, step 1,000 | as Kill N with a weapon: his own gun 3x as likely, a weapon seen and unlocked |
| Restore N HP with an item `heal_item` | 5 | 1.5 -> 3.5 | 60-180 / 80-240 / 100-300, step 10, times the item's own factor | a card or passive item that heals, unlocked, open on the stage, seen |
| Restore N HP with a power-up or structure `heal_source` | 4 | 1 -> 3 | 30-100 / 40-130 / 50-160, step 5, times the source's own factor | a healing power-up this map drops (its kill drops or its barrels) or a healing structure it places |
| Get an item to level N `item_level` | 6 | 1 -> 3 from where N fell | N from 2 (`min_level`) to that item's own top level | his own gun (2x as likely) or a weapon, a card or a passive item seen; a one-level item never |
| Break N barrels `barrels` | 6 | 1 -> 3 | 8-20 / 10-24 / 12-28, step 1, growth 0.1 a stage beaten, never past 40 | always (35 barrels stand on the map) |
| Take N Totem gifts `totems` | 6 | 1 -> 3 | 3-6 / 4-7 / 4-8, never more than the map's poles (10) | when the map stands Totem Poles |
| Deal N fire or poison damage `element_damage` | 5 | 1.5 -> 3.5 | 3,000-10,000 / 5,000-16,000 / 8,000-24,000, step 500 | fire or poison, when an item this hero may find carries it (a weapon's path mutations too) |

- 56.TASKS.13 **A target's own factor** (`target_mult` on damage_weapon, heal_item, heal_source and element_damage):
  the number range times that target's factor (empty = 1), the target drawn first; the difficulty is where the number
  fell in its own range. Healing items: Death 1.5, Temperance 1, Hot Springs 0.7, Vulture 0.4, Siesta 0.3, Cake 0.2;
  the Healing Well 0.6 (one well heals 35% of max health once).
- 56.TASKS.14 The new posters pay by the same formula as the others (54.WANTED); with these weights they are about 29%
  of the draw (40 of 136).

**Where the numbers came from.** The run sim, Sundown, the Drifter, a quarter board, the explorer bot, 10 players, seed 1
(tools/dl/sim/runs/p113-tasks-s1): the Revolver dealt 23,000-149,000 (half the runs under 30,000); fire 34,000 in the
one run with a Molotov, poison 400-7,400 in the three with a poison path; Temperance restored 8-158 HP, Siesta 5-42 (the
bot rarely stands still), Vulture 9-142, Hot Springs 57, Cake 9; the Heart 21-103 HP, the Healing Well 25-82 HP;
barrels broken 11-32 (half at least 21); Totem gifts 4-10. Nightfall, the same setup (tools/dl/sim/runs/p113-tasks-s2,
a fresh level-1 hero, 10:00): the Revolver 35,000-151,000 (half under 60,000), poison 18,000-29,000 in the three runs with
a poison path, Temperance 89-205 HP, Hot Springs 57-230, Siesta 3-32, Vulture 3-25, Cake 20, the Heart 23-170, the
Healing Well 42-85, barrels 16-30, Totem gifts 1-9. Garry's own played runs: life steal 350 HP in 3:53 and 732 HP in
10:46. Death has no sim data (it is locked on a fresh save): its 1.5 is a guess, and so are the Blood Moon ranges (grown
from Nightfall's).

Tests: game/tests/pass113_TASKS_test.gd (12); tools/level_editor/selftest_TASKS113.py; the re-run pass100_QUESTS,
pass111/112_wanted, pass111_skins, pass76_ui and their neighbours.

### 56.BOSS Each boss has a bullet-heaven attack: rare, long, guarded, with a big warning

Garry (2026-10-28): "Each of the Bosses needs a Bullet Heaven type of attack. Those attacks are supposed to be rare and
powerful. And while the boss is doing them it should be more challenging for Player to damage the boss until the attack is
done. This is supposed to be accompanied by impressive visuals." He picked option A of each boss in
docs/concepts/boss_bullet_heaven.md: the King's **Royal Dust Devil**, the Gila's **Venom Monsoon** (no weak spot), the
Brander's **Hellbrand Mandala**; and: "For each of those attacks I expect to see them in the Boss Attacks section of the
LevelEditor", "incorporated in a smart way so that they make sense with other attacks", "don't trigger immediately, and are
rare, something like once every 45s", "easy to detect as a Player. Big foreshadowing".

The rules, in plain words (every number is the attack's own, on the Level Editor's Boss attacks tab; content/boss_attacks/
royal_dust_devil, venom_monsoon, hellbrand_mandala, kind "pattern"):
- **When it comes.** Never part of the boss's attack cycle (its place in his list does not matter). Never in the first
  15 s of the fight (`trigger.first_after`). The first one comes when he falls under 60% HP (`first_at_hp`), or 45 s into
  the fight at the latest (`first_by`), so a slow fight still sees one. After that, 45 s after the last one ended
  (`cooldown`, counted from the end of his spent seconds). The fight clock is his: it starts when he arrives.
- **Only between his attacks.** It waits until he is walking: not in a wind-up, a roll, a stomp, a burrow, a tail beam,
  not standing for a rain, not still rising out of the sand, and none of his own shots still in the air.
- **The warning (2 s, `tell.seconds`).** The attack's name across the screen in its colour with his badge; the sand
  darkens in a circle 9 m round him with a pulsing ring at its edge (`tell.ring_*`); a loud rising alarm
  (en_boss_pattern_warn); the music drops 14 dB (`tell.duck_db`) until the bullets end; his own wind-up (the King spins
  faster and faster, the Gila rears up with her throat glowing, the Brander raises his iron and drives it in with a blast);
  his shell forms (a sand tornado, a glow behind her, a pillar of fire, and the Brander's brand sigil burning into the
  sand); a rumble of the camera. Like every wind-up it lasts x1/pace on the map.
- **The bullets (`timing.duration`: King 8 s, Gila 7 s, Brander 9 s).** Slow (2-3.2 m/s; the hero walks about 5), big and
  bright with a thick ink outline, never dimmed by Nightfall's or Blood Moon's filter. A bullet that touches the hero
  takes 12% of his max HP (`hit.hit_frac`) and is gone; his armour, an evade, the Shield power-up and the blink after a
  hit work as for any shot; no push (`knockback` 0). A bullet past its range (King 24 m, Gila 22 m, Brander 18 m) shrinks
  away. When the bullets end, the ones still flying burn out over 0.6 s (`timing.clear`) and hurt nobody.
- **Guarded.** From the warning's start to the last bullet he takes 80% less damage (`guard.share`): his bar turns grey
  with GUARDED in it, his outline glows in his shell's colour, and hits on him spark grey and show small grey numbers.
- **Spent (the payoff).** Then he stands dazed for 2.5 s (`spent.seconds`) taking 50% more (`spent.damage_taken`): his bar
  reads DAZED in brass; the King's tornado collapses and stars circle his crown, the Gila slumps, the Brander's pillar
  gutters out and his iron smokes.
- **The rest of the fight waits.** While it runs (warning, bullets, spent) nothing else of his starts and he summons
  nothing; he stands still (his touch still hurts); the boss fight's own rows (Timeline → Boss fights) bring nobody new and
  their clock stands still; a boss fight without such a window holds its spawns too. The creatures already there stay.
  After it, his cycle goes on after his usual rest between attacks (`timing.cooldown`, 0 = his own).
- **What each one does.**
  - Royal Dust Devil: three spiral arms of burning tumbleweeds (two side by side, 4.5 volleys a second, 3.2 m/s) turning
    50°/s, turning back the other way halfway (the safe lanes change), the hero between two arms at the start; and a ring
    of 20 with an 80° opening somewhere new every 1.7 s (2.4 m/s), from 15% to 90% of the time. About 280 in the air at its
    peak.
  - Venom Monsoon: big wobbling venom blobs in a fan of five over 56° that sweeps 150° left and right across wherever the
    hero stands (one sweep every 2 s, 2.8 volleys a second, 2.8 m/s); every second sweep a second fan of four, 50° off.
    The blobs leave purple puddles that fade in 2 s (only a look). About 130 in the air at its peak.
  - Hellbrand Mandala: a five-petal rose of 30 branded fireballs every 1.2 s (the petals at 3 m/s, the dips between them at
    a quarter of that, the petals opening and closing as the depth breathes), the mandala turning half a petal (36°) every
    3 s so the safe lines move; a slow five-arm spiral under it (2 m/s). Its last second pulls every fireball still flying
    straight back to him at 7.5 m/s: never stand between a fireball and the Brander. About 255 in the air at its peak.
- **How hard (measured, game/tools/_p113_BOSS_probe.gd, 3 runs each, the hero 9 m off when it starts).** Standing still the
  whole time: King 5-6 hits (68% of max HP), Gila 5 (60%), Brander 4 (48%). A careful player (looking 0.4 s ahead, 7-12 m
  from the boss): 0 hits on all three. Danger comes from the number of bullets, never from one hit.

Decisions of mine (not in the spec; say if they are wrong):
- The tell is 2 s (the concept doc said 1.2-1.5 s; the brief asked for big foreshadowing).
- The next one's 45 s run from the end of the spent seconds, not from the bullets' end.
- The Mandala turns 36° (half a petal) every 3 s, not 72° ("a fifth of a turn" turns a five-petal rose onto itself: no
  visible change).
- The bullets left when it ends burn out (harmless) instead of flying on, so the spent seconds are a clear payoff.
- The Gila's sprinkler sweeps across wherever the hero stands (otherwise standing behind her was safe), and the King's ring
  opening is somewhere new each ring (otherwise one spot stayed safe all attack).
- The ranges reach past the screen (18-24 m) so walking away during the warning does not escape it.
- A bullet pushes nobody; the guard also covers the warning; the boss's touch still hurts while he stands.

Tests: game/tests/pass113_BOSS_test.gd (15); tools/level_editor/selftest_BOSS113.py; selftest_BOSS.py re-pinned (the Gila's
script is one entry longer); pass72_boss, pass73_ground, pass95_BOSS, pass110_boss_window re-run.

### 56.LEAD The Monk's spheres fly as one cloud, faster and farther; a locked look is a dark silhouette; a look's goal met in a run is announced

**The Monk's volley as a cloud (rule changed).** Garry: "right now all the projectiles move towards the hero. What should
be happening is that these projectiles actually move as a cloud, kind of moving in the cloud where the center is aiming,
where the hero actually is." `squad.orb.aim`:
- **"cloud"** (the Monk, and the default for any squad): every sphere of a volley flies along **one line**, the line from
  the volley's centre (the middle of all the spheres as they leave the hands) to where the hero stands then (+ `lead` of
  his run, 0 for the Monk). The volley keeps the squad's shape as it flies: a block of blue spheres as wide as the squad
  (about 5 m for 10 monks, 7 m for 30) whose middle passes over the hero's spot. Stepping sideways out of its path is the
  dodge; standing still in the middle is a hit.
- **"each"**: every sphere aimed at the hero on its own (pass 112's rule), so they all close in on him.
- Faster: **5 m/s** (was 4; "a bit faster"; on Red Canyon's creature clock 4.05 m/s). The hero runs about 5 m/s, so he can
  still step out of the cloud's way.
- Farther: **26.25 m** (was 17.5; "extend the range of the projectiles by 50%"). Every sphere flies its 26.25 m from its
  own start, so the whole cloud bursts together.
- Nothing else changed: the squad still fires from its 5-8 m band, 3 s stops every 5.2 s, damage 8 a sphere.

**The Monk's looks.** MK-A (brown, the one played), MK-B (white) and MK-C (dark blue) are approved (no longer "fresh";
Garry: "they are all kind of ok"). The creature's base strip and icon (the "MON-0" look, what any place that shows the
creature without a look sees) are now MK-A's brown robe instead of the placeholder ("Let's make the brown ones the
default").

**A locked look on the hero sheet (rule changed).** Garry: "when the Skin is LOCKED it displays the Skin Icon as a
Darkened Silhouette." On the hero sheet's LOOKS row a look whose goal is not met yet shows its picture as a flat dark
shape (the same silhouette as a hero not yet owned in the drawer); a look without a full-body still shows its badge as
a black silhouette with a "?". Once the goal is met (on sale, owned or worn) it shows in its colours.

**A look's goal met in a run is announced (fix).** Garry: "When Player unlocks it during a run there is a notification,
similar to the other unlocks." A goal that completes when a boss falls (beat_stage: "Beat Nightfall with May.") was
marked done silently by the boss's own check, so the run's banner never showed. The boss's fall now goes through the
same check as every other unlock: the banner "NEW LOOK FOR SALE · <name>" (or "NEW LOOK · <name>" for a free one) with
the look's badge and the unlock sound, at once. Goals that complete at the end of a run (runs_total) still show on the
Results screen, as every unlock does.

Tests: game/tests/pass113_lead_test.gd; re-pinned game/tests/pass112_monk_test.gd (the sphere's range: 1.5 x pass 112's).

**The King's tornado lets him show through (the lead, at the merge).** A pattern attack's `shell.opacity` (0.5 to 1,
default 0.94) sets how solid the tornado's dust is; the King's Royal Dust Devil uses **0.62**, so his crown and face show
through the funnel while it guards him (at 0.94 the tornado hid him completely). The Level Editor's Boss attacks tab has
the row "Shell opacity".

## 57. Pass 114: the Level Editor's JSON windows and Save while a build runs, the bullet heaven twice as long, replays, a new Spit Cactus look

### 57.EDITOR The bullet heaven twice as long and twice as far with more room; its trigger as ranges; the cooldown from the true end; Saves while Godot is busy

Garry (2026-10-29): "Tumbleweed King - Royal Attack should x2 last longer and the projectiles should fly x2 further and
Increase spacing between projectiles a bit. Then tell me how I can edit this myself in the future. Same feedback for both
Venom Monsoon and Hellbrand Mandala"; "add the option of randomization for the starting pattern ... make it a range
between 10 and 15 for example. Also just to be clear, those cooldowns should be after the attack is actually over";
"Make the message about the Godot lock clearer ... This is preventing me from making saves"; "Allow for editing the JSON
directly in the 'Show JSON' window".

**The three attacks (content/boss_attacks; every number on the Boss attacks tab).** Twice as long (`timing.duration`),
twice as far (`projectile.range`), and about a quarter more room round every bullet (the angle to its neighbour times
the distance to the next volley's bullet behind it). Each emitter's `start` / `stop` are shares of the duration, so the
shape of the attack is the same over the longer time; its seconds-based rhythms (the Gila's sweep and pulse, the
Brander's turn every 3 s, his 1 s finale pull) repeat more often. The tell (2 s), the spent seconds (2.5 s), the speeds,
`hit_frac` and the triggers are as they were (the King's `first_by` 30 is Garry's own).
- Royal Dust Devil: 8 -> **16 s**, 24 -> **48 m**; the spiral arms 4.5 -> **3.6** volleys a second (25% more room along
  an arm; the two tumbleweeds side by side stay 8 deg apart, so the lanes between the arms keep their width); the ring
  20 -> **16** tumbleweeds (17.5 deg apart, was 14; the 80 deg opening as it was).
- Venom Monsoon: 7 -> **14 s**, 22 -> **44 m**; the main fan 5 blobs over 56 deg -> **4 over 52.5 deg** (17.5 deg apart,
  was 14); the second fan 4 over 40 deg -> **3 over 33 deg** (16.5 deg apart, was 13.3).
- Hellbrand Mandala: 9 -> **18 s**, 18 -> **36 m**; the rose 30 -> **24** fireballs (15 deg apart, was 12); the slow
  spiral 1.5 -> **1.2** volleys a second.
- Bullets in the air at most (no hero): King 284 -> **452**, Gila 132 -> **205**, Brander 255 -> **401**. The page's
  warning and the tests' bound moved from 400 to **600**. The pattern's tick on the PC (game/tools/_p113_BOSS_probe.gd,
  mean while bullets fly): King 0.16 -> 0.25 ms, Gila 0.09 -> 0.14 ms, Brander 0.14 -> 0.23 ms.
- How hard (the same probe, the hero 9 m off when it starts, 3 runs each; hits a run, a hit 12% of max HP):

  | | standing still | careful dodger | the run sim's bot |
  |---|---|---|---|
  | King | 5.3 -> **10** (64% -> 120% of max HP) | 0 -> **0.3** | 0 -> **0.3** |
  | Gila | 5 -> **11** (60% -> 132%) | 0 -> **0** | 0 -> **0** |
  | Brander | 4 -> **8** (48% -> 96%) | 0 -> **0** | 0 -> **0** |

  Harder only for a hero who stands still (twice as long = about twice the hits: from full HP without armour or an evade
  that is now a death in the King's and the Gila's); one who keeps moving still slips through.

**Ranges (rule new).** `trigger.first_after` (Not before), `trigger.first_by` (At the latest) and `trigger.cooldown` (Then
every) each take one number, as before, or a range `[min, max]` (0 <= min <= max; the server refuses anything else). The
game picks a number between min and max: Not before and At the latest **once per fight** (when the boss is first free),
Then every **afresh after each attack**. The dice are the fight's own (a RandomNumberGenerator per boss, seeded from the
run's seed (Run.run_seed, lane REPLAY), the boss's slot and spawn serial), never the global dice, so a replay picks the
same numbers. A fixed number takes no roll. The Boss attacks tab shows each as a "fixed / range" pair of boxes, and under
the preview the fight's first three attacks as earliest-latest start and end times.

**The cooldown starts when the attack is completely over (rule confirmed, made explicit).** Then every counts from the
end of the spent (dazed) seconds: the tell, all the bullets, their burn-out (it happens inside the spent seconds; a
burn-out longer than the spent seconds is cut there, and the page warns) and the dazed seconds are all done. A 20.5 s
Royal Dust Devil with "every 45" leaves 45 s of normal fighting between two of them. He still finishes whatever attack he
is in before the next one starts.

**Saving while Godot is busy (rule changed).** Every Save in the Level Editor (the map, an enemy, a hero, an item, a boss
attack, a look, a skin, a blood colour, the cards' look) writes the JSON at once. Its import (.tres) waits at most 8 s
for the Godot lock (it waited 2 min before, except the map's), then is queued as an import job that runs by itself when
Godot is free. The status line says who holds Godot in plain words, with the details in its tooltip (click the line to
unfold them): the build (ship.sh / ship_prod.sh, with how long it has run and its step), the tests, a script from
Claude (by name), a Test-in-game window, another import, an unknown or dead holder (with
`python tools/locks.py status` / `release godot --force` to clear it). For a build it also says whether the build being
made takes the change: saved before the build's own "json -> tres" step (ship_prod.sh: before its staging copy) = in
this build; after it = **not in this build, the next one will**. ship.sh and ship_prod.sh write their step on the lock
(`tools/locks.py note`).

**JSON windows.** The Enemies / Heroes / Items document's "Show / edit the JSON", the Boss attacks tab's "JSON…", a roster
row's, a wave's and an event's "JSON as it will be written" and the Settings tab's other keys are editable: Apply takes
the JSON exactly as typed (every key, also ones without a box) as one undoable edit and marks it unsaved; a typing
mistake is shown with its line and column and nothing changes; Cancel leaves it as it was. A document's id cannot be
changed there. A job's spec and a driver's meta stay read-only (derived).

How to change a bullet heaven yourself: docs/howto/boss_bullet_heaven.md (and the tab's "How do I change it?" fold).

Tests: game/tests/pass114_EDITOR_test.gd (6), tools/level_editor/selftest_EDITOR114.py; re-pinned
game/tests/pass113_BOSS_test.gd and selftest_BOSS113.py (the peak bound 400 -> 600), selftest_LE103.py (the Save's words,
every Save waiting SAVE_LOCK_WAIT).

### 57.REPLAY Every run recorded; replays on the build that recorded it (no gameplay number changed)

Garry: "Go ahead and implement it as described in run_replay_options.md as Option 1 ... builds saved in some kind of a
simple manner ... automatically selects the correct build ... well communicated which build is being replayed"; earlier:
"slow down functionality and a progress reel", "navigate the timeline of that play ... slow it down as well". How-to:
analytics/howto/04_replays.md; the file: analytics/SCHEMA.md "The replay file"; code: core/systems/RunReplay.gd,
Lockstep.gd, Dice.gd, game/replay/ReplayViewer.gd, tools/replay.py, tools/builds.py.

**The rules this pass adds (none changes a number the player sees):**
- **The run's seed** (`Run.run_seed`): every run gets one at its start (Game._enter_tree, before any system is ready),
  never 0; a replay forces the recording's. Every roll that can change a run comes from it: `Dice.r` (the rule dice)
  or a system's own dice seeded from it (`Dice.seed_rng`: the crowd, the pickups, the squads, the camera's shake, the
  director, the structures, the barrels, the dust devils, the cards, the totems, the bounty posters, the boss fights).
  The global randf()/randi() stream is only the looks' (particles, sound pitch, damage numbers, UI flourishes). The map
  seed's roll is taken whether a map seed is forced or not. `Run.play_clock` starts at 0 with each run.
- **The stick** every rule reads is the thumb's in 1/1024 steps (`Lockstep.q2`; a step under a twentieth of a degree, unfelt; 0.5 and 1 stay exact).
- **Rule timers** count the run's own frames (`Lockstep.after`: the bounty posters' beat, the next screen's beat, the
  Down! waits, a delayed boom, a fire drop, a structure's lift, a dust devil's burst), firing at the frame's end as the
  engine's timers did, paused with the run unless they ran through pauses before.
- **The game's own time scale** (the hit-stop, Last Stand, the drum moment) goes through `Lockstep.set_time_scale` /
  `time_scale()`: the same in play.
- **What is recorded:** the run's seed, the build id, the hero, look, stage, map and its seed, the launch, the whole
  save as the run began (`install_id` and `survey` blanked), the settings, the canvas and viewport size and the camera
  cutout; every engine frame's world steps and deltas (run-length coded); the stick at each frame's start; every
  choice a tap made by id (cards by item id, chests, the shop by card, the Stranger, totems by gift, the portal, Down!,
  TAP TO GO, pause/resume/quit, the posters, the spawn hurry, a setting changed mid-run) with its frame; every finger
  touch's place (the rings); the hero's exact place after each slide; checks every **5 s** of play (`CHECK_EVERY`) and
  the hero's track every **0.5 s** (`TRACK_EVERY`); the run's events for the reel.
- **Where:** `user://analytics/replays/<stamp>_replay.json` at the run's end; a phone keeps the newest **50**
  (`KEEP_FILES`); the editor binary mirrors it to `analytics/runs/replays/`. Not in the arena, a tool, a headless run,
  the sim, the Watch or a replay (a tool that asks: the launch's `replay_record`).
- **Sent:** as `run_replay` (parts of at most 100,000 characters, like run_record) at the run's end, only with play data
  on, never where run_record is never sent. No sampling: every run (the game has few players yet; sampling is a later
  switch).
- **Builds kept:** ship.sh stamps `game/config/build.json` (`<version>-<yyyymmdd-hhmm UTC>-<git>[-dirty]`) before both
  exports and keeps the PC exe in `builds/<id>/` (git-ignored); `tools/builds.py prune` keeps every build a recording on
  this PC names plus the newest **6** (`KEEP_NEWEST`). A `--no-pc` ship keeps no build, so its phone runs replay only
  on the nearest one.
- **The replay** runs with `--fixed-fps 64` and per frame 64 x k physics ticks (k = the recorded world steps, 1 or 2;
  jitter fix 0) and a time scale that makes every engine delta the recorded one; it never runs in a prod build (Boot
  opens it only outside prod; the prod presets leave game/replay/ out).
- **The hero's place** after each of his slides is recorded and a replay puts him there (`RunReplay.hero_moved`): the
  physics engine's own last bits (an internal order, another CPU) never part a replay through him.
- **The safety net** after a drift (the light turns red): every 0.5 s the hero is pulled half way to his recorded track
  point (when 0.25 m or more off) and his HP set to the recorded HP; a recorded card the replay does not offer is
  swapped after **60** frames (`OFFER_WAIT`) for the offered card of the same kind (else the first), and a choice whose
  screen never comes is dropped after **900** frames (`WAIT_FRAMES`); the viewer says each (`A` turns the net off).
- **Speeds:** 0.1x, 0.25x, 0.5x, 1x, 2x, 4x, 8x by pacing the recorded frames on the wall clock (each frame lasts its
  recorded time over the speed; above 1x at most 60 drawn a second), never by stretching a step.

Measured (this PC; the proof game/tools/_p114_REPLAY_proof.gd, recordings with the bot driving):
- **Exact replays** (every checkpoint's exact hash equal; recordings made with irregular frames on purpose):
  a 12-minute run with real touch events (God mode, the King and his bullet heaven, Endless, 23 level-ups, 10 chests,
  5 totems, 3 Strangers, a shop buy, 22 power-ups): **720 of 720 checks equal** headless, in the windowed viewer, and in
  an exported PC exe (the release template replays the editor binary's recording bit for bit); a 4.8-minute natural run
  (58 touches, 73 choices, 2 ad revives, a death): 286/286; frames at 47 fps (1 and 2 world steps a frame), 30 fps, 60
  fps, and real time headless (~130 fps, 0 or 1 steps): all exact; the hero's place needed the recorded correction 0 to
  3 times in 120 s (the physics engine's own last bits).
- **Size:** a 12-minute run 0.42 MB of JSON with checks every 5 s; **about 0.5 MB for 15 minutes**, sent as about 0.48 MB
  in 5 parts. Most of it is the hero's exact place a step (~0.23 MB) and the stick (~0.11 MB); a steady 60 fps phone's
  frame timing is a few KB.
- **Seeking** (this PC, frames run undrawn): to 2:30 in 30 s, to 4:58 in 70 s, the whole 12:00 in 2 min 51 s in the
  editor binary and 2 min 21 s in the exported exe (about 4 to 5 x real time; a jump back starts the run again first).
- **Builds kept:** 218.6 MB a build (the exe); six newest plus the named ones: about 1.3 GB.

Tests: game/tests/pass114_REPLAY_test.gd.

## 58. Pass 115 (v0.98)

### 58.META The game's name on screen, and Nerve: revive health only, cheap

Garry (2026-10-30): "Rename the game to `Outlaw Survivors`, but only in the game itself. Don't change anything in the code
and such. Wherever we have the title written we just write "Outlaw" with big fat text and the "Drag Dodge Survive" is
replaced with simply "Survivors"" and "Change the Revive to only affect the amount of HP Player gets when they revive in
the `Nerve` section. To make it so that the player, by default in the beginning, gets revived with 40% of their health.
By the end of this upgrade in Nerve, if it's all at max, [the player] gets revived with 100% of their health. Also skips
and this new revive thing are not valuable at all, rebalance their ordering in the view as well as their prices
accordingly."

**The name** (`W.GAME_NAME` "Outlaw Survivors", `W.GAME_WORD` "Outlaw", `W.GAME_LINE` "Survivors" in game/ui/wanted/W.gd):
- The title: **OUTLAW** in the slab (Alfa Slab One) at `TitleScreen.LOGO_PX` 190 (953 px wide, "88fits" was 652 at 210:
  OUTLAW at 210 would run off the 1080 px canvas), ink with the 10 px brass shadow, in the same 199.5 px line box, so
  nothing under it moves; **SURVIVORS** where "Drag · Dodge · Survive" was, in its style (Bitter 600 capitals, 30 px,
  0.3 em tracking, ink).
- The boot splash and loading screen (game/art/ui/splash.png, `python tools/make_splash.py`): OUTLAW at 140 px with its
  brass shadow, SURVIVORS under it as the title sets its line (it was "A survivor shooter" in Bitter italic 36 px); the
  loading bar moved up 4 px with the shorter line (Boot.gd's BAR and LABEL_Y, written by the tool). splash_icon.png has no
  words and did not change.
- The Settings version line ("Outlaw Survivors v0.98 · <player name>") and Down!'s copied hit log header.
- Left as "88fits" (not "in the game itself", or Garry asked to keep them): the project name (project.godot
  `config/name`: also the PC window's title bar and the save folder's name), the Android launcher labels ("88fits Dev",
  the prod build's "88fits"), the PC exe's product name and file name, the packages, PostHog (`88fits-godot`), the replay
  viewer's window title "88fits replay" (a tool), every code identifier and folder, the docs and the store screenshots.

**Nerve** (content/talents/nerve/nerve.json):
- **Revive health starts at 40%**: the talent's new `base_stats` {"revive_hp": 0.4} (TalentDef.base_stats, a reusable
  primitive: a talent may own a player stat's starting value; Run.hero_sheet sets it on every hero's sheet, ranks or none,
  over StatSheet.PLAYER_DEFAULTS' 0.5). Every revive reads it: Down!'s one chance a run (the ad), the debug revive.
- **Second Wind is +10% revive health a rank** (`revive_hp` add 0.1, every rank alike: 50, 60, 70, 80, 90, 100% at six) and
  gives **no revives**. It was +1 revive at ranks 1, 3, 5 and +15% revive health at 2, 4, 6 (from a 50% base). Nothing in
  the game gives `revives` now: Down! offers its one chance a run.
- **Skip** is unchanged (+1 skip a stage, a rank).
- The board says it in plain words: a talent's line folds its base into its ranks (HomesteadScreen.held_effects /
  held_line, TextGen.SET_TEXT): "Revive with 60% health", "+2 skips, revive with 50% health". The pause Stats tab and the
  hero sheet list "Health on revive" where they listed "Revives" (which nothing raises any more).
- **Phoenix Feather keeps half health** (new rule, lane META's call: Garry set the feather at "50% HP on revive" on
  2026-10-23, and a plain revive now starts lower): the feather's level gives `phoenix_hp` 0.5 (a hidden stat), and its
  revive stands him up at the larger of `revive_hp` and `phoenix_hp` (Player.revive_share): 50% with 0 or 1 Second Wind
  ranks, then 60% .. 100%. Set `phoenix_hp` to 0 in its JSON to make the feather follow the plain revive's 40%.

**The price** (rank k = k x k x rank 1, pass 110's ladder kept):

| talent | first rank | ranks 1-6 | total |
|---|---|---|---|
| Nerve before | 500 | 500, 2,000, 4,500, 8,000, 12,500, 18,000 | 45,500 |
| **Nerve now** | **150** | **150, 600, 1,350, 2,400, 3,750, 5,400** | **13,650** |

Why 150: pass 88 priced by measured power (the run sim's impact): the power talents (Grit, Stride, Study, Drive) 0.15-0.23
sit at 375-450; Fortune (Omen weak, Greed income) 300 and Choice (rerolls, banishes) 325 are the "a player values them,
a bot cannot show it" band. Nerve was the dearest at 500 because Second Wind was a whole extra life a rank. Now it is at
most +60 points of health on one revive a run, and Skip one more pass a stage: Garry calls both "not valuable at all",
so Nerve sits under Fortune and Choice at about a third of the power band, and over Stakes (100), which is a challenge
that pays gold back and stays first.

**The board's order** (by the first rank's price, then `order`, rewritten 1-8 to agree): Stakes 100, **Nerve 150**,
Fortune 300, Choice 325, Drive 375, Study 400, Stride 425, Grit 450 (Nerve was last). The whole board: 261,625 -> 229,775.

**Ranks already bought** (Save._migrate_nerve, once a save: once-flag `nerve_v115`, set on every save, a new one too, and
by buying a Nerve rank): they stay, the same count in the same forms (a Second Wind rank now gives +10% revive health).
The gold each was paid over its new price comes back. The save keeps no price a rank, so each is counted at **pass 88's
price** (500, 900, 1,500, 2,250, 3,250, 4,500: what Nerve sold at from 2026-10-18 to pass 110 on 2026-10-28; never more
than a rank bought since pass 88 cost): ranks 1-3 bring back 350, 300 and 150; ranks 4-6 cost more now than they did at
pass 88, so they bring nothing (never a negative). Never more than the board has cost in all (`talent_spent`; a board a
tool wrote cost nothing and gets nothing), and the spent total is lowered by as much, so Take it all back still returns
half of what was really paid. The Upgrade board says so once in toasts: "NERVE COSTS LESS NOW", "+800 GOLD BACK FOR 3
RANKS", and "SECOND WIND: REVIVE HEALTH" when a Second Wind rank is held. (The Stakes' refund of pass 88 was in full and
took the ranks away, because its new forms made the game harder; Nerve's ranks keep doing what their names say.)
Garry's PC save holds no Nerve rank: nothing changes on it. A phone save with Nerve ranks gets its toasts the first time
the Upgrade board opens.

Tests: game/tests/pass115_META_test.gd (re-pinned: pass46_ui_test's Second Wind, pass100_SMALL_test's feather,
pass110_econ_test's first ranks).

### 58.POLISH Far creatures catch up harder, a bigger and longer tornado, rarer barrel power-ups, bigger moving Pollen flowers

Garry (2026-10-30): "let's make it so that the speedup increases the further they are away from the player. Because
there are times when I can still outrun some enemies quite a lot. This increase has an upper bound and it's such that
heroes like Jezyk can still outrun the enemies quite a bit, but not as much as right now." / "Tornado should be a bit
bigger, last 3 times longer when it does appear, be a bit more transparent and lift both enemies and heroes a bit
higher." / "The probability of barrels dropping power-ups should be decreased by half." / "Beehive's Flowers are hard to
detect, make bigger and slightly animated."

**Far creatures** (map `timeline_data.far_speed`, Settings -> Scaling; 54.ENEMY's rule, the same creatures, the same
"only the walk" limits):
- `distance` **14 -> 12 m**, `ramp` **6 -> 24 m**, `max_mult` **2.0 -> 3.0**, new `curve` **"ease_out"** (quick at
  first, levelling off; pass 111's S-curve is "smooth"; "linear" and "ease_in" too), new `max_speed` **6.0 m/s**.
- The multiplier: 10 m x1 (x1 before), 14 m x1.32 (x1), 17 m x1.75 (x1.5), 20 m x2.11 (x2), 25 m x2.58 (x2), 30 m x2.88
  (x2), 36 m and beyond x3 (x2). Never below pass 111's at any distance; full speed just inside the 40 m despawn line.
- **New rule: the speed cap.** The boost never takes a walk past `max_speed` m/s; a creature already faster (a row's own
  speed boost) keeps its own walk, it is never slowed. 0 = no cap. This is the "upper bound": a hero who runs faster than
  6 m/s always gains on a far crowd.
- Walks (m/s, the map's pace 0.9 x Creature speed x 0.9 and the stage's speed; the hero runs straight away):

  | | own | 10 m | 20 m | 30 m | 40 m |
  |---|---|---|---|---|---|
  | skeleton, Sundown | 1.30 | 1.30 / 1.30 | 2.59 / 2.74 | 2.59 / 3.73 | 2.59 / 3.89 |
  | goblin runt, Nightfall | 2.05 | 2.05 / 2.05 | 4.10 / 4.33 | 4.10 / 5.89 | 4.10 / 6.00 |
  | fire ant, Blood Moon | 2.72 | 2.72 / 2.72 | 5.44 / 5.75 | 5.44 / 6.00 | 5.44 / 6.00 |
  | desert spider, Blood Moon (fastest regular on the map) | 2.92 | 2.92 / 2.92 | 5.83 / 6.00 | 5.83 / 6.00 | 5.83 / 6.00 |
  | Brander (boss), Blood Moon | 1.51 | 1.51 / 1.51 | 3.01 / 3.18 | 3.01 / 4.33 | 3.01 / 4.52 |
  | runt rush row r2 (its own x3), Sundown | 5.59 | 5.59 / 5.59 | 11.18 / 6.00 | 11.18 / 6.00 | 11.18 / 6.00 |

  (before / after). Heroes, measured from the run's sheet (game/tests/pass115_POLISH_test.gd): the Drifter 3.24; Jeżyk
  at level 1 without Momentum 2.78, at level 10 with full Momentum 5.45, at level 20 with full Momentum and The Chariot
  at level 4 7.51 (Sprint's power-up x1.4 on top). So a fast Jeżyk still gains at least 1.5 m/s on any far crowd; a
  level-10 Jeżyk gains 1.6 m/s on a far skeleton (2.9 under pass 111) and is caught by a far Blood Moon fire ant or
  spider; a slow hero is caught up to 12 m by everything, then the crowd walks at its own speed.
- Side effects: Garry's fast rows (r2's goblin runts x3, r22's spiders x2) arrive from far at 6 m/s instead of 11 and
  10.7; Endless's sped-up creatures are capped at 6 m/s far away too (their own walk is never slowed). Squads (the
  Monk) follow the same rule at their anchor.

**The tornado** (map `timeline_data.dust_devils`, Settings -> Dust devils; 56.TWISTER's dust devils):
- `life` **[20, 30] -> [60, 90] s** (x3). With `every` [120, 180] one now stands about half of each stage after 1:30;
  crossing the view at 1.4 m/s it is on the screen about 15 to 20 s of that, then keeps going off the screen (the extra
  life is mostly spent out of sight unless the hero follows it; "drifts about" or a lower speed keep it in view longer).
- `radius` **2.4 -> 3.0 m** (the ring the hero is thrown from 2.9 -> 3.5 m), new `size` **1.25** (the funnel 7 -> 8.75 m
  tall, its foot 0.6 -> 0.75 m, its top 2.1 -> 2.6 m across).
- New `opacity` **0.7** (the funnel's 0.94 before, x0.75; its skirt of dust 0.98 of it: 0.92 -> 0.69). Creatures and the
  hero inside and behind it show through more; it still reads as a tornado on Sundown and Nightfall.
- `toss.up` **8 -> 9.5 m/s**: the hero goes about **1.33 -> 1.88 m** up (x1.41 under his 24 m/s2; measured 1.45 -> 2.01
  m in the arena), `toss.out` 3.6 and `cooldown` 1.2 kept: thrown out of the ring within two throws, never stuck in it.
- New `lift_height` **4.5 m** (x its size; it was a fixed 3.2): creatures ride about 1.4 times as high (`lift` 1.7 s
  kept). The bees' old twister keeps 3.2 (EnemyManager.TORNADO_LIFT_H).

**Barrels' power-ups** (map `timeline_data.barrels`), half of the build Garry played (pass 114): brown `powerup_chance`
**0.08 -> 0.04** (already set so by Garry in the Level Editor before this pass; kept), black **0.3 -> 0.15**.

**The Beehive's Pollen flowers** (content/mutations/pollen `params.pollen`; core/systems/FlowerField.gd):
- New `flower_size` **1.6**: each flower 0.58-0.9 m -> 0.92-1.44 m tall. Picking unchanged (within 1.2 m of its foot).
- New `sway` **9 degrees** each way (pass 48's 4), the same 3.7 s sway; new `pulse` **0.07**: it breathes 7% bigger
  and smaller about every 2 s.
- New `halo` **0.55**: a soft ring on the sand under each flower in its colour (paler), its outer radius 0.42 m x the
  flower's size (0.54 to 0.84 m), breathing with it; see-through, so the stage filters never darken it (it reads on Nightfall's blue and the Blood
  Moon's red). 0 = no ring.

Tests: game/tests/pass115_POLISH_test.gd (re-pinned: pass111_enemy_test's empty-block x2 -> x3, pass113_TWISTER_test's
defaults and the 8 m/s throw; Level Editor selftest_ENEMY111.py and selftest_TWISTER113.py, selftest_L69.py reads
FlowerField.gd for the Pollen rows).

### 58.BOSS The King's thump reaches further, the Gila stays under longer, the bullet heaven flies faster inside a barrier

Garry (2026-10-30): "Increase the range of the Tumbleweed King thump attack. Increase by 25%"; "Gila Boss, increase the
time it takes for the Gila to pop out of the ground by 25% to give Player more time to escape"; "Special Boss Attacks ...
increase the speed of projectiles by 50% for all of them"; "add a barrier that appears around the boss and the hero. This
makes it so this Boss attack should only happen if Player is within the range of as far as the projectiles reach. Each
boss has their own barrier, but the object should be a 3d object, should appear with animation and should be easy to
'read' as a barrier so Player doesn't wonder what this is. Avoid making it so the Player gets stuck in this barrier when it
goes up. Barrier falls apart and disappears when the attack is done."

**The King's thump** (his `stomp`, the three hops with waves; content/bosses/tumbleweed_king): `radius` **6.0 -> 7.5 m**.
The one number is the whole reach: the red warning ring before each hop, the wave racing over the sand and the hit (the
hero within radius + 0.5 m, as before) all read it, so the warning grew with it.

**The Gila's burrow** (content/bosses/gila_grande): `windup` **4.0 -> 4.85 s**, `warn` **0.4 -> 0.5 s**; `sink` 0.6 as it
was. So the time under the sand unseen is 3.0 -> **3.75 s** and the red ring where she will come up shows 0.4 -> **0.5 s**
before she erupts: everything she spends in the ground x1.25 (on Red Canyon, pace 0.81: 3.7 -> 4.63 s unseen, 0.49 ->
0.62 s of ring). The sinking (in sight) and her rise are as they were. Decision of mine: the warning grew too (the brief:
"its warning on the ground follows it"); it is the part that gives the time to escape.

**The bullet heaven 50% faster** (content/boss_attacks): every emitter's `speed` x1.5, the ranges as they were:
- Royal Dust Devil: the spiral arms 3.2 -> **4.8 m/s**, the rings 2.4 -> **3.6 m/s** (range 48 m).
- Venom Monsoon: the main fan 2.8 -> **4.2 m/s**, the second fan 2.4 -> **3.6 m/s** (range 44 m).
- Hellbrand Mandala: the rose 3.0 -> **4.5 m/s**, the slow spiral 2.0 -> **3.0 m/s**, and the finale's pull home 7.5 ->
  **11.25 m/s** (also a projectile speed; range 36 m).
- The hero walks about 5 m/s: the King's arms now fly nearly as fast as he walks. Faster bullets with the same volleys a
  second are further apart along their lines and fewer are in the air: at the peak (no hero) King 452 -> **338**, Gila 205
  -> **161**, Brander 401 -> **286**. The page's warning (an emitter over 6 m/s) is not reached.

**The barrier** (a pattern's new `barrier` group; BossAttackDef, BossPatterns, Player.keep_in_fence, BossBarrier,
BarrierMeshes, core/shaders/boss_barrier.gdshader; the Level Editor's Boss attacks tab, section "The barrier"):
- **Where.** A ring round where the boss stands as the warning begins. `radius_mode` "range" (the three): `inset` 1 m
  inside the bullets' range: King **47 m**, Gila **43 m**, Brander **35 m** round him. "fixed": at `radius` (16 by
  default). Never under 3 m + half its thickness. `thickness` 0.8 m: the hero's middle is held within the inner face less
  his body (0.45 m): King 46.15, Gila 42.15, Brander 34.15 m.
- **The reach rule (new).** With a barrier the pattern begins only with the hero within reach of the boss: his middle at
  least 0.5 m (`BARRIER_KEEP`) inside where he is held, and never past the range: King **45.65 m**, Gila **41.65 m**,
  Brander **33.65 m**. When it is due and he is further off, it waits: its clock goes on, nothing is rolled again, and it
  begins on the first tick he is in reach (and the boss is between attacks, as before). Without a barrier (look "none")
  there is no reach rule (pass 113's behaviour).
- **Never trapped.** Because of the reach rule the wall never comes up on him: at the rise he stands at least 0.5 m
  inside the face he is held at (at the wall's middle line +- 0.3 m it waits). From the rise he is held inside: after
  every move (his walk, a shove, a throw, a leap, a tornado's lift, a dash) his flat place is kept within the limit and
  the outward part of his velocity and of a shove is dropped, so he slides along it. A Teleport while it stands lands him
  only inside it (1 m inside the hold; no landing inside = no teleport).
- **When it stands.** It rises with the warning (each stretch `rise_s` 0.8 s out of the sand with a little overshoot,
  the stretch on the hero's side first, round the ring over `spread_s` 0.6 s: up within 1.4 s, inside the 2 s warning)
  and holds through the bullets; `hold` "bullets" (the three): it falls apart as the bullets end, as he is dazed (the hero
  is free then); "spent": through his dazed seconds too. It also comes down whenever the pattern is called off (the boss
  killed or gone). It falls over `fall_s` 1.0 s per piece, the pieces starting at random over `spread_s`.
- **Creatures** (`creatures` "block", the three): every creature stays on the side it was on as it rose (one that comes
  later takes the side it is on): the ones inside never past the inner face, the ones outside never past the outer face
  (they pile up against it); only their place is held. "pass": they walk through. The boss stands in the middle.
- **Bullets** (`bullets` "stop", the three): a pattern bullet that reaches the inner face stops there and shrinks away
  (0.3 s, harmless) with a small spark in its colour where the hero can see (one every 0.06 s at most); so the bullets
  reach 46.6 / 42.6 / 34.6 m instead of 48 / 44 / 36. "pass": they fly on to the range. Other shots (the creatures') pass
  through it.
- **The looks** (3D, built in code from simple shapes, lit by the scene, glowing bits in `glow_color`; they write the
  structures' stencil, so the stage filters tint them a third as much as the sand and a creature behind one is outlined):
  - the King's **tumbleweed fence** (`glow_color` #FF8A1F): rough wooden stakes with rope wraps and two sagging ropes, a
    hedge of three dark tumbleweeds a stretch (1.8 m), smouldering with orange embers; as it falls the stakes topple and
    the tumbleweeds roll away across the line, bounce once and sink;
  - the Gila's **cactus fence** (#9A44FF): three ribbed organ-pipe cactus columns a stretch (1.3 m) with pale spines,
    clumps of long thorns, purple venom blooms on their tops; they topple and sink;
  - the Brander's **iron fence** (#FF6A1A): black iron bars with orange-hot spear heads, a red-hot lower rail and a black
    upper one, and every fourth post a branding iron with a glowing brand (a ring and a cross); the bars topple and sink.
  - `height` 1.8 m (the hero is about 1.9), `color` #FFFFFF (times its paint). Stretches past the map's edge are not
    made: the map's own wall closes the ring there. The rise throws up sand and a thud where the hero can see, the fall
    sand and a crash (en_boulder_land, st_barrel_break). Its own seeded dice (never the run's).
- **What the hero sees.** At the range the wall stands 35-47 m from the boss: the phone shows about 12 m round the hero,
  so while he dodges near the boss it is off the screen, and he meets it only when he runs out (it is there, rising on his
  side first, when he is near the edge as it comes up). Decision of mine (the brief's): the barrier at the bullets' range,
  so every spot inside can be hit, Garry's pass 114 "fly x2 further" kept. To see it during the fight: Where it stands =
  fixed, Radius 12-16 m (the capture king_fixed14_*.png; the bullets then vanish at it).
- **Cost** (game/tools/_p115_BOSS_cost.gd, the PC): the pieces built once a run (the King's 3.6 ms, the Gila's 1.3, the
  Brander's 0.4; the iron fence's under the spawn beam, Warmup), each ring laid out as the warning begins in about 5 ms
  (King 165 stretches / 1,485 pieces, Gila 208 / 1,512, Brander 130 / 1,040, fewer where the ring leaves the map), then
  0.01 ms a frame (the whole rise and fall run in the shader). One MultiMesh per kind of piece and 14 m of ring, so only
  the stretches on the screen are drawn (3-4 stretches' MultiMeshes, about 12-16 draw calls, when he stands at it).
- **How hard** (game/tools/_p113_BOSS_probe.gd, 3 runs each, the hero 9 m off when it starts; a hit 12% of max HP; the
  barrier at 35-47 m does not reach these pilots):

  | | standing still | careful dodger (0.4 s look-ahead) | the run sim's bot |
  |---|---|---|---|
  | King | 8.3 -> **8.0** (100% -> 96%) | 0.7 -> **0.7** | 0.3 -> **0** |
  | Gila | 11 -> **13** (132% -> 156%) | 0 -> **0** | 0 -> **0** |
  | Brander | 8 -> **9** (96% -> 108%) | 0 -> **0** | 0 -> **0** |

  Standing still costs a little more (the Gila and the Brander one bullet more); a hero who keeps moving still slips
  through (the probe's dodger sees 0.4 s ahead perfectly; a person reacts later, and the bullets now cover in that time
  half as much ground again: 1.9 m instead of 1.3 for the King's arms, so it is harder for a player than these numbers
  say). The bullets are faster but further apart along their lines, so the field is thinner.

Decisions of mine (not in the spec; say if they are wrong):
- The barrier at the bullets' range (as the brief says), not on the screen: he sees it only near the edge. Fixed 12-16 m
  would show it while he dodges (one dropdown and one number per attack).
- It falls apart as the bullets end, not after the dazed seconds (`hold` "bullets"; "spent" is one choice away).
- Creatures keep to their side; bullets vanish at it; other shots pass through it.
- The pattern waits (does not start) when he is at the wall's line; the wall is never pushed out to fit him.
- The Gila's warning ring grew with her wait (0.4 -> 0.5 s); the Brander's finale pull got the 50% too.
- The rise and fall sounds are existing ones (en_boulder_land, st_barrel_break), played where he can see the wall.

Tests: game/tests/pass115_BOSS_test.gd (15); re-pinned pass114_EDITOR_test (the speed x1.5, the room from the counts),
pass95_BOSS_test (the stomp's 7.5 m ring, wave and the hero 1 m past it), pass73_ground_test (the Gila under 3.75 s);
tools/level_editor/selftest_BOSS115.py (45), selftest_BOSS95.py and selftest_GROUND.py re-pinned. Captures:
tools/dl/p115/BOSS/shots/ (king_s1, gila_s2 Nightfall, brander_s3 Blood Moon, king_fixed14_s1), lab3/ (close ups).

### 58.LEAD The lead's calls (pass 115)
- **The bullet-heaven barrier stands 14 m round the boss** (`barrier.radius_mode` "fixed", `radius` 14 in all three
  attacks), not at the bullets' range (35-47 m) as 58.BOSS built it: at the range it was off screen in every normal fight,
  and Garry asked for a wall the player reads at a glance and is not trapped in. With it the reach rule reads the wall:
  the attack begins only with the hero within about 13 m of the boss, and every bullet stops at the wall's inner face,
  so the 2x range of pass 114 now matters only if he sets `radius_mode` back to "range" (Level Editor, Boss attacks,
  Barrier: "Where it stands").

## 59. Pass 116: lanes' rules

### 59.RESULTS

- **Endless with a Wanted poster open** (Garry: "If Player is playing the Endless Mode and they have a Wanted Task to
  finish this stat increase on enemies is only 33% as effective as it normally is. The moment Player manages to
  complete the task the stat increase picks up from there at a normal regular pace."). Map key
  `timeline_data.endless.open_task_growth` (default 0.33; Level Editor, Endless: "Growth with a Wanted poster open").
  While the run's poster is open (taken, neither done nor failed) each new Endless wave adds only 0.33 of a growth step:
  HP (hp_growth, compounding), attack (atk_growth) and speed (speed_growth, also on the creatures already alive) use
  the steps reached, not the wave number; Endless's knock resistance climbs at 0.33 of its pace. Once the poster is
  done (or failed: it can no longer be finished) every wave adds a whole step again from where the growth stands, so
  nothing jumps; what the open poster held back is never made up. The wave count, the wave sizes, the XP and coin rules
  are unchanged. Code: WaveDirector.endless_growth_share, Run.endless_growth_steps / endless_growth_seconds,
  WaveTimeline.endless_mults_steps. If Endless ever feels oddly gentle, an open poster is the reason.
- **Results, the bounty** (show only, no new numbers paid): after the banked gold counts, the poster's panel fades in, its
  bar counts from 0 to how far the run came (1.1 s of BOUNTY_TIME 1.6 s), a stamp lands (PAID / FAILED / NOT DONE), the
  reward shows as a coin and a gold "+N"; a paid one then flies 6 coins into the Banked count, which ticks up by N
  (BOUNTY_PAY_TIME 1.1 s). The reward is still paid once, at the run's end (WantedRun.settle); a tap hurries or skips it
  like the rest of the show.
- **Dragon's Breath ready sign**: when its cooldown runs out a small spiky ring of flame collapses into the hero's face
  in 0.45 s (blue with Blue Flame). A look only; `params.breath.ready_sign: false` turns it off.

### 59.REPLAY What a replay shows is what was played (no gameplay number changed)

Garry: "the Replay watch tool still randomizes the Elites that spawn ... I got a different Elite while playing from the
one that I saw when watching the replay".
- **The cause**: the wave director drew everything from one stream of dice: the Elite's modifier, the specials, and
  the power-up roll on every single kill. One kill more or less in the replay (the phone's ARM and the PC's x86 work
  floats a hair differently, so late in a run a shot can miss in one and hit in the other) moved every later draw,
  so the next Elite came with another modifier.
- **Now**: the director has four streams, all from the run's seed: the spawns' own, the **Elites'** (modifier and
  roster creature), the **specials'** (when and which), and the **per-kill power-up drops'**. Kills only move the drop
  stream, so the n-th Elite of a run is the same Elite in its replay, whatever the crowd did. Its spot (a ring round
  the hero) still follows where the hero and the crowd are.
- **Random Elite modifiers** are drawn from the modifiers sorted by id (before: the order the content folders were
  read in, which can differ between a phone build and the PC); the structures' shuffle the same; a weapon's mutations
  tie-break by id.
- **Each run its own seed** (a bug found on the way): every run after the first in one sitting reused the first run's
  seed (the dice repeated) until the app closed. A tool's seed (the run sim, the Watch) is now kept apart.
- **Replay checks** also compare a digest of the run's events (Elites, modifiers, specials, totem offers, bosses, the
  Stranger: `ev`) and the director's dice (`wd`); recordings from 0.97/0.98 have neither and are compared as before.

### 59.FIGHT Monks, charges, the Gila's warning, the Invisible Box
- **Monks** (content/enemies/monk `squad`): they stand with their near edge between `keep_distance` 8 m (was 4) and
  `range` 12 m (was 6) from the hero and shoot from there; the spheres fly `orb.range` 52.5 m (was 26.25). On a
  portrait phone the view reaches about 6-7 m to each side of the hero and about 9-12 m up/down, so a squad standing
  at 8-12 m is at or just past the screen's edge to the side, and its spheres cross the whole screen.
- **Bull Beetle** `charge.trigger_range` 9.0 m (Garry's 7.5 x 1.2); **Dune Scorpion** (the Scorpion Elite) 9.9 m (the
  Beetle's x 1.1; was 8.0).
- **The Gila's eruption warning**: her burrow's `warn` 3.0 s (was 0.5): that many seconds (x 1/pace: 3.7 s at Red
  Canyon's 0.81) before she comes up a red ring the size of the real hit (`radius` 5 m) lies on the spot, which is
  locked at the warning's start where the hero will be `predict` (0.6) s on; inside it a red disc fills out to the ring
  at the moment she erupts, and the ring pulses (`warn_pulse_hz` 2 a second, quickening to 4). `warn_fill: false` on a
  burrow row brings back the old fading ring. Her whole time in the sand is unchanged (wind-up 4.85 s less the 0.6 s
  sink = 4.25 s, pass 115's x1.25 of pass 114's 3.4 s, which was already in the game); the unmarked wait before the
  warning is now 1.25 s.
- **May's Invisible Box** (content/perks/invisible_box, `special` "box", her second perk, rare, weight 6): after
  `first` 10 s, then every `every` 25 s, a see-through box with white edges rises round her for `seconds` 3 s
  (stretched by buff duration like every buff), turning `spin` 0.35 rad a second. While it stands every hit is blocked
  as the Shield power-up blocks it: no damage, no shove ("BLOCK"); each blocked hit flashes the box and sends a white
  ripple over the face it struck. Its size is `width` 2 m x `height` 2.4 m; while the Shield power-up's bubble is up too
  the box grows to stand round it (2.94 m wide, 2.52 m high) and draws after it, so both read. The card text is
  written from these numbers (TextGen.perk_text).

### 59.MAP Three barrel kinds, painted; every stage run its own map
- Three barrel kinds (Garry's "Barrel Variant Terrain Comparison Board"), painted billboards cut straight from it
  (tools/cut_barrels.py -> game/art/sprites/barrels/barrel_exp|coins|powerup.png; core/systems/BarrelField.gd):
  - **EXP** (brown wood, iron hoops): 8 small gems, no coins, never a power-up. Weight 0.648 (~65% of barrels).
  - **EXP + Coins** (gold hoops and studs; pass 87's black barrel): 10 small + 4 medium gems, 1-5 coins, never a
    power-up. Weight 0.22 (~22%); the map's last two start spots are always this kind (pass 87 EXTRA_DARK).
  - **Power-up** (iron hoops, a white stripe): no gems, no coins, a power-up thrown out the pass 112 way (powerup_chance
    1.0, the old black barrel's list heart 6 / rage 3 / sprint 3 / shield 2 / magnet_pulse 2 / nuke 2, 5-7 m). Weight
    0.132 = 0.6 x the EXP + Coins weight (Garry: "about 60% of the amount of the EXP+Coins").
  - The weights pick each start barrel's kind and each respawned barrel's kind (the respawn's old `black_chance` is
    ignored). Keys: `timeline_data.barrels.exp|coins|powerup` {weight, gems_small, gems_medium, coins; powerup only:
    powerup_chance, powerups, throw_distance}; the old `brown`/`black` blocks are read as exp/coins (their power-up keys
    dropped, the powerup kind takes the old black list when it has none). Level Editor: Settings, Barrels card.
  - Heights (the square picture's side): EXP 1.06 m, EXP + Coins 1.15 m, Power-up 1.12 m (the board's relative sizes).
    They draw on the structures' stencil (5): outlines behind them and the stage filters as before.
  - Splinters: wood for all, gold bits from the EXP + Coins one, white stripe bits from the Power-up one. "A GOOD
    BARREL" toast and the bigger kick stay with the EXP + Coins one. The bot treats both rarer kinds as the good barrel.
- Every stage run rolls its own map (river, oases, props, totems, teleports, barrels): `Run.map_seed` comes from the run's
  own seed, and since lane REPLAY's fix this pass every run (each stage start included) gets a fresh seed; before it, every
  run in one app session reused the first run's seed, so stages 2 and 3 replayed stage 1's layout. A replay forces the
  run's seed and gets the same map. The fort wall and cliffs are a full ring round the map, so they look the same on every
  map by design.

### 59.STAGE Stage 3 (Blood Moon) rewritten: paced, themed, a fair ramp

- Every roster row of stage 3's window (map clock 1031..1810, the Blood Moon's 0:00..13:00) was replaced; stages 1 and
  2, the events (the Elite at 6:30 = 1420, the Brander at 13:00 = 1810), the boss fight window and every map-wide number
  (cap curve, hell_cap, HP/ATK curves, stage_mults) are unchanged. The old rows are kept in
  tools/dl/p116/STAGE/old_stage3_rows.json; the rewrite is tools/dl/p116/STAGE/stage3_rows.py.
- Why: the old stage opened on three continuous rows (imps on the hell channel, skeletons, fire ants) that filled the
  cap (about 320 alive) within 10 s; a fresh hero with half the board died at 0:20 (median of 8 sims), all 8 before 0:50.
- The new rule of the stage: mostly waves and set pieces in Garry's stage 1-2 style, continuous rows only with a
  `max_alive` (imps 18 -> 35 -> 50, hellhounds 10 -> 16 -> 22 alive at most, by phase), something new every 40-90 s.
  Theme: the dead wake (red-tinted skeletons and KN-E knights), hell leaks through (imps and hellhounds on the hell
  channel, ANT-E/ANT-B fire ants, RG-B red goblins and runts), a cult's rite (a dark MK-C monk squad, dust shamans),
  the mummies rise (DM-G, one shielded Cyclopean Mummy), hell's heavies (HG-C giants, red gunmen, bombers), and at
  9:35 the Blood Moon rises: a red werewolf pack (banner BLOOD MOON!) and werewolf waves to 12:20; 12:20..13:00 is a
  breather before the Brander. Early rows hit softer (damage_mult 0.6-0.7) and creature HP is set per row (hp_mult
  0.06-0.6, rising by phase).
- Rows with no end (imps, hellhounds, knights, shaman, giant, plus fire ants and werewolves from 13:01, once the Brander is up) feed Endless.

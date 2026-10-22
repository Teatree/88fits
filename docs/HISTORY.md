# 88fits pass history

Every pass from the first playable build to today, as it was recorded in CLAUDE.md's Status section until 2026-10-10 (moved here to keep CLAUDE.md small: every agent loads CLAUDE.md, nobody needs all of this at once). Newest at the bottom. Search it for a symbol, a file or a pass number (`grep -n "Pass 58" docs/HISTORY.md`) when you need the why behind something; CLAUDE.md's Status section says what is true now.

## Up to pass 63 (2026-10-10)

M0-M4 are implemented and the game ships to Garry's phone through Google Drive (`bash tools/ship.sh` -> signed release APK -> `E:/My Drive/88fits builds/88fits.apk`; see `docs/RUNNING.md` and the ship-to-phone skill). One map, **Red Canyon** (`world/maps/red_canyon/RedCanyon.gd`): terrain from noise with two dry rivers and a red-rock rim (3-texture `terrain_painted.gdshader`, vertex colour r = river, b = rock), a mountain wall of ridge meshes (`_ridge`), and nothing else in 3D: cacti/trees/bushes/rocks/bones/signs and the seven structures (`st_<id>.png`, `StructureManager` draws a BillboardSprite when the painting exists and swaps in `st_<id>_off.png` once used) are painted 2.5D (`tools/gen_props.py` -> `art/sprites/props/` + `props.json`, `PropField`, seeded scatter); only the movers stay 3D: tumbleweeds (GLB) and the dust devil cone (`world/features/`). Dry Gulch and the meadow are shelved in `tools/dl/backup/`. Creatures: goblin, runt (back in pass 33.5; the skeletons are retired), fire ant, sand lizard (runner), spit cactus, dust mummy, bull beetle, the Dune Scorpion (Elite, `outline_frac`/`outline_color` in its JSON), the Tumbleweed King. Heroes: Astro (default) and Drifter are playable; Dad, Buck and Mira are `hidden` (pass 33.4). Buck: (`specials: ["momentum"]` + `momentum {ramp_seconds, speed_bonus, might_bonus}`: Player ramps `Run.momentum`, reset on a hit, applied in `Run._build_player_sheet`). Weapons 15 / passives 13 / evolutions 15: poison and fire families (both may share a run since pass 36; the one-element rule is gone), Tommy Gun (`params.burst`: ProjectileEmitter fires the burst one round per 50 ms; Familiar), Land Mine (`MineLayer` behaviour + `core/systems/Mine.gd`), Quickdraw, Leech (`lifesteal` player stat, `Run.add_damage` -> `lifesteal_healed`). Chests: one-reel slot machine (`ui/ChestScreen.gd`), Take/Sell; elites/bosses always, regulars by `drops.chest`; a boss kill pulls every gem, coin and chest to the hero (`PickupManager.vacuum_all(true, true)`, `Chest.pulled`). Level-up loop: every run starts with one reroll and one banish (`StatSheet.PLAYER_DEFAULTS`), skip is always on and pays `Run.skip_gold()` (10 + 15 per Skip Bonus tier), banish replaces only the banished card (`CardPool.level_up_offer(count, exclude)`), spent buttons stay tappable but dim. `Run.element_of` reads an item's element off its stats when the JSON has no `element`. Passive mechanisms (pass 23, stats on the player sheet consumed by systems): `crit_chance`/`crit_damage`, `execute_frac`, `overkill` (EnemyManager.damage), `thorns` (Game._on_player_hit), `cooldown_on_kill` (Game._on_enemy_died), `adrenaline_speed`/`adrenaline_might` (Run.add_kill stacks, `Run.adrenaline`, folded after the passives in `_build_player_sheet`, HUD label), `xp_gain` (Run.add_xp); passives deadeye, guillotine, cactus_coat, adrenaline, overkill, trigger_happy, field_notes; flat passives cap at 5 levels, multishot at 3. Heroes carry a named trait (`trait_name`, `trait_text`, `level_heal` in CharacterDef) shown in play setup, collection and pause; Buck's momentum draws `Fx.trail` through `Player.momentum_trail`. Prop colliders are 62% of the painted foot (`props.json`, gen_props PROPS) with 0.08 m of steering padding. The Tommy Gun's Familiar has a sideways drum (`Drum` node turns per round), recoil (`ProjectileEmitter._recoil`), a Muzzle particle and `Fx.shell` casings. The launcher icon is a painted illustration (`tools/gen_app_icon.py` candidates, `--pick=<seed>`; `gen_art.app_icon` composes from `tools/dl/app_icon/icon_src.png`). Pass 24: death opens `ui/ReviveScreen.gd` (8 s count, free ad stand-in, 150 gold flat, give up, a dim always-on debug revive; one chance per run + shop Revive tiers, `Run.revives_used`, revive at 50% HP). Homing missiles are a ProjectileManager mode (`launch_missile`, `homing[]`, `_fly_missile`: wander/corkscrew then lock, `params.missile {wander, turn, spiral, life, trail}`, `homing_turn` player stat) fired by `core/behaviors/MissilePod.gd` (Familiar pod, queued volleys): weapons rocket_pod/hornet_nest, evolutions missile_massacre/killer_swarm, passives guidance_fins/payload; trails have per-dot colour and size. Weapon `tags` + `target: "tag:<tag>"` effects (WeaponInstance.rebuild); the player sheet is `scope = "player"` and never folds weapon-targeted effects. Ricochet (`ricochet` stat, bounce once at 60% in the projectile hit loop) replaced Trigger Happy. Creatures: horned_toad (armor via `EnemyDef.armor`), trapdoor_spider (`brain: ambush` + `ambush {trigger, rehide_distance, rehide_after}` + a `charge` block; `EnemyManager.hidden[]` keeps buried creatures out of the grid, the render and damage), jackalope, dust_shaman (`brain: support`, `support {keep_distance, range, interval, radius, heal}`, `_support_pulse`); boss gila_grande (attacks `spit_volley` with a `fan` telegraph and `burrow` with `ring_at_hero`; `drops.chests/coins` size the boss reward in Game). Timeline roster rows carry `weight_late` reached at `weight_late_t` (WaveDirector._roster_weight); stage 2 has its own boss event. The Tommy Gun is a Blender model (`tools/blender_tommy.py` -> `art/props/tommy_gun.glb` with a `Drum` node, plus the gold `chicago_typewriter.glb`; the visual scenes instance the GLB) and its icons are painted from the model's side render (`tools/gen_tommy_icon.py`). Hero JSON `pose_hint`/`side_hint` join `back_hint`; `key_sat` and `grade` (artkit, applied to the keyed figure) exist for a garment that shares the screen's hue (Mira's denim), and hero run cycles go on the screen colour furthest from the figure's palette (`animate._screen_for`), with the view spelled out and a vision check on back cycles (see docs/RUNNING.md). `Game.no_random_chests` is the capture tool's switch. Collection rows are `MOUSE_FILTER_PASS` so the list scrolls on touch. Pass 25: hub screens scroll by hand (`ScreenBase._input` reads ScreenTouch/ScreenDrag at the viewport and moves `scroll.scroll_vertical`, with a fling), because touch drags never reached the ScrollContainer through the row controls. The meta is the **homestead** (`ui/HomesteadScreen.gd/.tscn` replaces the Shop route): `content/buildings/<id>` (`BuildingDef`: `unlocks` = shop upgrade ids, `levels` = [{gold, bones, relics}]), Blender models in `art/props/meta/` (`tools/blender_meta.py`, preview with `tools/blender_preview.py`), Save `buildings`/`materials` + `building_level/upgrade_building/tier_open` (a building at level N opens tier N of each upgrade it keeps; `Save.buy_tier` is gated), `Run.run_materials` banked in `Game.end_run` (all on extract, half on death), drops in `_on_enemy_died` (Elites → bones, bosses → relics via `drops.relics`; Mira's `motherlode` special +1). The dice shrine is gone; `hooded_figure` (`effect: stranger`) opens `ui/StrangerScreen.gd` with `Run.stranger_offer()` (rare/epic only, weapon to Lv 3 / passive to Lv 2, +2 if held) and `Run.stranger_take()` (`Run.stranger_cost` folds −max_hp into the player sheet); its spent painting is the empty cloak. Blades: `core/behaviors/Thruster.gd` (a 3D `Blade` node scaled to reach, out/hold/back, hit-test along the line, fires only with a creature in reach; `params.thrust {out, hold, back, width, fan_deg, sweep_deg}`), weapons sabre/pike, evolutions zweihander/halberd, passives whetstone/long_arm aimed at `tag:blade`. Creatures: every enemy JSON carries a `doc` line and `tools/make_bible.py` generates the bible's creature table from it (`{{CREATURES}}`); `EnemyDef.death_burst` (the toad, via `Game.elite_explosion`), `ranged.straight/pull/life` (`Game.enemy_shot_straight`, silk pulls with `apply_knockback` toward `origin`; the spider's ambush erupts into a telegraphed silk line, no `charge` block), the shaman's `support.frenzy_seconds` (`frenzy_t[]` +30% speed) with per-creature sparks and a one-time hint (`Game.hint_once`), `brain: caster` (the Mirage Djinn: `caster {keep_distance, range}` + `boss.attacks` run by the per-index attack runner `_update_attacks` with `atk_i/atk_t/atk_target`; new attacks `blink`, `slam_at`; the boss uses the same arrays), `goblin_slinger` (stage-1 straight stone). Elite events list ids (`enemy: [..]`, `WaveDirector._pick_id`). All damage telegraphs are red (`_telegraph_shot`: a line for straight shots, a ring on the hero for lobs). Red Canyon has a stacked-stone boundary wall with posts and skulls (`_boundary_wall`). The chest is `art/props/meta/chest.glb` (Body + hinged `Lid`). Structure placement relaxes spacing until every kind lands. Mira (`content/characters/mira`, trait Motherlode). Power-ups drop from kills (`WaveDirector.drop_pickup_from`: timeline `pickups {per_kill, roster[{id, weight, hard_bias}]}`). After level-up cards or the reel, `ui/ResumeGate.gd` holds the pause until a tap and gives 1 s of blinking `invuln`. `core/systems/Warmup.gd` draws every creature type, projectile kind, weapon visual, effect and font once under the hero during the starter pick so no shader compiles mid-run (`EnemyManager.warm_draw`, `ProjectileManager.warm_draw`). Deaths: painted `_dead` still + 5-frame fall for everyone (`die` 8 fps, DIE_TIME 1.4 s). Hit: painted `hurt` stills. Fx pooled MultiMeshes; no point lights on phones; 3D at 80% on mobile; `Perf` counters (`smoke_run.gd -- perf=1`). HUD: boss/Elite edge chevron; the hero's health and shield bars are drawn by the HUD at `CameraRig.hero_anchor()` (pass 33.6). Art: Flux.2 Klein stills + Wan 2.2 clips (heroes pose-driven via Mixamo) on ComfyUI 192.168.137.54:8188, LM Studio vision QA on 1234; Props, structures and the Sand Lizard were painted on Flux.2 dev (pass 22): `gen_props.py` uses dev by default (`--klein` for the small model), `gen_art.py --dev` for creatures; both call `comfy.release_models()` after every render (unload, then `systemctl --user restart ai-comfyui.service` over ssh when RAM stays above 20 GB), because dev + its text encoder do not fit the server's RAM twice. Open-canopy props and the structures (`OPEN_CANOPY` in gen_props) tolerate enclosed transparency, since branches and arches are real gaps; the skull always trips the vision face check (sockets). Cards/reel/shop share `UiKit.item_header` (level chip + pips + "Next:"). Camera fixed north-up 22.5 m; joystick on touch, WASD on PC. The design bible is assembled by `python tools/make_bible.py --shots=<dir>` from `docs/design/src/` (edit the parts, not the output). App icon = Astro's badge (`gen_art.app_icon`). Pass 26 (the paths): `content/mutations` (MutationDef: weapon family, kind element|volume|motion|hero, element, hero, text, vfx, effects, params, optional behavior/visual), `content/lines` (LineDef extends PassiveDef: ranked, `trade`), `content/perks` (PerkDef: hero, effects, `special` + params). Run: `weapon_cap()` from the map's `weapon_cap [4,5,6]`, `mutations`/`mutation_stage`/`mutation_misses` (one path pick per weapon per stage from Lv 3, `MUTATION_FROM_LEVEL`, `can_mutate`, `open_mutations`, `add_mutation(id, force)`), `lines` (two a run, `MAX_LINES`), `perks` (`has_perk`, `perk_param`), `note_offer`; evolutions need `EVOLVE_MUTATIONS` (2) mutations, the passive keys are gone (`evolves_with` empty); the Stranger sells a closed mutation at 20%. WeaponInstance: `mutations`, merged `params` (behaviours read `inst.params`), `behavior()`, `visual_scene()`, `family_id()`; Game `_sync_weapons` rebuilds a behaviour on a swap. CardPool: five card kinds, limits (one new weapon, one line, one perk per offer), `_force_mutation`. UI: `UiKit.kind_of`, mutation cards framed in `TYPE_COLORS.mutation`, path pips, HUD padlocks and path dots, pause/collection list paths. Primitives: EnemyManager `slow/slow_radius`, `mark_t`, `twist` (spin + lift), `hold_t`, `poison_pass`, `fire_vuln`, `poison_slow`, cone shots (`ranged.cone_deg/count` + `Telegraphs.sector`), the Djinn's `rain` attack (`_rains`, `min_range`), the Ram; ProjectileManager `ret` (boomerang), `stuck` (sticky), `_burst_spawn` (ember/shrapnel), weapon-level ricochet, elements on blasts and seeker stings; `Zone` (ground patch); Orbiter gyro/lasso/strike; ProjectileEmitter sweep/momentum rounds/double_every/double_tap; Beam elements + zones; Thruster elements + lunge; Mine leap/element crater/gold. Buckshot Dwarf replaces the Goblin Slinger. Six passives retired (might, spurs, sombrero, snake_oil, leech, cactus_coat → lines) and five folded (guidance_fins, payload, whetstone, long_arm, conductor → mutations). The bible's 08b tables are generated (`{{MUTATIONS}}`, `{{LINES}}`, `{{PERKS}}`). Pass 27: the homestead is a farm: `content/buildings` carry `produces` + `yield` per level (Forge ore, Ranch hides, Stable feed, Saloon whiskey, Well water; the Well replaced the Watchtower) and the Market (`market: true`, `rates`, `rate_mult`); `Save.harvest(frac)` at `Game.end_run` (all on extract, half on death) fills `Save.stock`, `Save.sell_stock` turns it into `silver`, `Save.buy_tier` spends silver; resource icons in `content/resources`; models in `blender_meta.py` (well, market). Paths go on the table whole at set slots (`path_times` in the map timeline, `Run.path_due/next_path_weapon`, `CardPool.path_offer`, `Game.present_path_offer`, CardScreen `path_mode`); mutations never appear in level-ups. The Dune Centipede (`erupt` attack: a rain that spawns `sand_centipede`) replaced the Mirage Djinn. Rocket smoke is dark with a hot core; Tommy Gun rounds are box tracers (`params.tracer`); `Fx.lightning` draws ribbons; `CameraRig` zooms with speed (log, ×2 cap); `Chest` has a breathing ring and a glint; the shield is a holographic sphere (`core/shaders/holo_shield.gdshader`, `Player.shield`); variant tints are 0.22 with dark saturated specials. Pass 28: Red Canyon rolls its layout per run (`Run.map_seed`, `forced_map_seed` from `debug_launch.json` for captures): `_roll_layout` makes one dry river (waypoints rim to rim, bent around the flats) and one oasis (`_lake_c/_lake_r`, a dish in `_terrain_height`, a water disc on `core/shaders/oasis_water.gdshader`, a collider + obstacle), `_scatter_sprites` places by region (oasis palms, three green stands, river banks, rock fields, lone bushes; `river_points/lake_center/lake_radius` for tools); props fan_palm/ocotillo/yucca, bushes radius 0 in `gen_props.PROPS`. The timeline's cap ramps linearly (`cap_per_minute 2.5`, `cap_per_stage 0`, 25 → 63) and the roster's arrivals span the three stages; `EnemyDef.max_alive` + `EnemyManager.alive_of` + `WaveDirector._roster_open` cap a creature's live count. `sand_crab` (flock, pack 8) replaced `trapdoor_spider`; `harpoon_troglodyte` (kite, `ranged.harpoon` + `tether {length, seconds, slow}`, `max_alive 1`): the shot carries `harpoon/shooter/tether`, the hit calls `Game.tether_start`, `_tick_tether` runs `EnemyManager.tether_pull` (a distance constraint) and draws the rope (`_draw_rope`, ImmediateMesh ribbon), `Player.tether_slow` scales move speed, `tethered_i` braces the kite brain. `MissilePod` animates `Familiar/Body/Cluster` (quarter turn per launch, `Tip1..4` hide and pop back on reload). `WeaponBehavior.refresh_marks/_tick_marks` hang a mutation emblem per pick over Familiar/Held/shoulder (Game._sync_weapons refreshes). PauseScreen scrolls by hand like ScreenBase. Pass 29: the timeline scales creatures with the hero (`level_hp_per_level`, `level_damage_per_level` → `EnemyManager.level_hp_mult/level_dmg_mult`, set by the director) and the cap runs 25 → 150; `brain: artillery` (`EnemyDef.artillery {stand_off, windup, missile}`: `_stand_off` at spawn, one wind-up, `_fire_artillery` → `Game.enemy_missile` → `ProjectileManager.launch_enemy_rocket` (hostile homing, `rocket_of[proj] = shooter`, `_fly_rocket`, red trail), `Game.on_creature_died_index` → `kill_rockets_of`); the eruption rings call `Game.erupt_mound` (a sphere + crack ring tweened up over `warn`, then clods); the Nuke pickup (`effect: nuke`, `PickupDef.params {radius, knockback}` → `Game.nuke_blast`, `HUD.flash`); the magnet pulse is `vacuum_all(true, true)`; `ranged.lead` (the harpooner aims at hero position + velocity × flight); seekers with no blast fizzle on the ground and clouds need `area > 0.3` (the second-boss crash: zero-radius clouds logging thousands of warnings), antiparallel missile slerp yaws instead, chests queue behind an open reel (`_chest_queue`); `Turret` stances from `params.turret {style tower|bunker, barrels, turn}` and it uses `pierce`/`knockback`; Second Sting (`params.second_sting`: a killing seeker retargets once); `Chest` model at 0.9 in dark walnut (`blender_meta.CHEST_*`); the oasis has no collider and a 0.45 m dish (`RedCanyon.in_water`, `Game._tick_water` ripples); `dune_centipede` is `directions: 8` with `view_hints`; standing ranged creatures face the hero; `user://breadcrumb.txt` (a line a second, shown in Settings); `smoke_run.gd -- boss=2 evolve=all` jumps to the Gila with every weapon evolved. Pass 30: hostile shots carry `ranged.shot` ("pellet", "spike"; `Game._pellet_kind/_spike_kind`), a boss attack may set `straight: true` so its fan flies down the telegraphed lines; `brain: kamikaze` + `EnemyDef.kamikaze {radius, damage, knockback, windup, trigger}` (the Mine Crab: `_blow_up`, `blown[]` so the death burst does not double), and `Game.elite_explosion(center, r, damage, delay, knockback, friendly_frac = 0.2)` damages and throws the crowd too; the boss drops one `spawn_chest(at, true)` (Chest.boss: violet, 1.45 scale) whose roll is always a mutation (`Run.chest_roll(true)`, `chest_take` handles "mutation") and whose opening runs `vacuum_all(true, true)`; the rocketeer is `rocketeer` (max_alive 1) with a modelled `_rocket_mesh` that pulses via `psize`; power-up lifetimes doubled; the Big Mouth laser (`core/behaviors/LaserBeam.gd`: a Familiar mouth with a `Jaw` node, a 2 s beam drawn as two stretched boxes, ticks damage along the line, `params.beam {width, tick, arch_deg, color, width_mult, first_knock}`), evolution `loudmouth`, path `mouth_burn`/`mouth_knock`/`mouth_arch`, unlocked by 300 crab kills. Pass 31: `Game._spike_mesh` is built along -Z (a projectile's basis looks at its velocity) and hostile shots never spin, so thrown barbs hold their line; the Rocketeer has `outline_frac`/`outline_color` and a warm pulse in the artillery brain, with dancing clips; healing is a trickle (`Player.regen_hold` = 3 s after every hit, `Run.LIFESTEAL_CAP` 4% of max HP a second with a per-second tally, Mend 0.45/rank, Thirst 1.5%/rank, Vigour 8%/rank, heart 0.2, Astro level_heal 0.05, healing well 0.35); the oasis is a plain unshaded StandardMaterial3D at 55% alpha (the shader is gone); frames: `EnemyManager.SHADOW_BUDGET` 70 (only creatures near the hero cast one past that), `Fx._busy_skip` thins effects as the pool fills, `_drop_trail` halves beads past 60 live shots, and `_poison_slow` is read once a frame. Pass 32: the meta is the **Mirror** (`content/talents/<id>`, `TalentDef` with two `forms` and three ranks, `Save.talent_form/talent_rank/set_talent_form/buy_talent/talent_refund_all` in gold, folded in `Run._build_player_sheet`, the board is `ui/HomesteadScreen.gd`); the farm (buildings, market, resources, silver, stock, shop tiers, bones and relics) is gone and Elites and bosses pay gold instead; `content/structures/gold_bank` (`effect: bank`) banks the purse mid-run (`Run.banked_gold`); `Player.shove()` gates every creature knockback to one a second (`KNOCK_GRACE`) and caps the force, and the dwarf/Idol/scorpion carry `knockback` in their data; the ranged Elite is `sun_idol` (a caster with `spit_volley` shards, `erupt` with `pillar: true` -> `Game.light_pillar`, `slam_at`, `blink`) and the Dune Scorpion runs its own `boss.attacks` between charges (the attack runner now drives any Elite with a script); `Game.revive_blast` (`damage_radius` with `weapon_id "revive"` spares Elites and bosses at 10% max HP); `ProjectileManager.kill_rockets_of` sets `loose` so a rocket swirls to the nearest creature and `_explode_loose` throws the crowd; `CameraRig.zoom_per_level` widens the view with the hero's level (cap 2.6); `ui/DebugHand.gd` opens from a small button on the level-up screen and hands over any items at any level. Pass 33: the ranged Elite is `sun_prophet` (a long-necked lizard in a torn black toga with a sun staff, eight directions, blue screen; the Sun Idol is shelved in `tools/dl/backup/sun_idol`), same attack script; hostile shots hit on a flat distance with a height band (`ProjectileManager` hostile branch: the shards flew at 1.3 m and passed over a 3D sphere at the hero's feet); Berserk (`content/pickups/rage`, was Rage) adds the player stat `haste` (×2): `WeaponInstance.rebuild` divides every cooldown by it, `Run.haste` is cached for the behaviours' own clocks (Orbiter spin, Turret fire rate), `Game._tick_berserk` licks red flames round the hero; fire is `core/shaders/fire_billboard.gdshader` (Minionsart erosion + toon bands over `art/fx/fire_noise.png`), drawn as a third Fx pool (`Fx.flame`, `_emit_flame`, custom data = age, seed), and a fire `ElementCloud` is a see-through oil spill (`Telegraphs.draped_blob`, vertex-coloured) with tongues all over it; the Oil Slick is `params.drip {every, start, radius, slow}` (`ProjectileManager._drip` -> `Game.oil_drip`: a drop falls, a small slowing spill burns where it lands; `zone_line` is gone); `Chest` shines (`core/shaders/shine_aura.gdshader`: mode 0 sunburst, 1 beam, 2 ground pool, 3 sparkle); the Strongbox is `art/props/gold_bank.glb` (`blender_meta.py -- only=gold_bank`: Body, Lid, Balloon), `StructureManager` sways any `Balloon` node and `params.spent: "fly_away"` floats the box off when used; hostile rockets keep their path (`_paths`, `_draw_paths`: a faint ribbon back to the launch point, fading when the rocket is gone). Pass 33.1: the caster brain walks to `EnemyManager._screen_spot` (keep_distance up the camera's forward, at most `caster.side` across), starts no attack past `caster.attack_range`, and a blink with `"to": "screen"` repositions across the screen (the Prophet had parked 14 m to the side under the HUD strip and blinked further off every cycle); `application/config/quit_on_go_back=false`, the back gesture does nothing in a run (`Game._notification`, logged by `_log_pause` to `user://pauses.txt`, shown in Settings as "Recent system pauses"), ScreenBase goes back to the title and TitleScreen quits on it; `WeaponBehavior._stray`/`_fly_stray` flies any `Familiar` the active behaviour does not (Needle Rain's Lobber over the Poison Dart), and Lobber throws from it; the poison puddle is a muted `draped_blob` with faint puffs; the Strongbox is painted again (`st_gold_bank` in gen_props, `height 2.8`; every structure is 2.5D, the GLB shelved in tools/dl/backup/strongbox_3d). Pass 33.2: `sand_crab` and `jackalope` are out of the rotation (content kept; the Big Mouth unlock counts armadillos); goblins and fire ants come twice as many at half HP/damage/XP with `EnemyDef.cap_share` 0.5 (`EnemyManager.cap_load`, WaveDirector bursts in load units, the timeline's `hard_cap` 240 now enforced); `armadillo` (armoured pack creature from 2:30); the rocket flies at `artillery.missile.speed_of_hero` (0.9) of `Player.max_speed()`; every hero hit carries `info` {by, kind melee|ranged|boss, fx} (`EnemyManager.hit_info`, the shot params' `info`), logged in `Player.damage_log` (30 s) and shown by `ReviveScreen` (scroll, hold button, copy to clipboard); lines evolve (`LineDef.evolves_into/evolves_from`, a level-up card once maxed, `Run.evolve_line`), new lines `energy_shield` (player stats `shield_max/shield_delay/shield_rate`, `Player.shield_pts`, a blue `HealthBar3D.shield_style` bar; a hit on a holding shield never reaches HP) and `evade` (`evade`, `evade_invuln`), new stats `regen_delay` and `lifesteal_cap`; passives `beef_jerky`/`pickpocket` (`heal_drop`/`coin_drop`) drop the small pickups `jerky` and `coin_bag` (`params.small/quiet/magnet`, `effect: gold`); the Big Mouth is a painted two-frame sprite (`tools/gen_mouth.py` -> `big_mouth_sprite.png`) and a `laser_beam.gdshader` ribbon (the old boxes used `Basis.scaled`, world-axis scaling, so the beam missed the mouth unless aimed north); creatures get a dark-red rim and warm tint past 2x camera zoom (`enemy_billboard` `mark`, `CameraRig.zoom()`, `zoom_override` for captures); the fire pool is a faint orange again. Pass 33.3: badges float over creatures (`EnemyDef.badge` "crown"|"skull"|"gear"|"none", empty = its role's via `badge_for(modded)`: skull on a boss, crown on an Elite or any elite-modified creature; the harpooner and the rocketeer carry "gear"); `art/ui/badges/<badge>.png` from `tools/gen_badges.py`, one MultiMesh per badge in `EnemyManager` (`_badge_mm`, drawn in `_render` over the world by `core/shaders/badge.gdshader`, hung at `EnemyDef.head` = the figure's top as a fraction of the cell, measured by `tools/measure_heads.py`, warmed in `warm_draw`); `EnemyDef.retired` keeps a creature's content but leaves it out of the collection (goblin, goblin_runt, sand_crab, jackalope); `skeleton_warrior` and `skeleton_raider` took the goblins' roster rows, skin, swarm and the Tumbleweed King's ring, with bone sounds (`en_bone_hit/die`, gen_sfx `clatter`) and a collapse death (`"death": "collapse"` in the JSON: gen_art drops the standing painting apart in slices with `artkit.crumble`, then the painted heap; the heap's vision check skips "matches"); the rocketeer reloads when his rocket is gone (`artillery.reload`, `Game.rocket_out` -> `ProjectileManager.has_rocket_of`), and every hostile rocket goes off through `Game.rocket_blast` (the rocket's damage as before, `Player.blast(v, up)` past the shove cap unless `Player.last_outcome` is "evaded", `EnemyManager.throw_radius` flings the crowd unhurt, `Fx.explosion` never thinned by the budget, a scorch, a camera kick and a HUD flash; numbers in `artillery.missile` `knockback/lift/throw/throw_radius`); the HUD draws a chevron per off-screen target (`_arrows`, `_edge_arrow`): boss red, the boss's portal green, the Elite orange. Pass 33.4: `skeleton` (the goblin's slot) and `skeleton_knight` (breastplate and kettle helm, armour 1, the runt's slot) replace last pass's pair (shelved in tools/dl/backup/skeletons_333): no swords, arms out like the dead, walked on a Mixamo stride (creature JSON `"pose": "walk_zombie"` -> `gen_art` paints front and back with `pose_cycle`; `tools/pose_driver.py ... arms=zombie arm_drop=18` pins both arms forward with damped-track constraints, the back walk on `"pose": "walk_zombie_low"` (30 degrees down), the front on `"pose_front": "walk_zombie_high"` (12 up); standing/attack/hit/collapse frames come from the walk's `passing_frame`); `CharacterDef.hidden` (Buck, Dad, Mira) keeps a hero in the content but out of play (`Registry.sorted_characters`, `playable_character`, `quest_visible`); `EnemyDef.can_be_elite` (false on the spit cactus and the specials, `WaveDirector.elite_candidates`); the fire spill is black oil at 55% in the middle (`ElementCloud`); the rocketeer and the harpooner left the roster for the timeline's `specials` {from, interval, max_alive, pool[{enemy, stage}]} (`WaveDirector._tick_specials`, `specials_pool`, `specials_alive`: from 2:30 of stage 1, one at a time, the next 20-40 s after the last one dies, the harpooner from stage 2); the launcher icon is the Drifter's hat on the sand and his character icon a serious portrait, picked from four variants each (`tools/gen_icon_variants.py`, `--use hat=X drifter=Y`); the title's **Debug · Arena** (`Run.arena_next` -> `Game._start_arena`: god mode, the director held, `ui/ArenaPanel.gd` with a quick column (ARENA, AGAIN, CLEAR, WAVES, LV +1) and six tabs ENEMY/WAVES/ITEMS/HERO/DROPS/WORLD; `Run.debug_set_item`/`debug_clear_items`; the save is snapshot and restored by `Game.leave_arena`, no quests, no path offers). `WaveDirector._start_boss(id, where)` takes a spot. Pass 33.5: the goblins are back (goblin and goblin_runt in their roster rows, the 12:00 swarm, the King's ring and the map's walker skin, pass 33.2's numbers); `skeleton` and `skeleton_knight` carry `retired: true` (kept for later, still in the arena); the launcher icon is hat variant A (`gen_icon_variants.py --use hat=A`), the Drifter's icon stays B. Pass 33.6: `EnemyDef.badge_for()` gives the crown to the two Elites only (archetype elite; an elite modifier or a JSON `badge` never crowns an ordinary creature); `EnemyManager._update_boss` runs an Elite's attack script in STATE_ATTACK too (it ran only in STATE_MOVE, so the Scorpion's burrow never ended and it stayed `hidden`) and unburies any scripted creature outside its attack; the hero's bars left the world (HealthBar3D and its shader are gone: a quad hung 0.5 m off the rotating hero swung round him): `CameraRig.hero_anchor()` projects his feet through the shake-free `_rest_xf` and gives pixels per metre, and `HUD._tick_hero_bars/_draw_hero_bars` draw the 1.5 m health bar and the blue shield bar above it there. Pass 33.7: `CameraRig.zoom_amount` 0.7 scales the speed and level pull-out and the cap (widest view 2.12x, was 2.6x); the specials come 45-60 s apart; `weapon_cap` [4, 6, 6]; the harpooner has 70 HP. The launcher icon's hat is half size (the round mask cut it): `tools/dl/icon_variants/hat_A_half_icon.png`, the hat cut from icon A and pasted on a Flux repaint of the empty dunes (`hat_A_empty_541.png`). Pass 33.8 (late-game performance, nothing different to see): ground marks are instances of ready-made shapes in `Telegraphs` pools (`ring/line/sector/flash_ring/scorch`, owned marks `hold_blob/hold_disc/hold_puff` + `set_alpha/set_puff/release`), draped by `core/shaders/ground_mark.gdshader` from the map's height grid (`Telegraphs.set_ground(map)`; ring/disc/cone/line alpha is 1-(1-a)^2 because the old meshes had both windings); `ElementCloud` and `Zone` hold pool instances instead of meshes; EnemyManager's grid is flat arrays (`_g_head/_g_next`, `_gcol`), rebuilt every tick, half the crowd steers each tick (`(i & 1) == parity`), obstacles by cell (`_obst_cells`, `_obstacle_push`), per-type packed tables (`_t_*`, `_strip_of`, `strip_frames`); EnemyManager, ProjectileManager and PickupManager draw in `_process` once per new physics tick (`_ticks/_drawn`; the rocket lines' fading is `_tick_paths` in the tick); Orbiter blades are one MultiMesh; Fx lightning is two shared ImmediateMeshes; the wall posts are a MultiMesh; `MeshMerge.merge` joins a weapon model's (and an emblem's) plain parts that share a material (KEEP lists the names code moves). `tools/perf_late.gd` is the benchmark (7.8 -> 5.4 ms a frame at 60 fps on the PC, 12.7 -> 9 at 30, draw calls 310 -> 210). The oasis water draws at render_priority -10, under the marks (a red ring on the lake bed always reads). The harpooner has the rocketeer's HP (23). Bible section 15b "How the art is made" (2026-09-27): the kit (machines, a toolbox table of every model, LoRA and tool), the prompt anatomy, and step-card recipes for the Goblin, the Drifter, the Big Mouth icon and lips, the Tommy Gun and five shorter ones; its pictures (docs/design/img/ap_*.webp, two animated) are cut by tools/make_pipeline_figs.py from tools/dl/ intermediates and three arena captures in tools/dl/pipeline_caps/; recipe card styles are at the end of bible.css. The published bible is https://claude.ai/artifact/2onXrvqpGH3uqwPEstVYhr, with pose-animation.html (given a doctype and charset) as a supporting file. Pass 33.9 (the goblin and the runt redone): the goblin's front painting had four ears (and so did the runt's) and the vision QA passes that (both VL models count two), so stills are now painted as several seeds and picked by eye (the six fronts are `goblin_front_c0..c5` in tools/dl/ai_raw_anime; the prompt demands exactly two ears; `dead_hint` keeps the club in its hand); `tools/pose_driver.py body=top_nose:..,nose_neck:..,torso:..,thigh:..,shin:..,shoulder:..,hip:..,upper:..,fore:..,hand:..` (fractions of the figure's height read off the painting) retargets a Mixamo stride to a creature: bones scaled against the rig's rest pose, rebuilt from the hips out, the face points scaled with the head, the lowest ankle re-planted each frame; the goblin walks on `drivers/orc_walk_goblin` (Mixamo Orc Walk, 12 frames), the runt on `drivers/walk_runt` (Mixamo Walking; its `back_hint` keeps the dagger, which four backs in a row had dropped). Creature JSON: `"stand": "still"` keeps the painting for idle/attack/hit, `anim_negative` goes to the walk and fall clips, `"death": "clip"` (+ `death_frames`) makes the death a Wan 2.2 first-last-frame fall (`animate.wan_flf`/`fall_clip`: both paintings at one scale on one floor line, 33 frames; `gen_art.death_cycle` keeps 8 from the last near-standing frame to the first near-lying one, the dead painting last, die at 12 fps). `gen_art.hue_excess` scores a frame's colour that neither neighbour has: the fall swaps such a frame (over 0.06) for a neighbour and a pose cycle re-rolls over 0.08 (every hero run in the game is under 0.071). The bible's gameplay screenshots were retaken with the new goblins: the default `screenshot_run.gd` pass gives 60, and three flag runs give the rest (`character=buck weapon=tommy_gun` for 19/20/33, `weapon=rocket_pod` for 22/22b/35, `weapon=sabre` for 27); 30_dwarf kept its old picture (the retake missed the red wedge). Pass 33.10 (the harpoon is a leash): the rope is as long as the throw (`Game.tether_start`: `tether_len` = the gap at the hit; the fixed 4 m snapped the thrower to the hero), the thrower reels in slack (`_tick_tether`: `tether_len = max(min(len, gap), tether.min_length)`), `EnemyManager.tether_pull` returns how far it dragged (-1 when gone) and sets `tether_drag_t` (the wind-up strip while dragged, `_strip_of`), `Fx.drag_dust` every 80 ms while dragged; `Player.tethered/tether_from/tether_away` + `leash_factor`/static `leash_of` (towards free, straight away at `tether.away_speed` 0.7, a slant by its pull component); `max_speed()` ignores the rope; the holder's outline pulses red (`tether_glow()`: the glow level rides on the flip channel as flip + 2 x level 0..16; `enemy_billboard` decodes it for a wider bright-red rim and the painted outline turned red, `enemy_silhouette` decodes flip with `mod`); the hit: `hud.flash` red, a red burst, a `flash_ring`, a `HOOKED!` toast; the rope is two ribbons (dark band + red core nudged toward the camera, `_rope_strip`). Pass 34: **art variants** (an EnemyDef carries `variants` {code: {sprite, anims, fps, strip_cols, head, note}}, `variant` = the code the game plays, `variant_base` = the code of the top-level strip; `variant_def(code)` is a copy with that art, `type_key()` = id or id@code, EnemyManager keeps a type per key and `spawn(..., variant)` takes a code; the arena's ENEMY tab lists them as chips ("Art variants"); to adopt one, set `variant` in the JSON; an entry's `icon` becomes the creature's icon when it plays, applied in `JsonContent.build` after `_common`). `tools/lossy_imports.py` (run by ship.sh before the import) sets every content PNG import to lossy; `pass34_test` fails on a lossless one. `gen_art.py --only <id> --variant=CODE` paints a variant from `variants[CODE].recipe` (overrides: `stills` (a paintings prefix, e.g. c4 -> <id></id>_c4_front/back/dead in ai_raw_anime), `pose`, `gait`, `run_fps`, `death` ("clip" or "pose:<driver></driver>" = `gen_art.pose_death`, a Mixamo one-shot through Wan Animate), `stand`), clips under `<id>_<code>_*`, strip `<id>_sprite_<letter>.png`, record `<id>_<letter>_ai.json`. Variant paintings: scratchpad `vstills.py`-style (several seeds, picked by eye). New drivers: `walk_goblin`, `bigguy_goblin`, `death_back_goblin` (Mixamo Falling Back Death, `tools/dl/mixamo/falling_back_death.fbx`), `run_runt`, `death_back_runt`. `gen_art.hue_foreign` (share of hues the painting lacks, `FOREIGN_MAX` 0.025; good clips <= 0.016) re-rolls pose cycles and swaps fall frames, beside `hue_excess`; `pose_cycle` retries fresh seeds when a clip keeps leaving the frame. **Fire ant** (4 variants, `tools/gen_ant.py --variant=ANT-X [--use-side=kN] [--stage=paint]`): `tools/blender_ant.py` builds a primitive ant and walks it on the tripod gait in the five views (depth videos `ctl_NN.png` + a `clay.png`), Flux paints the side view from the clay (4 candidates, pick by eye), then the other views from the side painting + their clay, and Wan 2.2 **Fun Control** 14B (`animate.wan_fun_control`/`cycle_control`, models `wan2.2_fun_control_{high,low}_noise_14B_fp8_scaled` + the t2v lightx2v LoRAs) walks each view along its depth video; eight-direction strip. Hidden content: `ContentDef.hidden` on any kind (was CharacterDef only); `Registry.is_hidden(def)` (hidden, retired, or brought only by hidden things: evolutions of hidden weapons, their mutations, perks of hidden heroes); `unlocked_weapons/passives`, `mutations_of`, `perks_of`, `sorted_lines` skip hidden; quests for hidden things are not shown. Hidden: branding_iron, flare_gun, poison_dart, rattlesnake, sand_lizard (its roster row went to runts/ants/armadillos, its 11:30 swarm is 22 runts, the map's `runner` skin is the runt). The Collection lists hidden items in their own part at the end (`_split`). Lines: the map's `line_cap` [3, 4, 4] (`WaveTimeline.line_cap_at`, `Run.line_cap()`). Quickdraw: +15% projectile speed a level only. Wide Orbit: `params.breathe {min 0.9, max 1.6, period 2.8}` (Orbiter scales the ring) and `side_knock {force 7, every 1.0}` (a hit shoves along the blade's tangent once a second per creature; other hits no knockback; the pull is gone). Perks (Astro: `supply_drop` = a pod every 40 s (ring, blast, power-up), `thruster_burst` = 6+ creatures within 2.6 m fire her clear towards the emptiest ground and throw the ring (8 s); Drifter: `high_noon` = every 30 s the creatures' clock (`EnemyManager.time_scale`, hostile shots too) runs at 0.3 for 3 s, `bounty_hunter` = every 60 kills a nearby creature is WANTED (x4 HP, glows; 40 gold + a chest)); Game `_tick_supply/_tick_thrusters/_tick_high_noon/_count_bounty`. The Big Mouth is a 3D model (`tools/blender_mouth.py` -> `art/props/big_mouth.glb`, gold `loud_mouth.glb`; nodes Upper, Jaw, Cavity; visual scenes instance it as `Familiar/Mouth`, scale 0.62/0.8); LaserBeam opens the Jaw while the beam pours, chews between shots, faces the beam or the nearest creature, tipped back 32 degrees to the camera; the painted sprite stays as the fallback. The Results screen's second button is The Mirror (it went to the old Shop stub). The Stranger's offer card uses `UiKit.item_header` (it showed no name). `tools/ui_shots.gd` captures pause options, the stage-clear dialog, results after 30 s of play, the collection's hidden part and the bottoms of the Mirror and Settings; `tools/make_ui_review.py --shots= --extra=` writes the UI review pack for Claude Design (`docs/ui_review/`: brief, a document per screen, screenshots, ALL_IN_ONE.md, a zip). Pass 35: the art picks are GOB-D, RUN-D and ANT-A (a recipe's `"directions": 2` makes `gen_ant.py` walk and pack only the front and back, like every creature; ANT-A's eight-way strip is gone). The Sabre slices (`params.thrust.slice_deg/slice/side`: Thruster's slice mode swings one blade across the target through the arc, `amount` swings alternating, `_cut` hits each creature once a swing, knockback = away from the hero + along the swing; a crescent trail), the Zweihander too. Three new weapons, each with element/volume/motion paths and an evolution: the **Hammer** (`core/behaviors/Smasher.gd`: `WeaponBehavior.crowd_spots(n, reach, r)` picks a crowd per hammer; the visual's `Hammer` GLB (a `Handle` stretched down -Z to the reach, a `Head` sized with the blast) rears overhead and swoops down; `_impact` damages and throws outwards; `smash.aftershock`, `smash.quake` = the Earthshaker's fissures; paths Molten Hammer, Hammer Rain, Aftershock), the **Revolver** (ProjectileEmitter; `WeaponDef.hero` "drifter" keeps it out of every other hero's offers via `Registry.unlocked_weapons()` -> `hero_may_use`; burst with `burst_gap`/`scatter_deg`, the cylinder `Drum` turned about the barrel (`drum_axis` "forward", `drum_step`), `no_shells` (it stands upright like the Tommy Gun: a `familiar.roll` that laid it on its side read as sideways, pass 35b); the Golden Revolver's `params.trace` -> `core/systems/EnergyTraces.gd` (ProjectileManager.traces: start/follow/seal; lines of energy that hurt what walks in, `frac` of the shot every `tick`); paths Venom Rounds, Six-Shooter, Trick Shot) and the **Gravity Gun** (`core/behaviors/GravityGun.gd`; `EnemyManager.held[]` with `grabbable/grab/place_held/release`: a held creature is out of the grid, never damaged, never steers; lift, hold, throw on an arc, `_land` = blast + the creature's own fall damage (`self_frac`); the landing spot is picked as the throw leaves by `_lead_target` (every creature moved on by its `vel` for the flight, the spot catching the most, ties to the front of the pack: 9.5 of twelve caught against 5.4 when it was fixed at the grab, pass 35b; `blasts`/`blast_hits` count it); never a boss, an Elite, an elite-modded creature or `EnemyDef.can_be_grabbed` false (the rocketeer, the harpooner); the GLB's `Spin`, `ClawA..C` and `Core` animate open while it holds; the beam uses `Fx.tint_ribbon_material()`; `gravity.bounce` = Slingshot; paths Toxic Toss, Juggler, Slingshot; the Singularity is the same behaviour with `gravity.black_hole`: it lobs a shot whose `vortex` params make `ProjectileManager._explode` call `Game.spawn_vortex` (`core/systems/Vortex.gd`: `EnemyManager.drag_radius`, damage ticks, a pop; `core/shaders/black_hole.gdshader`, `swirl.gdshader`)). Models: `tools/blender_hammer.py`, `blender_revolver.py` (from Garry's `tools/dl/revolver_ref/`; it builds fresh Principled materials because the reference's active output is a plain Diffuse node and exported white), `blender_gravity_gun.py`; metallic kept at 0.3-0.5 (a mirror finish shows the desert sky and reads white from the camera); the values are linear, so the game shows them lighter. Swept trails share `Fx.glow_ribbon_material()` (additive), warmed in Warmup. Companion guns aim every round from where they circle (`ProjectileEmitter._from_familiar`; the Revolver's tight rounds went a metre wide, the Tommy Gun hits more too). The **Teleport** (`content/structures/teleport`, effect `teleport`, interact 1.5 s = half the Uber Magnet's; `Game.teleport_hero`: the thinnest crowd of forty spots at least 60% of the arena radius away, clear of rocks and the lake, a flash at both ends, `camera.snap_to`, 1.2 s invuln, the harpoon rope dropped; painted `st_teleport(_off).png` in gen_props, a `swirl.gdshader` billboard portal in the ring's hole at `params.portal {x, y, r}` (measured off the painting), faster and brighter as it charges, sparks from `Fx.mote`; the map's structure count is 9). The Peashooter's icon is peas. Icons are several Klein seeds each, picked by eye (the weapons' painted from their Blender side renders); new sounds w_hammer_swing/hit, w_revolver_fire, w_grav_grab/throw/land, w_blackhole, st_teleport. Captures: `_p35_shot.gd`-style arena scripts hide `arena_panel` for clean frames. Pass 36: the one-element rule is gone (`Run.held_element`/`element_allowed` removed; cards, paths, the Stranger and the boss chest offer both elements; a fire bomb still looks for the unburnt, a poison one for the unpoisoned). Bombs spread: `ProjectileManager.lob` keeps each bomb's `target` in its `extra`, `claimed_spots()` lists the in-flight bomb targets (not bomblets, not creatures' lobs) plus `_landed` spots for `LANDED_CLAIM` 2 s (a black hole for its seconds); `EnemyManager.densest_point(from, range, avoid, keep_away, keep_r)` skips creatures near those spots; the Lobber picks a crowd per bomb (away from claimed spots and its own volley), falls back to the thickest crowd when every crowd is taken, and scatters leftover bombs round the crowds found; the Singularity's `_fire_hole` avoids claimed spots too. Measured with three bomb weapons against four packs: pairs of bombs within 2 m of each other 47% -> 24%. Pass 37 (touch): project.godot keeps `emulate_mouse_from_touch=false` (since day one; Buttons handle raw touch, TapCard too), but Godot's Slider only listens to the mouse, so the volume sliders were dead on the phone: `ui/TouchSlider.gd` (UiKit.slider returns it, 84 px tall) reads ScreenTouch/ScreenDrag; the first 10 px decide (sideways takes the knob and `holds` the finger, up or down gives it to the page, a tap puts the knob there). The six hand-scroll copies (ScreenBase, PauseScreen, HomesteadScreen, DebugHand, ArenaPanel, ReviveScreen) are one `ui/TouchScroll.gd` (`input(event)`/`process()`/`reset()`, `only_inside`, `decay`): past 22 px it sends NOTIFICATION_SCROLL_BEGIN down the list, which takes the tap back from the Button or TapCard the finger landed on (a swipe down the Mirror had pressed its buttons), and it leaves a finger a TouchSlider holds alone. `tools/touch_audit.gd` pushes real finger events (`root.push_input(ev, true)`, canvas coordinates, any window size) through every screen and overlay (title, play setup, settings, collection, Mirror, HUD pause, the three pause tabs, level-up cards, debug hand, resume gate, chest, portal, Stranger, shop, revive, results, arena panel and its six tabs), unplugging each control's handlers while it taps it: buttons and cards must fire, sliders slide and take a tap, a vertical swipe on a slider scrolls the page, lists scroll, a swipe that starts on a button in a list must not press it. ship.sh runs it after the arena check (about 75 s headless); 713 of 713 controls answer. Pass 38 (Claude Design): `tools/make_ui_review.py` writes a from-zero **redesign brief** (Garry: Claude Design is to critique today's UI against the genre and propose its own look, never follow ours): the ask (start from zero on the look, critique, compare with Vampire Survivors, Survivor.io, Archero 2, Megabonk, Brotato, 20 Minutes Till Dawn, HoloCure, then three visual directions and every screen and piece in the chosen one), the game in one minute, the pieces, a glossary, 'Must still do (how is open)' per screen, today's UI for reference only; two art pages (`art_items.jpg`, `art_more.jpg`: every non-hidden icon, hero, creature and badge from the content folders) and the icons one by one under `art/` in the zip. The PDF (`docs/ui_review/88fits_ui_review.pdf`, headless Edge from `print.html`, plain document styling so nothing reads as the game's look) goes to the Drive builds folder with the zip. Anything wider than the A4 page makes Edge shrink every page to fit (the cover's three screenshots had printed the whole pack at about 70%): keep print elements in mm. The UI kit is also a Design System artifact, **88fits** (https://claude.ai/artifact/Q4YWdeUot9W4jyKhJ5XB3x: UiKit tokens, the two fonts, 15 static component previews, 149 uploaded images); it records today's UI and is not attached for the redesign. Pass 39 (2026-09-30, the **Wanted** UI; Claude Design's handoff is `design_handoff_88fits_wanted/`: README spec, `screens/*.png` at 1080x1920, `design/88fits Wanted.dc.html` for values): every screen rebuilt on the `ui/wanted/` kit, paper/ink/brass, Alfa Slab One + Bitter (+ JetBrains Mono for the developer menu) in `ui/fonts/` with their OFL files; kind = plate colour + one word, rarity = the wax seal only, level = stars /8 and /5, notches /3 or rivets /3 (drawn: no font has a star). `WText` lays text out in CSS line boxes: `W.normal_height` is Chrome's "normal" (ascent and descent each rounded); Godot's `Font.get_height` rounds both up and runs a pixel taller. Godot containers reset a child's rotation and scale on every sort: a turned chevron or seal inside one sits in a plain holder or is turned again in `sort_children`. `WSlider` lays out at 36 px and its 90x80 thumb hangs over the row (`_has_point` takes a finger anywhere on it). `WModal`s join the group `wanted_modal` and the HUD hides while one is up (the resume gate keeps it). Play setup is on the title (swipe or arrows over the hero, dots, a plaque with the trait's numbers and the favourite's plate, PLAY, the map's best); `ui/PlaySetup.*` is gone. Debug moved to `ui/DevMenu.gd/.tscn` (hold the Settings version line 2 s): arena, `Settings.debug_panel`, `debug_modal_buttons`, `free_revive_button`, `hit_log`, the breadcrumb and pause logs, hidden items (`CollectionScreen.hidden_only`), the save path. Collection: five tabs, tiles, an item page (levels, paths, evolution). Mirror: a board and a talent sheet under a sepia dim, the mirror drawn with the next hero in sepia (`ui/wanted/sepia.gdshader`). Placeholders are striped slots that `art/ui/wanted/<slot>.png` fills: `hero_<id>` 520x700, `stranger` 840x660, `strongbox`/`portal` 180, `mirror`; `menu_backdrop.jpg` is an arena still behind every menu. First-play hints use the HUD toast slot ("Drag anywhere to walk", "<He/She> shoots by <himself/herself>" from the new `CharacterDef.pronoun`, "The purple is XP"). TextGen now writes the missile pod and the laser mouth (Hornet Nest and Big Mouth read only their names before). `docs/ui_wanted_plan.md` is the build plan and `docs/ui_wanted_checklist.md` lists what still differs from each PNG and why (mostly data: rarities, prices, generated lines). touch_audit knows `WTap` and `WSwitch`, the title swipe, the version hold, the item page and the talent sheet: 695 of 695 answer at 1080x1920 and at 540x1202. Version 0.28 (`application/config/version`). Pass 40: the Collection's creature page read `EnemyDef.doc`, which did not exist (the enemy JSONs carried it for the bible only): the script error broke the page on the phone; `doc` is now an EnemyDef field read by JsonContent. The Mirror shows no hero (the talents hold for every hero): two brass eyes in the dark glass. Evolved weapons and lines share one look, a dark plate in a brass ring (`W.EVOLVED_FILL/EVOLVED_RING`, `W.is_evolved`, `WPlate.base_ring`); ember sat too close to brass. HUD slots: one row while it fits at 85 %, else weapons on a row and passives + lines on a second (`_row_width`); the pause strip follows the slots (`HUD.band_h`, read by PlayerInput's thumb zone); `wanted_shots.gd only=hud_full` is the 16-item check. Title heroes are painted (`tools/gen_title_heroes.py`: Klein from each hero's front still, four seeds, a review sheet, `--pick id=n` -> `art/ui/wanted/hero_<id>.png`; picked by eye: astro 1, drifter 2, dad 2, buck 1, mira 1); `tools/lossy_imports.py` now also covers `art/ui/wanted` (the backdrop was 1.1 MB lossless). Locked heroes (not hidden, not unlocked) ride the carousel after the open ones: `ui/wanted/silhouette.gdshader` (`WPlaceholder.silhouette`), a drawn padlock, the quest text and a bar from `QuestTracker.progress()`, PLAY reads LOCKED; `Settings.preview_locked_heroes` (developer menu) adds the hidden heroes as locked. `WText.font`/`font_size` re-shape when set. touch_audit's `collection_pages` opens every item's page on every tab and fails one that does not build (its taps are muted, so it had never opened a page). The title plaque shows the hero's weapons as plates, no text (Garry: icons, not a sentence): the favourite (FAVOURITE) then each weapon only that hero can find (`WeaponDef.hero`, SPECIAL: the Drifter's Revolver, and Astro's Gravity Gun since this pass, `"hero": "astro"` in its JSON, so the Drifter no longer finds it); `TitleScreen._weapon_plate/_own_weapons`. The plaque grows upwards from `PLAQUE_GAP` above PLAY; a swipe removes the old plates at once (`remove_child`), because a plate that is only queued still counts and the plaque sized in that moment stayed 1157 px wide. Pass 41: the in-run top is compact (Garry: it took too much room): `HUD.TOP_Y` 30, plates in 36 px type, the clock 56, the disc 78, an 18 px XP rail, slots from `SLOT_Y` 126 at `WEAPON_PX` 88 / `OTHER_PX` 74 (were 44 px type from y 44, 104/88 px slots from y 170), `BAND_H` 236; everything under the slots follows `_slots_bottom`, and the banner fills the compact row (`WBanner` 36 px). The chest reel runs `ChestScreen.TAIL` 4 plates past the landing cell, so after it stops the strip still goes on off the screen's edge; a landed evolution keeps the evolved plate (the ember override is gone). Pass 42 (the last placeholder art): `tools/gen_ui_art.py` paints the Wanted UI's slots and the boss portal on Flux.2 dev at full steps (28, no Turbo LoRA; the models are released after every render, about six minutes each), four seeds each, picked by eye, `--pick slot=n` installs: `stranger`, `strongbox`, `portal` (edits of the world's hooded figure, Strongbox and the new gate, so they match), `mirror` (the Mirror's frame with the eyes; HomesteadScreen draws it when present) and `portal_gate` = `art/sprites/props/boss_portal.png` + `boss_portal.json` (the round opening measured off the painting). `core/systems/Portal.gd` is now that sandstone moon gate as a BillboardSprite rising out of the sand, with the Teleport's swirl shader in green in its opening and no point light; the torus is only the fallback without the painting. `tools/lossy_imports.py` covers the new PNGs. Pass 43 (2026-10-01, Garry's list): the UI keeps clear of a camera cutout (`W.safe_top()`: the display's safe area in canvas px, or `Settings.top_inset` from the developer menu; the HUD strip, every modal header, the menu headers, the pause screen, the cards, the title and the debug hand sit that much lower); the volumes are five stops (`WSlider.make_levels`, notches on the track, the thumb naming the stop) in the pause Options and in Settings; eight-direction creatures keep their view until the heading is `VIEW_HYST` (12.6 degrees) past the boundary and the picture mirrors only past a `FLIP_BAND` dead band about the vertical (the Bull Beetle flicked between two sets every tick heading up-and-left); no rarity seals anywhere (WItem passes no rarity, the Collection's tiles and page, the chest reel); the stage-clear cards' art is painted as item icons (scratchpad `card_art43.py`, gen_art's ICON_STYLE, picked by eye) instead of edits of the scenery; the Gila's fan is a `rumble` attack (`EnemyManager._rumbles/_tick_rumbles`: a wave of sand runs down each telegraphed line at `speed`, hits the hero once per line within `width` and throws him along it with `lift`; `game.rumble_mark`); the Continue card says nothing about ×1.0 gold and Extract pays the run's gold as it is (the ×1.25 is gone from `Game.end_run`). **Stage 3** is hell: `stage_mults` [1, 2.2, 3.34] (2^0.6 over stage 2) and the **hell channel** (roster rows with `"channel": "hell"` spawn against `hell_cap` [0, 0.3, 0.4] of the regular cap with their own weighted draw, `WaveDirector._burst_from/_hell_load`, so the regular roster's mix and count never change: the count side of the doubling, 2^0.4); the ground goes a shade redder (`terrain_painted.gdshader` `hell` uniform, `RedCanyon.set_hell` tweens it with the ambient and fog light on `stage_started`, `MapBase.set_hell` no-op); the boss is **The Brander** (`content/bosses/brander`: `boss.ring` {radius 21, min_radius 8, shrink 42, hold 8, burn 0.07, creature_burn 0.12} runs `Game._tick_hell`'s ring of fire from `_on_boss_started`, a held draped ring (`Telegraphs.hold_ring/move_held`) with flames along it, whoever stands outside burns every half second, hero and crowd; its `brand` attack calls `Game.hell_line` (a burning strip on the sand for `life` seconds that ticks the hero and the crowd on it); `roll`, `slam`, `spawn_ring` of imps); endless needs no unlock (the `unlock_endless` quest is gone): the last portal offers Extract or **Stay**, every wave (`endless_wave_seconds` 60) multiplies by `endless_wave_mult` 1.12 compounding (`WaveTimeline.stage_mult/endless_wave`, `Run.endless_seconds/endless_wave`, a WAVE toast), and the endless bosses cycle through the timeline's boss events (`_endless_boss_id`); two items only stage 3 offers (`ContentDef.from_stage`, `CardPool.stage_open`, the Collection says "Stage 3 only"): `brimstone_brand` (player stat `brand_chance`: a kill sets a burning `Zone` with `flames` under the body, `Game._on_enemy_died`) and `sinners_greed` (greed and XP). Four creatures, all painted (`stills43.py`-style candidates picked by eye, then `gen_art.py`): `hobgoblin` (stage 2's hell row, `bigguy_goblin` walk), `imp` and `hellhound` (stage 3's), `hammer_giant` (from 7:00, `max_alive` 3, `cap_share` 2.5, `boss.attacks` with a `slam` gated by `reach` and thrown with `lift` through `player.blast`; the attack runner now drives any creature with a script, not only Elites; `drops.pickup` {id rage, chance 0.3} and `chest` 0.22). **Damage reduction** replaces armour everywhere (`damage_reduction`, a share of every hit: `Player.take_damage` caps it at 80%, `EnemyManager.dr[]`, `EnemyDef.damage_reduction`, the Shielded Elite adds 0.4, Grit's Plate 6% a rank, the lines 5-15%, Astro 5%; TextGen shows it as a percent, the title plaque calls it DEFENCE). **Calavera** (`content/characters/calavera`, the mariachi with the sugar-skull face; trait Last Dance +25% might, +15% crit, −15% max HP; favourite Skull Rain at level 2; his weapon the **Guitarra** (`hero: calavera`, a ProjectileEmitter fan of three notes with a companion guitar from `tools/blender_guitar.py` -> `art/props/guitarra.glb`/`requiem.glb`; paths `ember_chord`/`power_chord`/`tremolo`, evolution `requiem`, hero path `danza_macabra` on the Skull Rain; sound `w_guitarra_strum`); perks `crescendo` (`Run.crescendo` stacks per kill, `crescendo_might`, reset on a hit, on the HUD beside adrenaline), `serenade` (`Game._tick_serenade`: `slow_radius` every 0.3 s under a held gold disc) and `grand_finale` (a boss or Elite dying takes `frac` off every creature within `radius` and throws them)). `tools/hell_check.gd` is the headless Stage 3 check (the hell crowd, the tint, the rumble, the giant's wind-up, the ring, the lines, endless waves). `docs/analytics_plan.html` is the analytics plan (PostHog through a Godot autoload, the event catalogue, six dashboards), published as an artifact. Version 0.29. Pass 44 (2026-10-01, Garry's second list): a death leaves the run's gold in the sand (`Game.end_run`: only an extraction banks it; a Strongbox's banking stays; the Results screen says "Left in the sand", struck through, and names what the Strongbox banked; Down! warns under the count); **The Mirror is called Upgrade** everywhere (`HomesteadScreen` title, the title's button in brass with a breathing glow and a mark when a rank is affordable, the Results' Upgrade and Main Menu buttons, the card screens' lines; the file names stay), and "Take it all back" returns half (`Save.REFUND_FRAC`, `Save.talent_refund()`); the Collection shows only what has been met (`Save.seen(kind, id)` / `mark_seen`, marked by `Run.add_weapon`, `add_or_level_passive`, `add_or_rank_line`, `add_perk`, `evolve`, `evolve_line` and `EnemyManager.spawn`; an old save migrates what its kill totals prove, `Save._migrate_seen`); **half the items sit behind unlock quests** (23 of the 45 base weapons, passives and lines: 16 doable on stage 1, 6 on stage 2, 1 on stage 3, by `QuestTracker.stage_hint`, which reads the timeline's first arrival of a creature, a boss's stage or minutes survived; new condition types `kills_total`, `runs_total`, `pickups_total` (Game.apply_pickup counts power-ups), `gold_total` (Run.add_gold counts gold earned) and `reach_stage`; `Registry.unlocked_by(q)`; lines are filtered in `CardPool.open_lines()`, `Registry.sorted_lines()` stays the content listing; a locked tile shows the quest's words and a progress bar and opens `CollectionScreen._open_locked` with the quest, its bar, the stage that can do it and what the item does; the in-run UNLOCKED banner carries the item's icon); the player's own **debug mode** (`Settings.debug_mode`: ten taps on the first-play hints switch in one Settings visit flip it, ten more on a later visit flip it back; on: ARENA on the title, the debug hand on the pick screens, "hold time" and "respawn" on Down!; the developer menu lists it too); **reveals** on level-up and the chest's landing (`ui/wanted/WCelebrate.gd`: a wanted-poster sunburst behind the title or the landed plate, paper scraps and brass stars falling, a dust ring; `WModalHeader.stamp()` slams the title in; sounds `ui_fanfare`, `ui_jackpot`); **barrels** (`core/systems/BarrelField.gd`: 44 of `art/props/barrel.glb` from `tools/blender_barrel.py`, dark common and light rarer with three times the gems, placed by `Run.map_seed` clear of the flats, rocks, water, structures and every painting's cover band north of its foot (height / tan 46°), at least 6.5 m apart; the hero walking up bursts one into `Fx.splinters`, dust, gems scaled by the level, `st_barrel_break` and a camera kick; `smoke_run` counts them); **dust gusts** (`world/features/DustGust.gd`: a MultiMesh of flat streak quads sweeping past the hero along the wind every 9-16 s with sand puffs and `wd_gust`, visual only); tumbleweeds hidden (`RedCanyon.tumbleweeds` 0, the feature kept); the prickly pear gone (props.json, gen_props, the scatter tables); **Blue Slime** (`content/enemies/blue_slime`, the hobgoblin's stage-2 hell row; the hobgoblin is `retired`; sounds `en_slime_hit/die`); **Cheese** (`content/passives/cheese` + pickup `cheese_bite`, Beef Jerky and `jerky` are gone); the skeleton and the knight carry four art variants each (`variants` SK-A..D / KN-A..D with `recipe` overrides of `art_prompt`, `pose`, `gait`, `death`, `outline_frac`, `outline_color`: A arms down on `walk`, B a poncho or cape and a small knife on `run12`, C a chunky fused-rib cartoon skeleton on a free clip with a lighter outline, D a swagger on `bigguy` with a hatchet or a shield; both creatures stay `retired`; a variant recipe that wants the free clip must clear the base creature's `pose`/`pose_front` keys, since `d.update(recipe)` inherits them, and `anim_seed` in a creature's JSON or recipe rolls the clips again with the paintings cached); pose drivers `run12`, `bigguy`, `death_back` (human proportions) and `run_occ` (`tools/pose_occlude.py`: the back and three-quarter-back views drop a wrist that falls inside the torso, so Wan Animate no longer paints the hand on the jacket's back; hero JSON `pose_drivers` picks a driver per view, Calavera uses it for back and bd); Calavera's title painting is solemn with a guitar (`gen_title_heroes.py` `HOLDS`); the **Tommy Gun** is Garry's model (`_REFERENCES/3d/tommy_gun/source/tommyGunvs2.obj` imported by `tools/blender_tommy.py`, flat colours by material group, the drum a wheel across the barrel as its own `Drum` node, 850 mm, muzzle +Y) and its icons are painted from a three-quarter render of it (`gen_tommy_icon.py --seeds=4` / `--pick`); the launcher icon is the hat zoomed in a fifth (`tools/dl/app_icon/icon_src_full.png` is the uncropped painting); `_REFERENCES/` (git-ignored, with a README) holds every reference Garry shared; `docs/analytics_plan.html` gained the step-by-step PostHog setup and a pulse board of right-now numbers, `docs/marketing_plan.html` is the CPI test plan (pink); `wanted_shots.gd` states `16b-results-down`, `04d-collection-locked-page`, `04e-collection-locked-tiles`; tests `pass44_test.gd`. Version 0.30.

Pass 45 (2026-10-02, Garry's third list). **Pacing**: the live cap is a curve, `WaveTimeline.cap_curve` ([[seconds, cap], ...], linear between points, flat outside, `_curve_at`; it replaces cap_start/cap_per_minute when set), Red Canyon's [[0,10],[60,16],[120,25],[180,38],[240,52],[300,66],[600,108],[900,150]] = 20 skeletons at 0:00 rising to pass 29's line from 5:00; the boss fight keeps `boss_cap_frac` of the cap (0.6 on Red Canyon, default 0.3); the portal wait runs on `portal_cap` for `portal_spawn_seconds` (`WaveDirector._portal_t`; -1 / -1 on Red Canyon = the stage-end cap for as long as the hero stays out, Megabonk-style); `_spawn_burst` reads the roster at `elapsed - 1.0` outside NORMAL. **The skeletons replace the goblins** (skeleton SK-A and skeleton_knight KN-A in the roster rows and skins, `cap_share` 0.5, pack 5, the knight 7.2 HP = 1.2x, weights 10:4 = about 2.45 skeletons per knight; goblin and goblin_runt are `retired`; quests unlock_tumbleweed / unlock_sabre count skeletons / knights). **Bosses**: a scripted roll runs one clock (`_steer` leaves a boss-brain charge to `_update_attacks`, both read `_scripted_speed`; it ended at half its `duration`), "line" telegraphs are as long as the attack, `Game.hell_line(..., owner_i)` and `_tick_hell` skip the owner and any boss (the Brander burned on his own lines); bosses x1.6 HP (1440 / 2400 / 5440); the King's `tumbleweed_volley` on a `spokes` telegraph (`Game.tumbleweed_volley`, `_tumble_kind` from art/props/tumbleweed.glb; hostile shot params `hit_radius`, `roll`, `lift`, a "tumbleweed" dust trail) and a ring of `tumbleweed_minion`s (goblin numbers, speed 2.0, painted, hops); enemy JSON `front_faces` / `back_faces` ("left" inverts the two-way mirror: the hellhound); specials 50 HP, the harpooner's armour gone; the hammer giant drops a chest at 0.08 and Berserk at 0.12. **Stone Golem** (`content/enemies/stone_golem`, the third Elite in every `elite_boss` list, 520 HP, speed 0.9): `max_range` skips an attack while the hero is beyond it (`_attack_out_of_range`; `reach` waits instead), a `sector` telegraph, `swoop` (`_stalactites` / `_tick_stalactites`: stalactites over a 180-degree half-disc the dwarf's wedge wide, one hit and a throw, the crowd thrown, `Game.stalactite/stalactite_hit`), `boulder` (`Game.throw_boulder` -> `core/systems/Boulder.gd` on a high arc with a growing shadow -> `Game.boulder_land`: damage and a throw for hero and crowd, stone splinters), `throw_radius(..., except_i)` spares the thrower; sounds en_golem_* / en_boulder_land / en_stalactite_hit. **The loose rocket**: a rocketeer's rocket whose thrower dies goes loose in three phases (`ProjectileManager._fly_loose`): a 0.7 s blink (it slows, swells and flashes red and white, a "ROCKET LOOSE!" toast, `en_rocket_loose`), a 1 s wild corkscrew climb under `LOOSE_CEILING` 9 m (`en_rocket_wild`) and a dive on `EnemyManager.densest_point` (`_lock_dive`, `_dive_aim`, `en_rocket_dive`), a red ring on the sand under that crowd from the first blink (`_tick_loose_mark` -> Game `loose_mark/loose_mark_move/loose_mark_end`); it goes off through `Game.loose_rocket_blast` (the crowd thrown, never the hero), and one that runs out of life no longer goes through `rocket_blast`; the heat reaches the mesh as MultiMesh custom data (`register_kind(..., custom)`, `glow[]`, `core/shaders/rocket.gdshader`). **Run flow**: the hero mutation is the weapon's stage pick (`Run.add_mutation` stamps `mutation_stage` for every kind, `open_mutations` lists the hero option only while the pick is open); the boss chest's reel shows only the paths it can land on (`Run.boss_chest_mutations`, `ChestScreen._fill_strip`); **no starter pick**: every hero lands with `CharacterDef.start_weapon` (astro gravity_gun, drifter revolver, calavera guitarra; `Registry.start_weapon_for`) down a 3 s **spawn beam** (`Game._spawn_begin/_tick_spawn/_spawn_land_now`, `Chest.shine_quad`, `Player.cinematic`, a camera anchor with `zoom_override`, Warmup under the beam, a tap after 1 s skips; the launch-file key `"spawn": true` opts a tool in, so tools keep the instant start). **Saves**: atomic `save.json.tmp` -> `.bak` -> rename, corrupt files kept aside as `save.json.corrupt-<unix>`, `Save.VERSION` 2 migrates forward only, typed merge, debounced writes flushed on background/quit, the arena is `Save.begin_sandbox/end_sandbox`, Settings shows "saved N min ago", the gdUnit runner writes under `user://test_saves`, the export keeps data on uninstall and allows backup, ship.sh refuses a debug-keystore build without `--debug-key`. **UI**: `ui/wanted/WConfirm.gd` asks before every irreversible deed (pause Abandon, Settings Wipe, Upgrade's Take it all back, Down!'s STAY DOWN, the arena's Leave; ScreenBase routes back/Esc to it; touch_audit `_confirm_audit`); the Upgrade glow is one feathered halo behind the button and the "!" mark (`_mark`) over it; the FULL talent sheet reads summed ranks (`TalentDef.summed_effects`) and wraps; the HUD banner pops in place at `HUD.BANNER_FRAC` 0.38 of the height; trait debuffs on the title plaque are `W.BAD_DARK`; stat names "attack damage", "area of effect", "coin gain" (`TextGen.STATS`; ids unchanged; the talent form "Greed" and the item "Sinner's Greed" keep their names); the Results screen's Last hits panel (`ResultsScreen.hits_visible()` = `Settings.debug_mode or hit_log`, `Run.last_result.hit_log/last_hit` from `Game.end_run`); barrels 33. **Analytics**: `core/systems/RunAnalytics.gd` (a Game child with static `I`, never in the arena) samples a row a second of unpaused play (estimated DPS per weapon from `WeaponInstance.dps_estimate()`, which now follows `behavior()`; real damage per weapon; damage taken per creature id via `hit_info`'s new `id`; kills, spawns, alive vs cap, crowd pressure = sum of max HP x damage; the player sheet when it changes) plus events (every pick with its route and est before/after, chests, skips, banishes, rerolls, structures, pickups, bosses, stages, portal, death, revive) and writes `user://analytics/runs/<stamp>.json`, mirrored on the PC into `analytics/runs/` with `latest.js` and `index.js` (git-ignored); `analytics/dashboard.html` (Chart.js vendored in analytics/lib) opens from file:// and charts power against pressure, health, the crowd against the cap, rates, progression, weapon share, estimate against real, creatures, the picks, survivability, power/pressure ratios and run history; `analytics/SCHEMA.md` and README; `smoke_run.gd` checks the run file (`-- perf=1 seconds=340` plays the first stage unaltered for dashboard data). **Art**: the Dune Scorpion repainted from Garry's reference (`_REFERENCES/2d/scorpion.png`, realistic, golden yellow, no face); the golem from `Stone_Golem.webp` in sandstone; the hammer giant with one handle; the peashooter icon a pod of four peas; Calavera's back and three-quarter-back runs on `run_spread` (`tools/pose_spread.py`: back-view wrists inside the torso are pushed out past it; the occlusion driver had still let Wan paint the hand on his back); KN-A / SK-A die as a first-last-frame fall onto a painting lying sideways (head left; a painting lying on its back seen from above read as a standing T-pose) and `artkit.transform` slides a frame pushed past the cell's top back in (`keep_top`: the knight's helmet was chopped); four Blue Slime options SL-A..D (`variant` SL-A) and the Tumbleweed Minion hop on their own painting (creature JSON `"walk": "hop"` -> `artkit.hop_cycle`, `cell_fill` for headroom, `hop_height`; the Wan clips moved the slimes' mouths, greyed them and grew the minion legs); `gen_art.pose_cycle` no longer re-checks (and re-rolls) a cycle already on disk; `animate.cycle(..., fill)` / JSON `clip_fill`. Tests `pass45_*_test.gd` (pacing, bosses, golem, rocket, runflow, ui, analytics) and `save_test.gd`. Version 0.31.

Pass 46 (2026-10-02, Garry's fourth list, 22 items). **Pace x0.7**: Red Canyon's clocks stretched by exactly 430/300 (`stage_length` 430, bosses 430/860/1290, Elites 215/645/1075, the cap curve, roster arrivals, specials 215 and [64, 86], `path_times`, `elite_every` 129, `endless_wave_seconds` 86, `hp_growth` 0.0977 so HP at a stretched time is unchanged) and `WaveTimeline.xp_need_mult` 2.0 multiplies `Run.xp_to_next` (kills are spawn-limited, so the stretch alone gave more XP a stage; calibrated with `smoke_run -- perf=1 seconds=470`: level 22 at the first boss after 7:10 against pass 45's 21 after 5:00); `colour_after_kills` 50 gates the variance tints/specials (`EnemyManager.vspecial`) and holds elite-modifier spawns (`WaveDirector.colour_open`); `creature_hp_mult` 1.3 (everything but bosses); the hit invulnerability is the player stat `hit_invuln` 0.5 and `contact_cap` 0.22 caps one touch at 22% of max HP (not bosses); WaveDirector's endless clocks follow `stage_length`. **Gems** hop away from the hero for 0.22 s, then accelerate in (`PickupManager.phase/phase_t/hop_dir`, `_start_trip`, `_travel`), collected at 0.45 m, XP only on arrival. **Damage numbers**: `ui/DamageNumbers.gd` (static `I`, `add(i, at, amount, crit, green, hot)` from `EnemyManager.damage`, merges per creature within 0.12 s, cap 60, gold crits, orange burns, green poison; `Settings.damage_numbers`). **Lines are passives**: the 16 line folders live in `content/passives` (`PassiveDef.trade/evolves_into/evolves_from/text`, `LineDef` and `Run.lines`/`line_cap` deleted), `passive_cap` [4, 5, 6] by stage (`Run.passive_cap()`, `MAX_PASSIVES` 6 is the strip), one CardPool rule set (a maxed passive offers its evolution at x3, `Run.evolve_passive` keeps the slot), Save VERSION 3 merges `seen.line`; the HUD lays out all 12 slots from the start (`HUD.slot_specs`, `WPlate.slot`: dashed empty plates, padlocks with the stage that opens them); the Collection has four tabs. **Desperado** (`desperado` stat, +12% a level of attack damage scaled by missing health, `Run.note_hp` buckets of 10%). **Cheese is Cake** (`passives/cake`, `pickups/cake_slice`). **Ironwood** (`content/characters/ironwood`, from `_REFERENCES/2d/indian.webp`): trait Enduring (regen +1.2, regen_delay -1.5, no max HP), `start_weapon` spear, `favourite_passive` cake with `favourite_passive_bonus {"type": "max"}` (`Run.add_or_level_passive` delivers it maxed from any route), perks `unbroken` (hits don't pause his regen) and `deep_breath` (below 35% regen x4 for 6 s, 40 s cooldown); his hero JSON's `remap_hues` (`artkit.remap_hues` in gen_art's hero clips) put the green/magenta keying streaks of his fringed legs back into buckskin. **The Spear** (hero ironwood; `art/props/spear.glb` from `tools/blender_spear.py`; `WeaponBehavior.projectile_source` draws a model as the shot; `ProjectileManager` `plant` (it stands in the sand at the end), `pin` (`slow` 1.0 for 1.2 s; `_steer` allows a full stop), `no_spin`, `trail_zone`; mutations fire_hardened / spear_volley (amount x3) / pinning_throw; evolution war_lance). **The Guitarra is a cone of melody**: `core/behaviors/ConeWave.gd` (`indices_in_cone`, `EnemyManager.bounce` = `lift_mode` 1: lifted and dropped on the spot, no damage from the bounce; `params.cone {deg, min_deg, lift, lift_time, knock, side_random, notes}`; amount = echo waves at 60%; the companion is Garry's cartoon guitar from `_REFERENCES/3d/cartoon-mexican-guitar.zip`, imported and decimated by `tools/blender_guitar.py` (Body, Strings, Soundhole), held upright, strummed on every wave; notes from `tools/gen_notes.py` -> `art/fx/notes.png`, `Fx.note`, `note_billboard.gdshader`; `Telegraphs.wash`); mutations ember_chord / far_reach / music_slap (power_chord and tremolo in tools/dl/backup/mutations46); the Requiem is a 360° wave. **Turret Buddy** is our own model after Garry's (CC-BY-NC) reference: `tools/blender_turret.py` -> `art/props/turret_buddy.glb` / `turret_family.glb` (Base/Tripod/Sandbags stands with *Top empties, Yaw, Gun, Barrel / BarrelL / BarrelR with Muzzles); `Turret.gd` aims, recoils, flashes, smokes, ejects shells and fires tracers, `ProjectileManager.fire(..., hover_max)` keeps tower shots high; Buddy Squad = amount x2, `max_turrets_mult` 2, -40% damage. **Big Mouth** (`LaserBeam.gd`): a 0.12 s clamp, the jaw to -80° with an overshoot, the lip and cavity glowing, a muzzle flash and sparks, and boiling sand where the beam runs under the ground (`boil_points`). **Hammer** (`Smasher.gd`): appear, wind-up and hold, swing, squash, bounce, recover; `smash.size` 1.4 (Earthshaker 1.5), `grip_up`; the strike re-aims as the wind-up ends. **UI**: `WCoin` draws `art/ui/wanted/coin.png` everywhere; brass means buy (paper price tags, an ink WChoice, the turquoise `WButton.UPGRADE` on the title and results); talents have six ranks (`TalentDef.max_rank`, `rank_effects`: Second Wind alternates +1 revive and +0.15 `revive_hp`); the chest opens before the reel (`ui/wanted/WChest.gd` with the painted `chest_*` / `boss_chest_*` frames, `ui_chest_knock`, a tap skips); the Collection says Mutations and lists heroes' own ones ("CALAVERA ONLY", `Registry.weapon_hero_mutations`), centred rows of three; the hit log is on Down! (`ReviveScreen` rows: badges skull/crown/gear/bow/heart, the creature's colour, a red X on the killing hit; `Player.heal(amount, source)` logs pickup heals; Results no longer shows it). **Art**: new variants SC-A..D (the Dune Scorpion walked on Garry's 3D model: `tools/blender_scorpion.py` -> `tools/dl/drivers/scorpion_walk` depth videos, `tools/gen_ctl.py` = gen_ant generalised: Flux.2 dev side candidates, Klein views, Wan Fun Control walks; its death is the model rolling onto its back, `mode=death` -> `drivers/scorpion_death`, walked by `animate.oneshot_control` with the recipe's `death_keep` frames (Wan smears the middle of the roll); each view is resized to its depth video's width, `gen_ctl.model_scale`, because Wan keeps the painting's scale; dev renders go through `comfy.run_dev`, a fresh server each; SC-B, the teal of Garry's 2D reference, in play), TM-A..D (red fez, smaller meaner faces; TM-C in play, TM-0 the old one), HG-A..D (skin colours, hammers clear of the back; HG-C in play); the slime plays SL-C with `front_faces: left` in its variant entry; title paintings of Ironwood (arms crossed, looking down) and Calavera (the cartoon guitar, looking aside); icons painted from the new models' renders through `tools/gen_icon_cands.py` (several seeds, `--pick`; green subjects on the blue screen). Tests `pass46_*_test.gd` (schema, pacing, passives, weapons, hero, ui). Version 0.32. The bible's section 08 is **Items** (Garry, 2026-10-02: one clean list): `make_bible.py` generates it from the content folders (`item_weapon_rows` = every weapon grouped open / hero / locked / hidden with its mutations and evolution under it, `item_line_rows`, `item_passive_rows`, `item_counts`; icons embedded as 64 px WebP; marks for hidden, a quest lock with its words and stage (`quest_text` / `quest_stage` mirror TextGen and QuestTracker), a hero's own, start and favourite weapons, stage gates), with the rules, elements, weapon notes and builds folded in `<details>` under it; the level-up cards and the offer moved to section 10, the hero perks to 13, the stats to 14, and 13's unlocks table is generated (`unlock_rows`); on a phone the item tables stack into cards (bible.css).

Pass 47 (2026-10-03, Garry's fifth list, 32 items). **Items are three kinds again** (Megabonk's weapons, tomes and items): **weapons** (6 slots), **lines** (6 slots, 4 levels, evolve when maxed; `PassiveDef.line` + `is_line()`, flagged `"line": true` in the JSON on the 15 lines and their 15 evolutions, all still in `content/passives`) and **passive items** (no cap, never on the HUD, `Run.held_lines()` / `held_passives()`, `Registry.sorted_lines()` / `sorted_passives_only()`); Multishot, Field Notes, Haste and Deadeye became lines (evolving into Barrage, Almanac, Quicksilver, Eagle Eye), new lines Ducktape (`debuff_duration`, EnemyManager.debuff_mult stretches burn, poison, slows, pins and marks; perks pass `scaled=false`), Clover (`luck`) and Hot Sauce (`difficulty`: variance specials x(1+d), coloured-Elite timers by `WaveDirector.elite_pace`, `EnemyManager._hot_sauce_pay` a gem of 0.25 x d of the creature's XP and a chest at most every 40 s), evolving into Shackles, Golden Horseshoe, Ghost Pepper; Brawn and Juggernaut lost their speed penalty; six passive items: Barrel Rush (`Run.barrel_rush`, `boost_left`, a timed move-speed effect from `BarrelField`, `Fx.rush*`), Beer, Siesta (`still_regen`, Player counts standing still after 0.5 s), Steady Hand (`still_might`, `Run.note_still` folds up to +100% might in 5% buckets, a ring at the feet, the HUD's STEADY label), Prospector (`xp_drop_chance`, `PickupManager.prospector`), Big Game Hunter (`elite_damage`, `EnemyManager.is_big_game`). **Caps are static**: `weapon_cap` and `passive_cap` (the line cap) `[6, 6, 6]`, `Run.line_cap()`, `MAX_LINES`; `path_times` 7 slots on stage 1 and 8 later. **Rarity** has five tiers (common .. legendary, `ContentDef.RARITIES`) and is the plate's colour, no seal: weapons `W.WEAPON_BLUE` (the line yellow since 47c), lines `W.LINE_YELLOW`, passive items `W.RARITY_PLATE` (WoW hexes), evolutions ink in a brass ring (`W.plate_fill`). **Offers**: `CardPool.weight_of` = weight x RARITY_W x (1 + luck x LUCK_TIER) x 1.5 held x 0.88 per level past the first (Garry: each consecutive upgrade a little rarer) x 3 for a line's evolution; chests draw the same weights over held upgrades and new passive items (`Run.CHEST_NEW_MULT` 0.45); **skips** (2) and **banishes** (1) are per stage, shared by level-ups, mutation offers and chests (`Run.stage`'s setter calls `refill_choices`, `use_skip` / `use_banish`, `chest_skip`, `chest_banish` returns a new roll), no gold for a skip; Mirror: Nerve's form is Skip, Choice's Banish is per stage. **UI**: the HUD holds 6 weapons + 6 lines; the pause Build tab lists passives under their own heading; Collection tabs Weapons / Lines / Passives / Perks / Enemies, enemies badged at the tile's top left in a danger frame (`danger_role`); the chest is SKIP / BANISH / TAKE IT (Banish locked on an evolution or gold, a re-spin; Skip locked on gold), it opens low (`ChestScreen.CHEST_FRAC` 0.77) and its frames are repainted with thick lines (scratchpad `stills47.py` / `install_chests47.py`, warm gold glow); the boss name has no ink box; picked-up gold rises as "+N" with a coin (`Run.gold_gained`, `HUD.gold_popup`); Results' "Damage dealt" names every source with a picture (`ResultsScreen.damage_source`, `art/ui/sources/{fire,revive,blast,unknown}.png`, Venom's icon for poison). **Damage numbers** read on the phone (Alfa Slab, 48 / 64 crit / 40 ticks, thick outline, 0.9 s, ticks at most half of the 60, drawn in passes) and the hero has his own (`hero_hurt`, `hero_shield`, `hero_heal` batched, `hero_dodge`, `hero_block`); Save VERSION 4 turned `damage_numbers` back on (perf_late's `numbers=0` had saved it off; it now suppresses without Settings). **Fixes**: the buffs' clock `Run.buff_clock()` = elapsed + `held_time` (WaveDirector adds the time outside the normal phase) so Berserk, Barrel Rush, adrenaline and the lifesteal cap's second run in boss fights; `EnemyManager.died_xp_scale` pays a variance special's own `xp` (it never had); the Tumbleweed King's spokes as long as the volley (`volley_reach`) and wind-ups at `ATTACK_FPS` 3 (separation shoves made him flicker); the Shrapnel mutation throws steel spikes past the blast (`shrapnel_kind`); the turret's head turns at `turret.turn` deg/s and fires within 6 degrees, Watchtower removed (tools/dl/backup/mutations47), Bunker is its motion pick, `"marks": false` hangs no emblem on the hero (`WeaponBehavior.shows_marks`). **Ironwood** lands with the Pike, shown as "Spear" (ids unchanged), favourite Brawn at level 2; the thrown spear is "Throwing Spear", `hidden`; his title painting lost the spear (a Klein edit). **Art picks**: Dune Scorpion SC-D with `EnemyDef.shadow` {scale, up, drop} read by JsonContent (variant entries may carry their own; `shadow_xform`, `sprite_sink`), Hammer Giant HG-A, Tumbleweed Minion TM-C; icons for the 16 new items, Second Wind (blue screen: its green heart had keyed see-through) and Guillotine (a flat blade) and a plainer coin through `tools/gen_icon_cands.py` (pass 47 jobs, `"set": "47"` -> tools/dl/icons47, kind `source`). Garry raised the skeleton to 10 HP and the knight to 15 by hand (00:40): kept, tests loosened. Tests `pass47_*_test.gd` (rules, ui, combat, hero). Version 0.33. Follow-up 47b: `Settings.float_heal/float_xp/float_coins/float_size` (+ `float_scale()`; damage stays `damage_numbers`) in a Settings panel; title plaque shows a Start plate (`Registry.start_weapon_for`); `W.RARITY_PLATE` softened; every item capped at rare (passive tiers in pass47_rules_test TIERS); Guillotine `text`; Barrel Rush icon repainted (gen_icon_cands `barrel_rush2`). Balancing guide: BALANCING.md. 47d: `HUD._cutout` paints the camera-cutout strip (0..W.safe_top()) in ink during play. 47c: passive items gold_tooth (greed), cold_snap (`freeze_chance`, `EnemyManager.freeze`: freeze_t, still, no bites, ice tint, frost burst; never bosses), hush_money (`gold_on_hit` in Player.take_damage), vulture (`crit_heal_chance`, 2% max HP); Multishot icon repainted. The bible's Items section shows the plates' colours (read from W.gd), a rarity chip per passive item, section 10 "The odds" and section 14 "Tuning the game: where the numbers live".

Pass 48 (2026-10-04, Garry's sixth list, 48 items, version 0.34). **Items:** weapons have **5 levels** (`tools/compress_levels.py`: new L2 = old 2+3, L3 = 4+5, L4 = 6, L5 = 7+8, the level-5 sheet equal to the old level 8; `"max_level": 5` in every weapon JSON); passive items keep at most 5, lines 4. Weapons' and lines' plates **climb the rarity colours with their level** (`W.plate_fill(def, level)`, `W.level_fill`, `WPlate.for_def(def, px, is_locked, level)`: Lv1 common .. Lv5 legendary; evolutions keep the ink plate in a brass ring; passive items their own rarity); stars bigger (cards 40 px, chest 48, pause 34); **mutation dots** on weapon plates (`WPlate.set_dots(Vector2i, ready)`: brass held, hollow open, a brass glow when `Run.evolution_ready`); a weapon evolves with **every** non-hidden path mutation (`Run.path_progress(w) -> Vector2i`, `EVOLVE_MUTATIONS` gone; hero mutations optional). Six passive items: Phoenix Feather (`phoenix_revive`, `Run.phoenix_ready/use_phoenix`, `Game._revive(kind)` 2 s after the fall), Skedaddle (`hurt_speed`/`hurt_speed_seconds`, `Run.skedaddle()` on HP and shield hits, a red speed ribbon), Powder Keg (`powder_keg_chance`, `Game._powder_keg`, source `powder_keg`, no chains), Loose Change (`coin_on_hit`, `PickupManager.toss_coin`: a coin hops 2-3.5 m away and ignores the magnet 1 s), Gas Mask (epic, `gas_mask_cap`, 1% per poisoned creature, `Run.poisoned_alive`, `Run.gas_mask_dr`), Hot Streak (`streak_might`, `Run.streak` to 200 kills, reset by a landed hit); Sinner's Greed epic, Reach (+8% a level), Big Game Hunter and Venom uncommon; Desperado's `text`. **Mutations** (`"hidden": true` keeps a mutation or evolution in its folder, never offered; `Run.add_mutation` refuses hidden ones unless forced): 18 hidden, 17 new (Birdshot `birdshot_lane` (a lane blast), Both Barrels for everyone, Methanol (`params.fire_blue`: blue fire end to end, Fx custom.z + `fire_billboard` heart_blue/rim_blue), Big Peas, Bouncing Skull, Curare (`EnemyManager.hamper` slows moves and attacks, `set_status_tint`), Mini Crits (`EnemyManager.damage(..., flags)` `HIT_MINI`), Repulsor, Tinnitus (counts by `EnemyManager.serial`), Silver Bullet, Hip Shot, Thor's Wrath (`Fx.lightning(..., width)`), Giant Slayer, Pollen (`core/systems/FlowerField.gd`, painted flowers `content/pickups/pollen_*`, HUD pink chevrons), Tarantula Hawk (`core/systems/TarantulaHawk.gd`), Wide Reach (`Mine.gd` a state machine: crouch, spring, blow), Extra Supply, New Equipment); new evolutions Blunderbuss, Moonshine, Pea Cannon, Grave Hail, Hive Queen, Jackrabbit Mines, Golden Pineapple, the Golden Revolver and Earthshaker redone (old copies `<id>_v47`, hidden), Singularity buffed; an evolution's `params.final` merges after the mutations it keeps; `WeaponInstance.merge_params` copies nested dictionaries. Gold that reads gold (Chicago Typewriter, Golden Revolver, Earthshaker GLBs rebuilt, `golden_grenade.glb`). **Systems:** `move_pace` 0.8 in the map timeline (`Run.move_pace()`: hero and creature speeds, walk fps; hostile shots, boulders, rumbles on `EnemyManager.hostile_clock()`; every wind-up and warning / pace, charge and roll durations / pace); priority aim (`"targeting": "priority"`, `EnemyManager.priority_index`, `PRIORITY_CAP` 3, `WeaponBehavior.aim_index`); damage records capped at the creature's remaining HP (`Run.add_damage`, analytics and Results; nothing recorded at 0); `portal_wave` {count 12} then no spawns until the hero continues (`WaveDirector.spawn_portal_wave`), PortalDialog NOT YET (`declined`, the portal re-arms 2.5 m out); HUD slots all 72 px at 50% plate alpha (`HUD.SLOT_ALPHA`) with a brass divider, HOT STREAK / GAS MASK / SKEDADDLE labels, buff plates matched by id; the Collection's tabs and board below the back button at any inset; WoW crits (yellow, a pop and a hop), mini crits paler, poison numbers purple; speed effects per source (`Fx.speed_trail`: Barrel Rush a thin gold ribbon, Sprint blue with wind streaks, Skedaddle red); rare barrels black with brass hoops, the King's tumbleweeds jet black. **Arena dummies:** `content/enemies/training_dummy` (hidden, brain `dummy`, `EnemyManager.undying/home`), `Game.arena_dummies(count, hp)` from `Settings.dummy_count` (>= 10) / `dummy_hp` (0 = undying, else a respawn after 5 s), developer menu rows and the arena WORLD tab. **Art:** the Rocketeer is the **Vulture Raider** (Garry's `_REFERENCES/2d/Vulture Raider with Rocket Launcher.png`, Klein copies picked by eye, walked on `drivers/walk_hold`, attack frames = the standing painting, 35 HP, `artillery.muzzle`, `art/props/enemy_rocket.glb` black via `rocket.gdshader` and `Game.paint_white` (a MultiMesh with custom data needs instance colours on, or COLOR is 0)); the **Bull Beetle** BB-A..D from Garry's rigged rhino beetle (`tools/blender_beetle.py` + `gen_ctl.py`, recipe key `anatomy` replaces gen_ctl's scorpion words), BB-C in play; the magnet structure repainted without sparks; 34 icons (`gen_icon_cands.py` set "48"). Tests `pass48_*_test.gd` (p0, items, projectiles, melee, ui, world).

Pass 49 (2026-10-04, Garry's seventh list, version 0.35). **Items:** Hot Streak keeps every kill made while it is held for the rest of the run (Megabonk's Demonic Soul in our theme): stat `kill_might` = attack damage per 1,000 kills, 0.05 a level, `Run.STREAK_PER` 1000 and `STREAK_CAP` 1.0 (+100%: 4,000 kills at level 5), whole percents in `streak_bucket`, nothing resets it (`reset_hot_streak` is gone); Thor's Wrath and Giant Slayer at 50% (`params.thor.chance`, `params.giant_slayer.chance`); a weapon's plate draws a brass dot only for each mutation held (`WPlate.held_center`; `dot_center` is still the full row); the **Hornet Nest is Killer Bees** (id `hornet_nest` kept: names, texts, quest, TextGen's "killer bees", `TextGen.weapon_name()` for "weapon:<id>" targets; the companion is a cartoon ring beehive in `hornet_nest_visual.tscn` / `hive_queen_visual.tscn` / `killer_swarm_visual.tscn` with an `Entrance` node the bees and hawks leave by, `MissilePod._launch_point()`); the **Tarantula Hawk** is a glowing purple ball (0.17 m, purple motes) that circles its prey at the bees' speed on a tilted, bobbing orbit, turns back now and then and darts in for each of its five stings; **Pollen**: no HUD pointers to the flowers, and its 5 s buff shows as one sage power-up plate with Pollen's icon (`HUD.plate_key/plate_def`, `FlowerField.is_buff/BUFF_PREFIX/MUTATION`; every plate goes the moment its seconds reach 0); in the debug arena the buffs' clock runs (`WaveDirector._process` adds to `Run.held_time` while the director is held), so no timed buff lasts forever there; the pause Stats tab names a timed buff by its label (`PauseScreen._source_name`); the Blunderbuss's bell flares at the muzzle (top 0.19 / bottom 0.09, a dark `BellMouth`). Icons repainted (set "49" in `tools/gen_icon_cands.py`): Barrel Rush (a barrel wearing the Sprint power-up's logo, `tools/dl/sprint_logo_ref.png`), Gas Mask (no fumes), Brimstone Brand (a branding iron pressing a devil mark into a plank), Hot Streak (dice from a Blender render, `tools/blender_dice.py` -> `tools/dl/dice_ref.png`), Skedaddle (the spur on the heel), Killer Bees and Hive Queen (ring hives like the models), Second Sting (a bee). **HUD and screens:** a filled HUD slot is solid, only empty ones see-through; the camera cutout's ink strip is on every screen (`ui/wanted/CutoutBand.gd`, autoload `CutoutBand`, CanvasLayer 110, height `W.safe_top()`); the hero's speed trails draw under his painting (`Fx.speed_ribbon_material()` at `Fx.SPEED_TRAIL_PRIORITY` -2, `BillboardSprite.enable_over_trails()`: a second pass of the sprite in the see-through queue at `OVER_PRIORITY` -1, `core/shaders/sprite_billboard_over.gdshader`, pulled 0.08 m towards the camera with x and y scaled so it lands on the same pixels). **World:** skeletons 1.75 m and knights 1.85 m (radius 0.52 / 0.54); `"hidden": true` in `art/sprites/props/props.json` keeps a painting out of the scatter (`PropField.is_hidden`; the signpost and the yucca; `gen_props.py` keeps an entry's extra keys); the Uber Magnet painted again (Flux dev candidates, the chosen one's screen swapped to green by a Klein edit, keyed with `artkit.key_background(..., cut_shadow=False)` and the green spill clamped: blue had cut the silver caps' corners and the shadow cut the plinth's). **The Bull Beetle** BB-B and BB-C walked again (BB-C still in play): `tools/blender_beetle.py depth=tight amp=1.7` (`tools/dl/drivers/beetle_walk_amp`): each view's own depth range written with the Raw view transform (AgX had squeezed every depth video into one grey) and the legs' swing 1.7x round their average pose; `gen_ctl.py` recipe key `walk_seeds` {view: n} re-rolls one view (BB-B's three-quarter front lost its horn once). **Arena:** the ITEMS tab stacks each weapon's mutations (element, volume, motion, heroes'), evolution and hidden ones under its row (`ArenaPanel.weapon_stack`, a hidden-weapons section; no Evolutions/Mutations sections); dummies: `Settings.dummy_patrol` (the field walks ±2 m), `attacker_dummy_hp`, `elite_dummy_hp/mode`, `boss_dummy_hp/mode` (`DUMMY_MODES` stand, patrol, melee, ranged; `EnemyManager.dummy_mode/dummy_roam/patrol_dir/set_dummy_mode`); `Game.add_attacker(kind)` / `remove_attackers()` add `training_dummy_melee` (10 a bite) and `training_dummy_ranged` (the Spit Cactus's spit, 8) beside the field, the first turning god mode off; the Elite dummy (`training_dummy_elite`, crown) and the Boss dummy (`training_dummy_boss`, archetype elite with `"badge": "skull"`, so no boss bar, music or portal) stand behind the field, pay nothing (`_kill_effects` skips any dummy's purse) and stand up 5 s after falling; an arena death respawns the hero at once (`Game.arena_respawn`: full health, the start spot, 2 s blink, no Down!, no revive blast; HERO's "Go down" sets `arena_real_down` for the real flow). Tests `pass49_test.gd`, `pass49_bees_test.gd`, `pass49_dummies_test.gd`.

Pass 50 (2026-10-04, Garry's Bull Beetle list, version 0.36). BB-C stays the beetle (Garry's pick). It stands on its shadow: `"shadow": {"scale": [1.45, 1.7], "up": 0.35, "drop": 0.07}` (tried by eye in the arena; its painted legs end 11 px above the cell's floor). Its charge carries itself, from new keys in the `charge` block that `EnemyManager.charge_numbers()` reads into `_t_cv` (CV_N per type: shake, crouch, legs, lean, dust, shove, shove_walk, windup; a charger without them is unchanged, the Dune Scorpion). The wind-up crouches, rocks and shakes harder towards the launch (`charge_pose(i, scr)` -> Vector4 side, up, squash, roll, read by `_render`), its legs scrabble in place (`_strip_of` shows the view's run strip, `anim_t` speeds from the walk to `legs` times it, `windup_progress`), and it paws sand back (`_paw` -> `Fx.paw_dust`). It launches stretched with a burst (`_launch` -> `Fx.charge_launch`) and runs at `legs` times its step, bouncing (`BOUNCE`), rumbling and leaning into the run (`lean` x the heading's share across the screen) in a dust trail (`_charge_dust` -> `Fx.charge_dust`, every steer), then digs in squashed (`_skid` -> `Fx.skid_dust`). The lean and rock are a roll about the feet: `roll_basis(s, roll)` tips the instance's x column, and both creature billboard shaders read `atan(MODEL_MATRIX[0].y, MODEL_MATRIX[0].x)` (0 for every plain scaled basis). The shove: `_shove` in `_steer`'s separation loop pushes a creature ahead of or beside a charger straight out to its side (`kb`, `charge.shove` m/s charging, `shove_walk` walking, within SHOVE_REACH past touching, once per SHOVE_GRACE via `shove_t`, never a boss, an Elite, a lifted one or anything bigger), with a flinch and a scuff (`Fx.shove_dust`). Fx has a fifth pool, soft dust (`_dust_mm`, `_emit_dust`, `core/shaders/dust_puff.gdshader`: a camera-facing disc frayed by `art/fx/fire_noise.png`, paler on top; compiled at Fx's start by a puff under the map); only the charger's dust uses it so far (the older sand puffs are still spheres). Tests `pass50_beetle_test.gd`.

Pass 51 (2026-10-04, Garry's eighth list, version 0.37). **The arena's ITEMS tab** has an INFO toggle on every row (a weapon has two: EVO, its stack, and INFO): it opens what a player reads about the item under the row, from the very calls the screens make, read from the run as it stands (`ArenaPanel.item_texts(kind, def)` -> [heading, text] pairs: a weapon held, `WeaponInstance.description()` with its current sheet, the Build tab's `stat_rows()`, `PauseScreen.evolve_note()` and the next level's card `WItem.effect(card)`; not held, the card that offers it (the chest's words for an evolution); a passive or line held, `PauseScreen.passive_now()` (the open Build row's words, now shared) and the next level's card, a maxed line its evolution's card; a mutation or perk, its card), filled again whenever a level is set there (`_info_fills`, `_refill_info`); the open text is `Info_<kind>_<id>` with `InfoText<n>` labels. The EVO toggle reads "3 + EVO": `stack_summary` counts only the path mutations its evolution needs (`Registry.mutations_of`); a playable hero's own mutation is tagged "<Hero> · optional", a hidden hero's (Mira's Blasting Cap, Buck's Drum Roll) sits with the hidden ones (Garry had read the old "4 + evo" as four mutations to evolve; the evolution always needed the three). Calavera's trait is +5% crit chance (was +15%; there is no base crit chance, Garry's pick). Wide Reach springs from 2.8 m (was 3.5). The Jackrabbit Mines are flicked ahead of the walking hero (`params.lay_ahead` 2.0, `MineLayer.lay_point()`, `Mine.toss_to` / `ST_TOSS`: a 0.24 s hop from his feet, armed on landing; standing, at his feet; the Land Mine unchanged). Both Barrels fires its second shot a beat after the first (`ProjectileEmitter._arm_second_barrel/_second_barrel`, `params.double_gap` 0.15 / `DOUBLE_GAP`, re-aimed, its own flash, kick and bang, on the volley and the lane/cone paths; a pending one is never lost to a faster pull); its words "fires twice in quick succession". Dragon's Breath sets 60% of what a shot hits alight (`params.ignite_chance` 0.6, `WeaponInstance.ignite_chance()`, checked in `EnemyManager.ignite` for direct hits through `ignite_roll`: one roll a creature a shot, held `IGNITE_ROLL_HOLD` 0.1 s for that weapon on the crowd's own generator; a jumping fire never rolls), the Blunderbuss 100% (`params.final.ignite_chance` 1.0); the description and the Build tab say the share ("Sets 60% of the enemies it hits on fire", "catches fire 60%"). `tools/arena_check.gd` builds every item's INFO; `touch_audit` taps the Peashooter's INFO (`arena_info`). Tests `pass51_test.gd`.

Pass 52 (2026-10-04, Garry's ninth list, version 0.38). **Three cards at every level-up**: luck had added a fourth half its value of the time (`CardPool.bonus_card_chance`, gone; Game always asks `level_up_offer(3)`); luck now only lifts the rarer items' weights (Clover's and Fortune's texts say so). BALANCING.md lists every rule of the level-up offer ("What a level-up offers"). **Five weapon slots and five line slots** (`Run.MAX_WEAPONS`/`MAX_LINES` 5, `HUD.WEAPON_SLOTS`/`LINE_SLOTS` 5, the timeline arrays and defaults 5; the strip is ten 72 px slots, 832 px). Hot Streak's text is one sentence. `xp_need_mult` 2.1 (5% over 2.0). **Every hero starts with 1% crit chance** (`StatSheet.PLAYER_DEFAULTS`; Calavera 6% with his trait); under the gdUnit runner `Run.base_crit` is false and the base is left out, so suites that count exact damage never meet a random double (pass52_test turns it on). The coin is `core/shaders/coin.gdshader` (unshaded: a bright raised face, a darker ring, a pale lip, a dark brown outline and edge, a glint; `PickupManager.coin_material()`, warmed in Warmup), so it no longer sinks into the sand's gold. **Ground things lie on the slope**: `MapBase.normal_at/slope_at/ground_basis`; the power-up's ring tilts to the ground under it (`Powerup._lay_ring`), the black hole's disc and the eruption's crack ring too, the chest's pool of light gets the slope as a shader uniform (`shine_aura` mode 2 `slope`, `Chest._slope_pool`), and the Nuke's and the revive's wave is a draped band racing out (`Telegraphs.race_ring`, `MODE_RACE`) instead of a flat torus at the hero's height. The menu backdrop (`menu_backdrop.jpg`) was shot again (`wanted_shots only=backdrop`): no yuccas, ocotillos and agaves in their place. **The live main menu** (lane M, a subagent): `Settings.menu_style` "painted" (default) | "live", a Debug panel in Settings only in debug mode (`SettingsScreen._debug_panel`, WChoice `MenuStyle`); `ui/TitleStage.gd` (a SubViewportContainer: its own world with Red Canyon from seed 88, the hero at a picked spot (`SPOTS`), the run's camera angle closer in, the hero's in-game sprite idling/glancing/turning, his start weapon's `Familiar` flying its `params.familiar` circle with its own motions (none for Ironwood), a swap that runs the next hero in, locked heroes dark with the padlock, the 3D scale a run's, the built world kept as `TitleWorldKept` while in Upgrade/Collection/Settings and forgotten on PLAY/ARENA); TitleScreen preloads it (`TitleStageScript`). Garry set the map's `move_pace` to 0.6 by hand before this pass: kept (pass333 and pass48_world re-pinned; BALANCING.md and the bible say 0.6). `tools/perf_late.gd` skips build weapons past the five slots. Tests `pass52_test.gd`, `pass52_menu_test.gd`; touch_audit `title_live`, `settings_debug`.

Pass 53 (2026-10-05, Garry's tenth list, version 0.39; five parallel lanes on brief files, resumed once after a session limit cut them off). **Waves, overrides and the Level Editor** (`docs/waves_schema.md` is the schema, `docs/level_editor.md` the guide): the map's `timeline_data` gains `waves` (explicit windows: `t`, `until`, `count`, `burst`, `every`, `pattern` pack|scatter|single, `respect_cap`, `channel`, `elite`, `toast`, weighted `alts` rolled fresh every run), roster rows take `pack`/`pattern`/`variant`/`stats`, events take `name`/`chance`/`t_jitter`/`stats`/`variant`, weighted `enemy` lists, `elite_every.interval` as `[min, max]`, `swarm.pattern`; `stats` overrides (`EnemyDef.with_overrides`: hp/damage/speed/size/radius, `*_mult`, `contact_cd` (a new EnemyDef field, the bite cadence), `attack_rate_mult`, `projectile_speed_mult`, `knockback_mult`, pack, max_alive, cap_share, xp_mult, drops, `pickup_chance_mult`, `pickup_weights`, elite/boss blocks with `boss.attacks` on/off) make a cached copy with its own `type_key()` (`id[@variant][#hash]`, `Registry.enemy_with`, `EnemyManager.spawn(..., variant, overrides)`, `alive_of` across the id's types); `WaveDirector` rolls alts/chances/jitter at `start()` (`_roll_waves`, `_roll_events`, `wave_state(id)`, `skip_events_before`); `EnemyManager.stun(i, seconds)`. The editor is `tools/level_editor/` (Python stdlib server + one vanilla page: Timeline calendar with the cap curve, roster bars, wave blocks, event flags, specials; an inspector with every override as a placeholder; Settings, Creatures, Instructions with a worked example; validation; Save = backup + JSON + `import_json`), started by `tools\level_editor.cmd`; `tools\ship.cmd` runs ship.sh from a double-click. **Pacing**: skeleton + knight from 0:00 at 9 : 3, `lesser_scorpion` from 1:00, `fire_ant` from 5:00 as 0.6 of a mummy (36 HP, bite 8, size 1.15, packs of 8, cap_share 1); `move_pace` 0.9 (Garry's hand edit) imported. **Creatures** (all the skeleton's numbers): `lesser_scorpion` LS-A/B/C (gen_ctl on the Dune Scorpion's drivers at `size` 1.5, black, three detail levels; `keep` must say "jet-black, never brown" or Klein paints the three-quarter views brown; `remap_hues` keeps value, so a wrong colour must be repainted, not remapped), `werewolf` WW-A/B/C (`tools/gen_edit_stills.py`: front candidates as Klein edits of `_REFERENCES/2d/Werewolf.webp`, picked by eye, then `gen_art --variant`; walked on `tools/dl/drivers/orc_walk_wolf`, the Orc Walk retargeted with `body=`), `red_goblin` RG-A/B and `red_goblin_runt` RR-A/B (`tools/recolour_strip.py`: GOB-D/RUN-D strips with hues 55-135 moved to 357 / 14, the same frames), `dust_mummy` DM-A..D (new rags fronts as edits of the old painting; A/B walk on `tools/dl/drivers/zombie_walk` from Garry's `Zombie monster walk.glb` through `pose_driver.py glb= rig=sm` (the RIGS bone map, a centimetre rig scaled, `start=`/`end=` slicing one stride of a two-stride clip), C on `walk_zombie_low/high`, D a free clip; DM-0 is the old one, still in play). **Weapons** (every hidden thing kept in its folder): Rocket Pod hides thermobaric/salvo/bunker_buster for `heavy_warhead` (bigger, harder rockets, `blast_fx`), `cluster_munitions` (`core/systems/Bomblets.gd`: `params.cluster`, a field of dots that pop underfoot, cap, `chain`), `pressure_cooker` (`params.pressure`: the pod's interval shrinks while the hero goes unhit, a hit resets, the pod's materials warm) and the evolution `hellfire_battery` (six tubes, every rocket clusters and chains, `overpressure` double volleys; missile_massacre hidden); the rocket capsule flies nose first (`register_kind(..., basis)`), missiles hit at 0.3 x size, bomblets reach missiles; Turret Buddy hides dart_buddy for `last_stand` (`turret.boom` on expiry) and the evolution `iron_bastion` (`art/props/iron_bastion.glb` from `blender_turret.py -- only=bastion`, `params.focus` marks; turret_family hidden); Zap Beam hides venom_arc for `echo_zap` ("Aftershock" is the Hammer's name: 20 % → three follow-up zaps with a discharge; storm_cloud's `final` lifts it to 35 %); Sabre hides flame_blade for `critical_thinking` (+10 % crit on the player sheet), Flurry = x2 slices with no cut, evolution `whirlwind` (360° swings, `crit_refund`; zweihander hidden); Spear hides venom_tip/phalanx for `stunning_thrust` and `long_spear`, Wide Sweep is a slice with `amount_mode blades`, the thrust has bite (`windback`/`hitstop`/`flex`, a streak, sparks), evolution `thunder_lance` (`alternate` sweep/thrust, every hit stuns, `stunned_mult`, `crackle`; halberd hidden); Tumbleweed hides thorny_weed/weed_storm for `thorns` (same icon; `out_speed_mult`/`back_speed_mult`) and `dust_wake` (`params.aura`, a spinning ring MultiMesh), the projectile is `art/props/tumbleweed.glb`, evolution `dust_devil` (jet black, `return_damage_mult` 2, `second_pass`, a pulling wake; stampede hidden); the Boomstick fires only with a creature in reach (`params.fire_blind` on the Blunderbuss keeps it blasting); `WeaponBehavior.glow_companions` lights every dim companion material (`GLOW` 0.45, `params.glow`); TextGen says the new Thruster and MissilePod rules. **Items and polish**: common plates `d2cfc7` (weapons and lines at level 1 too), HUD weapon slots at the left edge and lines at the right (no divider), `Settings.menu_style` default "live" (Save VERSION 5 migrates), `Save.DEFAULT_HERO` drifter (the astro once-flag gone), the barrel lid's planks clipped to its disc and `BarrelField` applying each part's node transform (the hoops sat 12.6 cm low), perks suit_seals/serenade/bounty_hunter hidden, Supply Drop drops a heart or a magnet pulse and its blast does half. The bible's Items section has a Hero items group, the creature table shows every creature's picture and lists the unplaced ones, and every picture opens in a zoom pop-up. Tests `pass53_waves_test.gd` (27), `pass53_weapons_a_test.gd` (11), `pass53_weapons_b_test.gd` (13), `pass53_items_test.gd` (8), `pass53_lead_test.gd` (5); `tools/item_shots.gd` captures weapons and creatures in the arena.

Pass 54 (2026-10-06, Garry's eleventh list, version 0.40; six lanes on brief files, cut off by the account's limits four times and resumed each time from status files). **Solenne** (`content/characters/solenne`, she): trait Magic Hour (`buff_duration` x1.25, `debuff_duration` x1.25, cooldown x0.87, max HP x0.8; new player stats `buff_duration` (`Run.buff_seconds`: every timed buff, power-ups, structures, Pollen, Barrel Rush, the shield) and `heal_mult` (`Player.heal`, `_tick_regen`)), favourite Haste at level 2 (`CardPool.offer_passives` offers the run hero's favourite whatever its quest), perks `afterglow` (heal_mult +0.4) and `sunburn` (a burning or poisoned creature takes +20 % from her, `EnemyManager.damage`), hidden `lingering_light` and `long_day`; her title cut-out, badge and front/back stills are cut from Garry's turnaround (`tools/make_solenne_static.py`), the other views painted, walked on his `Walking_sun.fbx` (`tools/dl/drivers/walk_sun`, back views on `walk_sun_spread85`: `tools/pose_scale.py` shrank them 85 % so the wide arms stay in the clip), keyed with the new keyer knobs for glossy black latex (`key_sat` 0.85, `key_min_value` 0.8, `key_cut_shadow` false, `key_clamp_screen` true: `artkit.KEY_*`, read by `gen_art` and `tools/rekey_clip.py`). **Sun Scepter** (`core/behaviors/SunScepter.gd`, `core/systems/SunBeams.gd` one MultiMesh of 48 pillars on `sun_beam.gdshader`, Solenne's start weapon): `amount` pillars on on-screen creatures weighted 1/max(d,1.5)^2, the loose rocket's red `hold_ring` at 0.35 alpha (`ring_color`) + a soft beam for `warn` 0.45 s, hold when nothing is on the screen; paths Heat Stroke (ignite 35 %), Flicker (cooldown -30 %, damage -25 %, thinner yellower), Gold Dust (`params.gold_dust`, coins in `Game._kill_effects`); evolution Zenith (`params.final.zenith`: every 10th strike hits every on-screen creature at 80 %, the `Charge` ring fills); `tools/blender_scepter.py`; the title flies it sun-up (`TitleStage._fly_sun`). **Combat**: `creature_damage_mult` (1.25 on Red Canyon) and `damage_time_mult` multiply every hostile damage (`EnemyManager.hostile_mult()`); every creature has a contact `knockback` (`EnemyDef.default_knockback` = clamp(3.4 sqrt(dmg/4), 2.5, 7), written into every JSON by `tools/set_knockback.py`), `Player.hit_knock` (cap 9 m/s, a 0.12 s stick lock; big game x1.6; shots 0.7 of their shooter's), and `Game._on_player_hit` adds a red vignette, a 45 ms hit-stop and a sand puff; ranged weapons pick only on-screen creatures (`EnemyManager.onscreen[]`, `refresh_onscreen`, `any_screen` on nearest/priority/random/densest and `WeaponBehavior.aim_index`/`crowd_spots`; homing picks pass true; `Settings.ranged_on_screen`, a debug-panel switch). **Pickups**: `PickupManager._merge` fuses only gems farther than magnet + 4 m, cluster by cluster (the vanishing gems), coins capped at 150; gems half size, coins 75 %; gems and coins draw under every painted figure through the stencil (`enemy_billboard`, `sprite_billboard`, `prop_billboard` write 1; `coin.gdshader` and the gem material read not-equal; blob shadows at -3). **Waves** (`docs/waves_schema.md` "Pass 54 additions"): `spawn_sides {mode sides|facing, top/bottom/left/right, facing_share, facing_spread_deg}` (55/15/15/15), `hp_curve` / `damage_curve` {mode points|formula, points, formula {kind linear|power|exponential, a, b}} (`WaveTimeline.curve_mult`, `sample_points`), roster `weights [[t, w]...]` presence keyframes + row `id`s, row `stats.variance` / `elite_weight` / `elite_formats {single, pack, ring}` (`WaveDirector._spawn_elite`). **The Level Editor, second round** (`tools/level_editor/`, `docs/level_editor.md`): picture lists for every creature/variant/elite/pickup pick (`Forms.iconSelect`, the server's `icon_play`), cap points labelled and explained, presence curves in the roster bars and a Share band, row reordering, hover cards with HP/ATK at that second (`model.js` is the game's maths), HP x / ATK x lanes, the elite block, knockback, spawn sides, creature damage x, "Set as default look" (`POST /api/enemy/<id>/variant`), `selftest.py`. **UI**: the pause Options' slider thumbs were clipped by the scroll (spacers, margins); the floating-text block in pause Options; DamageNumbers in Bitter 800 (52/78/64/44/58/52/44, outline 0.28); `WWeaponReel` pre-reel on mutation offers (`Run.next_path_weapon` is random, `Run.path_offer_weapons`); the rainbow XP rail and a bigger level-up reveal on CardScreen; the mutation chest's purple header (`ChestScreen.style_header`); kind glyphs (`WPlate.kind_mark`, `art/ui/wanted/kind_*.png`); bold numbers in serif text (`WText.bold_numbers`, `W.serif_text`); the Phoenix fly-off (`HUD.fly_item`) and "(used)" in the Build tab; sounds `ui_reel_tick`, `ui_card`. **World**: lighter, less orange sand and river bed (`gen_textures.py`, shader flats, `RedCanyon.sand_color/river_color` wired); `water_level()`; creature splashes, ripples on the surface (`Telegraphs` ring `y_lift`), no shadows in the water; agave radius 0; signposts (`core/systems/SignField.gd`, `art/props/sign.glb`: 4-6 posts, 1-4 arms to the nearest unused structures at least 35 deg apart, camera-facing name tags lifted clear of each other, blank once used, SCALE 1.45); `BarrelField.covers_of` fixed (structure cover bands were never applied); the boot splash (`art/ui/splash.png`, Android `splash_screen/*`, no Godot logo). **Art**: SK-E / KN-E dark-blue looks (`recolour_strip.py --mode tint`, `artkit.tint_range`), LS-A painted as a Klein edit of LS-B's side, the pass-54 icons (gen_icon_cands set 54). The tumbleweed is `art/props/tumbleweed_dark.glb` (74, 46, 24) with a glow, Thorny Weed tinted (`params.tint`, `ProjectileEmitter.tint_kind`), the Dust Devil black with a rim. Tests `pass54_waves_test.gd` (16), `pass54_combat_test.gd` (20), `pass54_weapons_test.gd` (17), `pass54_ui_test.gd` (14), `pass54_world_test.gd` (20), `pass54_lead_test.gd` (4).

Pass 55 (2026-10-06, Garry's Solenne list, version 0.41; two lanes on brief files). **Solenne's walks are art variants** (heroes carry `variants` like creatures since this pass: `CharacterDef.variants/variant/variant_def/variant_codes/look_code/variant_note`, `JsonContent._character_variants`; the kept look is `Save.hero_look/set_hero_look` (written through the arena's sandbox), the hero draws `Player.look` (`show_look(code)` for a visit), the title draws the kept look): SOL-A is pass 54's walk, SOL-B Garry's `Walking_sun.fbx` again, SOL-C Mixamo's Catwalk Walking (`tools/dl/mixamo/catwalk_walking.fbx`), SOL-D the heroes' run; SOL-B plays by default. B, C and D walk on drivers squared to her hips (`pose_driver.py fwd=body`: the feet had turned Walking_sun's views 20 degrees, so the side walk went up the screen) and fitted to her painting (`tools/pose_fit.py` + `tools/pose_templates/solenne.json`: the Mixamo body had been a third taller than hers, so her head grew walking down and shrank walking up and her hands were large; the face is pinned on the painted sun disc, facing the viewer, so she no longer looks aside), the back views through `pose_spread` (no hands on her back), and her side still is composed (`solenne_s55_side`: the side painting's body under the three-quarter-front painting's head; Klein painted the disc edge-on six times out of six), named per view by the recipe's `still_keys`; `gen_art.py --variant` takes heroes (recipe `still_keys`, `pose_drivers`, `pose_motion`, `run_fps`; the badge is left alone). **The arena's HERO tab** switches heroes on the fly (`Hero_<id>` tiles, the out-of-play ones in debug mode, `Game.arena_swap_hero`: the new trait, the old hero's perks dropped, the items kept), shows a look on the hero (`Look_<code>` chips) and keeps one for every run (`KeepLook`, "Runs use ..."); touch_audit `arena_hero`, arena_check `_hero_checks`. **The Sun Scepter**: the Familiar 30 % smaller (1.19); every strike shakes the whole sceptre (`SunScepter.shake_at`: pitch and roll jitter and a kick up the staff, 0.25 s, the Zenith sweep twice as hard) and flares a small sunburst at the sun (`flare_at`, `params.shine {idle, flare, sweep, pop, charge}`; the plain sceptre shows nothing at rest, no crossed-bar glint (`sun.glint` 0)); mutations show on the sceptre, no floating emblems (`params.marks` false): Heat Stroke tints the handle a little orange (`params.staff_tint`), Flicker loads a ring round the handle (`params.handle_ring`), Gold Dust adds nothing; Zenith keeps its constant shine and bars and flares harder; the title's sceptre strikes the same way; Zenith's icon repainted (gen_icon_cands `zenith2`, set 55, the glow keyed out of the hoop). **Signs** point without names (`SignField.SHOW_NAMES` false; the tags and their layout stay for the day they come back). **The tumbleweeds roll** like wheels the way they fly (`params.roll_radius`: tumbleweed 0.6, Dust Devil 0.75; `ProjectileManager` spins a rolling shot v / (roll x size) about the axis across its flight; they had spun about their flight like drills). Tests `pass55_hv_test.gd` (14), `pass55_sc_test.gd` (9), `pass55_lead_test.gd` (4).

Pass 56 (2026-10-07, Garry's twelfth list, version 0.42; a plan-mode interview settled the open points, then three lanes, each reviewed by two reviewers and given a fix round). **The XP bar is twice as thick** (`HUD.RAIL_H` 36, `RAIL_INSET` 6; `TOP_Y = RAIL_H + 12`, `SLOT_Y = TOP_Y + 96`, `BAND_H = SLOT_Y + 94` follow it; CardScreen's rainbow copy reads HUD's constants and its header, mutation head and card lists move down by `RAIL_GROWTH`, the mutation cards fitted after the reel lands); under the strip the power-up plates come first and the boss plate and bar sit under them (`BOSS_UNDER_BUFFS`, `boss_plate_bottom()`), the words and toasts under those, a toast on screen sliding to a new place (`TOAST_SLIDE`); the arena's quick column follows the camera cutout and the boss plate (`ArenaPanel.column_top/place_column`); a tap that dismisses the resume gate on the strip no longer also opens the pause menu (`ResumeGate.on_strip`, touch_audit `gate_strip`). **The weapon card glyph is one solid revolver** (`tools/make_kind_glyphs.py` `revolver()`; the scroll unchanged; passive items get none). **XP gems are octahedrons** (`PickupManager.gem_mesh`: flat-shaded facets, `GEM_TALL` 2.4, `GEM_GROW` 1.05 with per-kind `GEM_LOOK` so each looks 1.05x its v0.41 self on screen and `VACUUM_LOOK` keeping the vacuum's size; `rest_of(k)` floats each clear of the sand; a drop starts the same height over its own rest), keep their float and add a very rare extra hop (`HOP_EXTRA_*`: each gem once in 40-60 s, 0.3 m, a spin flick and a landing squash, at most one starting on screen every `HOP_EXTRA_GAP` 0.75 s), and the medium and large gems glint now and then (`GLINT_*`, `core/shaders/gem_glint.gdshader`, throttled, only on screen below the HUD band). **The hero wades into the oasis like the creatures**: his over pass (pass 49) and his see-through outline discard where the camera's line to them crosses the water disc (`sprite_billboard_over.gdshader` and `sprite_silhouette.gdshader` `water`/`water_thick`; `BillboardSprite.set_water/clear_water/water_covers`; `RedCanyon.water_disc()` with `LAKE_DISC` 1.06 and `LAKE_THICK`; `Game._sink_hero` every frame within `WADE_REACH`), and the blob shadows (his and every creature's) hide wherever the drawn water covers them (`water_covers_blob`, `EnemyManager.shadow_wet`); purely visual. **Solenne's badge** is a Klein close-up with a wink and a sly smile (tools/dl/stills56), composed by a hero-JSON `"badge" {still, head_width, top_pad}` recipe (`gen_art.portrait_badge(head_width, top_pad)`), so the whole sun shows and her shoulders are solid. Garry reshaped Red Canyon in the Level Editor during the pass (a cap curve with rushes and drops, the roster reworked, `spawn_sides.mode` back to "facing"): kept, and the map tests now read his map file instead of pinning his numbers (pass17/24/25/26/28/44, pass45_pacing, pass46_pacing, pass54_waves). Tests `pass56_ui_test.gd` (13), `pass56_pk_test.gd` (15), `pass56_wt_test.gd` (15).

Pass 57 (2026-10-07, Garry's thirteenth list, version 0.43; three lanes on brief files, cut off by the account's weekly limit and finished from their status files). **PostHog**: the key file is `game/config/analytics.json` (`host` https://eu.i.posthog.com, `key` "" for Garry's `phc_` Project API key, `enabled` false; outside content/ so the Registry never scans it, shipped by the export's `*.json` filter; a write-only key, safe to commit). `core/autoload/Analytics.gd` (autoload, no class_name) stamps every event with super properties (`schema`, `app_version`, `os`, `os_version`, `device`, `screen`, `top_inset`, `lang`, `dev`; in a run `run_id`, `hero`, `hero_look`, `map`, `map_rev` = a short hash of the map's timeline as loaded, `stage`), queues in memory and `user://analytics_queue.json` and POSTs `{host}/batch/` every 30 s, at 20 events, at a run's end and on background/quit (one request in flight, backoff 30 s .. 5 min, the oldest dropped past 2000); it never sends from headless runs, tools, the gdUnit runner, the debug arena, with `Settings.analytics` off, or without a `phc_` key and `enabled: true`; editor-binary runs, debug builds and the player's debug mode send with `dev: true`. Events: `app_open`, `app_background`, `run_start`, `run_end`, one `run_summary` (per-minute arrays `m_alive`, `m_cap`, `m_spawned`, `m_killed`, `m_press`, `m_est`, `m_dmg`, `m_hp`, `m_level`, `m_took`, top-10 totals, `fps_avg`/`fps_low`), and RunAnalytics' kinds renamed (`Analytics.KIND_EVENTS`: item_picked, level_up, path_offer, card_banished, chest_opened, structure_used, pickup_taken, boss_started, boss_killed, elite_spawned, stage_started, endless_wave, portal_reached, stage_cleared, player_died, revive_chosen, quest_completed). `Save.install_id()` (UUID v4, kept in the save; a wipe makes a new one) is the distinct_id; no identify calls, no person profiles, `$geoip_disable`; no consent card yet (Garry is the only player). Settings has an "Anonymous play data" switch (off deletes the queue); the developer menu shows key set, enabled, queue, sent, the last send and a Send now button. `docs/analytics_plan.html` was rewritten for what is built (published artifact). **Spawn patterns** `ring` (`WaveDirector.RING_RADIUS` = 9 x 1.3 = 11.7 m, `ring_points`: even spacing from a random start, a slide of 0.2 of the spacing, 0.6 m of radial jitter, clamped; a row's pack, a wave's burst, all at once; the swarm's ring stays 16 m) and `in_front` (`_in_front_point`: each creature its own point 19-24 m within 45 degrees of the camera's up, ignoring `spawn_sides`; rows, waves, swarms); the editor's note under Pattern counts a thick ring (`U.ringCount`: 1.5 x 2 pi 11.7 / (2 x radius x size), rounded to 5; `U.RING_RADIUS` mirrors the game's). **Spawned so far**: a Level Editor lane under Cap with the cumulative spawn estimate (`model.js spawnEstimate`, its Python twin in selftest.py: the director's rules second by second with expected values; a kill rate (share of the living crowd a second), the boss fight's and the portal wait's seconds fitted from Garry's run records by `GET /api/turnover/<map>`, editable on the lane), stacked regular / coloured / Elites / specials / bosses with arrival marks and a hover card of every creature's count; within 9 % of a real run's record after 2:00. Tests `pass57_an_test.gd` (15), `pass57_sp_test.gd` (12); selftest 13832 checks. `pass56_wt_test` pins its skeleton's size (the variance's size jitter made the 0.45 m bank check flaky in the full suite), and two gdUnit runs at once share `user://test_saves` (lanes run their own files only). A review after the commit found the Android preset had no `permissions/internet` (no send could ever leave the phone): `export_presets.cfg` asks for it now, and `pass57_an_test` checks it.

Pass 58 (2026-10-07, Garry's fourteenth list, version 0.44; six lanes on brief files, then one reviewer and a fix round per lane in a workflow, after the account's session limit cut the first reviews off). **Boot**: `splash.png` is paper to every edge with an empty loading bar and LOADING baked in (`tools/make_splash.py`; the old ink bands floated inside a 20:9 screen as "brown lines" while the title loaded in one blocking step); `ui/Boot.gd` draws the same picture at the engine's Keep rect as one quad (an inline shader, the brass fill mixed in), loads the title with `ResourceLoader.load_threaded_request` (a fallback `load(..., CACHE_MODE_IGNORE)` on FAILED or a 10 s stall), builds it under the cover and dissolves over at least 8 frames, `CutoutBand` fading in with it. **Level-up and mutation screens** (`ui/CardScreen.gd`): the rainbow rail is full on every offer; `ui/wanted/WShine.gd` (a canvas shader on one square: brass and paper rays turning opposite ways, a breath, glints; `make/put/tint/pop_in/fade_out/show_now/warm`, warmed in `Warmup`) turns behind LEVEL N (radius 520), behind the mutation plate after the reel (500) and behind the chest; the star line reads LEVEL UP (34 px with an ink shadow, `WModalHeader.shadow_star`); banish mode is a red BANISH title with the star line STRIKE ONE OFF and plain words, a red stamp on every card that may go (on `WCard.tag_node`), held cards dimmed with YOU HAVE THIS (a tap shakes and says why), CANCEL, a BANISHED ghost while the replacement drops in, a locked button with a reason, a first-time note (hint `banish`). **The banish rule** (Garry: "should not allow Banishing items that Player already has"): `Run.banish_refusal(card)` returns "" or gold / held / evolution / path, used by `Run.banish_card`, `Run.chest_banish`, `CardPool.banishable` and `ChestScreen.can_banish`; `open_mutations` and `boss_chest_mutations` skip banished ids; an evolved weapon's base is never offered again (level-ups, the Stranger). **Cards** (`WItem`, `WCard`, `WMarks`, `TextGen`): a tag pill on the word line (UPGRADE brass with a chevron, NEW sage, EVOLUTION ember; `WItem.tag`), an upgrade lists what changes as rows ("Damage 9.6 → 11.5", the new number bold, a loss in `W.BAD_DARK`; `TextGen.weapon_changes`/`passive_changes`, at most `CHANGE_ROWS` 4, `amount_noun` names Hammers / Blades / Bees..., `area_radius` shows blast radii in metres; `WItem.card_text` is the one-line form the arena's INFO uses), the "this pick" stars pulse (`WMarks.pulse`, off by default); the chest's landed item the same. **Death splash** (`Fx.blood`, its own pool of `BLOOD_MAX` 384 on `core/shaders/blood_splash.gdshader`, animated by the shader from per-instance data; `Game._death_splash(i)` from `on_creature_died_index`): a 0.36 s splat 0.62 x size wide with drops at the body in the creature JSON's `blood` (`EnemyDef.blood`, every creature has one; red for flesh, cyan ectoplasm for skeletons, blue goo, green ichor, embers...), bigger for Elites and bosses (`Fx.blood_size`: past `BLOOD_SOFT` 2 m it grows with the square root), drops thinned in a crowd and splats shrunk in a mass kill (`_blood_burst`); the pale burst regular creatures had is gone. **Strongbox** (`Game.bank_purse`, `StructureManager.deposit`, `core/systems/CoinStream.gd` (no class_name), `core/shaders/coin_flight.gdshader`): the purse is banked at once, then 3D coins (0.3 m, dark rim, glint, shadow, sparkles; one a gold up to about 37, 89 at 400, at most 120) arc from the hero into the box over 3.0-3.6 s, quicker and denser with more gold, growing with the camera's zoom, a rising ping each and a bounce of the box, the purse counting down; the balloon lifts after the last coin. **Waves** (`docs/waves_schema.md` "Pass 58"): a row's numbers are fixed from its start (`WaveDirector.fixed_numbers(t0, stats)`, `source_for` keys `row:<id>#<index>` / `wave#<k>`, `forget_sources`; `EnemyManager.spawn(..., src)` keeps `f_stage`, `f_hpt`, `f_lvh`, `f_dmt`, `f_lvd` per creature and every later hit reads them; the curves at t0, the hero level at the row's first spawn, a `stats.hp`/`damage` override takes no curve, the stage multiplier stays live, bosses and Elite creatures as before); an event of a creature a row is bringing joins that row's numbers (`event_numbers`, `brood_numbers`), the portal wave the row it drew; in endless every row re-fixes at each WAVE; `stats.size: [min, max]` rolls a size per creature (radius follows, the special capped inside, wide creatures scan more grid cells); `stats.tint {hue: [h0, h1], sat, val, amount}` colours a row through `vtint` (a coloured row's special takes `EnemyDef.tint_special_color`: sat + 0.15, val x 0.7, strength + 0.15); ring and in-front spawns spread over the arcs inside the arena and off the lake (`EnemyManager.ring_spots`) and 15-24 m points turn inward at the wall (the pass-57 review: a ring had piled onto a hero at the wall). Garry's rows that set `stats.hp` lose the time curve they used to get (fire ants at 7:10 about -48 %): his numbers are kept; the one-time bake that would keep each row's first second is in the pass report. **Level Editor** (`docs/level_editor.md` "Pass 58"): a row's HP and ATK fixed from its start in a green line under From / Until (following a dragged bar; events name the row they join), **Actual HP x** / **Actual ATK x** lanes (spawn-weighted average, largest, the intended curve dotted; `model.js actualAt`), a size range (the creature's size as reference), a Colour group (hue strip with two handles, saturation, brightness, amount, a live preview of the in-play standing frame from `GET /sprite/<kind>/<id>[/<code>]` tinted by `Model.tintPixel`, the special's shade), an always-visible Default look strip and a blood colour per creature on the Creatures tab (`POST /api/enemy/<id>/blood`; creature keys are written line by line, `set_top_key`), a hint on long bars whose curve climbs past them; selftest 14038 checks. Tests `pass58_boot_test.gd` (12), `pass58_uia_test.gd` (14), `pass58_uib_test.gd` (14), `pass58_fx_test.gd` (18), `pass58_wv_test.gd` (29); re-pinned on purpose: pass47_rules, pass47_ui, pass51, pass54_ui, pass54_world, pass56_ui.

Pass 59 (2026-10-07, Garry's analytics requirements, version 0.45: follow one player, read PostHog on the phone, surveys; his answers: friends first, the name in Settings, the id kept through a wipe, PostHog's own site with a daily email, questions only on the Results screen, no reward). **Players**: person profiles are on (`$process_person_profile` is no longer sent false); every install is a Person under its `install_id`, named by `Save.player_name()` (`Save.name_for(id)`: `NAME_ADJ` x `NAME_NOUN` x 10-99 from the id's md5, "Dusty Coyote 41"), sent as the person property `player_name` (`Analytics.person_properties()`, with `app_version`, `surveys_opt_out`, `analytics_consent`; never `label`, which is Garry's) on `app_open`'s `$set` and on `consent`; the Settings foot reads "88fits v0.45 · <name>" (`SettingsScreen.version_line()`). A wipe keeps `Save.KEEP_ON_WIPE` (install_id, player_name, consent, survey). **The play-data card** (`ui/wanted/WConsent.gd`, no class_name: `.open(host)`; buttons Decline / Accept): on the title (`TitleScreen`, `CONSENT_DELAY` 0.8 s) when `Analytics.consent_needed()` (a configured key, a real run of the app, not the arena, `Save.consent()` ""); until it is answered `Analytics.awaiting_consent()` holds every event in memory (no flush, no queue file); `answer_consent(yes)`: yes = the switch on, a `consent` event, flush, `fetch_surveys`; no = the switch off and `purge()`; afterwards Settings' switch is the answer (`_on_settings_changed` records yes/no). **Surveys** (PostHog Surveys, API presentation): `Analytics.fetch_surveys()` GETs `{host}/api/surveys/?token=<phc key>` at launch after consent (`set_surveys_from` keeps launched, unended, unarchived surveys and the question types `SURVEY_TYPES` rating / single_choice / multiple_choice / open; cached in `user://surveys_cache.json`); `ResultsScreen._offer_survey` asks `survey_after_run(seconds)` (runs of `SURVEY_MIN_RUN` 60 s count, one every `SURVEY_EVERY` 3, never twice a session, each survey until answered: `Save.survey_state()` {answered, runs_since}) and opens `ui/wanted/WSurvey.gd` (`.open(host, survey)`, `CARD_TOP` 330: one question a page, Rate<n> / Choice<i> / Answer (TextEdit), NotNow, Next/SEND, NeverAsk under the card); events in PostHog's shape: `survey shown`, `survey sent` (`$survey_response_<question id>`, `$survey_questions`, `$survey_completed`, `$set $survey_responded/<id>`), `survey dismissed`; opting out (`Analytics.set_surveys(on, where)`: "Don't ask me again" or Settings' "Questions after a run" switch, `Settings.surveys`) sends `survey_opt_out` / `survey_opt_in` and sets `surveys_opt_out`. The plan (`docs/analytics_plan.html`, section "Players, the phone and surveys") has the how-to: the first survey to create in PostHog, editing questions, cohorts for friends, phone boards and the morning email. touch_audit `consent_card`, `survey_card` and the SurveySwitch (in `settings_analytics`). Tests `pass59_an_test.gd` (15); pass57_an re-pinned (a wipe keeps the id, profiles on, the Settings line).

Pass 60 (2026-10-08, Garry's fifteenth list, version 0.46; six lanes on briefs, cut off by the account's session limit twice and finished from their status files; the lead did the PostHog board and the merge). **Pickups** (`core/systems/PickupManager.gd`, `core/shaders/gem.gdshader`): the big magnet pulls (Magnet Pulse, Uber Magnet, the boss chest's opening, the Elite's vacuum gem, Turret Family's attractors: `vacuum_all` and the attractor path call `_start_trip(i, hero, arc = true)`) throw every gem and coin up in a wave rippling out from the hero (phases `PHASE_ARC_WAIT` / `PHASE_ARC_RISE` before FLY: a wait of `ARC_WAIT_PER_M` 0.035 s a metre capped at 0.5 + 0.12 jitter, a launch at sqrt(2 g h) to `ARC_HEIGHT_MIN` 2.4 + 1.4 random + 0.02 a metre with an outward drift, a hang, then the old dive; the walk-up pull keeps its hop); the gems draw through one ShaderMaterial a kind (`PickupManager.gem_material`, `use_custom_data`: x = the charge, y = a seed) that is lit, see-through, no depth write, stencil-read as before: x0.78 darker (`GEM_SHADE`, `COLOURS`; the motes and glints keep the old bright `GLINT_COLOURS`), `GEM_EMISSION` 0.3 at rest and, charged, a glow pushed toward the kind's pure hue at `CHARGED_EMISSION` 1.15 with a 7 Hz shimmer and a pale fresnel rim (an emission of 1.8 toward white had read as paper scraps: the Compatibility renderer has no tonemapping). **Weapons** (`core/behaviors/WeaponBehavior.gd`): the mutation emblems are gone (`_mark_*`, `_tick_marks`, `shows_marks` deleted; `refresh_marks()` only frees a "MutationMarks" node so the overrides keep their hook; the Sun Scepter's Flicker ring and Heat Stroke tint stay; `"marks": false` keys are inert); `muzzle_flash(at, dir)` turns the Muzzle / Flash / Smoke particles along the aim; `streak_mesh` builds a two-surface round (a hot core inside a translucent "Halo" border) so one MultiMesh draws both. The Tommy Gun's rounds are white-hot 0.95 m streaks with an orange border (gold on the Chicago Typewriter), a 0.07 s muzzle pop, shells kept; the Boomstick's pellets fly nose first as short bordered streaks with a cone flash and grey breech smoke (the Blunderbuss too), on per-weapon `params` `tracer_step` / `tracer_life` / `tracer_size` (`ProjectileManager.trail_life`: a bead ages against its own life) and `tail_fade` (the drawn size shrinks to 0.25 over the last share of the flight; the hit radius untouched); references: the Gungeon shot sheet and Vlambeer's feel notes. **Pressure Cooker** (`content/mutations/pressure_cooker`, `core/behaviors/MissilePod.gd`): standing still builds pressure (`params.pressure {max 2.0, seconds 15, hit_vent 0.5}`: `pressure` climbs dt / seconds while `Player.is_still()`, 0 the moment he moves, x(1 - hit_vent) on `player.hit` or `shield_hit` with a steam puff; `fire_interval` = cooldown / (1 + bonus), up to three volleys where one went; `VENT_HOLD` 0.8 s after a hit the ramp neither climbs nor dumps, because the hit's knock carries him a step that is not him moving: the review had found a bite dumping the pressure to 0); the pod glows with it (`HEAT_COLOR`, `HEAT_ENERGY` 1.4), no HUD label; the Hellfire Battery's `final.pressure` carries the same keys with its +25% start; `TextGen` says the rule. **Banish**: `Run.banish_refusal` returns "mutation" for any mutation card (hero mutations included), `ChestScreen` locks BANISH with "A mutation cannot be banished." **Knockback** (`player/Player.gd`): `knock_immune()` = the Invincibility bubble only (`shield_t > 0`; not the Energy Shield, `invuln` or god), and `shove(v, from_creature)`, `apply_knockback(v, hostile)`, `hit_knock(v, from_creature)`, `blast(v, up, hostile)` return under it (`_bubble_knock` gone); a creature's knock goes through `escape_dir(push)` (16 directions scored by the crowd within `ESCAPE_REACH` 4.5 m minus 0.6 x the push: out through the gap) and `settle_knock` (within `KNOCK_SETTLE` 0.45 s a second knock cannot reverse the first; `SETTLE_KEEP` 0.35); hostile shots (`shove(v, false)`), the Thruster lunge and Astro's burst (`blast(..., false)`) keep their line. **Creatures** (`core/systems/EnemyManager.gd`): the timeline's `creature_speed_mult` (0.9 on Red Canyon; `WaveTimeline`, `JsonContent`, `WaveDirector._apply_mults`, the Level Editor's "Creature speed x", `docs/waves_schema.md`) folds into the creatures' `pace` = `Run.move_pace() x creature_speed_mult` (spawn speed, `hostile_clock()`, scripted charges and rolls, wind-ups; the hero untouched; the Vulture Raider's rocket reads `Run.move_pace()` for the hero's share so the mult stays in its flight); the Dune Scorpion's burrow (`windup` 2.3, the Gila's 1.4) grows a sand mound at the ring's centre over the wind-up (`_mound_start` / `_tick_mounds` / `_mound_end`: a hemisphere + a crack ring on the slope, `MOUND_FRAC` 0.3 x size, driven by `timer[i]`), pops with `Fx.pop_dust(at, size)` (puffs, a column, grains, clods; never thinned), a `flash_ring` and a camera shake (the old 8-11 m `fx_burst` discs are 0.4 x size), and the figure rises out of the sand over `RISE_TIME` 0.4 s / pace (`rise_t[]`, `rise_sink` through the terrain's depth test, the badge and the blob shadow following; `frame_code(frame, rise)` sets `RISE_FLAG` 0.5 on the frame's fraction so `enemy_silhouette.gdshader` draws no ghost of the buried part; hittable, not biting, no new attack until up); the Sun Prophet's flicker: hero-facing standing types (caster, kite, artillery, support) face and walk by the brain's `intent[]`, not by `vel + kb` (a shove or a knock no longer turns them), a view holds `VIEW_MIN` 0.25 s over the hysteresis, the caster brain stands for `hold_t`, and eight-direction creatures (Prophet, Centipede) show their front-only hit / attack frames only in the front view. **UI** (`ui/StructureShop.gd`): prices = half a stage's gold by kind and rarity (BALANCING.md §7), the YOU HOLD tray wraps (a VBox under the header with `W.safe_top()`: the label row, an `HFlowContainer` of 76 px plates, 60 from 13 items; `_fit()` squeezes the gap, the plates and at last the list's scale so 22 items and a 130 px cutout still leave LEAVE on screen); `StrangerScreen` offsets take `W.safe_top()`; the consent card and the Settings line no longer mention "the maker" (`WConsent.body_text`, `Analytics.settings_line`); the survey's Answer box focuses on a finger (`gui_input` -> `grab_focus`, `virtual_keyboard_show` as belt and braces), a brass focus ring, the card lifts over the keyboard (`lift_for`, polled `virtual_keyboard_get_height`), a press outside releases it; signs sort like paintings: `core/shaders/sign_depth.gdshader` (`skip_vertex_transform`: screen xy kept, the depth moved to the sign's `foot`, `squash` 0.02 so arms still sort against the post, `bias` 0.03) on every post and arm (`SignField._mat_for(key, foot)`, no shadows), so the hero draws over a sign he stands south of and under one he stands north of. **One screen at a time, and death wins** (`game/Game.gd`): every screen that pauses the run (level-up cards, a mutation offer, a chest, the stage-clear dialog, Down!, the shop, the Stranger) is asked for through `_request_modal(kind, opener)` (`enum Modal`, `MODAL_PRIORITY`: REVIVE 70 > PORTAL 60 > CHEST 40 (+5 for a boss chest) > CARDS 30 > PATH 20 > SHOP / STRANGER 10, oldest first within a priority); one is up at a time, the rest queue; `_modal_done()` opens the next after `MODAL_BEAT` 0.2 s or hands the run back through the gate; while the hero is down only Down! may open, level-ups bank in `_pending_levels`, chests and path offers queue, and all come one after another `REVIVE_BEAT` 0.6 s after a revive; staying down drops the queue; every timer that can land a hit (`elite_explosion`'s bodies, the Down! wait) is pause-respecting; tools that open or close a screen by hand call `Game.modal_reset()` (smoke_run closes the Stranger and the shop through their own `_finish(false)`); an opener with nothing to show (a path slot due with no pick open) never pauses the running game, and a newcomer takes its place behind a waiting queue (the review round); while the hero is down a gem that reaches him lies down where it is, no pull starts and no power-up is spent (`PickupManager._down`); in debug mode `_check_one_modal` reports two screens up at once; the Nuke plays `pk_nuke`. **Sounds**: every effect comes from Stable Audio (`tools/ai_sfx.py`: two engines, Garry's Stable Audio app at http://127.0.0.1:7861/ through gradio_client (Gradio 6, `/generate`, 8 steps / cfg 1.0 only: any cfg above 1 returns silence) and audiocraft_plus on 7860 over the Gradio 3 websocket as the alternate; 3-6 candidates an id, scored by spectral centroid under a per-kind ceiling and above `FLOOR_HZ` 250, sub-bass share, onset, length; pitch shifts are varispeed; levelled to -14 dBFS RMS, peaks -2 dBFS; `--pick id=k` swaps one) into `content/sounds/real/<id>.wav` (118 ids + `pk_nuke` + `silence.wav`; the soundmap's `file` rows; `docs/sfx_review.html` + `tools/dl/sfx60/sfx_review.zip` to listen); the ten voice lines are gone (`voice/` deleted, `gen_voice.py` in tools/dl/backup/, pl_hurt and pl_jump silent, the others non-voice sounds); the placeholder wavs stay as the fallback. **Art**: the werewolf plays **WW-D** (WW-A's front and a back painted to its hunched stance, the back walk DRIVEN on `tools/dl/drivers/orc_walk_wolf_b88` = pose_scale 0.88 of the back view: WW-A's and WW-B's driven back clips had failed gen_art's frame check on the clawed feet and fallen back to free clips with an upright man's gait; creature recipes may pair `pose` (back) with `pose_front` like the skeletons); Solenne gained **SOL-E** (the catwalk again on `catwalk_fit` / `catwalk_fit_spread` / `catwalk_fit_wide_spread` = pose_spread 0.10 for the bd view, a prompt that says what each body part does and what stays put, `anim_seed` 4; SOL-B stays in play; `anim_negative` is inert at Wan Animate's cfg 1.0); the Critical Thinking icon is a sabre's point dead in a bullseye (`gen_icon_cands.py` set 60, `critical_thinking2` c2). **PostHog**: `run_summary` carries the rest of the local dashboard (`m_hp_max`, `m_shield`, `m_took_raw`, `m_evaded`, `m_shielded`, `m_healed`, `m_shield_s`, `m_invuln_s`, `m_load`, `m_hard_cap`, `m_xp`, `m_banked`, `m_kills`, `m_phase`, `dmg_by_minute` for the top eight weapons, `kills_by_weapon`, `took_kind`, `build` / `build_text`, `est_end`; `RunAnalytics.summary`), and `tools/posthog_boards.py` draws them on Run curves (8 tiles) and the new Run health & weapons board (9), keeping every board's id on a rerun. Tests `pass60_pk` (14), `pass60_wp` (18), `pass60_en` (17), `pass60_ui` (24), `pass60_sfx` (11), `pass60_art` (5), `pass60_lead` (5); re-pinned on purpose: pass46_pacing, pass52, pass54_combat, pass47_combat, pass55_sc, pass48_projectiles, pass53_weapons_a, pass58_uia/uib, pass338, pass48_world, content_test, pass54_world, pass55_lead, pass332 (its fake hero's speed carries `move_pace` like the real one); `EnemyManager._spots_on` clamps a slid ring spot into its arc (a once-in-a-few-runs flake of pass58_wv by the wall). The mutation looks Garry asked for as ideas (two per mutation, cheap and expensive) are in the pass-60 report, not built.

Pass 61 (2026-10-09, Garry's sixteenth list, version 0.47; eight lanes on briefs, cut off once by the account's session limit and resumed from their transcripts; two reviewers over the merged work). **Heroes have one or two stats that grow every level** (Garry: "Heroes have 1-2 unique stats, and they scale as they level up"): `CharacterDef.level_trait` (JSON `"trait_per_level"`, the `trait` schema) folded by `Run.hero_sheet(c, level)` (used by `_build_player_sheet` and the CV) as ONE effect per stat worth N x level (a mul per level would compound), source "<trait_name> (Lv N)" (`Run.trait_source`); `Run.add_xp` rebuilds the sheets before each `level_up.emit`; `"trait": []` on the five playable heroes, hidden ones untouched. Drifter crit_chance +0.01 a level; Astro max_hp +2 a level and `level_heal` 0.08; Calavera might +0.01; Ironwood regen +0.1 and regen_delay -0.05 (`StatSheet.STAT_FLOORS` regen_delay 0.5, also on the hit's hold); Solenne debuff_duration +0.015 (no buffs, cooldown or HP). Under the gdUnit runner the Drifter's crit is left out like the base 1 %. A max HP rise adds the same HP (`Player.refresh_stats`). Words from `TextGen.hero_trait / hero_trait_at / hero_trait_now / hero_step` (title plaque "+1% CRIT / LV", Collection, arena HERO tab; the pause breakdown names the source). `CharacterDef.order` (`Registry.sorted_characters`: Drifter 1, Astro 2, Calavera 3, Ironwood 4, Solenne 5). **The hero sheet** (`ui/wanted/WHeroSheet.gd`, no class_name, `.open(host, hero, locked)`): the title's plaque is a WTap (`Plaque`, "DETAILS ›") that opens a Wanted-poster CV (badge, name, slogan, the signature stat at Lv 1/10/20/40, 18 stats a run starts with incl. Upgrade ranks, the start / favourite / hero-only weapons, the hero mutation and the perks with their card words; a locked hero's quest), scrolled by hand, closed by CLOSE, a tap outside, back or Esc; a swipe on the plaque still changes hero (touch_audit `hero_sheet`). **The Upgrade board's choices are icons** (`content/talents/<id>/<id>_<form>_icon.png`, or a form's `"icon"` key; `TalentDef.form_icon`; painted with `gen_icon_cands.py` set 61, whose jobs may name a `"file"`): each tile carries a rank bar of `max_rank()` slots (the chosen form's icon or a dashed empty, `HomesteadScreen.rank_bar`, `TILE_SLOT` 60), a talent without ranks shows both forms beside its name, a **YOUR UPGRADES** strip sums the build (`summary_talents`), the sheet shows the bar at 100 px; `WChoice` options may carry a Control. **The XP rail is 1.8x** (`HUD.RAIL_H` 65, `RAIL_INSET` 11; TOP_Y 77, SLOT_Y 173, BAND_H 267; CardScreen's rainbow follows, `RAIL_GLINT` 7). **Map**: paler sand and a sand-coloured river bed (`gen_textures.py` palettes, `RedCanyon.sand_color` (0.90, 0.78, 0.58) / `river_color` (0.80, 0.67, 0.50), the shader defaults; the river's shape untouched), **bush patches** (`RedCanyon._scatter_sprites` last region: `BUSH_PATCHES` 5-7, `BUSH_PER_PATCH` 4-6, `BUSH_PATCH_R` 7 m, 2.5 m apart, 18 m from other regions; `bush_patches()`, `green_stands()`; no colliders; `StructureManager.clear_of_bushes` / `BUSH_CLEAR` 3 m), signs 1.4x taller (`SignField.STRETCH`, `tilt_for` keeps the 8-degree lean); the launcher icon's sand lighter (`tools/icon_sand.py`, the old source `tools/dl/app_icon/icon_src_v046.png`; it also re-runs `make_splash.py`); the menu backdrop re-shot. **Cheap mutation looks** (Garry picked every "cheap" proposal of pass 60), all from the mutation's JSON: `params.look` {parts, paint, heat, tongue, beads, flick, spikes, specks, blink} and `tint` {roughness, metallic, halo, halo_alpha}, `tracer_color/alpha/beads`, `drum_scale` read by `ProjectileEmitter` (`refresh_marks` -> `_apply_looks/_undo_looks`, `muzzle_flash` -> tongue + heat), `ProjectileManager.tinted_kind / spiked_kind`, thorn specks (`SPECK_MAX` 192) and stuck-grenade blinkers (`BLINK_MAX` 32, 2.5 -> 13 Hz), `Fx.flame_tongue`, `Lobber.shot_kind`: Dragon's Breath (orange pellets, a flame tongue, a red-hot barrel), Both Barrels (a second barrel, brass beads counting to the double; the plain Boomstick now has one barrel), Toxic Peas (lime peas, a green trail), Fan the Hammer (a white glove flicking under the pod), Drum Mag (a 1.5x drum, denser tracers), Sticky (amber resin, a blinking light on the creature), Thorny Weed (thorn spikes, thorn specks on the sand); `params.rust` / `rust_patina` (`core/shaders/rust_blade.gdshader`, `Orbiter._refresh_looks`, `Fx.rust_flake`), `beam.breath` (Bad Breath: `laser_beam.gdshader` haze / wobble / core_color / glow_gain, `Fx.breath_gust`), `params.razor` (Critical Thinking: `Blade/LookRazor`, white crit hairlines from `EnemyManager.last_crit`, `Thruster._crit_slash`), `params.riposte` (a brass `Blade/LookGuard`, a reverse flick once a stroke inside its `back` time, `Fx.clang_spark` + `w_iron_hit`); `Warmup` shows every `Look*` node and builds every tinted/spiked kind (`_warm_mutation_shots`); evolutions keep the looks (Golden Pineapple and Dust Devil carry a `final.tint`). **The Sun Scepter strikes harder**: `SunBeams` `FADE` 0.34, `LAND_POP` 0.85, `LAND_WIDEN` 0.25, `impact_at/width_at` (custom z to `sun_beam.gdshader`); `SunScepter` shake 8 degrees / 0.09 / 0.3 s, a disc pulse (`PULSE_EMIT` 2.2, `PULSE_WHITE` 0.45, `PULSE_SWELL` 0.22), sparks, and per landing `Fx.sun_impact`, a gold `race_ring` (1.6 x radius) and a held scorch glow; a Zenith sweep's landings at 0.4. **Gold in PostHog**: every `Run.add_gold/spend_gold` and `Save.add_gold/spend_gold` names a source or sink (`RunAnalytics.GOLD_SOURCES / GOLD_SINKS / META_REASONS`; `PickupManager.mark_coin` tells coin origins apart; the revive pays through `Run.spend_gold`), `run_summary` carries `gold_by_source`, `gold_spent_by`, `m_gold_in`, `m_gold_out`, `gold_greed`, `run_end` the run's gold ends (earned - spent = banked + lost), and `Save.gold_moved` -> `Analytics.meta_gold` sends `gold_meta` for every bank change outside the purse; `tools/posthog_boards.py` builds a ninth board, **Coins** (13 tiles), and a Pulse tile; the local dashboard has a gold card. **Level Editor snapping** (`model.js` `snapTargets / snapDrag`, `SNAP_PX` 8 at any zoom, tiers cap > rows and waves > events > stage marks > whole/half minutes; a Snap button, `S`, Alt frees a drag; a guide line and "snapped to ..." tag; selftest 14994). **XP gems and coins never fuse or vanish** (`PickupManager`: `_merge`, `MERGE_*`, `COIN_CAP` gone; the pool starts at `MAX` 2048 and doubles (a real run never grows it; a grow costs one spawn about 2 ms) (`_alloc/_grow`, the slot arrays may be longer than MAX: loop over `alive.size()`), each kind's MultiMesh from `INST_START` 1024 doubling (`_grow_instances`), one fixed instance per pickup with swap-remove in `_free`; a lying pickup sits in a grid (`GRID_CELL` 4 m, `GRID_HALF` 96 m) read only round the magnet and the turrets' pulls, only moving ones are in `_act`, each pickup's float phase is a per-slot seed x TAU in custom data y (`phase_of(i)`; the coins carry it too and lift in world space), idle hops and glints wait on a timing wheel (`IDLE_BUCKET` 0.05 s, `set_idle_due`), a hop off the screen passes; the float and spin are in `gem.gdshader` / `coin.gdshader` (`t_now`, `GEM_WRAP` 5 pi, `COIN_WRAP` 10 pi / 3; `shown_xf(i)` is the CPU copy), so a lying gem's transform is written once; a vacuum walks `WALK_MAX` 80 pickups / `WALK_CELLS` 400 cells a tick, on-screen ones arc (`FLIGHT_MAX` 600), off-screen ones wait on `_vq` and fly in from just past the camera's footprint (`_edge_table`, 32 bins + 2.5 m, `FAR_LEAD` 1.25 s, `EDGE_MAX` 80) or, the stream full, are collected unseen when they would have arrived (`_collect(i, quiet)`, `_credit_xp`); 3,000 lying gems cost 0.04 ms a frame against 0.8 ms for the old 600, a 3,000-gem vacuum 0.45 ms against 0.62 for 600; `game/tools/_p61_pk_bench.gd` is the windowed bench). Tests `pass61_hr` (13), `pass61_mr` (9), `pass61_map` (11), `pass61_an` (9), `pass61_wp1` (17), `pass61_wp2` (13), `pass61_pk` (13); re-pinned on purpose: pass23, pass24, pass31, pass45_ui, pass46_hero, pass47_rules, pass51, pass52, pass54_weapons, pass334, pass56_ui, pass54_world, pass54_combat, pass56_pk, pass60_pk, pass46_pacing (the merge is gone).

Pass 62 (2026-10-09/10, Garry's seventeenth list, version 0.48; four lanes on briefs, cut off by the account's session and weekly limits and resumed from their transcripts). **PostHog boards follow dashboard filters**: PostHog applies a dashboard filter to a HogQL tile only through a `{filters}` placeholder in its WHERE; `posthog_boards.scoped()` adds it to every `FROM events ... WHERE` (subqueries too; true with no filter), so filtering any board by the person property `player_name` shows one player (how-to: `analytics/howto/01_one_players_data.md`; Garry's analytics how-tos live in `analytics/howto/`). **Heartseeker** (`content/mutations/heartseeker`, Ironwood's hero mutation on the Spear/pike): `params.crit_stroke {every 4, reach_mult 1.2, color, core}`; `Thruster` counts one stroke per `_fire`, the 4th forces a crit on every hit (`EnemyManager.HIT_CRIT` flag, the hero's crit_damage) and reaches x1.2 (Wide Sweep: the sweep; Thunder Lance: the thrust half); the tip glows by `glow_for` (0.17/0.33/0.5, full red on the 4th; `Blade/LookCrit` with `TipRed`/`TipGlow` in the pike and Thunder Lance scenes), the crit thrust draws a red lance, a red ring, sparks (`Fx.crit_thrust`) and a camera kick, red streak/crescent drawn see-through (additive red read pale on the sand). **Solenne's favourite is the Molotov** (level 2; `CardPool.offer_weapons` offers the run hero's favourite weapon whatever its quest) and her hero mutation **Sun Cocktail** (`params.land_blast {damage_frac 1.5, radius_frac 0.9, knockback 2.4, look "sun"}`, `params.tint`, `params.halo`): `Lobber.land_blast` from `ProjectileManager._explode`, a sunburst halo and gold motes on every bottle in flight, `Fx.sun_puff` + a gold race ring + a scorch at the landing. **Pocket Watch** (passive item, uncommon, 5 levels): player stats `powerup_duration` (+0.15 a level, `Run.powerup_seconds` on the ground power-ups' buff and shield branches of `Game.apply_pickup`; not structures, Pollen, Barrel Rush) and `powerup_chance` (+0.04 at levels 1, 3, 5; `WaveDirector.powerup_chance_mult` on the per-kill chance); RunAnalytics records both. **Pierce drop-off** (`params.pierce_falloff {step 0.8, floor 0.4, first_mult}` on tommy_gun, revolver, boomstick, pike, turret_buddy (inert: it never pierces) and the evolutions Chicago Typewriter, Golden Revolver, Thunder Lance, Iron Bastion): the n-th creature a pierce >= 1 shot (or a thrust line, ranked along the blade: `Thruster._thrust_ranks`) hits takes x first_mult x max(step^(n-1), floor) (`ProjectileManager.falloff_factor/weapon_falloff`, `extra.pn`; ricochets and bounces are new shots); `Settings.pierce_falloff` (default on; Settings' Debug panel `PierceFalloff`, the developer menu's `PierceFalloffRow`; off = the old numbers); TextGen `pierce_falloff_words` while on. **Spit Cactus**: `ranged.land_only` (no hit in flight; the splash where it lands, a red ring there for the whole flight: `landing_of`, `_land_ring`), `projectile_speed` 5.4, `ranged.trail` and `ranged.pulse` (beads and a halo in the trail MultiMesh, `HALO_MAX` 48), read by `ProjectileManager._creature_look` for any lobber (the ranged training dummies too). **Surveys**: run rules from a tag in the survey's PostHog name (`Analytics.survey_rule/survey_title`, `pick_survey`): `[after N]` first at the N-th counted run (a run of at least SURVEY_MIN_RUN 60 s) then every SURVEY_EVERY 3 until answered, `[run N]` only at the N-th counted run (goes first, ignores the once-a-session rule), untagged = pass 59's rule; `Save.survey_state()` gains `counted` (lifetime, kept on wipe; an old save starts at `totals.runs`), `shown`, `dismissed`, `armed`; survey events carry `counted_runs`; the developer menu has a **Surveys** block (readout; Reset surveys with a confirm, Fetch now, Show a survey now, Next run asks, +1 counted run; touch_audit `_dev_surveys`); its row labels wrap (one long label had pushed every value off the right edge on a phone); how-to `analytics/howto/02_surveys.md` (rename the NPS "... [after 3]", create "Fifth run check-in [run 5]"). **Favourites on the cards**: a card for the run hero's favourite (weapon, line or passive item; never evolutions) carries a brass heart on the plate's corner (`WCard.add_heart`) and a quiet FAVOURITE beside the tag pill (`WCard.favourite_word`); a new favourite is offered at its bonus level with that level's words (`CardPool.first_weapon_level`, `preview_weapon` folds an effects bonus; `WItem.favourite_line` "His favourite: found at level 2." / "+20% area of effect."), on level-ups, the chest's landing, the shop ("LV 2") and the Stranger (which now gives the favourite's bonus too); `apply_favourite` never lowers a level. **Red Canyon's stages 2 and 3** (Garry hand-made stage 1 in the Level Editor; `pass62_pc_test` pins everything that acts before 430 s, incl. his edits): written in his style from his stage 1: rows r19-r52 (r10/r11 kept for the hell rows), two cap rushes a stage to 150 with ring / in-front rows (9:00 armadillo wall, 12:00 werewolf ring, 16:05 ember knight ring, 19:10 werewolf ring + hellhounds) and quiet stretches, swarms, fewer introductions (stage 1 nine, stage 2 five: the Dwarf Shooter `buckshot_dwarf` at 7:12, fire ants, armadillos, mummies, the hammer giant; stage 3 four: imps, horned toads, hellhounds, the dust shaman), every non-melee creature in packs of 1-2 with `max_alive`; stage 2 and 3 rows start at 431 / 861 (a boss reads the frozen clock, so the King and the Gila keep their stage's values). Difficulty: `damage_curve` in points mode `[[0,1],[430,1],[431,0.65],[860,0.65],[861,0.55],[1290,0.6]]` (stage 1 exactly 1; a stage-2 rocket is about half of a half-Mirror hero's health), HP by each row's `stats.hp_mult` on a ramp (7:11 x0.38 -> 12:00 x2.0 -> 14:20 x2.1; 14:21 x0.55 -> 19:04 x2.0 -> 21:30 x2.1; hammer giants x1.0 / x0.8 HP and x0.7 damage; the Elite events at 645 / 1075 x1.3 / x1.9 HP), because `stage_mults` also set coin value and boss HP and the hp_curve stays in formula mode (points would shift stage 1 by up to 1.2 %); targets: stage 2 clearable with half the Mirror, stage 3 with the full one. `game/tools/difficulty_probe.gd` is the headless probe (fixed builds b1/b2/b3, a Mirror at rank 0/3/6, a clock jump, a kiting autopilot, HP lost a minute net of healing per source; it sandboxes the Save). Thirst rank 1 already reaches the 4 % lifesteal cap, so the Mirror's sustain is front-loaded. Tests `pass62_hm` (16), `pass62_it` (20), `pass62_ux` (20), `pass62_pc` (10); re-pinned on purpose: pass26, pass47_rules, pass48_projectiles, pass53_weapons_a/b, pass54_weapons, pass54_waves, pass45_pacing, pass332, pass46_pacing.

Pass 63 (2026-10-10, version 0.49; Garry: "each Upgrade is a choice ... and that choice stays. They shouldn't be able to just switch"): **the Upgrade board's ranks are choices that stay**: `Save.talent_picks(id)` (the forms rank by rank, saved as `{"picks": [0, 1, 0], "rank", "form"}`; an old `{form, rank}` reads as that form `rank` times), `talent_count(id, form)`, `talent_rank` = the picks' size, `talent_form` = the last pick (analytics, old callers), `buy_talent(def, form)`; `set_talent_form` is gone. `Run.hero_sheet` folds each form's ranks on their own (`effects_for(form, count)`). `HomesteadScreen`: `rank_bar(def, picks, px, gap)` (each bought slot the icon of its own form), the pair "[icon] or [icon]" beside the name while a rank is left, the tile's line the held effects summed (`held_effects`), the summary a chip a form held (`Chip_<talent>_<form>`), the sheet's form switch replaced by one offer a form (`Offer0/1`: icon, name, words, "N owned", its own `Buy0/1` button) under "Rank N: choose one. It stays; Take it all back is the only way to choose again."; `run_start`'s `talent_forms` carries each talent's picks. Tests `pass63_mirror` (5); re-pinned pass25, pass61_mr.

Pass 64 (2026-10-10/11, Garry's list, version 0.50; three lanes on briefs, stopped once by a billing error and resumed). **The Strongbox returns**: `content/structures/gold_bank` `params.respawn {min 30, max 60}`: after a box flies away, `StructureManager` counts 30-60 s of unpaused run (`return_t`, `_tick_return`, `_on_flown`) and `bring_back()` floats a new one down from 18 m over 4.5 s + a 0.6 s settle (`_descend`, `descend_roll`, `_land`: bounce, sand puff, ring flash; unusable until it stands) at a spot from `find_spot()` (the start placement's `start_spot_ok()` rules + 0.3-0.86 of the arena, 20 m from the hero, 4 m from sign posts, 2.5 m from barrels, outside painting cover bands; relaxing, retry in 5 s); one at a time; signs keep their start targets (the used box's arm goes blank, nothing points at a returned box); an off-screen landing toasts "A STRONGBOX DRIFTS DOWN"; every structure now keeps 3 m from the lake. **The spawn beam**: the hero lands on `map.height_at` (the start spot sat 0.5 m up, so he dropped and stretched), the fall is smootherstep (`spawn_ease`), a landing squash (`Player.land_settle/land_squash`, `LAND_SQUASH` 0.09), shake 0.3, `quiet_invuln` (no blink), `Player.face_camera()` keeps the front view until he first moves; a press, drag or key after `SPAWN_HURRY_AFTER` 0.2 s speeds the rest x3 (`SPAWN_HURRY`, eased in at `SPAWN_HURRY_RAMP` 14/s) instead of skipping, and a finger still down at the landing becomes the stick (`_spawn_hand_over_finger`); touch_audit `_spawn_skip` checks it. **Rust** reads as old rust on metal (`rust.json` rust_color #AC6230, pit_color #6B4A30, pits 0.35, rim 0.1, `steel` 0.7, flakes 6 in light `flake_colors`; Saw Halo patina 0.3/0.15/0.06 + steel 1.0; `rust_blade.gdshader` `steel`, `PIT_FROM` 0.9). **Sound** (Garry missed the hype in the jingles): the AI server's ComfyUI runs Stable Audio 3 (`tools/comfy_audio.py`: CheckpointLoaderSimple `stable_audio_3_medium` + CLIPLoader `t5gemma_b_b_ul2` type stable_audio -> ConditioningStableAudio -> EmptyLatentAudio -> KSampler 8 steps cfg 1.0 lcm/simple -> VAEDecodeAudio -> TrimAudioDuration -> GameAudioSaveWAV; workflows `tools/comfy_workflows/06_stable_audio_3_*.json`; the small sfx model returns NaN or noise on this server, unused); `tools/ai_sfx.py` engine `sa3` + a `HYPE` table of 32 UI / reward / pickup ids (casino and western: slot-reel ticks, a jackpot payout on the chest landing, a mega-win on the evolution reveal, a cash-register ka-ching on buys and the Strongbox's last coin `st_deposit`, coin clinks, a payout hopper on the magnet, glassy gem pings, soft mobile pops for taps), kinds pop/click/casino/jingle/bling/coin scored by `score_hype`; new ids `ui_stamp`, `ui_stage_clear` (PortalDialog), `st_deposit` (CoinStream); world sounds keep pass 60's; **music** from `tools/ai_music.py` (six candidates a track, tempo found from the beats, a whole-bar loop crossfaded at the seam, -17 dBFS, `content/sounds/music/<id>.wav`): mu_title lounge western 100 BPM, mu_run_1 galloping electronic + twangy riff 128, mu_run_2 surf guitar + mariachi trumpets 136, mu_run_3 hell minor 145, mu_boss showdown 150, mu_results victory groove 110; `Audio.gd` plays one track at a time with a 1.5 s crossfade (`music_stage(s)` from `WaveDirector.stage_started`, `music_boss(on, id)` from the boss signals; before this only stage 1's music ever played and mu_boss never did); review page `docs/sfx_review.html` (+ zip in Drive as `sfx_review_v0.50.zip`); old files in `tools/dl/backup/sfx_pass63/`. **Difficulty** (Garry: stage 2 with a quarter of the Upgrade board, stage 3 with half): `damage_curve` `[[0,1],[430,1],[431,0.5],[860,0.5],[861,0.39],[1290,0.43]]`, stage-2 rows' and events' `hp_mult` x0.72 (ramp 0.27 -> 1.46, Elite 0.94), stage-3 x0.70 (ramp 0.39 -> 1.42, hell rows included, Elite 1.33), giants x0.72 / x0.56 HP and x0.7 / x0.55 damage; stage 1 untouched; `difficulty_probe.gd` writes `picks`, takes fractional `mirror=1.5` (talents 2 and 1 ranks by turns) and `spite=0|1`, and matches the average of a Thirst board and a Thorns board (Thirst rank 1 hides most of the board's worth); the probe is noisy (+-0.15), so this is a starting point. Tests `pass64_pl` (13), `pass64_sn` (12), `pass64_df` (6); re-pinned pass60_sfx, pass61_wp2.

Pass 65 (2026-10-10, version 0.51, one lane). **Shadows on slopes**: `EnemyManager.drape(xf, height_fn, extent)` tilts a blob to the plane through 5 height samples (`MapBase.ground_basis`) and lifts it past the ground's curvature + `SHADOW_LIFT` 0.03 (creatures through `shadow_xform`, the hero through `Game._drape_hero_shadow`, `Player.shadow_scale`; his shadow stays on the sand while he jumps); +0.1-0.3 ms at late-game crowds. **Sounds** from `tools/synth_sfx.py` (numpy; Garry's references `_REFERENCES/audio/AudioClip/sfx_gem.wav` / `sfx_enemyHit.wav` are Vampire Survivors rips, only analysed): gem dings `pk_gem_s` G6 220 ms, `pk_gem_m` E6+B6 420 ms, `pk_gem_l` C6 with a second strike 800 ms, rising on quick repeats (soundmap `chain_step` 0.5/0.5/1.0 semitones in a 0.3 s window, at most 10; `Audio.chain_pitch`; pitch_spread lowered); `pl_hurt` a chiptune falling square blip with a crunch, `min_gap` 0.25 s (`Audio.play`); the slot machine `ui_slot_start` / `ui_slot_spin` (loop, `Audio.play_loop/set_loop_pitch/stop_loop`) / `ui_slot_stop`, run by `ui/wanted/WSlotSound.gd` (begin, feed pitch 1.15 -> 0.7 as the strip slows, land, cancel) in `ChestScreen` and `WWeaponReel`; `ai_sfx.py`'s `SYNTH` set keeps these 7 ids out of its rebinding. Tests `pass65_test` (10); re-pinned pass60_sfx, pass64_sn.

Pass 66 (2026-10-11, version 0.52, six lanes S/J/P/V/G/B + the lead). **The asset system in the Level Editor** (Garry: "It's time for me to start being able to create art assets for both Heroes, Enemies and Items on my own ... a form or a template ... the local AI model ... previews ... a jobs queue ... don't break the LevelEditor"). Interview answers that shaped it: real content folders at once (heroes and items hidden by default); every finished look lands in the JSON as a selectable look and the editor and the arena cope with ~50 of them (a per-look `shelved` flag); honest reference roles (identity / style / pose-and-anatomy, follow loosely / closely / copy exactly) mapped to the wordings that worked, no fake strength slider; the driver library plus new drivers from an uploaded FBX/GLB (the preferred format stated), a 3D reference usable for the icon render, the look reference and the animation; items = weapons with their mutations and evolutions, lines, passive items; hero `availability | price | currency_type` written and shown, not wired (the purchase loop is parked at Garry's word: memory `88fits-hero-purchase-parked`); a "Test in game" button; previews = every strip animated by animation and facing; count-pinning tests → shape rules; a new enemy from a template with the comparison numbers; new items available at their rarity's weight; a weapon without a path gets three template mutations and a template evolution (lead's call: hidden until filled, since the shape rule and the offers need a complete path); any brain/attack combination with an "untested" warning; elites and bosses edited with their attack scripts drawn. Design: a 7-sweep exploration, three drafts (data/runner, UX, pipeline), a synthesis and a critique (`tools/dl/p66/`), settled in `INTERFACES.md`. **Built**: `tools/locks.py` + `tools/godot.sh` (repo-wide mkdir locks `tools/dl/locks/comfy.lock|godot.lock` with owner.json, pid-alive reclaim, the PC save kept aside; comfy.py takes the comfy lock for its whole process, lazily, reentrant, `LOCK_HELD_COMFY` for children); `content_io.py` (one-key-per-line writes grown to multi-line blocks via raw_decode spans, the file's own indent unit, parse-back, `set_variant_entry`, never a silent re-dump); `vocab.py` (every list the forms offer, checked against EnemyManager/StatSheet/TextGen/W.gd by regex); server.py routes for content (`/api/content/<kind>[/<id>/save|variant|retire|availability|delete|make_path|look|look/<code>]`, `/api/heroes`, `/api/items`, `/api/vocab`, `/api/methods`, `/api/drivers`, `/api/refs`, `/api/upload` streamed, `/api/test_launch`, `/dl/`, `/icon` and `/sprite` for every kind, `/art/wanted`, `/sound`, `/api/jobs*`, `/api/jobs/specs`, `/api/jobs/<id>/merge`, `/api/locks/<name>/release`) and the hooks jobs.py writes through; `jobs.py` (queue.json with rev, three lanes comfy/godot/local, 13 job kinds with SPECS, the state machine queued|running|waiting|done|failed|interrupted|cancelled, progress from the tools' printed lines plus the cache files, cancel = taskkill /T + /interrupt + /queue clear, edit in every state but running with the recipe written through, requeue with re-rolls (stills copied aside, clip folders moved), picks for gen_ctl's side/view and the front-from-picture, install, coalesced imports, recover(), launch = the editor binary into the arena with `arena/spawn_enemy/variant/count/look`); `asset_job.py` (the subprocess runner that sets argv before importing the tool and calls `gen_art.process` / `gen_ctl.main` / the candidate scripts; `--dry-run` records the prompts); the sidecar `ASSET_JOB_SIDECAR` in gen_art.py/gen_ctl.py (the tool never opens the content JSON; `result.json` entry + info with `clip_kind`, `recipe_ran`, `qa_online`; the 8-way key fix; the item icon backed up before overwriting); `gen_badge_cands.py`; `gen_title_heroes` reading `title_pose|holds|camera|extra_ref`; `blender_ref.py` (probe / icon / views of any FBX/GLB/OBJ) and `blender_depth_drivers.py` (the beetle method for any rigged model's own clip, proven byte-close against `beetle_walk_amp`); `pose_driver.py` `src= rigmap= probe=`; `methods.json` (17 methods with timings, weaknesses, examples and recipe fields; 13 wordings; the 3D insert text); the page: `assets.js` (documents with undo/dirty/save per asset, 409 conflicts, routing of Ctrl+S/Z/Y), `assets_fields.js` (enemy 93 rows, hero 69, weapon 51, passive 23, mutation 20; 124 rules; attacks, blocks, params keys), `assets_model.js` (strip maths, codes, TextGen ports, telegraph geometry, the Revolver TTK, pace), `enemies.js` (compare panel, brain blocks, the attack script editor with telegraph SVGs and the sequence line), `heroes.js`, `items.js` (grouped cards, path strip, quest drawer, band gauge), `strip_player.js` (canvas player, 2/8 directions, Player.gd's fallback chain, mirror rules, zoom 1/2/4 + modal, sand at ~94 px/m, cap 12 animating, LRU 16), `looks.js` (24 a page, filters, bulk, approve/shelve/remove/default), `jobs.js` (polling 2 s, badge, cards per state, the job form with method cards, reference rows, the driver picker, the 3D probe, "Show the words"), `instructions.js` sections, `docs/assets_schema.md`; Godot: `Game.gd` launch keys, `JsonContent`/`CharacterDef`/`EnemyDef` `shelved` + `availability/price/currency_type` + `variant_codes(include_shelved)`, `ArenaPanel` chips in HFlowContainers folding past 6 creatures with a Shelved toggle, `gen_placeholders.gd -- only=`, `pass66_gd_test` (15) and `pass66_shape_test` (14), the count pins re-pinned (pass26's hero loop gone), BALANCING §13. **Lead's integration**: the two routes the cards needed (`merge`, `locks release`), the create dialog's picker face, the record redraw after a landing, approve/note/recipe queueing an import, a real end-to-end in the page (Test Beast from the Lesser Scorpion → register job 31 s → a `creature_proc` look TB-A landed as one entry in place with `fresh: true` → import → the look grid played it → Make default, Approve → Test in game opened the arena with three of them → Cancel closed it → Delete). Numbers: selftest 17,023 checks (14,994 before), gdUnit 1308 tests, a whole-project `--import` with nothing new 11 s. **Lessons**: the Windows Godot binary writes nothing to a redirected console under the wrapper (lane G captured through `locks.run_godot`); a bash heredoc with a long quoted text breaks the Bash tool (write the file, then append); `Forms.iconSelect` never redraws its own face (its callers re-render), so a dialog that keeps state must redraw it; a page record fetched before an import finished shows "not imported" until refreshed: refresh and redraw the document on every finished job for its target.
**Pass 66 follow-ups (2026-10-11, Garry's first day with the asset system).** Model settings on every painting job (the
painter Flux.2 Klein or dev, the passes, the guidance, Turbo), apart from the asset settings (`MODEL_FIELDS` in jobs.py ->
the `ART_*` env -> `gen_art.MODEL` / `paint()`, also the flags `--model= --steps= --guidance= --no-turbo`); every job keeps
the ComfyUI workflows it ran, linked from its card, and the form links the template workflows; a new look paints its own
stills (`_seed_recipe`: the stills slug and the base's words; Garry's ARM-A had come out as ARM-0 because an empty recipe
reused the cached base stills); the Art Guide (`docs/art_guide.html`). Then three asks. The asset being edited pinned at
the top: the pane's sticky header carries the look's icon and a larger name. "Quite a few Looks are missing the art
prompt": no data was lost; a recipe keeps only what differs from the creature's own words (gen_art does
`d.update(recipe)`), and the typed editor showed the own keys only, so an inherited word looked like an empty box. The
recipe editor now shows every field with the value that applies and its source (own / inherited / the method's default),
says when a look has no recipe recorded at all (the base strips, the recolours RG-B/RR-B, Garry's ARM-A from the
empty-recipe job), lists keys the method's form has no row for (gen_ant's `body`, a recolour's `tint_of`), and the
job form greys the inherited words in the same way; the look cards and the stage facts name the method, the own keys
and the words. Duplicate… on every card: the job form with the look's recipe, words and painter copied, the next free
code, the stills slug cleared (new paintings, so the Model settings apply) with a box to reuse the source's paintings
(only the clips are redone). Every look job records its painter in `variants[CODE].recipe.painter` (`_painter_of`;
shown on the card, the stage and the recipe editor; Re-roll and Duplicate start the form from it; `gen_art.apply_painter`
reads it on a hand run that names no painter). An explicit `"stills": ""` now means the creature's own paintings
(only an absent key is seeded). Lesson: a sparse override record needs its effective values shown with their source,
or every empty box reads as lost data. Later the same day: the tab panels (the `:has` rule for the pinned header
outranked `[hidden]`, so the Enemies panel stayed open beside the next tab: `:not([hidden])` and a `!important` on
`[hidden]`); and "running a Mummy job I don't see a link to the ComfyUI on the job itself ... I want to click a link
and open the ComfyUI page with the workflow": the stock frontend (1.48) has no such link (only `?template=` and
`?share=`, found by reading its chunks), so every workflow a job runs is now also saved into the page's own Workflows
sidebar (`workflows/88fits/<id>_<CODE>/`, the user-data API) and a tiny web extension on the server, `88fits_open`
(`tools/comfy_ext`, `python tools/comfy.py --install-ext`), opens one from `?open=<path>`; the card harvests its
outputs every five seconds while it runs (the links and the cached stills and clips appear as they land), "Send to
ComfyUI" pushes the workflows of older jobs, the form's template workflows go to `88fits/templates/`, and the status
record says whether the extension is there. Found on the way: two `level_editor.cmd` windows were running (ports 8787
and 8788), each with its own picture of `queue.json` and each writing the whole file, and a second server's `recover()`
would kill the first one's running job; so the first editor now claims the queue (`locks` gained a third name, `jobs`;
`jobs.claim_queue` in `init`), a later one runs read-only (follows the file, refuses every change, a banner on the
Jobs tab, `status.readonly`). An adversarial review (33 agents, 13 confirmed findings) then hardened it: on Windows a
read-only editor's poll holding queue.json open for a millisecond made the claimant's `os.replace` fail, which could end
a lane thread or orphan a render (the save retries, `_take_next` sits inside the worker's try, a failed read keeps the
old picture); a phantom `jobs` lock (an editor closed by its window, its pid reused) is told from a live editor by the
port in the lock's note and released; a new editor never kills a job an older editor still runs (`server_pid` on every
taken job, `_foreign_runner`: it goes read-only instead); `--no-jobs` is view-only (it used to write the queue from an
empty picture); every job's sidebar copies sit in their own sub-folder (a re-roll overwrote the earlier job's); failed
and cancelled cards show their workflows; "Send to ComfyUI" reports what failed; the extension no longer loads inside
the awaited `setup` hook (the page's own init loaded another graph on top) but waits for the page's active workflow
and opens the saved file through the workflow store; `--install-ext` waits for the server's own queue to empty. Garry then saw the link "just open ComfyUI": the saved graphs carry no view (no `extra.ds`), so a canvas panned far away in a long-lived browser showed an empty page although the tab had changed; the extension now fits the view to the graph after loading (the `Comfy.Canvas.FitView` command), brings its tab back if a late restore took it, and says what it did in a toast; the Art Guide got a What-changed callout, a Looks section (recipe sources, Duplicate, the painter) and a Jobs section (the ComfyUI links, one editor at a time).

**Pass 67 (2026-10-11/12, v0.53): Polish 2.** Garry's list with design freedom "inspired by MegaBonk": darker, richer
weapon materials; the Hammer Giant at a third of its knockback with a stat for it; a quieter chest; the gem pickups as a
tune; Buck ("the gazelle guy") back and more powerful with his back run repainted; a new escape hero, a basketball
player. Run as a multi-agent pass: six readers mapped the subsystems (tools/dl/p67/map_*.json), three designers and a
judge wrote the hero kits (tools/dl/p67/design_spec.json, scored on fun, phone legibility, codebase fit, shape rules,
balance and buildability), then six implementation lanes in two waves under RULES.md / INTERFACES.md (file ownership,
shared names, a landing order; the second wave stopped on the old model's spend limit and resumed on Opus from status
files). **Weapons** (BALANCING 14.30): the Blender scripts had typed sRGB numbers into linear colour and Red Canyon's warm
light pulls every lit mesh toward the sand while the painted sprites are unshaded, so `WeaponBehavior.grade_materials`
grades every lit, opaque, untextured StandardMaterial3D of a weapon's visual in HSV (one copy per material, value x 0.78,
saturation x 1.3, emission alike) from the map's new `weapon_grade` block (glow 0.3), `params.grade` per weapon, the title
stage and the warm-up mirrored; the Level Editor's map Save now keeps top-level keys the page does not know.
**Knockback** (14.1): `knockback_resist` (creature JSON, 0..1) is the share of every hero-side shove a creature shrugs off
(hits, throws, the Lasso pull, Ram; the boss factor composes); the Hammer Giant 0.67; editor rows, card stat, compare row.
**Sounds** (§12): the chest's landing jingle -9 dB and slot stop -10 dB, the evolution's mega-win once (on TAKE), the lid's
crack no longer repeats the open sound, TAKE clacks a poker chip instead of the purchase ka-ching; the gem tune:
`Audio.chain_pitch` reads `ladder` (semitone offsets), `chain_group`, `chain_min_ms`, `chain_end`, and the three gem rows
share one counter and climb a pentatonic rooted in each ding's note (all in C major, window 0.6 s, no jitter: the pass-65
quarter-tone slide was inaudible under ±0.5 semitone jitter and three counters); five placeholder rows for the ball;
`ai_sfx.py --volume` alone no longer falls through into a full generate run. **Buck** (14.2-14.11), un-hidden as the
seventh hero (order 7): momentum {10 s, +80% speed, +60% damage, +20% evade (new `evade_bonus`), `hit_loss` 0.5: a landed
hit takes half the charge, not all}, Full Tilt +1% speed a level beside the flat -15% start, Ram's dead number fixed (12 +
2 a level + 3 x thorns, from `from` 0.99), the new perk Overdrive (a +5% damage gear every 5 s at full charge, five at
most, gone on a landed hit; damage, never cooldown, because a cooldown under the Tommy Gun's burst cuts its tail), a bug
fixed on the way (the sheet's quarter-second sync could stall the charge at 0.98, under Ram's 0.99), and a hero gauge on
the HUD (`Run.hero_gauge()`: MOMENTUM with four notches for him, HEAT for Fadeaway). His back run is look BUC-B
(hero_fit on `run_spread`: the arms swing beside the hips; BUC-C on `run_occ` bunched the hands again and is shelved).
**Fadeaway** (14.12-14.29), order 6, made in the Level Editor from the Drifter's template: Footwork +0.5% evade a level,
favourite Evade (at level 2), the Basketball (`tools/blender_basketball.py`, a vertex-coloured GLB: the visual gives it a
material that reads the colours, the glTF import leaves them off) with code added to ProjectileManager/ProjectileEmitter:
`amount_mode` "bounces" (amount and Multishot add hops, never balls), `return_on_hit` (a spent ball turns home; none is
ever lost), `return_pierce`, `ricochet_any.reach`, the rebound made a rule (the centre-to-centre touch test had made it
chance), the catch (`Game.ball_caught` -> `on_caught`: 35% of the cooldown back, +1 Heat for a scoring trip, +5% damage a
stack to 10, cooled by a landed hit), Free Throw (an evaded hit throws a ball), Slam Dunk (Heat kept, a dunk at full Heat);
his path On Fire / Full Court Press / Rebound; the perks Timeout (a whistle pickup 3 m to the emptier side every 20 s, one
at a time: stepping on it leaps him clear, 0.8 s untouchable, the crowd left slowed) and Buzzer Beater (every 24 s, 5 s
of -35% cooldown and +2 amount: a reusable `periodic_buff` special); look FAD-B (hero_pose5, back views on run_spread; its
back flinch repainted, it had faced the viewer), FAD-A (the placeholder strip) shelved, the badge, the title cut-out with
the ball and every icon painted by the AI and picked by eye. Probe at an empty Mirror (seed 11, net max HP lost a minute):
late stage 1 Fadeaway 0.79, Calavera 0.53, Buck 0.36; late stage 3 Fadeaway 0.15, Calavera 0.33, Buck 0.50 (Fadeaway
deals the most there, 10.7k a second): fragile early, tanky late, as an evade hero should be; no retune. Tests: pass67_grade
(6), pass67_kb (11), pass67_sounds (11), pass67_ball (12), pass67_buck (14), pass67_fadeaway (9); re-pins in pass334,
pass26, pass46_passives, pass55_hv, pass61_hr, pass66_shape, pass53_weapons_b, pass61_wp1, the editor's selftest_S/P.
BALANCING §14 holds 33 named rules. **Lessons**: a global like Run.heat leaks across the rounds of a looped test (reset
it per round); a sync that skips small steps needs its end state forced or a threshold just under the top becomes a coin
toss; a GLB's vertex colours need a material that reads them; agents stopped by a spend limit resume cleanly when each
keeps a status file of what is in the tree. The ship run then caught a pass-58 flake: EnemyManager.ring_spots let the end spots of a wall-clipped ring slide past the arc (its random generator is seeded fresh every run), and `_inside` pulled one in a few millimetres under the 16 m ring (pass58_wv_test, 15.987 m); pass 60 had clamped the slide inside the arc in `_spots_on` only, and the same clamp now sits on the main path.

**Pass 68 (2026-10-12, v0.54): looks, drafts and candidates in the Level Editor.** Garry's list: the hero's title cut-out
and icon candidates should already know the hero (he typed only the action and got unrelated art) and take a reference
picture; every new look must come with at least 3 icon and cut-out candidates; Duplicate must not start painting; a
duplicate on Flux.2 dev at 32 steps (MAM-C) had come out exactly like its Klein source (MAM-B); the upcoming jobs belong at
the top of the Jobs tab. Two readers (tools/dl/p68/map_*.json) found the causes on disk: a hero look read the hero's
cached paintings (`<id>_<view>`), so MAM-C painted no still and its strip was byte-identical (md5 167fef65...); painting
seeds came from the id alone, so two new looks with the same words were clones (DM-E and DM-F); the job form's re-roll
choices and its 2D/3D reference rows reached no tool (MAM-C's typed reference too); `_seed_recipe` wrote a letter slug into
EXISTING looks on any re-roll; the recorded painter said dev for Klein's paintings; icon candidates sent only the typed
words and no picture ("mamy icon" painted four women in aprons) and their pick wrote a square icon over a hero's round
badge; badge and title words never named the hero and their form fields were dropped. Built in four lanes (contract
tools/dl/p68/INTERFACES.md): **tools** (gen_art keys a hero look's stills `<id>_<slug>_<view>` and moves every seed by
104729 x `seed_offset`, names the real painter; gen_badge_cands, gen_title_heroes and gen_icon_cands take the character,
the action or pose, a reference picture and a look, keep candidates per job and repaint on a re-run, pick into the look's
own files and entry), **server** (a new look gets its own slug and seed offset, an existing look keeps `stills: ""`; the
re-roll modes are real and refuse what cannot work; the honest painter at landing; `candidate_defaults` and
`GET /api/jobs/defaults` fill and show every candidate input, the character cut of its pose clause by `appearance_of`;
a candidate job waits while its look is still painting its reference; a pick lands in `variants[CODE].icon` (marked
`icon_picked`, kept by later runs) or `.title`), **page** (Duplicate makes a draft with a Generate… button and starts
nothing; the candidate forms open filled and editable with a picture field; a new look requires at least 3 candidates of
each kind; the reference rows show only where a tool reads them; Up next first in the Jobs tab, numbered per lane) and
**game** (a hero is drawn in the look he is played in: his badge follows it everywhere and the Painted title shows the
look's own cut-out; the Live title, the default, has no cut-out). The lead then fixed four gaps the lanes flagged
(re-rolled stills re-walk their clips, candidates wait for their look, a picked icon survives a re-roll, a forced repaint
is spent once done), and an adversarial review (three lenses, a skeptic each) confirmed 14 more, all fixed: a removed
look's code was handed out again with its cached pictures (next codes now skip a code whose caches remain), an edited
re-roll job re-applied its re-roll, creature_ctl and recolour runs painted over a picked icon, a base look's candidates
took the creature's old front as their reference, a done job's progress was wiped, title candidates were not per job,
the held jobs' numbering, a base code picked into a look file, a cleared field could not be refilled, a redraw erased
the note being typed, and two test faults (the new title test assumed Astro has one look; two of its checks passed for
the wrong reason). A real badge job for Mamy (Klein, one seed, her description, her front still) painted her
unmistakably: the beret with the heart tip, the bob, the star, the magenta scarf and gloves, mock surprise. Lessons: a
cache keyed by name needs every new thing to get a new name (a look, a seed, a code once freed); a form field that the
server drops is worse than no field.
While the pass shipped, Garry retuned Red Canyon's ATK x curve in the Level Editor (stage 1 flat at 1.21 instead of
1; stage 2 from 1.44 to 1.39 and stage 3 from 1.54 to 1.58, where pass 64 had 0.5 and 0.39 to 0.43). Five tests pinned
the old numbers (pass54_waves, pass62_pc, pass64_df: stage 1 at 1, later stages softer than pass 62); his numbers were
kept and the tests now read the map file and ask only for shapes any curve of his has: a positive multiplier under 10
and each boss second on its own stage's side of the step (the King's 430 against 429, the Gila's 860 against 859, to
0.005 since his stage 2 slopes). Pass 64's promise (stage 2 with a quarter of the board, stage 3 with half) was tuned
on the old curve and is his to keep or drop.

**Pass 69 (2026-10-12, v0.55): Garry's big list, inspired by Megabonk.** Nine lanes from one contract (tools/dl/p69/INTERFACES.md: every id, number and file owner) and the lead's integration: the basketball's Heat moved from the HUD onto the ball, Full Court Press hidden and Alley-Oop in its slot, a black Slam Dunk; two new weapons (the Salt, the Frisbee) with three path mutations, a hero mutation and an evolution each; five new passive items and the Magnet reworked into random EXP pulls; special enemies three times rarer and far stronger with a glow Garry colours per creature, and one special Red Goblin at 2:00; the spawn beam fading out; Buck became Jeżyk (a bald blue Slav in a tracksuit, Salt and Frisbee), Mamy became May (Trigger Happy, the inflatable decoy); heroes are bought with gold after an unlock quest, shown as black silhouettes in a new hero drawer on the title; new looks for Fadeaway, Jeżyk (three runs) and May through the Level Editor's queue; the Level Editor edits all of it, with a Pass 69 how-to section.

Lane ART (pass 69). **Icons**, painted as candidate sets with Flux.2 Klein (`tools/gen_icon_cands.py`, set 69 in
`tools/dl/icons69/`, 4 seeds each, finished and checked at card and HUD size on the sand before installing; the review
sheet `tools/dl/p69/art/icons_review.png`): the Basketball again from words with the classic seams (one belt seam, one
crossing seam, two bowed side seams; the model render `basketball_ref.png` has beach-ball meridians, which is why the
pass-67 icon did not read as a basketball), Alley-Oop (a royal-blue ball throwing a red goblin skyward, the goblin as
big as the ball after the first set's was a speck at HUD size), Slam Dunk (a black ball with ember seams through the
hoop), Salt / Sea Salt / Hiwa Kai from lane SALT's shaker renders (white, pink, black salt with black crystals), Salt
Spill, Thing About Luck, Salt Flats, the Frisbee / Trick Shot (`frisbee_trick_shot`) / Poison Razors / Flying Saucer
from lane FRIS's disc renders (Poison Razors copies the joke of Garry's `frisbee_razors.jpg` without its text), Carry,
Counterpunch, Heavyweight, Snake Oil, Hot Springs, Last Stand (passives/last_stand: a cracked heart before a cold
stopwatch), the Magnet as an epic (a red magnet pulling purple, cyan and pink gems: the old purple one vanished on the
epic plate), Trigger Happy (the Tommy from `tommy_ref.png` firing with a pink heart) and Inflatable May. **Rebound**:
three designs as three Level Editor `icon_cands` jobs on `mutation/rebound` (a backboard bounce, a U-turn arrow round
the ball, a hand catching the returning ball); the arrow (B c3) installed through the editor's Install, the other two
installable from their job cards (`tools/dl/p69/keys_ART.md`). The hero unlock quests have icon slots the game never
shows; not painted. **The shoulder fault** Garry saw in the side runs and Fadeaway's sagging back run came from the
drivers, not the paintings: `pose_driver.py` takes the Mixamo Neck bone as OpenPose's neck, which sits above the
shoulder line, so seen from 25 degrees above both shoulders hang under the neck (an inverted V from behind: sagging
shoulders) and, from the side, the far elbow rides up behind the back at neck height in the passing frames (painted as a
raised, hunched shoulder). New `tools/pose_shoulders.py` levels the shoulders toward the neck (`level`, `keep_tilt`) and
tucks the far arm in the side view's passing frames (`tuck`); `pose_driver.py` gained `amp=` (limbs swing wider),
`lean=` (spine forward) and `arms=back` (the dash). Drivers: run_side / run_side_t, run_spread_lvl, run_sprint(_lvl,
_f), run_dash(_lvl, _f). **Looks**, all through the Level Editor's queue (port 8787) with badge and title cut-out
candidate jobs each, every strip checked frame by frame in contact sheets: Fadeaway FAD-C (white shorts with purple and
gold stripes; side on run_side_t, back on run_spread_lvl; square shoulders from behind, no lump from the side) is his
played look now; Jeżyk BUC-D (jog), BUC-E (sprint: legs 1.35x wider, a 12-degree lean; the front views on a no-lean copy
because the lean hid his face) and BUC-F (the dash with the arms swept back) from a front painted off Garry's tracksuit
sheet (`front_from_picture`, 6 candidates, c0); May MAY-G on Flux.2 dev at 30 steps without Turbo (about 6.5 min a still,
2 h for the look; dev painted the three-quarter front facing left twice, so it was mirrored; Wan turned her white sleeve
stripes yellow in some frames, sent back by the recipe's `remap_hues`) is her played look now; May's inflatable
decoy (`content/characters/may/may_decoy.png`: a blown-up pool toy of her with mitten hands, seams and a valve; the first
set came out as May in latex in a T-pose). **Lessons**: every hero is painted on the blue screen unless the JSON names
`screen`, so a blue-skinned hero lost his head and hands to the keyer (BUC-D's first stills; fixed with the recipe's
`"screen": "green"`); a still re-roll on a look whose paintings another look shares forks them to a new slug (BUC-D went
to "d2" and BUC-E/F had to follow); a forward lean hides the face in the front run (front views on a no-lean copy); the
comfy lock has no fairness, so a hand-run test starves while the editor's queue runs (queue it as a re-roll instead);
Klein turned the black tracksuit olive on the green screen in the cheer twice (neutralised by `fix_cheer.py`).

**Lane BB (the basketball, Heat on the ball, no hero gauge).** The HUD's hero gauge (pass 67's MOMENTUM / HEAT bar under
the slots, `HUD._build_gauge` / `_tick_gauge` / `gauge_state`, `GAUGE_*`) and its words under the slots (MOMENTUM, RAM,
OVERDRIVE, HEAT; `HUD.heat_bonus`) are gone, and `Run.hero_gauge()` with them (Garry: "No UI indicators of any kind").
Heat shows on the ball instead (`params.heat_look {color, hot, glow_min, glow_max, seam_glow_max, pulse_hz, pulse,
surfaces, trail_from, trail_size, trail_life, flame_from, flame_size, halo, halo_from, halo_alpha}` on the basketball
and Slam Dunk; Alley-Oop sets `surfaces` "seams"): each ball is drawn in a heat copy of its kind with its seams split
off (`ProjectileManager.seam_kind`, `heat_kind`: materials duplicated, emission on) whose glow
`ProjectileEmitter._tick_heat_look` writes every frame from Run.heat / catch.heat_max (`heat_glow`): the seams glow like
cracks of lava up to `seam_glow_max`, the body only warms (`glow_max` 0.45), all of it beating at 3 Hz at the top on
the manager's clock (`heat_pulse`); `_heat_trail` drops orange beads and, past `flame_from`, flame tongues behind it;
past `halo_from` `_draw_heat_halos` draws a soft two-shell halo in a smooth MultiMesh of its own, only its far half
(cull front, so it never tints the ball); a drop in Heat puts the balls in flight out at once with a puff of steam
(`_fizzle`). The first cut (the whole ball glowing at 2.2 with a pale halo) washed the ball into a pale disc on the
captures: the glow moved into the seams. New look keys for vertex-coloured shots: `tint.body` (flat colour, vertex
colours off: `tint_material`'s new `vertex_colors`) and `tint.seams {color, emission, energy, below}`
(`ProjectileManager.seam_kind` splits the model's dark triangles into a surface of their own), so Alley-Oop's ball is
dark blue with black seams and Slam Dunk's black with ember seams. Full Court Press is hidden; **Alley-Oop**
(`content/mutations/alley_oop`, volume, rare) takes its slot: `params.launch {chance 0.15, height 3.5, air_time 0.9,
fall_damage_frac 1.0, sfx}` rolled by every ball hit a creature lives through (the hook in ProjectileManager's hit loop
calls `EnemyManager.try_launch`); a plain creature flies straight up on its own curve (`launch_curve`: up fast, a hang,
the drop), skips its brain, bite and attacks (`_tick_launch`, riding lift_mode 1 with an entry in `_launched` keyed by
its spawn serial), lands with a spray of sand and `w_grav_land` taking the fall through `damage()`; big game takes it at
once; a body killed up there falls (`_drop_launched_body`). **Slam Dunk** keeps the path and amplifies it in its
`final` (return x1.2 over Rebound's x1.0, launch 0.25 and x1.5, On Fire's burn x1.5 by a level-1 `fire_damage mul`),
black with glowing seams, its Heat in the seams only (`heat_look.surfaces` "seams"); it lost Full Court Press's +2
bounces. `TextGen.launch_words` puts the launch in the ball's words; `WeaponInstance._ball_hits` counts the falls. Tests `pass69_bb_test.gd`; re-pinned on purpose:
pass67_buck (the gauge tests became one no-gauge test), pass67_fadeaway (the path, Slam Dunk's tint).

**Pass 69, lane SALT: the Salt.** Garry: "New Weapon - Salt - Leaves a white half transparent patch in hero's wake,
which damages enemies as long as they are walking or standing in it ... a little salt shaker floats around the hero,
shaking occasionally to pour some more salt down on the floor". A new uncommon weapon in everyone's pool,
`content/weapons/salt` on a new behaviour primitive, `core/behaviors/SaltShaker.gd`: every cooldown it pours `amount`
patches back along the hero's way (the first 0.4 m behind his heels, then every `salt.spacing` 1.2 m along the path he
walked, round his feet when he stood still), each `salt.radius` 1.4 m x area for `duration` 4 s; every `salt.tick` 0.5 s
each creature standing in the salt takes one hit through the weapon's own path (overlapping patches never hit twice), at
most 40 patches lie (the oldest fades and stops working). `core/systems/SaltPatches.gd` keeps and draws them: one
MultiMesh of discs draped over the dunes by `core/shaders/salt_patch.gdshader` (the telegraphs' height grid, a lobed rim,
grains of salt in world space on a see-through bed, loose grains at the edge) and one of little hard crystals: two draw
calls whatever lies. The shaker is a real model, `tools/blender_salt.py` -> `art/props/salt_shaker.glb` (ribbed glass
Body, a Contents mesh the path tints, a chrome Cap and its Holes, a Spout empty; the chrome is half metal with a faint cool
glow, since a full metal mirrored the orange sand and read as copper), floating 1.2 m out, circling and bobbing, tipping
over and shaking at every pour while grains fall (`Fx.salt_grains`) and each patch lands in a low puff (`Fx.salt_land`);
the same script renders `tools/dl/salt_ref.png`, `sea_salt_ref.png`, `hiwa_kai_ref.png` for the icons. The path, all
`params.salt` keys merged by the mutations and an evolution's `final`: Sea Salt (pink #F4A3C4 patches and contents, x1.75
duration, x0.95 damage), Salt Spill (x1.6 radius), Thing About Luck (a creature killed standing in a patch rolls the
power-up drop at x3: `Game._salt_luck_at` -> `WaveDirector.drop_pickup_from(..., luck)`, any weapon's kill), Jeżyk's Salt
Flats (walking INTO a patch from outside it puts his momentum at full: `Player.max_momentum()`; a patch laid round his
feet counts only once he has walked out and back in), and the evolution Hiwa Kai (black salt with seven hard black
crystals on every patch, the path amplified to x2 duration, x1.8 radius, x4 luck, and its own bite: a creature walking
into the salt takes a crunch of x2 a tick and moves 30% slower while it stands in it). Each pour plays `w_salt_shake`, synthesised in `tools/synth_sfx.py` (three glassy taps, a rattle of grains on the cap, a
hiss of falling salt). TextGen words it (`salt_words`,
"patches", "patch radius"), WeaponInstance gives its rows and estimate (`salt_rows`, `salt_dps`: one creature a patch
lying). Captured by `game/tools/_p69_salt_shot.gd` (white, pink, wide, black, at the game's camera, mid-pour and close);
tests `game/tests/pass69_salt_test.gd`.

**Pass 69, lane FRIS: the Frisbee.** A new common weapon `frisbee` (behaviour `Frisbee`, core/behaviors/Frisbee.gd, in
the pool for everyone; Jeżyk starts with it) after Garry's "throws a frisbee in curving arcs, can't predict which
direction they will go ... hits through enemies, but has a damage drop off like the Revolver, but frisbee never stops".
A self-contained flight with no ProjectileManager shot and no held model: it aims at the nearest creature in range (else
where he faces), each disc of a volley leaves its fanned aim line (16 degrees apart) at a bend of 25 degrees + 12 per
extra frisbee to a random side and turns back on the circle that crosses the line at the target's distance (clamped to
3 m..range, the whole turn capped at the bend + 60 degrees), flies its whole range (12 m), then glides 0.45 s down to the
sand and fades, hitting nothing on the way down. Every creature within 0.55 m x size of the disc is cut once a flight
at 0.85^n of the damage, never under 0.25. The discs are built in code (Frisbee.disc_mesh: a lathe-turned disc with
flight rings in vertex colours, a box per razor blade; the plain lime one, the hot-pink "Shredder" with eight blades
after `_REFERENCES/2d/frisbee_razors.jpg`, the chrome-and-pink saucer with glowing razors and a glass bubble), spin flat,
bank into the turn and leave a faint ribbon (one ImmediateMesh for every disc). The path: **Poison Razors** (element:
the game's poison, the razor disc), **Carry** (volume: 10% that the first creature hit rides the disc to where it comes
down, held by the Gravity Gun's grip so never a boss, an Elite or an ungrabbable creature, one a disc; the disc x1.5;
card text exactly Garry's "It has a 10% chance to carry the enemy away.") and **Trick Shot** (motion, id
`frisbee_trick_shot` since `trick_shot` is the Revolver's: `params.proc_mult` 1.25, read by the new
Run.trick_proc_mult in Run.add_damage for life steal and in EnemyManager.damage for crit, Cold Snap and Vulture, and by
the frisbee for a `stun` roll it may carry; no frisbee content stuns today, so its stun share waits for one). The
**Flying Saucer** evolution keeps the path amplified (carry 0.2 with a drop hit of the disc's damage, poison x1.5 via
its own base poison_damage/duration 2 on the razors' 4, proc_mult 1.5, the saucer disc x1.5 with a green poison haze)
and loops once a flight: one full 1.3 m circle the way it is turning, somewhere between 30% and 70% of its range.
TextGen.frisbee_words, amount noun "frisbees", stat rows without pierce, a dps estimate of three creatures at the
drop-off. References for the icons rendered by tools/_p69_fris_ref.gd (tools/dl/frisbee_ref.png,
frisbee_razors_ref.png, flying_saucer_ref.png); captures by tools/_p69_fris_shot.gd; tests pass69_fris_test.gd.

**Lane PAS (pass 69): five new passive items and the Magnet reworked** (Garry's items 4-9). Counterpunch (uncommon):
an evade arms the next attack (the first weapon to fire after it hits for x2 until it fires again or 1 s passes:
Run.counterpunch_evaded / counterpunch_fired, called from WeaponBehavior._process, / counterpunch_mult in
EnemyManager.damage) and starts a quiet timed boost of weapon speed and move speed (2 s, +20% / +15%; levels add).
Heavyweight (rare): +1% attack damage per whole 10 max HP (+0.25% a level), its own sheet source redone with the
passives (Run._apply_heavyweight). Snake Oil (epic): Player.overheal, filled by any heal past full (not regen) up to
20/30/40% of max HP, taken first by hits, never fading; the HUD's HP bar runs on past full in pink. Hot Springs (epic):
+max HP and regen, and every heal (regen too) is summed into a pulse at most every 0.5 s, 4 + 2 per HP healed (40 at
most) to creatures within 3 m (Player._tick_heal_pulse -> heal_pulsed -> Game._heal_pulse, source `hot_springs`), a
green-gold ring racing out. Last Stand (epic): a hit leaving him under 30% (Run.last_stand_check, from take_damage before
`hit`, so the hit-stop stays out) puts x2/x2.5/x3 attack damage on the sheet and ui/LastStandFx.gd runs the engine at 0.5x
for 2 s of real time, owning Engine.time_scale (1x whenever the run is paused, ended at once on death or when the node
leaves), with its own look (core/shaders/last_stand.gdshader: a cold blue-grey drain and a red heartbeat rim on a canvas
layer under the HUD), a toast and a thump; a hidden 20 s cooldown. The Magnet became epic and lost its pickup radius:
PickupManager._tick_xp_pulls pulls every EXP gem within 5-8.5 m (pull_xp, the magnet arc) at random waits of 3-8 s
divided by 1 + xp_pull_rate (1.5-4 s at level 5). TextGen gained the "word" stat kind (said by its name, never a number,
left out of totals) so the Magnet's "pulls more often" never names its interval. Ten new player stats (counter_*,
heavyweight, overheal, heal_pulse, last_stand, xp_pull_radius, xp_pull_rate), four synthesised sounds (tools/synth_sfx.py:
it_last_stand, it_heal_pulse, it_xp_pull, it_counterpunch). Tests: pass69_pas_test.gd; pass47_rules_test's tiers
re-pinned. A headless probe (game/tools/_p69_PAS_probe.gd: the arena, the Drifter with all six and Evade + Thirst,
a crowd that hits, god mode off) saw each work in the live game: Last Stand twice in 60 s (120 slowed frames each, the
clock back at 1x), ~90 heal pulses, every evade arming Counterpunch, ~20 Magnet pulls; captures in tools/dl/p69/PAS/shots
(game/tools/_p69_PAS_shots.gd). LastStandFx counts real time as the frame's delta without the engine's scale (a wall
clock clamped per frame had stretched the window on a slow frame).

**Lane EN (special enemies, the special Goblin, the spawn beam).** Garry: "increase the power of 'Special' enemies a bit
... 3 times more rare ... 1.25 times bigger ... HP x10 ... ATK x2 ... the colouring of special enemies should be
possible in the Level Editor ... a single 'Special' regular Goblin appears at the end of the first wave"; "the beam of
light ... gets cut off at the bottom". Every creature with a `variance.special_chance` has a third of it (4 decimals) and
`special` size 1.25, hp 10, damage 2 (a special's size is now exactly its factor x the creature's, the plain ones'
spread dropped, so it is never smaller than a big plain one; XP kept; `tools/dl/p69/EN/specials_edit.py`, line edits, CRLF kept, Garry's
armadillo/dust_mummy looks kept). `EnemyDef.SPECIAL_DEFAULTS` {size 1.25, hp 10, damage 2, xp 2, tint_strength 0.6,
glow 0.6} and `special_value(sp, defaults, key)`: a special's number is the creature's own, else the map's new
`timeline_data.special_defaults` (`WaveTimeline.special_defaults`, JsonContent, `WaveDirector._apply_mults` ->
`EnemyManager.special_defaults`), else the game's. New `special.glow` 0..1: `EnemyManager.vglow` rides on
INSTANCE_CUSTOM.y as 64 x level (`special_glow_code`, above the flip bit and the tether's 2 x 16, so
enemy_silhouette's `mod(y, 2)` is untouched) and `enemy_billboard.gdshader` draws an emissive rim 1 + 4.2 x glow px (a lighter core ring 0.6 + glow px)
wide in the tint's hue at full brightness (linear), breathing 0.8-1, and lights the painted outline (0.85 x glow); off
while dying; the tether's red wins. A swarm event's new `"special": true` holds `EnemyManager.force_special` around its
spawn: every one comes as its special, whatever its chance, before `colour_after_kills`, with no SWARM! banner. Red
Canyon's special Goblin: `{"t": 120, "type": "swarm", "enemy": "red_goblin", "variant": "RG-B", "count": 1, "pattern":
"in_front", "special": true, "name": "Special Goblin"}` (the green goblin is retired; the first row r1, the red goblins,
runs 0:00-2:02, the scorpion charge comes at 2:03; the event joins r1's fixed numbers). The spawn beam: shine_aura's
mode 1 gains `fade_y` (a smoothstep in world height, off by default so the chest's beam is unchanged) and
`Game._spawn_beam_fade` sets it on both beam quads from the highest sand under each (5 samples across its width):
nothing 0.15 m above it, whole 2.6 m higher (`SPAWN_BEAM_FADE_GAP`, `SPAWN_BEAM_FADE`, `spawn_beam_fade_y`). Level
Editor: the Enemies tab's new "Special" section (Chance, Size x, HP x, ATK x, XP x, Colour picker, Colour strength,
Glow; a table of what applies and from where: this creature / the map's Coloured specials / the game's; a plain one
beside its special drawn with its tint and rim, `Enemies.paintSpecial`), Settings' "Coloured specials" card
(`special_defaults.*`), the swarm's "Special" box with a note of what it brings, a star and the creature's special
colour on its Events-lane flag and a line in its card, "Special glow" among a row's Elite overrides; `Model.SPECIAL_DEFAULTS`
/ `specialValue` / `specialSource`, `varianceSpecial(c, stats, defaults)` (+ `glow`), `creatureAt` reading the map's
defaults, the spawn estimate counting a special swarm as coloured (and selftest.py's Python twin); a light special
colour is now a warning, not an error (pass27_test re-pinned to "a valid colour"); vocab.py's VARIANCE_KEYS and a drift
check against `EnemyDef.SPECIAL_DEFAULTS`; `selftest_EN.py` (28 checks). docs/waves_schema.md "Pass 69". Re-pinned:
pass27_test (special tint), pass46_pacing_test (the stretched events skip the special one), pass62_pc_test (stage 1's
events gain the special Goblin), selftest.py's varianceSpecial default size 1.25. Tests `pass69_en_test.gd` (8).

**Lane HERO (pass 69): Mamy is May, Buck is Jeżyk.** Garry's Mamy (built in the Level Editor during pass 68) became
**May** everywhere: her folder `content/characters/may` (may.json, the strips, the `_ai.json` markers, new .import files),
id `may`, codes MAY-A/B/C/F (her draft MAY-F still says it came from MAY-E); the art caches were COPIED under the new
keys (ai_raw_anime may_*, ai_anim may_mayb_/may_mayc_pose_run_*, review/may_badge_cands.png) so a re-roll finds them,
the old ones and the Level Editor's backups and finished jobs left as history. Her kit: favourite the Tommy Gun (cooldown
-15%), her hero mutation **Trigger Happy** (the Tommy never stops: ProjectileEmitter's new `fire_without_target` fires
along her facing with nobody in range, `stream` spreads each burst over the whole cooldown; damage x0.65, cooldown
x0.6) and her perk **Inflatable May** (the new perk special `decoy`, `core/systems/Decoy.gd`): every 30 s she throws an
inflatable double 4-7 m away; where it lands a faint pink circle of 6.5 m marks it and for 2 s every creature inside
(Elites too, never a boss) walks to it and bites it (EnemyManager `fool` / `decoy_target`, one hook where the brain
steers and one before the bite) with a pink "?" bobbing and pulsing over its head (one MultiMesh,
`core/shaders/decoy_mark.gdshader`, `art/ui/decoy_question.png` from `tools/make_decoy_art.py`), then it pops with a
pink puff and a squeak (`pk_decoy_land`, `pk_decoy_pop`, synthesised in `tools/synth_sfx.py`). The doll is
`may_decoy.png` (a placeholder cut from her cheer frame until lane ART paints the vinyl doll). **Buck** keeps his id and
charge and becomes **Jeżyk** (Polish "little hedgehog", the Sonic nod Garry asked for, no "-ov"): a bald blue-skinned
man in a black tracksuit with white stripes from Garry's reference; he lands with the Frisbee, loves the Salt (area
+25%), owns Salt Flats; Drum Roll is hidden. His top-level art words (art_prompt, appearance, hints, side_hint asking
for level shoulders, title_pose with his hands in his jacket pockets) are the tracksuit's, which every new look
inherits; the deer's words moved into the deer looks' recipes so a re-roll of them still paints the deer; BUC-A and
BUC-C shelved, BUC-B played until lane ART lands the tracksuit look. UiKit's Lilita One head font got the bold body font
as a fallback (it has no ż).

**Lane UI (heroes to unlock and buy, the hero drawer).** Garry: "There are now unavailable heroes, ones that can be
unlocked ... After the requirements are met the heroes will become available to unlock by buying them with coins", a Hero
Collections button "to the left of the selected hero plaque ... like a box of boxes" that opens "a kind of a Drawer UI
element with the list of all heroes 2 rows tall ... over the hero preview". The purchase loop parked in pass 66 is wired:
`availability` "purchase" no longer hides a hero (JsonContent: only "hidden" does; a purchase hero is shown whatever
`hidden` says); `Registry.hero_state(c)` reads owned | buyable | locked | hidden from his availability, his unlock quest
`unlock_<id>` (Registry.quest_for) and `Save.heroes_owned` (new key; a save from before owns only the free heroes, as
Garry asked); `Save.buy_hero` spends his price once with the sink "hero"; `Registry.heroes_for_drawer` orders owned, on
sale, locked. Six quests (Calavera: the Tumbleweed King; Ironwood: 2,500 kills; Solenne: extract after stage 2; Jeżyk:
15 minutes in a run; May: level 30 in a run; Mira: 99,999,999 kills, out of reach on purpose) and prices 300/400/600/
500/700/9,999, Fadeaway 50 with no requirement (Garry's test), Drifter and Astro free, Mira back (order 9), Dad hidden.
The title (ui/TitleScreen.gd): a hero not owned runs in under a black mask (TitleStage.LOCKED_TINT near black; the
desert haze still warms it a little), his plaque reads Unknown with "?" for his numbers and his start weapon and
favourite as mystery plates (WPlate.mystery: the icon's black shape and a "?"); locked, the Requirement card (what
unlocks him and the progress bar) sits over the plaque, between his feet and the dots, with the padlock on his chest;
on sale, BUY with his price sits over him (aged with "N more gold" under it when the purse is short); BUY asks
(WConfirm), buys, lifts the mask (TitleStage.reveal) under a WCelebrate burst and opens PLAY; PLAY refuses a hero not
owned. The Hero Collections button (drawn: two boxes and a third in an open crate; a close X while open) opens
ui/wanted/WHeroDrawer.gd over the preview, between the tagline and the hero's head: every hero as a badge tile in two
rows (sideways scroll when they do not fit: TouchScroll.horizontal), the shown one brass, a not-owned badge as a mystery
plate with his price or LOCKED under it; a tile selects him (he runs in under the drawer, which stays open), a tap
outside closes it. The hero sheet has the same unknown state (and his price when on sale); the developer menu has "own
every hero" and "forget the bought ones"; the run's banner and the results say a hero is for sale without naming him;
`hero_bought` goes to PostHog. touch_audit's hero_drawer / hero_buy, pass69_ui_test. tools/arena_check.gd runs the title's quiet quest check before it snapshots the save (a new hero quest the save already
met completed on the title after the arena and read as the arena changing the save); RunAnalytics.META_REASONS has
"hero".

Garry: "When making changes to Items along the way, make sure to update the LevelEditor and include instructions on how I
would be able to use the newly created tools in the future" (and the same for heroes). The editor now edits everything the
pass added, and its Instructions tab opens with "Pass 69: how to use the new tools" (twelve how-tos).

- **Typed params** (`AFIELDS.PARAM_GROUPS`, new `tools/level_editor/typed_forms.js`): a weapon's Params and a mutation's
  Effect show the knobs of the Salt (Salt patches, the floating shaker), the Frisbee (flight, disc, Carry, Trick Shot and
  stun, the loop), the ball (Alley-Oop's launch, the Heat look, the ball's body and seam colours) and Trigger Happy's
  nonstop fire as typed, explained fields above the JSON box. An empty box says what applies and where from (a mutation:
  its weapon's params, which /api/items now carries; an evolution's `final`: its own params; else the code's default). An
  evolution edits `params.final` or its own params. The selftest reads every typed key and default against the game's
  sources (it caught two: `salt.alpha` 0.5 and `disc.size` 0.36 in code, the weapons set their own) and checks every key
  the pass's content sets under a typed group has a row.
- **Perks have a form** (kind `perk`: server EDIT_KINDS / EDITOR_OWNED, KIND tables, the Heroes tab): His own → Edit or
  + New perk… (a copy of any perk for this hero). The special comes from `vocab.PERK_SPECIALS` (every default checked
  against Run.perk_param / Decoy.param); `decoy` and `periodic_buff` work on any perk, the others are checked by their
  perk's id in the game and the form warns on a copy.
- **Heroes to buy**: Availability free / to buy / hidden with `hidden` kept in step (lane UI's rule: only hidden hides);
  the hero's **Requirement** writes, edits or removes `content/quests/unlock_<hero>` (unlocks {type character}) through
  the availability op, in TextGen.quest_text's words (`AssetsModel.questText`); the list cards show the price and a
  requirement chip; new warnings for a hero on the title without a perk or with other than one hero mutation in play.
- **Icon candidates install from the item**: an item's (or perk's) Art section lists its finished icon candidate jobs, each
  picture with Install (Rebound's three designs A backboard, B return arrow, C catching hand).
- **Vocabulary**: the behaviours SaltShaker and Frisbee and their params keys; the ten new player stats with a help line
  each; TextGen's new stat kind "word" mirrored (the Magnet's "pulls more often": no number, no total).
- **Drivers** (lane ART's tools): the driver_pose job gained amp, amp_bones, lean, arms back and shoulders / shoulder_views
  / tuck (tools/pose_shoulders.py writes `<name>_lvl`); "+ New pose driver…" on a hero's Art words.
- **A pass 66 bug fixed**: `U.getPath` stopped at a list, so every weapon's and passive's Levels showed no effects, and
  `U.setPath` turned `levels` into an object on the first edit; both step into lists by index now.
- The quest-locked band follows pass44_test's re-pin (28-56%); the selftest's count pins became shape rules read from the
  content and the test file. Self-test 17,675 checks (new group selftest_L69.py).

**The lead.** Reviewed every lane's captures and fixed what read wrong: the Alley-Oop ball rendered violet and Slam Dunk's black brown under the sky's warm ambient light (a ball tint's `ambient` false: `disable_ambient_light`; Alley-Oop #0A4FA8), the live title's black mask came out brown in the scene's fog (`BillboardSprite.set_fogless`: copies of the billboard shaders with `fog_disabled` while a hero is locked), Last Stand's red rim was a solid band a quarter of the screen wide (now 0.085 of the width, at most 62% red), and a look kept on a phone that has since been shelved now gives way to the hero's own (Registry.played_look, which the player, the title stage, analytics and the arena now all read). Tests: pass69_lead_test.gd. Lessons: a windowed capture with an unbounded wait held the repo-wide Godot lock for half an hour and stalled every lane (captures need frame caps and a watchdog); the ComfyUI lock has no fairness, so a hand-run job starves behind the editor's queue (put the work in the queue); the blue screen keys a blue-skinned hero away (Jeżyk paints on green); Mixamo's Neck bone sits above the shoulder line, which painted sagging backs and raised side shoulders until tools/pose_shoulders.py levelled the drivers.

**Pass 70 (2026-10-13, v0.56): lines, the trampoline, coins kept, and the Level Editor's traps.** Five lanes from one contract (tools/dl/p70/INTERFACES.md). Fadeaway's Timeout became Hang Time (a 3D trampoline that launches him where he runs); Inflatable May now inflates out of a thrown puck; four new lines (Lodestone, Mule Kick, Slow Burn, Tin Star) and Prospector and Gold Tooth turned lines, each with an evolution; gold is banked on every end of a run, unlocks cost 2.5 times more, Elites and bosses pay five times more, the Strongbox is gone; the title's Collection button is a square as tall as the plaque with a 3x3 grid glyph; the Level Editor got distinct candidate seeds, pickers for a look's badge, cut-out and icon from everything painted, inherited text in the boxes, a Stills check (Garry's Bandit job had failed with a picture path in Stills), removing a base look (May's MAY-A), a one-view re-roll, a driver tweak job, per-view run sizes and two closed traps (the pick race, a hung Godot step); the art finished Garry's Bandit look, fixed May's straps, sizes and hands and Jeżyk BUC-F's sizes and hands (now played), and painted eleven icons.

**Lane TRAMP: Hang Time and May's puck.** Garry: "Time Out - name it something else and make it about trampolines ... a
3d trampoline spawns ... walking up on the trampoline causes the hero jump quite dramatically up in the direction
they've been walking ... Player can control his flight somewhat ... But not nearly as much as just walking"; "the
inflatable version of her should inflatable from a little hockey puck". Fadeaway's Timeout perk and pickup are retired
(`hidden`, kept with their code) and his perk is **Hang Time** (`content/perks/hang_time`, special `trampoline`, a new
reusable primitive any perk can carry: `core/systems/Trampoline.gd`, made by `Game._tick_trampoline`). After 10 s, then
20 s after the last folded, a 3D trampoline (`tools/blender_trampoline.py` -> `art/props/trampoline.glb`: Mat with a
"Dip" shape key, Rim, Legs; graded like the 3D weapons) drops out of the sky 3.5 m beside him, stands 30 s and folds
after one jump. Walking onto it from outside calls `Player.trampoline_launch`: an arc 4 m up and 8 m along the way he
walked, 1.1 s in the air on its own gravity (8h/T^2), the stick adding 35% of his walk, untouchable (take_damage and
every hostile push pass him by: `airborne` in `knock_immune`); the mat dips and wobbles on a spring, his shadow stays
on the sand and shrinks, the camera rides 30% of the arc (`Player.camera_y` read by CameraRig), the landing is a squash,
a thud and a dust ring. A pause or the card screen freezes a flight, a fall ends it. The first capture showed the fog
browning the black mat and turning the blue pad lavender (pass 69's fogless lesson again): the trampoline's mat and pad
and the puck draw without fog. May's decoy now flies as a black puck, lands 0.5 m short, slides to the spot with a hiss
and the doll inflates out of it in 0.3 s (0 -> 1.12 -> 1) before the fooling starts (Decoy phases SLIDING, INFLATING).
Three synthesised sounds (pk_trampoline_drop, pk_trampoline_boing, pk_decoy_hiss). The Level Editor knows the special
(vocab.py, assets_fields.js). Tests `pass70_tramp_test.gd` (14); `pass69_hero_test` re-pinned for the puck's slide and
inflation.

**Lane LINES (pass 70): six line items and their evolutions** (Garry's items 3-8). Four new lines and two passive items
made lines (ids kept, `max_level` 5 -> 4, their per-level numbers unchanged), each with an evolved line: **Lodestone**
(pickup radius x1.4 a level) -> **Mother Lode** (x4.5 and every 12 s every XP gem on the screen flies in:
`gem_sweep_every`, `PickupManager._tick_gem_sweep` / `sweep_screen`, the first sweep 1 s after it is taken, a gold ring);
**Mule Kick** (knockback x1.25 a level on `all_weapons`, folded into every weapon's sheet) -> **Bucking Bronco**
(knockback x3.0 and `bronco_chance` 0.35: `EnemyManager._bronco_kick`, called from `damage()` after the shove, throws a
plain creature 2.8 m up and 2.5-6 m away along the knock over 0.8 s on pass 69's `launch()` with a flat `drift` in its
`_launched` entry that `_tick_launch` carries (`_bronco_drift`); bosses, Elites and elite-modded creatures only take the
knock; no fall damage); **Slow Burn** (debuff duration x1.2 a level) -> **Prairie Fire** (x2.2 and `debuff_jump` 3: a burn
or poison that runs out, or whose creature dies with it, jumps to the nearest creature within 4 m that lacks it, at its
full seconds, 3 hops at most, never a fire onto the boss: `EnemyManager._prairie_jump` / `_prairie_on_death`, hooks in
`_tick_fire`, `_tick_poison` and `_die`, an ember streak by `Fx.lightning`; `poison()` keeps the item's own seconds as
`dur`); **Tin Star** (damage reduction +5% a level) -> **Marshal's Star** (+25% and `star_block_every` 10: a gold star over
the hero, `core/systems/StarGuard.gd`, made by `Player._star_guard_sync` from `refresh_stats`, blocks one whole hit after
the Invincibility bubble, the blink and an evade (`Player._star_block`: BLOCK, a gold burst, the iron clang, the hit's
blink, logged "blocked by Marshal's Star"), back 10 s later on the buffs' clock); **Prospector** (+6% extra gem a level) ->
**Eureka** (+35% and `vein_chance` 0.04: `PickupManager.vein`, rolled in `prospector()`, 5 gems of the kill's size burst
out in a fountain); **Gold Tooth** (coin gain x1.1 a level) -> **Gold Rush** (x1.6 and `gold_might` 0.01: +1% attack damage
for every 100 gold gained while held, +50% at most, `Run._gold_rush_gain` on `gold_gained`, its own source "Gold Rush
+N%", `Run.GOLD_RUSH_PER` / `GOLD_RUSH_CAP`). `debuff_duration` now also stretches freezes and stuns
(`EnemyManager.freeze` / `stun` take `scaled := true`; pass53_waves_test's "never scaled" pin re-pinned). TextGen kind
**"rule"** (`RULE_TEXT`, `rule_words`): a stat said as a sentence with its number inside ("a star blocks a whole hit every
10 s"); `LOWER_BETTER` gained the two waits. The six stats are in StatSheet.PLAYER_DEFAULTS, TextGen.STATS, the Level
Editor's vocab.py and assets_model.js (with help lines). Content: `content/passives/{lodestone, mule_kick, slow_burn,
tin_star, mother_lode, bucking_bronco, prairie_fire, marshals_star, eureka, gold_rush}` (placeholder icons; lane ART
paints them). Tests `pass70_lines_test.gd` (16); re-pinned on purpose: pass47_rules (21 lines / 42 with evolutions,
Prospector and Gold Tooth out of the passive-item tiers, Hush Money in Prospector's place in the no-cap loop), pass53_waves
(a stun is stretched now), pass44 (comment: 23 of 79, 29%), the Level Editor's selftest_S floor (21 lines, 34 passive
items). Captures `tools/dl/p70/LINES/shots/` (`game/tools/_p70_LINES_shots.gd`). Note: Ducktape (pass 47) was already a
debuff-duration line; Slow Burn is a second one, as the contract asked.

**Lane ECON (pass 70): coins kept on death, prices x2.5, Elites and bosses x5, no Strongbox, the Collection button.**
Every end of a run banks the purse: `Game.bank_run_end` (static, out of `end_run`, which still calls it once behind
`_ended`) puts the whole `Run.run_gold` into the save with the reason `run_bank` whether the hero extracted, died or
abandoned; `Run.last_result.lost` is 0; `RunAnalytics.gold_end` counts `gold_lost` only for a quit. The texts follow:
the Results screen shows "Banked" with the count and before → after for every end (the struck-through "Left in the
sand" and the Strongbox line are gone; first-time hint "Your gold comes home, whatever the end."), the stage-clear
dialog reads "Head home, or push on." and "The N gold comes home either way.", Down! says "Stay down and the N gold
still comes home." and its confirm "… comes home with you.", the pause screen's abandon row "picked up so far is kept"
and its confirm the same. Prices x2.5 (`tools/dl/p70/ECON/prices.py`, line edits): the eight talents' `cost` arrays
(halves to the nearest 5; the board 34,572 → 86,440) and the heroes' `price` (Calavera 750, Ironwood 1,000, Solenne
1,500, Jeżyk 1,250, May 1,750, Fadeaway 1,000). Elites and bosses x5: `Game.ELITE_PURSE` [450, 300] and `BOSS_PURSE`
[1300, 700] (`elite_purse()` / `boss_purse()`, base + per stage), the bosses' `drops.coins` 60 / 150 / 200 (King, Gila,
Brander; `Game.BOSS_COINS` 60 the default), and `PickupManager.BIG_COIN_MULT` 5 on an Elite's or a boss's `drops.gold`
coin (`big_coin_mult`). The Strongbox (`gold_bank`) is `hidden`; `StructureManager.in_play` keeps hidden structures off
the map (content, painting, the `bank` effect and pass 64's return primitive kept). The title's Hero Collections button
is a square as tall as the plaque (`TitleScreen.drawer_side` settles the two, `_on_plaque_resized` re-places when the
plaque's line wraps later; 167-169 px at 1080x1920, was 104) with the plaque's 8 px shadow, and its glyph is eight
plain ink squares of a 3 x 3 grid with the bottom-right one missing (`glyph_cells`, `GLYPH_SPAN` 0.5, `GLYPH_GAP` 0.28,
whole pixels); the close X grows with the button. Tests `pass70_econ_test.gd` (14); re-pinned on purpose:
pass61_an_test (a death banks: `test_a_death_banks_the_purse`; the real run's Elite purse 90 → 450), pass46_ui_test
(the results after a death show the banked purse, no Strongbox line), pass69_ui_test (the title buy test's purse holds
Fadeaway's 1,000), pass64_pl_test (`_bank` stands a Strongbox itself, its return primitive still tested).

**Pass 70, lane LE (the Level Editor's seven points, then the lead's three follow-ups).** Garry: candidates kept
coming out alike, a look's icon and cut-out could not be chosen, May showed no badge in the Heroes list, a Bandit look
failed with a 500, MAY-A could not be removed, and inherited prompts had to be retyped to change three words. Causes:
within a job the seeds always differed, but every new job of a look repeated the previous job's seeds (MAY-E's two badge
jobs both 2768/3768/4768, every title job 11/112/213/314) and a front from a picture always the same seeds and the cached
files; May's list badge was the base look's placeholder `may_icon.png` (her badge is MAY-G's own); the Bandit job had the
picture's path in Stills, which became the ComfyUI upload name. Made: `tools/cand_seeds.py` (candidate k a million seeds
from k-1, a job's own move, a re-run's attempt; `ASSET_JOB_ATTEMPT`), gen_edit_stills's slug check and candidates moved
aside before a paint, `comfy.upload_name`; the Stills slug rule in the form, the server, the recipe editor and the tool;
"Choose <CODE>'s badge / title cut-out / icon from everything painted" with Install into any look (`install
options.variant`), `icon_play` / `title_play` in the hero records; "Remove…" on a base look (`remove_base`: the new base's
art becomes the top level, inheriting looks pinned, files and `base_<CODE>.json` to backups/deleted, landings on such a
base mirrored) and MAY-A removed with it (MAY-G her base); inherited values in their boxes (`Forms.inheritable`: the typed
recipe, the job form, typed params); `driver_tweak` (scale / spread / occlude / shoulders on a copy of a driver), the
re-roll "redo one view's walk", a re-queue that reads the look's recipe from its JSON. Follow-ups from lane ART: a view's
size is the recipe's `run_scale` (ART's gen_art key; "Run size: <view>" rows), never a scaled driver (gen_art fits every
walk back to the standing height), and the docs say so; the front-from-a-picture pick merges only `stills` into the
look's current recipe (`Hooks.merge_recipe`; it had overwritten BD-A's words); a Godot step of a register or import job is
killed after 600 s (`GODOT_STEP_TIMEOUT`, the spec's `step_timeout`), freeing the Godot lock (a `godot --import` had hung
12 minutes). Self-test 17,876 checks (17,676 before), `selftest_LE70.py`. Lesson: a sparse record and a job's snapshot of
it drift apart; every writer merges the keys it owns into the file as it is now.

Lane ART (pass 70), all art through Garry's running Level Editor's queue (port 8787) except single-clip driver tests and
two still-candidate sets run beside it under the comfy lock. **The Bandit** (buckshot_dwarf BD-A): Garry's job had
failed because he put the picture's path in Stills (the slug the look's paintings are cached under), which became a
ComfyUI upload name with slashes (HTTP 500). The recipe was fixed to `stills: "bda"`, his turnaround cut into its
halves, the front painted from the front half with his words rephrased for one view (front_from_picture, 4 dev-Turbo
candidates, c2 picked: the simplest gun and no ground shadow; the vision QA called a good one "side / no-match"), then a
creature_free2 look like BD-0's walk (free Wan clips front and back, the tilt death). The first back still lost the
shotgun: the front_from_picture pick phase had written its own stale recipe over BD-A's after the look job was queued,
so the look ran on the base dwarf's words without Garry's back-view words; with them restored as `back_hint` the back
matches his picture (barrel up-left, stock down-right, the bandana knot, the V zigzag). Left `fresh`, not played.
**The size of a view's run** (May's side half a head taller, Jezyk's back run smaller) was not the drivers:
gen_art.pose_cycle fits each view's clip by its tallest frame, and a side run crouches in every frame (blown up) while a
back or front run has a foot reaching down toward the camera (shrunk); measured on the head, MAY-G ran at 1.18 / 1.08 /
1.32 / 1.24 / 1.14 of her standing size (back, bd, side, fd, front) and BUC-F at 0.96 / 0.99 / 1.17 / 1.16 / 1.24. A
scaled driver cannot change it (the clip is fitted back), so gen_art gained a recipe key `run_scale` ({view: factor},
default 1, a re-queue re-places the cached clips): MAY-G {side 0.88, fd 0.92}, BUC-F {back 1.07, bd 1.06, side 0.90, fd
0.91, front 0.90} (a view grows only until its walk fills the cell). **May**: her three-quarter-back still had been
painted without the overalls' back straps (every view is an edit of the front, whose straps are on the chest); four new
dev candidates with strap words in pose_hint all had them, a_c0 (front reference only: the editor's own route) kept the
old turn and was installed, the bd walk and hit still repainted from it. Her back run's gloves showed beside her in
every frame because run_spread_lvl pushes both wrists out past the torso; a new driver `run_hidefwd_lvl` drops, in the
back view, the arm that swings forward (judged from the side view's same frame), so one glove shows at a time beside
the hip (`run_occ_lvl`, the occluded one, still showed both often). **Jezyk**: the dash's front view put his wrists on
the jacket and Wan painted his hands over it; dropping the wrists (or only the fingers) made it paint his fists at his
chin; `run_dash_f_low` angles the front view's arms down and back with the hands low beside his hips, outside the
jacket. BUC-F approved and made his played look; MAY-G approved. **Icons** (Klein, 4 seeds, finished and checked on
their plates and at HUD size on the sand, `tools/dl/p70/art/icons_review.png`): Hang Time from lane TRAMP's trampoline
render (the dipped mat, a basketball flying up; the sneaker set read as a brand swoosh), Lodestone, Mule Kick (third
words: a whole small mule kicking into an impact burst; the hoof alone came out as a porthole, then cropped), Slow Burn
(a braided fuse and a brass hourglass; the first set were garden hoses), Tin Star (six points asked for twice; five
points read like Marshal's Star), Mother Lode, Bucking Bronco, Prairie Fire, Marshal's Star, Eureka, Gold Rush.
Garry's how-to for doing the May and Jezyk fixes in the editor alone: `tools/dl/p70/howto_ART.md`.

**The lead.** Integration: the whole suite green with every lane merged, the PostHog board's "left in the sand" tile relabelled (only a quit loses gold now; the boards were not re-run). Lessons: a value field that becomes a file name must be checked where it is typed and cleaned where it is used; a slug field next to a picture field invites the picture's path; walks are fitted by their tallest frame, so a per-view size is the honest knob, not a scaled driver.

**The Puppet trial (2026-10-13, after pass 70): image-to-3D for May.** **Lane PUPPET (2026-10-13): the image-to-3D "Puppet" trial on May.** `tools/puppet.py` (stages apose, shape, rig,
anim, guides, looks, compare; resumable, `--pick`, `--from-blend`, `--from-fbx`, `--install-pickers`) and
`tools/puppet_blender.py` (clean, rig, anim, guides, silhouette) turn MAY-G's painting into a rigged, animated 3D May
and use her renders to guide the video model. Klein painted her in a 45-degree A-pose (the first wording gave a near
T-pose), side and back in the same pose; Hunyuan3D-2mv (tencent, not gated, 4.9 GB into the server's
models/checkpoints) ran through ComfyUI's built-in nodes on the R9700 in about 90 s a try, nothing installed; the side
still is Hunyuan's "right" view and its mirror the "left". Blender cleaned it (one piece, voxel remesh, 60k vertices,
1.61 m = her game height). The rig is found from exact mesh cross-sections (edge crossings: vertex slabs gave false
gaps): the neck as the narrowest middle run, the shoulders where the body reaches 1.6x that, the arms where they stand
apart, the crotch where the legs merge; Mixamo's names, non-deforming fingers for the OpenPose hands, Blender's
automatic weights (no failures), the head region (hair, beret) on the head alone. The Mixamo run is retargeted by bone
directions (O_pose = D A O_rest: her A-pose onto Mixamo's T-pose), the idle is procedural (no Mixamo idle on disk),
her colours are projected from the paintings as vertex colours (side views skip the flank the hanging arm covers; the
fill comes from inside the keyed figure, not its teal rim); `may_puppet.glb` (run, idle) went to Drive at 14:09 with
GLB_READY.json. Guides: OpenPose from her own bones with the joints her body hides dropped by ray casts
(`tools/dl/drivers/may_puppet_run`), depth videos (`may_puppet_run_depth`) and the 3D truth of each view's run/idle
height (`silhouette.json`). Looks through the running Level Editor's API, both fresh, MAY-G still played: MAY-P
(puppet OpenPose in every view, no run_scale) and MAY-Q (Wan 2.2 Fun Control on the depth guide for fd/side/bd/back,
OpenPose for the front, through gen_art's new recipe key `ctl_drivers`). Found on the way: blender_ref.meshes() counted
the glTF importer's 2 m bone-shape icosphere as model geometry (every depth-driver job on a skinned GLB was framed and
ranged wrong; fixed); a side run painted her face to the camera until the guide's ear was placed as pose_driver places
it (on the head bone's axis her bob had pulled it straight over the neck; neither a profile face rule nor levelled
shoulders helped, Mixamo's head points did); a depth video carries no face (crosshatched face, then long hair, from the
front); the depth's flat head became skin from behind until the words named her hair. Verdict: the pipeline works end
to end; as a guide it ties MAY-G's hand-tuned drivers and wins on the side's size without run_scale (head 1.13 P,
1.05 Q, vs 1.16 for MAY-G with its 0.88 fix) and on the back-diagonal keeping her turned away (Q), loses on MAY-P's
front head (1.24) and on colour fringes; next: a run fit from the puppet's own silhouette ratios (drops run_scale),
a guide framed by the soles, the fringe hues remapped. The running editor predated pass 70 (no one-view re-roll, no
install into a look): clips were moved aside by hand, the badge/cut-out named in place, one hung import cancelled.

**Pass 71 (2026-10-13, v0.57): the Puppet method in the Level Editor.** **Lane PLE (pass 71, 2026-10-13): the Puppet method in the Level Editor.** Garry liked the trial ("add that in to
LevelEditor with the considerations that I asked you about earlier"): the method `hero_puppet` in the job form like the
others (methods.json: its card with the trial's May from the arms-out painting to the painted run, its weaknesses: the
Hunyuan3D-2mv licence leaving out the EU, the UK and South Korea, the AMD card's built-in nodes only, the depth video's
missing face, Klein's four hands; its stage times measured on May and Jeżyk). `tools/puppet.py` became any hero's:
`--ref` per view (arms-out paintings painted locally by default, a still of any look, an uploaded picture, or no side /
back), the screen (Jeżyk on green), the painter (Klein or Flux.2 dev), generic words per view (the trial's named May's
beret and straps), the clip and idle (Mixamo FBX), the stick figures framed by the soles (MAY-P's boots had left the
canvas), versioned guides (`<hero>_puppet_<clip>[_N]`, each with its silhouette, so a look keeps walking on its own),
`--reroll`, `--reset-from` (moved aside, never deleted), lane gating with PICK / NEXT / DONE lines and a dry run that
mirrors the hero's folder and records every painting, graph and Blender command. gen_art got the trial's next steps:
`run_fit` (each view's walk sized by its median frame at the puppet's own run/idle height, no run_scale to tune) and
`fringe_remap` (the colours a painting lacks moved to its own). jobs.py runs a puppet look as phases through
asset_job (tool `puppet`) on the lane each needs (comfy for the paintings and the shape, local for Blender without the
ComfyUI lock), stops for the three picks on the card (the front; one side and one back together; the shape's tries in
clay), writes the guides into the look's recipe and walks it like hero_pose5; Re-roll… runs the puppet again from a
stage. puppet.js: the form's "The 3D puppet" section (start from: the puppet he has, a new one, his .blend, a Mixamo
FBX; the 3D reference per view with thumbnails; the clips; depth or stick figure per view; framing; run size; fringes;
the walks' stills) and the 3D preview, Google's `<model-viewer>` 4.0.0 vendored for offline use, on the hero's Art words
and on the job card (orbit, zoom, the run/idle picker, play/pause, speed, four cameras); the server serves
`/api/puppet/<hero>`, `/vendor/` and `.glb`. Jeżyk got his puppet (hero `buck`, look BUC-F): four fronts in 92 s (one
with four hands), sides and backs in 161 s, two Hunyuan3D tries of 99 and 87 s, 75 s of Blender for the clean, rig, run,
colours, GLB and soles-framed guides; his looks untouched. The job machinery ran for real on a queue of its own
(LE_JOBS_DIR): Jeżyk reusing his puppet (straight to the walks), Astro's first phases on the comfy lane with the picks.
Found on the way: a spec posted without a recipe shared jobs.py's one default dict (a look's stills and seeds leaked
into every later such spec; now copied), and, for the lead (from lane PDOC), every job's "open in ComfyUI" link opened
with red LoadImage nodes: the graphs name `88fits/<file>` and the page's picker lists only the input folder's top
level; a job's saved workflow (the file and its sidebar copy, never the graph that runs) now names a top-level copy
named by its contents (`88fits_<sha1>_<file>`), checked open clean in a browser on Astro's new workflows.

Follow-up (Garry via the lead, same day): the trial's improvements are now settings of hero_puppet, not a new method,
each in the job form's *The 3D puppet* with plain help and on by default: **Size from the 3D model** (run_fit, now
counting the outline so a view lands within 1 % of the puppet's ratio), **Frame by the soles**, **Clean colour fringes**
(fringe_remap, default changed to on), **Keep the face angle** (new `--face nose|head` in puppet.py/puppet_blender: the
stick figures' ears from the measured nose, part of the guides' match; and gen_art.hint_for_view walks a face=nose
look's back views on words without the face, after MAY-R's first back walk ran facing the camera) and per view **Depth
or stick figure**. Every setting is recorded in the look's `recipe.puppet` (jobs.PUPPET_SETTINGS), shown by name in
Recipe (typed) (methods.json labels) and run by a re-queue. Then MAY-R, with every setting on (MAY-G's stills, new
guides may_puppet_run_2, depth fd/side/bd/back + stick front), landed through the server's own hooks, fresh and not
played: its run heights sit at the 3D truth (mean error 0.005 against 0.035-0.052 for G/P/Q), no foreign hues in the
depth views, its back correct after one re-roll, its front and back heads the largest of the four. Imported; pass69_hero_test and
pass66_shape_test 23/0; selftest 18,097.

**The lead.** The explainer page for Garry (lane PDOC: puppet-themed, the steps with the trial's pictures, ComfyUI workflow links, Blender GUI screenshots with the manual rig, the models and their times, the cost) published at https://claude.ai/artifact/RLK1zdb7p4QhDuFfMhdyRm; its token figures: the trial about 0.82M, building it in, the page and MAY-R about 1.57M (lanes measured, the lead's share estimated). Two ships stopped on tests that failed one run in ten (the Golden Pineapple's ride, Birdshot's lane): a crowd built without a director could roll a random special, and since pass 69 a special has x10 HP and x1.25 size; EnemyManager's `colour_after_kills` now defaults to COLOUR_NEVER until a director sets it (the game always does: the timeline's value, 0 in the arena), the one test that counts specials asks for colour itself, and Birdshot's comparison allows 0.01 HP. Lesson: a random roll that grows stronger turns old exact tests into dice.

**Pass 72 (2026-10-13, v0.58): knockback halved, stronger specials, bosses that answer the build, the Results show.** Four lanes and an integration lane from one contract (tools/dl/p72/INTERFACES.md): the basketball stays orange (Free Throw's white tint gone, On Fire's glow capped), a clean Rebound icon, every push the hero's side gives x0.5 (map `hero_knockback_mult`), First seed on every candidate job; specials x1.5 size, x15 HP, a 35% chest, at most 3 alive, and creature outlines only behind scenery (the stencil buffer); a boss's HP scales with the square root of the hero's last 45 s of DPS against a measured reference, shown as a chart in the Level Editor; custom boss attacks as content (`content/boss_attacks`) with their own Level Editor tab, the Gila's rumble replaced by the red cactus rain; the Results screen as a two-part show (gold along the run's own curve, a kills chart with markers and counters, the sources in the order they came, then the unlocks).

**The white basketball.** Measured, not guessed (game/tools/_p72_items_ball_shot.gd: a throw at Heat 0/5/10, Alley-Oop, Slam
Dunk, On Fire, Free Throw, a far camera; each frame also averages the ball's own pixels, a watchdog quits after `limit`).
The plain ball was orange at every Heat; two things painted it white: (1) Free Throw (Fadeaway's hero mutation: an evaded
hit throws a ball) drew its balls in ProjectileEmitter.FREE_TINT, white albedo plus a white glow x1.4, so with Free Throw
a share of his balls flew pure white (measured fff8e6); FREE_TINT is gone and a free throw is the ball in its own look;
(2) On Fire's tint (#FF3A00 at 1.6) on the body, pushed toward the heat colour and beating x1.35 at full Heat, summed past
what the screen shows and came out yellow-white (ffdb37); the new `heat_look.body_green_max` (basketball 0.3,
ProjectileManager._cap_body_green) caps the green the body's glow adds at max(its cold glow's, 0.3), so it stays orange;
the plain ball never reaches the cap. Alley-Oop (dark blue) and Slam Dunk (black) unchanged (their glow is in the seams).
Captures: tools/dl/p72/items/before*/, after/, ball_before_after.png.

**Knockback halved.** One map number, `timeline_data.hero_knockback_mult` (WaveTimeline, JsonContent; Red Canyon 0.5;
Level Editor Settings > Scaling "Hero knockback ×"), on every push the hero's side gives a creature
(EnemyManager.hero_knock_mult): damage()'s kb_force from any hero source (HOSTILE_PUSH_IDS "loose_rocket" and "blast"
stay whole), the new hero_throw_radius (the Nuke's throw, Thruster Burst, Grand Finale; the rocket, the loose rocket and
the golem's boulder keep throw_radius), Buck's Ram, the tornado's toss, the Guitarra chord's bounce (ConeWave) and
Bucking Bronco's throw distance. Not the pull, knockback_resist, the boss's 0.15 or a creature's push on the hero.

**First seed everywhere.** Every candidate job shows the same two fields, "Candidates" and "First seed", with the same
words (jobs.py CANDIDATES_HELP / FIRST_SEED_HELP): the badge, the title cut-out (its field had shown as the raw key
first_seed in Asset settings, default 11, and the count as "candidates" at the bottom), icon candidates, creature_ctl's
side and view candidates, a front from a picture (its "seed shift" reached no tool and is gone from those two forms),
the puppet's arms-out fronts, and a new look's follow-on candidate jobs. tools/cand_seeds.start: the job's first seed
when it names one, else the tool's own start; the job id and the attempt move it on as in pass 70. Every tool takes
--first-seed (gen_badge_cands' first seed now replaces seed_for(id)+40; it was added to it). Selftest group
selftest_ITEMS72.py.

**Rebound's icon.** Its U-turn arrow had come out broken in two. Twelve new seeds (tools/dl/icons72, gen_icon_cands from words: one smooth unbroken arrow), compared with pass 69's two alternates (a backboard, a catching hand) at 96, 48 and 36 px on the dark plate and on paper: the alternates shrink the ball to nothing at HUD size; rebound72_c2 (one clean arrow leaving the ball's top, round its right side, its head pointing back at the ball) installed; the old one in tools/dl/backup/icons72/.

Garry: "Specials should be more noticeable. They should be bigger. They should have way more of a chance of dropping a
box. They should have higher HP. They should be a limit to how many of them are there"; "Make the outline of the enemies
not appear when they're behind other enemies, only when they're behind environmental things."

- **Specials**: x1.5 size and x15 HP (from x1.25 / x10) in all 22 creature special blocks and in
  `EnemyDef.SPECIAL_DEFAULTS`; a chest on a special's death at 0.35 (`variance.special.chest_chance` > the map's
  `special_defaults.chest_chance` > the game's; `EnemyManager._special_chest_drop`, called from `_die` after Hot Sauce's
  pay); at most 3 alive at once (`special_defaults.max_alive`, `EnemyDef.SPECIAL_MAX_ALIVE`, 0 = no limit;
  `EnemyManager.specials_alive` kept by spawn / `_die` / `_free`; the roll is made first and refused past the cap, so
  below it the dice are unchanged; a forced special always comes). Red Canyon's `timeline_data.special_defaults`
  {chest_chance 0.35, max_alive 3} written (Garry's open editor page may drop it on his next save; the game's defaults
  are the same numbers). Level Editor: the Special block's Chest chance with a 0..1 rule and its source row, a "Max alive
  (map)" row; Settings -> Coloured specials: Chest chance, Max alive; the defaults 1.5 / 15 everywhere; the spawn
  estimate (and its Python twin in selftest.py) caps the expected coloured alive the same way.
- **Outlines**: the stencil. Scenery writes 2 (new `core/systems/SceneryStencil.gd`: prop_billboard, sign_depth, the
  structures' and the portal's runtime copy of sprite_billboard via `BillboardSprite.scenery`, the barrels', the boundary
  wall's (posts, boulders, skulls) and the near cliffs' StandardMaterial3Ds via `mark_tree`); creatures and the hero keep
  writing 1; `enemy_silhouette` reads `== 2`, so a creature is outlined only where scenery is the nearest thing in front of
  it; the gems, coins, glints and the coin stream's shadows read `== 0` (were `!= 1`). Cost: GPU 0.587 ms with the
  stencil against 0.595 ms for the old outline (250 creatures, PC), same draw calls; perf_late unchanged.
- **Checked by eye**: tools/dl/p72/SPEC/shots1, shots2 (`cmp_*.png`: new | old): a skeleton behind a beetle no longer
  outlined over it, a skeleton behind a mummy behind a cactus outlined only through the cactus; outlines kept behind the
  saguaro, the rock, the war drum, a barrel, a sign post and the wall; specials at x1.5 with their glow beside plain ones.
  Tool: game/tools/_p72_SPEC_shots.gd (mode=shots|bench|gems, a 150 s watchdog).
- **Tests**: game/tests/pass72_spec_test.gd; re-pinned on purpose: pass69_en_test (x1.5 / x15; the Special Goblin's
  place: Garry rebuilt stage 1, so only "in stage 1" is pinned), pass58_wv_test (two tests spawn 20 / 30 specials at
  once: max_alive 0 there), pass47_combat_test (Hot Sauce's chest count: the special's own chest off there),
  pass54_combat / pass56_pk / pass60_pk / pass61_pk (the pickups read stencil 0; props write 2); Level Editor:
  selftest_SPEC72.py new, selftest_EN.py and selftest.py re-pinned.

**Lane BOSS (pass 72).** **Boss HP pegged to the hero's DPS** (Garry: "Boss Max HP should scale up the bigger the
Player's DPS is in that moment. It shouldn't be 1 to 1"): a map's `timeline_data.boss_hp_scaling {enabled, exponent,
window, min, max, ref_dps}` (WaveTimeline, `BOSS_HP_SCALING_DEFAULTS`, static `boss_hp_mult`, `boss_ref_dps`,
`boss_dps_window`; JsonContent reads it); `Run` keeps the hero's damage in 240 one-second buckets on `buff_clock()`
(`dps_reset` at a run's reset, `dps_note` from `add_damage`, `recent_dps(window)`); `WaveDirector.boss_dps_scale(id)`
(arena ×1; endless grows a returning boss's reference with its own HP growth since its stage, `boss_stage_of`;
`last_boss_scale`; prints "boss hp scaling: ...") is held in `EnemyManager.boss_hp_scale` around `_start_boss`'s spawn
and multiplies the boss branch's HP. Red Canyon: on, exponent 0.5 (2× DPS = 1.41× HP, the fight 29% shorter), window
45 s, floor 0.75, ceiling 3, references measured with `difficulty_probe.gd` (new `DPS45` line, `boss=1` plays on through
the fight and prints it, `scale=0|1`) over the 45 s before each boss on pass 64's builds: the King 600, the Gila 4500, the
Brander 20000. Level Editor: Settings → **Boss HP** (fields.js five rows + group; `boss_scaling.js`: a reference DPS per
boss event, a chart on a doubling DPS axis from ref/8 to 16× ref with the multiplier, the fight length against the
reference fight with and without the scaling, the floor and ceiling shaded, a crosshair readout, and the thinking in
plain words; the same words in the Instructions tab). **Custom boss attacks**: a content type
`content/boss_attacks/<id>/<id>.json` (`core/data/BossAttackDef.gd`: kinds rain / volley / ring / slam / script, groups
projectile, pattern, landing, telegraph, timing, sounds + damage × bite, knockback, lift; `DEFAULTS`; the static layout
`points()` with its gap rule, `smallest_gap`, `land_times`, `runner_entry`); JsonContent.TYPES + `_boss_attack`,
`Registry.boss_attacks` / `boss_attack(id)` (no icon expected), gen_placeholders skips the type. A creature's script
names one as `{"name": "<id>"}`; EnemyManager's runner (appended section: `custom_resolved` once per def, `_custom_attack_begin`
for the wind-up's marks, `_custom_attack_fire` from the fire step's `_:` branch, `custom_rest`, `_tick_custom_attacks`
on the shot clock in `_update_boss`; rains, volleys, rings and slams; `custom_landed/fired/hits/last` for tests) and
`core/systems/BossAttackFx.gd` (one MultiMesh per look and colour, filled every tick: spike, spit, pellet, shard, rock,
fire). **The Gila Grande's red cactus rain** (`cactus_rain`) replaces its rumble: red spikes thrown up and out from its
back, landing on rings of spots 3.6-16 m round it with at least 1 m of sand between any two circles (64 spots, about 20%
covered), each spot a red circle 0.9 s before its spike, staggered over 1.5 s, 0.75 × its bite and a knock of 4 only
inside a 0.9 m circle, the spikes stuck in the sand a moment. Level Editor: a **Boss attacks** tab (`boss_attacks.js`,
`boss_model.js`, `boss.css`; routes in `boss_attacks_io.py` hooked into server.py: list, new from a blank kind or a copy,
save key by key with a 409 on a stale file, assign / unassign a creature (only its `boss` block written), delete (refused
while used, cascade takes it out of the scripts, the folder moved to the editor's backups)): the list with each attack's
colour and users, the editor with every key's help and the game's default in grey, a top-down preview to scale (the boss,
the hero, the spots, the narrowest gap marked, a time slider and Play, New layout), "In the script of" chips, its own
Ctrl+S / Z / Y; the Enemies tab's script offers the custom attacks (★) and shows their cards as custom, not unknown.
Tests `pass72_boss` (12+); re-pinned on purpose: pass24_test (the Gila names cactus_rain, not rumble), pass48_world_test
(the rumble's paced-clock test runs on a test boss), hell_check (the Gila's second attack is the rain). Selftest group
`selftest_BOSS.py`.

**Lane RESULTS (pass 72): the animated Results.** Garry: "The Result Screen sequence in general should be more
animated": the gold counting along the run's own curve, a new kills chart left to right with graves, skulls, crowns and
gears and Kills / Damage counters in short numbers, the damage sources added in the order they were acquired, each bar
filling in turn, then a pause, a scroll to the unlocks, each completed one stamped, the rest's bars filling. The run now
keeps its story: `core/systems/RunTimeline.gd` (`Run.timeline`, new at every `Run.start`; `attach` from `Game._ready`
for a real run, `tick` from `Game._process` beside the run recorder's) samples the purse, the kills and all damage each
second and every source's damage each 5 s, marks each boss / Elite / special kill (read off `EnemyManager.creature_dying`:
`boss_index`, `elite_idx`, `vspecial`, the gear badge) and each `Player.died`, notes each source's first owned moment
(a scan of the build on `build_changed`) or first hit, the starting weapon, and the counted unlocks' progress as the run
began. `ui/ResultsScreen.gd` became a sequencer of named parts (gold, breath, chart, sources | pause, scroll, unlock,
progress) on its own clock: a tap anywhere but a button hurries the sequence ×4, a second ends it, the buttons always
answer, the board is held (no finger, drag or wheel) until the show ends and only eases down by itself to keep the newest
row above the buttons; `sequence()`, `part_name()`, `part_frac()`, `show_time()`, `tap()`, `skip_sequence()`,
`skip_all()` for tools and tests; `short_num`, `ordered_sources`, `progress_list`, `unlock_time` static. New kit pieces:
`ui/wanted/WKillChart.gd` (the chart: 48 smoothed slices, rock-red area under an ink line on an aged plot, the marks laid
out in pixels with merges and stacking, stage names under the plot, pops with `popped`), `ui/wanted/WStamp.gd` (a rubber
stamp that slams), `WBar.gain` (the last part of the fill in a second colour). The four markers are the game's own badge
pictures, not emoji: none of the game's six fonts has 🪦 💀 👑 ⚙️ (checked with fontTools) and a phone's emoji fallback is
not something to trust, so skull, crown and gear are art/ui/badges' and the grave is new (`art/ui/badges/grave.png`,
drawn by `tools/dl/p72/RESULTS/make_grave_badge.py` in the badges' style). The end-of-run survey waits for the show.
Proof: `game/tools/_p72_results_shot.gd` (a made-up run from `game/tools/results_story.gd`, every part captured by the
screen's own part clock, a watchdog; 1080x1920 and inset=130), `game/tools/_p72_results_real.gd` (smoke_run's real run,
its story checked: kills sum to Run.kills, the boss marked, the starting weapon at 0, the revive joined), wanted_shots'
16 / 16b / 16c / 16d (chart) / 16e (stamp), touch_audit's `results_show` (buttons during the show, a swipe holds and
hurries, taps end each sequence; then the usual audit with the board scrolling), `tests/pass72_results_test.gd` (11).

**Lane INTEG (pass 72).** Garry edited content in his Level Editor while the lanes worked (2026-10-13: Astro on sale at
300 gold and third in his order, Ironwood second, Calavera 300 and fourth, Mira hidden again, May playing MAY-P with its
picked icon, Solenne's SOL-B icon picked, Red Canyon's stage 1 rebuilt with the scorpions first, the skeletons and
knights, the red goblins from 2:03 and the goblin runt back on the roster at 2:21, row r2). His edits stay; this lane
made the tree agree with them. **The goblin runt is in play again** (`retired` false; the goblin stays retired). **The
tests that pinned his old numbers read his data now and check a rule** (each with a comment naming his 2026-10-13
edit): pass333 / pass334 / pass45_pacing (a goblin on the roster is not retired; the knights come with or after the
skeletons, while they walk, one to three skeletons a knight where the rows overlap), pass26 / pass46_passives / pass51
(Mira's Blasting Cap is offered, on the page and "optional" exactly while she is in play, "hidden · Mira" in the arena
when not), pass53_items (a save that owns Astro keeps her), pass61_hr (the title's order is the JSONs' `order`, distinct,
the Drifter first), pass62_pc (stage 1's shape: the cap in time order from 0:00, every stage-1 row a creature there with
weights, distinct ids and an end inside the stage, the King at 7:10, the scalars present, stage 1 at x1, path times in
order inside it), pass66_gd ("absent" now strips the availability and price astro.json carries), pass69_hero (her
played look is one of hers with its strip on disk), pass69_ui (every hero on sale with no quest is buyable on a clean
save, one with a quest locked; the title and drawer cases take the first locked and owned heroes in his order),
pass70_econ (every hero on sale has a gold price above 0, the Drifter free), and the Level Editor's selftest_S
(/api/heroes in the JSONs' order, each record's availability its file's). **A hero on sale without an unlock quest**
(Astro now, Fadeaway before) is buyable at once (Registry.hero_state); a save that played Astro while she was free
opens on the Drifter until she is bought. **pass61_an's 40 -> 44 bounty** was not pass 72's code: the test's shop
bought a random card (CardPool._pick's randf) and now and then it was Gold Tooth (greed x1.1), so the 40 bounty after
it paid 44; the test now skips greed cards as it skipped the Phoenix Feather (pass 63) and says which card raised
greed if one ever does. **Map safety**: Garry's open editor page saves timeline_data from its own copy and drops keys it
never saw (server.ordered_like keeps only the page's keys one level down), so the game's defaults for an absent key are
now pass 72's numbers: `hero_knockback_mult` 0.5 (WaveTimeline.HERO_KNOCKBACK_DEFAULT, class default and JsonContent
fallback), `boss_hp_scaling` on by default (BOSS_HP_SCALING_DEFAULTS enabled true, exponent 0.5, window 45, 0.75..3;
BOSS_REF_DPS_DEFAULTS King 600, Gila 4500, Brander 20000 for a boss the block's ref_dps leaves out, 0 = never scaled;
an empty block is no longer "off"), `special_defaults` already fell back to EnemyDef.SPECIAL_DEFAULTS / SPECIAL_MAX_ALIVE
(x1.5, x15, 35% chest, 3 alive); the Level Editor shows the same grey defaults (fields.js, boss_model.js REF_DEFAULTS,
boss_scaling.js); new game/tests/pass72_integ_test.gd; pass72_boss / pass72_items tests and selftest_BOSS /
selftest_ITEMS72 re-pinned to "the file's number, else the default". The three keys are in red_canyon.json as pass 72
left them.

**Pass 73 (2026-10-14, v0.59): priority targets, the Saiga Sniper, the Gila's new rain and burrow, creatures that grow out of the ground, fortune cards, Totem Poles, the plaque at one size, the PC exe's icon.** Six lanes from one contract (tools/dl/p73/INTERFACES.md), every painting through Garry's Level Editor queue: weapons aim at the nearest special, Elite or boss within 10 m first (a volley spread over the crowd sends only its first shot there); the Saiga Sniper (a new special from Garry's picture, look SS-A) aims from the edge of the screen with a gathering red line that locks on and fires a beam across the map, runs from the hero, and runs when hit (`flee_on_hit`, a block any creature can carry); the Vulture Raider's rocket shakes and slows to half on every hit and recovers in 3 s; the Gila's cactus rain marks every spot at once and spews them all out of its mouth to land together, bigger and wider; the Gila and the Scorpion Elite sink into the sand where they can be seen, the Gila waits 3 s hidden and erupts where the hero is about to be, throwing the hero and the crowd; boss summons are never special and four more; every creature grows out of the ground when it spawns; the title's hero plaque has one size and one font set; the line items are fortune cards (tarot names, "<card> Risen" for their evolutions, a card glyph, four painted framings as item looks, the tilted card played); the Stranger's pictures lost their seams; 10 to 12 Totem Poles a map each offer three small boosts; the PC exe carries its own icon and version, and a signing hook waits for a certificate.

**Pass 73, lane SNIPER (Garry's "Special Enemies").** *Target priority*: one shared helper,
`EnemyManager.priority_target` (+ `is_priority`, `set_target_priority`): the nearest special (a coloured variance special or
a gear-badge creature), Elite (by kind or modifier) or boss within min(the weapon's range, the map's
`target_priority.reach` 10 m), on the screen as the weapon's own pick; `WeaponBehavior.aim_index` asks it first, and so
do the pickers that never went through aim_index (ProjectileEmitter's healthy/random picks and tracking, the
Guitarra and Big Mouth now through aim_index, missile seekers' retarget); a volley spread over different creatures sends
only its first shot there (`WeaponBehavior.priority_pick` + `crowd_spots`' first spot: the Hammer's first head, the
Gravity Gun's first throw; the Lobber's first bomb, the Zap Beam's first link, the Sun Scepter's first pillar, the
Singularity's hole, the first Tarantula Hawk). The map's `target_priority {enabled, reach}` (WaveTimeline,
TARGET_PRIORITY_DEFAULTS) and the Level Editor's Targeting card. *The Saiga Sniper* (`content/enemies/saiga_sniper`,
Garry's Antelope_Sniper.png; lane ART paints the look): a new brain `sniper` in its own EnemyManager section — the
Raider's stand-off spawn (26 m), runs inside 14 m, walks in past 38 m, and between them freezes in his aiming pose (the
`attack` strip, its front or back half by facing: `EnemyDef.attack_views "front_back"`, `_attack_view_frame`) while red
lines gather on the hero from the sides of a 44° cone, more and faster (`SniperFx.line_plan`: the k-th at
(aim − 0.2)(k/n)^0.6, sweeps 0.8 -> 0.2 s), following him for `aim` 2 s, then lock, blink through a 1 s hold, and a
60 m beam crosses the map along the locked line (0.15 s white core in red glow, then a red afterglow and shimmering
sparks over 1.5 s) — all drawn by the new `core/systems/SniperFx.gd` (two ImmediateMeshes, blended: the first capture
showed an added-on glow reading pale yellow on the sand). The hero on the line takes 0.7 × the Raider's rocket damage at
the sniper's own stage (read from the Raider's data, `beam.damage_from`) and a knock of 5; creatures on it take 5 % of
their max HP (≤ 40) and a 3 m push to their side. 9 ± 1.5 s shot to shot; a hit, stun, freeze or launch spoils the
aim (`recover` 2.5 s). Aim and hold × 1/pace like every wind-up (2.47 / 1.23 s on Red Canyon). Synthesised sounds
en_sniper_aim / lock / shot (tools/synth_sfx.py). Red Canyon: a `specials.pool` row beside the Raider's (same stage,
so the same chance; one special at a time, so each now comes half as often as the Raider alone did). *Flee on hit*
(`EnemyDef.flee_on_hit {seconds, speed_mult, interrupts}`, any creature, `flee_start` / `_flee_steer` / `_interrupt`,
a hook in `damage()` and one before `_steer`'s brain). *The Raider's rocket*: `artillery.missile.hit_slow {mult 0.5,
recover 3, shake 0.35}` (ProjectileManager.shooter_hit / _rocket_hit_slow / rocket_shake_basis): every hit on him
halves his rocket's speed at once, back to full linearly over 3 s of the shot clock, the nose and the body jittering;
and a fix: a Raider whose wind-up a stun or launch dropped no longer waits for good for a rocket that never left.
He holds the aiming pose 0.35 s after the shot (the capture with lane ART's SS-A showed him lowering the rifle on the
beam's own frame); the muzzle was fitted to that painting (the barrel tip 1.25 m right, 2.1 m up at size 3).
`priority_target` scans a short list of the priority creatures alive, gathered once per grid rebuild or spawn
(`_priority_list`, a `_grid_epoch` bump at the top of `_rebuild_grid`), after perf_late showed the per-pick radius query.
Tests `game/tests/pass73_sniper_test.gd` (17; pass334's specials pool re-pinned on purpose); captures
`game/tools/_p73_sniper_shot.gd` (`only=sniper,rocket`, `variant=SS-A`, bounded, a watchdog) -> tools/dl/p73/SNIPER/.
Lesson: on the bright sand an additive red glow reads pale yellow; blend red over it.

Lane ART (pass 73), every painting through Garry's running Level Editor queue (port 8787), interleaved with lane
CARDS' card jobs and Garry's own sand-lizard looks; nothing raced ComfyUI from a shell. **The Saiga Sniper** (look
SS-A, now the played look; `fresh` left for Garry's approval): Garry's picture `tools/dl/uploads/2d/Antelope_Sniper.png`
cut into its three figures (tools/dl/p73/art/sniper_front / back / aim.png); the front painted from his front figure
(front_from_picture, 6 Klein seeds, c3 picked: the cowl, the chevrons on the side flaps and the hem, the studded boots,
both gloves on the rifle where his are; every candidate painted the horns golden-amber and the poncho to mid-shin, his
are red-brown and ankle-long); free Wan walks front and back like the Bandit (a long poncho and a rifle held in both
hands fit no Mixamo driver); a Wan fall into a sideways dead still. Two in-job stills failed the frame check although
the vision QA passed them: the back (painted with his back figure as a second reference: a rifle with two muzzles) and
the dead (a barrel in his hand AND a rifle beside him). Every still of the look was then painted as candidates through
the queue with `icon_cands` jobs used as a candidate painter (a reference, the creature style words, "one single rifle")
and picked by eye into the paintings' cache: the back from his back figure (c1: stock up right, barrel and scope low
left, the hem and boots like the front), the aim as an edit of our front still with his aim words (route A c0: eye at
the scope, stock at the shoulder; route B, his third figure redrawn, was closer to his pose but painted a lighter
poncho), the aim from behind as an edit of our back still now aiming (route D c1; route C, the aim turned around,
lighter again), the dead with one rifle on the ground (c0). gen_art gained default-off keys for this (keys_ART.md):
painted attack poses from lane SNIPER's `aim_hint` / `aim_back_hint`, packed as the `attack` strip's front half and
back half (`attack_views: "front_back"`: attack 4 = the pose and a 1 px breath, from the front, then from behind),
placed on the standing figure's feet and height so he neither jumps nor changes size when he stops to aim, and their
browns matched to the walk (`aim_match`: the poses came out 5-7 degrees yellower); `back_ref` (a picture as the back
still's second reference: documented as risky after the two-muzzle back); the walk front scaled 0.955 (`run_scale`:
it stood 4 % taller than the idle with the horns on the cell's top row). Frame by frame (contact sheet
tools/dl/p73/art/saiga_sniper_SS-A_frames.png, the phone-scale row _phone.png, the walks and the death at zoom): no
frame touches the cell edge; the walks keep one figure, one rifle, no face on the back; the fall's third frame is a
motion smear with a bent barrel and the lying frames carry thin colour fringes at 4x (a Wan first-last-frame fall;
death "" would give the clean procedural tilt the Rocketeer and the Bandit have). The icon is the front painting, like
every creature's. Lane SNIPER fitted the beam's muzzle to the aim's barrel. **The totem pole**: the queue has no
structure kind, so the painting came as an `icon_cands` job on the bare id with the style anchor as reference and
gen_props' scenery words (6 Klein seeds; three painted a green frog the green screen would eat); c2 picked (an eagle
thunderbird with red-brown wings tipped black and turquoise over a red face, a bear, a grinning grey wolf and a
turquoise frog on a plank) and finished like gen_props' structures into game/art/sprites/props/st_totem_pole.png;
checked on the sand at the game's scale beside five structures with its grey used state, and in lane STRUCT's world
captures (1.8 m, grey when used). Lessons: the vision QA does not count guns; a two-reference edit whose references
hold different poses mixes them; candidates from one reference plus words, picked by eye, hold the identity and the
gun; a pose painted as its own edit drifts in hue and wants matching to the walk.

**Lane GROUND (pass 73).** **The ground-clip**: `enemy_billboard.gdshader` cuts the part of a creature under the sand
while it rises or sinks along a ragged sand line (the share of the quad under the line rides in the instance basis' z
column, MODEL_MATRIX[2].y: no new buffer; EnemyManager.ground_clip = the painting's drop + (1 − rise_ease) × head) and
dusts the painting just above it with sand; `rise_v[]` (signed: rising at its own rate, sinking hides it at the bottom),
`_tick_rise`. **Growing out of the ground**: map `timeline_data.spawn_rise {seconds 0.45, big_seconds 0.9, targetable
0.7, dust 1}` (WaveTimeline.SPAWN_RISE_DEFAULTS, JsonContent, WaveDirector._apply_mults → EnemyManager.set_spawn_rise;
off without a director): every spawn rises through its spawn state (no walk, bite or attack until up), a dust puff on
the screen (Fx.emerge_dust), big ones (≥ 2.4 m) spraying sand all the way up; the lead's rule (STRUCT's smoke_run caught
the first version, which left rising creatures out of the grid so the revive hit nobody): no weapon chooses a creature
under `targetable` (EnemyManager.targetable guards nearest_index, priority_index, priority_target, random_in_range,
densest_point, screen_ok, the beam's chain, the ricochet and "ahead" picks, the Land Mine's sense, the Orbiter's strike)
but area damage hits it. **Burrows you can see** (`_burrow_begin`, `_tick_burrows`, `_burrow_warn`, `_burrow_erupt`,
`_erupt_throw_hero`, `_erupt_throw_crowd`, `predict_spot`; Fx.dig_ring / dig_spray): a burrow entry's `sink` (in sight,
dust ring, spray, a poof as the sand closes), `rise`, `predict` + `warn` (the Gila: 3 s under unseen, then a 0.4 s ring
where the hero will be in 0.6 s, kept on the map), `mound`, the hero's throw (`throw_up/out/air/control` on his airborne
arc, Player.trampoline_launch; only a hit that landed) and the crowd's (`creature_up/out/damage`: launch with a drift,
3% of max HP on landing). The Gila: windup 4.0 (0.6 + 3.0 + 0.4), throw 2.5 m / 4 m; the Dune Scorpion: sink and rise
0.6, its ring and mound kept, throw 1.3 m / 2 m. **The cactus rain reworked** (BossAttackDef `landing.mode` volley,
`telegraph.all_at_once`, the `spew` group, `windup_seconds`, `volley_times`; the runner's `_custom_lit_*`,
`_custom_marks_*`, `_custom_rain_spots`, `custom_mouth`, `_custom_spew`): every circle lit at once 1.4 s before the spew
(held ground marks, released as each spike lands or with the boss), the Gila crouching, rearing up and spewing big red
spikes (2.72) from its mouth, all landing within 0.25 s on wider circles (1.4 m, spacing 3.9: gaps 1.0-1.2 m, 48% of the
ring covered). **Summons** never specials (`force_plain` round spawn_ring and an erupt's young), +4: the King 16, the
Gila 12, the Brander 14. Level Editor: the Boss attacks tab's new rows and Spew section with the volley preview and facts
(boss_model.js `volleyTimes`, `isVolley`, `litAtOnce`, `windupSeconds`; boss_attacks_io.py DEFAULTS and blank), the
burrow's twelve keys in the attack card (assets_fields.js, vocab.py) and the ring-at-hero warning's exception for
predict, Settings → Spawning's four spawn_rise rows; selftest group `selftest_GROUND.py`. Tests `pass73_ground` (18);
re-pinned on purpose: pass60_en_test (the burrows sink in sight; the Gila's wind-up 0.6 + 3 + 0.4), pass336_test,
pass69_hero_test (the decoy test's elite spawn is set up risen), pass72_boss_test (the cactus rain lit at once),
hell_check (the giant it places is up and its slam due). Captures `tools/dl/p73/GROUND/cap1-3` (`game/tools/_p73_ground_shot.gd`).
perf_late: enemies.render 0.81-0.91 ms against 0.90-0.93 before, no new draw call.

**Lane STRUCT (pass 73): the Stranger without a seam, and the Totem Poles.** Garry: "The Guy who you sacrifice Max HP
to in order to get an item art cuts off weirdly, should be seamless" and "New Structure type - Totem Poles ... a smaller
area ... just as much time ... a choice between 3 small stats improvements for that run ... titled ... like one of those
native American words for animals ... always between 10-12 of them on the map. Signs show to them as well ... a bit
smaller than other Structures ... When used they turn gray as well, but they don't get 'destroyed'". The Stranger had
two seams, both in the pictures: his world painting (`st_hooded_figure.png`) kept the keyed "faint violet glow from
inside the hood" of its prompt as an opaque pale bubble round the hood, outlined like a sticker; and his bargain
screen's cut-out (`art/ui/wanted/stranger.png`) ran off the picture's bottom edge, so his robe stopped on a hard line
over the dim. The bubble and its ring are gone (the hood re-outlined) and the cut-out's lower quarter fades out
(`tools/dl/p73/STRUCT/fix_stranger.py`, originals in `tools/dl/p73/STRUCT/backup/`). The Totem Pole is content
(`content/structures/totem_pole`, effect "totem"): `params.per_map {10, 12, spacing 14}` stands it apart from the
weighted draw (StructureManager.place_apart: the best of 16 fair spots, farthest from everything, off the river's bed
and out of the cover bands), a 1.2 m ring and the usual 3 s, 1.8 m tall (75% of the others' median), no light,
`per_sign 1` (one arm a sign at most), `spent "grey"` (its own painting desaturated in code, standing). Its menu
(`ui/TotemScreen.gd`, Game.Modal.TOTEM): a cedar dim, "★ CARVED SPIRITS ★ / THE TOTEM", the pole's painting, three
carved planks low on the screen in the thumb's reach, each a gift from `params.boons` (11 spirits from Garry's
reference: Le-loo the Wolf move speed, El-kolie the Whale max HP, Chet-woot the Bear attack damage, Thunderbird
cooldown, Ol-hiyo the Seal pickup radius, Walalee the Salmon regen, Frog XP, Skana the Killer Whale crit, Kuuma the
Bullhead armour, Raven luck, Se-sook the Two-headed Serpent area), its amount big on a paper disc, the plain line
("+6% move speed", TextGen) and one to three feathers for how big it rolled (TotemBoons). A pick stays all run
(Run.totem_boons, a sheet source "Totem: <word>"). Lane ART painted the pole (a thunderbird with spread wings over
bear, wolf and frog faces) through the Level Editor's queue. Tests `pass73_struct_test.gd` (13); re-pinned
content_test, pass25_test and pass70_econ_test (structure counts are the draw's); touch_audit `totem` and
`totem_inset130`.

**The line items are fortune cards.** Garry: "The Line Items are weird in that they look like just another set of
Passive Items, while in games like Megabonk the 'Line' items are a distinct object ... For our purposes I thought Fortune
Teller Cards would work best." The 21 lines and their 21 evolutions keep their ids (saves, quests, analytics, the Level
Editor) and every number; to the player they are tarot cards: Brawn is The Sun, Bristle The Thorn, Clover The Star,
Deadeye The Eye, Ducktape The Hourglass, Energy Shield The Guardian, Evade The Ghost, Field Notes The Sage, Gold Tooth The
King, Haste The Tower, Hot Sauce The Devil, Lodestone The Magnet, Mend Temperance, Mule Kick The Storm, Multishot The
Hydra, Prospector The Miner, Slow Burn The Ember (new), Stride The Chariot, Thirst Death, Tin Star The Emperor, Vigour The
Giant (Garry's prompt file named most), and each evolution is its card "Risen" (The Sun Risen; "Ascendant", the brief's
example, ran 817 px on the level-up card's 60 px slab where the column holds about 700; "Risen" tops out at 659). The
flavours read the card aloud in the old wry voice, numberless; the seven card texts lead with the card and keep their
numbers plain; the seven unlock quests of lines carry the card names. tools/dl/p73/CARDS/rename_cards.py wrote the lines
in place (gold_tooth.json keeps its CRLF).

**Card, not Line.** WItem's word CARD ("EVOLVES THE SUN" on an evolution), the Collection tab Cards, the pause screen's
Build group Cards, the arena's ITEMS section Cards, the hero sheet's "Favourite card"; the Level Editor's Items tab
(filter chip, heading, create dialog, the passive form's flag "Card (line item)", the page guide). Two texts that named
cards by hand read the item's name now (PassiveDef.display_name_of): the pause breakdown's Gold Rush source (Run.gd) and
the damage log's star block (Player.gd). The kind glyph on a card's plate (art/ui/wanted/kind_line.png, the file name
kept) is a card tilted 10 degrees with a bold star, drawn by tools/make_kind_glyphs.py line() (the scroll kept as
scroll()); it stays two shapes at the level-up card's 28 px, unlike the revolver.

**Item looks.** Passive items may carry looks like creatures and heroes, icons only: `variants {CODE: {icon, note,
shelved, icon_picked, recipe, painted}}`, `variant` (the look played) and `variant_base` (the look whose icon is the
top-level one). PassiveDef.variants / variant / variant_base / wear_look / look_icon / variant_codes;
JsonContent._passive_variants; build() puts the played look's icon on the def, so every screen (HUD, cards, chest, shop,
Stranger, pause, Collection, results) shows it. Every card has A (the icon it had, an object) and B-E (below); the game
plays **B**: A no longer matched the tarot names (The Sun showed a flexed arm, The Star a clover). On the phone the
arena's ITEMS tab has "Card look: JSON A B C D E" (Save.card_look, kept past the arena's sandbox like a hero's look,
Registry.apply_card_looks at boot and on a tap) so Garry can play every card in another look without a build.

**The four framings, painted.** Garry's references were "a bit too detailed, and they are just cards, which could look
weird in a square icon". tools/dl/p73/cards/prompts.md (written from card_prompts.py, the table the jobs came from): our
icon style crossed with the style anchor's cel shading, one bold symbol per card in two or three colours on its own dark
face colour, a thick border with rounded corners (cream on a base card, gilded gold on a Risen one), nothing written. B a
single card tilted (the least detail), C the card on a small fan of red card backs, D three cards fanned with the card in
front, E the card held up in a black lace glove with a tiny desert horizon (the most detail). A pilot (Garry's four
references and The Sun Risen in all four) through his Level Editor's queue, then all 42 x 4 as icon_cands jobs (B four
seeds, C-E three), six of mine open at a time so his and lane ART's jobs ran between them. Picked by eye on sheets that
show each candidate keyed and finished exactly as installed on the plate the game draws it on at 150 px and the HUD's
52 px (review_cards.py, zoom.py); B cards are turned to one 10-degree lean at install (cardkit.py: Klein leaned them 8
degrees left to 12 right). install_cards.py writes <id>_icon_<b..e>.png and each look's entry with the words it was
painted from. In numbers: 168 jobs, 603 candidates, none failed, 168 picks (sheets/picked_<frame>.png; every look of
every card side by side in sheets/looks_<n>.png; the HUD, a level-up and the pause screen captured in all five looks in
tools/dl/p73/CARDS/shots_final/, sheets/ingame_hud.png). The Magnet's face was simplified after the pilot (one magnet,
two gems: the gems and coins down both sides read as noise at 48 px) and repainted in all four framings.

**Level Editor.** The Items tab shows each card's played look in its list, a "Set every card to look X" bar above the
cards (POST /api/item_looks/set_all: every card that has the look painted plays it, the rest keep theirs; one import),
and in a card's editor its looks at 112 and 48 px with PLAYS, "Play this look" (write_variant_kind takes passives),
Show (the icon preview and "+ Icon candidates" follow it, so a repaint lands in that look) and "painted from"; a
candidate installed into a card's look merges (set_look_files takes a card's icon); the candidate list says which look a
job was for. Server routes need the editor restarted once. selftest_CARDS73.py.

Tests: game/tests/pass73_cards_test.gd; re-pinned on purpose: pass46_passives, pass47_ui, pass49_dummies, pass51,
pass56_ui (the glyph's doc), pass58_uib (three Brawn pins), pass70_lines (the star block's log). touch_audit drives the
arena's Card look chips (arena_card_looks).

**Lane UIPC: the hero plaque at one size, the PC build's icon and version, and why Windows warns.**

*The plaque.* Garry: "The size of the hero plaque in the main menu keeps changing depending on which hero you're
looking at ... It's annoying and it shifts a whole bunch of other UI elements back and forth ... The font size should
be consistent for all the heroes."
- **The cause.** The plaque took its height from its words and its width from its row of numbers and plates. Over
  the eight heroes it ran 167-225 px tall and 745-848 wide; Ironwood's ran 75 px past the screen's right edge. The
  Collections button (a square of the plaque's height, pass 70) and the hero above both moved on every swipe, by up
  to 58 px.
- **Size and sizes.** It is now one 200 px plaque (770 wide on a 1080 canvas) with one set of sizes: name 52,
  flavour 24 (at most two lines), numbers 30, every label 18 (14 before, too small on the phone), plates 84.
- **The insides.** They sit in a plain Control ("Body"), which clips and never grows.
  - The trait's numbers moved from columns beside the plates to a line under the flavour, "+1% CRIT / LV", label on
    the number's baseline (HFlowContainer `_trait`). Ironwood's two take a second row.
  - The plates sit top right (`_stats`, at most two: START and FAVOURITE), "Details ›" bottom right.
- **Code.** drawer_side() returns PLAQUE_H; pass 70's resize loop (_on_plaque_resized) is gone.
- **The hero's room now counts the camera cutout's inset.** With a 130 px inset on a 16:9 screen, the taller plaque
  had pushed the hat into "Drag · Dodge · Survive".
- **Verification.**
  - Every hero was captured in every state (owned / on sale / locked / hidden previewed), both looks, at 1080x1920
    and with inset 130 (game/tools/_p73_uipc_title_shots.gd writes geometry.json too). All 52 shots have identical
    plaque, button, PLAY and hero rects, and every word is inside the Body.
  - pass73_uipc_test pins it: one size, nothing moves, every hero fits at one set of sizes, flavour ≤ 2 lines.
  - pass70's square-button test passes unchanged; touch_audit title, hero_sheet, hero_drawer, hero_buy and
    title_live: 55/55.

*The PC build.* Garry: "Can you make an icon for the PC build".
- **The icon.** The exe already carried Godot's own conversion of the 1024 px app icon, a brown speck on sand at
  16-48 px. tools/make_win_icon.py now writes game/icon.ico with each size framed for its size (the hat filling the
  tile at 16-32), and the Windows preset embeds it.
- **The version.** It had been frozen at 0.50.0.0; it now follows application/config/version because the preset's
  version fields are empty (EditorExportPreset.get_version).
- **rcedit is gone from Godot.** The brief asked for rcedit, but Godot 4.5 writes the icon and version itself
  (PR #75950, merged 2025-06-05). The 4.7.2 binary has no rcedit code, so nothing was downloaded.
- **ship.sh**
  - remakes a stale icon;
  - deletes the old exe before exporting;
  - checks the exe's version against the game's (tools/exe_info.py);
  - signs only when tools/keys/codesign.env exists (tools/sign_exe.ps1: a .pfx, a store or token certificate by
    thumbprint, or a service's command; signtool from the Windows SDK, else Set-AuthenticodeSignature);
  - keeps an exe whose signing failed out of Drive.
- **Tests of the hook.** Run in a sandbox with a throwaway self-signed certificate: no file, a good one, a wrong
  password. A signed exe still boots with its packed game.

*Why Windows warns* (tools/dl/p73/UIPC/trust.md, sources dated):
- The Google Drive for desktop drive (FAT32, virtual) presents every file in My Drive as downloaded from the Internet
  (Zone.Identifier ZoneId=3, measured), so SmartScreen checks each new unsigned build.
- A copy on a local disk carries no mark (tested with Explorer's copy engine and PowerShell) and starts without the
  warning.
- A paid certificate shows his name but does not stop the warning until "hundreds of clean installs". EV lost its
  bypass in 2024. Microsoft's Artifact Signing is closed to individuals outside the US and Canada.
- The Microsoft Store (free for individuals since 2025-09-10, MSIX re-signed by Microsoft, private audience) is the
  one route without the warning.
- Recommendation: buy nothing; run a local copy.

**Pass 74 (2026-10-14, v0.60): the Results show on one clock, the run dashboard made whole.** Two lanes from one contract (tools/dl/p74/INTERFACES.md), after pass 73 was committed as Garry asked: the Results screen keeps its chart block out of sight while the gold counts and pops it in when the count ends, then plays the chart's line, its marks, the Kills and Damage counters and the damage sources together on one clock (each source's row arriving when the line reaches the moment it joined); the local run record went to schema 2 (the look played, the trait, talents, settings, the map's settings, the gold at the end, FPS, totems and their offers, lines apart from passive items, the run's timeline, quest progress, healing by source, specials and Elite modifiers, the bosses' HP scaling, the Stranger), tool runs went to their own folder, and analytics/dashboard.html shows all of it and downloads CSVs (a run's rows, its events, the history, every table; `tools/analytics_csv.py` for every run at once).

**Lane RESULTS (pass 74): the chart pops in after the gold; the line, the counters and the sources play together.**
Garry: "The empty chart shouldn't just be sitting there, it should pop-in after the Coin count sequence is concluded"
and "I wanted the chart, the kill count, the damage dealt and the individual damage sources sequence to play together at
the same time". `ui/ResultsScreen.gd`: while the gold counts, the "Run performance" label, the chart block, the "Damage
dealt" label and every source row wait unseen in their places (nothing on the board moves when they come); a new part
`pop` (POP_TIME 0.3 s) grows the block from 85 % past its size and back (ease-out-back, about 3 % over) while it fades
in, through a CanvasGroup (`_pop_holder`: the panel sits in a plain holder Control, so the board's column never resets
its scale, and in a CanvasGroup while it pops, so it fades as one picture instead of showing its ink shadow and plot
through the paper; `_land_pop` hands it back to the holder once landed, so nothing is drawn twice for the rest of the
show); the two parts "chart" and "sources" became ONE part, still named "chart" (wanted_shots' `_show_at("chart")` keeps
meaning "the chart half drawn"), JOINT_TIME 3.2 s: the line, its marks, the Kills and Damage counters and the rows on one
clock, each row coming in when the line reaches the moment its source joined (`row_times`: the starting weapon's with the
pop, ROW_BEAT 0.12 s between rows that joined together, ROW_FADE 0.2 s; the part runs on only if the last row needs it),
its bar, number and percent at its damage so far (`_row_damage`; the percent of the run's final total, so bars only grow
and end on their share); a run with no story keeps biggest first, spread evenly. `ordered_sources` keeps each source's
ids (`ids`); `core/systems/RunTimeline.gd` gained `source_damage_at(id, at, final)` (the 5 s samples, linear, 0 at the
start, the total at the end, -1 when never sampled); no field of the record changed (lane ANALYTICS reads them). The
first sequence went from about 9.1 s to 6.35 s. Proof: `game/tools/_p74_RESULTS_shot.gd` films the show frame by frame
on its own clock (the screen's processing stopped and stepped: the gold every 0.5 s, the pop every 0.04 s, the chart
part every 0.16 s; a made-up run, its fall, a run with no story; 1080x1920 and inset=130; a watchdog), and
`game/tools/_p74_RESULTS_real.gd` plays a real run first (the Drifter at x4 time with god mode, a down and a debug
revive at 150 s, the 3:35 Elite struck down, the King at 4:00, extraction) and films its Results;
`tools/dl/p74/RESULTS/sheet.py` makes the contact sheets checked by eye. Tests: `game/tests/pass74_results_test.gd` (9),
`pass72_results_test` re-pinned (row 0 unseen before the pop; the parts list), touch_audit's results part unchanged and
green.

**Pass 74, lane ANALYTICS (Garry: "Let's go back to that local Analytics dashboard that tracks individual runs. 1. Update
it so it contains all the info that might need adding or updating 2. Make it so that I can actually download the data as
a .csv file").** *The record, schema 2* (core/systems/RunAnalytics.gd): the header gained the hero's look, his trait as
it ended (name, line, numbers, words), the Upgrade board (each talent's forms), the switches (pierce drop-off, debug
mode, a developer run), the map's numbers as played with the game's defaults filled in (the knockback mult, the
specials' numbers and cap, the boss HP pegging with every reference, priority targets, the rise out of the sand, the
creature mults, the pace, the XP need), the stat words (TextGen), the launch file a tool or the editor's test launch
started from, the gold's end block (PostHog's run_end), the frame rate (a window only), the Totem gifts, the lines (the
fortune cards) apart from the passive items, the build in one line, the Results' story (markers, when each damage source
joined), the counted quests' progress before and after, and the crowd's counters (special and Hot Sauce chests, the Saiga
Sniper's aims, shots, hits, spoiled aims); a row gained the hits by creature, the healing by source (Player.heal's name;
life steal and the level-up patch named by the signals that cause them, heard right after Game heals), regen (never in
`healed`), the specials up and the damage ramp; the events gained the boss's HP and its pegging on boss_start, the
coloured specials (came, forced, fell, chest), creatures wearing an Elite modifier (came, fell with the modifier), Elites
by their kind falling, the Stranger's deals (the item, its cost, max HP before and after) and the ones turned down, and
each Totem Pole's offer (the three gifts, the one taken); a line's passive events say `line: true`. Hooks: one line each
in Player (heal's source, regen), EnemyManager (a marked spawn, a special's death after its chest roll), Game (the
Stranger's screen, the totem's menu, the launch file into create); `totem` and `special_kill` reach PostHog
(`totem_taken`, `special_killed`), nothing else new does. A tool's run (headless or `--script`) mirrors into
`analytics/runs/tools/` with its own latest.js and index, so the dashboard opens on a played run; a phone keeps its newest
50 run files, the PC every one (the lead's rule after the first test run had pruned the PC's user folder to 50: those
files were copies of analytics/runs as far as the counts, the survivors and PostHog can tell; tools/dl/p74/
status_ANALYTICS.md has the evidence). The index row is the header flattened (`gold_end.gold_banked`, `fps.avg`, ...) plus
the sums the history draws. *The dashboard* (analytics/dashboard.html, one file, the vendored Chart.js): a card per
question in plain words: the run (every fact above), was the build strong enough (with special and Elite kills as dots),
crowd pressure, when did the crowd outgrow me, health (falls named by their killer), what hurt me (HP lost and hits by
creature), the last 30 seconds (the Down! list), how hard did each boss scale (its multiplier, the DPS it read against the
reference, its health over the fight), specials and Elites, which weapon carried, estimate against real, how did the build
grow (a lane per item, levels, mutations, evolutions, lines apart), the picks (with the decisions and the pickups
counted), how did I choose (decision times, skips, rerolls, banishes, each card's pick rate), Totems and the Stranger,
where did my healing come from, survivability per minute (now with regen), how did his numbers grow (every stat that
moved, each weapon's numbers at the end), how strong did the creatures get, stacking bonuses, the crowd against the cap,
spawned and killed, progression, gold, quest progress and the history; a Played runs / Tool runs switch; "Where the runs
come from" (the editor binary, the tools, the PC exe's folder, the phone); every card hides itself when its data is
absent, and schema 1 files still open. Fixed: the debug hand's note printed "debug_item" (now its item kind), the
creatures' always-blank hits column (now `hits_by`), the picks' comment that promised pickups (now a counted table), and
a damage-share dip to -300 % after a quiet stretch (the rolling mean's float drift). *CSV*: the toolbar downloads this
run's rows (a line a second, every column, maps as `group.key`, the build's snapshots carried forward), its events (a
line each, every field) and the history (a line per run, every field); every card's table has its own CSV button (raw
numbers, times in seconds); `python tools/analytics_csv.py [--runs <folder>] [--tools] [--out <folder>] [--only ...]`
writes the rows and events CSVs of every run file in a folder and one history. UTF-8 with a BOM, commas, dots, CR LF,
`88fits_<stamp>_<what>.csv`. The page's CSV code and the Python tool were compared byte for byte (Node on the page's own
script) on a v0.51 played run and seven tool runs, and the browser's downloads matched the Python files.
Tests: game/tests/pass74_analytics_test.gd (8 cases); pass45_analytics_test re-pinned at two lines (schema 1 -> 2).
A windowed run driven by game/tools/_p74_ANALYTICS_run.gd (Astro, totems, the Stranger twice, a forced special, Elite
packs, an Elite, heals of every kind, a reroll, a banish, a skip, the first boss, stage 2, a revive, a death) made the
record the cards were checked on (analytics/runs/tools/2026-10-14T15-13-11.json).

**Pass 75 (2026-10-14, v0.61): the Revolver's punch and its trick spin.** Garry: "Let's work on the 3D object of the revolver. The shots still feel sluggish and jerky. Let's make it so the revolver does a little spin every now and then right after firing a shot. There should be much more visible impact on the revolver every time it shoots as well, a bigger punch." Filmed frame by frame first (game/tools/_p75_revolver_shot.gd, fixed 60 fps, a crop round the companion): the old kick (10 cm back, the muzzle tipped 0.28 rad, gone in 0.11 s) went through the companion's eased follow of the hero, which let about 1.5 cm of it through; it showed a frame after the round left (`_tick` places the gun before `_fire` pulls); between shots the gun pointed along the hero's line to the target while its rounds flew along its own, so every shot jerked it round; and from the camera above an upright gun (pass 35b kept it upright: laid on its side it read as sideways) a muzzle tip only shortens it. ProjectileEmitter: a companion whose `params.familiar` carries `kick {back, climb, twist, pop, hz, decay}` keeps its orbit place apart (`_fam_base`, the eased follow) and wears the kick on top of it unsmoothed (`_pose_punch`), on the frame the round leaves (`_start_punch` from `_kick`), as a damped spring past rest (`punch()`: amp x e^(-decay t) x cos(2 pi hz t)); it slides back along its barrel, climbs, twists to a random side and swells (the pop is what reads from above); a round on a kicking gun stacks half of what is left (KICK_STACK_MAX), a silver one kicks SILVER_PUNCH 1.3 times; it aims along its own line between shots and lines its barrel up with each round; `spin {chance, seconds, turns, gap, hop, axis}` (`_maybe_trick_spin`) twirls it about its trigger guard after the last round of a pull now and then, only when the twirl ends before the next pull, never within the gap or during a hip shot (whose twirl now runs on `_spin_len`), heard as the hip shot's twirl. The Revolver and the Golden Revolver carry both (back 0.32 m, climb 0.55, twist 0.14, pop 0.28, 3.2 Hz, decay 9; chance 0.3, 0.5 s, one turn, gap 2 s, hop 0.15 m); every other companion has neither and is as before. Both revolver visuals gained a hot muzzle "Flash" (orange-gold, 0.06 s). New game/tests/pass75_revolver_test.gd (8: the kick on the frame and unsmoothed, the spring past rest and settled, silver harder and capped, the spin follows the pull and ends, keeps its gap and the next pull, the own-line aim, the other companions unchanged); pass48/55/35/46 weapon tests green. Rules: BALANCING.md §22. The first ship stopped on pass64_pl_test's return-spot case, a flake pass 73 had made: it held every return spot 11 m (half the map's 22 m) from every structure, Totem Poles included, while pass 73's StructureManager.find_spot keeps a pole only at half its own 14 m when the search relaxes; a probe of 3,000 spots on its map found 32 breaking the old rule and none the new, so the case now checks the poles at their own spacing (re-pinned on purpose).

**Pass 76 (2026-10-14, v0.62): the Dynamite Stick, weapon looks, the Molotov's flames, the pause stats.** Seven lanes from one contract (tools/dl/p76/INTERFACES.md, read-only surveys first): weapon families got switchable looks (name, words, icon, visual, params; per save in the arena, per game in the Level Editor); the Grenade became the Drifter's favourite and, as its played look B (with C and D as candidates and the grenade kept as A), a Dynamite Stick that lies a second on the sand before it blows, its fuse spark going out half a second before, a slightly wider blast and twice the push, with Dynamite Bundle, Coffin Nails (the red stick), Sticky, the Drifter's new hero mutation Fire in the Hole (a blast catching nine or more creatures mini-crits all of them) and Boomtown; the Peashooter and Fan the Hammer hidden; the Molotov a real bottle and jug with flames on the wick in three new looks (the torch played); the pause Stats tab marks what changed since the run began and lists each stat's sources with icons; the Results screen never announces a hero already owned; the Revolver's tracer a dim brick red, thicker; the Totem Pole's gifts cut to about 0.4 of a card level each and a Claude Design brief for its screen in Drive; Solenne's first badge back and the Level Editor's icon guard (no overwrite, history, revert, a gallery). The lead fitted the Stranger's screen under a camera cutout and the arena's hero labels to hero_state. Known and older than this pass: about one headless game run in four to eight (smoke_run, touch_audit, a gdUnit run that plays) exits with 0xC0000005 while the scene tree is freed after the tool has printed its result (pass 75's code, extracted with git archive and run 8 times, did it once; check_scripts never did in 6); results are unaffected and ship.sh reads the printed result, not the exit code. And `--headless --quit` on the boot scene cuts Boot.gd's threaded title load short, so its preload errors (silhouette.gdshader, blob_shadow.gdshader) are an artifact of quitting on the first frame, not a fault in the files.

**Pass 76, lane LOOKS: weapon-family looks.** Garry wanted the Grenade restyled as a Dynamite Stick "as a Look (with several candidates), so I can switch back to the grenade if I ever change my mind", and the Molotov in several flame versions: pass 73's card looks (icons only, passives only) grew into looks for a whole weapon family. A weapon, an evolution or a mutation JSON carries `variants {CODE: entry}` and `variant_base` (the code its top level is, "A" by default); the weapon's `variant` is the code its family plays (the weapon, its evolutions, every mutation of it, hero mutations too). An entry may carry name, flavour, text (a mutation's), icon, visual, params, noun / nouns, note, shelved and fresh; an entry naming an icon or a visual that is not on disk is left out, as the cards' were. New game/core/data/ItemLooks.gd (no class_name, preloaded where it is used, so no Godot run before the next --import meets an unknown class) reads the entries (JsonContent, never worn there: the .tres keeps the top level) and wears a look in place, as PassiveDef.wear_look puts a card's icon on: display_name, flavour, text, icon, visual, params, noun and nouns become the look's, so every screen, the cards, TextGen and WeaponInstance.fold_params read it with no code of their own, the top level kept aside in `look_top`; a look's params are laid over the top level's one level deep, an evolution's `final` one level deeper, and a null removes a key (`{"final": {"tint": null}}` drops the Golden Pineapple's gold in a look). WeaponDef and MutationDef gained `variants`, `variant_base` (a weapon `variant`, `noun`, `nouns`) and the PassiveDef-style methods (variant_codes, variant_shelved, variant_note, look_icon, look_name, wear_look, look_code). Registry: `item_family`, `item_family_root`, `item_look_codes`, `played_item_look` (the phone's Save.item_looks while the weapon can play it and it is not shelved, else the JSON's `variant`, else the base) and `apply_item_looks` (end of scan, Save.load_save, Save.set_item_look, a wipe; a family none of whose members has looks is never touched); a family whose look changes while the run holds its weapon folds its params again and, in a live run, Run.rebuild_sheets, whose build_changed has Game._sync_weapons make the behaviour again (WeaponBehavior.look_seen / look_stale: its visual, its model and every node made from them are the new look's; one condition in _sync_weapons). TextGen: `weapon_nouns` / `thing_word`: a Lobber's sentence and amount_noun name the look's thing ("Lobs 2 sticks", "jugs of fire"), an evolution without words takes its weapon's, none keeps "grenade(s)". The arena's ITEMS tab has a Weapon looks row per family with two or more looks (JSON and a chip per look, ● on the one it plays; rows ItemLooks_<id>, chips ItemLook_<id>_<code>). Level Editor: ITEM_LOOK_KINDS gained weapon, evolution and mutation (FAMILY_LOOK_KINDS; a family look plays when every file it names is on disk); the weapon record carries `family_looks` (per look the weapon's icon and name and every member's, own or base) and the members follow the weapon's look (play, icon_play, name_play); the weapon's editor (Art) shows the family's looks with Play this look (writes the weapon's `variant`, then an import) and Show; an evolution's or a mutation's says which look its family plays and which it wears (Play this look is refused there); the list cards show the name a family plays under. Tests: game/tests/pass76_looks_test.gd (11, on a test-only family: reading and a missing file, the .tres round trip, the overlay, the family wearing names, icons, params and visuals, a kept look over the JSON and back, the sandbox and a wipe, the nouns, the cards and the fortune cards apart, a held weapon's params and a stale behaviour, the arena's chips, every real family); tools/touch_audit.gd arena_item_looks (a real tap: the look kept, worn, the held weapon remade, JSON back; a stand-in look on the grenade while no family has two); tools/level_editor/selftest_LOOKS76.py (28 checks).

**Lane DYN (the dynamite's rules, the Drifter, the Peashooter).** Garry made the grenade the Drifter's new favourite and
asked for a Dynamite Stick that "sit[s] there for 1 second and then explode[s]", with "a slightly bigger area", "double
the knockback for any of its explosions", "the little fuse light" that goes out 0.5 s before the blast, and a Drifter
special: "Hitting more than 8 enemies at once with the Dynamite guarantees that all those enemies will get a Mini Crit";
and "Peashooter ... Hide it for now". The rules are the same in every look (the grenade A, the dynamite B-D of lane
DYNART). Numbers: lob_grenade area 2.5 -> 2.8, knockback 7 -> 14; golden_pineapple knockback 9 -> 18 (its bomblets and
Frag's spikes push at half, so they double too). New primitive `params.fuse {seconds 1.0, out_before 0.5, lie, spark
{color #FF9A2E, size 0.13}, bomblet_seconds}` in both base params: ProjectileManager marks a fused weapon's lobs
(`_fuse_mark`, the spark's tip from Lobber.model_choice); a shot that lands and is not caught by Sticky lies where it
landed (`_fuse_lie`: a long model on its side along its throw, a squat one sitting, still, resting on the sand; its spot
stays claimed) and blows after `seconds` (`_tick_lying`); one Sticky catches rides in that same pose (`_fuse_ride`). The
spark (one MultiMesh in the blinker's recipe, drawn once in the warm-up: two glows, a four-point twinkle turning in the
camera's plane, a white-hot core, little sparks flung off through Fx.mote, a wisp of smoke as it goes out) burns at the
fuse tip in flight, lying and riding, and goes out out_before seconds before the blast (`fuse_lit`). The Lobber draws
its shot with `params.models[model_form][model_colour]` (stick/bundle, tan/red; Dynamite Bundle sets the form, Coffin
Nails the colour, so a bundle taken before or after is red too), falling back to `params.model`; `refresh_model()`
re-models it when a mutation changes the choice, each model registered once. `params.mass_mini {min_hits 9}`:
`EnemyManager.damage_radius` gained a `flags` argument and `blast_count`; `_explode` counts the creatures a blast catches
before it strikes and mini-crits all of them at nine or more (each bomblet on its own, never Frag's spikes). New hero
mutation `content/mutations/fire_in_the_hole` "Fire in the Hole" (placeholder icon until DYNART's); the Drifter's
favourite is lob_grenade; the Peashooter and Fan the Hammer are hidden (the Pea Cannon and the pea path hide with them).
TextGen: the Lobber's card says "It lies where it lands and blows a second later." ("Each one ...", "One that sticks to
nothing ..." with Sticky) and the mass mini sentence. The Level Editor's params vocabulary (vocab.py, assets_fields.js)
knows the new keys. Filmed in game (game/tools/_p76_DYN_fuse_shot.gd: the grenade look, and DYNART's B models laid in
memory): the shot lying, the spark, its going out, the blast, the Sticky ride, Fire in the Hole's 45s on 30-damage
blasts. Tests: game/tests/pass76_dyn_test.gd; re-pinned on purpose: pass26 (Fire in the Hole on the grenade),
pass46_passives (the grenade's Collection page), pass48_p0 (the whole-path walk on the grenade; an evolution hidden
exactly when its weapon is), pass48_ui, pass45_runflow and pass62_ux (the favourite at level 2 is the grenade),
pass49_dummies and pass51 (the arena's example stack and INFO row are the Skull Rain's), pass56_ui (the grenade's three
and Fire in the Hole as the long mutation offer); touch_audit and arena_check's examples moved the same way.

**Lane DYNART (the dynamite looks).** The grenade family (lob_grenade, new_equipment, frag, sticky, fire_in_the_hole,
golden_pineapple) gained three dynamite looks beside the grenade (A), all `fresh`, on lane LOOKS' engine and lane DYN's
models-by-form drawing; the family plays B. `tools/blender_dynamite.py -- look=b|c|d` builds each look's five models as
one vertex-coloured mesh each (like blender_grenade.py): a stick and a bundle in sandy brown and in red, and Boomtown's
own (B a gold-trimmed crate of nine red sticks that sits up when it lies, C a powder keg in gold hoops with four sticks
strapped on, D a gilded seven-stick bundle under a brass cap with a gold star), the fuse tips in
tools/dl/p76/DYNART/tips_<l>.json, three-quarter reference renders for the icons (tools/dl/dynamite_<l>_<part>_ref.png)
and review renders on sand. B is a classic paper stick (dark rings, cream ends, a pale cord fuse; a bundle of three in
black tape), C a chunky cartoon one (round shoulders, a cream label in black borders, a thick curly fuse; four sticks
tied with rope and a bow), D a waxed miner's stick (crimped ends, a printed band, a silver blasting cap; seven sticks in
copper wire). The 19 icons (the six items in B, C, D and Fire in the Hole's grenade icon) were painted through Garry's
running Level Editor queue as icon_cands jobs (target kind "", at most four of the lane's jobs open so lane MOLO's ran
between; five seeds each, the renders as references, the blue screen), picked by eye at icon size and at the HUD's
52 px and finished like gen_icon_cands' pick (tools/dl/p76/DYNART/: icons.py, q.py, review.py, install.py, picks.json).
The first stick icons read as plain tubes: the words were redone with a big spark burst and a freer fuse. The look
entries (tools/dl/p76/DYNART/looks.py, line by line through content_io) name the family the same in every dynamite look
(Dynamite Stick, Dynamite Bundle, Coffin Nails, Sticky, Fire in the Hole, Boomtown), carry the models by form and colour
on the weapon (Dynamite Bundle sets the form, Coffin Nails the colour, so a bundle is red whichever came first),
Boomtown's model, tip and own colours (its gold tint dropped), a matte paper finish, and under Sticky no amber tint and
no blinking light (Garry: "No need for visual changes to the 3d object"; the spark shows alone). Filmed in game
(game/tools/_p76_DYNART_shot.gd: stick, red, bundle, red bundle, Sticky's ride, Boomtown riding and lying) three times:
the first film showed the sandy brown as orange (a calibration row, _p76_DYNART_colours.gd, proved the game reads a
GLB's vertex colours as sRGB values: the script now writes them so, and the papers were picked in the game's light on
the sand); the second showed sticks flying like darts (a shot spins about the way it flies), so the models are exported
turned a quarter, long across their flight: they tumble like thrown sticks and still lie along the throw. Tests:
pass76_dynart_test (looks, names, icons, models by form and colour, no rule moved, Sticky's paper); pass61_wp1's Sticky
and pineapple tests wear the grenade look on purpose. Lessons: write vertex colours sRGB-encoded for this game; Klein's
"sandy brown" is the peachy CSS sandybrown, fine on the HUD's dark slots; check a 3D shot's paper in the game's warm
light before painting more.

Garry: "Regenerate the Molotov Visuals, the flame looks weird. Make several different versions." Filmed first
(game/tools/_p76_molo_shot.gd: a windowed capture of one throw at a still pack, frame by frame, bounded waits and a
watchdog; tools/dl/p76/MOLO/film0/): the bottle was the passes 17-19 placeholder, a flat amber cylinder spinning like a
propeller (Methanol's white, the Moonshine's a tan cone) whose scene "Flame" sphere was never drawn; the flight flame was
a dotted string of tiny separate tongues dropped every 0.07 s at the bottle's middle and pulled at the camera, so it read
as drips falling off a can; in blue (Methanol, the Moonshine) the same teardrops with a dark blue rim read as water drops,
and the pool was a shadow-like smudge with a few separate candles (raindrops in blue). New: a real bottle and jug
(tools/blender_molotov.py -> art/props/molotov_bottle.glb, molotov_bottle_blue.glb for Methanol, moonshine_jug.glb: clear
glass with the liquid, a tan rag stuffed and tied at the neck with a flap; a round brown jug with a loop handle and a
cloth plug; one surface each in vertex colours, since Blender 5.2's glTF export writes the colours of a mesh's first
primitive only), and a flame that burns AT THE WICK: `params.wick_flame {style, offset, size, rate, life, tumble, ...}`
(core/systems/WickFlames.gd + core/shaders/wick_flame.gdshader, owned by ProjectileManager; the old branch is kept for a
bottle without it) finds the wick every tick as the shot is drawn and stands the flame upright there (the camera's up,
leaning back with speed) while the bottle tumbles end over end, neck up as it leaves the hand. Three styles in one
shader and one MultiMesh (one draw call for every flame, ember and spark in the air): "torch" (a steady licking flame
with a glow and embers flung with the bottle's speed so they scatter instead of lining up), "streamer" (a continuous
tapered ribbon of fire along the wick's last 0.12 s of path under a small flame; its bottle flies base first, the visual
turned a quarter), "cartoon" (a bold three-layer flame in an ink line like the icons', its tongues jumping twelve times
a second, inked star sparks). `params.pool_flame {style, size, life}` burns the pool in the same style
(ElementCloud._flame_at -> WickFlames.ground_flame: the torch's pool flames stand on a flat foot fading out of the spill,
the cartoon's pop up and down; thinned in their own pool of 256). The Molotov family wears looks A (today's), B (torch),
C (streamer), D (cartoon) through lane LOOKS' engine (`variants` in molotov.json, methanol.json, moonshine.json:
`visual` + `params`); the Moonshine's jug and its own wick hold over Methanol's bottle (an evolution keeps its visual);
the family plays B, the torch (`variant: "B"`): it fixes both weird parts and stays in the same visual family as the
creatures' burning flames; C and D are one chip away in the arena (D's inked flame is the icons' and its blue reads best;
its inked pool clashes with the creatures' un-inked fire beside it). The icons stay: the new bottle and jug match them. Lessons: a style code packed with a flag in one instance float must be
read `flat` and rounded (an interpolated 8.0 came out 7.99 on some pixels and sprayed the blue flames with other styles'
colours); a flame pulled towards the camera covers a tumbling bottle (each style now places its own depth, a little
behind the wick); a teardrop with a round foot reads as a drop of water in blue: fire needs ragged tips and a foot that
rises out of the ground. Tests: game/tests/pass76_molo_test.gd.

**Lane UI: the pause Stats tab marks what changed and says why; owned heroes off the Results; a dim red Revolver
tracer.** Garry: "Stats in pause menu. Mark the stats that were changed since the start of the game. Provide some
minimal info on which items are doing the stat changes underneath somewhere. Think like a good game UI designer here and
be inspired by Vampire Survivors or Megabonk." Run.start now keeps the hero's numbers as the run began
(`Run.start_stats`, `start_stat()`: level 1, the Upgrade board, nothing taken; a fresh level-1 sheet after an arena
hero swap). The Stats tab (ui/PauseScreen.gd, data in the new core/systems/StatSources.gd, preloaded by path) became a
two-column grid where every stat that moved since the start carries a change pill (a drawn up/down triangle the way the
number went and how far; sage when better, rock when worse by TextGen._worse, so a cooldown cut is green; said as a
share of the start when every source multiplies, so "Cooldown ▼15%" reads as its "The Tower −15%" row, else in the
value's unit) and every one that did not is dimmed; any other stat that moved gets a cell of its own (weapon speed under
Berserk, Solenne's debuff duration, crit damage...; "word" and "rule" stats never). A tapped cell opens its sources right
under its row as an aged card with a pointer (the Build tab's rows open the same way; the first stat that moved opens by
itself, tapped again it closes, a card scrolls into view): "At the start" (the base, the hero, his signature stat's
level-1 step, the Upgrade board's ranks as one row a form) with the start value, and "This run" (the signature stat's
growth with his level, cards and passive items with their level, perks, mutations, Totem gifts one row a spirit with
"×2", the Stranger's cut, momentum, running bonuses under the item that gives them, timed buffs last with their seconds
left) with the change, each row an icon plate, a name and its summed amount. For that the hero's sheet carries a stable
source id beside every source's words (StatSheet entries' `sid`: talent:grit:0, totem:wolf, trait:solenne...; the words
the older tests read are kept). The five old bugs went with it: talent and totem names lost their first word and three
ranks were three rows; the hero's cooldown and duration read "1.00 s" (TextGen.PLAYER_SHARE: now "100%"); a cooldown cut
was coloured bad; effects aimed at weapons were listed in the hero's breakdown though never in his number
(StatSheet.breakdown in player scope leaves them out); changed stats outside the list were never shown. A tab change
opens at the top. "Result Screen unlocks are showing heroes that I already unlocked": a quest whose reward is a hero on
sale already owned (bought, or the developer menu's "own every hero") is marked done quietly (QuestTracker.owned_reward:
never returned, never in "Unlocked this run", never on the in-run banner, never in "Unlock progress"); FOR SALE and "A
NEW HERO IS FOR SALE" only while Registry.hero_state says "buyable"; "Unlocked this run" holds only the run's own checks
(the title's quiet check no longer adds to it, Run.start empties it). "Make the revolver basic projectile trail thing be
a dim red instead of yellow ... a bit thicker too": the Revolver's tracer_color #7A1F17 (the beads draw lighter than
their hex: it shows as a dim brick red on the sand; #A33A2E showed salmon), alpha 0.85, tracer_size 1.35 (0.9); the
colour order puts a weapon's own plain colour below Silver Bullet and an element, so Silver Bullet keeps its pale blue
and Venom Rounds its green; a new `tracer_clear` (1.1 m on the Revolver) keeps beads off the hero (the dim red laid over
his coat read as blood when his companion gun fired past him). Tests: pass76_ui_test.gd (10).

**Lane TOTEM: the Totem Pole's gifts reassessed, and a Claude Design brief for its screen.** Garry: "also some of the
upgrades are very powerful, can you reassess them please" and "Totem UI. It looks silly. Write a prompt explaining what
it is and how it works. Include screenshots that could be relevant for Claude design." One rule now sets the gifts
(BALANCING §23): a gift's average is about 0.4 of one level of the line item (fortune card) for its stat, a mul stat
measured in multiplier space because mul effects compound ((1 + m)^0.4 - 1), so a map's 10-12 gifts come to about one
maxed line (4 levels); ranges in whole steps of what the screen shows (TextGen rounds a mul to whole percents), the
smallest roll at least a third of the biggest (pass 73's floor), and a span of steps never a multiple of three (pass
73's 3-step percent ranges let a rounding error pick the feathers: the Thunderbird's -3% hung one feather where the
Raven's +4%, at the same place in its range, hung two). Pass 73's gifts averaged 0.67 of a level (10-12 gifts = 6.7-8.1
levels, two maxed lines with no slot taken); now 0.40 (4.0-4.9). New ranges in `content/structures/totem_pole`: Wolf
+1-3% move speed (was 3-7), Whale +2-6 max HP (6-14), Bear +2-6% attack damage (3-7), Thunderbird -2 to -4% cooldown
(-2 to -5), Seal +10-20% pickup radius (8-18: it was under the rule), Salmon +0.1-0.3 regen (0.2-0.5), Frog +2-4% XP
(4-8), Bullhead +1-3% damage reduction (2-4), Raven +2-6% luck (3-6), Serpent +2-4% area (3-6); the Killer Whale's
+2-4% crit was on the rule already; the weights, the feathers' rule, `per_map` and `choices` kept
(`tools/dl/p76/TOTEM/gift_table.py` prints the table). The brief is `docs/ui_review/totem/`: PROMPT.md (what a pole is
and how it works, the gifts' table, today's screen as the thing under review with our doubts, what the screen must do,
genre peers from Megabonk's charge shrines to Hades' boons, the real limits, three directions with mocks), 15
screenshots from `game/tools/_p76_TOTEM_shots.gd` in a real Red Canyon run with a mid-run kit (three chosen offers and
the same under a 130 px cutout, an offer the game rolled, a pole and its signpost, the hero in the ring with the pie,
the toast after a real tap, the used grey pole, the HUD in a fight, the level-up cards and the Stranger as siblings),
an overview sheet, the pole's painting, its grey and its keyed 883 px source, and Garry's word reference; copied to
Drive (`88fits builds/totem_ui_brief/` and `totem_ui_brief.zip`), built by `tools/dl/p76/TOTEM/make_brief.py`. Tests:
`pass76_totem_test.gd` (5: the rule, a map's sum, plain numbers, the feathers by thirds, the weights kept);
`pass73_struct_test.gd` re-pinned (the Whale's 6 and 14 read from the pool).

**Solenne's badge, and the icon guard (lane ICON).** Garry: "Bring back the old Solenne icon, I made a variant of an
Icon and can't find the old one. Make a fix in LevelEditor to make sure that this doesn't happen." What had happened
(2026-10-13 21:11): badge candidates painted for her base (job #a432) were installed into SOL-B, the look in play;
set_look_files wrote `icon: solenne_icon_b.png` + `icon_picked` into SOL-B's entry without a word, and the game puts the
played look's icon on the hero, so the drawer, the sheet and the results showed the new badge; the old
`solenne_icon.png` was untouched but only the other looks' tiles showed it. Fixed: the two keys left SOL-B (she plays
SOL-B with her own badge again; checked in a windowed capture of the title, the hero drawer and the sheet), and
`solenne_icon_b.png` stays on disk. The guard (server.py "pass 76 (lane ICON)": set_look_icon, the one place an icon
changes, for heroes, creatures, cards and lane LOOKS' weapon families): an install never overwrites (a file of its own,
`<id>_icon[_<x>]_<tag>_c<k>.png`, named by the server's install guard and written by gen_badge_cands `--icon-file` /
gen_icon_cands `keep_old`); an icon change of the look in play or the base is a 409 `confirm_needed` until confirmed,
and the page asks first (now -> new, the file names, "the look the game plays", the looks that share the base's
badge); every change goes onto the look's `icon_history` (the base's at the top level) with a copy of the replaced
picture under tools/level_editor/backups/<id>/; "Revert icon" steps back; "All icons on disk" lists every picture of the
asset (the folder, backups/<id>/, removed looks', the older tools' tools/dl/backup/icons*/ copies), one tile per
picture, with "Use for <look>"; look, item-icon and install jobs snapshot the asset's icons first; a re-roll keeps a
picked icon (merge_look, gen_art, gen_ctl). Found on the way: the Jobs tab's and an item's Install sent the candidate's
label ("c2"), which gen_icon_cands read as `<key>_cc2.png` (jobs.choice_id maps it to the id). Tests:
selftest_ICON76.py (87 checks: the guard over HTTP, picks, revert, a picture painted over since, the gallery, Use from
a backup and an older tool's copy, weapon families, the jobs' plan / landing / snapshot, the pick tools on a temp
tree, the page, Solenne's JSON); re-pinned on purpose: selftest_S D8 (the entry also gets icon_history) and selftest_LE70
(the picker installs through LookGrid.installPick); one end-to-end install of the real candidate c2 of #a432 on a temp
copy (tools/dl/p76/ICON/e2e_install.py); the page checked in Chrome on a server copy (tools/dl/p76/ICON/chrome/).
Garry's running editor gets the guard only after he restarts it.

**Pass 77 (2026-10-15, v0.63): the run sim.** Garry: a Level Editor tab that simulates a run for about ten players and averages per-second charts (DPS, HP, deaths, difficulty, coins, damage by source, kills by creature, level, XP), with every multiplier, the cap and the timeline, started by a button. The sim plays the real game: a bot (the difficulty probe's kiting autopilot moved into game/tools/sim_pilot.gd, with sweeps for gems, ring and line dodges, a boss leash, card tiers) runs game/tools/sim_run.gd headless, ten at once on a snapshot of game/ with its own user folder under its own sim lock (tools/sim_batch.py), and the Sim tab (next to the Timeline) shows the averages, the history and a compare overlay. Garry's feedback during the pass was folded in (the hero and the whole Upgrade board, Danger / Keeping up / Close crowd instead of crowd HP and attack, the tab placed, nothing cut off, the dashboard's useful cards). Two rules that counted real time (the Orbiter's repeat hit, the rebuild throttle) now read the run's clock in a sim (Run.rule_seconds; real time on a phone), and the fast sim mode (no drawing) plays level with the full game and replays a seed exactly. The lead took the gold revive off the Down! screen, trimmed the Totem brief to its screen, gave the difficulty probe the run's clock and re-pinned two tests to Garry's map (XP multiplier 4.1, a row starting with the King).

Garry (2026-10-14): a Level Editor tab that simulates a run for ~10 players and averages per-second charts. The lead's
decision: play the real game headless with a bot, so every multiplier, the cap, the timeline, specials, Elites, bosses
and their HP pegging count by construction. This lane built the one-player runner; lane SIMUI the driver
(tools/sim_batch.py), the aggregation and the Sim tab.

**The runner** `game/tools/sim_run.gd` (a SceneTree tool): `out= hero= seed= limit= board= talents= death=end|ad|keep
fast= map= progress= wall= res= unlocks=` (tools/dl/p77/keys_SIMRUN.md). It sandboxes the save (every unlock quest done, the
Upgrade board as difficulty_probe writes it), forces a player's settings, gives the headless window a phone's 9:20
canvas (1080 x 2404: headless Godot otherwise gives the PC's 9:16 "keep" view, 25 % wider, and the ranged weapons pick
only what is on the screen), seeds the dice, launches Game.tscn from memory and plays it to `limit` play seconds or the
end, answering every screen. It writes one JSON of per-second series built from the run recorder's rows in memory
(meta; t, clock, stage, phase, hp, hp_max, dps, est, alive, cap, press_hp, press_dmg, boss_hp, alive_by, gold_total,
gold, gold_by, dmg_total, dmg_by, kills, kills_by, level, xp_total, took, healed, deaths; events), atomically (tmp then
rename), also on a watchdog stop ("stuck:<what>"), and a `<out>.progress` file every `progress` play seconds.

**In the game** (small insertions): `Run.launch_override` (a launch set in memory, taken by Game._read_debug_launch
before the file, which is then never touched: side-by-side processes would race on user://debug_launch.json);
`Run.seed_dice(s)` / `Run.rng_seed` (the global stream, `CardPool.rng` for the offers' and chests' draws, the
director's dice through a hook after WaveDirector.start's randomize); `RunAnalytics.memory_only` (the launch key
`analytics_memory`: `_write` writes nothing, so no user://analytics file, no repo mirror, no latest.js or index) and
`RunAnalytics.xp_total` (Run.xp_gained summed; a new row key `xp_total`).

**The bot**: the difficulty probe's kiting autopilot moved verbatim into `game/tools/sim_pilot.gd` (the probe steers
through it; a test drives both against a frozen copy of pass 62's code, frame for frame), plus the sim's own: a sweep
that leans towards the richest cluster of gems on the field when the way is clear and he is well, a dodge out of the
creatures' red warning rings, and goals (a chest within 30 m, the boss's chest, then the portal; "Not yet" while the
boss chest lies there, stepping out to re-arm it; put on a must-reach goal after 45 s). Cards by tier (an evolution >
the favourite > a new weapon > a held weapon's level > a perk > a new line > a line's level > a passive item, ties at
random), a mutation offer at random, chests taken, the Stranger and the shop left, a Totem Pole's most-feathered gift,
the portal continued, Down! per `death`. Rules and numbers: tools/dl/p77/balancing_SIMRUN.md.

**Lessons**
- The probe's kite alone leaves the gems: it keeps off the crowd's front, which is where the kills fall. It gathered 0.5
  to 0.85 XP a kill and left 85 % of stage 1's XP on the sand until the boss chest's vacuum pulled it in (level 16 to 34
  in one second). A sweep that leans in only when the lane to the gems is clear, scaled by health, brought it to 1.1 to
  1.4 XP a kill, near Garry's own 0.59 run. A pull towards gems "nearby" was not enough: most of the uncollected XP lay
  beyond 14 m, where the crowd had pushed him from.
- Without reading the warnings on the sand the bot died to the Stone Golem's boulders (about 62 of 121 HP a hit) in
  stage 1: a human steps out of the red ring. The dodge reads Telegraphs' live rings by colour (the creatures' and the
  bosses' warnings share the red).
- `--fixed-fps` is the engine's own argument (not in OS.get_cmdline_args): the runner reads the fixed rate off the boot
  frames' deltas.
- A tool cannot name a game class (compiled before autoloads): the runner preloads its helper and the probe by path,
  reads the screens through their own finish paths, and reaches EnemyManager's and PickupManager's private dice through
  the node `ready` signal to seed them after their `_ready` randomizes them.

**The lead's additions (Garry looked at the Sim tab, 2026-10-14 evening)**
- **Talents**: `talents=` (lane SIMUI's format, one 0/1 form a rank, or `<id>:<rank>:<form>`, or `none`) writes the
  board as Save.data.talents[id].picks, so the game folds it as it folds a bought board; it replaces `board=`.
- **Down!**: `death=ad` (the ad revive once while Down! offers it, then the run ends) replaces `gold` (read as `ad`);
  `end` is the default.
- **Difficulty fields**: the recorder's rows gained `near3` / `near6` (creatures within 3 m / 6 m of the hero),
  `hp_lost` / `hp_healed` (the second's loss before healing, and heals with regen) and `boss_now` (the boss's health;
  `boss_hp` stays its share); the per-player output gained near3, near6, boss_hp_abs and, for lane SIMUI, hits,
  spawned, mult_hp / mult_dmg, took_by, healed_by, held_by and the bot's `pick` events.
- **The fast mode** (`fast=1`, the default): Run.sim_mode, set for each run from the launch's `sim_fast`, skips the work
  that only draws or plays (the crowd's, the shots', the pickups' and the ground marks' drawing, Fx, sounds, the HUD
  and the damage numbers' frames, the hints) and keeps every rule; the sheet's rebuild throttle (Desperado, Steady
  Hand, Hot Streak: 250 ms) reads the buffs' clock in it instead of real time. The profile (`profile=1`, Perf's
  buckets) before it, headless at 60 fps: a frame 3.4 to 4.4 ms in stages 1 and 2, of which the crowd's simulation
  about 1.1 ms, its drawing 0.5 to 0.6, the shots' drawing up to 0.5, the hero 0.4, the HUD, Fx, the pickups' drawing
  and the marks less than 0.1 each, and about 1 ms outside every bucket.
- **Repeatability**: one seed did not replay: Audio.play gates repeats on real time and draws a random pitch from the
  global stream, so how many draws happen hung on the machine's speed, and every later crit and drop moved (fixed by
  the fast mode, which plays no sound). With it the managers' own dice seeded too, two runs of one seed matched frame
  for frame for seconds, yet still parted now and then: not a race but the structures' unseeded dice and a weapon
  companion's bob on real time (round 2, below; a fast run now replays exactly); `trace=` prints a state line a frame
  for the next hunt.

**Measured (2026-10-14/15, this PC, headless, --fixed-fps 60, one process at a time)**
- A full 25-minute player (Drifter, a quarter of the board): before the fast mode 562 to 569 s of wall time (seed 21:
  gold, keep); the same seed on the final code 482 s with fast=0 and 345 s with fast=1 (28 % less, 4.3 play seconds a
  wall second against 2.7), the boot about 13 s either way. A player that dies at its first Down! (end) on 5:38: 91 s.
  Ten players to 10:00 one at a time: 163 s each in the full game, 114 s fast (30 % less). Lane SIMUI's ten players side
  by side to 25:00: 18:10 in the full game, 10:23 in the fast mode.

**Round 2 (2026-10-15 night): the two modes, the clocks, the seeds, the boss**
- **The two modes compared** (pairs of one seed both ways; a seed never replays across them, so only the spread over
  seeds compares them): level with each other to 5:00, then the full game pulled ahead (level +3.7 +- 1.3 at 7:00 over
  28 pairs) and further in the first boss fight, where the fast player's King lived longer, mostly when both held an
  orbiter. A code review of every path the fast mode skips found only drawing and sound; the cause was the clock.
- **The run's clock.** Two rules counted real time (Time.get_ticks_msec): an Orbiter's repeat hit on the same creature
  (its `cooldown`, 0.2 to 0.4 s: Orbit Saws, Branding Iron, Rattlesnake and their evolutions) and Run's rebuild
  throttle (Desperado, Steady Hand, Hot Streak, 250 ms). A headless run goes about 2.7 times real time in the full game
  and 4.3 in the fast mode, so the saws hit a creature 2.7 or 4.3 times less often than on a phone in every sim before
  this, the difficulty probe's included (its Drifter builds carry the Orbit Saws). In a sim both now count the run's
  own clock (Run.sim_clock, the launch's `sim_clock`, which the runner always sends; Run.rule_seconds = buff_clock); in
  play nothing changes. After it, ten pairs to 10:00 (seeds 71-80) end level (level +0.2 +- 1.4, kills -40 +- 390 at
  10:00), so the fast mode is the runner's default again (it was off from 00:15 to 01:55 while this was open).
- **Seeds that replay.** Two fast runs of one seed parted at 0:05: StructureManager.setup randomized its dice, so the
  structures stood elsewhere every run, and the barrels, placed clear of the structures' rings, with them. Seeded from
  the run's seed in a sim (and the Totem Poles' gifts from Run.totem_rng), the runs went on together to 3:14 and parted
  on the Big Mouth's damage: its beam starts at its mouth (LaserBeam.muzzle), whose bob ran on real time. With every
  weapon companion's bob on Run.rule_seconds (a look in play), a fast run replays exactly: seed 66 to 5:00 and seed 73
  to 10:00, twice each, every row and every pick equal. The full game does not replay (its sounds' gaps run on real
  time and each sound draws its pitch from the global dice): same seeds on two versions of the content are a paired
  comparison only in the fast mode.
- **The boss leash.** A boss log (a scratch tool, deleted) showed the bot's sweep leading him 40 to 60 m from the King
  while it followed at 1.3 m/s, so the first boss fight lasted 3 s or 6 minutes by where the gems lay (the King lost 1 %
  of its HP in two minutes in one run), and the boss chest's vacuum, 10 to 18 levels at once, came that much later. While
  a boss lives the bot now keeps within 10 m of it (walking back from further, to 7 m) and walks only to gems and chests
  near it: seed 73's fight went from 169 s (and 37 to 152 s in its other replays) to 26 s; over six seeds 8 to 88 s,
  median 20, against 30 to 169 s. Close to the King the bot ate his rolls and volleys (3 deaths to him in 6 runs, none
  before): the dodge read only red rings, so it reads his red lines too now (Telegraphs' strips: the roll, the spokes,
  a charge's or a spit's line); seeds 72, 73, 76 then lost no life to him (fights of 92, 17 and 9 s).
- A regression found by the whole suite and fixed: the recorder's near3/near6 read the crowd's `pos` and the hero's
  place straight, and two analytics test files feed it a stand-in crowd without `pos` (5 failures); it reads them
  defensively now.

**Lessons (round 2)**
- A rule that counts real time plays differently in a headless run, which goes several times faster than real time:
  before trusting a sim's number for a weapon, grep the rules for Time.get_ticks_msec. A look can reach a rule too: a
  companion that bobs on real time and is where the weapon fires from.
- An unseeded RNG anywhere upstream of a rule breaks replays: structures placed at random also moved the barrels placed
  around them. To find the next one, run one seed twice and diff the rows: the first second that differs, and the
  weapon or creature whose numbers differ first, point at it.
- A seed does not replay across the two modes: the full game draws its looks from the global dice (Fx's particles, the
  sounds' pitch), so the modes part in the first seconds and only many seeds compare them (pairs, signs, standard
  errors).
- The first boss is a hinge for the bot: it leaves most of stage 1's XP on the sand (5,000 to 11,000 XP lying at 7:00 on
  the content before the 00:41 import, about 2,500 after it), so the boss chest's vacuum lifts it many levels at
  once; how fast the boss falls decides when. A curve averaged over players shows that as a slope, a single player as a
  cliff.
- Garry tunes the map while a batch runs: the Registry reads `red_canyon.tres`, which changed between the batches at 00:41
  (an import of a map edit; the JSON changed again at 01:18), so batches either side of it played different content. Compare pairs within one
  batch, never across batches, and note the content's import time with a batch.

**Pass 77, lane SIMUI: the run sim's driver, its job and the Sim tab.** Garry asked for a Level Editor tab that
"simulates a run ... like 10 players (editable) and the output is the average", per-second charts of DPS, HP, deaths,
difficulty (the crowd's HP and attack alive and who is in it), coins, damage by source, kills by creature, level and
XP, "considering the multipliers and all the enemy, cap and stuff", started only by a button. The sim plays the real game
(lane SIMRUN's `game/tools/sim_run.gd`, a bot over a headless run), so no second model of the rules exists.
`tools/sim_batch.py` drives N runs K at a time: it copies game/ into `tools/dl/sim/snap/game/` (by size and mtime, the
.godot seeded once, the snapshot's project.godot given its own user folder `88fits_sim`), imports the snapshot only when
an imported asset, a uid, a new scene or a script's class changed (11-14 s; a no-change sync takes 1.4 s, the first copy
30 s), runs import_json on the snapshot for every content JSON newer than its .tres (so the sim plays the saved JSON even
when the editor's import was queued), then runs `Godot --headless --fixed-fps 60 --log-file ... --script
res://tools/sim_run.gd` per run with seed + k - 1 and a wall-time cap, judging each run by its JSON (one run exited
0xC0000005 at teardown and counted). It holds its own `tools/dl/locks/sim.lock`, never the Godot lock: the snapshot is
another project folder, so the editor's saves, imports and the tests are never blocked by a sim. It averages every
second of play into result.json (means over the runs still playing, DPS smoothed over 5 s per run, p10/p90 bands,
deaths over every run, breakdowns, the stage and boss times as medians, a summary from each run's own end), rewritten
after every finished run so a cancel keeps a partial result, and keeps the newest 10 sims plus kept ones. The job kind
`sim` runs on a new fourth lane `sim` (jobs.py: sim_plan / sim_stages / sim_parse / sim_eta / sim_title / sim_check;
mode "sim", no lock), its card showing every run's clock; `sim_io.py` serves /api/sim/settings, status, history,
result/<id>, run, keep, delete, cancel, unlock. The Sim tab (`sim_model.js` page-free + `sim.js` + `sim.css`): the
settings (hero, runs, at once up to cores - 2, stop at, Upgrade board, on death, seed, note), Run sim (Save and run with
unsaved map edits), the progress first in the column while it runs, the history (Show, Compare, Keep, Delete), the
header (which save of the map it played, the version, when, how long), stat tiles (runs that reached the stop, the
median end, deaths, level, kills, coins, each boss beaten of met with its fight and HP pegging), and twelve hand-built
SVG charts in Garry's order with the stage starts and boss fights marked, each saying what it shows and how it was
averaged, one hover cursor shared by every chart with the values under each, a compared sim in grey dashes, Table and
CSV per chart. Colours: the editor's validated dark series slots in a fixed order, splits folded to 7 + Other, the
creature charts sharing one colour map. Measured on this PC: see the report (the first default sim with SIMRUN's bot of
21:30 ended every run by a death at 1:48-3:09 in 1:47 of wall time; 10 full runs of 25:00 "keep playing", 6 at once,
in the time noted there). `selftest_SIM77.py` (132 checks): the averaging by hand on three tiny runs and on made-up ones,
the snapshot's rules, the lock, the job with a real run of the driver (`--synthetic`) and a cancel, the routes, the page's
maths under Node and its wiring.

Lessons: Godot's output reaches a redirected file line by line (a pipe or --log-file both flushed at once in a test);
--log-file per run keeps parallel runs off a shared user://logs. A short test sim plays only the light early game (6.7
play seconds a wall second against ~3.5 late): it must not feed the ETA.

**Pass 77, lane SIMUI, round 2 (Garry's notes on the first Sim tab).** The tab moved right after Timeline. The hero's
Upgrade board is set talent by talent (rank 0-6 and form each; presets none / a quarter / half / full as the difficulty
probe plays them, and "my save" read from the PC save, or the kept copy while a tool has it aside), sent to every run
as `talents=<id>:<picks>` (A/B a rank, lane SIMRUN's new argument), checked against what each run played
(meta.talent_forms) and named in the header when it differs. The death policies are end (the default), ad (one ad
revive) and keep; gold is gone with Get up with gold (an older sim's label still reads). The page offers only what the
runner knows (read off sim_run.gd's argument parser: talents=, fast=, the death list), and the run route and the driver
refuse a custom board or a policy an older runner would misplay. Crowd HP and attack (which counted the boss and every
hit at once) gave way to Danger (health lost a second as % of max HP, before and after healing, 5 s), Keeping up
(seconds of the run's own DPS to clear the crowd without the boss, and the boss alone: a median, since a crowd over a
DPS jumps where the DPS is small) and Close crowd (near3/near6); from the run dashboard came what hurt the hero, hits,
healing by source, the crowd against the cap, spawned and killed, the creatures' strength and the build's growth, each
drawn only when the runs carry its data (SIMRUN accepted all eleven requests). The page became one scroll in five
sections (Garry had found the bottom charts cut off: the settings column was an inner scroll area; plots now stretch
with their card and are redrawn on a width change). The ETA comes from speed records of the runner's current mode, at
the slow runs' pace, and the progress card's from the runs' own pace; a line under Run sim says why a sim takes what it
takes. At once defaults to auto (as many as the runs, at most cores - 2). A **Drawing** switch (shown when the runner
has `fast=`) sends `fast=0`; result.meta.sim_mode records what the runs played and the header and history say
"everything drawn". Measured on this PC, 10 runs of 25:00 (keep playing): 23:39 with 6 at once before the sim mode,
18:10 with 10 at once and the sim mode off, 10:23 with 10 at once and lane SIMRUN's sim mode; the default settings (end
at the first death, 10 at once, sim mode) 9:04, two runs reaching 25:00. selftest_SIM77.py: 181 checks.

Lessons (round 2): ten runs at once end with the slowest (one run at 1.41 play seconds a wall second against a median
of 1.98 made the 18:10), so the ETA plays a round at the slowest run's pace, not the median's; a sim where most runs
die early must not feed it either (its two survivors ran 2.9x with the PC to themselves, which would have promised a
full sim in 9:42 instead of 10:23). The same seeds 1-10 with the sim mode on (22:37) and off (22:47, after SIMRUN's
round-2 fields) levelled differently: at 10:00 the mode-off run was higher in 9 of 9 untied pairs (38.5 against 31.9
on average, kills 18.0K against 15.7K at the end); the runner changed between the two, so this alone does not say the
sim mode changes the game, but lane SIMRUN's same-seed A/B is the check that settles it.

**Pass 78 (2026-10-15, v0.64): run records through PostHog, the Sim's charts in the dashboard, averages.** Garry: "I want to see the equivalent of this local dashboard ... for one player in particular or as an average for several players ... save raw data in some kind of JSON ... download it ... dress it up into one of my HTML reports", and the Sim's charts in the local dashboard with matching formats. One lane (tools/dl/p78/INTERFACES.md): every run that sends analytics now sends its whole record as gzip+base64 `run_record` parts; tools/posthog_runs.py downloads them into analytics/remote/; analytics/dashboard.html opens them (Remote runs: one run, the ticked runs averaged, every run of the ticked players), shows the Sim's charts for any run from the Level Editor's own modules (sim_model.js, sim_avg.js, sim_plot.js) and averages with the sim's rules ported to JS (equal to tools/sim_batch.py). Shipped once after passes 77 and 78, as Garry asked.

Garry: "Add those charts [the Sim tab's] to our Local Run Analytics dashboard so their formats match", and "Looking at
Posthog I'm realizing that the dashboards have a very distinct limit ... I want to see the equivalent of this local
dashboard ... for one player in particular or as an average for several players ... save raw data in some kind of JSON
... make it so that I'm able to download it. Then take that data and basically dress it up into one of my HTML reports."

**The Sim's charts in analytics/dashboard.html.** The Sim tab's drawing moved out of tools/level_editor/sim.js into
tools/level_editor/sim_plot.js (SimPlot: the sections, the cards with Table and CSV, the SVG plot with the boss crowns,
stage lines, stacks, bands, the compared run dashed grey, one hover cursor and the readouts), unchanged; sim.js hands it
its state. The dashboard loads sim_model.js (the definitions), the new sim_avg.js, sim_plot.js and sim.css from
../tools/level_editor/ (one copy for both pages), and draws them for the open run in a folded section under the summary,
"The Sim's charts for this run": the same names, units, colours and explanations. sim_model.js words a ONE-run result
("for this run", no bands, no "Runs still playing"); a record without a key (before v0.63) hides that chart.

**One schema for sims, local runs and remote runs.** tools/level_editor/sim_avg.js: `fromRecord` maps any run record
(schema 1 or 2, played, a tool's, downloaded) onto the Sim's per-player schema with game/tools/sim_run.gd `series()`'s
own mapping (JS == GDScript exactly on a committed fixture: tools/level_editor/testdata/dash78_series_in.json ->
game/tools/series_fixture.gd -> dash78_series_out.json; pass78_dash_test re-checks the GDScript, selftest_DASH78 the
JS); `aggregate` is tools/sim_batch.py `aggregate()` in JS (Python's rounding as pyRound: equal to round() on 160,000
values; the whole result equal to the Python's on made-up runs and on the four real p77 sims, 10 players x 1500 s).

**Averages.** The dashboard opens several files or a whole folder (new *Open a folder*); "Runs you opened" ticks them:
Average (the Sim's charts over the ticked runs, every readout saying how many runs are behind that second, tiles, the
runs one by one with Open), Overlay (the old cards, the first run with up to three dashed; the Sim's charts compare with
the first overlay). *Compare with a sim* lays a sim's result.json dashed grey over any view; a sim's player files average
like runs. A view switch One run / Overlay / Average.

**Every player's runs from PostHog.** The game sends each run's whole record at its end as `run_record` events
(Analytics.record_parts: gzip + base64, parts of at most 100,000 characters; a 25-minute run is 2 parts, ~142 KB), with
the run's properties and the dev flag, only with the play-data card answered yes and never from a tool, the test runner,
the arena or the switch off; a quit sends it at the next launch; a run the phone kills after its checkpoint is sent at
the next launch as "killed" (user://analytics_pending_run.json); a request carries at most 400,000 characters.
`python tools/posthog_runs.py [--player <name>]... [--since <day> | --all] [--list] [--force] [--out <dir>]` lists the
parts with HogQL (cheap: no payloads), fetches the new ones, joins and checks them (sizes, md5), and writes
analytics/remote/<player>/<stamp>_<run id>.json (the record exactly as sent, plus a `remote` block: player, label,
install, received, parts, dev, recovered) with a .js twin and analytics/remote/index.js (window.REMOTE: players and the
index rows). The dashboard's new *Remote runs* switch lists the players and their runs: Open one (every card), Average
the ticked runs, Average every run of the ticked players, leave out developer runs. analytics/remote/ is git-ignored;
the personal key stays in tools/posthog_personal_key.txt (never printed or written). How-to:
analytics/howto/03_remote_runs.md.

**Checked end to end.** A windowed dev run of the editor binary (Astro, the Game scene from a debug launch, 31 s of
play until the first level-up screen waited, then the window closed by --quit-after): the record queued on the way out,
sent by the next launch (HTTP 200), `posthog_runs.py` fetched it (1 part, 1.2 MB read) and wrote a file identical to the
local one (header, 31 rows, events), and the dashboard opened it under Remote runs with every card and the Sim's charts,
and averaged it. Full-size parts through PostHog: a 25-minute record's two parts (100,000 + 33,256 characters) sent as
`run_record_probe` events (a name nothing reads) came back identical.

**Also**: tools/analytics_csv.py and the page's CSV columns gained pass 77's row keys (xp_total, hp_lost, hp_healed,
boss_now (empty without a boss), near3, near6), still byte for byte the same; analytics/SCHEMA.md (the pass-77 row keys,
`result: killed`, the `remote` block, the run_record event), analytics/README.md and two lines of docs/analytics_plan.html
(a run's whole record now goes to PostHog) brought up to date.

Tests: game/tests/pass78_dash_test.gd (9: the parts' keys and a 25-minute record in 2 parts, the round trip in any order,
refusals, the run's properties on run_record, only with consent, never from the test runner / switch off / arena / no
key, the killed run at the next launch, the request cap, the recorder's wiring, the series fixture);
tools/level_editor/selftest_DASH78.py (54: rounding, JS == Python averaging, JS == GDScript series, fromRecord, Python
joins the game's own parts, the downloader on recorded API answers, the page's wiring); selftest.py 18,634 green;
pass45/57/59/60_lead/61_an/74_analytics/77_simrun green; check_scripts 0 errors; smoke_run OK; the CSV compare OK.

**Pass 79 (2026-10-15, v0.65): mutations at level-ups, bodies that fly, line trails, a duskier rim, the dynamite thrown ahead.** Garry: "the mutations happen whenever there is a level up" (asked which, he chose: the offers stay one per weapon per stage, but come as a hero level-up's screen in place of the three cards, "but decrease the level requirements to achieve the same power level"); corpses that follow through with their push and fly from blasts "like the live ones"; a thin line trail like the rocket's instead of the beads (the regular shot dark red and see-through, Silver thicker in its own colour, fading like smoke); "Map the sides are too orange"; "Throw the dynamite in front of the enemies"; and an opinion (answered in chat, not built) on a bot-played Watch tool. Three lanes (tools/dl/p79/INTERFACES.md, brief_MUT.md): FX, WORLD, MUT. The lead swapped the old bead keys for the line's in the Level Editor's weapon fields.

Lane MUT (pass 79; Garry: "Mutations are supposed to be level ups, not just random occurrences"; his pick: the offers
stay, one per weapon per stage, but come as the level-up screen in place of the three cards; "decrease the level
requirements to achieve the same power level considering the changes"). **Delivery:** the director no longer opens a
mutation offer on the clock: `Run.mutlvl_tick` (WaveDirector, Phase NORMAL) spends a `path_times` slot as `path_due` did
and keeps the offer due (`Run.mutlvl_due`) when a weapon has a pick open (else it is spent with nothing, as before);
`Run.add_xp` claims a due offer at each level (`mutlvl_claim`: a mutation level-up, `mutlvl_ready`, counted in
`mutation_levels`; no weapon open -> the offer dropped, an ordinary level-up); `Game._show_next_level_cards` opens a
claimed one as the path offer (`Game._mutlvl_open`: `Run.mutlvl_take` draws the weapon among those open then, the reel,
the path cards, `_on_path_chosen`; one whose weapons lost their pick while banked opens as three cards,
`mutlvl_unclaim`); offers queue one a level-up and stay due across a stage's end; never in the arena.
`CardScreen.path_level` puts "Level N! Pick a mutation" on the head (`CardScreen.mutlvl_line`). `Game.present_path_offer`
stays for tools (screenshot_run). **The mark:** `HUD._build_mut_mark` / `_refresh_mut_mark` (on
`Run.mutation_due_changed`, `build_changed`, `stage_changed`): the LV plate in `W.PLUM` with paper letters and
MUTATION NEXT at the XP rail's right end while `Run.mutlvl_pending()`; `HUD.mutation_mark_on()`. **Card levels:**
`Run.card_level()` (level less mutation level-ups) for the creatures' level factor (WaveDirector._apply_mults,
fixed_numbers), the hero's trait (Run._build_player_sheet; StatSources' "Lv N", RunAnalytics `trait`), BarrelField's gems,
Ram's per_level (EnemyManager), Supply Drop's damage_per_level (Game); the map's `mutation_levels_scale` (WaveTimeline,
JsonContent; default false) counts every level-up instead. **XP:** Red Canyon's `xp_need_mult` 3.1 -> **1.65** (Garry's 3.1 of his 12:46 Level Editor save was "today"; 4.1 at HEAD, 2.1 before 2026-10-15): fitted at 1.64 on a 20-player 3.1 sim, confirmed by a 20-player sim of the new delivery at 1.65 (three-card level-ups by any minute within about two of today's over 0-24 min, the mutations the same, the badge about 13 levels higher by 20:00); against the brief's first baseline 4.1 the fit gave 2.0, confirmed the same way. A shape key
`xp_curve {base, linear, quad}` was built and dropped (one scalar holds within about two levels over 0-25 min).
**Measured** with the run sim on lane MUT's own snapshot (tools/dl/p79/MUT/simprep.py: `--sim-dir tools/dl/p79/MUT/sim`,
the snapshot's red_canyon.json patched and its .tres removed, `--delivery old|new` flips the snapshot's director line
so before and after run the same code otherwise; fit.py fits xp_need_mult so the same XP buys the old curve's level plus
the mutations taken by then; compare.py the before/after table): Drifter x20, 25:00, death keep, board a quarter.
Garry's local records (analytics/runs/) were all older versions at xp_need_mult <= 2.1 and mostly tool runs, so the
sims carried the measure. **Level Editor:** path_times is "Mutation offers per stage" with the new meaning, the timeline
lane "Mutations", the inspector's "Mutation offers", xp_need_mult's help, a "Mutation levels scale" switch (Scaling).
**Docs:** docs/design/src/part2.html (Mutations' first bullet, Evolutions: level 5 + all three path mutations),
docs/waves_schema.md "Pass 79". **Captures:** game/tools/_p79_MUT_shots.gd (HUD plain / marked / the level-up's reel /
landed / after), wanted_shots `only=hud_mutation` (06e-hud-mutation-next). **Tests:** game/tests/pass79_mut_test.gd (11:
a due offer waits for the level-up, queued offers one a level-up, nothing open -> spent or an ordinary level-up, a banked
claim whose pick went opens as cards, due across a stage, never in the arena, the card levels for the creatures and the
trait, the map's pace and switch, the Game's level-up showing the offer, no pick open -> three cards, the director never
opening a screen on the clock); re-pinned on purpose: pass56_ui (the XP rail holds one node now, the hidden
MutationNext word); pass26's comment only. pass27, pass46_pacing, pass62_pc pass unchanged (path_due and path_times kept).
Whole suite 1,800 green (before the value moved to 1.65; the map tests read the file); smoke_run, arena_check, touch_audit (cards, path, path_offer, gate_strip, resume_gate 44/44)
green; Level Editor selftest green (18,644).

### Pass 79, lane FX: bodies that follow through, tracer lines that fade like smoke

Garry: "Let's add a knockback to corpses from explosions. It should be that enemies that die have their corpses follow
through with their knockback. So when an explosion kills an enemy fly off like the live ones." and "Change the projectile
trail. The balls aren't good. Make a simple line trail, similar to that of the rocket. Should be thin. 1. Regular shot
dark red transparent 2. Silver - thicker, correct colour. 3. Then the line disappears like smoke."

**Bodies.** `EnemyManager._die` used to zero the push (`kb`) and the dying tick never moved the body, so a blast's kills
dropped where they stood while the survivors flew. Now `_die` calls `_corpse_begin`: the body keeps its push (the boss's
is zeroed: his death is as before) and the dying tick's `_corpse_tick` slides it on, decaying at the live crowd's own
6 /s, clamped to the arena and the ground, sliding along rocks. `damage_radius` marks the creature it is striking
(`_corpse_blast_i`, saved and restored round each hit, so nested blasts from kill effects stay right); a body killed by a
blast with a push is thrown up (`CORPSE_TOSS_PER` 0.3 m per m/s of push, capped at 2.5 m, none under 0.3 m), falls at
22 m/s², sails with an air drag of 1.5 /s and lands in a little sand; its death is stretched to the flight plus 0.6 s.
Big game slides but is never thrown; a body up in a launch keeps its launch fall and Bucking Bronco's drift as its push;
a body killed up in a tornado's toss or a bounce now falls instead of hanging there. Captures (tools/dl/p79/FX/final_corpses):
the dynamite throws a pack of skeletons 0.75-1.4 m up and ~1.2-2.4 m out, Powder Keg 0.6-0.85 m up and ~0.9-1.3 m out.

**Lines.** The tracer beads (pass 60/61/76) are gone: every `tracer` shot lays a line of segments (`ProjectileManager
._tracer_tick` / `tracer_segment` / `_tracer_lay`), one every 0.3 m it flies, into one MultiMesh ring of 2048 quads drawn
by `core/shaders/tracer_line.gdshader`. Each instance transform carries data, not a placement (origin = the piece's
start, basis x = the piece, basis y = (the end's birth, life, width), basis z = (the start's birth)), so the shader turns
each piece to the camera, keeps it at least 1.5 px wide, and fades it on the shots' clock: alpha (1 - f)^1.5, widening to
1.9x, drifting up 0.45 m/s, swaying by its world position, greying 40%. A frame costs one uniform; a new piece two
instance writes. The two ends of a piece are dated when the shot passed them, which removed the seams the first capture
showed where pieces met; the sway follows the world position for the same reason. Colours are converted from sRGB in the
shader: the bead material had read every tracer colour as linear, which is why pass 76's "dim red" #7A1F17 showed as a
salmon terracotta and the Silver Bullet's SILVER as a pale white-blue. New key `tracer_width`; `tracer_clear` now cuts
the line where it crosses the hero's circle; `tracer_size` / `tracer_step` / `tracer_beads` draw nothing. Content: the
Revolver #8B0A0A at 0.9, 0.045 m, 0.9 s; Silver Bullet and the Golden Revolver's final form #C9DCEF at 0.9, 0.11 m;
Drum Mag 0.065 m; the Boomstick's and Blunderbuss's pellets 0.035 m. Warmup draws one piece under the beam
(`warm_draw` -> `_tracer_warm`). Lessons: a dark see-through colour over bright sand turns brown under linear blending
(a red needs ~0.9 alpha to read red: the "transparent" comes from the thin line and the fade); a camera-facing ribbon
made of separate quads needs its shared ends to be identical (same age, same sway) or every joint shows.

Perf (tools/perf_late.gd, 504x1122, fixed 60): build=six 10.07 ms/frame before, 15.02 and 12.23 after, but every system
the lane did not touch rose by the same factor (enemies.sim 2.38 -> 3.77 / 3.12, hud 0.08 -> 0.13 / 0.10: the machine
was busier with the other lanes); projectiles + projectiles.draw against enemies.sim stayed 0.21 -> 0.22 / 0.21. The A/B
in one sitting (game/tools/_p79_FX_perf.gd, build=six_b, ~80 shots in the air from the Bullet Hose and the Doomstick):
lines on 1.26-1.33 ms projectiles, 0.46-0.48 draw, 192-194 draw calls; every tracer off 1.19, 0.45, 188.
The Level Editor's vocab.py: tracer_step and tracer_size out (nothing reads them), tracer_width, tracer_clear,
tracer_color and tracer_alpha in.

Tests: game/tests/pass79_fx_test.gd (16). Re-pinned: pass60_wp (the Tommy round's line in place of beads), pass61_wp1
(Toxic Peas' green line, Drum Mag's bolder line in place of three beads), pass76_ui and pass48_projectiles (the
Revolver's colour read off the content; Silver Bullet's and the Golden Revolver's own silver colour).

**The map's sides less orange, the dynamite thrown ahead of the crowd** (Garry: "Map the sides are too orange";
"Throw the dynamite in front of the enemies.").

*The sides.* Captured first (game/tools/_p79_WORLD_shots.gd: a real run of Red Canyon, seed 11, the hero at the north,
east, west, south and north-east rim at the play zoom and pulled out, the middle at full zoom, a spent Totem Pole stood on
the rock, a dozen creatures on it, stage 3's red ground; windowed 1080x1920, every wait bounded, a 200 s watchdog;
tools/dl/p79/WORLD/before/). On the screen the rim's rock read hue 25, saturation 0.65, value 0.80 (orange), the boundary
wall and the cliffs the same orange. The rim was orange twice over: the flat tone (0.62, 0.34, 0.24) and an orange rock
painting (redrock.png, bands (146, 70, 48)..(196, 112, 70)) under a warm sun and sky; the cliffs were tints over an
orange sandstone painting, so no tint could take the orange out. Now the terrain shader recolours the rock painting to
the rock colour (its luminance over its mean, `rock_tex_lum` 0.184 linear, times the colour taken into linear light: the
Compatibility renderer hands a source_color vec3 over as authored, which the first try missed and drew the rim
salmon-white), and sandstone.png is grey bands (gen_textures.py, new `--only`), so a colour key is the colour drawn.
Eight palettes were tried in the game (tools/dl/p79/WORLD/pal*, palettes*.json) and compared by eye; the pick is a dusky
red-brown (rock #785C5E; walls near #856B6E, far #705963, farther #594A57, stone #7A6363, light #8C7370, cap #544045,
riser #47383B, boulders #6B5457): on the screen the rock reads hue 22-24, saturation 0.53-0.56, value 0.66-0.67, the wall
and the cliffs saturation 0.52-0.53 (from 0.62-0.67), the sand untouched (pinned by pass54_world and pass61_map). The
authored colours lean a touch rosy because the warm light pushes everything towards orange. Stage 3's hell still turns
the rim a clear red (hue 15). A spent (grey) Totem Pole still reads on the rock; the creatures (the orange fire ants
most) read better on it than on the old orange. The colours are map keys: timeline_data `rock_color` and `wall_colors`
{near, far, farther, stone, light, cap, riser, boulders} (WaveTimeline, JsonContent, RedCanyon._read_colours, defaults
RedCanyon.ROCK_COLOR / WALL_COLORS = the file's), in the Level Editor's World card as swatches (forms.js `own`: an
empty box shows "the game's" default faded; selftest_WORLD79.py).

*The lead.* The Dynamite Stick aimed at the densest creature's spot and lay a second on the sand after its flight, so a
crowd walking at the hero had passed the spot when it blew. `params.lead` (lob_grenade and golden_pineapple) throws it
where the crowd will be: the wait (the lob's flight + the fuse; a Sticky bomb only the flight) times the crowd's walk
(EnemyManager.crowd_velocity / crowd_speed / walk_velocity, new), capped at 6 m, kept 1.5 m off the hero, in range and
in the arena; a Sticky throw at a priority target (the Golden Pineapple's) stays unled; a led shot's crowd spot rides
along (`lead_from`) and is claimed with the led one, so two bomb weapons still pick two crowds. The contract's straight
extrapolation (the crowd's mean velocity x the wait) was probed first (game/tools/_p79_WORLD_lead_probe.gd: the same
window of Red Canyon per seed, the lead off then on, every blast's creatures counted as it goes off) and caught FEWER
with the run sim's kiting pilot (6.38 -> 5.81 a blast, 5 seeds x 60 s): the hero moves and the crowd turns after him.
Whole runs differ from one another more than the lead changes them (one seed: 5.4 or 6.7 a blast), so the probe
scores every blast at every candidate spot at the moment it goes off (the paired count): on the same blasts the plain
lead caught no more than none (walk +0.03, chase +0.18 at level 5 with the kiting pilot; standing -0.2): the crowd near
the hero is a stream and the blast (3.8 m at level 5) is wider than the lead (about 2 m). What wins is aiming at the
spot where the most creatures will stand when it blows: "predict" (the default) scores five spots from the chosen one
to the chase lead (each creature near closing on where the hero will be at its own pace, EnemyManager.predicted_counts)
and throws at the best, the one further ahead on a tie. Paired: +1.29 (L1 kite), +0.83 (L5 kite), +0.59 (L5 standing)
creatures a blast over unled. Real runs, 6 seeds x 60 s each way: level 1 kiting 8.61 -> 9.00 caught a blast, kills a
minute 77 -> 88 (+14%); level 5 kiting 5.95 -> 6.48, kills 334 -> 353 a minute (+6%); level 5 standing 8.56 -> 8.84,
462 -> 473 (+2%). Lesson: score an aim on the same blasts (a paired count), never on separate runs.

Tests: game/tests/pass79_world_test.gd. Files: RedCanyon.gd, terrain_painted.gdshader, WaveTimeline.gd, JsonContent.gd,
gen_textures.py + sandstone.png, red_canyon.json (+ .tres), Lobber.gd, EnemyManager.gd (three new functions),
ProjectileManager.claimed_spots (one insertion), lob_grenade.json / golden_pineapple.json (+ .tres), the Level Editor
(fields.js, settings.js, forms.js, vocab.py, assets_fields.js, selftest_WORLD79.py).

**Pass 80 (2026-10-15, v0.66): the Watch, an explorer bot, the wisp tracer, a sandstone fort wall, two or three oases.** Garry: "For the 'Watch' tool, proceed with implementation of it. For the Player 'bot' add a desire to explore the map and interact with totems and barrels ... Sometimes chase power-ups, sometimes chase structures. Add option to interact with the Shop and the Stranger"; "The revolver trail looks awful ... Search the internet for a better option"; "make the edges of the map just sand ... that orange-dark stuff should be behind the walls ... the textures on the mountains behind the walls look too low res ... Make the walls look like sandstone castle walls (but western)"; "make the water slow everyone down ... just 10%. And ... 2 oasis at least per level generation ... sometimes 3"; "There is some z-fighting on the sign 3d"; and how to fly the camera round the map (answered in chat: the editor's Game tab, 3D mode, camera override; the map is built in code at run time, so its .tscn shows nothing). Five lanes (tools/dl/p80/INTERFACES.md): BOT, WATCH, TRAIL, WALLS, OASIS. The lead added the water to the run record.

#### Pass 80, lane BOT: one reusable bot that explores, uses the map's things and explains its choices

Garry (2026-10-15): "For the Player 'bot' add a desire to explore the map and interact with totems and barrels, as they
are an important part of the progression. Sometimes chase power-ups, sometimes chase structures. Add option to interact
with the Shop and the Stranger Structures, etc." The bot is shared by the run sim (pass 77) and the Watch (lane WATCH).

**The move (milestone 1).** The run sim's bot left game/tools/sim_run.gd (the screens, the goals, the sweep) and
game/tools/sim_pilot.gd (the legs) for game/tools/bot/: Bot.gd (the API of INTERFACES.md: `BOT.new(game, opts)`,
`tick(dt)`, `intent`, `goal`, `decisions`, `signal decided`), BotLegs.gd (sim_pilot's code; sim_pilot.gd is now one
`extends` line, so the difficulty probe and the pass 77 tests steer exactly as before), BotCards.gd (pass 77's tiers and
the new scores), BotGoals.gd (the planner). sim_run.gd keeps its CLI and its output; its static helpers forward. Proven
behaviour-neutral: preset=sim77 replayed the 10 baseline players (Drifter, a quarter board, 25:00, death=keep, seeds 1-10)
exactly, every series and event (tools/dl/p80/BOT/compare.py base_head m1_sim77 --exact).

**The planner.** One goal at a time by utility = value x the run's taste for the kind x the kind's mood for this 2-minute
spell x a fixed jitter per thing x the style's word / (1 + distance / 18 m), so two runs of a seed agree and seeds differ
("sometimes power-ups, sometimes structures"). He knows a structure, a Totem Pole or a barrel only once it has been within
12 m of him (nothing points at them in the game: exploring finds them); the arena is a grid of 11 m cells and explore
walks to the unseen. Values: a Totem Pole 80, a barrel 10 (black 28, x1.6 with Barrel Rush), a chest 70, explore 30 x
the dial x (0.5 + the share unseen), power-ups by effect (a heart by how hurt he is), structures by what they give (the
Healing Well by how hurt, the Uber Magnet by the XP lying, the Shop only with gold to spend, the Stranger only above 60%
HP, the Teleport only in trouble), the gems lying as the sweep (their worth over the next level's XP, capped at 45). A
goal is kept unless one 1.4 times better turns up, given up after 8 s + 0.55 s a metre (+ its use time) and rested 40 s;
far goals give way to low health and recent damage (75 m at full health, 12 m at a third); the kite wins while the crowd
closes (5 within 3 m, a big one or a rocket close, or hurt with one inside flee distance); he stands still in a ring to
use it. The musts stay pass 77's (the boss's chest, the portal, the boss's leash).

**The scores.** Every card, mutation offer, chest gift, shop ware, the Stranger's ware and Totem gift: dps (the game's
own estimate, WeaponInstance.dps_estimate, on temporary instances: the new weapon, the next level, the mutation added,
the evolution; stat effects through a copy of the hero's sheet with every weapon rebuilt on it; crit as expected damage),
survival (a table of points a unit, times the danger weight 0.6..2.1), plan (an evolution, the favourite, a level, the
last level, a new weapon while slots are free, a mutation, the path's last), greed (XP, magnet, luck, gold). The style
weighs the parts; skill reads every score with a gaussian error of (1 - skill) x 25 points. The Shop buys the best ware
less its price (0.03 points a gold x greed's weight) when that is 6 or more; the Stranger's deal is taken above 60% HP
when the ware beats the cut (15% x 0.8 points a % x survival's weight) by 5. Each decision is an entry with every option's
score and parts and a reason in a player's words ("+18% DPS: Tommy Gun to Lv 4", "a weaker pick: ...").

**The dials.** reaction (a warning younger than it unseen, the danger push seen that late), dodge (the share of warnings
seen, a fixed roll each), daring (the kite's 4.5 / 2.6 m at 0.5), stray (the sweep's reach), boss (leash / free), explore,
the six "use it or leave it" switches, cards (score / tier). Presets: sim77 (pass 77's bot), explorer (the default for
the Sim and the Watch), careless, expert.

**Everywhere.** sim_run.gd args (BOT_ARGS), meta.bot (options, metres, goals, seen, the map tallies) and bot_decisions in
each run file; tools/sim_batch.py `--bot` and the settings' `bot`, result.json's `bot` block (means and per run); the Level
Editor's Sim tab "Bot" group (presets, every option with its effective value and where it comes from), the history line,
the head card's map tallies, the runs table's "the map" column; jobs.py carries the job's bot field to `--bot`.

**Measured** (10 runs each: Drifter, a quarter board, 25:00, every fall counted, seeds 1-10): the Explorer used 9.6 of
the 10-12 Totem Poles a run (9.1 by 20:00), broke 26 of 33 barrels (pass 77's bot 17), used 6.7 other structures (0.8),
saw 93% of the arena, fell no more than pass 77's bot (median 6.5 falls against 8.0; three runs of ten never fell), and
had about 3% less XP and two levels fewer at 25:00 (the gems wait while he walks to a pole); kills and gold the same.
Careless falls most (median 13.5), Expert least (3.0). Lesson: a utility in raw XP grows with the run and swamps every
other goal by minute 8 (5.8 poles a run): the sweep's worth is now over the next level's XP, capped.

#### HISTORY.md paragraph (pass 80, lane WATCH)
**The Watch** (Garry, pass 80: "For the 'Watch' tool, proceed with implementation of it"; the design he approved in pass 79,
tools/dl/p80/REQUEST.md). A PC window (1920x1080, resizable) with the real game on the left at a phone's 9:20, scaled to
the window's height, played by lane BOT's bot (game/tools/bot/Bot.gd), and on the right a dark panel (the Level
Editor's style): the header (hero, board, seed, the bot's preset, the clock and stage, the speed buttons), ten live
numbers (real and estimated DPS, HP, Danger, Keeping up, creatures close, kills, level and XP, gold, the crowd against
the cap), four charts over the last 3 minutes or the whole run (DPS against the crowd's HP, HP over Danger, level and
XP, the damage share stacked) with the Sim's average of the same hero and board as a grey line (--ref auto: the newest
Sim result), the bot's decision log (each pick's offer with scores and parts, the reason, and the real DPS 30 s after
against the 30 s before, filled by the Watch), the build with a strip of when each item came, and the threat (what hurt
him in the last 10 s, every fall with its killer and last hits, the bot's intent and goal); afterwards the run's
record lands in analytics/runs/tools/ (the dashboard opens it) with <stamp>_decisions.csv beside it, and the window says
where. How it lives with the game, nothing changed in it: the Game scene in a SubViewport (own World3D,
size_2d_override = the phone's canvas) shown through a TextureRect, so no window input reaches the hero; started by a
SceneTree script (game/tools/watch/watch_main.gd) so the tree's current scene stays empty, and the Game freed the frame
its end_run starts (the record already written, its 1.2 s wait for the Results scene dropped with it). Speed
(WatchClock.gd): pause, 0.25x to 8x, step one second, run to the next level-up (8x until the cards are up, paused before
the bot picks). Godot runs --fixed-fps 60, so a frame is one 1/60 s step; up to 1x Engine.time_scale slows it (composed
with the game's own hit-stop and Last Stand); above 1x the frames come 60 x the speed a wall second with the step
unchanged, drawn 60 a second (30 from 4x on), and the frames not drawn skip the drawing work (Run.sim_mode set per
frame). Found on the way: --fixed-fps turns the engine's frame limit off (Main::iteration returns before
add_frame_delay), so the Watch paces its frames itself (OS.delay_usec), and the drawing work on frames nobody sees cost
half the frame (4x reached only 2x until sim_mode skipped it), and the Watch processing always had lent that mode to
the game (the crowd moving behind the level-up cards) until its SubViewport was made pausable. When a run falls short
of the speed asked, the drawing steps down to 30 frames a second (tried again at the full rate every 20 s). Speeds
reached on this PC (16 logical cores, RTX 4070; Drifter, a quarter board; measured while lane BOT's 10 sim players
and other lanes' Godot runs shared the CPU, 11-13 Godot processes): 0.25x, 0.5x, 1x, 2x exact early; 4x held to about
1:40, then 2.3-3.3x with 100-160 creatures up to 5:00; 8x 4.2-4.4x early, 2-3x mid-run, about 2x at 19:00 (where 4x
also gave 2x, and 1x 0.8x: drawn frames 19-21 ms, plain ones 6-8 ms there); the header shows the reached speed in red
when it falls under 90 % of the asked one. Launch: `tools\watch.cmd` (Drifter, a quarter board, a random seed), `python
tools/watch.py --hero ... --board ... --seed ... --bot key=value`, or the Sim tab's Watch button (POST /api/sim/watch);
each Watch plays on its own snapshot (tools/dl/watch/snap, user folder 88fits_watch, lock tools/dl/locks/watch.lock: one
at a time), never the Godot lock or the Sim's. Tests: game/tests/pass80_watch_test.gd, tools/level_editor/
selftest_WATCH80.py.

#### CLAUDE.md commands line
```
python tools/watch.py [--hero drifter] [--board none|quarter|half|full|save|<ranks> | --talents grit:AAB,...] [--seed N|random] [--speed 0.25..8] [--limit 5:00] [--bot key=value ...] [--ref auto|none|<result.json>] [--wait --timeout S --autoquit --shots DIR --shots-at 60,120 --actions p30:pause,w5:go --profile]   # pass 80: the Watch: one bot-played run in a PC window (the phone view left, numbers/charts/the bot's decisions right; Space, 1..6, +/-, ., L, G, M), on its own snapshot tools/dl/watch/snap (user folder 88fits_watch, tools/dl/locks/watch.lock, never the godot lock); tools\watch.cmd double-clicks it; the Sim tab's Watch button; the record + <stamp>_decisions.csv in analytics/runs/tools/
```

#### CLAUDE.md status line (Analytics or the tools paragraph)
Pass 80: the **Watch** (game/tools/watch/, tools/watch.py, tools\watch.cmd, the Sim tab's Watch button): the real game
in a SubViewport played by the bot (tools/bot/Bot.gd) beside a panel of live numbers, charts, the decision log, the
build and the threat; speeds pause..8x on --fixed-fps 60 with its own frame pacing (the reached speed in the header
when short); the record to analytics/runs/tools/ with the decisions as CSV.

**Lane TRAIL (pass 80): a better tracer.** Garry: "The revolver trail looks awful, I don't like it at all. Search the
internet for a better option than this, I want a clear visible trail, but one that doesn't look this bad." Pass 79's
line (a 4.5 cm, 0.9 s dark-red hairline that greyed, drifted up and swayed) read on the sand as a scratch or a hair. The
research (tools/dl/p80/TRAIL/research.md: Riot's VFX style guide and its missile breakdowns, Shannon McSheehan's
two-layer trails, tracer and stretched-billboard practice, the additive-on-light-ground problem, survivor-game clutter)
says: one focus at the head with the most contrast, a hot core in the weapon's colour, short and riding with the bullet,
tapered, alpha-blended on a light ground with a darker edge for value contrast, no lingering clutter. Four looks were
built into the same draw path (one MultiMesh ring, one shader; the style and its hot part ride in each segment's
transform, basis z): streak, ribbon, wisp (the streak over a pale smoke), toon (hard bands with a dark outline), with
pass 79's line kept as a fifth; `params.tracer_style` picks one per weapon, mutation or evolution (`tracer_hot` the hot
part), each with its own life and width unless the weapon sets them. Filmed on the same shots (the Revolver, Silver
Bullet, the Tommy Gun, the Boomstick) at 1080x1920 and at phone size (game/tools/_p80_TRAIL_shot.gd, sheets and GIFs in
tools/dl/p80/TRAIL/), the **wisp** was picked and made the default: a crimson (#C41E16) streak, hot at the bullet and
tapering to a point, with a soft halo, and behind it a pale warm smoke that fades in half a second; it keeps Garry's
pass 79 idea ("then the line disappears like smoke") but reads at phone size and never looks dirty. Silver Bullet's
trail is 0.3 m and its light silver gets a steel-blue edge (light colours get a darker body, edge and halo of their own
hue). The lead's review: the gold guns read as fat cream sticks with an orange outline (mostly the rounds themselves,
pass 60's 0.95 m cored boxes): the rounds and pellets were slimmed to a short white-hot tip in a thin amber halo, the
gold trails made thinner (0.1 m, pellets 0.08) with a deep amber body and a white middle only at the tip (a light
saturated colour's own rule), and the many-shot guns' smoke shortened (Tommy Gun and Chicago 0.3 s, pellets 0.25 s). Lessons: on the Compatibility renderer a `varying flat` made the whole shader draw nothing (no error printed), and
PROJECTION_MATRIX[1][1] is negative when drawing to a render target, so pass 79's "never under 1.5 px" floor never
applied (abs() now). Perf: perf_late build=six before/after in the report.

**Pass 80, lane WALLS (sand to the wall, real rock, a western fort wall, the sign's z-fighting).** Garry: "Let's make the
edges of the map just sand instead of that dark orange stuff, that orange-dark stuff should be behind the walls. Also the
textures on the mountains behind the walls look too low res and walls don't have any proper textures to begin with. Make
the walls look like sandstone castle walls (but western), instead of what they are now." and "There is some z-fighting
on the sign 3d. Fix it". (1) Sand to the wall: RedCanyon's terrain colour takes its red-rock weight from the new
`rock_weight(p)` (0 inside arena_radius + ROCK_FROM 0.4 m, 1 outside), so the sand runs to the wall's foot and the red
rock (`rock_color`) is only the strip between the wall and the cliffs; the rim still rises 2.2 m from rim_start 44 m but
as drifted sand (new exports `rim_bumps` 0.45 m, `rim_bump_freq` 1.4; were 1.2 m of broken rock at 2.5x); pass 79's
stair-stepped rock edge on the sand is gone. (2) The cliffs: a hi-res rock painting (art/env/cliff_rock.png, 2048 px,
VRAM compressed with mipmaps, anisotropic), painted by Flux.2 Klein on the AI server and made seamless by
tools/gen_wall_textures.py (new: candidates; seamless by rolling the picture by half and repainting the seam cross under a
soft mask with DifferentialDiffusion, which fixed Klein copying the seams from its reference; a grey mean so the
`wall_colors` tints stay the colours drawn); the three rings (new game/world/maps/red_canyon/CanyonWalls.gd `ridge`) get
UVs in metres (14 / 20 / 28 m a tile, strata level, nothing stretched; triplanar is gone) and two rows of relief that
break the faces into ledges; their on-screen colour unchanged (hue 26-27, saturation 0.53). (3) The boundary is a
western sandstone fort wall (CanyonWalls `fort_wall`): dressed blocks (art/env/fort_wall.png, 1024 px, Klein, seamless,
3.2 m a tile), a battered inner face weathered darker at its foot, a cap course, a walk 2 m up stepping 0.25 m with the
ground, a parapet with rounded Spanish-colonial merlons, vigas every 1.7 m (one MultiMesh) and a squat tower every 30
degrees standing out past the outer face; same footprint and height, no collider (the fence 1.1 m inside is unchanged),
the posts and skulls kept, the boulders gone. It is drawn unshaded with its light and shade in the vertex colours (the
sun stands in the north-east, so a lit wall showed the camera its dark side round the north half); stage 3's hell tints
it with the ground (RedCanyon.HELL_WALL). `wall_colors` re-meant (stone the blocks, light the trim, cap the walk, riser
the shaded sides) and `boulders` replaced by `beams` (the vigas); defaults a warm buff sandstone picked by eye from six
palettes (#C59E7B, #DEC09F, #A58266, #7A604E, #4F3626), Red Canyon's file and the Level Editor's World card updated; the
invisible fence no longer loads the old sandstone painting (4 MB). (4) The sign: sign_depth.gdshader kept 2% of the
sign's whole depth, so the board's stub and its part inside the post lay a millimetre behind the post's face and
flickered through it; the depth a vertex owes to its height keeps `squash` 0.02 and the depth it owes to its run over the
ground keeps the new `squash_h` 0.25 (a hero beside the post still draws over a board pointing at the camera); the nail
heads stand 12 mm proud (blender_sign.py, sign.glb regenerated). A diagnostic (game/tools/_p80_WALLS_shots.gd
`only=signdiag`: each sign alone with the game's depth against true depth) measured the sign's mis-sorted pixels
5.45% -> 0.40% at the play zoom, 2.76% -> 0.30% pulled out (single edge pixels left). Cost: the same draw calls,
+19.7k primitives, -0.7 MB of texture; perf_late build=six unchanged within noise. Captures (before / after, pairs in
tools/dl/p80/WALLS/cmp/), the palettes, the texture candidates and the tools in tools/dl/p80/WALLS/. Tests:
game/tests/pass80_walls_test.gd (12); pass79_world_test re-pinned on purpose (the cliffs' rule only, the beams key, the
cliff painting's grey mean, the stacked wall's helpers removed); selftest_WORLD79.py's keys re-pinned.
Lesson: a depth trick that squeezes a mesh's own depth must keep enough of it for the depth buffer at the camera's
farthest zoom (here 24-bit, near 0.05 m: about a millimetre at 25 m); squeeze only the component that causes the
sorting problem.

**Lane OASIS (pass 80): two or three oases, and water slows everyone by 10%.** Garry: "make the water slow everyone
down when they walk though it, not by a lot, just 10%. And make it so there are 2 oasis at least per level generation
in the red canyon, sometimes 3". Red Canyon keeps its lakes as packed arrays (`_lake_cs/_rs/_ys/_floors`); the first is
rolled with exactly the draws of the one lake before (a seed keeps its first oasis: seed 5's at (28.5, -2.5)), then
`_roll_oases` adds the others from timeline_data `oases` {min 2, max 3, extra_chance 0.35, gap 10}
(WaveTimeline.OASES_DEFAULTS): each like the first (5.5-7.5 m, 24-48 m out, off the flats by 8 m and the dry river by 5
m past its radius) and its dish (1.6 x the radius, LAKE_DISH) 10 m of open ground from every other lake's; over 2,000
seeds 1,298 rolled two and 702 three (35.1%), the gap never had to relax. Every lake has the dish, the damp ring (vertex
colours: the terrain shader was not touched), its own disc ("Oasis", "Oasis2", "Oasis3", one material) and its palms
and green. The API: `lakes()` [{center, radius, level, floor, disc}], `lake_count()`, `lake_index(p)`, `in_water(p)` in
any lake, `water_level(p := INF)` / `water_disc(p := INF)` for the lake at or nearest p (no argument = the first, so old
callers are unchanged; an optional parameter on an override of MapBase.water_level() parses in 4.7), `lake_center()` /
`lake_radius()` the first. Every caller reads every lake: Game._tick_water (ripples round waders in each lake at its own
level), Game._sink_hero (the disc nearest him, `_discs_of` / `_nearest_disc`), EnemyManager (the lake block keeps a list:
`_lakes_wet/_disc/_thick`, the first still in `_lake_c/_lake_r2/_disc` for the old tests; `map_lakes(map)` reads any map,
`lakes_of`, `lake_turns` over every lake, `ring_spots` cuts every lake's arc out with `_dry_arcs_many`, `_clear_in`
checks every lake, the render's shadow test `_near_water`), WaveDirector through lake_turns; everything that only asked
`in_water` (barrels, structures and Totem Poles, signs, flowers, the Trampoline, the Game's spot finder) keeps out of every
lake unchanged. Three oases took so much of the sand that 3 seeds in 60 laid four bush patches (pass 61's rule is five to
seven): past 200 of its 300 tries a patch may stand 6 m (BUSH_LAKE_NEAR) + 0.6 of its radius off the water instead of
11, and a map still short of five gets 200 more tries out to 10 m inside the wall (200 seeds: all five to seven). The
slow: WaveTimeline `water_slow` 0.1 (a map that names none plays it; 0 = off). The hero: `planar *= _wade_mult()` after
the stick lock (1 in Hang Time's flight or more than 0.35 m over the ground, never his `_kb`). The creatures: once a tick
`_wade_tick()` asks the crowd's grid who stands in each lake and marks `_wade_k` (not one in the air, rising or sinking,
hidden, held or dying), and the walk is `vel[i] * _wade_k[i] + kb[i]` (a push never slowed); a first version asked a
per-creature function and cost 120 us a tick for 250 creatures, the marks cost 33 us (tools/_p80_OASIS_bench.gd); perf_late build=six (seed 7, one lake before and three after)
read enemies.sim 3.96-4.37 ms before and 4.28-4.74 after, but an A/B on the same code (tools/_p80_OASIS_perf.gd oases=1 vs
3) read 4.04-4.25 against 3.65-4.15: the oases do not show past the machine's noise. The
rocketeer's rocket still keeps to 90% of his dry speed, so wading he cannot outrun it (named). Level Editor: five World
rows (water_slow, oases.min/max/extra_chance/gap) and selftest_OASIS80.py. Tests: pass80_oasis_test.gd (the roll over
400 seeds, the built map's lakes, the crowd's lakes and rings, the creature's and the hero's 10%, the exceptions);
pass61_map_test re-pinned (a patch against every lake, the relaxed bound). Captures: tools/dl/p80/OASIS/overview/
(top-down, seeds 3, 5, 6, 7, 11, 88, and seed 5's third oasis close). Tools: tools/_p80_OASIS_probe.gd (the roll over many
seeds), _p80_OASIS_scatter.gd (patches per seed), _p80_OASIS_overview.gd (the overviews), _p80_OASIS_bench.gd. Lesson: a
`--script` tool that names a class touching an autoload (EnemyManager) fails to compile and the process then waits
forever, holding the Godot lock: load such classes at run time.

**Pass 81 (2026-10-15, v0.67): oasis water, Megabonk-like sand, wave pacing, bee dashes, the production build.** Garry: "Make the water look more like water ... a cheap shader", "Make the sand texture a bit better. Bit more like what it looks like in MEGABONK", "a bit of a ground texture shading around the water ... like an oasis", the structures' radial ring's black line; in the Level Editor "the ability to control the pacing of the waves" with "yellow etches" on each row at its spawn times ("If it's continuous ... a continuous yellow line"); how the Scorpion that turns into 4 was set up (answered in chat: an Elites-every event that rolled the Splitter modifier on a Lesser Scorpion; a Coloured elite event with Modifier Splitter, a wave's Elite modifier, or the rows' Elite weight make it on purpose); the bees' trails ("look up what could work well here"); "the Rocket 85% of the heroes speed"; the Saiga Sniper "too zealous with his running away ... like ... the Cactus ranged enemy, but with a bit more speed"; and "a production build version ... no debug options, no extra art ... smaller and faster. Create a skill ... only make a prod build if I ask for it." Four lanes (tools/dl/p81/INTERFACES.md): MAP, PACE, POLISH, PROD. The lead put the PC save back after a stray smoke run had banked into it.

**Lane MAP (pass 81): water that looks like water, a calmer painted sand, the oasis ground, the ring's black line.**
Garry: "1. Make the water look more like water. Maybe a cheap (in terms of performance) shader. 2. Make the sand texture a
bit better. Bit more like what it looks like in MEGABONK. 3. Do a bit of a ground texture shading around the water.
Basically make it look more natural, like an oasis. 4. The radial animation thing that plays under the structures has a
black line. Can you remove it."
**The water**: every lake's disc ("Oasis", "Oasis2", "Oasis3", the same CylinderMesh) draws with one ShaderMaterial,
core/shaders/water_lake.gdshader (RedCanyon._water_material, `_water_mat`): unshaded, no depth write, render priority -10
as before, no screen or depth reads, four samples of a new 256 px noise texture (art/env/noise_rgb.png, three smooth
tileable noises, tools/gen_textures.py `noise_rgb`). The shader reads the lake's normalised radius off the top cap's UV
(CylinderMesh maps the cap onto (0.25, 0.75) +- 0.25; pass81_map_test pins that) and discards the side band, so the water
is a deep teal middle shading to a lighter shallow rim, the wet sand showing through the last stretch, ending on a
ragged line that a still noise moves in and out (no disc edge), with two noise layers drifting across each other (a soft
light web where they cross reads as ripples), a breathing lapping line, sparse sun glints from a finer faster layer and
a little sky in the far water; stage 3's hell reddens it with the ground. Pass 31's wave shader "read as a patterned disc
lying on the sand": every pattern here is faint, irregular and slow (four rounds by eye: the first web read as marble
cracks and the first glints as white crumbs). The unused pass-31 shader core/shaders/oasis_water.gdshader is deleted.
Nothing in play moved (in_water 1.02, the disc 1.06, the slow, the dish, the hero's cut through the disc).
**The oasis ground**: RedCanyon.oasis_wet(p) (1 to 0.6 m past the nearest lake's edge, 0 at 3.5 m + 0.45 of its radius,
that reach moved +-2.2 m by noise) rides in the terrain's vertex alpha; the terrain shader breaks the edge further with
the noise and draws damp earth, sparse green patches on it and greyer, darker wet sand at the water (uniforms
`oasis_*`). Pass 80's damp ring (a 0.35 mix of the cracked river bed) is gone. Every terrain corner now carries its own
colour (`_color_at` at each grid point, blended across the quad): one flat colour a 1 m quad had drawn a faint checker
over all the sand and blocky steps round the lakes.
**The sand**: research first: Megabonk's desert floor (its Steam screenshots) is a calm warm sand with soft broad
mottling and faint low-res patches, no stripes, the dunes' light doing the rest; ours had strong sine ripple bands at
one scale. Candidates compared in real captures at phone size (tools/dl/p81/MAP/sand_game/): five procedural (soft,
soft + patchy ripples, Megabonk-style chunky patches, painterly; then stronger versions F-H, still reading as dirty
camouflage up close) and four Flux.2 Klein paintings on the AI server (one job at a time under the comfy lock); picked
the calmest painting, seed 8102 (soft broad patches, faint soft ripples, a few pebbles: the plain option). It is kept as
source (tools/art_src/sand_klein_s8102.png, prompt in gen_textures.py); gen_textures.sand() makes it tileable (two
half-offset cross-fades: a single max-mask cross-fade left a seam down the middle) and lays its light and dark
(SAND_CONTRAST 0.06) over the procedural sand's mean colour, so the colour Garry approved in passes 54 and 61 (and the
tests' pins) holds exactly; the procedural sand is the fallback. The terrain shader adds a broad +-7% light and shade
over 53 m (noise) against the painting's 11 m repeat. sand, cracked, redrock and noise_rgb now import with mipmaps
(they had none: the far sand shimmered and cost bandwidth).
**The ring**: the "black line" is the dark clock hand StructureManager drew on the progress pie's leading edge (pass
35's "so the fill reads"); it is gone for every structure (the field `Structure.hand` stays, always null, for old tools
and tests). The ring and pie meshes have no seam.
Perf (tools/_p81_MAP_perf.gd, one sitting, 6 alternating blocks of 240 frames each, the new looks against pass 80's
material, terrain shader and sand swapped in at run time, 504x1122): the lake a third of the screen: GPU 0.245 ms vs
0.242, render CPU 0.461 vs 0.459, frame 1.820 vs 1.830 ms; open sand: GPU 0.247 vs 0.243, frame 1.811 vs 1.806 ms: within
the machine's noise.
Tests: game/tests/pass81_map_test.gd (9); pass31_test's water re-pinned on purpose (the plain material is the shader
now). Captures: tools/dl/p81/MAP/before/ and after/ (lakes at two zooms, wading, the sand, the ring at 40% and 75%,
hell, top-down overview/), the sand candidates in sand_cands/, sand_ai/, sand_game/. Tools: game/tools/_p81_MAP_shots.gd
(sand=<png>, wp.<uniform>=, tp.<uniform>= to try looks), _p81_MAP_perf.gd.
Research sources: Megabonk's Steam page and screenshots (https://store.steampowered.com/app/3405340/Megabonk/, through
the store API); reviews on its look (https://mezha.ua/en/reviews/megabonk-review-305493/,
https://www.playnforge.com/?p=7697, https://opencritic.com/game/19356/megabonk); stylised water: Stylized Water for Godot
4.x (https://godotshaders.com/shader/stylized-water-for-godot-4-x), Toon Style 3D Water, no textures
(https://godotshaders.com/shader/toon-style-3d-water-shader-no-textures-needed/), Water shader 3D (Godot 4.3)
(https://godotshaders.com/shader/water-shader-3d-godot-4-3/), the Stylized Water Shader thread on depth without a depth
texture (baked or vertex colours; https://discussions.unity.com/t/stylized-water-shader-desktop-mobile-vr-built-in-rp/639248),
Creating Toon Water for the Web (https://code.tutsplus.com/creating-toon-water-for-the-web-part-1--cms-30447t), Nimue's
stylized water (https://80.lv/articles/how-to-build-stylized-water-shader-design-implementation-for-nimue/). What we took:
two panned noises for ripples, depth from geometry instead of the depth buffer (here the disc's own radius), a soft shore
fade and lapping line instead of depth-intersection foam, fresnel for the sky, all unshaded.

**Wave pacing per roster row and the yellow etches.** Garry: "Add the ability to control the pacing of the waves. I mean
the frequency at which enemy waves come. And on top of the enemy node in the rows you should etch the yellow etches to
show when the enemies will spawn. If it's continuous (choose an option) it's shown as a continuous yellow line." A roster
row gained `pace`: "continuous" (the default, every row as it always was: drawn into the cap by its weight at every
spawn check) or "waves": `count` creatures (default its pack) every `every` s (default 30; 0 = once) from `t` + `offset`
while the row is open, in its pattern, its presence keyframes switching waves on and off (a wave due at weight 0 does not
come; the weight's size scales nothing), `respect_cap` (default on: cut to its channel's room, the rest owed and spawned
first at each spawn check until the next wave, which drops it) and `trickle` (default off: not in the continuous draw
between waves). The schedule's maths is WaveTimeline's (`row_paced`, `row_wave_index`, `row_wave_times`, ...), the
spawning WaveDirector's new section (`_tick_row_waves` after `_tick_waves` in the normal phase, `_row_waves_owed` first
in every `_spawn_burst`, `_burst_from` leaving out waves rows that do not trickle; a jumped clock fires one wave, never a
backlog; the row's pass-58 fixed numbers). The Level Editor: a Pacing select with Every / Per wave / Offset / Respect the
cap / Also continuous on the row form and a note of its waves; yellow etches along every roster bar's foot (a line where
a continuous row is drawn, a tick at each wave that comes, both on a trickling row; a tick at each burst of a `waves[]`
block; under 3 px apart the ticks are thinned, every m-th kept, never merged into a line), a "↻ 30 s ×20" chip, the next
wave in the hover card and the readout; the Share lane and the Presence share column leave waves rows out of the draw;
"Spawned so far" and the Actual lanes play waves rows (model.js and the Python copy in selftest.py both); validation
words; the global pacing (Burst min / max, Spawn check every) explained as the continuous rows' pacing in Settings ->
Spawning. Red Canyon's rows were left continuous: Garry sets the pacing. Tests: game/tests/pass81_pace_test.gd (10),
tools/level_editor/selftest_PACE81.py (56 checks: model.js against the game's rule in Python on random rows, the fields,
the estimate with waves rows agreeing JS / Python and hand-checked, the validation words). Screenshots of the Timeline
with rows set to waves: tools/dl/p81/PACE/shot_*.png (the page on a spare port with --no-jobs, nothing saved).

Lane POLISH (pass 81): the bees' trails, the rocket at 85%, the Saiga Sniper without running away. Garry: "Change the
trails of the bee projectiles too. Just look up what could work well here." Research (tools/dl/p81/POLISH/
research_bees.md: the cartoon bee's dotted flight path, comic motion lines, wing blur, short quiet trails on a light
ground) led to four looks drawn in the guns' tracer ring (one MultiMesh, core/shaders/tracer_line.gdshader, new styles
5 dash, 6 buzz, 7 bumble; zip = the streak style): `params.missile.trail_style`, ProjectileManager.BEE_LOOKS, `_bee_trail`
in place of pass 49's beads (a 20 m chain of dark dots behind each bee for 1.4 s). Picked by eye at 1080x1920 and at
phone size (sheets and GIFs in tools/dl/p81/POLISH/sheets/): **dash** (dark honey-brown dashes, 0.45 s), the clearest
and the most "bee"; buzz second; bumble broke into noise at phone size, zip read as fire. The three bee items name it
(`"trail_style": "dash"`), the rest one word away (Level Editor group "Bee trail"). "Let's make the Rocket 85% of the
heroes speed": the Raider's `speed_of_hero` 0.9 -> 0.85, and the rocket now takes the creatures' whole pace out of its
speed (ProjectileManager.rocket_clock_pace), so 0.85 is exactly its share of the hero's top speed on the ground (measured
in the game: 2.754 / 3.240 m/s = 85.0%); before, creature_speed_mult had made the 0.9 a real 0.81 (pass 80 had called
it 90%). "Stang Antiope is a bit too zealous with his running away. Remove that feature entirely, just make it like a
similar behaviour to the Cactus ranged enemy, but with a bit more speed": the Saiga Sniper lost flee on hit and his
flee_range (0; the code's default is now 0), walks straight in at 1.6 (cactus 1.15; was 3.2) until he is within 16 m
(`follow`, was 38), holds there and aims, and never backs off, however close the hero comes; a hit still spoils his aim
(new `sniper.spoil_on_hit`, true), without the run; his look's walk plays at 8 fps (was 15, cut for 3.2 m/s) so his feet
keep to the sand. Flee on hit stays in code; no creature uses it. Captures: POLISH/saiga_sheet.png (spawn, walk in,
hold at 16 m, the lines, the lock, the shot, the hero walking up to 3 m, a spoiled aim). Tests:
game/tests/pass81_polish_test.gd (11); re-pinned on purpose: pass73_sniper_test (the Saiga's data has no flee on hit;
"stands off and runs" -> "holds when the hero walks up"; "a hit spoils the aim and sends him running" -> "a hit spoils
the aim"; longer limits for the walk in), pass332_test (the rocket's 0.9 is of the hero's top speed on the ground).

Garry (2026-10-15): "It's time to make a production build version. This version will differ from the current build
by: 1. Having no debug options, no extra art (unless it's used in the Level timeline) 2. Extra optimization for the art
and stuff, to make the build smaller and faster. Create a skill for building this prod build. Build it now (+ the dev
build obviously) and upload the same way. But from this point onwards you will only make a prod build if I ask for it."

**The switch.** The production build is two new export presets, "Android Prod" and "Windows Desktop Prod", whose
custom feature `prod` makes `Settings.is_prod()` true (a headless check forces it with `prod=1` after `--`, a test with
`Settings.force_prod`). In prod, `Settings.PROD_LOCKED` holds every developer switch at the player's default (in
`from_dict`, and `set_value` refuses them): the player's debug mode and so the ARENA on the title, the debug hand, the
free revive and the hit log on Down!, the Settings debug panel; the in-run debug panel (and F1); the debug buttons on
modals; the hidden-hero preview; the menu style stays Live, ranged-on-screen and the pierce drop-off stay on. Small
guards: the ten taps on the hints switch and the 2 s hold on the version line do nothing (SettingsScreen), the
developer menu goes straight back to Settings (DevMenu._ready), the title's button (now named ArenaButton) asks
is_prod too, Game ignores `user://debug_launch.json` and `Run.launch_override` (the file left where it is) and
`Run.arena_next`. The dev build is unchanged. Analytics tags every event `build: prod|dev`.

**Only what the game can show.** `game/tools/prod_reach.gd` walks the Registry: every map; every hero not hidden and
his start and favourite weapon and passive, perks and hero mutations; every base weapon and passive in play with its
evolution, the passive it evolves with and its path; talents, Elite modifiers, pickups and structures not hidden;
every creature, boss, boss attack, pickup or structure any kept item's JSON names (the map's rows, waves, events,
specials, Elites, bosses, portal, hell; a boss's summons, so the hidden Sand Lizard stays; a perk's pickup), to a fixed
point; `Registry.<getter>("id")` literals in the game's scripts outside the debug-only ones (the Peashooter fallback)
with what the Registry needs to stay whole (its evolution); the quests that are shown for what is kept. Looks: heroes
and cards keep the look they play (promoted to the base), creatures their base, played and timeline-named looks.
`game/tools/prod_plan.gd` writes it as JSON; `tools/prod_prune.py` applies it to a STAGING copy only
(`tools/prod_stage.py`: game/ copied fresh to tools/dl/prod/stage/game, its .godot seeded, its own user folder) and
keeps anything a remaining file names by path (Grave Hail uses Dia de Muertos's visual, Jackrabbit Mines Minefield's:
those folders stay whole). It also drops every `_ai.json` and the sound files the sound map does not name.

**Smaller and faster.** `tools/prod_optimise.py`: the six music tracks to Ogg Vorbis q4 (13.6 MiB of QOA -> 7.5 MiB),
icon.png 1024 -> 256 px (1.5 MiB raw in both builds), the last four lossless prop billboards lossy, icon.ico out of the
APK. The Registry loads every content texture at boot, so fewer looks is also a shorter cold start.

**The route.** `bash tools/ship_prod.sh [--no-drive] [--quick] [--no-pc] [--no-android] [--out DIR]`: the source's
checks (and tests unless --quick), the staging copy, the plan, the prune, the optimiser, import + import_json there,
its checks (check_scripts, `prod_check.gd`: Registry clean, all art in play present, planning again drops nothing,
prod forced locks every switch; smoke_run; `prod_run_check.gd`: boot -> title without ARENA -> Settings without the
taps and the hold -> the developer menu bounced -> a real run with a planted arena launch file ignored, F1 inert), the
two exports from the staging copy (APK signed with the project keystore and verified; exe version-checked and signed
when tools/keys/codesign.env exists), the exe's cold start (`tools/prod_probe.py`: exported templates refuse --script
and a scene path, so it times Boot's own "engine and autoloads ... first frame" line and checks the save lands in
%APPDATA%/88fits), the numbers (`tools/prod_report.py` -> report.md) and Drive (88fits-prod.apk / .exe). Identity:
package com.eightyeightfits.game.prod, label "88fits"; the dev app is labelled "88fits Dev" (its package, and so its
save, unchanged); version code from the version (0.67 -> 6700). Skill: `.claude/skills/ship-prod/SKILL.md` (prod only
when Garry asks; one line in ship-to-phone says so).

**The numbers** (first run, `ship_prod.sh --no-drive --quick`, 351 s, against pass 80's dev builds): APK 106.9 ->
71.1 MiB (-34%: creatures 20.3 -> 10.6, heroes 19.9 -> 6.6, sound 16.2 -> 8.5, cards 2.3 -> 0.7, scripts and data
6.0 -> 3.6 MiB; the 23.3 MiB native library stays), EXE 186.8 -> 150.0 MiB; the prune took 94 folders, 59 items' unused
looks (257 files), 5 title cut-outs, 287 _ai.json and 128 sound files (27.9 MiB of imported art and sound); the PC's
cold start to the title (headless, median of 3) 6372 -> 3698 ms (engine and autoloads 5771 -> 3101 ms); perf_late
(build=none, the stage-3 crowd of 260) 5.2-5.7 ms a frame both ways, ~100 draw calls; every kept hero, creature look
and card served the same strip, anims, columns, fps and icon as the source (a Registry dump compared), captures of the
title and the results the same art.

Lessons: release export templates disable path overrides (no `--script`, no scene on the command line), so an exported
build can only be checked by what it writes itself; Windows Godot honours `APPDATA` (not `XDG_DATA_HOME`) for user://,
which keeps a probe of an exported exe off the real save; a feature-tagged project setting
(`custom_user_dir_name.editor`) gives the editor binary's runs on the staging copy their own user folder.

CLAUDE.md commands line:
```
bash tools/ship_prod.sh [--no-drive] [--quick] [--no-pc] [--no-android]   # pass 81: the PRODUCTION build, only when Garry asks (skill ship-prod): a pruned, optimised staging copy (tools/dl/prod/stage/game; tools/prod_stage.py, game/tools/prod_plan.gd + prod_reach.gd, tools/prod_prune.py [--selftest], tools/prod_optimise.py), its checks (game/tools/prod_check.gd, smoke_run, prod_run_check.gd), presets "Android Prod" (com.eightyeightfits.game.prod) + "Windows Desktop Prod" (feature `prod` -> Settings.is_prod(): no debug surfaces), tools/prod_probe.py (the exe's cold start), report tools/dl/prod/out/report.md, Drive 88fits-prod.apk/.exe
```

**Pass 82 (2026-10-16, v0.68): the HP bar shakes, every kill throws its body, five sands, the Spirit Pole, XP growth types, chests/power-ups/totems charts.** Garry: "Don't shake the screen when hero is damaged. Shake the hp bar instead"; "Sand Texture is still not very good" (his reference tools/dl/uploads/2d/sand-texture.webp, four variants, two with the little rocks, the previous as a fifth, switchable in the Level Editor); "The explosion thing that affects the enemy's corpses with knockback should come from all weapons"; in the Watch "Bot should try to find the Special Enemies" and "access to Pause button in the game"; the Totem UI from Claude Design's handoff ("Design critique and verdict.zip", direction 1b "The Spirit Pole"); "types of EXP growth displayed in a dropdown, each one with it's own 2 charts"; a Sim chart of "Chests Picked up, Power-ups and Totems", marks in the Watch, the same in the dashboard, and where the step-by-step for players' runs lives (answered in chat: analytics/howto/03_remote_runs.md, now indexed in analytics/README.md and shown on the dashboard). Six lanes (tools/dl/p82/INTERFACES.md): FEEL, SAND, WATCH, TOTEM, XP, STATS. The lead made the blasts shake the same whether they catch the hero.

**Lane FEEL (pass 82): the HP bar shakes instead of the screen; every kill throws its body.** Garry: "Don't shake the
screen when hero is damaged. Shake the hp bar instead. But do that a little bit." The hero's hurt shook the camera 0.9
on every `Player.hit` (Game.gd's one-line connect) and a harpoon's hook 1.0 more; both are gone. `Game._feel_hurt_bar_shake`
reads the hit's dealt damage off `player.damage_log` and calls `HUD.shake_hp_bar(dealt / max_hp)`: the hero's bars
(HP and the shield bar under it, drawn by `_draw_hero_bars`) jiggle sideways by `hp_shake_x`, 4 px + 40 px per whole
max HP, at most 10 px, three swings over 0.25 s dying as (1 - u)^2 (`HP_SHAKE_*`, `hp_shake_amp_for`, `hp_shake_at`,
`_tick_hp_shake` from `HUD.tick`), no allocation, exactly 0 at the end; a hit during one keeps the larger. Every other
shake stays (blasts, slams, rumbles, bosses down). "The explosion thing that affects the enemy's corpses with knockback
should come from all weapons. I think currently it's just the dynamite": pass 79's follow-through threw a body up only
for a `damage_radius` kill with a push, and most weapons push little, so their kills barely moved. Now `damage()` notes
the killing hit (`_corpse_note_kill`: its own direction, else away from the hero; its weight = damage over 4 max HPs,
+0.35 for a crit) right before `_die`, and `_corpse_begin` gives every such kill `_corpse_follow`: the push along the
hit raised to a floor (4 m/s, up to 5.5 for the heaviest hit, times a heft for big bodies, 1.5 / size, at least 0.5)
and a toss (0.4 m, up to 0.8, + 0.1 m per m/s of its own push, at most 1.6; a blast's pass-79 throw when higher). The
boss, big game, a launched body and one still rising (below `rise_targetable`; one nearly up is shown whole and thrown)
are as before; nothing changes for the living. Captures (tools/dl/p82/FEEL/sheets: hurt, rev, tommy, saws, beam, laser,
dyn) checked by eye: a chip kill throws a goblin 0.4 m up and ~1.5 m back, a one-shot 0.8 m and ~2.4 m, the saws fling
the ring outwards, the dynamite as before. Cost: A/B in one run (`game/tools/_p82_FEEL_bench.gd`, a kill every frame in
a crowd of 180) +0.19 ms enemies.sim and +0.08 ms fx per frame; perf_late build=six within noise. Tests
`pass82_feel_test.gd` (11); pass79_fx's corpse tests re-pinned on purpose (a non-blast kill and a no-push blast kill
are now thrown; the blast's height is the higher of the two rules; the falling body's flight is longer).

**Lane SAND (pass 82): five sands to choose from.** Garry: "Sand Texture is still not very good. I added a reference
called sand-texture.webp let's try generating something like that, and maybe a couple (4) variants to try out, see which
feels most natural. I like the little rocks in the texture though, can you keep them in 2 out of the 4 variants. Add the
previous sand texture as the 5th variant as well. I want to be able to switch between them easily. Maybe in the
LevelEditor". The reference (a watermarked stock photo, used only as words: soft broad wavy dune shading, a fine even
grain, warm golden tan; measured, its broad shading is about 5% of its brightness and its grain about 1%, where pass
81's sand is 3.5% and 4.7%: busy where the reference is calm) was never sent to the AI server or traced.
**Four new sands** (tools/gen_sand.py, new): 16 Flux.2 Klein paintings on the AI server (one job at a time under the
comfy lock; four prompts describing the reference in words, with and without sparse grey pebbles, broad dunes and
smaller wind ripples, four seeds each). Pass 81's way of making a painting tileable (a half-offset copy cross-faded in)
doubles every pebble and flattens bands where the copies cross, so the new ones are made tileable by repainting the
seam: the painting rolled half a tile, the cross where its old edges meet repainted by Klein under a grey latent noise
mask with differential diffusion (fully on the seam, less and less out to 256 px), which grows the repaint out of the
painting round it. Two defects found in the game captures and fixed: the repaint's slightly different colour cast
showed as a soft rectangle (fixed: each repaint brought to the painting's cast before blending), and the cross's arms,
repainted up to the tile's edges, broke the wrap there (a faint straight step every 11 m; fixed: three repaints, none
touching an edge: the cross with its arms stopping short, then each seam's two ends after rolling half a tile down and
across). Each sand is laid over pass 81's exact mean colour (the pins of passes 54 and 61 hold; the river, the oases and
the walls match): its broad shading normalised to 5.5% of the colour per SD, the fine rest (grain, pebbles) at 70% of
its painted contrast, and on the pebble sands half of a pebble's own local colour (it stays a little grey). Picked by eye
in four rounds of real game captures at the phone's 3D canvas (864x1920 through a SubViewport, the desktop window being
too short; the open sand, a crowd, a lake, pulled out): Soft dunes (dunes s8201, drawn 0.8 the scale: broader bands, the
closest to the reference), Soft dunes + pebbles (pebbles s8201), Wind ripples (drift s8203, livelier), Wind ripples +
pebbles (drift_pebbles s8202). Sources kept in tools/art_src/sand_<id>_src.png.
**The switch**: timeline_data `sand` (WaveTimeline.sand, JsonContent) picks one of RedCanyon.SANDS as the terrain
builds (its painting and `scale`, the terrain shader's new `sand_scale`, so the river bed and the rock keep their
tiling); "" or an unknown id plays pass 81's sand, which stays the default until Garry picks (the map file has no `sand`
key). The Level Editor's World card has a "Sand" select with the five named in words, help, and a preview of the chosen
one in the game (tools/level_editor/sand_previews.png); the arena's WORLD tab switches them on the spot (Sand row,
RedCanyon.set_sand), for the visit only.
**Pick**: Soft dunes, the plain option and the closest to the reference, calm under a crowd; Soft dunes + pebbles if he
wants the little rocks.
Tests: game/tests/pass82_sand_test.gd (7: five sands, the default pass 81's, every new one tiles at its edges and its
middle lines and wears pass 81's mean colour, the pebble two keep greyer pebbles and the plain two none, the map's key
paints the terrain, "" / "pass81" / an unknown id play pass 81's, the arena switches and lists them, the key read from
the file, the shader's sand_scale, the editor's row); tools/level_editor/selftest_SAND82.py. The colour pins (pass54_world,
pass61_map, pass79_world, pass81_map) pass unchanged. Captures: tools/dl/p82/SAND/sheet_five_{sand,crowd,lake,far}.png,
final/, detail_<id>.png, the rounds g1-g4, arena/. Tools: tools/gen_sand.py, game/tools/_p82_SAND_shots.gd,
game/tools/_p82_SAND_arena_shot.gd.

**Lane WATCH (pass 82): the bot goes to find the specials; the game's own Pause in the Watch; chests, power-ups and
totems in the Watch.** Garry: "Bot should try to find the Special Enemies when they appear", "Allow me access to Pause
button in the game, it also pauses the game, but I can access settings and such", and for the Watch "just mark the
totals somewhere and mark the times that these items were picked up on the chart of Level and XP".
- *The specials* (game/tools/bot/BotGoals.gd `special_candidates`, `special_seen`; Bot.gd `_hunt_step`, `_special_at`,
  `special_in_reach`, `_special_found`, `special_tallies`): the sims came first. Specials chase the hero and the weapons
  take them first within 10 m (pass 73), so the bot that never hunts already killed 98.4% of the ~160 specials of a
  25-minute run (30 runs). Hunting every one (walking straight at it; then leaning the kite at it and keeping it as the
  goal while the weapons fought it) killed no larger share and cost 3 to 8 levels at 25:00 and half again to twice the
  falls, most in stages 2-3 and at the bosses. The rule kept: go and find a glowing special that does not come (known 5 s
  within 30 m and still past 9 m or off the screen), leaning the kite towards it (the gems' sweep rules: clear way,
  health) until it is within 6 m and on screen ("found": he plays on while the weapons take it; that special waits 5 s
  more out of reach before another hunt); no hunt while a boss lives, none new under 50% health (one under way on to
  40%), worth 60 with no commitment (a heal or a chest that beats it takes over at once). Option `specials` (on but in
  sim77; sim_batch.py BOT_KEYS and sim_run.gd BOT_ARGS one entry each, so the Level Editor's Sim tab shows a "Specials"
  switch). The log: "a special: Red Goblin, a 35% chest, out of reach 6 s (14 m)", "found the special Red Goblin after 4 s:
  in reach, the weapons take it first" (kind `special`). meta.bot.specials {came, killed, chests, life_s (the mean
  seconds a special stood), hunted, found, hunted_down, gave_up}. Measured (20 runs against 30): the same share killed,
  falls 10.5 (median 6) against 9.3 (4), the level within half a level at 10-20 minutes and 2.7 lower at 25:00 (the
  batch noise is about 4). pass80_bot_test re-pinned on purpose (intent `special`; its no-planner bot has specials off).
  A finding for the bot's owner: BotGoals' per-thing jitter is keyed by object instance ids, so any code change
  reshuffles later choices (two batches of the same behaviour and seeds differed by 3.6 levels): compare sims by many
  runs, not seed by seed.
- *The game's Pause in the Watch* (Watch.gd, WatchClock.gd): the phone view takes the mouse and turns a left press, drag
  and release into the ScreenTouch / ScreenDrag of finger 0 the phone sends (no mouse events, so nothing that reads both
  fires twice), pushed into the SubViewport (its stretch maps it onto the 1080 canvas; `finger_event`, tested against a
  real SubViewport). The hero's PlayerInput is switched off for touches and keys in the Watch (no stick from a click, no
  WASD; the bot still drives). With the game's own pause screen up the bot is not ticked, nothing counts as stuck, and
  the clock runs the frames as at 1x (`game_hold`: 60 a second, all drawn, time scale 1, sound) so the screen and its
  Options work as on the phone; RESUME goes on at the Watch's speed; the header says "paused (in game)" and the speed
  badge hides (RESUME sits there). New check actions `click=x/y`, `gamepause`, `gametab=i`, `gameslider=i/f`,
  `gameresume`, `whole`, sent through the window's own input.
- *Totals and marks* (WatchData, WatchPanel, WatchChart): lane STATS' rule (sim_run.gd `pickup_kind`: every `chest`
  event, every `pickup` not small, every `totem`) read live from the recorder's events; Live tiles Chests, Power-ups,
  Totems (each in its mark's colour) and Specials (killed / came); on the Level and XP chart a gold square, a green
  circle or a pink triangle at each pickup's second, one lane a kind along the plot's foot, the totals leading its
  legend; last 3 minutes and whole run both.
- Checks: tests/pass82_watch_test.gd (11), the pass 80 bot and Watch tests, pass77 simrun, pass78 dash and pass82 stats
  green (70); check_scripts 535 files clean; LE selftest 18,873 green. Windowed Watch runs (Drifter, 4x, 5:00): the HUD's
  disc, the Options tab, a Music slider drag (3 to 1) and RESUME clicked through the window's input
  (tools/dl/p82/WATCH/shots1, shots2); the record's events match the tiles and the legend.

**Lane TOTEM (pass 82): the Spirit Pole.** Claude Design's answer to pass 76's brief (design_handoff_88fits_totem/,
direction 1b) replaces the Totem Pole's gift screen (`ui/TotemScreen.gd`, rewritten; pass 73's planks, feathers and
painting gone). The offer builds a pole on the left over the modal dim (W.DIM, the HUD hidden): the thunderbird crest
(art/ui/totem/crest.png, 420x126 at (0, 372)), three carved segments (WPlate in rock #B4472B, 300 px at x 60, y
500/840/1180, a 6 px ink border, radius 10, the carved inset as its 8 px ring of black at .18, the spirit's face 240 px)
and beside each a paper tag (the kit's HardBox paper, 5 px ink, 8 px hard shadow, 630x240 at x 390) nailed on (new kit
piece `ui/wanted/WNail.gd`) with the amount in Alfa Slab 48 and the stat in Bitter 600 30 on one baseline, the spirit
"Le-loo, the Wolf" in italic 26, and the roll gauge (new kit piece `ui/wanted/WNotches.gd`: both range ends, three
56x18 notches filled by the roll's third of its own range; the number brass dark on a top third), the base 360x64 at
(30, 1510), the label "★ TOTEM 4 OF 11 ★" at (60, 300) (Bitter 600 tracked 10 px with spaces 12 px wider, drawn stars,
so each glyph lands within 2 px of the mock's 10.5 px CSS tracking). Each gift row is one WTap target (segment, nail,
tag; `_has_point`), held 60 ms (the segment +14 px with a 44 px turquoise StyleBoxFlat glow, the tag on its shadow with
the 6 px brass inner outline, the other rows to 60 % as one picture through a CanvasGroup each: faded piece by piece the
tag's shadow had shown through its paper), dragged off 90 ms back, taken on release. Motion with tweens: open 460 ms
(ring flash, dim, crest from y -80, segments rising, tags sliding, base), close 420 ms (the face flies to the HUD's toast
icon and shrinks 240 -> 72, the rest drops and fades, the dim lifts last; the run goes on at 300 ms with the toast
"Le-loo · +2% move speed" carrying the face: WToasts icon toasts, `HUD.toast(text, colour, icon)`, `toast_icon_spot`).
Data (TotemBoons): word, animal, roll third, range ends (the smaller size first), the icon slot
art/ui/totem/spirit_<id>.png (the handoff's four stand-in faces for the Wolf, Bear, Frog and Serpent; the other seven
show their word in Alfa Slab 40), the label (gifts taken + 1 of the map's poles, StructureManager.count_of; "4TH TOTEM"
without a total). The pole in the world (`params.spent_motion {flash 0.12, fade 0.4}`): it keeps its paint and ring under
the screen, its ring flashes as the screen opens (StructureManager.flash_ring), it drains to grey over 0.4 s once the gift
is taken (spend_slowly; a `desat` uniform in sprite_billboard.gdshader) and ends in pass 73's grey painting; use_structure's
generic flash ring is skipped for it (it froze under the paused screen and played after the pick). Hints teaches "Totem
gifts last the whole run" once. Gameplay untouched (weights, ranges, charge, safety, analytics). Captures
(game/tools/_p82_TOTEM_shots.gd, a real run and a white backdrop for the pixel compare) match screens/01 and 02 within 1 px
on every element; tests pass82_totem_test (12), pass73_struct re-pinned on purpose (the menu's fields, the grey after the
pick, the top-anchored fit), touch_audit's totem states (taps off the rows, a drag off a gift, inset 130 and 200).

**Lane XP (pass 82): XP growth types.** Garry: "EXP requirements - I feel like we don't have enough settings for EXP
requirements. Say I want to make the EXP requirements exponential instead of linear, it doesn't look like I can. I want
that section to include types of EXP growth displayed in a dropdown, each one with it's own 2 charts for cumulative and
per level EXP requirements." The XP a level needs is now a map key with a growth type: `timeline_data.xp_curve` =
`{"type": <type>, <type>: {numbers}}`, read by the new `game/core/data/XpCurve.gd` (static: TYPES, DEFAULTS, type_of,
params_of, need, total) through `WaveTimeline.xp_curve` (JsonContent reads it as it is) and `Run.xp_to_next` =
`XpCurve.need(Run.xp_curve(), L) * xp_need_mult()` (the arena and a run without a map: today's curve × 1). Five types,
each times xp_need_mult: quadratic (today's, base + linear L + quad L², 15 / 6 / 0.5: absent, `{}` or an unknown type
plays it to the bit), linear (base + step (L − 1), 21.5 / 16.5), exponential (base × growth^(L − 1) under an optional
cap, 40 / 1.11 / 0), power (base × L^power, 6.5 / 1.33) and table ([[level, XP]] straight between listed levels, the
last grown by after_growth past it; default today's curve at 1, 5, 10 ... 60, +2.5%). The defaults land within 5% of
today's total XP by level 30 (7,322.5 before the multiplier: 100 / 100 / 97.5 / 101 / 102.5%) so switching type does not
wreck a run; each type keeps its own numbers in its own block, so switching back keeps them. Guards: a level needs 0.01
to 1e12 XP (NaN / infinity = 1e12). The run record's `map_settings.xp_curve` names the type played and its numbers.
Red Canyon names no curve (Garry's 1.65 kept): nothing changes until he picks one.
The Level Editor's Settings tab has a new **XP per level** card (after Scaling; `xp_need_mult` moved into it): the
Growth dropdown, the formula, the chosen type's numbers (an empty box shows the game's default in grey, "the game's N"
beside it), a table editor for the table type ("Edit a copy" of the default, + level, Default table), XP needed ×, the
page's checks (errors block Save: an unknown type, a level needing 0 XP or less, a non-number, a table with no readable
point, a negative cap; warnings: a curve passing 1e12 before level 150, a growth under 1, a level needing less than the
one before, stray keys), and two charts for the chosen type (the XP each level needs; the XP to reach a level in all),
levels 1-30 / 1-60 / 1-100, a log scale, today's curve as a faint dashed line, one crosshair across both with a readout
(this curve, today's, the ratio), a table of the values at levels 5-100, all times the map's xp_need_mult. Typing in a
box previews the charts at once (yellow-edged), Enter or leaving the box keeps it (one undo step). Under the charts: when
a run gaining XP as the latest sim of the map did (its mean `xp_total` a second) reaches levels 10, 20 and 30 with this
curve and with today's (a rough guide; the curve changes the cards and so the kills). Files: tools/level_editor/
xp_model.js (the page-free maths, a copy of XpCurve.gd), xp_card.js (the card), xp.css; fields.js `XP_TYPES` and the
card's rows (the Instructions tab documents every key); settings.js, app.js and index.html small hooks; the check group
selftest_XP82.py (the JS maths equal a Python copy of XpCurve.gd for 29 blocks × levels 0-150, the defaults' totals,
the readers, 16 check cases, the rows, the wiring). Tests: game/tests/pass82_xp_test.gd (absent = today's exactly for
levels 1-100 through XpCurve and Run.xp_to_next, each type's formula by hand, the defaults' totals, the guards, the
reader, the multiplier, the arena, levels by the chosen curve through add_xp, the run record); pass46_passives,
pass52 and pass79_mut re-pinned on purpose to read the map's curve through XpCurve (Garry picking a type would have
turned them red).

**Lane STATS (pass 82): chests, power-ups and totems through a run; the how-to made findable.** Garry: "In the Sim add a
chart for Chests Picked up, Power-ups and Totems though a run ... add the same to the local analytics dashboard" and
"Remind me how do I go about viewing this information ... a step by step of how I can save the data from real Players
posted to posthog and 'convert it' into the local dashboard". One rule counts them from a run's events, written once per
language and pinned to one fixture (tools/level_editor/testdata/stats82_pickups.json): a `chest` event is a chest
(taken or skipped, a boss's too), a `pickup` without `small` a power-up (the game's own rule: Heart, Magnet Pulse, Nuke,
Berserk, Shield, Sprint, Timeout; not cake slices, coin bags, pollen), a `totem` event a totem (sim_model.js
`pickupKind`, game/tools/sim_run.gd `pickup_kind` (the Watch uses it), tools/analytics_csv.py `pickup_kind`). The run
sim's player files carry `chests`, `powerups`, `totems` counts a row (sim_run.gd series(), its page twin sim_avg.js
series(); the dash78 fixture regenerated); sim_batch.py and sim_avg.js average them like kills (CUM_SERIES, the runs one
by one, the summary's means; made-up runs roll them on dice of their own so older pins hold). The Sim tab gained the
chart "Chests, power-ups, totems" (section Rewards, after Kills: amber, blue, magenta, validated as a set; the compared
sim's three lines dashed grey; `missing()` names it for an older sim), a tile "Chests · power-ups · totems a run" and a
"picked up" column in the runs table (SIM77's chart-id pins re-pinned on purpose). The dashboard (analytics/dashboard.html)
draws the same Sim chart for one run, an average or a remote run, plus its own card "Chests, power-ups and totems"
(tiles with what each was, step lines with overlays, each one marked at the bottom: a square a chest, a dot a power-up,
a diamond a totem; the list of each one) and the same marks under the level in Progression; the rows CSV gained the
three columns (the page's csv-lib and analytics_csv.py byte for byte, now checked). The how-to is findable: an index at
the top of analytics/README.md (each question, in Garry's words, and the page that answers it), a "How do I get players'
runs? (step by step)" panel on the dashboard's Remote runs view (open until a download exists; links to
howto/03_remote_runs.md, README.md, SCHEMA.md), a line in "Where the runs come from"; SCHEMA.md has a section on the
three counts. Checks: selftest_STATS82 (rule, series, JS = Python averages, the chart, the CSV twins, the page and the
README), game/tests/pass82_stats_test.gd, a real 3-run sim (tools/dl/sim/runs/p82-stats-check) seen in the Sim tab, the
dashboard in Chrome with local runs, three opened runs averaged and the remote run.

**Pass 83 (2026-10-16, v0.69): carved totem segments, heroes' requirements, Thorns nerfed, a composed title scene with shadows under everything, boss HP by seconds of full DPS, the hero's power, who spawns in the Timeline.** Garry: icons for every totem gift as parts of the column and a clean top; "Most of the locked [heroes] have requirements, 2 are only unlocked for money"; hero items hidden in the Collection until the hero is unlocked; "The Thorn Mirror Upgrade is way too OP"; the main menu "looks barren", variants of the environment art and "a simple shadow underneath" everything; "Sand - I am choosing Rip+P"; invulnerability after a hit halved; boss HP "at least 25 seconds of Player's FULL DPS on Tumbleweed king ... 40s ... a full minute"; enemy HP scaled by the hero's power level (defined, charted, explained in the Level Editor, 1 = none); in the Timeline the % of who spawns on hover and on the notches, a continuous row's interval, the highlight as the share of the past N seconds, the Share lane removed; and a critique of the spawning system with a Timeline redesign (answered in chat; built in pass 84). Five lanes (tools/dl/p83/INTERFACES.md): TOTEM, META, SCENE, SCALE, TIMELINE. The lead halved the invulnerability, set the sand, made rounds hit big bodies where they are drawn and re-pinned three tests to Garry's map edits.

Lane TOTEM (pass 83; Garry: "generate (with local AI, without creating a method for it in LevelEditor) icons for each
of the types of Upgrades that the Totem can give ... The icons should make sense as a part of the column. The top bit
... should have it's transparency fixed and look better. The idea is that the buttons represent parts of the column"):
all eleven Totem gifts (wolf, whale, bear, thunderbird, seal, salmon, frog, killer whale, bullhead, raven, two-headed
serpent) have a carved segment painted with Flux.2 Klein by the scratch generator tools/gen_totem_icons.py (no Level
Editor method): each spirit's carved, painted head on a green screen in the in-play pole painting's style (reference
tools/dl/icons_le_j20261014-005810-ba60/totem_pole_c2.png), keyed with clean alpha and laid on ONE shared cedar block
(the grain of a painted bare log on a symmetric cylinder shade with a carved groove top and bottom), so every segment
has the same wood, edges and depth; a motif says the gift (claw marks for damage, wind streaks for speed, a heart for
HP, lightning for cooldown, a horseshoe magnet for pickup radius, water drops and hearts for regen, a gem for XP, a
dorsal blade for crit, a shield for damage reduction, a golden sun for luck, rings for area). Lessons: whole-square
paintings gave plank fences, barrels and neighbouring faces round the head (keyed heads on one block fixed it); a
picked head used as a second reference made every animal a bear (round ears on the thunderbird), so the heads were
painted from the pole alone with "NO EARS ... not a bear" words. The crest was repainted (green screen, keyed clean,
the bare post under the wings cut off). The Spirit Pole screen: the segment fills its plate inside the ink border with
the carved inset over it, a cedar post between the segments and a cedar plinth make one column, the crest sits centred
on it. touch_audit's totem state waits for the gifts to land (a hit-stop's time scale made its 0.8 s timer end 60 ms
after the open) and a gift also takes a finger by the clock once its motion should have landed.

Lane META (pass 83): heroes' requirements and prices, hero items hidden in the Collection, Thorns nerfed. Garry: "Most of
the locked [heroes] have requirements - 2 are only unlocked for money" -> the Drifter is the only free hero; Ironwood
(availability available -> purchase, his 2,500-kill quest retired to tools/level_editor/backups/deleted/) and Astro are
sold for gold alone (300 each: the first runs' purse buys them), every later hero needs his quest then his price:
Calavera the King (300), Solenne extract after stage 2 (1,500), Fadeaway a new quest unlock_fadeaway "Kill 3 Saiga
Snipers" (1,750, was money only at 1,000), Jeżyk 15 minutes (2,000, was 1,250), May level 30 (2,500, was 1,750). A save
that had done unlock_ironwood keeps him (Save.FREED_BY_QUEST, every load). Item quests reviewed against the timeline and
the sims' per-run kills: no change (items are never bought; a hero's favourite and start weapon ignore quests). "Items
that are hero specific should be hidden in the Collections Menu if that hero is not unlocked" ->
CollectionScreen.item_hero / hero_item_hidden: a hero weapon and its evolution, hero mutations and perks are left out
(tiles, counts, a weapon page's hero mutations) until the hero is owned. "The Thorn Mirror Upgrade is way too OP" ->
Spite/Thorns +5 -> +2 thorns a rank; Game._thorns_burst: thorns at most once every 0.5 s (THORNS_COOLDOWN, pass 82's
rate, so the halved invulnerability does not double them), the damage recorded as "thorns" (Results row, run record,
DPS window; no life steal). Face-tank probe (game/tools/_p83_META_thorns.gd): thorns' share of damage by 5:00 at three
ranks 66 % -> 20 %, at six 35 % -> 19 %. Tests pass83_meta_test (8); re-pinned pass69_ui_test (Astro is the money-only
hero the purchase tests use), pass76_ui_test and pass72_results_test (Adrenaline / the Tumbleweed's quests in place of
Ironwood's), pass46_passives_test and pass53_items_test (the heroes owned around the Collection checks).

**Lane SCENE (pass 83): a composed title scene, eight prop variants and a new bush, ground shadows under all the
scenery.** Garry: "Main Menu background scene, looks barren ... add some variation to our environment art ... add a
simple shadow underneath the environment 2.5d things ... barrels, signs, and structures too." *Variants*: tools/gen_prop_variants.py
paints candidates with Flux.2 Klein from two references (the style anchor and the original prop's own raw render),
finishes them exactly as gen_props does (fit, warm thin outline, mute) and writes review sheets (on sand, at run size
and 2x); picks by eye after three rounds for the weak ones (the first agaves curled into spiders, the first boulders and
"young" joshua trees copied the reference's silhouette, the first dead shrubs grew trunks): agave_b (a compact silvery
blue rosette), barrel_cactus_b (a pair with red hooked spines and yellow crowns), ocotillo_b (a sparse open V in leaf,
red tips on two stems),
boulder_b (a balanced rock on a pedestal), desert_bush_b (sage in full purple bloom, weight 0.5), dead_shrub_b (a low wide mound of
dry twigs), joshua_tree_b (open, spreading) and joshua_tree_c (dense crown, a hanging branch; both from the "old wide"
prompt, the Y-shaped young tree looked like a slingshot), and the new kind brittlebush (silver leaves, yellow daisies;
a bunchgrass was painted too and read as wheat). props.json `variant_of` (+ `weight`) registers a variant;
PropField.add(kind) draws the kind or a variant by a hash of the spot (pick_look), never the map's roll, so every seed's
layout, colliders and the tests that pin it stand; `placed` rows keep the kind's id and gain `look`; add(..., exact)
draws the named painting itself (the title, captures). A run-size sheet of each original beside its variant sent the
ocotillo and the desert bush back for a fourth round (orange tips and lavender dots vanished at run size). The brittlebush
joined the bush patches, the oasis greenery and the tree stands' undergrowth (pass61_map_test's BUSHES re-pinned on
purpose). *Shadows*: core/shaders/ground_shadow.gdshader (a soft ellipse in the creatures' blob colour) in one MultiMesh
per PropField ("GroundShadows", draped on the slopes with EnemyManager.drape, the creatures' SHADOW_PRIORITY so gems and
coins draw over it); each painting's size from props.json `shadow` {w, d, x, z, a}, measured by tools/prop_shadows.py
(foot and lower-body widths; z puts the centre under the painted foot, which stands ~6% up its quad, over sin 46 deg)
and tuned by eye over three sheets (too faint and hidden behind the paintings at first: 1.45x the measured width, 0.7
deep, a flatter core). Shadows lean right away from the paintings' upper-left light (SUN_SHIFT). The barrels
(BarrelField.shadows, hidden on a break), the sign posts (SignField.shadows) and the structures (Structure.shadow; the
Strongbox's shrinks as it lifts and grows in as one comes down, StructureManager.shadow_k) add theirs to the map's same
MultiMesh through PropField.add_shadow: all the scenery's shadows are one draw. The shadow data is kept CPU-side
(a MultiMesh's buffer is never read back). *Title*: TitleStage.compose() reads art/ui/title_scene.json (per map: a box
round the hero's spot whose scatter is removed, PropField.remove_where, and the paintings laid by hand), composed by eye
over five rounds at 1080x1920, with the 130 px camera inset and at a 9:20 phone (the capture sets the phone's "expand"
stretch): a joshua tree and a saguaro framing the title, a low group either side of the hero, a dry shrub between them
for depth clear of the tagline even with the inset, a bush at each corner of his feet, faint shapes on the horizon under
the wash. The menus' backdrop jpg is that scene without the hero (new tools/menu_backdrop.gd; wanted_shots' arena still
only with only=backdrop_arena). perf_late (build six, 504x1122, fixed 60): 10.70 ms a frame without the shadows against
11.00 with them over four samples each, inside each run's own spread (10.1-11.3), render CPU +0.03 ms, +1 draw call.

**Boss HP by seconds of full DPS, the hero's power, enemy HP by power (lane SCALE).** Garry: "Fix the Boss HP. I want it
to take at least 25 seconds of Player's FULL DPS on Tumbleweed king to kill it. Then 40s for the next and a full minute
to the last one" and "add a modifier for the enemy HP scaling with the power level of the Player". What had gone wrong:
pass 72 pegged a boss to the hero's recent real DPS against a reference (King 600, Gila 4,500, Brander 20,000); the map
had references ten times those (6,000 / 45,000 / 200,000), and in that rule a bigger reference makes a boss softer, so
every boss came at the floor (×0.75: a 1,080-HP King). New `core/systems/HeroPower.gd`: full DPS (every weapon's estimate
with its crowd guess divided out, burns kept up, the average crit; on a boss Big Game Hunter too), effective HP ((max HP +
shield + 30 s of regen and lifesteal) ÷ ((1 − armour)(1 − evade))) and power = √(full DPS ÷ 20.4 × effective HP ÷ 100),
a fresh level-1 Drifter = 1. `boss_hp_scaling.mode` "seconds" (the game's default now; "dps" keeps pass 72's rule) with
`seconds` per boss (25 / 40 / 60, in red_canyon.json): HP = max(data HP, full DPS × seconds × (1 − damage reduction))
(WaveDirector.boss_seconds_target, EnemyManager.boss_hp_target). `power_hp_scaling` (1 = none) and `power_hp_max` (10):
creature HP × power^(s − 1), folded into the hero-level factor a row fixes at its first spawn. The power is recorded
every second (`power`, `full_dps`, `ehp`, `power_hp`; SCHEMA.md) and charted: the run dashboard's "Hero power" card,
the Sim's and the averages' / Remote runs' "Hero power" chart (sim_run.gd / sim_avg.js / sim_model.js series `power`,
a band series), the Watch (a Power button over its first chart, or P). Level Editor: the Boss HP card rewritten (the
mode on top, a "How it works" box with the King worked through and the reference trap named, a row of seconds a boss
with its data HP and a tuned build's HP, a chart of boss HP against full DPS; the pegged numbers show only in that mode
via a new `showIf` on fields), a new Hero power card (the two numbers, "How power is calculated", a chart of the HP ×
against the power) and an Instructions section. Measured with game/tools/_p83_SCALE_boss_probe.gd (difficulty_probe's
builds, the boss held still in front of the hero): every kill took at least its seconds (King 29-42 s, Gila 45-94 s,
Brander 81-239 s); the extra is shots that miss a big body (a projectile hits only within its radius + 0.35 m of a
creature's centre, so the Tommy Gun's scattered rounds land 10-25% on a boss), blades and orbits out of reach, the
Salt where the boss never walks. Tests pass83_scale_test.gd; pass72_boss_test / pass72_integ_test name the pegged mode;
selftest_SCALE83.py and selftest_BOSS (the mode row).

#### How to set it up in the Level Editor (for Garry)
Open **Settings** and find the **Boss HP** card. "Boss HP is set by" should say **seconds of full DPS** (it is the default
now). Under "Seconds of full DPS (each boss)" each boss has one number: the King 25, the Gila 40, the Brander 60. That
number is how many seconds the boss lasts if every single shot of the hero lands on it: when the boss arrives, the game
takes the hero's full DPS at that moment and multiplies it by the seconds, and that is the boss's HP (never less than its
normal HP). Want a tougher boss? Raise its seconds. A real fight always lasts longer than the number, because nobody lands
every shot. The "How it works" box at the top of the card works the King through (a 300-full-DPS hero meets a 7,500-HP
King), and the chart under the rows shows the boss's HP for any full DPS (hover it). The old numbers (exponent, window,
floor, ceiling and the reference DPS) belong to the other choice, "pegged to recent DPS", and only show when you pick it;
there, a bigger reference made the boss softer, which is why the King died in seconds with 6,000. Next to it, the
**Hero power** card explains how the hero's power is calculated and holds "Enemy HP by power": leave it at 1 for no
scaling, 1.5 makes creatures' HP grow with the square root of his power, 2 in step with it.

**Lane TIMELINE (pass 83): who spawns, on the Timeline.** Garry: "now that we added waves the highlight doesn't seem to
show which enemies are going to be spawning ... if I hover over enemies and specifically over those yellow notches it
actually shows the % of enemies that will be spawning. And for Continuous spawning, I would still like to control the
interval ... the notches on the enemy node should reflect that ... the highlight actually just shows the share of roster
draw as the % of enemies that spawned in the past 5 seconds (controllable value next to 'snap on') ... Remove the 'Share
section'". The readout's "Roster drawn now" had shown only the continuous rows' weight shares (pass 81 left the waves rows
out of the draw), so with Red Canyon's rows mostly paced as waves it named Goblin Runt 100% while the Red Goblin waves
brought most of the crowd. Now: a roster row may carry `interval` (the row form's **Draw every (s)**; absent = the map's
spawn check, today's path and dice): WaveDirector draws it on its own real-time clock from its start
(`_tick_row_intervals`), each draw a burst cut to its share of the channel's weight (`_interval_part`; a cut burst below
one creature brings one with that chance), so half the interval brings about twice as much and the other rows keep their
rate; least 0.1 s. A continuous row's etches are ticks at each draw (the spawn check's rhythm or its own clock), dotted
where under 3 px apart. Every share the page shows is the % of all creatures spawned in the **past N seconds** (a box
next to Snap on, default 5, remembered by the browser) read off the Spawned so far estimate (`Model.windowShares`; the
estimate and its Python copy in selftest.py play the own clocks): the readout lists every row and wave with its share
(0% dimmed, swarms/Elites/specials/bosses as "other"), the roster bars that spawned nothing in the window dim on the lane,
a bar's card gives its share, a wave tick its count and its share of the N seconds from it (how many the cap let in), a
draw tick how often and how much. The Share lane, its table, its legend and its CSS are gone. Files: WaveDirector.gd
(new section + hooks in `_process`, `start`, `_spawn_burst`, `_burst_from`), model.js, selftest.py (the Python
estimate), timeline.js, index.html, fields.js, inspector.js, app.js, style.css, instructions.js; tests
`game/tests/pass83_timeline_test.gd` (7), `tools/level_editor/selftest_TIMELINE83.py` (47 checks). docs/level_editor.md
needs: the Timeline tab's Share lane paragraph out; the roster lane's etches (draw ticks, dotted under 3 px); the window
box; the readout's "Spawned in the past N s"; the cards; the row form's Draw every; waves_schema.md: `interval` (keys_TIMELINE.md).

**Pass 84 (2026-10-16, v0.70): the Timeline change, every creature's shadow.** Garry approved the lead's critique of the spawning system and asked to build it (tools/dl/p84/REQUEST.md), with his notes: keep every spawning option and add controls rather than remove them, every per-row override editable in the Timeline, charts that say plainly what they are made of, collapsible sections with an obvious collapsed state, a subtle mark for view-only vs editing sections, and every spawning change in the game and the sims. The commit before is e158f49 "before LevelEditor Timeline change". Three lanes (tools/dl/p84/INTERFACES.md): SPAWN (rows learn the events' tricks, Red Canyon migrated and proven with 20-run sims), TIMELINE (the tab rebuilt), SIMVIEW (the Sim's per-second overlay). Then Garry: "The shadows on the enemies seem to have started to break": the lead found the pass-60s budget (70 shadows within 10 m) that Garry's bigger crowd had exposed, and gave every creature on screen its shadow.

**Lane SPAWN: one spawning language.** Garry agreed there were too many ways to spawn the same thing (continuous rows,
rows paced as waves, waves[], swarm events, coloured elites, Elites every, the specials clock, the portal wave, the hell
channel) but wanted every option kept ("better add too many controls than too few"). The roster row became the one
way: `pace` gained "once" (one wave at t + offset), `every` may be [min, max] (a timer: a fresh gap after each wave),
`enemy` may be a list (with `enemy_weights`: a row's `weights` were already its presence keyframes) or "roster" (each
creature drawn from the rows live then by elite_weight, the coloured-elite draw), and a row may carry `elite` (the
coloured-elite arrivals, waiting for colour, Hot Sauce on their clock), `special` (all forced specials), `banner` (a
toast as a wave comes), `ring_radius` (the swarm's classic even ring), `chance` and `t_jitter` (rolled once a run), and
the editor's `role` and `name`. Rows that are not "the mix" (one creature by id, no elite, no special, not once) stay out
of the portal wave, the Elites' candidates and the pass 58 join, so a swarm that became a row plays as its event did
(the same spots, numbers and dice: pass84_spawn_test plays both side by side). A map may set `floor_curve`, the density
floor: the regular continuous rows are drawn at once while the crowd is under it, within the cap and the hard cap.
Old maps' swarm / elite / elite_every events and waves[] still play through their own code; `Model.convertLegacy`
(the page converts on load) and `tools/migrate_timeline.py` (files) turn them into rows, and Red Canyon was migrated
(its five swarms and Elites every are rows r6 r7 r8 r9 r17 r53; a backup in tools/level_editor/backups/). The editor's
estimate (model.js spawnEstimate and its Python twin in selftest.py) plays every new key, takes the Sim's creature
lifetimes (`opts.life`), and gives per second the cap, the load, the floor, the share of spawn checks the cap was full,
who is alive by creature and which rows starved (`Model.estimateSeries`); `Model.creatureDifficulty` (GDScript twin
WaveDirector.shown_numbers) is the one HP / ATK shown per row and second. Lessons: a row's `weights` already meant
presence, so the events' pick weights could not keep their name; a jumped clock (smoke_run, hell_check) would have fired
every once row it skipped, so a once row more than 2 s late is dropped like a skipped event; same-seed sims are not
bit-identical (they part within a few minutes whatever changed), so the proof is statistical (20 runs each), with the
director's own `spawn84` log lines to count the swarms and Elites exactly.

**Pass 84, lane TIMELINE: the Timeline in sections.** Garry asked for the lead's Timeline design with his notes: keep and
add controls ("better add too many controls than too few"), charts that say plainly what they are made of, collapsible
sections whose collapsed state is obvious, a subtle mark for view-only vs editing sections, every per-row option
(stats, colour, behaviour) editable in the Timeline. The tab is now a stack of nine sections (Ruler and controls, On
screen, Challenge, Composition, Spawned so far, Spawn rows, Events, Curves, Warnings; FIELDS.SECTIONS), each a bar with
a chevron, an eye (view only, a recessed darker background) or a pencil (editing), its name, a line of what it is and
its controls; collapsed, the bar stays in place hatched with a dashed frame, a summary ("peak 260 alive at 1:53 · cap
full 15 times") and "collapsed: click to open" in yellow; per-map state in the browser, Collapse all / Open all; the
inspector folds to a hatched strip. New view lanes from the estimate (lane SPAWN's per-second aliveBy / cap / load /
full / starve) and the Sim (lane SIMVIEW's /api/sim/overlay plus result.json's keep_up): On screen (alive per second,
the hell channel on top, the cap turned into bodies at the crowd's mix, the floor, red where the cap is full with the
starving rows on hover), Challenge (seconds of the hero's damage to clear the screen = crowd HP ÷ his DPS, or health bars
lost clearing it = HP × bite ÷ (DPS × EHP), the Sim's `challenge`; zones per measure; the Sim's line and deaths; with no
Sim a typical hero 20.4 × power², EHP 100, because the Sims show his effective HP barely grows), Composition (% of the
crowd by creature, on screen or spawned in the past N s, estimate or Sim). Each has "What is this?", a legend naming
every line and a "How it is worked out" box (tools/level_editor/timeline_model.js RECIPES, page-free and Node-tested).
Spawn rows are grouped by stage / role / both / none (each group folds to a band with its rows as thin lines), coloured
by role (or creature), and say how many and how often (≈N/min from the estimate, "12 every 60–90 s", "once 24"), their HP
and ATK in play at the start (Model.creatureDifficulty) and badges (elite, special, banner, pattern, ring radius, hell,
no cap); + Row offers continuous, waves, once (a swarm), a coloured elite, Elites every, a special; Suggest roles fills
untagged rows. The inspector shows a row in folding groups (Schedule, Creature with one / list with enemy_weights /
roster draw, Where and how, Presence, In the estimate with a mini-chart of its spawns a second and its HP over its life,
Overrides with every block the game deep-merges: Body + Size × / Radius ×, Ranged and Charge in full, Kamikaze,
Artillery, Sniper, Flee on hit), with Split at <cursor> and → once / waves / continuous. Events keep bosses and Elites,
with the portal after each boss marked (its settings on a click). Curves gain the Floor lane (floor_curve: drag, double-
click, + Floor). Warnings list the estimate's findings with Go to (cap full and who starves, rows that never spawn or
never make 1% in any 10 s, the crowd's HP doubling in a second, a floor above the cap, identical rows overlapping). The
map converts an old file's swarm / elite / Elites-every events and waves[] to rows on load (lane SPAWN's convertLegacy);
a map with nothing old is left byte for byte (no churn). Validation learned the new keys. Tests: selftest_TIMELINE84.py
(113 checks), PACE81 re-pinned (Pacing offers Once, Every is an interval).

#### docs/level_editor.md
Added the section "Pass 84: the Timeline in sections, one way to spawn" (written by the lane; the lead may trim).

Garry's new Timeline (lane TIMELINE) draws what a Sim really did on the map's own clock: how many creatures were up on
each channel against the cap, how full the cap was and which roster rows wanted to spawn and could not, the crowd's
threat against the hero, and how long each creature lives (lane SPAWN's estimate reads that).

- **game/tools/sim_run.gd**: a sampler of its own (the `_sv_*` functions at the end, three hook lines), reading the game
  without changing it: one entry per recorder row of alive_hell, load, load_hell, cap_hell, hard_cap, cap_full (a share
  of the second, checked every 0.2 s of play), threat (sum of max HP x bite a second, the boss left out), hero_dps,
  hero_ehp, challenge (threat / (DPS x effective HP)); the breakdowns alive_hell_by and starving_by (rows by the
  director's keys); life_by (deaths and seconds lived per creature and stage: births from EnemyManager.serial, deaths
  from creature_dying); meta.rows_played (the roster as played) and meta.simview_ms (its cost).
- **tools/sim_batch.py** and its twin **tools/level_editor/sim_avg.js**: the play-second aggregate keeps the new series
  (threat banded, challenge a median, the two breakdowns); overlay() averages the runs by CLOCK second (the boss fight
  and the portal wait, which freeze the clock, left out) into overlay.json beside result.json.
- **tools/level_editor/sim_io.py**: GET /api/sim/overlay?map=<id>[&id=<sim>][&top=N]: the newest finished real Sim of the
  map (or one by id) for the Timeline; an older sim is worked out from its players' files (alive, cap, power, level and
  who is alive); creatures past the top N folded into Other; `stale` when the map was saved since.
- **tools/level_editor/sim_model.js**: the Sim tab's "The crowd against the cap" also draws the load the cap counts
  (dotted); new charts "Cap full" and "The crowd against the hero" for sims that carry them.
- Tests: tools/level_editor/selftest_SIMVIEW84.py, game/tests/pass84_simview_test.gd.

For docs/level_editor.md (the lead): a short "Pass 84: the Sim on the Timeline" paragraph: what the overlay's lines
mean (status_SIMVIEW.md "What each one is"), that it shows the newest finished Sim of the map and says when the map was
saved after it, and that a Sim from before pass 84 shows only the alive count, the cap, the hero's power and who is
alive.

#### The proof (2026-10-16)
10 runs of Red Canyon (the map as saved before SPAWN's migration, sha 979fcc8ee483), Drifter, a quarter of the board,
death keep, 25:00 of play, on a private snapshot: 25:31 wall, 2.5 s of play a second a run at 6 at once.
- Alive never above the hard cap (260) but for ONE second in one run (262): splits and summons are not under the
  director's hard cap (a game fact, not the sampler's).
- cap_full: 200 to 894 of ~1,150-1,310 normal seconds a run sat full at least half the second; of those only 1-51 had
  the load under 90 % of the cap at the sample (they were full on BODIES: early in stage 1 the 260-body hard cap binds
  before the 135 load cap, the fodder counting half). Seconds at the cap with 0 % full: 0-2 a run.
- Starving: the rows starving most are r25 (index 17), r29-r34 (stage 2-3 rows); a strong run (level 57-68) starves
  mostly r1 (index 0, the opening goblins).
- life_by (mean seconds from spawn to death, stage 1 / 2 / 3 / after): werewolf 23.8 / 17.7 / 7.8 / 6.9, skeleton
  55.1 / 20.4 / 14.1, skeleton knight 58.1 / 38.5 / 12.0 / 8.7, red goblin 28.5 / 18.4 / 24.2, imp (hell) 9.4 / 5.8,
  hellhound 12.7 / 7.6, armadillo 40.9 / 18.3, Tumbleweed King 87.5 (includes his walk-in); the long-range ones live
  long (rocketeer ~690 s: they sit off-screen).
- Bosses on the clock: King 430 (fight 71 s median, 10/10 beaten), Gila 860 (129.6 s, 10/10), Brander 1290 (48.2 s,
  5 reached, 2 beaten by 25:00).
- challenge (median over the run): 2.1 to 48; threat peaks 30-76 million (HP x damage a second).
- The sampler's cost: 3.5 to 4.9 ms of wall time a second of play (about 1 % of a run's wall time).

**Pass 85 (2026-10-17, v0.71): Fadeaway's Puppet look, the title on the chosen sand with presets, natural tints, two trees, three or four teleports, the Watch's run setup, the Dynamite Bandit.** Garry: "Redo Fadeaway art asset with the new puppet method"; the title "still features the old sand texture" and its arrangement "from a bunch of presets"; "slight random colour variations to the 2.5d environment assets ... natural for that element"; another palm and Joshua tree; smaller teleports, at least 3 (33% 4), spaced and never landing by another; the Timeline's right-drag pan in Rows; in the Watch the bot after power-ups, a Hero Settings pop-up to start and restart a run with the descent, build icons, sound off, the bot's goal plaque; the Cactus's "Cactus Bandito Look" from Dynamite_Bandit.png throwing red pulsing dynamite in place, a little ahead, faster, a 1 s fuse, blasts like the hero's. Four lanes (tools/dl/p85/INTERFACES.md): FADE, WORLD, TOOLS, BANDIT. The lead re-pinned two tests to Garry's map edits.

**Lane FADE (pass 85): Fadeaway redone with the Puppet method, look FAD-D (fresh).** Garry: "Redo Fadeaway art
asset with the new puppet method". No Level Editor ran the queue (the jobs lock's owner was dead), so the stages ran
from the shell as the hero_puppet job runs them: `tools/puppet.py fadeaway` on FAD-C's stills (screen blue, Klein):
four arms-out fronts (only c0 held the arms clear; c1-c3 hung them against the body), three sides (c2 held an arm
forward) and three backs (all with the arms higher than the front; c1 the closest): front c0, side c0, back c1;
Hunyuan3D-2mv two tries (about 2 min under the comfy lock, nearly identical, arms free): try 0; Blender clean, rig,
running.fbx retarget, colours, guides. The first rig put both hand tips on the flared hem of his wide shorts at knee
height (the finder's lowest arm-side vertex along the forearm), so the hand bones ran into the shorts and the bend
test spiked the hem; rebuilt by hand with tools/dl/p85/FADE/rig_fix.py (puppet_blender's rig, the tip the farthest
vertex near the forearm's line, the wrist a hand before it; the first rig and its guides moved to
tools/dl/puppet/fadeaway/old/20261017-020429/), bend test clean. Guides tools/dl/drivers/fadeaway_puppet_run (+ _depth,
silhouette.json, run/idle ratios within 0.015 of May's). The look entry was written with the Level Editor's line
writer (content_io: FAD-C's words, stills and seeds, method hero_puppet, every puppet setting recorded, FAD-C's badge
and cut-out, fresh) and walked by gen_art with the sidecar (merged by content_io, layout kept). The first walks: front
(stick figure), fd and back (depth) good; side and bd on depth came out with a dull grey-purple jersey, twice on new
seeds (anim_seed 1 -> 2, "vivid bright purple" in anim_hint): the raw Fun Control frames were dull, not the fringe
clean. Side and bd were walked on the puppet's stick figure instead (depth_views fd, back): the still's purple, bd
turned away throughout. Against FAD-C: the run's head size matches the idle's better (side 1.05 vs 1.11, back 1.07,
bd 0.97), the back run strides clearly instead of crossing its legs, each view at the puppet's own run/idle height.
In game (game/tools/_p85_FADE_shot.gd, look forced through Save.set_hero_look, sandboxed by godot.sh): eight
directions and the Basketball thrown at goblins, beside FAD-C: same size class, the ball unchanged. Sheets:
tools/dl/p85/FADE/fadd_vs_fadc_sheet.png, phone_size.png, fadd_vs_fadc.gif, ingame_*.png, zoom_run_<view>.png,
tools/dl/puppet/fadeaway/compare/. Tests: pass85_FADE_test (3), pass66_shape, pass69_hero, pass67_fadeaway,
pass76_looks green; check_scripts; selftest 13,051 passed.

**Lane WORLD (pass 85): the title on the chosen sand from six presets, natural tints for every prop, a twin palm and a
lopsided joshua tree, smaller Teleports, three or four of them.** Garry: "the Main Menu background still features the old
sand texture ... random but from a bunch of presets", "slight random colour variations ... natural for that element",
"another variant of a palm tree and joshua tree", "the teleport area a bit smaller ... at least 3 ... 33% of the time 4
... never teleport the Player next to another teleport ... never spawn close to each other". *Sand*: RedCanyon reads its
sand, oases and colours from Run.map, null on the title until a run starts, so the title always drew pass 81's default;
TitleStage._build_map now lets the map's def stand in for Run.map while the map builds (put back after), and
menu_backdrop.jpg was re-shot (tools/menu_backdrop.gd, preset 0 unless `preset=`). *Presets*: art/ui/title_scene.json
`presets` (six, each composed by eye at 1080x1920 and with the 130 px inset: the framing pair moved in to z -5..-7 so
their trunks show under the title wash); one drawn per title visit (TitleStage.force_preset for captures); a kept world
takes the last preset off with PropField.mark/truncate (the slots and shadows given back) before laying the next.
*Tints*: props.json `tint` per kind (hue window, sat_min, h/s/v ranges, link; up to two parts, the second on the first's
result), three rolls per prop from a hash of its spot packed into INSTANCE_CUSTOM.w (integers under 2048, safe in the
compatibility renderer's half floats), applied in prop_billboard.gdshader from the painting's own material uniforms, so
no draw call is added; outlines and greys untouched. Sheets of every painting untinted and at eight rolls (the corners
of the roll cube) checked by eye; the purple sage's hue range halved after the first sheet (one roll read magenta).
*Trees*: tools/gen_prop_variants.py (rows fan_palm_b/c, joshua_tree_d/e, `--cands`); the curving palm kept the original's
crown and lost its trunk texture, the twin palm (fan_palm_c c2) won and is registered as fan_palm_b; the joshua trees
painted from the original's raw copied its silhouette again (as in pass 83), so they were painted again without the
reference: the lopsided leaning tree (joshua_tree_d c3) won (the clump of three read as lollipops); its trunk stood 0.19
of the quad left of centre, so the painting was scaled to 0.8 about its foot and centred on it (the collider is the
spot) and its shadow measured again. *Teleports*: radius 1.8, height 2.7; `params.per_map` {3, 4, max_chance 0.33,
kin_spacing 40} (StructureManager.per_map_count, kin_spacing, KIN_RELAX 0.75 only in the last fifth of the tries),
`land_clear` 15 and `land_water` 2 checked by StructureManager.teleport_landing_ok from Game.teleport_hero (one hook).
Top-down captures of six seeds (tools/dl/p85/WORLD/teleports/): 3-4 Teleports, closest pairs 35.7-56 m, forty landings
each never nearer than 15.1 m to a Teleport, never wet.

Lane TOOLS (pass 85; Garry's "LevelEditor" and "Watch Tool" requests). **The Timeline pans** with the right mouse button
inside the Spawn rows section (timeline.js `onPanDown`/`panTo`, a capture-phase press so no bar ever sees it, a grab
cursor `body.tl-panning`, no context menu there; words in the Instructions and the section's help; selftest group
`selftest_TOOLS85.py`). **The Watch opens with a Hero Settings pop-up** (game/tools/watch/WatchSetup.gd, the panel's dark
tool style): the hero and his look (with his badge), the map, the seed (Random or a number), the speed, the time limit,
Down!, the sound, the damage numbers, the unlocks, the bot's preset and every option, and the Upgrade board talent by
talent (six rank slots each: a free slot buys up to it in form A, A turns to B, B sells it and the ranks above) with the
presets none / a quarter / half / full and the PC save's board (tools/watch.py writes tools/dl/watch/setup.json with the
presets, the save's board and the finished Sim results for the grey line). Start Run starts the run down the spawn beam
(Watch.gd `_begin_run`, `launch_of(..., spawn)`; the bot waits until he lands); the header's **Restart run** (R) opens
it mid-run with the run paused behind it: Start Run ends the run (recorded with its decision log) and starts the chosen
one once that game is gone (`_pending`, two frames), Cancel goes back. `--go` (or `--autoquit`) keeps the old instant
start for checks; new `--actions` words `setup`, `start`, `cancel`, `quit`, `setup.<field>=`. **The sound is off by
default** (`--sound`). **The Build shows the game's icons**: chips with the icon, the name and the level, a weapon's
mutations as smaller purple-edged chips after it, rows Weapons / Evolutions / Cards / Items / Perks, wrapping
(WatchPanel `build_rows`, `_chip`). **The bot's goal plaque** (WatchPlaque.gd) over the phone view's bottom, above the
speed badge: "Kiting", "Running away", "Dodging", "Exploring the map", "Going to a Totem Pole", "Grabbing a power-up:
Heart", "Hunting a special: Red Goblin", "Going to the shop", "Picking a level-up", "Choosing a mutation", "At a Totem
Pole", "Coming down"... with the goal's reason beneath, switching with a short fade (a word must hold 0.35 s). **The
bot strives for power-ups** (BotGoals PU_*: seen from 28 m, worth what they give now: a heart by how hurt he is, the
vacuum by the XP lying, the nuke, buffs and the shield by the crowd near; the run's taste floored at 0.85; grabbed from
5 m): 16-run sims (Drifter, a quarter, 15:00, Down! keep) took 13.3 -> 32.5 power-ups a run with fewer falls (11.4 ->
10.3) and higher levels (39.3 -> 43.3 at 15:00); `Bot.summary().powerups` {lying, goals, reached}. Tests
game/tests/pass85_tools_test.gd (10). Lesson: a test that starts a Watch must keep its record in memory and write no
decision CSV (`analytics=memory`): without a repo the CSV fell back to the PC's user://analytics/runs.

Lane BANDIT (pass 85): the Spit Cactus's Dynamite Bandit look (SC-A) and his dynamite. Garry: "Cactus Bandito Look ...
There is a reference file called Dynamite_Bandit.png. Throw Dynamite Sticks instead of Cactus things - and they explode
like the Player's ones, after a 1 second delay ... they can fly faster ... aim a little in front of the Player (not like
the Harpooner), just a bit. The throw should be in place, based on the ref. The Dynamite projectiles will always be red
and will still pulsate". **The look**: his picture cut into its four figures (tools/dl/p85/BANDIT/ref_*.png); every
painting picked by eye from Klein candidates (tools/dl/p85/BANDIT/cands.py, review sheets cands_*.png): the front
redrawn from his standing front figure (front_from_picture, 5 seeds, c2), the back from our front with his back figure
as a second reference (8 seeds over two rounds: the first round's hats were small and round, the second's words "huge
floppy ... tilted" gave c6), the walks are free Wan clips front and back (a first build on the walk_hold driver, the Vulture Raider's, put his
stocky painting on thin Mixamo legs: he changed body between standing and walking), the release poses (the hop with the arm flung up, the hand empty) from our front / back with
his two throwing figures (c1 each; c2 front painted a stick in the air and a shadow), the wind-ups as edits of our front
and back (front c1: the stick up behind his shoulder with a lit spark, the other hand pointing; back c1: one stick, the
others painted a second stick in the free hand). gen_art gained default-off keys: `windup_hint` / `windup_back_hint`
(a wind-up pose painted before the `aim_hint` pose, cache <sk>_windup_front/_back), `windup_fit`, `aim_lift` (the
attack pose raised off the floor: the throw's hop); the attack strip is wind-up, breath, release, breath from the front,
then the same from behind. The game reads `attack_throw` (EnemyDef, top level or a look entry; JsonContent and
apply_art now also take `attack_views` from a look entry): each view's half of the attack strip is wind-up | release,
the wind-up frames while he winds up, the release frames while he holds the throw (EnemyManager._throw_frame). **The
dynamite** (`ranged.shot: "dynamite"`, `ranged.dynamite`, `ranged.release_hold`; EnemyManager._throw_dynamite,
dynamite_aim, _throw_hold_start/_tick; ProjectileManager.hostile_dynamite, _dynamite_ring, _dynamite_lie,
_tick_dynamite_lying, _dynamite_blast): he stands to wind up (no ring at the hero any more), the stick leaves his hand
(`dynamite.hand`, muzzle_point's terms; muzzle_point takes the point as an optional argument now) aimed at the hero's
feet plus 0.35 of his velocity over the flight (at most 2.5 m), flies at 9 m/s (the spit 5.4) tumbling, harmless, the
hero's red Dynamite Stick model (art/props/dynamite_b_stick_red.glb, at 0.6 of its size: at full size it was as long
as his arm; the pulse halo counts from 0.2 m, the stick's length had made a disc of it) with the cactus's pulse in red and a smoke-grey
trail; a red ring of the blast's radius marks the spot from the throw to the blast; it lies 1 s with the hero's fuse
spark (out 0.5 s before), then blows like the hero's stick (burst, ground ring, camera kick, w_lob_boom): the hero
inside radius 2.0 + 0.4 takes the cactus's damage and is thrown back 7 (lift 2) unless he evaded, the crowd within 2.4 m
is pushed (10) and not hurt. He holds the release pose 0.35 s, then walks again. Sounds: the throw w_lob_throw, the
death en_goblin_die. Difficulty probe (quarter board, Calavera, seeds 11-13, scratch game/tools/_p85_bandit_probe.gd
with old=1 for the spit): stage 1 at 4:17-5:15, the cactus's share 2.34 maxHP a minute before, 2.17 after (145, 136,
104 sticks thrown, 13-18 % of them caught him); stage 2 at 10:00-11:40 too few cacti to read (0.60 before, 0.33 after).
Tests game/tests/pass85_bandit_test.gd.

**Pass 86 (2026-10-17, v0.72): the Dynamite Bandit hops and grows.** Garry: "Make the Cactus jump up a little bit when
he throws the Dynamite stick. Make em a bit bigger. try again". The lead: `ranged.throw_jump` (a sine hop through the
release hold, 0.45 m on the Spit Cactus) in EnemyManager._throw_hold_tick; the cactus `size` 1.5 -> 1.85 and `radius`
0.45 -> 0.55; checked frame by frame with game/tools/_p85_bandit_shot.gd (tools/dl/p86/jump/sheet.png).

**Pass 87 (2026-10-17, v0.73): stages separated, Endless, Nightfall and the Blood Moon, the Big Mouth's glow and punch, Solenne and Fadeaway on the Puppet method, four mummies, the evade, the black barrels' coins.** Garry: "It's time to make a significant change to how our Stages work. Now Player Unlocks Stages and is only able to enter them after having completed the previous one" (the portal with a 1 minute timer and only Extract, then Endless; a Stages menu with pictures and difficulty; a blueish evening for stage 2 and a reddish blood moon for stage 3; the Watch, the analytics, PostHog and the Level Editor by stage); answered: fresh runs retuned, 7:10 / 10:00 / 13:00, the menu on every Play, Endless deaths bank everything. Also: the Big Mouth's tongue out with a glow, a wind-up and a punch; the bandit's facing; Solenne's Puppet look on the Catwalk and Fadeaway's size, shoulders and back 88, each in two versions (a precise and a loose prompt); a new mummy from mummy.png in four looks with the arms always up; the evade shown; black barrels with 1-5 coins. Ten lanes (tools/dl/p87/INTERFACES.md, INTERFACES_STAGES.md); the first MUMMY agent ran out of room and a second one finished it; the lead made Endless respect live limits.

Pass 87, lane SGAME (stages as their own runs, in the game). Garry: "Now Player Unlocks Stages and is only able to enter
them after having completed the previous one ... Player kills the boss and the Portal that appears shows a 1 minute
timer before the Endless Mode will activate. There is only an Extract button now in the Portal." The map keeps one
timeline; `timeline_data.stage_list` cuts it into windows (WaveTimeline.stage_window / stage_at / stage_boss /
stage_filter / stage_entry; the fallback `stages` x `stage_length`), and `timeline_data.endless` holds Endless's keys
(ENDLESS_DEFAULTS, endless_mults: compounding HP and damage, linear capped speed). A run plays one stage: Run.start_stage
(Game._start_chosen_stage from Run.choose_stage or the launch's `stage`, 1-based) puts the fresh run at its window's
start; WaveDirector skips what came before the window (_enter_stage_window), holds the clock at the window's end and
brings the stage's boss there (_stage_end_reached), and on its death marks the stage beaten (Save.stages_beaten,
stage_unlocked, stages_menu_open; old saves migrated from their boss flags and kill totals) and runs the portal's
countdown (portal_seconds_left, tick_portal_countdown; the portal dialog keeps it running); at 0 Phase.ENDLESS
(start_endless): a huge first wave from the stage's late roster, a wave every 10 s, each fixed afresh with its
multipliers (source_for), the crowd kept up between them (_endless_fill), XP x xp_share (Game), coins x coin_chance
(PickupManager.endless_coin_chance), no bosses, Elites or specials; the old endless loop and continue_to_next_stage are
gone, and the portal dialog's "go on" became "not yet". Run gained stage_clock (the HUD, pause and Down! clocks),
run_time (survive quests, the best time), endless_time, stage_beaten, outcome; the summary carries them. Red Canyon was
migrated by tools/dl/p87/SGAME/migrate_stages.py (backup red_canyon.pre87.json): Sundown 430, Nightfall 600, Blood Moon
780, stages 2-3 stretched into their windows (the HP curve stays a formula on the run clock; lane TUNE retunes). Tools:
smoke_run plays stage 1 to its boss, says Not yet, runs the countdown out in the dialog and plays three Endless waves
(portal=extract for the old ending), hell_check plays stage 3 as its own run (its fight on the play clock), sim_run.gd
takes `stage=k`, the arena's clock reads the windows. Tests: pass87_sgame_test.gd; re-pinned pass28, pass46_pacing,
pass47_combat, pass48_world, pass58_wv, pass60_ui, pass62_pc.

Lane TUNE (pass 87): stages 2 and 3 retuned for a fresh level-1 hero, and Endless. Garry: "Stages 2 and 3 retuned so a
fresh hero can clear them, clearly harder than Stage 1" (a stage picked from the Stages menu is a fresh run: level 1,
the start weapon); the brief: a quarter of the Upgrade board clears stage 2 (10:00 + the Gila) most of the time, half
clears stage 3 (13:00 + the Brander), each harder than the stage before, Endless kills a typical hero in a few minutes.
After lane SGAME's migration (stage windows 430 / 600 / 780 s, stages 2-3 stretched) stage 2 carried pass 62/64's
numbers, made for a level-22 hero arriving with stage 1's build: a fresh hero met about 11 times stage 1's crowd HP and
6 times its bite in the first minute and fell about 50 times in a stage-2 run (sim, Drifter, a quarter board).
Method: the run sim (tools/sim_batch.py --stage k, the explorer bot, a private --sim-dir) with death=keep, every fall
counted by phase (the stage, the boss fight, the portal, Endless) from the phase series. The bots are far weaker than
Garry (death=end: the explorer cleared stage 1 at a quarter board 1 time in 10, the expert 0, both falling at ~1:40 to
the skeleton knights; Garry cleared it at level 30 with a third of the board), so the targets are relative, as pass 64's
were: stage 2 at a quarter and stage 3 at half about as hard as stage 1 with no board (the first-time stage everyone
clears), and each stage clearly harder than the one before at the same board. Garry's stage 1, stage_mults [1, 2.2,
3.34] (the coins' worth) and the HP formula (pass62_pc_test pins it through 7:10) are untouched; the knobs were the
stage-2 / stage-3 rows' HP x (a factor ramping through each window on the migrated numbers), the ATK x curve's points
after 430 s, the cap curve (a soft start in each window), the Elites' and the bosses' event HP x (the bosses' only as the
data-HP floor of the seconds mode: a fresh hero's 40 s / 60 s of full DPS now rules, as for the King), r18 a second later
(431: stage 2's side of the steps), and lane SGAME's `endless` keys. Tools: tools/dl/p87/TUNE/bake.py (reads the map as
it is, changes only these numbers, skips a row someone else edited), est.py (rows' numbers by stage minute), summ.py,
fallsmin.py, table.py; eight bakes, about 300 simulated runs. What the sims showed on the way: the fresh hero snowballs
(stage 2's creatures drop 1.6-2.7x stage 1's XP a kill), so a soft stage was beaten by level 20 at 4:00 and its second
half got easier, while a slightly hard opening sank the run (stage 3: +30% HP and ATK took the falls from 4 to 14), so
the openings stayed soft and the late rows ramp steeply (stage 2 x0.26 -> x1.4, stage 3 x0.30 -> x0.60); the hero
outgrew stage 3 by its end until its late rows were raised; Endless's 120-strong first wave at x1.2 ATK felled a third
of the stage-2 heroes within 15 s (Garry's words give the first wave "higher speed and HP", not attack). Tests re-pinned
on purpose: pass62_pc_test and pass64_df_test (stages compared at the middle of their own windows; the Elites found by
window). Numbers and the before/after table: balancing_TUNE.md.

**Lane SUI (the stages on screen).** Garry: "After Player had completed the 1st Stage ... A new menu unlocks, which will
pop-up whenever Player presses Play ... Each of the Stage Buttons will feature a screenshot ... and a quick description of
the difficulty ... The Stages that are locked will show the requirement ... Upon tapping the Stage Player will proceed to
play that Stage with the chosen hero"; "the Portal that appears shows a 1 minute timer before the Endless Mode will
activate. There is only an Extract button now in the Portal". New **ui/StagesScreen.gd** (+ .tscn, ScreenBase, the
Wanted kit): header "Stages" with the back square and the chosen hero's badge, "RED CANYON · DRIFTER", one card per
`stage_list` entry (WaveTimeline.stage_entry): the stage's picture (art/ui/stages/<map>_s<k>.jpg from lane SLOOK, 972 x
374 covered, striped until it exists) with an ink STAGE k tag and the stage's name in paper slab over a soft ink foot,
a sage BEATEN stamp on a beaten stage; under it the difficulty line in the stage's colour (sage / brass / rock), the
description, "7:10 to the boss" and the boss's plate and name. A locked card is aged with its picture under an ink wash
and a padlock and "To unlock: Beat the Gila Grande"; a tap plays the locked sound and shakes it. A tap on an open card
calls `Run.choose_stage(i)` and starts the run. **TitleScreen._on_play** opens the menu once `Save.stages_menu_open`
(the live title keeps its world for the way back); before that PLAY plays stage 1. **PortalDialog** rewritten: BOSS DOWN /
STAGE k CLEAR, the Extract road as before, and an ink Endless card with "STARTS IN" and the count (brass, rock and
swelling in the last 10 s), "A huge wave, then a tougher one every 10 s, until you fall." and the gold line; NOT YET
kept; the dialog drives the game's countdown while up (`Game.tick_portal_countdown`) and the game closes it when Endless
starts; with a pinned count or no game it closes itself (`expire`, signal `expired`). **HUD**: the clock plate shows the
stage's own clock (Run.stage_clock), then the portal's count on rock with ENDLESS IN hanging under it, then Endless's
time on ink with WAVE n (rock tag, a swell on each wave) and the ENDLESS banner (`on_endless_started`,
`on_endless_wave`, called by Game; `test_stage_clock` for captures). **Results**: the star line Extracted / Fell in
Endless / Run over, "STAGE 1 · SUNDOWN · BEATEN" in the stage's colour, the run's time, "Endless 01:24 · wave 9" in rock;
PLAY AGAIN replays the same stage. Tools: wanted_shots 18-stages / 18b / 18c (only=stages; inset=130 too), 15 / 15b /
15c (the new stage clear), 06f-hud-portal / 06g-hud-endless (only=hud_stage); touch_audit stages (PLAY opens the menu
with stage 1 beaten, every card, locked ones refuse, open ones start their stage, the back square), stages_play (a real
tap on stage 2 starts a fresh level-1 run at stage 2 with the clock at 00:00), portal_expire, endless_banner;
game/tools/_p87_SUI_flow.gd (scratch: boss down -> dialog -> NOT YET -> the HUD's count -> back in -> Endless -> wave 2
-> a fall -> the Results). Tests game/tests/pass87_sui_test.gd.

**Lane SLOOK (the stages' looks and their pictures).** Garry: "there is a blueish dim filter on the map for Stage 2 to
indicate evening, and a redish filter on Stage 3 to indicate hell / bloodmoon ... This should look good and not mess up
how elements 'read' during the game. The screenshots in the Stages menu should reflect the look." Most of the world is
unshaded paintings, so the sun and the ambient alone could not tint it, and a tint uniform in every world shader would
have meant hooks in EnemyManager, PropField, PickupManager and BillboardSprite. Instead a stage's `filter` {color,
strength, actors} (timeline_data.stage_list) is two quads over the whole view (core/shaders/stage_filter.gdshader,
blend_mul, the quad in clip space so any camera sees it, never culled), drawn by core/systems/StageLook.gd at render
priority -7: after the opaque world and the water, before every ground mark, shadow, gem, coin, outline, effect and
projectile, which stay untinted on top and pop more on the darker world. Split by pass 72's stencil: the world
(stencil 0 sand/water/sky and 2 scenery) at the filter's strength, the creatures and the hero (stencil 1) at `actors`
(default 0.35) of it, so they stay brighter than the ground. The quad's colour reaches the screen sRGB-encoded, so
StageLook hands it in linear light: on the screen each channel is multiplied by the colour as authored. A white factor
hides the quads (stage 1 costs nothing). Hell (pass 43's ground) comes from the entry's `hell` (fallback without a
stage list: the third stage on, as before); Game's stage_started lambda calls `StageLook.of(self).show_stage(s)` (it
called map.set_hell). The dust gusts and the dust devil now draw before the filter (priority -8; at 2 they were a pale
veil over the blood moon). Red Canyon, tuned side by side on a staged scene (tools/game/_p87_SLOOK_read.gd: creatures,
a special's rim, an Elite, outlines behind a saguaro and a structure, red rings, a danger disc, an orange line, gems,
coins, a chest): Nightfall #3D55C8 at 0.48 (a slate blue-grey sand), Blood Moon #6A1A28 at 0.6 over the hell ground (a
dark crimson: a dark red keeps the red warnings readable by brightness, a bright red flattened the danger disc). The
Stages menu's pictures: game/tools/stage_shots.gd builds the arena on the title's roll (88) with the run's dice fixed,
hides the props and structures between the camera and the crowd, puts the stage's own creatures (its window's most
weighted rows, the hell channel first on a hell stage, each row's look and stats) on the south shore of the east oasis
facing the hero (his back to the camera), applies the stage's look and shoots through a SubViewport sharing the run's
world, 2x supersampled to 1248 x 480 -> art/ui/stages/red_canyon_s1..3.jpg (the palms, the lake, the fort wall, the
cliffs and a sliver of sky behind); `overview=<png>` draws the roll from above for choosing a spot. The debug arena's
WORLD tab gained "Stage look" (each stage's look on the spot); perf_late gained `look=k` and prints the GPU time.

**Pass 87, lane STOOLS: the stages in the Level Editor, the estimate, the Sim, the Watch and the analytics.** Garry:
"These changes should be reflected in both the Watch tool, the analytics (posthog too) and the LevelEditor ... Watch Tool
should give me a choice to which Stage bot will be playing in. LevelEditor will have tabs in the Timeline for each Stage
(more Stages can be added and it should be fairly simple to add (choosing the colouring should be possible too)).
Analytics should make it easy to indicate which Stage Player was playing on and which Stage the data is about."

**The Level Editor.** model.js reads the map's `stage_list` (one window a stage, the sum of the earlier lengths;
without one, stage_length x stages as before: no churn): `stageList`, `stageWindow`, `stageStart/End/Len`, `stageMarks`,
and every page use of the old one stage length re-read through them (the ruler, the shades, the mutation offers, a
curve's seeded points, the snap targets, the summaries, the validation: a boss away from a window's end, a path time past
its stage's own length). A strip of **stage tabs** above the Timeline (stage_tabs.js): All | Stage 1 · Sundown 7:10 |
... | + Stage, each with its colour dot. A stage tab draws its window from the left edge (timeline.js: the axis from
`T0`, every sampled line read through it), the ruler counting the stage's own clock with the map's in brackets, only
the rows open in its window (a row spanning windows on both tabs, its label kept at the window's edge), its boss, the
portal's countdown and two minutes of Endless after it; each tab remembers its own Sim (the newest of its stage by
default). A **stage's card** (its tab, or its band on the ruler) holds its name, difficulty line, description, picture,
length (a new length asks: keep its own times, cutting what falls past a shorter end, or stretch them; the later stages
move either way, named in the question), boss (its boss event follows), look (a starting look, the colour with a live
swatch: the map's sand, rock and wall colours and the boss in daylight and in the stage's look, the strength, lane
SLOOK's share on the creatures) and hell ground; Delete stage asks with what goes. The edits are page-free in
stage_model.js (Node-tested). Settings gained the Endless block (lane SGAME's `endless` keys) and says the old endless
keys are not played; the Instructions tab a "Pass 87: stages as their own runs" section.

**The estimate per stage.** spawnEstimate's `opts.stage` plays a stage run (model.js STAGE_RUN_NOTES, the Python twin in
selftest.py step for step): an empty map at the window's start, only its own events, its boss at its end (from its entry
when no event), the kill-rate curve read at the seconds the fresh hero played, then the portal's countdown with the
director's clock held at the end and Endless (wave 1 at once, a wave every `every` s, the crowd kept up to the
stage-end cap x `endless.cap`, from the late roster) drawn after the window. "All" stitches every stage's run. On a
map with a stage list the old endless after the last stage is gone (`stageAt` keeps the last stage, `fixedFrom` never
refixes), as the game's WaveTimeline.

**The Sim.** sim_batch.py `--stage k` (settings `stage`, checked against the map's stages; each player gets `stage=k`;
the made-up players of a later stage start at its window), its job spec and the Sim tab's Stage box, the history and
the settings line say the stage; result.json's players say their `stage`, `outcome`, `boss_killed`, `endless_s` (from
sim_run.gd's meta) and `summary.stage_run` counts the boss kills, the outcomes and the median Endless survival
(sim_avg.js the twin). The bot's new option `portal` (endless, the default in every preset: never walks to the portal,
answers it "not yet" and plays on into Endless; extract: walks there and extracts), in Bot.gd, sim_run.gd's BOT_ARGS,
sim_batch's BOT_KEYS and the Watch's bot form.

**The Watch.** The Hero Settings pop-up has a Stage row (every stage of the map with its name, length and boss): with
Every unlock on every stage, off only the stages the PC save has unlocked (watch.py's setup file: `save_stages`,
sim_batch.save_stages reading the save as Save does, an unmigrated save from its old boss flags and kill totals); the
run starts that stage (the launch's `stage`); `--stage k`, check actions `setup.stage=`, `setup.unlocks=`; the header
says the stage's name, its own clock, the portal's countdown and the Endless wave; the grey line is a Sim of the same
stage (a whole-run Sim from before pass 87 only for stage 1).

**Analytics.** The run record's header names the stage (`stage_index`, `stage_id`, `stage_name`, `stage_start`,
`stage_length`, `stage_count`) and how the stage run ended (`outcome` extracted / died_endless / died_after_boss / died
/ quit, `boss_killed`, `stage_clock`, `endless_s`, `run_time`); a row in Endless has `en`; the stage's boss down is a
`stage_beaten` event (Endless begun stays Game's `endless`). PostHog: every run event carries `stage_id`, `in_endless`,
`endless_wave`; `stage_beaten` and `endless_started` events; `run_end` the header's stage keys; the portal's choice
`extract` or `not_yet`. tools/posthog_boards.py: a new "88fits · Stages" board (how stage runs end, boss-down rate,
Endless survival, by hero and player, when each player first beat each stage), "Runs a day, by stage" on Pulse, the
stage and outcome on Players' recent runs, deaths in Endless or before; rebuilt (ten boards, 68 tiles, all queries
checked); any board filters by stage with a dashboard filter on stage_id. analytics/dashboard.html: a Stage filter for
every list, the stage's name and outcome on the summary, the facts and the history. analytics/SCHEMA.md documents it all.

Tests: tools/level_editor/selftest_STOOLS87.py (176 checks: the windows by hand and against the Python twin, the edits,
the stage-run estimate twins on fixtures and Red Canyon, the page's wiring, the Sim's settings, args, made-up players
and the stage_run summary twins, the Watch's launcher and the save's stages, the analytics files); the selftest's twins
of the stage-free maths re-read through the stage list (snap targets, fixedFrom, creatureAt's stage, stage_mult);
game/tests/pass87_stools_test.gd (8); pass57_an_test re-pinned (the portal's choice). The full selftest: 13,157 + this
group, only lane SOL's Solenne looks pin failing. Checked by eye: the Level Editor on a spare port (the tabs, a stage
card, the length confirm), the Watch (its Stage row, a stage 3 run), the dashboard's filter, a stage 2 Sim.

For docs/level_editor.md (the lead): "Pass 87: the stage tabs" from the Instructions section above; for
docs/waves_schema.md nothing new beyond lane SGAME's keys (the editor writes stage_list and endless as SGAME documents).
For CLAUDE.md: the boards are ten (Stages added); `python tools/sim_batch.py ... --stage k`; `python tools/watch.py
--stage k`.

Pass 87, lane BIGMOUTH (Garry: "Remove the tongue from the **Big Mouth** 3d Object. But keep a kind of a bright shining
thing in the back of the Mouth when it's shooting the Laser. Add a bit of a wind-up animation to the Big Mouth as it's
about to shoot, something short. And a visual 'punch back' when the laser is being shot"). The model
(`tools/blender_mouth.py`, `art/props/big_mouth.glb` and the gold `loud_mouth.glb`, both regenerated) has no `Tongue`;
its inside is a dark throat: a hollow bowl open to the front, its inner skin `Cavity` (dark, lit by the glow) and its
outer skin `ThroatBack` (the lips' colour at 0.55, so the back of the mouth no longer reads as a dark egg or a hole
behind the gold lips), each single-sided, and a floor on the jaw (`Floor` inside, `FloorBack` outside) so the wide-open
mouth shows a dark hollow, never the sand; `Glow` (a core deep in the bowl) and `Flare` (an empty in the opening) are
for the code; `game_views=1` renders the game's angle (tipped back 32 degrees, camera 48 degrees up) from four sides,
shut, gaping and open, to tools/dl/mouth/. `LaserBeam.gd`: the **throat glow** (`params.beam.throat {size 0.9, gain 1,
walls 0.9}`, `_setup_throat`, `_tick_glow`, `_flare_facing`, `core/shaders/mouth_glow.gdshader`: a depth-tested
camera-facing flare, so it shows only through the open mouth, faded as the mouth turns its back on the camera): dark
at rest, 0.2 + 0.6 f^2 through the wind-up (it shines between the teeth before the jaw opens), 1 with a flicker while it
pours, gone in a tenth of a second after, always in the beam's colour (pink, Slow Roast orange, Bad Breath green); the
old whole-cavity white glow is gone. The **wind-up** ("the breath", `params.beam.windup {seconds 0.24, rear 0.35 rad,
gape 36 deg, swell 0.1, tremble 0.03 m}`; it was a fixed 0.12 s clamp-and-squash Garry never noticed): the mouth turns
to its target, its lips rear up, the jaw gapes, it swells, the glow gathers, a shiver at the end; the beam pours at its
end. The cooldown clock still starts at the pull, so the wind-up is taken from the cooldown and the time between beams
is unchanged; the first tick comes 0.24 s after the pull. The **punch** (`params.beam.punch {back 0.36 m (Loudmouth
0.45), climb 0.2 rad, pop 0.2, hz 2.8, decay 7.5, pulse 0.3}`, the Revolver's familiar.kick shape): as the beam leaves
the mouth kicks back along its aim, its lips climb and it swells, springs past rest and settles in about 0.6 s; every
pulse (0.28 s) kicks again at 0.3; the orbit is eased in `_fam_base` and the kick laid over it unsmoothed, the beam
leaving from the lips where they are. A pull while the beam still pours (cooldown shorter than the beam) re-aims it and
pours on at once with a fresh punch, no wind-up. The flash bursts moved out along the line (0.6 / 0.9 m, the pulse puff
0.7 m) so they no longer cover the lips. Numbers in big_mouth.json and loudmouth.json; keys in tools/dl/p87/keys_BIGMOUTH.md.
Captures: game/tools/_p87_BIGMOUTH_shot.gd (frame by frame round a shot, the pack set up the screen, down it or to the
side, the mouth held where it films best, crops round its orbit place so the punch shows), outputs tools/dl/p87/BIGMOUTH/.
Tests game/tests/pass87_BIGMOUTH_test.gd (10); pass46_weapons_test's wind-up test re-pinned (the breath, not the clamp)
and pass61_wp2_test reads the wind-up's own length.

**Lane SOL (pass 87): Solenne on the Puppet method, catwalking; two looks SOL-F (precise words) and SOL-G (loose
words), both fresh.** Garry: "Let's try a Look using the Puppet Method, I always felt it was weird that she looks at us
while walking to the side. Make sure to use the Cat Walk animation instead of a Run one for this. Make 2 new versions
(trying a more precise and less precise prompts)". Her played SOL-B walks on a stick figure whose face was pinned to the
viewer (pass 55's pose_fit) with a side still whose sun disc is turned to the camera; SOL-A's profile side read as a
head with two ears. The puppet (stages run from the shell as the hero_puppet job runs them; Garry's Level Editor held
the queue): `tools/puppet.py solenne --look SOL-B --clip catwalk_walking.fbx` with the arms-out side on words of its
own (tools/dl/p87/SOL/words_side.txt: her face in profile looking right, the rays all round): four arms-out fronts
(c2: slim like her, arms clear), three sides (all in profile; c2, rays like her front's), three backs (c0, the front's
arm angle); Hunyuan3D-2mv try 0 (a spiky sun ball with a face); the rig put her shoulders at the tips of her high
flared collar (the finder's "shoulder top" is the first slab 1.6x the neck's width) and was rebuilt with
tools/dl/p87/SOL/rig_fix.py (the shoulder on the straight arm's axis under the shoulder's round top, the elbow half
way; the first rig in tools/dl/puppet/solenne/old/); Mixamo's Catwalk Walking retargeted (36 frames), guides
solenne_puppet_catwalk_walking (+ _depth, silhouette). Each look painted its own side, three-quarter front and
three-quarter back (and their hurts) as four candidates on gen_art's own view prompts plus its words, picked by eye
(tools/dl/p87/SOL/still_cands.py); front, back, cheer, death and the front/back hurts stay her own paintings
(still_keys). The first SOL-F walks showed two faults the method shares with both looks: the three-quarter back on the
depth guide painted a black glossy reflection under her feet, and the side's far arm (projected up to her chest by
the 25-degree camera) came out as a hand at the back of her neck; both looks walk only the back on depth and the side
on tools/dl/drivers/solenne_puppet_catwalk_walking_farhide (tools/dl/p87/SOL/far_arm.py: the far arm dropped where its
wrist is above mid-torso).

The two prompts (recipe keys; everything else equal):

SOL-F, precise:
- pose_hint: "Her head always turns together with her body: her sun face looks the same way her chest and her feet
  point, the way she walks, and never turns towards the viewer unless her body faces the viewer. Her head is a round
  glossy yellow ball, not a flat disc, with long pointed golden-yellow rays sticking out all round it like a crown of
  spikes, so the same spiky sun shows from every side; her face (calm half-lidded eyes with thin black brows, a small
  nose, small red lips) sits on the side of the ball she faces. A slender figure: a long neck in the high collar of the
  glossy black latex catsuit, a small waist, long legs in knee-high black heeled boots, black gloves. Both arms hang
  straight down at her sides, hands open, not on the hips."
- side_hint: "Strict profile: her sun face is seen from the side looking to the right, where she walks: one eye, the
  tip of the nose and the lips at the right edge of the round yellow head, the back of the ball and its rays on the
  left; never turned to the viewer, never looking over her shoulder."
- back_hint: "the back of the round yellow sun ball with its rays all round and no face, the zip line down the
  catsuit's back, the heels of the boots; both arms swing loosely at her sides and never reach behind her back"
- anim_hint: "a slender woman in a glossy black latex catsuit with a high collar, black gloves and knee-high black
  heeled boots; her head is a round glossy yellow sun ball with long pointed golden-yellow rays all round it, the same
  spiky sun from every side; her head turns with her body and her face (calm half-lidded eyes, thin black brows, small
  red lips) looks the way she walks; the same slim proportions and the same height in every frame"
- pose_motion: "walking in place on the spot like on a treadmill with a slow catwalk stride: each foot placed straight
  in front of the other on one line, the hips swaying from side to side, the shoulders level and still, the chin up,
  both arms swinging loosely at her sides with open hands, the head and the body facing the same way the whole time"
- anim_negative: "a human head, hair, a helmet, a face on the body, a second head, a weapon, a cape, turning the head
  towards the camera, looking over the shoulder, a flat disc seen edge-on, a hand on the hip, hands behind the back,
  arms crossed, crouching, bending forward, jumping, a second figure"

SOL-G, loose:
- pose_hint: "She looks where she walks."
- anim_hint: "a woman in a black catsuit with a yellow sun for a head, looking where she walks"
- pose_motion: "a catwalk walk in place"
- side_hint, back_hint, anim_negative: "" (set empty on purpose, so her own top-level words do not apply)

What each prompt changed (both on the same puppet, guides, seeds scheme and picks by eye; sheets
tools/dl/p87/SOL/sheet_final.png, phone_final.png, walk_final.gif, heads_final.png, cmp_side_big.png, cmp_fd_big.png;
in game tools/dl/p87/SOL/ingame_dirs.png, ingame_frames.png, ingame_zoom_BFG.png): in both, unlike SOL-B, her sun face
looks where she walks: a profile looking right in the side walk and idle (mirrored to the left by the game), a
three-quarter face turned to the lower right in the diagonal front, the back of her head in the diagonal back; the
front still faces the camera (she walks at it). SOL-F's precise words kept her design from every side: all four side
candidates in profile with the rays all round (a spiky sun ball), the red lips, her slim build; the fd candidates
turned body and face together. SOL-G's one-liners also turned the face (the words that matter are "looks where she
walks"), but three of its four side candidates lost the rays (a bald yellow ball with two ear-like spikes, the model's
own reading of a flat sun seen edge-on) and the picked one keeps only a few short rays at the back; at phone size its
side and diagonal heads read as a yellow ball rather than a sun; the walks themselves (motion, size, colours) came out
alike, since the stick figures drive the motion. Sizes (opaque height, run/idle median): F and G front 1.03, fd
0.97-0.98, side 0.94, bd 0.94, back 0.96 (the puppet's own catwalk ratios; SOL-B 0.97-1.01). Tests:
game/tests/pass87_SOL_test.gd (4) with pass66_shape, pass55_lead, pass60_art, pass66_gd, pass55_hv, pass76_looks,
pass69_hero: 76 green; check_scripts clean; smoke_run OK; the Level Editor selftest pinned her looks as exactly SOL-A..E and is re-pinned
(tools/level_editor/selftest_S.py: those five among hers): 13,208 passed.

**Lane FADE (pass 87): Fadeaway, fixed, two fresh looks FAD-E (the precise prompt) and FAD-F (the loose one).**
Garry: "Fadeaway - Still has some problems: the size problem, they are inconsistent: run front is considerably larger
than front stand ...; back run shoulders look slouched; back 3/4 right/left the back number 88 is gone. Make 2 new
versions (trying a more precise and less precise prompts)". Measured first (tools/dl/p87/FADE/measure.py, the opaque box
per frame; match_scale.py, the standing head found in every frame at scales 0.75-1.35; size_table.py): the bounding box
cannot see the bug (FAD-D's front run stood at 0.99 of its stand's height) but the body can: his head in FAD-D's front
run was 1.12-1.18x the stand's (back 1.07-1.10), FAD-C's 1.09-1.12 (side 1.11). The causes, all in the guide and the
bd painting: (1) tools/puppet.py takes the puppet's Neck bone for OpenPose's neck point, 0.18 of the torso ABOVE the
shoulder line in the back views (an inverted V: Wan paints sloping, sagging shoulders = the slouch); (2) the running
puppet, leaning into the stride and seen from 25 degrees above, puts his face only 0.13 torso above the shoulders in
the front view (the Mixamo run: 0.29): the head is painted sunk into the shoulders, the figure comes out short for its
body and the fit by height blows the body up (the size); (3) gen_art paints the bd still from the front still alone,
with no back words, so fadeaway_c_bd's back was plain purple and no walk could keep an 88 (and the Running clip swings
the bd shoulder line from square, 0.113 of the frame, to edge-on, 0.019, and the near arm's backswing crosses the back:
half of every bd stride hid it anyway).
The fixes: a new guide tools/dl/drivers/fadeaway_puppet_run_up (tools/dl/p87/FADE/driver_fix.py from the puppet's
fadeaway_puppet_run): the neck point on the shoulder line in every view (square shoulders), the face lifted per view to
about the Mixamo run's head height (front/fd nose 0.29 torso, side ears 0.36, bd 0.50, back 0.56: upright), and in the
bd view only the shoulder twist calmed (width 0.08 + 0.2 x (w - mean): 0.069-0.088) and the backswing kept on its own
side (elbow and wrist at least 0.6 of the half shoulder width out from the back's middle). Every view walks on it as a
stick figure (the depth guide had dulled the purple in pass 85). The bd painting is made from the front AND the back
still (refs [front, back], words naming the 88 across his upper back) and named per view (`still_keys.bd`). Each view's
run is then sized to its standing still by the head (`run_scale` per view, from the head width, the head template and
ladders checked by eye): the run's head within 1-2 % of the stand's in every view of both looks.
The looks (both fresh, method hero_pose5, painter Klein, FAD-C's badge and cut-out; Garry's played look stays FAD-C):
- **FAD-E, the precise prompt** (stills `e`, seed_offset 2311): art_prompt "a tall, lean, athletic young Black man of
  about twenty with long arms and long legs, broad square shoulders held level, a straight upright back and his chest
  up; dark brown skin; a short rounded black afro with a white terry-cloth sweatband across his forehead; sharp angular
  features, a thin black goatee, heavy-lidded confident eyes and a sly half-smile; a sleeveless vivid royal-purple
  basketball jersey with gold trim round the neck and the armholes and a big gold number 88 printed in the middle of
  the chest; loose knee-length bright white basketball shorts with a purple waistband and a purple and gold stripe
  down the outside of each leg; white wristbands on both wrists; short white socks and white high-top sneakers with
  purple accents; standing straight and facing the viewer with his arms relaxed at his sides, empty hands", with
  pose_hint (chest up, both shoulders level and square), a back_hint naming "a big gold number 88 printed across the
  middle of his upper back between the shoulder blades, as big as the 88 on the front; both shoulders broad, square
  and level, his back straight and upright, never hunched or slouched", a side_hint, an anim_hint ("... he runs tall
  with his back straight, his chest up and both shoulders square and level") and plain negatives ("a basketball, a
  ball in his hands, extra arms or legs, a face on the back of his head, hunched shoulders, slouching, sloping
  shoulders, a plain jersey back without its number, a dull greyish jersey"). Picks: front c3 of 4, back c1 of 3, bd88
  c0 of 3 (face hidden, both digits on his back). Its first back flinch turned his head round to show a face and lost
  the 88 (the hero's hurt_hint "a grimace"): repainted from the back still (`still_keys.hurt_back`
  fadeaway_e_hurt_back88, c1 of 3: from behind, no face, the 88); its first down painting had a stray brown shape
  beside him: repainted (c0 of 3).
- **FAD-F, the loose prompt** (stills `f`, seed_offset 2377): art_prompt "a tall Black basketball player with an afro
  and a white headband, a purple number 88 jersey, white shorts and white sneakers, standing straight and facing the
  viewer, arms at his sides"; back_hint "Seen from behind: the number 88 on the back of his jersey, standing
  straight."; no side_hint; anim_hint "a basketball player with an afro and a white headband in a purple 88 jersey and
  white shorts"; bd words "Three-quarter back view of this character, turned away to the upper right, standing
  straight, with the 88 from the second image on his back. Same style." The short words gave him a white 88 (nothing
  said gold), a big round afro, a slimmer build and plainer shorts; two of three bd paintings barely turned (c2 picked);
  his cheer lost the 88. His first back walk painted a basketball in his hand: the hero's anim_negative "no
  basketball, ..." reads as a double negative in a negative prompt, and "a basketball player" invites the ball: walked
  again with plain negatives ("a basketball, a ball in his hands", anim_seed 1).
Walks: 53 s a view on the AI server (each rolled up to three times by gen_art's colour checks); F's back and bd, then
both bd walks twice more as the bd guide improved (old clips kept in tools/dl/p87/FADE/old_clips/). In game
(game/tools/_p87_FADE_shot.gd, the look forced in the wrapper's sandbox): eight directions beside FAD-C and FAD-D, the
runs at the stand's size, the 88 on the back and the back-diagonal in every frame captured. Sheets:
tools/dl/p87/FADE/sheet_C_D_E_F.png, phone_C_D_E_F.png, runs_C_D_E_F.gif, ingame_dirs.png, ingame_backs.png,
ef_other_anims.png (cheer, die, hits); the size table size_after.md. Tests: pass87_FADE_test (4: both entries,
their strips, the game wears them, every view's run head within 5 % of the stand and the run never taller than it
by 5 %; the same measure fails FAD-C and FAD-D's fronts), pass67_fadeaway re-pinned (Garry's bonus level 3 read from
his JSON), pass85_FADE, pass66_shape, pass69_hero, pass76_looks green; check_scripts 587 files 0 errors; Level Editor
selftest 13,206 passed.

Lane MUMMY (pass 87): four new Dust Mummy looks from Garry's mummy.png.
Garry: "Mummy - Let's have another go at the mummy as I really didn't like the previous iterations. Method: Same one as
we used for the skeleton. Ref: mummy.png. 2 direction. Important to make sure that the arms are always outstretched and
high up (kind of like a zombie). 4 Looks from the start (differing by seriousness / walking cycles)." Four looks of
content/enemies/dust_mummy, all `fresh`, DM-0 still played: DM-F "serious shuffle" (a slim menacing mummy close to
Garry's drawing, Mixamo Walking with the legs' swing x0.55, run 10 fps, falls on its back), DM-G "serious lurch" (the
same build, Orc Walk leaning 10 degrees, 15 fps, falls back and rolls onto its face, `anim_seed` 1), DM-H "goofy bounce"
(a round chubby mummy with a big head, Garry's Scary Clown Walk, 15 fps, unravels into a heap: `death: collapse`),
DM-I "goofy limp" (the round mummy, Walking with the right leg's swing x0.3, 12 fps, falls on its back). The skeleton's
method (creature_pose2: a Klein still per view, Wan Animate on an OpenPose driver, tools/gen_art.py --variant run
through tools/asset_job.py with a sidecar, merged in place by tools/dl/p87/MUMMY/entry.py): fronts as Klein edits of
Garry's front figure (tools/dl/p87/MUMMY/cands.py, serious and goofy wordings, with and without the style anchor),
backs from each picked front plus his back figure (`back_ref`), colour-matched to the front (cands.py
match_to_front), all picked by eye. Arms up in every frame came from the drivers: tools/pose_driver.py `arms=zombie`
gained `arm_wide` (a yaw out from straight ahead) and `fore_drop` (the forearm's own slope), one driver per view
(`pose_front` raised for the camera above, `pose` for the back, where raised arms rise further); the round goofy
mummies also need `body=` per view (pose_driver's goblin retarget: the front to the round front painting, the back to
the back painting), since on a man's proportions Wan made them slim, swung a bandage strip like a whip and crossed the
arms over the head (DM-H's first run), and a head scale above the painting's (`top_nose` x3.9) drew a giant head that
swallowed the raised hands (DM-H's second). Arm targets were read off the paintings in units of the neck-to-ankle
distance (tools/dl/p87/MUMMY/finish/drv_units2.py: wrist rise above the neck, reach out, elbow angle, ear spread):
arm_wide is applied at the target's forward distance, so the effective elevation is atan(tan(arm_drop) cos(arm_wide)).
New drivers tools/dl/drivers/mummy_shuffle_f/_b, mummy_lurch_f/_b, mummy_bounce_f/_b, mummy_limp_f/_b,
mummy_bounce_fit_f/_b, mummy_limp_fit_f/_b. Garry's Scary Clown Walk.dae was rebuilt for Blender 5 (no Collada
importer) by tools/dl/p87/MUMMY/dae_to_blend.py; his Zombie monster walk GLB's arm chain runs through _guideBn_ bones
and its head juts forward between the shoulders from above, so it was dropped. tools/gen_art.py (additive): a creature
look's `remap_hues` (an object or a list of blocks with artkit's min_sat / max_sat, on the walks and the death clip:
the walks' yellow drift back to beige, the teal and green feet Wan smeared in, and for the goofy two a pink cast, the
saturated red eyes spared by max_sat) and `match_still` (each walk frame's saturation and value matched to its view's
painting, the lines, the outline and the red eyes spared). Checked every frame (tools/dl/p87/MUMMY/sheet_DM-*.png,
z_DM-*_*.png, final_four.png at phone size) and in the arena (game/tools/_p87_mummy_shot.gd, tools/dl/p87/MUMMY/shots/).
Known flaws: DM-F's stepping foot shows a dark sole in 5 of 12 front frames; DM-G's fall flips the body mid-air before
it lands on its face (animate.fall_clip's prompt says "on its back"; two seeds did the same); DM-H's backs are slimmer
than its round front painting and its hands come out small with bent elbows (goofy "hands up" more than reaching
claws), with a few orange flecks in its first back frames; DM-I's walk grins (an open mouth under the eye slit). Tests
game/tests/pass87_mummy_test.gd (4), pass53/54_waves and pass66_shape unchanged and green.

Lane FIXES (pass 87): the Dynamite Bandit's back, the evade, the black barrels' coins.
Garry: "Cactus ... looks the wrong way when looking at the player. At least from the back the directions seem to be
swapped." The bandit look SC-A's back paintings came from Garry's back figure, which turns up-left (the back wind-up
aims with its left fist out to the left), while the look said nothing (back_faces "right"); and the attack strip's back
half (attack_views "front_back") read the FRONT key whatever the look said. Now `variants.SC-A.back_faces: "left"` and
EnemyManager._face_strip makes the throw's back half the back set for the mirror (`_render`) and for the hand the stick
leaves from (`muzzle_point`: from behind it had left from the empty hand). Checked with game/tools/_p87_FIXES_face.gd: the
bandit at the eight compass points round the hero, standing, winding up, releasing, walking in, backing off
(tools/dl/p87/FIXES/face_rr = before, face_fix = after, facing_*_before_after.png). The front was right (the head and the
pointing hand turn screen-right as painted).
Garry: "How do we show Player Evading? ... a text 'Evade' that flies out of the hero (just like with the 'Block') and hero
should become half transparent for a second". The hero's evade word (DamageNumbers, pass 47's DODGE) reads EVADE in its
own lavender (#cdb8ff; BLOCK stays pale), and the hero turns see-through: alpha 0.5 for 0.7 s easing back to whole by
1.0 s (Player.EVADE_GHOST_*; another evade restarts it, never fainter; cleared on death). His first pass steps aside
below alpha 1 (sprite_billboard `fade_alpha`) and his second pass, already in the see-through queue for the speed trails
(pass 49), draws him at that alpha (BillboardSprite.set_fade). Works with the hit blink (Ghost Step) and in the
trampoline's flight (tools/dl/p87/FIXES/evade1, evade2; game/tools/_p87_FIXES_evade.gd).
Garry: "The darker barrels should now give between 1-5 coins ... reduce the number of coins ... from just killing enemies
by the equivalent of claiming all of the dark barrels ... Add 2 more dark barrels". The darker ones are the rare black
barrels (pass 48; `light` in BarrelField's code): 35 barrels a map, the last two always black (9.26 black on average,
7.26 before); each black barrel holds 1-5 coins worth 1 (rolled with the map), dropped with its gems (gold source
"barrel"). The creatures' coins pay it back as a per-run bill (PickupManager.coin_debt = every coin the map's black
barrels hold, broken or not): while anything is owed, 40% of the coins the kills would drop go to the bill instead
(COIN_DEBT_SHARE 0.4 = the bill over a stage-1 run's kill coins), then they drop as ever. A multiplier on drops.gold could
not do it: coins a kill rise eightfold after stage 1 and with stage runs a run is one stage (BALANCING §34.FIXES). Sims
(Drifter, explorer bot, a quarter board, 10 runs each, tools/dl/p87/FIXES/sim_*): every full run paid its whole bill
(30.5 coins a map on average); the bot's barrels gave back about what it paid; the totals' run-to-run spread (an Elite's
coin is x5) hides a 28-coin shift.

**Pass 88 (2026-10-18, v0.74): the Big Mouth's one punch and white glow, no knockback on the hero, DM-G and FAD-E, a simpler Stages menu, Stakes on the Upgrade board.** Garry: the punch only when the laser starts; the "meaty part behind the mouth" (Cavity, Glow, ThroatBack) hidden and one bright white glow of their size shown while it attacks; the menu's idle spin stuttering at the bottom left; "Remove the Knockback from being hit for Player entirely" with a debug switch; "Let's go with DM-G" with its shadow under it; the Red Goblin hovering in death; "I'm going to go with FAD-E"; the Stages menu's words simpler with no creatures or bosses named, the boss hidden until met, no creatures in the pictures and their shadows fixed, "Choose a Stage", "Difficulty: Easy"...; on the Mirror, LifeSteal and Thorns replaced by Difficulty and Boss, prices by power, the cheapest first. Four lanes (tools/dl/p88/INTERFACES.md): MOUTH, TWEAKS, STAGEMENU, MIRROR.

Pass 88, lane MOUTH (Garry: "The 'Punch' from the laser should happen only once, when the laser shooting starts ... it's
looks like the mouth is having a fit"; "The tongue is still there actually. I mean the meaty part behind the mouth.
Looking at the .glb in blender it's actually the: `Cavity`, `Glow` and `ThroatBack`. Make it so these are all hidden, and
when the attack is happening there is a mesh that appears that is as big as all of those together, and glows bright
white as it used to, this will be our 'Glow' from now on"; "When spinning in an idle fashion is seems to stutter at a
specific point on the bottom left. Seems to only happen in Main Menu ... the mouth is always facing the camera when it's
spinning in the game ... make sure that it's happening like that in the Main Menu"). **The punch** comes once, as a beam
starts from a shut mouth: `params.beam.punch.pulse` 0 on the Big Mouth and the Loudmouth (and LaserBeam.PUNCH_DEFAULTS),
so the pulses every 0.28 s only puff and ring; a pull while the beam still pours re-aims it with no new punch
(`_start_beam(kick)`). **The model** (`tools/blender_mouth.py`, `art/props/big_mouth.glb` and `loud_mouth.glb`
regenerated): `Cavity`, `ThroatBack`, the small core and the `Flare` anchor removed from the GLB; `Glow` is now one closed
egg filling the old bowl's whole space (its middle and size, the front flat at the old rim, 0.8 x 0.29 x 0.28 m in the
model), white; the floor on the jaw (`Floor`, `FloorBack`) stays in the GLB but is shown only with the Glow (from behind, at rest, it read as the same meaty lump). **LaserBeam.gd**: the Glow gets its own unshaded
material (new `core/shaders/mouth_core.gdshader`: white, the beam's colour a faint edge, `throat.rim` 0.35), hidden at rest,
mostly lit the moment the wind-up starts (0.7) and full by its end, full while the beam pours, out in about 0.11 s after; as it
dies it darkens to the throat's dark (`GLOW_DARK`) and stays dark while the jaw is open more than 0.12 of its 80 degrees,
so the shutting mouth never shows the sand, then hides; the floor shows, hides and glows with it (white with a quarter of the beam's
colour, `throat.walls`); pass 87's beam-coloured flare quad and `core/shaders/mouth_glow.gdshader` are gone
(`throat.size` replaced by `throat.rim`); parts named Cavity, ThroatBack or Tongue on any model are hidden
(`HIDDEN_PARTS`). The mouth's rest pitch (32 degrees), chew (7 degrees at 2.6 rad/s, `chew_angle`) and orbit
(`ORBIT_DEFAULTS`, `BOB_RATE`) are named constants now. **The title** (`ui/TitleStage.gd`, Actor `_fly_mouth`): the stutter
was the title flying May's mouth as a gun: the guns' flourish kick (a 16-degree nod gone in 0.11 s) came every 3.5 to 5 s
from a clock seeded by the hero's id while the circle took 4.5 s, so it always fell at the same spot, the bottom left;
the mouth also flew level and turned out from her (side on, its underside showing). Now it flies as a run flies it with
no creature near: facing the camera all the way round, tipped back 32 degrees, chewing, the Glow hidden, on the run's
circle (1.25 m, 1.3 m up, 0.9 rad/s, bob 0.09 m). Captures: game/tools/_p88_MOUTH_title.gd (the title's companion frame by
frame over a full turn with a per-frame log), the in-run shots with game/tools/_p87_BIGMOUTH_shot.gd; outputs
tools/dl/p88/MOUTH/. Tests game/tests/pass88_MOUTH_test.gd; pass87_BIGMOUTH_test re-pinned (no Cavity/ThroatBack/Flare,
pulse 0, throat.rim, no fresh punch on a re-pull, the glow white with the beam's colour at its rim, the flare test gone).

Lane TWEAKS (pass 88). **No knockback on the hero** (Garry: "Remove the Knockback from being hit for Player entirely. Add
this option in the Debug version of the Settings menu"): `Settings.hero_knockback` (false by default, saved, in
PROD_LOCKED at false) and `Player.hit_knockback_on()`; off, `Player.shove`, `hit_knock` and a hostile `blast` do nothing,
and the two knockbacks that come through `apply_knockback` (Game.elite_explosion, a slam without `lift` in EnemyManager)
and the Gila's eruption throw (`_erupt_throw_hero`) ask first; the hits still land, and the Down! list leaves out
"knocked back" / "thrown" (`Player._logged_fx`). His own moves (dash, Thruster's lunge, the thruster burst, the leap,
Hang Time, teleports) and the two pulls (the silk line's pull, the harpoon's leash) still move him. The switch "Hero
knockback" sits in Settings' Debug panel (`HeroKnockback`, touch_audit taps it) and the developer menu
(`HeroKnockbackRow`); run records carry `settings.hero_knockback`; the sim and the Watch hold it off. Tests that pin the
pushes (pass332, pass333, pass54_combat, pass60_wp) switch it on. **Looks**: the Dust Mummy plays DM-G and Fadeaway
FAD-E, both approved (no longer fresh; pass87_mummy and pass87_FADE re-pinned). DM-G's shadow is its own
(`variants.DM-G.shadow` {drop 0.05, up 0.3}: its feet stood about a tenth of the cell above the blob). The Red Goblin's
dead body hovered over its blob (its last death frame ends 27 px of 128 above the foot line): a new key
`shadow.die_drop` (EnemyManager.die_drop_of / die_sink: the death strip sinks by that share of the cell at its last
frame, eased in by frame from 0 at its first) set to 0.2 on red_goblin; the green goblin (GOB-D) has the same frames.
Captures: tools/dl/p88/TWEAKS/ (game/tools/_p88_TWEAKS_shot.gd).

**Lane STAGEMENU (the Stages menu, simpler).** Garry: "Make the description of the Stages a bit simpler and don't
mention any enemies or bosses ... the icon of the Boss ... should remain hidden until Player had encountered it at
least once ... and the Boss name says 'Boss not encountered yet' ... avoid showing the enemies on the screenshot ...
fix the shadows and floor markings ... on the crystal, the Player and some of the enemies ... Add a call to Action.
'Choose a Stage' ... Just write 'Difficulty: Easy' 'Medium' 'Hard' 'Extremely Hard'". Red Canyon's stage_list words
(edited in place): "The canyon at sundown. Learn the ropes." / "Night falls on the canyon. Tougher, and longer." /
"Hell opens under a blood moon. Few come back."; `difficulty` Easy / Medium / Hard. ui/StagesScreen.gd: "Choose a
Stage" (slab 52) under the "RED CANYON · DRIFTER" line; the line "Difficulty: <word>" (`difficulty_word`: the entry's
word, a number 1..4 as a level, else by the stage's place: Easy, Medium, Hard, Extremely Hard from the fourth on); the
boss plate the Collection's silhouette and "Boss not encountered yet" until `Save.enemy_met(id)` (new: the
Collection's rule, seen on the sand in a run or killed), and a locked stage asks to "Beat Stage k" until the boss
before it is met. The pictures (game/tools/stage_shots.gd, re-shot): no creatures (`crowd=1` brings them back), the
hero alone at the oasis; the structures' rings and pies (ground marks: the teleport crystal's ring read as a stray arc
from the low camera) hidden; and every painted shadow laid again for the picture's camera. Cause, a capture matter and
not a game bug: a painting's foot stands a little up its camera-facing quad and the game pushes its shadow back by that
over sin(46 deg) (tools/prop_shadows.py), right for the play and title camera, but from the picture's ~10 deg camera
the shadow lay in front of the foot, under the palms, the crystal and the hero as a detached dark band. The tool now
casts the camera's ray through each painted foot (props by their manifest `shadow.z`, structures by `st_<id>`, the hero
by his frame's lowest opaque row) onto the ground and lays the shadow there (`_relay_shadows`, `_place_hero` with the
hero held cinematic so the game does not re-lay his). wanted_shots 18/18b show the Gila and the Brander hidden, 18c
all met.

Lane MIRROR (pass 88): **Spite became Stakes, the board priced by power and sorted cheapest first.** Garry: "The
following should be removed: LifeSteal, Thorns. To be replaced by 1. Difficulty ... 2. BOSS ... reassess the pricing
of the Upgrades in the Mirror ... the ones who's first upgrade is the cheapest go on top". The talent `spite` (id kept)
is **Stakes** with forms **Difficulty** (regular creatures: +10% HP, +10% attack, +4% speed a rank) and **Boss**
(bosses and Elites by their kind, the same steps), each paying a hidden +5% a rank more XP and coins; eight new player
stats (`danger_hp|attack|speed|bounty`, `boss_danger_*`) read through core/systems/MirrorDanger.gd: EnemyManager.spawn
(HP, speed, bite, XP scale; a boss's HP multiplied after the pass 83 seconds floor), `host_of` (every hit a creature
throws), PickupManager.drop_from (a coin's bounty, its fraction by chance: MirrorDanger.scaled_count), Game._kill_effects
(purses, the boss's coins); never in the arena. TextGen gained the kind "hidden" (the bounty is never written; the
form text names only the danger). The forms' icons are the skull and crown badges (art/ui/badges). An old save's Spite
ranks (Thorns / Thirst) are paid back in full at the old prices once (Save._migrate_stakes, once-flag stakes_v88, also
marked by buying a Stakes rank), said on the Upgrade board in two toasts (HomesteadScreen._show_board_note). **Prices**
from the run sim (tools/dl/p88/MIRROR/price_sims.py: 6 ranks of one form against an empty board, Drifter, 12 bots,
death=keep, to 7:10; 17 sims plus the Stakes at one rank and the Boss form through the King) and HeroPower: first ranks
Stakes 100, Fortune 300, Choice 325, Drive 375, Study 400, Stride 425 (was the cheapest at 300; the sims' best
survival), Grit 450, Nerve 500 (was 550), pass 46's ladder kept; the board's total 86,440 -> 74,190 (the seven power
talents -3%, Spite's 12,900 now 2,580). Difficulty at six ranks doubled the bots' falls for +13% gold; Boss at six made
the King's fight 78 s -> 102 s for +9% gold. **Order**: Registry.talents_list sorts by the first rank's price, then
`order` (TalentDef.board_before), `order` rewritten 1-8; the Level Editor's Sim tab lists them alike (sim_io); the sim's
and probes' preset boards never buy Stakes (sim_batch.PRESET_SKIP; a quarter 11 of 48 ranks). Tests:
pass88_mirror_test.gd; re-pinned pass83_meta (no Thorns form), pass45_ui (Grit by name), pass61_mr (summary in the
board's order), pass70_econ (the board's scale instead of x2.5 per rank), selftest_SIM77 (presets without Stakes, the
talents by price); the Level Editor's vocab.py / assets_model.js know the eight stats and the hidden kind.

**Pass 89 (2026-10-18, v0.75): the special attacks push the hero again, at half.** Garry: "make it so the special
attacks still knock player back. Like rocketeer rockets, dynamite, boss attacks, etc. but less than before. The regular
melee attacks shouldn't have a knockback still". Pass 88 had taken every push away. Now Player.knock_share splits them:
a regular attack (any creature's bite, bosses' included, and a plain shot) never pushes him; a special one (a charge,
every hostile blast, an Elite's death blast, slams, eruptions and their throw, custom and other boss attacks, the
Sniper's beam, a shot with its own weight) at the map's new `hero_special_knock` (default 0.5, push and lift alike;
WaveTimeline, JsonContent, the Level Editor's Scaling card, the run record's map_settings). EnemyManager marks the bite
`special_knock: false` and the Sniper's beam and custom attacks `true`; Player.special_push replaces the guarded
apply_knockback calls (Game.elite_explosion, the slam without a lift); _erupt_throw_hero scales its arc. The debug
switch is now labelled "Full hero knockback" (every push whole, as before pass 88). Tests: pass89_knock_test.gd;
pass88_tweaks_test re-pinned (only regular hits stay still).

**Pass 90 (2026-10-18, v0.76): the Watch's bot breaks out of rings and hunts only the special types; the Watch's Damage taken tab, chart hover hints and revive at will.** Garry: the bot "getting overwhelmed with enemies if they spawn in a `ring` around him" (push through in one direction, part of the safety style, a new preset); the hunt for "the Special enemy types like `Rocketeer`, `Sniper` and the `Harpooner`... Let's not hunt coloured fodder enemies"; a tab under HP and Danger with where the damage comes from; a hint when hovering the charts; "manually revive the Bot when he dies... as many times as I like". Two lanes (tools/dl/p90/INTERFACES.md): BOT, WATCH.

Lane BOT (Garry: the bot "has a nasty habit of getting overwhelmed with enemies if they spawn in a `ring` around him...
detects that he is surrounded and then just tries to push through in a specific direction"; and "I meant the Special
enemy types like `Rocketeer`, `Sniper` and the `Harpooner`. The ones which spawn outside the map. Let's not hunt
coloured fodder enemies"): the **ring breakout** (game/tools/bot/BotBreakout.gd, new; Bot.gd `_breakout_drive` in both
drive paths, option `breakout` in BOOL_KEYS and sim_run's BOT_ARGS). Two triggers: a **fresh ring** (12 or more creatures
first seen together at one distance, evenly round him; the arena wall closes a gap) sends him out through its thinnest
side before it closes; **shut in** (12 or more within 9 m, 90% of the ways shut, no 25° gap, open ground past the wall)
pushes him through the thinnest wall. The way: 32 directions, each costed by the bites waiting along a bite-wide lane (the
metres he would walk that close to each creature, x its damage against the crowd's mean, Elites and bosses double), the
crowd past the wall, the arena's edge and rocks, less a lean to his goal or the middle. He commits (full stick, no kite,
0.6-3 s) until he is out by a margin, then a 5 s cooldown. Decision kind `breakout` (phase start: the three cheapest ways,
the one taken, what he saw; phase end: out or the clock, seconds, metres, HP lost), intent `breakout`, meta.bot.breakout
{started, rings, out, timeout}. Part of the safety style (a style given as safety brings it unless `breakout` is given)
and the new **Survivor** preset (the Explorer with the safety style and the breakout; sim_batch's BOT_PRESETS, the Sim
tab, watch.py; WatchSetup reads Bot.PRESETS itself). Measured with the run sim (24 runs a cell, death=keep): neutral to a
little better (ring falls -11%, falls -3% pooled over stage 1 twice and stage 2; tools/dl/p90/balancing_BOT.md); a wider
coverage trigger tried first fired in every crowd and cost falls and levels (the pushes leave the gems behind). The
**hunt** now goes only for the special creature types (BotGoals.is_special_type: the type's gear badge, the Vulture
Raider, the Saiga Sniper, the harpooner), never the coloured variance specials; meta.bot.specials counts the types the bot
saw (came, killed, life_s) and keeps the coloured ones' recorder tallies under `coloured`. `Bot.on_revived()` clears a
life's state for the Watch's revive. A controlled ring probe for the sim snapshot: game/tools/_p90_BOT_ring.gd +
tools/dl/p90/BOT/ring_probe.py. Tests pass90_BOT_test.gd (10); pass82_watch_test re-pinned on purpose (its fake specials
are a gear-badge type now; the coloured tallies are `coloured_tallies()`); selftest_SIM77 gained the Survivor's checks.

**Lane WATCH (pass 90).** Garry: "add a tab in the HP, and Danger beneath which would show a breakdown of where the
damage comes from", "add a highlight to the Charts. One that shows a hint when you hover over the charts", and "allow me
to manually revive the Bot when he dies. Like, as many times as I like ... continue the run like nothing happened".
The Watch's HP chart now shares its place with a **Damage taken** tab (D, or the tabs over it): a table drawn like the
charts (game/tools/watch/WatchHurt.gd) of every hit he took, harvested each frame from Player.damage_log
(WatchData.read_hurt: the log keeps 30 s, so new entries are found by reference; heals left out), one row per source and
attack (Skeleton · bite, Vulture Raider · rocket, Gila Grande · volley): a coloured dot (boss red, Elite purple, special
pink), a bar (HP lost red, the Energy Shield's part blue, evaded grey outline), HP lost and share for the whole run, the
last 10/30/60 s (chips in the tab row), shield, evaded, hits; click a head to sort; the wheel scrolls; a row under the
pointer lights and its hint tells its story (incoming, lost, shield, evaded, blocked, biggest hit, last hit). The tab
takes 1.9 charts' height while it shows. **Every chart has a hover** (WatchChart.hover_info): a vertical line at the
pointer, dots where the named lines cross it, a hint box with the time, each named line's value (top line first, in its
axis's format), the share bands' values and the falls/revives/pickups within 6 px named; kept inside the plot, paused or
running. **Revive at will** (Watch.gd): `death` is "ask" by default now (watch.py --death, the Hero Settings' Down!
row: ask, auto, end, ad, keep): the fall pauses the run the frame after (Down! waits 1.2 s on the game's clock, so it
never comes; no results), a red box under the header says "Bot down at m:ss of play (clock m:ss): fell to <who>
(<attack>)" with Revive (R), Revive with blast (B), End run (E) (also the badge over the phone and the plaque); Revive
is Player.revive then full health and shield, its 2 s blink, the bar back, the banked screens resumed, no blast (the
crowd as it is), the bot told (Bot.on_revived, lane BOT); B adds Game.revive_blast and its push (the game's own revive
always blasts; the plain one is Garry's "like nothing happened"); "auto" revives by itself 0.5 s after the fall. Each
revive is the recorder's "revive" event (id watch), counted in header.watch_revives / watch.revives / watch.revive_t,
a "down" and a "revive" line in the decision log and CSV, "revived N×" on the HP tile and the end box, a green dot on
the fall's red mark, "· revived by you" in the Threat. Also: the safety style ticks lane BOT's "Ring breakout" box in
the Hero Settings (and with the safety style the box's state is always passed), the plaque says "Breaking out", and a
breakout decision gets no real-DPS change. Tests game/tests/pass90_WATCH_test.gd (7). No game code changed.

**Pass 91 (2026-10-19, v0.77): the Level Editor method "Creature from front + back pictures", the shatter death, the keyer's black line fixed.**

Pass 91 (lane ARTJOB, the Cactus Walker). Garry's green cactus came out with a black line at its bottom and a "pile of
pieces" death that was the whole cactus with pieces on it. The line: artkit.key_background cuts a cast-shadow band in the
bottom 12% of every figure, the pixels near the screen's hue; a green creature on the green screen lost its lower body
there and its ink lines stayed, which the outline filled into a dark band. Fixed at the cause: the cut is off when the
figure itself wears the screen's colours (artkit.figure_wears_screen, WEARS_SCREEN_SHARE 0.04 of the upper body). The
death: his creature JSON (cloned from the Blue Slime) had death "squash", and every painted dead still is a Klein EDIT of
the front ("This exact creature <dead_hint> ... keep the same proportions"), which keeps the creature whole. New death
"shatter" (artkit.shatter): the painting breaks into ~14 Voronoi pieces that pop, fall, turn and heap on the ground
(height-map stacking, pieces at 0.62 size at rest, a crack frame first; nothing painted, dead_hint unused). New Level
Editor method creature_pictures ("Creature from front + back pictures"): recipe front_ref, back_ref, picture_use as_is |
redraw, screen auto (blue when the picture's figure leans green; gen_art.auto_screen), plus every creature_proc input;
gen_art.picture_still lays the picture on the screen as a cached still (<id>_<slug>_front/_back) or has Klein redraw it.
Landed CW-E (fresh) on the Cactus Walker from his pictures. Balancing notes: shatter_pieces (14) and death_frames (6) are
recipe keys; the screen guard threshold WEARS_SCREEN_SHARE = 0.04 in tools/artkit.py.

**Pass 92 (2026-10-19, v0.78): the Desert Spider by the scorpion's method, four looks SP-A..D, the on-its-back death, the made walk and death in the depth-driver tool, the leg fix, explainer https://claude.ai/artifact/PuzdQ4H2dvaTJDEbtfKGwv (docs/spider/).**

## Pass 92, lane SPIDER: the Desert Spider (the scorpion's method on Garry's spider), four looks, a death on its back, an explainer

Garry asked for a spider by the scorpion's method from `spider._low_poly.glb`, four looks of rising cartooniness, a death
that leaves it on its back with its legs curled up, the Level Editor steps for the same result (with fixes on the way) and
an explainer like the puppet one (`docs/spider/spider_explainer.html`, pictures in `docs/spider/img/`).

- The model had **six legs** (three a side, plus two fangs), a 10.6 s idle-and-wander clip with no walk in it, a rest pose
  far from its stance (Sketchfab FBX -> GLB) and faced +Y (the probe said -Y). `tools/blender_limb_clone.py` (new) made the
  stance the rest pose (`rest=frame:0`, the clip dropped), copied the middle pair (`clone=left_leg_center_:left_leg_mid_:24:-0.06;...`)
  and turned the originals forward (`turn=...:-18:0.03`): `tools/dl/uploads/3d/spider_8legs/spider_8legs.glb`.
- `tools/blender_gait.py` (new) + `blender_depth_drivers.py` modes **gait** (a made walk: two alternating sets, L1 R2 L3 R4
  against R1 L2 R3 L4; swing, lift, flex, duty, bob, sway) and **flip_curl** (a made death: a jerk, a roll onto its back over
  roll_time, the legs curling in over the belly round one fold axis each, a bounce, a twitch, the dead pose held), plus
  **proportions** (body_scale, head_scale, leg_scale, scale_bones): the cartoon looks walk on the clay given their own
  proportions, since Wan Fun Control follows the depth's shapes over the painting's (SP-D's face vanished on the plain clay).
  Drivers: spider_walk / spider_death (A, B), spider_walk_c / spider_death_c, spider_walk_d / spider_death_d.
- New creature `desert_spider` (fire-ant numbers, no map brings it), four fresh looks SP-A (near-real wolf spider) .. SP-D
  (very exaggerated), all gen_ctl on the same model, picked by eye with the legs counted; it plays SP-B (a creature with
  looks must play one).
- Negative prompts reach nothing in this pipeline: Klein runs at cfg 1 with a zeroed negative, Flux.2 dev is guidance
  distilled (BasicGuider, no negative), Wan Fun Control at cfg 1 (ComfyUI skips the negative pass). Tried Klein at cfg 2 / 3
  with a real negative: see the explainer. The leg count is held by the clay and the anatomy words.
- Level Editor: the probe counts leg chains (`limbs`) and reads a creature's forward from its head bone; loose models in
  uploads/3d are listed and probed into their own folder; driver_depth offers gait / flip_curl and the proportions (in folds);
  new job kind and method `ref_limbs`; the enemy editor got "+ Depth driver…" and "+ Fix a model's legs…"; `file` fields keep
  their upload picker (src was a text box); the walk cache follows the painting, the seed and the control video
  (`animate.cache_fits`); methods.json tells the truth about negative words. selftest_SPIDER92.py.

**Pass 93 (2026-10-19, v0.79): the spider's legs fixed (`step=track`), SP-E light purple and SP-F light blue, the Level Editor's Drivers tab and frame picker.** Garry: "most legs aren't moving, and the ones that are moving are moving in the wrong direction"; drivers previewed in the Level Editor with frame numbers. Two lanes (tools/dl/p93/): LEGS, PREVIEW.

## Pass 93, lane LEGS: the Desert Spider's legs walk properly; SP-E (light purple) and SP-F (light blue) from SP-B; the explainer

Garry: "give me an instruction on how to improve on the Desert Spider SP-B version. I basically want 2 more versions which fix
the leg movement (currently most legs aren't moving, and the ones that are moving are moving in the wrong direction). And I
want the colour of the spider to be a light purple or light blue (1 each variant). Give me the instructions on how I ought to
have done it myself, then do it yourself, then update the HTML doc to only show the 3 variants - SP-B and the 2 new ones. Add an
explanation on how to fix the legs and what was wrong with them."

- **Diagnosis.** `blender_depth_drivers.py tips=1` (new) writes `tips.json`, every foot (the mesh tip of each leg chain's last
  weighted bone, farthest flat from the hip) per view and frame; `tools/gait_check.py` (new) draws the paths on the clay and
  judges each leg. Pass 92's made walk (`blender_gait` step swing: each leg turned rigidly round the vertical through its hip)
  moves a sideways leg's foot fore and aft but sweeps a forward or backward leg's foot ACROSS the body: in the front and back
  views L1, R1, L4, R4 travelled 94-132 px sideways (of 640) against 47-71 up and down (4 + 4 legs SIDEWAYS), and the middle
  legs' fore-aft step, foreshortened from 25 degrees above, barely showed; in the side view the front and back pairs slid back
  only 19-35 px a stride against 71-98 for the middle pair. The painter was not at fault: optical flow of SP-B's painted walk at
  each foot matched the driver's foot motion (cosine 0.6-0.98, 50-98% of its distance) wherever the leg is visible. Also
  excluded: a mirrored left/right sign (every planted foot slid back), thin depth legs, Wan smoothing, frame count, strip fps.
- **Fix.** `blender_gait.py` `step=track` (default `swing` keeps every old driver): each foot follows a straight track along
  the body (planted, sliding back at an even speed; an eased arc forward through the air peaking at `raise`), reached by
  turning the hip round the vertical and two-bone IK of hip and knee in the leg's plane (`two_bone`, knee up); `stride` 0.22,
  `raise` 0.12, `crouch` 0.1 (each track pulled in towards the hip: the straight resting legs had no bend to give, and the
  first track walk laid the front and back legs flat), `knee` up|down. Driver `tools/dl/drivers/spider_walk_v2`: step=track
  stride=0.22 raise=0.15 crouch=0.15 sway=0 bob=0.03 tips=1 (front view: 0 px sideways, 83 up and down; side: every planted
  foot slides back 90 px, lifts 61). The death is unchanged (spider_death).
- **gen_ctl `fit_ref`** (recipe key, true or a list of views): the painting's keyed figure fitted onto the depth video's figure
  (median width, centre and bottom) before Wan walks it. Klein paints some views far bigger than their clay (SP-E's front x1.54,
  back x1.6); Wan walked the painting at its own size along a smaller depth figure and left the painted legs outside the
  depth's as faded grey ghost legs beside the walking ones (SP-B's front has them too, hidden by its colour).
- **gen_ctl `no_green` "rb"** (recipe): green held down to max(red, blue) instead of red, for light blue looks; default unchanged.
- **Looks.** desert_spider SP-E (pale lavender / lilac) and SP-F (pale sky / powder blue): SP-B's recipe with the colour words,
  the belly in the death words and the outline colour changed, "the whole spider light purple/blue" appended, a motion line that
  says how a foot moves, drivers spider_walk_v2, death spider_death; side candidates counted by eye (SP-E k1 of 4; SP-F k6 of 8,
  k0 had nine legs); SP-E's back painted again (c0 of 3: the first kept the clay's brown legs); both looks walk their front fitted + softened and their side softened (`fit_ref` ["front"], `ctl_soft` {10, false, [front, side]}: the face and striped abdomen kept, no ghost legs); SP-F `no_green` "rb" (gen_ctl's green guard clamped green to red and turned its sky blue royal blue); fresh; the spider still plays SP-B. `game/tests/pass93_LEGS_test.gd`; pass92_SPIDER_test and
  selftest_SPIDER92 re-pinned to "contains the four" (they pinned exactly four looks).
- **Level Editor.** driver_depth's gait fold has step / stride / raise / crouch / knee (jobs.py SPECS + GAIT_KEYS, methods.json
  helps starting "gait: " so jobs.js folds them); a made motion's command gets tips=1 and a made walk runs gait_check.py as the
  job's second step (gait_check.png in the driver folder); methods.json names the sideways-legs lesson. selftest_LEGS93.py.
- **Doc.** docs/spider/spider_explainer.html now shows SP-B, SP-E and SP-F only, with section 4 "Fixing the legs: what was
  wrong and how" (top / front / side foot paths before and after, depth GIFs with the feet marked, the measurements, SP-B walked
  on both drivers, the crouch picture, gait_check) and 5b "How you could have made SP-E and SP-F yourself"; built by
  tools/dl/p93/LEGS/scripts/build_doc.py from tools/dl/p93/LEGS/doc/. The A/C/D pictures left docs/spider/img.
- **Checks.** gdUnit: pass93_LEGS_test 14 tests, pass92_SPIDER_test 4, pass66_shape_test 3: 0 failures); check_scripts 0; Level Editor selftest 13,736 / 0 (selftest_LEGS93.py 46). Optical flow of the new walks against spider_walk_v2: 23 (SP-E) and 24 (SP-F) of 40 leg-views follow, SP-B on its own walk 27: the painter copies a walk equally well; the walk itself is what changed. Captures tools/dl/p93/LEGS/shots/.
- Not done: the made-walk fold's summary text in jobs.js still lists "swing, lift, flex, duty, bob, sway" (PREVIEW lane's file); SP-B is not re-walked on the fixed walk in the game (only for the doc's comparison, cache desert_spider_spb_v2cmp_ctl_*); SP-E's first death frame is paler than the rest (Wan's first frames of the death clip).

Lane PREVIEW (pass 93): the Level Editor's **Drivers** tab and driver previews (Garry: "I only see names and can't
tell what the actual animation will look like ... where these are kept ... the frame index somewhere"). New
tools/level_editor/drivers_io.py (server.py hands it /api/drivers, /api/drivers/<name>, /api/painted_death/<enemy>/<code>,
POST /api/drivers[/<name>]/open; the old list_drivers body is gone, its keys kept): every folder of tools/dl/drivers with
frames, meta.json or not (gen_ctl's _soft copies listed with their parent), frame counts per view from the files
(`frames` = files, 25 for run; a depth meta's `frames` is poses per stride), first index, stills (clay, look,
clay_NN, a pose view's sheet), made-from sentence, plays loop|once (a made gait walks round although its meta says
loop false), size, files, date, used_by (every enemy / boss / hero look whose recipe names it). Page: drivers_model.js
(page-free maths), drivers.js (the tab: hover-play cards, search, filters, sort; the viewer: views, big frame index,
play/pause/step/first/last/scrub/speed/loop, keys, stills, numbered contact sheet, path with Copy and Open folder (Explorer
on library folders only), meta.json, users; inline thumbs + "preview" beside every driver field in the asset editor
and the job form, driver library cards and finished driver jobs; death_keep's picker: typed or picked off the death
driver's numbered frames or the look's painted death tools/dl/ai_anim/<key>_death/full_NN.png when it was walked along
that driver, "play the kept frames", even 8, the default, clear), drivers.css. methods.json: death_keep gains
`picker: "frames"`, `frames_of: "death_drivers"`, `view: "front"`. docs/level_editor.md "Pass 93". Tests:
selftest_PREVIEW93.py (57 checks; selftest_S re-pinned: run's `frames` 25, meta's 24); the whole selftest green
(13,687). Playwright screenshots in tools/dl/p93/PREVIEW/.

**Pass 95 (2026-10-21, v0.80): the shot from the muzzle, the Frisbee's trails, Fire forward, passive items up the rarity ladder to Evolved, the Dragon's Breath, despawning out of view, the timed Magnet, the King's trail and three stomps, the Scorpion's tail sniper, VACE frame repair in the Level Editor, and a read-only assessment of TOOLING_UPDATE_PROMPT.md.** Garry's list (tools/dl/p95/REQUEST.md) under the goal "complete all of the following while checking the quality of art assets and the game itself. Megabonk is a big inspiration"; the spider work (pass 94) parked on his word. Six lanes (tools/dl/p95/INTERFACES.md): ITEMS, PASSIVES, BREATH, WORLD, BOSS, VACE; the assessment docs/tooling/assessment_2026-10-21.md (published: https://claude.ai/artifact/H2KFqNpoq9r27k8b6PYR2H): 44 items, 39 accepted, 3 rejected, 2 questions (AN-07, AN-09). The lanes were cut twice by the spend limit and resumed from their status files. Lead fixes: the Boomstick's mutation "Dragon's Breath" renamed "Dragon Shells" (id unchanged) so the player sees one card of that name; Game.visible_modals skips a closing Spirit Pole (the smoke run's "two screens up at once: chest,totem").

**The shot from the gun** (Garry: "Shot should happen from the shotgun 3d object"). A held gun's rounds left the hero's
chest (Player.aim_origin: 0.8 m up, 0.5 m out) while the gun hung at his hip with its barrel reaching 0.85 m out, so every
Boomstick pellet, tracer and flash started a third of a metre behind the muzzle and above it, out of his painting.
ProjectileEmitter.shot_origin poses the held gun (at the hip, turned to the shot's line, so it snaps to the line its
rounds fly) and fires from the muzzle as drawn: the far end of the gun's barrels found from its visible meshes' vertices
(within 3 cm of the furthest down -Z, averaged: twin barrels and the Blunderbuss's bell give the bore), carried by the
gun's transform, so the hip's bob, the recoil squish and the turn are in it (held_tip, cached per look: Both Barrels
shows the twin barrels and hides the single one). Every path: the volley, the burst, the second barrel, Fan the Hammer's
taps, the hip shot, the blast's ghost pellets and the muzzle flash. The Boomstick, the Blunderbuss and the Doomstick
with every mutation; the companions untouched (pass 75's rest-place line kept); the hit test and the lead unchanged.

**The Frisbee's trail** (Garry: "needs a dim trail behind its flight because it's hard to see it right now. Treat each
visual update of Frisbee with its own trail effect"). `disc.trail` is a block {style, length, width, alpha, colour}, one
style per look: the plain disc's **streak** (a faint pale ribbon with a brighter thread), Poison Razors' **sparks** (two
thin bright edge lines and short sparks flicking off the rim), the Flying Saucer's **glow** (a wide soft glow with a
brighter core); Carry inherits the streak at its bigger disc (widths in disc radii). Longer (0.4 / 0.32 / 0.48 s against
0.22), more solid (alpha 0.6 / 0.9 / 0.45 against 0.32), and the ribbon fades out behind a gliding disc instead of
vanishing at the glide's start. Still one ImmediateMesh for every disc of a weapon (one draw call). The Level Editor's
disc group shows the five rows; an old `trail: true` reads as the look's own block.

**"Fire forward"** (Garry: "Change the following items to always fire at a sequence (add this as a togglable option in the
debug version of settings, by default it's off): Saber, Spear, Hammer, Frisbee, Tumbleweed - always in the direction
Player is facing; Basketball - always throw in front ... All of these will stop just shooting forward once there is an
enemy that's 75% of the weapon's attack range from the hero"). Settings.fire_forward (off, PROD_LOCKED, a Debug panel row,
a developer menu row, touch_audit); ONE helper, core/systems/FireForward.gd: the facing when the switch is on, the
weapon carries `params.fire_forward` (content: the six and their evolutions) and no living creature stands within
NEAR_FRAC 0.75 x the sheet's range; the behaviours ask it at every pull (ProjectileEmitter's usual aim, Thruster, Smasher,
Frisbee). The Sabre and Spear stroke along the facing on their clock, the Hammer lands 75% of its reach ahead, the Frisbee
arcs about its line, the Tumbleweed rolls straight; the Basketball thrown forward carries "drop_alone": at its range's end
with nothing struck it hops to a creature within its bounce reach, else drops to the sand and is gone (no return, no catch,
no Heat; ProjectileManager._drop_alone / _tick_dropping). The run record's settings carry the switch.

**Pass 95, lane PASSIVES: the passive items climb the rarity ladder.** Garry: "the number of Upgrades is reduced to
the number of upgrades they have left to reach Legendary + Evolved Rarity ... Evolved is a 'Rarity' for Passive Items
... I do expect that stats on the 1st level will be higher". The rule lives in one place (PassiveDef.ladder_levels,
applied to `max_level` in JsonContent.build): an item of rarity r has the rungs from r to legendary + Evolved as
upgrades, so common 6 levels, uncommon 5, rare 4, epic 3; level k stands on rung idx(r) + k - 1 and the top is Evolved,
a rarity for passive items alone (the dark plate in the brass ring every evolution wears, the item's Evolved icon, the
EVOLVED tag in ember and the card's ember band, "Evolved" in every generated line). W.plate_fill climbs for passive
items (level 0 stays the rarity's colour: the Collection), WPlate rings the Evolved rung and draws `evolved_icon`,
WItem names the rung on an upgrade card ("PASSIVE · RARE"), TextGen names it in the pause and next-level lines, the
Collection says "Passive · Rare → Evolved · 4 levels" and washes each level cell in its rung's colour. The 34 items'
JSONs now hold every rung explicitly (tools/passive_ladder.py: the table, the rewritten card lines, in-place with the
files' layout and line endings; the old numbers kept under tools/dl/p95/PASSIVES/old/): level 1 1.2-1.5x the old,
each rung about 0.8 of an old step, the Evolved rung the biggest, the top of an item that lost rungs 0.75-0.9 of the old
one, of one that kept its count about the same, of one that gained rungs a little above; capped stats stay under their
caps (the Magnet's 8.5 m). The Evolved icons: tools/evolved_icons.py cuts the subject by alpha, grows a white outline
(6 px of 256) and leaves the ground transparent (the plate is the black), with a review sheet of all 34 on the dark
plate. Phoenix Feather climbs too: rungs of health on revive, Evolved a second life (Run.phoenix_spent / phoenix_count;
`phoenix_used` still the "all spent" flag). The Level Editor's Items tab names the rung beside each level, warns when
the levels or max_level disagree with the ladder (an overlong list is an error), defaults a new item to 6 levels;
selftest_PASSIVES95.py. Tests pass95_PASSIVES_test.gd (the rule, every item's levels and icon, the plates, the cards'
words, every text at every rung, a run buys every rung and no further, a level past the top loads, the feather's
second life, the tool's --check) and the re-pins of pass23, 24, 46_passives, 47_rules, 48_items, 48_p0, 48_ui, 53_items,
62_it and 69_pas to the new numbers. Lessons: a rule that only one place computes (the ladder in PassiveDef) keeps the
JSON honest: the tool writes max_level too so every reader of the JSON agrees, and the editor flags the disagreement
instead of the game refusing it; a sparse JSON (repeat_last_level) was fine while every level was the same, but rungs
that differ must be explicit so Garry can tune each; the Godot lock has no fairness, so a lane's long test run waits
behind every other lane's short commands (start the long ones early, write the other pieces while they wait).

**BREATH: the Dragon's Breath (Cologne and Lighter).** Garry: a weapon that "breathes fire" where the hero faces for
a time, every creature in it burning and hit every second it stands there; rare, 2 s when it comes, the slowest in
the game, decent damage; amount = more seconds; very visible, cheap VFX; no 3D object, the fire from his face; three
mutations (a knockback every second with a fiercer look; a Methanol-like blue fire, further, weaker, longer; a doubled
attack from all sides after standing completely still 2 s, broken by a hit but never cutting a running attack); an
evolution amplifying it all with the Thorn's level-1 thorns. Built: a new behaviour primitive `FireBreath`
(core/behaviors/FireBreath.gd: a cone from `Player.face_origin` along `forward()`, bodies tested by their radius, a
tick on entry then every `breath.tick` anchored to the entry, `ignite` every tick, the cone turning and walking with
him; the wait rule: a creature in the cone, or anyone within reach after `breath.wait`; Backdraft's shove through
EnemyManager.damage's push at the map's hero share; Held Breath on `Player.still_unhit_seconds` (new: still_seconds
and a hit-ago clock, the hit noted in take_damage after the evade, so Steady Hand's still is untouched); blue through
WeaponInstance.blue_fire and EnemyManager.fire_blue; cheap VFX: Fx.breath_jet (pooled flame tongues down the cone,
about 40 alive, an ember now and then), Telegraphs.wash under it and a scorch after; the lighter's pop and a whoosh
loop (Audio.play_loop, `sfx.loop`, synthesised in numpy by tools/synth_breath_sfx.py). Content: weapons/dragons_breath
(rare, weight 6; 9 s, 2 s, 50°, 5 m, 32 a tick + a 6/2.5 s burn; at 5: 58 a tick, 7 s, 3 s, 6 m, 60°), mutations
blue_flame (element), held_breath (volume), backdraft (motion), evolutions/fire_eater (80 a tick, 6.5 s, 3.5 s, 7 m,
65°, burn 14/3.5 s, knock 7, thorns +8 on the hero: a weapon level effect aimed at "player", a new rule in
Run._apply_weapon_player_effects, named "weapon:<id>" in the Stats tab). The icons painted through gen_icon_cands set
95 (a cologne bottle and a lighter, the blue one, the ring, the gale, the torch and bottle crossed) and picked from one
review sheet. The estimate (WeaponInstance.breath_dps, BREATH_CATCH 3, HeroPower.element_uptime so the burn of a 9 s
weapon is not counted as always lit): the breath is the median weapon at level 1 (21 dps, beside the Boomstick and
the Revolver), 6th of 24 at level 5 by the estimate, the Fire Eater 8th of 24 evolutions; the difficulty probe's
pairs (the breath in the Peashooter's slot) in balancing_BREATH.md. TextGen.breath_words, the rows, the Level
Editor's FireBreath vocab and `breath` group (selftest_BREATH95.py, L69's SOURCES), pass95_BREATH_test.gd (13).
Lessons: the Boomstick's pass-51 mutation is already called "Dragon's Breath"; the ids never meet in code (the
Registry keys by type) but the player sees two cards of one name: the lead's call. A tick clock scheduled from the
frame a tick lands on drifts a frame a tick (the test with 1/60 s steps lost its fourth tick); anchor it to the due
time. A capture that counts the breaths after arming the cooldown misses a still hero's breath that fires the same
frame (the first evolution capture was empty); count before arming. A probe window past a stage's end (pass 87:
stage=0 at 860 s) ends at once and reports 0 s: give the probe the stage whose window holds t0.

**Pass 95, lane WORLD: regular creatures despawn out of view; the Magnet is a timed wide pull.** Garry: "in Vampire
Survivors certain enemies despawn if the player walks far enough from them. Let's do that as well ... only regular
enemies ... out of Player's view ... they leave nothing behind." The map's `timeline_data.despawn` {enabled true,
distance 40, grace 6, every 0.5, keep_share 0} (WaveTimeline.DESPAWN_DEFAULTS, JsonContent; the director hands it to
EnemyManager.set_despawn, off in the arena; the Level Editor's Scaling card has the five rows): every half second a
regular creature (never the boss, an Elite by kind or modifier, a special type, a coloured special, a boss's summon while
it lives, a dummy, one held, roped, in the air or rising) farther than 40 m from the hero, off the screen by the camera's
frustum test and older than 6 s vanishes (EnemyManager._tick_despawn at the top of the tick before the grid, can_despawn,
despawn → _free): no death, blood, XP, drops, chest, kill or corpse; the live counts drop as for a death so its row
spawns again near him, which is how VS and Megabonk keep the crowd round the hero. Counted in the run record (the
per-second `despawned` map, the crowd block's `despawned` / `despawned_by`) and in the run sim (`despawned_by`, a chart
under Rewards). And "Magnet - should not pull everything. Should just affect a big area and work for a time (like 10s)
... a 2d magnet icon floating around the Player ... around 2.5 times larger than the Magnet Epic Item": the Magnet Pulse
is the Magnet (content/pickups/magnet_pulse, effect "magnet", duration 10, params.radius_mult 2.5): for 10 s (the Pocket
Watch's and the hero's buff seconds; a second one adds its seconds) every gem and coin lying within 2.5 × the Magnet
card's level-1 reach (15 m with the card's 6 m) of the hero comes on the magnet arc, never a vacuum gem, a chest or a power-up
(PickupManager.magnet_start / _tick_magnet / magnet_pull); the HUD's plate counts it down through Run.timed; the 2D
magnet (core/systems/MagnetBuff.gd: the pickup's icon orbiting at 1.3 m, bobbing, dashed field lines to the nearest gems,
a spark now and then, blinking its last 1.5 s); a faint ring at the reach; the bot prices it as the vacuum. Tests
pass95_WORLD_test.gd (9), selftest_WORLD95.py; the probe game/tools/_p95_WORLD_probe.gd and the capture
_p95_WORLD_shot.gd.

Pass 95, lane BOSS (Garry: the King's tumbleweeds "should have a trail behind it. It's not visible right now"; the stomp
"should have an animation of the king jumping and doing the stomp. It should be more than one stomp, 3. There should be
visible wave effects around the boss"; "Scorpion Elite should have like a more powerful sniper attack, that comes out of
the scorpion's tail ... visually the same ... shoot 3 in a sequence 1 after the other"). The trail: pass 45's tan bead at
the ball's foot was tan on tan; every hostile `shot: "tumbleweed"` now wears a dust trail (ProjectileManager
`_tumble_trail_*`, TUMBLE_TRAIL: a dark-sand ribbon laid in the tracers' ring as the ball rolls, in the "line" style that
widens, lifts and greys like smoke, plus a real puff of dust off its foot every 0.11 s, Fx.roll_dust), the King's volley
row carrying its own `trail {style, colour, alpha, width, life, puffs}` through Game.tumbleweed_volley's new tenth
argument. The stomp: the King's `slam` row became the `stomp` script (EnemyManager `_stomp_*`): after the wind-up and its
ring the fire step parks the attack pose (STATE_ATTACK, the runner's timer at SNIPER_HELD) and runs the hops on lift_h (up
2.2 m over 0.35 s on an ease-out, down over 0.2 s on an ease-in: the painting rises, its shadow shrinks under it, it lands
squashed); each landing hurts the hero within 6 m for 18 (60% of the old slam's 30) with a special push of 6, shows the
wave (Game.stomp_wave: Telegraphs.race_ring to the radius, a flash ring, Fx.stomp_dust's ring of puffs, clods and grains,
a camera kick) and plays the boulder's thud; 0.45 s on the ground, the next hop; three landings 1.0 s apart, a ring before
every one; then the cooldown. The `slam` script is untouched. The tail sniper: the `tail_sniper` script (EnemyManager
`_tail_*`) on the Dune Scorpion's rotation (chance 0.7, skipped inside 5 m): the fire step freezes it the Saiga's way
(STATE_WINDUP, the timer parked) and runs three shots one after the other, each a fresh aim on the hero (SniperFx's lines
from the tail tip, muzzle_point with the row's `muzzle` up 2.0 / forward -0.4, 1.0 s), a 0.4 s lock, the Saiga's beam
(beam_hit: the hero on the line takes 2 x the Saiga's base = 30.8 before the Elite's factors, with a special push of 5,
"tail beam"; the crowd on it nicked 5% and pushed aside), 0.6 s frozen; a moving hero dodges the beam he stepped off and
is aimed at again by the next. Nothing but a stun, a freeze, a launch, a grab, hiding or death spoils it. The common attack
key `chance` (rolled as the turn comes, a miss skips to the next attack). The Level Editor: vocab.ATTACKS / ATTACK_COMMON,
assets_fields.js ATTACKS (nested blocks as `json` rows: a one-line branch in enemies.js attackField), BossAttackDef.SCRIPTS,
boss_attacks_io.BUILTINS, boss_model.js SCRIPTS (14 -> 16 built-ins); selftest_BOSS95.py. Tests pass95_BOSS_test.gd;
re-pins on purpose: pass45_bosses (the bosses' HP read from their files: Garry's doubled numbers; "slam" -> "stomp"),
pass73_sniper (the Saiga's HP read from its file: Garry's 125), pass89_knock (three `special_knock = true` writers).
Capture game/tools/_p95_BOSS_shot.gd. Lessons: a run that holds the runner's STATE_ATTACK must park `timer` far above
zero, or the fire step fires the same attack again next tick; aims drawn by SniperFx must be added after
`_tick_snipers` (its begin() clears the frame's aims), so the tails tick after it; the Registry serves the `.tres`, so a
content edit is invisible to the tests until import_json runs.

#### Pass 95, lane VACE: frame repair with VACE in the Level Editor, for every animation method and existing assets

Garry: "the 3rd approach using VACE for fixing broken frames seems to be the most sensible one ... add this VACE frames
fixing option to EVERY method that includes any kind of animation ... a way to view every single frame and choose which
ones to regenerate ... available to existing assets too ... options per frame (the history of other generated frames)
... frames from other Looks (SP-A-1, 2, 3) ... several frame changes in one go without needing to wait for the save
export thing to finish."

- **The install.** Probed the AI server over ssh (ComfyUI 0.33.0, the R9700's 34 GB, 216 GB free, HF at 40 MB/s,
  `WanVaceToVideo` a core node, no VACE weights). Installed **Wan 2.2 Fun VACE 14B** (Comfy-Org's fp8_scaled high +
  low noise, 17.3 GB each, 9 minutes of wget, no lock, no restart): the same generation, umt5, Wan 2.1 VAE and
  lightx2v 4-step t2v LoRAs as the Fun Control walks the creature clips come from. `tools/comfy.wan_fun_vace()`:
  the kept frames as the inactive video, the guides as the reactive one, masks per frame through `ImageToMask`, the
  painting as the reference latent (trimmed after), the two-stage split as the walks. ComfyUI loads it as
  `WAN21_Vace` (16.5 GB each, fully on the card); 25 frames at 640 px in 137-143 s.
- **The frames store** (`tools/frames_store.py`, `tools/dl/frames/<kind>/<id>/<CODE>/<anim>/<view>/slot_NN/vNNN.png+json`):
  one version per frame ever made, ids a hash of the PNG, labels `<CODE>-<n>`; `selected.json` (the choice per slot,
  pinned by a human), `staged.json` (choices not yet exported), `exports.json`. The retrofit cuts any installed strip
  by frame_px / strip_cols / the kind's order and, when the clip cache still has the clip, attaches the clip frame as
  the version's raw twin and measures the **fit** (cell = canvas x s + o: SP-B's side 0.5 px residual, the rendered
  twin at IoU 0.98 against the installed cell), so a repaired raw frame is placed, outlined and post-filtered exactly
  as the pipeline placed the clip's. The driver and the frame each slot was walked on are found from the recipe
  (creature_ctl's second stride, death_keep, Wan Animate's driver k+1). A landing (merge_look) syncs the store: new
  cells become versions selected unless the slot is pinned. Deterministic **flags** per frame (empty, footprint, jump,
  seam, silhouette against the driver) with the number and the rule; they miss ghost legs, said so.
- **The repair** (`tools/vace_repair.py`): the whole animation goes in as the clip (a short loop twice plus its first
  frame, 25 = 4k+1; a long one once; a one-shot padded), the chosen frames masked and replaced by the driver's frames
  **fitted onto the kept figure** (the painting walks at its own size: SP-B's side 1.11x the depth, 40 px over), or
  grey for a free fill (`--guide free`); the painting from the cache as the reference; the clip's own words as the
  prompt; the frames keyed like a clip and landed as versions `source: vace`, staged unless pinned. Proof on SP-B's
  side walk (slots 3-5 and 9, chosen by eye: khaki ghost hind legs, a green leg): 3 and 4 came back clean, 5 and 9
  worse on two seeds (a flatter body, a paler reshaped head): the versions drawer put the originals back for those
  two and the export took the two good ones. Pictures under tools/dl/p95/VACE/.
- **The Frames view** (`tools/level_editor/frames.js`, `frames_model.js`, `frames.css`; routes `frames_io.py`,
  `/api/frames/...`): **Frames…** on every look card (enemies, bosses, heroes; existing assets included) and on a
  landed look's or a repair's job card; tabs per animation x view with staged counts; the frame big with its slot
  number and badges, the previous and next beside it, the driver's frame under it; play / step / scrub / speed / loop
  / zoom; a numbered sheet (click, shift-click a range, ctrl-click); the versions drawer (stage, pin, unstage, large);
  Repair with VACE… (words, seed, window, guide: a `frames_repair` job on the comfy lane), Fill from neighbours… (the
  same with guide free), From another look… (every other look's same slot, compatibility warnings; a copy becomes a
  version here, never a link), Ask the local vision model (LM Studio, labelled as a hint), Undo (unstage), **Export**
  (one `frames_export` job: the strip packed with artkit from the staged and selected versions, the old strip under
  tools/level_editor/backups/<id>/, the entry merged line by line, fresh, then the import job). Staging is instant
  and lives in the store (a reload keeps it); only Export writes the strip.
- **Jobs**: `frames_repair` and `frames_export` in jobs.py (SPECS, `_frames_plan`, a step's own env so the comfy lock
  passes to the subprocess, the export's entry landing through `_post` like a look's, the outputs on the card).
- **Tests**: `selftest_VACE95.py` (78 checks: the store on a drawn creature with two looks, a synthetic clip cache,
  driver and painting: retrofit, fit, round trip, versions, staging, pinning, flags on an empty and a shifted frame,
  export and commit, a re-roll keeping a pin, a copy from the other look; the routes over HTTP with a jobs stand-in;
  vace_repair's window and dry run; frames_model.js under Node; the wiring; the two job kinds' plans).
- Not done: RIFE/FILM (no model on the server; the free VACE fill covers the case); the flags do not see ghost legs;
  procedural animations get the history / copy / export path, no Repair button logic beyond the same job (a free fill).
- **The resume (after the spend limit, 2026-10-21 evening; the read-only tooling assessment's AN-01..AN-14 and E2-E5
  read first).** The demo's export into SP-B, the look in play, was put back: the installed strip from the export's own
  backup (its hash equals the committed bytes), the repaired versions of slots 3, 4, 5 and 9 kept in the store unpinned
  and unstaged, the selections on the installed frames again, a rollback record in exports.json, the texture re-imported
  and the .tres regenerated under the Godot lock; `git status` shows the strip unmodified. Then the assessment's
  engineering items, no question asked: one writer of staged.json (the repair process returns its versions with
  `stage_wanted`; the Level Editor's landing stages them unless the slot is pinned or a hand choice came meanwhile);
  the shrink guard of artkit.place_clip_frames in the store's cell render (a figure larger than the cell is shrunk about
  its floor, never cropped, flagged `footprint`); `driver {name, ctl_sig}` and the clip's `wan` on every installed
  version, `store_version: 1` in every group.json; `frames_store.hook_after_save` after every strip.save in gen_art
  and gen_ctl (a look with a store is registered again from the saved strip with the run's own counts; a warning names
  the pinned frames the run replaced: "Export is the writer for this look"); a `repair` rule per method in
  methods.json (vace yes / conditional / no; fill cell / still / none) that the route, vace_repair.py and the page read:
  a procedural animation (no clip, no driver) is refused unless "fill freely anyway" is sent on purpose; no NEW mark on
  an export; a confirm box before exporting the look the game plays (Q5's default); an export job waits for a running
  repair of the same look; rollback when the entry cannot be merged or the import after it fails (the strip from the
  backup, the old entry merged back, the choices staged again, the card says "rolled back"); retention (never a
  referenced version deleted, 30 strip backups per asset, repair sheets 90 days, raws kept; a Delete in the versions
  drawer for the rest); the picker marks removed looks (their group.json serves their frames). The doc's per-method
  table gained the rule and the store-hook columns, the view a "Where frames live" line. selftest_VACE95.py grew from
  78 to 130 checks (the restore round-trip, one writer, the confirm, the rollback on a forced merge failure and a failed
  import, the refusals, retention, the wait). No GPU run in the resume. The honest state of the repair quality stays
  what the two demo runs showed: of four side-walk frames redone, the two at the start of a span came back clean and
  the span's end and a lone frame came back worse on two seeds; the single-window benchmark the assessment asks for
  has not been run.

**Pass 96 (2026-10-21/22, v0.81): the art-production loop, Phase 0 and Phase 1 of the tooling plan.** Garry: "proceed, make sure none of the old functionality is broken" on the revised assessment (docs/tooling/assessment_2026-10-21.md revision 2). Four lanes (tools/dl/p96/INTERFACES.md): GATES, REQ, LOOP, PAGE. What exists now: `tools/art_request.py start|status|result|...` creates a request (`tools/dl/jobs/requests/<rid>.json`) whose jobs run on the existing lanes; after every landing an `evaluate` job runs the tiers (0 deterministic flags and geometry = the hard gates; 1 the local vision model on flagged frames; 2 a cloud eye on one contact sheet only when the request pays) and writes `findings.json`; the planner (tools/level_editor/loop.py) proposes one op from the Auto-iterate allow-list (tools/level_editor/commands.py: requeue with prompt words and a new seed, reroll_view, repair with the VACE profile and the escalation single -> double -> reroll_view, ask, note, select_provisional, stop; never export/install/default/approve/pin/remove/delete/a pinned slot) until the gates pass or the budget ends, then waits for Garry's one approval (the batch box); the evaluator adapter tools/vision_eval.py (local OpenAI-chat, Anthropic Messages with a pinned model and a key only from tools/keys/anthropic.env, Gemini's official API with tools/keys/gemini.env; opaque image names; the ledger tools/dl/qa/ledger.json with per-request and daily ceilings, $0 = off); the frame layer as he decided (the label `SP-A / Run / Side / Frame 07 / v2`, a confirmation before any export that replaces an installed strip covering the whole batch, pins re-applied at every landing, no deletion of versions, the picker's filters); the request card on the Jobs tab; a pick survives polls; stills show on the render line; an honest connection line; cancel never clears ComfyUI's queue; the offline slice test. No game code changed.

2026-10-21 21:03 read RULES, INTERFACES, REQUEST, the brief, the assessment's E4 / F5 Phase 0 / AN-02 / AN-04 / AI-07 /
AI-08, report_VACE.md, design_VACE.md, vace_repair.py, frames_store.py (Look, Group, flags, _silhouette_iou), the 21
repair rules, part_AI.md. Its scratchpad scripts (bench.py, blind.py, manifest.json, the result files) still existed in
this session's scratchpad: the case list was rebuilt from the status files it cites and checked against them.

21:20 a probe of every look's run/front (tools/dl/p96/GATES_probe_looks.py): the pose2 candidate GOB-D (goblin_gobd_pose_f,
driver bigguy_goblin, in play), the free2 candidate BD-A (buckshot_dwarf_bda_walk_f, creature_free2, no driver, in
play), the recipe-less base RG-A (red_goblin: cells only, no clip, no still). The LM Studio server answers (22 models,
none loaded; the 7B and google/gemma-4-e4b present). No tools/keys/anthropic.env, no gemini.env.

21:25 the hue-histogram distance E4 names was measured on the demo's pairs (the real store's SP-B-2 / SP-B-3 versions
against the still): it put the good repairs (3, 4: 0.17-0.19) FARTHER from the still than the bad ones (0.06-0.15), so
it cannot be a check; a 6x6x6 RGB histogram distance of the figure's pixels separates them (good 0.34-0.37 at a kept
median 0.31, bad 0.41-0.57) and the mean saturation drops on the bad ones (0.69-0.75 vs 0.77-0.78). The RGB histogram
at 1.25 x the kept median became the `colour` check (tools/dl/p96/GATES/spb_pairs.png is the sheet behind it).

21:40 vace_repair.py: `profile_for` / `class_of` / `repair_rules` / `next_rung`, the partial `mask`, `store`, `profile`,
the upload volume; the CLI gained --mask, --store, --lora; --strength's default became "the profile's". A dry run with
--store registered SP-B in a separate root and left tools/dl/frames alone.

21:42 tools/vace_bench.py: the 27-run matrix, the bench store copy, the baselines, the checks, score, choose,
write-profiles (one-line in-place edits), checks_cli. Dry runs of one run per class + the mask built their inputs. The
check set calibrated on the demo's versions (calibrate_checks.log): the colour check catches the four bad versions,
good slot 3 passes every check, good slot 4 trips `jump` beside the bad new 5. The pose baseline flags `silhouette` on
all 12 installed GOB-D frames (a stick figure against a body): such a flag is left out of a group's checks and said so.

21:43 the GPU matrix started (`python tools/vace_bench.py run`, one subprocess a run so the comfy lock is released between
runs). 21:50 tools/qa_bench.py + the manifest (39 cases). 21:51 the LM Studio runs started (through LOOP's
vision_eval.openai_chat_json, which had landed). 21:57 the first four ctl runs: single window, strength 1.0: 0.917 and
1.0 (clean 3/4, 4/4); strength 0.7: 0.792 and 0.833 (clean 0/4): the weaker control strength is worse on this walk.
The PC GPU sat at 98% / 11.5 of 12 GB while the 7B ran (30-50 s an image against part D3's 1-2 s): the verdicts hold,
the seconds are to be re-timed. selftest_GATES96.py written (52 pass; the 8 that need the written profiles and tiers
wait for them).

22:05 the FLAG_RULES sweep (tools/dl/p96/GATES/flag_rules_tune.py, on its own copy of the SP-B group after a first attempt
collided with the running bench's staging in the bench store): no threshold lowers the misses without a new false alarm;
the demo's two good repairs carry the higher jump scores (2.67, 3.72) and 11 of 12 installed frames sit under IoU 0.6
against the depth driver. FLAG_RULES unchanged. The full LE selftest baseline at 22:10: 14,593 passed, 12 failed (8 mine
waiting for the profiles and tiers, one a crash on the absent key, fixed; LOOP96 x3 and the PLE dry-run check theirs).

22:18 the LM Studio runs done (the 7B x2 anchored, gemma x2 anchored, each unanchored once; LM Studio left with nothing
loaded): the 7B misses 9/19 anchored, 7/19 unanchored, flags 5/12 clean; gemma anchored misses 11-12/19 and flags 1-3,
unanchored misses 5 but flags 10/12. Neither sees a ghost leg. 22:21 the 7B unanchored run again (identical: the 7B is
deterministic at temperature 0; gemma agrees with itself on 92% of the flags). The tier rule gained FA_MAX 0.5 (a screen
that flags most clean frames is no screen). 22:22 the tier table written into request_defaults.json (REQ's file re-read;
its layout kept): tier 1 = the 7B unanchored, tier 2 = claude-haiku-5-5 on sheets at ceiling 0.0. 22:25 16 of the 27 VACE
runs done; the pose and free classes in; the cell, mask and 20-step runs remain.

23:04 the 27 VACE runs done (21:43-23:04; the 20-step runs 190-325 s each). `score`: the table in bench/summary.md; the
choice per class by the brief's rule; `write-profiles` changed the 21 repair lines of methods.json and nothing else;
the group test 70/70. A plain dry run of SP-B follows creature_ctl's written profile (double, 20 steps, cfg 3.5, no
LoRA, strength 0.7); the explicit demo settings reproduce pass 95's dry-run inputs key for key (oldpath/). The winner's
sheet and the mask run's sheet spot-checked by eye: the redone slots match the installed walk; the mask's rectangle
reads as a darker patch. design_VACE.md section 9, balancing_GATES.md's tables, report_GATES.md written; the full LE
selftest running at my end.

23:12 the full LE selftest at my end: 14,730 passed, 7 failed, all seven lane LOOP's ladder tests, which pin the plan's
fixed order single -> double -> reroll_view for creature_ctl while my choose() had written double -> single ->
reroll_view (the ctl winner's window first). INTERFACES fixes the order, so the fix is mine: a reliable class gets
the fixed ladder, an unreliable one ["reroll_view"]; the profile's window says where a hand run or an "auto" job
starts. 23:20 choose() changed, the group's expectations re-pinned, write-profiles again (the 21 repair lines), the
docs' ladder lines corrected; the full selftest again.

23:35 the full LE selftest: 14,737 passed, 0 failed. report_GATES.md written (through GATES/write_report.py). Done.

**Pass 96, lane REQ: the art request record and routes (1.1, 1.2), the cancel fix (1.6), the offline slice (1.8).**
`tools/level_editor/requests.py` is the record above the jobs of one art request (`tools/dl/jobs/requests/<rid>.json`:
goal, the immutable brief, the asset, the mode, Garry's budget and what was spent, the jobs, the iterations, the
provisional winner, the history, the result) and the frame of the Auto-iterate loop's step function: jobs.py calls
`requests.on_job_end(job)` for any job carrying `request` (after `_after_exit`, on a hand cancel, on a worker crash;
an import merged into another's counts as ended with it), the step loads the record, does nothing while paused /
stopped / cancelled or while a job of the request is still active, waits for approval when the budget is spent, and
otherwise asks LOOP's planner for one op, validates it (`commands.validate`), dispatches it (`commands.dispatch`),
records the iteration and counts the budget; mode `step` pauses after every op. Pause / Resume / Stop / Cancel / Step,
approve (one confirm for the whole batch: the fresh look approved and one `frames_export` with `confirm: true`; `done`
with the result once its import lands), reject (unstaged, AN-13's `review` on the versions, the loop goes on) and pick
(a code, or a version pinned and marked for the export's re-apply) are functions and routes (`requests_io.py`: `POST
/api/requests`, `GET /api/requests[/<rid>]` = the fold with one paragraph composed by code, `POST
/api/requests/<rid>/<verb>`, `GET /api/job/<id>/summary`). `tools/art_request.py` is Claude's one command (`start /
status / result / sheet / cancel / pause / resume / list / job`; stdlib; the port from the jobs lock's note; `result`
says "waiting for Garry's approval" with exit 2 until the export's import landed; no approve verb: that is Garry's, in
the page). jobs.py gained `enqueue(..., request=)` (or `spec.request`), `set_request`, `requests_module()` (ours even
when the PyPI library of the same name got into sys.modules first), the import after a request's job inheriting its
request, `comfy_prompt` from `comfy.run`'s new `comfy: prompt <id>` line, and `_comfy_interrupt(prompt_id)`: a cancel
now sends `POST /queue {delete: [its id]}` and `/interrupt` only while that id runs, never `clear` (WF-06c; a job
without a recorded id gets `/interrupt` alone). Tests: `selftest_REQ96.py` (156 checks) and `selftest_SLICE.py` (35:
the whole sentence offline on the real workers in about 10 s with a stand-in tool, the real `frames_store.export_look`,
a fake evaluator and planner, a fake ComfyUI that records what a cancel sent). A job without a request runs exactly as
before; `since=0` returns everything; the documented API changed only by additions. Lessons: jobs.py's import
coalescing marks a merged import done without `_after_exit`, so a request's hook has to fire for the merged ones when
the one that ran lands, and the record reads a merged job's state through the chain; a hand pin selects, so the store
has nothing "staged" and an approve must count the pinned frames the strip does not show (PAGE's `staged_batch`) or
the pick would never be packed.

**Pass 96, lane LOOP (1.3 the evaluator, 1.4 the loop body; 2026-10-21).** One adapter for every visual evaluator,
`tools/vision_eval.py`: three backends behind one call shape (`openai_chat` = LM Studio on the PC / Ollama on the server,
what gen_art.vision_json sent since pass 60; `anthropic` = the Messages API with a model pinned in request_defaults.json
and the key only from the git-ignored tools/keys/anthropic.env, never the environment; `gemini` = the official
generateContent API with tools/keys/gemini.env, built and untested because no key exists) plus a FakeBackend for the
tests; the opaque-name rule (every picture copied to img_<n>.png in a temporary folder, the backend given bytes only,
the question a fixed rubric from tools/qa_rubrics.json: the label leak of pass 95's experiment); a per-model answer
budget (a thinking model given 220 tokens returns nothing); an empty or unparsable answer = no verdict, never ok; the
ledger tools/dl/qa/ledger.json with the request's `cloud_dollars` and the global `cloud_ceiling_dollars_per_day`
ceilings (0 = the cloud tier off; a call that would pass one is refused and logged; an unpriced model refused); a cache
by sha1(picture) + rubric + model. The tiers on a stored look (`evaluate_look`, the `evaluate` job kind on the local
lane): 0 deterministic on every frame (the Frames view's flags, gen_art's geometry on the paintings: the only HARD
gates), 1 the local eye on the flagged frames plus one clean frame a group (advisory, badged with the model's name), 2
the cloud eye on one numbered contact sheet per decision point when the request pays for it and the tiers disagree or
a hard finding needs confirming. The findings record `<job>/findings.json` (items with kind measured / model / human,
the gates, the sheet), one line in the job's notes. The old callers unchanged and proven: gen_art.qa asks the same
question word for word with the same request body (byte for byte in the selftest), `--skip-qa` still skips, the Frames
view's Ask button asks frames_io.ASK; inside gen_art.render the geometry now runs BEFORE the model, so an empty or
edge-touching still never costs a vision call (`skipped_model` in the report; under --skip-qa the old shape exactly);
four asset_job dry runs (the Blue Slime through gen_art, the Desert Spider through gen_ctl, each with and without
--skip-qa) recorded before and after the change: every prompt identical (tools/dl/p96/LOOP/dry_diff.md). The loop
body: `commands.py` (one op shape {op, target, args, why}, unknown keys refused; the Auto-iterate allow-list requeue /
reroll_view / repair / stage / copy within the asset / ask / note / select_provisional / stop, Observe none, Step the
same one at a time; never export, install, default, approve, pin, remove, delete, a pinned slot, anything outside the
request's look; `validate` = schema, mode, target, pins, budget; `dispatch` through the page's own jobs_call /
frames_io functions; select_provisional stages and records, never pins, exports or touches `variant`) and `loop.py`
(the pure planner: ask when the findings are stale, select_provisional when the hard gates pass, repair the failing
slots as spans at the method's first rung with the ladder single -> double -> reroll_view read from methods.json's
`repair.profile` / `repair.escalation` (GATES) or built-in, the next rung when a repair did not lower the hard count on
its own slots, reroll_view after two ops without improvement or when every frame fails, requeue with words from a
defect -> words table and a new seed for a still-level failure or a procedural group, the plateau rule, budget units
checked before proposing). Lessons: a `creature_ctl` dry run had been dead since gen_ctl started passing `init=`
(asset_job's stand-in refused it); once alive it wrote stand-in frames over SP-B's installed strip and, through the pass
95 store hook, registered 91 stand-in cells as selected versions: undone from HEAD and verified slot by slot, then fixed
for good (gen_ctl's dry run writes into the job's copy through GEN_CTL_FOLDER like gen_art's has since pass 71, and the
dry-run stand-ins make frames_store.hook_after_save a recording no-op for both tools). 232 checks in
selftest_LOOP96.py.

Pass 96, lane PAGE (2026-10-21): Garry's changes to the frame layer (F5 step 1.5) and the request card with the page's
minimum (1.7). The frame label `SP-A / Run / Side / Frame 07 / v2` everywhere from one formatter (`frames_store.label_of`,
`FramesModel.frameLabel`; every served version and slot carries `name`, the short `label` stays for scripts); one
confirmation box before EVERY export that replaces an installed strip, listing the whole staged batch as before / after
pairs with the flag deltas and the pinned re-applies (`staged_batch`, `GET .../batch`, the route refuses without
`confirm: true`; `Frames.confirmBox` for the request card); pinned frames never overwritten: `on_look_landed` queues a
`frames_export` that packs the pinned versions back (no confirm, "re-applied N pinned frames" on the card),
`hook_after_save` re-packs in-process for a hand run (`reapply_pins`), pins that no longer fit (the count shrank,
frame_px changed) reported and moved to `lost_pins`, versions kept; Delete retired (`delete_version` and the route
refuse always); the picker's filters (look, animation, view, time, source, only raw; newest first; one group at a
time) and the marks old roll / archived. The Jobs tab: `Jobs.S.ui` (a pick, an open panel, the folds, the log place
survive polls), `sig` without the clock and a 1 s elapsed timer, the render-ok harvest in `_on_line`, the honest
connection line, and the Requests group with one card per art request (the fold, the budget bars, the last op, the
findings beside the outputs, the sheet, the jobs folded, Pause / Stop / Resume / Step / Approve / Reject / Pick
another). New `jobs_model.js` (page-free) and `requests.css`; `selftest_PAGE96.py` (74 checks); five VACE95 checks
re-pinned on purpose (Delete gone, the hook re-applies instead of warning, slot 1 keeps both versions).

**Pass 97 (2026-10-22, v0.82): the live page, Phase 2 of the tooling plan.** Garry: "proceed with Phase 2" (his pass 96 condition stands: nothing old may break). Three lanes (tools/dl/p97/INTERFACES.md): LIVE, PROGRESS, SAFE. Job cards patch in place (clips keep playing, panels and picks survive polls); `/api/jobs?delta=1` sends only what changed (5.4 MB -> ~13 KB a changed poll; without `delta` the old answer byte for byte); hash routes reopen a job, request or frame on reload; the look card has a live block and a history line; ComfyUI's node progress reaches the card (comfy.run's WebSocket thread under a Level Editor job; /history still ends a render); tools/dl/jobs/events.jsonl (seq, one writer) and the 30-day archive; /api/ops with measured medians and the ledger's dollars; a rotating server.log; failed jobs' errors as sentences; tools/doctor.py, tools/requirements.txt, tools/ai_hosts.json, the console-close handler (no dead jobs lock), Re-queue all, the request guard (a foreign Origin or Host 403, a non-JSON body 415), tools/net_check.py. Found and fixed: pass 96 shipped frames.js with a syntax error (the Frames view never loaded; a lead review fix; selftest_JSSYNTAX97.py now parses every page script); selftest_VACE95 had been overwriting the real tools/dl/jobs/queue.json on every full selftest run since pass 95 (jobs._save now refuses a queue file outside its jobs folder; the 470 job folders are intact and tools/dl/p97/PROGRESS/rebuild_queue.py rebuilt 468 records read-only into tools/dl/p97/PROGRESS/queue_recovered.json, not installed); creatures.js's icon fallback retried forever when both icons were missing.

Pass 97, lane LIVE (the live page: Phase 2 steps 2.1, 2.2, 2.5 and the page side of 2.3, 2.6, 2.7). **Stable cards
(UI-04 full)**: a job card is an `<article>` of named slots (head, sub, stage, bar, stages, log, outputs, choices,
actions, folds, reroll; `Jobs.SLOTS` per state, in today's order), each with its own signature
(`JobsModel.slotSigs`, no clock) and rebuilt alone when it moved (`patchCard` / `refreshSlot`); the log takes new lines
in place and re-pins only when it was at the bottom (`JobsView.patchLog`); outputs keep their clip players by URL
(`JobsView.Bank`: take / sweep), so a running creature_ctl card keeps its clips playing across polls and a card that
changes state hands its players to the new card; groups are kept (`groupEl`) and synced with `syncChildren`
(non-members removed first, then insertBefore only where out of place): `clear(S.groups)` is gone; `refreshRecord`
redraws the Looks section (and the pane header) alone when only look keys changed on disk (`redrawLooks` through a
one-shot `doc.__looksOnly` in `swapPane`; the aside-built sections' players destroyed), else the pane as before.
**Delta poll (UI-02 full)**: `jobs.list_delta` + `GET /api/jobs?since=&delta=1` -> `{rev, changed, removed, delta[,
order, full, unchanged]}`; per-record revs come from a hash of each record's served view (record + held + a running
job's tail) computed lazily once per queue rev (measured on a 468-record queue rebuilt from the job folders: 30 ms a scan;
a hash in `_save` would add that to every save, and `_touch` would need ~148 mutation sites across three lanes); one
running job changed = 12.7 KB instead of 5.4 MB; the non-delta answer is byte-identical to pass 96's (selftest compares
against an inline copy of the old `list()`); the page merges by id (`JobsModel.merge`), falls back to the whole list on a
501, drops crossing stale deltas, and tells `Jobs.subscribe` listeners `{changed, removed}`. **Routes**: `#<tab>`,
`#jobs/<id>`, `#jobs?look=CODE&id=`, `#requests/<rid>`, `#frames/<kind>/<id>/<code>/<anim>/<view>/<slot>` written with
replaceState and restored on load / hashchange (app.js; Frames.open wrapped once, a routed slot paused on); a card's
or request's id click puts its address in the bar. **Look card live block (UI-05)**: new `jobs_view.js` shared by the
Jobs card and the look stage; the selected look's stage shows its queued/running/waiting jobs (chip, stage k of N,
elapsed/ETA, lock wait or `lock_wait_s`, the ComfyUI substage, stages, 3 newest outputs, "open in Jobs") and its art
request (iteration, budget bars, provisional winner, Approve = the pass-96 batch box), redrawn from `Jobs.subscribe`
only when it changed, never the grid; a history line (past jobs with the `#jobs?look=` link, exports from the events
log or, on a click, from the frames store's exports.json, the newest events). **Page side of 2.3/2.6/2.7**:
`progress.substage` drawn as "side · KSampler step 3 of 4 · 41 s" (max 0 = the node alone; "(no tick for N s)"),
`progress.comfy_error` in red; an Ops fold (`GET /api/ops?days=7`: outcomes, rendered/cached medians beside
methods.json's, lock waits, failures as sentences, dollars per request) that the 2 s header redraw never closes; the
"offline since hh:mm" pill in the top bar on every tab; "N jobs were interrupted by the restart: Re-queue all"
(`/api/status.interrupted`, `POST /api/jobs/requeue_interrupted`). **Found and fixed**: frames.js did not parse at
51b037d (an unescaped apostrophe in pass 96's Repair-panel profile line): the browser dropped the file, so the Frames
view, the batch box and the request card's Approve were dead in the page; one character fixed, and selftest_LIVE97 now
`node --check`s every script index.html loads. Re-pinned on purpose (the outputs moved to jobs_view.js; the checks read
jobs.js + jobs_view.js): selftest_V (workflow links), selftest_PLE (Puppet.outputCell), selftest_PREVIEW93
(Drivers.open). Tests: selftest_LIVE97.py (93 checks). Lesson: string-grep wiring checks miss a file that does not
parse; check every page script with `node --check`. Latent, not fixed (not this lane's file): creatures.js's palette
retries a missing look icon forever when the creature's own icon is missing too (`onerror` sets the same failing URL).

Pass 97, lane PROGRESS (Phase 2 steps 2.3 server side, 2.4, 2.6 server side): **ComfyUI's live progress, the events
log, the archive, Ops.** `comfy.run` opens ComfyUI's WebSocket for its own client id on a daemon thread (`ProgressWatch`:
websocket-client, else websockets' sync client, else none) only under a Level Editor job, and prints `comfy: <prompt>
<node> k/n` (one line per 2 s, at once on a new node) and `comfy: <prompt> error ...`; /history stays the completion, a
socket that fails is tried twice more and then left alone. The message shapes come from ComfyUI's documented protocol;
a read-only capture on the idle AI server (the comfy lock taken, 00:37) recorded the `status` message on connect; the
fixture is tools/level_editor/testdata/comfy_ws/. `jobs.parse_line` turns the lines into `progress.substage` {node,
value, max, at, since, prompt, view} and `progress.comfy_error`. New `tools/level_editor/events.py`:
`tools/dl/jobs/events.jsonl` (one writer, the server; `seq`; a copy per job folder) fed at the choke points (enqueue,
take, finish, landing, merge, pick, requeue, cancel, edit, recover, the look ops, the icon set and guard, the content
Save, the frames verbs, the evaluator's verdict, every request history entry); `GET /api/events`. The archive: finished
jobs older than 30 days move to `archive/queue_<month>.json` at start and daily; `GET /api/job/<id>`, requeue and install
still find them; `GET /api/jobs/archived`; `/api/status.jobs.archived`. New `tools/level_editor/ops_io.py`:
`GET /api/ops?days=N` (outcomes, measured medians rendered vs cached, lock waits now kept per attempt, failures as
sentences, QA offline, interrupted, stalled, dollars per request from the ledger; 15 ms on 468 jobs) and the
`server.log` tee (5 MB x 3). The error-line rule strips ANSI codes and ends with "<exit code> after: <last line>" (the 6
Godot crashes that showed `\x1b[0m`); the ETA uses the measured median at >= 5 runs (`eta_source`). Found at the start:
`selftest_VACE95` had written its two-job fake over the real `tools/dl/jobs/queue.json` on every full selftest run (the
467 older records lost on 2026-10-22; their folders intact): `jobs._save()` now writes only JOBS_DIR's own queue file and
the test points both; `tools/dl/p97/PROGRESS/rebuild_queue.py` rebuilds the records read-only from the folders
(`queue_recovered.json`, 468 records). selftest_PROGRESS97.py: 120 checks.

Lane SAFE (pass 97, steps 2.7 server side and 2.8 of the tooling plan): **health and safety**. `tools/requirements.txt`
(an import scan of tools/: numpy, Pillow, scipy essential; websocket-client, soundfile, librosa, gradio_client, pefile
optional; Blender's own modules aside) and `tools/doctor.py` (read-only: Python, the packages, Node, Godot, Blender, the
JDK, git, ComfyUI / LM Studio / Ollama, the ssh key and a BatchMode login, the four locks with verdicts, disk, the key
files by name; exit 0 / 1 naming what is missing; `--json`, `--quick`, `--home`, `--root`; its quick summary in
`/api/status.doctor`, refreshed at most every 10 minutes off the request path, only in an editor main() started).
`tools/ai_hosts.json` + `tools/ai_hosts.py` (`get(name, default)`): comfy.py, jobs.py, server.py, gen_art.py and
vision_eval.py read the AI hosts from one file; with today's values (or no file) every constant is byte-identical,
COMFY_SERVER still wins. Closing the editor's console window now does what Ctrl+C does (`SetConsoleCtrlHandler` for
close / log off / shut down, Ctrl+Break as Ctrl+C, atexit): proved on a real server.main() in a hidden console with a
temp lock dir (the jobs lock released; with the handler taken out it was left behind, as before). "Re-queue all":
`POST /api/jobs/requeue_interrupted` and `/api/status.interrupted` (the jobs the last start interrupted; a Test in game
skipped; never automatic). The request guard in `do_POST` (`_request_guard`: a non-loopback Host or a foreign Origin
403, a JSON route's non-JSON body 415, the upload's raw body kept; the one GET that writes, the frames look summary,
checked too); every in-repo caller replayed against HEAD's server and today's (14 shapes identical; selftest_S's raw
`Host: x` requests now name 127.0.0.1). `tools/net_check.py` (read-only listing of non-loopback listeners; it found the
ssh forward `-L 192.168.0.43:8788:192.168.137.54:8788` and prints the one command to keep it on this PC; Garry's call).
`tools/keys/README.md` (tracked; the keys stay ignored). Found on the way: frames.js in HEAD does not parse (an
apostrophe in a single-quoted string at line 462), so the Frames view's script never loads; reported, not fixed (no owner).
Tests: selftest_SAFE97.py (115 checks).

**Pass 98 (2026-10-22, v0.83): Gemini as the art checker.** Garry has a Gemini subscription and no API billing; the Gemini API's free tier answered 429/503 and the Gemini CLI refused his tier, so the route is the Antigravity CLI (agy) in print mode under one narrow read rule in his ~/.gemini/antigravity-cli/settings.json (never --dangerously-skip-permissions). A blind benchmark on the 39-case set (tools/dl/qa_bench/agy_run.py): Gemini 3.8 Flash missed 0 of 19 broken frames but flagged 9 of 12 clean ones; leg counts right 2 of 11, ghost legs 22 of 25, faces 21 of 28; about 91 s a picture (the local qwen2.5-vl-7b: 7 misses, 5 false alarms). Garry: "just use Gemini first. Then if there are errors with Gemini we use the local as backups. And we make sure to surface that information somehow as an error." The benchmark spent his subscription's weekly quota (agy: "Individual quota reached ... Resets in 166h"), so the live proof ran the fallback for real and Gemini's own answer is proven only with a fake agy; the editor remembers the quota in tools/dl/qa/agy_state.json until 2026-10-29 13:00, and the lead lowered the daily cap to 6. Lead fixes: qa_bench.py `tiers --write` keeps a non-Anthropic tier 2; the Frames view's info block no longer prints "null"; REAL94's "the spider still plays SP-B" now accepts Garry's own pick (SP-G, set in the editor at 12:57).

Pass 98, lane GEMINI: Garry's Gemini subscription as the art checker. tools/vision_eval.py gained the `antigravity`
backend (agy.exe in print / plan mode on opaque pictures in tools/dl/qa/agy_inbox/<call id>/, removed after; a refused
read, a log-in error, a timeout or an empty answer = no verdict), numbered contact sheets of up to 16 frames
(agy_sheets, rubric sheet_agy), a daily call cap (tiers["2"].daily_calls, 6 a day) and the request's calls in ceiling_check,
ledger rows with seconds and agy's tokens, agy_health and ensure_agy_rule (the one inbox read rule appended to Garry's
~/.gemini/antigravity-cli/settings.json after a backup). Garry's order (2026-10-22): tier 0, then Gemini on the flagged
frames + a clean one a group, the local model only on the frames a Gemini call failed on, shown as an error everywhere
("Gemini failed: <why> - checked by the local model instead", "Local (fallback)" badges, an events entry, ledger rows,
the Ops count). request_defaults' tier 2 is antigravity (the paid eyes kept as alternates); new requests are stamped
eyes.tier2 and the planner asks [0, 1, 2] (one more before the provisional winner); both eyes flagging a frame orders
repairs first and earns one repair. The Level Editor: Ask Gemini in the Frames view (selected frames, one sheet, a job),
Check with Gemini on a look card and on finished look / repair job cards (every frame, sheets per animation x view),
per-frame badges per eye from the versions' qa.eyes (eyes_io.on_findings at the landing), G / L / G+L marks on the
sheet, the look's "Eyes:" line, Gemini named and coloured on the request card, today's calls and fallbacks in Ops.
New files: tools/level_editor/eyes_io.py, eyes.js, eyes.css, selftest_GEMINI98.py; GATES96 re-pinned on purpose (tier 2's
backend may be antigravity). Docs: docs/level_editor.md "Pass 98: Gemini as a checker".

**Pass 99 (2026-10-22, v0.84): the Desert Spider's SP-G and SP-H finished.** Garry: "continue with the spider then" (lifting pass 95's park). One lane, two rounds; the lead's round 2 targeted the faults with a known cause: the 3D model's dorsal fins (now dropped from the depth renders) and SP-G's pale three-quarter paintings (painted again). Lead's own pass 98 analysis the same day: the local vision model answers the expected leg count almost always (8 on 29 of 31 spiders), so its leg 'accuracy' was the anchor; Gemini never over-counted a clean spider.

Garry: "continue with the spider then" (pass 94's SP-G / SP-H work, parked in pass 95). SP-G (Klein) stays the played
look; every look stays fresh; SP-I (Garry's request r20261022-000038-84ed) untouched.

- **The frame-by-frame check** of SP-G's installed strip (numbered sheets of the 160 px cells and of the 640 px clip
  frames, tools/dl/p99/SPIDER/check/): every walk view had whole-view faults (rainbow fringes where Wan paints the pale
  thin legs half see-through over the green, the three-quarter front's legs stacked into tubes, the side's eyeless snout,
  the front's lost face, the three-quarter back's grey fan) and the death fell apart: pass 94's spider_death_v3 itself
  swings the folded legs out as two wings, so every death walked on it showed two loose clumps.
- **Fixes, cheapest first**: one view re-walked on another seed (walk_seeds {view: 1}, ~4 min): the front got its eyes
  and fangs back (kept); fd, bd, side were not better (not kept); softened depth (ctl_soft 10) on fd: worse. VACE repair
  with creature_ctl's benchmarked profile (double window 25, strength 0.7, 20 steps, cfg 3.5, no LoRA), once on SP-G fd
  4-5 and once on SP-H front 5 (~340 s each): both washed out and see-through: kept as versions SP-G-2 / SP-H-2 in the
  frames store, never staged or exported. **A new death driver** tools/dl/drivers/spider_death_v4 (blender_depth_drivers
  mode=flip_curl curl=100 curl_root=20 roll=170 twitch=4, smooth 2, skin capsule 0.06, views front,fd,side; Blender on
  the PC): the legs stay folded against the body; both deaths walked on it, death_keep [0, 3, 4, 10, 11, 13, 17, 24]
  (the roll's smeared frames skipped, a re-pick without a render).
- **SP-H** packed for the first time (the picks by eye: front c5, fd c2, side k2, bd the plain painting seed 24187,
  back c1), on spider_walk_v4 / spider_death_v4 with the full Wan, so G and H differ only in the painter (pinned by the
  new test test_g_and_h_differ_only_in_the_painter). Its strip and icon: desert_spider_sprite_h.png / icon_h.png.
- Verdict: in game SP-H reads better (a solid magenta silhouette, clean legs; faults: magenta not lavender, eyeless 3/4
  front and side heads); SP-G is the asked-for light purple with the better front face but pale, fringed legs and a
  tangled three-quarter front. Both keep the model's back fin as a spike in the front view (it is in the model's depth).
- Doc: docs/spider/spider_explainer.html section ★ finished (6b the frame check and the fixes, the side-by-side, the
  Level Editor steps with spider_death_v4, the timings), built from tools/dl/p99/SPIDER/doc/ by
  tools/dl/p99/SPIDER/scripts/build_doc.py (images 8.66 MB). Not published (the lead does).
- Timings: a walk 235-300 s, a death 236-244 s, five walks + death ~25 min a look; SP-G ~2 h 20 min of the server in
  all (pass 94 + 99), SP-H ~4 h 20 min.
- Tests: pass94_REAL_test.gd (SP-H must have its strip now; the new parity test) 4/4, pass93_LEGS 4/4, pass92_SPIDER
  3/3, check_scripts ok, Level Editor selftest 15,222 passed / 0 failed, tools/dl/jobs/queue.json untouched (sha1
  637fba2f... before and after). In-game capture game/tools/_p99_SPIDER_shots.gd (scratch, watchdog + frame cap).

Round 2 (lead's follow-up the same evening):
- **The spike**: the model's three dorsal fins and its head nub are loose 3-4 vertex pieces of the mesh on the body and
  head bones; new blender_depth_drivers `drop_islands=N` (+ `drop_groups`, default body|head|neck|root) deletes such
  islands before the renders (the file untouched; meta.json records it). spider_walk_v5 / spider_death_v5 = v4 + 
  drop_islands=4 (16 s each on the PC; gait_check ok). Both looks re-walked on them with the same seeds; kept where at
  least as good: all but SP-G's back (faceted far legs on v5), which stays on v4 via the new `view_drivers`.
  `clay_drivers` keeps each painting's v4 crop so the paintings lie where they did.
- **SP-G's three-quarter views painted again** (Klein 28, 4 seeds each from v5's clay, new `view_words` for fd/bd:
  strong value contrast, opaque legs): fd c2 and bd c0 picked by eye and walked on v5: clearly better than the pale ones.
- LE: driver form drop_islands / drop_groups (jobs.py fields + argv, methods.json), creature_ctl recipe fields view_words,
  clay_drivers, view_drivers (methods.json, assets_fields.js, vocab.py); selftest_SPIDER99.py (22 checks).
- Doc section 6c; round 2 took 1 h 20 min of the server.

**Pass 100 (2026-10-23, v0.85): build quests, the one-shot Phoenix, the stage look at the landing, the phone's performance assessed.** Garry (tools/dl/p100/REQUEST.md): more unlock requirements about levels with a hero, upgrading and evolving items; the Phoenix a once-a-run 50% revive without upgrades; Stage 2's intro not dark; "there are still performance issues on the mobile phone when there are too many enemies around". Three lanes: QUESTS, SMALL, PERF (assessment only: no game change).

Pass 100, lane QUESTS (Garry: "I'd like to see more requirements that have to do with getting Player to reach a specific
level with a hero, upgrading items passive/card/weapon to a certain level. Evolving an item, etc."): five build quests,
all done in one run and read off the run's build (`QuestTracker.run_progress` / `held_items`, no new Run state):
`hero_level {hero, level}`, `item_level {kind, id?, level | rung}` (a passive item's `level` is its number; `rung` names
the rarity rung, passive items only), `evolve_item {id | kind}` (a weapon at a chest, a card into its Risen card, a passive
item onto Evolved), `weapon_paths {weapon?}` and `items_maxed {kind, count}`; an evolved form counts its source at its top
level, a one-shot item is never "maxed"; their progress shows only while a run is on (the run record's quests carry it),
stage hints as BALANCING says. Worded by `TextGen.quest_build_text` ("Reach level 12 with Drifter.", "Evolve Temperance
into Temperance Risen.", "Take all 3 mutations of the Revolver in one run."), mirrored by the Level Editor (the Condition
list, fields per type: hero, item kind, item, rung; the id rows pick by kind; questText) and the bible (make_bible
quest_text / quest_stage). Seven kill quests and May's became build quests (Sabre: the Orbit Saws to 5; The Tower: a card
to 4; Overkill: a passive item to Legendary; Land Mine: evolve the Salt; Death: Temperance Risen; Ricochet: the Revolver's
three mutations; Fadeaway: level 12 with the Drifter; May: level 30 with Calavera); the other quests are as they were.
Completion is kept by quest id, so a save keeps what it unlocked. Tests: pass100_QUESTS_test.gd (14), pass83_meta
re-pinned (Fadeaway's words read off his quest), selftest_QUESTS100.py, selftest_L69 re-pinned (May's words).

Lane SMALL (pass 100). **Phoenix Feather is a one-shot item again** (Garry: "should still be a revive item with 50% HP on
revive. It can only be used once and doesn't feature any upgrades"): a reusable PassiveDef key `single` (one level, off
pass 95's rarity ladder: `on_ladder()` = is_item and not single, read by ladder_top / rung_at / is_evolved_rung /
apply_ladder (max_level 1) / effects_at_level (nothing past level 1), TextGen's rung words, W.rung_of, WItem.rung_word and
the Collection, whose kind line says "Passive · Uncommon · no upgrades"); its JSON is one level of `phoenix_revive` +1,
`single: true`, the card line "Two seconds after you fall, you get back up at half health (more with Second Wind) with
the revive's blast. Once a run; it never levels up."; Second Wind's revive health still applies (one rule for every
revive); the pause screen's "(used)" mark was already there; tools/passive_ladder.py and tools/evolved_icons.py leave a
single item alone (its old phoenix_feather_icon_evolved.png stays on disk, unused); the Level Editor's Items form has a
"One-shot (no upgrades)" switch with its warnings (assets_fields.js, assets.js, vocab.py, server.py owns the key);
selftest_SMALL100.py; pass95_PASSIVES (33 items on the ladder), pass48_items and selftest_PASSIVES95 re-pinned.
**Stage 2's intro in the dark** (Garry: "the into cutscene is not in dark"): the stage look (StageLook) came only on
WaveDirector.stage_started after the spawn beam's landing; Game._show_stage_look_now now shows the run's stage at once
before the beam (not in the arena), StageLook.show_stage leaves the stage it already shows when called without
`seconds` (no second switch; the arena's choice and the tools pass seconds and are unchanged), and the beam draws over
the filter (Game.SPAWN_BEAM_PRIORITY -6, was -10 under it) so it reads as light in Nightfall and Blood Moon. Checked by
eye on windowed captures of the landing on stages 1-3 (game/tools/_p100_SMALL_intro_shot.gd, tools/dl/p100/SMALL/shots2/sheet.png);
game/tests/pass100_SMALL_test.gd (7 tests).

Lane PERF (assessment only, no game change): the phone (Pixel 8 Pro, 19 of Garry's PostHog runs v0.64-v0.83) averages
65-115 fps (median 88.5) with 1% lows of 20-61 (median 31); fitted over time in each crowd size, ~96 fps under 200 alive
and ~70 at 250+, the lows from uneven pacing (a frame with a 60 Hz physics tick costs far more than one between). On the
PC perf_late's build six costs 14-16 ms a frame at ~290 creatures (enemies.sim 4.3 ms; pass 33.8 measured 5.4 ms in all
at ~150): the crowd is CPU-bound GDScript, steering half the crowd a tick with 44-50 neighbours per 2.5 m separation
cell, and drawing all of it although only 6-26% is on screen; shadows and outlines cost little; 120 Hz costs ~25% more
CPU than 60 Hz and shows nothing new (nothing interpolated). Art: strips import as lossy WebP without mipmaps, held
uncompressed in VRAM; the played strips are 88/123/128 MB a stage, but boot loads every look of every hero and creature
(856 pictures, ~2.3 GB). Ranked recommendations (a 60 fps cap on phones; per-second frame times in the run record;
render only on-screen creatures; smaller separation cells; slower off-screen steering; load only played looks; a 30 Hz
crowd with interpolation; C++ hot loops; threaded rendering; fewer damage numbers) are in tools/dl/p100/status_PERF.md
and the lead's report; probes game/tools/_p100_PERF_crowd.gd and _p100_PERF_vram.gd, results tools/dl/p100/PERF/.

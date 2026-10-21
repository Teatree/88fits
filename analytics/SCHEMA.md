# Run record schema (pass 45, the Game Analytics Watch; schema 2 since pass 74)

One JSON file per run, written by `game/core/systems/RunAnalytics.gd` (a Game child created for every real run; the
arena never records, and a launch file saying `"analytics": false` skips it). It is written when the run ends; a
checkpoint (`result: "in_progress"`) is written when the app goes to the background mid-run, and a run the game left
without an end is written as `result: "quit"`. Godot writes the JSON with its keys sorted.

**Schema 2** (pass 74, v0.60) adds the keys marked *(2)* below; a schema 1 file simply lacks them, and
`analytics/dashboard.html` opens both (a card that needs a schema 2 key hides itself).

## Where the files go

- Always `user://analytics/runs/<stamp>.json`: on the PC that is `%APPDATA%\Godot\app_userdata\88fits\analytics\runs\`
  (the editor binary and the PC build `88fits.exe` alike), on a phone the app's own folder.
- On the PC, when the game runs from the repo (the editor binary), also a copy beside the dashboard:
  - a **played** run: `analytics/runs/<stamp>.json`, `analytics/runs/latest.js` (`window.RUN = {...};`) and the index
    `analytics/runs/index.json` / `index.js` (`window.RUNS = [...]`, the last 500 runs);
  - *(2)* a **tool's** run (headless, or started with `--script` / `-s`: smoke_run, perf_late, hell_check, captures, the
    gdUnit runner): the same files under `analytics/runs/tools/`, so the dashboard opens on the last run Garry played.
- *(2)* How many are kept: a **phone** keeps its newest 50 run files (`RunAnalytics.KEEP_FILES`, pruned at a run's
  end; `prunes_here()`); **the PC never prunes** (a PC-build run lives only in its user folder). The repo's
  `analytics/runs/` is never pruned (git ignores it).
- `latest.js` is rewritten on every write (a checkpoint too); the index only when the run is over.
- The dashboard opens from `file://` and reads the `.js` files with script tags; a file input or a drop opens any run
  file. Its *Tool runs* switch loads `runs/tools/`.

`schema` is 2 (1 before pass 74). Numbers are snapped to 0.1 (stats to 0.001, multipliers and the boss bar to 0.01).

## Header

| key | meaning |
|---|---|
| `schema` | 2 (1 before pass 74) |
| `version` | `application/config/version` |
| `hero`, `hero_name` | the character id and name |
| `hero_look` *(2)* | the art look he was played in (`Registry.played_look`, e.g. `SOL-B`; "" for his own) |
| `map` | the map id |
| `map_rev` | (pass 57) a short hash of the map's `timeline_data` as loaded: the Level Editor version the run played |
| `seed` | `Run.map_seed` (the layout roll; combat randomness is not seeded per run) |
| `started` | local time the run started, `2026-10-01T18:05:11` |
| `stamp` | `started` with `:` as `-`: the file name |
| `run_id` | (pass 57) the run's id, the same on every PostHog event of the run |
| `headless`, `platform`, `device`, `pid` | `DisplayServer` headless, `OS.get_name()`, `OS.get_model_name()`, the process id (tools find their own file by it) |
| `tool` *(2)* | a tool's process (headless or `--script`): its copy goes to `analytics/runs/tools/` |
| `launch` *(2)* | the debug launch file the run started from (a tool's, or the editor's content dock test launch): its plain values, e.g. `{character, weapon, level, map, map_seed, spawn}`; absent for a run from the title |
| `result` | `in_progress` (a checkpoint), `extract`, `death` (Down!'s give up or its timeout), `abandon` (give up from the pause menu), `end`, `quit`; (pass 78) `killed` only in a copy PostHog got at the next launch: the app was closed after the run's checkpoint and before its end (the local file still says `in_progress`) |
| `length` | play seconds (unpaused; the x axis of every chart) |
| `clock` | `Run.elapsed`, the run clock (the map's), which freezes during a boss fight and at a portal; since pass 87 a stage run's clock starts at its window's start (stage 2 of Red Canyon at 430) and stands still at its end through the boss, the portal's countdown and Endless |
| `stage`, `endless_wave`, `level`, `kills`, `gold`, `strongbox`, `revives` | the end state (`gold` = the purse at the end, `strongbox` = gold a Strongbox banked, `revives` = revives bought) |
| `stage_index`, `stage_id`, `stage_name`, `stage_start`, `stage_length`, `stage_count` | (pass 87) the stage this run played (since pass 87 every run is one stage, picked in the Stages menu, the Watch or the Sim): `stage_index` 0-based (`stage` stays 1-based), `stage_id` the map's id for it (`s1`, `s2`...; the same in PostHog), `stage_name`, its window on the map's clock (`stage_start`, `stage_length` seconds to its boss), how many stages the map has |
| `outcome`, `boss_killed`, `stage_clock`, `endless_s`, `run_time` | (pass 87) how the stage run ended: `outcome` = `extracted` (through the portal), `died_endless` (fell in Endless), `died_after_boss` (fell between the boss and Endless), `died` (fell before the boss), `quit` (left from the pause menu or the app); `boss_killed` (the stage's boss fell: the next stage unlocked), `stage_clock` (seconds into the stage: its length once the boss came), `endless_s` (seconds survived in Endless), `run_time` (every second played: the stage, its boss, the portal's countdown and Endless) |
| `gold_before` | (pass 61) the saved gold (`Save.gold()`) as the run began |
| `gold_end` *(2)* | the run's gold as PostHog's `run_end` has it: `gold_earned`, `gold_spent`, `gold_greed`, `gold_debug`, `gold_strongbox`, `gold_purse`, `gold_banked`, `gold_lost`, `gold_before`, `gold_after` (see *Gold*) |
| `talents` *(2)* | the Upgrade board as the run began: `{talent id: [the form of each rank, in order]}` (0 its first form, 1 its second; only talents with a rank) |
| `talent_forms` *(2)* | `{talent id: [first form's name, second form's name]}` for those talents |
| `settings` *(2)* | `{pierce_falloff, debug_mode, dev}`: pierce drop-off, the player's debug mode, and whether the run counts as a developer's (`Analytics.is_dev`) |
| `map_settings` *(2)* | the map's numbers as the run played them, the game's defaults filled in where the map leaves a key out: `hero_knockback_mult`, `special_defaults` (size, hp, damage, xp, tint_strength, glow, chest_chance, `max_alive`: -1 = no limit), `boss_hp_scaling` (enabled, exponent, window, min, max, `ref_dps` {boss: DPS}), `target_priority` (enabled, reach), `spawn_rise` (seconds, big_seconds, targetable, dust), `creature_hp_mult`, `creature_damage_mult`, `creature_speed_mult`, `move_pace`, `xp_need_mult`, `water_slow` and `oases` (min, max, extra_chance, gap; pass 80), `xp_curve` (the growth type played and its numbers, defaults filled in; pass 82), and since pass 83 `boss_hp_scaling.mode` ("seconds" or "dps") and `boss_hp_scaling.seconds` {boss: seconds of full DPS}, `power_hp_scaling` (1 = off) and `power_hp_max`; since pass 89 `hero_special_knock` (the share of a special attack's push that reaches the hero) |
| `stat_names` *(2)* | `{stat: the pause screen's words}` (TextGen) for every stat a snapshot carries |
| `trait` *(2)* | the hero's trait as the run ended: `name`, `text` (its line), `level`, `stats` {stat: value at that level}, `words` (those numbers in words) |
| `totems` *(2)* | the Totem Poles' gifts taken: `[{id, name, stat, op, value, quality (1-3), words}]` |
| `build` | `{weapons: [{id, level, mutations: [ids]}], passives: {id: level}, perks: [ids]}`; *(2)* `lines: {id: level}`, the line items (the fortune cards, `PassiveDef.is_line`) apart from `passives`. A record from before pass 46 also has `lines` (the old lines) |
| `build_text` *(2)* | the build in one line, in the order it was taken (`Revolver 5 +3 · Peashooter 2 \| Clover 2 · Brawn 1 \| Afterglow`) |
| `totals` | `Run`'s `damage_by_weapon`, `kills_by_weapon`, `kills_by_enemy` |
| `timeline` *(2)* | the Results screen's story (`Run.timeline`) without its second-by-second samples: `markers` `[[t, kind]]` (kind `special`, `elite`, `boss`: a kill; `down`: the hero fell), `stages` `[[t, stage index]]`, `sources` `{damage id: {owned, hit}}` (the play second it was first owned / first hit; -1 never), `start_weapon` |
| `quests` *(2)* | every counted quest not done as the run began: `{id: {name, before, after, need, done}}` (its progress as the run began and as it ended, what it needs, done now) |
| `crowd` *(2)* | the crowd's counters at the end, those above zero: `special_chests`, `hot_chests` (Hot Sauce), `sniper_aims`, `sniper_shots`, `sniper_hero_hits`, `sniper_cancels` (the Saiga Sniper); since pass 95 `despawned` (regular creatures that vanished far from the hero and out of view, never a kill) and `despawned_by` `{creature id: count}` |
| `fps` *(2)* | `{avg, low}`: the mean frame rate and the 1 % low (a window only; the frame clock PostHog's run_summary has) |
| `names` | `{id: display name}` for every id the file mentions (weapons, passives, perks, mutations, creatures, pickups, structures; *(2)* Elite modifiers, talents, the totem gifts, the cards an offer showed) |
| `hit_log` | the hero's last 30 s of hits as the Down! screen shows them: `{t (the stage clock), by, id (the creature), kind (melee/ranged/boss/heal), role, colour, fx, raw, dealt, shield, note (evaded, shield, broke, star, ...), hp, fatal}`; a named heal has `kind: heal` and `amount`; only on a finished run |
| `samples` | the rows below |
| `events` | the events below |
| `remote` | (pass 78) only in a run downloaded from PostHog by `tools/posthog_runs.py` (`analytics/remote/<player>/`): `player` (the person's `player_name`, or `id <install id>`), `label` (Garry's own label in PostHog), `distinct_id` (the install id), `run_id`, `received` (the run_record's timestamp, UTC), `parts`, `uuids` (the events'), `dev`, `app_version`, `device`, `os`, `format`; `recovered` (sent at the next launch), `rows_left_out` (a record past the parts' cap) |

## Sample row (one a second of play)

Sparse: a key that is missing means 0 or empty. `stats`, `weapons`, `passives`, `lines`, `perks` and `mults` appear only
on a row where they changed (the sheet at most every 5 s unless an item was picked) and carry forward.

Pass 46 folded the lines into the passives: a record written between pass 46 and pass 74 has no `lines` anywhere, its
lines are `passives` and their events `passive` / `passive_evolution`. A record written before pass 46 keeps `lines`,
`line` and `line_evolution`. *(2)* Schema 2 keeps today's lines apart again (`lines`, and `line: true` on their events).

| key | meaning |
|---|---|
| `t` | play seconds |
| `clock` | the stage clock |
| `stage` | 1-based (since pass 87 the same on every row: a run plays one stage) |
| `phase` | the director's phase: 0 normal, 1 boss, 2 portal (pass 87: the portal's countdown), 3 Endless (pass 87) |
| `wave` | the endless wave, 1-based (missing before endless) |
| `en` | (pass 87) seconds into Endless (missing before it) |
| `level`, `xp`, `xp_next` | the hero's level, XP into it, XP the level needs |
| `xp_total` | (pass 77) every XP point gained so far (`Run.xp_gained`, after Field Notes), cumulative |
| `hp`, `hp_max`, `shield`, `invuln` | health, max, Energy Shield points, 1 while invulnerable |
| `gold`, `banked` | the purse and what a Strongbox banked |
| `gold_in`, `gold_out` | (pass 61) `{source: gold that came in this second}` and `{sink: gold spent this second}` (see *Gold*); gold that came while the game was paused lands on the next row, and what no row took by the end goes into the last one, so the rows sum to the run's totals |
| `kills` | the run total |
| `adren`, `cresc` | adrenaline and crescendo stacks |
| `steady` | (pass 47) Steady Hand's attack-damage bonus right now (0 to 1.0 = +100%), from `Run.steady_might()` |
| `desp` | Desperado's attack damage bonus right now (0.36 = +36%; pass 46) |
| `est` | `{weapon id: estimated DPS}` from each weapon's sheet (`WeaponInstance.dps_estimate`, the pause screen's "dps") |
| `est_total` | their sum: the build's promise |
| `power` | (pass 83) the hero's power level (`HeroPower`): sqrt((full DPS / 20.4) x (effective HP / 100)); a fresh level-1 Drifter with the Revolver on a clean save is 1.0 |
| `full_dps` | (pass 83) the full DPS the power reads: every weapon's damage a second on ONE target every shot hits (the estimate with its crowd guess taken out, its burn or poison kept up, times the average crit) |
| `ehp` | (pass 83) the effective HP the power reads: (max HP + shield + 30 s of regen and lifesteal) / ((1 - damage reduction) x (1 - evade)) |
| `power_hp` | (pass 83) the creatures' HP factor the power gives on this map (`power_hp_scaling`, `WaveTimeline.power_hp_factor`); missing = 1 (off) |
| `dmg` | `{weapon id: damage dealt this second}` (after crits and reduction, so it sums to `totals.damage_by_weapon`; also `blast`, `revive`, `grand_finale`, `powder_keg`, `loose_rocket`) |
| `took` | `{creature id: HP the hero lost this second}` (a hit with no creature id is keyed by its name, e.g. `the ring of fire`) |
| `took_raw` | the damage thrown at the hero before reduction, shields and evasion |
| `took_kind` | `{melee, ranged, boss: HP lost}` |
| `hits`, `evaded`, `shielded`, `healed` | hits that reached the hero (shielded and evaded ones included), evaded count, shield points spent, HP healed (every `Player.heal`; regen is not in it) |
| `hits_by` *(2)* | `{creature id: hits it landed this second}` (keyed like `took`; sums to `hits`) |
| `healed_by` *(2)* | `{source: HP healed this second}`: the name `Player.heal` was given (a pickup's or a structure's: Heart, Cake Slice, Healing Well; Vulture), `lifesteal`, `level_up` (the hero's level patch) and `other` (a heal nothing named); sums to `healed` (each value snapped to 0.1) |
| `regen` *(2)* | HP regenerated this second (regen, Siesta, Deep Breath; not in `healed`) |
| `hp_lost`, `hp_healed` | (pass 77) the second's HP lost (`took` summed, before any healing) and HP healed (`healed` + `regen`) |
| `killed` | `{creature id: kills this second}` |
| `elite_kills` | Elites (and elite-modified creatures) killed this second |
| `spawned` | `{creature id: spawned this second}` |
| `despawned` | (pass 95) `{creature id: despawned this second}`: regular creatures that vanished because the hero left them more than the map's despawn distance behind, off the screen (`timeline_data.despawn`); no kill, no drop |
| `alive`, `cap`, `load`, `hard_cap` | creatures up, the director's live cap, the crowd in cap-share units, the timeline's hard cap |
| `specials_alive` *(2)* | coloured variance specials up now (`EnemyManager.specials_alive`) |
| `press` | Σ over live creatures of max HP × damage: the crowd's pressure |
| `press_hp`, `press_dmg` | Σ current HP, Σ damage per hit |
| `alive_by` | `{creature id: up now}` |
| `boss_hp` | the boss's health as a fraction while one is up |
| `boss_now` | (pass 77) the boss's current HP itself while one is up (`boss_hp` stays its share) |
| `near3`, `near6` | (pass 77) creatures up within 3 m / 6 m of the hero (flat; `RunAnalytics.NEAR_CLOSE`, `NEAR_WIDE`) |
| `stats` | the player sheet: max_hp, damage_reduction, regen, move_speed, might, cooldown, area, projectile_speed, duration, amount, magnet, luck, greed, xp_gain, lifesteal, evade, crit_chance, crit_damage, thorns, execute_frac, overkill, haste, shield_max, ricochet, cooldown_on_kill; pass 47 adds still_regen, still_might, barrel_speed, barrel_seconds, xp_drop_chance, elite_damage, debuff_duration, difficulty, skips, banishes (the stage's); pass 62 adds powerup_duration, powerup_chance (`RunAnalytics.STAT_KEYS`; their words in the header's `stat_names`) |
| `weapons` | `[{id, level, mut: [mutation ids], dmg, cd, amount, pierce, area, est}]` from each weapon's folded sheet |
| `passives`, `lines` *(2)*, `perks` | `{id: level}` (the passive items; *(2)* the lines apart), `[ids]` (before pass 46 also `lines`, `{id: rank}`) |
| `mults` | the creatures' multipliers for one spawned now: `stage`, `hp_t` (the timeline's HP ramp), *(2)* `dmg_t` (its damage ramp), `lvl_hp`, `lvl_dmg` (scaling with the hero's level), `time_scale` (High Noon) |

## Events

Every event carries `t` (play seconds) and `clock`, plus `kind` and, when they apply, `id` and `level`. Item kinds
(`weapon`, `passive`, `mutation`, `perk`, `evolution`, `passive_evolution`) also carry `via` (how the item came:
`starter`, `card`, `path`, `chest`, `boss_chest`, `stranger`, `shop`, `debug`), `est_before` (the build's estimated
DPS before it) and `est_after` (after the sheets rebuilt). A key an event passes as `kind` is kept as `item_kind`, and
the event's own `t`, `clock` and `kind` are never overwritten.

| kind | extra keys |
|---|---|
| `weapon` | `id`, `level` (the level reached), `new` (true when it joined the build) |
| `passive` | `id`, `level`, `new`; `favourite` when the hero's favourite arrived past level 1 (Ironwood's Cake, full at once); *(2)* `line: true` for a line (a fortune card) |
| `mutation` | `id`, `weapon` (the family), `hero` (a hero mutation) |
| `perk` | `id` |
| `evolution`, `passive_evolution` | `id` (the evolved form), `from`; *(2)* `line: true` on a line's |
| `offer` | (pass 57) an offer the card screen settled: `id` (the pick, absent when skipped), `level` (the hero's), `route` (`level_up`, or `path` for a weapon's mutation offer: since pass 79 a mutation level-up), `cards` / `kinds` / `levels` (what was on the table: ids, `weapon`/`passive`/`perk`/`mutation`, the level each would reach), `skipped`, `decision_ms` (from showing to the pick), `weapon` (a path offer's family), `left` (skips left, when skipped), `rerolls`, `banished` ([ids]) |
| `chest` | `id` (what the reel landed on, empty for gold), `level` (level_to), `roll` (`weapon`, `passive`, `evolution`, `mutation`, `gold`), `take`; pass 47: `skip` true and `left` (the stage's skips left) when let go (before pass 47: false = sold, then `gold`), `boss` |
| `skip` | pass 47: `left` (the stage's skips left; skipping pays nothing now; before, `gold`); `id: "path"` when a mutation offer was skipped |
| `banish` | `id` (the card struck); pass 47: `where: "chest"` and `roll` when struck from a chest |
| `reroll` | |
| `debug_item` | `id`, `level`, `item_kind` (the debug hand's) |
| `level` | `level` (the new level) |
| `stage` | `level` = the stage that began (1-based) |
| `stage_beaten` | (pass 87) the stage's boss fell and the portal's countdown to Endless began: `level` = the stage, `stage_clock` |
| `endless` | (pass 87) the countdown ran out and Endless began: `level` = the stage (Game's own event) |
| `wave` | `level` = the endless wave that began |
| `boss_start` | `id` (the boss); *(2)* `hp` (its max HP as it came), and its HP pegging when it had one: `dps` (the hero's damage a second over the window), `ref` (the DPS the boss expects), `mult` (its HP multiplier), `window` (seconds); since pass 83 in the seconds mode (`boss_hp_scaling.mode`) also `mode` "seconds", `seconds` (the seconds of full DPS it was given) and `full_dps` (the hero's full DPS on it then; `dps` is the same number, `ref` and `window` 0) |
| `boss_end` | `id` (the boss) |
| `elite` | `id` (an Elite by its kind spawned) |
| `elite_mod` *(2)* | `id`, `mod`: a creature wearing an Elite modifier came |
| `elite_kill` *(2)* | `id`, `weapon` (what killed it), `mod` (the modifier it wore; absent for an Elite by its kind) |
| `special` *(2)* | `id`, `forced`: a coloured variance special came (`forced`: a Special swarm made it) |
| `special_kill` *(2)* | `id`, `weapon`, `chest` (its death dropped a chest) |
| `structure` | `id`, `effect` (`bank`, `vacuum_all`, `teleport`, `stranger`, `shop`, `heal`, `totem`, ...) |
| `stranger` *(2)* | the Stranger's deal taken: `id` (the item), `type` (`weapon`/`passive`/`mutation`), `level` (the level it comes at), `cost` (the fraction of max HP), `hp_max_before`, `hp_max_after` |
| `stranger_decline` *(2)* | his deal turned down: `id`, `type`, `level`, `cost` |
| `totem_offer` *(2)* | a Totem Pole's menu closed: `id` (the gift taken; absent when none was), `offered` / `stats` / `values` / `quality` / `words` (the gifts offered: ids, stats, amounts, quality 1-3, in words) |
| `totem` | (pass 73) a gift taken: `id`, `level` (gifts taken so far), `stat`, `value` |
| `mutation_due` | (pass 79) a mutation offer fell due on the stage clock and waits for the next level-up: `level` (the hero's), `due` (offers waiting after it), `slot`; `dropped: true` when it was spent with no weapon open (at its slot), at the level-up that took it (`at_level_up`) or as its screen opened (`at_screen`). A mutation level-up's own `offer` keeps `route: "path"` |
| `pickup` | `id`, `small` (cake slices, coin bags), `effect` |
| `portal_wait` | (pass 48) the boss is down and the portal waits: `level` = the stage |
| `portal` | `level` = the stage the portal closed, `extract` (pass 87: true = EXTRACT; false = "not yet", the countdown runs on) |
| `death` | `id` (the last creature whose hit the hero took), `hit` (melee/ranged/boss) |
| `revive` | `id` = `gold`, `ad`, `debug` or `phoenix` |
| `unlock` | `id` (the quest completed) |

## Chests, power-ups and totems (pass 82)

Garry: "a chart for Chests Picked up, Power-ups and Totems through a run". They are counted from the events above, the
same rule everywhere (`tools/level_editor/sim_model.js` `pickupKind`, `game/tools/sim_run.gd` `pickup_kind`,
`tools/analytics_csv.py` `pickup_kind`):

| count | the events |
|---|---|
| `chests` | every `chest` event: one per chest opened, taken or skipped (a skip spends the stage's skip and the game counts the chest as opened), a boss chest too; a banish re-rolls the same chest and adds none |
| `powerups` | every `pickup` event whose `small` is not set: Heart, Magnet Pulse, Nuke, Berserk, Shield, Sprint, Timeout today; not the small things underfoot (Cake Slice, Coin Bag, the pollen flowers: `params.small` in their content JSON). The game's own count of power-ups (the `pickups` total) is the same |
| `totems` | every `totem` event: a Totem Pole's gift taken |

An event counts from the first row whose `t` reaches it (`event.t <= row.t + 0.001`, as the deaths do). Where they show:

- the run sim's player files (`game/tools/sim_run.gd` series(); `tools/dl/p77/keys_SIMRUN.md`): `chests`, `powerups`,
  `totems`, one count a row as long as `t`; a sim's `result.json`: `series.chests|powerups|totems` (the mean over the runs
  still playing, like kills), `players[].chests|powerups|totems` (each run's own at its end) and
  `summary.chests_mean|powerups_mean|totems_mean`. A sim from before pass 82 has none (its chart is left out);
- the Sim's chart **Chests, power-ups, totems** (the Level Editor's Sim tab and the dashboard's Sim charts: one run, an
  average, a compared sim dashed grey);
- the dashboard's own card **Chests, power-ups and totems** (the three counts as steps, each one marked at the bottom and
  listed), and the marks under the level in **Progression**;
- the rows CSV: three columns `chests`, `powerups`, `totems` after the row's own keys;
- the Watch (game/tools/watch): the run's totals so far and a mark on its Level and XP chart at each one.

## Gold (pass 61)

Garry: "Coin Gains / Spend (During gameplay and not, have all the sources)". Every `Run.add_gold(n, source)` and
`Run.spend_gold(n, sink)` names where the gold came from or went, and every `Save.add_gold(n, reason)` /
`Save.spend_gold(n, reason)` why the saved gold moved (`RunAnalytics.GOLD_SOURCES`, `GOLD_SINKS`, `META_REASONS`;
`pass61_an_test` fails on a call that names none). The amounts are what reached the purse, greed included.

| in a run: source | where the gold came from |
|---|---|
| `coins` | a coin a creature dropped (the stage multiplies every coin) |
| `loose_change`, `gold_dust`, `boss_coins`, `loot_cache`, `blasting_cap`, `barrel` | coins of those origins (`PickupManager.mark_coin`): Loose Change's tossed coin, the Sun Scepter's Gold Dust, the boss's shower, the Loot Cache's coins (and its purse), Mira's Blasting Cap mine, a black barrel's 1-5 coins (pass 87); a merged coin counts as `coins` |
| `coin_bag` | Pickpocket's bag (a pickup with `effect: gold`, named by its id) |
| `elite_purse`, `boss_purse` | the purse an Elite's or a boss's death pays |
| `chest` | a chest's gold (its gold roll, or gold when the build changed under the reel) |
| `hush_money`, `bounty`, `dice` | Hush Money's pay for a hit, Bounty Hunter's bounty, the dice shrine |
| `empty_offer`, `stranger_empty`, `shop_empty` | gold instead of a level-up, a Stranger or a shop with nothing left to offer |
| `debug` | the developer's +gold buttons (the boards leave it out) |

| in a run: sink | where it went |
|---|---|
| `shop` | a card bought at the shop structure |
| `revive` | GET UP for gold on Down! (150) |

The Strongbox is not a spend: it banks the purse (`strongbox` below, and the row's `banked`).

| saved gold: reason | |
|---|---|
| `run_bank` | the purse a run's end brings home: since pass 70 every end (an extraction, a death, an abandon, a plain end); only a quit (the app gone mid-run) loses it |
| `strongbox` | a Strongbox banking the purse mid-run |
| `talent_refund` | Take it all back (half of what the ranks cost) |
| `talent` | an Upgrade rank bought (a spend) |
| `hero` | a hero bought on the title (a spend, pass 69; `hero`, `price` ride along) |
| `wipe` | the progress wiped (the balance to 0) |
| `debug` | a tool's gold (never sent) |

### In PostHog

- `run_summary` (one a run): `m_gold_in`, `m_gold_out` (gold in and out in each bucket, sums), `gold_by_source`
  (`{source: gold}`), `gold_spent_by` (`{sink: gold}`), `gold_greed` (what greed added; inside the sources' totals), next
  to the older `m_gold` (the purse at the bucket's end) and `m_banked` (what a Strongbox banked so far).
- `run_end`: `gold_earned` (every source), `gold_spent`, `gold_greed`, `gold_debug`, `gold_strongbox`, `gold_purse`
  (held at the end), `gold_banked` (Strongbox + the run's end: all that reached the save), `gold_lost` (the purse of a
  quit, left in the sand; since pass 70 a death and an abandon bank it), `gold_before` / `gold_after` (the saved gold as
  the run began and at its end). `gold_earned - gold_spent = gold_banked + gold_lost`, and
  `gold_after - gold_before = gold_banked` (when nothing else moved the saved gold meanwhile). *(2)* The local header
  keeps the same block as `gold_end`.
- `gold_meta` (one for every move of the saved gold, `Save.gold_moved` -> `Analytics.meta_gold`): `delta` (signed),
  `reason` (the table above), `balance_after`, `in_run` (true for the Strongbox and the banking at a run's end, which
  also carry the run's ids); a talent buy adds `talent`, `rank` (the rank reached) and `form`; a refund `ranks` (how many
  went back) and `spent` (what they had cost). None from the arena's sandbox, a tool or the test runner. With
  `app_open.gold` (the balance at every launch) it draws the bank's balance over time.
- `hero_bought` (pass 69: a hero bought with BUY on the title): `hero` (his id), `price`, `currency` (gold), `gold_after`;
  its spend is also a `gold_meta` with reason `hero`.
- The boards: **88fits · Coins** (`tools/posthog_boards.py`) and a "Gold today" tile on Pulse.

## What reaches PostHog

Every recorder event whose kind is in `Analytics.KIND_EVENTS` goes out renamed as it happens (an item's once its
`est_after` is known): item kinds as `item_picked`, `offer` as `level_up` / `path_offer`, `banish`, `chest`,
`structure`, `pickup` (a small one counted into the summary instead), `boss_start` / `boss_end`, `elite`, `stage`,
`wave`, `portal_wait`, `portal`, `death`, `revive`, `unlock`, `debug_item`; *(2)* `totem` as `totem_taken` and
`special_kill` as `special_killed`; (pass 87) `stage_beaten` as `stage_beaten` and `endless` as `endless_started`. Plus
`run_start`, `run_end` and `run_summary`.

**Stages (pass 87).** Every event of a run carries `stage` (1-based), `stage_id` (`s1`...), `in_endless` (true when it
came in Endless) and `endless_wave` (0 outside Endless) as super properties, so any chart breaks down by stage and by
the stage's Endless. `run_end` adds `stage_id`, `stage_name`, `stage_index`, `stage_length`, `stage_count`, `outcome`,
`boss_killed`, `stage_clock`, `endless_s` and `run_time` (the header's keys above). The portal's `stage_cleared` event
says `choice: extract` or `not_yet` (before pass 87 also `continue` / `stay`). The boards (`tools/posthog_boards.py`):
"88fits · Stages" and a stage breakdown on the run boards. The rest stays in the local file only:
`level`, `skip`, `reroll` (the offer carries them), *(2)* `special`, `elite_mod`, `elite_kill`, `stranger`,
`stranger_decline`, `totem_offer`, and every row; since pass 78 all of it also travels inside `run_record` (below).

### run_record (pass 78): the whole record

Garry: "save raw data in some kind of JSON ... make it so that I'm able to download it". At the end of every run that
sends analytics (`Analytics.run_record`, from `RunAnalytics.finish` and from a quit, before `run_end`), the record file
itself (this schema: header, `samples`, `events`, exactly the text of `user://analytics/runs/<stamp>.json`) goes as
`run_record` events: the JSON's UTF-8 gzipped, base64, cut into parts of at most `Analytics.RECORD_PART_MAX` (100,000)
characters, one event a part, each with the run's properties (`run_id`, `hero`, `hero_look`, `map`, `map_rev`) and the
super properties (the install's `distinct_id`, `dev`, `app_version`, `device`, ...).

| property | meaning |
|---|---|
| `part`, `parts` | this part's number (from 1) and how many the run has |
| `data` | this part's slice of the base64 text |
| `enc`, `format` | `gzip+base64`, 1 (`Analytics.RECORD_FORMAT`) |
| `raw_bytes`, `gz_bytes`, `md5` | the record's UTF-8 size, its gzipped size, the md5 of its UTF-8 (the download checks all three) |
| `recovered` | sent at the next launch: the app was closed after the run's checkpoint (it went to the background) and before the run ended; the record is the checkpoint's, its `result` `killed` |
| `rows_left_out` | the record needed more than `Analytics.RECORD_PARTS_MAX` (24) parts: it went without its rows (header and events only) |

- **The budget.** PostHog discards an event over 1 MB (posthog.com/docs/data/ingestion-warnings) and takes a `/batch/`
  request under 20 MB (docs/api/capture). A part is at most ~102 KB as an event; a request carries at most
  `Analytics.REQUEST_MAX` (400,000 characters) of events (at least one), so a phone uploads a part or two at a time. A
  25-minute run is about 1 MB of JSON, ~110 KB gzipped, ~145 KB of base64: two parts. 24 parts hold ~2.4 MB of base64,
  a run of about five hours.
- **When.** At the run's end (with `run_end`, then sent at once); a quit (the window closed mid-run): queued on disk,
  sent at the next launch; the app closed by the phone after a checkpoint: the checkpoint leaves
  `user://analytics_pending_run.json` and the next launch sends that record (`Analytics.send_pending`, `recovered`,
  `result` `killed`); a crash without a checkpoint sends nothing.
- **Never** from a tool, a headless run or the test runner (`Analytics.runtime_block`), the arena, the run sim
  (`memory_only`), with the Settings switch off or no key; and nothing leaves before the play-data card is answered yes
  (a "No thanks" deletes what waited).
- **Downloading.** `python tools/posthog_runs.py` (the personal key in `tools/posthog_personal_key.txt`) finds the parts
  with the query API, joins and checks them, and writes `analytics/remote/<player>/<stamp>_<run id>.json` (this schema,
  plus the `remote` block of the header table) with a `.js` twin and `analytics/remote/index.js` / `index.json`
  (`window.REMOTE = {made, host, players: [{key, name, label, distinct_ids, runs, dev_runs, first, last, play_s}], runs:
  [the index row of each run + player, player_name, player_label, distinct_id, file, js, received, uuids, run_id, dev,
  parts]}`); the dashboard's *Remote runs* switch reads them. How-to: `analytics/howto/03_remote_runs.md`.

## Surveys (pass 59, pass 62)

End-of-run surveys come from PostHog Surveys (`core/autoload/Analytics.gd`, the card `ui/wanted/WSurvey.gd`); the how-to
is `analytics/howto/02_surveys.md`. They are not in the run file; in PostHog:

| event | properties |
|---|---|
| `survey shown` | `$survey_id`, `$survey_name` (the name as written in PostHog, run tag included), `counted_runs` (pass 62) |
| `survey sent` | the same, `$survey_response_<question id>` per answer, `$survey_questions`, `$survey_completed`, `$survey_submission_id`, `$set: {$survey_responded/<id>: true}` |
| `survey dismissed` | `$survey_id`, `$survey_name`, `counted_runs`, `$set: {$survey_dismissed/<id>: true}` (NOT NOW, Don't ask me again, the back gesture) |
| `survey_opt_out` / `survey_opt_in` | `where` (`card` or `settings`), `$set: {surveys_opt_out}` |

`counted_runs` is the player's lifetime count of runs of 60 s or more at that moment (the run that just ended included).
When a survey comes is set by a tag in its PostHog name: `[after N]` (first after counted run N, then every 3 counted
runs until answered), `[run N]` (after counted run N only), no tag (3 counted runs after the last survey, the first
counted run on a new install). The record on the phone is the save's `survey` key (kept through a wipe): `counted`,
`runs_since`, `answered` and `dismissed` (survey ids), `shown` (survey id -> the counted run it last came after) and
`armed` (the developer menu's "Next run asks"); an old save started `counted` at its finished runs (`totals.runs`).

## Index

`index.json` / `index.js` hold one row per finished run (the last 500), the dashboard's history and its history CSV.

- Schema 1 rows: `{file, stamp, started, hero, hero_name, map, result, length, clock, stage, level, kills, gold, version,
  headless}`.
- *(2)* Schema 2 rows (`RunAnalytics.index_row`): `file`, then every header field except the big blocks
  (`names`, `hit_log`, `samples`, `events`, `build`, `totals`, `timeline`, `quests`, `talents`, `talent_forms`,
  `totems`, `stat_names`, `build_text`), the small blocks flattened as `block.key` (`gold_end.gold_banked`, `fps.avg`,
  `settings.dev`, `launch.weapon`, `trait.stats.might`, `map_settings.boss_hp_scaling.ref_dps.brander`, ...), and:
  `talents` (ranks bought, all talents) and `talents.<id>` (each), `totems` (gifts taken), `damage` (all damage dealt),
  `top_source` (the source that dealt the most), `dps_end` (the build's estimate at the end), `build` (`build_text`),
  `hp_lost`, `hits_taken`, `bosses` (killed), `specials_killed`, `elites_killed`, `killer` (what put him down last).

## CSV (pass 74)

The dashboard's buttons and `python tools/analytics_csv.py` write the same files (its test compares them byte for
byte): UTF-8 with a BOM (Excel), comma-separated, numbers with a dot, CR LF line ends, named
`88fits_<stamp>_<what>.csv`.

- **rows** (`88fits_<stamp>_rows.csv`): one line per row (a second of play). The row's plain keys first in the table's
  order above (only those the run has; pass 78 put pass 77's `xp_total`, `hp_lost`, `hp_healed`, `boss_now`, `near3`,
  `near6` among them), a key the row leaves out written as 0 (`boss_hp`, `boss_now` empty: no boss up); (pass 82) then
  `chests`, `powerups`, `totems`, picked up so far (counted from the events: *Chests, power-ups and totems*); then each
  per-second map flattened as `group.key` (`dmg.revolver`, `took.goblin`, `healed_by.Heart`, ...; missing = 0); then the
  carried snapshots, filled forward to every second until the next: `mults.*`, `stats.*`,
  `weapons.<id>.level|dmg|cd|amount|pierce|area|est|mut`, `passives.<id>`, `lines.<id>`, `perks`. A list of plain
  values is one cell joined with `; `.
- **events** (`88fits_<stamp>_events.csv`): one line per event: `t, clock, kind, id, name (the id's display name),
  level`, then every other key any event has, sorted; an absent key is empty.
- **history** (`88fits_<when>_history.csv`): one line per run, every index field (above); from the page, the open
  folder's index; from the tool, a row made from each run file the same way the game makes its index row (a file
  without `build_text` gets its build line in the file's own key order).
- **a card's table** (the page only): `88fits_<stamp>_<card>.csv`, the table as the card shows it, with raw numbers
  (times in seconds, shares as fractions).

## The estimate

`WeaponInstance.dps_estimate()` on the weapon's folded sheet (might, cooldown, haste, area, amount and the targeted
passives already inside), matched on the behaviour that runs (a mutation may swap it): `damage × max(amount, 1) /
max(cooldown, 0.05)`; Orbiter `damage × amount × 2`; Beam `damage × (1 + chains) / cooldown`; Spawner `damage × 3`;
Smasher and GravityGun `damage × amount × 3 / cooldown`. Pierce is not in it (the row's `weapons[].pierce` is there for
a reader who wants to weigh it; the dashboard draws the estimate as it is). It is standing output, not hits that land;
the real line beside it is the point of the chart.

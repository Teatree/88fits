# Run record schema (pass 45, the Game Analytics Watch)

One JSON file per run, written by `game/core/systems/RunAnalytics.gd` (a Game child created for every real run; the
arena never records, and a launch file saying `"analytics": false` skips it). It is written when the run ends; a
checkpoint (`result: "in_progress"`) is written when the app goes to the background mid-run, and a run the game left
without an end is written as `result: "quit"`.

Paths: `user://analytics/runs/<stamp>.json` always; on the PC, when the game runs from the repo, also
`analytics/runs/<stamp>.json`, `analytics/runs/latest.js` (`window.RUN = {...};`) and `analytics/runs/index.js`
(`window.RUNS = [...]`, the rows under *Index*, the last 500) with `index.json`. `analytics/dashboard.html` opens from
`file://` and reads the two `.js` files with script tags; a file input or a drop opens any run file.

`schema` is 1. Numbers are snapped to 0.1 (stats to 0.001, multipliers and the boss bar to 0.01).

## Header

| key | meaning |
|---|---|
| `schema` | 1 |
| `version` | `application/config/version` |
| `hero`, `hero_name` | the character id and name |
| `map` | the map id |
| `seed` | `Run.map_seed` (the layout roll) |
| `started` | local time the run started, `2026-10-01T18:05:11` |
| `stamp` | `started` with `:` as `-`: the file name |
| `headless`, `platform`, `device`, `pid` | `DisplayServer` headless, `OS.get_name()`, `OS.get_model_name()`, the process id (tools find their own file by it) |
| `result` | `in_progress` (a checkpoint), `extract`, `death`, `abandon` (give up / timeout on the Down! screen), `end`, `quit` |
| `length` | play seconds (unpaused; the x axis of every chart) |
| `clock` | `Run.elapsed`, the stage clock, which freezes during a boss fight and at a portal |
| `stage`, `endless_wave`, `level`, `kills`, `gold`, `strongbox`, `revives` | the end state (`strongbox` = gold a Strongbox banked) |
| `build` | `{weapons: [{id, level, mutations: [ids]}], passives: {id: level}, perks: [ids]}` (a record from before pass 46 also has `lines: {id: rank}`) |
| `totals` | `Run`'s `damage_by_weapon`, `kills_by_weapon`, `kills_by_enemy` |
| `names` | `{id: display name}` for every id the file mentions (weapons, passives, perks, mutations, creatures, pickups, structures) |
| `hit_log` | the hero's last 30 s of hits as the Down! screen shows them (`{t, by, kind, fx, raw, dealt, shield, note, hp, fatal}`); only on a finished run |
| `samples` | the rows below |
| `events` | the events below |

## Sample row (one a second of play)

Sparse: a key that is missing means 0 or empty. `stats`, `weapons`, `passives`, `perks` and `mults` appear only on a
row where they changed (the sheet at most every 5 s unless an item was picked) and carry forward.

Pass 46 folded the lines into the passives: a record written since has no `lines` anywhere, its former lines are
`passives` and their events `passive` / `passive_evolution`. A record written before keeps `lines`, `line` and
`line_evolution`, and the dashboard reads both.

| key | meaning |
|---|---|
| `t` | play seconds |
| `clock` | the stage clock |
| `stage` | 1-based |
| `phase` | the director's phase: 0 normal, 1 boss, 2 portal |
| `wave` | the endless wave, 1-based (missing before endless) |
| `level`, `xp`, `xp_next` | the hero's level, XP into it, XP the level needs |
| `hp`, `hp_max`, `shield`, `invuln` | health, max, Energy Shield points, 1 while invulnerable |
| `gold`, `banked` | the purse and what a Strongbox banked |
| `kills` | the run total |
| `adren`, `cresc` | adrenaline and crescendo stacks |
| `steady` | pass 47: Steady Hand's attack-damage bonus right now (0 to 1.0 = +100%), from `Run.steady_might()` |
| `desp` | Desperado's attack damage bonus right now (0.36 = +36%; pass 46) |
| `est` | `{weapon id: estimated DPS}` from each weapon's sheet (`WeaponInstance.dps_estimate`, the pause screen's "dps") |
| `est_total` | their sum: the build's promise |
| `dmg` | `{weapon id: damage dealt this second}` (after crits and reduction, so it sums to `totals.damage_by_weapon`; also `blast`, `revive`, `grand_finale`) |
| `took` | `{creature id: HP the hero lost this second}` (a hit with no creature id is keyed by its name, e.g. `the ring of fire`) |
| `took_raw` | the damage thrown at the hero before reduction, shields and evasion |
| `took_kind` | `{melee, ranged, boss: HP lost}` |
| `hits`, `evaded`, `shielded`, `healed` | hits that reached the hero (shielded and evaded ones included), evaded count, shield points spent, HP healed |
| `killed` | `{creature id: kills this second}` |
| `elite_kills` | Elites (and elite-modified creatures) killed this second |
| `spawned` | `{creature id: spawned this second}` |
| `alive`, `cap`, `load`, `hard_cap` | creatures up, the director's live cap, the crowd in cap-share units, the timeline's hard cap |
| `press` | Σ over live creatures of max HP × damage: the crowd's pressure |
| `press_hp`, `press_dmg` | Σ current HP, Σ damage per hit |
| `alive_by` | `{creature id: up now}` |
| `boss_hp` | the boss's health as a fraction while one is up |
| `stats` | the player sheet: max_hp, damage_reduction, regen, move_speed, might, cooldown, area, projectile_speed, duration, amount, magnet, luck, greed, xp_gain, lifesteal, evade, crit_chance, crit_damage, thorns, execute_frac, overkill, haste, shield_max, ricochet, cooldown_on_kill; pass 47 adds still_regen, still_might, barrel_speed, barrel_seconds, xp_drop_chance, elite_damage, debuff_duration, difficulty, skips, banishes (the stage's) |
| `weapons` | `[{id, level, mut: [mutation ids], dmg, cd, amount, pierce, area, est}]` from each weapon's folded sheet |
| `passives`, `perks` | `{id: level}`, `[ids]` (before pass 46 also `lines`, `{id: rank}`) |
| `mults` | the creatures' multipliers: `stage`, `hp_t` (the timeline's HP ramp), `lvl_hp`, `lvl_dmg` (scaling with the hero's level), `time_scale` (High Noon) |

## Events

Every event carries `t` (play seconds) and `clock`, plus `kind` and, when they apply, `id` and `level`. Item kinds
(`weapon`, `passive`, `mutation`, `perk`, `evolution`, `passive_evolution`) also carry `via` (how the item came:
`starter`, `card`, `path`, `chest`, `boss_chest`, `stranger`, `shop`, `debug`), `est_before` (the build's estimated
DPS before it) and `est_after` (after the sheets rebuilt).

| kind | extra keys |
|---|---|
| `weapon` | `id`, `level` (the level reached), `new` (true when it joined the build) |
| `passive` | `id`, `level`, `new`; `favourite` when the hero's favourite arrived past level 1 (Ironwood's Cake, full at once) |
| `mutation` | `id`, `weapon` (the family), `hero` (a hero mutation) |
| `perk` | `id` |
| `evolution`, `passive_evolution` | `id` (the evolved form), `from` |
| `chest` | `id` (what the reel landed on, empty for gold), `level` (level_to), `roll` (`weapon`, `passive`, `evolution`, `mutation`, `gold`), `take`; pass 47: `skip` true and `left` (the stage's skips left) when let go (before pass 47: false = sold, then `gold`), `boss` |
| `skip` | pass 47: `left` (the stage's skips left; skipping pays nothing now; before, `gold`); `id: "path"` when a mutation offer was skipped |
| `banish` | `id` (the card struck); pass 47: `where: "chest"` and `roll` when struck from a chest |
| `reroll` | |
| `debug_item` | `id`, `level`, `kind` (the debug hand) |
| `level` | `level` (the new level) |
| `stage` | `level` = the stage that began (1-based) |
| `wave` | `level` = the endless wave that began |
| `boss_start`, `boss_end` | `id` (the boss) |
| `elite` | `id` (an Elite spawned) |
| `structure` | `id`, `effect` (`bank`, `vacuum_all`, `teleport`, `stranger`, `shop`, `heal`, ...) |
| `pickup` | `id`, `small` (cake slices, coin bags), `effect` |
| `portal` | `level` = the stage the portal closed, `extract` |
| `death` | `id` (the last creature whose hit the hero took), `kind` (melee/ranged/boss) |
| `revive` | `id` = `gold`, `ad` or `debug` |
| `unlock` | `id` (the quest completed) |

## Index

`index.json` / `index.js` rows: `{file, stamp, started, hero, hero_name, map, result, length, clock, stage, level,
kills, gold, version, headless}`.

## The estimate

`WeaponInstance.dps_estimate()` on the weapon's folded sheet (might, cooldown, haste, area, amount and the targeted
passives already inside), matched on the behaviour that runs (a mutation may swap it): `damage × max(amount, 1) /
max(cooldown, 0.05)`; Orbiter `damage × amount × 2`; Beam `damage × (1 + chains) / cooldown`; Spawner `damage × 3`;
Smasher and GravityGun `damage × amount × 3 / cooldown`. Pierce is not in it (the row's `weapons[].pierce` lets the
dashboard show a pierce-adjusted variant). It is standing output, not hits that land; the real line beside it is the
point of the chart.

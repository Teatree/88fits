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
| `gold_before` | pass 61: the saved gold (`Save.gold()`) as the run began |
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
| `gold_in`, `gold_out` | pass 61: `{source: gold that came in this second}` and `{sink: gold spent this second}` (see *Gold*); gold that came while the game was paused lands on the next row, and what no row took by the end goes into the last one, so the rows sum to the run's totals |
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

## Gold (pass 61)

Garry: "Coin Gains / Spend (During gameplay and not, have all the sources)". Every `Run.add_gold(n, source)` and
`Run.spend_gold(n, sink)` names where the gold came from or went, and every `Save.add_gold(n, reason)` /
`Save.spend_gold(n, reason)` why the saved gold moved (`RunAnalytics.GOLD_SOURCES`, `GOLD_SINKS`, `META_REASONS`;
`pass61_an_test` fails on a call that names none). The amounts are what reached the purse, greed included.

| in a run: source | where the gold came from |
|---|---|
| `coins` | a coin a creature dropped (the stage multiplies every coin) |
| `loose_change`, `gold_dust`, `boss_coins`, `loot_cache`, `blasting_cap` | coins of those origins (`PickupManager.mark_coin`): Loose Change's tossed coin, the Sun Scepter's Gold Dust, the boss's shower, the Loot Cache's coins (and its purse), Mira's Blasting Cap mine; a merged coin counts as `coins` |
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
| `run_bank` | the purse an extraction (or a run's plain end) brings home |
| `strongbox` | a Strongbox banking the purse mid-run |
| `talent_refund` | Take it all back (half of what the ranks cost) |
| `talent` | an Upgrade rank bought (a spend) |
| `wipe` | the progress wiped (the balance to 0) |
| `debug` | a tool's gold (never sent) |

### In PostHog

- `run_summary` (one a run): `m_gold_in`, `m_gold_out` (gold in and out in each bucket, sums), `gold_by_source`
  (`{source: gold}`), `gold_spent_by` (`{sink: gold}`), `gold_greed` (what greed added; inside the sources' totals), next
  to the older `m_gold` (the purse at the bucket's end) and `m_banked` (what a Strongbox banked so far).
- `run_end`: `gold_earned` (every source), `gold_spent`, `gold_greed`, `gold_debug`, `gold_strongbox`, `gold_purse`
  (held at the end), `gold_banked` (Strongbox + extraction: all that reached the save), `gold_lost` (the purse of a
  death, an abandon or a quit, left in the sand), `gold_before` / `gold_after` (the saved gold as the run began and at
  its end). `gold_earned - gold_spent = gold_banked + gold_lost`, and `gold_after - gold_before = gold_banked`.
- `gold_meta` (one for every move of the saved gold, `Save.gold_moved` -> `Analytics.meta_gold`): `delta` (signed),
  `reason` (the table above), `balance_after`, `in_run` (true for the Strongbox and the banking at a run's end, which
  also carry the run's ids); a talent buy adds `talent`, `rank` (the rank reached) and `form`; a refund `ranks` (how many
  went back) and `spent` (what they had cost). None from the arena's sandbox, a tool or the test runner. With
  `app_open.gold` (the balance at every launch) it draws the bank's balance over time.
- The boards: **88fits · Coins** (`tools/posthog_boards.py`) and a "Gold today" tile on Pulse.

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

`index.json` / `index.js` rows: `{file, stamp, started, hero, hero_name, map, result, length, clock, stage, level,
kills, gold, version, headless}`.

## The estimate

`WeaponInstance.dps_estimate()` on the weapon's folded sheet (might, cooldown, haste, area, amount and the targeted
passives already inside), matched on the behaviour that runs (a mutation may swap it): `damage × max(amount, 1) /
max(cooldown, 0.05)`; Orbiter `damage × amount × 2`; Beam `damage × (1 + chains) / cooldown`; Spawner `damage × 3`;
Smasher and GravityGun `damage × amount × 3 / cooldown`. Pierce is not in it (the row's `weapons[].pierce` lets the
dashboard show a pierce-adjusted variant). It is standing output, not hits that land; the real line beside it is the
point of the chart.

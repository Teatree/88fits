# 88fits run analytics (pass 45, the Game Analytics Watch)

The game records every real run (never the debug arena) as one JSON file: a row a second of the hero's power against
the crowd's pressure, plus every build change and notable moment as an event. `dashboard.html` draws it.

## Start here: which page answers which question (pass 82)

| You want to... | Open |
|---|---|
| **Watch a run again like a video** (your phone's or anyone's with play data on): the real game plays it on the PC, slow motion to 8x, a reel to jump anywhere, the taps as rings | [howto/04_replays.md](howto/04_replays.md): `python tools/posthog_runs.py`, then double-click `tools\replay.cmd` |
| See **real players' runs** (your phone, friends) second by second, one run at a time or **averaged** for one player or several: download them from PostHog and open them in `dashboard.html` | [howto/03_remote_runs.md](howto/03_remote_runs.md), step by step. The same steps are on the dashboard itself: press **Remote runs**, then **How do I get players' runs?** |
| See **one player's progress** on the PostHog boards (every chart filtered to them) | [howto/01_one_players_data.md](howto/01_one_players_data.md) |
| Choose **when a survey appears**, add one for a given run, test it on the phone | [howto/02_surveys.md](howto/02_surveys.md) |
| Look at **a run you played on this PC** (the editor binary) | double-click `dashboard.html`: it opens your newest run. Other files: **Open run files** or drop them on the page (below: *The dashboard*) |
| **Average several runs** you have as files (a folder of runs, a sim's player files) | `dashboard.html`, **Open a folder** or **Open run files**, tick them, **Average** (below: *The Sim's charts and averages*) |
| Put the **bot's sim beside real players** | `dashboard.html`, **Compare with a sim**, then a sim's `result.json` from `tools/dl/sim/runs/<sim>/` |
| Get **Excel / Google Sheets** files | the dashboard's **Download CSV** buttons, or `python tools/analytics_csv.py` for every run at once (below: *The dashboard*) |
| See **chests, power-ups and totems** through a run | the dashboard's card *Chests, power-ups and totems* (one run) and the Sim's chart of the same name (one run, averages, the Level Editor's Sim tab); what counts is in [SCHEMA.md](SCHEMA.md), *Chests, power-ups and totems* |
| Know **what a key in a run file means** | [SCHEMA.md](SCHEMA.md) |

## Where the runs land

- **Always:** `user://analytics/runs/<stamp>.json` (Windows: `%APPDATA%/Godot/app_userdata/88fits/analytics/runs/`;
  the Settings screen's developer menu shows the `user://` path). The file is written when the run ends (extract,
  death, give up) and again if the app is sent to the background mid-run (a checkpoint, `result: "in_progress"`); a
  run the game left without an end (a quit, a tool stopping early) is written on the way out as `result: "quit"`.
- **On the PC, when the game runs from the repo** (the editor binary, the editor's play button, every tool): the
  same file is copied into this folder. A run you played goes to `runs/`; a tool's run (headless, or started with
  `--script`: smoke_run, hell_check, perf_late, captures, tests) goes to `runs/tools/` (pass 74), so the dashboard
  opens on your own newest run. Each folder has its own `latest.js` (`window.RUN = {...};`, its newest run) and
  `index.js` / `index.json` (`window.RUNS = [...]`, the last 500). `runs/` is git-ignored and never pruned.
- **How many are kept in `user://`:** every one on the PC (the PC exe's runs live only there); a phone keeps its
  newest 50 (pass 74). A phone build writes only to `user://`.

## The dashboard

Open `analytics/dashboard.html` straight from disk (`file://`): it loads `runs/index.js` and `runs/latest.js` with
script tags (a `file://` page cannot fetch JSON), so your newest played run appears on open; the **Played runs /
Tool runs** switch loads `runs/tools/` instead. Other runs: pick them with the file input or drop them on the page (a
run from the PC exe: `%APPDATA%\Godot\app_userdata\88fits\analytics\runs`); a second and third file overlay their
curves (dashed) over the first for an A/B. "Where the runs come from" on the page says the same.

The cards (pass 74, record schema 2; a card hides itself when its run has no data for it, so schema 1 files still
open): the run (hero and the look played, trait, map and its settings, version, seed, result, talents, switches),
was the build strong enough, crowd pressure, when did the crowd outgrow me, health, what hurt me, the last 30
seconds, how hard did each boss scale, specials and Elites, which weapon carried, estimate against real, how did the
build grow (the lines, i.e. the fortune cards, apart), the picks, how did I choose (decision time, skips, rerolls,
banishes), chests, power-ups and totems (pass 82: the three counted through the run, each one marked and listed), totems and the Stranger, where did my healing come from, survivability per minute, how did his numbers
grow, how strong did the creatures get, stacking bonuses, the crowd against the cap, spawned against killed,
progression, gold, quest progress and the history. Every card has a table view.

**CSV downloads** (pass 74): the buttons at the top save this run second by second (`88fits_<stamp>_rows.csv`: one
line a second, every column, maps as `group.key`), this run's events (`_events.csv`) and every run in the history
(`_history.csv`, one line a run); every card's table has its own CSV button. UTF-8 with a BOM, commas, dot decimals:
Excel and Google Sheets open them as they are. For every run at once:
`python tools/analytics_csv.py [--runs <dir>] [--tools] [--out <dir>]` (default out `analytics/runs/csv/`).

Chart.js is vendored at `lib/chart.umd.js` (4.4.1) with a cdnjs fallback, so the page works offline.

## The Sim's charts and averages (pass 78)

Garry: "Add those charts to our Local Run Analytics dashboard so their formats match." Under the summary, **The Sim's
charts for this run** draws the open run with the Level Editor's Sim tab's own charts (DPS, HP, deaths, danger, keeping
up, close crowd, who is alive, what hurt, hits, healing, the cap, spawned and killed, creature strength, coins, damage
by source, kills by creature, level, XP, the build): the same definitions (`tools/level_editor/sim_model.js`), drawing
(`sim_plot.js`) and styles (`sim.css`), loaded from `../tools/level_editor/`, so a real run and a sim read alike. A
record without a key (before v0.63: no close crowd, no boss HP, no XP total) leaves that chart out.

**Averages.** Open several run files (or a whole folder: *Open a folder*), tick runs in *Runs you opened*, press
*Average*: every second of play averaged exactly the way the Sim tab averages its runs (`sim_avg.js` = `tools/sim_batch.py`
`aggregate()`, checked equal by `selftest_DASH78`): a series is the mean over the runs still playing at that second, the
bands the middle 80 %, the deaths over every run, the stage and boss marks medians; every readout says how many runs
are behind that second. *Compare with a sim* lays a sim's `result.json` dashed grey over any view; a sim's player files
(`tools/dl/sim/runs/<sim>/players/pNN.json`) can be averaged like runs.

## Phone runs and other players: Remote runs (pass 78)

A release-signed APK keeps `user://` private (`adb` cannot pull it). Since v0.64 every run that sends analytics also
sends its whole record to PostHog (`run_record`, see `SCHEMA.md`). Download them:

    python tools/posthog_runs.py                  # the last 30 days, new runs only
    python tools/posthog_runs.py --player "Name"  # one player (repeat for several); --since 2026-10-01; --all; --list

They land in `analytics/remote/<player>/` (git-ignored) with `analytics/remote/index.js`. The dashboard's **Remote
runs** switch lists the players and their runs: *Open* one (every card, as if it were played here), *Average the
ticked runs*, or *Average every run of the ticked players* (several players at once); *leave out developer runs* hides
the editor binary's and debug builds' runs. The how-to in plain words: `howto/03_remote_runs.md`.

## The record

`SCHEMA.md` documents the header keys, the sample row's sparse columns and every event kind, as the recorder
(`game/core/systems/RunAnalytics.gd`) writes them. In short: `samples[]` rows are sparse (a missing key is zero; the
build snapshot keys `stats`, `weapons`, `passives`, `lines`, `perks` and the creature multipliers `mults` appear only
when they change and carry forward), `events[]` carry `t` (play seconds, the x axis) and `clock` (the stage clock,
which freezes during a boss and at a portal), item events carry `via` and the estimate before and after, and `names`
maps every id in the file to its display name so the page needs no content folder.

A tool's `user://debug_launch.json` may say `"analytics": false` to launch a run without the recorder (perf_late's
`analytics=0` does, for the A/B of the recorder's cost).

## PostHog (pass 57)

The same run's story also goes to PostHog through `game/core/autoload/Analytics.gd` once `game/config/analytics.json`
holds the Project API key (`phc_...`) and `"enabled": true`: the recorder's events renamed (`Analytics.KIND_EVENTS`),
`run_start`, `run_end` and one `run_summary` carrying this dashboard's per-minute series. Tool runs, the gdUnit runner
and the debug arena never send. The plan, the boards and the setup steps are in `docs/analytics_plan.html`.

Pass 59: every install is a Person in PostHog named by the game (`player_name`, shown in Settings), nothing is sent before the
play-data card on the first launch is answered, and end-of-run surveys come from PostHog Surveys (API presentation). The
how-to (the first survey, editing questions, following a friend) is in `docs/analytics_plan.html`.

Pass 78: `run_record` carries the whole record (gzip + base64 parts, at most 100,000 characters each; a 25-minute run is
two parts, ~145 KB), downloaded by `tools/posthog_runs.py` into `analytics/remote/` for this dashboard (above).

Pass 60: `run_summary` carries the rest of this dashboard's curves (`m_hp_max`, `m_shield`, `m_took_raw`, `m_evaded`, `m_shielded`, `m_healed`, `m_shield_s`, `m_invuln_s`, `m_load`, `m_hard_cap`, `m_xp`, `m_banked`, `m_kills`, `m_phase`, `dmg_by_minute` for the top eight weapons, `kills_by_weapon`, `took_kind`, the final `build` / `build_text` and `est_end`), and `tools/posthog_boards.py` draws them on the Run curves board and the new Run health & weapons board, keeping every board's id when it reruns.

# 88fits run analytics (pass 45, the Game Analytics Watch)

The game records every real run (never the debug arena) as one JSON file: a row a second of the hero's power against
the crowd's pressure, plus every build change and notable moment as an event. `dashboard.html` draws it.

## Where the runs land

- **Always:** `user://analytics/runs/<stamp>.json` (Windows: `%APPDATA%/Godot/app_userdata/88fits/analytics/runs/`;
  the Settings screen's developer menu shows the `user://` path). The file is written when the run ends (extract,
  death, give up) and again if the app is sent to the background mid-run (a checkpoint, `result: "in_progress"`); a
  run the game left without an end (a quit, a tool stopping early) is written on the way out as `result: "quit"`.
- **On the PC, when the game runs from the repo** (the editor binary, the editor's play button, every headless tool):
  the same file is copied into this folder's `runs/`, `runs/latest.js` becomes `window.RUN = {...};` for the newest
  run and `runs/index.js` / `runs/index.json` list every run (`window.RUNS = [...]`, the last 500). `runs/` is
  git-ignored. A phone build writes only to `user://`.

## The dashboard

Open `analytics/dashboard.html` straight from disk (`file://`): it loads `runs/index.js` and `runs/latest.js` with
script tags (a `file://` page cannot fetch JSON), so the newest run appears on open. Other runs: pick them with the
file input or drop them on the page; a second and third file overlay their power, real DPS and HP curves (dashed)
over the first for an A/B. Headless tool runs (`smoke_run`, `hell_check`, `perf_late`...) carry `headless: true` and
are hidden from the history by default (a switch shows them).

The charts, top to bottom: the summary (hero, map, version, seed, result, play length against the stage clock, stage,
level, kills, gold, the final build), the power curve (estimated DPS from the weapon sheets, real DPS as a 10 s rolling
mean, the crowd's pressure on its own scale), health and incoming damage, the crowd against the director's cap,
progression, damage share per weapon (rolling, stacked to 100 %), estimate against real per weapon, the creatures
(HP lost to each, kills, spawned against killed, melee/ranged/boss), the items (each pick with how it came, the
estimate before and after, and the real DPS 20 s before and after), survivability per minute, the power-to-pressure
ratio, and the run history. Every chart has a table view.

Chart.js is vendored at `lib/chart.umd.js` (4.4.1) with a cdnjs fallback, so the page works offline.

## Phone runs

A release-signed APK keeps `user://` private: `adb` cannot pull it and scoped storage blocks a copy to Downloads. For
now the dashboard is for runs played on the PC. The follow-up is a developer-menu "copy the last run" (the hit log
already goes to the clipboard that way) with a paste box on the dashboard, or a POST to the PC over the hotspot.

## The record

`SCHEMA.md` documents the header keys, the sample row's sparse columns and every event kind, as the recorder
(`game/core/systems/RunAnalytics.gd`) writes them. In short: `samples[]` rows are sparse (a missing key is zero; the
build snapshot keys `stats`, `weapons`, `passives`, `lines`, `perks` and the creature multipliers `mults` appear only
when they change and carry forward), `events[]` carry `t` (play seconds, the x axis) and `clock` (the stage clock,
which freezes during a boss and at a portal), item events carry `via` and the estimate before and after, and `names`
maps every id in the file to its display name so the page needs no content folder.

A tool's `user://debug_launch.json` may say `"analytics": false` to launch a run without the recorder (perf_late's
`analytics=0` does, for the A/B of the recorder's cost).

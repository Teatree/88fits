---
name: ship-prod
description: Build the PRODUCTION version of 88fits (no debug options, only the art and sound the game can show, smaller and faster) as 88fits-prod.apk and 88fits-prod.exe from a pruned staging copy, check it, and put both in Google Drive beside the dev builds. Use ONLY when Garry asks for a prod / production / release build; every other build is the dev one (ship-to-phone).
---

# Ship the production build

Garry (2026-10-15): "It's time to make a production build version ... no debug options, no extra art (unless it's used
in the Level timeline) ... extra optimization for the art and stuff, to make the build smaller and faster ... from this
point onwards you will only make a prod build if I ask for it." So: **never build prod unasked.** The everyday build
stays `bash tools/ship.sh` (the ship-to-phone skill). When he asks for prod, ship the dev build first if the change is
not on the phone yet, then this.

## Do

1. `bash tools/ship_prod.sh` from the repo root (after `bash tools/ship.sh`, add `--quick`: ship.sh just ran the tests).
   About 10-15 minutes; it holds the Godot lock the whole time (like ship.sh) and stops at the first failed check.
   - the source: lossy imports, import, json -> tres for stale JSON, the parse check, the gdUnit tests (not with
     `--quick`), the Windows icon;
   - the staging copy `tools/dl/prod/stage/game` (tools/prod_stage.py): fresh every time, its own user folder, the
     Android Prod version code from the game's version (0.67 -> 6700);
   - the plan (game/tools/prod_plan.gd + prod_reach.gd: what the game can show), the prune (tools/prod_prune.py), the
     optimiser (tools/prod_optimise.py), import + json -> tres in the staging copy;
   - the checks in the staging copy: check_scripts, prod_check (Registry clean, every hero, creature, look, item and
     sound in play has its art, planning again drops nothing, prod forced hides every developer surface), smoke_run,
     prod_run_check (prod forced: boot, title without ARENA, Settings without the taps and the hold, the developer
     menu goes back, a real run with a planted launch file ignored, F1 does nothing);
   - the exports from the staging copy: preset "Android Prod" (signed with the project keystore, verified) and
     "Windows Desktop Prod" (version info, signed only when tools/keys/codesign.env exists);
   - the exe's cold start to the title (tools/prod_probe.py, 3 launches, its user folder must be %APPDATA%/88fits);
   - the numbers (tools/prod_report.py -> `tools/dl/prod/out/report.md`: dev vs prod sizes, where the APK's bytes go,
     what was taken out, the cold start);
   - Drive: `E:/My Drive/88fits builds/88fits-prod.apk` and `88fits-prod.exe` (the dev 88fits.apk / 88fits.exe stay).
   Options: `--no-drive` (a test), `--quick`, `--no-pc`, `--no-android`, `--out DIR`.
2. Confirm the sync with the Google Drive connector: search `title contains '88fits-prod'`; both files' `modifiedTime`
   within minutes and `fileSize` equal to the local files (if stale: the ship-to-phone skill's Drive for Desktop steps).
3. Tell Garry: "Prod build is in Drive -> My Drive -> 88fits builds -> 88fits-prod.apk / 88fits-prod.exe", the sizes
   from report.md (dev vs prod), what changed, and the folder link
   https://drive.google.com/drive/folders/1DitOJiGvXaY3PXKUegknJJBtPPb-7_SM.

## What prod is

- **Its own app**: package `com.eightyeightfits.game.prod`, label "88fits" (the dev app is "88fits Dev",
  `com.eightyeightfits.game`), so it installs beside the dev build and Garry's dev save on the phone is untouched. On
  the PC the prod exe keeps its save in `%APPDATA%/88fits` (the dev build's is `%APPDATA%/Godot/app_userdata/88fits`).
  Same version (application/config/version); analytics tags every event `build: prod` (dev: `build: dev`).
- **No debug options** (the presets' custom feature `prod` -> `Settings.is_prod()`): no developer menu (the version-line
  hold), no player's debug mode (the ten taps) and so no ARENA on the title, no in-run debug panel (nor F1), no debug
  hand on the pick screens, no free revive or hit log on Down!, no Settings debug panel (the menu style stays Live,
  ranged-on-screen and the pierce drop-off stay on), `user://debug_launch.json` ignored. `Settings.PROD_LOCKED` lists
  the switches and their player values.
- **Only what the game can show**: hidden heroes (Dad, Mira), hidden weapons, evolutions, mutations, perks, creatures
  (the training dummies...), pickups and structures go with their quests, unless the map, a boss (summons), a creature,
  a perk or the code names them (game/tools/prod_reach.gd says why for each); heroes and cards keep only the look they
  play (made the base), creatures the base, the played look and every look a map row or event names; the title
  cut-outs of dropped looks; the painters' `_ai.json`; sound files the sound map does not name.
- **Smaller and faster**: music as Ogg Vorbis (q4, about 110 kbps) instead of QOA WAV, the 1024 px project icon at 256 px,
  the last lossless prop billboards lossy, icon.ico out of the APK; fewer textures for the Registry to load at boot.

## Do not

- Do not build prod when Garry did not ask for it.
- Do not prune or optimise the source tree: everything happens in `tools/dl/prod/stage/game` (the tools refuse game/).
- Do not change the prod package id or sign the prod APK with another key: Android would refuse the update and an
  uninstall wipes the prod save.
- The ship-to-phone skill's rules hold here too: no APK through the Drive connector or the chat card, no debug export,
  never uninstall the app on the phone to fix an install.
- Do not run it while another ship (ship.sh or ship_prod.sh) runs: both hold the Godot lock; it waits.

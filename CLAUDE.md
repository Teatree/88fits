# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`88fits` is a portrait, one-thumb, third-person survivor-shooter (Megabonk / Vampire Survivors mould) built in **Godot 4.7.2 with GDScript**. The design bible at `docs/design/design-bible.html` is the spec; section 14 holds the one hard rule: **every weapon, passive, evolution, enemy, elite modifier, character, shop upgrade, quest, sound and wave timeline is a content folder, never code.** Code changes are only for new reusable behaviour primitives.

The Godot project root is `game/` (`res://` = `game/`). The editor binary sits in `Godot_v4.7.2-stable_win64/` at the repo root and is git-ignored. The repo is a git repository; commit only when asked.

## Commands

```
GODOT="D:/_projects/88fits/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe"
P="--headless --path D:/_projects/88fits/game"

"$GODOT" $P --import                                            # (re)import assets after adding png/wav/tscn
"$GODOT" $P --script res://tools/check_scripts.gd               # parse-check every .gd and instantiate every .tscn
"$GODOT" $P --script res://tools/import_json.gd                 # regenerate <id>.tres from <id>.json for all content
"$GODOT" $P --script res://tools/gen_placeholders.gd            # placeholder sprites + icons (then --import, then import_json)
python tools/gen_sfx.py                                         # placeholder wav for every sound id (then --import)
"$GODOT" $P -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests           # all tests
"$GODOT" $P -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/stat_sheet_test.gd  # one file
"$GODOT" $P --script res://tools/smoke_run.gd -- seconds=90     # headless integration run: boss, portal, results, menus
"$GODOT" --audio-driver Dummy --path D:/_projects/88fits/game --script res://tools/screenshot_run.gd -- out=<dir>   # windowed, silent, saves PNGs
"$GODOT" --path D:/_projects/88fits/game -e                     # open the editor
JAVA_HOME=D:/_projects/88fits/tools/jdk17/jdk-17.0.20.1+1 "$GODOT" $P --export-debug "Android" export/88fits-debug.apk   # signed debug APK
bash tools/ship.sh [--quick] [--no-install]                       # checks -> signed APK -> install + launch on the phone (adb over USB or Wi-Fi)
bash tools/release.sh "note"                                      # upload the APK as the next GitHub release in the private builds repo (needs gh auth login once)
python tools/gen_textures.py && python tools/gen_music.py && python tools/paint_pass.py   # art + music regeneration (see docs/RUNNING.md)
python tools/gen_voice.py                                       # voice barks via Kokoro TTS at http://127.0.0.1:7860 (Pinokio); then --import + import_json
python tools/gen_art.py [--anchor|--pick=N] [--only id] [--force] [--seed=N]   # Clash-style sprites/icons via Flux.2 Klein on ComfyUI (192.168.137.54:8188), vision QA, review sheets, imports at the end
python tools/comfy.py --export                                  # ComfyUI workflows as UI-loadable JSON in tools/comfy_workflows/
python tools/animate.py <still.png> "<motion in place>" [seed]   # one Wan 2.2 image-to-video run cycle -> tools/dl/ai_anim/<key>/ (see .claude/skills/sprite-animation)
"$BLENDER" -b --python tools/blender_props.py -- out=D:/_projects/88fits/game/art/props     # 16 GLB props; BLENDER=%LOCALAPPDATA%/Programs/blender-5.2.0-windows-x64/blender.exe
```

Do the parse check and the smoke run after any change to `core/`, `player/`, `game/` or `ui/`. When a change is something the user should try, finish with `bash tools/ship.sh` (checks + signed APK + install on any phone adb can see) which also overwrites the build in Google Drive (`E:/My Drive/88fits builds/88fits.apk`, the route the user actually uses from the phone; `tools/release.sh` is the GitHub backup) and tell the user the build is in Drive: the user plays on the phone, often away from the PC, and steers this project from it, so every user-facing change ends in a build they can tap. The chat file card cannot carry the APK (30 MiB limit, the build is 32). Headless runs print `SCRIPT ERROR:` with file:line on failure; exit code is non-zero.

## Godot 4.7 gotchas that bit this codebase

- `var x := expr` fails to parse when `expr` is Variant-typed. Common sources: untyped `for` variables over a plain `Array` (type them: `for w: WeaponDef in list`), and `max()/min()/clamp()` which return Variant (use `maxf/maxi/minf/mini/clampf`). Use `var x: Type = expr` when in doubt.
- `SceneTree` scripts run with `--script` are compiled **before autoloads exist**. In tools, never name an autoload (`Run`, `Save`, `Registry`, `Audio`, `Settings`) or a class that references one at compile time; fetch them with `root.get_node("Run")` and defer work to `process_frame` (see `tools/smoke_run.gd`).
- `queue_free()` does not shrink `get_child_count()` in the same frame; loops that wait on it hang.
- Pausing uses `get_tree().paused`; the UI CanvasLayer is `PROCESS_MODE_ALWAYS`. Systems also check `game.paused`.
- Godot front faces are **clockwise**. A SurfaceTool mesh wound counter-clockwise is silently back-face culled; the terrain rendered as the sky's lower half for hours before anyone noticed. Check winding first when a generated mesh "has no texture".

## Architecture

- **Autoloads** (`core/autoload/`): `Registry` scans `res://content/**` at boot (prefers `<id>.tres`, falls back to `<id>.json`), `Save` (one JSON file in `user://`), `Settings`, `Audio` (sound ids from the sound map, voice-limited, layered music), `Run` (state of the current run: XP, gold, weapons as `WeaponInstance`, passives, evolution logic, chest logic).
- **Data classes** (`core/data/`): `Effect` {stat, op add|mul|set, value, target} is the only way numbers change. `WeaponDef`, `PassiveDef`, `EnemyDef`, `EliteModDef`, `CharacterDef`, `ShopUpgradeDef`, `QuestDef`, `MapDef` + `WaveTimeline`, `SoundMap`. `JsonContent` converts JSON to these; `tools/import_json.gd` writes `.tres`.
- **Stats**: `StatSheet` = (base + Σadd) × Π(1+mul) with sources kept for the pause screen breakdown. `WeaponInstance.rebuild()` folds player multipliers (might, cooldown, area, amount, targeted passives) into each weapon's sheet. `TextGen` generates every card, pause and collection description from data.
- **Game scene** (`game/Game.gd`): wires map, player, camera, `EnemyManager` (packed arrays + one MultiMesh per enemy type, camera-facing billboard shader in `core/shaders/`), `ProjectileManager`, `PickupManager` (gems/coins MultiMeshes, magnet, merge, chests), `Telegraphs`, `Fx`, `WaveDirector` (live cap, roster, events, boss, portal, stage clock), weapon behaviours (`core/behaviors/`: ProjectileEmitter, Orbiter, Lobber, Beam, Spawner+Turret) and the in-run UI (`ui/HUD`, `CardScreen`, `PauseScreen`, `PortalDialog`, `Hints`, `DebugPanel`).
- **Content folders**: `content/<type>/<id>/` holds `<id>.json` (authoring source), `<id>.tres` (generated, Inspector-editable), optional `<id>_visual.tscn` (weapon meshes/particles: nodes named `Projectile`, `Held`, `Muzzle`), `<id>_icon.png`, `<id>_sprite.png` (animation strip in the fixed order idle, run, attack, hit, die / characters add turn, cheer). `content/sounds/soundmap.json` binds sound ids.
- **Map**: `world/MapBase.gd` provides `height_at`, obstacle circles, flats centre; `world/maps/dry_gulch/DryGulch.gd` builds the greybox procedurally from exported tunables.
- **Hub screens** (`ui/`): `TitleScreen`, `PlaySetup`, `ShopScreen`, `CollectionScreen`, `ResultsScreen`, `SettingsScreen` extend `ScreenBase` and are built in code with `UiKit`.
- **Editor plugin** `addons/content_dock/`: lists content, warns on missing files, "New from template", JSON→.tres, and test-launch (writes `user://debug_launch.json`, which `Game.gd` reads to skip the starter pick).

## Adding content (no code)

Copy a folder under `content/<type>/`, rename the folder and the `id` in the JSON, edit numbers, run `import_json.gd` (or press "JSON → .tres" in the Content dock). The Registry finds it on the next run; cards, pause text, collection and HUD icons follow automatically. Add a sound by adding a row to `soundmap.json` and running `gen_sfx.py`.

## Status (2026-09-14, pass 9)

M0-M4 are implemented and the game ships to Garry's phone through Google Drive (`bash tools/ship.sh` -> signed release APK -> `E:/My Drive/88fits builds/88fits.apk`; see `docs/RUNNING.md` and the ship-to-phone skill). Two maps: Dry Gulch (desert: goblins, fire ants, spit cacti, bull beetles, the Tumbleweed King, dust devil, tumbleweeds) and Mossy Hollow (meadow, `world/maps/mossy_hollow/`: bramble imps, toadstools, hornets, puffballs, boars, King Toad; geysers, a bee swarm, fireflies, a pond). Three heroes (Astro, Drifter, Dad), Astro is the default; icons are portrait badges. Structures are content too (`content/structures/`: healing well, loot cache, XP beacon, travelling shop, war drum, dice shrine, uber magnet; `StructureDef`, scattered by `StructureManager` from the timeline's `structures` block, effects in `Game.use_structure`, the shop overlay in `ui/StructureShop.gd`). Poison is an enemy debuff (EnemyManager.poison / poison_src per item, 2 s ticks, green tint, negative flash = green; weapon stats poison_damage/poison_stacks/poison_duration; PoisonCloud for bombs; `healthy` / `densest_healthy` targeting). Chargers carry eight directions (`"directions": 8`, view sectors in EnemyManager). Pickups are content (`content/pickups/`: heart, rage, sprint, shield, magnet pulse; `PickupDef`, scheduled per map by the timeline's `pickups` block, spawned by WaveDirector, applied by `Game.apply_pickup`, timed buffs live in `Run.timed`). Art: anime-style sprites and Shop-Titans-style icons come from ComfyUI at 192.168.137.54:8188 (Flux.2 Klein stills, Wan 2.2 image-to-video run cycles: `tools/gen_art.py`, `tools/animate.py`, `tools/comfy.py`, `tools/artkit.py`; skills sprite-pipeline and sprite-animation), with LM Studio's vision model on port 1234 for QA. Strips are grids (`strip_cols` in the JSON, `cols`/`rows` shader uniforms); heroes run 24 frames at 28 fps, creatures 12 at 15 (`fps` in the JSON). `tools/gen_ui.py` can paint a 9-slice UI skin but is not wired in. UI (`ui/UiKit.gd`): Survivor.io as the target, navy/gold palette, Lilita One + Baloo 2, `TapCard`, HUD strip 250 px with a round pause button and a buff row. Camera: fixed north-up at 20.5 m. Controls: floating joystick on touch, WASD / arrows on PC. Hero run and hit cycles are pose-driven (Mixamo FBX in `tools/dl/mixamo/` -> `tools/pose_driver.py` -> Wan 2.2 Animate via `animate.cycle_pose`; method page `docs/design/pose-animation.html`). Test runs use `--audio-driver Dummy`; `smoke_run.gd` and `screenshot_run.gd` take `map=`, `character=` and `weapon=`. Weapon visuals may carry a `Held` gun (forward weapons) or a `Familiar` companion that orbits the hero and fires (Peashooter's pea pod; tuning in `params.familiar`); friendly arcing shots fly through enemies and explode on landing. Ground telegraphs are draped meshes (`Telegraphs.height_fn`), never flat discs.

---
name: godot
description: Run, import, test, and export the 88fits Godot 4.7 project headlessly, plus Godot 4 conventions and pitfalls for this repo. Use whenever touching game/ or running the game.
---

# Godot workflow for 88fits

The Godot project root is `game/` (so `res://` = `D:/_projects/88fits/game`).
The editor binary is checked in the repo folder but git-ignored:

```
GODOT="D:/_projects/88fits/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe"
```

Always pass `--path D:/_projects/88fits/game` (absolute, forward slashes) and `--headless` for anything automated.

## Commands

| Task | Command |
|---|---|
| Import assets (after adding png/wav/glb) | `"$GODOT" --headless --path D:/_projects/88fits/game --import` |
| Run a tool script (SceneTree script) | `"$GODOT" --headless --path D:/_projects/88fits/game --script res://tools/<name>.gd` |
| Smoke-run the main scene for N frames | `"$GODOT" --headless --path D:/_projects/88fits/game --quit-after 300` |
| Smoke-run a specific scene | `"$GODOT" --headless --path D:/_projects/88fits/game --quit-after 300 res://ui/TitleScreen.tscn` |
| Run all gdUnit4 tests | `"$GODOT" --headless --path D:/_projects/88fits/game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests` |
| Run one test file | `"$GODOT" --headless --path D:/_projects/88fits/game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<file>_test.gd` |
| Regenerate .tres from content JSON | `"$GODOT" --headless --path D:/_projects/88fits/game --script res://tools/import_json.gd` |
| Regenerate placeholder sprites + icons | `"$GODOT" --headless --path D:/_projects/88fits/game --script res://tools/gen_placeholders.gd` then `--import` |
| Regenerate placeholder sounds | `python tools/gen_sfx.py` then `--import` |
| Open the editor (not headless) | `"$GODOT" --path D:/_projects/88fits/game -e` |
| Export Android debug APK | `"$GODOT" --headless --path D:/_projects/88fits/game --export-debug "Android" export/88fits-debug.apk` (needs 4.7.2 export templates + JDK 17) |
| Install on phone | `"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" install -r export/88fits-debug.apk` |

Exit code from a headless run is non-zero on script errors. Read stdout for `SCRIPT ERROR` lines; they include file:line.

## Conventions in this repo

- Godot 4 API only. Never Godot 3 (`instance()` → `instantiate()`, `yield` → `await`, `export var` → `@export var`, `onready` → `@onready`, `KinematicBody` → `CharacterBody3D`, `move_and_slide()` takes no args and uses `velocity`).
- Custom resources use `class_name` and `extends Resource`; exported fields stay untyped `Array`/`Dictionary` so hand-written `.tres` and the JSON importer stay simple.
- Content lives in `res://content/<type>/<id>/` as `<id>.json` (authoring source), `<id>.tres` (generated, editor-editable), optional `<id>_visual.tscn`, `<id>_icon.png`. Never hard-code content in scripts. See `Registry` autoload.
- Enemies are data-oriented: `EnemyManager` holds packed arrays and a `MultiMeshInstance3D` per enemy type. Do not add per-enemy nodes.
- Autoloads: `Registry`, `Save`, `Audio`, `Run`, `Settings`. Access them by name.
- Sounds are played by id: `Audio.play("w_boom_fire", position)`. Ids come from the design bible section 16.
- Compatibility renderer, portrait 1080x1920 base, `canvas_items` stretch with `expand` aspect.

## Pitfalls seen

- `Image.create` is deprecated; use `Image.create_empty(w, h, false, Image.FORMAT_RGBA8)`.
- In `--headless` mode, `DisplayServer` is a dummy: never rely on window size; use `get_viewport().get_visible_rect()` with a guard.
- `ResourceSaver.save(res, path)` is (resource, path) in Godot 4.
- `.tres` typed arrays are painful to hand-write; the importer produces them, humans edit in the Inspector.
- When a `.tscn` references a script, make sure the script parses on its own first: run the tool script `res://tools/check_scripts.gd` which loads every `.gd` under `res://` and reports parse errors.

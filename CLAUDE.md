# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`88fits` is a portrait, one-thumb, third-person survivor-shooter (Megabonk / Vampire Survivors mould) built in **Godot 4.7.2 with GDScript**. The design bible at `docs/design/design-bible.html` is the spec; section 14 holds the one hard rule: **every weapon, passive, evolution, enemy, elite modifier, character, shop upgrade, quest, sound and wave timeline is a content folder, never code.** Code changes are only for new reusable behaviour primitives.

The Godot project root is `game/` (`res://` = `game/`). The editor binary sits in `Godot_v4.7.2-stable_win64/` at the repo root and is git-ignored. The repo is a git repository. **Always commit your changes** (Garry, 2026-10-07: "always commit changes to git, we haven't been doing that so far"): when a request or pass is done and its checks pass, `git add -A` and commit on the current branch with a message that says what changed (one commit per pass or finished request; a long pass may commit at its milestones). Look at `git status` first so nothing unexpected (a huge render, a secret) goes in; never push unless asked. Parallel lanes do not commit: the lead commits once their work is merged and verified.

## Commands

```
GODOT="D:/_projects/88fits/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe"
P="--headless --path D:/_projects/88fits/game"
bash tools/godot.sh $P --import       # pass 66: run EVERY Godot command through this wrapper instead of "$GODOT": it takes the repo-wide Godot lock (tools/dl/locks/godot.lock, one Godot process at a time across lanes and the Level Editor's server), keeps the PC save aside and restores it; `python tools/locks.py status` shows who holds the Godot or ComfyUI lock
python tools/level_editor/selftest.py                           # pass 66: the Level Editor's own checks (17,023; Node needed): model.js, the server on temp copies, and every selftest_<lane>.py group (S content writer/routes/vocab, J jobs, P page maths/rules, V previews, B methods.json)
python tools/asset_job.py <job_dir> [--dry-run]                 # pass 66: how the Level Editor runs an art job (job.json -> argv -> gen_art.process / gen_ctl.main / the candidate scripts; --dry-run records the prompts into dry_run.json); ASSET_JOB_SIDECAR=<path> makes gen_art/gen_ctl write result.json instead of the content JSON
python tools/gen_badge_cands.py --id <hero> --seeds 4 [--prompt ..] && python tools/gen_badge_cands.py --id <hero> --pick k [--head-width f --top-pad f]   # pass 66: hero badge candidates (RAW/<id>_portrait_c<k>.png, review/<id>_badge_cands.png), the pick written to <id>_icon.png + badge{}
"$BLENDER" -b --python tools/blender_ref.py -- src=<fbx|glb|obj> out=<dir> mode=probe|icon|views|all   # pass 66: what a 3D file can do (probe.json: rig, actions, rigmap guess), the icon reference render (3/4 view), the five sprite views as clay.png + look.png
"$BLENDER" -b --python tools/blender_depth_drivers.py -- src=<file> out=tools/dl/drivers/<name> action=<clip> mode=cycle|oneshot [frames=12 cycles=2 depth=tight amp=1.7 amp_bones=<regex>]   # pass 66: depth drivers from a rigged model's own clip (the beetle method for any model); pose_driver.py gained src= rigmap=<json> probe=1

"$GODOT" $P --import                                            # (re)import assets after adding png/wav/tscn
"$GODOT" $P --script res://tools/check_scripts.gd               # parse-check every .gd and instantiate every .tscn
"$GODOT" $P --script res://tools/import_json.gd                 # regenerate <id>.tres from <id>.json for all content
"$GODOT" $P --script res://tools/gen_placeholders.gd            # placeholder sprites + icons (then --import, then import_json)
python tools/gen_sfx.py                                         # placeholder wav for every sound id (then --import)
"$GODOT" $P -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests           # all tests
"$GODOT" $P -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/stat_sheet_test.gd  # one file
"$GODOT" $P --script res://tools/smoke_run.gd -- seconds=90     # headless integration run: boss, portal, results, menus
"$GODOT" $P --script res://tools/arena_check.gd                 # headless run through the debug arena (every tab, spawns, items, leaving)
"$GODOT" $P --script res://tools/touch_audit.gd [-- only=settings,pause]   # every button, card, slider and list on every screen, driven by simulated finger events (ship.sh runs it)
"$GODOT" $P --script res://tools/hell_check.gd [-- seconds=120]    # headless Stage 3: the hell crowd on its own cap, the red ground, the Gila's rumble, the giant's slam, the Brander's ring and lines, endless waves (pass 43)
"$BLENDER" -b --python tools/blender_tommy.py                     # the Tommy Gun GLBs from Garry's model in _REFERENCES/3d/tommy_gun (pass 44) + the icon's 3/4 reference render tools/dl/tommy_ref.png
python tools/gen_tommy_icon.py --seeds=4 && python tools/gen_tommy_icon.py --pick tommy_gun=N chicago_typewriter=N   # Tommy Gun icons from that render, picked by eye (tools/dl/tommy_icons/review_*.png)
"$BLENDER" -b --python tools/blender_barrel.py                    # art/props/barrel.glb (Body + Hoops) for BarrelField (pass 44)
python tools/pose_occlude.py tools/dl/drivers/run tools/dl/drivers/run_occ   # a hero run driver whose back views hide the hand that swings in front of the chest (pass 44; hero JSON "pose_drivers": {"back": "run_occ", "bd": "run_occ"})
python tools/pose_spread.py tools/dl/drivers/run tools/dl/drivers/run_spread [spread=0.06]   # a hero run driver whose back views push the wrists out past the torso (pass 45; Calavera's "pose_drivers")
"$BLENDER" -b --python tools/blender_scorpion.py -- out=tools/dl/drivers/scorpion_walk frames=12 cycles=2   # Garry's 3D scorpion walked on its rig: depth videos + clay in five views (pass 46); mode=death out=tools/dl/drivers/scorpion_death = its death (front, 25 frames)
python tools/gen_ctl.py --id=dune_scorpion --variant=SC-A [--dev] [--use-side=kN] [--view-cands=fd,back | --use-view=fd:c0]   # a creature variant walked on a 3D model's control video (gen_ant generalised; the recipe lives in the creature JSON; "death_drivers" walks the death too)
"$BLENDER" -b --python tools/blender_guitar.py   # also blender_turret.py, blender_spear.py: the Guitarra/Requiem from Garry's cartoon guitar, our turret (Base/Tripod/Sandbags stances), the Spear/War Lance + their icon references
"$BLENDER" -b --python tools/blender_beetle.py -- out=tools/dl/drivers/beetle_walk_amp frames=12 cycles=2 depth=tight amp=1.7   # the Bull Beetle's drivers from Garry's rigged rhino beetle (_REFERENCES/3d/a-rhino-beetle.zip), its own walk clip in five views (+ look.png in its own colours); mode=death out=tools/dl/drivers/beetle_death plays its death clip (pass 48); pass 49: depth=tight (each view's own depth range, written Raw: AgX had flattened every depth video) and amp (the legs swing that much wider round their average)
"$BLENDER" -b --python tools/blender_dice.py   # two true-cube dice -> tools/dl/dice_ref.png, the reference Hot Streak's icon is painted from (pass 49: Flux bends dice)
"$BLENDER" -b --python tools/blender_rocket.py   # also blender_grenade.py: the Vulture Raider's black rocket (art/props/enemy_rocket.glb) and the Golden Pineapple's grenade (golden_grenade.glb), one vertex-coloured mesh each (pass 48)
"$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/walking.fbx out=tools/dl/drivers/walk_hold frames=12 arms=hold_r   # a walk whose right hand holds something up at the shoulder (the Vulture Raider's launcher, pass 48)
python tools/compress_levels.py [--check]   # pass 48: weapons from 8 levels to 5 (level 5 = the old level 8); --check re-verifies against tools/dl/levels_v47.json
python tools/gen_icon_cands.py [--only spear,cake] [--seeds 4] && python tools/gen_icon_cands.py --pick spear=0   # icon candidates (renders as references), picked by eye
tools\level_editor.cmd                                           # pass 53: the Level Editor (a local page: waves, roster, events, overrides per map; Save writes the JSON + imports it); schema docs/waves_schema.md
tools\ship.cmd [--quick] [--no-install]                          # pass 53: ship.sh from a double-click (Git Bash)
python tools/recolour_strip.py --src <strip.png> --dst <strip.png> --ranges 55-135 --to 357 --sat 1.0 [--preview p.png]   # pass 53: a strip recoloured frame by frame (the Red Goblins from the goblins)
python tools/gen_edit_stills.py --id werewolf --stills wwa --ref _REFERENCES/2d/Werewolf.webp --prompt "..." --seeds 4 [--screen blue] && python tools/gen_edit_stills.py --id werewolf --stills wwa --pick 2   # pass 53: front candidates as Klein edits of a picture, picked by eye, then gen_art --variant paints the rest
"$BLENDER" -b --python tools/pose_driver.py -- glb="_REFERENCES/3d/Zombie monster walk.glb" rig=sm out=tools/dl/drivers/zombie_walk frames=12 start=0 end=1.5   # pass 53: a pose driver from a glTF clip (RIGS maps its bones to Mixamo names; start/end slice one stride)
python tools/pose_scale.py tools/dl/drivers/walk_sun_spread tools/dl/drivers/walk_sun_spread85 scale=0.85 views=back,bd   # pass 54: a pose driver with chosen views shrunk about the figure, so a wide-armed figure stays inside the clip
python tools/rekey_clip.py --id solenne [--keys a,b]   # pass 54: key cached clips again with the item JSON's key settings (key_sat, key_min_value, key_cut_shadow, key_clamp_screen); only clean when the first keying cut nothing it should have kept, else paint the clips again
"$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/catwalk_walking.fbx out=tools/dl/drivers/catwalk frames=24 pitch=25 fwd=body   # pass 55: fwd=body squares the views to the hips and shoulders (the feet had turned Walking_sun's 20 degrees)
python tools/pose_fit.py tools/dl/drivers/catwalk tools/dl/drivers/catwalk_fit tools/pose_templates/solenne.json   # pass 55: the stick figure scaled to the painted body, the face pinned on the painted head (facing the viewer), smaller hands; then pose_spread for the back views
python tools/gen_art.py --only solenne --variant=SOL-C --skip-qa --no-import   # pass 55: a hero's art variant (recipe: still_keys, pose_drivers, pose_motion, run_fps) -> <id>_sprite_<letter>.png + variants[code]; then lossy_imports, --import, import_json
python tools/set_knockback.py   # pass 54: writes each creature's and boss's contact `knockback` (EnemyDef.default_knockback from its damage) into its JSON where it has none
"$BLENDER" -b --python tools/blender_scepter.py   # pass 54: the Sun Scepter and Zenith GLBs (Staff, Sun, Charge, Glint, SunGlow) + their icon renders tools/dl/sun_scepter_ref.png, zenith_ref.png
"$BLENDER" -b --python tools/blender_sign.py   # pass 54: art/props/sign.glb (Post + one Arm, its origin on the post's axis, pointing +X) for core/systems/SignField.gd
"$BLENDER" -b --python tools/blender_props.py -- only=tumbleweed_dark   # pass 54: one prop only (the dark-brown tumbleweed the weapon throws; the King's and the desert's keep tumbleweed.glb)
python tools/make_splash.py && python tools/make_kind_glyphs.py [--preview p.png]   # pass 54: the boot splash (art/ui/splash.png + splash_icon.png for Android) and the cards' corner glyphs (art/ui/wanted/kind_weapon.png: one solid revolver since pass 56; kind_line.png: the scroll)
python tools/make_solenne_static.py [--no-raw]   # pass 54: Solenne's title cut-out, round badge and raw front/back stills cut straight from Garry's turnaround picture (no painting)
python tools/recolour_strip.py --src <strip> --dst <strip> --mode tint --ranges 10-75 --to 222 --set-sat 0.55 --value 0.6 --min-val 0.3   # pass 54: a pale material made dark and saturated frame by frame (the dark-blue SK-E / KN-E looks; artkit.tint_range)
"$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/walking_sun.fbx out=tools/dl/drivers/walk_sun frames=24 pitch=25 && python tools/pose_spread.py tools/dl/drivers/walk_sun tools/dl/drivers/walk_sun_spread   # pass 54: Solenne's walk (Garry's Walking_sun.fbx), the spread copy for the back views
python tools/posthog_boards.py [--check]   # pass 59/60: (re)builds the eight PostHog dashboards from HogQL/Trends queries (personal phx_ key in tools/posthog_personal_key.txt, git-ignored; never in the game); a rerun keeps every board's id and replaces its tiles; every SQL tile gets PostHog's `{filters}` placeholder (`scoped()`), so a dashboard filter such as person property player_name reaches it (pass 62; how-tos for Garry's analytics questions live in analytics/howto/*.md)
# analytics/dashboard.html: open in a browser after a run played from the editor binary (runs land in analytics/runs/, latest.js + index.js); analytics/SCHEMA.md documents the record
"$GODOT" --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/wanted_shots.gd -- out=<dir> [only=title,hud,...] [white=1] [inset=130]   # every Wanted screen state as the handoff's PNGs show it (only=backdrop rewrites art/ui/wanted/menu_backdrop.jpg; inset=N shows the screens under a camera cutout)
python tools/wanted_compare.py <dir>/<state>.png <mock-name> [--diff] [--crop=x,y,w,h]   # a render beside its PNG in design_handoff_88fits_wanted/screens/
"$GODOT" --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/perf_late.gd -- build=six   # late-game benchmark: ms per system and draw calls (--fixed-fps 30 = a phone at 30)
"$GODOT" --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/screenshot_run.gd -- out=<dir>   # windowed, silent, ~60 PNGs for the bible (make_bible.py --shots=<dir>); without --resolution the window override gives 432x768
"$GODOT" --path D:/_projects/88fits/game -e                     # open the editor
JAVA_HOME=D:/_projects/88fits/tools/jdk17/jdk-17.0.20.1+1 "$GODOT" $P --export-debug "Android" export/88fits-debug.apk   # signed debug APK
bash tools/ship.sh [--quick] [--no-install]                       # checks -> signed APK -> install + launch on the phone (adb over USB or Wi-Fi)
bash tools/release.sh "note"                                      # upload the APK as the next GitHub release in the private builds repo (needs gh auth login once)
python tools/gen_textures.py && python tools/gen_music.py && python tools/paint_pass.py   # art + music regeneration (see docs/RUNNING.md)
python tools/make_pipeline_figs.py && python tools/make_bible.py   # bible section 15b's step-by-step art pictures (from tools/dl/ intermediates), then the bible
python tools/ai_sfx.py [--dry-run | --gen-only | --auto | --bind | --report | --docs | --only ids | --cands N | --pick id=k | --volume id=dB]   # pass 60: every sound effect from Stable Audio (Garry's app at http://127.0.0.1:7861/, AudioGen on 7860 as the alternate) -> content/sounds/real/<id>.wav + the soundmap rows; then --import + import_json -- only=sounds; python tools/make_sfx_review.py -> docs/sfx_review.html + tools/dl/sfx60/sfx_review.zip (the voice barks are gone; gen_voice.py lives in tools/dl/backup/)
python tools/icon_sand.py [--gamma 0.8] [--splash] [--compare out.png]   # pass 61: the launcher icon's sand a touch lighter (only the sand; the old source tools/dl/app_icon/icon_src_v046.png), then gen_art.app_icon and make_splash
"$GODOT" --audio-driver Dummy --fixed-fps 60 --resolution 504x1122 --path D:/_projects/88fits/game --script res://tools/_p61_pk_bench.gd   # pass 61: the pickups benchmark (N gems lying, the hero walking, a vacuum): ms a frame for "pickups", the whole frame, draw calls
"$GODOT" --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/difficulty_probe.gd -- t0=300 secs=130 stage=0 level=22 build=b1 mirror=0 hero=calavera seed=11   # pass 62: how hard a stretch of the run is for a fixed build and Mirror rank (0/3/6): HP lost a minute net of healing, per source, kills, the crowd against the cap
"$GODOT" --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p61_wp1_shot.gd -- out=<dir>   # pass 61: the gun mutations' looks without and with, around a shot (needs --fixed-fps)
"$GODOT" --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p60_wp_shot.gd -- out=<dir> [only=tommy,boomstick,chicago,blunderbuss,pod,scepter,pea]   # pass 60: every gun's rounds frame by frame, the pod at pressure 0/1, the sceptre with Flicker; _p60_pk_shot.gd -- out=<dir>: a field of gems and the magnet arc
python tools/gen_art.py [--anchor|--pick=N] [--only id] [--force] [--seed=N]   # Clash-style sprites/icons via Flux.2 Klein on ComfyUI (192.168.137.54:8188), vision QA, review sheets, imports at the end
python tools/comfy.py --export                                  # ComfyUI workflows as UI-loadable JSON in tools/comfy_workflows/
python tools/animate.py <still.png> "<motion in place>" [seed]   # one Wan 2.2 image-to-video run cycle -> tools/dl/ai_anim/<key>/ (see .claude/skills/sprite-animation)
"$BLENDER" -b --python tools/blender_props.py -- out=D:/_projects/88fits/game/art/props     # 16 GLB props; BLENDER=%LOCALAPPDATA%/Programs/blender-5.2.0-windows-x64/blender.exe
"$BLENDER" -b --python tools/blender_hammer.py      # also blender_revolver.py, blender_gravity_gun.py, blender_tommy.py, blender_mouth.py: weapon GLBs + side renders on green (tools/dl/*_ref.png) the icons are painted from
```

Do the parse check and the smoke run after any change to `core/`, `player/`, `game/` or `ui/`. When a change is something the user should try, finish with `bash tools/ship.sh` (checks + signed APK + install on any phone adb can see) which also overwrites the build in Google Drive (`E:/My Drive/88fits builds/88fits.apk`, the route the user actually uses from the phone; `tools/release.sh` is the GitHub backup) and tell the user the build is in Drive: the user plays on the phone, often away from the PC, and steers this project from it, so every user-facing change ends in a build they can tap. The chat file card cannot carry the APK (30 MiB limit, the build is 63 MiB since pass 48). Headless runs print `SCRIPT ERROR:` with file:line on failure; exit code is non-zero.

## Godot 4.7 gotchas that bit this codebase

- `var x := expr` fails to parse when `expr` is Variant-typed. Common sources: untyped `for` variables over a plain `Array` (type them: `for w: WeaponDef in list`), and `max()/min()/clamp()` which return Variant (use `maxf/maxi/minf/mini/clampf`). Use `var x: Type = expr` when in doubt.
- `SceneTree` scripts run with `--script` are compiled **before autoloads exist**. In tools, never name an autoload (`Run`, `Save`, `Registry`, `Audio`, `Settings`) or a class that references one at compile time; fetch them with `root.get_node("Run")` and defer work to `process_frame` (see `tools/smoke_run.gd`).
- `queue_free()` does not shrink `get_child_count()` in the same frame; loops that wait on it hang.
- Pausing uses `get_tree().paused`; the UI CanvasLayer is `PROCESS_MODE_ALWAYS`. Systems also check `game.paused`.
- A Container resets each child's `rotation` and `scale` whenever it sorts. A turned or scaled piece inside one (an open row's chevron, a tilted seal) sits in a plain Control holder, or is set again in `sort_children`.
- `Font.get_height()` rounds ascent and descent up, so it runs a pixel taller than CSS `line-height: normal` (Chrome rounds each to nearest). Measure against the mocks with `W.normal_height()`.
- Godot front faces are **clockwise**. A SurfaceTool mesh wound counter-clockwise is silently back-face culled; the terrain rendered as the sky's lower half for hours before anyone noticed. Check winding first when a generated mesh "has no texture".

## Architecture

- **Autoloads** (`core/autoload/`): `Registry` scans `res://content/**` at boot (prefers `<id>.tres`, falls back to `<id>.json`), `Save` (one JSON file in `user://`), `Settings`, `Audio` (sound ids from the sound map, voice-limited, layered music), `Run` (state of the current run: XP, gold, weapons as `WeaponInstance`, passives, evolution logic, chest logic).
- **Data classes** (`core/data/`): `Effect` {stat, op add|mul|set, value, target} is the only way numbers change. `WeaponDef`, `PassiveDef`, `EnemyDef`, `EliteModDef`, `CharacterDef`, `ShopUpgradeDef`, `QuestDef`, `MapDef` + `WaveTimeline`, `SoundMap`. `JsonContent` converts JSON to these; `tools/import_json.gd` writes `.tres`.
- **Stats**: `StatSheet` = (base + Σadd) × Π(1+mul) with sources kept for the pause screen breakdown. `WeaponInstance.rebuild()` folds player multipliers (might, cooldown, area, amount, targeted passives) into each weapon's sheet. `TextGen` generates every card, pause and collection description from data.
- **Game scene** (`game/Game.gd`): wires map, player, camera, `EnemyManager` (packed arrays + one MultiMesh per enemy type, camera-facing billboard shader in `core/shaders/`), `ProjectileManager`, `PickupManager` (gems/coins MultiMeshes, a growable pool, a grid of lying pickups, magnet and vacuum, chests), `Telegraphs`, `Fx`, `WaveDirector` (live cap, roster, events, boss, portal, stage clock), weapon behaviours (`core/behaviors/`: ProjectileEmitter, Orbiter, Lobber, Beam, LaserBeam, Thruster, Smasher, ConeWave, GravityGun, MissilePod, MineLayer, SunScepter, Spawner+Turret) and the in-run UI (`ui/HUD`, `CardScreen`, `PauseScreen`, `PortalDialog`, `Hints`, `DebugPanel`).
- **Content folders**: `content/<type>/<id>/` holds `<id>.json` (authoring source), `<id>.tres` (generated, Inspector-editable), optional `<id>_visual.tscn` (weapon meshes/particles: nodes named `Projectile`, `Held`, `Muzzle`), `<id>_icon.png`, `<id>_sprite.png` (animation strip in the fixed order idle, run, attack, hit, die / characters add turn, cheer). `content/sounds/soundmap.json` binds sound ids.
- **Map**: `world/MapBase.gd` provides `height_at`, obstacle circles, flats centre; `world/maps/red_canyon/RedCanyon.gd` builds Red Canyon (Dry Gulch is shelved in `tools/dl/backup/`).
- **UI kit** (`ui/wanted/`, pass 39, the Wanted design): every screen is built in code from one set of components (`W` tokens and fonts, `HardBox`, `WText`, `WTap`, `WButton`, `WPlate`, `WSeal`, `WMarks`, `WCard`/`WItem`, `WModal`, `WMenuHeader`, `WTabs`, `WSlider`, `WSwitch`, `WChoice`, `WRow`, `WPlaceholder`, `WToasts`, `WBanner`, `WPointer`, `WBar`, `WCelebrate`, `WConfirm`); no screen draws its own version of a component. The old `UiKit` remains in the arena panel, the debug hand and the in-run debug panel, for `WItem`'s card text, and as the colour names `Game.gd` hands to toasts (`WToasts.tone` maps them to green, purple or paper).
- **Hub screens** (`ui/`): `TitleScreen` (with play setup), `CollectionScreen`, `HomesteadScreen` (the Upgrade board, "the Mirror" in code), `ResultsScreen`, `SettingsScreen` extend `ScreenBase`; `DevMenu` (held version line in Settings) stands alone.
- **Editor plugin** `addons/content_dock/`: lists content, warns on missing files, "New from template", JSON→.tres, and test-launch (writes `user://debug_launch.json`, which `Game.gd` reads for a tool's start: hero, weapon, map seed, no spawn beam).

## Adding content (no code)

Copy a folder under `content/<type>/`, rename the folder and the `id` in the JSON, edit numbers, run `import_json.gd` (or press "JSON → .tres" in the Content dock). The Registry finds it on the next run; cards, pause text, collection and HUD icons follow automatically. Add a sound by adding a row to `soundmap.json` and running `gen_sfx.py`.


## Planning Mode: Mandatory User Interview

Whenever Plan Mode is active, DO NOT immediately produce a final implementation plan.

Before producing the plan, you MUST complete a user interview.

### Phase 1: Investigate First

First inspect the relevant code, files, documentation, existing systems, and project structure.

Do not ask the user questions that can be answered by inspecting the project yourself.

### Phase 2: Clarification Questions

After investigating, ask me AT LEAST 5 clarification questions.

These questions must specifically target ambiguity, uncertainty, missing requirements, conflicting requirements, assumptions, edge cases, or decisions that materially affect the implementation.

Prioritize questions about:

1. Requirements or behavior that could reasonably be interpreted in multiple ways.
2. Scope boundaries: what should and should not be changed.
3. Expected behavior in edge cases.
4. Constraints, dependencies, or compatibility requirements.
5. Assumptions you would otherwise have to make.

If you believe something is ambiguous or you are not confident you understood my intent, you MUST ask about it rather than silently choosing an interpretation.

Do not ask filler questions merely to reach the required count. If fewer than five obvious ambiguities exist, identify potentially important assumptions or design decisions that should be confirmed.

### Phase 3: Game Design Questions

In addition to the clarification questions, ask me AT LEAST 3 questions specifically from a GAME DESIGN perspective.

These are separate from implementation questions.

Game-design questions should investigate areas such as:

- Intended player experience
- Player motivation
- Difficulty or challenge
- Progression
- Rewards
- Economy and resource flows
- Sources and sinks
- Balance
- Pacing
- Failure states
- Risk versus reward
- Player choice
- Meta progression
- Retention or replayability
- Exploitability / degenerate strategies
- How the feature interacts with existing game systems

Do NOT count technical questions as game-design questions.

For example, "Should this be implemented as a ScriptableObject?" is NOT a game-design question.

"Should players be able to intentionally lose this encounter to preserve resources?" IS a game-design question.

### Phase 4: Question Format

Ask all initial questions together in one response.

Use this structure:

**Clarification**

1. ...
2. ...
3. ...
4. ...
5. ...

**Game Design**
6. ...
7. ...
8. ...

You may ask more than 8 questions when genuinely necessary.

Questions should be concrete and specific to the task. Avoid generic questions such as:

- "Anything else?"
- "What are your preferences?"
- "Do you have any other requirements?"

Whenever possible, explain briefly WHY a question matters when the consequences are not obvious.

### Phase 5: STOP

After asking the questions, STOP.

DO NOT:

- produce the final plan
- begin implementation
- exit Plan Mode
- make assumptions in place of unanswered questions

Wait for my answers.

### Phase 6: Follow-up

After I answer, evaluate whether any important ambiguity remains.

If something important is still unclear, ask focused follow-up questions before planning.

Do not repeat questions I have already answered.

### Phase 7: Produce the Plan

Only once the requirements and game-design intent are sufficiently understood should you produce the implementation plan.

The plan must incorporate the answers I gave during the interview.

If the implementation plan requires making an assumption that I did not explicitly approve, identify that assumption in the plan rather than silently introducing it.

## Status (2026-10-11, pass 66, version 0.52)

What is true now, in short. The why and the detail of every pass (1 to 65) is in **`docs/HISTORY.md`**: search it for a
symbol, file or pass number when you need background (`grep -n "PickupManager" docs/HISTORY.md`); do not read it whole.
After each pass: append the pass's paragraph to `docs/HISTORY.md`, and update this section only where what is true
changed.

**Shipping.** `bash tools/ship.sh` -> signed release APK -> `E:/My Drive/88fits builds/88fits.apk`, then a PC build (the "Windows Desktop" preset, one `88fits.exe` with the game embedded) -> `E:/My Drive/88fits builds/88fits.exe` (`--no-pc` skips it; iOS was looked at and dropped: it needs a $99 Apple developer account) (Garry plays on the
phone, often away from the PC; see `docs/RUNNING.md` and the ship-to-phone skill). ship.sh runs import, import_json, the
parse check, all gdUnit tests (~1,310 in `game/tests/passNN_*_test.gd`), smoke_run, arena_check and touch_audit. Also run
`hell_check.gd` after stage-3 changes. Version in `application/config/version` (0.52).

**The game.** One map, **Red Canyon** (`world/maps/red_canyon/RedCanyon.gd`): noise terrain, one dry river and an oasis
rolled per run from `Run.map_seed`, a stone boundary wall; everything but the ground, the wall, barrels, signs and a few
movers is a painted 2.5D billboard (props `art/sprites/props/`, structures `st_<id>.png`). Three stages of 430 s (bosses
Tumbleweed King 7:10, Gila Grande 14:20, the Brander 21:30; Elites at 3:35 / 10:45 / 17:55; stage 3 is "hell": a red
ground and a hell channel of creatures on its own cap), then endless. The timeline (`content/maps/red_canyon/red_canyon.json`
`timeline_data`: cap curve, roster rows, waves, events, specials, HP/ATK curves, scaling) is **Garry's to edit in the
Level Editor** (`tools\level_editor.cmd`, `docs/level_editor.md`, schema `docs/waves_schema.md`; since pass 66 the same
page also creates and edits enemies, heroes and items and queues their art for the local AI: the Enemies / Heroes / Items
/ Jobs tabs, `docs/level_editor.md` "Pass 66", keys in `docs/assets_schema.md`, rules in BALANCING.md §13); stage 1 is his own
work (pinned by `pass62_pc_test`), stages 2-3 were written in his style in pass 62 and tuned in pass 64 so stage 2 is clearable with a quarter of the Upgrade board and stage 3 with half (`tools/difficulty_probe.gd`). Enemy strength = base x
`stage_mults` [1, 2.2, 3.34] x the HP/ATK curve at the row's start x (1 + level_*_per_level x (hero level - 1)) x
`creature_*_mult`, fixed per row from its start.

**Heroes** (playable, title order): Drifter (Revolver), Astro (Gravity Gun), Calavera (Guitarra), Ironwood (the Spear =
`pike`), Solenne (Sun Scepter); Buck, Dad and Mira are `hidden`. Each hero's trait is 1-2 stats that grow per level
(`trait_per_level`, `Run.hero_sheet`), a favourite weapon or passive (arrives at a bonus level, marked on cards), perks,
and a hero mutation. The title plaque opens the hero's Wanted-poster sheet (`ui/wanted/WHeroSheet.gd`). Art variants
(`variants` / `variant` in the JSON; Garry picks them in the arena or in the Level Editor's look grid; a look may be
`shelved` out of the chips, a landed one is `fresh` until approved): see the art-variants memory. A hero JSON carries
`availability` (hidden | available | purchase: anything but available hides him), `price` and `currency_type` (gold),
written and shown by the editor, not wired (the purchase loop is parked: memory `88fits-hero-purchase-parked`).

**Items.** Weapons (5 slots, 5 levels; three path mutations each, offered at set slots `path_times`; all three + level 5
= evolution at a chest; hero mutations optional), lines (5 slots, 4 levels, evolve when maxed; `PassiveDef.line`) and
passive items (no cap). Everything is content: `content/weapons|evolutions|mutations|passives|perks|pickups|structures|
enemies|bosses|characters|talents|maps|sounds`. Mutation looks come from their `params` (`look`, `tint`, ...); emblems
are gone. Pierce drop-off is on by default (`Settings.pierce_falloff`, Debug panel). Numbers and rules: `BALANCING.md`.
A weapon the editor creates starts hidden with three template path mutations and a template evolution, all hidden,
until they are filled; a new line or passive item starts available; "locked" is a quest whose `unlocks.id` names it
(the Items tab's availability op writes the quest). The count pins in the tests are shape rules now
(`pass66_shape_test.gd`: every weapon in play has its three path kinds and its evolution, every creature a doc, a blood
and a knockback, every playable hero a perk and one hero mutation).

**Meta.** The **Upgrade board** (`ui/HomesteadScreen.gd`, still "the Mirror" in code; `content/talents`): eight talents,
two forms, six ranks; every rank is bought in one form and keeps it (`Save.talent_picks`); Take it all back refunds half.
Gold: extraction banks the purse, a death leaves it in the sand, the Strongbox banks mid-run (a new one drifts down 30-60 s after one is used). Unlock quests gate half the
items; the Collection shows only what was met.

**UI.** The Wanted kit (`ui/wanted/`, see Architecture); one paused screen at a time with death winning
(`Game._request_modal`); the camera cutout is respected everywhere (`W.safe_top()`); touch is raw ScreenTouch, never
mouse emulation (`TouchScroll`, `TouchSlider`); prove UI with `touch_audit.gd`. The developer menu (hold the Settings
version line 2 s) and the player's debug mode (10 taps on the hints switch) hold the test switches; the debug arena is on
the title in debug mode.

**Analytics.** `core/autoload/Analytics.gd` -> PostHog EU (write-only `phc_` key in `game/config/analytics.json`; the
personal `phx_` key only in git-ignored `tools/posthog_personal_key.txt`, never in the game or a commit; Garry's email is
never sent anywhere). Consent card first, persons named by `Save.player_name()`, `run_summary` per-minute curves, gold
sources/sinks, surveys from PostHog Surveys with `[after N]` / `[run N]` name tags. Boards: `python tools/posthog_boards.py
[--check]` (nine boards, ids kept on a rerun, SQL tiles follow dashboard filters). How-tos for Garry: `analytics/howto/`.
Plan: `docs/analytics_plan.html` (artifact AK53A8KLchrSUFXxZo4kSu). Local runs: `analytics/dashboard.html`.

**Art and sound pipelines.** Flux.2 Klein / dev stills + Wan 2.2 clips on ComfyUI 192.168.137.54:8188 (skills
sprite-pipeline, sprite-animation; heroes walk on Mixamo pose drivers fitted to the painting; creatures on Blender
control videos via `gen_ctl.py`); paint several seeds and pick by eye, the vision QA misses defects. Icons:
`tools/gen_icon_cands.py` sets. Since pass 66 Garry queues all of it himself from the Level Editor's job form
(`tools/level_editor/methods.json` is the catalogue of 17 methods with their recipe fields, timings and weaknesses;
`tools/level_editor/jobs.py` runs each job as a subprocess through `tools/asset_job.py`; with `ASSET_JOB_SIDECAR` set,
gen_art.py / gen_ctl.py write `result.json` instead of the content JSON and the server merges the look's entry in place;
`tools/blender_ref.py` probes and renders any FBX/GLB/OBJ for the icon and look references, `tools/blender_depth_drivers.py`
turns a rigged model's own clip into depth drivers, `pose_driver.py src= rigmap= probe=` the Mixamo-style ones; new badge
candidates by `tools/gen_badge_cands.py`). One ComfyUI job at a time: `tools/locks.py` (comfy.py takes the lock itself).
Sound: Stable Audio 3 medium on the server's ComfyUI (`tools/comfy_audio.py`; UI and reward jingles in a casino-western `HYPE` table in `tools/ai_sfx.py`, music by `tools/ai_music.py` into `content/sounds/music/`; world sounds from pass 60; the gem dings, the hero's hurt and the slot machine are synthesised by `tools/synth_sfx.py`; Garry's own Stable Audio app at http://127.0.0.1:7861/ is the second engine; skill sound-pipeline). `Audio.gd` plays one music track at a time (`music_stage`, `music_boss`).
Blender models from Garry's references in `_REFERENCES/` (git-ignored).

**Docs.** The design bible is built from `docs/design/src/` by `python tools/make_bible.py` (edit the parts, not the
output) and published at https://claude.ai/artifact/2onXrvqpGH3uqwPEstVYhr; `BALANCING.md` (where every number lives);
`docs/HISTORY.md` (every pass).

**Working rules learnt the hard way** (details in HISTORY.md's lessons and the memory):
- Garry hand-tunes JSON (and the map in the Level Editor) while passes run: keep his numbers, re-pin tests; map tests read
  the map file rather than pinning his numbers.
- Parallel lanes work from brief files with a status file each, never commit, edit shared files with small edits only,
  keep LF line endings, and run every Godot command through `bash tools/godot.sh` (pass 66: the repo-wide lock
  `tools/dl/locks/godot.lock` that the Level Editor's server shares, the PC save kept aside; wait for it however long;
  never run the binary directly; two gdUnit runs at once share `user://test_saves`). One ComfyUI job at a time through
  `tools/dl/locks/comfy.lock` (`tools/locks.py`; comfy.py takes it for the whole process; a child told
  `LOCK_HELD_COMFY=1` passes through; a shell that holds a lock across several commands names itself:
  `python tools/locks.py acquire comfy "<who>" --pid $(cat /proc/$$/winpid)` ... `release comfy --pid $(cat /proc/$$/winpid)`,
  since the parent a Python sees under Git Bash is a transient fork).
- Tools and captures must not change the PC's `user://save.json` (smoke_run plays Astro on the real save: copy it aside
  around tool runs; use `Save.begin_sandbox()` in probes).
- Rules Garry never asked for read as bugs: name every new rule in BALANCING.md.
- Commit every finished pass (never push); the build goes to Drive at the end of every user-facing change.

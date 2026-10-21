# Running 88fits

## Setup on a new PC (pass 97)

1. Clone the repo; unzip Godot 4.7.2 (win64) into `Godot_v4.7.2-stable_win64\` at its root and a JDK 17 into
   `tools\jdk17\` (both git-ignored); Blender 5.2 into `%LOCALAPPDATA%\Programs\`; Node.js LTS (the Level Editor's
   selftest); Python 3.10 with "Add python.exe to PATH".
2. `python -m pip install -r tools/requirements.txt` (numpy, Pillow, scipy are what the art tools need; the rest are the
   sound tools', the exe check's and ComfyUI's live progress lines).
3. Copy the secrets by hand into `tools\keys\` (`tools/keys/README.md` lists them) and the AI server's key to
   `~\.ssh\id_ed25519_ai_server`; the AI hosts are in `tools/ai_hosts.json`.
4. `python tools/doctor.py`: it changes nothing and ends `essentials ok`, or names each missing piece with the line that
   fixes it (exit 1). `python tools/net_check.py` lists what on the PC listens beyond itself (read-only too).

## On this PC (Godot editor)

1. Run `Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe`, click **Import**, pick `game\project.godot`.
2. Press **F5**. The window opens at phone aspect (432×768). Mouse acts as the thumb: click and hold in the lower part of the screen to run, drag left/right to steer, release to stop.
3. **Esc** pauses. **F1** toggles the debug panel (spawn waves, level up, god mode, give weapons, skip time).
4. The **Content** dock (bottom-left in the editor) lists every weapon, passive, enemy, character, shop upgrade, quest and map. Double-click opens the item's `.tres` in the Inspector. **New from template** duplicates an item. The play button next to an item launches the game with it equipped.

## Editing content without code

Every item is a folder under `game/content/<type>/<id>/`:

| File | What |
|---|---|
| `<id>.json` | the authoring source: numbers, level table, targeting, pairing, sounds |
| `<id>.tres` | the same thing as a Godot resource, editable in the Inspector (regenerate from JSON with the dock button or `tools/import_json.gd`) |
| `<id>_visual.tscn` | weapons only: the 3D mesh and particles (`Projectile`, `Held`, `Muzzle` nodes) |
| `<id>_icon.png`, `<id>_sprite.png` | placeholder art; replace the files, keep the names |

Controls are a floating joystick: touch anywhere below the top bar and drag, lift to stop; every weapon fires by itself. Camera mode (Fixed north-up, the default, or Follow behind the hero), joystick size, volumes and hints live in **Settings** (title screen) and in the pause screen.

## On the phone

Everything needed is installed on this PC: Godot 4.7.2 export templates, a portable JDK 17 in `tools/jdk17/`, Android build-tools 34 in the SDK. Godot's editor settings already point at them.

```
set JAVA_HOME=D:\_projects\88fits\tools\jdk17\jdk-17.0.20.1+1
Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe --headless --path game --export-debug "Android" game\export\88fits-debug.apk
%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe install -r game\export\88fits-debug.apk
```

The debug APK is signed with Godot's debug certificate and verified with `apksigner verify`. Plug the phone in with USB debugging on, run the `adb install` line, open **88fits**. The export preset (`game/export_presets.cfg`) is portrait, arm64, immersive.

## Regenerating the art and sound

```
python tools/gen_textures.py                                   # sand, cracked earth, sandstone, sky panorama
"<blender.exe>" -b --python tools/blender_props.py -- out=D:/_projects/88fits/game/art/props   # 16 GLB props
python tools/gen_music.py                                      # music loops and stems
python tools/gen_sfx.py                                        # placeholder effects (skips existing files)
python tools/ai_sfx.py --report                                # pass 60: every sound effect comes from Stable Audio (tools/ai_sfx.py; the voice barks are gone, gen_voice.py lives in tools/dl/backup/)
"<godot>" --headless --path game --script res://tools/gen_placeholders.gd -- force   # flat sprite strips + icons
python tools/paint_pass.py                                     # shading, brush dabs, outlines on procedural sprites and icons
python tools/gen_art.py --anchor && python tools/gen_art.py --pick=N   # paint style-anchor candidates, install one (tools/dl/review/anchor_candidates.png)
python tools/gen_art.py [--only goblin,knight] [--force] [--seed=N]   # Clash-style sprites + icons via Flux.2 Klein on the ComfyUI server, vision-checked, then imported
python tools/comfy.py --export                                        # write the ComfyUI workflows to tools/comfy_workflows/ (open them in the ComfyUI UI)
python tools/animate.py tools/dl/ai_raw_anime/drifter_side.png "running in place, side profile" 1   # one video-made run cycle for review (tools/dl/ai_anim/)
"<godot>" --headless --path game --import
```

Blender is at `%LOCALAPPDATA%\Programs\blender-5.2.0-windows-x64\blender.exe`. To hand-paint a sprite, drop a strip with the same frame order over `<id>_sprite.png` and re-run `--import`; nothing else changes.

## Play on the phone after every change

The goal of every change is a build you can tap on the phone within minutes. Three ways, best first.

**One-time setup on the phone (Android)**
1. Settings → About phone → tap *Build number* seven times to unlock Developer options.
2. Developer options → turn on **USB debugging** and **Wireless debugging**.
3. The first build has to be installed once by hand: plug the phone in over USB, accept the "Allow USB debugging" prompt, then run `bash tools/ship.sh`, or use way 2 below.
4. If a build came from the browser, allow "Install unknown apps" for that browser when Android asks. Builds are signed with the project keystore in `tools/keys/` (git-ignored, back it up), so every later build updates in place. The old `88fits-debug.apk` was signed differently: uninstall it once.

**Way 1 · adb over Wi-Fi: zero taps.** Phone and PC on the same network (the PC's own hotspot counts).
1. Phone: Developer options → Wireless debugging → *Pair device with pairing code*. It shows an address, a port and a six-digit code.
2. PC, once: `adb pair <address:port>` then type the code, then `adb connect <address:port-shown-on-the-main-wireless-debugging-screen>` (`adb` is `%LOCALAPPDATA%\Android\Sdk\platform-toolsdb.exe`).
3. From then on `bash tools/ship.sh` runs the checks, exports the signed build, installs it and launches it on the phone. `--quick` skips the tests and smoke run.
   The connection survives until the phone or PC sleeps; `adb connect` again brings it back.

**Way 2 · download from the PC.** `bash tools/serve_apk.sh` prints an address like `http://192.168.137.1:8088/88fits.apk`; open it in the phone's browser, download, tap to install. Works on the hotspot or any shared Wi-Fi, no adb needed.

**Way 3 · from anywhere: Google Drive (the vacation route, in use).** Google Drive for Desktop is signed in on the PC and mounted as `E:`. Every `tools/ship.sh` run overwrites `My Drive/88fits builds/88fits.apk`; Drive syncs it and keeps the previous versions for 30 days.
On the phone: Google Drive app → My Drive → 88fits builds → 88fits.apk → download → open → install (allow installs from Drive/Files once). Same signature every time, so it updates in place.
Backup route, also from anywhere: GitHub Releases through `tools/release.sh` (needs a one-time `tools/dl/gh/bin/gh.exe auth login --web` with a device code typed on the phone).

**The loop when steering from the phone:** ask for a change → I make it, run `tools/ship.sh` (parse check, tests, smoke run, export, signature, install+launch if the phone is on adb) and tell you the build is ready → you open 88fits on the phone. If adb is not connected I say so and give the download address instead.

## The Level Editor and the two .cmd files (pass 53)
- `tools\level_editor.cmd` (double-click): a local page for the wave timeline of every map (Timeline, Settings,
  Creatures, Instructions). Save writes the map JSON, keeps a backup under `tools/level_editor/backups/` and runs the
  JSON -> .tres import; commit the JSON. The schema is `docs/waves_schema.md`, the guide `docs/level_editor.md`.
- `tools\ship.cmd [--quick] [--no-install]` (double-click): `tools/ship.sh` through Git Bash: the checks, the signed
  APK, the phone over adb when one is plugged in, and the copy into Google Drive (`My Drive/88fits builds`).
- Any JSON you edit by hand reaches the game only after `"$GODOT" --headless --path game --script
  res://tools/import_json.gd -- only=<kind>/<id>` (the editor binary and the APK read the generated `.tres`).

## The save file (pass 45)

The save is `user://save.json` with `save.json.bak` beside it: every write goes to `save.json.tmp`, the old file steps back to `.bak`, the tmp steps into place, so at every moment one whole file exists. A file that cannot be read is kept as `save.json.corrupt-<unix>` and the backup (or the tmp) loads instead. Versions migrate forward only (`Save.VERSION`; a newer file is loaded as it is). Writes are debounced (400 ms for a menu change, 8 s for in-run tallies) and flushed when the app goes to the background or quits; the debug arena is a sandbox (`Save.begin_sandbox/end_sandbox`) that never reaches the disk. Settings shows "saved N min ago" over the version line, the developer menu shows what the boot read, the last write and whether a backup exists. `tests/save_test.gd` covers it; the gdUnit runner saves under `user://test_saves`, never the PC's own save. The Android export keeps the data on an uninstall prompt (`retain_data_on_uninstall`) and lets Google back it up (`user_data_backup/allow`); `tools/ship.sh` refuses a debug-keystore build without `--debug-key`, since a differently signed APK cannot update the installed one and an uninstall would delete the save.

## Two maps, four heroes, pickups (pass 9)

- Map: `red_canyon` (desert, nothing in 3D but ground and mountains; pass 21). Dry Gulch (pass 21) and the meadow (pass 17) were shelved; its content, scene, art, sounds and texture tool sit in `tools/dl/backup/mossy_hollow/` (and in the first git commit). The timeline JSON schedules pickups (`pickups` block), structures (`structures` block: nine, every kind at least once), the Elite (`elite_boss` events at 150/450/750 s) and the harder stages (`stage_mults`, `cap_per_stage`, `speed_per_stage`).
- Heroes: Drifter (the default on a clean save since pass 53; Astro was from 2026-09-14), Astro, Calavera, Ironwood, Solenne (pass 54); Dad, Buck and Mira are `hidden`. Creatures and heroes are rendered by `python tools/gen_art.py --only=roadrunner,...` (without `--force` cached renders and clips are reused, so a repack after a pipeline change takes seconds); fps: `smoke_run.gd -- seconds=60 perf=1` prints per-system frame costs; run cycles are 24 frames for heroes and 12 for creatures, packed as grid strips (`strip_cols` in the JSON). A hero's run cycles are pose-driven (Wan Animate on the Mixamo stride in `tools/dl/drivers/run/<view>`) and cached in `tools/dl/ai_anim/<id>_pose_run_<view>/`: to re-roll one, delete that folder, bump `anim_seed` in the hero JSON and run `gen_art.py --only <id>` again (stills stay cached). The video frames go on whichever screen colour the figure is furthest from (`animate._screen_for`: blue denim goes on green), because the video model paints clothes more saturated than the still and Mira came back with no legs on blue; the view is spelled out in every cycle prompt and the back views carry face words in the negative, because a back cycle once came back with a face on it. Look at the raw `out_NN.png` frames of every view before trusting the packed sheet: the QA only checks that the figure stayed in frame (plus, for the back views, that a middle frame does not face the viewer). Two per-hero JSON fields exist for a garment that shares the screen's hue: `key_sat` (how saturated a screen-hued pixel must be to count as screen, default 0.35; Mira's front denim needed 0.6 or her overalls were keyed out) and `grade` ({hue: [lo, hi], sat_mul, sat_range, sat_max[, hue_shift, grey]}, `artkit.grade`), applied to the keyed figure of every still and frame so a grey-blue garment becomes one colour everywhere and the video model stops repainting it in the screen colour. Four more for a glossy figure that reflects the screen (pass 54, Solenne's black latex): `key_sat` 0.85, `key_min_value` (a screen-hued pixel darker than this is figure), `key_cut_shadow` false and `key_clamp_screen` true (the screen's channel held down to the other two in every figure pixel); a driver whose wide arms leave the clip's frame is shrunk with `tools/pose_scale.py`. A hero can carry art variants (pass 55: Solenne's SOL-A..D walks, `variants` + `variant` in her JSON, `gen_art.py --only solenne --variant=SOL-C`); the arena's HERO tab shows each on the hero and "USE ... FROM NOW ON" keeps one for every run (`Save.hero_look`). Her B, C and D walks run on drivers fitted to her painting (`tools/pose_fit.py` with `tools/pose_templates/solenne.json`, after `pose_driver.py ... fwd=body`).
- Test a hero headless: `--script res://tools/smoke_run.gd -- seconds=90 character=astro`; captures: `--script res://tools/screenshot_run.gd -- out=<dir> character=astro` (also captures the chest reel, the Elite with spit trails, and the boss pointer).
- Homestead models and the chest: `"$BLENDER" -b --python tools/blender_meta.py` writes `game/art/props/meta/*.glb`; `"$BLENDER" -b --python tools/blender_preview.py` renders them all to `tools/dl/review/meta_models.png` for a look.
- Tommy Gun: `"$BLENDER" -b --python tools/blender_tommy.py` rebuilds `game/art/props/tommy_gun.glb` + `chicago_typewriter.glb` and the side reference `tools/dl/tommy_ref.png`; `python tools/gen_tommy_icon.py` then paints both icons from that reference on Flux.2 dev.
- Pass 35 weapons: `"$BLENDER" -b --python tools/blender_hammer.py` (hammer.glb, earthshaker.glb), `tools/blender_revolver.py` (revolver.glb, golden_revolver.glb, from `tools/dl/revolver_ref/source/low_poly_revolver.blend`), `tools/blender_gravity_gun.py` (gravity_gun.glb, singularity.glb); each writes a side render on green to `tools/dl/<name>_ref.png`, which the icons were painted from (Klein, the render as the reference, several seeds, picked by eye). Run `--import` after a re-export: a GLB change is not seen until then.
- Fire ant packing: a variant recipe's `"directions": 2` makes `python tools/gen_ant.py --variant=ANT-X` walk and pack the front and back only (ANT-A, pass 35); without it the five views give eight directions. Clips and paintings are cached, so a re-pack costs no server time.
- Dune Scorpion variants (pass 46): `"$BLENDER" -b --python tools/blender_scorpion.py -- out=tools/dl/drivers/scorpion_walk frames=12 cycles=2` walks Garry's rigged scorpion (`_REFERENCES/3d/scorpion.zip`) and writes depth videos + clay for five views; `python tools/gen_ctl.py --id=dune_scorpion --variant=SC-A --dev` paints three side candidates on Flux.2 dev (about 8 min each; review `tools/dl/review/dune_scorpion_sca_side_cands.png`), then `--use-side=kN` paints the other views on Klein, walks them on Wan 2.2 Fun Control and packs `dune_scorpion_sprite_a.png`. The recipe (look, anatomy words, per-view camera words, outline) lives in the variant entry of `dune_scorpion.json`. A Klein view that comes out wrong (SC-B's three-quarter front was a plain side view, its back had a loose sting) is painted again as candidates with `--view-cands=fd,back` and picked with `--use-view=fd:c0,back:c2`. The death is walked on the model too: `"$BLENDER" -b --python tools/blender_scorpion.py -- mode=death out=tools/dl/drivers/scorpion_death` (front view, 25 frames: a spasm, a roll onto its back, the legs curled in the air) and the recipe's `"death_drivers": "scorpion_death"` makes gen_ctl paint the front painting along it (`animate.oneshot_control`, 8 frames); a Klein "dead on its back" still came out as a live scorpion rearing up and the vision check passed it. Wan keeps the painting's scale, not the depth video's, so gen_ctl resizes each view's walk to its depth video's width (`model_scale`; the front walk was 23% wider than the back). Flux.2 dev renders go through `comfy.run_dev` (a fresh ComfyUI process each, one retry after a timeout): the third dev render in one process sat 30 minutes loading into a full RAM and blocked the queue.
- Models from Garry's references (pass 46): `blender_guitar.py` imports the cartoon guitar (decimated, upright, Body/Strings/Soundhole), `blender_turret.py` builds our own turret in three stances (his reference is CC-BY-NC, so none of its mesh is used), `blender_spear.py` the Spear and the War Lance; each writes a reference render in `tools/dl/` that `python tools/gen_icon_cands.py` paints icons from (`--seeds 4`, review sheets in `tools/dl/icons46/`, then `--pick id=n`; a subject with green in it is painted on the blue screen: `"screen": "blue"` in its job).
- Launcher icon: `python tools/gen_app_icon.py --seeds=3,7` renders candidates on Flux.2 dev into `tools/dl/app_icon/`, `--pick=<seed>` crops the painted frame and writes `game/icon*.png` (every later `gen_art.py` run keeps it, since `app_icon()` composes from `icon_src.png` when it exists).
- Scenery: `python tools/gen_props.py [--only=id,id] [--force] [--klein]` paints the 2.5D props and the structures (each with a spent `_off` version) into `game/art/sprites/props/` (manifest `props.json`) on Flux.2 dev, one render at a time with the models released in between (about 4 minutes each); `--klein` uses the small model. `python tools/gen_art.py --only <id> --force --dev` repaints one creature on dev. Never run two ComfyUI jobs at once: dev does not fit the server twice.
- Design bible: `python tools/make_bible.py --shots=<capture dir>` assembles `docs/design/design-bible.html` from `docs/design/src/part1-4.html` (prose), `bible.css`, `sounds.json` and the captures; it also rebuilds the cast, hero-cycle and icon sheets from the content folders.
- Structures: `content/structures/<id>/<id>.json` (effect, params, weight, colour, prop); each map's timeline has `structures: {count, min_spacing}`. Props come from `tools/blender_props.py`.
- Paths (pass 26): a mutation is `content/mutations/<id>/<id>.json` (`weapon`, `kind`, `element`, `text`, `vfx`, `effects`, `params`, optional `behavior`/`visual`), a line `content/lines/<id>/`, a perk `content/perks/<id>/` (`hero`, `special`, `params`); icons render like passives (`gen_art.py --only <id> --dev`). The bible's path tables come from the data (`make_bible.py`: `{{MUTATIONS}}`, `{{LINES}}`, `{{PERKS}}`).
- Homestead farm (pass 27): buildings produce (`produces`, `yield`), the market sells (`rates`); resource icons `content/resources/<id>/` render like passives; `blender_meta.py` also builds `well.glb` and `market.glb`.
- Map roll (pass 28): every run rolls Red Canyon's river, oasis and dunes from `Run.map_seed`; tools that need the same desert twice set `Run.forced_map_seed` (the capture tool writes `map_seed: 88` into `debug_launch.json`). New painted props go through `python tools/gen_props.py --only=<ids>` (dev model, one render at a time), then `--import`; `PROPS` holds the collider radius (0 = walk-through, the bushes).
- Crash hunting (pass 29): `smoke_run.gd -- seconds=100 boss=2 evolve=all weapon=tommy_gun` jumps to the second boss with every weapon evolved and mutated; count engine warnings in the log (`grep -c 'at: normalize'`), a storm of them is a phone freeze. The game writes `user://breadcrumb.txt` every second; Settings shows it as "Last run's last second", so a phone crash report can quote it.

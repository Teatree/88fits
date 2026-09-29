# Running 88fits

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
python tools/gen_voice.py                                      # goofy voice barks via the local Kokoro TTS (Pinokio, port 7860)
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

## Two maps, four heroes, pickups (pass 9)

- Map: `red_canyon` (desert, nothing in 3D but ground and mountains; pass 21). Dry Gulch (pass 21) and the meadow (pass 17) were shelved; its content, scene, art, sounds and texture tool sit in `tools/dl/backup/mossy_hollow/` (and in the first git commit). The timeline JSON schedules pickups (`pickups` block), structures (`structures` block: nine, every kind at least once), the Elite (`elite_boss` events at 150/450/750 s) and the harder stages (`stage_mults`, `cap_per_stage`, `speed_per_stage`).
- Heroes: Astro (default), Drifter, Dad. Creatures and heroes are rendered by `python tools/gen_art.py --only=roadrunner,...` (without `--force` cached renders and clips are reused, so a repack after a pipeline change takes seconds); fps: `smoke_run.gd -- seconds=60 perf=1` prints per-system frame costs; run cycles are 24 frames for heroes and 12 for creatures, packed as grid strips (`strip_cols` in the JSON). A hero's run cycles are pose-driven (Wan Animate on the Mixamo stride in `tools/dl/drivers/run/<view>`) and cached in `tools/dl/ai_anim/<id>_pose_run_<view>/`: to re-roll one, delete that folder, bump `anim_seed` in the hero JSON and run `gen_art.py --only <id>` again (stills stay cached). The video frames go on whichever screen colour the figure is furthest from (`animate._screen_for`: blue denim goes on green), because the video model paints clothes more saturated than the still and Mira came back with no legs on blue; the view is spelled out in every cycle prompt and the back views carry face words in the negative, because a back cycle once came back with a face on it. Look at the raw `out_NN.png` frames of every view before trusting the packed sheet: the QA only checks that the figure stayed in frame (plus, for the back views, that a middle frame does not face the viewer). Two per-hero JSON fields exist for a garment that shares the screen's hue: `key_sat` (how saturated a screen-hued pixel must be to count as screen, default 0.35; Mira's front denim needed 0.6 or her overalls were keyed out) and `grade` ({hue: [lo, hi], sat_mul, sat_range, sat_max[, hue_shift, grey]}, `artkit.grade`), applied to the keyed figure of every still and frame so a grey-blue garment becomes one colour everywhere and the video model stops repainting it in the screen colour.
- Test a hero headless: `--script res://tools/smoke_run.gd -- seconds=90 character=astro`; captures: `--script res://tools/screenshot_run.gd -- out=<dir> character=astro` (also captures the chest reel, the Elite with spit trails, and the boss pointer).
- Homestead models and the chest: `"$BLENDER" -b --python tools/blender_meta.py` writes `game/art/props/meta/*.glb`; `"$BLENDER" -b --python tools/blender_preview.py` renders them all to `tools/dl/review/meta_models.png` for a look.
- Tommy Gun: `"$BLENDER" -b --python tools/blender_tommy.py` rebuilds `game/art/props/tommy_gun.glb` + `chicago_typewriter.glb` and the side reference `tools/dl/tommy_ref.png`; `python tools/gen_tommy_icon.py` then paints both icons from that reference on Flux.2 dev.
- Pass 35 weapons: `"$BLENDER" -b --python tools/blender_hammer.py` (hammer.glb, earthshaker.glb), `tools/blender_revolver.py` (revolver.glb, golden_revolver.glb, from `tools/dl/revolver_ref/source/low_poly_revolver.blend`), `tools/blender_gravity_gun.py` (gravity_gun.glb, singularity.glb); each writes a side render on green to `tools/dl/<name>_ref.png`, which the icons were painted from (Klein, the render as the reference, several seeds, picked by eye). Run `--import` after a re-export: a GLB change is not seen until then.
- Fire ant packing: a variant recipe's `"directions": 2` makes `python tools/gen_ant.py --variant=ANT-X` walk and pack the front and back only (ANT-A, pass 35); without it the five views give eight directions. Clips and paintings are cached, so a re-pack costs no server time.
- Launcher icon: `python tools/gen_app_icon.py --seeds=3,7` renders candidates on Flux.2 dev into `tools/dl/app_icon/`, `--pick=<seed>` crops the painted frame and writes `game/icon*.png` (every later `gen_art.py` run keeps it, since `app_icon()` composes from `icon_src.png` when it exists).
- Scenery: `python tools/gen_props.py [--only=id,id] [--force] [--klein]` paints the 2.5D props and the structures (each with a spent `_off` version) into `game/art/sprites/props/` (manifest `props.json`) on Flux.2 dev, one render at a time with the models released in between (about 4 minutes each); `--klein` uses the small model. `python tools/gen_art.py --only <id> --force --dev` repaints one creature on dev. Never run two ComfyUI jobs at once: dev does not fit the server twice.
- Design bible: `python tools/make_bible.py --shots=<capture dir>` assembles `docs/design/design-bible.html` from `docs/design/src/part1-4.html` (prose), `bible.css`, `sounds.json` and the captures; it also rebuilds the cast, hero-cycle and icon sheets from the content folders.
- Structures: `content/structures/<id>/<id>.json` (effect, params, weight, colour, prop); each map's timeline has `structures: {count, min_spacing}`. Props come from `tools/blender_props.py`.
- Paths (pass 26): a mutation is `content/mutations/<id>/<id>.json` (`weapon`, `kind`, `element`, `text`, `vfx`, `effects`, `params`, optional `behavior`/`visual`), a line `content/lines/<id>/`, a perk `content/perks/<id>/` (`hero`, `special`, `params`); icons render like passives (`gen_art.py --only <id> --dev`). The bible's path tables come from the data (`make_bible.py`: `{{MUTATIONS}}`, `{{LINES}}`, `{{PERKS}}`).
- Homestead farm (pass 27): buildings produce (`produces`, `yield`), the market sells (`rates`); resource icons `content/resources/<id>/` render like passives; `blender_meta.py` also builds `well.glb` and `market.glb`.
- Map roll (pass 28): every run rolls Red Canyon's river, oasis and dunes from `Run.map_seed`; tools that need the same desert twice set `Run.forced_map_seed` (the capture tool writes `map_seed: 88` into `debug_launch.json`). New painted props go through `python tools/gen_props.py --only=<ids>` (dev model, one render at a time), then `--import`; `PROPS` holds the collider radius (0 = walk-through, the bushes).
- Crash hunting (pass 29): `smoke_run.gd -- seconds=100 boss=2 evolve=all weapon=tommy_gun` jumps to the second boss with every weapon evolved and mutated; count engine warnings in the log (`grep -c 'at: normalize'`), a storm of them is a phone freeze. The game writes `user://breadcrumb.txt` every second; Settings shows it as "Last run's last second", so a phone crash report can quote it.

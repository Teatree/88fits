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
python tools/gen_badge_cands.py --id <hero> --seeds 4 [--character "<who>"] [--prompt "<action>"] [--ref <picture>] [--variant CODE] [--tag T] && python tools/gen_badge_cands.py --id <hero> --pick k [--tag T] [--variant CODE] [--head-width f --top-pad f]   # pass 66/68: hero badge candidates (RAW/<id>_portrait_<tag>_c<k>.png, review/<id>_badge_cands.png; the reference is --ref, else the look's own front still), the pick written to <id>_icon.png + badge{}, or for a look <id>_icon_<letter>.png + variants[CODE].icon; gen_title_heroes.py takes the same --character/--ref/--variant/--tag plus --pose/--holds/--camera/--extra-ref/--extra-words
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
"$BLENDER" -b --python tools/blender_basketball.py   # pass 67: Fadeaway's basketball (art/props/basketball.glb, vertex colours: its visual gives the mesh a material that reads them) + the icon reference tools/dl/basketball_ref.png
python tools/pose_shoulders.py tools/dl/drivers/run tools/dl/drivers/run_lvl [level=1 keep_tilt=1 tuck=25 views=side,fd]   # pass 69: a pose driver with the shoulders levelled up to the neck (Mixamo's Neck bone sits above the shoulder line: sagging backs, raised side shoulders), keep_tilt keeps the near shoulder lower, tuck lowers the far arm in the side view's passing frames; pose_driver.py gained amp= lean= arms=back (sprint, dash)
python tools/puppet.py may [--stage apose|shape|rig|anim|guides|looks|compare] [--from-blend] [--from-fbx <file>]   # the Puppet trial (2026-10-13): May painted arms-out, Hunyuan3D 2 multi-view on the AI server (built-in ComfyUI nodes, weights in models/checkpoints; its license excludes the EU, Garry accepted the risk), rigged in Blender with Mixamo names (tools/puppet_blender.py), running.fbx retargeted -> tools/dl/puppet/may/may_puppet.glb/.blend, guides tools/dl/drivers/may_puppet_run (+ _depth), looks MAY-P (stick figures) and MAY-Q (depth, gen_art recipe `ctl_drivers`); RIG_HOWTO.md for hand edits
"$BLENDER" -b --python tools/blender_salt.py   # pass 69: art/props/salt_shaker.glb (Body, Contents that a mutation tints, Cap, Holes, Spout) + the icon references tools/dl/salt_ref.png, sea_salt_ref.png, hiwa_kai_ref.png
"$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/walking.fbx out=tools/dl/drivers/walk_hold frames=12 arms=hold_r   # a walk whose right hand holds something up at the shoulder (the Vulture Raider's launcher, pass 48)
python tools/compress_levels.py [--check]   # pass 48: weapons from 8 levels to 5 (level 5 = the old level 8); --check re-verifies against tools/dl/levels_v47.json
python tools/sim_batch.py --out <dir> --hero drifter --players 10 --workers 0 --limit 1500 --death end --seed 1   # pass 77: the run sim the Level Editor's Sim tab runs (a snapshot of game/ in tools/dl/sim/snap with its own user folder 88fits_sim, players K at a time, under tools/dl/locks/sim.lock, never the godot lock); one player: game/tools/sim_run.gd (args in docs/assets_schema.md "Pass 77")
python tools/migrate_timeline.py --map red_canyon [--check | --write]   # pass 84: an old map's swarm / elite / elite_every events and waves[] turned into roster rows (the same converter as the Level Editor's model.js convertLegacy; layout kept, a backup first)
python tools/watch.py [--hero drifter] [--board none|quarter|half|full|save|<ranks> | --talents grit:AAB,...] [--seed N|random] [--speed 0.25..8] [--limit 5:00] [--bot key=value ...] [--ref auto|none|<result.json>]   # pass 80: the Watch: one bot-played run in a PC window (the phone view left; numbers, charts and the bot's decisions right; Space, 1..6, +/-, ., L, G, M) on its own snapshot tools/dl/watch/snap (user folder 88fits_watch, tools/dl/locks/watch.lock, never the godot lock); tools\watch.cmd double-clicks it; the Sim tab's Watch button; the record + <stamp>_decisions.csv in analytics/runs/tools/ (all args: docs/assets_schema.md "Pass 80")
python tools/gen_wall_textures.py   # pass 80: Klein candidates for the fort wall and the cliffs, made seamless (rolled by half, the seam cross repainted) and neutralised to grey -> game/art/env/fort_wall.png, cliff_rock.png (see docs/HISTORY.md pass 80 for the picks)
python tools/posthog_runs.py [--player <name>]... [--since YYYY-MM-DD | --all] [--list] [--force] [--out analytics/remote]   # pass 78: every player's runs (run_record) from PostHog into analytics/remote/ for analytics/dashboard.html's Remote runs (personal key; analytics/howto/03_remote_runs.md)
bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/series_fixture.gd   # pass 78: the fixtures sim_avg.js / posthog_runs.py are checked against
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
# analytics/dashboard.html: open in a browser after a run played from the editor binary (played runs land in analytics/runs/, tool runs in analytics/runs/tools/, each with latest.js + index.js; pass 74: record schema 2, CSV buttons); analytics/SCHEMA.md documents the record
python tools/analytics_csv.py [--runs analytics/runs] [--tools] [--out <dir>]   # pass 74: every run file as CSVs (rows a second, events, the history) for Excel/Sheets; default out analytics/runs/csv/
"$GODOT" --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/wanted_shots.gd -- out=<dir> [only=title,hud,...] [white=1] [inset=130]   # every Wanted screen state as the handoff's PNGs show it (only=backdrop_arena rewrites art/ui/wanted/menu_backdrop.jpg the old way; since pass 83 tools/menu_backdrop.gd makes it from the composed title scene; inset=N shows the screens under a camera cutout)
python tools/wanted_compare.py <dir>/<state>.png <mock-name> [--diff] [--crop=x,y,w,h]   # a render beside its PNG in design_handoff_88fits_wanted/screens/
"$GODOT" --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/perf_late.gd -- build=six   # late-game benchmark: ms per system and draw calls (--fixed-fps 30 = a phone at 30)
"$GODOT" --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/screenshot_run.gd -- out=<dir>   # windowed, silent, ~60 PNGs for the bible (make_bible.py --shots=<dir>); without --resolution the window override gives 432x768
"$GODOT" --path D:/_projects/88fits/game -e                     # open the editor
JAVA_HOME=D:/_projects/88fits/tools/jdk17/jdk-17.0.20.1+1 "$GODOT" $P --export-debug "Android" export/88fits-debug.apk   # signed debug APK
bash tools/ship.sh [--quick] [--no-install]                       # checks -> signed APK -> install + launch on the phone (adb over USB or Wi-Fi)
bash tools/ship_prod.sh [--no-drive] [--quick] [--no-pc] [--no-android]   # pass 81: the PRODUCTION build, ONLY when Garry asks (skill ship-prod): a pruned, optimised staging copy (tools/dl/prod/stage/game; tools/prod_stage.py, game/tools/prod_plan.gd + prod_reach.gd, tools/prod_prune.py [--selftest], tools/prod_optimise.py), its checks (game/tools/prod_check.gd, smoke_run, prod_run_check.gd), presets "Android Prod" (com.eightyeightfits.game.prod) + "Windows Desktop Prod" (feature `prod` -> Settings.is_prod(): no debug surfaces), tools/prod_probe.py (the exe's cold start), report tools/dl/prod/out/report.md, Drive 88fits-prod.apk/.exe
bash tools/release.sh "note"                                      # upload the APK as the next GitHub release in the private builds repo (needs gh auth login once)
python tools/make_win_icon.py [--if-stale] && python tools/exe_info.py game/export/88fits.exe --expect-version 0.59   # pass 73: game/icon.ico (16..256, framed per size) for the PC exe; Godot 4.5+ embeds the icon and version itself (rcedit is obsolete); exe_info reads the exe's version resource
powershell -NoProfile -ExecutionPolicy Bypass -File tools/sign_exe.ps1 -Exe game/export/88fits.exe   # pass 73: signs the PC exe only when tools/keys/codesign.env exists (git-ignored; a .pfx, a store certificate or a signing service); ship.sh calls it and keeps a failed signing out of Drive; why Windows warns and what fixes cost: docs/pc_build_trust.md
python tools/gen_textures.py && python tools/gen_music.py && python tools/paint_pass.py   # art + music regeneration (see docs/RUNNING.md)
python tools/gen_sand.py   # pass 82: the four new sands (Klein paintings, seam repainted in three passes, today's mean colour) -> game/art/env/sand_<id>.png, sources tools/art_src/sand_<id>_src.png; the map key timeline_data.sand picks one (default pass81 = sand.png), the Level Editor's World card and the arena's WORLD tab switch it
python tools/gen_prop_variants.py && python tools/prop_shadows.py   # pass 83: painted prop variants (Klein, the style anchor + the original's raw render; props.json `variant_of`, `weight`; PropField picks by a hash of the spot) and every painting's ground shadow (props.json `shadow`: width, depth, offsets, strength); bash tools/godot.sh ... --script res://tools/menu_backdrop.gd rewrites art/ui/wanted/menu_backdrop.jpg from the composed title scene (art/ui/title_scene.json)
python tools/gen_totem_icons.py   # pass 83: the totem gifts' carved segments (a head painted on green in the pole's style, keyed and laid on one cedar block) and the crest -> game/art/ui/totem/spirit_<id>.png, crest.png (usage in its header)
python tools/make_pipeline_figs.py && python tools/make_bible.py   # bible section 15b's step-by-step art pictures (from tools/dl/ intermediates), then the bible
python tools/make_onepager.py [--pdf] [--force]   # the kick-off one pager (2026-10-26): docs/onepager/src/onepager.html + content.json + pictures.json -> docs/onepager/88fits_OnePager.html (self-contained) and, with --pdf, the PDF through headless Edge; pictures cut once into docs/onepager/img/
bash tools/godot.sh --audio-driver Dummy --resolution 1920x1080 --path D:/_projects/88fits/game --script res://tools/marketing_shots.gd -- out=<dir> shot=swarm|nightfall|bloodmoon|boss|play|horde|bestiary|ui|scout   # staged in-engine marketing stills, frozen and captured (every argument in its header; 1080x1920 for play, horde, ui; bounded by a watchdog)
python tools/ai_sfx.py [--dry-run | --gen-only | --auto | --bind | --report | --docs | --only ids | --cands N | --pick id=k | --volume id=dB]   # pass 60: every sound effect from Stable Audio (Garry's app at http://127.0.0.1:7861/, AudioGen on 7860 as the alternate) -> content/sounds/real/<id>.wav + the soundmap rows; then --import + import_json -- only=sounds; python tools/make_sfx_review.py -> docs/sfx_review.html + tools/dl/sfx60/sfx_review.zip (the voice barks are gone; gen_voice.py lives in tools/dl/backup/)
python tools/icon_sand.py [--gamma 0.8] [--splash] [--compare out.png]   # pass 61: the launcher icon's sand a touch lighter (only the sand; the old source tools/dl/app_icon/icon_src_v046.png), then gen_art.app_icon and make_splash
"$GODOT" --audio-driver Dummy --fixed-fps 60 --resolution 504x1122 --path D:/_projects/88fits/game --script res://tools/_p61_pk_bench.gd   # pass 61: the pickups benchmark (N gems lying, the hero walking, a vacuum): ms a frame for "pickups", the whole frame, draw calls
"$GODOT" --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/difficulty_probe.gd -- t0=300 secs=130 stage=0 level=22 build=b1 mirror=0 hero=calavera seed=11   # pass 62: how hard a stretch of the run is for a fixed build and Mirror rank (0/3/6): HP lost a minute net of healing, per source, kills, the crowd against the cap
"$GODOT" --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p61_wp1_shot.gd -- out=<dir>   # pass 61: the gun mutations' looks without and with, around a shot (needs --fixed-fps)
"$GODOT" --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p60_wp_shot.gd -- out=<dir> [only=tommy,boomstick,chicago,blunderbuss,pod,scepter,pea]   # pass 60: every gun's rounds frame by frame, the pod at pressure 0/1, the sceptre with Flicker; _p60_pk_shot.gd -- out=<dir>: a field of gems and the magnet arc
python tools/gen_art.py [--anchor|--pick=N] [--only id] [--force] [--seed=N]   # Clash-style sprites/icons via Flux.2 Klein on ComfyUI (192.168.137.54:8188), vision QA, review sheets, imports at the end
python tools/comfy.py --export                                  # ComfyUI workflows as UI-loadable JSON in tools/comfy_workflows/
python tools/comfy.py --install-ext [--no-restart] | --check-ext   # pass 66 follow-up: the 88fits_open web extension (tools/comfy_ext) onto the AI server's custom_nodes + a restart under the ComfyUI lock; it opens a saved workflow from a link (<server>/?open=workflows%2F88fits%2F...), which the Level Editor's job cards use (every job's workflows are saved into the page's Workflows sidebar, 88fits/)
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

## Status (2026-10-26, pass 107, version 0.91)

What is true now, in short. The why and the detail of every pass (1 to 65) is in **`docs/HISTORY.md`**: search it for a
symbol, file or pass number when you need background (`grep -n "PickupManager" docs/HISTORY.md`); do not read it whole.
After each pass: append the pass's paragraph to `docs/HISTORY.md`, and update this section only where what is true
changed.

**Shipping.** `bash tools/ship.sh` -> signed release APK -> `E:/My Drive/88fits builds/88fits.apk`, then a PC build (the "Windows Desktop" preset, one `88fits.exe` with the game embedded) -> `E:/My Drive/88fits builds/88fits.exe` (`--no-pc` skips it; iOS was looked at and dropped: it needs a $99 Apple developer account) (Garry plays on the
phone, often away from the PC; see `docs/RUNNING.md` and the ship-to-phone skill). ship.sh runs import, import_json, the
parse check, all gdUnit tests (~1,731 in `game/tests/passNN_*_test.gd`), smoke_run, arena_check and touch_audit. Also run
`hell_check.gd` after stage-3 changes. Version in `application/config/version` (0.91). The PC exe carries game/icon.ico and
the game's version (Godot embeds both; pass 73) and is signed only when tools/keys/codesign.env exists (docs/pc_build_trust.md).
Pass 81: the dev build's label is "88fits Dev" (packages unchanged); the **production build** (`bash tools/ship_prod.sh`,
skill ship-prod: no debug surfaces via `Settings.is_prod()`, only the content and looks the game can show, music as
Ogg; package com.eightyeightfits.game.prod, label "88fits", its own PC save folder; Drive 88fits-prod.apk/.exe) is
made **only when Garry asks**; analytics events carry `build: dev|prod`.

**The game.** One map, **Red Canyon** (`world/maps/red_canyon/RedCanyon.gd`): noise terrain, one dry river and two or three oases
rolled per run from `Run.map_seed` (pass 80: `oases`, water slows walking by `water_slow` 10%), sand to a western
sandstone fort wall (pass 80, `CanyonWalls.gd`) with the red-rock cliffs behind it; everything but the ground, the wall, barrels, signs and a few
movers is a painted 2.5D billboard (props `art/sprites/props/`, structures `st_<id>.png`). Three stages, each its own run since pass 87
(Sundown 7:10 to the Tumbleweed King, Nightfall 10:00 to the Gila Grande, Blood Moon 13:00 to the Brander; stage 3 is "hell": a red
ground and a hell channel of creatures on its own cap), each followed by a portal countdown and Endless. The timeline (`content/maps/red_canyon/red_canyon.json`
`timeline_data`: cap curve, roster rows, waves, events, specials, HP/ATK curves, scaling) is **Garry's to edit in the
Level Editor** (`tools\level_editor.cmd`, `docs/level_editor.md`, schema `docs/waves_schema.md`; since pass 66 the same
page also creates and edits enemies, heroes and items and queues their art for the local AI: the Enemies / Heroes / Items
/ Jobs tabs, `docs/level_editor.md` "Pass 66", keys in `docs/assets_schema.md`, rules in BALANCING.md §13); stage 1 is his own
work (pinned by `pass62_pc_test`), stages 2-3 were written in his style in pass 62 and tuned in pass 64 so stage 2 is clearable with a quarter of the Upgrade board and stage 3 with half (`tools/difficulty_probe.gd`). Enemy strength = base x
`stage_mults` [1, 2.2, 3.34] x the HP/ATK curve at the row's start x (1 + level_*_per_level x (hero level - 1)) x
`creature_*_mult`, fixed per row from its start. Specials (pass 69): a third as often as before, x10 HP, x2 ATK, x1.25
size, a glowing rim in a colour Garry sets per creature (`variance.special`, map default `special_defaults`); one forced
special Red Goblin (a swarm event with `special: true`). Pass 72: specials x1.5 size, x15 HP, a 35% chest, at most 3 alive
(`special_defaults`); creature outlines only behind scenery (stencil 2 = scenery, core/systems/SceneryStencil.gd); every
push the hero's side gives x `hero_knockback_mult` (0.5); a boss's HP x clamp((recent DPS / reference)^0.5, 0.75, 3)
(`boss_hp_scaling`, refs King 600 / Gila 4500 / Brander 20000); custom boss attacks are content
(`content/boss_attacks/<id>`, kinds rain/volley/ring/slam/script; the Gila's `cactus_rain`), edited in the Level
Editor's Boss attacks tab. The Results screen is a two-part show fed by `Run.timeline` (core/systems/RunTimeline.gd); since pass 74 the chart
block pops in after the gold count and the line, the counters and the damage sources play together on one clock.
Pass 73: weapons take the nearest special, Elite or boss within 10 m first (map `target_priority`;
`EnemyManager.priority_target`, a spread volley sends only its first shot there); the Saiga Sniper (special, brain
`sniper`, core/systems/SniperFx.gd: a gathering red line, a lock, a beam across the map; look SS-A) and the `flee_on_hit`
block any creature can carry; the Raider's rocket slows to half on every hit (`artillery.missile.hit_slow`); custom
boss attacks gained `volley` landing (every spot lit at once, a `spew` from the mouth, all land together: the Gila's
cactus_rain); visible burrowing (a ground-clip in enemy_billboard.gdshader; the Gila waits 3 s hidden and erupts where
the hero is about to be, throwing him and the crowd; the Scorpion Elite weaker); boss summons never special, four more;
every spawn grows out of the ground (map `spawn_rise`; not a target until 70% up, area damage hits it); 10-12 Totem
Poles a map (content/structures/totem_pole, ui/TotemScreen.gd, core/systems/TotemBoons.gd, `Run.totem_boons`): three
small weighted boosts named in Pacific Northwest animal words, grey when used.
Pass 79: a mutation offer falls due on the stage's `path_times` and comes as the hero's next level-up, in place of
the three cards (the HUD's "MUTATION NEXT" mark; `Run.mutlvl_*`; `xp_need_mult` refit with the run sim; what grows
with his level reads `Run.card_level()`, his level less the mutation level-ups, unless `mutation_levels_scale`);
bodies follow through with their push and a blast throws them (EnemyManager `CORPSE_*`); every tracer is a thin
line fading like smoke (`tracer_width`, core/shaders/tracer_line.gdshader, one MultiMesh); the rim and the walls
take their colours from the map (`rock_color`, `wall_colors`, duskier since pass 79); the dynamite and the Golden
Pineapple are thrown where their crowd will be when they blow (`params.lead`, EnemyManager.predicted_counts).
Pass 80: every tracer draws the **wisp** (`tracer_style`: a hot streak riding with the round, a pale smoke fading in
about half a second; streak, ribbon, toon and pass 79's line one param away; ProjectileManager `TRACER_STYLE`).
Pass 81: the lakes are a cheap water shader (core/shaders/water_lake.gdshader) with damp earth and green round them
(`RedCanyon.oasis_wet`), the sand a calmer painted texture (tools/gen_textures.py, source tools/art_src/); a roster row
may be paced as waves (`pace`, `every`, `count`, `offset`, `respect_cap`, `trickle`; yellow etches in the editor);
the bees draw dashed flight paths (`missile.trail_style` "dash"); the Vulture Raider's rocket flies at 0.85 of the
hero's top speed; the Saiga Sniper walks in to 16 m and holds (no flee; a hit still spoils its aim).
Pass 82: the hero's hurt jiggles the HP bar (HUD `shake_hp_bar`), never the screen; every kill throws its body
(EnemyManager `_corpse_follow`: a floor push and toss along the hit, heavier for big hits and crits); five sands
(map `sand`: pass81 default, dunes, dunes_pebbles, ripples, ripples_pebbles); the Totem gift screen is the Spirit
Pole (ui/TotemScreen.gd from design_handoff_88fits_totem/, WNotches, WNail, toasts with an icon); the XP a level
needs follows `xp_curve` {type quadratic|linear|exponential|power|table} x xp_need_mult (core/data/XpCurve.gd; absent
= today's); the bot hunts specials (option `specials`); the Sim, the Watch and the dashboard chart chests, power-ups
and totems (SimModel.pickupKind).
Pass 83: bosses come with at least `boss_hp_scaling.seconds` (King 25, Gila 40, Brander 60) of the hero's full DPS
(mode "seconds", the default; "dps" is pass 72's peg); the hero's **power** (core/systems/HeroPower.gd: sqrt of full
DPS and effective HP against a fresh Drifter = 1.0) is recorded, charted and can scale creature HP
(`power_hp_scaling`, 1 = none); a round hits a body where it is drawn (`EnemyManager.indices_touching`);
`hit_invuln` 0.25 s; the sand plays ripples_pebbles; every prop, structure, barrel and sign stands on a ground
shadow (PropField GroundShadows) and props have painted variants; the title is a composed scene
(art/ui/title_scene.json); the totem's segments are carved faces per gift; a roster row in the continuous draw may
carry its own `interval`; the Timeline's shares are "% of the past N s" (the Share lane is gone).
Pass 84: **one spawning language**: a roster row is continuous, waves (every N or [min, max]) or `once`, its creature
one id, a list (`enemy_weights`) or "roster", and may carry `elite`, `special`, `banner`, `ring_radius`, `role`,
`name`, `chance`, `t_jitter`, `respect_hard_cap`; swarms and Elites-every are rows (old maps' events still play;
`tools/migrate_timeline.py`, the editor converts on load); `floor_curve` (least alive). The Timeline tab: foldable
sections (eye = view only, pencil = editing), On screen / Challenge / Composition charts with their recipes, rows
by stage and role, a full row inspector, warnings; the Sim's overlay (`/api/sim/overlay`, `overlay.json`: alive by
creature, cap full, starving rows, threat, challenge, lifetimes). Every creature on screen casts its shadow.
Pass 85: the title builds on the map's own sand and lays one of six presets (art/ui/title_scene.json); every prop
kind has a natural random tint (props.json `tint`, prop_billboard.gdshader, per spot); new fan_palm_b and
joshua_tree_d; Teleports smaller, 3 a map (4 a third of the time), 40 m apart, landing 15 m clear of any
(teleport `per_map`, `land_clear`); the Spit Cactus plays the Dynamite Bandit SC-A (fresh): `ranged.shot:
"dynamite"` thrown in place a little ahead with a hop (`throw_jump`, pass 86), a 1 s fuse, a blast like the hero's; Fadeaway has a Puppet look FAD-D
(fresh; he plays FAD-C); the Watch opens on a Hero Settings pop-up (WatchSetup.gd; Restart run, R), shows the
build's icons, the bot's goal plaque (WatchPlaque.gd), sound off by default, and the bot goes for power-ups.
Pass 87: **stages are their own runs** (`timeline_data.stage_list`: Sundown 430 s, Nightfall 600 s, Blood Moon 780 s,
windows of the one timeline; Run.start_stage / choose_stage; a fresh level-1 run from the window's start, the clock
shown per stage; after the boss a 60 s portal countdown with only EXTRACT, then **Endless** (`endless`: a big wave,
then a stronger one every 10 s, 0.35 XP, rare coins); Save `stages_beaten`; the Stages menu ui/StagesScreen.gd opens
on Play once stage 1 is beaten; stage filters (StageLook.gd, stage_filter.gdshader: Nightfall blue, Blood Moon red)
and pictures art/ui/stages/; the Level Editor's stage tabs, `--stage` on sim_batch and watch, analytics and PostHog
by stage (board "88fits · Stages")); stages 2-3 retuned for a fresh hero. Also: the Big Mouth without a tongue (a
throat glow, a 0.24 s wind-up, a punch); the EVADE word and a see-through hero; black barrels hold 1-5 coins (+2 a
map, `PickupManager.coin_debt`); fresh looks SOL-F/G, FAD-E/F, DM-F..I (none played yet).
Pass 88: the hero takes no knockback from hits (`Settings.hero_knockback`, a debug switch, locked off in prod);
the mummy plays DM-G and Fadeaway FAD-E; `shadow.die_drop` sinks a death strip (the Red Goblin 0.2); the Big Mouth
punches once a beam and shows one white `Glow` egg only while it attacks (Cavity/ThroatBack gone), its title spin
faces the camera; the Stages menu: "Choose a Stage", "Difficulty: Easy...", the boss hidden until met
(`Save.enemy_met`), pictures without creatures; the Upgrade board's Spite is **Stakes** (forms Difficulty and Boss:
+10% HP and ATK, +4% speed a rank, a hidden +5% XP and coins; core/systems/MirrorDanger.gd; old Spite ranks refunded
once), every talent repriced by its measured power and the board sorted by first-rank price (Registry.talents_list).
Pass 89: the special attacks push the hero again at the map's `hero_special_knock` (0.5: charges, blasts, rockets,
the dynamite, slams, eruptions, boss attacks, the Sniper's beam, weighted shots; Player.knock_share); a bite or a plain
shot never does; the debug switch "Full hero knockback" plays every push whole.
Pass 90 (tools only): the bot breaks out of a ring (game/tools/bot/BotBreakout.gd, option `breakout`, on with
style safety; new preset `survivor`), hunts only the special creature types (gear badge: Rocketeer, Saiga Sniper,
Harpooner); the Watch has a Damage taken tab beside HP & Danger (WatchHurt.gd, D), a hover hint on every chart, and
revives the fallen bot at will (`--death ask`, the default: R revive, B with the blast, E end; recorded as
`watch_revives`).
Pass 91 (art tools): Level Editor method "Creature from front + back pictures" (creature_pictures: two pictures as they are or redrawn, the procedural walk, screen auto), death `shatter` (a heap of pieces, artkit.shatter), the keyer no longer cuts a green figure's feet on a green screen (the black line).
Pass 92 (art tools): the Desert Spider (content/enemies/desert_spider, looks SP-A..D fresh, plays SP-B, on no map);
`blender_depth_drivers.py mode=gait|flip_curl` (tools/blender_gait.py: a made walk for a rig without a clip, a death
rolled onto its back with the legs curled; proportions body_scale/head_scale/leg_scale/head_pitch), tools/blender_limb_clone.py
(method ref_limbs: copy/turn leg chains, rest=frame:N), gen_ctl `ctl_soft`/`death_soft` (softened depth keeps cartoon
faces), a walk cache keyed on painting+seed+control; explainer https://claude.ai/artifact/PuzdQ4H2dvaTJDEbtfKGwv (docs/spider/).
Pass 93: made walks `step=track` (feet along the body; driver spider_walk_v2; tools/gait_check.py), spider looks SP-E
(light purple) and SP-F (light blue) fresh; gen_ctl `fit_ref`, `no_green: "rb"`; the Level Editor's Drivers tab
(tools/level_editor/drivers.js, drivers_io.py: every driver in tools/dl/drivers previewed with frame numbers, the
folder layout explained) and a `death_keep` frame picker.
Pass 95: held guns fire from the muzzle as drawn (`ProjectileEmitter.shot_origin`); the Frisbee's `disc.trail`
per look; the debug switch `Settings.fire_forward` (core/systems/FireForward.gd: Sabre, Spear, Hammer, Frisbee,
Tumbleweed and the Basketball fire where the hero faces until a creature is within 75% of range); **passive items
climb the rarity ladder** (PassiveDef.ladder_levels: rungs to Legendary + Evolved; `<id>_icon_evolved.png`;
tools/passive_ladder.py); the **Dragon's Breath** (content/weapons/dragons_breath, core/behaviors/FireBreath.gd, the
slowest weapon: a 2 s cone from the hero's face, a tick a second, ignite; Blue Flame / Held Breath / Backdraft,
evolution Fire Eater with thorns); regular creatures **despawn** 40 m away and off-screen leaving nothing
(`timeline_data.despawn`, EnemyManager.despawn; WaveDirector's old move-up kept for the kinds the rule never takes);
the Magnet power-up pulls gems and coins within 2.5x the Magnet card's reach for 10 s (MagnetBuff.gd, a HUD plate);
the King's tumbleweeds trail dust and his `stomp` is three hops with waves (Game.stomp_wave); the Scorpion Elite's
`tail_sniper` fires three Saiga-style beams in a row (boss attack rows take `chance`); the Level Editor's **Frames
view** (tools/frames_store.py, frames_io.py, frames.js: every frame of every look, versions per slot with
provenance, frames from other looks, several changes staged then one Export; VACE repair tools/vace_repair.py +
comfy.wan_fun_vace on the Wan 2.2 Fun VACE 14B fp8 pair installed on the AI server) and the tooling assessment
docs/tooling/assessment_2026-10-21.md.
Pass 96 (tools only): **the art-production loop** (Phase 0 + 1 of the assessment's plan): `tools/art_request.py`
+ tools/level_editor/requests.py (the record under tools/dl/jobs/requests/, the step function, the fold, Garry's
budgets per request), vision_eval.py (three evaluator backends, opaque names, the ledger with $0 ceilings),
commands.py + loop.py (the Auto-iterate allow-list and the planner: repair with the benchmarked VACE profile and
escalation, re-roll, prompt edits, a provisional winner that can never reach the game without his one approval),
the `evaluate` job kind, the request card on the Jobs tab, the frame layer's rules (the descriptive label, the batch
confirm, pins re-applied, no deletion), the cancel fix (never `/queue clear`), selftest_SLICE.py (the whole chain on
fakes); the VACE window profiles per method class in methods.json `repair.profile`, the tier table in
request_defaults.json; docs/level_editor.md "Pass 96".
Pass 97 (tools only): **the live page**: job cards patched in place, `/api/jobs?delta=1`, hash routes, the look
card's live block, ComfyUI node progress on the card, tools/dl/jobs/events.jsonl + the archive, /api/ops, server.log,
tools/doctor.py, tools/requirements.txt, tools/ai_hosts.json, the console-close handler, Re-queue all, the request
guard, tools/net_check.py; selftest_JSSYNTAX97.py parses every page script; jobs._save refuses a foreign queue file.
Pass 98 (tools only): **Gemini checks the art** through Garry's subscription via the Antigravity CLI
(`vision_eval` backend `antigravity`, numbered contact sheets of 16 frames, tools/dl/qa/agy_inbox, one read rule in his
Antigravity settings; never --dangerously-skip-permissions): tier 0, then Gemini, the local model only when a Gemini
call fails, shown as an error ("Gemini failed: ... - checked by the local model instead", "Local (fallback)");
a Gemini leg count alone never drives a repair; `tiers["2"].daily_calls` 6 (his quota is weekly; a spent quota is
remembered in tools/dl/qa/agy_state.json); Ask Gemini (Frames), Check with Gemini (look and job cards), badges per eye
(tools/level_editor/eyes.js, eyes_io.py); docs/level_editor.md "Pass 98".
Pass 99 (art): the Desert Spider's SP-G (Klein 28, plays) and SP-H (Flux.2 dev 40) finished on spider_walk_v5 /
spider_death_v5 (blender_depth_drivers `drop_islands`: the model's loose fins dropped from the renders; the death
curls the legs in); SP-G's fd/bd painted again; gen_ctl recipe keys `view_words`, `clay_drivers`, `view_drivers`;
explainer docs/spider/spider_explainer.html sections 6b/6c. The spider is still on no map.
Pass 100: **build quests** (QuestTracker types `hero_level`, `item_level` {kind, id?, level | rung},
`evolve_item`, `weapon_paths`, `items_maxed`; completed only by the run's own checks; seven kill quests and May's
converted, Save keeps completion by quest id); the Phoenix Feather is one-shot (PassiveDef `single`: one level, off
the rarity ladder, never offered again); the run's stage look is set before the spawn beam (Game._show_stage_look_now,
the beam drawn above the filter); the phone's performance assessed (tools/dl/p100/PERF).
Pass 101 (performance): only creatures whose whole picture reaches the view are drawn (EnemyManager `drawn_vis`,
vis_bounds, a border and a 6-tick hold; the weapons' `onscreen` unchanged; proof game/tools/_p101_CROWD_pixels.gd: 0
differing pixels); separation on its own 1.25 m grid (SEP_CELL, `_sep_bigs` cell lists; the 2.5 m grid stays for
weapon queries); creatures not drawn steer every 4th tick (bosses, Elites, near rocks every 2nd; far_push_scale);
`Settings.frame_cap` (60 on phones, the developer menu's Frame rate row); run record schema 3 with frame times a
second (`frame_timing`, the dashboard's Frame time card); looks load on demand (`sprite_path`, core/data/LookArt.gd
cache, core/systems/RunLooks.gd pins a run's set under the spawn beam): boot 2.3 GB of pictures -> 121 MB, a run ~0.4 GB.
Pass 102 (performance + Level Editor): a run caps the world's catch-up at `Game.CATCH_UP_STEPS` 2 a frame (an
overloaded phone slows the whole game together instead of spiralling; menus keep 8); `Run.play_clock` for rule
seconds; run record schema 4 (core/systems/WorkClock.gd: steps, phys/proc/rest ms a second, a per-minute heat table);
damage numbers merge and thin past 40 on screen, fire/poison clocks lazy, flames thinned past 80 burning, hit sounds
120 ms apart, crit stats cached (StatSheet.version); Level Editor: the cap shown as load with `cap_max`'s cut and the
effective limit in bodies, composition swatches, map saves wait 8 s then follow their import job.
Pass 103: Endless `hp_growth` 0.15, `atk_growth` 0.095 (the lead's guess for Garry to tune); creatures resist
non-explosive knockback more each second of Endless (`knock_resist_max` 1.0 over `knock_resist_seconds` 90; weapons
tagged `explosive` and the sources in `knock_resist_exempt_sources` keep their push; EnemyManager.HIT_BLAST); Backdraft
knock 3.3, Fire Eater 4.7; Powder Keg a twelfth of the body's max HP (Game.KEG_FRAC).
Pass 104 (docs): the design bible rebuilt for pass 103 (fresh captures from game/tools/screenshot_run.gd, played looks in
the generated sections, each section leading with what is true now and a collapsed history block; 12.4 MB).
Pass 105: the stage filter tells six stencil values apart (core/systems/StageStencil.gd): sand 0 and scenery 4 at
`strength`, actors 1 at `actors`, weapons' 3D models 2 at `items` (0), shots and chests 3 never tinted, structures,
the portal and barrels 5 at `structures` (0.3); one quad per tinted value; the creature outline reads stencil >= 4.
Pass 106: Endless `speed_growth` 0.04, `speed_max` 2.4, each wave's speed applied to creatures already alive
(EnemyManager.set_endless_speed, `e_speed`); a negative `shadow.die_drop` holds through the death's sink (the spider
-0.15); the War Drum stops time for a 2.2 s drum moment (ui/DrumMoment.gd, Modal.DRUM, Audio.hold_music, sound
st_war_drum_beat) then a 15 s boost (core/systems/DrumBoost.gd: x2 damage and attack speed, knockback, +15% speed;
halved where Rage or Sprint already boost, `params.stack`; a HUD plate); the Watch's "You play" button / T hands the
run to Garry (keyboard, mouse as the thumb, his clicks on screens; recorded as takeover/handback, a `driver` column).
Pass 107: recolour looks BB-E/BB-F (white and pearl shells), ANT-G/ANT-H (gold, rose), LS-D/LS-E (bone, gold) by
`recolour_strip.py --mode lift`, played in Stage 2's rows r27, r9, r29, r8; the Fire Ant plays ANT-E with its own shadow;
`stage_list[k].xp_mult` (Nightfall 0.7: ~12% faster levels than Sundown; Blood Moon still ~2x, reported); a
ProjectileEmitter's `night_tint` while a stage filter shows (the Tumbleweed pale straw); `EnemyManager.spawn_boss`
makes a slot when the pool (MAX 320, under the map's hard_cap 500) is full, so a boss or Elite always comes.

**Heroes** (title order; pass 83: the Drifter is free, Ironwood and Astro gold only at 300, every other one a requirement
then gold): Drifter (Revolver), Astro (Gravity Gun); Calavera (Guitarra), Ironwood (the Spear =
`pike`), Solenne (Sun Scepter), Fadeaway (the Basketball: evade per level, Heat shown on the ball itself, the Timeout
trampoline perk Hang Time, Buzzer Beater), Jeżyk (id `buck`: a bald blue Slav in a tracksuit, starts with the Frisbee, favourite the
Salt, momentum, Salt Flats), May (renamed from Mamy in pass 69: attack speed, Trigger Happy on the Tommy Gun, the
Inflatable May decoy, thrown as a puck that inflates) and Mira (an unattainable requirement) are bought with gold after an unlock quest
(`content/quests/unlock_<hero>`, `availability: "purchase"`, `price`; Save `heroes_owned`; Registry `hero_state`);
Dad is `hidden`. No HUD gauge for any hero (pass 69). The title's hero drawer (`ui/wanted/WHeroDrawer.gd`) lists every
hero; one not owned shows as a black silhouette, "Unknown", with his requirement or a BUY button. Each hero's trait is 1-2 stats that grow per level
(`trait_per_level`, `Run.hero_sheet`), a favourite weapon or passive (arrives at a bonus level, marked on cards), perks,
and a hero mutation. The title plaque opens the hero's Wanted-poster sheet (`ui/wanted/WHeroSheet.gd`). Art variants
(`variants` / `variant` in the JSON; Jeżyk plays BUC-F, Fadeaway FAD-C, May MAY-G (her base since pass 70); Garry picks them in the arena or in the Level Editor's look grid; a look may be
`shelved` out of the chips, a landed one is `fresh` until approved): see the art-variants memory. A hero JSON carries
`availability` (available | purchase | hidden: only hidden hides him), `price` and `currency_type` (gold), the unlock
quest edited from the Heroes tab (memory `88fits-hero-purchase-parked`: decided in pass 69).

**Items.** Weapons (5 slots, 5 levels; three path mutations each, due at set slots `path_times` and offered at the next level-up; all three + level 5
= evolution at a chest; hero mutations optional), lines (5 slots, 4 levels, evolve when maxed; `PassiveDef.line`) and
passive items (no cap). Since pass 73 the lines are **Cards** to the player (tarot names, evolutions "<card> Risen";
ids unchanged; `PassiveDef.display_name_of`); passives carry item looks (`variants`/`variant`, the cards A-E, the game
plays B, a save's own `Save.card_look` from the arena chips, the Level Editor's "Set every card to look"). Everything is content: `content/weapons|evolutions|mutations|passives|perks|pickups|structures|
enemies|bosses|characters|talents|maps|sounds`. Mutation looks come from their `params` (`look`, `tint`, ...); emblems
are gone. Pierce drop-off is on by default (`Settings.pierce_falloff`, Debug panel). Pass 70: lines Lodestone, Mule Kick (evolution Bucking Bronco throws creatures up and away), Slow Burn (overlaps
Ducktape), Tin Star, Prospector and Gold Tooth (lines now), each with an evolution (21 lines); perk special `trampoline`
(core/systems/Trampoline.gd, Player airborne flight with air control); a look recipe's `run_scale` per view. Pass 69 primitives: behaviours
`SaltShaker` (patches laid along the hero's path, `params.salt`) and `Frisbee` (curving discs through everything,
`params.frisbee`), the ball's `launch` (Alley-Oop) and `heat_look`, a ball tint's `body`/`seams`/`ambient`, a gun's
`fire_without_target`/`stream`, perk special `decoy`, player stats counter_*/heavyweight/overheal/heal_pulse/last_stand/
xp_pull_*, TextGen's stat kind "word" (named, never numbered). Pass 68: a look's recipe carries `stills` (heroes too), `seed_offset`, `method`, `from` (a draft), `painter.stills`; a look entry `icon_picked` and `title` (a hero look's own cut-out); a hero is drawn in the look he is played in (`Registry.played_look`: the badge everywhere, the cut-out on the Painted title). Pass 67 primitives: a weapon's `amount_mode: "bounces"`, `return_on_hit`/`return_pierce`, `catch` (the ball's refund and Heat), a creature's `knockback_resist`, the map's `weapon_grade` (every 3D weapon's lit materials darker and richer), perk specials `periodic_buff`/`timeout`/`overdrive`, the pickup effect `leap`. Pass 76: **weapon-family looks** (a weapon's `variants`/`variant_base`/`variant`, its mutations' and evolutions'
entries by the same codes: name, flavour, text, icon, visual, params laid over, nouns; per save `Save.item_looks` from
the arena chips, for everyone the weapon's `variant`; `core/data/ItemLooks.gd`, Registry.apply_item_looks); the
Grenade family plays **B, the Dynamite Stick** (C, D candidates, the grenade A): `params.fuse` (lies a second, the
spark out half a second before), models by form and colour (`models`, `model_form`, `model_colour`), `mass_mini`
(Fire in the Hole, the Drifter's hero mutation; his favourite is now lob_grenade; the Peashooter and Fan the Hammer
hidden); the Molotov family plays B, the torch (`wick_flame`, `pool_flame`, core/systems/WickFlames.gd); the pause
Stats tab marks changes since `Run.start_stats` and lists sources (core/systems/StatSources.gd, stable source ids).
Pass 75: a companion gun's `params.familiar.kick` (a punch on every round, on its frame, unsmoothed, a spring past
rest) and `familiar.spin` (a trick spin after a pull now and then), on the Revolver and the Golden Revolver only.
Numbers and rules: `BALANCING.md`.
A weapon the editor creates starts hidden with three template path mutations and a template evolution, all hidden,
until they are filled; a new line or passive item starts available; "locked" is a quest whose `unlocks.id` names it
(the Items tab's availability op writes the quest). The count pins in the tests are shape rules now
(`pass66_shape_test.gd`: every weapon in play has its three path kinds and its evolution, every creature a doc, a blood
and a knockback, every playable hero a perk and one hero mutation).

**Meta.** The **Upgrade board** (`ui/HomesteadScreen.gd`, still "the Mirror" in code; `content/talents`): eight talents,
two forms, six ranks; every rank is bought in one form and keeps it (`Save.talent_picks`); Take it all back refunds half.
Gold: every end of a run banks the purse (pass 70: a death too; only quitting the app mid-run loses it); unlocks cost
2.5x pass 69's, Elites and bosses pay 5x; the Strongbox (`gold_bank`) is hidden, out of play. Unlock quests gate half the
items; the Collection shows only what was met.

**UI.** The Wanted kit (`ui/wanted/`, see Architecture); one paused screen at a time with death winning
(`Game._request_modal`); the camera cutout is respected everywhere (`W.safe_top()`); touch is raw ScreenTouch, never
mouse emulation (`TouchScroll`, `TouchSlider`); prove UI with `touch_audit.gd`. The developer menu (hold the Settings
version line 2 s) and the player's debug mode (10 taps on the hints switch) hold the test switches; the debug arena is on
the title in debug mode. The Down! screen has no gold revive (pass 77). The title's hero plaque is one size for every hero and state (pass 73, ui/TitleScreen.gd constants).
The Level Editor never overwrites an icon and asks before changing a played look's (pass 76: icon history, Revert icon,
All icons on disk). Known (older than pass 76): about one headless game run in four to eight exits 0xC0000005 in the
scene tree's teardown after its result is printed; results are unaffected.

**Analytics.** `core/autoload/Analytics.gd` -> PostHog EU (write-only `phc_` key in `game/config/analytics.json`; the
personal `phx_` key only in git-ignored `tools/posthog_personal_key.txt`, never in the game or a commit; Garry's email is
never sent anywhere). Consent card first, persons named by `Save.player_name()`, `run_summary` per-minute curves, gold
sources/sinks, surveys from PostHog Surveys with `[after N]` / `[run N]` name tags. Boards: `python tools/posthog_boards.py
[--check]` (nine boards, ids kept on a rerun, SQL tiles follow dashboard filters). How-tos for Garry: `analytics/howto/`, indexed in `analytics/README.md` ("Start here"; pass 82; the dashboard's
Remote runs view shows the step-by-step).
Plan: `docs/analytics_plan.html` (artifact AK53A8KLchrSUFXxZo4kSu). Pass 78: every run that sends analytics also
sends its whole record (`run_record`, gzip+base64 parts of at most 100,000 characters, about 140 KB for 25 minutes;
never from tools, headless runs, the sim or without consent); `tools/posthog_runs.py` downloads them into the
git-ignored analytics/remote/, and the dashboard opens one run or averages runs and players (the sim's rules in
tools/level_editor/sim_avg.js). Local runs: `analytics/dashboard.html` (pass 74: the
record is schema 2, `core/systems/RunAnalytics.gd`, documented in `analytics/SCHEMA.md`: the look, trait, talents,
settings, the map's settings, totems and their offers, the Stranger, specials and Elite modifiers, the bosses' HP
scaling, healing by source, the run's timeline, quest progress, FPS; tool runs go to `analytics/runs/tools/`; a phone
keeps its newest 50 run files, the PC every one; CSV downloads on the page and `tools/analytics_csv.py`).

**Art and sound pipelines.** Flux.2 Klein / dev stills + Wan 2.2 clips on ComfyUI 192.168.137.54:8188 (skills
sprite-pipeline, sprite-animation; heroes walk on Mixamo pose drivers fitted to the painting; creatures on Blender
control videos via `gen_ctl.py`); paint several seeds and pick by eye, the vision QA misses defects. Icons:
`tools/gen_icon_cands.py` sets. Since pass 66 Garry queues all of it himself from the Level Editor's job form
(`tools/level_editor/methods.json` is the catalogue of 17 methods with their recipe fields, timings and weaknesses;
`tools/level_editor/jobs.py` runs each job as a subprocess through `tools/asset_job.py`; with `ASSET_JOB_SIDECAR` set,
gen_art.py / gen_ctl.py write `result.json` instead of the content JSON and the server merges the look's entry in place;
`tools/blender_ref.py` probes and renders any FBX/GLB/OBJ for the icon and look references, `tools/blender_depth_drivers.py`
turns a rigged model's own clip into depth drivers, `pose_driver.py src= rigmap= probe=` the Mixamo-style ones; new badge
candidates by `tools/gen_badge_cands.py`). Pass 71: the **Puppet** method (`hero_puppet`): a hero's painting turned into a rigged 3D puppet (Hunyuan3D 2 multi-view on the AI server, Blender rig with Mixamo names, `tools/puppet.py` + `tools/puppet_blender.py`, outputs `tools/dl/puppet/<hero>/`, a GLB previewed in the page with the vendored model-viewer) whose stick figures and depth renders guide the walks; settings size from the 3D model (`run_fit`), frame by the soles, clean colour fringes, keep the face angle, depth or stick per view; explainer https://claude.ai/artifact/RLK1zdb7p4QhDuFfMhdyRm (its source and pictures in docs/puppet/; republish from tools/dl/puppet/doc/ or docs/puppet/). May's puppet looks MAY-P, MAY-Q, MAY-R (all settings) are fresh; Jeżyk has a puppet too. One ComfyUI job at a time: `tools/locks.py` (comfy.py takes the lock itself).
Sound: Stable Audio 3 medium on the server's ComfyUI (`tools/comfy_audio.py`; UI and reward jingles in a casino-western `HYPE` table in `tools/ai_sfx.py`, music by `tools/ai_music.py` into `content/sounds/music/`; world sounds from pass 60; the gem dings, the hero's hurt and the slot machine are synthesised by `tools/synth_sfx.py`; Garry's own Stable Audio app at http://127.0.0.1:7861/ is the second engine; skill sound-pipeline). `Audio.gd` plays one music track at a time (`music_stage`, `music_boss`).
Blender models from Garry's references in `_REFERENCES/` (git-ignored).

**Docs.** The design bible is built from `docs/design/src/` by `python tools/make_bible.py` (edit the parts, not the
output) and published at https://claude.ai/artifact/2onXrvqpGH3uqwPEstVYhr; `BALANCING.md` (where every number lives);
`docs/HISTORY.md` (every pass); the kick-off one pager `docs/onepager/` (a cover and 22 slides, HTML + PDF, built by
`tools/make_onepager.py`, published at https://claude.ai/artifact/QJJocYePEYfXkv1978SLuZ; `reference_review.md` reviews the
Krazy Robots reference deck, `benchmark_sources.md` holds every market figure with its source); `docs/art_guide.html` (Garry's guide to every art method, the stats and where things
show in the game; pictures in `docs/guide_img/`; published at https://claude.ai/artifact/CcDTWtyzDiEG32i3N2MY4W).

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
- A windowed capture must bound every wait (frame caps and a watchdog): one that hung held the Godot lock for half an
  hour and stalled every lane (pass 69). The ComfyUI lock has no fairness: put art work in the Level Editor's queue
  rather than racing it from a shell.
- Tools and captures must not change the PC's `user://save.json` (smoke_run plays Astro on the real save: copy it aside
  around tool runs; use `Save.begin_sandbox()` in probes).
- Rules Garry never asked for read as bugs: name every new rule in BALANCING.md.
- Commit every finished pass (never push); the build goes to Drive at the end of every user-facing change.
- The run sim's bot is `game/tools/bot/Bot.gd` since pass 80 (presets sim77 = the pass 77 bot, explorer = the default:
  totems, barrels, power-ups, structures, the Shop and the Stranger, a map it explores; careless; expert); the Watch
  (pass 80, game/tools/watch/) plays it in a window on its own snapshot and lock like the sim.
- The run sim (pass 77) is the one exception to the Godot lock: tools/sim_batch.py runs its players on its own
  snapshot of game/ (tools/dl/sim/snap, its own user folder 88fits_sim) under tools/dl/locks/sim.lock, so the
  editor's saves and imports and the tests are not blocked; everything else still goes through tools/godot.sh.
- One Level Editor server at a time runs the job queue (`tools/dl/locks/jobs.lock`, claimed at start, the port in its
  note); a second one is read-only, `--no-jobs` is view-only. A new editor never kills a job an older editor still
  runs (`server_pid` on every taken job): it starts read-only; close the old one and restart.

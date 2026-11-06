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
python tools/level_editor/selftest.py                           # pass 66: the Level Editor's own checks (16,890; Node needed): model.js, the server on temp copies, and every selftest_<lane>.py group (S content writer/routes/vocab, J jobs, P page maths/rules, V previews, B methods.json)
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
python tools/make_loading_wallpaper.py [--review-only] [--mock out.png] [--sheet <dir>]   # pass 118: the loading screen's wallpaper strips (silhouettes from the game's icons + drawn ones) and title plate -> game/art/ui/loading/; capture: GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/load_shots.gd -- out=<dir> [entrance=punch|split] [tag=<name>]
"$BLENDER" -b --python tools/blender_telephone.py   # pass 126: the map's dressing (also blender_wheel.py, blender_grave_cross.py; kit tools/blender_lowpoly.py) -> art/props/telephone_pole.glb, wagon_wheel.glb, grave_cross.glb; the cart's painting: python tools/gen_prop_variants.py --only cart_toppled --seeds 6 --cands <dir>, then --warm <cand> game/art/sprites/props/cart_toppled.png
GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p126_DRESS_shots.gd -- out=<dir> seed=N stages=1,2,3,4   # pass 126: the dressing captured per stage; _p126_DRESS_probe.gd -- seeds=200 (headless) its numbers over many maps
bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p126_BOSS_fight.gd -- stage=2 build=b2 level=30 hero=calavera secs=150 before=20 seed=11 pilot=stand   # pass 126: Black Sunday's fight probe (the whirl's timings, lifts and tosses), _p126_BOSS_shots.gd its captures, _p126_STAGE_throw.gd what a tornado throws
python tools/gen_skin_views.py   # pass 126: a skin's stills as Klein edits of the source look's own stills, view by view, so its build and pose stay; tools/skin_recolour.py the recolour skins and a walked look's `--polish` (run it again after any new gen_art walk of a look: the walk rewrites the strip); arguments in docs/assets_schema.md "Pass 126"
python tools/figure_soles.py [--check]   # pass 127: each hero look's painted soles per idle frame -> game/art/ui/figure_soles.json (ship.sh runs it)
"$BLENDER" -b --python tools/blender_cart.py && python tools/gen_prop_variants.py --only cart_toppled --seeds 6 --cands <dir> && python tools/gen_prop_variants.py --cands <dir> --pick cart_toppled=N   # pass 127: the toppled cart, a Blender wagon (tools/dl/cart_ref.png) painted by Klein; its shadow in props.json is set by hand (no prop_shadows --force)
GODOT_TIMEOUT=260 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p127_ART_shots.gd -- out=<dir> [stage=2] [only=crow,bunny]   # pass 127: the crow and the bunnies in the arena; _p126_BOSS_shots.gd -- mode=come_here|spawn_ring|whirl stage=3 at=<s,...> up=12 out=<dir> for the boss's rows
python tools/gen_env_variations.py --only <base,...> [--seeds 2] [--force] | --sheets | --collect | --install "<name>" ... [--dry-run]   # pass 128: five named variations of each scenery prop (tools/env_variations.json; candidates, sheets and picks in tools/dl/p128/ENV; nothing in the game until --install, then prop_shadows.py and --import); python tools/make_env_variants.py builds the page docs/env_variants/index.html + artifact.html (published https://claude.ai/artifact/2Sx9fThGs4Fv6cEkLAWqVw); the cart's wreck states: "$BLENDER" -b --python tools/blender_cart_states.py
python tools/gen_env_reseed.py --only <painting id> [--seeds 5] [--force] | --list | --sheets | --install <id>=<k> ... [--dry-run]   # pass 130: five re-draws of ONE scenery painting (the same thing under another seed, one process a painting; FIXES = a repair's words; candidates in tools/dl/p130/ENV, nothing in the game until --install replaces the painting); python tools/make_env_reseed_page.py builds docs/env_variants/redraws.html + redraws_artifact.html (notes.json tags the weak ones; published https://claude.ai/artifact/WpgGKzv6j7ogMmqpsTRQdJ; INIT holds a wandering painting's composition, the cart family is painted over its Blender render, every re-draw is brought to its painting's own size in the cell)
bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <f> --script res://tools/_p130_ENV_probe.gd -- seeds=30 [looks=1]   # pass 130: what the scenery costs per stage (paintings a run draws = draw calls, textures and their MB, the map build); run it before and after adding paintings
GODOT_TIMEOUT=200 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p130_STORE_trail.gd -- out=<dir> shots=8:9:,15:16: [gold=4200]   # pass 130: the Trail screen on the game's own file at a Trail Level (level:look:node), for the store shot docs/store/06_trail.png
python tools/trail_bundle.py [level] [--optional]   # pass 130: what a Trail Level gives in one line (the same words as Trail.bundle_text and tools/level_editor/trail_bundle.js; one fixture pins the three)
python tools/trail_setup.py [--check | --tables | --fit | --probe-plan <dir> | --write [--force]]   # pass 129: the Trail's first 100 nodes as data (DESIGN), the power and purse models behind its amounts and prices; --write goes through the Level Editor's writer and refuses nodes Garry has edited since (tools/trail_setup.stamp)
python tools/level_editor/trail_io.py --check [file]   # pass 129: the Trail tab's checks on game/content/trail/trail.json from a shell (Node needed; exit 1 on an error); the tab: tools/level_editor/trail.js + trail_model.js (the rules mirrored from core/systems/Trail.gd: change both)
bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/trail_check.gd --log-file <f> [-- file=<path>]   # pass 129: the game's own reading of a Trail file (counts, total cost, warnings)
bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p129_SETUP_power.gd --log-file <f> -- plan=<abs plan.json> out=<abs out.json>   # pass 129: the Drifter's power (HeroPower) under a list of Trail set-ups, at level 1 and at level 30 with a plain build
GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p129_TRAIL_shots.gd -- out=<dir> [only=new,mid,choice,short,sections,done,nav] [bench=1 with --fixed-fps 60] [file=res://content/trail/trail.json]   # pass 129: the Trail screen's states on its fixture; bench=1 what a frame costs on 500 levels
python tools/make_trail_motifs.py [--sheet p.png]   # pass 129: the Trail backdrop's section signs -> game/art/ui/trail/motifs/
python tools/gen_icon_cands.py --only trail_<id>,... [--seeds 3] && python tools/gen_icon_cands.py --pick trail_<id>=k   # pass 129: a Trail upgrade icon (kind `trail`, jobs and the set's one style in tools/trail_icons.json) -> game/art/ui/trail/<id>.png
bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p128_BLOB_probe.gd --log-file <f> -- relocate=0|1 secs=60 warm=20 t0=200 stage=0 hero=drifter seed=11 [every=0.1]   # pass 128: the trailing blob measured (share of the crowd behind a running outlaw every 10 s, relocations)
"$BLENDER" -b --python tools/blender_dynamite.py -- look=b only=stick,stick_wire,stick_tar,stick_wire_tar,bundle,bundle_wire,bundle_tar,bundle_wire_tar   # pass 128: look B's eight red dynamite models (wire = barbed wire, tar = Sticky's amber) + the icon references; leaving evo out of only= keeps Boomtown's GLB
GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p128_DYNA_shots.gd -- out=<dir> stage=0|1|3 [only=stick,bundle_wire_tar]   # pass 128: each dynamite model thrown by the real weapon; _p128_UI_shots.gd -- out=<dir> the Outlaws screen scrolled and the other boards; _p118_BOSSCHEST_shots.gd -- only=meter mults=1,1.6,2 the speed panel
"$BLENDER" -b --python tools/blender_iron_horse.py   # pass 119: the Iron Horse's ghost train (art/props/iron_horse.glb: Engine, Tender, Coach + Chimney/Lamp empties, from Garry's Railway Kit unzipped in tools/dl/railway_kit/, CC BY 4.0) + the icon reference tools/dl/iron_horse_ref.png
python tools/gen_grave.py [--seeds 4] [--force] && python tools/gen_grave.py --pick N   # pass 119: the Undertaker's Shovel's painted headstone -> content/passives/undertakers_shovel/undertakers_shovel_grave.png
python tools/gen_ghost.py front [--seeds 2] && python tools/gen_ghost.py back --front N [--seeds 4] && python tools/gen_ghost.py --pick-front N --pick-back M [--mirror-back]   # pass 120/121: the Shovel's floating ghost (pass 121: a plain sheet ghost, nothing worn), front by Klein and its back as a Klein edit of it -> undertakers_shovel_ghost_front/back.png
"$BLENDER" -b --python tools/blender_boss_chests.py [-- export=gila_grande,brander] && python tools/gen_boss_chests.py   # pass 118 (pass 119: the Gila's and Brander's hollow, the Gila's white with lizard eyes; export= writes only those GLBs): the three bosses' chests (art/props/meta/boss_chest_<boss>.glb + renders in tools/dl/bosschest/) and their painted closed/cracked/open frames (Klein over the renders, picked by eye) -> game/art/ui/wanted/bosschest/; captures game/tools/_p118_BOSSCHEST_shots.gd
python tools/gen_royale_backdrop.py --paint [--seeds 6] [--prompt k] && python tools/gen_royale_backdrop.py --pick <name> && python tools/gen_royale_backdrop.py --manifest   # pass 123: the Royale theme's menu backdrop -> game/art/ui/royale/ (its header has the capture, the guide and the tumbleweed steps; PROPS_KEEP picks the props, a hand-measured sun is kept)
python tools/gen_ideas_art.py [--only a,b --force --seed N] [--sheet] && python tools/make_ideas_doc.py   # pass 124: the ideas book's concept art (Klein, prompts in docs/ideas/content.py) and its page
python tools/make_perf_report.py   # pass 124: the performance report from a phone run (RUN in its header) -> docs/perf/stage2_slowdown.html
python tools/build_native.py [--windows] [--android] [--setup]   # pass 125: the crowd's compiled library (native/, class CrowdCore; native/README.md) -> game/bin/ (committed, so a game build needs no compiler); fetches SCons, godot-cpp and NDK r29 into tools/dl/native/ when missing; MSVC on Windows; close the Godot editor first (it holds the DLL)
bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p125_NATIVE_proof.gd -- mode=record native=0 out=<f> hero=drifter stage=1 seed=7 limit=300 check=1 && bash tools/godot.sh --headless --fixed-fps 64 --path D:/_projects/88fits/game --script res://tools/_p125_NATIVE_proof.gd -- mode=replay native=1 file=<f> out=<report.json>   # pass 125: a run recorded by the script replayed through the library: every checkpoint equal (run it after changing native/src or the plain walker's path in EnemyManager); _p125_NATIVE_pixels.gd -- out=<dir> the draw's proof; _p125_CROWD_bench.gd -- n=800 [native=0] [every=3 far=6] what a crowd of N costs; native=0 on any tool's command line turns the library off
python tools/compress_levels.py [--check]   # pass 48: weapons from 8 levels to 5 (level 5 = the old level 8); --check re-verifies against tools/dl/levels_v47.json
python tools/sim_batch.py --out <dir> --hero drifter --players 10 --workers 0 --limit 1500 --death end --seed 1 [--trail quarter] [--trail-optional]   # pass 77: the run sim the Level Editor's Sim tab runs (a snapshot of game/ in tools/dl/sim/snap with its own user folder 88fits_sim, players K at a time, under tools/dl/locks/sim.lock, never the godot lock); one player: game/tools/sim_run.gd (args in docs/assets_schema.md "Pass 77")
python tools/migrate_timeline.py --map red_canyon [--check | --write]   # pass 84: an old map's swarm / elite / elite_every events and waves[] turned into roster rows (the same converter as the Level Editor's model.js convertLegacy; layout kept, a backup first)
python tools/watch.py [--hero drifter] [--trail none|quarter|half|full|save|<level>] [--trail-optional] [--seed N|random] [--speed 0.25..8] [--limit 5:00] [--bot key=value ...] [--ref auto|none|<result.json>]   # pass 80: the Watch: one bot-played run in a PC window (the phone view left; numbers, charts and the bot's decisions right; Space, 1..6, +/-, ., L, G, M) on its own snapshot tools/dl/watch/snap (user folder 88fits_watch, tools/dl/locks/watch.lock, never the godot lock); tools\watch.cmd double-clicks it; the Sim tab's Watch button; the record + <stamp>_decisions.csv in analytics/runs/tools/ (all args: docs/assets_schema.md "Pass 80"; pass 129: `--trail` is the Trail Level the run's save holds, `--board` its old name)
python tools/gen_wall_textures.py   # pass 80: Klein candidates for the fort wall and the cliffs, made seamless (rolled by half, the seam cross repainted) and neutralised to grey -> game/art/env/fort_wall.png, cliff_rock.png (see docs/HISTORY.md pass 80 for the picks)
python tools/posthog_runs.py [--player <name>]... [--since YYYY-MM-DD | --all] [--list] [--force] [--out analytics/remote]   # pass 78: every player's runs (run_record) from PostHog into analytics/remote/ for analytics/dashboard.html's Remote runs (personal key; analytics/howto/03_remote_runs.md)
bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/series_fixture.gd   # pass 78: the fixtures sim_avg.js / posthog_runs.py are checked against
python tools/gen_icon_cands.py [--only spear,cake] [--seeds 4] && python tools/gen_icon_cands.py --pick spear=0   # icon candidates (renders as references), picked by eye
tools\level_editor.cmd                                           # pass 53: the Level Editor (a local page: waves, roster, events, overrides per map; Save writes the JSON + imports it); schema docs/waves_schema.md
tools\ship.cmd [--quick] [--no-install]                          # pass 53: ship.sh from a double-click (Git Bash)
python tools/recolour_strip.py --src <strip.png> --dst <strip.png> --ranges 55-135 --to 357 --sat 1.0 [--preview p.png]   # pass 53: a strip recoloured frame by frame (the Red Goblins from the goblins)
python tools/recolour_look.py --id <creature> --from <CODE> --code <NEW> --passes "<recolour_strip flags>" ["<pass 2>" ...] [--note "..."] [--write]   # pass 131: a recolour look start to finish (the passes on the strip and the icon, a preview sheet in tools/dl/recolour_look/, --write adds the pictures and the entry with recipe.recolour_of + recolour_passes; black to grey or white is --mode lift --ranges 0-360 --min-sat 0 --max-sat 0.32 --min-val 0.035 --max-val 0.3 --src-hi 0.2: CC-C, CC-D); the Level Editor's "Recolour an existing look" does the same from its form (presets, a before / after)
python tools/pose_hang.py <driver dir> <out dir> [arms=rl|l|r out=0.03 swing=0.25 views=back,bd]   # pass 131: a pose driver whose arm(s) hang at the sides in the back views with a small swing (SK-F: a bent arm painted a second hand on the poncho; KN-D: the shield arm left the shield); never run `gen_art.py --help`: it has no help and starts a full run
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
"$GODOT" --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/wanted_shots.gd -- out=<dir> [only=title,hud,...] [white=1] [inset=130]   # every screen state (inset=N shows the screens under a camera cutout)
python tools/wanted_compare.py <dir>/<state>.png <mock-name> [--diff] [--crop=x,y,w,h]   # a render beside its PNG in design_handoff_88fits_wanted/screens/
"$GODOT" --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/perf_late.gd -- build=six   # late-game benchmark: ms per system and draw calls (--fixed-fps 30 = a phone at 30)
"$GODOT" --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/screenshot_run.gd -- out=<dir>   # windowed, silent, ~60 PNGs for the bible (make_bible.py --shots=<dir>); without --resolution the window override gives 432x768
"$GODOT" --path D:/_projects/88fits/game -e                     # open the editor
JAVA_HOME=D:/_projects/88fits/tools/jdk17/jdk-17.0.20.1+1 "$GODOT" $P --export-debug "Android" export/88fits-debug.apk   # signed debug APK
bash tools/ship.sh [--quick] [--no-install] [--no-pc] [--no-aab]   # checks -> signed APK -> install + launch on the phone (adb over USB or Wi-Fi) -> PC exe -> (pass 119) the Google Play .aab (ship_play.sh: version code +1), all three to Drive
bash tools/ship_prod.sh [--no-drive] [--quick] [--no-pc] [--no-android]   # pass 81: the PRODUCTION build, ONLY when Garry asks (skill ship-prod): a pruned, optimised staging copy (tools/dl/prod/stage/game; tools/prod_stage.py, game/tools/prod_plan.gd + prod_reach.gd, tools/prod_prune.py [--selftest], tools/prod_optimise.py), its checks (game/tools/prod_check.gd, smoke_run, prod_run_check.gd), presets "Android Prod" (com.eightyeightfits.game.prod) + "Windows Desktop Prod" (feature `prod` -> Settings.is_prod(): no debug surfaces), tools/prod_probe.py (the exe's cold start), report tools/dl/prod/out/report.md, Drive 88fits-prod.apk/.exe
bash tools/ship_play.sh [--no-drive] [--keep-code]   # 2026-10-31: the Google Play upload, the dev game as an .aab (preset "Android Play": package com.outlawsurvivors.game, permanent; label "Outlaw Survivors"; Gradle build in git-ignored game/android/, target SDK 36; upload key = the project keystore); raises version/code each run -> game/export/outlaw_survivors.aab + Drive; Internal testing track only for now
bash tools/release.sh "note"                                      # upload the APK as the next GitHub release in the private builds repo (needs gh auth login once)
python tools/make_win_icon.py [--if-stale] && python tools/exe_info.py game/export/88fits.exe --expect-version 0.59   # pass 73: game/icon.ico (16..256, framed per size) for the PC exe; Godot 4.5+ embeds the icon and version itself (rcedit is obsolete); exe_info reads the exe's version resource
powershell -NoProfile -ExecutionPolicy Bypass -File tools/sign_exe.ps1 -Exe game/export/88fits.exe   # pass 73: signs the PC exe only when tools/keys/codesign.env exists (git-ignored; a .pfx, a store certificate or a signing service); ship.sh calls it and keeps a failed signing out of Drive; why Windows warns and what fixes cost: docs/pc_build_trust.md
python tools/gen_textures.py && python tools/gen_music.py && python tools/paint_pass.py   # art + music regeneration (see docs/RUNNING.md)
python tools/gen_sand.py   # pass 82: the four new sands (Klein paintings, seam repainted in three passes, today's mean colour) -> game/art/env/sand_<id>.png, sources tools/art_src/sand_<id>_src.png; the map key timeline_data.sand picks one (default pass81 = sand.png), the Level Editor's World card and the arena's WORLD tab switch it
python tools/gen_prop_variants.py && python tools/prop_shadows.py   # pass 83: painted prop variants (Klein, the style anchor + the original's raw render; props.json `variant_of`, `weight`; PropField picks by a hash of the spot) and every painting's ground shadow (props.json `shadow`: width, depth, offsets, strength)
python tools/gen_totem_icons.py   # pass 83: the totem gifts' carved segments (a head painted on green in the pole's style, keyed and laid on one cedar block) and the crest -> game/art/ui/totem/spirit_<id>.png, crest.png (usage in its header)
python tools/make_pipeline_figs.py && python tools/make_bible.py   # bible section 15b's step-by-step art pictures (from tools/dl/ intermediates), then the bible
python tools/make_onepager.py [--pdf] [--force]   # the kick-off one pager (2026-10-26): docs/onepager/src/onepager.html + content.json + pictures.json -> docs/onepager/88fits_OnePager.html (self-contained) and, with --pdf, the PDF through headless Edge; pictures cut once into docs/onepager/img/
bash tools/godot.sh --audio-driver Dummy --resolution 1920x1080 --path D:/_projects/88fits/game --script res://tools/marketing_shots.gd -- out=<dir> shot=swarm|nightfall|bloodmoon|boss|play|horde|bestiary|ui|scout   # staged in-engine marketing stills, frozen and captured (every argument in its header; 1080x1920 for play, horde, ui; bounded by a watchdog)
GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/store_shots.gd -- out=<png> hero=drifter stage=1 crowd=lesser_scorpion:1100 layout=ring clear=2.8 freeze=walk band=0.185 zoom=0.65 fire=0   # pass 110: a staged store screenshot from the arena (every argument in its header)
python tools/make_store_shots.py --plan docs/store/plan.json   # pass 110: the Google Play set: raw captures + a caption band (torn Wanted paper, a colour a shot) -> docs/store/0N_*.png
python tools/add_left_sets.py --id cyclopean_mummy --looks CM-F|all [--force] [--dry-run]   # pass 111: a look's left-heading sets (idle_l, run_l, attack_l, hit_l, run_bl, idle_bl) as copies of its right-heading frames, so it never mirrors; edit either row by hand or in the Frames view
python tools/skin_stills.py   # pass 111: the full-body stills the hero sheet's LOOKS tiles show, cut from each skin look's strip (then --import)
python tools/ai_sfx.py [--dry-run | --gen-only | --auto | --bind | --report | --docs | --only ids | --cands N | --pick id=k | --volume id=dB]   # pass 60: every sound effect from Stable Audio (Garry's app at http://127.0.0.1:7861/, AudioGen on 7860 as the alternate) -> content/sounds/real/<id>.wav + the soundmap rows; then --import + import_json -- only=sounds; python tools/make_sfx_review.py -> docs/sfx_review.html + tools/dl/sfx60/sfx_review.zip (the voice barks are gone; gen_voice.py lives in tools/dl/backup/)
python tools/icon_sand.py [--gamma 0.8] [--splash] [--compare out.png]   # pass 61: the launcher icon's sand a touch lighter (only the sand; the old source tools/dl/app_icon/icon_src_v046.png), then gen_art.app_icon and make_splash
"$GODOT" --audio-driver Dummy --fixed-fps 60 --resolution 504x1122 --path D:/_projects/88fits/game --script res://tools/_p61_pk_bench.gd   # pass 61: the pickups benchmark (N gems lying, the hero walking, a vacuum): ms a frame for "pickups", the whole frame, draw calls
"$GODOT" --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/difficulty_probe.gd -- t0=300 secs=130 stage=0 level=22 build=b1 trail=none hero=calavera seed=11   # pass 62: how hard a stretch of the run is for a fixed build and Trail Level (pass 129: `trail=none|quarter|half|full|<level>`, game/tools/trail_arg.gd; `mirror=` is the old name): HP lost a minute net of healing, per source, kills, the crowd against the cap
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
- An additive (`blend_add`) spatial shader gets the scene's fog added on top: a faint glow turns into a solid tube. Give
  every additive effect shader `render_mode ... fog_disabled` (pass 113, the Brander's fire pillar).
- In the Compatibility renderer a MultiMesh with custom data but no instance colours multiplies the shader's vertex
  colour by the custom data (near-black paint): turn `use_colors` on and set every instance colour white (pass 115).
- A static function on a `class_name` script must not be named like a method of Script, Resource or Object: `Trail.reload(path)`
  called the engine's `Script.reload` (pass 129: it is `Trail.load_from`); a local named `_set` in a SceneTree tool collides with `Object._set`.
- Godot front faces are **clockwise**. A SurfaceTool mesh wound counter-clockwise is silently back-face culled; the terrain rendered as the sky's lower half for hours before anyone noticed. Check winding first when a generated mesh "has no texture".

## Architecture

- **Autoloads** (`core/autoload/`): `Registry` scans `res://content/**` at boot (prefers `<id>.tres`, falls back to `<id>.json`), `Save` (one JSON file in `user://`), `Settings`, `Audio` (sound ids from the sound map, voice-limited, layered music), `Run` (state of the current run: XP, gold, weapons as `WeaponInstance`, passives, evolution logic, chest logic).
- **Data classes** (`core/data/`): `Effect` {stat, op add|mul|set, value, target} is the only way numbers change. `WeaponDef`, `PassiveDef`, `EnemyDef`, `EliteModDef`, `CharacterDef`, `ShopUpgradeDef`, `QuestDef`, `MapDef` + `WaveTimeline`, `SoundMap`. `JsonContent` converts JSON to these; `tools/import_json.gd` writes `.tres`.
- **Stats**: `StatSheet` = (base + Σadd) × Π(1+mul) with sources kept for the pause screen breakdown. `WeaponInstance.rebuild()` folds player multipliers (might, cooldown, area, amount, targeted passives) into each weapon's sheet. `TextGen` generates every card, pause and collection description from data.
- **The compiled crowd** (`native/`, pass 125): `EnemyManager.gd` owns the rules and the data; a GDExtension (`CrowdCore`, `game/bin/`) reads and writes its packed arrays in place and runs its hottest loops (the grids, who is drawn, a plain walker's and a dying body's tick, the push, most of the draw), handing anything else back in index order. A run plays the same with it or without it (no library, `Settings.native_crowd` off, or `native=0`: the script runs everything). **A rule changed in the plain walker's path (`_physics_process`, `_steer`'s chase and flock, `_tick_tail`, `refresh_drawn`, `_rebuild_grid`) must change in `native/src/crowd_core.cpp` too**, with the script's number types (GDScript float a double, Vector3 part a float), and `_p125_NATIVE_proof.gd` catches a difference; a new per-creature array the walker reads goes in `_nat_arrays`.
- **Game scene** (`game/Game.gd`): wires map, player, camera, `EnemyManager` (packed arrays + one MultiMesh per enemy type, camera-facing billboard shader in `core/shaders/`), `ProjectileManager`, `PickupManager` (gems/coins MultiMeshes, a growable pool, a grid of lying pickups, magnet and vacuum, chests), `Telegraphs`, `Fx`, `WaveDirector` (live cap, roster, events, boss, portal, stage clock), weapon behaviours (`core/behaviors/`: ProjectileEmitter, Orbiter, Lobber, Beam, LaserBeam, Thruster, Smasher, ConeWave, GravityGun, MissilePod, MineLayer, SunScepter, Spawner+Turret) and the in-run UI (`ui/HUD`, `CardScreen`, `PauseScreen`, `PortalDialog`, `Hints`, `DebugPanel`).
- **Content folders**: `content/<type>/<id>/` holds `<id>.json` (authoring source), `<id>.tres` (generated, Inspector-editable), optional `<id>_visual.tscn` (weapon meshes/particles: nodes named `Projectile`, `Held`, `Muzzle`), `<id>_icon.png`, `<id>_sprite.png` (animation strip in the fixed order idle, run, attack, hit, die / characters add turn, cheer). `content/sounds/soundmap.json` binds sound ids.
- **Map**: `world/MapBase.gd` provides `height_at`, obstacle circles, flats centre; `world/maps/red_canyon/RedCanyon.gd` builds Red Canyon (Dry Gulch is shelved in `tools/dl/backup/`).
- **UI kit** (`ui/wanted/`, pass 39, the Wanted design): every screen is built in code from one set of components (`W` tokens and fonts, `HardBox`, `WText`, `WTap`, `WButton`, `WPlate`, `WSeal`, `WMarks`, `WCard`/`WItem`, `WModal`, `WMenuHeader`, `WTabs`, `WSlider`, `WSwitch`, `WChoice`, `WRow`, `WPlaceholder`, `WToasts`, `WBanner`, `WPointer`, `WBar`, `WCelebrate`, `WConfirm`); no screen draws its own version of a component. The old `UiKit` remains in the arena panel, the debug hand and the in-run debug panel, for `WItem`'s card text, and as the colour names `Game.gd` hands to toasts (`WToasts.tone` maps them to green, purple or paper).
- **Hub screens** (`ui/`): `TitleScreen` (with play setup), `CollectionScreen`, `TrailScreen` (the Trail, pass 129), `HeroesScreen`, `StagesScreen`, `ResultsScreen`, `SettingsScreen` extend `ScreenBase`; `DevMenu` (held version line in Settings) stands alone.
- **The Trail** (`core/systems/Trail.gd`, pass 129; static, plain JSON `content/trail/trail.json`, contract `docs/trail_schema.md`): the one permanent progression. Every lock in the game asks `Trail.gated` / `Trail.has` first; its bought upgrades fold into `Run.hero_sheet` as sources `trail:<type>`; `core/systems/Nav.gd` is the way back from a "Reach Trail Level N" tap (a screen offers `nav_state()`).
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

## Status (2026-11-06, pass 131, version 1.00)

What is true now, in short. The why and the detail of every pass (1 to 65) is in **`docs/HISTORY.md`**: search it for a
symbol, file or pass number when you need background (`grep -n "PickupManager" docs/HISTORY.md`); do not read it whole.
After each pass: append the pass's paragraph to `docs/HISTORY.md`, and update this section only where what is true
changed.

**Shipping.** `bash tools/ship.sh` -> signed release APK -> `E:/My Drive/88fits builds/88fits.apk`, then a PC build (the "Windows Desktop" preset, one `88fits.exe` with the game embedded) -> `E:/My Drive/88fits builds/88fits.exe` (`--no-pc` skips it; iOS was looked at and dropped: it needs a $99 Apple developer account) (Garry plays on the
phone, often away from the PC; see `docs/RUNNING.md` and the ship-to-phone skill). ship.sh runs import, import_json, the
parse check, all gdUnit tests (~3,170 in `game/tests/passNN_*_test.gd`), smoke_run, arena_check and touch_audit. Also run
`hell_check.gd` after Blood Moon changes. Version in `application/config/version` (1.00). The PC exe carries game/icon.ico and
the game's version (Godot embeds both; pass 73) and is signed only when tools/keys/codesign.env exists (docs/pc_build_trust.md).
Pass 81: the dev build's label is "88fits Dev" (packages unchanged); the **production build** (`bash tools/ship_prod.sh`,
skill ship-prod: no debug surfaces via `Settings.is_prod()`, only the content and looks the game can show, music as
Ogg; package com.eightyeightfits.game.prod, label "88fits", its own PC save folder; Drive 88fits-prod.apk/.exe) is
made **only when Garry asks**; analytics events carry `build: dev|prod`.

**The game.** One map, **Red Canyon** (`world/maps/red_canyon/RedCanyon.gd`): noise terrain, one dry river and two or three oases
rolled per run from `Run.map_seed` (pass 80: `oases`, water slows walking by `water_slow` 10%), sand to a western
sandstone fort wall (pass 80, `CanyonWalls.gd`) with the red-rock cliffs behind it; everything but the ground, the wall, barrels, signs, the map's dressing (pass 126: telephone poles, wagon wheels, grave crosses) and a few
movers is a painted 2.5D billboard (props `art/sprites/props/`, structures `st_<id>.png`). Four stages, each its own run since pass 87
(pass 126's order: Sundown 7:10 to the Tumbleweed King, Nightfall 10:00 to the Gila Grande, The Dust Bowl 13:00 to Black Sunday, Blood Moon 16:00 to the Brander; the last is "hell": a red
ground and a hell channel of creatures on its own cap; the tests' and tools' older "stage 3" means it), each followed by a portal countdown and Endless. The timeline (`content/maps/red_canyon/red_canyon.json`
`timeline_data`: cap curve, roster rows, waves, events, specials, HP/ATK curves, scaling) is **Garry's to edit in the
Level Editor** (`tools\level_editor.cmd`, `docs/level_editor.md`, schema `docs/waves_schema.md`; since pass 66 the same
page also creates and edits enemies, heroes and items and queues their art for the local AI: the Enemies / Heroes / Items
/ Jobs tabs, `docs/level_editor.md` "Pass 66", keys in `docs/assets_schema.md`, rules in BALANCING.md §13); stage 1 is his own
work (pinned by `pass62_pc_test`), stages 2-3 were written in his style in pass 62 and tuned in pass 64 so stage 2 was clearable with a quarter of the old Upgrade board and stage 3 with half (`tools/difficulty_probe.gd`; pass 129: the Trail opens the Dust Bowl and Blood Moon where its power matches those, BALANCING 71). Enemy strength = base x
`stage_mults` [1, 2.2, 3.34] x the HP/ATK curve at the row's start x (1 + level_*_per_level x (hero level - 1)) x
`creature_*_mult`, fixed per row from its start. Specials (pass 69): a third as often as before, x10 HP, x2 ATK, x1.25
size, a glowing rim in a colour Garry sets per creature (`variance.special`, map default `special_defaults`); one forced
special Red Goblin (a swarm event with `special: true`). Pass 72: specials x1.5 size, x15 HP, a 35% chest, at most 3 alive (pass 110: a sure chest, 1 alive, x3.5 ATK)
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
Pass 109: a kill counter under the clock (ui/wanted/WKillCount.gd, a jawless skull, dings that grow with the kill rate,
no sound); the first-run Dynamite offer (core/systems/FtueDynamite.gd: lob_grenade among the cheapest cards at the first
level-4 card screen of every run until picked once); weapons' attack speed 85% / 92.5% of the old at levels 1 / 2, as
before from 3 (BALANCING 52.ATKSPD, tools/check_attack_ramp.py; orbiters out); the Raider's rocket in hazard stripes with
a beacon, outline and x-ray (rocket*.gdshader); the Rocket Pod pitches up and fires up; the Dragon's Breath as particles
(core/systems/BreathFlames.gd); armadillo ARM-F/G repainted (fresh), Cyclopean Mummy CM-D/E (fresh); depth drivers `zoom=`.
Pass 110: regular creatures' chests 0.0002, specials always drop one but come a third as often (max_alive 1) with x3.5
ATK; Elite/boss coins halved; the Upgrade board's rank k costs k^2 x rank 1; heroes 500 x title place (BALANCING 53.ECON);
**boss fight windows** (`stage_list[k].boss_fight`: only its rows spawn while the boss lives, a 120 s loop under its Max
count; the Level Editor's Boss fights section; 53.BOSS); hero blasts in their own FX pool (Fx.blast, blast_fx.gdshader);
the breath behind the hero facing away; the arena's SHOTS tab, time 1/2 and 1/4, FREEZE, screenshot framing, HIDE UI
(53.ARENA; game/tools/store_shots.gd); the store screenshots in docs/store/ (tools/make_store_shots.py --plan
docs/store/plan.json); CM-F/G (fresh); the armadillo's shadow; `GODOT_TIMEOUT=<s>` on tools/godot.sh kills a hung Godot.
Pass 111: the **Bounty Board** (content/wanted/wanted.json, WantedBoard/WantedRun, paid when done; the Level Editor's
Wanted tab; 54.WANTED; since pass 112 three posters float in over the run after the descent, ui/BountyPosters.gd); **skins** (`variants[CODE].skin`,
the hero sheet's LOOKS row, quests with beat_stage) and the **currency layer** (content/currencies, core/systems/Currency.gd;
only gold; 54.SKINS); left-heading strip sets (tools/add_left_sets.py; the Cyclopean Mummy never mirrors, plays CM-F);
the Spit Cactus's black bomb; `far_speed`; the harpoon's chain (54.ENEMY). The Level Editor server needs a restart after
this pass (new routes).
Pass 112: the **Monk** (content/enemies/monk, brain `squad`: squads of 10/20/30 that move, stop and fire blue energy spheres
as one; core/systems/Squads.gd, EnergyOrbs.gd; looks MK-A brown plays, MK-B white, MK-C dark blue; on no map; 55.MONK);
pass 111's map chests reverted, **barrels** come back off screen and may throw out a power-up (`timeline_data.barrels`,
core/systems/BarrelSpawns.gd, the Level Editor's Barrels card; 55.BARREL); the harpoon's chain snaps; the hero's run
cycle follows his real speed; Warmup pre-draws the bomb, harpoon and orbs (55.ENEMY); pose_driver `arms=clasp`.
Pass 113: **seven new task types** for quests (unlocks, skins) and Wanted posters (damage with a weapon, HP restored by an
item or by a power-up/structure, an item to level N, barrels, totems, fire/poison damage; core/systems/TaskTally.gd banks
a run's tallies at its end; 56.TASKS), each with its picture (art/ui/wanted/barrel.png, poison.png); **boss bullet heaven**:
custom attack kind `pattern` (core/systems/BossPatterns.gd, BossPatternFx.gd; content/boss_attacks/royal_dust_devil,
venom_monsoon, hellbrand_mandala; rare: not before 15 s, at 60% HP or 45 s, then 45 s apart; a 2 s tell, guarded x0.2,
dazed x1.5; 56.BOSS); dust devils rare and tornado-shaped (core/systems/DustDevils.gd, TornadoFx.gd,
`timeline_data.dust_devils`; 56.TWISTER); the Monk's volley flies as one cloud, 5 m/s, 26.25 m; a locked look is a dark
silhouette; a look's goal met at a boss's fall is announced in the run (56.LEAD).
Pass 114: **replays** (57.REPLAY, analytics/howto/04_replays.md): the full game is deterministic (rule rolls on
core/systems/Dice.gd seeded by `Run.run_seed`, the global stream only for looks; rule timers and `_process` deltas through
core/systems/Lockstep.gd: new rule timers use `Lockstep.after`, new rule dice `Dice.r`); core/systems/RunReplay.gd records
every run (frames, stick, the hero's place, decisions by id, taps, checksums; `run_replay` to PostHog with consent);
game/replay/ReplayViewer.gd plays it on the build that made it (ship.sh stamps game/config/build.json and keeps the exe in
git-ignored builds/<id>/, tools/builds.py; `python tools/replay.py --latest`, tools\replay.cmd: header, drift light,
0.1x-8x, a seekable progress reel, finger rings); the Level Editor's JSON windows are editable (json_edit.js), every Save
writes at once and names the Godot lock's holder in plain words (ship.sh takes it as "the build"); the bullet heaven
twice as long and far with more room, its trigger `[min, max]` ranges (57.EDITOR, docs/howto/boss_bullet_heaven.md);
the Spit Cactus's Bombmaker looks SC-B/SC-C (fresh).
Pass 115: the name on screen is **Outlaw Survivors** (`W.GAME_NAME`; code, packages, launcher labels and files stay
88fits); the dashboard's Upgrade board, Hero level and items, Each weapon's real DPS and Health 5 s at a time cards
(record schema 5: `hp_min`, `board`, `weapon_sources`; Danger replaced in the Sim charts too), the replay's board panel;
bullet heaven x1.5 faster inside a per-boss **barrier** 14 m round the boss (core/systems/BossBarrier.gd; the attack
waits for the hero in reach; 58.BOSS, 58.LEAD); the King's stomp 7.5 m, the Gila 3.75 s under; `far_speed` a capped
ramp (x3 by 36 m, never past 6 m/s); dust devils 60-90 s; Nerve's Second Wind is revive health only (40% base via
TalentDef `base_stats`, 100% at six; Nerve 150 gold a first rank).
Pass 116: barrels are three painted billboards (EXP, EXP + Coins, Power-up; only the last throws power-ups; tools/cut_barrels.py);
Endless grows at `endless.open_task_growth` 0.33 while a Wanted poster is open (tell Garry if Endless feels odd); the Gila's
red ring 3 s on a locked spot; May's Invisible Box (perk special `box`, MimeBox.gd); Monks x2 range; WaveDirector's dice in
four streams (spawn, Elite, special, drop) and a fresh seed every run (the stages' "same map"); stage 3 rows s3a1..s3g2;
Results pays the bounty in coins on screen; the app icon is Garry's gunslinger picture (tools/make_app_icon.py); Level
Editor Mirror tab, Re-roll icon, stage-relative times; docs/ui_review rebuilt (tools/make_ui_review.py, ui_review_capture.sh).
Pass 117: a smashed barrel's painting comes apart (core/systems/BarrelDebris.gd: a stump, a lid and staves that lie 6 s);
the Watch's Weapon DPS tab (F, game/tools/watch/WatchWeaponDps.gd; the dashboard's card since pass 115); the app icon from
Garry's Gemini picture (tools/make_app_icon.py, also game/icon_512.png for the Play listing); check_scripts skips .gdignore
folders (game/android/build). Google Play: `tools/ship_play.sh` (Internal testing, com.outlawsurvivors.game), the privacy
policy docs/privacy/ (GitHub Pages), feature graphics docs/store/feature/.
Pass 118: the **loading screen** is saloon wallpaper and a title drop (game/ui/Boot.gd: no icon, no bar; the boot splash is plain
paper, art/ui/splash.png gone, the Android splash icon transparent; tools/make_loading_wallpaper.py -> art/ui/loading/; six strips
scroll up and down in turn and drift right, the OUTLAW / SURVIVORS plate lands, the title is built after it, never before 1.2 s);
crowned Elites drop the **purple chest** (mutation reel + call-in); each **boss drops its own chest** holding its purse, coins and
XP x a speed bonus (`timeline_data.boss_chest`; 3D boss_chest_<boss>.glb by tools/blender_boss_chests.py, painted frames by
tools/gen_boss_chests.py in art/ui/wanted/bosschest/, the boss JSON's `boss.chest`), opened in game/ui/BossChestScreen.gd (a jackpot
spew into GOLD and EXP counters, ui_bosschest_tune, CLAIM pays the counters exactly); the chest's beam and sunburst stand behind it,
its glint a soft sparkle, the lid back on top; creatures outside a standing boss barrier watch and never attack
(EnemyManager.onlook); new items Jade Key / Ruby Key (epic: every chest opened banks luck / damage, `chest_<stat>`,
Run.chest_opened) and the Grindstone (the first legendary passive item: extra random bonuses on weapon level-ups, its JSON's
`params.grind`); Beer shows as Ghost Pepper (id beer); every hero's own weapon may be found by anyone (`guest_weight` 0.45);
twelve legendary item proposals at https://claude.ai/artifact/Tr7hkvsLQd1wZuHS4XCGp7; the app icon from Gemini_Generated_Image_in0heein0heein0h.jfif.
Pass 119: the loading plate **punches** in (2.6x to its size in 0.12 s, a hit-stop flash, shake, shockwave, chips; Boot.entrance
keeps a `split` option); the menus are **Painted** by default (Save._migrate_painted once; the debug panel's switch outside prod);
after a pause the stick **carries its push** if the thumb comes back within 1 s (PlayerInput CARRY_WINDOW / CARRY_FADE), movement keys
resume the PC's tap-to-go gate; card icons lean by the job field `lean` (every line card's B recipe 10 degrees); ship.sh builds the
**.aab** too (`--no-aab`); six legendary passive items: the **Iron Horse** (core/systems/IronHorse.gd, a ghost train down the hero's
line) and **Personal Storm** (core/systems/PersonalStorm.gd), mutually exclusive by PassiveDef `excludes`; **Lightning in a Bottle**
(crit arcs, EnemyManager.crit_arc), the **Undertaker's Shovel** (core/systems/Graveyard.gd: graves and ghost gunmen), **Fool's Gold**
(the purse as damage), the **Pocket Bible** (a hit cap, bosses 35%, a block); the Grindstone is rare and levels the weakest weapon
or evolves one; EnemyManager.HIT_NO_CRIT; the Dragon's Breath's ready ring gone (a mouthful splash); armadillo looks ARM-H..M (zombie,
devil; fresh) and ARM-F/G's front walk without the leg-tail (blender_gait `splay_front`); gen_ctl `look_refs`, `extras`; the Gila's
chest white with lizard eyes, both bosses' chests hollow, the chest pop-up's loot party.
Pass 120: the Undertaker's ghost is one painted floating ghost (front/back, circling its grave) firing ghost bolts
(core/systems/GhostBolts.gd) whose count (up to 6) and damage grow with HeroPower, no knockback; Personal Storm every 45 s,
the Pocket Bible one 35% cap, the Iron Horse every 30 s with twice the warning at 22.5 m/s; a row's `special: true` makes a
creature with no variance block its special (map `special_defaults.tint`, else EnemyDef.SPECIAL_TINT) and with an `elite`
both at once, never waiting for colour (WaveDirector.colour_open_for); every way into a run plays the revolver-cylinder
wipe and Boot's loading screen (game/ui/RunCurtain.gd, UiFx.go_run; Game.SPAWN_MAX_STEP); the Level Editor's row card
shows SPD, Pacing and Pattern, Spawned so far counts guaranteed Elites and specials; replays never drag a fallen hero
(safety net, a red line when the run ended early), keep step at any frame rate (tweens stepped by the recorded delta),
record the debug hand/panel and TAP TO GO keys, and name the game files' fingerprint ("the game changed since").
Pass 121: the **Grindstone** is a one-shot (`single`, one level, once a run: `Run.grind_used`, `Run.spent_words`, "(used)"
on the pause screen) whose deed plays a show (game/ui/GrindMoment.gd, Game.Modal.GRIND: a wheel drawn in code, the weapon's
icon held to it with sparks, LEVEL n -> n+1 or EVOLVED; taps recorded as `grind_hurry`; timings and sounds in
`params.grind.moment`, sound it_grind); the ghost is a plain sheet ghost with no clothes (params.grave `ghost_fade`, the tail
fading out; sprite_billboard_over.gdshader `ghost_fade`); **no legendary item is offered before 4:30** of any stage's clock
from any source (core/systems/LegendaryHold.gd, map `timeline_data.legendary` {from 270, guarantee_at 0 = off}, per stage
`stage_list[k].legendary`; the Level Editor's Settings card "Legendary items" and the stage cards).
Pass 122: **Stage 3 reads**: the Blood Moon's sand lighter (filter strength 0.42, terrain `hell_mul` / `hell_add`, RedCanyon
HELL_*), barrels drawn as before (pass 122's pale rim off, `RIM_HELL` 0), **fire tornadoes** (map
`dust_devils.hell`, TornadoFx `fire`), seven recolour looks played by the stage-3 rows (IMP-A, RG-C, RR-C, HG-E, KN-F, DM-J,
BD-B, fresh; plus ANT-G, MK-B, BB-F; recolour_strip `--cells`); the Phoenix revive shows the feather (Run.phoenix_item); the
Explosive Elite's boom is a real blast (Fx.BLAST_ELITE, Game.ELITE_WARN); the **Royale theme**, first checkpoint, behind
`Settings.ui_theme` (wanted default, prod-locked; ui/wanted/R.gd, Ultra + Rubik, the item-frame shaders ui_radial_fill /
ui_rays / ui_rainbow_rim, `W.royale()`): the kit, the HUD (`Settings.hud_slot_rarity`), the level-up and the chest; toasts,
banners, TAP TO GO, the kill counter and the boss bar stay Wanted (`W.wanted_text`, `HardBox.themed`); pictures in
docs/ui_review/royale_p122/; the weapon/Card rarity tiers are a proposal for Garry (tools/dl/p122/LEAD/rarity_tiers.md).
Pass 123: **every screen under Royale structurally as Garry's picks** (ui/wanted/WTabBar.gd, RoyaleBackdrop.gd + art/ui/royale/
by tools/gen_royale_backdrop.py, ui/HeroesScreen.gd, WConfirm.shell, ScreenBase.board_sheet / tab_bar, core/systems/Crumbs.gd:
red crumbs seen once tapped, save `crumbs`; Wanted still the default, prod held there); **a seventh Upgrade rank** (`ranks` 7, 49 x
rank 1, TalentDef.top_mult, Save.talent_top; Second Wind past 100% buys untouchable time); the boss barrier 18.9 m; the Gila's Poison
Rain; a `death_burst` body lies until its blast; the Shaman's green numbers (DamageNumbers.creature_heal). BALANCING 65.
Pass 124: **the old UI is gone** (`Settings.ui_theme`, `menu_style`, `W.royale()` and every Wanted branch removed by tools/dl/p124/LEAD/strip_theme*.py and prune_dead.py;
prod shows Royale too, `hud_slot_rarity` locked on); the hero runs in and out on a diagonal (TitleScreen `_run_in`, `_run_off`, HeroFigure, FigureShadow); prop and hero shadows are their
own silhouettes (core/shaders/ui_backdrop_shadow.gdshader; `foot_up`, `foot_x`, `foot_w` in backdrop.json) and the backdrop's props are hand-placed (gen_royale_backdrop PROPS_LAYOUT); mutations have
their own frame (cut corners, near-black face, rose rim: R.MUTATION, WPlate shape 2); a short price is grey with the amount in red (R.SHORT_INK); a dark loading screen with the new wordmark
(Boot.palette, Boot.DARK, make_loading_wallpaper.plate; the same colour in project.godot, export_presets, Boot.tscn); the debug REVIVE on Down!. BALANCING 66. Waiting on Garry: his pick from
the performance report docs/perf/stage2_slowdown.html (published https://claude.ai/artifact/QtndhuRSrhw7ym6wHQBZAN; `python tools/make_perf_report.py`; pass 125 re-ranked it from his Stage 1 run: the phone slowing to about two thirds, then 60%, is the main cause, proven against a PC replay of the run by game/tools/_p125_PERF_replay.gd; options B, G, A, C, I first) and the ideas book docs/ideas/outlaw_ideas.html
(https://claude.ai/artifact/PNss4jA7mfqngzVbSZNpMH; words docs/ideas/content.py, art tools/gen_ideas_art.py, page tools/make_ideas_doc.py).
Pass 125: **the crowd in compiled code** (option C; see Architecture; at 300 creatures the crowd's cost 4.2 -> 0.7 ms on the PC, 800 creatures cost what 300 did; not yet measured on the phone: run records carry `native`; the developer menu's Compiled crowd compares); option D is the map's `timeline_data.crowd` {steer_every, steer_far_every}, measured and left at 2 / 4 (1% saved, 18-26% more overlap). The PC build's `crowd.windows.x86_64.dll` sits beside the exe (Drive, builds/<id>/). The pool stays `EnemyManager.MAX` 320 under the map's hard_cap 500: raising it is Garry's call after phone numbers. BALANCING 67.

Pass 126: **The Dust Bowl**, stage 3 of 4 (`dust`, 13:00 after Nightfall; Blood Moon stretched to 16:00, index 3): `stage_mults` [1, 2.2, 2.05, 2.05] with the HP curve on the absolute clock, new stage keys `reward_mult`, `speed_mult`, `weather` (fog, world/features/DustHaze.gd, stronger gusts, swaying props and wire; RedCanyon.set_weather), a stage's own `dust_devils` (more often, bigger, `fling` x2); its boss **Black Sunday** (attack `whirl`, core/systems/BossWhirl.gd: he becomes a tornado, lifts and hurts his own crowd, then stands dazed at x1.5; bullet heaven `black_blizzard`, barrier `cross_fence`, chest Collection Box); fodder Straw Man, Carrion Crow, Dust Bunny; rows d1a..d6j, `boss_fight` bfd-1..6; `Save._migrate_dust_bowl` (old Hell beaten counts the Dust Bowl as beaten). **The map's dressing** (core/systems/MapDressing.gd, TelephoneLine.gd, `timeline_data.dressing`, JSON only, its own dice off the map seed): one broken telephone line, a toppled cart in 75% of runs with 1-2 3D wheels, 2-6 grave sites; none but the cart has a collider; `rock_small` has none now. **Twelve skins** (DRI-B/C, AST-B/C, CAL-B/C, IRN-B/C, SOL-H, FAD-G, BUC-G, MAY-S; base codes DRI-A, AST-A, CAL-A, IRN-A; goal quests `skin_*`, all fresh; QuestTracker.skin_of_a_hero_not_owned). Items **Assayer's Scale** (a skip pays, Run._pay_skip) and **Canteen** (water no longer slows, leaving heals, Player._tick_canteen), life steal a quarter less (`thirst` 1.125%, `bloodthirst` 6%, caps 3% and 6%). The Heroes screen's two lists (a fixed two-row picker, the page above with WScrollThumb), no evolution among a hero's items, the menu hero x1.15 (`RY_FIGURE_H` 368) fading as he runs off, shadows at the soles (`TitleStage.FIGURE_SOLE`), Ultra on every tab, a coin on the buy buttons. `gen_art.py` writes the launcher icon only with `--app-icon`. A row's `stats.size` is absolute, never a multiple of the base. BALANCING 68. Waiting on Garry: Blood Moon's raised pay, the Dust Bowl's coins x3 (the Upgrade restructure was answered by pass 129's Trail).

Pass 127: Black Sunday is a quarter smaller and pulls instead of charging: built-in attack **`come_here`** (core/systems/BossComeHere.gd, telegraph `rect`, `Player.pull_leap`, `Fx.pull_dust`; no damage); `spawn_ring` `looks` (each ring its own random split, `EnemyManager.look_split`); the toppled cart repainted from a Blender model (tools/blender_cart.py); walk **Fly** (gen_art `walk: fly`, death `fall`; the Carrion Crow plays CC-B, no blue, `EnemyDef.flies`: no rise out of the sand); Dust Bunny DB-C, DB-D on some Dust Bowl rows; the menu hero's soles stay on the shadow's line (core/systems/FigureSoles.gd, art/ui/figure_soles.json); the Heroes screen's sheet clear of the header and apart from the picker's tray, a different hero's tile resets the page at once; the tab bar's closed tabs their own indigo (`R.DOCK_ROLE`); the player reads "Skins" everywhere a hero's look is sold or worn (the Level Editor and the arena keep "look" for any art variant; node names and save keys unchanged). The design bible and the UI reference rebuilt with every picture fresh (the bible 14.75 MB, 192 pictures; the UI reference 40 records, 101 captures). Where the data has moved past an older line here, the data holds: `boss_hp_scaling.seconds` King 40, Gila 60, Black Sunday 70, Brander 80; the Monk is on rows r62, r64, r66, d5b, s3c1 and the Desert Spider on r22, r68; the Armadillo is on no row; `cap_max` and `hard_cap` are 500 and the pool of 320 is what really holds; the HP curve plays its formula (exponent 1.35) while `hp_power` still stores 1.25. BALANCING 69. Waiting on Garry: everything listed under "Still waiting on Garry" in docs/HISTORY.md pass 127.

Pass 128: the player, the arena, the Watch and the Level Editor say **Outlaw(s)**, never Hero(es) (code names, ids, save keys and the painter's prompts keep `hero`; write Outlaw in every new text); **far creatures relocate** (map `timeline_data.relocate`, core/systems/CrowdRelocate.gd: a regular creature beyond 16 m for 5 s joins a queue, one every 0.4 s sinks and rises 19-24 m from the outlaw in the emptiest of 12 sectors; a row's `relocate`, Monks off by default; the Level Editor's Relocation card and the row's "Relocates when far"; no native change as long as a moving creature is kept out of STATE_MOVE) and Red Canyon's far speed is x4 capped at 8 m/s (a fast Jeżyk no longer outruns the far crowd); **an outlaw's starting weapon is offered only once he is owned** (`Registry.hero_may_use` / `weapon_comes_with`; `unlock_pike` and `unlock_big_mouth` retired; the Collection's "Comes with <name>" opens the Outlaws screen on him, `HeroesScreen.open_on`); the Dynamite's played look B is **red** from the start, its shrapnel mutation (`frag`) is Barbed Wire (`model_wire`), Sticky pours amber tar (`model_tar`), eight models `art/props/dynamite_b_{stick|bundle}{,_wire}{,_tar}.glb` chosen by `Lobber.model_key` (looks C and D still choose by `model_colour`), the creatures' dynamite is `dynamite_b_stick.glb`; the Boss Chest's speed bar starts past its multiplier; a board's scroll never starts above its sheet (`ScreenBase.scroll_top`). BALANCING 70. Waiting on Garry: the list under pass 128 in docs/HISTORY.md.

Pass 129: **the Trail replaces the Upgrade board** (see Meta; BALANCING 71; `docs/trail_schema.md`). The board is gone from the code the way pass 124 took the old UI out (`content/talents`, `TalentDef`, `HomesteadScreen`, the save's talent API, the Level Editor's Mirror tab): **every older line in this file that names the Upgrade board, the Mirror, talents, ranks and forms, Spite / Nerve, the seventh rank or the record's `board` is history.** What stayed: `MirrorDanger.gd` (the Stakes' stats, fed by the Trail's optional Stakes nodes), `Save._migrate_trail` (once: an old save's board paid back in full, what it had kept in `trail.had`), `Save.board_note()` (the migration's toast), a revive at 40% health (`StatSheet.PLAYER_DEFAULTS.revive_hp`). New stats `start_gold`, `totem_boost`, `boss_purse`. Six outlaws, eight items and two stages are Trail nodes; 13 unlock quests retired (`content/trail/quests_before.json` remembers them for old saves). The tools play a Trail Level (`game/tools/trail_arg.gd`: `trail=none|quarter|half|full|<level>`, `trail_optional=1`; the sim, the Watch, the difficulty probe, the replay proof, the Sim tab; `--board` / `board=` / `mirror=` are the old names): a sim at `--trail none` plays without the Trail's weapons and cards. Run record schema 6 (`trail` whole; no `talents`, `talent_forms`, `board`); the dashboard's Trail card and the replay's panel (key B). The Level Editor's **Trail tab** stands where the Mirror stood (left a scrolling preview as the game draws it, right the editor: price curve, sums, one row a node, CSV both ways); its server needs a restart after this pass. `tools/posthog_boards.py` was changed in code and not run (it rewrites Garry's live boards: `--check` first, when he asks). The design bible, the UI reference and the UI review still show the board (not rebuilt). Waiting on Garry: the list under pass 129 in docs/HISTORY.md.

Pass 130: **eleven of pass 128's environment variations are in the game with Garry's rules** (props.json `stages`, `per_run`, `stage_chance`; `PropField.in_stage` / `settle_rare`; RedCanyon hands the run's stage to `PropField.setup`: the creosote bush is White Fluff at Nightfall and Drought Twigs in the Dust Bowl and the Blood Moon, the brittlebush Dry Seedheads in the last two, the cart one of three and the Burnt Wreck in the Blood Moon, Yellow Catkins one a run; a variant plays its kind's collider, the arena stands in Sundown; cost: four more draw calls of about 240, +3 MB of textures, `_p130_ENV_probe.gd`); five re-draws of every scenery painting wait for his picks (`tools/gen_env_reseed.py`, docs/env_variants/redraws.html, published https://claude.ai/artifact/WpgGKzv6j7ogMmqpsTRQdJ; nothing in the game); **every tool that shows a Trail Level says what it gives** (`Trail.bundle_text`, the record's `trail.bundle`, `run_start`'s `trail_bundle` + `build_id`, the replay header's `trail`; the Watch, the Sim tab, the probe, the dashboard, the replay viewer's Trail button and pop-up, key B); the Level Editor's Trail tab has a Hint box (words in tools/level_editor/trail_hints.json: add an entry with every new upgrade type) and an open creature look a **Facing row** (Flip / Never mirror = `front_faces` / `back_faces`; the Straw Man's back is "left"); the sixth store shot docs/store/06_trail.png. The PostHog board "88fits · Trail" is in `tools/posthog_boards.py` (checked, 80 tiles) and **not created**: the session may not write Garry's live boards, he runs `python tools/posthog_boards.py`. His Level Editor needs a restart (a new look op, the Trail picks route). BALANCING 72. Waiting on Garry: the list under pass 130 in docs/HISTORY.md.

Pass 131 (art and tools; nothing played changed): the Level Editor's **Recolour an existing look** explains every box and can make black, grey, white and gold (mode `lift`, extra passes, presets, a before / after: `tools/level_editor/recolour_ui.js`, `recolour_io.py`, `POST /api/recolour/preview`; a method's fields may carry `label`, `example`, `guide`, `show_if`, `widget`); `tools/recolour_look.py` does a recolour look from a shell; new fresh looks CC-C (grey) and CC-D (white), RG-D (white) and RG-E (green), SK-F (SK-B with a clean back: `tools/pose_hang.py`), SK-G / SK-H (crimson, white-pink ponchos), SK-I (no hat) with SK-J / SK-K; KN-D's back and SK-C's walks repainted in place (old strips in tools/dl/p131/SKEL/before/). Garry's Level Editor needs a restart. Waiting on Garry: the list under pass 131 in docs/HISTORY.md.

**Outlaws** ("heroes" in code; title order): Drifter (Revolver; free), Astro (Gravity Gun), Calavera (Guitarra), Ironwood (the Spear =
`pike`), Solenne (Sun Scepter), Fadeaway (the Basketball: evade per level, Heat shown on the ball itself, the Timeout
trampoline perk Hang Time, Buzzer Beater), Jeżyk (id `buck`: a bald blue Slav in a tracksuit, starts with the Frisbee, favourite the
Salt, momentum, Salt Flats), May (renamed from Mamy in pass 69: attack speed, Trigger Happy on the Tommy Gun, the
Inflatable May decoy, thrown as a puck that inflates) and Mira (an unattainable requirement). Since pass 129 Astro, Calavera, Solenne,
Fadeaway, Jeżyk and May are **Trail nodes** (levels 9, 16, 23, 30, 38, 45 at their JSON prices: "Reach Trail Level N", owned once the
node is bought, never on sale; their `unlock_<hero>` quests are gone); Ironwood alone is bought with gold on the Outlaws screen
(`availability: "purchase"`, `price`; Save `heroes_owned`; Registry `hero_state`, `hero_requirement_text`);
Dad is `hidden`. No HUD gauge for any hero (pass 69). The Heroes screen (`ui/HeroesScreen.gd`, the tab bar) lists every
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
enemies|bosses|characters|maps|sounds` (and the plain JSON `content/trail/trail.json`, `content/wanted/wanted.json`). Mutation looks come from their `params` (`look`, `tint`, ...); emblems
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

**Meta.** **The Trail** (pass 129; `core/systems/Trail.gd`, `ui/TrailScreen.gd`, `content/trail/trail.json`, `docs/trail_schema.md`; the fourth tab, TRAIL):
a track of levels bought level by level with gold (a level is done when its required nodes are bought; only the next level can be bought; Trail Level = levels done). Nodes: plain,
**choice** (one of two to four, for good), **optional** (beside a level, never holds it: the Stakes, Grubstake, Spirit Guide), a node that needs two or three others, several a level. A node gives a free
amount of one of 35 upgrade types (each its icon in `art/ui/trail/`) or an unlock outright (outlaw, skin, item, stage, map, structure, power-up, the Bounty Board). No refund, no swap (the developer menu's
two reset rows are for tests). Price `round_to(base + k x level^power, round) x price_mult` or a node's own. The first set: 100 nodes on 70 levels under "To be continued" (`tools/trail_setup.py`
is the design as data; Garry edits the nodes in the Level Editor's Trail tab from now on: keep his numbers), 897,810 coins for every required node, about 100 runs by a weak purse model, node 100
x1.33 the old full board on a level-30 build. The red crumb on the tab keeps pass 123's rule (red until seen). Save: `trail {bought, spent, had}`.
Gold: every end of a run banks the purse (pass 70: a death too; only quitting the app mid-run loses it); unlocks cost
2.5x pass 69's, Elites and bosses pay 5x; the Strongbox (`gold_bank`) is hidden, out of play. Unlock quests gate 13 of the
items (eight more are Trail nodes); the Collection shows only what was met.

**UI.** One design since pass 124, Royale: the kit in `ui/wanted/` (the folder and class names stayed: `W` the API, `R` the tokens, see Architecture); the old Wanted look, the theme switch and the Painted / Live title are gone from the code, what is kept of it on purpose (paper posters, toasts, banners, TAP TO GO, the kill counter, the boss bar) uses `W.wanted_text` / `HardBox.themed = false`; one paused screen at a time with death winning
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
record is schema 6 since pass 129, `core/systems/RunAnalytics.gd`, documented in `analytics/SCHEMA.md`: the look, trait, the Trail (`trail`),
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
Krazy Robots reference deck, `benchmark_sources.md` holds every market figure with its source); the UI reference `docs/ui_screens/` (every
screen: purpose, when it shows, each control, the rules, captures; HTML + PDF, built by `tools/make_ui_screens.py [--pdf]` from
`docs/ui_screens/src/` (screens.json is the text), extra captures by game/tools/uidoc_shots.gd, published at
https://claude.ai/artifact/48aBTGN7SoCGhKjq73SUD5); `docs/art_guide.html` (Garry's guide to every art method, the stats and where things
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

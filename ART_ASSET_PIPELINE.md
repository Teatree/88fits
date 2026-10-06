# Art asset pipeline

How the game's art is made and how to make it again. Everything here runs on **this PC** (`D:/_projects/88fits`), from a
terminal in the repo folder. The game never reads prompts: they are inputs to these scripts.

## What you need
- **ComfyUI art server** at `http://192.168.137.54:8188`, switched on. It paints the stills (Flux.2 Klein, fast; Flux.2
  dev with `--dev`, slower and better) and the animations (Wan 2.2).
- **Python 3** (the scripts in `tools/`), and **Blender 5.2** for anything built from a 3D model
  (`%LOCALAPPDATA%/Programs/blender-5.2.0-windows-x64/blender.exe`).
- After any new art: re-import in Godot (open the editor, or `--import`, then `import_json.gd`). `bash tools/ship.sh` does
  both before it builds.

## The one rule: look at it yourself
The automatic vision check misses extra ears, arms, tails and missing legs. Every script paints **several candidates**
and writes a **review sheet** (`review_*.png`); open it, pick by eye, then install the pick. Look at walks and deaths at
the size they appear in the game, on sand.

## Where the words live
| field (in the item's JSON) | what it steers |
|---|---|
| `art_prompt` | what gets painted: the source of truth |
| `back_hint`, `view_hints`, `dead_hint`, `pose_hint` | the back view, side/diagonal views, the dead painting, the pose |
| `motion`, `anim_negative`, `anim_seed` | the walk clip's motion, what it must not do, re-roll a clip |
| `variants.<CODE>.recipe` | the same fields overridden for one art variant (SC-A, HG-B ...) |
| `outline_frac`, `outline_color`, `key_sat`, `remap_hues` | the outline and colour clean-up |

Edit the words, re-run the script, pick again.

## Creatures (enemies, bosses)
Paintings: front, back and dead; animation: a walk and a fall, packed into `<id>_sprite.png` (+ `<id>_icon.png`).

```
python tools/gen_art.py --only skeleton --force              # repaint one creature from its JSON (stills, clips, strip)
python tools/gen_art.py --only skeleton --variant=SK-B       # paint one art variant from its recipe
python tools/gen_art.py --only goblin --no-video             # quick procedural walk instead of video clips
```
- **Variants** are how new looks are tried: add an entry under `variants` with a `recipe`, paint it, then spawn it in
  **Debug · Arena → ENEMY → Art variants**. To play it, set `"variant": "<CODE>"` in the JSON.
- **Creatures from a 3D model** (scorpion, fire ant): the model is walked in Blender and Wan follows its depth video,
  so legs and tails stay right.
  ```
  "$BLENDER" -b --python tools/blender_scorpion.py -- out=tools/dl/drivers/scorpion_walk frames=12 cycles=2
  python tools/gen_ctl.py --id=dune_scorpion --variant=SC-A              # side candidates, then stops: look
  python tools/gen_ctl.py --id=dune_scorpion --variant=SC-A --use-side=k1
  python tools/gen_ant.py --variant=ANT-A                                # the fire ant's own version
  ```
- **A rigged model with its own animations** (the Bull Beetle, pass 48, from `_REFERENCES/3d/a-rhino-beetle.zip`): the
  model's own walk and death clips drive the paintings, so no gait has to be made by hand.
  ```
  "$BLENDER" -b --python tools/blender_beetle.py -- out=tools/dl/drivers/beetle_walk frames=12 cycles=2
  "$BLENDER" -b --python tools/blender_beetle.py -- mode=death out=tools/dl/drivers/beetle_death
  python tools/gen_ctl.py --id=bull_beetle --variant=BB-A --dev     # side candidates on Flux dev, then --use-side=kN
  ```
  Each view also gets `look.png` (the model in its own colours), which a recipe can name as `look_ref`.
  **Legs that stand still (pass 49):** render the walk with `depth=tight amp=1.7`
  (`tools/dl/drivers/beetle_walk_amp`). `depth=tight` maps each view's own near and far onto bright and dark and writes it
  with Blender's Raw view transform (the default AgX squeezed every depth video into one flat grey, so Wan saw a silhouette
  and walked half the legs on nothing); `amp` swings each leg bone wider around its own average pose, because a real
  beetle's step is too small to read on the phone. Check a walk by measuring it, not only by looking at one frame: the
  leg area should change from frame to frame in every view.
- **A creature copied from a picture** (the Vulture Raider, pass 48, from `_REFERENCES/2d/Vulture Raider with Rocket Launcher.png`):
  the front is painted as Klein edits of the picture itself ("copy this exact character", the picture laid on the green
  screen), six seeds, picked by eye; the back and the dead painting are edits of the chosen front (scratchpad `stills48.py`
  style), then `gen_art.py --only rocketeer` walks it. A hand that holds something (his launcher) is pinned in the walk driver
  so Wan keeps it still: `tools/pose_driver.py ... arms=hold_r` (`tools/dl/drivers/walk_hold`).
- **Hopping creatures** (slime, tumbleweed minion): `"walk": "hop"` in the JSON animates the painting itself, no video.
- **Shadow** looks off (floating)? Tune `shadow {scale, up, drop}` in the JSON; no repaint needed.
- Time: about 20 minutes a creature on Klein, up to 3 hours for a 3D-driven one with dev.



### Four more routes (pass 54)
- **A hero from a finished picture** (Solenne from Garry's turnaround): `python tools/make_solenne_static.py` cuts the picture in two at its widest clear gap; the front half is the title painting (`gen_title_heroes.fit`) and, cropped to the head, the round badge (`gen_art.portrait_badge`); both halves laid on the blue screen are written into `tools/dl/ai_raw_anime/<id>_front.png` / `_back.png` with a `.json`, so `gen_art` keeps them and paints only the side, the three-quarter views, the hurt stills, the dead painting and the walks. `gen_art` writes its own painted badge over `<id>_icon.png` at the end: keep a copy and put the chosen one back after every run.
- **A walk that leaves the frame**: a wide-armed walk (her `Walking_sun.fbx`) touched the clip's edges in the back views (pose_cycle threw six clips away; one kept a boot the keyer cut off). `python tools/pose_scale.py <driver> <driver>85 scale=0.85 views=back,bd` shrinks those views' stick figures about the middle; gen_art scales every frame back to the standing height, so the sprite is the same size.
- **Glossy black on a screen**: latex reflects the screen colour, and the keyer cut the reflections out (hollow boots, floating heels) and unmixed the edges into magenta. Four JSON keys fix it at the source: `key_sat` 0.85 (only the fully saturated screen is screen), `key_min_value` 0.8 (a screen-coloured pixel darker than that is figure), `key_cut_shadow` false (a clip has no cast shadow to cut) and `key_clamp_screen` true (the screen's channel is held down to the other two in every figure pixel, so a reflection becomes grey shine). Paint the clips again after changing them: `tools/rekey_clip.py` re-keys cached frames, but their edges were already unmixed by the first key.
- **A darker colour of a finished strip** (SK-E / KN-E, dark-blue bones): `python tools/recolour_strip.py --src <strip> --dst <strip> --mode tint --ranges 10-75 --to 222 --set-sat 0.55 --value 0.6 --min-val 0.3` sets the hue and the saturation and lowers the value (`artkit.tint_range`); `remap_hues` keeps value and cannot darken ivory. The knight needed two passes (the bone, then the brightest highlights with `--min-sat 0.55 --min-val 0.62`), and its steel stayed out of the warm hue range.
- **A plain look the model will not paint** (LS-A): Flux dev answered "plain, simple" with the clay render itself five times; a Klein edit of the plated look's side painting ("much simpler: thick outline, flat black fill, one grey highlight") gave the plain side, then `gen_ctl.py --use-side=kN` painted the other views and walked it as usual.

### Three more routes (pass 53)
- **A recolour of a finished strip** (the Red Goblins): `python tools/recolour_strip.py --src <strip> --dst <strip> --ranges 55-135 --to 357 --sat 1.0 [--preview p.png]` moves the hues inside the ranges (the green skin) to another hue frame by frame; value and alpha stay, so the lines, the shading and the death are the same pixels. Measure the hues first (a histogram of the first frame) so the browns and the outline stay out of the range. The icon goes through the same command.
- **Front candidates as edits of a picture** (the Werewolf from `_REFERENCES/2d/Werewolf.webp`): `python tools/gen_edit_stills.py --id werewolf --stills wwa --ref <picture> --prompt "<the creature, one cartooniness level>" --seeds 4 [--screen blue]`, look at `tools/dl/review/<id>_<stills>_front_cands.png`, then `--pick N`; the pick lands in `tools/dl/ai_raw_anime/<id>_<stills>_front.png`, and a variant whose recipe says `"stills": "wwa"` makes `gen_art.py --only <id> --variant=WW-A` paint the back and the dead painting from it and walk it. The mummy's four looks are edits of the old mummy's own painting with new words.
- **A walk from a glTF clip** (the mummy on Garry's `Zombie monster walk.glb`): `"$BLENDER" -b --python tools/pose_driver.py -- glb=<file> rig=sm out=tools/dl/drivers/zombie_walk frames=12 start=0 end=1.5` (the `RIGS` table maps the Bone_SM_* names to Mixamo's; a centimetre rig is scaled; count the strides in the clip from the ankles first and slice one with start/end), then `python tools/pose_driver.py draw ...`; the creature's recipe names it with `"pose"`.
- **A black creature on gen_ctl**: the three-quarter and back views drift to brown unless the recipe's `keep` says "jet-black armour all over, never brown, orange or tan"; a wrong view is repainted with `--view-cands=bd,back` and picked with `--use-view=bd:cN` (move the cached `tools/dl/ai_anim/<id>_<code>_ctl_<view>` folder away so the walk renders again); `remap_hues` cannot fix it (it keeps the value). The "simple" look must still say "painted, cel-shaded, crisp line art" or Flux dev returns the clay render itself.

## Heroes
Five views (front, three-quarter front, side, three-quarter back, back), a run in each driven by a Mixamo stride, hit
and dead paintings, a portrait icon, then a title-screen painting.
```
python tools/gen_art.py --only drifter                         # stills (missing ones), pose-driven runs, the strip
python tools/gen_title_heroes.py --only drifter --seeds 4      # title painting candidates
python tools/gen_title_heroes.py --pick drifter=2              # install -> game/art/ui/wanted/hero_drifter.png
```
- Runs use pose drivers in `tools/dl/drivers/` (`pose_drivers` in the hero JSON picks one per view; `run_spread`,
  `run_occ` fix a hand drawn on the back). Details: `.claude/skills/sprite-animation/SKILL.md`.
- Paint the front as 4-6 candidates first (the identity of the hero); every other view is an edit of it.
- **A hero whose build is not a man's** (pass 55, Solenne: a big sun head on a slim body): fit the driver to the
  painting, or the video model paints the painting onto a man's proportions and the head and hands change size from
  view to view. Measure the still as the clip sees it (its neck, ankle line and head on the 640 px canvas), write
  them in `tools/pose_templates/<id>.json` (`neck_to_ankle`, `ankle_y`, `centre_x`, `head_up`, `head_dx`, `hands`, a
  face per view), then:
  ```
  "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/<clip>.fbx out=tools/dl/drivers/<name> frames=24 pitch=25 fwd=body
  python tools/pose_fit.py tools/dl/drivers/<name> tools/dl/drivers/<name>_fit tools/pose_templates/<id>.json
  python tools/pose_spread.py tools/dl/drivers/<name>_fit tools/dl/drivers/<name>_fit_spread    # the back views
  ```
  `fwd=body` squares every view to the hips and shoulders (a walk with the toes turned out turned the side view a
  quarter away). Overlay a driver frame on the still before painting: the stick figure must sit on the body.
- **Several walks to choose from**: a hero's `variants` in its JSON, each with a `recipe` (`pose_drivers`,
  `still_keys` for a view painted or composed differently, `pose_motion`, `run_fps`), painted with
  `gen_art.py --only <id> --variant=<CODE>` into `<id>_sprite_<letter>.png`; Garry picks in the arena's HERO tab.
- A painting the image model will not give (Klein turned Solenne's sun disc edge-on in a side view six times): compose
  it from the paintings you have (her side still is the side body under the three-quarter-front head).
- **The badge** (pass 56): gen_art paints a close-up and `portrait_badge` zooms it to fill the circle. A hero whose head
  is wider than his shoulders (Solenne's sun) lost everything but the head that way. Paint several close-ups, pick one
  by eye, copy it into the paintings' cache under its own key, and name it in the hero JSON:
  `"badge": {"still": "solenne_badge", "head_width": 0.8, "top_pad": 0.03}` (the head's widest span as a share of the
  circle, hung that far from the top, the shoulders running off the bottom); every later gen_art run makes the same
  badge instead of painting a new portrait over it. Key it with the hero's own key knobs (a glossy black suit keyed
  with the defaults came out see-through).

## Icons (weapons, passives, lines, mutations, perks, UI bits)
```
python tools/gen_icon_cands.py --only beer --seeds 4    # candidates -> tools/dl/icons47/review_beer.png
python tools/gen_icon_cands.py --pick beer=2            # install -> game/content/passives/beer/beer_icon.png
```
- A job is one entry in `JOBS` at the top of `tools/gen_icon_cands.py` (subject words, kind, id). Add one for a new item.
- **Anything green in the subject goes on the blue screen** (`"screen": "blue"`), or the keyer cuts it out.
- Check icons on their plate colours before installing (dark evolution plate, the line/weapon yellow, rarity colours).
- Weapons with a 3D model get their icon painted from a render of the model (`"ref"`), so icon and model match.
- **Shapes Flux bends** (dice, anything that must be a true cube or circle): render the shape in Blender first and give it
  as the `"ref"` with the `COPY` words. Hot Streak's dice (pass 49): `"$BLENDER" -b --python tools/blender_dice.py` ->
  `tools/dl/dice_ref.png`. A logo on an object works the same way: Barrel Rush's barrel carries the Sprint power-up's icon
  (`tools/dl/sprint_logo_ref.png`).
- Other icon kinds: badges over creatures (`kind: badge`), UI art (`kind: ui`, e.g. the coin), damage-source icons for
  Results (`kind: source`). Older batch: `python tools/gen_art.py --only <id>` paints a plain icon from `art_prompt`.
- The app icon: `tools/gen_app_icon.py` (candidates, `--pick`).

## Props and structures (the 2.5D scenery)
Cacti, rocks, bones, trees and the structures (Strongbox, Teleport, wells...) are paintings on billboards.
```
python tools/gen_props.py --only st_teleport --force     # Flux dev by default; --klein for the fast model
```
- Their list and sizes are `PROPS` in `tools/gen_props.py`; output `game/art/sprites/props/` + `props.json`. A used
  structure has a second painting `st_<id>_off.png`.
- `"hidden": true` in a `props.json` entry keeps a painting out of the desert (the signpost and the yucca, pass 49);
  gen_props keeps an entry's extra keys when it rewrites the manifest.
- A structure must look still: no sparks, glows or lightning painted in (they read as stuck animation). Paint a few seeds and
  pick by eye (pass 49's magnet: scratchpad `magnet49.py` style).
- Structures stay painted (2.5D), never 3D models.

## UI art
- Painted UI slots (Stranger, Strongbox, portal, Mirror): `python tools/gen_ui_art.py --only mirror --seeds=4`, then
  `--pick mirror=n`.
- Chest-opening frames (`art/ui/wanted/chest_*.png`, `boss_chest_*.png`): closed, cracked and open paintings, the last
  two edits of the first.
- Badges: `python tools/gen_badges.py --only crown`.

## 3D models (Blender)
Weapons held or placed in the world are GLB models built by scripts, several from Garry's references in `_REFERENCES/`:
```
"$BLENDER" -b --python tools/blender_turret.py     # also blender_tommy, blender_guitar, blender_spear, blender_hammer,
                                                   # blender_revolver, blender_gravity_gun, blender_mouth, blender_barrel,
                                                   # blender_rocket (the Vulture Raider's rocket), blender_grenade (the
                                                   # Golden Pineapple), blender_beetle (the beetle's drivers)
```
Output `game/art/props/*.glb`, plus a reference render the icon is painted from.
- Gold that reads gold in the game (pass 48): a deep gold base `(255, 150, 12)`, metallic about 0.75, and a little of its own
  colour as emission (0.35). Paler gold at lower metal went tan under the desert sky (the old Golden Revolver and Chicago
  Typewriter). A part the game draws as one mesh in a MultiMesh (the rocket, the golden grenade) is coloured by vertex
  colours, one mesh, so a single material shows every colour.

## Where things land
| what | file |
|---|---|
| creature/hero strip and icon | `game/content/<type>/<id>/<id>_sprite.png`, `<id>_icon.png` |
| raw paintings (cached) | `tools/dl/ai_raw_anime/` (delete one to repaint it) |
| animation clips (cached) | `tools/dl/ai_anim/<key>/` |
| review sheets | `tools/dl/review/`, `tools/dl/icons47/`, `tools/dl/icons48/`, `tools/dl/stills48/`, `tools/dl/title_heroes/` |
| replaced art (backups) | `tools/dl/backup/` |

More depth: `docs/RUNNING.md`, the design bible's section 15b "How the art is made", and the skills in
`.claude/skills/` (sprite-pipeline, sprite-animation).

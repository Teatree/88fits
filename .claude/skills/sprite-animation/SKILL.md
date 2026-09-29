---
name: sprite-animation
description: Make smooth, consistent run and walk cycles for 88fits sprites from a single still using Wan 2.2 image-to-video on the ComfyUI server (the proven "animate a still, cut the loop" method). Use when a character or creature needs an animation, a new view direction, or when a cycle looks wrong.
---

# Sprite animation from one still

Hand-describing poses to an image model ("left leg forward, right leg back") produces six unrelated drawings, not motion.
The method that works is the one 2D studios and AI-sprite tools converged on: **animate the still with a video model,
then cut one loop into frames.** Character identity comes from the still, timing comes from the video model.

## Pipeline

1. **Still per view.** `tools/gen_art.py` renders the standing character once per view with Flux.2 Klein: back, side,
   front, three-quarter back (`bd`) and three-quarter front (`fd`) for heroes; front and back for creatures. Diagonals
   and the side are mirrored in game for the other half, giving eight directions from five stills.
2. **Clip.** `tools/animate.py` puts the keyed still on its screen colour with room to move, uploads it, and runs the
   official Wan 2.2 14B image-to-video graph (two-stage high/low noise sampling with the lightx2v 4-step LoRAs,
   `ModelSamplingSD3` shift 5, 640x640, 49 frames at 16 fps). The prompt asks for the motion "in place, like a treadmill,
   camera locked off, flat background". Frames are saved as PNGs by `SaveImage`.
3. **Loop.** Every frame is chroma-keyed; silhouettes are compared to find the period (7 to 26 frames) and start frame
   with the smallest wrap-around difference; eight evenly spaced frames of that period are kept, cropped to the union
   box of the whole cycle so the bounce survives. A clip where the figure leaves the frame is re-rolled with a new seed.
4. **Cells.** `artkit.place_clip_frames` scales the frames (24 per hero cycle at 28 fps, 12 per creature cycle at 15 fps; `HERO_RUN_FRAMES` / `CREATURE_RUN_FRAMES` in gen_art.py, the rate lands in the JSON as `fps`) so the figure matches its standing cell (feet at the
   cell floor) and adds the outline. Strips: heroes `idle 4 + run 8` per view, creatures `run 8` front and back.

## Commands

```
python tools/animate.py tools/dl/ai_raw_anime/drifter_side.png "running in place, side profile facing right" 1
      -> tools/dl/ai_anim/test_drifter_side/{cycle_sheet.png, out_00..07.png, raw_*.jpg, cycle.json}
python tools/gen_art.py --only drifter            # renders any missing stills, then the clips, then packs the strip
python tools/gen_art.py --only goblin --no-video  # procedural 6-frame walk instead (fast, for placeholders)
python tools/comfy.py --export                    # writes 05_run_cycle_wan22.json for the ComfyUI UI
```

Clips are cached in `tools/dl/ai_anim/<key>/`; delete a folder to regenerate that cycle. A creature or character JSON
may set `"motion"` to change the gait prompt ("hopping in place", "rolling on the spot", "scuttling").

## Review

Open `cycle_sheet.png` next to each clip: the frames should read as one continuous stride with the same outfit and
proportions. If the character drifted across the frame or turned, re-roll (`--keys` on the still keeps the pose; a
new seed on the clip is `animate.cycle(..., seed=N)`); if the loop stutters, the period was wrong: check
`cycle.json` and widen `find_cycle` bounds.

## Timing on the R9700

The two 14B fp8 models do not both fit next to the text encoder, so ComfyUI swaps them between the two sampling
stages: expect roughly 4 to 6 minutes per 49-frame clip. A hero is five clips, a creature two.

## Pose-driven cycles (the current method for heroes, 2026-09-15)

The free image-to-video clip left the stride count to the model, and the silhouette cutter could not tell a left step
from a right one in the front, back and side views, so cycles came out doubled or halved. Heroes now use
**Wan 2.2 Animate driven by a Mixamo stride**:

1. `tools/dl/mixamo/running.fbx` and `walking.fbx` (Mixamo, "In Place", FBX binary, 30 fps, without skin; one clean stride each).
2. `"$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/running.fbx out=tools/dl/drivers/run frames=24 pitch=25`
   then `python tools/pose_driver.py draw tools/dl/drivers/run`: OpenPose skeleton frames per game view (back, bd, side, fd,
   front; side and diagonals face screen-right like the stills), 24 frames of one stride plus a repeat of the first, camera 25 deg above.
3. `animate.cycle_pose(still, key, driver_dir, seed, prompt_hint)` -> `animate.wan_animate(...)` graph: Wan 2.2 Animate 14B fp8
   (`wan2.2_animate_14B_fp8_e4m3fn_scaled_KJ.safetensors`) + `lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16` LoRA, 4 steps,
   cfg 1, shift 8, `clip_vision_h`; the still as `reference_image`, the drivers as `pose_video`; ~2 min per 640x640x25 clip.
   Every driver frame is a sprite frame: no period detection. `gen_art.pose_cycle` wraps it and falls back to `video_cycle`.
4. Creatures with non-human skeletons (ants, cacti, beetles) still use the free clip; humanoids could use `drivers/walk`.

Models live on the server at `~/ai/ComfyUI/models/` (SSH: `ssh -i ~/.ssh/id_ed25519_ai_server teatree@192.168.137.54`; download with wget there).

## Creatures on a fitted stride, and deaths that fall (pass 33.9, the goblin)

A creature painted with other proportions than the Mixamo rig (a big head, short legs) comes out lanky when Wan
Animate paints it on the rig's skeleton, because Animate puts the body where the bones are. Retarget the driver:

1. Read the painting's proportions as fractions of its height (head top to soles): `top_nose`, `nose_neck`, `torso`
   (neck to the middle of the hips), `thigh`, `shin`, `shoulder` and `hip` (half widths), `upper`, `fore`, `hand`.
   A coordinate grid over the front still is enough (the goblin: 0.21, 0.134, 0.292, 0.16, 0.14, 0.119, 0.068, 0.174, 0.139, 0.078).
2. `"$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/orc_walk.fbx out=tools/dl/drivers/orc_walk_goblin frames=12 body=top_nose:0.21,...`
   then `python tools/pose_driver.py draw tools/dl/drivers/orc_walk_goblin`, and point the creature JSON's `"pose"` at the folder.
   Overlay a driver frame on the painting before painting anything (`make_pipeline_figs.overlay_driver`).
3. `"stand": "still"` keeps the painting for idle, attack and hit when the walk's passing frame would read worse.

`"death": "clip"` animates the death: `animate.fall_clip` puts the standing and the dead painting at one scale on one
floor line and runs Wan 2.2 first-last-frame (`wan_flf`, 33 frames, ~2 min). `gen_art.death_cycle` keeps `death_frames` (8) from the
last frame still near standing to the first near lying (silhouettes), swaps any frame with a colour flash for a neighbour
(`hue_excess` over 0.06), matches saturation and brightness to the paintings (the video paints brighter, and the step into
the dead painting flashed), and ends on the dead painting; die plays at 12 fps. Paint the dead still holding whatever the
creature carries (`dead_hint`), so nothing has to vanish mid-fall.

Pose cycles re-roll when a frame flashes a colour its neighbours lack (`hue_excess` over 0.08). The vision QA cannot
count ears or arms: paint several seeds of each still and pick by eye.

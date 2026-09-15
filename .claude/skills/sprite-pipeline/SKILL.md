---
name: sprite-pipeline
description: Generate, check, clean and pack the anime-style sprites and Shop-Titans-style icons for 88fits with Flux.2 Klein on the ComfyUI server, locked to one style anchor; run cycles come from Wan clips (see sprite-animation). Use when adding or re-rolling an enemy, character, weapon or icon, or when changing the art style.
---

# Sprite and icon pipeline

Every sprite follows the animation set in design-bible section 15, packed as a grid of square frames in a fixed order (one row while it fits in 16k px, more rows beyond; the JSON's `strip_cols` says how many per row and both billboard shaders read it):
enemies `idle`(2) `run`(2) `attack`(2) `hit`(1) `die`(1); characters `idle`(2) `run`(4) `hit`(1) `die`(1) `cheer`(1) for the back view, then
`idle_f`(2) `run_f`(4) for the front view and `idle_s`(2) `run_s`(4) for the side view (facing right, mirrored in game for left). The game picks
the view from the direction of travel relative to the camera; a strip without the extra views falls back to the back set. Frame sizes come from `frame_px` in the JSON: 256 px characters and bosses, 128 to 192 px enemies
(bigger creatures get bigger cells so they stay sharp at ~94 px per metre on the phone), 256 px icons.

## The look

Clean modern anime: crisp line art, cel shading with two-tone shadows, flat saturated colours, appealing proportions, no
surface detail. The pipeline adds a thin dark outline (2% of the cell) so silhouettes hold on sandy ground. One **style anchor** image
(`game/art/style/style_anchor.png`, a sheet of five subjects) is passed as a reference image to every render, which is what keeps the
whole roster in one style. Change the look by regenerating the anchor, not by editing forty prompts.

## Tools

- `tools/comfy.py` — ComfyUI API client + the workflow builders (`klein(...)`, `flux2_dev(...)`). `python tools/comfy.py --export` writes
  the graphs as UI-loadable workflows into `tools/comfy_workflows/` (drag one into the ComfyUI browser to inspect or tweak it).
- `tools/artkit.py` — keying, speck and ground-shadow cleanup, outline, contrast lift, cell fitting, procedural frames, grid strip packing (`pack_strip` returns image, counts, cols).
- `tools/gen_art.py` — the batch. Server: `http://192.168.137.54:8188`, model Flux.2 Klein 9B distilled (4 steps, cfg 1, ~16 s a render),
  text encoder qwen_3_8b, references through `ReferenceLatent`. Vision QA through LM Studio `qwen2.5-vl-7b` at `http://127.0.0.1:1234`.

```
python tools/gen_art.py --anchor            # paint 4 anchor candidates -> tools/dl/review/anchor_candidates.png
python tools/gen_art.py --pick=2            # install candidate 2 as game/art/style/style_anchor.png
python tools/gen_art.py                     # everything missing, then review sheets, then --import + import_json
python tools/gen_art.py --force --only goblin,knight --seed=1   # re-roll two items with a different seed
flags: --skip-qa  --no-import  --no-anchor-ref  --server=URL
```

## What one item costs

- icon items (weapons, evolutions, passives, shop, elites, maps, quests): one render.
- enemies and bosses: one front-view render; frames are derived procedurally (bob, lean, squash, white tint, fall) so the creature is
  consistent by construction.
- characters: front view (portrait icon + identity reference) -> back view and side view (edits of the front) -> three rendered strides per
  view plus a cheer (each referenced on its standing view). Every step is an image edit, so the outfit and colours stay put. Each run cycle is
  `left stride, pass, right stride, pass`; strides are fitted to 94% of the standing height because Klein draws running figures smaller.

Every render is graded by the vision model (`subjects`, `background`, `ground`, `text`, `cropped`, `view`, `matches`); a failing render
re-rolls with a new seed up to three times and the best one is kept. Raw renders and grades are cached in `tools/dl/ai_raw2/`
(`<key>.png` + `<key>.json`), the summary lands in `<id>_ai.json` next to the content. Prompts: the JSON `art_prompt` is the source of
truth; the style paragraph and the green-screen instruction are appended by the script (`STYLE`, `BG_GREEN`; green subjects get a blue
screen automatically from their `placeholder.color`).

## Check before you import

`tools/dl/review/icons.png`, `strips.png` and `phone.png`. `phone.png` shows each sprite at its on-screen pixel size on the sand texture
and ten icons at HUD size: if a creature does not read there, raise its `size` in the JSON or simplify its `art_prompt`, then re-roll.

## Gotchas

- Flux draws a ground shadow or grass line under things even when told not to; `artkit.key_background` cuts screen-tinted pixels in the
  bottom 20% of the figure, so do not put important detail at the feet.
- Never use magenta screens (rendered pink, eats red subjects). Green by default, blue for green subjects.
- Klein ignores "no face" on round objects; describe a flat symbol instead ("crosshair reticle" beat "ring of energy").
- Vision QA mislabels the odd back view as "side"; a legitimately good render that keeps failing can be forced with `--skip-qa`.
- `tools/paint_pass.py` (numpy shading over procedural strips) is only for items without an `<id>_ai.json` marker.

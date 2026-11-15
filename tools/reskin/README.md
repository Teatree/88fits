# Reskin a rigged 3D model with a new material (the mesh, rig and animations untouched)

Made for the hell hound wolf (2026-11-15: `wolf_hellhound.glb` at the repo root, from
`_REFERENCES/3d/Wolf_walk-cycle_Animated.glb`). What the local 3D model can do: **Hunyuan3D-2.1 Paint** on the AI server
paints **base colour, metallic and roughness** onto a given mesh from one reference picture. It makes **no normal map and
no emission**: those are made here (the normal map baked in Blender from the model's own normal map with the new
painting's cracks pressed in; the emission taken from the painting's hot, bright, saturated colours).

1. `blender -b --python tools/reskin/stage.py -- src=<model.glb> out=<dir>/stage` — the skinned mesh in its rest pose,
   turned side-on to the paint model's front camera; `ref_side.png` (its render from that camera), `shape_sub.glb` (the
   shape to paint, cut into four so the paint model's fill of unseen parts works on small triangles), `stage.json`.
2. `python tools/reskin/ref_klein.py --src <dir>/stage/ref_side.png --out <dir>/ref --prompt "<the look>" --seeds 4`, look
   at `<dir>/ref/sheet.png`, then `--out <dir>/ref --pick k` — the reference picture (Klein edits of the render, the
   render's silhouette as the alpha). `--prompt hellhound` is the wolf's.
3. `bash tools/reskin/paint_remote.sh <dir>/stage/shape_sub.glb <dir>/ref/ref_rgba.png <dir>/paint 12` — Hunyuan3D-2.1
   Paint on the AI server (~5 min: under the ComfyUI lock, ComfyUI stopped and started again; refuses while its queue is
   busy).
4. `blender -b --python tools/reskin/dress.py -- step=bake src=<model.glb> stage=<dir>/stage paint=<dir>/paint maps=<dir>/maps`
   — a new UV map `HellUV` on the model's own mesh (Smart UV Project: a game model's own UVs are often mirrored, both sides
   on the same texels), the painting's maps baked onto it from the painted shape, the model's own alpha (fur fringes) too.
5. `python tools/reskin/maps.py <dir>/maps` — emission, packed metallic-roughness, base colour with the alpha, the crack
   height.
6. `blender -b <dir>/maps/wolf_bake.blend --python tools/reskin/dress.py -- step=finish maps=<dir>/maps out=<new.glb> prev=<dir>/prev [emit=3] [bump=0.6]`
   — the normal map, the material (base colour + the source's alpha cut, metallic-roughness, normal, emission), the GLB
   with the rig and every animation, six previews in `prev/`.

Lessons from the wolf: copying the painted mesh's own UVs onto the model (same geometry, xatlas islands) left chevron
streaks at seams; baking from the painted shape onto a fresh UV map is clean. Without the source's alpha the fur fringes
showed as opaque flaps. A stray helper mesh at the scene's root (the wolf's 2 m Icosphere) is left out by step 4.

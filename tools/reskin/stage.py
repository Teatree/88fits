"""A reskin (tools/reskin/README.md), step 1 in Blender: a rigged model's skinned mesh in its rest pose, turned side-on to
the paint model's front camera (glTF +Z = Blender -Y; its length along X, the head at +X found as the higher end), its
reference render from that camera on transparent film (ref_side.png), the static shapes for Hunyuan3D-2.1 Paint
(shape.glb; shape_sub.glb cut into four, the one to paint), stage.json (the turn T the bake undoes) and the UV layout's
overlap (mirrored UVs share texels: the reason dress.py makes its own UV map). Made for the hell hound wolf (2026-11-15).
  blender -b --python tools/reskin/stage.py -- src=<model.glb> out=<dir>
"""
import bpy, sys, os, math, json
import bmesh
from mathutils import Vector, Matrix

args = dict(a.split("=", 1) for a in sys.argv[sys.argv.index("--") + 1:])
SRC, OUT = os.path.abspath(args["src"]), os.path.abspath(args["out"])
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = next(o for o in bpy.data.objects if o.type == "MESH" and o.vertex_groups)
for o in bpy.data.objects:
    if o.type == "MESH" and o is not body:
        o.hide_render = True
        o.hide_set(True)
arm.data.pose_position = "REST"
bpy.context.view_layer.update()

# the evaluated mesh in world space (rest pose)
dg = bpy.context.evaluated_depsgraph_get()
ev = body.evaluated_get(dg)
me = bpy.data.meshes.new_from_object(ev, depsgraph=dg)
me.transform(body.matrix_world)
pts = [v.co.copy() for v in me.vertices]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
size = hi - lo
# the head: the end of the long axis whose top is highest (a wolf's head is up, its tail low)
long_x = size.x >= size.y
ax = 0 if long_x else 1
mid = (lo[ax] + hi[ax]) / 2
top_lo = max((p.z for p in pts if p[ax] < mid - size[ax] * 0.3), default=0)
top_hi = max((p.z for p in pts if p[ax] > mid + size[ax] * 0.3), default=0)
head_sign = 1 if top_hi > top_lo else -1
# turn it so its length runs along +X with the head at +X: its left side then faces -Y (the paint model's front camera)
yaw = 0.0 if long_x else -math.pi / 2
if head_sign < 0:
    yaw += math.pi
R = Matrix.Rotation(yaw, 4, "Z")
centre = (lo + hi) / 2
T = Matrix.Translation(Vector((0, 0, 0))) @ R @ Matrix.Translation(-Vector((centre.x, centre.y, lo.z)))
me.transform(T)
shape = bpy.data.objects.new("shape", me)
bpy.context.scene.collection.objects.link(shape)
shape.data.materials.clear()
# the shape for the paint model: no materials, no UVs it would keep, Y-up glTF
for o in bpy.data.objects:
    o.select_set(False)
shape.select_set(True)
bpy.context.view_layer.objects.active = shape
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "shape.glb"), use_selection=True, export_materials="NONE",
                          export_texcoords=False, export_normals=True, export_animations=False, export_skins=False)
# v2: the same surface cut into four (simple subdivision, the shape unchanged) so the paint model's fill of the parts no
# view saw works on smaller triangles
sub = shape.modifiers.new("sub", "SUBSURF")
sub.subdivision_type = "SIMPLE"
sub.levels = 1
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "shape_sub.glb"), use_selection=True, export_materials="NONE",
                          export_texcoords=False, export_normals=True, export_animations=False, export_skins=False, export_apply=True)
shape.modifiers.remove(sub)
json.dump({"yaw": yaw, "centre": [centre.x, centre.y, lo.z], "size": list(size), "head_sign": head_sign,
           "T": [list(r) for r in T]}, open(os.path.join(OUT, "stage.json"), "w"), indent=1)

# the UV overlap: texels covered by more than one face (mirrored halves)
bm = bmesh.new()
bm.from_mesh(body.data)
uv = bm.loops.layers.uv.active
N = 256
cov = [0] * (N * N)
area = 0.0
for f in bm.faces:
    us = [l[uv].uv.copy() for l in f.loops]
    for i in range(1, len(us) - 1):
        a, b, c = us[0], us[i], us[i + 1]
        area += abs((b - a).cross(c - a)) / 2
        xs = [p.x for p in (a, b, c)]
        ys = [p.y for p in (a, b, c)]
        x0, x1 = max(int(min(xs) * N), 0), min(int(max(xs) * N) + 1, N)
        y0, y1 = max(int(min(ys) * N), 0), min(int(max(ys) * N) + 1, N)
        for yy in range(y0, y1):
            for xx in range(x0, x1):
                p = Vector(((xx + 0.5) / N, (yy + 0.5) / N))
                d1 = (b - a).cross(p - a); d2 = (c - b).cross(p - b); d3 = (a - c).cross(p - c)
                if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0):
                    cov[yy * N + xx] += 1
used = sum(1 for c in cov if c > 0)
multi = sum(1 for c in cov if c > 1)
print("UV area %.3f, texels used %.3f, of them covered twice or more %.3f" % (area, used / (N * N), multi / max(used, 1)))

# the reference render: the paint model's front camera (from -Y), orthographic, the original texture, soft light
scn = bpy.context.scene
scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
scn.render.film_transparent = True
scn.render.resolution_x = scn.render.resolution_y = 1024
scn.view_settings.view_transform = "Standard"
body.hide_render = True
shape.data.materials.append(body.data.materials[0])
# the shape lost its UVs in the export copy only: the object here still has them
cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam_d.ortho_scale = max(size.x, size.y, size.z) * 1.12
cam = bpy.data.objects.new("cam", cam_d)
scn.collection.objects.link(cam)
cam.location = (0, -10, size.z / 2)
cam.rotation_euler = (math.pi / 2, 0, 0)
scn.camera = cam
w = bpy.data.worlds.new("w")
scn.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
for rot, en in (((math.radians(50), 0, math.radians(-30)), 3.0), ((math.radians(60), 0, math.radians(150)), 1.2)):
    ld = bpy.data.lights.new("sun", "SUN")
    ld.energy = en
    lo_ = bpy.data.objects.new("sun", ld)
    lo_.rotation_euler = rot
    scn.collection.objects.link(lo_)
scn.render.filepath = os.path.join(OUT, "ref_side.png")
bpy.ops.render.render(write_still=True)
# a 3/4 front view too (only to look at)
cam.location = (6.5, -7.5, size.z * 0.75)
cam.rotation_euler = (math.radians(82), 0, math.radians(41))
scn.render.filepath = os.path.join(OUT, "ref_34.png")
bpy.ops.render.render(write_still=True)
print("stage done", OUT)

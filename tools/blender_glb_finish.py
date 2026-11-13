# Blender: the painted Hunyuan mesh -> 2 m tall, feet at 0, centred, keeps its texture; a six-view colour preview
import bpy, sys, math
from mathutils import Vector, Matrix
a = dict(x.split("=", 1) for x in sys.argv[sys.argv.index("--") + 1:])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a["src"])
ms = [o for o in bpy.data.objects if o.type == "MESH"]
for o in bpy.data.objects: o.select_set(o in ms)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1: bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
mw = ob.matrix_world.copy(); ob.parent = None; ob.matrix_world = mw
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o is not ob: bpy.data.objects.remove(o, do_unlink=True)
co = [ob.matrix_world @ v.co for v in ob.data.vertices]
zs = [c.z for c in co]; h = max(zs) - min(zs); s = float(a.get("height", 2.0)) / h
ob.scale = (s, s, s); bpy.ops.object.transform_apply(scale=True)
co = [v.co for v in ob.data.vertices]
mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co))); mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
ob.location = (-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z); bpy.ops.object.transform_apply(location=True)
ob.name = "Bull"; bpy.ops.object.shade_smooth()
print("size", [round(x, 3) for x in ob.dimensions], "faces", len(ob.data.polygons))
bpy.ops.export_scene.gltf(filepath=a["out"], export_format="GLB", use_selection=True, export_animations=False)
# preview
sc = bpy.context.scene; sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x = 360; sc.render.resolution_y = 420; sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True; w.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.45, 0.48, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 1.6
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 2.5
import os
outs = []
for k, deg in enumerate([0, 45, 90, 135, 180, 270]):
    r = math.radians(deg); cam.location = (6 * math.sin(r), -6 * math.cos(r), 1.0)
    cam.rotation_euler = (math.radians(90), 0, r)
    p = a["prev"] + "_%d.png" % k; sc.render.filepath = p; bpy.ops.render.render(write_still=True); outs.append(p)
print("PREV", ";".join(outs))

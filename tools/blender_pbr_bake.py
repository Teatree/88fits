# 2026-11-13: a Hunyuan3D-2.1 Paint result (OBJ + albedo, metallic, roughness) made into a game GLB with a real PBR
# material and a NORMAL MAP baked from the detailed shape (the raw Hunyuan3D mesh, ~270k faces) onto the painted
# 40k-face mesh (Cycles, selected to active). Then sized like tools/blender_glb_finish.py: `height` m tall, feet at 0.
#   "$BLENDER" -b --python tools/blender_pbr_bake.py -- obj=<textured.obj> high=<raw shape .glb> out=<abs .glb>
#       [prev=<abs prefix>] [height=2] [size=2048] [extrusion=0.012] [ray=0.03]
# All paths absolute. The textures are read from the OBJ's folder (textured.jpg, textured_metallic.jpg,
# textured_roughness.jpg); the baked normal map is written beside them as textured_normal.png.
import bpy, sys, os, math
from mathutils import Vector

a = dict(x.split("=", 1) for x in sys.argv[sys.argv.index("--") + 1:])
H = float(a.get("height", 2.0))
SIZE = int(a.get("size", 2048))
bpy.ops.wm.read_factory_settings(use_empty=True)
d = os.path.dirname(a["obj"])
stem = os.path.splitext(os.path.basename(a["obj"]))[0]


def only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def joined(new):
    ms = [o for o in new if o.type == "MESH"]
    only(ms)
    if len(ms) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    mw = ob.matrix_world.copy()
    ob.parent = None
    ob.matrix_world = mw
    for o in new:
        if o is not ob and o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    only([ob])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


before = set(bpy.data.objects)
bpy.ops.wm.obj_import(filepath=a["obj"])
low = joined([o for o in bpy.data.objects if o not in before])
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=a["high"])
high = joined([o for o in bpy.data.objects if o not in before])


def box(o):
    cs = [o.matrix_world @ v.co for v in o.data.vertices]
    return Vector([min(c[i] for c in cs) for i in range(3)]), Vector([max(c[i] for c in cs) for i in range(3)])


(l0, l1), (h0, h1) = box(low), box(high)
print("low box", [round(x, 3) for x in l0], [round(x, 3) for x in l1])
print("high box", [round(x, 3) for x in h0], [round(x, 3) for x in h1])
# the painter may rescale the mesh: fit the detailed one onto it, box to box
s = (l1 - l0).length / max((h1 - h0).length, 1e-9)
high.scale = (s, s, s)
only([high])
bpy.ops.object.transform_apply(scale=True)
h0, h1 = box(high)
high.location = (l0 + l1) / 2 - (h0 + h1) / 2
bpy.ops.object.transform_apply(location=True)

# the material: albedo, metallic, roughness from the painter, the normal map baked below
mat = bpy.data.materials.new("Bull")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]


def tex(name, colour):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(os.path.join(d, name))
    if not colour:
        n.image.colorspace_settings.name = "Non-Color"
    return n


nt.links.new(tex(stem + ".jpg", True).outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(tex(stem + "_metallic.jpg", False).outputs["Color"], bsdf.inputs["Metallic"])
nt.links.new(tex(stem + "_roughness.jpg", False).outputs["Color"], bsdf.inputs["Roughness"])
nimg = bpy.data.images.new(stem + "_normal", SIZE, SIZE, alpha=False)
nimg.colorspace_settings.name = "Non-Color"
ntex = nt.nodes.new("ShaderNodeTexImage")
ntex.image = nimg
nmap = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
low.data.materials.clear()
low.data.materials.append(mat)
only([low])
bpy.ops.object.shade_smooth()

# bake: the detailed shape's normals into the painted mesh's tangent space
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 1
sc.cycles.device = "CPU"
nt.nodes.active = ntex
bpy.ops.object.select_all(action="DESELECT")
high.select_set(True)
low.select_set(True)
bpy.context.view_layer.objects.active = low
bpy.ops.object.bake(type="NORMAL", use_selected_to_active=True, cage_extrusion=float(a.get("extrusion", 0.012)),
                    max_ray_distance=float(a.get("ray", 0.03)), normal_space="TANGENT", margin=16)
npath = os.path.join(d, stem + "_normal.png")
nimg.filepath_raw = npath
nimg.file_format = "PNG"
nimg.save()
print("normal map", npath)
nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
bpy.data.objects.remove(high, do_unlink=True)

# game size: `height` tall, feet at 0, centred; Blender's Z up is glTF's Y up
l0, l1 = box(low)
k = H / (l1.z - l0.z)
low.scale = (k, k, k)
only([low])
bpy.ops.object.transform_apply(scale=True)
l0, l1 = box(low)
low.location = (-(l0.x + l1.x) / 2, -(l0.y + l1.y) / 2, -l0.z)
bpy.ops.object.transform_apply(location=True)
low.name = "Bull"
print("size", [round(x, 3) for x in low.dimensions], "faces", len(low.data.polygons))
bpy.ops.export_scene.gltf(filepath=a["out"], export_format="GLB", use_selection=True, export_animations=False,
                          export_image_format="JPEG", export_jpeg_quality=92)
print("wrote", a["out"])

if a.get("prev"):
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 360, 420
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.45, 0.48, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = H * 1.25
    for i, deg in enumerate([0, 45, 135, 180]):
        r = math.radians(deg)
        cam.location = (6 * math.sin(r), -6 * math.cos(r), H / 2)
        cam.rotation_euler = (math.radians(90), 0, r)
        sun.rotation_euler = (math.radians(50), 0, r + math.radians(30))
        sc.render.filepath = a["prev"] + "_%d.png" % i
        bpy.ops.render.render(write_still=True)

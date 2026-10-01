"""The Tommy Gun from Garry's reference model (pass 44): `_REFERENCES/3d/tommy_gun/source/tommyGunvs2.obj` (his second 3D
reference; the first pass built one from primitives and used neither) imported into Blender, its six material groups
given the game's flat colours (steel, walnut, the drum, dark iron), scaled to a true 850 mm, turned so the muzzle points
+Y (the Familiar aims down -Z in Godot after the y-up export) and exported twice: `art/props/tommy_gun.glb` and the
gold-trimmed `chicago_typewriter.glb`. The drum is its own `Drum` object with its origin on its axle, so the game can turn
it a notch per round (ProjectileEmitter: `drum_axis` "forward", because in this model the drum sits like a wheel across
the barrel). A three-quarter render on green (`tools/dl/tommy_ref.png`) is what the icon is painted from, so the icon
and the 3D gun are one gun, and the drum reads as a thick round drum rather than a flat disc.

  "$BLENDER" -b --python tools/blender_tommy.py
"""
import math
import os

import bpy
import mathutils

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OBJ = os.path.join(REPO, "_REFERENCES", "3d", "tommy_gun", "source", "tommyGunvs2.obj")
OUT = os.path.join(REPO, "game", "art", "props")
REF = os.path.join(REPO, "tools", "dl", "tommy_ref.png")
REF2 = os.path.join(REPO, "tools", "dl", "tommy_ref_side.png")
LENGTH_M = 0.85
MATS = {}


def mat(name, rgb, rough=0.6, metal=0.0):
    key = (name, rgb)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)   # what the Workbench render shows
    MATS[key] = m
    return m


STEEL = ("steel", (62, 62, 70), 0.45, 0.5)
DRUM = ("drum", (48, 48, 56), 0.5, 0.5)
DARK = ("dark", (26, 26, 30), 0.5, 0.4)
WOOD = ("wood", (122, 72, 34), 0.7, 0.0)
GOLD = ("gold", (255, 178, 59), 0.3, 0.8)

# the OBJ's material groups, named by what they are (measured in pass 44: the receiver and barrel, the three wooden parts,
# the rear sight, the drum, the stock bolt and the trigger)
GROUPS = {"lambert4SG": "body", "lambert5SG": "wood", "lambert8SG": "sight", "lambert3SG": "drum", "lambert7SG": "bolt", "lambert6SG": "trigger"}


def import_gun():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()   # the materials of the last scene went with it
    bpy.ops.wm.obj_import(filepath=OBJ)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = {}
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        mname = o.data.materials[0].name if o.data.materials else ""
        parts[GROUPS.get(mname, mname)] = o
    return parts


def finish_parts(parts, trim):
    """Flat materials, true scale, the muzzle along +Y, the receiver's middle at the origin; the drum left apart."""
    for name, o in parts.items():
        o.data.materials.clear()
        if name == "wood":
            o.data.materials.append(mat(*WOOD))
        elif name == "drum":
            o.data.materials.append(mat(*(trim if trim is GOLD else DRUM)))
        elif name == "body":
            o.data.materials.append(mat(*STEEL))
        elif name in ("sight", "bolt", "trigger"):
            o.data.materials.append(mat(*(trim if trim is GOLD else DARK)))
        else:
            o.data.materials.append(mat(*STEEL))
    objs = list(parts.values())
    # the importer maps the OBJ's +Z (the muzzle) to Blender -Y: half a turn about Z points it +Y
    xs, ys, zs = [], [], []
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            xs.append(w.x); ys.append(w.y); zs.append(w.z)
    length = max(ys) - min(ys)
    k = LENGTH_M / length
    body = parts["body"]
    bx = [(body.matrix_world @ v.co) for v in body.data.vertices]
    mid_y = (max(p.y for p in bx) + min(p.y for p in bx)) * 0.5
    # the bore: the barrel runs along the body's top; its height is set so the bore sits 45 mm up like the old model
    bore_z = max(p.z for p in bx) - 0.11 * (max(p.z for p in bx) - min(p.z for p in bx))
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in objs:
        o.location = (0.0, 0.0, 0.0)
        o.rotation_euler = (0.0, 0.0, math.pi)
        o.scale = (k, k, k)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # after the half turn, +Y is the muzzle: slide the receiver's middle to the origin and the bore to z = 0.045
    dy = -(-mid_y) * k
    dz = 0.045 - bore_z * k
    for o in objs:
        o.location = (0.0, -dy, dz)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # the drum: its own object, origin on its axle (the middle of its bounding box), so a turn spins it in place
    drum = parts["drum"]
    pts = [drum.matrix_world @ v.co for v in drum.data.vertices]
    c = mathutils.Vector(((max(p.x for p in pts) + min(p.x for p in pts)) * 0.5, (max(p.y for p in pts) + min(p.y for p in pts)) * 0.5,
                          (max(p.z for p in pts) + min(p.z for p in pts)) * 0.5))
    bpy.context.scene.cursor.location = c
    for o in bpy.context.scene.objects:
        o.select_set(False)
    drum.select_set(True)
    bpy.context.view_layer.objects.active = drum
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    drum.name = "Drum"
    # everything else joins into the Body
    rest = [o for n, o in parts.items() if n != "drum"]
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in rest:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rest[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "Body"
    bpy.ops.object.shade_flat()
    return body, drum


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def render_reference(path, three_quarter, offset=(-3.0, 1.6, 1.0)):
    """The gun on flat green, orthographic: from the front-left and a little above (the drum's round face and its rim both
    read, the angle of Garry's drawing), or from the side."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.1 if three_quarter else 1.32
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = mathutils.Vector((0.0, 0.08, 0.0))
    if three_quarter:
        # the left side, well ahead of the muzzle's line, above: -X is the gun's left when +Y is forward
        cam.location = target + mathutils.Vector(offset)
    else:
        cam.location = target + mathutils.Vector((-3.0, 0.0, 0.0))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    light_data = bpy.data.lights.new("sun", "SUN")
    light_data.energy = 3.0
    light = bpy.data.objects.new("sun", light_data)
    scene.collection.objects.link(light)
    light.rotation_euler = (math.radians(50), math.radians(20), math.radians(60))
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = False
    scene.display.shading.background_type = "WORLD"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.color = (0.0, 1.0, 0.0)
    scene.render.film_transparent = False
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(light)


def main():
    os.makedirs(OUT, exist_ok=True)
    parts = import_gun()
    body, drum = finish_parts(parts, STEEL)
    export([body, drum], "tommy_gun")
    render_reference(REF, True)
    render_reference(REF.replace("tommy_ref.png", "tommy_ref_b.png"), True, (-2.6, 2.0, 1.4))
    render_reference(REF2, False)
    parts = import_gun()
    body, drum = finish_parts(parts, GOLD)
    export([body, drum], "chicago_typewriter")
    print("blender_tommy: done")


main()

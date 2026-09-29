"""The Hammer and the Earthshaker as real models (pass 35), built from primitives and exported as GLB for the Smasher
behaviour (art/props/hammer.glb, earthshaker.glb), each rendered once from the side on green (tools/dl/hammer_ref.png,
earthshaker_ref.png) as the reference the icons are painted from.

Two objects the game moves apart: "Handle", the grip at the origin and the shaft running REST_LEN metres up +Y (the
y-up export makes that Godot's -Z; the game stretches it to the reach), and "Head", centred on its own origin with its
striking axis along +Z (Godot's +Y: at the impact the handle lies nearly flat and a face comes down on the ground).

  "$BLENDER" -b --python tools/blender_hammer.py
"""
import math
import os

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
REST_LEN = 1.1
MATS = {}


def mat(name, rgb, rough=0.6, metal=0.0, glow=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    col = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if glow:
        bsdf.inputs["Emission Color"].default_value = (glow[0] / 255.0, glow[1] / 255.0, glow[2] / 255.0, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    m.diffuse_color = col
    MATS[name] = m
    return m


def part(op, m, **kw):
    op(**kw)
    o = bpy.context.active_object
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def cyl(r, depth, loc, m, axis="z", verts=12, r2=None):
    rot = {"y": (math.pi / 2, 0, 0), "x": (0, math.pi / 2, 0), "z": (0, 0, 0)}[axis]
    return part(bpy.ops.mesh.primitive_cone_add, m, vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth, location=loc, rotation=rot)


def box(size, loc, m, rot=(0, 0, 0)):
    o = part(bpy.ops.mesh.primitive_cube_add, m, size=1.0, location=loc, rotation=rot)
    o.scale = size
    return o


def join(objs, name, origin=(0.0, 0.0, 0.0)):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.context.scene.cursor.location = origin
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.shade_flat()
    return o


def hammer(kind):
    """kind "hammer": oak and steel with brass bands; "earthshaker": a carved stone block, gold bands, glowing cracks."""
    earth = kind == "earthshaker"
    wood = mat(kind + "_wood", (70, 44, 26) if earth else (150, 96, 52), 0.7)
    grip = mat(kind + "_grip", (48, 30, 22), 0.8)
    # metal kept low: a mirror finish shows the bright desert sky and reads white from the camera's height
    band = mat(kind + "_band", (255, 176, 48) if earth else (205, 150, 60), 0.45, 0.45)
    head_m = mat(kind + "_head", (118, 110, 104) if earth else (84, 88, 100), 0.55, 0.0 if earth else 0.35)
    face_m = mat(kind + "_face", (150, 142, 134) if earth else (150, 156, 170), 0.5, 0.0 if earth else 0.35)
    handle = []
    # the shaft, a leather wrap at the grip, a knob, and a ring where the head sits
    handle.append(cyl(0.042, REST_LEN, (0, REST_LEN / 2, 0), wood, "y", 10))
    handle.append(cyl(0.05, 0.3, (0, 0.17, 0), grip, "y", 10))
    handle.append(cyl(0.062, 0.05, (0, -0.02, 0), band, "y", 10))
    handle.append(cyl(0.054, 0.04, (0, REST_LEN - 0.3, 0), band, "y", 10))
    if earth:
        for k in range(3):
            handle.append(cyl(0.05, 0.025, (0, 0.45 + 0.13 * k, 0), band, "y", 10))
    h = join(handle, "Handle")
    # the head: an octagonal drum along Z, two bands round it and a flat face at each end
    head = []
    hz = 0.34 if earth else 0.3
    hr = 0.25 if earth else 0.21
    if earth:
        head.append(box((hr * 1.7, hr * 1.7, hz * 2.0), (0, REST_LEN, 0), head_m))
    else:
        head.append(cyl(hr, hz * 2.0, (0, REST_LEN, 0), head_m, "z", 8))
    for sz in (-1, 1):
        head.append(cyl(hr * 1.08, 0.06, (0, REST_LEN, sz * hz * 0.55), band, "z", 8))
        head.append(cyl(hr * 0.9, 0.05, (0, REST_LEN, sz * (hz + 0.02)), face_m, "z", 8))
    if earth:
        glow = mat(kind + "_crack", (255, 120, 30), 0.5, 0.0, glow=(255, 110, 20))
        # glowing cracks down the stone's sides
        for sx in (-1, 1):
            head.append(box((0.02, 0.05, 0.3), (sx * hr * 0.86, REST_LEN - 0.04, 0.02), glow, (0, 0.35 * sx, 0)))
            head.append(box((0.02, 0.04, 0.16), (sx * hr * 0.86, REST_LEN + 0.07, -0.12), glow, (0, -0.5 * sx, 0)))
        for sy in (-1, 1):
            head.append(box((0.05, 0.02, 0.28), (0.03, REST_LEN + sy * hr * 0.86, 0.0), glow, (0, 0, 0.3 * sy)))
    hd = join(head, "Head", (0.0, REST_LEN, 0.0))
    return h, hd


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def render_side(path):
    """Lying on its side, the head to the right, seen from +X: the whole hammer on flat green."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = REST_LEN * 1.45
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (3.0, REST_LEN * 0.55, 0.0)
    cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
    scene.camera = cam
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


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind, ref in (("hammer", "hammer_ref.png"), ("earthshaker", "earthshaker_ref.png")):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        MATS.clear()
        h, hd = hammer(kind)
        export([h, hd], kind)
        render_side(os.path.join(DL, ref))
    print("blender_hammer: done")


main()

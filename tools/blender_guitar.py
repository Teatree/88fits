"""The Guitarra and the Requiem as real models (pass 43, Calavera's weapon), built from primitives and exported as GLB
for the ProjectileEmitter's companion (art/props/guitarra.glb, requiem.glb), each rendered once from the front on green
(tools/dl/guitarra_ref.png, requiem_ref.png) as the reference the icons are painted from.

One object, "Body": the guitar standing on its end, the neck running up +Y (the y-up export makes that Godot's -Z, the
way the companion aims), the soundboard facing +Z (Godot's +Y, up at the camera). LENGTH metres from the tail to the
headstock.

  "$BLENDER" -b --python tools/blender_guitar.py
"""
import math
import os

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
LENGTH = 0.9
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
        bsdf.inputs["Emission Strength"].default_value = 2.0
    m.diffuse_color = col
    MATS[name] = m
    return m


def part(op, m, **kw):
    op(**kw)
    o = bpy.context.active_object
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def cyl(r, depth, loc, m, axis="z", verts=16, r2=None):
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
    return o


def guitar(kind):
    """kind "guitarra": a sunburst spruce top, a dark neck, a black pickguard, steel strings; "requiem": black lacquer,
    a gold rosette and gold strings, glowing."""
    gold = kind == "requiem"
    top = mat(kind + "_top", (16, 14, 16) if gold else (214, 140, 52), 0.35 if gold else 0.55)
    burst = mat(kind + "_burst", (60, 20, 10) if gold else (110, 46, 20), 0.5)
    side = mat(kind + "_side", (26, 18, 14) if gold else (96, 52, 26), 0.6)
    neck = mat(kind + "_neck", (30, 22, 18) if gold else (58, 36, 24), 0.6)
    fret = mat(kind + "_fret", (255, 190, 70) if gold else (200, 200, 210), 0.4, 0.5)
    string = mat(kind + "_string", (255, 200, 80) if gold else (225, 225, 235), 0.35, 0.6, glow=(255, 170, 40) if gold else None)
    hole = mat(kind + "_hole", (8, 6, 6), 0.9)
    guard = mat(kind + "_guard", (255, 180, 50) if gold else (18, 16, 18), 0.4, 0.4 if gold else 0.0)
    parts = []
    # the body: two flattened drums (the lower and upper bouts) and a waist block between them, the top a shade lighter
    thick = 0.11
    lower_r, upper_r = 0.2, 0.15
    ly, uy = 0.2, 0.46
    for r, y in ((lower_r, ly), (upper_r, uy)):
        parts.append(cyl(r, thick, (0, y, 0), side, "z", 24))
        parts.append(cyl(r * 0.985, 0.012, (0, y, thick * 0.5), top, "z", 24))
        parts.append(cyl(r * 0.985, 0.012, (0, y, -thick * 0.5), burst, "z", 24))
    parts.append(box((0.24, 0.16, thick), (0, (ly + uy) * 0.5, 0), side))
    parts.append(box((0.235, 0.155, 0.012), (0, (ly + uy) * 0.5, thick * 0.5), top))
    # the burst: a darker rim on the soundboard's lower bout
    parts.append(cyl(lower_r * 0.985, 0.006, (0, ly, thick * 0.5 + 0.007), burst, "z", 24, r2=lower_r * 0.985))
    parts.append(cyl(lower_r * 0.7, 0.008, (0, ly, thick * 0.5 + 0.008), top, "z", 24))
    # the sound hole with a rosette, the bridge and the pickguard
    parts.append(cyl(0.055, 0.02, (0, 0.34, thick * 0.5 + 0.004), hole, "z", 20))
    parts.append(cyl(0.068, 0.004, (0, 0.34, thick * 0.5 + 0.012), fret, "z", 24))
    parts.append(box((0.13, 0.03, 0.014), (0, 0.15, thick * 0.5 + 0.012), neck))
    parts.append(box((0.07, 0.11, 0.006), (0.09, 0.3, thick * 0.5 + 0.012), guard, (0, 0, -0.5)))
    # the neck up +Y, the fretboard on its face, frets across it, the headstock with six pegs
    neck_y0, neck_y1 = uy, LENGTH - 0.1
    parts.append(box((0.055, neck_y1 - neck_y0 + 0.02, 0.04), (0, (neck_y0 + neck_y1) * 0.5, 0.01), neck))
    parts.append(box((0.056, neck_y1 - neck_y0, 0.008), (0, (neck_y0 + neck_y1) * 0.5, 0.034), neck))
    for k in range(9):
        fy = neck_y0 + 0.04 + (neck_y1 - neck_y0 - 0.06) * (1.0 - 0.92 ** k) / (1.0 - 0.92 ** 9)
        parts.append(box((0.056, 0.004, 0.004), (0, fy, 0.04), fret))
    parts.append(box((0.075, 0.12, 0.028), (0, LENGTH - 0.05, 0.004), neck, (0.2, 0, 0)))
    for sx in (-1, 1):
        for k in range(3):
            parts.append(cyl(0.008, 0.02, (sx * 0.044, LENGTH - 0.085 + 0.03 * k, 0.004), fret, "x", 8))
    # six strings from the bridge to the nut
    for k in range(6):
        x = -0.023 + 0.0092 * k
        parts.append(box((0.0025, LENGTH - 0.1 - 0.15, 0.0025), (x, (LENGTH - 0.1 + 0.15) * 0.5, thick * 0.5 + 0.022), string))
    return join(parts, "Body")


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def render_front(path):
    """The soundboard to the camera, the neck up, on flat green."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = LENGTH * 1.15
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.0, LENGTH * 0.47, 3.0)
    cam.rotation_euler = (0, 0, 0)
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
    for kind in ("guitarra", "requiem"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        MATS.clear()
        body = guitar(kind)
        export([body], kind)
        render_front(os.path.join(DL, kind + "_ref.png"))


main()

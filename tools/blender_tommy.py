"""The Tommy Gun as a real model: an M1928 Thompson at true proportions (850 mm long), built from primitives in Blender
and exported as GLB for the companion gun in the game (art/props/tommy_gun.glb, plus a gold-trimmed
chicago_typewriter.glb), and rendered once from the side on green (tools/dl/tommy_ref.png) as the reference the 2D
icon is painted from, so the icon and the 3D gun are the same gun.

  "$BLENDER" -b --python tools/blender_tommy.py

Forward is +Y in Blender (the muzzle), which the y-up export turns into -Z in Godot: the direction the Familiar aims.
"""
import math
import os
import sys

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
REF = os.path.join(REPO, "tools", "dl", "tommy_ref.png")
MATS = {}


def mat(name, rgb, rough=0.6, metal=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)   # what the Workbench render shows
    MATS[name] = m
    return m


STEEL = ("steel", (62, 62, 70), 0.45, 0.6)
DARK = ("dark", (26, 26, 30), 0.5, 0.4)
WOOD = ("wood", (122, 72, 34), 0.7, 0.0)
BRASS = ("brass", (205, 160, 70), 0.4, 0.8)
GOLD = ("gold", (255, 178, 59), 0.3, 0.9)


def apply(o, m):
    o.data.materials.clear()
    o.data.materials.append(mat(*m))


def cube(size, loc, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    apply(o, m)
    return o


def cyl(r, depth, loc, m, axis="y", verts=14, r2=None):
    rot = {"y": (math.pi / 2, 0, 0), "x": (0, math.pi / 2, 0), "z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    apply(o, m)
    return o


def torus(major, minor, loc, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot, major_segments=18, minor_segments=8)
    o = bpy.context.active_object
    apply(o, m)
    return o


def join(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.shade_flat()
    return o


def thompson(trim):
    """Every part in metres, the receiver's centre at the origin, +Y forward, +Z up. `trim` is the accent material."""
    parts = []
    # receiver: the milled block with the round top rib, a raised rear sight
    parts.append(cube((0.055, 0.5, 0.07), (0, 0.05, 0.02), STEEL))
    parts.append(cyl(0.028, 0.5, (0, 0.05, 0.05), STEEL, "y", 12))
    parts.append(cube((0.03, 0.03, 0.03), (0, -0.16, 0.075), DARK))
    # barrel with cooling fins and the Cutts compensator
    parts.append(cyl(0.016, 0.3, (0, 0.44, 0.045), STEEL, "y", 10))
    for k in range(9):
        parts.append(cyl(0.024, 0.01, (0, 0.31 + k * 0.012, 0.045), trim if trim is GOLD else DARK, "y", 12))
    parts.append(cyl(0.02, 0.055, (0, 0.615, 0.045), DARK, "y", 10))
    parts.append(cube((0.012, 0.012, 0.02), (0, 0.585, 0.07), DARK))
    # the 50-round drum hanging under the receiver just ahead of the trigger, axis sideways, with its winding key;
    # its own object, so the game can turn it a notch per round
    drum = [cyl(0.095, 0.05, (0, 0.13, -0.085), STEEL, "x", 20),
            cyl(0.1, 0.008, (-0.027, 0.13, -0.085), trim, "x", 20),
            cyl(0.1, 0.008, (0.027, 0.13, -0.085), trim, "x", 20),
            cyl(0.022, 0.014, (-0.036, 0.13, -0.085), BRASS, "x", 8),
            cube((0.008, 0.03, 0.006), (-0.043, 0.13, -0.085), BRASS)]
    drum_obj = join(drum, "Drum")
    # the pivot on the drum's axis, so turning it turns the drum and not the gun
    bpy.context.scene.cursor.location = (0, 0.13, -0.085)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    # vertical wooden foregrip, tilted a touch forward
    parts.append(cyl(0.02, 0.12, (0, 0.29, -0.05), WOOD, "z", 10, r2=0.015))
    # pistol grip, raked back
    parts.append(cube((0.036, 0.048, 0.13), (0, -0.055, -0.045), WOOD, (math.radians(-22), 0, 0)))
    # trigger guard and trigger
    parts.append(torus(0.028, 0.004, (0, 0.02, -0.05), DARK, (0, math.pi / 2, 0)))
    parts.append(cube((0.006, 0.008, 0.024), (0, 0.025, -0.045), DARK))
    # the stock, dropping towards the butt, and its plate
    parts.append(cube((0.04, 0.24, 0.085), (0, -0.31, -0.022), WOOD, (math.radians(7), 0, 0)))
    parts.append(cube((0.044, 0.012, 0.1), (0, -0.428, -0.037), DARK))
    # bolt handle on top, ejection port on the right
    parts.append(cyl(0.009, 0.035, (0, -0.02, 0.09), STEEL, "z", 8))
    parts.append(cube((0.004, 0.05, 0.02), (0.03, 0.1, 0.03), DARK))
    body = join(parts, "Body")
    return body, drum_obj


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def render_reference(obj):
    """The gun from its right side on flat green, orthographic, for the icon painter to copy."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.32
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (3.0, 0.1, -0.01)
    cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
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
    scene.render.filepath = REF
    bpy.ops.render.render(write_still=True)
    print("rendered", REF)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    body, drum = thompson(STEEL)
    export([body, drum], "tommy_gun")
    render_reference(body)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    body, drum = thompson(GOLD)
    export([body, drum], "chicago_typewriter")
    print("blender_tommy: done")


main()

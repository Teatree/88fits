"""The Gravity Gun and the Singularity as real models (pass 35), built from primitives and exported as GLB for the
GravityGun behaviour (art/props/gravity_gun.glb, singularity.glb), each rendered once from the side on green
(tools/dl/gravity_gun_ref.png, singularity_ref.png) as the reference the icons are painted from.

Forward is +Y (the y-up export makes it Godot's -Z, where the Familiar aims). The parts the game moves keep their names:
"Core" (the glowing ball the gun holds things with; it swells and brightens), "Spin" (an empty on the barrel's axis at
the claw ring; the game turns it about the barrel) and under it "ProngA".."ProngC" (empties rolled 0, 120 and 240
degrees round the barrel) each holding a claw "ClawA".."ClawC", hinged where it meets the ring: turning a claw about its
own X opens it away from the barrel.

  "$BLENDER" -b --python tools/blender_gravity_gun.py
"""
import math
import os

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
RING_Y = 0.2
RING_R = 0.1
MATS = {}


def mat(name, rgb, rough=0.6, metal=0.0, glow=None, strength=4.0):
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
        bsdf.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = col
    MATS[name] = m
    return m


def part(op, m, **kw):
    op(**kw)
    o = bpy.context.active_object
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def cyl(r, depth, loc, m, axis="y", verts=14, r2=None):
    rot = {"y": (math.pi / 2, 0, 0), "x": (0, math.pi / 2, 0), "z": (0, 0, 0)}[axis]
    return part(bpy.ops.mesh.primitive_cone_add, m, vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth, location=loc, rotation=rot)


def box(size, loc, m, rot=(0, 0, 0)):
    o = part(bpy.ops.mesh.primitive_cube_add, m, size=1.0, location=loc, rotation=rot)
    o.scale = size
    return o


def ball(r, loc, m):
    return part(bpy.ops.mesh.primitive_uv_sphere_add, m, radius=r, location=loc, segments=16, ring_count=8)


def torus(major, minor, loc, m, rot=(0, 0, 0)):
    return part(bpy.ops.mesh.primitive_torus_add, m, major_radius=major, minor_radius=minor, location=loc, rotation=rot, major_segments=20, minor_segments=8)


def join(objs, name, origin=(0.0, 0.0, 0.0)):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.context.scene.cursor.location = origin
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.shade_flat()
    return o


def empty(name, parent=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.empty_display_size = 0.05
    if parent:
        e.parent = parent
    e.location = loc
    e.rotation_euler = rot
    return e


def gun(kind):
    """kind "gravity_gun": copper and dark iron, a hazard band, a cyan core; "singularity": black and gold, violet core."""
    sing = kind == "singularity"
    # metal kept low: a mirror finish shows the bright desert sky and reads white from the camera's height
    shell = mat(kind + "_shell", (22, 20, 26) if sing else (120, 50, 18), 0.5, 0.35)
    iron = mat(kind + "_iron", (255, 176, 48) if sing else (52, 54, 62), 0.5, 0.35)
    band = mat(kind + "_band", (150, 70, 255) if sing else (255, 150, 30), 0.5, 0.2)
    dark = mat(kind + "_dark", (26, 24, 30), 0.6, 0.3)
    glass = mat(kind + "_glass", (190, 120, 255) if sing else (120, 230, 255), 0.2, 0.0, glow=(160, 80, 255) if sing else (90, 220, 255), strength=3.0)
    core_m = mat(kind + "_core", (230, 200, 255) if sing else (200, 250, 255), 0.2, 0.0, glow=(170, 90, 255) if sing else (80, 225, 255), strength=6.0)
    body = []
    # the housing: a fat drum along the barrel, tapering to the claw ring, capped at the back
    body.append(cyl(0.085, 0.26, (0, 0.0, 0), shell, "y", 14))
    body.append(cyl(0.085, 0.08, (0, 0.17, 0), shell, "y", 14, r2=0.06))
    body.append(cyl(0.07, 0.05, (0, -0.15, 0), iron, "y", 14))
    body.append(cyl(0.045, 0.03, (0, -0.19, 0), dark, "y", 12))
    # hazard bands and a glass coil window along the top
    for y in (-0.07, 0.07):
        body.append(cyl(0.089, 0.025, (0, y, 0), band, "y", 14))
    body.append(box((0.05, 0.16, 0.03), (0, 0.0, 0.08), glass))
    body.append(box((0.07, 0.19, 0.012), (0, 0.0, 0.094), iron))
    # the grip below, raked back, and its guard
    body.append(box((0.05, 0.07, 0.15), (0, -0.07, -0.13), dark, (math.radians(-18), 0, 0)))
    body.append(box((0.012, 0.09, 0.012), (0, -0.01, -0.105), iron))
    # the claw ring at the front
    body.append(torus(RING_R, 0.018, (0, RING_Y, 0), iron, (math.pi / 2, 0, 0)))
    b = join(body, "Body")
    core = join([ball(0.055, (0, RING_Y + 0.07, 0), core_m)], "Core", (0.0, RING_Y + 0.07, 0.0))
    spin = empty("Spin", None, (0, RING_Y, 0))
    claws = [b, core, spin]
    for k, letter in enumerate("ABC"):
        prong = empty("Prong" + letter, spin, (0, 0, 0), (0, math.radians(120.0 * k), 0))
        # a claw in the top slot: from the hinge on the ring forward, then bending in over the core
        parts = [box((0.03, 0.12, 0.022), (0, 0.06, 0.0), iron),
                 box((0.028, 0.08, 0.02), (0, 0.145, -0.03), iron, (math.radians(-35), 0, 0)),
                 box((0.034, 0.03, 0.03), (0, 0.0, 0.0), shell),
                 box((0.02, 0.03, 0.016), (0, 0.18, -0.062), band, (math.radians(-60), 0, 0))]
        c = join(parts, "Claw" + letter)
        c.parent = prong
        c.location = (0, 0, RING_R)
        claws.append(prong)
        claws.append(c)
    return claws


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
    """From the gun's right side on flat green, the claws to the right."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.74
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (2.0, 0.1, -0.03)
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
    for kind, ref in (("gravity_gun", "gravity_gun_ref.png"), ("singularity", "singularity_ref.png")):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        MATS.clear()
        objs = gun(kind)
        export(objs, kind)
        render_side(os.path.join(DL, ref))
    print("blender_gravity_gun: done")


main()

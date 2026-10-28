"""The Dynamite Bandit's cartoon bomb (pass 111, lane ENEMY; Garry: "the Dynamite Projectile is not visible enough. Make it
into one of those black round bombs instead. Make it bigger ... a nice black bomb with a flight trail instead of a dynamite
stick"): a round glossy black ball, a dull metal collar on top with a rim, and a short cord fuse curling out of it, one
mesh coloured by vertex colours (a projectile kind is one mesh in a MultiMesh; ProjectileManager.dynamite_kind gives it a
material that reads COLOR, glossy by the creature's `ranged.dynamite.material`). The fuse points up along Blender +Z
(Godot +Y), so the bomb flies and lies fuse up; the ball is 0.6 m across at scale 1.

  "$BLENDER" -b --python tools/blender_bomb.py
    -> game/art/props/enemy_bomb.glb, tools/dl/p111/enemy/bomb_ref.png (a three-quarter render on green)
    prints the fuse tip in Godot's space (the JSON's `ranged.dynamite.tip`)
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "enemy_bomb.glb")
REF = os.path.join(REPO, "tools", "dl", "p111", "enemy", "bomb_ref.png")

BLACK = (0.002, 0.002, 0.003, 1.0)
METAL = (0.36, 0.36, 0.40, 1.0)
METAL_DARK = (0.17, 0.17, 0.2, 1.0)
CORD = (0.78, 0.62, 0.38, 1.0)
CORD_DARK = (0.42, 0.29, 0.16, 1.0)
R = 0.3


def paint(o, rgba):
    attr = o.data.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for d in attr.data:
        d.color = rgba
    return o


def fuse_points():
    """The cord's centre line: up out of the collar, curling over to one side and up again at the end."""
    pts = []
    base = Vector((0.0, 0.0, R + 0.075))
    n = 28
    for k in range(n + 1):
        f = k / n
        # a lazy S: up, leaning out along +X, its end turned up again
        x = 0.11 * math.sin(f * math.pi * 0.85)
        z = 0.2 * f + 0.03 * math.sin(f * math.pi * 2.0)
        pts.append(base + Vector((x, 0.0, z)))
    return pts


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = []
    # the ball
    bpy.ops.mesh.primitive_uv_sphere_add(segments=28, ring_count=18, radius=R, location=(0, 0, 0))
    parts.append(paint(bpy.context.active_object, BLACK))
    # the collar: a short metal cylinder and a rim round its top, set into the ball's crown
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.095, depth=0.1, location=(0, 0, R + 0.02))
    parts.append(paint(bpy.context.active_object, METAL))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.095, minor_radius=0.018, location=(0, 0, R + 0.07))
    parts.append(paint(bpy.context.active_object, METAL_DARK))
    # the cord: a tube along fuse_points, banded light and dark like a twisted fuse
    pts = fuse_points()
    curve = bpy.data.curves.new("fuse", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.027
    curve.bevel_resolution = 4
    sp = curve.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for k, p in enumerate(pts):
        sp.points[k].co = (p.x, p.y, p.z, 1.0)
    cobj = bpy.data.objects.new("fuse", curve)
    bpy.context.scene.collection.objects.link(cobj)
    bpy.context.view_layer.objects.active = cobj
    for o in bpy.context.scene.objects:
        o.select_set(False)
    cobj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    cord = bpy.context.active_object
    col = cord.data.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for poly in cord.data.polygons:
        c = poly.center
        band = int((c.z - (R + 0.075)) / 0.035 + c.x / 0.03) % 2 == 0
        for li in poly.loop_indices:
            col.data[li].color = CORD if band else CORD_DARK
    parts.append(cord)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    g = bpy.context.active_object
    g.name = "Bomb"
    bpy.ops.object.shade_smooth()
    m = bpy.data.materials.new("bomb")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.25
    b.inputs["Metallic"].default_value = 0.2
    g.data.materials.clear()
    g.data.materials.append(m)
    tip = pts[-1] + (pts[-1] - pts[-2]).normalized() * 0.01
    # Blender (x, y, z) -> glTF/Godot (x, z, -y)
    print("FUSE_TIP_GODOT [%.4f, %.4f, %.4f]" % (tip.x, tip.z, -tip.y))
    return g


def export(o):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    for x in bpy.context.scene.objects:
        x.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    kw = dict(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    print("exported", OUT)


def render(o):
    os.makedirs(os.path.dirname(REF), exist_ok=True)
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.1
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0, 0, 0.12))
    pos = Vector((1.6, -1.6, 1.1))
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - pos).to_track_quat("-Z", "Y")
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_specular_highlight = True
    scene.display.shading.background_type = "WORLD"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.color = (0.0, 1.0, 0.0)
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.filepath = REF
    bpy.ops.render.render(write_still=True)
    print("rendered", REF)


g = build()
export(g)
render(g)
print("blender_bomb: done")

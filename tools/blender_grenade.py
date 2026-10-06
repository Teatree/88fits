"""The Golden Pineapple's grenade (pass 48, Garry: the evolved grenades "have a golden element to them"): a pineapple
hand grenade with a dark olive segmented body, a gold top cap and fuse, a gold spoon lever down its side and a gold pull
ring, one mesh coloured by vertex colours (a projectile kind is one mesh in a MultiMesh; the visual's material takes
COLOR as albedo). The top along +Y (the export makes it Godot's -Z), 0.56 m tall like the old 0.26 m-radius ball.

  "$BLENDER" -b --python tools/blender_grenade.py
    -> game/art/props/golden_grenade.glb, tools/dl/golden_grenade_ref.png (a three-quarter render on green)
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "golden_grenade.glb")
REF = os.path.join(REPO, "tools", "dl", "golden_grenade_ref.png")

OLIVE = (0.09, 0.13, 0.04, 1.0)
GROOVE = (0.03, 0.045, 0.015, 1.0)
GOLD = (1.0, 0.6, 0.05, 1.0)
R = 0.24


def paint(o, rgba):
    attr = o.data.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for d in attr.data:
        d.color = rgba
    return o


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = []
    # the body: an egg with raised pineapple segments (every other ring of quads pushed out)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=R, location=(0, 0, 0))
    body = bpy.context.active_object
    body.scale = (1.0, 1.18, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    me = body.data
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for poly in me.polygons:
        c = poly.center
        ring = int((c.y / (R * 1.18) + 1.0) * 5.0)
        seg = int((math.atan2(c.z, c.x) + math.pi) / (2 * math.pi) * 16)
        lit = (ring + seg) % 2 == 0
        for li in poly.loop_indices:
            col.data[li].color = OLIVE if lit else GROOVE
    parts.append(body)
    # a gold band round the waist, the gold top cap and fuse, the lever and the ring
    bpy.ops.mesh.primitive_torus_add(major_radius=R * 1.0, minor_radius=0.016, location=(0, 0, 0), rotation=(math.pi / 2, 0, 0))
    parts.append(paint(bpy.context.active_object, GOLD))
    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.075, depth=0.06, location=(0, R * 1.18 + 0.01, 0), rotation=(-math.pi / 2, 0, 0))
    parts.append(paint(bpy.context.active_object, GOLD))
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.05, depth=0.07, location=(0, R * 1.18 + 0.07, 0), rotation=(-math.pi / 2, 0, 0))
    parts.append(paint(bpy.context.active_object, GOLD))
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, R * 0.55, R * 1.02))
    lever = bpy.context.active_object
    lever.scale = (0.05, 0.42, 0.018)
    lever.rotation_euler = (math.radians(-12), 0, 0)
    parts.append(paint(lever, GOLD))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.06, minor_radius=0.012, location=(0.09, R * 1.18 + 0.07, 0.0), rotation=(0, 0, math.pi / 2))
    parts.append(paint(bpy.context.active_object, GOLD))
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    g = bpy.context.active_object
    g.name = "Grenade"
    bpy.ops.object.shade_smooth()
    m = bpy.data.materials.new("grenade")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.45
    b.inputs["Metallic"].default_value = 0.3
    g.data.materials.clear()
    g.data.materials.append(m)
    return g


def export(o):
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
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.9
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0, 0.05, 0))
    pos = Vector((1.6, 0.9, 1.6))
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - pos).to_track_quat("-Z", "Y")
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
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
print("blender_grenade: done")

"""The Vulture Raider's rocket as a real model (pass 48, Garry: "make the rocket itself the model, very dark black instead
of the yellow"): a matte near-black body, a dark red warhead band and nose tip, four dark fins, a steel nozzle ring and a
hot exhaust cup at the tail. One mesh, coloured by vertex colours (the game draws every rocket in one MultiMesh with
core/shaders/rocket.gdshader, which reads COLOR.rgb as the paint and 1 - COLOR.a as where the heat glows: only the
exhaust cup has alpha 0), the nose along +Y, which the y-up export makes Godot's -Z, where a projectile looks.
Same size as the old procedural rocket (Game._rocket_mesh): 1.04 m from tail to nose, 0.17 m body radius.

  "$BLENDER" -b --python tools/blender_rocket.py
    -> game/art/props/enemy_rocket.glb, tools/dl/enemy_rocket_ref.png (a side render on green)
"""
import math
import os

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "enemy_rocket.glb")
REF = os.path.join(REPO, "tools", "dl", "enemy_rocket_ref.png")

BLACK = (0.035, 0.035, 0.04, 1.0)
RED = (0.32, 0.03, 0.025, 1.0)
FIN = (0.06, 0.055, 0.06, 1.0)
STEEL = (0.32, 0.32, 0.34, 1.0)
HOT = (1.0, 0.45, 0.12, 0.0)   # alpha 0: the shader's heat mask

R = 0.17
TAIL = -0.42   # Blender +Y is the nose
NOSE_BASE = 0.24
NOSE = 0.62


def paint(o, rgba):
    """One flat vertex colour over the whole part (a color attribute on the face corners)."""
    me = o.data
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for d in attr.data:
        d.color = rgba
    return o


def cone(r1, r2, depth, y, rgba, verts=16):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=(0, y, 0), rotation=(-math.pi / 2, 0, 0))
    return paint(bpy.context.active_object, rgba)


def fin(angle, rgba):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    o.scale = (0.025, 0.26, 0.2)
    o.location = (math.cos(angle) * (R + 0.09), TAIL + 0.15, math.sin(angle) * (R + 0.09))
    o.rotation_euler = (0, -angle, 0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # a swept fin: the front edge pulled in towards the body
    for v in o.data.vertices:
        if v.co.y > TAIL + 0.15:
            k = 0.45
            v.co.x -= math.cos(angle) * 0.07 * k
            v.co.z -= math.sin(angle) * 0.07 * k
    return paint(o, rgba)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = []
    body_len = NOSE_BASE - TAIL
    parts.append(cone(R, R, body_len, (NOSE_BASE + TAIL) / 2, BLACK, 20))
    parts.append(cone(R * 1.02, R * 1.02, 0.07, NOSE_BASE - 0.06, RED, 20))          # the warhead band
    parts.append(cone(R, R * 0.12, NOSE - NOSE_BASE, (NOSE + NOSE_BASE) / 2, BLACK, 20))   # the nose cone
    parts.append(cone(R * 0.14, 0.0, 0.06, NOSE + 0.01, RED, 12))                    # its red tip
    parts.append(cone(R * 1.05, R * 1.05, 0.04, TAIL + 0.32, RED, 20))               # a thin red ring behind the band
    parts.append(cone(R * 0.95, R * 0.75, 0.08, TAIL - 0.02, STEEL, 16))             # the nozzle ring
    parts.append(cone(R * 0.7, R * 0.55, 0.05, TAIL - 0.07, HOT, 16))                # the hot exhaust cup
    for k in range(4):
        parts.append(fin(math.pi / 4 + k * math.pi / 2, FIN))
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    rocket = bpy.context.active_object
    rocket.name = "Rocket"
    bpy.ops.object.shade_flat()
    m = bpy.data.materials.new("rocket")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.6
    rocket.data.materials.clear()
    rocket.data.materials.append(m)
    return rocket


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


def render_side(o):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.4
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (3.0, 0.1, 0.4)
    cam.rotation_euler = (math.radians(82), 0, math.pi / 2)
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


r = build()
export(r)
render_side(r)
print("blender_rocket: done")

"""Fadeaway's basketball (Polish 2, the Escape hero): one mesh coloured by vertex colours (a projectile kind is one mesh
in a MultiMesh; the visual's material takes COLOR as albedo). A burnt-orange ball with the classic black seams: three
great circles make the eight panels (a cartoon's reading of the real two-plus-two seams). 0.22 m radius, the same
read as the Golden Pineapple's 0.24 m grenade.

  "$BLENDER" -b --python tools/blender_basketball.py
    -> game/art/props/basketball.glb, tools/dl/basketball_ref.png (a three-quarter render on green for the icon)
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "basketball.glb")
REF = os.path.join(REPO, "tools", "dl", "basketball_ref.png")

ORANGE = (0.92, 0.36, 0.06, 1.0)      # a deep burnt orange (dark enough to read on the sand: Polish 2's material note)
ORANGE_LIT = (1.0, 0.48, 0.10, 1.0)   # the upper hemisphere a touch warmer, so the ball reads as lit from above
SEAM = (0.06, 0.035, 0.02, 1.0)
R = 0.22
SEAM_W = 0.035                        # half-width of a seam band, as a fraction of R


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=56, ring_count=28, radius=R, location=(0, 0, 0))
    ball = bpy.context.active_object
    ball.name = "Basketball"
    me = ball.data
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    # the seams: three great circles (the planes x=0, y=0, z=0), tilted a little about Y so no seam sits exactly on a
    # silhouette from the game's camera
    tilt = math.radians(18.0)
    cy, sy = math.cos(tilt), math.sin(tilt)
    for poly in me.polygons:
        c = poly.center
        n = c.normalized()
        # rotate the test frame about the vertical axis (Blender Z up here; the export turns it into Godot's Y up)
        x = n.x * cy - n.y * sy
        y = n.x * sy + n.y * cy
        z = n.z
        on_seam = min(abs(x), abs(y), abs(z)) < SEAM_W
        base = ORANGE_LIT if z > 0.15 else ORANGE
        rgba = SEAM if on_seam else base
        for li in poly.loop_indices:
            col.data[li].color = rgba
    bpy.ops.object.shade_smooth()
    m = bpy.data.materials.new("basketball")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.7
    b.inputs["Metallic"].default_value = 0.0
    ball.data.materials.clear()
    ball.data.materials.append(m)
    return ball


def export(o):
    for x in bpy.context.scene.objects:
        x.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
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
    cam_data.ortho_scale = 0.7
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0, 0, 0))
    pos = Vector((1.6, -1.6, 1.0))
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
    os.makedirs(os.path.dirname(REF), exist_ok=True)
    scene.render.filepath = REF
    bpy.ops.render.render(write_still=True)
    print("rendered", REF)


ball = build()
export(ball)
render(ball)
print("blender_basketball: done")

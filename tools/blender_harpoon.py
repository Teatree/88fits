"""The harpooner's barbed hook (pass 111, lane ENEMY; Garry: "The harpoon is too simplistic. Make it look like a fat chain
so it's easier to understand what it does"): a broad iron arrowhead with two swept-back barbs, a red-painted socket
behind it and a thick eye ring at the back where the chain is shackled, one mesh coloured by vertex colours (the harpoon
is a projectile kind: one mesh in a MultiMesh; Game._harpoon_material reads COLOR). Its point is along Blender +Y, which
the glTF export makes Godot's -Z: a shot is drawn looking down its flight, so the point leads. 1.0 m long, the barbs
0.56 m across.

  "$BLENDER" -b --python tools/blender_harpoon.py
    -> game/art/props/harpoon_hook.glb, tools/dl/p111/enemy/harpoon_ref.png (a three-quarter render on green)
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "harpoon_hook.glb")
REF = os.path.join(REPO, "tools", "dl", "p111", "enemy", "harpoon_ref.png")

STEEL = (0.72, 0.74, 0.78, 1.0)
STEEL_DARK = (0.3, 0.31, 0.35, 1.0)
RED = (0.85, 0.08, 0.05, 1.0)
IRON = (0.2, 0.2, 0.23, 1.0)


def paint(o, rgba):
    attr = o.data.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for d in attr.data:
        d.color = rgba
    return o


def prism(name, pts2d, depth, y0=0.0):
    """A flat plate from a 2D outline (x across, y along the point) `depth` thick in Z, its middle at z 0."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    top = [bm.verts.new((x, y + y0, depth * 0.5)) for x, y in pts2d]
    bot = [bm.verts.new((x, y + y0, -depth * 0.5)) for x, y in pts2d]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts2d)
    for k in range(n):
        a, b = k, (k + 1) % n
        bm.faces.new([top[a], bot[a], bot[b], top[b]])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = []
    # the head: a broad leaf point with two barbs swept back (a plate, then bevelled to a thick blade)
    head = [(0.0, 0.5), (0.12, 0.3), (0.075, 0.24), (0.28, 0.06), (0.2, 0.06), (0.06, 0.16), (0.05, 0.12),
            (-0.05, 0.12), (-0.06, 0.16), (-0.2, 0.06), (-0.28, 0.06), (-0.075, 0.24), (-0.12, 0.3)]
    h = prism("head", head, 0.07)
    parts.append(paint(h, STEEL))
    # a dark ridge down the middle of the blade
    r = prism("ridge", [(0.0, 0.48), (0.03, 0.3), (0.025, 0.13), (-0.025, 0.13), (-0.03, 0.3)], 0.11)
    parts.append(paint(r, STEEL_DARK))
    # the socket and shaft: a red-painted round shaft back to the eye
    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.05, depth=0.42, location=(0, -0.07, 0), rotation=(math.pi / 2, 0, 0))
    parts.append(paint(bpy.context.active_object, RED))
    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.065, depth=0.06, location=(0, 0.12, 0), rotation=(math.pi / 2, 0, 0))
    parts.append(paint(bpy.context.active_object, IRON))
    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.065, depth=0.05, location=(0, -0.26, 0), rotation=(math.pi / 2, 0, 0))
    parts.append(paint(bpy.context.active_object, IRON))
    # the eye at the back, where the chain's last link hangs
    bpy.ops.mesh.primitive_torus_add(major_radius=0.1, minor_radius=0.032, location=(0, -0.38, 0), rotation=(0, math.pi / 2, 0))
    parts.append(paint(bpy.context.active_object, IRON))
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    g = bpy.context.active_object
    g.name = "Hook"
    # the middle of its length at the origin: the point at +0.5, the eye's back at -0.48
    m = bpy.data.materials.new("hook")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.35
    b.inputs["Metallic"].default_value = 0.5
    g.data.materials.clear()
    g.data.materials.append(m)
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
    cam_data.ortho_scale = 1.3
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0, 0, 0))
    pos = Vector((1.2, -0.6, 1.6))
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
print("blender_harpoon: done")

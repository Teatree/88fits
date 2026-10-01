"""The wooden barrel (pass 44): a bulging stave barrel with three iron hoops and a plank lid, exported as
`game/art/props/barrel.glb` with two objects, `Body` (the staves and the lid, one wood material the game tints light or
dark per barrel) and `Hoops` (iron). Origin at the base, 0.9 m tall, 0.62 m across the belly. BarrelField draws both as
MultiMeshes and breaks a barrel into Fx splinters.

  "$BLENDER" -b --python tools/blender_barrel.py
"""
import math
import os

import bmesh
import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
H = 0.9
R_END = 0.26
R_BELLY = 0.31
STAVES = 14


def mat(name, rgb, rough=0.85, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def body():
    """Staves as a lathe: five rings from the base to the top, the belly in the middle, each stave a flat facet."""
    bm = bmesh.new()
    rings = []
    for k, t in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
        r = R_END + (R_BELLY - R_END) * math.sin(t * math.pi)
        ring = []
        for i in range(STAVES):
            a = (i + 0.5) * math.tau / STAVES
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, t * H)))
        rings.append(ring)
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(STAVES):
            bm.faces.new((a[i], a[(i + 1) % STAVES], b[(i + 1) % STAVES], b[i]))
    # the lid: a flat cap a hair inside the top ring, and the base
    top = [bm.verts.new((v.co.x * 0.97, v.co.y * 0.97, H)) for v in rings[-1]]
    bm.faces.new(top)
    base = [bm.verts.new((v.co.x * 0.97, v.co.y * 0.97, 0.0)) for v in rings[0]]
    bm.faces.new(list(reversed(base)))
    # the lid planks: three raised strips across the top so the lid reads as planks from above
    for px in (-0.14, 0.0, 0.14):
        hw = 0.058
        pl = [bm.verts.new((px - hw, -0.2, H)), bm.verts.new((px + hw, -0.2, H)), bm.verts.new((px + hw, 0.2, H)), bm.verts.new((px - hw, 0.2, H))]
        pu = [bm.verts.new((v.co.x, v.co.y, H + 0.022)) for v in pl]
        bm.faces.new(pu)
        for i in range(4):
            bm.faces.new((pl[i], pl[(i + 1) % 4], pu[(i + 1) % 4], pu[i]))
    me = bpy.data.meshes.new("Body")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Body", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat("wood", (200, 200, 200), 0.85))   # white: the game tints each barrel its own wood
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def hoops():
    objs = []
    for t in (0.14, 0.5, 0.86):
        r = R_END + (R_BELLY - R_END) * math.sin(t * math.pi)
        bpy.ops.mesh.primitive_cylinder_add(vertices=STAVES, radius=r + 0.018, depth=0.07, location=(0, 0, t * H))
        o = bpy.context.active_object
        objs.append(o)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Hoops"
    o.data.materials.clear()
    o.data.materials.append(mat("iron", (58, 48, 42), 0.6, 0.3))
    bpy.ops.object.shade_flat()
    return o


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    b = body()
    h = hoops()
    for o in bpy.context.scene.objects:
        o.select_set(False)
    b.select_set(True)
    h.select_set(True)
    bpy.context.view_layer.objects.active = b
    path = os.path.join(OUT, "barrel.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


main()

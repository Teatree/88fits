"""Ironwood's Spear and the War Lance (pass 46), after the lance in Garry's reference (_REFERENCES/2d/indian.webp): a long dark
wooden shaft wrapped in red cloth at three places, two eagle feathers hanging under the head on thongs, a leaf-shaped
steel point, and a tuft of feathers at the butt.

One mesh, "Spear", several surfaces (ProjectileManager draws a weapon's shot as one mesh in a MultiMesh): the shaft along
+Y (Godot's -Z, the way a shot flies), the point at the +Y end, the origin at the middle, LENGTH metres long. war_lance.glb
is the same spear longer, the shaft gold, the point gilded, the feathers white. Each is rendered side-on and three-quarters
on a transparent film as the reference its icon is painted from (tools/dl/spear_ref.png, war_lance_ref.png).

  "$BLENDER" -b --python tools/blender_spear.py
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
MATS = {}
LOOKS = {
    "spear": {"length": 1.5, "shaft": (0.22, 0.13, 0.07), "cloth": (0.72, 0.08, 0.06), "steel": (0.62, 0.64, 0.68),
              "feather": (0.92, 0.9, 0.86), "tip": (0.08, 0.07, 0.07), "metal": 0.35},
    "war_lance": {"length": 1.75, "shaft": (0.85, 0.62, 0.2), "cloth": (0.62, 0.05, 0.05), "steel": (0.95, 0.8, 0.35),
                  "feather": (0.98, 0.97, 0.95), "tip": (0.85, 0.62, 0.2), "metal": 0.45},
}


def mat(name, rgb, rough=0.6, metal=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    MATS[name] = m
    return m


def _take(m):
    o = bpy.context.active_object
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def cyl_y(r, length, y, m, verts=8, r2=None):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=length, location=(0, y, 0), rotation=(-math.pi / 2, 0, 0))
    return _take(m)


def leaf_point(length, width, y0, m):
    """A flat leaf blade: a diamond in the shaft's plane with a ridge, its base at y0, its tip at y0 + length."""
    import bmesh
    me = bpy.data.meshes.new("leaf")
    bm = bmesh.new()
    t = width * 0.22
    v = [bm.verts.new(p) for p in ((0, y0, 0), (width * 0.5, y0 + length * 0.35, 0), (0, y0 + length, 0), (-width * 0.5, y0 + length * 0.35, 0),
                                   (0, y0 + length * 0.35, t), (0, y0 + length * 0.35, -t))]
    for f in ((0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (1, 0, 5), (2, 1, 5), (3, 2, 5), (0, 3, 5)):
        bm.faces.new([v[i] for i in f])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("leaf", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(m)
    return o


def feather(y, x, m, tip_m, drop=0.24, swing=0.0):
    """A feather hanging under the shaft on a thong: a long flat quill with a dark tip."""
    import bmesh
    me = bpy.data.meshes.new("feather")
    bm = bmesh.new()
    w = 0.05
    pts = [(x, y, -0.02), (x + w, y - 0.03, -drop * 0.35), (x + w * 0.8, y - 0.05, -drop * 0.8), (x, y - 0.06, -drop),
           (x - w * 0.8, y - 0.05, -drop * 0.8), (x - w, y - 0.03, -drop * 0.35)]
    vs = [bm.verts.new(p) for p in pts]
    bm.faces.new(vs)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("feather", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(m)
    o.rotation_euler = (0, swing, 0)
    # the dark tip
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=w * 0.85, radius2=0.0, depth=drop * 0.25, location=(x, y - 0.06, -drop * 0.95), rotation=(math.pi, 0, 0))
    tip = _take(tip_m)
    tip.scale = (1.0, 0.25, 1.0)
    return [o, tip]


def build(look):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    L = look["length"]
    shaft, cloth = mat("shaft", look["shaft"], 0.7, look["metal"] if look["shaft"][0] > 0.5 else 0.0), mat("cloth", look["cloth"], 0.9)
    steel, fth, tip = mat("steel", look["steel"], 0.35, 0.45), mat("feather", look["feather"], 0.9), mat("quill_tip", look["tip"], 0.8)
    half = L * 0.5
    head = 0.3 * L / 1.5
    parts = [cyl_y(0.022, L - head, -head * 0.5, shaft, 8)]
    # red cloth wraps: under the head, at the middle, near the butt
    for y in (half - head - 0.06, 0.02, -half + 0.12):
        parts.append(cyl_y(0.032, 0.09, y, cloth, 8))
    # the socket and the leaf point
    parts.append(cyl_y(0.026, 0.07, half - head + 0.02, steel, 8, r2=0.02))
    parts.append(leaf_point(head * 0.95, 0.13 * L / 1.5, half - head + 0.05, steel))
    # two feathers on thongs under the head, one tuft at the butt
    parts += feather(half - head - 0.12, 0.0, fth, tip, 0.24 * L / 1.5, 0.25)
    parts += feather(half - head - 0.16, 0.03, fth, tip, 0.2 * L / 1.5, -0.3)
    parts += feather(-half + 0.08, 0.0, fth, tip, 0.18 * L / 1.5, 0.15)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    sp = bpy.context.active_object
    sp.name = "Spear"
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return sp


def export(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
    print("spear: wrote", path)


def render(path, L):
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes.get("Background").inputs["Color"].default_value = (0.75, 0.75, 0.75, 1.0)
    scene.world = w
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cd.type = "ORTHO"
    cd.ortho_scale = L * 1.12
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.5
    so = bpy.data.objects.new("sun", sun)
    scene.collection.objects.link(so)
    so.rotation_euler = (0.6, -0.3, -0.5)
    # the spear laid across the picture from the lower left to the upper right, seen from its side and a little above
    sp = bpy.data.objects["Spear"]
    sp.rotation_mode = "ZYX"   # turn it across the view first, then tilt it up the diagonal
    sp.rotation_euler = (0, math.radians(-40), math.radians(-90))
    cam.location = Vector((0, -5.0, 1.2))
    cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("spear: rendered", path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for key in ("spear", "war_lance"):
        build(LOOKS[key])
        export(os.path.join(OUT, key + ".glb"))
        render(os.path.join(DL, key + "_ref.png"), LOOKS[key]["length"])


main()

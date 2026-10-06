"""The Guitarra and the Requiem from Garry's cartoon guitar (pass 46; pass 43 built a guitar from primitives).

The mesh is his: _REFERENCES/3d/cartoon-mexican-guitar.zip holds source/guitar.zip, which holds guitar.glb (seven meshes,
flat colours: a yellow top with a red line round it, green sides, a red-white-blue rosette, a black neck and headstock,
grey strings). It is imported as it is, the strings kept apart and the rest joined and decimated to a phone's budget,
stood upright and exported for ConeWave's companion:

  Body        everything but the strings, decimated (about TARGET_TRIS triangles)
  Strings     the six strings, their own node so the strum can shimmer them
  Soundhole   an empty at the middle of the soundhole: where the notes leave from

Upright: the neck runs up +Z (Godot's +Y), the top faces -Y (Godot's +Z, towards the game camera, which sits south of the
hero looking north), the origin at the soundhole, LENGTH metres from the tail to the headstock. requiem.glb is the same
mesh recoloured black and gold. Each is rendered three-quarters from the front on green as the reference its icon is
painted from (tools/dl/guitarra_ref.png, requiem_ref.png).

  "$BLENDER" -b --python tools/blender_guitar.py
"""
import io
import math
import os
import zipfile

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
ZIP = os.path.join(REPO, "_REFERENCES", "3d", "cartoon-mexican-guitar.zip")
SRC = os.path.join(DL, "refs46", "guitar", "guitar.glb")
LENGTH = 0.95
TARGET_TRIS = 7000
# the Requiem's colours: the yellow top black, the green sides and the red line gold, the rosette's blue white
REQUIEM = {"yellow": (0.035, 0.03, 0.04), "green": (0.85, 0.6, 0.16), "red": (0.95, 0.72, 0.22), "blue": (0.9, 0.88, 0.8)}


def source():
    if not os.path.exists(SRC):
        os.makedirs(os.path.dirname(SRC), exist_ok=True)
        outer = zipfile.ZipFile(ZIP)
        inner = zipfile.ZipFile(io.BytesIO(outer.read("source/guitar.zip")))
        open(SRC, "wb").write(inner.read("guitar.glb"))
    return SRC


def tri_count(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source())
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # bake the hierarchy: every mesh in world space, no parents
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    strings = [o for o in meshes if any(m and m.name == "gray" for m in o.data.materials)]
    body_parts = [o for o in meshes if o not in strings]
    # the soundhole: the middle of the rosette's blue faces (the round red-blue-white ring round the black hole)
    ring = []
    for o in body_parts:
        for p in o.data.polygons:
            m = o.data.materials[p.material_index] if p.material_index < len(o.data.materials) else None
            if m and m.name == "blue":
                ring.append(o.matrix_world @ p.center)
    hole = sum(ring, Vector()) / len(ring) if ring else Vector()
    bpy.ops.object.select_all(action="DESELECT")
    for o in body_parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body_parts[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "Body"
    tris = tri_count(body)
    if tris > TARGET_TRIS:
        dec = body.modifiers.new("dec", "DECIMATE")
        dec.ratio = TARGET_TRIS / float(tris)
        bpy.ops.object.modifier_apply(modifier=dec.name)
    st = None
    if strings:
        bpy.ops.object.select_all(action="DESELECT")
        for o in strings:
            o.select_set(True)
        bpy.context.view_layer.objects.active = strings[0]
        if len(strings) > 1:
            bpy.ops.object.join()
        st = bpy.context.active_object
        st.name = "Strings"
    # scale to LENGTH and move the soundhole to the origin
    zs = [(body.matrix_world @ Vector(v)).z for v in body.bound_box]
    s = LENGTH / (max(zs) - min(zs))
    for o in [body] + ([st] if st else []):
        o.location = (o.location - hole) * s
        o.scale = (s, s, s)
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        # origin at the soundhole for both (the strum rocks the body about it; the strings shimmer about it)
        bpy.context.scene.cursor.location = (0, 0, 0)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    for m in bpy.data.materials:
        if m.node_tree:
            b = m.node_tree.nodes.get("Principled BSDF")
            if b:
                b.inputs["Roughness"].default_value = 0.55
                b.inputs["Metallic"].default_value = 0.0
    e = bpy.data.objects.new("Soundhole", None)
    bpy.context.scene.collection.objects.link(e)
    e.location = (0, 0, 0)
    print("guitar: body %d tris (from %d), strings %s, soundhole at the origin, scale %.4f" % (tri_count(body), tris, "yes" if st else "no", s))
    return body, st


def recolour(mapping):
    for m in list(bpy.data.materials):
        if m.name in mapping and m.node_tree:
            b = m.node_tree.nodes.get("Principled BSDF")
            rgb = mapping[m.name]
            b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
            if m.name in ("green", "red"):
                b.inputs["Metallic"].default_value = 0.35
                b.inputs["Roughness"].default_value = 0.35


def export(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
    print("guitar: wrote", path)


def render_ref(path):
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    w = bpy.data.worlds.new("w")
    scene.world = w
    w.color = (0.0, 1.0, 0.0)
    scene.view_settings.view_transform = "Standard"
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cd.type = "ORTHO"
    cd.ortho_scale = LENGTH * 1.25
    # three-quarters from the front-left and a little above, the neck leaning to the upper right
    d = Vector((-0.55, -0.8, 0.3)).normalized()
    centre = Vector((0, 0, LENGTH * 0.12))
    cam.location = centre + d * 4.0
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.rotation_euler.rotate_axis("Z", math.radians(-28))
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.5
    so = bpy.data.objects.new("sun", sun)
    scene.collection.objects.link(so)
    so.rotation_euler = (0.6, -0.3, -0.5)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("guitar: rendered", path)


def main():
    os.makedirs(OUT, exist_ok=True)
    build()
    export(os.path.join(OUT, "guitarra.glb"))
    render_ref(os.path.join(DL, "guitarra_ref.png"))
    build()
    recolour(REQUIEM)
    export(os.path.join(OUT, "requiem.glb"))
    render_ref(os.path.join(DL, "requiem_ref.png"))


main()

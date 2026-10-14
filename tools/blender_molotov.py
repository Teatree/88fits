"""The Molotov's bottle and the Moonshine's jug (pass 76, lane MOLO; Garry: "Regenerate the Molotov Visuals, the flame
looks weird. Make several different versions"). Built to match the icons the family already wears: a clear bottle with
orange liquid in its lower part, a tan rag stuffed in the neck and tied round it with a flap hanging down; a round brown
pot-bellied jug with a loop handle and a cloth plug in its mouth.

Each model is ONE mesh of ONE surface in its own vertex colours (a projectile kind is one mesh in a MultiMesh), so a
mutation's `params.tint` (Sun Cocktail's gold) tints the whole of it as before. Methanol's bottle is the same bottle with
its liquid pale blue (molotov_bottle_blue.glb): Blender 5.2's glTF export wrote the vertex colours of a mesh's FIRST
primitive only (every later one came out white), so the liquid could not be a surface of its own for a material to
recolour. Vertex colours are written linear (the glTF way); Godot's import turns them back to sRGB.

The long axis is Blender's +Z (the export makes it Godot's +Y), the origin the middle of the vessel, so a shot turns about
its middle; the wick's tip (where WickFlames stands the flame) is printed and written to tools/dl/p76/MOLO/wicks.json in
Godot's axes, for each look's `params.wick_flame.offset`.

  "$BLENDER" -b --python tools/blender_molotov.py
    -> game/art/props/molotov_bottle.glb, molotov_bottle_blue.glb (Methanol's), moonshine_jug.glb,
       tools/dl/p76/MOLO/molotov_bottle_ref.png, methanol_bottle_ref.png, moonshine_jug_ref.png (three-quarter renders on
       green), tools/dl/p76/MOLO/wicks.json
"""
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(REPO, "game", "art", "props")
OUTDIR = os.path.join(REPO, "tools", "dl", "p76", "MOLO")
SEGS = 20


def lin(r, g, b, a=1.0):
    """An sRGB colour (0..1) as the linear one Blender's float colour attribute holds."""
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), a)


# the bottle
GLASS = lin(0.56, 0.84, 0.82)        # clear glass, its cool green-blue
GLASS_DARK = lin(0.32, 0.58, 0.6)    # its thick base and the neck
GLASS_HI = lin(0.9, 1.0, 0.98)       # the highlight streak down its side
RAG = lin(0.86, 0.74, 0.52)          # the tan rag
RAG_DARK = lin(0.62, 0.47, 0.3)      # its folds and stains
RAG_BURNT = lin(0.24, 0.17, 0.12)    # the burning end
STRING = lin(0.36, 0.22, 0.12)
# the liquid's greys (the material's colour does the rest): lighter at its top, darker at the bottom
LIQ_TOP = (0.98, 0.98, 0.98, 1.0)
LIQ_BOTTOM = (0.78, 0.78, 0.78, 1.0)
LIQ_HI = (1.0, 1.0, 1.0, 1.0)
# the reference renders' liquid colours (the visuals' materials use the same)
LIQ_ORANGE = (1.0, 0.6, 0.16)
LIQ_BLUE = (0.5, 0.78, 1.0)
# the jug
JUG = lin(0.58, 0.31, 0.14)
JUG_DARK = lin(0.38, 0.19, 0.08)
JUG_HI = lin(0.8, 0.5, 0.26)
JUG_LIP = lin(0.3, 0.15, 0.07)
PLUG = lin(0.55, 0.47, 0.36)
PLUG_DARK = lin(0.32, 0.26, 0.2)


def lathe(profile, segs, name):
    """A surface of revolution about Z from (r, z) points, bottom to top; r 0 at either end closes it there."""
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        if r <= 0.0:
            rings.append([bm.verts.new((0.0, 0.0, z))])
            continue
        ring = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for j in range(len(rings) - 1):
        a, b = rings[j], rings[j + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(segs):
            k2 = (k + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[k], b[k2]))
            elif len(b) == 1:
                bm.faces.new((a[k], b[0], a[k2]))
            else:
                bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def colour_faces(ob, fn):
    """Every face corner coloured fn(face centre, face normal) in the one attribute "Col"; the part gets the model's
    one material."""
    me = ob.data
    if len(me.materials) == 0:
        for m in MATS:
            me.materials.append(m)
    col = me.color_attributes.get("Col") or me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for poly in me.polygons:
        rgba = fn(poly.center, poly.normal)
        for li in poly.loop_indices:
            col.data[li].color = rgba
        poly.material_index = 0


def jitter(ob, amount, seed):
    rnd = random.Random(seed)
    for v in ob.data.vertices:
        v.co += Vector((rnd.uniform(-amount, amount), rnd.uniform(-amount, amount), rnd.uniform(-amount, amount)))


def join(parts, name):
    # every part got the same two slots before its faces were put in them (colour_faces), so a face's slot means the
    # same thing in all of them
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    ob.data.name = name
    return ob


def materials(names):
    out = []
    for n in names:
        m = bpy.data.materials.new(n)
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes.get("Principled BSDF")
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.2
        out.append(m)
    return out


def centre(ob, z0):
    """Moves the mesh so z0 sits at the origin; returns nothing."""
    for v in ob.data.vertices:
        v.co.z -= z0


def light_side(c, n):
    """0..1: how much a face looks to the highlight side (a streak of light down the glass)."""
    a = math.atan2(c.y, c.x)
    return max(0.0, math.cos(a - 0.9)) ** 6


# ---------------------------------------------------------------- the bottle

LIQ_LINE = 0.19   # the liquid's surface
BOTTLE_PROFILE = [
    (0.0, 0.0), (0.082, 0.0), (0.095, 0.008), (0.1, 0.03), (0.1, 0.1), (0.1, 0.17), (0.1, LIQ_LINE - 0.004),
    (0.1, LIQ_LINE + 0.004), (0.098, 0.215), (0.09, 0.24), (0.074, 0.262), (0.054, 0.279), (0.04, 0.29),
    (0.034, 0.302), (0.033, 0.33), (0.033, 0.345), (0.039, 0.348), (0.04, 0.358), (0.034, 0.362), (0.0, 0.362),
]
BOTTLE_MID = 0.19


MATS = []


def build_bottle(liquid):
    """The bottle with its liquid in `liquid` (an sRGB colour)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS[:] = materials(["bottle"])
    parts = []
    glass = lathe(BOTTLE_PROFILE, SEGS, "Glass")

    def glass_col(c, n):
        hi = light_side(c, n)
        if c.z < LIQ_LINE and c.z > 0.012:
            # the liquid seen through the glass, lighter near its surface and down the lit side
            f = min(max(c.z / LIQ_LINE, 0.0), 1.0)
            g = [LIQ_BOTTOM[k] + (LIQ_TOP[k] - LIQ_BOTTOM[k]) * f for k in range(3)]
            g = [g[k] + (LIQ_HI[k] - g[k]) * hi for k in range(3)]
            return lin(g[0] * liquid[0], g[1] * liquid[1], g[2] * liquid[2])
        base = GLASS_DARK if c.z <= 0.012 or c.z > 0.29 else GLASS
        g = [base[k] + (GLASS_HI[k] - base[k]) * hi for k in range(3)]
        return (g[0], g[1], g[2], 1.0)

    colour_faces(glass, glass_col)
    parts.append(glass)
    # the rag: a plug in the neck, a crumpled bunch on top, a string tied round the neck and a flap hanging from it
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.03, depth=0.05, location=(0, 0, 0.365))
    plug = bpy.context.active_object
    colour_faces(plug, lambda c, n: RAG)
    parts.append(plug)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.042, location=(0, 0, 0.392))
    bunch = bpy.context.active_object
    bunch.scale = (1.0, 0.9, 0.85)
    bpy.ops.object.transform_apply(scale=True)
    jitter(bunch, 0.007, 76)

    def bunch_col(c, n):
        if c.z > 0.41:
            return RAG_BURNT
        if (int((c.x + 0.1) * 90) + int((c.y + 0.1) * 70)) % 3 == 0:
            return RAG_DARK
        return RAG

    colour_faces(bunch, bunch_col)
    parts.append(bunch)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.036, minor_radius=0.006, major_segments=16, minor_segments=6,
                                     location=(0, 0, 0.334))
    tie = bpy.context.active_object
    colour_faces(tie, lambda c, n: STRING)
    parts.append(tie)
    # the flap: a thin bent strip of cloth from the tie down the shoulder, wider at its end
    bm = bmesh.new()
    rows = 6
    pts = []
    for j in range(rows + 1):
        f = j / rows
        z = 0.334 - f * 0.085
        x = 0.036 + f * 0.045 + 0.012 * math.sin(f * math.pi)
        hw = 0.014 + f * 0.012
        pts.append((x, hw, z))
    th = 0.004
    vs = []
    for (x, hw, z) in pts:
        vs.append([bm.verts.new((x - th, -hw, z)), bm.verts.new((x - th, hw, z)), bm.verts.new((x + th, hw, z)), bm.verts.new((x + th, -hw, z))])
    for j in range(rows):
        a, b = vs[j], vs[j + 1]
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bm.faces.new(vs[0][::-1])
    bm.faces.new(vs[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Flap")
    bm.to_mesh(me)
    bm.free()
    flap = bpy.data.objects.new("Flap", me)
    bpy.context.scene.collection.objects.link(flap)
    flap.rotation_euler = (0, 0, math.radians(-35))
    colour_faces(flap, lambda c, n: RAG_DARK if c.z < 0.27 else RAG)
    parts.append(flap)
    ob = join(parts, "Bottle")
    tip_z = max(v.co.z for v in ob.data.vertices)
    centre(ob, BOTTLE_MID)
    bpy.ops.object.shade_smooth()
    return ob, tip_z - BOTTLE_MID


# ---------------------------------------------------------------- the jug

JUG_PROFILE = [
    (0.0, 0.0), (0.09, 0.0), (0.11, 0.01), (0.13, 0.035), (0.146, 0.075), (0.15, 0.11), (0.146, 0.145),
    (0.132, 0.18), (0.108, 0.212), (0.08, 0.236), (0.058, 0.252), (0.048, 0.266), (0.046, 0.282),
    (0.056, 0.288), (0.058, 0.3), (0.05, 0.306), (0.0, 0.306),
]
JUG_MID = 0.15


def build_jug():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS[:] = materials(["jug"])
    parts = []
    body = lathe(JUG_PROFILE, SEGS + 4, "Body")

    def body_col(c, n):
        hi = light_side(c, n)
        if c.z > 0.28:
            base = JUG_LIP
        elif c.z < 0.02:
            base = JUG_DARK
        else:
            # darker towards the foot, as a glaze pools
            f = min(max((c.z - 0.02) / 0.2, 0.0), 1.0)
            base = [JUG_DARK[k] + (JUG[k] - JUG_DARK[k]) * f for k in range(3)]
        g = [base[k] + (JUG_HI[k] - base[k]) * hi * 0.8 for k in range(3)]
        return (g[0], g[1], g[2], 1.0)

    colour_faces(body, body_col)
    parts.append(body)
    # the loop handle on its shoulder (half of it inside the body, which hides it)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.058, minor_radius=0.015, major_segments=18, minor_segments=8,
                                     location=(-0.118, 0, 0.215), rotation=(math.pi / 2, 0, 0))
    handle = bpy.context.active_object
    colour_faces(handle, lambda c, n: JUG if c.x < -0.15 else JUG_DARK)
    parts.append(handle)
    # the cloth plug in its mouth, crumpled, its top burnt
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.042, depth=0.04, location=(0, 0, 0.3))
    plug = bpy.context.active_object
    colour_faces(plug, lambda c, n: PLUG)
    parts.append(plug)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.046, location=(0, 0, 0.323))
    bunch = bpy.context.active_object
    bunch.scale = (1.0, 0.92, 0.7)
    bpy.ops.object.transform_apply(scale=True)
    jitter(bunch, 0.007, 77)
    colour_faces(bunch, lambda c, n: RAG_BURNT if c.z > 0.34 else (PLUG_DARK if c.x > 0.02 else PLUG))
    parts.append(bunch)
    ob = join(parts, "Jug")
    tip_z = max(v.co.z for v in ob.data.vertices)
    centre(ob, JUG_MID)
    bpy.ops.object.shade_smooth()
    return ob, tip_z - JUG_MID


def export(ob, path):
    me = ob.data
    me.color_attributes.active_color = me.color_attributes["Col"]
    for x in bpy.context.scene.objects:
        x.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    print("exported", path)


def render(ob, path, scale=0.62):
    """A three-quarter render on green."""
    me = ob.data
    me.color_attributes.active_color = me.color_attributes["Col"]
    scene = bpy.context.scene
    cam = scene.camera
    if cam is None:
        cam_data = bpy.data.cameras.new("cam")
        cam_data.type = "ORTHO"
        cam = bpy.data.objects.new("cam", cam_data)
        scene.collection.objects.link(cam)
        scene.camera = cam
    cam.data.ortho_scale = scale
    target = Vector((0, 0, 0.0))
    pos = Vector((1.6, -1.2, 0.9))
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - pos).to_track_quat("-Z", "Y")
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.background_type = "WORLD"
    scene.display.shading.show_specular_highlight = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.color = (0.0, 1.0, 0.0)
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


os.makedirs(OUTDIR, exist_ok=True)
wicks = {}
bottle, tip = build_bottle(LIQ_ORANGE)
# Blender (x, y, z) is Godot (x, z, -y): the wick sits on the axis, so its tip is (0, tip, 0) in Godot's axes
wicks["molotov_bottle"] = [0.0, round(tip, 4), 0.0]
render(bottle, os.path.join(OUTDIR, "molotov_bottle_ref.png"))
export(bottle, os.path.join(PROPS, "molotov_bottle.glb"))
bottle, tip = build_bottle(LIQ_BLUE)
render(bottle, os.path.join(OUTDIR, "methanol_bottle_ref.png"))
export(bottle, os.path.join(PROPS, "molotov_bottle_blue.glb"))
jug, tip = build_jug()
wicks["moonshine_jug"] = [0.0, round(tip, 4), 0.0]
render(jug, os.path.join(OUTDIR, "moonshine_jug_ref.png"))
export(jug, os.path.join(PROPS, "moonshine_jug.glb"))
with open(os.path.join(OUTDIR, "wicks.json"), "w", newline="\n") as f:
    json.dump(wicks, f, indent=1)
print("wicks", wicks)
print("blender_molotov: done")

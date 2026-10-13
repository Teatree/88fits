"""Fadeaway's Hang Time trampoline (pass 70, lane TRAMP): a round backyard trampoline, a black mat stretched inside a
thick blue padded rim on steel U-legs. Exported as `game/art/props/trampoline.glb` with three objects, each its own
mesh so the game can move them apart (core/systems/Trampoline.gd):

  Mat   the black jumping mat, a disc of MAT_R at TOP, in radial rings so it can bow; its shape key "Dip" (a glTF morph
        target, a blend shape in Godot) sinks the middle DIP metres in a smooth bowl (1 - (r / MAT_R)^2), the edge held
  Rim   the padded rim over the springs, a flattened ring from PAD_IN to PAD_OUT, a little above the mat
  Legs  the steel frame ring under the pad and four U-legs down to the sand (the game folds them by scaling Y)

Every object's origin is the trampoline's centre on the ground (Blender Z up; the export turns it into Godot's Y up).
Colours are typed in sRGB and converted to linear (pass 53/54: the old scripts typed sRGB into linear colour and the
imports came out lighter). Also renders a three-quarter reference on green for the icon: tools/dl/trampoline_ref.png.

  "$BLENDER" -b --python tools/blender_trampoline.py
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "trampoline.glb")
REF = os.path.join(REPO, "tools", "dl", "trampoline_ref.png")

TOP = 0.55          # the mat's height over the sand
MAT_R = 1.0         # the mat's radius (the game's trigger radius is a little more: params.radius 1.1)
RINGS = 10          # rings of the mat from the centre out (the bowl needs them)
SEGS = 40           # segments round the circle
DIP = 0.32          # how deep "Dip" sinks the middle
PAD_IN = 0.93       # the pad's inner edge (it covers the mat's rim and the springs)
PAD_OUT = 1.28
PAD_H = 0.09        # the pad's thickness
PAD_LIFT = 0.025    # the pad's underside over the mat
FRAME_R = 1.2       # the steel ring under the pad
TUBE = 0.035        # the steel tubes' radius
LEGS = 4            # U-legs round the frame
LEG_SPREAD = 0.28   # radians between a U-leg's two uprights

BLACK = (18, 18, 22)
BLUE = (28, 96, 235)
BLUE_LIGHT = (70, 140, 255)
STEEL = (150, 156, 168)


def lin(c):
    """sRGB 0..255 to linear 0..1."""
    out = []
    for v in c:
        s = v / 255.0
        out.append(s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def mat(name, rgb, rough=0.8, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = lin(rgb)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = lin(rgb)
    return m


def link(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def mat_disc():
    """The mat: a centre vertex and RINGS rings, faces wound so their normals point up (+Z)."""
    bm = bmesh.new()
    centre = bm.verts.new((0.0, 0.0, TOP))
    rings = []
    for k in range(1, RINGS + 1):
        r = MAT_R * k / RINGS
        rings.append([bm.verts.new((math.cos(math.tau * i / SEGS) * r, math.sin(math.tau * i / SEGS) * r, TOP)) for i in range(SEGS)])
    first = rings[0]
    for i in range(SEGS):
        bm.faces.new((centre, first[i], first[(i + 1) % SEGS]))
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(SEGS):
            bm.faces.new((a[i], b[i], b[(i + 1) % SEGS], a[(i + 1) % SEGS]))
    # a thin skirt down from the edge, so the mat has an edge under the pad from a low angle
    edge = rings[-1]
    low = [bm.verts.new((v.co.x, v.co.y, TOP - 0.04)) for v in edge]
    for i in range(SEGS):
        bm.faces.new((edge[i], low[i], low[(i + 1) % SEGS], edge[(i + 1) % SEGS]))
    bm.normal_update()
    up = sum((f.normal.z for f in bm.faces if abs(f.normal.z) > 0.5), 0.0)
    if up < 0.0:
        for f in bm.faces:
            f.normal_flip()
    o = link("Mat", bm)
    o.data.materials.append(mat("mat_black", BLACK, 0.55))
    for p in o.data.polygons:
        p.use_smooth = True
    # the bowl: the middle sinks, the edge holds
    o.shape_key_add(name="Basis", from_mix=False)
    dip = o.shape_key_add(name="Dip", from_mix=False)
    for i, v in enumerate(o.data.vertices):
        r = math.hypot(v.co.x, v.co.y)
        f = max(0.0, 1.0 - (r / MAT_R) ** 2) if v.co.z > TOP - 0.01 else 0.0
        dip.data[i].co = Vector((v.co.x, v.co.y, v.co.z - DIP * f))
    return o


def pad():
    """The padded rim: a ring of SEGS boxes' worth, a rounded top (three heights across) and flat sides."""
    bm = bmesh.new()
    z0 = TOP + PAD_LIFT
    # the cross-section from the inner edge to the outer: (radius, height)
    prof = [(PAD_IN, z0), (PAD_IN, z0 + PAD_H * 0.75), (PAD_IN + 0.06, z0 + PAD_H), (PAD_OUT - 0.06, z0 + PAD_H),
            (PAD_OUT, z0 + PAD_H * 0.75), (PAD_OUT, z0)]
    loops = []
    for i in range(SEGS):
        a = math.tau * i / SEGS
        loops.append([bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)) for r, z in prof])
    n = len(prof)
    for i in range(SEGS):
        a = loops[i]
        b = loops[(i + 1) % SEGS]
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = link("Rim", bm)
    o.data.materials.append(mat("pad_blue", BLUE, 0.7))
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def tube(bm, a, b, r=TUBE, segs=10):
    """A closed steel tube from a to b."""
    d = (b - a)
    length = d.length
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=r, depth=length)
    q = d.normalized().to_track_quat("Z", "Y")
    bmesh.ops.rotate(bm, verts=res["verts"], cent=(0, 0, 0), matrix=q.to_matrix())
    bmesh.ops.translate(bm, verts=res["verts"], vec=(a + b) * 0.5)


def legs():
    bm = bmesh.new()
    zf = TOP - 0.02
    # the frame ring under the pad, as short straight tubes
    pts = [Vector((math.cos(math.tau * i / SEGS) * FRAME_R, math.sin(math.tau * i / SEGS) * FRAME_R, zf)) for i in range(SEGS)]
    for i in range(SEGS):
        tube(bm, pts[i], pts[(i + 1) % SEGS], TUBE * 0.9, 8)
    # four U-legs: two uprights a little splayed out, a bar along the sand between their feet
    for k in range(LEGS):
        mid = math.tau * (k + 0.5) / LEGS
        feet = []
        for s in (-1, 1):
            a = mid + s * LEG_SPREAD * 0.5
            top = Vector((math.cos(a) * FRAME_R, math.sin(a) * FRAME_R, zf))
            foot = Vector((math.cos(a) * (FRAME_R + 0.08), math.sin(a) * (FRAME_R + 0.08), TUBE))
            tube(bm, top, foot)
            feet.append(foot)
        tube(bm, feet[0], feet[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = link("Legs", bm)
    o.data.materials.append(mat("steel", STEEL, 0.35, 0.6))
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def export(objs):
    for x in bpy.context.scene.objects:
        x.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # no modifiers anywhere, so nothing to apply (applying would drop the Mat's shape key)
    kw = dict(filepath=OUT, export_format="GLB", use_selection=True, export_apply=False, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_morph=True, **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    print("exported", OUT)


def render():
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 3.4
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0, 0, 0.35))
    pos = Vector((4.0, -4.0, 3.6))
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - pos).to_track_quat("-Z", "Y")
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
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


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = [mat_disc(), pad(), legs()]
    export(objs)
    render()
    print("blender_trampoline: done")


main()

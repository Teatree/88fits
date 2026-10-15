"""The directional sign (pass 54, Garry: signposts round the map that point at the structures): a weathered wooden post
and one arm, exported as `game/art/props/sign.glb` with two objects.

`Post`: 0.14 m square, 2.6 m tall, dark wood, its top split down the middle the way an old post cracks; origin at its
foot. `Arm`: a board 0.9 x 0.16 x 0.05 m pointed at +X, pale weathered wood inside a darker rim on both faces, two nail
heads by the post. Its origin is ON the post's axis at the board's middle height and the board runs through the post (a
short stub shows behind it), so one yaw about the origin turns it to any heading and it still sits in the post.
SignField (game/core/systems/SignField.gd) draws one post and up to four arms per sign from these two meshes, sets its
own materials on them by name (`post`, `wood`, `rim`, `nail`) and burns each structure's name into its arm.

The Arm node stands at ARM_SHOW_Z in the file only so the model reads whole in a viewer; the game places every arm
itself.

  "$BLENDER" -b --python tools/blender_sign.py
"""
import math
import os

import bmesh
import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
POST_W = 0.14
POST_H = 2.6
SPLIT = 0.02          # the crack's width down the post's top
SPLIT_D = 0.17        # how far down it runs
SPLIT_DROP = 0.04     # each half's top slopes down this much to its outer edge
ARM_X0 = -0.12        # the board's root, past the post's axis
ARM_X1 = 0.78         # its tip: 0.9 m in all
TIP = 0.14            # the pointed end
ARM_H = 0.16
ARM_T = 0.05
RIM = 0.02            # the darker frame round each face of the board
NAIL_X = 0.11         # the nail heads, just clear of the post's face
NAIL_Z = 0.045
NAIL_S = 0.016
# pass 80 (lane WALLS, the sign's z-fighting): the heads stand 12 mm proud of the board (were 4 mm, under what the
# depth buffer tells apart once sign_depth.gdshader squeezes the sign's depth: they flickered in and out of the wood)
NAIL_UP = 0.012
ARM_SHOW_Z = 2.0

POST_RGB = (84, 60, 38)
WOOD_RGB = (150, 118, 80)
RIM_RGB = (100, 76, 50)
NAIL_RGB = (40, 34, 30)


def lin(c):
    """sRGB 0-255 to Blender's linear base colour, so the GLB shows the colour named here (the game sets its own)."""
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def mat(name, rgb, rough=0.9, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def box(bm, x0, x1, y0, y1, z0, z1, mat_index=0, top=None):
    """A closed box; `top` (four heights for the corners x0y0, x1y0, x1y1, x0y1) slants its lid."""
    tz = top if top else (z1, z1, z1, z1)
    v = [bm.verts.new(p) for p in (
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, tz[0]), (x1, y0, tz[1]), (x1, y1, tz[2]), (x0, y1, tz[3]))]
    faces = [
        (v[3], v[2], v[1], v[0]),   # bottom
        (v[4], v[5], v[6], v[7]),   # top
        (v[0], v[1], v[5], v[4]),
        (v[1], v[2], v[6], v[5]),
        (v[2], v[3], v[7], v[6]),
        (v[3], v[0], v[4], v[7]),
    ]
    out = []
    for f in faces:
        face = bm.faces.new(f)
        face.material_index = mat_index
        out.append(face)
    return out


def post():
    bm = bmesh.new()
    h = POST_W * 0.5
    s = SPLIT * 0.5
    z_split = POST_H - SPLIT_D
    box(bm, -h, h, -h, h, 0.0, z_split)
    # the split top: two halves with the crack between them, each sloping down to its outer edge
    box(bm, -h, -s, -h, h, z_split, POST_H, top=(POST_H - SPLIT_DROP, POST_H, POST_H, POST_H - SPLIT_DROP))
    box(bm, s, h, -h, h, z_split, POST_H, top=(POST_H, POST_H - SPLIT_DROP, POST_H - SPLIT_DROP, POST_H))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("Post")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Post", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat("post", POST_RGB, 0.95))
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def outline():
    """The board's edge in (x, z), counter-clockwise seen from -Y: root bottom, along to the tip, back along the top."""
    hz = ARM_H * 0.5
    return [(ARM_X0, -hz), (ARM_X1 - TIP, -hz), (ARM_X1, 0.0), (ARM_X1 - TIP, hz), (ARM_X0, hz)]


def inset(poly, d):
    """A convex polygon (counter-clockwise) moved `d` inwards: each edge pushed in along its inward normal, the corners
    where the pushed edges meet."""
    n = len(poly)
    lines = []
    for i in range(n):
        (x0, z0), (x1, z1) = poly[i], poly[(i + 1) % n]
        ex, ez = x1 - x0, z1 - z0
        ln = math.hypot(ex, ez)
        nx, nz = -ez / ln, ex / ln          # the inward normal of a counter-clockwise edge
        lines.append(((x0 + nx * d, z0 + nz * d), (ex, ez)))
    out = []
    for i in range(n):
        (p, r), (q, s) = lines[i - 1], lines[i]
        den = r[0] * s[1] - r[1] * s[0]
        t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / den
        out.append((p[0] + r[0] * t, p[1] + r[1] * t))
    return out


def arm():
    bm = bmesh.new()
    outer = outline()
    inner = inset(outer, RIM)
    n = len(outer)
    ht = ARM_T * 0.5
    rings = {}
    for side, y in (("front", -ht), ("back", ht)):
        o = [bm.verts.new((x, y, z)) for x, z in outer]
        i = [bm.verts.new((x, y, z)) for x, z in inner]
        rings[side] = o
        panel = bm.faces.new(i)
        panel.material_index = 0                 # pale wood
        for k in range(n):
            f = bm.faces.new((o[k], o[(k + 1) % n], i[(k + 1) % n], i[k]))
            f.material_index = 1                 # the darker rim
    fo, bo = rings["front"], rings["back"]
    for k in range(n):
        f = bm.faces.new((fo[k], bo[k], bo[(k + 1) % n], fo[(k + 1) % n]))
        f.material_index = 1
    # two nail heads on each face, just clear of the post
    for y, sgn in ((-ht, -1.0), (ht, 1.0)):
        for z in (-NAIL_Z, NAIL_Z):
            ys = sorted((y, y + sgn * NAIL_UP))
            box(bm, NAIL_X - NAIL_S * 0.5, NAIL_X + NAIL_S * 0.5, ys[0], ys[1], z - NAIL_S * 0.5, z + NAIL_S * 0.5, 2)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("Arm")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Arm", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat("wood", WOOD_RGB, 0.9))
    o.data.materials.append(mat("rim", RIM_RGB, 0.9))
    o.data.materials.append(mat("nail", NAIL_RGB, 0.6, 0.3))
    for p in o.data.polygons:
        p.use_smooth = False
    o.location = (0.0, 0.0, ARM_SHOW_Z)
    return o


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    p = post()
    a = arm()
    for o in bpy.context.scene.objects:
        o.select_set(False)
    p.select_set(True)
    a.select_set(True)
    bpy.context.view_layer.objects.active = p
    path = os.path.join(OUT, "sign.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


main()

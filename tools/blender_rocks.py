"""Pass 148 (lane ROCKS; Garry: the painted rocks "feel a little detached from the ground", the little rocks at their foot "at
a different angle from the 3D view"): the four rock paintings' shapes as low-poly models, rendered from the game's own
camera pitch (~48 degrees above the ground, orthographic), so tools/gen_prop_variants.py paints each over its render and
the painting's perspective is the world's. No pebbles at the foot: each rock is one body (boulder_b a boulder on its
pedestal), its base cut flat on the ground, so the bottom edge seen from above is the rock meeting the sand.

It is no game asset: it renders the references gen_prop_variants paints from (the blue screen, flat studio colours):

  "$BLENDER" -b --python tools/blender_rocks.py [-- only=rock_small,rock_big,boulder,boulder_b pitch=48 size=1024
      out=tools/dl/p148/ROCKS/render smooth=0|1 (1: subdivided and smooth-shaded, round 2's renders)]
      -> <out>/<id>_ref.png (flat colours) and <id>_ref_clay.png (grey, the shapes only)
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_lowpoly as lp  # noqa: E402
import blender_cart as bc  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SMOOTH = False

# sandstone, sRGB 0..1: the paintings' tan and orange, the bands of the boulders
TAN = (0.86, 0.62, 0.42)
ORANGE = (0.80, 0.47, 0.30)
PALE = (0.93, 0.75, 0.55)
RUST = (0.70, 0.38, 0.25)


def arg(name, default):
    for a in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default


def lump(bm, centre, size, seed, sub=2, rough=0.18, cuts=7, flat_top=0.0):
    """A faceted rock: an icosphere of `size` (x, y, z radii) roughened by noise, then cut by `cuts` random planes (the
    flat chipped faces sandstone breaks into); flat_top > 0 cuts a level top at that share of its height."""
    rng = random.Random(seed)
    geom = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    verts = geom["verts"]
    off = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
    for v in verts:
        n = noise.noise(v.co * 1.4 + off)
        k = 1.0 + rough * n
        v.co = Vector((v.co.x * size[0] * k, v.co.y * size[1] * k, v.co.z * size[2] * k)) + Vector(centre)
    if SMOOTH:
        # round 2: no chipped planes (the painter copied them as crystal faces); a flat top is the lump pressed level
        if flat_top > 0.0:
            zt = centre[2] + size[2] * flat_top
            for v in verts:
                v.co.z = min(v.co.z, zt + 0.03 * noise.noise(v.co * 3.0 + off))
        return
    for _ in range(cuts):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 1.0))).normalized()
        reach = max(size) * rng.uniform(0.78, 0.92)
        co = Vector(centre) + Vector((d.x * size[0], d.y * size[1], d.z * size[2])).normalized() * reach * 0.95
        _cut(bm, co, d)
    if flat_top > 0.0:
        _cut(bm, Vector(centre) + Vector((0, 0, size[2] * flat_top)), Vector((0.05, -0.08, 1.0)).normalized())


def _cut(bm, co, normal):
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=normal, clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        try:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        except Exception:
            pass


def ground(bm, embed):
    """The base cut flat at z 0, `embed` of the height up from the lowest point (the rock sits in the sand, its foot
    as wide as its body there, never a ball on a point)."""
    zmin = min(v.co.z for v in bm.verts)
    zmax = max(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= zmin + embed * (zmax - zmin)
    _cut(bm, Vector((0, 0, 0.0)), Vector((0, 0, -1)))
    for v in bm.verts:
        v.co.z = max(v.co.z, 0.0)


def colour(bm, me, bands, seed, top):
    """A colour a face: the sandstone by height (bands: strata), a little jitter, the top faces paler."""
    rng = random.Random(seed)
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for poly in me.polygons:
        z = poly.center.z / max(top, 0.01)
        if bands:
            b = int(math.floor(z * bands + 0.3 * math.sin(poly.center.x * 2.1)))
            col = (TAN, ORANGE, PALE, RUST)[b % 4]
        else:
            col = TAN if poly.normal.z > 0.35 else ORANGE
        if poly.normal.z > 0.75:
            col = tuple(min(1.0, c * 1.08) for c in PALE)
        k = 1.0 + rng.uniform(-0.05, 0.05)
        lin = tuple(lp.lin(min(c * k, 1.0)) for c in col) + (1.0,)
        for li in poly.loop_indices:
            attr.data[li].color = lin


# id: (lumps [(centre, radii, seed, flat_top, subdivisions, cuts)], bands, seed, embed)
ROCKS = {
    # a rounded dome, a little wider than tall (0.8 m painting)
    "rock_small": ([((0, 0, 0.3), (0.45, 0.38, 0.4), 11, 0.0, 2, 6)], 0, 18, 0.22),
    # a big rounded block with a flat top, much wider than tall (1.6 m painting)
    "rock_big": ([((0, 0, 0.5), (0.8, 0.64, 0.62), 23, 0.6, 2, 7)], 0, 19, 0.2),
    # a huge rounded boulder with layered bands (2.8 m painting)
    "boulder": ([((0, 0, 1.0), (1.05, 0.92, 1.12), 37, 0.0, 3, 6)], 6, 20, 0.16),
    # a balanced rock: a big boulder on a shorter, narrower pedestal (2.8 m painting)
    "boulder_b": ([((0, 0, 0.55), (0.6, 0.52, 0.72), 41, 0.7, 3, 5), ((0.08, 0.0, 1.62), (0.95, 0.8, 0.62), 43, 0.0, 3, 6)], 7, 8531, 0.1),
}


# round 2 (smooth=1): rounder lumps; the boulders as stacked sandstone slabs (the layered look of the old paintings)
ROCKS_SMOOTH = {
    "rock_small": ([((0, 0, 0.3), (0.45, 0.38, 0.38), 11, 0.0, 3, 0), ((0.18, -0.12, 0.2), (0.25, 0.22, 0.22), 12, 0.0, 3, 0)], 0, 18, 0.2),
    "rock_big": ([((0, 0, 0.5), (0.8, 0.64, 0.6), 23, 0.55, 3, 0)], 0, 19, 0.18),
    "boulder": ([((0, 0, 0.42), (1.0, 0.86, 0.52), 37, 0.0, 3, 0), ((0.05, 0.02, 0.95), (1.0, 0.86, 0.52), 38, 0.0, 3, 0),
                 ((-0.04, 0.0, 1.45), (0.92, 0.8, 0.5), 39, 0.0, 3, 0), ((0.04, 0.03, 1.85), (0.72, 0.64, 0.42), 40, 0.5, 3, 0)], 6, 20, 0.1),
    "boulder_b": ([((0, 0, 0.3), (0.62, 0.55, 0.36), 41, 0.0, 3, 0), ((0.03, 0.0, 0.75), (0.5, 0.45, 0.32), 42, 0.0, 3, 0),
                   ((0.1, 0.0, 1.45), (1.05, 0.88, 0.48), 43, 0.0, 3, 0), ((0.06, 0.02, 2.0), (0.82, 0.7, 0.38), 44, 0.45, 3, 0)], 7, 8531, 0.08),
}


def build(id_):
    lumps, bands, seed, embed = (ROCKS_SMOOTH if SMOOTH else ROCKS)[id_]
    bm = bmesh.new()
    for centre, radii, s, flat, sub, cuts in lumps:
        part = bmesh.new()
        lump(part, centre, radii, s, sub=sub, cuts=cuts, flat_top=flat)
        tmp = bpy.data.meshes.new("tmp")
        part.to_mesh(tmp)
        part.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    ground(bm, embed)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(id_)
    bm.to_mesh(me)
    bm.free()
    me.update()
    top = max(v.co.z for v in me.vertices)
    colour(None, me, bands, seed, top)
    ob = bpy.data.objects.new(id_, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = SMOOTH
    if SMOOTH:
        # round 2: the facets rounded off (the painter had copied them as crystal faces), the flat cuts kept as soft planes
        mod = ob.modifiers.new("sub", "SUBSURF")
        mod.levels = 2
        mod.render_levels = 2
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.modifier_apply(modifier="sub")
        me = ob.data
        zmin = min(v.co.z for v in me.vertices)
        for v in me.vertices:
            v.co.z -= zmin
        for p in me.polygons:
            p.use_smooth = True
    return ob


def main():
    out = arg("out", "tools/dl/p148/ROCKS/render")
    if not os.path.isabs(out):
        out = os.path.join(REPO, out)
    global SMOOTH
    SMOOTH = arg("smooth", "0") == "1"
    pitch = float(arg("pitch", 48.0))
    size = int(arg("size", 1024))
    only = [s for s in arg("only", ",".join(ROCKS)).split(",") if s]
    for id_ in only:
        lp.fresh()
        ob = build(id_)
        ob.rotation_euler = (0.0, 0.0, math.radians(float(arg("yaw", 20.0))))
        bpy.context.view_layer.update()
        bc.render(ob, os.path.join(out, id_ + "_ref.png"), pitch, size, (0.0, 0.0, 1.0))


if __name__ == "__main__":
    main()

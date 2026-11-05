"""Pass 126 (lane DRESS): the small kit tools/blender_telephone.py, blender_wheel.py and blender_grave_cross.py build their
low-poly scenery with: prisms and boxes with one colour a face (a little jitter, so the wood is not one flat tone), one
object per model, flat shaded, colours as a corner colour attribute, exported as one GLB (Godot's y-up: Blender z is up,
Blender +x stays +x, Blender +y turns into Godot -z). The game reads the vertices and colours and merges them itself
(core/systems/MapDressing.gd), so no material of the file is ever drawn.

Colours are given as the sRGB values you would pick (0..1) and written linear: the game's shader takes COLOR as albedo.
"""
import math
import random

import bpy
from mathutils import Matrix, Vector


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


class Model:
    def __init__(self, name, seed=1, jitter=0.07):
        self.name = name
        self.verts = []
        self.faces = []
        self.cols = []
        self.rng = random.Random(seed)
        self.jitter = jitter

    def face(self, idx, col):
        k = 1.0 + self.rng.uniform(-self.jitter, self.jitter)
        self.faces.append(idx)
        self.cols.append((lin(min(col[0] * k, 1.0)), lin(min(col[1] * k, 1.0)), lin(min(col[2] * k, 1.0)), 1.0))

    def ring(self, centre, axis, r, n, phase=0.0, squash=1.0):
        """`n` points round `axis` at `centre`, radius r (squash: the second direction's share); returns their indices."""
        a = Vector(axis).normalized()
        u = a.orthogonal().normalized()
        v = a.cross(u).normalized()
        c = Vector(centre)
        out = []
        for k in range(n):
            t = phase + math.tau * k / n
            out.append(len(self.verts))
            self.verts.append(c + u * (math.cos(t) * r) + v * (math.sin(t) * r * squash))
        return out

    def tube(self, points, radii, col, n=6, caps=(True, True), squash=1.0, phase=0.0):
        """A prism through `points` (at least two), each with its radius; its rings keep one frame along the way."""
        rings = []
        # one frame for the whole tube, from its overall direction: rings of a bent tube do not twist against each other
        d = Vector(points[-1]) - Vector(points[0])
        for p in points:
            rings.append(self.ring(p, d, radii[len(rings)], n, phase, squash))
        for r0, r1 in zip(rings[:-1], rings[1:]):
            for k in range(n):
                k2 = (k + 1) % n
                self.face([r0[k], r0[k2], r1[k2], r1[k]], col)
        if caps[0]:
            self.face(list(reversed(rings[0])), col)
        if caps[1]:
            self.face(list(rings[-1]), col)
        return rings

    def box(self, centre, size, col, rot=(0.0, 0.0, 0.0)):
        """A box of `size` (x, y, z) turned by `rot` (degrees about x, y, z) about its centre."""
        m = Matrix.Translation(centre) @ (Matrix.Rotation(math.radians(rot[2]), 4, "Z") @ Matrix.Rotation(math.radians(rot[1]), 4, "Y") @ Matrix.Rotation(math.radians(rot[0]), 4, "X"))
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        base = len(self.verts)
        for sx, sy, sz in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)):
            self.verts.append(m @ Vector((sx * hx, sy * hy, sz * hz)))
        for f in ((3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face([base + i for i in f], col)

    def build(self):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        me.update()
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        for poly, col in zip(me.polygons, self.cols):
            for li in poly.loop_indices:
                attr.data[li].color = col
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        for p in me.polygons:
            p.use_smooth = False
        m = bpy.data.materials.get("dress") or bpy.data.materials.new("dress")
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes.get("Principled BSDF")
        if b is not None and not any(n.bl_idname == "ShaderNodeVertexColor" for n in nt.nodes):
            node = nt.nodes.new("ShaderNodeVertexColor")
            node.layer_name = "Col"
            nt.links.new(node.outputs["Color"], b.inputs["Base Color"])
        me.materials.append(m)
        return ob


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def export(objs, path):
    for x in bpy.context.scene.objects:
        x.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    print("exported", path, "tris", sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs))

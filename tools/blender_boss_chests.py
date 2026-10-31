"""The bosses' own chests (pass 118, lane BOSSCHEST; Garry: "Each Boss now drops a unique chest ... Each Boss Chest has a
unique 3d model. There is also a 2d drawing of the chest with an opening animation."): one chest a boss, built from
primitives into a Body and a hinged Lid (the convention of art/props/meta/chest.glb, tools/blender_meta.py: the Lid's
origin on the back top edge, so a rotation about X opens it), exported as GLB, and rendered closed, cracked and open in
the three-quarter view the 2D paintings are made from (tools/gen_boss_chests.py paints over them with Klein, so the 2D
chest and the 3D one are one thing).

  "$BLENDER" -b --python tools/blender_boss_chests.py [-- only=tumbleweed_king,brander] [renders=0]
      -> game/art/props/meta/boss_chest_<boss>.glb
      -> tools/dl/bosschest/<boss>_<pose>.png (closed, cracked, open: 1024 px, transparent film)

  tumbleweed_king  woven straw and rope, gold corners, a golden crown on the lid with a green gem, tumbleweed tufts
  gila_grande      beaded scales in the gila monster's black and orange, bone bands, saguaro cacti on the lid
  brander          black iron plates and rivets, red-hot brands glowing on the front and the lid, chains, spikes

Units are metres, +Z up in Blender (+Y in Godot), the front (the lock) faces -Y (Godot +Z). Every part is built in one
bmesh per object with a material slot each, so a chest is a handful of surfaces however many beads or rivets it has.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "meta")
REN = os.path.join(REPO, "tools", "dl", "bosschest")

# the shared proportions: a body W x D x H, a flat lid slab and a barrel top, hinged on the back top edge
W = 1.22
D = 0.86
H = 0.62
SLAB = 0.1
BARREL_R = D * 0.5
HINGE = (0.0, D * 0.5, H + SLAB)

MATS = {}


def lin(v):
    """An sRGB channel 0-255 as a linear factor."""
    c = v / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def mat(name, rgb, rough=0.7, metal=0.0, emit=None, strength=0.0):
    """A material by name (made once): its colour as 0-255 RGB, roughness, metalness, and an emission colour and
    strength for what glows (the Brander's brands, the light inside an open chest)."""
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    # the colours are picked as sRGB; Blender and glTF hold linear factors (blender_meta's were taken as linear and
    # came out pale in the game)
    c = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)
    bsdf.inputs["Base Color"].default_value = c
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (lin(emit[0]), lin(emit[1]), lin(emit[2]), 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = c
    MATS[name] = m
    return m


class Part:
    """One object's mesh, built in a bmesh with a material index per piece."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    def _mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _paint(self, verts, m):
        mi = self._mi(m)
        faces = set()
        for v in verts:
            for f in v.link_faces:
                faces.add(f)
        for f in faces:
            f.material_index = mi

    def box(self, size, loc, m, rot=(0.0, 0.0, 0.0)):
        mx = Matrix.LocRotScale(Vector(loc), Euler(rot).to_quaternion(), Vector(size))
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mx)
        self._paint(r["verts"], m)
        return r["verts"]

    def cyl(self, r, depth, loc, m, rot=(0.0, 0.0, 0.0), segs=12, r2=None):
        """A cylinder (or a cone with r2) along its local Z, turned by `rot`."""
        mx = Matrix.LocRotScale(Vector(loc), Euler(rot).to_quaternion(), Vector((1.0, 1.0, 1.0)))
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                                    radius2=r if r2 is None else r2, depth=depth, matrix=mx)
        self._paint(res["verts"], m)
        return res["verts"]

    def ball(self, r, loc, m, segs=10, rings=6, scale=(1.0, 1.0, 1.0)):
        mx = Matrix.LocRotScale(Vector(loc), Euler((0, 0, 0)).to_quaternion(), Vector(scale))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=r, matrix=mx)
        self._paint(res["verts"], m)
        return res["verts"]

    def torus(self, R, r, loc, m, rot=(0.0, 0.0, 0.0), segs=14, sides=6, scale=(1.0, 1.0, 1.0)):
        """A ring of radius R and tube r in its local XY plane (a chain link: scale it long on X)."""
        mx = Matrix.LocRotScale(Vector(loc), Euler(rot).to_quaternion(), Vector((1.0, 1.0, 1.0)))
        sc = Matrix.Diagonal(Vector(scale)).to_4x4()
        verts = []
        rings = []
        for i in range(segs):
            a = 2.0 * math.pi * i / segs
            ring = []
            for j in range(sides):
                b = 2.0 * math.pi * j / sides
                p = Vector(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
                v = self.bm.verts.new(mx @ (sc @ p))
                ring.append(v)
                verts.append(v)
            rings.append(ring)
        mi = self._mi(m)
        for i in range(segs):
            for j in range(sides):
                a, b = rings[i][j], rings[i][(j + 1) % sides]
                c, d = rings[(i + 1) % segs][(j + 1) % sides], rings[(i + 1) % segs][j]
                self.bm.faces.new((a, b, c, d)).material_index = mi
        return verts

    def sweep(self, pts, r, mat_of, sides=8, closed=True):
        """A tube of radius r along the points (a rope, a chain's line); `mat_of(i, j)` names segment i, side j's
        material (a rope's twist is a diagonal stripe of the darker strand)."""
        n = len(pts)
        rings = []
        for i in range(n):
            p = Vector(pts[i])
            a = Vector(pts[(i - 1) % n]) if (closed or i > 0) else p
            b = Vector(pts[(i + 1) % n]) if (closed or i < n - 1) else p
            t = (b - a).normalized()
            up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            u = t.cross(up).normalized()
            w = t.cross(u).normalized()
            ring = []
            for j in range(sides):
                ang = 2.0 * math.pi * j / sides
                ring.append(self.bm.verts.new(p + (u * math.cos(ang) + w * math.sin(ang)) * r))
            rings.append(ring)
        last = n if closed else n - 1
        for i in range(last):
            for j in range(sides):
                a, b = rings[i][j], rings[i][(j + 1) % sides]
                c, d = rings[(i + 1) % n][(j + 1) % sides], rings[(i + 1) % n][j]
                self.bm.faces.new((a, b, c, d)).material_index = self._mi(mat_of(i, j))

    def to_object(self, origin=(0.0, 0.0, 0.0)):
        """The finished object, its origin at `origin` (the lid's hinge), flat-shaded."""
        bmesh.ops.translate(self.bm, vec=-Vector(origin), verts=self.bm.verts)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = origin
        return ob


def barrel_point(x, ang, rr=None):
    """A point on the lid's barrel top: `ang` 0 at the front edge, pi at the back."""
    r = BARREL_R if rr is None else rr
    return (x, -math.cos(ang) * r, H + SLAB + math.sin(ang) * r)


def rounded_rect_loop(w, d, z, rad, n_side=6, n_corner=5):
    """A closed loop round the body at height z (a rope or a chain's line), its corners rounded by `rad`."""
    pts = []
    hx, hy = w * 0.5 - rad, d * 0.5 - rad
    corners = [((hx, -hy), -math.pi * 0.5), ((hx, hy), 0.0), ((-hx, hy), math.pi * 0.5), ((-hx, -hy), math.pi)]
    for k, ((cx, cy), a0) in enumerate(corners):
        for i in range(n_corner):
            a = a0 + (math.pi * 0.5) * i / (n_corner - 1)
            pts.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad, z))
        (nx, ny), _ = corners[(k + 1) % 4]
        ex = (cx + math.cos(a0 + math.pi * 0.5) * rad, cy + math.sin(a0 + math.pi * 0.5) * rad)
        sx = (nx + math.cos(a0 + math.pi * 0.5) * rad, ny + math.sin(a0 + math.pi * 0.5) * rad)
        for i in range(1, n_side):
            f = i / n_side
            pts.append((ex[0] + (sx[0] - ex[0]) * f, ex[1] + (sx[1] - ex[1]) * f, z))
    return pts


def barrel(part, r, width, x, m, segs=36):
    """A half cylinder along X over the lid's slab (the barrel top, a band or a strap round it): a whole one whose lower
    half is squashed flat just inside the slab, so nothing hangs under the lid line or swings out when it opens."""
    verts = part.cyl(r, width, (x, 0, H + SLAB), m, rot=(0, math.pi * 0.5, 0), segs=segs)
    for v in verts:
        if v.co.z < H + SLAB:
            v.co.z = H + SLAB - 0.004
    return verts


def lid_shell(lid, m_wood, m_rim):
    """The lid every chest shares: a slab and the barrel top over it (a half cylinder, its flat side down), a rim."""
    lid.box((W + 0.04, D + 0.04, SLAB), (0, 0, H + SLAB * 0.5), m_wood)
    barrel(lid, BARREL_R, W + 0.04, 0.0, m_wood)
    lid.box((W + 0.08, D + 0.08, 0.05), (0, 0, H + 0.025), m_rim)


def body_shell(body, m_wood, m_trim):
    body.box((W, D, H), (0, 0, H * 0.5), m_wood)
    body.box((W + 0.05, D + 0.05, 0.06), (0, 0, 0.03), m_trim)
    body.box((W + 0.05, D + 0.05, 0.05), (0, 0, H - 0.025), m_trim)


def corner_caps(body, m, s=0.11):
    """Metal caps on the body's eight corners."""
    for x in (-1, 1):
        for y in (-1, 1):
            for z, h in ((0.0, s), (H - s, s)):
                body.box((s, s, h), (x * (W * 0.5 - s * 0.5 + 0.015), y * (D * 0.5 - s * 0.5 + 0.015), z + h * 0.5), m)


# ---------------------------------------------------------------- the Tumbleweed King's
def king():
    straw = mat("king_straw", (214, 168, 78), 0.95)
    straw_dk = mat("king_straw_dark", (164, 112, 46), 0.95)
    rope = mat("king_rope", (196, 150, 92), 0.95)
    rope_dk = mat("king_rope_dark", (130, 92, 50), 0.95)
    gold = mat("king_gold", (255, 196, 48), 0.3, 0.9)
    gem = mat("king_gem", (110, 210, 40), 0.2, 0.0, (90, 200, 30), 0.6)
    ruby = mat("king_ruby", (220, 40, 50), 0.2)
    twig = mat("king_twig", (150, 104, 60), 0.95)
    body = Part("Body")
    body_shell(body, straw, straw_dk)
    # the basket weave: raised strips across, standing out of every face in a checker
    strip = 0.085
    rows = int(H / strip)
    for side, (nx, ny) in (("front", (0, -1)), ("back", (0, 1)), ("left", (-1, 0)), ("right", (1, 0))):
        span = W if ny != 0 else D
        cols = int(span / 0.16)
        for r in range(1, rows - 1):
            z = 0.06 + r * strip + strip * 0.5
            for c in range(cols):
                if (r + c) % 2:
                    continue
                t = -span * 0.5 + (c + 0.5) * span / cols
                if ny != 0:
                    loc = (t, ny * (D * 0.5 + 0.012), z)
                    size = (span / cols * 0.92, 0.03, strip * 0.8)
                else:
                    loc = (nx * (W * 0.5 + 0.012), t, z)
                    size = (0.03, span / cols * 0.92, strip * 0.8)
                body.box(size, loc, straw_dk if (r // 2) % 2 else straw)
    # the rope: two loops round the body, twisted (a diagonal stripe of the darker strand)
    for z in (0.17, H - 0.17):
        body.sweep(rounded_rect_loop(W + 0.06, D + 0.06, z, 0.06), 0.034, lambda i, j: rope_dk if (i + j) % 4 == 0 else rope, 8)
    corner_caps(body, gold)
    # the lock: a gold crest with the green gem
    body.box((0.26, 0.04, 0.26), (0, -D * 0.5 - 0.03, H - 0.16), gold)
    body.ball(0.06, (0, -D * 0.5 - 0.06, H - 0.16), gem, 10, 6, (1.0, 0.6, 1.0))
    # a tumbleweed tuft tied to each side (the King's own weeds)
    rnd = random.Random(118)
    for sx in (-1, 1):
        c = Vector((sx * (W * 0.5 + 0.12), 0.0, H * 0.45))
        for k in range(46):
            a = rnd.uniform(0, 2 * math.pi)
            e = rnd.uniform(-1.2, 1.2)
            d = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
            body.cyl(0.008, 0.26, tuple(c + d * rnd.uniform(0.0, 0.09)), twig,
                     rot=(rnd.uniform(0, math.pi), rnd.uniform(0, math.pi), rnd.uniform(0, math.pi)), segs=4)
    lid = Part("Lid")
    lid_shell(lid, straw, gold)
    # straw ridges along the barrel, and two gold bands over it
    for k in range(9):
        ang = math.pi * (k + 0.5) / 9
        p = barrel_point(0.0, ang, BARREL_R + 0.012)
        lid.box((W - 0.1, 0.05, 0.035), p, straw_dk if k % 2 else straw, rot=(math.pi * 0.5 - ang, 0, 0))
    for x in (-0.38, 0.38):
        barrel(lid, BARREL_R + 0.035, 0.09, x, gold)
    lid.box((0.1, D + 0.12, SLAB + 0.02), (-0.38, 0, H + SLAB * 0.5), gold)
    lid.box((0.1, D + 0.12, SLAB + 0.02), (0.38, 0, H + SLAB * 0.5), gold)
    # the crown on top: a gold band, five points with balls, gems between
    top = H + SLAB + BARREL_R
    lid.cyl(0.2, 0.12, (0, 0, top + 0.05), gold, segs=20)
    for k in range(5):
        a = 2 * math.pi * k / 5 + math.pi * 0.5
        p = (math.cos(a) * 0.18, math.sin(a) * 0.18, top + 0.15)
        lid.cyl(0.055, 0.16, p, gold, segs=4, r2=0.0)
        lid.ball(0.035, (p[0], p[1], top + 0.24), gold, 8, 5)
        a2 = a + math.pi / 5
        lid.ball(0.03, (math.cos(a2) * 0.205, math.sin(a2) * 0.205, top + 0.05), ruby if k % 2 else gem, 8, 5)
    lid.ball(0.07, (0, 0, top + 0.1), gem, 10, 6)
    return body, lid, {"shine": (210, 232, 80)}


# ---------------------------------------------------------------- the Gila Grande's
def gila():
    black = mat("gila_black", (34, 26, 30), 0.6)
    orange = mat("gila_orange", (240, 120, 60), 0.5)
    pink = mat("gila_pink", (236, 150, 120), 0.5)
    bone = mat("gila_bone", (232, 216, 180), 0.7)
    copper = mat("gila_copper", (200, 110, 60), 0.35, 0.8)
    cactus = mat("gila_cactus", (70, 150, 70), 0.8)
    cactus_dk = mat("gila_cactus_dark", (44, 110, 56), 0.8)
    flower = mat("gila_flower", (255, 110, 160), 0.6)
    body = Part("Body")
    body_shell(body, black, bone)

    def blotch(x, y, z):
        # the gila monster's pattern: orange bands and blotches over black, from a few crossed waves
        v = math.sin(x * 9.0 + z * 4.0) + math.sin(y * 8.0 - z * 6.5) * 0.8 + math.sin((x + y) * 5.0 + z * 11.0) * 0.6
        if v > 0.75:
            return pink
        if v > 0.05:
            return orange
        return black

    # beaded scales: hexagonal beads in rows, every face
    step = 0.072
    for ny in (-1, 1):
        for r in range(int((H - 0.12) / (step * 0.86))):
            z = 0.09 + r * step * 0.86
            off = step * 0.5 if r % 2 else 0.0
            x = -W * 0.5 + 0.06 + off
            while x < W * 0.5 - 0.05:
                y = ny * (D * 0.5 + 0.008)
                body.cyl(step * 0.46, 0.03, (x, y, z), blotch(x, y, z), rot=(math.pi * 0.5, 0, 0), segs=6)
                x += step
    for nx in (-1, 1):
        for r in range(int((H - 0.12) / (step * 0.86))):
            z = 0.09 + r * step * 0.86
            off = step * 0.5 if r % 2 else 0.0
            y = -D * 0.5 + 0.06 + off
            while y < D * 0.5 - 0.05:
                x = nx * (W * 0.5 + 0.008)
                body.cyl(step * 0.46, 0.03, (x, y, z), blotch(x, y, z), rot=(0, math.pi * 0.5, 0), segs=6)
                y += step
    # bone bands down the corners and copper studs
    for x in (-1, 1):
        for y in (-1, 1):
            body.box((0.07, 0.07, H), (x * (W * 0.5 + 0.005), y * (D * 0.5 + 0.005), H * 0.5), bone)
    for x in (-0.45, -0.15, 0.15, 0.45):
        body.ball(0.025, (x, -D * 0.5 - 0.035, 0.03), copper, 8, 5)
    # the lock: a copper plate shaped like a gila's head, two bead eyes
    body.box((0.24, 0.04, 0.2), (0, -D * 0.5 - 0.035, H - 0.14), copper)
    body.cyl(0.07, 0.04, (0, -D * 0.5 - 0.035, H - 0.27), copper, rot=(math.pi * 0.5, 0, 0), segs=12)
    for ex in (-0.06, 0.06):
        body.ball(0.025, (ex, -D * 0.5 - 0.06, H - 0.12), black, 8, 5)
    # cactus-arm handles on the sides
    for sx in (-1, 1):
        body.sweep([(sx * (W * 0.5 + 0.0), -0.16, H * 0.55), (sx * (W * 0.5 + 0.13), -0.16, H * 0.55),
                    (sx * (W * 0.5 + 0.16), -0.05, H * 0.62), (sx * (W * 0.5 + 0.16), 0.08, H * 0.62),
                    (sx * (W * 0.5 + 0.13), 0.16, H * 0.55), (sx * (W * 0.5 + 0.0), 0.16, H * 0.55)],
                   0.045, lambda i, j: cactus_dk if j % 2 else cactus, 8, closed=False)
    lid = Part("Lid")
    lid_shell(lid, black, bone)
    # beads over the barrel
    rows = 15
    for r in range(rows):
        ang = math.pi * (r + 0.5) / rows
        off = step * 0.5 if r % 2 else 0.0
        x = -W * 0.5 + 0.06 + off
        while x < W * 0.5 - 0.04:
            p = barrel_point(x, ang, BARREL_R + 0.008)
            lid.cyl(step * 0.46, 0.03, p, blotch(p[0], p[1], p[2]), rot=(math.pi * 0.5 - ang, 0, 0), segs=6)
            x += step
    for x in (-0.38, 0.38):
        barrel(lid, BARREL_R + 0.03, 0.07, x, bone)
    # a saguaro on top, two arms up; barrel cacti with a pink flower at the front corners
    top = H + SLAB + BARREL_R
    lid.cyl(0.075, 0.5, (0, 0, top + 0.22), cactus, segs=10)
    lid.ball(0.075, (0, 0, top + 0.47), cactus, 10, 6)
    for sx in (-1, 1):
        lid.cyl(0.05, 0.14, (sx * 0.12, 0, top + 0.2), cactus_dk, rot=(0, math.pi * 0.5, 0), segs=8)
        lid.cyl(0.05, 0.2, (sx * 0.19, 0, top + 0.29), cactus, segs=8)
        lid.ball(0.05, (sx * 0.19, 0, top + 0.39), cactus, 8, 5)
    for k in range(10):
        a = 2 * math.pi * k / 10
        lid.cyl(0.006, 0.03, (math.cos(a) * 0.08, math.sin(a) * 0.08, top + 0.1 + (k % 3) * 0.12), bone,
                rot=(0, math.pi * 0.5, a), segs=3)
    for sx in (-1, 1):
        c = barrel_point(sx * 0.48, 0.55, BARREL_R + 0.05)
        lid.ball(0.085, c, cactus, 10, 7, (1.0, 1.0, 0.85))
        lid.ball(0.035, (c[0], c[1], c[2] + 0.08), flower, 8, 5)
    return body, lid, {"shine": (255, 140, 50)}


# ---------------------------------------------------------------- the Brander's
def brander():
    # black iron that stays black under the desert's warm light (a high metalness took the sand's colour: brown), and
    # brands that glow red-hot without blooming to yellow in the game
    iron = mat("brand_iron", (46, 44, 50), 0.55, 0.3)
    iron_dk = mat("brand_iron_dark", (26, 24, 28), 0.6, 0.3)
    rivet = mat("brand_rivet", (120, 114, 118), 0.4, 0.5)
    hot = mat("brand_hot", (255, 70, 20), 0.4, 0.0, (255, 60, 10), 1.4)
    glow = mat("brand_glow", (255, 170, 60), 0.4, 0.0, (255, 150, 40), 1.8)
    chain = mat("brand_chain", (70, 68, 76), 0.45, 0.5)
    body = Part("Body")
    body_shell(body, iron, iron_dk)
    # plates: raised panels and rivets round every face's edge
    for ny in (-1, 1):
        for x in (-0.3, 0.3):
            body.box((0.5, 0.025, H - 0.18), (x, ny * (D * 0.5 + 0.01), H * 0.5), iron_dk)
    for nx in (-1, 1):
        body.box((0.025, D - 0.16, H - 0.18), (nx * (W * 0.5 + 0.01), 0, H * 0.5), iron_dk)
    for ny in (-1, 1):
        for k in range(9):
            x = -W * 0.5 + 0.07 + k * (W - 0.14) / 8
            for z in (0.1, H - 0.1):
                body.ball(0.022, (x, ny * (D * 0.5 + 0.03), z), rivet, 8, 5)
    for nx in (-1, 1):
        for k in range(6):
            y = -D * 0.5 + 0.07 + k * (D - 0.14) / 5
            for z in (0.1, H - 0.1):
                body.ball(0.022, (nx * (W * 0.5 + 0.03), y, z), rivet, 8, 5)
    # the brands on the front: a ring with a cross through it and a bar under (the Brander's mark), red-hot
    for cx in (-0.3, 0.3):
        c = Vector((cx, -D * 0.5 - 0.03, H * 0.5))
        body.torus(0.12, 0.018, tuple(c), hot, rot=(math.pi * 0.5, 0, 0), segs=20, sides=6)
        body.box((0.03, 0.02, 0.3), tuple(c), hot)
        body.box((0.3, 0.02, 0.03), tuple(c), hot)
        body.box((0.2, 0.02, 0.03), (cx, -D * 0.5 - 0.03, H * 0.5 - 0.2), hot)
    # a chain round the body's middle, link by link
    loop = rounded_rect_loop(W + 0.08, D + 0.08, H * 0.3, 0.08, 10, 4)
    acc = 0.0
    k = 0
    for i in range(len(loop)):
        a, b = Vector(loop[i]), Vector(loop[(i + 1) % len(loop)])
        seg = (b - a).length
        while acc < seg:
            p = a + (b - a) * (acc / seg)
            yaw = math.atan2((b - a).y, (b - a).x)
            rot = (0, 0, yaw) if k % 2 == 0 else (math.pi * 0.5, 0, yaw)
            body.torus(0.035, 0.012, tuple(p), chain, rot=rot, segs=10, sides=5, scale=(1.6, 1.0, 1.0))
            acc += 0.075
            k += 1
        acc -= seg
    # the padlock hanging off the front, its keyhole glowing
    body.box((0.22, 0.08, 0.2), (0, -D * 0.5 - 0.09, H - 0.24), iron_dk)
    body.torus(0.07, 0.018, (0, -D * 0.5 - 0.09, H - 0.12), rivet, rot=(math.pi * 0.5, 0, 0), segs=12, sides=6)
    body.box((0.035, 0.02, 0.07), (0, -D * 0.5 - 0.135, H - 0.25), glow)
    lid = Part("Lid")
    lid_shell(lid, iron, iron_dk)
    # iron straps over the barrel with rivets, a glowing seam under the lid's edge, a brand on top
    for x in (-0.42, 0.0, 0.42):
        barrel(lid, BARREL_R + 0.03, 0.08, x, iron_dk)
        for k in range(7):
            ang = math.pi * (k + 0.5) / 7
            lid.ball(0.02, barrel_point(x, ang, BARREL_R + 0.05), rivet, 8, 5)
    lid.box((W - 0.06, 0.02, 0.025), (0, -D * 0.5 - 0.03, H + 0.012), glow)
    top = H + SLAB + BARREL_R
    for sx in (-0.21, 0.21):
        c = barrel_point(sx, math.pi * 0.42, BARREL_R + 0.02)
        lid.torus(0.08, 0.015, c, hot, rot=(math.pi * 0.5 - math.pi * 0.42, 0, 0), segs=16, sides=5)
    for k in range(5):
        x = -0.48 + k * 0.24
        lid.cyl(0.04, 0.16, (x, 0, top + 0.06), iron_dk, segs=6, r2=0.0)
    # spikes on the lid's four corners
    for x in (-1, 1):
        for y in (-1, 1):
            lid.cyl(0.055, 0.2, (x * (W * 0.5 - 0.02), y * (D * 0.5 - 0.02), H + SLAB + 0.1), iron_dk, segs=8, r2=0.0)
    return body, lid, {"shine": (255, 70, 30)}


BOSSES = {"tumbleweed_king": king, "gila_grande": gila, "brander": brander}


# ---------------------------------------------------------------- export and renders
def clear():
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    # the meshes too, so the next chest's Body and Lid keep their own names (the game finds the Lid by name)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def treasure():
    """What fills an open chest in the renders (never in the GLB): a heap of gold coins and XP gems in the game's
    purple, blue and pink, and a glow over them."""
    p = Part("Treasure")
    gold = mat("t_gold", (255, 200, 60), 0.3, 0.9, (255, 180, 40), 0.8)
    gems = [mat("t_gem_s", (124, 96, 200), 0.2, 0.0, (124, 96, 230), 0.8), mat("t_gem_m", (90, 170, 200), 0.2, 0.0, (90, 190, 230), 0.8),
            mat("t_gem_l", (200, 110, 170), 0.2, 0.0, (230, 110, 180), 0.8)]
    rnd = random.Random(7)
    for k in range(120):
        x = rnd.uniform(-W * 0.42, W * 0.42)
        y = rnd.uniform(-D * 0.38, D * 0.38)
        hump = 0.16 * (1.0 - (x / (W * 0.5)) ** 2) * (1.0 - (y / (D * 0.5)) ** 2)
        z = H - 0.03 + hump + rnd.uniform(0.0, 0.05)
        if k % 5 == 0:
            g = gems[k % 3]
            p.cyl(0.05, 0.1, (x, y, z + 0.04), g, rot=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 0), segs=4, r2=0.0)
            p.cyl(0.05, 0.06, (x, y, z - 0.03), g, rot=(math.pi, 0, 0), segs=4, r2=0.0)
        else:
            p.cyl(0.05, 0.014, (x, y, z), gold, rot=(rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), 0), segs=14)
    return p.to_object()


def render_poses(name, body, lid, info):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.show_object_outline = True
    sh.object_outline_color = (0.05, 0.03, 0.03)
    sh.show_specular_highlight = True
    scene.render.film_transparent = True
    # the colours as picked (AgX greys every saturated colour, and Klein copies what it sees)
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    # the paintings' view: a little from the left and above, as the walnut chest's painting stands
    target = Vector((0.0, 0.0, 0.62))
    az = math.radians(-28.0)
    el = math.radians(24.0)
    dist = 3.6
    cam.location = target + Vector((math.sin(az) * math.cos(el) * dist, -math.cos(az) * math.cos(el) * dist, math.sin(el) * dist))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    poses = {"closed": 0.0, "cracked": math.radians(-14.0), "open": math.radians(-108.0)}
    tre = None
    lightbox = None
    for pose, rx in poses.items():
        lid.rotation_euler = (rx, 0.0, 0.0)
        if pose != "closed" and lightbox is None:
            # the light inside: a glowing slab just under the lid line (seen through the crack, behind the heap)
            g = mat("inner_glow", (255, 236, 160), 0.5, 0.0, (255, 220, 120), 8.0)
            pl = Part("Glow")
            pl.box((W - 0.08, D - 0.08, 0.02), (0, 0, H - 0.05), g)
            lightbox = pl.to_object()
        if pose == "open" and tre is None:
            tre = treasure()
        scene.render.filepath = os.path.join(REN, "%s_%s.png" % (name, pose))
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)
    lid.rotation_euler = (0.0, 0.0, 0.0)
    for o in (tre, lightbox, cam):
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REN, exist_ok=True)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = []
    renders = True
    for a in args:
        if a.startswith("only="):
            only = [x for x in a[5:].split(",") if x]
        elif a.startswith("renders="):
            renders = a[8:] not in ("0", "false", "no")
    for name, fn in BOSSES.items():
        if only and name not in only:
            continue
        clear()
        MATS.clear()
        b, l, info = fn()
        body = b.to_object()
        lid = l.to_object(HINGE)
        export([body, lid], "boss_chest_" + name)
        if renders:
            render_poses(name, body, lid, info)
    clear()
    print("blender_boss_chests: done")


main()

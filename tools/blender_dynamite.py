"""The dynamite looks of the grenade family (pass 76, Garry: "Change the visuals and the naming of the Grenade to be a
Dynamite Stick ... the vanilla version of the Dynamite stick is sandy brown instead of red, and this Mutation is what
colours it red ... a bundle of several Dynamite Sticks ... Evolution ... the visual of the thing should change quite a
bit"). Three looks, each in its own style:
  b  classic paper stick: a plain sandy-brown (or red) paper stick, dark printed rings near its ends, cream end plugs, a
     pale cord fuse with a charred tip; the bundle three sticks in black tape; Boomtown a gold-trimmed wooden crate
     packed with nine red sticks, one fuse rising from the middle one
  c  chunky cartoon: a fat stick with rounded ends and a cream label in black borders, a thick black curly fuse; the
     bundle four sticks tied with rope and a bow; Boomtown a powder keg in gold hoops with six red sticks strapped
     round its belly
  d  waxed miner's stick: a slim glossy stick with crimped paper ends, a dark printed label, a silver blasting cap with
     a tarred fuse; the bundle seven sticks in copper wire; Boomtown a gilded bundle of seven red sticks under a brass
     cap with a gold band and a gold star
Every model is one mesh coloured by vertex colours ("Col", like tools/blender_grenade.py: a projectile kind is one mesh
in a MultiMesh and the Lobber's material takes COLOR as albedo), built with its long axis along Blender +Y and the fuse
at that end curling up Blender +Z (Godot +Y, up when the shot lies on the sand), then exported turned a quarter so the
long axis runs along Godot +X: a shot flies looking down its -Z and spins about it, so the stick tumbles across its
flight like a thrown stick; it lies along its throw (ProjectileManager._lie_basis). The crate stands up Blender +Z. Origin at the model's middle. The vertex
colours are written sRGB-encoded (encode(): the game reads them so; Blender's renders show the linear palette), and the
papers were picked in the game's light on the sand (tools/dl/p76/DYNART/_colours2_crop.png: a sandy brown that still
reads against the sand, a red that is not orange).

  "$BLENDER" -b --python tools/blender_dynamite.py -- look=b|c|d [only=stick_tan,evo] [refs=1] [review=1]
    -> game/art/props/dynamite_<l>_stick_tan.glb, _stick_red.glb, _bundle_tan.glb, _bundle_red.glb, _evo.glb
       tools/dl/dynamite_<l>_<part>_ref.png   the icon references: a three-quarter render on a transparent film
                                              (768 px; the icon jobs lay it on their screen colour), a small glowing
                                              spark at the fuse tip (render only)
       tools/dl/p76/DYNART/tips_<l>.json      each model's fuse tip in Godot model space and its bounds
       tools/dl/p76/DYNART/review/<l>_<part>_<view>.png   renders on sand to check by eye (ref, game, side)
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
LANE = os.path.join(DL, "p76", "DYNART")
REVIEW = os.path.join(LANE, "review")
PARTS = ("stick_tan", "stick_red", "bundle_tan", "bundle_red", "evo")


def args():
    out = {"look": "b", "only": "", "refs": "1", "review": "1"}
    if "--" in sys.argv:
        for a in sys.argv[sys.argv.index("--") + 1:]:
            if "=" in a:
                k, v = a.split("=", 1)
                out[k] = v
    return out


def lin(h):
    """An sRGB hex colour as the linear RGBA a vertex colour holds (glTF's COLOR_0 is linear; Godot reads it so)."""
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def shade(rgba, f):
    return (rgba[0] * f, rgba[1] * f, rgba[2] * f, 1.0)


# ------------------------------------------------------------------------------------------------ the mesh builder
class Mesh:
    """One bmesh with a per-corner float colour layer; every part adds faces in its own colour."""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")

    def v(self, co):
        return self.bm.verts.new(co)

    def f(self, verts, rgba):
        try:
            face = self.bm.faces.new(verts)
        except ValueError:
            return None
        for lp in face.loops:
            lp[self.col] = rgba
        return face

    def lathe(self, prof, M=Matrix(), n=24, cap0=None, cap1=None, cfn=None, pleat=None):
        """A surface of revolution about the local Y axis. prof: [(t, r, colour), ...] from the -Y end to the +Y end
        (the segment from point i to i+1 takes point i's colour; cfn(i, k) may override it per facet); cap0/cap1 the
        end discs' colours (None: open; a point with r 0 needs none). pleat: {i: (amp, waves)} crimps ring i."""
        rings = []
        for i, (t, r, _c) in enumerate(prof):
            ring = []
            for k in range(n):
                a = 2.0 * math.pi * k / n
                rr = r
                if pleat and i in pleat:
                    amp, waves = pleat[i]
                    rr = r * (1.0 + amp * math.cos(waves * a))
                ring.append(self.v(M @ Vector((rr * math.cos(a), t, rr * math.sin(a)))))
            rings.append(ring)
        for i in range(len(prof) - 1):
            for k in range(n):
                k2 = (k + 1) % n
                c = cfn(i, k) if cfn else prof[i][2]
                if c is None:
                    c = prof[i][2]
                self.f([rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2]], c)
        if cap0 is not None and prof[0][1] > 1e-6:
            c = self.v(M @ Vector((0.0, prof[0][0], 0.0)))
            for k in range(n):
                self.f([c, rings[0][k], rings[0][(k + 1) % n]], cap0)
        if cap1 is not None and prof[-1][1] > 1e-6:
            c = self.v(M @ Vector((0.0, prof[-1][0], 0.0)))
            for k in range(n):
                self.f([c, rings[-1][(k + 1) % n], rings[-1][k]], cap1)

    def tube(self, pts, r, rgba, n=8, tip=None, tip_frac=0.18, cap_end=True, r_end=None):
        """A cord swept along a smooth curve through `pts` (Catmull-Rom), capped at its far end; the last tip_frac of
        its length in `tip` (a charred end). r_end: the radius at the far end (a taper)."""
        path = catmull(pts, 6)
        total = sum((path[i + 1] - path[i]).length for i in range(len(path) - 1))
        tang = []
        for i in range(len(path)):
            a = path[max(i - 1, 0)]
            b = path[min(i + 1, len(path) - 1)]
            tang.append((b - a).normalized())
        # parallel transport of a normal along the path
        t0 = tang[0]
        ref = Vector((0.0, 0.0, 1.0)) if abs(t0.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        nrm = (ref - t0 * ref.dot(t0)).normalized()
        rings = []
        run = 0.0
        for i, p in enumerate(path):
            if i > 0:
                run += (path[i] - path[i - 1]).length
                prev, cur = tang[i - 1], tang[i]
                axis = prev.cross(cur)
                if axis.length > 1e-8:
                    ang = prev.angle(cur)
                    nrm = Matrix.Rotation(ang, 3, axis.normalized()) @ nrm
                nrm = (nrm - cur * nrm.dot(cur)).normalized()
            bnr = tang[i].cross(nrm)
            rr = r if r_end is None else r + (r_end - r) * (run / total)
            ring = [self.v(p + (nrm * math.cos(2 * math.pi * k / n) + bnr * math.sin(2 * math.pi * k / n)) * rr) for k in range(n)]
            rings.append((ring, run / total))
        for i in range(len(rings) - 1):
            ring_a, fa = rings[i]
            ring_b, _fb = rings[i + 1]
            c = tip if (tip is not None and fa >= 1.0 - tip_frac) else rgba
            for k in range(n):
                k2 = (k + 1) % n
                self.f([ring_a[k], ring_a[k2], ring_b[k2], ring_b[k]], c)
        if cap_end:
            ring, _ = rings[-1]
            c = self.v(path[-1] + tang[-1] * (r if r_end is None else r_end) * 0.6)
            for k in range(n):
                self.f([c, ring[k], ring[(k + 1) % n]], tip if tip is not None else rgba)
        return path[-1] + tang[-1] * (r if r_end is None else r_end) * 0.6

    def hull_band(self, circles, t0, t1, thick, rgba, M=Matrix(), samples=64):
        """A band round several parallel round things (circles [(x, z, r)] in the local XZ plane), from t0 to t1 along
        local Y: its outer face on their convex hull grown by `thick`, with thin lips at its edges."""
        pts = []
        for (x, z, r) in circles:
            for k in range(samples):
                a = 2.0 * math.pi * k / samples
                pts.append((x + (r + thick) * math.cos(a), z + (r + thick) * math.sin(a)))
        hull = convex_hull(pts)
        # resample the hull evenly (60 points) so the band's facets are even
        hull = resample(hull, 60)
        cx = sum(p[0] for p in hull) / len(hull)
        cz = sum(p[1] for p in hull) / len(hull)
        inner = []
        for (x, z) in hull:
            d = math.hypot(x - cx, z - cz)
            s = max(d - thick * 1.6, 0.0) / d if d > 1e-6 else 0.0
            inner.append((cx + (x - cx) * s, cz + (z - cz) * s))
        n = len(hull)
        o0 = [self.v(M @ Vector((x, t0, z))) for (x, z) in hull]
        o1 = [self.v(M @ Vector((x, t1, z))) for (x, z) in hull]
        i0 = [self.v(M @ Vector((x, t0, z))) for (x, z) in inner]
        i1 = [self.v(M @ Vector((x, t1, z))) for (x, z) in inner]
        for k in range(n):
            k2 = (k + 1) % n
            self.f([o0[k], o1[k], o1[k2], o0[k2]], rgba)
            self.f([o1[k], i1[k], i1[k2], o1[k2]], rgba)
            self.f([i0[k], o0[k], o0[k2], i0[k2]], rgba)

    def box(self, c, size, rgba, M=Matrix(), cols=None):
        """An axis-aligned box (local) centred at c; cols: per-face colours {'+z': ..} overriding rgba."""
        hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        P = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    P[(sx, sy, sz)] = self.v(M @ Vector((c[0] + sx * hx, c[1] + sy * hy, c[2] + sz * hz)))
        faces = {
            "+x": [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
            "-x": [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)],
            "+y": [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)],
            "-y": [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
            "+z": [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
            "-z": [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)],
        }
        for name, keys in faces.items():
            self.f([P[k] for k in keys], (cols or {}).get(name, rgba))

    def star(self, c, normal, up, r_out, r_in, depth, rgba, points=5):
        """A flat star standing `depth` proud along `normal`, one point towards `up`."""
        nrm = Vector(normal).normalized()
        u = (Vector(up) - nrm * Vector(up).dot(nrm)).normalized()
        w = nrm.cross(u)
        c = Vector(c)
        front, back = [], []
        for k in range(points * 2):
            a = math.pi * k / points
            rr = r_out if k % 2 == 0 else r_in
            p = c + (u * math.cos(a) + w * math.sin(a)) * rr
            front.append(self.v(p + nrm * depth))
            back.append(self.v(p))
        cf = self.v(c + nrm * depth * 1.4)
        m = len(front)
        for k in range(m):
            k2 = (k + 1) % m
            self.f([cf, front[k], front[k2]], rgba)
            self.f([back[k], back[k2], front[k2], front[k]], shade(rgba, 0.8))

    def finish(self, name, rough=0.6, metal=0.0, sharp_deg=38.0):
        # every part is wound outwards as it is made (open bands and cords too, which a normal recalculation may flip)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-6)
        self.bm.normal_update()
        for face in self.bm.faces:
            face.smooth = True
        lim = math.radians(sharp_deg)
        for e in self.bm.edges:
            if len(e.link_faces) == 2:
                e.smooth = e.link_faces[0].normal.angle(e.link_faces[1].normal, 0.0) < lim
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        attr = me.color_attributes.get("Col")
        if attr is not None:
            me.color_attributes.active_color = attr
            try:
                me.color_attributes.render_color_index = list(me.color_attributes).index(attr)
            except (AttributeError, ValueError):
                pass
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        m = bpy.data.materials.new(name + "_mat")
        try:
            m.use_nodes = True
        except AttributeError:
            pass
        nt = m.node_tree
        b = nt.nodes.get("Principled BSDF")
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        me.materials.append(m)
        return o


def catmull(pts, steps):
    P = [Vector(p) for p in pts]
    if len(P) < 3:
        return P
    ext = [P[0] + (P[0] - P[1])] + P + [P[-1] + (P[-1] - P[-2])]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(steps):
            t = s / float(steps)
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-1])
    return out


def convex_hull(points):
    pts = sorted(set((round(x, 6), round(z, 6)) for x, z in points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def resample(poly, n):
    segs = []
    total = 0.0
    m = len(poly)
    for i in range(m):
        a, b = poly[i], poly[(i + 1) % m]
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        segs.append((a, b, d))
        total += d
    out = []
    step = total / n
    acc = 0.0
    si = 0
    pos = 0.0
    for k in range(n):
        target = k * step
        while si < len(segs) - 1 and acc + segs[si][2] < target:
            acc += segs[si][2]
            si += 1
        a, b, d = segs[si]
        f = (target - acc) / d if d > 1e-9 else 0.0
        out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    # the hull from the monotone chain runs counter-clockwise in (x, z), from +x towards +z like a lathe's rings, so the
    # band's quads face out the way the lathe's do
    return out


def at(x, z):
    """The matrix that moves a part to (x, *, z) in the bundle's cross-section."""
    return Matrix.Translation(Vector((x, 0.0, z)))


# ------------------------------------------------------------------------------------------------ the looks
LOOKS = {}

# --- b: the classic paper stick
B = {
    "tan": lin("A47C52"), "red": lin("B32A22"), "end": lin("ECD8AE"), "ring": lin("3A2618"),
    "fuse": lin("D8CFBD"), "char": lin("2C241F"), "tape": lin("2A2624"),
    "wood": lin("C08A50"), "wood_dark": lin("80522C"), "inside": lin("2A1A10"), "gold": lin("F2B632"),
    "R": 0.085, "H": 0.27, "rough": 0.72,
}


def b_stick_prof(paper, R=None, H=None):
    R = R or B["R"]
    H = H or B["H"]
    rim = shade(paper, 0.78)
    ring = B["ring"]
    e = 0.003
    return [(-H, R * 0.86, rim), (-H + 0.009, R, paper), (-H + 0.055, R, ring), (-H + 0.055, R + e, ring),
            (-H + 0.078, R + e, ring), (-H + 0.078, R, paper), (H - 0.078, R, ring), (H - 0.078, R + e, ring),
            (H - 0.055, R + e, ring), (H - 0.055, R, paper), (H - 0.009, R, rim), (H, R * 0.86, rim)]


def b_fuse(m, x, y0, z, flip=1.0):
    pts = [(x, y0 - 0.01, z), (x, y0 + 0.022, z + 0.004), (x + 0.004 * flip, y0 + 0.058, z + 0.03),
           (x - 0.008 * flip, y0 + 0.083, z + 0.07), (x - 0.02 * flip, y0 + 0.088, z + 0.108)]
    return m.tube(pts, 0.016, B["fuse"], n=8, tip=B["char"], tip_frac=0.2)


def b_stick(colour):
    m = Mesh()
    m.lathe(b_stick_prof(B[colour]), n=24, cap0=B["end"], cap1=B["end"])
    tip = b_fuse(m, 0.0, B["H"], 0.0)
    return m.finish("Dynamite", rough=B["rough"]), tip


B_BUNDLE = [(-0.087, -0.05, -0.012), (0.087, -0.05, 0.01), (0.0, 0.1, 0.0)]


def b_bundle(colour):
    m = Mesh()
    R = B["R"]
    for (x, z, dy) in B_BUNDLE:
        m.lathe(b_stick_prof(B[colour]), M=at(x, z) @ Matrix.Translation((0, dy, 0)), n=24, cap0=B["end"], cap1=B["end"])
    circles = [(x, z, R) for (x, z, _dy) in B_BUNDLE]
    for (t0, t1) in ((-0.175, -0.13), (0.13, 0.175)):
        m.hull_band(circles, t0, t1, 0.006, B["tape"])
    tip = b_fuse(m, 0.0, B["H"], 0.1)
    return m.finish("Dynamite", rough=B["rough"]), tip


def b_evo():
    """Boomtown (b): a wooden crate trimmed in gold, packed with nine red sticks standing up, one fuse rising from the
    middle one. The crate stands up +Z (Godot +Y)."""
    m = Mesh()
    W, D, Hh = 0.46, 0.54, 0.32          # x, y, z
    z0, z1 = -0.17, -0.17 + Hh
    wood, dark, gold = B["wood"], B["wood_dark"], B["gold"]
    # the crate: its walls (the top face is the dark inside)
    m.box((0, 0, (z0 + z1) / 2), (W, D, Hh), wood, cols={"+z": B["inside"]})
    # planks: two dark grooves round the walls
    for zz in (z0 + Hh * 0.36, z0 + Hh * 0.68):
        m.box((0, 0, zz), (W + 0.008, D + 0.008, 0.012), dark, cols={"+z": dark, "-z": dark})
    # gold corner posts and the gold rims at the top and the bottom
    p = 0.04
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((sx * (W / 2 - p / 2 + 0.006), sy * (D / 2 - p / 2 + 0.006), (z0 + z1) / 2), (p, p, Hh + 0.012), gold)
    rim = 0.032
    for (zz, h) in ((z1 - rim / 2 + 0.004, rim), (z0 + rim / 2 - 0.004, rim)):
        m.box((0, D / 2 - 0.004, zz), (W + 0.014, 0.022, h), gold)
        m.box((0, -D / 2 + 0.004, zz), (W + 0.014, 0.022, h), gold)
        m.box((W / 2 - 0.004, 0, zz), (0.022, D + 0.014, h), gold)
        m.box((-W / 2 + 0.004, 0, zz), (0.022, D + 0.014, h), gold)
    # a gold plate on each long side
    for sx in (-1, 1):
        m.box((sx * (W / 2 + 0.006), 0, z0 + Hh * 0.52), (0.014, 0.2, 0.09), gold)
    # nine red sticks standing in it, poking out over the rim
    R = 0.064
    tops = [0.11, 0.135, 0.105, 0.125, 0.15, 0.115, 0.1, 0.13, 0.11]
    k = 0
    for ix in (-1, 0, 1):
        for iy in (-1, 0, 1):
            x, y = ix * 0.135, iy * 0.16
            top = z1 + tops[k]
            k += 1
            bot = z0 + 0.04
            L = top - bot
            prof = b_stick_prof(B["red"], R=R, H=L / 2)
            # the stick's local Y turned up to +Z, centred between its ends
            M = Matrix.Translation((x, y, (top + bot) / 2)) @ Matrix.Rotation(math.pi / 2, 4, "X")
            m.lathe(prof, M=M, n=16, cap0=B["end"], cap1=B["end"])
    # the fuse from the middle stick, rising and curling
    t = z1 + tops[4]
    pts = [(0, 0, t - 0.01), (0.0, 0.004, t + 0.03), (0.02, 0.0, t + 0.07), (0.045, -0.02, t + 0.1), (0.05, -0.05, t + 0.13)]
    tip = m.tube(pts, 0.015, B["fuse"], n=8, tip=B["char"], tip_frac=0.2)
    return m.finish("Boomtown", rough=0.5), tip


LOOKS["b"] = {"stick": b_stick, "bundle": b_bundle, "evo": b_evo, "rough": B["rough"], "evo_rough": 0.5}

# --- c: the chunky cartoon stick
C = {
    "tan": lin("B38755"), "red": lin("C22A20"), "label": lin("F4E8CC"), "border": lin("231C18"),
    "end_tan": lin("F0D7A6"), "end_red": lin("F2B49C"),
    "fuse": lin("2B2622"), "char": lin("120E0C"), "rope": lin("CFA35E"), "rope_dark": lin("94703C"),
    "wood": lin("B47A44"), "wood_dark": lin("8A5A30"), "head": lin("7A4A26"), "gold": lin("F2B632"),
    "leather": lin("4A2C18"), "R": 0.105, "H": 0.26, "rough": 0.55,
}


def c_stick_prof(paper, R=None, H=None, rc=0.034, label=True):
    """The cartoon stick: round-shouldered ends, a narrow cream label in thick black borders round its middle (none on
    the keg's small sticks)."""
    R = R or C["R"]
    H = H or C["H"]
    e = 0.0045
    prof = []
    steps = 5
    for k in range(steps + 1):
        ph = (math.pi / 2) * k / steps
        prof.append((-H + rc * (1 - math.cos(ph)), R - rc + rc * math.sin(ph), paper))
    lab, bw = 0.052, 0.014
    if label:
        prof += [(-lab - bw, R, C["border"]), (-lab - bw, R + e, C["border"]), (-lab, R + e, C["label"]),
                 (lab, R + e, C["border"]), (lab + bw, R + e, C["border"]), (lab + bw, R, paper)]
    for k in range(steps, -1, -1):
        ph = (math.pi / 2) * k / steps
        prof.append((H - rc * (1 - math.cos(ph)), R - rc + rc * math.sin(ph), paper))
    return prof


def c_fuse(m, x, y0, z):
    pts = [(x, y0 - 0.012, z), (x, y0 + 0.03, z + 0.008), (x + 0.03, y0 + 0.06, z + 0.045), (x + 0.012, y0 + 0.075, z + 0.1),
           (x - 0.03, y0 + 0.065, z + 0.125), (x - 0.05, y0 + 0.085, z + 0.165)]
    return m.tube(pts, 0.02, C["fuse"], n=10, tip=C["char"], tip_frac=0.12, r_end=0.016)


def c_stick(colour):
    m = Mesh()
    end = shade(C[colour], 0.8)
    m.lathe(c_stick_prof(C[colour]), n=28, cap0=end, cap1=end)
    tip = c_fuse(m, 0.0, C["H"], 0.0)
    return m.finish("Dynamite", rough=C["rough"]), tip


C_BUNDLE = [(-0.106, -0.106, 0.008), (0.106, -0.106, -0.01), (-0.106, 0.106, -0.004), (0.106, 0.106, 0.012)]


def c_bundle(colour):
    m = Mesh()
    R = C["R"]
    end = shade(C[colour], 0.8)
    for (x, z, dy) in C_BUNDLE:
        m.lathe(c_stick_prof(C[colour]), M=at(x, z) @ Matrix.Translation((0, dy, 0)), n=28, cap0=end, cap1=end)
    circles = [(x, z, R) for (x, z, _dy) in C_BUNDLE]
    for (t0, t1) in ((-0.18, -0.14), (0.14, 0.18)):
        m.hull_band(circles, t0, t1, 0.012, C["rope"])
    # a bow on top of the front rope: two loops and two short tails
    top = 0.106 + R + 0.012
    by = 0.16
    for s in (-1, 1):
        loop = [(s * 0.012, by, top), (s * 0.05, by - 0.017, top + 0.03), (s * 0.085, by, top + 0.04), (s * 0.08, by + 0.017, top + 0.015),
                (s * 0.012, by, top)]
        m.tube(loop, 0.009, C["rope"], n=6, cap_end=False)
        tail = [(s * 0.01, by, top), (s * 0.04, by + 0.005, top + 0.005), (s * 0.07, by + 0.02, top - 0.02)]
        m.tube(tail, 0.008, C["rope_dark"], n=6)
    m.lathe([(-0.012, 0.016, C["rope_dark"]), (0.012, 0.016, C["rope_dark"])], M=Matrix.Translation((0, by, top)) @ Matrix.Rotation(math.pi / 2, 4, "X"),
            n=10, cap0=C["rope_dark"], cap1=C["rope_dark"])
    # the fuse out of the gap in the middle of the four sticks
    tip = c_fuse(m, 0.0, C["H"], 0.0)
    m.lathe([(C["H"] - 0.06, 0.03, C["fuse"]), (C["H"] - 0.01, 0.026, C["fuse"])], n=10, cap1=C["fuse"])
    return m.finish("Dynamite", rough=C["rough"]), tip


def c_evo():
    """Boomtown (c): a round powder keg on its side (its axis the shot's long axis) in four gold hoops, its staves two
    browns, six red sticks strapped round its belly with a leather strap, the fuse out of a gold bung in its head."""
    m = Mesh()
    L2 = 0.25

    def rad(t):
        return 0.165 + 0.05 * (1.0 - (t / L2) ** 2)

    wood, dark, gold = C["wood"], C["wood_dark"], C["gold"]
    prof = []
    hoops = [(-0.215, -0.185), (-0.105, -0.08), (0.08, 0.105), (0.185, 0.215)]
    ts = [-L2, -L2 + 0.012]
    for (a, b) in hoops:
        ts += [a, b]
    ts += [L2 - 0.012, L2]
    ts = sorted(ts)
    # the stave runs and the hoops (raised)
    prof.append((-L2 + 0.02, rad(-L2) - 0.022, C["head"]))
    prof.append((-L2, rad(-L2) - 0.016, wood))
    for t in [x for x in ts if -L2 < x < L2]:
        inh = any(a <= t < b for (a, b) in hoops)
        starts = any(abs(t - a) < 1e-9 for (a, b) in hoops)
        ends = any(abs(t - b) < 1e-9 for (a, b) in hoops)
        r = rad(t)
        if starts:
            prof.append((t, r, gold))
            prof.append((t, r + 0.009, gold))
        elif ends:
            prof.append((t, r + 0.009, gold))
            prof.append((t, r, wood))
        else:
            prof.append((t, r, wood))
        # bulge samples between
    prof.append((L2, rad(L2) - 0.016, C["head"]))
    prof.append((L2 - 0.02, rad(L2) - 0.022, C["head"]))
    # finer bulge: insert mid samples in the long stave runs
    fine = [prof[0]]
    for i in range(1, len(prof)):
        a, b = prof[i - 1], prof[i]
        if a[2] == wood and b[2] in (wood, gold) and abs(a[1] - rad(a[0])) < 1e-6 and (b[0] - a[0]) > 0.04:
            steps = int((b[0] - a[0]) / 0.025)
            for s in range(1, steps):
                t = a[0] + (b[0] - a[0]) * s / steps
                fine.append((t, rad(t), wood))
        fine.append(b)

    def staves(i, k):
        if fine[i][2] == wood:
            return wood if k % 2 == 0 else dark
        return None

    m.lathe(fine, n=18, cap0=C["head"], cap1=C["head"], cfn=staves)
    # four red sticks strapped round its belly (plain: no labels, so the keg still reads first)
    R = 0.056
    ang = [2 * math.pi * (k + 0.5) / 4 for k in range(4)]
    rr = rad(0.0) + R - 0.006
    for a in ang:
        x, z = rr * math.cos(a), rr * math.sin(a)
        m.lathe(c_stick_prof(C["red"], R=R, H=0.175, rc=0.022, label=False), M=at(x, z), n=16, cap0=C["end_red"], cap1=C["end_red"])
    circles = [(rr * math.cos(a), rr * math.sin(a), R) for a in ang]
    circles.append((0.0, 0.0, rad(0.0)))
    m.hull_band(circles, -0.022, 0.022, 0.008, C["leather"])
    # the gold bung on the head and the fuse out of it
    m.lathe([(L2 - 0.03, 0.04, gold), (L2 + 0.006, 0.04, gold), (L2 + 0.006, 0.028, gold)], n=14, cap1=gold)
    pts = [(0, L2 - 0.01, 0), (0, L2 + 0.04, 0.01), (0.03, L2 + 0.07, 0.05), (0.012, L2 + 0.085, 0.105), (-0.03, L2 + 0.075, 0.13),
           (-0.05, L2 + 0.095, 0.17)]
    tip = m.tube(pts, 0.02, C["fuse"], n=10, tip=C["char"], tip_frac=0.12, r_end=0.016)
    return m.finish("Boomtown", rough=0.45), tip


LOOKS["c"] = {"stick": c_stick, "bundle": c_bundle, "evo": c_evo, "rough": C["rough"], "evo_rough": 0.45}

# --- d: the waxed miner's stick
D = {
    "tan": lin("A9825A"), "red": lin("B02A22"), "label_tan": lin("3E2616"), "label_red": lin("1E1A18"),
    "stripe": lin("EAD8B0"), "cap": lin("C9CDD3"), "cap_dark": lin("8A8F96"), "fuse": lin("211C18"),
    "char": lin("0E0B09"), "copper": lin("C0703A"), "gold": lin("F2B632"), "brass": lin("D9A441"),
    "R": 0.082, "H": 0.235, "rough": 0.32,
}


def d_stick_prof(paper, label, R=None, H=None):
    R = R or D["R"]
    H = H or D["H"]
    e = 0.0025
    crimp = [(-H - 0.045, 0.02, paper), (-H - 0.03, 0.04, paper), (-H, R, paper)]
    prof = crimp + [(-0.12, R, label), (-0.12, R + e, label), (-0.1, R + e, D["stripe"]), (-0.088, R + e, label),
                    (0.088, R + e, D["stripe"]), (0.1, R + e, label), (0.12, R + e, label), (0.12, R, paper),
                    (H, R, paper), (H + 0.03, 0.04, paper), (H + 0.045, 0.02, paper)]
    return prof


D_PLEAT = None


def d_pleats(prof):
    n = len(prof)
    return {0: (0.18, 7), 1: (0.16, 7), n - 2: (0.16, 7), n - 1: (0.18, 7)}


def d_cap_fuse(m, x, z, H=None):
    H = H or D["H"]
    y0 = H + 0.03
    m.lathe([(y0, 0.021, D["cap"]), (y0 + 0.05, 0.021, D["cap_dark"]), (y0 + 0.056, 0.021, D["cap_dark"]), (y0 + 0.07, 0.017, D["cap"])],
            M=at(x, z), n=12, cap1=D["cap"])
    yy = y0 + 0.07
    pts = [(x, yy - 0.006, z), (x, yy + 0.03, z + 0.006), (x + 0.004, yy + 0.06, z + 0.035), (x - 0.008, yy + 0.075, z + 0.075),
           (x - 0.02, yy + 0.078, z + 0.105)]
    return m.tube(pts, 0.011, D["fuse"], n=8, tip=D["char"], tip_frac=0.15)


def d_stick(colour):
    m = Mesh()
    prof = d_stick_prof(D[colour], D["label_" + colour])
    m.lathe(prof, n=28, cap0=D[colour], cap1=D[colour], pleat=d_pleats(prof))
    tip = d_cap_fuse(m, 0.0, 0.0)
    return m.finish("Dynamite", rough=D["rough"]), tip


def hex_layout(R, gap=0.002):
    pts = [(0.0, 0.0)]
    for k in range(6):
        a = 2 * math.pi * k / 6 + math.pi / 6
        pts.append(((2 * R + gap) * math.cos(a), (2 * R + gap) * math.sin(a)))
    return pts


D_STAGGER = [0.0, 0.012, -0.01, 0.006, -0.014, 0.01, -0.004]


def d_bundle(colour):
    m = Mesh()
    R = D["R"]
    lay = hex_layout(R)
    for k, (x, z) in enumerate(lay):
        prof = d_stick_prof(D[colour], D["label_" + colour])
        dy = D_STAGGER[k] if k else 0.0
        m.lathe(prof, M=at(x, z) @ Matrix.Translation((0, dy, 0)), n=24, cap0=D[colour], cap1=D[colour], pleat=d_pleats(prof))
    circles = [(x, z, R) for (x, z) in lay]
    for (t0, t1) in ((-0.185, -0.16), (0.16, 0.185)):
        m.hull_band(circles, t0, t1, 0.005, D["copper"])
    tip = d_cap_fuse(m, 0.0, 0.0)
    return m.finish("Dynamite", rough=D["rough"]), tip


def d_evo():
    """Boomtown (d): seven red sticks gilded: their tops under one brass cap with a brass nipple, a broad gold band round
    their middle with a gold star on it, a gold band near their crimped red feet; the fuse out of the nipple."""
    m = Mesh()
    R = 0.078
    lay = hex_layout(R, 0.003)
    for k, (x, z) in enumerate(lay):
        prof = d_stick_prof(D["red"], D["label_red"], R=R, H=0.25)
        m.lathe(prof, M=at(x, z) @ Matrix.Translation((0, -0.02 + (D_STAGGER[k] if k else 0.0) * 0.5, 0)), n=20,
                cap0=D["red"], cap1=D["red"], pleat=d_pleats(prof))
    circles = [(x, z, R) for (x, z) in lay]
    rb = 3 * R + 0.006
    # the brass cap over the tops: a short cup with a rolled rim and a domed top
    brass, gold = D["brass"], D["gold"]
    cap = [(0.12, rb - 0.012, brass), (0.12, rb + 0.012, brass), (0.12, rb + 0.024, brass), (0.145, rb + 0.024, brass),
           (0.145, rb + 0.012, brass)]
    for k in range(7):
        ph = (math.pi / 2) * k / 6
        cap.append((0.235 + 0.06 * math.sin(ph), (rb + 0.012) * math.cos(ph) + 0.03 * math.sin(ph), brass))
    m.lathe(cap, n=36, cap1=brass)
    m.lathe([(0.285, 0.034, gold), (0.33, 0.034, gold), (0.33, 0.04, gold), (0.342, 0.04, gold), (0.342, 0.022, gold)], n=14, cap1=gold)
    # the gold bands
    m.hull_band(circles, -0.07, 0.05, 0.01, gold)
    m.hull_band(circles, -0.215, -0.19, 0.008, gold)
    # a gold star on the band, facing up (+Z)
    m.star((0.0, -0.01, rb + 0.008), (0, 0, 1), (0, 1, 0), 0.07, 0.03, 0.016, lin("FFD866"))
    pts = [(0, 0.336, 0), (0, 0.37, 0.008), (0.006, 0.4, 0.04), (-0.01, 0.415, 0.085), (-0.025, 0.418, 0.12)]
    tip = m.tube(pts, 0.012, D["fuse"], n=8, tip=D["char"], tip_frac=0.15)
    return m.finish("Boomtown", rough=0.3, metal=0.0), tip


LOOKS["d"] = {"stick": d_stick, "bundle": d_bundle, "evo": d_evo, "rough": D["rough"], "evo_rough": 0.3}


# ------------------------------------------------------------------------------------------------ export, tips, renders
def godot(v):
    """Blender -> Godot model space (the y-up export: x stays, z becomes y, y becomes -z)."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def _to_srgb(c):
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1.0 / 2.4)) - 0.055


def _to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def encode(o, srgb):
    """The vertex colours sRGB-encoded (srgb=True) or linear again. The game reads a GLB's vertex colours as sRGB values
    (pass 76, filmed: a stick exported in linear colours came out twice as dark and orange; the grenade and the
    basketball were written that way before), while Blender shows the attribute as linear: so the palette stays linear
    for the renders and is encoded for the export only."""
    attr = o.data.color_attributes.get("Col")
    if attr is None:
        return
    f = _to_srgb if srgb else _to_linear
    for d in attr.data:
        c = d.color
        d.color = (f(c[0]), f(c[1]), f(c[2]), c[3])


def export(o, path):
    for x in bpy.context.scene.objects:
        x.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    encode(o, True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    encode(o, False)
    print("exported", path)


def bounds(o):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for v in o.data.vertices:
        for i in range(3):
            lo[i] = min(lo[i], v.co[i])
            hi[i] = max(hi[i], v.co[i])
    return lo, hi


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_render(res, transparent, bg=None):
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.film_transparent = transparent
    scene.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    try:
        w.use_nodes = True
    except AttributeError:
        pass
    bgn = w.node_tree.nodes.get("Background") if w.node_tree else None
    if bgn is not None:
        bgn.inputs["Color"].default_value = (0.5, 0.52, 0.56, 1.0)
        bgn.inputs["Strength"].default_value = 0.9
    else:
        w.color = (0.5, 0.52, 0.56)
    scene.world = w
    for name, energy, rot in (("key", 3.2, (0.8, -0.3, -0.6)), ("fill", 1.0, (1.2, 0.4, 2.3)), ("rim", 1.4, (-0.9, 0.0, 3.0))):
        L = bpy.data.lights.new(name, "SUN")
        L.energy = energy
        lo = bpy.data.objects.new(name, L)
        scene.collection.objects.link(lo)
        lo.rotation_euler = rot
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"


def spark_at(p, scale=1.0):
    """A small glowing spark (render only): a hot white core in a yellow-orange star of rays."""
    m = bpy.data.materials.new("spark")
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (1.0, 0.85, 0.3, 1.0)
    b.inputs["Emission Color"].default_value = (1.0, 0.75, 0.2, 1.0)
    b.inputs["Emission Strength"].default_value = 6.0
    objs = []
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.022 * scale, location=p)
    objs.append(bpy.context.active_object)
    for k in range(6):
        a = math.pi * k / 6
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.006 * scale, radius2=0.0, depth=0.09 * scale, location=p)
        c = bpy.context.active_object
        c.rotation_euler = (a, a * 0.7, 0.3 * k)
        objs.append(c)
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.006 * scale, radius2=0.0, depth=0.09 * scale, location=p)
        c = bpy.context.active_object
        c.rotation_euler = (a + math.pi, a * 0.7, 0.3 * k)
        objs.append(c)
    for o in objs:
        o.data.materials.append(m)
    return objs


def frame_matrix(a_deg=36.0, b_deg=38.0):
    """The three-quarter pose of the icon reference: the model's +Y (its fuse end) to the upper right at a_deg, its +Z
    (the fuse's curl, a crate's top) partly towards the camera and partly up-left (b_deg)."""
    a, b = math.radians(a_deg), math.radians(b_deg)
    vy = Vector((math.cos(a), 0.0, math.sin(a)))
    toward = Vector((0.0, -1.0, 0.0))
    perp = Vector((-math.sin(a), 0.0, math.cos(a)))
    vz = (toward * math.cos(b) + perp * math.sin(b)).normalized()
    vx = vy.cross(vz).normalized()
    M = Matrix((vx, vy, vz)).transposed()
    return M.to_4x4()


def render_view(o, tip, path, view, res, transparent, with_spark=True, sand=False):
    scene = bpy.context.scene
    piv = bpy.data.objects.new("pivot", None)
    scene.collection.objects.link(piv)
    o.parent = piv
    extras = spark_at(Vector(tip), 1.0) if with_spark else []
    for e in extras:
        e.parent = piv
    if view == "ref":
        piv.matrix_world = frame_matrix()
    elif view == "ref_up":
        # a crate stands up: a gentler turn, its top towards the viewer and up
        piv.matrix_world = Matrix.Rotation(math.radians(26), 4, "X") @ Matrix.Rotation(math.radians(-32), 4, "Z")
    elif view == "side":
        piv.matrix_world = Matrix.Rotation(math.radians(-90), 4, "Z")
    elif view == "game":
        piv.matrix_world = Matrix.Rotation(math.radians(-30), 4, "Z")
    bpy.context.view_layer.update()
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    if view == "game":
        pitch = math.radians(48.0)
        dirv = Vector((0.0, math.cos(pitch), -math.sin(pitch)))
    else:
        dirv = Vector((0.0, 1.0, 0.0))
    # fit: project every vertex (and the spark) onto the camera plane
    up = Vector((0.0, 0.0, 1.0))
    right = dirv.cross(up).normalized()
    upv = right.cross(dirv).normalized()
    pts = [piv.matrix_world @ (o.matrix_local @ v.co) for v in o.data.vertices]
    pts.append(piv.matrix_world @ Vector(tip))
    xs = [p.dot(right) for p in pts]
    ys = [p.dot(upv) for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    cam_d.ortho_scale = span * (1.22 if view.startswith("ref") else 1.35)
    centre = right * cx + upv * cy
    cam.location = centre - dirv * 5.0
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = dirv.to_track_quat("-Z", "Y")
    plane = None
    if sand:
        bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0, 0, min(p.z for p in pts) - 0.002))
        plane = bpy.context.active_object
        sm = bpy.data.materials.new("sand")
        try:
            sm.use_nodes = True
        except AttributeError:
            pass
        sb = sm.node_tree.nodes.get("Principled BSDF")
        sb.inputs["Base Color"].default_value = lin("F0C988")
        sb.inputs["Roughness"].default_value = 0.95
        plane.data.materials.append(sm)
    scene.render.filepath = path
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.film_transparent = transparent
    bpy.ops.render.render(write_still=True)
    print("rendered", path)
    # undo the view
    for e in extras:
        bpy.data.objects.remove(e, do_unlink=True)
    if plane:
        bpy.data.objects.remove(plane, do_unlink=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = Matrix()
    bpy.data.objects.remove(piv, do_unlink=True)


def main():
    a = args()
    look = a["look"].lower()
    if look not in LOOKS:
        raise SystemExit("blender_dynamite: look must be one of %s" % ", ".join(sorted(LOOKS)))
    only = [x for x in a["only"].split(",") if x] or list(PARTS)
    L = LOOKS[look]
    os.makedirs(PROPS, exist_ok=True)
    os.makedirs(REVIEW, exist_ok=True)
    tips_path = os.path.join(LANE, "tips_%s.json" % look)
    try:
        tips = json.load(open(tips_path, encoding="utf-8"))
    except (OSError, ValueError):
        tips = {}
    for part in only:
        clear_scene()
        if part == "evo":
            o, tip = L["evo"]()
        else:
            form, colour = part.split("_")
            o, tip = L[form](colour)
        glb = os.path.join(PROPS, "dynamite_%s_%s.glb" % (look, part))
        # exported with the long axis across (Blender +Y turned onto +X, Godot +X): a shot spins about the way it flies,
        # so a stick across its flight tumbles like a thrown stick (along it, it flew like a dart); it lies along its
        # throw either way (ProjectileManager._lie_basis lays the long axis along the throw). The renders keep +Y.
        turn = Matrix.Rotation(-math.pi / 2, 4, "Z")
        o.data.transform(turn)
        tip_x = turn @ Vector(tip)
        export(o, glb)
        lo, hi = bounds(o)
        g_lo, g_hi = godot(lo), godot(hi)
        tips[part] = {"tip": godot(tip_x), "aabb_min": [min(g_lo[i], g_hi[i]) for i in range(3)],
                      "aabb_max": [max(g_lo[i], g_hi[i]) for i in range(3)], "glb": "res://art/props/dynamite_%s_%s.glb" % (look, part),
                      "tris": sum(len(p.vertices) - 2 for p in o.data.polygons)}
        o.data.transform(turn.inverted())
        print("tip", part, tips[part])
        if a["refs"] == "1" or a["review"] == "1":
            setup_render(768, True)
        if a["refs"] == "1":
            view = "ref_up" if (part == "evo" and look == "b") else "ref"
            render_view(o, tip, os.path.join(DL, "dynamite_%s_%s_ref.png" % (look, part)), view, 768, True)
        if a["review"] == "1":
            for view in ("game", "side"):
                render_view(o, tip, os.path.join(REVIEW, "%s_%s_%s.png" % (look, part, view)), view, 512, False, True, True)
    with open(tips_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(tips, f, indent=1)
    print("blender_dynamite: done", look, tips_path)


main()

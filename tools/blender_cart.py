"""Pass 127 (lane ART; Garry: "The toppled over cart doesn't look like any cart I've ever seen and it looks like it's supported
by lying cloth. Looks weird. Fix it."): the toppled cart as a model, so the painter is told what a cart is. A plain western
wooden wagon: a plank box with plank sides and iron straps, two axles, a reach pole and a tongue under it, tipped over on its
long side a little past level, so its underside faces the game's high camera; on the side that is up one whole spoked wheel and
one broken one, both up in the air (with one wheel alone it read as a crate on a wheel), the other two gone (MapDressing's 3D wheels
lie near it), one side board hanging. No cloth, no canvas, no bonnet.

It is no game asset: it renders the reference tools/gen_prop_variants.py paints `cart_toppled` from (the game's camera, high
3/4, orthographic, on the blue screen):

  "$BLENDER" -b --python tools/blender_cart.py [-- out=tools/dl/cart_ref.png pitch=46 yaw=-16 tip=-100 size=1024 wheel2=1 up=-1]
      -> <out> (flat studio colours), <out minus .png>_clay.png (grey, the shapes only)
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_lowpoly as lp  # noqa: E402
import blender_wheel as bw  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

WOOD = (0.78, 0.52, 0.30)
WOOD_D = (0.62, 0.39, 0.22)
WOOD_L = (0.88, 0.63, 0.38)
INSIDE = (0.36, 0.23, 0.13)
BEAM = (0.56, 0.35, 0.19)
IRON = (0.24, 0.23, 0.23)

# the wagon before it tips, metres: x along the box (the tongue at -x), y across it, z up, the floor's top at z 0
L, W, H = 2.7, 1.05, 0.5
AXLE_X = 0.9
AXLE_Z = -0.2
AXLE_OUT = 0.3
SKEIN = 0.09
# the side that ends up on top: -1 (tipped with the underside to the camera) or 1 (tipped with the open box to it)
UP = -1
# a second, broken wheel still on the front axle (wheel2=0: the back wheel alone)
WHEEL2 = True


def arg(name, default):
    for a in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default


def planks_floor(m):
    n = 7
    pw = W / n
    for k in range(n):
        y = -W / 2.0 + (k + 0.5) * pw
        col = (WOOD, WOOD_D, WOOD_L)[k % 3]
        m.box((0, y, -0.03), (L, pw - 0.018, 0.06), col)


def side(m, sy):
    """Three boards along one side, four stakes and two iron straps outside them. `sy` == UP is the side that ends up on top."""
    n = 3
    bh = H / n
    for k in range(n):
        z = (k + 0.5) * bh + 0.01
        col = (WOOD_L, WOOD, WOOD_D)[k % 3]
        if sy == UP and k == 2:
            # the top side's upper board has come off its back stakes and hangs (a short one and a tipped one)
            m.box((-0.72, sy * W / 2.0, z), (L * 0.42, 0.045, bh - 0.02), col)
            m.box((0.45, sy * (W / 2.0 + 0.05), z - 0.05), (L * 0.46, 0.045, bh - 0.02), col, rot=(0.0, 13.0, 0.0))
        else:
            m.box((0, sy * W / 2.0, z), (L, 0.045, bh - 0.02), col)
    for x in (-L / 2.0 + 0.1, -0.42, 0.42, L / 2.0 - 0.1):
        m.box((x, sy * (W / 2.0 + 0.038), H * 0.46), (0.085, 0.04, H * 1.02), BEAM)
    for x in (-0.42, 0.42):
        m.box((x, sy * (W / 2.0 + 0.064), H * 0.46), (0.11, 0.012, H * 1.0), IRON)
    # the corner irons
    for x in (-L / 2.0 + 0.02, L / 2.0 - 0.02):
        m.box((x, sy * (W / 2.0 + 0.03), H * 0.5), (0.05, 0.05, H), IRON)


def ends(m):
    """The headboard, whole; the tailgate gone but for its lowest board: from the camera's side the box shows hollow, its dark inside."""
    n = 3
    bh = H / n
    for k in range(n):
        z = (k + 0.5) * bh + 0.01
        m.box((-L / 2.0, 0, z), (0.05, W, bh - 0.02), (WOOD, WOOD_L, WOOD_D)[k % 3])
    m.box((L / 2.0, 0, bh * 0.5 + 0.01), (0.05, W, bh - 0.02), WOOD_L)
    # the inside's darker skin: inner faces of the far walls
    m.box((-L / 2.0 + 0.035, 0, H / 2.0), (0.012, W - 0.1, H - 0.05), INSIDE)
    m.box((0, W / 2.0 - 0.03, H / 2.0), (L - 0.1, 0.012, H - 0.05), INSIDE)
    m.box((0, -W / 2.0 + 0.03, H / 2.0), (L - 0.1, 0.012, H - 0.05), INSIDE)
    m.box((0, 0, 0.012), (L - 0.1, W - 0.1, 0.012), INSIDE)


def under(m):
    """Two bolsters, two axles with iron ends, the reach pole and the hounds, the tongue. The top side's axle ends stick out; the
    bottom side's are broken short where the box lies on them."""
    for x in (-AXLE_X, AXLE_X):
        m.box((x, 0, -0.09), (0.11, W * 0.92, 0.07), BEAM)
    # the axle runs from the broken stub at +y to its end at -y
    y0, y1 = -UP * (W / 2.0 - 0.02), UP * (W / 2.0 + AXLE_OUT)
    for x in (-AXLE_X, AXLE_X):
        m.box((x, (y0 + y1) * 0.5, AXLE_Z), (0.12, abs(y0 - y1), 0.13), BEAM)
        m.box((x, y1 + UP * SKEIN * 0.5, AXLE_Z), (0.085, SKEIN, 0.085), IRON)
        m.box((x, y1 * 0.5 + y0 * 0.5 - 0.3, AXLE_Z - 0.066), (0.14, 0.03, 0.012), IRON)
        m.box((x, y1 * 0.5 + y0 * 0.5 + 0.3, AXLE_Z - 0.066), (0.14, 0.03, 0.012), IRON)
    m.box((0, 0, -0.165), (AXLE_X * 2.0 + 0.3, 0.1, 0.075), WOOD_D)
    # the hounds: a V from the front axle back to the reach
    for s in (-1, 1):
        a = Vector((-AXLE_X, s * 0.33, AXLE_Z + 0.05))
        b = Vector((-AXLE_X + 0.62, s * 0.03, -0.165))
        c = (a + b) * 0.5
        d = b - a
        m.box(tuple(c), (d.length, 0.07, 0.06), WOOD, rot=(0.0, 0.0, math.degrees(math.atan2(d.y, d.x))))
    # the tongue: out of the front axle along -x, drooped a little in the wagon's frame, snapped off short
    m.tube([(-AXLE_X + 0.05, 0.0, AXLE_Z + 0.0), (-L / 2.0 - 0.1, 0.0, AXLE_Z - 0.03), (-L / 2.0 - 0.72, 0.0, AXLE_Z - 0.08)],
           [0.062, 0.058, 0.05], WOOD_L, 6)
    m.box((-L / 2.0 - 0.25, 0, AXLE_Z - 0.04), (0.06, 0.1, 0.11), IRON)
    # the crossbar the team was hitched to, at its end
    m.box((-L / 2.0 - 0.66, 0, AXLE_Z - 0.08), (0.07, 0.72, 0.07), BEAM)


def wheel(m, centre, broken=False):
    """A spoked wheel (the kit's wheel A: an iron tyre, the felloe, ten spokes, the hub; `broken` its wheel B, a gap in the rim) laid on
    `m` with its axle along y."""
    w = lp.Model("wheel_tmp", 41)
    gap = (3, 4, 5, 6) if broken else ()
    tyre = (2, 3, 4, 5, 6, 7) if broken else ()
    bw.felloe(w, bw.RADIUS - 0.1, bw.RADIUS - 0.02, 0.042, (0.62, 0.42, 0.25), skip=gap)
    bw.felloe(w, bw.RADIUS - 0.02, bw.RADIUS, 0.046, IRON, skip=tyre)
    bw.spokes(w, 10, 0.09, bw.RADIUS - 0.09, skip=(2,) if broken else (), short=(1, 3) if broken else ())
    bw.hub(w)
    xf = Matrix.Translation(centre) @ Matrix.Rotation(math.radians(90.0), 4, "X")
    base = len(m.verts)
    for v in w.verts:
        m.verts.append(xf @ Vector(v))
    for f, c in zip(w.faces, w.cols):
        m.faces.append([base + i for i in f])
        m.cols.append(c)


def build():
    m = lp.Model("Cart", 77, jitter=0.1)
    planks_floor(m)
    side(m, -1)
    side(m, 1)
    ends(m)
    under(m)
    # one wheel still on: the back axle's end on the side that is up
    wheel(m, (AXLE_X, UP * (W / 2.0 + AXLE_OUT + SKEIN * 0.4), AXLE_Z))
    if WHEEL2:
        wheel(m, (-AXLE_X, UP * (W / 2.0 + AXLE_OUT + SKEIN * 0.4), AXLE_Z), True)
    return m.build()


def place(ob, tip, yaw):
    """On its long side: `tip` degrees about the box's length (-90 = the underside straight at the camera, more = turned up to it),
    `yaw` round the vertical, so one end (the open one) comes towards us; then its lowest point on z 0."""
    ob.matrix_world = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(tip), 4, "X")
    bpy.context.view_layer.update()
    me = ob.data
    zmin = min((ob.matrix_world @ v.co).z for v in me.vertices)
    ob.matrix_world = Matrix.Translation((0, 0, -zmin)) @ ob.matrix_world
    bpy.context.view_layer.update()


def render(ob, out, pitch, size, screen):
    scene = bpy.context.scene
    data = bpy.data.cameras.new("cam")
    data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", data)
    scene.collection.objects.link(cam)
    d = Vector((0.0, math.cos(math.radians(pitch)), -math.sin(math.radians(pitch))))
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    # the frame from the model as this camera sees it
    right = Vector((1, 0, 0))
    up = right.cross(d).normalized()
    xs = [p.dot(right) for p in pts]
    ys = [p.dot(up) for p in pts]
    cx, cy = (min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5
    data.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.12
    cam.location = right * cx + up * cy - d * 20.0
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = d.to_track_quat("-Z", "Y")
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.background_type = "WORLD"
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    # no cast shadows: the painter keeps them as blotches on the wood
    sh.show_shadows = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.color = screen
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sh.color_type = "VERTEX"
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    sh.color_type = "SINGLE"
    sh.single_color = (0.7, 0.7, 0.7)
    clay = out[:-4] + "_clay.png"
    scene.render.filepath = clay
    bpy.ops.render.render(write_still=True)
    print("rendered", out, clay)


def main():
    out = arg("out", "tools/dl/cart_ref.png")
    if not os.path.isabs(out):
        out = os.path.join(REPO, out)
    pitch = float(arg("pitch", 46.0))
    yaw = float(arg("yaw", -16.0))
    tip = float(arg("tip", -100.0))
    size = int(arg("size", 1024))
    global UP, WHEEL2
    UP = int(arg("up", UP))
    WHEEL2 = arg("wheel2", "1") == "1"
    lp.fresh()
    ob = build()
    place(ob, tip, yaw)
    # the screen's blue as gen_art's BG_BLUE asks for it
    render(ob, out, pitch, size, (0.0, 0.0, 1.0))


if __name__ == "__main__":
    main()

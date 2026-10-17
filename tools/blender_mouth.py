"""The Big Mouth as a 3D model (pass 34): glossy lips with a cupid's bow, two rows of teeth and a dark mouth, the lower
lip and lower teeth on a `Jaw` node hinged behind the corners so the laser can open it.

    "$BLENDER" -b --python tools/blender_mouth.py -- out=D:/_projects/88fits/game/art/props [lips=0.86,0.05,0.12] [name=big_mouth] [game_views=1]

Writes <out>/<name>.glb (nodes: Mouth > Upper, Jaw (LowerLip, LowerTooth_*, Floor, FloorBack), Cavity, ThroatBack,
Glow, Flare) and previews shut and open in tools/dl/mouth/. The mouth faces Blender's +Y, which the glTF exporter turns
into -Z: a Godot node's forward, so look_at points the lips at a target. About a metre wide. The two in the game:
big_mouth (the default lips) and loud_mouth (lips=0.95,0.62,0.08 name=loud_mouth).

Pass 87 (Garry: "Remove the tongue from the Big Mouth 3d Object. But keep a kind of a bright shining thing in the back
of the Mouth when it's shooting the Laser"): no tongue; the inside is a dark throat: a hollow bowl open to the front
(its inner skin `Cavity`, its outer skin `ThroatBack` in the lips' colour, darker, each drawn from its own side only)
and a dark floor on the jaw (`Floor` its inside, `FloorBack` its outside), so the wide-open mouth shows a dark hollow
and never the sand; `Glow` is a small emissive core deep in the bowl
and `Flare` an empty in the opening's middle, both for LaserBeam.gd (it hides the core at rest and lights it, with a
camera-facing flare at `Flare` and the inner skin and floor glowing, through the wind-up and while the beam pours).
game_views=1 also renders the game's angle (tipped back 32 degrees, a camera 48 degrees up) from four sides, shut,
gaping (the wind-up) and wide open with the core lit, to tools/dl/mouth/<name>_game_<state>_<side>.png.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector


def _args():
    out = {}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        if "=" in a:
            k, v = a.split("=", 1)
            out[k] = v
    return out


A = _args()
OUT = A.get("out", "D:/_projects/88fits/game/art/props")
NAME = A.get("name", "big_mouth")
LIPS = tuple(float(v) for v in A.get("lips", "0.62,0.01,0.05").split(","))
TEETH = tuple(float(v) for v in A.get("teeth", "0.96,0.95,0.9").split(","))
W = 0.5          # half the mouth's width
CURVE = 0.22     # how far the corners fall back round the face

bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, rgb, rough, metal=0.0, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        b.inputs["Emission Strength"].default_value = 0.6
    return m


M_LIP = mat("lips", LIPS, 0.22, 0.0)
M_TOOTH = mat("teeth", TEETH, 0.3)
# the throat's inside (the bowl's inner skin and the floor) and its outside (the bowl's outer skin), each drawn from its
# own side only, so the glow LaserBeam lights on the inside never shows on the back of the mouth
M_CAVE = mat("cavity", (0.12, 0.008, 0.025), 0.9)
M_CAVE.use_backface_culling = True
# the back of the throat seen from outside wears the lips' colour, darker (a dark crimson egg read as a hole behind the
# gold Loudmouth's lips from the high camera)
M_BACK = mat("throat_back", tuple(c * 0.55 for c in LIPS), 0.45)
M_BACK.use_backface_culling = True
# the core deep in the throat (LaserBeam swaps its material for its own and keeps it hidden at rest)
M_GLOW = mat("glow", (1.0, 0.55, 0.85), 0.5, emit=(1.0, 0.45, 0.8))
M_GLOW.node_tree.nodes.get("Principled BSDF").inputs["Emission Strength"].default_value = 6.0


def face_back(u):
    """How far the face curves back at u (-1..1 across the mouth)."""
    return -CURVE * u * u


def lip(name, upper):
    """A lip as a tube swept across the mouth: its cross-section an ellipse that is fattest in the middle and pinches to
    nothing at the corners; the upper one with a cupid's bow, the lower one fuller."""
    nu, nv = 56, 24
    bm = bmesh.new()
    rows = []
    for i in range(nu + 1):
        u = -1.0 + 2.0 * i / nu
        taper = math.sqrt(max(0.0, 1.0 - u ** 6))
        if upper:
            bow = 1.0 + 0.28 * math.exp(-((abs(u) - 0.24) ** 2) / 0.02) - 0.22 * math.exp(-(u ** 2) / 0.006)
            hgt = 0.13 * taper * bow
            zc = 0.012 + hgt * 0.5 + 0.03 * u * u
            thick = 0.1 * taper
        else:
            hgt = 0.16 * taper * (1.0 + 0.15 * math.exp(-(u ** 2) / 0.1))
            zc = -0.012 - hgt * 0.5 + 0.03 * u * u
            thick = 0.12 * taper
        ring = []
        for j in range(nv):
            th = 2 * math.pi * j / nv
            y = face_back(u) + thick * 0.35 + thick * math.cos(th)
            z = zc + hgt * 0.5 * math.sin(th)
            ring.append(bm.verts.new((u * W, y, z)))
        rows.append(ring)
    for i in range(nu):
        for j in range(nv):
            a, b = rows[i][j], rows[i][(j + 1) % nv]
            c, d = rows[i + 1][(j + 1) % nv], rows[i + 1][j]
            bm.faces.new((a, b, c, d))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(M_LIP)
    for p in me.polygons:
        p.use_smooth = True
    return o


def teeth(name, upper, parent):
    """A row of rounded teeth following the mouth's curve, just behind the lips."""
    n = 8
    objs = []
    for k in range(n):
        u = -0.78 + 1.56 * k / (n - 1)
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        t = bpy.context.active_object
        t.name = "%s_%d" % (name, k)
        wid = 0.1 if abs(u) < 0.3 else 0.08
        t.scale = (wid, 0.05, 0.09)
        # the upper row hangs just below the line where the lips meet, the lower row stands just above it, so an open
        # mouth shows both
        z = (-0.012 if upper else 0.01) + 0.03 * u * u
        t.location = (u * W * 0.92, face_back(u) - 0.02, z)
        t.rotation_euler = (0.0, 0.0, -u * 0.5)
        mod = t.modifiers.new("round", "BEVEL")
        mod.width = 0.018
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier="round")
        bpy.ops.object.shade_smooth()
        t.data.materials.append(M_TOOTH)
        t.parent = parent
        objs.append(t)
    return objs


root = bpy.data.objects.new("Mouth", None)
bpy.context.scene.collection.objects.link(root)
upper = bpy.data.objects.new("Upper", None)
bpy.context.scene.collection.objects.link(upper)
upper.parent = root
jaw = bpy.data.objects.new("Jaw", None)
bpy.context.scene.collection.objects.link(jaw)
jaw.parent = root
# the hinge: behind the corners, on the line where the lips meet
jaw.location = (0.0, -0.28, 0.0)

ul = lip("UpperLip", True)
ul.parent = upper
teeth("UpperTooth", True, upper)
ll = lip("LowerLip", False)
ll.parent = jaw
ll.location = (0.0, 0.28, 0.0)
for t in teeth("LowerTooth", False, jaw):
    t.location.y += 0.28
# pass 87: no tongue. The floor of the mouth, dark, on the jaw (it swings down with it), so the wide-open mouth is dark
# all the way down to the lower lip: its upper half `Floor` is the inside (lit with the throat), its lower half
# `FloorBack` the outside (seen from below and behind once the jaw drops), like the throat's two skins


def half_egg(name, top, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(0.0, 0.28 - 0.17, -0.1))
    o = bpy.context.active_object
    o.name = name
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if (v.co.z < -0.001 if top else v.co.z > 0.001)], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.scale = (W * 0.66, 0.19, 0.06)
    bpy.ops.object.shade_smooth()
    o.data.materials.append(material)
    o.parent = jaw
    return o


floor = half_egg("Floor", True, M_CAVE)
half_egg("FloorBack", False, M_BACK)
# the dark mouth behind the teeth, so an open mouth is a mouth and not a hole in the world: a hollow bowl (pass 87; it
# was a closed egg), its front cut away behind the lips, so the throat has depth and the core glows at its back
# its top kept below the upper lip's line of sight from the high camera, so the shut mouth shows no dome behind its lip
THROAT_C = (0.0, -0.19, -0.09)
THROAT_R = (W * 0.8, 0.2, 0.14)
THROAT_CUT = 0.45   # the bowl's rim, as a fraction of its depth in front of its middle


def bowl(name, inner, material):
    """The throat's bowl: an egg with its front cut away; its inner skin faces in (seen through the open mouth), its outer
    skin faces out (seen from behind)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=1.0, location=THROAT_C)
    o = bpy.context.active_object
    o.name = name
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > THROAT_CUT], context="VERTS")
    if inner:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(o.data)
    bm.free()
    o.scale = THROAT_R
    bpy.ops.object.shade_smooth()
    o.data.materials.append(material)
    o.parent = root
    return o


cave = bowl("Cavity", True, M_CAVE)
bowl("ThroatBack", False, M_BACK)
# the core: a small hot lens against the back of the throat
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1.0, location=(0.0, -0.28, -0.14))
glow = bpy.context.active_object
glow.name = "Glow"
glow.scale = (0.085, 0.05, 0.07)
bpy.ops.object.shade_smooth()
glow.data.materials.append(M_GLOW)
glow.parent = root
# where the flare's middle sits: in the mouth's opening, behind the lips
flare = bpy.data.objects.new("Flare", None)
bpy.context.scene.collection.objects.link(flare)
flare.location = (0.0, -0.1, -0.1)
flare.parent = root

os.makedirs(OUT, exist_ok=True)
# previews: shut and wide open, from the front and a little above (like the game's camera), under a sun
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.scene.collection.objects.link(cam)
cam.location = (0.0, 2.6, 1.1)
cam.rotation_mode = "QUATERNION"
cam.rotation_quaternion = (Vector((0.0, 0.0, 0.0)) - cam.location).to_track_quat("-Z", "Y")
bpy.context.scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.0
bpy.context.scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(50), 0.0, math.radians(200))
sc = bpy.context.scene
names = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
sc.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in names else ("BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in names else "CYCLES")
sc.render.resolution_x = 512
sc.render.resolution_y = 512
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes.get("Background").inputs[0].default_value = (0.35, 0.3, 0.22, 1)
prev = A.get("previews", "D:/_projects/88fits/tools/dl/mouth")
os.makedirs(prev, exist_ok=True)
glow.hide_render = True
for tag, ang in (("shut", 0.0), ("open", -30.0)):
    jaw.rotation_euler = (math.radians(ang), 0.0, 0.0)
    sc.render.filepath = os.path.join(prev, NAME + "_preview_" + tag + ".png")
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as e:
        print("blender_mouth: preview failed:", e)
if A.get("game_views", "0") == "1":
    # the game's angle: the mouth tipped back 32 degrees so its lips face up to the camera, a camera 48 degrees up from
    # the front, the front-right, the right and the back-right
    sc.render.resolution_x = 360
    sc.render.resolution_y = 360
    root.rotation_euler = (math.radians(32.0), 0.0, 0.0)
    for state, ang, lit in (("shut", 0.0, False), ("gape", -28.0, True), ("open", -80.0, True)):
        jaw.rotation_euler = (math.radians(ang), 0.0, 0.0)
        glow.hide_render = not lit
        for side, az in (("front", 0.0), ("fr", 50.0), ("right", 100.0), ("back", 160.0)):
            el = math.radians(48.0)
            a = math.radians(az)
            cam.location = Vector((math.sin(a) * math.cos(el), math.cos(a) * math.cos(el), math.sin(el))) * 2.4
            cam.rotation_quaternion = (Vector((0.0, 0.0, -0.05)) - cam.location).to_track_quat("-Z", "Y")
            sc.render.filepath = os.path.join(prev, "%s_game_%s_%s.png" % (NAME, state, side))
            try:
                bpy.ops.render.render(write_still=True)
            except Exception as e:
                print("blender_mouth: game view failed:", e)
    root.rotation_euler = (0.0, 0.0, 0.0)
glow.hide_render = False
jaw.rotation_euler = (0.0, 0.0, 0.0)
bpy.data.objects.remove(cam)
bpy.data.objects.remove(sun)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, NAME + ".glb"), export_format="GLB", export_apply=True)
print("blender_mouth: wrote", os.path.join(OUT, NAME + ".glb"))

"""The Big Mouth as a 3D model (pass 34): glossy lips with a cupid's bow, two rows of teeth, a tongue and a dark mouth,
the lower lip, lower teeth and tongue on a `Jaw` node hinged behind the corners so the laser can open it.

    "$BLENDER" -b --python tools/blender_mouth.py -- out=D:/_projects/88fits/game/art/props [lips=0.86,0.05,0.12] [name=big_mouth]

Writes <out>/<name>.glb (nodes: Mouth > Upper, Jaw, Cavity) and previews shut and open in tools/dl/mouth/. The mouth faces Blender's +Y, which
the glTF exporter turns into -Z: a Godot node's forward, so look_at points the lips at a target. About a metre wide.
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
M_TONGUE = mat("tongue", (0.93, 0.36, 0.45), 0.45)
M_CAVE = mat("cavity", (0.18, 0.01, 0.04), 0.85)


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
bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(0.0, 0.28 - 0.14, -0.06))
tongue = bpy.context.active_object
tongue.name = "Tongue"
tongue.scale = (0.26, 0.2, 0.05)
bpy.ops.object.shade_smooth()
tongue.data.materials.append(M_TONGUE)
tongue.parent = jaw
# the dark mouth behind the teeth, so an open mouth is a mouth and not a hole in the world
bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(0.0, -0.22, -0.03))
cave = bpy.context.active_object
cave.name = "Cavity"
cave.scale = (W * 0.84, 0.17, 0.1)
bpy.ops.object.shade_smooth()
cave.data.materials.append(M_CAVE)
cave.parent = root

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
for tag, ang in (("shut", 0.0), ("open", -30.0)):
    jaw.rotation_euler = (math.radians(ang), 0.0, 0.0)
    prev = A.get("previews", "D:/_projects/88fits/tools/dl/mouth")
    os.makedirs(prev, exist_ok=True)
    sc.render.filepath = os.path.join(prev, NAME + "_preview_" + tag + ".png")
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as e:
        print("blender_mouth: preview failed:", e)
jaw.rotation_euler = (0.0, 0.0, 0.0)
bpy.data.objects.remove(cam)
bpy.data.objects.remove(sun)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, NAME + ".glb"), export_format="GLB", export_apply=True)
print("blender_mouth: wrote", os.path.join(OUT, NAME + ".glb"))

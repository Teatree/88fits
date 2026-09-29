"""A walking ant for the fire ant's art (pass 34): the Mixamo + Wan method for a creature Mixamo has no skeleton for.

Blender builds a stylised ant from primitives (head with mandibles and elbowed antennae, thorax, a waist node, a big
gaster, six legs of femur and tibia) and walks it in place on the insect tripod gait (front and hind legs of one side
with the middle leg of the other, then the other three), the feet planted on the ground through a two-bone solve. It
renders what Wan 2.2 Fun Control needs from the game's views (the camera 25 degrees above, like tools/pose_driver.py):

  <out>/<view>/ctl_NN.png   the depth video (near is bright, the ground and the sky black): the motion the clip follows
  <out>/<view>/clay.png     frame 0 as coloured clay on the screen colour: what the painting is repainted from
  <out>/meta.json

    "$BLENDER" -b --python tools/blender_ant.py -- out=tools/dl/drivers/ant_walk frames=12 cycles=2 legs=1.0 body=1.0
      frames: one stride in frames; cycles: strides rendered (the clip is frames*cycles+1 long, Wan's 4k+1);
      legs / body / head / gaster: proportions (1 = the reference ant); stride: step length; bob: body bounce.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector


def _args():
    out = {}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        if "=" in a:
            k, v = a.split("=", 1)
            out[k] = v
    return out


A = _args()
OUT = A.get("out", "tools/dl/drivers/ant_walk")
N = int(A.get("frames", 12))
CYCLES = int(A.get("cycles", 2))
LEG = float(A.get("legs", 1.0))
BODY = float(A.get("body", 1.0))
HEAD = float(A.get("head", 1.0))
GASTER = float(A.get("gaster", 1.0))
STRIDE = float(A.get("stride", 0.34))
BOB = float(A.get("bob", 0.03))
PITCH = math.radians(float(A.get("pitch", 25.0)))
SIZE = 640
SCREEN = tuple(float(v) for v in A.get("screen", "0,1,0").split(","))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def mat(name, rgb, rough=0.45):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


M_BODY = mat("body", (0.72, 0.1, 0.04), 0.3)
M_DARK = mat("dark", (0.35, 0.05, 0.03), 0.4)
M_EYE = mat("eye", (0.02, 0.02, 0.02), 0.2)


def ellipsoid(name, loc, scale, m, seg=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.shade_smooth()
    o.data.materials.append(m)
    return o


def rod(name, radius, m):
    """A unit-length capsule along +Z from its origin (placed and stretched every frame by aim())."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=1.0, location=(0, 0, 0.5))
    o = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    # origin at the base
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    o.name = name
    o.data.materials.append(m)
    return o


def aim(o, a, b):
    """Put a unit rod from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    o.location = a
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized()) if L > 1e-6 else (1, 0, 0, 0)
    o.scale = (1.0, 1.0, max(L, 1e-4))


def knee(h, f, a, b, out):
    """Two-bone solve: the knee between hip h and foot f (femur a, tibia b), raised up and out like an insect's."""
    h, f = Vector(h), Vector(f)
    d = f - h
    dist = min(max(d.length, 1e-4), a + b - 1e-4)
    dn = d.normalized()
    x = (a * a - b * b + dist * dist) / (2 * dist)
    hgt = math.sqrt(max(a * a - x * x, 0.0))
    up = (Vector((0, 0, 1)) + Vector(out) * 0.9).normalized()
    side = up - dn * up.dot(dn)
    side.normalize()
    return h + dn * x + side * hgt


# ---------------------------------------------------------------- the body (the ant faces +Y)
TH_Z = 0.4 * LEG      # thorax height above the ground
ellipsoid("thorax", (0, 0.08, TH_Z + 0.02), (0.17 * BODY, 0.38 * BODY, 0.16 * BODY), M_BODY)
ellipsoid("waist", (0, -0.34 * BODY, TH_Z + 0.06), (0.075, 0.075, 0.1), M_BODY, 16)
ellipsoid("waist2", (0, -0.48 * BODY, TH_Z + 0.07), (0.09, 0.08, 0.09), M_BODY, 16)
ellipsoid("gaster", (0, -0.86 * BODY * GASTER, TH_Z + 0.1), (0.31 * GASTER, 0.38 * GASTER, 0.28 * GASTER), M_BODY)
head = ellipsoid("head", (0, 0.66 * BODY, TH_Z + 0.12), (0.31 * HEAD, 0.28 * HEAD, 0.25 * HEAD), M_BODY)
for s in (-1, 1):
    ellipsoid("eye", (s * 0.24 * HEAD, 0.76 * BODY, TH_Z + 0.2), (0.06, 0.06, 0.06), M_EYE, 16)
mand = []
for s in (-1, 1):
    m1 = rod("mand", 0.035, M_DARK)
    mand.append((m1, s))
ants = []
for s in (-1, 1):
    ants.append((rod("scape", 0.032, M_DARK), rod("funiculus", 0.028, M_DARK), s))
legs = []
# hip points on the thorax, rest feet on the ground: front, middle, hind; x out, y forward
HIPS = [(0.12, 0.3), (0.14, 0.08), (0.12, -0.14)]
FEET = [(0.52, 0.66), (0.66, 0.06), (0.56, -0.56)]
FEMUR, TIBIA = 0.38 * LEG, 0.5 * LEG
for side in (-1, 1):
    for k in range(3):
        legs.append({"side": side, "k": k, "femur": rod("femur", 0.045, M_DARK), "tibia": rod("tibia", 0.035, M_DARK)})
# the tripod: left front, right middle, left hind move together; then the other three
for L in legs:
    L["phase"] = 0.0 if ((L["side"] < 0) == (L["k"] != 1)) else 0.5


def pose(t):
    """Set the ant at time t in strides (0..1 per stride)."""
    bob = BOB * math.sin(t * 2 * math.pi * 2)
    sway = 0.03 * math.sin(t * 2 * math.pi)
    for name in ("thorax", "waist", "gaster", "head", "eye"):
        pass
    for o in bpy.data.objects:
        if o.name.startswith(("thorax", "waist", "gaster", "head", "eye")) and o.type == "MESH":
            if "rest" not in o:
                o["rest"] = list(o.location)
            r = o["rest"]
            o.location = (r[0] + sway * (1.4 if o.name.startswith("gaster") else 1.0), r[1], r[2] + bob)
    hz = TH_Z + bob
    hy = 0.66 * BODY
    # mandibles open and close a little; antennae sway
    for m1, s in mand:
        base = Vector((s * 0.12 * HEAD, hy + 0.24 * HEAD, hz + 0.04))
        tip = base + Vector((-s * 0.08 + s * 0.04 * math.sin(t * 2 * math.pi * 2), 0.24 * HEAD, -0.05))
        aim(m1, base, tip)
    for sc, fu, s in ants:
        # elbowed: the scape rises up and out from the front of the head, the rest bends forward and down
        base = Vector((s * 0.14 * HEAD, hy + 0.16 * HEAD, hz + 0.18 * HEAD))
        elbow = base + Vector((s * 0.16, 0.08, 0.34))
        tip = elbow + Vector((s * 0.1 + 0.05 * math.sin(t * 2 * math.pi + s), 0.36, -0.08 + 0.05 * math.cos(t * 2 * math.pi)))
        aim(sc, base, elbow)
        aim(fu, elbow, tip)
    for L in legs:
        s, k = L["side"], L["k"]
        hx, hy2 = HIPS[k]
        hip = Vector((s * hx * BODY + sway, hy2 * BODY, hz - 0.04))
        fx, fy = FEET[k]
        ph = (t + L["phase"]) % 1.0
        if ph < 0.5:
            u = ph / 0.5
            y = fy * LEG + STRIDE / 2 - STRIDE * u
            z = 0.0
        else:
            u = (ph - 0.5) / 0.5
            y = fy * LEG - STRIDE / 2 + STRIDE * u
            z = 0.12 * math.sin(math.pi * u)
        foot = Vector((s * fx * LEG, y, z))
        kn = knee(hip, foot, FEMUR, TIBIA, (s, 0, 0))
        aim(L["femur"], hip, kn)
        aim(L["tibia"], kn, foot)


# ---------------------------------------------------------------- camera and renders
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
scene.render.resolution_x = SIZE
scene.render.resolution_y = SIZE
scene.render.film_transparent = False
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")


VIEWS = {"front": 0.0, "fd": 45.0, "side": 90.0, "bd": 135.0, "back": 180.0}


def place_camera(view):
    # the camera's bearing round the ant (which faces +Y): front 0 (it walks at the camera), side 90 (it faces
    # screen-right, like the painted side views), back 180; the diagonals between, facing right as well
    yaw = math.radians(VIEWS[view])
    d = Vector((math.sin(yaw), math.cos(yaw), 0))
    target = Vector((0, -0.1, 0.35))
    dist = 10.0
    pos = target + d * dist * math.cos(PITCH) + Vector((0, 0, dist * math.sin(PITCH)))
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - pos).to_track_quat("-Z", "Y")
    cam_data.ortho_scale = 2.9 * max(LEG, BODY)


def depth_material():
    """Near bright, far dark: an emission of the camera distance mapped over the ant's depth range."""
    m = bpy.data.materials.new("depth")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    camd = nt.nodes.new("ShaderNodeCameraData")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 9.0
    mr.inputs["From Max"].default_value = 11.0
    mr.inputs["To Min"].default_value = 1.0
    mr.inputs["To Max"].default_value = 0.08
    nt.links.new(camd.outputs["View Z Depth"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


os.makedirs(OUT, exist_ok=True)
total = N * CYCLES + 1
DEPTH = depth_material()
originals = {o.name: [s.material for s in o.material_slots] for o in bpy.data.objects if o.type == "MESH"}
for view in A.get("views", "front,fd,side,bd,back").split(","):
    d = os.path.join(OUT, view)
    os.makedirs(d, exist_ok=True)
    place_camera(view)
    # clay: frame 0, coloured, lit, on the screen colour
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (0.05, 0.02, 0.02)
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = SCREEN
    for o in bpy.data.objects:
        if o.type == "MESH":
            for i, s in enumerate(o.material_slots):
                s.material = originals[o.name][i]
    pose(0.0)
    scene.render.filepath = os.path.join(d, "clay.png")
    bpy.ops.render.render(write_still=True)
    # depth: every frame of the clip
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.cycles.use_denoising = False
    bg.inputs[0].default_value = (0, 0, 0, 1)
    for o in bpy.data.objects:
        if o.type == "MESH":
            for s in o.material_slots:
                s.material = DEPTH
    for f in range(total):
        pose((f % N) / N)
        scene.render.filepath = os.path.join(d, "ctl_%02d.png" % f)
        bpy.ops.render.render(write_still=True)
    print("blender_ant: rendered", view, total, "depth frames")
json.dump({"frames": N, "cycles": CYCLES, "total": total, "legs": LEG, "body": BODY, "head": HEAD, "gaster": GASTER, "stride": STRIDE,
           "pitch": math.degrees(PITCH), "size": SIZE}, open(os.path.join(OUT, "meta.json"), "w"), indent=1)

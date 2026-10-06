"""The Dune Scorpion's walk from Garry's 3D scorpion (pass 46): the drivers its four art variants are painted and animated
on, the fire ant's method (tools/blender_ant.py) with a real model instead of a blockout.

_REFERENCES/3d/scorpion.zip holds source/Scorpion simple.glb: one skinned mesh on a 78-joint rig (eight legs of six joints,
five abdomen and seven sting joints, two pedipalps with two-part claws) with only an idle animation. This walks it in
place on the scorpion's alternating tetrapod gait (front-left, second-right, third-left and hind-right legs together, then
the other four): each hip swings about the vertical through its stride and lifts its leg on the way forward, the body
bobs twice a stride, the tail sways and the claws breathe. One tail and one body by construction, in every view.

It renders what Wan 2.2 Fun Control needs for the five game views (front, fd, side, bd, back; the camera 25 degrees above,
like tools/pose_driver.py; the scorpion faces screen-right in the side and diagonal views):
  <out>/<view>/ctl_NN.png   the depth video (near bright, the ground and the sky black)
  <out>/<view>/clay.png     frame 0 as warm clay on the screen colour: what the side painting is repainted from
  <out>/meta.json

  "$BLENDER" -b --python tools/blender_scorpion.py -- out=tools/dl/drivers/scorpion_walk frames=12 cycles=2

mode=death renders the death the same way, front view only (a creature has one die set): 25 frames from the walk's
first pose (so the front painting matches frame 0), a spasm, a roll onto its back about the long axis while the tail
straightens out flat behind it, and the legs curling up in the air with a last twitch (pass 46: Klein painted the
"dead on its back" still as a live scorpion rearing up, and the vision check passed it). gen_ctl walks the front
painting along it with Wan 2.2 Fun Control when the recipe names "death_drivers".

  "$BLENDER" -b --python tools/blender_scorpion.py -- mode=death out=tools/dl/drivers/scorpion_death
"""
import io
import json
import math
import os
import sys
import zipfile

import bpy
from mathutils import Matrix, Quaternion, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZIP = os.path.join(REPO, "_REFERENCES", "3d", "scorpion.zip")
SRC = os.path.join(REPO, "tools", "dl", "refs46", "scorpion", "source", "Scorpion simple.glb")


def _args():
    out = {}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        if "=" in a:
            k, v = a.split("=", 1)
            out[k] = v
    return out


A = _args()
OUT = os.path.abspath(A.get("out", os.path.join(REPO, "tools", "dl", "drivers", "scorpion_walk")))  # render paths must be absolute
N = int(A.get("frames", 12))
CYCLES = int(A.get("cycles", 2))
SWING = math.radians(float(A.get("swing", 13.0)))
LIFT = math.radians(float(A.get("lift", 16.0)))
BOB = float(A.get("bob", 0.0025))
PITCH = math.radians(float(A.get("pitch", 25.0)))
MODE = A.get("mode", "walk")
SIZE = 640
SCREEN = tuple(float(v) for v in A.get("screen", "0,1,0").split(","))
CLAY = (0.78, 0.55, 0.3, 1.0)


def source():
    if not os.path.exists(SRC):
        os.makedirs(os.path.dirname(SRC), exist_ok=True)
        z = zipfile.ZipFile(ZIP)
        open(SRC, "wb").write(z.read("source/Scorpion simple.glb"))
    return SRC


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=source())
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
body = [o for o in bpy.data.objects if o.type == "MESH"][0]
# stop the imported idle action: the pose is driven by hand
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = Quaternion()
    pb.location = Vector()

# the legs: tetrapod groups A and B half a stride apart; the scorpion faces -Y, so a foot on the +X side moves forward
# when its hip turns clockwise seen from above
LEGS = []
GROUP_A = {("l", "FrontLeg"), ("r", "MidFrontLeg"), ("l", "MidBackLeg"), ("r", "BackLeg")}
for side in ("l", "r"):
    for leg in ("FrontLeg", "MidFrontLeg", "MidBackLeg", "BackLeg"):
        hip = arm.pose.bones.get("Scorpion_%s_%s_HipSHJnt" % (side, leg))
        toe = arm.data.bones.get("Scorpion_%s_%s_ToeSHJnt" % (side, leg))
        if hip is None or toe is None:
            continue
        h = arm.matrix_world @ hip.bone.head_local
        t = arm.matrix_world @ toe.tail_local
        out = Vector((t.x - h.x, t.y - h.y, 0.0)).normalized()
        LEGS.append({"pb": hip, "phase": 0.0 if (side, leg) in GROUP_A else 0.5, "fwd": -1.0 if side == "l" else 1.0, "out": out})
STING = [arm.pose.bones.get("Scorpion_Sting_01_%02dSHJnt" % k) for k in range(1, 8)]
PALPS = [arm.pose.bones.get("Scorpion_%s_Pedipalp_01_02SHJnt" % s) for s in ("l", "r")]
CLAWS = [arm.pose.bones.get("Scorpion_%s_Claw_02_01SHJnt" % s) for s in ("l", "r")]
ROOT = arm.pose.bones.get("Scorpion_ROOTSHJnt")


def world_rot(pb, q_world):
    """A rotation given in world space, applied to a pose bone whose parents are at rest: into the bone's own frame."""
    r = (arm.matrix_world @ pb.bone.matrix_local).to_3x3().normalized()
    return (r.inverted() @ q_world.to_matrix() @ r).to_quaternion()


def pose(t):
    """t in [0, 1): one stride."""
    for L in LEGS:
        u = (t + L["phase"]) % 1.0
        if u < 0.5:
            # stance: the foot on the ground sweeps back from the front of its arc to the back
            s = 1.0 - 4.0 * u
            lift = 0.0
        else:
            # swing: lifted and carried forward
            v = (u - 0.5) * 2.0
            s = -1.0 + 2.0 * (0.5 - 0.5 * math.cos(math.pi * v))
            lift = math.sin(math.pi * v)
        q_yaw = Quaternion(Vector((0, 0, 1)), L["fwd"] * SWING * s)
        axis = L["out"].cross(Vector((0, 0, 1)))
        q_lift = Quaternion(axis, -LIFT * lift)
        L["pb"].rotation_quaternion = world_rot(L["pb"], q_yaw @ q_lift)
    if ROOT:
        ROOT.location = Vector((0, 0, 0))
        ROOT.location = (arm.matrix_world @ ROOT.bone.matrix_local).to_3x3().inverted() @ Vector((0, 0, BOB * math.sin(4.0 * math.pi * t)))
    for k, pb in enumerate(STING):
        if pb:
            pb.rotation_quaternion = world_rot(pb, Quaternion(Vector((0, 0, 1)), math.radians(2.2) * math.sin(2.0 * math.pi * t + k * 0.5)))
    for k, pb in enumerate(PALPS):
        if pb:
            pb.rotation_quaternion = world_rot(pb, Quaternion(Vector((0, 0, 1)), math.radians(3.0) * math.sin(2.0 * math.pi * t + k * math.pi)))
    for k, pb in enumerate(CLAWS):
        if pb:
            pb.rotation_quaternion = world_rot(pb, Quaternion(Vector((0, 0, 1)), math.radians(6.0) * (0.5 + 0.5 * math.sin(2.0 * math.pi * t)) * (1 if k == 0 else -1)))
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- the death
def _chain(pb):
    out = []
    while pb is not None:
        out.append(pb)
        pb = pb.children[0] if pb.children else None
    return out


LEG_CHAINS = [(_chain(L["pb"]), 1.0 if L["out"].x > 0 else -1.0) for L in LEGS]
# the dead tail lies out to one side (beside the body once it is over, so a scorpion on its back still shows its tail) and a
# little up, which is down on the sand after the roll
TAIL_DIR = Vector((0.3, 0.95, 0.1)).normalized()
REST_DIRS = [((arm.matrix_world @ pb.bone.tail_local) - (arm.matrix_world @ pb.bone.head_local)).normalized() for pb in STING if pb]
CENTRE_Z = 0.06


def _ease(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def death_pose(f, total):
    """Frame f of the death: 0 = the walk's first pose, then the spasm, the roll and the settle."""
    pose(0.0)
    u = f / float(total - 1)
    spasm = math.sin(math.pi * min(u / 0.18, 1.0)) if u < 0.18 else 0.0
    roll = _ease((u - 0.16) / 0.46)
    # the tail stays curled while the body is on its side (out straight it would leave the frame) and lies down as it lands
    flat = _ease((u - 0.38) / 0.3)
    settle = max(u - 0.62, 0.0) / 0.38
    # the legs: splay in the spasm, then curl in towards the belly (in the air once it is over), a last twitch
    curl = -9.0 * spasm + 24.0 * _ease((u - 0.2) / 0.5) + 7.0 * math.sin(settle * math.pi * 3.0) * (1.0 - settle)
    for chain, side in LEG_CHAINS:
        q = Quaternion(Vector((0.0, side, 0.0)), math.radians(curl))
        for k, pb in enumerate(chain[:5]):
            pb.rotation_quaternion = world_rot(pb, q) if k else world_rot(pb, q) @ pb.rotation_quaternion
    # the tail: a lash up in the spasm, then every segment turned to lie flat behind the body
    prev = Quaternion()
    for pb, d in zip([b for b in STING if b], REST_DIRS):
        g = d.rotation_difference(TAIL_DIR)
        g = Quaternion().slerp(g, flat)
        if spasm > 0.0:
            g = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(-10.0 * spasm)) @ g
        pb.rotation_quaternion = world_rot(pb, prev.inverted() @ g)
        prev = g
    # the claws hang open
    for k, pb in enumerate(CLAWS):
        if pb:
            pb.rotation_quaternion = world_rot(pb, Quaternion(Vector((0, 0, 1)), math.radians(14.0 * max(spasm, roll)) * (1 if k == 0 else -1)))
    # the roll about the long axis, lifted clear of the sand while it is on its side and shifted the way it falls
    a = math.pi * roll
    arm.rotation_mode = "XYZ"
    arm.rotation_euler = (0.0, a, math.radians(-12.0) * roll)
    lift = 0.12 * math.sin(a)
    # rotating about the origin moves the body's centre line; put it back on the pivot (CENTRE_Z), then lift and shift
    c = Vector((0.0, 0.0, CENTRE_Z))
    rc = Matrix.Rotation(a, 3, "Y") @ c
    arm.location = (c - rc) + Vector((0.07 * (1.0 - math.cos(a)) * 0.5, 0.0, lift))
    bpy.context.view_layer.update()


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
# the middle of the creature with its tail up, and the frame it needs from every side
mn = Vector((1e9, 1e9, 1e9))
mx = Vector((-1e9, -1e9, -1e9))
for v in body.bound_box:
    w = body.matrix_world @ Vector(v)
    mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
    mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
TARGET = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, (mn.z + mx.z) * 0.42))
EXTENT = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
DIST = 10.0


def place_camera(view):
    # the camera's bearing round the scorpion, which faces -Y: front 0 (it walks at the camera), side 90 (it faces
    # screen-right, like the painted side views), back 180; the diagonals between, facing right as well
    yaw = math.radians(VIEWS[view])
    d = Vector((-math.sin(yaw), -math.cos(yaw), 0))
    pos = TARGET + d * DIST * math.cos(PITCH) + Vector((0, 0, DIST * math.sin(PITCH)))
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (TARGET - pos).to_track_quat("-Z", "Y")
    cam_data.ortho_scale = EXTENT * 1.45


def depth_material():
    """Near bright, far dark: an emission of the camera distance mapped over the creature's depth range."""
    m = bpy.data.materials.new("depth")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    camd = nt.nodes.new("ShaderNodeCameraData")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = DIST - EXTENT * 0.7
    mr.inputs["From Max"].default_value = DIST + EXTENT * 0.7
    mr.inputs["To Min"].default_value = 1.0
    mr.inputs["To Max"].default_value = 0.08
    nt.links.new(camd.outputs["View Z Depth"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def clay_material():
    m = bpy.data.materials.new("clay")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = CLAY
    m.diffuse_color = CLAY
    return m


os.makedirs(OUT, exist_ok=True)
total = N * CYCLES + 1 if MODE != "death" else int(A.get("frames", 25))
DEPTH = depth_material()
CLAYM = clay_material()


def at(f):
    if MODE == "death":
        death_pose(f, total)
    else:
        pose((f % N) / N)


for view in A.get("views", "front" if MODE == "death" else "front,fd,side,bd,back").split(","):
    d = os.path.join(OUT, view)
    os.makedirs(d, exist_ok=True)
    place_camera(view)
    # clay: frame 0, warm and lit, on the screen colour
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (0.05, 0.02, 0.02)
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = SCREEN
    for s in body.material_slots:
        s.material = CLAYM
    at(0)
    scene.render.filepath = os.path.join(d, "clay.png")
    bpy.ops.render.render(write_still=True)
    if MODE == "death":
        # the clay at a few moments of the death, to look at
        for f in (total // 4, total // 2, total - 1):
            at(f)
            scene.render.filepath = os.path.join(d, "clay_%02d.png" % f)
            bpy.ops.render.render(write_still=True)
    # depth: every frame of the clip
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.cycles.use_denoising = False
    bg.inputs[0].default_value = (0, 0, 0, 1)
    for s in body.material_slots:
        s.material = DEPTH
    for f in range(total):
        at(f)
        scene.render.filepath = os.path.join(d, "ctl_%02d.png" % f)
        bpy.ops.render.render(write_still=True)
    print("blender_scorpion: rendered", view, total, "depth frames")
json.dump({"mode": MODE, "frames": N, "cycles": CYCLES, "total": total, "swing": math.degrees(SWING), "lift": math.degrees(LIFT), "bob": BOB,
           "pitch": math.degrees(PITCH), "size": SIZE, "extent": EXTENT}, open(os.path.join(OUT, "meta.json"), "w"), indent=1)

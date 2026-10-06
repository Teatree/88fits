"""The Bull Beetle's drivers from Garry's rigged rhino beetle (pass 48): the depth videos its four art variants (BB-A..D)
are painted and walked on, the Dune Scorpion's method (tools/blender_scorpion.py) with the model's own clips.

_REFERENCES/3d/a-rhino-beetle.zip holds source/rhino_beetle_study.fbx: one skinned mesh (Cube.008, material rhino_bug) on
an 18-bone armature "Beetle" (body, head and horn, three pairs of two- and three-part legs) with four actions: walk (30
frames), idle (140), attack (38) and death (40); textures/rhino_albedom.png is its colour map. The beetle faces -Y, like
the scorpion, so the same five cameras see it walk at the viewer (front), face screen-right (side) and walk away (back).

  <out>/<view>/ctl_NN.png   the depth video (near bright, the ground and the sky black)
  <out>/<view>/clay.png     frame 0 as warm clay on the screen colour: what the side painting is repainted from
  <out>/<view>/look.png     frame 0 textured with the model's own colour map on the screen colour: a look reference
  <out>/meta.json

  "$BLENDER" -b --python tools/blender_beetle.py -- out=tools/dl/drivers/beetle_walk frames=12 cycles=2
  "$BLENDER" -b --python tools/blender_beetle.py -- mode=death out=tools/dl/drivers/beetle_death

mode=death plays the model's death clip (front view only: a creature has one die set), 25 frames from its first frame.

depth=tight (pass 49, Garry: "a lot of the feet stay still while he is supposed to be moving") maps each view's own depth
range, nearest vertex to farthest over the whole clip, onto bright..dark instead of one wide range for every view: the wide
range left the beetle one flat grey shape, the far legs melted into the near ones, and Wan walked the painted far legs on
nothing, so they stood still. tools/dl/drivers/beetle_walk_t is the walk rendered that way.

amp=1.7 (pass 49) swings the six legs that much wider: each leg bone's rotation away from its own average over the cycle
is scaled (axis kept, angle times amp), so the stance stays the clip's and only the steps grow; the body, head and horns
move as the clip has them. The model's own walk is a real beetle's, too small a step to read on a creature 2 m long seen
from 22 m. tools/dl/drivers/beetle_walk_amp is the walk rendered with depth=tight amp=1.7.
"""
import json
import math
import os
import sys
import zipfile

import bpy
from mathutils import Quaternion, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZIP = os.path.join(REPO, "_REFERENCES", "3d", "a-rhino-beetle.zip")
SRC_DIR = os.path.join(REPO, "tools", "dl", "refs48", "rhino_beetle")
SRC = os.path.join(SRC_DIR, "source", "rhino_beetle_study.fbx")
ALBEDO = os.path.join(SRC_DIR, "textures", "rhino_albedom.png")


def _args():
    out = {}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        if "=" in a:
            k, v = a.split("=", 1)
            out[k] = v
    return out


A = _args()
MODE = A.get("mode", "walk")
OUT = os.path.abspath(A.get("out", os.path.join(REPO, "tools", "dl", "drivers", "beetle_walk" if MODE != "death" else "beetle_death")))
N = int(A.get("frames", 12))
CYCLES = int(A.get("cycles", 2))
PITCH = math.radians(float(A.get("pitch", 25.0)))
SIZE = 640
SCREEN = tuple(float(v) for v in A.get("screen", "0,1,0").split(","))
DEPTH_MODE = A.get("depth", "wide")
AMP = float(A.get("amp", "1.0"))
## the six legs' bones (Bone.003 the front pair, .004 and .005 the middle and hind pairs, each with its lower parts)
LEGS = ("Bone.003", "Bone.004", "Bone.005")
CLAY = (0.78, 0.55, 0.3, 1.0)


def source():
    if not os.path.exists(SRC) or not os.path.exists(ALBEDO):
        os.makedirs(SRC_DIR, exist_ok=True)
        zipfile.ZipFile(ZIP).extractall(SRC_DIR)
    return SRC


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
bpy.ops.import_scene.fbx(filepath=source())
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
body = [o for o in bpy.data.objects if o.type == "MESH"][0]


def _action(name):
    for a in bpy.data.actions:
        if a.name.endswith("|" + name):
            return a
    raise SystemExit("blender_beetle: no action %s in %s" % (name, [a.name for a in bpy.data.actions]))


def use_action(name):
    act = _action(name)
    if arm.animation_data is None:
        arm.animation_data_create()
    ad = arm.animation_data
    ad.action = act
    # Blender 4.4+ layered actions: the action's slot must be picked too or nothing plays
    if hasattr(ad, "action_slot") and getattr(act, "slots", None) and len(act.slots) > 0:
        ad.action_slot = act.slots[0]
    return act


ACT = use_action("death" if MODE == "death" else "walk")
F0, F1 = ACT.frame_range[0], ACT.frame_range[1]


POSE = None   # amp: the cycle's N poses with the legs' swing scaled, {bone: (location, rotation, scale)} each


def set_time(frame):
    if POSE is not None:
        k = int(round((frame - F0) / (F1 - F0) * N)) % N
        for pb in arm.pose.bones:
            loc, q, sc = POSE[k][pb.name]
            pb.location = loc
            pb.rotation_quaternion = q
            pb.scale = sc
        bpy.context.view_layer.update()
        return
    i = int(math.floor(frame))
    scene.frame_set(i, subframe=frame - i)
    bpy.context.view_layer.update()


def _sample_pose():
    """The clip's N poses of one cycle, as the action plays them."""
    rows = []
    for k in range(N):
        t = F0 + (F1 - F0) * k / float(N)
        i = int(math.floor(t))
        scene.frame_set(i, subframe=t - i)
        rows.append({pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in arm.pose.bones})
    return rows


def _amplify(rows, amp):
    """Each leg bone's rotation away from its own average over the cycle, the angle times `amp` (the axis kept)."""
    out = [dict(r) for r in rows]
    for name in rows[0].keys():
        if not name.startswith(LEGS):
            continue
        qs = [r[name][1] for r in rows]
        acc = [0.0, 0.0, 0.0, 0.0]
        for q in qs:
            sgn = 1.0 if q.dot(qs[0]) >= 0.0 else -1.0
            for j, v in enumerate((q.w, q.x, q.y, q.z)):
                acc[j] += v * sgn
        mean = Quaternion(acc)
        mean.normalize()
        inv = mean.inverted()
        for k, q in enumerate(qs):
            d = inv @ q
            axis, ang = d.to_axis_angle()
            if ang > math.pi:
                ang -= 2.0 * math.pi
            loc, _q, sc = out[k][name]
            out[k][name] = (loc, mean @ Quaternion(axis, ang * amp), sc)
    return out


if MODE != "death" and abs(AMP - 1.0) > 0.001:
    POSE = _amplify(_sample_pose(), AMP)
    arm.animation_data.action = None
    print("blender_beetle: legs swung %.2fx" % AMP)


def bbox():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    mesh = ev.to_mesh()
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    mw = ev.matrix_world
    for v in mesh.vertices:
        w = mw @ v.co
        mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
        mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    ev.to_mesh_clear()
    return mn, mx


# the walk is played in place: any drift of the body's centre over the clip is taken back out per frame
arm.location = Vector((0, 0, 0))
set_time(F0)
mn0, mx0 = bbox()
C0 = (mn0 + mx0) * 0.5


def at(f, total):
    arm.location = Vector((0, 0, 0))
    if MODE == "death":
        set_time(F0 + (F1 - F0) * f / float(max(total - 1, 1)))
        return
    t = (f % N) / float(N)
    set_time(F0 + (F1 - F0) * t)
    mn, mx = bbox()
    c = (mn + mx) * 0.5
    # kept on the spot horizontally (in case the clip carries root motion); the height keeps the clip's own bob
    arm.location = Vector((C0.x - c.x, C0.y - c.y, 0.0))
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
# the frame the creature needs from every side over the whole clip
mn = Vector((1e9, 1e9, 1e9))
mx = Vector((-1e9, -1e9, -1e9))
for k in range(9):
    arm.location = Vector((0, 0, 0))
    set_time(F0 + (F1 - F0) * k / 8.0)
    a, b = bbox()
    mn = Vector((min(mn.x, a.x), min(mn.y, a.y), min(mn.z, a.z)))
    mx = Vector((max(mx.x, b.x), max(mx.y, b.y), max(mx.z, b.z)))
TARGET = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, (mn.z + mx.z) * 0.42))
EXTENT = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
DIST = EXTENT * 3.0


def place_camera(view):
    # the camera's bearing round the beetle, which faces -Y: front 0 (it walks at the camera), side 90 (it faces
    # screen-right, like the painted side views), back 180; the diagonals between, facing right as well
    yaw = math.radians(VIEWS[view])
    d = Vector((-math.sin(yaw), -math.cos(yaw), 0))
    pos = TARGET + d * DIST * math.cos(PITCH) + Vector((0, 0, DIST * math.sin(PITCH)))
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (TARGET - pos).to_track_quat("-Z", "Y")
    cam_data.ortho_scale = EXTENT * (1.6 if MODE == "death" else 1.45)
    cam_data.clip_end = DIST * 4.0


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
    mr.inputs["From Min"].default_value = DIST - EXTENT * 0.55
    mr.inputs["From Max"].default_value = DIST + EXTENT * 0.55
    mr.inputs["To Min"].default_value = 1.0
    mr.inputs["To Max"].default_value = 0.08
    mr.name = "range"
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


def look_material():
    """The model's own colour map (the FBX does not carry a texture path that exists here)."""
    m = bpy.data.materials.new("look")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(ALBEDO)
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    nt.nodes.active = tex
    return m


def view_depths(total):
    """The nearest and farthest the creature comes along the camera's axis over the clip (depth=tight)."""
    bpy.context.view_layer.update()
    fwd = cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))
    near, far = 1e9, -1e9
    dg = bpy.context.evaluated_depsgraph_get()
    for k in range(9):
        at(int(round((total - 1) * k / 8.0)), total)
        dg.update()
        ev = body.evaluated_get(dg)
        mesh = ev.to_mesh()
        mw = ev.matrix_world
        for v in mesh.vertices:
            d = (mw @ v.co - cam.location).dot(fwd)
            near = min(near, d)
            far = max(far, d)
        ev.to_mesh_clear()
    return near, far


def set_depth_range(near, far):
    mr = DEPTH.node_tree.nodes["range"]
    pad = (far - near) * 0.03
    mr.inputs["From Min"].default_value = near - pad
    mr.inputs["From Max"].default_value = far + pad
    mr.inputs["To Min"].default_value = 1.0
    mr.inputs["To Max"].default_value = 0.16


os.makedirs(OUT, exist_ok=True)
VIEW_TRANSFORM = scene.view_settings.view_transform
total = N * CYCLES + 1 if MODE != "death" else int(A.get("frames", 25))
DEPTH = depth_material()
CLAYM = clay_material()
LOOKM = look_material()


def workbench(color_type):
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = color_type
    scene.display.shading.show_cavity = True
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (0.05, 0.02, 0.02)
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = SCREEN


def set_material(m):
    for s in body.material_slots:
        s.material = m


for view in A.get("views", "front" if MODE == "death" else "front,fd,side,bd,back").split(","):
    d = os.path.join(OUT, view)
    os.makedirs(d, exist_ok=True)
    place_camera(view)
    at(0, total)
    # clay: frame 0, warm and lit, on the screen colour
    workbench("MATERIAL")
    set_material(CLAYM)
    scene.render.filepath = os.path.join(d, "clay.png")
    bpy.ops.render.render(write_still=True)
    # the look: the same frame in the model's own colours
    workbench("TEXTURE")
    set_material(LOOKM)
    scene.render.filepath = os.path.join(d, "look.png")
    bpy.ops.render.render(write_still=True)
    if MODE == "death":
        workbench("MATERIAL")
        set_material(CLAYM)
        for f in (total // 4, total // 2, (3 * total) // 4, total - 1):
            at(f, total)
            scene.render.filepath = os.path.join(d, "clay_%02d.png" % f)
            bpy.ops.render.render(write_still=True)
    # depth: every frame of the clip
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.cycles.use_denoising = False
    bg.inputs[0].default_value = (0, 0, 0, 1)
    set_material(DEPTH)
    if DEPTH_MODE == "tight":
        near, far = view_depths(total)
        set_depth_range(near, far)
        print("blender_beetle: %s depth %.2f..%.2f" % (view, near, far))
        # the depth written as it is: the default view transform (AgX) squeezed the emission into a 141..194 band of
        # grey, so every depth video was one flat shape whatever its range (pass 49)
        scene.view_settings.view_transform = "Raw"
    for f in range(total):
        at(f, total)
        scene.render.filepath = os.path.join(d, "ctl_%02d.png" % f)
        bpy.ops.render.render(write_still=True)
    print("blender_beetle: rendered", view, total, "depth frames")
    scene.view_settings.view_transform = VIEW_TRANSFORM
json.dump({"mode": MODE, "depth": DEPTH_MODE, "amp": AMP, "action": ACT.name, "range": [F0, F1], "frames": N, "cycles": CYCLES, "total": total,
           "pitch": math.degrees(PITCH), "size": SIZE, "extent": EXTENT}, open(os.path.join(OUT, "meta.json"), "w"), indent=1)

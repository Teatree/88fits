"""Pose drivers for Wan Animate from Mixamo clips: one clean stride per view, at the exact frame count we want.

Stage 1 (inside Blender): read the armature of a Mixamo FBX, resample one full stride to N frames and write the
2D OpenPose keypoints for each of the game's five views (back, back-diagonal, side, front-diagonal, front, the
side and diagonals facing screen-right like the painted stills), seen from a camera a little above the figure.
Stage 2 (plain Python): draw those keypoints as OpenPose skeletons (coloured limbs on black), the format the
WanAnimateToVideo node expects, plus a contact sheet per view.

    "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/running.fbx out=tools/dl/drivers/run frames=24 pitch=25
    "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/pain_gesture.fbx out=tools/dl/drivers/hit frames=9 loop=0 start=0.2 end=1.0
    "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/walking.fbx out=tools/dl/drivers/walk_zombie frames=12 arms=zombie
    python tools/pose_driver.py draw tools/dl/drivers/run

Loops (loop=1, default): N frames of the whole action plus a repeat of the first, so Wan's 4k+1 length closes the loop.
arms=zombie (pass 33.4, the skeletons): both arms held straight out in front at shoulder height through the whole
stride, the upper and fore arms pinned by damped-track constraints to points ahead of the shoulders, the legs and the
torso left to the clip.
arms=hold_r (pass 48, the Vulture Raider): the right arm pinned holding something up at the shoulder (upper arm down, forearm
up), the left arm and the legs walking as the clip does.
One-shots (loop=0): N frames evenly from `start` to `end` seconds, N itself 4k+1.
body=<part:fraction,...> (pass 33.9, the goblin): retarget the stride to a creature's proportions. Wan Animate paints the
figure on the driver's bones, so a goblin walked on a man's skeleton came out with a small head and long legs. Each part is
read off the painting as a fraction of the figure's height (head top to soles): top_nose, nose_neck, torso (neck to the
middle of the hips), thigh, shin, shoulder (half the shoulder width), hip (half the hip width), upper (upper arm), fore
(forearm), hand (wrist to the middle fingertip). The rig's own fractions come from its rest pose; every frame is rebuilt
from the hips out with each bone scaled by the ratio, the head and its face points around the head's middle, and the
lowest ankle put back where the clip's lowest ankle was, so the feet stay planted.
    "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/orc_walk.fbx out=tools/dl/drivers/orc_walk_goblin frames=12 \
        body=top_nose:0.21,nose_neck:0.134,torso:0.292,thigh:0.16,shin:0.14,shoulder:0.119,hip:0.068,upper:0.174,fore:0.139,hand:0.078
glb=<file> rig=sm (pass 53, the mummy on Garry's "Zombie monster walk.glb"): a glTF clip instead of a Mixamo FBX. Its
bones are renamed to Mixamo's through the RIGS table (rig=sm is the Bone_SM_* skeleton that Cinema 4D exports; add a
table for another), a centimetre rig is scaled to metres, and start=/end= seconds pick the one stride to loop when the
clip holds more than one (they slice loops too since pass 53).
    "$BLENDER" -b --python tools/pose_driver.py -- glb="_REFERENCES/3d/Zombie monster walk.glb" rig=sm out=tools/dl/drivers/zombie_walk frames=12
fwd=body (pass 55, Solenne's walks): the character's forward is taken square to the hip and shoulder lines instead of
along the feet; a walk with the toes turned out had turned every view up to 20 degrees.
Pass 66 (the Level Editor's asset system, all additive):
  src=<file>        any of fbx, glb/gltf, dae, blend by its extension (fbx= and glb= still work)
  action=<name>     the clip to read when the file holds several (exact name, the part after the last "|", or a unique
                    piece of it); a clip the armature does not play yet is assigned to it
  rigmap=<json>     a bone-name map for a humanoid rig with its own names, merged over rig='s table: either
                    {"model_bone": "MixamoName"} or, as blender_ref.py's probe guesses it, {"MixamoName": "model_bone"}
  probe=1           print the armature's bone names, the clips and which of the 21 Mixamo names are still missing, then
                    stop (nothing written; out= not needed)
  meta.json gains kind: "pose" (plus src, action, rig, rigmap, arms) for the editor's driver library.
Pass 69 (Jezyk's three runs, all additive):
  amp=<f> [amp_bones=<regex>]  the limbs (Arm, ForeArm, UpLeg, Leg by default) swing f times as far round their average
                    rotation (written into the clip's keyframes): a sprint from the Running clip with amp=1.3
  lean=<deg>        the spine bent forward that many degrees in all (Spine, Spine1, Spine2 a third each)
  arms=back         both arms swept straight back behind the body, `arm_drop` (40) degrees below the horizontal: the dash
    "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/running.fbx out=tools/dl/drivers/run_sprint frames=24 amp=1.3 lean=12
    "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/running.fbx out=tools/dl/drivers/run_dash frames=24 arms=back lean=14
  then tools/pose_shoulders.py levels the shoulders (every Mixamo driver's neck sits above the shoulder line).
Output: <out>/<view>/poses.json, <out>/<view>/driver_NN.png, <out>/<view>_sheet.png, <out>/meta.json.
"""
import json
import math
import os
import sys

VIEWS = {"back": 0.0, "bd": 45.0, "side": 90.0, "fd": 135.0, "front": 180.0}   # forward yaw in screen space, 0 = into the screen
SIZE = 640
FILL = 0.72   # figure height as a fraction of the frame, like tools/animate._prep_still

# OpenPose body-18 order
KP = ["nose", "neck", "rsho", "relb", "rwri", "lsho", "lelb", "lwri", "rhip", "rknee", "rank", "lhip", "lknee", "lank", "reye", "leye", "rear", "lear"]
LIMBS = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13), (1, 0), (0, 14), (14, 16), (0, 15), (15, 17)]
COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0), (0, 255, 0), (0, 255, 85), (0, 255, 170),
          (0, 255, 255), (0, 170, 255), (0, 85, 255), (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255), (255, 0, 170), (255, 0, 85)]
# DWPose hand: wrist, then thumb, index, middle, ring, pinky, four joints each from the base to the tip
HAND_BONES = ["Hand"] + [f + str(k) for f in ("HandThumb", "HandIndex", "HandMiddle", "HandRing", "HandPinky") for k in (1, 2, 3, 4)]
HAND_EDGES = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (0, 9), (9, 10), (10, 11), (11, 12), (0, 13), (13, 14), (14, 15), (15, 16), (0, 17), (17, 18), (18, 19), (19, 20)]
# Other rigs' bone names -> Mixamo's (pass 53): the Bone_SM_* skeleton of "Zombie monster walk.glb" (Cinema 4D; its
# deform bones; the _guideBn_* and *Roll bones are left out, and its fingers have three joints, so no hands are drawn)
RIGS = {"sm": {"Bone_SM_Pelvis": "Hips", "Bone_SM_Spine1": "Spine", "Bone_SM_Spine2": "Spine1", "Bone_SM_Neck": "Neck",
               "Bone_SM_Head": "Head", "Bone_SM_Clavicle_L": "LeftShoulder", "Bone_SM_Clavicle_R": "RightShoulder",
               "Bone_SM_UpperArm_L": "LeftArm", "Bone_SM_ForeArm_L": "LeftForeArm", "Bone_SM_Hand_L": "LeftHand",
               "Bone_SM_UpperArm_R": "RightArm", "Bone_SM_ForeArm_R": "RightForeArm", "Bone_SM_Hand_R": "RightHand",
               "Bone_SM_Thigh_L": "LeftUpLeg", "Bone_SM_Calf_L": "LeftLeg", "Bone_SM_Ankle_L": "LeftFoot", "Bone_SM_Toes_L": "LeftToeBase",
               "Bone_SM_Thigh_R": "RightUpLeg", "Bone_SM_Calf_R": "RightLeg", "Bone_SM_Ankle_R": "RightFoot", "Bone_SM_Toes_R": "RightToeBase"}}
BONES = {"neck": "Neck", "rsho": "RightArm", "relb": "RightForeArm", "rwri": "RightHand", "lsho": "LeftArm", "lelb": "LeftForeArm",
         "lwri": "LeftHand", "rhip": "RightUpLeg", "rknee": "RightLeg", "rank": "RightFoot", "lhip": "LeftUpLeg", "lknee": "LeftLeg", "lank": "LeftFoot"}
# the Mixamo names the drivers read (the hands' 21 points are optional): what probe=1 reports as found or missing
MIXAMO_NAMES = ["Hips", "Spine", "Neck", "Head", "HeadTop_End",
                "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
                "RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
MIXAMO_NEEDED = ["Hips", "Neck", "Head", "LeftArm", "LeftForeArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot",
                 "RightArm", "RightForeArm", "RightHand", "RightUpLeg", "RightLeg", "RightFoot"]


def _args():
    out = {}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    for a in argv:
        if "=" in a:
            k, v = a.split("=", 1)
            out[k] = v
    return out


# ---------------------------------------------------------------- stage 1: Blender

def extract():
    import bpy
    from mathutils import Vector, Matrix
    a = _args()
    fbx = a.get("fbx") or a.get("glb") or a.get("src")
    if not fbx:
        raise SystemExit("pose_driver: fbx=, glb= or src=<file> is needed\n" + __doc__)
    out = a.get("out", "")
    n = int(a.get("frames", 24))
    loop = a.get("loop", "1") not in ("0", "false", "no")
    pitch = math.radians(float(a.get("pitch", 25.0)))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(fbx)[1].lower()
    if a.get("glb") or ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=fbx)
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=fbx)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=fbx)
    else:
        bpy.ops.import_scene.fbx(filepath=fbx)
    sc = bpy.context.scene
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not arms:
        raise SystemExit("pose_driver: no armature in " + fbx)
    arm = next((o for o in arms if o.animation_data and o.animation_data.action), arms[0])
    if arm.dimensions.z > 20.0:
        # a centimetre rig (the zombie GLB stands 180 units tall): every offset below is in metres
        arm.scale = (0.01, 0.01, 0.01)
        bpy.context.view_layer.update()
        print("pose_driver: a centimetre rig, scaled to metres")
    act = _pick_action(arm, a.get("action"))
    if act is None:
        raise SystemExit("pose_driver: no animation clip in %s; export it from Mixamo as FBX Binary, 30 fps, In Place, keyframe reduction none, or a GLB that carries its animation" % fbx)
    f0, f1 = act.frame_range
    fps = sc.render.fps
    if not loop or a.get("start") or a.get("end"):
        # a one-shot, or one stride out of a longer loop: the slice of the action between start and end seconds
        f0 = act.frame_range[0] + float(a.get("start", 0.0)) * fps
        f1 = min(act.frame_range[1], act.frame_range[0] + float(a.get("end", (act.frame_range[1] - act.frame_range[0]) / fps)) * fps)
    alias = dict(RIGS.get(a.get("rig", "mixamo"), {}))
    if a.get("rigmap"):
        alias.update(_load_rigmap(a["rigmap"]))
    pb = {alias.get(b.name, b.name.split(":")[-1]): b for b in arm.pose.bones}
    if a.get("probe") in ("1", "true", "yes"):
        _probe(arm, pb, fbx, fps)
        return
    if a.get("amp") and abs(float(a["amp"]) - 1.0) > 0.001:
        _bake_amp(arm, act, pb, float(a["amp"]), a.get("amp_bones", AMP_BONES))
    if not out:
        raise SystemExit("pose_driver: out=<folder> is needed")

    def joint(name, f):
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        return arm.matrix_world @ pb[name].head

    # the character's forward: the feet point forward (toe minus ankle), averaged over the stride
    fwd = Vector((0, 0, 0))
    for k in range(8):
        f = f0 + (f1 - f0) * k / 8.0
        for side in ("Left", "Right"):
            v = joint(side + "ToeBase", f) - joint(side + "Foot", f)
            v.z = 0.0
            fwd += v
    fwd.normalize()
    up = Vector((0, 0, 1))
    if a.get("fwd") == "body":
        # pass 55 (Solenne): forward square to the hips and shoulders instead of along the feet. A walk with the toes turned
        # out reads its forward off the feet up to 20 degrees wrong (Walking_sun: the side view showed her a quarter turned
        # away, so Wan painted her walking up the screen); the hip and shoulder lines, averaged over the stride, are square
        # to where the body goes
        lat = Vector((0, 0, 0))
        for k in range(16):
            f = f0 + (f1 - f0) * k / 16.0
            for l_b, r_b in (("LeftUpLeg", "RightUpLeg"), ("LeftArm", "RightArm")):
                v = joint(l_b, f) - joint(r_b, f)
                v.z = 0.0
                lat += v
        cand = up.cross(lat)
        cand = cand if cand.dot(fwd) > 0 else -cand
        cand.normalize()
        print("pose_driver: forward from the body %.1f deg (the feet said %.1f)" % (math.degrees(math.atan2(cand.y, cand.x)), math.degrees(math.atan2(fwd.y, fwd.x))))
        fwd = cand
    yaw0 = math.atan2(fwd.y, fwd.x)   # world yaw of "forward"
    if a.get("lean") and abs(float(a["lean"])) > 0.01:
        _bake_lean(arm, act, pb, float(a["lean"]), fwd, joint, f0)
    if a.get("arms") == "back":
        # pass 69 (Jezyk's dash): both arms swept straight back behind the body, angled `arm_drop` degrees (40 by default)
        # below the horizontal and a touch wide, the hands trailing at the hips (the "ninja run"); the legs and torso keep
        # the clip's stride
        side_v = fwd.cross(up)
        slope = math.tan(math.radians(float(a.get("arm_drop", 40.0))))
        for side, sgn in (("Right", 1.0), ("Left", -1.0)):
            sh = joint(side + "Arm", f0)
            for bone, reach, wide in ((side + "Arm", 0.6, 0.1), (side + "ForeArm", 1.3, 0.16)):
                e = bpy.data.objects.new("back_" + bone, None)
                sc.collection.objects.link(e)
                e.location = sh - fwd * reach - up * reach * slope + side_v * sgn * wide
                c = pb[bone].constraints.new("DAMPED_TRACK")
                c.target = e
                c.track_axis = "TRACK_Y"
        print("pose_driver: arms swept back")
    if a.get("arms") == "zombie":
        # the arms reach forward like a sleepwalker's: each upper arm and forearm tracks a point ahead of its shoulder
        # (a touch low and a touch wide), so the clip's arm swing is replaced and everything else is left alone
        # the arms slope down `arm_drop` degrees (18 by default): level arms seen from behind and above rose beside the
        # head like hands up; at 18 degrees the hands sit at the shoulders from behind and before the chest from the front
        side_v = fwd.cross(up)
        slope = math.tan(math.radians(float(a.get("arm_drop", 18.0))))
        for side, sgn in (("Right", 1.0), ("Left", -1.0)):
            sh = joint(side + "Arm", f0)
            for bone, reach, wide in ((side + "Arm", 0.6, 0.07), (side + "ForeArm", 1.3, 0.09)):
                drop = -reach * slope
                e = bpy.data.objects.new("zombie_" + bone, None)
                sc.collection.objects.link(e)
                e.location = sh + fwd * reach + up * drop + side_v * sgn * wide
                c = pb[bone].constraints.new("DAMPED_TRACK")
                c.target = e
                c.track_axis = "TRACK_Y"
        print("pose_driver: zombie arms")
    if a.get("arms") == "hold_r":
        # pass 48 (the Vulture Raider): the right hand holds a launcher up at the shoulder through the whole stride: the
        # upper arm hangs down and a little forward and out, the forearm points up and forward, so the hand sits in front of
        # the shoulder and the launcher it holds never swings; the left arm and the legs keep the clip's walk
        side_v = fwd.cross(up)
        sh = joint("RightArm", f0)
        el = sh + fwd * 0.1 - up * 0.26 + side_v * 0.1
        for bone, tgt in (("RightArm", el), ("RightForeArm", el + fwd * 0.16 + up * 0.3 - side_v * 0.04)):
            e = bpy.data.objects.new("hold_" + bone, None)
            sc.collection.objects.link(e)
            e.location = tgt
            c = pb[bone].constraints.new("DAMPED_TRACK")
            c.target = e
            c.track_axis = "TRACK_Y"
        print("pose_driver: right hand held up at the shoulder")
    def skeleton(f):
        """Every point the drivers draw at source frame f, in world space: the body joints, the head's base and top,
        and the 21 points of each hand (under "l:<bone>" / "r:<bone>")."""
        s = {key: joint(bone, f) for key, bone in BONES.items()}
        s["head"] = joint("Head", f)
        s["top"] = joint("HeadTop_End", f) if "HeadTop_End" in pb else joint("Head", f) + Vector((0, 0, 0.2))
        for side_name, tag in (("Left", "l"), ("Right", "r")):
            for bone in HAND_BONES:
                if side_name + bone in pb:
                    s[tag + ":" + bone] = joint(side_name + bone, f)
        return s

    # the retarget (body=...): bone scale factors from the painting's proportions over the rig's rest pose
    R = {}
    hd = 1.0
    if a.get("body"):
        want = {kv.split(":")[0]: float(kv.split(":")[1]) for kv in a["body"].split(",") if ":" in kv}
        rest = {alias.get(b.name, b.name.split(":")[-1]): arm.matrix_world @ b.head_local for b in arm.data.bones}
        rtop = rest["HeadTop_End"] if "HeadTop_End" in rest else rest["Head"] + Vector((0, 0, 0.2))
        rsole = min(rest.get("LeftToe_End", rest["LeftFoot"]).z, rest.get("RightToe_End", rest["RightFoot"]).z)
        H = rtop.z - rsole
        rcentre = (rest["Head"] + rtop) * 0.5
        rpel = (rest["LeftUpLeg"] + rest["RightUpLeg"]) * 0.5
        rig = {"top_nose": rtop.z - (rcentre.z - 0.01), "torso": (rest["Neck"] - rpel).length,
               "thigh": (rest["LeftLeg"] - rest["LeftUpLeg"]).length, "shin": (rest["LeftFoot"] - rest["LeftLeg"]).length,
               "shoulder": (rest["LeftArm"] - rest["RightArm"]).length * 0.5, "hip": (rest["LeftUpLeg"] - rest["RightUpLeg"]).length * 0.5,
               "upper": (rest["LeftForeArm"] - rest["LeftArm"]).length, "fore": (rest["LeftHand"] - rest["LeftForeArm"]).length,
               "hand": (rest.get("LeftHandMiddle4", rest["LeftHand"]) - rest["LeftHand"]).length}
        for part, frac in want.items():
            if part in rig and rig[part] > 1e-6:
                R[part] = frac * H / rig[part]
        # the head: its size from top_nose (the face points are offsets from the head's middle, scaled with it), then
        # the neck stretched so the nose sits nose_neck above the neck point
        hd = R.get("top_nose", 1.0)
        if "nose_neck" in want:
            rise = (rcentre - rest["Neck"]).z
            R["neck"] = (want["nose_neck"] * H + 0.01 * hd) / max(rise, 1e-6)
        print("pose_driver: retarget " + ", ".join("%s x%.2f" % (k, v) for k, v in sorted(R.items())))

    def retarget(s):
        if not R:
            return s
        o = dict(s)
        pel = (s["rhip"] + s["lhip"]) * 0.5
        o["neck"] = pel + (s["neck"] - pel) * R.get("torso", 1.0)
        for sd in "rl":
            o[sd + "hip"] = pel + (s[sd + "hip"] - pel) * R.get("hip", 1.0)
            o[sd + "knee"] = o[sd + "hip"] + (s[sd + "knee"] - s[sd + "hip"]) * R.get("thigh", 1.0)
            o[sd + "ank"] = o[sd + "knee"] + (s[sd + "ank"] - s[sd + "knee"]) * R.get("shin", 1.0)
            o[sd + "sho"] = o["neck"] + (s[sd + "sho"] - s["neck"]) * R.get("shoulder", 1.0)
            o[sd + "elb"] = o[sd + "sho"] + (s[sd + "elb"] - s[sd + "sho"]) * R.get("upper", 1.0)
            o[sd + "wri"] = o[sd + "elb"] + (s[sd + "wri"] - s[sd + "elb"]) * R.get("fore", 1.0)
            for bone in HAND_BONES:
                if sd + ":" + bone in s:
                    o[sd + ":" + bone] = o[sd + "wri"] + (s[sd + ":" + bone] - s[sd + "wri"]) * R.get("hand", 1.0)
        centre = (s["head"] + s["top"]) * 0.5
        c2 = o["neck"] + (centre - s["neck"]) * R.get("neck", 1.0)
        o["head"] = c2 + (s["head"] - centre) * hd
        o["top"] = c2 + (s["top"] - centre) * hd
        # the feet stay planted: the lowest ankle goes back to the height of the clip's lowest ankle
        dz = min(s["rank"].z, s["lank"].z) - min(o["rank"].z, o["lank"].z)
        lift = Vector((0.0, 0.0, dz))
        return {k: v + lift for k, v in o.items()}

    count = n + 1 if loop else n
    skel = []
    for k in range(count):
        f = f0 + (f1 - f0) * ((k % n) / n if loop else (k / max(n - 1, 1)))
        skel.append(retarget(skeleton(f)))
    # ground level and figure height, from the whole stride
    ground = min(min(s["rank"].z, s["lank"].z) for s in skel[:n])
    height = max(s["top"].z for s in skel[:n]) - ground
    print("pose_driver: forward yaw %.0f deg, figure %.2f m, stride %d source frames -> %d" % (math.degrees(yaw0), height, int(f1 - f0), n))
    for view, want_deg in VIEWS.items():
        # rotate the world so the character's forward points `want_deg` from "into the screen"; screen-right is +X
        # camera looks along +Y (into the screen), tilted down by `pitch`, at the figure's mid height
        # screen-right is +X and "into the screen" is +Y; a positive yaw about +Z turns +Y toward -X, so the wanted
        # turn toward screen-right is applied with the opposite sign
        want = math.radians(want_deg)
        rot = Matrix.Rotation(math.pi * 0.5 - want - yaw0, 4, "Z")
        cam_dir = Vector((0.0, math.cos(pitch), -math.sin(pitch)))    # into the screen and down
        cam_up = Vector((0.0, math.sin(pitch), math.cos(pitch)))
        cam_right = Vector((1.0, 0.0, 0.0))
        frames = []
        for k in range(count):
            s = skel[k]
            pts = {}
            for key in BONES:
                pts[key] = rot @ s[key]
            head = rot @ s["head"]
            top = rot @ s["top"]
            hfwd = rot @ Vector((fwd.x, fwd.y, 0.0))
            hright = hfwd.cross(up)   # the character's right
            centre = (head + top) * 0.5
            # the face points are offsets from the head's middle, scaled with the head (hd, 1 without a retarget)
            nose = centre + (hfwd * 0.09 - up * 0.01) * hd
            pts["nose"] = nose
            pts["reye"] = nose + (hright * 0.03 + up * 0.03 - hfwd * 0.02) * hd
            pts["leye"] = nose + (-hright * 0.03 + up * 0.03 - hfwd * 0.02) * hd
            pts["rear"] = centre + hright * 0.075 * hd
            pts["lear"] = centre - hright * 0.075 * hd
            facing = hfwd.dot(-cam_dir)   # > 0: face toward the camera
            vis = {k2: True for k2 in KP}
            vis["nose"] = vis["reye"] = vis["leye"] = facing > 0.15
            vis["rear"] = hright.dot(-cam_dir) > -0.25
            vis["lear"] = (-hright).dot(-cam_dir) > -0.25
            span = height / FILL   # orthographic: the frame spans height / FILL metres vertically

            def project(p):
                rel = p - Vector((0.0, 0.0, ground + height * 0.5))
                return round(0.5 + rel.dot(cam_right) / span, 4), round(0.5 - rel.dot(cam_up) / span + 0.04, 4)   # feet near the bottom like the stills

            row = []
            for key in KP:
                u, v = project(pts[key])
                row.append([u, v, 1 if vis[key] else 0])
            # hands: 21 points each, so the video model knows where every finger is
            hands = {}
            for tag in ("l", "r"):
                hands[tag] = [list(project(rot @ s[tag + ":" + bone])) if tag + ":" + bone in s else None for bone in HAND_BONES]
            frames.append({"body": row, "hands": hands})
        d = os.path.join(out, view)
        os.makedirs(d, exist_ok=True)
        json.dump({"view": view, "frames": frames, "size": SIZE, "fbx": os.path.basename(fbx), "n": n, "pitch": math.degrees(pitch)},
                  open(os.path.join(d, "poses.json"), "w"), indent=0)
        print("pose_driver: wrote", d, len(frames), "frames")
    json.dump({"kind": "pose", "fbx": os.path.basename(fbx), "src": os.path.basename(fbx), "action": act.name, "frames": n, "loop": loop,
               "pitch": math.degrees(pitch), "start": a.get("start"), "end": a.get("end"), "views": list(VIEWS),
               "body": a.get("body"), "fwd": a.get("fwd", "feet"), "arms": a.get("arms"), "rig": a.get("rig", "mixamo"), "rigmap": a.get("rigmap"),
               "amp": float(a["amp"]) if a.get("amp") else None, "lean": float(a["lean"]) if a.get("lean") else None,
               "retarget": {k: round(v, 3) for k, v in R.items()}, "notes": ""},
              open(os.path.join(out, "meta.json"), "w"), indent=1)


AMP_BONES = r"(Arm|ForeArm|UpLeg|Leg)$"


def _quat_curves(arm, act, bone_name):
    """The four rotation_quaternion F-curves of a pose bone in the action (Blender 4.4+ slotted actions included), or None."""
    path = 'pose.bones["%s"].rotation_quaternion' % bone_name
    curves = {}
    fcs = list(getattr(act, "fcurves", []) or [])
    if not fcs and hasattr(act, "layers"):
        for layer in act.layers:
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    fcs.extend(bag.fcurves)
    for fc in fcs:
        if fc.data_path == path:
            curves[fc.array_index] = fc
    return curves if len(curves) == 4 else None


def _rewrite_quats(curves, fn):
    """Every keyframe of the four curves read as one quaternion, passed through fn(frame, q) and written back."""
    from mathutils import Quaternion
    frames = sorted({round(kp.co[0], 3) for kp in curves[0].keyframe_points})
    qs = [Quaternion([curves[i].evaluate(f) for i in range(4)]) for f in frames]
    out = fn(frames, qs)
    for i in range(4):
        by_frame = {round(kp.co[0], 3): kp for kp in curves[i].keyframe_points}
        for f, q in zip(frames, out):
            kp = by_frame.get(f)
            if kp is not None:
                kp.co[1] = (q.w, q.x, q.y, q.z)[i]
                kp.handle_left[1] = kp.co[1]
                kp.handle_right[1] = kp.co[1]
        curves[i].update()


def _bake_amp(arm, act, pb, factor, pattern):
    """amp=<f> (pass 69, a sprint): each limb bone matching amp_bones swings `factor` times as far round its own average
    rotation over the clip (the axis kept), written into the action's keyframes, so the stance stays and only the swing
    grows (blender_depth_drivers.py's amp for the OpenPose drivers)."""
    import re
    from mathutils import Quaternion

    def amplify(frames, qs):
        acc = [0.0, 0.0, 0.0, 0.0]
        for q in qs:
            sgn = 1.0 if q.dot(qs[0]) >= 0.0 else -1.0
            for j, v in enumerate((q.w, q.x, q.y, q.z)):
                acc[j] += v * sgn
        mean = Quaternion(acc)
        mean.normalize()
        inv = mean.inverted()
        res = []
        for q in qs:
            axis, ang = (inv @ q).to_axis_angle()
            if ang > math.pi:
                ang -= 2.0 * math.pi
            res.append(mean @ Quaternion(axis, ang * factor))
        return res

    done = []
    for short, bone in pb.items():
        if re.search(pattern, short) and not short.endswith("Shoulder"):
            curves = _quat_curves(arm, act, bone.name)
            if curves:
                _rewrite_quats(curves, amplify)
                done.append(short)
    print("pose_driver: amp x%.2f on %s" % (factor, ", ".join(done) if done else "no bone (quaternion curves not found)"))


def _bake_lean(arm, act, pb, deg, fwd, joint, f0):
    """lean=<deg> (pass 69, a sprint): the spine bent forward `deg` degrees in all, a third at each of Spine, Spine1 and
    Spine2, written into the keyframes; the direction is checked against the character's forward (the head must move
    ahead) so a rig with the other axis convention leans the right way."""
    from mathutils import Quaternion
    names = [n for n in ("Spine", "Spine1", "Spine2") if n in pb] or ["Spine"]
    step = math.radians(deg) / len(names)
    head0 = joint("Head", f0)

    def tilt(sign):
        def fn(frames, qs):
            return [q @ Quaternion((1.0, 0.0, 0.0), sign * step) for q in qs]
        return fn

    for n in names:
        curves = _quat_curves(arm, act, pb[n].name)
        if curves:
            _rewrite_quats(curves, tilt(1.0))
    moved = (joint("Head", f0) - head0).dot(fwd)
    if moved < 0.0:
        # the other way round: undo twice over
        for n in names:
            curves = _quat_curves(arm, act, pb[n].name)
            if curves:
                _rewrite_quats(curves, tilt(-2.0))
        moved = (joint("Head", f0) - head0).dot(fwd)
    print("pose_driver: lean %.0f deg over %s (the head %.2f m ahead)" % (deg, ", ".join(names), moved))


def _pick_action(arm, name=None):
    """The armature's own clip, or action=<name> (exact, the part after the last '|', or a unique case-insensitive piece);
    a clip the armature does not play yet (a GLB's unassigned action) is assigned, with Blender 4.4+'s action slot."""
    import bpy
    acts = list(bpy.data.actions)
    if not acts:
        return None
    act = None
    if name:
        act = next((x for x in acts if x.name == name), None) or next((x for x in acts if x.name.split("|")[-1] == name), None)
        if act is None:
            low = [x for x in acts if name.lower() in x.name.lower()]
            if len(low) != 1:
                raise SystemExit("pose_driver: no action %r in %s" % (name, [x.name for x in acts]))
            act = low[0]
    elif arm.animation_data and arm.animation_data.action:
        return arm.animation_data.action
    else:
        act = acts[0]
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    ad = arm.animation_data
    if hasattr(ad, "action_slot") and getattr(act, "slots", None) and len(act.slots) > 0:
        try:
            ad.action_slot = act.slots[0]
        except Exception as e:
            print("pose_driver: action_slot not set (%s)" % e)
    return act


def _load_rigmap(path):
    """{model_bone: MixamoName}; a file written the other way round ({MixamoName: model_bone}, blender_ref's guess) is
    turned round, and empty rows are dropped."""
    m = json.load(open(path, encoding="utf-8"))
    rows = {str(k): str(v) for k, v in m.items() if k and v}
    known = set(MIXAMO_NAMES) | {"Spine1", "Spine2", "LeftToe_End", "RightToe_End"}
    if rows and sum(1 for k in rows if k in known) > sum(1 for v in rows.values() if v in known):
        rows = {v: k for k, v in rows.items()}
    print("pose_driver: rigmap %s: %d bones" % (os.path.basename(path), len(rows)))
    return rows


def _probe(arm, pb, fbx, fps):
    """probe=1: what the file holds, for the editor's bone-map form and clip pick (printed, nothing written)."""
    import bpy
    print("pose_driver: armature %s: %d bones" % (arm.name, len(arm.data.bones)))
    print("pose_driver: bones: " + ", ".join(b.name for b in arm.data.bones))
    for act in bpy.data.actions:
        f0, f1 = act.frame_range
        print("pose_driver: action %s: frames %.0f..%.0f (%.2f s at %d fps)" % (act.name, f0, f1, (f1 - f0) / float(fps), fps))
    found = [k for k in MIXAMO_NAMES if k in pb]
    missing = [k for k in MIXAMO_NEEDED if k not in pb]
    print("pose_driver: mixamo names found %d/%d: %s" % (len(found), len(MIXAMO_NAMES), ", ".join(found)))
    if missing:
        print("pose_driver: missing for a driver: " + ", ".join(missing) + " (map them with rigmap=<json>)")
    else:
        print("pose_driver: every bone a driver needs is there" + ("" if "HeadTop_End" in pb else " (no HeadTop_End: the head's top is guessed 20 cm up)"))
    hands = all(("Left" + h) in pb for h in HAND_BONES) and all(("Right" + h) in pb for h in HAND_BONES)
    print("pose_driver: hands: " + ("21-point hands will be drawn" if hands else "no full finger chains, so no hands are drawn"))


# ---------------------------------------------------------------- stage 2: draw

def _ellipse_poly(p0, p1, w):
    (x0, y0), (x1, y1) = p0, p1
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    L = math.hypot(x1 - x0, y1 - y0)
    ang = math.atan2(y1 - y0, x1 - x0)
    pts = []
    for k in range(24):
        t = 2 * math.pi * k / 24
        ex, ey = math.cos(t) * L / 2, math.sin(t) * w
        pts.append((mx + ex * math.cos(ang) - ey * math.sin(ang), my + ex * math.sin(ang) + ey * math.cos(ang)))
    return pts


def draw(folder):
    from PIL import Image, ImageDraw
    sheets = []
    for view in VIEWS:
        d = os.path.join(folder, view)
        meta = json.load(open(os.path.join(d, "poses.json")))
        size = meta["size"]
        w = max(2, int(size * 0.008))
        r = max(2, int(size * 0.008))
        imgs = []
        for k, fr in enumerate(meta["frames"]):
            row = fr["body"] if isinstance(fr, dict) else fr
            hands = fr.get("hands", {}) if isinstance(fr, dict) else {}
            img = Image.new("RGB", (size, size), (0, 0, 0))
            over = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            od = ImageDraw.Draw(over)
            pts = [(u * size, v * size, vis) for u, v, vis in row]
            for li, (a, b) in enumerate(LIMBS):
                if pts[a][2] and pts[b][2]:
                    od.polygon(_ellipse_poly(pts[a][:2], pts[b][:2], w), fill=COLORS[li] + (153,))
            img.paste(over, mask=over.getchannel("A"))
            dd = ImageDraw.Draw(img)
            for ji, (x, y, vis) in enumerate(pts):
                if vis:
                    dd.ellipse((x - r, y - r, x + r, y + r), fill=COLORS[ji])
            # hands in the DWPose style: thin rainbow edges, small blue joints
            import colorsys
            hw = max(1, int(size * 0.004))
            hr = max(1, int(size * 0.005))
            for tag in ("l", "r"):
                hp = hands.get(tag) or []
                if len(hp) < 21 or any(p is None for p in hp):
                    continue
                hxy = [(p[0] * size, p[1] * size) for p in hp]
                for ei, (a, b) in enumerate(HAND_EDGES):
                    col = tuple(int(c * 255) for c in colorsys.hsv_to_rgb(ei / float(len(HAND_EDGES)), 1.0, 1.0))
                    dd.line([hxy[a], hxy[b]], fill=col, width=hw)
                for (x, y) in hxy:
                    dd.ellipse((x - hr, y - hr, x + hr, y + hr), fill=(0, 0, 255))
            img.save(os.path.join(d, "driver_%02d.png" % k))
            imgs.append(img)
        cols = 13
        rows = (len(imgs) + cols - 1) // cols
        cell = 120
        sheet = Image.new("RGB", (cols * cell, rows * cell), (30, 30, 36))
        for i, im in enumerate(imgs):
            t = im.resize((cell, cell))
            sheet.paste(t, ((i % cols) * cell, (i // cols) * cell))
        sheet.save(os.path.join(folder, view + "_sheet.png"))
        sheets.append(sheet)
        print("pose_driver: drew", view, len(imgs), "frames")
    if sheets:
        from PIL import Image as I2
        big = I2.new("RGB", (max(s.width for s in sheets), sum(s.height for s in sheets)), (30, 30, 36))
        y = 0
        for s in sheets:
            big.paste(s, (0, y))
            y += s.height
        big.save(os.path.join(folder, "all_sheet.png"))


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
        extract()
    except ImportError:
        if len(sys.argv) >= 3 and sys.argv[1] == "draw":
            draw(sys.argv[2])
        else:
            print(__doc__)

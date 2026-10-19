"""Depth drivers from any rigged model's own clip (pass 66): tools/blender_beetle.py made generic, for the Level Editor's
"walked on a 3D model's own motion" method (gen_ctl.py reads the folder this writes).

    "$BLENDER" -b --python tools/blender_depth_drivers.py -- src=<file> out=tools/dl/drivers/<name> action=<name>
        mode=cycle|oneshot [frames=12] [cycles=2] [total=25] [start=<s>] [end=<s>] [depth=tight|wide] [amp=1.0]
        [amp_bones=<regex>] [pitch=25] [views=front,fd,side,bd,back] [forward=-Y|+Y|-X|+X|auto|yaw:<deg>]
        [screen=0,1,0] [albedo=<png>] [inplace=1] [scale=auto]

What it writes, blender_beetle.py's contract, so gen_ctl runs on it unchanged:
  <out>/<view>/ctl_NN.png   the depth video: near bright, far dark, the ground and the sky black (Cycles, 4 samples)
  <out>/<view>/clay.png     frame 0 as warm clay on the screen colour: what the side painting is redrawn from
  <out>/<view>/look.png     frame 0 in the model's own colours (its textures, or `albedo=`): a look reference
  <out>/<view>/clay_NN.png  oneshot only: clay at the quarter, half, three-quarter and last frame, to see the clip
  <out>/meta.json           {kind: "depth", mode, src, action, range, frames, cycles, total, views, loop, depth, amp, ...}

mode=cycle (a walk): the clip is read as one loop and resampled to `frames` poses, played `cycles` times plus one closing
frame (total = frames x cycles + 1: Wan's 4k+1 length, 25 for 12 x 2); root motion is taken back out per frame by the
body's box centre (inplace=1; inplace=0 keeps the travel). start=/end= in seconds slice one stride out of a longer clip.
mode=oneshot (a death, an attack): `total` frames evenly from the clip's first to last frame (or start..end), the front
view by default (a creature has one die set), the travel kept.

depth=tight (the default, pass 49's lesson): each view's own depth range, nearest vertex to farthest over the clip, is
mapped onto bright..dark, and the frames are written Raw (the default AgX view transform squeezed every depth video into
one flat grey shape, and Wan walked the far legs on nothing). depth=wide is one range for all views (the first beetle
run); both are written Raw.
amp=1.7 (pass 49): the bones matching `amp_bones` swing that much wider round their own average pose over the cycle (the
axis kept, the angle scaled), so a real creature's small step reads at sprite size; the default pattern matches leg
names (leg, thigh, calf, shin, foot, toe, tarsus, femur, tibia); the beetle's unnamed legs need amp_bones=^Bone\\.00[345].
forward= is the way the model faces (-Y for the beetle, the scorpion and Blender's convention); the cameras go round it:
front 0 (it walks at the viewer), fd 45, side 90 (it faces screen-right like the painted side views), bd 135, back 180,
pitch 25 from above, orthographic, three extents away, 1.45 extents wide (1.6 for a oneshot).
tips=1 (pass 93, mode gait / flip_curl): also writes <out>/tips.json, where every leg's foot (its mesh tip vertex) and its
last bone's tail fall in each view's pictures frame by frame ({legs, size, views: {view: [[[mx, my, bx, by] per leg] per
frame]]}}); tools/gait_check.py draws the foot paths and says which way each foot travels while it is down.
"""
import json
import math
import os
import re
import sys
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_ref as R  # noqa: E402
import blender_gait as G  # noqa: E402
try:
    import bpy
    from mathutils import Quaternion, Vector
except ImportError:  # importable outside Blender (the selftest); main() needs Blender
    bpy = None

LEG_WORDS = r"(?i)leg|thigh|calf|shin|foot|toe|tarsus|femur|tibia"


def main():
    A = R.args()
    if "src" not in A:
        raise SystemExit(__doc__)
    src = R.import_model(A["src"])
    sc = R.scene()
    factor = R.auto_scale(A.get("scale", "auto"))
    arm = R.main_armature()
    body = R.meshes()
    if arm is None:
        raise SystemExit("blender_depth_drivers: no armature in %s: a depth driver needs a rigged model with a clip" % src)
    if not body:
        raise SystemExit("blender_depth_drivers: no mesh in %s" % src)
    mode = A.get("mode", "cycle")
    if mode not in ("cycle", "oneshot", "gait", "flip_curl"):
        raise SystemExit("blender_depth_drivers: mode=%s is not cycle, oneshot, gait or flip_curl" % mode)
    proc = mode in ("gait", "flip_curl")   # pass 92: made here, no clip needed (tools/blender_gait.py)
    act = R.find_action(A.get("action"), arm) if R.all_actions() and (not proc or A.get("action")) else None
    if act is None and not proc:
        raise SystemExit("blender_depth_drivers: %s has no animation clip, so it cannot drive a walk (mode=gait makes a "
                         "walk for a legged model without one). %s" % (src, R.INSERT_HINT))
    if act is not None:
        R.use_action(arm, act)
    out = os.path.abspath(A.get("out", os.path.join(R.REPO, "tools", "dl", "drivers", os.path.splitext(os.path.basename(src))[0])))
    N = int(A.get("frames", 12))
    CYCLES = int(A.get("cycles", 2))
    total = N * CYCLES + 1 if mode in ("cycle", "gait") else int(A.get("total", 25))
    pitch = float(A.get("pitch", 25.0))
    size = 640
    screen = R.parse_rgb(A.get("screen"), (0.0, 1.0, 0.0))
    depth_mode = A.get("depth", "tight")
    amp = float(A.get("amp", "1.0"))
    amp_re = A.get("amp_bones", LEG_WORDS)
    inplace = A.get("inplace", "1" if mode == "cycle" else "0") not in ("0", "false", "no") and not proc
    views = A.get("views", "front,fd,side,bd,back" if mode in ("cycle", "gait") else "front").split(",")
    fps = sc.render.fps
    F0, F1 = (act.frame_range[0], act.frame_range[1]) if act is not None else (0.0, 1.0)
    f0, f1 = F0, F1
    if A.get("start") or A.get("end"):
        f0 = F0 + float(A.get("start", 0.0)) * fps
        f1 = min(F1, F0 + float(A.get("end", (F1 - F0) / float(fps))) * fps)
    if f1 - f0 < 1e-6:
        raise SystemExit("blender_depth_drivers: the slice %s..%s s is empty (the clip is %.2f s)" % (A.get("start"), A.get("end"), (F1 - F0) / fps))
    albedo = A.get("albedo") or (None if any(R.has_image_texture(o) for o in body) else R.find_albedo(src))
    root = arm
    while root.parent is not None:
        root = root.parent
    legs = None
    gopt = {}
    if proc:
        # the base pose: the rest pose, or the clip's pose at `base` seconds when an action is named (its stance)
        base = None
        if act is not None:
            R.set_frame(F0 + float(A.get("base", 0.0) or 0.0) * fps)
            base = {pb.name: (pb.location.copy(), (pb.rotation_quaternion.copy() if pb.rotation_mode == "QUATERNION"
                    else pb.rotation_euler.to_quaternion()), pb.scale.copy()) for pb in arm.pose.bones}
            arm.animation_data.action = None
        alias0 = R.bone_alias(arm)
        _l, _y, _b, fvec = R.forward_guess(arm, alias0)
        sopt = G.options(A, G.SCALE_DEFAULTS)
        legs = G.Legs(arm, body, root, R.forward_vector(A.get("forward", "-Y"), fvec), A.get("legs") or G.LEG_WORDS, base, sopt)
        gopt = G.options(A, G.GAIT_DEFAULTS if mode == "gait" else G.DEATH_DEFAULTS)
        gopt.update({k: v for k, v in sopt.items() if v not in (1.0, "")})
        print("blender_depth_drivers: %d legs: %s" % (len(legs.chains), ", ".join(legs.describe())))
        print("blender_depth_drivers: %s %s" % (mode, ", ".join("%s=%s" % kv for kv in sorted(gopt.items()))))
    # pass 93: tips=1 writes tips.json, where every leg's foot is in each view's picture frame by frame (the leg check)
    want_tips = legs is not None and str(A.get("tips", "0")) not in ("0", "", "false", "no")
    tip_verts = legs.tip_vertices(body) if want_tips else None
    tips = {}

    # ------------------------------------------------------------ time
    POSE = [None]   # amp: the cycle's N poses with the matching bones' swing scaled, {bone: (location, rotation, scale)}

    def set_time(frame):
        if POSE[0] is not None:
            k = int(round((frame - f0) / (f1 - f0) * N)) % N
            for pb in arm.pose.bones:
                loc, q, s = POSE[0][k][pb.name]
                pb.location = loc
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = q
                pb.scale = s
            R.update()
            return
        R.set_frame(frame)

    def rot_q(pb):
        """The bone's rotation as a quaternion whatever mode its curves drive (an Euler rig keeps its animation)."""
        if pb.rotation_mode == "QUATERNION":
            return pb.rotation_quaternion.copy()
        if pb.rotation_mode == "AXIS_ANGLE":
            aa = pb.rotation_axis_angle
            return Quaternion((aa[1], aa[2], aa[3]), aa[0])
        return pb.rotation_euler.to_quaternion()

    def sample_pose():
        rows = []
        for k in range(N):
            R.set_frame(f0 + (f1 - f0) * k / float(N))
            rows.append({pb.name: (pb.location.copy(), rot_q(pb), pb.scale.copy()) for pb in arm.pose.bones})
        return rows

    def amplify(rows, factor_, pattern):
        """Each matching bone's rotation away from its own average over the cycle, the angle times `factor_` (the axis
        kept): the stance stays the clip's and only the swing grows."""
        out_rows = [dict(r) for r in rows]
        matched = 0
        for name in rows[0].keys():
            if not re.search(pattern, name):
                continue
            matched += 1
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
                loc, _q, s = out_rows[k][name]
                out_rows[k][name] = (loc, mean @ Quaternion(axis, ang * factor_), s)
        return out_rows, matched

    amp_matched = 0
    if mode == "cycle" and abs(amp - 1.0) > 0.001:
        rows, amp_matched = amplify(sample_pose(), amp, amp_re)
        if amp_matched == 0:
            print("blender_depth_drivers: amp=%g but no bone matches amp_bones=%r; the bones are: %s" % (amp, amp_re, ", ".join(b.name for b in arm.data.bones)))
        else:
            POSE[0] = rows
            arm.animation_data.action = None
            print("blender_depth_drivers: %d bones swung %.2fx" % (amp_matched, amp))

    if not proc:
        root.location = Vector((0, 0, 0))
        set_time(f0)
    mn0, mx0 = R.bbox(body)
    C0 = (mn0 + mx0) * 0.5

    def at(f):
        if proc:
            if mode == "gait":
                legs.pose_gait((f % N) / float(N), gopt)
            else:
                legs.pose_flip_curl(float(gopt["seconds"]) * f / float(max(total - 1, 1)), gopt)
            return
        root.location = Vector((0, 0, 0))
        if mode == "oneshot":
            set_time(f0 + (f1 - f0) * f / float(max(total - 1, 1)))
        else:
            set_time(f0 + (f1 - f0) * ((f % N) / float(N)))
        if not inplace:
            return
        mn, mx = R.bbox(body)
        c = (mn + mx) * 0.5
        # kept on the spot horizontally; the height keeps the clip's own bob
        root.location = Vector((C0.x - c.x, C0.y - c.y, 0.0))
        R.update()

    # ------------------------------------------------------------ camera: the frame the creature needs from every side over the clip
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for k in range(9):
        at(int(round((total - 1) * k / 8.0)))
        a, b = R.bbox(body)
        mn = Vector((min(mn.x, a.x), min(mn.y, a.y), min(mn.z, a.z)))
        mx = Vector((max(mx.x, b.x), max(mx.y, b.y), max(mx.z, b.z)))
    target, extent, dist, ortho = R.camera_rule(mn, mx, death=(mode in ("oneshot", "flip_curl")))
    alias = R.bone_alias(arm)
    _label, _yaw, _basis, fwd_vec = R.forward_guess(arm, alias)
    fwd = R.forward_vector(A.get("forward", "-Y"), fwd_vec)
    cam = R.make_camera(size)

    # ------------------------------------------------------------ materials
    def depth_material():
        """Near bright, far dark: an emission of the camera distance mapped over the creature's depth range."""
        m = bpy.data.materials.new("depth")
        nt = R._nodes(m)
        nt.nodes.clear()
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        em = nt.nodes.new("ShaderNodeEmission")
        camd = nt.nodes.new("ShaderNodeCameraData")
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = dist - extent * 0.55
        mr.inputs["From Max"].default_value = dist + extent * 0.55
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.08
        mr.name = "range"
        nt.links.new(camd.outputs["View Z Depth"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], o.inputs["Surface"])
        return m

    def view_depths():
        """The nearest and farthest the creature comes along the camera's axis over the clip (depth=tight)."""
        import numpy as np
        R.update()
        f = cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))
        fa = np.array([f.x, f.y, f.z])
        near, far = 1e9, -1e9
        for k in range(9):
            at(int(round((total - 1) * k / 8.0)))
            w = R.verts_world(body)
            d = (w - np.array(cam.location)) @ fa
            near = min(near, float(d.min()))
            far = max(far, float(d.max()))
        return near, far

    def set_depth_range(m, near, far):
        mr = m.node_tree.nodes["range"]
        pad = (far - near) * 0.03
        mr.inputs["From Min"].default_value = near - pad
        mr.inputs["From Max"].default_value = far + pad
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.16

    backup = R.materials_backup(body)
    clay = R.clay_material()
    look = R.look_material(albedo) if albedo else None
    depth = depth_material()
    has_tex = any(R.has_image_texture(o) for o in body)
    R.black_world()
    view_transform = sc.view_settings.view_transform
    os.makedirs(out, exist_ok=True)

    def looks():
        if look is not None:
            R.set_material(body, look)
            R.workbench("TEXTURE", screen)
        else:
            R.restore_materials(backup)
            R.workbench("TEXTURE" if has_tex else "MATERIAL", screen)

    ranges = {}
    for view in views:
        if view not in R.VIEWS:
            raise SystemExit("blender_depth_drivers: view %r is not one of %s" % (view, ", ".join(R.VIEWS)))
        d = os.path.join(out, view)
        os.makedirs(d, exist_ok=True)
        R.place_camera(cam, target, dist, fwd, R.VIEWS[view], pitch, ortho)
        at(0)
        # clay first, so a bad framing shows before the depth frames
        R.set_material(body, clay)
        R.workbench("MATERIAL", screen)
        R.render(os.path.join(d, "clay.png"))
        looks()
        R.render(os.path.join(d, "look.png"))
        if mode in ("oneshot", "flip_curl"):
            R.set_material(body, clay)
            R.workbench("MATERIAL", screen)
            for f in sorted({total // 4, total // 2, (3 * total) // 4, total - 1}):
                at(f)
                R.render(os.path.join(d, "clay_%02d.png" % f))
        # depth: every frame of the clip, written Raw (AgX squeezed the emission into a flat grey band, pass 49)
        sc.render.engine = "CYCLES"
        sc.cycles.samples = 4
        sc.cycles.use_denoising = False
        sc.render.film_transparent = False
        sc.render.image_settings.color_mode = "RGB"
        R.set_material(body, depth)
        if depth_mode == "tight":
            near, far = view_depths()
            set_depth_range(depth, near, far)
            ranges[view] = [round(near, 3), round(far, 3)]
            print("blender_depth_drivers: %s depth %.2f..%.2f" % (view, near, far))
        else:
            mr = depth.node_tree.nodes["range"]
            mr.inputs["From Min"].default_value = dist - extent * 0.55
            mr.inputs["From Max"].default_value = dist + extent * 0.55
            mr.inputs["To Min"].default_value = 1.0
            mr.inputs["To Max"].default_value = 0.08
        sc.view_settings.view_transform = "Raw"
        for f in range(total):
            at(f)
            R.render(os.path.join(d, "ctl_%02d.png" % f))
            if want_tips:
                from bpy_extras.object_utils import world_to_camera_view
                row = []
                for mesh_w, bone_w in legs.tips_world(body, tip_verts):
                    pm = world_to_camera_view(sc, cam, mesh_w)
                    pb_ = world_to_camera_view(sc, cam, bone_w)
                    row.append([round(pm.x * size, 1), round((1.0 - pm.y) * size, 1), round(pb_.x * size, 1), round((1.0 - pb_.y) * size, 1)])
                tips.setdefault(view, []).append(row)
        print("blender_depth_drivers: rendered %s %d depth frames" % (view, total))
        sc.view_settings.view_transform = view_transform
    R.restore_materials(backup)
    meta = {"kind": "depth", "mode": mode, "loop": mode == "cycle", "src": os.path.relpath(src, R.REPO).replace("\\", "/"),
            "action": act.name if act is not None else None, "range": [f0, f1], "clip_range": [F0, F1], "start": A.get("start"), "end": A.get("end"), "fps": fps,
            "frames": N, "cycles": CYCLES, "total": total, "views": views, "depth": depth_mode, "depth_ranges": ranges,
            "amp": amp, "amp_bones": amp_re if abs(amp - 1.0) > 0.001 else None, "amp_matched": amp_matched,
            "pitch": pitch, "size": size, "extent": extent, "forward": A.get("forward", "-Y"), "inplace": inplace,
            "albedo": os.path.relpath(albedo, R.REPO).replace("\\", "/") if albedo else None, "scale_applied": factor,
            "notes": "", "legs": legs.describe() if legs else None,
            ("gait" if mode == "gait" else "death"): gopt if proc else None}
    json.dump(meta, open(os.path.join(out, "meta.json"), "w", encoding="utf-8", newline="\n"), indent=1)
    if want_tips:
        json.dump({"legs": legs.describe(), "size": size, "cols": "mesh_x, mesh_y, bone_x, bone_y (pixels)", "views": tips},
                  open(os.path.join(out, "tips.json"), "w", encoding="utf-8", newline="\n"))
    print("blender_depth_drivers: done ->", out)


if __name__ == "__main__":
    main()

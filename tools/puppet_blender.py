"""The Puppet trial's Blender half (tools/puppet.py runs it): clean the Hunyuan3D mesh, rig it with Mixamo's bone names,
retarget the Mixamo run onto it, colour it from the paintings, export the GLB, and draw OpenPose guides from her own
bones with the joints her own body hides dropped.

    "$BLENDER" -b --factory-startup --python tools/puppet_blender.py -- mode=clean src=<raw.glb> out=<shape.glb> preview=<png> height=1.58 [faces=60000] [turn=0] [only_preview=1]
    "$BLENDER" -b --factory-startup --python tools/puppet_blender.py -- mode=rig src=<shape.glb> out=<may_puppet.blend> overlay=<dir>
    "$BLENDER" -b --factory-startup --python tools/puppet_blender.py -- mode=anim src=<may_puppet.blend | mixamo.fbx> clip=tools/dl/mixamo/running.fbx paint=<dir> out=<may_puppet.glb> renders=<dir> [save=<blend>]
    "$BLENDER" -b --factory-startup --python tools/puppet_blender.py -- mode=guides src=<may_puppet.blend> out=tools/dl/drivers/may_puppet_run [frames=24] [pitch=25] [action=run]

Conventions: the figure stands on z = 0, faces -Y (Blender's front), metres; her left is +X. The armature "May_Rig"
(object at the origin, no rotation or scale) carries Mixamo's names with the "mixamorig:" prefix, so a Mixamo FBX
matches bone for bone and tools/pose_driver.py reads it (it strips the prefix); the mesh is "May".

Pass 71 (lane PLE, any hero): name=<Name> names the mesh and the armature (<Name>, <Name>_Rig; puppet.py passes the hero
id in letters: "May", "Buck"); mode=anim takes idle=<fbx> (a Mixamo idle retargeted like the run; without it the
procedural breathing idle); mode=guides takes frame=soles|ankles (the stride's ground at the lowest sole of the posed mesh,
so the boots stay inside the canvas, or at the ankles as pose_driver does), face=nose|head (the ears' middle from the
measured nose, keeping a side view in profile; or on the head bone's axis, the trial's first guide) and writes frame,
face, clip and glb into meta.json.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import blender_ref as R  # noqa: E402

P = "mixamorig:"
MESH_NAME = "May"
RIG_NAME = "May_Rig"
FINGERS = ("Thumb", "Index", "Middle", "Ring", "Pinky")


def A():
    return R.args()


def set_names():
    """name=<Name> (pass 71): the mesh and the armature named for the hero; May's names are the default."""
    global MESH_NAME, RIG_NAME
    nm = str(A().get("name") or "").strip()
    if nm:
        MESH_NAME, RIG_NAME = nm, nm + "_Rig"


def log(*a):
    print("puppet_blender:", *a, flush=True)


def fail(msg):
    print("puppet_blender: FAILED " + msg, flush=True)
    raise SystemExit(1)


# ---------------------------------------------------------------- mesh helpers

def mesh_np(obj, world=True, dg=None):
    import numpy as np
    if dg is not None:
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
    else:
        me = obj.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    if world:
        mw = np.array(obj.matrix_world)
        co = co @ mw[:3, :3].T + mw[:3, 3]
    if dg is not None:
        obj.evaluated_get(dg).to_mesh_clear()
    return co


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def apply_all(obj):
    select_only([obj])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def clean():
    a = A()
    src, out = a["src"], a.get("out")
    R.import_model(src)
    ms = R.meshes()
    if not ms:
        fail("no mesh in %s" % src)
    for o in R.roots():
        if o.type != "MESH":
            o.matrix_world = o.matrix_world  # keep
    select_only(ms)
    if len(ms) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # unparent (the glTF importer may put the mesh under an empty)
    mw = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = mw
    apply_all(obj)
    for o in list(bpy.data.objects):
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.name = MESH_NAME
    obj.data.name = MESH_NAME
    import numpy as np
    co = mesh_np(obj)
    ext = co.max(axis=0) - co.min(axis=0)
    log("raw mesh: %d verts, %d faces, extent %s" % (len(obj.data.vertices), len(obj.data.polygons), np.round(ext, 3).tolist()))
    # up: the longest axis is her height
    up = int(np.argmax(ext))
    if up != 2:
        rot = Matrix.Rotation(math.radians(-90 if up == 1 else 90), 4, "X" if up == 1 else "Y")
        obj.matrix_world = rot @ obj.matrix_world
        apply_all(obj)
        log("turned the long axis %d up" % up)
    turn = float(a.get("turn", 0))
    if abs(turn) > 1e-6:
        obj.matrix_world = Matrix.Rotation(math.radians(turn), 4, "Z") @ obj.matrix_world
        apply_all(obj)
    if a.get("flip") in ("1", "true"):
        obj.matrix_world = Matrix.Rotation(math.pi, 4, "X") @ obj.matrix_world
        apply_all(obj)
    # the biggest piece only (plus pieces over 2 % of it: the beret's tip may float)
    keep_main_pieces(obj, 0.02)
    # metres: her game height; feet on z = 0, centred on x/y
    co = mesh_np(obj)
    h = co[:, 2].max() - co[:, 2].min()
    s = float(a.get("height", 1.6)) / max(h, 1e-6)
    obj.scale = (s, s, s)
    apply_all(obj)
    co = mesh_np(obj)
    c = (co.min(axis=0) + co.max(axis=0)) * 0.5
    obj.location = (-c[0], -c[1], -co[:, 2].min())
    apply_all(obj)
    if a.get("only_preview") not in ("1", "true"):
        remesh_decimate(obj, float(a.get("voxel", 0.0045)), int(a.get("faces", 60000)))
        select_only([obj])
        bpy.ops.object.shade_smooth()
    co = mesh_np(obj)
    log("clean mesh: %d verts, %d faces, height %.3f m, width %.3f, depth %.3f" % (
        len(obj.data.vertices), len(obj.data.polygons), np.ptp(co[:, 2]), np.ptp(co[:, 0]), np.ptp(co[:, 1])))
    if a.get("preview"):
        turntable([obj], a["preview"], views=("front", "fd", "side", "bd", "back", "left"))
    if out and a.get("only_preview") not in ("1", "true"):
        select_only([obj])
        bpy.ops.export_scene.gltf(filepath=os.path.abspath(out), export_format="GLB", use_selection=True, export_animations=False,
                                  export_materials="NONE")
        log("wrote %s" % out)


def keep_main_pieces(obj, frac):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    parts = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        comp = []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        parts.append(comp)
    parts.sort(key=len, reverse=True)
    big = len(parts[0])
    drop = [v for p in parts if len(p) < big * frac for v in p]
    log("pieces: %d (largest %d verts); dropped %d small pieces (%d verts)" % (len(parts), big, sum(1 for p in parts if len(p) < big * frac), len(drop)))
    if drop:
        bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def remesh_decimate(obj, voxel, faces):
    select_only([obj])
    m = obj.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.adaptivity = 0.0
    m.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=m.name)
    keep_main_pieces(obj, 0.02)
    n = len(obj.data.polygons)
    if n > faces:
        d = obj.modifiers.new("decimate", "DECIMATE")
        d.ratio = faces / float(n)
        bpy.ops.object.modifier_apply(modifier=d.name)
    log("remeshed at %.4f m and decimated: %d -> %d faces" % (voxel, n, len(obj.data.polygons)))


# ---------------------------------------------------------------- renders

def view_dir(view):
    """From the figure toward the camera, horizontal: front 0 (her face, -Y), side 90 (her right, she faces screen-right),
    back 180, left = 270 (her left side, facing screen-left)."""
    yaw = {"front": 0.0, "fd": 45.0, "side": 90.0, "bd": 135.0, "back": 180.0, "left": 270.0}[view]
    return R.bearing(Vector((0, -1, 0)), yaw)


def make_cam(size=640):
    cam = R.make_camera(size)
    return cam


def place(cam, objs, view, pitch=0.0, margin=1.08, target=None, span=None):
    """An orthographic camera on `view`, `pitch` degrees above, framed on the objects (or on target/span)."""
    import numpy as np
    co = np.concatenate([mesh_np(o, dg=bpy.context.evaluated_depsgraph_get()) for o in objs])
    mn, mx = co.min(axis=0), co.max(axis=0)
    t = Vector(target) if target is not None else Vector(((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2))
    ext = float(max(mx - mn))
    d = view_dir(view)
    p = math.radians(pitch)
    cam.location = t + d * ext * 3 * math.cos(p) + Vector((0, 0, ext * 3 * math.sin(p)))
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (t - cam.location).to_track_quat("-Z", "Y")
    cam.data.ortho_scale = span if span else ext * margin
    cam.data.clip_start = 0.01
    cam.data.clip_end = ext * 10
    R.update()


def turntable(objs, path, views=("front", "fd", "side", "bd", "back"), size=512, color="MATERIAL", pitch=8.0):
    """One PNG per view in <path stem>_<view>.png and a row of them in `path`."""
    stem = os.path.splitext(path)[0]
    cam = make_cam(size)
    R.workbench(color, (0.16, 0.17, 0.2))
    sc = bpy.context.scene
    sc.display.shading.light = "STUDIO"
    paths = []
    for v in views:
        place(cam, objs, v, pitch)
        f = "%s_%s.png" % (stem, v)
        R.render(f)
        paths.append(f)
    R.contact_sheet(paths, path, cell=size // 2 if size > 300 else size)
    bpy.data.objects.remove(cam, do_unlink=True)
    log("preview %s" % path)
    return paths


# ---------------------------------------------------------------- rig

BONE_PARENT = {
    "Hips": None, "Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1", "Neck": "Spine2", "Head": "Neck", "HeadTop_End": "Head",
    "LeftShoulder": "Spine2", "LeftArm": "LeftShoulder", "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
    "RightShoulder": "Spine2", "RightArm": "RightShoulder", "RightForeArm": "RightArm", "RightHand": "RightForeArm",
    "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot", "LeftToe_End": "LeftToeBase",
    "RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot", "RightToe_End": "RightToeBase",
}
# the bone's tail is this joint (the chains are connected); an end bone gets a short tail along its parent's direction
BONE_TAIL = {
    "Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head", "Head": "HeadTop_End",
    "LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandTip",
    "RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "RightHandTip",
    "LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase", "LeftToeBase": "LeftToe_End",
    "RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase", "RightToeBase": "RightToe_End",
}
NON_DEFORM = {"HeadTop_End", "LeftToe_End", "RightToe_End"}


EDGES = {"e": None}


def set_edges(obj):
    """The mesh's edges as an (n, 2) index array, for the exact cross-sections slab_clusters cuts."""
    import numpy as np
    e = np.empty(len(obj.data.edges) * 2, dtype=np.int64)
    obj.data.edges.foreach_get("vertices", e)
    EDGES["e"] = e.reshape(-1, 2)


def section(co, z):
    """The points where the mesh's edges cross the plane at height z (the exact outline of the cross-section)."""
    import numpy as np
    e = EDGES["e"]
    z0, z1 = co[e[:, 0], 2], co[e[:, 1], 2]
    m = (z0 - z) * (z1 - z) <= 0.0
    m &= np.abs(z1 - z0) > 1e-9
    a, b = co[e[m, 0]], co[e[m, 1]]
    t = ((z - a[:, 2]) / (b[:, 2] - a[:, 2]))[:, None]
    return a + (b - a) * t


def slab_clusters(co, z, half=0.004, gap=0.012, xlim=None):
    """The cross-section of the mesh at height z (edge crossings; a vertex slab when no edges are set), split into runs
    along x wherever the gap is over `gap` m: [(xmin, xmax, ymin, ymax, n)] left to right."""
    import numpy as np
    if EDGES["e"] is not None:
        pts = section(co, z)
    else:
        pts = co[np.abs(co[:, 2] - z) < half]
    if xlim is not None:
        pts = pts[np.abs(pts[:, 0]) < xlim]
    if len(pts) == 0:
        return []
    pts = pts[np.argsort(pts[:, 0])]
    cuts = np.nonzero(np.diff(pts[:, 0]) > gap)[0] + 1
    out = []
    for part in np.split(pts, cuts):
        if len(part) < 3:
            continue
        out.append((float(part[:, 0].min()), float(part[:, 0].max()), float(part[:, 1].min()), float(part[:, 1].max()), len(part)))
    return out


def find_joints(obj):
    """Every joint of a Mixamo-named skeleton from an A-posed mesh (z up, facing -Y, her left +X, feet on 0): the arms
    from the slabs where they stand apart from the torso, the legs from the slabs below the crotch, the spine, neck and
    head from the torso's middle; proportions where the shape cannot say. Returns ({name: Vector}, notes)."""
    import numpy as np
    co = mesh_np(obj)
    set_edges(obj)
    H = float(co[:, 2].max())
    zs = np.arange(0.02 * H, 0.97 * H, 0.004 * H)
    rows = {float(z): slab_clusters(co, float(z)) for z in zs}
    notes = {"height": H}
    # ---- the arms: rows where the outermost runs stand apart from a middle run that holds x = 0
    arm_rows = []
    for z, cl in rows.items():
        if len(cl) < 3:
            continue
        mid = [c for c in cl if c[0] <= 0.0 <= c[1]]
        if not mid:
            continue
        mid = mid[0]
        left = [c for c in cl if c[0] > mid[1]]
        right = [c for c in cl if c[1] < mid[0]]
        if left and right:
            arm_rows.append((z, mid, left[-1], right[0]))
    if not arm_rows:
        fail("no rows with both arms apart from the body: is the mesh in an A-pose?")
    # the armpit: the top of the longest unbroken stack of arm rows
    arm_rows.sort(key=lambda r: r[0])
    step = 0.004 * H * 1.5
    runs, cur = [], [arm_rows[0]]
    for r in arm_rows[1:]:
        if r[0] - cur[-1][0] <= step:
            cur.append(r)
        else:
            runs.append(cur)
            cur = [r]
    runs.append(cur)
    best = max(runs, key=len)
    notes["arm_rows"] = [round(best[0][0], 4), round(best[-1][0], 4)]

    def mid_width(z):
        """The middle of the body at height z: every run that reaches into the centre band (a cleavage or a spine groove
        may split it) merged into one."""
        cl = [c for c in slab_clusters(co, float(z)) if c[0] < 0.03 * H and c[1] > -0.03 * H]
        if not cl:
            return None, None
        m = (min(c[0] for c in cl), max(c[1] for c in cl), min(c[2] for c in cl), max(c[3] for c in cl), sum(c[4] for c in cl))
        return m[1] - m[0], m
    # ---- the neck first: the narrowest middle run between 62 % and 90 % of her height (the scarf; below it the
    # shoulders and the arms that hug the bust, above it the bob)
    best_w, neck_mid = 1e9, 0.78 * H
    for z in np.arange(0.62 * H, 0.9 * H, 0.002 * H):
        w, _ = mid_width(z)
        if w is not None and w < best_w:
            best_w, neck_mid = w, float(z)
    notes["neck_mid_z"] = neck_mid
    notes["neck_width"] = best_w
    # the top of the shoulders: going down from the neck, the first slab 1.6 times as wide as the neck
    sh_top = neck_mid - 0.04 * H
    for z in np.arange(neck_mid, neck_mid - 0.15 * H, -0.002 * H):
        w, _ = mid_width(z)
        if w is not None and w > 1.6 * best_w:
            sh_top = float(z)
            break
    notes["shoulder_top_z"] = sh_top
    J = {}
    for side, idx, sgn in (("Left", 2, 1.0), ("Right", 3, -1.0)):
        # the arm's centre line where it stands apart from the body (forearm, lower upper arm)
        pts = []
        for r in best:
            c = r[idx]
            m = (np.abs(co[:, 2] - r[0]) < 0.004) & (co[:, 0] >= c[0] - 1e-6) & (co[:, 0] <= c[1] + 1e-6)
            if m.any():
                pts.append(co[m].mean(axis=0))
        pts = np.array(pts)
        widths = np.array([r[idx][1] - r[idx][0] for r in best])
        c0 = pts.mean(axis=0)
        u = np.linalg.svd(pts - c0)[2][0]
        if u[2] > 0:
            u = -u
        # the arm's radius from a slanted slab's width (a slab through a cylinder tilted by t is 2r / cos(t) wide)
        r_arm = float(np.median(widths)) * 0.5 * abs(u[2])
        # the hand's tip: the arm's vertices beyond the torso's edge, from the separated rows down a little past them
        # (the hand hangs past the hips, where the legs part and the rows stop counting); never the boots
        torso_half = (best[0][1][1] - best[0][1][0]) * 0.5
        arm_mask = (co[:, 0] * sgn > torso_half + 0.01) & (co[:, 2] < best[-1][0]) & (co[:, 2] > best[0][0] - 0.12 * H)
        av = co[arm_mask]
        tip = av[np.argmax((av - c0) @ u)]
        t_tip = float((tip - c0) @ u)
        wrist = c0 + u * (t_tip - float(A().get("hand_len", 0.095)) * H)
        # the shoulder joint: an arm's radius under the top of the shoulder, an arm's radius in from the body's outer edge
        # there (the upper arm lies against the bust, so the middle run at that height holds it)
        sz = sh_top - max(r_arm, 0.018 * H)
        _, cl = mid_width(sz)
        edge = (cl[1] if sgn > 0 else cl[0]) if cl else sgn * 0.09 * H
        sx = edge - sgn * max(r_arm, 0.018 * H) * 1.1
        ycol = co[(np.abs(co[:, 2] - sz) < 0.006 * H) & (np.abs(co[:, 0] - sx) < 0.01 * H)]
        sy = float((ycol[:, 1].min() + ycol[:, 1].max()) * 0.5) if len(ycol) else float(c0[1])
        sh = np.array([sx, sy, sz])
        # the elbow: on the separated centre line where it is about half way from the shoulder to the wrist (the line
        # itself where the rows reach high enough, else the straight line from the shoulder to the wrist)
        ez = sz + 0.5 * (wrist[2] - sz)
        if best[0][0] <= ez <= best[-1][0]:
            k = int(np.argmin(np.abs(np.array([r[0] for r in best]) - ez)))
            elbow = pts[k]
        else:
            elbow = sh + (wrist - sh) * 0.5
        J[side + "Arm"] = Vector(sh.tolist())
        J[side + "ForeArm"] = Vector(elbow.tolist()) + Vector((0, 0.008, 0))   # a hint of bend backward at the elbow
        J[side + "Hand"] = Vector(wrist.tolist())
        J[side + "HandTip"] = Vector(tip.tolist())
        notes[side + "_arm"] = {"radius": round(r_arm, 4), "upper": round(float(np.linalg.norm(elbow - sh)), 4),
                                "fore": round(float(np.linalg.norm(wrist - elbow)), 4), "hand": round(float(np.linalg.norm(tip - wrist)), 4)}
    # ---- the legs: central runs below the crotch

    def central(cl):
        return [c for c in cl if abs((c[0] + c[1]) * 0.5) < 0.16 * H]
    crotch_z = None
    for z in sorted(rows):
        if z < 0.15 * H:
            continue
        cc = central(rows[z])
        if len(cc) == 1 and cc[0][0] < 0.0 < cc[0][1]:
            crotch_z = z
            break
    notes["crotch_z_found"] = crotch_z
    if crotch_z is None or crotch_z < 0.36 * H or crotch_z > 0.55 * H:
        crotch_z = float(A().get("crotch", 0.46)) * H
        notes["crotch_z_fallback"] = True
    notes["crotch_z"] = crotch_z
    for side, sgn in (("Left", 1.0), ("Right", -1.0)):
        xs = []
        for z in sorted(rows):
            if 0.12 * H <= z <= crotch_z - 0.02 * H:
                for c in central(rows[z]):
                    cx = (c[0] + c[1]) * 0.5
                    if cx * sgn > 0:
                        xs.append(cx)
        leg_x = float(np.median(xs)) if xs else sgn * 0.06 * H
        hip_z = crotch_z + 0.045 * H
        boot = co[(co[:, 2] < 0.06 * H) & (co[:, 0] * sgn > 0)]
        toe_y = float(boot[:, 1].min())
        heel_y = float(boot[:, 1].max())
        shin = co[(np.abs(co[:, 2] - 0.12 * H) < 0.01 * H) & (co[:, 0] * sgn > 0) & (np.abs(co[:, 0]) < 0.16 * H)]
        ank_y = float((shin[:, 1].min() + shin[:, 1].max()) * 0.5) if len(shin) else (toe_y + heel_y) * 0.5
        ank_x = float((shin[:, 0].min() + shin[:, 0].max()) * 0.5) if len(shin) else leg_x
        thigh = co[(np.abs(co[:, 2] - (crotch_z - 0.03 * H)) < 0.008 * H) & (co[:, 0] * sgn > 0) & (np.abs(co[:, 0]) < 0.16 * H)]
        hip_y = float((thigh[:, 1].min() + thigh[:, 1].max()) * 0.5) if len(thigh) else ank_y
        hip_x = float((thigh[:, 0].min() + thigh[:, 0].max()) * 0.5) if len(thigh) else leg_x
        J[side + "UpLeg"] = Vector((hip_x, hip_y, hip_z))
        J[side + "Foot"] = Vector((ank_x, ank_y, 0.055 * H))
        knee = J[side + "UpLeg"].lerp(J[side + "Foot"], 0.5)
        J[side + "Leg"] = knee + Vector((0, -0.012, 0))   # a hint of bend forward at the knee
        J[side + "ToeBase"] = Vector((ank_x, heel_y + 0.72 * (toe_y - heel_y), 0.02 * H))
        J[side + "Toe_End"] = Vector((ank_x, toe_y, 0.02 * H))
    # ---- spine, neck, head

    def torso_y(z, back=0.3):
        cl = [c for c in slab_clusters(co, z) if c[0] <= 0.0 <= c[1]]
        if not cl:
            return 0.0
        c = cl[0]
        mid = (c[2] + c[3]) * 0.5
        return mid + (c[3] - mid) * back
    hips_z = (J["LeftUpLeg"].z + J["RightUpLeg"].z) * 0.5 + 0.015 * H
    shoulder_z = (J["LeftArm"].z + J["RightArm"].z) * 0.5
    neck_z = neck_mid - 0.02 * H
    head_z = neck_mid + 0.025 * H
    J["Hips"] = Vector((0.0, torso_y(hips_z, 0.0), hips_z))
    J["Neck"] = Vector((0.0, torso_y(neck_z, 0.1), neck_z))
    for name, f in (("Spine", 0.2), ("Spine1", 0.44), ("Spine2", 0.7)):
        z = hips_z + (neck_z - hips_z) * f
        J[name] = Vector((0.0, torso_y(z, 0.3), z))
    hz = co[(np.abs(co[:, 2] - (head_z + 0.06 * H)) < 0.01 * H) & (np.abs(co[:, 0]) < 0.1 * H)]
    head_y = float((hz[:, 1].min() + hz[:, 1].max()) * 0.5) if len(hz) else J["Neck"].y
    J["Head"] = Vector((0.0, head_y, head_z))
    crown = head_z + float(A().get("head_len", 0.075)) * H
    J["HeadTop_End"] = Vector((0.0, head_y, crown))
    for side, sgn in (("Left", 1.0), ("Right", -1.0)):
        J[side + "Shoulder"] = Vector((sgn * 0.022 * H, J["Spine2"].y, (J["Spine2"].z + J[side + "Arm"].z) * 0.5 + 0.02 * H))
    notes.update({"hips_z": hips_z, "shoulder_z": shoulder_z, "head_z": head_z, "crown_z": crown})
    return J, notes


def finger_joints(J, side):
    """Fingers for the OpenPose hands (non-deforming): from the wrist toward the tip, spread across the hand's width, the
    thumb in front (her hands hang palm-in in the A-pose, so the thumbs point forward, -Y)."""
    w = J[side + "Hand"]
    tip = J[side + "HandTip"]
    d = (tip - w)
    L = d.length
    d.normalize()
    fwd = Vector((0, -1, 0))
    across = (fwd - d * fwd.dot(d)).normalized()
    out = {}
    for f in FINGERS:
        if f == "Thumb":
            base = w + d * 0.12 * L + across * 0.10 * L
            fd = (d * 0.6 + across * 0.8).normalized()
            seg = 0.16 * L
        else:
            off = {"Index": 0.12, "Middle": 0.04, "Ring": -0.04, "Pinky": -0.11}[f] * L
            base = w + d * 0.45 * L + across * off
            fd = d
            seg = (0.55 if f == "Middle" else 0.5 if f in ("Index", "Ring") else 0.42) * L / 3.0
        for j in range(1, 5):
            out[side + "Hand" + f + str(j)] = base + fd * seg * (j - 1)
    return out


def build_armature(J):
    arm_data = bpy.data.armatures.new(RIG_NAME)
    rig = bpy.data.objects.new(RIG_NAME, arm_data)
    bpy.context.scene.collection.objects.link(rig)
    select_only([rig])
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    fj = {}
    for side in ("Left", "Right"):
        fj.update(finger_joints(J, side))
    order = list(BONE_PARENT) + list(fj)
    made = {}
    for name in order:
        b = eb.new(P + name)
        b.head = J[name] if name in J else fj[name]
        if name in BONE_TAIL:
            t = BONE_TAIL[name]
            b.tail = J[t] if t in J else fj[t]
        elif name in fj:
            j = int(name[-1])
            if j < 4:
                b.tail = fj[name[:-1] + str(j + 1)]
            else:
                b.tail = b.head + (b.head - fj[name[:-1] + "3"]).normalized() * 0.008
        else:   # an end bone: a short tail along the parent's direction
            b.tail = b.head + (b.head - J[BONE_PARENT[name]]).normalized() * 0.03
        made[name] = b
    for name, b in made.items():
        parent = BONE_PARENT.get(name)
        if parent is None and name in fj:
            j = int(name[-1])
            parent = name[:-1] + str(j - 1) if j > 1 else name.split("Hand")[0] + "Hand"
        if parent:
            b.parent = made[parent]
            b.use_connect = (made[parent].tail - b.head).length < 1e-5
        b.use_deform = name not in NON_DEFORM and name not in fj
    for name, b in made.items():
        b.align_roll(Vector((0, -1, 0)) if abs((b.tail - b.head).normalized().y) < 0.9 else Vector((0, 0, 1)))
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig, fj


def weight_fixes(mesh, rig, J, notes):
    """After the automatic weights: every vertex of the head (hair and beret included) on the head only, a leg never
    pulled by the other leg, at most four bones a vertex, normalised; vertices the bone heat left empty get the nearest
    bone's weight."""
    import numpy as np
    H = notes["height"]
    co = mesh_np(mesh)
    gname = {g.index: g.name for g in mesh.vertex_groups}
    nV = len(mesh.data.vertices)
    W = {}
    for v in mesh.data.vertices:
        W[v.index] = {gname[g.group]: g.weight for g in v.groups if g.weight > 1e-4}
    empty = [i for i, w in W.items() if sum(w.values()) < 0.01]
    notes["unweighted_after_heat"] = len(empty)
    deform = [b.name for b in rig.data.bones if b.use_deform]
    segs = {b.name: (np.array(rig.matrix_world @ b.head_local), np.array(rig.matrix_world @ b.tail_local)) for b in rig.data.bones if b.use_deform}

    def nearest_bone(p):
        best, bd = None, 1e9
        for n, (a, b) in segs.items():
            ab = b - a
            t = np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-9), 0, 1)
            d = np.linalg.norm(p - (a + ab * t))
            if d < bd:
                best, bd = n, d
        return best
    for i in empty:
        W[i] = {nearest_bone(co[i]): 1.0}
    head_z = J["Head"].z
    head_c = J["Head"]
    n_head = 0
    for i in range(nV):
        p = co[i]
        # the head: above the skull base and within the hair's reach of the head's axis (the bob reaches the chin)
        if p[2] >= head_z - 0.005 * H and abs(p[0]) < 0.11 * H and abs(p[1] - head_c.y) < 0.12 * H:
            W[i] = {P + "Head": 1.0}
            n_head += 1
            continue
        w = W[i]
        if p[2] < notes["crotch_z"]:
            other = "Right" if p[0] > 0.01 else ("Left" if p[0] < -0.01 else None)
            if other:
                for k in list(w):
                    if k.startswith(P + other) and any(s in k for s in ("UpLeg", "Leg", "Foot", "Toe")):
                        del w[k]
        top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
        s = sum(v for _, v in top)
        W[i] = {k: v / s for k, v in top} if s > 1e-6 else {nearest_bone(p): 1.0}
    notes["head_verts"] = n_head
    for g in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(g)
    groups = {n: mesh.vertex_groups.new(name=n) for n in deform}
    for i, w in W.items():
        for k, v in w.items():
            if k in groups:
                groups[k].add([i], v, "REPLACE")


def joint_markers(J, extra=None):
    """Small red spheres at the joints and green rods for the bones, for an x-ray check render."""
    objs = []
    pts = dict(J)
    pts.update(extra or {})
    for n, p in pts.items():
        small = ("Hand" in n and not n.endswith("Hand")) or n.endswith("Tip")
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.005 if small else 0.012, location=p, segments=8, ring_count=6)
        o = bpy.context.active_object
        o.color = (1.0, 0.15, 0.1, 1.0)
        objs.append(o)
    for n, par in BONE_PARENT.items():
        if par and n in J and par in J:
            a, b = J[par], J[n]
            L = (b - a).length
            bpy.ops.mesh.primitive_cylinder_add(radius=0.004, depth=L, location=(a + b) * 0.5, vertices=6)
            o = bpy.context.active_object
            o.rotation_mode = "QUATERNION"
            o.rotation_quaternion = (b - a).to_track_quat("Z", "Y")
            o.color = (0.1, 0.9, 0.3, 1.0)
            objs.append(o)
    return objs


def xray_renders(mesh, J, folder, extra=None, views=("front", "side")):
    os.makedirs(folder, exist_ok=True)
    marks = joint_markers(J, extra)
    mesh.color = (0.75, 0.75, 0.78, 1.0)
    cam = make_cam(900)
    R.workbench("OBJECT", (0.12, 0.12, 0.14))
    sh = bpy.context.scene.display.shading
    sh.show_xray = True
    sh.xray_alpha = 0.45
    out = []
    for v in views:
        place(cam, [mesh], v, 0.0, margin=1.04)
        f = os.path.join(folder, "rig_%s.png" % v)
        R.render(f)
        out.append(f)
    sh.show_xray = False
    for o in marks:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    return out


def load_mesh_only(src):
    R.import_model(src)
    ms = R.meshes()
    select_only(ms)
    if len(ms) > 1:
        bpy.ops.object.join()
    mesh = bpy.context.view_layer.objects.active
    mw = mesh.matrix_world.copy()
    mesh.parent = None
    mesh.matrix_world = mw
    apply_all(mesh)
    for o in list(bpy.data.objects):
        if o is not mesh:
            bpy.data.objects.remove(o, do_unlink=True)
    mesh.name = MESH_NAME
    mesh.data.name = MESH_NAME
    return mesh


def mode_rig():
    a = A()
    mesh = load_mesh_only(a["src"])
    J, notes = find_joints(mesh)
    log("joints: " + ", ".join("%s (%.3f %.3f %.3f)" % (k, v.x, v.y, v.z) for k, v in sorted(J.items())))
    log("notes: " + json.dumps({k: (round(v, 4) if isinstance(v, float) else v) for k, v in notes.items()}))
    folder = a.get("overlay") or os.path.dirname(os.path.abspath(a["out"]))
    fj = {}
    for side in ("Left", "Right"):
        fj.update(finger_joints(J, side))
    xray_renders(mesh, J, folder, fj)
    if a.get("joints_only") in ("1", "true"):
        return
    rig, fj = build_armature(J)
    select_only([mesh, rig])
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    weight_fixes(mesh, rig, J, notes)
    log("weights: %d verts left empty by the bone heat (given the nearest bone), %d on the head" % (notes["unweighted_after_heat"], notes["head_verts"]))
    mat = bpy.data.materials.new(MESH_NAME + "_clay")
    mat.diffuse_color = (0.8, 0.78, 0.76, 1.0)
    if not mesh.data.materials:
        mesh.data.materials.append(mat)
    json.dump({"joints": {k: [round(c, 5) for c in v] for k, v in J.items()}, "fingers": {k: [round(c, 5) for c in v] for k, v in fj.items()},
               "notes": notes}, open(os.path.join(folder, "joints.json"), "w", encoding="utf-8"), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a["out"]))
    log("wrote %s" % a["out"])
    if a.get("bendtest") not in ("0", "false"):
        bend_test(rig, mesh, folder)


def bend_test(rig, mesh, folder):
    """Arms down, an elbow and a knee bent, the head turned: a bad weight shows at once (bendtest.png)."""
    pb = rig.pose.bones
    for b in pb:
        b.rotation_mode = "QUATERNION"

    def rot_world(name, axis, deg):
        b = pb[P + name]
        M = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
        b.rotation_quaternion = Quaternion(M.inverted() @ Vector(axis), math.radians(deg))
    rot_world("LeftArm", (0, 1, 0), 38)
    rot_world("RightArm", (0, 1, 0), -38)
    rot_world("LeftForeArm", (1, 0, 0), 60)
    rot_world("RightUpLeg", (1, 0, 0), 55)
    rot_world("RightLeg", (1, 0, 0), -70)
    rot_world("Spine1", (1, 0, 0), 10)
    rot_world("Head", (0, 0, 1), 25)
    R.update()
    turntable([mesh], os.path.join(folder, "bendtest.png"), views=("front", "side", "back"), size=512)
    for b in pb:
        b.rotation_quaternion = Quaternion()
    R.update()


# ---------------------------------------------------------------- anim: retarget, idle, colours, export

def strip(name):
    return name.split(":")[-1]


def load_puppet(src):
    """(rig, mesh) from may_puppet.blend, or from a Mixamo-rigged FBX (mixamo.com's auto-rigger: its armature and skinned
    mesh renamed to ours, centimetres to metres, feet on the floor)."""
    ext = os.path.splitext(src)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=os.path.abspath(src))
        rig = bpy.data.objects.get(RIG_NAME) or next(o for o in bpy.data.objects if o.type == "ARMATURE")
        mesh = bpy.data.objects.get(MESH_NAME) or next(o for o in bpy.data.objects if o.type == "MESH" and o.find_armature() == rig)
        return rig, mesh
    R.import_model(src)
    rig = R.main_armature()
    mesh = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    for o in list(bpy.data.objects):
        if o not in (rig, mesh):
            bpy.data.objects.remove(o, do_unlink=True)
    # bake the armature object's transform (FBX: rotated 90 and scaled 0.01) into everything, as our own rig is built
    select_only([rig, mesh])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    rig.name, mesh.name = RIG_NAME, MESH_NAME
    for b in rig.data.bones:
        if not b.name.startswith(P):
            b.name = P + strip(b.name)
    if rig.animation_data:
        rig.animation_data.action = None
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    log("a Mixamo-rigged FBX: %d bones, %d verts" % (len(rig.data.bones), len(mesh.data.vertices)))
    return rig, mesh


def rest_world(rig, name):
    return rig.matrix_world @ rig.data.bones[name].matrix_local


def hierarchy(rig):
    """The rig's bones parents first."""
    out = []

    def walk(b):
        out.append(b)
        for c in b.children:
            walk(c)
    for b in rig.data.bones:
        if b.parent is None:
            walk(b)
    return out


def apply_world_rotations(rig, rots, root_loc=None):
    """Pose the rig so each bone named in `rots` has that world rotation (a Quaternion; its head stays where its parent
    puts it), every other bone keeping its rest relation to its parent; `root_loc` moves the root bone's head. Returns
    {bone: (location, rotation)} as basis values (what keyframes hold)."""
    out = {}
    pose_m = {}
    for b in hierarchy(rig):
        rest = b.matrix_local
        if b.parent is None:
            parent_chain = Matrix.Identity(4)
            head = Vector(root_loc) if root_loc is not None else rest.translation
        else:
            parent_chain = pose_m[b.parent.name] @ b.parent.matrix_local.inverted()
            head = (parent_chain @ rest).translation
        if b.name in rots:
            q = rots[b.name]
        else:
            q = (parent_chain @ rest).to_quaternion()
        B = Matrix.Translation(head) @ q.to_matrix().to_4x4()
        pose_m[b.name] = B
        ref = rest if b.parent is None else parent_chain @ rest
        basis = ref.inverted() @ B
        loc, rot, _ = basis.decompose()
        out[b.name] = (loc, rot)
    return out


def key_pose(rig, basis, frame, root_name, prev=None):
    for name, (loc, rot) in basis.items():
        pb = rig.pose.bones[name]
        pb.rotation_mode = "QUATERNION"
        if prev is not None and name in prev:
            rot.make_compatible(prev[name])
        pb.rotation_quaternion = rot
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if name == root_name:
            pb.location = loc
            pb.keyframe_insert("location", frame=frame)
    return {n: r for n, (_l, r) in basis.items()}


def new_action(rig, name):
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old)
    if rig.animation_data is None:
        rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    return act


def linear(act):
    fcs = list(getattr(act, "fcurves", []) or [])
    if not fcs and hasattr(act, "layers"):
        for layer in act.layers:
            for st in layer.strips:
                for bag in getattr(st, "channelbags", []):
                    fcs.extend(bag.fcurves)
    for fc in fcs:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    return fcs


def retarget_run(rig, mesh, clip, name="run", keep=("run", "idle")):
    """The Mixamo clip retargeted onto our rig by bone directions: each of our bones takes the source bone's world
    rotation away from its rest (D = M_pose M_rest^-1) after first being turned onto the source's rest direction (A: her
    A-pose arms onto Mixamo's T-pose), O_pose = D A O_rest, so every bone points where the source's points and twists
    as it does; the hips' travel is scaled by the leg lengths; then the whole clip is lifted so the lowest sole of the
    stride touches z = 0. Keys at the clip's own frames (30 fps), renamed "run"."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.abspath(clip))
    new = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new if o.type == "ARMATURE")
    sact = R.find_action(None, src) or bpy.data.actions[-1]
    R.use_action(src, sact)
    f0, f1 = int(round(sact.frame_range[0])), int(round(sact.frame_range[1]))
    sc = bpy.context.scene
    sc.render.fps = 30
    sbones = {strip(b.name): b for b in src.pose.bones}
    ours = {strip(b.name): b for b in rig.data.bones}
    common = [n for n in ours if n in sbones]
    # rests in world space
    sc.frame_set(f0)
    s_rest = {n: (src.matrix_world @ src.data.bones[sbones[n].name].matrix_local) for n in common}
    o_rest = {n: rest_world(rig, ours[n].name) for n in common}

    def ydir(M):
        return (M.to_3x3().normalized() @ Vector((0, 1, 0))).normalized()
    align = {n: ydir(o_rest[n]).rotation_difference(ydir(s_rest[n])) for n in common}
    o_rot = {n: o_rest[n].to_3x3().normalized().to_quaternion() for n in common}
    s_rot_inv = {n: s_rest[n].to_3x3().normalized().to_quaternion().inverted() for n in common}

    def leg_len(get, names):
        return (get(names[0]) - get(names[1])).length + (get(names[1]) - get(names[2])).length
    k = leg_len(lambda n: o_rest[n].translation, ("LeftUpLeg", "LeftLeg", "LeftFoot")) / max(1e-6, leg_len(lambda n: s_rest[n].translation, ("LeftUpLeg", "LeftLeg", "LeftFoot")))
    hips_rest_s = s_rest["Hips"].translation
    hips_rest_o = o_rest["Hips"].translation
    root = rig.data.bones[0].name if rig.data.bones[0].parent is None else next(b.name for b in rig.data.bones if b.parent is None)
    act = new_action(rig, name)
    frames = list(range(f0, f1 + 1))
    poses = []
    for f in frames:
        sc.frame_set(f)
        rots = {}
        for n in common:
            M = src.matrix_world @ sbones[n].matrix
            D = M.to_3x3().normalized().to_quaternion() @ s_rot_inv[n]
            rots[ours[n].name] = D @ align[n] @ o_rot[n]
        hs = (src.matrix_world @ sbones["Hips"].matrix).translation
        root_loc = hips_rest_o + (hs - hips_rest_s) * k
        poses.append((rots, root_loc))
    # the stride on the floor: lowest sole over the stride at z = 0 (evaluated on the posed mesh)
    lows = []
    for rots, root_loc in poses[:: max(1, len(poses) // 8)]:
        b = apply_world_rotations(rig, rots, root_loc)
        for name, (loc, rot) in b.items():
            pb = rig.pose.bones[name]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = rot
            pb.location = loc if name == root else Vector()
        R.update()
        lows.append(float(mesh_np(mesh, dg=bpy.context.evaluated_depsgraph_get())[:, 2].min()))
    lift = -min(lows)
    prev = None
    for i, (rots, root_loc) in enumerate(poses):
        b = apply_world_rotations(rig, rots, root_loc + Vector((0, 0, lift)))
        prev = key_pose(rig, b, frames[i] - f0, root, prev)
    linear(act)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    # the clip's own action goes too (it fits our bone names, so the exporter would ship it as a third animation)
    for a_ in list(bpy.data.actions):
        if a_ is not act and a_.name not in keep:
            bpy.data.actions.remove(a_)
    log("%s: %d frames from %s (%d..%d at 30 fps), hips travel x%.3f, lifted %.3f m to the floor, %d bones driven" % (
        act.name, len(frames), os.path.basename(clip), f0, f1, k, lift, len(common)))
    return act, len(frames) - 1


def make_idle(rig, mesh, seconds=2.0, fps=30):
    """A standing idle (there is no Mixamo idle on disk): the arms brought down from the A-pose to hang at her sides,
    elbows a little bent, a breath that lifts the chest and shoulders, a small sway of the hips and a nod; one loop."""
    act = new_action(rig, "idle")
    n = int(seconds * fps)
    names = {strip(b.name): b.name for b in rig.data.bones}
    o_rest = {s: rest_world(rig, full) for s, full in names.items()}

    def ydir(M):
        return (M.to_3x3().normalized() @ Vector((0, 1, 0))).normalized()

    def aim(s, d, extra=None):
        q = ydir(o_rest[s]).rotation_difference(d.normalized()) @ o_rest[s].to_3x3().normalized().to_quaternion()
        return (extra @ q) if extra is not None else q
    root = next(b.name for b in rig.data.bones if b.parent is None)
    hips0 = o_rest["Hips"].translation
    prev = None
    for f in range(n + 1):
        t = f / float(n)
        br = math.sin(2 * math.pi * t)          # the breath
        sw = math.sin(2 * math.pi * t + 0.6)    # the sway
        rots = {}
        for side, sgn in (("Left", 1.0), ("Right", -1.0)):
            up = Vector((sgn * 0.16, 0.02, -1.0))
            fore = Vector((sgn * 0.12, -0.28, -1.0))
            rots[names[side + "Arm"]] = aim(side + "Arm", up + Vector((0, 0, 0.012 * br)))
            rots[names[side + "ForeArm"]] = aim(side + "ForeArm", fore)
            rots[names[side + "Hand"]] = aim(side + "Hand", fore + Vector((sgn * 0.05, 0.05, 0)))
            rots[names[side + "Shoulder"]] = Quaternion((0, -sgn, 0), math.radians(1.2 * br)) @ o_rest[side + "Shoulder"].to_3x3().normalized().to_quaternion()
        for s, amt in (("Spine1", 0.8), ("Spine2", 1.0)):
            rots[names[s]] = Quaternion((1, 0, 0), math.radians(-amt * br)) @ o_rest[s].to_3x3().normalized().to_quaternion()
        rots[names["Head"]] = Quaternion((1, 0, 0), math.radians(1.5 * br)) @ Quaternion((0, 0, 1), math.radians(2.0 * sw)) @ o_rest["Head"].to_3x3().normalized().to_quaternion()
        # the legs stay planted: they keep their rest directions in the world while the hips sway a centimetre
        for s in ("LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"):
            if s in names:
                rots[names[s]] = o_rest[s].to_3x3().normalized().to_quaternion()
        b = apply_world_rotations(rig, rots, hips0 + Vector((0.008 * sw, 0, 0.003 * br)))
        prev = key_pose(rig, b, f, root, prev)
    linear(act)
    log("idle: %d frames at %d fps (arms down, breath, sway)" % (n + 1, fps))
    return act, n


def colour_from_paintings(mesh, paint_dir):
    """Vertex colours projected from the arms-out paintings (front, back, right = the side still, left = its mirror;
    puppet.py keyed them and filled the screen round the figure with the nearest figure colour): each vertex takes each
    view's colour where it faces that camera and is not hidden from it (a ray toward the camera), weighted by how
    squarely it faces it; the painting is fitted to the mesh by her height, then slid sideways to the best overlap."""
    import numpy as np
    from mathutils.bvhtree import BVHTree
    meta = json.load(open(os.path.join(paint_dir, "paint.json"), encoding="utf-8"))
    dg = bpy.context.evaluated_depsgraph_get()
    co = mesh_np(mesh)
    me = mesh.data
    nrm = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("normal", nrm)
    nrm = nrm.reshape(-1, 3) @ np.array(mesh.matrix_world.to_3x3()).T
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    bvh = BVHTree.FromObject(mesh, dg)
    H = float(co[:, 2].max() - co[:, 2].min())
    z0 = float(co[:, 2].min())
    # view: (direction from the figure to the camera, screen-right axis)
    views = {"front": (Vector((0, -1, 0)), np.array([1.0, 0, 0])), "back": (Vector((0, 1, 0)), np.array([-1.0, 0, 0])),
             "right": (Vector((-1, 0, 0)), np.array([0, -1.0, 0])), "left": (Vector((1, 0, 0)), np.array([0, 1.0, 0]))}
    acc = np.zeros((len(co), 3))
    wsum = np.zeros(len(co))
    best_w = np.zeros(len(co))
    best_c = np.zeros((len(co), 3))
    report = {}
    for v, (d, right) in views.items():
        if v not in meta:
            continue
        img = bpy.data.images.load(os.path.abspath(os.path.join(paint_dir, meta[v]["file"])))
        W, Hh = img.size
        px = np.empty(W * Hh * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(Hh, W, 4)[::-1]   # top row first
        bb = meta[v]["bbox"]              # x0, y0, x1, y1 of the figure (pixels, top-left origin)
        s = (bb[3] - bb[1]) / H
        u_off = (bb[0] + bb[2]) * 0.5
        hor = co @ right
        hor_c = (hor.max() + hor.min()) * 0.5
        vv = bb[3] - (co[:, 2] - z0) * s
        alpha = px[..., 3]
        # slide sideways to the best overlap of the mesh's points with the painting's figure
        best, best_dx = -1, 0
        for dx in range(-40, 41, 2):
            uu = (u_off + (hor - hor_c) * s + dx).astype(int)
            ok = (uu >= 0) & (uu < W) & (vv >= 0) & (vv < Hh)
            hit = np.zeros(len(co), bool)
            hit[ok] = alpha[vv[ok].astype(int), uu[ok]] > 0.5
            score = hit.mean()
            if score > best:
                best, best_dx = score, dx
        uu = np.clip(u_off + (hor - hor_c) * s + best_dx, 0, W - 1)
        vc = np.clip(vv, 0, Hh - 1)
        col = px[vc.astype(int), uu.astype(int), :3]
        facing = np.clip(nrm @ np.array(d), 0.0, 1.0)
        vis = np.zeros(len(co), bool)
        dd = Vector(d)
        for i in np.nonzero(facing > 0.05)[0]:
            p = Vector(co[i]) + Vector(nrm[i]) * 0.002 + dd * 0.002
            hit = bvh.ray_cast(p, dd, 5.0)
            vis[i] = hit[0] is None
        w = facing ** 2 * vis
        if v in ("right", "left"):
            # in the side still her arm hangs over her flank from the shoulder to the hip: what the side painting shows there
            # is the sleeve and the glove, never the A-pose's bare flank (it painted magenta on the overalls)
            band = (co[:, 2] - z0 > 0.42 * H) & (co[:, 2] - z0 < 0.80 * H) & (np.abs(co[:, 0]) < 0.16)
            w[band] = 0.0
        acc += col * w[:, None]
        wsum += w
        upd = (facing > best_w)
        best_w[upd] = facing[upd]
        best_c[upd] = col[upd]
        report[v] = {"overlap": round(float(best), 3), "slide_px": best_dx, "visible": int(vis.sum())}
        bpy.data.images.remove(img)
    out = np.where(wsum[:, None] > 1e-4, acc / np.maximum(wsum, 1e-9)[:, None], best_c)
    # a vertex no painting sees (the inner thighs, the armpits) takes the colour of the nearest vertex one does: the
    # nearest-facing painting's pixel there was often the hand or the screen's edge
    from mathutils.kdtree import KDTree
    seen = np.nonzero(wsum > 0.05)[0]
    kd = KDTree(len(seen))
    for j, i in enumerate(seen):
        kd.insert(Vector(co[i]), j)
    kd.balance()
    for i in np.nonzero(wsum <= 0.05)[0]:
        _p, j, _d = kd.find(Vector(co[i]))
        if j is not None:
            out[i] = out[seen[j]]
    old = me.color_attributes.get("Col")
    if old is not None and (old.domain != "POINT" or old.data_type != "BYTE_COLOR"):
        me.color_attributes.remove(old)   # an FBX brings its colours on the corners: ours go on the points
    attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
    rgba = np.concatenate([out, np.ones((len(co), 1))], axis=1).astype(np.float32).ravel()
    if hasattr(attr.data[0], "color_srgb"):
        attr.data.foreach_set("color_srgb", rgba)
    else:
        attr.data.foreach_set("color", rgba)
    me.color_attributes.active_color = attr
    try:
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
    except Exception:
        pass
    # a material that shows them (Blender, the glTF exporter and the viewers read the Color Attribute node)
    mat = bpy.data.materials.get("May_paint") or bpy.data.materials.new("May_paint")
    nt = R._nodes(mat)
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    ca = nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = "Col"
    nt.links.new(ca.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.85
    for nm in ("Specular IOR Level", "Specular"):
        if nm in bs.inputs:
            bs.inputs[nm].default_value = 0.1
    nt.links.new(bs.outputs["BSDF"], o.inputs["Surface"])
    me.materials.clear()
    me.materials.append(mat)
    log("colours: " + json.dumps(report) + ", %d verts barely seen by any painting (the nearest seen vertex's colour)" % int((wsum <= 0.05).sum()))
    return report


def export_glb(rig, mesh, out):
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    select_only([rig, mesh])
    kw = dict(filepath=os.path.abspath(out), export_format="GLB", use_selection=True, export_animations=True, export_skins=True,
              export_yup=True, export_apply=False)
    opts = [{"export_animation_mode": "ACTIONS", "export_vertex_color": "MATERIAL"}, {"export_animation_mode": "ACTIONS"}, {}]
    last = None
    for extra in opts:
        try:
            bpy.ops.export_scene.gltf(**kw, **extra)
            log("wrote %s (%s)" % (out, extra or "defaults"))
            return
        except TypeError as e:
            last = e
            continue
    raise RuntimeError("glTF export failed: %s" % last)


def play(rig, act, frame):
    R.use_action(rig, act)
    bpy.context.scene.frame_set(int(frame))
    R.update()


def mode_anim():
    a = A()
    rig, mesh = load_puppet(a["src"])
    rig.matrix_world = Matrix.Identity(4)
    sc = bpy.context.scene
    sc.render.fps = 30
    run, run_n = retarget_run(rig, mesh, a.get("clip", os.path.join(REPO, "tools", "dl", "mixamo", "running.fbx")))
    if a.get("idle"):
        # pass 71: a Mixamo idle retargeted like the run (the stride's floor rule keeps its feet down)
        idle, idle_n = retarget_run(rig, mesh, a["idle"], name="idle")
    else:
        idle, idle_n = make_idle(rig, mesh)
    if a.get("paint"):
        play(rig, idle, 0)
        # the colours go on in the rest pose (the paintings are the A-pose)
        rig.data.pose_position = "REST"
        R.update()
        colour_from_paintings(mesh, a["paint"])
        rig.data.pose_position = "POSE"
    # the clips as NLA tracks too, so the file opens with both listed and the exporter sees both
    ad = rig.animation_data
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for act in (idle, run):
        tr = ad.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, 0, act)
        tr.mute = True
    R.use_action(rig, run)
    sc.frame_start, sc.frame_end = 0, run_n
    if a.get("save"):
        os.makedirs(os.path.dirname(os.path.abspath(a["save"])), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a["save"]))
        log("saved %s" % a["save"])
    export_glb(rig, mesh, a["out"])
    rd = a.get("renders")
    if rd:
        os.makedirs(rd, exist_ok=True)
        play(rig, idle, 0)
        turntable([mesh], os.path.join(rd, "turntable.png"), views=("front", "fd", "side", "bd", "back"), size=512, color="VERTEX", pitch=8.0)
        cam = make_cam(512)
        R.workbench("VERTEX", (0.16, 0.17, 0.2))
        frames = [int(round(run_n * k / 6.0)) for k in range(6)]
        paths = []
        for view in ("side", "front", "back"):
            for f in frames:
                play(rig, run, f)
                place(cam, [mesh], view, 8.0, margin=1.25, target=(0, 0, 0.8), span=2.0)
                p = os.path.join(rd, "run_%s_%02d.png" % (view, f))
                R.render(p)
                paths.append(p)
        bpy.data.objects.remove(cam, do_unlink=True)
        json.dump({"turntable": ["turntable_%s.png" % v for v in ("front", "fd", "side", "bd", "back")],
                   "run": [os.path.basename(p) for p in paths], "run_frames": frames, "run_n": run_n, "idle_n": idle_n},
                  open(os.path.join(rd, "renders.json"), "w", encoding="utf-8"), indent=1)


# ---------------------------------------------------------------- guides: OpenPose from her own bones

GVIEWS = {"back": 0.0, "bd": 45.0, "side": 90.0, "fd": 135.0, "front": 180.0}   # tools/pose_driver.py's VIEWS
GSIZE = 640
GFILL = 0.72
KP = ["nose", "neck", "rsho", "relb", "rwri", "lsho", "lelb", "lwri", "rhip", "rknee", "rank", "lhip", "lknee", "lank", "reye", "leye", "rear", "lear"]
GBONES = {"neck": "Neck", "rsho": "RightArm", "relb": "RightForeArm", "rwri": "RightHand", "lsho": "LeftArm", "lelb": "LeftForeArm",
          "lwri": "LeftHand", "rhip": "RightUpLeg", "rknee": "RightLeg", "rank": "RightFoot", "lhip": "LeftUpLeg", "lknee": "LeftLeg", "lank": "LeftFoot"}
HAND_BONES = ["Hand"] + [f + str(k) for f in ("HandThumb", "HandIndex", "HandMiddle", "HandRing", "HandPinky") for k in (1, 2, 3, 4)]
LEGS = {"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "Hips"}
# what may stand between a joint and the camera without hiding it: its own limb (a joint sits inside it), and for the legs
# the other leg (one leg crossing the other is never dropped: Wan would paint a one-legged stride)
OWN = {"relb": {"RightArm", "RightForeArm"}, "rwri": {"RightForeArm", "RightHand"}, "lelb": {"LeftArm", "LeftForeArm"},
       "lwri": {"LeftForeArm", "LeftHand"}, "rknee": LEGS, "rank": LEGS, "lknee": LEGS, "lank": LEGS}


def mode_guides():
    """OpenPose drivers in tools/pose_driver.py's format (five views, its camera, framing and frame count) from HER rig
    playing the retargeted run, with every elbow, wrist (and its hand), knee and ankle that her own body hides from the
    camera dropped: a ray from the joint toward the camera that meets a part of the mesh weighted to another bone than
    the joint's own limb. Shoulders and hips stay (they anchor the limbs, as a pose detector infers them); the face
    points follow pose_driver's facing rule, set on her own head (the nose measured on the mesh) and turned with it."""
    import numpy as np
    from mathutils.bvhtree import BVHTree
    a = A()
    frame_mode = str(a.get("frame") or "ankles")
    # pass 71 follow-up: the face angle. "nose" (the trial's guide v3, the default): the ears' middle set from the
    # measured nose as pose_driver places it, so a side view stays in profile; "head": the ears' middle on the head
    # bone's axis (the trial's first guide: her bob pulled it back over the neck and Wan turned her face to the camera)
    face_mode = "head" if str(a.get("face") or "nose") == "head" else "nose"
    rig, mesh = load_puppet(a["src"])
    act = bpy.data.actions.get(a.get("action", "run"))
    if act is None:
        fail("no action %s in %s" % (a.get("action", "run"), a["src"]))
    R.use_action(rig, act)
    n = int(a.get("frames", 24))
    pitch = math.radians(float(a.get("pitch", 25.0)))
    out = a["out"]
    f0, f1 = act.frame_range[0], act.frame_range[1]
    period = f1 - f0     # the last key repeats the first pose (a loop)
    sc = bpy.context.scene
    pb = {strip(b.name): b for b in rig.pose.bones}
    # every vertex's strongest bone, for "what did the ray hit"
    gname = {g.index: strip(g.name) for g in mesh.vertex_groups}
    dom = []
    for v in mesh.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dom.append(gname.get(best.group, "") if best is not None else "")
    polys = [tuple(p.vertices) for p in mesh.data.polygons]

    def face_bone(fi):
        names = [dom[i] for i in polys[fi]]
        return max(set(names), key=names.count)

    # the face, measured in the rest pose and carried by the head bone: the nose is the face's front-most vertex
    rig.data.pose_position = "REST"
    R.update()
    co = mesh_np(mesh)
    head_rest = rig.data.bones[pb["Head"].name]
    hz0 = (rig.matrix_world @ head_rest.head_local).z
    top0 = (rig.matrix_world @ rig.data.bones[pb["HeadTop_End"].name].head_local).z
    face = co[(co[:, 2] > hz0) & (co[:, 2] < top0) & (np.abs(co[:, 0]) < 0.02)]
    nose_w = Vector(face[np.argmin(face[:, 1])].tolist()) if len(face) else Vector((0, -0.09, (hz0 + top0) * 0.5))
    head_m0 = rig.matrix_world @ head_rest.matrix_local
    nose_local = head_m0.inverted() @ nose_w
    rig.data.pose_position = "POSE"
    R.update()
    face_scale = (top0 - hz0) / 0.19   # pose_driver's eye and ear offsets are for a Mixamo head; hers is this size
    # the ears' middle: pose_driver's head centre is 9 cm behind its nose and 1 cm above it; hers is set from her nose
    # the same way (scaled to her head). The first guide put it on the head bone's axis, which her bob pulls back over
    # the neck: in the side view one ear dot sat straight above the neck and Wan Animate turned her face to the camera
    # on three seeds, with the shoulders levelled too; with the ear ahead of the neck (Mixamo's place) she ran in profile
    centre_local = head_m0.inverted() @ (nose_w + Vector((0.0, 0.09 * face_scale, 0.01 * face_scale)))
    if face_mode == "head":
        hb = rig.matrix_world @ head_rest.head_local
        centre_local = head_m0.inverted() @ Vector((hb.x, hb.y, nose_w.z + 0.01 * face_scale))

    def joint(name):
        return rig.matrix_world @ pb[name].head

    skel = []
    occ_stats = {}
    for k in range(n + 1):
        f = f0 + period * ((k % n) / float(n))
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        R.update()
        s = {key: joint(b) for key, b in GBONES.items()}
        s["head"] = joint("Head")
        s["top"] = joint("HeadTop_End")
        hm = rig.matrix_world @ pb["Head"].matrix
        s["nose3"] = hm @ nose_local
        s["centre3"] = hm @ centre_local
        s["hfwd"] = (hm.to_3x3().normalized() @ (head_m0.to_3x3().normalized().inverted() @ Vector((0, -1, 0)))).normalized()
        for side, tag in (("Left", "l"), ("Right", "r")):
            for hb in HAND_BONES:
                if side + hb in pb:
                    s[tag + ":" + hb] = joint(side + hb)
        dg = bpy.context.evaluated_depsgraph_get()
        s["bvh"] = BVHTree.FromObject(mesh, dg)
        if frame_mode == "soles":
            s["sole"] = float(mesh_np(mesh, dg=dg)[:, 2].min())
        skel.append(s)
    # the stride's ground and height, as pose_driver measures them (ankles, the head's top); pass 71: frame=soles puts the
    # ground at the lowest sole of the posed mesh over the stride, so a figure with chunky boots or long feet keeps them
    # inside the canvas (MAY-P's front and fd walks left the frame at the bottom on the ankle framing)
    ground = min(min(s["rank"].z, s["lank"].z) for s in skel[:n])
    ankle_ground = ground
    if frame_mode == "soles":
        ground = min(s["sole"] for s in skel[:n])
    height = max(s["top"].z for s in skel[:n]) - ground
    # forward: the feet, averaged over the stride (pose_driver's rule)
    fwd = Vector((0, 0, 0))
    for s_k in range(0, n, max(1, n // 8)):
        f = f0 + period * s_k / float(n)
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        R.update()
        for side in ("Left", "Right"):
            v = joint(side + "ToeBase") - joint(side + "Foot")
            v.z = 0.0
            fwd += v
    fwd.normalize()
    yaw0 = math.atan2(fwd.y, fwd.x)
    up = Vector((0, 0, 1))
    span = height / GFILL
    meta_views = {}
    for view, want_deg in GVIEWS.items():
        rot = Matrix.Rotation(math.pi * 0.5 - math.radians(want_deg) - yaw0, 4, "Z")
        cam_dir = Vector((0.0, math.cos(pitch), -math.sin(pitch)))
        cam_up = Vector((0.0, math.sin(pitch), math.cos(pitch)))
        cam_right = Vector((1.0, 0.0, 0.0))
        to_cam_world = (rot.to_3x3().inverted() @ (-cam_dir)).normalized()

        def project(p):
            rel = rot @ p - Vector((0.0, 0.0, ground + height * 0.5))
            return round(0.5 + rel.dot(cam_right) / span, 4), round(0.5 - rel.dot(cam_up) / span + 0.04, 4)

        def hidden(s, key, p):
            own = OWN[key]
            o = p.copy()
            for _ in range(16):
                hit = s["bvh"].ray_cast(o, to_cam_world, 5.0)
                if hit[0] is None:
                    return False
                if face_bone(hit[2]) not in own:
                    return True
                o = hit[0] + to_cam_world * 1e-4
            return False

        frames = []
        dropped = {k_: 0 for k_ in OWN}
        for k, s in enumerate(skel):
            pts = {key: s[key] for key in GBONES}
            hf = rot.to_3x3() @ s["hfwd"]
            hf.z = 0.0
            hf = hf.normalized() if hf.length > 1e-6 else Vector((0, -1, 0))
            hright = hf.cross(up)
            nose = rot @ s["nose3"]
            centre = rot @ s["centre3"]
            fs = face_scale
            vis = {k2: True for k2 in KP}
            for key in OWN:
                if hidden(s, key, s[key]):
                    vis[key] = False
                    dropped[key] += 1
            row = []
            # which face points show is decided by the body's forward, as pose_driver does (her head's own small yaw in
            # the run put the nose on and off in the side view, frame by frame); where they are drawn follows the head
            bf = rot.to_3x3() @ Vector((fwd.x, fwd.y, 0.0))
            bright = bf.cross(up)
            facing = bf.dot(-cam_dir)
            pts_r = {key: rot @ p for key, p in pts.items()}
            pts_r["nose"] = nose
            pts_r["reye"] = nose + (hright * 0.03 + up * 0.03 - hf * 0.02) * fs
            pts_r["leye"] = nose + (-hright * 0.03 + up * 0.03 - hf * 0.02) * fs
            pts_r["rear"] = centre + hright * 0.075 * fs
            pts_r["lear"] = centre - hright * 0.075 * fs
            # pose_driver's rule (a profile shows no nose or eyes; the DWPose-style profile face, nose and near eye drawn,
            # did not keep her face from turning to the camera: the ear's place did, see centre_local)
            vis["nose"] = vis["reye"] = vis["leye"] = facing > 0.15
            vis["rear"] = bright.dot(-cam_dir) > -0.25
            vis["lear"] = (-bright).dot(-cam_dir) > -0.25
            for key in KP:
                p = pts_r[key]
                rel = p - Vector((0.0, 0.0, ground + height * 0.5))
                u, v = round(0.5 + rel.dot(cam_right) / span, 4), round(0.5 - rel.dot(cam_up) / span + 0.04, 4)
                row.append([u, v, 1 if vis[key] else 0])
            hands = {}
            for tag, wkey in (("l", "lwri"), ("r", "rwri")):
                if not vis[wkey]:
                    hands[tag] = []   # hidden: no hand (draw skips it; pose_shoulders and the other tweaks take an empty list)
                    continue
                hands[tag] = [list(project(s[tag + ":" + hb])) if tag + ":" + hb in s else None for hb in HAND_BONES]
            frames.append({"body": row, "hands": hands})
        d = os.path.join(out, view)
        os.makedirs(d, exist_ok=True)
        json.dump({"view": view, "frames": frames, "size": GSIZE, "fbx": os.path.basename(str(a.get("glb") or "puppet.glb")), "n": n, "pitch": math.degrees(pitch)},
                  open(os.path.join(d, "poses.json"), "w"), indent=0)
        # her standing height in this view's pixels (the rest pose's head top over the stride's ground), for the size checks
        meta_views[view] = {"dropped": dropped}
        occ_stats[view] = dropped
        log("guides %s: %d frames, dropped %s" % (view, len(frames), {k_: v for k_, v in dropped.items() if v}))
    rig.data.pose_position = "REST"
    R.update()
    stand_top = joint("HeadTop_End").z
    stand_ank = min(joint("RightFoot").z, joint("LeftFoot").z)
    rig.data.pose_position = "POSE"
    json.dump({"kind": "pose", "fbx": os.path.basename(str(a.get("glb") or "puppet.glb")), "src": os.path.relpath(a["src"], REPO).replace("\\", "/"), "action": act.name,
               "frames": n, "loop": True, "pitch": math.degrees(pitch), "start": None, "end": None, "views": list(GVIEWS),
               "body": None, "fwd": "feet", "arms": None, "rig": "puppet", "rigmap": None, "amp": None, "lean": None, "retarget": {},
               "occlusion": occ_stats, "ground": ground, "height": height, "span_m": span, "frame": frame_mode, "ankle_ground": ankle_ground,
               "face": face_mode,
               "clip": a.get("clip") or None, "glb": a.get("glb") or None,
               "stand": {"top_minus_ankle_m": stand_top - stand_ank, "px": (stand_top - stand_ank) / span * GSIZE},
               "notes": "the Puppet method: OpenPose from the hero's own rig (tools/puppet_blender.py mode=guides); joints hidden by the body dropped; framed by the %s" % frame_mode},
              open(os.path.join(out, "meta.json"), "w", encoding="utf-8", newline="\n"), indent=1)
    log("guides written to %s (ground %.3f, height %.3f m)" % (out, ground, height))


def mode_silhouette():
    """The puppet's own answer to "how tall is her run in this view": per view (the guides' 25-degree cameras), the
    screen height of her posed mesh in each of the run's 24 poses and in the idle's first frame (arms down, standing),
    so a painted run can be checked against the ratio the 3D figure really has -> <out> (JSON)."""
    import numpy as np
    a = A()
    rig, mesh = load_puppet(a["src"])
    n = int(a.get("frames", 24))
    pitch = math.radians(float(a.get("pitch", 25.0)))
    run = bpy.data.actions["run"]
    idle = bpy.data.actions["idle"]
    sc = bpy.context.scene
    cam_up_l = Vector((0.0, math.sin(pitch), math.cos(pitch)))
    yaw0 = -math.pi / 2   # she faces -Y (the guides measured the feet: the same within a degree)

    def heights(view_deg):
        rot = Matrix.Rotation(math.pi * 0.5 - math.radians(view_deg) - yaw0, 3, "Z")
        up_w = rot.inverted() @ cam_up_l
        return np.array([up_w.x, up_w.y, up_w.z])
    out = {}
    R.use_action(rig, idle)
    sc.frame_set(0)
    R.update()
    co_idle = mesh_np(mesh, dg=bpy.context.evaluated_depsgraph_get())
    poses = []
    R.use_action(rig, run)
    f0, f1 = run.frame_range
    for k in range(n):
        f = f0 + (f1 - f0) * k / float(n)
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        R.update()
        poses.append(mesh_np(mesh, dg=bpy.context.evaluated_depsgraph_get()))
    for view, deg in GVIEWS.items():
        u = heights(deg)
        h_idle = float(np.ptp(co_idle @ u))
        hs = [float(np.ptp(c @ u)) for c in poses]
        out[view] = {"stand": round(h_idle, 4), "run": [round(h, 4) for h in hs], "ratio_median": round(float(np.median(hs)) / h_idle, 4),
                     "ratio_max": round(max(hs) / h_idle, 4), "ratio_min": round(min(hs) / h_idle, 4)}
        log("silhouette %s: run/idle median %.3f max %.3f" % (view, out[view]["ratio_median"], out[view]["ratio_max"]))
    json.dump(out, open(a["out"], "w", encoding="utf-8", newline="\n"), indent=1)


# ---------------------------------------------------------------- main

def main():
    mode = A().get("mode", "")
    set_names()
    fn = {"clean": clean}.get(mode) or globals().get("mode_" + mode)
    if fn is None:
        fail("mode=%s is not one of clean, rig, anim, guides" % mode)
    fn()
    log("done")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        import traceback
        traceback.print_exc()
        print("puppet_blender: FAILED (exception above)", flush=True)
        sys.exit(1)

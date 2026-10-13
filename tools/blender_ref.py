"""What a 3D file can do for us, and the reference renders it gives (pass 66, the Level Editor's asset system).

A 3D reference Garry drops in (FBX, GLB/glTF, OBJ, DAE, .blend, or a zip holding one of them, the way Sketchfab packs
`source/` + `textures/`) can serve three things: the icon (a three-quarter render the icon pipeline paints from, like
tools/dl/tommy_ref.png), the look of the sprite sheet (clay and textured renders of the five game views, what gen_ctl's
`look_ref` and the side painting are redrawn from) and the animation (drivers: tools/pose_driver.py for a humanoid rig,
tools/blender_depth_drivers.py for any rigged model with a clip). This script does the first two and tells the editor
which of the three the file allows.

    "$BLENDER" -b --python tools/blender_ref.py -- src=<file> out=<dir> mode=probe|icon|views|all
        [forward=-Y|+Y|-X|+X|auto|yaw:<deg>] [action=<name>] [at=<seconds>|frame=<n>] [pitch=25]
        [icon_yaw=35] [icon_pitch=20] [size=1024] [screen=0,1,0] [albedo=<png>] [scale=auto|<factor>]

mode=probe  (no big renders, a few seconds) writes <out>/probe.json:
    {src, armatures: [{name, bones, bone_parents}], actions: [{name, frame_range, frames, fps, seconds}], meshes,
     dimensions, scale_applied, rig_guess: mixamo|sm|other|none, rigmap_guess, humanoid, forward_guess, forward_yaw_deg,
     forward_basis, albedo_guess, can: {icon, look, pose_drivers, depth_drivers}, message}
  and <out>/thumbs.png, a quick contact of the five game views and the icon's angle (192 px tiles).
mode=icon   writes <out>/icon_ref.png: 1024 square, orthographic, the front-left three-quarter from a little above
  (icon_yaw 35 degrees round from the front toward the model's left, icon_pitch 20, the angle of tools/dl/tommy_ref.png),
  textured when the model has textures (or `albedo=`), on a transparent film unless `screen=` is given
  (gen_icon_cands._ref lays a transparent render on the green or blue screen itself).
mode=views  writes <out>/<view>/clay.png and <out>/<view>/look.png for front, fd, side, bd, back with the depth drivers'
  camera rule (blender_beetle.py: yaw 0/45/90/135/180 round the model's forward, pitch 25, an orthographic camera at three
  extents, 1.45 extents wide), clay first so a bad framing shows at once. clay.png is the model as warm clay on the screen
  colour (what a side painting is redrawn from); look.png the same frame in the model's own colours (a look reference).
mode=all    probe, icon and views.

forward= is the way the model faces (Blender's convention, and the beetle's and scorpion's, is -Y); `auto` takes the
probe's guess (the feet of a Mixamo-style rig, else its hips and shoulders, else -Y). action= names the clip to pose
(exact name, or the part after the last "|", or a unique case-insensitive piece of it); at=/frame= the moment of it
(default its first frame). scale=auto applies pose_driver's rule: a model taller than 20 units is a centimetre model and
is scaled to metres (x0.01); a number scales by that.

The functions here are shared with tools/blender_depth_drivers.py (import, scale, the camera rule, the materials); run
from Blender only (`import bpy`).
"""
import json
import math
import os
import re
import sys
import warnings
import zipfile

warnings.filterwarnings("ignore", category=DeprecationWarning)

try:
    import bpy
    from mathutils import Vector
except ImportError:  # outside Blender only the pure helpers (rig_guess, rigmap_guess, args, ...) are usable: the selftest
    bpy = None
    Vector = None

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEWS = {"front": 0.0, "fd": 45.0, "side": 90.0, "bd": 135.0, "back": 180.0}
CLAY = (0.78, 0.55, 0.3, 1.0)
MODEL_EXTS = (".fbx", ".glb", ".gltf", ".obj", ".dae", ".blend")
# the bones a Mixamo-style humanoid must have (after the "mixamorig:" prefix is stripped) for pose_driver.py to walk it
MIXAMO_CORE = ("Hips", "Spine", "Neck", "Head", "LeftUpLeg", "RightUpLeg", "LeftArm", "RightArm", "LeftFoot", "RightFoot")
# the 21 names pose_driver.py reads (RIGS maps another rig's names onto these)
MIXAMO_NAMES = ["Hips", "Spine", "Spine1", "Neck", "Head", "HeadTop_End",
                "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
                "RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
INSERT_HINT = ("For a walk export it from Mixamo as FBX Binary, 30 fps, In Place, keyframe reduction none, or a GLB that "
               "carries its animation.")


# ---------------------------------------------------------------- arguments and files

def args(argv=None):
    out = {}
    argv = sys.argv if argv is None else argv
    rest = argv[argv.index("--") + 1:] if "--" in argv else []
    for a in rest:
        if "=" in a:
            k, v = a.split("=", 1)
            out[k.strip()] = v
    return out


def parse_rgb(s, default=(0.0, 1.0, 0.0)):
    if not s:
        return tuple(default)
    if s in ("green",):
        return (0.0, 1.0, 0.0)
    if s in ("blue",):
        return (0.0, 0.0, 1.0)
    if s in ("magenta",):
        return (1.0, 0.0, 1.0)
    parts = [float(v) for v in s.split(",")]
    return tuple(parts[:3])


def strip_prefix(name):
    """'mixamorig:Hips' -> 'Hips' (pose_driver.py's rule)."""
    return name.split(":")[-1]


def unzip_model(src):
    """A zip is unpacked beside itself (into <dir>/<stem>/, once) and the first model file inside is the source."""
    src = os.path.abspath(src)
    if not src.lower().endswith(".zip"):
        return src
    folder = os.path.join(os.path.dirname(src), os.path.splitext(os.path.basename(src))[0])
    if not os.path.isdir(folder) or not os.listdir(folder):
        os.makedirs(folder, exist_ok=True)
        zipfile.ZipFile(src).extractall(folder)
    found = []
    for root, _dirs, files in os.walk(folder):
        for f in files:
            if f.lower().endswith(MODEL_EXTS):
                found.append(os.path.join(root, f))
    if not found:
        raise SystemExit("blender_ref: no model file (%s) inside %s" % (", ".join(MODEL_EXTS), src))
    found.sort(key=lambda p: (MODEL_EXTS.index(os.path.splitext(p)[1].lower()), p))
    return found[0]


def find_albedo(src):
    """A colour map beside the model (Sketchfab's textures/ folder): the first file whose name says albedo, diffuse or
    base colour; None when there is none."""
    here = os.path.dirname(os.path.abspath(src))
    parent = os.path.dirname(here)
    folders = [here] + [os.path.join(parent, d) for d in sorted(os.listdir(parent)) if d.lower().startswith("texture")
                        and os.path.isdir(os.path.join(parent, d))]
    cands = []
    for folder in folders:
        for f in sorted(os.listdir(folder)):
            low = f.lower()
            if low.endswith((".png", ".jpg", ".jpeg", ".tga")) and re.search(r"albedo|diffuse|basecolor|base_color|base-color|_col\b|_color|_diff", low):
                cands.append(os.path.join(folder, f))
    cands.sort(key=lambda p: (0 if "albedo" in os.path.basename(p).lower() else 1, p))
    return cands[0] if cands else None


def import_model(src):
    """A fresh empty file, then the importer the extension asks for. Returns the model file actually read."""
    src = unzip_model(src)
    ext = os.path.splitext(src)[1].lower()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=src)
    elif ext == ".dae":
        if not hasattr(bpy.ops.wm, "collada_import"):
            raise SystemExit("blender_ref: this Blender has no Collada importer; export the model as FBX or GLB")
        bpy.ops.wm.collada_import(filepath=src)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=src)
    else:
        raise SystemExit("blender_ref: cannot read %s (%s)" % (src, ", ".join(MODEL_EXTS)))
    return src


def scene():
    return bpy.context.scene


def armatures():
    return [o for o in bpy.data.objects if o.type == "ARMATURE"]


def meshes():
    """The model's meshes. Not the bone display shapes: Blender's glTF importer gives every bone of a skinned GLB a 2 m
    icosphere as its custom shape (collection "glTF_not_exported"); counted as geometry it set the framing and the depth
    range of blender_depth_drivers.py (lane PUPPET, 2026-10-13: May's puppet came out a third of the frame, flat white)."""
    shapes = {pb.custom_shape for a in bpy.data.objects if a.type == "ARMATURE" for pb in a.pose.bones if pb.custom_shape is not None}
    return [o for o in bpy.data.objects if o.type == "MESH" and o not in shapes
            and not any(c.name.startswith("glTF_not_exported") for c in o.users_collection)]


def roots():
    return [o for o in bpy.data.objects if o.parent is None]


def update():
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- geometry

def verts_world(objs, dg=None):
    """Every vertex of the evaluated meshes, in world space, as a list of Vectors (the armature's pose applied)."""
    import numpy as np
    dg = dg or bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        ev = o.evaluated_get(dg)
        try:
            me = ev.to_mesh()
        except RuntimeError:
            continue
        if me is None or len(me.vertices) == 0:
            ev.to_mesh_clear()
            continue
        arr = np.empty(len(me.vertices) * 3, dtype=np.float64)
        me.vertices.foreach_get("co", arr)
        arr = arr.reshape(-1, 3)
        mw = np.array(ev.matrix_world, dtype=np.float64)
        w = arr @ mw[:3, :3].T + mw[:3, 3]
        ev.to_mesh_clear()
        pts.append(w)
    if not pts:
        return None
    return np.concatenate(pts, axis=0)


def bbox(objs, dg=None):
    """(min, max) of the evaluated meshes in world space; None without geometry."""
    w = verts_world(objs, dg)
    if w is None:
        return None
    return Vector(w.min(axis=0).tolist()), Vector(w.max(axis=0).tolist())


def set_frame(f):
    i = int(math.floor(f))
    scene().frame_set(i, subframe=f - i)
    update()


def auto_scale(mode="auto"):
    """pose_driver's rule: a model taller than 20 units is in centimetres and is scaled to metres. Returns the factor."""
    objs = roots()
    if not objs:
        return 1.0
    factor = 1.0
    if mode in ("auto", "", None):
        arm = armatures()
        if arm:
            h = max(o.dimensions.z for o in arm)
        else:
            bb = bbox(meshes())
            h = (bb[1] - bb[0]).z if bb else 0.0
            h = max(h, max((bb[1] - bb[0]).x, (bb[1] - bb[0]).y) if bb else 0.0)
        if h > 20.0:
            factor = 0.01
    else:
        try:
            factor = float(mode)
        except ValueError:
            factor = 1.0
    if abs(factor - 1.0) > 1e-9:
        for o in objs:
            o.scale = Vector(o.scale) * factor
            o.location = Vector(o.location) * factor
        update()
        print("blender_ref: scaled x%g (%s)" % (factor, "a centimetre model" if factor == 0.01 else "scale="))
    return factor


# ---------------------------------------------------------------- actions

def all_actions():
    return list(bpy.data.actions)


def find_action(name=None, arm=None):
    """By exact name, by the part after the last '|' (Blender's 'Armature|Armature|walk'), or by a unique case-insensitive
    piece; without a name the armature's own action, else the first action; None when the file has none."""
    acts = all_actions()
    if not acts:
        return None
    if name:
        for a in acts:
            if a.name == name:
                return a
        for a in acts:
            if a.name.endswith("|" + name) or a.name.split("|")[-1] == name:
                return a
        low = [a for a in acts if name.lower() in a.name.lower()]
        if len(low) == 1:
            return low[0]
        raise SystemExit("blender_ref: no action %r in %s" % (name, [a.name for a in acts]))
    if arm is not None and arm.animation_data and arm.animation_data.action:
        return arm.animation_data.action
    return acts[0]


def use_action(arm, act):
    """Plays `act` on `arm` (Blender 4.4+ layered actions: the slot must be picked too or nothing moves)."""
    if arm.animation_data is None:
        arm.animation_data_create()
    ad = arm.animation_data
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None) and len(act.slots) > 0:
        try:
            ad.action_slot = act.slots[0]
        except Exception as e:  # a slot that does not fit the armature: the action still plays through the old path
            print("blender_ref: action_slot not set (%s)" % e)
    return act


def action_info(act, fps):
    f0, f1 = act.frame_range[0], act.frame_range[1]
    return {"name": act.name, "frame_range": [round(f0, 2), round(f1, 2)], "frames": int(round(f1 - f0)),
            "fps": fps, "seconds": round((f1 - f0) / float(fps), 3) if fps else None}


def main_armature():
    arms = armatures()
    if not arms:
        return None
    for a in arms:
        if a.animation_data and a.animation_data.action:
            return a
    return arms[0]


# ---------------------------------------------------------------- the rig

def bone_alias(arm, rigmap=None):
    """{mixamo-style name: pose bone} for the armature: a 'mixamorig:' prefix stripped, then `rigmap` {model: mixamo}."""
    rigmap = rigmap or {}
    out = {}
    for b in arm.pose.bones:
        out[rigmap.get(b.name, strip_prefix(b.name))] = b
    return out


def rig_guess(names):
    stripped = {strip_prefix(n) for n in names}
    if not names:
        return "none"
    if all(c in stripped for c in MIXAMO_CORE):
        return "mixamo"
    if "Bone_SM_Pelvis" in stripped:
        return "sm"
    return "other"


_SIDE_L = re.compile(r"(^|[^a-z])(l|left|lft)([^a-z]|$)|left", re.I)
_SIDE_R = re.compile(r"(^|[^a-z])(r|right|rgt)([^a-z]|$)|right", re.I)
_PARTS = [  # (mixamo part, sided?, pattern): the first match wins, so the specific words come before the plain ones
    ("ToeBase", True, r"toe|ball"),
    ("Foot", True, r"foot|ankle"),
    ("UpLeg", True, r"upleg|up_leg|upperleg|upper_leg|thigh|femur"),
    ("Leg", True, r"lowerleg|lower_leg|calf|shin|knee|tibia|(^|[^a-z])leg"),
    ("Hand", True, r"(^|[^a-z])hand($|[^a-z])|wrist"),
    ("ForeArm", True, r"forearm|fore_arm|lowerarm|lower_arm|elbow"),
    ("Arm", True, r"upperarm|upper_arm|uparm|(^|[^a-z])arm($|[^a-z])"),
    ("Shoulder", True, r"clavicle|shoulder|collar"),
    ("Hips", False, r"hips|pelvis"),
    ("Spine", False, r"spine|chest|torso"),
    ("Neck", False, r"neck"),
    ("Head", False, r"head"),
]


def rigmap_guess(names):
    """A first guess at {mixamo name: model bone} for a rig with other names (the bone-map form starts from it); None
    where no bone fits. Fingers, twist/roll and helper bones are left out."""
    out = {n: None for n in MIXAMO_NAMES}
    taken = set()
    spines = []
    for raw in names:
        n = strip_prefix(raw)
        # CamelCase split so 'LeftForeArm' reads as 'left_fore_arm' (HumanIK's Character1_LeftForeArm, and the like)
        low = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", n).lower()
        if re.search(r"twist|roll|guide|helper|ik_|_ik|ctrl|control|finger|thumb|index|middle|ring|pinky|end$", low):
            continue
        side = ""
        if _SIDE_L.search(n) and not _SIDE_R.search(n):
            side = "Left"
        elif _SIDE_R.search(n) and not _SIDE_L.search(n):
            side = "Right"
        for part, sided, pat in _PARTS:
            if re.search(pat, low):
                if sided and not side:
                    break
                key = (side + part) if sided else part
                if key == "Spine":
                    spines.append(raw)
                    break
                if out.get(key) is None and raw not in taken:
                    out[key] = raw
                    taken.add(raw)
                break
    if spines:
        spines.sort()
        out["Spine"] = spines[0]
        if len(spines) > 1:
            out["Spine1"] = spines[1]
    return out


def forward_guess(arm, alias):
    """Where the figure faces: the feet (toe minus ankle) of a humanoid rig, else its hips and shoulders (left minus right,
    turned square), else Blender's -Y. Returns (axis label, yaw degrees, basis)."""
    up = Vector((0, 0, 1))
    fwd = Vector((0, 0, 0))
    basis = "default"
    if arm is not None and alias:
        def head(name):
            return arm.matrix_world @ alias[name].head
        for side in ("Left", "Right"):
            if side + "ToeBase" in alias and side + "Foot" in alias:
                v = head(side + "ToeBase") - head(side + "Foot")
                v.z = 0.0
                fwd += v
        if fwd.length > 1e-6:
            basis = "feet"
        else:
            lat = Vector((0, 0, 0))
            for l_b, r_b in (("LeftUpLeg", "RightUpLeg"), ("LeftArm", "RightArm"), ("LeftShoulder", "RightShoulder")):
                if l_b in alias and r_b in alias:
                    v = head(l_b) - head(r_b)
                    v.z = 0.0
                    lat += v
            if lat.length > 1e-6:
                fwd = lat.cross(up)
                basis = "body"
    if fwd.length <= 1e-6:
        fwd = Vector((0, -1, 0))
    fwd.normalize()
    yaw = math.degrees(math.atan2(fwd.y, fwd.x))
    labels = {"+X": 0.0, "+Y": 90.0, "-X": 180.0, "-Y": -90.0}
    label = min(labels, key=lambda k: abs((yaw - labels[k] + 180.0) % 360.0 - 180.0))
    return label, round(yaw, 1), basis, fwd


def forward_vector(spec, guess_vec=None):
    """forward= as a unit vector: -Y (default), +Y, -X, +X, auto (the probe's guess) or yaw:<degrees>."""
    s = (spec or "-Y").strip()
    table = {"-Y": (0, -1, 0), "+Y": (0, 1, 0), "Y": (0, 1, 0), "-X": (-1, 0, 0), "+X": (1, 0, 0), "X": (1, 0, 0)}
    if s.upper() in table:
        return Vector(table[s.upper()])
    if s.lower() == "auto":
        return Vector(guess_vec) if guess_vec is not None else Vector((0, -1, 0))
    if s.lower().startswith("yaw:"):
        a = math.radians(float(s.split(":", 1)[1]))
        return Vector((math.cos(a), math.sin(a), 0.0))
    raise SystemExit("blender_ref: forward=%r is not -Y, +Y, -X, +X, auto or yaw:<deg>" % spec)


# ---------------------------------------------------------------- camera and renders

def camera_rule(mn, mx, death=False):
    """blender_beetle.py's framing: the target a little below the middle, the extent the biggest side of the box, the camera
    three extents away, 1.45 extents wide (1.6 for a death, which sprawls)."""
    target = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z + (mx.z - mn.z) * 0.42))
    extent = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, 1e-6)
    return target, extent, extent * 3.0, extent * (1.6 if death else 1.45)


def bearing(fwd, yaw_deg):
    """The horizontal direction from the model to a camera `yaw_deg` round from its front: 0 looks at its face, 90 sees it
    from its right (it faces screen-right, like the painted side views), 180 from behind."""
    a = -math.radians(yaw_deg)
    return Vector((fwd.x * math.cos(a) - fwd.y * math.sin(a), fwd.x * math.sin(a) + fwd.y * math.cos(a), 0.0))


def make_camera(size):
    sc = scene()
    cam_data = bpy.data.cameras.new("ref_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("ref_cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x = size
    sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    return cam


def place_camera(cam, target, dist, fwd, yaw_deg, pitch_deg, ortho):
    d = bearing(fwd, yaw_deg)
    pitch = math.radians(pitch_deg)
    pos = target + d * dist * math.cos(pitch) + Vector((0, 0, dist * math.sin(pitch)))
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - pos).to_track_quat("-Z", "Y")
    cam.data.ortho_scale = ortho
    cam.data.clip_start = max(dist * 0.01, 0.001)
    cam.data.clip_end = dist * 4.0
    update()


def fit_camera(cam, objs, margin=1.10):
    """The orthographic frame tightened round what the camera sees (the icon render): the projected box of every vertex,
    centred, the wider side times `margin`."""
    import numpy as np
    update()
    w = verts_world(objs)
    if w is None:
        return
    inv = np.array(cam.matrix_world.inverted(), dtype=np.float64)
    c = w @ inv[:3, :3].T + inv[:3, 3]
    x0, y0 = c[:, 0].min(), c[:, 1].min()
    x1, y1 = c[:, 0].max(), c[:, 1].max()
    span = max(x1 - x0, y1 - y0, 1e-6) * margin
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    right = cam.matrix_world.to_3x3() @ Vector((1, 0, 0))
    up = cam.matrix_world.to_3x3() @ Vector((0, 1, 0))
    cam.location = cam.location + right * cx + up * cy
    cam.data.ortho_scale = span
    update()


def _nodes(datablock):
    """The node tree of a material or world, created when Blender still needs `use_nodes` (deprecated, gone in 6.0)."""
    if getattr(datablock, "node_tree", None) is None and hasattr(datablock, "use_nodes"):
        datablock.use_nodes = True
    return datablock.node_tree


def black_world():
    sc = scene()
    w = bpy.data.worlds.new("ref_world")
    sc.world = w
    w.color = (0.0, 0.0, 0.0)
    nt = _nodes(w)
    if nt is not None:
        bg = nt.nodes.get("Background")
        if bg is not None:
            bg.inputs[0].default_value = (0, 0, 0, 1)
    return w


def clay_material():
    m = bpy.data.materials.new("ref_clay")
    nt = _nodes(m)
    b = nt.nodes.get("Principled BSDF") if nt else None
    if b is not None:
        b.inputs["Base Color"].default_value = CLAY
    m.diffuse_color = CLAY
    return m


def look_material(albedo):
    """The model's colour map on a plain shader (Sketchfab FBX files carry texture paths that do not exist here)."""
    m = bpy.data.materials.new("ref_look")
    nt = _nodes(m)
    b = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.abspath(albedo))
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    nt.nodes.active = tex
    return m


def has_image_texture(obj):
    for s in obj.material_slots:
        m = s.material
        if m is None or m.node_tree is None:
            continue
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None and n.image.has_data:
                return True
    return False


def materials_backup(objs):
    return [(o, [s.material for s in o.material_slots]) for o in objs]


def set_material(objs, m):
    for o in objs:
        if not o.material_slots:
            o.data.materials.append(m)
        for s in o.material_slots:
            s.material = m


def restore_materials(backup):
    for o, mats in backup:
        for s, m in zip(o.material_slots, mats):
            s.material = m


def workbench(color_type, screen, transparent=False):
    """Studio-lit workbench with cavity and an outline, like blender_beetle.py; the background the screen colour or none."""
    sc = scene()
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = color_type
    sh.show_cavity = True
    sh.show_object_outline = True
    sh.object_outline_color = (0.05, 0.02, 0.02)
    sh.show_shadows = False
    sh.background_type = "VIEWPORT"
    sh.background_color = tuple(screen[:3])
    sc.render.film_transparent = bool(transparent)
    sc.render.image_settings.color_mode = "RGBA" if transparent else "RGB"


def render(path):
    sc = scene()
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sc.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)
    return path


def contact_sheet(paths, out, cell=192, gap=4, bg=(0.12, 0.12, 0.14, 1.0)):
    """The PNGs side by side in one row (numpy through Blender's images: there is no PIL inside Blender)."""
    import numpy as np
    tiles = []
    for p in paths:
        if not p or not os.path.exists(p):
            continue
        img = bpy.data.images.load(os.path.abspath(p))
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        if (w, h) != (cell, cell):
            ys = (np.arange(cell) * h // cell).clip(0, h - 1)
            xs = (np.arange(cell) * w // cell).clip(0, w - 1)
            px = px[ys][:, xs]
        tiles.append(px)
        bpy.data.images.remove(img)
    if not tiles:
        return None
    W = len(tiles) * cell + (len(tiles) + 1) * gap
    H = cell + 2 * gap
    sheet = np.empty((H, W, 4), dtype=np.float32)
    sheet[:, :] = bg
    for i, t in enumerate(tiles):
        x = gap + i * (cell + gap)
        a = t[:, :, 3:4]
        sheet[gap:gap + cell, x:x + cell, :3] = t[:, :, :3] * a + sheet[gap:gap + cell, x:x + cell, :3] * (1.0 - a)
        sheet[gap:gap + cell, x:x + cell, 3] = 1.0
    img = bpy.data.images.new("contact", W, H, alpha=True)
    img.pixels.foreach_set(sheet.reshape(-1))
    img.filepath_raw = os.path.abspath(out)
    img.file_format = "PNG"
    img.save()
    return out


# ---------------------------------------------------------------- the probe

def probe(src, scale_applied, albedo=None):
    sc = scene()
    fps = sc.render.fps
    arms = armatures()
    mesh_objs = meshes()
    arm = main_armature()
    names = [b.name for b in arm.data.bones] if arm else []
    guess = rig_guess(names)
    rmap = rigmap_guess(names) if guess == "other" else None
    alias = bone_alias(arm, {v: k for k, v in rmap.items() if v} if rmap else None) if arm else {}
    if guess == "sm":
        alias = bone_alias(arm, {"Bone_SM_Pelvis": "Hips", "Bone_SM_Spine1": "Spine", "Bone_SM_Neck": "Neck", "Bone_SM_Head": "Head",
                                 "Bone_SM_UpperArm_L": "LeftArm", "Bone_SM_UpperArm_R": "RightArm", "Bone_SM_Thigh_L": "LeftUpLeg",
                                 "Bone_SM_Thigh_R": "RightUpLeg", "Bone_SM_Ankle_L": "LeftFoot", "Bone_SM_Ankle_R": "RightFoot",
                                 "Bone_SM_Toes_L": "LeftToeBase", "Bone_SM_Toes_R": "RightToeBase"})
    humanoid = guess in ("mixamo", "sm") or (rmap is not None and all(rmap.get(c) for c in MIXAMO_CORE))
    acts = [action_info(a, fps) for a in all_actions()]
    label, yaw, basis, fwd_vec = forward_guess(arm, alias)
    bb = bbox(mesh_objs)
    dims = [round(v, 4) for v in (bb[1] - bb[0])] if bb else [0, 0, 0]
    mesh_rows = []
    for o in mesh_objs:
        mesh_rows.append({"name": o.name, "verts": len(o.data.vertices), "has_image_texture": has_image_texture(o),
                          "materials": [s.material.name for s in o.material_slots if s.material]})
    has_tex = any(r["has_image_texture"] for r in mesh_rows)
    can = {"icon": bool(mesh_objs), "look": bool(mesh_objs),
           "pose_drivers": bool(arm) and bool(acts) and humanoid,
           "depth_drivers": bool(arm) and bool(acts) and bool(mesh_objs)}
    if not arms and not mesh_objs:
        message = "Not a model Blender can read: no mesh and no armature came out of the file."
    elif not arms:
        message = "A mesh without a rig: it can be the icon's reference and the look reference, but cannot drive a walk. " + INSERT_HINT
    elif not acts:
        message = ("This model has no animation clip, so it cannot drive a walk; it can be the icon's reference and the look "
                   "reference. " + INSERT_HINT)
    elif guess == "mixamo":
        message = "A Mixamo-style humanoid with %d clip%s: pose drivers (tools/pose_driver.py) and depth drivers both work." % (len(acts), "" if len(acts) == 1 else "s")
    elif guess == "sm":
        message = "A Cinema 4D Bone_SM_* humanoid with %d clip%s: pose drivers with rig=sm, or depth drivers." % (len(acts), "" if len(acts) == 1 else "s")
    elif humanoid:
        message = "A humanoid rig with its own bone names: pose drivers after the bone map is checked (rigmap), or depth drivers."
    else:
        message = "A rigged model with %d clip%s that is not a humanoid: depth drivers of its own clips (choose the walk, the death)." % (len(acts), "" if len(acts) == 1 else "s")
    return {"src": src, "scale_applied": scale_applied, "fps": fps,
            "armatures": [{"name": a.name, "bones": [b.name for b in a.data.bones],
                           "bone_parents": {b.name: (b.parent.name if b.parent else None) for b in a.data.bones}} for a in arms],
            "actions": acts, "meshes": mesh_rows, "dimensions": dims, "has_image_texture": has_tex,
            "rig_guess": guess, "rigmap_guess": rmap, "humanoid": humanoid,
            "forward_guess": label, "forward_yaw_deg": yaw, "forward_basis": basis,
            "albedo_guess": os.path.relpath(albedo, REPO).replace("\\", "/") if albedo and os.path.exists(albedo) else None,
            "can": can, "message": message}


# ---------------------------------------------------------------- main

def main():
    A = args()
    if "src" not in A:
        raise SystemExit(__doc__)
    mode = A.get("mode", "probe")
    out = os.path.abspath(A.get("out", os.path.join(os.path.dirname(os.path.abspath(A["src"])), "ref")))
    os.makedirs(out, exist_ok=True)
    src = import_model(A["src"])
    sc = scene()
    factor = auto_scale(A.get("scale", "auto"))
    arm = main_armature()
    act = None
    if all_actions() and arm is not None:
        act = find_action(A.get("action"), arm)
        use_action(arm, act)
        f = act.frame_range[0]
        if "frame" in A:
            f = float(A["frame"])
        elif "at" in A:
            f = act.frame_range[0] + float(A["at"]) * sc.render.fps
        set_frame(f)
    albedo = A.get("albedo") or (None if any(has_image_texture(o) for o in meshes()) else find_albedo(src))
    info = probe(src, factor, albedo)
    info["posed"] = {"action": act.name if act else None, "frame": sc.frame_current}
    json.dump(info, open(os.path.join(out, "probe.json"), "w", encoding="utf-8", newline="\n"), indent=1, ensure_ascii=False)
    print("blender_ref: probe: rig %s, %d action(s), forward %s (%s), %s" % (info["rig_guess"], len(info["actions"]), info["forward_guess"], info["forward_basis"], info["message"]))
    mesh_objs = meshes()
    if not mesh_objs:
        print("blender_ref: nothing to render")
        return
    label, yaw, basis, fwd_vec = forward_guess(arm, bone_alias(arm) if arm else {})
    fwd = forward_vector(A.get("forward", "-Y"), fwd_vec)
    screen = parse_rgb(A.get("screen"), (0.0, 1.0, 0.0))
    pitch = float(A.get("pitch", 25.0))
    size = int(A.get("size", 1024))
    cam = make_camera(640)
    backup = materials_backup(mesh_objs)
    clay = clay_material()
    look = look_material(albedo) if albedo else None
    bb = bbox(mesh_objs)
    target, extent, dist, ortho = camera_rule(*bb)

    def textured():
        if look is not None:
            set_material(mesh_objs, look)
            workbench("TEXTURE", screen, transparent=sc.render.film_transparent)
        else:
            restore_materials(backup)
            workbench("TEXTURE" if info["has_image_texture"] else "MATERIAL", screen, transparent=sc.render.film_transparent)

    def icon_render(path, px):
        sc.render.resolution_x = sc.render.resolution_y = px
        place_camera(cam, target, dist, fwd, -float(A.get("icon_yaw", 35.0)), float(A.get("icon_pitch", 20.0)), ortho)
        fit_camera(cam, mesh_objs)
        sc.render.film_transparent = "screen" not in A
        textured()
        render(path)
        sc.render.film_transparent = False

    if mode in ("icon", "all"):
        icon_render(os.path.join(out, "icon_ref.png"), size)
        print("blender_ref: wrote icon_ref.png (%d px, yaw %s, pitch %s, %s)" % (size, A.get("icon_yaw", 35), A.get("icon_pitch", 20), "transparent" if "screen" not in A else "on the screen colour"))
    if mode in ("views", "all"):
        sc.render.resolution_x = sc.render.resolution_y = 640
        for view, deg in VIEWS.items():
            place_camera(cam, target, dist, fwd, deg, pitch, ortho)
            set_material(mesh_objs, clay)
            workbench("MATERIAL", screen)
            render(os.path.join(out, view, "clay.png"))
            textured()
            render(os.path.join(out, view, "look.png"))
            print("blender_ref: wrote %s/clay.png and look.png" % view)
    if mode in ("probe", "all"):
        tmp = os.path.join(out, "_thumbs")
        os.makedirs(tmp, exist_ok=True)
        paths = []
        sc.render.resolution_x = sc.render.resolution_y = 192
        for view, deg in VIEWS.items():
            place_camera(cam, target, dist, fwd, deg, pitch, ortho)
            textured()
            paths.append(render(os.path.join(tmp, view + ".png")))
        icon_render(os.path.join(tmp, "icon.png"), 192)
        paths.append(os.path.join(tmp, "icon.png"))
        contact_sheet(paths, os.path.join(out, "thumbs.png"))
        for p in paths:
            try:
                os.remove(p)
            except OSError:
                pass
        try:
            os.rmdir(tmp)
        except OSError:
            pass
        print("blender_ref: wrote thumbs.png (front, fd, side, bd, back, icon)")
    restore_materials(backup)
    print("blender_ref: done ->", out)


if __name__ == "__main__":
    main()

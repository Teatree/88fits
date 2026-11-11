"""Pass 136 (lane PLACED; Garry: "Let's make it so the 'stink' of the Skull that stays on is actually around a skull 3d
object sitting on the ground, which disappears once the effect is off"): the Skull Rain's skull that sits on the sand in
its poison cloud (core/systems/GroundSkulls.gd).

Pass 143 (Garry: "The skull it leaves behind is too big. Make it half as big. Make it more white so it reads better over
the yellow sand. Also, it doesn't look much like a skull right now. Remodel it."): remodelled as a skull rather than a
ball with a box under it: a cranium longer than it is wide, a brow over two big deep eye sockets, cheekbones, an upper jaw
with a row of square teeth over a dark mouth line and a lower jaw with its own teeth, an upside-down heart of a nose. One
mesh, smooth shaded (a voxel remesh of the joined parts, then the holes cut), coloured by vertex colours: near-white bone,
a grey shade under the brow, the cheeks and the jaw, the sockets, the nose and the mouth a near-black green with a small
toxic glint at the back of each socket (GroundSkulls' shader makes green glow). Its face looks along Blender -Y, which the
y-up export makes Godot +Z (towards the camera); its base sits on z = 0 (the sand). About 0.5 m wide at scale 1 (the
weapon's `ground_skull.size` sets its size in the game).

  "$BLENDER" -b --python tools/blender_skull_rain.py
    -> game/art/props/skull_rain_skull.glb, tools/dl/p143/SKULL/skull_ref.png (from the game's camera, the face turned up
       as GroundSkulls turns it) and skull_ref34.png (a 3/4 look)
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "skull_rain_skull.glb")
REF_DIR = os.path.join(REPO, "tools", "dl", "p143", "SKULL")


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(r, g, b):
    return (lin(r), lin(g), lin(b), 1.0)


BONE = rgba(0.97, 0.975, 0.98)
BONE_SHADE = rgba(0.82, 0.83, 0.85)
HOLE = rgba(0.07, 0.11, 0.07)
GLINT = rgba(0.30, 0.95, 0.22)

CRANIUM_C = Vector((0.0, 0.035, 0.36))
CRANIUM_R = 0.25
EYES = [Vector((dx, -0.215, 0.285)) for dx in (-0.088, 0.088)]
EYE_R = 0.074
NOSE = Vector((0.0, -0.235, 0.185))
MOUTH_Z = 0.112
MOUTH_Y = -0.19


def sel(objs, active=None):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def apply_mods(o):
    sel([o])
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def boolean(o, cutter, op):
    m = o.modifiers.new("b", "BOOLEAN")
    m.operation = op
    m.object = cutter
    m.solver = "EXACT"
    apply_mods(o)
    bpy.data.objects.remove(cutter, do_unlink=True)


def uv_sphere(r, at, scale=(1, 1, 1), seg=32, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=at)
    o = bpy.context.active_object
    o.scale = scale
    sel([o])
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    return o


def rounded_box(size, at, bevel=0.04, taper=None):
    """A box `size` (x, y, z) at `at`, its edges rounded; `taper(v)` may move its vertices before the rounding."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    o = bpy.context.active_object
    o.scale = size
    sel([o])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if taper:
        for v in o.data.vertices:
            taper(v)
    bev = o.modifiers.new("bev", "BEVEL")
    bev.width = bevel
    bev.segments = 3
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    apply_mods(o)
    return o


def join(objs):
    sel(objs, objs[0])
    bpy.ops.object.join()
    return bpy.context.active_object


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = []
    # the cranium: longer front to back than wide, a little flattened on the sides
    parts.append(uv_sphere(CRANIUM_R, CRANIUM_C, (0.92, 1.08, 0.94)))
    # the brow: a soft ridge across the top of the sockets
    parts.append(uv_sphere(0.11, Vector((0.0, -0.17, 0.355)), (1.85, 0.62, 0.42)))
    # the face under the cranium's front: the upper jaw, narrower towards the teeth

    def face_taper(v):
        if v.co.z < 0.0:
            v.co.x *= 0.78
        if v.co.y < 0.0 and v.co.z < 0.0:
            v.co.y *= 0.92
    parts.append(rounded_box((0.30, 0.25, 0.17), Vector((0.0, -0.075, 0.205)), 0.06, face_taper))
    # the cheekbones, standing out under the outer corners of the sockets
    for dx in (-0.128, 0.128):
        parts.append(uv_sphere(0.058, Vector((dx, -0.135, 0.215)), (1.15, 1.25, 0.8)))

    # the lower jaw: a rounded block under the teeth, the chin narrower than the hinge
    def jaw_taper(v):
        if v.co.y < 0.0:
            v.co.x *= 0.82
        if v.co.z < 0.0:
            v.co.x *= 0.9
    parts.append(rounded_box((0.235, 0.21, 0.085), Vector((0.0, -0.085, 0.05)), 0.035, jaw_taper))
    head = join(parts)
    # one clean skin over the parts, smoothed a little, then light enough for a crowd of them
    rm = head.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.014
    sm = head.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = 4
    apply_mods(head)
    dec = head.modifiers.new("dec", "DECIMATE")
    dec.ratio = 0.22
    apply_mods(head)
    # a flat base so it sits on the sand
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=(0.0, 0.0, -1.0 + 0.008))
    boolean(head, bpy.context.active_object, "DIFFERENCE")
    # the eye sockets: big and deep, a little squarer at the top
    for e in EYES:
        boolean(head, uv_sphere(EYE_R, e, (1.0, 1.15, 1.08), 20, 12), "DIFFERENCE")
    # the nose: an upside-down heart (two lobes over a point)
    for dx in (-0.019, 0.019):
        boolean(head, uv_sphere(0.026, NOSE + Vector((dx, 0.0, 0.006)), (0.85, 1.6, 1.25), 12, 8), "DIFFERENCE")
    bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=0.03, depth=0.09, location=NOSE + Vector((0.0, 0.0, -0.018)),
                                    rotation=(math.radians(90), 0.0, math.radians(180)))
    boolean(head, bpy.context.active_object, "DIFFERENCE")
    # the mouth: a dark line between the jaws, the teeth standing in it
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, MOUTH_Y - 0.03, MOUTH_Z))
    slot = bpy.context.active_object
    slot.scale = (0.205, 0.16, 0.03)
    boolean(head, slot, "DIFFERENCE")
    # the jaw's front at the mouth, measured on the mesh (the remesh and the smoothing moved it in)
    front = [v.co.y for v in head.data.vertices if abs(v.co.x) < 0.03 and abs(v.co.z - MOUTH_Z) < 0.045 and v.co.y < -0.1]
    front_y = min(front) if front else MOUTH_Y
    print("jaw front y", round(front_y, 4))
    teeth = []
    n = 6
    for k in range(n):
        x = -0.075 + 0.15 * k / (n - 1)
        # the row follows the jaw's curve: the outer teeth sit further back
        y = front_y + 0.017 + 0.9 * x * x
        for z0, h in ((MOUTH_Z + 0.016, 0.034), (MOUTH_Z - 0.016, 0.03)):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, z0))
            t = bpy.context.active_object
            t.scale = (0.022, 0.03, h)
            bv = t.modifiers.new("bev", "BEVEL")
            bv.width = 0.006
            bv.segments = 2
            apply_mods(t)
            teeth.append(t)
    head = join([head] + teeth)
    head.name = "SkullRainSkull"
    paint(head)
    sel([head])
    bpy.ops.object.shade_smooth()
    return head


def paint(o):
    me = o.data
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    counts = {}
    for poly in me.polygons:
        c = poly.center
        nrm = poly.normal
        col = BONE
        # a socket's own faces look back at its centre (the cranium's round them look out): dark, a green glint deep in
        for e in EYES:
            if (c - e).length < EYE_R * 1.45 and (e - c).normalized().dot(nrm) > 0.2:
                deep = e + Vector((0.0, EYE_R * 1.1, 0.0))
                col = GLINT if (c - deep).length < EYE_R * 0.42 else HOLE
        if (c - NOSE).length < 0.07 and c.y > -0.26 and (nrm.y > -0.5 or (NOSE - c).normalized().dot(nrm) > 0.0):
            if abs(c.x) < 0.045 and -0.05 < c.z - NOSE.z < 0.045 and c.y > NOSE.y - 0.01:
                col = HOLE
        # the mouth line's inside (not the teeth, which stand in front of it)
        if abs(c.z - MOUTH_Z) < 0.016 and c.y > MOUTH_Y - 0.012 and abs(c.x) < 0.1:
            col = HOLE
        # a little shade under the brow, the cheekbones and the jaws
        if col == BONE and nrm.z < -0.45:
            col = BONE_SHADE
        for li in poly.loop_indices:
            attr.data[li].color = col
        counts[col] = counts.get(col, 0) + 1
    me.color_attributes.active_color = attr
    print("paint:", {("bone" if k == BONE else "shade" if k == BONE_SHADE else "hole" if k == HOLE else "glint"): v for k, v in counts.items()})


def export(o):
    sel([o])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    kw = dict(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    print("exported", OUT, "tris", sum(len(p.vertices) - 2 for p in o.data.polygons))


def render(o):
    """The game's look (the camera ~50 degrees down, the face turned up 0.55 rad as GroundSkulls turns it) and a 3/4 look,
    on sand, the vertex colours as the base colour."""
    m = bpy.data.materials.new("skull")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    vc = nt.nodes.new("ShaderNodeAttribute")
    vc.attribute_name = "Col"
    nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    o.data.materials.append(m)
    sc = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=6.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("sand")
    gm.use_nodes = True
    gm.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = rgba(0.93, 0.78, 0.48)
    ground.data.materials.append(gm)
    bpy.ops.object.light_add(type="SUN", location=(1, -1, 3))
    sun = bpy.context.active_object
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(35), 0, math.radians(25))
    w = sc.world or bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.6, 0.6, 1.0)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    names = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in names else "BLENDER_EEVEE"
    sc.render.resolution_x = 512
    sc.render.resolution_y = 512
    sc.view_settings.view_transform = "Standard"
    os.makedirs(REF_DIR, exist_ok=True)
    bpy.ops.object.camera_add(location=(0, 0, 0))
    cam = bpy.context.active_object
    sc.camera = cam
    for name, rot, cam_at in (("skull_ref.png", 0.55, Vector((0.0, -1.35, 1.6))), ("skull_ref34.png", 0.0, Vector((0.75, -1.1, 0.75)))):
        o.rotation_euler = (-rot, 0.0, 0.0)
        o.location = (0.0, 0.0, 0.0 if rot == 0.0 else 0.06)
        cam.location = cam_at
        d = Vector((0, 0, 0.22)) - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(REF_DIR, name)
        bpy.ops.render.render(write_still=True)
        print("rendered", sc.render.filepath)


if __name__ == "__main__":
    o = build()
    export(o)
    try:
        render(o)
    except Exception as ex:  # the renders are only a look for the eye
        print("render failed:", ex)

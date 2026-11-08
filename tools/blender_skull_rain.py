"""Pass 136 (lane PLACED; Garry: "Let's make it so the 'stink' of the Skull that stays on is actually around a skull 3d
object sitting on the ground, which disappears once the effect is off"): the Skull Rain's skull that sits on the sand in
its poison cloud (core/systems/GroundSkulls.gd).

A cartoon skull, one mesh, coloured by vertex colours (bone, toxic green eye sockets and nose, a dark mouth line with
teeth): a round cranium with a cheek-and-jaw block below its front, eye sockets and a nose cut in by booleans and painted
by where each face lies. Its face looks along Blender -Y, which the y-up export makes Godot +Z (towards the camera);
its base sits on z = 0 (the sand). About 0.6 m wide at scale 1.

  "$BLENDER" -b --python tools/blender_skull_rain.py
    -> game/art/props/skull_rain_skull.glb, tools/dl/p136/PLACED/skull_ref.png (a 3/4 render on green)
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "skull_rain_skull.glb")
REF = os.path.join(REPO, "tools", "dl", "p136", "PLACED", "skull_ref.png")


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(r, g, b):
    return (lin(r), lin(g), lin(b), 1.0)


BONE = rgba(0.95, 0.92, 0.82)
BONE_SHADE = rgba(0.84, 0.80, 0.68)
GREEN = rgba(0.45, 1.0, 0.30)
GREEN_DEEP = rgba(0.16, 0.55, 0.12)
MOUTH = rgba(0.18, 0.30, 0.12)

CRANIUM_C = Vector((0.0, 0.03, 0.40))
CRANIUM_R = 0.30
EYES = [Vector((dx, -0.275, 0.325)) for dx in (-0.115, 0.115)]
EYE_R = 0.098
NOSE = Vector((0.0, -0.285, 0.195))
NOSE_R = 0.04


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


def uv_sphere(r, at, scale=(1, 1, 1), seg=28, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=at)
    o = bpy.context.active_object
    o.scale = scale
    sel([o])
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    return o


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # the cranium, a little longer front to back and flattened under
    head = uv_sphere(CRANIUM_R, CRANIUM_C, (1.0, 1.06, 0.95))
    # the cheeks and the jaw: a rounded block under the front of the cranium, narrower than it
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, -0.09, 0.15))
    jaw = bpy.context.active_object
    jaw.scale = (0.44, 0.34, 0.30)
    sel([jaw])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    # narrower at the chin than at the cheekbones
    for v in jaw.data.vertices:
        if v.co.z < 0.0:
            v.co.x *= 0.72
    bev = jaw.modifiers.new("bev", "BEVEL")
    bev.width = 0.07
    bev.segments = 3
    sub = jaw.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    apply_mods(jaw)
    boolean(head, jaw, "UNION")
    # a flat base so it sits on the sand
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=(0.0, 0.0, -1.0 + 0.012))
    boolean(head, bpy.context.active_object, "DIFFERENCE")
    # the eye sockets and the nose
    for e in EYES:
        boolean(head, uv_sphere(EYE_R, e, (1.0, 1.0, 1.12), 16, 10), "DIFFERENCE")
    boolean(head, uv_sphere(NOSE_R, NOSE, (0.8, 1.0, 1.25), 12, 8), "DIFFERENCE")
    # the mouth: a thin slot across the jaw's front
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, -0.28, 0.085))
    slot = bpy.context.active_object
    slot.scale = (0.22, 0.12, 0.026)
    boolean(head, slot, "DIFFERENCE")
    head.name = "SkullRainSkull"
    paint(head)
    sel([head])
    bpy.ops.object.shade_flat()
    return head


def paint(o):
    me = o.data
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for poly in me.polygons:
        c = poly.center
        n = poly.normal
        col = BONE
        # the faces inside a socket: green, deeper at the back of it
        # (a socket's own faces look back at its centre: the cranium's round them look out)
        for e in EYES:
            if (c - e).length < EYE_R * 1.3 and (e - c).normalized().dot(n) > 0.3:
                col = GREEN if (c - e).y < 0.03 else GREEN_DEEP
        if (c - NOSE).length < NOSE_R * 1.6 and (NOSE - c).normalized().dot(n) > 0.3:
            col = GREEN_DEEP
        # the mouth slot's inside
        if abs(c.z - 0.085) < 0.028 and c.y < -0.17 and abs(c.x) < 0.12 and n.y > -0.7:
            col = MOUTH
        # the teeth: gaps every 0.05 m along the slot's lips on the front
        if col == BONE and c.y < -0.2 and abs(c.x) < 0.11 and 0.03 < c.z < 0.14 and n.y < -0.5:
            if (int(math.floor((c.x + 0.11) / 0.044)) % 2) == 1:
                col = BONE_SHADE
        # a little shade under the brow and on the cheeks' undersides
        if col == BONE and n.z < -0.4:
            col = BONE_SHADE
        for li in poly.loop_indices:
            attr.data[li].color = col
    me.color_attributes.active_color = attr


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
    """A 3/4 look from above-front on green, the vertex colours as the base colour."""
    m = bpy.data.materials.new("skull")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.8
    o.data.materials.append(m)
    sc = bpy.context.scene
    bpy.ops.object.camera_add(location=(0.5, -1.3, 1.9))
    cam = bpy.context.active_object
    d = Vector((0, 0, 0.25)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    bpy.ops.object.light_add(type="SUN", location=(1, -1, 3))
    bpy.context.active_object.data.energy = 1.6
    bpy.context.active_object.rotation_euler = (math.radians(40), 0, math.radians(30))
    w = sc.world or bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.45, 0.45, 1.0)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x = 512
    sc.render.resolution_y = 512
    sc.view_settings.view_transform = "Standard"
    os.makedirs(os.path.dirname(REF), exist_ok=True)
    sc.render.filepath = REF
    bpy.ops.render.render(write_still=True)
    print("rendered", REF)


if __name__ == "__main__":
    o = build()
    export(o)
    try:
        render(o)
    except Exception as ex:  # the render is only a look for the eye
        print("render failed:", ex)

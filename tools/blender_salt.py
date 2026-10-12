"""The Salt weapon's shaker (pass 69): a ribbed glass salt shaker with a chrome cap, exported as GLB for the SaltShaker
behaviour (game/art/props/salt_shaker.glb) and rendered on a transparent film as the reference the icons are painted from
(tools/dl/salt_ref.png; sea_salt_ref.png and hiwa_kai_ref.png with pink and black contents, for the mutation and the
evolution icons).

The shaker stands up +Z (the y-up export makes that Godot's +Y) with its origin at the middle of its height, so the
behaviour tilts and shakes it about its middle. The parts keep their names, since the game finds them:
  "Body"      the glass: sixteen flat facets, a little narrower at the top, see-through (alpha blend);
  "Contents"  the salt inside, filling two thirds of it with a low mound on top: its own material, so a mutation tints
              it (Sea Salt pink, Hiwa Kai black);
  "Cap"       the chrome screw band and dome;
  "Holes"     the seven dark pour holes in the dome.
"Spout" is an empty at the top of the dome, where the game lets its grains fall from.

  "$BLENDER" -b --python tools/blender_salt.py
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "salt_shaker.glb")
DL = os.path.join(REPO, "tools", "dl")
MATS = {}

BODY_Z0, BODY_Z1 = -0.14, 0.10
BODY_R0, BODY_R1 = 0.078, 0.068
CAP_Z0, CAP_Z1 = 0.098, 0.13
CAP_R = 0.071
DOME_H = 0.042
FILL_TOP = 0.035

LOOKS = {
    "salt": (246, 246, 240),
    "sea_salt": (244, 163, 196),
    "hiwa_kai": (26, 26, 26),
}


def mat(name, rgb, rough=0.6, metal=0.0, alpha=1.0, glow=None, strength=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    col = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        # Blender 4.2+: the blended render method is what the glTF exporter writes as alphaMode BLEND
        try:
            m.surface_render_method = "BLENDED"
        except AttributeError:
            m.blend_method = "BLEND"
    if glow:
        bsdf.inputs["Emission Color"].default_value = (glow[0] / 255.0, glow[1] / 255.0, glow[2] / 255.0, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (col[0], col[1], col[2], alpha)
    MATS[name] = m
    return m


def part(op, m, **kw):
    op(**kw)
    o = bpy.context.active_object
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def cyl(r, depth, loc, m, verts=16, r2=None):
    return part(bpy.ops.mesh.primitive_cone_add, m, vertices=verts, radius1=r, radius2=r if r2 is None else r2,
                depth=depth, location=loc)


def ball(r, loc, m, seg=20, rings=10, sz=1.0):
    o = part(bpy.ops.mesh.primitive_uv_sphere_add, m, radius=r, location=loc, segments=seg, ring_count=rings)
    o.scale = (1.0, 1.0, sz)
    return o


def join(objs, name, smooth=False):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if smooth:
        bpy.ops.object.shade_smooth()
    else:
        bpy.ops.object.shade_flat()
    return o


def empty(name, loc):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.empty_display_size = 0.02
    e.location = loc
    return e


def dome_z(r):
    """The dome's height over the band at `r` from the axis (an ellipse of DOME_H over CAP_R)."""
    f = max(0.0, 1.0 - (r / CAP_R) ** 2)
    return CAP_Z1 + DOME_H * math.sqrt(f)


def build(key):
    glass = mat("glass", (196, 224, 242), rough=0.08, metal=0.0, alpha=0.24)
    salt = mat(key + "_salt", LOOKS[key], rough=0.92)
    # a bright silver that stays silver in the game: half metal (a full one mirrors the orange sand and reads as copper)
    # and a faint cool glow of its own
    chrome = mat("chrome", (226, 230, 238), rough=0.22, metal=0.5, glow=(200, 208, 222), strength=0.18)
    hole = mat("hole", (22, 22, 26), rough=0.7)
    # the glass: sixteen facets (flat shaded, they catch the light like a ribbed diner shaker), a thick base ring
    h = BODY_Z1 - BODY_Z0
    body = [cyl(BODY_R0, h, (0, 0, (BODY_Z0 + BODY_Z1) * 0.5), glass, 16, r2=BODY_R1)]
    body.append(cyl(BODY_R0 * 1.03, 0.018, (0, 0, BODY_Z0 + 0.009), glass, 16))
    bd = join(body, "Body")
    # the salt inside: a little inside the glass, two thirds full, a low mound on top
    fill_h = FILL_TOP - (BODY_Z0 + 0.012)
    r_top = BODY_R0 + (BODY_R1 - BODY_R0) * ((FILL_TOP - BODY_Z0) / h)
    cont = [cyl(BODY_R0 - 0.009, fill_h, (0, 0, BODY_Z0 + 0.012 + fill_h * 0.5), salt, 16, r2=r_top - 0.009)]
    cont.append(ball(r_top - 0.012, (0, 0, FILL_TOP), salt, 16, 8, sz=0.28))
    ct = join(cont, "Contents", smooth=True)
    # the chrome cap: a ridged screw band and a dome
    cap = [cyl(CAP_R, CAP_Z1 - CAP_Z0, (0, 0, (CAP_Z0 + CAP_Z1) * 0.5), chrome, 24)]
    for k in range(3):
        z = CAP_Z0 + 0.006 + k * 0.01
        cap.append(cyl(CAP_R * 1.035, 0.004, (0, 0, z), chrome, 24))
    cap.append(ball(CAP_R, (0, 0, CAP_Z1), chrome, 24, 12, sz=DOME_H / CAP_R))
    cp = join(cap, "Cap", smooth=True)
    # seven pour holes: one at the top, six round it, each a dark bead sunk into the dome
    holes = [ball(0.0075, (0, 0, dome_z(0.0)), hole, 8, 4, sz=0.5)]
    for k in range(6):
        a = k * math.tau / 6.0
        r = CAP_R * 0.5
        holes.append(ball(0.0075, (math.cos(a) * r, math.sin(a) * r, dome_z(r)), hole, 8, 4, sz=0.5))
    hl = join(holes, "Holes", smooth=True)
    sp = empty("Spout", (0.0, 0.0, CAP_Z1 + DOME_H))
    return [bd, ct, cp, hl, sp]


def export(objs):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", OUT)


def render(path):
    """The shaker tipped over to the right as if pouring, turned a little towards the viewer, seen a little from above,
    on a transparent film (the icon scripts lay it on their screen colour); a few grains fall from the holes."""
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes.get("Background").inputs["Color"].default_value = (0.55, 0.58, 0.62, 1.0)
    scene.world = w
    pivot = bpy.data.objects.new("pivot", None)
    scene.collection.objects.link(pivot)
    for o in list(scene.objects):
        if o is not pivot and o.parent is None and o.type in ("MESH", "EMPTY"):
            o.parent = pivot
    pivot.rotation_mode = "ZYX"
    pivot.rotation_euler = (0.0, math.radians(118.0), math.radians(-18.0))
    bpy.context.view_layer.update()
    # grains falling from the holes (render only: never exported)
    grain_m = MATS[[k for k in MATS if k.endswith("_salt")][0]]
    spout = pivot.matrix_world @ Vector((0.0, 0.0, CAP_Z1 + DOME_H))
    tip = pivot.matrix_world.to_3x3() @ Vector((0.0, 0.0, 1.0))
    for k in range(16):
        t = 0.02 + k * 0.016
        spread = 0.002 + t * 0.12
        p = spout + tip * 0.012 + Vector((((k * 37) % 7 - 3) * spread, ((k * 53) % 5 - 2) * spread, -t))
        g = ball(0.0055, p, grain_m, 6, 4)
        g.name = "grain%d" % k
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cd.type = "ORTHO"
    cd.ortho_scale = 0.62
    centre = Vector((0.05, 0.0, -0.06))
    cam.location = centre + Vector((0.0, -4.0, 1.2))
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    sun = bpy.data.lights.new("sunlight", "SUN")
    sun.energy = 2.6
    so = bpy.data.objects.new("sunlight", sun)
    scene.collection.objects.link(so)
    so.rotation_euler = (0.75, -0.35, -0.45)
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 0.8
    fo = bpy.data.objects.new("fill", fill)
    scene.collection.objects.link(fo)
    fo.rotation_euler = (1.1, 0.5, 2.4)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def main():
    os.makedirs(DL, exist_ok=True)
    for key in ("salt", "sea_salt", "hiwa_kai"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        MATS.clear()
        objs = build(key)
        if key == "salt":
            export(objs)
        render(os.path.join(DL, key + "_ref.png"))
    print("blender_salt: done")


main()

"""The Sun Scepter and Zenith as real models (pass 54), built from primitives and exported as GLB for the SunScepter
behaviour (art/props/sun_scepter.glb, zenith.glb), each rendered once on a transparent film (tools/dl/sun_scepter_ref.png,
zenith_ref.png) as the reference the icons are painted from.

The sceptre stands up +Z (the y-up export makes that Godot's +Y) with its origin near the middle of its length, so the
companion tilts and rocks about its middle. The sun disc lies in the XZ plane and faces -Y (Godot's +Z: towards the
game's camera when the companion is not turned). Four parts keep their names, since the game finds them:
  "Staff"   the dark lacquered shaft, its brass bands, the collar under the sun and the brass foot;
  "Sun"     the gold disc and its straight rays (emission 0.6: a strong glow washes the gold out to white in the game),
            its origin at the disc's centre;
  "Charge"  a thin brass ring round the disc, its origin at the disc's centre: Zenith's count (the game scales it and
            lights it as the tenth strike nears; the plain sceptre hides it);
  "Glint"   an empty at the disc's upper-right rim, where the game hangs its flare.
Zenith adds "Halo", a second thin ring through the rays, a bigger white-hot disc and twelve rays (long and short).

  "$BLENDER" -b --python tools/blender_scepter.py
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
MATS = {}

LOOKS = {
    "sun_scepter": {
        "foot": -0.42, "staff_top": 0.17, "sun_z": 0.30, "staff_r": 0.021,
        "disc_r": 0.115, "boss_r": 0.075, "rays": 8, "ray_in": 0.095, "ray_out": 0.225, "ray_short": None, "ray_w": 0.036,
        "charge_r": 0.152, "halo_r": None,
        "lacquer": (34, 16, 14), "band": (205, 150, 60), "gold": (255, 172, 26), "boss": (255, 206, 74),
        "gold_glow": 0.6, "boss_glow": 0.75, "band_glow": 0.0,
    },
    "zenith": {
        "foot": -0.44, "staff_top": 0.17, "sun_z": 0.33, "staff_r": 0.023,
        "disc_r": 0.14, "boss_r": 0.095, "rays": 12, "ray_in": 0.115, "ray_out": 0.31, "ray_short": 0.235, "ray_w": 0.044,
        "charge_r": 0.166, "halo_r": 0.228,
        "lacquer": (24, 12, 10), "band": (255, 176, 48), "gold": (255, 182, 34), "boss": (255, 236, 160),
        "gold_glow": 0.6, "boss_glow": 0.9, "band_glow": 0.25,
    },
}


def mat(name, rgb, rough=0.6, metal=0.0, glow=None, strength=0.6):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    col = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if glow:
        bsdf.inputs["Emission Color"].default_value = (glow[0] / 255.0, glow[1] / 255.0, glow[2] / 255.0, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = col
    MATS[name] = m
    return m


def part(op, m, **kw):
    op(**kw)
    o = bpy.context.active_object
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def cyl(r, depth, loc, m, axis="z", verts=12, r2=None):
    rot = {"y": (math.pi / 2, 0, 0), "x": (0, math.pi / 2, 0), "z": (0, 0, 0)}[axis]
    return part(bpy.ops.mesh.primitive_cone_add, m, vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth,
                location=loc, rotation=rot)


def ball(r, loc, m):
    return part(bpy.ops.mesh.primitive_uv_sphere_add, m, radius=r, location=loc, segments=14, ring_count=8)


def torus(major, minor, loc, m):
    # its axis along Y: the ring lies in the disc's plane
    return part(bpy.ops.mesh.primitive_torus_add, m, major_radius=major, minor_radius=minor, location=loc,
                rotation=(math.pi / 2, 0, 0), major_segments=40, minor_segments=8)


def ray(centre, angle, r_in, r_out, width, m):
    """A straight pointed ray in the disc's plane: a four-sided cone flattened across the disc, its point outwards."""
    depth = r_out - r_in
    mid = r_in + depth * 0.5
    loc = (centre[0] + math.sin(angle) * mid, centre[1], centre[2] + math.cos(angle) * mid)
    o = part(bpy.ops.mesh.primitive_cone_add, m, vertices=4, radius1=width, radius2=0.0, depth=depth, location=loc,
             rotation=(0, angle, 0))
    o.scale = (1.0, 0.34, 1.0)
    return o


def join(objs, name, origin=(0.0, 0.0, 0.0)):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.context.scene.cursor.location = origin
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.shade_flat()
    return o


def empty(name, loc):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.empty_display_size = 0.03
    e.location = loc
    return e


def build(key):
    L = LOOKS[key]
    lacquer = mat(key + "_lacquer", L["lacquer"], 0.28, 0.1)
    band = mat(key + "_band", L["band"], 0.4, 0.45, glow=L["band"] if L["band_glow"] > 0 else None, strength=L["band_glow"])
    # the glow a shade more orange than the gold, so it reads as sunlight and not lemon
    glow = (255, max(L["gold"][1] - 26, 0), max(L["gold"][2] - 10, 0))
    gold = mat(key + "_gold", L["gold"], 0.35, 0.35, glow=glow, strength=L["gold_glow"])
    boss = mat(key + "_boss", L["boss"], 0.3, 0.2, glow=L["boss"], strength=L["boss_glow"])
    ring_m = mat(key + "_ring", L["band"], 0.4, 0.45)
    foot, top, sz = L["foot"], L["staff_top"], L["sun_z"]
    # the staff: a slim lacquered shaft, three brass bands, a flared brass collar holding the sun and a pointed brass foot
    staff = [cyl(L["staff_r"], top - foot, (0, 0, (top + foot) * 0.5), lacquer, "z", 12)]
    for z in (foot + 0.17, foot + 0.36, top - 0.12):
        staff.append(cyl(L["staff_r"] * 1.38, 0.028, (0, 0, z), band, "z", 12))
    staff.append(cyl(L["staff_r"] * 1.2, 0.05, (0, 0, top + 0.02), band, "z", 12, r2=L["staff_r"] * 2.5))
    staff.append(ball(L["staff_r"] * 1.6, (0, 0, top - 0.025), band))
    staff.append(cyl(L["staff_r"] * 1.45, 0.022, (0, 0, foot + 0.02), band, "z", 12))
    staff.append(cyl(0.0, 0.07, (0, 0, foot - 0.026), band, "z", 12, r2=L["staff_r"] * 1.45))
    st = join(staff, "Staff")
    # the sun: a gold disc, a raised brighter boss on both faces, the rays straight and pointed in the disc's plane
    centre = (0.0, 0.0, sz)
    sun = [cyl(L["disc_r"], 0.034, centre, gold, "y", 32)]
    sun.append(cyl(L["boss_r"], 0.052, centre, boss, "y", 32))
    n = L["rays"]
    for k in range(n):
        a = k * math.tau / n
        out = L["ray_out"] if (L["ray_short"] is None or k % 2 == 0) else L["ray_short"]
        sun.append(ray(centre, a, L["ray_in"], out, L["ray_w"], gold))
    sn = join(sun, "Sun", centre)
    objs = [st, sn]
    if L["halo_r"]:
        objs.append(join([torus(L["halo_r"], 0.0065, centre, ring_m)], "Halo", centre))
    objs.append(join([torus(L["charge_r"], 0.009, centre, ring_m)], "Charge", centre))
    objs.append(empty("Glint", (L["disc_r"] * 0.62, -0.036, sz + L["disc_r"] * 0.62)))
    return objs


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def render(path, key, show_charge):
    """The sceptre upright and leaning a little to the right, turned a fifth towards the viewer, seen from the disc's side
    and a little above, on a transparent film (gen_icon_cands lays it on the screen colour)."""
    scene = bpy.context.scene
    for o in scene.objects:
        if o.name == "Charge":
            o.hide_render = not show_charge
    # the GLB is written: the picture shows the gold as gold (a glow under this light washes it to lemon)
    for m in MATS.values():
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Emission Strength"].default_value = min(b.inputs["Emission Strength"].default_value, 0.12)
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes.get("Background").inputs["Color"].default_value = (0.4, 0.4, 0.4, 1.0)
    scene.world = w
    # parent everything to one empty and turn that, so the parts keep their places
    pivot = bpy.data.objects.new("pivot", None)
    scene.collection.objects.link(pivot)
    for o in list(scene.objects):
        if o is not pivot and o.parent is None and o.type in ("MESH", "EMPTY"):
            o.parent = pivot
    pivot.rotation_mode = "ZYX"
    pivot.rotation_euler = (0.0, math.radians(14.0), math.radians(-20.0))
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cd.type = "ORTHO"
    cd.ortho_scale = 1.12
    centre = Vector((0.0, 0.0, 0.03))
    cam.location = centre + Vector((0.0, -4.0, 0.9))
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    sun = bpy.data.lights.new("sunlight", "SUN")
    sun.energy = 2.4
    so = bpy.data.objects.new("sunlight", sun)
    scene.collection.objects.link(so)
    so.rotation_euler = (0.75, -0.35, -0.45)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(DL, exist_ok=True)
    for key in ("sun_scepter", "zenith"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        MATS.clear()
        objs = build(key)
        export(objs, key)
        render(os.path.join(DL, key + "_ref.png"), key, key == "zenith")
    print("blender_scepter: done")


main()

"""The Turret Buddy as a model (pass 46; until now Turret.gd built it from boxes). Garry pointed at an anti-tank turret on
Sketchfab (_REFERENCES/3d/anti-tank_turret.glb) to follow loosely; that model is CC-BY-NC, so none of its mesh is used:
this builds our own in its spirit from Blender primitives: a stepped octagonal base with four fins, a squat bell, an
angular head with a hatch and a long barrel with two red bands and a muzzle brake, flat game colours.

Every stance is in the one file, Turret.gd shows the one it needs (Blender +Y is forward = Godot -Z after the y-up export):
  Base, BaseTop          the plain stand (the Turret Buddy) and where its head sits
  Tripod, TripodTop      the Watchtower's tall wooden tripod and platform
  Sandbags, SandbagsTop  the Bunker's ring of sandbags round a low block
  Yaw                    the head, turning about its origin (Turret.gd moves it onto the stance's *Top)
    Gun                  pitch pivot at the front of the head
      Barrel/Muzzle      the single barrel and its tip (recoil slides Barrel back along its axis)
      BarrelL/Muzzle, BarrelR/Muzzle   the Bunker's twin barrels (hidden otherwise)

turret_buddy.glb in gunmetal and red, turret_family.glb in gold. Each stance is rendered three-quarters from the front on
green as the reference its icon is painted from (tools/dl/turret_<stance>_ref.png).

Pass 53: iron_bastion.glb, the Iron Bastion's (the Turret Buddy's evolution since pass 53; Garry: the turret model "should
look different after it's Evolved"): the bunker stance made heavy (`heavy`): a wider ring of sandbags in three courses
round a riveted octagonal armour hull in dark iron with a brass band and brass rivets, a bigger head with a brass band,
rivets along its edges and a small searchlight box on top, two longer barrels with muzzle brakes. The same node names, so
Turret.gd finds everything. `-- only=bastion` (or buddy, family) builds one file.

  "$BLENDER" -b --python tools/blender_turret.py [-- only=bastion]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
MATS = {}
PALETTES = {
    "buddy": {"metal": (0.2, 0.21, 0.24), "dark": (0.09, 0.09, 0.11), "band": (0.72, 0.12, 0.09), "rim": (0.62, 0.47, 0.2)},
    "family": {"metal": (0.86, 0.62, 0.2), "dark": (0.26, 0.17, 0.06), "band": (0.55, 0.08, 0.06), "rim": (0.95, 0.85, 0.55)},
    # pass 53: dark iron with brass (the band and the rivets are brass; the barrels' bands too)
    "bastion": {"metal": (0.18, 0.19, 0.22), "dark": (0.08, 0.08, 0.1), "band": (0.75, 0.55, 0.2), "rim": (0.75, 0.55, 0.2)},
}
FILES = {"buddy": "turret_buddy.glb", "family": "turret_family.glb", "bastion": "iron_bastion.glb"}
WOOD = (0.45, 0.29, 0.15)
SAND = (0.72, 0.6, 0.4)
## the glass of the bastion's searchlight
LENS = (0.9, 0.95, 1.0)


def mat(name, rgb, rough=0.55, metal=0.0):
    key = (name, rgb)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    MATS[key] = m
    return m


def _take(m, bevel=0.0):
    o = bpy.context.active_object
    o.data.materials.clear()
    o.data.materials.append(m)
    if bevel > 0.0:
        md = o.modifiers.new("bev", "BEVEL")
        md.width = bevel
        md.segments = 2
        md.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.ops.object.shade_flat()
    return o


def cyl(r, depth, loc, m, verts=8, r2=None, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth, location=loc, rotation=rot)
    return _take(m, bevel)


def box(size, loc, m, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _take(m, bevel)


def blob(size, loc, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _take(m)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    # the joined object keeps its first part's rotation; bake it, so a child placed along +Y (a barrel's Muzzle) really
    # sits along the barrel (pass 46: the muzzles came out 0.62 m above the barrels)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return o


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    if parent:
        e.parent = parent
    return e


def parent_keep(child, parent):
    mw = child.matrix_world.copy()
    child.parent = parent
    child.matrix_world = mw


def barrel(name, x, P, long=False):
    """A barrel from its breech at y 0.19 out along +Y: the tube, two bands, a muzzle brake and the bore's lip. `long`
    (pass 53, the Iron Bastion): a thicker tube a third longer with a wider brake, slotted with two dark rings."""
    metal, dark, band = mat("metal", P["metal"], 0.45, 0.35), mat("dark", P["dark"], 0.6, 0.2), mat("band", P["band"], 0.5)
    rot = (math.pi / 2, 0, 0)
    y0 = 0.19
    if long:
        L = 0.76
        parts = [cyl(0.048, L, (x, y0 + L / 2, 0.0), metal, 10, rot=rot),
                 cyl(0.06, 0.05, (x, y0 + 0.12, 0.0), band, 10, rot=rot),
                 cyl(0.06, 0.05, (x, y0 + 0.24, 0.0), band, 10, rot=rot),
                 # the brake: a fat dark cylinder with two brass rings cut round it
                 cyl(0.075, 0.16, (x, y0 + L - 0.02, 0.0), dark, 10, rot=rot, bevel=0.012),
                 cyl(0.08, 0.025, (x, y0 + L - 0.06, 0.0), band, 10, rot=rot),
                 cyl(0.08, 0.025, (x, y0 + L + 0.01, 0.0), band, 10, rot=rot),
                 cyl(0.034, 0.02, (x, y0 + L + 0.07, 0.0), dark, 8, rot=rot)]
        tip = L + 0.09
    else:
        parts = [cyl(0.042, 0.56, (x, 0.47, 0.0), metal, 10, rot=rot),
                 cyl(0.054, 0.05, (x, 0.3, 0.0), band, 10, rot=rot),
                 cyl(0.054, 0.05, (x, 0.4, 0.0), band, 10, rot=rot),
                 cyl(0.06, 0.1, (x, 0.74, 0.0), dark, 10, rot=rot, bevel=0.01),
                 cyl(0.03, 0.02, (x, 0.79, 0.0), dark, 8, rot=rot)]
        tip = 0.62
    b = join(parts, name)
    # the barrel's origin at its breech, so the recoil slides it along its own axis
    bpy.context.scene.cursor.location = (x, y0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    m = empty("Muzzle", (0, 0, 0))
    m.parent = b
    m.location = (0.0, tip, 0.0)
    return b


def rivets(parts, spots, r, m):
    """Small domed heads at every spot (pass 53, the bastion's armour)."""
    for loc in spots:
        parts.append(blob((r, r, r * 0.6), loc, m))


def build(P, heavy=False):
    """The three stands, the head and the barrels. `heavy` (pass 53) is the Iron Bastion: its bunker stance and head are the
    heavy ones below, its barrels long; the plain stand and the tripod stay as they are (hidden in that stance)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    metal, dark, band, rim = (mat("metal", P["metal"], 0.45, 0.35), mat("dark", P["dark"], 0.6, 0.2),
                              mat("band", P["band"], 0.5), mat("rim", P["rim"], 0.4, 0.4))
    wood, sand = mat("wood", WOOD, 0.9), mat("sand", SAND, 1.0)
    # the plain stand: a stepped octagonal plinth, four fins, a squat bell
    parts = [cyl(0.44, 0.1, (0, 0, 0.05), dark, 8, r2=0.4, bevel=0.012),
             cyl(0.36, 0.42, (0, 0, 0.31), metal, 8, r2=0.24, bevel=0.012),
             cyl(0.26, 0.04, (0, 0, 0.54), rim, 8)]
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        # a buttress leaning on the bell, its outer end low (rotated about the tangent before it turns round the bell)
        f = box((0.07, 0.24, 0.26), (math.cos(a) * 0.37, math.sin(a) * 0.37, 0.15), metal, rot=(-0.55, 0.0, a - math.pi / 2), bevel=0.01)
        parts.append(f)
    base = join(parts, "Base")
    empty("BaseTop", (0, 0, 0.56))
    # the Watchtower: a three-legged wooden tripod, braces and a platform with a mount ring
    parts = []
    for k in range(3):
        a = k * math.tau / 3
        top = Vector((math.cos(a) * 0.2, math.sin(a) * 0.2, 1.72))
        foot = Vector((math.cos(a) * 0.62, math.sin(a) * 0.62, 0.0))
        mid = (top + foot) / 2
        d = top - foot
        leg = cyl(0.04, d.length, mid, wood, 6)
        leg.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        parts.append(leg)
        b0 = foot.lerp(top, 0.45)
        a2 = (k + 1) * math.tau / 3
        b1 = Vector((math.cos(a2) * 0.62, math.sin(a2) * 0.62, 0.0)).lerp(Vector((math.cos(a2) * 0.2, math.sin(a2) * 0.2, 1.72)), 0.45)
        bd = b1 - b0
        br = cyl(0.022, bd.length, (b0 + b1) / 2, wood, 5)
        br.rotation_euler = bd.to_track_quat("Z", "Y").to_euler()
        parts.append(br)
    parts.append(cyl(0.42, 0.06, (0, 0, 1.74), wood, 8, bevel=0.01))
    parts.append(cyl(0.24, 0.08, (0, 0, 1.81), metal, 8, r2=0.22, bevel=0.01))
    tripod = join(parts, "Tripod")
    empty("TripodTop", (0, 0, 1.85))
    if heavy:
        # the Iron Bastion's bunker (pass 53): a riveted octagonal armour hull with a brass band, inside a wider ring of
        # sandbags in three courses
        parts = [cyl(0.4, 0.3, (0, 0, 0.15), metal, 8, r2=0.36, bevel=0.012),
                 cyl(0.405, 0.04, (0, 0, 0.21), band, 8, r2=0.395),
                 cyl(0.3, 0.03, (0, 0, 0.315), rim, 8)]
        spots = []
        for k in range(8):
            a = math.pi / 8 + k * math.pi / 4
            for z, r in ((0.09, 0.395), (0.27, 0.368)):
                spots.append((math.cos(a) * r, math.sin(a) * r, z))
        rivets(parts, spots, 0.022, rim)
        for course, (r, z, n) in enumerate(((0.76, 0.08, 14), (0.74, 0.2, 13), (0.72, 0.31, 12))):
            for k in range(n):
                a = (k + 0.5 * course) * math.tau / n
                parts.append(blob((0.2, 0.12, 0.085), (math.cos(a) * r, math.sin(a) * r, z), sand, rot=(0, 0, a + math.pi / 2)))
        sandbags = join(parts, "Sandbags")
        empty("SandbagsTop", (0, 0, 0.34))
    else:
        # the Bunker: two courses of sandbags round a low block
        parts = [cyl(0.3, 0.26, (0, 0, 0.13), metal, 8, r2=0.26, bevel=0.012)]
        for course, (r, z, n) in enumerate(((0.58, 0.07, 12), (0.56, 0.18, 11))):
            for k in range(n):
                a = (k + 0.5 * course) * math.tau / n
                parts.append(blob((0.17, 0.1, 0.075), (math.cos(a) * r, math.sin(a) * r, z), sand, rot=(0, 0, a + math.pi / 2)))
        sandbags = join(parts, "Sandbags")
        empty("SandbagsTop", (0, 0, 0.28))
    if heavy:
        # the heavy head (pass 53): a bigger armoured box with a brass band round it, rivets along its top edges, the
        # hatch, and a searchlight box on top looking forward (+Y); the gun pivot sits a little further forward and up
        lens = mat("lens", LENS, 0.2, 0.0)
        parts = [box((0.56, 0.58, 0.24), (0, -0.02, 0.12), metal, bevel=0.03),
                 box((0.5, 0.18, 0.14), (0, 0.27, 0.1), metal, rot=(-0.5, 0, 0), bevel=0.02),
                 box((0.58, 0.6, 0.03), (0, -0.02, 0.06), band),
                 cyl(0.09, 0.03, (0.1, -0.1, 0.255), rim, 10),
                 cyl(0.06, 0.035, (0.1, -0.1, 0.27), dark, 10),
                 box((0.13, 0.15, 0.1), (-0.16, -0.02, 0.29), dark, bevel=0.01),
                 cyl(0.055, 0.04, (-0.16, 0.065, 0.29), rim, 10, rot=(math.pi / 2, 0, 0)),
                 cyl(0.042, 0.012, (-0.16, 0.088, 0.29), lens, 10, rot=(math.pi / 2, 0, 0)),
                 box((0.1, 0.18, 0.06), (0.22, -0.06, 0.1), band)]
        spots = []
        for y in (-0.24, -0.12, 0.0, 0.12):
            spots.append((0.26, y, 0.245))
            spots.append((-0.26, y, 0.245))
        rivets(parts, spots, 0.016, rim)
        yaw = join(parts, "Yaw")
        gun = empty("Gun", (0, 0.24, 0.1), yaw)
        for name, x in (("Barrel", 0.0), ("BarrelL", -0.09), ("BarrelR", 0.09)):
            b = barrel(name, x, P, long=True)
            b.parent = gun
            b.location = (x, -0.01, 0.0)
        return base, tripod, sandbags, yaw
    # the head: an angular box sloped at the front, a hatch and a sight; its origin is the turning point
    parts = [box((0.46, 0.5, 0.2), (0, -0.02, 0.1), metal, bevel=0.03),
             box((0.4, 0.16, 0.12), (0, 0.22, 0.08), metal, rot=(-0.5, 0, 0), bevel=0.02),
             cyl(0.08, 0.03, (0.06, -0.08, 0.215), rim, 10),
             cyl(0.055, 0.035, (0.06, -0.08, 0.23), dark, 10),
             box((0.05, 0.08, 0.06), (-0.14, 0.05, 0.23), dark),
             box((0.08, 0.16, 0.06), (0.2, -0.05, 0.1), band)]
    yaw = join(parts, "Yaw")
    gun = empty("Gun", (0, 0.2, 0.09), yaw)
    for name, x in (("Barrel", 0.0), ("BarrelL", -0.075), ("BarrelR", 0.075)):
        b = barrel(name, x, P)
        b.location = (x, 0.19 - 0.2, -0.09 + 0.09)
        b.parent = gun
        b.location = (x, -0.01, 0.0)
    return base, tripod, sandbags, yaw


def export(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
    print("turret: wrote", path)


def stance(name):
    """Show one stance for a render: the head on its top, the right barrels."""
    objs = bpy.data.objects
    tops = {"buddy": "BaseTop", "watchtower": "TripodTop", "bunker": "SandbagsTop"}
    stands = {"buddy": "Base", "watchtower": "Tripod", "bunker": "Sandbags"}
    for s in stands.values():
        objs[s].hide_render = s != stands[name]
    objs["Yaw"].location = objs[tops[name]].location
    twin = name == "bunker"
    objs["Barrel"].hide_render = twin
    objs["BarrelL"].hide_render = not twin
    objs["BarrelR"].hide_render = not twin
    objs["Yaw"].rotation_euler = (0, 0, math.radians(-30))


def render(path, height):
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.view_settings.view_transform = "Standard"
    # a neutral grey world lights it (a green one tinted every face green) and the film is transparent: the icon
    # script lays the render on the green screen itself
    scene.render.film_transparent = True
    if scene.world is None:
        w = bpy.data.worlds.new("w")
        w.use_nodes = True
        bg = w.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (0.75, 0.75, 0.75, 1.0)
        bg.inputs["Strength"].default_value = 0.8
        scene.world = w
    if scene.camera is None:
        cd = bpy.data.cameras.new("cam")
        cam = bpy.data.objects.new("cam", cd)
        scene.collection.objects.link(cam)
        scene.camera = cam
        cd.type = "ORTHO"
        sun = bpy.data.lights.new("sun", "SUN")
        sun.energy = 3.5
        so = bpy.data.objects.new("sun", sun)
        scene.collection.objects.link(so)
        so.rotation_euler = (0.6, -0.3, -0.5)
    cam = scene.camera
    cam.data.ortho_scale = max(height * 1.25, 1.5)
    centre = Vector((0, 0, height * 0.5))
    # from the front-left (forward is +Y) and above, the barrel coming towards the viewer and off to the right
    d = Vector((-0.55, 0.8, 0.5)).normalized()
    cam.location = centre + d * 6.0
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("turret: rendered", path)


def _only():
    """The files asked for after `--` (`only=bastion,family`), or every one."""
    argv = sys.argv
    if "--" in argv:
        for a in argv[argv.index("--") + 1:]:
            if a.startswith("only="):
                return [k for k in a.split("=", 1)[1].split(",") if k]
    return list(FILES.keys())


def main():
    os.makedirs(OUT, exist_ok=True)
    for key in _only():
        build(PALETTES[key], heavy=key == "bastion")
        export(os.path.join(OUT, FILES[key]))
        if key == "buddy":
            for st, h in (("buddy", 0.9), ("watchtower", 2.2), ("bunker", 0.7)):
                stance(st)
                render(os.path.join(DL, "turret_%s_ref.png" % st), h)
        elif key == "family":
            stance("buddy")
            render(os.path.join(DL, "turret_family_ref.png"), 0.9)
        else:
            # the Iron Bastion shows only its bunker stance
            stance("bunker")
            render(os.path.join(DL, "turret_bastion_ref.png"), 0.9)


main()

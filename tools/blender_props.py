"""Builds the Dry Gulch prop kit in Blender and exports one GLB per prop into game/art/props/.

Low-poly, painted-flat materials (colour per material, no textures), origin at the base so Godot can
drop them on the terrain. Run headless:
  "<blender.exe>" -b --python tools/blender_props.py -- out=D:/_projects/88fits/game/art/props [only=tumbleweed_dark,...]
Props: saguaro, barrel_cactus, rock_small, rock_big, boulder, mesa_block, signpost, skull, bone,
       pickup_wreck, gas_station, water_tower, wind_pump, tumbleweed, campfire, ramp, tumbleweed_dark (pass 54)
`only=` builds just the props it names (pass 54: the dark weed alone, the rest of the kit untouched).
"""
import bpy, bmesh, math, os, random, sys

OUT = "D:/_projects/88fits/game/art/props"
ONLY = []
for a in sys.argv:
    if a.startswith("out="):
        OUT = a[4:]
    if a.startswith("only="):
        ONLY = [s for s in a[5:].split(",") if s]
os.makedirs(OUT, exist_ok=True)
random.seed(88)

MATS = {}


def mat(name, rgb, rough=0.9):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    MATS[name] = m
    return m


CACTUS = ("cactus", (78, 143, 76))
CACTUS_DARK = ("cactus_dark", (60, 118, 62))
ROCK = ("rock", (156, 138, 122))
ROCK_DARK = ("rock_dark", (122, 104, 92))
SANDSTONE = ("sandstone", (184, 107, 62))
SANDSTONE_DARK = ("sandstone_dark", (143, 78, 44))
RUST = ("rust", (122, 74, 58))
RUST_DARK = ("rust_dark", (86, 50, 36))
WOOD = ("wood", (138, 106, 74))
WOOD_DARK = ("wood_dark", (91, 66, 37))
BONE = ("bone", (241, 232, 214))
RED = ("red", (216, 67, 59))
METAL = ("metal", (110, 74, 44))
IRON = ("iron", (58, 42, 30))
TUMBLE = ("tumble", (200, 170, 110))
GOLD = ("gold", (255, 178, 59))


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def apply_mat(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(mat(*m))


def cyl(r_top, r_bot, depth, loc, m, verts=10, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r_bot, radius2=r_top, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    apply_mat(o, m)
    return o


def cube(size, loc, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    apply_mat(o, m)
    return o


def ico(radius, loc, m, subdiv=1, jitter=0.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    o = bpy.context.active_object
    if jitter > 0.0:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        for v in bm.verts:
            v.co += v.normal * random.uniform(-jitter, jitter) * radius
        bm.to_mesh(o.data)
        bm.free()
    apply_mat(o, m)
    return o


def join(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.shade_flat()
    return o


def export(obj, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def saguaro():
    parts = [cyl(0.42, 0.5, 3.0, (0, 0, 1.5), CACTUS, 8)]
    parts.append(cyl(0.3, 0.3, 0.9, (-0.85, 0, 1.3), CACTUS, 7, (0, math.pi / 2, 0)))
    parts.append(cyl(0.28, 0.3, 1.6, (-1.15, 0, 2.1), CACTUS, 7))
    parts.append(cyl(0.3, 0.3, 0.8, (0.8, 0, 1.7), CACTUS, 7, (0, math.pi / 2, 0)))
    parts.append(cyl(0.26, 0.3, 1.3, (1.05, 0, 2.3), CACTUS, 7))
    for k in range(6):
        a = k * math.tau / 6
        parts.append(cube((0.05, 0.05, 2.8), (math.cos(a) * 0.47, math.sin(a) * 0.47, 1.5), CACTUS_DARK))
    return join(parts, "saguaro")


def barrel_cactus():
    o = ico(0.55, (0, 0, 0.5), CACTUS, 2, 0.04)
    o.scale = (1.0, 1.0, 0.85)
    ridges = [cube((0.06, 0.06, 0.9), (math.cos(k * math.tau / 8) * 0.52, math.sin(k * math.tau / 8) * 0.52, 0.5), CACTUS_DARK) for k in range(8)]
    top = ico(0.12, (0, 0, 0.98), RED, 1)
    return join([o] + ridges + [top], "barrel_cactus")


def rock(name, r, jitter):
    o = ico(r, (0, 0, r * 0.7), ROCK, 2, jitter)
    o.scale = (1.3, 1.0, 0.75)
    return join([o, ico(r * 0.55, (r * 0.8, r * 0.3, r * 0.35), ROCK_DARK, 1, jitter)], name)


def mesa_block():
    body = cube((1.0, 1.0, 1.0), (0, 0, 0.5), SANDSTONE)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for v in bm.verts:
        if v.co.z > 0.4:
            v.co.x += random.uniform(-0.06, 0.06)
            v.co.y += random.uniform(-0.06, 0.06)
    bm.to_mesh(body.data)
    bm.free()
    band = cube((1.04, 1.04, 0.18), (0, 0, 0.42), SANDSTONE_DARK)
    return join([body, band], "mesa_block")


def ramp():
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.25))
    o = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        if v.co.y > 0 and v.co.z > 0:
            v.co.z = -0.5
    bm.to_mesh(o.data)
    bm.free()
    o.scale = (1.0, 1.0, 1.0)
    apply_mat(o, SANDSTONE)
    o.name = "ramp"
    bpy.ops.object.shade_flat()
    return o


def signpost():
    post = cyl(0.08, 0.1, 3.0, (0, 0, 1.5), WOOD_DARK, 6)
    board = cube((2.4, 0.12, 0.6), (0.4, 0, 2.6), WOOD, (0, 0, 0.2))
    board2 = cube((1.6, 0.12, 0.45), (-0.3, 0, 1.9), WOOD, (0, 0, -0.3))
    return join([post, board, board2], "signpost")


def skull():
    head = ico(0.5, (0, 0, 0.45), BONE, 2, 0.02)
    head.scale = (1.0, 1.15, 0.9)
    jaw = cube((0.6, 0.5, 0.25), (0, 0.25, 0.15), BONE)
    eyes = [ico(0.13, (dx, 0.42, 0.5), IRON, 1) for dx in (-0.2, 0.2)]
    return join([head, jaw] + eyes, "skull")


def bone():
    shaft = cyl(0.1, 0.1, 2.0, (0, 0, 0.12), BONE, 6, (0, math.pi / 2, 0))
    knobs = [ico(0.17, (dx, dy, 0.14), BONE, 1) for dx in (-1.0, 1.0) for dy in (-0.12, 0.12)]
    return join([shaft] + knobs, "bone")


def pickup_wreck():
    bed = cube((5.0, 2.4, 1.2), (0, 0, 0.9), RUST)
    cab = cube((2.0, 2.2, 1.3), (-1.2, 0, 1.95), RUST_DARK)
    hood = cube((1.4, 2.2, 0.6), (-2.9, 0, 1.4), RUST)
    wheels = [cyl(0.5, 0.5, 0.4, (x, y, 0.5), IRON, 10, (math.pi / 2, 0, 0)) for x in (-2.2, 1.6) for y in (-1.3, 1.3)]
    return join([bed, cab, hood] + wheels, "pickup_wreck")


def gas_station():
    box = cube((9.0, 5.0, 4.0), (0, 0, 2.0), WOOD)
    roof = cube((9.4, 5.4, 0.4), (0, 0, 4.2), WOOD_DARK)
    canopy = cube((6.0, 4.0, 0.3), (0, -4.5, 4.0), RED)
    posts = [cyl(0.15, 0.15, 4.0, (x, -6.0, 2.0), IRON, 6) for x in (-2.5, 2.5)]
    sign = cube((6.0, 0.4, 1.2), (0, 2.7, 5.2), RED)
    pumps = [cube((0.6, 0.6, 1.6), (x, -4.5, 0.8), RUST) for x in (-1.5, 1.5)]
    return join([box, roof, canopy, sign] + posts + pumps, "gas_station")


def water_tower():
    tank = cyl(2.0, 2.0, 2.6, (0, 0, 7.0), WOOD, 12)
    lid = cyl(0.2, 2.2, 0.8, (0, 0, 8.7), WOOD_DARK, 12)
    legs = [cyl(0.15, 0.2, 6.0, (math.cos(a) * 1.4, math.sin(a) * 1.4, 3.0), IRON, 6) for a in (0.785, 2.356, 3.927, 5.498)]
    braces = [cube((2.6, 0.08, 0.08), (0, 0, z), IRON, (0, 0, r)) for z in (2.0, 4.0) for r in (0.0, math.pi / 2)]
    return join([tank, lid] + legs + braces, "water_tower")


def wind_pump():
    legs = [cyl(0.08, 0.14, 7.0, (math.cos(a) * 0.9, math.sin(a) * 0.9, 3.5), IRON, 5) for a in (0.785, 2.356, 3.927, 5.498)]
    hub = ico(0.3, (0, -0.6, 7.2), IRON, 1)
    blades = [cube((0.25, 0.05, 1.6), (math.cos(a) * 1.0, -0.65, 7.2 + math.sin(a) * 1.0), METAL, (0, a, 0)) for a in [k * math.tau / 8 for k in range(8)]]
    tail = cube((1.4, 0.05, 0.8), (0, 1.2, 7.2), RED)
    return join(legs + [hub, tail] + blades, "wind_pump")


def tumbleweed():
    o = ico(0.8, (0, 0, 0.8), TUMBLE, 2, 0.12)
    mod = o.modifiers.new("wire", "WIREFRAME")
    mod.thickness = 0.06
    bpy.ops.object.modifier_apply(modifier="wire")
    o.name = "tumbleweed"
    return o


def _srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def tumbleweed_dark():
    """The Tumbleweed weapon's shot (pass 54, Garry: the tan weed vanished on the sand): the same tangle in dark brown
    with thicker wires (0.09) and a faint glow of its own colour, so it reads in shade. Its colour is given as the game
    shows it (sRGB 74, 46, 24): Blender's base colour is linear. The mesh keeps the name "tumbleweed", so the visual
    scenes' material overrides find it by the same path. Its own seed: built alone (only=) or with the kit, it is the
    same weed. The King's black weeds and the world's rolling ones keep tumbleweed.glb."""
    random.seed(8854)
    rgb = (74, 46, 24)
    lin = tuple(_srgb_to_linear(c) for c in rgb)
    m = bpy.data.materials.new("tumble_dark")
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Emission Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs["Emission Strength"].default_value = 0.15
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.8, location=(0, 0, 0.8))
    o = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        v.co += v.normal * random.uniform(-0.12, 0.12) * 0.8
    bm.to_mesh(o.data)
    bm.free()
    o.data.materials.clear()
    o.data.materials.append(m)
    mod = o.modifiers.new("wire", "WIREFRAME")
    mod.thickness = 0.09
    bpy.ops.object.modifier_apply(modifier="wire")
    o.name = "tumbleweed"
    return o


def campfire():
    stones = [ico(0.22, (math.cos(a) * 0.7, math.sin(a) * 0.7, 0.15), ROCK, 1, 0.1) for a in [k * math.tau / 8 for k in range(8)]]
    logs = [cyl(0.1, 0.1, 1.1, (0, 0, 0.18), WOOD_DARK, 6, (0, math.pi / 2, r)) for r in (0.3, 1.4, 2.4)]
    flame = ico(0.28, (0, 0, 0.55), GOLD, 1, 0.2)
    flame.scale = (1, 1, 1.6)
    return join(stones + logs + [flame], "campfire")


# ---------------------------------------------------------------- meadow props

def _wood():
    return ("bark", (78, 52, 30))


def _leaf():
    return ("leaf", (34, 88, 30))


def oak_tree():
    parts = [cyl(0.32, 0.45, 3.2, (0, 0, 1.6), _wood(), 8)]
    leaf = _leaf()
    for (x, y, z, r) in [(0, 0, 4.6, 1.9), (1.2, 0.3, 4.0, 1.3), (-1.1, -0.4, 4.2, 1.35), (0.2, 1.1, 4.3, 1.2), (-0.1, -1.1, 4.1, 1.15)]:
        parts.append(ico(r, (x, y, z), leaf, 2, 0.08))
    return join(parts, "oak_tree")


def pine_tree():
    parts = [cyl(0.22, 0.32, 3.0, (0, 0, 1.5), _wood(), 7)]
    leaf = ("pine", (24, 70, 34))
    for k, (z, r, h) in enumerate([(2.6, 2.0, 2.4), (4.2, 1.6, 2.2), (5.6, 1.15, 2.0), (6.8, 0.7, 1.7)]):
        parts.append(cyl(0.0, r, h, (0, 0, z + h * 0.5 - 0.6), leaf, 7))
    return join(parts, "pine_tree")


def bush():
    leaf = _leaf()
    parts = [ico(0.8, (0, 0, 0.6), leaf, 2, 0.1), ico(0.6, (0.6, 0.2, 0.5), leaf, 2, 0.1), ico(0.55, (-0.5, -0.3, 0.45), leaf, 2, 0.1)]
    return join(parts, "bush")


def mushroom_big():
    stem = cyl(0.42, 0.55, 1.8, (0, 0, 0.9), ("stem", (230, 219, 184)), 9)
    cap = ico(1.35, (0, 0, 1.95), ("cap", (204, 56, 46)), 2, 0.03)
    cap.scale = (1.0, 1.0, 0.62)
    spots = [ico(0.16, (math.cos(k * 2.1) * 0.85, math.sin(k * 2.1) * 0.85, 2.45 + (k % 2) * 0.1), ("spot", (242, 237, 217)), 1) for k in range(6)]
    return join([stem, cap] + spots, "mushroom_big")


def log_prop():
    body = cyl(0.42, 0.46, 3.2, (0, 0, 0.42), _wood(), 9, (0, math.pi / 2, 0))
    end = cyl(0.36, 0.36, 0.06, (1.62, 0, 0.42), ("cut", (184, 148, 92)), 9, (0, math.pi / 2, 0))
    return join([body, end], "log")


def stump():
    body = cyl(0.62, 0.72, 0.8, (0, 0, 0.4), _wood(), 9)
    top = cyl(0.58, 0.58, 0.06, (0, 0, 0.82), ("cut", (184, 148, 92)), 9)
    return join([body, top], "stump")


# ---------------------------------------------------------------- structures (map landmarks, 1.5 - 3 m)

STONE = ("stone", (112, 108, 100))
STONE_DARK = ("stone_dark", (78, 74, 70))
RED = ("red", (214, 56, 46))
IRON = ("iron", (150, 152, 158))
GOLD = ("gold", (240, 190, 60))
PURPLE = ("purple", (139, 108, 255))
CANVAS = ("canvas", (240, 232, 210))
CANVAS_RED = ("canvas_red", (214, 70, 60))
CRYSTAL = ("crystal", (184, 163, 255))
DRUMSKIN = ("drumskin", (226, 206, 160))


def plinth(r=0.9, h=0.4):
    return cyl(r * 0.92, r, h, (0, 0, h * 0.5), STONE, 12)


def magnet_shrine():
    parts = [plinth()]
    # a horseshoe magnet standing upright: two legs, a bend, silver tips
    for x in (-0.42, 0.42):
        parts.append(cube((0.34, 0.34, 1.1), (x, 0, 0.95), RED))
        parts.append(cube((0.36, 0.36, 0.3), (x, 0, 1.65), IRON))
    parts.append(cube((1.18, 0.34, 0.36), (0, 0, 0.58), RED))
    for x in (-0.55, 0.55):
        parts.append(cube((0.36, 0.34, 0.5), (x, 0, 0.7), RED))
    return join(parts, "magnet_shrine")


def shop_stall():
    parts = [cube((2.2, 1.1, 0.9), (0, 0, 0.45), WOOD)]          # counter
    for x in (-1.0, 1.0):
        for y in (-0.45, 0.45):
            parts.append(cyl(0.05, 0.05, 2.2, (x, y, 1.1), WOOD_DARK, 6))
    parts.append(cube((2.5, 1.5, 0.08), (0, 0, 2.25), CANVAS))    # awning
    for k in range(5):
        if k % 2 == 0:
            parts.append(cube((0.5, 1.52, 0.1), (-1.0 + k * 0.5, 0, 2.26), CANVAS_RED))
    parts.append(cube((0.5, 0.4, 0.3), (-0.6, 0, 1.05), GOLD))   # wares on the counter
    parts.append(ico(0.22, (0.5, 0.1, 1.12), PURPLE, 1))
    parts.append(ico(0.18, (0.1, -0.2, 1.08), RED, 1))
    return join(parts, "shop_stall")


def healing_well():
    parts = [cyl(0.9, 0.9, 0.8, (0, 0, 0.4), STONE, 12), cyl(0.7, 0.7, 0.82, (0, 0, 0.42), ("water", (60, 130, 170)), 12)]
    for x in (-0.75, 0.75):
        parts.append(cyl(0.06, 0.06, 1.6, (x, 0, 1.4), WOOD_DARK, 6))
    parts.append(cube((2.0, 1.3, 0.1), (0, 0, 2.3), WOOD))        # roof
    parts.append(cube((1.4, 0.9, 0.3), (0, 0, 2.5), WOOD_DARK))
    parts.append(cyl(0.12, 0.12, 0.5, (0, 0, 1.75), WOOD, 8, (math.pi / 2, 0, 0)))   # the drum
    return join(parts, "healing_well")


def loot_cache():
    parts = [plinth(0.8, 0.5), cube((1.2, 0.8, 0.6), (0, 0, 0.8), WOOD), cube((1.24, 0.84, 0.28), (0, 0, 1.24), WOOD_DARK)]
    parts.append(cube((1.26, 0.1, 0.62), (0, 0, 0.82), GOLD))     # strap
    parts.append(cube((0.2, 0.12, 0.2), (0, -0.44, 1.0), GOLD))    # lock
    return join(parts, "loot_cache")


def war_drum():
    parts = [cyl(0.7, 0.75, 1.1, (0, 0, 0.55), WOOD_DARK, 14), cyl(0.72, 0.72, 0.06, (0, 0, 1.12), DRUMSKIN, 14)]
    for k in range(3):
        parts.append(cyl(0.76, 0.76, 0.08, (0, 0, 0.2 + k * 0.4), RED, 14))
    for x in (-0.5, 0.3):
        parts.append(cyl(0.03, 0.03, 0.9, (x, -0.2, 1.4), WOOD, 6, (0.5, 0.4, 0)))
        parts.append(ico(0.09, (x - 0.3, -0.45, 1.75), DRUMSKIN, 1))
    return join(parts, "war_drum")


def dice_shrine():
    parts = [plinth(0.9, 0.5), cube((1.0, 1.0, 1.0), (0, 0, 1.15), PURPLE)]
    parts[1].rotation_euler = (0.15, 0.1, 0.6)
    for (x, y, z) in [(0.3, -0.52, 1.35), (-0.3, -0.52, 0.95), (0, -0.52, 1.15), (0.52, 0.3, 1.4), (0.52, -0.3, 0.9)]:
        parts.append(ico(0.09, (x, y, z), CANVAS, 1))
    return join(parts, "dice_shrine")


def beacon():
    parts = [plinth(0.9, 0.35), cube((0.7, 0.7, 2.2), (0, 0, 1.45), STONE_DARK)]
    parts[1].scale = (1.0, 1.0, 1.0)
    top = ico(0.38, (0, 0, 2.95), CRYSTAL, 1)
    top.scale = (1.0, 1.0, 1.6)
    parts.append(top)
    return join(parts, "beacon")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    builders = [
        ("saguaro", saguaro), ("barrel_cactus", barrel_cactus), ("rock_small", lambda: rock("rock_small", 0.7, 0.18)),
        ("rock_big", lambda: rock("rock_big", 1.4, 0.16)), ("boulder", lambda: rock("boulder", 2.2, 0.14)),
        ("mesa_block", mesa_block), ("ramp", ramp), ("signpost", signpost), ("skull", skull), ("bone", bone),
        ("pickup_wreck", pickup_wreck), ("gas_station", gas_station), ("water_tower", water_tower),
        ("wind_pump", wind_pump), ("tumbleweed", tumbleweed), ("campfire", campfire),
        ("oak_tree", oak_tree), ("pine_tree", pine_tree), ("bush", bush), ("mushroom_big", mushroom_big), ("log", log_prop), ("stump", stump),
        ("magnet_shrine", magnet_shrine), ("shop_stall", shop_stall), ("healing_well", healing_well), ("loot_cache", loot_cache),
        ("war_drum", war_drum), ("dice_shrine", dice_shrine), ("beacon", beacon),
        ("tumbleweed_dark", tumbleweed_dark),
    ]
    if ONLY:
        builders = [b for b in builders if b[0] in ONLY]
    for name, fn in builders:
        clear()
        obj = fn()
        export(obj, name)
    clear()
    print("blender_props: done, %d props" % len(builders))


main()

"""The 3D bits of the meta: a proper drop chest (body + a hinged Lid), and the five homestead buildings, built from
primitives in Blender and exported as GLB into game/art/props/meta/.

  "$BLENDER" -b --python tools/blender_meta.py
  "$BLENDER" -b --python tools/blender_meta.py -- only=chest

Units are metres; +Z is up in Blender and becomes +Y in Godot (y-up export). Every building sits on the ground at its
origin, so the screen can drop them straight onto the yard.
"""
import math
import os
import sys

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "meta")
MATS = {}


def mat(name, rgb, rough=0.8, metal=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    MATS[name] = m
    return m


WOOD = ("wood", (168, 112, 58), 0.85)
WOOD_DARK = ("wood_dark", (120, 76, 38), 0.85)
# the chest (pass 29): dark walnut and black iron, so it is a dark thing on the pale sand
CHEST_WOOD = ("chest_wood", (66, 38, 22), 0.9)
CHEST_LID = ("chest_lid", (48, 27, 16), 0.9)
CHEST_IRON = ("chest_iron", (34, 34, 40), 0.5, 0.75)
PLANK = ("plank", (176, 128, 74), 0.85)
IRON = ("iron", (96, 98, 110), 0.45, 0.7)
GOLD = ("gold", (255, 178, 59), 0.3, 0.9)
STONE = ("stone", (150, 132, 112), 0.95)
STONE_DARK = ("stone_dark", (110, 94, 80), 0.95)
BRICK = ("brick", (150, 72, 52), 0.9)
ROOF = ("roof", (128, 48, 38), 0.9)
ROOF_SLATE = ("roof_slate", (78, 70, 88), 0.9)
HAY = ("hay", (222, 184, 92), 0.95)
GLASS = ("glass", (90, 150, 180), 0.3)
CLOTH = ("cloth", (200, 60, 50), 0.9)
EMBER = ("ember", (255, 120, 40), 0.4)
DARK = ("dark", (30, 26, 24), 0.9)
BRASS = ("brass", (196, 150, 70), 0.4, 0.6)
WALL = ("wall", (214, 196, 160), 0.9)


def apply(o, m):
    o.data.materials.clear()
    o.data.materials.append(mat(*m))


def cube(size, loc, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    apply(o, m)
    return o


def cyl(r, depth, loc, m, axis="z", verts=12, r2=None):
    rot = {"y": (math.pi / 2, 0, 0), "x": (0, math.pi / 2, 0), "z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    apply(o, m)
    return o


def pyramid(half, height, loc, m, rot_z=math.pi / 4):
    """A square pyramid roof: a 4-vertex cone turned 45 degrees so its sides face the walls."""
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=half * math.sqrt(2.0), radius2=0.0, depth=height, location=loc, rotation=(0, 0, rot_z))
    o = bpy.context.active_object
    apply(o, m)
    return o


def gable(w, d, h, loc, m):
    """A gable roof: two slabs leaning together along the building's length (d along Y)."""
    slope = math.atan2(h, w * 0.5)
    L = math.sqrt((w * 0.5) ** 2 + h ** 2) + 0.15
    a = cube((L, d + 0.5, 0.12), (loc[0] - w * 0.25, loc[1], loc[2] + h * 0.5), m, (0, -slope, 0))
    b = cube((L, d + 0.5, 0.12), (loc[0] + w * 0.25, loc[1], loc[2] + h * 0.5), m, (0, slope, 0))
    return [a, b]


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


def export(objs, name, out=None):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(out or OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


# ---------------------------------------------------------------- the chest
def chest():
    body = []
    body.append(cube((1.1, 0.8, 0.62), (0, 0, 0.31), CHEST_WOOD))
    # iron bands around the body and the corner brackets
    for x in (-0.36, 0.36):
        body.append(cube((0.08, 0.84, 0.66), (x, 0, 0.32), CHEST_IRON))
    for x in (-0.55, 0.55):
        for y in (-0.4, 0.4):
            body.append(cube((0.05, 0.05, 0.66), (x, y, 0.32), CHEST_IRON))
    # feet, and the lock plate on the front
    for x in (-0.42, 0.42):
        for y in (-0.3, 0.3):
            body.append(cube((0.12, 0.12, 0.08), (x, y, 0.04), CHEST_IRON))
    body.append(cube((0.18, 0.04, 0.16), (0, -0.42, 0.5), GOLD))
    body.append(cube((0.06, 0.05, 0.05), (0, -0.44, 0.44), DARK))
    body_obj = join(body, "Body")
    # the lid: a box with a barrel top, hinged along the back top edge
    lid = []
    lid.append(cube((1.14, 0.84, 0.12), (0, 0, 0.68), CHEST_LID))
    lid.append(cyl(0.42, 1.14, (0, 0, 0.74), CHEST_LID, "x", 16))
    # trim the barrel below the lid line by a box of wood that hides it (cheap: the body's top band covers the seam)
    for x in (-0.36, 0.36):
        lid.append(cyl(0.44, 0.08, (x, 0, 0.74), CHEST_IRON, "x", 16))
    lid.append(cube((0.2, 0.06, 0.2), (0, -0.44, 0.8), GOLD))
    lid_obj = join(lid, "Lid")
    # remove the lower half of the barrel: bisect at the lid line
    bpy.context.view_layer.objects.active = lid_obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(plane_co=(0, 0, 0.74), plane_no=(0, 0, 1), clear_inner=True, use_fill=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    # the hinge: origin at the back top edge so a rotation about X opens it
    bpy.context.scene.cursor.location = (0, 0.42, 0.74)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    lid_obj.select_set(True)
    bpy.context.view_layer.objects.active = lid_obj
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return [body_obj, lid_obj]


# ---------------------------------------------------------------- the buildings
def forge():
    p = []
    p.append(cube((2.6, 2.2, 1.9), (0, 0, 0.95), STONE))
    p.append(cube((2.7, 2.3, 0.3), (0, 0, 0.15), STONE_DARK))
    p.append(pyramid(1.5, 1.2, (0, 0, 2.5), ROOF_SLATE))
    p.append(cube((0.5, 0.5, 1.6), (0.8, -0.5, 2.6), BRICK))
    p.append(cube((0.9, 0.1, 1.3), (0, -1.12, 0.65), DARK))
    p.append(cube((0.7, 0.05, 0.9), (0, -1.1, 0.7), EMBER))
    # the anvil on its stump, out front
    p.append(cyl(0.28, 0.5, (-1.0, -1.8, 0.25), WOOD_DARK, "z", 8))
    p.append(cube((0.7, 0.3, 0.2), (-1.0, -1.8, 0.6), IRON))
    p.append(cube((0.3, 0.26, 0.2), (-1.0, -1.8, 0.45), IRON))
    p.append(cyl(0.11, 0.35, (-0.75, -1.8, 0.6), IRON, "x", 8, r2=0.02))
    return [join(p, "forge")]


def ranch_house():
    p = []
    p.append(cube((3.2, 2.4, 2.2), (0, 0, 1.1), PLANK))
    p.append(cube((3.3, 2.5, 0.25), (0, 0, 0.12), STONE_DARK))
    p += gable(3.6, 2.6, 1.3, (0, 0, 2.2), ROOF)
    # porch: a deck and two posts under a small roof
    p.append(cube((3.2, 1.1, 0.16), (0, -1.75, 0.3), WOOD))
    for x in (-1.3, 1.3):
        p.append(cyl(0.08, 1.8, (x, -2.2, 1.2), WOOD_DARK, "z", 8))
    p.append(cube((3.4, 1.3, 0.1), (0, -1.85, 2.15), ROOF, (0.25, 0, 0)))
    p.append(cube((0.8, 0.1, 1.6), (0.6, -1.22, 1.0), DARK))
    p.append(cube((0.7, 0.1, 0.7), (-0.8, -1.22, 1.3), GLASS))
    p.append(cyl(0.32, 0.8, (1.9, -1.5, 0.4), WOOD_DARK, "z", 10))
    p.append(cube((0.5, 0.5, 0.9), (-0.9, 0.5, 2.9), BRICK))
    return [join(p, "ranch_house")]


def stable():
    p = []
    for x in (-1.6, 1.6):
        for y in (-1.2, 1.2):
            p.append(cyl(0.1, 2.4, (x, y, 1.2), WOOD_DARK, "z", 8))
    p.append(cube((3.6, 2.8, 0.14), (0, 0, 2.4), WOOD))
    p += gable(4.0, 3.0, 1.1, (0, 0, 2.45), ROOF)
    # the back wall and the hay loft
    p.append(cube((3.4, 0.12, 2.3), (0, 1.25, 1.15), PLANK))
    p.append(cube((1.4, 1.0, 0.6), (-0.8, 0.6, 0.3), HAY))
    p.append(cube((1.0, 0.8, 0.5), (0.9, 0.7, 0.25), HAY))
    # fence rails in front
    for y in (-1.9,):
        for z in (0.45, 0.95):
            p.append(cube((4.4, 0.08, 0.1), (0, y, z), WOOD))
        for x in (-2.1, -0.7, 0.7, 2.1):
            p.append(cyl(0.07, 1.3, (x, y, 0.65), WOOD_DARK, "z", 6))
    return [join(p, "stable")]


def saloon():
    p = []
    p.append(cube((3.2, 2.8, 2.6), (0, 0, 1.3), PLANK))
    p.append(cube((3.4, 3.0, 0.25), (0, 0, 0.12), STONE_DARK))
    p.append(cube((3.6, 0.16, 3.9), (0, -1.45, 1.95), WOOD))
    p.append(cube((3.6, 0.2, 0.3), (0, -1.5, 3.75), WOOD_DARK))
    p.append(cube((2.4, 0.06, 0.5), (0, -1.56, 3.1), GOLD))
    p.append(cube((0.5, 0.06, 0.34), (0, -1.6, 3.1), CLOTH))
    for x in (-1.0, 1.0):
        p.append(cube((0.7, 0.06, 0.8), (x, -1.56, 2.0), GLASS))
    for x in (-0.28, 0.28):
        p.append(cube((0.5, 0.06, 0.9), (x, -1.56, 0.9), WOOD_DARK))
    p.append(cube((3.6, 1.0, 0.1), (0, -1.9, 2.35), ROOF, (0.2, 0, 0)))
    for x in (-1.5, 1.5):
        p.append(cyl(0.07, 2.2, (x, -2.35, 1.1), WOOD_DARK, "z", 8))
    p.append(cube((3.6, 1.2, 0.12), (0, -2.0, 0.24), WOOD))
    p += gable(3.4, 3.0, 0.8, (0, 0.2, 2.6), ROOF_SLATE)
    return [join(p, "saloon")]


def watchtower():
    p = []
    for x in (-0.8, 0.8):
        for y in (-0.8, 0.8):
            p.append(cyl(0.1, 4.6, (x * 1.15, y * 1.15, 2.3), WOOD_DARK, "z", 8))
    for z in (1.2, 2.6):
        for sgn in (-1, 1):
            p.append(cube((2.6, 0.08, 0.1), (0, sgn * 0.95, z), WOOD, (0, 0.55 * sgn, 0)))
            p.append(cube((0.08, 2.6, 0.1), (sgn * 0.95, 0, z), WOOD, (0.55 * sgn, 0, 0)))
    p.append(cube((2.6, 2.6, 0.16), (0, 0, 3.7), WOOD))
    for sgn in (-1, 1):
        p.append(cube((2.6, 0.08, 0.5), (0, sgn * 1.26, 4.0), PLANK))
        p.append(cube((0.08, 2.6, 0.5), (sgn * 1.26, 0, 4.0), PLANK))
    for x in (-1.1, 1.1):
        for y in (-1.1, 1.1):
            p.append(cyl(0.07, 1.6, (x, y, 4.5), WOOD_DARK, "z", 6))
    p.append(pyramid(1.5, 0.9, (0, 0, 5.7), ROOF))
    # a ladder up the front
    for z in (0.6, 1.2, 1.8, 2.4, 3.0):
        p.append(cube((0.5, 0.06, 0.06), (0, -1.05, z), WOOD))
    for x in (-0.25, 0.25):
        p.append(cube((0.06, 0.06, 3.6), (x, -1.05, 1.8), WOOD_DARK))
    return [join(p, "watchtower")]


def well():
    """A round stone well: a low ring wall, two posts, a little gabled roof, the crank and a bucket on the rope."""
    p = []
    p.append(cyl(0.9, 0.9, (0, 0, 0.45), STONE, "z", 16, r2=0.95))
    p.append(cyl(0.7, 0.3, (0, 0, 0.95), DARK, "z", 14))
    for x in (-0.75, 0.75):
        p.append(cube((0.12, 0.12, 2.2), (x, 0, 1.6), WOOD))
    p.append(cube((0.08, 0.08, 1.7), (0, 0, 2.55), WOOD_DARK, (0, math.pi / 2, 0)))
    p += gable(2.1, 1.6, 0.6, (0, 0, 2.7), ROOF)
    p.append(cyl(0.12, 0.3, (0, 0, 2.2), BRASS, "y", 8))
    p.append(cyl(0.18, 0.3, (0, 0, 1.4), IRON, "z", 10, r2=0.14))
    return [join(p, "well")]


def market():
    """A general store that reads as one from the yard camera: a boardwalk, a wide open shop front with a counter, a
    striped awning on posts, big barrels and a sack pile out front, a tall sign board over the door. The front faces
    -Y like every other building (the yard turns them to face its centre)."""
    p = []
    p.append(cube((4.6, 3.2, 0.2), (0, -0.3, 0.1), WOOD_DARK))          # boardwalk
    p.append(cube((3.8, 2.2, 2.4), (0, 0.3, 1.4), PLANK))                 # the shop
    p += gable(4.1, 2.6, 0.9, (0, 0.3, 2.6), ROOF_SLATE)
    p.append(cube((3.0, 0.1, 1.5), (0, -0.85, 1.05), DARK))               # the open front
    p.append(cube((3.2, 0.5, 0.12), (0, -1.0, 1.05), WOOD))               # the counter
    for k in range(7):                                                     # a striped awning
        p.append(cube((0.6, 1.6, 0.08), (-1.8 + k * 0.6, -1.5, 2.3), ROOF if k % 2 == 0 else WALL, (math.radians(14), 0, 0)))
    for x in (-2.0, 2.0):
        p.append(cube((0.14, 0.14, 2.2), (x, -2.2, 1.1), WOOD))           # awning posts
    p.append(cube((2.6, 0.12, 0.8), (0, 0.25, 3.35), WOOD_DARK))          # the sign board
    p.append(cube((2.2, 0.06, 0.4), (0, 0.16, 3.35), GOLD))
    p.append(cyl(0.38, 0.8, (1.6, -1.9, 0.6), WOOD, "z", 10))             # barrels
    p.append(cyl(0.34, 0.7, (2.0, -1.2, 0.55), WOOD_DARK, "z", 10))
    p.append(cyl(0.4, 0.55, (-1.7, -1.8, 0.5), HAY, "z", 8, r2=0.25))      # sacks
    p.append(cyl(0.35, 0.5, (-2.1, -1.1, 0.45), HAY, "z", 8, r2=0.2))
    return [join(p, "market")]


def flag():
    p = [cyl(0.05, 2.2, (0, 0, 1.1), WOOD_DARK, "z", 6), cube((0.9, 0.04, 0.5), (0.45, 0, 1.9), CLOTH)]
    return [join(p, "flag")]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    # "-- only=a,b" builds just those
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = []
    for a in args:
        if a.startswith("only="):
            only = [x for x in a[5:].split(",") if x]
    for name, fn, out in (("chest", chest, None), ("forge", forge, None), ("ranch_house", ranch_house, None), ("stable", stable, None),
                          ("saloon", saloon, None), ("well", well, None), ("market", market, None), ("flag", flag, None)):
        if only and name not in only:
            continue
        clear()
        objs = fn()
        export(objs, name, out)
    clear()
    print("blender_meta: done")


main()

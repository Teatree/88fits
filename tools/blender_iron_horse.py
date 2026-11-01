"""The Iron Horse's ghost train (pass 119, lane LEGEND_A; Garry: "I added a 3d reference called
low-poly-railway-kit-free-assets.zip. You can take that, fix it to be more ghost(ly) and that will be that").

    "$BLENDER" -b --python tools/blender_iron_horse.py [-- kit=<folder> out=<glb> ref=<png>]

The engine is the kit's steam locomotive (Low-Poly Railway Kit Free by heyheythere, CC BY 4.0,
https://heyheythere.itch.io/low-poly-railway-kit-free; unzipped from _REFERENCES/3d/low-poly-railway-kit-free-assets.zip
into tools/dl/railway_kit/), its body, wheelsets and rods joined into ONE mesh; a tender and a western coach are built
here in its proportions. Three objects go into game/art/props/iron_horse.glb, front to back: `Engine`, `Tender`,
`Coach`, each with its origin on the rail top (y 0) at the middle of its own length, facing +Z in Godot (-Y here), plus
two empties under `Engine`: `Chimney` (the stack's mouth: the ghost smoke) and `Lamp` (the headlight's glass).

The ghost look is the game's (core/shaders/ghost_train.gdshader: see-through spectral blue-green, a fresnel rim, faint
bands), so the GLB carries geometry and the data the shader moves the running gear with, in two UV maps whose floats
survive the trip exactly (a vertex colour may be gamma-converted on import):
  UV0  x: the part's kind  0 body, 1 wheel (turns about its hub), 2 coupling rod (rides the crank pin round),
          3 connecting rod (its crank end rides the pin, its crosshead end slides), 4 crosshead (slides),
          5 a glowing window or lamp glass (drawn brighter)
       y: along a connecting rod, 0 at the crosshead end, 1 at the crank end
  UV1  a wheel: its hub (along, up) in metres in the car's own space (Godot axes: along +Z, up +Y); the rolling radius
       is the hub's height (the tread sits on the rail top, y 0)
       a rod or crosshead: the crank pin's rest offset from its hub (along, up)
The shader turns every wheel by travel / radius and moves the rods by rot(pin, angle) - pin with the drivers' angle.
Also renders tools/dl/iron_horse_ref.png, a three-quarter view of the engine on a transparent film (the icon's
reference, tools/gen_icon_cands.py job "iron_horse").
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(REPO, "tools", "dl", "railway_kit", "low-poly-railway-kit-free")
OUT = os.path.join(REPO, "game", "art", "props", "iron_horse.glb")
REF = os.path.join(REPO, "tools", "dl", "iron_horse_ref.png")

BODY, WHEEL, COUPLING, CONNECTING, CROSSHEAD, GLOW = 0, 1, 2, 3, 4, 5
DRIVER_R = 0.7       # the kit's driving wheels' hub height (their rolling radius)


def args():
    a = {}
    if "--" in sys.argv:
        for s in sys.argv[sys.argv.index("--") + 1:]:
            if "=" in s:
                k, v = s.split("=", 1)
                a[k] = v
    return a


def g(v):
    """A Blender point (x, y, z; forward -Y, up +Z) in Godot's car axes: (along +Z, up +Y)."""
    return (-v.y, v.z)


def set_part(bm, uv0, uv1, verts_faces, kind, f_of=None, uv1_of=None):
    """Write the kind (and the rod fraction) into UV0 and the hub / pin into UV1 for every loop of `verts_faces`."""
    for face in verts_faces:
        for loop in face.loops:
            co = loop.vert.co
            loop[uv0].uv = (float(kind), float(f_of(co)) if f_of else 0.0)
            loop[uv1].uv = uv1_of(co) if uv1_of else (0.0, 0.0)


def mesh_object(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def ghost_material():
    m = bpy.data.materials.get("ghost") or bpy.data.materials.new("ghost")
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.55, 0.95, 0.85, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.6
    return m


# ---------------------------------------------------------------- the engine (the kit's locomotive)

def engine():
    src = os.path.join(KIT, "glb", "steam_loco.glb")
    bpy.ops.import_scene.gltf(filepath=src)
    objs = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("steam_loco")]
    axles = {o.name: o.matrix_world.translation.copy() for o in objs if "axle" in o.name}
    drivers = [axles[k] for k in axles if "pony" not in k]
    mean_y = sum(v.y for v in drivers) / len(drivers)
    # the crank pin's rest offset from its hub, read off a coupling rod (it rides the pins of every driver, the main
    # driver's too, which the connecting rod and the crosshead follow)
    pin = (0.0, 0.3)
    for o in objs:
        if "coupling_rod" in o.name:
            ws = [o.matrix_world @ v.co for v in o.data.vertices]
            cy = (min(w.y for w in ws) + max(w.y for w in ws)) * 0.5
            cz = (min(w.z for w in ws) + max(w.z for w in ws)) * 0.5
            pin = (-(cy - mean_y), cz - DRIVER_R)
            break
    print("crank pin (along, up)", tuple(round(x, 3) for x in pin))
    # the middle of its length goes on the origin: every part moved by `shift` before its hub is read
    ys = [(o.matrix_world @ v.co).y for o in objs for v in o.data.vertices]
    shift = Matrix.Translation((0.0, -(min(ys) + max(ys)) * 0.5, 0.0))
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    uv1 = bm.loops.layers.uv.new("hub")
    for o in objs:
        part = bmesh.new()
        part.from_mesh(o.data)
        part.transform(shift @ o.matrix_world)
        mn = Vector((min(v.co.x for v in part.verts), min(v.co.y for v in part.verts), min(v.co.z for v in part.verts)))
        mx = Vector((max(v.co.x for v in part.verts), max(v.co.y for v in part.verts), max(v.co.z for v in part.verts)))
        # the joined mesh gets this part's faces with its own data
        tmp = bpy.data.meshes.new("tmp")
        part.to_mesh(tmp)
        part.free()
        start = len(bm.faces)
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        bm.faces.ensure_lookup_table()
        faces = bm.faces[start:]
        n = o.name
        if "axle" in n:
            hub = (shift @ o.matrix_world).translation
            set_part(bm, uv0, uv1, faces, WHEEL, uv1_of=lambda co, h=hub: g(h))
        elif "coupling_rod" in n:
            set_part(bm, uv0, uv1, faces, COUPLING, uv1_of=lambda co, p=pin: p)
        elif "connecting_rod" in n:
            # the crank end is the back one here (larger y: nearer the drivers), the crosshead end the front
            cross_y, span = mn.y, max(mx.y - mn.y, 0.01)
            set_part(bm, uv0, uv1, faces, CONNECTING, f_of=lambda co, a=cross_y, s=span: min(max((co.y - a) / s, 0.0), 1.0),
                     uv1_of=lambda co, p=pin: p)
        elif "crosshead" in n:
            set_part(bm, uv0, uv1, faces, CROSSHEAD, uv1_of=lambda co, p=pin: p)
        else:
            set_part(bm, uv0, uv1, faces, BODY)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    ys = [v.co.y for v in bm.verts]
    # the chimney's mouth: the highest point in the front half; the lamp: the smokebox's front face, at its middle
    front = [v.co for v in bm.verts if v.co.y < -1.0]
    top = max(c.z for c in front)
    stack = [c for c in front if c.z > top - 0.05]
    chim = Vector((0.0, sum(c.y for c in stack) / len(stack), top))
    box = [v.co for v in bm.verts if 1.4 < v.co.z < 3.2 and abs(v.co.x) < 0.9]
    face_y = min(c.y for c in box)
    lamp = Vector((0.0, face_y - 0.05, 2.35))
    ob = mesh_object("Engine", bm)
    for nm, at in (("Chimney", chim), ("Lamp", lamp)):
        e = bpy.data.objects.new(nm, None)
        bpy.context.scene.collection.objects.link(e)
        e.parent = ob
        e.location = at
    return ob, max(ys) - min(ys)


# ---------------------------------------------------------------- the tender and the coach, in the kit's proportions

def _box(bm, uv0, uv1, centre, size, kind=BODY):
    m = Matrix.Translation(centre) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    faces = list({f for v in res["verts"] for f in v.link_faces})
    set_part(bm, uv0, uv1, faces, kind)
    return faces


def _wheelset(bm, uv0, uv1, y, r, gauge=0.75, thick=0.14):
    """Two wheels and their axle at `y` along the car, hub `r` up: they turn about the hub (WHEEL)."""
    hub = Vector((0.0, y, r))
    faces = []
    for sx in (-1.0, 1.0):
        m = Matrix.Translation((sx * gauge, y, r)) @ Matrix.Rotation(math.radians(90.0), 4, "Y")
        res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=10, radius1=r, radius2=r, depth=thick, matrix=m)
        faces += list({f for v in res["verts"] for f in v.link_faces})
        # a hub cap a little smaller, so the turning shows
        m2 = Matrix.Translation((sx * (gauge + thick * 0.6), y, r)) @ Matrix.Rotation(math.radians(90.0), 4, "Y")
        res2 = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=r * 0.35, radius2=r * 0.25, depth=0.08, matrix=m2)
        faces += list({f for v in res2["verts"] for f in v.link_faces})
        # one spoke bar across the wheel's face: you can see it turn
        m3 = Matrix.Translation((sx * (gauge + thick * 0.55), y, r)) @ Matrix.Diagonal((0.05, r * 1.7, 0.08, 1.0))
        res3 = bmesh.ops.create_cube(bm, size=1.0, matrix=m3)
        faces += list({f for v in res3["verts"] for f in v.link_faces})
    m = Matrix.Translation((0.0, y, r)) @ Matrix.Rotation(math.radians(90.0), 4, "Y")
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=0.07, radius2=0.07, depth=gauge * 2.0, matrix=m)
    faces += list({f for v in res["verts"] for f in v.link_faces})
    set_part(bm, uv0, uv1, faces, WHEEL, uv1_of=lambda co, h=hub: g(h))


def tender():
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    uv1 = bm.loops.layers.uv.new("hub")
    L = 5.6
    _box(bm, uv0, uv1, Vector((0, 0, 0.72)), (2.3, L, 0.26))              # the frame
    _box(bm, uv0, uv1, Vector((0, 0.2, 1.72)), (2.6, L - 0.6, 1.75))      # the water tank
    _box(bm, uv0, uv1, Vector((0, 0.2, 2.62)), (2.7, L - 0.45, 0.08))     # its lip
    # the coal heap: a squashed sphere over the front half
    m = Matrix.Translation((0, -0.9, 2.55)) @ Matrix.Diagonal((1.15, 1.5, 0.45, 1.0))
    res = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0, matrix=m)
    set_part(bm, uv0, uv1, list({f for v in res["verts"] for f in v.link_faces}), BODY)
    # the tool box and the water hatch at the back
    _box(bm, uv0, uv1, Vector((0, 2.0, 2.82)), (0.8, 0.6, 0.35))
    for y in (-2.0, -1.2, 1.2, 2.0):
        _wheelset(bm, uv0, uv1, y, 0.45)
    return mesh_object("Tender", bm), L


def coach():
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    uv1 = bm.loops.layers.uv.new("hub")
    L = 9.0
    _box(bm, uv0, uv1, Vector((0, 0, 0.78)), (2.3, L - 0.2, 0.26))         # the frame
    _box(bm, uv0, uv1, Vector((0, 0, 1.95)), (2.6, L - 1.6, 2.1))          # the body
    _box(bm, uv0, uv1, Vector((0, 0, 3.06)), (2.95, L - 1.2, 0.14))        # the roof
    _box(bm, uv0, uv1, Vector((0, 0, 3.3)), (1.3, L - 2.4, 0.36))          # the clerestory
    _box(bm, uv0, uv1, Vector((0, 0, 3.5)), (1.55, L - 2.2, 0.08))         # its lid
    # six windows a side, a little proud of the body (they glow)
    n = 6
    span = L - 2.6
    for k in range(n):
        y = -span * 0.5 + span * (k + 0.5) / n
        for sx in (-1.0, 1.0):
            _box(bm, uv0, uv1, Vector((sx * 1.315, y, 2.25)), (0.04, 0.62, 0.8), GLOW)
    # the open end platforms and their railings
    for sy in (-1.0, 1.0):
        y = sy * (L * 0.5 - 0.4)
        _box(bm, uv0, uv1, Vector((0, y, 0.98)), (2.3, 0.8, 0.12))
        _box(bm, uv0, uv1, Vector((0, sy * (L * 0.5 - 0.06), 1.62)), (2.2, 0.06, 0.06))
        for sx in (-1.0, -0.33, 0.33, 1.0):
            _box(bm, uv0, uv1, Vector((sx * 1.08, sy * (L * 0.5 - 0.06), 1.3)), (0.06, 0.06, 0.66))
        # a doorway lamp-lit
        _box(bm, uv0, uv1, Vector((0, sy * (L * 0.5 - 0.79), 2.0)), (0.75, 0.04, 1.5), GLOW)
    for y in (-3.6, -2.4, 2.4, 3.6):
        _wheelset(bm, uv0, uv1, y, 0.42)
    return mesh_object("Coach", bm), L


def render_ref(ob):
    """The engine in three-quarter view, transparent film: the icon's reference (blender_ref's angle)."""
    scene = bpy.context.scene
    for o in bpy.data.objects:
        o.hide_render = o is not ob and o.type == "MESH"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 12.5
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    yaw, pitch, d = math.radians(35.0), math.radians(20.0), 30.0
    # the front is -Y: the camera stands ahead of it and a little to its left
    target = Vector((0.0, 0.0, 1.8))
    cam.location = target + Vector((-math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * d
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    light = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    light.data.energy = 3.5
    light.rotation_euler = (math.radians(50), 0, math.radians(-30))
    scene.collection.objects.link(light)
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE_NEXT"
    scene.render.film_transparent = True
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.filepath = REF
    m = bpy.data.materials.new("clay")
    m.use_nodes = True
    m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.62, 0.66, 0.7, 1.0)
    ob.data.materials.clear()
    ob.data.materials.append(m)
    os.makedirs(os.path.dirname(REF), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    ob.data.materials.clear()
    ob.data.materials.append(ghost_material())
    print("rendered", REF)


def main():
    global KIT, OUT, REF
    a = args()
    KIT = a.get("kit", KIT)
    OUT = a.get("out", OUT)
    REF = a.get("ref", REF)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    eng, el = engine()
    ten, tl = tender()
    cch, cl = coach()
    mat = ghost_material()
    for ob in (eng, ten, cch):
        ob.data.materials.clear()
        ob.data.materials.append(mat)
    # front to back along -Y here (+Z in Godot): the tender, then the coach, half a metre apart (the game places each
    # car itself; this is the layout the GLB opens with)
    ten.location = (0.0, el * 0.5 + 0.5 + tl * 0.5, 0.0)
    cch.location = (0.0, el * 0.5 + 0.5 + tl + 0.5 + cl * 0.5, 0.0)
    print("lengths engine %.2f tender %.2f coach %.2f" % (el, tl, cl))
    for e in eng.children:
        print("empty", e.name, tuple(round(x, 3) for x in e.location))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in bpy.data.objects:
        ob.select_set(True)
    kw = dict(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
              export_texcoords=True, export_normals=True, export_materials="EXPORT", export_animations=False)
    bpy.ops.export_scene.gltf(**kw)
    print("exported", OUT)
    render_ref(eng)


main()

"""The Revolver as a real model (pass 35), from the reference Garry added (tools/dl/revolver_ref/source/low_poly_revolver.blend,
a low-poly single-action revolver: objects `barrel`, `body` and `rotator`, the cylinder). The parts are turned so the
muzzle points +Y (the y-up export makes that Godot's -Z, where the Familiar aims), scaled to LENGTH metres, recoloured
(blued steel and walnut; the Golden Revolver: gold and ivory), the barrel joined into the frame as "Body" and the
cylinder kept apart as "Drum" with its pivot on its own axis, so the game turns it a chamber per shot. Exports
art/props/revolver.glb and golden_revolver.glb, and renders each from the side on green (tools/dl/revolver_ref.png,
revolver_gold_ref.png) for the icon painter.

  "$BLENDER" -b --python tools/blender_revolver.py
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "tools", "dl", "revolver_ref", "source", "low_poly_revolver.blend")
OUT = os.path.join(REPO, "game", "art", "props")
DL = os.path.join(REPO, "tools", "dl")
LENGTH = 0.46

FINISHES = {
    # metal kept low: the desert sky in a mirror-finish gun washes it out to white from the camera's height. The numbers
    # are linear (the game shows them lighter): blued steel is (20, 22, 30) here
    "revolver": {"gunMetal": ((20, 22, 30), 0.5, 0.35), "gunWood": ((110, 50, 16), 0.65, 0.0)},
    "golden_revolver": {"gunMetal": ((255, 176, 48), 0.4, 0.55), "gunWood": ((238, 228, 204), 0.45, 0.0)},
}


def fresh(name, rgb, rough, metal):
    """A clean Principled material: the reference's own have a second output fed by a plain Diffuse node, which is what
    the glTF export follows (it came out white)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    col = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = col
    return m


def build(name):
    bpy.ops.wm.open_mainfile(filepath=SRC)
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        # every part's own transform baked in, so the turn and the scale below act on the whole gun
        o.data = o.data.copy()
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for v in o.data.vertices:
            mn = Vector(map(min, mn, v.co))
            mx = Vector(map(max, mx, v.co))
    size = mx - mn
    print("bounds", tuple(round(c, 3) for c in mn), tuple(round(c, 3) for c in mx))
    # the long axis is X with the muzzle towards -X (the side render): -90 degrees about Z points it at +Y
    centre = (mn + mx) / 2
    s = LENGTH / max(size.x, 1e-6)
    xf = Matrix.Rotation(math.radians(-90.0), 4, "Z") @ Matrix.Scale(s, 4) @ Matrix.Translation(-centre)
    for o in meshes:
        o.data.transform(xf)
        o.data.update()
    fin = FINISHES[name]
    made = {k: fresh(name + "_" + k, *v) for k, v in fin.items()}
    for o in meshes:
        for slot in o.material_slots:
            if slot.material and slot.material.name in made:
                slot.material = made[slot.material.name]
    drum = bpy.data.objects.get("rotator")
    parts = [o for o in meshes if o is not drum]
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "Body"
    drum.name = "Drum"
    # the pivot on the cylinder's axis: the middle of its box, which a round cylinder has on its axis
    for o in bpy.context.scene.objects:
        o.select_set(False)
    drum.select_set(True)
    bpy.context.view_layer.objects.active = drum
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    print("drum at", tuple(round(c, 4) for c in drum.location), "dims", tuple(round(c, 4) for c in drum.dimensions))
    return body, drum


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("exported", path)


def render_side(path):
    """From the gun's right side on flat green, orthographic, the muzzle to the right."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = LENGTH * 1.25
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (2.0, 0.0, 0.0)
    cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = False
    scene.display.shading.background_type = "WORLD"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.color = (0.0, 1.0, 0.0)
    scene.render.film_transparent = False
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, ref in (("revolver", "revolver_ref.png"), ("golden_revolver", "revolver_gold_ref.png")):
        body, drum = build(name)
        export([body, drum], name)
        render_side(os.path.join(DL, ref))
    print("blender_revolver: done")


main()

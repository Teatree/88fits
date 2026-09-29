"""A contact render of the meta models (the chest and the homestead buildings) for a critical look before they ship:
every GLB from game/art/props/meta/ imported into one scene in a row, lit, rendered from a low three-quarter angle.

  "$BLENDER" -b --python tools/blender_preview.py           -> tools/dl/review/meta_models.png
"""
import math
import os

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "game", "art", "props", "meta")
OUT = os.path.join(REPO, "tools", "dl", "review", "meta_models.png")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    names = ["chest", "forge", "ranch_house", "stable", "saloon", "well", "market", "flag"]
    x = 0.0
    for n in names:
        path = os.path.join(SRC, n + ".glb")
        if not os.path.exists(path):
            continue
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.context.scene.objects if o not in before]
        # the imported objects share a parent; shift the whole group along X, chests get scaled up so they read
        s = 2.2 if n == "chest" else (1.4 if n == "flag" else 1.0)
        for o in new:
            if o.parent is None or o.parent not in new:
                o.location.x += x
                o.scale = (o.scale[0] * s, o.scale[1] * s, o.scale[2] * s)
        x += 6.0
    # ground
    bpy.ops.mesh.primitive_plane_add(size=80, location=(x * 0.5 - 3.0, 0, 0))
    g = bpy.context.active_object
    m = bpy.data.materials.new("sand")
    m.diffuse_color = (0.86, 0.68, 0.42, 1.0)
    g.data.materials.append(m)
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 30
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cx = x * 0.5 - 3.0
    cam.location = (cx, -40.0, 15.0)
    cam.rotation_euler = (math.radians(64), 0, 0)
    scene.camera = cam
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(45), math.radians(15), math.radians(35))
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.background_type = "WORLD"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.color = (0.55, 0.7, 0.9)
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 800
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = OUT
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("rendered", OUT)


main()

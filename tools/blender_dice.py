"""Two white dice as true cubes (pass 49): the reference Hot Streak's icon is painted from (Garry: "the cubes look
deformed"), so the painting copies square faces and evenly spaced pips instead of inventing them.

  "$BLENDER" -b --python tools/blender_dice.py      -> tools/dl/dice_ref.png (transparent film, 1024 px)
"""
import math
import os

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "tools", "dl", "dice_ref.png")

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def mat(name, rgb, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = rgb + (1.0,)
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = rgb + (1.0,)
    return m


WHITE = mat("die", (0.92, 0.9, 0.86), 0.35)
BLACK = mat("pip", (0.03, 0.03, 0.035), 0.5)
# pips on a face, in the face's own (u, v) from its centre, a unit die
LAYOUT = {
    1: [(0, 0)],
    2: [(-1, -1), (1, 1)],
    3: [(-1, -1), (0, 0), (1, 1)],
    4: [(-1, -1), (-1, 1), (1, -1), (1, 1)],
    5: [(-1, -1), (-1, 1), (0, 0), (1, -1), (1, 1)],
    6: [(-1, -1), (-1, 0), (-1, 1), (1, -1), (1, 0), (1, 1)],
}
STEP = 0.27


def die(at, yaw_deg, faces):
    """A rounded cube at `at` turned `yaw_deg` about the vertical; `faces` {normal axis: pips}."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    cube = bpy.context.object
    cube.data.materials.append(WHITE)
    bev = cube.modifiers.new("bevel", "BEVEL")
    bev.width = 0.11
    bev.segments = 5
    bpy.ops.object.shade_smooth()
    parts = [cube]
    for normal, n in faces.items():
        nrm = Vector(normal)
        # two axes across the face
        u = Vector((0, 0, 1)) if abs(nrm.z) < 0.5 else Vector((1, 0, 0))
        v = nrm.cross(u)
        for (pu, pv) in LAYOUT[n]:
            c = nrm * 0.5 + u * pu * STEP + v * pv * STEP
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.075, segments=16, ring_count=8, location=c - nrm * 0.012)
            pip = bpy.context.object
            # flattened into the face
            pip.scale = Vector((1, 1, 1)) - Vector((abs(nrm.x), abs(nrm.y), abs(nrm.z))) * 0.7
            pip.data.materials.append(BLACK)
            bpy.ops.object.shade_smooth()
            parts.append(pip)
    root = bpy.data.objects.new("die", None)
    scene.collection.objects.link(root)
    for p in parts:
        p.parent = root
    root.location = Vector(at)
    root.rotation_euler = (0, 0, math.radians(yaw_deg))


# the front die shows six to the camera (-Y), five on top, three on its right; the second sits behind and to the right,
# turned the other way, six to the camera as well
die((-0.62, 0.0, 0.5), 18.0, {(0, -1, 0): 6, (0, 0, 1): 5, (1, 0, 0): 3, (-1, 0, 0): 4})
die((0.7, 0.55, 0.5), -24.0, {(0, -1, 0): 6, (0, 0, 1): 2, (1, 0, 0): 4, (-1, 0, 0): 3})

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 70
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
target = Vector((0.05, 0.25, 0.45))
cam.location = target + Vector((1.2, -6.2, 3.4))
cam.rotation_mode = "QUATERNION"
cam.rotation_quaternion = (target - cam.location).to_track_quat("-Z", "Y")
scene.render.resolution_x = 1024
scene.render.resolution_y = 1024
scene.render.film_transparent = True
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_cavity = True
scene.display.shading.show_object_outline = True
scene.display.shading.object_outline_color = (0.05, 0.05, 0.05)
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("blender_dice: wrote", OUT)

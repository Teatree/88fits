"""Pose drivers for Wan Animate from Mixamo clips: one clean stride per view, at the exact frame count we want.

Stage 1 (inside Blender): read the armature of a Mixamo FBX, resample one full stride to N frames and write the
2D OpenPose keypoints for each of the game's five views (back, back-diagonal, side, front-diagonal, front, the
side and diagonals facing screen-right like the painted stills), seen from a camera a little above the figure.
Stage 2 (plain Python): draw those keypoints as OpenPose skeletons (coloured limbs on black), the format the
WanAnimateToVideo node expects, plus a contact sheet per view.

    "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/running.fbx out=tools/dl/drivers/run frames=24 pitch=25
    "$BLENDER" -b --python tools/pose_driver.py -- fbx=tools/dl/mixamo/pain_gesture.fbx out=tools/dl/drivers/hit frames=9 loop=0 start=0.2 end=1.0
    python tools/pose_driver.py draw tools/dl/drivers/run

Loops (loop=1, default): N frames of the whole action plus a repeat of the first, so Wan's 4k+1 length closes the loop.
One-shots (loop=0): N frames evenly from `start` to `end` seconds, N itself 4k+1.
Output: <out>/<view>/poses.json, <out>/<view>/driver_NN.png, <out>/<view>_sheet.png, <out>/meta.json.
"""
import json
import math
import os
import sys

VIEWS = {"back": 0.0, "bd": 45.0, "side": 90.0, "fd": 135.0, "front": 180.0}   # forward yaw in screen space, 0 = into the screen
SIZE = 640
FILL = 0.72   # figure height as a fraction of the frame, like tools/animate._prep_still

# OpenPose body-18 order
KP = ["nose", "neck", "rsho", "relb", "rwri", "lsho", "lelb", "lwri", "rhip", "rknee", "rank", "lhip", "lknee", "lank", "reye", "leye", "rear", "lear"]
LIMBS = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13), (1, 0), (0, 14), (14, 16), (0, 15), (15, 17)]
COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0), (0, 255, 0), (0, 255, 85), (0, 255, 170),
          (0, 255, 255), (0, 170, 255), (0, 85, 255), (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255), (255, 0, 170), (255, 0, 85)]
# DWPose hand: wrist, then thumb, index, middle, ring, pinky, four joints each from the base to the tip
HAND_BONES = ["Hand"] + [f + str(k) for f in ("HandThumb", "HandIndex", "HandMiddle", "HandRing", "HandPinky") for k in (1, 2, 3, 4)]
HAND_EDGES = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (0, 9), (9, 10), (10, 11), (11, 12), (0, 13), (13, 14), (14, 15), (15, 16), (0, 17), (17, 18), (18, 19), (19, 20)]
BONES = {"neck": "Neck", "rsho": "RightArm", "relb": "RightForeArm", "rwri": "RightHand", "lsho": "LeftArm", "lelb": "LeftForeArm",
         "lwri": "LeftHand", "rhip": "RightUpLeg", "rknee": "RightLeg", "rank": "RightFoot", "lhip": "LeftUpLeg", "lknee": "LeftLeg", "lank": "LeftFoot"}


def _args():
    out = {}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    for a in argv:
        if "=" in a:
            k, v = a.split("=", 1)
            out[k] = v
    return out


# ---------------------------------------------------------------- stage 1: Blender

def extract():
    import bpy
    from mathutils import Vector, Matrix
    a = _args()
    fbx = a["fbx"]
    out = a["out"]
    n = int(a.get("frames", 24))
    loop = a.get("loop", "1") not in ("0", "false", "no")
    pitch = math.radians(float(a.get("pitch", 25.0)))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fbx)
    sc = bpy.context.scene
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    act = arm.animation_data.action
    f0, f1 = act.frame_range
    fps = sc.render.fps
    if not loop:
        # a one-shot: the slice of the action between start and end seconds
        f0 = f0 + float(a.get("start", 0.0)) * fps
        f1 = min(f1, act.frame_range[0] + float(a.get("end", (act.frame_range[1] - act.frame_range[0]) / fps)) * fps)
    pb = {b.name.split(":")[-1]: b for b in arm.pose.bones}

    def joint(name, f):
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        return arm.matrix_world @ pb[name].head

    # the character's forward: the feet point forward (toe minus ankle), averaged over the stride
    fwd = Vector((0, 0, 0))
    for k in range(8):
        f = f0 + (f1 - f0) * k / 8.0
        for side in ("Left", "Right"):
            v = joint(side + "ToeBase", f) - joint(side + "Foot", f)
            v.z = 0.0
            fwd += v
    fwd.normalize()
    up = Vector((0, 0, 1))
    yaw0 = math.atan2(fwd.y, fwd.x)   # world yaw of "forward"
    # ground level and figure height, from the whole stride
    zs, tops = [], []
    for k in range(n):
        f = f0 + (f1 - f0) * k / n
        zs.append(min(joint("LeftFoot", f).z, joint("RightFoot", f).z))
        tops.append(joint("HeadTop_End", f).z if "HeadTop_End" in pb else joint("Head", f).z + 0.2)
    ground = min(zs)
    height = max(tops) - ground
    print("pose_driver: forward yaw %.0f deg, figure %.2f m, stride %d source frames -> %d" % (math.degrees(yaw0), height, int(f1 - f0), n))
    for view, want_deg in VIEWS.items():
        # rotate the world so the character's forward points `want_deg` from "into the screen"; screen-right is +X
        # camera looks along +Y (into the screen), tilted down by `pitch`, at the figure's mid height
        # screen-right is +X and "into the screen" is +Y; a positive yaw about +Z turns +Y toward -X, so the wanted
        # turn toward screen-right is applied with the opposite sign
        want = math.radians(want_deg)
        rot = Matrix.Rotation(math.pi * 0.5 - want - yaw0, 4, "Z")
        cam_dir = Vector((0.0, math.cos(pitch), -math.sin(pitch)))    # into the screen and down
        cam_up = Vector((0.0, math.sin(pitch), math.cos(pitch)))
        cam_right = Vector((1.0, 0.0, 0.0))
        frames = []
        count = n + 1 if loop else n
        for k in range(count):
            f = f0 + (f1 - f0) * ((k % n) / n if loop else (k / max(n - 1, 1)))
            pts = {}
            for key, bone in BONES.items():
                pts[key] = rot @ joint(bone, f)
            head = rot @ joint("Head", f)
            top = rot @ (joint("HeadTop_End", f) if "HeadTop_End" in pb else joint("Head", f) + Vector((0, 0, 0.2)))
            hfwd = rot @ Vector((fwd.x, fwd.y, 0.0))
            hright = hfwd.cross(up)   # the character's right
            centre = (head + top) * 0.5
            nose = centre + hfwd * 0.09 - up * 0.01
            pts["nose"] = nose
            pts["reye"] = nose + hright * 0.03 + up * 0.03 - hfwd * 0.02
            pts["leye"] = nose - hright * 0.03 + up * 0.03 - hfwd * 0.02
            pts["rear"] = centre + hright * 0.075
            pts["lear"] = centre - hright * 0.075
            facing = hfwd.dot(-cam_dir)   # > 0: face toward the camera
            vis = {k2: True for k2 in KP}
            vis["nose"] = vis["reye"] = vis["leye"] = facing > 0.15
            vis["rear"] = hright.dot(-cam_dir) > -0.25
            vis["lear"] = (-hright).dot(-cam_dir) > -0.25
            span = height / FILL   # orthographic: the frame spans height / FILL metres vertically

            def project(p):
                rel = p - Vector((0.0, 0.0, ground + height * 0.5))
                return round(0.5 + rel.dot(cam_right) / span, 4), round(0.5 - rel.dot(cam_up) / span + 0.04, 4)   # feet near the bottom like the stills

            row = []
            for key in KP:
                u, v = project(pts[key])
                row.append([u, v, 1 if vis[key] else 0])
            # hands: 21 points each, so the video model knows where every finger is
            hands = {}
            for side_name, tag in (("Left", "l"), ("Right", "r")):
                hp = []
                for bone in HAND_BONES:
                    name = side_name + bone
                    hp.append(list(project(rot @ joint(name, f))) if name in pb else None)
                hands[tag] = hp
            frames.append({"body": row, "hands": hands})
        d = os.path.join(out, view)
        os.makedirs(d, exist_ok=True)
        json.dump({"view": view, "frames": frames, "size": SIZE, "fbx": os.path.basename(fbx), "n": n, "pitch": math.degrees(pitch)},
                  open(os.path.join(d, "poses.json"), "w"), indent=0)
        print("pose_driver: wrote", d, len(frames), "frames")
    json.dump({"fbx": os.path.basename(fbx), "frames": n, "loop": loop, "pitch": math.degrees(pitch), "start": a.get("start"), "end": a.get("end")},
              open(os.path.join(out, "meta.json"), "w"), indent=1)


# ---------------------------------------------------------------- stage 2: draw

def _ellipse_poly(p0, p1, w):
    (x0, y0), (x1, y1) = p0, p1
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    L = math.hypot(x1 - x0, y1 - y0)
    ang = math.atan2(y1 - y0, x1 - x0)
    pts = []
    for k in range(24):
        t = 2 * math.pi * k / 24
        ex, ey = math.cos(t) * L / 2, math.sin(t) * w
        pts.append((mx + ex * math.cos(ang) - ey * math.sin(ang), my + ex * math.sin(ang) + ey * math.cos(ang)))
    return pts


def draw(folder):
    from PIL import Image, ImageDraw
    sheets = []
    for view in VIEWS:
        d = os.path.join(folder, view)
        meta = json.load(open(os.path.join(d, "poses.json")))
        size = meta["size"]
        w = max(2, int(size * 0.008))
        r = max(2, int(size * 0.008))
        imgs = []
        for k, fr in enumerate(meta["frames"]):
            row = fr["body"] if isinstance(fr, dict) else fr
            hands = fr.get("hands", {}) if isinstance(fr, dict) else {}
            img = Image.new("RGB", (size, size), (0, 0, 0))
            over = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            od = ImageDraw.Draw(over)
            pts = [(u * size, v * size, vis) for u, v, vis in row]
            for li, (a, b) in enumerate(LIMBS):
                if pts[a][2] and pts[b][2]:
                    od.polygon(_ellipse_poly(pts[a][:2], pts[b][:2], w), fill=COLORS[li] + (153,))
            img.paste(over, mask=over.getchannel("A"))
            dd = ImageDraw.Draw(img)
            for ji, (x, y, vis) in enumerate(pts):
                if vis:
                    dd.ellipse((x - r, y - r, x + r, y + r), fill=COLORS[ji])
            # hands in the DWPose style: thin rainbow edges, small blue joints
            import colorsys
            hw = max(1, int(size * 0.004))
            hr = max(1, int(size * 0.005))
            for tag in ("l", "r"):
                hp = hands.get(tag) or []
                if len(hp) < 21 or any(p is None for p in hp):
                    continue
                hxy = [(p[0] * size, p[1] * size) for p in hp]
                for ei, (a, b) in enumerate(HAND_EDGES):
                    col = tuple(int(c * 255) for c in colorsys.hsv_to_rgb(ei / float(len(HAND_EDGES)), 1.0, 1.0))
                    dd.line([hxy[a], hxy[b]], fill=col, width=hw)
                for (x, y) in hxy:
                    dd.ellipse((x - hr, y - hr, x + hr, y + hr), fill=(0, 0, 255))
            img.save(os.path.join(d, "driver_%02d.png" % k))
            imgs.append(img)
        cols = 13
        rows = (len(imgs) + cols - 1) // cols
        cell = 120
        sheet = Image.new("RGB", (cols * cell, rows * cell), (30, 30, 36))
        for i, im in enumerate(imgs):
            t = im.resize((cell, cell))
            sheet.paste(t, ((i % cols) * cell, (i // cols) * cell))
        sheet.save(os.path.join(folder, view + "_sheet.png"))
        sheets.append(sheet)
        print("pose_driver: drew", view, len(imgs), "frames")
    if sheets:
        from PIL import Image as I2
        big = I2.new("RGB", (max(s.width for s in sheets), sum(s.height for s in sheets)), (30, 30, 36))
        y = 0
        for s in sheets:
            big.paste(s, (0, y))
            y += s.height
        big.save(os.path.join(folder, "all_sheet.png"))


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
        extract()
    except ImportError:
        if len(sys.argv) >= 3 and sys.argv[1] == "draw":
            draw(sys.argv[2])
        else:
            print(__doc__)

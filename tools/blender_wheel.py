"""Pass 126 (lane DRESS; Garry: "a random toppled over westerny cart with a wheel or two lying on the ground ... the wheels
are 3d"): the cart's wagon wheels, one GLB game/art/props/wagon_wheel.glb with these objects, the hub on the origin and the
axle along Blender z (Godot y), so a wheel with no turn lies flat on the sand:

  WheelA   whole: an iron tyre, a felloe in 16 pieces, 10 tapered spokes, a hub with an iron ring, radius RADIUS
  WheelB   worn: two felloe pieces and the tyre there gone, two spokes missing, one snapped short
  WheelC   heavier and shorter of spokes: 8 spokes, no iron tyre left

core/systems/MapDressing.gd merges them into the map's one dressing mesh (it names RADIUS as WHEEL_R).

  "$BLENDER" -b --python tools/blender_wheel.py
"""
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_lowpoly as lp  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "wagon_wheel.glb")

RADIUS = 0.62
WOOD = (0.58, 0.48, 0.36)
SPOKE = (0.68, 0.59, 0.46)
HUB = (0.42, 0.34, 0.26)
IRON = (0.27, 0.25, 0.24)
SEGS = 16


def felloe(m, r0, r1, depth, col, skip=()):
    """A ring with a rectangular section, SEGS pieces, those in `skip` left out."""
    for k in range(SEGS):
        if k in skip:
            continue
        a0 = math.tau * k / SEGS
        a1 = math.tau * (k + 1) / SEGS
        quad = []
        for a in (a0, a1):
            c, s = math.cos(a), math.sin(a)
            quad.append((Vector((c * r0, s * r0, -depth)), Vector((c * r1, s * r1, -depth)), Vector((c * r1, s * r1, depth)), Vector((c * r0, s * r0, depth))))
        base = len(m.verts)
        for ring in quad:
            m.verts.extend(ring)
        for i in range(4):
            j = (i + 1) % 4
            m.face([base + i, base + j, base + 4 + j, base + 4 + i], col)
        # the broken pieces' ends show their section
        if (k + 1) % SEGS in skip:
            m.face([base + 4, base + 5, base + 6, base + 7], col)
        if (k - 1) % SEGS in skip:
            m.face([base + 3, base + 2, base + 1, base + 0], col)


def spokes(m, n, r_in, r_out, skip=(), short=()):
    for k in range(n):
        if k in skip:
            continue
        a = math.tau * k / n + 0.11
        c, s = math.cos(a), math.sin(a)
        end = r_out * (0.55 if k in short else 1.0)
        m.tube([(c * r_in, s * r_in, 0.0), (c * end, s * end, 0.0)], [0.034, 0.024], SPOKE, 4, phase=0.78)


def hub(m, r=0.11, depth=0.09):
    m.tube([(0, 0, -depth), (0, 0, -depth * 0.55), (0, 0, depth * 0.55), (0, 0, depth)], [r * 0.72, r, r, r * 0.72], HUB, 8)
    m.tube([(0, 0, -depth * 0.4), (0, 0, depth * 0.4)], [r * 1.05, r * 1.05], IRON, 8, caps=(False, False))


def wheel_a():
    m = lp.Model("WheelA", 31)
    felloe(m, RADIUS - 0.1, RADIUS - 0.02, 0.042, WOOD)
    felloe(m, RADIUS - 0.02, RADIUS, 0.046, IRON)
    spokes(m, 10, 0.09, RADIUS - 0.09)
    hub(m)
    return m.build()


def wheel_b():
    m = lp.Model("WheelB", 32)
    gap = (3, 4)
    felloe(m, RADIUS - 0.1, RADIUS - 0.02, 0.042, WOOD, skip=gap)
    felloe(m, RADIUS - 0.02, RADIUS, 0.046, IRON, skip=(2, 3, 4, 5))
    spokes(m, 10, 0.09, RADIUS - 0.09, skip=(2, 7), short=(1,))
    hub(m)
    return m.build()


def wheel_c():
    m = lp.Model("WheelC", 33)
    r = RADIUS * 0.92
    felloe(m, r - 0.12, r, 0.05, (0.53, 0.44, 0.33))
    spokes(m, 8, 0.1, r - 0.1, short=(5,))
    hub(m, 0.125, 0.1)
    return m.build()


def main():
    lp.fresh()
    objs = [wheel_a(), wheel_b(), wheel_c()]
    lp.export(objs, OUT)


if __name__ == "__main__":
    main()

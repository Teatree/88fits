"""Pass 126 (lane DRESS; Garry: "Let's add the telephone pole generation that cuts across the whole desert ... It's often
broken in many places"): the telephone poles, one GLB game/art/props/telephone_pole.glb with these objects, every foot on
the origin, in metres:

  PoleA   the whole pole: a slightly crooked weathered post 5.6 m tall, a crossarm along x with two braces and two glass
          insulators (the wire's anchors: x = +-ANCHOR_X, z = ANCHOR_Z; core/systems/TelephoneLine.gd names the same numbers)
  PoleB   the same pole more worn: the crossarm hanging askew, one brace gone, a second short arm below
  SnapA   a post snapped at 2.3 m, its top a splintered crown of pale fresh wood
  SnapB   a stump snapped at 1.1 m
  Fallen  the snapped-off top lying on the sand: 3 m of post and its arm, all of it just over z = 0, the break at the origin

TelephoneLine merges them into the map's one dressing mesh (core/systems/MapDressing.gd).

  "$BLENDER" -b --python tools/blender_telephone.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_lowpoly as lp  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "telephone_pole.glb")

WOOD = (0.39, 0.30, 0.215)
WOOD_DARK = (0.30, 0.225, 0.16)
ARM = (0.43, 0.34, 0.25)
FRESH = (0.66, 0.53, 0.36)
GLASS = (0.50, 0.66, 0.60)
H = 5.6
R0, R1 = 0.115, 0.085
ARM_Z = 5.12
ARM_L = 1.46
ANCHOR_X = 0.58
ANCHOR_Z = 5.29


def post(m, height, r0=R0, r1=R1, kink=0.05, cap=True):
    pts = []
    rad = []
    for k in range(5):
        f = k / 4.0
        off = math.sin(f * 2.4 + 0.5) * kink * f
        pts.append((off, off * 0.6, height * f))
        rad.append(r0 + (r1 - r0) * f)
    # a little below the ground, so a tilted foot never shows its end
    pts.insert(0, (0.0, 0.0, -0.3))
    rad.insert(0, r0)
    m.tube(pts, rad, WOOD, 6, caps=(True, cap))
    return pts[-1]


def splinters(m, top, r, col=FRESH, h=0.34):
    """A crown of sharp pale slivers on a broken post's end."""
    n = 6
    for k in range(n):
        t = math.tau * k / n + 0.3
        ring = (top[0] + math.cos(t) * r * 0.62, top[1] + math.sin(t) * r * 0.62, top[2] - 0.02)
        hh = h * (0.45 + 0.55 * ((k * 5) % n) / (n - 1))
        tip = (ring[0] + math.cos(t) * 0.03, ring[1] + math.sin(t) * 0.03, top[2] + hh)
        m.tube([ring, tip], [r * 0.5, 0.004], col if k % 2 else WOOD, 4)
    m.tube([(top[0], top[1], top[2] - 0.04), (top[0], top[1], top[2] + 0.02)], [r * 0.98, r * 0.98], col, 6)


def insulator(m, x, z):
    m.tube([(x, 0, z), (x, 0, z + 0.05), (x, 0, z + 0.13)], [0.03, 0.045, 0.02], GLASS, 5)


def pole_a():
    m = lp.Model("PoleA", 11)
    post(m, H)
    m.box((0, 0, ARM_Z), (ARM_L, 0.1, 0.1), ARM)
    for s in (-1, 1):
        # a brace from the post up to the arm
        a = (0.0, -0.06, ARM_Z - 0.6)
        b = (s * 0.42, -0.06, ARM_Z - 0.05)
        m.tube([a, b], [0.022, 0.022], WOOD_DARK, 4)
        insulator(m, s * ANCHOR_X, ARM_Z + 0.05)
    return m.build()


def pole_b():
    m = lp.Model("PoleB", 12)
    post(m, H - 0.15, kink=0.09)
    m.box((0.03, 0, ARM_Z - 0.15), (ARM_L, 0.1, 0.1), ARM, rot=(0, 9, 0))
    m.box((0, 0, ARM_Z - 0.85), (0.8, 0.09, 0.09), WOOD_DARK, rot=(0, -5, 0))
    m.tube([(0.0, -0.06, ARM_Z - 0.75), (0.42, -0.06, ARM_Z - 0.28)], [0.022, 0.022], WOOD_DARK, 4)
    insulator(m, -ANCHOR_X, ARM_Z + 0.0)
    insulator(m, ANCHOR_X, ARM_Z - 0.14)
    return m.build()


def snap(name, height, seed):
    m = lp.Model(name, seed)
    r = R0 - (R0 - R1) * height / H
    top = post(m, height, r1=r, kink=0.03, cap=False)
    splinters(m, top, r)
    return m.build()


def fallen():
    m = lp.Model("Fallen", 14)
    lie = 0.09
    pts = [(0.0, 0.0, lie), (1.0, 0.03, lie), (2.0, 0.0, lie), (3.0, 0.02, lie)]
    m.tube(pts, [0.1, 0.095, 0.09, 0.085], WOOD, 6)
    m.tube([(-0.02, 0.0, lie), (-0.2, 0.05, lie)], [0.09, 0.006], FRESH, 4)
    m.box((2.5, 0.0, lie + 0.1), (0.1, ARM_L, 0.1), ARM, rot=(6, 0, 4))
    return m.build()


def main():
    lp.fresh()
    objs = [pole_a(), pole_b(), snap("SnapA", 2.3, 21), snap("SnapB", 1.1, 22), fallen()]
    lp.export(objs, OUT)


if __name__ == "__main__":
    main()

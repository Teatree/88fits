"""Pass 126 (lane DRESS; Garry: "Add random Crosses for graves ... The Crosses are often crooked and each looks different
from the rest ... Very rarely 5% chance a cross will be just a stick sticking out of the ground"): one GLB
game/art/props/grave_cross.glb, every foot on the origin, each post running a little under it (the game cuts them at the
ground):

  Cross0..Cross9   ten different grave crosses: thickness and height of the post, height and length of the bar, nailed or
                   roped, pale or dark wood, a twisted bar, a broken arm, a slipped bar, branches
  Stick0, Stick1   bare sticks, no bar

core/systems/MapDressing.gd merges them into the map's one dressing mesh with its own turn, tilt, size and sink for each.

  "$BLENDER" -b --python tools/blender_grave_cross.py
"""
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_lowpoly as lp  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "game", "art", "props", "grave_cross.glb")

DARK = (0.43, 0.32, 0.22)
MID = (0.56, 0.44, 0.32)
PALE = (0.74, 0.66, 0.55)
GREY = (0.64, 0.61, 0.56)
ROPE = (0.76, 0.66, 0.46)
NAIL = (0.13, 0.115, 0.105)
SPLINTER = (0.74, 0.62, 0.45)


def plank(m, height, w, t, col, top=0.0, crooked=0.0, under=0.25):
    """A squared post: w wide (x), t thick (y), its end cut at `top` (0 flat, more: a point)."""
    n = 4
    rings = []
    pts = [(0, 0, -under), (crooked * 0.4, 0, height * 0.35), (crooked, crooked * 0.3, height * 0.7), (crooked * 0.6, crooked * 0.3, height)]
    for p in pts:
        base = len(m.verts)
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            m.verts.append(Vector((p[0] + sx * w * 0.5, p[1] + sy * t * 0.5, p[2])))
        rings.append(base)
    for r0, r1 in zip(rings[:-1], rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            m.face([r0 + k, r0 + k2, r1 + k2, r1 + k], col)
    m.face([rings[0] + 3, rings[0] + 2, rings[0] + 1, rings[0]], col)
    r = rings[-1]
    if top > 0.0:
        tip = len(m.verts)
        p = pts[-1]
        m.verts.append(Vector((p[0], p[1] - t * 0.5, p[2] + top)))
        m.verts.append(Vector((p[0], p[1] + t * 0.5, p[2] + top)))
        m.face([r, r + 1, tip], col)
        m.face([r + 2, r + 3, tip + 1], col)
        m.face([r + 1, r + 2, tip + 1, tip], col)
        m.face([r + 3, r, tip, tip + 1], col)
    else:
        m.face([r, r + 1, r + 2, r + 3], col)


def nails(m, x, z, y, count=2, spread=0.03):
    for k in range(count):
        m.box((x + (k - (count - 1) * 0.5) * spread * 1.6, y, z + (k % 2 - 0.5) * spread), (0.022, 0.012, 0.022), NAIL)


def rope(m, z, r_x, r_y, turns=3, step=0.022, y=0.0, x=0.0):
    for k in range(turns):
        zk = z + (k - (turns - 1) * 0.5) * step
        m.tube([(x, y, zk), (x, y, zk + 0.016)], [r_x, r_x], ROPE, 6, squash=r_y / r_x)


def cross0():
    m = lp.Model("Cross0", 40)
    plank(m, 1.25, 0.11, 0.05, MID)
    m.box((0, -0.04, 0.88), (0.68, 0.035, 0.095), MID)
    nails(m, 0, 0.88, -0.062)
    return m.build()


def cross1():
    m = lp.Model("Cross1", 41)
    plank(m, 1.55, 0.16, 0.09, DARK)
    m.box((0, -0.065, 1.08), (1.02, 0.05, 0.13), DARK)
    rope(m, 1.08, 0.13, 0.115, 4, 0.03, y=-0.02)
    return m.build()


def cross2():
    m = lp.Model("Cross2", 42)
    plank(m, 1.1, 0.075, 0.05, GREY, crooked=0.09)
    m.box((0.05, -0.035, 0.74), (0.52, 0.03, 0.07), GREY, rot=(0, 9, 0))
    nails(m, 0.05, 0.74, -0.055, 1)
    return m.build()


def cross3():
    m = lp.Model("Cross3", 43)
    plank(m, 1.35, 0.1, 0.06, MID)
    # a twisted bar: its two halves turned opposite ways along their length
    m.box((-0.24, -0.05, 0.96), (0.5, 0.03, 0.09), MID, rot=(22, 3, 0))
    m.box((0.24, -0.05, 0.96), (0.5, 0.03, 0.09), MID, rot=(-18, -3, 0))
    nails(m, 0, 0.96, -0.072)
    return m.build()


def cross4():
    m = lp.Model("Cross4", 44)
    plank(m, 1.4, 0.12, 0.06, PALE, top=0.08)
    # one arm long, the other snapped short with a pale break
    m.box((0.18, -0.045, 1.0), (0.56, 0.03, 0.1), PALE)
    m.box((-0.14, -0.045, 1.0), (0.14, 0.03, 0.1), PALE, rot=(0, 6, 0))
    m.tube([(-0.21, -0.045, 0.99), (-0.3, -0.045, 1.01)], [0.03, 0.003], SPLINTER, 4)
    nails(m, 0.0, 1.0, -0.066)
    return m.build()


def cross5():
    m = lp.Model("Cross5", 45)
    plank(m, 0.9, 0.2, 0.05, GREY, top=0.12)
    m.box((0, -0.04, 0.62), (0.8, 0.035, 0.15), GREY)
    nails(m, 0, 0.62, -0.062, 2, 0.05)
    return m.build()


def cross6():
    m = lp.Model("Cross6", 46)
    plank(m, 1.75, 0.07, 0.07, DARK, crooked=-0.05)
    m.box((-0.03, -0.05, 1.42), (0.46, 0.04, 0.06), DARK, rot=(0, -6, 0))
    rope(m, 1.42, 0.075, 0.09, 3, 0.022, y=-0.012, x=-0.03)
    return m.build()


def cross7():
    m = lp.Model("Cross7", 47)
    plank(m, 1.2, 0.13, 0.04, PALE)
    # the bar slipped down on its one nail, hanging at an angle
    m.box((0.07, -0.032, 0.62), (0.7, 0.028, 0.09), PALE, rot=(0, 26, 0))
    nails(m, -0.01, 0.65, -0.05, 1)
    return m.build()


def cross8():
    m = lp.Model("Cross8", 48)
    # two branches tied together: round, knotty, the arm's ends cut uneven
    m.tube([(0, 0, -0.25), (0.02, 0.01, 0.42), (-0.03, 0.0, 0.85), (0.02, 0.02, 1.32)], [0.058, 0.05, 0.05, 0.036], MID, 6)
    m.tube([(-0.42, -0.05, 0.87), (-0.14, -0.06, 0.93), (0.16, -0.06, 0.91), (0.38, -0.05, 0.98)], [0.026, 0.038, 0.038, 0.024], MID, 6)
    rope(m, 0.91, 0.08, 0.08, 4, 0.026, y=-0.03)
    return m.build()


def cross9():
    m = lp.Model("Cross9", 49)
    # the post snapped off just over the bar, the bar nailed on low with a second board behind it
    plank(m, 0.86, 0.12, 0.06, DARK, crooked=0.03)
    m.tube([(0.02, 0.0, 0.84), (0.03, 0.0, 0.98)], [0.05, 0.004], SPLINTER, 4)
    m.box((0.02, -0.046, 0.66), (0.72, 0.03, 0.1), DARK, rot=(0, -4, 0))
    m.box((0.02, 0.04, 0.66), (0.18, 0.02, 0.12), MID, rot=(0, 12, 0))
    return m.build()


def stick0():
    m = lp.Model("Stick0", 50)
    m.tube([(0, 0, -0.25), (0.04, 0.01, 0.35), (-0.02, 0.03, 0.75), (0.05, 0.03, 1.12)], [0.042, 0.036, 0.028, 0.012], GREY, 5)
    m.tube([(-0.01, 0.03, 0.68), (-0.13, 0.05, 0.95)], [0.016, 0.006], GREY, 4)
    return m.build()


def stick1():
    m = lp.Model("Stick1", 51)
    m.tube([(0, 0, -0.25), (-0.03, 0.0, 0.3), (0.02, -0.02, 0.62), (0.0, -0.01, 0.82)], [0.05, 0.044, 0.04, 0.036], DARK, 5)
    m.tube([(0.0, -0.01, 0.8), (0.015, -0.01, 0.94)], [0.03, 0.003], SPLINTER, 4)
    return m.build()


def main():
    lp.fresh()
    objs = [cross0(), cross1(), cross2(), cross3(), cross4(), cross5(), cross6(), cross7(), cross8(), cross9(), stick0(), stick1()]
    lp.export(objs, OUT)


if __name__ == "__main__":
    main()

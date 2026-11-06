"""Pass 128 (lane ENV; Garry: "Create 5 additional variations of each of the 2.5d environment art assets"): the toppled
cart's five other wreck states as Blender renders, each the reference tools/gen_env_variations.py paints one cart
variation from (the same wagon as tools/blender_cart.py: its parts, its camera, its blue screen; only the state differs).

  "$BLENDER" -b --python tools/blender_cart_states.py [-- out=tools/dl/p128/ENV/cart_refs only=b,c size=1024]
      -> <out>/cart_toppled_<letter>.png (+ _clay.png)

  b Open Box    tipped the other way: the open box faces the camera, both wheels up on top
  c Belly Up    upside down, the underside to the sky, the wheels standing behind it
  d One Wheel   the front wheel gone, the other end turned towards us
  e Burnt Wreck the original's pose, every colour charred
  f No Wheels   both wheels gone, turned a little more
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_cart as bc  # noqa: E402
import blender_lowpoly as lp  # noqa: E402

# letter: up (the side that ends on top), tip, yaw, wheels [(axle end -1 front | 1 back, broken)], char
STATES = {
    "b": {"up": 1, "tip": 100.0, "yaw": -16.0, "wheels": [(1, False), (-1, True)]},
    "c": {"up": -1, "tip": -172.0, "yaw": -14.0, "wheels": [(1, False), (-1, True)]},
    "d": {"up": -1, "tip": -100.0, "yaw": 18.0, "wheels": [(1, False)]},
    "e": {"up": -1, "tip": -100.0, "yaw": -22.0, "wheels": [(1, False), (-1, True)], "char": True},
    "f": {"up": -1, "tip": -97.0, "yaw": -30.0, "wheels": []},
}


def char(c):
    """A colour burnt: charcoal, a little warm, the light planks a paler ash grey."""
    grey = (c[0] + c[1] + c[2]) / 3.0
    out = (0.07 + 0.3 * grey, 0.06 + 0.27 * grey, 0.055 + 0.25 * grey)
    return out + tuple(c[3:])


def build(st):
    """blender_cart.build with the state's side up, its wheels and its colours."""
    bc.UP = int(st["up"])
    m = lp.Model("Cart", 77, jitter=0.1)
    bc.planks_floor(m)
    bc.side(m, -1)
    bc.side(m, 1)
    bc.ends(m)
    bc.under(m)
    y = bc.UP * (bc.W / 2.0 + bc.AXLE_OUT + bc.SKEIN * 0.4)
    for end, broken in st["wheels"]:
        bc.wheel(m, (end * bc.AXLE_X, y, bc.AXLE_Z), broken)
    if st.get("char"):
        m.cols = [char(c) for c in m.cols]
    return m.build()


def main():
    out = bc.arg("out", "tools/dl/p128/ENV/cart_refs")
    if not os.path.isabs(out):
        out = os.path.join(bc.REPO, out)
    only = [s for s in bc.arg("only", "").split(",") if s]
    size = int(bc.arg("size", 1024))
    for letter, st in STATES.items():
        if only and letter not in only:
            continue
        lp.fresh()
        ob = build(st)
        bc.place(ob, float(st["tip"]), float(st["yaw"]))
        bc.render(ob, os.path.join(out, "cart_toppled_%s.png" % letter), 46.0, size, (0.0, 0.0, 1.0))


if __name__ == "__main__":
    main()

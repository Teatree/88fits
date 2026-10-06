"""A pose driver with chosen views shrunk about the figure's middle (pass 54, Solenne's walk): Garry's walk swings both
arms out wide, and with the boots, the sun head's rays and the arms painted over the skeleton, the back and three-quarter
back figures touched the clip's edges, so gen_art's pose cycle threw the clips away ("figure left the frame") or kept one
whose boot the keyer cut off at the bottom. Shrinking the stick figure keeps the painted figure inside the frame; gen_art
scales every clip frame back to the standing height, so the sprite comes out the same size.

    python tools/pose_scale.py tools/dl/drivers/walk_sun_spread tools/dl/drivers/walk_sun_spread85 [scale=0.85] [views=back,bd]

Every keypoint of a view (the body, both hands, the face) moves towards the middle of the whole clip's keypoint box by
`scale`; the frames are then redrawn as pose_driver.draw does.
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_driver  # noqa: E402


def _points(fr):
    """Every [x, y, ...] point list of a frame: the body, the hands, the face."""
    out = [fr.get("body") or []]
    hands = fr.get("hands") or {}
    for side in ("l", "r"):
        if hands.get(side):
            out.append(hands[side])
    if fr.get("face"):
        out.append(fr["face"])
    return out


def scale_driver(src, dst, factor=0.85, views=("back", "bd")):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    for view in views:
        p = os.path.join(dst, view, "poses.json")
        if not os.path.exists(p):
            continue
        d = json.load(open(p, encoding="utf-8"))
        xs, ys = [], []
        for fr in d["frames"]:
            for pts in _points(fr):
                for q in pts:
                    if len(q) < 3 or q[2]:
                        xs.append(q[0])
                        ys.append(q[1])
        cx, cy = (min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5
        for fr in d["frames"]:
            for pts in _points(fr):
                for q in pts:
                    q[0] = round(cx + (q[0] - cx) * factor, 4)
                    q[1] = round(cy + (q[1] - cy) * factor, 4)
        d["scaled"] = {"factor": factor, "about": [round(cx, 4), round(cy, 4)]}
        json.dump(d, open(p, "w", encoding="utf-8"), indent=1)
        print("pose_scale: %s %s x%.2f about (%.3f, %.3f)" % (os.path.basename(dst), view, factor, cx, cy))
    pose_driver.draw(dst)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if "=" not in a]
    kw = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
    if len(args) < 2:
        raise SystemExit(__doc__)
    scale_driver(args[0], args[1], float(kw.get("scale", "0.85")), tuple(v for v in kw.get("views", "back,bd").split(",") if v))

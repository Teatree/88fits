"""A pose driver whose back views keep the hands clear of the body (pass 45, Calavera's back run): Wan Animate paints a
hand wherever the driver's wrist is, and a wrist that swings level with the hips inside the torso's width came out as a
bone-white hand painted on the back of the jacket (pass 44's pose_occlude hid that wrist, and the model painted the hand
anyway from the forearm). Seen from behind, a runner's hands show beside the hips: this copies a driver and, in the back
and three-quarter-back views, pushes any wrist that sits inside the torso's width out past it, moves the elbow half as far
and the hand outline with the wrist, then redraws.

    python tools/pose_spread.py tools/dl/drivers/run tools/dl/drivers/run_spread [spread=0.06]
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_driver  # noqa: E402

# OpenPose body-18: nose, neck, rsho, relb, rwri, lsho, lelb, lwri, rhip, rknee, rank, lhip, lknee, lank, ...
NECK, RSHO, RELB, RWRI, LSHO, LELB, LWRI, RHIP, LHIP = 1, 2, 3, 4, 5, 6, 7, 8, 11


def spread(src, dst, views=("back", "bd"), gap=0.06):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    moved = 0
    for view in views:
        p = os.path.join(dst, view, "poses.json")
        if not os.path.exists(p):
            continue
        meta = json.load(open(p))
        for fr in meta["frames"]:
            row = fr["body"] if isinstance(fr, dict) else fr
            xs = [row[j][0] for j in (RSHO, LSHO, RHIP, LHIP) if row[j][2]]
            if len(xs) < 3:
                continue
            cx = 0.5 * (min(xs) + max(xs))
            half = 0.5 * (max(xs) - min(xs))
            for sho, elb, wri, tag in ((RSHO, RELB, RWRI, "r"), (LSHO, LELB, LWRI, "l")):
                wx, wy, wv = row[wri]
                if not wv:
                    continue
                side = 1.0 if row[sho][0] >= cx else -1.0
                want = cx + side * (half + gap)
                if side * (wx - cx) >= half + gap:
                    continue
                dx = want - wx
                row[wri][0] = round(want, 4)
                if row[elb][2]:
                    row[elb][0] = round(row[elb][0] + 0.5 * dx, 4)
                if isinstance(fr, dict) and fr.get("hands") and fr["hands"].get(tag):
                    fr["hands"][tag] = [[round(u + dx, 4), v] for u, v in fr["hands"][tag]]
                moved += 1
        json.dump(meta, open(p, "w"), indent=1)
    pose_driver.draw(dst)
    meta = json.load(open(os.path.join(dst, "meta.json")))
    meta["spread"] = {"views": list(views), "gap": gap}
    json.dump(meta, open(os.path.join(dst, "meta.json"), "w"), indent=1)
    print("pose_spread: %s -> %s, %d wrists moved" % (src, dst, moved))


if __name__ == "__main__":
    g = 0.06
    for a in sys.argv[3:]:
        if a.startswith("spread="):
            g = float(a.split("=", 1)[1])
    spread(sys.argv[1], sys.argv[2], gap=g)

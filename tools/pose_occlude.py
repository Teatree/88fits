"""A pose driver with the hidden hands hidden (pass 44, Calavera's back run): Wan Animate paints every joint the driver
shows, so a hand that swings in front of the chest in the back view came out painted on the back of the jacket. Seen
from behind, that hand is behind the body: this copies a driver and, in the back and three-quarter-back views, drops
the wrist (and the elbow when it sits inside too) of any arm whose wrist falls inside the torso's box, then redraws.

    python tools/pose_occlude.py tools/dl/drivers/run tools/dl/drivers/run_occ
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_driver  # noqa: E402

# OpenPose body-18: nose, neck, rsho, relb, rwri, lsho, lelb, lwri, rhip, rknee, rank, lhip, lknee, lank, ...
NECK, RSHO, RELB, RWRI, LSHO, LELB, LWRI, RHIP, LHIP = 1, 2, 3, 4, 5, 6, 7, 8, 11


def occlude(src, dst, views=("back", "bd"), margin=0.012):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    hidden = 0
    for view in views:
        p = os.path.join(dst, view, "poses.json")
        if not os.path.exists(p):
            continue
        meta = json.load(open(p))
        for fr in meta["frames"]:
            row = fr["body"] if isinstance(fr, dict) else fr
            xs = [row[j][0] for j in (RSHO, LSHO, RHIP, LHIP) if row[j][2]]
            if len(xs) < 3 or not row[NECK][2]:
                continue
            x0, x1 = min(xs) + margin, max(xs) - margin
            y0 = row[NECK][1]
            y1 = max(row[RHIP][1], row[LHIP][1])
            for wri, elb in ((RWRI, RELB), (LWRI, LELB)):
                wx, wy, wv = row[wri]
                if wv and x0 < wx < x1 and y0 < wy < y1:
                    row[wri][2] = 0
                    hidden += 1
                    ex, ey, ev = row[elb]
                    if ev and x0 < ex < x1 and y0 < ey < y1:
                        row[elb][2] = 0
            # the hand outlines go with the wrist
            if isinstance(fr, dict) and fr.get("hands"):
                for tag, wri in (("r", RWRI), ("l", LWRI)):
                    if not row[wri][2]:
                        fr["hands"][tag] = None
        json.dump(meta, open(p, "w"), indent=1)
    pose_driver.draw(dst)
    meta = json.load(open(os.path.join(dst, "meta.json")))
    meta["occluded"] = list(views)
    json.dump(meta, open(os.path.join(dst, "meta.json"), "w"), indent=1)
    print("pose_occlude: %s -> %s, %d wrists hidden" % (src, dst, hidden))


if __name__ == "__main__":
    occlude(sys.argv[1], sys.argv[2])

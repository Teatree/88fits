"""A pose driver whose back views let the arms hang (pass 131, the poncho skeleton SK-F): a runner's bent arm swings its
hand up in front of the chest, and from behind Wan Animate painted that hand on the back of the poncho, beside the arm
the painting already hangs at the side (two right arms; the left hand through the cloth). pose_occlude's torso box is
the driver's narrow ribcage, far inside a poncho, and pose_spread would leave a raised hand beside the shoulder. This
copies a driver and, in the back and three-quarter-back views, hangs each arm down and a little out from its shoulder
(as the painting holds it) and keeps a small swing from the clip: the side view says how far forward the wrist is; a
forward hand shortens the forearm, a hand swung back pushes it out. The hand outline goes with the wrist, turned to hang with it. Redraws.

    python tools/pose_hang.py tools/dl/drivers/run12 tools/dl/drivers/run12_hang [out=0.03 swing=0.25 views=back,bd arms=rl]

arms=l hangs only the figure's left arm (the Skeleton Knight KN-D: the shield arm folded up in front of the chest for half
the stride, and the shield was left hanging in the air without it); the other arm keeps the clip's swing.
"""
import json
import math
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_driver  # noqa: E402

# OpenPose body-18: nose, neck, rsho, relb, rwri, lsho, lelb, lwri, rhip, ...
NECK, RSHO, RELB, RWRI, LSHO, LELB, LWRI = 1, 2, 3, 4, 5, 6, 7


def _frames(p):
    meta = json.load(open(p))
    return meta, [fr["body"] if isinstance(fr, dict) else fr for fr in meta["frames"]]


def hang(src, dst, views=("back", "bd"), out=0.03, swing=0.25, arms="rl"):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    # how far forward each wrist is, frame by frame, from the side view (it faces screen-right): -1 back .. +1 forward
    fwd = {}
    sp = os.path.join(src, "side", "poses.json")
    if os.path.exists(sp):
        _, rows = _frames(sp)
        for sho, wri in ((RSHO, RWRI), (LSHO, LWRI)):
            raw = [r[wri][0] - r[sho][0] for r in rows]
            mid, amp = 0.5 * (max(raw) + min(raw)), max(1e-6, 0.5 * (max(raw) - min(raw)))
            fwd[wri] = [(v - mid) / amp for v in raw]
    moved = 0
    for view in views:
        p = os.path.join(dst, view, "poses.json")
        if not os.path.exists(p):
            continue
        meta, rows = _frames(p)
        # the arm's true lengths: the longest each bone shows in the cycle (a foreshortened frame is shorter)
        lens = {}
        for sho, elb, wri in ((RSHO, RELB, RWRI), (LSHO, LELB, LWRI)):
            lens[wri] = (max(math.dist(r[sho][:2], r[elb][:2]) for r in rows), max(math.dist(r[elb][:2], r[wri][:2]) for r in rows))
        for i, (fr, row) in enumerate(zip(meta["frames"], rows)):
            for sho, elb, wri, tag in ((RSHO, RELB, RWRI, "r"), (LSHO, LELB, LWRI, "l")):
                if tag not in arms or not (row[sho][2] and row[elb][2] and row[wri][2]):
                    continue
                side = 1.0 if row[sho][0] >= row[NECK][0] else -1.0
                f = fwd.get(wri, [0.0] * len(rows))[min(i, len(fwd.get(wri, [0.0])) - 1)] if fwd else 0.0
                up, fo = lens[wri]
                back = max(0.0, -f)   # swung back: towards the viewer, a little out and whole
                ahead = max(0.0, f)   # swung forward: away from the viewer, the forearm shorter
                ex = row[sho][0] + side * (out + 0.4 * out * back)
                ey = row[sho][1] + up * (0.95 - 0.08 * ahead)
                wx = ex + side * (0.3 * out + swing * out * back)
                wy = ey + fo * (0.95 - swing * ahead)
                dx, dy = wx - row[wri][0], wy - row[wri][1]
                row[elb][0], row[elb][1] = round(ex, 4), round(ey, 4)
                row[wri][0], row[wri][1] = round(wx, 4), round(wy, 4)
                if isinstance(fr, dict) and fr.get("hands") and fr["hands"].get(tag):
                    # the hand hangs too: turned about the wrist until its middle finger points down the forearm
                    hp = fr["hands"][tag]
                    a = math.atan2(wy - ey, wx - ex) - math.atan2(hp[9][1] - hp[0][1], hp[9][0] - hp[0][0])
                    ca, sa = math.cos(a), math.sin(a)
                    fr["hands"][tag] = [[round(wx + (u - hp[0][0]) * ca - (v - hp[0][1]) * sa, 4),
                                         round(wy + (u - hp[0][0]) * sa + (v - hp[0][1]) * ca, 4)] for u, v in hp]
                moved += 1
        json.dump(meta, open(p, "w"), indent=1)
    pose_driver.draw(dst)
    meta = json.load(open(os.path.join(dst, "meta.json")))
    meta["hang"] = {"views": list(views), "out": out, "swing": swing, "arms": arms}
    json.dump(meta, open(os.path.join(dst, "meta.json"), "w"), indent=1)
    print("pose_hang: %s -> %s, %d arms hung" % (src, dst, moved))


if __name__ == "__main__":
    kw = dict(a.split("=", 1) for a in sys.argv[3:])
    hang(sys.argv[1], sys.argv[2], tuple(kw.get("views", "back,bd").split(",")), float(kw.get("out", 0.03)), float(kw.get("swing", 0.25)), kw.get("arms", "rl"))

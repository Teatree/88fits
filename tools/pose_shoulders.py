"""A pose driver with the shoulders pulled level with the neck in chosen views (pass 69, lane ART: Fadeaway's sagging back
run and the side runs' raised shoulder).

Why: OpenPose's neck is the middle of the shoulder line, but pose_driver.py takes the Mixamo Neck bone, which sits above
and in front of the shoulder joints. Seen from the camera 25 degrees above, that puts both shoulders 0.02-0.04 (of the
frame) below the neck in the back views (an inverted V: Wan Animate paints sagging shoulders) and, in the side view, the
near shoulder 0.05 below the neck with the far one at the neck's height, so the model takes the higher point for the
near shoulder and paints it hunched up toward the ear in the frames where the arms pass the body.

Every shoulder's height above or below the neck is multiplied by `level` (0 = exactly level with the neck, 1 = unchanged)
and the arm hanging from it (elbow, wrist, the hand's 21 points) moves up or down with it, so the arms keep their swing.

    python tools/pose_shoulders.py tools/dl/drivers/run_spread tools/dl/drivers/run_spread_lvl [level=0.3] [views=back,bd]
    python tools/pose_shoulders.py tools/dl/drivers/run tools/dl/drivers/run_lvl level=0.3 views=side,fd,front

tuck=<deg> (side view only): the FAR arm's upper arm may point at most that many degrees back from straight down; the
whole far arm turns about its shoulder to get there. In the Running clip's passing frames both elbows are behind the
body at once, and the far elbow, up behind the back at the neck's height, was painted as a lump that read as a raised,
hunched shoulder; tucked, the far arm hangs behind the torso where a profile hides it.
    python tools/pose_shoulders.py tools/dl/drivers/run tools/dl/drivers/run_side views=side level=0.3 tuck=25

keep_tilt=1: the `level` rule moves the shoulders' midpoint and both shoulders move with it by the same amount, so the
near shoulder of a side view stays lower than the far one, as the camera above sees it.
"""
import math
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_driver  # noqa: E402

# OpenPose body-18: nose, neck, rsho, relb, rwri, lsho, lelb, lwri, ...
NECK = 1
ARMS = ((2, 3, 4, "r"), (5, 6, 7, "l"))


def _tuck_far_arm(fr, row, max_deg):
    """In the frames where the NEAR arm has swung back too (its elbow behind its shoulder by more than a quarter of the
    upper arm, fully from 0.45), the far arm's upper arm (the shoulder higher on screen in a right-facing profile) turns
    about its shoulder toward pointing at most max_deg back from straight down; the forearm and the hand keep their
    direction and move with the elbow, so the far hand stays a hand at the hip. The weight ramps, so the arm never jumps
    between frames. Returns True when it moved."""
    far, near = (ARMS[0], ARMS[1]) if row[ARMS[0][0]][1] < row[ARMS[1][0]][1] else (ARMS[1], ARMS[0])
    sho, elb, wri, tag = far
    if not (row[sho][2] and row[elb][2] and row[near[0]][2] and row[near[1]][2]):
        return False
    n_len = math.hypot(row[near[1]][0] - row[near[0]][0], row[near[1]][1] - row[near[0]][1]) or 1.0
    back = -(row[near[1]][0] - row[near[0]][0]) / n_len
    w = min(1.0, max(0.0, (back - 0.25) / 0.2))
    if w <= 0.0:
        return False
    sx, sy = row[sho][0], row[sho][1]
    dx, dy = row[elb][0] - sx, row[elb][1] - sy
    ang = math.atan2(-dx, dy)            # 0 = straight down, > 0 = swung back (screen-left of a right-facing figure)
    lim = math.radians(max_deg)
    if ang <= lim:
        return False
    t = ang - (ang - lim) * w
    r = math.hypot(dx, dy)
    ex, ey = sx - r * math.sin(t), sy + r * math.cos(t)
    mx, my = ex - row[elb][0], ey - row[elb][1]
    row[elb][0], row[elb][1] = round(ex, 4), round(ey, 4)
    row[wri][0], row[wri][1] = round(row[wri][0] + mx, 4), round(row[wri][1] + my, 4)
    if isinstance(fr, dict) and fr.get("hands") and fr["hands"].get(tag):
        fr["hands"][tag] = [[round(u + mx, 4), round(v + my, 4)] if (u is not None and v is not None) else [u, v] for u, v in fr["hands"][tag]]
    return True


def level_shoulders(src, dst, level=0.3, views=("back", "bd"), tuck=None, keep_tilt=False):
    if os.path.abspath(src) == os.path.abspath(dst):
        raise SystemExit("pose_shoulders: write to a new folder")
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    moved, worst, tucked = 0, 0.0, 0
    for view in views:
        p = os.path.join(dst, view, "poses.json")
        if not os.path.exists(p):
            continue
        meta = json.load(open(p))
        for fr in meta["frames"]:
            row = fr["body"] if isinstance(fr, dict) else fr
            if not row[NECK][2]:
                continue
            ny = row[NECK][1]
            mid = 0.5 * (row[ARMS[0][0]][1] + row[ARMS[1][0]][1])
            for sho, elb, wri, tag in ARMS:
                if not row[sho][2]:
                    continue
                # keep_tilt: both shoulders move by the same amount (their midpoint toward the neck), so the side view's
                # near shoulder stays lower than the far one, as the camera above sees it
                dy = (1.0 - level) * (ny - mid) if keep_tilt else (ny + level * (row[sho][1] - ny)) - row[sho][1]
                worst = max(worst, abs(dy))
                for j in (sho, elb, wri):
                    row[j][1] = round(row[j][1] + dy, 4)
                if isinstance(fr, dict) and fr.get("hands") and fr["hands"].get(tag):
                    fr["hands"][tag] = [[u, round(v + dy, 4)] for u, v in fr["hands"][tag]]
                moved += 1
            if tuck is not None and view == "side" and _tuck_far_arm(fr, row, tuck):
                tucked += 1
        json.dump(meta, open(p, "w"), indent=1)
    pose_driver.draw(dst)
    mp = os.path.join(dst, "meta.json")
    meta = json.load(open(mp))
    meta["shoulders"] = {"views": list(views), "level": level, "tuck": tuck, "keep_tilt": keep_tilt, "source": os.path.basename(os.path.normpath(src))}
    json.dump(meta, open(mp, "w"), indent=1)
    print("pose_shoulders: %s -> %s, %d shoulders levelled (largest move %.3f of the frame), far arm tucked in %d side frames"
          % (src, dst, moved, worst, tucked))


if __name__ == "__main__":
    lv, vs, tk, kt = 0.3, ("back", "bd"), None, False
    for a in sys.argv[3:]:
        if a.startswith("level="):
            lv = float(a.split("=", 1)[1])
        elif a.startswith("views="):
            vs = tuple(v for v in a.split("=", 1)[1].split(",") if v)
        elif a.startswith("tuck="):
            tk = float(a.split("=", 1)[1])
        elif a.startswith("keep_tilt="):
            kt = a.split("=", 1)[1] not in ("0", "false", "no", "")
    level_shoulders(sys.argv[1], sys.argv[2], lv, vs, tk, kt)

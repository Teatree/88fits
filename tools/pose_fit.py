"""A pose driver fitted to one painted figure (pass 55, Solenne's walks).

Wan Animate paints the reference still onto the driver's skeleton at the skeleton's size. A Mixamo stride projected at
pose_driver's fill makes a man's body about a third taller than Solenne's painted body (her sun head and its rays take
the height the stride gives a neck and a skull), so her body came out stretched, her hands large, and her head grew in
the front walk and shrank in the back walk, wherever the model settled between the two. Her head is also a flat sun disc
that should face the viewer like a badge, but the driver's face points turned with the stride, so she looked aside.

This copies a driver and, in every view, with one similarity for the whole clip (so the motion is untouched):
  - scales and moves the skeleton so the neck-to-ankle height and the ankle line match the painting
    (`neck_to_ankle`, `ankle_y`, `centre_x`, pixels on the `canvas` the still is placed on);
  - replaces the face with the painting's: the head's middle `head_up` px above the neck point (and `head_dx` px across in
    a view whose head sits ahead of the neck; it bobs with the neck, never tilts or turns), the nose, eyes and ears at the
    template's offsets per view (`faces`; a point left out is hidden);
  - shrinks each hand about its wrist by `hands`;
then redraws the frames as pose_driver.draw does.

    python tools/pose_fit.py tools/dl/drivers/walk_sun_b tools/dl/drivers/walk_sun_fit tools/pose_templates/solenne.json
    python tools/pose_spread.py tools/dl/drivers/walk_sun_fit tools/dl/drivers/walk_sun_fit_spread   # then the back views' wrists
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_driver  # noqa: E402

KP = pose_driver.KP
I = {k: i for i, k in enumerate(KP)}
FACE = ("nose", "reye", "leye", "rear", "lear")


def _clip_frame_box(frames):
    """The clip's mean neck x, mean lowest-ankle v and mean neck-to-lowest-ankle span (normalised units)."""
    nx, gv, span = [], [], []
    for fr in frames:
        b = fr["body"]
        ank = max(b[I["rank"]][1], b[I["lank"]][1])
        nx.append(b[I["neck"]][0])
        gv.append(ank)
        span.append(ank - b[I["neck"]][1])
    n = float(len(frames))
    return sum(nx) / n, sum(gv) / n, sum(span) / n


def fit(src, dst, tpl_path):
    tpl = json.load(open(tpl_path, encoding="utf-8"))
    C = float(tpl.get("canvas", 640))
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    # one scale for every view, from the front view (its neck-to-ankle span is the plain height, as on the painting)
    front = json.load(open(os.path.join(dst, "front", "poses.json"), encoding="utf-8"))
    _, _, span_f = _clip_frame_box(front["frames"][:-1] or front["frames"])
    k = (float(tpl["neck_to_ankle"]) / C) / span_f
    print("pose_fit: neck-to-ankle %.3f -> %.3f, scale x%.3f" % (span_f, tpl["neck_to_ankle"] / C, k))
    for view in pose_driver.VIEWS:
        p = os.path.join(dst, view, "poses.json")
        if not os.path.exists(p):
            continue
        d = json.load(open(p, encoding="utf-8"))
        frames = d["frames"]
        cx, gv, _ = _clip_frame_box(frames[:-1] or frames)
        tx, ty = float(tpl["centre_x"]) / C, float(tpl["ankle_y"]) / C

        def xf(u, v):
            return round(tx + (u - cx) * k, 4), round(ty + (v - gv) * k, 4)

        face = (tpl.get("faces") or {}).get(view, {})
        up = float(tpl.get("head_up", 0)) / C
        hs = float(tpl.get("hands", 1.0))
        for fr in frames:
            b = fr["body"]
            for q in b:
                q[0], q[1] = xf(q[0], q[1])
            hands = fr.get("hands") or {}
            for tag in ("l", "r"):
                hp = hands.get(tag)
                if not hp:
                    continue
                pts = [list(xf(q[0], q[1])) if q is not None else None for q in hp]
                w = pts[0]
                if w is not None and hs != 1.0:
                    pts = [[round(w[0] + (q[0] - w[0]) * hs, 4), round(w[1] + (q[1] - w[1]) * hs, 4)] if q is not None else None for q in pts]
                hands[tag] = pts
            if face:
                hx, hy = b[I["neck"]][0] + float((tpl.get("head_dx") or {}).get(view, 0)) / C, b[I["neck"]][1] - up
                for name in FACE:
                    if name in face:
                        ox, oy = face[name]
                        b[I[name]] = [round(hx + ox / C, 4), round(hy + oy / C, 4), 1]
                    else:
                        b[I[name]][2] = 0
        d["fit"] = {"template": os.path.basename(tpl_path), "scale": round(k, 4), "about": [round(cx, 4), round(gv, 4)], "to": [round(tx, 4), round(ty, 4)]}
        json.dump(d, open(p, "w", encoding="utf-8"), indent=1)
    meta_p = os.path.join(dst, "meta.json")
    meta = json.load(open(meta_p, encoding="utf-8"))
    meta["fit"] = {"template": os.path.basename(tpl_path), "scale": round(k, 4), "from": os.path.basename(os.path.normpath(src))}
    json.dump(meta, open(meta_p, "w", encoding="utf-8"), indent=1)
    pose_driver.draw(dst)
    print("pose_fit: %s -> %s" % (src, dst))


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    fit(sys.argv[1], sys.argv[2], sys.argv[3])

"""Check a made walk's legs (pass 93): where every foot goes in each view, and whether it steps the right way.

    python tools/gait_check.py <driver_dir> [--out <png>] [--frames 12] [--strict]

Reads <driver_dir>/tips.json (blender_depth_drivers.py ... tips=1) and draws each leg's foot path over one stride on the
view's clay picture (a dot per frame, the big dot is frame 0; L1 red .. L4 green on the left, R1 cyan .. R4 pink on the
right), and prints a verdict per leg:
  side view (the creature faces screen-right): a foot on the ground must slide LEFT, back under the body, and come back
    RIGHT through the air ("ok"); the other way round is "BACKWARDS"; a foot whose fore-aft travel is under a quarter of
    the best leg's is "barely steps".
  front and back views: a foot should rise and fall (and shift up and down a little with its fore-aft step), not sweep
    across the body: "SIDEWAYS" when its left-right travel is bigger than its up-down travel.
Writes <out> (default <driver_dir>/gait_check.png) and <driver_dir>/gait_check.json. With --strict the exit code is 1
when a leg is BACKWARDS or SIDEWAYS (the Level Editor's driver_depth job runs it without, so a check never fails a job).
"""
import argparse
import json
import math
import os
import sys

COL = {"L1": (255, 60, 60), "L2": (255, 160, 0), "L3": (255, 255, 0), "L4": (120, 255, 60),
       "R1": (0, 220, 255), "R2": (80, 120, 255), "R3": (200, 90, 255), "R4": (255, 100, 220)}
VIEWS = ("front", "fd", "side", "bd", "back")


def side_verdicts(rows, tags):
    """{tag: {stance_dx, swing_dx, lift_px, verdict}} for the side view (screen y grows downwards: the lower half of a
    foot's path is the ground)."""
    out = {}
    n = len(rows)
    for li, tag in enumerate(tags):
        xs = [r[li][0] for r in rows]
        ys = [r[li][1] for r in rows]
        mid = (min(ys) + max(ys)) / 2.0
        stance = swing = 0.0
        for k in range(n):
            k2 = (k + 1) % n
            dx = xs[k2] - xs[k]
            if ys[k] >= mid and ys[k2] >= mid:
                stance += dx
            else:
                swing += dx
        out[tag] = {"stance_dx": round(stance, 1), "swing_dx": round(swing, 1), "lift_px": round(max(ys) - min(ys), 1),
                    "fore_aft_px": round(max(xs) - min(xs), 1)}
    best = max((v["fore_aft_px"] for v in out.values()), default=0.0)
    for v in out.values():
        if v["stance_dx"] > 0 and v["swing_dx"] < 0:
            v["verdict"] = "BACKWARDS"
        elif v["fore_aft_px"] < 0.25 * best:
            v["verdict"] = "barely steps"
        elif v["stance_dx"] < 0 and v["swing_dx"] > 0:
            v["verdict"] = "ok"
        else:
            v["verdict"] = "unclear"
    return out


def front_verdicts(rows, tags):
    out = {}
    for li, tag in enumerate(tags):
        xs = [r[li][0] for r in rows]
        ys = [r[li][1] for r in rows]
        dx, dy = max(xs) - min(xs), max(ys) - min(ys)
        out[tag] = {"across_px": round(dx, 1), "up_down_px": round(dy, 1), "verdict": "SIDEWAYS" if dx > dy else "ok"}
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("driver")
    ap.add_argument("--out", default=None)
    ap.add_argument("--frames", type=int, default=12)
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args(argv)
    from PIL import Image, ImageDraw
    T = json.load(open(os.path.join(a.driver, "tips.json"), encoding="utf-8"))
    tags = [s.split()[0] for s in T["legs"]]
    views = [v for v in VIEWS if v in T["views"]]
    cells, report, bad = [], {}, False
    for v in views:
        rows = T["views"][v][:a.frames]
        p = os.path.join(a.driver, v, "clay.png")
        im = Image.open(p).convert("RGB") if os.path.exists(p) else Image.new("RGB", (T["size"], T["size"]), (0, 0, 0))
        dr = ImageDraw.Draw(im)
        for li, tag in enumerate(tags):
            pts = [(r[li][0], r[li][1]) for r in rows]
            c = COL.get(tag, (255, 255, 255))
            dr.line(pts + [pts[0]], fill=c, width=3)
            for k, (x, y) in enumerate(pts):
                rr = 7 if k == 0 else 3
                dr.ellipse((x - rr, y - rr, x + rr, y + rr), fill=c)
            dr.text((pts[0][0] + 8, pts[0][1] - 6), tag, fill=c)
        dr.text((8, 8), v, fill=(255, 255, 255))
        cells.append(im.resize((im.width // 2, im.height // 2)))
        if v == "side":
            report[v] = side_verdicts(rows, tags)
        elif v in ("front", "back"):
            report[v] = front_verdicts(rows, tags)
        else:
            continue
        for tag, r in report[v].items():
            bad = bad or r["verdict"] in ("BACKWARDS", "SIDEWAYS")
        print("%-5s %s" % (v, "  ".join("%s %s" % (t, r["verdict"]) for t, r in report[v].items())))
    S = Image.new("RGB", (sum(c.width for c in cells), max(c.height for c in cells)), (0, 0, 0))
    x = 0
    for c in cells:
        S.paste(c, (x, 0))
        x += c.width
    out = a.out or os.path.join(a.driver, "gait_check.png")
    S.save(out)
    json.dump(report, open(os.path.join(a.driver, "gait_check.json"), "w", encoding="utf-8", newline="\n"), indent=1)
    print("gait_check: %s (%s)" % (out, "a leg steps the wrong way" if bad else "every foot steps the right way"))
    return 1 if (bad and a.strict) else 0


if __name__ == "__main__":
    sys.exit(main())

"""Rig an unrigged many-legged creature mesh (pass 106, lane ANT) so blender_depth_drivers.py mode=gait / flip_curl can walk
it and kill it: Garry's armored beetle (tools/dl/uploads/3d/a-heavily-armored-beetle-3d-model-free) is one textured mesh
with no armature and no clip, and every made motion needs leg bones.

    "$BLENDER" -b --python tools/blender_autorig_legs.py -- src=<glb|fbx|obj|zip> out=<dir>/<name>.blend
        [legs=6] [forward=-Y] [thin=0.075] [foot=0.05] [weld=0.00001] [drop_small=40] [head_cut=auto|<share>]
        [grow=2.0] [ankle=0.8] [feet_z=0.25] [sep=0.15] [hip=0.12] [hip_x=0.6] [drop_antenna=1]
        [antennae=elbowed antenna_len=0.3 antenna_radius=0.012] [debug=<npz>]

How the legs are found (no names to go by):
  1. the meshes are joined and welded (a Sketchfab/AI GLB is split at every UV seam: 4,366 pieces became 112) and loose
     parts under `drop_small` vertices dropped (the beetle's floating spines);
  2. every vertex's local thickness is measured by a ray cast inward along its normal (a shape-diameter test, smoothed
     over its neighbours); vertices thinner than `thin` x the creature's height are "thin": legs, spikes, antennae;
  3. the thin parts that reach the ground (a vertex within `foot` x height of the lowest point) are the legs; the
     `legs` biggest such parts are kept. A spike or an antenna never touches the ground;
  4. each leg's path is the shortest walk along the mesh from its foot (the lowest vertex) to the far end of its thin
     part (the hip); the knee is the path point farthest above the hip-to-foot line, the ankle `ankle` of the way from
     the knee to the foot; vertices that are not thin but lie within `grow` x the leg's thickness of its bones, beyond
     its hip, join the leg (a thick knee or claw);
  5. bones: root, body (the legs' common parent, so the gait's sway and the death's roll find it), head (the share of the
     body length from the front given by `head_cut`; auto = where the top of the body drops into the neck), and one chain
     per leg leg_<L|R><n>_1/_2/_3 (hip-knee, knee-ankle, ankle-foot) named to match blender_gait's LEG_WORDS;
  6. weights: a leg vertex to its nearest segment of its chain, the head and the body by the head cut (blended over a
     short band), every other vertex the body; an Armature modifier; saved as a .blend (and <out>.json: the legs found,
     the cut, the thickness numbers; <out>.npz: positions, labels and joints for a check plot).

blender_depth_drivers.py reads the .blend as `src=` (blender_ref.import_model opens .blend files); pass `albedo=` the
model's colour map, since it is not beside the .blend.
"""
import heapq
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_ref as R  # noqa: E402

try:
    import bpy
    import bmesh
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
except ImportError:
    bpy = None


def comps(n, adj, mask):
    """Connected parts of the vertices where mask is True, along the mesh's edges."""
    lab = [-1] * n
    out = []
    for s in range(n):
        if not mask[s] or lab[s] >= 0:
            continue
        k = len(out)
        stack, part = [s], []
        lab[s] = k
        while stack:
            x = stack.pop()
            part.append(x)
            for y in adj[x]:
                if mask[y] and lab[y] < 0:
                    lab[y] = k
                    stack.append(y)
        out.append(part)
    return out, lab


def dijkstra(src, allowed, adj, co):
    dist = {src: 0.0}
    prev = {}
    h = [(0.0, src)]
    while h:
        d, x = heapq.heappop(h)
        if d > dist.get(x, 1e18):
            continue
        for y in adj[x]:
            if allowed is not None and y not in allowed:
                continue
            nd = d + (co[x] - co[y]).length
            if nd < dist.get(y, 1e18):
                dist[y] = nd
                prev[y] = x
                heapq.heappush(h, (nd, y))
    return dist, prev


def seg_dist(p, a, b):
    ab = b - a
    L2 = ab.length_squared
    t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / L2))
    return (p - (a + ab * t)).length, t


def main():
    A = R.args()
    if "src" not in A or "out" not in A:
        raise SystemExit(__doc__)
    src = R.import_model(A["src"])
    out = os.path.abspath(A["out"])
    n_legs = int(A.get("legs", 6))
    fwd = R.forward_vector(A.get("forward", "-Y"))
    fwd = Vector((fwd.x, fwd.y, 0.0)).normalized()
    up = Vector((0, 0, 1))
    right = fwd.cross(up)
    thin_k = float(A.get("thin", 0.075))
    foot_k = float(A.get("foot", 0.05))
    grow_k = float(A.get("grow", 2.0))
    ankle_k = float(A.get("ankle", 0.8))

    # 1. one welded mesh
    ms = R.meshes()
    for o in bpy.data.objects:
        o.select_set(o in ms)
    bpy.context.view_layer.objects.active = ms[0]
    if len(ms) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.data.objects):
        if o is not ob and o.type != "MESH" and o.parent is None and not o.children:
            pass
    ob.parent = None
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=float(A.get("weld", 1e-5)))
    bm.verts.ensure_lookup_table()
    # loose parts under drop_small vertices
    drop_small = int(A.get("drop_small", 40))
    seen = set()
    kill = []
    for v in bm.verts:
        if v.index in seen:
            continue
        part, stack = [], [v]
        seen.add(v.index)
        while stack:
            x = stack.pop()
            part.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        if len(part) < drop_small:
            kill += part
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    me = ob.data
    me.update()
    n = len(me.vertices)
    co = [v.co.copy() for v in me.vertices]
    nor = [v.normal.copy() for v in me.vertices]
    adj = [[] for _ in range(n)]
    for e in me.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    zs = [c.z for c in co]
    ground, top = min(zs), max(zs)
    H = top - ground
    print("autorig: %d vertices after the weld (%d loose dropped), height %.3f" % (n, len(kill), H))

    # 2. thickness by an inward ray
    bm = bmesh.new()
    bm.from_mesh(me)
    bvh = BVHTree.FromBMesh(bm)
    bm.free()
    thick = [H] * n
    for i in range(n):
        nn = nor[i]
        if nn.length < 1e-9:
            continue
        hit = bvh.ray_cast(co[i] - nn * 1e-5, -nn, H)
        if hit[0] is not None:
            thick[i] = (hit[0] - co[i]).length
    # a median over each vertex's ring, three times: a ray that slips out through a crack reads the whole height, and a
    # mean let one such miss make a leg tip read as thick as the body
    for _ in range(3):
        nxt = []
        for i in range(n):
            ring = sorted([thick[i]] + [thick[j] for j in adj[i]])
            nxt.append(ring[len(ring) // 2])
        thick = nxt
    thin_t = thin_k * H
    thin = [t < thin_t for t in thick]
    print("autorig: thin = thickness < %.4f (%d of %d vertices)" % (thin_t, sum(thin), n))

    # 3. the feet: the leg ends, the low vertices farthest out from the body's middle (a raised back leg's foot need not
    # touch the ground: the beetle's hind legs end 0.14 up), one per `sep` of the creature's length, the farthest first
    centre = sum(co, Vector()) / n
    along0 = [(c - centre).dot(fwd) for c in co]
    length = max(along0) - min(along0)
    feet_z = ground + float(A.get("feet_z", 0.25)) * H
    sep = float(A.get("sep", 0.15)) * length

    def flat(c):
        d = c - centre
        return Vector((d.x, d.y, 0.0))
    low = sorted([i for i in range(n) if co[i].z <= feet_z and thin[i]], key=lambda i: -flat(co[i]).length)
    feet = []
    for i in low:
        if all((flat(co[i]) - flat(co[j])).length > sep for j in feet):
            feet.append(i)
        if len(feet) == n_legs:
            break
    if len(feet) < n_legs:
        raise SystemExit("autorig: only %d feet found for legs=%d: raise feet_z= or lower sep=" % (len(feet), n_legs))
    print("autorig: feet at %s" % ", ".join("(%.2f %.2f %.2f)" % tuple(co[i]) for i in feet))
    # 4. each leg: the shortest walk along the mesh from its foot to the belly; the hip where the walk's thickness passes
    # hip x height (held for a few vertices); the knee the path point farthest above the hip-to-foot line
    belly = min(range(n), key=lambda i: (co[i] - Vector((centre.x, centre.y, ground + 0.3 * H))).length + (0 if not thin[i] else 1))
    gdist, gprev = dijkstra(belly, None, adj, co)
    hip_t = float(A.get("hip", 0.12)) * H
    # the body's half-width from its upper half (the legs stay below it): a hip is never nearer the middle line than
    # hip_x of it (the belly is a thin shell too, and the middle legs' walks ran on under it to the middle)
    lat_up = sorted(abs((co[i] - centre).dot(right)) for i in range(n) if co[i].z > ground + 0.45 * H)
    half_w = lat_up[int(0.95 * (len(lat_up) - 1))] if lat_up else 0.25 * length
    hip_lat = float(A.get("hip_x", 0.6)) * half_w
    legs = []
    for foot in feet:
        path = [foot]
        while path[-1] != belly and path[-1] in gprev:
            path.append(gprev[path[-1]])
        # foot -> belly; the hip: the first point where the thickness stays above hip_t for 4 path points
        hk = len(path) - 1
        for j in range(len(path) - 4):
            if all(thick[path[j + q]] > hip_t for q in range(4)) or abs((co[path[j]] - centre).dot(right)) < hip_lat:
                hk = j
                break
        leg_path = list(reversed(path[:hk + 1]))     # hip -> foot
        pts = [co[i] for i in leg_path]
        if len(pts) < 4:
            raise SystemExit("autorig: the leg at (%.2f %.2f %.2f) is %d path points long: lower hip=" % (tuple(co[foot]) + (len(pts),)))
        a, b = pts[0], pts[-1]
        ab = b - a
        best, kn = -1.0, len(pts) // 3
        for j, p in enumerate(pts[1:-1], 1):
            d, t = seg_dist(p, a, b)
            lift = (p - (a + ab * t)).z
            if lift > 0 and d > best:
                best, kn = d, j
        cum = [0.0]
        for j in range(1, len(pts)):
            cum.append(cum[-1] + (pts[j] - pts[j - 1]).length)
        kn = min(max(kn, 1), len(pts) - 3)
        target = cum[kn] + ankle_k * (cum[-1] - cum[kn])
        an = next((j for j in range(kn + 1, len(pts)) if cum[j] >= target), len(pts) - 2)
        an = min(max(an, kn + 1), len(pts) - 2)
        joints = [pts[0], pts[kn], pts[an], pts[-1]]
        side = 1 if (b - centre).dot(right) > 0 else -1
        tk = sorted(thick[i] for i in leg_path)
        legs.append({"hip": leg_path[0], "foot": foot, "joints": joints, "side": side, "path": leg_path,
                     "ahead": (b - centre).dot(fwd), "thick": tk[len(tk) // 2], "size": len(leg_path)})
    for s in (1, -1):
        mine = sorted([L for L in legs if L["side"] == s], key=lambda L: -L["ahead"])
        for o, L in enumerate(mine):
            L["name"] = "leg_%s%d" % ("R" if s > 0 else "L", o + 1)
    # leg membership: within `grow` x the leg's thickness of its bones, beyond its hip (or on its path), the nearest leg
    owner = {}
    byname = {L["name"]: L for L in legs}
    for L in legs:
        for i in L["path"]:
            owner[i] = L["name"]
    grown = 0
    for i in range(n):
        if i in owner:
            continue
        best = None
        for L in legs:
            J = L["joints"]
            r = grow_k * max(L["thick"], 1e-4)
            d0, t0 = seg_dist(co[i], J[0], J[1])
            d = min(seg_dist(co[i], J[1], J[2])[0], seg_dist(co[i], J[2], J[3])[0])
            if t0 > 0.05:
                d = min(d, d0)
            if d < r and (best is None or d < best[0]):
                best = (d, L["name"])
        if best is not None:
            owner[i] = best[1]
            grown += 1
    # what is left of a leg (a claw, a spine on a shin) is cut off from the body by the leg's own vertices: every part of
    # the not-leg vertices but the biggest (the body) goes to the leg nearest its middle, else it floats in the walk
    rest, _rl = comps(n, adj, [i not in owner for i in range(n)])
    rest.sort(key=len, reverse=True)
    stray = 0
    for part in rest[1:]:
        mid = sum((co[i] for i in part), Vector()) / len(part)
        bestL = min(legs, key=lambda L: min(seg_dist(mid, L["joints"][s], L["joints"][s + 1])[0] for s in range(3)))
        dmin = min(seg_dist(mid, bestL["joints"][s], bestL["joints"][s + 1])[0] for s in range(3))
        if dmin < 0.15 * length:
            for i in part:
                owner[i] = bestL["name"]
            stray += len(part)
    print("autorig: %d stray vertices in %d cut-off bits joined their leg" % (stray, max(0, len(rest) - 1)))
    for L in legs:
        L["size"] = sum(1 for i in owner if owner[i] == L["name"])
    print("autorig: legs %s; %d vertices grown onto them" % (", ".join("%s %d v (thick %.3f)" % (L["name"], L["size"], L["thick"]) for L in sorted(legs, key=lambda L: L["name"])), grown))
    if A.get("debug"):
        import numpy as np
        np.savez(A["debug"], co=np.array([tuple(c) for c in co]), thick=np.array(thick),
                 lab=np.array([1 + sorted(byname).index(owner[i]) if i in owner else 0 for i in range(n)]),
                 thin=np.array([i in owner for i in range(n)]),
                 joints=np.array([[tuple(j) for j in byname[k]["joints"]] for k in sorted(byname)]))

    # 5. the head cut
    along = [(c - centre).dot(fwd) for c in co]
    body_idx = [i for i in range(n) if i not in owner]
    # the body's front and back from its thick vertices (an antenna or a spike sticking out is no part of the length)
    thick_al = sorted(along[i] for i in body_idx if thick[i] > thin_t)
    fr = thick_al[int(0.995 * (len(thick_al) - 1))]
    bk = thick_al[int(0.005 * (len(thick_al) - 1))]
    hc = A.get("head_cut", "auto")
    if hc == "auto":
        # the top of the body (the highest non-thin vertex) slice by slice from the front: the neck is where the top
        # jumps up behind the head (the pronotum rising)
        nb = 40
        tops = []
        for s in range(nb):
            lo = fr - (fr - bk) * (s + 1) / nb
            hi = fr - (fr - bk) * s / nb
            zz = [co[i].z for i in body_idx if lo <= along[i] < hi and thick[i] > thin_t]
            tops.append(max(zz) if zz else ground)
        jump = max(range(1, nb // 2), key=lambda s: tops[s] - tops[s - 1])
        cut_share = jump / float(nb)
    else:
        cut_share = float(hc)
    cut = fr - (fr - bk) * cut_share
    band = 0.03 * (fr - bk)
    print("autorig: body from %.3f (front) to %.3f along forward; head cut at %.2f of it (%.3f)" % (fr, bk, cut_share, cut))

    # 6. the armature
    arm_data = bpy.data.armatures.new("rig")
    arm = bpy.data.objects.new("rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    for o in bpy.data.objects:
        o.select_set(o is arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    root = eb.new("root")
    gc = Vector((centre.x, centre.y, ground))
    root.head, root.tail = gc, gc + Vector((0, 0, 0.1 * H))
    body = eb.new("body")
    body_c = Vector((centre.x, centre.y, ground + 0.45 * H))
    body.head = body_c - fwd * 0.2 * (fr - bk)
    body.tail = body_c + fwd * 0.2 * (fr - bk)
    body.parent = root
    head = eb.new("head")
    hpt = centre + fwd * (cut - (centre - centre).dot(fwd))
    hz = sum(co[i].z for i in body_idx if along[i] > cut) / max(1, sum(1 for i in body_idx if along[i] > cut))
    head.head = Vector((centre.x, centre.y, hz)) + fwd * cut
    head.tail = Vector((centre.x, centre.y, hz)) + fwd * fr
    head.parent = body
    for L in legs:
        J = L["joints"]
        prev = body
        for s in range(3):
            b = eb.new("%s_%d" % (L["name"], s + 1))
            b.head, b.tail = J[s], J[s + 1]
            b.parent = prev
            b.use_connect = s > 0
            prev = b
    bpy.ops.object.mode_set(mode="OBJECT")

    # 7. weights
    groups = {}

    def vg(name):
        if name not in groups:
            groups[name] = ob.vertex_groups.new(name=name)
        return groups[name]
    labels = []
    for i in range(n):
        if i in owner:
            L = byname[owner[i]]
            J = L["joints"]
            ds = [seg_dist(co[i], J[s], J[s + 1])[0] for s in range(3)]
            s = min(range(3), key=lambda s: ds[s])
            vg("%s_%d" % (L["name"], s + 1)).add([i], 1.0, "REPLACE")
            labels.append(1 + legs.index(L))
            continue
        w = max(0.0, min(1.0, (along[i] - (cut - band)) / (2 * band)))
        if w > 0:
            vg("head").add([i], w, "REPLACE")
        if w < 1:
            vg("body").add([i], 1.0 - w, "REPLACE")
        labels.append(-1 if w >= 0.5 else 0)
    mod = ob.modifiers.new("arm", "ARMATURE")
    mod.object = arm
    ob.parent = arm
    # 8. antennae (pass 106: the beetle has one straight antenna, an ant two elbowed ones). drop_antenna=1 deletes every
    # hair-thin part (thinner than 0.02 x height) that reaches past the head's front by 8% of the length;
    # antennae=elbowed adds two elbowed tapered antennae on the head (a scape up and out, then the funiculus forward and
    # down), weighted to the head bone, `antenna_len` x the body length each
    dropped_ant = 0
    if str(A.get("drop_antenna", "0")) not in ("0", "", "no", "false"):
        hair = [t < 0.02 * H for t in thick]
        hp, _hl = comps(n, adj, hair)
        kill_i = set()
        for part in hp:
            if max(along[i] for i in part) > fr + 0.08 * (fr - bk):
                kill_i.update(part)
        if kill_i:
            bm = bmesh.new()
            bm.from_mesh(me)
            bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(kill_i)], context="VERTS")
            bm.to_mesh(me)
            bm.free()
            me.update()
            dropped_ant = len(kill_i)
        print("autorig: drop_antenna: %d vertices" % dropped_ant)
    ant_mode = str(A.get("antennae", "") or "")
    if ant_mode == "elbowed":
        Lb = fr - bk
        alen = float(A.get("antenna_len", 0.3)) * Lb
        rad = float(A.get("antenna_radius", 0.012)) * Lb
        head_vs = [i for i in range(n) if i not in owner and along[i] > cut]
        htop = max(co[i].z for i in head_vs)
        hfront_z = sorted(co[i].z for i in head_vs if along[i] > fr - 0.05 * Lb) or [htop]
        base_z = hfront_z[int(0.8 * (len(hfront_z) - 1))]
        for sgn in (1, -1):
            p0 = Vector((centre.x, centre.y, 0)) + fwd * (fr - 0.04 * Lb) + right * (sgn * 0.04 * Lb)
            p0.z = base_z
            p1 = p0 + (fwd * 0.25 + right * (sgn * 0.55) + up * 0.8).normalized() * (0.42 * alen)
            p2 = p1 + (fwd * 0.85 + right * (sgn * 0.25) - up * 0.45).normalized() * (0.58 * alen)
            for (h, t, r0, r1) in ((p0, p1, rad, rad * 0.8), (p1, p2, rad * 0.8, rad * 1.1)):
                L = (t - h).length
                bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=r0, radius2=r1, depth=L, location=(h + t) / 2.0)
                a = bpy.context.active_object
                a.rotation_mode = "QUATERNION"
                a.rotation_quaternion = (t - h).to_track_quat("Z", "Y")
                bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
                bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=r1 * 1.15, location=t)
                bpy.context.active_object.select_set(True)
                a.select_set(True)
                bpy.context.view_layer.objects.active = a
                bpy.ops.object.join()
                a.name = "antenna_%s" % ("R" if sgn > 0 else "L")
                for poly in a.data.polygons:
                    poly.use_smooth = True
                g = a.vertex_groups.new(name="head")
                g.add(list(range(len(a.data.vertices))), 1.0, "REPLACE")
                m2 = a.modifiers.new("arm", "ARMATURE")
                m2.object = arm
                a.parent = arm
                if ob.data.materials:
                    a.data.materials.append(ob.data.materials[0])
        print("autorig: antennae=elbowed, %.3f long, radius %.4f" % (alen, rad))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out)
    rep = {"src": os.path.relpath(src, R.REPO).replace("\\", "/"), "vertices": n, "dropped_loose": len(kill), "height": H,
           "thin_threshold": thin_t, "thin_vertices": sum(thin), "feet": len(feet), "grown": grown,
           "head_cut_share": cut_share, "legs": [{"name": L["name"], "vertices": L["size"], "thick": round(L["thick"], 4),
                                                   "joints": [[round(x, 4) for x in j] for j in L["joints"]]}
                                                  for L in sorted(legs, key=lambda L: L["name"])],
           "args": {k: v for k, v in A.items()}}
    with open(os.path.splitext(out)[0] + ".json", "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=1)
    try:
        import numpy as np
        np.savez(os.path.splitext(out)[0] + ".npz", co=np.array([tuple(c) for c in co]), lab=np.array(labels),
                 joints=np.array([[tuple(j) for j in L["joints"]] for L in legs]), thick=np.array(thick))
    except Exception as e:  # noqa: BLE001
        print("autorig: no npz (%s)" % e)
    print("autorig: wrote %s" % out)


if __name__ == "__main__" and bpy is not None:
    main()

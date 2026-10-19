"""A limb chain copied or turned on a rigged model (pass 92, lane SPIDER): the fix for a model that has the wrong number of
legs (Garry's spider._low_poly.glb has six, three a side; a spider has eight).

    "$BLENDER" -b --python tools/blender_limb_clone.py -- src=<fbx|glb|blend> out=<file.glb|file.blend>
        [clone=<chain>:<new>:<yaw>[:<shift>];...] [turn=<chain>:<yaw>[:<shift>];...] [forward=-Y|+Y|-X|+X] [shot=<png>]

A chain is every bone whose name starts with <chain> (left_leg_center_ takes left_leg_center_1_011 .. _4_014), with the
mesh islands those bones carry (an island goes with the chain when its heaviest weight is one of the chain's bones; a
leg welded to the body is not a separate island and cannot be copied this way: the script says so and stops).
  clone=  copies the bones (named <new> + the rest of each old name: left_leg_center_1_011 -> left_leg_mid_1_011) and the
          mesh islands with their weights moved to the new bones, then turns the copy `yaw` degrees round the vertical
          axis through the chain's first joint (positive = counter-clockwise seen from above) and slides it `shift`
          along the model's forward (negative = back towards the tail).
  turn=   turns (and slides) an existing chain the same way, bones and mesh together.
Rest bones and their vertices move together, so the skin stays bound; the model's own clips still play (a new chain has
no keys and holds its rest pose in them). out= .glb exports the model with its skin and clips (what the Level Editor
previews), .blend saves the scene. shot= renders a clay view from above to check the result (head up the picture).
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_ref as R  # noqa: E402
try:
    import bpy
    import bmesh
    from mathutils import Matrix, Vector
except ImportError:
    bpy = None


def parse_ops(spec, n_min, n_max):
    """'a:b:20;c:d:-20:0.1' -> [[a, b, 20.0], [c, d, -20.0, 0.1]] (numbers from the third field on)."""
    out = []
    for part in [p for p in re.split(r"[;,]", spec or "") if p.strip()]:
        f = [x.strip() for x in part.split(":")]
        if not (n_min <= len(f) <= n_max):
            raise SystemExit("blender_limb_clone: %r is not %d to %d fields separated by ':'" % (part, n_min, n_max))
        out.append(f)
    return out


def chain_bones(arm, prefix):
    names = [b.name for b in arm.data.bones if b.name.startswith(prefix)]
    if not names:
        raise SystemExit("blender_limb_clone: no bone starts with %r (the bones: %s)" % (prefix, ", ".join(b.name for b in arm.data.bones)))
    return names


def chain_root(arm, names):
    s = set(names)
    roots = [n for n in names if arm.data.bones[n].parent is None or arm.data.bones[n].parent.name not in s]
    if len(roots) != 1:
        raise SystemExit("blender_limb_clone: the chain %s has %d roots, not one" % (names, len(roots)))
    return roots[0]


def islands(bm, dl, group_ids):
    """The mesh islands whose heaviest weight is one of `group_ids`: lists of BMVerts."""
    seen = set()
    out = []
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        heavy = {}
        for x in comp:
            w = x[dl]
            if w:
                gi = max(w.keys(), key=lambda k: w[k])
                heavy[gi] = heavy.get(gi, 0) + 1
        if heavy and max(heavy, key=heavy.get) in group_ids:
            mixed = [g for g in heavy if g not in group_ids]
            if mixed and sum(heavy[g] for g in mixed) > 0.3 * len(comp):
                raise SystemExit("blender_limb_clone: a mesh island of the chain is welded to other bones' geometry; "
                                 "this tool copies separate limb islands only")
            out.append(comp)
    return out


def turn_matrix(pivot_world, yaw_deg, shift_vec):
    """World matrix: a turn round the vertical axis through `pivot_world`, then a slide."""
    return (Matrix.Translation(shift_vec) @ Matrix.Translation(pivot_world) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
            @ Matrix.Translation(-pivot_world))


def rest_check(arm, body):
    """A Sketchfab GLB's rest pose is often not its stance (spider._low_poly.glb rests far off to one side and only its
    clip's first frame puts the legs where the mesh shows them): say so, since the pivots are read at rest."""
    if not (arm.animation_data and arm.animation_data.action):
        return
    R.set_frame(arm.animation_data.action.frame_range[0])
    a = R.bbox(body)
    act = arm.animation_data.action
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
    R.update()
    b = R.bbox(body)
    arm.animation_data.action = act
    R.update()
    if a and b:
        size = max((a[1] - a[0]).length, 1e-9)
        off = ((a[0] + a[1]) * 0.5 - (b[0] + b[1]) * 0.5).length
        if off > 0.25 * size or abs((b[1] - b[0]).length - size) > 0.25 * size:
            print("blender_limb_clone: WARNING: the rest pose is not the clip's first pose (the mesh moves %.0f%% of its size "
                  "between them): run with rest=frame:0 so the stance becomes the rest pose" % (100.0 * off / size))


def rest_from_pose(arm, body, spec, action=None):
    """rest=frame:<n>: the clip's pose at frame n becomes the rest pose (the mesh baked in that pose, Apply Pose as Rest
    Pose on the armature) and the clips are removed: their keys were made against the old rest and would now throw the
    limbs about. A walk is then made by blender_depth_drivers.py mode=gait, which needs no clip."""
    m = re.match(r"frame:(-?[\d.]+)$", spec.strip())
    if not m:
        raise SystemExit("blender_limb_clone: rest=%r is not frame:<n>" % spec)
    if arm.animation_data is None or arm.animation_data.action is None:
        act = R.find_action(action, arm) if R.all_actions() else None
        if act is None:
            raise SystemExit("blender_limb_clone: rest=frame:<n> needs a clip to pose from")
        R.use_action(arm, act)
    elif action:
        R.use_action(arm, R.find_action(action, arm))
    R.set_frame(float(m.group(1)))
    dg = bpy.context.evaluated_depsgraph_get()
    baked = {}
    for ob in body:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        baked[ob.name] = [v.co.copy() for v in me.vertices]
        ev.to_mesh_clear()
    for ob in body:
        cos = baked[ob.name]
        if len(cos) != len(ob.data.vertices):
            raise SystemExit("blender_limb_clone: %s changes its vertex count under its modifiers; cannot bake its pose" % ob.name)
        for v, c in zip(ob.data.vertices, cos):
            v.co = c
        ob.data.update()
    bpy.context.view_layer.objects.active = arm
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.animation_data.action = None
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
    R.update()
    print("blender_limb_clone: frame %s is the rest pose now; the clips are removed" % m.group(1))


def main():
    A = R.args()
    if "src" not in A or "out" not in A:
        raise SystemExit(__doc__)
    src = R.import_model(A["src"])
    arm = R.main_armature()
    if arm is None:
        raise SystemExit("blender_limb_clone: no armature in %s" % src)
    body = R.meshes()
    clones = parse_ops(A.get("clone"), 3, 4)
    turns = parse_ops(A.get("turn"), 2, 3)
    fwd = R.forward_vector(A.get("forward", "-Y"))
    for pb in arm.pose.bones:
        if pb.constraints:
            print("blender_limb_clone: note: %s has %d constraint(s)" % (pb.name, len(pb.constraints)))
    if A.get("rest"):
        rest_from_pose(arm, body, A["rest"], A.get("action"))
    else:
        rest_check(arm, body)
    # every bone at rest while we work (the clip's pose would confuse the pivots)
    saved_action = arm.animation_data.action if arm.animation_data else None
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
    R.update()
    M_arm = arm.matrix_world.copy()
    # forward= is the way the model faces in the scene as imported (what the probe's forward guess and every render use)
    fwd_world = Vector(fwd)
    fwd_world.z = 0.0
    fwd_world = fwd_world.normalized() if fwd_world.length > 1e-9 else Vector((0, -1, 0))
    ops = [("clone", f) for f in clones] + [("turn", f) for f in turns]
    for kind, f in ops:
        prefix = f[0]
        names = chain_bones(arm, prefix)
        root = chain_root(arm, names)
        pivot = M_arm @ arm.data.bones[root].head_local
        yaw = float(f[2] if kind == "clone" else f[1])
        sh = f[3] if kind == "clone" and len(f) > 3 else (f[2] if kind == "turn" and len(f) > 2 else "0")
        # shift is in the model's own units after the importer's scale: given in metres of the scaled model would be
        # surprising, so it is a fraction of the chain's reach (first joint to the farthest joint)
        reach = max((M_arm @ arm.data.bones[n].head_local - pivot).length for n in names) or 1.0
        W = turn_matrix(pivot, yaw, fwd_world * float(sh) * reach)
        new_names = {n: (f[1] + n[len(prefix):]) if kind == "clone" else n for n in names}
        # ---- bones
        bpy.context.view_layer.objects.active = arm
        for o in bpy.context.selected_objects:
            o.select_set(False)
        arm.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        ebs = arm.data.edit_bones
        A_mat = M_arm.inverted() @ W @ M_arm   # the same motion in the armature's own space
        if kind == "clone":
            for n in names:
                if new_names[n] in ebs:
                    raise SystemExit("blender_limb_clone: %s exists already" % new_names[n])
            for n in names:
                o = ebs[n]
                e = ebs.new(new_names[n])
                e.head, e.tail, e.roll = o.head.copy(), o.tail.copy(), o.roll
                e.use_deform = o.use_deform
                e.inherit_scale = o.inherit_scale
            for n in names:
                o = ebs[n]
                e = ebs[new_names[n]]
                if o.parent is not None:
                    e.parent = ebs[new_names.get(o.parent.name, o.parent.name)] if o.parent.name in new_names else o.parent
                e.use_connect = o.use_connect
        for n in names:
            ebs[new_names[n]].transform(A_mat)
        bpy.ops.object.mode_set(mode="OBJECT")
        # ---- mesh islands
        moved = 0
        for ob in body:
            gidx = {g.name: g.index for g in ob.vertex_groups}
            ids = {gidx[n] for n in names if n in gidx}
            if not ids:
                continue
            if kind == "clone":
                for n in names:
                    if n in gidx and new_names[n] not in gidx:
                        ob.vertex_groups.new(name=new_names[n])
                gidx = {g.name: g.index for g in ob.vertex_groups}
            remap = {gidx[n]: gidx[new_names[n]] for n in names if n in gidx}
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            dl = bm.verts.layers.deform.verify()
            comps = islands(bm, dl, ids)
            if not comps:
                bm.free()
                continue
            verts = [v for c in comps for v in c]
            if kind == "clone":
                vs = set(verts)
                faces = [fc for fc in bm.faces if all(v in vs for v in fc.verts)]
                edges = [ed for ed in bm.edges if all(v in vs for v in ed.verts)]
                res = bmesh.ops.duplicate(bm, geom=verts + edges + faces)
                vmap = res["vert_map"]
                verts = [vmap[v] for v in verts]
                for v in verts:
                    w = v[dl]
                    old = dict(w.items())
                    for k in list(w.keys()):
                        del w[k]
                    for gi, val in old.items():
                        w[remap.get(gi, gi)] = val
            Mo = ob.matrix_world
            Lm = Mo.inverted() @ W @ Mo
            for v in verts:
                v.co = Lm @ v.co
            moved += len(verts)
            bm.to_mesh(ob.data)
            ob.data.update()
            bm.free()
        print("blender_limb_clone: %s %s (%d bones, %d vertices) %+.1f deg%s" % (
            kind, prefix + (" -> " + f[1] if kind == "clone" else ""), len(names), moved, yaw,
            (", shift %s of its reach" % sh) if float(sh) else ""))
    if saved_action is not None:
        arm.animation_data.action = saved_action
    R.update()
    if A.get("shot"):
        shot(A["shot"], arm)
    out = os.path.abspath(A["out"])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if out.lower().endswith(".blend"):
        bpy.ops.wm.save_as_mainfile(filepath=out)
    else:
        for o in bpy.data.objects:
            o.select_set(False)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True, export_skins=True,
                                  export_apply=False, use_selection=False)
    print("blender_limb_clone: wrote", out)


def shot(path, arm):
    """A clay view from straight above, the head up the picture."""
    body = R.meshes()
    mn, mx = R.bbox(body)
    sc = R.scene()
    cam = R.make_camera(720)
    clay = R.clay_material()
    backup = R.materials_backup(body)
    R.set_material(body, clay)
    R.workbench("MATERIAL", (0.0, 1.0, 0.0))
    target, extent, dist, ortho = R.camera_rule(mn, mx)
    cam.location = target + Vector((0, 0, dist))
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = Vector((0, 0, -1)).to_track_quat("-Z", "Y")
    cam.data.ortho_scale = ortho * 1.1
    cam.data.clip_end = dist * 4
    R.update()
    R.render(path)
    R.restore_materials(backup)
    bpy.data.objects.remove(cam)
    sc.camera = None


if __name__ == "__main__":
    main()

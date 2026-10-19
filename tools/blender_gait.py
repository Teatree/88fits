"""Procedural motion for a rigged many-legged model (pass 92, lane SPIDER): a walk for a model whose file has no walk clip,
and the "flip_curl" death (rolled onto its back, the legs curled up, the way a real spider or beetle lies dead).
tools/blender_depth_drivers.py renders them (mode=gait, mode=flip_curl) into the same depth-driver folders gen_ctl reads.

Everything is done on the posed bones in world space round each joint, so a rig's own bone axes never matter (a Sketchfab
GLB's bone axes are often nonsense). The legs are found by name: every bone matching `legs` (a regex, default the usual
leg words) whose parent does not match starts a chain, and the chain is that bone and its matching descendants. A leg's
side and its place front to back are read from where its first joint sits round the body, along `forward`.

The walk (mode=gait), one stride over `frames` poses:
  gait=alternate   the legs in two sets half a stride apart, alternating along each side and across: a spider's
                   L1 R2 L3 R4 against R1 L2 R3 L4, an insect's tripod (L1 R2 L3 / R1 L2 R3), a quadruped's trot
  gait=wave        each side's legs one after another from the back forward (a centipede's ripple), the sides opposite
  swing=14         degrees each leg turns fore and aft round its hip over the stride
  lift=18          degrees a leg rises while it swings forward (stepping)
  flex=14          degrees the leg's second joint bends while it is raised (a raised knee)
  duty=0.55        the share of the stride a leg is on the ground (pushing back)
  bob=0.04         the body dips this share of its height twice a stride
  sway=2.5         degrees the body turns side to side once a stride
  step=swing       how a foot is moved (pass 93). swing (pass 92, the default, kept for the old drivers): each leg turns
                   rigidly round the vertical through its hip (swing degrees) and tilts up (lift, flex). That moves a
                   sideways leg's foot fore and aft, but a leg pointing forward or back sweeps its foot ACROSS the body,
                   and the front and back views see the feet slide sideways while the middle legs' fore-aft step is
                   foreshortened away: the spider's legs looked still or moving the wrong way.
                   track: every foot follows the same straight track along the body's length (planted and sliding back
                   under it on the ground, an arc forward through the air), reached by turning the hip round the vertical
                   and bending hip and knee in the leg's own plane (two-bone IK, the knee kept up); swing/lift/flex are
                   then unused. The spider's v2 walk: step=track stride=0.22 raise=0.15 crouch=0.15 sway=0 bob=0.03.
  stride=0.22      track: how far each foot travels fore and aft, a share of the creature's length (legs included)
  raise=0.12       track: how high a foot rises mid-step, a share of the same length
  crouch=0.1       track: each foot's track pulled in towards its hip by this share of its reach, so a leg that rests
                   straight has bend to give (without it a front or back leg reaching out straightens and lies flat)
  knee=up          track: up keeps every knee above the hip-to-foot line (spiders, insects); down below it
The death (mode=flip_curl), over the clip's `total` frames, a timeline in seconds over `seconds`:
  seconds=1.2      how long the whole clip is (frames are spread evenly over it)
  spasm=0.12       seconds of the hit: the legs splay up and the body jumps a little (spasm_deg=22)
  roll_axis=side   side: it rolls over sideways round its own length (a spider); front: it flips over end to end
  roll=180         degrees it turns over (170 leaves it tipped a little to one side, which reads better than flat)
  roll_dir=1       which way it rolls (-1: the other way)
  roll_start=0.08  seconds when the roll starts; roll_time=0.4 seconds it takes
  curl=70          degrees each knee folds in towards the belly at the end; curl_root=40 the hips' share
  curl_start=0.05, curl_end=0.75  seconds the curl happens over (it keeps folding after it lands)
  bounce=0.12      the share of its height it bounces when it lands on its back (two hops, dying away)
  twitch=6         degrees the folded legs twitch after the curl (0: none)
  hold=0.85        the share of the clip after which the pose is held: the last frames are the dead pose
Proportions (both modes, pass 92: a cartoon look's walk lost its big face on the plain model's depth, since Wan follows the
control video's shapes over the painting's): the clay is given the look's proportions before it moves.
  body_scale=1.0   the body bone (the common parent of the legs) this much bigger, the legs kept their own size
  head_scale=1.0   every bone named like head (not head_end) this much bigger on top of the body's scale
  leg_scale=1.0    every leg this much longer or shorter (0.6: stubby cartoon legs)
  scale_bones=     name:factor,... any other bone (its children follow)
  head_pitch=0     degrees the head is raised (positive: it looks up at the camera; a cartoon face then faces the front
                   view instead of showing the top of the head)
"""
import math
import re

try:
    import bpy
    from mathutils import Matrix, Vector
except ImportError:  # importable outside Blender for the selftest (only the pure helpers then)
    bpy = None

LEG_WORDS = r"(?i)leg|thigh|calf|shin|foot|toe|tarsus|femur|tibia"

GAIT_DEFAULTS = {"gait": "alternate", "swing": 14.0, "lift": 18.0, "flex": 14.0, "duty": 0.55, "bob": 0.04, "sway": 2.5,
                 "step": "swing", "stride": 0.22, "raise": 0.12, "crouch": 0.1, "knee": "up"}
SCALE_DEFAULTS = {"body_scale": 1.0, "head_scale": 1.0, "leg_scale": 1.0, "scale_bones": "", "head_pitch": 0.0}
DEATH_DEFAULTS = {"seconds": 1.2, "spasm": 0.12, "spasm_deg": 22.0, "roll_axis": "side", "roll": 180.0, "roll_dir": 1.0,
                  "roll_start": 0.08, "roll_time": 0.4, "curl": 70.0, "curl_root": 40.0, "curl_start": 0.05, "curl_end": 0.75,
                  "bounce": 0.12, "twitch": 6.0, "hold": 0.85}


def options(A, defaults):
    """The mode's options from the command line, numbers as floats, unknown text kept."""
    out = dict(defaults)
    for k, v in defaults.items():
        if k in A and str(A[k]).strip() != "":
            out[k] = A[k] if isinstance(v, str) else float(A[k])
    return out


def phase_offsets(sides, order, gait="alternate"):
    """Each leg's phase offset (0..1) in the stride. `sides` +1 right / -1 left, `order` 0 = the frontmost of its side.
    alternate: (order + side) even -> 0, odd -> 0.5 (L1 R2 L3 R4 against R1 L2 R3 L4); wave: the back leg first."""
    out = []
    n_side = {}
    for s, o in zip(sides, order):
        n_side[s] = max(n_side.get(s, 0), o + 1)
    for s, o in zip(sides, order):
        if gait == "wave":
            n = max(n_side.get(s, 1), 1)
            off = ((n - 1 - o) / float(n)) * 0.5 + (0.5 if s > 0 else 0.0)
            out.append(off % 1.0)
        else:
            out.append(0.0 if (o + (1 if s > 0 else 0)) % 2 == 0 else 0.5)
    return out


def track_offset(ph, duty, stride, raise_):
    """step=track (pass 93): where a foot is at phase `ph` (0..1), as (along, up) in the creature's length units: on the
    ground (ph < duty) it slides straight back under the body from +stride/2 to -stride/2 at an even speed (planted while
    the body walks over it); in the air it comes forward again along an eased arc that peaks at `raise_` mid-step."""
    ph = ph % 1.0
    if ph < duty:
        s = ph / duty
        return stride * (0.5 - s), 0.0
    s = (ph - duty) / max(1.0 - duty, 1e-6)
    e = 0.5 - 0.5 * math.cos(math.pi * s)
    return stride * (-0.5 + e), raise_ * math.sin(math.pi * s)


def two_bone(j1, e, t, knee_up=True):
    """Two-bone IK in a leg's vertical plane, the hip at the origin; points are (out, up) pairs: j1 the knee, e the foot,
    t the target. The knee and everything beyond it turn as one piece (the joints past the knee keep their bend).
    Returns (hip, knee) turns in radians, positive raising the outer part; the target is pulled into reach when it is out
    of it (the foot then stops short along the line to it). knee_up: the knee stays above the hip-to-foot line (a spider's
    or an insect's); False: below it."""
    a = math.hypot(j1[0], j1[1])
    b = math.hypot(e[0] - j1[0], e[1] - j1[1])
    d = math.hypot(t[0], t[1])
    lo, hi = abs(a - b) + 1e-6, a + b - 1e-6
    th = math.atan2(t[1], t[0])
    if a < 1e-9 or b < 1e-9:
        return th - math.atan2(e[1], e[0]), 0.0
    d = min(max(d, lo), hi)
    phi = math.acos(min(max((a * a + d * d - b * b) / (2.0 * a * d), -1.0), 1.0))
    hip = (th + phi if knee_up else th - phi) - math.atan2(j1[1], j1[0])
    c, s_ = math.cos(hip), math.sin(hip)
    k = (j1[0] * c - j1[1] * s_, j1[0] * s_ + j1[1] * c)
    e2 = (e[0] * c - e[1] * s_, e[0] * s_ + e[1] * c)
    tt = (d * math.cos(th), d * math.sin(th))
    knee = math.atan2(tt[1] - k[1], tt[0] - k[0]) - math.atan2(e2[1] - k[1], e2[0] - k[0])
    knee = (knee + math.pi) % (2.0 * math.pi) - math.pi
    return hip, knee


def leg_angles(ph, duty, swing, lift, flex):
    """(yaw forward, lift, knee flex) in degrees for a leg at phase `ph` (0..1): on the ground it sweeps back from +swing to
    -swing; in the air it comes forward again, raised and bent."""
    ph = ph % 1.0
    if ph < duty:
        s = ph / duty
        return swing * (1.0 - 2.0 * s), 0.0, 0.0
    s = (ph - duty) / max(1.0 - duty, 1e-6)
    e = 0.5 - 0.5 * math.cos(math.pi * s)
    return swing * (-1.0 + 2.0 * e), lift * math.sin(math.pi * s), flex * math.sin(math.pi * s)


def bone_scales(o, names, body_bone, leg_roots):
    """{bone: pose scale} for the proportion options: body_scale on the body bone with every leg root given
    leg_scale / body_scale (a bone inherits its parent's scale, so the legs keep leg_scale), head_scale on the head bones,
    scale_bones as written. Empty when every factor is 1."""
    out = {}
    bs = float(o.get("body_scale", 1.0) or 1.0)
    ls = float(o.get("leg_scale", 1.0) or 1.0)
    hs = float(o.get("head_scale", 1.0) or 1.0)
    if body_bone and abs(bs - 1.0) > 1e-9:
        out[body_bone] = bs
    if abs(ls / bs - 1.0) > 1e-9:
        for r in leg_roots:
            out[r] = ls / bs
    if abs(hs - 1.0) > 1e-9:
        for n in names:
            if re.search(r"(?i)head", n) and not re.search(r"(?i)end$|_end|top", n):
                out[n] = hs
                break   # the first head bone: its children (the fangs, the head's end) follow it
    for part in [p for p in str(o.get("scale_bones", "") or "").split(",") if ":" in p]:
        n, f = part.rsplit(":", 1)
        if n.strip() in names:
            out[n.strip()] = float(f)
    return out


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def death_curve(t, o):
    """The death's state at `t` seconds: {spasm (0..1 of spasm_deg), roll (degrees), curl (0..1), hop (share of the
    height), twitch (0..1 of twitch, signed)}; past `hold` of the clip everything is at its end."""
    T = float(o["seconds"])
    t = min(t, T * float(o["hold"]))
    sp = float(o["spasm"])
    spasm = math.sin(math.pi * min(t / sp, 1.0)) if sp > 0 and t < sp else 0.0
    r0, rt = float(o["roll_start"]), max(float(o["roll_time"]), 1e-3)
    u = (t - r0) / rt
    roll = float(o["roll"]) * (0.0 if u <= 0 else (1.0 if u >= 1 else (u * u * u * (u * (u * 6 - 15) + 10))))
    c0, c1 = float(o["curl_start"]), max(float(o["curl_end"]), float(o["curl_start"]) + 1e-3)
    curl = ease((t - c0) / (c1 - c0))
    land = r0 + rt
    hop = 0.0
    bt = 0.35
    if t > land and float(o["bounce"]) > 0:
        v = (t - land) / bt
        if v < 1.0:
            hop = float(o["bounce"]) * abs(math.sin(2.0 * math.pi * v)) * (1.0 - v)
    tw = 0.0
    hold_t = T * float(o["hold"])
    if float(o["twitch"]) > 0 and t > c1 and hold_t > c1:
        v = (t - c1) / (hold_t - c1)
        tw = math.sin(2.0 * math.pi * 3.0 * v) * (1.0 - v)
    return {"spasm": spasm, "roll": roll, "curl": curl, "hop": hop, "twitch": tw}


# ---------------------------------------------------------------- the rig (Blender only)

class Legs:
    """The model's leg chains and body, posed procedurally from its rest (or base) pose."""

    def __init__(self, arm, body, root, fwd, legs_re=LEG_WORDS, base=None, scales=None):
        self.arm, self.body, self.root = arm, body, root
        self.fwd = Vector((fwd.x, fwd.y, 0.0)).normalized()
        self.up = Vector((0.0, 0.0, 1.0))
        self.right = self.fwd.cross(self.up)
        self.base = base            # {bone: (loc, quat, scale)} or None (the rest pose)
        self.scales = {}            # {bone: scale} laid on after every reset (the look's proportions)
        self.root_m0 = root.matrix_world.copy()
        self.reset()
        pat = re.compile(legs_re)
        bones = arm.pose.bones
        match = {b.name for b in bones if pat.search(b.name)}
        roots = [b for b in bones if b.name in match and (b.parent is None or b.parent.name not in match)]
        self.chains = []
        for r in roots:
            chain = [r]
            cur = r
            while True:
                kids = [c for c in cur.children if c.name in match]
                if not kids:
                    break
                cur = kids[0]
                chain.append(cur)
            self.chains.append(chain)
        if not self.chains:
            raise SystemExit("blender_gait: no bone matches legs=%r; the bones are: %s" % (legs_re, ", ".join(b.name for b in bones)))
        parents = {c[0].parent.name if c[0].parent else None for c in self.chains}
        self.body_bone = bones[list(parents)[0]] if len(parents) == 1 and None not in parents else None
        self.scales = bone_scales(scales or {}, [b.name for b in bones], self.body_bone.name if self.body_bone else None,
                                  [c[0].name for c in self.chains])
        self.head_pitch = float((scales or {}).get("head_pitch", 0.0) or 0.0)
        self.head_bone = next((b for b in bones if re.search(r"(?i)head", b.name) and not re.search(r"(?i)end$|_end|top", b.name)), None)
        if self.scales:
            self.reset()
        mn, mx = self.bbox()
        self.centre = (mn + mx) * 0.5
        self.height = max(mx.z - mn.z, 1e-6)
        self.ground = mn.z
        sides, ahead = [], []
        for c in self.chains:
            h = self.world(c[0].head)
            d = h - self.centre
            sides.append(1 if d.dot(self.right) > 0 else -1)
            ahead.append(d.dot(self.fwd))
        order = []
        for i, s in enumerate(sides):
            order.append(sorted([j for j in range(len(sides)) if sides[j] == s], key=lambda j: -ahead[j]).index(i))
        self.sides, self.order = sides, order
        # each leg's fold axis read once from the rest (or base) pose: recomputed as a leg folds, its horizontal direction
        # flips once it passes straight down and the fold would turn back on itself (the first curls came out bunched)
        self.axes = [self.fold_axis(c, self.up) for c in self.chains]

    # -------------------------------------------------------- helpers
    def world(self, v_arm):
        return self.arm.matrix_world @ v_arm

    def bbox(self):
        import blender_ref as R
        return R.bbox(self.body)

    def describe(self):
        rows = []
        for c, s, o in zip(self.chains, self.sides, self.order):
            rows.append("%s%d %s (%d bones)" % ("R" if s > 0 else "L", o + 1, c[0].name, len(c)))
        return rows

    def reset(self):
        self.root.matrix_world = self.root_m0.copy()
        for pb in self.arm.pose.bones:
            if self.base and pb.name in self.base:
                loc, q, s = self.base[pb.name]
                pb.location, pb.scale = loc, s
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = q
            else:
                pb.location = (0, 0, 0)
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.scale = (1, 1, 1)
            f = self.scales.get(pb.name)
            if f is not None:
                pb.scale = (pb.scale[0] * f, pb.scale[1] * f, pb.scale[2] * f)
        bpy.context.view_layer.update()
        hb = getattr(self, "head_bone", None)
        if hb is not None and abs(getattr(self, "head_pitch", 0.0)) > 1e-6:
            # raised round the side-to-side axis through the head's joint: a positive turn round `right` lifts the front
            self.turn_bone(hb, self.world(hb.head), self.right, self.head_pitch)

    def turn_bone(self, pb, pivot_w, axis_w, deg):
        """pb (and so its children) turned `deg` round a world axis through a world point."""
        if abs(deg) < 1e-6:
            return
        W = Matrix.Translation(pivot_w) @ Matrix.Rotation(math.radians(deg), 4, axis_w.normalized()) @ Matrix.Translation(-pivot_w)
        M = self.arm.matrix_world
        pb.matrix = (M.inverted() @ W @ M) @ pb.matrix
        bpy.context.view_layer.update()

    def leg_dir(self, chain):
        """The leg's horizontal direction now: its first joint to its last."""
        a = self.world(chain[0].head)
        b = self.world(chain[-1].head if len(chain) > 1 else chain[0].tail)
        v = b - a
        v.z = 0.0
        return v.normalized() if v.length > 1e-9 else self.right

    def fold_axis(self, chain, up):
        """The axis a positive turn round which folds the leg's outer part towards the belly (`up` is the body's up)."""
        t = self.leg_dir(chain)
        a = up.cross(t)
        return a.normalized() if a.length > 1e-9 else self.fwd

    # -------------------------------------------------------- leg tips (pass 93: tips=1 writes where each foot goes)
    def tip_vertices(self, objs):
        """Per chain, the mesh vertex its foot is: of the vertices weighted mostly to the chain's last bone that has any,
        the farthest from its hip measured flat (a spider's raised knee is farther from a hip sunk under the body than its
        foot is, in 3D); (object index, vertex index) or None when the mesh has no such weights."""
        import numpy as np
        dg = bpy.context.evaluated_depsgraph_get()
        out = []
        per_obj = []
        for o in objs:
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            arr = np.empty(len(me.vertices) * 3, dtype=np.float64)
            me.vertices.foreach_get("co", arr)
            mw = np.array(ev.matrix_world, dtype=np.float64)
            w = arr.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
            ev.to_mesh_clear()
            names = {g.index: g.name for g in o.vertex_groups}
            top = []
            for v in o.data.vertices:
                best = max(v.groups, key=lambda g: g.weight, default=None)
                top.append(names.get(best.group) if best is not None else None)
            per_obj.append((w, top))
        for c in self.chains:
            hip = self.world(c[0].head)
            best = None
            for pb in reversed(c):
                far = -1.0
                for oi, (w, top) in enumerate(per_obj):
                    for vi, g in enumerate(top):
                        if g == pb.name:
                            d = Vector((w[vi][0] - hip.x, w[vi][1] - hip.y)).length
                            if d > far:
                                best, far = (oi, vi), d
                if best is not None:
                    break
            out.append(best)
        return out

    def tips_world(self, objs, verts):
        """Each chain's foot now, in world space: its tip vertex (tip_vertices) where it has one, else the last bone's tail;
        and the bone tails, [(mesh_tip, bone_tip), ...]."""
        import numpy as np
        dg = bpy.context.evaluated_depsgraph_get()
        cos = []
        for o in objs:
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            arr = np.empty(len(me.vertices) * 3, dtype=np.float64)
            me.vertices.foreach_get("co", arr)
            mw = np.array(ev.matrix_world, dtype=np.float64)
            cos.append(arr.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3])
            ev.to_mesh_clear()
        out = []
        for c, tv in zip(self.chains, verts):
            bone = self.world(c[-1].tail)
            mesh = Vector(cos[tv[0]][tv[1]]) if tv is not None else bone
            out.append((mesh, bone))
        return out

    # -------------------------------------------------------- the walk
    def track_setup(self):
        """step=track: each leg's hip, knee and foot at rest in world space (the foot is the mesh's tip vertex, else the last
        bone's tail) and the creature's length along forward, read once."""
        import numpy as np
        import blender_ref as R
        self.reset()
        verts = self.tip_vertices(self.body)
        feet = [m for m, _b in self.tips_world(self.body, verts)]
        w = R.verts_world(self.body)
        f = np.array([self.fwd.x, self.fwd.y, 0.0])
        proj = w @ f
        self.length = max(float(proj.max() - proj.min()), 1e-6)
        self.track = []
        for c, foot in zip(self.chains, feet):
            j0 = self.world(c[0].head)
            j1 = self.world(c[1].head) if len(c) > 1 else None
            self.track.append((j0, j1, foot.copy()))

    def pose_track(self, c, rest, along, up_, knee_up, crouch=0.0):
        """One leg posed so its foot reaches rest foot + forward x along + up x up_ (world units): the hip turns round the
        vertical (the foot's bearing), then the hip and the knee bend in the leg's vertical plane (two_bone). crouch: the
        foot's track is pulled in towards the hip by this share of its flat reach, so a leg that rests straight has bend to
        give when its foot reaches forward or back (else it straightens and lies flat)."""
        j0, j1, foot = rest
        flat0 = Vector((foot.x - j0.x, foot.y - j0.y, 0.0))
        T = foot - flat0 * crouch + self.fwd * along + self.up * up_
        u0 = Vector((foot.x - j0.x, foot.y - j0.y, 0.0))
        u1 = Vector((T.x - j0.x, T.y - j0.y, 0.0))
        if u0.length < 1e-9 or u1.length < 1e-9:
            return
        yaw = math.atan2(u0.cross(u1).z, u0.dot(u1))
        self.turn_bone(c[0], j0, self.up, math.degrees(yaw))
        if j1 is None:
            return
        Ry = Matrix.Rotation(yaw, 3, self.up)
        k = j0 + Ry @ (j1 - j0)
        e = j0 + Ry @ (foot - j0)
        h = u1.normalized()

        def flat(P):
            d = P - j0
            return (d.dot(h), d.z)
        hip, knee = two_bone(flat(k), flat(e), flat(T), knee_up)
        axis = h.cross(self.up)
        self.turn_bone(c[0], j0, axis, math.degrees(hip))
        k2 = j0 + Matrix.Rotation(hip, 3, axis) @ (k - j0)
        self.turn_bone(c[1], k2, axis, math.degrees(knee))

    def pose_gait(self, phase, o):
        if str(o.get("step", "swing")) == "track":
            if getattr(self, "track", None) is None:
                self.track_setup()
            self.reset()
            offs = phase_offsets(self.sides, self.order, o["gait"])
            L = self.length
            for c, off, rest in zip(self.chains, offs, self.track):
                along, h = track_offset(phase + off, float(o["duty"]), float(o["stride"]), float(o["raise"]))
                self.pose_track(c, rest, along * L, h * L, str(o.get("knee", "up")) != "down", float(o.get("crouch", 0.0)))
            self.body_motion(phase, o)
            return
        self.reset()
        offs = phase_offsets(self.sides, self.order, o["gait"])
        for c, off in zip(self.chains, offs):
            yaw, lift, flex = leg_angles(phase + off, float(o["duty"]), float(o["swing"]), float(o["lift"]), float(o["flex"]))
            hip = self.world(c[0].head)
            t = self.leg_dir(c)
            sgn = 1.0 if self.up.cross(t).dot(self.fwd) > 0 else -1.0   # a positive turn round up moves the tip forward
            self.turn_bone(c[0], hip, self.up, sgn * yaw)
            a = self.fold_axis(c, self.up)
            self.turn_bone(c[0], self.world(c[0].head), a, -lift)
            if len(c) > 1 and flex:
                self.turn_bone(c[1], self.world(c[1].head), self.fold_axis(c, self.up), flex)
        self.body_motion(phase, o)

    def body_motion(self, phase, o):
        """The body's sway (turned side to side once a stride) and bob (dipped twice a stride)."""
        if self.body_bone is not None and float(o["sway"]):
            self.turn_bone(self.body_bone, self.centre, self.up, float(o["sway"]) * math.sin(2.0 * math.pi * phase))
        dip = float(o["bob"]) * self.height * (0.5 + 0.5 * math.cos(4.0 * math.pi * phase))
        if dip:
            self.root.matrix_world = Matrix.Translation(Vector((0, 0, -dip))) @ self.root.matrix_world
            bpy.context.view_layer.update()

    # -------------------------------------------------------- the death
    def pose_flip_curl(self, t, o):
        self.reset()
        st = death_curve(t, o)
        up = self.up
        for i, c in enumerate(self.chains):
            a = self.axes[i]
            # the hit: every leg flung up for a moment; then the curl: the hip swings the leg towards the belly and each
            # further joint folds it in, all round the leg's one fold axis
            hip = float(o["curl_root"]) * st["curl"] - float(o["spasm_deg"]) * st["spasm"]
            self.turn_bone(c[0], self.world(c[0].head), a, hip)
            tw = float(o["twitch"]) * st["twitch"] * (1.0 if (i % 2) == 0 else -0.7)
            for pb in c[1:]:
                self.turn_bone(pb, self.world(pb.head), a, float(o["curl"]) * st["curl"] + tw)
        # the roll, round the body's centre, then down onto the ground (plus the spasm's jump and the bounce)
        axis = self.fwd if o["roll_axis"] == "side" else self.right
        if st["roll"]:
            W = (Matrix.Translation(self.centre) @ Matrix.Rotation(math.radians(st["roll"] * float(o["roll_dir"])), 4, axis)
                 @ Matrix.Translation(-self.centre))
            self.root.matrix_world = W @ self.root.matrix_world
            bpy.context.view_layer.update()
        mn, _mx = self.bbox()
        lift = (st["hop"] + 0.15 * st["spasm"]) * self.height
        self.root.matrix_world = Matrix.Translation(Vector((0, 0, self.ground + lift - mn.z))) @ self.root.matrix_world
        bpy.context.view_layer.update()
        return st

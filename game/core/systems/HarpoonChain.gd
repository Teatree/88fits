## The harpooner's chain (pass 111, lane ENEMY; Garry: "Harpooner - The harpoon is too simplistic. Make it look like a fat
## chain so it's easier to understand what it does. Make the whole shooting of the harpoon sequence more impressive and
## noticeable."). One MultiMesh of chunky iron links (a TorusMesh stretched into an oval, every other one turned a quarter
## about the chain, so it reads as a chain from the high camera), dark-outlined, from the harpooner's hand to the hook,
## and the hook itself (art/props/harpoon_hook.glb, tools/blender_harpoon.py) where no shot draws it: stuck in the hero
## while he is roped, and flying home when a throw misses. Game drives it (enemy_shot_straight, _tick_tether,
## tether_start, tether_end): `launch` (sparks off the hand, the chain paying out behind the hook with a wave running down
## it), `draw` (every frame the hook flies or the hero is roped: taut and rattling while it hauls, a little sag while it
## holds), `hooked` (a clank of sparks at the hero and at the hand, the chain snapping taut with a shudder, a short camera
## kick through CameraRig.shake, so the screen-shake setting holds), `missed` (the chain goes slack and the hook is reeled
## back to the hand), `release` (the rope ends: hidden), `snap_break` (pass 112: the rope breaks: the chain snaps with sparks
## and a tink, the two halves whip and fall and shrink away, the hook drops off the hero), `warm` (pass 112: drawn once under
## the spawn beam, Warmup). The numbers are the creature's `ranged.harpoon_fx` over DEFAULTS
## (configure). Parented under the ProjectileManager, so the stage filter never darkens it (StageStencil.CLEAR, like
## every shot). Nothing runs in the sim (Run.sim_mode) but the hidden state.
class_name HarpoonChain
extends Node3D

const HOOK_MODEL := "res://art/props/harpoon_hook.glb"
## the most links drawn (a 24 m chain at 0.3 m a link)
const MAX_LINKS := 120
## `ranged.harpoon_fx`'s keys and the game's values for the ones a creature leaves out
const DEFAULTS := {
	"hand": {"up": 1.45, "side": 0.55, "forward": 0.25},
	"chain": {"link": 0.56, "width": 0.4, "thick": 0.13, "colour": "#8A8A94", "outline": "#140E0C", "outline_px": 0.022, "overlap": 0.3},
	"hook_scale": 1.3,
	"windup": {"lean": 16.0, "glint": 0.5},
	"launch": {"sparks": 7, "streak": "#FFF1D0", "streak_width": 0.22, "streak_life": 0.22, "wave": 0.22, "sfx": "w_spear_throw"},
	"hit": {"shake": 0.35, "snap": 0.35, "sfx": "w_hammer_hit"},
	"miss": {"reel": 0.6, "sfx": "w_hammer_swing"},
	"rattle": 0.035,
	# pass 112 (lane ENEMY): the rope breaking (snap_break): where along it (0 the hand .. 1 the hook), the loose ends' whip
	# (m), how long until it is gone (s), how far the hand's half springs back (a share of it), the metal bits flung out,
	# the tink's size
	"break": {"at": 0.55, "whip": 0.55, "seconds": 0.9, "recoil": 0.7, "bits": 8, "tink": 1.1, "sfx": "w_spear_hit"},
}
## the links' modes (draw)
const FLY := 0
const TAUT := 1
const SLACK := 2
const REEL := 3

var cfg: Dictionary = DEFAULTS.duplicate(true)
var game: Node = null
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _hook: MeshInstance3D
var _clock := 0.0
## seconds since the last launch, hook-in and the reel's start (-1 = none running)
var _launch_t := -1.0
var _snap_t := -1.0
var _reel_t := -1.0
var _reel_from := Vector3.ZERO
var _reel_shooter := -1
## pass 112: the break under way (snap_break; -1 = none): its clock, the shooter, the chain's ends and where it broke, the
## hook where it hung and the point it led away from, the hook's shrink
var _brk_t := -1.0
var _brk_shooter := -1
var _brk_a := Vector3.ZERO
var _brk_b := Vector3.ZERO
var _brk_p := Vector3.ZERO
var _hook_at := Vector3.INF
var _hook_from := Vector3.ZERO
var _hook_k := 1.0
## diagnostics and tests: links drawn on the last draw, launches, hook-ins, misses reeled, and the last draw's ends
var links_drawn := 0
var launches := 0
var hooks := 0
var reels := 0
var breaks := 0
var last_a := Vector3.ZERO
var last_b := Vector3.ZERO
var last_mode := -1


## A block over DEFAULTS, key by key (one level of nesting deep).
static func merged(fx) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if not (fx is Dictionary):
		return out
	for k in (fx as Dictionary).keys():
		var v = fx[k]
		if v is Dictionary and out.get(k) is Dictionary:
			var sub: Dictionary = (out[k] as Dictionary).duplicate()
			for kk in (v as Dictionary).keys():
				sub[kk] = v[kk]
			out[k] = sub
		else:
			out[k] = v
	return out


## The hook's mesh (the GLB's first mesh; a red box without the file, the pass 28 harpoon).
static func hook_mesh() -> Mesh:
	if ResourceLoader.exists(HOOK_MODEL):
		var scn = load(HOOK_MODEL)
		if scn is PackedScene:
			var root: Node = (scn as PackedScene).instantiate()
			var found: Mesh = null
			for c in root.find_children("*", "MeshInstance3D", true, false):
				if (c as MeshInstance3D).mesh:
					found = (c as MeshInstance3D).mesh
					break
			root.free()
			if found:
				return found
	var b := BoxMesh.new()
	b.size = Vector3(0.07, 0.07, 1.0)
	return b


## The hook's material: its vertex colours lit as iron (the red shaft stays the one red thing on the line), with a dark
## outline so it reads on any sand.
static func hook_material() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = ResourceLoader.exists(HOOK_MODEL)
	m.albedo_color = Color.WHITE if m.vertex_color_use_as_albedo else Color(1.0, 0.12, 0.08)
	m.metallic = 0.15
	m.roughness = 0.45
	# the warm haze would brown the iron and its outline (pass 70's trampoline lesson): clear of it, like the bomb
	m.set("disable_fog", true)
	m.next_pass = _outline_material(Color(0.08, 0.05, 0.04), 0.025)
	return m


static func _outline_material(col: Color, grow: float) -> StandardMaterial3D:
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.albedo_color = col
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = grow
	o.set("disable_fog", true)
	return o


func setup(p_game: Node) -> void:
	game = p_game
	_build()


## The creature's own numbers for the next throw (its `ranged.harpoon_fx`).
func configure(fx) -> void:
	cfg = merged(fx)
	if _mmi != null:
		var ch: Dictionary = cfg["chain"]
		var m := _mmi.material_override as StandardMaterial3D
		if m != null:
			m.albedo_color = Color.from_string(str(ch.get("colour", "#8A8A94")), Color(0.54, 0.54, 0.58))
			var o := m.next_pass as StandardMaterial3D
			if o != null:
				o.albedo_color = Color.from_string(str(ch.get("outline", "#140E0C")), Color(0.08, 0.05, 0.04))
				o.grow_amount = float(ch.get("outline_px", 0.022))


func _build() -> void:
	if _mm != null:
		return
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.5
	torus.rings = 14
	torus.ring_segments = 8
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = torus
	_mm.instance_count = MAX_LINKS
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.54, 0.54, 0.58)
	mat.metallic = 0.3
	mat.roughness = 0.4
	mat.set("disable_fog", true)
	mat.next_pass = _outline_material(Color(0.08, 0.05, 0.04), 0.018)
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(_mmi)
	_hook = MeshInstance3D.new()
	_hook.mesh = hook_mesh()
	_hook.material_override = hook_material()
	_hook.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hook.visible = false
	add_child(_hook)
	configure({})


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt): the camera and what is on screen follow it
	delta = Lockstep.dt(delta)
	_clock += delta
	if _launch_t >= 0.0:
		_launch_t += delta
	if _snap_t >= 0.0:
		_snap_t += delta
		if _snap_t > 2.0:
			_snap_t = -1.0
	if _reel_t >= 0.0:
		_tick_reel(delta)
	if _brk_t >= 0.0:
		_tick_break(delta)


## Where creature `i`'s chain leaves its hand, aiming at `toward` (EnemyManager.muzzle_point with the block's `hand`).
func hand_of(i: int, toward: Vector3) -> Vector3:
	var em = game.get("enemies") if game != null else null
	if em == null or not em.is_alive(i):
		return Vector3.INF
	var hd = cfg.get("hand", {})
	return em.muzzle_point(i, toward - em.pos[i], hd if hd is Dictionary else {})


## The wind-up's last moment (EnemyManager._steer, REAR_GLINT s before the throw): a white glint off the hook in creature
## `i`'s hand, a flash and four rays of light flung out, `windup.glint` its size (0 = none).
func glint(i: int, toward: Vector3) -> void:
	configure_from(i)
	var size := float((cfg["windup"] as Dictionary).get("glint", 0.5))
	if Run.sim_mode or size <= 0.0:
		return
	var at := hand_of(i, toward)
	var fx = game.get("fx") if game != null else null
	if not at.is_finite() or fx == null or not fx.has_method("mote"):
		return
	at += Vector3(0, 0.35, 0)
	fx.mote(at, Vector3.ZERO, 0.32, size * 1.6, Color(1.0, 1.0, 0.95, 1.0))
	fx.mote(at, Vector3.ZERO, 0.45, size * 2.6, Color(1.0, 0.92, 0.7, 0.45))
	for k in range(4):
		var a := TAU * float(k) / 4.0 + PI * 0.25
		fx.mote(at, Vector3(cos(a), sin(a) * 0.8 + 0.2, sin(a) * 0.5) * 3.2, 0.22, size * 0.45, Color(1.0, 1.0, 0.9, 1.0))


## Takes creature `i`'s own block (its def's `ranged.harpoon_fx`).
func configure_from(i: int) -> void:
	var em = game.get("enemies") if game != null else null
	if em == null or i < 0 or i >= em.type_idx.size():
		return
	var def: EnemyDef = em.types[em.type_idx[i]]["def"]
	configure(def.ranged.get("harpoon_fx", {}))


## The throw left: sparks off the hand, the wave starts down the chain.
func launch(from: Vector3, dir: Vector3) -> void:
	_launch_t = 0.0
	_snap_t = -1.0
	_reel_t = -1.0
	_brk_t = -1.0
	_hook_k = 1.0
	launches += 1
	if Run.sim_mode:
		return
	var lc: Dictionary = cfg["launch"]
	var fx = game.get("fx") if game != null else null
	if fx != null and fx.has_method("mote"):
		for k in range(int(lc.get("sparks", 7))):
			var v := dir * randf_range(3.0, 6.0) + Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.5), randf_range(-1.5, 1.5))
			fx.mote(from, v, randf_range(0.18, 0.32), 0.14, Color(1.0, randf_range(0.7, 0.95), 0.4, 1.0))
	Audio.play(str(lc.get("sfx", "")), from)


## The chain between the hand `a` and the hook's end `b` this frame, in `mode` (FLY, TAUT, SLACK); `sag` the share of its
## length it hangs at the middle (at most 0.9 m).
func draw(a: Vector3, b: Vector3, sag: float, mode: int) -> void:
	last_a = a
	last_b = b
	last_mode = mode
	if Run.sim_mode or _mm == null or not a.is_finite() or not b.is_finite():
		return
	var k := _lay(a, b, sag, mode, 0, 1.0, 0.0, true)
	_mm.visible_instance_count = k
	links_drawn = k


## Lays the links from `a` to `b` into the MultiMesh from instance `k0` on (draw, and both halves of a break); `scale`
## shrinks every link (a broken half going), `whip` throws its loose end (the `b` end when `loose_b`, else the `a` end)
## that many metres across the chain. Returns the next free instance.
func _lay(a: Vector3, b: Vector3, sag: float, mode: int, k0: int, scale: float, whip: float, loose_b: bool) -> int:
	var ch: Dictionary = cfg["chain"]
	var link := maxf(float(ch.get("link", 0.56)), 0.08)
	var width := maxf(float(ch.get("width", 0.4)), 0.04)
	var thick := maxf(float(ch.get("thick", 0.13)), 0.02)
	var pitch := link * clampf(1.0 - float(ch.get("overlap", 0.3)), 0.4, 1.0)
	var span := a.distance_to(b)
	var n: int = mini(int(span / pitch), MAX_LINKS)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var to_cam: Vector3 = (cam.global_position - a.lerp(b, 0.5)).normalized() if cam else Vector3.UP
	var along := (b - a) / maxf(span, 0.001)
	var side := along.cross(to_cam)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	# the sag, a snap's shudder on top, and the wave or the rattle across the chain
	var s := minf(span * sag, 0.9)
	var shud := 0.0
	if _snap_t >= 0.0:
		var snap := float((cfg["hit"] as Dictionary).get("snap", 0.35))
		s += snap * exp(-_snap_t * 9.0) * cos(_snap_t * 34.0)
		shud = snap * 0.6 * exp(-_snap_t * 8.0)
	var wave := 0.0
	if mode == FLY and _launch_t >= 0.0:
		wave = float((cfg["launch"] as Dictionary).get("wave", 0.22)) * exp(-_launch_t * 2.5)
	var rattle := float(cfg.get("rattle", 0.035)) if mode == TAUT else 0.0
	var k := k0
	if scale <= 0.01:
		return k
	link *= scale
	width *= scale
	thick *= scale
	for j in range(n):
		if k >= MAX_LINKS:
			break
		var f := (float(j) + 0.5) * pitch / maxf(span, 0.001)
		var p := _point(a, b, f, s, side, wave, rattle, shud, span)
		var q := _point(a, b, minf(f + 0.02, 1.0), s, side, wave, rattle, shud, span)
		if whip != 0.0:
			# a loose end lashes across: most at the end that broke, nothing where it is still held
			var e := f if loose_b else 1.0 - f
			p += side * whip * e * e
			var fq := minf(f + 0.02, 1.0)
			var eq := fq if loose_b else 1.0 - fq
			q += side * whip * eq * eq
		var t := (q - p)
		t = t.normalized() if t.length_squared() > 0.000001 else along
		var sd := t.cross(to_cam)
		sd = sd.normalized() if sd.length_squared() > 0.0001 else side
		var nf := sd.cross(t).normalized()
		var bs: Basis
		if j % 2 == 0:
			# the link seen flat: its ring open towards the camera
			bs = Basis(t * link, nf * (thick / 0.2), sd * width)
		else:
			# the link between, seen edge on
			bs = Basis(t * link, sd * (thick / 0.2), nf * width * 0.85)
		_mm.set_instance_transform(k, Transform3D(bs, p))
		k += 1
	return k


## A point `f` of the way along the chain from `a` to `b`: the sag hanging it down in the middle, the wave running from the
## hand to the hook, the rattle's quick jitter and a snap's shudder across it, none at the ends.
func _point(a: Vector3, b: Vector3, f: float, sag: float, side: Vector3, wave: float, rattle: float, shud: float, span: float) -> Vector3:
	var p := a.lerp(b, f)
	p.y -= sag * 4.0 * f * (1.0 - f)
	var env := sin(PI * f)
	var off := 0.0
	if wave > 0.0:
		off += wave * sin(TAU * (f * span / 2.4 - _launch_t * 3.0)) * env
	if rattle > 0.0:
		off += rattle * sin(TAU * (f * span / 0.9 + _clock * 11.0)) * env
	if shud > 0.0:
		off += shud * sin(PI * f * 3.0) * cos(_snap_t * 41.0) * env
	return p + side * off


## Where the chain meets a hook at `at` whose point leads away from `from` (its eye, EYE of its length behind the middle,
## at its drawn size: hook_scale x the shots' CHUNK).
const EYE := 0.42
func eye_of(at: Vector3, from: Vector3) -> Vector3:
	var d := at - from
	if d.length_squared() < 0.0001:
		return at
	return at - d.normalized() * EYE * float(cfg.get("hook_scale", 1.3)) * ProjectileManager.CHUNK


## The hook stuck where the chain ends, its point along the chain away from the hand (roped: in the hero).
func show_hook(at: Vector3, from: Vector3) -> void:
	if _hook == null or Run.sim_mode:
		return
	var d := at - from
	if d.length_squared() < 0.0001:
		d = Vector3.FORWARD
	_hook_at = at
	_hook_from = from
	var hs := float(cfg.get("hook_scale", 1.3)) * ProjectileManager.CHUNK * _hook_k
	_hook.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).scaled(Vector3(hs, hs, hs)), at)
	_hook.visible = true


## The hook bit (Game.tether_start): a clank at the hero and at the hand, the chain snaps taut with a shudder, and the camera
## kicks (CameraRig.shake: the player's screen-shake setting scales it).
func hooked(at: Vector3, hand: Vector3) -> void:
	_snap_t = 0.0
	_launch_t = -1.0
	_reel_t = -1.0
	hooks += 1
	if Run.sim_mode:
		return
	var hc: Dictionary = cfg["hit"]
	var fx = game.get("fx") if game != null else null
	if fx != null and fx.has_method("clang_spark"):
		fx.clang_spark(at, (at - hand))
		if hand.is_finite():
			fx.clang_spark(hand, (hand - at))
	var cam = game.get("camera") if game != null else null
	if cam != null and cam.has_method("shake"):
		cam.shake(float(hc.get("shake", 0.35)))
	Audio.play(str(hc.get("sfx", "")), at)


## The throw missed (its shot ran out at `at`): the chain goes slack and the hook comes home to creature `shooter`'s hand.
func missed(at: Vector3, shooter: int) -> void:
	_launch_t = -1.0
	if not at.is_finite():
		release()
		return
	_reel_from = at
	_reel_shooter = shooter
	_reel_t = 0.0
	reels += 1
	if not Run.sim_mode:
		Audio.play(str((cfg["miss"] as Dictionary).get("sfx", "")), at)


func _tick_reel(delta: float) -> void:
	_reel_t += delta
	var secs := maxf(float((cfg["miss"] as Dictionary).get("reel", 0.6)), 0.05)
	var em = game.get("enemies") if game != null else null
	if em == null or not em.is_alive(_reel_shooter) or _reel_t >= secs:
		_reel_t = -1.0
		release()
		return
	var hand := hand_of(_reel_shooter, _reel_from)
	if not hand.is_finite():
		_reel_t = -1.0
		release()
		return
	# eased in: it drags at first, then whips home
	var u := clampf(_reel_t / secs, 0.0, 1.0)
	var at := _reel_from.lerp(hand, u * u)
	var map = game.get("map") if game != null else null
	if map != null and map.has_method("height_at"):
		at.y = maxf(at.y, map.height_at(at.x, at.z) + 0.15)
	# dragged home backwards: its eye towards the hand, its point trailing away
	draw(hand, eye_of(at, hand), 0.14 * (1.0 - u) + 0.03, REEL)
	show_hook(at, hand)


## The rope is over (it ran out, its thrower died, the hero cut free): nothing drawn.
func release() -> void:
	_launch_t = -1.0
	_snap_t = -1.0
	if _reel_t >= 0.0 or _brk_t >= 0.0:
		return
	_hook_at = Vector3.INF
	_hook_k = 1.0
	if _mm != null:
		_mm.visible_instance_count = 0
	if _hook != null:
		_hook.visible = false
	links_drawn = 0


## Whether a miss's reel is under way (Game leaves the chain to it).
func reeling() -> bool:
	return _reel_t >= 0.0


# ---------------------------------------------------------------- pass 112 (lane ENEMY): the chain breaks
## Garry (pass 112): "Harpooner - the chain should break when it breaks. Like there should be a visual of this." When the
## rope ends any other way than a clean miss's reel (its time runs out, the harpooner dies, a teleport, the hero falls:
## Game.tether_end), the chain snaps where it hung (`break.at` of the way from the hand, give or take a little): a clank
## of sparks and a white tink at the break, a few iron bits flung out (Fx.splinters), the hand's half springs back
## `break.recoil` of its length towards the harpooner's hand and both loose ends lash `break.whip` m across, dying away, as
## the halves drop to the sand; the hook falls off the hero to his feet; over the last 40% of `break.seconds` every link
## and the hook shrink away. Nothing in the sim.

## The rope broke (Game.tether_end): the chain snaps as it was last drawn; `shooter` the harpooner (its hand is followed
## while it lives). Nothing drawn (nothing to break) = released.
func snap_break(shooter: int) -> void:
	_launch_t = -1.0
	_snap_t = -1.0
	_reel_t = -1.0
	if Run.sim_mode or links_drawn <= 0 or not last_a.is_finite() or not last_b.is_finite():
		_brk_t = -1.0
		release()
		return
	var bc: Dictionary = cfg["break"]
	_brk_t = 0.0
	_brk_shooter = shooter
	_brk_a = last_a
	_brk_b = last_b
	var f := clampf(float(bc.get("at", 0.55)) + randf_range(-0.08, 0.08), 0.15, 0.85)
	_brk_p = last_a.lerp(last_b, f)
	if _hook_at == Vector3.INF:
		_hook_at = last_b
		_hook_from = last_a
	_hook_k = 1.0
	breaks += 1
	var fx = game.get("fx") if game != null else null
	if fx != null:
		var along := (last_b - last_a).normalized()
		if fx.has_method("clang_spark"):
			fx.clang_spark(_brk_p, along)
		if fx.has_method("mote"):
			# the tink: a white flash at the break and a wider pale one
			var tk := float(bc.get("tink", 1.1))
			fx.mote(_brk_p, Vector3.ZERO, 0.18, tk, Color(1.0, 1.0, 1.0, 1.0))
			fx.mote(_brk_p, Vector3.ZERO, 0.32, tk * 1.8, Color(0.85, 0.9, 1.0, 0.45))
		if fx.has_method("splinters") and int(bc.get("bits", 8)) > 0:
			var ch: Dictionary = cfg["chain"]
			fx.splinters(_brk_p - Vector3(0, 0.45, 0), Color.from_string(str(ch.get("colour", "#8A8A94")), Color(0.54, 0.54, 0.58)), int(bc.get("bits", 8)), 0.14)
	Audio.play(str(bc.get("sfx", "")), _brk_p)


## Whether a break is under way (its halves still falling).
func breaking() -> bool:
	return _brk_t >= 0.0


func _tick_break(delta: float) -> void:
	_brk_t += delta
	var bc: Dictionary = cfg["break"]
	var secs := maxf(float(bc.get("seconds", 0.9)), 0.1)
	var u := clampf(_brk_t / secs, 0.0, 1.0)
	if u >= 1.0 or _mm == null:
		_brk_t = -1.0
		_hook_k = 1.0
		release()
		return
	# the hand's end follows the harpooner while it lives
	var hand := hand_of(_brk_shooter, _brk_b)
	if not hand.is_finite():
		hand = _brk_a
	var whip := float(bc.get("whip", 0.55)) * exp(-_brk_t * 6.0) * sin(_brk_t * 32.0)
	var fade := 1.0 - smoothstep(0.6, 1.0, u)
	var d1 := 1.0 - minf(u * 2.2, 1.0)
	var drop := 1.0 - d1 * d1
	# the hand's half: its loose end springs back towards the hand and drops to the sand
	var end_a := _brk_p.lerp(hand, float(bc.get("recoil", 0.7)) * drop)
	end_a.y = lerpf(_brk_p.y, _ground(end_a) + 0.1, drop)
	# the hook's half: its loose end drops where it broke, the hook falls off the hero to his feet
	var start_b := _brk_p
	start_b.y = lerpf(_brk_p.y, _ground(_brk_p) + 0.1, drop)
	var hook := _hook_at
	var hook_down := Vector3(hook.x, _ground(hook) + 0.12, hook.z)
	var hf := minf(u * 1.8, 1.0)
	hook = hook.lerp(hook_down, hf * hf)
	_hook_k = fade
	# (a slack sag while they fall, none once they lie on the sand: a sag there would bury their middles)
	var sag := 0.08 * (1.0 - drop)
	var k := _lay(hand, end_a, sag, SLACK, 0, fade, whip, true)
	k = _lay(start_b, eye_of(hook, start_b), sag, SLACK, k, fade, -whip, false)
	_mm.visible_instance_count = k
	links_drawn = k
	if fade > 0.02:
		show_hook(hook, start_b)
	elif _hook != null:
		_hook.visible = false


func _ground(p: Vector3) -> float:
	var map = game.get("map") if game != null else null
	if map != null and map.has_method("height_at"):
		return map.height_at(p.x, p.z)
	return 0.0


## Drawn once under the spawn beam (pass 112, Warmup): a short chain with both turns of link and the hook at `at`, so the
## links' material, its outline pass and the hook's compile before the first throw (Vector3.INF = put away again).
func warm(at: Vector3) -> void:
	if _mm == null:
		return
	if at == Vector3.INF:
		_mm.visible_instance_count = 0
		if _hook != null:
			_hook.visible = false
		_hook_at = Vector3.INF
		links_drawn = 0
		return
	var k := _lay(at, at + Vector3(2.0, 0.0, 0.0), 0.0, SLACK, 0, 1.0, 0.0, true)
	_mm.visible_instance_count = k
	links_drawn = k
	show_hook(at + Vector3(2.4, 0.0, 0.0), at)

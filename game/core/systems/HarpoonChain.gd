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
## back to the hand), `release` (the rope ends: hidden). The numbers are the creature's `ranged.harpoon_fx` over DEFAULTS
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
## diagnostics and tests: links drawn on the last draw, launches, hook-ins, misses reeled, and the last draw's ends
var links_drawn := 0
var launches := 0
var hooks := 0
var reels := 0
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
	_clock += delta
	if _launch_t >= 0.0:
		_launch_t += delta
	if _snap_t >= 0.0:
		_snap_t += delta
		if _snap_t > 2.0:
			_snap_t = -1.0
	if _reel_t >= 0.0:
		_tick_reel(delta)


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
	var k := 0
	for j in range(n):
		var f := (float(j) + 0.5) * pitch / maxf(span, 0.001)
		var p := _point(a, b, f, s, side, wave, rattle, shud, span)
		var q := _point(a, b, minf(f + 0.02, 1.0), s, side, wave, rattle, shud, span)
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
	_mm.visible_instance_count = k
	links_drawn = k


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
	var hs := float(cfg.get("hook_scale", 1.3)) * ProjectileManager.CHUNK
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
	if _reel_t >= 0.0:
		return
	if _mm != null:
		_mm.visible_instance_count = 0
	if _hook != null:
		_hook.visible = false
	links_drawn = 0


## Whether a miss's reel is under way (Game leaves the chain to it).
func reeling() -> bool:
	return _reel_t >= 0.0

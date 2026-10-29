## Marshal's Star (pass 70, lane LINES, Tin Star's evolution): with the hero's `star_block_every` above 0 a gold star
## floats over his head while it is ready, and the next hit that would reach him (past the Invincibility power-up, the
## blink after a hit and an evade; before damage reduction and the Energy Shield) is blocked whole: no damage and no
## shove of its own (a blast's throw still carries him), BLOCK over him, a gold burst with sparks and the iron clang, and
## the usual blink after a hit (`hit_invuln`). The star then recharges for `star_block_every` seconds of the buffs' clock (Run.buff_clock, so a pause or a menu stops it) and
## pops back over his head. It starts ready. The Player makes one (Player._star_guard_sync) once the stat appears.
class_name StarGuard
extends Node3D

## Where the star floats over the hero's feet (m), how big (its outer radius, m), and its bob.
const HEAD_Y := 3.0
const RADIUS := 0.2
const BOB := 0.05
## The block's flare: the star swells to FLARE_SCALE and fades out over FLARE_TIME s.
const FLARE_TIME := 0.3
const FLARE_SCALE := 2.2
const GOLD := Color(1.0, 0.8, 0.22)
const RIM := Color(0.36, 0.2, 0.04)
const BURST := Color(1.0, 0.85, 0.35)
const SFX := "w_iron_hit"

## When the star is ready again (the buffs' clock); -INF: ready now.
var ready_at := -INF
## Hits blocked this run (tests, the capture).
var blocks := 0
var _star: MeshInstance3D
var _rim: MeshInstance3D
var _flare := 0.0
var _pop := 1.0
var _shown := false
var _t := 0.0


func _ready() -> void:
	_rim = _make_star(RADIUS * 1.22, RIM, 0)
	_star = _make_star(RADIUS, GOLD, 1)
	position = Vector3(0, HEAD_Y, 0)
	_show(is_ready(), false)


## The seconds between blocks the hero's sheet holds now (0 without the item).
static func every() -> float:
	var run := _run()
	var sheet = run.get("player_sheet") if run else null
	return maxf((sheet as StatSheet).get_stat("star_block_every", 0.0), 0.0) if sheet is StatSheet else 0.0


## Whether a star is ready to take the next hit.
func is_ready() -> bool:
	return every() > 0.0 and _clock() >= ready_at


## The block (Player.take_damage asks): true and the star spent when one was ready.
func try_block() -> bool:
	if not is_ready():
		return false
	ready_at = _clock() + every()
	blocks += 1
	var at := global_position if is_inside_tree() else position
	var game := _game()
	var fx = game.get("fx") if game else null
	if fx != null:
		if fx.has_method("burst"):
			fx.burst(at, BURST, 0.45)
		if fx.has_method("sun_sparks"):
			fx.sun_sparks(at, BURST, 7)
	var audio := _node("Audio")
	if audio:
		audio.call("play", SFX, at)
	# the star flares and fades where it was, then it is gone until it comes back
	_flare = FLARE_TIME
	_shown = false
	return true


## Seconds until the star is back (0 when it is ready or the item is not held).
func seconds_left() -> float:
	if every() <= 0.0:
		return 0.0
	return maxf(ready_at - _clock(), 0.0)


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt): the camera and what is on screen follow it
	delta = Lockstep.dt(delta)
	_t += delta
	if _flare > 0.0:
		_flare = maxf(_flare - delta, 0.0)
		var k := _flare / FLARE_TIME
		scale = Vector3.ONE * lerpf(FLARE_SCALE, 1.0, k * k)
		_set_alpha(k)
		if _flare <= 0.0:
			_set_alpha(1.0)
			_show(is_ready(), true)
		return
	var r := is_ready()
	if r != _shown:
		_show(r, true)
	if not _shown:
		return
	_pop = minf(_pop + delta * 3.5, 1.0)
	# a pop with a little overshoot as it comes back, then a slow breathing glint
	var s := _ease_pop(_pop) * (1.0 + 0.06 * sin(_t * 4.0))
	scale = Vector3.ONE * s
	position = Vector3(0, HEAD_Y + BOB * sin(_t * 2.6), 0)


func _show(on: bool, pop: bool) -> void:
	_shown = on
	visible = on
	_pop = 0.0 if (on and pop) else 1.0
	if not pop:
		scale = Vector3.ONE


func _set_alpha(a: float) -> void:
	for mi: MeshInstance3D in [_star, _rim]:
		if mi and mi.material_override is StandardMaterial3D:
			var m := mi.material_override as StandardMaterial3D
			m.albedo_color.a = clampf(a, 0.0, 1.0)


static func _ease_pop(p: float) -> float:
	# back-out: past 1 a little, then settles
	var c := 2.2
	var q := p - 1.0
	return 1.0 + (c + 1.0) * q * q * q + c * q * q


## A flat five-pointed star facing the camera (billboard), unshaded, drawn over the sprite.
func _make_star(r: float, col: Color, prio: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for k in range(10):
		var a := -PI * 0.5 + TAU * float(k) / 10.0
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(Vector3(cos(a) * rr, -sin(a) * rr, 0.0))
	for k in range(10):
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[k])
		st.add_vertex(pts[(k + 1) % 10])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# the node's scale carries the pop, the breathing and the flare
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 10 + prio
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _clock() -> float:
	var run := _run()
	return float(run.call("buff_clock")) if run and run.has_method("buff_clock") else 0.0


func _game() -> Node:
	var p := get_parent()
	var hops := 0
	while p != null and hops < 3:
		if "fx" in p:
			return p
		p = p.get_parent()
		hops += 1
	return null


static func _run() -> Node:
	return _node("Run")


static func _node(n: String) -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null(n) if ml is SceneTree else null

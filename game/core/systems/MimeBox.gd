## Pass 116 (lane FIGHT): May's second perk, Invisible Box (content/perks/invisible_box, `special` "box"). Garry: "display
## a transparent box with white outlines that she stands in, it slowly rotates and every hit is reflected on it,
## basically it functions like the Shield Power-up ... the box is over the power-up shield". After `first` s, then every
## `every` s, a see-through box rises round her for `seconds` s (Run.buff_seconds stretches it like every buff): while it
## stands every hit is blocked as the Shield power-up blocks it (Player.box_t: no damage, no shove), and each blocked hit
## flashes the box and sends a white ripple over the face it struck. No new animation on May: the box is its own node
## that follows her. With the Shield power-up's bubble up as well the box grows to stand round the bubble (BUBBLE_R plus a
## margin) and draws after it (render priority), so the outline reads over the bubble and the two never z-fight.
## Game._tick_box makes this node the first time a box perk is held; the clock runs on the game's lockstepped delta.
class_name MimeBox
extends Node3D

## the Shield power-up's bubble (Player.shield: a sphere of radius 1.35 centred 1.05 m up)
const BUBBLE_R := 1.35
const BUBBLE_Y := 1.05
const BUBBLE_MARGIN := 0.12
const EDGE := 0.045          # the outline's beam thickness (m)
const RISE := 0.25           # seconds the box takes to unfold, and to fold away
const FLASH_DECAY := 3.0     # a hit's flash fades over a third of a second
const RIPPLE_TIME := 0.4
const RIPPLE_MAX := 6
## drawn after the Shield bubble (its material sits at priority 0)
const PRIORITY := 10

var game: Node = null
var clock := -1.0            # seconds until the next box (-1: not started yet)
var up_t := 0.0              # seconds the box has left
var up_total := 0.0
var flash := 0.0
var _size := Vector3(2.0, 2.4, 2.0)
var _root: Node3D
var _faces: MeshInstance3D
var _face_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _edges: Array = []
var _ripples: Array = []     # {node, mat, t}
var _last_hits := 0
# for the tests and the captures
var shown := 0
var hits_blocked := 0


## A perk's box number (Run.perk_param by the mechanism), or `default`.
static func param(key: String, default: float) -> float:
	var run = Engine.get_main_loop().root.get_node_or_null("Run") if Engine.get_main_loop() else null
	return float(run.perk_param("box", key, default)) if run else default


## Whether the hero holds a perk whose special is "box".
static func active() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var run = tree.root.get_node_or_null("Run")
	var reg = tree.root.get_node_or_null("Registry")
	if run == null or reg == null:
		return false
	for pk in run.perks:
		var def = reg.perk(str(pk))
		if def and def.special == "box":
			return true
	return false


func setup(p_game: Node) -> void:
	game = p_game
	_build()


func _player() -> Node3D:
	return game.get("player") if game else null


## The box's size: its own (width, height) from the perk, or round the Shield bubble while that is up.
func box_size() -> Vector3:
	var w := param("width", 2.0)
	var h := param("height", 2.4)
	var p := _player()
	if p != null and float(p.get("shield_t")) > 0.0:
		# a cube round the sphere: half its width past the radius, its top over the bubble's top
		w = maxf(w, (BUBBLE_R + BUBBLE_MARGIN) * 2.0)
		h = maxf(h, BUBBLE_Y + BUBBLE_R + BUBBLE_MARGIN)
	return Vector3(w, h, w)


func is_up() -> bool:
	return up_t > 0.0


func tick(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	if up_t <= 0.0:
		if not active():
			clock = -1.0
			return
		if clock < 0.0:
			clock = param("first", 8.0)
		clock -= delta
		if clock <= 0.0 and not bool(p.get("dead")):
			raise_box()
	else:
		up_t = maxf(up_t - delta, 0.0)
		p.set("box_t", up_t)
		var hits := int(p.get("box_hits"))
		if hits > _last_hits:
			for k in range(mini(hits - _last_hits, 3)):
				_hit_fx(p.get("box_hit_from"))
			hits_blocked += hits - _last_hits
			_last_hits = hits
		if up_t <= 0.0:
			clock = param("every", 20.0)
	_draw(delta, p)


## Up it comes now (the clock, the tests and the captures).
func raise_box() -> void:
	var p := _player()
	if p == null:
		return
	var run = get_tree().root.get_node_or_null("Run")
	var secs := param("seconds", 3.0)
	if run and run.has_method("buff_seconds"):
		secs = float(run.buff_seconds(secs))
	up_t = secs
	up_total = secs
	p.set("box_t", up_t)
	_last_hits = int(p.get("box_hits"))
	shown += 1
	flash = 0.6
	var audio = get_tree().root.get_node_or_null("Audio")
	if audio:
		audio.play("pk_decoy_land", p.global_position)


func _draw(delta: float, p: Node3D) -> void:
	if up_t <= 0.0 and _root.visible and flash <= 0.0:
		_root.visible = false
	if up_t <= 0.0:
		return
	_root.visible = true
	global_position = p.global_position
	var target := box_size()
	_size = _size.lerp(target, clampf(delta * 8.0, 0.0, 1.0)) if _size.distance_to(target) > 0.01 else target
	# unfold over RISE, fold away over the last RISE
	var gone := up_total - up_t
	var k := clampf(minf(gone, up_t) / RISE, 0.0, 1.0)
	k = ease(k, 0.4)
	_root.scale = Vector3(_size.x, _size.y * k, _size.z) * (1.0 + 0.05 * flash)
	_root.rotation.y += delta * param("spin", 0.35)
	flash = maxf(flash - delta * FLASH_DECAY, 0.0)
	_face_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.1 + 0.3 * flash)
	_edge_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85 + 0.15 * flash).lerp(Color(0.75, 0.9, 1.0, 1.0), flash * 0.5)
	# the edges keep their thickness whatever the box's scale
	for e: MeshInstance3D in _edges:
		var axis: int = e.get_meta("axis")
		var s := Vector3(EDGE / maxf(_size.x, 0.01), EDGE / maxf(_size.y * k, 0.01), EDGE / maxf(_size.z, 0.01)) * (1.0 + flash)
		s[axis] = 1.0 + EDGE / maxf(_size[axis], 0.01)
		e.scale = s
	for r: Dictionary in _ripples:
		var n: MeshInstance3D = r["node"]
		if not n.visible:
			continue
		r["t"] = float(r["t"]) + delta
		var u := float(r["t"]) / RIPPLE_TIME
		if u >= 1.0:
			n.visible = false
			continue
		n.scale = Vector3.ONE * lerpf(0.15, 0.9, ease(u, 0.5))
		(r["mat"] as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.9 * (1.0 - u))


## A blocked hit: the box flashes and a ripple spreads over the face toward `from`.
func _hit_fx(from) -> void:
	flash = 1.0
	var p := _player()
	if p == null:
		return
	var d := Vector3.FORWARD
	if from is Vector3:
		d = (from as Vector3) - p.global_position
		d.y = 0.0
		if d.length_squared() < 0.0001:
			d = Vector3.FORWARD
	# into the box's own turning frame: the face whose normal is nearest the hit
	var local := _root.global_transform.basis.inverse() * d.normalized()
	var axis := 0 if absf(local.x) >= absf(local.z) else 2
	var sgn := signf(local[axis])
	var slot: Dictionary = {}
	for r: Dictionary in _ripples:
		if not (r["node"] as MeshInstance3D).visible:
			slot = r
			break
	if slot.is_empty():
		slot = _ripples[0]
	var n: MeshInstance3D = slot["node"]
	n.visible = true
	slot["t"] = 0.0
	n.position = Vector3(0.0, 0.5, 0.0)
	n.position[axis] = 0.5 * sgn + 0.002 * sgn
	n.rotation = Vector3(0.0, 0.0, PI * 0.5) if axis == 0 else Vector3(PI * 0.5, 0.0, 0.0)


func _material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, alpha)
	m.disable_fog = true
	m.render_priority = PRIORITY
	m.disable_receive_shadows = true
	return m


func _build() -> void:
	_root = Node3D.new()
	_root.name = "Box"
	add_child(_root)
	_root.visible = false
	# the faces: a unit box standing on the sand (0..1 up), seen through
	_face_mat = _material(0.1)
	_face_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_faces = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_faces.mesh = bm
	_faces.position = Vector3(0, 0.5, 0)
	_faces.material_override = _face_mat
	_faces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(_faces)
	# the twelve white edges
	_edge_mat = _material(0.95)
	_edge_mat.render_priority = PRIORITY + 1
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for axis in range(3):
		for a in [-0.5, 0.5]:
			for b in [-0.5, 0.5]:
				var e := MeshInstance3D.new()
				e.mesh = unit
				e.material_override = _edge_mat
				e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var at := Vector3.ZERO
				var o: Array = [0, 1, 2]
				o.erase(axis)
				at[o[0]] = a
				at[o[1]] = b
				at.y += 0.5
				e.position = at
				e.set_meta("axis", axis)
				_root.add_child(e)
				_edges.append(e)
	# the ripples a blocked hit sends over a face
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 32
	tm.ring_segments = 4
	for k in range(RIPPLE_MAX):
		var n := MeshInstance3D.new()
		n.mesh = tm
		var m := _material(0.9)
		m.render_priority = PRIORITY + 2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		n.material_override = m
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.visible = false
		_root.add_child(n)
		_ripples.append({"node": n, "mat": m, "t": 0.0})

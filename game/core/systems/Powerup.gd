## A pickup on the ground: its icon as a camera-facing sprite over a glowing ring, bobbing, blinking in its last
## seconds, gone when the hero walks into it (PickupManager checks the distance) or when its lifetime runs out.
class_name Powerup
extends Node3D

var def: PickupDef
var life := 20.0
var taken := false
var _t := 0.0
var _sprite: BillboardSprite
var _ring: MeshInstance3D
var _light: OmniLight3D
## whether the ring lies on the slope yet (pass 52: done on the first frame, once the pickup stands where it was dropped)
var _laid := false
## Pass 111 (lane CHEST; Garry: "The power ups don't immediately get claimed and used by the hero. They jump far enough
## out for it to be a conscious decision for the Player"): one thrown out of a chest (throw_to) is in the air on a hop
## until it lands (`flying`: never taken, its lifetime not running, its ring hidden), and never pulled by a magnet
## (`no_magnet`: a coin bag's own pull included; a vacuum never touched power-ups): the hero walks to it, or leaves it.
var flying := false
var no_magnet := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _fly_t := 0.0
var _fly_dur := 0.0
var _apex := 0.0
## The hop: THROW_TIME + THROW_TIME_PER_M x its length in the air, its top THROW_APEX + THROW_APEX_PER_M x its length
## over the line from the chest to where it lands (6 m: 0.76 s, 3.1 m up).
const THROW_TIME := 0.55
const THROW_TIME_PER_M := 0.035
const THROW_APEX := 1.8
const THROW_APEX_PER_M := 0.22


func setup(p_def: PickupDef) -> void:
	def = p_def
	life = maxf(def.lifetime, 5.0)


func _ready() -> void:
	var col := def.color if def else Color(1, 1, 1)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.8
	tm.rings = 24
	tm.ring_segments = 8
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(col.r, col.g, col.b, 0.75)
	_ring.material_override = rm
	_ring.position.y = 0.06
	_ring.scale = Vector3(1, 0.35, 1)
	add_child(_ring)
	_sprite = BillboardSprite.new()
	add_child(_sprite)
	var tex: Texture2D = def.icon if def and def.icon else PlaceholderArt.icon(def, 128)
	_sprite.setup(tex, {"idle": 1}, ["idle"], 1.15)
	_sprite.position.y = 0.35
	if Fx.want_lights():
		_light = OmniLight3D.new()
		_light.light_color = col
		_light.omni_range = 4.0
		_light.light_energy = 1.0
		_light.position.y = 1.0
		add_child(_light)
	scale = Vector3(0.01, 0.01, 0.01)
	var tw := create_tween()
	# the drop passives' cake slices and coin bags are small things underfoot, not power-ups on a plinth
	var size: float = 0.62 if (def and bool(def.params.get("small", false))) else 1.0
	tw.tween_property(self, "scale", Vector3.ONE * size, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if taken:
		return
	if flying:
		_fly(delta)
		return
	if not _laid:
		_lay_ring()
	_t += delta
	life -= delta
	_sprite.position.y = 0.35 + sin(_t * 2.6) * 0.12
	# it turns about the slope's up, not the world's
	_ring.rotate_object_local(Vector3.UP, delta * 1.2)
	var pulse := 1.0 + sin(_t * 4.0) * 0.06
	_ring.scale = Vector3(pulse, 0.35, pulse)
	# the last four seconds blink, so a pickup never just vanishes
	if life < 4.0:
		_sprite.visible = int(life * 5.0) % 2 == 0
	if life <= 0.0:
		queue_free()


## The ring lies on the sand under the pickup (pass 52, Garry: the power-up's ring "isn't always displayed correctly"): a
## level ring on a slope sank into the uphill side and stood off the downhill one; tilted to the ground's plane over its
## own width, it sits on it whole.
func _lay_ring() -> void:
	_laid = true
	var g = get_parent().get("game") if get_parent() else null
	var map = g.get("map") if g else null
	if map == null or not map.has_method("normal_at"):
		return
	var n: Vector3 = map.normal_at(global_position.x, global_position.z, 0.8)
	_ring.basis = MapBase.ground_basis(n)
	_ring.position = n * 0.06


## Thrown out of a chest (pass 111): from `from` (the chest) on a hop to `to` (on the sand), in the air until it lands.
func throw_to(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	var d := Vector2(to.x - from.x, to.z - from.z).length()
	_fly_dur = THROW_TIME + THROW_TIME_PER_M * d
	_apex = THROW_APEX + THROW_APEX_PER_M * d
	_fly_t = 0.0
	flying = true
	no_magnet = true
	if is_inside_tree():
		global_position = from
	if _ring:
		_ring.visible = false


## Where the hop has it `f` (0..1) of the way: along the line, a parabola `_apex` high over it.
func throw_point(f: float) -> Vector3:
	var p := _from.lerp(_to, clampf(f, 0.0, 1.0))
	p.y += 4.0 * _apex * f * (1.0 - f)
	return p


func _fly(delta: float) -> void:
	_fly_t += delta
	var f := clampf(_fly_t / maxf(_fly_dur, 0.01), 0.0, 1.0)
	global_position = throw_point(f)
	if _sprite:
		_sprite.position.y = 0.35
	if f < 1.0:
		return
	# down: it lies where it landed, its ring laid on the sand there, with a little squash
	flying = false
	global_position = _to
	_laid = false
	if _ring:
		_ring.visible = true
	var size: float = scale.x
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(size * 1.25, size * 0.75, size * 1.25), 0.07)
	tw.tween_property(self, "scale", Vector3.ONE * size, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func collect_anim() -> void:
	taken = true
	_sprite.visible = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sprite, "position:y", 1.6, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3(1.4, 1.4, 1.4), 0.3)
	if _light:
		tw.tween_property(_light, "light_energy", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)

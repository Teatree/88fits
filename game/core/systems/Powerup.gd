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
	# the drop passives' jerky and coin bags are small things underfoot, not power-ups on a plinth
	var size: float = 0.62 if (def and bool(def.params.get("small", false))) else 1.0
	tw.tween_property(self, "scale", Vector3.ONE * size, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if taken:
		return
	_t += delta
	life -= delta
	_sprite.position.y = 0.35 + sin(_t * 2.6) * 0.12
	_ring.rotation.y += delta * 1.2
	var pulse := 1.0 + sin(_t * 4.0) * 0.06
	_ring.scale = Vector3(pulse, 0.35, pulse)
	# the last four seconds blink, so a pickup never just vanishes
	if life < 4.0:
		_sprite.visible = int(life * 5.0) % 2 == 0
	if life <= 0.0:
		queue_free()


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

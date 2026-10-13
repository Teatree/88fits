## The portal that appears where a boss dies. Walking in asks: extract or continue (or not yet: pass 48, the hero who
## steps back out past REARM metres can walk in and be asked again).
## Painted like the scenery (pass 42): a sandstone moon gate (art/sprites/props/boss_portal.png, a billboard) with a green
## vortex turning in its round opening (the Teleport's swirl shader; where the opening is in the painting comes from
## boss_portal.json beside it, measured when tools/gen_ui_art.py installs the art). It rises out of the sand when it opens. The
## old green torus is only the stand-in for a build without the painting.
class_name Portal
extends Node3D

signal entered

const ART := "res://art/sprites/props/boss_portal.png"
const MANIFEST := "res://art/sprites/props/boss_portal.json"
const GREEN := Color(0.27, 0.83, 0.6)
## Walking in (within ENTER metres) asks; after a "Not yet" the portal waits for the hero to be REARM metres out before it
## asks again (pass 48), so the one who stands still in it is not asked every frame.
const ENTER := 1.5
const REARM := 2.5

var _t := 0.0
var armed := true
var _ring: MeshInstance3D
var _swirl: ShaderMaterial
var _body: Node3D
static var _cfg: Dictionary = {}


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var cfg := _entry()
	if ResourceLoader.exists(ART):
		# the painting's square is 1.15 x the gate's height, as for every structure
		var side := float(cfg.get("height", 3.6)) * 1.15
		var bs := BillboardSprite.new()
		# pass 72: scenery (a creature it hides is outlined, SceneryStencil)
		bs.scenery = true
		_body.add_child(bs)
		bs.setup(load(ART), {"idle": 1}, ["idle"], side)
		bs.position.y = 0.04
		_add_swirl(cfg.get("portal", {"x": 0.5, "y": 0.48, "r": 0.2}), side)
		# it rises out of the sand (the ground hides what is still under it)
		_body.position.y = -side
		var tw := create_tween()
		tw.tween_property(_body, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_stand_in()
	Audio.play("wd_portal_open", global_position)


## The painting's numbers: {height (m), portal {x, y (from the top), r}} as fractions of its square.
func _entry() -> Dictionary:
	if _cfg.is_empty() and FileAccess.file_exists(MANIFEST):
		var d = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if d is Dictionary:
			_cfg = d
	return _cfg


## The vortex in the round opening: standing up to the camera like the painting and a little behind it, so the stone
## covers its edge (as the Teleport's).
func _add_swirl(p: Dictionary, side: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	q.mesh = qm
	q.custom_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swirl = ShaderMaterial.new()
	_swirl.shader = preload("res://core/shaders/swirl.gdshader")
	_swirl.set_shader_parameter("billboard", 1.0)
	_swirl.set_shader_parameter("size", 2.0 * float(p.get("r", 0.2)) * side * 1.08)
	_swirl.set_shader_parameter("lift", (1.0 - float(p.get("y", 0.48))) * side + 0.04)
	_swirl.set_shader_parameter("shift", (float(p.get("x", 0.5)) - 0.5) * side)
	_swirl.set_shader_parameter("push", 0.08)
	_swirl.set_shader_parameter("color_a", Color(0.05, 0.3, 0.18, 0.9))
	_swirl.set_shader_parameter("color_b", Color(GREEN.r, GREEN.g, GREEN.b, 0.95))
	_swirl.set_shader_parameter("color_eye", Color(0.9, 1.0, 0.92, 0.95))
	_swirl.set_shader_parameter("eye", 0.24)
	_swirl.set_shader_parameter("arms", 4.0)
	_swirl.set_shader_parameter("twist", 1.6)
	_swirl.set_shader_parameter("speed", 2.6)
	q.material_override = _swirl
	_body.add_child(q)


## The feel test's ring, for a build without the painting.
func _stand_in() -> void:
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.4
	t.outer_radius = 1.8
	_ring.mesh = t
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GREEN
	mat.emission_enabled = true
	mat.emission = GREEN
	mat.emission_energy_multiplier = 1.5
	_ring.material_override = mat
	_ring.position.y = 2.0
	_ring.rotation.x = PI * 0.5
	_body.add_child(_ring)
	scale = Vector3(0.05, 0.05, 0.05)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	if _swirl:
		# it breathes while it waits
		_swirl.set_shader_parameter("energy", 1.1 + 0.15 * sin(_t * 3.0))
	elif _ring:
		_ring.rotation.z += delta * 1.2
		_ring.position.y = 2.0 + sin(_t * 2.0) * 0.15


func check_player(p: Node3D) -> void:
	var d := p.global_position - global_position
	d.y = 0.0
	if not armed:
		if d.length() > REARM:
			armed = true
		return
	if d.length() < ENTER:
		armed = false
		entered.emit()

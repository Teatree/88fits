## The hero's health bar, in the world under the feet instead of projected from the HUD, so it moves with the sprite
## in the same frame and never trails it. Two camera-facing quads drawn on top of everything.
class_name HealthBar3D
extends Node3D

const WIDTH := 1.5
const HEIGHT := 0.14

var _bg: MeshInstance3D
var _fg: MeshInstance3D
var _fg_mat: StandardMaterial3D
var _frac := 1.0


func _ready() -> void:
	_bg = _quad(Color(0, 0, 0, 0.55), 1)
	_fg = _quad(UiKit.GOOD, 2)
	_fg_mat = _fg.material_override
	position = Vector3(0, 0.12, 0.55)
	set_fraction(1.0)


func _quad(color: Color, priority: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(WIDTH, HEIGHT)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.render_priority = priority
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func set_fraction(f: float) -> void:
	_frac = clampf(f, 0.0, 1.0)
	# the fill shrinks from the right: scale about the left edge by offsetting along the billboard's local x
	_fg.scale = Vector3(maxf(_frac, 0.001), 1.0, 1.0)
	_fg.position = Vector3(-WIDTH * 0.5 * (1.0 - _frac), 0.0, 0.0)
	_fg_mat.albedo_color = UiKit.GOOD if _frac > 0.35 else UiKit.DANGER

## One sprite-strip quad that always faces the camera with its feet on the ground (core/shaders/sprite_billboard).
## Plays the animations of a content strip (idle, run, hit, die, cheer ...) from an `anims` dictionary and
## exposes lean, squash, flash and tint for juice. The player uses it; enemies use the MultiMesh twin.
class_name BillboardSprite
extends MeshInstance3D

signal animation_finished(anim: String)

const SPEEDS := {"idle": 4.0, "run": 14.0, "turn": 8.0, "attack": 6.0, "hit": 6.0, "die": 5.0, "cheer": 4.0}
const LOOPS := ["idle", "run", "turn", "attack"]

var animation := ""
var frame := 0.0
var playing := false
var _anims: Dictionary = {}   # name -> {"offset": int, "count": int}
var _fps: Dictionary = {}     # prefix -> frames per second, from the content def
var _total := 1
var _mat: ShaderMaterial
var _sil: ShaderMaterial
## The hero wants an outline where props hide him; pickups and the like do not.
var outline_when_hidden := false


func _ready() -> void:
	_ensure()


func _ensure() -> void:
	if _mat != null:
		return
	if mesh == null:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mesh = q
	custom_aabb = AABB(Vector3(-2.5, -0.5, -2.5), Vector3(5.0, 5.0, 5.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://core/shaders/sprite_billboard.gdshader")
	material_override = _mat
	if outline_when_hidden:
		enable_outline()


## The occluded pass: the same uniforms, drawn only where a prop hides the sprite. Call before setup().
func enable_outline() -> void:
	_ensure()
	if _sil:
		return
	outline_when_hidden = true
	_sil = ShaderMaterial.new()
	_sil.shader = load("res://core/shaders/sprite_silhouette.gdshader")
	_mat.next_pass = _sil


func _param(key: String, value: Variant) -> void:
	_mat.set_shader_parameter(key, value)
	if _sil:
		_sil.set_shader_parameter(key, value)


func setup(tex: Texture2D, anims: Dictionary, order: Array, height_m: float, cols: int = 0, fps: Dictionary = {}) -> void:
	_ensure()
	_anims.clear()
	_fps = fps
	var k := 0
	for a in order:
		var n := int(anims.get(a, 0))
		if n > 0:
			_anims[a] = {"offset": k, "count": n}
			k += n
	_total = maxi(k, 1)
	_param("sprite", tex)
	_param("frames", float(_total))
	_param("cols", float(cols))
	_param("rows", float(ceili(float(_total) / float(cols))) if cols > 0 else 1.0)
	_param("height", height_m)
	animation = ""
	play("idle")


func has_animation(anim: String) -> bool:
	return _anims.has(anim)


func play(anim: String) -> void:
	if not _anims.has(anim):
		if _anims.is_empty():
			return
		anim = _anims.keys()[0]
	if animation == anim and playing:
		return
	animation = anim
	frame = 0.0
	playing = true
	_apply()


func _process(delta: float) -> void:
	if not playing or not _anims.has(animation):
		return
	var n := int(_anims[animation]["count"])
	frame += delta * _speed(animation)
	if frame >= n:
		if _loops(animation):
			frame = fmod(frame, float(n))
		else:
			frame = float(n - 1)
			playing = false
			animation_finished.emit(animation)
	_apply()


func _speed(anim: String) -> float:
	for k in _fps.keys():
		if anim.begins_with(str(k)):
			return float(_fps[k])
	for k in SPEEDS.keys():
		if anim.begins_with(k):
			return float(SPEEDS[k])
	return 6.0


func _loops(anim: String) -> bool:
	for k in LOOPS:
		if anim.begins_with(k):
			return true
	return false


func _apply() -> void:
	if not _anims.has(animation):
		return
	_param("frame", float(int(_anims[animation]["offset"]) + int(frame)))


func set_flip(f: bool) -> void:
	_param("flip", 1.0 if f else 0.0)


func set_flash(v: float) -> void:
	_param("flash", clampf(v, 0.0, 1.0))


func set_squash(sx: float, sy: float) -> void:
	_param("stretch", sx)
	_param("squash", sy)


func set_roll(rad: float) -> void:
	_param("roll", rad)


func set_tint(c: Color) -> void:
	_param("tint", c)


func set_height(h: float) -> void:
	_param("height", h)

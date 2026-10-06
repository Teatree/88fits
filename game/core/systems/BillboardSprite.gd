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
var _over: ShaderMaterial
## The hero wants an outline where props hide him; pickups and the like do not.
var outline_when_hidden := false
## The see-through queue's place of the hero's second pass (pass 49, enable_over_trails): after his speed trails
## (Fx.SPEED_TRAIL_PRIORITY), before every other effect (0).
const OVER_PRIORITY := -1
## The water the second pass leaves out (pass 56, set_water): x and z the disc's centre, y its top face, w its radius
## (0 = no water), and how far its rim reaches under the top face. Kept here so a pass made later gets it too.
var _water := Vector4(0.0, -1000.0, 0.0, 0.0)
var _water_thick := 0.0


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
	if _over:
		_sil.next_pass = _over


## The painting drawn once more over the hero's speed trails (pass 49, Garry: "the speed up trail should be rendered
## underneath the 2.5d sprite of the hero"; core/shaders/sprite_billboard_over): the same quad and frame in the see-through
## queue at OVER_PRIORITY, a hair towards the camera, so a trail running between him and the camera goes under him while
## anything really in front of him still hides him. Call before setup().
func enable_over_trails() -> void:
	_ensure()
	if _over:
		return
	_over = ShaderMaterial.new()
	_over.shader = load("res://core/shaders/sprite_billboard_over.gdshader")
	_over.render_priority = OVER_PRIORITY
	if _water.w > 0.0:
		_apply_water()
	# after the outline pass when there is one (where a prop hides him the depth test drops this one anyway)
	if _sil:
		_sil.next_pass = _over
	else:
		_mat.next_pass = _over


## The water he wades in (pass 56, Garry: "Hero for some reason walks on water ... Should be submerged like all the
## enemies"): the second pass (enable_over_trails) is drawn after the see-through oasis and painted his whole figure over
## it, so it leaves out what the water's disc covers on his first pass (core/shaders/sprite_billboard_over), and the
## water tints him there as it tints a creature. `center` is the disc's middle (x, z), `top` its top face's height,
## `radius` its radius, `thick` how far its rim reaches under the top. Only the second pass gets it: his first pass, his
## outline and every creature are drawn as before. Game._sink_hero hands it over while he is near the water.
func set_water(center: Vector2, top: float, radius: float, thick: float) -> void:
	var w := Vector4(center.x, top, center.y, maxf(radius, 0.0))
	if w == _water and thick == _water_thick:
		return
	_water = w
	_water_thick = thick
	_apply_water()


## No water for the second pass (away from the lake, or a map without one): his whole painting again.
func clear_water() -> void:
	set_water(Vector2.ZERO, -1000.0, 0.0, 0.0)


## Whether the second pass has a water disc to leave out now (pass 56).
func has_water() -> bool:
	return _water.w > 0.0


## The disc the second pass leaves out (pass 56): x and z its centre, y its top face, w its radius (0 = none).
func water() -> Vector4:
	return _water


func _apply_water() -> void:
	if _over:
		_over.set_shader_parameter("water", _water)
		_over.set_shader_parameter("water_thick", _water_thick)


## The second pass's water test in GDScript (pass 56; the shader's fragment does the same per pixel, here for tests and
## tools): whether the water's `disc` (x, z centre, y top face, w radius) with a rim `thick` deep covers `point` seen
## from `camera`, so the pass leaves that point out and the water tints his first pass there.
static func water_covers(point: Vector3, camera: Vector3, disc: Vector4, thick: float) -> bool:
	if disc.w <= 0.0 or point.y >= disc.y:
		return false
	var drop := camera.y - point.y
	if drop <= 0.0001:
		return false
	var cam := Vector2(camera.x, camera.z)
	var run := Vector2(point.x, point.z) - cam
	var c := Vector2(disc.x, disc.z)
	var at_top := cam + run * ((camera.y - disc.y) / drop)
	var at_rim := cam + run * ((camera.y - maxf(point.y, disc.y - thick)) / drop)
	return at_top.distance_to(c) < disc.w or at_rim.distance_to(c) < disc.w


func _param(key: String, value: Variant) -> void:
	_mat.set_shader_parameter(key, value)
	if _sil:
		_sil.set_shader_parameter(key, value)
	if _over:
		_over.set_shader_parameter(key, value)


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


## Swaps the painting and keeps the frame layout (a structure's spent version).
func set_texture(tex: Texture2D) -> void:
	_param("sprite", tex)

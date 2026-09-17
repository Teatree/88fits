## The hero. Floating joystick: he runs where the thumb points (relative to the camera) and faces that way.
## The sprite is a camera-facing billboard strip with back, back-diagonal, side, front-diagonal and front views
## (idle/run each; diagonals and side mirrored for the other half), picked from the direction of travel relative
## to the camera, plus hit, die and cheer. Leans into turns.
class_name Player
extends CharacterBody3D

signal died
signal damaged(hp: float, max_hp: float)
signal hit
signal jumped
signal landed
signal lifted_thumb
signal moved_first

const RADIUS := 0.45

@onready var input: PlayerInput = $Input
@onready var sprite: BillboardSprite = $Sprite
@onready var shadow: MeshInstance3D = $Shadow
@onready var muzzle: Marker3D = $Muzzle
@onready var hip: Marker3D = $Hip
var health_bar: HealthBar3D
@onready var ring: MeshInstance3D = $MagnetRing

var sheet: StatSheet
var facing := 0.0               # yaw radians, 0 = -Z forward
var hp := 100.0
var max_hp := 100.0
var invuln := 0.0
var dead := false
var god := false
var cannot_stop := false
var was_on_floor := true
var distance_moved := 0.0
var _kb := Vector3.ZERO
var _bob := 0.0
var _tilt := 0.0
var _flash := 0.0
var _regen_acc := 0.0
var _step_timer := 0.0
var _moved_emitted := false
var _hit_pose := 0.0
var shield_t := 0.0
var _view := ""          # "" back, "_f" front, "_s" side
var _flip := false
var character: CharacterDef
var camera_yaw_fn: Callable = Callable()


func _ready() -> void:
	sheet = Run.player_sheet
	input.touch_ended.connect(func(): lifted_thumb.emit())
	_setup_sprite()
	health_bar = HealthBar3D.new()
	add_child(health_bar)
	_setup_shadow()
	refresh_stats()
	hp = max_hp


func setup(p_char: CharacterDef) -> void:
	character = p_char
	cannot_stop = p_char != null and p_char.specials.has("cannot_stop")
	if is_inside_tree():
		_setup_sprite()


func refresh_stats() -> void:
	sheet = Run.player_sheet
	var new_max := sheet.get_stat("max_hp", 100.0)
	if new_max != max_hp:
		var ratio: float = hp / max_hp if max_hp > 0.0 else 1.0
		max_hp = new_max
		hp = clamp(new_max * ratio, 1.0, new_max)
	damaged.emit(hp, max_hp)


func _setup_sprite() -> void:
	var tex: Texture2D = character.sprite if character and character.sprite else null
	var anims: Dictionary = character.anims if character else {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
	var fpx: int = character.frame_px if character else 256
	if tex == null:
		tex = PlaceholderArt.character_strip(character)
	var cols: int = character.strip_cols if character and character.sprite else 0
	var fps: Dictionary = character.fps if character and character.sprite else {}
	sprite.enable_outline()
	sprite.setup(tex, anims, ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"], 1.9, cols, fps)
	sprite.position = Vector3(0, 0.0, 0)


func _setup_shadow() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/shaders/blob_shadow.gdshader")
	shadow.material_override = mat
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.54, 0.41, 0.95, 0.0)
	ring.material_override = rm
	ring.visible = false


func show_magnet_ring(seconds := 2.0) -> void:
	var r := sheet.get_stat("magnet", 1.5)
	var t := ring.mesh as TorusMesh
	if t:
		t.outer_radius = r
		t.inner_radius = max(r - 0.08, 0.05)
	ring.visible = true
	var mat := ring.material_override as StandardMaterial3D
	mat.albedo_color.a = 0.6
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, seconds)
	tw.tween_callback(func(): ring.visible = false)


func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))


## Where a shot leaves the hero when aimed along `dir`: chest height, half a metre out.
func aim_origin(dir: Vector3) -> Vector3:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		d = forward()
	return global_position + Vector3(0, 0.8, 0) + d.normalized() * 0.5


func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	if dead:
		# only gravity: whatever he was doing when he fell stops with him
		velocity.x = 0.0
		velocity.z = 0.0
		_kb = Vector3.ZERO
		velocity.y -= 24.0 * delta
		move_and_slide()
		Perf.add("player", _t0)
		return
	invuln = max(invuln - delta, 0.0)
	if shield_t > 0.0:
		shield_t = maxf(shield_t - delta, 0.0)
		if shield_t <= 0.0:
			sprite.set_tint(Color(1, 1, 1))
	_flash = max(_flash - delta * 5.0, 0.0)
	_hit_pose = max(_hit_pose - delta, 0.0)
	var move_speed := sheet.get_stat("move_speed", 5.0)
	var planar := Vector3.ZERO
	var prev_facing := facing
	if input.wants_move and input.stick_dir.length() > 0.02:
		var cam_yaw: float = camera_yaw_fn.call() if camera_yaw_fn.is_valid() else facing
		var d := input.stick_dir
		var world := Vector3(d.x, 0, d.y).rotated(Vector3.UP, cam_yaw)
		var target_yaw := atan2(-world.x, -world.z)
		facing = lerp_angle(facing, target_yaw, clampf(delta * 22.0, 0.0, 1.0))
		# gentle nudges creep, past half deflection it is full speed: precise in a crowd, fast in the open
		var throttle := smoothstep(0.0, 0.55, d.length())
		planar = world.normalized() * move_speed * throttle
	elif cannot_stop:
		planar = forward() * move_speed
	rotation.y = facing
	var dyaw := angle_difference(prev_facing, facing) / maxf(delta, 0.001)
	_tilt = lerpf(_tilt, clampf(dyaw / 9.0, -1.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0
	velocity.x = planar.x + _kb.x
	velocity.z = planar.z + _kb.z
	_kb = _kb.lerp(Vector3.ZERO, delta * 6.0)
	var before := global_position
	move_and_slide()
	var stepped := (global_position - before)
	stepped.y = 0.0
	distance_moved += stepped.length()
	if distance_moved > 5.0 and not _moved_emitted:
		_moved_emitted = true
		moved_first.emit()
	var on_floor := is_on_floor()
	if on_floor and not was_on_floor:
		landed.emit()
		Audio.play("pl_land", global_position)
	was_on_floor = on_floor
	# regen
	var regen := sheet.get_stat("regen", 0.0)
	if regen > 0.0 and hp < max_hp:
		hp = min(hp + regen * delta, max_hp)
		damaged.emit(hp, max_hp)
	_animate(delta, planar.length() > 0.1, on_floor)
	if planar.length() > 0.1 and on_floor:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.28
			var step: String = str(Run.map.music.get("step", "pl_step_sand")) if Run.map else "pl_step_sand"
			Audio.play(step, global_position)
	Perf.add("player", _t0)


func _animate(delta: float, moving: bool, on_floor: bool) -> void:
	# which side of the hero the camera sees, in eight sectors: back, back-diagonal, side, front-diagonal, front
	if moving:
		var cam_yaw: float = camera_yaw_fn.call() if camera_yaw_fn.is_valid() else 0.0
		var rel := angle_difference(cam_yaw, facing)
		var a := absf(rel)
		if a < PI * 0.125:
			_view = ""
		elif a < PI * 0.375:
			_view = "_bd"
		elif a < PI * 0.625:
			_view = "_s"
		elif a < PI * 0.875:
			_view = "_fd"
		else:
			_view = "_f"
		_flip = rel > 0.0     # the rendered side and diagonal views face screen-right; mirror them when running left
	var anim := _anim_for("hit" if _hit_pose > 0.0 else ("run" if moving else "idle"))
	if sprite.animation != anim and sprite.has_animation(anim):
		sprite.play(anim)
	sprite.set_flip(_flip and _view in ["_s", "_bd", "_fd"])
	_bob = _bob + delta * (10.0 if moving else 3.0)
	var bob := sin(_bob) * (0.03 if moving else 0.015)
	var jump_stretch := 0.0 if on_floor else 0.12
	sprite.set_squash(1.0 - jump_stretch * 0.5, 1.0 + bob * 0.5 + jump_stretch)
	sprite.set_roll(-_tilt * 0.14)
	sprite.set_flash(_flash)
	if invuln > 0.0 and not god:
		sprite.visible = int(invuln * 20.0) % 2 == 0
	else:
		sprite.visible = true
	var s := 0.9 + (0.0 if on_floor else 0.2)
	shadow.scale = Vector3(s, 1, s * 0.7)


func launch(v: Vector3) -> void:
	velocity.y = v.y
	_kb += Vector3(v.x, 0, v.z)
	jumped.emit()
	Audio.play("pl_jump", global_position)


func apply_knockback(v: Vector3) -> void:
	_kb += v


func heal(amount: float) -> void:
	if dead:
		return
	hp = minf(hp + amount, max_hp)
	damaged.emit(hp, max_hp)


## A shield: no damage for `seconds`, the sprite tinted blue while it holds.
func shield(seconds: float) -> void:
	shield_t = maxf(shield_t, seconds)
	sprite.set_tint(Color(0.72, 0.9, 1.0))
	show_magnet_ring(seconds)


func take_damage(amount: float, from: Vector3) -> void:
	if dead or god or invuln > 0.0 or shield_t > 0.0:
		return
	var armor := sheet.get_stat("armor", 0.0)
	var dealt: float = max(amount - armor, amount * 0.2)
	hp -= dealt
	invuln = 0.35
	_flash = 1.0
	# a strip with a real flinch plays it through; the single squashed frame shows for a blink
	var hit_frames: int = int(character.anims.get("hit", 1)) if character else 1
	var hit_fps: float = float(character.fps.get("hit", 20.0)) if character else 20.0
	_hit_pose = float(hit_frames) / maxf(hit_fps, 1.0) if hit_frames > 1 else 0.15
	hit.emit()
	var away := global_position - from
	away.y = 0.0
	apply_knockback(away.normalized() * 2.5)
	Audio.play("pl_hurt", global_position)
	damaged.emit(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		_die()


## The strip may lack some views (older art): fall back along the nearest available direction.
func _anim_for(base: String) -> String:
	var chain: Array = {"": [""], "_bd": ["_bd", "_s", ""], "_s": ["_s", "_bd", "_fd", ""], "_fd": ["_fd", "_s", "_f"], "_f": ["_f", "_fd", ""]}.get(_view, [""])
	for suffix in chain:
		if sprite.has_animation(base + suffix):
			return base + suffix
	return base


func _die() -> void:
	dead = true
	velocity = Vector3.ZERO
	_kb = Vector3.ZERO
	sprite.set_squash(1.0, 1.0)
	sprite.set_roll(0.0)
	sprite.set_flash(0.0)
	sprite.visible = true
	sprite.play("die")
	Audio.play("pl_death")
	died.emit()


func revive() -> void:
	dead = false
	hp = max_hp * 0.6
	invuln = 2.0
	sprite.play("idle")
	Audio.play("pl_revive")
	damaged.emit(hp, max_hp)


func cheer() -> void:
	if sprite.has_animation("cheer"):
		sprite.play("cheer")
	input.enabled = false

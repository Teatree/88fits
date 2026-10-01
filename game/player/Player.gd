## The hero. Floating joystick: he runs where the thumb points (relative to the camera) and faces that way.
## The sprite is a camera-facing billboard strip with back, back-diagonal, side, front-diagonal and front views
## (idle/run each; diagonals and side mirrored for the other half), picked from the direction of travel relative
## to the camera, plus hit, die and cheer. Leans into turns.
class_name Player
extends CharacterBody3D

signal died
signal damaged(hp: float, max_hp: float)
signal hit
signal momentum_trail(at: Vector3, back: Vector3, strength: float)   # Buck's dust and streaks (Game feeds it to Fx)
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
@onready var ring: MeshInstance3D = $MagnetRing

var sheet: StatSheet
var facing := 0.0               # yaw radians, 0 = -Z forward
var hp := 100.0
var max_hp := 100.0
var invuln := 0.0
var momentum := false     # Buck: speed and might climb while unhurt (CharacterDef.momentum)
var _momentum_t := 0.0
var _momentum_sync := 0.0
var _trail_t := 0.0
var dead := false
var god := false
var cannot_stop := false
var was_on_floor := true
var distance_moved := 0.0
var _kb := Vector3.ZERO
## the harpoon's rope (pass 33.10, Game sets these while it holds him): walking towards `tether_from` is free, walking
## straight away from it runs at `tether_away` of his speed (sideways in between), and the rope drags the thrower along
var tethered := false
var tether_from := Vector3.ZERO
var tether_away := 0.7
var _bob := 0.0
var _tilt := 0.0
var _flash := 0.0
var _regen_acc := 0.0
## seconds of regen held off after taking a hit: healing is for the gap between fights, not for standing in one
var regen_hold := 0.0
const REGEN_HOLD_AFTER_HIT := 3.0
## The last 30 s of hits for the death screen (pass 33.2): {t, by, kind, fx, raw, dealt, shield, note, hp, fatal}
var damage_log: Array = []
const LOG_SECONDS := 30.0
## The Energy Shield line: points that take whole hits while any are left, back once he goes shield_delay untouched
var shield_pts := 0.0
var _shield_wait := 0.0
signal evaded
signal shield_hit(broke: bool)
var _step_timer := 0.0
var _moved_emitted := false
var _hit_pose := 0.0
var shield_t := 0.0
var _shield_node: MeshInstance3D
var _shield_mat: ShaderMaterial
var _shield_hit := 0.0
var _view := ""          # "" back, "_f" front, "_s" side
var _flip := false
var character: CharacterDef
var camera_yaw_fn: Callable = Callable()


func _ready() -> void:
	sheet = Run.player_sheet
	input.touch_ended.connect(func(): lifted_thumb.emit())
	_setup_sprite()
	_setup_shadow()
	refresh_stats()
	hp = max_hp


func setup(p_char: CharacterDef) -> void:
	character = p_char
	cannot_stop = p_char != null and p_char.specials.has("cannot_stop")
	momentum = p_char != null and p_char.specials.has("momentum")
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
	_knock_grace = maxf(_knock_grace - delta, 0.0)
	if momentum and not dead:
		_tick_momentum(delta)
	if shield_t > 0.0:
		shield_t = maxf(shield_t - delta, 0.0)
		if shield_t <= 0.0:
			sprite.set_tint(Color(1, 1, 1))
			if _shield_node:
				_shield_node.visible = false
	if _shield_node and _shield_node.visible:
		# the sphere breathes, spins slowly, fades in its last second and flashes when it takes a hit
		_shield_hit = maxf(_shield_hit - delta * 4.0, 0.0)
		_shield_node.rotation.y += delta * 0.7
		_shield_node.scale = Vector3.ONE * (1.0 + 0.03 * sin(Time.get_ticks_msec() * 0.006))
		_shield_mat.set_shader_parameter("strength", clampf(shield_t / 1.0, 0.25, 1.0))
		_shield_mat.set_shader_parameter("hit", _shield_hit)
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
		planar = world.normalized() * move_speed * throttle * leash_factor(world)
	elif cannot_stop:
		planar = forward() * move_speed * leash_factor(forward())
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
	# regen: held for a few seconds after every hit, so a fight is won by not being hit, not by out-ticking the crowd
	regen_hold = maxf(regen_hold - delta, 0.0)
	var regen := sheet.get_stat("regen", 0.0)
	if regen > 0.0 and hp < max_hp and regen_hold <= 0.0:
		hp = min(hp + regen * delta, max_hp)
		damaged.emit(hp, max_hp)
	# the Energy Shield: back up once he has gone shield_delay without a hit, shield_rate of it a second
	var smax := sheet.get_stat("shield_max", 0.0)
	if smax > 0.0:
		_shield_wait = maxf(_shield_wait - delta, 0.0)
		if _shield_wait <= 0.0 and shield_pts < smax:
			shield_pts = minf(shield_pts + smax * sheet.get_stat("shield_rate", 0.5) * delta, smax)
		shield_pts = minf(shield_pts, smax)
	elif shield_pts > 0.0:
		shield_pts = 0.0
	_animate(delta, planar.length() > 0.1, on_floor)
	if planar.length() > 0.1 and on_floor:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.28
			var step: String = str(Run.map.music.get("step", "pl_step_sand")) if Run.map else "pl_step_sand"
			Audio.play(step, global_position)
	Perf.add("player", _t0)


func _animate(delta: float, moving: bool, on_floor: bool) -> void:
	# momentum shows on the ground: puffs at the heels as it builds, streaks behind him near full
	if momentum and moving and on_floor and Run.momentum > 0.15:
		_trail_t -= delta
		if _trail_t <= 0.0:
			_trail_t = lerpf(0.16, 0.035, Run.momentum)
			momentum_trail.emit(global_position, -forward(), Run.momentum)
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


## A shove from a creature (a shotgun blast, a spike, a charge, a blast). One lands, then the hero is immune to the
## next for `KNOCK_GRACE`: three shoves in the same instant used to stack into a launch across the arena, and a crowd
## could pin him in the air. The hero's own knockback (a harpoon rope, a tornado) goes through `apply_knockback`.
const KNOCK_GRACE := 1.0
var _knock_grace := 0.0
## what the last take_damage came to: "hit", "shield", "evaded", "immune" or "none" (a blast reads it: an evade
## leaves him standing)
var last_outcome := "none"


func shove(v: Vector3) -> bool:
	if _knock_grace > 0.0 or dead:
		return false
	_knock_grace = KNOCK_GRACE
	# whatever the source, the shove itself is bounded: the physics never sees a metre a frame
	var f: float = minf(v.length(), 14.0)
	if f > 0.01:
		_kb += v.normalized() * f
	return true


func apply_knockback(v: Vector3) -> void:
	_kb += v


## A blast throws him (pass 33.3, the rocketeer's rocket): past the shove's cap and its grace, `up` metres a second off
## the ground with it, and the grace starts again so no shove stacks on top while he flies.
func blast(v: Vector3, up: float = 0.0) -> void:
	if dead:
		return
	_knock_grace = KNOCK_GRACE
	_kb += Vector3(v.x, 0, v.z)
	if up > 0.0:
		velocity.y = maxf(velocity.y, up)


## Buck's momentum: climbs to full over ramp_seconds while he is not hit, resets to nothing on a hit. Applied to the
## sheet a few times a second so the stats screen and the speed follow it.
func _tick_momentum(delta: float) -> void:
	var ramp: float = float(Run.momentum_def.get("ramp_seconds", 12.0))
	_momentum_t = minf(_momentum_t + delta, ramp)
	var f := _momentum_t / maxf(ramp, 0.1)
	_momentum_sync -= delta
	if _momentum_sync <= 0.0 and absf(f - Run.momentum) > 0.02:
		_momentum_sync = 0.25
		Run.momentum = f
		Run.rebuild_sheets()


func heal(amount: float) -> void:
	if dead:
		return
	hp = minf(hp + amount, max_hp)
	damaged.emit(hp, max_hp)


## A shield: no damage for `seconds`, the sprite tinted blue while it holds.
func shield(seconds: float) -> void:
	shield_t = maxf(shield_t, seconds)
	sprite.set_tint(Color(0.72, 0.9, 1.0))
	if _shield_node == null:
		# a hollow holographic sphere that covers the whole hero (core/shaders/holo_shield.gdshader)
		_shield_node = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.35
		sm.height = 2.7
		sm.radial_segments = 32
		sm.rings = 16
		_shield_node.mesh = sm
		_shield_mat = ShaderMaterial.new()
		_shield_mat.shader = load("res://core/shaders/holo_shield.gdshader")
		_shield_node.material_override = _shield_mat
		_shield_node.position = Vector3(0, 1.05, 0)
		_shield_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shield_node)
	_shield_node.visible = true
	_shield_node.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(_shield_node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shield_hit = 1.0


## `info` says who hit him and how, for the death screen's log: {"by", "kind" (melee, ranged, boss), "fx": [...]}.
func take_damage(amount: float, from: Vector3, info: Dictionary = {}) -> void:
	last_outcome = "none"
	if dead:
		return
	if shield_t > 0.0:
		# the shield power-up takes it: a flash on the sphere, nothing on the hero
		_shield_hit = 1.0
		_log_hit(amount, 0.0, 0.0, info, "power-up")
		last_outcome = "shield"
		return
	if god or invuln > 0.0:
		last_outcome = "immune"
		return
	# Evade: a clean miss, no damage and no shove; Ghost Step leaves him untouchable a moment after it
	var ev := sheet.get_stat("evade", 0.0)
	if ev > 0.0 and randf() < minf(ev, 0.9):
		invuln = maxf(invuln, sheet.get_stat("evade_invuln", 0.0))
		_log_hit(amount, 0.0, 0.0, info, "evaded")
		evaded.emit()
		last_outcome = "evaded"
		return
	# damage reduction (pass 43): a share of every hit, capped so nothing makes him immune
	var dr := clampf(sheet.get_stat("damage_reduction", 0.0), 0.0, 0.8)
	var dealt: float = amount * (1.0 - dr)
	invuln = 0.35
	regen_hold = sheet.get_stat("regen_delay", REGEN_HOLD_AFTER_HIT)
	_shield_wait = sheet.get_stat("shield_delay", 3.0)
	# the Energy Shield: while any of it holds, the whole hit is the shield's and none of it reaches his health
	last_outcome = "hit"
	if shield_pts > 0.0:
		last_outcome = "shield"
		var took := minf(shield_pts, dealt)
		shield_pts = maxf(shield_pts - dealt, 0.0)
		_log_hit(amount, 0.0, took, info, "broke" if shield_pts <= 0.0 else "shield")
		shield_hit.emit(shield_pts <= 0.0)
		return
	hp -= dealt
	_log_hit(amount, dealt, 0.0, info, "")
	if momentum and _momentum_t > 0.0:
		_momentum_t = 0.0
		Run.momentum = 0.0
		Run.rebuild_sheets()
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
		if not damage_log.is_empty():
			damage_log[damage_log.size() - 1]["fatal"] = true
			damage_log[damage_log.size() - 1]["hp"] = 0.0
		_die()


func _log_hit(raw: float, dealt: float, shield: float, info: Dictionary, note: String) -> void:
	damage_log.append({"t": Run.elapsed, "by": str(info.get("by", "something")), "kind": str(info.get("kind", "melee")),
		"fx": (info.get("fx", []) as Array).duplicate(), "raw": raw, "dealt": dealt, "shield": shield, "note": note,
		"hp": maxf(hp, 0.0), "fatal": false})
	var cut: float = Run.elapsed - LOG_SECONDS
	while not damage_log.is_empty() and (float(damage_log[0]["t"]) < cut or damage_log.size() > 80):
		damage_log.pop_front()


## The death screen's log: newest first, a line a hit, 💀 on the one that ended it; 🏹 ranged, 🗡️ melee, 👑 a boss.
func damage_log_text() -> String:
	var lines: PackedStringArray = []
	for k in range(damage_log.size() - 1, -1, -1):
		var e: Dictionary = damage_log[k]
		var t: float = float(e["t"])
		var stamp := "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]
		var icon: String = {"ranged": "🏹", "boss": "👑"}.get(str(e["kind"]), "🗡️")
		var head := ("💀 " if bool(e["fatal"]) else "") + icon
		var raw: float = float(e["raw"])
		var what := ""
		match str(e["note"]):
			"evaded":
				what = "evaded (%d)" % roundi(raw)
			"power-up":
				what = "blocked by the Shield power-up (%d)" % roundi(raw)
			"shield":
				what = "−%d shield" % roundi(float(e["shield"]))
			"broke":
				what = "−%d shield, it broke" % roundi(float(e["shield"]))
			_:
				what = "−%d HP, %d left" % [roundi(float(e["dealt"])), roundi(float(e["hp"]))]
				if raw - float(e["dealt"]) >= 1.0:
					what += " (armour took %d)" % roundi(raw - float(e["dealt"]))
		var fx: Array = e["fx"]
		var tail := ("  · " + ", ".join(PackedStringArray(fx))) if not fx.is_empty() else ""
		lines.append("%s %s  %s  %s%s" % [head, stamp, str(e["by"]), what, tail])
	if lines.is_empty():
		return "nothing hit you in the last 30 seconds"
	return "\n".join(lines)


## The most a hero can run right now (the rocketeer's rocket keeps to 90% of it). A harpoon rope does not change it:
## towards the thrower he still runs flat out.
func max_speed() -> float:
	return sheet.get_stat("move_speed", 5.0)


## His speed factor for a step in `dir` while a harpoon rope holds him: 1 towards the thrower or across, `tether_away`
## straight away from it, in between for a slant (the part of the step that pulls against the rope is what is slowed).
func leash_factor(dir: Vector3) -> float:
	if not tethered:
		return 1.0
	return leash_of(dir, global_position - tether_from, tether_away)


## The leash rule on its own: a step in `dir` when the thrower lies back along `away` (from it to the hero).
static func leash_of(dir: Vector3, away: Vector3, away_speed: float) -> float:
	var a := Vector3(away.x, 0.0, away.z)
	var flat := Vector3(dir.x, 0.0, dir.z)
	if a.length_squared() < 0.0001 or flat.length_squared() < 0.0001:
		return 1.0
	var pull := clampf(flat.normalized().dot(a.normalized()), 0.0, 1.0)
	return 1.0 - (1.0 - away_speed) * pull


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
	hp = max_hp * 0.5
	invuln = 2.0
	sprite.play("idle")
	Audio.play("pl_revive")
	damaged.emit(hp, max_hp)


func cheer() -> void:
	if sprite.has_animation("cheer"):
		sprite.play("cheer")
	input.enabled = false

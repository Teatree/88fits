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
## The spawn beam moves him by hand (pass 45): no gravity, no stick, no animation tick while this is on.
var cinematic := false
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
## (Ironwood's Unbroken, pass 46, never holds it)
var regen_hold := 0.0
const REGEN_HOLD_AFTER_HIT := 3.0
## Deep Breath (pass 46, Ironwood): seconds of the regen running `mult` times over, and the wait before it can come again
signal deep_breath
var deep_breath_t := 0.0
var _deep_cd := 0.0
## The last 30 s for the Down! list (pass 33.2; rows since pass 46): a hit is {t, by, id, kind (melee, ranged, boss),
## role (boss, elite, special or ""), colour ("#rrggbb" or ""), fx, raw, dealt, shield, note, hp, fatal}; a pickup heal
## is the same row with kind "heal", `by` the pickup and `amount` the health it gave back
var damage_log: Array = []
const LOG_SECONDS := 30.0
## the health Run last heard of (Run.note_hp: Desperado grows as it falls)
var _noted_hp := -1.0
var _noted_max := -1.0
## The Energy Shield line: points that take whole hits while any are left, back once he goes shield_delay untouched
var shield_pts := 0.0
var _shield_wait := 0.0
signal evaded
signal shield_hit(broke: bool)
## Standing still (pass 47): seconds since he last moved (no stick, next to no speed, on the ground); he counts as still
## once it passes STILL_AFTER. Siesta heals while he is (`still_regen` HP a second, held SIESTA_HOLD after a hit, never
## with Unbroken) and Steady Hand grows with it (Run.note_still every tick; `noted_still` is the last it heard).
const STILL_AFTER := 0.5
const STILL_SPEED := 0.3
const SIESTA_HOLD := 1.0
var _still_raw := 0.0
var _siesta_hold := 0.0
var noted_still := -1.0
## Healing over time (regen, Deep Breath, Siesta) shows as one green number every HEAL_BATCH seconds (pass 47, Garry:
## "Healing should be visible on the Player as well, regen and life steal too"), so a trickle never spams the screen.
const HEAL_BATCH := 0.5
var _heal_batch := 0.0
var _heal_batch_t := 0.0
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
## The art he is drawn with (pass 55): `character` wearing the look kept for him (Save.hero_look, else his JSON's
## `variant`), or the arena's look for this session (`look_override`, the HERO tab's chips). Only the strip reads it;
## everything else about him reads `character`.
var look: CharacterDef
var look_override := ""
var camera_yaw_fn: Callable = Callable()


func _ready() -> void:
	sheet = Run.player_sheet
	input.touch_ended.connect(func(): lifted_thumb.emit())
	_setup_sprite()
	_setup_shadow()
	refresh_stats()
	hp = max_hp


func setup(p_char: CharacterDef) -> void:
	# another hero (pass 55, the arena's swap) starts on his own kept look, and Buck's ramp starts from nothing
	if p_char != character:
		look_override = ""
		_momentum_t = 0.0
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
	look = _look_def()
	var tex: Texture2D = look.sprite if look and look.sprite else null
	var anims: Dictionary = look.anims if look else {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
	if tex == null:
		tex = PlaceholderArt.character_strip(character)
	var cols: int = look.strip_cols if look and look.sprite else 0
	var fps: Dictionary = look.fps if look and look.sprite else {}
	sprite.enable_outline()
	# his speed trails run under him, never over him (pass 49)
	sprite.enable_over_trails()
	sprite.setup(tex, anims, ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"], 1.9, cols, fps)
	sprite.position = Vector3(0, 0.0, 0)


## The look he wears: the arena's for this session, else the one kept for him (Save.hero_look); a code he does not
## have falls back to his JSON's (CharacterDef.variant_def).
func _look_def() -> CharacterDef:
	if character == null:
		return null
	return character.variant_def(look_override if look_override != "" else Save.hero_look(character.id))


## The arena's look chips (pass 55): draws him wearing art variant `code` at once, for this session only ("" = the
## kept look again).
func show_look(code: String) -> void:
	look_override = code
	if is_inside_tree():
		_setup_sprite()


## The art variant he is drawn with now ("" for a hero with one art).
func look_code() -> String:
	return look.look_code() if look else ""


func _setup_shadow() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/shaders/blob_shadow.gdshader")
	# under the gems and coins like the creatures' (pass 54, EnemyManager.SHADOW_PRIORITY)
	mat.render_priority = EnemyManager.SHADOW_PRIORITY
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
	_note_hp()
	if dead:
		# only gravity: whatever he was doing when he fell stops with him
		velocity.x = 0.0
		velocity.z = 0.0
		_kb = Vector3.ZERO
		velocity.y -= 24.0 * delta
		move_and_slide()
		_stop_still()
		Perf.add("player", _t0)
		return
	if cinematic:
		_stop_still()
		Perf.add("player", _t0)
		return
	invuln = max(invuln - delta, 0.0)
	_knock_grace = maxf(_knock_grace - delta, 0.0)
	_stick_lock = maxf(_stick_lock - delta, 0.0)
	_settle_t = maxf(_settle_t - delta, 0.0)
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
	# the map's pace knob (pass 48, Run.move_pace): the hero runs at its fraction, like every creature
	var move_speed := sheet.get_stat("move_speed", 5.0) * Run.move_pace()
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
	# a hit's shove (pass 54, hit_knock): for a beat the stick does not move him, so the shove is not walked through
	if _stick_lock > 0.0:
		planar = Vector3.ZERO
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
	_tick_still(delta, planar, stepped, on_floor)
	_tick_regen(delta)
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


## Regen: held for a few seconds after every hit (Unbroken never holds it), so a fight is won by not being hit, not by
## out-ticking the crowd. Deep Breath runs it `mult` times over while its seconds last; the hold still applies, so
## without Unbroken the breath pays out once he gets clear.
## Siesta (pass 47) heals on top while he stands still, on its own hold; what comes back shows every HEAL_BATCH seconds.
func _tick_regen(delta: float) -> void:
	regen_hold = maxf(regen_hold - delta, 0.0)
	_tick_deep_breath(delta)
	var regen := sheet.get_stat("regen", 0.0)
	if deep_breath_t > 0.0:
		regen *= Run.perk_param("deep_breath", "mult", 4.0)
	var rate := regen if regen > 0.0 and regen_hold <= 0.0 else 0.0
	rate += siesta_rate()
	# Afterglow (pass 54, Solenne's perk): every heal on her is `heal_mult` times its size, her regen too
	rate *= heal_mult()
	if rate > 0.0 and hp < max_hp and not dead:
		var before := hp
		hp = minf(hp + rate * delta, max_hp)
		_heal_batch += hp - before
		damaged.emit(hp, max_hp)
	_flush_heal_batch(delta)


## Siesta (pass 47, Garry: "Standing Still Heals the Hero"): `still_regen` HP a second while he stands still, nothing for
## SIESTA_HOLD after a hit (Unbroken never holds it).
func siesta_rate() -> float:
	if not is_still() or _siesta_hold > 0.0:
		return 0.0
	return maxf(sheet.get_stat("still_regen", 0.0), 0.0)


## The healing over time as one green number every HEAL_BATCH seconds: what came back since the last one, once it is a
## whole point (when the bar fills, what is left over from half a point; less is let go).
func _flush_heal_batch(delta: float) -> void:
	_heal_batch_t += delta
	if _heal_batch_t < HEAL_BATCH:
		return
	_heal_batch_t = 0.0
	var full := hp >= max_hp
	if _heal_batch >= 1.0 or (full and _heal_batch >= 0.5):
		if DamageNumbers.I: DamageNumbers.I.hero_heal(_heal_batch)
		_heal_batch = 0.0
	elif full:
		_heal_batch = 0.0


## Whether he stands still (pass 47): no stick, next to no speed (a shove or a rope moving him counts as moving), on the
## ground. Run hears how long every tick it changes (Steady Hand folds it into his attack damage): every tick while he
## stands, once when he moves (0), nothing while he keeps moving.
func _tick_still(delta: float, planar: Vector3, stepped: Vector3, on_floor: bool) -> void:
	_siesta_hold = maxf(_siesta_hold - delta, 0.0)
	if planar.length() > 0.05 or stepped.length() > STILL_SPEED * delta or not on_floor:
		_still_raw = 0.0
	else:
		_still_raw += delta
	var s := still_seconds()
	if s != noted_still:
		_note_still(s)


## Seconds he has stood still, counted from when he counts as still (0 while he moves).
func still_seconds() -> float:
	return maxf(_still_raw - STILL_AFTER, 0.0)


func is_still() -> bool:
	return _still_raw >= STILL_AFTER


## Dead, or in the spawn beam: not standing still, and Run hears so once.
func _stop_still() -> void:
	_still_raw = 0.0
	if noted_still != 0.0:
		_note_still(0.0)


## Steady Hand's ear (pass 47): Run.note_still with the seconds he has stood still, every tick.
func _note_still(seconds: float) -> void:
	noted_still = seconds
	Run.note_still(seconds)


## Deep Breath (pass 46, Ironwood): once his health is under `below` of the most it can be, his regen runs `mult` times
## over for `seconds`, then not again for `cooldown` seconds (counted from when it began).
func _tick_deep_breath(delta: float) -> void:
	deep_breath_t = maxf(deep_breath_t - delta, 0.0)
	_deep_cd = maxf(_deep_cd - delta, 0.0)
	if _deep_cd > 0.0 or not Run.has_perk("deep_breath"):
		return
	if hp > 0.0 and hp < max_hp * Run.perk_param("deep_breath", "below", 0.35):
		deep_breath_t = Run.perk_param("deep_breath", "seconds", 6.0)
		_deep_cd = Run.perk_param("deep_breath", "cooldown", 40.0)
		deep_breath.emit()


## Run hears of his health once a tick, and only when it moved (pass 46: Desperado reads it).
func _note_hp() -> void:
	if hp != _noted_hp or max_hp != _noted_max:
		_noted_hp = hp
		_noted_max = max_hp
		Run.note_hp(hp, max_hp)


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
## Out of the crowd (pass 60, Garry: "currently it's possible for Player to get knocked about between enemies, but the
## idea is that the knockback would throw the Player away from the enemies"): a creature's knock (a bite, a charge, a
## slam) goes the emptiest way out, escape_dir, and for KNOCK_SETTLE seconds after one lands no creature knock may turn
## him back the way he came (settle_knock: the part against the last knock dropped, at least SETTLE_KEEP of the push kept
## so the hit still reads). A hostile shot's shove and a blast keep their own line (ProjectileManager passes
## from_creature false; _knock_from reads the hit's kind).
const KNOCK_SETTLE := 0.45
const SETTLE_KEEP := 0.35
const ESCAPE_REACH := 4.5
const ESCAPE_DIRS := 16
const ESCAPE_PUSH_W := 0.6
var _settle_t := 0.0
var _last_knock := Vector3.ZERO
## the crowd escape_dir reads: Game's EnemyManager, found on the parent the first time (tests set it; none on the title)
var enemies: EnemyManager = null
## A landed hit's shove (pass 54, Garry: every creature its own knockback): take_damage shoves him away from where the
## hit came from by the number its caller names in `info.knock` (a bite: the creature's own, EnemyDef.hit_knockback, a
## boss's or an Elite's 1.6 times; a hostile shot with no weight of its own: 0.7 of its shooter's; the ring of fire:
## none), or HIT_KNOCK when it names none (an eruption, a hell line, a blast's own hit: the fixed shove every hit gave
## before). A hit the Energy Shield takes shoves him too; an evaded or an immune one never does, and (pass 60) neither
## does one the Invincibility bubble takes (knock_immune). hit_knock is the shove itself: past the shove's grace (the
## bites are already spaced by hit_invuln), never past HIT_KNOCK_MAX m/s in all (a blast already flinging him harder
## keeps its own speed), and for STICK_LOCK seconds the stick does not move him, so the shove reads instead of being
## walked through.
const HIT_KNOCK := 2.5
const HIT_KNOCK_MAX := 9.0
const STICK_LOCK := 0.12
var _stick_lock := 0.0
## what the last take_damage came to: "hit", "shield", "evaded", "immune" or "none" (a blast reads it: an evade
## leaves him standing)
var last_outcome := "none"


## `from_creature` (the default): a creature's own shove, turned out of the crowd and settled (_crowd_knock); a hostile
## shot's passes false and keeps its line. Nothing while the Invincibility bubble holds (pass 60).
func shove(v: Vector3, from_creature: bool = true) -> bool:
	if _knock_grace > 0.0 or dead or knock_immune():
		return false
	_knock_grace = KNOCK_GRACE
	# whatever the source, the shove itself is bounded: the physics never sees a metre a frame
	var f: float = minf(v.length(), 14.0)
	if f > 0.01:
		var push := v.normalized() * f
		if from_creature:
			push = _crowd_knock(push)
		_kb += push
	return true


## The hero's own knockback and the pulls on him: a `hostile` one (the default: a harpoon rope's, a silk line's, a
## blast's throw) is nothing while the Invincibility bubble holds; his own (Thruster's lunge passes false) always moves
## him.
func apply_knockback(v: Vector3, hostile: bool = true) -> void:
	if hostile and knock_immune():
		return
	_kb += v


## The Invincibility power-up's rule (pass 60, Garry: "Invincibility (shield) Power Up should null out the knockback
## from enemies"): while its bubble is up no hostile shove, hit knock, pull or blast moves him. Only the power-up: the
## Energy Shield line's points still take the shove of what they catch, and the blink after a hit or a revive is no
## bubble.
func knock_immune() -> bool:
	return shield_t > 0.0


## A landed hit's shove (pass 54): `v` (m/s, flat) on top of whatever moves him, past the shove's grace, the whole never
## past HIT_KNOCK_MAX (or past what a blast already gave him), and the stick held off for STICK_LOCK seconds. A
## creature's (`from_creature`, the default) goes out of the crowd and never straight back (pass 60, _crowd_knock); a
## shot's keeps its line. Nothing while the Invincibility bubble holds.
func hit_knock(v: Vector3, from_creature: bool = true) -> void:
	if dead or knock_immune():
		return
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length_squared() < 0.0001:
		return
	if from_creature:
		flat = _crowd_knock(flat)
		if flat.length_squared() < 0.0001:
			return
	var cap := maxf(HIT_KNOCK_MAX, _kb.length())
	_kb += flat
	if _kb.length() > cap:
		_kb = _kb.normalized() * cap
	_stick_lock = STICK_LOCK


## A creature's knock as it lands (pass 60): turned the emptiest way out of the crowd (escape_dir) and, within
## KNOCK_SETTLE of the last one, never back against it (settle_knock); the way it went is kept for the next.
func _crowd_knock(push: Vector3) -> Vector3:
	var out := escape_dir(push)
	if _settle_t > 0.0 and _last_knock.length_squared() > 0.0001:
		out = settle_knock(out, _last_knock)
	if out.length_squared() > 0.0001:
		_last_knock = out.normalized()
		_settle_t = KNOCK_SETTLE
	return out


## The no-ping-pong rule on its own: `push` with its part against `last` (the last knock's way) dropped, and at least
## SETTLE_KEEP of its length kept, along what is left or, when nothing is, along `last`.
static func settle_knock(push: Vector3, last: Vector3) -> Vector3:
	var mag := push.length()
	if mag < 0.0001 or last.length_squared() < 0.0001:
		return push
	var l := last.normalized()
	var out := push
	var against := push.dot(l)
	if against < 0.0:
		out = push - l * against
	var keep := mag * SETTLE_KEEP
	if out.length() < keep:
		out = (out.normalized() if out.length_squared() > 0.000001 else l) * keep
	return out


## The emptiest way out for a push (pass 60): of ESCAPE_DIRS flat directions, the one with the least crowd ahead of it
## (every live creature within ESCAPE_REACH, weighed 1 - d / reach times how squarely it lies that way) less a pull of
## ESCAPE_PUSH_W towards the push's own line, at the push's length. A lone biter: straight away from it, as before; one
## on each side: out through the gap, not into the other. Without a crowd to read (the title, tests) the push as it was.
func escape_dir(push: Vector3) -> Vector3:
	var flat := Vector3(push.x, 0.0, push.z)
	var mag := flat.length()
	if mag < 0.0001:
		return Vector3.ZERO
	var em := _crowd()
	if em == null:
		return flat
	var near: PackedInt32Array = em.indices_in_radius(global_position, ESCAPE_REACH)
	var here := global_position
	var cands: Array = []
	for i in near:
		if em.alive[i] == 0 or em.hidden[i] == 1 or em.held[i] == 1:
			continue
		var to: Vector3 = em.pos[i] - here
		to.y = 0.0
		var d := to.length()
		if d < 0.001 or d > ESCAPE_REACH:
			continue
		cands.append([to / d, 1.0 - d / ESCAPE_REACH])
	if cands.is_empty():
		return flat
	var pdir := flat / mag
	var a0 := atan2(pdir.x, pdir.z)
	var best := pdir
	var best_score := INF
	for k in range(ESCAPE_DIRS):
		var a := a0 + TAU * float(k) / float(ESCAPE_DIRS)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var crowd := 0.0
		for c: Array in cands:
			var u: Vector3 = c[0]
			crowd += float(c[1]) * maxf(0.0, dir.dot(u))
		var score := crowd - ESCAPE_PUSH_W * dir.dot(pdir)
		if score < best_score - 0.0001:
			best_score = score
			best = dir
	return best * mag


## The crowd he reads: `enemies` when set, else the nearest ancestor's (Game.enemies: the hero is Game's own child, a
## holder or two up is allowed), found once; null when there is none (the title's stage, a bare test).
func _crowd() -> EnemyManager:
	if enemies == null or not is_instance_valid(enemies):
		enemies = null
		var p := get_parent()
		var hops := 0
		while p != null and hops < 3:
			if "enemies" in p:
				enemies = p.get("enemies") as EnemyManager
				break
			p = p.get_parent()
			hops += 1
	return enemies


## The shove of a hit that landed from `from` (pass 54): `info.knock` m/s straight away from it, HIT_KNOCK when the
## caller names none, nothing at 0 (the ring of fire) or when it came from right where he stands. A creature's hit (any
## kind but "ranged") goes out of the crowd (pass 60); a shot's keeps its line.
func _knock_from(from: Vector3, info: Dictionary) -> void:
	var f := float(info.get("knock", HIT_KNOCK))
	if f <= 0.0:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	hit_knock(away.normalized() * f, str(info.get("kind", "melee")) != "ranged")


## A blast throws him (pass 33.3, the rocketeer's rocket): past the shove's cap and its grace, `up` metres a second off
## the ground with it, and the grace starts again so no shove stacks on top while he flies. A `hostile` one (the
## default) is nothing while the Invincibility bubble holds (pass 60); his own (Astro's thruster burst passes false)
## throws him anyway.
func blast(v: Vector3, up: float = 0.0, hostile: bool = true) -> void:
	if dead or (hostile and knock_immune()):
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


## Health back. `source` names a pickup heal for the Down! list (the Heart, a Cake Slice, the Healing Well); regen,
## lifesteal and the level patch pass none and are not listed. A heal that gave nothing back is not listed either.
func heal(amount: float, source: String = "") -> void:
	if dead:
		return
	# Afterglow (pass 54): every heal is `heal_mult` times its size (1 without the perk)
	amount *= heal_mult()
	var before := hp
	hp = minf(hp + amount, max_hp)
	if RunAnalytics.I: RunAnalytics.I.healed(hp - before)
	# a green number on him (pass 47): pickups, lifesteal and the level patch as they come, lifesteal's points merged
	if hp - before >= 0.5 and DamageNumbers.I: DamageNumbers.I.hero_heal(hp - before)
	if source != "" and hp - before >= 0.5:
		damage_log.append({"t": Run.elapsed, "by": source, "id": "", "kind": "heal", "role": "", "colour": "", "fx": [],
			"raw": amount, "amount": hp - before, "dealt": 0.0, "shield": 0.0, "note": "", "hp": hp, "fatal": false})
		_trim_log()
	damaged.emit(hp, max_hp)


## How much bigger every heal on him is (pass 54: the `heal_mult` player stat, Solenne's Afterglow; 1 without it).
func heal_mult() -> float:
	return maxf(sheet.get_stat("heal_mult", 1.0), 0.0) if sheet else 1.0


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


## `info` says who hit him and how, for the Down! list: {"by", "kind" (melee, ranged, boss), "fx": [...]}, and from
## EnemyManager.hit_info also "id", "role" (boss, elite, special or "") and "colour" ("#rrggbb" or "").
func take_damage(amount: float, from: Vector3, info: Dictionary = {}) -> void:
	last_outcome = "none"
	if dead:
		return
	if shield_t > 0.0:
		# the shield power-up takes it: a flash on the sphere, nothing on the hero, and (pass 60) no shove either
		_shield_hit = 1.0
		_log_hit(amount, 0.0, 0.0, info, "power-up")
		last_outcome = "shield"
		if DamageNumbers.I: DamageNumbers.I.hero_block()
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
		if DamageNumbers.I: DamageNumbers.I.hero_dodge()
		return
	# damage reduction (pass 43): a share of every hit, capped so nothing makes him immune; Gas Mask (pass 48) adds a
	# point for every poisoned creature alive, up to its cap (Run.gas_mask_dr), under the same cap
	var dr := clampf(sheet.get_stat("damage_reduction", 0.0) + Run.gas_mask_dr(), 0.0, 0.8)
	var dealt: float = amount * (1.0 - dr)
	invuln = sheet.get_stat("hit_invuln", 0.5)
	# Unbroken (pass 46, Ironwood): a hit never stops his healing (Siesta's either, pass 47)
	if not Run.has_perk("unbroken"):
		regen_hold = sheet.get_stat("regen_delay", REGEN_HOLD_AFTER_HIT)
		_siesta_hold = SIESTA_HOLD
	_shield_wait = sheet.get_stat("shield_delay", 3.0)
	# the Energy Shield: while any of it holds, the whole hit is the shield's and none of it reaches his health
	last_outcome = "hit"
	if shield_pts > 0.0:
		last_outcome = "shield"
		var took := minf(shield_pts, dealt)
		shield_pts = maxf(shield_pts - dealt, 0.0)
		_log_hit(amount, 0.0, took, info, "broke" if shield_pts <= 0.0 else "shield")
		shield_hit.emit(shield_pts <= 0.0)
		if DamageNumbers.I: DamageNumbers.I.hero_shield(took)
		_knock_from(from, info)
		return
	hp -= dealt
	_log_hit(amount, dealt, 0.0, info, "")
	# Hush Money (pass 47c): every hit that reaches his health pays
	var paid := int(round(sheet.get_stat("gold_on_hit", 0.0)))
	if paid > 0:
		Run.add_gold(paid)
	if DamageNumbers.I: DamageNumbers.I.hero_hurt(dealt)
	if momentum and _momentum_t > 0.0:
		_momentum_t = 0.0
		Run.momentum = 0.0
		Run.rebuild_sheets()
	_flash = 1.0
	# a strip with a real flinch plays it through; the single squashed frame shows for a blink
	var art: CharacterDef = look if look else character
	var hit_frames: int = int(art.anims.get("hit", 1)) if art else 1
	var hit_fps: float = float(art.fps.get("hit", 20.0)) if art else 20.0
	_hit_pose = float(hit_frames) / maxf(hit_fps, 1.0) if hit_frames > 1 else 0.15
	hit.emit()
	_knock_from(from, info)
	Audio.play("pl_hurt", global_position)
	damaged.emit(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		if not damage_log.is_empty():
			damage_log[damage_log.size() - 1]["fatal"] = true
			damage_log[damage_log.size() - 1]["hp"] = 0.0
		_die()


func _log_hit(raw: float, dealt: float, shield: float, info: Dictionary, note: String) -> void:
	damage_log.append({"t": Run.elapsed, "by": str(info.get("by", "something")), "id": str(info.get("id", "")),
		"kind": str(info.get("kind", "melee")), "role": role_of(info), "colour": colour_of(info.get("colour", "")),
		"fx": (info.get("fx", []) as Array).duplicate(), "raw": raw, "dealt": dealt, "shield": shield, "note": note,
		"hp": maxf(hp, 0.0), "fatal": false})
	if RunAnalytics.I: RunAnalytics.I.took(info, raw, dealt, shield, note)
	_trim_log()


func _trim_log() -> void:
	var cut: float = Run.elapsed - LOG_SECONDS
	while not damage_log.is_empty() and (float(damage_log[0]["t"]) < cut or damage_log.size() > 80):
		damage_log.pop_front()


## A hit's role for the Down! list's icon: what EnemyManager.hit_info says ("boss", "elite", "special" or ""), else read
## off the kind (a boss's attack, the ring of fire) and the Elite flag the run recorder gets.
static func role_of(info: Dictionary) -> String:
	var r := str(info.get("role", ""))
	if r != "":
		return r
	if str(info.get("kind", "")) == "boss":
		return "boss"
	return "elite" if bool(info.get("elite", false)) else ""


## A creature's own colour (an elite modifier's outline, a coloured special's tint) as "#rrggbb", or "" for none.
static func colour_of(v) -> String:
	if v is Color:
		return "#" + (v as Color).to_html(false)
	var s := str(v).strip_edges() if v != null else ""
	if s == "" or not Color.html_is_valid(s):
		return ""
	return "#" + Color.html(s).to_html(false)


## The Down! list as text, for its copy button: newest first, a line a row, in plain words ("FATAL" on the hit that
## ended it; "boss", "elite", "special", "ranged", "melee", "heal").
func damage_log_text() -> String:
	return log_text(damage_log)


static func log_text(rows: Array) -> String:
	var lines: PackedStringArray = []
	for k in range(rows.size() - 1, -1, -1):
		var e: Dictionary = rows[k]
		var t: float = float(e.get("t", 0.0))
		var stamp := "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]
		var kind := str(e.get("kind", "melee"))
		var role := str(e.get("role", ""))
		var tag := role if role != "" else kind
		if role != "" and kind == "ranged":
			tag += ", ranged"
		var raw: float = float(e.get("raw", 0.0))
		var dealt: float = float(e.get("dealt", 0.0))
		var what := ""
		match str(e.get("note", "")):
			"evaded":
				what = "evaded (%d)" % roundi(raw)
			"power-up":
				what = "blocked by the Shield power-up (%d)" % roundi(raw)
			"shield":
				what = "−%d shield" % roundi(float(e.get("shield", 0.0)))
			"broke":
				what = "−%d shield, it broke" % roundi(float(e.get("shield", 0.0)))
			_:
				if kind == "heal":
					what = "+%d HP, %d left" % [roundi(float(e.get("amount", 0.0))), roundi(float(e.get("hp", 0.0)))]
				else:
					what = "−%d HP, %d left" % [roundi(dealt), roundi(float(e.get("hp", 0.0)))]
					if raw - dealt >= 1.0:
						what += " (damage reduction took %d)" % roundi(raw - dealt)
		var fx: Array = e.get("fx", [])
		var tail := ("  · " + ", ".join(PackedStringArray(fx))) if not fx.is_empty() else ""
		var head := "FATAL " if bool(e.get("fatal", false)) else ""
		lines.append("%s%s  %s  %s  %s%s" % [head, stamp, tag, str(e.get("by", "something")), what, tail])
	if lines.is_empty():
		return "nothing hit you in the last 30 seconds"
	return "\n".join(lines)


## The most a hero can run right now (the rocketeer's rocket keeps to 90% of it). A harpoon rope does not change it:
## towards the thrower he still runs flat out. The map's pace knob is in it (pass 48, Run.move_pace).
func max_speed() -> float:
	return sheet.get_stat("move_speed", 5.0) * Run.move_pace()


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
	# half his health unless Second Wind's ranks say more (pass 46: the revive_hp stat)
	hp = clampf(max_hp * sheet.get_stat("revive_hp", 0.5), 1.0, max_hp)
	invuln = 2.0
	sprite.play("idle")
	Audio.play("pl_revive")
	damaged.emit(hp, max_hp)


func cheer() -> void:
	if sprite.has_animation("cheer"):
		sprite.play("cheer")
	input.enabled = false

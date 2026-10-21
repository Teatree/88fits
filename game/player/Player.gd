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
## The blob's size as Player wants it (pass 65: Game._drape_hero_shadow lays it on the slope from this every frame)
var shadow_scale := Vector3(0.9, 1, 0.63)
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
var _over_t := 0.0        # Buck's Overdrive (pass 67): seconds at full charge since the last hit that landed
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
## Snake Oil (pass 69, a passive item): health past full, up to overheal_cap(); a heal that is not regen fills it once the
## bar is full, a hit takes it before his health, it never fades. The HUD draws it as the bar's pink extension.
var overheal := 0.0
## Hot Springs (pass 69, a passive item): what every heal (regen too) gave back since the last pulse, and the wait before
## the next; heal_pulsed carries the pulse's damage (Game hurts what stands within HEAL_PULSE_RADIUS).
const HEAL_PULSE_RADIUS := 3.0
const HEAL_PULSE_PER_HP := 2.0
const HEAL_PULSE_CAP := 40.0
const HEAL_PULSE_GAP := 0.5
var _pulse_healed := 0.0
var _pulse_cd := 0.0
signal heal_pulsed(damage: float, healed: float)
## Last Stand (pass 69, a passive item): a hit left him low and it started (Run.last_stand_check); Game slows the clock.
signal last_stand
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
## The landing at the run's start (pass 64, Garry: "make it so the hero is facing us when we land"): the spawn beam
## turns him to the camera (face_camera) and he keeps that view until he first moves, since _animate only picks a view
## while moving. `land_settle` gives him a soft squash and spring back as he touches down (LAND_SQUASH of his height at
## the deepest, over `_land_len` seconds), and `quiet_invuln` keeps the landing's second of safety from blinking him.
const LAND_SQUASH := 0.09
var _land_t := 0.0
var _land_len := 0.0
var quiet_invuln := false
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
		# and so do Overdrive's gears (pass 67)
		_over_t = 0.0
		Run.overdrive = 0
	character = p_char
	cannot_stop = p_char != null and p_char.specials.has("cannot_stop")
	momentum = p_char != null and p_char.specials.has("momentum")
	if is_inside_tree():
		_setup_sprite()


func refresh_stats() -> void:
	sheet = Run.player_sheet
	var new_max := sheet.get_stat("max_hp", 100.0)
	if dead:
		# a level banked on the fallen hero (pass 61: Astro's max HP climbs with it) leaves him down; the revive sets him up
		max_hp = new_max
	elif new_max > max_hp and max_hp > 0.0:
		# a rise (pass 61: Astro's max HP climbs every level) brings the same health with it, so a level-up never leaves
		# her looking wounded; a fall keeps the share she had
		hp = clampf(hp + (new_max - max_hp), 1.0, new_max)
		max_hp = new_max
	elif new_max != max_hp:
		var ratio: float = hp / max_hp if max_hp > 0.0 else 1.0
		max_hp = new_max
		hp = clamp(new_max * ratio, 1.0, new_max)
	# Snake Oil's overheal never outgrows its cap (a level of max HP lost, the item gone)
	overheal = minf(overheal, overheal_cap())
	damaged.emit(hp, max_hp)
	# Marshal's Star (pass 70): its star over his head once the item is held
	_star_guard_sync()


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
	return character.variant_def(look_override) if look_override != "" else Registry.played_look(character)


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


## Pass 95 (lane BREATH): where his face is when he looks along `dir` (the Dragon's Breath starts there, no 3D object):
## FACE_UP metres up his 1.9 m painting, FACE_FORWARD out, so the fire leaves in front of the painting, not through it.
const FACE_UP := 1.45
const FACE_FORWARD := 0.3


func face_origin(dir: Vector3) -> Vector3:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		d = forward()
	return global_position + Vector3(0, FACE_UP, 0) + d.normalized() * FACE_FORWARD


## Pass 95 (lane BREATH): seconds he has stood still AND unhit (Held Breath's rule: "being hit by anything breaks up this
## effect"): his still seconds (still_seconds, untouched: Steady Hand keeps reading those), or the seconds since the last
## hit that landed on his star, his shield or his health (take_damage: an evaded or immune hit is a miss and does not
## count), whichever is shorter.
var _hit_ago := 1.0e9


func still_unhit_seconds() -> float:
	return minf(still_seconds(), _hit_ago)


## take_damage's hook: a hit landed now.
func _note_hit_for_still() -> void:
	_hit_ago = 0.0


func _tick_hit_ago(delta: float) -> void:
	_hit_ago = minf(_hit_ago + delta, 1.0e9)


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
	# pass 80 (lane OASIS): wading, his walk is water_slow slower (never a shove or a pull, never in the air)
	planar *= _wade_mult()
	# Hang Time (pass 70): in the air the arc carries him and the stick only bends it (_air_planar)
	if airborne:
		planar = _air_planar(delta, planar, prev_facing)
	rotation.y = facing
	var dyaw := angle_difference(prev_facing, facing) / maxf(delta, 0.001)
	_tilt = lerpf(_tilt, clampf(dyaw / 9.0, -1.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))
	if airborne:
		velocity.y -= _air_g * delta
	elif not is_on_floor():
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
	if airborne:
		_tick_air(delta, on_floor)
	if on_floor and not was_on_floor:
		landed.emit()
		Audio.play("pl_land", global_position)
	was_on_floor = on_floor
	_tick_still(delta, planar, stepped, on_floor)
	_tick_regen(delta)
	# Hot Springs (pass 69): the heals since the last pulse go out
	_tick_heal_pulse(delta)
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
	if airborne:
		_air_look()
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
		# Hot Springs (pass 69): regen's ticks count towards the pulse too (Snake Oil's overheal they never fill)
		_note_heal_pulse(hp - before)
		if RunAnalytics.I: RunAnalytics.I.regen(hp - before)
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
	_tick_hit_ago(delta)   # pass 95 (lane BREATH): still_unhit_seconds


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
	var land := land_squash()
	_land_t = maxf(_land_t - delta, 0.0)
	sprite.set_squash(1.0 - jump_stretch * 0.5 + land * 0.6, 1.0 + bob * 0.5 + jump_stretch - land)
	sprite.set_roll(-_tilt * 0.14)
	sprite.set_flash(_flash)
	# pass 87 (lane FIXES): an evade's see-through second fading back
	_tick_evade_ghost(delta)
	if quiet_invuln and invuln <= 0.0:
		quiet_invuln = false
	if invuln > 0.0 and not god and not quiet_invuln:
		sprite.visible = int(invuln * 20.0) % 2 == 0
	else:
		sprite.visible = true
	var s := 0.9 + (0.0 if on_floor else 0.2)
	shadow_scale = Vector3(s, 1, s * 0.7)
	shadow.scale = shadow_scale


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
## Pass 89: every caller of shove is a special attack's push (a charge, a slam, an eruption, a shot with its own
## weight), so it comes at knock_share(true).
func shove(v: Vector3, from_creature: bool = true) -> bool:
	var share: float = knock_share(true)
	if _knock_grace > 0.0 or dead or knock_immune() or share <= 0.0:
		return false
	_knock_grace = KNOCK_GRACE
	# whatever the source, the shove itself is bounded: the physics never sees a metre a frame
	var f: float = minf(v.length() * share, 14.0)
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


## Whether every hit pushes him whole, as before pass 88: the debug switch Settings.hero_knockback, off by default.
## Pass 88 took every push away; pass 89 (Garry: "make it so the special attacks still knock player back. Like
## rocketeer rockets, dynamite, boss attacks, etc. but less than before. The regular melee attacks shouldn't have a
## knockback still") brings the special attacks' back at a share (knock_share). His own moves (the dash, a lunge, the
## thruster burst, the leap, Hang Time's trampoline, a teleport) and the pulls (a silk line, the harpoon's leash) are
## not knockback and always move him.
func hit_knockback_on() -> bool:
	return bool(Settings.hero_knockback)


## How much of a push reaches him (pass 89): 1 with the debug switch on (every push as before pass 88); otherwise a
## `special` one (a charge, a blast, a rocket, the dynamite, a boulder, a slam, an eruption, a boss's attack, the
## Sniper's beam, a shot with its own weight) at the map's `hero_special_knock` (Red Canyon: the game's 0.5), and a
## regular one (any creature's bite, a boss's too, and a plain shot or splash) not at all.
func knock_share(special: bool) -> float:
	if hit_knockback_on():
		return 1.0
	if not special:
		return 0.0
	var m: MapDef = Run.map
	if m == null or m.timeline == null:
		return WaveTimeline.HERO_SPECIAL_KNOCK_DEFAULT
	return clampf(m.timeline.hero_special_knock, 0.0, 1.0)


## Whether a hit's own shove (take_damage's `info.knock`) is a special attack's (pass 89): what the caller says in
## `info.special_knock`, else a boss's attack (`kind` "boss": the contact bite says false itself).
static func is_special_hit(info: Dictionary) -> bool:
	if info.has("special_knock"):
		return bool(info["special_knock"])
	return str(info.get("kind", "melee")) == "boss"


## A special attack's push through the plain knockback (pass 89: an Elite's blast, a slam without a lift): `v` at
## knock_share(true), nothing while the Invincibility bubble holds.
func special_push(v: Vector3) -> void:
	var share: float = knock_share(true)
	if share <= 0.0 or dead or knock_immune():
		return
	_kb += v * share


## The Invincibility power-up's rule (pass 60, Garry: "Invincibility (shield) Power Up should null out the knockback
## from enemies"): while its bubble is up no hostile shove, hit knock, pull or blast moves him. Only the power-up: the
## Energy Shield line's points still take the shove of what they catch, and the blink after a hit or a revive is no
## bubble. Pass 70: nor while Hang Time's trampoline has him in the air (airborne).
func knock_immune() -> bool:
	return shield_t > 0.0 or airborne


## A landed hit's shove (pass 54): `v` (m/s, flat) on top of whatever moves him, past the shove's grace, the whole never
## past HIT_KNOCK_MAX (or past what a blast already gave him), and the stick held off for STICK_LOCK seconds. A
## creature's (`from_creature`, the default) goes out of the crowd and never straight back (pass 60, _crowd_knock); a
## shot's keeps its line. Nothing while the Invincibility bubble holds.
## Pass 89: a `special` one comes at knock_share(true), a regular one (a bite, a plain shot) at knock_share(false).
func hit_knock(v: Vector3, from_creature: bool = true, special: bool = false) -> void:
	var share: float = knock_share(special)
	if dead or knock_immune() or share <= 0.0:
		return
	var flat := Vector3(v.x, 0.0, v.z) * share
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
	hit_knock(away.normalized() * f, str(info.get("kind", "melee")) != "ranged", is_special_hit(info))


## A blast throws him (pass 33.3, the rocketeer's rocket): past the shove's cap and its grace, `up` metres a second off
## the ground with it, and the grace starts again so no shove stacks on top while he flies. A `hostile` one (the
## default) is nothing while the Invincibility bubble holds (pass 60); his own (Astro's thruster burst passes false)
## throws him anyway. Pass 89: a hostile blast is always a special attack's, so it throws him at knock_share(true),
## the push and the lift alike.
func blast(v: Vector3, up: float = 0.0, hostile: bool = true) -> void:
	if dead:
		return
	if hostile:
		var share: float = knock_share(true)
		if knock_immune() or share <= 0.0:
			return
		v *= share
		up *= share
	_knock_grace = KNOCK_GRACE
	_kb += Vector3(v.x, 0, v.z)
	if up > 0.0:
		velocity.y = maxf(velocity.y, up)


## Buck's momentum: climbs to full over ramp_seconds while he is not hit (standing still too), and a hit that lands knocks
## off `hit_loss` of it (take_damage). Applied to the sheet a few times a second so the stats screen and the speed follow
## it; the last step always lands on exactly full (pass 67: a sheet that had last followed at 0.985 stayed there, under
## Ram's 0.99, once a half-loss shifted the steps).
func _tick_momentum(delta: float) -> void:
	var ramp: float = float(Run.momentum_def.get("ramp_seconds", 12.0))
	_momentum_t = minf(_momentum_t + delta, ramp)
	var f := _momentum_t / maxf(ramp, 0.1)
	_momentum_sync -= delta
	if _momentum_sync <= 0.0 and (absf(f - Run.momentum) > 0.02 or (f >= 1.0 and Run.momentum < 1.0)):
		_momentum_sync = 0.25
		Run.momentum = f
		Run.rebuild_sheets()
	# Overdrive (pass 67, Buck's perk): every `every` seconds at full charge is a gear, Run.overdrive_gears() at most; the
	# sheet follows when the count changes (Run._build_player_sheet folds them into attack damage)
	if f >= 0.99 and Run.has_perk("overdrive"):
		_over_t += delta
		var n := mini(int(_over_t / maxf(Run.perk_param("overdrive", "every", 5.0), 0.1)), Run.overdrive_gears())
		if n != Run.overdrive:
			Run.overdrive = n
			Run.rebuild_sheets()


## Salt Flats (pass 69, lane SALT: the Salt's hero mutation): his charge to full at once, the sheet following now. True
## when it rose; false for a hero without momentum, a fallen one, or one already at full.
func max_momentum() -> bool:
	if not momentum or dead:
		return false
	var ramp: float = float(Run.momentum_def.get("ramp_seconds", 12.0))
	if _momentum_t >= ramp and Run.momentum >= 1.0:
		return false
	_momentum_t = ramp
	_momentum_sync = 0.25
	Run.momentum = 1.0
	Run.rebuild_sheets()
	return true


## Health back. `source` names a pickup heal for the Down! list (the Heart, a Cake Slice, the Healing Well); regen,
## lifesteal and the level patch pass none and are not listed. A heal that gave nothing back is not listed either.
func heal(amount: float, source: String = "") -> void:
	if dead:
		return
	# Afterglow (pass 54): every heal is `heal_mult` times its size (1 without the perk)
	amount *= heal_mult()
	var before := hp
	hp = minf(hp + amount, max_hp)
	# Snake Oil (pass 69): what the full bar could not take fills the overheal, up to its cap; Hot Springs hears it all
	var got := hp - before + _fill_overheal(amount - (hp - before))
	_note_heal_pulse(got)
	if RunAnalytics.I: RunAnalytics.I.healed(got, source)
	# a green number on him (pass 47): pickups, lifesteal and the level patch as they come, lifesteal's points merged
	if got >= 0.5 and DamageNumbers.I: DamageNumbers.I.hero_heal(got)
	if source != "" and got >= 0.5:
		damage_log.append({"t": Run.elapsed, "by": source, "id": "", "kind": "heal", "role": "", "colour": "", "fx": [],
			"raw": amount, "amount": got, "dealt": 0.0, "shield": 0.0, "note": "", "hp": hp, "fatal": false})
		_trim_log()
	damaged.emit(hp, max_hp)


## How much bigger every heal on him is (pass 54: the `heal_mult` player stat, Solenne's Afterglow; 1 without it).
func heal_mult() -> float:
	return maxf(sheet.get_stat("heal_mult", 1.0), 0.0) if sheet else 1.0


# ---------------------------------------------------------------- pass 69, the new passive items

## Snake Oil's cap (pass 69): the most health past full he can hold, `overheal` of his max HP (0 without the item).
func overheal_cap() -> float:
	return max_hp * maxf(sheet.get_stat("overheal", 0.0), 0.0) if sheet else 0.0


## Puts up to `extra` HP into the overheal (what a heal had left once the bar was full), under its cap; what it took.
func _fill_overheal(extra: float) -> float:
	if extra <= 0.0:
		return 0.0
	var room := maxf(overheal_cap() - overheal, 0.0)
	var took := minf(extra, room)
	overheal += took
	return took


## A hit's damage after the overheal has taken what it can of it (Snake Oil: the pink goes first).
func _soak_overheal(dealt: float) -> float:
	if overheal <= 0.0 or dealt <= 0.0:
		return dealt
	var took := minf(overheal, dealt)
	overheal -= took
	return dealt - took


## Hot Springs (pass 69): a heal of `got` HP counts towards the next pulse (only with `heal_pulse` held).
func _note_heal_pulse(got: float) -> void:
	if got > 0.0 and sheet and sheet.get_stat("heal_pulse", 0.0) > 0.0:
		_pulse_healed += got


## Hot Springs' pulse: what was healed since the last one goes out at once when the wait is over (HEAL_PULSE_GAP between
## two at most), heal_pulse_damage of it; Game hurts the creatures round him with it.
func _tick_heal_pulse(delta: float) -> void:
	_pulse_cd = maxf(_pulse_cd - delta, 0.0)
	if _pulse_healed <= 0.0 or _pulse_cd > 0.0:
		return
	var flat := sheet.get_stat("heal_pulse", 0.0) if sheet else 0.0
	if flat <= 0.0 or dead:
		_pulse_healed = 0.0
		return
	var healed := _pulse_healed
	_pulse_healed = 0.0
	_pulse_cd = HEAL_PULSE_GAP
	heal_pulsed.emit(heal_pulse_damage(flat, healed), healed)


## A heal pulse's damage (pass 69, Hot Springs): `flat` plus HEAL_PULSE_PER_HP for every HP healed, HEAL_PULSE_CAP at most.
static func heal_pulse_damage(flat: float, healed: float) -> float:
	return minf(flat + HEAL_PULSE_PER_HP * maxf(healed, 0.0), HEAL_PULSE_CAP)


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
	# Hang Time (pass 70): nothing reaches him in the air, and nothing shows or is logged
	if airborne:
		last_outcome = "immune"
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
		# Counterpunch (pass 69): the next attack is armed and the boost starts, before the evade is told (Game's burst)
		Run.counterpunch_evaded()
		evaded.emit()
		last_outcome = "evaded"
		if DamageNumbers.I: DamageNumbers.I.hero_dodge()
		# pass 87 (lane FIXES): he turns see-through for a second
		_evade_ghost_start()
		return
	# pass 95 (lane BREATH): from here the hit lands (on the star, the shield or his health): his stillness is broken
	_note_hit_for_still()
	# Marshal's Star (pass 70, lane LINES): a ready star takes the whole hit
	if _star_block(amount, info):
		return
	# damage reduction (pass 43): a share of every hit, capped so nothing makes him immune; Gas Mask (pass 48) adds a
	# point for every poisoned creature alive, up to its cap (Run.gas_mask_dr), under the same cap
	var dr := clampf(sheet.get_stat("damage_reduction", 0.0) + Run.gas_mask_dr(), 0.0, 0.8)
	var dealt: float = amount * (1.0 - dr)
	invuln = sheet.get_stat("hit_invuln", 0.25)
	# Unbroken (pass 46, Ironwood): a hit never stops his healing (Siesta's either, pass 47)
	if not Run.has_perk("unbroken"):
		# never under the floor (pass 61: Ironwood's delay shrinks every level; the sheet floors it as well)
		regen_hold = maxf(sheet.get_stat("regen_delay", REGEN_HOLD_AFTER_HIT), float(StatSheet.STAT_FLOORS["regen_delay"]))
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
	# Snake Oil (pass 69): the overheal takes the hit before his health
	hp -= _soak_overheal(dealt)
	# Last Stand (pass 69): a hit that leaves him low slows the clock (told before `hit`, so its hit-stop stays out)
	if hp > 0.0 and Run.last_stand_check(hp, max_hp):
		last_stand.emit()
	_log_hit(amount, dealt, 0.0, info, "")
	# Hush Money (pass 47c): every hit that reaches his health pays
	var paid := int(round(sheet.get_stat("gold_on_hit", 0.0)))
	if paid > 0:
		Run.add_gold(paid, "hush_money")
	if DamageNumbers.I: DamageNumbers.I.hero_hurt(dealt)
	# Buck's charge (pass 67): a hit that lands knocks off `hit_loss` of it (half; 1.0, the default, is the old full
	# reset) and drops every Overdrive gear; an evaded, shielded or immune hit returned above and keeps both
	if momentum and (_momentum_t > 0.0 or _over_t > 0.0 or Run.overdrive > 0):
		var ramp: float = float(Run.momentum_def.get("ramp_seconds", 12.0))
		_momentum_t *= 1.0 - clampf(float(Run.momentum_def.get("hit_loss", 1.0)), 0.0, 1.0)
		Run.momentum = _momentum_t / maxf(ramp, 0.1)
		_over_t = 0.0
		Run.overdrive = 0
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


# ---------------------------------------------------------------- pass 87 (lane FIXES): the evade shows
## Garry: "How do we show Player Evading? Should be that there is a text 'Evade' that flies out of the hero (just like
## with the 'Block') and hero should become half transparent for a second". An evaded hit says EVADE over him
## (DamageNumbers.hero_dodge) and turns him see-through: EVADE_GHOST_ALPHA for EVADE_GHOST_HOLD seconds, then easing back
## to whole by EVADE_GHOST_TIME (BillboardSprite.set_fade). Another evade starts the second again from the top; it never
## adds up, so he is never fainter than EVADE_GHOST_ALPHA. The blink after a hit (invuln) still hides him on its beats.
const EVADE_GHOST_TIME := 1.0
const EVADE_GHOST_HOLD := 0.7
const EVADE_GHOST_ALPHA := 0.5
## Seconds of the see-through left (0: whole).
var evade_ghost_t := 0.0


## How opaque he is with `left` seconds of the see-through to go: EVADE_GHOST_ALPHA through the hold, then a smooth way
## back to 1 over the rest of EVADE_GHOST_TIME.
static func evade_ghost_alpha(left: float) -> float:
	if left <= 0.0:
		return 1.0
	var since := EVADE_GHOST_TIME - minf(left, EVADE_GHOST_TIME)
	if since <= EVADE_GHOST_HOLD:
		return EVADE_GHOST_ALPHA
	var k := clampf((since - EVADE_GHOST_HOLD) / maxf(EVADE_GHOST_TIME - EVADE_GHOST_HOLD, 0.001), 0.0, 1.0)
	return lerpf(EVADE_GHOST_ALPHA, 1.0, smoothstep(0.0, 1.0, k))


func _evade_ghost_start() -> void:
	evade_ghost_t = EVADE_GHOST_TIME
	if sprite:
		sprite.set_fade(EVADE_GHOST_ALPHA)


func _tick_evade_ghost(delta: float) -> void:
	if evade_ghost_t <= 0.0:
		return
	evade_ghost_t = maxf(evade_ghost_t - delta, 0.0)
	if sprite:
		sprite.set_fade(evade_ghost_alpha(evade_ghost_t))


func _evade_ghost_clear() -> void:
	evade_ghost_t = 0.0
	if sprite:
		sprite.set_fade(1.0)


# ---------------------------------------------------------------- pass 70 (lane LINES): Marshal's Star
## The star over his head (core/systems/StarGuard.gd), made the first time his sheet holds `star_block_every`.
var star_guard: StarGuard = null


func _star_guard_sync() -> void:
	if star_guard == null and is_inside_tree() and sheet != null and sheet.get_stat("star_block_every", 0.0) > 0.0:
		star_guard = StarGuard.new()
		star_guard.name = "StarGuard"
		add_child(star_guard)


## A hit the star takes (pass 70): no damage and no shove of its own (a blast's throw still carries him), BLOCK over him,
## the blink after a hit, logged as the star's. True when it blocked.
func _star_block(amount: float, info: Dictionary) -> bool:
	if star_guard == null or not star_guard.try_block():
		return false
	invuln = maxf(invuln, sheet.get_stat("hit_invuln", 0.25))
	_log_hit(amount, 0.0, 0.0, info, "star")
	last_outcome = "shield"
	if DamageNumbers.I: DamageNumbers.I.hero_block()
	return true


## A hit's words for the Down! list (pass 88): when no push reaches him (pass 89: the map's hero_special_knock at 0 with
## the debug switch off; only the special attacks carry the push words) "knocked back" and "thrown" are left out.
func _logged_fx(info: Dictionary) -> Array:
	var fx: Array = (info.get("fx", []) as Array).duplicate()
	if knock_share(true) <= 0.0:
		fx = fx.filter(func(w) -> bool: return str(w) != "knocked back" and str(w) != "thrown")
	return fx


func _log_hit(raw: float, dealt: float, shield: float, info: Dictionary, note: String) -> void:
	damage_log.append({"t": Run.elapsed, "by": str(info.get("by", "something")), "id": str(info.get("id", "")),
		"kind": str(info.get("kind", "melee")), "role": role_of(info), "colour": colour_of(info.get("colour", "")),
		"fx": _logged_fx(info), "raw": raw, "dealt": dealt, "shield": shield, "note": note,
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
			"star":
				# pass 73 (lane CARDS): the card's own name (Tin Star's evolution is a fortune card now)
				what = "blocked by %s (%d)" % [PassiveDef.display_name_of("marshals_star", "Marshal's Star"), roundi(raw)]
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


## Wading (pass 80, lane OASIS; Garry: "make the water slow everyone down when they walk though it, not by a lot, just
## 10%"): his walking speed's factor, 1 - the map's water_slow (WaveTimeline, 0.1) while he stands in any lake (the map's
## in_water) on its floor; 1 in the air (Hang Time's flight, or more than WADE_AIR m over the ground: a launch, a leap),
## down, or with no map. It scales the stick's walk only: a shove, a knockback or a rope's pull (_kb) is never slowed.
## The rocketeer's rocket keeps to max_speed (his dry speed), so he does not outrun it by wading.
const WADE_AIR := 0.35
var _wade_holder: Node = null


func _wade_mult() -> float:
	if airborne or dead:
		return 1.0
	var m := _wade_map()
	if m == null or not m.has_method("in_water"):
		return 1.0
	var at := global_position
	if not bool(m.call("in_water", at)):
		return 1.0
	if m.has_method("height_at") and at.y > float(m.call("height_at", at.x, at.z)) + WADE_AIR:
		return 1.0
	return 1.0 - water_slow()


## The map's water_slow (pass 80): its timeline's, else WaveTimeline.WATER_SLOW_DEFAULT; held to 0..0.95.
static func water_slow() -> float:
	var tl: WaveTimeline = Run.map.timeline if Run.map else null
	return clampf(tl.water_slow if tl else WaveTimeline.WATER_SLOW_DEFAULT, 0.0, 0.95)


## The map he walks on (pass 80): the nearest ancestor's `map` (Game.map; a holder or two up is allowed), the holder found
## once; null when there is none (the title's stage, a bare test).
func _wade_map() -> Node:
	if _wade_holder == null or not is_instance_valid(_wade_holder):
		_wade_holder = null
		var p := get_parent()
		var hops := 0
		while p != null and hops < 3:
			if "map" in p:
				_wade_holder = p
				break
			p = p.get_parent()
			hops += 1
	if _wade_holder == null:
		return null
	var m = _wade_holder.get("map")
	return m if is_instance_valid(m) and m is Node else null


## The leash rule on its own: a step in `dir` when the thrower lies back along `away` (from it to the hero).
static func leash_of(dir: Vector3, away: Vector3, away_speed: float) -> float:
	var a := Vector3(away.x, 0.0, away.z)
	var flat := Vector3(dir.x, 0.0, dir.z)
	if a.length_squared() < 0.0001 or flat.length_squared() < 0.0001:
		return 1.0
	var pull := clampf(flat.normalized().dot(a.normalized()), 0.0, 1.0)
	return 1.0 - (1.0 - away_speed) * pull


## The spawn beam's view (pass 64): the front, idle, not mirrored; kept until he first moves.
func face_camera() -> void:
	_view = "_f"
	_flip = false
	var anim := _anim_for("idle")
	if sprite and sprite.has_animation(anim):
		sprite.play(anim)
		sprite.set_flip(false)


## Touching down (pass 64): a soft squash that springs back over `seconds`.
func land_settle(seconds: float) -> void:
	_land_len = maxf(seconds, 0.01)
	_land_t = _land_len


## The landing squash now (0 at rest): it starts from nothing (no one-frame snap after the fall), squashes to about
## LAND_SQUASH, springs a little past and dies away.
func land_squash() -> float:
	if _land_t <= 0.0 or _land_len <= 0.0:
		return 0.0
	var p := 1.0 - _land_t / _land_len
	return LAND_SQUASH * sin(p * TAU) * (1.0 - p) * 1.4


## The strip may lack some views (older art): fall back along the nearest available direction.
func _anim_for(base: String) -> String:
	var chain: Array = {"": [""], "_bd": ["_bd", "_s", ""], "_s": ["_s", "_bd", "_fd", ""], "_fd": ["_fd", "_s", "_f"], "_f": ["_f", "_fd", ""]}.get(_view, [""])
	for suffix in chain:
		if sprite.has_animation(base + suffix):
			return base + suffix
	return base


func _die() -> void:
	dead = true
	# a flight ends with him (pass 70): he falls as the dead do
	airborne = false
	velocity = Vector3.ZERO
	_kb = Vector3.ZERO
	sprite.set_squash(1.0, 1.0)
	sprite.set_roll(0.0)
	sprite.set_flash(0.0)
	sprite.visible = true
	_evade_ghost_clear()
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


# ---------------------------------------------------------------- Hang Time's flight (pass 70, lane TRAMP)

## A trampoline throws him (core/systems/Trampoline.gd, Fadeaway's Hang Time): trampoline_launch sends him up and along
## an arc whose top is `height` m over the take-off and which lasts `air_time` s on level ground (up at 4 h / T under his
## own gravity 8 h / T^2), carried `distance` m along `dir` (the way he was walking). In the air the stick adds
## `air_control` of his walking speed to the arc (he bends it, never stops it) and he faces the way he flies. Nothing
## reaches him up there: take_damage, shoves, pulls and blasts pass him by (knock_immune). He lands where the sand meets
## him: a squash, `air_landed` (the trampoline's dust ring), and the usual thud (pl_land). The camera rises AIR_CAMERA of
## the way with him (camera_y), so the jump reads on the screen.
signal air_launched
signal air_landed(at: Vector3)
const AIR_CAMERA := 0.3
const AIR_SAFETY := 3.0     # a flight that has not met the ground after this many air times ends anyway
var airborne := false
var air_flights := 0
var _air_t := 0.0
var _air_time := 1.1
var _air_h := 4.0
var _air_g := 24.0
var _air_v := Vector3.ZERO
var _air_control := 0.35
var _air_from_y := 0.0


## Throws him (see above). False when he cannot fly now: down, in the spawn beam, or already in the air.
func trampoline_launch(dir: Vector3, height: float, distance: float, air_time: float, air_control: float) -> bool:
	if dead or cinematic or airborne:
		return false
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = forward()
	flat = flat.normalized()
	_air_time = maxf(air_time, 0.2)
	_air_h = maxf(height, 0.1)
	_air_g = 8.0 * _air_h / (_air_time * _air_time)
	_air_v = flat * maxf(distance, 0.0) / _air_time
	_air_control = clampf(air_control, 0.0, 1.0)
	_air_t = 0.0
	_air_from_y = global_position.y
	airborne = true
	air_flights += 1
	velocity = Vector3(_air_v.x, 4.0 * _air_h / _air_time, _air_v.z)
	_kb = Vector3.ZERO
	_stick_lock = 0.0
	facing = atan2(-flat.x, -flat.z)
	_stop_still()
	jumped.emit()
	air_launched.emit()
	return true


## The flat speed in the air: the arc's own, plus the stick's walking speed (`planar`, as the ground would have moved
## him) at `air_control` of it; he turns to face the way he flies.
func _air_planar(delta: float, planar: Vector3, prev_facing: float) -> Vector3:
	var v := _air_v + Vector3(planar.x, 0.0, planar.z) * _air_control
	if v.length_squared() > 0.01:
		facing = lerp_angle(prev_facing, atan2(-v.x, -v.z), clampf(delta * 10.0, 0.0, 1.0))
	return v


## The flight's clock after the move: he lands once the ground has him (not in the first frames, while he is still
## leaving it), or when the flight has run far past its time (a safety).
func _tick_air(delta: float, on_floor: bool) -> void:
	_air_t += delta
	if (on_floor and _air_t > 0.08 and velocity.y <= 0.5) or _air_t > _air_time * AIR_SAFETY:
		_air_land()


func _air_land() -> void:
	airborne = false
	land_settle(0.32)
	air_landed.emit(global_position)


## The look in the air: stretched leaving and coming down, round at the top; his shadow on the sand shrinks as he rises.
func _air_look() -> void:
	var p := clampf(_air_t / _air_time, 0.0, 1.0)
	var up := 4.0 * p * (1.0 - p)
	var s := 0.9 * (1.0 - 0.45 * up)
	shadow_scale = Vector3(s, 1, s * 0.7)
	shadow.scale = shadow_scale
	var st := 0.16 * absf(cos(PI * p))
	sprite.set_squash(1.0 - st * 0.5, 1.0 + st)


## The height the camera rides at (CameraRig): his own on the ground; in the air AIR_CAMERA of the way up from where he
## left the ground, so the jump shows as a jump.
func camera_y() -> float:
	if not airborne:
		return global_position.y
	return _air_from_y + (global_position.y - _air_from_y) * AIR_CAMERA


## How high over his take-off he is now, from the arc's clock (0 on the ground).
func air_height() -> float:
	if not airborne:
		return 0.0
	var p := clampf(_air_t / _air_time, 0.0, 1.0)
	return _air_h * 4.0 * p * (1.0 - p)

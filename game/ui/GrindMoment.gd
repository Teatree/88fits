## Pass 121 (lane GRIND; Garry: "Grindstone - should be a 1 time use item. And there should be an animation sequence
## showing a weapon being upgraded. It's one time use, no upgrades, player gets only one ever."): the Grindstone's show, a
## screen of the one-screen rule (Game.Modal.GRIND) while the run stands paused behind it (ui/DrumMoment.gd is its model).
## The Grindstone has done its deed by the time the show opens (Run._grindstone, Run.grind_used: the weakest weapon one
## level up, or a ready one evolved); the show tells it:
## - spin (0 .. press_at): a dusk falls over the world and a grinding wheel, drawn face-on in its wooden frame over its
##   trough, pops in at the screen's middle and spins up, its crank turning with it; the weapon's icon flies in from its
##   HUD slot (from below without one) and turns its edge to the rim;
## - grind (press_at .. reveal_at): the icon pressed to the rim, stroking along it, a shower of sparks off the contact
##   (additive streaks under gravity, white-hot to red), the stone's grain smearing with the speed, the grinding loop;
## - reveal (reveal_at): the wheel gives way to the weapon's plate (WPlate, its level's colour) in a sunburst, its name
##   over it. A level: its stars under it; stamp_after later the new star stamps in, the plate takes the new level's
##   colour and "LEVEL 2 > 3" slams under it. An evolution: the old plate shakes and flashes faster and faster, and
##   evolve_after later bursts into the evolved one (the dark plate in its brass ring, the evolved icon), "EVOLVED" over
##   it, the new name under it and the old one under that;
## - then it fades over the last fade_out seconds (`seconds` for a level, `evolve_seconds` for an evolution) and
##   `finished`.
## Every number is the item's params.grind.moment (content/passives/grindstone/grindstone.json), with these defaults.
## A tap hurries it (hurry: straight to the reveal, then to the stamp or the burst, then, hurry_guard after it, to the
## fade; each one RunReplay records as "grind_hurry"); every touch is swallowed (touches_eaten). It counts its own real
## seconds on the frame's delta as a replay records it (Lockstep.dt), so a replay plays it frame for frame. skip() ends
## it at once (tests, tools); seek(t) jumps the clock quietly (captures). Its sounds play on its own players (the run's
## are stopped and the music held while it plays: Game._open_grind).
## Pass 123 (lane RUN_C), under Royale (Garry: "Grindstone moment: keep the wheel and sparks; the weapon in the
## new item frame, its title and LEVEL / EVOLVED stamp in the new kit's type"): the dusk, the wheel, its crank and trough,
## the sparks, the flashes and every beat are today's; the weapon's plate is the kit's item frame (WPlate under Royale: its
## level's rarity, an evolution's black face, rainbow rim and EVO plaque); GRINDSTONE, the weapon's name and LEVEL n in
## cream Ultra with the kit's navy edge (DrumMoment.kit_line), the line under the title in the secondary blue, the new
## level's number and its arrow in the kit's gold with its bevel, EVOLVED in the epic purple (the kit's tag table: an
## evolution is purple), the stars the kit's (gold, the new one cream, the rest slate, every one stroked navy), the burst's
## rays gold (purple after an evolution) and its slap lines navy and cream. Wanted is drawn as before.
class_name GrindMoment
extends Control

signal finished

## the wheel's middle (a share of the screen's height), its radius and the icon held to it (shares of the width)
const WHEEL_Y := 0.49
const WHEEL_R := 0.27
const ICON_W := 0.27
## where the icon meets the rim (radians, screen space: -PI/2 is the top): a little left of the top, so the sparks fly
## right over the wheel's crown and fall away on its right
const CONTACT := -1.78
## the result's plate (a share of the width) and its middle (a share of the height)
const PLATE_W := 0.31
const PLATE_Y := 0.47
const TITLE_PX := 96
const SUB_PX := 34
const NAME_PX := 70
const LEVEL_PX := 80
const EVOLVED_PX := 124
const STAR_PX := 74.0
## the wheel's top speed (radians a second) and how fast the sparks fall (px/s^2)
const SPIN_MAX := 16.0
const GRAVITY := 2600.0
## the icon's stroke along the rim: its reach (px) and its period (s)
const STROKE_PX := 16.0
const STROKE_T := 0.46
const STONE := Color("98876f")
const STONE_DARK := Color("62543f")
const STONE_LIGHT := Color("c9b898")
const WOOD := Color("8a5a2b")
const WOOD_DARK := Color("5e3b1a")
const IRON := Color("3d3833")
const HOT := Color(1.0, 0.97, 0.82)
const SPARK := Color(1.0, 0.68, 0.22)
const SPARK_RED := Color(0.86, 0.22, 0.06)
const DUSK := Color(0.12, 0.08, 0.05)
## how dark the dusk over the world is
const DUSK_A := 0.86

var playing := false
## seconds into the show
var t := 0.0
## touches swallowed while it played, hurries taken, sparks thrown (tests, touch_audit, captures)
var touches_eaten := 0
var hurries := 0
var sparks_thrown := 0
## what it shows: the weapon now held, the one it worked on, the levels, whether it evolved (Run.grind_used)
var info: Dictionary = {}
var evolved := false
## the stamp (a level) or the burst (an evolution) has happened
var stamped := false
var title := ""
var from_def: WeaponDef = null
var to_def: WeaponDef = null
var level_from := 1
var level_to := 2

var _seconds := 3.0
var _fade_in := 0.28
var _fade_out := 0.35
var _press_at := 0.62
var _reveal_at := 1.8
var _stamp_at := 2.08
var _hurry_guard := 0.3
var _rate := 140.0
var _snd: Dictionary = {}
var _from_rect := Rect2()
var _theta := 0.0
var _omega := 0.0
var _sparks: Array = []          # {p: Vector2, v: Vector2, age, life, w}
var _spark_acc := 0.0
var _shake := 0.0
var _shake_v := Vector2.ZERO
var _flash := 0.0
var _flashes: Array = []         # the evolution's quickening flashes: seconds after the reveal
var _flash_i := 0
var _said: Dictionary = {}
var _quiet := false
var _rng := RandomNumberGenerator.new()
var _grain: Array = []           # [angle, radius share, size, light?] the stone's specks
var _glow: GradientTexture2D
var _sparks_layer: Control
var _top: Control
var _plate: WPlate
var _loop: AudioStreamPlayer
var _one: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 256
	_glow.height = 256
	# the sparks glow: added onto what is under them
	_sparks_layer = Control.new()
	_sparks_layer.name = "Sparks"
	_sparks_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks_layer.material = mat
	add_child(_sparks_layer)
	_sparks_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sparks_layer.draw.connect(_draw_sparks)
	_plate = WPlate.new()
	_plate.name = "Plate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.visible = false
	add_child(_plate)
	# the words, the stars, the flashes and the ink bursts over the plate
	_top = Control.new()
	_top.name = "Top"
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	_top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top.draw.connect(_draw_top)
	_loop = AudioStreamPlayer.new()
	_loop.bus = "SFX"
	add_child(_loop)
	for k in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_one.append(p)


## Plays the show for `p_info` (Run.grind_used: id, from, level_from, level_to, evolved) with the numbers of `moment`
## (the item's params.grind.moment); `from_rect` is the weapon's HUD slot, where its icon flies in from (none: below).
func open(p_info: Dictionary, moment: Dictionary = {}, from_rect: Rect2 = Rect2()) -> void:
	info = p_info.duplicate()
	evolved = bool(info.get("evolved", false))
	to_def = Registry.weapon(str(info.get("id", "")))
	from_def = Registry.weapon(str(info.get("from", info.get("id", ""))))
	if from_def == null:
		from_def = to_def
	level_from = maxi(int(info.get("level_from", 1)), 1)
	level_to = maxi(int(info.get("level_to", level_from + 1)), 1)
	var m := moment
	_seconds = maxf(float(m.get("evolve_seconds" if evolved else "seconds", 3.5 if evolved else 3.0)), 0.5)
	_fade_in = clampf(float(m.get("fade_in", 0.28)), 0.01, _seconds * 0.4)
	_fade_out = clampf(float(m.get("fade_out", 0.35)), 0.01, _seconds * 0.4)
	_press_at = clampf(float(m.get("press_at", 0.62)), 0.05, _seconds * 0.6)
	_reveal_at = clampf(float(m.get("reveal_at", 1.8)), _press_at + 0.05, _seconds - _fade_out - 0.2)
	_stamp_at = minf(_reveal_at + maxf(float(m.get("evolve_after" if evolved else "stamp_after", 0.6 if evolved else 0.28)), 0.05),
		_seconds - _fade_out - 0.1)
	_hurry_guard = maxf(float(m.get("hurry_guard", 0.3)), 0.0)
	_rate = maxf(float(m.get("sparks_per_second", 140.0)), 0.0)
	_snd = {}
	for k in ["grind", "grind_fallback", "press", "stamp", "level", "flash", "evolve"]:
		_snd[k] = str(m.get("sound_" + k, {"grind": "it_grind", "grind_fallback": "w_saw_loop", "press": "w_saw_hit",
			"stamp": "ui_stamp", "level": "ui_levelup", "flash": "ui_chest_knock", "evolve": "w_evo_reveal"}[k]))
	_from_rect = from_rect
	var stone: PassiveDef = Registry.passive("grindstone")
	title = (stone.display_name if stone else "Grindstone").to_upper()
	# the evolution's flashes come faster and faster up to the burst
	_flashes = []
	var span := _stamp_at - _reveal_at
	for f in [0.18, 0.42, 0.62, 0.78, 0.9]:
		_flashes.append(_reveal_at + span * float(f))
	_flash_i = 0
	t = 0.0
	_theta = 0.0
	_omega = 0.0
	_sparks.clear()
	_spark_acc = 0.0
	_shake = 0.0
	_flash = 0.0
	_said = {}
	stamped = false
	hurries = 0
	sparks_thrown = 0
	# the looks' dice (sparks, jitter, grain): the same show for the same weapon, every time
	_rng.seed = hash(str(info.get("from", "")) + ":" + str(info.get("id", "")))
	_make_grain()
	_plate.visible = false
	_plate.scale = Vector2.ONE
	_plate.modulate = Color.WHITE
	playing = true
	visible = true
	move_to_front()
	queue_redraw()
	_top.queue_redraw()
	_sparks_layer.queue_redraw()


## Its phase now: "spin", "grind", "reveal" (before the stamp or the burst), "stamped", "fade" (tests, captures).
func phase() -> String:
	if not playing:
		return ""
	if t >= _seconds - _fade_out:
		return "fade"
	if stamped:
		return "stamped"
	if t >= _reveal_at:
		return "reveal"
	if t >= _press_at:
		return "grind"
	return "spin"


## The beats in seconds (tests, captures): {press, reveal, stamp, fade, seconds}.
func beats() -> Dictionary:
	return {"press": _press_at, "reveal": _reveal_at, "stamp": _stamp_at, "fade": _seconds - _fade_out, "seconds": _seconds}


## A tap: before the reveal, straight to it; before the stamp (the burst), straight to that; hurry_guard after it, on to
## the fade. True when it moved the show on (RunReplay records it then as "grind_hurry", and a replay calls it again).
func hurry() -> bool:
	if not playing:
		return false
	var to := -1.0
	if t < _reveal_at:
		to = _reveal_at
	elif t < _stamp_at:
		to = _stamp_at
	elif t >= _stamp_at + _hurry_guard and t < _seconds - _fade_out:
		to = _seconds - _fade_out
	if to < 0.0:
		return false
	RunReplay.note("grind_hurry")
	hurries += 1
	_jump(to)
	return true


## Ends it now (a test's or a tool's hand), as after a whole one.
func skip() -> void:
	if playing:
		_finish()


## The clock jumped to `p_t` quietly in steps (captures: the sparks, the wheel and the beats where the clock says).
func seek(p_t: float) -> void:
	_quiet = true
	while playing and t < p_t - 0.0001:
		advance(minf(1.0 / 60.0, p_t - t))
	_quiet = false
	queue_redraw()
	_top.queue_redraw()
	_sparks_layer.queue_redraw()


## Where the result's plate is on the screen (the gate flies it into the weapon's slot from there).
func result_rect() -> Rect2:
	var side := size.x * PLATE_W
	var c := Vector2(size.x * 0.5, size.y * PLATE_Y)
	return Rect2(get_global_rect().position + c - Vector2(side, side) * 0.5, Vector2(side, side))


func _jump(to: float) -> void:
	# the beat landed on happens (its sounds, the plate's change), the ones jumped over in silence; the sparks in flight go out
	if to >= _reveal_at and t < _reveal_at:
		_sparks.clear()
	# the evolution's flashes jumped over pass in silence
	while evolved and _flash_i < _flashes.size() and to >= float(_flashes[_flash_i]):
		_flash_i += 1
	t = to
	_beats()
	_place_plate()
	queue_redraw()
	_top.queue_redraw()
	_sparks_layer.queue_redraw()


func _finish() -> void:
	playing = false
	visible = false
	_stop_sounds()
	finished.emit()


func _stop_sounds() -> void:
	if _loop and _loop.playing:
		_loop.stop()
	for p: AudioStreamPlayer in _one:
		if p.playing:
			p.stop()


## The loop never outlives the show.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_stop_sounds()


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	if not playing:
		return
	# real seconds: a hit-stop that slowed the clock does not stretch the show (as the drum's)
	advance(delta / maxf(Lockstep.time_scale(), 0.01))


## The show `dt` seconds on: the wheel's turn, the sparks, the beats, the end.
func advance(dt: float) -> void:
	if not playing:
		return
	t += dt
	# the wheel: up to speed by the press, full through the grind, slowing after the reveal
	var want := SPIN_MAX * _ease_in(clampf(t / _press_at, 0.0, 1.0))
	if t >= _reveal_at:
		want = SPIN_MAX * 0.25
	_omega = lerpf(_omega, want, clampf(dt * 6.0, 0.0, 1.0))
	_theta = fmod(_theta + _omega * dt, TAU * 64.0)
	# the sparks off the contact while the blade is on the stone
	if t >= _press_at and t < _reveal_at and _rate > 0.0:
		var stroke := absf(cos(TAU * (t - _press_at) / STROKE_T))
		_spark_acc += _rate * (0.55 + 0.45 * stroke) * dt
		while _spark_acc >= 1.0:
			_spark_acc -= 1.0
			_emit_spark()
	var keep: Array = []
	for s: Dictionary in _sparks:
		s["age"] = float(s["age"]) + dt
		if float(s["age"]) >= float(s["life"]):
			continue
		var v: Vector2 = s["v"]
		v.y += GRAVITY * dt
		v *= 1.0 - minf(dt * 0.6, 0.5)
		s["v"] = v
		s["p"] = (s["p"] as Vector2) + v * dt
		keep.append(s)
	_sparks = keep
	_beats()
	_shake = maxf(_shake - dt * 3.2, 0.0)
	var grind_shake := 3.0 if t >= _press_at and t < _reveal_at else 0.0
	# (the player's screen shake setting scales it, as the camera's)
	var amp := (16.0 * _shake * _shake + grind_shake) * clampf(float(Settings.screen_shake), 0.0, 2.0)
	_shake_v = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * amp
	_flash = maxf(_flash - dt * 3.5, 0.0)
	_place_plate()
	if t >= _seconds:
		_finish()
		return
	queue_redraw()
	_top.queue_redraw()
	_sparks_layer.queue_redraw()


## The beats as the clock passes them (once each): the press, the reveal, the evolution's flashes, the stamp or burst.
func _beats() -> void:
	if t >= _press_at and not _said.has("press"):
		_said["press"] = true
		if t < _reveal_at:
			_sfx(str(_snd.get("press", "")))
			_start_loop()
			_shake = maxf(_shake, 0.45)
	if t >= _reveal_at and not _said.has("reveal"):
		_said["reveal"] = true
		if _loop.playing:
			_loop.stop()
		_plate.for_def(from_def if from_def else to_def, size.x * PLATE_W, false, level_from)
		_plate.set_kind_mark_for(from_def if from_def else to_def)
		_plate.shadow = 10
		_plate.visible = true
		_flash = 1.0
		_shake = maxf(_shake, 0.6)
	if evolved:
		while _flash_i < _flashes.size() and t >= float(_flashes[_flash_i]):
			_flash_i += 1
			_flash = maxf(_flash, 0.55 + 0.08 * _flash_i)
			if _flash_i >= 3:
				_sfx(str(_snd.get("flash", "")))
	if t >= _stamp_at and not stamped:
		stamped = true
		_flash = 1.0
		_shake = 1.0
		if evolved:
			_plate.for_def(to_def, size.x * PLATE_W, false, maxi(level_to, 1))
			_plate.set_kind_mark_for(to_def)
			_sfx(str(_snd.get("evolve", "")))
		else:
			_plate.for_def(to_def, size.x * PLATE_W, false, level_to)
			_plate.set_kind_mark_for(to_def)
			_sfx(str(_snd.get("stamp", "")))
			_sfx(str(_snd.get("level", "")))


func _emit_spark() -> void:
	var c := wheel_center()
	var r := wheel_radius()
	var at := c + Vector2.from_angle(CONTACT) * r
	# the rim's way at the contact (the wheel turns clockwise on the screen), lifted a little and spread
	var dir := Vector2(-sin(CONTACT), cos(CONTACT)).rotated(_rng.randf_range(-0.42, 0.18))
	var speed := _rng.randf_range(700.0, 1550.0)
	var hot := _rng.randf() < 0.18
	_sparks.append({"p": at + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-4.0, 4.0)), "v": dir * speed,
		"age": 0.0, "life": _rng.randf_range(0.32, 0.72) * (1.25 if hot else 1.0), "w": _rng.randf_range(3.0, 5.5) * (1.4 if hot else 1.0)})
	sparks_thrown += 1


func _make_grain() -> void:
	_grain.clear()
	for k in 46:
		_grain.append([_rng.randf() * TAU, sqrt(_rng.randf_range(0.04, 0.86)), _rng.randf_range(2.0, 5.5), _rng.randf() < 0.4])


func _start_loop() -> void:
	if _quiet or Run.sim_mode:
		return
	var stream: AudioStream = null
	var row: Dictionary = {}
	for id in [str(_snd.get("grind", "")), str(_snd.get("grind_fallback", ""))]:
		if id == "":
			continue
		row = Registry.soundmap.entry(id)
		stream = row.get("stream") if not row.is_empty() else null
		if stream != null:
			break
	if stream == null:
		return
	# looped as Audio.play_loop loops a row (a longer grind in the JSON goes on sounding)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.mix_rate * wav.get_length()))
	_loop.stream = stream
	_loop.volume_db = float(row.get("volume_db", 0.0))
	_loop.play()


func _sfx(id: String) -> void:
	if id == "" or _quiet or Run.sim_mode:
		return
	var row := Registry.soundmap.entry(id)
	var stream: AudioStream = row.get("stream") if not row.is_empty() else null
	if stream == null:
		return
	for p: AudioStreamPlayer in _one:
		if not p.playing:
			p.stream = stream
			p.volume_db = float(row.get("volume_db", 0.0))
			p.play()
			return


func _input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion:
		var pressed: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
		if pressed:
			touches_eaten += 1
			hurry()
		get_viewport().set_input_as_handled()


func _gui_input(_event: InputEvent) -> void:
	if playing:
		accept_event()


# ---------------------------------------------------------------- where things are

func wheel_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * WHEEL_Y)


func wheel_radius() -> float:
	return size.x * WHEEL_R


## 0..1: in over fade_in, out over the last fade_out.
func alpha_at(time: float) -> float:
	var a_in := clampf(time / _fade_in, 0.0, 1.0)
	var a_out := clampf((_seconds - time) / _fade_out, 0.0, 1.0)
	return minf(1.0 - pow(1.0 - a_in, 2.0), a_out * a_out * (3.0 - 2.0 * a_out))


## The wheel's own fade and size: popping in with a little overshoot, giving way to the plate after the reveal.
func _wheel_look() -> Vector2:
	var sc := _back(clampf(t / maxf(_press_at * 0.6, 0.05), 0.0, 1.0), 0.72)
	var a := 1.0
	if t >= _reveal_at:
		var f := clampf((t - _reveal_at) / 0.3, 0.0, 1.0)
		a = 1.0 - f
		sc *= 1.0 + 0.12 * f
	return Vector2(sc, a)


## The icon's rect and turn while it is on its way and on the stone: [Rect2, angle].
func icon_pose() -> Array:
	var c := wheel_center()
	var r := wheel_radius()
	var side := size.x * ICON_W
	var contact := c + Vector2.from_angle(CONTACT) * r
	var tangent := Vector2(-sin(CONTACT), cos(CONTACT))
	var normal := Vector2.from_angle(CONTACT)
	# held up and back from the contact, its lower right corner on the stone, its edge turned to the rim
	var held := contact + normal * side * 0.34 - tangent * side * 0.2
	var ang := -0.32
	var come := _press_at - 0.36
	if t < _press_at:
		var src := _from_rect
		if src.size.x <= 0.0:
			src = Rect2(Vector2(size.x * 0.5 - side * 0.3, size.y + side * 0.2), Vector2(side * 0.6, side * 0.6))
		var f := clampf((t - come) / maxf(_press_at - come, 0.01), 0.0, 1.0)
		var e := _back(f, 0.0)
		var mid := src.get_center().lerp(held, e)
		var s := lerpf(src.size.x, side, clampf(e, 0.0, 1.2))
		return [Rect2(mid - Vector2(s, s) * 0.5, Vector2(s, s)), lerpf(0.0, ang, f)]
	# on the stone: stroking along the rim, pressed in at each pass, jittering
	var k := sin(TAU * (t - _press_at) / STROKE_T)
	var press := absf(cos(TAU * (t - _press_at) / STROKE_T)) * 6.0
	var jit := Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5)) if t < _reveal_at else Vector2.ZERO
	var at := held + tangent * k * STROKE_PX - normal * press + jit
	if t >= _reveal_at:
		# off the stone and into the plate
		var f2 := clampf((t - _reveal_at) / 0.16, 0.0, 1.0)
		at = at.lerp(Vector2(size.x * 0.5, size.y * PLATE_Y), f2)
	return [Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), ang + k * 0.03]


func _place_plate() -> void:
	if not _plate.visible:
		return
	var side := size.x * PLATE_W
	var c := Vector2(size.x * 0.5, size.y * PLATE_Y)
	_plate.side = side
	_plate.pivot_offset = Vector2(side, side) * 0.5
	var since := t - _reveal_at
	var sc := _back(clampf(since / 0.22, 0.0, 1.0), 0.6)
	var jig := Vector2.ZERO
	if evolved and not stamped:
		# the old plate shakes harder as the burst comes
		var f := clampf(since / maxf(_stamp_at - _reveal_at, 0.01), 0.0, 1.0)
		jig = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * (2.0 + 12.0 * f * f)
		sc *= 1.0 + 0.05 * f
	if stamped:
		var s2 := t - _stamp_at
		sc *= 1.0 + 0.32 * exp(-s2 / 0.08) * cos(TAU * 3.0 * s2)
	_plate.position = c - Vector2(side, side) * 0.5 + jig + _shake_v * 0.5
	_plate.scale = Vector2(sc, sc)
	var a := alpha_at(t)
	var w := 1.0 + 1.6 * _flash
	_plate.modulate = Color(w, w, w, a)


static func _ease_in(f: float) -> float:
	return f * f * (3.0 - 2.0 * f)


## An ease out with an overshoot (back), from `from` up to 1.
static func _back(f: float, from: float) -> float:
	var c := 1.7
	var e := 1.0 + (c + 1.0) * pow(f - 1.0, 3.0) + c * pow(f - 1.0, 2.0)
	return lerpf(from, 1.0, e)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not playing:
		return
	var vp := size
	var a := alpha_at(t)
	# the world stands still behind a dusk
	draw_rect(Rect2(Vector2.ZERO, vp), Color(DUSK, DUSK_A * a))
	var look := _wheel_look()
	var c := wheel_center() + _shake_v
	var r := wheel_radius() * look.x
	var wa := a * look.y
	if wa > 0.004:
		# a warm light behind the wheel, brighter at the contact while it grinds
		var heat := 1.0 if t >= _press_at and t < _reveal_at else 0.35
		var gr := r * 2.3
		draw_texture_rect(_glow, Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1.0, 0.55, 0.22, wa * (0.22 + 0.18 * heat)))
		_draw_wheel(c, r, wa)
	# the sunburst behind the plate after the reveal
	if t >= _reveal_at:
		_draw_burst(Vector2(vp.x * 0.5, vp.y * PLATE_Y), a)
	# the weapon's icon on its way, on the stone and off it into the plate
	var tex := from_def.icon if from_def else null
	if tex != null and t >= _press_at - 0.36 and t < _reveal_at + 0.16:
		var pose := icon_pose()
		var rr: Rect2 = pose[0]
		var heat2 := 0.0
		if t >= _press_at:
			heat2 = clampf((t - _press_at) / maxf(_reveal_at - _press_at, 0.01), 0.0, 1.0)
		var ia := a * (1.0 - clampf((t - _reveal_at) / 0.16, 0.0, 1.0))
		var flick := 0.08 * _rng.randf() if t >= _press_at and t < _reveal_at else 0.0
		var col := Color(1.0 + 0.45 * heat2 + flick, 1.0 + 0.25 * heat2 + flick, 1.0, ia)
		draw_set_transform(rr.get_center() + _shake_v, float(pose[1]), Vector2.ONE)
		# a hard ink shadow under it, then the icon
		draw_texture_rect(tex, Rect2(-rr.size * 0.5 + Vector2(8, 10), rr.size), false, Color(DUSK, 0.5 * ia))
		draw_texture_rect(tex, Rect2(-rr.size * 0.5, rr.size), false, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the title over it all and what it works on
	var font := W.slab()
	# under the HUD's strip (its clock and its slots)
	var ty := maxf(W.safe_top(), 0.0) + vp.y * 0.168
	_outlined(self, font, title, Vector2(vp.x * 0.5, ty), TITLE_PX, W.PAPER, a, 16, 7.0)
	if t < _reveal_at + 0.3 and from_def != null:
		var sub := Loc.t("ui.grind.sharpening", {"item": from_def.display_name.to_upper()})
		var sa := a * (1.0 - clampf((t - _reveal_at) / 0.3, 0.0, 1.0))
		# pass 123: under Royale the line under a title is the kit's secondary blue (gold is for what acts, coins, stars)
		_outlined(self, font, sub, Vector2(vp.x * 0.5, ty + TITLE_PX * 0.72), _fit(font, sub, SUB_PX, vp.x - 80.0), R.SECONDARY, sa, 10, 4.0)


## The grinding wheel face-on: its A-frame behind it, the stone (rim, face, grain that turns, a lit crown), the iron hub
## and the crank that turns with it, and the wooden trough in front of its foot.
func _draw_wheel(c: Vector2, r: float, a: float) -> void:
	var ink := Color(W.INK, a)
	# the frame: two legs from the axle to the ground and a plank across their feet
	var foot := c.y + r * 1.42
	for sx in [-1.0, 1.0]:
		var top := c + Vector2(sx * r * 0.1, 0.0)
		var bot := Vector2(c.x + sx * r * 0.78, foot)
		var n := (bot - top).normalized().orthogonal() * r * 0.075
		var leg := PackedVector2Array([top - n, top + n, bot + n, bot - n])
		draw_colored_polygon(_grow(leg, 6.0), ink)
		draw_colored_polygon(leg, Color(WOOD, a))
		draw_line(top + n * 0.4, bot + n * 0.4, Color(WOOD_DARK, a * 0.6), 3.0, true)
	var plank := Rect2(Vector2(c.x - r * 1.02, foot - r * 0.05), Vector2(r * 2.04, r * 0.14))
	draw_rect(plank.grow(5.0), ink)
	draw_rect(plank, Color(WOOD, a))
	# the stone: an ink ring, the rim, the face
	draw_circle(c, r + 7.0, ink, true, -1.0, true)
	draw_circle(c, r, Color(STONE_DARK, a), true, -1.0, true)
	draw_circle(c, r * 0.9, Color(STONE, a), true, -1.0, true)
	# the lit crown and the shaded foot (they stay where the light is: the stone turns under them)
	draw_arc(c, r * 0.74, PI * 1.08, PI * 1.62, 40, Color(STONE_LIGHT, a * 0.55), r * 0.2, true)
	draw_arc(c, r * 0.8, PI * 0.12, PI * 0.62, 32, Color(STONE_DARK, a * 0.35), r * 0.16, true)
	# the grain: rings with gaps and specks that turn with the stone, smeared as it speeds up
	var smear := clampf(_omega * 0.035, 0.0, 0.55)
	for ring in [[0.36, 0.0, 1.9], [0.55, 1.3, 2.4], [0.72, 2.6, 1.6], [0.83, 4.2, 2.8]]:
		var rad := r * float(ring[0])
		var a0 := _theta + float(ring[1])
		draw_arc(c, rad, a0, a0 + float(ring[2]) + smear * 2.0, 36, Color(STONE_DARK, a * 0.42), 3.0, true)
	for g: Array in _grain:
		var ga := float(g[0]) + _theta
		var gp := c + Vector2.from_angle(ga) * r * float(g[1])
		var gc := Color(STONE_LIGHT, a * 0.75) if bool(g[3]) else Color(STONE_DARK, a * 0.8)
		if smear > 0.06:
			draw_arc(c, r * float(g[1]), ga - smear, ga, 6, Color(gc, gc.a * 0.6), float(g[2]), true)
		else:
			draw_circle(gp, float(g[2]) * 0.6, gc, true, -1.0, true)
	# the rim's own edge, worn smooth: a pale line just inside the ink
	draw_arc(c, r - 3.0, 0.0, TAU, 96, Color(STONE_LIGHT, a * 0.35), 3.0, true)
	# the hub: iron, four bolts that turn with the stone, a brass cap
	draw_circle(c, r * 0.17 + 5.0, ink, true, -1.0, true)
	draw_circle(c, r * 0.17, Color(IRON, a), true, -1.0, true)
	for k in 4:
		var bp := c + Vector2.from_angle(_theta + PI * 0.5 * k + 0.4) * r * 0.115
		draw_circle(bp, r * 0.022, Color(W.AGED, a * 0.8), true, -1.0, true)
	# the crank on the near end of the axle: an iron arm round the turn and a wooden handle at its end
	var arm := Vector2.from_angle(_theta * 1.0 + 0.9) * r * 0.58
	draw_line(c, c + arm, ink, r * 0.075 + 8.0, true)
	draw_line(c, c + arm, Color(IRON, a), r * 0.075, true)
	draw_circle(c + arm, r * 0.075 + 5.0, ink, true, -1.0, true)
	draw_circle(c + arm, r * 0.075, Color(WOOD, a), true, -1.0, true)
	draw_circle(c + arm + Vector2(-r * 0.02, -r * 0.022), r * 0.028, Color(1, 1, 1, a * 0.3), true, -1.0, true)
	draw_circle(c, r * 0.07 + 4.0, ink, true, -1.0, true)
	draw_circle(c, r * 0.07, Color(W.BRASS, a), true, -1.0, true)
	# the trough in front of its foot: a wooden box with planks, a dark line of water
	var tr := Rect2(Vector2(c.x - r * 1.12, c.y + r * 0.66), Vector2(r * 2.24, r * 0.52))
	draw_rect(tr.grow(6.0), ink)
	draw_rect(tr, Color(WOOD, a))
	draw_rect(Rect2(tr.position, Vector2(tr.size.x, r * 0.07)), Color(WOOD_DARK, a))
	for k in range(1, 3):
		var yy := tr.position.y + tr.size.y * float(k) / 3.0
		draw_line(Vector2(tr.position.x + 6.0, yy), Vector2(tr.end.x - 6.0, yy), Color(WOOD_DARK, a * 0.75), 3.0, true)
	for sx in [0.08, 0.92]:
		var xx := tr.position.x + tr.size.x * float(sx)
		draw_circle(Vector2(xx, tr.position.y + tr.size.y * 0.32), 5.0, Color(IRON, a), true, -1.0, true)
		draw_circle(Vector2(xx, tr.position.y + tr.size.y * 0.72), 5.0, Color(IRON, a), true, -1.0, true)


## Brass rays turning slowly behind the plate (ember and longer for an evolution, after its burst).
func _draw_burst(c: Vector2, a: float) -> void:
	var since := t - _reveal_at
	var f := clampf(since / 0.25, 0.0, 1.0)
	var big := evolved and stamped
	var col := W.EMBER if big else W.BRASS
	# pass 123: the kit's gold, an evolution's purple
	col = (R.RARITY["epic"]["base"] as Color) if big else (R.role("gold")["bottom"] as Color)
	var n := 18 if big else 14
	var reach := size.x * (0.62 if big else 0.5) * (0.6 + 0.4 * f)
	var turn := since * 0.35
	var mid := Color(col, a * f * (0.42 if big else 0.34))
	var rim := Color(col, 0.0)
	for k in n:
		var a0 := turn + TAU * float(k) / float(n)
		var w := TAU / float(n) * 0.26
		# each ray fades out along its length
		var tri := PackedVector2Array([c, c + Vector2.from_angle(a0 - w) * reach, c + Vector2.from_angle(a0 + w) * reach])
		draw_polygon(tri, PackedColorArray([mid, rim, rim]))
	var gr := size.x * (0.42 if big else 0.34)
	draw_texture_rect(_glow, Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(col.lerp(Color.WHITE, 0.3), a * f * 0.45))


func _draw_sparks() -> void:
	if not playing:
		return
	var a := alpha_at(t)
	var off := _shake_v
	# the contact's glow while the blade is on the stone
	if t >= _press_at and t < _reveal_at:
		var at := wheel_center() + Vector2.from_angle(CONTACT) * wheel_radius() + off
		var pulse := 0.75 + 0.25 * absf(cos(TAU * (t - _press_at) / STROKE_T))
		var gr := wheel_radius() * 0.42 * pulse
		_sparks_layer.draw_texture_rect(_glow, Rect2(at - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1.0, 0.5, 0.15, 0.85 * a))
		var gr2 := gr * 0.4
		_sparks_layer.draw_texture_rect(_glow, Rect2(at - Vector2(gr2, gr2), Vector2(gr2, gr2) * 2.0), false, Color(1.0, 0.95, 0.75, a))
	for s: Dictionary in _sparks:
		var f := float(s["age"]) / float(s["life"])
		var v: Vector2 = s["v"]
		var p: Vector2 = (s["p"] as Vector2) + off
		var col := HOT.lerp(SPARK, clampf(f * 2.2, 0.0, 1.0)).lerp(SPARK_RED, clampf((f - 0.5) * 2.0, 0.0, 1.0))
		col.a = a * (1.0 - f * f)
		var tail := v * 0.03
		_sparks_layer.draw_line(p - tail, p, col, float(s["w"]) * (1.0 - 0.45 * f), true)
	# the flash at the reveal and at the stamp, from the plate
	if _flash > 0.01 and t >= _reveal_at:
		var c := Vector2(size.x * 0.5, size.y * PLATE_Y)
		var gr3 := size.x * (0.35 + 0.35 * (1.0 - _flash))
		_sparks_layer.draw_texture_rect(_glow, Rect2(c - Vector2(gr3, gr3), Vector2(gr3, gr3) * 2.0), false, Color(1.0, 0.85, 0.55, 0.7 * _flash * a))


func _draw_top() -> void:
	if not playing or t < _reveal_at:
		return
	var vp := size
	var a := alpha_at(t)
	var font := W.slab()
	var side := vp.x * PLATE_W
	var c := Vector2(vp.x * 0.5, vp.y * PLATE_Y)
	var since := t - _reveal_at
	var in_a := a * clampf(since / 0.15, 0.0, 1.0)
	# pass 123: the kit's navy and cream under Royale
	var ink: Color = R.NAVY
	var paper: Color = R.CREAM
	# ink burst lines round the plate at the reveal and at the stamp
	var burst_t := (t - _stamp_at) if stamped else since
	if burst_t < 0.2:
		var k := 1.0 - burst_t / 0.2
		var n := 16
		for i in n:
			var ang := TAU * float(i) / float(n) + 0.11
			var dir := Vector2.from_angle(ang)
			var jag := 0.85 + 0.3 * float((i * 7) % 5) / 4.0
			var r0 := side * (0.62 + 0.12 * (1.0 - k))
			var r1 := r0 + side * (0.18 + (0.22 if stamped else 0.12)) * jag * k
			_top.draw_line(c + dir * r0, c + dir * r1, Color(ink, a * k), 12.0 * k + 3.0, true)
			_top.draw_line(c + dir * r0, c + dir * r1, Color(paper, a * k), 5.0 * k + 1.5, true)
	var name_y := c.y - side * 0.5 - vp.y * 0.045
	var under_y := c.y + side * 0.5 + vp.y * 0.06
	if evolved:
		if stamped:
			var s2 := t - _stamp_at
			var sc := 1.0 + 0.5 * exp(-s2 / 0.09)
			_outlined(_top, font, Loc.t("ui.grind.evolved"), Vector2(c.x, name_y), EVOLVED_PX, W.EMBER, a * clampf(s2 / 0.08, 0.0, 1.0), 18, 7.0, sc)
			var nm := to_def.display_name.to_upper() if to_def else ""
			_outlined(_top, font, nm, Vector2(c.x, under_y + 10.0), _fit(font, nm, NAME_PX, vp.x - 80.0), W.PAPER, a, 14, 6.0)
			if from_def:
				var was := Loc.t("ui.grind.from", {"item": from_def.display_name})
				var sf := W.serif(600, true)
				var ww := sf.get_string_size(was, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
				# pass 123: Rubik italic in the kit's secondary blue on its navy edge under Royale
				_top.draw_string_outline(sf, Vector2(c.x - ww * 0.5, under_y + NAME_PX * 1.0 + 12.0), was, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 8, Color(ink, a))
				_top.draw_string(sf, Vector2(c.x - ww * 0.5, under_y + NAME_PX * 1.0 + 12.0), was, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(R.SECONDARY, a))
		else:
			var nm0 := from_def.display_name.to_upper() if from_def else ""
			_outlined(_top, font, nm0, Vector2(c.x, name_y), _fit(font, nm0, NAME_PX, vp.x - 80.0), W.PAPER, in_a, 14, 6.0)
		return
	# a level: the name over the plate, its stars under it, then the level
	var nm1 := to_def.display_name.to_upper() if to_def else ""
	_outlined(_top, font, nm1, Vector2(c.x, name_y), _fit(font, nm1, NAME_PX, vp.x - 80.0), W.PAPER, in_a, 14, 6.0)
	var total := maxi(to_def.max_level if to_def else 5, 1)
	var step := STAR_PX * 0.92
	var x0 := c.x - step * float(total - 1) * 0.5
	var sy := under_y + 6.0
	# pass 123: the kit's stars under Royale (gold held, the new one cream, the rest slate, every one stroked navy)
	var s_held: Color = WMarks.ROYALE_HELD
	var s_next: Color = WMarks.ROYALE_NEXT
	var s_empty: Color = WMarks.ROYALE_EMPTY
	for i in total:
		var sc2 := 1.0
		var fill := s_empty
		var held := i < level_from
		if held:
			fill = s_held
		elif i < level_to:
			if stamped:
				var s3 := t - _stamp_at
				fill = s_held
				sc2 = 1.0 + 0.9 * exp(-s3 / 0.1)
				WMarks.glow(_top, Vector2(x0 + step * i, sy), STAR_PX * 1.2, Color(s_held, in_a * 0.6 * exp(-s3 / 0.35)))
			else:
				# the star to come breathes in paper
				fill = s_next
				sc2 = 1.0 + 0.12 * sin(since * 14.0)
		var sw := 3.0
		WMarks.star(_top, Vector2(x0 + step * i, sy), STAR_PX * 0.5 * sc2, Color(fill, in_a), sw, Color(ink, in_a))
	# "LEVEL 2", and from the stamp "LEVEL 2 > 3" with the new number in brass, slammed in
	var ly := sy + STAR_PX * 1.45
	var word := Loc.t("ui.grind.level", {"level": str(level_from)})
	var px := LEVEL_PX
	var ww2 := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	if not stamped:
		_outlined(_top, font, word, Vector2(c.x, ly), px, W.PAPER, in_a, 14, 6.0)
		return
	var s4 := t - _stamp_at
	var lsc := 1.0 + 0.45 * exp(-s4 / 0.08)
	var num := str(level_to)
	var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var gap := px * 0.95
	var total_w := ww2 + gap + nw
	var left := c.x - total_w * 0.5
	_outlined(_top, font, word, Vector2(left + ww2 * 0.5, ly), px, W.PAPER, a, 14, 6.0)
	# the arrow, drawn (the slab face has no arrow)
	var ax := left + ww2 + gap * 0.5
	var ay := ly - px * 0.36
	var head := PackedVector2Array([Vector2(ax + px * 0.28, ay), Vector2(ax - px * 0.06, ay - px * 0.24), Vector2(ax - px * 0.06, ay + px * 0.24)])
	# (pass 123: the kit's gold on navy under Royale)
	var brass: Color = R.GOLD_TEXT
	_top.draw_line(Vector2(ax - px * 0.32, ay), Vector2(ax, ay), Color(ink, a), px * 0.16 + 8.0)
	_top.draw_colored_polygon(_grow(head, 5.0), Color(ink, a))
	_top.draw_line(Vector2(ax - px * 0.3, ay), Vector2(ax, ay), Color(brass, a), px * 0.16)
	_top.draw_colored_polygon(head, Color(brass, a))
	_outlined(_top, font, num, Vector2(left + ww2 + gap + nw * 0.5, ly), px, W.BRASS, a, 14, 6.0, lsc)


## A slab line centred on `at` (its baseline) on `ci` (this control, or the top layer): an ink outline, a hard ink
## shadow, the colour; `sc` swells it about its middle.
func _outlined(ci: CanvasItem, font: Font, s: String, at: Vector2, px: int, col: Color, a: float, outline: int, shadow: float, sc: float = 1.0) -> void:
	if s == "" or a <= 0.003:
		return
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_set_transform(at + Vector2(0.0, -px * 0.35), 0.0, Vector2(sc, sc))
	var o := Vector2(-w * 0.5, px * 0.35)
	# pass 123: the kit's type (DrumMoment.kit_line): paper reads cream, brass the kit's gold with its bevel, ember
	# (EVOLVED) the epic purple; a colour of the kit's own is kept
	var gold := col.is_equal_approx(W.BRASS)
	var kc := col
	if col.is_equal_approx(W.PAPER):
		kc = R.CREAM
	elif gold:
		kc = R.GOLD_TEXT
	elif col.is_equal_approx(W.EMBER):
		kc = R.RARITY["epic"]["light"]
	DrumMoment.kit_line(ci, font, o, s, px, kc, a, gold)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return



## The largest size up to `px` at which `s` fits `width`.
static func _fit(font: Font, s: String, px: int, width: float) -> int:
	var p := px
	while p > 20 and font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, p).x > width:
		p -= 2
	return p


static func _grow(pts: PackedVector2Array, by: float) -> PackedVector2Array:
	var out := Geometry2D.offset_polygon(pts, by, Geometry2D.JOIN_MITER)
	return out[0] if not out.is_empty() else pts

## Last Stand's slowed time and its look (pass 69, a passive item; Garry: "slow down time and deal Nx damage for like 2
## seconds ... The slow down time effect should look different from High Noon"). Game makes one when the hero's
## last_stand signal fires (Run.last_stand_check has put the damage on the sheet) and calls start(): the engine's clock
## runs at Run.LAST_STAND_SCALE for Run.LAST_STAND_SECONDS of real time, the world drained to a cold blue-grey with a red
## rim swelling with a heartbeat (core/shaders/last_stand.gdshader, on its own layer under the HUD), one low thump.
## It owns Engine.time_scale while it runs: whenever the run is paused (a card screen, the pause board, a chest, Down!)
## the clock is put back to normal and its seconds wait; the hero falling, the run ending or this node leaving the tree
## end it at once, the clock back and the damage off the sheet (Run.set_last_stand(false)).
class_name LastStandFx
extends CanvasLayer

const FADE_IN := 0.12
const FADE_OUT := 0.35
## heartbeats a second of real time (a racing heart), each a "lub" and a softer "dub" BEAT_DUB later
const BEAT_HZ := 1.6
const BEAT_DUB := 0.17

var game: Node
var active := false
## real seconds of slowed time left
var left := 0.0
var _scale := 0.5
var _restore := 1.0
var _strength := 0.0
var _beat_t := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://core/shaders/last_stand.gdshader")
	_rect.material = _mat
	add_child(_rect)
	visible = false


## Slowed time for `seconds` of real time at the clock `slow` (Run's numbers unless a test gives others).
func start(seconds: float = -1.0, slow: float = -1.0) -> void:
	if seconds < 0.0:
		seconds = Run.LAST_STAND_SECONDS
	if slow < 0.0:
		slow = Run.LAST_STAND_SCALE
	if not active:
		# the clock it goes back to: what it was (the arena's game speed), never a hit-stop's blink
		_restore = Lockstep.time_scale() if Lockstep.time_scale() >= 0.2 else 1.0
	active = true
	left = seconds
	_scale = clampf(slow, 0.05, 1.0)
	_beat_t = 0.0
	visible = true
	if not held():
		Lockstep.set_time_scale(_scale)


## Whether the run stands still now (a screen up), so the clock goes back to normal and the seconds wait.
func held() -> bool:
	if not is_inside_tree():
		return false
	if get_tree().paused:
		return true
	return game != null and bool(game.get("paused"))


## Whether it must end now: the hero down, the run over.
func _over() -> bool:
	if game == null:
		return false
	if bool(game.get("_ended")):
		return true
	var p = game.get("player")
	return p != null and bool(p.get("dead"))


## The frame's real time is its delta without the engine's scale (the clock it runs, so a capture at a fixed frame rate
## or a slow frame counts as the game counts it), a long stall at most MAX_STEP.
const MAX_STEP := 0.5


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the game's own clock and scale (Lockstep: the recorded ones in a replay)
	tick_real(minf(Lockstep.dt(delta) / maxf(Lockstep.time_scale(), 0.01), MAX_STEP))


## One step of `real` seconds of real time: the clock, the end, the look.
func tick_real(real: float) -> void:
	if active:
		if _over():
			finish()
		elif held():
			Lockstep.set_time_scale(1.0)
		else:
			Lockstep.set_time_scale(_scale)
			left -= real
			if left <= 0.0:
				finish()
	var still := held()
	var want := 1.0 if active else 0.0
	if not still:
		var rate := 1.0 / FADE_IN if want > _strength else 1.0 / FADE_OUT
		_strength = move_toward(_strength, want, real * rate)
		_beat_t += real
	if _mat:
		_mat.set_shader_parameter("strength", _strength)
		_mat.set_shader_parameter("beat", beat_at(_beat_t))
		var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1080, 1920)
		_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	visible = _strength > 0.001


## The heartbeat's swell `t` real seconds in: a sharp "lub" and a softer "dub" every 1 / BEAT_HZ seconds, 0..1.
static func beat_at(t: float) -> float:
	var p := fmod(t * BEAT_HZ, 1.0) / BEAT_HZ
	var lub := exp(-pow((p - 0.02) / 0.05, 2.0))
	var dub := 0.65 * exp(-pow((p - 0.02 - BEAT_DUB) / 0.05, 2.0))
	return clampf(maxf(lub, dub), 0.0, 1.0)


## The end: the clock back, the damage off the sheet, the look fading.
func finish() -> void:
	if not active:
		return
	active = false
	left = 0.0
	Lockstep.set_time_scale(_restore)
	Run.set_last_stand(false)


func _exit_tree() -> void:
	if active:
		active = false
		Lockstep.set_time_scale(1.0)
		Run.set_last_stand(false)

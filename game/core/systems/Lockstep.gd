## Pass 114 (lane REPLAY): the frame gates a replay drives the run through (core/systems/RunReplay.gd records and
## replays). The game runs its rules in `_process(delta)` (variable frames) and 60 Hz `_physics_process` (at most
## Game.CATCH_UP_STEPS a frame). A recording keeps every frame's physics steps k, their delta pd and the frame's delta d;
## a replay runs the build with --fixed-fps 64 and 64 physics ticks (one engine physics step a frame, every delta a
## power-of-two multiple: exact) and per frame:
## - every rule `_process` reads `delta = Lockstep.dt(delta)`: the recorded d (in play: the engine's own delta);
## - every rule `_physics_process` starts with `if Lockstep.phys_skip(): return`: in a replay the engine's own call
##   returns at once and RunReplay's driver calls it k times with pd, in the engine's order (physics priority, then the
##   tree); every such node joins the group with `Lockstep.join(self)` in _ready;
## - the game's own writes to Engine.time_scale go through set_time_scale (a replay sets the engine's itself) and its
##   reads through time_scale() (the recorded game scale in a replay).
## In play every gate is one bool test. Names no autoload (tools compile it before the autoloads exist).
class_name Lockstep
extends RefCounted

const GROUP := &"lockstep_phys"
## The replay's engine rate (--fixed-fps and the physics ticks): a power of two, so 64 * d / 64 == d bit for bit.
const REPLAY_HZ := 64
## The most engine physics steps a replay's frame has (its physics ticks are REPLAY_HZ x the recorded frame's steps, 1 or
## 2: Game.CATCH_UP_STEPS), so the engine's work between two world steps happens as it did on the device.
const PHYS_PER_FRAME := 2
## The stick's resolution: every rule reads the stick quantised to 1/STICK_Q (q2), so a recording keeps it exactly (a
## power of two: 0.5, 0.25 and 1 stay exact; a step is under a twentieth of a degree at full tilt).
const STICK_Q := 1024.0

## A replay drives this run.
static var replaying := false
## Inside the driver's physics steps (the gated nodes run then and only then).
static var driving := false
## The recorded frame delta of the frame now playing (a replay).
static var proc_d := 1.0 / 60.0
## The game's own time scale (what Engine.time_scale holds in play): kept here in a replay, where the engine's carries
## the replay's own pacing.
static var game_scale := 1.0
## Pass 114: true while a tap's handler (between frames) or a driver of the run (the bot, a tool's tick wrapped in
## begin_input/end_input) acts: a decision noted then is the player's, recorded; one noted otherwise is the game's own
## consequence (a timer, an expiry) and is not.
static var input_depth := 0


## The frame's delta every rule `_process` uses.
static func dt(d: float) -> float:
	return proc_d if replaying else d


## True when a gated `_physics_process` must return at once (a replay, outside the driver's steps).
static func phys_skip() -> bool:
	return replaying and not driving


## A gated physics node joins the driver's group (call in _ready).
static func join(n: Node) -> void:
	if n != null and not n.is_in_group(GROUP):
		n.add_to_group(GROUP)


## The game's own write to the engine's time scale (the hit-stop, Last Stand).
static func set_time_scale(v: float) -> void:
	game_scale = v
	if not replaying:
		Engine.time_scale = v


## The game's own time scale (Engine.time_scale in play; the recorded one in a replay).
static func time_scale() -> float:
	return game_scale if replaying else Engine.time_scale


## The 60 Hz world's ticks a second as the rules count them (Engine.physics_ticks_per_second in play; a replay's engine
## runs REPLAY_HZ, but the world it drives steps at the recorded rate).
static func world_hz() -> int:
	return 60 if replaying else Engine.physics_ticks_per_second


## A run's own timer (in place of SceneTree.create_timer for a rule): counts the frames' deltas as the rules see them
## (dt) at the end of each frame (RunReplay's tail, where the engine's timers would fire), paused with the tree unless
## `process_always`. Without a run's ticker (a test without a Game) it is the engine's own timer.
class LockTimer:
	extends RefCounted
	signal timeout
	var left := 0.0
	var always := true


static var ticking := 0
static var _timers: Array = []


static func after(n: Node, seconds: float, process_always: bool = true):
	if ticking <= 0 or n == null:
		return n.get_tree().create_timer(seconds, process_always)
	var t := LockTimer.new()
	t.left = seconds
	t.always = process_always
	_timers.append(t)
	return t


## RunReplay's tail: every run timer down by the frame's delta, the ones that ran out fired (in the order they were made).
static func tick_timers(delta: float, paused: bool) -> void:
	if _timers.is_empty():
		return
	var due: Array = []
	for t: LockTimer in _timers:
		if t.always or not paused:
			t.left -= delta
			if t.left <= 0.0:
				due.append(t)
	for t: LockTimer in due:
		_timers.erase(t)
		t.timeout.emit()


static func clear_timers() -> void:
	_timers.clear()


## The stick as every rule reads it: each axis to the nearest 1/STICK_Q (a recording stores those steps exactly).
static func q2(v: Vector2) -> Vector2:
	return Vector2(roundf(v.x * STICK_Q) / STICK_Q, roundf(v.y * STICK_Q) / STICK_Q)

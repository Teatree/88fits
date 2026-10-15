## The Watch's speed control (pass 80, lane WATCH; the design Garry approved: "pause, 0.25x up to about 8x, step one
## second, run to the next level-up; up to 1x the game clock slows; above 1x several game steps per drawn frame instead
## of stretched steps"). Pure state and arithmetic: Watch.gd reads the numbers and writes them to the engine.
## - The game steps 1/60 s a frame (watch.py starts Godot with --fixed-fps 60: a frame is one process step and one
##   physics step whatever the wall clock does).
## - Up to 1x: Engine.time_scale = the speed (every step that much shorter, 60 frames a wall second), composed with the
##   game's own writes to it (the hit-stop's 0.08, Last Stand's slow clock): game_scale_of.
## - Above 1x: time_scale 1 (the step itself unchanged: a weapon still fires at most once a step), 60 x the speed frames
##   a wall second, and a frame is drawn only when 1/DRAW_HZ s of wall time has passed (1/DRAW_HZ_FAST from 4x on:
##   draw_due), so the frames between draws are pure simulation.
## - The frames are paced here (pace): --fixed-fps turns the engine's own frame limit (Engine.max_fps) off, so each
##   frame waits for its share of wall time; a frame that ran late is made up by the next ones not waiting, at most
##   CATCH_UP_US behind (past that the clock starts again from now: the run goes as fast as the PC lets it).
## - Pause: the tree held paused and the bot not ticked (Watch.gd). "Step one second": runs STEP_SECONDS of play at the
##   speed (1x from a pause) and pauses. "Next level-up": the fastest speed until the level-up cards are on screen, then
##   pauses before the bot picks.
## Tools only (tools/* is never exported).
extends RefCounted

const RING := preload("res://tools/watch/WatchRing.gd")

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const STEP_HZ := 60.0
## frames drawn a wall second at most: DRAW_HZ up to 2x, DRAW_HZ_FAST from 4x on (a drawn frame costs about 4 ms more
## than one that is not, which the game's own step needs there)
const DRAW_HZ := 60.0
const DRAW_HZ_FAST := 30.0
const STEP_SECONDS := 1.0
const FASTEST := 8.0
## the header shows the reached speed when it is under this share of the one asked for
const SHORT := 0.9
## the measured speed: game seconds over wall seconds of play in half-second buckets, the newest BUCKETS of them
const BUCKET_S := 0.5
const BUCKETS := 4
## how far behind its frames' wall time the run may fall and still catch up (microseconds)
const CATCH_UP_US := 250000
const LOW_DRAW_RETRY_S := 20.0

var speed := 1.0
var paused := false
## "" plain; "step" until play reaches step_until; "level" until the next level-up's cards
var mode := ""
var step_until := 0.0
var step_speed := 1.0
var level_from := 0
## Engine.time_scale as the Watch last wrote it, and the game's own share of it (1 = the game asks nothing)
var applied := 1.0
var game_scale := 1.0
var reached := 0.0
## the run fell short of the speed asked (short()): frames are drawn at most DRAW_HZ_FAST a second at any speed, so the
## steps get the time; tried again at the full rate after LOW_DRAW_RETRY_S wall seconds of play (or a new speed)
var low_draw := false
var _low_t := 0.0

var _last_draw_us := -1
var _pace_us := -1
var _wall_b := RING.new(BUCKETS)
var _play_b := RING.new(BUCKETS)
var _acc_wall := 0.0
var _acc_play := 0.0


## The speed above `s` in SPEEDS (the fastest stays).
static func faster(s: float) -> float:
	for v in SPEEDS:
		if float(v) > s + 0.001:
			return float(v)
	return float(SPEEDS[SPEEDS.size() - 1])


## The speed below `s` in SPEEDS (the slowest stays).
static func slower(s: float) -> float:
	var out := float(SPEEDS[0])
	for v in SPEEDS:
		if float(v) < s - 0.001:
			out = float(v)
	return out


## The speed nearest to `s` in SPEEDS (a tie goes to the slower one: speed=3 is 2x).
static func nearest(s: float) -> float:
	var best := 1.0
	var bd := INF
	for v in SPEEDS:
		var d := absf(float(v) - s)
		if d < bd - 0.0001:
			bd = d
			best = float(v)
	return best


## Engine.time_scale the Watch asks for at speed `s`: the speed up to 1x, 1 above.
static func nominal_scale(s: float) -> float:
	return clampf(s, 0.0, 1.0)


## Frames a wall second at speed `s`: 60 up to 1x, 60 x the speed above.
static func frames_per_second(s: float) -> int:
	return int(round(STEP_HZ * maxf(s, 1.0)))


## The game's own share of Engine.time_scale, read off what it holds now (`observed`) against what the Watch wrote
## (`applied`) and asks for (`nominal`): unchanged since the Watch wrote it -> `prev`; the game set it back to the
## Watch's nominal clock (Last Stand restoring the clock it found) or to 1 (the hit-stop's end) -> 1; anything else is
## the game's own clock (the hit-stop's 0.08, Last Stand's slow).
static func game_scale_of(observed: float, applied_now: float, nominal: float, prev: float) -> float:
	if absf(observed - applied_now) < 0.0005:
		return prev
	if absf(observed - nominal) < 0.0005 or absf(observed - 1.0) < 0.0005:
		return 1.0
	return clampf(observed, 0.0, 1.0)


## The time_scale to write this frame with the engine's value `observed` now; remembers it.
func compose(observed: float) -> float:
	var nominal := nominal_scale(running_speed())
	game_scale = game_scale_of(observed, applied, nominal, game_scale)
	applied = nominal * game_scale
	return applied


## The speed the run goes at now: the fastest in "level" mode, the step's own speed in "step" mode, else `speed`.
func running_speed() -> float:
	if mode == "level":
		return FASTEST
	if mode == "step":
		return step_speed
	return speed


func set_speed(s: float) -> void:
	speed = nearest(s)
	paused = false
	mode = ""


func toggle_pause() -> void:
	paused = not paused
	mode = ""


## "Step one second" from play second `play_t`: at the speed it runs (1x from a pause), then paused.
func step(play_t: float) -> void:
	step_speed = 1.0 if paused else speed
	mode = "step"
	step_until = play_t + STEP_SECONDS
	paused = false


## "Run to the next level-up" from level `level`: the fastest speed until the level-up cards are up.
func to_level(level: int) -> void:
	mode = "level"
	level_from = level
	paused = false


## Whether a step or a run to a level-up has come to its end now (play second `play_t`; `cards_up`: a level-up's cards
## are on screen waiting for a pick); it pauses then. Called every frame before the bot ticks.
func reached_end(play_t: float, cards_up: bool) -> bool:
	if paused:
		return false
	if mode == "step" and play_t >= step_until - 0.0001:
		mode = ""
		paused = true
		return true
	if mode == "level" and cards_up:
		mode = ""
		paused = true
		return true
	return false


## The wall microseconds this frame waits before it plays (wall clock `now_us`): each frame has 1/frames_per_second of
## wall time (60 a second while paused or `idle`: no run up, or over).
func pace(now_us: int, idle: bool = false) -> int:
	var budget := int(1000000.0 / float(frames_per_second(1.0 if paused or idle else running_speed())))
	if _pace_us < 0 or now_us - _pace_us > CATCH_UP_US:
		_pace_us = now_us
	var wait := maxi(_pace_us - now_us, 0)
	_pace_us += budget
	return wait


## Whether this frame is drawn (wall clock `now_us`): every frame up to 1x; above it, one each 1/DRAW_HZ s, one each
## 1/DRAW_HZ_FAST s from 4x on; at any speed one each 1/DRAW_HZ_FAST s once the run has fallen short (low_draw).
func draw_due(now_us: int) -> bool:
	if paused or (running_speed() <= 1.0 and not low_draw):
		_last_draw_us = now_us
		return true
	var hz := DRAW_HZ_FAST if (running_speed() >= 4.0 or low_draw) else DRAW_HZ
	if _last_draw_us < 0 or now_us - _last_draw_us >= int(1000000.0 / hz) - 300:
		_last_draw_us = now_us
		return true
	return false


## The measured speed: a frame of `wall_dt` wall seconds that played `play_dt` seconds of the run (frames that played
## nothing, paused or behind a screen, are left out).
func measure(wall_dt: float, play_dt: float) -> void:
	if play_dt <= 0.0 or wall_dt <= 0.0 or wall_dt > 1.0:
		return
	if low_draw:
		_low_t += wall_dt
		if _low_t >= LOW_DRAW_RETRY_S:
			reset_measure()
			return
	_acc_wall += wall_dt
	_acc_play += play_dt
	if _acc_wall >= BUCKET_S:
		_wall_b.push(_acc_wall)
		_play_b.push(_acc_play)
		_acc_wall = 0.0
		_acc_play = 0.0
		reached = _play_b.sum() / maxf(_wall_b.sum(), 0.0001)
		if _wall_b.size() >= 2 and short():
			low_draw = true


## Forget the measured speed (a new speed was asked for).
func reset_measure() -> void:
	_wall_b.clear()
	_play_b.clear()
	_acc_wall = 0.0
	_acc_play = 0.0
	reached = 0.0
	low_draw = false
	_low_t = 0.0


## Whether the measured speed falls short of the one asked for (SHORT of it).
func short() -> bool:
	return not paused and reached > 0.0 and reached < SHORT * running_speed()


## "8x", "0.25x", "1x".
static func label(s: float) -> String:
	if absf(s - roundf(s)) < 0.001:
		return "%dx" % int(roundf(s))
	return ("%.2fx" % s).replace("0.50x", "0.5x")

## Pass 114 (lane REPLAY): the replay viewer. A recorded run (core/systems/RunReplay.gd's file) played through the real
## game with the real art in a phone-shaped view on the left, fed the recorded stick and taps instead of a thumb, with a
## header that says whose run it is and which build plays it, speed buttons, a progress reel to jump anywhere, the taps
## drawn as rings, the stick as a ghost, the drift light, and a small chart (analytics/howto/04_replays.md).
## Started by tools/replay.py, which picks the build the run was recorded on (builds/<id>/88fits.exe) and runs:
##   88fits.exe --fixed-fps 64 --resolution 1600x900 -- replay=<file> [speed=1] [paused=0] [seek=mm:ss] [sound=0]
##       [shots=<dir> demo=1] [quit_after=<wall s>]
## (Boot opens this instead of the title; never in a prod build). --fixed-fps 64 is required: each engine frame is one
## recorded frame (RunReplay's driver sets the engine's time scale so every delta is the recorded one).
## Speeds pace the frames on the wall clock (never stretch a step); a seek forward runs the frames undrawn, a seek back
## starts the run again and runs to the point.
extends Control

const GAME_SCENE := "res://game/Game.tscn"
const RESULTS_SCENE := "res://ui/ResultsScreen.tscn"
const SPEEDS := [0.1, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const DRAW_HZ := 60.0
const PANEL_W := 560.0
const REEL_H := 92.0
const HEAD_H := 86.0
const RING_S := 0.6
const BG := Color(0.07, 0.07, 0.09)
const INK := Color(0.92, 0.9, 0.86)
const DIM := Color(0.6, 0.6, 0.62)
const GOOD := Color(0.35, 0.85, 0.45)
const BAD := Color(0.95, 0.3, 0.28)
const WARN := Color(0.98, 0.75, 0.25)
const MARK_COLOURS := {"level": Color(0.98, 0.82, 0.3), "offer": Color(0.98, 0.82, 0.3), "boss_start": Color(0.95, 0.3, 0.28),
	"boss_end": Color(0.95, 0.5, 0.3), "death": Color(1, 1, 1), "revive": Color(0.4, 0.9, 1.0), "totem_offer": Color(0.45, 0.85, 0.5),
	"pickup": Color(0.4, 0.7, 1.0), "elite": Color(0.95, 0.6, 0.25), "special": Color(0.8, 0.45, 1.0), "portal": Color(0.6, 0.6, 1.0),
	"endless": Color(0.6, 0.6, 1.0), "stranger": Color(0.75, 0.75, 0.75), "structure": Color(0.6, 0.8, 0.6), "hurt": Color(0.95, 0.3, 0.28),
	"stage_beaten": Color(0.98, 0.9, 0.5)}

var args: Dictionary = {}
var plan: Dictionary = {}
var file_path := ""
var problems: Array = []

var sub: SubViewport
var view: TextureRect
var overlay: Control
var header: RichTextLabel
var panel: VBoxContainer
var numbers: Label
var light: Label
var light_dot: ColorRect
var log_box: RichTextLabel
var chart: Control
var reel: Control
var seek_box: PanelContainer
var seek_label: Label
var speed_buttons: Array = []
var game: Node
var rr: Node

var speed := 1.0
var paused := false
var _want_pause := false
var _step_req := 0
var _seek_target := -1
var _seek_from_ms := 0
var _restart_pending := false
var _pace_us := -1
var _last_draw_us := 0
var _next_ui_us := 0
var frames_n := 0
## per recorded frame: its wall time on the device (s) and the run's clock, cumulated (for the reel's axis and mm:ss)
var wall_at := PackedFloat64Array()
var marks: Array = []
var taps: Array = []
var origins: Array = []
var hp_track := PackedVector2Array()
var lv_track := PackedVector2Array()
var _tap_i := 0
var _log_lines: Array = []
var _canvas := Vector2(1080, 2400)
var _quit_after := 0.0
var _t0_ms := 0
var _shots_dir := ""
var _demo := false
var _demo_step := 0
var _demo_wait := 0.0
var _sound := false
var _drift_text := ""
## check=1: run the whole recording undrawn, print what the checks said and how long it took, quit (the proof)
var _check_mode := false
## the game is added from a timer started in _process (see _process)
var _add_pending := false
var _last_tick_us := 0
var _fps_frames := 0
var _notes_seen := 0
var _fps_warned := false
var _check_t0 := 0
var _assist_seen := 0


# ---------------------------------------------------------------- set up

static func parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := str(a).trim_prefix("--")
		var i := s.find("=")
		if i > 0:
			out[s.substr(0, i)] = s.substr(i + 1)
		elif s != "":
			out[s] = "1"
	return out


func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	if args.is_empty():
		args = parse_args()
	file_path = str(args.get("replay", ""))
	speed = float(args.get("speed", "1"))
	_want_pause = str(args.get("paused", "0")) == "1"
	_quit_after = float(args.get("quit_after", "0"))
	_shots_dir = str(args.get("shots", ""))
	_demo = str(args.get("demo", "0")) == "1"
	for v in str(args.get("shot_at", "")).split(",", false):
		_shot_at.append(float(v))
	_sound = str(args.get("sound", "0")) == "1"
	_check_mode = str(args.get("check", "0")) == "1"
	var w := int(args.get("w", "1600"))
	var h := int(args.get("h", "900"))
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		win.size = Vector2i(w, h)
		win.title = "88fits replay"
	# the camera cutout's ink band (an autoload over the whole window) would cover the header when the run was recorded on a
	# phone with a cutout (the recording's safe_top); the phone view's HUD keeps its own band (pass 114, lead)
	var band := get_node_or_null("/root/CutoutBand") as CanvasLayer
	if band:
		band.visible = false
	Engine.physics_ticks_per_second = Lockstep.REPLAY_HZ
	Engine.physics_jitter_fix = 0.0
	Engine.max_fps = 0
	# the viewer runs whatever the game pauses (a card screen pauses the tree)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_plan()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	get_tree().node_added.connect(_on_node_added)
	if plan.is_empty():
		_say_problem()
		return
	if not _sound:
		AudioServer.set_bus_mute(0, true)
	_start_game()


func _load_plan() -> void:
	if file_path == "" or not FileAccess.file_exists(file_path):
		problems.append("No replay file: " + file_path)
		return
	var p = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not (p is Dictionary) or str((p as Dictionary).get("kind", "")) != RunReplay.KIND:
		problems.append("Not a replay file: " + file_path)
		return
	plan = p
	frames_n = int(plan.get("frames_n", 0))
	var cv: Array = plan.get("canvas", [1080, 2400])
	_canvas = Vector2(float(cv[0]), float(cv[1])) if cv.size() == 2 and float(cv[0]) > 0.0 else Vector2(1080, 2400)
	_index_frames()
	taps = plan.get("taps", [])
	origins = plan.get("origins", [])
	_make_marks()


## The recorded frames' wall time (d over the game's time scale), cumulated: the reel's axis is the video's time.
func _index_frames() -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = RunReplay._unblob(str(plan.get("frames", "")))
	wall_at.resize(frames_n + 1)
	var acc := 0.0
	var i := 0
	wall_at[0] = 0.0
	while b.get_position() < b.get_size() and i < frames_n:
		var n := b.get_u32()
		b.get_u8()
		b.get_double()
		var d := b.get_double()
		var ts := b.get_double()
		var real := d / maxf(ts, 0.01)
		for _j in range(n):
			if i >= frames_n:
				break
			acc += real
			i += 1
			wall_at[i] = acc
	frames_n = i
	wall_at.resize(frames_n + 1)


func frame_at_wall(t: float) -> int:
	var lo := 0
	var hi := frames_n
	while lo < hi:
		var mid := (lo + hi) >> 1
		if wall_at[mid] < t:
			lo = mid + 1
		else:
			hi = mid
	return clampi(lo, 0, maxi(frames_n - 1, 0))


func total_wall() -> float:
	return wall_at[frames_n] if frames_n > 0 else 0.0


## The reel's marks: the run's own events (level-ups, picks, bosses, totems, power-ups, deaths, revives, the portal) and
## the hits that took a fifth of his HP within a second (the track).
func _make_marks() -> void:
	marks.clear()
	for m in plan.get("marks", []):
		var a: Array = m
		var kind := str(a[2])
		if not MARK_COLOURS.has(kind):
			continue
		var label := _mark_label(kind, str(a[3]), int(a[4]))
		marks.append({"f": int(a[0]), "kind": kind, "label": label})
	# HP from the track: drops of a fifth of the run's top HP within about a second
	var t := StreamPeerBuffer.new()
	t.data_array = RunReplay._unblob(str(plan.get("track", "")))
	var pts: Array = []
	var top := 1.0
	while t.get_position() + 16 <= t.get_size():
		var f := t.get_u32()
		t.get_32()
		t.get_32()
		var hp := t.get_float()
		pts.append([f, hp])
		top = maxf(top, hp)
	hp_track.resize(pts.size())
	for i in range(pts.size()):
		hp_track[i] = Vector2(float(pts[i][0]), float(pts[i][1]))
		if i >= 2 and float(pts[i - 2][1]) - float(pts[i][1]) >= top * 0.2:
			if marks.is_empty() or int(marks[-1]["f"]) < int(pts[i][0]) - 120 or str(marks[-1]["kind"]) != "hurt":
				marks.append({"f": int(pts[i][0]), "kind": "hurt", "label": "Big hit: -%d HP" % int(float(pts[i - 2][1]) - float(pts[i][1]))})
	for c in plan.get("checks", []):
		var cd: Dictionary = c
		lv_track.append(Vector2(float(cd.get("f", 0)), float(cd.get("lv", 1))))
	marks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["f"]) < int(b["f"]))


func _mark_label(kind: String, id: String, level: int) -> String:
	match kind:
		"level":
			return "Level %d" % level
		"offer":
			return "Took " + _item_name(id) if id != "" else "Skipped the cards"
		"boss_start":
			return "Boss: " + _enemy_name(id)
		"boss_end":
			return "Boss down: " + _enemy_name(id)
		"death":
			return "Down (hit by %s)" % id if id != "" else "Down"
		"revive":
			return "Revived"
		"totem_offer":
			return "Totem gift: " + id
		"pickup":
			return "Power-up: " + id
		"elite":
			return "Elite: " + _enemy_name(id)
		"special":
			return "Special: " + _enemy_name(id)
		"portal":
			return "Portal"
		"endless":
			return "Endless"
		"stage_beaten":
			return "Stage beaten"
		"stranger":
			return "The Stranger's deal: " + _item_name(id)
		"structure":
			return "Used " + id
	return kind


func _item_name(id: String) -> String:
	for getter in ["weapon", "passive", "evolution", "mutation"]:
		if Registry.has_method(getter):
			var d = Registry.call(getter, id)
			if d != null and d.get("display_name") != null:
				return str(d.display_name)
	return id


func _enemy_name(id: String) -> String:
	var d = Registry.enemy(id) if Registry.has_method("enemy") else null
	if d != null and d.get("display_name") != null:
		return str(d.display_name)
	return id


# ---------------------------------------------------------------- the game

func _start_game() -> void:
	# the save and the settings as the run began (sandboxed: nothing reaches the PC's save)
	Save.set("_dirty", false)
	if not Save.sandboxed():
		Save.begin_sandbox()
	Save.data = (plan.get("save", {}) as Dictionary).duplicate(true)
	Settings.from_dict(plan.get("settings", {}))
	Settings.top_inset = int(roundf(float(plan.get("safe_top", 0.0))))
	var lo: Dictionary = (plan.get("launch", {}) as Dictionary).duplicate()
	lo["analytics_memory"] = true
	lo.erase("replay_record")
	if args.has("trace"):
		var tr := str(args["trace"]).split("-")
		lo["replay_trace"] = [int(tr[0]), int(tr[1])]
	Run.launch_override = lo
	RunReplay.plan = plan
	Lockstep.replaying = false
	# the frame the game is made in runs at the recorded delta (its _ready's tweens and timers), one frame from now
	Engine.time_scale = float(Lockstep.REPLAY_HZ) * float(plan.get("d_ready", 1.0 / 64.0))
	_make_game.call_deferred()


func _make_game() -> void:
	# a few frames for the engine's clock to settle (its first frames may run no physics step), then the next frame (its
	# delta is the recorded one) after its nodes' processing, where a scene change lands: the game's first processed
	# frame is then the recording's frame 0
	for _i in range(6):
		await get_tree().process_frame
	Engine.time_scale = float(Lockstep.REPLAY_HZ) * float(plan.get("d_ready", 1.0 / 64.0))
	await get_tree().process_frame
	_add_pending = true


func _add_game() -> void:
	var scene = load(GAME_SCENE)
	game = scene.instantiate()
	sub.add_child(game)
	rr = game.get_node_or_null("RunReplay")
	if rr == null:
		problems.append("The game did not start its replay driver")
		return
	rr.checkpoint_compared.connect(_on_check)
	rr.decision_applied.connect(_on_decision)
	rr.finished_frames.connect(func(): _note("The recording ends here."))
	if _check_mode:
		_check_t0 = Time.get_ticks_msec()
		seek_to_wall(total_wall())
	elif args.has("seek"):
		seek_to_wall(parse_time(str(args["seek"])))
	if _want_pause:
		paused = true
		rr.call("request_hold", true)


func _on_node_added(node: Node) -> void:
	# what the run's end sends to the window's root (the scene fade, the Results scene): not in the viewer
	var root := get_tree().root
	if node.get_parent() == root and node != self and not node.name in ["Run", "Save", "Settings", "Registry", "Audio", "Analytics"]:
		if (node is CanvasLayer and (node as CanvasLayer).layer == 100) or str(node.scene_file_path) == RESULTS_SCENE:
			node.queue_free.call_deferred()


static func parse_time(s: String) -> float:
	if s.contains(":"):
		var p := s.split(":")
		return float(p[0]) * 60.0 + float(p[1])
	return float(s)


static func speed_words(s: float) -> String:
	return ("%dx" % int(s)) if s == floorf(s) else ("%sx" % str(s))


static func mmss(t: float) -> String:
	var s := int(floorf(maxf(t, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- control

func set_speed(s: float) -> void:
	speed = s
	_pace_us = -1
	if paused:
		set_paused(false)
	_refresh_buttons()


func set_paused(v: bool) -> void:
	paused = v
	_pace_us = -1
	if rr:
		rr.call("request_hold", v)
	_refresh_buttons()


func step_frame() -> void:
	if not paused:
		set_paused(true)
		return
	if rr:
		rr.call("request_step", 1)


## Jump to `t` seconds of the video's time: forward runs the frames undrawn; back starts the run again first.
func seek_to_wall(t: float) -> void:
	if rr == null:
		return
	var target := frame_at_wall(clampf(t, 0.0, total_wall()))
	var now := int(rr.get("frame"))
	_seek_from_ms = Time.get_ticks_msec()
	if target < now:
		_restart_and_seek(target)
		return
	_seek_target = target
	rr.call("request_hold", false)


func _restart_and_seek(target: int) -> void:
	_seek_target = target
	_restart_pending = true
	if game and is_instance_valid(game):
		game.queue_free()
	game = null
	rr = null
	_log_lines.clear()
	_drift_text = ""
	_tap_i = 0
	_highlight = Rect2()
	_highlight_until = 0.0
	_notes_seen = 0
	_restart_game.call_deferred()


func _restart_game() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_restart_pending = false
	_start_game()


func _process(_delta: float) -> void:
	if _add_pending:
		_add_pending = false
		# from a timer: the engine runs those after every node's processing and every deferred call, where a scene change
		# lands, so no node of the game is processed in the frame it is made (the recording's frame 0 is the next one)
		get_tree().create_timer(0.0).timeout.connect(_add_game, CONNECT_ONE_SHOT)
	if _quit_after > 0.0 and float(Time.get_ticks_msec() - _t0_ms) / 1000.0 > _quit_after:
		get_tree().quit(0)
		return
	# --fixed-fps 64 makes every frame before the game exactly 1/64 s (the engine's own args are not in the cmdline list)
	_fps_frames += 1
	if game == null and _fps_frames >= 2 and _fps_frames <= 5 and Engine.time_scale == 1.0 and _delta != 1.0 / float(Lockstep.REPLAY_HZ):
		if not _fps_warned:
			_fps_warned = true
			problems.append("This window was not started with --fixed-fps 64: the replay cannot keep step. Start it with tools/replay.py.")
	var wall_dt := float(Time.get_ticks_usec() - _last_tick_us) / 1000000.0 if _last_tick_us > 0 else 0.0
	_last_tick_us = Time.get_ticks_usec()
	if _demo:
		_demo_tick(minf(wall_dt, 0.25))
	if _check_mode and rr and int(rr.get("frame")) >= frames_n - 1:
		print("replay: check: frames %d/%d checks ok %d bad %d drift_frame %d hero_fixes %d late %d dropped %d in %.1f s (%s)" % [
			int(rr.get("frame")) + 1, frames_n, int(rr.get("checks_ok")), int(rr.get("checks_bad")), int(rr.get("drift_frame")),
			int(rr.get("hero_fixes")), int(rr.get("late_decisions")), (rr.get("dropped_decisions") as Array).size(),
			float(Time.get_ticks_msec() - _check_t0) / 1000.0, str(RunReplay.build_info().get("id", ""))])
		if _drift_text != "":
			print("replay: check: " + _drift_text)
		get_tree().quit(0)
		return
	var now_us := Time.get_ticks_usec()
	var f := int(rr.get("frame")) if rr else 0
	var seeking := _seek_target >= 0
	if seeking and rr:
		if f >= _seek_target:
			_seek_target = -1
			seeking = false
			_pace_us = -1
			_note("Jumped to %s in %.1f s" % [mmss(wall_at[clampi(f, 0, frames_n)]), float(Time.get_ticks_msec() - _seek_from_ms) / 1000.0])
			if paused:
				rr.call("request_hold", true)
	# drawing: every frame up to 1x, DRAW_HZ a second above it, a few a second while seeking (the game view not at all)
	var draw := true
	if seeking or _restart_pending:
		draw = now_us - _last_draw_us > 250000
		sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if speed > 1.0 and not paused:
			draw = now_us - _last_draw_us >= int(1000000.0 / DRAW_HZ) - 300
	if draw:
		_last_draw_us = now_us
	RenderingServer.render_loop_enabled = draw or paused
	if draw or paused:
		_refresh_ui(f)
	# pacing: a frame takes the wall time it took on the device, over the speed
	if not seeking and not paused and rr and f >= 0 and f < frames_n:
		var real := (wall_at[f + 1] - wall_at[f]) / maxf(speed, 0.01)
		var budget := int(real * 1000000.0)
		if _pace_us < 0 or now_us - _pace_us > 250000:
			_pace_us = now_us
		var wait := _pace_us - now_us
		_pace_us += budget
		if wait > 0:
			OS.delay_usec(mini(wait, 200000))
	elif paused:
		OS.delay_usec(8000)
	if _shots_dir != "" and not _shot_at.is_empty() and float(Time.get_ticks_msec() - _t0_ms) / 1000.0 >= float(_shot_at[0]):
		_shot_next = "at_%d" % int(_shot_at[0])
		_shot_at.pop_front()
	if _shots_dir != "" and _shot_next != "":
		_take_shot(_shot_next)
		_shot_next = ""


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed:
		return
	match (e as InputEventKey).keycode:
		KEY_SPACE:
			set_paused(not paused)
		KEY_PERIOD:
			step_frame()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			set_speed(float(SPEEDS[int((e as InputEventKey).keycode) - KEY_1]))
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			set_speed(_faster(speed))
		KEY_MINUS, KEY_KP_SUBTRACT:
			set_speed(_slower(speed))
		KEY_RIGHT:
			seek_to_wall(_now_wall() + (30.0 if e.shift_pressed else 5.0))
		KEY_LEFT:
			seek_to_wall(_now_wall() - (30.0 if e.shift_pressed else 5.0))
		KEY_HOME:
			seek_to_wall(0.0)
		KEY_A:
			if rr:
				rr.set("assist", not bool(rr.get("assist")))
				_note("Safety net " + ("on" if bool(rr.get("assist")) else "off"))
		KEY_M:
			_sound = not _sound
			AudioServer.set_bus_mute(0, not _sound)
		KEY_ESCAPE:
			get_tree().quit(0)


static func _faster(s: float) -> float:
	for v in SPEEDS:
		if float(v) > s + 0.001:
			return float(v)
	return float(SPEEDS[-1])


static func _slower(s: float) -> float:
	var out := float(SPEEDS[0])
	for v in SPEEDS:
		if float(v) < s - 0.001:
			out = float(v)
	return out


func _now_wall() -> float:
	var f := int(rr.get("frame")) if rr else 0
	return wall_at[clampi(f, 0, frames_n)]


# ---------------------------------------------------------------- the driver's news

func _on_check(i: int, ok: bool, diffs: Dictionary) -> void:
	if not ok and _drift_text == "":
		var parts: Array = []
		for k in diffs:
			var key := str(k)
			var pr: Array = diffs[k]
			# the hashes and the dice say only THAT they parted; the plain numbers say by how much
			if key in ["crowd", "dice", "bits", "cx", "cz"]:
				if not parts.has(_field_name(key)):
					parts.append(_field_name(key))
			else:
				parts.append("%s %s / %s" % [_field_name(key), str(pr[0]), str(pr[1])])
		_drift_text = "Out of step from %s: %s differ (recorded / replay)" % [mmss(_now_wall()), ", ".join(PackedStringArray(parts.slice(0, 5)))]
		_note("[color=#f05048]" + _drift_text + "[/color]")


static func _field_name(k: String) -> String:
	return {"x": "hero x", "z": "hero z", "hp": "HP", "lv": "level", "xp": "XP", "kills": "kills", "gold": "gold", "alive": "creatures",
		"crowd": "the creatures' places", "cx": "the crowd's middle", "cz": "the crowd's middle", "dice": "the dice", "t": "clock",
		"bits": "the last digits", "shots": "shots in the air", "picks": "pickups lying"}.get(k, k)


func _on_decision(d: Dictionary, late: int) -> void:
	var k := str(d.get("k", ""))
	_mark_pick(d)
	var words := k
	match k:
		"card":
			words = "Picked " + _item_name(str(d.get("id", "")))
			if d.has("took"):
				words = "Took %s (the player picked %s, not offered here)" % [_item_name(str(d["took"])), _item_name(str(d.get("id", "")))]
		"card_skip":
			words = "Skipped the cards"
		"card_reroll":
			words = "Rerolled the cards"
		"card_banish_mode":
			words = "Banish mode"
		"chest_finish":
			words = "Chest: took it" if bool(d.get("take", true)) else "Chest: skipped"
		"chest_banish":
			words = "Chest: banished"
		"shop_buy":
			words = "Shop: bought " + _item_name(str(d.get("id", "")))
		"shop_leave":
			words = "Shop: left"
		"stranger":
			words = "The Stranger: " + ("deal" if bool(d.get("took", false)) else "walked away")
		"totem":
			words = "Totem: " + str(d.get("id", ""))
		"portal_extract":
			words = "Portal: EXTRACT"
		"portal_decline":
			words = "Portal: not yet"
		"revive":
			words = "Down!: " + str(d.get("kind", ""))
		"gate":
			words = "Tap to go"
		"pause":
			words = "Paused the game"
		"resume":
			words = "Resumed"
		"abandon":
			words = "Quit the run"
		"bounty":
			words = "Wanted poster %d" % int(d.get("i", -1)) if int(d.get("i", -1)) >= 0 else "No bounty"
		"setting":
			words = "Setting %s = %s" % [str(d.get("key", "")), str(d.get("value", ""))]
		"god":
			words = "God mode " + ("on" if bool(d.get("on", false)) else "off")
		"reel_skip", "chest_intro", "chest_hurry", "spawn_hurry":
			return
	_note(("%s  %s" % [mmss(_now_wall()), words]) + ("  (%d frames late)" % late if late > 0 else ""))


## The control a pick landed on, framed in gold over the phone view for HIGHLIGHT_S (the card, the chest's TAKE IT, the
## gift, the shop's card, the road): the screen as it was, with the pick shown.
const HIGHLIGHT_S := 1.2
var _highlight := Rect2()
var _highlight_until := 0.0
## the picked control while it lives (a card still sliding in when the pick came: the frame follows it)
var _highlight_ref: WeakRef = null


func _mark_pick(d: Dictionary) -> void:
	if game == null or not is_instance_valid(game):
		return
	var c: Control = null
	match str(d.get("k", "")):
		"card":
			var cs = game.get("cards")
			if cs:
				var offer: Array = cs._offer
				for i in range(offer.size()):
					if offer[i] is Dictionary and str((offer[i] as Dictionary).get("id", "")) == str(d.get("id", "")) and i < (cs._cards as Array).size():
						c = cs._cards[i]
						break
		"chest_finish":
			var ch = game.get("chest_screen")
			if ch and bool(d.get("take", true)):
				c = ch.get("_take_btn")
		"totem":
			var ts = game.get("totem_screen")
			if ts:
				for r in ts.planks():
					if is_instance_valid(r) and str((r.boon as Dictionary).get("id", "")) == str(d.get("id", "")):
						c = r
		"shop_buy":
			var sh = game.get("structure_shop")
			var i := int(d.get("i", -1))
			if sh and i >= 0 and i < (sh._cards as Array).size():
				c = sh._cards[i]
		"portal_extract":
			var pd = game.get("portal_dialog")
			if pd:
				c = pd.get("_extract")
	if c != null and is_instance_valid(c) and c.is_visible_in_tree():
		_highlight = c.get_global_rect()
		_highlight_ref = weakref(c)
		_highlight_until = _now_wall() + HIGHLIGHT_S


func _note(s: String) -> void:
	_log_lines.append(s)
	if _log_lines.size() > 60:
		_log_lines = _log_lines.slice(_log_lines.size() - 60)
	if log_box:
		log_box.text = "\n".join(PackedStringArray(_log_lines))
		log_box.scroll_to_line(log_box.get_line_count())


# ---------------------------------------------------------------- the window

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	sub = SubViewport.new()
	sub.name = "Phone"
	sub.process_mode = Node.PROCESS_MODE_PAUSABLE
	sub.own_world_3d = true
	sub.size_2d_override_stretch = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.audio_listener_enable_3d = true
	sub.handle_input_locally = false
	sub.gui_disable_input = true
	var px: Array = plan.get("vp_px", [])
	if px.size() == 2 and int(px[0]) > 0:
		sub.size = Vector2i(int(px[0]), int(px[1]))
	else:
		sub.size = Vector2i(int(_canvas.x / 2.0), int(_canvas.y / 2.0))
	sub.size_2d_override = Vector2i(int(_canvas.x), int(_canvas.y))
	add_child(sub)
	view = TextureRect.new()
	view.texture = sub.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	header = RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = false
	header.scroll_active = false
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_font_size_override("normal_font_size", 17)
	header.add_theme_font_size_override("bold_font_size", 19)
	header.add_theme_color_override("default_color", INK)
	add_child(header)
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)
	var lrow := HBoxContainer.new()
	light_dot = ColorRect.new()
	light_dot.custom_minimum_size = Vector2(22, 22)
	light_dot.color = GOOD
	lrow.add_child(light_dot)
	light = Label.new()
	light.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	light.custom_minimum_size = Vector2(PANEL_W - 60, 0)
	light.add_theme_font_size_override("font_size", 16)
	lrow.add_child(light)
	panel.add_child(lrow)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 4)
	var pb := Button.new()
	pb.text = "Pause"
	pb.pressed.connect(func(): set_paused(not paused))
	srow.add_child(pb)
	speed_buttons.append([pb, -1.0])
	var st := Button.new()
	st.text = "Step"
	st.tooltip_text = "One frame forward (. key)"
	st.pressed.connect(step_frame)
	srow.add_child(st)
	for i in range(SPEEDS.size()):
		var b := Button.new()
		var s: float = SPEEDS[i]
		b.text = speed_words(s)
		b.tooltip_text = "Key %d" % (i + 1)
		b.pressed.connect(set_speed.bind(s))
		srow.add_child(b)
		speed_buttons.append([b, s])
	panel.add_child(srow)
	numbers = Label.new()
	numbers.add_theme_font_size_override("font_size", 16)
	numbers.add_theme_color_override("font_color", INK)
	panel.add_child(numbers)
	chart = Control.new()
	chart.custom_minimum_size = Vector2(PANEL_W - 20, 150)
	chart.draw.connect(_draw_chart)
	panel.add_child(chart)
	var lt := Label.new()
	lt.text = "What happened (the taps and the screens, as they were):"
	lt.add_theme_color_override("font_color", DIM)
	lt.add_theme_font_size_override("font_size", 14)
	panel.add_child(lt)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.custom_minimum_size = Vector2(PANEL_W - 20, 220)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_size_override("normal_font_size", 14)
	log_box.add_theme_color_override("default_color", INK)
	panel.add_child(log_box)
	var keys := Label.new()
	keys.text = "Keys: Space pause · . one frame · 1-7 speed 0.1x-8x · +/- faster/slower · ←/→ 5 s (Shift 30 s) · Home start · A safety net · M sound · Esc quit. Click the reel to jump."
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.custom_minimum_size = Vector2(PANEL_W - 20, 0)
	keys.add_theme_color_override("font_color", DIM)
	keys.add_theme_font_size_override("font_size", 13)
	panel.add_child(keys)
	reel = Control.new()
	reel.mouse_filter = Control.MOUSE_FILTER_STOP
	reel.draw.connect(_draw_reel)
	reel.gui_input.connect(_on_reel_input)
	reel.mouse_exited.connect(func(): _reel_hover = -1.0; reel.queue_redraw())
	add_child(reel)
	seek_box = PanelContainer.new()
	var sbs := StyleBoxFlat.new()
	sbs.bg_color = Color(0, 0, 0, 0.78)
	sbs.set_corner_radius_all(8)
	sbs.content_margin_left = 18
	sbs.content_margin_right = 18
	sbs.content_margin_top = 12
	sbs.content_margin_bottom = 12
	seek_box.add_theme_stylebox_override("panel", sbs)
	seek_label = Label.new()
	seek_label.add_theme_font_size_override("font_size", 20)
	seek_box.add_child(seek_label)
	seek_box.visible = false
	add_child(seek_box)
	_refresh_buttons()


func _layout() -> void:
	var win := get_viewport().get_visible_rect().size
	var avail_h := win.y - HEAD_H - REEL_H
	var h := avail_h
	var w := roundf(h * _canvas.x / _canvas.y)
	if w > win.x - PANEL_W:
		w = win.x - PANEL_W
		h = roundf(w * _canvas.y / _canvas.x)
	view.position = Vector2(12, HEAD_H + (avail_h - h) * 0.5)
	view.size = Vector2(w, h)
	overlay.position = view.position
	overlay.size = view.size
	header.position = Vector2(12, 8)
	header.size = Vector2(win.x - 24, HEAD_H - 10)
	panel.position = Vector2(w + 30, HEAD_H)
	panel.size = Vector2(win.x - w - 42, avail_h - 6)
	reel.position = Vector2(12, win.y - REEL_H + 4)
	reel.size = Vector2(win.x - 24, REEL_H - 12)
	seek_box.position = view.position + Vector2(20, view.size.y * 0.45)


func _refresh_buttons() -> void:
	for pair in speed_buttons:
		var b: Button = pair[0]
		var s: float = pair[1]
		if s < 0.0:
			b.text = "Play" if paused else "Pause"
			continue
		b.modulate = Color(1.0, 0.85, 0.3) if (not paused and absf(s - speed) < 0.001) else Color(1, 1, 1)


func _say_problem() -> void:
	header.text = "[b][color=#f05048]%s[/color][/b]" % " ".join(PackedStringArray(problems))


func _refresh_ui(f: int) -> void:
	var t_now := _now_wall()
	_refresh_header()
	var pl = game.get("player") if game and is_instance_valid(game) else null
	var em = game.get("enemies") if game and is_instance_valid(game) else null
	var lines := PackedStringArray()
	lines.append("%s / %s   frame %d of %d   %s" % [mmss(t_now), mmss(total_wall()), f, frames_n,
		"PAUSED" if paused else speed_words(speed)])
	if pl:
		lines.append("HP %d / %d    level %d    kills %d    gold %d    creatures %d" % [int(pl.get("hp")), int(pl.get("max_hp")), int(Run.level),
			int(Run.kills), int(Run.run_gold), em.alive_count() if em else 0])
	numbers.text = "\n".join(lines)
	# what the driver had to say (a choice it could not make as recorded)
	if rr:
		var ns: Array = rr.get("notes")
		while _notes_seen < ns.size():
			_note("[color=#f5c040]%s  %s[/color]" % [mmss(t_now), str(ns[_notes_seen])])
			_notes_seen += 1
	# the drift light
	if rr:
		var bad := int(rr.get("checks_bad"))
		var ok := int(rr.get("checks_ok"))
		if bad == 0:
			light_dot.color = GOOD
			light.add_theme_color_override("font_color", GOOD)
			light.text = "In step with the recording: %d of %d checks equal." % [ok, ok]
		else:
			light_dot.color = BAD
			light.add_theme_color_override("font_color", BAD)
			var extra := ""
			if bool(rr.get("assist")) and int(rr.get("assisted")) > 0:
				extra = "  Safety net ON: the hero is pulled to where the player really was (%d times)." % int(rr.get("assisted"))
			light.text = "%s  (%d checks equal, %d different).%s" % [_drift_text, ok, bad, extra]
	if _seek_target >= 0 or _restart_pending:
		seek_box.visible = true
		var tgt := _seek_target
		var frac := float(f) / float(maxi(tgt, 1)) if tgt > 0 else 0.0
		seek_label.text = "Jumping to %s ... %d%%  (%.0f s)" % [mmss(wall_at[clampi(tgt, 0, frames_n)]), int(frac * 100.0),
			float(Time.get_ticks_msec() - _seek_from_ms) / 1000.0]
	else:
		seek_box.visible = false
	overlay.queue_redraw()
	chart.queue_redraw()
	reel.queue_redraw()
	_refresh_buttons()


func _refresh_header() -> void:
	var b: Dictionary = plan.get("build", {})
	var mine := RunReplay.build_info()
	var same := str(b.get("id", "")) == str(mine.get("id", ""))
	var when := str(plan.get("recorded", ""))
	var who := str(plan.get("player", "")) if str(plan.get("player", "")) != "" else "a player"
	var result: String = {"death": "died", "extract": "extracted", "abandon": "quit", "end": "ended"}.get(str(plan.get("result", "")), str(plan.get("result", "")))
	var line1 := "[b]Replaying %s's run of %s[/b]  ·  %s on stage %d  ·  %s at %s  ·  level %d, %d kills" % [who, when,
		_hero_name(str(plan.get("hero", ""))), int(plan.get("stage", 0)), result, mmss(float(plan.get("play_s", 0.0))),
		int(plan.get("level", 0)), int(plan.get("kills", 0))]
	var rec := _build_words(b)
	var here := _build_words(mine)
	var line2 := ""
	if same:
		line2 = "Recorded on build %s  ·  played on the same build [color=#59d873]✓[/color]  ·  %s" % [rec, str(plan.get("device", ""))]
	else:
		line2 = "[color=#f05048]Recorded on build %s  ·  played on build %s: NOT the same build, the replay may go out of step.[/color]" % [rec, here]
	if not problems.is_empty():
		line2 += "\n[color=#f05048]%s[/color]" % " ".join(PackedStringArray(problems))
	header.text = line1 + "\n" + line2


static func _build_words(b: Dictionary) -> String:
	var s := str(b.get("version", "?"))
	var parts: Array = []
	if b.has("utc"):
		parts.append(str(b["utc"]))
	if b.has("git"):
		parts.append(str(b["git"]) + (" dirty" if bool(b.get("dirty", false)) else ""))
	if bool(b.get("unstamped", false)):
		parts.append("unstamped dev run")
	return s + (" (" + ", ".join(PackedStringArray(parts)) + ")" if not parts.is_empty() else "")


func _hero_name(id: String) -> String:
	var c = Registry.character(id) if Registry.has_method("character") else null
	return str(c.display_name) if c != null and c.get("display_name") != null else id


# ---------------------------------------------------------------- drawing

## The finger's touches as rings (fading over RING_S of the video's time) and the stick as a ghost under the thumb.
func _draw_overlay() -> void:
	if rr == null or view.size.x <= 0.0:
		return
	var f := int(rr.get("frame"))
	var k := view.size.x / _canvas.x
	var now := _now_wall()
	# taps: every one whose frame is within RING_S before now
	for tp in taps:
		var a: Array = tp
		var tf := int(a[0])
		if tf > f:
			break
		var age := now - wall_at[clampi(tf, 0, frames_n)]
		if age > RING_S or age < 0.0:
			continue
		var at := Vector2(float(a[1]), float(a[2])) * k
		var fade := 1.0 - age / RING_S
		var down := int(a[3]) == 1
		var r := (18.0 + 40.0 * (1.0 - fade)) * (1.0 if down else 0.7)
		# a dark rim under the yellow, so a ring reads on the sand as well as on the night
		overlay.draw_arc(at, r, 0.0, TAU, 40, Color(0.0, 0.0, 0.0, 0.55 * fade), 8.0)
		overlay.draw_arc(at, r, 0.0, TAU, 40, Color(1.0, 0.9, 0.2, fade), 4.5)
		if down:
			overlay.draw_circle(at, 9.0, Color(0.0, 0.0, 0.0, 0.5 * fade))
			overlay.draw_circle(at, 7.0, Color(1.0, 0.9, 0.2, fade))
	# the stick
	var inp = game.player.input if game and is_instance_valid(game) and game.get("player") and game.player.get("input") else null
	if inp and inp.wants_move and not inp.keyboard:
		var o := _origin_at(f) * k
		var rad := float(PlayerInput.STICK_FULL_PX) * (_canvas.x / 432.0) * float(Settings.stick_size) * k
		overlay.draw_circle(o, rad, Color(1, 1, 1, 0.12))
		overlay.draw_arc(o, rad, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 2.0)
		var thumb := o + (inp.stick_dir as Vector2) * rad
		overlay.draw_circle(thumb, rad * 0.42, Color(1, 1, 1, 0.35))
		overlay.draw_arc(thumb, rad * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 2.0)
	elif inp and inp.wants_move and inp.keyboard:
		var c := Vector2(view.size.x * 0.5, view.size.y - 70.0)
		overlay.draw_line(c, c + (inp.stick_dir as Vector2) * 50.0, Color(1, 1, 1, 0.7), 4.0)
		overlay.draw_string(get_theme_default_font(), c + Vector2(-40, 30), "keyboard", HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(1, 1, 1, 0.7))
	if _highlight_ref != null:
		var hc = _highlight_ref.get_ref()
		if hc != null and is_instance_valid(hc) and (hc as Control).is_visible_in_tree():
			_highlight = (hc as Control).get_global_rect()
		else:
			# its screen has gone: so has the frame
			_highlight_until = 0.0
			_highlight_ref = null
	if _highlight.size.x > 0.0 and _now_wall() <= _highlight_until:
		var hr := Rect2(_highlight.position * k, _highlight.size * k).grow(6.0)
		overlay.draw_rect(hr, Color(1.0, 0.82, 0.25, 0.95), false, 5.0)
		overlay.draw_string(get_theme_default_font(), hr.position + Vector2(0, -8), "PICKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.82, 0.25))
	# the speed in the view's bottom corner (the game's HUD is along its top)
	var tag := "PAUSED" if paused else ("" if speed == 1.0 else speed_words(speed))
	if tag != "":
		var at2 := Vector2(10, view.size.y - 14)
		overlay.draw_rect(Rect2(at2 + Vector2(-4, -24), Vector2(12 + 13 * tag.length(), 32)), Color(0, 0, 0, 0.6))
		overlay.draw_string(get_theme_default_font(), at2, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.3))


func _origin_at(f: int) -> Vector2:
	var o := Vector2(_canvas.x * 0.5, _canvas.y * 0.75)
	for e in origins:
		var a: Array = e
		if int(a[0]) > f:
			break
		o = Vector2(float(a[1]), float(a[2]))
	return o


## HP (red) and level (gold) over the run, the recording's, with the cursor where the replay is.
func _draw_chart() -> void:
	var sz := chart.size
	chart.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.04))
	if frames_n <= 0:
		return
	var top := 1.0
	for p in hp_track:
		top = maxf(top, p.y)
	var lv_top := 1.0
	for p in lv_track:
		lv_top = maxf(lv_top, p.y)
	var tw := total_wall()
	var prev := Vector2.INF
	for p in hp_track:
		var x := wall_at[clampi(int(p.x), 0, frames_n)] / maxf(tw, 0.01) * sz.x
		var q := Vector2(x, sz.y - p.y / top * (sz.y - 18.0) - 4.0)
		if prev != Vector2.INF:
			chart.draw_line(prev, q, BAD, 2.0)
		prev = q
	prev = Vector2.INF
	for p in lv_track:
		var x := wall_at[clampi(int(p.x), 0, frames_n)] / maxf(tw, 0.01) * sz.x
		var q := Vector2(x, sz.y - p.y / lv_top * (sz.y - 18.0) - 4.0)
		if prev != Vector2.INF:
			chart.draw_line(prev, Vector2(q.x, prev.y), WARN, 2.0)
			chart.draw_line(Vector2(q.x, prev.y), q, WARN, 2.0)
		prev = q
	var cx := _now_wall() / maxf(tw, 0.01) * sz.x
	chart.draw_line(Vector2(cx, 0), Vector2(cx, sz.y), Color(1, 1, 1, 0.8), 2.0)
	var font := get_theme_default_font()
	chart.draw_string(font, Vector2(6, 14), "HP (recorded)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BAD)
	chart.draw_string(font, Vector2(120, 14), "level up to %d" % int(lv_top), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WARN)


var _reel_hover := -1.0


## The progress reel: the whole run (the video's time), the part played, the marks (hover names them), the cursor;
## a click jumps there.
func _draw_reel() -> void:
	var sz := reel.size
	var font := get_theme_default_font()
	var y0 := 26.0
	var bar := Rect2(0, y0, sz.x, sz.y - y0 - 18.0)
	reel.draw_rect(bar, Color(1, 1, 1, 0.07))
	var tw := maxf(total_wall(), 0.01)
	var cx := _now_wall() / tw * sz.x
	reel.draw_rect(Rect2(0, y0, cx, bar.size.y), Color(1.0, 0.85, 0.3, 0.22))
	for m in marks:
		var x := wall_at[clampi(int(m["f"]), 0, frames_n)] / tw * sz.x
		var col: Color = MARK_COLOURS.get(str(m["kind"]), INK)
		var tall := str(m["kind"]) in ["boss_start", "boss_end", "death", "revive", "portal", "stage_beaten"]
		reel.draw_line(Vector2(x, y0 + (0.0 if tall else bar.size.y * 0.45)), Vector2(x, y0 + bar.size.y), col, 3.0 if tall else 2.0)
	reel.draw_line(Vector2(cx, y0 - 6), Vector2(cx, y0 + bar.size.y + 4), Color(1, 1, 1), 3.0)
	# minute ticks
	var step := 60.0 if tw > 240.0 else 30.0
	var t := 0.0
	while t <= tw:
		var x := t / tw * sz.x
		reel.draw_line(Vector2(x, y0 + bar.size.y), Vector2(x, y0 + bar.size.y + 5), DIM, 1.0)
		reel.draw_string(font, Vector2(x + 2, sz.y - 2), mmss(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		t += step
	var title := "Progress reel: %s of %s. Gold: level-ups and picks · red: bosses and big hits · white: down · blue: revives, power-ups, the portal" % [mmss(_now_wall()), mmss(tw)]
	if _reel_hover >= 0.0:
		var hf := frame_at_wall(_reel_hover / sz.x * tw)
		var best := ""
		var bd := 9999.0
		for m in marks:
			var x := wall_at[clampi(int(m["f"]), 0, frames_n)] / tw * sz.x
			if absf(x - _reel_hover) < 8.0 and absf(x - _reel_hover) < bd:
				bd = absf(x - _reel_hover)
				best = str(m["label"])
		title = "Click to jump to %s%s" % [mmss(wall_at[hf]), ("  ·  " + best) if best != "" else ""]
		reel.draw_line(Vector2(_reel_hover, y0), Vector2(_reel_hover, y0 + bar.size.y), Color(1, 1, 1, 0.4), 1.0)
	reel.draw_string(font, Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_LEFT, sz.x, 14, INK)


func _on_reel_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_reel_hover = (e as InputEventMouseMotion).position.x
		reel.queue_redraw()
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var x := (e as InputEventMouseButton).position.x
		seek_to_wall(x / maxf(reel.size.x, 1.0) * total_wall())


# ---------------------------------------------------------------- captures (shots=<dir> demo=1)

var _shot_next := ""
## shot_at=<s,s,...>: shots at these wall seconds after the start (at_<s>.png)
var _shot_at: Array = []


func _take_shot(name: String) -> void:
	RenderingServer.render_loop_enabled = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.make_dir_recursive_absolute(_shots_dir)
		img.save_png(_shots_dir.path_join(name + ".png"))
		print("replay: shot " + name)


## The scripted tour the proof's captures come from: play, slow motion with the rings, a jump on the reel, paused and
## stepped, fast, back to the start, the end.
func _demo_tick(delta: float) -> void:
	if rr == null:
		return
	_demo_wait -= delta
	if _demo_wait > 0.0:
		return
	var f := int(rr.get("frame"))
	match _demo_step:
		0:
			if f > 200:
				_shot_next = "01_playing_1x"
				_demo_step = 1
				_demo_wait = 0.5
		1:
			set_speed(0.25)
			_demo_step = 2
			_demo_wait = 2.5
		2:
			_shot_next = "02_slow_0.25x"
			_demo_step = 3
			_demo_wait = 0.5
		3:
			var tgt := float(args.get("demo_seek", "180"))
			seek_to_wall(tgt)
			set_speed(1.0)
			_demo_step = 4
			_demo_wait = 1.0
		4:
			_shot_next = "03_seeking"
			_demo_step = 5
			_demo_wait = 0.3
		5:
			if _seek_target < 0:
				_demo_step = 6
				_demo_wait = 1.5
		6:
			_shot_next = "04_after_jump"
			set_paused(true)
			_demo_step = 7
			_demo_wait = 0.6
		7:
			for _i in range(3):
				step_frame()
			_demo_step = 8
			_demo_wait = 0.6
		8:
			_shot_next = "05_paused_stepped"
			_demo_step = 9
			_demo_wait = 0.4
		9:
			set_speed(8.0)
			_demo_step = 10
			_demo_wait = 3.0
		10:
			_shot_next = "06_fast_8x"
			_demo_step = 11
			_demo_wait = 0.4
		11:
			# a decision on screen at slow speed: to the next card pick
			var next := -1
			for d in plan.get("decisions", []):
				if str((d as Dictionary).get("k", "")) == "card" and int((d as Dictionary).get("f", 0)) > f + 60:
					next = int((d as Dictionary).get("f", 0))
					break
			if next > 0:
				seek_to_wall(wall_at[clampi(next - 4, 0, frames_n)])
			set_speed(0.1)
			_demo_step = 12
			_demo_wait = 1.0
		12:
			if _seek_target < 0:
				_demo_step = 13
				_demo_wait = 1.4
		13:
			_shot_next = "07_card_pick_slow"
			_demo_step = 14
			_demo_wait = 0.5
		14:
			# a finger touch: to just after the next press, slowly, for its ring
			var tf := -1
			for tp in taps:
				if int((tp as Array)[3]) == 1 and int((tp as Array)[0]) > int(rr.get("frame")) + 30:
					tf = int((tp as Array)[0])
					break
			if tf > 0:
				seek_to_wall(wall_at[clampi(tf - 2, 0, frames_n)])
			set_speed(0.25)
			_demo_step = 21
			_demo_wait = 1.0
		21:
			if _seek_target < 0:
				_demo_step = 22
				_demo_wait = 0.5
		22:
			_shot_next = "07b_finger_ring"
			_demo_step = 23
			_demo_wait = 0.5
		23:
			seek_to_wall(10.0)
			_demo_step = 15
			_demo_wait = 1.0
		15:
			if _seek_target < 0 and not _restart_pending and rr != null:
				_demo_step = 16
				_demo_wait = 1.0
		16:
			_shot_next = "08_back_to_10s"
			_demo_step = 17
			_demo_wait = 0.5
		17:
			seek_to_wall(total_wall())
			_demo_step = 18
			_demo_wait = 1.0
		18:
			if _seek_target < 0:
				_demo_step = 19
				_demo_wait = 1.0
		19:
			_shot_next = "09_end"
			_demo_step = 20
			_demo_wait = 1.0
		20:
			print("replay: demo done; checks ok %d bad %d" % [int(rr.get("checks_ok")), int(rr.get("checks_bad"))])
			get_tree().quit(0)

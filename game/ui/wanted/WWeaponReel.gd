## The mutation offer's pre-reel (pass 54, Garry: the weapon whose path goes on the table is picked at random among the
## weapons with a path still open, and the player sees it picked): a strip of the hero's weapon plates runs sideways past
## a brass window in the middle of the screen, ticking as each plate passes it, fast at first and slowing (ease out), and
## stops on the chosen weapon, which flashes brass in a sunburst to the jackpot. A single weapon only wobbles in the window
## for WOBBLE seconds and stops. A tap anywhere skips to the landing. `done` fires HOLD seconds after the landing (a
## second tap fires it at once). Runs while the game is paused.
class_name WWeaponReel
extends Control

signal done

## A plate in the strip and the step from one to the next.
const CELL := 170.0
const STEP := CELL + 46.0
## The landed plate holds this long before `done`.
const HOLD := 0.35
## One weapon: its wobble before it stops.
const WOBBLE := 0.6
## Plates the strip runs past before it stops (at least; more when the hero holds many weapons).
const MIN_CELLS := 12
## Plates left after the landing cell, so the strip runs on off the edge.
const TAIL := 3
## Off the window, a plate is this faint and this small.
const SIDE_ALPHA := 0.45
const SIDE_SCALE := 0.82

var chosen: ContentDef
## Where the window's middle sits (screen px); the card screen puts it where the mutation head's weapon plate will be.
var center := Vector2(540, 300)
var _defs: Array = []
var _plates: Array = []
var _x := 0.0
var _end_x := 0.0
var _last_cell := 0
var _tw: Tween
var _landed := false
var _finished := false
var _flash := 0.0
var _single := false
var _hold_tw: Tween
var _window: Control
## How many ticks the strip made and how many plates it ran past (the tests read them).
var ticks := 0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


## Spin to `chosen_def` over `seconds` past `defs` (WeaponDefs or WeaponInstances; the chosen one is added when
## missing); returns `done`.
func play(defs: Array, chosen_def: ContentDef, seconds: float = 1.5) -> Signal:
	chosen = chosen_def
	var pool: Array = []
	for d in defs:
		var def: ContentDef = d.def if d is WeaponInstance else d as ContentDef
		if def != null and not pool.has(def):
			pool.append(def)
	if chosen != null and not pool.has(chosen):
		pool.append(chosen)
	_single = pool.size() <= 1
	_fill_strip(pool)
	_build()
	_window = Control.new()
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.draw.connect(_draw_window)
	add_child(_window)
	if _single:
		_set_x(0.0)
		_wobble()
	else:
		_set_x(0.0)
		_tw = create_tween()
		_tw.tween_method(_set_x, 0.0, _end_x, maxf(seconds, 0.2)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_tw.tween_callback(_land_from_tween)
	return done


## The strip: MIN_CELLS cells (more with many weapons) and TAIL after the landing cell, which holds the chosen weapon; the
## rest cycle the pool counted from the landing cell with the chosen one first, so its neighbours are never itself.
func _fill_strip(pool: Array) -> void:
	_defs.clear()
	if _single:
		_defs.append(chosen if chosen else (pool[0] if not pool.is_empty() else null))
		_end_x = 0.0
		return
	var order: Array = pool.duplicate()
	order.shuffle()
	order.erase(chosen)
	order.push_front(chosen)
	var n := order.size()
	var cells := maxi(MIN_CELLS, n * 3)
	var land := cells - 1
	for k in range(cells + TAIL):
		_defs.append(order[posmod(k - land, n)])
	_end_x = float(land) * STEP


## The landing cell's index in the strip.
func landing_cell() -> int:
	return 0 if _single else _defs.size() - 1 - TAIL


func _build() -> void:
	for p in _plates:
		(p as Node).queue_free()
	_plates.clear()
	for d in _defs:
		var p := WPlate.new().for_def(d, CELL, false, _level_of(d))
		p.icon_frac = 0.74
		p.border = 5
		p.shadow = 8
		var pd := WPlate.path_of(d)
		if pd.y > 0:
			p.set_dots(pd)
		p.set_kind_mark("")
		p.pivot_offset = Vector2(CELL, CELL) * 0.5
		add_child(p)
		_plates.append(p)


## The level a plate shows: the run's copy of the weapon, else 1.
static func _level_of(d: ContentDef) -> int:
	var run := W.node("Run")
	if run and d and run.has_method("weapon_instance"):
		var inst = run.weapon_instance(d.id)
		if inst != null:
			return int(inst.level)
	return 1


## The strip `x` px along: the plate at `x` sits in the window; a tick each time a new plate reaches it.
func _set_x(x: float) -> void:
	_x = x
	for i in _plates.size():
		var p: WPlate = _plates[i]
		var px := center.x + i * STEP - x
		p.position = Vector2(px - CELL * 0.5, center.y - CELL * 0.5)
		var off := absf(px - center.x)
		p.visible = (px > -CELL and px < size.x + CELL) if size.x > 0.0 else true
		var k := clampf(off / STEP, 0.0, 1.0)
		p.modulate.a = lerpf(1.0, SIDE_ALPHA, k)
		if not (_landed and i == landing_cell()):
			p.scale = Vector2.ONE * lerpf(1.0, SIDE_SCALE, k)
	var cell := int((x + STEP * 0.5) / STEP)
	if cell != _last_cell:
		_last_cell = cell
		ticks += 1
		W.sfx_first(["ui_reel_tick", "ui_tap"])


## One weapon: it shakes in the window, damped, and stops.
func _wobble() -> void:
	var p: WPlate = _plates[0] if not _plates.is_empty() else null
	_tw = create_tween()
	if p:
		for k in 4:
			var a := deg_to_rad(9.0) * (1.0 - k / 4.0) * (1.0 if k % 2 == 0 else -1.0)
			_tw.tween_property(p, "rotation", a, WOBBLE / 5.0).set_trans(Tween.TRANS_SINE)
			_tw.tween_callback(func(): W.sfx_first(["ui_reel_tick", "ui_tap"]))
		_tw.tween_property(p, "rotation", 0.0, WOBBLE / 5.0).set_trans(Tween.TRANS_SINE)
	else:
		_tw.tween_interval(WOBBLE)
	_tw.tween_callback(_land_from_tween)


## The spin ran out by itself: its tween is done, nothing to stop.
func _land_from_tween() -> void:
	_tw = null
	_land()


## The landing: the chosen plate pops and flashes brass, a sunburst behind it, the jackpot; `done` after HOLD.
func _land() -> void:
	if _landed:
		return
	_landed = true
	if _tw and _tw.is_valid():
		_tw.kill()
	if not _single:
		_set_x(_end_x)
	var p: WPlate = _plates[landing_cell()] if not _plates.is_empty() else null
	if p:
		p.rotation = 0.0
		p.modulate.a = 1.0
		p.scale = Vector2.ONE * 1.25
		var tp := create_tween()
		tp.tween_property(p, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flash = 1.0
	var tf := create_tween()
	tf.tween_method(func(v: float):
		_flash = v
		if _window:
			_window.queue_redraw(), 1.0, 0.0, 0.45)
	WCelebrate.burst(self, center, 0, 1.0)
	W.sfx_first(["ui_jackpot"])
	_hold_tw = create_tween()
	_hold_tw.tween_interval(HOLD)
	_hold_tw.tween_callback(_finish)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _hold_tw and _hold_tw.is_valid():
		_hold_tw.kill()
	done.emit()


func is_landed() -> bool:
	return _landed


func is_finished() -> bool:
	return _finished


## A tap anywhere: spinning, straight to the landing; landed, straight on.
func skip() -> void:
	if not _landed:
		_land()
	else:
		_finish()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _finished:
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if tap:
		skip()
		get_viewport().set_input_as_handled()


## The window: a brass frame in an ink border round the middle cell, a soft brass light inside it on the landing.
func _draw_window() -> void:
	var r := Rect2(center - Vector2(CELL, CELL) * 0.5, Vector2(CELL, CELL)).grow(16.0)
	if _flash > 0.0:
		for i in 8:
			var k := float(i) / 8.0
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(W.BRASS, 0.09 * _flash)
			sb.set_corner_radius_all(int(20 + 60 * (1.0 - k)))
			_window.draw_style_box(sb, r.grow(70.0 * (1.0 - k)))
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_corner_radius_all(20)
	frame.set_border_width_all(10)
	frame.border_color = W.INK
	frame.anti_aliasing = true
	_window.draw_style_box(frame, r)
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.set_corner_radius_all(16)
	inner.set_border_width_all(5)
	inner.border_color = W.BRASS.lerp(Color(1, 0.95, 0.7), _flash * 0.6)
	inner.anti_aliasing = true
	_window.draw_style_box(inner, r.grow(-3.0))
	# the window's two pointers: brass wedges over and under it, pointing in
	for sy: float in [-1.0, 1.0]:
		var tip := Vector2(center.x, r.position.y - 6.0) if sy < 0.0 else Vector2(center.x, r.end.y + 6.0)
		var base_y := tip.y + 26.0 * sy
		var pts := PackedVector2Array([tip, Vector2(center.x + 22.0, base_y), Vector2(center.x - 22.0, base_y)])
		_window.draw_colored_polygon(pts, W.BRASS)
		_window.draw_polyline(pts + PackedVector2Array([pts[0]]), W.INK, 3.0, true)

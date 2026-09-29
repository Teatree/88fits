## The gate (Wanted screen 09): not a screen. After a pick or the chest, the run stays paused while the dim lifts from
## 78 % to 40 % and the picked card shrinks and flies (rotating -8 degrees) into its HUD slot, which takes a brass
## border and a brass level tag; "TAP TO GO" and "Still paused. They'll wait." wait at y 1500. Any touch resumes, and
## the same touch can start the joystick (the gate lets it through).
class_name ResumeGate
extends Control

signal resumed

var hud: HUD
var _dim: ColorRect
var _go: WText
var _sub: WText
var _t := 0.0
var _slot_id := ""
var _flyer: Control
var _streaks: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_dim = W.dim(W.DIM_GATE, false)
	# under the HUD: the plates stay crisp while the world waits behind 40 % sepia
	_dim.z_index = -1
	add_child(_dim)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 8)
	col.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	col.offset_top = 1500
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_go = W.text("TAP TO GO", W.slab(), 64, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_go.stroke = 2
	_go.shadow = 5
	col.add_child(_go)
	_sub = W.text("Still paused. They'll wait.", W.serif(400, true), 28, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_sub.shadow = 2
	col.add_child(_sub)


## `pick` is {def, rect}: the card the player just took and where it was on screen (empty for a skip).
func open(pick: Dictionary = {}) -> void:
	_t = 0.0
	visible = true
	_go.modulate.a = 0.0
	_sub.modulate.a = 0.0
	_dim.color = Color(W.DIM.r, W.DIM.g, W.DIM.b, W.DIM.a)
	var tw := create_tween()
	var def: ContentDef = pick.get("def")
	var from: Rect2 = pick.get("rect", Rect2())
	_slot_id = def.id if def else ""
	var to := hud.slot_rect(_slot_id) if hud and def else Rect2()
	if def and to.size.x > 0.0 and from.size.x > 0.0:
		_fly(def, from, to)
		tw.tween_interval(0.35)
		tw.tween_callback(func():
			if hud:
				hud.mark_slot(_slot_id, true))
	tw.tween_property(_dim, "color:a", W.DIM_GATE.a, 0.3)
	tw.parallel().tween_property(_go, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(_sub, "modulate:a", 1.0, 0.3)


## The card as a small paper tag (the plate and the name) that shrinks from where it was into the slot, turning -8
## degrees, with two paper streaks behind it.
func _fly(def: ContentDef, from: Rect2, to: Rect2) -> void:
	if _flyer:
		_flyer.queue_free()
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 4, 6).pad(20, 20, 20, 20))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := WPlate.new().for_def(def, 118.0)
	plate.icon_frac = 0.7
	row.add_child(plate)
	var nm := W.slab_text(def.display_name, 40, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 40.0)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nm)
	p.add_child(row)
	add_child(p)
	p.reset_size()
	p.pivot_offset = Vector2(p.size.x, 0)
	p.position = Vector2(from.end.x - p.size.x, from.position.y + (from.size.y - p.size.y) * 0.5)
	_flyer = p
	var end_scale := clampf(to.size.x / 118.0 * 0.9, 0.2, 0.6)
	var end_pos := Vector2(to.end.x - p.size.x, to.position.y)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "position", end_pos, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "scale", Vector2(end_scale, end_scale), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "rotation", deg_to_rad(-8.0), 0.35)
	# it goes into the slot: the slot keeps the brass mark while the gate waits
	tw.chain().tween_property(p, "modulate:a", 0.0, 0.12)
	for s in _streaks:
		(s as Node).queue_free()
	_streaks.clear()
	var mid := (from.get_center() + to.get_center()) * 0.5
	for k in 2:
		var l := ColorRect.new()
		l.color = Color(W.PAPER.r, W.PAPER.g, W.PAPER.b, 0.7 - 0.2 * k)
		l.size = Vector2(200 - 60 * k, 6)
		l.position = mid + Vector2(-40 - 20 * k, 20 * k)
		l.rotation = deg_to_rad(-30.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_streaks.append(l)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_go.pivot_offset = _go.size * 0.5
	_go.scale = Vector2.ONE * (1.0 + 0.03 * sin(_t * 4.0))


func tap() -> void:
	if not visible:
		return
	visible = false
	if hud and _slot_id != "":
		hud.mark_slot(_slot_id, false)
	if _flyer:
		_flyer.queue_free()
		_flyer = null
	for s in _streaks:
		(s as Node).queue_free()
	_streaks.clear()
	resumed.emit()


func _input(event: InputEvent) -> void:
	if not visible or _t < 0.25:
		return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		tap()

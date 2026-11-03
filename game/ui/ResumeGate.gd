## The gate (Wanted screen 09): not a screen. After a pick or the chest, the run stays paused while the dim lifts from
## 78 % to 40 % and the picked card shrinks and flies (rotating -8 degrees) into its HUD slot, which takes a brass
## border and a brass level tag; "TAP TO GO" and "Still paused. They'll wait." wait at y 1500. Any touch resumes, and
## the same touch can start the joystick (the gate lets it through), unless it lands on the HUD's strip: there the gate
## keeps it (pass 56: the strip pauses on a tap, so letting it through opened the pause menu the moment the run went on).
class_name ResumeGate
extends Control

signal resumed

## Seconds after it opens before a touch or a key goes on (a touch landing with the pick must not skip it). Pass 119: 0.25
## -> 0.15, and a movement key still held from before the screen goes on as soon as this has passed (_process).
const GUARD := 0.15

var hud: HUD
var _dim: ColorRect
var _go: WText
var _sub: WText
var _t := 0.0
## pass 120 (lane REPLAY): the held key's go is on its way (an input event, see _process)
var _key_sent := false
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
	# pass 122 (the review of lane UIHUD; Garry: "Toasts, banners, hints and TAP TO GO stay as they are"): the Wanted
	# faces and paper under both themes (W.wanted_text; the line in Bitter italic, its paper put back after W.text)
	_go = W.wanted_text("TAP TO GO", 64, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_go.stroke = 2
	_go.shadow = 5
	col.add_child(_go)
	_sub = W.text("Still paused. They'll wait.", W.wanted_serif(400, true), 28, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_sub.color = W.PAPER
	_sub.shadow = 2
	col.add_child(_sub)


## `pick` is {def, rect, level}: the card the player just took, where it was on screen and the level it lands on (pass
## 48: the flying plate's colour; the level held when the pick does not say) (empty for a skip).
func open(pick: Dictionary = {}) -> void:
	_t = 0.0
	_key_sent = false
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
		_fly(def, from, to, int(pick.get("level", 0)))
		tw.tween_interval(0.35)
		tw.tween_callback(func():
			if hud:
				hud.mark_slot(_slot_id, true))
	tw.tween_property(_dim, "color:a", W.DIM_GATE.a, 0.3)
	tw.parallel().tween_property(_go, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(_sub, "modulate:a", 1.0, 0.3)


## The level `def` is held at now (the pick has landed by the time the gate opens): a weapon's, a passive's or a
## line's; 0 for anything else.
static func held_level(def: ContentDef) -> int:
	if def is WeaponDef:
		var inst: WeaponInstance = Run.weapon_instance(def.id)
		return inst.level if inst else 0
	if def is PassiveDef:
		return Run.passive_level(def.id)
	return 0


## The card as a small paper tag (the plate, in the colour of the level it lands on, and the name) that shrinks from
## where it was into the slot, turning -8 degrees, with two paper streaks behind it.
func _fly(def: ContentDef, from: Rect2, to: Rect2, level: int = 0) -> void:
	if _flyer:
		_flyer.queue_free()
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 4, 6).pad(20, 20, 20, 20))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := WPlate.new().for_def(def, 118.0, false, level if level > 0 else held_level(def))
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
	# pass 119: a movement key held through the screen (the PC) goes on as soon as the guard has passed
	if _t >= GUARD and not Lockstep.replaying and not _key_sent and Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.1:
		# pass 120 (lane REPLAY): it goes on as an input event (between frames, as a finger's tap does), so the recording
		# keeps it and its replay takes it at the same moment (a tap from _process was neither kept nor replayed)
		_key_sent = true
		var e := InputEventAction.new()
		e.action = KEY_GO
		e.pressed = true
		Input.parse_input_event(e)
		return
	_go.pivot_offset = _go.size * 0.5
	_go.scale = Vector2.ONE * (1.0 + 0.03 * sin(_t * 4.0))


func tap() -> void:
	if not visible:
		return
	RunReplay.note("gate")
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


const KEY_GO := &"resume_gate_key_go"


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventAction and (event as InputEventAction).action == KEY_GO:
		tap()
		get_viewport().set_input_as_handled()
		return
	if _t < GUARD:
		return
	# pass 119 (the lead; Garry's lost step after a level-up, "a solution that works for both PC and Mobile"): on the PC a
	# movement key goes on too, and the hero moves at once (PlayerInput reads the keys from the next frame)
	if event is InputEventKey and event.pressed and not event.echo and _move_key(event):
		tap()
		return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		tap()
		# a tap on the strip ends here (pass 56): let through, it also reached the strip, which paused the run the gate had
		# just let go (the pause menu opened on the tap to go); lower down it goes on and can start the stick
		if on_strip(event.position, get_viewport_rect().size):
			get_viewport().set_input_as_handled()


## Whether a key event is one of the hero's movement keys (the Input Map's move_* actions).
static func _move_key(event: InputEvent) -> bool:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		if InputMap.has_action(a) and event.is_action(a):
			return true
	return false


## Whether a finger at `p` (canvas px, the visible canvas `vp` across) is on the HUD's strip, where a tap pauses: what
## PlayerInput's thumb zone leaves out (HUD.band_h, scaled with the canvas width as there).
static func on_strip(p: Vector2, vp: Vector2) -> bool:
	if vp.x <= 0.0 or vp.y <= 0.0:
		return false
	return p.y <= HUD.band_h * vp.x / 1080.0

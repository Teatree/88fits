## The frame every modal that pauses the run shares: a sepia dim over the world (never a blur), the header stack at
## y 110, content from y 470, a button row with its bottom 90 px up. It enters as the design says: the dim fades in
## over 200 ms, the header drops 40 px (250 ms, ease out), the content slides up 60 px, 60 ms apart; it leaves in 150 ms.
## While one is up the HUD steps aside (group "wanted_modal").
class_name WModal
extends Control

var dim: ColorRect
var header: WModalHeader
var content: Control
var buttons: HBoxContainer
var dim_color := W.DIM
var _debug_btn: WButton


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("wanted_modal")


func build_dim(c: Color = W.DIM) -> ColorRect:
	dim_color = c
	dim = W.dim(c, true)
	add_child(dim)
	return dim


func build_header(star: String, title: String, italic: String = "", title_px: int = 150, title_color: Color = W.PAPER,
		top: float = 110.0, star_color: Color = W.PAPER) -> WModalHeader:
	header = WModalHeader.make(star, title, italic, title_px, title_color, 30, top, star_color)
	add_child(header)
	return header


## The bottom row: 48 px side margins, 24 px apart, its bottom 90 px above the screen's.
func build_buttons(height: float = 108.0) -> HBoxContainer:
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	buttons.offset_left = 48
	buttons.offset_right = -48
	buttons.offset_bottom = -90
	buttons.offset_top = -90 - height
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(buttons)
	return buttons


## The developer's hand on the pick screens (the developer menu's "Debug buttons on modals"): a small ink button at
## the bottom right, only when that switch is on.
func build_debug_button(on_press: Callable) -> void:
	_debug_btn = WButton.make(["debug"], 22, WButton.SECONDARY, 3, 0, 8.0, 14.0)
	_debug_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_debug_btn.offset_left = -170
	_debug_btn.offset_top = -80
	_debug_btn.offset_right = -24
	_debug_btn.offset_bottom = -24
	_debug_btn.modulate.a = 0.7
	_debug_btn.pressed.connect(on_press)
	add_child(_debug_btn)
	_debug_btn.visible = false


func _sync_debug_button() -> void:
	if _debug_btn:
		var s := W.node("Settings")
		# the developer menu's switch, or the player's own debug mode (pass 44: ten taps on the hints switch)
		_debug_btn.visible = s != null and (bool(s.get("debug_modal_buttons")) or bool(s.get("debug_mode")))


## Show with the design's entry motion; `stagger` is the content's children that slide up one after another.
func enter(stagger: Array = []) -> void:
	visible = true
	_sync_debug_button()
	if dim:
		dim.color = Color(dim_color.r, dim_color.g, dim_color.b, 0.0)
		var td := create_tween()
		td.tween_property(dim, "color:a", dim_color.a, 0.2)
	if header:
		header.drop_in()
	var i := 0
	for c in stagger:
		var ctl := c as Control
		if ctl == null:
			continue
		ctl.modulate.a = 0.0
		# bound to the piece it moves: freed early, the tween goes with it
		var tw := ctl.create_tween()
		tw.tween_interval(0.06 * i)
		tw.tween_callback(func(): _slide_in(ctl))
		i += 1


func _slide_in(ctl: Control) -> void:
	if not is_instance_valid(ctl):
		return
	var y := ctl.position.y
	ctl.position.y = y + 60.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ctl, "position:y", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctl, "modulate:a", 1.0, 0.2)


func leave() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		visible = false
		modulate.a = 1.0)

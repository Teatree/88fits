## Common frame for hub screens: dark ground, header with title and back, scrolling content column.
class_name ScreenBase
extends Control

const TITLE := "res://ui/TitleScreen.tscn"

var content: VBoxContainer
var header: HBoxContainer
var title_label: Label


func _ready() -> void:
	UiKit.fullscreen(self)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	UiKit.fullscreen(bg)
	add_child(bg)
	var v := UiKit.vbox(18)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 40
	v.offset_right = -40
	v.offset_top = 70
	v.offset_bottom = -50
	add_child(v)
	header = UiKit.hbox(20)
	var back := UiKit.button("‹ Back", 30, false, 80)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size = Vector2(170, 80)
	back.pressed.connect(on_back)
	header.add_child(back)
	title_label = UiKit.label("", 56, UiKit.INK)
	header.add_child(title_label)
	v.add_child(header)
	content = UiKit.vbox(16)
	v.add_child(UiKit.scroll(content))
	build()
	UiFx.stagger(content, 0.035)


func build() -> void:
	pass


func set_title(t: String) -> void:
	title_label.text = t


func on_back() -> void:
	go(TITLE)


func go(path: String) -> void:
	UiFx.go(get_tree(), path)


func clear_content() -> void:
	for c in content.get_children():
		c.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		on_back()
	elif event.is_action_pressed("ui_cancel"):
		on_back()

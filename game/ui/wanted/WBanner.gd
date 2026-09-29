## The banner: takes the HUD's top row for 2 s. It drops from above the screen to the row's line over 250 ms, holds,
## and rises out. Ink with paper text for news (BOSS DOWN, STAGE 2), ember with the weapon's icon for EVOLVED · NAME.
## Alfa Slab 36, tracked (the compact row since pass 41; the mock's was 44).
class_name WBanner
extends PanelContainer

signal shown(on: bool)

const HOLD := 2.0
var _row: HBoxContainer
var _icon: TextureRect
var _text: WText
var _tw: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 20)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(46, 46)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_icon)
	_text = W.text("", W.slab(W.em(36, 0.08)), 36, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 36 * 1.15)
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_text)


## Show `t`; `ember` for an evolution (with its icon), ink otherwise.
func play(t: String, ember: bool = false, icon: Texture2D = null, top: float = 30.0) -> void:
	_text.text = t.to_upper()
	_text.color = W.INK if ember else W.PAPER
	_icon.texture = icon
	_icon.visible = icon != null
	var hb := W.box(W.EMBER if ember else W.INK, 4, 5).pad(52, 14, 52, 14)
	add_theme_stylebox_override("panel", hb)
	visible = true
	reset_size()
	var w := get_combined_minimum_size().x
	size = Vector2(w, get_combined_minimum_size().y)
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) * 0.5, -120.0)
	if _tw:
		_tw.kill()
	shown.emit(true)
	_tw = create_tween()
	_tw.tween_property(self, "position:y", top, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_interval(HOLD)
	_tw.tween_property(self, "position:y", -140.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tw.tween_callback(func():
		visible = false
		shown.emit(false))


func is_up() -> bool:
	return visible

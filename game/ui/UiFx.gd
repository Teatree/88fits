## Motion for the UI. Overlays fade and slide in, lists stagger, buttons squash when pressed, scenes cross-fade
## through black. Everything is a Tween on the control itself, so it keeps running while the game is paused
## whenever the control's process mode allows it (the in-run overlays are PROCESS_MODE_ALWAYS).
class_name UiFx

const IN := 0.22
const OUT := 0.14


## Fade the whole overlay in and slide its first anchored child up 40 px. Call right after `visible = true`.
static func enter(root: Control, slide: Control = null, dur: float = IN) -> void:
	root.modulate.a = 0.0
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, dur * 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if slide:
		var y := slide.position.y
		slide.position.y = y + 40.0
		var tw2 := slide.create_tween()
		tw2.tween_property(slide, "position:y", y, dur).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


## Scale + fade pop on one control (a dialog box, a banner, a chip). Pivot is centred once the layout exists.
static func pop(c: Control, delay: float = 0.0, from_scale: float = 0.86, dur: float = 0.3) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(from_scale, from_scale)
	var tw := c.create_tween()
	tw.tween_callback(func(): c.pivot_offset = c.size * 0.5)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.6)
	tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Stagger the children of a list so they appear one after another.
static func stagger(container: Node, per: float = 0.045, max_items: int = 14) -> void:
	var i := 0
	for c in container.get_children():
		if c is Control and c.visible:
			pop(c, minf(i, max_items) * per, 0.92, 0.26)
			i += 1


## Quick "picked" punch before an overlay closes.
static func punch(c: Control, scale_to: float = 1.05, dur: float = 0.12) -> Tween:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(scale_to, scale_to), dur * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, dur * 0.5)
	return tw


## Buttons squash while held.
static func pressable(b: BaseButton) -> void:
	b.button_down.connect(func():
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.96, 0.96), 0.06).set_trans(Tween.TRANS_SINE))
	b.button_up.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## Fade a control out, then hide it.
static func leave(c: Control, dur: float = OUT) -> void:
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, dur)
	tw.tween_callback(func(): c.visible = false; c.modulate.a = 1.0)


## Cross-fade through black into another scene. The overlay lives on the root so it survives the scene change.
static func go(tree: SceneTree, path: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = Color(0.04, 0.035, 0.06, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.modulate.a = 0.0
	layer.add_child(rect)
	tree.root.add_child(layer)
	var tw := rect.create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, 0.16)
	tw.tween_callback(func(): tree.change_scene_to_file(path))
	tw.tween_interval(0.06)
	tw.tween_property(rect, "modulate:a", 0.0, 0.3)
	tw.tween_callback(layer.queue_free)

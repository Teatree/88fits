extends GdUnitTestSuite

## Pass 37: the UI answers a finger. The phone sends raw touch with no mouse events behind it (emulate_mouse_from_touch
## off), so the volume sliders never moved (TouchSlider now reads the touch), and a swipe that started on a button in a
## list pressed it on release (TouchScroll now tells the list it is scrolling, which takes the tap back). The whole UI is
## checked by tools/touch_audit.gd; these pin the two pieces.


func _touch(at: Vector2, pressed: bool, index := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	get_tree().root.push_input(e, true)


func _drag(at: Vector2, rel: Vector2, index := 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	e.relative = rel
	get_tree().root.push_input(e, true)


func _swipe(from: Vector2, to: Vector2, steps := 8) -> void:
	_touch(from, true)
	var prev := from
	for k in range(1, steps + 1):
		var p := from.lerp(to, float(k) / float(steps))
		_drag(p, p - prev)
		prev = p
	_touch(to, false)


func _slider() -> TouchSlider:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(900, 900)
	add_child(host)
	var s := UiKit.slider(0.5, 0.0, 1.0) as TouchSlider
	host.add_child(s)
	s.position = Vector2(100, 100)
	s.size = Vector2(500, 84)
	return s


func test_the_sliders_are_touch_sliders() -> void:
	var s := UiKit.slider(0.5, 0.0, 1.0)
	assert_bool(s is TouchSlider).is_true()
	s.free()


func test_a_finger_slides_the_knob() -> void:
	var s := _slider()
	await get_tree().process_frame
	var r := s.get_global_rect()
	_swipe(Vector2(r.position.x + r.size.x * 0.5, r.get_center().y), Vector2(r.position.x + r.size.x * 0.95, r.get_center().y))
	assert_float(s.value).is_greater(0.85)
	# a tap near the start puts the knob there
	_touch(Vector2(r.position.x + 10.0, r.get_center().y), true)
	_touch(Vector2(r.position.x + 10.0, r.get_center().y), false)
	assert_float(s.value).is_less(0.1)
	assert_bool(TouchSlider.holds(0)).is_false()


func test_a_swipe_up_on_a_slider_leaves_the_knob() -> void:
	var s := _slider()
	await get_tree().process_frame
	var c := s.get_global_rect().get_center()
	_swipe(c, c - Vector2(8, 200))
	assert_float(s.value).is_equal_approx(0.5, 0.0001)
	assert_bool(TouchSlider.holds(0)).is_false()


func test_a_swipe_on_a_list_scrolls_it_and_presses_nothing() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var sc := UiKit.scroll(col)
	sc.position = Vector2(50, 50)
	sc.size = Vector2(500, 400)
	host.add_child(sc)
	var pressed := [0]
	var first: Button = null
	for k in range(12):
		var b := Button.new()
		b.text = "row %d" % k
		b.custom_minimum_size = Vector2(0, 100)
		b.pressed.connect(func(): pressed[0] += 1)
		col.add_child(b)
		if first == null:
			first = b
	var ts := TouchScroll.new(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	var c := first.get_global_rect().get_center()
	# the owner feeds its _input to the helper before the controls see the event; here, by hand, in the same order
	var steps := 10
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = c
	ev.pressed = true
	ts.input(ev)
	get_tree().root.push_input(ev, true)
	var prev := c
	for k in range(1, steps + 1):
		var p := c.lerp(c - Vector2(0, 260), float(k) / float(steps))
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = p
		d.relative = p - prev
		prev = p
		ts.input(d)
		get_tree().root.push_input(d, true)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = prev
	up.pressed = false
	ts.input(up)
	get_tree().root.push_input(up, true)
	assert_int(sc.scroll_vertical).is_greater(100)
	assert_int(pressed[0]).is_equal(0)
	# and a plain tap still presses
	sc.scroll_vertical = 0
	await get_tree().process_frame
	var c2 := first.get_global_rect().get_center()
	_touch(c2, true)
	_touch(c2, false)
	assert_int(pressed[0]).is_equal(1)

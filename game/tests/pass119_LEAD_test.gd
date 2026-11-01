## Pass 119 (the lead). Garry: "when I return from the level up screen I often end up loosing a bit of momentum because of
## a tiny delay between the tap being registered and the move actually starting ... a solution that works for both PC
## and Mobile": the stick a pause took away is carried to the first touch after it (PlayerInput.carry), and the gate goes
## on to a movement key (ResumeGate).
extends GdUnitTestSuite


func _input_node() -> PlayerInput:
	var pi: PlayerInput = auto_free(PlayerInput.new())
	add_child(pi)
	return pi


func _press(pi: PlayerInput, at: Vector2, idx: int = 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = at
	e.pressed = true
	pi._unhandled_input(e)


func _drag(pi: PlayerInput, at: Vector2, idx: int = 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = at
	pi._unhandled_input(e)


func _lift(pi: PlayerInput, idx: int = 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.pressed = false
	pi._unhandled_input(e)


## The thumb pushing the stick right at full, then a pause taking it away.
func _paused_while_running(pi: PlayerInput) -> Vector2:
	var vp := pi.get_viewport().get_visible_rect().size
	var at := Vector2(vp.x * 0.5, vp.y * 0.8)
	_press(pi, at)
	_drag(pi, at + Vector2(pi.radius_px(), 0))
	pi._process(0.016)
	assert_float(pi.stick_dir.x).is_greater(0.9)
	pi.ui_blocking = true
	pi.force_release()
	assert_bool(pi.wants_move).is_false()
	pi.ui_blocking = false
	return at


func test_the_first_touch_after_a_pause_starts_with_the_old_push() -> void:
	var pi := _input_node()
	var at := _paused_while_running(pi)
	pi.resumed()
	# the gate's tap, anywhere: the stick is at once where it was (the same way, the same throttle)
	_press(pi, at + Vector2(-50, 30))
	pi._process(0.016)
	assert_float(pi.stick_dir.x).is_greater(0.9)
	assert_float(absf(pi.stick_dir.y)).is_less(0.05)


func test_the_thumbs_own_drag_takes_over() -> void:
	var pi := _input_node()
	var at := _paused_while_running(pi)
	pi.resumed()
	_press(pi, at)
	pi._process(0.016)
	# a turn back: once the drag reaches CARRY_FADE of the reach the old push is gone and the stick points where he drags
	_drag(pi, at + Vector2(-pi.radius_px() * PlayerInput.CARRY_FADE, 0))
	pi._process(0.016)
	assert_float(pi.stick_dir.x).is_less(-0.5)
	assert_bool(pi.carry == Vector2.ZERO).is_true()
	# a small wiggle early on keeps the old way
	var pj := _input_node()
	var at2 := _paused_while_running(pj)
	pj.resumed()
	_press(pj, at2)
	_drag(pj, at2 + Vector2(0, 8))
	pj._process(0.016)
	assert_float(pj.stick_dir.x).is_greater(0.8)


func test_no_push_is_carried_late_or_after_a_lift() -> void:
	var pi := _input_node()
	var at := _paused_while_running(pi)
	pi.resumed()
	pi._resumed_ms -= int(PlayerInput.CARRY_WINDOW * 1000.0) + 200
	_press(pi, at)
	pi._process(0.016)
	assert_float(pi.stick_dir.length()).is_less(0.01)
	# a lift drops a carried push
	var pj := _input_node()
	var at2 := _paused_while_running(pj)
	pj.resumed()
	_press(pj, at2)
	_lift(pj)
	_press(pj, at2)
	pj._process(0.016)
	assert_float(pj.stick_dir.length()).is_less(0.01)


func test_a_still_thumb_before_the_pause_carries_nothing() -> void:
	var pi := _input_node()
	pi.ui_blocking = true
	pi.force_release()
	pi.ui_blocking = false
	pi.resumed()
	var vp := pi.get_viewport().get_visible_rect().size
	_press(pi, Vector2(vp.x * 0.5, vp.y * 0.8))
	pi._process(0.016)
	assert_float(pi.stick_dir.length()).is_less(0.01)


func test_the_gate_goes_on_to_a_movement_key() -> void:
	assert_float(ResumeGate.GUARD).is_less_equal(0.15)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_W
	k.keycode = KEY_W
	k.pressed = true
	assert_bool(ResumeGate._move_key(k)).is_true()
	var other := InputEventKey.new()
	other.keycode = KEY_P
	other.physical_keycode = KEY_P
	other.pressed = true
	assert_bool(ResumeGate._move_key(other)).is_false()

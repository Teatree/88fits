## Pass 117 (Garry: "the breaking isn't clear. It looks like I am just picking the barrels up. Let's make the break more
## obvious looking. Complete with some debris that lingers for a bit"): a smashed barrel's painting comes apart
## (core/systems/BarrelDebris.gd): the stump stays on its spot, the lid and the staves fly, every piece lands and lies
## LINGER seconds, then dissolves.
extends GdUnitTestSuite


func _debris() -> BarrelDebris:
	var d: BarrelDebris = auto_free(BarrelDebris.new())
	add_child(d)
	d.setup(null, null, BarrelField.SPRITES)
	return d


func _run_for(d: BarrelDebris, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		d._process(0.05)
		t += 0.05


func test_a_barrel_breaks_into_a_stump_a_lid_and_its_staves() -> void:
	var d := _debris()
	var n := d.burst(1, Vector3.ZERO, 1.15, Vector3(0, 0, 1.3))
	assert_int(n).is_equal(2 + BarrelDebris.COLS)
	assert_int(d.live_count()).is_equal(n)


func test_the_pieces_land_lie_and_then_go() -> void:
	var d := _debris()
	d.burst(0, Vector3.ZERO, 1.06, Vector3(0, 0, 1.3))
	_run_for(d, 2.5)
	var base := BarrelDebris.POOL * 0
	for k in 2 + BarrelDebris.COLS:
		assert_int(d._rest[base + k]).override_failure_message("piece %d still flying" % k).is_equal(2)
	# the stump stays near its spot; the others spread round it, but not across the map
	assert_float(Vector2(d._pos[base].x, d._pos[base].z).length()).is_less(0.6)
	for k in range(1, 2 + BarrelDebris.COLS):
		assert_float(Vector2(d._pos[base + k].x, d._pos[base + k].z).length()).is_less(4.5)
	# still lying a little before LINGER, gone after LINGER + FADE
	_run_for(d, BarrelDebris.LINGER - 2.5 - 0.2)
	assert_int(d.live_count()).is_equal(2 + BarrelDebris.COLS)
	_run_for(d, BarrelDebris.FADE + 0.5)
	assert_int(d.live_count()).is_equal(0)


func test_a_full_ring_takes_the_oldest_pieces() -> void:
	var d := _debris()
	for k in 40:
		d.burst(2, Vector3(k, 0, 0), 1.12, Vector3(k, 0, 1.3))
	assert_int(d.live_count()).is_less_equal(BarrelDebris.POOL)

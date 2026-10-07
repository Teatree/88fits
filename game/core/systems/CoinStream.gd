## The Strongbox's coin stream (pass 58, Garry: "There should be an indicator of what happened whenever a player
## deposits money with the coin-depositing structure ... coins flying out of the player and into the chest. The coins
## flying should be visible and noticeable but they should be 3D coins and it should take 3 seconds at least. After the
## coins arrive the chest flies away. There should be more coins and they're more intense and move quicker the more coins
## the player deposits. If it's a couple of coins then they should look like a couple of coins. Keep in mind that coins
## are yellow and the background is oftentimes yellow so they need to be noticeable.").
## StructureManager.deposit starts a stream when the hero banks: count_for(gold) coins (one a gold up to COINS_LITERAL,
## then a slower climb to COINS_MAX), each worth its share of the gold, leave his chest one after another and arc into the
## box's lid; the last lands duration_for(gold) seconds after the deposit (MIN_SECONDS at least). The more gold, the more
## coins, the quicker each flight, the closer together and the brighter their glint (intensity_for). A coin is a 3D coin
## drawn by core/shaders/coin_flight.gdshader (the pickup coin's face in a thicker dark rim, a dark edge, a glint sweeping
## across it), flipping as it flies, with a soft dark shadow on the sand under it that shrinks and pales as it climbs,
## and now and then a sparkle. Every landing pings (pk_coin's sound on this node's own players, higher as the stream goes
## on) and calls on_arrive (the box bounces and shines); after the last, on_done (only then does the balloon lift the
## box). The purse on the HUD counts down as the coins leave the hero (the gold itself was banked the moment he used the
## box, Game.bank_purse). One node for every stream, StructureManager's child; drawn by two MultiMeshes that are empty
## between deposits. Its own random sequence: the shared one is replayed by the tests.
extends Node3D

## The flying coin: a little bigger than a pickup coin (PickupManager.COIN_R 0.21), so it reads on a phone
const COIN_R := 0.3
const COIN_H := 0.075
## and it grows by COIN_ZOOM_KEEP of how far out the run's camera has pulled (CameraRig.zoom(), about 1.3 to 1.5 late in a
## run, 2.1 at most), as the death splash does, so a late deposit of a couple of coins is still a couple of coins, not two
## specks (pass 58 review)
const COIN_ZOOM_KEEP := 0.5
## How many coins carry `gold`: one a gold ("If it's a couple of coins then they should look like a couple of coins") until
## COINS_LITERAL + COINS_LOG x ln(gold / COINS_LITERAL) falls below it (about 37 gold), then that slower climb, never
## more than COINS_MAX (40 gold: 38 coins, 400: 89, about 1,700 and up: 120)
const COINS_LITERAL := 12
const COINS_LOG := 22.0
const COINS_MAX := 120
## The stream lasts MIN_SECONDS, up to MORE_SECONDS longer for a big deposit (intensity 1)
const MIN_SECONDS := 3.0
const MORE_SECONDS := 0.6
## The first coin leaves this long after the deposit
const LAUNCH_AT := 0.2
## A coin's flight (s) and how high it arcs over the straight line (m), from a couple of coins (intensity 0) to a few
## hundred (1); each coin its own share either side
const FLIGHT_SLOW := 1.15
const FLIGHT_FAST := 0.5
const ARC_HIGH := 2.4
const ARC_LOW := 1.3
## A single coin is tossed high and slow over the whole stream, ARC_SINGLE m over the line, landing as it ends (pass 58
## review: it was in after 1.35 s and the box then sat idle for 2.4 s before it lifted)
const ARC_SINGLE := 3.4
## It leaves the hero's chest, this high over his feet
const FROM_UP := 1.1
## How fast it flips (radians a second), and the glint's sweeps a second and brightness, low to high intensity
const SPIN_SLOW := 8.0
const SPIN_FAST := 15.0
const GLINT_RATE := Vector2(0.8, 1.7)
const GLINT := Vector2(0.45, 1.0)
## The share of its flight it pops to full size in, and the last share it sinks into the box in (never longer than
## SINK_SECONDS: the single coin's long toss would shrink high over the lid)
const POP := 0.12
const SINK := 0.16
const SINK_SECONDS := 0.2
## Its shadow on the sand: SHADOW_R m round on the ground, as dark as SHADOW_ALPHA, smaller and paler as it climbs
const SHADOW_R := 0.36
const SHADOW_ALPHA := 0.5
## A ping at most every PING_GAP s (a dense stream is a quick run of them), its pitch rising from PING_LOW to PING_HIGH
## over the stream
const PING_GAP := 0.05
const PING_LOW := 0.95
const PING_HIGH := 1.75
const PING_ID := "pk_coin"
const PING_PLAYERS := 4
## and each a little softer the denser the stream (dB at intensity 1), so a big deposit is a quick run, not a din
const PING_SOFTER := 4.0
## A sparkle off a coin in the air every SPARKLE_GAP s, twice as often at intensity 1
const SPARKLE_GAP := 0.1
## Coins drawn at once, every stream together
const MAX_DRAWN := 256
## The warm-up (StructureManager.setup): one coin and its shadow drawn far under the map for this long, so the shader
## compiles while the run starts, not on the first deposit
const WARM_SECONDS := 0.5

var game: Node
var map: MapBase
var _streams: Array = []
var _coin_mm: MultiMesh
var _shadow_mm: MultiMesh
var _rng := RandomNumberGenerator.new()
var _players: Array = []
var _player_i := 0
var _warm := 0.0
var _shown := -1          # the purse the HUD was last told
var _shown_run := -1      # Run.run_gold when it was told


## One stream: its clock and every coin's schedule, flight and state (0 waiting, 1 in the air, 2 in the box).
class Stream:
	var t := 0.0
	var dur := 3.0
	var k := 0.0
	var src: Node3D
	var src_at := Vector3.ZERO
	var to := Vector3.ZERO
	var launch := PackedFloat32Array()
	var flight := PackedFloat32Array()
	var arc := PackedFloat32Array()
	var spin := PackedFloat32Array()
	var tilt := PackedFloat32Array()
	var glint0 := PackedFloat32Array()
	var value := PackedInt32Array()
	var from := PackedVector3Array()
	var to_j := PackedVector3Array()
	var state := PackedByteArray()
	var landed := 0
	var left := 0
	var on_arrive: Callable
	var on_done: Callable
	var done := false
	var ping_t := -1.0
	var spark_t := 0.0


## How many coins carry `gold` (tests: 2 for 2 gold, never more than COINS_MAX).
static func count_for(gold: int) -> int:
	if gold <= 0:
		return 0
	if gold <= COINS_LITERAL:
		return gold
	return mini(gold, mini(COINS_MAX, int(round(COINS_LITERAL + COINS_LOG * log(float(gold) / COINS_LITERAL)))))


## How intense a deposit of `gold` is: 0 for a coin or two, 1 from a thousand gold (log scale).
static func intensity_for(gold: int) -> float:
	return clampf(log(maxf(float(gold), 1.0)) / log(1000.0), 0.0, 1.0)


## How long the stream of `gold` lasts, from the deposit to the last coin in the box (s; 0 for no gold).
static func duration_for(gold: int) -> float:
	if gold <= 0:
		return 0.0
	return MIN_SECONDS + MORE_SECONDS * intensity_for(gold)


func _ready() -> void:
	_ensure()


## Its meshes, materials and ping players, made once (on _ready, or on the first warm or start before it).
func _ensure() -> void:
	if _coin_mm != null:
		return
	_rng.randomize()
	_coin_mm = _pool(_coin_mesh(), _coin_material(), true)
	_shadow_mm = _pool(_shadow_mesh(), _shadow_material(), false)
	var row: Dictionary = Registry.soundmap.entry(PING_ID) if Registry.soundmap else {}
	var stream: AudioStream = row.get("stream") if not row.is_empty() else null
	for k in range(PING_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = stream
		p.volume_db = float(row.get("volume_db", -10.0)) + 1.0
		p.set_meta("db", p.volume_db)
		add_child(p)
		_players.append(p)


func _coin_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = COIN_R
	m.bottom_radius = COIN_R
	m.height = COIN_H
	m.radial_segments = 16
	m.rings = 1
	return m


func _coin_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/coin_flight.gdshader")
	mat.set_shader_parameter("radius", COIN_R)
	return mat


## The shadow: a flat square on the sand with a soft round dark spot in it.
func _shadow_mesh() -> Mesh:
	var m := PlaneMesh.new()
	m.size = Vector2(1.0, 1.0)
	return m


func _shadow_material() -> StandardMaterial3D:
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 1.0))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	g.add_point(0.55, Color(0.0, 0.0, 0.0, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# on the sand under every painting, like the pickups' (PickupManager.PAINTING_STENCIL)
	mat.render_priority = PickupManager.PICKUP_PRIORITY - 1
	mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
	mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
	mat.stencil_reference = PickupManager.PAINTING_STENCIL
	return mat


func _pool(mesh: Mesh, mat: Material, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = MAX_DRAWN
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 140, 400))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 140, 400))
	# the instances are world positions, wherever this node hangs
	mmi.top_level = true
	add_child(mmi)
	return mm


## One coin and its shadow far under the map for WARM_SECONDS (StructureManager.setup), so both materials compile under
## the run's start.
func warm() -> void:
	_ensure()
	_warm = WARM_SECONDS
	var at := Transform3D(Basis(), Vector3(0.0, -60.0, 0.0))
	_coin_mm.set_instance_transform(0, at)
	_coin_mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
	_coin_mm.visible_instance_count = 1
	_shadow_mm.set_instance_transform(0, at)
	_shadow_mm.set_instance_color(0, Color(0, 0, 0, 0.5))
	_shadow_mm.visible_instance_count = 1


## A deposit: `gold` flies from `src` (the hero; where he stands as each coin leaves) to `to` (the box's lid, world).
## `on_arrive(landed, count)` is called as each coin lands, `on_done()` once the last is in. Returns the stream's
## seconds (0: no gold, no stream).
func start(src: Node3D, to: Vector3, gold: int, on_arrive: Callable = Callable(), on_done: Callable = Callable()) -> float:
	var n := count_for(gold)
	if n <= 0:
		return 0.0
	_ensure()
	var st := Stream.new()
	st.k = intensity_for(gold)
	st.dur = duration_for(gold)
	st.src = src
	st.src_at = src.global_position if src != null and is_instance_valid(src) and src.is_inside_tree() else to
	st.to = to
	st.left = gold
	st.on_arrive = on_arrive
	st.on_done = on_done
	# (each by name: a packed array is a value, so resizing one held in a list would resize a copy)
	st.launch.resize(n)
	st.flight.resize(n)
	st.arc.resize(n)
	st.spin.resize(n)
	st.tilt.resize(n)
	st.glint0.resize(n)
	st.value.resize(n)
	st.from.resize(n)
	st.to_j.resize(n)
	st.state.resize(n)
	# each coin's share of the gold: the first gold % n carry one more
	var base: int = floori(float(gold) / float(n))
	var extra: int = gold - base * n
	var flight: float = lerpf(FLIGHT_SLOW, FLIGHT_FAST, st.k)
	var side := _screen_right()
	for j in range(n):
		var f: float = flight * _rng.randf_range(0.9, 1.1)
		st.flight[j] = f
		# evenly through the stream, the last one landing as it ends
		st.launch[j] = LAUNCH_AT if n == 1 else LAUNCH_AT + (st.dur - f - LAUNCH_AT) * float(j) / float(n - 1)
		st.arc[j] = lerpf(ARC_HIGH, ARC_LOW, st.k) * _rng.randf_range(0.85, 1.15)
		st.spin[j] = lerpf(SPIN_SLOW, SPIN_FAST, st.k) * _rng.randf_range(0.8, 1.2) * (1.0 if _rng.randf() < 0.5 else -1.0)
		st.tilt[j] = _rng.randf_range(-0.6, 0.6)
		st.glint0[j] = _rng.randf()
		st.value[j] = base + (1 if j < extra else 0)
		st.to_j[j] = to + side * _rng.randf_range(-0.12, 0.12)
		st.state[j] = 0
	if n == 1:
		# a single coin: one high, slow toss over the whole stream, in the box as it ends (the box lifts the usual beat
		# later, not after a wait with nothing in the air)
		st.launch[0] = LAUNCH_AT
		st.flight[0] = st.dur - LAUNCH_AT
		st.arc[0] = ARC_SINGLE
	_streams.append(st)
	_show_purse()
	return st.dur


## Whether any coin is still to land (tests, StructureManager).
func busy() -> bool:
	return not _streams.is_empty()


## How many coins are in the air now (tests).
func in_air() -> int:
	var n := 0
	for st: Stream in _streams:
		for j in range(st.state.size()):
			if st.state[j] == 1:
				n += 1
	return n


## The gold still with the hero, every stream's coins not yet gone (the HUD's purse is Run.run_gold plus this).
func purse_left() -> int:
	var n := 0
	for st: Stream in _streams:
		n += st.left
	return n


func _screen_right() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_transform.basis.x.normalized() if cam else Vector3.RIGHT


## How much bigger a coin is drawn for the camera's pull-out: 1 + COIN_ZOOM_KEEP x (zoom - 1), 1 without the run's camera
## (tests: 1.5 at zoom 2).
func grow() -> float:
	var rig = game.get("camera") if game != null and is_instance_valid(game) else null
	if rig == null or not is_instance_valid(rig) or not rig.has_method("zoom"):
		return 1.0
	return 1.0 + COIN_ZOOM_KEEP * maxf(float(rig.zoom()) - 1.0, 0.0)


## The HUD's purse: what he carries now plus what has yet to leave him (told only when it changes; a coin picked up
## during the stream is told by Run itself and put right here the next frame).
func _show_purse() -> void:
	var want := Run.run_gold + purse_left()
	if want == _shown and Run.run_gold == _shown_run:
		return
	_shown = want
	_shown_run = Run.run_gold
	Run.gold_changed.emit(want)


func _process(delta: float) -> void:
	if _warm > 0.0:
		_warm -= delta
		if _streams.is_empty():
			if _warm <= 0.0:
				_coin_mm.visible_instance_count = 0
				_shadow_mm.visible_instance_count = 0
			return
	if _streams.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var back: Vector3 = cam.global_transform.basis.z.normalized() if cam else Vector3.BACK
	var right: Vector3 = cam.global_transform.basis.x.normalized() if cam else Vector3.RIGHT
	var up: Vector3 = cam.global_transform.basis.y.normalized() if cam else Vector3.UP
	# a coin's face turned to the camera (its mesh lies along its own Y)
	var face := Basis(right, back, -up)
	var big := grow()
	var drawn := 0
	var finished: Array = []
	for st: Stream in _streams:
		st.t += delta
		if st.src != null and is_instance_valid(st.src) and st.src.is_inside_tree():
			st.src_at = st.src.global_position
		var n := st.state.size()
		for j in range(n):
			var s: int = st.state[j]
			if s == 2:
				continue
			if s == 0:
				if st.t < st.launch[j]:
					continue
				# out of the hero's chest, a little to either side
				st.from[j] = st.src_at + Vector3(0.0, FROM_UP, 0.0) + right * _rng.randf_range(-0.22, 0.22)
				st.state[j] = 1
				st.left -= st.value[j]
			var age: float = st.t - st.launch[j]
			var u: float = age / maxf(st.flight[j], 0.01)
			if u >= 1.0:
				st.state[j] = 2
				st.landed += 1
				_arrive(st, j)
				continue
			if drawn >= MAX_DRAWN:
				continue
			drawn = _draw_coin(st, j, u, age, face, right, up, drawn, big)
		# done once every coin is in and the stream has run its length (a coin that lands early never lifts the box sooner)
		if st.landed >= n and st.t >= st.dur:
			finished.append(st)
		_sparkle(st, delta)
	_coin_mm.visible_instance_count = drawn
	_shadow_mm.visible_instance_count = drawn
	_show_purse()
	for st: Stream in finished:
		_streams.erase(st)
		st.done = true
		if st.on_done.is_valid():
			st.on_done.call()
	if _streams.is_empty():
		_show_purse()


## Coin `j` of a stream at `u` of its flight: on its arc, flipping, popping in and sinking into the box; its shadow on the
## sand under it; both `big` times their size (grow()). Returns the next free slot.
func _draw_coin(st: Stream, j: int, u: float, age: float, face: Basis, right: Vector3, up: Vector3, slot: int, big: float = 1.0) -> int:
	var p: Vector3 = st.from[j].lerp(st.to_j[j], u) + Vector3(0.0, st.arc[j] * 4.0 * u * (1.0 - u), 0.0)
	var sink: float = minf(SINK, SINK_SECONDS / maxf(st.flight[j], 0.01))
	var sc := 1.0
	if u < POP:
		# pops out to full size with a little overshoot
		var q: float = u / POP
		sc = 1.0 - pow(1.0 - q, 3.0) + 0.18 * sin(q * PI)
	elif u > 1.0 - sink:
		sc = lerpf(1.0, 0.3, (u - (1.0 - sink)) / sink)
	var axis: Vector3 = (right * cos(st.tilt[j]) + up * sin(st.tilt[j])).normalized()
	var b := (Basis(axis, st.spin[j] * age) * face).scaled(Vector3.ONE * sc * big)
	_coin_mm.set_instance_transform(slot, Transform3D(b, p))
	var glint: float = fposmod(st.glint0[j] + age * lerpf(GLINT_RATE.x, GLINT_RATE.y, st.k), 1.0)
	var flash: float = clampf((u - (1.0 - sink)) / sink, 0.0, 1.0)
	_coin_mm.set_instance_custom_data(slot, Color(glint, lerpf(GLINT.x, GLINT.y, st.k), flash, 0.0))
	# the shadow: where the coin is over the sand, smaller and paler the higher it is
	var ground: float = map.height_at(p.x, p.z) if map else st.src_at.y
	var h: float = maxf(p.y - ground, 0.0)
	var ss: float = SHADOW_R * 2.0 * sc * big / (1.0 + 0.3 * h)
	_shadow_mm.set_instance_transform(slot, Transform3D(Basis().scaled(Vector3(ss, 1.0, ss)), Vector3(p.x, ground + 0.05, p.z)))
	_shadow_mm.set_instance_color(slot, Color(0.0, 0.0, 0.0, SHADOW_ALPHA / (1.0 + 0.45 * h)))
	return slot + 1


## A coin dropped into the box: the ping (higher the further into the stream) and the box's bounce.
func _arrive(st: Stream, j: int) -> void:
	var n := st.state.size()
	var last := st.landed >= n
	if last or st.ping_t < 0.0 or st.t - st.ping_t >= PING_GAP:
		st.ping_t = st.t
		_ping(lerpf(PING_LOW, PING_HIGH, float(st.landed - 1) / maxf(float(n - 1), 1.0)) + (0.1 if last and n > 1 else 0.0),
			0.0 if last else -PING_SOFTER * st.k)
	if game and game.get("fx") and game.fx:
		var at: Vector3 = st.to_j[j]
		for k in range(2 if last else 1):
			game.fx.mote(at, Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(1.6, 3.0), _rng.randf_range(-0.6, 0.6)), 0.4, 0.16, Color(1.0, 0.92, 0.55, 0.95))
	if st.on_arrive.is_valid():
		st.on_arrive.call(st.landed, n)


func _ping(pitch: float, db: float = 0.0) -> void:
	if _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_player_i]
	_player_i = (_player_i + 1) % _players.size()
	if p.stream == null:
		return
	p.pitch_scale = pitch
	p.volume_db = float(p.get_meta("db", -9.0)) + db
	p.play()


## Now and then a sparkle off a coin in the air (more often for a big deposit).
func _sparkle(st: Stream, delta: float) -> void:
	if game == null or not game.get("fx") or game.fx == null:
		return
	st.spark_t -= delta
	if st.spark_t > 0.0:
		return
	st.spark_t = SPARKLE_GAP / (1.0 + st.k)
	var flying: Array = []
	for j in range(st.state.size()):
		if st.state[j] == 1:
			flying.append(j)
	if flying.is_empty():
		return
	var j: int = flying[_rng.randi() % flying.size()]
	var u: float = (st.t - st.launch[j]) / maxf(st.flight[j], 0.01)
	var p: Vector3 = st.from[j].lerp(st.to_j[j], u) + Vector3(0.0, st.arc[j] * 4.0 * u * (1.0 - u), 0.0)
	game.fx.mote(p, Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0.4, 1.0), _rng.randf_range(-0.5, 0.5)), 0.35, 0.14, Color(1.0, 0.98, 0.8, 0.95))

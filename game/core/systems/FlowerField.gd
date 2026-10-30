## The Pollen flowers (pass 48, the Killer Bees' Pollen mutation; Garry: flowers grow out of the sand every 8-12 s,
## 10-18 m from the hero, at most 3 at once, about a cake slice's size, three kinds in mixed sizes; each lives 15 s,
## blinks 4 s and goes; picking one up gives the weapon x4 bees and x1.5 speed for 5 s, red bees with red trails).
## One field while any held weapon carries `params.pollen` {every [lo, hi], near, far, max, life, blink, seconds,
## amount_mult, speed_mult} (MissilePod makes it, FlowerField.ensure; it frees itself once none is held). Each flower is
## one of the painted pickups content/pickups/pollen_poppy|pollen_marigold|pollen_lupine drawn as a BillboardSprite
## that rises out of the ground with a little overshoot and sways; walking within PICK_R picks it: a pop of petals in
## its colour, "pk_flower", and the buff (Run.add_timed_effects aimed at "weapon:<id>", id buff_id, `seconds` long on
## the buffs' clock). The Hive Queen's bee kills sprout one where the creature fell (sprout), past the field's own cap
## by KILL_EXTRA.
## Pass 49 (Garry: "don't show the HUD guide to where the Flowers are ... since it's a kind of a power-up it should show
## up in the HUD as well"): nothing points at the flowers any more; while the buff runs the HUD shows it as a timed
## power-up plate with Pollen's icon and its seconds left, one plate however many weapons carry it (is_buff).
## Pass 115 (lane POLISH; Garry: "Beehive's Flowers are hard to detect, make bigger and slightly animated"): the Pollen
## settings may carry `flower_size` (x every flower's height; FLOWER_SIZE 1.6 when absent), `sway` (degrees each way its
## sway leans; SWAY_DEG), `pulse` (the share it breathes bigger and smaller by; PULSE) and `halo` (how opaque a soft ring
## in its colour, paler, lies on the sand under it, breathing with it; 0 = none; HALO). The halo is see-through, so it is
## drawn after the stage's filter in its own colour (StageStencil: see-through materials are never tinted), and reads on
## Nightfall's blue and the Blood Moon's red. Picking is as before (PICK_R round its foot). Cheap: one ring and one
## material a flower, a few numbers a frame for the at most `max` + KILL_EXTRA flowers.
class_name FlowerField
extends Node3D

## The keys' defaults (the reads below spell them out, so the Level Editor's selftest finds them).
const FLOWER_SIZE := 1.6
const SWAY_DEG := 9.0
const PULSE := 0.07
const HALO := 0.55
## Radians a second: the sway (pass 48's 1.7) and the breathing.
const SWAY_W := 1.7
const PULSE_W := 3.1
## The halo's radius (m) at a flower's size 1 before flower_size, its band's share of that, and how much of the way to
## white its colour is.
const HALO_R := 0.42
const HALO_BAND := 0.22
const HALO_PALE := 0.45

const GROUP := "flower_field"
const KINDS := ["pollen_poppy", "pollen_marigold", "pollen_lupine"]
## A weapon's Pollen buff is this and its id (buff_id); the HUD's plate for them shows the mutation MUTATION's icon.
const BUFF_PREFIX := "pollen:"
const MUTATION := "pollen"
## Metres: how close the hero walks to pick one.
const PICK_R := 1.2
## Metres: a flower at size 1 (a cake slice on the sand is about this tall).
const HEIGHT := 0.72
const SIZE_MIN := 0.8
const SIZE_MAX := 1.25
## Seconds a flower takes to rise out of the sand, and to shrink away at the end.
const GROW := 0.5
const SHRINK := 0.3
## How far apart two flowers stand at least, and how far from a rock's edge.
const GAP := 2.5
const ROCK_CLEAR := 1.0
## A kill's flower may stand past the field's own cap by this many.
const KILL_EXTRA := 3
## The first flower comes this long after the field is made (then every `every`).
const FIRST := 4.0

var game: Node
## The live flowers: {node: Node3D, sprite: BillboardSprite, def: PickupDef, t, life, blink, size, phase, gone, out}
var flowers: Array = []
## Diagnostics: flowers grown and picked.
var grown := 0
var picked := 0
var _next := FIRST
var _check := 0.0
var _cfg: Dictionary = {}


## The field in `p_game`, made when there is none.
static func ensure(p_game: Node) -> FlowerField:
	var f := of(p_game)
	if f == null and p_game != null:
		f = FlowerField.new()
		f.game = p_game
		p_game.add_child(f)
	return f


## The field in `p_game`, or null.
static func of(p_game: Node) -> FlowerField:
	if p_game == null or not p_game.is_inside_tree():
		return null
	for n in p_game.get_tree().get_nodes_in_group(GROUP):
		if n is FlowerField and not (n as Node).is_queued_for_deletion():
			return n
	return null


## A flower where a creature fell (the Hive Queen's bee kills), when there is a field.
static func sprout(p_game: Node, at: Vector3) -> void:
	var f := of(p_game)
	if f:
		f.grow_at(at, true)


## The id of the buff a picked flower gives weapon `wid` (MissilePod asks Run.boost_left with it).
static func buff_id(wid: String) -> String:
	return BUFF_PREFIX + wid


## Whether a timed buff (Run.timed's id) is a weapon's Pollen buff (pass 49: the HUD shows them all as one plate).
static func is_buff(id: String) -> bool:
	return id.begins_with(BUFF_PREFIX)


## The Pollen settings of the first held weapon that carries them, {} when none does.
static func held_config() -> Dictionary:
	for w in Run.weapons:
		var p = (w as WeaponInstance).params.get("pollen")
		if p is Dictionary:
			return p
	return {}


func _ready() -> void:
	add_to_group(GROUP)
	_cfg = held_config()


func _exit_tree() -> void:
	for f in flowers:
		var n = f["node"]
		if is_instance_valid(n):
			(n as Node).queue_free()
	flowers.clear()


## Where the live flowers stand (tests and tools; pass 49: nothing on the HUD points at them), picked or withering
## ones left out.
func positions() -> Array:
	var out: Array = []
	for f in flowers:
		if not bool(f["gone"]) and is_instance_valid(f["node"]):
			out.append((f["node"] as Node3D).global_position)
	return out


func live_count() -> int:
	var n := 0
	for f in flowers:
		if not bool(f["gone"]):
			n += 1
	return n


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	if game == null or game.paused:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_cfg = held_config()
		if _cfg.is_empty():
			# nothing carries Pollen any more: the field goes, its flowers with it
			queue_free()
			return
	_next -= delta
	if _next <= 0.0:
		var ev = _cfg.get("every", [8, 12])
		var lo: float = float(ev[0]) if ev is Array and (ev as Array).size() > 0 else 8.0
		var hi: float = float(ev[1]) if ev is Array and (ev as Array).size() > 1 else lo
		_next = Dice.r.randf_range(lo, maxf(hi, lo))
		if live_count() < int(_cfg.get("max", 3)):
			var at := _spot()
			if at != Vector3.INF:
				grow_at(at, false)
	_tick_flowers(delta)


## A spot `near` to `far` metres from the hero (10-18), mostly ahead of where he is heading, inside the arena, clear of
## rocks, the lake and the other flowers; INF when none of the tries is clear.
func _spot() -> Vector3:
	var hero: Node3D = game.player
	if hero == null:
		return Vector3.INF
	var near := float(_cfg.get("near", 10.0))
	var far := maxf(float(_cfg.get("far", 18.0)), near)
	var head := Vector3.ZERO
	var v = hero.get("velocity")
	if v is Vector3:
		head = Vector3(v.x, 0.0, v.z)
	if head.length_squared() < 0.25 and hero.has_method("forward"):
		head = hero.forward()
	var ha: float = atan2(head.z, head.x) if head.length_squared() > 0.0001 else Dice.r.randf() * TAU
	for k in range(28):
		# the first tries ahead (within about 70 degrees of the heading), the rest anywhere round him
		var a: float = ha + Dice.r.randf_range(-1.2, 1.2) if k < 16 else Dice.r.randf() * TAU
		var p: Vector3 = hero.global_position + Vector3(cos(a), 0.0, sin(a)) * Dice.r.randf_range(near, far)
		if _clear(p):
			p.y = game.map.height_at(p.x, p.z) if game.map else hero.global_position.y
			return p
	return Vector3.INF


## Inside the arena, off the rocks and the water, and not crowding another flower.
func _clear(p: Vector3) -> bool:
	var map = game.map
	if map:
		var inside: Vector3 = map.clamp_to_arena(p)
		if Vector2(inside.x - p.x, inside.z - p.z).length() > 0.01:
			return false
		for o: Vector3 in map.obstacles:
			if Vector2(p.x - o.x, p.z - o.y).length() < o.z + ROCK_CLEAR:
				return false
		if map.has_method("in_water") and map.in_water(p):
			return false
	for f in flowers:
		if not bool(f["gone"]) and is_instance_valid(f["node"]):
			var q: Vector3 = (f["node"] as Node3D).global_position
			if Vector2(p.x - q.x, p.z - q.z).length() < GAP:
				return false
	return true


## A flower rises at `at` (one of KINDS at random, a random size); `from_kill` lets it past the field's own cap.
func grow_at(at: Vector3, from_kill: bool = false) -> void:
	var cap := int(_cfg.get("max", 3)) + (KILL_EXTRA if from_kill else 0)
	if live_count() >= cap:
		return
	if game and game.map:
		at.y = game.map.height_at(at.x, at.z)
	var id: String = KINDS[Dice.r.randi() % KINDS.size()]
	var def: PickupDef = Registry.pickup(id)
	var node := Node3D.new()
	node.name = "Flower"
	add_child(node)
	node.global_position = at
	var sprite := BillboardSprite.new()
	node.add_child(sprite)
	var tex: Texture2D = def.icon if def and def.icon else PlaceholderArt.icon(def, 128)
	# pass 115 (lane POLISH): x flower_size (1.6)
	var size := Dice.r.randf_range(SIZE_MIN, SIZE_MAX) * flower_size(_cfg)
	sprite.setup(tex, {"idle": 1}, ["idle"], HEIGHT * size)
	sprite.set_squash(1.0, 0.0)
	var blink := float(_cfg.get("blink", 4.0))
	var life := float(_cfg.get("life", 15.0))
	if def and def.lifetime > 0.0 and not _cfg.has("life"):
		life = maxf(def.lifetime - blink, 1.0)
	var col: Color = def.color if def else Color(1.0, 0.45, 0.7)
	var halo := _halo(node, col, size)
	flowers.append({"node": node, "sprite": sprite, "def": def, "t": 0.0, "life": life, "blink": blink, "size": size,
		"phase": Dice.r.randf() * TAU, "gone": false, "out": 0.0, "halo": halo})
	grown += 1


## A weapon's Pollen settings' flower size (pass 115): x every flower's height.
static func flower_size(cfg: Dictionary) -> float:
	return clampf(float(cfg.get("flower_size", 1.6)), 0.25, 4.0)


## Pass 115 (lane POLISH): the soft ring under a flower of `size` (its height share) in `col`, paler, laid on the slope
## under `node`; null when the settings' halo is 0.
func _halo(node: Node3D, col: Color, size: float) -> MeshInstance3D:
	var a := clampf(float(_cfg.get("halo", 0.55)), 0.0, 1.0)
	if a <= 0.0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Halo"
	var tm := TorusMesh.new()
	var r := HALO_R * size
	tm.outer_radius = r
	tm.inner_radius = r * (1.0 - HALO_BAND)
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pale := col.lerp(Color(1, 1, 1), HALO_PALE)
	m.albedo_color = Color(pale.r, pale.g, pale.b, a)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("alpha", a)
	node.add_child(mi)
	var map = game.get("map") if game else null
	if map != null and map.has_method("normal_at"):
		var n: Vector3 = map.normal_at(node.global_position.x, node.global_position.z, 0.8)
		mi.basis = MapBase.ground_basis(n)
		mi.position = n * 0.05
	else:
		mi.position.y = 0.05
	mi.scale = Vector3(0.01, 0.35, 0.01)
	return mi


func _tick_flowers(delta: float) -> void:
	var hero: Node3D = game.player
	var keep: Array = []
	for f in flowers:
		var node = f["node"]
		if not is_instance_valid(node):
			continue
		var sprite: BillboardSprite = f["sprite"]
		var halo = f.get("halo")
		f["t"] = float(f["t"]) + delta
		var t: float = f["t"]
		if bool(f["gone"]):
			# shrinking back into the sand
			f["out"] = float(f["out"]) + delta
			var k: float = clampf(1.0 - float(f["out"]) / SHRINK, 0.0, 1.0)
			sprite.set_squash(k, k)
			if halo is MeshInstance3D and is_instance_valid(halo):
				(halo as MeshInstance3D).scale = Vector3(maxf(k, 0.01), 0.35, maxf(k, 0.01))
			if k <= 0.0:
				(node as Node).queue_free()
				continue
			keep.append(f)
			continue
		# rising out of the sand with a little overshoot, then a gentle sway and (pass 115) a breathing pulse
		var g: float = clampf(t / GROW, 0.0, 1.0)
		var y: float = 1.0 if g >= 1.0 else (1.0 + 0.15 * sin(g * PI)) * (1.0 - pow(1.0 - g, 3.0))
		var ph: float = float(f["phase"])
		var br: float = sin(t * PULSE_W + ph * 1.3)
		var p: float = 1.0 + clampf(float(_cfg.get("pulse", 0.07)), 0.0, 0.5) * br * g
		sprite.set_squash(p, y * p)
		sprite.set_roll(sin(t * SWAY_W + ph) * deg_to_rad(clampf(float(_cfg.get("sway", 9.0)), 0.0, 45.0)))
		var end: float = float(f["life"]) + float(f["blink"])
		# its last seconds blink, so it never just vanishes
		sprite.visible = t < float(f["life"]) or int((end - t) * 5.0) % 2 == 0
		if halo is MeshInstance3D and is_instance_valid(halo):
			var hm: MeshInstance3D = halo
			var hs: float = maxf(g * (1.0 + 0.08 * br), 0.01)
			hm.scale = Vector3(hs, 0.35, hs)
			hm.visible = sprite.visible
			var mat := hm.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = float(hm.get_meta("alpha", HALO)) * (0.8 + 0.2 * br)
		if t >= end:
			sprite.visible = true
			f["gone"] = true
			keep.append(f)
			continue
		if hero and hero.get("dead") != true and g >= 0.6:
			var d: Vector3 = hero.global_position - (node as Node3D).global_position
			if Vector2(d.x, d.z).length() <= PICK_R:
				_pick(f)
				continue
		keep.append(f)
	flowers = keep


## The hero walked into flower `f`: petals in its colour, the sound, and every held Pollen weapon's buff.
func _pick(f: Dictionary) -> void:
	var node: Node3D = f["node"]
	var at := node.global_position
	var def: PickupDef = f["def"]
	var col: Color = def.color if def else Color(1.0, 0.45, 0.7)
	picked += 1
	node.queue_free()
	var fx = game.get("fx")
	if fx:
		fx.burst(at + Vector3(0, 0.45, 0), col, 0.9)
		for k in range(10):
			var a := TAU * float(k) / 10.0 + randf() * 0.5
			fx.mote(at + Vector3(0, 0.5, 0), Vector3(cos(a) * randf_range(1.5, 3.0), randf_range(2.0, 3.8), sin(a) * randf_range(1.5, 3.0)), randf_range(0.5, 0.8), 0.22, col)
	Audio.play("pk_flower", at)
	give_buff(game)


## Every held weapon carrying Pollen gets its buff: `amount_mult` x its bees and `speed_mult` x their speed for
## `seconds` (a second flower starts the clock again).
static func give_buff(p_game: Node) -> void:
	var mult := 0.0
	for w in Run.weapons:
		var wi: WeaponInstance = w
		var p = wi.params.get("pollen")
		if not p is Dictionary:
			continue
		var pd: Dictionary = p
		var target := "weapon:" + wi.def.id
		var effects := [Effect.make("amount", "mul", float(pd.get("amount_mult", 4.0)) - 1.0, target),
			Effect.make("speed", "mul", float(pd.get("speed_mult", 1.5)) - 1.0, target)]
		Run.add_timed_effects(buff_id(wi.def.id), "Pollen", effects, float(pd.get("seconds", 5.0)), true)
		mult = float(pd.get("amount_mult", 4.0))
	if mult > 0.0 and p_game and p_game.has_method("toast"):
		p_game.toast("POLLEN! BEES x%d" % int(round(mult)), Color(1.0, 0.45, 0.7))

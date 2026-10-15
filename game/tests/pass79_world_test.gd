extends GdUnitTestSuite

## Pass 79, lane WORLD (Garry: "Map the sides are too orange"; "Throw the dynamite in front of the enemies."): the red-rock
## rim and the walls in duskier, less saturated colours that the map file names (timeline_data rock_color and
## wall_colors, the Level Editor's World card; RedCanyon.ROCK_COLOR / WALL_COLORS by default), the rock painting
## recoloured to the rock colour in the terrain shader and the cliffs' sandstone painting grey so a colour key is the
## colour drawn; and the Dynamite Stick's lead (Lobber params.lead): thrown where its crowd will be when it blows, the
## crowd's walking velocity (EnemyManager.crowd_velocity) times the flight and the fuse, capped, kept off the hero, in
## range, unled for a Sticky throw at a priority target. The sand and river colours stay as pass 61 left them
## (pass54_world_test, pass61_map_test pin them); the map tests read the map file, never Garry's numbers.

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles = null
var enemies = null
var telegraphs = null
var fx = null
var map = null
var camera = null
var paused := false
func fx_hit(_a, _b) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
func forward() -> Vector3:
	return Vector3(0, 0, -1)
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 1, 0) + d * 0.4
"""

## Pass 78's colours of the sides, the ones Garry called too orange.
const OLD_ROCK := Color(0.62, 0.34, 0.24)
const OLD_WALLS := {
	"near": Color(0.78, 0.6, 0.5), "far": Color(0.62, 0.42, 0.36), "farther": Color(0.46, 0.30, 0.30),
	"stone": Color(0.60, 0.40, 0.30), "light": Color(0.68, 0.47, 0.35), "cap": Color(0.40, 0.26, 0.21),
	"riser": Color(0.34, 0.22, 0.18), "boulders": Color(0.5, 0.33, 0.26),
}
## The old sandstone painting's bands: the orange the near cliffs wore under any tint.
const OLD_SANDSTONE := Color8(182, 109, 65)
const RED_CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()
	Run.forced_map_seed = 0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## Red Canyon built for a run on `mapdef` (the registry's own by default) with seed `ms`.
func _canyon(ms: int, mapdef: MapDef = null) -> Node3D:
	Run.forced_map_seed = ms
	Run.end()
	var md: MapDef = mapdef if mapdef else Registry.map("red_canyon")
	Run.start(Registry.character("astro"), md)
	var m: Node3D = auto_free((md.scene as PackedScene).instantiate())
	add_child(m)
	return m


## The registry's Red Canyon with its own timeline copy carrying `rock` and `walls` (so the registry is never touched).
func _map_with(rock, walls) -> MapDef:
	var md: MapDef = Registry.map("red_canyon").duplicate()
	md.timeline = md.timeline.duplicate()
	md.timeline.rock_color = rock
	md.timeline.wall_colors = walls
	return md


func _json_timeline() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	return (d as Dictionary).get("timeline_data", {})


func _terrain_mat(m: Node3D) -> ShaderMaterial:
	var t := m.get_node_or_null("Terrain") as MeshInstance3D
	return t.material_override as ShaderMaterial if t else null


## The ridge meshes (the three rings of cliffs, near first): every MeshInstance3D child whose material is a textured
## StandardMaterial3D duplicate of the stone.
func _ridges(m: Node3D) -> Array:
	var out: Array = []
	for c in m.get_children():
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi and mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).albedo_texture != null:
			out.append(mi)
	return out


## (pass 80: the boulders' and the stacked wall's helpers went with them; pass80_walls_test reads the fort wall)


# ---------------------------------------------------------------- the sides' colours

func test_the_defaults_are_duskier_and_less_saturated_than_before_and_still_red_rock() -> void:
	var rock: Color = RED_CANYON.ROCK_COLOR
	assert_float(rock.s).is_less(OLD_ROCK.s - 0.2)
	assert_float(rock.v).is_less(OLD_ROCK.v)
	# still red rock: a red hue (within 30 degrees of red either side), red its strongest channel
	assert_bool(rock.h < 30.0 / 360.0 or rock.h > 330.0 / 360.0).override_failure_message("rock hue %f" % (rock.h * 360.0)).is_true()
	assert_float(rock.r).is_greater(maxf(rock.g, rock.b))
	var walls: Dictionary = RED_CANYON.WALL_COLORS
	# pass 80 (lane WALLS, re-pinned on purpose): the boundary is a sandstone fort wall since, its keys (stone, light,
	# cap, riser, beams) a warm buff sandstone (pass80_walls_test pins them); the rule here holds for the three rings of
	# cliffs, which keep pass 79's colours
	for k: String in ["near", "far", "farther"]:
		var c: Color = walls[k]
		var old: Color = OLD_WALLS[k]
		assert_float(c.s).override_failure_message("%s saturation %.2f (was %.2f)" % [k, c.s, old.s]).is_less(old.s)
		assert_float(c.r).override_failure_message("%s is not red-led" % k).is_greater(maxf(c.g, c.b))
		# the two rings out on the horizon may go a little towards dusk violet (the warm light browns them on the screen)
		var lo := 300.0 if k in ["far", "farther"] else 330.0
		assert_bool(c.h < 30.0 / 360.0 or c.h > lo / 360.0).override_failure_message("%s hue %f" % [k, c.h * 360.0]).is_true()
	# the far cliffs darker
	assert_float(walls["far"].v).is_less(walls["near"].v)
	assert_float(walls["farther"].v).is_less(walls["far"].v)


func test_the_map_file_names_colours_the_game_reads() -> void:
	var tl := _json_timeline()
	var wt: WaveTimeline = Registry.map("red_canyon").timeline
	# what the file says is what the registry carries (the .tres made from it): read from the file, never pinned
	assert_str(wt.rock_color).is_equal(str(tl.get("rock_color", "")))
	var walls = tl.get("wall_colors", {})
	assert_bool(walls is Dictionary).is_true()
	for k in (walls as Dictionary).keys():
		assert_bool(RED_CANYON.WALL_COLORS.has(k)).override_failure_message("unknown wall colour " + str(k)).is_true()
		assert_bool(Color.html_is_valid(str(walls[k]))).override_failure_message("%s: %s" % [k, walls[k]]).is_true()
		assert_str(str(wt.wall_colors.get(k, ""))).is_equal(str(walls[k]))
	if tl.has("rock_color"):
		assert_bool(Color.html_is_valid(str(tl["rock_color"]))).is_true()


func test_color_of_reads_hex_lists_and_falls_back() -> void:
	var fb := Color(0.1, 0.2, 0.3)
	assert_bool(WaveTimeline.color_of("#785C5E", fb).is_equal_approx(Color8(0x78, 0x5C, 0x5E))).is_true()
	assert_bool(WaveTimeline.color_of("785C5E", fb).is_equal_approx(Color8(0x78, 0x5C, 0x5E))).is_true()
	assert_bool(WaveTimeline.color_of([0.5, 0.25, 0.75], fb).is_equal_approx(Color(0.5, 0.25, 0.75))).is_true()
	for bad in ["", "orange-ish", null, 3, {}]:
		assert_bool(WaveTimeline.color_of(bad, fb).is_equal_approx(fb)).override_failure_message(str(bad)).is_true()


func test_red_canyon_builds_in_the_files_colours() -> void:
	var walls := {"near": "#405060", "far": "#304050", "farther": "#203040", "stone": "#506070", "light": "#607080",
		"cap": "#101820", "riser": "#081018", "beams": "#708090"}
	var m := _canyon(7, _map_with("#112233", walls))
	assert_bool((m.get("rock_color") as Color).is_equal_approx(Color("#112233"))).is_true()
	var mat := _terrain_mat(m)
	assert_object(mat).is_not_null()
	assert_bool((mat.get_shader_parameter("rock_flat") as Color).is_equal_approx(Color("#112233"))).is_true()
	# the sand and the river stay the map's own
	assert_bool((mat.get_shader_parameter("sand_flat") as Color).is_equal_approx(m.get("sand_color"))).is_true()
	assert_bool((mat.get_shader_parameter("cracked_flat") as Color).is_equal_approx(m.get("river_color"))).is_true()
	var ridges := _ridges(m)
	assert_int(ridges.size()).is_equal(3)
	var tints: Array = ridges.map(func(r: MeshInstance3D) -> Color: return (r.material_override as StandardMaterial3D).albedo_color)
	for k: String in ["near", "far", "farther"]:
		var want := Color(str(walls[k]))
		assert_bool(tints.any(func(c: Color) -> bool: return c.is_equal_approx(want))).override_failure_message("no ridge in " + k).is_true()
	# (pass 80, re-pinned on purpose: the fort wall's colours are each key times its light and shade; pass80_walls_test
	# checks every key on it, the beams on the vigas)


func test_a_colour_left_out_or_unreadable_plays_the_default() -> void:
	var m := _canyon(7, _map_with("", {"near": "#405060", "far": "not a colour"}))
	assert_bool((m.get("rock_color") as Color).is_equal_approx(RED_CANYON.ROCK_COLOR)).is_true()
	var wc: Dictionary = m.get("wall_colors")
	assert_bool((wc["near"] as Color).is_equal_approx(Color("#405060"))).is_true()
	assert_bool((wc["far"] as Color).is_equal_approx(RED_CANYON.WALL_COLORS["far"])).is_true()
	assert_bool((wc["beams"] as Color).is_equal_approx(RED_CANYON.WALL_COLORS["beams"])).is_true()


func test_the_cliff_painting_is_grey_and_the_rock_shader_knows_its_paintings_mean() -> void:
	# pass 80 (lane WALLS, re-pinned on purpose): the cliffs wear art/env/cliff_rock.png, a hi-res rock painting brought
	# to a grey mean (a little of its hue left in the strata, so no longer grey pixel by pixel)
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes("res://art/env/cliff_rock.png"))).is_equal(OK)
	img.convert(Image.FORMAT_RGB8)
	img.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0, 0, 0)
	for y in range(64):
		for x in range(64):
			var c := img.get_pixel(x, y)
			assert_float(c.s).is_less(0.15)
			sum += c
	var mean := sum / 4096.0
	assert_float(maxf(maxf(mean.r, mean.g), mean.b) - minf(minf(mean.r, mean.g), mean.b)).is_less(0.03)
	# far from the old orange bands, light enough that a tint is about the colour drawn
	assert_float(mean.v).is_greater(0.65)
	assert_float(OLD_SANDSTONE.s).is_greater(0.5)
	# the terrain shader's rock_tex_lum is the rock painting's mean linear luminance (a regenerated painting needs it again)
	var rk := Image.new()
	assert_int(rk.load_png_from_buffer(FileAccess.get_file_as_bytes("res://art/env/redrock.png"))).is_equal(OK)
	rk.convert(Image.FORMAT_RGB8)
	rk.resize(128, 128, Image.INTERPOLATE_BILINEAR)
	var lum := 0.0
	for y in range(128):
		for x in range(128):
			var l := rk.get_pixel(x, y).srgb_to_linear()
			lum += l.r * 0.299 + l.g * 0.587 + l.b * 0.114
	lum /= 16384.0
	var src := FileAccess.get_file_as_string("res://core/shaders/terrain_painted.gdshader")
	var rx := RegEx.create_from_string("uniform float rock_tex_lum = ([0-9.]+);")
	var mt := rx.search(src)
	assert_object(mt).is_not_null()
	assert_float(float(mt.get_string(1))).is_equal_approx(lum, lum * 0.1)


# ---------------------------------------------------------------- the dynamite's lead

func _setup() -> Node:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	pm.register_kind(BoxMesh.new(), null, 1.0)
	return g


## A crowd of `n` round `at` walking at `v` (all the way up out of the sand).
func _walkers(g: Node, at: Vector3, n: int, v: Vector3) -> Array:
	var em: EnemyManager = g.enemies
	var ids: Array = []
	for k in range(n):
		var a := TAU * float(k) / float(n)
		var i := em.spawn("goblin", at + Vector3(cos(a), 0, sin(a)) * 0.8, null, 1.0, 50.0)
		em.state[i] = EnemyManager.STATE_MOVE
		em.rise_t[i] = 1.0
		em.vel[i] = v
		ids.append(i)
	em._rebuild_grid()
	return ids


func _bomber(g: Node, id: String, params := {}, amount := 0) -> Lobber:
	var b := Lobber.new()
	var d: WeaponDef = Registry.weapon(id).duplicate()
	if not params.is_empty():
		d.params = d.params.duplicate(true)
		d.params.merge(params, true)
	if amount > 0:
		d.base = d.base.duplicate()
		d.base["amount"] = amount
	b.inst = WeaponInstance.new(d, 1)
	b.inst.rebuild(Run.player_sheet, [])
	b.game = g
	b.player = g.player
	b.projectile_kind = 0
	g.add_child(b)
	return b


## The shots in flight: [target, extra] each.
func _throws(g: Node) -> Array:
	var pm: ProjectileManager = g.projectiles
	var out: Array = []
	for i in range(ProjectileManager.MAX):
		if pm.alive[i] == 1 and pm.arc[i] == 1 and pm.extra[i] is Dictionary and (pm.extra[i] as Dictionary).has("target"):
			out.append([pm.extra[i]["target"], pm.extra[i]])
	return out


func test_only_the_dynamite_and_its_golden_pineapple_lead() -> void:
	for id in ["lob_grenade", "golden_pineapple"]:
		var lc := Lobber.lead_config(Registry.weapon(id).params)
		assert_float(float(lc["share"])).override_failure_message(id + " has no lead").is_greater(0.0)
		assert_str(str(lc["mode"])).is_equal("predict")
	for w: WeaponDef in Registry.weapons.values():
		if w.behavior != "Lobber" or w.id in ["lob_grenade", "golden_pineapple"]:
			continue
		assert_float(float(Lobber.lead_config(w.params)["share"])).override_failure_message(w.id + " leads").is_equal(0.0)


func test_lead_config_reads_a_number_a_switch_or_a_block() -> void:
	assert_float(float(Lobber.lead_config({})["share"])).is_equal(0.0)
	assert_float(float(Lobber.lead_config({"lead": 0.5})["share"])).is_equal_approx(0.5, 0.0001)
	assert_float(float(Lobber.lead_config({"lead": true})["share"])).is_equal(1.0)
	assert_float(float(Lobber.lead_config({"lead": false})["share"])).is_equal(0.0)
	var b := Lobber.lead_config({"lead": {"max": 4.0, "gap": 2.0}})
	assert_float(float(b["share"])).is_equal(1.0)
	assert_float(float(b["max"])).is_equal(4.0)
	assert_float(float(b["gap"])).is_equal(2.0)
	assert_float(float(b["radius"])).is_equal(Lobber.LEAD_RADIUS)
	assert_float(float(Lobber.lead_config({"lead": -2})["share"])).is_equal(0.0)


func test_the_spot_is_where_the_crowd_walks_by_the_blast() -> void:
	# a crowd walking straight at a hero who stands: both ways of foreseeing it agree
	var cfg := Lobber.lead_config({"lead": {"mode": "walk"}})
	assert_str(str(cfg["mode"])).is_equal("walk")
	assert_bool(Lobber.lead_spot(Vector3(0, 0, -9), Vector3(0, 1.2, 0), Vector3(0, 0, 1.2), 9.0, 1.0, Lobber.lead_config({"lead": 1.0}), Vector3.ZERO, 10.0, 60.0)
		.is_equal_approx(Lobber.lead_spot(Vector3(0, 0, -9), Vector3(0, 1.2, 0), Vector3(0, 0, 1.2), 9.0, 1.0, cfg, Vector3.ZERO, 10.0, 60.0))).is_true()
	var hero := Vector3.ZERO
	var from := Vector3(0, 1.2, 0)
	var target := Vector3(0, 0, -9)
	var v := Vector3(0, 0, 1.2)
	var aim := Lobber.lead_spot(target, from, v, 9.0, 1.0, cfg, hero, 10.0, 60.0)
	# twice round: the flight to the led spot, plus the fuse, times the walk
	var t1 := clampf(9.0 / 9.0, 0.35, 2.5) + 1.0
	var a1 := target + v * t1
	var t2 := clampf(Vector2(a1.x - from.x, a1.z - from.z).length() / 9.0, 0.35, 2.5) + 1.0
	assert_bool(aim.is_equal_approx(target + v * t2)).override_failure_message("aim %s" % aim).is_true()
	# half the share, half the walk; no walk, no lead
	var half := Lobber.lead_spot(target, from, v, 9.0, 1.0, Lobber.lead_config({"lead": 0.5}), hero, 10.0, 60.0)
	assert_float(half.distance_to(target)).is_less(aim.distance_to(target))
	assert_bool(Lobber.lead_spot(target, from, Vector3.ZERO, 9.0, 1.0, cfg, hero, 10.0, 60.0).is_equal_approx(target)).is_true()
	# a Sticky bomb (no fuse) leads only by its flight
	var sticky := Lobber.lead_spot(target, from, v, 9.0, 0.0, cfg, hero, 10.0, 60.0)
	assert_float(sticky.distance_to(target)).is_less(aim.distance_to(target) - 1.0)


func test_the_chase_closes_on_where_the_hero_will_be() -> void:
	# a number or a block without a mode is "predict", which foresees with the chase; "chase" by name the same
	assert_str(str(Lobber.lead_config({"lead": 1.0})["mode"])).is_equal("predict")
	assert_str(str(Lobber.lead_config({"lead": {"mode": "nonsense"}})["mode"])).is_equal("predict")
	var cfg := Lobber.lead_config({"lead": {"mode": "chase"}})
	assert_str(str(cfg["mode"])).is_equal("chase")
	assert_bool(Lobber.lead_spot(Vector3(0, 0, -8), Vector3(0, 1.2, 0), Vector3(1.3, 0, 0), 9.0, 1.0, Lobber.lead_config({"lead": 1.0}), Vector3.ZERO, 10.0, 60.0)
		.is_equal_approx(Lobber.lead_spot(Vector3(0, 0, -8), Vector3(0, 1.2, 0), Vector3(1.3, 0, 0), 9.0, 1.0, cfg, Vector3.ZERO, 10.0, 60.0))).is_true()
	var from := Vector3(0, 1.2, 0)
	var target := Vector3(0, 0, -8)
	# the crowd walks across him now (its mean velocity sideways), but it is walking at him: the chase heads for him at
	# its pace; a straight walk would go on sideways
	var side := Vector3(1.3, 0, 0)
	var chase := Lobber.lead_spot(target, from, side, 9.0, 1.0, cfg, Vector3.ZERO, 10.0, 60.0)
	assert_float(absf(chase.x)).is_less(0.01)
	assert_float(chase.z).is_greater(target.z + 1.3 * 1.5)
	var walk := Lobber.lead_spot(target, from, side, 9.0, 1.0, Lobber.lead_config({"lead": {"mode": "walk"}}), Vector3.ZERO, 10.0, 60.0)
	assert_float(walk.x).is_greater(1.3 * 1.5)
	assert_float(absf(walk.z - target.z)).is_less(0.01)
	# a crowd milling about (its mean velocity nought, each one walking) still closes on him: the pace is its own
	var mill := Lobber.lead_spot(target, from, Vector3.ZERO, 9.0, 1.0, cfg, Vector3.ZERO, 10.0, 60.0, Vector3.ZERO, 1.3)
	assert_float(mill.z).is_greater(target.z + 1.3 * 1.5)
	# the hero running east: the crowd turns after where he will be partway through the wait
	var run := Lobber.lead_spot(target, from, Vector3(0, 0, 1.3), 9.0, 1.0, cfg, Vector3.ZERO, 10.0, 60.0, Vector3(4, 0, 0))
	assert_float(run.x).is_greater(0.3)
	# hero_ahead 0: towards where he stands
	var now := Lobber.lead_spot(target, from, Vector3(0, 0, 1.3), 9.0, 1.0, Lobber.lead_config({"lead": {"hero_ahead": 0.0}}), Vector3.ZERO, 10.0, 60.0, Vector3(4, 0, 0))
	assert_float(absf(now.x)).is_less(0.01)


func test_the_lead_is_capped_kept_off_the_hero_in_range_and_in_the_arena() -> void:
	var hero := Vector3.ZERO
	var from := Vector3(0, 1.2, 0)
	var cfg := Lobber.lead_config({"lead": {"max": 3.0, "gap": 1.5}})
	var walk := Lobber.lead_config({"lead": {"max": 3.0, "gap": 1.5, "mode": "walk"}})
	# the straight walk: drawn back to `gap` where it would pass him, never past the weapon's range or the arena's edge
	var past := Lobber.lead_spot(Vector3(0.5, 0, -3), from, Vector3(0, 0, 4), 9.0, 1.0, walk, hero, 20.0, 60.0)
	assert_float(Vector2(past.x, past.z).length()).is_equal_approx(1.5, 0.01)
	assert_float(past.z).is_less(0.0)
	var off := Lobber.lead_spot(Vector3(0, 0, -9.5), from, Vector3(0, 0, -3), 9.0, 1.0, walk, hero, 10.0, 60.0)
	assert_float(Vector2(off.x, off.z).length()).is_less_equal(10.0 + 0.001)
	var out := Lobber.lead_spot(Vector3(0, 0, -63), from, Vector3(0, 0, -3), 9.0, 1.0, walk, Vector3(0, 0, -55), 10.0, 64.5)
	assert_float(Vector2(out.x, out.z).length()).is_less_equal(64.5 + 0.001)
	# a fast crowd sideways: the lead is at most `max`
	var side := Lobber.lead_spot(Vector3(0, 0, -8), from, Vector3(6, 0, 0), 9.0, 1.0, cfg, hero, 20.0, 60.0)
	assert_float(Vector2(side.x, side.z - (-8.0)).length()).is_less_equal(3.0 + 0.001)
	# a crowd walking at the hero: the spot stops `gap` short of him, on the crowd's side
	var at_hero := Lobber.lead_spot(Vector3(0, 0, -3), from, Vector3(0, 0, 4), 9.0, 1.0, cfg, hero, 20.0, 60.0)
	assert_float(Vector2(at_hero.x, at_hero.z).length()).is_equal_approx(1.5, 0.01)
	assert_float(at_hero.z).is_less(0.0)
	# a crowd at his feet already: no lead
	var near := Lobber.lead_spot(Vector3(0, 0, -1), from, Vector3(0, 0, 4), 9.0, 1.0, cfg, hero, 20.0, 60.0)
	assert_bool(near.is_equal_approx(Vector3(0, 0, -1))).is_true()
	# a crowd walking away: never past the weapon's range, never past the arena's edge
	var away := Lobber.lead_spot(Vector3(0, 0, -9.5), from, Vector3(0, 0, -3), 9.0, 1.0, cfg, hero, 10.0, 60.0)
	assert_float(Vector2(away.x, away.z).length()).is_less_equal(10.0 + 0.001)
	var edge := Lobber.lead_spot(Vector3(0, 0, -63), from, Vector3(0, 0, -3), 9.0, 1.0, cfg, Vector3(0, 0, -60), 10.0, 64.5)
	assert_float(Vector2(edge.x, edge.z).length()).is_less_equal(64.5 + 0.001)


func test_predicted_counts_close_each_creature_on_the_hero() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	# four walking at the hero from 8 m north at 1.5 m/s, two standing (winding up) at 8 m east
	_walkers(g, Vector3(0, 0, -8), 4, Vector3(0, 0, 1.5))
	_walkers(g, Vector3(8, 0, 0), 2, Vector3.ZERO)
	var spots: Array = [Vector3(0, 0, -8), Vector3(0, 0, -5), Vector3(8, 0, 0), Vector3(0, 0, -1)]
	var c := em.predicted_counts(spots, 1.2, 2.0, Vector3.ZERO, 1.5, Vector3.ZERO, 20.0)
	# in two seconds the walkers are 3 m on (round z = -5); the standing two stay; nobody passes the 1.5 m gap
	assert_int(c[0]).is_equal(0)
	assert_int(c[1]).is_equal(4)
	assert_int(c[2]).is_equal(2)
	assert_int(c[3]).is_equal(0)
	# a long wait: they stop 1.5 m short of him
	var late := em.predicted_counts([Vector3(0, 0, -1.5)], 1.0, 20.0, Vector3.ZERO, 1.5, Vector3.ZERO, 20.0)
	assert_int(late[0]).is_equal(4)


func test_predict_picks_the_best_spot_and_the_one_ahead_on_a_tie() -> void:
	assert_int(Lobber.predict_pick(PackedInt32Array([3, 5, 4, 2, 1]))).is_equal(1)
	assert_int(Lobber.predict_pick(PackedInt32Array([3, 5, 5, 2, 5]))).is_equal(4)
	assert_int(Lobber.predict_pick(PackedInt32Array([0, 0, 0]))).is_equal(2)
	assert_int(Lobber.predict_pick(PackedInt32Array([7]))).is_equal(0)


func test_a_crowd_that_stands_is_not_led_past() -> void:
	# eight standing round a spot (biting, winding up) and one in their middle walking off fast: the crowd's mean pace says
	# lead, the foreseen crowd stays put. The plain chase throws past the ring; predict keeps the whole ring in the blast.
	var crowd := Vector3(0, 0, -8)
	var caught := {}
	for mode in ["predict", "chase"]:
		var g := _setup()
		var em: EnemyManager = g.enemies
		var mid: Array = _walkers(g, crowd, 1, Vector3(0, 0, 5.0))
		em.pos[mid[0]] = crowd
		for k in range(8):
			var a := TAU * float(k) / 8.0
			var i := em.spawn("goblin", crowd + Vector3(cos(a), 0, sin(a)) * 2.2, null, 1.0, 50.0)
			em.state[i] = EnemyManager.STATE_MOVE
			em.rise_t[i] = 1.0
			em.vel[i] = Vector3.ZERO
		em._rebuild_grid()
		var b := _bomber(g, "lob_grenade", {"lead": {"mode": mode}})
		assert_bool(b._fire()).is_true()
		var target: Vector3 = _throws(g)[0][0]
		caught[mode] = em.blast_count(target, b.stat("area", 2.8))
		caught[mode + "_unled"] = em.blast_count(crowd, b.stat("area", 2.8))
	assert_int(int(caught["predict"])).is_greater_equal(int(caught["predict_unled"]))
	assert_int(int(caught["chase"])).is_less(int(caught["chase_unled"]))


func test_crowd_velocity_is_the_walk_of_the_risen_living() -> void:
	var g := _setup()
	var em: EnemyManager = g.enemies
	var ids := _walkers(g, Vector3(0, 0, -6), 4, Vector3(0, 0, 2))
	assert_bool(em.crowd_velocity(Vector3(0, 0, -6), 3.0).is_equal_approx(Vector3(0, 0, 2))).is_true()
	# one still rising out of the sand and the push a hit gave them do not count
	em.rise_t[ids[0]] = 0.5
	em.vel[ids[0]] = Vector3(0, 0, -20)
	em.kb[ids[1]] = Vector3(30, 0, 0)
	assert_bool(em.crowd_velocity(Vector3(0, 0, -6), 3.0).is_equal_approx(Vector3(0, 0, 2))).is_true()
	# High Noon's slow is the world's clock
	em.time_scale = 0.5
	assert_bool(em.crowd_velocity(Vector3(0, 0, -6), 3.0).is_equal_approx(Vector3(0, 0, 1))).is_true()
	assert_bool(em.walk_velocity(ids[2]).is_equal_approx(Vector3(0, 0, 1))).is_true()
	assert_bool(em.walk_velocity(ids[0]).is_equal_approx(Vector3.ZERO)).is_true()
	em.time_scale = 1.0
	assert_bool(em.crowd_velocity(Vector3(20, 0, 20), 3.0).is_equal_approx(Vector3.ZERO)).is_true()


func test_the_dynamite_lands_ahead_of_a_crowd_walking_at_the_hero() -> void:
	var g := _setup()
	var crowd := Vector3(0, 0, -8)
	_walkers(g, crowd, 6, Vector3(0, 0, 1.3))
	var b := _bomber(g, "lob_grenade", {"lead": 1.0})
	assert_bool(b._fire()).is_true()
	var th := _throws(g)
	assert_int(th.size()).is_equal(1)
	var target: Vector3 = th[0][0]
	var ex: Dictionary = th[0][1]
	# the crowd's spot at the throw (one of the six) rides along as lead_from
	assert_bool(ex.has("lead_from")).is_true()
	var was: Vector3 = ex["lead_from"]
	assert_float(Vector2(was.x - crowd.x, was.z - crowd.z).length()).is_less(1.0)
	# ahead of it, towards the hero, by its walk over the flight and the fuse (about two seconds)
	var hero: Vector3 = g.player.global_position
	var closer := Vector2(was.x - hero.x, was.z - hero.z).length() - Vector2(target.x - hero.x, target.z - hero.z).length()
	assert_float(closer).is_greater(1.3 * 1.5)
	assert_float(closer).is_less(1.3 * 2.5)
	assert_float(Vector2(target.x - was.x, target.z - was.z).length()).is_equal_approx(closer, 0.01)
	assert_int(b.leads).is_equal(1)
	# claimed: the led spot and the crowd's
	var spots: Array = g.projectiles.claimed_spots()
	assert_int(spots.size()).is_equal(2)
	assert_bool(spots.any(func(s: Vector3) -> bool: return Vector2(s.x - crowd.x, s.z - crowd.z).length() < 1.0)).is_true()


func test_without_the_lead_the_throw_goes_where_it_did() -> void:
	var g := _setup()
	var crowd := Vector3(0, 0, -8)
	var ids := _walkers(g, crowd, 6, Vector3(0, 0, 1.3))
	var b := _bomber(g, "lob_grenade", {"lead": 0.0})
	assert_bool(b._fire()).is_true()
	var th := _throws(g)
	var target: Vector3 = th[0][0]
	# at one of the crowd, as before pass 79
	var em: EnemyManager = g.enemies
	assert_bool(ids.any(func(i: int) -> bool: return em.pos[i].is_equal_approx(target))).is_true()
	assert_bool((th[0][1] as Dictionary).has("lead_from")).is_false()
	assert_int(b.leads).is_equal(0)
	# and the Molotov (no lead of its own) the same
	var g2 := _setup()
	var ids2 := _walkers(g2, crowd, 6, Vector3(0, 0, 1.3))
	var mo := _bomber(g2, "molotov")
	assert_bool(mo._fire()).is_true()
	var t2: Vector3 = _throws(g2)[0][0]
	var em2: EnemyManager = g2.enemies
	assert_bool(ids2.any(func(i: int) -> bool: return em2.pos[i].is_equal_approx(t2))).is_true()


func test_a_sticky_throw_at_the_strongest_stays_unled() -> void:
	var g := _setup()
	var crowd := Vector3(0, 0, -8)
	var ids := _walkers(g, crowd, 6, Vector3(0, 0, 1.3))
	var em: EnemyManager = g.enemies
	em.max_hp[ids[3]] = 5000.0
	em.hp[ids[3]] = 5000.0
	em.refresh_crowd_stats()
	# one bomb (a second one would land round the crowd, where the strongest may be out of its reach)
	var b := _bomber(g, "golden_pineapple", {}, 1)
	assert_bool((b.inst.params.get("sticky") as Dictionary).get("priority", false)).is_true()
	assert_float(float(Lobber.lead_config(b.inst.params)["share"])).is_greater(0.0)
	assert_bool(b._fire()).is_true()
	for th in _throws(g):
		var target: Vector3 = th[0]
		assert_bool(ids.any(func(i: int) -> bool: return em.pos[i].is_equal_approx(target))).override_failure_message("led to %s" % target).is_true()
	assert_int(b.leads).is_equal(0)

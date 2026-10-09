## Pooled projectiles in packed arrays, one MultiMesh per visual kind. Straight shots, gravity arcs that
## fly through enemies and explode on landing, and hostile shots that hit the player. Hit checks use the enemy spatial grid.
## A weapon's params shape its shots (pass 46): `no_spin` keeps a shot from tumbling (a spear points where it flies),
## `roll_radius` (pass 55) rolls it like a wheel the way it flies (the tumbleweeds),
## `plant` stands it in the sand at the end of its flight (_plant), `pin` stops the first creature it strikes (slow 1.0),
## `trail_zone` leaves patches of slowing dust behind it (_dust_trail), and a tracer's beads take the weapon's element.
class_name ProjectileManager
extends Node3D

const MAX := 400

var game: Node
var kinds: Array = []   # {mm, mmi, scale}

var pos := PackedVector3Array()
var vel := PackedVector3Array()
var life := PackedFloat32Array()
var dmg := PackedFloat32Array()
var pierce := PackedInt32Array()
var kind := PackedInt32Array()
var radius := PackedFloat32Array()
var kb := PackedFloat32Array()
var area := PackedFloat32Array()
var hostile := PackedByteArray()
var arc := PackedByteArray()
var homing := PackedByteArray()   # missiles: steered by _fly_missile, explode on contact (see launch_missile)
var ret := PackedByteArray()      # the boomerang: 0 plain, 1 on its way out, 2 coming back to the hero
var stuck := PackedInt32Array()   # the sticky grenade: the creature it rides, -1 for none
var stuck_t := PackedFloat32Array()
var psize := PackedFloat32Array()
var glow := PackedFloat32Array()   # per shot: 0..1 heat a `custom` kind's shader reads (the loose rocket's blink, pass 45)
## the rocketeers' rockets: projectile index -> creature index; a rocket lives while its goblin does (Game asks)
var rocket_of: Dictionary = {}
## diagnostics: missiles launched per weapon id (the smoke run prints it)
var missiles_by_weapon: Dictionary = {}   # a shot's own size against its kind's (params.size_mult): a slug is big, a swarm's bees small
var alive := PackedByteArray()
var spin := PackedFloat32Array()
var hover := PackedFloat32Array()   # straight shots: height above the ground they keep, sampled where they were fired
var weapon: Array = []
var memo: Array = []
var extra: Array = []
var free_list: Array = []
var count := 0
## Counters for the smoke run: lobbed shots fired, and how many of them exploded on landing (the rest timed out).
var lobs_fired := 0
var lobs_exploded := 0
## Hostile shots leave a faint trail of fading dots, so a spit can be followed back to whoever threw it.
const TRAIL_MAX := 800
## a shot's extra tracer beads (params.tracer_beads, pass 61's Drum Mag) drop only while no more shots than this fly
const TRACER_EXTRA_BUSY := 40
const TRAIL_LIFE := 1.4
const TRAIL_STEP := 0.055
var trail_pos := PackedVector3Array()
var trail_age := PackedFloat32Array()
var trail_col := PackedColorArray()   # per dot: spit is green, rocket smoke warm, bees gold
var trail_size := PackedFloat32Array()   # per dot: rocket smoke puffs are bigger than a spit trail's beads
## per dot: how long it lives (TRAIL_LIFE, or a tracer's own `tracer_life`, pass 60: the Tommy Gun's streak is short)
var trail_life := PackedFloat32Array()
var trail_next := 0
var trail_count := 0
var _trail_t := PackedFloat32Array()   # per projectile: seconds until its next trail dot
var _trail_mm: MultiMesh
## The rocketeer's rockets draw a faint smoke line all the way back to where they were fired (pass 33), so the hero can
## follow one home to the goblin: the points a rocket has passed, a camera-facing ribbon through them, faded out over a
## second once the rocket is gone. {"pts": PackedVector3Array, "proj": index or -1 once gone, "fade": 1..0}
var _paths: Array = []
var _path_mesh: ImmediateMesh
var _path_drawn := false
## the draw waits for a new physics tick and runs once per shown frame (pass 33.8): ticks run, the last one drawn, and
## the simulated time the trails have to age by
var _ticks := 0
var _drawn := -1
var _draw_dt := 0.0
const PATH_STEP := 0.6
const PATH_MAX := 360
const PATH_WIDTH := 0.22
const PATH_COLOR := Color(1.0, 0.86, 0.8, 0.5)


## The Golden Revolver's lines of energy (pass 35): shots of a weapon with params.trace leave one behind.
var traces: EnergyTraces
## Cluster Munitions' bomblets on the sand (pass 53, `params.cluster` on a weapon: a rocket's blast may scatter them).
var bomblets: Bomblets
## Where bombs just came down (pass 36): {at, t} for LANDED_CLAIM seconds, so the next bomb picks another crowd.
var _landed: Array = []
const LANDED_CLAIM := 2.0
## A planted spear shrinks away over its last this many seconds (pass 46).
const PLANT_FADE := 0.12
## Frag's shrapnel (pass 47): short steel spikes, their own kind (shrapnel_kind), born this far out from the blast's
## centre, trailing a hot bead every SHRAPNEL_TRAIL seconds.
var _shrapnel_kind := -1
const SHRAPNEL_OUT := 0.35
const SHRAPNEL_TRAIL := 0.03
## A rocket whose thrower died (pass 45): a blink, a wild climb, a dive on the thickest crowd (_fly_loose).
const LOOSE_BLINK := 0.7
const LOOSE_CLIMB := 1.0
const LOOSE_DIVE_MAX := 1.8
const LOOSE_BLINK_HZ := 8.0
const LOOSE_CLIMB_MULT := 2.5
const LOOSE_CLIMB_MIN := 9.0   # m/s: the climb is fast even when the guided rocket was slow (a slow hero)
const LOOSE_DIVE_MULT := 3.0
const LOOSE_DIVE_TIME := 0.9   # s: a far crowd makes the dive faster, so it lands in about this long
const LOOSE_DIVE_TOP := 28.0   # m/s
const LOOSE_CEILING := 9.0
## Pass 48: how far a shot of `params.ricochet_any` (the Pea Cannon, the Golden Revolver) looks for its next creature.
const RICOCHET_REACH := 7.0
## The Silver Bullet's colour (pass 48): its rounds, their tracer beads and the muzzle flash.
const SILVER := Color(0.55, 0.8, 1.0)
## Curare (pass 48): a creature it holds is tinted this dark green while slowed and poisoned; a cloud breathing on a
## creature every 0.3 s counts as one poisoning a CURARE_GAP at most.
const CURARE_TINT := Color(0.1, 0.35, 0.12)
const CURARE_GAP := 1.0
## A skull's bounce (pass 48, Bouncing Skull) flies at this speed: a hop, quicker than the throw.
const BOUNCE_SPEED := 9.0
## The shots' own clock (pass 48): physics seconds since the manager started; Curare's cooldowns run on it.
var clock := 0.0
## Curare's state per creature, keyed by EnemyManager.serial: {chance, ready (clock), last (clock), until (clock)}.
var _curare: Dictionary = {}
## Tests: a fixed roll for Curare in place of randf() (-1 = random).
var curare_roll := -1.0
## Diagnostics: Curare's procs, ricochets that needed no kill.
var curare_procs := 0
var ricochets_any := 0


func _ready() -> void:
	traces = EnergyTraces.new()
	add_child(traces)
	bomblets = Bomblets.new()
	bomblets.game = game
	add_child(bomblets)
	pos.resize(MAX); vel.resize(MAX); life.resize(MAX); dmg.resize(MAX); pierce.resize(MAX); kind.resize(MAX)
	radius.resize(MAX); kb.resize(MAX); area.resize(MAX); hostile.resize(MAX); arc.resize(MAX); homing.resize(MAX); alive.resize(MAX); spin.resize(MAX); hover.resize(MAX)
	ret.resize(MAX); stuck.resize(MAX); stuck_t.resize(MAX); psize.resize(MAX); glow.resize(MAX)
	for k in range(MAX):
		stuck[k] = -1
		psize[k] = 1.0
		glow[k] = 0.0
	weapon.resize(MAX); memo.resize(MAX); extra.resize(MAX); _trail_t.resize(MAX)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	trail_pos.resize(TRAIL_MAX)
	trail_age.resize(TRAIL_MAX); trail_col.resize(TRAIL_MAX); trail_size.resize(TRAIL_MAX); trail_life.resize(TRAIL_MAX)
	for k in range(TRAIL_MAX):
		trail_age[k] = TRAIL_LIFE
		trail_life[k] = TRAIL_LIFE
	_build_trail()
	_path_mesh = ImmediateMesh.new()
	var pmi := MeshInstance3D.new()
	pmi.mesh = _path_mesh
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.vertex_color_use_as_albedo = true
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pmi.material_override = pm
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(pmi)
	_build_looks()


func _build_trail() -> void:
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 6
	sm.rings = 3
	_trail_mm.mesh = sm
	_trail_mm.instance_count = TRAIL_MAX
	_trail_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _trail_mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)


## A bead at `at`, `size_mult` of the bead sphere, fading over `life` seconds (TRAIL_LIFE unless a tracer says shorter,
## pass 60).
func _drop_trail(at: Vector3, col: Color = Color(0.62, 0.95, 0.5, 0.45), size_mult: float = 1.0, life: float = TRAIL_LIFE) -> void:
	# a screen full of shots drops every other bead: the line still reads, the fill rate halves
	if count > 60 and (trail_next & 1) == 0:
		trail_next = (trail_next + 1) % TRAIL_MAX
		return
	trail_pos[trail_next] = at
	trail_age[trail_next] = 0.0
	trail_col[trail_next] = col
	trail_size[trail_next] = size_mult
	trail_life[trail_next] = maxf(life, 0.05)
	trail_next = (trail_next + 1) % TRAIL_MAX


## Every projectile is drawn a third bigger than its mesh says: small things read as nothing on a phone.
const CHUNK := 1.35


## `custom` (pass 45): the kind's instances carry custom data, Color(glow, 0, 0, 0), for a shader that reads
## INSTANCE_CUSTOM (the rocket's heat). Only flagged kinds are written: custom data on a MultiMesh without it is an error.
## `basis` (pass 53): the turn the mesh is drawn with inside a shot's own frame (a shot's basis looks down its flight,
## -Z): a visual's Projectile node turned so its capsule's long axis (Y) lies along -Z hands that turn here, and the
## rocket flies nose first instead of crosswise (WeaponBehavior._load_visual registered mesh, material and scale only).
func register_kind(mesh: Mesh, material: Material, scale: float = 1.0, custom: bool = false, basis: Basis = Basis()) -> int:
	scale *= CHUNK
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# the flag goes before the count, or the buffer is built without room for it
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if material:
		mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	# how far the mesh reaches along -Z, its point (a planted spear sinks it into the sand)
	var tip: float = maxf(-mesh.get_aabb().position.z, 0.05) if mesh else 0.5
	kinds.append({"mm": mm, "mmi": mmi, "scale": scale, "custom": custom, "tip": tip, "basis": basis, "turned": not basis.is_equal_approx(Basis())})
	return kinds.size() - 1


## The turn kind `k`'s mesh is drawn with inside a shot's frame (pass 53, see register_kind): a behaviour whose visual's
## Projectile node is turned sets it after WeaponBehavior registered the kind (MissilePod does).
func set_kind_basis(k: int, basis: Basis) -> void:
	if k < 0 or k >= kinds.size():
		return
	kinds[k]["basis"] = basis
	kinds[k]["turned"] = not basis.is_equal_approx(Basis())


## The turn kind `k` is drawn with (Basis() for a plain kind).
func kind_basis(k: int) -> Basis:
	if k < 0 or k >= kinds.size():
		return Basis()
	return kinds[k].get("basis", Basis())


## `hover_max` (pass 46): the most height above the ground a straight shot keeps; a tower turret's rounds keep theirs.
func fire(p_kind: int, from: Vector3, velocity: Vector3, damage: float, p_pierce: int, p_radius: float, p_life: float, w: WeaponInstance, knockback: float = 0.0, hover_max: float = 1.3) -> int:
	if free_list.is_empty():
		return -1
	var i: int = free_list.pop_back()
	pos[i] = from; vel[i] = velocity; life[i] = p_life; dmg[i] = damage; pierce[i] = p_pierce
	kind[i] = p_kind; radius[i] = p_radius; kb[i] = knockback; area[i] = 0.0
	hostile[i] = 0; arc[i] = 0; alive[i] = 1; spin[i] = randf() * TAU; homing[i] = 0
	ret[i] = 1 if (w and bool(w.params.get("return", false))) else 0
	stuck[i] = -1
	psize[i] = float(w.params.get("size_mult", 1.0)) if w else 1.0
	glow[i] = 0.0
	# a straight shot follows the ground at the height it left the muzzle, so dunes never swallow it or leave it floating
	var g0: float = game.map.height_at(from.x, from.z) if game and game.map else 0.0
	hover[i] = clampf(from.y - g0, 0.35, maxf(hover_max, 0.35))
	weapon[i] = w; memo[i] = {}; extra[i] = {}
	if w:
		# pass 53 (Thorny Weed, the Dust Devil; Garry: "slowing down works only when flying out in the case of the
		# Boomerang, coming back is faster"): params.out_speed_mult scales the way out (the life stretched, so the
		# ground covered stays the same), params.back_speed_mult the way home (set at the turn), return_damage_mult
		# the damage on the way back, second_pass one more out-and-back before the shot is freed, aura {radius, slow,
		# seconds, every, tint, pull} a slowing wake round the shot
		var om := float(w.params.get("out_speed_mult", 1.0))
		if om > 0.0 and om != 1.0:
			vel[i] = velocity * om
			life[i] = p_life / om
		if ret[i] == 1:
			extra[i]["spd0"] = velocity.length()
			extra[i]["dir0"] = velocity.normalized()
			extra[i]["dmg0"] = damage
			extra[i]["life0"] = p_life
			extra[i]["pierce0"] = p_pierce
			if bool(w.params.get("second_pass", false)):
				extra[i]["passes"] = 0
		if w.params.get("aura") is Dictionary:
			extra[i]["aura_t"] = 0.0
		if w.params.has("tail_fade"):
			# pass 60: the flight this shot fades over the end of (its life as it leaves, after any out_speed stretch)
			extra[i]["fade0"] = life[i]
		# pass 61 (Thorny Weed's look): the ground it has rolled since its last thorn specks
		var lk = w.params.get("look")
		if lk is Dictionary and (lk as Dictionary).get("specks") is Dictionary:
			extra[i]["speck"] = 0.0
	if w and bool(w.params.get("no_spin", false)):
		spin[i] = 0.0
		extra[i]["no_spin"] = true
	elif w and float(w.params.get("roll_radius", 0.0)) > 0.0:
		# pass 55 (Garry: the tumbleweed "should be [spinning] in the direction that it's moving in"): a shot that rolls
		# turns like a wheel about the axis across its flight, v / roll_radius a second, the way the King's weeds do
		extra[i]["roll"] = float(w.params["roll_radius"])
	if w and w.params.has("trace"):
		traces.game = game
		extra[i]["trace"] = traces.start(from, w, damage)
	# Mini Crits (pass 48, params.mini_crit): the round is rolled once as it leaves, and every creature it strikes, through
	# every pierce, takes it as a mini crit (EnemyManager.HIT_MINI)
	if w:
		var mc := float(w.params.get("mini_crit", 0.0))
		if mc > 0.0 and randf() < mc:
			extra[i]["mini"] = true
	count += 1
	return i


func lob(p_kind: int, from: Vector3, target: Vector3, speed: float, damage: float, p_area: float, w: WeaponInstance, knockback: float, params: Dictionary = {}) -> int:
	var i := fire(p_kind, from, Vector3.ZERO, damage, 0, 0.3, 6.0, w, knockback)
	if i < 0:
		return -1
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var dist: float = max(flat.length(), 0.5)
	var t: float = clamp(dist / max(speed, 1.0), 0.35, 2.5)
	var g := 24.0
	var vy := ((target.y - from.y) + 0.5 * g * t * t) / t
	vel[i] = flat / t + Vector3(0, vy, 0)
	arc[i] = 1
	area[i] = p_area
	# its own copy (a caller may hand in a weapon's params), with where it will come down, for the other throwers
	extra[i] = params.duplicate()
	extra[i]["target"] = target
	lobs_fired += 1
	return i


func hostile_shot(p_kind: int, from: Vector3, velocity: Vector3, damage: float, splash: float, p_life: float = 4.0, arcing := false, params: Dictionary = {}) -> int:
	var i := fire(p_kind, from, velocity, damage, 0, 0.35, p_life, null, 0.0)
	if i >= 0:
		hostile[i] = 1
		arc[i] = 1 if arcing else 0
		area[i] = splash
		radius[i] = float(params.get("hit_radius", 0.35))   # a rolling ball (the King's tumbleweeds, pass 45) is wider than a pellet
		extra[i] = params
		_trail_t[i] = 0.0
	return i


## A hostile shot with no weight of its own (no `knockback` in its params) shoves the hero by this share of its shooter's
## bite when it hits him or splashes on him (pass 54, Garry: every creature its own knockback; the dwarf's shotgun and
## the rocketeer's rocket keep theirs).
const SHOT_KNOCK := 0.7


## The shove such a shot gives (pass 54): SHOT_KNOCK x its shooter's EnemyDef.hit_knockback(), the shooter read off the
## hit's info (`id`, EnemyManager.hit_info); -1 when it names none (Player.take_damage's own default then).
static func shot_knock(info: Dictionary) -> float:
	var id := str(info.get("id", ""))
	var def: EnemyDef = Registry.enemy(id) if id != "" else null
	return SHOT_KNOCK * def.hit_knockback() if def != null else -1.0


## Writes a shot's shove into its hit's `info` (pass 54): none for a silk line (it pulls), else shot_knock when it knows
## the shooter.
static func put_shot_knock(info: Dictionary, pull: bool = false) -> void:
	if pull:
		info["knock"] = 0.0
		return
	var k := shot_knock(info)
	if k >= 0.0:
		info["knock"] = k


func _free(i: int) -> void:
	homing[i] = 0
	if alive[i] == 0:
		return
	# a rocket's smoke line stays behind and fades once the rocket is gone
	if extra[i] is Dictionary and (extra[i] as Dictionary).has("path"):
		extra[i]["path"]["proj"] = -1
	# a loose rocket's ring on the sand goes with it, however it ends (the dive, its life, clear_all)
	if extra[i] is Dictionary and int((extra[i] as Dictionary).get("loose_mark", -1)) >= 0:
		if game and game.has_method("loose_mark_end"):
			game.loose_mark_end(int(extra[i]["loose_mark"]))
		extra[i]["loose_mark"] = -1
	# a Golden Revolver shot's line stays in the air where the shot went
	if extra[i] is Dictionary and (extra[i] as Dictionary).has("trace"):
		traces.seal(extra[i]["trace"])
		(extra[i] as Dictionary).erase("trace")
	if rocket_of.has(i):
		rocket_of.erase(i)
	alive[i] = 0
	weapon[i] = null
	memo[i] = {}
	free_list.append(i)
	count -= 1


func clear_all() -> void:
	for i in range(MAX):
		_free(i)
	traces.clear()
	if bomblets:
		bomblets.clear()
	_landed.clear()
	clear_specks()


## The spots bombs are headed for or came down on in the last LANDED_CLAIM seconds (pass 36): a bomb thrower picks a
## crowd away from these, so the Molotov, the Skull Rain and the Grenade do not all land on one spot. Bomblets and the
## creatures' own lobs do not count.
func claimed_spots() -> Array:
	var out: Array = []
	for i in range(MAX):
		if alive[i] == 1 and arc[i] == 1 and hostile[i] == 0 and extra[i] is Dictionary:
			var ex: Dictionary = extra[i]
			if ex.has("target") and not ex.has("is_bomblet"):
				out.append(ex["target"])
	for s: Dictionary in _landed:
		out.append(s["at"])
	return out


func _physics_process(delta: float) -> void:
	if game == null:
		return
	var t0 := Time.get_ticks_usec()
	clock += delta
	if _curare.size() > 256:
		_prune_curare()
	var enemies: EnemyManager = game.enemies
	var player: Node3D = game.player
	var map = game.map
	# a creature's shot keeps the creatures' shot clock (High Noon slows them in the air too; pass 48: the pace knob too,
	# EnemyManager.hostile_clock, so a shot covers its ground in 1/pace the time and the slower hero still gets clear)
	var hostile_dt: float = delta * (enemies.hostile_clock() if enemies else 1.0)
	for k in range(_landed.size() - 1, -1, -1):
		_landed[k]["t"] = float(_landed[k]["t"]) - delta
		if float(_landed[k]["t"]) <= 0.0:
			_landed.remove_at(k)
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var dt: float = hostile_dt if hostile[i] == 1 else delta
		life[i] -= dt
		if hostile[i] == 0 and extra[i].has("planted"):
			# a spear standing in the sand (params.plant): it hits nothing, and shrinks away in its last moment
			if life[i] <= 0.0:
				_free(i)
			else:
				psize[i] = clampf(life[i] / PLANT_FADE, 0.0, 1.0)
			continue
		if stuck[i] >= 0:
			# the sticky grenade rides its creature, then blows where it got to
			var e := stuck[i]
			stuck_t[i] -= delta
			if extra[i].has("blink"):
				extra[i]["blink"] = float(extra[i]["blink"]) + delta * blink_hz(i)
			if enemies.alive[e] == 1 and enemies.state[e] != enemies.STATE_DYING:
				pos[i] = enemies.pos[e] + Vector3(0, enemies.size[e] * 0.7, 0)
			if stuck_t[i] <= 0.0 or enemies.alive[e] == 0 or enemies.state[e] == enemies.STATE_DYING:
				# the Golden Pineapple (pass 48): a grenade that rode its creature goes off wider (sticky.blast_mult)
				var ws: WeaponInstance = weapon[i]
				if ws and ws.params.get("sticky") is Dictionary and not (extra[i] as Dictionary).has("is_bomblet"):
					area[i] *= float((ws.params["sticky"] as Dictionary).get("blast_mult", 1.0))
				_explode(i)
				_free(i)
			continue
		if homing[i] == 1:
			if life[i] <= 0.0:
				_explode(i)
				_free(i)
			else:
				_fly_missile(i, dt, enemies, map)
			continue
		if arc[i] == 1:
			vel[i].y -= 24.0 * dt
		if ret[i] == 2 and player:
			# coming home: steered at the hero, gone when it reaches him
			var home := player.global_position + Vector3(0, hover[i], 0) - pos[i]
			home.y = 0.0
			if home.length() < 0.9:
				if int(extra[i].get("passes", 1)) == 0:
					# pass 53 (the Dust Devil's second_pass): out again from the hero, a little to one side of its first line
					extra[i]["passes"] = 1
					var wq: WeaponInstance = weapon[i]
					var om2: float = float(wq.params.get("out_speed_mult", 1.0)) if wq else 1.0
					om2 = maxf(om2, 0.05)
					var d0: Vector3 = extra[i].get("dir0", vel[i].normalized())
					d0 = d0.rotated(Vector3.UP, deg_to_rad(25.0))
					ret[i] = 1
					pierce[i] = int(extra[i].get("pierce0", pierce[i]))
					memo[i] = {}
					dmg[i] = float(extra[i].get("dmg0", dmg[i]))
					vel[i] = d0 * float(extra[i].get("spd0", 6.0)) * om2
					life[i] = float(extra[i].get("life0", 2.0)) / om2
					pos[i] = player.global_position + Vector3(0, hover[i], 0) + d0 * 0.6
					continue
				_free(i)
				continue
			vel[i] = home.normalized() * maxf(vel[i].length(), 6.0)
		pos[i] += vel[i] * dt
		# a creature's shot holds its line; only the hero's own shots tumble (saws, boomerangs, grenades)
		if hostile[i] == 0:
			if extra[i].has("roll"):
				spin[i] += dt * vel[i].length() / maxf(float(extra[i]["roll"]) * psize[i], 0.1)
			elif not extra[i].has("no_spin"):
				spin[i] += delta * 12.0
		elif extra[i].has("roll"):
			# a rolling creature's shot (the King's tumbleweeds, pass 45) turns like a wheel: v / r a second, on its clock
			spin[i] += dt * vel[i].length() / maxf(float(extra[i]["roll"]), 0.1)
		if extra[i].has("aura_t") and weapon[i]:
			# pass 53 (Dust Wake, the Dust Devil): every `every` seconds the shot slows what stands within `radius` for
			# `seconds` and tints it dark green (Curare's language for slowed); `pull` drags them toward it every frame
			var au: Dictionary = weapon[i].params.get("aura", {})
			var ar := float(au.get("radius", 1.6))
			extra[i]["aura_t"] = float(extra[i]["aura_t"]) - dt
			if float(extra[i]["aura_t"]) <= 0.0:
				extra[i]["aura_t"] = maxf(float(au.get("every", 0.2)), 0.05)
				var secs := float(au.get("seconds", 0.4))
				enemies.slow_radius(pos[i], ar, float(au.get("slow", 0.2)), secs)
				var tint := Color(str(au.get("tint", "#1A5A1E")))
				for e in enemies.indices_in_radius(pos[i], ar):
					enemies.set_status_tint(e, tint, secs)
			var pull := float(au.get("pull", 0.0))
			if pull > 0.0:
				enemies.drag_radius(pos[i], ar, pull, dt)
		if life[i] <= 0.0:
			if ret[i] == 1:
				# the boomerang turns at the end of its run: fresh pierce, fresh memory; pass 53: the way home at
				# back_speed_mult of the launch speed and the damage x return_damage_mult (the Dust Devil's x2)
				ret[i] = 2
				life[i] = 6.0
				pierce[i] = 80
				memo[i] = {}
				var wr: WeaponInstance = weapon[i]
				if wr:
					var s0: float = float(extra[i].get("spd0", vel[i].length()))
					vel[i] = vel[i].normalized() * maxf(s0 * float(wr.params.get("back_speed_mult", 1.0)), 6.0)
					dmg[i] = float(extra[i].get("dmg0", dmg[i])) * float(wr.params.get("return_damage_mult", 1.0))
				continue
			if _plant(i, map):
				continue
			_burst_spawn(i)
			_free(i)
			continue
		var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
		if arc[i] == 0:
			pos[i].y = ground + hover[i]
		if arc[i] == 1 and pos[i].y <= ground + 0.15:
			pos[i].y = ground + 0.15
			# Sticky: a creature by the landing spot gets the grenade on its back instead of a blast; the Golden
			# Pineapple's (pass 48, sticky.priority) takes the strongest one there, and its bomblets ride for
			# sticky.bomblet_seconds
			var w0: WeaponInstance = weapon[i]
			if hostile[i] == 0 and w0 and w0.params.get("sticky") is Dictionary:
				var st: Dictionary = w0.params["sticky"]
				var reach := float(st.get("reach", 1.4))
				# the creature at the landing spot, wherever the screen is (pass 54)
				var near := enemies.priority_index(pos[i], reach, "", true) if bool(st.get("priority", false)) else enemies.nearest_index(pos[i], reach, "", true)
				if near >= 0:
					stuck[i] = near
					var bomblet: bool = (extra[i] as Dictionary).has("is_bomblet")
					stuck_t[i] = float(st.get("bomblet_seconds", st.get("seconds", 1.3))) if bomblet else float(st.get("seconds", 1.3))
					arc[i] = 0
					vel[i] = Vector3.ZERO
					# pass 61 (Sticky's look): a light on whatever it rides, blinking faster towards the blast (_render_blinks)
					var lk0 = w0.params.get("look")
					if lk0 is Dictionary and (lk0 as Dictionary).get("blink") is Dictionary:
						extra[i]["blink"] = 0.0
						extra[i]["blink_t0"] = maxf(stuck_t[i], 0.05)
					continue
			_explode(i)
			_free(i)
			continue
		if arc[i] == 1 and hostile[i] == 0:
			# Oil Slick (pass 33): the burning bottle leaks as it flies, a drop every `every` metres of the throw (the
			# Moonshine's, pass 48: one burning line)
			if extra[i].has("drip") or extra[i].has("burn_line"):
				_drip(i)
			# a fire bottle's rag burns as it flies (pass 48: blue for Methanol's bottle and the Moonshine's jug, whose
			# drawn shot is the bottle alone)
			var wl: WeaponInstance = weapon[i]
			if wl and not extra[i].has("is_bomblet") and wl.stat("fire_damage", 0.0) > 0.0 and game.get("fx") != null:
				_trail_t[i] -= delta
				if _trail_t[i] <= 0.0 or _trail_t[i] > 0.2:
					_trail_t[i] = 0.07
					game.fx.flame(pos[i] + Vector3(0, 0.2, 0), 0.5, 0.22, Fx.FLAME_ORANGE, wl.blue_fire())
			# lobbed shots (skulls, grenades, bomblets) sail over and through the crowd; they only ever explode on landing
			continue
		if hostile[i] == 1:
			_trail_t[i] -= delta
			if _trail_t[i] <= 0.0:
				_trail_t[i] = TRAIL_STEP
				# silk is white; spit is green; a sun shard gold, lead smoke grey; a harpoon trails its rope (Game draws it)
				var shot_kind := str(extra[i].get("shot", ""))
				if extra[i].has("harpoon"):
					pass
				elif extra[i].has("pull"):
					_drop_trail(pos[i], Color(0.96, 0.96, 0.9, 0.7), 0.8)
				elif shot_kind == "shard":
					_drop_trail(pos[i], Color(1.0, 0.84, 0.36, 0.6), 0.9)
				elif shot_kind == "pellet":
					_drop_trail(pos[i], Color(0.42, 0.4, 0.44, 0.45), 0.7)
				elif shot_kind == "tumbleweed":
					# dust at its foot (pass 45)
					_drop_trail(pos[i] - Vector3(0, 0.3, 0), Color(0.82, 0.68, 0.45, 0.4), 1.1)
				else:
					_drop_trail(pos[i])
			if player and not player.dead:
				# a flat distance and a height band as tall as the hero: a shard off a tall creature's staff flies at
				# head height, and the old sphere under a metre across let it pass straight over him
				var d := player.global_position - pos[i]
				var dy: float = pos[i].y - player.global_position.y
				d.y = 0.0
				if d.length() < radius[i] + 0.5 and dy > -0.6 and dy < 2.4:
					var kn: float = float(extra[i].get("knockback", 0.0))
					# who fired it and what it did, for the death log
					var sinfo: Dictionary = (extra[i].get("info", {}) as Dictionary).duplicate(true)
					var sfx: Array = sinfo.get("fx", [])
					if kn > 0.0:
						sfx.append("knocked back")
					if extra[i].has("pull"):
						sfx.append("pulled in")
					if extra[i].has("harpoon"):
						sfx.append("roped")
					sinfo["fx"] = sfx
					# a shot with no weight of its own shoves him by SHOT_KNOCK of its shooter's bite (pass 54, shot_knock);
					# a silk line pulls instead; one with weight keeps its shove below
					if kn <= 0.0:
						put_shot_knock(sinfo, extra[i].has("pull"))
					player.take_damage(dmg[i], pos[i], sinfo)
					# a shot that carries weight throws him back, once a second however many land; one with `lift` too (the
					# King's tumbleweeds, pass 45) is a throw past the shove's cap, unless he evaded it
					if kn > 0.0:
						var away := player.global_position - pos[i]
						away.y = 0.0
						if away.length_squared() > 0.01:
							if extra[i].has("lift") and player.has_method("blast"):
								if not ("last_outcome" in player) or str(player.last_outcome) != "evaded":
									player.blast(away.normalized() * kn, float(extra[i]["lift"]))
									if game and game.has_method("fx_burst"):
										game.fx_burst(pos[i], Color(0.72, 0.56, 0.3), 1.2)
									Audio.play("w_tumble_hit", pos[i])
							elif player.has_method("shove"):
								# its own line (pass 60): a shot's push goes the way it flew, not out of the crowd (a fake
								# hero with the one-argument shove still takes it)
								if player.get_method_argument_count("shove") >= 2:
									player.shove(away.normalized() * kn, false)
								else:
									player.shove(away.normalized() * kn)
					# a silk line: the hero is yanked towards whoever fired it
					if extra[i].has("pull") and extra[i].has("origin") and player.has_method("apply_knockback"):
						var to: Vector3 = Vector3(extra[i]["origin"]) - player.global_position
						to.y = 0.0
						if to.length_squared() > 0.01:
							player.apply_knockback(to.normalized() * float(extra[i]["pull"]))
					# a harpoon: the rope holds from here on
					if extra[i].has("harpoon") and game and game.has_method("tether_start"):
						game.tether_start(int(extra[i].get("shooter", -1)), extra[i].get("tether", {}))
					_free(i)
			continue
		# friendly: hit enemies
		var w: WeaponInstance = weapon[i]
		var wid := w.def.id if w else ""
		if extra[i].has("trace"):
			traces.follow(extra[i]["trace"], pos[i])
		# the War Lance's wake: patches of slowing dust along its flight
		if w and w.params.has("trail_zone"):
			_dust_trail(i, w, ground)
		# a shrapnel spike (pass 47) trails hot sparks, so a Frag burst reads as metal flung out of the blast
		if extra[i].has("sparks"):
			_trail_t[i] -= delta
			if _trail_t[i] <= 0.0:
				_trail_t[i] = SHRAPNEL_TRAIL
				_drop_trail(pos[i], Color(1.0, 0.82, 0.45, 0.9), 0.6)
		# a tracer round (params.tracer): a bright short line behind every bullet, so a burst reads as shots fired; gold,
		# or the weapon's element (a Dart Buddy's rounds trail green). Pass 60: the weapon may set the beads' step,
		# life and size (params.tracer_step / tracer_life / tracer_size: the Tommy Gun drops them denser and shorter-
		# lived, so each round reads as one hot streak; the Boomstick's spray a short-lived one)
		if w and bool(w.params.get("tracer", false)):
			_trail_t[i] -= delta
			if _trail_t[i] <= 0.0:
				_trail_t[i] = maxf(float(w.params.get("tracer_step", 0.022)), 0.005)
				if not extra[i].has("tc"):
					extra[i]["tc"] = _tracer_colour(w)
				var t_size := float(w.params.get("tracer_size", 0.9))
				var t_life := float(w.params.get("tracer_life", TRAIL_LIFE))
				_drop_trail(pos[i], extra[i]["tc"], t_size, t_life)
				# pass 61 (Drum Mag's denser trails): `tracer_beads` beads a drop, the others spread back along the ground
				# this tick moved over (one bead a physics tick is the most a step can give)
				# (the review: on a Chicago Typewriter's long bursts the extra beads lapped the shared ring of TRAIL_MAX in
				# under half a second and cut every other trail short, the hostile rocket's warning among them): the extra
				# beads only while the screen is not busy with shots, and at half the life
				var nb := int(w.params.get("tracer_beads", 1)) if count <= TRACER_EXTRA_BUSY else 1
				for b in range(1, nb):
					_drop_trail(pos[i] - vel[i] * delta * float(b) / float(nb), extra[i]["tc"], t_size, t_life * 0.5)
		# pass 61 (Thorny Weed): a rolling shot with `look.specks` sheds thorn specks on the sand every `every` metres
		if extra[i].has("speck"):
			_shed_specks(i, w, delta, ground)
		# a shot that fades at the end of its range (pass 60, params.tail_fade = the last share of its flight; the
		# Boomstick's pellets lose their energy instead of popping out at the range's end): drawn shrunk over that
		# last part, never under a quarter; the hit radius is untouched. The size it had as it left is read once, so a
		# blast's ghost pellets (sized after they are fired) shrink from their own
		if extra[i].has("fade0"):
			if not extra[i].has("fade_s"):
				extra[i]["fade_s"] = psize[i]
			var fw: float = maxf(float(extra[i]["fade0"]) * float(w.params.get("tail_fade", 0.25)), 0.01) if w else 0.01
			psize[i] = float(extra[i]["fade_s"]) * clampf(life[i] / fw, 0.25, 1.0)
		# a pellet streaking down a Birdshot lane or a Blunderbuss cone (pass 48) is only seen: the blast has hit already
		if extra[i].has("ghost"):
			continue
		var hits := enemies.indices_in_radius(pos[i], radius[i] + 0.35)
		var flags: int = EnemyManager.HIT_MINI if extra[i].has("mini") else 0
		for e in hits:
			if memo[i].has(e):
				continue
			memo[i][e] = true
			var dir := vel[i]
			if w and w.stat("poison_damage", 0.0) > 0.0:
				weapon_poison(e, w)
			if w and w.stat("fire_damage", 0.0) > 0.0:
				enemies.ignite(e, wid, w.stat("fire_damage", 4.0), w.stat("fire_duration", 1.8), w.stat("fire_spread", 0.5))
			# a spear's first strike is heard (its hit sound is the thunk of the point going in)
			if w and w.params.has("plant") and not extra[i].has("hit_sfx"):
				extra[i]["hit_sfx"] = true
				Audio.play(str(w.def.sfx.get("hit", "")), pos[i])
			var killed := enemies.damage(e, dmg[i], wid, dir, kb[i], false, false, flags)
			# Iron Bastion's focus (pass 53, params.focus {mult, seconds}): a creature a bastion's round strikes takes `mult`
			# more from the next rounds for `seconds` (EnemyManager's mark, stretched by Ducktape), so the bastions gang up
			# on it: "more than the sum of its parts"
			if w and w.params.get("focus") is Dictionary and enemies.is_alive(e):
				var fc: Dictionary = w.params["focus"]
				enemies.mark_t[e] = maxf(enemies.mark_t[e], float(fc.get("seconds", 2.0)) * enemies.debuff_mult())
				enemies.mark_mult[e] = maxf(enemies.mark_mult[e], 1.0 + float(fc.get("mult", 0.2)))
			# Pinning Throw: the first creature a spear strikes and does not kill is held where it stands
			if not killed and w and not extra[i].has("pinned") and w.params.get("pin") is Dictionary and _pinnable(enemies, e):
				var pn: Dictionary = w.params["pin"]
				enemies.slow(e, float(pn.get("frac", 1.0)), float(pn.get("seconds", 1.2)))
				extra[i]["pinned"] = e
				game.fx_burst(enemies.pos[e] + Vector3(0, 0.25, 0), Color(0.86, 0.72, 0.5), 0.7)
			if killed:
				if w:
					w.kills += 1
				# Ricochet: a killing shot may bounce to the next creature, once, at 60% (never lobs or missiles);
				# a weapon with its own ricochet (Bouncing Peas) bounces at its own odds and damage
				var rc: float = Run.player_sheet.get_stat("ricochet", 0.0)
				var frac := 0.6
				if w and w.stat("ricochet", 0.0) > 0.0:
					rc = maxf(rc, w.stat("ricochet", 0.0))
					frac = w.stat("ricochet_damage", 0.6)
				# a shot that ricochets anyway (pass 48, params.ricochet_any) bounces at the end of its pierce instead
				if w and w.params.get("ricochet_any") is Dictionary:
					rc = 0.0
				if rc > 0.0 and arc[i] == 0 and not extra[i].has("bounced") and randf() < rc:
					var nxt := _nearest_other(enemies, pos[i], 7.0, memo[i])
					if nxt >= 0:
						var to: Vector3 = enemies.pos[nxt] - pos[i]
						to.y = 0.0
						var j := fire(kind[i], pos[i], to.normalized() * maxf(vel[i].length(), 8.0), dmg[i] * frac, 0, radius[i], 1.5, w, kb[i])
						if j >= 0:
							extra[j]["bounced"] = true
							memo[j][e] = true
							game.fx_burst(pos[i], Color(1.0, 0.9, 0.5), 0.45)
			if w:
				game.fx_hit(pos[i], w.def)
			pierce[i] -= 1
			if pierce[i] < 0:
				if _ricochet_on(i, enemies, w):
					break
				if _plant(i, map):
					break
				_burst_spawn(i)
				_free(i)
				break
	_tick_paths(delta)
	_ticks += 1
	_draw_dt += delta
	Perf.add("projectiles", t0)


## The shots, their trails and the rockets' lines are drawn once per shown frame, and only after a tick has moved
## them (pass 33.8: inside the physics tick, a phone below 60 fps drew them twice for every frame it showed).
func _process(_delta: float) -> void:
	if game == null or _drawn == _ticks:
		return
	_drawn = _ticks
	var t0 := Time.get_ticks_usec()
	_render()
	_tick_trail(_draw_dt)
	_tick_specks(_draw_dt)
	_draw_dt = 0.0
	_draw_paths()
	Perf.add("projectiles.draw", t0)


## The Oil Slick's leak: counts the ground a lobbed bottle has covered and lets a drop of burning oil fall every
## `drip.every` metres after the first `drip.start` (Game.oil_drip makes the spill where it lands).
func _drip(i: int) -> void:
	var p: Dictionary = extra[i]
	if p.get("burn_line") is Dictionary:
		_burn_line(i)
		return
	var dp: Dictionary = p["drip"]
	if not p.has("drip_from"):
		p["drip_from"] = pos[i]
		p["drip_went"] = 0.0
		p["drip_n"] = 0
		return
	var from: Vector3 = p["drip_from"]
	p["drip_went"] = float(p["drip_went"]) + Vector2(pos[i].x - from.x, pos[i].z - from.z).length()
	p["drip_from"] = pos[i]
	var n: int = int(p["drip_n"])
	if float(p["drip_went"]) >= float(dp.get("start", 1.2)) + float(dp.get("every", 0.9)) * n:
		p["drip_n"] = n + 1
		if game.has_method("oil_drip"):
			game.oil_drip(pos[i], weapon[i], dp)


## The Moonshine's trail (pass 48, params.burn_line {start, step, width, seconds, slow}): the Oil Slick's drops become
## one burning line on the sand under the bottle's flight, laid as it flies: after the first `start` metres a piece
## every `step` metres (an ElementCloud line, `width` across, burning `seconds`, slowing by `slow`), and the last piece
## runs on to where the bottle breaks (_explode).
func _burn_line(i: int) -> void:
	var p: Dictionary = extra[i]
	var bl: Dictionary = p["burn_line"]
	var here := Vector3(pos[i].x, game.map.height_at(pos[i].x, pos[i].z) if game.map else 0.0, pos[i].z)
	if not p.has("line_went"):
		p["line_went"] = 0.0
		p["line_last"] = here
		return
	var last: Vector3 = p["line_last"]
	p["line_went"] = float(p["line_went"]) + Vector2(here.x - last.x, here.z - last.z).length()
	p["line_last"] = here
	if float(p["line_went"]) < float(bl.get("start", 1.5)):
		return
	if not p.has("line_from"):
		p["line_from"] = here
		return
	var from: Vector3 = p["line_from"]
	if Vector2(here.x - from.x, here.z - from.z).length() >= float(bl.get("step", 1.6)):
		_lay_line(i, here)


## One piece of a burning line from where the last one ended to `to` (ground), then the next starts there.
func _lay_line(i: int, to: Vector3) -> void:
	var p: Dictionary = extra[i]
	var w: WeaponInstance = weapon[i]
	var from: Vector3 = p.get("line_from", to)
	p["line_from"] = to
	var bl = p.get("burn_line")
	if w == null or not bl is Dictionary or not game.has_method("spawn_cloud"):
		return
	if Vector2(to.x - from.x, to.z - from.z).length() < 0.3:
		return
	var b: Dictionary = bl
	game.spawn_cloud(from, w, float(b.get("width", 1.1)) * 0.5, "fire", {"line_to": to, "pool_seconds": float(b.get("seconds", 4.0)), "slow": float(b.get("slow", 0.35))})


## The Spear's end (pass 46, params.plant {seconds, tilt_deg, bury}): instead of vanishing the shot stops where it is
## and stands in the sand, tilted down along its last heading by `tilt_deg` with its point `bury` metres under, for
## `seconds`, hitting nothing (the loop skips it), then shrinks away in its last PLANT_FADE; a puff of sand and the hit
## sound where the point goes in. False for anything that does not plant (and for one already planted).
func _plant(i: int, map) -> bool:
	var w: WeaponInstance = weapon[i]
	if hostile[i] == 1 or w == null or arc[i] == 1 or homing[i] == 1 or stuck[i] >= 0:
		return false
	var pl = w.params.get("plant")
	if not pl is Dictionary or extra[i].has("planted"):
		return false
	var d := Vector3(vel[i].x, 0.0, vel[i].z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	# steep, so it reads as stuck in the ground from the high camera (at about the camera's own 46 degrees a spear thrown
	# north would be seen end on, a dot)
	var tilt := deg_to_rad(float(pl.get("tilt_deg", 70.0)))
	var fwd := (d * cos(tilt) + Vector3(0.0, -sin(tilt), 0.0)).normalized()
	var reach := 0.8
	var k := kind[i]
	if k >= 0 and k < kinds.size():
		reach = float(kinds[k].get("tip", 0.6)) * float(kinds[k]["scale"]) * psize[i]
	var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
	pos[i].y = ground - float(pl.get("bury", 0.25)) + sin(tilt) * reach
	extra[i]["planted"] = Basis.looking_at(fwd, Vector3.UP)
	vel[i] = Vector3.ZERO
	spin[i] = 0.0
	life[i] = maxf(float(pl.get("seconds", 0.6)), 0.05)
	var tip := pos[i] + fwd * reach
	if game and game.has_method("fx_sand"):
		game.fx_sand(Vector3(tip.x, ground, tip.z), 0.45)
	Audio.play(str(w.def.sfx.get("hit", "")), tip)
	return true


## A creature a spear may pin: never a boss or an Elite (by its kind or a modifier).
func _pinnable(enemies: EnemyManager, e: int) -> bool:
	if e == enemies.boss_index or enemies.elite_idx[e] >= 0:
		return false
	var def: EnemyDef = enemies.types[enemies.type_idx[e]]["def"]
	return def.archetype != "elite" and def.archetype != "boss"


## The War Lance's wake (pass 46, params.trail_zone {every, radius, seconds, slow}): a patch of dust every `every`
## metres of the flight that slows whatever walks in it and hurts nothing (Game.spawn_zone), with a puff of sand.
func _dust_trail(i: int, w: WeaponInstance, ground: float) -> void:
	var tz: Dictionary = w.params["trail_zone"]
	var ex: Dictionary = extra[i]
	if not ex.has("trail_from"):
		ex["trail_from"] = pos[i]
		return
	var from: Vector3 = ex["trail_from"]
	if Vector2(pos[i].x - from.x, pos[i].z - from.z).length() < float(tz.get("every", 1.6)):
		return
	ex["trail_from"] = pos[i]
	var at := Vector3(pos[i].x, ground, pos[i].z)
	if game.has_method("spawn_zone"):
		game.spawn_zone(at, float(tz.get("radius", 0.85)), float(tz.get("seconds", 1.6)), 0.0, 0.3, w, float(tz.get("slow", 0.45)), Color(0.84, 0.7, 0.46, 0.38))
	if game.has_method("fx_sand"):
		game.fx_sand(at, 0.4)


## A tracer bead's colour: gold, orange for a burning weapon, green for a poison one, the Silver Bullet's pale blue;
## a weapon's own `tracer_color` (pass 61, a mutation's look: Toxic Peas' sickly green, Drum Mag's hot orange) first.
func _tracer_colour(w: WeaponInstance) -> Color:
	if w.params.has("tracer_color"):
		var tc := Color(str(w.params["tracer_color"]))
		return Color(tc.r, tc.g, tc.b, float(w.params.get("tracer_alpha", 0.9)))
	if bool(w.params.get("silver", false)):
		return Color(SILVER.r, SILVER.g, SILVER.b, 0.9)
	match w.element():
		"fire":
			return Color(1.0, 0.5, 0.15, 0.9)
		"poison":
			return Color(0.5, 1.0, 0.35, 0.9)
	return Color(1.0, 0.85, 0.35, 0.9)


## Pass 48, `params.ricochet_any {count, frac, puff, puff_seconds}` (the Pea Cannon, the Golden Revolver): a shot whose
## last pierce is spent on a creature, killed or not, hops on to the nearest creature it has not struck within
## RICOCHET_REACH, `count` times, every hop at `frac` of the shot's first damage; with `puff` (metres) a small poison
## cloud is left where it bounced, `puff_seconds` long. False when it does not bounce (the shot ends as before).
func _ricochet_on(i: int, enemies: EnemyManager, w: WeaponInstance) -> bool:
	if w == null or hostile[i] == 1 or arc[i] == 1 or homing[i] == 1 or stuck[i] >= 0:
		return false
	var ra = w.params.get("ricochet_any")
	if not ra is Dictionary:
		return false
	var rd: Dictionary = ra
	var ex: Dictionary = extra[i]
	var left: int = int(ex.get("rc_left", int(rd.get("count", 0))))
	if left <= 0:
		return false
	var nxt := _nearest_other(enemies, pos[i], RICOCHET_REACH, memo[i])
	if nxt < 0:
		return false
	if not ex.has("rc_dmg"):
		ex["rc_dmg"] = dmg[i]
	ex["rc_left"] = left - 1
	ex["bounced"] = true
	ricochets_any += 1
	var to: Vector3 = enemies.pos[nxt] - pos[i]
	to.y = 0.0
	var sp: float = maxf(vel[i].length(), 8.0)
	vel[i] = to.normalized() * sp
	dmg[i] = float(ex["rc_dmg"]) * float(rd.get("frac", 0.8))
	pierce[i] = 0
	life[i] = maxf(to.length() / sp + 0.3, 0.4)
	game.fx_burst(pos[i], SILVER if bool(w.params.get("silver", false)) else Color(1.0, 0.9, 0.5), 0.45)
	var puff := float(rd.get("puff", 0.0))
	if puff > 0.0 and w.stat("poison_damage", 0.0) > 0.0 and game.has_method("spawn_cloud"):
		var g: float = game.map.height_at(pos[i].x, pos[i].z) if game.map else pos[i].y
		game.spawn_cloud(Vector3(pos[i].x, g, pos[i].z), w, puff, "poison", {"pool_seconds": float(rd.get("puff_seconds", 1.5))})
	return true


## This weapon poisons creature `e` (pass 48: its shot, its blast, its cloud; ElementCloud calls this too, so a cloud's
## poisonings count): the poison itself, then Curare's roll (`params.curare`), and the Grave Hail's double poison
## (`curare.double_poison`) on a creature its curare is holding. Negative numbers read the weapon's own stats.
func weapon_poison(e: int, w: WeaponInstance, p_dmg: float = -1.0, p_stacks: int = -1, p_duration: float = -1.0) -> void:
	var em: EnemyManager = game.enemies if game else null
	if em == null or w == null or e < 0:
		return
	var wid: String = w.def.id
	var d: float = p_dmg if p_dmg >= 0.0 else w.stat("poison_damage", 3.0)
	var st: int = p_stacks if p_stacks >= 0 else maxi(w.stat_int("poison_stacks", 1), 1)
	var du: float = p_duration if p_duration >= 0.0 else w.stat("poison_duration", 10.0)
	em.poison(e, wid, d, st, du)
	var cu = w.params.get("curare")
	if not cu is Dictionary:
		return
	_curare_roll(e, cu)
	var dbl := float((cu as Dictionary).get("double_poison", 1.0))
	if dbl > 1.0:
		# EnemyManager keeps the strongest dose a source gave; this one follows the hold instead (twice while it lasts)
		var src: Dictionary = em.poison_src[e]
		if src.has(wid):
			(src[wid] as Dictionary)["dmg"] = d * (dbl if curare_holds(e) else 1.0)


## Curare (pass 48, params.curare {chance, step, slow, seconds, cooldown}): a poisoning rolls the creature's chance, which
## starts at `chance` and grows by `step` with every poisoning that did not take; when it takes, the creature's moves and
## attacks are slowed by `slow` for `seconds` (EnemyManager.hamper) and it shows dark green (CURARE_TINT), the chance
## starts over, and nothing more takes for `cooldown` seconds. A cloud's breaths count once a CURARE_GAP.
func _curare_roll(e: int, cu: Dictionary) -> void:
	var em: EnemyManager = game.enemies
	if em.alive[e] == 0 or em.state[e] == EnemyManager.STATE_DYING:
		return
	var key: int = em.serial[e]
	var s: Dictionary = _curare.get(key, {})
	if s.is_empty():
		s = {"chance": float(cu.get("chance", 0.2)), "ready": -1.0, "last": -1000.0, "until": -1.0}
		_curare[key] = s
	if clock < float(s["ready"]) or clock - float(s["last"]) < CURARE_GAP:
		return
	s["last"] = clock
	var roll: float = curare_roll if curare_roll >= 0.0 else randf()
	if roll < float(s["chance"]):
		var secs: float = float(cu.get("seconds", 3.0))
		em.hamper(e, float(cu.get("slow", 0.5)), secs)
		var held: float = secs * em.debuff_mult()
		em.set_status_tint(e, CURARE_TINT, held)
		s["chance"] = float(cu.get("chance", 0.2))
		s["ready"] = clock + float(cu.get("cooldown", 10.0))
		s["until"] = clock + held
		curare_procs += 1
		if game.has_method("fx_burst"):
			game.fx_burst(em.pos[e] + Vector3(0, em.size[e] * 0.6, 0), Color(0.2, 0.55, 0.22), 0.7)
	else:
		s["chance"] = minf(float(s["chance"]) + float(cu.get("step", 0.2)), 1.0)


## Whether Curare is holding creature `e` right now.
func curare_holds(e: int) -> bool:
	var em: EnemyManager = game.enemies if game else null
	if em == null or e < 0 or em.alive[e] == 0:
		return false
	var s: Dictionary = _curare.get(em.serial[e], {})
	return not s.is_empty() and clock < float(s["until"])


## Curare's chance on creature `e` now (tests, the arena): its first chance when it was never rolled (-1 for none).
func curare_chance(e: int) -> float:
	var em: EnemyManager = game.enemies if game else null
	if em == null or e < 0:
		return -1.0
	var s: Dictionary = _curare.get(em.serial[e], {})
	return float(s.get("chance", -1.0))


## Forgets the creatures Curare has not touched in a while (their slots have new creatures by now).
func _prune_curare() -> void:
	for key in _curare.keys():
		var s: Dictionary = _curare[key]
		if clock - float(s["last"]) > 30.0 and clock >= float(s["ready"]):
			_curare.erase(key)


## Sky Flare and Frag: when a shot ends it spawns others. `burst_spawn` on the weapon's params: kind "ember" lobs
## `count` embers to a ring around the spot, kind "shrapnel" throws `count` steel spikes out (_shrapnel); never off a
## burst.
func _burst_spawn(i: int) -> void:
	var w: WeaponInstance = weapon[i]
	if w == null or hostile[i] == 1 or extra[i].has("is_burst"):
		return
	var bs = w.params.get("burst_spawn")
	if not bs is Dictionary:
		return
	var n := int(bs.get("count", 5))
	var dm := float(bs.get("damage_mult", 0.5))
	if str(bs.get("kind", "shrapnel")) == "ember":
		var ring := float(bs.get("ring", 2.0))
		for k in range(n):
			var a := TAU * float(k) / float(n) + randf_range(-0.2, 0.2)
			var target := pos[i] + Vector3(cos(a), 0, sin(a)) * ring
			var j := lob(kind[i], pos[i] + Vector3(0, 0.6, 0), target, 7.0, dmg[i] * dm, float(bs.get("area", 1.2)), w, kb[i] * 0.5, {"is_burst": true})
			if j >= 0:
				vel[j].y += 5.0
		game.fx_burst(pos[i], Color(1.0, 0.85, 0.45), 1.0)
		return
	_shrapnel(i, w, bs, n, dm)


## Frag (pass 47, Garry: the grenade "just disappears on collision instead of exploding into a bunch of shrapnel"): the
## burst throws `count` short steel spikes flat out from where it blew, round the compass from a random start, each
## flying straight along its line (no spin) at `speed` for `life` seconds and trailing hot sparks. The spikes used to be
## born in the middle of the crowd the grenade picked: every one hit the creature at the centre on its first tick and was
## gone before it moved, so nothing flew. Now the creatures the blast itself caught are already behind them (their memo),
## and a spike's hit (`pierce`, 0 by default) lands on something past the blast. A small blast where it went off and
## steel grit thrown up. A Cluster Bomb's bomblet (the evolution keeps Frag) throws half as many, without the sparks
## behind them, after a plain flash: two bombs and twelve bomblets would otherwise fling 84 sparking spikes a volley.
func _shrapnel(i: int, w: WeaponInstance, bs: Dictionary, n: int, dm: float) -> void:
	var at := pos[i]
	var bomblet: bool = (extra[i] as Dictionary).has("is_bomblet")
	if bomblet:
		n = maxi(n / 2, 1)
	var enemies: EnemyManager = game.enemies if game else null
	var caught := {}
	if enemies and area[i] > 0.0:
		for e in enemies.indices_in_radius(at, area[i]):
			caught[e] = true
	var sp := float(bs.get("speed", 14.0))
	var life_s := float(bs.get("life", 0.5))
	var spike := shrapnel_kind()
	var a0 := randf() * TAU
	for k in range(n):
		var a := a0 + TAU * float(k) / float(maxi(n, 1)) + randf_range(-0.15, 0.15)
		var d := Vector3(cos(a), 0, sin(a))
		var j := fire(spike, at + d * SHRAPNEL_OUT + Vector3(0, 0.3, 0), d * sp, dmg[i] * dm, int(bs.get("pierce", 0)), 0.22, life_s, w, kb[i] * 0.5)
		if j >= 0:
			extra[j] = {"is_burst": true, "no_spin": true, "shrapnel": true}
			if not bomblet:
				extra[j]["sparks"] = true
			spin[j] = 0.0
			psize[j] = float(bs.get("size", 1.0))
			memo[j] = caught.duplicate()
			_trail_t[j] = 0.0
	var fx = game.get("fx") if game else null
	if fx == null:
		if game and game.has_method("fx_burst"):
			game.fx_burst(at, Color(1.0, 0.85, 0.45), 1.0)
		return
	if not bomblet and fx.has_method("explosion"):
		fx.explosion(at, float(bs.get("blast", 0.55)))
	elif fx.has_method("burst"):
		fx.burst(at + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.45), 0.8)
	if fx.has_method("splinters"):
		fx.splinters(at, Color(0.56, 0.56, 0.6), 8, 0.12)


## The shrapnel's kind (pass 47, Garry: "we use spikes as shrapnel instead of the smaller grenades"), registered the
## first time a burst or the warm-up asks for it.
func shrapnel_kind() -> int:
	if _shrapnel_kind < 0:
		_shrapnel_kind = register_kind(_spike_mesh(), _spike_material(), 1.0)
	return _shrapnel_kind


## A short four-sided steel spike along -Z (a shot's basis looks along its flight): the point ahead, a blunt square back.
static func _spike_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, 0, -0.44)
	var w := 0.07
	var back := 0.12
	var c := [Vector3(-w, -w, back), Vector3(w, -w, back), Vector3(w, w, back), Vector3(-w, w, back)]
	for k in range(4):
		var p0: Vector3 = c[k]
		var p1: Vector3 = c[(k + 1) % 4]
		var nrm := (tip - p0).cross(p1 - p0).normalized()
		st.set_normal(nrm)
		st.add_vertex(p0)
		st.add_vertex(tip)
		st.add_vertex(p1)
	st.set_normal(Vector3(0, 0, 1))
	for idx in [0, 2, 1, 0, 3, 2]:
		st.add_vertex(c[idx])
	return st.commit()


## Dark gunmetal, a little hot from the blast: dark so a spike reads against the pale sand from the high camera, its hot
## sparks behind it; both faces drawn (the hand-built winding needs no care).
static func _spike_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.3, 0.33)
	m.metallic = 0.5
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.15)
	m.emission_energy_multiplier = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The nearest live creature to `from` within `r` that a shot has not already hit.
func _nearest_other(enemies: EnemyManager, from: Vector3, r: float, seen: Dictionary) -> int:
	var best := -1
	var best_d := r * r
	for e in enemies.indices_in_radius(from, r):
		if seen.has(e) or enemies.state[e] == EnemyManager.STATE_DYING:
			continue
		var d2: float = (enemies.pos[e] - from).length_squared()
		if d2 < best_d:
			best_d = d2
			best = e
	return best


## A homing missile: launched along `dir`, it corkscrews for `wander` seconds, then locks onto the nearest creature and
## turns towards it at `turn` rad/s, diving; it bursts in `p_area` (0 = a single hit) on contact, on the ground or
## when its life runs out. `params.trail` 1 is rocket smoke, 2 a bee's gold dust.
func launch_missile(p_kind: int, from: Vector3, dir: Vector3, speed: float, damage: float, p_area: float, p_range: float, w: WeaponInstance, params: Dictionary, knockback: float = 0.0) -> int:
	var i := fire(p_kind, from, dir.normalized() * speed * 0.6, damage, 0, 0.3, float(params.get("life", 4.5)), w, knockback)
	if i < 0:
		return -1
	homing[i] = 1
	# a rocket hits as big as it looks (pass 53): a Heavy Warhead's fat rocket (size_mult) was still a 0.3 m hit
	radius[i] = 0.3 * psize[i]
	var wid0: String = w.def.id if w else "?"
	missiles_by_weapon[wid0] = int(missiles_by_weapon.get(wid0, 0)) + 1
	area[i] = p_area
	extra[i] = {"speed": speed, "wander": float(params.get("wander", 0.5)), "turn": float(params.get("turn", 6.0)), "spiral": float(params.get("spiral", 7.0)),
		"age": 0.0, "target": -1, "phase": randf() * TAU, "range": p_range, "trail": int(params.get("trail", 1))}
	_trail_t[i] = 0.0
	return i


## The rocketeer's rocket: slow, bright red, hunts the hero for as long as its goblin lives, and nothing the hero
## carries can touch it (hostile shots are never in the weapons' hit loop). Explodes on the hero or on the ground it
## dives to; when its goblin dies it goes loose and comes down on his own crowd (kill_rockets_of, _fly_loose).
func launch_enemy_rocket(p_kind: int, shooter: int, from: Vector3, dir: Vector3, speed: float, turn: float, damage: float, p_area: float, speed_of_hero: float = 0.0, info: Dictionary = {}, blast: Dictionary = {}) -> int:
	var i := fire(p_kind, from, dir.normalized() * speed, damage, 0, 0.42, 60.0, null, 0.0)
	if i < 0:
		return -1
	hostile[i] = 1
	homing[i] = 1
	area[i] = p_area
	extra[i] = {"speed": speed, "wander": 0.0, "turn": turn, "spiral": 0.0, "age": 0.0, "target": -1, "phase": 0.0, "range": 0.0,
		"trail": 3, "rocket": true, "shooter": shooter, "speed_of_hero": speed_of_hero, "info": info, "blast": blast}
	rocket_of[i] = shooter
	_trail_t[i] = 0.0
	# the smoke line home starts at the goblin's launch tube
	var rec := {"pts": PackedVector3Array([from]), "proj": i, "fade": 1.0}
	_paths.append(rec)
	extra[i]["path"] = rec
	return i


## Whether the creature `shooter` has a rocket of its own in the air (the rocketeer reloads only once it is gone).
func has_rocket_of(shooter: int) -> bool:
	for pi in rocket_of.keys():
		if int(rocket_of[pi]) == shooter and alive[int(pi)] == 1:
			return true
	return false


## The rockets whose thrower was `shooter` lose their guidance and go loose (pass 45, _fly_loose): they stop and blink
## red and white for LOOSE_BLINK seconds while a red ring blinks on the sand under the crowd they will take, climb wild
## and fast for LOOSE_CLIMB, then dive on the thickest crowd. A loose rocket cannot touch the hero; it throws creatures
## about and barely scratches them (Game.loose_rocket_blast).
func kill_rockets_of(shooter: int) -> void:
	for pi in rocket_of.keys():
		if int(rocket_of[pi]) == shooter:
			var i: int = int(pi)
			if alive[i] == 1 and extra[i].has("rocket"):
				var p: Dictionary = extra[i]
				p["loose"] = true
				p["loose_t"] = 0.0
				p["loose_phase"] = 0
				p["wild"] = randf() * TAU
				p["target"] = -1
				p["dive_at"] = Vector3.INF
				p["loose_mark"] = -1
				p["blink_n"] = -1
				life[i] = LOOSE_BLINK + LOOSE_CLIMB + LOOSE_DIVE_MAX
				dmg[i] = 6.0
				psize[i] = 1.0
				# the ring goes under a crowd from the first blink; the dive looks again (crowds walk)
				_lock_dive(i)
				game.fx_burst(pos[i], Color(1.0, 0.7, 0.3), 1.2)
				if game.has_method("toast"):
					game.toast("ROCKET LOOSE!", Color(1.0, 0.55, 0.2))
				Audio.play("en_rocket_loose", pos[i])
				# nobody to find any more: the line home fades
				if p.has("path"):
					p["path"]["proj"] = -1
			rocket_of.erase(pi)


func _fly_rocket(i: int, delta: float, map) -> void:
	var p: Dictionary = extra[i]
	var player: Node3D = game.player
	var heading: Vector3 = vel[i].normalized() if vel[i].length_squared() > 0.0001 else Vector3.FORWARD
	if bool(p.get("loose", false)):
		# no hand on it any more (pass 45): it blinks, climbs wild and dives on the thickest crowd
		_fly_loose(i, delta, map)
		return
	# the rocket keeps to a fraction of the hero's top speed (pass 33.2: 90%), so it gains on nobody and nobody outruns it
	# for free: a Sprint makes it faster too, a harpoon rope slower
	var soh: float = float(p.get("speed_of_hero", 0.0))
	if soh > 0.0 and player and player.has_method("max_speed"):
		# the hero's top speed has the pace knob in it and the rocket flies on the paced shot clock (pass 48): taken out
		# here once, so the rocket keeps to its share of his speed instead of paying the pace twice. Pass 60: the hero's own
		# knob (Run.move_pace) comes out, so the creatures' creature_speed_mult in the shot clock stays in, and the rocket is
		# 10% slower with every other hostile shot
		var pc: float = maxf(Run.move_pace(), 0.05)
		p["speed"] = maxf(player.max_speed() * soh / pc, 1.0)
	if player and not player.dead:
		var want: Vector3 = (player.global_position + Vector3(0, 0.9, 0) - pos[i])
		if want.length_squared() > 0.0001:
			want = want.normalized()
			var ang := heading.angle_to(want)
			if ang > 0.001 and ang < PI - 0.02:
				heading = heading.slerp(want, clampf(float(p["turn"]) * delta / ang, 0.0, 1.0)).normalized()
			elif ang >= PI - 0.02:
				heading = heading.rotated(Vector3.UP, float(p["turn"]) * delta).normalized()
	vel[i] = heading * float(p["speed"])
	pos[i] += vel[i] * delta
	# no tumbling: a rocket points where it is going, and it pulses bigger and smaller twice a second so the eye
	# catches it against the sand
	spin[i] = 0.0
	var age2: float = float(p.get("age2", 0.0)) + delta
	p["age2"] = age2
	psize[i] = 1.0 + 0.28 * sin(age2 * 12.0)
	var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
	pos[i].y = clampf(pos[i].y, ground + 0.5, ground + 4.0)
	# the faint line home: a point every PATH_STEP metres, the oldest half thinned when it gets long
	var rec = p.get("path")
	if rec is Dictionary:
		var pts: PackedVector3Array = rec["pts"]
		if pts.is_empty() or pts[pts.size() - 1].distance_to(pos[i]) >= PATH_STEP:
			pts.append(pos[i])
			if pts.size() > PATH_MAX:
				var thin := PackedVector3Array()
				var half := pts.size() / 2
				for k in range(pts.size()):
					if k >= half or k % 2 == 0:
						thin.append(pts[k])
				pts = thin
			rec["pts"] = pts
	_trail_t[i] -= delta
	if _trail_t[i] <= 0.0:
		# a bright red and white smoke line, thick, so the rocket is seen coming from across the screen
		_trail_t[i] = 0.03
		extra[i]["puff"] = int(extra[i].get("puff", 0)) + 1
		if int(extra[i]["puff"]) % 2 == 0:
			_drop_trail(pos[i], Color(1.0, 0.15, 0.1, 0.9), 1.6)
		else:
			_drop_trail(pos[i], Color(1.0, 0.85, 0.8, 0.85), 1.0)
	if player and not player.dead:
		var d := player.global_position + Vector3(0, 0.9, 0) - pos[i]
		if d.length() < radius[i] + 0.6:
			_explode(i)
			rocket_of.erase(i)
			_free(i)


## A loose rocket (pass 45), three phases kept on extra: loose_t (seconds since it went loose) and loose_phase 0 blink /
## 1 climb / 2 dive. Blink: it hangs (its speed falls to 15%, the nose lifting), grows to 1.7x and flashes red and white
## at LOOSE_BLINK_HZ (glow[] -> core/shaders/rocket.gdshader) with a spark on every beat, a red ring blinking on the sand
## under the crowd it will take. Climb: a fast rolling corkscrew up at LOOSE_CLIMB_MULT, drifting towards that crowd,
## levelling off under LOOSE_CEILING, white-hot. Dive: the thickest crowd is looked up again (crowds walk), LOOSE_DIVE_MULT,
## straight in; it goes off through _explode_loose on the crowd, on the ground or when its life runs out. Never the hero.
## `delta` is the creatures' clock, so High Noon slows the whole show like every creature's shot.
func _fly_loose(i: int, delta: float, map) -> void:
	var p: Dictionary = extra[i]
	var heading: Vector3 = vel[i].normalized() if vel[i].length_squared() > 0.0001 else Vector3.FORWARD
	var t: float = float(p.get("loose_t", 0.0)) + delta
	p["loose_t"] = t
	var base: float = maxf(float(p.get("speed", 4.0)), 1.0)
	var phase: int = int(p.get("loose_phase", 0))
	if phase == 0 and t >= LOOSE_BLINK:
		phase = 1
		p["loose_phase"] = 1
		p["wild"] = randf() * TAU
		game.fx_burst(pos[i], Color(1.0, 0.9, 0.7), 1.0)
		Audio.play("en_rocket_wild", pos[i])
	elif phase == 1 and t >= LOOSE_BLINK + LOOSE_CLIMB:
		phase = 2
		p["loose_phase"] = 2
		_lock_dive(i)
		# fast enough to land in about LOOSE_DIVE_TIME however far the crowd is (up to LOOSE_DIVE_TOP)
		var d0: float = pos[i].distance_to(_dive_aim(i))
		p["dive_speed"] = maxf(minf(d0 / LOOSE_DIVE_TIME, LOOSE_DIVE_TOP), base * LOOSE_DIVE_MULT)
		game.fx_burst(pos[i], Color(1.0, 0.3, 0.1), 1.0)
		Audio.play("en_rocket_dive", pos[i])
	_tick_loose_mark(i, t)
	var ground0: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
	if phase == 0:
		var k: float = clampf(t / LOOSE_BLINK, 0.0, 1.0)
		var blink: float = _loose_blink(t)
		glow[i] = blink
		psize[i] = lerpf(1.0, 1.7, k) * (1.0 + 0.2 * blink)
		heading.y = lerpf(heading.y, 0.35, clampf(delta * 4.0, 0.0, 1.0))
		heading = heading.normalized()
		vel[i] = heading * base * lerpf(1.0, 0.15, k)
		# a spark on every bright beat
		var n: int = int(t * LOOSE_BLINK_HZ)
		if n != int(p.get("blink_n", -1)):
			p["blink_n"] = n
			game.fx_burst(pos[i], Color(1.0, 0.95, 0.9), 0.6)
	elif phase == 1:
		# it drifts towards the crowd it will take while the yaw swings wide on a sine: a corkscrew up
		var to: Vector3 = _dive_aim(i) - pos[i]
		to.y = 0.0
		var flat := Vector3(heading.x, 0.0, heading.z)
		if to.length_squared() > 0.01 and flat.length_squared() > 0.0001:
			var a: float = flat.signed_angle_to(to, Vector3.UP)
			heading = heading.rotated(Vector3.UP, clampf(a, -3.0 * delta, 3.0 * delta))
		p["wild"] = float(p["wild"]) + delta * 11.0
		heading = heading.rotated(Vector3.UP, sin(float(p["wild"])) * 9.0 * delta)
		# nose up, levelling off over the last two metres under the ceiling
		var room: float = clampf((ground0 + LOOSE_CEILING - pos[i].y) / 2.0, 0.0, 1.0)
		heading.y = lerpf(heading.y, 0.75 * room, clampf(delta * 5.0, 0.0, 1.0))
		heading = heading.normalized()
		vel[i] = heading * maxf(base * LOOSE_CLIMB_MULT, LOOSE_CLIMB_MIN)
		# white-hot, flickering
		glow[i] = 0.8 + 0.2 * sin(t * 40.0)
		psize[i] = 1.5
		spin[i] += delta * 16.0
	else:
		var aim: Vector3 = _dive_aim(i)
		var want: Vector3 = aim - pos[i]
		var dive: float = float(p.get("dive_speed", base * LOOSE_DIVE_MULT))
		# it pitches over hard: the faster it goes, the faster it turns (a turn about 2.5 m across)
		var turn: float = maxf(7.0, dive / 2.5)
		if want.length_squared() > 0.0001:
			want = want.normalized()
			var ang: float = heading.angle_to(want)
			if ang > 0.001 and ang < PI - 0.02:
				heading = heading.slerp(want, clampf(turn * delta / ang, 0.0, 1.0)).normalized()
			elif ang >= PI - 0.02:
				heading = heading.rotated(Vector3.RIGHT, turn * delta).normalized()
		vel[i] = heading * dive
		glow[i] = 1.0
		psize[i] = 1.4
		spin[i] += delta * 10.0
		if pos[i].distance_to(aim) < 1.2:
			_explode_loose(i)
			return
	pos[i] += vel[i] * delta
	var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
	if phase == 2 and pos[i].y <= ground + 0.35:
		_explode_loose(i)
		return
	pos[i].y = clampf(pos[i].y, ground + 0.5, ground + (LOOSE_CEILING if phase >= 1 else 4.0))
	_trail_t[i] -= delta
	if _trail_t[i] <= 0.0:
		_trail_t[i] = 0.05 if phase == 0 else 0.02
		p["puff"] = int(p.get("puff", 0)) + 1
		if phase == 0:
			_drop_trail(pos[i], Color(1.0, 1.0, 1.0, 0.9) if glow[i] > 0.5 else Color(1.0, 0.5, 0.15, 0.7), 1.1)
		elif int(p["puff"]) % 2 == 0:
			_drop_trail(pos[i], Color(1.0, 0.98, 0.9, 0.95), 1.3)
		else:
			_drop_trail(pos[i], Color(1.0, 0.35, 0.1, 0.9), 1.9)
	if life[i] <= 0.0:
		_explode_loose(i)


## The loose rocket's blink at `t` seconds: 0 red, 1 white, a near-square wave at LOOSE_BLINK_HZ (on, off, on: it reads
## as a warning light, not a glow).
func _loose_blink(t: float) -> float:
	return smoothstep(-0.35, 0.35, sin(TAU * LOOSE_BLINK_HZ * t))


## Where a loose rocket will come down: the thickest crowd within 30 m (EnemyManager.densest_point), the creature nearest
## that spot followed from then on; nothing in reach = the nearest creature within 40 m, or straight down where it is.
func _lock_dive(i: int) -> void:
	var p: Dictionary = extra[i]
	var enemies2: EnemyManager = game.enemies
	var dense: Vector3 = Vector3.INF
	if enemies2:
		# a dead rocketeer's rocket is no weapon of the hero's: any crowd, on the screen or off it (pass 54)
		dense = enemies2.densest_point(pos[i], 30.0, "", [], 0.0, true)
		if dense == Vector3.INF:
			var near: int = enemies2.nearest_index(pos[i], 40.0, "", true)
			if near >= 0:
				dense = enemies2.pos[near]
	if dense == Vector3.INF:
		dense = Vector3(pos[i].x, game.map.height_at(pos[i].x, pos[i].z) if game.map else 0.0, pos[i].z)
	p["dive_at"] = dense
	p["target"] = enemies2.nearest_index(dense, 2.5, "", true) if enemies2 else -1


## Where a loose rocket is headed now: its creature while that one lives (and is not buried or held), else the last
## spot it had.
func _dive_aim(i: int) -> Vector3:
	var p: Dictionary = extra[i]
	var enemies2: EnemyManager = game.enemies
	var t2: int = int(p.get("target", -1))
	if t2 >= 0 and enemies2 and enemies2.is_alive(t2) and enemies2.hidden[t2] == 0 and enemies2.held[t2] == 0:
		p["dive_at"] = enemies2.pos[t2]
		return enemies2.pos[t2] + Vector3(0, 0.4, 0)
	var at = p.get("dive_at", Vector3.INF)
	if at is Vector3 and at != Vector3.INF:
		return at
	return Vector3(pos[i].x, game.map.height_at(pos[i].x, pos[i].z) if game.map else 0.0, pos[i].z)


## The red ring on the sand under the crowd a loose rocket will take: made on its first tick, moved with the crowd,
## blinking with the rocket through the blink, then solid. Game owns the mark (loose_mark/_move/_end); _free releases it.
func _tick_loose_mark(i: int, t: float) -> void:
	if not game.has_method("loose_mark"):
		return
	var p: Dictionary = extra[i]
	var aim: Vector3 = _dive_aim(i)
	var id: int = int(p.get("loose_mark", -1))
	if id < 0:
		id = int(game.loose_mark(aim, maxf(area[i], 2.4)))
		p["loose_mark"] = id
	var a: float = (0.25 + 0.65 * _loose_blink(t)) if t < LOOSE_BLINK else 0.9
	game.loose_mark_move(id, aim, a)


func _fly_missile(i: int, delta: float, enemies: EnemyManager, map) -> void:
	var p: Dictionary = extra[i]
	if p.has("rocket"):
		_fly_rocket(i, delta, map)
		return
	var age: float = float(p["age"]) + delta
	p["age"] = age
	var spd: float = float(p["speed"])
	var heading: Vector3 = vel[i].normalized() if vel[i].length_squared() > 0.0001 else Vector3.FORWARD
	var wander: float = float(p["wander"])
	if age < wander:
		# the corkscrew: the yaw swings on a sine while the nose eases towards level, at reduced speed
		var ph: float = float(p["phase"]) + age * float(p["spiral"])
		heading = heading.rotated(Vector3.UP, sin(ph) * 6.5 * delta)
		heading.y = lerpf(heading.y, 0.3, clampf(delta * 3.0, 0.0, 1.0))
		heading = heading.normalized()
		spd *= 0.65
	else:
		var t: int = int(p["target"])
		if t < 0 or enemies.alive[t] == 0 or enemies.state[t] == EnemyManager.STATE_DYING or enemies.hidden[t] == 1:
			# a priority weapon's seekers (pass 48: the Killer Bees) lock on the strong and the close
			var wl: WeaponInstance = weapon[i]
			var reach: float = float(p["range"]) + 6.0
			# homing (pass 54): a seeker hunts off the screen too
			t = enemies.priority_index(pos[i], reach, "", true) if (wl and wl.def.targeting == "priority") else enemies.nearest_index(pos[i], reach, "", true)
			p["target"] = t
		if t >= 0:
			var want: Vector3 = (enemies.pos[t] + Vector3(0, enemies.size[t] * 0.45, 0) - pos[i]).normalized()
			var ang := heading.angle_to(want)
			if ang > 0.0001 and ang < PI - 0.02:
				heading = heading.slerp(want, clampf(float(p["turn"]) * delta / ang, 0.0, 1.0)).normalized()
			elif ang >= PI - 0.02:
				# straight behind: slerp has no plane to turn in, so yaw
				heading = heading.rotated(Vector3.UP, float(p["turn"]) * delta).normalized()
		else:
			heading.y = lerpf(heading.y, -0.25, clampf(delta * 2.0, 0.0, 1.0))
			heading = heading.normalized()
	vel[i] = heading * spd
	pos[i] += vel[i] * delta
	spin[i] += delta * 20.0
	var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
	if pos[i].y < ground + 0.25:
		pos[i].y = ground + 0.25
		if age >= wander:
			if area[i] > 0.05:
				_explode(i)
			else:
				# a seeker (no blast) just fizzles in the sand: the zero-radius blast used to spawn a zero-radius cloud
				# whose mesh logged hundreds of warnings each, and every bee dived at once when a boss died
				game.fx_burst(pos[i], Color(0.9, 0.8, 0.5), 0.35)
			_free(i)
			return
		vel[i].y = absf(vel[i].y)
	pos[i].y = minf(pos[i].y, ground + 7.0)
	_trail_t[i] -= delta
	if _trail_t[i] <= 0.0:
		_trail_t[i] = 0.028
		if int(p["trail"]) == 1:
			# rocket smoke: dark puffs with a hot white core every other drop, so the trail reads on the sand (a warm
			# puff the colour of the ground was invisible)
			extra[i]["puff"] = int(extra[i].get("puff", 0)) + 1
			if int(extra[i]["puff"]) % 2 == 0:
				_drop_trail(pos[i], Color(0.32, 0.31, 0.42, 0.78), 1.5)
			else:
				_drop_trail(pos[i], Color(1.0, 0.96, 0.85, 0.9), 0.75)
		elif int(p["trail"]) == 4:
			# a bee on Pollen's buff (pass 48): a red line
			_drop_trail(pos[i], Color(1.0, 0.16, 0.12, 0.75), 0.85)
		else:
			# a seeker's line: dark, thin
			_drop_trail(pos[i], Color(0.32, 0.2, 0.08, 0.6), 0.8)
	# contact
	var hits := enemies.indices_in_radius(pos[i], radius[i] + 0.4)
	if hits.is_empty():
		return
	if area[i] > 0.01:
		_explode(i)
	else:
		var w: WeaponInstance = weapon[i]
		var wid := w.def.id if w else ""
		var e: int = hits[0]
		# a seeker's sting carries the weapon's element (Ember Bees)
		if w and w.stat("fire_damage", 0.0) > 0.0:
			enemies.ignite(e, wid, w.stat("fire_damage", 4.0), w.stat("fire_duration", 1.8), w.stat("fire_spread", 0.5))
		if w and w.stat("poison_damage", 0.0) > 0.0:
			weapon_poison(e, w)
		var at_kill: Vector3 = enemies.pos[e]
		var killed := enemies.damage(e, dmg[i], wid, vel[i], kb[i])
		if killed and w:
			w.kills += 1
			# the Hive Queen (pass 48, params.flower_on_kill): a bee's kill now and then sprouts a flower where it fell
			var fk := float(w.params.get("flower_on_kill", 0.0))
			if fk > 0.0 and randf() < fk:
				FlowerField.sprout(game, at_kill)
		if w:
			game.fx_hit(pos[i], w.def)
		# Second Sting: a bee that kills loops round and dives at the next creature, `second_sting` times (true is
		# once; the Hive Queen's twice, pass 48)
		var stings: int = int(w.params.get("second_sting", 0)) if w else 0
		if killed and stings > 0 and int(extra[i].get("second", 0)) < stings:
			extra[i]["second"] = int(extra[i].get("second", 0)) + 1
			extra[i]["target"] = -1
			extra[i]["age"] = float(extra[i].get("wander", 0.0))
			life[i] = maxf(life[i], 1.5)
			vel[i] = -vel[i] * 0.5 + Vector3(0, 3.0, 0)
			game.fx_burst(pos[i], Color(1.0, 0.85, 0.3), 0.6)
			return
	_free(i)


func _tick_trail(delta: float) -> void:
	var n := 0
	for k in range(TRAIL_MAX):
		# each bead on its own life (pass 60: a tracer's beads go sooner than a spit trail's); one that reaches it this
		# frame is not drawn once more at nothing
		var tl: float = trail_life[k]
		if trail_age[k] >= tl:
			continue
		trail_age[k] += delta
		if trail_age[k] >= tl:
			continue
		var f: float = clampf(trail_age[k] / tl, 0.0, 1.0)
		var s: float = (1.0 - f * 0.7) * maxf(trail_size[k], 0.1)
		_trail_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, s, s)), trail_pos[k]))
		var c: Color = trail_col[k]
		_trail_mm.set_instance_color(n, Color(c.r, c.g, c.b, c.a * (1.0 - f)))
		n += 1
	_trail_mm.visible_instance_count = n


## The lines of rockets that are gone fade over a second and a bit, and go (the tick; _draw_paths draws them).
func _tick_paths(delta: float) -> void:
	if _paths.is_empty():
		return
	var keep: Array = []
	for rec in _paths:
		if int(rec["proj"]) < 0:
			rec["fade"] = float(rec["fade"]) - delta / 1.2
			if float(rec["fade"]) <= 0.0:
				continue
		keep.append(rec)
	_paths = keep


## The rockets' lines home, as one ImmediateMesh: a flat ribbon per segment facing the camera, from the launch point to
## the rocket (or to where it ended, fading).
func _draw_paths() -> void:
	if _paths.is_empty():
		if _path_drawn:
			_path_mesh.clear_surfaces()
			_path_drawn = false
		return
	var cam := get_viewport().get_camera_3d()
	var to_cam: Vector3 = cam.global_transform.basis.z if cam else Vector3.UP
	_path_mesh.clear_surfaces()
	var begun := false
	for rec in _paths:
		var pi: int = int(rec["proj"])
		var pts: PackedVector3Array = rec["pts"]
		if pi >= 0 and alive[pi] == 1:
			pts.append(pos[pi])
		if pts.size() < 2:
			continue
		if not begun:
			_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
		var c := Color(PATH_COLOR.r, PATH_COLOR.g, PATH_COLOR.b, PATH_COLOR.a * float(rec["fade"]))
		for k in range(pts.size() - 1):
			var p0 := pts[k]
			var p1 := pts[k + 1]
			var dir := p1 - p0
			if dir.length_squared() < 0.0001:
				continue
			var side := dir.cross(to_cam).normalized() * PATH_WIDTH * 0.5
			for v in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
				_path_mesh.surface_set_color(c)
				_path_mesh.surface_add_vertex(v)
	if begun:
		_path_mesh.surface_end()
	_path_drawn = begun


## A loose rocket goes off: it scratches the crowd and throws it about (Game.loose_rocket_blast: the rocket's own fireball
## and throw, pass 45), and the hero is not touched at all.
func _explode_loose(i: int) -> void:
	var enemies: EnemyManager = game.enemies
	var r: float = maxf(area[i], 2.4)
	if enemies:
		enemies.damage_radius(pos[i], r, dmg[i], "loose_rocket", 11.0)
	if game.has_method("loose_rocket_blast"):
		game.loose_rocket_blast(pos[i], r, extra[i].get("blast", {}))
	else:
		game.fx_burst(pos[i] + Vector3(0, 0.5, 0), Color(1.0, 0.6, 0.2), 3.0)
		if game.has_method("shockwave"):
			game.shockwave(pos[i], r)
		Audio.play("en_rocket_boom", pos[i])
	rocket_of.erase(i)
	_free(i)


func _explode(i: int) -> void:
	var enemies: EnemyManager = game.enemies
	if hostile[i] == 1:
		if extra[i].has("rocket"):
			# a loose one (its rocketeer is dead) ran its life out: it goes off on the crowd, never on the hero (pass 45)
			if bool(extra[i].get("loose", false)):
				_explode_loose(i)
				return
			# the rocketeer's rocket goes off big (pass 33.3): Game.rocket_blast throws the hero and the crowd
			game.rocket_blast(pos[i], area[i], dmg[i], extra[i].get("info", {}), extra[i].get("blast", {}))
			return
		var player: Node3D = game.player
		if player and not player.dead:
			var d := player.global_position - pos[i]
			d.y = 0.0
			if d.length() <= area[i] + 0.4:
				var einfo: Dictionary = (extra[i].get("info", {}) as Dictionary).duplicate(true)
				(einfo.get("fx", []) as Array).append("rocket blast" if extra[i].has("rocket") else "splash")
				# away from where it came down, by SHOT_KNOCK of its shooter's bite (pass 54)
				if float(extra[i].get("knockback", 0.0)) <= 0.0:
					put_shot_knock(einfo)
				player.take_damage(dmg[i], pos[i], einfo)
		game.fx_burst(pos[i], Color(0.45, 0.75, 0.4), area[i])
		return
	if extra[i] is Dictionary and (extra[i] as Dictionary).has("vortex"):
		# the Singularity: no blast, a black hole that drags and eats and then pops (Vortex); its spot is taken while it lives
		lobs_exploded += 1
		game.spawn_vortex(pos[i], weapon[i], area[i], extra[i]["vortex"], dmg[i])
		_landed.append({"at": pos[i], "t": float((extra[i]["vortex"] as Dictionary).get("seconds", 3.0))})
		return
	var w: WeaponInstance = weapon[i]
	var wid := w.def.id if w else ""
	var before := Run.kills
	lobs_exploded += 1
	if not (extra[i] as Dictionary).has("is_bomblet"):
		_landed.append({"at": pos[i], "t": LANDED_CLAIM})
	enemies.damage_radius(pos[i], area[i], dmg[i], wid, kb[i])
	var element: String = w.element() if w else ""
	if w and element != "":
		# the blast itself carries the element (Thermobaric, Incendiary): everything in it is lit or poisoned at once
		for e in enemies.indices_in_radius(pos[i], area[i]):
			if w.stat("fire_damage", 0.0) > 0.0:
				enemies.ignite(e, wid, w.stat("fire_damage", 4.0), w.stat("fire_duration", 1.8), w.stat("fire_spread", 0.5))
			if w.stat("poison_damage", 0.0) > 0.0:
				weapon_poison(e, w)
	if element != "" and area[i] > 0.3:
		# a poison bomb leaves a cloud, a fire bomb a burning pool; both keep working on whoever stands in them. Methanol
		# (pass 48, params.cloud_mult) spreads its pool wider than the blast
		var cm: float = float(w.params.get("cloud_mult", 1.0)) if w else 1.0
		game.spawn_cloud(pos[i], w, area[i] * cm, element, extra[i])
	# the Moonshine's burning line (pass 48) runs on to where the bottle broke
	if (extra[i] as Dictionary).has("line_from"):
		_lay_line(i, Vector3(pos[i].x, game.map.height_at(pos[i].x, pos[i].z) if game.map else pos[i].y, pos[i].z))
	_burst_spawn(i)
	_bounce_on(i, w)
	if w:
		w.kills += Run.kills - before
		Audio.play(str(w.def.sfx.get("hit", "w_lob_boom")), pos[i])
	# Heavy Warhead (pass 53, params.blast_fx {scale, flash}; Garry: "the visual of the explosion becomes 'stronger'
	# looking"): the burst, its ring and the camera's kick at `scale` of the blast, and a white flash with a ring of hot
	# sparks on top (Fx.burst_strength); the damage radius is the weapon's area, as before
	var bfx = w.params.get("blast_fx") if w else null
	var fx_r: float = area[i]
	var strength := 1.0
	if bfx is Dictionary:
		strength = maxf(float((bfx as Dictionary).get("scale", 1.0)), 1.0)
		fx_r *= strength
	var fx_col: Color = {"poison": Color(0.45, 0.95, 0.35), "fire": Color(1.0, 0.45, 0.15)}.get(element, Color(1.0, 0.7, 0.3))
	game.fx_burst(pos[i], fx_col, fx_r)
	if strength > 1.0 and game.get("fx") != null and game.fx.has_method("burst_strength"):
		game.fx.burst_strength(pos[i], fx_col, fx_r, strength, bool((bfx as Dictionary).get("flash", true)))
	game.camera.shake(0.5)
	# Cluster Munitions (pass 53, params.cluster): the blast may scatter bomblets on the sand round it (Bomblets). The
	# cluster is read off the weapon's params, never the shot's extra (a missile's extra is its flight, so the old
	# `bomblets` key there never reached a rocket); a bomb's own bomblets never cluster
	var cl = w.params.get("cluster") if w else null
	if cl is Dictionary and not (extra[i] as Dictionary).has("is_bomblet") and randf() < float((cl as Dictionary).get("chance", 0.0)):
		if bomblets:
			bomblets.game = game
			bomblets.scatter(w, pos[i], dmg[i], cl)
	var params: Dictionary = extra[i]
	var lobbed := int(params.get("bomblets", 0))
	if lobbed > 0 and not params.has("is_bomblet"):
		# bomblet_size (pass 48, the Golden Pineapple's small golden ones): drawn that share of the bomb
		var bsize: float = psize[i] * float(params.get("bomblet_size", 1.0))
		for k in range(lobbed):
			var a := TAU * k / lobbed
			var target := pos[i] + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 3.5)
			var j := lob(kind[i], pos[i] + Vector3(0, 0.5, 0), target, 6.0, dmg[i] * float(params.get("bomblet_damage_mult", 0.5)), float(params.get("bomblet_area", 1.4)), w, kb[i] * 0.5, {"is_bomblet": true})
			if j >= 0:
				vel[j].y += 4.0
				psize[j] = bsize


## Bouncing Skull (pass 48, params.bounce {count, steer_deg, scale, size, reach_mult, reach_add}): after its blast the
## skull is lobbed on along its throw (throw_dir), turned at most `steer_deg` towards the nearest creature ahead of it,
## to land reach_mult[k] x the first blast's radius + reach_add[k] metres on, past the blast it just made (the first
## bounce farthest). Bounce k blasts and leaves its cloud at scale[k] of the first's radius, and the skull is drawn
## size[k] as big. A bomblet never bounces.
func _bounce_on(i: int, w: WeaponInstance) -> void:
	if w == null or game == null:
		return
	var bo = w.params.get("bounce")
	if not bo is Dictionary:
		return
	var b: Dictionary = bo
	var ex: Dictionary = extra[i]
	if ex.has("is_bomblet") or ex.has("is_burst"):
		return
	var k: int = int(ex.get("bounce_k", 0))
	if k >= int(b.get("count", 0)):
		return
	var a0: float = float(ex.get("bounce_a0", area[i]))
	var dir := Vector3.ZERO
	var td = ex.get("throw_dir")
	if td is Vector3:
		dir = td
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(vel[i].x, 0.0, vel[i].z)
	if dir.length_squared() < 0.0001:
		var ar := randf() * TAU
		dir = Vector3(cos(ar), 0.0, sin(ar))
	dir = dir.normalized()
	var dist: float = a0 * _nth(b.get("reach_mult"), k, 1.6 - 0.4 * float(k)) + _nth(b.get("reach_add"), k, 1.5 - 0.5 * float(k))
	var enemies: EnemyManager = game.enemies
	var steer := deg_to_rad(float(b.get("steer_deg", 30.0)))
	var prey := _ahead(enemies, pos[i], dir, dist + 3.0) if enemies else -1
	if prey >= 0:
		var to: Vector3 = enemies.pos[prey] - pos[i]
		to.y = 0.0
		if to.length_squared() > 0.0001:
			dir = dir.rotated(Vector3.UP, clampf(dir.signed_angle_to(to.normalized(), Vector3.UP), -steer, steer)).normalized()
	var land := pos[i] + dir * dist
	land.y = game.map.height_at(land.x, land.z) if game.map else 0.0
	var lp: Dictionary = ex.duplicate()
	lp.erase("target")
	lp["bounce_k"] = k + 1
	lp["bounce_a0"] = a0
	lp["throw_dir"] = dir
	var j := lob(kind[i], pos[i] + Vector3(0, 0.4, 0), land, BOUNCE_SPEED, dmg[i], a0 * _nth(b.get("scale"), k, 1.0), w, kb[i], lp)
	if j >= 0:
		psize[j] = float(w.params.get("size_mult", 1.0)) * _nth(b.get("size"), k, 1.0)


## Element `k` of an Array param as a float, or `fallback` when it is missing.
static func _nth(arr, k: int, fallback: float) -> float:
	if arr is Array and k >= 0 and k < (arr as Array).size():
		return float(arr[k])
	return fallback


## The nearest creature within `r` of `from` and ahead of it along `dir` (within 90 degrees either side), -1 for none.
func _ahead(enemies: EnemyManager, from: Vector3, dir: Vector3, r: float) -> int:
	var best := -1
	var best_d := r * r
	for e in enemies.indices_in_radius(from, r):
		var to: Vector3 = enemies.pos[e] - from
		to.y = 0.0
		if to.dot(dir) <= 0.0:
			continue
		var d2 := to.length_squared()
		if d2 < best_d:
			best_d = d2
			best = e
	return best


# ---------------------------------------------------------------- pass 61 (lane WP1): the cheap mutation looks
## Pass 61 (Garry: "Mutation Visual, implement every Cheap version"): the shots' side of the looks a mutation brings in
## its params (the behaviours do the guns' side). Kinds in a tint's colours (tinted_kind) or bristling with spikes
## (spiked_kind), thorn specks a rolling shot sheds on the sand (`look.specks`, one pooled MultiMesh), and a light
## blinking on a stuck grenade (`look.blink`, faster towards the blast).

## The kinds made from others, by the words that made them (tinted_kind, spiked_kind).
var _derived := {}
## Thorn specks on the sand: a ring of SPECK_MAX, each a flat three-pointed thorn fading out over its life.
const SPECK_MAX := 192
var _speck_mm: MultiMesh
var _speck_xf: Array = []
var _speck_age := PackedFloat32Array()
var _speck_life := PackedFloat32Array()
var _speck_col := PackedColorArray()
var _speck_next := 0
## specks were drawn on the last tick, or one fell since (the tick has nothing to do otherwise)
var _specks_drawn := 0
var _speck_fell := false
## The stuck grenade's light: one MultiMesh of glow and bulb pairs drawn over everything, at most BLINK_MAX grenades.
const BLINK_MAX := 32
const BLINK_UP := 0.42
const BLINK_HZ0 := 2.5
const BLINK_HZ1 := 13.0
## the glow round a lit bulb: this many times the bulb's size, at this alpha
const BLINK_GLOW := 2.4
const BLINK_GLOW_ALPHA := 0.5
var _blink_mm: MultiMesh
var _blink_list: Array = []
## Diagnostics and tests: blinkers drawn on the last frame, and how many of them were lit.
var blinks_drawn := 0
var blinks_lit := 0


func _build_looks() -> void:
	_speck_xf.resize(SPECK_MAX)
	_speck_age.resize(SPECK_MAX)
	_speck_life.resize(SPECK_MAX)
	_speck_col.resize(SPECK_MAX)
	for k in range(SPECK_MAX):
		_speck_age[k] = 1.0
		_speck_life[k] = 1.0
		_speck_xf[k] = Transform3D()
	_speck_mm = MultiMesh.new()
	_speck_mm.transform_format = MultiMesh.TRANSFORM_3D
	_speck_mm.use_colors = true
	_speck_mm.mesh = _speck_mesh()
	_speck_mm.instance_count = SPECK_MAX
	_speck_mm.visible_instance_count = 0
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = _speck_mm
	# the trail beads' very recipe (unshaded, see-through, vertex colours, back faces culled), so no new shader
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	smi.material_override = sm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(smi)
	_blink_mm = MultiMesh.new()
	_blink_mm.transform_format = MultiMesh.TRANSFORM_3D
	_blink_mm.use_colors = true
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	sp.radial_segments = 10
	sp.rings = 5
	_blink_mm.mesh = sp
	_blink_mm.instance_count = BLINK_MAX * 2
	_blink_mm.visible_instance_count = 0
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = _blink_mm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.vertex_color_use_as_albedo = true
	# a warning light on the creature's back reads over its painting, whatever stands in front
	bm.no_depth_test = true
	bm.render_priority = 4
	bmi.material_override = bm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(bmi)


## A flat thorn speck lying on the sand, a metre across before its size: three thin points from the middle, facing up
## (clockwise seen from above, Godot's front).
static func _speck_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for k in range(3):
		var a := TAU * float(k) / 3.0 + 0.35 * float(k)
		var tip := Vector3(cos(a), 0.0, sin(a)) * (0.5 if k == 0 else 0.36)
		var side := Vector3(-sin(a), 0.0, cos(a)) * 0.07
		var tri := [side, -side, tip]
		# front faces are clockwise seen from where the normal points: the cross of a front face points down
		var cr: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
		if cr.y > 0.0:
			tri = [side, tip, -side]
		for v: Vector3 in tri:
			verts.append(v)
			norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A copy of kind `k` in a tint's colours (pass 61, out of pass 54's ProjectileEmitter.tint_kind so the Lobber shares it:
## Thorny Weed's weed, Dragon's Breath's orange pellets, Toxic Peas, Sticky's resin). The kind's material is duplicated
## with the tint's `albedo` (multiplying a vertex-coloured model's own colours), a glow of `emission` at `energy` (0.35),
## and `roughness` / `metallic` when given; a kind drawn as two surfaces (a cored streak, pass 60) has its core tinted
## and its second surface, the halo, recoloured by `halo` (alpha `halo_alpha`). Made once per kind and tint; the copies
## switch no shader feature on (no clearcoat, no rim), so nothing compiles mid-run. A bad kind or no tint: `k` itself.
func tinted_kind(k: int, tint: Dictionary) -> int:
	if k < 0 or k >= kinds.size() or tint.is_empty():
		return k
	var key := "t%d|%s" % [k, str(tint)]
	if _derived.has(key):
		return int(_derived[key])
	var kd: Dictionary = kinds[k]
	var mesh: Mesh = (kd["mm"] as MultiMesh).mesh
	var over: Material = (kd["mmi"] as MultiMeshInstance3D).material_override
	var out: int
	if over != null or mesh == null or mesh.get_surface_count() <= 1:
		var src: Material = over
		if src == null and mesh and mesh.get_surface_count() > 0:
			src = mesh.surface_get_material(0)
		out = _register_like(kd, mesh, tint_material(src, tint))
	else:
		var copy := ArrayMesh.new()
		for s in range(mesh.get_surface_count()):
			copy.add_surface_from_arrays(_prim(mesh, s), mesh.surface_get_arrays(s))
			var m: Material = mesh.surface_get_material(s)
			if s == 0:
				m = tint_material(m, tint)
			elif tint.has("halo"):
				m = halo_material(m, tint)
			if m:
				copy.surface_set_material(s, m)
		out = _register_like(kd, copy, null)
	_derived[key] = out
	return out


## A kind with kind `kd`'s scale, turn and custom-data flag, drawn with `mesh` and `mat`.
func _register_like(kd: Dictionary, mesh: Mesh, mat: Material) -> int:
	var basis: Basis = kd.get("basis", Basis())
	return register_kind(mesh, mat, float(kd["scale"]) / CHUNK, bool(kd.get("custom", false)), basis)


static func _prim(mesh: Mesh, s: int) -> int:
	return (mesh as ArrayMesh).surface_get_primitive_type(s) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES


## `src` (a StandardMaterial3D, else a new one) in a tint's colours (tinted_kind).
static func tint_material(src: Material, tint: Dictionary) -> StandardMaterial3D:
	var mat: StandardMaterial3D = (src.duplicate() as StandardMaterial3D) if src is StandardMaterial3D else StandardMaterial3D.new()
	if tint.has("albedo"):
		var a := Color(str(tint["albedo"]))
		mat.albedo_color = Color(a.r, a.g, a.b, mat.albedo_color.a)
	if tint.has("emission"):
		mat.emission_enabled = true
		mat.emission = Color(str(tint["emission"]))
		mat.emission_energy_multiplier = float(tint.get("energy", 0.35))
	if tint.has("roughness"):
		mat.roughness = float(tint["roughness"])
	if tint.has("metallic"):
		mat.metallic = float(tint["metallic"])
	return mat


## A streak's halo (its second surface) recoloured: `halo` at `halo_alpha` (else the halo's own alpha).
static func halo_material(src: Material, tint: Dictionary) -> Material:
	if not (src is StandardMaterial3D):
		return src
	var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	var c := Color(str(tint["halo"]))
	mat.albedo_color = Color(c.r, c.g, c.b, float(tint.get("halo_alpha", mat.albedo_color.a)))
	return mat


## Kind `k` bristling with spikes (pass 61, Thorny Weed: "thorn spikes on the tumbleweed"): its mesh, each surface in
## the material it is drawn with, and one more surface of `count` four-sided cones standing out of it round the whole
## ball (a Fibonacci sphere), their feet at `inset` of the mesh's radius, `length` and `base` as shares of that radius,
## in `color` with a glow of `emission` at `energy` (lit and glowing like the shots, so no new shader). Made once per
## kind and words. A bad kind or no words: `k` itself.
func spiked_kind(k: int, spikes: Dictionary) -> int:
	if k < 0 or k >= kinds.size() or spikes.is_empty():
		return k
	var key := "s%d|%s" % [k, str(spikes)]
	if _derived.has(key):
		return int(_derived[key])
	var kd: Dictionary = kinds[k]
	var mesh: Mesh = (kd["mm"] as MultiMesh).mesh
	if mesh == null:
		return k
	var over: Material = (kd["mmi"] as MultiMeshInstance3D).material_override
	var copy := ArrayMesh.new()
	for s in range(mesh.get_surface_count()):
		copy.add_surface_from_arrays(_prim(mesh, s), mesh.surface_get_arrays(s))
		var m: Material = over if over else mesh.surface_get_material(s)
		if m:
			copy.surface_set_material(s, m)
	var n := copy.get_surface_count()
	copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, spike_arrays(mesh.get_aabb(), spikes))
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(str(spikes.get("color", "#2A140A")))
	sm.emission_enabled = true
	sm.emission = Color(str(spikes.get("emission", spikes.get("color", "#2A140A"))))
	sm.emission_energy_multiplier = float(spikes.get("energy", 0.4))
	sm.roughness = 0.6
	copy.surface_set_material(n, sm)
	var out := _register_like(kd, copy, null)
	_derived[key] = out
	return out


## The cones of spiked_kind round a mesh with bounds `aabb` (its middle, the largest half-size as the radius).
static func spike_arrays(aabb: AABB, spikes: Dictionary) -> Array:
	var c := aabb.get_center()
	var r: float = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z) * 0.5
	var count: int = maxi(int(spikes.get("count", 14)), 1)
	var inset: float = float(spikes.get("inset", 0.8))
	var length: float = float(spikes.get("length", 0.5)) * r
	var base: float = float(spikes.get("base", 0.1)) * r
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var golden := PI * (3.0 - sqrt(5.0))
	for k in range(count):
		var y := 1.0 - 2.0 * (float(k) + 0.5) / float(count)
		var ring := sqrt(maxf(1.0 - y * y, 0.0))
		var a := golden * float(k)
		var out := Vector3(cos(a) * ring, y, sin(a) * ring).normalized()
		var foot := c + out * r * inset
		var tip := foot + out * length
		var u := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := out.cross(u).normalized()
		var rim: Array = [foot + u * base, foot + v * base, foot - u * base, foot - v * base]
		for s in range(4):
			var p0: Vector3 = rim[s]
			var p1: Vector3 = rim[(s + 1) % 4]
			var tri := [p0, p1, tip]
			var cr: Vector3 = (p1 - p0).cross(tip - p0)
			var mid: Vector3 = (p0 + p1 + tip) / 3.0 - foot
			# clockwise seen from outside (Godot's front): the cross of a front face points in
			if cr.dot(mid) > 0.0:
				tri = [p0, tip, p1]
				cr = -cr
			var nrm := (-cr).normalized()
			for q: Vector3 in tri:
				verts.append(q)
				norms.append(nrm)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	return arrays


## Thorny Weed's specks (pass 61, `look.specks {every, life, size, color, spread}`): every `every` metres a rolling shot
## covers, one or two thorn specks fall on the sand round its foot (within `spread` of its middle).
func _shed_specks(i: int, w: WeaponInstance, dt: float, ground: float) -> void:
	if w == null:
		return
	var lk = w.params.get("look")
	if not (lk is Dictionary and (lk as Dictionary).get("specks") is Dictionary):
		return
	var sp: Dictionary = lk["specks"]
	var acc: float = float(extra[i]["speck"]) + vel[i].length() * dt
	var every: float = maxf(float(sp.get("every", 0.5)), 0.1)
	if acc < every:
		extra[i]["speck"] = acc
		return
	extra[i]["speck"] = fmod(acc, every)
	var spread := float(sp.get("spread", 0.5))
	var col := Color(str(sp.get("color", "#2A160A")))
	col.a = float(sp.get("alpha", 0.9))
	for k in range(1 + int(randf() < 0.3)):
		var at := Vector3(pos[i].x + randf_range(-spread, spread), ground, pos[i].z + randf_range(-spread, spread))
		drop_speck(at, randf() * TAU, float(sp.get("size", 0.25)) * randf_range(0.8, 1.2), col, float(sp.get("life", 3.5)))


## One speck on the sand at `at` (its foot), turned `yaw`, `size` metres across, laid on the slope, fading over `life`.
func drop_speck(at: Vector3, yaw: float, size: float, col: Color, life: float) -> void:
	if _speck_mm == null:
		return
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(size, size, size))
	var map = game.map if game else null
	var g := at.y
	if map != null:
		g = map.height_at(at.x, at.z)
		if map.has_method("normal_at"):
			b = MapBase.ground_basis(map.normal_at(at.x, at.z)) * b
	_speck_xf[_speck_next] = Transform3D(b, Vector3(at.x, g + 0.04, at.z))
	_speck_age[_speck_next] = 0.0
	_speck_life[_speck_next] = maxf(life, 0.1)
	_speck_col[_speck_next] = col
	_speck_next = (_speck_next + 1) % SPECK_MAX
	_speck_fell = true


## The specks age; the live ones are drawn, each fading over the last third of its life.
func _tick_specks(delta: float) -> void:
	if _speck_mm == null:
		return
	if _specks_drawn == 0 and not _speck_fell and _warm_at == Vector3.INF:
		return
	_speck_fell = false
	var n := 0
	for k in range(SPECK_MAX):
		if _speck_age[k] >= _speck_life[k]:
			continue
		_speck_age[k] += delta
		var f: float = _speck_age[k] / _speck_life[k]
		if f >= 1.0:
			continue
		var c: Color = _speck_col[k]
		_speck_mm.set_instance_transform(n, _speck_xf[k])
		_speck_mm.set_instance_color(n, Color(c.r, c.g, c.b, c.a * clampf((1.0 - f) * 3.0, 0.0, 1.0)))
		n += 1
	if _warm_at != Vector3.INF and n < SPECK_MAX:
		_speck_mm.set_instance_transform(n, Transform3D(Basis(), _warm_at))
		_speck_mm.set_instance_color(n, Color(0, 0, 0, 0.5))
		n += 1
	_speck_mm.visible_instance_count = n
	_specks_drawn = n


## How many specks lie on the sand now (tests; never more than SPECK_MAX).
func speck_count() -> int:
	var n := 0
	for k in range(SPECK_MAX):
		if _speck_age[k] < _speck_life[k]:
			n += 1
	return n


func clear_specks() -> void:
	for k in range(SPECK_MAX):
		_speck_age[k] = _speck_life[k]
	if _speck_mm:
		_speck_mm.visible_instance_count = 0


## How fast stuck shot `i`'s light blinks: BLINK_HZ0 as it sticks rising to BLINK_HZ1 as it blows (or `look.blink`'s own
## `hz0`/`hz1`), so the last beats come quick.
func blink_hz(i: int) -> float:
	var w: WeaponInstance = weapon[i]
	var bl: Dictionary = {}
	if w and w.params.get("look") is Dictionary and (w.params["look"] as Dictionary).get("blink") is Dictionary:
		bl = w.params["look"]["blink"]
	var t0: float = float(extra[i].get("blink_t0", 1.0))
	var f: float = clampf(1.0 - stuck_t[i] / t0, 0.0, 1.0)
	return lerpf(float(bl.get("hz0", BLINK_HZ0)), float(bl.get("hz1", BLINK_HZ1)), f * f)


## Whether stuck shot `i`'s light is on (the first half of every beat).
func blink_on(i: int) -> bool:
	return fmod(float(extra[i].get("blink", 0.0)), 1.0) < 0.5


## The lights on the stuck grenades listed by _render: a soft red glow (only while lit, swelling) under a bulb (bright
## red lit, dark red between beats), a little over where the grenade rides, drawn over the creature's painting.
func _render_blinks() -> void:
	if _blink_mm == null:
		return
	var n := 0
	var lit := 0
	var shown := 0
	for i: int in _blink_list:
		if shown >= BLINK_MAX:
			break
		var w: WeaponInstance = weapon[i]
		var bl: Dictionary = {}
		if w and w.params.get("look") is Dictionary and (w.params["look"] as Dictionary).get("blink") is Dictionary:
			bl = w.params["look"]["blink"]
		var col := Color(str(bl.get("color", "#FF2A14")))
		var size := float(bl.get("size", 0.2)) * (0.6 if (extra[i] as Dictionary).has("is_bomblet") else 1.0)
		var at: Vector3 = pos[i] + Vector3(0, BLINK_UP * (0.6 if (extra[i] as Dictionary).has("is_bomblet") else 1.0), 0)
		var on := blink_on(i)
		if on:
			var g: float = size * BLINK_GLOW
			_blink_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(g, g, g)), at))
			_blink_mm.set_instance_color(n, Color(col.r, col.g, col.b, BLINK_GLOW_ALPHA))
			n += 1
			lit += 1
		var bc := col if on else Color(col.r * 0.35, col.g * 0.25, col.b * 0.25)
		bc = bc.lightened(0.35) if on else bc
		_blink_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(size, size, size)), at))
		_blink_mm.set_instance_color(n, Color(bc.r, bc.g, bc.b, 1.0))
		n += 1
		shown += 1
	_blink_list.clear()
	if _warm_at != Vector3.INF and n < BLINK_MAX * 2:
		_blink_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(0.1, 0.1, 0.1)), _warm_at))
		_blink_mm.set_instance_color(n, Color(1, 0, 0, 0.5))
		n += 1
	_blink_mm.visible_instance_count = n
	blinks_drawn = shown
	blinks_lit = lit


## The warm-up's speck and blinker (warm_draw): drawn by their ticks while `_warm_at` is set, gone when it is not.
func _warm_looks(_at: Vector3) -> void:
	_tick_specks(0.0)
	_render_blinks()


## Warm-up: one instance of every kind at `at` (Vector3.INF stops it), so the instanced shader variants compile early.
var _warm_at := Vector3.INF


func warm_draw(at: Vector3) -> void:
	_warm_at = at
	if at != Vector3.INF:
		# Frag's spikes (pass 47) are drawn by their own kind: registered here so its material compiles behind the beam
		shrapnel_kind()
	for kd in kinds:
		var mm: MultiMesh = kd["mm"]
		if at == Vector3.INF:
			mm.visible_instance_count = 0
		else:
			mm.set_instance_transform(0, Transform3D(Basis(), at))
			if bool(kd.get("custom", false)):
				mm.set_instance_custom_data(0, Color(0.0, 0.0, 0.0, 0.0))
			mm.visible_instance_count = 1
	if at != Vector3.INF:
		_drop_trail(at)
	# pass 61: the thorn specks' and the stuck grenade's blinker's MultiMeshes, one instance each (the blinker's no-depth
	# material is a variant of its own)
	_warm_looks(at)


## The basis shot `i` is drawn with (pass 53, out of _render so a test can read it: the headless renderer keeps no
## instance transform to read back): looking down its flight (a planted spear keeps its stance), spun, at its kind's
## scale times its own size, and then the kind's own turn inside that frame (a capsule lying along -Z flies nose first).
func draw_basis(i: int) -> Basis:
	var kd: Dictionary = kinds[kind[i]]
	var s: float = kd["scale"]
	var bs := Basis()
	var v := vel[i]
	if hostile[i] == 0 and extra[i].has("planted"):
		bs = extra[i]["planted"]
	elif v.length_squared() > 0.01:
		var fwd := v.normalized()
		var up := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		bs = Basis.looking_at(fwd, up)
	if extra[i].has("roll"):
		# a rolling shot (pass 45; the hero's tumbleweeds too since pass 55) turns about the axis across its travel (a
		# wheel, its top going the way it flies), not along it
		bs = bs.rotated(bs.x, -spin[i]).scaled(Vector3(s, s, s) * psize[i])
	else:
		bs = bs.rotated(bs.z, spin[i]).scaled(Vector3(s, s, s) * psize[i])
	if bool(kd.get("turned", false)):
		bs = bs * (kd["basis"] as Basis)
	return bs


func _render() -> void:
	var counters := PackedInt32Array()
	counters.resize(kinds.size())
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var k := kind[i]
		if k < 0 or k >= kinds.size():
			continue
		var kd: Dictionary = kinds[k]
		var mm: MultiMesh = kd["mm"]
		var n: int = counters[k]
		mm.set_instance_transform(n, Transform3D(draw_basis(i), pos[i]))
		# only a kind built with custom data may be handed any (the rocket's heat, pass 45)
		if bool(kd.get("custom", false)):
			mm.set_instance_custom_data(n, Color(glow[i], 0.0, 0.0, 0.0))
		counters[k] = n + 1
		if stuck[i] >= 0 and extra[i].has("blink"):
			_blink_list.append(i)
	_render_blinks()
	for k in range(kinds.size()):
		if _warm_at != Vector3.INF:
			kinds[k]["mm"].set_instance_transform(counters[k], Transform3D(Basis(), _warm_at))
			if bool(kinds[k].get("custom", false)):
				kinds[k]["mm"].set_instance_custom_data(counters[k], Color(0.0, 0.0, 0.0, 0.0))
			counters[k] += 1
		kinds[k]["mm"].visible_instance_count = counters[k]

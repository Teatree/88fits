## Fires projectiles. Targeting: nearest, random, or forward cone (Boomstick style). Every mode auto-aims: a forward
## weapon points its cone at the nearest enemy in range and fires nothing when nothing is near (pass 53, Garry: "Boomstick
## seems to be firing all the time, this should only happen after it's Evolved"), unless `params.fire_blind` says it
## blasts on its clock whoever is there (the Blunderbuss).
## The visual scene may carry a "Held" node (a gun at the hero's hip, forward weapons) or a "Familiar" node
## (a little companion that circles the hero and fires from where it is; child nodes "WingL"/"WingR" flap).
## Familiar tuning is data: params.familiar = {"radius": 1.25, "height": 1.35, "speed": 1.4, "bob": 0.12}.
## A burst (params.burst) leaves a round every `burst_gap` seconds (0.05), each scattered up to `scatter_deg` (else the
## volley's spread, at least 5 degrees); the companion's "Drum" turns `drum_step` radians a round about its sideways
## axis, or about the barrel with `drum_axis` "forward" (the Revolver's cylinder, pass 35); `no_shells` keeps the casings
## in (a revolver). A volley fans its shots `fan_step_deg` (8) apart (pass 46: the Spear Volley's three spread wider); a
## shot's own params (`no_spin`, `plant`, `pin`, `trail_zone`: the Spear) are the ProjectileManager's.
## A weapon with `params.aura` (pass 53: the Tumbleweed's Dust Wake, the Dust Devil) draws the visual's "Ring" node under
## every one of its shots in flight, laid on the ground at the aura's radius and turning (_tick_rings); the slow itself
## is the ProjectileManager's.
## Pass 48: "priority" targeting aims at the strong and the close (WeaponBehavior.aim_index) on every aim: the pull, the
## gun tracking between shots, the companion's own line and every round of a burst. `params.blast` (Birdshot's lane, the
## Blunderbuss's cone) hits everything in its shape at once (_blast) with pellets streaking through it only for the eye;
## `double_every` fires that pull twice: the second barrel `double_gap` seconds after the first (pass 51), aimed afresh
## with its own flash, kick and bang (both at once read as one bigger shot). `size_mult`/`radius_mult` make the shot bigger and its hit wider (Big Peas, the
## Silver Bullet), `speed_mult` faster; `tint {albedo, emission, energy}` (pass 54, Thorny Weed) draws the shots in a
## copy of the visual's kind in those colours (tint_kind); `silver` turns the rounds, their tracer and the muzzle flash pale blue with a
## harder kick and a small camera kick a shot. `hip_shot {every, volleys, gap}`: every `every`th pull fires `volleys`
## volleys `gap` seconds apart, each the whole amount at once, and then the companion twirls a full turn.
## Pass 67 (the basketball): `amount_mode` "bounces" throws one ball whose amount past the first is that many more hops
## (_throw_ball); with `catch` Game hands the ball back here when it reaches his hand (on_caught: the refund, Heat, Slam
## Dunk's dunk), a hit on his health cools Heat (on_hero_hit) and `free_throw` throws on an evade (on_hero_evaded).
## Pass 75 (the Revolver; Garry: "The shots still feel sluggish and jerky ... a little spin every now and then right after
## firing a shot ... much more visible impact on the revolver every time it shoots ... a bigger punch"): a companion whose
## `params.familiar` carries `kick {back, climb, twist, pop, hz, decay}` punches on every round (it slides back along its
## barrel, the muzzle climbs, it twists a little to one side and swells, then springs back past rest and settles), shown
## on the frame the round leaves and never smoothed by the eased follow (which carries only the orbit); it aims along its
## own line to the target between shots, so a shot no longer jerks it off the hero's line. `spin {chance, seconds, turns,
## gap, hop, axis}`: after the last round of a pull, now and then (never twice within `gap` seconds, only when the twirl
## ends before the next pull), it twirls about its trigger guard with a little hop. Guns without them are as before.
class_name ProjectileEmitter
extends WeaponBehavior

## The pale gold a blast's lane or cone washes the sand with (pass 48).
const BLAST_WASH := Color(1.0, 0.93, 0.68)
## Seconds the companion's twirl after a hip shot takes, and how hard a silver round kicks.
const HIP_SPIN := 0.35
const SILVER_RECOIL := 1.7
const SILVER_SHAKE := 0.12
## Pass 75: a punchy companion's kick and trick spin when its `familiar.kick` / `familiar.spin` leave a number out.
const KICK_DEFAULTS := {"back": 0.3, "climb": 0.5, "twist": 0.12, "pop": 0.25, "hz": 3.2, "decay": 9.0}
const SPIN_DEFAULTS := {"chance": 0.3, "seconds": 0.5, "turns": 1.0, "gap": 2.0, "hop": 0.15, "axis": "x"}
## A kick on a gun still settling from the last one adds half of what is left, up to this many kicks' worth; a silver
## round's kick is SILVER_PUNCH kicks (the old recoil's 1.7 would swell the gun by half and flip it past 50 degrees).
const KICK_STACK_MAX := 2.2
const SILVER_PUNCH := 1.3

var _held: Node3D
var _familiar: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _drum: Node3D          # a drum magazine on the companion gun turns a notch per round
var _recoil := 0.0
var _aim_yaw := 0.0
var _aim_dir := Vector3.ZERO
var _orbit := 0.0
var _flap := 0.0
# params.burst: the shots of one trigger pull leave one after another (a submachine gun) instead of all at once
var _burst: Array = []   # pending shots: {from, dir, speed, damage, pierce, prad, life, knock, spread}
var _burst_t := 0.0
var _stream_gap := 0.0   # pass 69 (lane HERO, May's Trigger Happy): params.stream spreads a burst over the whole cooldown
var _shots := 0          # trigger pulls, for Both Barrels (every Nth fires twice) and Hip Shot (every Nth)
## Both Barrels (pass 51, Garry: "it's actual 2 shots in quick succession"): seconds until the second barrel of a pull
## that fires twice (-1: none waiting), DOUBLE_GAP unless params.double_gap says otherwise; and how many have gone (tests)
const DOUBLE_GAP := 0.15
var _barrel_t := -1.0
var second_barrels := 0
var _taps := 0           # Fan the Hammer: extra volleys still to fire after this one
var _tap_t := 0.0
var _tap_mult := 1.0
# Hip Shot (pass 48): volleys still to fire, the clock to the next, their gap; the twirl's clock (< 0: none)
var _hip_left := 0
var _hip_t := 0.0
var _hip_gap := 0.12
var _spin_t := -1.0
# pass 75: the running twirl's length (a hip shot's HIP_SPIN or a trick spin's seconds) and whether it is a trick spin
var _spin_len := HIP_SPIN
var _spin_trick := false
var _since_spin := 0.0
var _force_spin := false
## Trick spins so far (tests, captures).
var trick_spins := 0
# pass 75: a punchy companion's place on its orbit without the kick, the kick's clock (< 0: at rest), its size, its side
var _fam_base := Vector3.ZERO
var _fam_base_set := false
var _punch_t := -1.0
var _punch_amp := 0.0
var _twist_sign := 1.0
# the Silver Bullet's pale blue rounds (a kind of their own, made the first time) and muzzle flash
var _silver_kind := -1
var _muzzle_silver := false
## Diagnostics and tests (pass 48): blasts fired, hip-shot volleys fired.
var blasts := 0
var hip_volleys := 0
## Pass 67 (the basketball), for tests and the arena: balls thrown, caught (on_caught), dunks (catch.slam), free throws
## (Free Throw); the free throw's gap (seconds until the next may go), and while one is thrown its damage share and look.
var throws := 0
var catches := 0
var dunks := 0
var free_throws := 0
var _free_t := 0.0
var _free_mult := 1.0
var _free_throw := false
## The dust ring under every live shot of a weapon with an aura (pass 53, Garry on the Tumbleweed's Dust Wake: "each
## Tumbleweed has a small aura around it ... the area of effect is not huge"): the visual's "Ring" node (its merged dashes)
## drawn once per shot by one MultiMesh, flat on the sand at `params.aura.radius`, turning RING_SPIN radians a second.
const RING_MAX := 64
const RING_SPIN := 2.2
var _ring_mm: MultiMesh
var _ring_spin := 0.0


## The tracked creature between shots (pass 48): picked every TRACK_EVERY seconds, the gun turning to it in between.
const TRACK_EVERY := 0.1
var _track_i := -1
var _track_cd := 0.0

func _shows_held() -> bool:
	return inst.def.targeting == "forward"


func _on_setup() -> void:
	_held = visual.get_node_or_null("Held")
	_familiar = visual.get_node_or_null("Familiar")
	if _familiar:
		_wing_l = _familiar.get_node_or_null("WingL")
		_wing_r = _familiar.get_node_or_null("WingR")
		_drum = _familiar.find_child("Drum", true, false)
		_orbit = randf() * TAU
		_place_familiar(0.0)
	_setup_ring()
	# pass 69: a ball that shows its Heat has its heat copy made now, so the warm-up behind the spawn beam compiles it
	if not heat_look().is_empty():
		_ball_kind(_kind())


## The ring under the shots (pass 53): one MultiMesh of the visual's "Ring" mesh, for a weapon whose params carry an `aura`;
## the node itself is never shown.
func _setup_ring() -> void:
	var ring := visual.get_node_or_null("Ring") as Node3D
	if ring == null:
		return
	ring.visible = false
	if not (inst.params.get("aura") is Dictionary):
		return
	var src: MeshInstance3D = null
	for c in ring.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).mesh:
			src = c
			break
	if src == null:
		return
	_ring_mm = MultiMesh.new()
	_ring_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ring_mm.mesh = src.mesh
	_ring_mm.instance_count = RING_MAX
	_ring_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _ring_mm
	mmi.material_override = src.material_override if src.material_override else src.mesh.surface_get_material(0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.top_level = true
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)


## Every live shot of this weapon (never a blast's ghost pellets) gets a ring on the ground under it, all turning together.
func _tick_rings(delta: float) -> void:
	if _ring_mm == null:
		return
	_ring_spin = fmod(_ring_spin + delta * RING_SPIN, TAU)
	var pm: ProjectileManager = game.projectiles
	var aura = inst.params.get("aura", {})
	var r: float = float((aura as Dictionary).get("radius", 1.0)) if aura is Dictionary else 1.0
	var basis := Basis(Vector3.UP, _ring_spin).scaled(Vector3(r, 1.0, r))
	var map = game.get("map")
	var n := 0
	for j in range(ProjectileManager.MAX):
		if n >= RING_MAX:
			break
		if pm.alive[j] == 0 or pm.weapon[j] != inst:
			continue
		var ex = pm.extra[j]
		if ex is Dictionary and (ex as Dictionary).has("ghost"):
			continue
		var p: Vector3 = pm.pos[j]
		var g: float = map.height_at(p.x, p.z) if map != null else p.y - 0.5
		_ring_mm.set_instance_transform(n, Transform3D(basis, Vector3(p.x, g + 0.06, p.z)))
		n += 1
	_ring_mm.visible_instance_count = n


## How many rings are drawn right now (tests).
func ring_count() -> int:
	return _ring_mm.visible_instance_count if _ring_mm else 0


func _familiar_param(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


## The shots' speed: the sheet's, times `speed_mult` (pass 48, the Silver Bullet's, never written on a card).
func _speed() -> float:
	return stat("speed", 14.0) * float(inst.params.get("speed_mult", 1.0))


## How wide a shot hits: params.radius, times `radius_mult` (pass 48: Big Peas, the Silver Bullet, the Pea Cannon).
func _prad() -> float:
	return float(inst.params.get("radius", 0.25)) * float(inst.params.get("radius_mult", 1.0))


func _silver() -> bool:
	return bool(inst.params.get("silver", false))


## The kind a shot is drawn with: the visual's, the Silver Bullet's pale blue copy of it, or (pass 54) a copy in a
## mutation's own colours (`params.tint`, tint_kind: Thorny Weed's darker weed, pass 61 Dragon's Breath's orange
## pellets and Toxic Peas' sickly green); pass 61: bristling with `look.spikes` (Thorny Weed's thorns,
## ProjectileManager.spiked_kind) on top of that.
func _kind() -> int:
	# worked out again only when the weapon's params are a new fold (every rebuild makes a new dictionary), so a volley
	# does not turn its tint and thorns into keys every pull
	if _kind_cache >= 0 and is_same(inst.params, _kind_params):
		return _kind_cache
	var k := _colour_kind()
	var sp = look().get("spikes")
	if sp is Dictionary and k >= 0 and game.projectiles.has_method("spiked_kind"):
		k = game.projectiles.spiked_kind(k, sp)
	_kind_cache = k
	_kind_params = inst.params
	return k


var _kind_cache := -1
var _kind_params = null


func _colour_kind() -> int:
	if not _silver():
		var tint = inst.params.get("tint")
		if tint is Dictionary:
			return tint_kind(tint)
		return projectile_kind
	if _silver_kind < 0:
		var pm: ProjectileManager = game.projectiles
		if projectile_kind < 0 or projectile_kind >= pm.kinds.size():
			return projectile_kind
		var kd: Dictionary = pm.kinds[projectile_kind]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.86, 0.94, 1.0)
		mat.emission_enabled = true
		mat.emission = ProjectileManager.SILVER
		mat.emission_energy_multiplier = 2.2
		_silver_kind = pm.register_kind((kd["mm"] as MultiMesh).mesh, mat, float(kd["scale"]) / ProjectileManager.CHUNK)
	return _silver_kind


## A copy of the visual's kind in its own colours (pass 54, `params.tint {albedo, emission, energy}`: Thorny Weed's
## darker brown with pale warm tips): the shot's material duplicated with that albedo and a glow of `emission` at
## `energy`, registered the first time and kept by the tint's words, so a mutation picked later gets its own copy.
## Pass 61: made by ProjectileManager.tinted_kind (the Lobber's resin shares it), which also takes `roughness`,
## `metallic` and, on a cored streak, `halo` for the glow round the core (Dragon's Breath's orange pellets).
func tint_kind(tint: Dictionary) -> int:
	# pass 69 (the ball): `body` paints a vertex-coloured model flat in that colour, and the seams (`seams`, else plain dark
	# ones) are drawn again in their own (ProjectileManager.seam_kind): Alley-Oop's dark blue ball, Slam Dunk's black one
	var t := tint
	if tint.has("body"):
		t = tint.duplicate(true)
		t["albedo"] = tint["body"]
		t["vertex_colors"] = false
	var k: int = game.projectiles.tinted_kind(projectile_kind, t)
	var sm = tint.get("seams")
	if sm == null and tint.has("body"):
		sm = {}
	if sm is Dictionary and game.projectiles.has_method("seam_kind"):
		k = game.projectiles.seam_kind(k, sm)
	return k


## A round leaves: the companion kicks back (harder for a silver round, with a small camera kick), and the muzzle flash
## takes the round's colour.
func _kick() -> void:
	var silver := _silver()
	_recoil = SILVER_RECOIL if silver else 1.0
	if _familiar and not _fam_dict("kick").is_empty():
		_start_punch(silver)
	if silver:
		var cam = game.get("camera")
		if cam != null and cam.has_method("shake"):
			cam.shake(SILVER_SHAKE)
		# a silver round rings over the gun's own shot (pass 48)
		if _familiar:
			Audio.play("w_silver_fire", _familiar.global_position)
	if silver != _muzzle_silver:
		_muzzle_silver = silver
		var m := visual.get_node_or_null("Muzzle") as GeometryInstance3D
		if m:
			if silver:
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = ProjectileManager.SILVER
				mat.emission_enabled = true
				mat.emission = ProjectileManager.SILVER
				mat.emission_energy_multiplier = 2.2
				m.material_override = mat
			else:
				m.material_override = null


func _place_familiar(delta: float) -> void:
	var r := _familiar_param("radius", 1.25)
	var h := _familiar_param("height", 1.35)
	var bob := _familiar_param("bob", 0.12)
	_orbit += delta * _familiar_param("speed", 1.4)
	var t := Run.rule_seconds()  # pass 77 (lane SIMRUN): real time in play, the run's clock in a run sim
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 3.1) * bob, sin(_orbit) * r)
	if not _fam_dict("kick").is_empty():
		# pass 75: the eased follow carries only the orbit, and the kick rides on top of it unsmoothed (the follow had
		# swallowed nearly all of the old 10 cm jump back)
		_fam_base = want if (delta <= 0.0 or not _fam_base_set) else _fam_base.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
		_fam_base_set = true
		_pose_punch()
	else:
		# recoil: the gun jumps back along its own barrel and the muzzle climbs, then settles
		var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
		want -= aim * 0.1 * _recoil
		# eased follow, so a sprinting hero drags the companion behind him a little
		_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
		_familiar.rotation.y = _aim_yaw
		# a hip shot's twirl (pass 48): one full turn over the trigger guard, quick out and easing in
		var twirl := 0.0
		if _spin_t >= 0.0:
			var f: float = clampf(_spin_t / _spin_len, 0.0, 1.0)
			twirl = TAU * (1.0 - (1.0 - f) * (1.0 - f))
		_familiar.rotation.x = -0.28 * _recoil - twirl
		# params.familiar.roll lays a flat gun on its side, so the camera overhead sees its profile
		_familiar.rotation.z = sin(t * 2.3) * 0.08 + _familiar_param("roll", 0.0)
	_flap += delta * 20.0
	var wing := 0.35 + absf(sin(_flap)) * 0.55
	if _wing_l:
		_wing_l.rotation.z = wing
	if _wing_r:
		_wing_r.rotation.z = -wing


## Whether the companion is twirling after a hip shot.
func spinning() -> bool:
	return _spin_t >= 0.0


## Pass 75: one of the companion's own blocks (`familiar.kick`, `familiar.spin`), or {} when it has none.
func _fam_dict(key: String) -> Dictionary:
	var f = inst.params.get("familiar", {})
	if f is Dictionary:
		var d = (f as Dictionary).get(key)
		if d is Dictionary:
			return d
	return {}


## Pass 75: a number of the kick (`familiar.kick`), else KICK_DEFAULTS'.
func _kick_value(key: String) -> float:
	return float(_fam_dict("kick").get(key, KICK_DEFAULTS[key]))


## Pass 75: how far into its kick the companion is now: 1 on the frame the round leaves, then a spring settling back past
## rest (the barrel swings forward of it for a moment) to 0: amp x e^(-decay t) x cos(2 pi hz t). 0 at rest.
func punch() -> float:
	if _punch_t < 0.0:
		return 0.0
	return _punch_amp * exp(-_kick_value("decay") * _punch_t) * cos(TAU * _kick_value("hz") * _punch_t)


## Pass 75: a round leaves a punchy companion: the kick starts over from where the last one has got to (a burst's rounds
## stack, KICK_STACK_MAX at most; a silver round kicks SILVER_PUNCH times as hard), to a side picked at random, and the
## gun takes the pose at once, on the frame the round leaves.
func _start_punch(silver: bool) -> void:
	var left := maxf(punch(), 0.0)
	_punch_amp = minf((SILVER_PUNCH if silver else 1.0) + left * 0.5, KICK_STACK_MAX)
	_punch_t = 0.0
	_twist_sign = -1.0 if randf() < 0.5 else 1.0
	if _fam_base_set:
		_pose_punch()


## Pass 75: the punchy companion's pose: its orbit place, pushed back along its barrel by the kick and lifted by a trick
## spin's hop; its aim, plus the kick's muzzle climb and side twist and the twirl (about the trigger guard, or flat with
## `spin.axis` "y"); a slow wobble about the barrel; swollen by the kick's `pop` (and a little thin past rest).
func _pose_punch() -> void:
	var p := punch()
	var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
	var t := Run.rule_seconds()  # pass 77 (lane SIMRUN): real time in play, the run's clock in a run sim
	var pitch := _kick_value("climb") * p
	var yaw := _aim_yaw + _kick_value("twist") * _twist_sign * p
	var lift := 0.0
	if _spin_t >= 0.0:
		var f: float = clampf(_spin_t / _spin_len, 0.0, 1.0)
		if _spin_trick:
			var sp := _fam_dict("spin")
			# a flick: fast out of the hand, slowing as it comes round to be caught
			var turn := TAU * float(sp.get("turns", SPIN_DEFAULTS["turns"])) * (1.0 - pow(1.0 - f, 3.0))
			lift = float(sp.get("hop", SPIN_DEFAULTS["hop"])) * sin(PI * f)
			if str(sp.get("axis", SPIN_DEFAULTS["axis"])) == "y":
				yaw += turn
			else:
				pitch -= turn
		else:
			# a hip shot's twirl (pass 48)
			pitch -= TAU * (1.0 - (1.0 - f) * (1.0 - f))
	_familiar.global_position = _fam_base - aim * _kick_value("back") * p + Vector3(0, lift, 0)
	_familiar.rotation = Vector3(pitch, yaw, sin(t * 2.3) * 0.08 + _familiar_param("roll", 0.0))
	_familiar.scale = Vector3.ONE * maxf(1.0 + _kick_value("pop") * p, 0.5)


## Pass 75 (`familiar.spin`): after the last round of a pull, now and then a trick spin: `chance` a pull, never within
## `gap` seconds of the last, and only when it ends before the next pull (a whole cooldown away when this is the pull's
## own round, else what is left of the weapon's clock), never during a hip shot. The twirl is heard (the hip shot's sound).
func _maybe_trick_spin() -> void:
	var sp := _fam_dict("spin")
	if sp.is_empty() or _familiar == null or _spin_t >= 0.0 or _hip_left > 0:
		return
	var secs := maxf(float(sp.get("seconds", SPIN_DEFAULTS["seconds"])), 0.1)
	if not _force_spin:
		var next := cooldown_left if cooldown_left > 0.0 else maxf(stat("cooldown", 1.0), 0.05)
		if _since_spin < float(sp.get("gap", SPIN_DEFAULTS["gap"])) or next < secs + 0.05:
			return
		if randf() >= float(sp.get("chance", SPIN_DEFAULTS["chance"])):
			return
	_force_spin = false
	_spin_t = 0.0
	_spin_len = secs
	_spin_trick = true
	_since_spin = 0.0
	trick_spins += 1
	Audio.play("w_hip_spin", _familiar.global_position)


## Pass 75: the next pull ends in a trick spin whatever the dice say (captures, tests).
func debug_force_spin() -> void:
	_force_spin = true


func _fire_burst_shot() -> void:
	if _burst.is_empty():
		return
	var b: Dictionary = _burst.pop_front()
	var dir: Vector3 = _aim_dir if _aim_dir.length_squared() > 0.0001 else player.forward()
	if _stream_gap > 0.0:
		dir = _stream_dir()
	if _familiar:
		# every round aims from where the companion is now (pass 35: it circles a metre off the hero, and the hero's line
		# to the target sent a tight round, the Revolver's, a metre wide of it)
		dir = _from_familiar(dir)
	# Sweep Fire: the rounds walk across a fan instead of scattering
	var d: Vector3 = dir.rotated(Vector3.UP, float(b["angle"])) if b.has("angle") else dir.rotated(Vector3.UP, randf_range(-float(b["spread"]), float(b["spread"])))
	var punchy := _familiar != null and not _fam_dict("kick").is_empty()
	var from: Vector3 = ((_fam_base if punchy else _familiar.global_position) + dir * 0.45) if _familiar else player.aim_origin(dir)
	game.projectiles.fire(_kind(), from, d * float(b["speed"]), float(b["damage"]), int(b["pierce"]), float(b["prad"]), float(b["life"]), inst, float(b["knock"]))
	if _familiar:
		if punchy:
			# pass 75: the barrel lies along the round as it leaves (the kick then throws it back from there)
			_aim_yaw = atan2(-dir.x, -dir.z)
		# every round: a kick, the drum turns a notch, a casing flies out to the right
		_kick()
		_turn_drum()
		if not bool(inst.params.get("no_shells", false)):
			game.fx.shell(_familiar.global_position + Vector3(0, 0.05, 0), dir.rotated(Vector3.UP, -PI * 0.5))
		if _burst.is_empty():
			# pass 75: the pull's last round; now and then a trick spin
			_maybe_trick_spin()
	muzzle_flash(from, d)


## The companion's drum turns a notch: a drum magazine about the axis running sideways through the gun, a revolver's
## cylinder about the barrel.
func _turn_drum() -> void:
	if _drum:
		var axis := Vector3.FORWARD if str(inst.params.get("drum_axis", "")) == "forward" else Vector3.RIGHT
		_drum.rotate_object_local(axis, float(inst.params.get("drum_step", 0.5)))


## Pass 69 (lane HERO, May's Trigger Happy, `params.stream`): a burst's rounds spread evenly over the whole cooldown, so
## the gun never pauses (the last round leaves just before the next pull).
static func stream_gap(cooldown: float, amount: int) -> float:
	return maxf(cooldown, 0.05) * 0.97 / float(maxi(amount, 1))


## Where a streamed round goes (pass 69): at the creature the gun would aim at now, else along the hero's facing (a
## stream with nobody in range follows where she runs; `fire_without_target`).
func _stream_dir() -> Vector3:
	var t := aim_index(player.global_position, stat("range", 9.0))
	if t < 0:
		return player.forward()
	var d: Vector3 = game.enemies.pos[t] - player.global_position
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else player.forward()


func _tick(_delta: float) -> void:
	_tick_rings(_delta)
	_tick_looks(_delta)
	_tick_heat_look(_delta)
	if _free_t > 0.0:
		_free_t -= _delta
	if not _burst.is_empty():
		_burst_t -= _delta
		if _burst_t <= 0.0:
			_burst_t = (_burst_t + _stream_gap) if _stream_gap > 0.0 else float(inst.params.get("burst_gap", 0.05))
			_fire_burst_shot()
	if _barrel_t >= 0.0:
		_barrel_t -= _delta
		if _barrel_t < 0.0:
			_second_barrel()
	if _taps > 0:
		_tap_t -= _delta
		if _tap_t <= 0.0:
			_taps -= 1
			_tap_t = 0.09
			_volley(_tap_mult)
	if _hip_left > 0:
		_hip_t -= _delta
		if _hip_t <= 0.0:
			_hip_volley()
	if _spin_t >= 0.0:
		_spin_t += _delta
		if _spin_t >= _spin_len:
			_spin_t = -1.0
			_spin_trick = false
	_since_spin += _delta
	if _punch_t >= 0.0:
		_punch_t += _delta
		# settled once the spring has lost all but 1 % of its swing
		if exp(-_kick_value("decay") * _punch_t) < 0.01:
			_punch_t = -1.0
	if (_held and _held.visible) or _familiar:
		# the held gun (or the companion) tracks its target between shots, so it points where the shots go: the nearest,
		# or the strong and the close for a priority weapon (pass 48)
		var enemies: EnemyManager = game.enemies
		var hero := player.global_position
		# the creature the gun tracks is picked again ten times a second, not every frame (pass 48: a priority aim weighs
		# most of the crowd, and every gun asked every frame), and dropped at once when it falls
		_track_cd -= _delta
		if _track_cd <= 0.0 or _track_i < 0 or enemies.alive[_track_i] == 0 or enemies.state[_track_i] == EnemyManager.STATE_DYING:
			_track_cd = TRACK_EVERY
			if inst.def.targeting == "healthy":
				# pass 73 (lane SNIPER): a special, an Elite or the boss within reach first
				_track_i = priority_pick(hero, stat("range", 9.0))
				if _track_i < 0:
					_track_i = enemies.nearest_index(hero, stat("range", 9.0), inst.element())
				if _track_i < 0:
					_track_i = enemies.nearest_index(hero, stat("range", 9.0))
			else:
				_track_i = aim_index(hero, stat("range", 9.0))
		var t := _track_i
		var want: Vector3 = (enemies.pos[t] - hero) if t >= 0 else player.forward()
		if t >= 0 and _familiar and _fam_base_set and not _fam_dict("kick").is_empty():
			# pass 75: a punchy companion points along its own line to the target, the line its rounds fly (the hero's
			# line, up to some 15 degrees off it, made every shot jerk the gun round and drift back)
			want = enemies.pos[t] - _fam_base
		want.y = 0.0
		if want.length_squared() > 0.0001:
			_aim_yaw = lerp_angle(_aim_yaw, atan2(-want.x, -want.z), clampf(_delta * 12.0, 0.0, 1.0))
	if _held and _held.visible:
		_held.global_position = player.hip.global_position
		_held.rotation.y = _aim_yaw
		# small recoil settle
		_held.scale = _held.scale.lerp(Vector3.ONE, _delta * 10.0)
	if _familiar:
		_recoil = maxf(_recoil - _delta * 9.0, 0.0)
		_place_familiar(_delta)
		if _fam_dict("kick").is_empty():
			_familiar.scale = _familiar.scale.lerp(Vector3.ONE, _delta * 10.0)


## The way from the companion to creature `t` (the gun's own line of fire), else to the one it would aim at now
## (aim_index: the nearest, or the strong and the close), else `fallback`.
func _from_familiar(fallback: Vector3, t: int = -1) -> Vector3:
	var em: EnemyManager = game.enemies
	if t < 0 or t >= EnemyManager.MAX or em.alive[t] == 0:
		t = aim_index(player.global_position, stat("range", 9.0))
	if t < 0:
		return fallback
	# pass 75: a punchy companion aims from its rest place, not from wherever its kick has thrown it
	var origin: Vector3 = _fam_base if (_fam_base_set and not _fam_dict("kick").is_empty()) else _familiar.global_position
	var to: Vector3 = em.pos[t] - origin
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.01 else fallback


## Half the fan a volley of `amount` spreads over: params.fan_step_deg between neighbouring shots, 8 by default (pass 46:
## the Spear Volley fans its three wider).
func _fan_half(amount: int) -> float:
	return deg_to_rad(float(inst.params.get("fan_step_deg", 8.0))) * 0.5 * float(maxi(amount - 1, 0))


## One fan of `amount` shots along `dir` from `from`.
func _volley_at(dir: Vector3, from: Vector3, amount: int, damage: float, speed: float, pierce: int, prad: float, life: float, knock: float, half_spread: float) -> void:
	var k_draw := _kind()
	for k in range(amount):
		var a := 0.0
		if amount > 1:
			a = lerp(-half_spread, half_spread, float(k) / float(amount - 1))
		var d := dir.rotated(Vector3.UP, a)
		game.projectiles.fire(k_draw, from, d * speed, damage, pierce, prad, life, inst, knock)


## Both Barrels (pass 51): when this pull is one that fires twice (every `double_every`th), the second barrel is armed to
## go `double_gap` seconds from now (DOUBLE_GAP).
func _arm_second_barrel() -> void:
	var de := int(inst.params.get("double_every", 0))
	if de <= 0 or _shots % de != 0:
		return
	if _barrel_t >= 0.0:
		# the last pull's second barrel has not gone yet (pulls closer than the gap): it goes now, never lost
		_barrel_t = -1.0
		_second_barrel()
	_barrel_t = maxf(float(inst.params.get("double_gap", DOUBLE_GAP)), 0.02)


## The second barrel (Both Barrels, pass 51): the pull once more, aimed afresh at what the gun points at now. A lane or a
## cone blasts again (its own wash and pellets), a volley flies again; a kick of the held gun, a flash, a bang.
func _second_barrel() -> void:
	second_barrels += 1
	# Both Barrels' beads (pass 61): the double has gone, the count starts over
	_set_beads(0)
	if _held:
		_held.scale = Vector3(1.0, 1.0, 0.7)
	var bl := inst.blast()
	if bl.is_empty():
		_volley(1.0)
		return
	var hero := player.global_position
	var t := aim_index(hero, float(bl["range"]))
	var dir: Vector3 = (game.enemies.pos[t] - hero) if t >= 0 else _aim_dir
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else player.forward()
	_aim_dir = dir
	_aim_yaw = atan2(-dir.x, -dir.z)
	_blast(bl, dir, stat("damage", 5.0), maxi(stat_int("amount", 1), 1), stat("knockback", 0.0), _speed())
	var from: Vector3 = player.aim_origin(dir)
	muzzle_flash(from, dir)
	sfx("fire", from)


## A repeat of the last volley at the current aim (Fan the Hammer), scaled.
func _volley(mult: float) -> void:
	var dir: Vector3 = _aim_dir if _aim_dir.length_squared() > 0.0001 else player.forward()
	var from: Vector3 = (_familiar.global_position + dir * 0.45) if _familiar else player.aim_origin(dir)
	var amount: int = max(stat_int("amount", 1), 1)
	var speed := _speed()
	var half_spread := _fan_half(amount)
	if inst.def.targeting == "forward":
		half_spread = deg_to_rad(stat("spread_deg", 30.0)) * 0.5
	_volley_at(dir, from, amount, stat("damage", 5.0) * mult, speed, stat_int("pierce", 0), _prad(), stat("range", 9.0) / maxf(speed, 1.0), stat("knockback", 0.0), half_spread)
	muzzle_flash(from, dir)
	sfx("fire", from)


## One volley of a hip shot (pass 48): every round of the amount at once, from the companion (or the hip) along a fresh
## aim, in half the volley's fan; a kick, the cylinder turns, the shot is heard. The last volley sets the companion
## twirling (HIP_SPIN).
func _hip_volley() -> void:
	_hip_left -= 1
	_hip_t = _hip_gap
	var dir: Vector3 = _aim_dir if _aim_dir.length_squared() > 0.0001 else player.forward()
	if _familiar:
		dir = _from_familiar(dir)
	var punchy := _familiar != null and _fam_base_set and not _fam_dict("kick").is_empty()
	var from: Vector3 = ((_fam_base if punchy else _familiar.global_position) + dir * 0.45) if _familiar else player.aim_origin(dir)
	var amount: int = maxi(stat_int("amount", 1), 1)
	var speed := _speed()
	_volley_at(dir, from, amount, stat("damage", 5.0), speed, stat_int("pierce", 0), _prad(), stat("range", 9.0) / maxf(speed, 1.0), stat("knockback", 0.0), _fan_half(amount) * 0.5)
	hip_volleys += 1
	if _familiar:
		if punchy:
			_aim_yaw = atan2(-dir.x, -dir.z)
		_kick()
		_turn_drum()
	muzzle_flash(from, dir)
	sfx("fire", from)
	if _hip_left <= 0:
		_spin_t = 0.0
		_spin_len = HIP_SPIN
		_spin_trick = false
		# the twirl is heard (pass 48)
		Audio.play("w_hip_spin", from)


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var amount: int = max(stat_int("amount", 1), 1)
	var speed := _speed()
	var range_m := stat("range", 9.0)
	# pass 67: the ball's Heat (1 for every other weapon) and a free throw's share (1 but on Free Throw's own throw)
	var damage := stat("damage", 5.0) * heat_mult() * _free_mult
	var pierce := stat_int("pierce", 0)
	var knock := stat("knockback", 0.0)
	var prad := _prad()
	var bl := inst.blast()
	var hero := player.global_position
	var dir := Vector3.ZERO
	var half_spread := 0.0
	var target := -1
	match inst.def.targeting:
		"forward":
			# a lane or a cone (pass 48) aims at what is within its own reach
			target = aim_index(hero, float(bl["range"]) if not bl.is_empty() else range_m)
			if target < 0 and not bool(inst.params.get("fire_blind", false)):
				# nobody in reach (pass 53, Garry: "Boomstick seems to be firing all the time, this should only happen after
				# it's Evolved"): no shot, no kick, no flash, no bang; the Blunderbuss's `fire_blind` keeps it blasting on its
				# clock along the facing
				return false
			dir = (enemies.pos[target] - hero) if target >= 0 else player.forward()
			half_spread = deg_to_rad(stat("spread_deg", 30.0)) * 0.5
			if _held:
				_held.scale = Vector3(1.0, 1.0, 0.7)
		"random":
			# pass 73 (lane SNIPER): a special, an Elite or the boss within reach first
			target = priority_pick(hero, range_m)
			if target < 0:
				target = enemies.random_in_range(hero, range_m)
			if target < 0:
				return false
			dir = (enemies.pos[target] - hero)
			half_spread = _fan_half(amount)
		"healthy":
			# the nearest creature not carrying this weapon's element yet; when everyone does, the nearest one (pass 73:
			# a special, an Elite or the boss within reach before either)
			target = priority_pick(hero, range_m)
			if target < 0:
				target = enemies.nearest_index(hero, range_m, inst.element())
			if target < 0:
				target = enemies.nearest_index(hero, range_m)
			if target < 0:
				return false
			dir = (enemies.pos[target] - hero)
			half_spread = _fan_half(amount)
		_:
			# the nearest, or (pass 48, "priority") the strong and the close
			target = aim_index(hero, range_m)
			if target < 0 and not bool(inst.params.get("fire_without_target", false)):
				return false
			# pass 69 (lane HERO, May's Trigger Happy): `fire_without_target` fires along her facing when nobody is in range
			dir = (enemies.pos[target] - hero) if target >= 0 else player.forward()
			half_spread = _fan_half(amount)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = player.forward()
	dir = dir.normalized()
	_aim_dir = dir
	_aim_yaw = atan2(-dir.x, -dir.z)
	var from: Vector3 = player.aim_origin(dir)
	if _familiar:
		# shots leave the companion's mouth, wherever it is circling right now, aimed from there
		if inst.def.targeting != "random":
			dir = _from_familiar(dir, target)
			_aim_dir = dir
		if not _fam_dict("kick").is_empty() and _fam_base_set:
			# pass 75: a punchy companion fires from its rest place, along its own line, and swells with its kick instead
			from = _fam_base + dir * 0.45
			_aim_yaw = atan2(-dir.x, -dir.z)
		else:
			from = _familiar.global_position + dir * 0.45
			_familiar.scale = Vector3(1.18, 0.86, 1.18)
	var life := range_m / maxf(speed, 1.0)
	_shots += 1
	# Both Barrels' beads (pass 61): one more lit towards the double
	_count_bead()
	# Drum Roll: the burst grows with Buck's momentum
	var mr := int(inst.params.get("momentum_rounds", 0))
	if mr > 0:
		amount += int(floor(Run.momentum * float(mr) + 0.0001))
	if not bl.is_empty():
		# Birdshot's lane, the Blunderbuss's cone (pass 48): all of it at once; Both Barrels fires the pull again a beat later
		_blast(bl, dir, damage, amount, knock, speed)
		_arm_second_barrel()
		muzzle_flash(from, dir)
		sfx("fire", from)
		return true
	var hs = inst.params.get("hip_shot")
	if hs is Dictionary and int((hs as Dictionary).get("every", 0)) > 0 and _shots % int(hs["every"]) == 0:
		# Hip Shot (pass 48): this pull is `volleys` volleys `gap` apart, each the whole amount at once
		_burst.clear()
		_hip_left = maxi(int((hs as Dictionary).get("volleys", 3)), 1)
		_hip_gap = maxf(float((hs as Dictionary).get("gap", 0.12)), 0.02)
		_hip_volley()
		return true
	if bool(inst.params.get("burst", false)):
		# a burst: one shot now, the rest every 50 ms from wherever the gun is by then, each with its own scatter
		_burst.clear()
		var sweep := deg_to_rad(float(inst.params.get("sweep_deg", 0.0)))
		var scatter: float = deg_to_rad(float(inst.params["scatter_deg"])) if inst.params.has("scatter_deg") else maxf(half_spread, deg_to_rad(5.0))
		for k in range(amount):
			var shot := {"speed": speed, "damage": damage, "pierce": pierce, "prad": prad, "life": life, "knock": knock, "spread": scatter}
			if sweep > 0.0 and amount > 1:
				shot["angle"] = lerpf(-sweep * 0.5, sweep * 0.5, float(k) / float(amount - 1))
			_burst.append(shot)
		_burst_t = 0.0
		_stream_gap = stream_gap(stat("cooldown", 1.0), amount) if bool(inst.params.get("stream", false)) else 0.0
		if _stream_gap > 0.0:
			_burst_t = _stream_gap
		_fire_burst_shot()
	elif _bounces():
		# pass 67 (the basketball): one ball, its amount past the first more hops
		_throw_ball(dir, from, amount, damage, speed, pierce, prad, life, knock)
	else:
		_volley_at(dir, from, amount, damage, speed, pierce, prad, life, knock, half_spread)
		if _familiar:
			# pass 75: a companion with `familiar.spin` may twirl after a volley too
			_maybe_trick_spin()
		# Both Barrels: every Nth pull fires the volley again a beat later; Fan the Hammer: extra volleys a beat apart, a
		# little weaker
		_arm_second_barrel()
		var dt = inst.params.get("double_tap")
		if dt is Dictionary:
			_taps = maxi(int(dt.get("count", 2)) - 1, 0)
			# Fan the Hammer's hand (pass 61) flicks under the pod for the extra volleys
			if _taps > 0:
				_start_flick()
			_tap_t = 0.09
			_tap_mult = float(dt.get("damage_mult", 0.75))
	if bool(inst.params.get("shockwave", false)):
		enemies.damage_radius(player.global_position, 1.8, damage * 0.5, inst.def.id, knock)
		game.telegraphs.flash_ring(player.global_position, 1.8, Color(1.0, 0.7, 0.3))
	muzzle_flash(from, dir)
	sfx("fire", from)
	return true


## Pass 48, `params.blast` (Birdshot's lane, the Blunderbuss's cone; WeaponInstance.blast reads it): no pellet does the
## work. Every creature in the lane (`width` wide, `range` long ahead of the hero) or the cone (`deg` wide, `range` deep)
## takes `frac` of a full point-blank volley (damage x amount) at once, is set alight or poisoned by the weapon's element,
## and is thrown along the lane (out from the hero in a cone). Pellets streak through it for the eye (ghost shots, which
## hit nothing) and a pale wash marks it on the sand. Returns how many it hit.
func _blast(bl: Dictionary, dir: Vector3, damage: float, amount: int, knock: float, speed: float) -> int:
	var em: EnemyManager = game.enemies
	var hero := player.global_position
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var per: float = float(bl["frac"]) * damage * float(amount)
	var wid: String = inst.def.id
	var cone: bool = str(bl["shape"]) == "cone"
	var hit := blast_targets(bl, hero, d)
	for e in hit:
		var kdir := d
		if cone:
			var out := Vector3(em.pos[e].x - hero.x, 0.0, em.pos[e].z - hero.z)
			if out.length_squared() > 0.0001:
				kdir = out.normalized()
		if inst.stat("fire_damage", 0.0) > 0.0:
			em.ignite(e, wid, inst.stat("fire_damage", 4.0), inst.stat("fire_duration", 1.8), inst.stat("fire_spread", 0.5))
		if inst.stat("poison_damage", 0.0) > 0.0:
			game.projectiles.weapon_poison(e, inst)
		var at: Vector3 = em.pos[e] + Vector3(0, 0.6, 0)
		if em.damage(e, per, wid, kdir, knock):
			inst.kills += 1
		game.fx_hit(at, inst.def)
	_blast_show(bl, hero, d, amount, speed)
	blasts += 1
	return hit.size()


## The creatures a blast from `origin` along `d` covers: in the cone (EnemyManager.indices_in_cone), or with their middle
## inside the lane's rectangle.
func blast_targets(bl: Dictionary, origin: Vector3, d: Vector3) -> PackedInt32Array:
	var em: EnemyManager = game.enemies
	var r := float(bl["range"])
	if str(bl["shape"]) == "cone":
		return em.indices_in_cone(origin, d, r, float(bl["deg"]) * 0.5)
	var half := float(bl["width"]) * 0.5
	var out := PackedInt32Array()
	for e in em.indices_in_radius(origin + d * r * 0.5, r * 0.5 + half + 0.5):
		var v := Vector3(em.pos[e].x - origin.x, 0.0, em.pos[e].z - origin.z)
		var along := v.dot(d)
		if along < 0.0 or along > r:
			continue
		if (v - d * along).length() > half:
			continue
		out.append(e)
	return out


## What a blast looks like: the wash on the sand (a pale line for 0.15 s down a lane, a pale sweep over a cone) and the
## pellets streaking through it (ghost shots of the weapon's own kind, fast, gone at its end).
func _blast_show(bl: Dictionary, hero: Vector3, d: Vector3, amount: int, speed: float) -> void:
	var r := float(bl["range"])
	var g: float = game.map.height_at(hero.x, hero.z) if game.map else hero.y
	var ground := Vector3(hero.x, g, hero.z)
	var cone: bool = str(bl["shape"]) == "cone"
	var tg = game.get("telegraphs")
	if tg:
		if cone:
			tg.wash(ground, d, r, float(bl["deg"]), 0.3, BLAST_WASH, 0.32)
		else:
			tg.line(ground, d, r, 0.15, BLAST_WASH, float(bl["width"]))
	var pm: ProjectileManager = game.projectiles
	var n: int = clampi(amount, 3, 14)
	var spd: float = maxf(speed * 2.2, 30.0)
	var start: Vector3 = player.aim_origin(d)
	var side := d.cross(Vector3.UP).normalized()
	# the ghost pellets in the weapon's own look (pass 61: Dragon's Breath's orange down a Birdshot lane)
	var k_draw := _kind()
	for k in range(n):
		var f: float = (float(k) + randf()) / float(n)
		var dd := d
		var from := start
		if cone:
			dd = d.rotated(Vector3.UP, deg_to_rad(lerpf(-0.5, 0.5, f) * float(bl["deg"])))
		else:
			from = start + side * lerpf(-0.45, 0.45, f) * float(bl["width"])
		var j := pm.fire(k_draw, from, dd * spd, 0.0, 0, 0.0, r / spd * randf_range(0.85, 1.0), inst, 0.0)
		if j >= 0:
			pm.extra[j]["ghost"] = true


# ---------------------------------------------------------------- pass 61 (lane WP1): the cheap mutation looks
## Pass 61 (Garry: "Mutation Visual, implement every Cheap version"): a mutation shows on the gun and its shots, switched
## on by its own params (merged into the weapon's, so an evolution that keeps the mutation keeps the look):
## - `tint` / `look.spikes` (the shots' kind: _kind), `tracer_color` / `tracer_beads` / `look.specks` / `look.blink`
##   (the ProjectileManager's side);
## - `look.parts {show {node: true}, hide {node: true}}`: named parts of the visual shown or hidden (Both Barrels' second
##   barrel); `look.paint {node: tint}`: every mesh under a named part in a tint's colours (Toxic Peas' peas in the pod);
## - `look.heat {parts {node: true}, color, energy, cool}`: the meshes under the named parts glow `color` at `energy`
##   after every shot and cool back in `cool` seconds (Dragon's Breath's red-hot barrel);
## - `look.tongue {length, size}`: a tongue of flame licks out of the muzzle with every shot (Fx.flame_tongue);
## - `look.beads {node, on, energy}`: under the named part, `double_every` beads (Bead1..), one lit a pull, all dark again
##   when the second barrel goes (Both Barrels' count);
## - `look.flick {node, seconds, swing_deg}`: the named part (hidden) shows and swings under the companion on a volley
##   that fires again (Fan the Hammer's hand);
## - `drum_scale`: the companion's Drum that much bigger (Drum Mag; `drum_step` already turns it).
## Every look is undone before it is put on again (refresh_marks: every build change), so a look taken away goes.
const HEAT_COLOR := Color(1.0, 0.22, 0.04)
const HEAT_ENERGY := 2.4
const HEAT_COOL := 0.6
const BEAD_ON := Color(1.0, 0.78, 0.25)
const BEAD_ENERGY := 1.5
const FLICK_SECONDS := 0.26
const FLICK_SWING := 75.0
## what a look changed, to put back: Node3D -> {"visible": bool} / MeshInstance3D -> {"over": Material}
var _look_undo := {}
var _heat := 0.0
var _heat_mats: Array = []
var _heat_base: Array = []
var _heat_shown := -1.0
var _beads: Array = []
var _bead_on: Array = []
var _bead_off: Array = []
var _beads_lit := 0
var _flick: Node3D
var _flick_t := -1.0
var _flick_rest := Transform3D.IDENTITY
var _drum_rest := Vector3.ZERO
## Diagnostics and tests: flicks played, tongues licked.
var flicks := 0
var tongues := 0


## What the looks were last built from (the model, the look words, the drum's scale, the double's count): a rebuild
## with the same key keeps the looks as they are.
var _look_key := ""


## The look words this weapon carries (params.look, merged from its mutations), or none.
func look() -> Dictionary:
	if inst == null:
		return {}
	var lk = inst.params.get("look")
	return lk if lk is Dictionary else {}


func refresh_marks() -> void:
	super.refresh_marks()
	_apply_looks()


## Every shot's muzzle: the flash, and then the shot's look (the flame tongue, the barrel's heat).
func muzzle_flash(at: Vector3 = Vector3.INF, dir: Vector3 = Vector3.ZERO) -> void:
	super.muzzle_flash(at, dir)
	_shot_look(at, dir)


func _shot_look(at: Vector3, dir: Vector3) -> void:
	if inst == null:
		return
	if not _heat_mats.is_empty():
		_heat = 1.0
	var tg = look().get("tongue")
	if tg is Dictionary and at != Vector3.INF and game.get("fx") != null and game.fx.has_method("flame_tongue"):
		game.fx.flame_tongue(at, dir, float((tg as Dictionary).get("length", 1.0)), float((tg as Dictionary).get("size", 0.5)), inst.blue_fire())
		tongues += 1


func _apply_looks() -> void:
	_kind_cache = -1
	if visual == null or inst == null:
		return
	# the same looks on the same model: nothing to redo (the review: every build change, Adrenaline's or Crescendo's
	# several a second among them, had put out the beads, the barrel's heat and the hand mid-swing)
	var lkey := "%d|%s|%s|%s" % [visual.get_instance_id(), str(look()), str(inst.params.get("drum_scale", 1.0)), str(inst.params.get("double_every", 0))]
	if lkey == _look_key:
		return
	_look_key = lkey
	_undo_looks()
	var lk := look()
	var parts = lk.get("parts")
	if parts is Dictionary:
		for key in ["show", "hide"]:
			var names = (parts as Dictionary).get(key, {})
			if names is Dictionary:
				for nm in (names as Dictionary).keys():
					if bool(names[nm]):
						_show_part(str(nm), key == "show")
	var paint = lk.get("paint")
	if paint is Dictionary:
		for nm in (paint as Dictionary).keys():
			if paint[nm] is Dictionary:
				_paint_part(str(nm), paint[nm])
	_setup_heat(lk.get("heat"))
	_setup_beads(lk.get("beads"))
	var fl = lk.get("flick")
	if fl is Dictionary:
		_flick = _part(str((fl as Dictionary).get("node", "Hand")))
		if _flick:
			_flick_rest = _flick.transform
			_flick.visible = false
	if _drum:
		if _drum_rest == Vector3.ZERO:
			_drum_rest = _drum.scale
		_drum.scale = _drum_rest * float(inst.params.get("drum_scale", 1.0))


## Puts back everything the looks changed (visibility, materials) and forgets their state.
func _undo_looks() -> void:
	for n in _look_undo.keys():
		if not is_instance_valid(n):
			continue
		var rec: Dictionary = _look_undo[n]
		if rec.has("visible"):
			(n as Node3D).visible = bool(rec["visible"])
		if rec.has("over"):
			(n as MeshInstance3D).material_override = rec["over"]
	_look_undo.clear()
	_heat_mats.clear()
	_heat_base.clear()
	_heat = 0.0
	_heat_shown = -1.0
	_beads.clear()
	_bead_on.clear()
	_bead_off.clear()
	_beads_lit = 0
	if _flick and is_instance_valid(_flick):
		_flick.transform = _flick_rest
		_flick.visible = false
	_flick = null
	_flick_t = -1.0


## The visual's part named `nm` (searched anywhere under it), or null.
func _part(nm: String) -> Node3D:
	if visual == null or nm == "":
		return null
	return visual.find_child(nm, true, false) as Node3D


func _remember(n: Node, key: String, value) -> void:
	if not _look_undo.has(n):
		_look_undo[n] = {}
	if not (_look_undo[n] as Dictionary).has(key):
		_look_undo[n][key] = value


func _show_part(nm: String, on: bool) -> void:
	var n := _part(nm)
	if n == null:
		return
	_remember(n, "visible", n.visible)
	n.visible = on


## The meshes under (and at) a part.
func _meshes_of(n: Node) -> Array:
	var out: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		out.append(n)
	return out


## The material a mesh is drawn with (its override, else its first surface's).
static func _mat_of(m: MeshInstance3D) -> Material:
	if m.material_override:
		return m.material_override
	if m.mesh and m.mesh.get_surface_count() > 0:
		var s := m.get_surface_override_material(0)
		return s if s else m.mesh.surface_get_material(0)
	return null


func _paint_part(nm: String, tint: Dictionary) -> void:
	var n := _part(nm)
	if n == null:
		return
	var made := {}
	for m: MeshInstance3D in _meshes_of(n):
		var src := _mat_of(m)
		if src == null:
			continue
		var key := src.get_instance_id()
		if not made.has(key):
			made[key] = ProjectileManager.tint_material(src, tint)
		_remember(m, "over", m.material_override)
		m.material_override = made[key]


## Dragon's Breath's heat (pass 61): one copy per material of the meshes under the named parts, its own glow kept as the
## bottom of the ramp (the companion glow of pass 53 lit them all, so the shader never changes under it).
func _setup_heat(cfg) -> void:
	if not (cfg is Dictionary):
		return
	var names = (cfg as Dictionary).get("parts", {})
	if not (names is Dictionary):
		return
	var made := {}
	for nm in (names as Dictionary).keys():
		var n := _part(str(nm))
		if n == null:
			continue
		for m: MeshInstance3D in _meshes_of(n):
			var src := _mat_of(m)
			if not (src is StandardMaterial3D):
				continue
			var key := src.get_instance_id()
			if not made.has(key):
				var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				var base_col := Color(dup.emission.r, dup.emission.g, dup.emission.b) if dup.emission_enabled else Color.BLACK
				var base_e: float = dup.emission_energy_multiplier if dup.emission_enabled else 0.0
				dup.emission_enabled = true
				dup.emission = base_col
				dup.emission_energy_multiplier = base_e
				made[key] = dup
				_heat_mats.append(dup)
				_heat_base.append({"color": base_col, "energy": base_e, "albedo": dup.albedo_color})
			_remember(m, "over", m.material_override)
			m.material_override = made[key]
	_heat_shown = -1.0


## The heat after a shot cools over `cool` seconds; the glow is written only when it moved.
func _tick_heat(delta: float) -> void:
	if _heat_mats.is_empty():
		return
	var cfg: Dictionary = look().get("heat", {}) if look().get("heat") is Dictionary else {}
	_heat = maxf(_heat - delta / maxf(float(cfg.get("cool", HEAT_COOL)), 0.05), 0.0)
	var r: float = _heat * _heat * (3.0 - 2.0 * _heat)
	if absf(r - _heat_shown) < 0.02 and not (r <= 0.0 and _heat_shown > 0.0):
		return
	_heat_shown = r
	var hot := Color(str(cfg.get("color", HEAT_COLOR.to_html(false))))
	var hot_e := float(cfg.get("energy", HEAT_ENERGY))
	for k in range(_heat_mats.size()):
		var m: StandardMaterial3D = _heat_mats[k]
		var b: Dictionary = _heat_base[k]
		m.emission = (b["color"] as Color).lerp(hot, r)
		m.emission_energy_multiplier = lerpf(float(b["energy"]), maxf(hot_e, float(b["energy"])), r)
		m.albedo_color = (b["albedo"] as Color).lerp(Color(hot.r, hot.g * 0.6, hot.b * 0.6, (b["albedo"] as Color).a), r * 0.5)


## How hot the barrel shows now, 0..1 (tests).
func heat_shown() -> float:
	return maxf(_heat_shown, 0.0)


## Both Barrels' beads (pass 61): `double_every` of Bead1, Bead2... under the named part shown, the rest hidden; each with
## its dark brass and a lit copy glowing `on` at `energy`.
func _setup_beads(cfg) -> void:
	if not (cfg is Dictionary):
		return
	var holder := _part(str((cfg as Dictionary).get("node", "Beads")))
	var de := int(inst.params.get("double_every", 0))
	if holder == null or de <= 0:
		return
	_remember(holder, "visible", holder.visible)
	holder.visible = true
	var on_col := Color(str((cfg as Dictionary).get("on", BEAD_ON.to_html(false))))
	var energy := float((cfg as Dictionary).get("energy", BEAD_ENERGY))
	var k := 1
	while true:
		var b := holder.get_node_or_null("Bead%d" % k) as MeshInstance3D
		if b == null:
			break
		_remember(b, "visible", b.visible)
		_remember(b, "over", b.material_override)
		b.visible = k <= de
		if k <= de:
			var off := _mat_of(b)
			var lit: Material = off
			if off is StandardMaterial3D:
				var l := (off as StandardMaterial3D).duplicate() as StandardMaterial3D
				l.emission_enabled = true
				l.emission = on_col
				l.emission_energy_multiplier = energy
				l.albedo_color = on_col
				lit = l
			_beads.append(b)
			_bead_off.append(off)
			_bead_on.append(lit)
		k += 1
	_set_beads(0)


## Lights the first `n` beads (the rest dark).
func _set_beads(n: int) -> void:
	_beads_lit = clampi(n, 0, _beads.size())
	for k in range(_beads.size()):
		(_beads[k] as MeshInstance3D).material_override = _bead_on[k] if k < _beads_lit else _bead_off[k]


## A pull counts towards the double: 1, 2 ... `double_every` lit (the last on the pull that fires twice).
func _count_bead() -> void:
	if _beads.is_empty():
		return
	var de := int(inst.params.get("double_every", 0))
	if de <= 0:
		return
	_set_beads(((_shots - 1) % de) + 1)


## How many beads are lit, and how many there are (tests).
func beads_lit() -> int:
	return _beads_lit


func bead_count() -> int:
	return _beads.size()


func _start_flick() -> void:
	if _flick == null:
		return
	_flick_t = 0.0
	flicks += 1


## The hand's flick (Fan the Hammer): it pops in under the companion, swings across `swing_deg` (a quick snap through
## the middle, as the second volley goes) and is gone at `seconds`.
func _tick_flick(delta: float) -> void:
	if _flick == null or _flick_t < 0.0:
		return
	var cfg: Dictionary = look().get("flick", {}) if look().get("flick") is Dictionary else {}
	var dur := maxf(float(cfg.get("seconds", FLICK_SECONDS)), 0.05)
	_flick_t += delta
	if _flick_t >= dur:
		_flick_t = -1.0
		_flick.visible = false
		_flick.transform = _flick_rest
		return
	var f := _flick_t / dur
	var swing := deg_to_rad(float(cfg.get("swing_deg", FLICK_SWING)))
	# out to one side, a snap across (smoothstep in the middle), a little settle
	var s: float = clampf((f - 0.15) / 0.5, 0.0, 1.0)
	s = s * s * (3.0 - 2.0 * s)
	var yaw: float = lerpf(-swing * 0.5, swing * 0.5, s)
	var pop: float = clampf(f / 0.15, 0.0, 1.0) * clampf((1.0 - f) / 0.2, 0.0, 1.0)
	_flick.visible = true
	_flick.transform = _flick_rest
	_flick.rotate_object_local(Vector3.UP, yaw)
	_flick.scale = _flick_rest.basis.get_scale() * maxf(pop, 0.05)


## Whether the hand is out now (tests).
func flicking() -> bool:
	return _flick != null and _flick_t >= 0.0


func _tick_looks(delta: float) -> void:
	_tick_heat(delta)
	_tick_flick(delta)


# ---------------------------------------------------------------- pass 67 (lane P): the basketball
## Pass 72: a free throw's ball is the ball, in its own look (Garry: "the 3d object projectile seems to be white, should
## be orange"): pass 67 drew it in white (albedo and a white glow at 1.4), so with Free Throw a third of his balls flew
## white. FREE_TINT is gone; the free throw is told by the evade that threw it.
## Slam Dunk's dunk: its ring on the sand and its burst.
const DUNK_COLOR := Color(1.0, 0.55, 0.12)


## Whether `amount` counts bounces (pass 67, `params.amount_mode` "bounces": the basketball, Slam Dunk).
func _bounces() -> bool:
	return str(inst.params.get("amount_mode", "")) == "bounces"


## One ball (pass 67, amount_mode "bounces"), fired through the manager along the aim with its hops seeded: the block's
## ricochet_any.count plus every amount past the first (ProjectileManager._ricochet_on reads extra["rc_left"] before the
## count), so a level, Multishot or a +amount buff sends it on to one more creature instead of throwing a second ball. A
## free throw's ball is drawn as the ball (pass 72; pass 67 drew it white). The shot's index, -1 when the pool is full.
func _throw_ball(dir: Vector3, from: Vector3, amount: int, damage: float, speed: float, pierce: int, prad: float, life: float, knock: float) -> int:
	var pm: ProjectileManager = game.projectiles
	var k: int = _ball_kind(_kind())
	var j := pm.fire(k, from, dir * speed, damage, pierce, prad, life, inst, knock)
	if j < 0:
		return -1
	var ra = inst.params.get("ricochet_any")
	var count: int = int((ra as Dictionary).get("count", 0)) if ra is Dictionary else 0
	pm.extra[j]["rc_left"] = maxi(count + amount - 1, 0)
	throws += 1
	return j


## The ball's Heat on its damage (pass 67, `params.catch.heat_per`): 1 + Run.heat x heat_per; 1 for any other weapon.
func heat_mult() -> float:
	var ct = inst.params.get("catch") if inst else null
	if not ct is Dictionary:
		return 1.0
	return 1.0 + float(Run.heat) * float((ct as Dictionary).get("heat_per", 0.0))


## The ball is back in his hand (pass 67, `params.catch {refund, heat_per, heat_max, heat_keep, slam}`: the manager calls
## Game.ball_caught, which hands it here with the shot's extra, `ex["hits"]` the creatures it struck on the trip). The
## catch gives back `refund` of the weapon's cooldown (never below none left), a trip that scored adds one Heat up to
## `heat_max`, and with `slam {at_heat, radius, damage_frac, knockback}` (Slam Dunk) a catch at that much Heat is a dunk
## (_dunk). Heard (the weapon's "catch" sound) and seen (a small burst at his hands).
func on_caught(ex: Dictionary) -> void:
	var ct = inst.params.get("catch") if inst else null
	if not ct is Dictionary:
		return
	var c: Dictionary = ct
	catches += 1
	cooldown_left = maxf(cooldown_left - float(c.get("refund", 0.0)) * stat("cooldown", 1.0), 0.0)
	if int(ex.get("hits", 0)) >= 1:
		Run.heat = mini(Run.heat + 1, maxi(int(c.get("heat_max", 10)), 0))
	var at: Vector3 = (player.global_position + Vector3(0, 0.9, 0)) if player else Vector3.INF
	sfx("catch", at)
	if player and game.has_method("fx_burst"):
		game.fx_burst(at, Color(1.0, 0.6, 0.2), 0.45)
	var sl = c.get("slam")
	if sl is Dictionary and Run.heat >= int((sl as Dictionary).get("at_heat", c.get("heat_max", 10))):
		_dunk(sl)


## Slam Dunk's dunk (pass 67, catch.slam): the weapon's damage x `damage_frac` (Heat does not multiply it) to everything
## within `radius` of him, thrown out by `knockback`; a ring on the sand, a burst and a shake where the game has them.
func _dunk(sl: Dictionary) -> void:
	if player == null or game.get("enemies") == null:
		return
	var at: Vector3 = player.global_position
	var r := float(sl.get("radius", 3.5))
	game.enemies.damage_radius(at, r, stat("damage", 5.0) * float(sl.get("damage_frac", 1.0)), inst.def.id, float(sl.get("knockback", 0.0)))
	dunks += 1
	var tg = game.get("telegraphs")
	if tg != null and tg.has_method("flash_ring"):
		tg.flash_ring(at, r, DUNK_COLOR, 0.4)
	var cam = game.get("camera")
	if cam != null and cam.has_method("shake"):
		cam.shake(0.4)
	if game.has_method("fx_burst"):
		game.fx_burst(at + Vector3(0, 0.4, 0), DUNK_COLOR, 1.2)


## A hit reached his health (pass 67; Game calls this on every behaviour that has it): the ball's Heat drops to nothing
## unless its catch.heat_keep (Slam Dunk). An evade or a hit the shield took never comes here.
func on_hero_hit() -> void:
	var ct = inst.params.get("catch") if inst else null
	if ct is Dictionary and not bool((ct as Dictionary).get("heat_keep", false)):
		Run.heat = 0


## Free Throw (pass 67, the hero mutation, `params.free_throw {every, damage_mult}`; Game calls this on every behaviour
## that has it when he evades a hit): a ball at once, outside the cooldown (which runs on untouched), at `damage_mult` of
## the throw and drawn as the ball (pass 72); at most one every `every` seconds, the gap counted from a throw that went (nobody within
## range: no throw and no gap).
func on_hero_evaded() -> void:
	var ft = inst.params.get("free_throw") if inst else null
	if not ft is Dictionary or _free_t > 0.0 or player == null or player.dead:
		return
	_free_mult = float((ft as Dictionary).get("damage_mult", 1.0))
	_free_throw = true
	var went := _fire()
	_free_throw = false
	_free_mult = 1.0
	if went:
		free_throws += 1
		_free_t = maxf(float((ft as Dictionary).get("every", 0.8)), 0.0)


# ---------------------------------------------------------------- pass 69 (lane BB): Heat on the ball
## Garry: "This indicator should only be present on the 3d object of the ball itself, so a trail, pulsating energy, etc.
## No UI Indicators". A weapon with `params.heat_look` (the basketball, Slam Dunk; keys in ProjectileManager.heat_glow,
## _heat_trail and _draw_heat_halos) draws its balls in heat copies of their kinds (ProjectileManager.heat_kind), whose
## glow follows Run.heat every frame: the emission and an orange trail grow with Heat, flames lick behind it past
## `flame_from`, a halo swells round it, and at the top all of it beats at `pulse_hz`. A drop in Heat (a hit that reached
## him) puts the balls in flight out at once with a puff of steam off each (_fizzle).
## The heat copies of the kinds this weapon's balls are drawn in (kind -> true), Run.heat as last seen.
var _heat_kinds: Dictionary = {}
var _heat_was := -1
## Diagnostics and tests: the Heat the ball shows now (0..1) and the steam puffs a cooling put out.
var heat_level_shown := 0.0
var fizzles := 0


## The heat look this weapon carries (params.heat_look, merged from an evolution's `final` too), or none.
func heat_look() -> Dictionary:
	if inst == null:
		return {}
	var hl = inst.params.get("heat_look")
	return hl if hl is Dictionary else {}


## The kind a ball is drawn in: `k` itself, or (with a heat look) the heat copy of it with its seams split off (so the
## Heat can glow in them; a tint with `body` split them already), kept for the glow's writes.
func _ball_kind(k: int) -> int:
	if heat_look().is_empty() or k < 0 or game == null or game.get("projectiles") == null:
		return k
	if not game.projectiles.has_seams(k):
		k = game.projectiles.seam_kind(k, {})
	var kh: int = game.projectiles.heat_kind(k)
	_heat_kinds[kh] = true
	return kh


## Every frame: the glow of every heat copy written for Heat now (ProjectileManager.heat_glow), and a drop puts the balls
## out.
func _tick_heat_look(_delta: float) -> void:
	var hl := heat_look()
	if hl.is_empty() or game == null or game.get("projectiles") == null:
		return
	var lv: float = ProjectileManager.heat_level(inst)
	var h: int = Run.heat
	if _heat_was > 0 and h < _heat_was:
		_fizzle()
	_heat_was = h
	heat_level_shown = lv
	for kh in _heat_kinds.keys():
		game.projectiles.heat_glow(int(kh), lv, hl)


## Heat lost (pass 69): a puff of steam off every ball of this weapon in flight, so the cooling reads on the ball.
func _fizzle() -> void:
	var pm = game.projectiles
	for i in range(ProjectileManager.MAX):
		if pm.alive[i] == 1 and pm.weapon[i] == inst:
			fizzles += 1
			if game.has_method("fx_burst"):
				game.fx_burst(pm.pos[i] + Vector3(0, 0.15, 0), Color(0.86, 0.86, 0.84), 0.55)

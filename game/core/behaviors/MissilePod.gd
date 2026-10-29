## A launcher that floats beside the hero and fires homing missiles. Every volley queues `amount` missiles that leave
## one after another in a fan; each corkscrews for a moment before it locks on and dives (ProjectileManager.launch_missile,
## tuned by `params.missile`). The "Familiar" node of the visual scene is the pod: it tracks its target between volleys
## and kicks back per launch. The same behaviour runs the Killer Bees (pass 49, Garry: "change the whole naming for this
## one to be about Killer Bees, not Hornets"; the id stays hornet_nest) with faster, smaller, non-exploding seekers, the
## bees, from a beehive: they and the Tarantula Hawks come out of its door (an "Entrance" marker, _launch_point).
## Pass 48: a priority weapon tracks and locks on the strong and the close (aim_index, EnemyManager.priority_index);
## `params.pollen` keeps a FlowerField on the map while the weapon is held, and while a picked flower's buff lasts the
## bees fly red with red trails (a red kind, trail 4); `params.hawk {every, stings, seconds, slow}` sends a Tarantula Hawk
## every `every` bursts (every burst while the Pollen buff lasts) at the strongest creature near that no hawk holds.
## Pass 53: the rocket flies nose first (the visual's Projectile node is turned so its capsule lies along -Z; that turn
## goes to the shot's kind, ProjectileManager.set_kind_basis); the cluster's tips are any count (Tip1..TipN, the Hellfire
## Battery's six) and `params.cluster_spin` false keeps a two-row battery from revolving. Pressure Cooker (pass 60,
## Garry: "while standing still the rate of fire of the Rocket Pod increases, every second, up to +200%. Being hit or
## moving stops it. Takes like 15 seconds to get to max, increases linearly"; params.pressure {max, seconds, hit_vent,
## start}): `pressure` (0..1) climbs by dt / `seconds` while the hero stands still (Player.is_still, with its half-second
## grace), is all let out the moment he moves, and a hit on his health or his Energy Shield vents `hit_vent` of it (a puff
## of steam off the pod); the fire interval is the cooldown over 1 + bonus, bonus = start + (max - start) x pressure
## (start is 0 without it: the Hellfire Battery starts hot). The pod's body and tubes glow with the pressure (HEAT_COLOR
## up to HEAT_ENERGY, clearly hot at the top). The Hellfire Battery's overpressure (params.overpressure {every}): at full
## pressure every `every`th volley is a double volley. Pass 81 (lane POLISH): the bees' line is `params.missile.trail_style`
## (dash, buzz, bumble, zip, beads; ProjectileManager.BEE_LOOKS, "dash" without one) and `trail_color`, handed to each bee.
## Pass 109 (lane VFX; Garry: "there are some flaps that open on the top of it. Looks like they are clipping through and it
## looks broken. The launch animation should be that of the Launcher looking up and shooting up"): a launcher whose
## `params.familiar.launch_pitch` (degrees) is above 0 looks up before a volley (LAUNCH_RAISE_RATE; the first rocket waits
## until it is RAISED_SHARE of the way up, at most RAISE_WAIT s), fires every rocket from the open end of the tube in turn
## (its Tip, along the tubes: launch_dir, fanned a little), holds there through the volley and settles back after
## LAUNCH_SETTLE s; its tube cluster never turns (the quarter turns pushed the tubes through the box's top) and the kick no
## longer swells the cluster. `params.missile.rise` (ProjectileManager.launch_missile) keeps the rockets climbing through
## their corkscrew before they turn onto their targets.
class_name MissilePod
extends WeaponBehavior

const LAUNCH_GAP := 0.09
## A bee on Pollen's buff (pass 48).
const RED_BEE := Color(1.0, 0.18, 0.12)
## The Pressure Cooker's glow (pass 53; hotter since pass 60, the glow is its only gauge) and the steam a vented hit lets
## out (pass 60).
const HEAT_COLOR := Color(1.0, 0.36, 0.08)
const HEAT_ENERGY := 1.4
const STEAM := Color(0.93, 0.92, 0.9)
## Pass 109: the look up (how fast it rises, how fast it settles), the share of the way up the first rocket waits for,
## the longest it waits, and the seconds it stays up after the volley's last rocket.
const LAUNCH_RAISE_RATE := 14.0
const LAUNCH_SETTLE_RATE := 5.0
const RAISED_SHARE := 0.8
const RAISE_WAIT := 0.2
const LAUNCH_SETTLE := 0.3
## How wide the volley fans round the tubes' line when the launcher looks up (a share of the level fan).
const UP_FAN := 0.35

var _familiar: Node3D
var _orbit := 0.0
var _aim_yaw := 0.0
var _recoil := 0.0
var _queue: Array = []
var _queue_t := 0.0
# the pod's own animation (pass 28): the tube cluster revolves a quarter turn per launch, the fired tube shows empty, and
# the rocket tips pop back one at a time while the pod reloads
var _cluster: Node3D
var _tips: Array = []
var _spin_target := 0.0
var _next_tube := 0
var _empty: Array = []
var _reload_t := 0.0
var _kick := 0.0
## Bursts fired (pass 48: the Tarantula Hawk comes every `hawk.every` of them), hawks sent.
var bursts := 0
var hawks_sent := 0
var _red_kind := -1
## The hive's door (pass 49, an "Entrance" marker in the Killer Bees' visual): the bees and the hawks come out of it.
## A pod without one launches from just over its middle, as before.
var _entrance: Node3D
## Pressure Cooker (pass 53, the stillness rule since pass 60): the pressure built, 0..1; the pod's materials that warm
## with it (duplicated once at setup) and the level they show; volleys fired at full pressure (the overpressure count);
## whether the last _process fired (the re-arm is then the pressure's interval); hits that vented some (tests)
var pressure := 0.0
## seconds after a hit during which the ramp neither climbs nor dumps (the knock's step is not a move)
const VENT_HOLD := 0.8
var _vent_hold := 0.0
var vents := 0
var _pressure_wired := false
var _heat_mats: Array = []
## each heated material's own emission before the ramp, {color, energy}: the bottom of its warming
var _heat_base: Array = []
var _heat_shown := -1.0
var _top_volleys := 0
var _fired := false
var _cluster_spins := true
## Pass 109: the launcher's look up (radians now, and where it is going), the seconds it holds there after a launch, and
## how long the next rocket has waited for it.
var _pitch := 0.0
var _pitch_want := 0.0
var _hold_up := 0.0
var _raise_wait := 0.0
## Double volleys the overpressure gave (tests).
var doubled := 0


func _on_setup() -> void:
	_familiar = visual.get_node_or_null("Familiar")
	_orbit = Dice.r.randf() * TAU
	_entrance = visual.get_node_or_null("Familiar/Body/Entrance") as Node3D
	_cluster = visual.get_node_or_null("Familiar/Body/Cluster")
	# pass 109: a launcher that looks up fires its tubes in turn and never turns the cluster
	_cluster_spins = bool(inst.params.get("cluster_spin", true)) and launch_pitch() <= 0.0
	_tips.clear()
	# every tip the cluster has, Tip1 up (pass 53: the pod's four, the Hellfire Battery's six)
	var k := 1
	while true:
		var tip := visual.get_node_or_null("Familiar/Body/Cluster/Tip%d" % k)
		if tip == null:
			break
		_tips.append(tip)
		k += 1
	# the rocket flies nose first (pass 53): the visual's Projectile node is turned so its capsule's long axis lies along
	# -Z, and that turn goes to the shot's kind (WeaponBehavior._load_visual hands it over since pass 53 too; this keeps
	# the pod right with a loader that registers mesh and scale alone, as the old one did)
	var proj := visual.get_node_or_null("Projectile")
	if proj is Node3D and projectile_kind >= 0 and game.projectiles.has_method("set_kind_basis"):
		game.projectiles.set_kind_basis(projectile_kind, (proj as Node3D).transform.basis.orthonormalized())
	_pressure_setup()
	_place(0.0)
	_keep_field()


# ---------------------------------------------------------------- Pressure Cooker (pass 53, stillness since pass 60)

## Wires the Pressure Cooker when the weapon carries it: at setup, and from refresh_marks when the pick is taken mid-run
## (a mutation never rebuilds the behaviour). The pressure starts from nothing at the pick; a hit on his health, and one
## his Energy Shield took, both vent it (the Invincibility bubble's absorb is neither: nothing touched him).
func _pressure_setup() -> void:
	if _pressure_wired or _pressure().is_empty():
		return
	_pressure_wired = true
	pressure = 0.0
	if player:
		if player.has_signal("hit") and not player.is_connected("hit", Callable(self, "note_hit")):
			player.connect("hit", Callable(self, "note_hit"))
		if player.has_signal("shield_hit") and not player.is_connected("shield_hit", Callable(self, "_on_shield_hit")):
			player.connect("shield_hit", Callable(self, "_on_shield_hit"))
	_heat_setup()


func _pressure() -> Dictionary:
	var pr = inst.params.get("pressure") if inst else null
	return pr if pr is Dictionary else {}


## The pressure's clock (pass 60): while the hero stands still (Player.is_still: no stick, next to no speed, on the
## ground, for half a second) it climbs by delta / `seconds`, to 1; the moment he moves it is all let out. For
## VENT_HOLD after a hit it does neither: the hit's knock carries him a step, which is not him moving (the review:
## a bite had dumped the pressure to 0 instead of venting half).
func _tick_pressure(delta: float) -> void:
	var pr := _pressure()
	if pr.is_empty():
		return
	if _vent_hold > 0.0:
		_vent_hold = maxf(_vent_hold - delta, 0.0)
		return
	if player != null and player.has_method("is_still") and bool(player.is_still()):
		pressure = minf(pressure + delta / maxf(float(pr.get("seconds", 15.0)), 0.01), 1.0)
	elif pressure > 0.0:
		pressure = 0.0


## The attack speed the pressure gives now: `start` with none built (0 without it), `max` at full pressure.
func pressure_bonus() -> float:
	var pr := _pressure()
	if pr.is_empty():
		return 0.0
	var start := float(pr.get("start", 0.0))
	return start + (float(pr.get("max", 2.0)) - start) * pressure


## Seconds between volleys: the sheet's cooldown over 1 + the pressure's bonus.
func fire_interval() -> float:
	return maxf(stat("cooldown", 1.0) / (1.0 + pressure_bonus()), 0.05)


## The hero was touched (his health, or his Energy Shield): `hit_vent` of the pressure escapes (half without it), a puff
## of steam off the pod when any did.
func note_hit() -> void:
	var pr := _pressure()
	if pr.is_empty() or pressure <= 0.0:
		return
	var vent: float = clampf(float(pr.get("hit_vent", 0.5)), 0.0, 1.0)
	if vent <= 0.0:
		return
	pressure = maxf(pressure * (1.0 - vent), 0.0)
	if pressure < 0.02:
		pressure = 0.0
	_vent_hold = VENT_HOLD
	vents += 1
	if game and game.has_method("fx_burst"):
		var at: Vector3 = (_familiar.global_position if _familiar else player.global_position) + Vector3(0, 0.25, 0)
		game.fx_burst(at, STEAM, 0.3)


func _on_shield_hit(_broke: bool) -> void:
	note_hit()


## The pod's materials that warm up (Garry: "the rocket launcher 3d object gradually looks hotter"): every
## StandardMaterial3D on the body, tubes, fins and plates under Familiar/Body, each duplicated once so the glow is this
## pod's alone; the warheads (Tip*) and a vent strip that already burns (Vent) are left as they are. Each keeps the
## emission it had as the bottom of its ramp (the companion glow of pass 53, WeaponBehavior.glow_companions, lights every
## dim material a little) and warms from there to HEAT_COLOR at HEAT_ENERGY. Emission stays on from the start, so no
## shader changes under it later.
func _heat_setup() -> void:
	_heat_mats.clear()
	_heat_base.clear()
	var body := visual.get_node_or_null("Familiar/Body")
	if body == null:
		return
	var seen := {}
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		# MeshMerge joins parts sharing a material under one "Merged_<first>" node
		var nm := str(m.name).trim_prefix("Merged_")
		if nm.begins_with("Tip") or nm.begins_with("Vent"):
			continue
		if m.material_override is StandardMaterial3D:
			m.material_override = _heat_copy(m.material_override, seen)
		elif m.mesh:
			for s in range(m.mesh.get_surface_count()):
				var sm = m.get_surface_override_material(s)
				if sm == null:
					sm = m.mesh.surface_get_material(s)
				if sm is StandardMaterial3D:
					m.set_surface_override_material(s, _heat_copy(sm, seen))
	_heat_shown = -1.0


## The heated copy of `src` (one per material, shared by the parts that shared it), its own emission remembered.
func _heat_copy(src: StandardMaterial3D, seen: Dictionary) -> StandardMaterial3D:
	var key := src.get_instance_id()
	if seen.has(key):
		return seen[key]
	var dup: StandardMaterial3D = src.duplicate()
	var base_col := Color(dup.emission.r, dup.emission.g, dup.emission.b) if dup.emission_enabled else HEAT_COLOR
	var base_energy: float = dup.emission_energy_multiplier if dup.emission_enabled else 0.0
	dup.emission_enabled = true
	dup.emission = base_col
	dup.emission_energy_multiplier = base_energy
	seen[key] = dup
	_heat_mats.append(dup)
	_heat_base.append({"color": base_col, "energy": base_energy})
	return dup


## The glow follows the pressure (written only when it moved: a material set every frame is a needless upload).
func _tick_heat() -> void:
	if _heat_mats.is_empty():
		return
	var r := pressure
	if absf(r - _heat_shown) < 0.02 and not (r >= 1.0 and _heat_shown < 1.0) and not (r <= 0.0 and _heat_shown > 0.0):
		return
	_heat_shown = r
	for k in range(_heat_mats.size()):
		var m: StandardMaterial3D = _heat_mats[k]
		var b: Dictionary = _heat_base[k]
		m.emission = (b["color"] as Color).lerp(HEAT_COLOR, r)
		m.emission_energy_multiplier = lerpf(float(b["energy"]), maxf(HEAT_ENERGY, float(b["energy"])), r)


## The glow the pod shows now, 0..1 (tests).
func heat_shown() -> float:
	return maxf(_heat_shown, 0.0)


func _process(delta: float) -> void:
	_fired = false
	super._process(delta)
	if _fired and not _pressure().is_empty():
		# the re-arm is the pressure's interval (WeaponBehavior re-arms with the sheet's cooldown alone)
		cooldown_left = fire_interval()


## Game calls this on every build change (a mutation taken does not rebuild the behaviour): Pollen's field comes with it,
## and the Pressure Cooker is wired the moment it is picked (pass 53).
func refresh_marks() -> void:
	super.refresh_marks()
	_keep_field()
	_pressure_setup()


## While this weapon carries Pollen, there is a flower field on the map (one, however many carry it; it goes by itself).
func _keep_field() -> void:
	if inst and game and inst.params.get("pollen") is Dictionary:
		FlowerField.ensure(game)


## Whether a picked flower's buff is on this weapon now.
func pollen_on() -> bool:
	return inst != null and Run.boost_left(FlowerField.buff_id(inst.def.id)) > 0.0


## The reload: while nothing is queued, every empty tube gets its tip back in turn, spread over most of the cooldown,
## each with a pop; the cluster eases to its next quarter turn and the launch kick settles.
func _tick_pod(delta: float) -> void:
	if _cluster == null:
		return
	_cluster.rotation.z = lerp_angle(_cluster.rotation.z, _spin_target, clampf(delta * 12.0, 0.0, 1.0))
	_kick = maxf(_kick - delta * 6.0, 0.0)
	# pass 109: the kick squashes the cluster along the tubes only (swelling it pushed the tubes through the box)
	_cluster.scale = Vector3(1.0, 1.0, 1.0 - 0.1 * _kick)
	if _queue.is_empty() and not _empty.is_empty():
		_reload_t -= delta
		if _reload_t <= 0.0:
			var gap: float = maxf(fire_interval() * 0.7 / float(maxi(_tips.size(), 1)), 0.12)
			_reload_t = gap
			var tip: Node3D = _empty.pop_front()
			if is_instance_valid(tip):
				tip.visible = true
				tip.scale = Vector3(0.2, 0.2, 0.2)
				var tw := create_tween()
				tw.tween_property(tip, "scale", Vector3(1.15, 1.15, 1.15), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(tip, "scale", Vector3.ONE, 0.07)
				_kick = maxf(_kick, 0.35)
				sfx("reload", _familiar.global_position if _familiar else Vector3.INF)


func _missile_param(key: String, default: float) -> float:
	var m = inst.params.get("missile", {})
	return float(m.get(key, default)) if m is Dictionary else default


func _familiar_param(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


## Pass 109: how far the launcher looks up for a volley, in radians (`params.familiar.launch_pitch` degrees; 0 = it fires
## level as before: the bees' hive).
func launch_pitch() -> float:
	return deg_to_rad(clampf(_familiar_param("launch_pitch", 0.0), 0.0, 85.0)) if inst else 0.0


## The look up eased each tick: up while a volley is queued or just fired (LAUNCH_SETTLE), back down after.
func _tick_pitch(delta: float) -> void:
	var lp := launch_pitch()
	if lp <= 0.0:
		_pitch = 0.0
		return
	_hold_up = maxf(_hold_up - delta, 0.0)
	_pitch_want = lp if (not _queue.is_empty() or _hold_up > 0.0) else 0.0
	if _pitch < _pitch_want:
		_pitch = minf(_pitch + LAUNCH_RAISE_RATE * delta * maxf(_pitch_want - _pitch, 0.15), _pitch_want)
	else:
		_pitch = lerpf(_pitch, _pitch_want, clampf(delta * LAUNCH_SETTLE_RATE, 0.0, 1.0))


## The launcher's look up now (radians; tests and the capture).
func pitch() -> float:
	return _pitch


## Whether the next rocket may leave: a launcher that looks up waits until it is RAISED_SHARE of the way up (RAISE_WAIT s
## at most, so a slow frame never holds a volley back).
func _raised(delta: float) -> bool:
	var lp := launch_pitch()
	if lp <= 0.0 or _pitch >= lp * RAISED_SHARE:
		_raise_wait = 0.0
		return true
	_raise_wait += delta
	return _raise_wait >= RAISE_WAIT


## Where a launcher that looks up points its tubes: the pod's own forward (its yaw and its pitch).
func launch_dir() -> Vector3:
	var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
	return (aim * cos(_pitch) + Vector3(0, sin(_pitch), 0)).normalized()


func _place(delta: float) -> void:
	if _familiar == null:
		return
	var r := _familiar_param("radius", 1.2)
	var h := _familiar_param("height", 1.6)
	var bob := _familiar_param("bob", 0.1)
	_orbit += delta * _familiar_param("speed", 0.9)
	var t := Run.rule_seconds()  # pass 77 (lane SIMRUN): real time in play, the run's clock in a run sim
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 2.7) * bob, sin(_orbit) * r)
	var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
	want -= aim * 0.12 * _recoil
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	_familiar.rotation.y = _aim_yaw
	# pass 109: a launcher that looks up dips back a little on each launch instead of nodding forward
	_familiar.rotation.x = (_pitch - 0.1 * _recoil) if launch_pitch() > 0.0 else -0.3 * _recoil
	_familiar.rotation.z = sin(t * 1.9) * 0.06


func _tick(delta: float) -> void:
	_tick_pitch(delta)
	if not _queue.is_empty():
		_queue_t -= delta
		if _queue_t <= 0.0 and _raised(delta):
			_queue_t = LAUNCH_GAP
			_launch_one()
			if launch_pitch() > 0.0:
				_hold_up = LAUNCH_SETTLE
	var enemies: EnemyManager = game.enemies
	# the pod faces what its seekers will go for (pass 48: the strong and the close for a priority weapon); seekers hunt
	# off the screen too (pass 54)
	var t := aim_index(player.global_position, stat("range", 12.0), "", true)
	var want: Vector3 = (enemies.pos[t] - player.global_position) if t >= 0 else player.forward()
	want.y = 0.0
	if want.length_squared() > 0.0001:
		_aim_yaw = lerp_angle(_aim_yaw, atan2(-want.x, -want.z), clampf(delta * 8.0, 0.0, 1.0))
	_recoil = maxf(_recoil - delta * 8.0, 0.0)
	_tick_pressure(delta)
	_tick_heat()
	_tick_pod(delta)
	_place(delta)


func _fire() -> bool:
	# homing: it fires at prey off the screen too (pass 54)
	if aim_index(player.global_position, stat("range", 12.0), "", true) < 0:
		return false
	var n: int = maxi(stat_int("amount", 1), 1)
	for k in range(n):
		_queue.append(k)
	# the Hellfire Battery's overpressure (pass 53): at the top of the ramp every `every`th volley is a double one
	var op = inst.params.get("overpressure")
	if op is Dictionary and pressure >= 1.0:
		_top_volleys += 1
		if _top_volleys % maxi(int((op as Dictionary).get("every", 4)), 1) == 0:
			for k in range(n):
				_queue.append(k)
			doubled += 1
	_queue_t = 0.0
	_fired = true
	bursts += 1
	var hk = inst.params.get("hawk")
	if hk is Dictionary:
		var every: int = maxi(int((hk as Dictionary).get("every", 4)), 1)
		if bursts % every == 0 or pollen_on():
			_send_hawk(hk)
	return true


## Where a shot leaves the pod: the hive's door when it has one (pass 49), else just over the pod's middle.
func _launch_point() -> Vector3:
	if _entrance and _entrance.is_inside_tree():
		return _entrance.global_position
	return (_familiar.global_position if _familiar else player.aim_origin(player.forward())) + Vector3(0, 0.2, 0)


## Pass 109: the open end of tube `n` (its Tip, Tip1 up in turn, a little past it along the tubes); a pod without tips
## (the Missile Massacre's) fires from the front of its middle, Vector3.INF without a pod.
func _muzzle_of(n: int) -> Vector3:
	if _tips.is_empty():
		if _familiar and _familiar.is_inside_tree():
			return _familiar.global_position + launch_dir() * 0.45
		return Vector3.INF
	var tip: Node3D = _tips[n % _tips.size()]
	if not is_instance_valid(tip) or not tip.is_inside_tree():
		return Vector3.INF
	return tip.global_position + launch_dir() * 0.08


## A Tarantula Hawk from the pod at the strongest creature near that no hawk holds yet (TarantulaHawk.pick).
func _send_hawk(cfg: Dictionary) -> void:
	var from := _launch_point()
	var prey := TarantulaHawk.pick(game.enemies, player.global_position, stat("range", 12.0), TarantulaHawk.held_serials(game))
	if prey < 0:
		return
	if TarantulaHawk.launch(game, inst, from, prey, cfg):
		hawks_sent += 1


## The bees' kind while Pollen's buff lasts: the same mesh, red (made the first time).
func _red() -> int:
	if _red_kind < 0:
		var pm: ProjectileManager = game.projectiles
		if projectile_kind < 0 or projectile_kind >= pm.kinds.size():
			return projectile_kind
		var kd: Dictionary = pm.kinds[projectile_kind]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = RED_BEE
		mat.emission_enabled = true
		mat.emission = RED_BEE
		mat.emission_energy_multiplier = 0.9
		_red_kind = pm.register_kind((kd["mm"] as MultiMesh).mesh, mat, float(kd["scale"]) / ProjectileManager.CHUNK, false, kd.get("basis", Basis()))
	return _red_kind


func _launch_one() -> void:
	var k: int = _queue.pop_front()
	var from := _launch_point()
	var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
	# a fan: alternate sides of the aim, wider for the later ones, all tilted up; the corkscrew does the rest
	var side: float = (1.0 if k % 2 == 0 else -1.0) * (0.3 + 0.22 * float(k / 2))
	var dir: Vector3 = (aim + aim.rotated(Vector3.UP, PI * 0.5) * side + Vector3(0, 0.9, 0)).normalized()
	# pass 109: a launcher that looks up fires out of the open end of the tube whose turn it is, along its tubes (fanned a
	# little round them), so the rockets visibly leave the muzzle going up
	if launch_pitch() > 0.0:
		var muzzle := _muzzle_of(_next_tube)
		if muzzle != Vector3.INF:
			from = muzzle
		dir = (launch_dir() + aim.rotated(Vector3.UP, PI * 0.5) * side * UP_FAN).normalized()
	var red := pollen_on()
	var params := {
		"wander": _missile_param("wander", 0.5),
		"turn": _missile_param("turn", 6.0) * Run.player_sheet.get_stat("homing_turn", 1.0),
		"spiral": _missile_param("spiral", 7.0),
		"life": _missile_param("life", 4.5),
		"trail": 4 if red else int(_missile_param("trail", 1.0)),
		"rise": _missile_param("rise", 0.3),
	}
	# pass 81 (lane POLISH): the bees' trail look and colour (ProjectileManager.BEE_LOOKS; "" = the default look)
	var m = inst.params.get("missile", {})
	if m is Dictionary:
		params["trail_style"] = str((m as Dictionary).get("trail_style", ""))
		params["trail_color"] = str((m as Dictionary).get("trail_color", ""))
	game.projectiles.launch_missile(_red() if red else projectile_kind, from, dir, stat("speed", 13.0), stat("damage", 12.0), stat("area", 1.5), stat("range", 12.0), inst, params, stat("knockback", 3.0))
	_recoil = 1.0
	# the tube that fired shows empty and the cluster turns the next one up
	if not _tips.is_empty():
		var tip: Node3D = _tips[_next_tube % _tips.size()]
		_next_tube += 1
		if tip.visible:
			tip.visible = false
			_empty.append(tip)
		if _cluster_spins:
			_spin_target += PI * 0.5
		_kick = 1.0
		_reload_t = 0.35
	muzzle_flash(from, aim)
	sfx("fire", from)
